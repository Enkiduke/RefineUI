----------------------------------------------------------------------------------------
-- AutoItemBar for RefineUI
-- Description: Automatically adds useable items from bags to an action bar.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local AutoItemBar = RefineUI:RegisterModule("AutoItemBar")

AutoItemBar.BUTTONS_PER_LINE = 12
AutoItemBar.NUM_BAG_SLOTS = NUM_BAG_SLOTS or 4

----------------------------------------------------------------------------------------
--	Constants
----------------------------------------------------------------------------------------

AutoItemBar.ORIENTATION_HORIZONTAL = "HORIZONTAL"
AutoItemBar.ORIENTATION_VERTICAL = "VERTICAL"

AutoItemBar.DIRECTION_FORWARD = "FORWARD"
AutoItemBar.DIRECTION_REVERSE = "REVERSE"

AutoItemBar.WRAP_FORWARD = "FORWARD"
AutoItemBar.WRAP_REVERSE = "REVERSE"

AutoItemBar.VISIBILITY_ALWAYS = "ALWAYS"
AutoItemBar.VISIBILITY_IN_COMBAT = "IN_COMBAT"
AutoItemBar.VISIBILITY_OUT_OF_COMBAT = "OUT_OF_COMBAT"
AutoItemBar.VISIBILITY_MOUSEOVER = "MOUSEOVER"
AutoItemBar.VISIBILITY_NEVER = "NEVER"

AutoItemBar.CATEGORY_SCHEMA_VERSION = 2

AutoItemBar.buttonSize = 36
AutoItemBar.buttonSpacing = 6
AutoItemBar.currentConsumables = AutoItemBar.currentConsumables or {}

----------------------------------------------------------------------------------------
--	Registry
----------------------------------------------------------------------------------------

local AUTO_ITEM_BAR_BUTTON_STATE_REGISTRY = "AutoItemBarButtonState"
AutoItemBar.ButtonState = RefineUI:CreateDataRegistry(AUTO_ITEM_BAR_BUTTON_STATE_REGISTRY, "k")

function AutoItemBar:GetButtonState(button)
    if not button then return nil end

    local state = self.ButtonState[button]
    if not state then
        state = {}
        self.ButtonState[button] = state
    end
    return state
end

function AutoItemBar:GetButtonData(button, key, defaultValue)
    local state = self:GetButtonState(button)
    if not state then return defaultValue end

    local value = state[key]
    if value == nil then
        return defaultValue
    end
    return value
end

function AutoItemBar:SetButtonData(button, key, value)
    local state = self:GetButtonState(button)
    if not state then return end
    state[key] = value
end
