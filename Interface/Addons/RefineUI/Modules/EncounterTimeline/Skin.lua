----------------------------------------------------------------------------------------
-- EncounterTimeline Component: Skin
-- Description: Timeline view/event-frame skinning and border/icon styling
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local EncounterTimeline = RefineUI:GetModule("EncounterTimeline")

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local AnchorUtil = AnchorUtil
local CreateFrame = CreateFrame
local EventRegistry = EventRegistry
local GridLayoutMixin = GridLayoutMixin
local hooksecurefunc = hooksecurefunc
local issecretvalue = issecretvalue
local math_max = math.max
local math_min = math.min
local setmetatable = setmetatable

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local BAR_BORDER_INSET = 6
local EDGE_SIZE = 12
local TRACK_LINE_BAR_THICKNESS = 8
local TRACK_LINE_ALPHA = 0.5
local TRACK_LINE_FRAME_LEVEL_OFFSET = -2
local TRACK_LINE_RETRY_KEY = "EncounterTimeline:TrackLineRetry"
local TRACK_COUNTDOWN_FONT_SIZE = 22
local TIMER_COUNTDOWN_FONT_SIZE = 18
local TIMER_NAME_FONT_SIZE = 12
local TRACK_NAME_FONT_SIZE = 11
local TRACK_STATUS_FONT_SIZE = 10
local PIP_TEXT_FONT_SIZE = 14
local TRACK_TEXT_ANCHOR_OFFSET = 10
local TRACK_TEXT_WIDTH = 200
-- Blizzard raises IconContainer by up to 30 levels from a secret severity, so its level is secret.
local ICON_MAX_LEVEL_OFFSET = 30
local TRACK_TEXT_LEVEL_OFFSET = ICON_MAX_LEVEL_OFFSET + 20
local INDICATOR_LEVEL_OFFSET = ICON_MAX_LEVEL_OFFSET + 13
local SPELL_TYPE_ICON_ANCHOR_OFFSET_Y = -6
local SPELL_TYPE_ICON_SPACING = 2
local ICON_TEXCOORD_MIN = 0.08
local ICON_TEXCOORD_MAX = 0.92
local ICON_BORDER_SUBLEVEL = -8

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
local skinnedFrames = setmetatable({}, { __mode = "k" })
local trackTexts = setmetatable({}, { __mode = "k" })
local visibleIndicators = {}
local trackLineBar

----------------------------------------------------------------------------------------
-- Indicators
----------------------------------------------------------------------------------------
local function ElevateIndicatorTextures(indicatorContainer)
    local roleIndicators = indicatorContainer.RoleIndicators
    for index = 1, #roleIndicators do
        roleIndicators[index]:SetDrawLayer("OVERLAY", 7)
    end

    local otherIndicators = indicatorContainer.OtherIndicators
    for index = 1, #otherIndicators do
        otherIndicators[index]:SetDrawLayer("OVERLAY", 7)
    end
end

local function RaiseIndicatorContainer(eventFrame, indicatorContainer)
    indicatorContainer:SetFrameLevel(eventFrame:GetFrameLevel() + INDICATOR_LEVEL_OFFSET)
end

-- Indicator art becomes secret during encounters; only readable, populated textures are re-anchored.
local function IsRenderableIndicator(texture)
    local shown = texture:IsShown()
    if not issecretvalue(shown) and not shown then
        return false
    end

    local atlas = texture:GetAtlas()
    if not issecretvalue(atlas) and atlas and atlas ~= "" then
        return true
    end

    local file = texture:GetTexture()
    return not issecretvalue(file) and file ~= nil
end

local function CollectVisibleIndicators(textureList, count)
    for index = 1, #textureList do
        local texture = textureList[index]
        if IsRenderableIndicator(texture) then
            count = count + 1
            visibleIndicators[count] = texture
        end
    end
    return count
end

local function AnchorTimerIndicators(eventFrame)
    local indicatorContainer = eventFrame.IndicatorContainer
    RaiseIndicatorContainer(eventFrame, indicatorContainer)

    local count = CollectVisibleIndicators(indicatorContainer.RoleIndicators, 0)
    count = CollectVisibleIndicators(indicatorContainer.OtherIndicators, count)
    if count == 0 then
        return
    end

    local iconFrame = eventFrame.IconContainer
    local growRightToLeft = eventFrame:ShouldFlipHorizontally()
    local first = visibleIndicators[1]
    first:ClearAllPoints()
    if growRightToLeft then
        first:SetPoint("BOTTOMRIGHT", iconFrame, "TOPRIGHT", 0, SPELL_TYPE_ICON_ANCHOR_OFFSET_Y)
    else
        first:SetPoint("BOTTOMLEFT", iconFrame, "TOPLEFT", 0, SPELL_TYPE_ICON_ANCHOR_OFFSET_Y)
    end

    for index = 2, count do
        local texture = visibleIndicators[index]
        texture:ClearAllPoints()
        if growRightToLeft then
            texture:SetPoint("RIGHT", visibleIndicators[index - 1], "LEFT", -SPELL_TYPE_ICON_SPACING, 0)
        else
            texture:SetPoint("LEFT", visibleIndicators[index - 1], "RIGHT", SPELL_TYPE_ICON_SPACING, 0)
        end
    end
end

-- Right-anchored track text takes the icon's right side, so indicators move to the left.
local function AnchorTrackIndicators(eventFrame)
    if EncounterTimeline:GetConfig().TrackTextAnchor ~= "RIGHT" or not eventFrame:GetTrackOrientation():IsVertical() then
        return
    end

    local indicatorContainer = eventFrame.Indicators
    RaiseIndicatorContainer(eventFrame, indicatorContainer)
    indicatorContainer:ClearAllPoints()
    indicatorContainer:SetPoint("RIGHT", eventFrame.IconContainer, "LEFT")

    local initialAnchor = AnchorUtil.CreateAnchor("TOPRIGHT", indicatorContainer, "TOPRIGHT", 0, 2)
    indicatorContainer:ApplyLayout(initialAnchor, GridLayoutMixin.Direction.TopRightToBottomLeft, 0, 2, 19, 16)
end

----------------------------------------------------------------------------------------
-- Track Text
----------------------------------------------------------------------------------------
-- Blizzard's track text uses AutoScalingFontStringMixin, so RefineUI mirrors it into its own font strings.
local function CreateTrackText(parent, fontSize)
    local text = parent:CreateFontString(nil, "OVERLAY", nil, 7)
    text:SetJustifyV("MIDDLE")
    text:SetWordWrap(false)
    text:SetWidth(TRACK_TEXT_WIDTH)
    RefineUI.Font(text, fontSize, RefineUI.Media.Fonts.Medium, "OUTLINE", true)
    text:SetTextColor(1, 1, 1)
    return text
end

local function GetTrackTexts(eventFrame)
    local texts = trackTexts[eventFrame]
    if not texts then
        local overlay = CreateFrame("Frame", nil, eventFrame)
        overlay:SetAllPoints(eventFrame)
        texts = {
            Overlay = overlay,
            Name = CreateTrackText(overlay, TRACK_NAME_FONT_SIZE),
            Status = CreateTrackText(overlay, TRACK_STATUS_FONT_SIZE),
        }
        trackTexts[eventFrame] = texts
    end
    return texts
end

local function SyncTrackText(eventFrame)
    local texts = GetTrackTexts(eventFrame)
    local showText = eventFrame:ShouldShowText() and eventFrame:GetTrackOrientation():IsVertical()
    texts.Overlay:SetShown(showText)
    if not showText then
        return
    end

    -- Alpha 0 on the native text gets reset to 1 in-game (not by timeline Lua), so hide it instead.
    -- Blizzard only re-shows it in UpdateNameText/UpdateStatusText, which always lead to this UpdateTextLayout hook.
    eventFrame.NameText:Hide()
    eventFrame.StatusText:Hide()

    texts.Overlay:SetFrameLevel(eventFrame:GetFrameLevel() + TRACK_TEXT_LEVEL_OFFSET)

    local nameText, statusText = texts.Name, texts.Status
    local eventInfo = eventFrame:GetEventInfo()
    local status = eventFrame:GetAppropriateStatusText()
    nameText:SetText(eventInfo and eventInfo.spellName)
    statusText:SetText(status)
    statusText:SetShown(status ~= nil)

    local offsetX = TRACK_TEXT_ANCHOR_OFFSET * eventFrame:GetIconScale()
    local justify, namePoint, statusPoint, singlePoint, framePoint = "LEFT", "BOTTOMLEFT", "TOPLEFT", "LEFT", "RIGHT"
    if EncounterTimeline:GetConfig().TrackTextAnchor == "LEFT" then
        offsetX = -offsetX
        justify, namePoint, statusPoint, singlePoint, framePoint = "RIGHT", "BOTTOMRIGHT", "TOPRIGHT", "RIGHT", "LEFT"
    end

    nameText:SetJustifyH(justify)
    statusText:SetJustifyH(justify)
    nameText:ClearAllPoints()
    statusText:ClearAllPoints()
    if status then
        nameText:SetPoint(namePoint, eventFrame, framePoint, offsetX, 2)
        statusText:SetPoint(statusPoint, eventFrame, framePoint, offsetX, -2)
    else
        nameText:SetPoint(singlePoint, eventFrame, framePoint, offsetX, 0)
    end
end

----------------------------------------------------------------------------------------
-- Track Line
----------------------------------------------------------------------------------------
local SkinTrackLine

local function RetryTrackLine()
    SkinTrackLine(_G.EncounterTimeline.TrackView)
end

SkinTrackLine = function(viewFrame)
    local viewLeft, viewBottom = viewFrame:GetLeft(), viewFrame:GetBottom()
    local left1, bottom1, width1, height1 = viewFrame.LineStart:GetRect()
    local left2, bottom2, width2, height2 = viewFrame.LineEnd:GetRect()
    if issecretvalue(viewLeft) or issecretvalue(left1) or issecretvalue(left2) then
        return
    end
    if not (viewLeft and viewBottom and left1 and left2) then
        trackLineBar:Hide()
        if viewFrame:IsShown() then
            RefineUI:After(TRACK_LINE_RETRY_KEY, 0, RetryTrackLine)
        end
        return
    end

    local left = math_min(left1, left2)
    local right = math_max(left1 + width1, left2 + width2)
    local bottom = math_min(bottom1, bottom2)
    local top = math_max(bottom1 + height1, bottom2 + height2)
    local halfThickness = RefineUI:Scale(TRACK_LINE_BAR_THICKNESS) * 0.5

    if (right - left) >= (top - bottom) then
        local centerY = (top + bottom) * 0.5
        top, bottom = centerY + halfThickness, centerY - halfThickness
    else
        local centerX = (left + right) * 0.5
        left, right = centerX - halfThickness, centerX + halfThickness
    end

    trackLineBar:ClearAllPoints()
    trackLineBar:SetPoint("TOPLEFT", viewFrame, "BOTTOMLEFT", left - viewLeft, top - viewBottom)
    trackLineBar:SetPoint("BOTTOMRIGHT", viewFrame, "BOTTOMLEFT", right - viewLeft, bottom - viewBottom)
    trackLineBar:Show()
end

local function SkinTrackView(viewFrame)
    RefineUI.Font(viewFrame.PipText, PIP_TEXT_FONT_SIZE, RefineUI.Media.Fonts.Number, "OUTLINE", true)

    viewFrame.LineStart:SetAlpha(0)
    viewFrame.LineEnd:SetAlpha(0)
    viewFrame.LongDivider:SetAlpha(0)
    viewFrame.QueueDivider:SetAlpha(0)
    for _, maskTexture in viewFrame:EnumerateLineBreakMaskTextures() do
        maskTexture:SetAlpha(0)
    end

    trackLineBar = CreateFrame("Frame", nil, viewFrame)
    RefineUI:AddAPI(trackLineBar)
    trackLineBar:SetFrameLevel(math_max(0, viewFrame:GetFrameLevel() + TRACK_LINE_FRAME_LEVEL_OFFSET))
    trackLineBar:SetAlpha(TRACK_LINE_ALPHA)
    RefineUI.SetTemplate(trackLineBar, "Default")
    RefineUI.CreateBorder(trackLineBar, BAR_BORDER_INSET, BAR_BORDER_INSET, EDGE_SIZE)

    local fill = trackLineBar:CreateTexture(nil, "ARTWORK")
    fill:SetAllPoints()
    fill:SetTexture(RefineUI.Media.Textures.Statusbar)
    trackLineBar:Hide()

    -- UpdateView ends with UpdateLineTextures, so one hook covers layout and orientation changes.
    -- Avoid HookScript on these views; script hooks taint Edit Mode secret-value paths.
    hooksecurefunc(viewFrame, "UpdateLineTextures", SkinTrackLine)
    SkinTrackLine(viewFrame)
end

----------------------------------------------------------------------------------------
-- Event Frames
----------------------------------------------------------------------------------------
-- Blizzard's rounded mask and normal overlay ring are replaced by the RefineUI border.
local function SkinIconContainer(iconContainer)
    local icon = iconContainer.IconTexture
    icon:RemoveMaskTexture(iconContainer.IconMask)
    icon:SetTexCoord(ICON_TEXCOORD_MIN, ICON_TEXCOORD_MAX, ICON_TEXCOORD_MIN, ICON_TEXCOORD_MAX)
    iconContainer.NormalOverlay:SetAlpha(0)

    local borderOwner = CreateFrame("Frame", nil, iconContainer)
    borderOwner:SetAllPoints(iconContainer)
    local border = RefineUI.CreateBorder(borderOwner, BAR_BORDER_INSET, BAR_BORDER_INSET, EDGE_SIZE)

    -- A child frame draws above all container regions, so the pieces move onto the container itself:
    -- above the ARTWORK icon, below Blizzard's deadly/paused/queued/highlight OVERLAY effects (sublevel 0+).
    local pieces = border._refineBorderPieces
    for index = 1, #pieces do
        local piece = pieces[index]
        piece:SetParent(iconContainer)
        piece:SetDrawLayer("OVERLAY", ICON_BORDER_SUBLEVEL)
    end
end

local function SkinTrackEventFrame(eventFrame)
    local countdown = eventFrame.Countdown
    countdown:SetSwipeTexture(RefineUI.Media.Textures.CooldownSwipe)
    countdown:SetDrawEdge(false)
    countdown:SetDrawBling(false)
    countdown:SetDrawSwipe(true)
    RefineUI.Font(countdown:GetCountdownFontString(), TRACK_COUNTDOWN_FONT_SIZE, RefineUI.Media.Fonts.Number, "OUTLINE", true)

    SkinIconContainer(eventFrame.IconContainer)
    ElevateIndicatorTextures(eventFrame.Indicators)

    -- Blizzard runs UpdateTextLayout after every name/status change.
    hooksecurefunc(eventFrame, "UpdateTextLayout", SyncTrackText)
    hooksecurefunc(eventFrame, "UpdateIndicatorLayout", AnchorTrackIndicators)
    SyncTrackText(eventFrame)
    AnchorTrackIndicators(eventFrame)
end

local function SkinTimerEventFrame(eventFrame)
    local bar = eventFrame.Bar
    RefineUI.SetTemplate(bar, "Default")
    RefineUI.CreateBorder(bar, BAR_BORDER_INSET, BAR_BORDER_INSET, EDGE_SIZE)
    bar:SetStatusBarTexture(RefineUI.Media.Textures.Statusbar)
    RefineUI.Font(bar.Duration, TIMER_COUNTDOWN_FONT_SIZE, RefineUI.Media.Fonts.Number, "OUTLINE", true)
    RefineUI.Font(bar.Name, TIMER_NAME_FONT_SIZE, RefineUI.Media.Fonts.Medium, "OUTLINE", true)

    SkinIconContainer(eventFrame.IconContainer)
    ElevateIndicatorTextures(eventFrame.IndicatorContainer)

    hooksecurefunc(eventFrame, "UpdateIndicatorIcons", AnchorTimerIndicators)
    hooksecurefunc(eventFrame, "UpdateLayout", AnchorTimerIndicators)
    AnchorTimerIndicators(eventFrame)
end

-- Pooled frames keep their skin and hooks, so each frame is styled once.
local function SkinEventFrame(eventFrame)
    if skinnedFrames[eventFrame] then
        return
    end

    local config = EncounterTimeline:GetConfig()
    if eventFrame.Countdown then
        if not config.SkinTrackView then
            return
        end
        SkinTrackEventFrame(eventFrame)
    elseif eventFrame.Bar then
        if not config.SkinTimerView then
            return
        end
        SkinTimerEventFrame(eventFrame)
    else
        return
    end

    skinnedFrames[eventFrame] = true
end

local function OnEventFrameAcquired(_, viewFrame, eventFrame)
    SkinEventFrame(eventFrame)

    -- Geometry can be unresolved when the line was first skinned while the view was hidden.
    if trackLineBar and viewFrame == trackLineBar:GetParent() and not trackLineBar:IsShown() then
        SkinTrackLine(viewFrame)
    end
end

----------------------------------------------------------------------------------------
-- Public
----------------------------------------------------------------------------------------
function EncounterTimeline:RefreshTrackTextAnchor()
    for eventFrame in _G.EncounterTimeline.TrackView:EnumerateEventFrames() do
        if skinnedFrames[eventFrame] then
            SyncTrackText(eventFrame)
            AnchorTrackIndicators(eventFrame)
        end
    end
end

function EncounterTimeline:InstallSkin()
    local timelineFrame = _G.EncounterTimeline
    if self:GetConfig().SkinTrackView then
        SkinTrackView(timelineFrame.TrackView)
    end

    EventRegistry:RegisterCallback("EncounterTimeline.OnEventFrameAcquired", OnEventFrameAcquired, self)

    for _, viewFrame in timelineFrame:EnumerateViews() do
        for eventFrame in viewFrame:EnumerateEventFrames() do
            SkinEventFrame(eventFrame)
        end
    end
end
