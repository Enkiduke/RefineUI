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
local AnchorUtil = _G.AnchorUtil
local CreateFrame = CreateFrame
local GridLayoutMixin = _G.GridLayoutMixin
local math_max = math.max
local math_min = math.min
local pcall = pcall
local C_Spell = _G.C_Spell
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
        -- Do not mutate AutoScalingFontStringMixin font objects or scale.
        -- Blizzard's ScaleTextToFit math can receive secret values here.
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

local function CreateTrackReplacementText(parentFrame, drawLayerSubLevel)
    if not parentFrame or type(parentFrame.CreateFontString) ~= "function" then
        return nil
    end

    local text = parentFrame:CreateFontString(nil, "OVERLAY")
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
    if type(text.SetWidth) == "function" then
        pcall(text.SetWidth, text, 200)
    end
    if type(text.Hide) == "function" then
        text:Hide()
    end

    return text
end

local function EnsureTrackTextOverlayFrame(eventFrame, parentFrame, state)
    if not eventFrame or not parentFrame then
        return nil
    end

    local overlayFrame = state.TextOverlayFrame
    if not overlayFrame or type(overlayFrame.GetParent) ~= "function" or overlayFrame:GetParent() ~= parentFrame then
        overlayFrame = CreateFrame("Frame", nil, parentFrame)
        overlayFrame:SetAllPoints(parentFrame)
        overlayFrame:EnableMouse(false)
        state.TextOverlayFrame = overlayFrame
    end

    local anchorFrame = eventFrame.IconContainer or eventFrame
    local frameStrata = GetSafeFrameStrata(anchorFrame, "MEDIUM")
    local frameLevel = math_max(0, GetSafeFrameLevel(anchorFrame, 0) + 20)

    if type(overlayFrame.SetFrameStrata) == "function" then
        pcall(overlayFrame.SetFrameStrata, overlayFrame, frameStrata)
    end
    if type(overlayFrame.SetFrameLevel) == "function" then
        pcall(overlayFrame.SetFrameLevel, overlayFrame, frameLevel)
    end

    return overlayFrame
end

function EncounterTimeline:EnsureTrackReplacementTextState(eventFrame)
    if not eventFrame or not IsTrackEventFrame(eventFrame) then
        return nil, nil
    end

    local textParent = eventFrame:GetParent() or eventFrame
    local state = self:StateGet(eventFrame, "trackReplacementTextState")
    if type(state) ~= "table" then
        state = {}
        self:StateSet(eventFrame, "trackReplacementTextState", state)
    end

    local overlayParent = EnsureTrackTextOverlayFrame(eventFrame, textParent, state)
    if not overlayParent then
        return nil, nil
    end

    local nameText = state.NameText
    if not nameText or type(nameText.GetParent) ~= "function" or nameText:GetParent() ~= overlayParent then
        nameText = CreateTrackReplacementText(overlayParent, 7)
        state.NameText = nameText
        ApplyTrackTextStyle(nameText, TRACK_NAME_FONT_SIZE)
    end

    local statusText = state.StatusText
    if not statusText or type(statusText.GetParent) ~= "function" or statusText:GetParent() ~= overlayParent then
        statusText = CreateTrackReplacementText(overlayParent, 7)
        state.StatusText = statusText
        ApplyTrackTextStyle(statusText, TRACK_STATUS_FONT_SIZE)
    end

    return nameText, statusText
end

local function RestoreBlizzardTrackText(fontString)
    if not fontString then
        return
    end

    if type(fontString.SetAlpha) == "function" then
        pcall(fontString.SetAlpha, fontString, 1)
    end
end

function EncounterTimeline:RestoreBlizzardTrackText(eventFrame)
    if not eventFrame then
        return
    end

    RestoreBlizzardTrackText(eventFrame.NameText)
    RestoreBlizzardTrackText(eventFrame.StatusText)
end

local function SuppressBlizzardTrackText(fontString)
    if not fontString then
        return
    end

    if type(fontString.SetAlpha) == "function" then
        pcall(fontString.SetAlpha, fontString, 0)
    end
end

function EncounterTimeline:HideBlizzardTrackText(eventFrame)
    if not eventFrame then
        return
    end

    SuppressBlizzardTrackText(eventFrame.NameText)
    SuppressBlizzardTrackText(eventFrame.StatusText)
end

local function GetTrackDisplayTextElements(eventFrame)
    if not eventFrame then
        return nil, nil
    end

    if IsTrackEventFrame(eventFrame) then
        local config = EncounterTimeline:GetConfig()
        if config.SkinEnabled == true and config.SkinTrackView == true then
            local nameText, statusText = EncounterTimeline:EnsureTrackReplacementTextState(eventFrame)
            if nameText and statusText then
                return nameText, statusText
            end
        end
    end

    return eventFrame.NameText, eventFrame.StatusText
end

local function ResolveSpellNameFromSpellID(spellID)
    if not EncounterTimeline:IsNonSecretNumber(spellID) then
        return nil
    end
    if not C_Spell or type(C_Spell.GetSpellName) ~= "function" then
        return nil
    end

    local okResolvedName, resolvedName = pcall(C_Spell.GetSpellName, spellID)
    if not okResolvedName or IsUnreadableValue(resolvedName) or type(resolvedName) ~= "string" or resolvedName == "" then
        return nil
    end

    return resolvedName
end

local function ResolveTrackSpellName(eventID)
    local metadata = EncounterTimeline:IsValidEventID(eventID) and EncounterTimeline:GetEventMetadata(eventID) or nil
    if type(metadata) ~= "table" then
        return nil
    end

    if metadata.trackDisplayName ~= nil then
        return metadata.trackDisplayName
    end
    if type(metadata.overrideName) == "string" and metadata.overrideName ~= "" then
        return metadata.overrideName
    end

    local resolved = ResolveSpellNameFromSpellID(metadata.spellID)
    if resolved then
        return resolved
    end

    return nil
end

local function ApplyTrackReplacementTextColor(nameText, eventFrame, eventID)
    if not nameText or type(nameText.SetTextColor) ~= "function" then
        return
    end

    local metadata = EncounterTimeline:IsValidEventID(eventID) and EncounterTimeline:GetEventMetadata(eventID) or nil
    if type(metadata) ~= "table" then
        pcall(nameText.SetTextColor, nameText, 1, 1, 1)
        return
    end

    local r = metadata.trackTextColorR
    local g = metadata.trackTextColorG
    local b = metadata.trackTextColorB
    if type(r) == "number" and type(g) == "number" and type(b) == "number"
        and not IsUnreadableValue(r) and not IsUnreadableValue(g) and not IsUnreadableValue(b) then
        pcall(nameText.SetTextColor, nameText, r, g, b)
    else
        pcall(nameText.SetTextColor, nameText, 1, 1, 1)
    end
end

local function ShouldShowMirroredTrackText(eventFrame)
    if not eventFrame or not IsTrackEventFrame(eventFrame) then
        return false
    end

    local showText = true
    if type(eventFrame.ShouldShowText) == "function" then
        local okShowText, value = pcall(eventFrame.ShouldShowText, eventFrame)
        if okShowText and not IsUnreadableValue(value) and type(value) == "boolean" then
            showText = value
        end
    end
    if not showText then
        return false
    end

    local orientation = type(eventFrame.GetTrackOrientation) == "function" and eventFrame:GetTrackOrientation() or nil
    if not orientation or type(orientation.IsVertical) ~= "function" or not orientation:IsVertical() then
        return false
    end

    return true
end

local function BuildTrackStatusText(eventFrame)
    if not eventFrame then
        return ""
    end

    local okState, eventState = pcall(eventFrame.GetEventState, eventFrame)
    if not okState or IsUnreadableValue(eventState) then
        eventState = nil
    end

    local okBlocked, blocked = pcall(eventFrame.IsEventBlocked, eventFrame)
    if not okBlocked or IsUnreadableValue(blocked) then
        blocked = false
    end

    local track = nil
    local okTrack, eventTrack = pcall(eventFrame.GetEventTrack, eventFrame)
    if okTrack and not IsUnreadableValue(eventTrack) then
        track = eventTrack
    end

    if eventState == Enum.EncounterTimelineEventState.Paused then
        return COMBAT_WARNINGS_EVENT_STATUS_PAUSED or ""
    end
    if blocked == true then
        return COMBAT_WARNINGS_EVENT_STATUS_BLOCKED or ""
    end
    if track == Enum.EncounterTimelineTrack.Queued then
        return COMBAT_WARNINGS_EVENT_STATUS_QUEUED or ""
    end

    return ""
end

local function ResolveTrackReplacementPresentation(eventFrame)
    local eventID = type(eventFrame.GetEventID) == "function" and eventFrame:GetEventID() or nil
    local showMirroredText = ShouldShowMirroredTrackText(eventFrame)
    local nameValue = ResolveTrackSpellName(eventID)
    local statusValue = BuildTrackStatusText(eventFrame)

    local showName = showMirroredText
    local showStatus = showMirroredText and statusValue ~= ""

    return eventID, nameValue, statusValue, showName, showStatus, showMirroredText
end

function EncounterTimeline:UpdateTrackNativeTextVisibility(eventFrame, replacementActive)
    if replacementActive == true then
        self:HideBlizzardTrackText(eventFrame)
    else
        self:RestoreBlizzardTrackText(eventFrame)
    end
end

function EncounterTimeline:SyncTrackReplacementText(eventFrame)
    if not eventFrame or not IsTrackEventFrame(eventFrame) then
        return
    end

    local nameReplacement, statusReplacement = self:EnsureTrackReplacementTextState(eventFrame)
    if not nameReplacement or not statusReplacement then
        return
    end

    local eventID, nameValue, statusValue, showName, showStatus, showMirroredText = ResolveTrackReplacementPresentation(eventFrame)
    local state = self:StateGet(eventFrame, "trackReplacementTextState")
    local replacementActive = showMirroredText

    if type(state) == "table" then
        state.Active = replacementActive
        if state.TextOverlayFrame and type(state.TextOverlayFrame.SetShown) == "function" then
            pcall(state.TextOverlayFrame.SetShown, state.TextOverlayFrame, replacementActive)
        end
    end

    self:UpdateTrackNativeTextVisibility(eventFrame, replacementActive)

    if showName then
        RefineUI:SetFontStringValue(nameReplacement, nameValue, { emptyText = "" })
        ApplyTrackReplacementTextColor(nameReplacement, eventFrame, eventID)
        pcall(nameReplacement.SetAlpha, nameReplacement, 1)
        nameReplacement:Show()
    else
        nameReplacement:Hide()
    end

    if showStatus then
        RefineUI:SetFontStringValue(statusReplacement, statusValue, { emptyText = "" })
        ApplyTrackReplacementTextColor(statusReplacement, eventFrame, eventID)
        pcall(statusReplacement.SetAlpha, statusReplacement, 1)
        statusReplacement:Show()
    else
        statusReplacement:Hide()
    end
end

function EncounterTimeline:CleanupTrackReplacementText(eventFrame)
    if not eventFrame then
        return
    end

    local state = self:StateGet(eventFrame, "trackReplacementTextState")
    if type(state) ~= "table" then
        return
    end

    if state.NameText and type(state.NameText.Hide) == "function" then
        state.NameText:Hide()
    end
    if state.StatusText and type(state.StatusText.Hide) == "function" then
        state.StatusText:Hide()
    end
    if state.TextOverlayFrame and type(state.TextOverlayFrame.Hide) == "function" then
        state.TextOverlayFrame:Hide()
    end
    state.Active = false
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
        if okAtlas and not IsUnreadableValue(atlas) and type(atlas) == "string" and atlas ~= "" then
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

local function SetTrackNativeIndicatorAlpha(indicatorContainer, alphaValue)
    if not indicatorContainer or type(indicatorContainer.SetAlpha) ~= "function" then
        return
    end

    pcall(indicatorContainer.SetAlpha, indicatorContainer, alphaValue)
end

function EncounterTimeline:RestoreTrackNativeIndicators(eventFrame)
    if not eventFrame then
        return
    end

    local indicatorContainer = eventFrame.Indicators or eventFrame.IndicatorContainer
    SetTrackNativeIndicatorAlpha(indicatorContainer, 1)
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

function EncounterTimeline:ApplyTrackTextAnchorOverride(eventFrame)
    if not eventFrame or not IsTrackEventFrame(eventFrame) then
        return
    end

    local nameText, statusText = GetTrackDisplayTextElements(eventFrame)
    if not nameText or not statusText then
        return
    end

    local config = self:GetConfig()
    local desiredAnchor = config.TrackTextAnchor or self.TRACK_TEXT_ANCHOR.RIGHT

    local iconScale = (type(eventFrame.GetIconScale) == "function" and eventFrame:GetIconScale()) or 1
    if IsUnreadableValue(iconScale) or type(iconScale) ~= "number" then
        iconScale = 1
    end

    local okOffset, scaledOffset = pcall(function()
        return TRACK_TEXT_ANCHOR_OFFSET * iconScale
    end)
    local offset = (okOffset and type(scaledOffset) == "number") and scaledOffset or TRACK_TEXT_ANCHOR_OFFSET
    local offsetX = offset
    local justify = "LEFT"
    local namePoint = "BOTTOMLEFT"
    local statusPoint = "TOPLEFT"
    local framePoint = "RIGHT"
    local relativePoint = "LEFT"

    if desiredAnchor == self.TRACK_TEXT_ANCHOR.LEFT then
        offsetX = -offset
        justify = "RIGHT"
        namePoint = "BOTTOMRIGHT"
        statusPoint = "TOPRIGHT"
        framePoint = "LEFT"
        relativePoint = "RIGHT"
    end

    if type(nameText.SetJustifyH) == "function" then
        nameText:SetJustifyH(justify)
    end
    if type(statusText.SetJustifyH) == "function" then
        statusText:SetJustifyH(justify)
    end

    nameText:ClearAllPoints()
    statusText:ClearAllPoints()

    if GetShownState(nameText) ~= false and GetShownState(statusText) ~= false then
        nameText:SetPoint(namePoint, eventFrame, framePoint, offsetX, 2)
        statusText:SetPoint(statusPoint, eventFrame, framePoint, offsetX, -2)
    elseif GetShownState(nameText) ~= false then
        nameText:SetPoint(relativePoint, eventFrame, framePoint, offsetX, 0)
    elseif GetShownState(statusText) ~= false then
        statusText:SetPoint(relativePoint, eventFrame, framePoint, offsetX, 0)
    end
end

function EncounterTimeline:ApplyTrackIndicatorAnchorOverride(eventFrame)
    if not eventFrame or not IsTrackEventFrame(eventFrame) then
        return
    end

    local iconFrame = eventFrame.IconContainer
    local indicatorContainer = eventFrame.Indicators or eventFrame.IndicatorContainer
    if not iconFrame or not indicatorContainer then
        return
    end

    local trackOrientation = type(eventFrame.GetTrackOrientation) == "function" and eventFrame:GetTrackOrientation() or nil
    if not trackOrientation or type(trackOrientation.IsVertical) ~= "function" or not trackOrientation:IsVertical() then
        self:RestoreTrackNativeIndicators(eventFrame)
        return
    end

    local config = self:GetConfig()
    local desiredAnchor = config.TrackTextAnchor or self.TRACK_TEXT_ANCHOR.RIGHT
    if desiredAnchor ~= self.TRACK_TEXT_ANCHOR.RIGHT then
        self:RestoreTrackNativeIndicators(eventFrame)
        return
    end

    SetTrackNativeIndicatorAlpha(indicatorContainer, 1)
    ElevateIndicatorLayer(eventFrame, indicatorContainer)

    indicatorContainer:ClearAllPoints()
    indicatorContainer:SetPoint("RIGHT", iconFrame, "LEFT")

    if AnchorUtil and GridLayoutMixin and type(indicatorContainer.ApplyLayout) == "function" then
        local initialAnchor = AnchorUtil.CreateAnchor("TOPRIGHT", indicatorContainer, "TOPRIGHT", 0, 2)
        local layoutDirection = GridLayoutMixin.Direction.TopRightToBottomLeft
        indicatorContainer:ApplyLayout(initialAnchor, layoutDirection, 0, 2, 19, 16)
    end
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

    if IsTrackEventFrame(eventFrame) then
        self:ApplyTrackIndicatorAnchorOverride(eventFrame)
        return
    end

    ElevateIndicatorLayer(eventFrame, indicatorContainer)

    local visibleIndicators = CollectVisibleIndicatorTextures(indicatorContainer)
    if #visibleIndicators == 0 then
        return
    end

    local firstIndicator = visibleIndicators[1]
    local growRightToLeft = false
    local firstPoint = "BOTTOMLEFT"
    local firstRelativePoint = "TOPLEFT"
    local firstOffsetX = 0
    local firstOffsetY = SPELL_TYPE_ICON_ANCHOR_OFFSET_Y

    if type(eventFrame.ShouldFlipHorizontally) == "function" then
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

    self:EnsureTrackReplacementTextState(eventFrame)
    self:SyncTrackReplacementText(eventFrame)

    local token = "Track:" .. tostring(GetCountdownSwipeTexture())
    if not force and self:StateGet(eventFrame, "trackSkinToken") == token then
        self:ApplyTrackTextAnchorOverride(eventFrame)
        self:ApplyTrackIndicatorAnchorOverride(eventFrame)
        self:ApplyEventIconVisualStyling(eventFrame, eventID)
        return
    end

    ApplyIconContainerSkin(eventFrame.IconContainer)
    self:ApplyEventIconVisualStyling(eventFrame, eventID)

    if eventFrame.Countdown then
        ApplyCooldownSwipeStyle(eventFrame.Countdown)
        ApplyCooldownTextStyle(eventFrame.Countdown, TRACK_COUNTDOWN_FONT_SIZE)
    end

    local iconHookKey = self:BuildFrameHookKey(eventFrame, "UpdateBorderStyle", "MaskStyle")
    RefineUI:HookOnce(iconHookKey, eventFrame, "UpdateBorderStyle", function(frame)
        local frameEventID = type(frame.GetEventID) == "function" and frame:GetEventID() or nil
        EncounterTimeline:ApplyEventIconVisualStyling(frame, frameEventID)
    end)

    local orientationHookKey = self:BuildFrameHookKey(eventFrame, "UpdateOrientation", "TrackNativeLayout")
    RefineUI:HookOnce(orientationHookKey, eventFrame, "UpdateOrientation", function(frame)
        EncounterTimeline:SyncTrackReplacementText(frame)
        EncounterTimeline:ApplyTrackIndicatorAnchorOverride(frame)
        EncounterTimeline:ApplyTrackTextAnchorOverride(frame)
    end)

    local statusHookKey = self:BuildFrameHookKey(eventFrame, "UpdateStatusText", "TrackReplacementText")
    RefineUI:HookOnce(statusHookKey, eventFrame, "UpdateStatusText", function(frame)
        EncounterTimeline:SyncTrackReplacementText(frame)
        EncounterTimeline:ApplyTrackTextAnchorOverride(frame)
    end)

    local textAnchorHookKey = self:BuildFrameHookKey(eventFrame, "UpdateTextAnchors", "TrackTextAnchor")
    RefineUI:HookOnce(textAnchorHookKey, eventFrame, "UpdateTextAnchors", function(frame)
        EncounterTimeline:SyncTrackReplacementText(frame)
        EncounterTimeline:ApplyTrackTextAnchorOverride(frame)
    end)

    self:ApplyTrackIndicatorAnchorOverride(eventFrame)
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
    self:CleanupTrackReplacementText(eventFrame)
    self:RestoreBlizzardTrackText(eventFrame)
    self:RestoreTrackNativeIndicators(eventFrame)
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
