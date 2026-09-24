----------------------------------------------------------------------------------------
-- ActionBars State
-- Description: Cooldown, range, usability, resync, and deferred refresh logic.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local ActionBars = RefineUI:GetModule("ActionBars")
if not ActionBars then
    return
end

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local C_ActionBar = C_ActionBar
local C_Spell = C_Spell
local C_Timer = C_Timer
local GetPetActionCooldown = GetPetActionCooldown
local GetPetActionInfo = GetPetActionInfo
local GetPetActionSlotUsable = GetPetActionSlotUsable
local GetShapeshiftFormInfo = GetShapeshiftFormInfo
local GetTime = GetTime
local IsActionInRange = IsActionInRange
local UnitExists = UnitExists
local math_abs, next, pairs, type, wipe = math.abs, next, pairs, type, wipe

----------------------------------------------------------------------------------------
-- Shared State
----------------------------------------------------------------------------------------
local private = ActionBars.Private
local visual = private.COOLDOWN_VISUAL
local GCD_SPELL_ID = 61304

local COOLDOWN_FRAME_MASK = {
    NORMAL = 1,
    CHARGE = 2,
    LOSS_OF_CONTROL = 4,
}

local function IsCooldownFrameVisible(frame)
    return frame and frame.IsShown and frame:IsShown()
end

local function GetCooldownFrameMask(button)
    local mask = 0
    if IsCooldownFrameVisible(button and button.cooldown) then
        mask = mask + COOLDOWN_FRAME_MASK.NORMAL
    end
    if IsCooldownFrameVisible(button and button.chargeCooldown) then
        mask = mask + COOLDOWN_FRAME_MASK.CHARGE
    end
    if IsCooldownFrameVisible(button and button.lossOfControlCooldown) then
        mask = mask + COOLDOWN_FRAME_MASK.LOSS_OF_CONTROL
    end
    return mask
end

local function IsResetCooldownMask(mask)
    return mask == 0 or mask == COOLDOWN_FRAME_MASK.CHARGE
end

local function HasCooldownFrameFlag(mask, flag)
    return mask % (flag * 2) >= flag
end

local function IsCooldownVisualExcluded(button)
    return private.GetBarKeyForButton(button) == private.BAR_KEY.STANCE
end

-- Read timing from the cooldown APIs, not the Blizzard cooldown frame: once combat feeds
-- the frame secret values, its Cooldown secret aspect sticks until SetToDefaults().
local function GetCooldownRemainingSeconds(button)
    local startTime, duration, isOnGCD
    if button.action then
        local info = C_ActionBar.GetActionCooldown(button.action)
        if info then
            startTime, duration, isOnGCD = info.startTime, info.duration, info.isOnGCD
        end
    elseif private.GetBarKeyForButton(button) == private.BAR_KEY.PET then
        startTime, duration = GetPetActionCooldown(button:GetID())
    end

    if isOnGCD and (RefineUI:IsSecretValue(startTime) or RefineUI:IsSecretValue(duration)) then
        local info = C_Spell.GetSpellCooldown(GCD_SPELL_ID)
        if info then
            startTime, duration = info.startTime, info.duration
        end
    end

    if RefineUI:IsSecretValue(startTime) or RefineUI:IsSecretValue(duration)
        or type(startTime) ~= "number" or type(duration) ~= "number" or duration <= 0 then
        return nil, nil
    end

    local remaining = (startTime + duration) - GetTime()
    if remaining <= 0 then
        return 0, startTime
    end

    return remaining, startTime
end

local function ClearPendingActionRefresh()
    private.pendingAllActionRefresh = false
    private.pendingActionPageRefresh = false
    wipe(private.pendingActionSlotRefresh)
end

----------------------------------------------------------------------------------------
-- Cooldown State
----------------------------------------------------------------------------------------
local function SetButtonCooldownAlpha(button, alpha)
    if not button or not button.icon then
        return
    end

    local state = private.GetButtonState(button)
    local last = state.lastCooldownAlpha
    if last and math_abs(last - alpha) < visual.alphaEpsilon then
        return
    end

    button.icon:SetAlpha(alpha)
    state.lastCooldownAlpha = alpha
end

local function ResetButtonCooldownVisual(button, hideShade)
    if not button then
        return
    end
    local state = private.GetButtonState(button)
    private.StopCooldownIconFade(button)
    SetButtonCooldownAlpha(button, 1)
    if hideShade then
        private.SetCooldownShadeVisible(button, false)
    end
    state.cooldownFadeToken = nil
    state.cooldownVisualMode = "reset"
end

function private.UpdateCooldownState(button, frameMask)
    if not button or not button.icon or not button:IsVisible() then
        return false, false
    end

    local state = private.GetButtonState(button)
    frameMask = frameMask or GetCooldownFrameMask(button)
    local previousMask = state.cooldownFrameMask
    local previousMode = state.cooldownVisualMode
    state.cooldownFrameMask = frameMask

    if IsResetCooldownMask(frameMask) then
        if previousMask == frameMask and previousMode == "reset" then
            return false, false
        end
        if previousMode == "fade" then
            private.StopCooldownIconFade(button)
        end
        SetButtonCooldownAlpha(button, 1)
        state.cooldownFadeToken = nil
        state.cooldownVisualMode = "reset"
        return false, true
    end

    if HasCooldownFrameFlag(frameMask, COOLDOWN_FRAME_MASK.NORMAL) then
        local remainingSeconds, startTime = GetCooldownRemainingSeconds(button)
        if remainingSeconds and remainingSeconds > 0 then
            if remainingSeconds <= visual.gcdDuration then
                if previousMask == frameMask and previousMode == "fade" and state.cooldownFadeToken == startTime then
                    return true, false
                end

                private.StartCooldownIconFade(button, remainingSeconds)
                state.cooldownFadeToken = startTime
                state.cooldownVisualMode = "fade"
                return true, true
            end

            if previousMode == "fade" then
                private.StopCooldownIconFade(button)
            end
            state.cooldownFadeToken = nil

            if previousMask == frameMask and previousMode == "hold" then
                return true, false
            end

            SetButtonCooldownAlpha(button, visual.normalAlpha)
            state.cooldownVisualMode = "hold"
            return true, true
        end
    end

    if previousMask == frameMask and previousMode == "normal" then
        return true, false
    end

    if previousMode == "fade" then
        private.StopCooldownIconFade(button)
    end
    SetButtonCooldownAlpha(button, visual.normalAlpha)
    state.cooldownFadeToken = nil
    state.cooldownVisualMode = "normal"
    return true, true
end

function private.HandleButtonCooldownUpdate(button, frameMask)
    if not button or not private.SkinnedButtons[button] then
        return
    end
    if IsCooldownVisualExcluded(button) then
        ResetButtonCooldownVisual(button, true)
        return
    end
    local state = private.GetButtonState(button)
    local hasVisual, changed = private.UpdateCooldownState(button, frameMask or state.pendingCooldownFrameMask)
    state.pendingCooldownFrameMask = nil
    if not hasVisual then
        if changed then
            ResetButtonCooldownVisual(button, true)
        end
        return
    end
    private.SetCooldownShadeVisible(button, true)
end

----------------------------------------------------------------------------------------
-- Icon State
----------------------------------------------------------------------------------------
local function ApplyRenderState(button, renderState, force)
    if not button or not button.icon then
        return
    end

    local state = private.GetButtonState(button)
    if not force and state.renderState == renderState then
        return
    end

    local color = private.RANGE_COLORS[renderState] or private.RANGE_COLORS.normal
    button.icon:SetVertexColor(color[1], color[2], color[3])
    state.renderState = renderState
end

local function ResolveRenderState(button)
    local state = private.GetButtonState(button)
    if state.rangeState == "oor" then
        return "oor"
    end
    return state.usabilityState or "normal"
end

local function ApplyResolvedRenderState(button, force)
    ApplyRenderState(button, ResolveRenderState(button), force)
end

local function GetButtonUsabilityState(button)
    local barKey = private.GetBarKeyForButton(button)
    if barKey == "PetActionBar" then
        return GetPetActionSlotUsable(button:GetID()) and "normal" or "unusable"
    end

    if barKey == "StanceBar" then
        local _, _, isCastable = GetShapeshiftFormInfo(button:GetID())
        return isCastable and "normal" or "unusable"
    end

    if button.action and C_ActionBar and C_ActionBar.IsUsableAction then
        local isUsable, notEnoughMana = C_ActionBar.IsUsableAction(button.action)
        if notEnoughMana then
            return "oom"
        end
        if not isUsable then
            return "unusable"
        end
    end

    return "normal"
end

local function GetExplicitUsabilityState(button, isUsable, notEnoughMana)
    if isUsable == nil and notEnoughMana == nil then
        return GetButtonUsabilityState(button)
    end

    local barKey = private.GetBarKeyForButton(button)
    if barKey == "PetActionBar" or barKey == "StanceBar" then
        return GetButtonUsabilityState(button)
    end

    if notEnoughMana then
        return "oom"
    end
    if isUsable == false then
        return "unusable"
    end

    return "normal"
end

local function GetManualRangeState(button, hasTarget)
    if not hasTarget then
        return "normal"
    end

    local barKey = private.GetBarKeyForButton(button)
    if barKey == "PetActionBar" then
        local _, _, _, _, _, _, _, checksRange, inRange = GetPetActionInfo(button:GetID())
        if checksRange and inRange == false then
            return "oor"
        end
        return "normal"
    end

    if not button.action or not C_ActionBar then
        return "normal"
    end

    local checksRange = C_ActionBar.HasRangeRequirements and C_ActionBar.HasRangeRequirements(button.action)
    if not checksRange then
        return "normal"
    end

    local inRange = C_ActionBar.IsActionInRange and C_ActionBar.IsActionInRange(button.action) or IsActionInRange(button.action)
    if inRange == false then
        return "oor"
    end

    return "normal"
end

function private.RefreshButtonState(button, force, hasTarget)
    if not button or not button.icon or not private.SkinnedButtons[button] then
        return
    end

    local state = private.GetButtonState(button)
    state.usabilityState = GetButtonUsabilityState(button)
    state.rangeState = GetManualRangeState(button, hasTarget)
    ApplyResolvedRenderState(button, force)
end

function private.RefreshButtonUsability(button, force, isUsable, notEnoughMana)
    if not button or not button.icon or not private.SkinnedButtons[button] then
        return
    end

    private.GetButtonState(button).usabilityState = GetExplicitUsabilityState(button, isUsable, notEnoughMana)
    ApplyResolvedRenderState(button, force)
end

function private.RefreshButtonRange(button, force, hasTarget)
    if not button or not button.icon or not private.SkinnedButtons[button] then
        return
    end

    private.GetButtonState(button).rangeState = GetManualRangeState(button, hasTarget)
    ApplyResolvedRenderState(button, force)
end

function private.ApplyRangeIndicatorState(button, checksRange, inRange)
    if not button or not button.icon or not private.SkinnedButtons[button] then
        return
    end

    local state = private.GetButtonState(button)
    state.rangeState = (checksRange and inRange == false) and "oor" or "normal"
    ApplyResolvedRenderState(button, false)
end

----------------------------------------------------------------------------------------
-- Deferred Updates
----------------------------------------------------------------------------------------
local function RunDeferredFlush()
    private.deferredFlushScheduled = false
    private.FlushDeferredUpdates()
end

function private.FlushDeferredUpdates()
    local deferred = private.DeferredManager
    local hasTarget

    local button, pressed = next(deferred.PressButtons)
    while button do
        deferred.PressButtons[button] = nil
        private.SetPressedVisual(button, pressed)
        button, pressed = next(deferred.PressButtons)
    end

    button = next(deferred.CooldownButtons)
    while button do
        deferred.CooldownButtons[button] = nil
        local state = private.ButtonState[button]
        local pendingFrameMask = state and state.pendingCooldownFrameMask or nil
        if button:IsVisible() then
            private.HandleButtonCooldownUpdate(button, pendingFrameMask)
        elseif state then
            state.pendingCooldownFrameMask = nil
        end
        button = next(deferred.CooldownButtons)
    end

    button = next(deferred.StateButtons)
    while button do
        deferred.StateButtons[button] = nil
        if button:IsVisible() then
            if hasTarget == nil then
                hasTarget = UnitExists("target")
            end
            private.RefreshButtonState(button, true, hasTarget)
        end
        button = next(deferred.StateButtons)
    end

    button = next(deferred.RangeButtons)
    while button do
        deferred.RangeButtons[button] = nil
        local state = private.ButtonState[button]
        if state then
            private.ApplyRangeIndicatorState(button, state.pendingRangeChecks, state.pendingRangeInRange)
            state.pendingRangeChecks = nil
            state.pendingRangeInRange = nil
        end
        button = next(deferred.RangeButtons)
    end
end

function private.ScheduleDeferredFlush()
    if private.deferredFlushScheduled then
        return
    end

    private.deferredFlushScheduled = true
    C_Timer.After(0, RunDeferredFlush)
end

function private.QueueDeferredPress(button, pressed)
    if not button then
        return
    end
    private.DeferredManager.PressButtons[button] = pressed and true or false
    private.ScheduleDeferredFlush()
end

function private.QueueDeferredCooldownUpdate(button)
    if not button or not private.SkinnedButtons[button] then
        return
    end
    if IsCooldownVisualExcluded(button) then
        return
    end

    local state = private.GetButtonState(button)
    local frameMask = GetCooldownFrameMask(button)
    if private.DeferredManager.CooldownButtons[button] and state.pendingCooldownFrameMask == frameMask then
        return
    end

    if IsResetCooldownMask(frameMask) and state.cooldownFrameMask == frameMask and state.cooldownVisualMode == "reset" then
        return
    end

    state.pendingCooldownFrameMask = frameMask
    private.DeferredManager.CooldownButtons[button] = true
    private.ScheduleDeferredFlush()
end

function private.QueueDeferredStateUpdate(button)
    if not button or not private.SkinnedButtons[button] then
        return
    end
    local state = private.GetButtonState(button)
    private.DeferredManager.RangeButtons[button] = nil
    state.pendingRangeChecks = nil
    state.pendingRangeInRange = nil
    private.DeferredManager.StateButtons[button] = true
    private.ScheduleDeferredFlush()
end

function private.QueueDeferredRangeUpdate(button, checksRange, inRange)
    if not button or not private.SkinnedButtons[button] or private.DeferredManager.StateButtons[button] then
        return
    end

    local nextChecksRange = checksRange and true or false
    local nextRangeState = (nextChecksRange and inRange == false) and "oor" or "normal"
    local state = private.GetButtonState(button)
    if state.pendingRangeChecks ~= nil then
        if state.pendingRangeChecks == nextChecksRange and state.pendingRangeInRange == inRange then
            return
        end
    elseif state.rangeState == nextRangeState then
        return
    end

    if not button:IsVisible() then
        state.pendingRangeChecks = nil
        state.pendingRangeInRange = nil
        state.rangeState = nextRangeState
        return
    end
    state.pendingRangeChecks = nextChecksRange
    state.pendingRangeInRange = inRange
    private.DeferredManager.RangeButtons[button] = true
    private.ScheduleDeferredFlush()
end

----------------------------------------------------------------------------------------
-- Targeted Action Refresh
----------------------------------------------------------------------------------------
function ActionBars:RunActionButtonRefresh()
    local pendingSlots = private.pendingActionSlotRefresh
    local refreshAll = private.pendingAllActionRefresh
    local refreshPage = private.pendingActionPageRefresh
    private.pendingAllActionRefresh = false
    private.pendingActionPageRefresh = false
    if not private.actionbarsSetup or not next(private.ActionButtons) then
        wipe(pendingSlots)
        return
    end
    if refreshAll then
        private.RefreshButtonCollection(private.ActionButtons, true, true, true)
        wipe(pendingSlots)
        return
    end
    local hasTarget
    if refreshPage then
        hasTarget = UnitExists("target")
        for button in pairs(private.PagedButtons) do
            private.RefreshButton(button, true, true, true, hasTarget)
        end
    end
    if next(pendingSlots) then
        if hasTarget == nil then
            hasTarget = UnitExists("target")
        end
        for button in pairs(private.ActionButtons) do
            if not (refreshPage and private.PagedButtons[button]) then
                local action = button and button.action
                if action and pendingSlots[action] then
                    private.RefreshButton(button, true, true, true, hasTarget)
                end
            end
        end
    end

    wipe(pendingSlots)
end

local function RunQueuedActionButtonRefresh()
    ActionBars:RunActionButtonRefresh()
end
function ActionBars:QueueActionButtonRefresh(reason, slot)
    if not private.actionbarsSetup or not next(private.ActionButtons) then
        return
    end
    if reason == "ACTIONBAR_PAGE_CHANGED" then
        private.pendingActionPageRefresh = true
    elseif type(slot) == "number" and slot > 0 then
        private.pendingActionSlotRefresh[slot] = true
    else
        private.pendingAllActionRefresh = true
    end
    RefineUI:Debounce(private.DEBOUNCE_KEY.ACTION_BUTTON_REFRESH, private.ACTION_FULL_RESYNC_DEBOUNCE, RunQueuedActionButtonRefresh)
end

----------------------------------------------------------------------------------------
-- Full Resync
----------------------------------------------------------------------------------------
local function RunQueuedFullResync()
    ActionBars:RunFullResync()
end

function ActionBars:RunFullResync()
    if not private.actionbarsSetup then
        return
    end
    private.RefreshButtonCollection(private.SkinnedButtons, true, true, true)
end

function ActionBars:QueueFullResync()
    if not private.actionbarsSetup or not next(private.SkinnedButtons) then
        return
    end

    RefineUI:CancelDebounce(private.DEBOUNCE_KEY.ACTION_BUTTON_REFRESH)
    ClearPendingActionRefresh()
    RefineUI:Debounce(private.DEBOUNCE_KEY.FULL_RESYNC, private.ACTION_FULL_RESYNC_DEBOUNCE, RunQueuedFullResync)
end

function ActionBars:RefreshCombatButtonStates(force)
    if not private.actionbarsSetup then
        return
    end

    private.RefreshButtonCollection(private.ActionButtons, false, true, force)
    private.RefreshButtonCollection(private.PetButtons, false, true, force)
end

function ActionBars:RefreshTargetButtonRanges(force)
    if not private.actionbarsSetup then
        return
    end

    local hasTarget = UnitExists("target")
    private.RefreshButtonRangeCollection(private.ActionButtons, force == true, hasTarget)
    private.RefreshButtonRangeCollection(private.PetButtons, force == true, hasTarget)
end
