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
local Config = RefineUI.Config
local Media = RefineUI.Media

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local CreateFrame = CreateFrame

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local ACTION_BARS_EXTRA_STATE_REGISTRY = "ActionBarsExtra:State"

----------------------------------------------------------------------------------------
-- Shared State
----------------------------------------------------------------------------------------
local private = ActionBars.Private
local ButtonState = RefineUI:CreateDataRegistry(ACTION_BARS_EXTRA_STATE_REGISTRY, "k")

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function ExtraButton_OnEnter(self)
    local state = ButtonState[self]
    local border = state and state.SkinOverlay and state.SkinOverlay.border
    local hoverColor = private.HOVER_BORDER_COLOR
    if border and border.SetBackdropBorderColor then
        border:SetBackdropBorderColor(hoverColor[1], hoverColor[2], hoverColor[3], hoverColor[4])
    end
end

local function ExtraButton_OnLeave(self)
    local state = ButtonState[self]
    local border = state and state.SkinOverlay and state.SkinOverlay.border
    if border and state and state.OriginalR then
        border:SetBackdropBorderColor(state.OriginalR, state.OriginalG, state.OriginalB, state.OriginalA)
    end
end

local function StyleExtraButton(button, isZoneButton)
    if not button then
        return
    end

    local state = ButtonState[button]
    if not state then
        state = {}
        ButtonState[button] = state
    end
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

    if not state.SkinOverlay then
        local overlay = CreateFrame("Frame", nil, button)
        overlay:SetAllPoints(button)
        overlay:EnableMouse(false)
        state.SkinOverlay = overlay
        RefineUI.SetTemplate(overlay, "Icon")
    end

    if count then
        count:ClearAllPoints()
        RefineUI.Point(count, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
        RefineUI.Font(count, 16, nil, "OUTLINE")
    end

    if hotkey then
        local showHotkey = ActionBars.db and ActionBars.db.ShowHotkeys and ActionBars.db.ShowHotkeys["ExtraAction"]
        if showHotkey then
            hotkey:ClearAllPoints()
            RefineUI.Point(hotkey, "TOPRIGHT", button, "TOPRIGHT", -2, -2)
            RefineUI.Font(hotkey, 12, nil, "OUTLINE")
        else
            hotkey:SetAlpha(0)
            if hotkey.SetShown then
                RefineUI:HookOnce(private.BuildHookKey(hotkey, "SetShown", "ExtraHotkey"), hotkey, "SetShown", function(frame, shown)
                    if shown then
                        frame:SetAlpha(0)
                    end
                end)
            end
            RefineUI:HookOnce(private.BuildHookKey(hotkey, "Show", "ExtraHotkey"), hotkey, "Show", function(frame)
                frame:SetAlpha(0)
            end)
        end
    end

    if cooldown then
        RefineUI.SetInside(cooldown, button, 2, 2)
        if ActionBars.StyleCooldownText then
            ActionBars:StyleCooldownText(cooldown)
        end
    end

    if flash then
        flash:SetTexture(Media.Textures.Statusbar or "Interface\\TargetingFrame\\UI-StatusBar")
        flash:SetVertexColor(0.55, 0, 0, 0.5)
    end

    RefineUI.StyleButton(button)

    local border = state.SkinOverlay.border
    if border and border.GetBackdropBorderColor then
        state.OriginalR, state.OriginalG, state.OriginalB, state.OriginalA = border:GetBackdropBorderColor()
    else
        state.OriginalR, state.OriginalG, state.OriginalB, state.OriginalA = 0.3, 0.3, 0.3, 1
        if Config and Config.General and Config.General.BorderColor then
            local borderColor = Config.General.BorderColor
            state.OriginalR, state.OriginalG, state.OriginalB, state.OriginalA = borderColor[1], borderColor[2], borderColor[3], borderColor[4]
        end
    end

    RefineUI:HookScriptOnce(private.BuildHookKey(button, "OnEnter", "ExtraHover"), button, "OnEnter", ExtraButton_OnEnter)
    RefineUI:HookScriptOnce(private.BuildHookKey(button, "OnLeave", "ExtraHover"), button, "OnLeave", ExtraButton_OnLeave)

    if ActionBars.EnableDesaturation and button.action then
        ActionBars.EnableDesaturation(button)
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
                if button and not (ButtonState[button] and ButtonState[button].isSkinned) then
                    StyleExtraButton(button, true)
                end
            end
        end)
    end
end
