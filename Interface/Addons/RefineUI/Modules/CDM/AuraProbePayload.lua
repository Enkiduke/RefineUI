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
    return self:_ProbeCooldownAuraInternal(cooldownID, activeFrameMap)
end

function CDM:GetActiveAuraMap(cooldownIDs)
    return self:_GetActiveAuraMapInternal(cooldownIDs)
end
