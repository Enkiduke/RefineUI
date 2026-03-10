----------------------------------------------------------------------------------------
-- ActionBars Vehicle
-- Description: Vehicle exit button, override bar, and seat indicator styling.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local ActionBars = RefineUI:GetModule("ActionBars")
if not ActionBars then
    return
end

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local ipairs = ipairs

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local ACTION_BARS_VEHICLE_STATE_REGISTRY = "ActionBarsVehicle:State"
local OVERRIDE_BAR_HIDE_FRAMES = {
    "OverrideActionBarEndCapL", "OverrideActionBarEndCapR",
    "OverrideActionBarMicroBGL", "OverrideActionBarMicroBGR", "OverrideActionBarMicroBGMid",
    "OverrideActionBarExpBar", "OverrideActionBarHealthBar", "OverrideActionBarPowerBar",
    "OverrideActionBarLeaveFrameExitBG", "OverrideActionBarDivider2", "OverrideActionBarLeaveFrameDivider3",
    "OverrideActionBarButtonBGL", "OverrideActionBarButtonBGMid", "OverrideActionBarButtonBGR",
    "OverrideActionBarBG", "OverrideActionBarBorder",
}

----------------------------------------------------------------------------------------
-- Shared State
----------------------------------------------------------------------------------------
local private = ActionBars.Private
local VehicleState = RefineUI:CreateDataRegistry(ACTION_BARS_VEHICLE_STATE_REGISTRY, "k")

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
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
    for _, name in ipairs(OVERRIDE_BAR_HIDE_FRAMES) do
        local frame = _G[name]
        if frame and not frame:IsForbidden() then
            frame:SetAlpha(0)
        end
    end
end

local function SkinVehicleIndicator()
    if not VehicleSeatIndicator then
        return
    end
end

local function StyleMainMenuBarVehicleLeaveButton()
    local button = _G.MainMenuBarVehicleLeaveButton
    if not button then
        return
    end

    local state = GetVehicleState(button)
    if state.isStyled then
        return
    end

    RefineUI.StripTextures(button)

    local icon = button.Icon or button:GetNormalTexture()
    if icon then
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:ClearAllPoints()
        RefineUI.Point(icon, "TOPLEFT", button, "TOPLEFT", 1, -1)
        RefineUI.Point(icon, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    end

    RefineUI.SetTemplate(button, "Icon")
    state.isStyled = true
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function ActionBars:SetupVehicleActionBars()
    StyleDefaultVehicleExitButton()
    SkinOverrideBar()
    SkinVehicleIndicator()
    StyleMainMenuBarVehicleLeaveButton()

    local leaveButton = _G.OverrideActionBarLeaveFrameLeaveButton
    if leaveButton and leaveButton.HookScript then
        RefineUI:HookScriptOnce(private.BuildHookKey(leaveButton, "OnShow", "VehicleExit"), leaveButton, "OnShow", StyleDefaultVehicleExitButton)
    end

    local vehicleButton = _G.MainMenuBarVehicleLeaveButton
    if vehicleButton and vehicleButton.HookScript then
        RefineUI:HookScriptOnce(private.BuildHookKey(vehicleButton, "OnShow", "VehicleLeave"), vehicleButton, "OnShow", StyleMainMenuBarVehicleLeaveButton)
    end
end
