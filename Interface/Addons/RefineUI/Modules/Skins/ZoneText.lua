----------------------------------------------------------------------------------------
-- Skins Component: Zone Text
-- Description: Replaces Blizzard's zone banner with a RefineUI-styled announcement.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Skins = RefineUI:GetModule("Skins")
if not Skins then
    return
end

----------------------------------------------------------------------------------------
-- WoW Globals (Upvalues)
----------------------------------------------------------------------------------------
local C_PvP = C_PvP
local CreateFrame = CreateFrame
local GetInstanceInfo = GetInstanceInfo
local GetMinimapZoneText = GetMinimapZoneText
local GetRealZoneText = GetRealZoneText
local GetSubZoneText = GetSubZoneText
local GetTime = GetTime
local GetZoneText = GetZoneText
local UIParent = UIParent
local _G = _G
local format = format
local hooksecurefunc = hooksecurefunc

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local COMPONENT_KEY = "Skins:ZoneText"

local EVENT_KEY = {
    LOADING_SCREEN_DISABLED = COMPONENT_KEY .. ":LOADING_SCREEN_DISABLED",
    ZONE_CHANGED = COMPONENT_KEY .. ":ZONE_CHANGED",
    ZONE_CHANGED_INDOORS = COMPONENT_KEY .. ":ZONE_CHANGED_INDOORS",
    ZONE_CHANGED_NEW_AREA = COMPONENT_KEY .. ":ZONE_CHANGED_NEW_AREA",
}

local HOLD_TIME = 1.75
local FADE_TIME = 1.5
local REPEAT_WINDOW = 1
local DIVIDER_REVEAL_TIME = 0.35
local TEXT_IN_TIME = 0.3
local SUBTEXT_DELAY = 0.15
local TEXT_RISE = 8

local DIVIDER_ATLAS = "QuestLog-header-glow-yellow"
local DIVIDER_WIDTH = 307
local DIVIDER_HEIGHT = 20
local DIVIDER_OFFSET_Y = 6

local ZONE_FONT_SIZE = 32
local SUBZONE_FONT_SIZE = 18
local DIFFICULTY_FONT_SIZE = 14
local ANCHOR_HEIGHT_PERCENT = 0.8
local LINE_SPACING = -5

-- Matches Blizzard's SetZoneText colors.
local HOSTILE_COLOR = { 1.0, 0.1, 0.1 }
local DEFAULT_ZONE_COLOR = { 1.0, 0.9294, 0.7607 }
local ZONE_COLORS = {
    sanctuary = { 0.41, 0.8, 0.94 },
    arena = HOSTILE_COLOR,
    friendly = { 0.1, 1.0, 0.1 },
    hostile = HOSTILE_COLOR,
    contested = { 1.0, 0.7, 0.0 },
    combat = HOSTILE_COLOR,
}

----------------------------------------------------------------------------------------
-- Locals
----------------------------------------------------------------------------------------
local announcementFrame
local fadeAnimation
local introAnimation
local zoneText
local divider
local subZoneText
local difficultyText
local lastZone, lastSubZone, lastDifficulty
local lastAnnouncementTime = 0

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------

local function GetDifficulty()
    local _, _, _, difficultyName, maxPlayers = GetInstanceInfo()
    if not difficultyName or difficultyName == "" then
        return ""
    end

    if maxPlayers > 0 then
        return format("%s (%d player)", difficultyName, maxPlayers)
    end

    return difficultyName
end

local function HideAnnouncement()
    fadeAnimation:Stop()
    introAnimation:Stop()
    announcementFrame:Hide()
end

local function AddTextFadeIn(target, delay)
    local fadeIn = introAnimation:CreateAnimation("Alpha")
    fadeIn:SetTarget(target)
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetStartDelay(delay)
    fadeIn:SetDuration(TEXT_IN_TIME)
end

local function CreateAnnouncementFrame()
    local font = RefineUI.Media.Fonts.Default

    announcementFrame = CreateFrame("Frame", "RefineUI_ZoneAnnouncement", UIParent)
    announcementFrame:SetSize(512, 128)
    announcementFrame:SetFrameStrata("TOOLTIP")
    announcementFrame:SetFrameLevel(10)
    announcementFrame:Hide()

    fadeAnimation = announcementFrame:CreateAnimationGroup()
    local fade = fadeAnimation:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetStartDelay(HOLD_TIME)
    fade:SetDuration(FADE_TIME)
    fadeAnimation:SetScript("OnFinished", function()
        announcementFrame:Hide()
    end)

    zoneText = announcementFrame:CreateFontString(nil, "OVERLAY")
    zoneText:SetPoint("CENTER", announcementFrame, "CENTER", 0, 0)
    zoneText:SetJustifyH("CENTER")
    zoneText:SetFont(font, RefineUI:Scale(ZONE_FONT_SIZE), "OUTLINE")

    divider = announcementFrame:CreateTexture(nil, "ARTWORK")
    divider:SetAtlas(DIVIDER_ATLAS)
    divider:SetDesaturated(true)
    divider:SetSize(RefineUI:Scale(DIVIDER_WIDTH), RefineUI:Scale(DIVIDER_HEIGHT))
    divider:SetPoint("TOP", zoneText, "BOTTOM", 0, RefineUI:Scale(DIVIDER_OFFSET_Y))

    -- Draws the divider outward from its center while the text holds.
    local reveal = fadeAnimation:CreateAnimation("Scale")
    reveal:SetTarget(divider)
    reveal:SetScaleFrom(0, 1)
    reveal:SetScaleTo(1, 1)
    reveal:SetDuration(DIVIDER_REVEAL_TIME)
    reveal:SetSmoothing("OUT")

    subZoneText = announcementFrame:CreateFontString(nil, "OVERLAY")
    subZoneText:SetPoint("TOP", divider, "BOTTOM", 0, RefineUI:Scale(LINE_SPACING))
    subZoneText:SetJustifyH("CENTER")
    subZoneText:SetFont(font, RefineUI:Scale(SUBZONE_FONT_SIZE), "OUTLINE")
    subZoneText:SetTextColor(0.8, 0.8, 0.8)

    difficultyText = announcementFrame:CreateFontString(nil, "OVERLAY")
    difficultyText:SetJustifyH("CENTER")
    difficultyText:SetFont(font, RefineUI:Scale(DIFFICULTY_FONT_SIZE), "OUTLINE")
    difficultyText:SetTextColor(0.6, 0.6, 0.6)

    -- Text alphas start at 0 each show and keep their final value, so start delays
    -- stay hidden until their fade-in begins.
    introAnimation = announcementFrame:CreateAnimationGroup()
    introAnimation:SetToFinalAlpha(true)

    -- An instant drop below the anchor, then a rise back into place (GroupLootFrame pattern).
    local drop = introAnimation:CreateAnimation("Translation")
    drop:SetTarget(zoneText)
    drop:SetOffset(0, -RefineUI:Scale(TEXT_RISE))
    drop:SetDuration(0)

    local rise = introAnimation:CreateAnimation("Translation")
    rise:SetTarget(zoneText)
    rise:SetOffset(0, RefineUI:Scale(TEXT_RISE))
    rise:SetDuration(TEXT_IN_TIME)
    rise:SetSmoothing("OUT")

    AddTextFadeIn(zoneText, 0)
    AddTextFadeIn(subZoneText, SUBTEXT_DELAY)
    AddTextFadeIn(difficultyText, SUBTEXT_DELAY)
end

local function ShowAnnouncement(force)
    -- Blizzard skips zone text while an event toast owns the top of the screen.
    if _G.EventToastManagerFrame:IsCurrentlyToasting() then
        return
    end

    local zone = GetRealZoneText() or ""
    if zone == "" then
        zone = GetZoneText() or ""
    end
    if zone == "" then
        return
    end

    local subzone = GetSubZoneText() or ""
    if subzone == "" then
        subzone = GetMinimapZoneText() or ""
    end
    if subzone == zone then
        subzone = ""
    end

    local difficulty = GetDifficulty()
    local now = GetTime()
    if not force
        and zone == lastZone and subzone == lastSubZone and difficulty == lastDifficulty
        and (now - lastAnnouncementTime) < REPEAT_WINDOW then
        return
    end

    lastZone, lastSubZone, lastDifficulty = zone, subzone, difficulty
    lastAnnouncementTime = now

    local color = ZONE_COLORS[C_PvP.GetZonePVPInfo()] or DEFAULT_ZONE_COLOR
    local r, g, b = color[1], color[2], color[3]
    zoneText:SetText(zone)
    zoneText:SetTextColor(r, g, b)
    divider:SetVertexColor(r, g, b)
    subZoneText:SetText(subzone)
    difficultyText:SetText(difficulty)

    difficultyText:ClearAllPoints()
    difficultyText:SetPoint("TOP", subzone ~= "" and subZoneText or divider, "BOTTOM", 0, RefineUI:Scale(LINE_SPACING))

    fadeAnimation:Stop()
    introAnimation:Stop()
    zoneText:SetAlpha(0)
    subZoneText:SetAlpha(0)
    difficultyText:SetAlpha(0)
    -- Re-anchored per show so it follows resolution and UI scale changes.
    announcementFrame:SetPoint("CENTER", UIParent, "BOTTOM", 0, UIParent:GetHeight() * ANCHOR_HEIGHT_PERCENT)
    announcementFrame:Show()
    fadeAnimation:Play()
    introAnimation:Play()
end

local function OnZoneEvent(event)
    -- LOADING_SCREEN_DISABLED covers login, reload, and every zone transfer; any
    -- announcement started behind the loading screen is restarted here.
    ShowAnnouncement(event ~= "ZONE_CHANGED" and event ~= "ZONE_CHANGED_INDOORS")
end

----------------------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------------------

function Skins:SetupZoneTextSkin()
    local zoneFrame = _G.ZoneTextFrame

    -- ZoneTextFrame owns the zone events and is the only thing that shows either banner.
    zoneFrame:UnregisterEvent("ZONE_CHANGED")
    zoneFrame:UnregisterEvent("ZONE_CHANGED_INDOORS")
    zoneFrame:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
    zoneFrame:Hide()
    _G.SubZoneTextFrame:Hide()

    CreateAnnouncementFrame()

    -- Blizzard clears zone text for center-screen banners (bonus objectives, PvP) and
    -- hides ZoneTextFrame when an event toast animates in; follow both.
    hooksecurefunc("ZoneText_Clear", HideAnnouncement)
    hooksecurefunc(zoneFrame, "Hide", HideAnnouncement)

    RefineUI:RegisterEventCallback("LOADING_SCREEN_DISABLED", OnZoneEvent, EVENT_KEY.LOADING_SCREEN_DISABLED)
    RefineUI:RegisterEventCallback("ZONE_CHANGED", OnZoneEvent, EVENT_KEY.ZONE_CHANGED)
    RefineUI:RegisterEventCallback("ZONE_CHANGED_INDOORS", OnZoneEvent, EVENT_KEY.ZONE_CHANGED_INDOORS)
    RefineUI:RegisterEventCallback("ZONE_CHANGED_NEW_AREA", OnZoneEvent, EVENT_KEY.ZONE_CHANGED_NEW_AREA)
end
