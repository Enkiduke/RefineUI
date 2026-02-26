----------------------------------------------------------------------------------------
-- EncounterAchievements Module
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local EncounterAchievements = RefineUI:RegisterModule("EncounterAchievements")

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local _G = _G
local select = select
local tostring = tostring
local type = type

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
EncounterAchievements.KEY_PREFIX = "EncounterAchievements"
EncounterAchievements.BLIZZARD_ENCOUNTER_ADDON = "Blizzard_EncounterJournal"
EncounterAchievements.BLIZZARD_ACHIEVEMENT_ADDON = "Blizzard_AchievementUI"

----------------------------------------------------------------------------------------
-- Key Helpers
----------------------------------------------------------------------------------------
function EncounterAchievements:BuildKey(...)
    local key = self.KEY_PREFIX
    for index = 1, select("#", ...) do
        key = key .. ":" .. tostring(select(index, ...))
    end
    return key
end

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
function EncounterAchievements:InitializeState()
    self.currentInstanceID = nil
    self.customTabActive = false
    self.pendingAchievementUILoadFromTab = false
    self.pendingRowRefreshInstanceID = nil
end

function EncounterAchievements:GetCurrentJournalInstanceID()
    local journal = _G.EncounterJournal
    return journal and journal.instanceID or nil
end

----------------------------------------------------------------------------------------
-- Runtime Event Handling
----------------------------------------------------------------------------------------
function EncounterAchievements:RegisterRuntimeEvents()
    if self.runtimeEventsRegistered then
        return
    end

    RefineUI:RegisterEventCallback("ADDON_LOADED", function(_, addonName)
        if RefineUI:IsSecretValue(addonName) then
            return
        end
        if type(addonName) ~= "string" then
            return
        end

        if addonName == self.BLIZZARD_ENCOUNTER_ADDON then
            self:InitializeEncounterJournalIntegration()
        elseif addonName == self.BLIZZARD_ACHIEVEMENT_ADDON then
            self:OnAchievementUILoaded()
        end
    end, self:BuildKey("Runtime", "ADDON_LOADED"))

    RefineUI:RegisterEventCallback("EJ_DIFFICULTY_UPDATE", function()
        if self.customTabActive then
            self:RefreshCustomTabContent()
        end
    end, self:BuildKey("Runtime", "EJ_DIFFICULTY_UPDATE"))

    self.runtimeEventsRegistered = true
end

----------------------------------------------------------------------------------------
-- Blizzard Hooks
----------------------------------------------------------------------------------------
function EncounterAchievements:InstallEncounterHooks()
    if self.hooksInstalled then
        return
    end

    RefineUI:HookOnce(self:BuildKey("Hook", "EncounterJournal_DisplayInstance"), "EncounterJournal_DisplayInstance", function(instanceID)
        self:OnEncounterInstanceChanged(instanceID)
    end)

    RefineUI:HookOnce(self:BuildKey("Hook", "EncounterJournal_DisplayEncounter"), "EncounterJournal_DisplayEncounter", function()
        self:OnEncounterInstanceChanged(self:GetCurrentJournalInstanceID())
    end)

    RefineUI:HookOnce(self:BuildKey("Hook", "EncounterJournal_SetTab"), "EncounterJournal_SetTab", function()
        if self.customTabActive then
            self:DeactivateCustomTab()
        end
    end)

    local journal = _G.EncounterJournal
    if journal and journal.HookScript then
        RefineUI:HookScriptOnce(self:BuildKey("HookScript", "EncounterJournal", "OnHide"), journal, "OnHide", function()
            self:OnEncounterJournalHidden()
        end)
    end

    local encounterFrame = journal and journal.encounter
    if encounterFrame and encounterFrame.HookScript then
        RefineUI:HookScriptOnce(self:BuildKey("HookScript", "EncounterFrame", "OnShow"), encounterFrame, "OnShow", function()
            self:UpdateCustomTabAvailability()
            if self.customTabActive then
                self:RefreshCustomTabContent()
            end
        end)

        RefineUI:HookScriptOnce(self:BuildKey("HookScript", "EncounterFrame", "OnHide"), encounterFrame, "OnHide", function()
            self:DeactivateCustomTab()
        end)
    end

    if not self.tabSetCallbackRegistered and _G.EventRegistry and type(_G.EventRegistry.RegisterCallback) == "function" then
        _G.EventRegistry:RegisterCallback("EncounterJournal.TabSet", function(_, journalFrame, tabID)
            if journalFrame ~= _G.EncounterJournal then
                return
            end
            self:OnEncounterJournalTabSet(tabID)
        end, self)
        self.tabSetCallbackRegistered = true
    end

    self.hooksInstalled = true
end

----------------------------------------------------------------------------------------
-- Hook Callbacks
----------------------------------------------------------------------------------------
function EncounterAchievements:OnEncounterJournalTabSet(tabID)
    if self.customTabActive and not self:IsSupportedContentTab(tabID) then
        self:DeactivateCustomTab()
    end
    self:UpdateCustomTabAvailability()
end

function EncounterAchievements:OnEncounterJournalHidden()
    self.currentInstanceID = nil
    self.pendingRowRefreshInstanceID = nil
    if self.CancelPendingInstanceRowBuilds then
        self:CancelPendingInstanceRowBuilds()
    end
    self:DeactivateCustomTab()
end

function EncounterAchievements:OnEncounterInstanceChanged(instanceID)
    self.currentInstanceID = instanceID
    self:UpdateCustomTabAvailability()

    if not self.customTabActive then
        self.pendingRowRefreshInstanceID = nil
        if self.CancelPendingInstanceRowBuilds then
            self:CancelPendingInstanceRowBuilds()
        end
        return
    end

    self:RefreshCustomTabContent()
end

----------------------------------------------------------------------------------------
-- Integration Bootstrap
----------------------------------------------------------------------------------------
function EncounterAchievements:InitializeEncounterJournalIntegration()
    if self.encounterJournalInitialized then
        return
    end

    if type(_G.EncounterJournal) ~= "table" then
        return
    end

    self:InitializeData()
    self:EnsureUI()
    self:InstallEncounterHooks()
    self:UpdateCustomTabAvailability()

    self.encounterJournalInitialized = true
end

----------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------
function EncounterAchievements:OnEnable()
    self:InitializeState()
    self:RegisterRuntimeEvents()

    if type(_G.EncounterJournal) == "table" then
        self:InitializeEncounterJournalIntegration()
    end
end
