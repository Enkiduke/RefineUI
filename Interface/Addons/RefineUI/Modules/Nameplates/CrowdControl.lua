-- Nameplates Component: CrowdControl
-- Description: CC duration bar driven by Blizzard nameplate crowd-control categorization.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Nameplates = RefineUI:GetModule("Nameplates")
if not Nameplates then
    return
end
local Config = RefineUI.Config

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local _G = _G
local pairs = pairs
local next = next
local type = type
local format = string.format
local GetTime = GetTime
local math_max = math.max
local math_abs = math.abs
local setmetatable = setmetatable

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local C_UnitAuras = C_UnitAuras
local Enum = Enum

----------------------------------------------------------------------------------------
-- Locals
----------------------------------------------------------------------------------------
local NAMEPLATE_CC_STATE_REGISTRY = "NameplateCrowdControlState"
local CrowdControlState = RefineUI:CreateDataRegistry(NAMEPLATE_CC_STATE_REGISTRY, "k")
local NAMEPLATE_CC_AURAFRAME_STATE_REGISTRY = "NameplateCrowdControlAuraFrameState"
local CrowdControlAuraFrameState = RefineUI:CreateDataRegistry(NAMEPLATE_CC_AURAFRAME_STATE_REGISTRY, "k")
local NAMEPLATE_CC_TIMER_JOB_KEY = "Nameplates:CrowdControlTimerUpdater"
local NAMEPLATE_CC_TIMER_INTERVAL = 0.05
local ActiveTimerStates = setmetatable({}, { __mode = "k" })
local ccTimerSchedulerInitialized = false
local SetCrowdControlTimerActive
local NameplatesUtil = RefineUI.NameplatesUtil
local IsSecret = NameplatesUtil.IsSecret
local HasValue = NameplatesUtil.HasValue
local IsAccessibleValue = NameplatesUtil.IsAccessibleValue
local ReadSafeBoolean = NameplatesUtil.ReadSafeBoolean
local ReadAccessibleValue = NameplatesUtil.ReadAccessibleValue
local IsUsableUnitToken = NameplatesUtil.IsUsableUnitToken
local BuildHookKey = NameplatesUtil.BuildHookKey
local BuildCrowdControlHookKey = function(owner, method)
    return BuildHookKey("NameplateCrowdControl", owner, method)
end

local legacyConfigMigrated = false

local function IsNameplateUnitToken(unit)
    if not IsUsableUnitToken(unit) then
        return false
    end
    return unit:match("^nameplate%d+$") ~= nil
end

local function GetAuraFrameState(aurasFrame)
    if not aurasFrame then return nil end
    local state = CrowdControlAuraFrameState[aurasFrame]
    if not state then
        state = {}
        CrowdControlAuraFrameState[aurasFrame] = state
    end
    return state
end

local function GetCrowdControlConfig()
    local nameplates = Config and Config.Nameplates
    if type(nameplates) ~= "table" then
        return nil
    end

    local cfg = nameplates.CrowdControl
    local legacyCfg = nameplates.CrowdControlTest

    if not legacyConfigMigrated and type(cfg) == "table" and type(legacyCfg) == "table" then
        local function IsDefaultCCConfig(t)
            local function NearlyEqual(a, b)
                if type(a) ~= "number" or type(b) ~= "number" then
                    return false
                end
                return math_abs(a - b) < 0.0001
            end

            if type(t) ~= "table" then return false end
            local color = t.Color
            local borderColor = t.BorderColor
            local isDefaultColor = type(color) == "table"
                and NearlyEqual(color[1], 0.2)
                and NearlyEqual(color[2], 0.6)
                and NearlyEqual(color[3], 1.0)
            local isDefaultBorderColor = type(borderColor) == "table"
                and NearlyEqual(borderColor[1], 0.2)
                and NearlyEqual(borderColor[2], 0.6)
                and NearlyEqual(borderColor[3], 1.0)

            return t.Enable == true
                and t.HideWhileCasting == true
                and isDefaultColor
                and isDefaultBorderColor
        end

        if IsDefaultCCConfig(cfg) then
            if legacyCfg.Enable ~= nil then
                cfg.Enable = legacyCfg.Enable
            end
            if legacyCfg.HideWhileCasting ~= nil then
                cfg.HideWhileCasting = legacyCfg.HideWhileCasting
            end
            if type(legacyCfg.Color) == "table" then
                cfg.Color = {
                    legacyCfg.Color[1] or 0.2,
                    legacyCfg.Color[2] or 0.6,
                    legacyCfg.Color[3] or 1.0,
                    legacyCfg.Color[4],
                }
            end
            if type(legacyCfg.BorderColor) == "table" then
                cfg.BorderColor = {
                    legacyCfg.BorderColor[1] or 0.2,
                    legacyCfg.BorderColor[2] or 0.6,
                    legacyCfg.BorderColor[3] or 1.0,
                    legacyCfg.BorderColor[4],
                }
            end
        end

        legacyConfigMigrated = true
    end

    if type(cfg) == "table" then
        return cfg
    end

    if type(legacyCfg) == "table" then
        return legacyCfg
    end

    return nil
end

local function ShouldHideCrowdControlAuraFrame(cfg)
    if not cfg or cfg.Enable == false then
        return false
    end
    return cfg.HideAuraIcons ~= false
end

local function EnsureCrowdControlAuraFrameHooks(unitFrame)
    if not unitFrame then
        return
    end

    local aurasFrame = unitFrame.AurasFrame
    if not aurasFrame then
        return
    end

    local ccListFrame = aurasFrame.CrowdControlListFrame
    if not ccListFrame then
        return
    end

    if not RefineUI.HookOnce then
        return
    end

    local state = GetAuraFrameState(aurasFrame)
    if not state then
        return
    end
    if state.hooksRegistered then
        return
    end

    local hideIfEnabled = function(frameObj)
        local cfg = GetCrowdControlConfig()
        if not ShouldHideCrowdControlAuraFrame(cfg) then
            return
        end

        local frame = frameObj and frameObj.CrowdControlListFrame
        if frame and frame:IsShown() then
            frame:Hide()
        end

        local hookState = GetAuraFrameState(frameObj)
        if hookState then
            hookState.suppressed = true
        end
    end

    RefineUI:HookOnce(
        BuildCrowdControlHookKey(aurasFrame, "UpdateEnemyNpcAuraFrames"),
        aurasFrame,
        "UpdateEnemyNpcAuraFrames",
        hideIfEnabled
    )

    RefineUI:HookOnce(
        BuildCrowdControlHookKey(aurasFrame, "UpdateShownState"),
        aurasFrame,
        "UpdateShownState",
        hideIfEnabled
    )

    RefineUI:HookOnce(
        BuildCrowdControlHookKey(ccListFrame, "Show"),
        ccListFrame,
        "Show",
        function(frame)
            local cfg = GetCrowdControlConfig()
            if ShouldHideCrowdControlAuraFrame(cfg) then
                frame:Hide()
            end
        end
    )

    state.hooksRegistered = true
end

local function SyncCrowdControlAuraFrameVisibility(unitFrame, cfg)
    if not unitFrame then
        return
    end

    local aurasFrame = unitFrame.AurasFrame
    local ccListFrame = aurasFrame and aurasFrame.CrowdControlListFrame
    if not aurasFrame or not ccListFrame then
        return
    end

    local state = GetAuraFrameState(aurasFrame)
    if not state then
        return
    end

    if ShouldHideCrowdControlAuraFrame(cfg) then
        EnsureCrowdControlAuraFrameHooks(unitFrame)
        if ccListFrame:IsShown() then
            ccListFrame:Hide()
        end
        state.suppressed = true
        return
    end

    if state.suppressed then
        if type(aurasFrame.UpdateShownState) == "function" then
            pcall(aurasFrame.UpdateShownState, aurasFrame)
        end
        state.suppressed = false
    end
end

local function EnsureNameplateData(unitFrame)
    RefineUI.NameplateData = RefineUI.NameplateData or setmetatable({}, { __mode = "k" })

    local data = RefineUI.NameplateData[unitFrame]
    if not data then
        data = {}
        RefineUI.NameplateData[unitFrame] = data
    end
    return data
end

local function GetState(unitFrame)
    if not unitFrame then return nil end
    local state = CrowdControlState[unitFrame]
    if not state then
        state = {}
        CrowdControlState[unitFrame] = state
    end
    return state
end

local function ApplyBarColors(state, cfg)
    if not state or not state.bar then return end

    local color = cfg.Color or { 0.2, 0.6, 1.0 }
    local r = color[1] or 0.2
    local g = color[2] or 0.6
    local b = color[3] or 1.0
    state.bar:SetStatusBarColor(r, g, b)

    if state.bg then
        state.bg:SetVertexColor(r * 0.25, g * 0.25, b * 0.25, 1)
    end

    if state.bar.border and state.bar.border.SetBackdropBorderColor then
        local borderColor = cfg.BorderColor or color
        local br = borderColor[1] or r
        local bg = borderColor[2] or g
        local bb = borderColor[3] or b
        local ba = borderColor[4] or 1
        state.bar.border:SetBackdropBorderColor(br, bg, bb, ba)
    end
end

local function LayoutBar(unitFrame, state)
    if not unitFrame or not state or not state.bar then
        return
    end

    local castConfig = Config.Nameplates and Config.Nameplates.CastBar or {}
    local castHeight = castConfig.Height or 20
    local hpHeight = unitFrame.HealthBarsContainer and unitFrame.HealthBarsContainer:GetHeight()
    local safeHeight = 12
    if IsAccessibleValue(hpHeight) and hpHeight and hpHeight > 0 then
        safeHeight = hpHeight
    end

    state.bar:ClearAllPoints()
    RefineUI.Point(state.bar, "TOPLEFT", unitFrame, "TOPLEFT", 12, -(safeHeight - 4))
    RefineUI.Point(state.bar, "TOPRIGHT", unitFrame, "TOPRIGHT", -12, -(safeHeight - 4))
    state.bar:SetHeight(RefineUI:Scale(castHeight))

    if state.timer then
        state.timer:ClearAllPoints()
        RefineUI.Point(state.timer, "BOTTOMRIGHT", state.bar, "BOTTOMRIGHT", -2, 0)
    end

    local castBar = unitFrame.castBar or unitFrame.CastBar
    local castLevel = castBar and castBar:GetFrameLevel()
    if castLevel and castLevel > 0 then
        state.bar:SetFrameLevel(castLevel)
        if state.bar.border then
            state.bar.border:SetFrameLevel(castLevel + 1)
        end
        if state.timer then
            state.timer:SetDrawLayer("OVERLAY", 7)
        end
        return
    end

    local unitFrameLevel = unitFrame:GetFrameLevel() or 1
    local barLevel = math_max(0, unitFrameLevel - 2)
    state.bar:SetFrameLevel(barLevel)
    if state.bar.border then
        state.bar.border:SetFrameLevel(barLevel + 1)
    end
    if state.timer then
        state.timer:SetDrawLayer("OVERLAY", 7)
    end
end

local function EnsureBar(unitFrame)
    local state = GetState(unitFrame)
    if not state then return nil end
    if state.bar then
        return state
    end

    local bar = CreateFrame("StatusBar", nil, unitFrame)
    bar:SetStatusBarTexture(RefineUI.Media.Textures.HealthBar)
    bar:SetStatusBarDesaturated(true)
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(0)
    bar:Hide()
    RefineUI.CreateBorder(bar, 6, 6, 12)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetTexture(RefineUI.Media.Textures.HealthBar)

    local text = bar:CreateFontString(nil, "OVERLAY")
    RefineUI.Font(text, 10, nil, "OUTLINE")
    RefineUI.Point(text, "BOTTOMLEFT", bar, "BOTTOMLEFT", 4, 0)
    text:SetDrawLayer("OVERLAY", 6)

    local timer = bar:CreateFontString(nil, "OVERLAY")
    RefineUI.Font(timer, 12, nil, "OUTLINE")
    timer:SetDrawLayer("OVERLAY", 7)
    timer:Hide()

    state.bar = bar
    state.bg = bg
    state.text = text
    state.timer = timer
    return state
end

local function IsCastActive(unitFrame, unit)
    local castBar = unitFrame and (unitFrame.castBar or unitFrame.CastBar)
    -- Use bar-only check (no UnitCastingInfo fallback) to avoid false positives
    -- from stale/secret unit API data during interrupt transitions.
    return NameplatesUtil.IsCastBarActive(castBar)
end

local function GetAuraFromCrowdControlList(unitFrame)
    local aurasFrame = unitFrame and unitFrame.AurasFrame
    local ccList = aurasFrame and aurasFrame.crowdControlList
    if not ccList then
        return nil
    end

    if type(ccList.GetTop) == "function" then
        local ok, aura = pcall(ccList.GetTop, ccList)
        if ok and aura then
            return aura, "blizzard_list"
        end
    end

    return nil
end

local function GetActiveCrowdControlAura(unitFrame)
    return GetAuraFromCrowdControlList(unitFrame)
end

local function GetAuraDurationObject(unit, auraInstanceID)
    if not C_UnitAuras or type(C_UnitAuras.GetAuraDuration) ~= "function" then
        return nil
    end
    if not IsUsableUnitToken(unit) then
        return nil
    end
    if not HasValue(auraInstanceID) then
        return nil
    end

    local ok, duration = pcall(C_UnitAuras.GetAuraDuration, unit, auraInstanceID)
    if not ok then
        return nil
    end

    if not HasValue(duration) then
        return nil
    end

    return duration
end

local function ApplyDurationToBar(state, duration)
    if not state or not state.bar then
        return false
    end
    if not duration then
        return false
    end
    if not state.bar.SetTimerDuration then
        return false
    end

    state.bar:SetMinMaxValues(0, 100)

    local interpolation = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
    local direction = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime

    local ok
    if direction and interpolation then
        ok = pcall(state.bar.SetTimerDuration, state.bar, duration, interpolation, direction)
    elseif direction then
        ok = pcall(state.bar.SetTimerDuration, state.bar, duration, nil, direction)
    else
        -- If direction support is unavailable, let numeric fallback handle countdown rendering.
        return false
    end

    return ok and true or false
end

local ApplyNumericFallbackState

local function ApplyNumericFallback(state, aura)
    if not state or not state.bar or not aura then
        return false
    end

    local duration = aura.duration
    local expirationTime = aura.expirationTime

    if IsAccessibleValue(duration) and IsAccessibleValue(expirationTime) and duration and expirationTime and duration > 0 then
        state.numericDuration = duration
        state.numericExpirationTime = expirationTime
        return ApplyNumericFallbackState(state)
    end

    return false
end

local function ClearDurationText(state)
    if not state or not state.timer then
        return
    end

    RefineUI:SetFontStringValue(state.timer, nil, {
        emptyText = "",
    })
    state.timer:Hide()
end

local function TryApplyDurationText(state, duration)
    if not state or not state.timer or not duration then
        return false
    end

    -- FontStrings don't have SetTimerDuration — use EvaluateRemainingDuration + SetFormattedText
    if not duration.EvaluateRemainingDuration or not RefineUI.GetLinearCurve then
        return false
    end

    local ok, remaining = pcall(duration.EvaluateRemainingDuration, duration, RefineUI.GetLinearCurve())
    if not ok or not HasValue(remaining) then
        return false
    end

    -- SetFormattedText is AllowedWhenTainted — safe even if remaining is secret
    local fmtOk = pcall(state.timer.SetFormattedText, state.timer, "%.1f", remaining)
    if fmtOk then
        state.timer:Show()
        return true
    end

    return false
end

local function SetDurationText(state, duration, aura)
    if not state then return end
    state.duration = duration
    state.numericDuration = nil
    state.numericExpirationTime = nil
    state.activeDuration = nil

    if not state.timer then return end

    if not duration or not aura then
        ClearDurationText(state)
        return false
    end

    if TryApplyDurationText(state, duration) then
        -- Store duration for continuous re-evaluation by the timer job
        state.activeDuration = duration
        return true
    end

    ClearDurationText(state)
    return false
end

ApplyNumericFallbackState = function(state)
    if not state or not state.bar then
        return false
    end

    local numericDuration = state.numericDuration
    local numericExpirationTime = state.numericExpirationTime
    if type(numericDuration) ~= "number" or numericDuration <= 0 then
        return false
    end
    if type(numericExpirationTime) ~= "number" or numericExpirationTime <= 0 then
        return false
    end

    local remaining = math_max(0, numericExpirationTime - GetTime())
    state.bar:SetMinMaxValues(0, numericDuration)
    state.bar:SetValue(remaining)
    if state.timer then
        RefineUI:SetFontStringValue(state.timer, remaining, {
            format = "%.1f",
            emptyText = "",
        })
        state.timer:Show()
    end

    return remaining > 0
end

local function IsCrowdControlTimerRelevant(state)
    if not state or not state.bar or not state.bar:IsShown() then
        return false
    end

    -- Relevant if we have a stored Duration object for text re-evaluation
    if state.activeDuration and state.activeDuration.EvaluateRemainingDuration then
        return true
    end

    return type(state.numericDuration) == "number" and type(state.numericExpirationTime) == "number"
end

local function CrowdControlTimerUpdateJob()
    local hasActive = false

    for state in pairs(ActiveTimerStates) do
        if not IsCrowdControlTimerRelevant(state) then
            ActiveTimerStates[state] = nil
            if state then
                state.numericDuration = nil
                state.numericExpirationTime = nil
                state.activeDuration = nil
            end
        elseif state.activeDuration and state.activeDuration.EvaluateRemainingDuration then
            -- Duration-object path: re-evaluate remaining and update text
            if TryApplyDurationText(state, state.activeDuration) then
                hasActive = true
            else
                ActiveTimerStates[state] = nil
                state.activeDuration = nil
            end
        elseif ApplyNumericFallbackState(state) then
            hasActive = true
        else
            ActiveTimerStates[state] = nil
            if state then
                state.numericDuration = nil
                state.numericExpirationTime = nil
            end
        end
    end

    if not hasActive and not next(ActiveTimerStates) and RefineUI.SetUpdateJobEnabled then
        RefineUI:SetUpdateJobEnabled(NAMEPLATE_CC_TIMER_JOB_KEY, false, false)
    end
end

local function EnsureCrowdControlTimerScheduler()
    if ccTimerSchedulerInitialized then
        return
    end
    if not RefineUI.RegisterUpdateJob then
        return
    end

    RefineUI:RegisterUpdateJob(
        NAMEPLATE_CC_TIMER_JOB_KEY,
        NAMEPLATE_CC_TIMER_INTERVAL,
        CrowdControlTimerUpdateJob,
        { enabled = false }
    )

    ccTimerSchedulerInitialized = true
end

SetCrowdControlTimerActive = function(state, enabled)
    if not state then
        return
    end

    EnsureCrowdControlTimerScheduler()
    if not ccTimerSchedulerInitialized then
        return
    end

    if enabled and IsCrowdControlTimerRelevant(state) then
        ActiveTimerStates[state] = true
    else
        ActiveTimerStates[state] = nil
    end

    if RefineUI.SetUpdateJobEnabled then
        RefineUI:SetUpdateJobEnabled(NAMEPLATE_CC_TIMER_JOB_KEY, next(ActiveTimerStates) ~= nil, false)
    end
end

local function RefreshPortraitAndBorders(unitFrame, unit, event)
    if not unitFrame then
        return
    end

    RefineUI:RefreshNameplateVisualState(unitFrame, unit, event or "UNIT_AURA", {
        refreshBorders = true,
        refreshPortrait = true,
    })
end

function RefineUI:ClearNameplateCrowdControl(unitFrame, suppressVisualRefresh)
    if not unitFrame then
        return
    end

    local cfg = GetCrowdControlConfig()
    SyncCrowdControlAuraFrameVisibility(unitFrame, cfg)

    local state = CrowdControlState[unitFrame]
    if state and state.bar then
        state.bar:Hide()
    end
    if state then
        if SetCrowdControlTimerActive then
            SetCrowdControlTimerActive(state, false)
        end
        SetDurationText(state, nil, nil)
        if state.text then
            RefineUI:SetFontStringValue(state.text, nil, {
                emptyText = "",
            })
        end
    end

    local data = EnsureNameplateData(unitFrame)
    local wasActive = data.CrowdControlActive == true
    local hadAura = data.CrowdControlAuraInstanceID ~= nil
    local wasSuppressed = data.CrowdControlSuppressed == true

    data.CrowdControlActive = false
    data.CrowdControlSuppressed = false
    data.CrowdControlAuraInstanceID = nil
    data.CrowdControlSpellID = nil
    data.CrowdControlIcon = nil
    data.CrowdControlName = nil
    data.CrowdControlDuration = nil
    data.CrowdControlSource = nil

    if (wasActive or hadAura or wasSuppressed) and not suppressVisualRefresh then
        RefreshPortraitAndBorders(unitFrame, unitFrame.unit, "UNIT_AURA")
    end
end

function RefineUI:UpdateNameplateCrowdControl(unitFrame, unit, event, suppressVisualRefresh, _isDeferred)
    if not unitFrame then
        return
    end

    unit = unit or unitFrame.unit
    if not IsNameplateUnitToken(unit) then
        self:ClearNameplateCrowdControl(unitFrame, suppressVisualRefresh)
        return
    end

    local cfg = GetCrowdControlConfig()
    SyncCrowdControlAuraFrameVisibility(unitFrame, cfg)
    if not cfg or cfg.Enable == false then
        self:ClearNameplateCrowdControl(unitFrame, suppressVisualRefresh)
        return
    end

    local data = EnsureNameplateData(unitFrame)
    if data.RefineHidden then
        self:ClearNameplateCrowdControl(unitFrame, suppressVisualRefresh)
        return
    end

    local aura, source = GetActiveCrowdControlAura(unitFrame)
    if not aura then
        self:ClearNameplateCrowdControl(unitFrame, suppressVisualRefresh)
        return
    end

    local hideWhileCasting = cfg.HideWhileCasting ~= false
    local suppressForCast = hideWhileCasting and IsCastActive(unitFrame, unit)
    local auraInstanceID = ReadAccessibleValue(aura.auraInstanceID, nil)

    local duration = GetAuraDurationObject(unit, aura.auraInstanceID)

    local state = EnsureBar(unitFrame)
    if not state then
        return
    end

    LayoutBar(unitFrame, state)
    ApplyBarColors(state, cfg)

    if state.text then
        RefineUI:SetFontStringValue(state.text, aura.name, {
            emptyText = "Crowd Control",
        })
    end

    if suppressForCast then
        SetDurationText(state, nil, nil)
        state.bar:Hide()
        if SetCrowdControlTimerActive then
            SetCrowdControlTimerActive(state, false)
        end
    else
        SetDurationText(state, duration, aura)
        local appliedDuration = ApplyDurationToBar(state, duration)
        local appliedNumeric = false
        if not appliedDuration then
            appliedNumeric = ApplyNumericFallback(state, aura)
        end

        if not appliedDuration and not appliedNumeric then
            self:ClearNameplateCrowdControl(unitFrame, suppressVisualRefresh)
            return
        end

        state.bar:Show()

        if SetCrowdControlTimerActive then
            SetCrowdControlTimerActive(state, appliedDuration or appliedNumeric)
        end
    end

    local wasActive = data.CrowdControlActive == true
    local previousAuraID = data.CrowdControlAuraInstanceID
    local wasSuppressed = data.CrowdControlSuppressed == true

    data.CrowdControlActive = true
    data.CrowdControlSuppressed = suppressForCast and true or false
    data.CrowdControlAuraInstanceID = auraInstanceID
    data.CrowdControlSpellID = aura.spellId
    data.CrowdControlIcon = aura.icon
    data.CrowdControlName = aura.name
    data.CrowdControlDuration = duration
    data.CrowdControlSource = source

    local changed = (not wasActive) or (previousAuraID ~= auraInstanceID) or (wasSuppressed ~= data.CrowdControlSuppressed)
    if changed and not suppressVisualRefresh then
        RefreshPortraitAndBorders(unitFrame, unit, event or "UNIT_AURA")
    end
end

