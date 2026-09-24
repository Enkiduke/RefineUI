----------------------------------------------------------------------------------------
-- Auto Zone Track for RefineUI
-- Description: Handles auto quest watch updates based on zone and user pins
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local AutoZoneTrack = RefineUI:RegisterModule("AutoZoneTrack", function(cfg)
    local quests = cfg.Quests
    if type(quests) ~= "table" or quests.Enable == false then
        return false
    end
    return quests.AutoZoneTrack ~= false
end)

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local InCombatLockdown = InCombatLockdown
local C_QuestLog = C_QuestLog
local C_Map = C_Map
local Enum = Enum
local wipe = wipe
local tinsert = table.insert
local tremove = table.remove
local ipairs = ipairs
local pairs = pairs

local addQuestWatch = C_QuestLog.AddQuestWatch
local removeQuestWatch = C_QuestLog.RemoveQuestWatch
local removeWorldQuestWatch = C_QuestLog.RemoveWorldQuestWatch
local isWorldQuest = C_QuestLog.IsWorldQuest
local getQuestInfo = C_QuestLog.GetInfo
local getNumQuestLogEntries = C_QuestLog.GetNumQuestLogEntries
local getLogIndexForQuestID = C_QuestLog.GetLogIndexForQuestID
local getNumQuestWatches = C_QuestLog.GetNumQuestWatches
local getQuestIDForQuestWatchIndex = C_QuestLog.GetQuestIDForQuestWatchIndex
local getNumWorldQuestWatches = C_QuestLog.GetNumWorldQuestWatches
local getQuestIDForWorldQuestWatchIndex = C_QuestLog.GetQuestIDForWorldQuestWatchIndex
local getQuestWatchType = C_QuestLog.GetQuestWatchType
local getQuestsOnMap = C_QuestLog.GetQuestsOnMap
local getBestMapForUnit = C_Map.GetBestMapForUnit
local getMapInfo = C_Map.GetMapInfo
local getTasksTable = GetTasksTable

local function isQuestWatched(questID)
    if getQuestWatchType then
        return getQuestWatchType(questID) ~= nil
    end
    return false
end

local hiddenQuests = {
    [24636] = true,
}

local manualPins

local AUTO_CAP = 12
local OPS_PER_TICK = 2
local TICK_SECONDS = 0.05
local RESYNC_DEBOUNCE_KEY = "AutoZoneTrack:Resync"
local RESYNC_DEBOUNCE_DELAY = 0.20
local QUEUE_TICK_TIMER_KEY = "AutoZoneTrack:QueueTick"

local QUEST_WATCH_TYPE_MANUAL = (Enum and Enum.QuestWatchType and Enum.QuestWatchType.Manual) or 1

local pendingOps = {}
local queueIndex = 1
local queueRunning = false
local needsResync = false
local expectedWatchChanges = {}
local QueueResync

----------------------------------------------------------------------------------------
--	Helpers
----------------------------------------------------------------------------------------
local function IsEligibleQuestInfo(info)
    if not info or not info.questID then
        return false
    end
    if info.isHidden or info.isHeader then
        return false
    end
    if isWorldQuest(info.questID) then
        return false
    end
    return true
end

local function ShouldAutoTrack(info, localQuests)
    if not info or not info.questID then
        return false
    end
    return localQuests[info.questID] or hiddenQuests[info.questID] or false
end

local function BuildLocalQuestSet()
    local mapID = getBestMapForUnit("player")
    if not mapID then
        return nil
    end

    local mapInfo = getMapInfo(mapID)
    while mapInfo and mapInfo.mapType > Enum.UIMapType.Zone and mapInfo.parentMapID and mapInfo.parentMapID > 0 do
        mapID = mapInfo.parentMapID
        mapInfo = getMapInfo(mapID)
    end

    local localQuests = {}
    local quests = getQuestsOnMap(mapID)
    if quests then
        for i = 1, #quests do
            localQuests[quests[i].questID] = true
        end
    end
    return localQuests
end

local function RecordWatch(watchedSet, watchedOrder, worldQuestSet, questID, worldQuest)
    if not questID then
        return
    end

    if worldQuest then
        worldQuestSet[questID] = true
    end

    if watchedSet[questID] then
        return
    end

    watchedSet[questID] = true
    tinsert(watchedOrder, questID)
end

local function BuildCurrentWatchSet()
    local watchedSet = {}
    local watchedOrder = {}
    local worldQuestSet = {}

    if getNumQuestWatches and getQuestIDForQuestWatchIndex then
        local numWatched = getNumQuestWatches() or 0
        for i = 1, numWatched do
            RecordWatch(watchedSet, watchedOrder, worldQuestSet, getQuestIDForQuestWatchIndex(i))
        end
    else
        for i = 1, getNumQuestLogEntries() do
            local info = getQuestInfo(i)
            if IsEligibleQuestInfo(info) and isQuestWatched(info.questID) then
                RecordWatch(watchedSet, watchedOrder, worldQuestSet, info.questID)
            end
        end
    end

    for i = 1, getNumWorldQuestWatches() do
        RecordWatch(watchedSet, watchedOrder, worldQuestSet, getQuestIDForWorldQuestWatchIndex(i), true)
    end

    return watchedSet, watchedOrder, worldQuestSet
end

local function BuildLocalWorldQuestSet()
    local localWorldQuests = {}
    local tasks = getTasksTable()

    for i = 1, #tasks do
        local questID = tasks[i]
        if isWorldQuest(questID) then
            localWorldQuests[questID] = true
        end
    end

    return localWorldQuests
end

local function BuildDesiredWatchSet()
    local localQuests = BuildLocalQuestSet()
    if not localQuests then
        return nil
    end

    local desiredSet = {}
    local desiredOrder = {}
    local autoCandidates = {}

    for i = 1, getNumQuestLogEntries() do
        local info = getQuestInfo(i)
        if IsEligibleQuestInfo(info) then
            local questID = info.questID
            if manualPins[questID] then
                if not desiredSet[questID] then
                    desiredSet[questID] = true
                    tinsert(desiredOrder, questID)
                end
            elseif ShouldAutoTrack(info, localQuests) then
                tinsert(autoCandidates, questID)
            end
        end
    end

    local autoCount = 0
    for _, questID in ipairs(autoCandidates) do
        if autoCount >= AUTO_CAP then
            break
        end
        if not desiredSet[questID] then
            desiredSet[questID] = true
            tinsert(desiredOrder, questID)
            autoCount = autoCount + 1
        end
    end

    return desiredSet, desiredOrder
end

local function StopQueueProcessing(clearQueue)
    RefineUI:CancelTimer(QUEUE_TICK_TIMER_KEY)
    queueRunning = false

    if clearQueue then
        wipe(pendingOps)
        queueIndex = 1
    end
end

local function BuildFullResyncOps()
    local watchedSet, watchedOrder, worldQuestSet = BuildCurrentWatchSet()
    local localWorldQuests = BuildLocalWorldQuestSet()
    local desiredSet, desiredOrder = BuildDesiredWatchSet()
    if not desiredSet then
        return
    end

    wipe(pendingOps)
    queueIndex = 1

    for _, questID in ipairs(watchedOrder) do
        local keepLocalWorldQuest = worldQuestSet[questID] and localWorldQuests[questID]
        if not desiredSet[questID] and not keepLocalWorldQuest then
            tinsert(pendingOps, {
                op = "remove",
                questID = questID,
                isWorldQuest = worldQuestSet[questID] or false,
            })
        end
    end

    for _, questID in ipairs(desiredOrder) do
        if not watchedSet[questID] then
            tinsert(pendingOps, { op = "add", questID = questID })
        end
    end
end

----------------------------------------------------------------------------------------
--	Queue Processing
----------------------------------------------------------------------------------------
local function ProcessQueueTick()
    if not Config.Quests.AutoZoneTrack then
        StopQueueProcessing(true)
        return
    end

    if InCombatLockdown() then
        needsResync = true
        StopQueueProcessing(true)
        return
    end

    local processed = 0

    while processed < OPS_PER_TICK and queueIndex <= #pendingOps do
        local op = pendingOps[queueIndex]
        queueIndex = queueIndex + 1

        if op and op.questID then
            if op.op == "add" then
                if not isQuestWatched(op.questID) then
                    expectedWatchChanges[op.questID] = true
                    addQuestWatch(op.questID)
                    if not isQuestWatched(op.questID) then expectedWatchChanges[op.questID] = nil end
                end
            elseif op.op == "remove" then
                if not manualPins[op.questID] and isQuestWatched(op.questID) then
                    expectedWatchChanges[op.questID] = false
                    if op.isWorldQuest then
                        removeWorldQuestWatch(op.questID)
                    else
                        removeQuestWatch(op.questID)
                    end
                    if isQuestWatched(op.questID) then expectedWatchChanges[op.questID] = nil end
                end
            end
            processed = processed + 1
        end
    end

    if queueIndex > #pendingOps then
        StopQueueProcessing(true)
        if needsResync then QueueResync(0.05) end
    elseif queueRunning then
        RefineUI:After(QUEUE_TICK_TIMER_KEY, TICK_SECONDS, ProcessQueueTick)
    end
end

local function StartQueueProcessing()
    if queueRunning then
        return
    end

    if #pendingOps == 0 then
        return
    end

    if InCombatLockdown() then
        needsResync = true
        return
    end

    queueRunning = true
    RefineUI:After(QUEUE_TICK_TIMER_KEY, TICK_SECONDS, ProcessQueueTick)
end

----------------------------------------------------------------------------------------
--	Resync + Incremental Updates
----------------------------------------------------------------------------------------
QueueResync = function(delay)
    needsResync = true
    StopQueueProcessing(true)

    RefineUI:Debounce(RESYNC_DEBOUNCE_KEY, delay or RESYNC_DEBOUNCE_DELAY, function()
        if not Config.Quests.AutoZoneTrack then
            StopQueueProcessing(true)
            return
        end

        if InCombatLockdown() then
            needsResync = true
            return
        end

        needsResync = false
        BuildFullResyncOps()
        StartQueueProcessing()
    end)
end

local function RemovePendingOpsForQuest(questID)
    if not questID then
        return
    end

    for i = #pendingOps, queueIndex, -1 do
        local op = pendingOps[i]
        if op and op.questID == questID then
            tremove(pendingOps, i)
        end
    end

    if queueIndex > #pendingOps then
        StopQueueProcessing(true)
    end
end

local function EvaluateQuestWant(questID)
    local questLogIndex = getLogIndexForQuestID and getLogIndexForQuestID(questID)
    if not questLogIndex then
        return false, false
    end

    local info = getQuestInfo(questLogIndex)
    if not IsEligibleQuestInfo(info) then
        return false, false
    end

    if manualPins[questID] then
        return true, true
    end

    local localQuests = BuildLocalQuestSet()
    if not localQuests then
        return nil, false
    end
    if ShouldAutoTrack(info, localQuests) then
        return true, false
    end

    return false, false
end

local function CanAddAutoQuest(questID)
    local watchedSet, watchedOrder = BuildCurrentWatchSet()
    local autoCount = 0

    for _, watchedQuestID in ipairs(watchedOrder) do
        if not isWorldQuest(watchedQuestID) and not manualPins[watchedQuestID] then
            autoCount = autoCount + 1
        end
    end

    if watchedSet[questID] and not manualPins[questID] then
        return true
    end

    for i = queueIndex, #pendingOps do
        local op = pendingOps[i]
        if op and op.questID and not op.isWorldQuest and not manualPins[op.questID] then
            if op.op == "add" and not watchedSet[op.questID] then
                watchedSet[op.questID] = true
                autoCount = autoCount + 1
            elseif op.op == "remove" and watchedSet[op.questID] then
                watchedSet[op.questID] = nil
                autoCount = autoCount - 1
            end
        end
    end

    return autoCount < AUTO_CAP
end

local function QueueIncrementalQuestUpdate(questID)
    if not questID then
        return
    end

    if needsResync then
        return
    end

    if InCombatLockdown() then
        needsResync = true
        return
    end

    if isWorldQuest(questID) then
        QueueResync(0.05)
        return
    end

    local want, isManualPin = EvaluateQuestWant(questID)
    if want == nil then
        return
    end
    local watched = isQuestWatched(questID)

    RemovePendingOpsForQuest(questID)

    if want and not watched then
        if not isManualPin and not CanAddAutoQuest(questID) then
            return
        end
        tinsert(pendingOps, { op = "add", questID = questID })
        StartQueueProcessing()
    elseif not want and watched then
        tinsert(pendingOps, {
            op = "remove",
            questID = questID,
            isWorldQuest = isWorldQuest(questID),
        })
        StartQueueProcessing()
    end
end

local function CleanupQuestState(questID)
    if not questID then
        return
    end
    manualPins[questID] = nil
    expectedWatchChanges[questID] = nil
    RemovePendingOpsForQuest(questID)
end

----------------------------------------------------------------------------------------
--	Update Trigger
-----------------------------------------------------------------------------------------
function AutoZoneTrack:UpdateTrigger(delay, questID)
    if not Config.Quests.AutoZoneTrack then
        RefineUI:CancelDebounce(RESYNC_DEBOUNCE_KEY)
        StopQueueProcessing(true)
        needsResync = false
        return
    end
    if not self.eventsRegistered then self:OnInitialize() end

    if questID then
        QueueIncrementalQuestUpdate(questID)
    else
        QueueResync(delay or RESYNC_DEBOUNCE_DELAY)
    end
end

----------------------------------------------------------------------------------------
--	Watch Change Tracking (Strict Manual Detection)
----------------------------------------------------------------------------------------
function AutoZoneTrack:OnQuestWatchListChanged(questID, added)
    if not questID then
        return
    end

    local expected = expectedWatchChanges[questID]
    expectedWatchChanges[questID] = nil
    if expected ~= nil and expected == added then
        return
    end

    RemovePendingOpsForQuest(questID)
    if added then
        local watchType = getQuestWatchType and getQuestWatchType(questID)
        if watchType == QUEST_WATCH_TYPE_MANUAL and not isWorldQuest(questID) then
            manualPins[questID] = true
        end
    else
        manualPins[questID] = nil
    end
end

----------------------------------------------------------------------------------------
--	Initialize
----------------------------------------------------------------------------------------
function AutoZoneTrack:OnInitialize()
    if self.eventsRegistered then return end
    if not Config.Quests.Enable then
        return
    end

    self.eventsRegistered = true
    RefineUI.DB.AutoZoneTrackManualPins = RefineUI.DB.AutoZoneTrackManualPins or {}
    manualPins = RefineUI.DB.AutoZoneTrackManualPins
    for questID in pairs(manualPins) do
        if not isQuestWatched(questID) then manualPins[questID] = nil end
    end
    local events = {
        "QUEST_WATCH_LIST_CHANGED",
        "QUEST_ACCEPTED",
        "QUEST_REMOVED",
        "QUEST_TURNED_IN",
        "AREA_POIS_UPDATED",
        "PLAYER_ENTERING_WORLD",
        "ZONE_CHANGED",
        "ZONE_CHANGED_INDOORS",
        "ZONE_CHANGED_NEW_AREA",
        "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED"
    }

    RefineUI:OnEvents(events, function(event, ...)
        if event == "QUEST_WATCH_LIST_CHANGED" then
            self:OnQuestWatchListChanged(...)
            return
        end

        if event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN" then
            local questID = ...
            CleanupQuestState(questID)
            if Config.Quests.AutoZoneTrack then
                QueueResync(0.05)
            end
            return
        end

        if event == "PLAYER_REGEN_DISABLED" then
            if queueRunning then
                needsResync = true
                StopQueueProcessing(true)
            end
            return
        end

        if event == "PLAYER_REGEN_ENABLED" then
            if needsResync then
                self:UpdateTrigger(0.05)
            end
            return
        end

        if event == "QUEST_ACCEPTED" then
            local questID = ...
            self:UpdateTrigger(0, questID)
            return
        end

        self:UpdateTrigger(0.20)
    end, "AutoZoneTrack:Update")
end
