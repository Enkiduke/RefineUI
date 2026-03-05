----------------------------------------------------------------------------------------
-- EncounterTimeline Component: Skin
-- Description: Timeline view/event-frame skinning and border/icon styling
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local EncounterTimeline = RefineUI:GetModule("EncounterTimeline")
if not EncounterTimeline then
    return
end

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local CreateFrame = CreateFrame
local math_max = math.max
local math_min = math.min
local pcall = pcall
local tostring = tostring
local type = type
local issecretvalue = _G.issecretvalue
local canaccessvalue = _G.canaccessvalue

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local VIEW_BORDER_INSET = 6
local EDGE_SIZE = 12
local TRACK_LINE_BAR_THICKNESS = 8
local TRACK_LINE_BORDER_INSET = 6
local TRACK_LINE_ALPHA = 0.5
local TRACK_LINE_FRAME_LEVEL_OFFSET = -2
local TRACK_COUNTDOWN_FONT_SIZE = 22
local TIMER_COUNTDOWN_FONT_SIZE = 18
local TIMER_NAME_FONT_SIZE = 12
local TRACK_NAME_FONT_SIZE = 11
local TRACK_STATUS_FONT_SIZE = 10
local PIP_TEXT_FONT_SIZE = 14
local TRACK_TEXT_ANCHOR_OFFSET = 10
local SPELL_TYPE_ICON_ANCHOR_OFFSET_Y = -6
local SPELL_TYPE_ICON_SPACING = 2
local SPELL_NAME_UNDER_ICON_OFFSET_Y = -2
local SPELL_STATUS_UNDER_NAME_OFFSET_Y = -1

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local function IsTimerEventFrame(eventFrame)
    return eventFrame and eventFrame.Bar ~= nil
end

local function IsTrackEventFrame(eventFrame)
    return eventFrame and eventFrame.Countdown ~= nil
end

local function GetStatusbarTexture()
    local media = RefineUI.Media
    local textures = media and media.Textures
    return textures and textures.Statusbar
end

local function IsTrackView(viewFrame)
    return viewFrame and viewFrame.LineStart and viewFrame.LineEnd
end

local function IsUnreadableValue(value)
    if value == nil then
        return false
    end

    if issecretvalue and issecretvalue(value) then
        return true
    end
    if canaccessvalue and not canaccessvalue(value) then
        return true
    end
    if RefineUI.IsSecretValue and RefineUI:IsSecretValue(value) then
        return true
    end
    return false
end

local function IsBlizzardAutoScalingTextElement(fontString)
    if not fontString then
        return false
    end

    -- EncounterWarnings text elements mix in AutoScalingFontStringMixin.
    return type(fontString.SetTextScale) == "function"
        and type(fontString.SetTextToFit) == "function"
        and type(fontString.ScaleTextToFit) == "function"
end

local function HasAnyValue(value)
    return value ~= nil
end

local function GetShownState(frame)
    if not frame or type(frame.IsShown) ~= "function" then
        return nil
    end

    local ok, shown = pcall(frame.IsShown, frame)
    if not ok or IsUnreadableValue(shown) or type(shown) ~= "boolean" then
        return nil
    end

    return shown
end

local function IsFrameShown(frame)
    if not frame then
        return false
    end

    local shown = GetShownState(frame)
    if shown == nil then
        return true
    end
    return shown
end

local function GetSafeFrameLevel(frame, fallback)
    local safeFallback = type(fallback) == "number" and fallback or 0
    if not frame or type(frame.GetFrameLevel) ~= "function" then
        return safeFallback
    end

    local ok, frameLevel = pcall(frame.GetFrameLevel, frame)
    if not ok or IsUnreadableValue(frameLevel) or type(frameLevel) ~= "number" then
        return safeFallback
    end

    return frameLevel
end

local function GetSafeFrameStrata(frame, fallback)
    local safeFallback = (type(fallback) == "string" and fallback ~= "") and fallback or "MEDIUM"
    if not frame or type(frame.GetFrameStrata) ~= "function" then
        return safeFallback
    end

    local ok, frameStrata = pcall(frame.GetFrameStrata, frame)
    if not ok or IsUnreadableValue(frameStrata) or type(frameStrata) ~= "string" or frameStrata == "" then
        return safeFallback
    end

    return frameStrata
end

local function IsSafeColorChannel(value)
    return type(value) == "number" and not IsUnreadableValue(value)
end

local function GetCountdownSwipeTexture()
    local media = RefineUI.Media
    local textures = media and media.Textures
    if type(textures) ~= "table" then
        return nil
    end
    return textures.CooldownSwipe or textures.CooldownSwipeSmall
end

local function ApplyCooldownTextStyle(cooldown, fontSize)
    if not cooldown or type(cooldown.GetRegions) ~= "function" then
        return
    end

    local regions = { cooldown:GetRegions() }
    for index = 1, #regions do
        local region = regions[index]
        if region and type(region.GetObjectType) == "function" and region:GetObjectType() == "FontString" then
            if not IsBlizzardAutoScalingTextElement(region) then
                RefineUI.Font(region, fontSize, RefineUI.Media.Fonts.Number, "OUTLINE", true)
            end
        end
    end
end

local function ApplyCooldownSwipeStyle(cooldown)
    if not cooldown then
        return
    end

    local swipeTexture = GetCountdownSwipeTexture()
    if swipeTexture and cooldown.SetSwipeTexture then
        pcall(cooldown.SetSwipeTexture, cooldown, swipeTexture)
    end

    if cooldown.SetDrawEdge then
        pcall(cooldown.SetDrawEdge, cooldown, false)
    end
    if cooldown.SetDrawBling then
        pcall(cooldown.SetDrawBling, cooldown, false)
    end
    if cooldown.SetDrawSwipe then
        pcall(cooldown.SetDrawSwipe, cooldown, true)
    end
end

local function GetConfiguredTextShadowStyle()
    local appearance = RefineUI.Config and RefineUI.Config.General and RefineUI.Config.General.Appearance
    local offsetX, offsetY = 1, -1
    local colorR, colorG, colorB, colorA = 0, 0, 0, 1

    if type(appearance) == "table" then
        local shadowOffset = appearance.ShadowOffset
        if type(shadowOffset) == "table" then
            if type(shadowOffset[1]) == "number" and not IsUnreadableValue(shadowOffset[1]) then
                offsetX = shadowOffset[1]
            end
            if type(shadowOffset[2]) == "number" and not IsUnreadableValue(shadowOffset[2]) then
                offsetY = shadowOffset[2]
            end
        end

        local shadowColor = appearance.ShadowColor
        if type(shadowColor) == "table" then
            if type(shadowColor[1]) == "number" and not IsUnreadableValue(shadowColor[1]) then
                colorR = shadowColor[1]
            end
            if type(shadowColor[2]) == "number" and not IsUnreadableValue(shadowColor[2]) then
                colorG = shadowColor[2]
            end
            if type(shadowColor[3]) == "number" and not IsUnreadableValue(shadowColor[3]) then
                colorB = shadowColor[3]
            end
            if type(shadowColor[4]) == "number" and not IsUnreadableValue(shadowColor[4]) then
                colorA = shadowColor[4]
            end
        end
    end

    return offsetX, offsetY, colorR, colorG, colorB, colorA
end

local function ApplyTrackTextStyle(fontString, fontSize)
    if not fontString then
        return
    end

    if IsBlizzardAutoScalingTextElement(fontString) then
        -- Do not mutate font/scale for AutoScalingFontStringMixin text;
        -- this can taint secret-value math in Blizzard's ScaleTextToFit path.
    else
        RefineUI.Font(fontString, fontSize, RefineUI.Media.Fonts.Medium, "OUTLINE", true)
    end

    local offsetX, offsetY, colorR, colorG, colorB, colorA = GetConfiguredTextShadowStyle()
    if type(fontString.SetShadowOffset) == "function" then
        pcall(fontString.SetShadowOffset, fontString, offsetX, offsetY)
    end
    if type(fontString.SetShadowColor) == "function" then
        pcall(fontString.SetShadowColor, fontString, colorR, colorG, colorB, colorA)
    end
end

local function CreateTrackReplacementText(eventFrame, drawLayerSubLevel)
    if not eventFrame or type(eventFrame.CreateFontString) ~= "function" then
        return nil
    end

    local text = eventFrame:CreateFontString(nil, "OVERLAY")
    if not text then
        return nil
    end

    if type(text.SetDrawLayer) == "function" then
        pcall(text.SetDrawLayer, text, "OVERLAY", drawLayerSubLevel or 7)
    end
    if type(text.SetJustifyV) == "function" then
        pcall(text.SetJustifyV, text, "MIDDLE")
    end
    if type(text.SetWordWrap) == "function" then
        pcall(text.SetWordWrap, text, false)
    end
    if type(text.Hide) == "function" then
        text:Hide()
    end

    return text
end

function EncounterTimeline:EnsureTrackReplacementTextState(eventFrame)
    if not eventFrame or not IsTrackEventFrame(eventFrame) then
        return nil, nil
    end

    local state = self:StateGet(eventFrame, "trackReplacementTextState")
    if type(state) ~= "table" then
        state = {}
        self:StateSet(eventFrame, "trackReplacementTextState", state)
    end

    local nameText = state.NameText
    if not nameText or type(nameText.GetParent) ~= "function" or nameText:GetParent() ~= eventFrame then
        nameText = CreateTrackReplacementText(eventFrame, 7)
        state.NameText = nameText
    end

    local statusText = state.StatusText
    if not statusText or type(statusText.GetParent) ~= "function" or statusText:GetParent() ~= eventFrame then
        statusText = CreateTrackReplacementText(eventFrame, 7)
        state.StatusText = statusText
    end

    return nameText, statusText
end

local function SuppressBlizzardTrackText(fontString)
    if not fontString then
        return
    end

    if type(fontString.SetAlpha) == "function" then
        pcall(fontString.SetAlpha, fontString, 0)
    end
end

local function GetTrackDisplayTextElements(eventFrame)
    if not eventFrame then
        return nil, nil
    end

    local state = EncounterTimeline:StateGet(eventFrame, "trackReplacementTextState")
    if type(state) == "table" and state.NameText and state.StatusText then
        return state.NameText, state.StatusText
    end

    return eventFrame.NameText, eventFrame.StatusText
end

local function SyncTrackReplacementFontString(sourceText, replacementText)
    if not sourceText or not replacementText then
        return
    end

    local shown = GetShownState(sourceText)
    local textValue = ""
    if type(sourceText.GetText) == "function" then
        local ok, value = pcall(sourceText.GetText, sourceText)
        if ok and not IsUnreadableValue(value) and type(value) == "string" then
            textValue = value
        end
    end

    if type(replacementText.SetText) == "function" then
        pcall(replacementText.SetText, replacementText, textValue)
    end

    if type(sourceText.GetTextColor) == "function" and type(replacementText.SetTextColor) == "function" then
        local ok, red, green, blue, alpha = pcall(sourceText.GetTextColor, sourceText)
        if ok and IsSafeColorChannel(red) and IsSafeColorChannel(green) and IsSafeColorChannel(blue) then
            if not IsSafeColorChannel(alpha) then
                alpha = 1
            end
            pcall(replacementText.SetTextColor, replacementText, red, green, blue, alpha)
        end
    end

    if shown == false then
        if type(replacementText.Hide) == "function" then
            replacementText:Hide()
        end
    else
        if type(replacementText.Show) == "function" then
            replacementText:Show()
        end
        if type(replacementText.SetAlpha) == "function" then
            pcall(replacementText.SetAlpha, replacementText, 1)
        end
    end
end

function EncounterTimeline:HideBlizzardTrackText(eventFrame)
    if not eventFrame then
        return
    end

    SuppressBlizzardTrackText(eventFrame.NameText)
    SuppressBlizzardTrackText(eventFrame.StatusText)
end

function EncounterTimeline:SyncTrackReplacementText(eventFrame)
    if not eventFrame or not IsTrackEventFrame(eventFrame) then
        return
    end

    local nameReplacement, statusReplacement = self:EnsureTrackReplacementTextState(eventFrame)
    if not nameReplacement or not statusReplacement then
        return
    end

    SyncTrackReplacementFontString(eventFrame.NameText, nameReplacement)
    SyncTrackReplacementFontString(eventFrame.StatusText, statusReplacement)
end

local function ApplyIconContainerSkin(iconContainer)
    if not iconContainer then
        return
    end

    if iconContainer.bg and iconContainer.bg.SetAlpha then
        iconContainer.bg:SetAlpha(0)
    end
end

local function HasProbeTextureResult(texture, requireVisibleAlpha)
    if not texture then
        return false
    end

    if GetShownState(texture) == false then
        return false
    end

    if requireVisibleAlpha == true and type(texture.GetAlpha) == "function" then
        local okAlpha, alpha = pcall(texture.GetAlpha, texture)
        if okAlpha and type(alpha) == "number" and not IsUnreadableValue(alpha) and alpha <= 0 then
            return false
        end
    end

    if type(texture.GetAtlas) == "function" then
        local okAtlas, atlas = pcall(texture.GetAtlas, texture)
        if okAtlas and type(atlas) == "string" and atlas ~= "" and not IsUnreadableValue(atlas) then
            return true
        end
    end

    if type(texture.GetTexture) == "function" then
        local okTexture, resolvedTexture = pcall(texture.GetTexture, texture)
        if okTexture and HasAnyValue(resolvedTexture) and not IsUnreadableValue(resolvedTexture) then
            return true
        end
    end

    return false
end

function EncounterTimeline:ApplyEventIconVisualStyling(eventFrame, _eventID)
    if not eventFrame then
        return
    end

    local iconContainer = eventFrame.IconContainer
    if iconContainer and iconContainer.bg and iconContainer.bg.SetAlpha then
        iconContainer.bg:SetAlpha(0)
    end
end

local function CollectVisibleIndicatorTextures(indicatorContainer)
    local visibleIndicators = {}
    if not indicatorContainer then
        return visibleIndicators
    end

    local function IsRenderableIndicatorTexture(indicatorTexture)
        if not indicatorTexture then
            return false
        end

        local shown = GetShownState(indicatorTexture)
        if shown == false then
            return false
        end

        return HasProbeTextureResult(indicatorTexture, false)
    end

    local function AppendVisible(textureList)
        if type(textureList) ~= "table" then
            return
        end

        for index = 1, #textureList do
            local indicatorTexture = textureList[index]
            if IsRenderableIndicatorTexture(indicatorTexture) then
                visibleIndicators[#visibleIndicators + 1] = indicatorTexture
            end
        end
    end

    AppendVisible(indicatorContainer.RoleIndicators)
    AppendVisible(indicatorContainer.OtherIndicators)
    return visibleIndicators
end

local function CollectVisibleEffectIndicatorTextures(indicatorContainer)
    local visibleIndicators = {}
    if not indicatorContainer then
        return visibleIndicators
    end

    local otherIndicators = indicatorContainer.OtherIndicators
    if type(otherIndicators) ~= "table" then
        return visibleIndicators
    end

    for index = 1, #otherIndicators do
        local indicatorTexture = otherIndicators[index]
        if indicatorTexture and GetShownState(indicatorTexture) ~= false and HasProbeTextureResult(indicatorTexture, false) then
            visibleIndicators[#visibleIndicators + 1] = indicatorTexture
        end
    end

    return visibleIndicators
end

local function CollectVisibleRoleIndicatorTextures(indicatorContainer)
    local visibleIndicators = {}
    if not indicatorContainer then
        return visibleIndicators
    end

    local roleIndicators = indicatorContainer.RoleIndicators
    if type(roleIndicators) ~= "table" then
        return visibleIndicators
    end

    for index = 1, #roleIndicators do
        local indicatorTexture = roleIndicators[index]
        if indicatorTexture and GetShownState(indicatorTexture) ~= false and HasProbeTextureResult(indicatorTexture, false) then
            visibleIndicators[#visibleIndicators + 1] = indicatorTexture
        end
    end

    return visibleIndicators
end

local function ElevateIndicatorLayer(eventFrame, indicatorContainer)
    if not eventFrame or not indicatorContainer then
        return
    end

    local iconContainer = eventFrame.IconContainer or eventFrame
    local targetStrata = GetSafeFrameStrata(iconContainer, "MEDIUM")
    local targetLevel = math_max(0, GetSafeFrameLevel(iconContainer, 0) + 13)

    if type(indicatorContainer.SetFrameStrata) == "function" then
        pcall(indicatorContainer.SetFrameStrata, indicatorContainer, targetStrata)
    end
    if type(indicatorContainer.SetFrameLevel) == "function" then
        pcall(indicatorContainer.SetFrameLevel, indicatorContainer, targetLevel)
    end

    local function ElevateTextureList(textureList)
        if type(textureList) ~= "table" then
            return
        end
        for index = 1, #textureList do
            local texture = textureList[index]
            if texture and type(texture.SetDrawLayer) == "function" then
                pcall(texture.SetDrawLayer, texture, "OVERLAY", 7)
            end
        end
    end

    ElevateTextureList(indicatorContainer.RoleIndicators)
    ElevateTextureList(indicatorContainer.OtherIndicators)
end

local function GetVisibleFontStringHeight(fontString)
    if not fontString then
        return 0
    end

    local shown = GetShownState(fontString)
    if shown == false then
        return 0
    end

    if type(fontString.GetStringHeight) == "function" then
        local ok, stringHeight = pcall(fontString.GetStringHeight, fontString)
        if ok and not IsUnreadableValue(stringHeight) and type(stringHeight) == "number" and stringHeight > 0 then
            return stringHeight
        end
    end

    if type(fontString.GetHeight) == "function" then
        local ok, regionHeight = pcall(fontString.GetHeight, fontString)
        if ok and not IsUnreadableValue(regionHeight) and type(regionHeight) == "number" and regionHeight > 0 then
            return regionHeight
        end
    end

    return 0
end

local function ComputeTrackIconRowCenterOffsetY(eventFrame, nameText, statusText)
    if not eventFrame then
        return SPELL_TYPE_ICON_ANCHOR_OFFSET_Y
    end

    local displayNameText = nameText or eventFrame.NameText
    local displayStatusText = statusText or eventFrame.StatusText
    local nameHeight = GetVisibleFontStringHeight(displayNameText)
    local statusHeight = GetVisibleFontStringHeight(displayStatusText)
    local hasName = nameHeight > 0
    local hasStatus = statusHeight > 0

    if hasName and hasStatus then
        return (nameHeight + statusHeight - SPELL_NAME_UNDER_ICON_OFFSET_Y - SPELL_STATUS_UNDER_NAME_OFFSET_Y) * 0.5
    end

    if hasName then
        return (nameHeight - SPELL_NAME_UNDER_ICON_OFFSET_Y) * 0.5
    end

    if hasStatus then
        return (statusHeight - SPELL_NAME_UNDER_ICON_OFFSET_Y) * 0.5
    end

    return SPELL_TYPE_ICON_ANCHOR_OFFSET_Y
end

function EncounterTimeline:ApplyTrackTextAnchorOverride(eventFrame)
    if not eventFrame or not IsTrackEventFrame(eventFrame) then
        return
    end

    local nameText, statusText = GetTrackDisplayTextElements(eventFrame)
    if not nameText or not statusText then
        return
    end

    local config = self:GetConfig()
    local desiredAnchor = config.TrackTextAnchor or self.TRACK_TEXT_ANCHOR.LEFT
    local iconScale = (type(eventFrame.GetIconScale) == "function" and eventFrame:GetIconScale()) or 1
    if IsUnreadableValue(iconScale) or type(iconScale) ~= "number" then
        iconScale = 1
    end

    local okOffset, scaledOffset = pcall(function()
        return TRACK_TEXT_ANCHOR_OFFSET * iconScale
    end)
    local offset = (okOffset and type(scaledOffset) == "number") and scaledOffset or TRACK_TEXT_ANCHOR_OFFSET
    local pointName = "LEFT"
    local relativePointName = "RIGHT"
    local offsetX = offset
    local nameTopPoint = "BOTTOMLEFT"
    local statusTopPoint = "TOPLEFT"
    local textJustify = "LEFT"

    if desiredAnchor == self.TRACK_TEXT_ANCHOR.LEFT then
        pointName = "RIGHT"
        relativePointName = "LEFT"
        offsetX = -offset
        nameTopPoint = "BOTTOMRIGHT"
        statusTopPoint = "TOPRIGHT"
        textJustify = "RIGHT"
    end

    if type(nameText.SetJustifyH) == "function" then
        nameText:SetJustifyH(textJustify)
    end
    if type(statusText.SetJustifyH) == "function" then
        statusText:SetJustifyH(textJustify)
    end

    local indicatorContainer = eventFrame.Indicators or eventFrame.IndicatorContainer
    local visibleIndicators = CollectVisibleIndicatorTextures(indicatorContainer)
    local visibleRoleIndicators = CollectVisibleRoleIndicatorTextures(indicatorContainer)

    nameText:ClearAllPoints()
    statusText:ClearAllPoints()

    if #visibleRoleIndicators == 0 then
        local iconFrame = eventFrame.IconContainer or eventFrame

        if type(nameText.SetJustifyH) == "function" then
            nameText:SetJustifyH("LEFT")
        end
        if type(statusText.SetJustifyH) == "function" then
            statusText:SetJustifyH("LEFT")
        end

        local rightOffset = math.abs(offset)
        local splitOffset = 1
        local nameShown = GetShownState(nameText) ~= false
        local statusShown = GetShownState(statusText) ~= false

        if nameShown and statusShown then
            nameText:SetPoint("BOTTOMLEFT", iconFrame, "RIGHT", rightOffset, splitOffset)
            statusText:SetPoint("TOPLEFT", iconFrame, "RIGHT", rightOffset, -splitOffset)
        elseif nameShown then
            nameText:SetPoint("LEFT", iconFrame, "RIGHT", rightOffset, 0)
        else
            statusText:SetPoint("LEFT", iconFrame, "RIGHT", rightOffset, 0)
        end
        return
    end

    if #visibleIndicators > 0 then
        local anchorIndicator = visibleIndicators[1]
        if desiredAnchor == self.TRACK_TEXT_ANCHOR.LEFT then
            nameText:SetPoint("TOPRIGHT", anchorIndicator, "BOTTOMRIGHT", 0, SPELL_NAME_UNDER_ICON_OFFSET_Y)
            statusText:SetPoint("TOPRIGHT", nameText, "BOTTOMRIGHT", 0, SPELL_STATUS_UNDER_NAME_OFFSET_Y)
        else
            nameText:SetPoint("TOPLEFT", anchorIndicator, "BOTTOMLEFT", 0, SPELL_NAME_UNDER_ICON_OFFSET_Y)
            statusText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, SPELL_STATUS_UNDER_NAME_OFFSET_Y)
        end
        return
    end

    nameText:SetPoint(pointName, eventFrame, relativePointName, offsetX, 0)
    statusText:SetPoint(statusTopPoint, nameText, nameTopPoint, 0, SPELL_STATUS_UNDER_NAME_OFFSET_Y)
end

function EncounterTimeline:ApplySpellTypeIndicatorAnchorOverride(eventFrame)
    if not eventFrame then
        return
    end

    local iconFrame = eventFrame.IconContainer
    local indicatorContainer = eventFrame.Indicators or eventFrame.IndicatorContainer
    if not iconFrame or not indicatorContainer then
        return
    end

    ElevateIndicatorLayer(eventFrame, indicatorContainer)

    local visibleIndicators = CollectVisibleIndicatorTextures(indicatorContainer)
    if #visibleIndicators == 0 then
        if IsTrackEventFrame(eventFrame) then
            self:ApplyTrackTextAnchorOverride(eventFrame)
        end
        return
    end

    local firstIndicator = visibleIndicators[1]
    local growRightToLeft = false
    local firstPoint = "BOTTOMLEFT"
    local firstRelativePoint = "TOPLEFT"
    local firstOffsetX = 0
    local firstOffsetY = SPELL_TYPE_ICON_ANCHOR_OFFSET_Y

    if IsTrackEventFrame(eventFrame) then
        local displayNameText, displayStatusText = GetTrackDisplayTextElements(eventFrame)
        local hasAutoScalingTrackText = IsBlizzardAutoScalingTextElement(displayNameText)
            or IsBlizzardAutoScalingTextElement(displayStatusText)
        local config = self:GetConfig()
        local desiredAnchor = config.TrackTextAnchor or self.TRACK_TEXT_ANCHOR.LEFT
        local iconScale = (type(eventFrame.GetIconScale) == "function" and eventFrame:GetIconScale()) or 1
        if IsUnreadableValue(iconScale) or type(iconScale) ~= "number" then
            iconScale = 1
        end

        local okSideOffset, sideOffsetValue = pcall(function()
            return math.abs(TRACK_TEXT_ANCHOR_OFFSET * iconScale)
        end)
        local sideOffset = (okSideOffset and type(sideOffsetValue) == "number") and sideOffsetValue or TRACK_TEXT_ANCHOR_OFFSET
        local iconWidth = (type(iconFrame.GetWidth) == "function" and iconFrame:GetWidth()) or 0
        if IsUnreadableValue(iconWidth) or type(iconWidth) ~= "number" then
            iconWidth = 0
        end

        local indicatorWidth = (type(firstIndicator.GetWidth) == "function" and firstIndicator:GetWidth()) or 0
        if IsUnreadableValue(indicatorWidth) or type(indicatorWidth) ~= "number" then
            indicatorWidth = 0
        end

        if not hasAutoScalingTrackText then
            firstOffsetY = ComputeTrackIconRowCenterOffsetY(eventFrame, displayNameText, displayStatusText)
        end
        firstPoint = "CENTER"
        firstRelativePoint = "CENTER"

        if desiredAnchor == self.TRACK_TEXT_ANCHOR.LEFT then
            growRightToLeft = true
            local okOffsetX, offsetX = pcall(function()
                return -((iconWidth * 0.5) + sideOffset + (indicatorWidth * 0.5))
            end)
            if okOffsetX and type(offsetX) == "number" then
                firstOffsetX = offsetX
            else
                firstOffsetX = -sideOffset
            end
        else
            growRightToLeft = false
            local okOffsetX, offsetX = pcall(function()
                return (iconWidth * 0.5) + sideOffset + (indicatorWidth * 0.5)
            end)
            if okOffsetX and type(offsetX) == "number" then
                firstOffsetX = offsetX
            else
                firstOffsetX = sideOffset
            end
        end
    elseif type(eventFrame.ShouldFlipHorizontally) == "function" then
        local ok, flipped = pcall(eventFrame.ShouldFlipHorizontally, eventFrame)
        if ok and not IsUnreadableValue(flipped) and type(flipped) == "boolean" then
            growRightToLeft = flipped
        end

        if growRightToLeft then
            firstPoint = "BOTTOMRIGHT"
            firstRelativePoint = "TOPRIGHT"
        else
            firstPoint = "BOTTOMLEFT"
            firstRelativePoint = "TOPLEFT"
        end
    end

    firstIndicator:ClearAllPoints()
    firstIndicator:SetPoint(firstPoint, iconFrame, firstRelativePoint, firstOffsetX, firstOffsetY)

    for index = 2, #visibleIndicators do
        local indicatorTexture = visibleIndicators[index]
        local previousTexture = visibleIndicators[index - 1]
        indicatorTexture:ClearAllPoints()
        if growRightToLeft then
            indicatorTexture:SetPoint("RIGHT", previousTexture, "LEFT", -SPELL_TYPE_ICON_SPACING, 0)
        else
            indicatorTexture:SetPoint("LEFT", previousTexture, "RIGHT", SPELL_TYPE_ICON_SPACING, 0)
        end
    end

    -- Keep the primary effect indicator pinned to the icon's top-center edge.
    local effectIndicators = CollectVisibleEffectIndicatorTextures(indicatorContainer)
    if #effectIndicators > 0 then
        local effectIndicator = effectIndicators[1]
        effectIndicator:ClearAllPoints()
        effectIndicator:SetPoint("BOTTOM", iconFrame, "TOP", 0, SPELL_TYPE_ICON_ANCHOR_OFFSET_Y)
    end

    if IsTrackEventFrame(eventFrame) then
        self:ApplyTrackTextAnchorOverride(eventFrame)
    end
end

local function HideTrackLineTexture(texture)
    if texture and texture.SetAlpha then
        texture:SetAlpha(0)
    end
end

local function ShowTrackLineTexture(texture)
    if texture and texture.SetAlpha then
        texture:SetAlpha(1)
    end
end

function EncounterTimeline:RestoreDefaultTrackLineArt(viewFrame)
    if not IsTrackView(viewFrame) then
        return
    end

    ShowTrackLineTexture(viewFrame.LineStart)
    ShowTrackLineTexture(viewFrame.LineEnd)
    ShowTrackLineTexture(viewFrame.LongDivider)
    ShowTrackLineTexture(viewFrame.QueueDivider)

    if type(viewFrame.EnumerateLineBreakMaskTextures) == "function" then
        for _, maskTexture in viewFrame:EnumerateLineBreakMaskTextures() do
            ShowTrackLineTexture(maskTexture)
        end
    end
end

function EncounterTimeline:HideDefaultTrackLineArt(viewFrame)
    if not IsTrackView(viewFrame) then
        return
    end

    HideTrackLineTexture(viewFrame.LineStart)
    HideTrackLineTexture(viewFrame.LineEnd)
    HideTrackLineTexture(viewFrame.LongDivider)
    HideTrackLineTexture(viewFrame.QueueDivider)

    if type(viewFrame.EnumerateLineBreakMaskTextures) == "function" then
        for _, maskTexture in viewFrame:EnumerateLineBreakMaskTextures() do
            HideTrackLineTexture(maskTexture)
        end
    end
end

function EncounterTimeline:EnsureTrackLineBar(viewFrame)
    local barFrame = self:StateGet(viewFrame, "trackLineBar")
    if barFrame then
        return barFrame
    end

    barFrame = CreateFrame("Frame", nil, viewFrame)
    RefineUI:AddAPI(barFrame)
    barFrame:SetFrameStrata(GetSafeFrameStrata(viewFrame, "MEDIUM"))
    barFrame:SetFrameLevel(math_max(0, GetSafeFrameLevel(viewFrame, 0) + TRACK_LINE_FRAME_LEVEL_OFFSET))
    barFrame:SetAlpha(TRACK_LINE_ALPHA)
    RefineUI.SetTemplate(barFrame, "Default")
    RefineUI.CreateBorder(barFrame, TRACK_LINE_BORDER_INSET, TRACK_LINE_BORDER_INSET, EDGE_SIZE)

    local fill = barFrame:CreateTexture(nil, "ARTWORK")
    fill:SetAllPoints()
    fill:SetTexture(GetStatusbarTexture())
    barFrame:Hide()

    self:StateSet(viewFrame, "trackLineBar", barFrame)
    self:StateSet(viewFrame, "trackLineFill", fill)
    return barFrame
end

function EncounterTimeline:UpdateTrackLineBarGeometry(viewFrame, barFrame)
    if not IsTrackView(viewFrame) or not barFrame then
        return false
    end

    local lineStart = viewFrame.LineStart
    local lineEnd = viewFrame.LineEnd
    local viewLeft = viewFrame:GetLeft()
    local viewBottom = viewFrame:GetBottom()
    local left1, right1 = lineStart:GetLeft(), lineStart:GetRight()
    local top1, bottom1 = lineStart:GetTop(), lineStart:GetBottom()
    local left2, right2 = lineEnd:GetLeft(), lineEnd:GetRight()
    local top2, bottom2 = lineEnd:GetTop(), lineEnd:GetBottom()

    local geometryValues = { viewLeft, viewBottom, left1, right1, top1, bottom1, left2, right2, top2, bottom2 }
    for index = 1, #geometryValues do
        local value = geometryValues[index]
        if IsUnreadableValue(value) then
            return nil
        end
        if type(value) ~= "number" then
            return false
        end
    end

    local left = math_min(left1, left2)
    local right = math_max(right1, right2)
    local top = math_max(top1, top2)
    local bottom = math_min(bottom1, bottom2)
    local thickness = RefineUI:Scale(TRACK_LINE_BAR_THICKNESS)

    if (right - left) >= (top - bottom) then
        local centerY = (top + bottom) * 0.5
        top = centerY + (thickness * 0.5)
        bottom = centerY - (thickness * 0.5)
    else
        local centerX = (left + right) * 0.5
        left = centerX - (thickness * 0.5)
        right = centerX + (thickness * 0.5)
    end

    barFrame:ClearAllPoints()
    barFrame:SetPoint("TOPLEFT", viewFrame, "BOTTOMLEFT", left - viewLeft, top - viewBottom)
    barFrame:SetPoint("BOTTOMRIGHT", viewFrame, "BOTTOMLEFT", right - viewLeft, bottom - viewBottom)
    return true
end

function EncounterTimeline:InstallTrackLineHooks(viewFrame)
    if not IsTrackView(viewFrame) then
        return
    end
    if self:StateGet(viewFrame, "trackLineHooksInstalled") == true then
        return
    end
    self:StateSet(viewFrame, "trackLineHooksInstalled", true)

    local updateLineHookKey = self:BuildFrameHookKey(viewFrame, "UpdateLineTextures", "TrackLineSkin")
    RefineUI:HookOnce(updateLineHookKey, viewFrame, "UpdateLineTextures", function(frame)
        EncounterTimeline:ApplyTrackLineSkin(frame, true)
    end)

    local updateViewHookKey = self:BuildFrameHookKey(viewFrame, "UpdateView", "TrackLineSkin")
    RefineUI:HookOnce(updateViewHookKey, viewFrame, "UpdateView", function(frame)
        EncounterTimeline:ApplyTrackLineSkin(frame, true)
    end)

    -- Avoid HookScript on Blizzard EncounterWarnings views; those script hooks taint
    -- Edit Mode secret-value paths. Secure method hooks above plus explicit refreshes
    -- cover normal updates.
end

function EncounterTimeline:ApplyTrackLineSkin(viewFrame, force)
    if not IsTrackView(viewFrame) then
        return
    end
    self:InstallTrackLineHooks(viewFrame)

    local token = "TrackLine:" .. tostring(GetStatusbarTexture())
    if not force and self:StateGet(viewFrame, "trackLineSkinToken") == token then
        return
    end

    if not IsFrameShown(viewFrame) then
        local hiddenBar = self:StateGet(viewFrame, "trackLineBar")
        if hiddenBar then
            hiddenBar:Hide()
        end
        self:StateSet(viewFrame, "trackLineSkinToken", token)
        return
    end

    self:HideDefaultTrackLineArt(viewFrame)

    local barFrame = self:EnsureTrackLineBar(viewFrame)
    local fill = self:StateGet(viewFrame, "trackLineFill")
    if fill then
        fill:SetTexture(GetStatusbarTexture())
    end

    local geometryApplied = self:UpdateTrackLineBarGeometry(viewFrame, barFrame)
    if geometryApplied == true then
        barFrame:Show()
        self:StateClear(viewFrame, "trackLineDeferredQueued")
    elseif geometryApplied == false then
        barFrame:Hide()

        if self:StateGet(viewFrame, "trackLineDeferredQueued") ~= true then
            self:StateSet(viewFrame, "trackLineDeferredQueued", true)
            local deferredHookKey = self:BuildFrameHookKey(viewFrame, "DeferredApply", "TrackLineSkin")
            RefineUI:After(deferredHookKey, 0, function()
                EncounterTimeline:StateClear(viewFrame, "trackLineDeferredQueued")
                if IsFrameShown(viewFrame) then
                    EncounterTimeline:ApplyTrackLineSkin(viewFrame, true)
                end
            end)
        end
    else
        self:StateClear(viewFrame, "trackLineDeferredQueued")
    end

    self:StateSet(viewFrame, "trackLineSkinToken", token)
end

----------------------------------------------------------------------------------------
-- Event Frame Skin
----------------------------------------------------------------------------------------
function EncounterTimeline:ApplyTimerEventSkin(eventFrame, eventID, force)
    if not eventFrame or not IsTimerEventFrame(eventFrame) then
        return
    end

    local token = "Timer:" .. tostring(GetStatusbarTexture())
    if not force and self:StateGet(eventFrame, "timerSkinToken") == token then
        self:ApplyEventIconVisualStyling(eventFrame, eventID)
        return
    end

    ApplyIconContainerSkin(eventFrame.IconContainer)
    self:ApplyEventIconVisualStyling(eventFrame, eventID)

    local bar = eventFrame.Bar
    if bar then
        pcall(RefineUI.SetTemplate, bar, "Default")
        pcall(RefineUI.CreateBorder, bar, VIEW_BORDER_INSET, VIEW_BORDER_INSET, EDGE_SIZE)

        local statusbarTexture = GetStatusbarTexture()
        if statusbarTexture and type(bar.SetStatusBarTexture) == "function" then
            bar:SetStatusBarTexture(statusbarTexture)
        end

        if bar.Duration then
            if not IsBlizzardAutoScalingTextElement(bar.Duration) then
                RefineUI.Font(bar.Duration, TIMER_COUNTDOWN_FONT_SIZE, RefineUI.Media.Fonts.Number, "OUTLINE", true)
            end
        end
        if bar.Name then
            if not IsBlizzardAutoScalingTextElement(bar.Name) then
                RefineUI.Font(bar.Name, TIMER_NAME_FONT_SIZE, RefineUI.Media.Fonts.Medium, "OUTLINE", true)
            end
        end
    end

    local iconHookKey = self:BuildFrameHookKey(eventFrame, "UpdateIconBorder", "MaskStyle")
    RefineUI:HookOnce(iconHookKey, eventFrame, "UpdateIconBorder", function(frame)
        local frameEventID = type(frame.GetEventID) == "function" and frame:GetEventID() or nil
        EncounterTimeline:ApplyEventIconVisualStyling(frame, frameEventID)
    end)

    local indicatorHookKey = self:BuildFrameHookKey(eventFrame, "UpdateIndicatorIcons", "SpellTypeIconAnchor")
    RefineUI:HookOnce(indicatorHookKey, eventFrame, "UpdateIndicatorIcons", function(frame)
        EncounterTimeline:ApplySpellTypeIndicatorAnchorOverride(frame)
    end)

    local layoutHookKey = self:BuildFrameHookKey(eventFrame, "UpdateLayout", "SpellTypeIconAnchor")
    RefineUI:HookOnce(layoutHookKey, eventFrame, "UpdateLayout", function(frame)
        EncounterTimeline:ApplySpellTypeIndicatorAnchorOverride(frame)
    end)
    self:ApplySpellTypeIndicatorAnchorOverride(eventFrame)

    self:StateSet(eventFrame, "timerSkinToken", token)
end

function EncounterTimeline:ApplyTrackEventSkin(eventFrame, eventID, force)
    if not eventFrame or not IsTrackEventFrame(eventFrame) then
        return
    end

    local token = "Track:" .. tostring(GetCountdownSwipeTexture())
    if not force and self:StateGet(eventFrame, "trackSkinToken") == token then
        self:EnsureTrackReplacementTextState(eventFrame)
        self:HideBlizzardTrackText(eventFrame)
        self:SyncTrackReplacementText(eventFrame)
        self:ApplyTrackTextAnchorOverride(eventFrame)
        self:ApplyEventIconVisualStyling(eventFrame, eventID)
        return
    end

    ApplyIconContainerSkin(eventFrame.IconContainer)
    self:ApplyEventIconVisualStyling(eventFrame, eventID)

    if eventFrame.Countdown then
        ApplyCooldownSwipeStyle(eventFrame.Countdown)
        ApplyCooldownTextStyle(eventFrame.Countdown, TRACK_COUNTDOWN_FONT_SIZE)
    end

    local replacementNameText, replacementStatusText = self:EnsureTrackReplacementTextState(eventFrame)
    if replacementNameText then
        ApplyTrackTextStyle(replacementNameText, TRACK_NAME_FONT_SIZE)
    end
    if replacementStatusText then
        ApplyTrackTextStyle(replacementStatusText, TRACK_STATUS_FONT_SIZE)
    end
    self:HideBlizzardTrackText(eventFrame)
    self:SyncTrackReplacementText(eventFrame)

    local iconHookKey = self:BuildFrameHookKey(eventFrame, "UpdateBorderStyle", "MaskStyle")
    RefineUI:HookOnce(iconHookKey, eventFrame, "UpdateBorderStyle", function(frame)
        local frameEventID = type(frame.GetEventID) == "function" and frame:GetEventID() or nil
        EncounterTimeline:ApplyEventIconVisualStyling(frame, frameEventID)
    end)

    local iconographyHookKey = self:BuildFrameHookKey(eventFrame, "UpdateIconography", "SpellTypeIconAnchor")
    RefineUI:HookOnce(iconographyHookKey, eventFrame, "UpdateIconography", function(frame)
        EncounterTimeline:ApplySpellTypeIndicatorAnchorOverride(frame)
    end)

    local orientationHookKey = self:BuildFrameHookKey(eventFrame, "UpdateOrientation", "SpellTypeIconAnchor")
    RefineUI:HookOnce(orientationHookKey, eventFrame, "UpdateOrientation", function(frame)
        EncounterTimeline:ApplySpellTypeIndicatorAnchorOverride(frame)
    end)
    self:ApplySpellTypeIndicatorAnchorOverride(eventFrame)

    local nameTextHookKey = self:BuildFrameHookKey(eventFrame, "UpdateNameText", "TrackTextReplacement")
    RefineUI:HookOnce(nameTextHookKey, eventFrame, "UpdateNameText", function(frame)
        EncounterTimeline:HideBlizzardTrackText(frame)
        EncounterTimeline:SyncTrackReplacementText(frame)
        EncounterTimeline:ApplyTrackTextAnchorOverride(frame)
    end)

    local statusTextHookKey = self:BuildFrameHookKey(eventFrame, "UpdateStatusText", "TrackTextReplacement")
    RefineUI:HookOnce(statusTextHookKey, eventFrame, "UpdateStatusText", function(frame)
        EncounterTimeline:HideBlizzardTrackText(frame)
        EncounterTimeline:SyncTrackReplacementText(frame)
        EncounterTimeline:ApplyTrackTextAnchorOverride(frame)
    end)

    local textAnchorHookKey = self:BuildFrameHookKey(eventFrame, "UpdateTextAnchors", "TrackTextAnchor")
    RefineUI:HookOnce(textAnchorHookKey, eventFrame, "UpdateTextAnchors", function(frame)
        EncounterTimeline:HideBlizzardTrackText(frame)
        EncounterTimeline:SyncTrackReplacementText(frame)
        EncounterTimeline:ApplyTrackTextAnchorOverride(frame)
    end)
    self:HideBlizzardTrackText(eventFrame)
    self:SyncTrackReplacementText(eventFrame)
    self:ApplyTrackTextAnchorOverride(eventFrame)

    self:StateSet(eventFrame, "trackSkinToken", token)
end

function EncounterTimeline:ApplyEventFrameSkin(viewFrame, eventFrame, eventID, force)
    if not eventFrame then
        return
    end

    if self:IsValidEventID(eventID) then
        self:MapEventFrame(eventID, eventFrame)
    end

    local config = self:GetConfig()
    if config.SkinEnabled ~= true then
        return
    end

    if config.SkinTimerView and IsTimerEventFrame(eventFrame) then
        self:ApplyTimerEventSkin(eventFrame, eventID, force)
    end

    if config.SkinTrackView and IsTrackEventFrame(eventFrame) then
        self:ApplyTrackEventSkin(eventFrame, eventID, force)
    end

end

----------------------------------------------------------------------------------------
-- View Skin
----------------------------------------------------------------------------------------
function EncounterTimeline:ApplyViewEventFrameSkins(viewFrame, force)
    if not viewFrame or type(viewFrame.EnumerateEventFrames) ~= "function" then
        return
    end
    for eventFrame in viewFrame:EnumerateEventFrames() do
        local eventID = type(eventFrame.GetEventID) == "function" and eventFrame:GetEventID() or nil
        self:ApplyEventFrameSkin(viewFrame, eventFrame, eventID, force)
    end
end

function EncounterTimeline:EnsureViewBorderOverlay(viewFrame)
    if not viewFrame then
        return nil
    end

    local overlay = self:StateGet(viewFrame, "viewBorderOverlay")
    if overlay and type(overlay.SetAllPoints) == "function" then
        return overlay
    end

    overlay = CreateFrame("Frame", nil, viewFrame)
    if not overlay then
        return nil
    end

    if overlay.EnableMouse then
        overlay:EnableMouse(false)
    end
    overlay:SetAllPoints(viewFrame)

    self:StateSet(viewFrame, "viewBorderOverlay", overlay)
    return overlay
end

function EncounterTimeline:ApplyViewBorderSkin(viewFrame)
    local overlay = self:EnsureViewBorderOverlay(viewFrame)
    if not overlay then
        return
    end

    -- Intentionally suppress full-view borders; per-event and track-line skins handle borders.
    if overlay.border and overlay.border.Hide then
        overlay.border:Hide()
    end
    if overlay.RefineBorder and overlay.RefineBorder.Hide then
        overlay.RefineBorder:Hide()
    end
end

function EncounterTimeline:ApplyViewSkin(viewFrame, force)
    if not viewFrame then
        return
    end
    local config = self:GetConfig()
    if config.SkinEnabled ~= true then
        return
    end

    local timelineFrame = _G.EncounterTimeline
    if timelineFrame then
        if viewFrame == timelineFrame.TrackView and config.SkinTrackView ~= true then
            return
        end
        if viewFrame == timelineFrame.TimerView and config.SkinTimerView ~= true then
            return
        end
    end

    local token = "ViewSkin"
    if not force and self:StateGet(viewFrame, "viewSkinToken") == token then
        return
    end

    self:ApplyViewBorderSkin(viewFrame)

    if viewFrame.PipText then
        RefineUI.Font(viewFrame.PipText, PIP_TEXT_FONT_SIZE, RefineUI.Media.Fonts.Number, "OUTLINE", true)
    end

    self:StateSet(viewFrame, "viewSkinToken", token)

    if IsTrackView(viewFrame) then
        self:ApplyTrackLineSkin(viewFrame, force)
    end

    if type(viewFrame.UpdateView) == "function" then
        local updateViewHookKey = self:BuildFrameHookKey(viewFrame, "UpdateView", "Skin")
        RefineUI:HookOnce(updateViewHookKey, viewFrame, "UpdateView", function(frame)
            EncounterTimeline:ApplyViewSkin(frame, true)
            EncounterTimeline:ApplyViewEventFrameSkins(frame, true)
        end)
    end

    if type(viewFrame.UpdateLineTextures) == "function" then
        local updateLineHookKey = self:BuildFrameHookKey(viewFrame, "UpdateLineTextures", "Skin")
        RefineUI:HookOnce(updateLineHookKey, viewFrame, "UpdateLineTextures", function(frame)
            EncounterTimeline:ApplyViewSkin(frame, true)
        end)
    end
end

function EncounterTimeline:RefreshTimelineSkins(force)
    local timelineFrame = _G.EncounterTimeline
    if not timelineFrame then
        return
    end

    local config = self:GetConfig()
    if config.SkinEnabled ~= true then
        return
    end

    local timerView = timelineFrame.TimerView
    local trackView = timelineFrame.TrackView

    if config.SkinTimerView and timerView then
        self:ApplyViewSkin(timerView, force)
        self:ApplyViewEventFrameSkins(timerView, force)
    end

    if config.SkinTrackView and trackView then
        self:ApplyViewSkin(trackView, force)
        self:ApplyViewEventFrameSkins(trackView, force)
    end
end

----------------------------------------------------------------------------------------
-- Skin Hooks
----------------------------------------------------------------------------------------
function EncounterTimeline:OnTimelineEventFrameAcquired(viewFrame, eventFrame, eventID, _isNewObject)
    if self:IsValidEventID(eventID) then
        self:MapEventFrame(eventID, eventFrame)
    end

    if viewFrame then
        self:ApplyViewSkin(viewFrame, true)
    end
    self:ApplyEventFrameSkin(viewFrame, eventFrame, eventID, true)
end

function EncounterTimeline:OnTimelineEventFrameReleased(_viewFrame, eventFrame)
    self:CleanupReleasedEventFrame(eventFrame)
end

function EncounterTimeline:OnTimelineViewActivated(viewFrame)
    if not viewFrame then
        return
    end
    self:ApplyViewSkin(viewFrame, true)
    self:ApplyViewEventFrameSkins(viewFrame, true)
end

function EncounterTimeline:InstallSkinHooks()
    if self.skinHooksInstalled then
        return
    end
    if not _G.EventRegistry then
        return
    end

    _G.EventRegistry:RegisterCallback("EncounterTimeline.OnEventFrameAcquired", self.OnTimelineEventFrameAcquired, self)
    _G.EventRegistry:RegisterCallback("EncounterTimeline.OnEventFrameReleased", self.OnTimelineEventFrameReleased, self)
    _G.EventRegistry:RegisterCallback("EncounterTimeline.OnViewActivated", self.OnTimelineViewActivated, self)

    self.skinHooksInstalled = true
end
