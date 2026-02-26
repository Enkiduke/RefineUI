----------------------------------------------------------------------------------------
-- UnitFrames Class Resources
-- Description: Handling for Class Power, Runes, Totems, Stagger, etc.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local Config = RefineUI.Config
local Media = RefineUI.Media

RefineUI.UnitFrames = RefineUI.UnitFrames or {}
local UF = RefineUI.UnitFrames

-- WoW Globals
local CreateFrame = CreateFrame
local hooksecurefunc = hooksecurefunc
local UnitClass = UnitClass
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local GetSpecialization = GetSpecialization
local UnitPowerType = UnitPowerType
local GetRuneCooldown = GetRuneCooldown
local GetTime = GetTime
local UnitStagger = UnitStagger
local UnitHealthMax = UnitHealthMax
local GetTotemInfo = GetTotemInfo
local GetPlayerAuraBySpellID = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID or GetPlayerAuraBySpellID
local MAX_TOTEMS = _G.MAX_TOTEMS or 4
local min, max, floor = math.min, math.max, math.floor
local select = select
local unpack = unpack
local pairs = pairs
local next = next
local type = type
local tostring = tostring
local issecretvalue = _G.issecretvalue

-- Configuration Cache
local DB = Config.UnitFrames.DataBars
local Media = RefineUI.Media -- Re-caching locally if needed

-- Constants
local SPELL_POWER_COMBO_POINTS = Enum.PowerType.ComboPoints
local SPELL_POWER_ENERGY = Enum.PowerType.Energy
local SPELL_POWER_SOUL_SHARDS = Enum.PowerType.SoulShards
local SPELL_POWER_HOLY_POWER = Enum.PowerType.HolyPower
local SPELL_POWER_CHI = Enum.PowerType.Chi
local SPELL_POWER_ARCANE_CHARGES = Enum.PowerType.ArcaneCharges
local SPELL_POWER_ESSENCE = Enum.PowerType.Essence
local SPELL_POWER_MAELSTROM = Enum.PowerType.Maelstrom
local SPELL_POWER_LUNAR_POWER = Enum.PowerType.LunarPower
local SPELL_POWER_INSANITY = Enum.PowerType.Insanity
local STAGGER_YELLOW_TRANSITION = _G.STAGGER_YELLOW_TRANSITION or 0.3
local STAGGER_RED_TRANSITION = _G.STAGGER_RED_TRANSITION or 0.6
local SPEC_INDEX_PRIEST_SHADOW = 3
local SPEC_INDEX_DRUID_BALANCE = 1
local SPEC_INDEX_SHAMAN_ELEMENTAL = 1
local SPEC_INDEX_SHAMAN_ENHANCEMENT = 2
local SPEC_INDEX_DEATHKNIGHT_BLOOD = 1
local SPEC_INDEX_DEATHKNIGHT_FROST = 2
local SPEC_INDEX_DEATHKNIGHT_UNHOLY = 3
local SPEC_INDEX_MONK_BREWMASTER = 1
local SPEC_INDEX_MONK_WINDWALKER = 3
local ENHANCEMENT_MAELSTROM_WEAPON_AURA_SPELL_ID = 344179
local RESOURCE_BAR_TEXTURE = (Media.Textures and Media.Textures.Smooth) or "Interface\\Buttons\\WHITE8X8"
local SUPPRESS_HOOK_KEY_PREFIX = "UnitFrames:ClassResources:Suppress"
local DK_RUNE_SPEC_COLORS = {
    [SPEC_INDEX_DEATHKNIGHT_BLOOD] = { 196 / 255, 30 / 255, 58 / 255 },   -- Blood (red)
    [SPEC_INDEX_DEATHKNIGHT_FROST] = { 85 / 255, 180 / 255, 255 / 255 },   -- Frost (blue)
    [SPEC_INDEX_DEATHKNIGHT_UNHOLY] = { 86 / 255, 174 / 255, 87 / 255 },   -- Unholy (green)
}

-- Locals
local Class = select(2, UnitClass("player"))
local ResourceColors = {
    -- Rogue/Druid Gradients
    R1 = {0.67, 0.43, 0.32}, R2 = {0.65, 0.56, 0.33}, R3 = {0.58, 0.62, 0.33},
    R4 = {0.45, 0.60, 0.33}, R5 = {0.33, 0.59, 0.33}, R6 = {0.33, 0.59, 0.33},
    -- Evoker Essence Gradient (light red -> light yellow -> light green -> light blue)
    E1 = {0.98, 0.66, 0.66},
    E2 = {0.98, 0.84, 0.62},
    E3 = {0.96, 0.96, 0.64},
    E4 = {0.76, 0.94, 0.70},
    E5 = {0.62, 0.82, 0.95},
    E6 = {0.64, 0.84, 1.00},
}

----------------------------------------------------------------------------------------
-- Secondary Power Mapping
----------------------------------------------------------------------------------------
local function GetPlayerSecondaryPowerInfo(spec)
    spec = spec or GetSpecialization()

    if Class == "PRIEST" and spec == SPEC_INDEX_PRIEST_SHADOW then
        return SPELL_POWER_INSANITY, "INSANITY"
    end

    if Class == "DRUID" and spec == SPEC_INDEX_DRUID_BALANCE then
        return SPELL_POWER_LUNAR_POWER, "LUNAR_POWER"
    end

    if Class == "SHAMAN" and spec == SPEC_INDEX_SHAMAN_ELEMENTAL then
        return SPELL_POWER_MAELSTROM, "MAELSTROM"
    end

    return nil, nil
end

function UF.GetPlayerSecondaryPowerInfo()
    return GetPlayerSecondaryPowerInfo()
end

function UF.IsPlayerSecondaryPowerSwapActive()
    local powerType = GetPlayerSecondaryPowerInfo()
    return powerType ~= nil
end

local function GetResourceColor(resType, index, barCount)
    local r, g, b = 1, 1, 1
    local classCol = RefineUI.MyClassColor or RefineUI.Colors.Class[Class]

    if resType == "RUNES" then
        if Class == "DEATHKNIGHT" then
            local specColor = DK_RUNE_SPEC_COLORS[GetSpecialization()]
            if specColor then
                r, g, b = specColor[1], specColor[2], specColor[3]
            elseif RefineUI.Colors.Power["RUNES"] then
                r, g, b = unpack(RefineUI.Colors.Power["RUNES"])
            end
        elseif RefineUI.Colors.Power["RUNES"] then
            r, g, b = unpack(RefineUI.Colors.Power["RUNES"])
        end
    elseif resType == "CLASS_POWER" then
        if Class == "PALADIN" then
            r, g, b = 1, 0.82, 0
        elseif Class == "WARLOCK" then
            r, g, b = 0.6, 0.4, 0.8
        elseif Class == "ROGUE" or Class == "DRUID" then
            local c = ResourceColors["R"..min(6, index or barCount or 1)]
            if c then r, g, b = c[1], c[2], c[3] end
        elseif Class == "EVOKER" then
            local c = ResourceColors["E"..min(6, index or barCount or 1)]
            if c then r, g, b = c[1], c[2], c[3] end
        elseif classCol then
            r, g, b = classCol.r, classCol.g, classCol.b
        end
    elseif resType == "MAELSTROM" then
        local maelstromColor = RefineUI.Colors.Power["MAELSTROM"]
        if maelstromColor then
            r, g, b = maelstromColor.r, maelstromColor.g, maelstromColor.b
        elseif classCol then
            r, g, b = classCol.r, classCol.g, classCol.b
        end
    elseif classCol then
        r, g, b = classCol.r, classCol.g, classCol.b
    end
    
    return r, g, b
end

-- Resource storage on UF
UF.ClassResources = {}
local RUNE_UPDATE_JOB_KEY = "UnitFrames:RuneCooldownUpdater"
local RUNE_UPDATE_INTERVAL = 0.05
local runeSchedulerInitialized = false

local function RuneCooldownUpdateJob()
    local resource = UF.ClassResources and UF.ClassResources.Runes
    if not resource or not resource.Segments then
        if RefineUI.SetUpdateJobEnabled then
            RefineUI:SetUpdateJobEnabled(RUNE_UPDATE_JOB_KEY, false, false)
        end
        return
    end

    local active = false
    for j = 1, 6 do
        local segment = resource.Segments[j]
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
        RefineUI:SetUpdateJobEnabled(RUNE_UPDATE_JOB_KEY, false, false)
    end
end

local function EnsureRuneScheduler()
    if runeSchedulerInitialized then return end
    if not RefineUI.RegisterUpdateJob then return end

    RefineUI:RegisterUpdateJob(
        RUNE_UPDATE_JOB_KEY,
        RUNE_UPDATE_INTERVAL,
        RuneCooldownUpdateJob,
        { enabled = false }
    )

    runeSchedulerInitialized = true
end

local function SetRuneSchedulerEnabled(enabled)
    EnsureRuneScheduler()
    if runeSchedulerInitialized and RefineUI.SetUpdateJobEnabled then
        RefineUI:SetUpdateJobEnabled(RUNE_UPDATE_JOB_KEY, enabled and true or false, false)
    end
end

---------------------------
-- Animation Helpers     --
---------------------------
local function CreatePulse(frame)
    if frame.PulseAnim then return end
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
    if not frame.PulseAnim then CreatePulse(frame) end
    if not frame.PulseAnim:IsPlaying() then frame.PulseAnim:Play() end
end

local function StopPulse(frame)
    if frame.PulseAnim and frame.PulseAnim:IsPlaying() then frame.PulseAnim:Stop() end
end

-- Backward-compatible glow handler used by status-bar resources (e.g. Stagger).
-- Segmented bars use the threshold helper below.
local function HandleResourceGlow(Resource, isActive, r, g, b)
    if not Resource or not Resource.Bar then return end

    if isActive then
        if Resource.PulseGlow then
            Resource.PulseGlow:Show()
            PlayPulse(Resource.PulseGlow)
            Resource.PulseGlow:SetBackdropBorderColor(r or 1, g or 1, b or 1, 0.8)
        end
        if Resource.Bar.border then
            Resource.Bar.border:SetBackdropBorderColor(r or 1, g or 1, b or 1, 1)
        end
        return
    end

    if Resource.PulseGlow then
        StopPulse(Resource.PulseGlow)
        Resource.PulseGlow:Hide()
    end

    if Resource.Bar.border then
        local br, bg, bb = unpack(Config.General.BorderColor)
        Resource.Bar.border:SetBackdropBorderColor(br, bg, bb, 1)
    end
end

local function GetSuppressionOwnerId(frame)
    if type(frame) == "table" and frame.GetName then
        local name = frame:GetName()
        if name and name ~= "" then
            return name
        end
    end
    return tostring(frame)
end

local function BuildSuppressionHookKey(frame, method)
    return SUPPRESS_HOOK_KEY_PREFIX .. ":" .. GetSuppressionOwnerId(frame) .. ":" .. method
end

local function HideBlizzardResource(frame)
    if not frame then return end
    frame:SetAlpha(0)

    if frame.SetAlpha then
        RefineUI:HookOnce(BuildSuppressionHookKey(frame, "SetAlpha"), frame, "SetAlpha", function(self, alpha)
            if alpha ~= 0 then
                self:SetAlpha(0)
            end
        end)
    end

    if frame.Show then
        RefineUI:HookOnce(BuildSuppressionHookKey(frame, "Show"), frame, "Show", function(self)
            self:SetAlpha(0)
        end)
    end

    if frame.SetShown then
        RefineUI:HookOnce(BuildSuppressionHookKey(frame, "SetShown"), frame, "SetShown", function(self, shown)
            if shown then
                self:SetAlpha(0)
            end
        end)
    end

end

-- ColorCurve for Paladin Holy Power text: White (0%) → Gold (100%)
local PaladinTextColorCurve
local function GetPaladinTextColorCurve(maxVal)
    if not PaladinTextColorCurve or PaladinTextColorCurve._max ~= maxVal then
        PaladinTextColorCurve = C_CurveUtil.CreateColorCurve()
        PaladinTextColorCurve:SetType(Enum.LuaCurveType.Linear)
        PaladinTextColorCurve:AddPoint(0.0, CreateColor(1, 1, 1, 1))       -- White
        PaladinTextColorCurve:AddPoint(maxVal or 5, CreateColor(1, 0.82, 0, 1))    -- Gold
        PaladinTextColorCurve._max = maxVal
    end
    return PaladinTextColorCurve
end

---------------------------
-- Pulse & Glow Logic    --
---------------------------

-- SECRET-SAFE: Initialize glow threshold bar for a resource
-- This bar fills when Min >= Max, triggering glow via OnValueChanged
local function SetupGlowThreshold(Resource)
    if Resource.GlowThresholdBar then return end
    
    local threshold = CreateFrame("StatusBar", nil, Resource.Bar)
    threshold:SetSize(1, 1)  -- Invisible helper
    threshold:SetAlpha(0)
    threshold:SetPoint("CENTER")
    
    -- The trick: range [Max - 0.5, Max] means bar fills only when Min >= Max
    threshold:SetScript("OnValueChanged", function(self)
        local val = self:GetValue()
        local _, maxVal = self:GetMinMaxValues()
        -- Bar is "full" when value >= max threshold
        local isFull = false
        if issecretvalue and issecretvalue(val) then
            isFull = true -- Assume full for glow if secret (simplified for safety)
        else
            isFull = (val >= maxVal)
        end
        
        if isFull then
            if Resource.PulseGlow then
                Resource.PulseGlow:Show()
                PlayPulse(Resource.PulseGlow)
                local r, g, b = GetResourceColor(Resource.Type, nil, Resource.LastBarCount)
                Resource.PulseGlow:SetBackdropBorderColor(r, g, b, 0.8)
            end
            if Resource.Bar.border then
                local r, g, b = GetResourceColor(Resource.Type, nil, Resource.LastBarCount)
                Resource.Bar.border:SetBackdropBorderColor(r, g, b, 1)
            end
        else
            if Resource.PulseGlow then
                StopPulse(Resource.PulseGlow)
                Resource.PulseGlow:Hide()
            end
            if Resource.Bar.border then
                local br, bg, bb = unpack(Config.General.BorderColor)
                Resource.Bar.border:SetBackdropBorderColor(br, bg, bb, 1)
            end
        end
    end)
    
    Resource.GlowThresholdBar = threshold
end

-- Update glow state using threshold bar (SECRET-SAFE pass-through)
local function UpdateGlowState(Resource, Min, Max)
    if not Resource.GlowThresholdBar then
        SetupGlowThreshold(Resource)
    end
    
    local threshold = Resource.GlowThresholdBar
    -- Set range so bar only fills when Min >= Max
    threshold:SetMinMaxValues(Max - 0.5, Max)
    threshold:SetValue(Min)  -- Pass secret value, OnValueChanged handles the rest
end

---------------------------
-- Segmented Bar Update  --
---------------------------

local function UpdateSegmentedBar(Resource)
    local Min, Max, BarCount, PowerType
    local Spec = GetSpecialization()

    if Resource.Type == "CLASS_POWER" then
        PowerType = Resource.PowerType
        if Class == "WARLOCK" and Spec == 3 then
            Min = UnitPower("player", PowerType, true)
            Max = UnitPowerMax("player", PowerType, true)
            BarCount = 5
        else
            Min = UnitPower("player", PowerType)
            Max = UnitPowerMax("player", PowerType)
            BarCount = Max
        end
    elseif Resource.Type == "MAELSTROM" then
        -- Enhancement Shaman: Maelstrom Weapon stacks (not Elemental Maelstrom power).
        local Aura = GetPlayerAuraBySpellID(ENHANCEMENT_MAELSTROM_WEAPON_AURA_SPELL_ID)
        Min = Aura and Aura.applications or 0
        Max = 10
        BarCount = 10
    elseif Resource.Type == "RUNES" then
        Min = 0
        Max = 6
        BarCount = 6
    end

    if not BarCount or BarCount == 0 then return end
    
    -- Reset stale segments when BarCount changes
    if Resource.LastBarCount and Resource.LastBarCount ~= BarCount then
        for i = 1, max(BarCount, Resource.LastBarCount) do
            local seg = Resource.Segments[i]
            if seg then
                seg:SetValue(0)
                seg:SetAlpha(0)
                if seg.animGroup then seg.animGroup:Stop() end
            end
        end
    end
    Resource.LastBarCount = BarCount
    
    local BarWidth = Resource.Bar:GetWidth()
    -- SECRET-SAFE: Use stored unscaled width as fallback if GetWidth returns a secret value or 0
    if (issecretvalue and issecretvalue(BarWidth)) or (not BarWidth or BarWidth == 0) then
        BarWidth = RefineUI:Scale(Resource.Bar._width or 120)
    end

    local Spacing = 2
    local TotalSpacing = (BarCount - 1) * Spacing
    local runeCoolingActive = false

    for i = 1, BarCount do
        local Segment = Resource.Segments[i]
        if not Segment then
            Segment = CreateFrame("StatusBar", nil, Resource.Bar)
            RefineUI:AddAPI(Segment)
            -- Z-Order: Ensure segments are above backdrop
            Segment:SetFrameLevel(Resource.Bar:GetFrameLevel() + 5)
            
            Segment:SetStatusBarTexture(RESOURCE_BAR_TEXTURE)
            Segment:SetAlpha(0)
            
            -- SECRET-SAFE ALPHA CONTROL: Fade in when segment fills, fade out when empty
            Segment:SetScript("OnValueChanged", function(self)
                local val = self:GetValue()
                local minVal, maxVal = self:GetMinMaxValues()
                
                -- SECRET-SAFE: Guard arithmetic on secret values
                local isSecret = issecretvalue and issecretvalue(val)
                local fillPercent = 0
                if not isSecret then
                    fillPercent = (maxVal > minVal) and ((val - minVal) / (maxVal - minVal)) or 0
                end

                if isSecret or fillPercent >= 0.99 then
                    if Resource.Type == "RUNES" and self._isCooling then
                        -- Charging rune: keep a slightly dimmed presentation.
                        self:SetAlpha(0.5)
                    else
                        -- Fully filled or secret - fade in
                        if self:GetAlpha() < 1 then
                            self:FadeIn()
                        end
                    end
                elseif fillPercent > 0 then
                    -- Partially filled segments
                    if Resource.Type == "RUNES" and self._isCooling then
                        self:SetAlpha(0.5)
                    else
                        self:SetAlpha(1)
                    end
                else
                    -- Empty - fade out
                    if self:GetAlpha() > 0 then
                        self:FadeOut(0.15, 0)
                    end
                end
            end)
            
            Resource.Segments[i] = Segment
        end

        local Width = math.floor((BarWidth - TotalSpacing) * i / BarCount) - math.floor((BarWidth - TotalSpacing) * (i - 1) / BarCount)
        Segment:SetSize(Width, Resource.Height)
        Segment:ClearAllPoints()
        if i == 1 then
            Segment:SetPoint("LEFT", Resource.Bar, "LEFT", 0, 0)
        else
            Segment:SetPoint("LEFT", Resource.Segments[i-1], "RIGHT", Spacing, 0)
        end

        -- Coloring
        local r, g, b = GetResourceColor(Resource.Type, i, BarCount)
        Segment:SetStatusBarColor(r, g, b)

        -- Filling (Secret Value Safe)
        if Resource.Type == "RUNES" then
            local Start, Duration, Ready = GetRuneCooldown(i)
            if Ready then
                Min = Min + 1
                Segment:SetMinMaxValues(0, 1)
                Segment:SetValue(1)
                Segment._isCooling = false
                Segment._runeStart = nil
                Segment._runeDuration = nil
                if Segment.animGroup then Segment.animGroup:Stop() end
                Segment:FadeIn()
            elseif Start then
                Segment:SetMinMaxValues(0, Duration)
                
                Segment._runeStart = Start
                Segment._runeDuration = Duration
                Segment._isCooling = true
                Segment:FadeOut(0.25, 0.75)
            else
                Segment._isCooling = false
                Segment._runeStart = nil
                Segment._runeDuration = nil
            end

            if Segment._isCooling then
                runeCoolingActive = true
            end
        elseif Resource.Type == "CLASS_POWER" and Class == "WARLOCK" and Spec == 3 then
            -- Warlock Demo: Each shard is 10 points, use partitioned ranges
            local bMin, bMax = (i - 1) * 10, i * 10
            Segment:SetMinMaxValues(bMin, bMax)
            Segment:SetValue(Min) -- StatusBar handles secrets, shows partial fill naturally
            -- Visibility handled by OnValueChanged
        else
            -- SECRET-SAFE PASS-THROUGH: StatusBar clamps Min to [i-1, i]
            -- Full if Min >= i, empty if Min < i-1, partial otherwise
            Segment:SetMinMaxValues(i - 1, i)
            Segment:SetValue(Min)
            -- Visibility handled by OnValueChanged
        end
    end

    if Resource.Type == "RUNES" then
        SetRuneSchedulerEnabled(runeCoolingActive)
    end

    -- Hide extras
    for i = BarCount + 1, #Resource.Segments do 
        Resource.Segments[i]:Hide() 
    end

    -- Glow at max resources (SECRET-SAFE via threshold bar)
    UpdateGlowState(Resource, Min, BarCount)

    -- Ensure rune pulse glow color tracks spec changes even when the threshold
    -- helper value does not change (e.g. full runes before/after a spec swap).
    if Resource.Type == "RUNES" then
        local gr, gg, gb = GetResourceColor(Resource.Type, nil, BarCount)
        if Resource.PulseGlow then
            Resource.PulseGlow:SetBackdropBorderColor(gr, gg, gb, 0.8)
        end
        if Resource.Bar and Resource.Bar.border and Min == BarCount then
            Resource.Bar.border:SetBackdropBorderColor(gr, gg, gb, 1)
        end
    end

    -- Text display with SECRET-SAFE coloring
    if Resource.Text then
        if (issecretvalue and issecretvalue(Min)) or Min ~= 0 then
            Resource.Text:SetText(Min) -- FontString accepts secrets via pass-through
        else
            Resource.Text:SetText("")
        end
        Resource.Text:Show()
        Resource.Text:SetAlpha(1)
        
        -- Paladin: Use ColorCurve for white→gold gradient based on power level
        if Class == "PALADIN" and Resource.Type == "CLASS_POWER" then
            -- Set up helper bar for text color if needed
            if not Resource.TextColorBar then
                local colorBar = CreateFrame("StatusBar", nil, Resource.Bar)
                colorBar:SetSize(1, 1)
                colorBar:SetAlpha(0)
                colorBar:SetPoint("CENTER")
                
                colorBar:SetScript("OnValueChanged", function(self)
                    local val = self:GetValue()
                    local _, maxVal = self:GetMinMaxValues()
                    if maxVal > 0 then
                        local curve = GetPaladinTextColorCurve(maxVal)
                        local color = curve:Evaluate(val)
                        if Resource.Text and color then
                            local r, g, b, a = color:GetRGBA()
                            Resource.Text:SetTextColor(r, g, b, a)
                        end
                    end
                end)
                
                Resource.TextColorBar = colorBar
            end
            
            -- Update the color bar with current values
            Resource.TextColorBar:SetMinMaxValues(0, BarCount)
            Resource.TextColorBar:SetValue(Min)
        else
            Resource.Text:SetTextColor(1, 1, 1)
        end
    end
end

---------------------------
-- Status Bar Update     --
---------------------------

local function UpdateStatusBar(Resource)
    local Min, Max, r, g, b
    local Bar = Resource.Bar
    
    if Resource.Type == "STAGGER" then
        Min, Max = UnitStagger("player"), UnitHealthMax("player")
        
        -- SECRET VALUE SAFETY: Check before arithmetic
        if issecretvalue and (issecretvalue(Min) or issecretvalue(Max)) then
            -- Use neutral color when we can't determine percentage
            r, g, b = 0.52, 1, 0.52
        else
            if Max == 0 then return end
            local Perc = Min / Max
            if Perc >= STAGGER_RED_TRANSITION then r, g, b = 1, 0.52, 0.52
            elseif Perc > STAGGER_YELLOW_TRANSITION then r, g, b = 1, 0.82, 0.52
            else r, g, b = 0.52, 1, 0.52 end
        end
    elseif Resource.Type == "SECONDARY_POWER" then
        Min = UnitPower("player", Resource.PowerType)
        Max = UnitPowerMax("player", Resource.PowerType)

        local powerColor = RefineUI.Colors.Power[Resource.PowerTypeName or ""]
        if powerColor then
            r, g, b = powerColor.r, powerColor.g, powerColor.b
        else
            local classColor = RefineUI.MyClassColor or RefineUI.Colors.Class[Class]
            if classColor then
                r, g, b = classColor.r, classColor.g, classColor.b
            else
                r, g, b = 1, 1, 1
            end
        end

        if not Max or (type(Max) == "number" and Max <= 0) then
            Max = 1
            if not Min or (type(Min) == "number" and Min < 0) then
                Min = 0
            end
        end
    elseif Resource.Type == "SOUL_FRAGMENTS" then
        local BlizzBar = _G.DemonHunterSoulFragmentsBar
        if not BlizzBar then return end
        Min, Max = BlizzBar:GetValue(), select(2, BlizzBar:GetMinMaxValues())
        r, g, b = 0.55, 0.25, 2.0
    end

    -- SECRET VALUE SAFETY: Guard remaining operations
    local isSecret = issecretvalue and (issecretvalue(Min) or issecretvalue(Max))
    local allowSecretPassThrough = (Resource.Type == "SECONDARY_POWER")

    if isSecret and not allowSecretPassThrough then
        -- Do not store secret values on the custom status bar. Reuse the last safe
        -- numeric range/value (or a neutral 0/1 fallback) to avoid tainting Edit Mode
        -- paths that later touch PlayerFrame-attached children.
        local safeMax = Resource.LastSafeMax
        local safeMin = Resource.LastSafeMin

        if type(safeMax) ~= "number" or safeMax <= 0 or (issecretvalue and issecretvalue(safeMax)) then
            safeMax = 1
        end
        if type(safeMin) ~= "number" or (issecretvalue and issecretvalue(safeMin)) then
            safeMin = 0
        end

        if safeMin < 0 then safeMin = 0 end
        if safeMin > safeMax then safeMin = safeMax end

        Bar:SetMinMaxValues(0, safeMax)
        Bar:SetValue(safeMin)
    else
        if not isSecret then
            Resource.LastSafeMin = Min
            Resource.LastSafeMax = Max
        end
        Bar:SetMinMaxValues(0, Max)
        Bar:SetValue(Min)
    end

    Bar:SetStatusBarColor(r, g, b)
    
    if isSecret then
        if Resource.Text then
            if Resource.Type == "SECONDARY_POWER" then
                -- FontString can accept secret values via pass-through. Avoid formatting.
                Resource.Text:SetText(Min)
            else
                Resource.Text:SetText("")
            end
        end
        if Resource.TextPer then Resource.TextPer:SetText("") end
        HandleResourceGlow(Resource, false, r, g, b)
    else
        if Resource.Text then Resource.Text:SetText(RefineUI:ShortValue(Min)) end
        if Resource.Type == "STAGGER" and Resource.TextPer then 
            Resource.TextPer:SetText(floor(Min / Max * 1000) / 10 .. "%") 
        end
        HandleResourceGlow(Resource, (Min == Max and Min > 0), r, g, b)
    end

    if Resource.Text then
        Resource.Text:Show()
        Resource.Text:SetAlpha(1)
    end
end

---------------------------
-- Totem Bar Update      --
---------------------------

local function UpdateTotemBar(Resource)
    local anyActive = false
    for i = 1, MAX_TOTEMS do
        local Button = Resource.Buttons[i]
        local _, _, start, duration, icon = GetTotemInfo(i)
        if icon and icon ~= "" then
            Button.Icon:SetTexture(icon)
            Button.Cooldown:SetCooldown(start, duration)
            Button:FadeIn()
            anyActive = true
        else
            Button:FadeOut()
        end
    end
    
    if anyActive then
        Resource.Bar:Show()
    else
        Resource.Bar:Hide()
    end
end

---------------------------
-- Main Factory Function --
---------------------------

function UF:CreateClassResources(Frame)
    if Frame ~= PlayerFrame then return end -- Only supported for PlayerFrame currently

    -- Parent to RefineUF if possible, else Frame
    local Parent = Frame.RefineUF or Frame
    -- Note: RefineUF might not be created if this is called too early.
    -- Assuming this is called inside StyleUnitFrame where RefineUF exists.

    -- Width matching: BBF style resources usually match the bars width or frame width
    local ParentWidth = Frame.RefineUF and Frame.RefineUF.Texture:GetWidth() or 150
    -- Adjust for actual bar width approximately
    ParentWidth = 120 -- Safe approx or read config

    local Resources = UF.ClassResources
        local DataBars = Config.UnitFrames.DataBars
    local DB = DataBars -- Alias for easier access

    -- Cleanup helper
    local function CreateBaseBar(name, type, width, height, yOff)
        local frameName = "RefineUI_" .. name
        if _G[frameName] then return _G[frameName], _G[frameName].PulseGlow end

        local Parent = Frame.RefineUF or Frame
        local ParentWidth = DB.Width or 120
        width = width or ParentWidth
        height = height or DB.Height or 4
        yOff = yOff or DB.YOffset or 4
        local Bar = CreateFrame(type == "STATUS" and "StatusBar" or "Frame", frameName, Parent)
        RefineUI:AddAPI(Bar)
        Bar:Size(width, height)
        Bar._width = width -- Store for secret-safe retrieval

        -- Anchoring: Above RefineUF Texture, or relative to ManaBar?
        local anchor = (Frame.RefineUF and Frame.RefineUF.Texture) or Frame
        
        -- Fix Centering: Anchor to the actual HealthBar if possible
        if Frame.PlayerFrameContent and Frame.PlayerFrameContent.PlayerFrameContentMain then
            local hb = Frame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer
            if hb and hb.HealthBar then
                anchor = hb.HealthBar
            end
        end

        local pos = RefineUI.Positions["RefineUI_" .. name]
        if pos then
            Bar:Point(pos[1], anchor, pos[3], pos[4], pos[5])
        else
            Bar:Point("BOTTOM", anchor, "TOP", 0, yOff)
        end
        
        Bar:SetTemplate("Transparent") -- Sets up backdrop + border for small resource bars
        Bar:CreateBorder(4, 4, 8)      -- Very thin edge for short-height resource bars
        Bar:Hide()

        -- Ensure border is above segments
        if Bar.border then
            Bar.border:SetFrameLevel(Bar:GetFrameLevel() + 10)
        end

        -- Pulse Glow (Extra glow layer)
        local PulseGlow = RefineUI.CreateGlow and RefineUI.CreateGlow(Bar, 6)
        if PulseGlow then
            PulseGlow:SetFrameStrata(Bar:GetFrameStrata())
            PulseGlow:SetFrameLevel(Bar:GetFrameLevel() + 20)
            PulseGlow:SetBackdropBorderColor(1, .5, .5, 1)
            PulseGlow:Hide()
        end
        
        Bar.PulseGlow = PulseGlow

        return Bar, PulseGlow
    end

    -- 1. Class Power (Combo Points, Shards, Holy Power, Chi, Charges, Essence)
    local cpType = (Class == "ROGUE" or Class == "DRUID") and SPELL_POWER_COMBO_POINTS or
                   (Class == "WARLOCK") and SPELL_POWER_SOUL_SHARDS or
                   (Class == "PALADIN") and SPELL_POWER_HOLY_POWER or
                   (Class == "MONK") and SPELL_POWER_CHI or
                   (Class == "MAGE") and SPELL_POWER_ARCANE_CHARGES or
                   (Class == "EVOKER") and SPELL_POWER_ESSENCE

    if cpType and DataBars.ClassPowerBar then
        local Bar, Glow = CreateBaseBar("ClassPowerBar", "FRAME", nil, nil, nil)
        
        -- Resource Text
        -- Use Bar.border as parent if available so text renders ON TOP of the border
        if not Bar.Text then
            local parent = Bar.border or Bar
            local Text = parent:CreateFontString(nil, "OVERLAY")
            RefineUI:AddAPI(Text)
            Text:Point("CENTER", Bar, 0, 0)
            Text:Font(16, nil, "OUTLINE")
            Text:Hide()
            Bar.Text = Text
        end
        
        -- Preserve existing table and Segments to prevent orphaned frames
        if not Resources.ClassPower then
            Resources.ClassPower = { 
                Bar = Bar, 
                PulseGlow = Glow, 
                Type = "CLASS_POWER", 
                Segments = {}, 
                Text = Bar.Text 
            }
        else
            -- Update mutable properties
            local r = Resources.ClassPower
            r.Bar = Bar
            r.PulseGlow = Glow
            r.Type = "CLASS_POWER"
            r.Height = DB.Height or 8
            r.Text = Bar.Text
            -- NOTE: r.Segments is preserved!
        end
        Resources.ClassPower.PowerType = cpType
        Resources.ClassPower.Height = DB.Height or 8
        Bar:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
        Bar:RegisterUnitEvent("UNIT_MAXPOWER", "player")
        Bar:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
        Bar:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        Bar:RegisterEvent("PLAYER_ENTERING_WORLD")

        -- Store power type name for event filtering
        local PowerTypeNames = {
            [SPELL_POWER_COMBO_POINTS] = "COMBO_POINTS",
            [SPELL_POWER_SOUL_SHARDS] = "SOUL_SHARDS",
            [SPELL_POWER_HOLY_POWER] = "HOLY_POWER",
            [SPELL_POWER_CHI] = "CHI",
            [SPELL_POWER_ARCANE_CHARGES] = "ARCANE_CHARGES",
            [SPELL_POWER_ESSENCE] = "ESSENCE",
        }
        Resources.ClassPower.PowerTypeName = PowerTypeNames[cpType]
        
        local function ShouldShowClassPower(spec)
            return (Class == "ROGUE" or Class == "WARLOCK" or Class == "PALADIN" or Class == "EVOKER") or
                   (Class == "DRUID" and UnitPowerType("player") == SPELL_POWER_ENERGY) or
                   (Class == "MONK" and spec == SPEC_INDEX_MONK_WINDWALKER) or (Class == "MAGE" and spec == 1)
        end

        local function QueueClassPowerUpdate()
            local resource = Resources.ClassPower
            if not resource or resource.updateQueued then return end
            resource.updateQueued = true
            C_Timer.After(0, function()
                local r = Resources.ClassPower
                if not r then return end
                r.updateQueued = false

                local spec = GetSpecialization()
                if ShouldShowClassPower(spec) then
                    Bar:Show()
                    UpdateSegmentedBar(r)
                else
                    Bar:Hide()
                end
            end)
        end
        
        Bar:SetScript("OnEvent", function(self, event, unit, powerType)
            if event == "UNIT_POWER_UPDATE" then
                if unit ~= "player" then return end
                if powerType ~= Resources.ClassPower.PowerTypeName then return end
            elseif event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
                if unit ~= "player" then return end
            end

            QueueClassPowerUpdate()
        end)
        
        -- Hide Blizzard
        HideBlizzardResource(_G.ComboPointPlayerFrame)
        HideBlizzardResource(_G.WarlockShardBarFrame)
        HideBlizzardResource(_G.PaladinPowerBarFrame)
        HideBlizzardResource(_G.MonkHarmonyBarFrame)
        HideBlizzardResource(_G.MageArcaneChargesFrame)
        HideBlizzardResource(_G.EvokerEssencePlayerFrame)
        HideBlizzardResource(_G.EssencePlayerFrame) -- Evoker Alternative
        HideBlizzardResource(_G.EvokerEbonMightBar) -- Augmentation default timer bar
        
        -- Nameplate Variants
        HideBlizzardResource(_G.ClassNameplateBarRogueFrame)
        HideBlizzardResource(_G.ClassNameplateBarWarlockFrame)
        HideBlizzardResource(_G.ClassNameplateBarPaladinFrame)
        HideBlizzardResource(_G.ClassNameplateBarMonkFrame)
        HideBlizzardResource(_G.ClassNameplateBarMageFrame)
        HideBlizzardResource(_G.ClassNameplateBarDracthyrFrame)
    end

    -- 1b. Secondary Power (Shadow Priest / Balance Druid / Elemental Shaman)
    if (Class == "PRIEST" or Class == "DRUID" or Class == "SHAMAN") and DataBars.SecondaryPowerBar then
        local Bar, Glow = CreateBaseBar("SecondaryPowerBar", "STATUS", nil, DB.HeightLarge or 16, DB.YOffset or 4)
        Bar:SetStatusBarTexture(RESOURCE_BAR_TEXTURE)

        if not Bar.Text then
            local parent = Bar.border or Bar
            local Text = parent:CreateFontString(nil, "OVERLAY")
            RefineUI:AddAPI(Text)
            Text:Point("CENTER", Bar, 0, 0)
            Text:Font(18, nil, "OUTLINE")
            Text:Hide()
            Bar.Text = Text
        end

        if not Resources.SecondaryPower then
            Resources.SecondaryPower = {
                Bar = Bar,
                PulseGlow = Glow,
                Type = "SECONDARY_POWER",
                Text = Bar.Text,
            }
        else
            local r = Resources.SecondaryPower
            r.Bar = Bar
            r.PulseGlow = Glow
            r.Type = "SECONDARY_POWER"
            r.Text = Bar.Text
        end

        Bar:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
        Bar:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
        Bar:RegisterUnitEvent("UNIT_MAXPOWER", "player")
        Bar:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
        Bar:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        Bar:RegisterEvent("PLAYER_ENTERING_WORLD")

        local function QueueSecondaryPowerUpdate()
            local resource = Resources.SecondaryPower
            if not resource or resource.updateQueued then return end
            resource.updateQueued = true

            C_Timer.After(0, function()
                local r = Resources.SecondaryPower
                if not r then return end
                r.updateQueued = false

                local powerType, powerTypeName = GetPlayerSecondaryPowerInfo()
                if not powerType or not powerTypeName then
                    Bar:Hide()
                    return
                end

                r.PowerType = powerType
                r.PowerTypeName = powerTypeName
                Bar:Show()
                UpdateStatusBar(r)
            end)
        end

        Bar:SetScript("OnEvent", function(_, event, unit)
            if event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" then
                if unit ~= "player" then return end
            elseif event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
                if unit ~= "player" then return end
            end

            QueueSecondaryPowerUpdate()
        end)

        -- Player-frame-only secondary resource visuals handled by RefineUI.
        HideBlizzardResource(_G.AlternatePowerBar)
        HideBlizzardResource(_G.InsanityBarFrame)
    end

    -- 2. Runes (Death Knight)
    if Class == "DEATHKNIGHT" and DataBars.RuneBar then
        local Bar, Glow = CreateBaseBar("RuneBar", "FRAME", nil, DB.HeightLarge or 16, nil)
        if not Bar.Background then
            local bg = Bar:CreateTexture(nil, "ARTWORK", nil, -1)
            bg:SetAllPoints(Bar)
            bg:SetTexture(RESOURCE_BAR_TEXTURE)
            bg:SetVertexColor(0.06, 0.06, 0.08, 0.9)
            Bar.Background = bg
        end
        if not Resources.Runes then
            Resources.Runes = { Bar = Bar, PulseGlow = Glow, Type = "RUNES", Segments = {}, Height = DB.HeightLarge or 16 }
        else
            -- Update properties, preserve Segments
            local r = Resources.Runes
            r.Bar = Bar; r.PulseGlow = Glow; r.Height = DB.HeightLarge or 16
        end
        Bar:RegisterEvent("RUNE_POWER_UPDATE"); Bar:RegisterEvent("PLAYER_ENTERING_WORLD"); Bar:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        Bar:SetScript("OnEvent", function() Bar:Show(); UpdateSegmentedBar(Resources.Runes) end)
        
        -- Hide Blizzard
        HideBlizzardResource(_G.DeathKnightResourceBar)
    end

    -- 3. Maelstrom (Enhancement Shaman Maelstrom Weapon stacks)
    if Class == "SHAMAN" and DB.MaelstromBar then
        local Bar, Glow = CreateBaseBar("MaelstromBar", "FRAME", nil, DB.HeightLarge or 16, DB.YOffset or 4)
        
        local textParent = Bar.border or Bar
        if not Bar.Text then
            local Text = textParent:CreateFontString(nil, "OVERLAY")
            RefineUI:AddAPI(Text)
            Text:Point("CENTER", Bar, 0, 0)
            Text:Font(22)
            if Text.SetDrawLayer then
                Text:SetDrawLayer("OVERLAY", 7)
            end
            Bar.Text = Text
        else
            if Bar.Text:GetParent() ~= textParent then
                Bar.Text:SetParent(textParent)
            end
            if Bar.Text.SetDrawLayer then
                Bar.Text:SetDrawLayer("OVERLAY", 7)
            end
        end
        
        if not Resources.Maelstrom then
            Resources.Maelstrom = { Bar = Bar, PulseGlow = Glow, Type = "MAELSTROM", Segments = {}, Height = DB.HeightLarge or 16, Text = Bar.Text }
        else
            local r = Resources.Maelstrom
            r.Bar = Bar; r.PulseGlow = Glow; r.Height = DB.HeightLarge or 16; r.Text = Bar.Text
        end
        Bar:RegisterEvent("UNIT_AURA"); Bar:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED"); Bar:RegisterEvent("PLAYER_ENTERING_WORLD")
        Bar:SetScript("OnEvent", function() 
            if GetSpecialization() == SPEC_INDEX_SHAMAN_ENHANCEMENT then Bar:Show(); UpdateSegmentedBar(Resources.Maelstrom) else Bar:Hide() end
        end)
    end

    -- 4. Stagger (Brewmaster Monk)
    if Class == "MONK" and DB.StaggerBar then
        local Bar, Glow = CreateBaseBar("StaggerBar", "STATUS", nil, DB.HeightLarge or 16, DB.YOffset or 4)
        Bar:SetStatusBarTexture(RESOURCE_BAR_TEXTURE)
        
        if not Bar.Text then
            local T1 = Bar:CreateFontString(nil, "OVERLAY")
            RefineUI:AddAPI(T1)
            T1:Point("LEFT", Bar, 6, 0)
            T1:Font(16)
            Bar.Text = T1
        end
        
        if not Bar.TextPer then
            local T2 = Bar:CreateFontString(nil, "OVERLAY")
            RefineUI:AddAPI(T2)
            T2:Point("RIGHT", Bar, -6, 0)
            T2:Font(16)
            Bar.TextPer = T2
        end
        
        if not Resources.Stagger then
            Resources.Stagger = { Bar = Bar, PulseGlow = Glow, Type = "STAGGER", Text = Bar.Text, TextPer = Bar.TextPer }
        else
            local r = Resources.Stagger
            r.Bar = Bar; r.PulseGlow = Glow; r.Text = Bar.Text; r.TextPer = Bar.TextPer
        end
        Bar:RegisterEvent("UNIT_AURA"); Bar:RegisterEvent("UNIT_MAXPOWER"); Bar:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        Bar:RegisterEvent("PLAYER_ENTERING_WORLD")
        Bar:SetScript("OnEvent", function()
            if GetSpecialization() == SPEC_INDEX_MONK_BREWMASTER then Bar:Show(); UpdateStatusBar(Resources.Stagger) else Bar:Hide() end
        end)

        HideBlizzardResource(_G.MonkStaggerBar)
    end

    -- 5. Soul Fragments (Vengeance/Devourer Demon Hunter)
    if Class == "DEMONHUNTER" and GetSpecialization() == 2 and DB.SoulFragmentsBar then
        local Bar, Glow = CreateBaseBar("SoulFragmentsBar", "STATUS", nil, DB.Height or 4, DB.YOffset or 4)
        Bar:SetStatusBarTexture(RESOURCE_BAR_TEXTURE)
        
        if not Bar.Text then
            local Text = Bar:CreateFontString(nil, "OVERLAY")
            RefineUI:AddAPI(Text)
            Text:Point("CENTER", Bar, 0, 0)
            Text:Font(16)
            Bar.Text = Text
        end
        
        if not Resources.SoulFragments then
            Resources.SoulFragments = { Bar = Bar, PulseGlow = Glow, Type = "SOUL_FRAGMENTS", Text = Bar.Text }
        else
            local r = Resources.SoulFragments
            r.Bar = Bar; r.PulseGlow = Glow; r.Text = Bar.Text
        end
        Bar:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
        Bar:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        Bar:RegisterEvent("PLAYER_ENTERING_WORLD")

        local function QueueSoulFragmentsUpdate()
            local resource = Resources.SoulFragments
            if not resource or resource.updateQueued then return end
            resource.updateQueued = true
            C_Timer.After(0, function()
                local r = Resources.SoulFragments
                if not r then return end
                r.updateQueued = false
                if GetSpecialization() == 2 then
                    Bar:Show()
                    UpdateStatusBar(r)
                else
                    Bar:Hide()
                end
            end)
        end

        Bar:SetScript("OnEvent", function(_, event, unit, powerType)
            if event == "UNIT_POWER_UPDATE" then
                if unit ~= "player" then return end
                if powerType ~= "SOUL_FRAGMENTS" then return end
            end
            QueueSoulFragmentsUpdate()
        end)
        
        -- Hide Blizzard
        HideBlizzardResource(_G.DemonHunterSoulFragmentsBar)
    end

    -- 6. Totems
    if DB.TotemBar and (Class == "SHAMAN" or Class == "DRUID" or Class == "MONK") then
        local Bar, Glow = CreateBaseBar("TotemBar", "FRAME", nil, 14, DB.YOffset or 4)
        local Buttons = Bar.Buttons or {}
        local ParentWidth = DB.Width or 120
        local bSize = math.floor((ParentWidth - (MAX_TOTEMS - 1) * (DB.Spacing or 2)) / MAX_TOTEMS)
        
        if not Bar.Buttons then
            for i = 1, MAX_TOTEMS do
                local B = CreateFrame("Frame", nil, Bar)
                RefineUI:AddAPI(B)
                B:SetID(i)
                B:Size(bSize, 12)
                B:SetTemplate("Default")
                
                B:SetAlpha(0)
                if i == 1 then 
                    B:Point("LEFT", Bar) 
                else 
                    B:Point("LEFT", Buttons[i-1], "RIGHT", 2, 0) 
                end
                
                B.Icon = B:CreateTexture(nil, "OVERLAY")
                RefineUI.SetInside(B.Icon)
                B.Icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
                
                B.Cooldown = CreateFrame("Cooldown", nil, B, "CooldownFrameTemplate")
                RefineUI.SetInside(B.Cooldown)
                B.Cooldown:SetHideCountdownNumbers(false)
                
                if Class == "SHAMAN" then
                    local D = CreateFrame("Button", nil, B, "SecureUnitButtonTemplate")
                    D:SetID(i)
                    D:SetAllPoints()
                    D:RegisterForClicks("RightButtonUp")
                    -- Note: destroytotem requires secure environment or careful handling
                    D:SetAttribute("type2", "destroytotem")
                    D:SetAttribute("*totem-slot*", i)

                end
                Buttons[i] = B
            end
            Bar.Buttons = Buttons
        end
        
        if not Resources.Totems then
            Resources.Totems = { Bar = Bar, PulseGlow = Glow, Type = "TOTEM", Buttons = Buttons }
        else
            local r = Resources.Totems
            r.Bar = Bar; r.PulseGlow = Glow; r.Buttons = Buttons -- Buttons ref is reused from Bar.Buttons
        end
        
        Bar:RegisterEvent("PLAYER_TOTEM_UPDATE"); Bar:RegisterEvent("PLAYER_ENTERING_WORLD")
        Bar:SetScript("OnEvent", function() Bar:Show(); UpdateTotemBar(Resources.Totems) end)
        
        HideBlizzardResource(_G.TotemFrame)
    end
end

