----------------------------------------------------------------------------------------
-- Tooltip Edit Mode
-- Description: Edit Mode anchor frame and settings for tooltip anchoring.
----------------------------------------------------------------------------------------

local _, RefineUI = ...

----------------------------------------------------------------------------------------
-- Module
----------------------------------------------------------------------------------------
local Tooltip = RefineUI:GetModule("Tooltip")
if not Tooltip then
    return
end

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local UIParent = UIParent
local type = type
local floor = math.floor
local abs = math.abs
local tonumber = tonumber

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local MOVER_FRAME_NAME = Tooltip.TOOLTIP_ANCHOR_MOVER_FRAME_NAME or "RefineUI_TooltipAnchorMover"
local TOOLTIP_ANCHOR_MODE = Tooltip.TOOLTIP_ANCHOR_MODE or {
    MOUSE = "MOUSE",
    MOVER = "MOVER",
}
local TOOLTIP_ANCHOR_PLACEMENT = Tooltip.TOOLTIP_ANCHOR_PLACEMENT or {
    TOPLEFT = "TOPLEFT",
    TOPRIGHT = "TOPRIGHT",
    BOTTOMLEFT = "BOTTOMLEFT",
    BOTTOMRIGHT = "BOTTOMRIGHT",
}
local EDIT_MODE_LABEL = "Tooltip Anchor"
local SETTING_NAME_ANCHOR_MODE = "Anchor Mode"
local SETTING_NAME_PLACEMENT = "Placement"
local SETTING_NAME_X_OFFSET = "X Offset"
local SETTING_NAME_Y_OFFSET = "Y Offset"
local SETTING_NAME_CLAMP_TO_SCREEN = "Clamp To Screen"
local MOVER_DEFAULT_POINT = "BOTTOMRIGHT"
local MOVER_DEFAULT_RELATIVE_TO = "Minimap"
local MOVER_DEFAULT_RELATIVE_POINT = "TOPRIGHT"
local MOVER_DEFAULT_X = 0
local MOVER_DEFAULT_Y = 6
local MOVER_LEGACY_POINT = "BOTTOMRIGHT"
local MOVER_LEGACY_RELATIVE_TO = "UIParent"
local MOVER_LEGACY_RELATIVE_POINT = "BOTTOMRIGHT"
local MOVER_LEGACY_X = -340
local MOVER_LEGACY_Y = 220

----------------------------------------------------------------------------------------
-- Locals
----------------------------------------------------------------------------------------
local editModeSettingsRegistered = false
local editModeCallbacksRegistered = false
local editModeSettingsAttached = false

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local function EnsureAnchorConfig()
    Config.Tooltip = Config.Tooltip or {}
    if type(Config.Tooltip.Anchor) ~= "table" then
        Config.Tooltip.Anchor = {}
    end
    return Config.Tooltip.Anchor
end

local function ResolveRelativeFrame(relativeTo)
    if type(relativeTo) == "string" then
        return _G[relativeTo]
    end

    return relativeTo
end

local function GetTooltipMoverDefaultAnchor()
    local relativeTo = ResolveRelativeFrame(MOVER_DEFAULT_RELATIVE_TO)
    if not relativeTo then
        return MOVER_LEGACY_POINT, UIParent, MOVER_LEGACY_RELATIVE_POINT, MOVER_LEGACY_X, MOVER_LEGACY_Y
    end

    return MOVER_DEFAULT_POINT, relativeTo, MOVER_DEFAULT_RELATIVE_POINT, MOVER_DEFAULT_X, MOVER_DEFAULT_Y
end

local function NormalizeFrameToParent(frame)
    local parent = frame and frame:GetParent()
    if not parent then
        return nil
    end

    local scale = frame:GetScale()
    if not scale then
        return nil
    end

    local left = frame:GetLeft()
    local top = frame:GetTop()
    local right = frame:GetRight()
    local bottom = frame:GetBottom()
    if not left or not top or not right or not bottom then
        return nil
    end

    left = left * scale
    top = top * scale
    right = right * scale
    bottom = bottom * scale

    local parentWidth, parentHeight = parent:GetSize()
    if not parentWidth or not parentHeight then
        return nil
    end

    local x, y, point
    if left < (parentWidth - right) and left < abs((left + right) / 2 - parentWidth / 2) then
        x = left
        point = "LEFT"
    elseif (parentWidth - right) < abs((left + right) / 2 - parentWidth / 2) then
        x = right - parentWidth
        point = "RIGHT"
    else
        x = (left + right) / 2 - parentWidth / 2
        point = ""
    end

    if bottom < (parentHeight - top) and bottom < abs((bottom + top) / 2 - parentHeight / 2) then
        y = bottom
        point = "BOTTOM" .. point
    elseif (parentHeight - top) < abs((bottom + top) / 2 - parentHeight / 2) then
        y = top - parentHeight
        point = "TOP" .. point
    else
        y = (bottom + top) / 2 - parentHeight / 2
    end

    if point == "" then
        point = "CENTER"
    end

    return point, x / scale, y / scale
end

local function ApplyMoverPoint(frame, point, relativeTo, relativePoint, x, y)
    local anchor = ResolveRelativeFrame(relativeTo) or UIParent
    frame:ClearAllPoints()
    frame:SetPoint(
        point or MOVER_DEFAULT_POINT,
        anchor,
        relativePoint or point or MOVER_DEFAULT_RELATIVE_POINT,
        tonumber(x) or MOVER_DEFAULT_X,
        tonumber(y) or MOVER_DEFAULT_Y
    )
end

local function ResolveMoverDefault(frame)
    if frame then
        local currentPoint, currentRelativeTo, currentRelativePoint, currentX, currentY = frame:GetPoint(1)
        local point, relativeTo, relativePoint, x, y = GetTooltipMoverDefaultAnchor()

        ApplyMoverPoint(frame, point, relativeTo, relativePoint, x, y)

        local normalizedPoint, normalizedX, normalizedY = NormalizeFrameToParent(frame)

        frame:ClearAllPoints()
        if currentPoint then
            frame:SetPoint(currentPoint, currentRelativeTo or UIParent, currentRelativePoint or currentPoint, currentX or 0, currentY or 0)
        else
            ApplyMoverPoint(frame, point, relativeTo, relativePoint, x, y)
        end

        if normalizedPoint then
            return {
                point = normalizedPoint,
                x = normalizedX,
                y = normalizedY,
            }
        end
    end

    return {
        point = MOVER_LEGACY_POINT,
        x = MOVER_LEGACY_X,
        y = MOVER_LEGACY_Y,
    }
end

local function RoundOffset(value, fallback)
    local numericValue = tonumber(value)
    if type(numericValue) ~= "number" then
        return fallback
    end

    if numericValue >= 0 then
        return floor(numericValue + 0.5)
    end

    return -floor((-numericValue) + 0.5)
end

local function SaveMoverPosition(point, x, y)
    RefineUI:SetPosition(MOVER_FRAME_NAME, {
        point,
        "UIParent",
        point,
        x,
        y,
    })
end

local function IsLegacyDefaultPosition(position)
    return type(position) == "table"
        and position[1] == MOVER_LEGACY_POINT
        and position[2] == MOVER_LEGACY_RELATIVE_TO
        and position[3] == MOVER_LEGACY_RELATIVE_POINT
        and tonumber(position[4]) == MOVER_LEGACY_X
        and tonumber(position[5]) == MOVER_LEGACY_Y
end

local function EnsureStoredMoverPosition()
    if not RefineUI.Positions[MOVER_FRAME_NAME] or IsLegacyDefaultPosition(RefineUI.Positions[MOVER_FRAME_NAME]) then
        RefineUI:SetPosition(MOVER_FRAME_NAME, {
            MOVER_DEFAULT_POINT,
            MOVER_DEFAULT_RELATIVE_TO,
            MOVER_DEFAULT_RELATIVE_POINT,
            MOVER_DEFAULT_X,
            MOVER_DEFAULT_Y,
        })
    end
end

local function IsEditModeActive()
    local lib = RefineUI.LibEditMode
    return lib
        and type(lib.IsInEditMode) == "function"
        and lib:IsInEditMode()
end

local function IsMoverModeActive()
    return Tooltip:GetTooltipAnchorConfig().Mode == TOOLTIP_ANCHOR_MODE.MOVER
end

----------------------------------------------------------------------------------------
-- Anchor Frame
----------------------------------------------------------------------------------------
function Tooltip:RefreshTooltipAnchorMover()
    local mover = self.tooltipAnchorMover
    if not mover then
        return
    end

    local anchorConfig = self:GetTooltipAnchorConfig()
    local moverEnabled = anchorConfig.Mode == TOOLTIP_ANCHOR_MODE.MOVER

    if mover.background then
        if moverEnabled then
            mover.background:SetColorTexture(1, 0.82, 0, 0.2)
        else
            mover.background:SetColorTexture(1, 1, 1, 0.12)
        end
    end

    if mover.borders then
        local r, g, b, a
        if moverEnabled then
            r, g, b, a = 1, 0.82, 0, 0.75
        else
            r, g, b, a = 1, 1, 1, 0.3
        end

        for _, border in ipairs(mover.borders) do
            border:SetColorTexture(r, g, b, a)
        end
    end
end

function Tooltip:UpdateTooltipAnchorEditModeSettingAvailability()
    local lib = RefineUI.LibEditMode
    local mover = self.tooltipAnchorMover
    local settings = self.tooltipAnchorEditModeSettings
    if not lib or not mover or type(settings) ~= "table" then
        return
    end

    local moverModeActive = IsMoverModeActive()
    local disabled = not moverModeActive

    for index = 1, #settings do
        local setting = settings[index]
        local name = setting and setting.name
        if name == SETTING_NAME_PLACEMENT
            or name == SETTING_NAME_X_OFFSET
            or name == SETTING_NAME_Y_OFFSET
            or name == SETTING_NAME_CLAMP_TO_SCREEN
        then
            setting.disabled = disabled
        end
    end

    if type(lib.RefreshFrameSettings) == "function" then
        lib:RefreshFrameSettings(mover)
    end
end

function Tooltip:EnsureTooltipAnchorMover()
    if self.tooltipAnchorMover then
        return self.tooltipAnchorMover
    end

    EnsureStoredMoverPosition()

    local mover = CreateFrame("Frame", MOVER_FRAME_NAME, UIParent)
    mover:SetSize(140, 28)
    mover:SetFrameStrata("DIALOG")
    mover:SetFrameLevel(120)
    mover:SetClampedToScreen(true)
    mover:EnableMouse(false)
    mover.editModeName = EDIT_MODE_LABEL
    mover:Hide()

    local background = mover:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    mover.background = background

    mover.borders = {}

    local topBorder = mover:CreateTexture(nil, "BORDER")
    topBorder:SetPoint("TOPLEFT")
    topBorder:SetPoint("TOPRIGHT")
    topBorder:SetHeight(1)
    mover.borders[#mover.borders + 1] = topBorder

    local bottomBorder = mover:CreateTexture(nil, "BORDER")
    bottomBorder:SetPoint("BOTTOMLEFT")
    bottomBorder:SetPoint("BOTTOMRIGHT")
    bottomBorder:SetHeight(1)
    mover.borders[#mover.borders + 1] = bottomBorder

    local leftBorder = mover:CreateTexture(nil, "BORDER")
    leftBorder:SetPoint("TOPLEFT")
    leftBorder:SetPoint("BOTTOMLEFT")
    leftBorder:SetWidth(1)
    mover.borders[#mover.borders + 1] = leftBorder

    local rightBorder = mover:CreateTexture(nil, "BORDER")
    rightBorder:SetPoint("TOPRIGHT")
    rightBorder:SetPoint("BOTTOMRIGHT")
    rightBorder:SetWidth(1)
    mover.borders[#mover.borders + 1] = rightBorder

    local point, relativeTo, relativePoint, x, y = unpack(RefineUI.Positions[MOVER_FRAME_NAME] or {})
    ApplyMoverPoint(mover, point, relativeTo, relativePoint, x, y)

    self.tooltipAnchorMover = mover
    self:RefreshTooltipAnchorMover()
    return mover
end

----------------------------------------------------------------------------------------
-- Edit Mode Settings
----------------------------------------------------------------------------------------
function Tooltip:RegisterTooltipAnchorEditModeSettings()
    if editModeSettingsRegistered or not RefineUI.LibEditMode or not RefineUI.LibEditMode.SettingType then
        return
    end

    local settingType = RefineUI.LibEditMode.SettingType
    local anchorModeValues = {
        { text = "Mouse", value = TOOLTIP_ANCHOR_MODE.MOUSE },
        { text = "Mover", value = TOOLTIP_ANCHOR_MODE.MOVER },
    }
    local placementValues = {
        { text = "Top Left", value = TOOLTIP_ANCHOR_PLACEMENT.TOPLEFT },
        { text = "Top Right", value = TOOLTIP_ANCHOR_PLACEMENT.TOPRIGHT },
        { text = "Bottom Left", value = TOOLTIP_ANCHOR_PLACEMENT.BOTTOMLEFT },
        { text = "Bottom Right", value = TOOLTIP_ANCHOR_PLACEMENT.BOTTOMRIGHT },
    }

    local settings = {
        {
            kind = settingType.Dropdown,
            name = SETTING_NAME_ANCHOR_MODE,
            default = TOOLTIP_ANCHOR_MODE.MOUSE,
            values = anchorModeValues,
            get = function()
                return Tooltip:GetTooltipAnchorConfig().Mode
            end,
            set = function(_, value)
                local anchorConfig = EnsureAnchorConfig()
                if value ~= TOOLTIP_ANCHOR_MODE.MOVER then
                    value = TOOLTIP_ANCHOR_MODE.MOUSE
                end
                anchorConfig.Mode = value
                Tooltip:RefreshTooltipAnchorMover()
                Tooltip:UpdateTooltipAnchorEditModeSettingAvailability()
            end,
        },
        {
            kind = settingType.Dropdown,
            name = SETTING_NAME_PLACEMENT,
            default = TOOLTIP_ANCHOR_PLACEMENT.TOPRIGHT,
            values = placementValues,
            get = function()
                return Tooltip:GetTooltipAnchorConfig().Placement
            end,
            set = function(_, value)
                local anchorConfig = EnsureAnchorConfig()
                anchorConfig.Placement = value
                Tooltip:RefreshTooltipAnchorMover()
            end,
        },
        {
            kind = settingType.Slider,
            name = SETTING_NAME_X_OFFSET,
            default = 0,
            minValue = -80,
            maxValue = 80,
            valueStep = 1,
            get = function()
                return Tooltip:GetTooltipAnchorConfig().OffsetX
            end,
            set = function(_, value)
                local anchorConfig = EnsureAnchorConfig()
                anchorConfig.OffsetX = RoundOffset(value, 0)
                Tooltip:RefreshTooltipAnchorMover()
            end,
        },
        {
            kind = settingType.Slider,
            name = SETTING_NAME_Y_OFFSET,
            default = 4,
            minValue = -80,
            maxValue = 80,
            valueStep = 1,
            get = function()
                return Tooltip:GetTooltipAnchorConfig().OffsetY
            end,
            set = function(_, value)
                local anchorConfig = EnsureAnchorConfig()
                anchorConfig.OffsetY = RoundOffset(value, 4)
                Tooltip:RefreshTooltipAnchorMover()
            end,
        },
        {
            kind = settingType.Checkbox,
            name = SETTING_NAME_CLAMP_TO_SCREEN,
            default = true,
            get = function()
                return Tooltip:GetTooltipAnchorConfig().ClampToScreen
            end,
            set = function(_, value)
                local anchorConfig = EnsureAnchorConfig()
                anchorConfig.ClampToScreen = value and true or false
                Tooltip:RefreshTooltipAnchorMover()
            end,
        },
    }

    self.tooltipAnchorEditModeSettings = settings
    editModeSettingsRegistered = true
end

----------------------------------------------------------------------------------------
-- Edit Mode Registration
----------------------------------------------------------------------------------------
function Tooltip:RegisterTooltipAnchorEditModeFrame()
    local lib = RefineUI.LibEditMode
    if not lib or type(lib.AddFrame) ~= "function" then
        return
    end

    local mover = self:EnsureTooltipAnchorMover()

    if not self.tooltipAnchorMoverRegistered then
        local default = ResolveMoverDefault(mover)
        lib:AddFrame(mover, function(_, _, point, x, y)
            mover:ClearAllPoints()
            mover:SetPoint(point, UIParent, point, x, y)
            SaveMoverPosition(point, x, y)
            Tooltip:RefreshTooltipAnchorMover()
        end, default, EDIT_MODE_LABEL)
        self.tooltipAnchorMoverRegistered = true
    end

    if self.tooltipAnchorEditModeSettings and not editModeSettingsAttached and type(lib.AddFrameSettings) == "function" then
        lib:AddFrameSettings(mover, self.tooltipAnchorEditModeSettings)
        editModeSettingsAttached = true
        self:UpdateTooltipAnchorEditModeSettingAvailability()
    end
end

function Tooltip:RegisterTooltipAnchorEditModeCallbacks()
    local lib = RefineUI.LibEditMode
    if editModeCallbacksRegistered or not lib or type(lib.RegisterCallback) ~= "function" then
        return
    end

    lib:RegisterCallback("enter", function()
        local mover = Tooltip:EnsureTooltipAnchorMover()
        Tooltip:RefreshTooltipAnchorMover()
        Tooltip:UpdateTooltipAnchorEditModeSettingAvailability()
        mover:Show()
    end)

    lib:RegisterCallback("exit", function()
        if Tooltip.tooltipAnchorMover then
            Tooltip.tooltipAnchorMover:Hide()
        end
    end)

    editModeCallbacksRegistered = true
end

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------
function Tooltip:InitializeTooltipEditMode()
    if not RefineUI.LibEditMode then
        return
    end

    self:RegisterTooltipAnchorEditModeSettings()
    self:RegisterTooltipAnchorEditModeFrame()
    self:RegisterTooltipAnchorEditModeCallbacks()
    self:UpdateTooltipAnchorEditModeSettingAvailability()

    if IsEditModeActive() and self.tooltipAnchorMover then
        self:RefreshTooltipAnchorMover()
        self:UpdateTooltipAnchorEditModeSettingAvailability()
        self.tooltipAnchorMover:Show()
    end
end
