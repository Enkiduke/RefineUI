----------------------------------------------------------------------------------------
-- Vehicle Exit Buttons for RefineUI
----------------------------------------------------------------------------------------
-- Vehicle Action Bars
----------------------------------------------------------------------------------------

local AddOnName, RefineUI = ...
local Module = RefineUI:GetModule("ActionBars")

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Media = RefineUI.Media
local Positions = RefineUI.Positions

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues 
----------------------------------------------------------------------------------------
local _G = _G
local CreateFrame = CreateFrame
local UnitOnTaxi = UnitOnTaxi
local TaxiRequestEarlyLanding = TaxiRequestEarlyLanding
local VehicleExit = VehicleExit
local CanExitVehicle = CanExitVehicle
local InCombatLockdown = InCombatLockdown
local type = type
local tostring = tostring

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------

local function BuildVehicleHookKey(owner, method)
	local ownerId
	if type(owner) == "table" and owner.GetName then
		ownerId = owner:GetName()
	end
	if not ownerId or ownerId == "" then
		ownerId = tostring(owner)
	end
	return "ActionBarsVehicle:" .. ownerId .. ":" .. method
end

function Module:CreateVehicleExitButton(anchor, offsetX)
	local button = CreateFrame("Button", nil, UIParent)
	RefineUI.Size(button, 32, 22)
	RefineUI.Point(button, anchor, UIParent, "BOTTOM", offsetX, 24)
	RefineUI.SetTemplate(button, "Default")
	button:SetAlpha(0)
	button:RegisterForClicks("AnyUp")

	local texture = Media.Textures.ExitVehicle
	
	button:SetNormalTexture(texture)
	local normal = button:GetNormalTexture()
	if normal then
		RefineUI.SetInside(normal, button, 2, 2)
		normal:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end

	button:SetPushedTexture(texture)
	local pushed = button:GetPushedTexture()
	if pushed then
		RefineUI.SetInside(pushed, button, 2, 2)
		pushed:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		pushed:SetVertexColor(1, 0.82, 0)
	end

	button:SetHighlightTexture(texture)
	local highlight = button:GetHighlightTexture()
	if highlight then
		RefineUI.SetInside(highlight, button, 2, 2)
		highlight:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		highlight:SetAlpha(0.3)
	end

	button:SetScript("OnClick", function()
		if UnitOnTaxi("player") then
			TaxiRequestEarlyLanding()
		else
			VehicleExit()
		end
	end)

	return button
end

-- Centralized Vehicle Listener
local VehicleListener = CreateFrame("Frame")
local vehicleListenerInitialized = false

local function UpdateVehicleExitButtons()
    local show = CanExitVehicle() or UnitOnTaxi("player")

    if Module.VehicleExitButtonLeft then
        if show then
            RefineUI:FadeIn(Module.VehicleExitButtonLeft, 0.25, 1)
        else
            RefineUI:FadeOut(Module.VehicleExitButtonLeft, 0.25, 0)
        end
    end
    if Module.VehicleExitButtonRight then
        if show then
            RefineUI:FadeIn(Module.VehicleExitButtonRight, 0.25, 1)
        else
            RefineUI:FadeOut(Module.VehicleExitButtonRight, 0.25, 0)
        end
    end
end

local function EnsureVehicleListener()
    if vehicleListenerInitialized then return end

    VehicleListener:RegisterEvent("PLAYER_ENTERING_WORLD")
    VehicleListener:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
    VehicleListener:RegisterEvent("UPDATE_MULTI_CAST_ACTIONBAR")
    VehicleListener:RegisterEvent("UNIT_ENTERED_VEHICLE")
    VehicleListener:RegisterEvent("UNIT_EXITED_VEHICLE")
    VehicleListener:RegisterEvent("VEHICLE_UPDATE")
    VehicleListener:SetScript("OnEvent", UpdateVehicleExitButtons)

    vehicleListenerInitialized = true
end

local function SkinOverrideBar()
	local hideFrames = {
		"OverrideActionBarEndCapL", "OverrideActionBarEndCapR",
		"OverrideActionBarMicroBGL", "OverrideActionBarMicroBGR", "OverrideActionBarMicroBGMid",
		"OverrideActionBarExpBar", "OverrideActionBarHealthBar", "OverrideActionBarPowerBar",
		"OverrideActionBarLeaveFrameExitBG", "OverrideActionBarDivider2", "OverrideActionBarLeaveFrameDivider3",
		"OverrideActionBarButtonBGL", "OverrideActionBarButtonBGMid", "OverrideActionBarButtonBGR",
		"OverrideActionBarBG", "OverrideActionBarBorder"
	}

	for _, name in pairs(hideFrames) do
		local frame = _G[name]
		if frame and not frame:IsForbidden() then
			-- MODIFIED: Use ONLY SetAlpha(0). NEVER Hide() secure frames.
			frame:SetAlpha(0)
		end
	end

	if OverrideActionBarLeaveFrameLeaveButton then
		RefineUI.SetTemplate(OverrideActionBarLeaveFrameLeaveButton, "Transparent")
	end
end

local function SkinVehicleIndicator()
	local anchor = CreateFrame("Frame", "RefineVehicleAnchor", UIParent)
	local pos = Positions and Positions["Vehicle"] or { "BOTTOM", UIParent, "BOTTOM", 0, 320 }
	RefineUI.Point(anchor, pos[1], pos[2], pos[3], pos[4], pos[5])
	RefineUI.Size(anchor, 130, 130)

	-- Non-destructive positioning hook
	RefineUI:HookOnce(BuildVehicleHookKey(VehicleSeatIndicator, "SetPoint"), VehicleSeatIndicator, "SetPoint", function(self, _, parent)
		if parent ~= anchor and not InCombatLockdown() then
			self:ClearAllPoints()
			RefineUI.Point(self, "BOTTOM", anchor, "BOTTOM", 0, 24)
		end
	end)
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function Module:SetupVehicleActionBars()
	if not self.VehicleExitButtonLeft then
		self.VehicleExitButtonLeft = self:CreateVehicleExitButton("LEFT", -39)
	end
	
	if not self.VehicleExitButtonRight then
		self.VehicleExitButtonRight = self:CreateVehicleExitButton("RIGHT", 39)
	end

    EnsureVehicleListener()
	SkinOverrideBar()
	SkinVehicleIndicator()
    UpdateVehicleExitButtons()
end
