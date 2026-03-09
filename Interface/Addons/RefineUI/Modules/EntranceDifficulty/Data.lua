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
local _G = _G
local format = string.format
local huge = math.huge
local lower = string.lower
local max = math.max
local select = select
local sqrt = math.sqrt
local tableConcat = table.concat
local tostring = tostring
local type = type
local C_EncounterJournal = C_EncounterJournal
local C_Map = C_Map
local C_RaidLocks = C_RaidLocks
local GetDifficultyInfo = GetDifficultyInfo
local GetDungeonDifficultyID = GetDungeonDifficultyID
local GetInstanceInfo = GetInstanceInfo
local GetLegacyRaidDifficultyID = GetLegacyRaidDifficultyID
local GetNumSavedInstances = GetNumSavedInstances
local GetRaidDifficultyID = GetRaidDifficultyID
local GetSavedInstanceEncounterInfo = GetSavedInstanceEncounterInfo
local GetSavedInstanceInfo = GetSavedInstanceInfo
local HasLFGRestrictions = HasLFGRestrictions
local IsInGroup = IsInGroup
local IsInInstance = IsInInstance
local SetDungeonDifficultyID = SetDungeonDifficultyID
local SetLegacyRaidDifficultyID = SetLegacyRaidDifficultyID
local SetRaidDifficultyID = SetRaidDifficultyID
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
local DifficultyUtil = _G.DifficultyUtil

local LEGACY_DIFFICULTY = {
    [DifficultyUtil and DifficultyUtil.ID and DifficultyUtil.ID.Raid10Normal or -1] = true,
    [DifficultyUtil and DifficultyUtil.ID and DifficultyUtil.ID.Raid25Normal or -1] = true,
    [DifficultyUtil and DifficultyUtil.ID and DifficultyUtil.ID.Raid10Heroic or -1] = true,
    [DifficultyUtil and DifficultyUtil.ID and DifficultyUtil.ID.Raid25Heroic or -1] = true,
    [DifficultyUtil and DifficultyUtil.ID and DifficultyUtil.ID.Raid40 or -1] = true,
}

local PRIMARY_RAID_DIFFICULTY = {
    [DifficultyUtil and DifficultyUtil.ID and DifficultyUtil.ID.PrimaryRaidNormal or -1] = true,
    [DifficultyUtil and DifficultyUtil.ID and DifficultyUtil.ID.PrimaryRaidHeroic or -1] = true,
    [DifficultyUtil and DifficultyUtil.ID and DifficultyUtil.ID.PrimaryRaidMythic or -1] = true,
    [DifficultyUtil and DifficultyUtil.ID and DifficultyUtil.ID.PrimaryRaidLFR or -1] = true,
}

local RAID_TOGGLE_MAP = {
    [DifficultyUtil and DifficultyUtil.ID and DifficultyUtil.ID.PrimaryRaidNormal or -1] = {
        DifficultyUtil and DifficultyUtil.ID and DifficultyUtil.ID.Raid10Normal or -1,
        DifficultyUtil and DifficultyUtil.ID and DifficultyUtil.ID.Raid25Normal or -1,
    },
    [DifficultyUtil and DifficultyUtil.ID and DifficultyUtil.ID.PrimaryRaidHeroic or -1] = {
        DifficultyUtil and DifficultyUtil.ID and DifficultyUtil.ID.Raid10Heroic or -1,
        DifficultyUtil and DifficultyUtil.ID and DifficultyUtil.ID.Raid25Heroic or -1,
    },
    [DifficultyUtil and DifficultyUtil.ID and DifficultyUtil.ID.PrimaryRaidMythic or -1] = {},
}

local TRACKING_INTERVAL_SECONDS = {
    Fast = 0.12,
    Near = 0.35,
    Medium = 1.00,
    Far = 2.50,
}

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local function IsLegacyDifficulty(difficultyID)
    return LEGACY_DIFFICULTY[difficultyID] == true
end

local function IsPrimaryRaidDifficulty(difficultyID)
    return PRIMARY_RAID_DIFFICULTY[difficultyID] == true
end

local function GetVectorXY(vector)
    if type(vector) ~= "table" then
        return nil, nil
    end

    if type(vector.GetXY) == "function" then
        return vector:GetXY()
    end

    return vector.x, vector.y
end

local function NormalizeName(name)
    if type(name) ~= "string" then
        return ""
    end

    return lower(name)
end

local function BuildSavedInstanceKey(instanceName, difficultyID)
    return NormalizeName(instanceName) .. ":" .. tostring(difficultyID or 0)
end

local function GetMaxPlayersForDifficulty(difficultyID)
    if type(difficultyID) ~= "number" then
        return nil
    end

    if type(DifficultyUtil) == "table" and type(DifficultyUtil.GetMaxPlayers) == "function" then
        return DifficultyUtil.GetMaxPlayers(difficultyID)
    end

    local _, _, _, _, _, _, _, _, _, maxPlayers = GetDifficultyInfo(difficultyID)
    return maxPlayers
end

local function NormalizeLegacyDifficultyID(difficultyID)
    if not IsLegacyDifficulty(difficultyID) then
        return difficultyID
    end

    if difficultyID > 4 then
        difficultyID = difficultyID - 2
    end
    return difficultyID
end

local function GetMappedLegacyDifficultyID(difficultyID, size)
    local mappedDifficultyIDs = RAID_TOGGLE_MAP[difficultyID]
    if type(mappedDifficultyIDs) ~= "table" then
        return nil
    end

    for index = 1, #mappedDifficultyIDs do
        local mappedDifficultyID = mappedDifficultyIDs[index]
        if GetMaxPlayersForDifficulty(mappedDifficultyID) == size then
            return mappedDifficultyID
        end
    end

    return nil
end

local function CheckToggleDifficulty(toggleDifficultyID, difficultyID)
    if IsLegacyDifficulty(toggleDifficultyID) then
        if IsLegacyDifficulty(difficultyID) then
            return NormalizeLegacyDifficultyID(difficultyID) == NormalizeLegacyDifficultyID(toggleDifficultyID)
        end

        local mappedDifficultyIDs = RAID_TOGGLE_MAP[difficultyID]
        if type(mappedDifficultyIDs) ~= "table" then
            return false
        end

        for index = 1, #mappedDifficultyIDs do
            if mappedDifficultyIDs[index] == toggleDifficultyID then
                return true
            end
        end
        return false
    end

    if not IsLegacyDifficulty(difficultyID) then
        return toggleDifficultyID == difficultyID
    end

    return false
end

local function SetRaidDifficultiesCompat(primaryRaid, difficultyID)
    if primaryRaid then
        local force
        local instanceDifficultyID, _, _, _, isDynamicInstance = select(3, GetInstanceInfo())
        local toggleDifficultyID

        if isDynamicInstance and type(_G.CanChangePlayerDifficulty) == "function" and _G.CanChangePlayerDifficulty() then
            toggleDifficultyID = select(7, GetDifficultyInfo(instanceDifficultyID))
            if toggleDifficultyID and IsLegacyDifficulty(toggleDifficultyID) then
                force = true
            end
        end

        SetRaidDifficultyID(difficultyID, force)

        if DifficultyUtil and DifficultyUtil.ID and difficultyID == DifficultyUtil.ID.PrimaryRaidMythic then
            return
        end

        force = toggleDifficultyID and not IsLegacyDifficulty(toggleDifficultyID)

        local otherDifficulty = GetLegacyRaidDifficultyID()
        local size = GetMaxPlayersForDifficulty(otherDifficulty)
        local newDifficulty = GetMappedLegacyDifficultyID(difficultyID, size)
        if newDifficulty ~= nil then
            SetLegacyRaidDifficultyID(newDifficulty, force)
        end
        return
    end

    local otherDifficulty = GetRaidDifficultyID()
    local size = GetMaxPlayersForDifficulty(difficultyID)
    local newDifficulty = GetMappedLegacyDifficultyID(otherDifficulty, size)
    if newDifficulty ~= nil then
        SetLegacyRaidDifficultyID(newDifficulty)
    end
end

local function GetDifficultyLabel(difficultyID)
    local difficultyName
    if type(DifficultyUtil) == "table" and type(DifficultyUtil.GetDifficultyName) == "function" then
        difficultyName = DifficultyUtil.GetDifficultyName(difficultyID)
    end

    if type(difficultyName) ~= "string" or difficultyName == "" then
        difficultyName = select(1, GetDifficultyInfo(difficultyID)) or tostring(difficultyID)
    end

    local size
    if difficultyID ~= (DifficultyUtil and DifficultyUtil.ID and DifficultyUtil.ID.RaidTimewalker)
        and difficultyID ~= (DifficultyUtil and DifficultyUtil.ID and DifficultyUtil.ID.RaidStory)
        and not IsPrimaryRaidDifficulty(difficultyID) then
        size = GetMaxPlayersForDifficulty(difficultyID)
    end

    if type(size) == "number" and size > 0 then
        if type(_G.ENCOUNTER_JOURNAL_DIFF_TEXT) == "string" and _G.ENCOUNTER_JOURNAL_DIFF_TEXT ~= "" then
            return format(_G.ENCOUNTER_JOURNAL_DIFF_TEXT, size, difficultyName)
        end
        return format("%d Player %s", size, difficultyName)
    end

    return difficultyName
end

local function IsDifficultyUserSelectable(difficultyID)
    local _, _, _, _, _, _, _, _, _, _, isUserSelectable = GetDifficultyInfo(difficultyID)
    return isUserSelectable == true
end

local function HasLFGRestriction()
    if type(HasLFGRestrictions) == "function" then
        return HasLFGRestrictions() == true
    end

    if type(_G.UnitPopupSharedUtil) == "table" and type(_G.UnitPopupSharedUtil.HasLFGRestrictions) == "function" then
        return _G.UnitPopupSharedUtil.HasLFGRestrictions() == true
    end

    return false
end

local function BuildSavedInstanceLookup()
    local lookup = {}

    for instanceIndex = 1, (GetNumSavedInstances() or 0) do
        local instanceName, _, _, difficultyID, _, _, _, _, _, _, numEncounters, encounterProgress = GetSavedInstanceInfo(instanceIndex)
        if type(instanceName) == "string" and type(difficultyID) == "number" then
            local encounters = {}
            for encounterIndex = 1, (numEncounters or 0) do
                local bossName, _, isKilled = GetSavedInstanceEncounterInfo(instanceIndex, encounterIndex)
                encounters[encounterIndex] = {
                    name = bossName,
                    isKilled = isKilled == true,
                }
            end

            lookup[BuildSavedInstanceKey(instanceName, difficultyID)] = {
                difficultyID = difficultyID,
                encounterProgress = encounterProgress or 0,
                encounters = encounters,
                name = instanceName,
                numEncounters = numEncounters or 0,
            }
        end
    end

    return lookup
end

local function BuildEncounterTemplate(journalInstanceID)
    local encounters = {}
    local encounterIndex = 1

    while true do
        local encounterName, _, journalEncounterID, _, _, _, dungeonEncounterID, mapID = EJ_GetEncounterInfoByIndex(encounterIndex, journalInstanceID)
        if type(journalEncounterID) ~= "number" or journalEncounterID <= 0 then
            break
        end

        encounters[#encounters + 1] = {
            name = encounterName,
            dungeonEncounterID = dungeonEncounterID,
            mapID = mapID,
        }

        encounterIndex = encounterIndex + 1
    end

    return encounters
end

local function BuildProgressFromSavedData(encounterTemplate, savedData)
    local encounters = {}
    local killedCount = 0
    local totalCount = 0

    if type(encounterTemplate) == "table" and #encounterTemplate > 0 then
        totalCount = #encounterTemplate
        for encounterIndex = 1, #encounterTemplate do
            local templateEncounter = encounterTemplate[encounterIndex]
            local savedEncounter = savedData and savedData.encounters and savedData.encounters[encounterIndex]
            local isKilled = savedEncounter and savedEncounter.isKilled == true or false
            if isKilled then
                killedCount = killedCount + 1
            end

            encounters[#encounters + 1] = {
                name = templateEncounter.name or (savedEncounter and savedEncounter.name) or format("Boss %d", encounterIndex),
                isKilled = isKilled,
            }
        end
        return encounters, killedCount, totalCount
    end

    if savedData and type(savedData.encounters) == "table" then
        totalCount = #savedData.encounters
        for encounterIndex = 1, totalCount do
            local savedEncounter = savedData.encounters[encounterIndex]
            local isKilled = savedEncounter and savedEncounter.isKilled == true or false
            if isKilled then
                killedCount = killedCount + 1
            end
            encounters[#encounters + 1] = {
                name = savedEncounter and savedEncounter.name or format("Boss %d", encounterIndex),
                isKilled = isKilled,
            }
        end
    end

    return encounters, killedCount, totalCount
end

local function BuildProgressFromRaidLocks(encounterTemplate, difficultyID)
    local encounters = {}
    local hadTrackableEncounters = false
    local killedCount = 0
    local totalCount = 0

    for encounterIndex = 1, #encounterTemplate do
        local templateEncounter = encounterTemplate[encounterIndex]
        local isKilled

        if type(C_RaidLocks) == "table"
            and type(C_RaidLocks.IsEncounterComplete) == "function"
            and type(templateEncounter.mapID) == "number"
            and type(templateEncounter.dungeonEncounterID) == "number" then
            local resolvedDifficultyID = difficultyID
            if type(C_RaidLocks.GetRedirectedDifficultyID) == "function" then
                local redirectedDifficultyID = C_RaidLocks.GetRedirectedDifficultyID(templateEncounter.mapID, difficultyID)
                if type(redirectedDifficultyID) == "number" and redirectedDifficultyID > 0 then
                    resolvedDifficultyID = redirectedDifficultyID
                end
            end

            local ok, killed = pcall(C_RaidLocks.IsEncounterComplete, templateEncounter.mapID, templateEncounter.dungeonEncounterID, resolvedDifficultyID)
            if ok and type(killed) == "boolean" then
                isKilled = killed
                hadTrackableEncounters = true
            end
        end

        if isKilled == true then
            killedCount = killedCount + 1
        end

        totalCount = totalCount + 1
        encounters[#encounters + 1] = {
            name = templateEncounter.name or format("Boss %d", encounterIndex),
            isKilled = isKilled == true,
        }
    end

    return encounters, killedCount, totalCount, hadTrackableEncounters
end

local function SaveEncounterJournalState()
    return {
        difficultyID = type(EJ_GetDifficulty) == "function" and EJ_GetDifficulty() or nil,
        instanceID = _G.EncounterJournal and _G.EncounterJournal.instanceID or nil,
        tier = type(EJ_GetCurrentTier) == "function" and EJ_GetCurrentTier() or nil,
    }
end

local function RestoreEncounterJournalState(state)
    if type(state) ~= "table" then
        return
    end

    if type(EJ_SelectTier) == "function" and type(state.tier) == "number" then
        pcall(EJ_SelectTier, state.tier)
    end

    if type(EJ_SelectInstance) == "function" and type(state.instanceID) == "number" and state.instanceID > 0 then
        pcall(EJ_SelectInstance, state.instanceID)
    end

    if type(EJ_SetDifficulty) == "function" and type(state.difficultyID) == "number" and state.difficultyID > 0 then
        pcall(EJ_SetDifficulty, state.difficultyID)
    end
end

local function GetDifficultyIDsForInstance(journalInstanceID)
    local difficultyIDs = {}
    local savedState = SaveEncounterJournalState()

    if type(EJ_SelectInstance) == "function" then
        pcall(EJ_SelectInstance, journalInstanceID)
    end

    for index = 1, #EntranceDifficulty.WALK_IN_DIFFICULTY_IDS do
        local difficultyID = EntranceDifficulty.WALK_IN_DIFFICULTY_IDS[index]
        if type(difficultyID) == "number"
            and type(EJ_IsValidInstanceDifficulty) == "function"
            and EJ_IsValidInstanceDifficulty(difficultyID)
            and IsDifficultyUserSelectable(difficultyID) then
            difficultyIDs[#difficultyIDs + 1] = difficultyID
        end
    end

    RestoreEncounterJournalState(savedState)
    return difficultyIDs
end

local function DoesCurrentRaidDifficultyMatch(compareDifficultyID)
    if type(DifficultyUtil) == "table" and type(DifficultyUtil.DoesCurrentRaidDifficultyMatch) == "function" then
        return DifficultyUtil.DoesCurrentRaidDifficultyMatch(compareDifficultyID)
    end

    local currentDifficultyID = GetRaidDifficultyID()
    if type(currentDifficultyID) ~= "number" then
        return false
    end

    if IsLegacyDifficulty(compareDifficultyID) then
        return GetLegacyRaidDifficultyID() == compareDifficultyID
    end

    if currentDifficultyID == compareDifficultyID then
        return true
    end

    local toggleDifficultyID = select(7, GetDifficultyInfo(currentDifficultyID))
    if type(toggleDifficultyID) == "number" then
        return CheckToggleDifficulty(toggleDifficultyID, compareDifficultyID)
    end

    return false
end

local function IsDifficultyActive(difficultyID, isRaid)
    if isRaid then
        return DoesCurrentRaidDifficultyMatch(difficultyID)
    end

    return GetDungeonDifficultyID() == difficultyID
end

local function BuildCardStateSignature(cardState)
    local parts = {
        tostring(cardState.journalInstanceID or 0),
        tostring(cardState.displayName or ""),
        tostring(cardState.activeDifficultyID or 0),
        tostring(cardState.statusText or ""),
        tostring(cardState.footerText or ""),
        tostring(cardState.lockReason or ""),
        tostring(cardState.canInteract == true and 1 or 0),
        tostring(#(cardState.rows or {})),
    }

    local rows = cardState.rows or {}
    for index = 1, #rows do
        local row = rows[index]
        parts[#parts + 1] = tostring(row.difficultyID or 0)
        parts[#parts + 1] = tostring(row.isActive == true and 1 or 0)
        parts[#parts + 1] = tostring(row.killedCount or 0)
        parts[#parts + 1] = tostring(row.totalCount or 0)
    end

    return tableConcat(parts, "|")
end

----------------------------------------------------------------------------------------
-- Visible Caches
----------------------------------------------------------------------------------------
function EntranceDifficulty:InvalidateSavedInstanceSnapshot()
    self.savedInstanceSnapshotVersion = (self.savedInstanceSnapshotVersion or 0) + 1
    self.savedInstanceLookupCache = nil
end

function EntranceDifficulty:GetSavedInstanceLookupCached()
    local version = self.savedInstanceSnapshotVersion or 0
    local cache = self.savedInstanceLookupCache
    if cache and cache.version == version then
        return cache.lookup
    end

    local lookup = BuildSavedInstanceLookup()
    self.savedInstanceLookupCache = {
        lookup = lookup,
        version = version,
    }
    return lookup
end

function EntranceDifficulty:GetInstanceStaticData(journalInstanceID)
    self.instanceStaticCache = self.instanceStaticCache or {}
    local cached = self.instanceStaticCache[journalInstanceID]
    if cached then
        return cached
    end

    local instanceName, _, _, _, _, _, _, _, _, _, _, isRaid = EJ_GetInstanceInfo(journalInstanceID)
    if type(instanceName) ~= "string" or instanceName == "" then
        instanceName = "Dungeon"
    end

    local difficultyIDs = GetDifficultyIDsForInstance(journalInstanceID)
    local difficulties = {}
    for index = 1, #difficultyIDs do
        local difficultyID = difficultyIDs[index]
        difficulties[#difficulties + 1] = {
            difficultyID = difficultyID,
            label = GetDifficultyLabel(difficultyID),
        }
    end

    local staticData = {
        difficulties = difficulties,
        encounterTemplate = BuildEncounterTemplate(journalInstanceID),
        instanceName = instanceName,
        isRaid = isRaid == true,
        journalInstanceID = journalInstanceID,
    }

    self.instanceStaticCache[journalInstanceID] = staticData
    return staticData
end

function EntranceDifficulty:ReleaseVisibleCaches()
    self.savedInstanceLookupCache = nil
    self.savedInstanceSnapshotVersion = nil
end

----------------------------------------------------------------------------------------
-- Tracking Data
----------------------------------------------------------------------------------------
local function GetPlayerMapID()
    if type(C_Map) ~= "table" or type(C_Map.GetBestMapForUnit) ~= "function" then
        return nil
    end

    local mapID = C_Map.GetBestMapForUnit("player")
    if type(mapID) ~= "number" or mapID <= 0 then
        return nil
    end

    return mapID
end

local function BuildMapChain(mapID)
    if type(C_Map) ~= "table" or type(C_Map.GetMapInfo) ~= "function" then
        return {}
    end

    local mapIDs = {}
    local seen = {}

    while type(mapID) == "number" and mapID > 0 and not seen[mapID] do
        mapIDs[#mapIDs + 1] = mapID
        seen[mapID] = true

        local mapInfo = C_Map.GetMapInfo(mapID)
        mapID = mapInfo and mapInfo.parentMapID or nil
    end

    return mapIDs
end

local function GetCoarseTrackingDistanceYards(triggerDistanceYards)
    return max(triggerDistanceYards * 4, 80)
end

local function GetEntranceMapData(mapID)
    if type(C_Map) ~= "table"
        or type(C_Map.GetMapWorldSize) ~= "function"
        or type(C_EncounterJournal) ~= "table"
        or type(C_EncounterJournal.GetDungeonEntrancesForMap) ~= "function" then
        return nil
    end

    EntranceDifficulty.entranceMapCache = EntranceDifficulty.entranceMapCache or {}
    local cached = EntranceDifficulty.entranceMapCache[mapID]
    if cached ~= nil then
        return cached or nil
    end

    local mapWidth, mapHeight = C_Map.GetMapWorldSize(mapID)
    if type(mapWidth) ~= "number" or type(mapHeight) ~= "number" or mapWidth <= 0 or mapHeight <= 0 then
        EntranceDifficulty.entranceMapCache[mapID] = false
        return nil
    end

    local dungeonEntrances = C_EncounterJournal.GetDungeonEntrancesForMap(mapID)
    if type(dungeonEntrances) ~= "table" or #dungeonEntrances == 0 then
        EntranceDifficulty.entranceMapCache[mapID] = false
        return nil
    end

    local candidates = {}
    for index = 1, #dungeonEntrances do
        local entranceInfo = dungeonEntrances[index]
        local entranceX, entranceY = GetVectorXY(entranceInfo and entranceInfo.position)
        if type(entranceX) == "number"
            and type(entranceY) == "number"
            and type(entranceInfo.journalInstanceID) == "number"
            and entranceInfo.journalInstanceID > 0 then
            candidates[#candidates + 1] = {
                description = entranceInfo.description,
                journalInstanceID = entranceInfo.journalInstanceID,
                name = entranceInfo.name,
                x = entranceX,
                y = entranceY,
            }
        end
    end

    if #candidates == 0 then
        EntranceDifficulty.entranceMapCache[mapID] = false
        return nil
    end

    local mapData = {
        candidates = candidates,
        mapHeight = mapHeight,
        mapID = mapID,
        mapWidth = mapWidth,
    }

    EntranceDifficulty.entranceMapCache[mapID] = mapData
    return mapData
end

local function ResolveTrackedMapData()
    if type(C_Map) ~= "table" or type(C_Map.GetPlayerMapPosition) ~= "function" then
        return nil, nil, nil
    end

    local playerMapID = GetPlayerMapID()
    if not playerMapID then
        return nil, nil, nil
    end

    EntranceDifficulty.resolvedTrackingMapCache = EntranceDifficulty.resolvedTrackingMapCache or {}
    local resolvedMapData = EntranceDifficulty.resolvedTrackingMapCache[playerMapID]
    if resolvedMapData == nil then
        resolvedMapData = false

        local mapChain = BuildMapChain(playerMapID)
        for index = 1, #mapChain do
            local mapData = GetEntranceMapData(mapChain[index])
            if mapData then
                resolvedMapData = mapData
                break
            end
        end

        EntranceDifficulty.resolvedTrackingMapCache[playerMapID] = resolvedMapData
    end

    if resolvedMapData == false then
        return nil, nil, nil
    end

    local playerPosition = C_Map.GetPlayerMapPosition(resolvedMapData.mapID, "player")
    local playerX, playerY = GetVectorXY(playerPosition)
    if type(playerX) ~= "number" or type(playerY) ~= "number" then
        return resolvedMapData, nil, nil
    end

    return resolvedMapData, playerX, playerY
end

local function FindNearestEntranceOnMap(mapData, playerX, playerY)
    if type(mapData) ~= "table" or type(playerX) ~= "number" or type(playerY) ~= "number" then
        return nil
    end

    local nearest
    local nearestDistanceSquared = huge
    for index = 1, #mapData.candidates do
        local entranceInfo = mapData.candidates[index]
        local deltaX = (entranceInfo.x - playerX) * mapData.mapWidth
        local deltaY = (entranceInfo.y - playerY) * mapData.mapHeight
        local distanceSquared = (deltaX * deltaX) + (deltaY * deltaY)
        if distanceSquared < nearestDistanceSquared then
            nearestDistanceSquared = distanceSquared
            nearest = {
                description = entranceInfo.description,
                distanceSquared = distanceSquared,
                distanceYards = sqrt(distanceSquared),
                journalInstanceID = entranceInfo.journalInstanceID,
                mapID = mapData.mapID,
                name = entranceInfo.name,
            }
        end
    end

    return nearest
end

local function GetTrackingIntervalSeconds(triggerDistanceYards, distanceYards)
    if type(distanceYards) ~= "number" then
        return nil
    end

    if distanceYards <= triggerDistanceYards then
        return TRACKING_INTERVAL_SECONDS.Fast
    end

    if distanceYards <= GetCoarseTrackingDistanceYards(triggerDistanceYards) then
        return TRACKING_INTERVAL_SECONDS.Near
    end

    if distanceYards <= max(triggerDistanceYards * 10, 260) then
        return TRACKING_INTERVAL_SECONDS.Medium
    end

    return TRACKING_INTERVAL_SECONDS.Far
end

----------------------------------------------------------------------------------------
-- Detection
----------------------------------------------------------------------------------------
function EntranceDifficulty:ResetTrackingState()
    self.trackingState = nil
end

function EntranceDifficulty:IsTrackingActive()
    return type(self.trackingState) == "table" and self.trackingState.enabled == true
end

function EntranceDifficulty:GetTrackingIntervalSeconds()
    if type(self.trackingState) ~= "table" then
        return nil
    end

    return self.trackingState.intervalSeconds
end

function EntranceDifficulty:UpdateDetectionContext()
    local inInstance = select(1, IsInInstance())
    if inInstance then
        local wasVisible = self.detectedEntranceContext ~= nil
        self:ResetTrackingState()
        self.detectedEntranceContext = nil
        self.detectedEntranceToken = nil
        return wasVisible
    end

    local triggerDistanceYards = self:GetConfig().TriggerDistanceYards
    local mapData, playerX, playerY = ResolveTrackedMapData()
    if not mapData then
        local wasVisible = self.detectedEntranceContext ~= nil
        self:ResetTrackingState()
        self.detectedEntranceContext = nil
        self.detectedEntranceToken = nil
        return wasVisible
    end

    if type(playerX) ~= "number" or type(playerY) ~= "number" then
        local wasVisible = self.detectedEntranceContext ~= nil
        self.trackingState = {
            coarseDistanceYards = GetCoarseTrackingDistanceYards(triggerDistanceYards),
            enabled = true,
            intervalSeconds = TRACKING_INTERVAL_SECONDS.Medium,
            mapID = mapData.mapID,
            nearestDistanceYards = nil,
            nearestJournalInstanceID = nil,
        }
        self.detectedEntranceContext = nil
        self.detectedEntranceToken = nil
        return wasVisible
    end

    local nearestContext = FindNearestEntranceOnMap(mapData, playerX, playerY)
    self.trackingState = {
        coarseDistanceYards = GetCoarseTrackingDistanceYards(triggerDistanceYards),
        enabled = nearestContext ~= nil,
        intervalSeconds = GetTrackingIntervalSeconds(triggerDistanceYards, nearestContext and nearestContext.distanceYards or nil),
        mapID = mapData.mapID,
        nearestDistanceYards = nearestContext and nearestContext.distanceYards or nil,
        nearestJournalInstanceID = nearestContext and nearestContext.journalInstanceID or nil,
    }

    local shouldShow = nearestContext and nearestContext.distanceYards <= triggerDistanceYards
    if not shouldShow then
        nearestContext = nil
    end

    local detectionToken
    if nearestContext then
        detectionToken = tableConcat({
            tostring(nearestContext.mapID),
            tostring(nearestContext.journalInstanceID),
            tostring(nearestContext.name or ""),
        }, ":")
    end

    if self.detectedEntranceToken == detectionToken then
        return false
    end

    self.detectedEntranceToken = detectionToken
    self.detectedEntranceContext = nearestContext
    return true
end

----------------------------------------------------------------------------------------
-- Visible Card State
----------------------------------------------------------------------------------------
function EntranceDifficulty:GetInteractionLockReason(isRaid)
    if IsInGroup() and not UnitIsGroupLeader("player") then
        return "Only the group leader can change difficulty."
    end

    local inInstance = select(1, IsInInstance())
    if inInstance then
        return "Difficulty can't be changed from inside an instance."
    end

    if HasLFGRestriction() then
        return "Queued or matchmaking groups can't change walk-in difficulty."
    end

    if isRaid and type(DifficultyUtil) == "table" and type(DifficultyUtil.InStoryRaid) == "function" and DifficultyUtil.InStoryRaid() then
        return _G.DIFFICULTY_LOCKED_REASON_STORY_RAID or "Story raid difficulty is locked."
    end

    return nil
end

function EntranceDifficulty:BuildDifficultyRows(staticData, instanceName)
    local rows = {}
    local encounterTemplate = staticData.encounterTemplate or {}
    local savedLookup = self:GetSavedInstanceLookupCached()
    local difficulties = staticData.difficulties or {}

    for index = 1, #difficulties do
        local difficultyData = difficulties[index]
        local difficultyID = difficultyData.difficultyID
        local savedData = savedLookup[BuildSavedInstanceKey(instanceName, difficultyID)]
        local encounters, killedCount, totalCount, hadTrackableEncounters = BuildProgressFromRaidLocks(encounterTemplate, difficultyID)

        if (not hadTrackableEncounters or (killedCount == 0 and savedData and savedData.encounterProgress > 0)) then
            encounters, killedCount, totalCount = BuildProgressFromSavedData(encounterTemplate, savedData)
        end

        rows[#rows + 1] = {
            difficultyID = difficultyID,
            label = difficultyData.label,
            isActive = IsDifficultyActive(difficultyID, staticData.isRaid),
            isEnabled = true,
            killedCount = killedCount,
            totalCount = totalCount,
            encounters = encounters,
        }
    end

    return rows
end

function EntranceDifficulty:BuildCardState()
    local context = self.detectedEntranceContext
    if type(context) ~= "table" or type(context.journalInstanceID) ~= "number" then
        return nil
    end

    local staticData = self:GetInstanceStaticData(context.journalInstanceID)
    local instanceName = staticData.instanceName
    if type(instanceName) ~= "string" or instanceName == "" then
        instanceName = context.name or "Dungeon"
    end

    local rows = self:BuildDifficultyRows(staticData, instanceName)
    local lockReason = self:GetInteractionLockReason(staticData.isRaid)
    local activeDifficultyID
    for index = 1, #rows do
        if rows[index].isActive == true then
            activeDifficultyID = rows[index].difficultyID
            break
        end
    end

    local statusText
    if not IsInGroup() then
        statusText = "Solo"
    elseif lockReason then
        statusText = "Read only"
    else
        statusText = "Leader"
    end

    local footerText = lockReason
    if not footerText and #rows == 0 then
        footerText = "No walk-in difficulties are available here."
    end

    local cardState = {
        journalInstanceID = context.journalInstanceID,
        displayName = context.name or instanceName,
        instanceName = instanceName,
        isRaid = staticData.isRaid,
        rows = rows,
        activeDifficultyID = activeDifficultyID,
        statusText = statusText,
        footerText = footerText,
        lockReason = lockReason,
        canInteract = lockReason == nil,
    }

    cardState.signature = BuildCardStateSignature(cardState)
    return cardState
end

----------------------------------------------------------------------------------------
-- Difficulty Actions
----------------------------------------------------------------------------------------
function EntranceDifficulty:ApplyDifficulty(difficultyID, isRaid)
    if type(difficultyID) ~= "number" then
        return false
    end

    if isRaid then
        SetRaidDifficultiesCompat(IsPrimaryRaidDifficulty(difficultyID), difficultyID)
    else
        SetDungeonDifficultyID(difficultyID)
    end

    self:InvalidateVisibleCard()
    self:RequestRaidInfoUpdate()
    self:RequestVisibleRefresh()
    return true
end
