----------------------------------------------------------------------------------------
-- RefineUI ClickCasting Conflict
-- Description: Detects conflicting click-cast systems and suspends safely.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local ClickCasting = RefineUI:GetModule("ClickCasting")
if not ClickCasting then
    return
end

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local GetProfileInfo = C_ClickBindings.GetProfileInfo
local ClickBindingType = Enum.ClickBindingType

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local SUSPEND_REASON = "Blizzard Mouseover Casting has custom bindings"

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local function HasCustomBlizzardClickCastBindings()
    local profileInfo = GetProfileInfo()
    for index = 1, #profileInfo do
        local bindingType = profileInfo[index].type
        if bindingType == ClickBindingType.Spell or bindingType == ClickBindingType.Macro or bindingType == ClickBindingType.PetAction then
            return true
        end
    end
    return false
end

----------------------------------------------------------------------------------------
-- Conflict API
----------------------------------------------------------------------------------------
function ClickCasting:RefreshConflictState()
    self.hasConflict = HasCustomBlizzardClickCastBindings()
    return self.hasConflict
end

function ClickCasting:GetSuspendReasonText()
    if self.hasConflict then
        return SUSPEND_REASON
    end
    return nil
end
