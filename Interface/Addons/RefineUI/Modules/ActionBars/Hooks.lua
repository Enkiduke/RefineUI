----------------------------------------------------------------------------------------
-- ActionBars Hooks
-- Description: Blizzard hook wiring for press, cooldown, range, and hotkey updates.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local ActionBars = RefineUI:GetModule("ActionBars")
if not ActionBars then
    return
end

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G

local NUM_PET_ACTION_SLOTS = NUM_PET_ACTION_SLOTS or 10
local NUM_STANCE_SLOTS = NUM_STANCE_SLOTS or 10

----------------------------------------------------------------------------------------
-- Shared State
----------------------------------------------------------------------------------------
local private = ActionBars.Private

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function QueueCooldownUpdate(button)
    if button then
        private.QueueDeferredCooldownUpdate(button)
    end
end

local function QueueStateUpdate(button)
    if button then
        private.QueueDeferredStateUpdate(button)
    end
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function ActionBars:SetupHooks()
    if private.hooksInitialized then
        return
    end

    private.hooksInitialized = true

    if ActionBarActionButtonMixin and ActionBarActionButtonMixin.SetButtonStateOverride then
        RefineUI:HookOnce(private.BuildHookKey(ActionBarActionButtonMixin, "SetButtonStateOverride"), ActionBarActionButtonMixin, "SetButtonStateOverride", function(button, state)
            private.QueueDeferredPress(button, state == "PUSHED")
        end)
    end

    do
        local function TriggerPressed(button, pressed)
            if button then
                private.SetPressedVisual(button, pressed)
            end
        end

        local function TriggerByID(id, pressed)
            local button = _G.GetActionButtonForID and _G.GetActionButtonForID(id)
            TriggerPressed(button, pressed)
        end

        if _G.ActionButtonDown then
            RefineUI:HookOnce("ActionBars:ActionButtonDown", "ActionButtonDown", function(id)
                TriggerByID(id, true)
            end)
        end
        if _G.ActionButtonUp then
            RefineUI:HookOnce("ActionBars:ActionButtonUp", "ActionButtonUp", function(id)
                TriggerByID(id, false)
            end)
        end
        if _G.MultiActionButtonDown then
            RefineUI:HookOnce("ActionBars:MultiActionButtonDown", "MultiActionButtonDown", function(bar, id)
                TriggerPressed(_G[bar .. "Button" .. id], true)
            end)
        end
        if _G.MultiActionButtonUp then
            RefineUI:HookOnce("ActionBars:MultiActionButtonUp", "MultiActionButtonUp", function(bar, id)
                TriggerPressed(_G[bar .. "Button" .. id], false)
            end)
        end
        if _G.PetActionButtonDown then
            RefineUI:HookOnce("ActionBars:PetActionButtonDown", "PetActionButtonDown", function(id)
                TriggerPressed(_G["PetActionButton" .. id], true)
            end)
        end
        if _G.PetActionButtonUp then
            RefineUI:HookOnce("ActionBars:PetActionButtonUp", "PetActionButtonUp", function(id)
                TriggerPressed(_G["PetActionButton" .. id], false)
            end)
        end
        if _G.StanceButtonDown then
            RefineUI:HookOnce("ActionBars:StanceButtonDown", "StanceButtonDown", function(id)
                TriggerPressed(_G["StanceButton" .. id], true)
            end)
        end
        if _G.StanceButtonUp then
            RefineUI:HookOnce("ActionBars:StanceButtonUp", "StanceButtonUp", function(id)
                TriggerPressed(_G["StanceButton" .. id], false)
            end)
        end
    end

    if _G.ActionButton_UpdateCooldown then
        RefineUI:HookOnce("ActionBars:ActionButton_UpdateCooldown", "ActionButton_UpdateCooldown", function(button)
            QueueCooldownUpdate(button)
        end)
    end

    if _G.ActionButton_UpdateRangeIndicator then
        RefineUI:HookOnce("ActionBars:ActionButton_UpdateRangeIndicator", "ActionButton_UpdateRangeIndicator", function(button, checksRange, inRange)
            private.QueueDeferredRangeUpdate(button, checksRange, inRange)
        end)
    end

    if ActionBarActionButtonMixin and ActionBarActionButtonMixin.UpdateUsable then
        RefineUI:HookOnce("ActionBars:ActionBarActionButtonMixin:UpdateUsable", ActionBarActionButtonMixin, "UpdateUsable", function(button)
            QueueStateUpdate(button)
        end)
    elseif ActionButtonMixin and ActionButtonMixin.UpdateUsable then
        RefineUI:HookOnce("ActionBars:ActionButtonMixin:UpdateUsable", ActionButtonMixin, "UpdateUsable", function(button)
            QueueStateUpdate(button)
        end)
    elseif _G.ActionButton_UpdateUsable then
        RefineUI:HookOnce("ActionBars:ActionButton_UpdateUsable", "ActionButton_UpdateUsable", function(button)
            QueueStateUpdate(button)
        end)
    end

    if PetActionBarMixin and PetActionBarMixin.UpdateCooldowns then
        RefineUI:HookOnce("ActionBars:PetActionBarMixin:UpdateCooldowns", PetActionBarMixin, "UpdateCooldowns", function(bar)
            local buttons = bar and bar.actionButtons
            if not buttons then
                return
            end
            for index = 1, NUM_PET_ACTION_SLOTS do
                QueueCooldownUpdate(buttons[index])
            end
        end)
    end

    if PetActionButtonMixin then
        if PetActionButtonMixin.Update then
            RefineUI:HookOnce("ActionBars:PetActionButtonMixin:Update", PetActionButtonMixin, "Update", function(button)
                QueueStateUpdate(button)
            end)
        end
        if PetActionButtonMixin.UpdateUsable then
            RefineUI:HookOnce("ActionBars:PetActionButtonMixin:UpdateUsable", PetActionButtonMixin, "UpdateUsable", function(button)
                QueueStateUpdate(button)
            end)
        end
    elseif _G.PetActionButton_Update then
        RefineUI:HookOnce("ActionBars:PetActionButton_Update", "PetActionButton_Update", function(button)
            QueueStateUpdate(button)
        end)
    end

    if _G.StanceBar_Update then
        RefineUI:HookOnce("ActionBars:StanceBar_Update", "StanceBar_Update", function()
            for index = 1, NUM_STANCE_SLOTS do
                local button = _G["StanceButton" .. index]
                QueueCooldownUpdate(button)
                QueueStateUpdate(button)
            end
        end)
    end

    if ActionBarActionButtonMixin and ActionBarActionButtonMixin.UpdateHotkeys then
        RefineUI:HookOnce("ActionBars:ActionBarActionButtonMixin:UpdateHotkeys", ActionBarActionButtonMixin, "UpdateHotkeys", function(button)
            local hotkey = button and button.HotKey
            if not hotkey then
                return
            end

            if private.IsHotkeyEnabledForButton(button) then
                hotkey:SetAlpha(1)
                hotkey:Show()
            else
                hotkey:SetAlpha(0)
                hotkey:Hide()
            end
        end)
    end
end
