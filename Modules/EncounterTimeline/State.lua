----------------------------------------------------------------------------------------
-- EncounterTimeline Component: State
-- Description: Runtime registries and state lifecycle for event/timer tracking
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
local next = next
local tonumber = tonumber
local type = type

----------------------------------------------------------------------------------------
-- Registry Helpers
----------------------------------------------------------------------------------------
function EncounterTimeline:InitializeState()
    if self.stateInitialized then
        return
    end

    RefineUI:CreateDataRegistry(self.STATE_REGISTRY, "k")
    self.eventFramesByEventID = self.eventFramesByEventID or {}
    self.eventMetadataByEventID = self.eventMetadataByEventID or {}
    self.audioPlayedSecondsByEventID = self.audioPlayedSecondsByEventID or {}
    self.activeBigIconEventIDs = self.activeBigIconEventIDs or {}
    self.stateInitialized = true
end

function EncounterTimeline:StateGet(owner, key, defaultValue)
    return RefineUI:RegistryGet(self.STATE_REGISTRY, owner, key, defaultValue)
end

function EncounterTimeline:StateSet(owner, key, value)
    return RefineUI:RegistrySet(self.STATE_REGISTRY, owner, key, value)
end

function EncounterTimeline:StateClear(owner, key)
    return RefineUI:RegistryClear(self.STATE_REGISTRY, owner, key)
end

----------------------------------------------------------------------------------------
-- Event Frame Mapping
----------------------------------------------------------------------------------------
function EncounterTimeline:MapEventFrame(eventID, eventFrame)
    if not self:IsValidEventID(eventID) or not eventFrame then
        return
    end

    self:InitializeState()
    self.eventFramesByEventID[eventID] = eventFrame
    self:StateSet(eventFrame, "eventID", eventID)
end

function EncounterTimeline:GetEventFrameByEventID(eventID)
    if not self:IsValidEventID(eventID) then
        return nil
    end
    self:InitializeState()
    return self.eventFramesByEventID[eventID]
end

function EncounterTimeline:UnmapEventID(eventID)
    if not self:IsValidEventID(eventID) then
        return
    end
    self:InitializeState()
    self.eventFramesByEventID[eventID] = nil
end

function EncounterTimeline:CleanupReleasedEventFrame(eventFrame)
    if not eventFrame then
        return
    end

    self:InitializeState()

    local eventID = self:StateGet(eventFrame, "eventID")
    if type(eventID) ~= "number" then
        eventID = tonumber(eventID)
    end
    if self:IsValidEventID(eventID) then
        self.eventFramesByEventID[eventID] = nil
    end

    self:StateClear(eventFrame, "eventID")
end

function EncounterTimeline:ClearEventFrameMappings()
    self:InitializeState()
    for eventID in next, self.eventFramesByEventID do
        self.eventFramesByEventID[eventID] = nil
    end
end

----------------------------------------------------------------------------------------
-- Event Metadata
----------------------------------------------------------------------------------------
function EncounterTimeline:GetEventMetadata(eventID)
    if not self:IsValidEventID(eventID) then
        return nil
    end

    self:InitializeState()
    return self.eventMetadataByEventID[eventID]
end

function EncounterTimeline:SetEventMetadata(eventID, metadata)
    if not self:IsValidEventID(eventID) then
        return
    end
    if type(metadata) ~= "table" then
        return
    end

    self:InitializeState()
    local stored = self.eventMetadataByEventID[eventID]
    if type(stored) ~= "table" then
        stored = {}
        self.eventMetadataByEventID[eventID] = stored
    end

    for key, value in next, metadata do
        stored[key] = value
    end
end

function EncounterTimeline:SetEventMetadataField(eventID, key, value)
    if type(key) ~= "string" or key == "" then
        return
    end

    self:SetEventMetadata(eventID, {
        [key] = value,
    })
end

function EncounterTimeline:MarkScriptEvent(eventID, metadata)
    if not self:IsValidEventID(eventID) then
        return
    end

    metadata = metadata or {}
    metadata.sourceToken = self.AUDIO_SOURCE_FILTER.SCRIPT
    metadata.isScriptEvent = true
    self:SetEventMetadata(eventID, metadata)
end

function EncounterTimeline:ClearEventMetadata(eventID)
    if not self:IsValidEventID(eventID) then
        return
    end

    self:InitializeState()
    self.eventMetadataByEventID[eventID] = nil
end

function EncounterTimeline:ClearAllEventMetadata()
    self:InitializeState()
    for eventID in next, self.eventMetadataByEventID do
        self.eventMetadataByEventID[eventID] = nil
    end
end

----------------------------------------------------------------------------------------
-- Big Icon Active State
----------------------------------------------------------------------------------------
function EncounterTimeline:SetActiveBigIconEventIDs(eventIDs)
    self:InitializeState()
    self.activeBigIconEventIDs = {}

    if type(eventIDs) ~= "table" then
        return
    end

    for index = 1, #eventIDs do
        local eventID = eventIDs[index]
        if self:IsValidEventID(eventID) then
            self.activeBigIconEventIDs[#self.activeBigIconEventIDs + 1] = eventID
        end
    end
end

function EncounterTimeline:GetActiveBigIconEventIDs()
    self:InitializeState()
    return self.activeBigIconEventIDs
end

function EncounterTimeline:RemoveActiveBigIconEventID(eventID)
    if not self:IsValidEventID(eventID) then
        return
    end

    self:InitializeState()
    local activeList = self.activeBigIconEventIDs
    for index = #activeList, 1, -1 do
        if activeList[index] == eventID then
            table.remove(activeList, index)
        end
    end
end

----------------------------------------------------------------------------------------
-- Audio Countdown State
----------------------------------------------------------------------------------------
function EncounterTimeline:HasPlayedAudioSecond(eventID, second)
    if not self:IsValidEventID(eventID) then
        return false
    end
    if type(second) ~= "number" then
        return false
    end

    self:InitializeState()
    local bySecond = self.audioPlayedSecondsByEventID[eventID]
    return type(bySecond) == "table" and bySecond[second] == true
end

function EncounterTimeline:MarkAudioSecondPlayed(eventID, second)
    if not self:IsValidEventID(eventID) then
        return
    end
    if type(second) ~= "number" then
        return
    end

    self:InitializeState()
    local bySecond = self.audioPlayedSecondsByEventID[eventID]
    if type(bySecond) ~= "table" then
        bySecond = {}
        self.audioPlayedSecondsByEventID[eventID] = bySecond
    end
    bySecond[second] = true
end

function EncounterTimeline:ClearPlayedAudioStateForEvent(eventID)
    if not self:IsValidEventID(eventID) then
        return
    end

    self:InitializeState()
    self.audioPlayedSecondsByEventID[eventID] = nil
end

function EncounterTimeline:ClearAllPlayedAudioState()
    self:InitializeState()
    for eventID in next, self.audioPlayedSecondsByEventID do
        self.audioPlayedSecondsByEventID[eventID] = nil
    end
end

----------------------------------------------------------------------------------------
-- Per-Event Cleanup
----------------------------------------------------------------------------------------
function EncounterTimeline:ClearEventRuntimeState(eventID)
    if not self:IsValidEventID(eventID) then
        return
    end

    self:UnmapEventID(eventID)
    self:ClearEventMetadata(eventID)
    self:ClearPlayedAudioStateForEvent(eventID)
    self:RemoveActiveBigIconEventID(eventID)
end

----------------------------------------------------------------------------------------
-- Cleanup
----------------------------------------------------------------------------------------
function EncounterTimeline:ResetRuntimeState()
    self:ClearEventFrameMappings()
    self:ClearAllEventMetadata()
    self:ClearAllPlayedAudioState()
    self:SetActiveBigIconEventIDs({})
    self.bigIconLastSortedEventIDs = nil
    self.activeReadyCheckScriptEventID = nil
    self.activePullScriptEventID = nil
    self.audioLatestEventID = nil
end
