----------------------------------------------------------------------------------------
-- RadBar Component: Core
-- Description: Secure core frame and bridge callback wiring.
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
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local tonumber = tonumber

----------------------------------------------------------------------------------------
-- Secure Environment
----------------------------------------------------------------------------------------

-- Core Logic Snippets
local SNIPPETS = {
    -- Constants & Utils
    INIT = [[
        TWO_PI = 6.283185307179586
    ]],

    -- Math: Cursor to Polar Coordinates relative to Content
    GET_POLAR = [[
        local mx, my = self:GetMousePosition()
        if not mx then return 0, 0 end

        local sw, sh = self:GetWidth(), self:GetHeight()
        if not sw or not sh or sw <= 0 or sh <= 0 then
            return 0, 0
        end

        mx, my = mx * sw, my * sh

        local cx = self:GetAttribute("centerX")
        local cy = self:GetAttribute("centerY")
        if not cx or not cy then
            cx, cy = sw / 2, sh / 2
        end

        local dx, dy = mx - cx, my - cy
        local angle = math.atan2(dx, dy)
        if angle < 0 then angle = angle + 6.283185307179586 end
        local radius = (dx*dx + dy*dy)^0.5

        return angle, radius
    ]],

    -- Proxy OnClick: This runs when the keybind/button is pressed
    ON_CLICK = [[
        local bindMode = self:GetAttribute("bindMode")

        if bindMode then
            self:SetAttribute("type", nil)
            self:SetAttribute("typerelease", nil)
            self:SetAttribute("macrotext", nil)
            return false
        end

        if button == "RightButton" then
            if IsControlKeyDown() or IsShiftKeyDown() then
                local numSlices = self:GetAttribute("numSlices") or 0
                local angle, radius = self:RunAttribute("GetPolar")
                local inner = self:GetAttribute("innerRadius") or 45

                local index = 0 -- Default to center
                if radius > inner and numSlices > 0 then
                    local sliceAngle = 6.283185307179586 / numSlices
                    local adjAngle = angle + (sliceAngle / 2)
                    if adjAngle >= 6.283185307179586 then adjAngle = adjAngle - 6.283185307179586 end
                    index = math.floor(adjAngle / sliceAngle) + 1
                end

                local bridge = self:GetFrameRef("Bridge")
                if bridge then
                    bridge:CallMethod("Notify", "Unbind", index)
                end
                return false
            end

            self:Hide()
            local bridge = self:GetFrameRef("Bridge")
            if bridge then
                bridge:CallMethod("Notify", "Hide")
            end
            self:SetAttribute("type", nil)
            return false
        end

        if down then
            if not self:IsShown() then
                self:Show() -- Show immediate to validate mouse data
                local mx, my = self:GetMousePosition()

                local sw, sh = self:GetWidth(), self:GetHeight()
                if mx then
                    self:SetAttribute("centerX", mx * sw)
                    self:SetAttribute("centerY", my * sh)
                else
                    self:SetAttribute("centerX", sw * 0.5)
                    self:SetAttribute("centerY", sh * 0.5)
                end
            end

            local bridge = self:GetFrameRef("Bridge")
            if bridge then
                bridge:CallMethod("Notify", "Show")
            end
            return false
        else
            if not self:IsShown() then return false end -- Already hidden/cancelled by RightButton

            self:Hide()
            local bridge = self:GetFrameRef("Bridge")
            if bridge then
                bridge:CallMethod("Notify", "Hide")
            end

            local numSlices = self:GetAttribute("numSlices") or 0
            local angle, radius = self:RunAttribute("GetPolar")
            local inner = self:GetAttribute("innerRadius") or 45

            local prefix
            if radius > inner and numSlices > 0 then
                local sliceAngle = 6.283185307179586 / numSlices
                local adjAngle = angle + (sliceAngle / 2)
                if adjAngle >= 6.283185307179586 then adjAngle = adjAngle - 6.283185307179586 end
                local index = math.floor(adjAngle / sliceAngle) + 1
                prefix = "child" .. index .. "-"
            else
                -- DEFAULT: CENTER
                prefix = "center-"
            end

            local macro = self:GetAttribute(prefix .. "macro")
            if macro then
                self:SetAttribute("type", "macro")
                self:SetAttribute("typerelease", "macro")
                self:SetAttribute("macrotext", macro)
                return true -- Trigger the macro execution on release
            end

            self:SetAttribute("type", nil)
            return false
        end
    ]],
}

----------------------------------------------------------------------------------------
-- Public Component Methods
----------------------------------------------------------------------------------------
function RadBar:SetupCore()
    local private = self.Private or {}
    local name = private.CORE_FRAME_NAME or "RefineUI_RadBar"

    -- CORE: Fullscreen capture
    local core = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate, SecureHandlerAttributeTemplate")
    core:SetAllPoints(UIParent)
    core:SetFrameStrata("TOOLTIP") -- Topmost to avoid occlusion by nameplates/UI
    core:RegisterForClicks("AnyDown", "AnyUp")
    core:Hide()

    -- CONTENT: Detached visual container (allows lingering for fade-out)
    local content = CreateFrame("Frame", nil, UIParent)
    RefineUI.Size(content, 400, 400)
    RefineUI.Point(content, "CENTER", UIParent, "CENTER", 0, 0)
    content:SetFrameStrata("TOOLTIP") -- Above unit frames
    content:SetAlpha(0)
    content:EnableMouse(false)
    content:Hide()
    self.Content = content

    -- DIRECTIONAL ARROW: Frame-based to support OnUpdate (Fade)
    local arrow = CreateFrame("Frame", nil, content)
    RefineUI.Size(arrow, 32, 32) -- Smaller
    RefineUI.Point(arrow, "CENTER", content, "CENTER", 0, 0)
    arrow:SetAlpha(0)
    arrow.Tex = arrow:CreateTexture(nil, "OVERLAY")
    arrow.Tex:SetAllPoints()
    arrow.Tex:SetAtlas("CovenantSanctum-Renown-Arrow")
    content.Arrow = arrow

    -- SECURE ATTRS
    core:SetAttribute("innerRadius", 35) -- Tighter center
    core:SetAttribute("bindMode", nil)
    core:SetAttribute("pressAndHoldAction", 1) -- Robustness attribute
    core:SetAttribute("centerX", UIParent:GetWidth() * 0.5)
    core:SetAttribute("centerY", UIParent:GetHeight() * 0.5)
    core:Execute(SNIPPETS.INIT)
    core:SetAttribute("GetPolar", SNIPPETS.GET_POLAR)

    -- WrapScript
    core:WrapScript(core, "OnClick", SNIPPETS.ON_CLICK)

    -- Frame refs used by secure snippets must point at a protected frame.
    -- A plain Frame can become an invalid handle in combat.
    local bridge = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    core:SetFrameRef("Bridge", bridge)

    -- LUA CALLBACKS
    bridge.Notify = function(_, msg, data)
        if msg == "Show" then
            RadBar:StartUpdate()
            local centerX = core:GetAttribute("centerX")
            local centerY = core:GetAttribute("centerY")
            if centerX and centerY then
                RadBar.Content:ClearAllPoints()
                RadBar.Content:SetPoint("CENTER", UIParent, "BOTTOMLEFT", centerX, centerY)
            end
            RadBar.Content:Show()
            RadBar:Fade(RadBar.Content, 1, 0.05)
            RadBar:UpdateSlotVisibility()
            RadBar:UpdateUsabilityVisuals()
        elseif msg == "Hide" then
            RadBar:StopUpdate()
            RadBar:Fade(RadBar.Content, 0, 0.2, function(f)
                f:Hide()
            end)
        elseif msg == "Unbind" then
            if InCombatLockdown() then
                return
            end
            local idx = tonumber(data)
            if not idx then
                return
            end

            if idx == 0 then
                RadBar.db.Rings["Main"].Center = nil
            else
                RadBar.db.Rings["Main"].Slices[idx] = nil
            end

            RadBar:Print("Unbound slot " .. (idx == 0 and "Center" or idx))
            RadBar:BuildRing("Main")
            RadBar:UpdateSlotVisibility()
        end
    end

    self.Core = core
end
