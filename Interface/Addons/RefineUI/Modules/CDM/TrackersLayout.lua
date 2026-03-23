----------------------------------------------------------------------------------------
-- CDM Component: TrackersLayout
-- Description: Tracker frame creation, edit-mode settings, and icon layout plumbing.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local CDM = RefineUI:GetModule("CDM")
if not CDM then
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
local _G = _G
local type = type
local tonumber = tonumber
local floor = math.floor

local CreateFrame = CreateFrame
local UIParent = UIParent
local issecretvalue = _G.issecretvalue

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local ORIENTATION_HORIZONTAL = "HORIZONTAL"
local ORIENTATION_VERTICAL = "VERTICAL"
local DIRECTION_LEFT = "LEFT"
local DIRECTION_RIGHT = "RIGHT"
local DIRECTION_UP = "UP"
local DIRECTION_DOWN = "DOWN"
local DIRECTION_CENTERED = "CENTERED"
local RADIAL_BUCKET = "Radial"
local RADIAL_TEXT_POSITION_CENTER = "CENTER"
local RADIAL_TEXT_POSITION_ABOVE = "ABOVE"
local RADIAL_TEXT_POSITION_BELOW = "BELOW"
local RADIAL_DEFAULT_SCALE = 0.7
local RADIAL_MAX_SCALE = 2.0
local DEFAULT_ICON_BASE_SIZE = 44
local RADIAL_BASE_SIZE = 512

local FRAME_LABELS = {
    Left = "Cooldown Tracker Left",
    Right = "Cooldown Tracker Right",
    Bottom = "Cooldown Tracker Bottom",
    Radial = "Cooldown Tracker Radial",
}

local function GetBucketBaseSize(bucketName)
    if bucketName == RADIAL_BUCKET then
        return RADIAL_BASE_SIZE
    end
    return DEFAULT_ICON_BASE_SIZE
end


----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function GetSafeOwnedFrameLevel(frame)
    if not frame or type(frame.GetFrameLevel) ~= "function" then
        return 0
    end

    local level = frame:GetFrameLevel()
    if IsSecret(level) or type(level) ~= "number" then
        return 0
    end

    return level
end


local function ClampIconScale(value)
    local scale = tonumber(value) or 1
    if scale < 0.5 then
        scale = 0.5
    elseif scale > 2.5 then
        scale = 2.5
    end
    return floor((scale * 100) + 0.5) / 100
end

local function ClampRadialScale(value)
    local scale = tonumber(value) or RADIAL_DEFAULT_SCALE
    if scale < 0.5 then
        scale = 0.5
    elseif scale > RADIAL_MAX_SCALE then
        scale = RADIAL_MAX_SCALE
    end
    return floor((scale * 10) + 0.5) / 10
end


local function ClampSpacing(value)
    local spacing = floor((tonumber(value) or 6) + 0.5)
    if spacing < 0 then
        spacing = 0
    elseif spacing > 20 then
        spacing = 20
    end
    return spacing
end

local function ClampRadialTextSize(value)
    local size = floor((tonumber(value) or 22) + 0.5)
    if size < 10 then
        size = 10
    elseif size > 48 then
        size = 48
    end
    return size
end


local function NormalizeOrientation(value)
    if value == ORIENTATION_VERTICAL then
        return ORIENTATION_VERTICAL
    end
    return ORIENTATION_HORIZONTAL
end

local function NormalizeRadialTextPosition(value)
    if value == RADIAL_TEXT_POSITION_ABOVE or value == RADIAL_TEXT_POSITION_BELOW then
        return value
    end
    return RADIAL_TEXT_POSITION_CENTER
end


local function NormalizeDirection(bucketName, orientation, value)
    local direction = value
    if direction == "CENTER" then
        direction = DIRECTION_CENTERED
    end

    if orientation == ORIENTATION_VERTICAL then
        if direction == DIRECTION_UP or direction == DIRECTION_DOWN or direction == DIRECTION_CENTERED then
            return direction
        end
        return DIRECTION_UP
    end

    if direction == DIRECTION_LEFT or direction == DIRECTION_RIGHT or direction == DIRECTION_CENTERED then
        return direction
    end

    return CDM.TRACKER_DEFAULT_DIRECTION[bucketName] or DIRECTION_RIGHT
end


local function ResolveRelativeFrame(relativeTo)
    if type(relativeTo) == "string" then
        return _G[relativeTo] or UIParent
    end
    return relativeTo or UIParent
end


local function ResolveAnchorPosition(frameName)
    local pos = RefineUI.Positions and RefineUI.Positions[frameName]
    if type(pos) ~= "table" then
        return "CENTER", UIParent, "CENTER", 0, 0
    end

    local point = pos[1] or "CENTER"
    local relativeTo = ResolveRelativeFrame(pos[2])
    local relativePoint = pos[3] or point
    local x = pos[4] or 0
    local y = pos[5] or 0
    return point, relativeTo, relativePoint, x, y
end


local function SaveFramePosition(frameName, point, x, y)
    RefineUI:SetPosition(frameName, { point, "UIParent", point, x, y })
end


----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function CDM:IsEditModeActive()
    if RefineUI.LibEditMode
        and type(RefineUI.LibEditMode.IsInEditMode) == "function"
        and RefineUI.LibEditMode:IsInEditMode() then
        return true
    end

    local manager = _G.EditModeManagerFrame
    if not manager then
        return false
    end

    local shown = manager:IsShown()
    if IsSecret(shown) then
        return false
    end
    return shown and true or false
end


function CDM:GetTrackerVisualSettings(bucketName)
    local cfg = self:GetConfig()
    cfg.BucketSettings = cfg.BucketSettings or {}
    cfg.BucketSettings[bucketName] = cfg.BucketSettings[bucketName] or {}

    local bucketCfg = cfg.BucketSettings[bucketName]
    local baseSize = GetBucketBaseSize(bucketName)
    local iconScale = bucketCfg.IconScale
    if type(iconScale) ~= "number" then
        local legacyIconSize = bucketCfg.IconSize
        if type(legacyIconSize) == "number" and legacyIconSize > 0 then
            iconScale = legacyIconSize / baseSize
        else
            if bucketName == RADIAL_BUCKET then
                iconScale = RADIAL_DEFAULT_SCALE
            else
                iconScale = cfg.IconScale or 1
            end
        end
    end
    if bucketName == RADIAL_BUCKET then
        iconScale = ClampRadialScale(iconScale)
    else
        iconScale = ClampIconScale(iconScale)
    end

    local spacing = ClampSpacing(bucketCfg.Spacing or cfg.Spacing)
    local orientation = NormalizeOrientation(bucketCfg.Orientation)
    local direction = NormalizeDirection(bucketName, orientation, bucketCfg.Direction)
    local showDurationText = bucketCfg.ShowDurationText ~= false
    local textSize = ClampRadialTextSize(bucketCfg.TextSize)
    local textPosition = NormalizeRadialTextPosition(bucketCfg.TextPosition)

    bucketCfg.IconScale = iconScale
    bucketCfg.Spacing = spacing
    bucketCfg.Orientation = orientation
    bucketCfg.Direction = direction
    bucketCfg.ShowDurationText = showDurationText
    bucketCfg.TextSize = textSize
    bucketCfg.TextPosition = textPosition
    return iconScale, spacing, orientation, direction, bucketCfg
end


function CDM:BuildEditModeSettings(bucketName)
    self.editModeSettingsByBucket = self.editModeSettingsByBucket or {}
    if self.editModeSettingsByBucket[bucketName] then
        return self.editModeSettingsByBucket[bucketName]
    end

    if not RefineUI.LibEditMode or not RefineUI.LibEditMode.SettingType then
        return nil
    end

    local settings = {}
    if bucketName == RADIAL_BUCKET then
        settings[#settings + 1] = {
            kind = RefineUI.LibEditMode.SettingType.Slider,
            name = "Scale",
            default = RADIAL_DEFAULT_SCALE,
            minValue = 0.5,
            maxValue = RADIAL_MAX_SCALE,
            valueStep = 0.1,
            formatter = function(value)
                return ClampRadialScale(value)
            end,
            get = function()
                local iconScale = CDM:GetTrackerVisualSettings(bucketName)
                return iconScale
            end,
            set = function(_, value)
                local _, _, _, _, bucketCfg = CDM:GetTrackerVisualSettings(bucketName)
                bucketCfg.IconScale = ClampRadialScale(value)
                CDM:RequestRefresh()
            end,
        }

        settings[#settings + 1] = {
            kind = RefineUI.LibEditMode.SettingType.Checkbox,
            name = "Show Duration Text",
            default = true,
            get = function()
                local _, _, _, _, bucketCfg = CDM:GetTrackerVisualSettings(bucketName)
                return bucketCfg.ShowDurationText ~= false
            end,
            set = function(_, value)
                local _, _, _, _, bucketCfg = CDM:GetTrackerVisualSettings(bucketName)
                bucketCfg.ShowDurationText = value == true
                CDM:RequestRefresh()
            end,
        }

        settings[#settings + 1] = {
            kind = RefineUI.LibEditMode.SettingType.Slider,
            name = "Text Size",
            default = 22,
            minValue = 10,
            maxValue = 48,
            valueStep = 1,
            get = function()
                local _, _, _, _, bucketCfg = CDM:GetTrackerVisualSettings(bucketName)
                return bucketCfg.TextSize
            end,
            set = function(_, value)
                local _, _, _, _, bucketCfg = CDM:GetTrackerVisualSettings(bucketName)
                bucketCfg.TextSize = ClampRadialTextSize(value)
                CDM:RequestRefresh()
            end,
        }

        settings[#settings + 1] = {
            kind = RefineUI.LibEditMode.SettingType.Dropdown,
            name = "Text Position",
            default = RADIAL_TEXT_POSITION_CENTER,
            values = {
                { text = "Center", value = RADIAL_TEXT_POSITION_CENTER },
                { text = "Above", value = RADIAL_TEXT_POSITION_ABOVE },
                { text = "Below", value = RADIAL_TEXT_POSITION_BELOW },
            },
            get = function()
                local _, _, _, _, bucketCfg = CDM:GetTrackerVisualSettings(bucketName)
                return bucketCfg.TextPosition
            end,
            set = function(_, value)
                local _, _, _, _, bucketCfg = CDM:GetTrackerVisualSettings(bucketName)
                bucketCfg.TextPosition = NormalizeRadialTextPosition(value)
                CDM:RequestRefresh()
            end,
        }

        self.editModeSettingsByBucket[bucketName] = settings
        return settings
    end

    settings[#settings + 1] = {
        kind = RefineUI.LibEditMode.SettingType.Dropdown,
        name = "Orientation",
        default = ORIENTATION_HORIZONTAL,
        values = {
            { text = "Horizontal", value = ORIENTATION_HORIZONTAL },
            { text = "Vertical", value = ORIENTATION_VERTICAL },
        },
        get = function()
            local _, _, orientation = CDM:GetTrackerVisualSettings(bucketName)
            return orientation
        end,
        set = function(_, value)
            local _, _, _, _, bucketCfg = CDM:GetTrackerVisualSettings(bucketName)
            bucketCfg.Orientation = NormalizeOrientation(value)
            bucketCfg.Direction = NormalizeDirection(bucketName, bucketCfg.Orientation, bucketCfg.Direction)
            CDM:RequestRefresh()
        end,
    }

    settings[#settings + 1] = {
        kind = RefineUI.LibEditMode.SettingType.Dropdown,
        name = "Icon Direction",
        default = CDM.TRACKER_DEFAULT_DIRECTION[bucketName] or DIRECTION_RIGHT,
        generator = function(_, rootDescription)
            local _, _, orientation, direction = CDM:GetTrackerVisualSettings(bucketName)
            local options
            if orientation == ORIENTATION_VERTICAL then
                options = {
                    { text = "Up", value = DIRECTION_UP },
                    { text = "Down", value = DIRECTION_DOWN },
                    { text = "Centered", value = DIRECTION_CENTERED },
                }
            else
                options = {
                    { text = "Left", value = DIRECTION_LEFT },
                    { text = "Right", value = DIRECTION_RIGHT },
                    { text = "Centered", value = DIRECTION_CENTERED },
                }
            end

            for i = 1, #options do
                local option = options[i]
                rootDescription:CreateRadio(
                    option.text,
                    function(data)
                        return direction == data.value
                    end,
                    function(data)
                        local _, _, currentOrientation, _, bucketCfg = CDM:GetTrackerVisualSettings(bucketName)
                        bucketCfg.Direction = NormalizeDirection(bucketName, currentOrientation, data.value)
                        CDM:RequestRefresh()
                    end,
                    { value = option.value }
                )
            end
        end,
        get = function()
            local _, _, _, direction = CDM:GetTrackerVisualSettings(bucketName)
            return direction
        end,
        set = function(_, value)
            local _, _, orientation, _, bucketCfg = CDM:GetTrackerVisualSettings(bucketName)
            bucketCfg.Direction = NormalizeDirection(bucketName, orientation, value)
            CDM:RequestRefresh()
        end,
    }

    settings[#settings + 1] = {
        kind = RefineUI.LibEditMode.SettingType.Slider,
        name = "Icon Scale",
        default = 1,
        minValue = 0.5,
        maxValue = 2.5,
        valueStep = 0.05,
        get = function()
            local iconScale = CDM:GetTrackerVisualSettings(bucketName)
            return iconScale
        end,
        set = function(_, value)
            local _, _, _, _, bucketCfg = CDM:GetTrackerVisualSettings(bucketName)
            bucketCfg.IconScale = ClampIconScale(value)
            CDM:RequestRefresh()
        end,
    }

    settings[#settings + 1] = {
        kind = RefineUI.LibEditMode.SettingType.Slider,
        name = "Icon Spacing",
        default = 6,
        minValue = 0,
        maxValue = 20,
        valueStep = 1,
        get = function()
            local _, spacing = CDM:GetTrackerVisualSettings(bucketName)
            return spacing
        end,
        set = function(_, value)
            local _, _, _, _, bucketCfg = CDM:GetTrackerVisualSettings(bucketName)
            bucketCfg.Spacing = ClampSpacing(value)
            CDM:RequestRefresh()
        end,
    }

    self.editModeSettingsByBucket[bucketName] = settings
    return settings
end


function CDM:RegisterTrackerFrameEditMode(frame, bucketName)
    if not frame or not RefineUI.LibEditMode or type(RefineUI.LibEditMode.AddFrame) ~= "function" then
        return
    end

    if self:StateGet(frame, "editModeRegistered", false) then
        return
    end

    local frameName = self.TRACKER_FRAME_NAMES[bucketName]
    local pos = RefineUI.Positions and RefineUI.Positions[frameName]
    local default = {
        point = (pos and pos[1]) or "CENTER",
        x = (pos and pos[4]) or 0,
        y = (pos and pos[5]) or 0,
    }

    RefineUI.LibEditMode:AddFrame(frame, function(targetFrame, _, point, x, y)
        targetFrame:ClearAllPoints()
        targetFrame:SetPoint(point, UIParent, point, x, y)
        SaveFramePosition(frameName, point, x, y)
    end, default, FRAME_LABELS[bucketName] or "Cooldown Tracker")

    local settings = self:BuildEditModeSettings(bucketName)
    if settings and type(RefineUI.LibEditMode.AddFrameSettings) == "function" then
        RefineUI.LibEditMode:AddFrameSettings(frame, settings)
    end

    self:StateSet(frame, "editModeRegistered", true)
end


function CDM:EnsureTrackerFrame(bucketName)
    self.trackerFrames = self.trackerFrames or {}
    local frame = self.trackerFrames[bucketName]
    if frame then
        return frame
    end

    local frameName = self.TRACKER_FRAME_NAMES[bucketName]
    frame = CreateFrame("Frame", frameName, UIParent)
    RefineUI.AddAPI(frame)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(25)
    frame.bucketName = bucketName
    frame.icons = {}
    frame:Hide()

    local point, relativeTo, relativePoint, x, y = ResolveAnchorPosition(frameName)
    frame:ClearAllPoints()
    frame:Point(point, relativeTo, relativePoint, x, y)
    local baseSize = GetBucketBaseSize(bucketName)
    frame:Size(baseSize, baseSize)

    self.trackerFrames[bucketName] = frame
    self:RegisterTrackerFrameEditMode(frame, bucketName)
    return frame
end


function CDM:EnsureTrackerIcon(frame, index)
    frame.icons = frame.icons or {}
    local iconFrame = frame.icons[index]
    if iconFrame then
        return iconFrame
    end

    iconFrame = CreateFrame("Frame", nil, frame)
    RefineUI.AddAPI(iconFrame)
    local parentLevel = GetSafeOwnedFrameLevel(frame)
    iconFrame:SetFrameLevel(parentLevel + 1)
    RefineUI.SetTemplate(iconFrame, "Default")
    iconFrame:Hide()

    iconFrame.Icon = iconFrame:CreateTexture(nil, "ARTWORK")
    iconFrame.Icon:SetAllPoints()
    iconFrame.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    iconFrame.Cooldown = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")

    frame.icons[index] = iconFrame
    return iconFrame
end

function CDM:EnsureRadialTrackerDisplay(frame)
    if not frame then
        return nil
    end

    local radialDisplay = frame.RadialDisplay
    if radialDisplay then
        return radialDisplay
    end

    radialDisplay = CreateFrame("Frame", nil, frame)
    RefineUI.AddAPI(radialDisplay)
    local parentLevel = GetSafeOwnedFrameLevel(frame)
    radialDisplay:SetFrameLevel(parentLevel + 1)
    radialDisplay:SetPoint("CENTER", frame, "CENTER", 0, 0)
    radialDisplay:Size(RADIAL_BASE_SIZE, RADIAL_BASE_SIZE)
    radialDisplay:Hide()

    radialDisplay.Background = radialDisplay:CreateTexture(nil, "BACKGROUND")
    radialDisplay.Background:SetAllPoints()

    radialDisplay.Cooldown = CreateFrame("Cooldown", nil, radialDisplay, "CooldownFrameTemplate")
    radialDisplay.Cooldown:SetAllPoints()

    radialDisplay.CountdownText = radialDisplay:CreateFontString(nil, "OVERLAY")
    radialDisplay.CountdownText:SetJustifyH("CENTER")
    radialDisplay.CountdownText:SetJustifyV("MIDDLE")
    radialDisplay.CountdownText:SetFont(RefineUI.Media.Fonts.Number, 22, "OUTLINE")
    radialDisplay.CountdownText:SetText("")

    frame.RadialDisplay = radialDisplay
    return radialDisplay
end
