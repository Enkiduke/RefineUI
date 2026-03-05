----------------------------------------------------------------------------------------
-- Auto Zone Track for RefineUI
-- Description: Handles auto quest watch updates based on zone and user pins
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local AutoZoneTrack = RefineUI:RegisterModule("AutoZoneTrack")

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local InCombatLockdown = InCombatLockdown
local C_QuestLog = C_QuestLog
local Enum = Enum
local wipe = wipe
local tinsert = table.insert
local tremove = table.remove
local ipairs = ipairs

local addQuestWatch = C_QuestLog.AddQuestWatch
local removeQuestWatch = C_QuestLog.RemoveQuestWatch
local isWorldQuest = C_QuestLog.IsWorldQuest
local getQuestInfo = C_QuestLog.GetInfo
local getNumQuestLogEntries = C_QuestLog.GetNumQuestLogEntries
local getLogIndexForQuestID = C_QuestLog.GetLogIndexForQuestID
local getNumQuestWatches = C_QuestLog.GetNumQuestWatches
local getQuestIDForQuestWatchIndex = C_QuestLog.GetQuestIDForQuestWatchIndex
local getQuestWatchType = C_QuestLog.GetQuestWatchType

local function isQuestWatched(questID)
    if getQuestWatchType then
        return getQuestWatchType(questID) ~= nil
    end
    return false
end

local hiddenQuests = {
    [24636] = true,
}

local questDB

local AUTO_CAP = 12
local OPS_PER_TICK = 2
local TICK_SECONDS = 0.05
local RESYNC_DEBOUNCE_KEY = "AutoZoneTrack:Resync"
local RESYNC_DEBOUNCE_DELAY = 0.20
local QUEUE_TICK_TIMER_KEY = "AutoZoneTrack:QueueTick"

local QUEST_WATCH_TYPE_MANUAL = (Enum and Enum.QuestWatchType and Enum.QuestWatchType.Manual) or 1
local QUEST_WATCH_TYPE_AUTOMATIC = (Enum and Enum.QuestWatchType and Enum.QuestWatchType.Automatic) or 0

local pendingOps = {}
local queueIndex = 1
local queueRunning = false
local needsResync = false
local isApplyingQueue = false
local knownWatchTypes = {}

----------------------------------------------------------------------------------------
--	Helpers
----------------------------------------------------------------------------------------
local function EnsureDB()
    if not questDB then
        RefineUI_ZonedQuestsDB = RefineUI_ZonedQuestsDB or {}
        questDB = RefineUI_ZonedQuestsDB
    end
end

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

local function ShouldAutoTrack(info)
    if not info or not info.questID then
        return false
    end
    return info.isOnMap or hiddenQuests[info.questID] or false
end

local function BuildCurrentWatchSet()
    local watchedSet = {}
    local watchedOrder = {}

    if getNumQuestWatches and getQuestIDForQuestWatchIndex then
        local numWatched = getNumQuestWatches() or 0
        for i = 1, numWatched do
            local questID = getQuestIDForQuestWatchIndex(i)
            if questID then
                watchedSet[questID] = true
                tinsert(watchedOrder, questID)
                if getQuestWatchType then
                    local watchType = getQuestWatchType(questID)
                    if watchType ~= nil then
                        knownWatchTypes[questID] = watchType
                    end
                end
            end
        end
    else
        for i = 1, getNumQuestLogEntries() do
            local info = getQuestInfo(i)
            if IsEligibleQuestInfo(info) and isQuestWatched(info.questID) then
                watchedSet[info.questID] = true
                tinsert(watchedOrder, info.questID)
                if getQuestWatchType then
                    local watchType = getQuestWatchType(info.questID)
                    if watchType ~= nil then
                        knownWatchTypes[info.questID] = watchType
                    end
                end
            end
        end
    end

    return watchedSet, watchedOrder
end

local function BuildDesiredWatchSet()
    EnsureDB()

    local desiredSet = {}
    local desiredOrder = {}
    local autoCandidates = {}

    for i = 1, getNumQuestLogEntries() do
        local info = getQuestInfo(i)
        if IsEligibleQuestInfo(info) then
            local questID = info.questID
            if questDB[questID] then
                if not desiredSet[questID] then
                    desiredSet[questID] = true
                    tinsert(desiredOrder, questID)
                end
            elseif ShouldAutoTrack(info) then
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

    isApplyingQueue = false

    if clearQueue then
        wipe(pendingOps)
        queueIndex = 1
    end
end

local function BuildFullResyncOps()
    local watchedSet, watchedOrder = BuildCurrentWatchSet()
    local desiredSet, desiredOrder = BuildDesiredWatchSet()

    wipe(pendingOps)
    queueIndex = 1

    for _, questID in ipairs(desiredOrder) do
        if not watchedSet[questID] then
            tinsert(pendingOps, { op = "add", questID = questID })
        end
    end

    for _, questID in ipairs(watchedOrder) do
        if not desiredSet[questID] then
            tinsert(pendingOps, { op = "remove", questID = questID })
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

    if queueIndex > #pendingOps then
        StopQueueProcessing(true)
        if needsResync then
            RefineUI:Debounce(RESYNC_DEBOUNCE_KEY, 0.05, function()
                if not Config.Quests.AutoZoneTrack then
                    return
                end
                if InCombatLockdown() then
                    needsResync = true
                    return
                end
                needsResync = false
                BuildFullResyncOps()
                if #pendingOps > 0 then
                    queueRunning = true
                    RefineUI:After(QUEUE_TICK_TIMER_KEY, TICK_SECONDS, ProcessQueueTick)
                end
            end)
        end
        return
    end

    local processed = 0
    isApplyingQueue = true

    while processed < OPS_PER_TICK and queueIndex <= #pendingOps do
        local op = pendingOps[queueIndex]
        queueIndex = queueIndex + 1

        if op and op.questID then
            if op.op == "add" then
                if not isQuestWatched(op.questID) then
                    addQuestWatch(op.questID)
                end
                if isQuestWatched(op.questID) then
                    knownWatchTypes[op.questID] = QUEST_WATCH_TYPE_AUTOMATIC
                end
            elseif op.op == "remove" then
                if isQuestWatched(op.questID) then
                    removeQuestWatch(op.questID)
                end
                knownWatchTypes[op.questID] = nil
            end
            processed = processed + 1
        end
    end

    isApplyingQueue = false

    if queueIndex > #pendingOps then
        StopQueueProcessing(true)
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
local function QueueResync(delay)
    needsResync = true

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
        StopQueueProcessing(true)
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
    EnsureDB()

    local questLogIndex = getLogIndexForQuestID and getLogIndexForQuestID(questID)
    if not questLogIndex then
        return false, false
    end

    local info = getQuestInfo(questLogIndex)
    if not IsEligibleQuestInfo(info) then
        return false, false
    end

    if questDB[questID] then
        return true, true
    end

    if ShouldAutoTrack(info) then
        return true, false
    end

    return false, false
end

local function CanAddAutoQuest(questID)
    local watchedSet, watchedOrder = BuildCurrentWatchSet()
    local autoCount = 0

    for _, watchedQuestID in ipairs(watchedOrder) do
        if not questDB[watchedQuestID] then
            autoCount = autoCount + 1
        end
    end

    if watchedSet[questID] and not questDB[questID] then
        return true
    end

    for i = queueIndex, #pendingOps do
        local op = pendingOps[i]
        if op and op.questID and not questDB[op.questID] then
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

    local want, isManualPin = EvaluateQuestWant(questID)
    local watched = isQuestWatched(questID)

    RemovePendingOpsForQuest(questID)

    if want and not watched then
        if not isManualPin and not CanAddAutoQuest(questID) then
            return
        end
        tinsert(pendingOps, { op = "add", questID = questID })
        StartQueueProcessing()
    elseif not want and watched then
        tinsert(pendingOps, { op = "remove", questID = questID })
        StartQueueProcessing()
    end
end

local function CleanupQuestState(questID)
    if not questID then
        return
    end
    EnsureDB()
    questDB[questID] = nil
    knownWatchTypes[questID] = nil
    RemovePendingOpsForQuest(questID)
end

----------------------------------------------------------------------------------------
--	Update Trigger
-----------------------------------------------------------------------------------------
function AutoZoneTrack:UpdateTrigger(delay, questID)
    EnsureDB()

    if not Config.Quests.AutoZoneTrack then
        RefineUI:CancelDebounce(RESYNC_DEBOUNCE_KEY)
        StopQueueProcessing(true)
        needsResync = false
        return
    end

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

    EnsureDB()

    if isApplyingQueue then
        if added and getQuestWatchType then
            knownWatchTypes[questID] = getQuestWatchType(questID)
        elseif not added then
            knownWatchTypes[questID] = nil
        end
        return
    end

    if added then
        local watchType = getQuestWatchType and getQuestWatchType(questID)
        knownWatchTypes[questID] = watchType
        if watchType == QUEST_WATCH_TYPE_MANUAL then
            questDB[questID] = true
        end
    else
        local previousType = knownWatchTypes[questID]
        knownWatchTypes[questID] = nil
        if previousType == QUEST_WATCH_TYPE_MANUAL then
            questDB[questID] = nil
        end
    end
end

----------------------------------------------------------------------------------------
--	Initialize
----------------------------------------------------------------------------------------
function AutoZoneTrack:OnInitialize()
    if not Config.Quests.Enable then
        return
    end

    EnsureDB()

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
