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
local pcall = pcall
local wipe = _G.wipe or table.wipe

local CreateFrame = CreateFrame
local UIParent = UIParent
local CooldownFrame_Clear = CooldownFrame_Clear
local CooldownFrame_Set = CooldownFrame_Set
local C_Spell = C_Spell
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
local DEFAULT_ICON_BASE_SIZE = 44
local TRACKER_SWIPE_OVERLAY_INSET = 2
local TRACKER_SWIPE_FRAMELEVEL_OFFSET = 20
local TRACKER_SWIPE_COLOR_R = 0
local TRACKER_SWIPE_COLOR_G = 0
local TRACKER_SWIPE_COLOR_B = 0
local TRACKER_SWIPE_COLOR_A = 0.8
local TRACKER_COOLDOWN_TEXT_SIZE = 22


local function ApplyTrackerCooldownTextStyle(cooldown)
    if not cooldown or type(cooldown.GetRegions) ~= "function" then
        return
    end

    local regions = { cooldown:GetRegions() }
    for i = 1, #regions do
        local region = regions[i]
        if region and type(region.GetObjectType) == "function" and region:GetObjectType() == "FontString" then
            region:SetFont(RefineUI.Media.Fonts.Number, TRACKER_COOLDOWN_TEXT_SIZE, "OUTLINE")
        end
    end
end


local function GetRefineCooldownSwipeTexture()
    local media = RefineUI.Media
    local textures = media and media.Textures
    if type(textures) ~= "table" then
        return nil
    end
    if type(textures.CooldownSwipe) == "string" and textures.CooldownSwipe ~= "" then
        return textures.CooldownSwipe
    end
    if type(textures.CooldownSwipeSmall) == "string" and textures.CooldownSwipeSmall ~= "" then
        return textures.CooldownSwipeSmall
    end
    return nil
end


local function GetSafeFrameLevelForTracker(frame)
    if not frame or type(frame.GetFrameLevel) ~= "function" then
        return nil
    end

    local ok, level = pcall(frame.GetFrameLevel, frame)
    if not ok or (issecretvalue and issecretvalue(level)) or type(level) ~= "number" then
        return nil
    end

    return level
end


local function GetSafeFrameStrataForTracker(frame)
    if not frame or type(frame.GetFrameStrata) ~= "function" then
        return nil
    end

    local ok, strata = pcall(frame.GetFrameStrata, frame)
    if not ok or (issecretvalue and issecretvalue(strata)) or type(strata) ~= "string" or strata == "" then
        return nil
    end

    return strata
end


local function ApplyTrackerCooldownSkin(iconFrame)
    if not iconFrame or not iconFrame.Cooldown then
        return
    end

    local cooldown = iconFrame.Cooldown
    local swipeTexture = GetRefineCooldownSwipeTexture()
    local frameLevel = GetSafeFrameLevelForTracker(iconFrame) or 1
    local frameStrata = GetSafeFrameStrataForTracker(iconFrame) or ""
    local skinToken = tostring(swipeTexture or "") .. ":" .. frameStrata .. ":" .. tostring(frameLevel + TRACKER_SWIPE_FRAMELEVEL_OFFSET)
    if CDM.StateGet and CDM:StateGet(iconFrame, "trackerCooldownSkinToken") == skinToken then
        return
    end

    cooldown:ClearAllPoints()
    cooldown:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", -TRACKER_SWIPE_OVERLAY_INSET, TRACKER_SWIPE_OVERLAY_INSET)
    cooldown:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", TRACKER_SWIPE_OVERLAY_INSET, -TRACKER_SWIPE_OVERLAY_INSET)
    if cooldown.SetFrameStrata then
        local strata = GetSafeFrameStrataForTracker(iconFrame)
        if strata then
            cooldown:SetFrameStrata(strata)
        end
    end
    if cooldown.SetFrameLevel then
        cooldown:SetFrameLevel(frameLevel + TRACKER_SWIPE_FRAMELEVEL_OFFSET)
    end
    cooldown:SetDrawEdge(false)
    if cooldown.SetDrawBling then
        pcall(cooldown.SetDrawBling, cooldown, true)
    end
    cooldown:SetDrawSwipe(true)
    if cooldown.SetSwipeColor then
        pcall(cooldown.SetSwipeColor, cooldown, TRACKER_SWIPE_COLOR_R, TRACKER_SWIPE_COLOR_G, TRACKER_SWIPE_COLOR_B, TRACKER_SWIPE_COLOR_A)
    end

    ApplyTrackerCooldownTextStyle(cooldown)

    if swipeTexture and cooldown.SetSwipeTexture then
        pcall(cooldown.SetSwipeTexture, cooldown, swipeTexture)
    end

    if CDM.StateSet then
        CDM:StateSet(iconFrame, "trackerCooldownSkinToken", skinToken)
    end
end

local FRAME_LABELS = {
    Left = "Cooldown Tracker Left",
    Right = "Cooldown Tracker Right",
    Bottom = "Cooldown Tracker Bottom",
}


----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end


local function HasValue(value)
    if IsSecret(value) then
        return true
    end
    return value ~= nil
end


local function ResolveCooldownModRate(value)
    if IsSecret(value) then
        return value
    end
    if type(value) == "number" then
        return value
    end
    return 1
end


local function BuildRenderPrimitive(value, defaultToken)
    if IsSecret(value) then
        return nil, false
    end
    if value == nil then
        return defaultToken, true
    end
    local valueType = type(value)
    if valueType == "number" or valueType == "string" or valueType == "boolean" then
        return tostring(value), true
    end
    return nil, false
end


local function BuildEntryRenderSignature(entry)
    if type(entry) ~= "table" then
        return "0", true
    end

    local parts = {}
    local cacheable = true

    local cooldownID = entry.cooldownID
    if type(cooldownID) == "number" then
        parts[#parts + 1] = tostring(cooldownID)
    else
        parts[#parts + 1] = "0"
        cacheable = false
    end

    local iconToken, iconOk = BuildRenderPrimitive(entry.icon, "icon_nil")
    if iconOk then
        parts[#parts + 1] = "icon:" .. iconToken
    else
        cacheable = false
    end

    local hasDurationObject = HasValue(entry.duration)
    parts[#parts + 1] = hasDurationObject and "dur_obj:1" or "dur_obj:0"
    if hasDurationObject then
        cacheable = false
    end

    local startToken, startOk = BuildRenderPrimitive(entry.cooldownStartTime, "start_nil")
    if startOk then
        parts[#parts + 1] = "start:" .. startToken
    else
        cacheable = false
    end

    local durationToken, durationOk = BuildRenderPrimitive(entry.cooldownDuration, "dur_nil")
    if durationOk then
        parts[#parts + 1] = "dur:" .. durationToken
    else
        cacheable = false
    end

    local modRateToken, modRateOk = BuildRenderPrimitive(entry.cooldownModRate, "mod_nil")
    if modRateOk then
        parts[#parts + 1] = "mod:" .. modRateToken
    else
        cacheable = false
    end

    local borderToken, borderOk = BuildRenderPrimitive(entry.borderColorToken, "border_nil")
    if borderOk then
        parts[#parts + 1] = "border:" .. borderToken
    else
        cacheable = false
    end

    local fontToken, fontOk = BuildRenderPrimitive(entry.fontColorToken, "font_nil")
    if fontOk then
        parts[#parts + 1] = "font:" .. fontToken
    else
        cacheable = false
    end

    return table.concat(parts, ";"), cacheable
end


local function BuildBucketRenderSignature(activeEntries, iconScale, spacing, orientation, direction, inEditMode)
    local parts = {
        "scale:" .. tostring(iconScale),
        "spacing:" .. tostring(spacing),
        "orientation:" .. tostring(orientation),
        "direction:" .. tostring(direction),
        "edit:" .. (inEditMode and "1" or "0"),
        "count:" .. tostring(#activeEntries),
    }

    local cacheable = true
    for i = 1, #activeEntries do
        local entrySignature, entryCacheable = BuildEntryRenderSignature(activeEntries[i])
        parts[#parts + 1] = entrySignature
        if not entryCacheable then
            cacheable = false
        end
    end

    if not cacheable then
        return nil
    end
    return table.concat(parts, "|")
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


local function ClampSpacing(value)
    local spacing = floor((tonumber(value) or 6) + 0.5)
    if spacing < 0 then
        spacing = 0
    elseif spacing > 20 then
        spacing = 20
    end
    return spacing
end


local function NormalizeOrientation(value)
    if value == ORIENTATION_VERTICAL then
        return ORIENTATION_VERTICAL
    end
    return ORIENTATION_HORIZONTAL
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
    RefineUI.Positions = RefineUI.Positions or {}
    RefineUI.Positions[frameName] = { point, "UIParent", point, x, y }
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
        return true
    end
    return shown and true or false
end


function CDM:GetTrackerVisualSettings(bucketName)
    local cfg = self:GetConfig()
    cfg.BucketSettings = cfg.BucketSettings or {}
    cfg.BucketSettings[bucketName] = cfg.BucketSettings[bucketName] or {}

    local bucketCfg = cfg.BucketSettings[bucketName]
    local iconScale = bucketCfg.IconScale
    if type(iconScale) ~= "number" then
        local legacyIconSize = bucketCfg.IconSize
        if type(legacyIconSize) == "number" and legacyIconSize > 0 then
            iconScale = legacyIconSize / DEFAULT_ICON_BASE_SIZE
        else
            iconScale = cfg.IconScale or 1
        end
    end
    iconScale = ClampIconScale(iconScale)

    local spacing = ClampSpacing(bucketCfg.Spacing or cfg.Spacing)
    local orientation = NormalizeOrientation(bucketCfg.Orientation)
    local direction = NormalizeDirection(bucketName, orientation, bucketCfg.Direction)

    bucketCfg.IconScale = iconScale
    bucketCfg.Spacing = spacing
    bucketCfg.Orientation = orientation
    bucketCfg.Direction = direction
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
    frame:Size(44, 44)

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
    local parentLevel = GetSafeFrameLevelForTracker(frame) or 0
    iconFrame:SetFrameLevel(parentLevel + 1)
    RefineUI.SetTemplate(iconFrame, "Default")
    iconFrame:Hide()

    iconFrame.Icon = iconFrame:CreateTexture(nil, "ARTWORK")
    iconFrame.Icon:SetAllPoints()
    iconFrame.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    iconFrame.Cooldown = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
    ApplyTrackerCooldownSkin(iconFrame)

    frame.icons[index] = iconFrame
    return iconFrame
end

