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
local IsUsableAction = IsUsableAction
local IsActionInRange = IsActionInRange
local InCombatLockdown = InCombatLockdown
local UnitExists = UnitExists
local ActionHasRange = ActionHasRange
local C_ActionBar = C_ActionBar
local NUM_ACTIONBAR_BUTTONS = NUM_ACTIONBAR_BUTTONS or 12
local NUM_PET_ACTION_SLOTS = NUM_PET_ACTION_SLOTS or 10
local NUM_STANCE_SLOTS = NUM_STANCE_SLOTS or 10
local Config = RefineUI.Config
local Media = RefineUI.Media

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local GOLD_R, GOLD_G, GOLD_B = 1, 0.82, 0

local ACTION_BARS_STATE_REGISTRY = "ActionBarsState"
local ACTION_BARS_BUTTON_STATE_REGISTRY = "ActionBarsButtonState"
local ACTION_BARS_SKINNED_BUTTONS_REGISTRY = "ActionBarsSkinnedButtons"

local JOB_KEY = {
    COOLDOWN = "ActionBars:CooldownUpdater",
    RANGE = "ActionBars:RangeUpdater",
}

local THROTTLE = {
    COOLDOWN_UPDATE = 0.05,
    RANGE_UPDATE_COMBAT = 0.1,
    RANGE_UPDATE_OOC = 0.35,
}

local RANGE_COLORS = {
    normal    = { 1.0, 1.0, 1.0 }, -- Neutral (Solid)
    oor       = { 0.8, 0.4, 0.4 }, -- Pale Red Glow
    oom       = { 0.4, 0.6, 1.0 }, -- Pale Blue Glow
    unusable  = { 0.3, 0.3, 0.3 }  -- Darkened Unusable
}

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

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------

-- Saturation Curve: Grey (>1.5s) -> Colored (0s)
local SaturationCurve = C_CurveUtil.CreateCurve()
SaturationCurve:SetType(Enum.LuaCurveType.Linear)
SaturationCurve:AddPoint(0, 0)      -- 0s remaining: Colored (0 Desat)
SaturationCurve:AddPoint(1.5, 1)    -- 1.5s remaining: Grey (1 Desat)
SaturationCurve:AddPoint(3600, 1)   -- >1.5s remaining: Grey (1 Desat)

-- Alpha Curve: Dark (>1.5s) -> Bright (0s)
local AlphaCurve = C_CurveUtil.CreateCurve()
AlphaCurve:SetType(Enum.LuaCurveType.Linear)
AlphaCurve:AddPoint(0, 1)      -- 0s remaining: Fully Visible (1.0)
AlphaCurve:AddPoint(1.5, 0.3)  -- 1.5s remaining: Darkened/Faded (0.3)
AlphaCurve:AddPoint(3600, 0.3) -- >1.5s remaining: Faded (0.3)

-- Desaturation Logic
local function UpdateCooldownState(button)
    if not button.action or not button.icon or not button:IsVisible() then return end
    
    -- Fetch current duration info (GCD or Spell CD)
    local cooldownInfo = C_ActionBar.GetActionCooldownDuration(button.action)
    
    if cooldownInfo and cooldownInfo.EvaluateRemainingDuration then
        -- Evaluate visuals
        local desaturation = cooldownInfo:EvaluateRemainingDuration(SaturationCurve)
        local alpha = cooldownInfo:EvaluateRemainingDuration(AlphaCurve)
        
        button.icon:SetDesaturation(desaturation)
        button.icon:SetAlpha(alpha)
    else
        button.icon:SetDesaturation(0)
        button.icon:SetAlpha(1)
    end
end

-- Centralized Cooldown Updater
local CooldownUpdater = {}
CooldownUpdater.ActiveButtons = {}

local function CooldownUpdateJob()
    local hasActive = false
    for button in pairs(CooldownUpdater.ActiveButtons) do
        if button and button.action and button.icon and button:IsVisible() then
            UpdateCooldownState(button)
            hasActive = true
        else
            CooldownUpdater.ActiveButtons[button] = nil
            if button and button.icon then
                button.icon:SetDesaturation(0)
                button.icon:SetAlpha(1)
            end
        end
    end
    
    if not hasActive then
        RefineUI:SetUpdateJobEnabled(JOB_KEY.COOLDOWN, false, false)
    end
end

-- Range/Usability Logic
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

    local currentState = GetActionBarState(button, "RefineRangeState", "normal")
    -- Most non-range actions don't change from normal without Blizzard usability events.
    -- Skip periodic polling for those and rely on forced updates/hooks.
    if (not force) and (not stateData.hasRangeRequirement) and currentState == "normal" then
        return
    end

    local isUsable, notEnoughMana = IsUsableAction(button.action)
    
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
    
    -- Only update if state changed OR forced to fight Blizzard internal updates
    if force or currentState ~= state then
        local color = RANGE_COLORS[state]
        button.icon:SetVertexColor(color[1], color[2], color[3])
        
        -- Always use BLEND to keep icons solid and opaque
        button.icon:SetBlendMode("BLEND")
        
        -- Optional: Desaturate slightly for non-normal states to make it pop
        button.icon:SetDesaturation(state == "normal" and 0 or 0.2)
        
        SetActionBarState(button, "RefineRangeState", state)
    end
end

-- Centralized Range Manager (Throttled for performance)
local RangeManager = {}
RangeManager.ActiveButtons = {}

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

    if not next(RangeManager.ActiveButtons) then
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
    for button in pairs(RangeManager.ActiveButtons) do
        if button:IsVisible() and button.action then
            UpdateRangeState(button, false, hasTarget)
            hasActive = true
        else
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
        CooldownUpdater.ActiveButtons[button] = true
        RefineUI:SetUpdateJobEnabled(JOB_KEY.COOLDOWN, true, false)
        UpdateCooldownState(button)
    end
end

function Module.Cooldown_OnHide(self)
    local button = GetActionBarState(self, "RefineButton")
    if button then
        CooldownUpdater.ActiveButtons[button] = nil
        if button.icon then
            button.icon:SetDesaturation(0)
            button.icon:SetAlpha(1)
        end
    end
    if not next(CooldownUpdater.ActiveButtons) then
        RefineUI:SetUpdateJobEnabled(JOB_KEY.COOLDOWN, false, false)
    end
end

function Module.Cooldown_OnDone(self)
    local button = GetActionBarState(self, "RefineButton")
    if button then
        CooldownUpdater.ActiveButtons[button] = nil
        if button.icon then
            button.icon:SetDesaturation(0)
            button.icon:SetAlpha(1)
        end
    end
    if not next(CooldownUpdater.ActiveButtons) then
        RefineUI:SetUpdateJobEnabled(JOB_KEY.COOLDOWN, false, false)
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

-- desaturation update logic is handled via Scheduler jobs and ActiveButtons pool.

local function EnableDesaturation(button)
    if not button then return end
    
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
        CooldownUpdater.ActiveButtons[button] = true
        RefineUI:SetUpdateJobEnabled(JOB_KEY.COOLDOWN, true, false)
        UpdateCooldownState(button)
    end
    
    UpdateRangeState(button, false, UnitExists("target"))

    -- Update on action change: Blizzard's UpdateAction often triggers a refresh,
    -- but our visibility hooks will handle the Updater pool.
    -- We just ensure a clean state if the action changes and cooldown hides.
    RefineUI:HookOnce(BuildActionBarHookKey(button, "UpdateAction"), button, "UpdateAction", function(self)
        RangeManager.ActiveButtons[self] = true
        UpdateRangeManagerVisibility()

        if not (self.cooldown and self.cooldown:IsShown()) then
            CooldownUpdater.ActiveButtons[self] = nil
            if self.icon then
                self.icon:SetDesaturation(0)
                self.icon:SetAlpha(1)
            end
            if not next(CooldownUpdater.ActiveButtons) then
                RefineUI:SetUpdateJobEnabled(JOB_KEY.COOLDOWN, false, false)
            end
        end
        UpdateRangeState(self, true, UnitExists("target"))
    end)
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
    
    -- Style count
    if count then
        count:SetParent(button)
        count:SetJustifyH("RIGHT")
        count:ClearAllPoints()
        RefineUI.Point(count, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
        count:SetDrawLayer("OVERLAY", 1)
        RefineUI.Font(count, 12, nil, "THINOUTLINE")
    end
    
    -- Hide hotkey binding text
    if hotkey then
        local showHotkey = Module.db and Module.db.HotKey
        if not showHotkey then
            hotkey:SetText("")
            hotkey:SetAlpha(0)
            hotkey:Hide()
        else
            hotkey:ClearAllPoints()
            RefineUI.Point(hotkey, "TOPRIGHT", button, "TOPRIGHT", -2, -4)
            RefineUI.Font(hotkey, 11, nil, "THINOUTLINE")
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

-- Hook Mixin (Modern)
if ActionBarActionButtonMixin and ActionBarActionButtonMixin.SetButtonStateOverride then
    RefineUI:HookOnce("ActionBars:ActionBarActionButtonMixin:SetButtonStateOverride", ActionBarActionButtonMixin, "SetButtonStateOverride", function(self, state)
        if state == "PUSHED" then
            SetPressedVisual(self, true)
        else
            SetPressedVisual(self, false)
        end
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
-- Modern WoW uses Mixins for Action Buttons
if ActionBarActionButtonMixin and ActionBarActionButtonMixin.UpdateUsable then
    RefineUI:HookOnce("ActionBars:ActionBarActionButtonMixin:UpdateUsable", ActionBarActionButtonMixin, "UpdateUsable", function(self)
        UpdateRangeState(self, true)
    end)
elseif ActionButtonMixin and ActionButtonMixin.UpdateUsable then
    RefineUI:HookOnce("ActionBars:ActionButtonMixin:UpdateUsable", ActionButtonMixin, "UpdateUsable", function(self)
        UpdateRangeState(self, true)
    end)
elseif ActionButton_UpdateUsable then
    RefineUI:HookOnce("ActionBars:ActionButton_UpdateUsable", "ActionButton_UpdateUsable", function(self)
        UpdateRangeState(self, true)
    end)
end

-- Pet and Stance updates often use their own functions/mixins
if PetActionButtonMixin then
    if PetActionButtonMixin.Update then
        RefineUI:HookOnce("ActionBars:PetActionButtonMixin:Update", PetActionButtonMixin, "Update", function(self)
            UpdateRangeState(self, true)
        end)
    end
    if PetActionButtonMixin.UpdateUsable then
        RefineUI:HookOnce("ActionBars:PetActionButtonMixin:UpdateUsable", PetActionButtonMixin, "UpdateUsable", function(self)
            UpdateRangeState(self, true)
        end)
    end
elseif PetActionButton_Update then
    RefineUI:HookOnce("ActionBars:PetActionButton_Update", "PetActionButton_Update", function(self)
        UpdateRangeState(self, true)
    end)
end

if StanceBar_Update then
    RefineUI:HookOnce("ActionBars:StanceBar_Update", "StanceBar_Update", function()
        for i = 1, NUM_STANCE_SLOTS do
            local button = _G["StanceButton"..i]
            if button then UpdateRangeState(button, true) end
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
    
    -- Optimized Hotkey Hiding (Wait for modern buttons to be styled)
    if not (Module.db and Module.db.HotKey) then
        if ActionBarButtonEventsFrame and ActionBarButtonEventsFrame.UpdateEvents then
            RefineUI:HookOnce("ActionBars:ActionButton_UpdateHotkeys", "ActionButton_UpdateHotkeys", function(button)
                local hotkey = button.HotKey
                if hotkey then
                    hotkey:SetText("")
                    hotkey:Hide()
                end
            end)
        end
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
end




----------------------------------------------------------------------------------------
-- Edit Mode Integration
----------------------------------------------------------------------------------------

function Module:RegisterEditModeSettings()
    if not RefineUI.LibEditMode then return end
    
    if self.editModeRegistered then return end
    self.editModeRegistered = true
    
    -- Actually, we must register separately for each systemID to capture the ID in the closure.
    -- MainMenuBar = 1, MultiBarBottomLeft = 2, MultiBarBottomRight = 3, MultiBarRight = 4, MultiBarLeft = 5
    -- MultiBar5 = 6, MultiBar6 = 7, MultiBar7 = 8
    -- StanceBar = 15? PetFrame = 16?
    
    Module.SystemFrames = {}

    local ActionBarSystem = Enum.EditModeSystem.ActionBar
    -- Fallback for older clients or if missing?
    if not ActionBarSystem then ActionBarSystem = 1 end -- Should be safe if we are on modern WoW

    local StanceBarSystem = Enum.EditModeSystem.StanceBar or (StanceBar and StanceBar.system)
    local PetFrameSystem = Enum.EditModeSystem.PetFrame or (PetActionBar and PetActionBar.system)

    local definitions = {
        { frame = MainMenuBar, system = ActionBarSystem, index = 1, name = "MainMenuBar" },
        { frame = MultiBarBottomLeft, system = ActionBarSystem, index = 2, name = "MultiBarBottomLeft" },
        { frame = MultiBarBottomRight, system = ActionBarSystem, index = 3, name = "MultiBarBottomRight" },
        { frame = MultiBarRight, system = ActionBarSystem, index = 4, name = "MultiBarRight" },
        { frame = MultiBarLeft, system = ActionBarSystem, index = 5, name = "MultiBarLeft" },
        { frame = MultiBar5, system = ActionBarSystem, index = 6, name = "MultiBar5" },
        { frame = MultiBar6, system = ActionBarSystem, index = 7, name = "MultiBar6" },
        { frame = MultiBar7, system = ActionBarSystem, index = 8, name = "MultiBar7" },
        { frame = StanceBar, system = StanceBarSystem, index = nil, name = "StanceBar" },
        { frame = PetActionBar, system = PetFrameSystem, index = nil, name = "PetActionBar" },
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
local function EnsureSchedulerJobs()
    if schedulerInitialized then return end
    if not RefineUI.RegisterUpdateJob then return end

    RefineUI:RegisterUpdateJob(
        JOB_KEY.COOLDOWN,
        THROTTLE.COOLDOWN_UPDATE,
        CooldownUpdateJob,
        { enabled = false }
    )
    RefineUI:RegisterUpdateJob(
        JOB_KEY.RANGE,
        THROTTLE.RANGE_UPDATE_OOC,
        RangeUpdateJob,
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
    
    -- Setup on entering world
    RefineUI:OnEvents({"PLAYER_ENTERING_WORLD"}, function()
        self:SetupActionBars()
    end)
    
    self:RegisterEditModeSettings()
end
