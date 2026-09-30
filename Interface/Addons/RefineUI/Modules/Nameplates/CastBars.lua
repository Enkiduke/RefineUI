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
local unpack = unpack
local math = math
local pcall = pcall
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
local lower = string.lower
local RAID_CLASS_COLORS = RAID_CLASS_COLORS

----------------------------------------------------------------------------------------
-- Texture Cache
----------------------------------------------------------------------------------------
local MediaTextures = RefineUI.Media.Textures
local TEX_BAR = MediaTextures.HealthBar
local NORMALIZED_TEX_BAR = type(TEX_BAR) == "string" and lower(TEX_BAR) or nil
local CASTBAR_BACKDROP_DARKEN = 0.5
local NameplatesUtil = RefineUI.NameplatesUtil
local IsSecret = NameplatesUtil.IsSecret
local HasValue = NameplatesUtil.HasValue
local IsAccessibleValue = NameplatesUtil.IsAccessibleValue
local ReadSafeBoolean = NameplatesUtil.ReadSafeBoolean
local IsUsableUnitToken = NameplatesUtil.IsUsableUnitToken
local IsCastBarActiveOnly = NameplatesUtil.IsCastBarActive
local GetCastBarUnitFrame = NameplatesUtil.GetCastBarUnitFrame
local IsRuntimeSuppressedNameplate = NameplatesUtil.IsNameOnly
local BuildHookKey = NameplatesUtil.BuildHookKey
local BuildNameplateCastHookKey = function(owner, method)
    return BuildHookKey("NameplatesCastBars", owner, method)
end

local DEFAULT_INTERRUPTIBLE_CAST_COLOR = { 1, 0.7, 0 }
local DEFAULT_NON_INTERRUPTIBLE_CAST_COLOR = { 1, 0.2, 0.2 }
local INTERRUPTED_CAST_COLOR = { 0.45, 0.45, 0.45 }
local CAST_BG_MULTIPLIER = 0.3
local INTERRUPTED = INTERRUPTED or "Interrupted"
local EMPTY_TEXT_OPTS = { emptyText = "" }

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

local function SetCastBarVisualAlpha(castBar, alpha)
    if not castBar or type(alpha) ~= "number" then
        return
    end

    castBar:SetAlpha(alpha)

    local fadeWidgets = castBar.additionalFadeWidgets
    if not fadeWidgets then
        return
    end

    for widget in pairs(fadeWidgets) do
        if widget and widget.SetAlpha then
            widget:SetAlpha(alpha)
        end
    end
end

local function EnforceNameOnlyCastBarHidden(castBar)
    if not castBar or not castBar.GetParent then
        return false
    end

    if not IsRuntimeSuppressedNameplate(GetCastBarUnitFrame(castBar)) then
        return false
    end

    SetCastBarVisualAlpha(castBar, 0)
    return true
end

function Nameplates:SetCastBarVisualAlpha(castBar, alpha)
    SetCastBarVisualAlpha(castBar, alpha)
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

local function NormalizeTextureToken(textureValue)
    if not IsAccessibleValue(textureValue) or type(textureValue) ~= "string" then
        return nil
    end

    return lower(textureValue)
end

local function GetInterruptibilityFromTexture(texturePath)
    texturePath = NormalizeTextureToken(texturePath)
    if texturePath == nil then
        return nil
    end

    -- Blizzard's native fill atlas still tells us whether the cast was interruptible
    -- before we replace the texture with our own statusbar art.
    if texturePath == "" then
        return false
    end

    if texturePath:find("uninterruptable", 1, true) or texturePath:find("uninterruptible", 1, true) then
        return true
    end

    if texturePath:find("ui-castingbar-filling-", 1, true) then
        return false
    end

    return nil
end

local function ClearCachedCastInterruptibility(data, clearNativeStatusBarTexture)
    if not data then
        return
    end

    data.cachedNotInterruptible = nil
    if clearNativeStatusBarTexture == true then
        data.nativeStatusBarTexture = nil
    end
end

local function ClearCastInterruptibilityState(data)
    ClearCachedCastInterruptibility(data, true)
end

local function IsSafeBarType(castBar, expectedType)
    local barType = GetSafeBarType(castBar)
    return barType ~= nil and barType == expectedType
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

local function GetCastBarStatusTexture(castBar)
    if not castBar or not castBar.GetStatusBarTexture then
        return nil
    end

    return castBar:GetStatusBarTexture()
end

local function CacheNativeStatusBarTextureValue(data, textureValue)
    if not data then
        return
    end

    local normalizedTexture = NormalizeTextureToken(textureValue)
    if normalizedTexture == nil then
        return
    end
    if NORMALIZED_TEX_BAR ~= nil and normalizedTexture == NORMALIZED_TEX_BAR then
        return
    end

    data.nativeStatusBarTexture = textureValue
end

local function SnapshotNativeStatusBarTexture(castBar, data)
    if not castBar or not data then
        return
    end

    local statusTexture = GetCastBarStatusTexture(castBar)
    if not statusTexture then
        return
    end

    if statusTexture.GetAtlas then
        local ok, atlas = pcall(statusTexture.GetAtlas, statusTexture)
        if ok and atlas ~= nil then
            CacheNativeStatusBarTextureValue(data, atlas)
        end
    end

    if data.nativeStatusBarTexture ~= nil then
        return
    end

    if statusTexture.GetTexture then
        local ok, textureValue = pcall(statusTexture.GetTexture, statusTexture)
        if ok and textureValue ~= nil then
            CacheNativeStatusBarTextureValue(data, textureValue)
        end
    end
end

local function EnsureCastBarTextureDesaturation(castBar)
    if not castBar then
        return nil
    end

    local statusTexture = GetCastBarStatusTexture(castBar)
    if statusTexture and statusTexture.SetDesaturated then
        statusTexture:SetDesaturated(true)
    elseif castBar.SetStatusBarDesaturated then
        castBar:SetStatusBarDesaturated(true)
    end

    return statusTexture
end

local function ApplyCastStatusColorDirect(castBar, color)
    if not castBar or not color then
        return false
    end

    local statusTexture = EnsureCastBarTextureDesaturation(castBar)
    if statusTexture and statusTexture.SetVertexColor then
        statusTexture:SetVertexColor(unpack(color))
        return true
    end

    if castBar.SetStatusBarColor then
        castBar:SetStatusBarColor(unpack(color))
        return true
    end

    return false
end

local function ApplyCastStatusColorFromSignal(castBar, signal, resolvedNotInterruptible)
    if not castBar then
        return false
    end

    local colors = RefineUI.Colors.Cast
    local bgColors = RefineUI.Colors.CastBG

    local statusTexture = EnsureCastBarTextureDesaturation(castBar)
    if signal ~= nil and statusTexture and statusTexture.SetVertexColorFromBoolean then
        local colorObjs = RefineUI.Colors.CastColorObj
        statusTexture:SetVertexColorFromBoolean(
            signal,
            colorObjs and colorObjs.NonInterruptible or CreateColorFromArray(colors.NonInterruptible),
            colorObjs and colorObjs.Interruptible or CreateColorFromArray(colors.Interruptible)
        )
    elseif resolvedNotInterruptible ~= nil then
        local baseColor = resolvedNotInterruptible and colors.NonInterruptible or colors.Interruptible
        if not ApplyCastStatusColorDirect(castBar, baseColor) then
            return false
        end
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

    local frameData = Nameplates:GetNameplateData(unitFrame)
    if frameData.RefineHidden == true then
        if frameData.isCasting ~= false or forceRefresh == true then
            frameData.isCasting = false
            RefineUI:UpdateTarget(unitFrame)
        end
        return
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
        RefineUI:UpdateTarget(unitFrame)
    end
end

local UpdateCastColor
local HandleCastBarEvent
local GetCastInterruptibilitySignal
local GetResolvedCastBarInterruptibility

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

-- CC presence is secret in 12.1, so cast transitions always re-evaluate the
-- CC display's hide-while-casting state when that option is on.
local function ShouldRefreshCrowdControlForCastState()
    local crowdControlConfig = Config
        and Config.Nameplates
        and (Config.Nameplates.CrowdControl or Config.Nameplates.CrowdControlTest)
    if not crowdControlConfig or crowdControlConfig.Enable == false then
        return false
    end

    return crowdControlConfig.HideWhileCasting ~= false
end

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
        local castBar = NameplatesUtil.GetNameplateCastBar(unitFrame)
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
    if notInt == nil then
        notInt = GetResolvedCastBarInterruptibility(castBar)
    end
    if notInt == nil then
        return nil
    end

    local colors = RefineUI.Colors.Cast
    local bgColors = RefineUI.Colors.CastBG

    if notInt then
        return colors.NonInterruptible, bgColors.NonInterruptible
    end

    return colors.Interruptible, bgColors.Interruptible
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
        ClearCastInterruptibilityState(data)
     end
     
     -- Reset Portrait Border using centralized logic
     -- RefineHidden is true for name-only plates and nil until RefreshAddedNameplate runs.
     -- Blizzard's OnUnitSet resets the cast bar before NAME_PLATE_UNIT_ADDED reaches us,
     -- and the add handler refreshes the portrait, CC, and borders itself.
     local unitFrame = GetCastBarUnitFrame(self)
     local frameData = unitFrame and RefineUI.NameplateData[unitFrame]
     if not frameData or frameData.RefineHidden ~= false then
         return
     end
     RefineUI:RefreshNameplateVisualState(unitFrame, unitFrame.unit, "CAST_RESET",
         ShouldRefreshCrowdControlForCastState(), true, true, false)
end

local function GetLiveUnitCastInterruptibilitySignal(unit)
    if not IsUsableUnitToken(unit) then
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

    return nil, false
end

GetResolvedCastBarInterruptibility = function(castBar)
    if not castBar then
        return nil
    end

    local data = GetCastBarData(castBar)
    if data and data.cachedNotInterruptible ~= nil then
        return data.cachedNotInterruptible
    end

    if castBar.BorderShield and castBar.BorderShield.IsShown then
        local shieldShown = ReadSafeBoolean(castBar.BorderShield:IsShown())
        if shieldShown ~= nil then
            return shieldShown
        end
    end

    local barType = GetSafeBarType(castBar)
    if barType == "uninterruptable" or barType == "uninterruptible" then
        return true
    end
    if barType == "standard"
        or barType == "channel"
        or barType == "empowered"
        or barType == "applyingcrafting" then
        return false
    end

    if data and data.nativeStatusBarTexture ~= nil then
        local textureNotInterruptible = GetInterruptibilityFromTexture(data.nativeStatusBarTexture)
        if textureNotInterruptible ~= nil then
            return textureNotInterruptible
        end
    end

    return nil
end

GetCastInterruptibilitySignal = function(unit, castBar)
    local castBarActive = IsCastBarActiveOnly and IsCastBarActiveOnly(castBar) or false
    local liveSignal, liveHasCast = nil, false
    if castBarActive and IsUsableUnitToken(unit) then
        liveSignal, liveHasCast = GetLiveUnitCastInterruptibilitySignal(unit)
        if liveHasCast and liveSignal ~= nil then
            return liveSignal, true
        end
    end

    local hasCast = castBarActive or IsCastActive(unit, castBar)
    if not hasCast then
        return nil, false
    end

    local resolvedNotInterruptible = GetResolvedCastBarInterruptibility(castBar)
    if resolvedNotInterruptible ~= nil then
        return resolvedNotInterruptible, true
    end

    if IsUsableUnitToken(unit) and (not castBarActive or liveHasCast) then
        if not castBarActive then
            liveSignal, liveHasCast = GetLiveUnitCastInterruptibilitySignal(unit)
        end
        if liveHasCast then
            return liveSignal, true
        end
    end

    return nil, true
end

local function RefreshCastVisualState(self, event, unitFrame, unit)
    if not unitFrame or IsRuntimeSuppressedNameplate(unitFrame) then
        return
    end

    local refreshState = CAST_STATE_REFRESH_EVENTS[event] == true
    local refreshBorders = refreshState or CAST_BORDER_REFRESH_EVENTS[event] == true
    if not refreshBorders then
        return
    end

    -- Stop events keep the live cast check: UNIT_SPELLCAST_SUCCEEDED can arrive after a
    -- channel has started, and the cast bar's OnHide reset clears cast colors.
    RefineUI:RefreshNameplateVisualState(unitFrame, unit, event,
        refreshState and ShouldRefreshCrowdControlForCastState(), refreshState, refreshBorders)
end

UpdateCastColor = function(self, refreshBorders)
     local data = GetCastBarData(self)
     if not data then return end
     if data.refineColoring then return end
     data.refineColoring = true
     
     local unitFrame = GetCastBarUnitFrame(self)
     if IsRuntimeSuppressedNameplate(unitFrame) then
         data.castR, data.castG, data.castB = nil, nil, nil
         ClearCastInterruptibilityState(data)
         data.refineColoring = false
         return
     end

     local unit = (unitFrame and unitFrame.unit) or self.unit
     
     if unit or IsCastActive(nil, self) then
         local interruptSignal, hasCast = GetCastInterruptibilitySignal(unit, self)
         if not hasCast then
             data.refineColoring = false
             if refreshBorders then
                 ResetCastStyle(self)
             else
                 data.castR, data.castG, data.castB = nil, nil, nil
                 ClearCastInterruptibilityState(data)
             end
             return
         end

         local resolvedNotInterruptible = GetResolvedCastBarInterruptibility(self)
         local signalApplied = ApplyCastStatusColorFromSignal(self, interruptSignal, resolvedNotInterruptible)
         local castColor, bgColor = RefineUI:GetCastColor(unit, self)

         if castColor and not signalApplied then
             signalApplied = ApplyCastStatusColorDirect(self, castColor)
         end

         local r, g, b = GetCastBarRenderedColor(self)
         if (r == nil or g == nil or b == nil) and type(castColor) == "table" then
             r, g, b = unpack(castColor)
         end
         if (r == nil or g == nil or b == nil)
             and type(data.castR) == "number"
             and type(data.castG) == "number"
             and type(data.castB) == "number" then
             r, g, b = data.castR, data.castG, data.castB
         end

         if r ~= nil and g ~= nil and b ~= nil then
             data.castR, data.castG, data.castB = r, g, b
         else
             data.castR, data.castG, data.castB = nil, nil, nil
         end

         local borderApplied = false
         if self.border then
             borderApplied = ApplyBorderColorFromSignal(self.border, interruptSignal, resolvedNotInterruptible)
             if (not borderApplied) and r ~= nil and g ~= nil and b ~= nil then
                 self.border:SetBackdropBorderColor(r, g, b)
             end
         end

         if refreshBorders and unitFrame and RefineUI.UpdateBorderColors then
             RefineUI:UpdateBorderColors(unitFrame)
         end

         if (not signalApplied) and bgColor == nil and r ~= nil and g ~= nil and b ~= nil then
             bgColor = BuildBackgroundColor({ r, g, b })
         end
         if bgColor and not signalApplied then
             -- Darken both our custom layer and Blizzard's visible Background layer.
             ApplyBackdropDarken(data.Background, bgColor)
             ApplyBackdropDarken(self.Background, bgColor)
         end
     end
     data.refineColoring = false
end

local function ClearCastTimeText(castTimeText)
    if not castTimeText then
        return
    end

    RefineUI:SetFontStringValue(castTimeText, nil, EMPTY_TEXT_OPTS)
    castTimeText:Hide()
end

HandleCastBarEvent = function(self, event, ...)
    local data = GetCastBarData(self)
    -- Any cast event can start, delay, or end the cast, so refetch its duration next update.
    data.castDuration = nil
    local unitFrame = GetCastBarUnitFrame(self)
    local unit = unitFrame and unitFrame.unit
    if unitFrame and IsRuntimeSuppressedNameplate(unitFrame) then
        if data then
            data.castR, data.castG, data.castB = nil, nil, nil
            ClearCastInterruptibilityState(data)
            local castTimeText = data.castTimeText
            if castTimeText then
                ClearCastTimeText(castTimeText)
            end
        end

        EnforceNameOnlyCastBarHidden(self)
        SyncNameplateCastAlphaState(self, unitFrame, unit, true)
        return
    end

    if data then
        if event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
            data.cachedNotInterruptible = true
        elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
            data.cachedNotInterruptible = false
        elseif event == "UNIT_SPELLCAST_START"
            or event == "UNIT_SPELLCAST_CHANNEL_START"
            or event == "UNIT_SPELLCAST_EMPOWER_START" then
            ClearCachedCastInterruptibility(data, false)
            data.castR, data.castG, data.castB = nil, nil, nil
        end
    end

    UpdateCastColor(self, false)

    if unitFrame then
        RefreshCastVisualState(self, event, unitFrame, unit)
        SyncNameplateCastAlphaState(self, unitFrame, unit)

        -- Color interrupted/failed casts here, after Blizzard has ended the cast on the bar.
        -- Channel and empower interrupts arrive as *_STOP with interruptedBy. The unit's
        -- cast info can outlive the interrupt event, so check the bar's flags, not the unit.
        local interrupted = event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED"
        if event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            interrupted = HasValue(select(4, ...))
        elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
            interrupted = HasValue(select(5, ...))
        end
        if interrupted
            and ReadSafeBoolean(self.casting) ~= true
            and ReadSafeBoolean(self.channeling) ~= true
            and ReadSafeBoolean(self.reverseChanneling) ~= true then
            ApplyCastStatusColorDirect(self, INTERRUPTED_CAST_COLOR)
            if self.border then
                self.border:SetBackdropBorderColor(unpack(INTERRUPTED_CAST_COLOR))
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
        RefineUI.Point(castTimeText, "BOTTOMRIGHT", castBar, "BOTTOMRIGHT", -2, 0)
        data.castTimeText = castTimeText
    end

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

-- Runs from Blizzard's per-frame UpdateCastTimeText; kept as a named function so the
-- pcall below does not allocate a closure each frame.
local function GetCastBarRemainingSeconds(castBar, countsDown)
    local minValue, maxValue = castBar:GetMinMaxValues()
    local currentValue = castBar:GetValue()
    if countsDown then
        return math.max(minValue, maxValue - currentValue)
    end
    return math.max(minValue, currentValue)
end

local function UpdateCustomCastTimeText(castBar)
    local data = GetCastBarData(castBar)
    local castTimeText = data and data.castTimeText
    if not castTimeText then
        return
    end

    local unitFrame = GetCastBarUnitFrame(castBar)
    if IsRuntimeSuppressedNameplate(unitFrame) then
        ClearCastTimeText(castTimeText)
        return
    end

    local isCasting = ReadSafeBoolean(castBar.casting) == true
    local isChanneling = ReadSafeBoolean(castBar.channeling) == true
    local isReverseChanneling = ReadSafeBoolean(castBar.reverseChanneling) == true
    if not (isCasting or isChanneling or isReverseChanneling) then
        data.castDuration = nil
        ClearCastTimeText(castTimeText)
        return
    end

    -- Path 1: Duration object from UnitCastingDuration / UnitChannelDuration.
    -- Blizzard calls UpdateCastTimeText every frame while casting; the duration object
    -- stays valid for the whole cast, so fetch it once and reuse it until the next cast event.
    local duration = data.castDuration
    if duration == nil then
        local unit = (unitFrame and unitFrame.unit) or castBar.unit
        if IsUsableUnitToken(unit) then
            if (isChanneling or isReverseChanneling) and UnitChannelDuration then
                duration = UnitChannelDuration(unit)
            elseif UnitCastingDuration then
                duration = UnitCastingDuration(unit)
            end
        end
        if HasValue(duration) then
            data.castDuration = duration
        end
    end

    if HasValue(duration) and TryFormatRemainingDuration(castTimeText, duration) then
        return
    end
    data.castDuration = nil

    -- Path 2: Bar values — arithmetic may involve secrets, wrap in pcall
    local ok, seconds = pcall(GetCastBarRemainingSeconds, castBar, isCasting or isReverseChanneling)

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
    
    local unitFrame = GetCastBarUnitFrame(self)
    if unitFrame and IsRuntimeSuppressedNameplate(unitFrame) then
        EnforceNameOnlyCastBarHidden(self)
        if data then data.adjusting = false end
        return
    end

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
        EnsureCastTimeText(self)

        -- Name-only suppression is visual-only. Hiding the Blizzard cast bar
        -- forces later addon-driven reshow paths back through secret cast logic.
        EnforceNameOnlyCastBarHidden(self)

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
    
    local unitFrame = GetCastBarUnitFrame(self)
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

function Nameplates:SuppressCastBarForNameOnly(castBar)
    if not castBar then
        return
    end

    local data = GetCastBarData(castBar)
    if data then
        data.castR, data.castG, data.castB = nil, nil, nil
        ClearCastInterruptibilityState(data)
        local castTimeText = data.castTimeText
        if castTimeText then
            ClearCastTimeText(castTimeText)
        end
    end

    EnforceNameOnlyCastBarHidden(castBar)

    local unitFrame = GetCastBarUnitFrame(castBar)
    SyncNameplateCastAlphaState(castBar, unitFrame, unitFrame and unitFrame.unit, true)
end

function Nameplates:RefreshCastBarForRuntimeMode(castBar)
    if not castBar then
        return
    end

    local unitFrame = GetCastBarUnitFrame(castBar)
    if IsRuntimeSuppressedNameplate(unitFrame) then
        self:SuppressCastBarForNameOnly(castBar)
        return
    end

    SetCastBarVisualAlpha(castBar, 1)
    ApplyCastBarLayout(castBar)
    UpdateCastColor(castBar, true)
    UpdateCustomCastTimeText(castBar)
    SyncNameplateCastAlphaState(castBar, unitFrame, unitFrame and unitFrame.unit, true)
end

function RefineUI:StyleNameplateCastBar(castBar)
    local data = GetCastBarData(castBar)
    if not castBar or data.isStyled then return end

    RefineUI:RefreshNameplateCastColors(false)

    -- Strip defaults
    if castBar.Border then castBar.Border:SetAlpha(0) end
    if castBar.BorderShield then castBar.BorderShield:SetAlpha(0) end
    if castBar.TextBorder then castBar.TextBorder:SetAlpha(0) end

    -- Texture
    SnapshotNativeStatusBarTexture(castBar, data)
    castBar:SetStatusBarTexture(TEX_BAR)
    EnsureCastBarTextureDesaturation(castBar)

    RefineUI:HookOnce(BuildNameplateCastHookKey(castBar, "SetStatusBarTexture"), castBar, "SetStatusBarTexture", function(self, tex)
        local data = GetCastBarData(self)
        if data then
            local normalizedTexture = NormalizeTextureToken(tex)
            if normalizedTexture ~= nil and normalizedTexture ~= NORMALIZED_TEX_BAR then
                ClearCachedCastInterruptibility(data, false)
                data.castR, data.castG, data.castB = nil, nil, nil
            end
            CacheNativeStatusBarTextureValue(data, tex)
            SnapshotNativeStatusBarTexture(self, data)
        end
        if (not IsAccessibleValue(tex)) or tex ~= TEX_BAR then
            -- Re-enters this hook with TEX_BAR, which applies the desaturation.
            self:SetStatusBarTexture(TEX_BAR)
            return
        end
        EnsureCastBarTextureDesaturation(self)
    end)

    -- Blizzard's UpdateBarFillTexture follows every SetStatusBarTexture with
    -- SetStatusBarColor(1, 1, 1), which would wipe a color applied in the texture
    -- hook. Recolor after it instead, including FinishSpell from OnUpdate, where no
    -- cast event follows in the same frame.
    RefineUI:HookOnce(BuildNameplateCastHookKey(castBar, "SetStatusBarColor"), castBar, "SetStatusBarColor", function(self)
        UpdateCastColor(self, false)
    end)

    -- Border
    RefineUI.CreateBorder(castBar, 6, 6, 12)

    -- Important casts: Blizzard's indicator art spans the bar and its icon slot. Blank it
    -- and drive the RefineUI bar glow and the portrait glow from its flag, which can be
    -- secret, so it is only ever passed to SetAlphaFromBoolean.
    if castBar.ImportantCastIndicator then
        castBar.ImportantCastIndicator:SetTexture(nil)
        local importantGlow = RefineUI.CreateGlow(castBar)
        importantGlow:SetAlpha(0)
        importantGlow:Show()
        RefineUI:HookOnce(
            BuildNameplateCastHookKey(castBar, "SetIsHighlightedImportantCast"),
            castBar,
            "SetIsHighlightedImportantCast",
            function(self, isImportant)
                importantGlow:SetAlphaFromBoolean(isImportant, 1, 0)
                RefineUI:SetNameplateImportantCast(GetCastBarUnitFrame(self), isImportant)
            end
        )
    end

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
                    data.cachedNotInterruptible = shieldShown
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
    RefineUI:HookOnce(
        BuildNameplateCastHookKey(castBar, "ApplyAlpha"),
        castBar,
        "ApplyAlpha",
        function(self)
            EnforceNameOnlyCastBarHidden(self)
        end
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
        local parentFrame = GetCastBarUnitFrame(self)
        SyncNameplateCastAlphaState(self, parentFrame, parentFrame and parentFrame.unit, true)
        EnforceNameOnlyCastBarHidden(self)
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
        local parentFrame = GetCastBarUnitFrame(self)
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
    local unitFrame = GetCastBarUnitFrame(castBar)
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
