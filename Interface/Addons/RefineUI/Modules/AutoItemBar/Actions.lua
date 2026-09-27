----------------------------------------------------------------------------------------
-- AutoItemBar Component: Actions
-- Description: Handles secure action assignment for items.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local AutoItemBar = RefineUI:GetModule("AutoItemBar")
if not AutoItemBar then return end

local format = string.format
local InCombatLockdown = InCombatLockdown
local GetCursorInfo = GetCursorInfo
local ClearCursor = ClearCursor
local pairs = pairs

----------------------------------------------------------------------------------------
--	Constants
----------------------------------------------------------------------------------------

local ATTR_TYPE1 = "type1"
local ATTR_ITEM1 = "item1"

local ACTION_TYPE_ITEM = "item"

----------------------------------------------------------------------------------------
--	State Application
----------------------------------------------------------------------------------------

-- Buttons are keyed by item ID, so a button's action only changes when use actions
-- are toggled. Attributes are applied out of combat; ApplyUseActions catches up on
-- PLAYER_REGEN_ENABLED.
function AutoItemBar:AssignUseAction(button, itemID)
    if InCombatLockdown() then return end

    local state = self:GetButtonState(button)
    if self._useActionsEnabled == false then
        if state.useItemID then
            button:SetAttribute(ATTR_TYPE1, nil)
            button:SetAttribute(ATTR_ITEM1, nil)
            state.useItemID = nil
        end
    elseif state.useItemID ~= itemID then
        button:SetAttribute(ATTR_TYPE1, ACTION_TYPE_ITEM)
        button:SetAttribute(ATTR_ITEM1, format("item:%d", itemID))
        state.useItemID = itemID
    end
end

function AutoItemBar:ApplyUseActions()
    if InCombatLockdown() or not self.consumableButtons then return end

    for itemID, button in pairs(self.consumableButtons) do
        self:AssignUseAction(button, itemID)
    end
end

function AutoItemBar:SetUseActionsEnabled(enable)
    if InCombatLockdown() then return end

    local desired = enable and true or false
    if self._useActionsEnabled == desired then return end

    self._useActionsEnabled = desired
    self:ApplyUseActions()
end

function AutoItemBar:HandleDropFromCursor()
    local cursorType, itemID = GetCursorInfo()
    if cursorType ~= "item" or not itemID then return false end

    local changed = self:AddTrackedItem(itemID)
    ClearCursor()
    self:SetUseActionsEnabled(true)
    self:ShowBar()
    return changed
end

function AutoItemBar:SetInteractive(enable)
    local desired = enable and true or false

    if InCombatLockdown() then
        return
    end

    if self._appliedInteractive == desired then
        return
    end

    self.ConsumableBarParent:EnableMouse(desired)
    for _, button in pairs(self.consumableButtons) do
        button:EnableMouse(desired)
    end

    self._appliedInteractive = desired
end
