----------------------------------------------------------------------------------------
-- RefineUI MouseoverCasting Conflict
-- Description: Pauses while Blizzard click bindings are customized.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local MouseoverCasting = RefineUI:GetModule("MouseoverCasting")
if not MouseoverCasting then
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
local function HasCustomBlizzardClickBindings()
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
function MouseoverCasting:RefreshConflictState()
    self.hasConflict = HasCustomBlizzardClickBindings()
    return self.hasConflict
end

function MouseoverCasting:GetSuspendReasonText()
    if self.hasConflict then
        return SUSPEND_REASON
    end
    return nil
end
