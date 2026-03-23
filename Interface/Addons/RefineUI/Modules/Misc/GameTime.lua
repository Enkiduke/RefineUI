----------------------------------------------------------------------------------------
-- GameTime
-- Description: Displays a configurable clock or combat timer with Edit Mode support.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local GameTime = RefineUI:RegisterModule("GameTime")

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local GetGameTime = GetGameTime
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local UIParent = UIParent
local C_Timer = C_Timer
local date = date
local floor = math.floor
local format = string.format
local tonumber = tonumber
local type = type
local unpack = unpack

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local FRAME_NAME = "RefineUI_GameTime"
local EDIT_MODE_LABEL = "Game Time"
local DISPLAY_JOB_KEY = "GameTime:DisplayUpdate"
local DEFAULT_POSITION = { "BOTTOM", "UIParent", "BOTTOM", 0, 10 }
local DEFAULT_SCALE = 1.0
local MIN_SCALE = 0.75
local MAX_SCALE = 1.5
local BASE_WIDTH = 200
local BASE_HEIGHT = 32
local BASE_FONT_SIZE = 32

local EVENT_KEY = {
    COMBAT_START = "GameTime:CombatStart",
    COMBAT_END = "GameTime:CombatEnd",
}

local DISPLAY_STYLE = {
    LOCAL_24H = "LOCAL_24H",
    LOCAL_AM_PM = "LOCAL_AM_PM",
    REALM_24H = "REALM_24H",
    REALM_AM_PM = "REALM_AM_PM",
}

local DISPLAY_STYLE_OPTIONS = {
    { text = "Local 24-Hour", value = DISPLAY_STYLE.LOCAL_24H },
    { text = "Local AM/PM", value = DISPLAY_STYLE.LOCAL_AM_PM },
    { text = "Realm 24-Hour", value = DISPLAY_STYLE.REALM_24H },
    { text = "Realm AM/PM", value = DISPLAY_STYLE.REALM_AM_PM },
}

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
local combatStartTime = 0
local inCombat = false
local clockTimer = nil

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local function RoundNumber(value)
    value = tonumber(value) or 0
    if value >= 0 then
        return floor(value + 0.5)
    end
    return floor(value - 0.5)
end

local function ClampScale(value)
    local scale = tonumber(value) or DEFAULT_SCALE
    if scale < MIN_SCALE then
        return MIN_SCALE
    end
    if scale > MAX_SCALE then
        return MAX_SCALE
    end
    return scale
end

local function NormalizeDisplayStyle(value)
    for _, option in ipairs(DISPLAY_STYLE_OPTIONS) do
        if option.value == value then
            return value
        end
    end
    return DISPLAY_STYLE.LOCAL_24H
end

local function ResolveRelativeFrame(relativeTo)
    if type(relativeTo) == "string" then
        return _G[relativeTo] or UIParent
    end
    return relativeTo or UIParent
end

local function FormatElapsedTime(seconds)
    local minutes = floor(seconds / 60)
    local remainingSeconds = floor(seconds % 60)
    return format("%02d:%02d", minutes, remainingSeconds)
end

local function FormatClockTime(hour, minute, useAmPm)
    hour = tonumber(hour) or 0
    minute = tonumber(minute) or 0

    if useAmPm then
        local timeFormat = TIME_TWELVEHOURAM or "%d:%02d AM"
        if hour == 0 then
            hour = 12
        elseif hour == 12 then
            timeFormat = TIME_TWELVEHOURPM or "%d:%02d PM"
        elseif hour > 12 then
            timeFormat = TIME_TWELVEHOURPM or "%d:%02d PM"
            hour = hour - 12
        end

        return format(timeFormat, hour, minute)
    end

    return format(TIMEMANAGER_TICKER_24HOUR or "%02d:%02d", hour, minute)
end

local function GetLocalTimeParts()
    return tonumber(date("%H")) or 0, tonumber(date("%M")) or 0
end

local function GetRealmTimeParts()
    local hour, minute = GetGameTime()
    return hour or 0, minute or 0
end

local function CancelClockTimer()
    if clockTimer and clockTimer.Cancel then
        clockTimer:Cancel()
    end
    clockTimer = nil
end

local function GetSecondsUntilNextMinute()
    local currentSecond = tonumber(date("%S")) or 0
    local delay = 60 - currentSecond
    if delay <= 0 then
        delay = 60
    end
    return delay
end

----------------------------------------------------------------------------------------
-- Data Model
----------------------------------------------------------------------------------------
function GameTime:GetConfig()
    self.db = self.db or (RefineUI.Config and RefineUI.Config.GameTime) or {}
    return self.db
end

function GameTime:IsCombatTimerEnabled()
    return self:GetConfig().CombatTimerEnable ~= false
end

function GameTime:GetCombatTimerInterval()
    local interval = tonumber(self:GetConfig().CombatTimerUpdateInterval)
    if not interval or interval <= 0 then
        return 0.1
    end
    return interval
end

function GameTime:GetDisplayStyle()
    local cfg = self:GetConfig()
    cfg.DisplayStyle = NormalizeDisplayStyle(cfg.DisplayStyle)
    return cfg.DisplayStyle
end

function GameTime:GetClockText()
    local displayStyle = self:GetDisplayStyle()
    local hour, minute

    if displayStyle == DISPLAY_STYLE.LOCAL_24H or displayStyle == DISPLAY_STYLE.LOCAL_AM_PM then
        hour, minute = GetLocalTimeParts()
    else
        hour, minute = GetRealmTimeParts()
    end

    return FormatClockTime(hour, minute, displayStyle == DISPLAY_STYLE.LOCAL_AM_PM or displayStyle == DISPLAY_STYLE.REALM_AM_PM)
end

function GameTime:GetDefaultPosition()
    local position = RefineUI.Positions and RefineUI.Positions[FRAME_NAME]
    if type(position) == "table" and type(position[1]) == "string" then
        return position
    end
    return DEFAULT_POSITION
end

function GameTime:IsShowingCombatTimer()
    return inCombat and self:IsCombatTimerEnabled()
end

----------------------------------------------------------------------------------------
-- Display
----------------------------------------------------------------------------------------
function GameTime:ApplyScale()
    if not (self.Frame and self.Text) then
        return
    end

    local scale = ClampScale(self:GetConfig().Scale)
    self:GetConfig().Scale = scale

    RefineUI.Size(self.Frame, RoundNumber(BASE_WIDTH * scale), RoundNumber(BASE_HEIGHT * scale))
    RefineUI.Font(self.Text, RoundNumber(BASE_FONT_SIZE * scale))
end

function GameTime:UpdateClockDisplay()
    if not self.Text then
        return
    end

    self.Text:SetText(self:GetClockText())
    self.Text:SetTextColor(1, 1, 1)
end

function GameTime:UpdateCombatTimerDisplay()
    if not (self.Text and self:IsShowingCombatTimer()) then
        return
    end

    self.Text:SetText(FormatElapsedTime(GetTime() - combatStartTime))
    self.Text:SetTextColor(1, 0.2, 0.2)
end

function GameTime:ScheduleNextClockUpdate()
    CancelClockTimer()

    if self:IsShowingCombatTimer() or not self.Text then
        return
    end

    if not C_Timer or not C_Timer.NewTimer then
        self:UpdateClockDisplay()
        return
    end

    clockTimer = C_Timer.NewTimer(GetSecondsUntilNextMinute(), function()
        clockTimer = nil
        GameTime:UpdateClockDisplay()
        GameTime:ScheduleNextClockUpdate()
    end)
end

function GameTime:SetCombatUpdateEnabled(enabled)
    if not (RefineUI.IsUpdateJobRegistered and RefineUI:IsUpdateJobRegistered(DISPLAY_JOB_KEY)) then
        return
    end

    if enabled and RefineUI.SetUpdateJobInterval then
        RefineUI:SetUpdateJobInterval(DISPLAY_JOB_KEY, self:GetCombatTimerInterval())
    end

    if RefineUI.SetUpdateJobEnabled then
        RefineUI:SetUpdateJobEnabled(DISPLAY_JOB_KEY, enabled, true)
    end
end

function GameTime:RefreshDisplay()
    if not self.Text then
        return
    end

    if self:IsShowingCombatTimer() then
        CancelClockTimer()
        self:UpdateCombatTimerDisplay()
        self:SetCombatUpdateEnabled(true)
        return
    end

    self:SetCombatUpdateEnabled(false)
    self:UpdateClockDisplay()
    self:ScheduleNextClockUpdate()
end

function GameTime:ApplyFramePosition()
    if not self.Frame then
        return
    end

    local point, relativeTo, relativePoint, x, y = unpack(self:GetDefaultPosition())
    self.Frame:ClearAllPoints()
    self.Frame:SetPoint(point, ResolveRelativeFrame(relativeTo), relativePoint or point, x or 0, y or 0)
end

----------------------------------------------------------------------------------------
-- Edit Mode
----------------------------------------------------------------------------------------
function GameTime:RegisterEditModeSettings()
    local lib = RefineUI.LibEditMode
    if self._editModeSettingsRegistered or not lib then
        return
    end

    local settingType = lib.SettingType
    if not settingType then
        return
    end

    self._editModeSettings = {
        {
            kind = settingType.Dropdown,
            name = "Display Style",
            default = DISPLAY_STYLE.LOCAL_24H,
            generator = function(_, rootDescription)
                local cfg = GameTime:GetConfig()
                for _, option in ipairs(DISPLAY_STYLE_OPTIONS) do
                    rootDescription:CreateRadio(
                        option.text,
                        function(data)
                            return cfg.DisplayStyle == data.value
                        end,
                        function(data)
                            cfg.DisplayStyle = NormalizeDisplayStyle(data.value)
                            GameTime:RefreshDisplay()
                        end,
                        { value = option.value }
                    )
                end
            end,
            get = function()
                return GameTime:GetDisplayStyle()
            end,
            set = function(_, value)
                local cfg = GameTime:GetConfig()
                cfg.DisplayStyle = NormalizeDisplayStyle(value)
                GameTime:RefreshDisplay()
            end,
        },
        {
            kind = settingType.Slider,
            name = "Scale",
            default = DEFAULT_SCALE,
            minValue = MIN_SCALE,
            maxValue = MAX_SCALE,
            valueStep = 0.05,
            formatter = function(value)
                return format("%.2f", ClampScale(value))
            end,
            get = function()
                return ClampScale(GameTime:GetConfig().Scale)
            end,
            set = function(_, value)
                GameTime:GetConfig().Scale = ClampScale(value)
                GameTime:ApplyScale()
            end,
        },
        {
            kind = settingType.Checkbox,
            name = "Show Combat Timer",
            default = true,
            get = function()
                return GameTime:IsCombatTimerEnabled()
            end,
            set = function(_, value)
                GameTime:GetConfig().CombatTimerEnable = value == true
                GameTime:RefreshDisplay()
            end,
        },
    }

    self._editModeSettingsRegistered = true
end

function GameTime:RegisterEditModeFrame()
    local lib = RefineUI.LibEditMode
    if self._editModeFrameRegistered or not (lib and self.Frame and type(lib.AddFrame) == "function") then
        return
    end

    local point, _, _, x, y = unpack(self:GetDefaultPosition())
    lib:AddFrame(self.Frame, function(frame, _, newPoint, offsetX, offsetY)
        frame:ClearAllPoints()
        frame:SetPoint(newPoint, UIParent, newPoint, offsetX, offsetY)
        RefineUI:SetPosition(FRAME_NAME, { newPoint, "UIParent", newPoint, offsetX, offsetY })
    end, {
        point = point,
        x = x or 0,
        y = y or 0,
    }, EDIT_MODE_LABEL)
    self._editModeFrameRegistered = true

    if self._editModeSettings and not self._editModeSettingsAttached and type(lib.AddFrameSettings) == "function" then
        lib:AddFrameSettings(self.Frame, self._editModeSettings)
        self._editModeSettingsAttached = true
    end
end

----------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------
function GameTime:OnEnable()
    local cfg = RefineUI.Config and RefineUI.Config.GameTime
    if not (cfg and cfg.Enable) then
        return
    end

    self.db = cfg
    self.db.DisplayStyle = NormalizeDisplayStyle(self.db.DisplayStyle)
    self.db.Scale = ClampScale(self.db.Scale)
    if self.db.CombatTimerEnable == nil then
        self.db.CombatTimerEnable = true
    end

    local frame = self.Frame or _G[FRAME_NAME]
    if not frame then
        frame = CreateFrame("Button", FRAME_NAME, UIParent)
        frame:SetClampedToScreen(true)
        frame:RegisterForClicks("LeftButtonUp")
    end
    frame.editModeName = EDIT_MODE_LABEL
    frame:SetScript("OnClick", function(_, button)
        if button == "LeftButton" and not inCombat and type(_G.ToggleCalendar) == "function" then
            _G.ToggleCalendar()
        end
    end)

    local text = self.Text
    if not text then
        text = frame:CreateFontString(nil, "OVERLAY")
        RefineUI.Point(text, "CENTER", frame, "CENTER", 0, 0)
        text:SetAlpha(0.5)
    end

    self.Frame = frame
    self.Text = text

    self:ApplyFramePosition()
    self:ApplyScale()

    if RefineUI.RegisterUpdateJob and not (RefineUI.IsUpdateJobRegistered and RefineUI:IsUpdateJobRegistered(DISPLAY_JOB_KEY)) then
        RefineUI:RegisterUpdateJob(DISPLAY_JOB_KEY, self:GetCombatTimerInterval(), function()
            GameTime:UpdateCombatTimerDisplay()
        end, {
            enabled = false,
            combatOnly = true,
            predicate = function()
                return GameTime:IsShowingCombatTimer() and GameTime.Text ~= nil
            end,
        })
    end

    self:RegisterEditModeSettings()
    self:RegisterEditModeFrame()

    RefineUI:RegisterEventCallback("PLAYER_REGEN_DISABLED", function()
        inCombat = true
        combatStartTime = GetTime()
        GameTime:RefreshDisplay()
    end, EVENT_KEY.COMBAT_START)

    RefineUI:RegisterEventCallback("PLAYER_REGEN_ENABLED", function()
        inCombat = false
        GameTime:RefreshDisplay()
    end, EVENT_KEY.COMBAT_END)

    if InCombatLockdown() then
        inCombat = true
        combatStartTime = GetTime()
    end

    self:RefreshDisplay()
end
