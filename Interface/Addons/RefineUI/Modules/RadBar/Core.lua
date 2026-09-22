----------------------------------------------------------------------------------------
-- RadBar Component: Core
-- Secure input and the bridge to unprotected presentation.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local RadBar = RefineUI:GetModule("RadBar")
if not RadBar then return end

local Private = RadBar.Private
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown

local SNIPPETS = {
    GET_POLAR = [[
        local mx, my = self:GetMousePosition()
        if not mx or not my then return 0, 0 end
        local sw, sh = self:GetWidth(), self:GetHeight()
        if not sw or not sh or sw <= 0 or sh <= 0 then return 0, 0 end
        local cx = self:GetAttribute("centerX") or sw / 2
        local cy = self:GetAttribute("centerY") or sh / 2
        local dx, dy = mx * sw - cx, my * sh - cy
        local angle = math.atan2(dx, dy)
        if angle < 0 then angle = angle + TWO_PI end
        return angle, (dx * dx + dy * dy)^0.5
    ]],
    GET_SELECTION = [[
        local angle, radius = self:RunAttribute("GetPolar")
        local count = self:GetAttribute("numSlices") or 0
        local inner = self:GetAttribute("innerRadius")
        if radius <= inner or count <= 0 then return 0 end
        local sliceAngle = TWO_PI / count
        return math.floor(((angle + sliceAngle / 2) % TWO_PI) / sliceAngle) + 1
    ]],
    CLEAR_ACTION = [[
        self:SetAttribute("type", nil)
        self:SetAttribute("typerelease", nil)
        self:SetAttribute("macrotext", nil)
    ]],
    ON_COMBAT = [[
        if newstate == "combat" and self:GetAttribute("customizing") then
            self:RunAttribute("ClearAction")
            self:SetAttribute("customizing", nil)
            self:SetAttribute("bindMode", nil)
            self:Hide()
            local bridge = self:GetFrameRef("Bridge")
            if bridge then bridge:CallMethod("Notify", "Hide") end
        end
    ]],
    ON_CLICK = [[
        -- Every suppressed click must clear release actions as well as press actions.
        self:RunAttribute("ClearAction")
        if self:GetAttribute("bindMode") then return false end

        local bridge = self:GetFrameRef("Bridge")
        if button == "RightButton" then
            if down and (IsControlKeyDown() or IsShiftKeyDown()) then
                local index = self:RunAttribute("GetSelection")
                if bridge then bridge:CallMethod("Notify", "Unbind", index) end
            elseif not (IsControlKeyDown() or IsShiftKeyDown()) then
                self:SetAttribute("customizing", nil)
                self:Hide()
                if bridge then bridge:CallMethod("Notify", "Hide") end
            end
            return false
        end
        if button ~= "LeftButton" then return false end

        if down then
            if not self:IsShown() then
                self:Show()
                local mx, my = self:GetMousePosition()
                local sw, sh = self:GetWidth(), self:GetHeight()
                self:SetAttribute("centerX", mx and mx * sw or sw / 2)
                self:SetAttribute("centerY", my and my * sh or sh / 2)
            end
            self:SetAttribute("customizing", nil)
            if bridge then bridge:CallMethod("Notify", "Show") end
            return false
        end

        if not self:IsShown() then return false end
        -- Sample before hiding: selection must use the visible capture frame.
        local index = self:RunAttribute("GetSelection")
        local prefix = index == 0 and "center-" or "child" .. index .. "-"
        local macro = self:GetAttribute(prefix .. "macro")
        self:SetAttribute("customizing", nil)
        self:Hide()
        if bridge then bridge:CallMethod("Notify", "Hide") end
        if macro then
            self:SetAttribute("type", "macro")
            self:SetAttribute("typerelease", "macro")
            self:SetAttribute("macrotext", macro)
            return button -- WrapScript's first return value is the forwarded button.
        end
        return false
    ]],
}

function RadBar:SetupCore()
    if self.Core then return end
    local core = CreateFrame("Button", Private.CORE_FRAME_NAME, UIParent,
        "SecureActionButtonTemplate, SecureHandlerStateTemplate")
    core:SetAllPoints(UIParent)
    core:SetFrameStrata("TOOLTIP")
    core:RegisterForClicks("AnyDown", "AnyUp")
    core:Hide()

    local content = CreateFrame("Frame", nil, UIParent)
    RefineUI.Size(content, Private.CONTENT_SIZE, Private.CONTENT_SIZE)
    content:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    content:SetFrameStrata("TOOLTIP")
    content:SetAlpha(0)
    content:EnableMouse(false)
    content:Hide()
    self.Content = content

    local arrow = CreateFrame("Frame", nil, content)
    RefineUI.Size(arrow, Private.ARROW_SIZE, Private.ARROW_SIZE)
    arrow:SetPoint("CENTER", content, "CENTER", 0, 0)
    arrow:SetAlpha(0)
    arrow.Tex = arrow:CreateTexture(nil, "OVERLAY")
    arrow.Tex:SetAllPoints()
    arrow.Tex:SetAtlas("CovenantSanctum-Renown-Arrow")
    content.Arrow = arrow

    core:SetAttribute("innerRadius", Private.INNER_RADIUS)
    core:SetAttribute("pressAndHoldAction", 1)
    core:SetAttribute("centerX", UIParent:GetWidth() / 2)
    core:SetAttribute("centerY", UIParent:GetHeight() / 2)
    core:Execute("TWO_PI = " .. string.format("%.17g", Private.TWO_PI))
    core:SetAttribute("GetPolar", SNIPPETS.GET_POLAR)
    core:SetAttribute("GetSelection", SNIPPETS.GET_SELECTION)
    core:SetAttribute("ClearAction", SNIPPETS.CLEAR_ACTION)
    core:SetAttribute("_onstate-combat", SNIPPETS.ON_COMBAT)
    core:WrapScript(core, "OnClick", SNIPPETS.ON_CLICK)

    -- Frame references in secure snippets must point to protected frames.
    local bridge = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    core:SetFrameRef("Bridge", bridge)
    bridge.Notify = function(_, msg, data)
        if msg == "Show" then
            self:SetPresentationMode("selecting")
        elseif msg == "Hide" then
            self:SetPresentationMode("closed")
        elseif msg == "Unbind" and not InCombatLockdown() then
            local index = tonumber(data)
            if self:SetSlotAction(index, nil) then
                self:Print("Unbound slot " .. (index == 0 and "Center" or index))
            end
        end
    end
    self.Core = core
    RegisterStateDriver(core, "combat", "[combat] combat; peace")
end

-- These entry points are for ordinary Lua callers. Combat input stays in snippets.
function RadBar:OpenRing()
    if InCombatLockdown() or not self.Core then return end
    local x, y = GetCursorPosition()
    local scale = self.Core:GetEffectiveScale()
    if scale <= 0 then return end
    self.Core:SetAttribute("bindMode", nil)
    self.Core:SetAttribute("customizing", nil)
    self.Core:SetAttribute("centerX", x / scale)
    self.Core:SetAttribute("centerY", y / scale)
    self.Core:Show()
    self:SetPresentationMode("selecting")
end

function RadBar:CloseRing()
    if InCombatLockdown() or not self.Core then return end
    self.Core:SetAttribute("bindMode", nil)
    self.Core:SetAttribute("customizing", nil)
    self.Core:SetAttribute("type", nil)
    self.Core:SetAttribute("typerelease", nil)
    self.Core:SetAttribute("macrotext", nil)
    self.Core:Hide()
    self:SetPresentationMode("closed")
end
