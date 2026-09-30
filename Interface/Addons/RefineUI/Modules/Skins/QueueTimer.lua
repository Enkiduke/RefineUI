----------------------------------------------------------------------------------------
-- Skins Component: Queue Timer
-- Description: Countdown crest, urgency colors, wait time, and alert sounds on the
--              LFG and PvP ready dialogs.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Skins = RefineUI:GetModule("Skins")
if not Skins then
    return
end

----------------------------------------------------------------------------------------
-- Shared Aliases
----------------------------------------------------------------------------------------
local Config = RefineUI.Config
local Media = RefineUI.Media

----------------------------------------------------------------------------------------
-- WoW Globals (Upvalues)
----------------------------------------------------------------------------------------
local _G = _G
local C_AddOns = C_AddOns
local C_CurveUtil = C_CurveUtil
local C_DurationUtil = C_DurationUtil
local C_StringUtil = C_StringUtil
local C_Texture = C_Texture
local C_Timer = C_Timer
local CreateColor = CreateColor
local CreateFrame = CreateFrame
local Enum = Enum
local GetBattlefieldPortExpiration = GetBattlefieldPortExpiration
local GetBattlefieldStatus = GetBattlefieldStatus
local GetBattlefieldTimeWaited = GetBattlefieldTimeWaited
local GetLFGMode = GetLFGMode
local GetLFGProposal = GetLFGProposal
local GetLFGQueueStats = GetLFGQueueStats
local GetTime = GetTime
local PlaySoundFile = PlaySoundFile
local SecondsToTime = SecondsToTime
local hooksecurefunc = hooksecurefunc
local select = select

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local COMPONENT_KEY = "Skins:QueueTimer"

local EVENT_KEY = {
    LFG_QUEUE_STATUS_UPDATE = COMPONENT_KEY .. ":LFG_QUEUE_STATUS_UPDATE",
    UPDATE_BATTLEFIELD_STATUS = COMPONENT_KEY .. ":UPDATE_BATTLEFIELD_STATUS",
}

local HOOK_KEY = {
    LFG_HIDE = COMPONENT_KEY .. ":LFGDungeonReadyDialog:OnHide",
    PVP_HIDE = COMPONENT_KEY .. ":PVPReadyDialog:OnHide",
}

local ALERT_SOUND_FILE_ID = 567458 -- sound/interface/alarmclockwarning3.ogg
-- Blizzard exposes no expiration for LFG proposals; they last 40 seconds.
local PROPOSAL_DURATION = 40
local WARNING_SECONDS = 6
local URGENT_SECONDS = 10
-- Remaining-time boundaries where the crest restyles, descending.
local PHASE_SECONDS = { 20, URGENT_SECONDS, WARNING_SECONDS }

-- Journeys (Adventure Guide) renown ring art.
local RING_TRACK_ATLAS = "ui-journeys-renown-radial-bar"
local RING_FILL_ATLAS = "ui-journeys-renown-radial-fill"
local RING_PIT_ATLAS = "ui-journeys-delve-renown-circle-pit"
local PIT_SCALE = 75 / 90 -- Journeys overview: 75px pit inside a 90px ring
local BACKDROP_ATLAS = "ui-journeys-bg" -- the Journeys page backdrop the ring sits on
local BACKDROP_SCALE = 1.2 -- tucks the disc edge under the ring track

local CREST_SIZE = 58
local TIMER_FONT_SIZE = 24

----------------------------------------------------------------------------------------
-- Locals
----------------------------------------------------------------------------------------
local widgetsByDialog = {}
local timerFormatter, timerColorCurve
local proposalID, proposalStart
local lfgQueuedAt
local pvpQueuedAt, pvpPortStart, pvpPortLength = {}, {}, {}

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------

-- Master channel, so the alert is heard with sound effects muted.
local function PlayAlert()
    PlaySoundFile(ALERT_SOUND_FILE_ID, "Master")
end

local function PlayWarning()
    PlayAlert()
    C_Timer.After(0.1, PlayAlert)
    C_Timer.After(0.2, PlayAlert)
end

local function AnnouncePop(kind, queuedAt)
    local config = Config.Skins.QueueTimer
    if config.Sound then
        PlayAlert()
    end
    if not config.AnnounceWaitTime then
        return
    end

    if not queuedAt then
        RefineUI:Print("Queue: %s is ready!", kind)
        return
    end

    local waited = GetTime() - queuedAt
    if waited < 1 then
        RefineUI:Print("Queue: %s popped instantly!", kind)
    else
        RefineUI:Print("Queue: %s popped after %s.", kind, SecondsToTime(waited))
    end
end

-- Boss mods parent their own countdown bars to the dungeon ready popup.
local function HideStatusBars(...)
    for index = 1, select("#", ...) do
        local child = select(index, ...)
        if child:GetObjectType() == "StatusBar" then
            child:Hide()
        end
    end
end

local function CreateTimerStyle()
    -- Whole seconds, rounded up, with no unit so the number fills the crest.
    timerFormatter = C_StringUtil.CreateNumericRuleFormatter()
    timerFormatter:AddBreakpoint({ threshold = 0, step = 1, rounding = Enum.NumericRuleFormatRounding.Up, format = "%.0f" })

    -- Step points promote on exact matches: red below 10s, gold below 20s.
    timerColorCurve = C_CurveUtil.CreateColorCurve()
    timerColorCurve:SetType(Enum.LuaCurveType.Step)
    timerColorCurve:AddPoint(0, CreateColor(1, 0.125, 0.125, 1))
    timerColorCurve:AddPoint(URGENT_SECONDS, CreateColor(1, 0.82, 0, 1))
    timerColorCurve:AddPoint(20, CreateColor(0.125, 1, 0.125, 1))
end

-- Recolors the crest for the current urgency, starts the pulse and warning when due,
-- then sleeps until the next boundary. Runs a few times per pop, never per frame.
local function ApplyPhase(widgets)
    local remaining = widgets.endTime - GetTime()
    local r, g, b = timerColorCurve:Evaluate(remaining):GetRGB()
    widgets.text:SetTextColor(r, g, b)
    widgets.glow:SetVertexColor(r, g, b)
    widgets.cooldown:SetSwipeColor(r, g, b, 1)

    if remaining <= URGENT_SECONDS and not widgets.pulse:IsPlaying() then
        widgets.pulse:Play()
    end
    if widgets.warnPending and remaining <= WARNING_SECONDS then
        widgets.warnPending = false
        PlayWarning()
    end

    for index = 1, #PHASE_SECONDS do
        local boundary = PHASE_SECONDS[index]
        if remaining > boundary then
            RefineUI:After(widgets.phaseKey, remaining - boundary, widgets.onPhase)
            return
        end
    end
end

-- A medallion centered on the dialog's top-left corner, built like the Journeys renown
-- ring: a sunken pit, a radial track, and an urgency-colored fill that drains as the
-- port expires, with the seconds in the middle. The fill and number are driven
-- natively by the duration object.
local function GetWidgets(dialog)
    local widgets = widgetsByDialog[dialog]
    if widgets then
        return widgets
    end

    local crest = CreateFrame("Frame", nil, dialog)
    RefineUI.Size(crest, CREST_SIZE, CREST_SIZE)
    crest:SetPoint("CENTER", dialog, "TOPLEFT", 10, -10)
    crest:SetFrameLevel(dialog:GetFrameLevel() + 10)

    -- Over the backdrop, under the pit, track, and fill.
    local glow = crest:CreateTexture(nil, "BACKGROUND", nil, -2)
    glow:SetAtlas("ChallengeMode-WhiteSpikeyGlow")
    glow:SetBlendMode("ADD")
    glow:SetAlpha(0.4)
    glow:SetSize(CREST_SIZE * 1.3, CREST_SIZE * 1.3)
    glow:SetPoint("CENTER")

    -- A round window onto the center of the Journeys backdrop, since half the crest
    -- hangs off the dialog with nothing behind it.
    local backdropInfo = C_Texture.GetAtlasInfo(BACKDROP_ATLAS)
    local cropX = (backdropInfo.rightTexCoord - backdropInfo.leftTexCoord) * (1 - backdropInfo.height / backdropInfo.width) / 2
    local backdrop = crest:CreateTexture(nil, "BACKGROUND", nil, -3)
    backdrop:SetTexture(backdropInfo.file or backdropInfo.filename)
    backdrop:SetTexCoord(backdropInfo.leftTexCoord + cropX, backdropInfo.rightTexCoord - cropX, backdropInfo.topTexCoord, backdropInfo.bottomTexCoord)
    backdrop:SetSize(CREST_SIZE * BACKDROP_SCALE, CREST_SIZE * BACKDROP_SCALE)
    backdrop:SetPoint("CENTER")
    local backdropMask = crest:CreateMaskTexture()
    backdropMask:SetTexture(Media.Textures.PortraitMask)
    backdropMask:SetAllPoints(backdrop)
    backdrop:AddMaskTexture(backdropMask)

    local pit = crest:CreateTexture(nil, "BACKGROUND", nil, -1)
    pit:SetAtlas(RING_PIT_ATLAS)
    pit:SetSize(CREST_SIZE * PIT_SCALE, CREST_SIZE * PIT_SCALE)
    pit:SetPoint("CENTER")

    local track = crest:CreateTexture(nil, "BACKGROUND")
    track:SetAtlas(RING_TRACK_ATLAS)
    track:SetAllPoints()

    -- Same fill setup as JourneysProgressBarMixin:RefreshBar, but live and unreversed,
    -- so the lit arc is the time remaining.
    local fill = C_Texture.GetAtlasInfo(RING_FILL_ATLAS)
    local cooldown = CreateFrame("Cooldown", nil, crest)
    cooldown:SetAllPoints()
    cooldown:SetSwipeTexture(fill.file or fill.filename)
    cooldown:SetTexCoordRange(
        { x = fill.leftTexCoord, y = fill.topTexCoord },
        { x = fill.rightTexCoord, y = fill.bottomTexCoord }
    )
    -- Journeys' rotation="180": the arc starts at the bottom, where the fill art expects it.
    cooldown:SetRotation(math.pi)
    cooldown:SetDrawEdge(false)
    cooldown:SetDrawBling(false)
    cooldown:SetHideCountdownNumbers(true)

    local face = CreateFrame("Frame", nil, crest)
    face:SetAllPoints()
    face:SetFrameLevel(cooldown:GetFrameLevel() + 1)

    local text = face:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER")
    RefineUI.Font(text, TIMER_FONT_SIZE, Media.Fonts.Number, "OUTLINE", true)

    local binding = C_DurationUtil.CreateDurationTextBinding()
    binding:SetFontString(text)
    binding:SetFormatter(timerFormatter)
    -- Redraw every tick so the digit flips on the exact second, in step with ApplyPhase's
    -- boundary timers. A throttled interval lets the digit lag the color by up to one
    -- interval, by a different amount each pop. Native, and disabled while hidden.
    binding:SetUpdateInterval(0)

    -- Heartbeat once time is short: the crest swells and its glow flares.
    local pulse = crest:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local swell = pulse:CreateAnimation("Scale")
    swell:SetScaleFrom(1, 1)
    swell:SetScaleTo(1.08, 1.08)
    swell:SetDuration(0.4)
    swell:SetSmoothing("IN_OUT")
    local flare = pulse:CreateAnimation("Alpha")
    flare:SetTarget(glow)
    flare:SetFromAlpha(0.4)
    flare:SetToAlpha(1)
    flare:SetDuration(0.4)

    widgets = {
        text = text,
        glow = glow,
        cooldown = cooldown,
        binding = binding,
        pulse = pulse,
        duration = C_DurationUtil.CreateDuration(),
        phaseKey = COMPONENT_KEY .. ":Phase:" .. dialog:GetName(),
    }
    widgets.onPhase = function()
        ApplyPhase(widgets)
    end
    widgetsByDialog[dialog] = widgets
    return widgets
end

----------------------------------------------------------------------------------------
-- Countdown
----------------------------------------------------------------------------------------

local function StartCountdown(dialog, startTime, length)
    local widgets = GetWidgets(dialog)
    local endTime = startTime + length
    if widgets.endTime ~= endTime then
        widgets.endTime = endTime
        widgets.warnPending = Config.Skins.QueueTimer.WarningSound
    end

    local duration = widgets.duration
    duration:SetTimeFromStart(startTime, length)
    widgets.cooldown:SetCooldownFromDurationObject(duration)
    widgets.binding:SetDuration(duration)
    widgets.binding:SetEnabled(true)
    ApplyPhase(widgets)
end

local function StopCountdown(dialog)
    local widgets = widgetsByDialog[dialog]
    if not widgets then
        return
    end

    widgets.binding:SetEnabled(false)
    widgets.pulse:Stop()
    RefineUI:CancelTimer(widgets.phaseKey)
end

----------------------------------------------------------------------------------------
-- Blizzard Hooks & Events
----------------------------------------------------------------------------------------

-- Runs after Blizzard has filled in the dialog for a new or updated proposal. It is
-- driven by LFG_PROPOSAL_UPDATE, after boss mods have shown their LFG_PROPOSAL_SHOW bars.
local function OnDungeonPopupUpdate()
    local dialog = _G.LFGDungeonReadyDialog
    local exists, id = GetLFGProposal()
    if not exists or not dialog:IsShown() then
        return
    end

    if id ~= proposalID then
        proposalID, proposalStart = id, GetTime()
        AnnouncePop("Dungeon", lfgQueuedAt)
        lfgQueuedAt = nil
        if Config.Skins.QueueTimer.HideOtherTimers then
            HideStatusBars(_G.LFGDungeonReadyPopup:GetChildren())
        end
    end

    StartCountdown(dialog, proposalStart, PROPOSAL_DURATION)
end

-- Blizzard redisplays the dialog on every battlefield update while the port is open.
local function OnPvPDialogDisplay(dialog, index)
    if not pvpPortStart[index] then
        pvpPortStart[index] = GetTime()
        pvpPortLength[index] = GetBattlefieldPortExpiration(index)
        AnnouncePop("PvP queue", pvpQueuedAt[index])
        pvpQueuedAt[index] = nil
    end

    StartCountdown(dialog, pvpPortStart[index], pvpPortLength[index])
end

local function OnLFGQueueStatus()
    for category = 1, NUM_LE_LFG_CATEGORYS do
        if GetLFGMode(category) == "queued" then
            local hasData, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, queuedTime = GetLFGQueueStats(category)
            if hasData and queuedTime then
                lfgQueuedAt = queuedTime
                return
            end
        end
    end
end

local function OnBattlefieldStatus(_, index)
    local status = GetBattlefieldStatus(index)
    if status == "queued" then
        pvpQueuedAt[index] = pvpQueuedAt[index] or (GetTime() - GetBattlefieldTimeWaited(index) / 1000)
    elseif status ~= "confirm" then
        pvpQueuedAt[index], pvpPortStart[index], pvpPortLength[index] = nil, nil, nil
    end
end

----------------------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------------------

function Skins:SetupQueueTimerSkin()
    -- These addons replace the same ready-dialog timers.
    if C_AddOns.IsAddOnLoaded("BetterBlizzQueue") or C_AddOns.IsAddOnLoaded("SafeQueue") then
        return
    end

    CreateTimerStyle()
    hooksecurefunc("LFGDungeonReadyPopup_Update", OnDungeonPopupUpdate)
    hooksecurefunc("PVPReadyDialog_Display", OnPvPDialogDisplay)
    RefineUI:HookScriptOnce(HOOK_KEY.LFG_HIDE, _G.LFGDungeonReadyDialog, "OnHide", StopCountdown)
    RefineUI:HookScriptOnce(HOOK_KEY.PVP_HIDE, _G.PVPReadyDialog, "OnHide", StopCountdown)
    RefineUI:RegisterEventCallback("UPDATE_BATTLEFIELD_STATUS", OnBattlefieldStatus, EVENT_KEY.UPDATE_BATTLEFIELD_STATUS)
    -- Queue start times only feed the wait-time announcement.
    if Config.Skins.QueueTimer.AnnounceWaitTime then
        RefineUI:RegisterEventCallback("LFG_QUEUE_STATUS_UPDATE", OnLFGQueueStatus, EVENT_KEY.LFG_QUEUE_STATUS_UPDATE)
    end
end
