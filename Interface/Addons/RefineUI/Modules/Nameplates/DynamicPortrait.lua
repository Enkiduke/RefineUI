----------------------------------------------------------------------------------------
-- Dynamic Portrait for RefineUI Nameplates
-- Description: Handles radial status bars, quest icons, and cast icons for nameplates
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local C = RefineUI.Config

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local _G = _G
local canaccessvalue = _G.canaccessvalue
local math = math
local pairs, ipairs, unpack, select = pairs, ipairs, unpack, select
local strmatch = string.match
local wipe = table.wipe

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local GetTime = GetTime
local UnitGUID = UnitGUID
local UnitName = UnitName
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local IsInInstance = IsInInstance
local SetPortraitTexture = SetPortraitTexture
local C_QuestLog = C_QuestLog
local GetQuestLogSpecialItemInfo = GetQuestLogSpecialItemInfo
local GetNumQuestLeaderBoards = GetNumQuestLeaderBoards
local GetQuestObjectiveInfo = GetQuestObjectiveInfo
local THREAT_TOOLTIP = THREAT_TOOLTIP
local C_TooltipInfo = C_TooltipInfo
local CreateColor = CreateColor
local C_Spell = C_Spell

----------------------------------------------------------------------------------------
-- Locals & Cache
----------------------------------------------------------------------------------------
local M = RefineUI.Media.Textures
local ThreatTooltip = THREAT_TOOLTIP:gsub("%%d", "%%d-")
local tooltipCache = setmetatable({}, { __mode = "v" }) -- Weak-valued for GC safety
local NameplatesUtil = RefineUI.NameplatesUtil
local IsSecret = NameplatesUtil.IsSecret
local HasValue = NameplatesUtil.HasValue
local ReadSafeBoolean = NameplatesUtil.ReadSafeBoolean
local IsTargetNameplateUnitFrame = NameplatesUtil.IsTargetNameplateUnitFrame

-- External Data Registry to prevent Taint
RefineUI.NameplateData = RefineUI.NameplateData or setmetatable({}, { __mode = "k" })
local IMPORTANT_CAST_GLOW_ATLAS = "PowerSwirlAnimation-SpinningGlowys"
local IMPORTANT_CAST_GLOW_PADDING = 0
local IMPORTANT_CAST_GLOW_ALPHA = 1
local IMPORTANT_CAST_GLOW_ROTATION_SECONDS = 1.2
local IMPORTANT_CAST_GLOW_TEST_ALL_CASTS = false
local BASE_PORTRAIT_SIZE = 36
local DYNAMIC_PORTRAIT_SCALE_MIN = 0.5
local DYNAMIC_PORTRAIT_SCALE_MAX = 2.0
local DEFAULT_BORDER_COLOR = { 0.25, 0.25, 0.25, 1 }
local DEFAULT_CAST_COLOR = { 1, 0.7, 0 }
local CAST_START_EVENTS = {
    UNIT_SPELLCAST_START = true,
    UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_EMPOWER_START = true,
}
local CAST_STOP_EVENTS = {
    UNIT_SPELLCAST_STOP = true,
    UNIT_SPELLCAST_FAILED = true,
    UNIT_SPELLCAST_INTERRUPTED = true,
    UNIT_SPELLCAST_SUCCEEDED = true,
    UNIT_SPELLCAST_CHANNEL_STOP = true,
    UNIT_SPELLCAST_EMPOWER_STOP = true,
}
local cachedCastSignalInterruptibleColor = nil
local cachedCastSignalNonInterruptibleColor = nil
local cachedCastSignalInterruptibleR, cachedCastSignalInterruptibleG, cachedCastSignalInterruptibleB, cachedCastSignalInterruptibleA = nil, nil, nil, nil
local cachedCastSignalNonInterruptibleR, cachedCastSignalNonInterruptibleG, cachedCastSignalNonInterruptibleB, cachedCastSignalNonInterruptibleA = nil, nil, nil, nil

local function GetConfiguredDynamicPortraitScale()
    local cfg = C and C.Nameplates
    local scale = tonumber(cfg and cfg.DynamicPortraitScale) or 1
    if scale < DYNAMIC_PORTRAIT_SCALE_MIN then
        return DYNAMIC_PORTRAIT_SCALE_MIN
    end
    if scale > DYNAMIC_PORTRAIT_SCALE_MAX then
        return DYNAMIC_PORTRAIT_SCALE_MAX
    end
    return scale
end

local function GetConfiguredDynamicPortraitSize()
    return RefineUI:Scale(BASE_PORTRAIT_SIZE * GetConfiguredDynamicPortraitScale())
end

local function IsCastBarActive(castBar)
    if not castBar then
        return false
    end

    if castBar.IsShown and not castBar:IsShown() then
        return false
    end

    if ReadSafeBoolean(castBar.casting) == true then
        return true
    end
    if ReadSafeBoolean(castBar.channeling) == true then
        return true
    end
    if ReadSafeBoolean(castBar.reverseChanneling) == true then
        return true
    end

    local barType = castBar.barType
    if not IsSecret(barType) and type(barType) == "string" then
        if barType == "standard"
            or barType == "channel"
            or barType == "uninterruptable"
            or barType == "uninterruptible" then
            return true
        end
    end

    return false
end

----------------------------------------------------------------------------------------
-- Radial Statusbar Logic
----------------------------------------------------------------------------------------

local function SetRadialStatusBarValue(self, value)
    if not value or value <= 0 then
        self:SetCooldown(0, 0) -- Clear
        self:SetAlpha(0)     -- Hide
        return
    end
    self:SetAlpha(1)
    
    self:SetReverse(true)
    
    local duration = 40 
    local start = GetTime() - (value * duration)
    
    self:SetCooldown(start, duration)
    self:Pause()
end

-- CreateRadialStatusBar that returns a Cooldown Frame
function RefineUI.CreateRadialStatusBar(parent)
    local bar = CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")
    bar:SetHideCountdownNumbers(true) 
    bar:SetEdgeTexture("Interface\\Cooldown\\edge") 
    bar:SetSwipeColor(1, 0.82, 0, 1) 
    bar:SetDrawEdge(false)
    bar:SetDrawBling(false)
    bar:SetDrawSwipe(true)
    bar:SetReverse(true) 
    
    bar.SetRadialStatusBarValue = SetRadialStatusBarValue
    
    -- Wrapper for SetVertexColor since Cooldown uses SetSwipeColor
    bar.SetVertexColor = function(self, r, g, b, a)
        self:SetSwipeColor(r, g, b, a or 1)
    end
    
    -- Wrapper for SetTexture to set the Swipe Texture
    bar.SetTexture = function(self, texture)
        self:SetSwipeTexture(texture)
    end

    return bar
end

----------------------------------------------------------------------------------------
-- Quest Scanning Logic
----------------------------------------------------------------------------------------

-- (Omitted details for brevity, largely unchanged logic)
local function CheckTextForQuest(text)
    if IsSecret(text) or type(text) ~= "string" then
        return nil, false
    end

    local x, y = strmatch(text, "(%d+)/(%d+)")
    if x and y then
        return tonumber(x) / tonumber(y), x == y
    elseif not strmatch(text, ThreatTooltip) then
        local progress = tonumber(strmatch(text, "([%d%.]+)%%"))
        if progress and progress <= 100 then
            return progress / 100, progress == 100, true
        end
    end
    return nil, false
end

local function GetQuestInfoFromTooltip(unit)
    if IsSecret(unit) or type(unit) ~= "string" then return nil end

    -- Safe C_QuestLog check
    if not C_QuestLog.UnitIsRelatedToActiveQuest(unit) then return nil end

    local guid = UnitGUID(unit)
    -- Secret Protection: prevent table index is secret error
    local isSecret = IsSecret(guid)

    if not isSecret and tooltipCache[guid] then return tooltipCache[guid] end

    local tooltipData = C_TooltipInfo.GetUnit(unit)
    if not tooltipData then return nil end

    for i, line in ipairs(tooltipData.lines) do
        if line.type == 17 and line.id then
             local questID = line.id
             
             for j = i + 1, #tooltipData.lines do
                 local subLine = tooltipData.lines[j]
                 local leftText = subLine and subLine.leftText
                 local hasProgressText = false
                 if not IsSecret(leftText) and type(leftText) == "string" then
                     hasProgressText = (strmatch(leftText, "(%d+)/(%d+)") or strmatch(leftText, "%%")) and true or false
                 end
                 
                 if subLine.type == 18 or hasProgressText then 
                     local text = leftText
                     local progress, isComplete, isPercent = CheckTextForQuest(text)
                     
                     if not progress then
                         progress = 0
                         isComplete = false
                     end

                     if not isComplete then
                         local result = {
                             isPercent = isPercent,
                             objectiveProgress = progress,
                             questType = "DEFAULT",
                             questID = questID
                         }
                        if not isSecret then
                             tooltipCache[guid] = result
                         end
                         return result
                     end
                 elseif subLine.type == 17 then
                     break
                 end
             end
             
             local result = {
                 isPercent = false,
                 objectiveProgress = 0,
                 questType = "DEFAULT",
                 questID = questID
             }
             if not isSecret then
                 tooltipCache[guid] = result
             end
             return result
        end
    end
    
    return nil
end

----------------------------------------------------------------------------------------
-- Border Color Management (Centralized)
----------------------------------------------------------------------------------------

local function SetColorBorder(frame, r, g, b)
    if not frame then return end
    
    if frame.border then
        if frame.border.SetBackdropBorderColor then
            frame.border:SetBackdropBorderColor(r, g, b)
        elseif frame.border.SetVertexColor then
            frame.border:SetVertexColor(r, g, b)
        end
    elseif frame.SetBackdropBorderColor then
        frame:SetBackdropBorderColor(r, g, b)
    end
end

local function IsAccessibleColorComponent(v)
    if v == nil then return false end
    if IsSecret(v) then return false end
    if canaccessvalue and not canaccessvalue(v) then return false end
    return type(v) == "number"
end

local function GetNameplateCastRenderedColor(castBar)
    if not castBar then
        return nil, nil, nil
    end

    local r, g, b
    if RefineUI.GetNameplateCastRenderedColor then
        r, g, b = RefineUI:GetNameplateCastRenderedColor(castBar)
    elseif castBar.GetStatusBarTexture then
        local tex = castBar:GetStatusBarTexture()
        if tex and tex.GetVertexColor then
            r, g, b = tex:GetVertexColor()
        end
    end

    if IsAccessibleColorComponent(r) and IsAccessibleColorComponent(g) and IsAccessibleColorComponent(b) then
        return r, g, b
    end

    return nil, nil, nil
end

local function GetPortraitCastSignalColors()
    local castPalette = RefineUI.Colors and RefineUI.Colors.Cast
    local interruptible = castPalette and castPalette.Interruptible or DEFAULT_CAST_COLOR
    local nonInterruptible = castPalette and castPalette.NonInterruptible or DEFAULT_CAST_COLOR

    local intR = tonumber(interruptible[1]) or DEFAULT_CAST_COLOR[1]
    local intG = tonumber(interruptible[2]) or DEFAULT_CAST_COLOR[2]
    local intB = tonumber(interruptible[3]) or DEFAULT_CAST_COLOR[3]
    local intA = tonumber(interruptible[4]) or 1

    if cachedCastSignalInterruptibleColor == nil
        or cachedCastSignalInterruptibleR ~= intR
        or cachedCastSignalInterruptibleG ~= intG
        or cachedCastSignalInterruptibleB ~= intB
        or cachedCastSignalInterruptibleA ~= intA then
        cachedCastSignalInterruptibleColor = CreateColor(
            intR,
            intG,
            intB,
            intA
        )
        cachedCastSignalInterruptibleR = intR
        cachedCastSignalInterruptibleG = intG
        cachedCastSignalInterruptibleB = intB
        cachedCastSignalInterruptibleA = intA
    end

    local nonIntR = tonumber(nonInterruptible[1]) or DEFAULT_CAST_COLOR[1]
    local nonIntG = tonumber(nonInterruptible[2]) or DEFAULT_CAST_COLOR[2]
    local nonIntB = tonumber(nonInterruptible[3]) or DEFAULT_CAST_COLOR[3]
    local nonIntA = tonumber(nonInterruptible[4]) or 1

    if cachedCastSignalNonInterruptibleColor == nil
        or cachedCastSignalNonInterruptibleR ~= nonIntR
        or cachedCastSignalNonInterruptibleG ~= nonIntG
        or cachedCastSignalNonInterruptibleB ~= nonIntB
        or cachedCastSignalNonInterruptibleA ~= nonIntA then
        cachedCastSignalNonInterruptibleColor = CreateColor(
            nonIntR,
            nonIntG,
            nonIntB,
            nonIntA
        )
        cachedCastSignalNonInterruptibleR = nonIntR
        cachedCastSignalNonInterruptibleG = nonIntG
        cachedCastSignalNonInterruptibleB = nonIntB
        cachedCastSignalNonInterruptibleA = nonIntA
    end

    return cachedCastSignalInterruptibleColor, cachedCastSignalNonInterruptibleColor
end

local function ApplyPortraitCastSignalColor(borderTexture, signal)
    if not borderTexture or signal == nil then
        return false
    end
    if not borderTexture.SetVertexColorFromBoolean then
        return false
    end

    local interruptibleColorObj, nonInterruptibleColorObj = GetPortraitCastSignalColors()
    borderTexture:SetVertexColorFromBoolean(
        signal,
        nonInterruptibleColorObj,
        interruptibleColorObj
    )
    return true
end

local function ReadAccessibleSpellIdentifier(value)
    if value == nil or IsSecret(value) then
        return nil
    end
    if canaccessvalue and not canaccessvalue(value) then
        return nil
    end

    local valueType = type(value)
    if valueType == "number" or valueType == "string" then
        return value
    end

    return nil
end

local function GetCastBarSpellIdentifier(castBar)
    if not castBar then
        return nil
    end

    local spellIdentifier = ReadAccessibleSpellIdentifier(castBar.spellID)
    if spellIdentifier then
        return spellIdentifier
    end

    spellIdentifier = ReadAccessibleSpellIdentifier(castBar.channelSpellID)
    if spellIdentifier then
        return spellIdentifier
    end

    spellIdentifier = ReadAccessibleSpellIdentifier(castBar.castingSpellID)
    if spellIdentifier then
        return spellIdentifier
    end

    return nil
end

local function GetActiveCastSpellIdentifier(unit, castBar)
    if IsSecret(unit) or type(unit) ~= "string" then
        return GetCastBarSpellIdentifier(castBar)
    end

    local castName, _, _, _, _, _, _, _, castSpellID = UnitCastingInfo(unit)
    if HasValue(castName) then
        return ReadAccessibleSpellIdentifier(castSpellID)
    end

    local channelName, _, _, _, _, _, _, channelSpellID = UnitChannelInfo(unit)
    if HasValue(channelName) then
        return ReadAccessibleSpellIdentifier(channelSpellID)
    end

    return GetCastBarSpellIdentifier(castBar)
end

local function SafeIsSpellImportant(spellIdentifier)
    if not spellIdentifier then
        return false
    end
    if not C_Spell or type(C_Spell.IsSpellImportant) ~= "function" then
        return false
    end

    local ok, result = pcall(C_Spell.IsSpellImportant, spellIdentifier)
    if not ok then
        return false
    end

    return ReadSafeBoolean(result) == true
end

local function EnsurePortraitImportantCastGlow(data)
    if not data then return nil end
    if data.PortraitImportantCastGlow then
        return data.PortraitImportantCastGlow
    end
    if not data.PortraitFrame then
        return nil
    end

    local glow = data.PortraitFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    if not glow then
        return nil
    end

    if not glow.SetAtlas then
        return nil
    end

    local atlasOk = pcall(glow.SetAtlas, glow, IMPORTANT_CAST_GLOW_ATLAS, false)
    if not atlasOk then
        return nil
    end

    RefineUI.SetOutside(glow, data.PortraitFrame, IMPORTANT_CAST_GLOW_PADDING, IMPORTANT_CAST_GLOW_PADDING)
    glow:SetBlendMode("ADD")
    glow:SetAlpha(IMPORTANT_CAST_GLOW_ALPHA)
    glow:Hide()

    local spin = glow:CreateAnimationGroup()
    spin:SetLooping("REPEAT")

    local rotation = spin:CreateAnimation("Rotation")
    rotation:SetOrder(1)
    rotation:SetDuration(IMPORTANT_CAST_GLOW_ROTATION_SECONDS)
    rotation:SetDegrees(-360)
    rotation:SetOrigin("CENTER", 0, 0)

    data.PortraitImportantCastGlow = glow
    data.PortraitImportantCastGlowAnim = spin

    return glow
end

local function SetPortraitImportantCastGlow(data, enabled)
    if not data then
        return
    end

    local shouldShow = enabled == true
    if data.PortraitImportantCastGlowShown == shouldShow then
        return
    end

    data.PortraitImportantCastGlowShown = shouldShow
    local glow = data.PortraitImportantCastGlow
    local spin = data.PortraitImportantCastGlowAnim

    if shouldShow then
        glow = glow or EnsurePortraitImportantCastGlow(data)
        spin = data.PortraitImportantCastGlowAnim
        if not glow then
            data.PortraitImportantCastGlowShown = false
            return
        end

        glow:Show()
        if spin and not spin:IsPlaying() then
            spin:Play()
        end
        return
    end

    if spin and spin:IsPlaying() then
        spin:Stop()
    end
    if glow then
        glow:Hide()
    end
end

function RefineUI:UpdateBorderColors(unitFrame, forceCastCheck)
    if not unitFrame then return end
    local unit = unitFrame.unit
    if not unit then return end
    
    local data = RefineUI.NameplateData[unitFrame]
    if not data then return end
    
    -- Priority 1: Check for active cast
    local castBar = unitFrame.castBar or unitFrame.CastBar
    local castSignal, hasCastSignal
    local castColor
    local castColorR, castColorG, castColorB
    local hasActiveCast = false
    local castBarActive = false
    local importantCastActive = false
    if forceCastCheck ~= false then
        castBarActive = IsCastBarActive(castBar)

        if RefineUI.GetNameplateCastInterruptibilitySignal then
            castSignal, hasCastSignal = RefineUI:GetNameplateCastInterruptibilitySignal(unit, castBar)
            hasActiveCast = hasCastSignal == true
        end

        if not hasActiveCast and castBarActive then
            hasActiveCast = true
        end

        -- Only use cast color while a cast/channel is actually active.
        if hasActiveCast or hasCastSignal == nil or castBarActive then
            castColorR, castColorG, castColorB = GetNameplateCastRenderedColor(castBar)
            if castColorR == nil or castColorG == nil or castColorB == nil then
                castColor = RefineUI:GetCastColor(unit, castBar)
                if type(castColor) == "table" then
                    castColorR = castColor[1]
                    castColorG = castColor[2]
                    castColorB = castColor[3]
                end
            end
            if (hasCastSignal == nil or hasCastSignal == false)
                and castColorR ~= nil and castColorG ~= nil and castColorB ~= nil then
                hasActiveCast = true
            end
            if (castColorR == nil or castColorG == nil or castColorB == nil) and hasActiveCast then
                local fallbackCastColor = RefineUI.Colors and RefineUI.Colors.Cast and RefineUI.Colors.Cast.Interruptible
                    or DEFAULT_CAST_COLOR
                castColorR = fallbackCastColor[1]
                castColorG = fallbackCastColor[2]
                castColorB = fallbackCastColor[3]
            end
        end

        if hasActiveCast then
            if IMPORTANT_CAST_GLOW_TEST_ALL_CASTS then
                importantCastActive = true
            else
                local spellIdentifier = GetActiveCastSpellIdentifier(unit, castBar)
                if spellIdentifier then
                    importantCastActive = SafeIsSpellImportant(spellIdentifier)
                end
            end
        end
    end
    
    -- Priority 2: Check target status
    local isTarget = IsTargetNameplateUnitFrame(unitFrame)
    data.isTarget = isTarget
    
    -- Determine colors
    local nameplatesConfig = C and C.Nameplates
    local generalConfig = C and C.General
    local targetColor = isTarget and nameplatesConfig and nameplatesConfig.TargetBorderColor
    local ccConfig = nameplatesConfig and (nameplatesConfig.CrowdControl or nameplatesConfig.CrowdControlTest)
    local ccColor = nil
    if data.CrowdControlActive and ccConfig and ccConfig.Enable ~= false then
        ccColor = ccConfig.BorderColor or ccConfig.Color
    end
    local defaultColor = (generalConfig and generalConfig.BorderColor) or DEFAULT_BORDER_COLOR
    local nameplateColor = targetColor or defaultColor
    local portraitColorR = defaultColor[1] or DEFAULT_BORDER_COLOR[1]
    local portraitColorG = defaultColor[2] or DEFAULT_BORDER_COLOR[2]
    local portraitColorB = defaultColor[3] or DEFAULT_BORDER_COLOR[3]

    if hasActiveCast and castColorR ~= nil and castColorG ~= nil and castColorB ~= nil then
        portraitColorR = castColorR
        portraitColorG = castColorG
        portraitColorB = castColorB
    elseif ccColor then
        portraitColorR = ccColor[1] or portraitColorR
        portraitColorG = ccColor[2] or portraitColorG
        portraitColorB = ccColor[3] or portraitColorB
    elseif targetColor then
        portraitColorR = targetColor[1] or portraitColorR
        portraitColorG = targetColor[2] or portraitColorG
        portraitColorB = targetColor[3] or portraitColorB
    end
    
    -- Apply to nameplate border (Target or Default only)
    if data.RefineBorder then
        SetColorBorder(
            data.RefineBorder,
            nameplateColor[1] or DEFAULT_BORDER_COLOR[1],
            nameplateColor[2] or DEFAULT_BORDER_COLOR[2],
            nameplateColor[3] or DEFAULT_BORDER_COLOR[3]
        )
    end

    SetPortraitImportantCastGlow(data, importantCastActive)
    
    -- Apply to portrait border (Cast > CC > Target > Default)
    if data.PortraitBorder then
        local appliedCastSignal = false
        if forceCastCheck ~= false and hasCastSignal == true then
            appliedCastSignal = ApplyPortraitCastSignalColor(data.PortraitBorder, castSignal)
        end

        if not appliedCastSignal then
            data.PortraitBorder:SetVertexColor(portraitColorR, portraitColorG, portraitColorB)
        end
    end
end

----------------------------------------------------------------------------------------
-- Portrait Update Logic
----------------------------------------------------------------------------------------

function RefineUI:UpdateDynamicPortrait(nameplate, unit, event)
    if not nameplate then return end
    if IsSecret(unit) or type(unit) ~= "string" then return end
    
    local unitFrame = nameplate.UnitFrame
    if not unitFrame then return end
    
    local data = RefineUI.NameplateData[unitFrame]
    if not data then return end
    local desiredPortraitScale = GetConfiguredDynamicPortraitScale()
    local desiredPortraitSize = GetConfiguredDynamicPortraitSize()

    -- Lazy Creation of Portrait Elements
    -- Optimization: Only create these if the unit is not hidden (hostile) or is starting a cast
    if not data.PortraitFrame and not data.RefineHidden then
        local parent = data.HealthBorderOverlay or unitFrame
        local pf = CreateFrame("Frame", nil, parent)
        
        if data.HealthBorderOverlay then
            pf:SetFrameLevel(data.HealthBorderOverlay:GetFrameLevel() + 10)
        end
        
        local portraitSize = desiredPortraitSize
        RefineUI.Size(pf, portraitSize)
        RefineUI.Point(pf, "RIGHT", parent, "LEFT", 6, 0)
        data.PortraitFrame = pf
        data.PortraitScaleApplied = desiredPortraitScale

        local portrait = pf:CreateTexture(nil, "ARTWORK")
        RefineUI.SetInside(portrait, pf, 0, 0)
        data.Portrait = portrait

        local mask = pf:CreateMaskTexture()
        mask:SetTexture(RefineUI.Media.Textures.PortraitMask)
        RefineUI.SetInside(mask, pf, 0, 0)
        portrait:AddMaskTexture(mask)

        local bg = pf:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture(RefineUI.Media.Textures.PortraitBG)
        RefineUI.SetInside(bg, pf, 0, 0)
        bg:AddMaskTexture(mask)

        local border = pf:CreateTexture(nil, "OVERLAY")
        border:SetTexture(RefineUI.Media.Textures.PortraitBorder)
        local c = RefineUI.Config.General.BorderColor
        border:SetVertexColor(unpack(c))
        RefineUI.SetOutside(border, pf)
        data.PortraitBorder = border

        local radial = RefineUI.CreateRadialStatusBar(pf)
        RefineUI.SetOutside(radial, pf)
        radial:SetTexture(RefineUI.Media.Textures.PortraitBorder)
        radial:SetFrameLevel(pf:GetFrameLevel() + 5)
        radial:SetAlpha(0.8)
        data.PortraitRadialStatusbar = radial

        local text = pf:CreateFontString(nil, "OVERLAY")
        RefineUI.Font(text, 12, nil, "OUTLINE")
        RefineUI.Point(text, "CENTER", pf, "CENTER", 0, 0)
        data.PortraitText = text
    end

    if data.PortraitFrame and data.PortraitScaleApplied ~= desiredPortraitScale then
        RefineUI.Size(data.PortraitFrame, desiredPortraitSize)
        data.PortraitScaleApplied = desiredPortraitScale
    end
    
    local portrait = data.Portrait
    local radial = data.PortraitRadialStatusbar
    local text = data.PortraitText
    if not portrait then return end

    -- Hide if requested or if health bar is hidden
    if data.PortraitFrame and (not data.PortraitFrame:IsShown() or data.RefineHidden) then
        portrait:SetTexture(nil)
        if text then text:SetText("") end
        if radial then radial:Hide() end
        SetPortraitImportantCastGlow(data, false)
        if data.PortraitFrame then data.PortraitFrame:Hide() end
        data.lastPortraitMode = "hidden"
        data.lastPortraitGUID = nil
        return
    end

    local guid = UnitGUID(unit)
    local castBar = unitFrame.castBar or unitFrame.CastBar
    local previousPortraitMode = data.lastPortraitMode
    
    -- Source of truth for cast state is the Unit API + castbar runtime state.
    -- Avoid persistent suppression flags here; they can stick when events are dropped/reordered.
    local isCastStartEvent = CAST_START_EVENTS[event] == true
    local isCastStopEvent = CAST_STOP_EVENTS[event] == true

    local castName, _, castTexture = UnitCastingInfo(unit)
    local hasApiCast = HasValue(castName)
    if not hasApiCast then
        castName, _, castTexture = UnitChannelInfo(unit)
        hasApiCast = HasValue(castName)
    end

    local castBarActive = IsCastBarActive(castBar)
    local isCasting = hasApiCast or castBarActive

    -- Stop events can arrive before UnitCastingInfo/UnitChannelInfo clears.
    -- Only force a stop when the castbar is no longer active to avoid suppressing new casts.
    if isCastStopEvent and not isCastStartEvent and not castBarActive then
        isCasting = false
    end

    -- Some start events fire before API fields settle; use castbar icon as immediate fallback.
    if isCastStartEvent and not isCasting and castBar and castBar.Icon and castBar.Icon.GetTexture then
        local startTexture = castBar.Icon:GetTexture()
        if HasValue(startTexture) then
            castTexture = startTexture
            isCasting = true
        end
    end
    
    if isCasting then
        portrait:SetTexture(castTexture or (castBar and castBar.Icon and castBar.Icon:GetTexture()) or 136235) -- Fallback to default spell icon if all fails
        if text then text:SetText("") end
        if radial then
            radial:SetRadialStatusBarValue(0)
            radial:Hide()
        end
        data.lastPortraitMode = "cast"
        data.lastPortraitGUID = nil
        
        -- Color Portrait Border based on Cast (Centralized)
        if RefineUI.UpdateBorderColors then
            RefineUI:UpdateBorderColors(unitFrame)
        end
    else
        local ccActive = data.CrowdControlActive == true
        local ccIcon = data.CrowdControlIcon

        if ccActive and HasValue(ccIcon) then
            portrait:SetTexture(ccIcon)
            if text then text:SetText("") end
            if radial then
                radial:SetRadialStatusBarValue(0)
                radial:Hide()
            end
            data.lastPortraitMode = "cc"
            data.lastPortraitGUID = nil

            if RefineUI.UpdateBorderColors then
                RefineUI:UpdateBorderColors(unitFrame)
            end
        else
            local quest = GetQuestInfoFromTooltip(unit)
            if quest then
                if radial then
                    radial:SetTexture(M.PortraitBorder)
                    radial:SetVertexColor(1, 0.82, 0)
                    radial:SetRadialStatusBarValue(quest.objectiveProgress)
                    radial:Show()
                end

                portrait:SetTexture(M.QuestIcon)
                data.lastPortraitMode = "quest"
                data.lastPortraitGUID = nil

                if text then
                    text:SetText("")
                    text:SetTextColor(1, 0.82, 0)
                end
            else
                -- Guard for SECRET values: If either GUID is secret, always update portrait
                local cachedGUID = data.lastPortraitGUID
                local shouldUpdate = (previousPortraitMode ~= "portrait")
                
                if HasValue(cachedGUID) and HasValue(guid) then
                    local cachedIsSecret = IsSecret(cachedGUID)
                    local guidIsSecret = IsSecret(guid)
                    
                    if not cachedIsSecret and not guidIsSecret then
                        -- Update if GUID changed OR if we just finished casting (to clear spell icon)
                        shouldUpdate = shouldUpdate or (cachedGUID ~= guid) or data.wasCasting or isCastStopEvent
                    else
                        shouldUpdate = true
                    end
                else
                    shouldUpdate = true
                end
                
                if shouldUpdate then
                    SetPortraitTexture(portrait, unit)
                    data.lastPortraitGUID = IsSecret(guid) and nil or guid
                end
                data.lastPortraitMode = "portrait"
                
                if text then text:SetText("") end
                if radial then
                    radial:SetRadialStatusBarValue(0)
                    radial:Hide()
                end
                
                -- Reset Portrait Border color (Centralized)
                -- Pass false to skip logic that might think we are still casting
                if RefineUI.UpdateBorderColors then
                    RefineUI:UpdateBorderColors(unitFrame, false)
                end
            end
        end
    end
    
    -- Track casting state for next update
    data.wasCasting = isCasting
end

----------------------------------------------------------------------------------------
-- Setup Events
----------------------------------------------------------------------------------------

local EventFrame = CreateFrame("Frame")
EventFrame:RegisterEvent("QUEST_LOG_UPDATE")
EventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
EventFrame:SetScript("OnEvent", function(self, event)
    if event == "QUEST_LOG_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        wipe(tooltipCache)
        -- Force update all nameplates
        local active = RefineUI.ActiveNameplates
        if active then
            for nameplate, unit in pairs(active) do
                RefineUI:UpdateDynamicPortrait(nameplate, unit)
            end
        else
            for _, nameplate in pairs(C_NamePlate.GetNamePlates()) do
                RefineUI:UpdateDynamicPortrait(nameplate, nameplate.UnitFrame and nameplate.UnitFrame.unit)
            end
        end
    end
end)
