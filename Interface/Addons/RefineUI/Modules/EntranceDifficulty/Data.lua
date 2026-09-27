----------------------------------------------------------------------------------------
-- EntranceDifficulty Component: Data
-- Description: Entrance detection, cached instance metadata, and visible-only progress.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local EntranceDifficulty = RefineUI:GetModule("EntranceDifficulty")
if not EntranceDifficulty then
    return
end

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local format = string.format
local huge = math.huge
local max = math.max
local select = select
local sqrt = math.sqrt
local tostring = tostring
local C_EncounterJournal = C_EncounterJournal
local C_Map = C_Map
local C_RaidLocks = C_RaidLocks
local DifficultyUtil = DifficultyUtil
local GetDifficultyInfo = GetDifficultyInfo
local GetDungeonDifficultyID = GetDungeonDifficultyID
local GetNumSavedInstances = GetNumSavedInstances
local GetSavedInstanceEncounterInfo = GetSavedInstanceEncounterInfo
local GetSavedInstanceInfo = GetSavedInstanceInfo
local HasLFGRestrictions = HasLFGRestrictions
local IsInGroup = IsInGroup
local SetDungeonDifficultyID = SetDungeonDifficultyID
local SetRaidDifficulties = SetRaidDifficulties
local UnitIsGroupLeader = UnitIsGroupLeader
local EJ_GetCurrentTier = EJ_GetCurrentTier
local EJ_GetDifficulty = EJ_GetDifficulty
local EJ_GetEncounterInfoByIndex = EJ_GetEncounterInfoByIndex
local EJ_GetInstanceInfo = EJ_GetInstanceInfo
local EJ_IsValidInstanceDifficulty = EJ_IsValidInstanceDifficulty
local EJ_SelectInstance = EJ_SelectInstance
local EJ_SelectTier = EJ_SelectTier
local EJ_SetDifficulty = EJ_SetDifficulty

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local DIFFICULTY = DifficultyUtil.ID

local WALK_IN_DIFFICULTY_IDS = {
    DIFFICULTY.DungeonNormal,
    DIFFICULTY.DungeonHeroic,
    DIFFICULTY.DungeonMythic,
    DIFFICULTY.DungeonChallenge,
    DIFFICULTY.DungeonTimewalker,
    DIFFICULTY.RaidLFR,
    DIFFICULTY.Raid10Normal,
    DIFFICULTY.Raid10Heroic,
    DIFFICULTY.Raid25Normal,
    DIFFICULTY.Raid25Heroic,
    DIFFICULTY.PrimaryRaidLFR,
    DIFFICULTY.PrimaryRaidNormal,
    DIFFICULTY.PrimaryRaidHeroic,
    DIFFICULTY.PrimaryRaidMythic,
    DIFFICULTY.RaidTimewalker,
    DIFFICULTY.Raid40,
    DIFFICULTY.RaidStory,
}

local TRACKING_INTERVAL_NEAR = 0.35
local TRACKING_INTERVAL_MEDIUM = 1.00
local TRACKING_INTERVAL_FAR = 2.50

----------------------------------------------------------------------------------------
-- Caches
----------------------------------------------------------------------------------------
local entranceMapCache = {} -- [uiMapID] = mapData | false
local trackedMapCache = {} -- [playerMapID] = mapData | false
local instanceStaticCache = {} -- [journalInstanceID] = staticData

----------------------------------------------------------------------------------------
-- Instance Metadata
----------------------------------------------------------------------------------------
local function GetDifficultyLabel(difficultyID)
    local difficultyName = DifficultyUtil.GetDifficultyName(difficultyID) or GetDifficultyInfo(difficultyID) or tostring(difficultyID)

    if difficultyID ~= DIFFICULTY.RaidTimewalker
        and difficultyID ~= DIFFICULTY.RaidStory
        and not DifficultyUtil.IsPrimaryRaid(difficultyID) then
        local size = DifficultyUtil.GetMaxPlayers(difficultyID)
        if size and size > 0 then
            return format(ENCOUNTER_JOURNAL_DIFF_TEXT, size, difficultyName)
        end
    end

    return difficultyName
end

local function IsDifficultyUserSelectable(difficultyID)
    return select(11, GetDifficultyInfo(difficultyID)) == true
end

local function BuildEncounterTemplate(journalInstanceID)
    local encounters = {}
    local encounterIndex = 1

    while true do
        local encounterName, _, journalEncounterID, _, _, _, dungeonEncounterID, mapID = EJ_GetEncounterInfoByIndex(encounterIndex, journalInstanceID)
        if not journalEncounterID or journalEncounterID <= 0 then
            break
        end

        encounters[encounterIndex] = {
            name = encounterName,
            dungeonEncounterID = dungeonEncounterID,
            mapID = mapID,
        }
        encounterIndex = encounterIndex + 1
    end

    return encounters
end

local function GetDifficultiesForInstance(journalInstanceID)
    local difficulties = {}

    -- EJ_IsValidInstanceDifficulty reads the journal's selected instance; restore the player's journal afterwards.
    local savedTier = EJ_GetCurrentTier()
    local savedInstanceID = EncounterJournal and EncounterJournal.instanceID
    local savedDifficultyID = EJ_GetDifficulty()

    EJ_SelectInstance(journalInstanceID)
    for index = 1, #WALK_IN_DIFFICULTY_IDS do
        local difficultyID = WALK_IN_DIFFICULTY_IDS[index]
        if EJ_IsValidInstanceDifficulty(difficultyID) and IsDifficultyUserSelectable(difficultyID) then
            difficulties[#difficulties + 1] = {
                difficultyID = difficultyID,
                label = GetDifficultyLabel(difficultyID),
            }
        end
    end

    if savedTier then
        EJ_SelectTier(savedTier)
    end
    if savedInstanceID and savedInstanceID > 0 then
        EJ_SelectInstance(savedInstanceID)
    end
    if savedDifficultyID and savedDifficultyID > 0 then
        EJ_SetDifficulty(savedDifficultyID)
    end

    return difficulties
end

function EntranceDifficulty:GetInstanceStaticData(journalInstanceID)
    local staticData = instanceStaticCache[journalInstanceID]
    if staticData then
        return staticData
    end

    local instanceName, _, _, _, _, _, _, _, _, instanceMapID, _, isRaid = EJ_GetInstanceInfo(journalInstanceID)
    staticData = {
        difficulties = GetDifficultiesForInstance(journalInstanceID),
        encounterTemplate = BuildEncounterTemplate(journalInstanceID),
        instanceMapID = instanceMapID,
        instanceName = instanceName,
        isRaid = isRaid == true,
    }

    instanceStaticCache[journalInstanceID] = staticData
    return staticData
end

----------------------------------------------------------------------------------------
-- Progress
----------------------------------------------------------------------------------------
-- [instanceMapID][difficultyID] = { { name, isKilled }, ... } for active lockouts with kills.
local function BuildSavedInstanceLookup()
    local lookup = {}

    for instanceIndex = 1, GetNumSavedInstances() do
        local _, _, _, difficultyID, locked, extended, _, _, _, _, numEncounters, encounterProgress, _, instanceMapID = GetSavedInstanceInfo(instanceIndex)
        -- Expired lockouts stay listed (greyed in Raid Info) until they age out; they no longer hold kills.
        if (locked or extended) and encounterProgress and encounterProgress > 0 then
            local encounters = {}
            for encounterIndex = 1, numEncounters do
                local bossName, _, isKilled = GetSavedInstanceEncounterInfo(instanceIndex, encounterIndex)
                encounters[encounterIndex] = {
                    name = bossName,
                    isKilled = isKilled == true,
                }
            end

            local byDifficulty = lookup[instanceMapID]
            if not byDifficulty then
                byDifficulty = {}
                lookup[instanceMapID] = byDifficulty
            end
            byDifficulty[difficultyID] = encounters
        end
    end

    return lookup
end

local function BuildProgressFromRaidLocks(encounterTemplate, difficultyID)
    local encounters = {}
    local killedCount = 0
    local trackable = false

    for encounterIndex = 1, #encounterTemplate do
        local templateEncounter = encounterTemplate[encounterIndex]
        local mapID = templateEncounter.mapID
        local isKilled = false

        if mapID and templateEncounter.dungeonEncounterID then
            local lockDifficultyID = C_RaidLocks.GetRedirectedDifficultyID(mapID, difficultyID) or difficultyID
            if lockDifficultyID <= 0 then
                lockDifficultyID = difficultyID
            end
            isKilled = C_RaidLocks.IsEncounterComplete(mapID, templateEncounter.dungeonEncounterID, lockDifficultyID) == true
            trackable = true
        end

        if isKilled then
            killedCount = killedCount + 1
        end
        encounters[encounterIndex] = {
            name = templateEncounter.name or format("Boss %d", encounterIndex),
            isKilled = isKilled,
        }
    end

    return encounters, killedCount, trackable
end

local function BuildProgressFromSavedData(encounterTemplate, savedEncounters)
    local encounters = {}
    local killedCount = 0
    -- Saved lockout order only lines up with the journal when both list the same bosses.
    local useTemplateNames = #encounterTemplate == #savedEncounters

    for encounterIndex = 1, #savedEncounters do
        local savedEncounter = savedEncounters[encounterIndex]
        if savedEncounter.isKilled then
            killedCount = killedCount + 1
        end
        encounters[encounterIndex] = {
            name = (useTemplateNames and encounterTemplate[encounterIndex].name) or savedEncounter.name or format("Boss %d", encounterIndex),
            isKilled = savedEncounter.isKilled,
        }
    end

    return encounters, killedCount
end

function EntranceDifficulty:GetSavedInstanceLookup()
    local lookup = self.savedInstanceLookup
    if not lookup then
        lookup = BuildSavedInstanceLookup()
        self.savedInstanceLookup = lookup
    end
    return lookup
end

----------------------------------------------------------------------------------------
-- Detection
----------------------------------------------------------------------------------------
local function GetEntranceMapData(mapID)
    local mapData = entranceMapCache[mapID]
    if mapData ~= nil then
        return mapData
    end

    mapData = false
    local mapWidth, mapHeight = C_Map.GetMapWorldSize(mapID)
    if mapWidth and mapHeight and mapWidth > 0 and mapHeight > 0 then
        local dungeonEntrances = C_EncounterJournal.GetDungeonEntrancesForMap(mapID)
        if dungeonEntrances and #dungeonEntrances > 0 then
            local entrances = {}
            for index = 1, #dungeonEntrances do
                local entranceInfo = dungeonEntrances[index]
                local x, y = entranceInfo.position:GetXY()
                entrances[index] = {
                    atlasName = entranceInfo.atlasName,
                    journalInstanceID = entranceInfo.journalInstanceID,
                    name = entranceInfo.name,
                    x = x,
                    y = y,
                }
            end

            mapData = {
                entrances = entrances,
                mapHeight = mapHeight,
                mapID = mapID,
                mapWidth = mapWidth,
            }
        end
    end

    entranceMapCache[mapID] = mapData
    return mapData
end

local function ResolveTrackedMapData(playerMapID)
    local mapData = trackedMapCache[playerMapID]
    if mapData ~= nil then
        return mapData
    end

    local mapID = playerMapID
    mapData = false
    while mapID and mapID > 0 do
        mapData = GetEntranceMapData(mapID)
        if mapData then
            break
        end

        local mapInfo = C_Map.GetMapInfo(mapID)
        mapID = mapInfo and mapInfo.parentMapID
    end

    trackedMapCache[playerMapID] = mapData
    return mapData
end

-- Returns the entrance within trigger range (or nil) and the next poll interval (nil stops polling).
function EntranceDifficulty:DetectEntrance(triggerDistanceYards)
    local playerMapID = C_Map.GetBestMapForUnit("player")
    local mapData = playerMapID and ResolveTrackedMapData(playerMapID)
    if not mapData then
        return nil, nil
    end

    local position = C_Map.GetPlayerMapPosition(mapData.mapID, "player")
    if not position then
        return nil, TRACKING_INTERVAL_MEDIUM
    end

    local playerX, playerY = position:GetXY()
    local entrances = mapData.entrances
    local nearest
    local nearestDistanceSquared = huge
    for index = 1, #entrances do
        local entrance = entrances[index]
        local deltaX = (entrance.x - playerX) * mapData.mapWidth
        local deltaY = (entrance.y - playerY) * mapData.mapHeight
        local distanceSquared = (deltaX * deltaX) + (deltaY * deltaY)
        if distanceSquared < nearestDistanceSquared then
            nearestDistanceSquared = distanceSquared
            nearest = entrance
        end
    end

    local distanceYards = sqrt(nearestDistanceSquared)
    if distanceYards <= triggerDistanceYards then
        return nearest, TRACKING_INTERVAL_NEAR
    elseif distanceYards <= max(triggerDistanceYards * 4, 80) then
        return nil, TRACKING_INTERVAL_NEAR
    elseif distanceYards <= max(triggerDistanceYards * 10, 260) then
        return nil, TRACKING_INTERVAL_MEDIUM
    end

    return nil, TRACKING_INTERVAL_FAR
end

----------------------------------------------------------------------------------------
-- Visible Card State
----------------------------------------------------------------------------------------
local function GetInteractionLockReason()
    if IsInGroup() and not UnitIsGroupLeader("player") then
        return "Only the group leader can change difficulty."
    end

    if HasLFGRestrictions() then
        return "Queued or matchmaking groups can't change walk-in difficulty."
    end

    return nil
end

local function IsDifficultyActive(difficultyID, isRaid)
    if isRaid then
        return DifficultyUtil.DoesCurrentRaidDifficultyMatch(difficultyID)
    end

    return GetDungeonDifficultyID() == difficultyID
end

function EntranceDifficulty:BuildCardState()
    local entrance = self.detectedEntrance
    if not entrance then
        return nil
    end

    local staticData = self:GetInstanceStaticData(entrance.journalInstanceID)
    local encounterTemplate = staticData.encounterTemplate
    local savedByDifficulty = self:GetSavedInstanceLookup()[staticData.instanceMapID]
    local difficulties = staticData.difficulties
    local rows = {}
    local activeDifficultyID

    for index = 1, #difficulties do
        local difficultyID = difficulties[index].difficultyID
        local encounters, killedCount, trackable = BuildProgressFromRaidLocks(encounterTemplate, difficultyID)
        local totalCount = #encounterTemplate

        local savedEncounters = savedByDifficulty and savedByDifficulty[difficultyID]
        if savedEncounters and (not trackable or killedCount == 0) then
            encounters, killedCount = BuildProgressFromSavedData(encounterTemplate, savedEncounters)
            totalCount = #savedEncounters
        end

        local isActive = IsDifficultyActive(difficultyID, staticData.isRaid)
        if isActive and not activeDifficultyID then
            activeDifficultyID = difficultyID
        end

        rows[index] = {
            difficultyID = difficultyID,
            encounters = encounters,
            isActive = isActive,
            killedCount = killedCount,
            label = difficulties[index].label,
            totalCount = totalCount,
        }
    end

    local lockReason = GetInteractionLockReason()
    local footerText = lockReason
    if not footerText and #rows == 0 then
        footerText = "No walk-in difficulties are available here."
    end

    return {
        activeDifficultyID = activeDifficultyID,
        atlasName = entrance.atlasName,
        canInteract = lockReason == nil,
        footerText = footerText,
        isRaid = staticData.isRaid,
        journalInstanceID = entrance.journalInstanceID,
        name = entrance.name or staticData.instanceName,
        rows = rows,
    }
end

----------------------------------------------------------------------------------------
-- Difficulty Actions
----------------------------------------------------------------------------------------
function EntranceDifficulty:ApplyDifficulty(difficultyID, isRaid)
    if isRaid then
        SetRaidDifficulties(DifficultyUtil.IsPrimaryRaid(difficultyID), difficultyID)
    else
        SetDungeonDifficultyID(difficultyID)
    end

    self:RequestVisibleRefresh()
end
