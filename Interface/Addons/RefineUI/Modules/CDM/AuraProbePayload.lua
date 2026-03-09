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
-- Public Methods
----------------------------------------------------------------------------------------
function CDM:ProbeCooldownAura(cooldownID, activeFrameMap)
    if self.ShouldUseRuntimeResolverFallback
        and self:ShouldUseRuntimeResolverFallback()
        and type(self._ProbeCooldownAuraFallbackInternal) == "function"
    then
        return self:_ProbeCooldownAuraFallbackInternal(cooldownID, activeFrameMap)
    end
    return self:_ProbeCooldownAuraInternal(cooldownID, activeFrameMap)
end

function CDM:GetActiveAuraMap(cooldownIDs)
    if self.ShouldUseRuntimeResolverFallback
        and self:ShouldUseRuntimeResolverFallback()
        and type(self._GetActiveAuraMapFallbackInternal) == "function"
    then
        return self:_GetActiveAuraMapFallbackInternal(cooldownIDs)
    end
    return self:_GetActiveAuraMapInternal(cooldownIDs)
end
