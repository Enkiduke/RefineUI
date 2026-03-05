-- Nameplate Crowd Control Bar for RefineUI
-- Description: CC duration bar driven by Blizzard nameplate crowd-control categorization.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local C = RefineUI.Config

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local _G = _G
local pairs = pairs
local ipairs = ipairs
local next = next
local type = type
local GetTime = GetTime
local math_min = math.min
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
local C_Spell = C_Spell
local Enum = Enum

----------------------------------------------------------------------------------------
-- Locals
----------------------------------------------------------------------------------------
local NAMEPLATE_CC_STATE_REGISTRY = "NameplateCrowdControlState"
local CrowdControlState = RefineUI:CreateDataRegistry(NAMEPLATE_CC_STATE_REGISTRY, "k")
local NAMEPLATE_CC_AURAFRAME_STATE_REGISTRY = "NameplateCrowdControlAuraFrameState"
local CrowdControlAuraFrameState = RefineUI:CreateDataRegistry(NAMEPLATE_CC_AURAFRAME_STATE_REGISTRY, "k")
local NAMEPLATE_CC_HARMFUL_FILTER = "HARMFUL|INCLUDE_NAME_PLATE_ONLY"
local NAMEPLATE_CC_TIMER_JOB_KEY = "Nameplates:CrowdControlTimerUpdater"
local NAMEPLATE_CC_TIMER_INTERVAL = 0.05
local NAMEPLATE_CC_DEFERRED_REFRESH_DELAY = 0.05
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
    local nameplates = C and C.Nameplates
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

    local castConfig = C.Nameplates and C.Nameplates.CastBar or {}
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

    local castBar = unitFrame.castBar or unitFrame.CastBar
    local castLevel = castBar and castBar:GetFrameLevel()
    if castLevel and castLevel > 0 then
        state.bar:SetFrameLevel(castLevel)
        if state.bar.border then
            state.bar.border:SetFrameLevel(castLevel + 1)
        end
        return
    end

    local unitFrameLevel = unitFrame:GetFrameLevel() or 1
    local barLevel = math_max(0, unitFrameLevel - 2)
    state.bar:SetFrameLevel(barLevel)
    if state.bar.border then
        state.bar.border:SetFrameLevel(barLevel + 1)
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

    local timer = bar:CreateFontString(nil, "OVERLAY")
    RefineUI.Font(timer, 10, nil, "OUTLINE")
    RefineUI.Point(timer, "BOTTOMRIGHT", bar, "BOTTOMRIGHT", -4, 0)
    timer:Hide()

    state.bar = bar
    state.bg = bg
    state.text = text
    state.timer = timer
    return state
end

local function IsCastActive(unitFrame, unit)
    local castBar = unitFrame and (unitFrame.castBar or unitFrame.CastBar)
    if castBar and castBar:IsShown() then
        if ReadSafeBoolean(castBar.casting) == true then return true end
        if ReadSafeBoolean(castBar.channeling) == true then return true end
        if ReadSafeBoolean(castBar.reverseChanneling) == true then return true end

        local barType = castBar.barType
        if IsAccessibleValue(barType) and type(barType) == "string" then
            if barType == "standard" or barType == "channel" or barType == "uninterruptable" or barType == "uninterruptible" then
                return true
            end
        end
    end

    if IsUsableUnitToken(unit) then
        local castName = UnitCastingInfo(unit)
        if HasValue(castName) then
            return true
        end

        castName = UnitChannelInfo(unit)
        if HasValue(castName) then
            return true
        end
    end

    return false
end

local function SafeIsSpellCrowdControl(spellIdentifier)
    if not C_Spell or type(C_Spell.IsSpellCrowdControl) ~= "function" then
        return false
    end

    local ok, result = pcall(C_Spell.IsSpellCrowdControl, spellIdentifier)
    if not ok then
        return false
    end
    return ReadSafeBoolean(result) == true
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

local function GetAuraFromApiScan(unit)
    if not C_UnitAuras or type(C_UnitAuras.GetUnitAuras) ~= "function" then
        return nil
    end

    local sortRule = Enum and Enum.UnitAuraSortRule and Enum.UnitAuraSortRule.ExpirationOnly
    local sortDirection = Enum and Enum.UnitAuraSortDirection and Enum.UnitAuraSortDirection.Reverse

    local ok, auras
    if sortRule and sortDirection then
        ok, auras = pcall(C_UnitAuras.GetUnitAuras, unit, NAMEPLATE_CC_HARMFUL_FILTER, nil, sortRule, sortDirection)
    else
        ok, auras = pcall(C_UnitAuras.GetUnitAuras, unit, NAMEPLATE_CC_HARMFUL_FILTER)
    end

    if not ok or type(auras) ~= "table" then
        return nil
    end

    local now = GetTime()
    local bestAura = nil
    local bestRemaining = nil

    local function GetRemainingDuration(aura)
        if type(aura) ~= "table" then
            return nil
        end

        local expirationTime = ReadAccessibleValue(aura.expirationTime, nil)
        if type(expirationTime) == "number" and expirationTime > 0 then
            return math_max(0, expirationTime - now)
        end

        local duration = ReadAccessibleValue(aura.duration, nil)
        if type(duration) == "number" and duration > 0 then
            return duration
        end

        return nil
    end

    for _, aura in ipairs(auras) do
        local spellId = aura and ReadAccessibleValue(aura.spellId, nil)
        if HasValue(spellId) and SafeIsSpellCrowdControl(spellId) then
            local remaining = GetRemainingDuration(aura)
            if type(remaining) == "number" then
                if not bestAura or bestRemaining == nil or remaining > bestRemaining then
                    bestAura = aura
                    bestRemaining = remaining
                end
            elseif not bestAura then
                -- Keep a deterministic fallback if remaining data is unavailable.
                bestAura = aura
                bestRemaining = -1
            end
        end
    end

    if bestAura then
        return bestAura, "api_scan_longest_remaining"
    end

    return nil
end

local function GetActiveCrowdControlAura(unitFrame, unit)
    local aura, source = GetAuraFromApiScan(unit)
    if aura then
        return aura, source
    end
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

local function IsAuraStillPresent(unit, auraInstanceID)
    if not C_UnitAuras or type(C_UnitAuras.GetAuraDataByAuraInstanceID) ~= "function" then
        return true
    end
    if not IsUsableUnitToken(unit) then
        return true
    end
    if not HasValue(auraInstanceID) then
        return true
    end

    local ok, auraData = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, auraInstanceID)
    if not ok then
        return true
    end

    return HasValue(auraData)
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

local function ApplyNumericFallback(state, aura)
    if not state or not state.bar or not aura then
        return false
    end

    local duration = aura.duration
    local expirationTime = aura.expirationTime

    if IsAccessibleValue(duration) and IsAccessibleValue(expirationTime) and duration and expirationTime and duration > 0 then
        local startTime = expirationTime - duration
        local elapsed = GetTime() - startTime
        local remaining = math_max(0, duration - elapsed)
        state.bar:SetMinMaxValues(0, duration)
        state.bar:SetValue(remaining)
        return true
    end

    return false
end

local function SetDurationText(state, duration)
    if not state then return end
    state.duration = duration

    if not state.timer then return end

    if not duration then
        RefineUI:SetFontStringValue(state.timer, nil, {
            emptyText = "",
        })
        state.timer:Hide()
        return
    end

    local remaining
    if duration.EvaluateRemainingDuration and RefineUI.GetLinearCurve then
        local ok, value = pcall(duration.EvaluateRemainingDuration, duration, RefineUI.GetLinearCurve())
        if ok and HasValue(value) then
            remaining = value
        end
    end

    if not HasValue(remaining) and duration.GetRemainingDuration then
        local ok, value = pcall(duration.GetRemainingDuration, duration)
        if ok and HasValue(value) then
            remaining = value
        end
    end

    if not HasValue(remaining) and duration.GetTotalDuration then
        local ok, value = pcall(duration.GetTotalDuration, duration)
        if ok and HasValue(value) then
            remaining = value
        end
    end

    if HasValue(remaining) then
        state.timer:Show()
        RefineUI:SetFontStringValue(state.timer, remaining, {
            format = "%.1f",
            duration = duration,
            emptyText = "",
        })
        return
    end

    if state.timer.SetTimerDuration then
        local ok = pcall(state.timer.SetTimerDuration, state.timer, duration)
        if ok then
            state.timer:Show()
            return
        end
    end

    RefineUI:SetFontStringValue(state.timer, nil, {
        duration = duration,
        emptyText = "",
    })
    state.timer:Hide()
end

local function IsCrowdControlTimerRelevant(state)
    if not state or not state.bar then
        return false
    end
    if not state.bar:IsShown() then
        return false
    end
    if not state.timer or not state.duration then
        return false
    end
    return true
end

local function CrowdControlTimerUpdateJob()
    local hasActive = false

    for state in pairs(ActiveTimerStates) do
        if IsCrowdControlTimerRelevant(state) then
            SetDurationText(state, state.duration)
            hasActive = true
        else
            ActiveTimerStates[state] = nil
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

    if enabled then
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
        SetDurationText(state, nil)
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

local function QueueDeferredCrowdControlRefresh(unitFrame, unit, event, suppressVisualRefresh)
    if not unitFrame then
        return
    end
    if not RefineUI.After then
        return
    end

    local timerKey = BuildCrowdControlHookKey(unitFrame, "DeferredRefresh")
    RefineUI:After(timerKey, NAMEPLATE_CC_DEFERRED_REFRESH_DELAY, function()
        if RefineUI.UpdateNameplateCrowdControl then
            RefineUI:UpdateNameplateCrowdControl(unitFrame, unit, event, suppressVisualRefresh, true)
        end
    end)
end

function RefineUI:UpdateNameplateCrowdControl(unitFrame, unit, event, suppressVisualRefresh, isDeferred)
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

    local aura, source = GetActiveCrowdControlAura(unitFrame, unit)
    if not aura then
        if not isDeferred and event == "UNIT_AURA" then
            QueueDeferredCrowdControlRefresh(unitFrame, unit, event, suppressVisualRefresh)
        end
        self:ClearNameplateCrowdControl(unitFrame, suppressVisualRefresh)
        return
    end

    local hideWhileCasting = cfg.HideWhileCasting ~= false
    local suppressForCast = hideWhileCasting and IsCastActive(unitFrame, unit)
    local auraInstanceID = ReadAccessibleValue(aura.auraInstanceID, nil)

    if auraInstanceID and not IsAuraStillPresent(unit, auraInstanceID) then
        if not isDeferred and event == "UNIT_AURA" then
            QueueDeferredCrowdControlRefresh(unitFrame, unit, event, suppressVisualRefresh)
        end
        self:ClearNameplateCrowdControl(unitFrame, suppressVisualRefresh)
        return
    end

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
        SetDurationText(state, nil)
        state.bar:Hide()
        if SetCrowdControlTimerActive then
            SetCrowdControlTimerActive(state, false)
        end
    else
        SetDurationText(state, duration)
        local appliedDuration = ApplyDurationToBar(state, duration)
        local appliedNumeric = false
        if not appliedDuration then
            appliedNumeric = ApplyNumericFallback(state, aura)
        end

        if not appliedDuration and not appliedNumeric then
            if not isDeferred and event == "UNIT_AURA" then
                QueueDeferredCrowdControlRefresh(unitFrame, unit, event, suppressVisualRefresh)
            end
            -- Unresolved timing can indicate stale/lagging aura data. Clear until revalidated.
            self:ClearNameplateCrowdControl(unitFrame, suppressVisualRefresh)
            return
        end

        state.bar:Show()

        if SetCrowdControlTimerActive then
            SetCrowdControlTimerActive(state, (appliedDuration or appliedNumeric) and duration ~= nil)
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
