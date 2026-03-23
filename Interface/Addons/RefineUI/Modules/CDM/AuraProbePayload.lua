----------------------------------------------------------------------------------------
-- CDM Component: AuraProbePayload
-- Description: Public payload accessors that delegate to aura probe internals.
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
local pairs = pairs
local next = next
local issecretvalue = _G.issecretvalue

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

local function HasPayloadDurationObject(payload)
    return type(payload) == "table" and HasValue(payload.duration)
end

local function HasPayloadTiming(payload)
    if type(payload) ~= "table" then
        return false
    end

    return HasValue(payload.cooldownDuration)
        and (HasValue(payload.cooldownStartTime) or HasValue(payload.cooldownExpirationTime))
end

local function ShouldRequestProbeSupplement(payload)
    if type(payload) ~= "table" then
        return true
    end

    return not HasPayloadDurationObject(payload) and not HasPayloadTiming(payload)
end

local function MergePayloadPrimaryFirst(primaryPayload, secondaryPayload)
    if type(primaryPayload) ~= "table" then
        return secondaryPayload
    end

    if type(secondaryPayload) ~= "table" then
        return primaryPayload
    end

    if ShouldRequestProbeSupplement(primaryPayload) then
        if HasPayloadDurationObject(secondaryPayload) or HasPayloadTiming(secondaryPayload) then
            if not HasValue(secondaryPayload.icon) and HasValue(primaryPayload.icon) then
                secondaryPayload.icon = primaryPayload.icon
            end
            return secondaryPayload
        end
    end

    if not HasValue(primaryPayload.icon) and HasValue(secondaryPayload.icon) then
        primaryPayload.icon = secondaryPayload.icon
    end

    return primaryPayload
end

local function AddCooldownID(targetList, seenSet, cooldownID)
    if type(cooldownID) ~= "number" or cooldownID <= 0 or seenSet[cooldownID] then
        return
    end

    seenSet[cooldownID] = true
    targetList[#targetList + 1] = cooldownID
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function CDM:ProbeCooldownAura(cooldownID, activeFrameMap)
    if self.ShouldUseRuntimeResolverFallback and self:ShouldUseRuntimeResolverFallback() then
        if type(self._ProbeCooldownAuraResolverInternal) == "function" then
            return self:_ProbeCooldownAuraResolverInternal(cooldownID)
        end
        if type(self._ProbeCooldownAuraFallbackInternal) == "function" then
            return self:_ProbeCooldownAuraFallbackInternal(cooldownID, activeFrameMap)
        end
        return nil
    end

    local resolverMap = type(activeFrameMap) == "table" and activeFrameMap.resolverMap or nil
    local probeMap = type(activeFrameMap) == "table" and activeFrameMap.probeMap or nil
    if self.IsBlizzardPrimaryAuraRuntimeActive and self:IsBlizzardPrimaryAuraRuntimeActive() then
        return MergePayloadPrimaryFirst(
            type(probeMap) == "table" and probeMap[cooldownID] or nil,
            type(resolverMap) == "table" and resolverMap[cooldownID] or nil
        )
    end

    return MergePayloadPrimaryFirst(
        type(resolverMap) == "table" and resolverMap[cooldownID] or nil,
        type(probeMap) == "table" and probeMap[cooldownID] or nil
    )
end

function CDM:GetActiveAuraMap(cooldownIDs)
    if self.ShouldUseRuntimeResolverFallback and self:ShouldUseRuntimeResolverFallback() then
        if type(self._GetActiveAuraMapResolverInternal) == "function" then
            return self:_GetActiveAuraMapResolverInternal(cooldownIDs)
        end
        if type(self._GetActiveAuraMapFallbackInternal) == "function" then
            return self:_GetActiveAuraMapFallbackInternal(cooldownIDs)
        end
        return {}
    end

    if type(cooldownIDs) ~= "table" then
        return {}
    end

    local preferProbe = self.IsBlizzardPrimaryAuraRuntimeActive and self:IsBlizzardPrimaryAuraRuntimeActive()
    local resolverMap = {}
    local probeMap = {}

    local primaryCooldownIDs = {}
    local secondaryCooldownIDs = {}
    local seenSecondaryCooldownIDs = {}

    if preferProbe then
        for i = 1, #cooldownIDs do
            primaryCooldownIDs[i] = cooldownIDs[i]
        end

        if #primaryCooldownIDs > 0 and type(self._GetActiveAuraMapProbeInternal) == "function" then
            if self.IncrementPerfCounter then
                self:IncrementPerfCounter("cdm_aura_probe_requested", #primaryCooldownIDs)
                if self.auraProbeInitialized ~= true then
                    self:IncrementPerfCounter("cdm_aura_probe_unavailable", #primaryCooldownIDs)
                end
            end
            probeMap = self:_GetActiveAuraMapProbeInternal(primaryCooldownIDs) or {}
        end

        for i = 1, #cooldownIDs do
            local cooldownID = cooldownIDs[i]
            local probePayload = probeMap[cooldownID]
            if ShouldRequestProbeSupplement(probePayload) then
                AddCooldownID(secondaryCooldownIDs, seenSecondaryCooldownIDs, cooldownID)
            end
        end

        if #secondaryCooldownIDs > 0 and type(self._GetActiveAuraMapResolverInternal) == "function" then
            resolverMap = self:_GetActiveAuraMapResolverInternal(secondaryCooldownIDs) or {}
        end
    else
        if type(self._GetActiveAuraMapResolverInternal) == "function" then
            resolverMap = self:_GetActiveAuraMapResolverInternal(cooldownIDs) or {}
        end

        for i = 1, #cooldownIDs do
            local cooldownID = cooldownIDs[i]
            local resolverPayload = resolverMap[cooldownID]
            if ShouldRequestProbeSupplement(resolverPayload) then
                AddCooldownID(secondaryCooldownIDs, seenSecondaryCooldownIDs, cooldownID)
            end
        end

        if #secondaryCooldownIDs > 0 and type(self._GetActiveAuraMapProbeInternal) == "function" then
            if self.IncrementPerfCounter then
                self:IncrementPerfCounter("cdm_aura_probe_requested", #secondaryCooldownIDs)
                if self.auraProbeInitialized ~= true then
                    self:IncrementPerfCounter("cdm_aura_probe_unavailable", #secondaryCooldownIDs)
                end
            end
            probeMap = self:_GetActiveAuraMapProbeInternal(secondaryCooldownIDs) or {}
        end
    end

    local activeMap = {}
    for i = 1, #cooldownIDs do
        local cooldownID = cooldownIDs[i]
        local mergedPayload = preferProbe
            and MergePayloadPrimaryFirst(probeMap[cooldownID], resolverMap[cooldownID])
            or MergePayloadPrimaryFirst(resolverMap[cooldownID], probeMap[cooldownID])
        if mergedPayload then
            activeMap[cooldownID] = mergedPayload
        end
    end

    return activeMap
end
