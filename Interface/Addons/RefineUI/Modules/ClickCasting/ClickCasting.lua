----------------------------------------------------------------------------------------
-- RefineUI ClickCasting
-- Description: Frame-scoped key-based click casting for Blizzard unit frames.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local ClickCasting = RefineUI:RegisterModule("ClickCasting")

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local _G = _G
local InCombatLockdown = InCombatLockdown
local type = type
local issecretvalue = _G.issecretvalue

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local REBUILD_DEBOUNCE_KEY = "ClickCasting:Rebuild"
local MACRO_REBUILD_FOLLOWUP_KEY = "ClickCasting:Rebuild:MacroFollowup"
local EVENT_PREFIX = "ClickCasting:Event"

local REBUILD_EVENTS = {
    PLAYER_LOGIN = true,
    PLAYER_ENTERING_WORLD = true,
    PLAYER_SPECIALIZATION_CHANGED = true,
    ACTIONBAR_SLOT_CHANGED = true,
    UPDATE_BINDINGS = true,
    UPDATE_MACROS = true,
    SPELLS_CHANGED = true,
    ACTIONBAR_PAGE_CHANGED = true,
    UPDATE_BONUS_ACTIONBAR = true,
    UPDATE_OVERRIDE_ACTIONBAR = true,
}

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
function ClickCasting:IsModuleEnabled()
    local cfg = self:GetConfig()
    return cfg and cfg.Enable ~= false
end

function ClickCasting:RequestRebuild(reason)
    if not self:IsModuleEnabled() then
        return
    end

    if self.IsCliqueLoaded and self:IsCliqueLoaded() then
        self.pendingRebuild = false
        self.pendingSecureApply = false
        self:RefreshConflictState()
        return
    end

    self.pendingRebuild = true
    self.pendingSecureApply = true

    RefineUI:Debounce(REBUILD_DEBOUNCE_KEY, 0.05, function()
        self:FlushRebuild()
    end)
end

function ClickCasting:FlushRebuild()
    if not self:IsModuleEnabled() then
        self.pendingRebuild = false
        self.pendingSecureApply = false
        self:DisableSecureSystem("disabled")
        self:RefreshSpellbookPanel()
        return
    end

    if InCombatLockdown() then
        self.pendingRebuild = true
        self.pendingSecureApply = true
        return
    end

    self.pendingRebuild = false

    local hasConflict = self:RefreshConflictState()
    if hasConflict then
        self.pendingSecureApply = false
        self:DisableSecureSystem("conflict")
        self:RefreshSpellbookPanel()
        return
    end

    self:RebuildActiveSpecBindings()
    self:ApplySecureSystem()
    self.pendingSecureApply = false
    self:RefreshSpellbookPanel()
end

----------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------
function ClickCasting:HandleEvent(event, ...)
    if event == "PLAYER_REGEN_ENABLED" then
        if self.pendingRebuild or self.pendingSecureApply or self.pendingFrameRegistration then
            self:DiscoverSupportedFrames()
            self:FlushRebuild()
        end
        return
    end

    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        local unit = ...
        if unit and ((issecretvalue and issecretvalue(unit)) or type(unit) ~= "string" or unit ~= "player") then
            return
        end
    elseif event == "ADDON_LOADED" then
        local addonName = ...
        if issecretvalue and issecretvalue(addonName) then
            return
        end
        if self.HandleAddonLoaded then
            self:HandleAddonLoaded(addonName)
        end
        if addonName == "Clique" then
            self:RefreshConflictState()
            return
        end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" or event == "PLAYER_ENTERING_WORLD" then
        self:DiscoverSupportedFrames()
    end

    if REBUILD_EVENTS[event] then
        self:RequestRebuild(event)
        if event == "UPDATE_MACROS" then
            RefineUI:Debounce(MACRO_REBUILD_FOLLOWUP_KEY, 0.25, function()
                self:RequestRebuild("UPDATE_MACROS:followup")
            end)
        end
    elseif event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "Blizzard_MacroUI" or addonName == "Blizzard_PlayerSpells" then
            self:RequestRebuild(event .. ":" .. addonName)
        end
    end
end

function ClickCasting:RegisterModuleEvents()
    local events = {
        "PLAYER_LOGIN",
        "PLAYER_ENTERING_WORLD",
        "PLAYER_SPECIALIZATION_CHANGED",
        "ACTIONBAR_SLOT_CHANGED",
        "UPDATE_BINDINGS",
        "UPDATE_MACROS",
        "SPELLS_CHANGED",
        "ACTIONBAR_PAGE_CHANGED",
        "UPDATE_BONUS_ACTIONBAR",
        "UPDATE_OVERRIDE_ACTIONBAR",
        "PLAYER_REGEN_ENABLED",
        "GROUP_ROSTER_UPDATE",
        "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
        "ADDON_LOADED",
    }

    RefineUI:OnEvents(events, function(event, ...)
        self:HandleEvent(event, ...)
    end, EVENT_PREFIX)
end

----------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------
function ClickCasting:OnEnable()
    if not self:IsModuleEnabled() then
        return
    end

    self.pendingRebuild = false
    self.pendingSecureApply = false
    self.pendingFrameRegistration = false
    self.isSuspended = false
    self.suspendReason = nil

    self:InitializeData()
    self:InitializeSecureSystem()
    self:InitializeFrameDiscovery()
    self:InitializeSpellbookUI()
    self:RegisterModuleEvents()
    if self.SetConflictWatchEnabled then
        self:SetConflictWatchEnabled(false)
    end

    self:DiscoverSupportedFrames()
    self:RequestRebuild("enable")
end
