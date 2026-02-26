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
local tinsert = table.insert
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
local framesByCooldownID = {}
local cooldownIDByFrame = setmetatable({}, { __mode = "k" })
local ghostPayloadByCooldownID = {}
local cooldownIDSeenScratch = {}
local registryReconcileQueued = nil
local registryDirty = true
local dataChangedCallbackRegistered = false
local hookedFrames = setmetatable({}, { __mode = "k" })
local hookedViewers = setmetatable({}, { __mode = "k" })
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

    if frame and IsNonSecretNumber(frame.cooldownID) and frame.cooldownID > 0 then
        return frame.cooldownID
    end

    if frame and type(frame.cooldownInfo) == "table" then
        local infoCooldownID = frame.cooldownInfo.cooldownID
        if IsNonSecretNumber(infoCooldownID) and infoCooldownID > 0 then
            return infoCooldownID
        end
    end

    return nil
end

local function GetFrameRegistryBucket(cooldownID)
    local bucket = framesByCooldownID[cooldownID]
    if bucket then
        return bucket
    end

    bucket = setmetatable({}, { __mode = "k" })
    framesByCooldownID[cooldownID] = bucket
    return bucket
end

local function RegisterCooldownFrame(frame, cooldownID)
    if not frame or not IsNonSecretNumber(cooldownID) or cooldownID <= 0 then
        return
    end

    local previousID = cooldownIDByFrame[frame]
    if IsNonSecretNumber(previousID) and previousID ~= cooldownID then
        local previousBucket = framesByCooldownID[previousID]
        if previousBucket then
            previousBucket[frame] = nil
            if next(previousBucket) == nil then
                framesByCooldownID[previousID] = nil
            end
        end
    end

    cooldownIDByFrame[frame] = cooldownID
    local bucket = GetFrameRegistryBucket(cooldownID)
    bucket[frame] = true
end

local function UnregisterCooldownFrame(frame)
    if not frame then
        return
    end

    local previousID = cooldownIDByFrame[frame]
    if not IsNonSecretNumber(previousID) then
        cooldownIDByFrame[frame] = nil
        return
    end

    local bucket = framesByCooldownID[previousID]
    if bucket then
        bucket[frame] = nil
        if next(bucket) == nil then
            framesByCooldownID[previousID] = nil
        end
    end
    cooldownIDByFrame[frame] = nil
end

local function ResetFrameRegistry()
    for cooldownID in pairs(framesByCooldownID) do
        framesByCooldownID[cooldownID] = nil
    end
    for frame in pairs(cooldownIDByFrame) do
        cooldownIDByFrame[frame] = nil
    end
end

local function GetHookObjectID(obj)
    if obj and type(obj.GetName) == "function" then
        local name = obj:GetName()
        if type(name) == "string" and name ~= "" then
            return name
        end
    end
    return tostring(obj)
end

local function InstallFrameHooks(frame)
    if not frame or hookedFrames[frame] then
        return
    end

    local hookID = GetHookObjectID(frame)
    if type(frame.SetCooldownID) == "function" then
        RefineUI:HookOnce("CDM:AuraProbe:" .. hookID .. ":SetCooldownID", frame, "SetCooldownID", function(hookedFrame, cooldownID)
            local resolvedCooldownID = ResolveFrameCooldownID(hookedFrame, cooldownID)
            if resolvedCooldownID then
                RegisterCooldownFrame(hookedFrame, resolvedCooldownID)
            else
                UnregisterCooldownFrame(hookedFrame)
            end
            CDM:RequestRefresh()
        end)
    end

    if type(frame.ClearCooldownID) == "function" then
        RefineUI:HookOnce("CDM:AuraProbe:" .. hookID .. ":ClearCooldownID", frame, "ClearCooldownID", function(hookedFrame)
            UnregisterCooldownFrame(hookedFrame)
            CDM:RequestRefresh()
        end)
    end

    hookedFrames[frame] = true
end

local function InstallViewerHooks(viewer, viewerName)
    if not viewer or hookedViewers[viewer] then
        return
    end

    local hookID = viewerName or GetHookObjectID(viewer)
    local function OnViewerReshuffle()
        MarkRegistryDirty()
        QueueRegistryReconcile()
    end
    local function OnViewerDataRefresh()
        CDM:RequestRefresh()
    end

    if type(viewer.OnAcquireItemFrame) == "function" then
        RefineUI:HookOnce("CDM:AuraProbe:" .. hookID .. ":OnAcquireItemFrame", viewer, "OnAcquireItemFrame", OnViewerReshuffle)
    end
    if type(viewer.RefreshData) == "function" then
        RefineUI:HookOnce("CDM:AuraProbe:" .. hookID .. ":RefreshData", viewer, "RefreshData", OnViewerDataRefresh)
    end
    if type(viewer.RefreshLayout) == "function" then
        RefineUI:HookOnce("CDM:AuraProbe:" .. hookID .. ":RefreshLayout", viewer, "RefreshLayout", OnViewerReshuffle)
    end

    hookedViewers[viewer] = true
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

local function CollectViewerFrames(viewer)
    local collected = {}
    local seen = {}

    local function AddFrame(frame)
        if not frame or seen[frame] then
            return
        end
        seen[frame] = true
        tinsert(collected, frame)
    end

    if viewer and type(viewer.GetChildren) == "function" then
        pcall(function()
            local children = { viewer:GetChildren() }
            for i = 1, #children do
                AddFrame(children[i])
            end
        end)
    end

    return collected
end

local function ReconcileFrameRegistry()
    ResetFrameRegistry()

    for i = 1, #AURA_VIEWER_NAMES do
        local viewerName = AURA_VIEWER_NAMES[i]
        local viewer = _G[viewerName]
        InstallViewerHooks(viewer, viewerName)
        local frames = CollectViewerFrames(viewer)
        for n = 1, #frames do
            local frame = frames[n]
            InstallFrameHooks(frame)
            local cooldownID = ResolveFrameCooldownID(frame)
            if cooldownID then
                RegisterCooldownFrame(frame, cooldownID)
            end
        end
    end
    registryDirty = false
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
            ReconcileFrameRegistry()
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

    if HasAuraInstanceID(frame.auraInstanceID) then
        return frame.auraInstanceID
    end

    return nil
end

local function ResolveTotemSlot(frame)
    if not frame then
        return nil
    end

    local slot = frame.preferredTotemUpdateSlot
    if IsNonSecretNumber(slot) and slot > 0 then
        return slot
    end

    return nil
end

local function ResolveTotemState(frame)
    local slot = ResolveTotemSlot(frame)
    local hasTotemData = false
    if frame then
        local okTotemData, value = pcall(function()
            return frame.totemData ~= nil
        end)
        if okTotemData and value then
            hasTotemData = true
        end
    end

    if not hasTotemData then
        return slot, false, nil, nil, nil, nil
    end

    if not IsNonSecretNumber(slot) or slot <= 0 or type(GetTotemInfo) ~= "function" then
        return slot, hasTotemData, nil, nil, nil, nil
    end

    local okTotem, _hasTotem, _name, startTime, duration, icon, modRate = pcall(GetTotemInfo, slot)
    if not okTotem then
        return slot, hasTotemData, nil, nil, nil, nil
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

local function BuildFramePayload(frame, cooldownID)
    if not frame or not IsNonSecretNumber(cooldownID) then
        return nil
    end

    local auraInstanceID = ResolveAuraInstanceID(frame)
    local totemSlot, hasTotemData, totemStartTime, totemDuration, totemIcon, totemModRate = ResolveTotemState(frame)
    local isTotemLinked = IsNonSecretNumber(totemSlot) and totemSlot > 0
    local active = HasAuraInstanceID(auraInstanceID) or hasTotemData
    local auraContext = active
    if not auraContext then
        local wasSetFromAura = frame.wasSetFromAura
        if IsSecret(wasSetFromAura) then
            auraContext = true
        elseif wasSetFromAura == true then
            auraContext = true
        elseif HasValue(frame.auraDataUnit) then
            auraContext = true
        end
    end
    if not active and not isTotemLinked then
        local cooldownFrame = frame.Cooldown
        if auraContext and cooldownFrame and type(cooldownFrame.IsShown) == "function" then
            local okShown, isShown = pcall(cooldownFrame.IsShown, cooldownFrame)
            if okShown then
                if IsSecret(isShown) then
                    active = true
                else
                    active = isShown == true
                end
            end
        end
    end
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

    local cooldownStartTime
    local cooldownDuration
    local cooldownModRate
    if HasValue(frame.cooldownStartTime) and HasValue(frame.cooldownDuration) then
        cooldownStartTime = frame.cooldownStartTime
        cooldownDuration = frame.cooldownDuration
        cooldownModRate = frame.cooldownModRate
    elseif hasTotemData and HasValue(totemStartTime) and HasValue(totemDuration) then
        cooldownStartTime = totemStartTime
        cooldownDuration = totemDuration
        cooldownModRate = HasValue(totemModRate) and totemModRate or frame.cooldownModRate
    elseif not isTotemLinked then
        local cooldownWidgetActive, cooldownWidgetStart, cooldownWidgetDuration = ResolveCooldownWidgetActive(frame.Cooldown)
        if cooldownWidgetActive and cooldownWidgetStart and cooldownWidgetDuration then
            cooldownStartTime = cooldownWidgetStart
            cooldownDuration = cooldownWidgetDuration
            cooldownModRate = frame.cooldownModRate
        end
    end

    local icon
    if frame.Icon and type(frame.Icon.GetTexture) == "function" then
        local okIcon, texture = pcall(frame.Icon.GetTexture, frame.Icon)
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

    if registryDirty then
        ReconcileFrameRegistry()
    end

    if wipe then
        wipe(cooldownIDSeenScratch)
    else
        for key in pairs(cooldownIDSeenScratch) do
            cooldownIDSeenScratch[key] = nil
        end
    end

    for i = 1, #cooldownIDs do
        local cooldownID = cooldownIDs[i]
        if IsNonSecretNumber(cooldownID) and cooldownID > 0 and not cooldownIDSeenScratch[cooldownID] then
            cooldownIDSeenScratch[cooldownID] = true

            local bucket = framesByCooldownID[cooldownID]
            if type(bucket) == "table" then
                for frame in pairs(bucket) do
                    local payload = BuildFramePayload(frame, cooldownID)
                    if payload then
                        if ShouldReplacePayload(map[cooldownID], payload) then
                            map[cooldownID] = payload
                        end
                    end
                end
            end
        end
    end

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

    RefineUI:RegisterEventCallback("ADDON_LOADED", function(_event, addonName)
        if addonName == "Blizzard_CooldownViewer" then
            InstallKnownViewerHooks()
            TryRegisterDataChangedCallback()
            CDM:InvalidateAuraProbeCache()
            CDM:RequestAuraProbeReconcile()
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

