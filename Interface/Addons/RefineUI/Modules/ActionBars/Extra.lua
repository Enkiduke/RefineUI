----------------------------------------------------------------------------------------
-- ActionBars Extra
-- Description: Skinning for ExtraActionButton and ZoneAbility buttons.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local ActionBars = RefineUI:GetModule("ActionBars")
if not ActionBars then
    return
end

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Media = RefineUI.Media

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G

----------------------------------------------------------------------------------------
-- Shared State
----------------------------------------------------------------------------------------
local private = ActionBars.Private

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function StyleExtraButton(button, isZoneButton)
    if not button then
        return
    end

    local state = private.GetButtonState(button)
    if state.isSkinned then
        return
    end

    RefineUI.Size(button, 64, 64)

    local name = button.GetName and button:GetName()
    local icon = button.icon or button.Icon or (name and _G[name .. "Icon"])
    local flash = button.Flash or (name and _G[name .. "Flash"])
    local hotkey = button.HotKey or (name and _G[name .. "HotKey"])
    local count = button.Count or (name and _G[name .. "Count"])
    local cooldown = button.cooldown or button.Cooldown or (name and _G[name .. "Cooldown"])
    local normal = button.NormalTexture or (name and _G[name .. "NormalTexture"]) or (button.GetNormalTexture and button:GetNormalTexture())

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
    if button.style then
        button.style:SetAlpha(0)
    end
    if isZoneButton and ZoneAbilityFrame and ZoneAbilityFrame.Style then
        ZoneAbilityFrame.Style:SetAlpha(0)
    end

    if icon then
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:ClearAllPoints()
        RefineUI.Point(icon, "TOPLEFT", button, "TOPLEFT", 1, -1)
        RefineUI.Point(icon, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    end

    if count then
        count:ClearAllPoints()
        RefineUI.Point(count, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
        RefineUI.Font(count, 16, nil, "OUTLINE")
    end

    if hotkey then
        hotkey:ClearAllPoints()
        RefineUI.Point(hotkey, "TOPRIGHT", button, "TOPRIGHT", -2, -2)
        RefineUI.Font(hotkey, 12, nil, "OUTLINE")
        private.ApplyHotkeyVisibility(button, hotkey)
    end

    if cooldown then
        RefineUI.SetInside(cooldown, button, 2, 2)
        ActionBars:StyleCooldownText(cooldown)
    end

    if flash then
        flash:SetTexture(Media.Textures.Statusbar or "Interface\\TargetingFrame\\UI-StatusBar")
        flash:SetVertexColor(0.55, 0, 0, 0.5)
    end

    RefineUI.StyleButton(button)
    private.SetupButtonChrome(button, state)

    if button.action then
        private.EnableDesaturation(button)
    end

    state.isSkinned = true
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function ActionBars:SetupExtraActionBars()
    if ExtraActionBarFrame then
        for index = 1, ExtraActionBarFrame:GetNumChildren() do
            StyleExtraButton(_G["ExtraActionButton" .. index], false)
        end
    end

    if ZoneAbilityFrame then
        RefineUI:HookOnce("ActionBars:ZoneAbilityFrame:UpdateDisplayedZoneAbilities", ZoneAbilityFrame, "UpdateDisplayedZoneAbilities", function(frame)
            for button in frame.SpellButtonContainer:EnumerateActive() do
                StyleExtraButton(button, true)
            end
        end)
    end
end
