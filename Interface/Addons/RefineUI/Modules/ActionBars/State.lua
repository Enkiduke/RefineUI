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
local C_CurveUtil = C_CurveUtil
local C_Timer = C_Timer
local Enum = Enum
local GetPetActionInfo = GetPetActionInfo
local GetPetActionSlotUsable = GetPetActionSlotUsable
local GetShapeshiftFormInfo = GetShapeshiftFormInfo
local IsActionInRange = IsActionInRange
local UnitExists = UnitExists
local math_abs, next, pairs, type, wipe = math.abs, next, pairs, type, wipe

----------------------------------------------------------------------------------------
-- Shared State
----------------------------------------------------------------------------------------
local private = ActionBars.Private
local visual = private.COOLDOWN_VISUAL
local AlphaCurve = C_CurveUtil.CreateCurve()
AlphaCurve:SetType(Enum.LuaCurveType.Linear)
AlphaCurve:AddPoint(0, visual.gcdAlpha)
AlphaCurve:AddPoint(visual.gcdDuration, visual.gcdAlpha)
AlphaCurve:AddPoint(visual.gcdDuration + visual.alphaStep, visual.normalAlpha)
AlphaCurve:AddPoint(3600, visual.normalAlpha)

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

local function ClearTableEntries(map)
    if wipe then
        wipe(map)
        return
    end
    for key in pairs(map) do
        map[key] = nil
    end
end

local function ClearPendingActionRefresh()
    private.pendingAllActionRefresh = false
    private.pendingActionPageRefresh = false
    ClearTableEntries(private.pendingActionSlotRefresh)
end

----------------------------------------------------------------------------------------
-- Cooldown State
----------------------------------------------------------------------------------------
local function SetButtonCooldownAlpha(button, alpha)
    if not button or not button.icon then
        return
    end

    if type(RefineUI.IsSecretValue) == "function" and RefineUI:IsSecretValue(alpha) then
        button.icon:SetAlpha(alpha)
        private.GetButtonState(button).lastCooldownAlpha = nil
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
    if button.icon then
        SetButtonCooldownAlpha(button, 1)
    end
    if hideShade and private.SetCooldownShadeVisible then
        private.SetCooldownShadeVisible(button, false)
    end
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
    local normalShown = HasCooldownFrameFlag(frameMask, COOLDOWN_FRAME_MASK.NORMAL)
    local chargeShown = HasCooldownFrameFlag(frameMask, COOLDOWN_FRAME_MASK.CHARGE)
    local locShown = HasCooldownFrameFlag(frameMask, COOLDOWN_FRAME_MASK.LOSS_OF_CONTROL)
    state.cooldownFrameMask = frameMask

    if not normalShown and not chargeShown and not locShown then
        if previousMask == frameMask and previousMode == "reset" then
            return false, false
        end
        SetButtonCooldownAlpha(button, 1)
        state.cooldownVisualMode = "reset"
        return false, true
    end

    if chargeShown and not normalShown and not locShown then
        if previousMask == frameMask and previousMode == "reset" then
            return false, false
        end
        SetButtonCooldownAlpha(button, 1)
        state.cooldownVisualMode = "reset"
        return false, true
    end

    if button.action and C_ActionBar and C_ActionBar.GetActionCooldown then
        local cooldownInfo = C_ActionBar.GetActionCooldown(button.action)
        if cooldownInfo then
            local isOnGCD = cooldownInfo.isOnGCD
            if isOnGCD ~= nil and not RefineUI:IsSecretValue(isOnGCD) and normalShown and isOnGCD then
                if previousMask == frameMask and previousMode == "gcd" then
                    return true, false
                end
                SetButtonCooldownAlpha(button, visual.gcdAlpha)
                state.cooldownVisualMode = "gcd"
                return true, true
            end
        end
    end

    if normalShown and button.action and C_ActionBar and C_ActionBar.GetActionCooldownDuration then
        local cooldownDuration = C_ActionBar.GetActionCooldownDuration(button.action)
        if cooldownDuration and cooldownDuration.EvaluateRemainingDuration then
            SetButtonCooldownAlpha(button, cooldownDuration:EvaluateRemainingDuration(AlphaCurve))
            state.cooldownVisualMode = "duration"
            return true, true
        end
    end

    if previousMask == frameMask and previousMode == "normal" then
        return true, false
    end

    SetButtonCooldownAlpha(button, visual.normalAlpha)
    state.cooldownVisualMode = "normal"
    return true, true
end

function private.HandleButtonCooldownUpdate(button, frameMask)
    if not button or not private.SkinnedButtons[button] then
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
    if private.SetCooldownShadeVisible then
        private.SetCooldownShadeVisible(button, true)
    end
    if changed and private.IsActionResyncDebugEnabled() then
        private.ActionResyncDebug.cooldownPasses = private.ActionResyncDebug.cooldownPasses + 1
    end
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
    ApplyRenderState(button, ResolveRenderState(button), force)
end

function private.ApplyRangeIndicatorState(button, checksRange, inRange)
    if not button or not button.icon or not private.SkinnedButtons[button] then
        return
    end

    local state = private.GetButtonState(button)
    state.rangeState = (checksRange and inRange == false) and "oor" or "normal"
    ApplyRenderState(button, ResolveRenderState(button), false)

    if private.IsActionResyncDebugEnabled() then
        private.ActionResyncDebug.rangePasses = private.ActionResyncDebug.rangePasses + 1
    end
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
    private.DeferredManager.StateButtons[button] = true
    private.ScheduleDeferredFlush()
end

function private.QueueDeferredRangeUpdate(button, checksRange, inRange)
    if not button or not private.SkinnedButtons[button] then
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
        ClearTableEntries(pendingSlots)
        return
    end
    if refreshAll then
        private.RefreshButtonCollection(private.ActionButtons, true, true, true)
        ClearTableEntries(pendingSlots)
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

    ClearTableEntries(pendingSlots)
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
function ActionBars:GetActionResyncDebugSnapshot()
    local debugState = private.ActionResyncDebug
    local averageButtonsTouched = 0
    if debugState.executed > 0 then
        averageButtonsTouched = debugState.totalButtonsTouched / debugState.executed
    end

    return {
        queued = debugState.queued,
        executed = debugState.executed,
        averageButtonsTouched = averageButtonsTouched,
        lastReason = debugState.lastReason,
        fullPasses = debugState.fullPasses,
        cooldownPasses = debugState.cooldownPasses,
        rangePasses = debugState.rangePasses,
    }
end

function ActionBars:RunFullResync()
    if not private.actionbarsSetup or not next(private.SkinnedButtons) then
        return
    end
    local debugEnabled = private.IsActionResyncDebugEnabled()
    local touched = private.RefreshButtonCollection(private.SkinnedButtons, true, true, true)
    if debugEnabled then
        local debugState = private.ActionResyncDebug
        debugState.executed = debugState.executed + 1
        debugState.totalButtonsTouched = debugState.totalButtonsTouched + touched
        debugState.fullPasses = debugState.fullPasses + 1
    end
end

function ActionBars:QueueFullResync(reason)
    if not private.actionbarsSetup then
        private.fullResyncPendingSetup = true
        return
    end

    if not next(private.SkinnedButtons) then
        return
    end

    if private.IsActionResyncDebugEnabled() then
        local debugState = private.ActionResyncDebug
        debugState.queued = debugState.queued + 1
        debugState.lastReason = reason or "UNKNOWN"
    end
    RefineUI:CancelDebounce(private.DEBOUNCE_KEY.ACTION_BUTTON_REFRESH)
    ClearPendingActionRefresh()
    RefineUI:Debounce(private.DEBOUNCE_KEY.FULL_RESYNC, private.ACTION_FULL_RESYNC_DEBOUNCE, RunQueuedFullResync)
end

function ActionBars:RefreshAllButtonStates(force)
    if not private.actionbarsSetup or not next(private.StateTrackedButtons) then
        return
    end
    private.RefreshButtonCollection(private.StateTrackedButtons, false, true, force == true)
end
