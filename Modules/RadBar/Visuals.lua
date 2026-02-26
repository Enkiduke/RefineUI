----------------------------------------------------------------------------------------
-- RadBar Component: Visuals
-- Description: Updater, fades/highlights, pointer tracking, and slot visibility.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local RadBar = RefineUI:GetModule("RadBar")
if not RadBar then
    return
end

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config
local Media = RefineUI.Media
local Colors = RefineUI.Colors
local Locale = RefineUI.Locale

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local pairs = pairs
local next = next
local ipairs = ipairs
local math = math
local CreateFrame = CreateFrame
local GetCursorInfo = GetCursorInfo
local GetCursorPosition = GetCursorPosition

----------------------------------------------------------------------------------------
-- Public Component Methods
----------------------------------------------------------------------------------------
function RadBar:SetupVisuals()
    -- Keep updater independent from secure core visibility.
    -- Secure OnClick hides self.Core before fade completion; parenting to UIParent
    -- ensures queued fades/highlights continue to completion.
    self.Updater = CreateFrame("Frame", nil, UIParent)
    self.Updater:Hide()
    self.cursorTracking = false
    self.updateAccumulator = 0
    self.updateInterval = 1 / 120
    self.usabilityAccumulator = 0
    self.usabilityInterval = 0.1
    self.ActiveFades = self.ActiveFades or {}
    self.HighlightAnims = self.HighlightAnims or {}
    self.bindVisualsApplied = nil
    self.Updater:SetScript("OnUpdate", function(_, elapsed)
        self:UpdateVisuals(elapsed)
    end)
end

function RadBar:EnsureUpdater()
    if self.Updater and not self.Updater:IsShown() then
        self.Updater:Show()
    end
end

function RadBar:StartUpdate()
    self.cursorTracking = true
    self:EnsureUpdater()
end

function RadBar:StopUpdate()
    self.cursorTracking = false
    self.usabilityAccumulator = 0
    self:Select(nil)
    self:UpdateUsabilityVisuals(true)
    if not next(self.ActiveFades) and not next(self.HighlightAnims) then
        self.Updater:Hide()
    end
end

function RadBar:UpdateSlotVisibility()
    local private = self.Private or {}
    local isSupportedActionType = private.IsSupportedActionType
    local getDefaultBorderColor = private.GetDefaultBorderColor
    local bindEmptySlotAtlas = private.BIND_EMPTY_SLOT_ATLAS or "cdm-empty"
    local bindEmptyIconScale = private.BIND_EMPTY_ICON_SCALE or 1.15
    local iconTexMin = private.ICON_TEX_MIN or 0.08
    local iconTexMax = private.ICON_TEX_MAX or 0.92
    local defaultEmptyIcon = private.DEFAULT_EMPTY_ICON or 134400

    local cType = GetCursorInfo()
    local customizing = self.isCustomizing or (isSupportedActionType and isSupportedActionType(cType))
    local bindMode = self.Core and self.Core:GetAttribute("bindMode")

    local defaultR, defaultG, defaultB, defaultA
    if getDefaultBorderColor then
        defaultR, defaultG, defaultB, defaultA = getDefaultBorderColor()
    else
        defaultR, defaultG, defaultB, defaultA = 0.3, 0.3, 0.3, 1
    end

    if self.CenterButton then
        local hasCenter = self.Core:GetAttribute("center-macro")
        self.CenterButton:SetShown(customizing or hasCenter)
        if bindMode and not hasCenter then
            self.CenterButton.Icon:SetAtlas(bindEmptySlotAtlas)
            self.CenterButton.Icon:SetTexCoord(0, 1, 0, 1)
            self.CenterButton.Icon:SetScale(bindEmptyIconScale)
            self.CenterButton.Icon:SetAlpha(1)
            if self.CenterButton.RefineBorder then
                self.CenterButton.RefineBorder:SetBackdropBorderColor(
                    defaultR,
                    defaultG,
                    defaultB,
                    defaultA
                )
            end
        else
            self.CenterButton.Icon:SetScale(1)
            if not hasCenter then
                self.CenterButton.Icon:SetTexture(defaultEmptyIcon)
            end
            self.CenterButton.Icon:SetTexCoord(iconTexMin, iconTexMax, iconTexMin, iconTexMax)
            if bindMode then
                self.CenterButton.Icon:SetAlpha(1)
            elseif customizing and not hasCenter then
                self.CenterButton.Icon:SetAlpha(0.4) -- More visible drop target
            end
            if self.CenterButton.RefineBorder then
                self.CenterButton.RefineBorder:SetBackdropBorderColor(defaultR, defaultG, defaultB, defaultA)
            end
        end
        if not bindMode and not hasCenter and not customizing then
            self.CenterButton.Icon:SetAlpha(0.1)
        elseif not bindMode and customizing and not hasCenter then
            self.CenterButton.Icon:SetAlpha(0.4) -- More visible drop target
        end
        self:SetIconUsabilityColor(self.CenterButton.Icon, true)
    end

    for i, btn in ipairs(self.Buttons) do
        local hasAction = self.Core:GetAttribute("child" .. i .. "-macro")
        btn:SetShown(customizing or hasAction)
        if bindMode and not hasAction then
            btn.Icon:SetAtlas(bindEmptySlotAtlas)
            btn.Icon:SetTexCoord(0, 1, 0, 1)
            btn.Icon:SetScale(bindEmptyIconScale)
            btn.Icon:SetAlpha(1)
            if btn.RefineBorder then
                btn.RefineBorder:SetBackdropBorderColor(defaultR, defaultG, defaultB, defaultA)
            end
        else
            btn.Icon:SetScale(1)
            if not hasAction then
                btn.Icon:SetTexture(defaultEmptyIcon)
            end
            btn.Icon:SetTexCoord(iconTexMin, iconTexMax, iconTexMin, iconTexMax)
            if bindMode then
                btn.Icon:SetAlpha(1)
            elseif customizing and not hasAction then
                btn.Icon:SetAlpha(0.4) -- More visible drop target
            end
            if btn.RefineBorder then
                btn.RefineBorder:SetBackdropBorderColor(defaultR, defaultG, defaultB, defaultA)
            end
        end
        if not bindMode and not hasAction and not customizing then
            btn.Icon:SetAlpha(0.1)
        elseif not bindMode and customizing and not hasAction then
            btn.Icon:SetAlpha(0.4) -- More visible drop target
        end
        self:SetIconUsabilityColor(btn.Icon, true)
    end
end

function RadBar:ClearAnimationQueues()
    if self.ActiveFades then
        for frame in pairs(self.ActiveFades) do
            self.ActiveFades[frame] = nil
        end
    end

    if self.HighlightAnims then
        for btn in pairs(self.HighlightAnims) do
            self.HighlightAnims[btn] = nil
        end
    end
end

function RadBar:ApplyBindModeVisuals()
    if not self.Core or not self.Content then
        return
    end
    self:ClearAnimationQueues()
    self.Core:Hide()
    local content = self.Content
    content:SetAlpha(1)
    content.Arrow:SetAlpha(0)
    self.sel = nil

    if self.CenterButton then
        self.CenterButton:SetScale(1)
        self.CenterButton:SetAlpha(1)
        self.CenterButton.Icon:SetAlpha(1)
        if self.CenterButton.glow then
            self.CenterButton.glow:Hide()
            if self.CenterButton.glow.PulseAnim then
                self.CenterButton.glow.PulseAnim:Stop()
            end
        end
    end

    for _, btn in ipairs(self.Buttons) do
        btn:SetScale(1)
        btn:SetAlpha(1)
        btn.Icon:SetAlpha(1)
        if btn.glow then
            btn.glow:Hide()
            if btn.glow.PulseAnim then
                btn.glow.PulseAnim:Stop()
            end
        end
    end

    self:UpdateSlotVisibility()
    self:UpdateUsabilityVisuals(true)

    if self.Updater and not self.cursorTracking then
        self.Updater:Hide()
    end
end

function RadBar:Fade(frame, target, duration, callback)
    if not frame then
        return
    end

    duration = duration or 0.2
    if duration <= 0 then
        frame:SetAlpha(target)
        if callback then
            callback(frame)
        end
        return
    end

    self.ActiveFades[frame] = {
        startAlpha = frame:GetAlpha(),
        targetAlpha = target,
        duration = duration,
        elapsed = 0,
        callback = callback,
    }
    self:EnsureUpdater()
end

function RadBar:SmoothHighlight(btn, targetScale, targetAlpha, duration)
    if not btn then
        return
    end

    duration = duration or 0.1
    if duration <= 0 then
        btn:SetScale(targetScale)
        btn:SetAlpha(targetAlpha)
        return
    end

    local current = self.HighlightAnims[btn]
    if current and current.targetScale == targetScale and current.targetAlpha == targetAlpha then
        return
    end

    self.HighlightAnims[btn] = {
        startScale = btn:GetScale(),
        startAlpha = btn:GetAlpha(),
        targetScale = targetScale,
        targetAlpha = targetAlpha,
        duration = duration,
        elapsed = 0,
    }
    self:EnsureUpdater()
end

function RadBar:ProcessFades(elapsed)
    if not next(self.ActiveFades) then
        return
    end

    for frame, state in pairs(self.ActiveFades) do
        state.elapsed = state.elapsed + elapsed
        local progress = math.min(1, state.elapsed / state.duration)
        frame:SetAlpha(state.startAlpha + (state.targetAlpha - state.startAlpha) * progress)

        if progress >= 1 then
            self.ActiveFades[frame] = nil
            local callback = state.callback
            if callback then
                callback(frame)
            end
        end
    end
end

function RadBar:ProcessHighlights(elapsed)
    if not next(self.HighlightAnims) then
        return
    end

    for btn, state in pairs(self.HighlightAnims) do
        state.elapsed = state.elapsed + elapsed
        local progress = math.min(1, state.elapsed / state.duration)
        btn:SetScale(state.startScale + (state.targetScale - state.startScale) * progress)
        btn:SetAlpha(state.startAlpha + (state.targetAlpha - state.startAlpha) * progress)

        if progress >= 1 then
            self.HighlightAnims[btn] = nil
        end
    end
end

function RadBar:UpdateVisuals(elapsed)
    elapsed = elapsed or 0

    local bindMode = self.Core:GetAttribute("bindMode")
    if bindMode then
        if not self.bindVisualsApplied then
            self:ApplyBindModeVisuals()
            self.bindVisualsApplied = true
        end
        self.usabilityAccumulator = 0
    else
        self.bindVisualsApplied = nil

        if self.cursorTracking then
            self.updateAccumulator = self.updateAccumulator + elapsed
            self.usabilityAccumulator = self.usabilityAccumulator + elapsed
            if self.updateAccumulator >= self.updateInterval then
                self.updateAccumulator = 0
                self:UpdatePointerVisuals()
            end
            if self.usabilityAccumulator >= self.usabilityInterval then
                self.usabilityAccumulator = 0
                self:UpdateUsabilityVisuals()
            end
        else
            self.updateAccumulator = 0
            self.usabilityAccumulator = 0
        end
    end

    self:ProcessFades(elapsed)
    self:ProcessHighlights(elapsed)

    if not self.cursorTracking and not next(self.ActiveFades) and not next(self.HighlightAnims) then
        self.Updater:Hide()
    end
end

function RadBar:UpdatePointerVisuals()
    local x, y = GetCursorPosition()
    local s = self.Core:GetEffectiveScale()
    if s == 0 then
        return
    end
    x, y = x / s, y / s

    local cx, cy = self.Content:GetCenter()
    if not cx then
        return
    end

    local dx, dy = x - cx, y - cy
    local r = (dx * dx + dy * dy) ^ 0.5
    local a = math.atan2(dx, dy)
    local TP = math.pi * 2
    if a < 0 then
        a = a + TP
    end

    local num = self.Core:GetAttribute("numSlices") or 0
    local inner = self.Core:GetAttribute("innerRadius")
    local idx = nil
    if r <= inner then
        idx = 0
        self.Content.Arrow:SetAlpha(0)
    elseif num > 0 then
        local sA = TP / num
        local adA = a + (sA / 2)
        if adA >= TP then
            adA = adA - TP
        end
        idx = math.floor(adA / sA) + 1

        -- Smooth Arrow Following (Only if slot has action or customizing)
        local hasAction = self.Core:GetAttribute("child" .. idx .. "-macro")
        if hasAction or self.isCustomizing then
            local arrowRadius = 50 -- Tightened orbit
            local content = self.Content
            content.Arrow:SetPoint("CENTER", content, "CENTER", math.sin(a) * arrowRadius, math.cos(a) * arrowRadius)
            content.Arrow.Tex:SetRotation(-a - (math.pi / 2))
            content.Arrow:SetAlpha(0.8)
        else
            self.Content.Arrow:SetAlpha(0)
        end
    else
        self.Content.Arrow:SetAlpha(0)
    end

    self:Select(idx)
end

function RadBar:Select(idx)
    if self.sel == idx then
        return
    end
    self.sel = idx
    local content = self.Content

    local private = self.Private or {}
    local getDefaultBorderColor = private.GetDefaultBorderColor
    local defaultR, defaultG, defaultB, defaultA
    if getDefaultBorderColor then
        defaultR, defaultG, defaultB, defaultA = getDefaultBorderColor()
    else
        defaultR, defaultG, defaultB, defaultA = 0.3, 0.3, 0.3, 1
    end

    -- Center
    if idx == 0 then
        self:SmoothHighlight(self.CenterButton, 1.1, 1, 0.1)
        if self.CenterButton.RefineBorder then
            self.CenterButton.RefineBorder:SetBackdropBorderColor(1, 0.82, 0, 1)
        end
        if self.CenterButton.glow then
            self.CenterButton.glow:Show()
            if self.CenterButton.glow.PulseAnim then
                self.CenterButton.glow.PulseAnim:Play()
            end
        end
        self:Fade(content.Arrow, 0, 0.1)
    else
        self:SmoothHighlight(self.CenterButton, 1.0, 0.6, 0.1)
        if self.CenterButton.RefineBorder then
            self.CenterButton.RefineBorder:SetBackdropBorderColor(defaultR, defaultG, defaultB, defaultA)
        end
        if self.CenterButton.glow then
            self.CenterButton.glow:Hide()
            if self.CenterButton.glow.PulseAnim then
                self.CenterButton.glow.PulseAnim:Stop()
            end
        end
    end

    -- Arrow & Slices
    for i, btn in ipairs(self.Buttons) do
        if i == idx then
            self:SmoothHighlight(btn, 1.1, 1, 0.1)
            if btn.RefineBorder then
                btn.RefineBorder:SetBackdropBorderColor(1, 0.82, 0, 1)
            end
            if btn.glow then
                btn.glow:Show()
                if btn.glow.PulseAnim then
                    btn.glow.PulseAnim:Play()
                end
            end
        else
            self:SmoothHighlight(btn, 1.0, 0.5, 0.1)
            if btn.RefineBorder then
                btn.RefineBorder:SetBackdropBorderColor(defaultR, defaultG, defaultB, defaultA)
            end
            if btn.glow then
                btn.glow:Hide()
                if btn.glow.PulseAnim then
                    btn.glow.PulseAnim:Stop()
                end
            end
        end
    end
end
