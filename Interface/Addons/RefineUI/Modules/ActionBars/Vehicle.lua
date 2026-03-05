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
local Positions = RefineUI.Positions

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local ACTION_BARS_VEHICLE_STATE_REGISTRY = "ActionBarsVehicle:State"

----------------------------------------------------------------------------------------
-- External State (Secure-safe)
----------------------------------------------------------------------------------------
local VehicleState = RefineUI:CreateDataRegistry(ACTION_BARS_VEHICLE_STATE_REGISTRY, "k")

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues 
----------------------------------------------------------------------------------------
local _G = _G
local CreateFrame = CreateFrame
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

local function GetVehicleState(owner)
    local state = VehicleState[owner]
    if not state then
        state = {}
        VehicleState[owner] = state
    end
    return state
end

local function StyleDefaultVehicleExitButton()
    local leaveFrame = _G.OverrideActionBarLeaveFrame
    if leaveFrame and (not leaveFrame.IsForbidden or not leaveFrame:IsForbidden()) then
        leaveFrame:SetAlpha(1)
    end

    local leaveButton = _G.OverrideActionBarLeaveFrameLeaveButton
    if not leaveButton or (leaveButton.IsForbidden and leaveButton:IsForbidden()) then
        return
    end

    leaveButton:SetAlpha(1)
    local state = GetVehicleState(leaveButton)
    if not state.isStyled then
        RefineUI.SetTemplate(leaveButton, "Default")
        state.isStyled = true
    end
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
local function StyleMainMenuBarVehicleLeaveButton()
    local btn = _G.MainMenuBarVehicleLeaveButton
    if not btn then return end

    local state = GetVehicleState(btn)
    if state.isStyled then return end

    RefineUI.StripTextures(btn)

    local icon = btn.Icon or btn:GetNormalTexture()
    if icon then
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:ClearAllPoints()
        RefineUI.Point(icon, "TOPLEFT", btn, "TOPLEFT", 1, -1)
        RefineUI.Point(icon, "BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    end

    RefineUI.SetTemplate(btn, "Icon")
    state.isStyled = true
end

function Module:SetupVehicleActionBars()
	StyleDefaultVehicleExitButton()
	SkinOverrideBar()
	SkinVehicleIndicator()
	StyleMainMenuBarVehicleLeaveButton()

    local leaveButton = _G.OverrideActionBarLeaveFrameLeaveButton
    if leaveButton and type(leaveButton.HookScript) == "function" then
        RefineUI:HookScriptOnce(
            BuildVehicleHookKey(leaveButton, "OnShow"),
            leaveButton,
            "OnShow",
            StyleDefaultVehicleExitButton
        )
    end

    local vehicleBtn = _G.MainMenuBarVehicleLeaveButton
    if vehicleBtn and type(vehicleBtn.HookScript) == "function" then
        RefineUI:HookScriptOnce(
            BuildVehicleHookKey(vehicleBtn, "OnShow"),
            vehicleBtn,
            "OnShow",
            StyleMainMenuBarVehicleLeaveButton
        )
    end
end
