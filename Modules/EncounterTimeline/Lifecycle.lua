----------------------------------------------------------------------------------------
-- EncounterTimeline Component: Lifecycle
-- Description: Runtime event wiring and module enable/ready flow
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local EncounterTimeline = RefineUI:GetModule("EncounterTimeline")
if not EncounterTimeline then
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
local issecretvalue = _G.issecretvalue
local canaccessvalue = _G.canaccessvalue

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local RUNTIME_EVENT_KEY_PREFIX = EncounterTimeline:BuildKey("Runtime")
local RUNTIME_EVENTS = {
    "ADDON_LOADED",
    "ENCOUNTER_TIMELINE_VIEW_ACTIVATED",
    "ENCOUNTER_TIMELINE_VIEW_DEACTIVATED",
    "ENCOUNTER_TIMELINE_EVENT_ADDED",
    "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED",
    "ENCOUNTER_TIMELINE_EVENT_TRACK_CHANGED",
    "ENCOUNTER_TIMELINE_EVENT_BLOCK_STATE_CHANGED",
    "ENCOUNTER_TIMELINE_LAYOUT_UPDATED",
    "ENCOUNTER_TIMELINE_STATE_UPDATED",
    "ENCOUNTER_TIMELINE_EVENT_HIGHLIGHT",
    "ENCOUNTER_TIMELINE_EVENT_REMOVED",
    "READY_CHECK",
    "READY_CHECK_FINISHED",
    "START_PLAYER_COUNTDOWN",
    "CANCEL_PLAYER_COUNTDOWN",
}

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local function IsTimelineAddonLoaded()
    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
        if C_AddOns.IsAddOnLoaded(EncounterTimeline.BLIZZARD_ADDON_NAME) then
            return true
        end
    end

    return EncounterTimeline:IsTimelineVisible()
end

local function IsUnreadableValue(value)
    if value == nil then
        return false
    end
    if issecretvalue and issecretvalue(value) then
        return true
    end
    if canaccessvalue and not canaccessvalue(value) then
        return true
    end
    if RefineUI.IsSecretValue and RefineUI:IsSecretValue(value) then
        return true
    end
    return false
end

----------------------------------------------------------------------------------------
-- Runtime Wiring
----------------------------------------------------------------------------------------
function EncounterTimeline:RegisterRuntimeEvents()
    if self.runtimeEventsRegistered then
        return
    end

    RefineUI:OnEvents(RUNTIME_EVENTS, function(event, ...)
        EncounterTimeline:OnRuntimeEvent(event, ...)
    end, RUNTIME_EVENT_KEY_PREFIX)

    self.runtimeEventsRegistered = true
end

function EncounterTimeline:OnEncounterTimelineReady()
    if not IsTimelineAddonLoaded() then
        return
    end

    local config = self:GetConfig()
    if config.SkinEnabled == true or config.BigIconEnable == true then
        self:InstallSkinHooks()
    end

    if config.SkinEnabled == true then
        self:RefreshTimelineSkins(true)
    end

    self:RegisterEncounterTimelineEditModeSettings()
    self:RefreshBigIconVisualState()
    self:UpdateBigIconSchedulerState()
end

function EncounterTimeline:OnRuntimeEvent(event, ...)
    local function UpdateEventLatest(eventID)
        if EncounterTimeline:IsValidEventID(eventID) then
            EncounterTimeline.audioLatestEventID = eventID
        end
    end

    local function HandleSkinAndBigIconRefresh(forceSkins)
        if forceSkins and EncounterTimeline:GetConfig().SkinEnabled == true then
            EncounterTimeline:RefreshTimelineSkins(true)
        end
        EncounterTimeline:RefreshBigIconVisualState()
        EncounterTimeline:UpdateBigIconSchedulerState()
    end

    if event == "ADDON_LOADED" then
        local addonName = ...
        if IsUnreadableValue(addonName) then
            return
        end
        if type(addonName) == "string" and addonName == self.BLIZZARD_ADDON_NAME then
            self:OnEncounterTimelineReady()
        end
        return
    end

    if not self:IsEnabled() then
        return
    end

    if event == "ENCOUNTER_TIMELINE_VIEW_ACTIVATED" then
        self:OnEncounterTimelineReady()
        return
    elseif event == "ENCOUNTER_TIMELINE_VIEW_DEACTIVATED" then
        self:CancelReadyCheckTimelineEvent()
        self:CancelPullTimelineEvent()
        self:ResetRuntimeState()
        self:HideBigIcon()
        self:UpdateBigIconSchedulerState()
        return
    elseif event == "ENCOUNTER_TIMELINE_EVENT_ADDED" then
        local eventInfo = ...
        if not IsUnreadableValue(eventInfo) and type(eventInfo) == "table" then
            local eventID = eventInfo.id
            if self:IsValidEventID(eventID) then
                self:UpdateEventMetadataFromInfo(eventID, eventInfo)
                UpdateEventLatest(eventID)
            end
        end
        HandleSkinAndBigIconRefresh(true)
        return
    elseif event == "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED" or event == "ENCOUNTER_TIMELINE_EVENT_TRACK_CHANGED" or event == "ENCOUNTER_TIMELINE_EVENT_BLOCK_STATE_CHANGED" then
        local eventID = ...
        if not IsUnreadableValue(eventID) then
            UpdateEventLatest(eventID)
        end
        HandleSkinAndBigIconRefresh(true)
        return
    elseif event == "ENCOUNTER_TIMELINE_LAYOUT_UPDATED" or event == "ENCOUNTER_TIMELINE_STATE_UPDATED" then
        HandleSkinAndBigIconRefresh(true)
        return
    elseif event == "ENCOUNTER_TIMELINE_EVENT_HIGHLIGHT" then
        local eventID = ...
        if not IsUnreadableValue(eventID) then
            UpdateEventLatest(eventID)
        end
        HandleSkinAndBigIconRefresh(false)
        return
    elseif event == "ENCOUNTER_TIMELINE_EVENT_REMOVED" then
        local eventID = ...
        if self:IsValidEventID(eventID) then
            self:ClearEventRuntimeState(eventID)
            if self.audioLatestEventID == eventID then
                self.audioLatestEventID = nil
            end
        end
        HandleSkinAndBigIconRefresh(false)
        return
    elseif event == "READY_CHECK" then
        if not self:CanProcessVisibleTimelineEvents() then
            self:CancelReadyCheckTimelineEvent()
            return
        end
        local _initiatorName, readyCheckTimeLeft = ...
        self:HandleReadyCheckTimelineEvent(readyCheckTimeLeft)
        HandleSkinAndBigIconRefresh(false)
    elseif event == "READY_CHECK_FINISHED" then
        self:HandleReadyCheckFinishedTimelineEvent()
        HandleSkinAndBigIconRefresh(false)
    elseif event == "START_PLAYER_COUNTDOWN" then
        if not self:CanProcessVisibleTimelineEvents() then
            self:CancelPullTimelineEvent()
            return
        end
        local _initiatedBy, timeRemaining = ...
        self:HandlePullStartTimelineEvent(timeRemaining)
        HandleSkinAndBigIconRefresh(false)
    elseif event == "CANCEL_PLAYER_COUNTDOWN" then
        self:HandlePullCancelTimelineEvent()
        HandleSkinAndBigIconRefresh(false)
    end
end

----------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------
function EncounterTimeline:OnEnable()
    self:InitializeState()

    if not self:IsEnabled() then
        self:CancelReadyCheckTimelineEvent()
        self:CancelPullTimelineEvent()
        self:HideBigIcon()
        self:ResetRuntimeState()
        self:UpdateBigIconSchedulerState()
        return
    end

    self:RegisterRuntimeEvents()
    self:InitializeBigIcon()
    self:OnEncounterTimelineReady()
end
