----------------------------------------------------------------------------------------
-- UnitFrames Class Resources: Shared
-- Description: Shared constants, helpers, glow logic, and Blizzard suppression.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local UnitFrames = RefineUI:GetModule("UnitFrames")
if not UnitFrames then
    return
end

local Config = RefineUI.Config
local Media = RefineUI.Media
local Private = UnitFrames:GetPrivate()
local CR = Private.ClassResources

local CreateFrame = CreateFrame
local CreateColor = CreateColor
local UnitClass = UnitClass
local GetSpecialization = GetSpecialization
local GetTime = GetTime
local GetCollapsingStarCost = GetCollapsingStarCost
local unpack = unpack
local min = math.min
local type = type
local select = select
local issecretvalue = _G.issecretvalue
local GetSpecializationInfo = C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo
local GetSpellCastCount = C_Spell and C_Spell.GetSpellCastCount
local GetSpellMaxCumulativeAuraApplications = C_Spell and C_Spell.GetSpellMaxCumulativeAuraApplications
local GetPlayerAuraBySpellID = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID

CR.Constants = CR.Constants or {
    POWER_COMBO_POINTS = Enum.PowerType.ComboPoints,
    POWER_ENERGY = Enum.PowerType.Energy,
    POWER_SOUL_SHARDS = Enum.PowerType.SoulShards,
    POWER_HOLY_POWER = Enum.PowerType.HolyPower,
    POWER_CHI = Enum.PowerType.Chi,
    POWER_ARCANE_CHARGES = Enum.PowerType.ArcaneCharges,
    POWER_ESSENCE = Enum.PowerType.Essence,
    POWER_MAELSTROM = Enum.PowerType.Maelstrom,
    POWER_LUNAR_POWER = Enum.PowerType.LunarPower,
    POWER_INSANITY = Enum.PowerType.Insanity,
    MAX_TOTEMS = _G.MAX_TOTEMS or 4,
    STAGGER_YELLOW_TRANSITION = _G.STAGGER_YELLOW_TRANSITION or 0.3,
    STAGGER_RED_TRANSITION = _G.STAGGER_RED_TRANSITION or 0.6,
    SPEC_PRIEST_SHADOW = 3,
    SPEC_DRUID_BALANCE = 1,
    SPEC_SHAMAN_ELEMENTAL = 1,
    SPEC_SHAMAN_ENHANCEMENT = 2,
    SPEC_DK_BLOOD = 1,
    SPEC_DK_FROST = 2,
    SPEC_DK_UNHOLY = 3,
    SPEC_DH_VENGEANCE = 581,
    SPEC_DH_DEVOURER = 1480,
    SPEC_MONK_BREWMASTER = 1,
    SPEC_MONK_WINDWALKER = 3,
    SOUL_FRAGMENTS_MAX_VENGEANCE = 6,
    SPELL_SOUL_CLEAVE_ID = 228477,
    AURA_DARK_HEART_ID = 1225789,
    AURA_COLLAPSING_STAR_ID = 1227702,
    SOUL_FRAGMENTS_SPARK_VISUAL = {
        atlas = "UF-DDH-CollapsingStar-Bar-Endcap",
        xOffset = 1,
        barHeight = 10,
        showAtMax = false,
    },
    ENHANCEMENT_MAELSTROM_WEAPON_AURA_SPELL_ID = 344179,
    RESOURCE_BAR_TEXTURE = (Media.Textures and Media.Textures.Smooth) or "Interface\\Buttons\\WHITE8X8",
}

CR.PlayerClass = CR.PlayerClass or select(2, UnitClass("player"))
CR.Resources = CR.Resources or UnitFrames.ClassResources or {}
UnitFrames.ClassResources = CR.Resources

CR.ResourceColors = CR.ResourceColors or {
    R1 = { 0.67, 0.43, 0.32 },
    R2 = { 0.65, 0.56, 0.33 },
    R3 = { 0.58, 0.62, 0.33 },
    R4 = { 0.45, 0.60, 0.33 },
    R5 = { 0.33, 0.59, 0.33 },
    R6 = { 0.33, 0.59, 0.33 },
    E1 = { 0.98, 0.66, 0.66 },
    E2 = { 0.98, 0.84, 0.62 },
    E3 = { 0.96, 0.96, 0.64 },
    E4 = { 0.76, 0.94, 0.70 },
    E5 = { 0.62, 0.82, 0.95 },
    E6 = { 0.64, 0.84, 1.00 },
}

CR.DKRuneSpecColors = CR.DKRuneSpecColors or {
    [CR.Constants.SPEC_DK_BLOOD] = { 196 / 255, 30 / 255, 58 / 255 },
    [CR.Constants.SPEC_DK_FROST] = { 85 / 255, 180 / 255, 255 / 255 },
    [CR.Constants.SPEC_DK_UNHOLY] = { 86 / 255, 174 / 255, 87 / 255 },
}

CR.RuneScheduler = CR.RuneScheduler or {
    JobKey = "UnitFrames:RuneCooldownUpdater",
    Interval = 0.05,
    Initialized = false,
}

function CR.IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

function CR.IsNonSecretNumber(value)
    return not CR.IsSecret(value) and type(value) == "number"
end

function CR.IsNonSecretTexture(value)
    if CR.IsSecret(value) then
        return false
    end

    local valueType = type(value)
    return valueType == "string" or valueType == "number"
end

function CR.GetPlayerSpecID()
    if type(GetSpecialization) ~= "function" or type(GetSpecializationInfo) ~= "function" then
        return nil
    end

    local specIndex = GetSpecialization()
    if not specIndex or specIndex <= 0 then
        return nil
    end

    return GetSpecializationInfo(specIndex)
end

function CR.ShouldShowSoulFragments(specID)
    if CR.PlayerClass ~= "DEMONHUNTER" then
        return false
    end

    specID = specID or CR.GetPlayerSpecID()
    return specID == CR.Constants.SPEC_DH_VENGEANCE or specID == CR.Constants.SPEC_DH_DEVOURER
end

function CR.GetSoulFragmentsState(specID)
    local K = CR.Constants

    specID = specID or CR.GetPlayerSpecID()

    if specID == K.SPEC_DH_VENGEANCE then
        local currentValue = type(GetSpellCastCount) == "function" and GetSpellCastCount(K.SPELL_SOUL_CLEAVE_ID) or 0
        if type(currentValue) ~= "number" or currentValue < 0 then
            currentValue = 0
        end

        return currentValue, K.SOUL_FRAGMENTS_MAX_VENGEANCE
    end

    if specID ~= K.SPEC_DH_DEVOURER then
        return 0, 0
    end

    local darkHeartAura = type(GetPlayerAuraBySpellID) == "function" and GetPlayerAuraBySpellID(K.AURA_DARK_HEART_ID) or nil
    local collapsingStarAura = type(GetPlayerAuraBySpellID) == "function" and GetPlayerAuraBySpellID(K.AURA_COLLAPSING_STAR_ID) or nil
    local activeAura = collapsingStarAura or darkHeartAura

    local currentValue = activeAura and activeAura.applications or 0
    local maxValue = 0

    if collapsingStarAura and type(GetCollapsingStarCost) == "function" then
        maxValue = GetCollapsingStarCost() or 0
    elseif type(GetSpellMaxCumulativeAuraApplications) == "function" then
        maxValue = GetSpellMaxCumulativeAuraApplications(K.AURA_DARK_HEART_ID) or 0
    end

    if type(currentValue) ~= "number" or currentValue < 0 then
        currentValue = 0
    end

    if type(maxValue) ~= "number" or maxValue < 0 then
        maxValue = 0
    end

    return currentValue, maxValue
end

function CR.ClearCooldownSafe(cooldown)
    if not cooldown then
        return
    end
    if type(cooldown.Clear) == "function" then
        cooldown:Clear()
    else
        cooldown:SetCooldown(0, 0)
    end
end

local function GetPlayerSecondaryPowerInfo(spec)
    local K = CR.Constants
    local class = CR.PlayerClass

    spec = spec or GetSpecialization()

    if class == "PRIEST" and spec == K.SPEC_PRIEST_SHADOW then
        return K.POWER_INSANITY, "INSANITY"
    end

    if class == "DRUID" and spec == K.SPEC_DRUID_BALANCE then
        return K.POWER_LUNAR_POWER, "LUNAR_POWER"
    end

    if class == "SHAMAN" and spec == K.SPEC_SHAMAN_ELEMENTAL then
        return K.POWER_MAELSTROM, "MAELSTROM"
    end

    return nil, nil
end

CR.GetPlayerSecondaryPowerInfo = GetPlayerSecondaryPowerInfo

function UnitFrames.GetPlayerSecondaryPowerInfo()
    return GetPlayerSecondaryPowerInfo()
end

function UnitFrames.IsPlayerSecondaryPowerSwapActive()
    local powerType = GetPlayerSecondaryPowerInfo()
    return powerType ~= nil
end

function CR.GetResourceColor(resourceType, index, barCount)
    local r, g, b = 1, 1, 1
    local class = CR.PlayerClass
    local classColor = RefineUI.MyClassColor or RefineUI.Colors.Class[class]

    if resourceType == "RUNES" then
        if class == "DEATHKNIGHT" then
            local specColor = CR.DKRuneSpecColors[GetSpecialization()]
            if specColor then
                r, g, b = specColor[1], specColor[2], specColor[3]
            elseif RefineUI.Colors.Power.RUNES then
                r, g, b = unpack(RefineUI.Colors.Power.RUNES)
            end
        elseif RefineUI.Colors.Power.RUNES then
            r, g, b = unpack(RefineUI.Colors.Power.RUNES)
        end
    elseif resourceType == "CLASS_POWER" then
        if class == "PALADIN" then
            r, g, b = 1, 0.82, 0
        elseif class == "WARLOCK" then
            r, g, b = 0.6, 0.4, 0.8
        elseif class == "ROGUE" or class == "DRUID" then
            local color = CR.ResourceColors["R" .. min(6, index or barCount or 1)]
            if color then
                r, g, b = color[1], color[2], color[3]
            end
        elseif class == "EVOKER" then
            local color = CR.ResourceColors["E" .. min(6, index or barCount or 1)]
            if color then
                r, g, b = color[1], color[2], color[3]
            end
        elseif classColor then
            r, g, b = classColor.r, classColor.g, classColor.b
        end
    elseif resourceType == "MAELSTROM" then
        local maelstromColor = RefineUI.Colors.Power.MAELSTROM
        if maelstromColor then
            r, g, b = maelstromColor.r, maelstromColor.g, maelstromColor.b
        elseif classColor then
            r, g, b = classColor.r, classColor.g, classColor.b
        end
    elseif classColor then
        r, g, b = classColor.r, classColor.g, classColor.b
    end

    return r, g, b
end

local function RuneCooldownUpdateJob()
    local resource = UnitFrames.ClassResources and UnitFrames.ClassResources.Runes
    if not resource or not resource.Segments then
        if RefineUI.SetUpdateJobEnabled then
            RefineUI:SetUpdateJobEnabled(CR.RuneScheduler.JobKey, false, false)
        end
        return
    end

    local active = false
    for index = 1, 6 do
        local segment = resource.Segments[index]
        if segment and segment._isCooling then
            local start = segment._runeStart or 0
            local duration = segment._runeDuration or 0
            local progress = GetTime() - start

            if duration <= 0 or progress >= duration then
                segment:SetValue(duration > 0 and duration or 1)
                segment._isCooling = false
                segment._runeStart = nil
                segment._runeDuration = nil
                segment:FadeIn()
            else
                segment:SetValue(progress)
                active = true
            end
        end
    end

    if not active and RefineUI.SetUpdateJobEnabled then
        RefineUI:SetUpdateJobEnabled(CR.RuneScheduler.JobKey, false, false)
    end
end

local function EnsureRuneScheduler()
    if CR.RuneScheduler.Initialized then
        return
    end
    if not RefineUI.RegisterUpdateJob then
        return
    end

    RefineUI:RegisterUpdateJob(CR.RuneScheduler.JobKey, CR.RuneScheduler.Interval, RuneCooldownUpdateJob, {
        enabled = false,
    })
    CR.RuneScheduler.Initialized = true
end

function CR.SetRuneSchedulerEnabled(enabled)
    EnsureRuneScheduler()
    if CR.RuneScheduler.Initialized and RefineUI.SetUpdateJobEnabled then
        RefineUI:SetUpdateJobEnabled(CR.RuneScheduler.JobKey, enabled and true or false, false)
    end
end

local function CreatePulse(frame)
    if frame.PulseAnim then
        return
    end

    local animGroup = frame:CreateAnimationGroup()
    animGroup:SetLooping("BOUNCE")

    local alpha = animGroup:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0.2)
    alpha:SetToAlpha(0.8)
    alpha:SetDuration(0.6)
    alpha:SetSmoothing("IN_OUT")

    frame.PulseAnim = animGroup
end

local function PlayPulse(frame)
    if not frame.PulseAnim then
        CreatePulse(frame)
    end
    if not frame.PulseAnim:IsPlaying() then
        frame.PulseAnim:Play()
    end
end

local function StopPulse(frame)
    if frame.PulseAnim and frame.PulseAnim:IsPlaying() then
        frame.PulseAnim:Stop()
    end
end

function CR.HandleResourceGlow(resource, isActive, r, g, b)
    if not resource or not resource.Bar then
        return
    end

    if isActive then
        if resource.PulseGlow then
            resource.PulseGlow:Show()
            PlayPulse(resource.PulseGlow)
            resource.PulseGlow:SetBackdropBorderColor(r or 1, g or 1, b or 1, 0.8)
        end
        if resource.Bar.border then
            resource.Bar.border:SetBackdropBorderColor(r or 1, g or 1, b or 1, 1)
        end
        return
    end

    if resource.PulseGlow then
        StopPulse(resource.PulseGlow)
        resource.PulseGlow:Hide()
    end

    if resource.Bar.border then
        local br, bg, bb = unpack(Config.General.BorderColor)
        resource.Bar.border:SetBackdropBorderColor(br, bg, bb, 1)
    end
end

function CR.BuildSuppressionHookKey(frame, method)
    return UnitFrames:BuildHookKey(frame, "ClassResources:Suppress:" .. method)
end

function CR.HideBlizzardResource(frame)
    if not frame then
        return
    end

    frame:SetAlpha(0)

    if frame.SetAlpha then
        RefineUI:HookOnce(CR.BuildSuppressionHookKey(frame, "SetAlpha"), frame, "SetAlpha", function(self, alpha)
            if alpha ~= 0 then
                self:SetAlpha(0)
            end
        end)
    end

    if frame.Show then
        RefineUI:HookOnce(CR.BuildSuppressionHookKey(frame, "Show"), frame, "Show", function(self)
            self:SetAlpha(0)
        end)
    end

    if frame.SetShown then
        RefineUI:HookOnce(CR.BuildSuppressionHookKey(frame, "SetShown"), frame, "SetShown", function(self, shown)
            if shown then
                self:SetAlpha(0)
            end
        end)
    end
end

local PaladinTextColorCurve
local SoulFragmentsTextColorCurve

function CR.GetPaladinTextColorCurve(maxValue)
    if not PaladinTextColorCurve or PaladinTextColorCurve._max ~= maxValue then
        PaladinTextColorCurve = C_CurveUtil.CreateColorCurve()
        PaladinTextColorCurve:SetType(Enum.LuaCurveType.Linear)
        PaladinTextColorCurve:AddPoint(0.0, CreateColor(1, 1, 1, 1))
        PaladinTextColorCurve:AddPoint(maxValue or 5, CreateColor(1, 0.82, 0, 1))
        PaladinTextColorCurve._max = maxValue
    end

    return PaladinTextColorCurve
end

function CR.GetSoulFragmentsTextColorCurve(maxValue)
    if not SoulFragmentsTextColorCurve or SoulFragmentsTextColorCurve._max ~= maxValue then
        SoulFragmentsTextColorCurve = C_CurveUtil.CreateColorCurve()
        SoulFragmentsTextColorCurve:SetType(Enum.LuaCurveType.Linear)
        SoulFragmentsTextColorCurve:AddPoint(0.0, CreateColor(1, 1, 1, 1))
        SoulFragmentsTextColorCurve:AddPoint(maxValue or 6, CreateColor(0.06, 0.42, 0.92, 1))
        SoulFragmentsTextColorCurve._max = maxValue
    end

    return SoulFragmentsTextColorCurve
end

function CR.SetupGlowThreshold(resource)
    if resource.GlowThresholdBar then
        return
    end

    local threshold = CreateFrame("StatusBar", nil, resource.Bar)
    threshold:SetSize(1, 1)
    threshold:SetAlpha(0)
    threshold:SetPoint("CENTER")
    threshold:SetScript("OnValueChanged", function(self)
        local value = self:GetValue()
        local _, maxValue = self:GetMinMaxValues()
        local isFull = false

        if CR.IsSecret(value) then
            isFull = true
        else
            isFull = (value >= maxValue)
        end

        if isFull then
            if resource.PulseGlow then
                resource.PulseGlow:Show()
                PlayPulse(resource.PulseGlow)
                local r, g, b = CR.GetResourceColor(resource.Type, nil, resource.LastBarCount)
                resource.PulseGlow:SetBackdropBorderColor(r, g, b, 0.8)
            end
            if resource.Bar.border then
                local r, g, b = CR.GetResourceColor(resource.Type, nil, resource.LastBarCount)
                resource.Bar.border:SetBackdropBorderColor(r, g, b, 1)
            end
        else
            if resource.PulseGlow then
                StopPulse(resource.PulseGlow)
                resource.PulseGlow:Hide()
            end
            if resource.Bar.border then
                local br, bg, bb = unpack(Config.General.BorderColor)
                resource.Bar.border:SetBackdropBorderColor(br, bg, bb, 1)
            end
        end
    end)

    resource.GlowThresholdBar = threshold
end

function CR.UpdateGlowState(resource, minimumValue, maximumValue)
    if not resource.GlowThresholdBar then
        CR.SetupGlowThreshold(resource)
    end

    local threshold = resource.GlowThresholdBar
    threshold:SetMinMaxValues(maximumValue - 0.5, maximumValue)
    threshold:SetValue(minimumValue)
end
