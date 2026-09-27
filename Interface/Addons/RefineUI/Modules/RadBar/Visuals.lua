----------------------------------------------------------------------------------------
-- RadBar Component: Visuals
-- Presentation modes, shared slot rendering, and an idle-aware animation updater.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local RadBar = RefineUI:GetModule("RadBar")
if not RadBar then return end

local Private = RadBar.Private
local math = math

function RadBar:SetupVisuals()
    if self.Updater then return end
    -- Independent of the secure frame so closing animations can finish.
    self.Updater = CreateFrame("Frame", nil, UIParent)
    self.Updater:Hide()
    self.mode = "closed"
    self.isCustomizing = false
    self.cursorTracking = false
    self.usabilityAccumulator = 0
    self.usabilityInterval = 0.1
    self.ActiveFades = {}
    self.HighlightAnims = {}
    self.Updater:SetScript("OnUpdate", function(_, elapsed)
        self:UpdateVisuals(elapsed)
    end)
end

function RadBar:EnsureUpdater()
    if not self.Updater:IsShown() then self.Updater:Show() end
end

-- Presentation only: safe to call from a secure bridge during combat.
-- All protected frame mutations belong to Core/Customization, never fades.
-- The updater hides itself once tracking and animations have no work left.
function RadBar:SetPresentationMode(mode)
    self.mode = mode
    self.isCustomizing = mode == "customizing"
    self.cursorTracking = false
    self.sel = nil
    self:ClearAnimationQueues()
    self.Content.Arrow:SetAlpha(0)

    if mode ~= "closed" then
        -- Cached for pointer tracking; the secure snippet sets these before notifying.
        self.centerX = self.Core:GetAttribute("centerX")
        self.centerY = self.Core:GetAttribute("centerY")
        self.Content:ClearAllPoints()
        self.Content:SetPoint("CENTER", UIParent, "BOTTOMLEFT", self.centerX, self.centerY)
        self.Content:Show()
    end
    self:UpdateSlotVisibility()
    self:UpdateUsabilityVisuals()

    if mode == "closed" then
        self:Fade(self.Content, 0, 0.1, function(frame)
            if self.mode == "closed" then frame:Hide() end
        end)
    elseif self.isCustomizing and self.Core:GetAttribute("bindMode") then
        self.Content:SetAlpha(1)
    else
        self.cursorTracking = true
        self.usabilityAccumulator = 0
        self.cursorX = nil
        self:UpdatePointerVisuals()
        self:Fade(self.Content, 1, mode == "selecting" and 0.05 or 0.1)
    end
end

function RadBar:UpdateSlotAppearance(btn)
    local bindMode = self.isCustomizing and self.Core:GetAttribute("bindMode")
    btn:SetShown(self.isCustomizing or btn.HasAction)
    btn:EnableMouse(self.isCustomizing)
    if bindMode and not btn.HasAction then
        btn.Icon:SetAtlas(Private.BIND_EMPTY_SLOT_ATLAS)
        btn.Icon:SetTexCoord(0, 1, 0, 1)
        btn.Icon:SetScale(Private.BIND_EMPTY_ICON_SCALE)
        btn.Icon:SetAlpha(1)
    else
        -- Always restore texture after an empty-slot atlas, including newly filled slots.
        btn.Icon:SetTexture(btn.ActionIcon)
        btn.Icon:SetTexCoord(Private.ICON_TEX_MIN, Private.ICON_TEX_MAX,
            Private.ICON_TEX_MIN, Private.ICON_TEX_MAX)
        btn.Icon:SetScale(1)
        btn.Icon:SetAlpha(btn.HasAction and 1 or (self.isCustomizing and 0.4 or 0.1))
    end
end

function RadBar:UpdateSlotVisibility()
    for index = 0, Private.SLOT_COUNT do
        local btn = index == 0 and self.CenterButton or self.Buttons[index]
        if btn then self:UpdateSlotAppearance(btn) end
    end
    self:Select(self.sel, true)
end

function RadBar:ClearAnimationQueues()
    for frame in pairs(self.ActiveFades) do self.ActiveFades[frame] = nil end
    for btn in pairs(self.HighlightAnims) do self.HighlightAnims[btn] = nil end
end

function RadBar:Fade(frame, target, duration, callback)
    if not frame then return end
    -- Replacement also cancels the previous callback for immediate transitions.
    self.ActiveFades[frame] = nil
    duration = duration or 0.2
    if duration <= 0 then
        frame:SetAlpha(target)
        if callback then callback(frame) end
        return
    end
    self.ActiveFades[frame] = {
        startAlpha = frame:GetAlpha(), targetAlpha = target,
        duration = duration, elapsed = 0, callback = callback,
    }
    self:EnsureUpdater()
end

function RadBar:SmoothHighlight(btn, targetScale, targetAlpha, duration)
    duration = duration or 0.1
    if duration <= 0 then
        self.HighlightAnims[btn] = nil
        btn:SetScale(targetScale)
        btn:SetAlpha(targetAlpha)
        return
    end
    local current = self.HighlightAnims[btn]
    if current and current.targetScale == targetScale and current.targetAlpha == targetAlpha then return end
    if not current and btn:GetScale() == targetScale and btn:GetAlpha() == targetAlpha then return end
    self.HighlightAnims[btn] = {
        startScale = btn:GetScale(), startAlpha = btn:GetAlpha(),
        targetScale = targetScale, targetAlpha = targetAlpha,
        duration = duration, elapsed = 0,
    }
    self:EnsureUpdater()
end

function RadBar:ProcessFades(elapsed)
    for frame, state in pairs(self.ActiveFades) do
        state.elapsed = state.elapsed + elapsed
        local progress = math.min(1, state.elapsed / state.duration)
        frame:SetAlpha(state.startAlpha + (state.targetAlpha - state.startAlpha) * progress)
        if progress >= 1 then
            self.ActiveFades[frame] = nil
            if state.callback then state.callback(frame) end
        end
    end
end

function RadBar:ProcessHighlights(elapsed)
    for btn, state in pairs(self.HighlightAnims) do
        state.elapsed = state.elapsed + elapsed
        local progress = math.min(1, state.elapsed / state.duration)
        btn:SetScale(state.startScale + (state.targetScale - state.startScale) * progress)
        btn:SetAlpha(state.startAlpha + (state.targetAlpha - state.startAlpha) * progress)
        if progress >= 1 then self.HighlightAnims[btn] = nil end
    end
end

function RadBar:UpdateVisuals(elapsed)
    if self.cursorTracking then
        self:UpdatePointerVisuals()
        self.usabilityAccumulator = self.usabilityAccumulator + elapsed
        if self.usabilityAccumulator >= self.usabilityInterval then
            self.usabilityAccumulator = self.usabilityAccumulator % self.usabilityInterval
            self:UpdateUsabilityVisuals()
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
    if x == self.cursorX and y == self.cursorY then return end
    self.cursorX, self.cursorY = x, y
    local core = self.Core
    local scale = core:GetEffectiveScale()
    -- Mirror the restricted GetMousePosition normalization, including its bounds
    -- check and arithmetic order, so exact sector edges agree at every UI scale.
    local left, bottom, width, height = core:GetRect()
    local angle, radius = 0, 0
    if width and height and width > 0 and height > 0 then
        x, y = x / scale - left, y / scale - bottom
        if x >= 0 and x <= width and y >= 0 and y <= height then
            local dx = x / width * core:GetWidth() - self.centerX
            local dy = y / height * core:GetHeight() - self.centerY
            radius = (dx * dx + dy * dy)^0.5
            angle = math.atan2(dx, dy)
            if angle < 0 then angle = angle + Private.TWO_PI end
        end
    end
    local index = Private.GetSelection(angle, radius, Private.INNER_RADIUS, Private.SLOT_COUNT)
    local btn = index == 0 and self.CenterButton or self.Buttons[index]
    local arrow = self.Content.Arrow
    if index > 0 and btn and (btn.HasAction or self.isCustomizing) then
        arrow:SetPoint("CENTER", self.Content, "CENTER",
            math.sin(angle) * Private.ARROW_RADIUS, math.cos(angle) * Private.ARROW_RADIUS)
        arrow.Tex:SetRotation(-angle - math.pi / 2)
        arrow:SetAlpha(0.8)
    else
        arrow:SetAlpha(0)
    end
    self:Select(index)
end

function RadBar:SetSlotHighlight(btn, selected, immediate)
    local neutral = self.mode == "closed" or (self.isCustomizing and self.Core:GetAttribute("bindMode"))
    selected = not neutral and selected and (btn.HasAction or self.isCustomizing)
    local alpha = (neutral or selected) and 1 or (btn.SlotIndex == 0 and 0.6 or 0.5)
    self:SmoothHighlight(btn, selected and 1.1 or 1, alpha, immediate and 0 or 0.1)
    if btn.RefineBorder then
        if selected then
            btn.RefineBorder:SetBackdropBorderColor(1, 0.82, 0, 1)
        else
            btn.RefineBorder:SetBackdropBorderColor(Private.GetDefaultBorderColor())
        end
    end
    if btn.glow then
        btn.glow:SetShown(selected and true or false)
        if btn.glow.PulseAnim then
            if selected then btn.glow.PulseAnim:Play() else btn.glow.PulseAnim:Stop() end
        end
    end
end

-- Forced reapplication follows a mode or slot change and snaps immediately.
function RadBar:Select(index, force)
    if self.sel == index and not force then return end
    self.sel = index
    for slot = 0, Private.SLOT_COUNT do
        local btn = slot == 0 and self.CenterButton or self.Buttons[slot]
        if btn then self:SetSlotHighlight(btn, slot == index, force) end
    end
end
