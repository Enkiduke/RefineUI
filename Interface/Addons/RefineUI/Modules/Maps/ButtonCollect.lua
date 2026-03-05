----------------------------------------------------------------------------------------
-- ButtonCollect for RefineUI
-- Description: Gathers addon minimap buttons into a consolidated frame.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Maps = RefineUI:GetModule("Maps")

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local _G = _G
local pairs, ipairs, unpack, select = pairs, ipairs, unpack, select
local math = math
local table = table
local tostring = tostring
local type = type
local tonumber = tonumber
local floor = math.floor
local ceil = math.ceil
local max = math.max
local min = math.min

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local Minimap = _G.Minimap
local UIParent = _G.UIParent

----------------------------------------------------------------------------------------
-- Locals
----------------------------------------------------------------------------------------

local BlackList = {
	["QueueStatusButton"] = true,
	["MiniMapTracking"] = true,
	["MiniMapMailFrame"] = true,
	["HelpOpenTicketButton"] = true,
	["GameTimeFrame"] = true,
    ["TimeManagerClockButton"] = true,
    ["AddonCompartmentFrame"] = true,
    ["ExpansionLandingPageMinimapButton"] = true,
    ["RefineUI_MinimapPortalsButton"] = true,
}

local texList = {
	["136430"] = true,
	["136467"] = true,
}

local buttons = {}
local buttonIndex = {}
local hoverHooked = {}
local buttonState = {}
local collectFrame
local requestRefreshButtonCollect

local ORIENTATION_HORIZONTAL = "HORIZONTAL"
local ORIENTATION_VERTICAL = "VERTICAL"
local DIRECTION_FORWARD = "FORWARD"
local DIRECTION_REVERSE = "REVERSE"
local DEFAULT_BUTTON_SIZE = 32
local DEFAULT_BUTTON_SPACING = 3
local GOLD_R, GOLD_G, GOLD_B, GOLD_A = 1, 0.82, 0, 1

local function GetButtonBorder(button)
    if not button then
        return nil
    end

    local border = button.RefineBorder or button.border
    if border and border.SetBackdropBorderColor then
        return border
    end
    return nil
end

local function GetDefaultBorderColor()
    local color = RefineUI.Config and RefineUI.Config.General and RefineUI.Config.General.BorderColor
    if color then
        return color[1] or 0.3, color[2] or 0.3, color[3] or 0.3, color[4] or 1
    end
    return 0.3, 0.3, 0.3, 1
end

local function ApplyGoldHoverBorder(button)
    local border = GetButtonBorder(button)
    local state = buttonState[button]
    if not border or not state then
        return
    end

    if border.GetBackdropBorderColor then
        state.hoverRestoreR, state.hoverRestoreG, state.hoverRestoreB, state.hoverRestoreA = border:GetBackdropBorderColor()
    else
        state.hoverRestoreR, state.hoverRestoreG, state.hoverRestoreB, state.hoverRestoreA = GetDefaultBorderColor()
    end

    border:SetBackdropBorderColor(GOLD_R, GOLD_G, GOLD_B, GOLD_A)
end

local function RestoreHoverBorder(button)
    local border = GetButtonBorder(button)
    if not border then
        return
    end

    local state = buttonState[button]
    local r, g, b, a
    if state and state.hoverRestoreR ~= nil then
        r, g, b, a = state.hoverRestoreR, state.hoverRestoreG, state.hoverRestoreB, state.hoverRestoreA
    else
        r, g, b, a = GetDefaultBorderColor()
    end
    border:SetBackdropBorderColor(r, g, b, a or 1)
end

local function SkinButton(f, size)
	f:SetPushedTexture(0)
	f:SetHighlightTexture(0)
	f:SetDisabledTexture(0)
	f:SetSize(size, size)

	for i = 1, f:GetNumRegions() do
		local region = select(i, f:GetRegions())
		if region:IsVisible() and region:GetObjectType() == "Texture" then
			local tex = tostring(region:GetTexture())

			if tex and (texList[tex] or tex:find("Border") or tex:find("Background") or tex:find("AlphaMask")) then
				region:SetTexture(nil)
			else
				region:ClearAllPoints()
				region:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
				region:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
				region:SetTexCoord(0.1, 0.9, 0.1, 0.9)
				region:SetDrawLayer("ARTWORK")
				if f:GetName() == "PS_MinimapButton" then
					f.SetPoint = RefineUI.Dummy
				end
			end
		end
	end

	RefineUI.SetTemplate(f, "Default")
end

----------------------------------------------------------------------------------------
-- Functions
----------------------------------------------------------------------------------------

local function NormalizeOrientation(value)
    if value == ORIENTATION_VERTICAL then
        return ORIENTATION_VERTICAL
    end
    return ORIENTATION_HORIZONTAL
end

local function NormalizeGrowDirection(value)
    if value == DIRECTION_REVERSE then
        return DIRECTION_REVERSE
    end
    return DIRECTION_FORWARD
end

function Maps:GetButtonCollectConfig()
    local config = RefineUI.Config.Maps or {}
    local db = self.db or config

    local size = floor((tonumber(db.AddonButtonSize) or tonumber(config.AddonButtonSize) or DEFAULT_BUTTON_SIZE) + 0.5)
    if size < 16 then size = 16 end
    if size > 64 then size = 64 end

    local spacing = floor((tonumber(db.AddonButtonSpacing) or tonumber(config.AddonButtonSpacing) or DEFAULT_BUTTON_SPACING) + 0.5)
    if spacing < 0 then spacing = 0 end
    if spacing > 30 then spacing = 30 end

    local minimapSize = tonumber(db.Size) or tonumber(config.Size) or (Minimap and Minimap:GetWidth()) or 162
    if minimapSize <= 0 then
        minimapSize = 162
    end

    local orientation = NormalizeOrientation(db.AddonButtonOrientation or config.AddonButtonOrientation or ORIENTATION_HORIZONTAL)
    local growDirection = NormalizeGrowDirection(db.AddonButtonGrowDirection or config.AddonButtonGrowDirection or DIRECTION_FORWARD)

    return {
        size = size,
        spacing = spacing,
        minimapSize = minimapSize,
        orientation = orientation,
        growDirection = growDirection,
    }
end

function Maps:GetButtonCollectGrowDirectionLabel(value)
    local orientation = self:GetButtonCollectConfig().orientation
    local direction = NormalizeGrowDirection(value)

    if orientation == ORIENTATION_VERTICAL then
        return (direction == DIRECTION_REVERSE) and "Bottom to Top" or "Top to Bottom"
    end
    return (direction == DIRECTION_REVERSE) and "Right to Left" or "Left to Right"
end

function Maps:RequestButtonCollectRefresh()
    if requestRefreshButtonCollect then
        requestRefreshButtonCollect()
    end
end

function Maps:RegisterButtonCollectEditModeSettings()
    if not collectFrame or not RefineUI.LibEditMode or not RefineUI.LibEditMode.SettingType then
        return
    end

    if not self._buttonCollectEditModeSettingsRegistered then
        local settings = {}
        local settingType = RefineUI.LibEditMode.SettingType

        settings[#settings + 1] = {
            kind = settingType.Slider,
            name = "Button Size",
            default = DEFAULT_BUTTON_SIZE,
            minValue = 16,
            maxValue = 64,
            valueStep = 1,
            get = function()
                return self:GetButtonCollectConfig().size
            end,
            set = function(_, value)
                self.db = self.db or (RefineUI.DB and RefineUI.DB.Maps) or RefineUI.Config.Maps or {}
                self.db.AddonButtonSize = floor((tonumber(value) or DEFAULT_BUTTON_SIZE) + 0.5)
                self:RequestButtonCollectRefresh()
            end,
        }

        settings[#settings + 1] = {
            kind = settingType.Slider,
            name = "Button Spacing",
            default = DEFAULT_BUTTON_SPACING,
            minValue = 0,
            maxValue = 30,
            valueStep = 1,
            get = function()
                return self:GetButtonCollectConfig().spacing
            end,
            set = function(_, value)
                self.db = self.db or (RefineUI.DB and RefineUI.DB.Maps) or RefineUI.Config.Maps or {}
                self.db.AddonButtonSpacing = floor((tonumber(value) or DEFAULT_BUTTON_SPACING) + 0.5)
                self:RequestButtonCollectRefresh()
            end,
        }

        settings[#settings + 1] = {
            kind = settingType.Dropdown,
            name = "Orientation",
            default = ORIENTATION_HORIZONTAL,
            values = {
                { text = "Horizontal", value = ORIENTATION_HORIZONTAL },
                { text = "Vertical", value = ORIENTATION_VERTICAL },
            },
            get = function()
                return self:GetButtonCollectConfig().orientation
            end,
            set = function(_, value)
                self.db = self.db or (RefineUI.DB and RefineUI.DB.Maps) or RefineUI.Config.Maps or {}
                self.db.AddonButtonOrientation = NormalizeOrientation(value)
                self:RequestButtonCollectRefresh()
            end,
        }

        settings[#settings + 1] = {
            kind = settingType.Dropdown,
            name = "Grow Direction",
            default = DIRECTION_FORWARD,
            generator = function(_, rootDescription)
                local options = { DIRECTION_FORWARD, DIRECTION_REVERSE }
                for i = 1, #options do
                    local direction = options[i]
                    rootDescription:CreateRadio(
                        self:GetButtonCollectGrowDirectionLabel(direction),
                        function(data)
                            return self:GetButtonCollectConfig().growDirection == data.value
                        end,
                        function(data)
                            self.db = self.db or (RefineUI.DB and RefineUI.DB.Maps) or RefineUI.Config.Maps or {}
                            self.db.AddonButtonGrowDirection = NormalizeGrowDirection(data.value)
                            self:RequestButtonCollectRefresh()
                        end,
                        { value = direction }
                    )
                end
            end,
            get = function()
                return self:GetButtonCollectConfig().growDirection
            end,
            set = function(_, value)
                self.db = self.db or (RefineUI.DB and RefineUI.DB.Maps) or RefineUI.Config.Maps or {}
                self.db.AddonButtonGrowDirection = NormalizeGrowDirection(value)
                self:RequestButtonCollectRefresh()
            end,
        }

        self._buttonCollectEditModeSettings = settings
        self._buttonCollectEditModeSettingsRegistered = true
    end

    if not self._buttonCollectEditModeSettingsAttached
        and self._buttonCollectEditModeSettings
        and type(RefineUI.LibEditMode.AddFrameSettings) == "function" then
        RefineUI.LibEditMode:AddFrameSettings(collectFrame, self._buttonCollectEditModeSettings)
        self._buttonCollectEditModeSettingsAttached = true
    end
end

function Maps:SetupButtonCollect()
    if not self.db or self.db.ButtonCollect ~= true then return end

    collectFrame = CreateFrame("Frame", "RefineUI_MinimapButtonCollect", UIParent)
    collectFrame:SetSize(1, 1)
    
    local pos = self.positions.RefineUI_MinimapButtonCollect or { "TOPRIGHT", "Minimap", "TOPRIGHT", 0, 0 }
    local point, relativeTo, relativePoint, x, y = unpack(pos)
    if type(relativeTo) == "string" then
        relativeTo = _G[relativeTo] or UIParent
    end
    collectFrame:SetPoint(point, relativeTo, relativePoint, x, y)
    
    if RefineUI.LibEditMode then
        local default = { point = point, x = x, y = y }
        RefineUI.LibEditMode:AddFrame(collectFrame, function(frame, _, newPoint, newX, newY)
            if not self.positions then
                self.positions = RefineUI.DB and RefineUI.DB.Positions or RefineUI.Positions
            end
            self.positions.RefineUI_MinimapButtonCollect = { newPoint, "UIParent", newPoint, newX, newY }
            frame:ClearAllPoints()
            frame:SetPoint(newPoint, UIParent, newPoint, newX, newY)
        end, default, "Minimap Buttons")
    end

    local function TryCollectFrom(parent)
        if not parent then return end
        for _, child in ipairs({ parent:GetChildren() }) do
            local name = child:GetName()
            if name and not BlackList[name] then
                if child:GetObjectType() == "Button" and child:GetNumRegions() >= 3 and child:IsShown() then
                    if not buttonIndex[child] then
                        buttonIndex[child] = true
                        child:SetParent(collectFrame)
                        table.insert(buttons, child)
                    end
                end
            end
        end
    end

    local function LayoutButtons()
        local cfg = self:GetButtonCollectConfig()
        local size = cfg.size
        local spacing = cfg.spacing
        local orientation = cfg.orientation
        local growDirection = cfg.growDirection
        local lineLen = max(1, floor((cfg.minimapSize + spacing) / (size + spacing)))

        if #buttons == 0 then
            collectFrame:Hide()
            return
        end

        local count = #buttons
        local columns, rows
        if orientation == ORIENTATION_VERTICAL then
            rows = min(lineLen, count)
            columns = ceil(count / lineLen)
        else
            columns = min(lineLen, count)
            rows = ceil(count / lineLen)
        end

        local frameWidth = (columns * size) + ((columns - 1) * spacing)
        local frameHeight = (rows * size) + ((rows - 1) * spacing)
        collectFrame:SetSize(max(frameWidth, size), max(frameHeight, size))
        collectFrame:Show()

        for i = 1, #buttons do
            local f = buttons[i]
            local state = buttonState[f]
            if not state then
                state = {
                    clearAllPoints = f.ClearAllPoints,
                    setPoint = f.SetPoint,
                    locked = false,
                }
                buttonState[f] = state
            end

            state.clearAllPoints(f)
            local wrapped = ((i - 1) % lineLen == 0)

            if orientation == ORIENTATION_VERTICAL then
                if i == 1 then
                    if growDirection == DIRECTION_REVERSE then
                        state.setPoint(f, "BOTTOMLEFT", collectFrame, "BOTTOMLEFT", 0, 0)
                    else
                        state.setPoint(f, "TOPLEFT", collectFrame, "TOPLEFT", 0, 0)
                    end
                elseif wrapped then
                    local prevColumnButton = buttons[i - lineLen]
                    if growDirection == DIRECTION_REVERSE then
                        state.setPoint(f, "BOTTOMLEFT", prevColumnButton, "BOTTOMRIGHT", spacing, 0)
                    else
                        state.setPoint(f, "TOPLEFT", prevColumnButton, "TOPRIGHT", spacing, 0)
                    end
                else
                    if growDirection == DIRECTION_REVERSE then
                        state.setPoint(f, "BOTTOM", buttons[i - 1], "TOP", 0, spacing)
                    else
                        state.setPoint(f, "TOP", buttons[i - 1], "BOTTOM", 0, -spacing)
                    end
                end
            else
                if i == 1 then
                    if growDirection == DIRECTION_REVERSE then
                        state.setPoint(f, "TOPRIGHT", collectFrame, "TOPRIGHT", 0, 0)
                    else
                        state.setPoint(f, "TOPLEFT", collectFrame, "TOPLEFT", 0, 0)
                    end
                elseif wrapped then
                    local prevRowButton = buttons[i - lineLen]
                    if growDirection == DIRECTION_REVERSE then
                        state.setPoint(f, "TOPRIGHT", prevRowButton, "BOTTOMRIGHT", 0, -spacing)
                    else
                        state.setPoint(f, "TOPLEFT", prevRowButton, "BOTTOMLEFT", 0, -spacing)
                    end
                else
                    if growDirection == DIRECTION_REVERSE then
                        state.setPoint(f, "RIGHT", buttons[i - 1], "LEFT", -spacing, 0)
                    else
                        state.setPoint(f, "LEFT", buttons[i - 1], "RIGHT", spacing, 0)
                    end
                end
            end

            if not state.locked then
                f.ClearAllPoints = RefineUI.Dummy
                f.SetPoint = RefineUI.Dummy
                state.locked = true
            end

            f:SetAlpha(0)

            if not hoverHooked[f] then
                hoverHooked[f] = true
                f:HookScript("OnEnter", function(selfButton)
                    RefineUI:FadeIn(selfButton)
                    ApplyGoldHoverBorder(selfButton)
                end)
                f:HookScript("OnLeave", function(selfButton)
                    RefineUI:FadeOut(selfButton)
                    RestoreHoverBorder(selfButton)
                end)
            end

            SkinButton(f, size)
        end
    end

    local function RefreshButtons()
        TryCollectFrom(Minimap)
        TryCollectFrom(_G.MinimapCluster)
        TryCollectFrom(_G.MinimapBackdrop)
        LayoutButtons()
    end

    local function RequestRefresh()
        RefineUI:Debounce("Maps:ButtonCollect:Refresh", 0.15, RefreshButtons)
    end
    requestRefreshButtonCollect = RequestRefresh

    RefineUI:RegisterEventCallback("PLAYER_ENTERING_WORLD", RequestRefresh, "Maps:ButtonCollect:PEW")
    RefineUI:RegisterEventCallback("ADDON_LOADED", RequestRefresh, "Maps:ButtonCollect:ADDON_LOADED")
    self:RegisterButtonCollectEditModeSettings()
    RequestRefresh()
end
