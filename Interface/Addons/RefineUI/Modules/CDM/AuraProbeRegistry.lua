----------------------------------------------------------------------------------------
-- CDM Component: AuraProbeRegistry
-- Description: Aura probe registry, frame indexing, payload synthesis, and reconcile flow.
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
local pcall = pcall
local pairs = pairs
local next = next
local setmetatable = setmetatable
local tostring = tostring
local wipe = _G.wipe or table.wipe

local GetTime = GetTime
local C_Spell = C_Spell
local C_UnitAuras = C_UnitAuras
local C_Totem = C_Totem
local issecretvalue = _G.issecretvalue
local GetTotemInfo = _G.GetTotemInfo

if type(GetTotemInfo) ~= "function" and C_Totem and type(C_Totem.GetTotemInfo) == "function" then
    GetTotemInfo = C_Totem.GetTotemInfo
end

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local DEFAULT_ICON_TEXTURE = 134400
local RECONCILE_TIMER_KEY = CDM:BuildKey("AuraProbe", "Reconcile")
local AURA_VIEWER_NAMES = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}

local cooldownIconCache = {}
local ghostPayloadByCooldownID = {}
local cooldownIDLookupScratch = {}
local registeredFramesByCooldownID = {}
local registeredFrameCooldownID = setmetatable({}, { __mode = "k" })
local registeredFrameSpellIDs = setmetatable({}, { __mode = "k" })
local hiddenFrameGraceExpiry = setmetatable({}, { __mode = "k" })
local registryReconcileQueued = nil
local registryDirty = true
local dataChangedCallbackRegistered = false
local hookedViewers = setmetatable({}, { __mode = "k" })
local hookedFrames = setmetatable({}, { __mode = "k" })
local MarkRegistryDirty
local QueueRegistryReconcile

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function HasValue(value)
    if IsSecret(value) then
        return true
    end
    return value ~= nil
end

local function IsNonSecretNumber(value)
    if IsSecret(value) then
        return false
    end
    return type(value) == "number"
end

local function HasNumericValue(value)
    if IsSecret(value) then
        return true
    end
    return type(value) == "number"
end

local function HasPositiveNumericValue(value)
    if IsSecret(value) then
        return true
    end
    return type(value) == "number" and value > 0
end

local function HasTotemSlotValue(value)
    if IsSecret(value) then
        return true
    end
    return type(value) == "number" and value > 0
end

local function IsNonSecretTexture(value)
    if IsSecret(value) then
        return false
    end
    local valueType = type(value)
    return valueType == "string" or valueType == "number"
end

local function IsUnitToken(value)
    if IsSecret(value) then
        return false
    end
    return type(value) == "string" and value ~= ""
end

local function IsTextureLike(value)
    if IsSecret(value) then
        return false
    end
    local valueType = type(value)
    return valueType == "string" or valueType == "number"
end

local function HasAuraInstanceID(value)
    if IsSecret(value) then
        return true
    end
    if value == nil then
        return false
    end
    if type(value) == "number" and value == 0 then
        return false
    end
    return true
end

local function ResolveIconFromSpellID(spellID)
    if not IsNonSecretNumber(spellID) then
        return nil
    end
    if not C_Spell or type(C_Spell.GetSpellTexture) ~= "function" then
        return nil
    end

    local ok, texture = pcall(C_Spell.GetSpellTexture, spellID)
    if ok and IsNonSecretTexture(texture) then
        return texture
    end
    return nil
end

local function ResolveIconFromCooldownID(cooldownID)
    local cached = cooldownIconCache[cooldownID]
    if HasValue(cached) then
        return cached
    end

    local info = CDM:GetCooldownInfo(cooldownID)
    if type(info) ~= "table" then
        return nil
    end

    local texture = ResolveIconFromSpellID(CDM:ResolveCooldownSpellID(info))
    if IsNonSecretTexture(texture) then
        cooldownIconCache[cooldownID] = texture
    end
    return texture
end

local function ResolveFrameCooldownID(frame, hintedCooldownID)
    if IsNonSecretNumber(hintedCooldownID) and hintedCooldownID > 0 then
        return hintedCooldownID
    end

    if frame and type(frame.GetCooldownID) == "function" then
        local okCooldownID, resolvedCooldownID = pcall(frame.GetCooldownID, frame)
        if okCooldownID and IsNonSecretNumber(resolvedCooldownID) and resolvedCooldownID > 0 then
            return resolvedCooldownID
        end
    end

    return nil
end

local function AddResolvedSpellID(spellIDs, seen, spellID)
    if IsNonSecretNumber(spellID) and spellID > 0 and not seen[spellID] then
        seen[spellID] = true
        spellIDs[#spellIDs + 1] = spellID
    end
end

local function ResolveFrameAssociatedSpellIDs(frame)
    local cached = registeredFrameSpellIDs[frame]
    if type(cached) == "table" then
        return cached
    end

    local spellIDs = {}
    local seen = {}
    if not frame then
        return spellIDs
    end

    local function TryMethod(methodName)
        if type(frame[methodName]) ~= "function" then
            return
        end

        local ok, value = pcall(frame[methodName], frame)
        if ok then
            AddResolvedSpellID(spellIDs, seen, value)
        end
    end

    TryMethod("GetAuraSpellID")
    TryMethod("GetLinkedSpell")
    TryMethod("GetSpellID")
    TryMethod("GetBaseSpellID")

    local okAuraSpellID, auraSpellID = pcall(function()
        return frame.auraSpellID
    end)
    if okAuraSpellID then
        AddResolvedSpellID(spellIDs, seen, auraSpellID)
    end

    local okSpellID, rawSpellID = pcall(function()
        return frame.spellID
    end)
    if okSpellID then
        AddResolvedSpellID(spellIDs, seen, rawSpellID)
    end

    local okRangeSpellID, rangeSpellID = pcall(function()
        return frame.rangeCheckSpellID
    end)
    if okRangeSpellID then
        AddResolvedSpellID(spellIDs, seen, rangeSpellID)
    end

    if type(frame.GetCooldownInfo) == "function" then
        local okInfo, cooldownInfo = pcall(frame.GetCooldownInfo, frame)
        if okInfo and type(cooldownInfo) == "table" then
            AddResolvedSpellID(spellIDs, seen, cooldownInfo.linkedSpellID)
            AddResolvedSpellID(spellIDs, seen, cooldownInfo.overrideTooltipSpellID)
            AddResolvedSpellID(spellIDs, seen, cooldownInfo.overrideSpellID)
            AddResolvedSpellID(spellIDs, seen, cooldownInfo.spellID)
            if type(cooldownInfo.linkedSpellIDs) == "table" then
                for i = 1, #cooldownInfo.linkedSpellIDs do
                    AddResolvedSpellID(spellIDs, seen, cooldownInfo.linkedSpellIDs[i])
                end
            end
        end
    end

    registeredFrameSpellIDs[frame] = spellIDs
    return spellIDs
end

local function ResolveUniqueLookupCooldownID(cooldownIDSet)
    if type(cooldownIDSet) ~= "table" then
        return nil
    end

    local resolvedCooldownID
    for cooldownID in pairs(cooldownIDSet) do
        if not IsNonSecretNumber(cooldownID) or cooldownID <= 0 then
            return nil
        end
        if resolvedCooldownID and resolvedCooldownID ~= cooldownID then
            return nil
        end
        resolvedCooldownID = cooldownID
    end

    return resolvedCooldownID
end

local function ResolveUniqueSpellMatchedCooldownID(frame, spellIDLookup)
    if not frame or type(spellIDLookup) ~= "table" then
        return nil
    end

    -- Hidden Blizzard viewer items sometimes expose multiple related spell IDs.
    -- Only accept spell-based fallback when they collapse to one Refine assignment.
    local frameSpellIDs = ResolveFrameAssociatedSpellIDs(frame)
    local matchedCooldownID

    for i = 1, #frameSpellIDs do
        local spellID = frameSpellIDs[i]
        local spellCooldownIDs = spellIDLookup[spellID]
        if spellCooldownIDs then
            local resolvedCooldownID = ResolveUniqueLookupCooldownID(spellCooldownIDs)
            if not resolvedCooldownID then
                return nil
            end
            if matchedCooldownID and matchedCooldownID ~= resolvedCooldownID then
                return nil
            end
            matchedCooldownID = resolvedCooldownID
        end
    end

    return matchedCooldownID
end

local function ForEachViewerItemFrame(viewer, callback)
    if not viewer or type(callback) ~= "function" then
        return
    end

    local itemPool = viewer.itemFramePool
    if type(itemPool) == "table" and type(itemPool.EnumerateActive) == "function" then
        for itemFrame in itemPool:EnumerateActive() do
            callback(itemFrame)
        end
        return
    end

    if type(viewer.GetItemFrames) == "function" then
        local okFrames, itemFrames = pcall(viewer.GetItemFrames, viewer)
        if okFrames and type(itemFrames) == "table" then
            for i = 1, #itemFrames do
                callback(itemFrames[i])
            end
        end
    end
end

local function BuildTrackedCooldownIDSet(cooldownIDs)
    if wipe then
        wipe(cooldownIDLookupScratch)
    else
        for key in pairs(cooldownIDLookupScratch) do
            cooldownIDLookupScratch[key] = nil
        end
    end

    if type(cooldownIDs) ~= "table" then
        return cooldownIDLookupScratch
    end

    for i = 1, #cooldownIDs do
        local cooldownID = cooldownIDs[i]
        if IsNonSecretNumber(cooldownID) and cooldownID > 0 then
            cooldownIDLookupScratch[cooldownID] = true
        end
    end

    return cooldownIDLookupScratch
end

local function ClearFrameRegistration(frame)
    if not frame then
        return
    end

    local cooldownID = registeredFrameCooldownID[frame]
    if IsNonSecretNumber(cooldownID) and cooldownID > 0 then
        local frameSet = registeredFramesByCooldownID[cooldownID]
        if type(frameSet) == "table" then
            frameSet[frame] = nil
            if next(frameSet) == nil then
                registeredFramesByCooldownID[cooldownID] = nil
            end
        end
    end

    registeredFrameCooldownID[frame] = nil
    registeredFrameSpellIDs[frame] = nil
    hiddenFrameGraceExpiry[frame] = nil
end

local function RegisterFrameForCooldown(frame, cooldownID)
    if not frame then
        return
    end
    if not IsNonSecretNumber(cooldownID) or cooldownID <= 0 then
        ClearFrameRegistration(frame)
        return
    end

    local currentCooldownID = registeredFrameCooldownID[frame]
    if currentCooldownID == cooldownID then
        local currentSet = registeredFramesByCooldownID[cooldownID]
        if type(currentSet) ~= "table" then
            currentSet = {}
            registeredFramesByCooldownID[cooldownID] = currentSet
        end
        currentSet[frame] = true
        return
    end

    ClearFrameRegistration(frame)

    local frameSet = registeredFramesByCooldownID[cooldownID]
    if type(frameSet) ~= "table" then
        frameSet = {}
        registeredFramesByCooldownID[cooldownID] = frameSet
    end

    frameSet[frame] = true
    registeredFrameCooldownID[frame] = cooldownID
    hiddenFrameGraceExpiry[frame] = nil
end

local function ClearRegistryFrames()
    for frame in pairs(registeredFrameCooldownID) do
        ClearFrameRegistration(frame)
    end
end

local function GetAssignedSpellLookup()
    local snapshot = CDM.GetAssignedCooldownSnapshot and CDM:GetAssignedCooldownSnapshot() or nil
    if type(snapshot) ~= "table" or type(snapshot.associatedSpellToCooldownIDs) ~= "table" then
        return {}
    end
    return snapshot.associatedSpellToCooldownIDs
end

local function ResolveTrackedCooldownIDForFrame(frame, trackedCooldownIDSet, spellLookup)
    local directCooldownID = ResolveFrameCooldownID(frame, registeredFrameCooldownID[frame])
    if IsNonSecretNumber(directCooldownID) and trackedCooldownIDSet[directCooldownID] then
        return directCooldownID
    end

    return ResolveUniqueSpellMatchedCooldownID(frame, spellLookup)
end

local function GetFrameHideGraceDuration()
    local ttl = CDM.GetPayloadGhostTTL and CDM:GetPayloadGhostTTL() or 0.20
    if type(ttl) ~= "number" then
        ttl = 0.20
    end
    if ttl < 0.20 then
        ttl = 0.20
    elseif ttl > 0.35 then
        ttl = 0.35
    end
    return ttl
end

local function MarkFrameHidden(frame)
    if not frame then
        return
    end

    hiddenFrameGraceExpiry[frame] = GetTime() + GetFrameHideGraceDuration()
end

local function RefreshRegisteredFrame(frame, trackedCooldownIDSet, spellLookup)
    if not frame then
        return nil
    end

    registeredFrameSpellIDs[frame] = nil

    if type(frame.IsShown) == "function" then
        local okShown, shown = pcall(frame.IsShown, frame)
        if okShown and shown == false then
            local expiresAt = hiddenFrameGraceExpiry[frame]
            if type(expiresAt) ~= "number" then
                MarkFrameHidden(frame)
                return registeredFrameCooldownID[frame]
            end
            if expiresAt > GetTime() then
                return registeredFrameCooldownID[frame]
            end
            ClearFrameRegistration(frame)
            return nil
        end
    end

    hiddenFrameGraceExpiry[frame] = nil
    local cooldownID = ResolveTrackedCooldownIDForFrame(frame, trackedCooldownIDSet, spellLookup)
    RegisterFrameForCooldown(frame, cooldownID)
    return cooldownID
end

local function InstallTrackedFrameHooks(frame)
    if not frame or hookedFrames[frame] then
        return
    end

    hookedFrames[frame] = true

    RefineUI:HookScriptOnce("CDM:AuraProbe:Frame:" .. tostring(frame) .. ":OnShow", frame, "OnShow", function(selfFrame)
        local assignedSnapshot = CDM.GetAssignedCooldownSnapshot and CDM:GetAssignedCooldownSnapshot() or nil
        local trackedCooldownIDs = assignedSnapshot and assignedSnapshot.allAssignedIDs or nil
        RefreshRegisteredFrame(selfFrame, BuildTrackedCooldownIDSet(trackedCooldownIDs), GetAssignedSpellLookup())
    end)
    RefineUI:HookScriptOnce("CDM:AuraProbe:Frame:" .. tostring(frame) .. ":OnHide", frame, "OnHide", function(selfFrame)
        MarkFrameHidden(selfFrame)
    end)
end

local function InstallViewerHooks(viewer, _viewerName)
    if not viewer or hookedViewers[viewer] then
        return
    end

    hookedViewers[viewer] = true
    RefineUI:HookScriptOnce("CDM:AuraProbe:Viewer:" .. tostring(viewer) .. ":OnShow", viewer, "OnShow", function()
        MarkRegistryDirty()
        QueueRegistryReconcile()
    end)
end

local function InstallKnownViewerHooks()
    for i = 1, #AURA_VIEWER_NAMES do
        local viewerName = AURA_VIEWER_NAMES[i]
        local viewer = _G[viewerName]
        if viewer then
            InstallViewerHooks(viewer, viewerName)
        end
    end
end

MarkRegistryDirty = function()
    registryDirty = true
end

QueueRegistryReconcile = function()
    if registryReconcileQueued then
        return
    end
    registryReconcileQueued = true

    local function Execute()
        registryReconcileQueued = nil
        if registryDirty then
            InstallKnownViewerHooks()
        end
        CDM:RequestRefresh()
    end

    if RefineUI.After then
        RefineUI:After(RECONCILE_TIMER_KEY, 0, Execute)
    else
        Execute()
    end
end

local function CopyPayload(payload)
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
    }
end

local function StoreGhostPayload(cooldownID, payload)
    local ttl = CDM.GetPayloadGhostTTL and CDM:GetPayloadGhostTTL() or 0.20
    if ttl <= 0 or type(payload) ~= "table" then
        return
    end

    ghostPayloadByCooldownID[cooldownID] = {
        payload = CopyPayload(payload),
        expiresAt = GetTime() + ttl,
    }
end

local function GetGhostPayload(cooldownID)
    local ghost = ghostPayloadByCooldownID[cooldownID]
    if type(ghost) ~= "table" then
        return nil
    end

    if type(ghost.expiresAt) ~= "number" or ghost.expiresAt <= GetTime() then
        ghostPayloadByCooldownID[cooldownID] = nil
        return nil
    end

    return CopyPayload(ghost.payload)
end

local function PruneExpiredGhostPayloads()
    local now = GetTime()
    for cooldownID, ghost in pairs(ghostPayloadByCooldownID) do
        if type(ghost) ~= "table" or type(ghost.expiresAt) ~= "number" or ghost.expiresAt <= now then
            ghostPayloadByCooldownID[cooldownID] = nil
        end
    end
end

local function ResolveAuraUnit(frame)
    if not frame then
        return nil
    end

    if type(frame.GetAuraDataUnit) == "function" then
        local okAuraUnit, auraUnit = pcall(frame.GetAuraDataUnit, frame)
        if okAuraUnit and IsUnitToken(auraUnit) then
            return auraUnit
        end
    end

    local okRawUnit, rawUnit = pcall(function()
        return frame.auraDataUnit
    end)
    if okRawUnit and IsUnitToken(rawUnit) then
        return rawUnit
    end

    return nil
end

local function ResolveAuraInstanceID(frame)
    if not frame then
        return nil
    end

    if type(frame.GetAuraSpellInstanceID) == "function" then
        local okAuraID, auraInstanceID = pcall(frame.GetAuraSpellInstanceID, frame)
        if okAuraID and HasAuraInstanceID(auraInstanceID) then
            return auraInstanceID
        end
    end

    local okRawAuraID, rawAuraID = pcall(function()
        return frame.auraInstanceID
    end)
    if okRawAuraID and HasAuraInstanceID(rawAuraID) then
        return rawAuraID
    end

    return nil
end

local function ResolveTotemData(frame)
    if not frame then
        return nil
    end

    if type(frame.GetTotemData) == "function" then
        local okTotemData, totemData = pcall(frame.GetTotemData, frame)
        if okTotemData and HasValue(totemData) then
            return totemData
        end
    end

    local okRawTotemData, rawTotemData = pcall(function()
        return frame.totemData
    end)
    if okRawTotemData and HasValue(rawTotemData) then
        return rawTotemData
    end

    return nil
end

local function ResolveFrameActive(frame)
    if not frame then
        return nil
    end

    local okActive, active = pcall(function()
        return frame.isActive
    end)
    if okActive then
        if IsSecret(active) then
            return nil
        end
        if type(active) == "boolean" then
            return active
        end
    end

    return nil
end

local function ResolveTotemSlot(frame, totemData)
    if not frame then
        return nil
    end

    local slot = frame.preferredTotemUpdateSlot
    if HasTotemSlotValue(slot) then
        return slot
    end

    if HasValue(totemData) then
        local okDataSlot, dataSlot = pcall(function()
            return totemData.slot
        end)
        if okDataSlot and HasTotemSlotValue(dataSlot) then
            return dataSlot
        end
    end

    if type(frame.GetTotemSlot) == "function" then
        local okSlot, resolvedSlot = pcall(frame.GetTotemSlot, frame)
        if okSlot and HasTotemSlotValue(resolvedSlot) then
            return resolvedSlot
        end
    end

    return nil
end

local function ResolveCooldownWindowFromTotemData(totemData, totemSlot)
    local cooldownStartTime
    local cooldownDuration
    local cooldownModRate

    if not IsSecret(totemData) and type(totemData) == "table" then
        local expirationTime = totemData.expirationTime
        local duration = totemData.duration
        local modRate = totemData.modRate
        if IsNonSecretNumber(expirationTime)
            and IsNonSecretNumber(duration)
            and duration > 0
        then
            cooldownStartTime = expirationTime - duration
            cooldownDuration = duration
            if IsNonSecretNumber(modRate) then
                cooldownModRate = modRate
            end
            return cooldownStartTime, cooldownDuration, cooldownModRate
        end
    end

    if HasTotemSlotValue(totemSlot) and type(GetTotemInfo) == "function" then
        local okTotem, _hasTotem, _name, startTime, duration, _icon, modRate = pcall(GetTotemInfo, totemSlot)
        if okTotem and HasNumericValue(startTime) and HasPositiveNumericValue(duration) then
            cooldownStartTime = startTime
            cooldownDuration = duration
            if IsNonSecretNumber(modRate) then
                cooldownModRate = modRate
            end
            return cooldownStartTime, cooldownDuration, cooldownModRate
        end
    end

    return nil, nil, nil
end

local function ResolveCooldownWindowFromWidget(frame)
    if not frame or not frame.Cooldown or type(frame.Cooldown.GetCooldownTimes) ~= "function" then
        return nil, nil, nil
    end

    local okTimes, startMS, durationMS = pcall(frame.Cooldown.GetCooldownTimes, frame.Cooldown)
    if not okTimes then
        return nil, nil, nil
    end
    if not IsNonSecretNumber(startMS) or not IsNonSecretNumber(durationMS) or durationMS <= 0 then
        return nil, nil, nil
    end

    return startMS / 1000, durationMS / 1000, nil
end

local function ResolveFrameIcon(frame, cooldownID)
    if not frame then
        return ResolveIconFromCooldownID(cooldownID)
    end

    if type(frame.GetSpellTexture) == "function" then
        local okTexture, texture = pcall(frame.GetSpellTexture, frame)
        if okTexture and IsTextureLike(texture) then
            return texture
        end
    end

    local iconRegion = frame.Icon
    if iconRegion and type(iconRegion.GetTexture) == "function" then
        local okIconTexture, iconTexture = pcall(iconRegion.GetTexture, iconRegion)
        if okIconTexture and IsTextureLike(iconTexture) then
            return iconTexture
        end
    end

    return ResolveIconFromCooldownID(cooldownID)
end

local function GetActiveStateRank(payload)
    if type(payload) ~= "table" then
        return 0
    end

    local token = payload.activeStateToken
    if type(token) ~= "string" then
        return 0
    end

    if token == "viewer:aura" then
        return 3
    end
    if string.find(token, "^viewer:totem", 1, false) then
        return 2
    end
    if token == "viewer:active" then
        return 1
    end

    return 0
end

local function BuildFramePayload(frame, cooldownID)
    if not frame or not IsNonSecretNumber(cooldownID) then
        return nil
    end

    local auraInstanceID = ResolveAuraInstanceID(frame)
    local frameActive = ResolveFrameActive(frame)
    if frameActive == false then
        return nil
    end

    local totemData = ResolveTotemData(frame)
    local hasTotemData = HasValue(totemData)
    local totemSlot = ResolveTotemSlot(frame, totemData)

    local activeStateToken = "viewer:pool"
    if HasAuraInstanceID(auraInstanceID) then
        activeStateToken = "viewer:aura"
    elseif hasTotemData then
        if IsNonSecretNumber(totemSlot) and totemSlot > 0 then
            activeStateToken = "viewer:totem:" .. tostring(totemSlot)
        else
            activeStateToken = "viewer:totem"
        end
    end

    local auraUnit = ResolveAuraUnit(frame)

    local durationObject
    if HasAuraInstanceID(auraInstanceID)
        and auraUnit
        and C_UnitAuras
        and type(C_UnitAuras.GetAuraDuration) == "function"
    then
        local okDuration, resolvedDuration = pcall(C_UnitAuras.GetAuraDuration, auraUnit, auraInstanceID)
        if okDuration and HasValue(resolvedDuration) then
            durationObject = resolvedDuration
        end
    end

    local cooldownStartTime
    local cooldownDuration
    local cooldownModRate

    if hasTotemData then
        local totemCooldownStart, totemCooldownDuration, totemCooldownModRate = ResolveCooldownWindowFromTotemData(totemData, totemSlot)
        if HasNumericValue(totemCooldownStart) and HasPositiveNumericValue(totemCooldownDuration) then
            cooldownStartTime = totemCooldownStart
            cooldownDuration = totemCooldownDuration
            if IsNonSecretNumber(totemCooldownModRate) then
                cooldownModRate = totemCooldownModRate
            end
        end
    end

    if not HasValue(cooldownStartTime) then
        local widgetCooldownStart, widgetCooldownDuration, widgetCooldownModRate = ResolveCooldownWindowFromWidget(frame)
        if IsNonSecretNumber(widgetCooldownStart) and IsNonSecretNumber(widgetCooldownDuration) and widgetCooldownDuration > 0 then
            cooldownStartTime = widgetCooldownStart
            cooldownDuration = widgetCooldownDuration
            if IsNonSecretNumber(widgetCooldownModRate) then
                cooldownModRate = widgetCooldownModRate
            end
        end
    end

    local hasAuraDurationObject = HasValue(durationObject)
    local hasCooldownWindow = HasValue(cooldownStartTime) and HasValue(cooldownDuration)
    local hasTotemWindow = hasTotemData and hasCooldownWindow
    if not HasAuraInstanceID(auraInstanceID)
        and not hasTotemWindow
        and not hasAuraDurationObject
    then
        return nil
    end

    local icon = ResolveFrameIcon(frame, cooldownID)
    if not HasValue(icon) then
        icon = DEFAULT_ICON_TEXTURE
    end

    return {
        cooldownID = cooldownID,
        icon = icon,
        duration = durationObject,
        auraUnit = auraUnit,
        auraInstanceID = auraInstanceID,
        activeStateToken = activeStateToken,
        cooldownStartTime = cooldownStartTime,
        cooldownDuration = cooldownDuration,
        cooldownModRate = cooldownModRate,
    }
end

local function ShouldReplacePayload(existing, candidate)
    if not existing then
        return true
    end
    if not candidate then
        return false
    end

    local existingHasDuration = HasValue(existing.duration) or HasValue(existing.cooldownDuration)
    local candidateHasDuration = HasValue(candidate.duration) or HasValue(candidate.cooldownDuration)
    if candidateHasDuration and not existingHasDuration then
        return true
    end
    if existingHasDuration and not candidateHasDuration then
        return false
    end

    local existingHasDurationObject = HasValue(existing.duration)
    local candidateHasDurationObject = HasValue(candidate.duration)
    if candidateHasDurationObject and not existingHasDurationObject then
        return true
    end
    if existingHasDurationObject and not candidateHasDurationObject then
        return false
    end

    local existingHasAuraInstance = HasAuraInstanceID(existing.auraInstanceID)
    local candidateHasAuraInstance = HasAuraInstanceID(candidate.auraInstanceID)
    if candidateHasAuraInstance and not existingHasAuraInstance then
        return true
    end
    if existingHasAuraInstance and not candidateHasAuraInstance then
        return false
    end

    local existingStateRank = GetActiveStateRank(existing)
    local candidateStateRank = GetActiveStateRank(candidate)
    if candidateStateRank > existingStateRank then
        return true
    end
    if existingStateRank > candidateStateRank then
        return false
    end

    if existingHasDuration and candidateHasDuration then
        local existingStart = existing.cooldownStartTime
        local candidateStart = candidate.cooldownStartTime
        if IsNonSecretNumber(existingStart) and IsNonSecretNumber(candidateStart) then
            if candidateStart > existingStart then
                return true
            end
            if candidateStart < existingStart then
                return false
            end
        end
    end

    if not HasValue(candidate.icon) and HasValue(existing.icon) then
        candidate.icon = existing.icon
    end

    return true
end

local function ReconcileViewerRegistry(cooldownIDs)
    local reconcileStartTime = GetTime()
    local trackedCooldownIDSet = BuildTrackedCooldownIDSet(cooldownIDs)
    local spellLookup = GetAssignedSpellLookup()

    ClearRegistryFrames()

    for i = 1, #AURA_VIEWER_NAMES do
        local viewerName = AURA_VIEWER_NAMES[i]
        local viewer = _G[viewerName]
        if viewer then
            InstallViewerHooks(viewer, viewerName)
            ForEachViewerItemFrame(viewer, function(frame)
                InstallTrackedFrameHooks(frame)
                RefreshRegisteredFrame(frame, trackedCooldownIDSet, spellLookup)
            end)
        end
    end

    registryDirty = false
    CDM:IncrementPerfCounter("cdm_aura_probe_reconcile")
    CDM:RecordPerfSample("cdm_aura_probe_reconcile", GetTime() - reconcileStartTime)
end

local function BuildActiveCooldownFrameMap(cooldownIDs)
    local buildStartTime = GetTime()
    local map = {}
    if type(cooldownIDs) ~= "table" or #cooldownIDs == 0 then
        return map
    end

    local assignedSnapshot = CDM.GetAssignedCooldownSnapshot and CDM:GetAssignedCooldownSnapshot() or nil
    local validationCooldownIDs = cooldownIDs
    if type(assignedSnapshot) == "table" and type(assignedSnapshot.allAssignedIDs) == "table" and #assignedSnapshot.allAssignedIDs > 0 then
        validationCooldownIDs = assignedSnapshot.allAssignedIDs
    end

    if registryDirty then
        ReconcileViewerRegistry(validationCooldownIDs)
    end

    local trackedCooldownIDSet = BuildTrackedCooldownIDSet(validationCooldownIDs)
    local spellLookup = GetAssignedSpellLookup()
    for frame in pairs(registeredFrameCooldownID) do
        RefreshRegisteredFrame(frame, trackedCooldownIDSet, spellLookup)
    end

    for i = 1, #cooldownIDs do
        local cooldownID = cooldownIDs[i]
        local frameSet = registeredFramesByCooldownID[cooldownID]
        if type(frameSet) == "table" then
            for frame in pairs(frameSet) do
                local payload = BuildFramePayload(frame, cooldownID)
                if payload and ShouldReplacePayload(map[cooldownID], payload) then
                    map[cooldownID] = payload
                end
            end
        end
    end

    CDM:IncrementPerfCounter("cdm_aura_probe_build")
    CDM:RecordPerfSample("cdm_aura_probe_build", GetTime() - buildStartTime)
    return map
end

local function TryRegisterDataChangedCallback()
    if dataChangedCallbackRegistered then
        return
    end

    local eventRegistry = _G.EventRegistry
    if not eventRegistry or type(eventRegistry.RegisterCallback) ~= "function" then
        return
    end

    eventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", function()
        local settingsFrame = CDM.GetCooldownViewerSettingsFrame and CDM:GetCooldownViewerSettingsFrame()
        if settingsFrame and settingsFrame:IsShown() and CDM.MarkReloadRecommendationPending then
            CDM:MarkReloadRecommendationPending()
        end
        if CDM.MarkAssignmentsPruneDirty then
            CDM:MarkAssignmentsPruneDirty()
        end
        MarkRegistryDirty()
        QueueRegistryReconcile()
    end, CDM)

    dataChangedCallbackRegistered = true
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function CDM:InvalidateAuraProbeCache()
    MarkRegistryDirty()
    if wipe then
        wipe(cooldownIconCache)
        return
    end

    for key in pairs(cooldownIconCache) do
        cooldownIconCache[key] = nil
    end
end

function CDM:RequestAuraProbeReconcile()
    MarkRegistryDirty()
    QueueRegistryReconcile()
end

function CDM:InitializeAuraProbe()
    if self.auraProbeInitialized then
        return
    end

    InstallKnownViewerHooks()
    TryRegisterDataChangedCallback()
    MarkRegistryDirty()
    QueueRegistryReconcile()

    self.auraProbeInitialized = true
end

function CDM:_ProbeCooldownAuraInternal(cooldownID, activeFrameMap)
    if not IsNonSecretNumber(cooldownID) or cooldownID <= 0 then
        return nil
    end

    local payload = type(activeFrameMap) == "table" and activeFrameMap[cooldownID] or nil
    if payload then
        StoreGhostPayload(cooldownID, payload)
        return payload
    end

    return GetGhostPayload(cooldownID)
end

function CDM:_GetActiveAuraMapInternal(cooldownIDs)
    local activeMap = {}
    if type(cooldownIDs) ~= "table" then
        return activeMap
    end

    local activeFrameMap = BuildActiveCooldownFrameMap(cooldownIDs)
    for i = 1, #cooldownIDs do
        local cooldownID = cooldownIDs[i]
        local payload = self:ProbeCooldownAura(cooldownID, activeFrameMap)
        if payload then
            if not HasValue(payload.icon) then
                local resolvedIcon = ResolveIconFromCooldownID(cooldownID)
                if HasValue(resolvedIcon) then
                    payload.icon = resolvedIcon
                else
                    payload.icon = DEFAULT_ICON_TEXTURE
                end
            end
            activeMap[cooldownID] = payload
        end
    end

    PruneExpiredGhostPayloads()
    return activeMap
end
