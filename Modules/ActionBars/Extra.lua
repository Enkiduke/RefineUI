----------------------------------------------------------------------------------------
-- Extra Action Bars for RefineUI
----------------------------------------------------------------------------------------
-- Extra Action Bars for RefineUI
-- Description: Skinning for ExtraActionButton and ZoneAbility buttons.
----------------------------------------------------------------------------------------

local AddOnName, RefineUI = ...
local Module = RefineUI:GetModule("ActionBars")

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
local unpack = unpack
local type = type
local tostring = tostring

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local GOLD_R, GOLD_G, GOLD_B = 1, 0.82, 0

local ACTION_BARS_EXTRA_STATE_REGISTRY = "ActionBarsExtra:State"

----------------------------------------------------------------------------------------
-- External State (Secure-safe)
----------------------------------------------------------------------------------------
local ButtonState = RefineUI:CreateDataRegistry(ACTION_BARS_EXTRA_STATE_REGISTRY, "k")

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------

local function BuildExtraHookKey(owner, method, suffix)
    local ownerId
    if type(owner) == "table" and owner.GetName then
        ownerId = owner:GetName()
    end
    if not ownerId or ownerId == "" then
        ownerId = tostring(owner)
    end
    if suffix and suffix ~= "" then
        return "ActionBarsExtra:" .. ownerId .. ":" .. method .. ":" .. suffix
    end
    return "ActionBarsExtra:" .. ownerId .. ":" .. method
end

local function ExtraButton_OnEnter(self)
    local s = ButtonState[self]
    if s and s.SkinOverlay and s.SkinOverlay.border and s.SkinOverlay.border.SetBackdropBorderColor then
        s.SkinOverlay.border:SetBackdropBorderColor(GOLD_R, GOLD_G, GOLD_B, 1)
    end
end

local function ExtraButton_OnLeave(self)
    local s = ButtonState[self]
    if s and s.SkinOverlay and s.SkinOverlay.border and s.OriginalBorder then
        s.SkinOverlay.border:SetBackdropBorderColor(unpack(s.OriginalBorder))
    end
end

local function StyleExtraButton(button, isZone)
	if not button then return end
    if not ButtonState[button] then ButtonState[button] = {} end
    local state = ButtonState[button]
    if state.isSkinned then return end

	-- Use sizes from reference
	local width, height = 64, 64
	RefineUI.Size(button, width, height)

	-- NON-DESTRUCTIVE HIDING
	local name = button.GetName and button:GetName()
	local icon = button.icon or button.Icon or (name and _G[name.."Icon"])
	local flash = button.Flash or (name and _G[name.."Flash"])
	local hotkey = button.HotKey or (name and _G[name.."HotKey"])
	local count = button.Count or (name and _G[name.."Count"])
    local cooldown = button.cooldown or button.Cooldown or (name and _G[name.."Cooldown"])
    local normal = button.NormalTexture or (name and _G[name.."NormalTexture"]) or (button.GetNormalTexture and button:GetNormalTexture())

    -- Hide Blizzard assets that interfere with our look
    if normal then normal:SetAlpha(0) end
    if button.IconMask then button.IconMask:Hide() end
    if button.SlotArt then button.SlotArt:Hide() end
    if button.SlotBackground then button.SlotBackground:Hide() end
    
    -- ExtraActionBarFrame specific style (the "gloss" texture)
	if button.style then
		button.style:SetAlpha(0)
	end
	
	-- ZoneAbilityFrame specific style
	if isZone and ZoneAbilityFrame and ZoneAbilityFrame.Style then
		ZoneAbilityFrame.Style:SetAlpha(0)
	end

    -- Icon
	if icon then
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:ClearAllPoints()
		RefineUI.Point(icon, "TOPLEFT", button, "TOPLEFT", 1, -1)
        RefineUI.Point(icon, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
	end

	-- Apply RefineUI Template (Via Overlay to avoid Taint and destructive stripping)
    if not state.SkinOverlay then
        local overlay = CreateFrame("Frame", nil, button)
        overlay:SetAllPoints(button)
        overlay:EnableMouse(false) 
        state.SkinOverlay = overlay
        
        RefineUI.SetTemplate(overlay, "Icon")
    end

	-- Count
	if count then
		count:ClearAllPoints()
		RefineUI.Point(count, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
		RefineUI.Font(count, 16, nil, "OUTLINE")
	end

	-- HotKey
	if hotkey then
		if Module.db and Module.db.HotKey then
			hotkey:ClearAllPoints()
			RefineUI.Point(hotkey, "TOPRIGHT", button, "TOPRIGHT", -2, -2)
			RefineUI.Font(hotkey, 12, nil, "OUTLINE")
        else
			hotkey:SetText("")
			hotkey:Hide()
            if hotkey.SetShown then
                RefineUI:HookOnce(BuildExtraHookKey(hotkey, "SetShown"), hotkey, "SetShown", function(self, shown)
                    if shown then self:Hide() end
                end)
            end
			RefineUI:HookOnce(BuildExtraHookKey(hotkey, "Show"), hotkey, "Show", function(self) self:Hide() end)
		end
	end

	-- Cooldown
	if cooldown then
        -- Reparent cooldown if needed to match ActionBars.lua strata logic (Optional but good for consistency)
        -- For now, just styling it is enough to fix the icon.
		RefineUI.SetInside(cooldown, button, 2, 2)
		if Module.StyleCooldownText then
			Module:StyleCooldownText(cooldown)
		end
	end

    -- Style flash
    if flash then
        flash:SetTexture(Media.Textures.Statusbar or "Interface\\TargetingFrame\\UI-StatusBar")
        flash:SetVertexColor(0.55, 0, 0, 0.5)
    end

	-- Hover / Pushed / Checked (matching ActionBars.lua logic where possible)
	RefineUI.StyleButton(button)

	-- Store original border color for restoration
    local border = state.SkinOverlay.border
	if border and border.GetBackdropBorderColor then
		local r, g, b, a = border:GetBackdropBorderColor()
		state.OriginalBorder = { r, g, b, a }
	else
		state.OriginalBorder = { 0.3, 0.3, 0.3, 1 }
		if Config and Config.General and Config.General.BorderColor then
			state.OriginalBorder = { unpack(Config.General.BorderColor) }
		end
	end

    RefineUI:HookScriptOnce(
        BuildExtraHookKey(button, "OnEnter", "Hover"),
        button,
        "OnEnter",
        ExtraButton_OnEnter
    )
    RefineUI:HookScriptOnce(
        BuildExtraHookKey(button, "OnLeave", "Hover"),
        button,
        "OnLeave",
        ExtraButton_OnLeave
    )

    -- Integration with ActionBars cooldown desaturation if available
    if Module.EnableDesaturation then
        -- Check if it's an action button (has .action)
        -- ExtraActionButtons typically have .action, ZoneAbilities might not in the same way
        if button.action then
            Module.EnableDesaturation(button)
        end
    end

	state.isSkinned = true
end

----------------------------------------------------------------------------------------
-- Setup
----------------------------------------------------------------------------------------
function Module:SetupExtraActionBars()
	-- 1. Extra Action Button (Do this first so it skins even if container logic fails)
	if ExtraActionBarFrame then
		for i = 1, ExtraActionBarFrame:GetNumChildren() do
			local button = _G["ExtraActionButton"..i]
			if button then
				StyleExtraButton(button)
			end
		end
	end

	-- 2. Zone Abilities
	if ZoneAbilityFrame then
		RefineUI:HookOnce("ActionBarsExtra:ZoneAbilityFrame:UpdateDisplayedZoneAbilities", ZoneAbilityFrame, "UpdateDisplayedZoneAbilities", function(frame)
			for button in frame.SpellButtonContainer:EnumerateActive() do
				if button and not (ButtonState[button] and ButtonState[button].isSkinned) then
					StyleExtraButton(button, true)
				end
			end
		end)
	end


end
