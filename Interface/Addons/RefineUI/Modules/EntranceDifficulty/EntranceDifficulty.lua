----------------------------------------------------------------------------------------
-- EntranceDifficulty for RefineUI
-- Description: Entrance proximity difficulty selector and lockout summary.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local EntranceDifficulty = RefineUI:RegisterModule("EntranceDifficulty", "EntranceDifficulty")

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local max = math.max
local min = math.min
local tonumber = tonumber
local IsInInstance = IsInInstance
local RequestRaidInfo = RequestRaidInfo

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local TRACKING_EVENTS = {
    "PLAYER_MAP_CHANGED",
    "PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED",
    "ZONE_CHANGED_INDOORS",
    "ZONE_CHANGED_NEW_AREA",
    "NEW_WMO_CHUNK",
}

local VISIBLE_EVENTS = {
    "GROUP_ROSTER_UPDATE",
    "PARTY_LEADER_CHANGED",
    "PLAYER_DIFFICULTY_CHANGED",
    "UPDATE_INSTANCE_INFO",
}

local KEY_PREFIX = "EntranceDifficulty"
local TRACKING_DEBOUNCE_KEY = KEY_PREFIX .. ":TrackingRefresh"
local VISIBLE_DEBOUNCE_KEY = KEY_PREFIX .. ":VisibleRefresh"
local REFRESH_JOB_KEY = KEY_PREFIX .. ":RefreshJob"
local TRACKING_EVENT_KEY = KEY_PREFIX .. ":TrackingEvent"
local VISIBLE_EVENT_KEY = KEY_PREFIX .. ":VisibleEvent"

EntranceDifficulty.FRAME_NAME = "RefineUI_EntranceDifficulty"
EntranceDifficulty.HIDE_TIMER_KEY = KEY_PREFIX .. ":HideCard"

----------------------------------------------------------------------------------------
-- Callbacks
----------------------------------------------------------------------------------------
local function RefreshTracking()
    EntranceDifficulty:RefreshTracking()
end

local function RefreshVisibleCard()
    EntranceDifficulty:RefreshVisibleCard()
end

local function OnTrackingEvent()
    RefineUI:Debounce(TRACKING_DEBOUNCE_KEY, 0.05, RefreshTracking)
end

local function OnVisibleEvent(event)
    EntranceDifficulty:OnVisibleEvent(event)
end

----------------------------------------------------------------------------------------
-- Visible State
----------------------------------------------------------------------------------------
function EntranceDifficulty:RequestVisibleRefresh()
    if self.visibleMode then
        RefineUI:Debounce(VISIBLE_DEBOUNCE_KEY, 0.05, RefreshVisibleCard)
    end
end

function EntranceDifficulty:SetVisibleEventsEnabled(enabled)
    for index = 1, #VISIBLE_EVENTS do
        local event = VISIBLE_EVENTS[index]
        if enabled then
            RefineUI:RegisterEventCallback(event, OnVisibleEvent, VISIBLE_EVENT_KEY .. ":" .. event)
        else
            RefineUI:OffEvent(event, VISIBLE_EVENT_KEY .. ":" .. event)
        end
    end
end

function EntranceDifficulty:EnterVisibleMode()
    self.visibleMode = true
    self:SetVisibleEventsEnabled(true)
    RequestRaidInfo()
    self:RequestVisibleRefresh()
end

function EntranceDifficulty:ExitVisibleMode()
    if not self.visibleMode then
        return
    end

    self.visibleMode = nil
    self:SetVisibleEventsEnabled(false)
    RefineUI:CancelDebounce(VISIBLE_DEBOUNCE_KEY)
    self.savedInstanceLookup = nil
    self:HideCard()
end

function EntranceDifficulty:RefreshVisibleCard()
    if not self.visibleMode then
        return
    end

    local cardState = self:BuildCardState()
    if not cardState then
        self:ExitVisibleMode()
        return
    end

    self:RefreshCard(cardState)
end

----------------------------------------------------------------------------------------
-- Tracking
----------------------------------------------------------------------------------------
function EntranceDifficulty:SetRefreshInterval(intervalSeconds)
    if self.refreshIntervalSeconds ~= intervalSeconds then
        self.refreshIntervalSeconds = intervalSeconds
        RefineUI:SetUpdateJobInterval(REFRESH_JOB_KEY, intervalSeconds)
    end
end

function EntranceDifficulty:RefreshTracking()
    local entrance, intervalSeconds
    if not IsInInstance() then
        entrance, intervalSeconds = self:DetectEntrance(self.triggerDistanceYards)
    end

    if entrance ~= self.detectedEntrance then
        self.detectedEntrance = entrance
        if entrance then
            if self.visibleMode then
                self:RequestVisibleRefresh()
            else
                self:EnterVisibleMode()
            end
        else
            self:ExitVisibleMode()
        end
    end

    if intervalSeconds then
        self:SetRefreshInterval(intervalSeconds)
    end
    RefineUI:SetUpdateJobEnabled(REFRESH_JOB_KEY, intervalSeconds ~= nil, false)
end

----------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------
function EntranceDifficulty:OnVisibleEvent(event)
    if event == "UPDATE_INSTANCE_INFO" then
        self.savedInstanceLookup = nil
    end

    self:RequestVisibleRefresh()
end

----------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------
function EntranceDifficulty:OnEnable()
    local config = Config.EntranceDifficulty
    self.triggerDistanceYards = min(80, max(8, tonumber(config.TriggerDistanceYards) or 24))

    RefineUI:OnEvents(TRACKING_EVENTS, OnTrackingEvent, TRACKING_EVENT_KEY)
    RefineUI:RegisterUpdateJob(REFRESH_JOB_KEY, 1, RefreshTracking, { enabled = false })
    self:RefreshTracking()
end
