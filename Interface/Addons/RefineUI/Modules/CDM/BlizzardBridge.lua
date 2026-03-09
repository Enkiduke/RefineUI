----------------------------------------------------------------------------------------
-- CDM Component: BlizzardBridge
-- Description: Centralized gating and deferral for Blizzard-owned Cooldown Viewer mutations.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local CDM = RefineUI:GetModule("CDM")
if not CDM then
    return
end

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config
local Media = RefineUI.Media
local Colors = RefineUI.Colors
local Locale = RefineUI.Locale

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local type = type
local pairs = pairs
local pcall = pcall
local InCombatLockdown = InCombatLockdown
local C_AddOns = C_AddOns

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local BLIZZARD_ADDON_NAME = "Blizzard_CooldownViewer"

CDM.BLIZZARD_MUTATION_KIND = CDM.BLIZZARD_MUTATION_KIND or {
    SETTINGS = "settings",
    VIEWER_VISIBILITY = "viewer_visibility",
    VIEWER_VISUALS = "viewer_visuals",
    LAYOUT_SYNC = "layout_sync",
}

local VALID_MUTATION_KIND = {
    [CDM.BLIZZARD_MUTATION_KIND.SETTINGS] = true,
    [CDM.BLIZZARD_MUTATION_KIND.VIEWER_VISIBILITY] = true,
    [CDM.BLIZZARD_MUTATION_KIND.VIEWER_VISUALS] = true,
    [CDM.BLIZZARD_MUTATION_KIND.LAYOUT_SYNC] = true,
}

local pendingMutationByKey = {}
local mutationOrder = {}

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function IsValidMutationKind(kind)
    return type(kind) == "string" and VALID_MUTATION_KIND[kind] == true
end


local function IsCooldownViewerLoaded()
    local settingsFrame = CDM.GetCooldownViewerSettingsFrame and CDM:GetCooldownViewerSettingsFrame()
    if settingsFrame then
        return true
    end

    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
        local ok, isLoaded = pcall(C_AddOns.IsAddOnLoaded, BLIZZARD_ADDON_NAME)
        if ok and isLoaded then
            return true
        end
    end

    if type(_G.IsAddOnLoaded) == "function" then
        local ok, isLoaded = pcall(_G.IsAddOnLoaded, BLIZZARD_ADDON_NAME)
        if ok and isLoaded then
            return true
        end
    end

    return false
end


local function RemovePendingMutation(key)
    if pendingMutationByKey[key] == nil then
        return
    end

    pendingMutationByKey[key] = nil
    for i = #mutationOrder, 1, -1 do
        if mutationOrder[i] == key then
            table.remove(mutationOrder, i)
            break
        end
    end
end


local function QueuePendingMutation(key, kind, fn)
    if pendingMutationByKey[key] == nil then
        mutationOrder[#mutationOrder + 1] = key
    end

    pendingMutationByKey[key] = {
        kind = kind,
        fn = fn,
    }
end


local function ExecuteMutation(key, entry)
    if type(entry) ~= "table" or type(entry.fn) ~= "function" then
        RemovePendingMutation(key)
        return false
    end

    local ok, executed = pcall(entry.fn)
    if not ok then
        RemovePendingMutation(key)
        return false
    end

    if executed == false then
        return false
    end

    RemovePendingMutation(key)
    return true
end


----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function CDM:IsBlizzardMutationAllowed(kind)
    if not IsValidMutationKind(kind) then
        return false
    end

    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return false
    end

    return IsCooldownViewerLoaded()
end


function CDM:RunOrDeferBlizzardMutation(key, kind, fn)
    if type(key) ~= "string" or key == "" then
        return false, "invalid_key"
    end
    if not IsValidMutationKind(kind) then
        return false, "invalid_kind"
    end
    if type(fn) ~= "function" then
        return false, "invalid_callback"
    end

    QueuePendingMutation(key, kind, fn)

    if not self:IsBlizzardMutationAllowed(kind) then
        return false, "deferred"
    end

    local executed = ExecuteMutation(key, pendingMutationByKey[key])
    if executed then
        return true, "executed"
    end

    return false, "deferred"
end


function CDM:MarkBlizzardMutationDirty(key, kind)
    if type(key) ~= "string" or key == "" then
        return false
    end
    if not IsValidMutationKind(kind) then
        return false
    end

    local entry = pendingMutationByKey[key]
    if type(entry) ~= "table" or type(entry.fn) ~= "function" then
        return false
    end

    entry.kind = kind
    if self:IsBlizzardMutationAllowed(kind) then
        return ExecuteMutation(key, entry)
    end

    return false
end


function CDM:FlushDeferredBlizzardMutations(kind)
    if kind ~= nil and not IsValidMutationKind(kind) then
        return 0
    end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return 0
    end
    if not IsCooldownViewerLoaded() then
        return 0
    end

    local flushed = 0
    local orderSnapshot = {}
    for i = 1, #mutationOrder do
        orderSnapshot[i] = mutationOrder[i]
    end

    for i = 1, #orderSnapshot do
        local key = orderSnapshot[i]
        local entry = pendingMutationByKey[key]
        if entry and (kind == nil or entry.kind == kind) then
            if ExecuteMutation(key, entry) then
                flushed = flushed + 1
            end
        end
    end

    return flushed
end


function CDM:GetBlizzardLayoutSyncContext()
    if not self:IsBlizzardMutationAllowed(self.BLIZZARD_MUTATION_KIND.LAYOUT_SYNC) then
        return nil, nil, nil
    end

    local provider, settingsFrame = self:GetCooldownViewerDataProvider()
    if not provider or not settingsFrame or not settingsFrame:IsShown() then
        return nil, nil, nil
    end

    local layoutManager = nil
    if type(settingsFrame.GetLayoutManager) == "function" then
        layoutManager = settingsFrame:GetLayoutManager()
    elseif type(provider.GetLayoutManager) == "function" then
        layoutManager = provider:GetLayoutManager()
    end

    return provider, settingsFrame, layoutManager
end


function CDM:InitializeBlizzardMutationBridge()
    if self.blizzardMutationBridgeInitialized then
        return
    end

    RefineUI:RegisterEventCallback("PLAYER_REGEN_ENABLED", function()
        CDM:FlushDeferredBlizzardMutations()
    end, "CDM:Bridge:RegenEnabled")

    RefineUI:RegisterEventCallback("ADDON_LOADED", function(_event, addonName)
        if addonName == BLIZZARD_ADDON_NAME then
            CDM:FlushDeferredBlizzardMutations()
        end
    end, "CDM:Bridge:AddonLoaded")

    local eventRegistry = _G.EventRegistry
    if eventRegistry and type(eventRegistry.RegisterCallback) == "function" then
        eventRegistry:RegisterCallback("CooldownViewerSettings.OnShow", function()
            CDM:FlushDeferredBlizzardMutations()
        end, self)
    end

    self.blizzardMutationBridgeInitialized = true
end
