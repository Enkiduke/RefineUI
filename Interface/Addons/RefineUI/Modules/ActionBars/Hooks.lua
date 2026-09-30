----------------------------------------------------------------------------------------
-- ActionBars Hooks
-- Description: Blizzard hook wiring for press, cooldown, and range updates.
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

----------------------------------------------------------------------------------------
-- Shared State
----------------------------------------------------------------------------------------
local private = ActionBars.Private

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
-- Blizzard's UpdateUsable just repainted the icon, so reapply our color in the same frame.
-- Hooked per button in EnableDesaturation: the mixin methods are copied onto the buttons before RefineUI loads.
function private.ReapplyUsability(button, _, isUsable, notEnoughMana)
    private.RefreshButtonUsability(button, true, isUsable, notEnoughMana)
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function ActionBars:SetupHooks()
    if private.hooksInitialized then
        return
    end

    private.hooksInitialized = true

    do
        local function TriggerPressed(button, pressed)
            if button then
                private.QueueDeferredPress(button, pressed)
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
        -- Pet keybinds call PetActionBar:PetActionButtonDown/Up on the frame instance.
        RefineUI:HookOnce("ActionBars:PetActionBar:PetActionButtonDown", PetActionBar, "PetActionButtonDown", function(bar, id)
            TriggerPressed(bar.actionButtons[id], true)
        end)
        RefineUI:HookOnce("ActionBars:PetActionBar:PetActionButtonUp", PetActionBar, "PetActionButtonUp", function(bar, id)
            TriggerPressed(bar.actionButtons[id], false)
        end)
    end

    if _G.ActionButton_UpdateCooldown then
        RefineUI:HookOnce("ActionBars:ActionButton_UpdateCooldown", "ActionButton_UpdateCooldown", private.QueueDeferredCooldownUpdate)
    end

    if _G.ActionButton_UpdateRangeIndicator then
        RefineUI:HookOnce("ActionBars:ActionButton_UpdateRangeIndicator", "ActionButton_UpdateRangeIndicator", private.QueueDeferredRangeUpdate)
    end

    -- PetActionBar:Update repaints every pet icon white/grey, wiping our range tint; it also calls UpdateCooldowns.
    RefineUI:HookOnce("ActionBars:PetActionBar:Update", PetActionBar, "Update", function(bar)
        for index = 1, NUM_PET_ACTION_SLOTS do
            private.QueueDeferredStateUpdate(bar.actionButtons[index])
        end
    end)
    RefineUI:HookOnce("ActionBars:PetActionBar:UpdateCooldowns", PetActionBar, "UpdateCooldowns", function(bar)
        for index = 1, NUM_PET_ACTION_SLOTS do
            private.QueueDeferredCooldownUpdate(bar.actionButtons[index])
        end
    end)
end
