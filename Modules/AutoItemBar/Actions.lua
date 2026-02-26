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

local ATTR_TYPE = "type"
local ATTR_ITEM = "item"
local ATTR_MACROTEXT = "macrotext"
local ATTR_TYPE1 = "type1"
local ATTR_ITEM1 = "item1"
local ATTR_MACROTEXT1 = "macrotext1"
local ATTR_TYPE2 = "type2"
local ATTR_ITEM2 = "item2"
local ATTR_MACROTEXT2 = "macrotext2"

local ACTION_TYPE_ITEM = "item"

----------------------------------------------------------------------------------------
--	State Application
----------------------------------------------------------------------------------------

function AutoItemBar:ClearUseAction(button)
    if not button then return end
    button:SetAttribute(ATTR_TYPE, nil)
    button:SetAttribute(ATTR_ITEM, nil)
    button:SetAttribute(ATTR_MACROTEXT, nil)
    button:SetAttribute(ATTR_TYPE1, nil)
    button:SetAttribute(ATTR_ITEM1, nil)
    button:SetAttribute(ATTR_MACROTEXT1, nil)
    button:SetAttribute(ATTR_TYPE2, nil)
    button:SetAttribute(ATTR_ITEM2, nil)
    button:SetAttribute(ATTR_MACROTEXT2, nil)
end

function AutoItemBar:AssignUseAction(button, itemID)
    if not button or not itemID then return end

    if self._useActionsEnabled == false then
        if not InCombatLockdown() then
            self:ClearUseAction(button)
            self:SetButtonData(button, "lastUseItem", nil)
        end
        self:SetButtonData(button, "pendingUseItem", nil)
        return
    end

    local itemToken = format("item:%d", itemID)
    if InCombatLockdown() then
        self:SetButtonData(button, "pendingUseItem", itemToken)
        return
    end

    if self:GetButtonData(button, "lastUseItem") ~= itemToken then
        button:SetAttribute(ATTR_TYPE, nil)
        button:SetAttribute(ATTR_ITEM, nil)
        button:SetAttribute(ATTR_MACROTEXT, nil)
        button:SetAttribute(ATTR_TYPE1, ACTION_TYPE_ITEM)
        button:SetAttribute(ATTR_ITEM1, itemToken)
        button:SetAttribute(ATTR_TYPE2, nil)
        button:SetAttribute(ATTR_ITEM2, nil)
        button:SetAttribute(ATTR_MACROTEXT2, nil)
        self:SetButtonData(button, "lastUseItem", itemToken)
    end
    self:SetButtonData(button, "pendingUseItem", nil)
end

function AutoItemBar:HandleDropFromCursor()
    local cursorType, itemID = GetCursorInfo()
    if cursorType ~= "item" or not itemID then return false end

    local changed = self:AddTrackedItem(itemID)
    ClearCursor()
    self._cursorHasPayload = false
    self:SetUseActionsEnabled(true)
    self:ShowBar()
    return changed
end

function AutoItemBar:SetUseActionsEnabled(enable)
    local desired = enable and true or false
    self._pendingUseActionsEnabled = desired

    if InCombatLockdown() then
        return
    end

    if self._useActionsEnabled == desired and not self._forceUseActionRefresh then
        return
    end

    if self.consumableButtons then
        for _, button in pairs(self.consumableButtons) do
            local itemID = self:GetButtonData(button, "itemID")
            if button and itemID then
                if desired then
                    self:AssignUseAction(button, itemID)
                else
                    self:ClearUseAction(button)
                    self:SetButtonData(button, "lastUseItem", nil)
                    self:SetButtonData(button, "pendingUseItem", nil)
                end
            end
        end
    end

    self._useActionsEnabled = desired
    self._forceUseActionRefresh = nil
end

function AutoItemBar:SetInteractive(enable)
    local desired = enable and true or false
    self._pendingInteractive = desired

    if InCombatLockdown() then
        return
    end

    if self._appliedInteractive == desired then
        return
    end

    if self.ConsumableBarParent and self.ConsumableBarParent.EnableMouse then
        self.ConsumableBarParent:EnableMouse(desired)
    end

    if self.consumableButtons then
        for _, button in pairs(self.consumableButtons) do
            if button and button.EnableMouse then
                button:EnableMouse(desired)
            end
        end
    end

    self._appliedInteractive = desired
end

function AutoItemBar:ApplyPendingButtonActions()
    if InCombatLockdown() then return end
    if not self.consumableButtons then return end

    local useActionsEnabled = (self._useActionsEnabled ~= false)
    for _, button in pairs(self.consumableButtons) do
        local itemID = self:GetButtonData(button, "itemID")
        if button and itemID then
            local pendingUseItem = self:GetButtonData(button, "pendingUseItem")
            if not useActionsEnabled then
                self:ClearUseAction(button)
                self:SetButtonData(button, "lastUseItem", nil)
                self:SetButtonData(button, "pendingUseItem", nil)
            elseif pendingUseItem then
                button:SetAttribute(ATTR_TYPE, nil)
                button:SetAttribute(ATTR_ITEM, nil)
                button:SetAttribute(ATTR_MACROTEXT, nil)
                button:SetAttribute(ATTR_TYPE1, ACTION_TYPE_ITEM)
                button:SetAttribute(ATTR_ITEM1, pendingUseItem)
                button:SetAttribute(ATTR_TYPE2, nil)
                button:SetAttribute(ATTR_ITEM2, nil)
                button:SetAttribute(ATTR_MACROTEXT2, nil)
                self:SetButtonData(button, "lastUseItem", pendingUseItem)
                self:SetButtonData(button, "pendingUseItem", nil)
            else
                self:AssignUseAction(button, itemID)
            end
        end
    end
end
