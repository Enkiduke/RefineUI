----------------------------------------------------------------------------------------
-- CDM Component: VisualsStyles
-- Description: Visual style resolution, color tokens, and override mutation helpers.
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
local type = type
local tonumber = tonumber
local format = string.format
local C_Spell = C_Spell
local GetSpellCooldown = GetSpellCooldown
local GetTime = GetTime
local issecretvalue = _G.issecretvalue

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local TRACKED_BAR = Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBar
local CATEGORY_ESSENTIAL = Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.Essential
local CATEGORY_UTILITY = Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.Utility
local GCD_SPELL_ID = 61304
local GCD_START_TOLERANCE_SECONDS = 0.15
local GCD_DURATION_TOLERANCE_SECONDS = 0.15
local GCD_END_TOLERANCE_SECONDS = 0.2

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end


local function IsUsableCooldownID(value)
    if IsSecret(value) then
        return false
    end
    return type(value) == "number" and value > 0
end


local function ClampColorComponent(value, defaultValue)
    local number = tonumber(value)
    if not number then
        number = defaultValue or 1
    end
    if number < 0 then
        number = 0
    elseif number > 1 then
        number = 1
    end
    return number
end


local function NormalizeColor(color, fallback)
    local source = color
    if type(source) ~= "table" then
        source = fallback
    end
    if type(source) ~= "table" then
        source = { 1, 1, 1, 1 }
    end

    local alpha = source[4]
    if alpha == nil then
        alpha = 1
    end

    return {
        ClampColorComponent(source[1], 1),
        ClampColorComponent(source[2], 1),
        ClampColorComponent(source[3], 1),
        ClampColorComponent(alpha, 1),
    }
end


local function ColorsEqual(left, right)
    if left == right then
        return true
    end
    if type(left) ~= "table" or type(right) ~= "table" then
        return false
    end

    local epsilon = 0.0001
    for i = 1, 4 do
        local lhs = tonumber(left[i]) or (i == 4 and 1 or 0)
        local rhs = tonumber(right[i]) or (i == 4 and 1 or 0)
        if math.abs(lhs - rhs) > epsilon then
            return false
        end
    end
    return true
end


local function CopyColor(source)
    if type(source) ~= "table" then
        return nil
    end
    local normalized = NormalizeColor(source)
    return { normalized[1], normalized[2], normalized[3], normalized[4] }
end


local function ColorToToken(color)
    local normalized = NormalizeColor(color)
    return format("%.3f:%.3f:%.3f:%.3f", normalized[1], normalized[2], normalized[3], normalized[4])
end


local function ResolveCooldownInfo(frame, cooldownID)
    if frame and type(frame.GetCooldownInfo) == "function" then
        local ok, info = pcall(frame.GetCooldownInfo, frame)
        if ok and type(info) == "table" then
            return info
        end
    end

    if IsUsableCooldownID(cooldownID) and CDM.GetCooldownInfo then
        return CDM:GetCooldownInfo(cooldownID)
    end

    return nil
end


local function GetCooldownRegion(frame)
    if frame and frame.Cooldown and type(frame.Cooldown.SetSwipeTexture) == "function" then
        return frame.Cooldown
    end
    return nil
end


----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function CDM:GetVisualOverrides(layoutKey)
    local cfg = self:GetConfig()
    cfg.VisualOverrides = cfg.VisualOverrides or {}
    local key = layoutKey or self:GetCurrentLayoutKey()
    cfg.VisualOverrides[key] = cfg.VisualOverrides[key] or {}
    return cfg.VisualOverrides[key], key
end


function CDM:GetCooldownVisualStyle(cooldownID, layoutKey)
    if not IsUsableCooldownID(cooldownID) then
        return nil
    end

    local overrides = self:GetVisualOverrides(layoutKey)
    local style = overrides[cooldownID]
    if type(style) ~= "table" then
        return nil
    end

    local result = {}
    if type(style.Border) == "table" then
        result.Border = NormalizeColor(style.Border)
    end
    if type(style.Bar) == "table" then
        result.Bar = NormalizeColor(style.Bar)
    end
    if type(style.Font) == "table" then
        result.Font = NormalizeColor(style.Font)
    end

    if not result.Border and not result.Bar and not result.Font then
        return nil
    end
    return result
end


function CDM:GetDefaultBorderColor()
    local general = RefineUI.Config and RefineUI.Config.General
    local border = general and general.BorderColor
    return NormalizeColor(border or { 0.6, 0.6, 0.6, 1 })
end


function CDM:GetDefaultFontColor()
    return { 1, 1, 1, 1 }
end


local function IsSpellCategory(category)
    if IsSecret(category) then
        return false
    end
    return category == CATEGORY_ESSENTIAL or category == CATEGORY_UTILITY
end


local function IsTrackedBarCategory(category)
    if IsSecret(category) then
        return false
    end
    return category == TRACKED_BAR
end


local function GetSettingsItemCategory(frame)
    if not frame or type(frame.GetParent) ~= "function" then
        return nil
    end

    local categoryFrame = frame:GetParent()
    if not categoryFrame or type(categoryFrame.GetCategoryObject) ~= "function" then
        return nil
    end

    local categoryObject = categoryFrame:GetCategoryObject()
    if type(categoryObject) ~= "table" or type(categoryObject.GetCategory) ~= "function" then
        return nil
    end

    local okCategory, category = pcall(categoryObject.GetCategory, categoryObject)
    if not okCategory or IsSecret(category) then
        return nil
    end

    return category
end


function CDM:IsBlizzardSpellIconFrame(frame, cooldownID)
    local info = ResolveCooldownInfo(frame, cooldownID)
    if type(info) ~= "table" then
        return false
    end
    return IsSpellCategory(info.category)
end


function CDM:IsTrackedBarFrame(frame, cooldownID)
    local info = ResolveCooldownInfo(frame, cooldownID)
    if type(info) ~= "table" then
        return false
    end
    return IsTrackedBarCategory(info.category)
end


function CDM:IsSpellSettingsItemFrame(frame, cooldownID)
    if not frame or type(frame.SetAsCooldown) ~= "function" then
        return false
    end

    local category = GetSettingsItemCategory(frame)
    if category ~= nil then
        return IsSpellCategory(category)
    end

    return self:IsBlizzardSpellIconFrame(frame, cooldownID)
end


local function ResolveCooldownWindowStateSeconds(cooldown)
    if not cooldown or type(cooldown.GetCooldownTimes) ~= "function" then
        return false, nil, nil, false
    end

    local okTimes, startMS, durationMS = pcall(cooldown.GetCooldownTimes, cooldown)
    if not okTimes then
        return false, nil, nil, false
    end
    if IsSecret(startMS) or IsSecret(durationMS) then
        return false, nil, nil, false
    end
    if type(startMS) ~= "number" or type(durationMS) ~= "number" then
        return false, nil, nil, false
    end
    if durationMS <= 0 then
        return false, nil, nil, true
    end

    local nowMS = GetTime() * 1000
    if (startMS + durationMS) <= nowMS then
        return false, nil, nil, true
    end

    return true, startMS / 1000, durationMS / 1000, true
end


local function ResolveGlobalCooldownWindowSeconds()
    local startSeconds, durationSeconds

    if C_Spell and type(C_Spell.GetSpellCooldown) == "function" then
        local okSpell, cooldownInfo, durationValue = pcall(C_Spell.GetSpellCooldown, GCD_SPELL_ID)
        if okSpell then
            if type(cooldownInfo) == "table" then
                startSeconds = cooldownInfo.startTime
                durationSeconds = cooldownInfo.duration
            elseif not IsSecret(cooldownInfo) and not IsSecret(durationValue) then
                if type(cooldownInfo) == "number" and type(durationValue) == "number" then
                    startSeconds = cooldownInfo
                    durationSeconds = durationValue
                end
            end
        end
    end

    if (type(startSeconds) ~= "number" or type(durationSeconds) ~= "number")
        and type(GetSpellCooldown) == "function"
    then
        local okLegacy, legacyStart, legacyDuration = pcall(GetSpellCooldown, GCD_SPELL_ID)
        if okLegacy and not IsSecret(legacyStart) and not IsSecret(legacyDuration) then
            if type(legacyStart) == "number" and type(legacyDuration) == "number" then
                startSeconds = legacyStart
                durationSeconds = legacyDuration
            end
        end
    end

    if type(startSeconds) ~= "number" or type(durationSeconds) ~= "number" then
        return nil, nil
    end
    if startSeconds <= 0 or durationSeconds <= 0 then
        return nil, nil
    end
    if (startSeconds + durationSeconds) <= GetTime() then
        return nil, nil
    end

    return startSeconds, durationSeconds
end


function CDM:IsCooldownSwipeShowing(frame)
    local cooldown = GetCooldownRegion(frame)
    if not cooldown then
        return false
    end

    if type(cooldown.GetDrawSwipe) == "function" then
        local okSwipe, drawSwipe = pcall(cooldown.GetDrawSwipe, cooldown)
        if okSwipe and not IsSecret(drawSwipe) and drawSwipe == false then
            return false
        end
    end

    local activeWindow, _, _, hasReliableTimes = ResolveCooldownWindowStateSeconds(cooldown)
    if hasReliableTimes then
        return activeWindow
    end

    if type(cooldown.IsShown) == "function" then
        local okShown, shown = pcall(cooldown.IsShown, cooldown)
        if okShown and not IsSecret(shown) then
            return shown == true
        end
    end

    return false
end


function CDM:IsFrameOnGlobalCooldown(frame)
    local cooldown = GetCooldownRegion(frame)
    if not cooldown then
        return false
    end

    local isActive, frameStartSeconds, frameDurationSeconds = ResolveCooldownWindowStateSeconds(cooldown)
    if not isActive then
        return false
    end

    local gcdStartSeconds, gcdDurationSeconds = ResolveGlobalCooldownWindowSeconds()
    if not gcdStartSeconds or not gcdDurationSeconds then
        return false
    end

    if math.abs(frameDurationSeconds - gcdDurationSeconds) > GCD_DURATION_TOLERANCE_SECONDS then
        return false
    end

    if math.abs(frameStartSeconds - gcdStartSeconds) <= GCD_START_TOLERANCE_SECONDS then
        return true
    end

    local frameEndSeconds = frameStartSeconds + frameDurationSeconds
    local gcdEndSeconds = gcdStartSeconds + gcdDurationSeconds
    return math.abs(frameEndSeconds - gcdEndSeconds) <= GCD_END_TOLERANCE_SECONDS
end


function CDM:GetResolvedBorderColorForFrame(frame, cooldownID, layoutKey)
    local defaultColor = self:GetDefaultBorderColor()
    local style = self:GetCooldownVisualStyle(cooldownID, layoutKey)

    if not self:IsBlizzardSpellIconFrame(frame, cooldownID) then
        if style and style.Border then
            return style.Border
        end
        return defaultColor
    end

    if not style or not style.Border then
        return defaultColor
    end

    if self:IsSpellSettingsItemFrame(frame, cooldownID) then
        return style.Border
    end

    if self:IsCooldownSwipeShowing(frame) then
        if self:IsFrameOnGlobalCooldown(frame) then
            return defaultColor
        end
        return style.Border
    end

    return defaultColor
end


function CDM:GetCooldownBorderColor(cooldownID, layoutKey)
    local style = self:GetCooldownVisualStyle(cooldownID, layoutKey)
    if style and style.Border then
        return style.Border
    end
    return self:GetDefaultBorderColor()
end


function CDM:GetCooldownBorderColorToken(cooldownID, layoutKey)
    return ColorToToken(self:GetCooldownBorderColor(cooldownID, layoutKey))
end


function CDM:GetCooldownBarColor(cooldownID, layoutKey)
    local style = self:GetCooldownVisualStyle(cooldownID, layoutKey)
    if style and style.Bar then
        return style.Bar
    end
    return nil
end


function CDM:GetCooldownFontColor(cooldownID, layoutKey)
    local style = self:GetCooldownVisualStyle(cooldownID, layoutKey)
    if style and style.Font then
        return style.Font
    end
    return self:GetDefaultFontColor()
end


function CDM:GetCooldownFontColorToken(cooldownID, layoutKey)
    return ColorToToken(self:GetCooldownFontColor(cooldownID, layoutKey))
end


function CDM:ApplyTrackerIconVisual(iconFrame, cooldownID)
    if not iconFrame or not iconFrame.border or type(iconFrame.border.SetBackdropBorderColor) ~= "function" then
        return
    end

    local borderColor
    if IsUsableCooldownID(cooldownID) then
        borderColor = self:GetCooldownBorderColor(cooldownID)
    else
        borderColor = self:GetDefaultBorderColor()
    end

    iconFrame.border:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
end


function CDM:InvalidateTrackerRenderSignatures()
    if type(self.trackerFrames) ~= "table" then
        return
    end

    for i = 1, #self.TRACKER_BUCKETS do
        local bucket = self.TRACKER_BUCKETS[i]
        local frame = self.trackerFrames[bucket]
        if frame then
            self:StateClear(frame, "renderSignature")
            self:StateClear(frame, "renderEntryCount")
        end
    end
end


local function PruneEmptyStyle(style)
    if type(style) ~= "table" then
        return true
    end
    return style.Border == nil and style.Bar == nil and style.Font == nil
end


function CDM:OnVisualStylesChanged()
    self:InvalidateTrackerRenderSignatures()
    self:RequestCooldownViewerVisualRefresh()
    self:RequestRefresh(true)
    if self:IsSettingsFrameShown() and self.RefreshSettingsSection then
        self:RefreshSettingsSection()
    end
end


function CDM:SetCooldownBorderColor(cooldownID, rgba, layoutKey)
    if not IsUsableCooldownID(cooldownID) then
        return false
    end

    local overrides = self:GetVisualOverrides(layoutKey)
    local style = overrides[cooldownID]
    if type(style) ~= "table" then
        style = {}
        overrides[cooldownID] = style
    end

    local color = NormalizeColor(rgba)
    local defaultColor = self:GetDefaultBorderColor()
    if ColorsEqual(color, defaultColor) then
        style.Border = nil
    else
        style.Border = CopyColor(color)
    end

    if PruneEmptyStyle(style) then
        overrides[cooldownID] = nil
    end

    self:OnVisualStylesChanged()
    return true
end


function CDM:SetCooldownBarColor(cooldownID, rgba, layoutKey)
    if not IsUsableCooldownID(cooldownID) then
        return false
    end

    local overrides = self:GetVisualOverrides(layoutKey)
    local style = overrides[cooldownID]
    if type(style) ~= "table" then
        style = {}
        overrides[cooldownID] = style
    end

    style.Bar = CopyColor(NormalizeColor(rgba))
    if PruneEmptyStyle(style) then
        overrides[cooldownID] = nil
    end

    self:OnVisualStylesChanged()
    return true
end


function CDM:SetCooldownFontColor(cooldownID, rgba, layoutKey)
    if not IsUsableCooldownID(cooldownID) then
        return false
    end

    local overrides = self:GetVisualOverrides(layoutKey)
    local style = overrides[cooldownID]
    if type(style) ~= "table" then
        style = {}
        overrides[cooldownID] = style
    end

    local color = NormalizeColor(rgba)
    local defaultColor = self:GetDefaultFontColor()
    if ColorsEqual(color, defaultColor) then
        style.Font = nil
    else
        style.Font = CopyColor(color)
    end

    if PruneEmptyStyle(style) then
        overrides[cooldownID] = nil
    end

    self:OnVisualStylesChanged()
    return true
end


function CDM:ClearCooldownVisualStyle(cooldownID, what, layoutKey)
    if not IsUsableCooldownID(cooldownID) then
        return false
    end

    local overrides = self:GetVisualOverrides(layoutKey)
    local style = overrides[cooldownID]
    if type(style) ~= "table" then
        return false
    end

    if what == "Border" then
        style.Border = nil
    elseif what == "Bar" then
        style.Bar = nil
    elseif what == "Font" then
        style.Font = nil
    else
        style.Border = nil
        style.Bar = nil
        style.Font = nil
    end

    if PruneEmptyStyle(style) then
        overrides[cooldownID] = nil
    end

    self:OnVisualStylesChanged()
    return true
end


function CDM:IsSkinCooldownViewerEnabled()
    return self:GetConfig().SkinCooldownViewer ~= false
end

