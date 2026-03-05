----------------------------------------------------------------------------------------
-- ActionBars for RefineUI
-- Description: Lightweight skinning for Blizzard action buttons
----------------------------------------------------------------------------------------

local AddOnName, RefineUI = ...
local Module = RefineUI:RegisterModule("ActionBars")

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config
local Media = RefineUI.Media

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues 
----------------------------------------------------------------------------------------
local _G = _G
local pairs, ipairs, unpack, select = pairs, ipairs, unpack, select
local type = type
local tostring = tostring
local CreateFrame = CreateFrame
local GetTime = GetTime
local IsActionInRange = IsActionInRange
local InCombatLockdown = InCombatLockdown
local UnitExists = UnitExists
local ActionHasRange = ActionHasRange
local C_ActionBar = C_ActionBar
local NUM_ACTIONBAR_BUTTONS = NUM_ACTIONBAR_BUTTONS or 12
local NUM_PET_ACTION_SLOTS = NUM_PET_ACTION_SLOTS or 10
local NUM_STANCE_SLOTS = NUM_STANCE_SLOTS or 10
local math_abs = math.abs
local Config = RefineUI.Config
local Media = RefineUI.Media

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local GOLD_R, GOLD_G, GOLD_B = 1, 0.82, 0

local ACTION_BARS_STATE_REGISTRY = "ActionBarsState"
local ACTION_BARS_BUTTON_STATE_REGISTRY = "ActionBarsButtonState"
local ACTION_BARS_SKINNED_BUTTONS_REGISTRY = "ActionBarsSkinnedButtons"
local ACTION_BARS_BUTTON_BAR_KEY_REGISTRY = "ActionBarsButtonBarKey"

local JOB_KEY = {
    RANGE = "ActionBars:RangeUpdater",
    DEFERRED = "ActionBars:DeferredUpdater",
}

local THROTTLE = {
    RANGE_UPDATE_COMBAT = 0.1,
    RANGE_UPDATE_OOC = 0.35,
}

local RANGE_COLORS = {
    normal    = { 1.0, 1.0, 1.0 }, -- Neutral (Solid)
    oor       = { 0.8, 0.4, 0.4 }, -- Pale Red Glow
    oom       = { 0.4, 0.6, 1.0 }, -- Pale Blue Glow
    unusable  = { 0.3, 0.3, 0.3 }  -- Darkened Unusable
}
local COOLDOWN_SHADE_ALPHA = .25
local COOLDOWN_ALPHA_EPSILON = 0.01
local COOLDOWN_ALPHA_GCD_DURATION = 1.55
local COOLDOWN_ALPHA_GCD = 0.75
local COOLDOWN_ALPHA_NORMAL = 0.25
local COOLDOWN_ALPHA_STEP = 0.01

-- Maps bar keys to button name prefixes (used for per-bar hotkey lookup)
local BAR_KEY_TO_PREFIX = {
    MainMenuBar        = "ActionButton",
    MultiBarBottomLeft = "MultiBarBottomLeftButton",
    MultiBarBottomRight = "MultiBarBottomRightButton",
    MultiBarRight      = "MultiBarRightButton",
    MultiBarLeft       = "MultiBarLeftButton",
    MultiBar5          = "MultiBar5Button",
    MultiBar6          = "MultiBar6Button",
    MultiBar7          = "MultiBar7Button",
    PetActionBar       = "PetActionButton",
    StanceBar          = "StanceButton",
}

local ACTION_RESYNC_EVENTS = {
    "ACTIONBAR_SLOT_CHANGED",
    "ACTIONBAR_PAGE_CHANGED",
    "UPDATE_BONUS_ACTIONBAR",
    "UPDATE_VEHICLE_ACTIONBAR",
    "SPELLS_CHANGED",
    "PET_BAR_UPDATE",
    "UPDATE_SHAPESHIFT_FORMS",
    "PLAYER_MOUNT_DISPLAY_CHANGED",
}
local ACTION_RESYNC_DEBOUNCE = 0.03

local ACTION_RESYNC_FULL_EVENT_SET = {
    ACTIONBAR_SLOT_CHANGED = true,
    ACTIONBAR_PAGE_CHANGED = true,
    UPDATE_BONUS_ACTIONBAR = true,
    UPDATE_VEHICLE_ACTIONBAR = true,
    SPELLS_CHANGED = true,
    PET_BAR_UPDATE = true,
    UPDATE_SHAPESHIFT_FORMS = true,
    PLAYER_MOUNT_DISPLAY_CHANGED = true,
}

-- Reverse lookup: prefix -> bar key (built once)
local PREFIX_TO_BAR_KEY = {}
for barKey, prefix in pairs(BAR_KEY_TO_PREFIX) do
    PREFIX_TO_BAR_KEY[prefix] = barKey
end

local ButtonBarKeyCache

local function GetBarKeyForButton(button)
    if not button then return nil end

    local cached = ButtonBarKeyCache and ButtonBarKeyCache[button]
    if cached ~= nil then
        return cached or nil
    end

    local name = button:GetName()
    if not name then return nil end
    for prefix, barKey in pairs(PREFIX_TO_BAR_KEY) do
        if name:sub(1, #prefix) == prefix then
            if ButtonBarKeyCache then
                ButtonBarKeyCache[button] = barKey
            end
            return barKey
        end
    end
    if ButtonBarKeyCache then
        ButtonBarKeyCache[button] = false
    end
    return nil
end

local function IsHotkeyEnabledForButton(button)
    local db = Module.db
    if not db or not db.ShowHotkeys then return false end
    local barKey = GetBarKeyForButton(button)
    if not barKey then return false end
    return db.ShowHotkeys[barKey] == true
end

----------------------------------------------------------------------------------------
-- External State (Secure-safe)
----------------------------------------------------------------------------------------
local actionbarsSetup = false

local function GetActionBarState(owner, key, defaultValue)
    return RefineUI:RegistryGet(ACTION_BARS_STATE_REGISTRY, owner, key, defaultValue)
end

local function SetActionBarState(owner, key, value)
    if value == nil then
        RefineUI:RegistryClear(ACTION_BARS_STATE_REGISTRY, owner, key)
    else
        RefineUI:RegistrySet(ACTION_BARS_STATE_REGISTRY, owner, key, value)
    end
end

local function BuildActionBarHookKey(owner, method, qualifier)
    local ownerId
    if type(owner) == "table" and owner.GetName then
        ownerId = owner:GetName()
    end
    if not ownerId or ownerId == "" then
        ownerId = tostring(owner)
    end
    local key = "ActionBars:" .. ownerId .. ":" .. method
    if qualifier and qualifier ~= "" then
        key = key .. ":" .. qualifier
    end
    return key
end

-- Button State Storage (Weak table to allow GC)
local ButtonState = RefineUI:CreateDataRegistry(ACTION_BARS_BUTTON_STATE_REGISTRY, "k")
local SkinnedButtons = RefineUI:CreateDataRegistry(ACTION_BARS_SKINNED_BUTTONS_REGISTRY, "k")
ButtonBarKeyCache = RefineUI:CreateDataRegistry(ACTION_BARS_BUTTON_BAR_KEY_REGISTRY, "k")
Module.SkinnedButtons = Module.SkinnedButtons or SkinnedButtons

-- Helper to access state safely
local function GetButtonState(button)
    local s = ButtonState[button]
    if not s then
        s = {}
        ButtonState[button] = s
    end
    return s
end

local EnsureSchedulerJobs

local DeferredManager = {
    PressButtons = {},
    RangeButtons = {},
    ActionResyncRequested = false,
    ActionResyncNeedsFull = false,
    ActionResyncNeedsCooldown = false,
    ActionResyncNeedsRange = false,
    ActionResyncDueAt = 0,
    scheduled = false,
}

local function ResolveActionResyncNeeds(reason)
    if reason and ACTION_RESYNC_FULL_EVENT_SET[reason] then
        return true, false, false
    end
    if reason == "ACTIONBAR_UPDATE_COOLDOWN" then
        return false, true, false
    end
    if reason == "ACTIONBAR_UPDATE_USABLE" or reason == "ACTIONBAR_UPDATE_STATE" then
        return false, false, true
    end
    return true, false, false
end

local function HasDeferredWork()
    if next(DeferredManager.PressButtons) then return true end
    if DeferredManager.ActionResyncRequested then return true end
    if next(DeferredManager.RangeButtons) then return true end
    return false
end

local function ScheduleDeferredFlush()
    if DeferredManager.scheduled then return end
    if EnsureSchedulerJobs then
        EnsureSchedulerJobs()
    end
    DeferredManager.scheduled = true
    RefineUI:SetUpdateJobEnabled(JOB_KEY.DEFERRED, true, true)
end

local function QueueDeferredPress(button, pressed)
    if not button then return end
    DeferredManager.PressButtons[button] = pressed and true or false
    ScheduleDeferredFlush()
end

local function QueueDeferredRangeUpdate(button)
    if not button or not SkinnedButtons[button] then return end
    DeferredManager.RangeButtons[button] = true
    ScheduleDeferredFlush()
end

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------

-- NOTE: We intentionally avoid SetDesaturation() AND SetVertexColor()
-- on button.icon for cooldown visuals because:
--   SetDesaturation: taints the texture's internal state, causing
--     Blizzard's UpdateUsable (icon:IsDesaturated()) to error
--   SetVertexColor: conflicts with Blizzard's UpdateUsable which uses
--     SetVertexColor to show unusable spells (no resources, etc.)
-- We use alpha dimming + a fixed dark overlay instead.

local SetCooldownShadeVisible

-- Secret-safe alpha curve: two-level darkness.
-- GCD window stays lighter; anything above shifts to normal dark.
local AlphaCurve = C_CurveUtil.CreateCurve()
AlphaCurve:SetType(Enum.LuaCurveType.Linear)
AlphaCurve:AddPoint(0, COOLDOWN_ALPHA_GCD)
AlphaCurve:AddPoint(COOLDOWN_ALPHA_GCD_DURATION, COOLDOWN_ALPHA_GCD)
AlphaCurve:AddPoint(COOLDOWN_ALPHA_GCD_DURATION + COOLDOWN_ALPHA_STEP, COOLDOWN_ALPHA_NORMAL)
AlphaCurve:AddPoint(3600, COOLDOWN_ALPHA_NORMAL)

local function SetButtonCooldownAlpha(button, alpha)
    if not button or not button.icon then return end
    if type(RefineUI.IsSecretValue) == "function" and RefineUI:IsSecretValue(alpha) then
        button.icon:SetAlpha(alpha)
        local state = GetButtonState(button)
        state.lastCooldownAlpha = nil
        return
    end
    local state = GetButtonState(button)
    local last = state.lastCooldownAlpha
    if last and math_abs(last - alpha) < COOLDOWN_ALPHA_EPSILON then
        return
    end
    button.icon:SetAlpha(alpha)
    state.lastCooldownAlpha = alpha
end

local function ResetButtonCooldownVisual(button, hideShade)
    if not button then return end
    if button.icon then
        SetButtonCooldownAlpha(button, 1)
    end
    if hideShade then
        SetCooldownShadeVisible(button, false)
    end
end

-- Secret-safe cooldown visual update.
local function UpdateCooldownState(button)
    if not button or not button.action or not button.icon or not button:IsVisible() then
        return false
    end

    local cooldownInfo = C_ActionBar.GetActionCooldownDuration(button.action)
    if not (cooldownInfo and cooldownInfo.EvaluateRemainingDuration) then
        SetButtonCooldownAlpha(button, 1)
        return false
    end

    local alpha = cooldownInfo:EvaluateRemainingDuration(AlphaCurve)
    SetButtonCooldownAlpha(button, alpha)
    return true
end

local function EnsureCooldownShade(button)
    if not button then return nil end
    local state = GetButtonState(button)
    if state.CooldownShade then
        return state.CooldownShade
    end

    local shade = button:CreateTexture(nil, "ARTWORK", nil, 2)
    shade:SetColorTexture(0, 0, 0, COOLDOWN_SHADE_ALPHA)
    shade:SetBlendMode("BLEND")
    shade:ClearAllPoints()
    RefineUI.Point(shade, "TOPLEFT", button, "TOPLEFT", 1, -1)
    RefineUI.Point(shade, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    shade:Hide()

    state.CooldownShade = shade
    return shade
end

SetCooldownShadeVisible = function(button, visible)
    local state = button and ButtonState[button]
    local shade = state and state.CooldownShade
    if not shade then return end

    if visible then
        if not shade:IsShown() then
            shade:Show()
        end
    else
        if shade:IsShown() then
            shade:Hide()
        end
    end
end

-- Range/Usability Logic
local SetRangePolling

local function UpdateRangeState(button, force, hasTarget)
    if not button.action or not button.icon or not button:IsVisible() then return end

    local stateData = GetButtonState(button)
    hasTarget = (hasTarget == nil) and UnitExists("target") or hasTarget
    
    if stateData.lastRangeAction ~= button.action then
        stateData.lastRangeAction = button.action
        if C_ActionBar and C_ActionBar.HasRangeRequirements then
            stateData.hasRangeRequirement = C_ActionBar.HasRangeRequirements(button.action) and true or false
        elseif ActionHasRange then
            stateData.hasRangeRequirement = ActionHasRange(button.action) and true or false
        else
            stateData.hasRangeRequirement = true
        end
    end

    local currentState = stateData.rangeState or "normal"
    -- Most non-range actions don't change from normal without Blizzard usability events.
    -- Skip periodic polling for those and rely on forced updates/hooks.
    if (not force) and (not stateData.hasRangeRequirement) and currentState == "normal" then
        SetRangePolling(button, false)
        return
    end

    local isUsable, notEnoughMana = C_ActionBar.IsUsableAction(button.action)
    
    local state = "normal"
    if notEnoughMana then
        state = "oom"
    elseif stateData.hasRangeRequirement and hasTarget then
        local inRange
        if C_ActionBar and C_ActionBar.IsActionInRange then
            inRange = C_ActionBar.IsActionInRange(button.action)
        else
            inRange = IsActionInRange(button.action)
        end

        if inRange == false then
            state = "oor"
        elseif not isUsable then
            state = "unusable"
        end
    elseif not isUsable then
        state = "unusable"
    end
    
    local shouldPoll = stateData.hasRangeRequirement or state ~= "normal"
    SetRangePolling(button, shouldPoll)

    -- Only update if state changed OR forced to fight Blizzard internal updates
    if force or currentState ~= state then
        local color = RANGE_COLORS[state]
        button.icon:SetVertexColor(color[1], color[2], color[3])
        
        -- Always use BLEND to keep icons solid and opaque
        button.icon:SetBlendMode("BLEND")
        
        stateData.rangeState = state
    end
end

-- Centralized Range Manager (Throttled for performance)
local RangeManager = {}
RangeManager.ActiveButtons = {}
RangeManager.PollButtons = {}

SetRangePolling = function(button, shouldPoll)
    if not button then return end
    if shouldPoll then
        RangeManager.PollButtons[button] = true
    else
        RangeManager.PollButtons[button] = nil
    end
end

local function RefreshRangeStates(force)
    local hasTarget = UnitExists("target")
    for button in pairs(RangeManager.ActiveButtons) do
        if button:IsVisible() and button.action then
            UpdateRangeState(button, force, hasTarget)
        end
    end
end

local function UpdateRangeManagerVisibility()
    local shouldEnable = false

    if not next(RangeManager.PollButtons) then
        shouldEnable = false
    elseif InCombatLockdown() or UnitExists("target") then
        shouldEnable = true
    end

    RefineUI:SetUpdateJobInterval(
        JOB_KEY.RANGE,
        InCombatLockdown() and THROTTLE.RANGE_UPDATE_COMBAT or THROTTLE.RANGE_UPDATE_OOC
    )
    RefineUI:SetUpdateJobEnabled(JOB_KEY.RANGE, shouldEnable, false)
end

local function RangeUpdateJob()
    local inCombat = InCombatLockdown()
    local hasTarget = UnitExists("target")
    if not inCombat and not hasTarget then
        RefineUI:SetUpdateJobEnabled(JOB_KEY.RANGE, false, false)
        return
    end

    local hasActive = false
    for button in pairs(RangeManager.PollButtons) do
        if button:IsVisible() and button.action then
            UpdateRangeState(button, false, hasTarget)
            hasActive = true
        else
            RangeManager.PollButtons[button] = nil
            RangeManager.ActiveButtons[button] = nil
        end
    end
    
    if not hasActive then
        RefineUI:SetUpdateJobEnabled(JOB_KEY.RANGE, false, false)
    end
end

----------------------------------------------------------------------------------------
-- Visual Press Logic
----------------------------------------------------------------------------------------

local function SetPressedVisual(button, pressed)
    local state = ButtonState[button] -- Use localized GetButtonState or direct access
    if not state then return end
    
    local overlay = state.SkinOverlay
    local border = overlay and overlay.border
    
    if pressed then
        if state.PressAnimation then
            state.PressAnimation:Stop()
            state.PressAnimation:Play()
        end
        if border and border.SetBackdropBorderColor and border.GetBackdropBorderColor then
            state.RestoreR, state.RestoreG, state.RestoreB, state.RestoreA = border:GetBackdropBorderColor()
            border:SetBackdropBorderColor(1, 1, 1, 1)
        end
    else
        if border then
            if state.RestoreR then
                border:SetBackdropBorderColor(state.RestoreR, state.RestoreG, state.RestoreB, state.RestoreA)
            elseif state.OriginalR then
                border:SetBackdropBorderColor(state.OriginalR, state.OriginalG, state.OriginalB, state.OriginalA)
            end
        end
    end
end

-- Shared Hook Handlers (Static references to reduce memory/GC fragmentation)
function Module.Cooldown_OnShow(self)
    local button = GetActionBarState(self, "RefineButton")
    if button and button.action then
        UpdateCooldownState(button)
        SetCooldownShadeVisible(button, true)
    end
end

function Module.Cooldown_OnHide(self)
    local button = GetActionBarState(self, "RefineButton")
    if button then
        ResetButtonCooldownVisual(button, true)
    end
end

function Module.Cooldown_OnDone(self)
    local button = GetActionBarState(self, "RefineButton")
    if button then
        ResetButtonCooldownVisual(button, true)
    end
end

-- Shared Visual Hooks
function Module.Button_OnEnter(self)
    local state = ButtonState[self]
    if state and state.SkinOverlay and state.SkinOverlay.border and state.SkinOverlay.border.SetBackdropBorderColor then
        state.SkinOverlay.border:SetBackdropBorderColor(GOLD_R, GOLD_G, GOLD_B, 1)
    end
end

function Module.Button_OnLeave(self)
    local state = ButtonState[self]
    if state and state.SkinOverlay and state.SkinOverlay.border and state.OriginalR then
        state.SkinOverlay.border:SetBackdropBorderColor(state.OriginalR, state.OriginalG, state.OriginalB, state.OriginalA)
    end
end

function Module.Button_OnMouseDown(self)
    SetPressedVisual(self, true)
end

function Module.Button_OnMouseUp(self)
    SetPressedVisual(self, false)
end

-- Cooldown visual logic is driven by Blizzard cooldown frame callbacks.
local function HandleButtonCooldownUpdate(button)
    if not button or not SkinnedButtons[button] then return end

    if not (button.cooldown and button.cooldown:IsShown()) then
        ResetButtonCooldownVisual(button, true)
    else
        UpdateCooldownState(button)
        SetCooldownShadeVisible(button, true)
    end
end

local function HandleButtonRangeUpdate(button, hasTarget)
    if not button or not SkinnedButtons[button] then return end
    RangeManager.ActiveButtons[button] = true
    UpdateRangeState(button, true, hasTarget)
end

local function HandleButtonActionUpdate(button, hasTarget)
    if not button or not SkinnedButtons[button] then return end
    HandleButtonCooldownUpdate(button)
    HandleButtonRangeUpdate(button, hasTarget)
end

local actionResyncPendingSetup = false
local ActionResyncDebug = {
    queued = 0,
    executed = 0,
    totalButtonsTouched = 0,
    lastReason = nil,
    fullPasses = 0,
    cooldownPasses = 0,
    rangePasses = 0,
}

local function IsActionResyncDebugEnabled()
    return type(RefineUI.IsObservabilityEnabled) == "function" and RefineUI:IsObservabilityEnabled()
end

local function QueueActionBarsResync(reason)
    if not actionbarsSetup then
        actionResyncPendingSetup = true
        return
    end
    if not next(SkinnedButtons) then
        return
    end

    if IsActionResyncDebugEnabled() then
        ActionResyncDebug.queued = ActionResyncDebug.queued + 1
        ActionResyncDebug.lastReason = reason or "UNKNOWN"
    end

    local needFull, needCooldown, needRange = ResolveActionResyncNeeds(reason)
    if needFull then
        DeferredManager.ActionResyncNeedsFull = true
        DeferredManager.ActionResyncNeedsCooldown = false
        DeferredManager.ActionResyncNeedsRange = false
    else
        if needCooldown then
            DeferredManager.ActionResyncNeedsCooldown = true
        end
        if needRange then
            DeferredManager.ActionResyncNeedsRange = true
        end
    end

    if not DeferredManager.ActionResyncRequested then
        DeferredManager.ActionResyncDueAt = GetTime() + ACTION_RESYNC_DEBOUNCE
    end
    DeferredManager.ActionResyncRequested = true
    ScheduleDeferredFlush()
end

local function RunActionBarsResync(runCooldown, runRange, runFull)
    if not actionbarsSetup then return end
    if not next(SkinnedButtons) then return end
    if not runCooldown and not runRange then return end

    local hasTarget = runRange and UnitExists("target") or nil
    local touched = 0
    for button in pairs(SkinnedButtons) do
        if button then
            local visible = button:IsVisible()
            if visible then
                if runCooldown and runRange then
                    HandleButtonActionUpdate(button, hasTarget)
                elseif runCooldown then
                    HandleButtonCooldownUpdate(button)
                else
                    HandleButtonRangeUpdate(button, hasTarget)
                end
                touched = touched + 1
            end
        end
    end
    if runRange then
        UpdateRangeManagerVisibility()
    end

    if IsActionResyncDebugEnabled() then
        ActionResyncDebug.executed = ActionResyncDebug.executed + 1
        ActionResyncDebug.totalButtonsTouched = ActionResyncDebug.totalButtonsTouched + touched
        if runFull then
            ActionResyncDebug.fullPasses = ActionResyncDebug.fullPasses + 1
        elseif runCooldown then
            ActionResyncDebug.cooldownPasses = ActionResyncDebug.cooldownPasses + 1
        elseif runRange then
            ActionResyncDebug.rangePasses = ActionResyncDebug.rangePasses + 1
        end
    end
end

function Module:GetActionResyncDebugSnapshot()
    local executed = ActionResyncDebug.executed
    local avgButtons = 0
    if executed > 0 then
        avgButtons = ActionResyncDebug.totalButtonsTouched / executed
    end
    return {
        queued = ActionResyncDebug.queued,
        executed = executed,
        averageButtonsTouched = avgButtons,
        lastReason = ActionResyncDebug.lastReason,
        fullPasses = ActionResyncDebug.fullPasses,
        cooldownPasses = ActionResyncDebug.cooldownPasses,
        rangePasses = ActionResyncDebug.rangePasses,
    }
end

local function DeferredUpdateJob()
    local hasTarget

    for button, pressed in pairs(DeferredManager.PressButtons) do
        DeferredManager.PressButtons[button] = nil
        SetPressedVisual(button, pressed)
    end

    if DeferredManager.ActionResyncRequested then
        local now = GetTime()
        if now >= (DeferredManager.ActionResyncDueAt or 0) then
            local runFull = DeferredManager.ActionResyncNeedsFull and true or false
            local runCooldown = runFull or DeferredManager.ActionResyncNeedsCooldown
            local runRange = runFull or DeferredManager.ActionResyncNeedsRange

            DeferredManager.ActionResyncRequested = false
            DeferredManager.ActionResyncNeedsFull = false
            DeferredManager.ActionResyncNeedsCooldown = false
            DeferredManager.ActionResyncNeedsRange = false
            DeferredManager.ActionResyncDueAt = 0

            RunActionBarsResync(runCooldown, runRange, runFull)
        end
    end

    for button in pairs(DeferredManager.RangeButtons) do
        DeferredManager.RangeButtons[button] = nil
        if hasTarget == nil then
            hasTarget = UnitExists("target")
        end
        UpdateRangeState(button, true, hasTarget)
    end

    if not HasDeferredWork() then
        DeferredManager.scheduled = false
        RefineUI:SetUpdateJobEnabled(JOB_KEY.DEFERRED, false, false)
    end
end

local function EnableDesaturation(button)
    if not button then return end
    EnsureCooldownShade(button)
    
    -- Link frames directly to avoid parent crawling in hooks
    if button.cooldown then
        SetActionBarState(button.cooldown, "RefineButton", button)
    end

    -- Hook range manager
    RangeManager.ActiveButtons[button] = true
    UpdateRangeManagerVisibility()

    -- Ensure cooldown cleanup on completion (Optional safety)
    if button.cooldown and button.cooldown.HookScript then
        RefineUI:HookScriptOnce(
            BuildActionBarHookKey(button.cooldown, "OnShow", "Cooldown"),
            button.cooldown,
            "OnShow",
            Module.Cooldown_OnShow
        )
        RefineUI:HookScriptOnce(
            BuildActionBarHookKey(button.cooldown, "OnHide", "Cooldown"),
            button.cooldown,
            "OnHide",
            Module.Cooldown_OnHide
        )
        RefineUI:HookScriptOnce(
            BuildActionBarHookKey(button.cooldown, "OnCooldownDone", "Cooldown"),
            button.cooldown,
            "OnCooldownDone",
            Module.Cooldown_OnDone
        )
    end
    
    -- Register in skinned buttons pool (for debugging/bulk updates if ever needed)
    SkinnedButtons[button] = true
    
    -- Initial check
    if button.cooldown and button.cooldown:IsShown() then
        UpdateCooldownState(button)
        SetCooldownShadeVisible(button, true)
    else
        ResetButtonCooldownVisual(button, true)
    end
    
    UpdateRangeState(button, false, UnitExists("target"))
end

function Module.EnableDesaturation(button)
    EnableDesaturation(button)
end

----------------------------------------------------------------------------------------
-- Button Styling
----------------------------------------------------------------------------------------

-- Helper to style cooldown text (Increase size)
function Module:StyleCooldownText(cooldown)
    if not cooldown then return end
    local regions = {cooldown:GetRegions()}
    for _, region in pairs(regions) do
        if region:GetObjectType() == "FontString" then
            -- Identify the timer text (usually the first/only FontString)
            -- We set it to a larger size (e.g. 19) and use the Number font
            region:SetFont(Media.Fonts.Number, 24, "OUTLINE")
            
            -- Hook usage just to be safe if it resets? 
            -- Usually SetFont persists unless Blizzard specifically overwrites the font object
            -- For now, just setting it here should be enough for default action bars
        end
    end
end

-- Style a single action button
function Module:StyleButton(button)
    local state = GetButtonState(button)
    if not button or state.isSkinned then return end
    
    local name = button:GetName()
    if not name then return end
    
    local icon = _G[name .. "Icon"] or button.icon or button.Icon
    local count = _G[name .. "Count"]
    local cooldown = _G[name .. "Cooldown"] or button.cooldown
    local normal = _G[name .. "NormalTexture"] or button:GetNormalTexture()
    local flash = _G[name .. "Flash"]
    local hotkey = button.HotKey or _G[name .. "HotKey"]
    local macroName = _G[name .. "Name"]
    
    -- Hide default textures
    if normal then normal:SetAlpha(0) end
    if button.IconMask then button.IconMask:Hide() end
    if button.SlotArt then button.SlotArt:Hide() end
    if button.SlotBackground then button.SlotBackground:Hide() end
    if button.RightDivider then button.RightDivider:Hide() end
    if macroName then macroName:Hide() end
    if button.AutoCastOverlay and button.AutoCastOverlay.Corners then
        button.AutoCastOverlay.Corners:Hide()
    end
    
    -- Hide Blizzard's hover/pushed overlays that cover the border
    if button.PushedTexture then
        button.PushedTexture:SetAlpha(0)
    elseif button.GetPushedTexture then
        local pt = button:GetPushedTexture()
        if pt then pt:SetAlpha(0) end
    end
    
    -- Hide highlight texture that covers border on hover 
    if button.HighlightTexture then
        button.HighlightTexture:SetAlpha(0)
    elseif button.GetHighlightTexture then
        local ht = button:GetHighlightTexture()
        if ht then ht:SetAlpha(0) end
    end
    
    -- Style icon
    if icon then
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:ClearAllPoints()
        RefineUI.Point(icon, "TOPLEFT", button, "TOPLEFT", 1, -1)
        RefineUI.Point(icon, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        icon:SetBlendMode("BLEND") -- Default back to BLEND
    end
    EnsureCooldownShade(button)
    
    -- Style count
    if count then
        count:SetParent(button)
        count:SetJustifyH("RIGHT")
        count:ClearAllPoints()
        RefineUI.Point(count, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
        count:SetDrawLayer("OVERLAY", 1)
        RefineUI.Font(count, 12, nil, "THINOUTLINE")
    end
    
    -- Hotkey binding text (per-bar setting)
    if hotkey then
        if IsHotkeyEnabledForButton(button) then
            hotkey:ClearAllPoints()
            RefineUI.Point(hotkey, "TOPRIGHT", button, "TOPRIGHT", -2, -4)
            RefineUI.Font(hotkey, 11, nil, "THINOUTLINE")
            hotkey:SetAlpha(1)
            hotkey:Show()
        else
            hotkey:SetText("")
            hotkey:SetAlpha(0)
            hotkey:Hide()
        end
    end
    
    -- Create cooldown overlay frame (sits above border at DIALOG strata like OLD)
    if cooldown then
        -- Create overlay container if not exists
        if not state.RefineCooldownOverlay then
            local overlay = CreateFrame("Frame", nil, button)
            overlay:SetAllPoints(button)
            overlay:SetFrameStrata("DIALOG")
            overlay:SetFrameLevel((button:GetFrameLevel() or 0) + 60)
            overlay:EnableMouse(false)
            state.RefineCooldownOverlay = overlay
        end
        
        -- Reparent cooldown to overlay
        local overlay = state.RefineCooldownOverlay
        cooldown:SetParent(overlay)
        cooldown:ClearAllPoints()
        cooldown:SetAllPoints(overlay)
        cooldown:SetDrawEdge(false)
        cooldown:SetDrawSwipe(true)
        cooldown:SetSwipeColor(0, 0, 0, 0.8)
        if cooldown.SetSwipeTexture and Media.Textures.CooldownSwipe then
            cooldown:SetSwipeTexture(Media.Textures.CooldownSwipe)
        end
        
        -- Style the text size
        Module:StyleCooldownText(cooldown)
    end
    
    -- Style flash
    if flash then
        flash:SetTexture(Media.Textures.Statusbar)
        flash:SetVertexColor(0.55, 0, 0, 0.5)
    end
    
    
    -- Apply RefineUI styling (Via Overlay to avoid Taint)
    if not state.SkinOverlay then
        local overlay = CreateFrame("Frame", nil, button)
        overlay:SetAllPoints(button)
        -- Overlay needs to be visible but not intercept mouse if frame level is high? 
        -- Actually, frames without scripts don't intercept mouse usually, or we can disable mouse.
        overlay:EnableMouse(false) 
        state.SkinOverlay = overlay
        
        RefineUI.SetTemplate(overlay, "Icon")
    end
    
    -- Store original border color for restoration in safe state
    -- Note: We check the overlay's border now
    local overlay = state.SkinOverlay
    if overlay and overlay.border and overlay.border.GetBackdropBorderColor then
        state.OriginalR, state.OriginalG, state.OriginalB, state.OriginalA = overlay.border:GetBackdropBorderColor()
    else
        local borderColor = Config.General.BorderColor
        state.OriginalR, state.OriginalG, state.OriginalB, state.OriginalA = borderColor[1], borderColor[2], borderColor[3], borderColor[4]
    end
    
    -- Shared static hooks to reduce closure memory
    RefineUI:HookScriptOnce(
        BuildActionBarHookKey(button, "OnEnter", "Style"),
        button,
        "OnEnter",
        Module.Button_OnEnter
    )
    RefineUI:HookScriptOnce(
        BuildActionBarHookKey(button, "OnLeave", "Style"),
        button,
        "OnLeave",
        Module.Button_OnLeave
    )
    
    -- Press animation
    if not state.PressAnimation then
        local ag = button:CreateAnimationGroup()
        local a1 = ag:CreateAnimation("Translation")
        a1:SetOffset(3, -3)
        a1:SetDuration(0.05)
        a1:SetOrder(1)
        a1:SetSmoothing("IN")
        
        local a2 = ag:CreateAnimation("Translation")
        a2:SetOffset(-3, 3)
        a2:SetDuration(0.10)
        a2:SetOrder(2)
        
        local a3 = ag:CreateAnimation("Translation")
        a3:SetOffset(0, 0)
        a3:SetDuration(0.05)
        a3:SetOrder(3)
        
        ag:SetLooping("NONE")
        state.PressAnimation = ag
    end
    
    -- Mouse hooks for press visual
    RefineUI:HookScriptOnce(
        BuildActionBarHookKey(button, "OnMouseDown", "Style"),
        button,
        "OnMouseDown",
        Module.Button_OnMouseDown
    )
    RefineUI:HookScriptOnce(
        BuildActionBarHookKey(button, "OnMouseUp", "Style"),
        button,
        "OnMouseUp",
        Module.Button_OnMouseUp
    )
    
    -- Enable Desaturation logic
    EnableDesaturation(button)
    
    state.isSkinned = true
end

-- Style multiple buttons by name pattern
local function StyleButtons(buttonNames, count)
    for _, name in ipairs(buttonNames) do
        for i = 1, count do
            local button = _G[name .. i]
            if button then Module:StyleButton(button) end
        end
    end
end

----------------------------------------------------------------------------------------
-- Press Animation Hooks (Keybind Press Support)
----------------------------------------------------------------------------------------

-- Hook Mixin (Modern) — deferred to avoid tainting Blizzard's event dispatch context
if ActionBarActionButtonMixin and ActionBarActionButtonMixin.SetButtonStateOverride then
    RefineUI:HookOnce("ActionBars:ActionBarActionButtonMixin:SetButtonStateOverride", ActionBarActionButtonMixin, "SetButtonStateOverride", function(self, state)
        QueueDeferredPress(self, state == "PUSHED")
    end)
end

-- Hook Global Input Functions (Legacy/Fallback)
do
    local function TriggerPressed(button, pressed)
        if button then
            SetPressedVisual(button, pressed)
        end
    end
    
    local function TriggerByID(id, pressed)
        local button = _G.GetActionButtonForID and _G.GetActionButtonForID(id)
        if button then TriggerPressed(button, pressed) end
    end
    
    if _G.ActionButtonDown then
        RefineUI:HookOnce("ActionBars:ActionButtonDown", "ActionButtonDown", function(id) TriggerByID(id, true) end)
    end
    if _G.ActionButtonUp then
        RefineUI:HookOnce("ActionBars:ActionButtonUp", "ActionButtonUp", function(id) TriggerByID(id, false) end)
    end
    
    if _G.MultiActionButtonDown then
        RefineUI:HookOnce("ActionBars:MultiActionButtonDown", "MultiActionButtonDown", function(bar, id)
            local button = _G[bar.."Button"..id]
            if button then TriggerPressed(button, true) end
        end)
    end
    if _G.MultiActionButtonUp then
        RefineUI:HookOnce("ActionBars:MultiActionButtonUp", "MultiActionButtonUp", function(bar, id)
            local button = _G[bar.."Button"..id]
            if button then TriggerPressed(button, false) end
        end)
    end
    
    if _G.PetActionButtonDown then
        RefineUI:HookOnce("ActionBars:PetActionButtonDown", "PetActionButtonDown", function(id)
            local button = _G["PetActionButton"..id]
            if button then TriggerPressed(button, true) end
        end)
    end
    if _G.PetActionButtonUp then
        RefineUI:HookOnce("ActionBars:PetActionButtonUp", "PetActionButtonUp", function(id)
            local button = _G["PetActionButton"..id]
            if button then TriggerPressed(button, false) end
        end)
    end
    
    if _G.StanceButtonDown then
        RefineUI:HookOnce("ActionBars:StanceButtonDown", "StanceButtonDown", function(id)
            local button = _G["StanceButton"..id]
            if button then TriggerPressed(button, true) end
        end)
    end
    if _G.StanceButtonUp then
        RefineUI:HookOnce("ActionBars:StanceButtonUp", "StanceButtonUp", function(id)
            local button = _G["StanceButton"..id]
            if button then TriggerPressed(button, false) end
        end)
    end
end

-- Force Range Update on Blizzard state refreshes
-- All hooks deferred off the protected call stack to avoid tainting Blizzard's
-- event dispatch context (prevents secret value errors in CooldownViewer etc.)
local function DeferRangeUpdate(button)
    if not InCombatLockdown() and not UnitExists("target") then
        return
    end
    QueueDeferredRangeUpdate(button)
end

-- Modern WoW uses Mixins for Action Buttons
if ActionBarActionButtonMixin and ActionBarActionButtonMixin.UpdateUsable then
    RefineUI:HookOnce("ActionBars:ActionBarActionButtonMixin:UpdateUsable", ActionBarActionButtonMixin, "UpdateUsable", function(self)
        DeferRangeUpdate(self)
    end)
elseif ActionButtonMixin and ActionButtonMixin.UpdateUsable then
    RefineUI:HookOnce("ActionBars:ActionButtonMixin:UpdateUsable", ActionButtonMixin, "UpdateUsable", function(self)
        DeferRangeUpdate(self)
    end)
elseif ActionButton_UpdateUsable then
    RefineUI:HookOnce("ActionBars:ActionButton_UpdateUsable", "ActionButton_UpdateUsable", function(self)
        DeferRangeUpdate(self)
    end)
end

-- Pet and Stance updates often use their own functions/mixins
if PetActionButtonMixin then
    if PetActionButtonMixin.Update then
        RefineUI:HookOnce("ActionBars:PetActionButtonMixin:Update", PetActionButtonMixin, "Update", function(self)
            DeferRangeUpdate(self)
        end)
    end
    if PetActionButtonMixin.UpdateUsable then
        RefineUI:HookOnce("ActionBars:PetActionButtonMixin:UpdateUsable", PetActionButtonMixin, "UpdateUsable", function(self)
            DeferRangeUpdate(self)
        end)
    end
elseif PetActionButton_Update then
    RefineUI:HookOnce("ActionBars:PetActionButton_Update", "PetActionButton_Update", function(self)
        DeferRangeUpdate(self)
    end)
end

if StanceBar_Update then
    RefineUI:HookOnce("ActionBars:StanceBar_Update", "StanceBar_Update", function()
        for i = 1, NUM_STANCE_SLOTS do
            DeferRangeUpdate(_G["StanceButton"..i])
        end
    end)
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------

function Module:SetupActionBars()
    if InCombatLockdown() then return end
    if actionbarsSetup then return end
    
    local buttonGroups = {
        {
            names = {
                "ActionButton",
                "MultiBarBottomLeftButton",
                "MultiBarLeftButton",
                "MultiBarRightButton",
                "MultiBarBottomRightButton",
                "MultiBar5Button",
                "MultiBar6Button",
                "MultiBar7Button"
            },
            count = NUM_ACTIONBAR_BUTTONS
        },
        { names = {"PetActionButton"}, count = NUM_PET_ACTION_SLOTS },
        { names = {"StanceButton"}, count = NUM_STANCE_SLOTS },
    }
    
    for _, group in ipairs(buttonGroups) do
        StyleButtons(group.names, group.count)
    end
    
    -- Per-bar hotkey visibility (hook Blizzard's mixin method to enforce our per-bar setting)
    if ActionBarActionButtonMixin and ActionBarActionButtonMixin.UpdateHotkeys then
        RefineUI:HookOnce("ActionBars:ActionBarActionButtonMixin:UpdateHotkeys", ActionBarActionButtonMixin, "UpdateHotkeys", function(button)
            local hotkey = button.HotKey
            if not hotkey then return end
            if IsHotkeyEnabledForButton(button) then
                hotkey:SetAlpha(1)
            else
                hotkey:SetAlpha(0)
            end
        end)
    end
    
    -- Setup Extra Action Bars
    if self.SetupExtraActionBars then
        self:SetupExtraActionBars()
    end
    
    -- Setup Vehicle Action Bars
    if self.SetupVehicleActionBars then
        self:SetupVehicleActionBars()
    end

    actionbarsSetup = true
    if actionResyncPendingSetup then
        actionResyncPendingSetup = false
        QueueActionBarsResync("POST_SETUP_PENDING")
    else
        QueueActionBarsResync("POST_SETUP")
    end
end




----------------------------------------------------------------------------------------
-- Edit Mode Integration
----------------------------------------------------------------------------------------

local function RefreshHotkeysForBar(barKey)
    local prefix = BAR_KEY_TO_PREFIX[barKey]
    if not prefix then return end
    local db = Module.db
    local enabled = db and db.ShowHotkeys and db.ShowHotkeys[barKey] == true
    local count = (barKey == "PetActionBar") and NUM_PET_ACTION_SLOTS
            or (barKey == "StanceBar") and NUM_STANCE_SLOTS
            or NUM_ACTIONBAR_BUTTONS
    for i = 1, count do
        local button = _G[prefix .. i]
        if button then
            local hotkey = button.HotKey or _G[prefix .. i .. "HotKey"]
            if hotkey then
                if enabled then
                    hotkey:ClearAllPoints()
                    RefineUI.Point(hotkey, "TOPRIGHT", button, "TOPRIGHT", -2, -4)
                    RefineUI.Font(hotkey, 11, nil, "THINOUTLINE")
                    hotkey:SetAlpha(1)
                    if button.UpdateHotkeys then
                        button:UpdateHotkeys(button.buttonType)
                    end
                else
                    hotkey:SetAlpha(0)
                end
            end
        end
    end
end

function Module:RegisterEditModeSettings()
    if not RefineUI.LibEditMode then return end
    
    if self.editModeRegistered then return end
    self.editModeRegistered = true
    
    -- All action bars (including Stance and Pet) use ActionBarSystem with subSystemIndices
    -- from Enum.EditModeActionBarSystemIndices (see Blizzard API docs)
    Module.SystemFrames = {}
    local ActionBarSystem = Enum.EditModeSystem.ActionBar
    if not ActionBarSystem then ActionBarSystem = 1 end

    local definitions = {
        { frame = MainActionBar, system = ActionBarSystem, index = 1, name = "MainMenuBar" },
        { frame = MultiBarBottomLeft, system = ActionBarSystem, index = 2, name = "MultiBarBottomLeft" },
        { frame = MultiBarBottomRight, system = ActionBarSystem, index = 3, name = "MultiBarBottomRight" },
        { frame = MultiBarRight, system = ActionBarSystem, index = 4, name = "MultiBarRight" },
        { frame = MultiBarLeft, system = ActionBarSystem, index = 5, name = "MultiBarLeft" },
        { frame = MultiBar5, system = ActionBarSystem, index = 6, name = "MultiBar5" },
        { frame = MultiBar6, system = ActionBarSystem, index = 7, name = "MultiBar6" },
        { frame = MultiBar7, system = ActionBarSystem, index = 8, name = "MultiBar7" },
        { frame = StanceBar, system = ActionBarSystem, index = 11, name = "StanceBar" },
        { frame = PetActionBar, system = ActionBarSystem, index = 12, name = "PetActionBar" },
    }

    if not RefineUI.EditModeRegistrations then RefineUI.EditModeRegistrations = {} end

    for _, def in ipairs(definitions) do
        local bar = def.frame
        local systemID = def.system
        local systemIndex = def.index
        
        if bar and systemID then
            -- Store Frame Mapping
            if not Module.SystemFrames[systemID] then Module.SystemFrames[systemID] = {} end
            local mapKey = systemIndex or "Base"
            Module.SystemFrames[systemID][mapKey] = bar
            
            -- Global Idempotency Check
            local registrationKey = systemID .. "-" .. mapKey
            if not RefineUI.EditModeRegistrations[registrationKey] then
                -- Mouseover option intentionally removed to keep bar visibility consistent.
                RefineUI.EditModeRegistrations[registrationKey] = true
            end

            -- Register "Show Hotkeys" checkbox per bar
            local lib = RefineUI.LibEditMode
            if lib and lib.SettingType and type(lib.AddSystemSettings) == "function" then
                local settingType = lib.SettingType
                local barKey = def.name
                local db = Module.db
                lib:AddSystemSettings(systemID, {
                    {
                        kind = settingType.Checkbox,
                        name = "Show Hotkeys",
                        default = false,
                        get = function()
                            return db and db.ShowHotkeys and db.ShowHotkeys[barKey] == true
                        end,
                        set = function(_, value)
                            if db then
                                if not db.ShowHotkeys then db.ShowHotkeys = {} end
                                db.ShowHotkeys[barKey] = value and true or false
                                RefreshHotkeysForBar(barKey)
                            end
                        end,
                    },
                }, systemIndex)
            end
        end
    end
end

----------------------------------------------------------------------------------------
-- Centralized Mouseover Manager
----------------------------------------------------------------------------------------

local MouseoverManager = CreateFrame("Frame")
MouseoverManager.Bars = {}
local SetHoverFromCursor
local mouseoverEventsInitialized = false

local function RefreshAllMouseoverBars()
    for bar in pairs(MouseoverManager.Bars) do
        SetHoverFromCursor(bar)
    end
end

local function EvaluateMouseoverVisibility(bar)
    if not bar then return end
    if not GetActionBarState(bar, "RefineUIMouseoverEnabled", false) then return end

    local inEditMode = RefineUI.LibEditMode and RefineUI.LibEditMode:IsInEditMode()
    local dragging = GetCursorInfo() ~= nil
    local gridShown = bar.showgrid and bar.showgrid > 0
    local hovered = GetActionBarState(bar, "RefineUIMouseoverHovered", false)
    local shouldShow = (inEditMode or dragging or gridShown or hovered) and true or false
    local isVisible = GetActionBarState(bar, "RefineUIMouseoverVisible", nil)

    if isVisible == shouldShow then
        return
    end

    SetActionBarState(bar, "RefineUIMouseoverVisible", shouldShow)
    if shouldShow then
        RefineUI:FadeIn(bar, 0.2, 1)
    else
        RefineUI:FadeOut(bar, 0.2, 0)
    end
end

SetHoverFromCursor = function(bar)
    if not bar then return end
    if not GetActionBarState(bar, "RefineUIMouseoverEnabled", false) then return end

    SetActionBarState(bar, "RefineUIMouseoverHovered", MouseIsOver(bar) and true or false)
    EvaluateMouseoverVisibility(bar)
end

local function QueueHoverRefresh(bar)
    if not bar then return end
    if GetActionBarState(bar, "RefineUIMouseoverRefreshQueued", false) then
        return
    end

    SetActionBarState(bar, "RefineUIMouseoverRefreshQueued", true)
    C_Timer.After(0, function()
        SetActionBarState(bar, "RefineUIMouseoverRefreshQueued", false)
        SetHoverFromCursor(bar)
    end)
end

local function HookMouseoverElement(bar, element)
    if not element or type(element.HookScript) ~= "function" then return end
    if GetActionBarState(element, "RefineUIMouseoverElementHooked", false) then return end

    RefineUI:HookScriptOnce(
        BuildActionBarHookKey(element, "OnEnter", "Mouseover"),
        element,
        "OnEnter",
        function()
            SetActionBarState(bar, "RefineUIMouseoverHovered", true)
            EvaluateMouseoverVisibility(bar)
        end
    )
    RefineUI:HookScriptOnce(
        BuildActionBarHookKey(element, "OnLeave", "Mouseover"),
        element,
        "OnLeave",
        function()
            QueueHoverRefresh(bar)
        end
    )

    SetActionBarState(element, "RefineUIMouseoverElementHooked", true)
end

local function HookBarButtonsForMouseover(bar)
    if not bar or GetActionBarState(bar, "RefineUIMouseoverButtonsHooked", false) then
        return
    end

    local base
    local count
    if bar == MainMenuBar then
        base, count = "ActionButton", NUM_ACTIONBAR_BUTTONS
    elseif bar == MultiBarBottomLeft then
        base, count = "MultiBarBottomLeftButton", NUM_ACTIONBAR_BUTTONS
    elseif bar == MultiBarBottomRight then
        base, count = "MultiBarBottomRightButton", NUM_ACTIONBAR_BUTTONS
    elseif bar == MultiBarRight then
        base, count = "MultiBarRightButton", NUM_ACTIONBAR_BUTTONS
    elseif bar == MultiBarLeft then
        base, count = "MultiBarLeftButton", NUM_ACTIONBAR_BUTTONS
    elseif bar == MultiBar5 then
        base, count = "MultiBar5Button", NUM_ACTIONBAR_BUTTONS
    elseif bar == MultiBar6 then
        base, count = "MultiBar6Button", NUM_ACTIONBAR_BUTTONS
    elseif bar == MultiBar7 then
        base, count = "MultiBar7Button", NUM_ACTIONBAR_BUTTONS
    elseif bar == PetActionBar then
        base, count = "PetActionButton", NUM_PET_ACTION_SLOTS
    elseif bar == StanceBar then
        base, count = "StanceButton", NUM_STANCE_SLOTS
    end

    if base and count then
        for i = 1, count do
            local button = _G[base .. i]
            if button then
                HookMouseoverElement(bar, button)
            end
        end
    end

    SetActionBarState(bar, "RefineUIMouseoverButtonsHooked", true)
end

local function EnsureMouseoverManagerEvents()
    if mouseoverEventsInitialized then return end

    MouseoverManager:RegisterEvent("ACTIONBAR_SHOWGRID")
    MouseoverManager:RegisterEvent("ACTIONBAR_HIDEGRID")
    MouseoverManager:RegisterEvent("CURSOR_CHANGED")
    MouseoverManager:SetScript("OnEvent", function()
        RefreshAllMouseoverBars()
    end)

    mouseoverEventsInitialized = true
end

local editModeHooksInitialized = false
local function EnsureEditModeMouseoverHooks()
    if editModeHooksInitialized then return end
    if not EditModeManagerFrame or type(EditModeManagerFrame.HookScript) ~= "function" then return end

    RefineUI:HookScriptOnce(
        "ActionBars:EditModeManagerFrame:OnShow:Mouseover",
        EditModeManagerFrame,
        "OnShow",
        RefreshAllMouseoverBars
    )
    RefineUI:HookScriptOnce(
        "ActionBars:EditModeManagerFrame:OnHide:Mouseover",
        EditModeManagerFrame,
        "OnHide",
        RefreshAllMouseoverBars
    )
    editModeHooksInitialized = true
end

function Module:UpdateMouseoverState(bar, enabled)
    if not bar then return end
    
    if enabled then
        EnsureMouseoverManagerEvents()
        EnsureEditModeMouseoverHooks()
        SetActionBarState(bar, "RefineUIMouseoverEnabled", true)
        self:HookMouseover(bar)
        SetHoverFromCursor(bar)
    else
        SetActionBarState(bar, "RefineUIMouseoverEnabled", false)
        SetActionBarState(bar, "RefineUIMouseoverHovered", false)
        SetActionBarState(bar, "RefineUIMouseoverVisible", nil)
        MouseoverManager.Bars[bar] = nil
        RefineUI:FadeIn(bar, 0.2, 1)
    end
end

function Module:HookMouseover(bar)
    EnsureMouseoverManagerEvents()
    EnsureEditModeMouseoverHooks()

    if GetActionBarState(bar, "RefineUIMouseoverHooked", false) then 
        if GetActionBarState(bar, "RefineUIMouseoverEnabled", false) then
            MouseoverManager.Bars[bar] = true
            SetHoverFromCursor(bar)
        end
        return 
    end
    
    HookMouseoverElement(bar, bar)
    HookBarButtonsForMouseover(bar)
    RefineUI:HookScriptOnce(
        BuildActionBarHookKey(bar, "OnShow", "Mouseover"),
        bar,
        "OnShow",
        function()
            SetHoverFromCursor(bar)
        end
    )
    RefineUI:HookScriptOnce(
        BuildActionBarHookKey(bar, "OnHide", "Mouseover"),
        bar,
        "OnHide",
        function()
            SetActionBarState(bar, "RefineUIMouseoverHovered", false)
            SetActionBarState(bar, "RefineUIMouseoverVisible", nil)
        end
    )
    
    MouseoverManager.Bars[bar] = true
    SetHoverFromCursor(bar)
    
    SetActionBarState(bar, "RefineUIMouseoverHooked", true)
end

local schedulerInitialized = false
EnsureSchedulerJobs = function()
    if schedulerInitialized then return end
    if not RefineUI.RegisterUpdateJob then return end

    RefineUI:RegisterUpdateJob(
        JOB_KEY.RANGE,
        THROTTLE.RANGE_UPDATE_OOC,
        RangeUpdateJob,
        { enabled = false }
    )
    RefineUI:RegisterUpdateJob(
        JOB_KEY.DEFERRED,
        0,
        DeferredUpdateJob,
        { enabled = false }
    )

    schedulerInitialized = true
end

----------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------

function Module:OnInitialize()
    self.db = RefineUI.DB and RefineUI.DB.ActionBars or RefineUI.Config.ActionBars
end

function Module:OnEnable()
    if not self.db or not self.db.Enable then return end
    EnsureSchedulerJobs()

    RefineUI:RegisterEventCallback("PLAYER_REGEN_DISABLED", function()
        RefreshRangeStates(true)
        UpdateRangeManagerVisibility()
    end, "ActionBars:RangeEnterCombat")

    RefineUI:RegisterEventCallback("PLAYER_REGEN_ENABLED", function()
        if not actionbarsSetup then
            self:SetupActionBars()
        end
        RefreshRangeStates(true)
        UpdateRangeManagerVisibility()
    end, "ActionBars:RangeLeaveCombat")

    RefineUI:RegisterEventCallback("PLAYER_TARGET_CHANGED", function()
        RefreshRangeStates(true)
        UpdateRangeManagerVisibility()
    end, "ActionBars:RangeTargetChanged")

    RefineUI:OnEvents(ACTION_RESYNC_EVENTS, function(event)
        QueueActionBarsResync(event)
    end, "ActionBars:ActionResync")
    
    -- Setup on entering world
    RefineUI:OnEvents({"PLAYER_ENTERING_WORLD"}, function()
        self:SetupActionBars()
    end)
    
    self:RegisterEditModeSettings()
end
