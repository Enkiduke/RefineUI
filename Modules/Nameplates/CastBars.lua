----------------------------------------------------------------------------------------
-- Nameplate CastBars for RefineUI
-- Description: Extracted CastBar logic with performance optimizations
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local C = RefineUI.Config

-- External Data Registry
local NAMEPLATE_CASTBAR_STATE_REGISTRY = "NameplateCastBarsState"
local CastBarData = RefineUI:CreateDataRegistry(NAMEPLATE_CASTBAR_STATE_REGISTRY, "k")

local function GetCastBarData(castBar)
    if not castBar then return nil end
    local data = CastBarData[castBar]
    if not data then
        data = {}
        CastBarData[castBar] = data
    end
    return data
end

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local _G = _G
local unpack = unpack
local math = math
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local UnitCastingDuration = UnitCastingDuration
local UnitChannelDuration = UnitChannelDuration
local UnitIsPlayer = UnitIsPlayer
local UnitAffectingCombat = UnitAffectingCombat
local CreateFrame = CreateFrame
local C_Timer = C_Timer
local C_NamePlate = C_NamePlate
local CreateColor = CreateColor
local type = type
local tonumber = tonumber
local pairs = pairs
local next = next
local setmetatable = setmetatable

----------------------------------------------------------------------------------------
-- Texture Cache
----------------------------------------------------------------------------------------
local M = RefineUI.Media.Textures
local TEX_BAR = M.HealthBar
local CASTBAR_BACKDROP_DARKEN = 0.5
local NameplatesUtil = RefineUI.NameplatesUtil
local IsSecret = NameplatesUtil.IsSecret
local HasValue = NameplatesUtil.HasValue
local IsAccessibleValue = NameplatesUtil.IsAccessibleValue
local ReadSafeBoolean = NameplatesUtil.ReadSafeBoolean
local IsUsableUnitToken = NameplatesUtil.IsUsableUnitToken
local SafeUnitIsUnit = NameplatesUtil.SafeUnitIsUnit
local BuildHookKey = NameplatesUtil.BuildHookKey
local BuildNameplateCastHookKey = function(owner, method)
    return BuildHookKey("NameplatesCastBars", owner, method)
end

local DEFAULT_INTERRUPTIBLE_CAST_COLOR = { 1, 0.7, 0 }
local DEFAULT_NON_INTERRUPTIBLE_CAST_COLOR = { 1, 0.2, 0.2 }
local CAST_BG_MULTIPLIER = 0.3

local function ClampColorChannel(value, fallback)
    local number = tonumber(value)
    if not number then
        return fallback
    end
    if number < 0 then
        return 0
    end
    if number > 1 then
        return 1
    end
    return number
end

local function BuildColorFromConfig(configColor, fallback)
    return {
        ClampColorChannel(configColor and configColor[1], fallback[1]),
        ClampColorChannel(configColor and configColor[2], fallback[2]),
        ClampColorChannel(configColor and configColor[3], fallback[3]),
    }
end

local function BuildBackgroundColor(sourceColor)
    return {
        sourceColor[1] * CAST_BG_MULTIPLIER,
        sourceColor[2] * CAST_BG_MULTIPLIER,
        sourceColor[3] * CAST_BG_MULTIPLIER,
    }
end

local function ApplyBackdropDarken(texture, bgColor)
    if not texture or not bgColor then return end
    local br, bg, bb, ba = unpack(bgColor)
    br = (br or 0) * CASTBAR_BACKDROP_DARKEN
    bg = (bg or 0) * CASTBAR_BACKDROP_DARKEN
    bb = (bb or 0) * CASTBAR_BACKDROP_DARKEN
    texture:SetVertexColor(br, bg, bb, ba)
end

local NAMEPLATE_CASTBAR_TIMER_JOB_KEY = "Nameplates:CastBarTimerUpdater"
local NAMEPLATE_CASTBAR_TIMER_INTERVAL = 0.1
local ActiveTimerCastBars = setmetatable({}, { __mode = "k" })
local castBarTimerSchedulerInitialized = false
local SetCastBarTimerActive
local IsCastActive

local function GetSafeBarType(castBar)
    if not castBar then return nil end
    local barType = castBar.barType
    if not IsAccessibleValue(barType) then
        return nil
    end
    if type(barType) ~= "string" then
        return nil
    end
    return barType
end

local function IsSafeBarType(castBar, expectedType)
    local barType = GetSafeBarType(castBar)
    return barType ~= nil and barType == expectedType
end

local function SafeCastBarIsInterruptable(castBar)
    if not castBar or type(castBar.IsInterruptable) ~= "function" then
        return nil
    end

    local ok, isInterruptable = pcall(castBar.IsInterruptable, castBar)
    if not ok then
        return nil
    end

    return ReadSafeBoolean(isInterruptable)
end

local function CreateColorFromArray(color, darkenFactor)
    local r, g, b, a = unpack(color or {})
    local mult = darkenFactor or 1
    return CreateColor((r or 1) * mult, (g or 1) * mult, (b or 1) * mult, a or 1)
end

local function GetCastBarRenderedColor(castBar)
    if not castBar or not castBar.GetStatusBarTexture then
        return nil
    end

    local tex = castBar:GetStatusBarTexture()
    if not tex or not tex.GetVertexColor then
        return nil
    end

    local r, g, b = tex:GetVertexColor()
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        return nil
    end
    if IsSecret(r) or IsSecret(g) or IsSecret(b) then
        return nil
    end
    if not IsAccessibleValue(r) or not IsAccessibleValue(g) or not IsAccessibleValue(b) then
        return nil
    end

    return r, g, b
end

local function GetCastInterruptibilitySignal(unit, castBar)
    if not unit then
        return nil, false
    end

    local castName, _, _, _, _, _, _, notInterruptible = UnitCastingInfo(unit)
    if HasValue(castName) then
        return notInterruptible, true
    end

    local channelName
    channelName, _, _, _, _, _, notInterruptible = UnitChannelInfo(unit)
    if HasValue(channelName) then
        return notInterruptible, true
    end

    if not IsCastActive(unit, castBar) then
        return nil, false
    end

    if castBar then
        local castBarNotInterruptible = castBar.notInterruptible
        if HasValue(castBarNotInterruptible) then
            return castBarNotInterruptible, true
        end

        local ok, isInterruptable = pcall(function()
            if type(castBar.IsInterruptable) == "function" then
                return castBar:IsInterruptable()
            end
            return nil
        end)
        if ok and HasValue(isInterruptable) then
            return not isInterruptable, true
        end
    end

    return nil, true
end

local function ApplyCastStatusColorFromSignal(castBar, signal, resolvedNotInterruptible)
    if not castBar then
        return false
    end

    local colors = RefineUI.Colors.Cast
    local bgColors = RefineUI.Colors.CastBG

    local statusTexture = castBar.GetStatusBarTexture and castBar:GetStatusBarTexture()
    if signal ~= nil and statusTexture and statusTexture.SetVertexColorFromBoolean then
        statusTexture:SetVertexColorFromBoolean(
            signal,
            CreateColorFromArray(colors.NonInterruptible),
            CreateColorFromArray(colors.Interruptible)
        )
    elseif resolvedNotInterruptible ~= nil and castBar.SetStatusBarColor then
        local baseColor = resolvedNotInterruptible and colors.NonInterruptible or colors.Interruptible
        castBar:SetStatusBarColor(unpack(baseColor))
    else
        return false
    end

    local function ApplyBackgroundSignal(background)
        if not background then return end

        if signal ~= nil and background.SetVertexColorFromBoolean then
            background:SetVertexColorFromBoolean(
                signal,
                CreateColorFromArray(bgColors.NonInterruptible, CASTBAR_BACKDROP_DARKEN),
                CreateColorFromArray(bgColors.Interruptible, CASTBAR_BACKDROP_DARKEN)
            )
        elseif resolvedNotInterruptible ~= nil and background.SetVertexColor then
            local baseBG = resolvedNotInterruptible and bgColors.NonInterruptible or bgColors.Interruptible
            ApplyBackdropDarken(background, baseBG)
        end
    end

    local data = GetCastBarData(castBar)
    ApplyBackgroundSignal(data and data.Background)
    ApplyBackgroundSignal(castBar.Background)

    return true
end

local function ApplyBorderColorFromSignal(borderFrame, signal, resolvedNotInterruptible)
    if not borderFrame then
        return false
    end

    local colors = RefineUI.Colors.Cast
    local trueColor = CreateColorFromArray(colors.NonInterruptible)
    local falseColor = CreateColorFromArray(colors.Interruptible)

    local pieces = borderFrame._refineBorderPieces
    if signal ~= nil and pieces then
        local applied = false
        for i = 1, #pieces do
            local tex = pieces[i]
            if tex and tex.SetVertexColorFromBoolean then
                tex:SetVertexColorFromBoolean(signal, trueColor, falseColor)
                applied = true
            end
        end
        if applied then
            return true
        end
    end

    if resolvedNotInterruptible ~= nil and borderFrame.SetBackdropBorderColor then
        local color = resolvedNotInterruptible and colors.NonInterruptible or colors.Interruptible
        borderFrame:SetBackdropBorderColor(unpack(color))
        return true
    end

    return false
end

local function SetCastTimerText(timer, text)
    if not timer then return end
    RefineUI:SetFontStringValue(timer, text, {
        emptyText = "",
    })
end

local function SetCastTimerNumber(timer, value, durationObj)
    if not timer then return end
    RefineUI:SetFontStringValue(timer, value, {
        format = "%.1f",
        duration = durationObj,
        emptyText = "",
    })
end

local function SetUnitAlphaCached(data, unitFrame, alpha)
    if not data or not unitFrame then return end
    if data.lastUnitAlpha ~= alpha then
        data.lastUnitAlpha = alpha
        unitFrame:SetAlpha(alpha)
    end
end

local function EmptyCastBar(castBar)
    if not castBar or not castBar.SetValue then return end

    local minValue = 0
    if castBar.GetMinMaxValues then
        local minCandidate = castBar:GetMinMaxValues()
        if (not IsSecret(minCandidate)) and minCandidate ~= nil then
            minValue = minCandidate
        end
    end

    castBar:SetValue(minValue)
end

IsCastActive = function(unit, castBar)
    if unit then
        local castName = UnitCastingInfo(unit)
        if HasValue(castName) then
            return true
        end

        castName = UnitChannelInfo(unit)
        if HasValue(castName) then
            return true
        end
    end

    if castBar and castBar:IsShown() then
        local barType = GetSafeBarType(castBar)
        local isCasting = ReadSafeBoolean(castBar.casting) == true
        local isChanneling = ReadSafeBoolean(castBar.channeling) == true
        local isReverseChanneling = ReadSafeBoolean(castBar.reverseChanneling) == true

        if isCasting or isChanneling or isReverseChanneling then
            return true
        end
        if barType and barType ~= "" and barType ~= "interrupted" then
            return true
        end
    end

    return false
end

local UpdateCastColor
local IsCastTimerRelevant
local HandleCastBarEvent

function RefineUI:RefreshNameplateCastColors(refreshExisting)
    self.Colors = self.Colors or {}
    self.Colors.Cast = self.Colors.Cast or {}
    self.Colors.CastBG = self.Colors.CastBG or {}

    local configColors = C
        and C.Nameplates
        and C.Nameplates.CastBar
        and C.Nameplates.CastBar.Colors

    local interruptibleColor = BuildColorFromConfig(
        configColors and configColors.Interruptible,
        DEFAULT_INTERRUPTIBLE_CAST_COLOR
    )
    local nonInterruptibleColor = BuildColorFromConfig(
        configColors and configColors.NonInterruptible,
        DEFAULT_NON_INTERRUPTIBLE_CAST_COLOR
    )

    self.Colors.Cast.Interruptible = interruptibleColor
    self.Colors.Cast.NonInterruptible = nonInterruptibleColor
    self.Colors.CastBG.Interruptible = BuildBackgroundColor(interruptibleColor)
    self.Colors.CastBG.NonInterruptible = BuildBackgroundColor(nonInterruptibleColor)

    if refreshExisting ~= true or not C_NamePlate or type(C_NamePlate.GetNamePlates) ~= "function" then
        return
    end

    for _, nameplate in pairs(C_NamePlate.GetNamePlates()) do
        local unitFrame = nameplate and nameplate.UnitFrame
        local castBar = unitFrame and (unitFrame.castBar or unitFrame.CastBar)
        if castBar then
            UpdateCastColor(castBar)
        end
    end
end

----------------------------------------------------------------------------------------
-- Functions
----------------------------------------------------------------------------------------

function RefineUI:GetCastColor(unit, castBar)
    if not unit then return nil end
    if IsSafeBarType(castBar, "interrupted") then
        return nil
    end
    
    local hasCastFromAPI = false
    local apiNotInterruptible
    local notInt
    local castName
    
    -- Prefer unit APIs first.
    castName, _, _, _, _, _, _, apiNotInterruptible = UnitCastingInfo(unit)
    if HasValue(castName) then
        hasCastFromAPI = true
    else
        castName, _, _, _, _, _, apiNotInterruptible = UnitChannelInfo(unit)
    end
    if HasValue(castName) then
        hasCastFromAPI = true
    end

    local hasCast = hasCastFromAPI or IsCastActive(unit, castBar)

    if not hasCast then
        return nil -- No active cast
    end

    local data = castBar and GetCastBarData(castBar) or nil

    -- Prefer Blizzard's own resolved interruptibility when accessible.
    if castBar then
        local isInterruptable = SafeCastBarIsInterruptable(castBar)
        if isInterruptable ~= nil then
            notInt = not isInterruptable
        end
    end

    -- Additional positive non-interruptible signals.
    if notInt ~= true and castBar then
        local barType = GetSafeBarType(castBar)
        if barType == "uninterruptable" or barType == "uninterruptible" then
            notInt = true
        else
            local castBarNotInterruptible = ReadSafeBoolean(castBar.notInterruptible)
            if castBarNotInterruptible == true then
                notInt = true
            end
        end
    end
    if notInt ~= true and data and data.notInterruptible == true then
        notInt = true
    end

    -- Then fall back to API value when available.
    if notInt == nil then
        local apiNotInt = ReadSafeBoolean(apiNotInterruptible)
        if apiNotInt ~= nil then
            notInt = apiNotInt
        end
    end

    -- Final explicit interruptible event state.
    if notInt == nil and data and data.notInterruptible == false then
        notInt = false
    end

    -- Shield visibility is driven by Blizzard's own interruptibility resolution for nameplate castbars.
    if notInt == nil and castBar and castBar.BorderShield and castBar.BorderShield.IsShown then
        local shieldShown = ReadSafeBoolean(castBar.BorderShield:IsShown())
        if shieldShown ~= nil then
            notInt = shieldShown
        end
    end
    
    local colors = RefineUI.Colors.Cast
    local bgColors = RefineUI.Colors.CastBG
    
    -- Final resolution/secret guard
    if IsSecret(notInt) or notInt == nil then
        return colors.Interruptible, bgColors.Interruptible
    elseif notInt then
        return colors.NonInterruptible, bgColors.NonInterruptible
    else
        return colors.Interruptible, bgColors.Interruptible
    end
end

function RefineUI:GetNameplateCastInterruptibilitySignal(unit, castBar)
    return GetCastInterruptibilitySignal(unit, castBar)
end

function RefineUI:GetNameplateCastRenderedColor(castBar)
    return GetCastBarRenderedColor(castBar)
end

local function UpdateCastTime(self, elapsed)
    local data = GetCastBarData(self)
    if not data or not data.timer then return end

    -- Throttle to 10 updates/second (100ms) to reduce CPU load 
    -- especially when many nameplates are active.
    data.elapsed = (data.elapsed or 0) + elapsed
    if data.elapsed < 0.1 then return end
    data.elapsed = 0

    local unitFrame = self:GetParent()
    if not unitFrame then return end
    local unit = unitFrame.unit
    local npData = RefineUI.NameplateData and RefineUI.NameplateData[unitFrame]
    
    -- Optimization: Use cached isTarget from external nameplate data (avoids secure-frame field writes).
    -- Use global check if nil (safety)
    local isTarget = npData and npData.isTarget
    if isTarget == nil then 
        if not IsSecret(unit) then
            isTarget = SafeUnitIsUnit("target", unit)
        else
            isTarget = false
        end
    end
    
    -- Timer should not depend on color cache. Determine active cast/channel explicitly.
    local barType = GetSafeBarType(self)
    local isChanneling = (ReadSafeBoolean(self.channeling) == true)
        or (ReadSafeBoolean(self.reverseChanneling) == true)
        or barType == "channel"
    local isCasting = (ReadSafeBoolean(self.casting) == true)
        or barType == "standard"
        or barType == "uninterruptable"
        or barType == "uninterruptible"
    local hasActiveCast = isCasting or isChanneling
    local apiHasChannel = false

    if not hasActiveCast and unit then
        isCasting = HasValue(UnitCastingInfo(unit))
        if not isCasting then
            apiHasChannel = HasValue(UnitChannelInfo(unit))
            isChanneling = apiHasChannel
        end
        hasActiveCast = isCasting or isChanneling
    end

    if not hasActiveCast then
        if barType == "interrupted" then
            EmptyCastBar(self)
        end
        SetCastTimerText(data.timer, "")
        return
    end

    local value = self.value
    local maxValue = self.maxValue
    local canUseNumericMath = (not IsSecret(value)) and (not IsSecret(maxValue)) and value ~= nil and maxValue ~= nil

    -- Prefer Duration object path when math operands are unavailable/secret.
    if not canUseNumericMath then
        if not self.GetTimerDuration then return end

        local durationObj
        local preferChannelDuration = isChanneling or apiHasChannel
        if preferChannelDuration and UnitChannelDuration then
            durationObj = UnitChannelDuration(unit)
        elseif UnitCastingDuration then
            durationObj = UnitCastingDuration(unit)
        end
        if not HasValue(durationObj) and self.GetTimerDuration then
            durationObj = self:GetTimerDuration()
        end
        if not HasValue(durationObj) then return end
        
        -- Safe Duration display
        local remaining
        if durationObj.EvaluateRemainingDuration then
             remaining = durationObj:EvaluateRemainingDuration(RefineUI.GetLinearCurve())
        end

        if (not IsSecret(remaining)) and remaining == nil and durationObj.GetTotalDuration then
            remaining = durationObj:GetTotalDuration()
        end

        if IsSecret(remaining) then
            SetCastTimerNumber(data.timer, remaining, durationObj)
        elseif remaining ~= nil then
            SetCastTimerNumber(data.timer, remaining, durationObj)
        else
            SetCastTimerNumber(data.timer, nil, durationObj)
        end
    else
        local remaining
        if isChanneling then
            remaining = math.max(value, 0)
        else
            remaining = math.max(maxValue - value, 0)
        end
        SetCastTimerNumber(data.timer, remaining)
    end

    -- Evaluate Dynamic Alpha
    -- Logic: 
    -- 1. Is Target? -> 1.0 (Always visible)
    -- 2. Else Is NPC in Combat (Important)? -> High Alpha (0.8-1.0)
    -- 3. Else? -> Low Alpha (0.6)
    
    if npData and npData.RefineHidden then
        -- Name-only plates should not be faded by castbar alpha logic.
        SetUnitAlphaCached(data, unitFrame, 1)
    elseif isTarget then
        SetUnitAlphaCached(data, unitFrame, 1)
    else
        -- Optimization: Retrieve cached isPlayer and inCombat from the unitFrame data
        -- This avoids multiple API calls every frame
        local isPlayer = npData and npData.isPlayer
        if isPlayer == nil then
            isPlayer = ReadSafeBoolean(UnitIsPlayer(unit))
        end
        if isPlayer == nil then
            isPlayer = false
        end
        
        local inCombat = npData and npData.inCombat
        if inCombat == nil then
            inCombat = ReadSafeBoolean(UnitAffectingCombat(unit))
        end
        if inCombat == nil then
            inCombat = false
        end
        
        local isNPC = not isPlayer
        local shouldHighlight = isNPC and inCombat
        
        if shouldHighlight then
            -- Transition logic could go here, but for simplicity/perf:
            SetUnitAlphaCached(data, unitFrame, 0.9)
        else
            SetUnitAlphaCached(data, unitFrame, 0.6)
        end
    end
end

IsCastTimerRelevant = function(castBar)
    if not castBar or not castBar:IsShown() then
        return false
    end

    local barType = GetSafeBarType(castBar)
    local isCasting = ReadSafeBoolean(castBar.casting) == true
    local isChanneling = ReadSafeBoolean(castBar.channeling) == true
    local isReverseChanneling = ReadSafeBoolean(castBar.reverseChanneling) == true
    if isCasting or isChanneling or isReverseChanneling then
        return true
    end

    if barType == "standard" or barType == "channel" or barType == "uninterruptable" or barType == "uninterruptible" then
        return true
    end

    local unitFrame = castBar:GetParent()
    local unit = unitFrame and unitFrame.unit
    if IsUsableUnitToken(unit) then
        if HasValue(UnitCastingInfo(unit)) then
            return true
        end
        if HasValue(UnitChannelInfo(unit)) then
            return true
        end
    end

    return false
end

local function CastBarTimerUpdateJob()
    local hasActive = false

    for castBar in pairs(ActiveTimerCastBars) do
        if castBar and castBar:IsShown() then
            UpdateCastTime(castBar, NAMEPLATE_CASTBAR_TIMER_INTERVAL)
            if IsCastTimerRelevant(castBar) then
                hasActive = true
            else
                ActiveTimerCastBars[castBar] = nil
            end
        else
            ActiveTimerCastBars[castBar] = nil
        end
    end

    if not hasActive and not next(ActiveTimerCastBars) and RefineUI.SetUpdateJobEnabled then
        RefineUI:SetUpdateJobEnabled(NAMEPLATE_CASTBAR_TIMER_JOB_KEY, false, false)
    end
end

local function EnsureCastBarTimerScheduler()
    if castBarTimerSchedulerInitialized then return end
    if not RefineUI.RegisterUpdateJob then return end

    RefineUI:RegisterUpdateJob(
        NAMEPLATE_CASTBAR_TIMER_JOB_KEY,
        NAMEPLATE_CASTBAR_TIMER_INTERVAL,
        CastBarTimerUpdateJob,
        { enabled = false }
    )

    castBarTimerSchedulerInitialized = true
end

SetCastBarTimerActive = function(castBar, enabled)
    if not castBar then return end
    EnsureCastBarTimerScheduler()
    if not castBarTimerSchedulerInitialized then return end

    if enabled then
        ActiveTimerCastBars[castBar] = true
    else
        ActiveTimerCastBars[castBar] = nil
    end

    if RefineUI.SetUpdateJobEnabled then
        RefineUI:SetUpdateJobEnabled(NAMEPLATE_CASTBAR_TIMER_JOB_KEY, next(ActiveTimerCastBars) ~= nil, false)
    end
end

local function ResetCastStyle(self)
     local data = GetCastBarData(self)
     if data then
        data.castR, data.castG, data.castB = nil, nil, nil
        data.notInterruptible = nil
        if data.timer then data.timer:SetText("") end
     end
     
     -- Reset Portrait Border using centralized logic
     local unitFrame = self:GetParent()
     if unitFrame then
         RefineUI:RefreshNameplateVisualState(unitFrame, unitFrame.unit, "CAST_RESET", {
             refreshBorders = true,
             forceCastCheck = false,
         })
     end
end

UpdateCastColor = function(self)
     local data = GetCastBarData(self)
     if not data then return end
     if data.refineColoring then return end
     data.refineColoring = true
     
     local unitFrame = self:GetParent()
     local unit = (unitFrame and unitFrame.unit) or self.unit
     
     if unit then
         local interruptSignal, hasCast = GetCastInterruptibilitySignal(unit, self)
         if not hasCast then
             ResetCastStyle(self)
             data.refineColoring = false
             return
         end

         local resolvedNotInterruptible = ReadSafeBoolean(interruptSignal)
         if resolvedNotInterruptible == nil and self.BorderShield and self.BorderShield.IsShown then
             resolvedNotInterruptible = ReadSafeBoolean(self.BorderShield:IsShown())
         end
         if resolvedNotInterruptible == nil and data.notInterruptible ~= nil then
             resolvedNotInterruptible = data.notInterruptible and true or false
         end
         if resolvedNotInterruptible ~= nil then
             data.notInterruptible = resolvedNotInterruptible
         end

         local signalApplied = ApplyCastStatusColorFromSignal(self, interruptSignal, resolvedNotInterruptible)
         local castColor, bgColor = RefineUI:GetCastColor(unit, self)
         if not castColor then
             if resolvedNotInterruptible ~= nil then
                 local colors = RefineUI.Colors.Cast
                 local bgColors = RefineUI.Colors.CastBG
                 castColor = resolvedNotInterruptible and colors.NonInterruptible or colors.Interruptible
                 bgColor = resolvedNotInterruptible and bgColors.NonInterruptible or bgColors.Interruptible
             else
                 castColor = RefineUI.Colors.Cast.Interruptible
                 bgColor = RefineUI.Colors.CastBG.Interruptible
             end
         end
          
         if castColor then
             local r, g, b = GetCastBarRenderedColor(self)
             if r == nil then
                 local effectiveColor = castColor
                 if resolvedNotInterruptible ~= nil then
                     effectiveColor = resolvedNotInterruptible and RefineUI.Colors.Cast.NonInterruptible or RefineUI.Colors.Cast.Interruptible
                 end
                 r, g, b = unpack(effectiveColor)
             end
             
             -- Cache for OnUpdate
             data.castR, data.castG, data.castB = r, g, b
             
             -- 1. Color CastBar (Status Bar)
             if not signalApplied then
                 self:SetStatusBarColor(r, g, b)
             end
             
             -- 2. Color CastBar Border (Backdrop)
              if self.border then
                local borderApplied = ApplyBorderColorFromSignal(self.border, interruptSignal, resolvedNotInterruptible)
                if not borderApplied then
                    self.border:SetBackdropBorderColor(r, g, b)
                end
              end
             
             -- 3. Update Border Colors (Centralized logic handles portrait & nameplate)
             if unitFrame and RefineUI.UpdateBorderColors then
                 RefineUI:UpdateBorderColors(unitFrame)
             end
  
             -- 4. Color Background (Using bgColor)
             if bgColor and not signalApplied then
                  -- Darken both our custom layer and Blizzard's visible Background layer.
                  ApplyBackdropDarken(data.Background, bgColor)
                  ApplyBackdropDarken(self.Background, bgColor)
              end
         else
             -- No active cast, trigger reset immediately if we were coloring
             ResetCastStyle(self)
         end
     end
     data.refineColoring = false
end

HandleCastBarEvent = function(self, event)
    local data = GetCastBarData(self)
    if data then
        if event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
            data.notInterruptible = true
        elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
            data.notInterruptible = false
        elseif event == "UNIT_SPELLCAST_START"
            or event == "UNIT_SPELLCAST_CHANNEL_START"
            or event == "UNIT_SPELLCAST_EMPOWER_START" then
            data.notInterruptible = nil
        end
    end

    UpdateCastColor(self)
end

-- Layout functions (Keep local to avoid pollution)
local function ApplyCastBarLayout(self)
    local data = GetCastBarData(self)
    if data and data.adjusting then return end
    if data then data.adjusting = true end
    
    local unitFrame = self:GetParent()
    if unitFrame then
        local cfg = C.Nameplates.CastBar
        local hpHeight = unitFrame.HealthBarsContainer and unitFrame.HealthBarsContainer:GetHeight()
        local safeHeight = 12
        
        if IsSecret(hpHeight) then
             safeHeight = 12
        elseif hpHeight and hpHeight > 0 then 
            safeHeight = hpHeight
        end
        
        self:ClearAllPoints()
        RefineUI.Point(self, "TOPLEFT", unitFrame, "TOPLEFT", 12, -(safeHeight - 4))
        RefineUI.Point(self, "TOPRIGHT", unitFrame, "TOPRIGHT", -12, -(safeHeight - 4))
        self:SetHeight(RefineUI:Scale(cfg.Height)) 
        
        -- Keep Icon hidden and text centered
        if self.Icon then self.Icon:SetAlpha(0) self.Icon:Hide() end
        if self.BorderShield then self.BorderShield:SetAlpha(0) end
        if self.Text then
            self.Text:ClearAllPoints()
            RefineUI.Point(self.Text, "BOTTOMLEFT", self, "BOTTOMLEFT", 4, 0)
            RefineUI.Font(self.Text, 10, nil, "OUTLINE") 
        end
        
        -- Check RefineHidden on frame data
        local frameData = RefineUI.NameplateData and RefineUI.NameplateData[unitFrame]
        local isHidden = (frameData and frameData.RefineHidden) or unitFrame.RefineHidden

        if isHidden then
            self:SetAlpha(0)
            self:Hide()
        end

        local baseLevel = unitFrame:GetFrameLevel()
        self:SetFrameLevel(baseLevel - 2)
        if self.border then
            self.border:SetFrameLevel(baseLevel - 1)
        end

        local sparkWidth, sparkHeight = RefineUI:Scale(5), RefineUI:Scale(30)
        if self.Spark then
            RefineUI.Size(self.Spark, sparkWidth, sparkHeight) 
            self.Spark:SetAlpha(1)
        end
        if self.Flash then
            self.Flash:ClearAllPoints()
            RefineUI.SetInside(self.Flash, self, 0, 0)
        end
    end
    
    if data then data.adjusting = false end
end

local function ApplyHealthBarLayout(self)
    -- This function handles HealthBarContainer, so we need data for IT (if we were storing it)
    -- But here it seems we just use a local property or assume it's safe. 
    -- HealthBarsContainer is a frame. Let's use a weak table for it too if we want to be 100% safe, 
    -- but for now let's just avoid `self.adjusting` on the frame directly.
    -- Or use a local table `LayoutState`.
    
    -- Using a quick local cache for layout locking to avoid taint
    -- (We can reuse CastBarData if we key by frame, or a separate one)
    local data = GetCastBarData(self) -- Will work for any frame
    if data.adjusting then return end
    data.adjusting = true
    
    local unitFrame = self:GetParent()
    if unitFrame then
        self:ClearAllPoints()
        RefineUI.Point(self, "TOPLEFT", unitFrame, "TOPLEFT", 12, 0)
        RefineUI.Point(self, "TOPRIGHT", unitFrame, "TOPRIGHT", -12, 0)

        self:SetFrameLevel(unitFrame:GetFrameLevel() + 5)
        if self.border then
            self.border:SetFrameLevel(self:GetFrameLevel())
        end
    end
    
    data.adjusting = false
end

function RefineUI:StyleNameplateCastBar(castBar)
    local data = GetCastBarData(castBar)
    if not castBar or data.isStyled then return end
    local cfg = C.Nameplates.CastBar

    RefineUI:RefreshNameplateCastColors(false)

    -- Strip defaults
    if castBar.Border then castBar.Border:SetAlpha(0) end
    if castBar.BorderShield then castBar.BorderShield:SetAlpha(0) end
    if castBar.TextBorder then castBar.TextBorder:SetAlpha(0) end

    -- Texture
    castBar:SetStatusBarTexture(TEX_BAR)
    castBar:SetStatusBarDesaturated(true)

    RefineUI:HookOnce(BuildNameplateCastHookKey(castBar, "SetStatusBarTexture"), castBar, "SetStatusBarTexture", function(self, tex)
        if (not IsAccessibleValue(tex)) or tex ~= TEX_BAR then
            self:SetStatusBarTexture(TEX_BAR)
            self:SetStatusBarDesaturated(true)
        end
    end)
    
    -- Border
    RefineUI.CreateBorder(castBar, 6, 6, 12)
    
    -- Icon
    if castBar.Icon then
         castBar.Icon:SetAlpha(0)
         castBar.Icon:Hide()
    end
    if castBar.BorderShield then
        RefineUI:HookOnce(
            BuildNameplateCastHookKey(castBar.BorderShield, "SetShown"),
            castBar.BorderShield,
            "SetShown",
            function(shield)
                local shieldShown = ReadSafeBoolean(shield:IsShown())
                if shieldShown ~= nil then
                    data.notInterruptible = shieldShown
                end
                UpdateCastColor(castBar)
            end
        )
    end

    -- Background
    if not data.Background then
        data.Background = castBar:CreateTexture(nil, "BACKGROUND")
        data.Background:SetAllPoints(castBar)
        data.Background:SetTexture(TEX_BAR)
    end

    -- Timer
    if not data.timer then
        data.timer = castBar:CreateFontString(nil, "OVERLAY")
        RefineUI.Font(data.timer, 12, nil, "OUTLINE")
        RefineUI.Point(data.timer, "BOTTOMRIGHT", castBar, "BOTTOMRIGHT", -2, 0)
    end

    -- Timer updates: prefer centralized scheduler, fallback to per-castbar OnUpdate.
    if not data.timerDriverInitialized then
        EnsureCastBarTimerScheduler()
        if castBarTimerSchedulerInitialized then
            data.timerUsesScheduler = true
        else
            data.timerUsesScheduler = false
            castBar:HookScript("OnUpdate", UpdateCastTime)
        end
        data.timerDriverInitialized = true
    end

    -- Hooks
    castBar:HookScript("OnShow", UpdateCastColor)
    castBar:HookScript("OnHide", ResetCastStyle)
    castBar:HookScript("OnEvent", HandleCastBarEvent)
    castBar:HookScript("OnShow", function(self)
        UpdateCastTime(self, NAMEPLATE_CASTBAR_TIMER_INTERVAL)
        if data.timerUsesScheduler and SetCastBarTimerActive then
            SetCastBarTimerActive(self, IsCastTimerRelevant(self))
        end
    end)
    castBar:HookScript("OnHide", function(self)
        if data.timerUsesScheduler and SetCastBarTimerActive then
            SetCastBarTimerActive(self, false)
        end
    end)
    
    -- Layout Hooks
    RefineUI:HookOnce(BuildNameplateCastHookKey(castBar, "SetPoint"), castBar, "SetPoint", ApplyCastBarLayout)
    castBar:HookScript("OnShow", ApplyCastBarLayout)

    -- Hook HealthBarsContainer
    local unitFrame = castBar:GetParent()
    if unitFrame and unitFrame.HealthBarsContainer then 
        RefineUI:HookOnce(
            BuildNameplateCastHookKey(unitFrame.HealthBarsContainer, "SetPoint"),
            unitFrame.HealthBarsContainer,
            "SetPoint",
            ApplyHealthBarLayout
        )
    end
    
    ApplyCastBarLayout(castBar)
    if unitFrame and unitFrame.HealthBarsContainer then
        ApplyHealthBarLayout(unitFrame.HealthBarsContainer)
    end
    
    UpdateCastColor(castBar)
    

    -- Register events dynamically when unit changes
    -- Since nameplates reuse frames, we need to update the unit registration.
    
    castBar.UpdateUnitEvents = function(self, unit)
        local unitFrame = self:GetParent()
        local resolvedUnit = unit
        if not IsUsableUnitToken(resolvedUnit) then
            resolvedUnit = unitFrame and unitFrame.unit or nil
        end
        if not IsUsableUnitToken(resolvedUnit) then
            return
        end

         if data.unitEventFrame then
              data.unitEventFrame:UnregisterAllEvents()
              data.unitEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTIBLE", resolvedUnit)
             data.unitEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", resolvedUnit)
             data.unitEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", resolvedUnit)
             data.unitEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", resolvedUnit)
             data.unitEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", resolvedUnit)
             data.unitEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", resolvedUnit)
             data.unitEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", resolvedUnit)
             data.unitEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", resolvedUnit)
             data.unitEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", resolvedUnit)
               data.unitEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", resolvedUnit)
               data.unitEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", resolvedUnit)
          end
        local frameData = RefineUI.NameplateData and RefineUI.NameplateData[unitFrame]
        if frameData then
            if IsUsableUnitToken(resolvedUnit) then
                frameData.isTarget = SafeUnitIsUnit("target", resolvedUnit)
            else
                frameData.isTarget = nil
            end
        end
        data.lastUnitAlpha = nil
        data.notInterruptible = nil
        ResetCastStyle(self)
        
        -- Immediate refresh for the new unit/reuse
        UpdateCastColor(self)
        UpdateCastTime(self, NAMEPLATE_CASTBAR_TIMER_INTERVAL)
        if data.timerUsesScheduler and SetCastBarTimerActive then
            SetCastBarTimerActive(self, IsCastTimerRelevant(self))
        end
    end
    
    local eventFrame = data.unitEventFrame or CreateFrame("Frame", nil, castBar)
    data.unitEventFrame = eventFrame

    eventFrame:SetScript("OnEvent", function(evFrame, event, unit)
         -- Optimization: Filter by unit early
         if not IsUsableUnitToken(unit) or not IsUsableUnitToken(unitFrame.unit) then return end
         if unit ~= unitFrame.unit then return end

         if event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
            if IsCastActive(unit, castBar) then
                data.notInterruptible = true
                UpdateCastColor(castBar)
            end
         elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
            -- Ignore late INTERRUPTIBLE flips while cast is already ending/interrupted (e.g., stun stop).
            if IsCastActive(unit, castBar) and not IsSafeBarType(castBar, "interrupted") then
                data.notInterruptible = false
                UpdateCastColor(castBar)
            end
         elseif event == "UNIT_SPELLCAST_START"
            or event == "UNIT_SPELLCAST_CHANNEL_START"
            or event == "UNIT_SPELLCAST_EMPOWER_START" then
            -- New cast/channel can reuse frame state; clear stale interruptibility first.
            data.notInterruptible = nil
            UpdateCastColor(castBar)
         elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
            EmptyCastBar(castBar)
            ResetCastStyle(castBar)
            C_Timer.After(0, function()
                if castBar and IsSafeBarType(castBar, "interrupted") then
                    EmptyCastBar(castBar)
                end
            end)
         elseif event == "UNIT_SPELLCAST_STOP" or 
            event == "UNIT_SPELLCAST_FAILED" or 
            event == "UNIT_SPELLCAST_SUCCEEDED" or
            event == "UNIT_SPELLCAST_CHANNEL_STOP" or
            event == "UNIT_SPELLCAST_EMPOWER_STOP" then
            -- Force reset and color reload for these events
            ResetCastStyle(castBar)
         else
            UpdateCastColor(castBar)
         end

         RefineUI:RefreshNameplateVisualState(unitFrame, unit, event, {
             refreshCrowdControl = true,
             refreshPortrait = true,
         })

         if data.timerUsesScheduler and SetCastBarTimerActive then
             SetCastBarTimerActive(castBar, IsCastTimerRelevant(castBar))
         end
    end)

    data.isStyled = true
end
