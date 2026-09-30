----------------------------------------------------------------------------------------
-- RefineUI MouseoverCasting
-- Description: Casts with action bar keybinds on the hovered Blizzard unit frame.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local MouseoverCasting = RefineUI:RegisterModule("MouseoverCasting", "MouseoverCasting")

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local C_AddOns = C_AddOns
local C_ClickBindings = C_ClickBindings
local InCombatLockdown = InCombatLockdown
local hooksecurefunc = hooksecurefunc

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local REBUILD_DEBOUNCE_KEY = "MouseoverCasting:Rebuild"
local MACRO_REBUILD_FOLLOWUP_KEY = "MouseoverCasting:Rebuild:MacroFollowup"
local EVENT_PREFIX = "MouseoverCasting:Event"

local MODULE_EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "ACTIONBAR_SLOT_CHANGED",
    "UPDATE_BINDINGS",
    "UPDATE_MACROS",
    "SPELLS_CHANGED",
    "ACTIONBAR_PAGE_CHANGED",
    "UPDATE_BONUS_ACTIONBAR",
    "UPDATE_OVERRIDE_ACTIONBAR",
    "PLAYER_REGEN_ENABLED",
    "ADDON_LOADED",
}

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
function MouseoverCasting:RequestRebuild()
    self.pendingRebuild = true
    if InCombatLockdown() then
        return
    end
    RefineUI:Debounce(REBUILD_DEBOUNCE_KEY, 0.05, self.flushRebuildCallback)
end

function MouseoverCasting:FlushRebuild()
    if InCombatLockdown() then
        self.pendingRebuild = true
        return
    end

    self.pendingRebuild = false

    if self:RefreshConflictState() then
        self:DisableSecureSystem()
    else
        self:RebuildActiveSpecBindings()
        self:ApplySecureSystem()
    end
    self:RefreshSpellbookPanel()
end

----------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------
function MouseoverCasting:HandleEvent(event, ...)
    if event == "PLAYER_REGEN_ENABLED" then
        if self.pendingFrameRegistration then
            self:FlushPendingFrameRegistrations()
        end
        if self.pendingRebuild then
            self:FlushRebuild()
        end
        return
    end

    if event == "ADDON_LOADED" then
        if ... == "Blizzard_PlayerSpells" then
            self:AttachToPlayerSpellsFrame()
        end
        return
    end

    self:RequestRebuild()
    if event == "UPDATE_MACROS" then
        RefineUI:Debounce(MACRO_REBUILD_FOLLOWUP_KEY, 0.25, self.requestRebuildCallback)
    end
end

function MouseoverCasting:RegisterModuleEvents()
    local function OnEvent(event, ...)
        self:HandleEvent(event, ...)
    end
    RefineUI:OnEvents(MODULE_EVENTS, OnEvent, EVENT_PREFIX)
    RefineUI:OnUnitEvents("player", { "PLAYER_SPECIALIZATION_CHANGED" }, OnEvent, EVENT_PREFIX)

    -- Blizzard click bindings change only through these calls; no event reports it.
    hooksecurefunc(C_ClickBindings, "SetProfileByInfo", self.requestRebuildCallback)
    hooksecurefunc(C_ClickBindings, "ResetCurrentProfile", self.requestRebuildCallback)
end

----------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------
function MouseoverCasting:OnEnable()
    -- Clique owns unit frame bindings and cannot unload without a reload. The standalone
    -- Refined Mouseover Casting addon runs this same feature, so it takes over when loaded.
    if C_AddOns.IsAddOnLoaded("Clique") or C_AddOns.IsAddOnLoaded("RefinedMouseoverCasting") then
        return
    end

    self.pendingRebuild = false
    self.pendingFrameRegistration = false
    self.flushRebuildCallback = function()
        self:FlushRebuild()
    end
    self.requestRebuildCallback = function()
        self:RequestRebuild()
    end

    self:InitializeData()
    self:InitializeSecureSystem()
    self:RegisterModuleEvents()

    self:DiscoverSupportedFrames()
    self:AttachToPlayerSpellsFrame()
    self:RequestRebuild()
end
