----------------------------------------------------------------------------------------
-- CDM Component: AuraProbeRegistry
-- Description: Aura probe registry, frame indexing, payload synthesis, and reconcile flow.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local CDM = RefineUI:GetModule("CDM")
if not CDM then
    return
end

-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local type = type
local pcall = pcall
local pairs = pairs
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
local AURA_VIEWER_NAMES = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}

local cooldownIconCache = {}
local ghostPayloadByCooldownID = {}
local cooldownIDSeenScratch = {}
local dataChangedCallbackRegistered = false

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

local function IsUnitToken(value)
    if IsSecret(value) then
        return false
    end
    return type(value) == "string" and value ~= ""
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
    if ok and HasValue(texture) then
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
    if texture then
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

    if frame and IsNonSecretNumber(frame.cooldownID) and frame.cooldownID > 0 then
        return frame.cooldownID
    end

    return nil
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
            return
        end
    end

    if type(viewer.GetChildren) == "function" then
        pcall(function()
            local children = { viewer:GetChildren() }
            for i = 1, #children do
                callback(children[i])
            end
        end)
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
        source = payload.source,
        cooldownExpirationTime = payload.cooldownExpirationTime,
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
        local okUnit, unit = pcall(frame.GetAuraDataUnit, frame)
        if okUnit and IsUnitToken(unit) then
            return unit
        end
    end

    local unit = frame.auraDataUnit
    if IsUnitToken(unit) then
        return unit
    end

    return nil
end

local function ResolveAuraInstanceID(frame)
    if not frame then
        return nil
    end

    if type(frame.GetAuraSpellInstanceID) == "function" then
        local okAuraInstanceID, auraInstanceID = pcall(frame.GetAuraSpellInstanceID, frame)
        if okAuraInstanceID and HasAuraInstanceID(auraInstanceID) then
            return auraInstanceID
        end
    end

    if HasAuraInstanceID(frame.auraInstanceID) then
        return frame.auraInstanceID
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

    local totemData = frame.totemData
    if HasValue(totemData) then
        return totemData
    end

    return nil
end

local function ResolveTotemSlot(frame, totemData)
    if not frame then
        return nil
    end

    local slot = frame.preferredTotemUpdateSlot
    if IsNonSecretNumber(slot) and slot > 0 then
        return slot
    end

    if type(totemData) == "table" and not IsSecret(totemData) and IsNonSecretNumber(totemData.slot) and totemData.slot > 0 then
        return totemData.slot
    end

    if type(frame.GetTotemSlot) == "function" then
        local okSlot, resolvedSlot = pcall(frame.GetTotemSlot, frame)
        if okSlot and IsNonSecretNumber(resolvedSlot) and resolvedSlot > 0 then
            return resolvedSlot
        end
    end

    return nil
end

local function ResolveTotemWindowFromSlot(slot)
    if not IsNonSecretNumber(slot) or slot <= 0 or type(GetTotemInfo) ~= "function" then
        return nil, nil, nil, nil
    end

    local okTotemInfo, _hasTotem, _name, startTime, duration, _icon, modRate = pcall(GetTotemInfo, slot)
    if not okTotemInfo or not HasValue(startTime) or not HasValue(duration) then
        return nil, nil, nil, nil
    end

    if IsNonSecretNumber(duration) and duration <= 0 then
        return nil, nil, nil, nil
    end

    local resolvedModRate = nil
    if IsNonSecretNumber(modRate) then
        resolvedModRate = modRate
    end

    return startTime, duration, resolvedModRate, nil
end

local function ResolveTotemState(frame, totemData)
    local hasTotemData = HasValue(totemData)
    local slot = ResolveTotemSlot(frame, totemData)

    if not hasTotemData then
        return slot, false, nil, nil, nil, nil
    end

    local startTime = nil
    local duration = nil
    local icon = nil
    local modRate = nil

    if type(totemData) == "table" and not IsSecret(totemData) then
        local expirationTime = totemData.expirationTime
        if type(expirationTime) == "number"
            and not IsSecret(expirationTime)
            and type(totemData.duration) == "number"
            and not IsSecret(totemData.duration)
        then
            startTime = expirationTime - totemData.duration
        end
        if HasValue(totemData.duration) then
            duration = totemData.duration
        end
        if HasValue(totemData.icon) then
            icon = totemData.icon
        end
        if HasValue(totemData.modRate) then
            modRate = totemData.modRate
        end
    end

    return slot, hasTotemData, startTime, duration, icon, modRate
end

local function ResolveCooldownWidgetActive(cooldownFrame)
    if not cooldownFrame or type(cooldownFrame.GetCooldownTimes) ~= "function" then
        return false, nil, nil
    end

    local okTimes, startMS, durationMS = pcall(cooldownFrame.GetCooldownTimes, cooldownFrame)
    if not okTimes then
        return false, nil, nil
    end

    if IsSecret(startMS) or IsSecret(durationMS) then
        return false, nil, nil
    end

    if type(startMS) == "number" and type(durationMS) == "number" then
        local okActive, isActive = pcall(function()
            return durationMS > 0 and (startMS + durationMS) > (GetTime() * 1000)
        end)
        if okActive and isActive then
            return true, startMS / 1000, durationMS / 1000
        end
    end

    return false, nil, nil
end

local function ResolveCooldownWidgetDurationObject(cooldownFrame)
    if not cooldownFrame or type(cooldownFrame.GetCooldownDuration) ~= "function" then
        return nil
    end

    local okDuration, durationObject = pcall(cooldownFrame.GetCooldownDuration, cooldownFrame)
    if not okDuration or durationObject == nil then
        return nil
    end

    return durationObject
end

local function ResolveFrameCooldownWindow(frame)
    if not frame then
        return nil, nil, nil, false
    end

    local startTime = frame.cooldownStartTime
    local duration = frame.cooldownDuration
    local modRate = frame.cooldownModRate
    local hasSecretWindow = IsSecret(startTime) or IsSecret(duration)

    if hasSecretWindow then
        return startTime, duration, modRate, true
    end

    if type(startTime) == "number" and type(duration) == "number" then
        return startTime, duration, modRate, (startTime > 0 and duration > 0)
    end

    return startTime, duration, modRate, false
end

local function BuildFramePayload(frame, cooldownID)
    if not frame or not IsNonSecretNumber(cooldownID) then
        return nil
    end

    local cooldownFrame = frame.Cooldown
    if type(frame.GetCooldownFrame) == "function" then
        local okCooldownFrame, resolvedCooldownFrame = pcall(frame.GetCooldownFrame, frame)
        if okCooldownFrame and resolvedCooldownFrame then
            cooldownFrame = resolvedCooldownFrame
        end
    end

    local auraInstanceID = ResolveAuraInstanceID(frame)
    local totemData = ResolveTotemData(frame)
    local totemSlot, hasTotemData, totemStartTime, totemDuration, totemIcon, totemModRate = ResolveTotemState(frame, totemData)
    local hasTotemWindow = hasTotemData and HasValue(totemStartTime) and HasValue(totemDuration)
    local slotStartTime, slotDuration, slotModRate, slotExpirationTime = ResolveTotemWindowFromSlot(totemSlot)
    local hasSlotTotemWindow = HasValue(slotDuration) and (HasValue(slotStartTime) or HasValue(slotExpirationTime))
    local cooldownWidgetActive, cooldownWidgetStart, cooldownWidgetDuration = ResolveCooldownWidgetActive(cooldownFrame)
    local frameStartTime, frameDuration, frameModRate, hasFrameCooldownWindow = ResolveFrameCooldownWindow(frame)
    local active = HasAuraInstanceID(auraInstanceID)
        or hasTotemData
        or hasSlotTotemWindow
        or cooldownWidgetActive
        or hasFrameCooldownWindow
    if not active then
        return nil
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

    if not HasValue(durationObject) then
        durationObject = ResolveCooldownWidgetDurationObject(cooldownFrame)
    end

    local cooldownStartTime
    local cooldownExpirationTime
    local cooldownDuration
    local cooldownModRate
    local activeStateToken = "probe:viewer"
    local source = "probe"
    if hasSlotTotemWindow then
        cooldownStartTime = slotStartTime
        cooldownExpirationTime = slotExpirationTime
        cooldownDuration = slotDuration
        cooldownModRate = HasValue(slotModRate) and slotModRate or nil
        activeStateToken = "probe:totem:" .. tostring(totemSlot or "unknown")
        source = "probe-totem"
    elseif hasTotemWindow then
        cooldownStartTime = totemStartTime
        cooldownDuration = totemDuration
        cooldownModRate = HasValue(totemModRate) and totemModRate or nil
        activeStateToken = "probe:totem:" .. tostring(totemSlot or "unknown")
        source = "probe-totem"
    elseif hasFrameCooldownWindow then
        cooldownStartTime = frameStartTime
        cooldownDuration = frameDuration
        cooldownModRate = frameModRate
        activeStateToken = "probe:frame"
    elseif cooldownWidgetActive and cooldownWidgetStart and cooldownWidgetDuration then
        cooldownStartTime = cooldownWidgetStart
        cooldownDuration = cooldownWidgetDuration
        activeStateToken = "probe:widget"
    elseif HasAuraInstanceID(auraInstanceID) then
        activeStateToken = "probe:aura"
    end

    local icon
    local iconTexture = frame.Icon
    if type(frame.GetIconTexture) == "function" then
        local okIconTexture, resolvedIconTexture = pcall(frame.GetIconTexture, frame)
        if okIconTexture and resolvedIconTexture then
            iconTexture = resolvedIconTexture
        end
    end
    if iconTexture and type(iconTexture.GetTexture) == "function" then
        local okIcon, texture = pcall(iconTexture.GetTexture, iconTexture)
        if okIcon and HasValue(texture) then
            icon = texture
        end
    end
    if not HasValue(icon) and HasValue(totemIcon) then
        icon = totemIcon
    end
    if not HasValue(icon) then
        icon = ResolveIconFromCooldownID(cooldownID)
    end
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
        source = source,
        cooldownExpirationTime = cooldownExpirationTime,
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

local function BuildActiveCooldownFrameMap(cooldownIDs)
    local map = {}
    if type(cooldownIDs) ~= "table" or #cooldownIDs == 0 then
        return map
    end
    local buildStartTime = GetTime()

    if wipe then
        wipe(cooldownIDSeenScratch)
    else
        for key in pairs(cooldownIDSeenScratch) do
            cooldownIDSeenScratch[key] = nil
        end
    end

    for i = 1, #cooldownIDs do
        local cooldownID = cooldownIDs[i]
        if IsNonSecretNumber(cooldownID) and cooldownID > 0 then
            cooldownIDSeenScratch[cooldownID] = true
        end
    end

    for i = 1, #AURA_VIEWER_NAMES do
        local viewer = _G[AURA_VIEWER_NAMES[i]]
        ForEachViewerItemFrame(viewer, function(frame)
            local cooldownID = ResolveFrameCooldownID(frame)
            if cooldownID and cooldownIDSeenScratch[cooldownID] then
                local payload = BuildFramePayload(frame, cooldownID)
                if payload and ShouldReplacePayload(map[cooldownID], payload) then
                    map[cooldownID] = payload
                end
            end
        end)
    end

    CDM:IncrementPerfCounter("cdm_aura_probe_scan")
    CDM:RecordPerfSample("cdm_aura_probe_scan", GetTime() - buildStartTime)

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
        if not CDM.IsRefineRuntimeOwnerActive or not CDM:IsRefineRuntimeOwnerActive() then
            return
        end
        local settingsFrame = CDM.GetCooldownViewerSettingsFrame and CDM:GetCooldownViewerSettingsFrame()
        if settingsFrame and settingsFrame:IsShown() and CDM.MarkReloadRecommendationPending then
            CDM:MarkReloadRecommendationPending()
        end
        if CDM.MarkAssignmentsPruneDirty then
            CDM:MarkAssignmentsPruneDirty()
        end
        if CDM.RequestRefresh then
            CDM:RequestRefresh(true)
        end
    end, CDM)

    dataChangedCallbackRegistered = true
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function CDM:InvalidateAuraProbeCache()
    if wipe then
        wipe(cooldownIconCache)
        wipe(ghostPayloadByCooldownID)
        return
    end

    for key in pairs(cooldownIconCache) do
        cooldownIconCache[key] = nil
    end
    for key in pairs(ghostPayloadByCooldownID) do
        ghostPayloadByCooldownID[key] = nil
    end
end

function CDM:RequestAuraProbeReconcile()
    if not self.IsRefineRuntimeOwnerActive or not self:IsRefineRuntimeOwnerActive() then
        return
    end
    if not self.auraProbeInitialized then
        return
    end
    if self.RequestRefresh then
        self:RequestRefresh(true)
    end
end

function CDM:InitializeAuraProbe()
    if not self.IsRefineRuntimeOwnerActive or not self:IsRefineRuntimeOwnerActive() then
        return
    end
    if self.auraProbeInitialized then
        return
    end

    TryRegisterDataChangedCallback()

    RefineUI:RegisterEventCallback("ADDON_LOADED", function(_event, addonName)
        if addonName == "Blizzard_CooldownViewer" then
            TryRegisterDataChangedCallback()
            CDM:InvalidateAuraProbeCache()
            if CDM.RequestRefresh then
                CDM:RequestRefresh(true)
            end
        end
    end, "CDM:AuraProbe:AddonLoaded")

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
        local payload = self:_ProbeCooldownAuraInternal(cooldownID, activeFrameMap)
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

CDM._ProbeCooldownAuraProbeInternal = CDM._ProbeCooldownAuraInternal
CDM._GetActiveAuraMapProbeInternal = CDM._GetActiveAuraMapInternal
