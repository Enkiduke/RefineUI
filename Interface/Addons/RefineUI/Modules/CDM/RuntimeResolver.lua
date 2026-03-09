-- Description: Refine-owned runtime resolution for aura and totem state.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local CDM = RefineUI:GetModule("CDM")
if not CDM then
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
local abs = math.abs
local pcall = pcall
local pairs = pairs
local tconcat = table.concat
local tostring = tostring

local GetTime = GetTime
local GetNumTotemSlots = GetNumTotemSlots
local GetTotemInfo = _G.GetTotemInfo
local InCombatLockdown = InCombatLockdown
local C_Spell = C_Spell
local C_UnitAuras = C_UnitAuras
local issecretvalue = _G.issecretvalue

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local DEFAULT_ICON_TEXTURE = 134400

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
local activePayloadCache = {}
local runtimeDebugState = {
    enabled = false,
    lastSnapshot = nil,
    lastCombatSnapshot = nil,
    buildingSnapshot = nil,
    recentAuraEvents = {},
}
local unitAuraCache = {
    player = {
        bySpellID = {},
        byInstanceID = {},
        spellInstances = {},
    },
    target = {
        bySpellID = {},
        byInstanceID = {},
        spellInstances = {},
    },
}

local GetUnitAuraBucket
local GetAuraSpellIDValue

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function CountTableEntries(tbl)
    if type(tbl) ~= "table" then
        return 0
    end

    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

local function SafeValueString(value)
    if IsSecret(value) then
        return "secret"
    end
    if value == nil then
        return "nil"
    end
    return tostring(value)
end

local function SafeBoolString(value)
    if IsSecret(value) then
        return "secret"
    end
    if value == nil then
        return "nil"
    end
    return value and "yes" or "no"
end

local function JoinValueList(values)
    if type(values) ~= "table" or #values == 0 then
        return "-"
    end

    local parts = {}
    for i = 1, #values do
        parts[#parts + 1] = SafeValueString(values[i])
    end
    return tconcat(parts, ",")
end

local function SafeGetSpellName(spellID)
    if type(spellID) ~= "number" or spellID <= 0 or not C_Spell or type(C_Spell.GetSpellName) ~= "function" then
        return nil
    end

    local ok, name = pcall(C_Spell.GetSpellName, spellID)
    if ok and not IsSecret(name) and type(name) == "string" and name ~= "" then
        return name
    end

    return nil
end

local function FormatSpellToken(spellID, suffix)
    if type(spellID) ~= "number" or spellID <= 0 or IsSecret(spellID) then
        return nil
    end

    local token = tostring(spellID)
    local spellName = SafeGetSpellName(spellID)
    if spellName then
        token = token .. "(" .. spellName .. ")"
    end

    if suffix ~= nil then
        token = token .. "@" .. SafeValueString(suffix)
    end

    return token
end

local function PushRecentAuraEvent(line)
    if type(line) ~= "string" or line == "" then
        return
    end

    local events = runtimeDebugState.recentAuraEvents
    events[#events + 1] = line
    if #events > 10 then
        table.remove(events, 1)
    end
end

local function BuildAuraCacheSummary(unit)
    local bucket = GetUnitAuraBucket(unit)
    if not bucket then
        return {}, {}
    end

    local summary = {}
    local unknown = {}
    for auraInstanceID, auraData in pairs(bucket.byInstanceID) do
        if type(auraData) == "table" then
            local spellID = GetAuraSpellIDValue(auraData)
            if spellID then
                summary[#summary + 1] = FormatSpellToken(spellID, auraInstanceID) or (SafeValueString(spellID) .. "@" .. SafeValueString(auraInstanceID))
            else
                local auraName = type(auraData.name) == "string" and auraData.name or "unknown"
                unknown[#unknown + 1] = auraName .. "@" .. SafeValueString(auraInstanceID)
            end
        end
    end
    return summary, unknown
end

local function BuildTotemSummary(totemMap)
    local summary = {}
    if type(totemMap) ~= "table" then
        return summary
    end

    for spellID, totemInfo in pairs(totemMap) do
        if type(totemInfo) == "table" then
            summary[#summary + 1] = (FormatSpellToken(spellID) or SafeValueString(spellID)) .. "@" .. SafeValueString(totemInfo.slot)
        end
    end
    return summary
end

local function BuildLiveAuraScan(unit, filter)
    local summary = {
        count = 0,
        spells = {},
        unknown = {},
    }

    if not C_UnitAuras or type(C_UnitAuras.GetUnitAuras) ~= "function" then
        return summary
    end

    local effectiveFilter = filter
    if unit == "player" and (type(effectiveFilter) ~= "string" or effectiveFilter == "") then
        effectiveFilter = "HELPFUL"
    end
    if unit == "target" and (type(effectiveFilter) ~= "string" or effectiveFilter == "") then
        effectiveFilter = "HARMFUL|PLAYER"
    end

    local ok, auraTable = pcall(C_UnitAuras.GetUnitAuras, unit, effectiveFilter)
    if not ok or type(auraTable) ~= "table" then
        return summary
    end

    summary.count = #auraTable
    for i = 1, #auraTable do
        local auraData = auraTable[i]
        if type(auraData) == "table" then
            local spellID = GetAuraSpellIDValue(auraData)
            local auraInstanceID = auraData.auraInstanceID
            if spellID then
                summary.spells[#summary.spells + 1] = FormatSpellToken(spellID, auraInstanceID) or (SafeValueString(spellID) .. "@" .. SafeValueString(auraInstanceID))
            else
                local auraName = type(auraData.name) == "string" and auraData.name or "unknown"
                summary.unknown[#summary.unknown + 1] = auraName .. "@" .. SafeValueString(auraInstanceID)
            end
        end
    end

    return summary
end

local function FindDirectAuraMatch(unit, spellIDs, filter)
    if type(spellIDs) ~= "table" or #spellIDs == 0 then
        return nil, nil
    end

    if not C_UnitAuras then
        return nil, nil
    end

    for i = 1, #spellIDs do
        local spellID = spellIDs[i]
        if type(spellID) == "number" and spellID > 0 and not IsSecret(spellID) then
            if unit == "player" and type(C_UnitAuras.GetPlayerAuraBySpellID) == "function" then
                local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
                if ok and type(auraData) == "table" then
                    return spellID, auraData.auraInstanceID
                end
            end

            if type(C_UnitAuras.GetUnitAuraBySpellID) == "function" then
                local ok, auraData = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, spellID)
                if ok and type(auraData) == "table" then
                    return spellID, auraData.auraInstanceID
                end
            end
        end
    end

    return nil, nil
end

local function SafeGetSpellTexture(spellID)
    if type(spellID) ~= "number" or spellID <= 0 or not C_Spell or type(C_Spell.GetSpellTexture) ~= "function" then
        return nil
    end

    local ok, texture = pcall(C_Spell.GetSpellTexture, spellID)
    if ok and not IsSecret(texture) and texture ~= nil then
        return texture
    end

    return nil
end

local function GetAuraDurationObject(unit, auraInstanceID)
    if not C_UnitAuras or type(C_UnitAuras.GetAuraDuration) ~= "function" then
        return nil
    end
    if type(unit) ~= "string" or unit == "" or auraInstanceID == nil then
        return nil
    end

    local ok, durationObject = pcall(C_UnitAuras.GetAuraDuration, unit, auraInstanceID)
    if ok and durationObject ~= nil then
        return durationObject
    end

    return nil
end

local function CopyActivePayload(payload)
    if type(payload) ~= "table" then
        return nil
    end

    return {
        cooldownID = payload.cooldownID,
        icon = payload.icon,
        duration = payload.duration,
        auraUnit = payload.auraUnit,
        auraInstanceID = payload.auraInstanceID,
        activeStateToken = payload.activeStateToken,
        cooldownStartTime = payload.cooldownStartTime,
        cooldownDuration = payload.cooldownDuration,
        cooldownModRate = payload.cooldownModRate,
        source = payload.source,
    }
end

local function BuildAssignedBucketMap(cooldownIDs)
    local bucketMap = {}
    local assignments = CDM.GetCurrentAssignments and CDM:GetCurrentAssignments()
    if type(assignments) ~= "table" then
        return bucketMap
    end

    local tracked = {}
    if type(cooldownIDs) == "table" then
        for i = 1, #cooldownIDs do
            local cooldownID = cooldownIDs[i]
            if type(cooldownID) == "number" and cooldownID > 0 then
                tracked[cooldownID] = true
            end
        end
    end

    for i = 1, #CDM.TRACKER_BUCKETS do
        local bucket = CDM.TRACKER_BUCKETS[i]
        local ids = assignments[bucket]
        if type(ids) == "table" then
            for n = 1, #ids do
                local cooldownID = ids[n]
                if tracked[cooldownID] then
                    local buckets = bucketMap[cooldownID]
                    if not buckets then
                        buckets = {}
                        bucketMap[cooldownID] = buckets
                    end
                    buckets[#buckets + 1] = bucket
                end
            end
        end
    end

    return bucketMap
end

local function BeginRuntimeDebugSnapshot(reason, cooldownIDs, targetAuras, totemMap)
    if not runtimeDebugState.enabled then
        runtimeDebugState.buildingSnapshot = nil
        return nil
    end

    local playerAuraSummary, playerAuraUnknownSummary = BuildAuraCacheSummary("player")
    local targetAuraSummary, targetAuraUnknownSummary = BuildAuraCacheSummary("target")

    local snapshot = {
        reason = reason or "unknown",
        timestamp = GetTime(),
        inCombat = InCombatLockdown and InCombatLockdown() and true or false,
        cooldownIDs = {},
        cooldowns = {},
        bucketMap = BuildAssignedBucketMap(cooldownIDs),
        playerAuraCacheCount = CountTableEntries(unitAuraCache.player.byInstanceID),
        targetAuraCacheCount = CountTableEntries(unitAuraCache.target.byInstanceID),
        targetAuraScanCount = type(targetAuras) == "table" and #targetAuras or 0,
        totemCount = CountTableEntries(totemMap),
        playerAuraSummary = playerAuraSummary,
        playerAuraUnknownSummary = playerAuraUnknownSummary,
        targetAuraSummary = targetAuraSummary,
        targetAuraUnknownSummary = targetAuraUnknownSummary,
        totemSummary = BuildTotemSummary(totemMap),
        livePlayerAuraScan = BuildLiveAuraScan("player"),
        liveTargetAuraScan = BuildLiveAuraScan("target", "HARMFUL|PLAYER"),
        activeCount = 0,
    }

    if type(cooldownIDs) == "table" then
        for i = 1, #cooldownIDs do
            local cooldownID = cooldownIDs[i]
            if type(cooldownID) == "number" and cooldownID > 0 then
                snapshot.cooldownIDs[#snapshot.cooldownIDs + 1] = cooldownID
            end
        end
    end

    runtimeDebugState.buildingSnapshot = snapshot
    return snapshot
end

local function FinalizeRuntimeDebugSnapshot(activeMap)
    local snapshot = runtimeDebugState.buildingSnapshot
    if not snapshot then
        return
    end

    snapshot.activeCount = CountTableEntries(activeMap)
    runtimeDebugState.lastSnapshot = snapshot
    if snapshot.inCombat then
        runtimeDebugState.lastCombatSnapshot = snapshot
    end
    runtimeDebugState.buildingSnapshot = nil
end

local function EnsureCooldownDebugRecord(cooldownID, info)
    local snapshot = runtimeDebugState.buildingSnapshot
    if not snapshot or type(cooldownID) ~= "number" or cooldownID <= 0 then
        return nil
    end

    local record = snapshot.cooldowns[cooldownID]
    if record then
        return record
    end

    local canUseAura = false
    local associatedSpellIDs = {}
    local linkedSpellIDs = {}
    if type(info) == "table" then
        canUseAura = CDM.CanUseAuraForCooldown and CDM:CanUseAuraForCooldown(info) and true or false
        if CDM.GetAssociatedSpellIDs then
            associatedSpellIDs = CDM:GetAssociatedSpellIDs(info) or {}
        end
        if type(info.linkedSpellIDs) == "table" then
            for i = 1, #info.linkedSpellIDs do
                linkedSpellIDs[#linkedSpellIDs + 1] = info.linkedSpellIDs[i]
            end
        end
    end

    record = {
        cooldownID = cooldownID,
        buckets = snapshot.bucketMap[cooldownID] or {},
        infoFound = type(info) == "table",
        canUseAura = canUseAura,
        selfAura = type(info) == "table" and info.selfAura or nil,
        spellID = type(info) == "table" and info.spellID or nil,
        overrideSpellID = type(info) == "table" and info.overrideSpellID or nil,
        overrideTooltipSpellID = type(info) == "table" and info.overrideTooltipSpellID or nil,
        associatedSpellIDs = associatedSpellIDs,
        linkedSpellIDs = linkedSpellIDs,
        status = "unresolved",
        playerAuraSpellID = nil,
        playerAuraInstanceID = nil,
        targetAuraSpellID = nil,
        targetAuraInstanceID = nil,
        totemSpellID = nil,
        totemSlot = nil,
        durationObject = nil,
        auraUnit = nil,
        cachedFallback = false,
        resultSource = nil,
        activeStateToken = nil,
        directPlayerMatchSpellID = nil,
        directPlayerMatchInstanceID = nil,
        directTargetMatchSpellID = nil,
        directTargetMatchInstanceID = nil,
    }

    if #associatedSpellIDs > 0 then
        record.directPlayerMatchSpellID, record.directPlayerMatchInstanceID = FindDirectAuraMatch("player", associatedSpellIDs)
        record.directTargetMatchSpellID, record.directTargetMatchInstanceID = FindDirectAuraMatch("target", associatedSpellIDs, "HARMFUL|PLAYER")
    end

    snapshot.cooldowns[cooldownID] = record
    return record
end

GetUnitAuraBucket = function(unit)
    return unitAuraCache[unit]
end

local function ClearUnitAuraBucket(unit)
    local bucket = GetUnitAuraBucket(unit)
    if not bucket then
        return
    end

    for key in pairs(bucket.bySpellID) do
        bucket.bySpellID[key] = nil
    end
    for key in pairs(bucket.byInstanceID) do
        bucket.byInstanceID[key] = nil
    end
    for key in pairs(bucket.spellInstances) do
        bucket.spellInstances[key] = nil
    end
end

local function BuildCachedAuraList(unit)
    local bucket = GetUnitAuraBucket(unit)
    if not bucket then
        return {}
    end

    local auraList = {}
    for auraInstanceID, auraData in pairs(bucket.byInstanceID) do
        if type(auraInstanceID) == "number"
            and not IsSecret(auraInstanceID)
            and type(auraData) == "table"
        then
            auraList[#auraList + 1] = auraData
        end
    end

    return auraList
end

GetAuraSpellIDValue = function(auraData)
    if type(auraData) ~= "table" then
        return nil
    end

    local spellID = auraData.spellId
    if type(spellID) == "number" and not IsSecret(spellID) and spellID > 0 then
        return spellID
    end

    spellID = auraData.spellID
    if type(spellID) == "number" and not IsSecret(spellID) and spellID > 0 then
        return spellID
    end

    return nil
end

local function StoreAuraData(unit, auraData)
    local bucket = GetUnitAuraBucket(unit)
    if not bucket or type(auraData) ~= "table" then
        return
    end

    if unit == "target" then
        local sourceUnit = auraData.sourceUnit
        if not IsSecret(sourceUnit) and sourceUnit ~= nil and sourceUnit ~= "player" then
            return
        end
    end

    local spellID = GetAuraSpellIDValue(auraData)
    local auraInstanceID = auraData.auraInstanceID
    if not spellID or type(auraInstanceID) ~= "number" or IsSecret(auraInstanceID) or auraInstanceID <= 0 then
        return
    end

    bucket.byInstanceID[auraInstanceID] = auraData

    local spellInstances = bucket.spellInstances[spellID]
    if not spellInstances then
        spellInstances = {}
        bucket.spellInstances[spellID] = spellInstances
    end
    spellInstances[auraInstanceID] = auraData
    bucket.bySpellID[spellID] = auraData
end

local function RemoveAuraInstance(unit, auraInstanceID)
    local bucket = GetUnitAuraBucket(unit)
    if not bucket or type(auraInstanceID) ~= "number" or IsSecret(auraInstanceID) then
        return
    end

    local auraData = bucket.byInstanceID[auraInstanceID]
    if not auraData then
        return
    end

    local spellID = GetAuraSpellIDValue(auraData)
    bucket.byInstanceID[auraInstanceID] = nil

    if spellID then
        local spellInstances = bucket.spellInstances[spellID]
        if spellInstances then
            spellInstances[auraInstanceID] = nil

            local replacement = nil
            for _, instanceAura in pairs(spellInstances) do
                replacement = instanceAura
                break
            end

            if replacement then
                bucket.bySpellID[spellID] = replacement
            else
                bucket.bySpellID[spellID] = nil
                bucket.spellInstances[spellID] = nil
            end
        end
    end
end

local function CacheAuraTable(unit, auraTable)
    if type(auraTable) ~= "table" then
        return
    end

    for i = 1, #auraTable do
        StoreAuraData(unit, auraTable[i])
    end
end

local function PrimeUnitAuraCache(unit)
    local bucket = GetUnitAuraBucket(unit)
    if not bucket or not C_UnitAuras or type(C_UnitAuras.GetUnitAuras) ~= "function" then
        return
    end

    ClearUnitAuraBucket(unit)

    local filter = "HELPFUL"
    if unit == "target" then
        filter = "HARMFUL|PLAYER"
    end

    local ok, auraTable = pcall(C_UnitAuras.GetUnitAuras, unit, filter)
    if ok and type(auraTable) == "table" then
        CacheAuraTable(unit, auraTable)
    end
end

local function HandleUnitAuraUpdate(unit, unitAuraUpdateInfo)
    local bucket = GetUnitAuraBucket(unit)
    if not bucket then
        return
    end

    if type(unitAuraUpdateInfo) ~= "table" or unitAuraUpdateInfo.isFullUpdate then
        PrimeUnitAuraCache(unit)
        return
    end

    if type(unitAuraUpdateInfo.removedAuraInstanceIDs) == "table" then
        for i = 1, #unitAuraUpdateInfo.removedAuraInstanceIDs do
            RemoveAuraInstance(unit, unitAuraUpdateInfo.removedAuraInstanceIDs[i])
        end
    end

    if type(unitAuraUpdateInfo.updatedAuraInstanceIDs) == "table"
        and C_UnitAuras
        and type(C_UnitAuras.GetAuraDataByAuraInstanceID) == "function"
    then
        for i = 1, #unitAuraUpdateInfo.updatedAuraInstanceIDs do
            local auraInstanceID = unitAuraUpdateInfo.updatedAuraInstanceIDs[i]
            if type(auraInstanceID) == "number" and not IsSecret(auraInstanceID) and auraInstanceID > 0 then
                local ok, auraData = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, auraInstanceID)
                if ok and type(auraData) == "table" then
                    StoreAuraData(unit, auraData)
                end
            end
        end
    end

    if type(unitAuraUpdateInfo.addedAuras) == "table" then
        CacheAuraTable(unit, unitAuraUpdateInfo.addedAuras)
    end
end

local function IsPayloadWindowActive(payload, nowSeconds)
    if type(payload) ~= "table" then
        return false
    end

    local startTime = payload.cooldownStartTime
    local duration = payload.cooldownDuration
    if type(startTime) == "number"
        and type(duration) == "number"
        and not IsSecret(startTime)
        and not IsSecret(duration)
        and duration > 0
    then
        return (startTime + duration) > (nowSeconds or GetTime())
    end

    if payload.duration ~= nil and payload.auraUnit and payload.auraInstanceID ~= nil then
        return true
    end

    return false
end

local function StoreActivePayload(cooldownID, payload)
    if type(cooldownID) ~= "number" or cooldownID <= 0 then
        return
    end

    local copied = CopyActivePayload(payload)
    if copied then
        activePayloadCache[cooldownID] = copied
    end
end

local function ClearActivePayload(cooldownID)
    if type(cooldownID) == "number" and cooldownID > 0 then
        activePayloadCache[cooldownID] = nil
    end
end

local function GetCachedActivePayload(cooldownID, nowSeconds)
    local cached = activePayloadCache[cooldownID]
    if type(cached) ~= "table" then
        return nil
    end

    if not IsPayloadWindowActive(cached, nowSeconds) then
        activePayloadCache[cooldownID] = nil
        return nil
    end

    return CopyActivePayload(cached)
end

local function BuildPlayerTotemMap()
    local totemMap = {}
    if type(GetNumTotemSlots) ~= "function" or type(GetTotemInfo) ~= "function" then
        return totemMap
    end

    local slotCount = GetNumTotemSlots()
    if IsSecret(slotCount) or type(slotCount) ~= "number" or slotCount <= 0 then
        return totemMap
    end

    for slot = 1, slotCount do
        local ok, hasTotem, name, startTime, duration, icon, modRate, spellID = pcall(GetTotemInfo, slot)
        local hasUsableTotem = ok and not IsSecret(hasTotem) and hasTotem == true
        if hasUsableTotem and not IsSecret(spellID) and type(spellID) == "number" and spellID > 0 then
            local rawStartTime = type(startTime) == "number" and startTime or 0
            local rawDuration = type(duration) == "number" and duration or 0
            local expirationTime = nil
            if not IsSecret(rawStartTime) and not IsSecret(rawDuration) then
                expirationTime = rawStartTime + rawDuration
            end
            local totemInfo = {
                spellID = spellID,
                slot = slot,
                name = (not IsSecret(name) and name) or nil,
                startTime = rawStartTime,
                duration = rawDuration,
                expirationTime = expirationTime,
                icon = (not IsSecret(icon) and icon) or nil,
                modRate = (type(modRate) == "number" and modRate) or 1,
            }

            local existing = totemMap[spellID]
            if not existing then
                totemMap[spellID] = totemInfo
            elseif existing.expirationTime == nil then
                if totemInfo.expirationTime ~= nil then
                    totemMap[spellID] = totemInfo
                end
            elseif totemInfo.expirationTime ~= nil and totemInfo.expirationTime > existing.expirationTime then
                totemMap[spellID] = totemInfo
            end
        end
    end

    return totemMap
end

local function GetAuraDataBySpellID(unit, spellID)
    if not C_UnitAuras or type(unit) ~= "string" or unit == "" then
        return nil
    end
    if type(spellID) ~= "number" or IsSecret(spellID) or spellID <= 0 then
        return nil
    end

    local bucket = GetUnitAuraBucket(unit)
    if bucket then
        local cachedAura = bucket.bySpellID[spellID]
        if type(cachedAura) == "table" then
            return cachedAura
        end
    end

    if unit == "player" and type(C_UnitAuras.GetPlayerAuraBySpellID) == "function" then
        local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
        if ok and type(auraData) == "table" then
            return auraData
        end
    end

    if type(C_UnitAuras.GetUnitAuraBySpellID) == "function" then
        local ok, auraData = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, spellID)
        if ok and type(auraData) == "table" then
            return auraData
        end
    end

    return nil
end

local function ResolveLinkedPlayerAura(info)
    if type(info) ~= "table" or type(info.linkedSpellIDs) ~= "table" then
        return nil, nil
    end

    for i = 1, #info.linkedSpellIDs do
        local spellID = info.linkedSpellIDs[i]
        local auraData = GetAuraDataBySpellID("player", spellID)
        if auraData then
            return auraData, spellID
        end
    end

    return nil, nil
end

local function ResolvePlayerAuraForInfo(info)
    if type(info) ~= "table" or not CDM:CanUseAuraForCooldown(info) then
        return nil, nil
    end

    local linkedAura, linkedSpellID = ResolveLinkedPlayerAura(info)
    if linkedAura then
        return linkedAura, linkedSpellID
    end

    local spellOrder = {
        info.overrideTooltipSpellID,
        info.overrideSpellID,
        info.spellID,
    }

    for i = 1, #spellOrder do
        local spellID = spellOrder[i]
        local auraData = GetAuraDataBySpellID("player", spellID)
        if auraData then
            return auraData, spellID
        end
    end

    return nil, nil
end

local function ResolveTargetAuraForInfo(info, targetAuras)
    if type(info) ~= "table" or not CDM:CanUseAuraForCooldown(info) then
        return nil
    end

    local associatedSpellIDs = CDM:GetAssociatedSpellIDs(info)
    for i = 1, #associatedSpellIDs do
        local auraData = GetAuraDataBySpellID("target", associatedSpellIDs[i])
        if auraData then
            return auraData
        end
    end

    local associatedSpellSet = {}
    for i = 1, #associatedSpellIDs do
        associatedSpellSet[associatedSpellIDs[i]] = true
    end

    for i = 1, #targetAuras do
        local auraData = targetAuras[i]
        if type(auraData) == "table" then
            local spellID = auraData.spellId
            if type(spellID) == "number" and not IsSecret(spellID) and associatedSpellSet[spellID] then
                return auraData
            end
        end
    end

    return nil
end

local function ResolveTotemForInfo(info, totemMap)
    if type(info) ~= "table" or not CDM:CanUseAuraForCooldown(info) then
        return nil
    end

    local associatedSpellIDs = CDM:GetAssociatedSpellIDs(info)
    for i = 1, #associatedSpellIDs do
        local totemInfo = totemMap[associatedSpellIDs[i]]
        if totemInfo then
            return totemInfo
        end
    end

    return nil
end

local function ResolveDisplaySpellID(info, runtimeState)
    if type(runtimeState) == "table" then
        local auraSpellID = runtimeState.auraSpellID
        if type(auraSpellID) == "number" and not IsSecret(auraSpellID) and auraSpellID > 0 then
            return auraSpellID
        end

        local linkedSpellID = runtimeState.linkedSpellID
        if type(linkedSpellID) == "number" and not IsSecret(linkedSpellID) and linkedSpellID > 0 then
            return linkedSpellID
        end
    end

    if type(info) ~= "table" then
        return nil
    end

    local spellOrder = {
        info.overrideTooltipSpellID,
        info.overrideSpellID,
        info.spellID,
    }

    for i = 1, #spellOrder do
        local spellID = spellOrder[i]
        if type(spellID) == "number" and not IsSecret(spellID) and spellID > 0 then
            return spellID
        end
    end

    return nil
end

local function BuildActiveStateToken(kind, ...)
    local parts = { kind }
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if IsSecret(value) then
            parts[#parts + 1] = "secret"
        elseif value == nil then
            parts[#parts + 1] = "nil"
        else
            parts[#parts + 1] = tostring(value)
        end
    end
    return tconcat(parts, ":")
end

local function ResolveAuraOrTotemPayload(cooldownID, info, targetAuras, totemMap, debugRecord)
    local runtimeState = {}

    local totemInfo = ResolveTotemForInfo(info, totemMap)
    if totemInfo then
        if debugRecord then
            debugRecord.totemSpellID = totemInfo.spellID
            debugRecord.totemSlot = totemInfo.slot
            debugRecord.resultSource = "totem"
            debugRecord.status = "resolved"
        end
        runtimeState.totemSpellID = totemInfo.spellID
        local icon = totemInfo.icon or SafeGetSpellTexture(totemInfo.spellID) or DEFAULT_ICON_TEXTURE
        return {
            cooldownID = cooldownID,
            icon = icon,
            auraUnit = "player",
            activeStateToken = "totem:" .. tostring(totemInfo.slot) .. ":" .. tostring(totemInfo.spellID),
            cooldownStartTime = totemInfo.startTime,
            cooldownDuration = totemInfo.duration,
            cooldownModRate = totemInfo.modRate or 1,
            source = "resolver",
        }, runtimeState
    end

    local auraData, linkedSpellID = ResolvePlayerAuraForInfo(info)
    local auraUnit = "player"
    if debugRecord and auraData then
        debugRecord.playerAuraSpellID = GetAuraSpellIDValue(auraData)
        debugRecord.playerAuraInstanceID = auraData.auraInstanceID
    end
    if not auraData then
        auraData = ResolveTargetAuraForInfo(info, targetAuras)
        auraUnit = auraData and "target" or nil
        if debugRecord and auraData then
            debugRecord.targetAuraSpellID = GetAuraSpellIDValue(auraData)
            debugRecord.targetAuraInstanceID = auraData.auraInstanceID
        end
    end

    if not auraData then
        if debugRecord and debugRecord.status ~= "resolved" then
            debugRecord.status = "no-runtime-match"
        end
        return nil, runtimeState
    end

    local auraSpellID = auraData.spellId
    local auraInstanceID = auraData.auraInstanceID
    local durationObject = GetAuraDurationObject(auraUnit, auraInstanceID)
    if debugRecord then
        debugRecord.auraUnit = auraUnit
        debugRecord.durationObject = durationObject and true or false
        debugRecord.resultSource = durationObject and "duration-object" or "time-window"
        debugRecord.status = "resolved"
    end
    local icon = SafeGetSpellTexture(auraSpellID) or SafeGetSpellTexture(linkedSpellID) or SafeGetSpellTexture(ResolveDisplaySpellID(info, runtimeState)) or DEFAULT_ICON_TEXTURE

    runtimeState.auraSpellID = auraSpellID
    runtimeState.linkedSpellID = linkedSpellID

    local payload = {
        cooldownID = cooldownID,
        icon = icon,
        duration = durationObject,
        auraUnit = auraUnit,
        auraInstanceID = auraInstanceID,
        activeStateToken = BuildActiveStateToken("aura", auraUnit or "none", auraInstanceID or auraSpellID or cooldownID),
        source = "resolver",
    }

    local duration = auraData.duration
    local expirationTime = auraData.expirationTime
    local modRate = auraData.timeMod
    if type(duration) == "number"
        and type(expirationTime) == "number"
        and not IsSecret(duration)
        and not IsSecret(expirationTime)
        and duration > 0
        and expirationTime > 0
    then
        payload.cooldownStartTime = expirationTime - duration
        payload.cooldownDuration = duration
        payload.cooldownModRate = (type(modRate) == "number" and not IsSecret(modRate) and modRate) or 1
    end

    if debugRecord then
        debugRecord.activeStateToken = payload.activeStateToken
    end

    return payload, runtimeState
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function CDM:InvalidateRuntimeResolver()
    for cooldownID in pairs(activePayloadCache) do
        activePayloadCache[cooldownID] = nil
    end
    ClearUnitAuraBucket("player")
    ClearUnitAuraBucket("target")
end

function CDM:SetRuntimeDebugEnabled(enabled)
    runtimeDebugState.enabled = enabled and true or false
    if not runtimeDebugState.enabled then
        runtimeDebugState.buildingSnapshot = nil
    end
end

function CDM:IsRuntimeDebugEnabled()
    return runtimeDebugState.enabled and true or false
end

function CDM:ResetRuntimeDebugSnapshot()
    runtimeDebugState.lastSnapshot = nil
    runtimeDebugState.lastCombatSnapshot = nil
    runtimeDebugState.buildingSnapshot = nil
    runtimeDebugState.recentAuraEvents = {}
end

function CDM:RecordRuntimeDebugAuraEvent(subEvent, spellID, sourceName, destName, auraType)
    if not runtimeDebugState.enabled then
        return
    end

    local token = FormatSpellToken(spellID) or SafeValueString(spellID)
    local line = SafeValueString(subEvent)
        .. " spell=" .. token
        .. " source=" .. SafeValueString(sourceName)
        .. " dest=" .. SafeValueString(destName)
        .. " auraType=" .. SafeValueString(auraType)
    PushRecentAuraEvent(line)
end

function CDM:GetRuntimeDebugSnapshotLines()
    local lines = {
        "CDM runtime debug: " .. (runtimeDebugState.enabled and "ON" or "OFF"),
    }

    if self.auraProbeInitialized then
        lines[#lines + 1] = "Hidden viewer bridge is active; this standalone snapshot is secondary."
    end

    local snapshot = runtimeDebugState.lastCombatSnapshot or runtimeDebugState.lastSnapshot
    if not snapshot then
        lines[#lines + 1] = "No snapshot recorded yet."
        return lines
    end

    if runtimeDebugState.lastCombatSnapshot then
        lines[#lines + 1] = "Showing last in-combat snapshot."
    elseif runtimeDebugState.lastSnapshot then
        lines[#lines + 1] = "No in-combat snapshot recorded yet. Showing latest snapshot."
    end

    lines[#lines + 1] = "Snapshot reason="
        .. SafeValueString(snapshot.reason)
        .. " inCombat=" .. SafeBoolString(snapshot.inCombat)
        .. " assigned=" .. SafeValueString(#snapshot.cooldownIDs)
        .. " active=" .. SafeValueString(snapshot.activeCount)
        .. " playerCache=" .. SafeValueString(snapshot.playerAuraCacheCount)
        .. " targetCache=" .. SafeValueString(snapshot.targetAuraCacheCount)
        .. " targetScan=" .. SafeValueString(snapshot.targetAuraScanCount)
        .. " totems=" .. SafeValueString(snapshot.totemCount)
    lines[#lines + 1] = "Player cache spells=" .. JoinValueList(snapshot.playerAuraSummary)
    lines[#lines + 1] = "Player cache unknown=" .. JoinValueList(snapshot.playerAuraUnknownSummary)
    lines[#lines + 1] = "Target cache spells=" .. JoinValueList(snapshot.targetAuraSummary)
    lines[#lines + 1] = "Target cache unknown=" .. JoinValueList(snapshot.targetAuraUnknownSummary)
    lines[#lines + 1] = "Totem spells=" .. JoinValueList(snapshot.totemSummary)
    lines[#lines + 1] = "Live player scan count=" .. SafeValueString(snapshot.livePlayerAuraScan.count)
        .. " spells=" .. JoinValueList(snapshot.livePlayerAuraScan.spells)
        .. " unknown=" .. JoinValueList(snapshot.livePlayerAuraScan.unknown)
    lines[#lines + 1] = "Live target scan count=" .. SafeValueString(snapshot.liveTargetAuraScan.count)
        .. " spells=" .. JoinValueList(snapshot.liveTargetAuraScan.spells)
        .. " unknown=" .. JoinValueList(snapshot.liveTargetAuraScan.unknown)
    lines[#lines + 1] = "Recent aura events=" .. JoinValueList(runtimeDebugState.recentAuraEvents)

    for i = 1, #snapshot.cooldownIDs do
        local cooldownID = snapshot.cooldownIDs[i]
        local record = snapshot.cooldowns[cooldownID]
        if record then
            lines[#lines + 1] = "CD " .. cooldownID
                .. " buckets=" .. JoinValueList(record.buckets)
                .. " status=" .. SafeValueString(record.status)
                .. " info=" .. SafeBoolString(record.infoFound)
                .. " canAura=" .. SafeBoolString(record.canUseAura)
                .. " selfAura=" .. SafeValueString(record.selfAura)
                .. " spell=" .. (FormatSpellToken(record.spellID) or SafeValueString(record.spellID))
                .. " override=" .. (FormatSpellToken(record.overrideSpellID) or SafeValueString(record.overrideSpellID))
                .. " tooltip=" .. (FormatSpellToken(record.overrideTooltipSpellID) or SafeValueString(record.overrideTooltipSpellID))
                .. " assoc=" .. JoinValueList(record.associatedSpellIDs)
                .. " linked=" .. JoinValueList(record.linkedSpellIDs)
                .. " directPlayer=" .. (FormatSpellToken(record.directPlayerMatchSpellID, record.directPlayerMatchInstanceID) or (SafeValueString(record.directPlayerMatchSpellID) .. "@" .. SafeValueString(record.directPlayerMatchInstanceID)))
                .. " directTarget=" .. (FormatSpellToken(record.directTargetMatchSpellID, record.directTargetMatchInstanceID) or (SafeValueString(record.directTargetMatchSpellID) .. "@" .. SafeValueString(record.directTargetMatchInstanceID)))
                .. " player=" .. (FormatSpellToken(record.playerAuraSpellID, record.playerAuraInstanceID) or (SafeValueString(record.playerAuraSpellID) .. "@" .. SafeValueString(record.playerAuraInstanceID)))
                .. " target=" .. (FormatSpellToken(record.targetAuraSpellID, record.targetAuraInstanceID) or (SafeValueString(record.targetAuraSpellID) .. "@" .. SafeValueString(record.targetAuraInstanceID)))
                .. " totem=" .. (FormatSpellToken(record.totemSpellID) or SafeValueString(record.totemSpellID)) .. "@" .. SafeValueString(record.totemSlot)
                .. " auraUnit=" .. SafeValueString(record.auraUnit)
                .. " durationObj=" .. SafeBoolString(record.durationObject)
                .. " cached=" .. SafeBoolString(record.cachedFallback)
                .. " source=" .. SafeValueString(record.resultSource)
        else
            lines[#lines + 1] = "CD " .. cooldownID .. " status=no-record"
        end
    end

    return lines
end

function CDM:ResolveActiveCooldownPayload(cooldownID, targetAuras, totemMap, nowSeconds)
    local info = self:GetCooldownInfo(cooldownID)
    local debugRecord = EnsureCooldownDebugRecord(cooldownID, info)
    if type(info) ~= "table" then
        if debugRecord then
            debugRecord.status = "missing-info"
        end
        if not (InCombatLockdown and InCombatLockdown()) then
            ClearActivePayload(cooldownID)
        end
        return nil
    end

    local auraPayload = ResolveAuraOrTotemPayload(cooldownID, info, targetAuras or {}, totemMap or {}, debugRecord)
    if auraPayload then
        if debugRecord and auraPayload.activeStateToken then
            debugRecord.activeStateToken = auraPayload.activeStateToken
        end
        StoreActivePayload(cooldownID, auraPayload)
        return auraPayload
    end

    if InCombatLockdown and InCombatLockdown() then
        local cachedPayload = GetCachedActivePayload(cooldownID, nowSeconds)
        if cachedPayload then
            if debugRecord then
                debugRecord.cachedFallback = true
                debugRecord.status = "cached-fallback"
                debugRecord.resultSource = cachedPayload.source or "cache"
                debugRecord.activeStateToken = cachedPayload.activeStateToken
            end
            return cachedPayload
        end
    end

    if debugRecord and debugRecord.status == "unresolved" then
        debugRecord.status = "inactive"
    end
    ClearActivePayload(cooldownID)
    return nil
end


function CDM:_ProbeCooldownAuraInternal(cooldownID)
    local totemMap = BuildPlayerTotemMap()
    local targetAuras = BuildCachedAuraList("target")
    BeginRuntimeDebugSnapshot("probe", { cooldownID }, targetAuras, totemMap)
    local payload = self:ResolveActiveCooldownPayload(cooldownID, targetAuras, totemMap, GetTime())
    FinalizeRuntimeDebugSnapshot(payload and { [cooldownID] = payload } or nil)
    return payload
end


function CDM:_GetActiveAuraMapInternal(cooldownIDs)
    local activeMap = {}
    if type(cooldownIDs) ~= "table" or #cooldownIDs == 0 then
        return activeMap
    end

    local nowSeconds = GetTime()
    local totemMap = BuildPlayerTotemMap()
    local targetAuras = BuildCachedAuraList("target")
    BeginRuntimeDebugSnapshot("active-map", cooldownIDs, targetAuras, totemMap)

    for i = 1, #cooldownIDs do
        local cooldownID = cooldownIDs[i]
        if type(cooldownID) == "number" and cooldownID > 0 then
            local payload = self:ResolveActiveCooldownPayload(cooldownID, targetAuras, totemMap, nowSeconds)
            if payload then
                activeMap[cooldownID] = payload
            end
        end
    end

    FinalizeRuntimeDebugSnapshot(activeMap)

    return activeMap
end


function CDM:HandleUnitAuraUpdate(unit, unitAuraUpdateInfo)
    if unit ~= "player" and unit ~= "target" then
        return
    end
    HandleUnitAuraUpdate(unit, unitAuraUpdateInfo)
end


function CDM:PrimeRuntimeAuraCache(unit)
    if unit == nil then
        PrimeUnitAuraCache("player")
        PrimeUnitAuraCache("target")
        return
    end

    if unit == "player" or unit == "target" then
        PrimeUnitAuraCache(unit)
    end
end


function CDM:ClearRuntimeAuraCache(unit)
    if unit == nil then
        ClearUnitAuraBucket("player")
        ClearUnitAuraBucket("target")
        return
    end

    if unit == "player" or unit == "target" then
        ClearUnitAuraBucket(unit)
    end
end

CDM._ProbeCooldownAuraFallbackInternal = CDM._ProbeCooldownAuraInternal
CDM._GetActiveAuraMapFallbackInternal = CDM._GetActiveAuraMapInternal
