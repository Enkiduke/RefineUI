----------------------------------------------------------------------------------------
-- ActionBars Skin
-- Description: Button styling, overlays, cooldown chrome, and press visuals.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local ActionBars = RefineUI:GetModule("ActionBars")
if not ActionBars then
    return
end

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config
local Media = RefineUI.Media

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local CreateFrame = CreateFrame
local ipairs = ipairs
local pairs = pairs
local select = select

----------------------------------------------------------------------------------------
-- Shared State
----------------------------------------------------------------------------------------
local private = ActionBars.Private

----------------------------------------------------------------------------------------
-- Visual Helpers
----------------------------------------------------------------------------------------
local function SetBorderColor(border, r, g, b, a)
    if border and border.SetBackdropBorderColor then
        border:SetBackdropBorderColor(r, g, b, a)
    end
end

local function ApplyButtonBorderVisual(state, border)
    if not border then
        return
    end

    local mode
    if state.isPressed then
        mode = "pressed"
    elseif state.isHovered then
        mode = "hover"
    else
        mode = "normal"
    end

    if state.borderVisualState == mode then
        return
    end

    state.borderVisualState = mode

    if mode == "pressed" then
        local hoverColor = private.HOVER_BORDER_COLOR
        SetBorderColor(border, hoverColor[1], hoverColor[2], hoverColor[3], hoverColor[4])
        return
    end

    if mode == "hover" then
        local hoverColor = private.HOVER_BORDER_COLOR
        SetBorderColor(border, hoverColor[1], hoverColor[2], hoverColor[3], hoverColor[4])
        return
    end

    if state.OriginalR then
        SetBorderColor(border, state.OriginalR, state.OriginalG, state.OriginalB, state.OriginalA)
    end
end

function private.SetHoveredVisual(button, hovered)
    local state = private.ButtonState[button]
    if not state then
        return
    end

    state.isHovered = hovered and true or false
    local border = state.SkinOverlay and state.SkinOverlay.border
    ApplyButtonBorderVisual(state, border)
end

function private.EnsureCooldownShade(button)
    if not button then
        return nil
    end

    local state = private.GetButtonState(button)
    if state.CooldownShade then
        return state.CooldownShade
    end

    local shade = button:CreateTexture(nil, "ARTWORK", nil, 2)
    shade:SetColorTexture(0, 0, 0, private.COOLDOWN_VISUAL.shadeAlpha)
    shade:SetBlendMode("BLEND")
    shade:ClearAllPoints()
    RefineUI.Point(shade, "TOPLEFT", button, "TOPLEFT", 1, -1)
    RefineUI.Point(shade, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    shade:Hide()

    state.CooldownShade = shade
    return shade
end

function private.SetCooldownShadeVisible(button, visible)
    local shade = button and private.GetButtonState(button).CooldownShade
    if not shade then
        return
    end

    if visible then
        if not shade:IsShown() then
            shade:Show()
        end
    elseif shade:IsShown() then
        shade:Hide()
    end
end

function private.EnsureCooldownIconFade(button)
    if not button or not button.icon then
        return nil, nil
    end

    local state = private.GetButtonState(button)
    if state.CooldownIconFade and state.CooldownIconFadeAlpha then
        return state.CooldownIconFade, state.CooldownIconFadeAlpha
    end

    local animationGroup = button.icon:CreateAnimationGroup()
    animationGroup:SetLooping("NONE")
    animationGroup:SetToFinalAlpha(true)

    local fade = animationGroup:CreateAnimation("Alpha")
    fade:SetOrder(1)
    fade:SetFromAlpha(private.COOLDOWN_VISUAL.normalAlpha)
    fade:SetToAlpha(1)
    fade:SetDuration(private.COOLDOWN_VISUAL.gcdDuration)
    fade:SetSmoothing("IN_OUT")

    animationGroup:SetScript("OnFinished", function()
        local buttonState = private.ButtonState[button]
        if not buttonState or not button.icon then
            return
        end

        button.icon:SetAlpha(1)
        buttonState.lastCooldownAlpha = 1
        buttonState.cooldownFadePlaying = false
    end)

    animationGroup:SetScript("OnStop", function()
        local buttonState = private.ButtonState[button]
        if buttonState then
            buttonState.cooldownFadePlaying = false
        end
    end)

    state.CooldownIconFade = animationGroup
    state.CooldownIconFadeAlpha = fade
    return animationGroup, fade
end

function private.StartCooldownIconFade(button, duration)
    local state = private.GetButtonState(button)
    local animationGroup, fade = private.EnsureCooldownIconFade(button)
    if not animationGroup or not fade or not button.icon then
        return
    end

    local animationDuration = duration
    if type(animationDuration) ~= "number" or animationDuration <= 0 then
        animationDuration = private.COOLDOWN_VISUAL.gcdDuration
    end

    if animationDuration < 0.05 then
        animationDuration = 0.05
    end

    animationGroup:Stop()
    fade:SetFromAlpha(private.COOLDOWN_VISUAL.normalAlpha)
    fade:SetToAlpha(1)
    fade:SetDuration(animationDuration)
    button.icon:SetAlpha(private.COOLDOWN_VISUAL.normalAlpha)
    state.lastCooldownAlpha = private.COOLDOWN_VISUAL.normalAlpha
    state.cooldownFadePlaying = true
    animationGroup:Play()
end

function private.StopCooldownIconFade(button)
    local state = button and private.GetButtonState(button)
    if not state or not state.CooldownIconFade then
        return
    end

    if state.CooldownIconFade:IsPlaying() then
        state.CooldownIconFade:Stop()
    end
    state.cooldownFadePlaying = false
end

function private.SetPressedVisual(button, pressed)
    local state = private.ButtonState[button]
    if not state then
        return
    end

    if pressed then
        if not state.isPressed and state.PressAnimation then
            state.PressAnimation:Stop()
            state.PressAnimation:Play()
        end
    end

    state.isPressed = pressed and true or false
    local border = state.SkinOverlay and state.SkinOverlay.border
    ApplyButtonBorderVisual(state, border)
end

----------------------------------------------------------------------------------------
-- Cooldown Styling
----------------------------------------------------------------------------------------
local function Cooldown_OnStateChange(self)
    local button = private.GetActionBarState(self, "RefineButton")
    if button then
        private.QueueDeferredCooldownUpdate(button)
    end
end

function private.EnableDesaturation(button)
    if not button then
        return
    end

    private.SkinnedButtons[button] = true
    private.RegisterButtonCollections(button)

    if private.GetBarKeyForButton(button) ~= private.BAR_KEY.STANCE then
        private.EnsureCooldownShade(button)
        private.ForEachButtonCooldownFrame(button, function(frame)
            private.SetActionBarState(frame, "RefineButton", button)
        end)

        private.ForEachButtonCooldownFrame(button, function(frame, key)
            if not frame.HookScript then
                return
            end

            RefineUI:HookScriptOnce(private.BuildHookKey(frame, "OnShow", key), frame, "OnShow", Cooldown_OnStateChange)
            RefineUI:HookScriptOnce(private.BuildHookKey(frame, "OnHide", key), frame, "OnHide", Cooldown_OnStateChange)
            RefineUI:HookScriptOnce(private.BuildHookKey(frame, "OnCooldownDone", key), frame, "OnCooldownDone", Cooldown_OnStateChange)
        end)

        private.HandleButtonCooldownUpdate(button)
    end
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function ActionBars:StyleCooldownText(cooldown)
    if not cooldown then
        return
    end

    local regions = { cooldown:GetRegions() }
    for i = 1, #regions do
        local region = regions[i]
        if region and region:GetObjectType() == "FontString" then
            region:SetFont(Media.Fonts.Number, 24, "OUTLINE")
        end
    end
end

function ActionBars:StyleButton(button)
    if not button then
        return
    end

    local state = private.GetButtonState(button)
    if state.isSkinned then
        return
    end

    local name = button:GetName()
    if not name then
        return
    end

    local icon = _G[name .. "Icon"] or button.icon or button.Icon
    local count = _G[name .. "Count"]
    local cooldown = _G[name .. "Cooldown"] or button.cooldown
    local normal = _G[name .. "NormalTexture"] or button:GetNormalTexture()
    local flash = _G[name .. "Flash"]
    local hotkey = button.HotKey or _G[name .. "HotKey"]
    local macroName = _G[name .. "Name"]

    if normal then
        normal:SetAlpha(0)
    end
    if button.IconMask then
        button.IconMask:Hide()
    end
    if button.SlotArt then
        button.SlotArt:Hide()
    end
    if button.SlotBackground then
        button.SlotBackground:Hide()
    end
    if button.RightDivider then
        button.RightDivider:Hide()
    end
    if macroName then
        macroName:Hide()
    end
    if button.AutoCastOverlay and button.AutoCastOverlay.Corners then
        button.AutoCastOverlay.Corners:Hide()
    end

    if button.PushedTexture then
        button.PushedTexture:SetAlpha(0)
    elseif button.GetPushedTexture then
        local pushedTexture = button:GetPushedTexture()
        if pushedTexture then
            pushedTexture:SetAlpha(0)
        end
    end

    if button.HighlightTexture then
        button.HighlightTexture:SetAlpha(0)
    elseif button.GetHighlightTexture then
        local highlightTexture = button:GetHighlightTexture()
        if highlightTexture then
            highlightTexture:SetAlpha(0)
        end
    end

    if icon then
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:ClearAllPoints()
        RefineUI.Point(icon, "TOPLEFT", button, "TOPLEFT", 1, -1)
        RefineUI.Point(icon, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        icon:SetBlendMode("BLEND")
    end

    private.EnsureCooldownShade(button)
    private.EnsureCooldownIconFade(button)

    if count then
        count:SetParent(button)
        count:SetJustifyH("RIGHT")
        count:ClearAllPoints()
        RefineUI.Point(count, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
        count:SetDrawLayer("OVERLAY", 1)
        RefineUI.Font(count, 12, nil, "THINOUTLINE")
    end

    if hotkey then
        if private.IsHotkeyEnabledForButton(button) then
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

    if cooldown then
        if not state.RefineCooldownOverlay then
            local overlay = CreateFrame("Frame", nil, button)
            overlay:SetAllPoints(button)
            overlay:SetFrameStrata("DIALOG")
            overlay:SetFrameLevel((button:GetFrameLevel() or 0) + 60)
            overlay:EnableMouse(false)
            state.RefineCooldownOverlay = overlay
        end

        cooldown:SetParent(state.RefineCooldownOverlay)
        cooldown:ClearAllPoints()
        cooldown:SetAllPoints(state.RefineCooldownOverlay)
        cooldown:SetDrawEdge(false)
        cooldown:SetDrawSwipe(true)
        cooldown:SetSwipeColor(0, 0, 0, 0.8)
        if cooldown.SetSwipeTexture and Media.Textures.CooldownSwipe then
            cooldown:SetSwipeTexture(Media.Textures.CooldownSwipe)
        end

        self:StyleCooldownText(cooldown)
    end

    if flash then
        flash:SetTexture(Media.Textures.Statusbar)
        flash:SetVertexColor(0.55, 0, 0, 0.5)
    end

    if not state.SkinOverlay then
        local overlay = CreateFrame("Frame", nil, button)
        overlay:SetAllPoints(button)
        overlay:EnableMouse(false)
        state.SkinOverlay = overlay
        RefineUI.SetTemplate(overlay, "Icon")
    end

    if state.SkinOverlay.border and state.SkinOverlay.border.GetBackdropBorderColor then
        state.OriginalR, state.OriginalG, state.OriginalB, state.OriginalA = state.SkinOverlay.border:GetBackdropBorderColor()
    else
        local borderColor = Config.General.BorderColor
        state.OriginalR, state.OriginalG, state.OriginalB, state.OriginalA = borderColor[1], borderColor[2], borderColor[3], borderColor[4]
    end
    state.isHovered = false
    state.isPressed = false
    state.borderVisualState = nil

    if not state.PressAnimation then
        local animationGroup = button:CreateAnimationGroup()
        local pushIn = animationGroup:CreateAnimation("Translation")
        pushIn:SetOffset(3, -3)
        pushIn:SetDuration(0.05)
        pushIn:SetOrder(1)
        pushIn:SetSmoothing("IN")

        local pullBack = animationGroup:CreateAnimation("Translation")
        pullBack:SetOffset(-3, 3)
        pullBack:SetDuration(0.10)
        pullBack:SetOrder(2)

        local settle = animationGroup:CreateAnimation("Translation")
        settle:SetOffset(0, 0)
        settle:SetDuration(0.05)
        settle:SetOrder(3)

        animationGroup:SetLooping("NONE")
        state.PressAnimation = animationGroup
    end

    RefineUI:HookScriptOnce(private.BuildHookKey(button, "OnEnter", "Style"), button, "OnEnter", function(self)
        private.SetHoveredVisual(self, true)
    end)
    RefineUI:HookScriptOnce(private.BuildHookKey(button, "OnLeave", "Style"), button, "OnLeave", function(self)
        private.SetHoveredVisual(self, false)
    end)

    ApplyButtonBorderVisual(state, state.SkinOverlay.border)
    private.EnableDesaturation(button)
    state.isSkinned = true
end

function private.StyleButtons(buttonNames, count)
    for _, name in ipairs(buttonNames) do
        for index = 1, count do
            local button = _G[name .. index]
            if button then
                ActionBars:StyleButton(button)
            end
        end
    end
end

function ActionBars.EnableDesaturation(self, button)
    if self ~= ActionBars then
        button = self
    end
    private.EnableDesaturation(button)
end
