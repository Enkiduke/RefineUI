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
local C_Timer = C_Timer
local CreateFrame = CreateFrame
local GetInstanceInfo = GetInstanceInfo
local GetMinimapZoneText = GetMinimapZoneText
local GetRealZoneText = GetRealZoneText
local GetSubZoneText = GetSubZoneText
local GetTime = GetTime
local GetZoneText = GetZoneText
local IsLoggedIn = IsLoggedIn
local UIParent = UIParent
local _G = _G
local format = format
local hooksecurefunc = hooksecurefunc
local max = math.max
local tableConcat = table.concat
local type = type

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local COMPONENT_KEY = "Skins:ZoneText"

local EVENT_KEY = {
    LOADING_SCREEN_DISABLED = COMPONENT_KEY .. ":LOADING_SCREEN_DISABLED",
    PLAYER_ENTERING_WORLD = COMPONENT_KEY .. ":PLAYER_ENTERING_WORLD",
    PLAYER_LEAVING_WORLD = COMPONENT_KEY .. ":PLAYER_LEAVING_WORLD",
    ZONE_CHANGED = COMPONENT_KEY .. ":ZONE_CHANGED",
    ZONE_CHANGED_INDOORS = COMPONENT_KEY .. ":ZONE_CHANGED_INDOORS",
    ZONE_CHANGED_NEW_AREA = COMPONENT_KEY .. ":ZONE_CHANGED_NEW_AREA",
}

local HOOK_KEY = {
    ZONE_FRAME_ON_SHOW = COMPONENT_KEY .. ":ZoneTextFrame:OnShow",
    SUBZONE_FRAME_ON_SHOW = COMPONENT_KEY .. ":SubZoneTextFrame:OnShow",
}

local HOLD_TIME = 1.75
local FADE_TIME = 1.5
local WORLD_ENTRY_DELAY = 0.15
local LOADING_SCREEN_DELAY = 0.05
local RETRY_DELAY = 0.25
local MAX_RETRIES = 8

local ZONE_FONT_SIZE = 32
local SUBZONE_FONT_SIZE = 18
local DIFFICULTY_FONT_SIZE = 14
local ANCHOR_Y = 500
local LINE_SPACING = -5

----------------------------------------------------------------------------------------
-- Locals
----------------------------------------------------------------------------------------
local announcementFrame
local zoneText
local subZoneText
local difficultyText
local holdTimer = 0
local fadeTimer = 0
local pendingRequestId = 0
local lastAnnouncementKey = ""
local lastAnnouncementTime = 0
local pendingStableKey = nil
local pendingStableCount = 0
local transitionSourceKey = nil
local pendingReloadingUI = false
local pendingAnnouncementTimer
local pendingRetryTimer
local blizzardZoneEventsUnregistered = false
local blizzardZoneFrameHooked = false
local blizzardSubZoneFrameHooked = false
local zoneTextClearHooked = false
local zoneTextSkinInitialized = false

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------

local function GetZoneColor()
    local pvpType = C_PvP and C_PvP.GetZonePVPInfo and C_PvP.GetZonePVPInfo()
    if pvpType == "sanctuary" then
        return 0.41, 0.8, 0.94
    elseif pvpType == "arena" then
        return 1.0, 0.1, 0.1
    elseif pvpType == "friendly" then
        return 0.1, 1.0, 0.1
    elseif pvpType == "hostile" then
        return 1.0, 0.1, 0.1
    elseif pvpType == "contested" then
        return 1.0, 0.7, 0.0
    elseif pvpType == "combat" then
        return 1.0, 0.1, 0.1
    end

    return 1.0, 0.9294, 0.7607
end

local function CancelTimer(timerHandle)
    if timerHandle and timerHandle.Cancel then
        timerHandle:Cancel()
    end
end

local function GetDifficulty()
    local _, _, _, difficultyName, maxPlayers = GetInstanceInfo()
    if not difficultyName or difficultyName == "" then
        return nil
    end

    if type(maxPlayers) == "number" and maxPlayers > 0 then
        return format("%s (%d player)", difficultyName, maxPlayers)
    end

    return difficultyName
end

local function IsEventToastActive()
    return _G.EventToastManagerFrame
        and _G.EventToastManagerFrame.IsCurrentlyToasting
        and _G.EventToastManagerFrame:IsCurrentlyToasting()
end

local function ResetPendingState()
    pendingRequestId = pendingRequestId + 1
    pendingStableKey = nil
    pendingStableCount = 0
end

local function HideBlizzardZoneFrame(frame)
    if not frame then return end
    frame:SetAlpha(0)
    frame:Hide()
end

local function SuppressBlizzardZoneText()
    local zoneFrame = _G.ZoneTextFrame
    local subZoneFrame = _G.SubZoneTextFrame

    if zoneFrame and not blizzardZoneEventsUnregistered then
        zoneFrame:UnregisterEvent("ZONE_CHANGED")
        zoneFrame:UnregisterEvent("ZONE_CHANGED_INDOORS")
        zoneFrame:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
        blizzardZoneEventsUnregistered = true
    end

    if zoneFrame and not blizzardZoneFrameHooked then
        RefineUI:HookScriptOnce(HOOK_KEY.ZONE_FRAME_ON_SHOW, zoneFrame, "OnShow", function(self)
            HideBlizzardZoneFrame(self)
        end)
        blizzardZoneFrameHooked = true
    end

    if subZoneFrame and not blizzardSubZoneFrameHooked then
        RefineUI:HookScriptOnce(HOOK_KEY.SUBZONE_FRAME_ON_SHOW, subZoneFrame, "OnShow", function(self)
            HideBlizzardZoneFrame(self)
        end)
        blizzardSubZoneFrameHooked = true
    end

    HideBlizzardZoneFrame(zoneFrame)
    HideBlizzardZoneFrame(subZoneFrame)

    if _G.ZoneTextString then
        _G.ZoneTextString:SetText("")
    end
    if _G.SubZoneTextString then
        _G.SubZoneTextString:SetText("")
    end
    if _G.PVPInfoTextString then
        _G.PVPInfoTextString:SetText("")
    end
    if _G.PVPArenaTextString then
        _G.PVPArenaTextString:SetText("")
    end
end

local function ApplyAnnouncementLayout(hasSubZone)
    if not (zoneText and subZoneText and difficultyText) then
        return
    end

    local spacing = RefineUI:Scale(LINE_SPACING)

    subZoneText:ClearAllPoints()
    subZoneText:SetPoint("TOP", zoneText, "BOTTOM", 0, spacing)

    difficultyText:ClearAllPoints()
    if hasSubZone then
        difficultyText:SetPoint("TOP", subZoneText, "BOTTOM", 0, spacing)
    else
        difficultyText:SetPoint("TOP", zoneText, "BOTTOM", 0, spacing)
    end
end

local function OnAnnouncementUpdate(self, elapsed)
    holdTimer = holdTimer + elapsed

    if holdTimer <= HOLD_TIME then
        return
    end

    fadeTimer = fadeTimer + elapsed
    local alpha = max(0, 1 - (fadeTimer / FADE_TIME))
    self:SetAlpha(alpha)

    if fadeTimer >= FADE_TIME then
        self:Hide()
        self:SetAlpha(0)
    end
end

local function EnsureAnnouncementFrame()
    if announcementFrame then
        return
    end

    announcementFrame = _G.RefineUI_ZoneAnnouncement or CreateFrame("Frame", "RefineUI_ZoneAnnouncement", UIParent)
    announcementFrame:ClearAllPoints()
    announcementFrame:SetSize(512, 128)
    announcementFrame:SetPoint("CENTER", UIParent, "CENTER", 0, RefineUI:Scale(ANCHOR_Y))
    announcementFrame:SetFrameStrata("TOOLTIP")
    announcementFrame:SetFrameLevel(10)
    announcementFrame:EnableMouse(false)
    announcementFrame:SetAlpha(0)
    announcementFrame:SetScript("OnUpdate", OnAnnouncementUpdate)
    announcementFrame:Hide()

    zoneText = announcementFrame.ZoneText or announcementFrame:CreateFontString(nil, "OVERLAY")
    announcementFrame.ZoneText = zoneText
    zoneText:SetPoint("CENTER", announcementFrame, "CENTER", 0, 0)
    zoneText:SetJustifyH("CENTER")
    zoneText:SetFont(RefineUI.Media.Fonts.Default, RefineUI:Scale(ZONE_FONT_SIZE), "OUTLINE")

    subZoneText = announcementFrame.SubZoneText or announcementFrame:CreateFontString(nil, "OVERLAY")
    announcementFrame.SubZoneText = subZoneText
    subZoneText:SetJustifyH("CENTER")
    subZoneText:SetFont(RefineUI.Media.Fonts.Default, RefineUI:Scale(SUBZONE_FONT_SIZE), "OUTLINE")
    subZoneText:SetTextColor(0.8, 0.8, 0.8)

    difficultyText = announcementFrame.DifficultyText or announcementFrame:CreateFontString(nil, "OVERLAY")
    announcementFrame.DifficultyText = difficultyText
    difficultyText:SetJustifyH("CENTER")
    difficultyText:SetFont(RefineUI.Media.Fonts.Default, RefineUI:Scale(DIFFICULTY_FONT_SIZE), "OUTLINE")
    difficultyText:SetTextColor(0.6, 0.6, 0.6)

    ApplyAnnouncementLayout(false)
end

local function GetAnnouncementData()
    local zone = GetRealZoneText() or ""
    if zone == "" and GetZoneText then
        zone = GetZoneText() or ""
    end

    local subzone = GetSubZoneText and GetSubZoneText() or ""
    if subzone == "" and GetMinimapZoneText then
        subzone = GetMinimapZoneText() or ""
    end

    if subzone == zone then
        subzone = ""
    end

    local difficulty = GetDifficulty()
    local r, g, b = GetZoneColor()

    return zone, subzone, difficulty, r, g, b
end

local function BuildAnnouncementKey(zone, subzone, difficulty)
    return tableConcat({
        zone or "",
        subzone or "",
        difficulty or "",
    }, "\031")
end

local ShowAnnouncement

local function QueueRetry(retriesRemaining, forceShow)
    if retriesRemaining <= 0 then
        return false
    end

    local requestId = pendingRequestId
    CancelTimer(pendingRetryTimer)
    pendingRetryTimer = C_Timer.NewTimer(RETRY_DELAY, function()
        pendingRetryTimer = nil
        if requestId ~= pendingRequestId then
            return
        end
        ShowAnnouncement(retriesRemaining - 1, forceShow)
    end)

    return true
end

ShowAnnouncement = function(retriesRemaining, forceShow)
    SuppressBlizzardZoneText()
    EnsureAnnouncementFrame()

    if IsEventToastActive() then
        QueueRetry(retriesRemaining, forceShow)
        return
    end

    local zone, subzone, difficulty, r, g, b = GetAnnouncementData()
    if not zone or zone == "" then
        QueueRetry(retriesRemaining, forceShow)
        return
    end

    local key = BuildAnnouncementKey(zone, subzone, difficulty)
    if forceShow then
        if not pendingReloadingUI and transitionSourceKey and key == transitionSourceKey and QueueRetry(retriesRemaining, forceShow) then
            return
        end

        if key ~= pendingStableKey then
            pendingStableKey = key
            pendingStableCount = 1
            if QueueRetry(retriesRemaining, forceShow) then
                return
            end
        elseif pendingStableCount < 2 then
            pendingStableCount = pendingStableCount + 1
            if QueueRetry(retriesRemaining, forceShow) then
                return
            end
        end
    end

    local now = GetTime()
    if not forceShow and key == lastAnnouncementKey and (now - lastAnnouncementTime) < 1 then
        return
    end

    pendingStableKey = nil
    pendingStableCount = 0
    transitionSourceKey = nil
    pendingReloadingUI = false
    CancelTimer(pendingRetryTimer)
    pendingRetryTimer = nil
    lastAnnouncementKey = key
    lastAnnouncementTime = now

    zoneText:SetText(zone)
    zoneText:SetTextColor(r, g, b)

    if subzone and subzone ~= "" then
        subZoneText:SetText(subzone)
    else
        subZoneText:SetText("")
    end

    if difficulty and difficulty ~= "" then
        difficultyText:SetText(difficulty)
    else
        difficultyText:SetText("")
    end

    ApplyAnnouncementLayout(subzone and subzone ~= "")

    holdTimer = 0
    fadeTimer = 0
    announcementFrame:SetAlpha(1)
    announcementFrame:Show()
end

local function RequestAnnouncement(delay, forceShow)
    ResetPendingState()
    CancelTimer(pendingAnnouncementTimer)
    CancelTimer(pendingRetryTimer)
    pendingAnnouncementTimer = nil
    pendingRetryTimer = nil
    local requestId = pendingRequestId

    if delay and delay > 0 then
        pendingAnnouncementTimer = C_Timer.NewTimer(delay, function()
            pendingAnnouncementTimer = nil
            if requestId ~= pendingRequestId then
                return
            end
            ShowAnnouncement(MAX_RETRIES, forceShow)
        end)
        return
    end

    ShowAnnouncement(MAX_RETRIES, forceShow)
end

local function OnZoneEvent(event, ...)
    if event == "PLAYER_LEAVING_WORLD" then
        ResetPendingState()
        CancelTimer(pendingAnnouncementTimer)
        CancelTimer(pendingRetryTimer)
        pendingAnnouncementTimer = nil
        pendingRetryTimer = nil
        if announcementFrame then
            announcementFrame:Hide()
            announcementFrame:SetAlpha(0)
        end
        holdTimer = 0
        fadeTimer = 0
        local zone, subzone, difficulty = GetAnnouncementData()
        transitionSourceKey = BuildAnnouncementKey(zone, subzone, difficulty)
        pendingReloadingUI = false
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        local _, isReloadingUI = ...
        pendingReloadingUI = isReloadingUI and true or false
        RequestAnnouncement(WORLD_ENTRY_DELAY, true)
        return
    end

    if event == "LOADING_SCREEN_DISABLED" then
        RequestAnnouncement(LOADING_SCREEN_DELAY, true)
        return
    end

    if event == "ZONE_CHANGED_NEW_AREA" then
        RequestAnnouncement(0, true)
        return
    end

    RequestAnnouncement(0, false)
end

----------------------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------------------

function Skins:SetupZoneTextSkin()
    if RefineUI.Config.Skins and RefineUI.Config.Skins.Enable == false then
        return
    end
    if zoneTextSkinInitialized then
        SuppressBlizzardZoneText()
        return
    end

    zoneTextSkinInitialized = true

    SuppressBlizzardZoneText()
    EnsureAnnouncementFrame()

    if not zoneTextClearHooked and type(ZoneText_Clear) == "function" then
        hooksecurefunc("ZoneText_Clear", SuppressBlizzardZoneText)
        zoneTextClearHooked = true
    end

    RefineUI:RegisterEventCallback("LOADING_SCREEN_DISABLED", OnZoneEvent, EVENT_KEY.LOADING_SCREEN_DISABLED)
    RefineUI:RegisterEventCallback("PLAYER_ENTERING_WORLD", OnZoneEvent, EVENT_KEY.PLAYER_ENTERING_WORLD)
    RefineUI:RegisterEventCallback("PLAYER_LEAVING_WORLD", OnZoneEvent, EVENT_KEY.PLAYER_LEAVING_WORLD)
    RefineUI:RegisterEventCallback("ZONE_CHANGED", OnZoneEvent, EVENT_KEY.ZONE_CHANGED)
    RefineUI:RegisterEventCallback("ZONE_CHANGED_INDOORS", OnZoneEvent, EVENT_KEY.ZONE_CHANGED_INDOORS)
    RefineUI:RegisterEventCallback("ZONE_CHANGED_NEW_AREA", OnZoneEvent, EVENT_KEY.ZONE_CHANGED_NEW_AREA)

    if _G.ZoneTextFrame and _G.ZoneTextFrame:IsShown() then
        SuppressBlizzardZoneText()
    end

    if IsLoggedIn() then
        RequestAnnouncement(WORLD_ENTRY_DELAY, true)
    end
end
