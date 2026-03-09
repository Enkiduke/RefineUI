----------------------------------------------------------------------------------------
-- Nameplates Component: CastBars
-- Description: Extracted CastBar logic with performance optimizations
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Nameplates = RefineUI:GetModule("Nameplates")
if not Nameplates then
    return
end
local Config = RefineUI.Config

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
local format = string.format
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local UnitCastingDuration = UnitCastingDuration
local UnitChannelDuration = UnitChannelDuration
local C_NamePlate = C_NamePlate
local CreateColor = CreateColor
local UnitClassFromGUID = C_PlayerInfo and C_PlayerInfo.UnitClassFromGUID or UnitClassFromGUID
local type = type
local tonumber = tonumber
local pairs = pairs
local RAID_CLASS_COLORS = RAID_CLASS_COLORS

----------------------------------------------------------------------------------------
-- Texture Cache
----------------------------------------------------------------------------------------
local MediaTextures = RefineUI.Media.Textures
local TEX_BAR = MediaTextures.HealthBar
local CASTBAR_BACKDROP_DARKEN = 0.5
local NameplatesUtil = RefineUI.NameplatesUtil
local IsSecret = NameplatesUtil.IsSecret
local HasValue = NameplatesUtil.HasValue
local IsAccessibleValue = NameplatesUtil.IsAccessibleValue
local ReadSafeBoolean = NameplatesUtil.ReadSafeBoolean
local IsUsableUnitToken = NameplatesUtil.IsUsableUnitToken
local BuildHookKey = NameplatesUtil.BuildHookKey
local BuildNameplateCastHookKey = function(owner, method)
    return BuildHookKey("NameplatesCastBars", owner, method)
end

local DEFAULT_INTERRUPTIBLE_CAST_COLOR = { 1, 0.7, 0 }
local DEFAULT_NON_INTERRUPTIBLE_CAST_COLOR = { 1, 0.2, 0.2 }
local CAST_BG_MULTIPLIER = 0.3
local INTERRUPTED = INTERRUPTED or "Interrupted"

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

local function ApplyCastStatusColorFromSignal(castBar, signal, resolvedNotInterruptible)
    if not castBar then
        return false
    end

    local colors = RefineUI.Colors.Cast
    local bgColors = RefineUI.Colors.CastBG

    local statusTexture = castBar.GetStatusBarTexture and castBar:GetStatusBarTexture()
    if signal ~= nil and statusTexture and statusTexture.SetVertexColorFromBoolean then
        local colorObjs = RefineUI.Colors.CastColorObj
        statusTexture:SetVertexColorFromBoolean(
            signal,
            colorObjs and colorObjs.NonInterruptible or CreateColorFromArray(colors.NonInterruptible),
            colorObjs and colorObjs.Interruptible or CreateColorFromArray(colors.Interruptible)
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
            local bgObjs = RefineUI.Colors.CastColorObj
            background:SetVertexColorFromBoolean(
                signal,
                bgObjs and bgObjs.NonInterruptibleBG or CreateColorFromArray(bgColors.NonInterruptible, CASTBAR_BACKDROP_DARKEN),
                bgObjs and bgObjs.InterruptibleBG or CreateColorFromArray(bgColors.Interruptible, CASTBAR_BACKDROP_DARKEN)
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
    local colorObjs = RefineUI.Colors.CastColorObj
    local trueColor = colorObjs and colorObjs.NonInterruptible or CreateColorFromArray(colors.NonInterruptible)
    local falseColor = colorObjs and colorObjs.Interruptible or CreateColorFromArray(colors.Interruptible)

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

IsCastActive = function(unit, castBar)
    return NameplatesUtil.IsCastActive(unit, castBar)
end

local function SyncNameplateCastAlphaState(castBar, unitFrame, unit, forceRefresh)
    if not unitFrame then
        return
    end

    RefineUI.NameplateData = RefineUI.NameplateData or {}
    local frameData = RefineUI.NameplateData[unitFrame]
    if not frameData then
        frameData = {}
        RefineUI.NameplateData[unitFrame] = frameData
    end

    local resolvedUnit = unit
    if not IsUsableUnitToken(resolvedUnit) then
        resolvedUnit = unitFrame.unit
    end
    if not IsUsableUnitToken(resolvedUnit) then
        resolvedUnit = nil
    end

    local isCastingNow = IsCastActive(resolvedUnit, castBar)
    if frameData.isCasting ~= isCastingNow then
        frameData.isCasting = isCastingNow
        if RefineUI.UpdateTarget then
            RefineUI:UpdateTarget(unitFrame)
        end
    end
end

local UpdateCastColor
local HandleCastBarEvent
local GetCastInterruptibilitySignal

local CAST_STATE_REFRESH_EVENTS = {
    UNIT_SPELLCAST_START = true,
    UNIT_SPELLCAST_STOP = true,
    UNIT_SPELLCAST_FAILED = true,
    UNIT_SPELLCAST_INTERRUPTED = true,
    UNIT_SPELLCAST_SUCCEEDED = true,
    UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_CHANNEL_STOP = true,
    UNIT_SPELLCAST_EMPOWER_START = true,
    UNIT_SPELLCAST_EMPOWER_STOP = true,
}

local CAST_BORDER_REFRESH_EVENTS = {
    UNIT_SPELLCAST_INTERRUPTIBLE = true,
    UNIT_SPELLCAST_NOT_INTERRUPTIBLE = true,
}

function RefineUI:RefreshNameplateCastColors(refreshExisting)
    self.Colors = self.Colors or {}
    self.Colors.Cast = self.Colors.Cast or {}
    self.Colors.CastBG = self.Colors.CastBG or {}

    local configColors = Config
        and Config.Nameplates
        and Config.Nameplates.CastBar
        and Config.Nameplates.CastBar.Colors

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

    -- Pre-cache CreateColor objects to avoid per-call allocation
    self.Colors.CastColorObj = self.Colors.CastColorObj or {}
    self.Colors.CastColorObj.Interruptible = CreateColor(unpack(interruptibleColor))
    self.Colors.CastColorObj.NonInterruptible = CreateColor(unpack(nonInterruptibleColor))
    self.Colors.CastColorObj.InterruptibleBG = CreateColor(
        interruptibleColor[1] * CASTBAR_BACKDROP_DARKEN,
        interruptibleColor[2] * CASTBAR_BACKDROP_DARKEN,
        interruptibleColor[3] * CASTBAR_BACKDROP_DARKEN,
        1
    )
    self.Colors.CastColorObj.NonInterruptibleBG = CreateColor(
        nonInterruptibleColor[1] * CASTBAR_BACKDROP_DARKEN,
        nonInterruptibleColor[2] * CASTBAR_BACKDROP_DARKEN,
        nonInterruptibleColor[3] * CASTBAR_BACKDROP_DARKEN,
        1
    )

    if refreshExisting ~= true or not C_NamePlate or type(C_NamePlate.GetNamePlates) ~= "function" then
        return
    end

    for _, nameplate in pairs(C_NamePlate.GetNamePlates()) do
        local unitFrame = nameplate and nameplate.UnitFrame
        local castBar = unitFrame and (unitFrame.castBar or unitFrame.CastBar)
        if castBar then
            UpdateCastColor(castBar, true)
        end
    end
end

----------------------------------------------------------------------------------------
-- Functions
----------------------------------------------------------------------------------------

function RefineUI:GetCastColor(unit, castBar)
    if IsSafeBarType(castBar, "interrupted") then
        return nil
    end

    local interruptSignal, hasCast = GetCastInterruptibilitySignal(unit, castBar)
    if not hasCast then
        return nil
    end

    local notInt = ReadSafeBoolean(interruptSignal)
    local colors = RefineUI.Colors.Cast
    local bgColors = RefineUI.Colors.CastBG

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

local function ResetCastStyle(self)
     local data = GetCastBarData(self)
     if data then
        data.castR, data.castG, data.castB = nil, nil, nil
        data.notInterruptible = nil
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

local function GetCastBarInterruptibilitySignal(castBar)
    if not castBar then
        return nil
    end

    local isInterruptable = SafeCastBarIsInterruptable(castBar)
    if isInterruptable ~= nil then
        return not isInterruptable
    end

    local barType = GetSafeBarType(castBar)
    if barType == "uninterruptable" or barType == "uninterruptible" then
        return true
    end

    local castBarNotInterruptible = ReadSafeBoolean(castBar.notInterruptible)
    if castBarNotInterruptible ~= nil then
        return castBarNotInterruptible
    end

    if castBar.BorderShield and castBar.BorderShield.IsShown then
        local shieldShown = ReadSafeBoolean(castBar.BorderShield:IsShown())
        if shieldShown ~= nil then
            return shieldShown
        end
    end

    local data = GetCastBarData(castBar)
    if data and data.notInterruptible ~= nil then
        return data.notInterruptible
    end

    return nil
end

GetCastInterruptibilitySignal = function(unit, castBar)
    local hasCast = IsCastActive(unit, castBar)
    if not hasCast then
        return nil, false
    end

    local castBarSignal = GetCastBarInterruptibilitySignal(castBar)
    if castBarSignal ~= nil then
        return castBarSignal, true
    end

    if not unit then
        return nil, true
    end

    local castName, _, _, _, _, _, _, apiNotInterruptible = UnitCastingInfo(unit)
    if HasValue(castName) then
        return apiNotInterruptible, true
    end

    local channelName
    channelName, _, _, _, _, _, apiNotInterruptible = UnitChannelInfo(unit)
    if HasValue(channelName) then
        return apiNotInterruptible, true
    end

    return nil, true
end

local function RefreshCastVisualState(self, event, unitFrame, unit)
    if not unitFrame or not RefineUI.RefreshNameplateVisualState then
        return
    end

    local refreshState = CAST_STATE_REFRESH_EVENTS[event] == true
    local refreshBorders = refreshState or CAST_BORDER_REFRESH_EVENTS[event] == true
    if not refreshState and not refreshBorders then
        return
    end

    RefineUI:RefreshNameplateVisualState(unitFrame, unit, event, {
        refreshCrowdControl = refreshState,
        refreshPortrait = refreshState,
        refreshBorders = refreshBorders,
    })
end

UpdateCastColor = function(self, refreshBorders)
     local data = GetCastBarData(self)
     if not data then return end
     if data.refineColoring then return end
     data.refineColoring = true
     
     local unitFrame = self:GetParent()
     local unit = (unitFrame and unitFrame.unit) or self.unit
     
     if unit or IsCastActive(nil, self) then
         local interruptSignal, hasCast = GetCastInterruptibilitySignal(unit, self)
         if not hasCast then
             data.refineColoring = false
             if refreshBorders then
                 ResetCastStyle(self)
             else
                 data.castR, data.castG, data.castB = nil, nil, nil
                 data.notInterruptible = nil
             end
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
             
             -- Cache the rendered cast color for other nameplate visuals.
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
             if refreshBorders and unitFrame and RefineUI.UpdateBorderColors then
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

local function ClearCastTimeText(castTimeText)
    if not castTimeText then
        return
    end

    RefineUI:SetFontStringValue(castTimeText, nil, {
        emptyText = "",
    })
    castTimeText:Hide()
end

local function ForceHideCastBar(castBar)
    if not castBar then return end

    -- Stop Blizzard fade/interrupt animations
    if castBar.HoldFadeOutAnim and castBar.HoldFadeOutAnim.Stop then
        pcall(castBar.HoldFadeOutAnim.Stop, castBar.HoldFadeOutAnim)
    end
    if castBar.FadeOutAnim and castBar.FadeOutAnim.Stop then
        pcall(castBar.FadeOutAnim.Stop, castBar.FadeOutAnim)
    end
    if castBar.FlashAnim and castBar.FlashAnim.Stop then
        pcall(castBar.FlashAnim.Stop, castBar.FlashAnim)
    end
    if castBar.InterruptShakeAnim and castBar.InterruptShakeAnim.Stop then
        pcall(castBar.InterruptShakeAnim.Stop, castBar.InterruptShakeAnim)
    end
    if castBar.InterruptGlowAnim and castBar.InterruptGlowAnim.Stop then
        pcall(castBar.InterruptGlowAnim.Stop, castBar.InterruptGlowAnim)
    end
    if castBar.InterruptSparkAnim and castBar.InterruptSparkAnim.Stop then
        pcall(castBar.InterruptSparkAnim.Stop, castBar.InterruptSparkAnim)
    end

    -- Immediately hide
    castBar:SetAlpha(0)
    castBar:Hide()

    -- Clear timer text
    local data = GetCastBarData(castBar)
    local castTimeText = data and data.castTimeText
    if castTimeText then
        ClearCastTimeText(castTimeText)
    end
end

local CAST_END_EVENTS = {
    UNIT_SPELLCAST_INTERRUPTED = true,
    UNIT_SPELLCAST_FAILED = true,
    UNIT_SPELLCAST_STOP = true,
    UNIT_SPELLCAST_CHANNEL_STOP = true,
    UNIT_SPELLCAST_EMPOWER_STOP = true,
}

HandleCastBarEvent = function(self, event, ...)
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

    UpdateCastColor(self, false)

    local unitFrame = self:GetParent()
    local unit = unitFrame and unitFrame.unit
    if unitFrame then
        RefreshCastVisualState(self, event, unitFrame, unit)
        SyncNameplateCastAlphaState(self, unitFrame, unit)

        -- Instant-hide cast bar when a cast ends and CC is active on this unit
        if CAST_END_EVENTS[event] then
            local frameData = RefineUI.NameplateData and RefineUI.NameplateData[unitFrame]
            if frameData and frameData.CrowdControlActive then
                ForceHideCastBar(self)
            end
        end

        -- Class-colored "Interrupted" text (no player name)
        if event == "UNIT_SPELLCAST_INTERRUPTED" then
            local _unit, _castID, _spellID, interruptedByGUID = ...
            local castText = self.Text
            if castText and castText.SetText and castText.SetTextColor then
                castText:SetText(INTERRUPTED)
                if IsAccessibleValue(interruptedByGUID) and interruptedByGUID and UnitClassFromGUID then
                    local _, classFilename = UnitClassFromGUID(interruptedByGUID)
                    if IsAccessibleValue(classFilename) and classFilename then
                        local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFilename]
                        if classColor then
                            castText:SetTextColor(classColor.r, classColor.g, classColor.b)
                        end
                    end
                end
            end
        end
    end
end

local function EnsureCastTimeText(castBar)
    if not castBar then
        return nil
    end

    local data = GetCastBarData(castBar)
    if not data then
        return nil
    end

    local castTimeText = data.castTimeText
    if not castTimeText then
        castTimeText = castBar:CreateFontString(nil, "OVERLAY")
        RefineUI.Font(castTimeText, 12, nil, "OUTLINE")
        data.castTimeText = castTimeText
    end

    RefineUI.Font(castTimeText, 12, nil, "OUTLINE")
    castTimeText:ClearAllPoints()
    RefineUI.Point(castTimeText, "BOTTOMRIGHT", castBar, "BOTTOMRIGHT", -2, 0)
    return castTimeText
end

local function TryFormatRemainingDuration(castTimeText, duration)
    if not castTimeText or not duration then
        return false
    end
    if not duration.EvaluateRemainingDuration or not RefineUI.GetLinearCurve then
        return false
    end

    local ok, remaining = pcall(duration.EvaluateRemainingDuration, duration, RefineUI.GetLinearCurve())
    if not ok or not HasValue(remaining) then
        return false
    end

    -- SetFormattedText is AllowedWhenTainted — safe even if remaining is secret
    local fmtOk = pcall(castTimeText.SetFormattedText, castTimeText, "%.1f", remaining)
    if fmtOk then
        castTimeText:Show()
        return true
    end

    return false
end

local function UpdateCustomCastTimeText(castBar)
    local data = GetCastBarData(castBar)
    local castTimeText = data and data.castTimeText
    if not castTimeText then
        return
    end

    local isCasting = ReadSafeBoolean(castBar.casting) == true
    local isChanneling = ReadSafeBoolean(castBar.channeling) == true
    local isReverseChanneling = ReadSafeBoolean(castBar.reverseChanneling) == true
    if not (isCasting or isChanneling or isReverseChanneling) then
        ClearCastTimeText(castTimeText)
        return
    end

    -- Path 1: Duration object from UnitCastingDuration / UnitChannelDuration
    local unitFrame = castBar:GetParent()
    local unit = (unitFrame and unitFrame.unit) or castBar.unit
    if IsUsableUnitToken(unit) then
        local duration
        if (isChanneling or isReverseChanneling) and UnitChannelDuration then
            duration = UnitChannelDuration(unit)
        elseif UnitCastingDuration then
            duration = UnitCastingDuration(unit)
        end

        if HasValue(duration) and TryFormatRemainingDuration(castTimeText, duration) then
            return
        end
    end

    -- Path 2: Bar values — arithmetic may involve secrets, wrap in pcall
    local ok, seconds = pcall(function()
        local minValue, maxValue = castBar:GetMinMaxValues()
        local currentValue = castBar:GetValue()
        if isCasting or isReverseChanneling then
            return math.max(minValue, maxValue - currentValue)
        else
            return math.max(minValue, currentValue)
        end
    end)

    if ok and HasValue(seconds) then
        -- SetFormattedText is AllowedWhenTainted — safe even if seconds is secret
        local fmtOk = pcall(castTimeText.SetFormattedText, castTimeText, "%.1f", seconds)
        if fmtOk then
            castTimeText:Show()
            return
        end
    end

    ClearCastTimeText(castTimeText)
end

-- Layout functions
local function ApplyCastBarLayout(self)
    local data = GetCastBarData(self)
    if data and data.adjusting then return end
    if data then data.adjusting = true end
    
    local unitFrame = self:GetParent()
    if unitFrame then
        local cfg = Config.Nameplates.CastBar
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
        local castTimeText = EnsureCastTimeText(self)
        if castTimeText then
            castTimeText:ClearAllPoints()
            RefineUI.Point(castTimeText, "BOTTOMRIGHT", self, "BOTTOMRIGHT", -2, 0)
            RefineUI.Font(castTimeText, 12, nil, "OUTLINE")
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
    -- Reuse the registry for layout reentry protection instead of frame fields.
    local data = GetCastBarData(self)
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
    local cfg = Config.Nameplates.CastBar

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
                UpdateCastColor(castBar, true)
            end
        )
    end

    -- Background
    if not data.Background then
        data.Background = castBar:CreateTexture(nil, "BACKGROUND")
        data.Background:SetAllPoints(castBar)
        data.Background:SetTexture(TEX_BAR)
    end
    EnsureCastTimeText(castBar)

    -- Hooks
    RefineUI:HookOnce(
        BuildNameplateCastHookKey(castBar, "UpdateCastTimeText"),
        castBar,
        "UpdateCastTimeText",
        UpdateCustomCastTimeText
    )
    RefineUI:HookOnce(
        BuildNameplateCastHookKey(castBar, "UpdateCastTimeTextShown"),
        castBar,
        "UpdateCastTimeTextShown",
        UpdateCustomCastTimeText
    )
    RefineUI:HookScriptOnce(
        BuildNameplateCastHookKey(castBar, "OnEvent"),
        castBar,
        "OnEvent",
        HandleCastBarEvent
    )
    RefineUI:HookScriptOnce(
        BuildNameplateCastHookKey(castBar, "OnShow:State"),
        castBar,
        "OnShow",
        function(self)
        UpdateCastColor(self, true)
        UpdateCustomCastTimeText(self)
        local parentFrame = self:GetParent()
        SyncNameplateCastAlphaState(self, parentFrame, parentFrame and parentFrame.unit, true)
        end
    )
    RefineUI:HookScriptOnce(
        BuildNameplateCastHookKey(castBar, "OnHide:State"),
        castBar,
        "OnHide",
        function(self)
        ResetCastStyle(self)
        local hiddenText = EnsureCastTimeText(self)
        if hiddenText then
            hiddenText:SetText("")
            hiddenText:Hide()
        end
        local parentFrame = self:GetParent()
        SyncNameplateCastAlphaState(self, parentFrame, parentFrame and parentFrame.unit, true)
        end
    )
    
    -- Layout Hooks
    RefineUI:HookOnce(BuildNameplateCastHookKey(castBar, "SetPoint"), castBar, "SetPoint", ApplyCastBarLayout)
    RefineUI:HookScriptOnce(
        BuildNameplateCastHookKey(castBar, "OnShow:Layout"),
        castBar,
        "OnShow",
        ApplyCastBarLayout
    )

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
    
    UpdateCastColor(castBar, true)
    SyncNameplateCastAlphaState(castBar, unitFrame, unitFrame and unitFrame.unit, true)

    data.isStyled = true
end

