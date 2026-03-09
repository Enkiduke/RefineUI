----------------------------------------------------------------------------------------
-- EntranceDifficulty for RefineUI
-- Description: Entrance proximity difficulty selector and lockout summary.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local EntranceDifficulty = RefineUI:RegisterModule("EntranceDifficulty")

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local select = select
local format = string.format
local tonumber = tonumber
local tostring = tostring
local type = type
local IsInInstance = IsInInstance
local RequestRaidInfo = RequestRaidInfo

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local DEFAULT_TRIGGER_DISTANCE_YARDS = 30
local DEFAULT_UPDATE_INTERVAL_SECONDS = 2.0

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

EntranceDifficulty.KEY_PREFIX = "EntranceDifficulty"
EntranceDifficulty.FRAME_NAME = "RefineUI_EntranceDifficulty"
EntranceDifficulty.TRACKING_DEBOUNCE_KEY = EntranceDifficulty.KEY_PREFIX .. ":TrackingRefresh"
EntranceDifficulty.VISIBLE_DEBOUNCE_KEY = EntranceDifficulty.KEY_PREFIX .. ":VisibleRefresh"
EntranceDifficulty.REFRESH_JOB_KEY = EntranceDifficulty.KEY_PREFIX .. ":RefreshJob"
EntranceDifficulty.BLIZZARD_ENCOUNTER_JOURNAL = "Blizzard_EncounterJournal"
EntranceDifficulty.WALK_IN_DIFFICULTY_IDS = {}

local function AddWalkInDifficultyID(difficultyID)
    if type(difficultyID) == "number" then
        EntranceDifficulty.WALK_IN_DIFFICULTY_IDS[#EntranceDifficulty.WALK_IN_DIFFICULTY_IDS + 1] = difficultyID
    end
end

do
    local difficultyIDs = _G.DifficultyUtil and _G.DifficultyUtil.ID
    if type(difficultyIDs) == "table" then
        AddWalkInDifficultyID(difficultyIDs.DungeonNormal)
        AddWalkInDifficultyID(difficultyIDs.DungeonHeroic)
        AddWalkInDifficultyID(difficultyIDs.DungeonMythic)
        AddWalkInDifficultyID(difficultyIDs.DungeonChallenge)
        AddWalkInDifficultyID(difficultyIDs.DungeonTimewalker)
        AddWalkInDifficultyID(difficultyIDs.RaidLFR)
        AddWalkInDifficultyID(difficultyIDs.Raid10Normal)
        AddWalkInDifficultyID(difficultyIDs.Raid10Heroic)
        AddWalkInDifficultyID(difficultyIDs.Raid25Normal)
        AddWalkInDifficultyID(difficultyIDs.Raid25Heroic)
        AddWalkInDifficultyID(difficultyIDs.PrimaryRaidLFR)
        AddWalkInDifficultyID(difficultyIDs.PrimaryRaidNormal)
        AddWalkInDifficultyID(difficultyIDs.PrimaryRaidHeroic)
        AddWalkInDifficultyID(difficultyIDs.PrimaryRaidMythic)
        AddWalkInDifficultyID(difficultyIDs.RaidTimewalker)
        AddWalkInDifficultyID(difficultyIDs.Raid40)
        AddWalkInDifficultyID(difficultyIDs.RaidStory)
    end
end

----------------------------------------------------------------------------------------
-- Key Helpers
----------------------------------------------------------------------------------------
function EntranceDifficulty:BuildKey(...)
    local key = self.KEY_PREFIX
    for index = 1, select("#", ...) do
        key = key .. ":" .. tostring(select(index, ...))
    end
    return key
end

----------------------------------------------------------------------------------------
-- Config
----------------------------------------------------------------------------------------
function EntranceDifficulty:GetConfig()
    Config.EntranceDifficulty = Config.EntranceDifficulty or {}

    local config = Config.EntranceDifficulty
    if type(config.Enable) ~= "boolean" then
        config.Enable = true
    end

    if type(config.TriggerDistanceYards) ~= "number" then
        if type(config.TriggerRadius) == "number" then
            config.TriggerDistanceYards = tonumber(format("%.0f", config.TriggerRadius * 2000)) or DEFAULT_TRIGGER_DISTANCE_YARDS
        else
            config.TriggerDistanceYards = DEFAULT_TRIGGER_DISTANCE_YARDS
        end
    end

    if config.TriggerDistanceYards < 8 then
        config.TriggerDistanceYards = 8
    elseif config.TriggerDistanceYards > 80 then
        config.TriggerDistanceYards = 80
    end

    return config
end

function EntranceDifficulty:IsEnabled()
    return self:GetConfig().Enable ~= false
end

----------------------------------------------------------------------------------------
-- Visible State
----------------------------------------------------------------------------------------
function EntranceDifficulty:InvalidateVisibleCard()
    self.visibleCardDirty = true
end

function EntranceDifficulty:ReleaseVisibleState()
    self.pendingRaidInfoRequest = nil
    self.visibleCardDirty = nil
    self.renderedCardSignature = nil
    self.cardState = nil

    if self.ReleaseVisibleCaches then
        self:ReleaseVisibleCaches()
    end
end

function EntranceDifficulty:SetVisibleEventsEnabled(enabled)
    local eventKeyPrefix = self:BuildKey("VisibleEvent")
    if enabled == self.visibleEventsEnabled then
        return
    end

    self.visibleEventsEnabled = enabled == true
    for index = 1, #VISIBLE_EVENTS do
        local event = VISIBLE_EVENTS[index]
        local key = eventKeyPrefix .. ":" .. event
        if enabled then
            RefineUI:RegisterEventCallback(event, function(firedEvent, ...)
                EntranceDifficulty:OnVisibleEvent(firedEvent, ...)
            end, key)
        else
            RefineUI:OffEvent(event, key)
        end
    end
end

function EntranceDifficulty:EnterVisibleMode()
    if self.visibleMode == true then
        return
    end

    self.visibleMode = true
    self:SetVisibleEventsEnabled(true)
    self:InvalidateVisibleCard()
    self:RequestRaidInfoUpdate()
    self:RequestVisibleRefresh()
end

function EntranceDifficulty:ExitVisibleMode()
    if self.visibleMode ~= true then
        return
    end

    self.visibleMode = nil
    self:SetVisibleEventsEnabled(false)
    RefineUI:CancelDebounce(self.VISIBLE_DEBOUNCE_KEY)
    self:ReleaseVisibleState()

    if self.HideCard then
        self:HideCard()
    end
end

----------------------------------------------------------------------------------------
-- Refresh Pipeline
----------------------------------------------------------------------------------------
function EntranceDifficulty:RequestRaidInfoUpdate()
    if self.visibleMode ~= true or self.pendingRaidInfoRequest == true then
        return
    end
    if type(RequestRaidInfo) ~= "function" then
        return
    end

    self.pendingRaidInfoRequest = true
    RequestRaidInfo()
end

function EntranceDifficulty:RegisterRefreshJob()
    if self.refreshJobRegistered then
        return
    end
    if type(RefineUI.RegisterUpdateJob) ~= "function" then
        return
    end

    local ok = RefineUI:RegisterUpdateJob(self.REFRESH_JOB_KEY, DEFAULT_UPDATE_INTERVAL_SECONDS, function()
        EntranceDifficulty:OnRefreshTick()
    end, {
        enabled = false,
    })

    if ok then
        self.refreshJobRegistered = true
    end
end

function EntranceDifficulty:SetRefreshInterval(intervalSeconds)
    if not self.refreshJobRegistered or type(RefineUI.SetUpdateJobInterval) ~= "function" then
        return
    end

    if type(intervalSeconds) ~= "number" or intervalSeconds <= 0 then
        intervalSeconds = DEFAULT_UPDATE_INTERVAL_SECONDS
    end

    if self.refreshIntervalSeconds == intervalSeconds then
        return
    end

    self.refreshIntervalSeconds = intervalSeconds
    RefineUI:SetUpdateJobInterval(self.REFRESH_JOB_KEY, intervalSeconds)
end

function EntranceDifficulty:UpdateRefreshJobState()
    if not self.refreshJobRegistered or type(RefineUI.SetUpdateJobEnabled) ~= "function" then
        return
    end

    local inInstance = select(1, IsInInstance())
    local shouldEnable = self:IsEnabled() and not inInstance and self:IsTrackingActive()
    self:SetRefreshInterval(self:GetTrackingIntervalSeconds())
    RefineUI:SetUpdateJobEnabled(self.REFRESH_JOB_KEY, shouldEnable, false)
end

function EntranceDifficulty:RefreshVisibleCard()
    if self.visibleMode ~= true or self.visibleCardDirty ~= true then
        return
    end
    if not self.BuildCardState or not self.RefreshCard then
        return
    end

    local cardState = self:BuildCardState()
    self.visibleCardDirty = nil

    if type(cardState) ~= "table" then
        self:ExitVisibleMode()
        return
    end

    self.cardState = cardState
    self:RefreshCard(cardState)
end

function EntranceDifficulty:RefreshTracking()
    if not self:IsEnabled() then
        self:ResetTrackingState()
        self.detectedEntranceContext = nil
        self.detectedEntranceToken = nil
        self:ExitVisibleMode()
        self:UpdateRefreshJobState()
        return
    end

    local inInstance = select(1, IsInInstance())
    if inInstance then
        self:ResetTrackingState()
        self.detectedEntranceContext = nil
        self.detectedEntranceToken = nil
        self:ExitVisibleMode()
        self:UpdateRefreshJobState()
        return
    end

    local detectionChanged = false
    if self.UpdateDetectionContext then
        detectionChanged = self:UpdateDetectionContext()
    end

    local shouldShow = type(self.detectedEntranceContext) == "table"
    if shouldShow then
        if self.visibleMode ~= true then
            self:EnterVisibleMode()
        elseif detectionChanged then
            self:InvalidateVisibleCard()
            self:RequestRaidInfoUpdate()
            self:RequestVisibleRefresh()
        end
    else
        self:ExitVisibleMode()
    end

    self:UpdateRefreshJobState()
end

function EntranceDifficulty:RequestTrackingRefresh()
    RefineUI:Debounce(self.TRACKING_DEBOUNCE_KEY, 0.05, function()
        EntranceDifficulty:RefreshTracking()
    end)
end

function EntranceDifficulty:RequestVisibleRefresh()
    if self.visibleMode ~= true then
        return
    end

    RefineUI:Debounce(self.VISIBLE_DEBOUNCE_KEY, 0.05, function()
        EntranceDifficulty:RefreshVisibleCard()
    end)
end

function EntranceDifficulty:OnRefreshTick()
    self:RefreshTracking()
end

----------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------
function EntranceDifficulty:OnTrackingEvent()
    self:RequestTrackingRefresh()
end

function EntranceDifficulty:OnVisibleEvent(event)
    if self.visibleMode ~= true then
        return
    end

    if event == "UPDATE_INSTANCE_INFO" then
        self.pendingRaidInfoRequest = nil
        if self.InvalidateSavedInstanceSnapshot then
            self:InvalidateSavedInstanceSnapshot()
        end
    end

    self:InvalidateVisibleCard()
    self:RequestVisibleRefresh()
end

----------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------
function EntranceDifficulty:OnEnable()
    if not self:IsEnabled() then
        return
    end

    RefineUI:OnEvents(TRACKING_EVENTS, function(event, ...)
        EntranceDifficulty:OnTrackingEvent(event, ...)
    end, self:BuildKey("TrackingEvent"))

    self:RegisterRefreshJob()
    self:RefreshTracking()
end
