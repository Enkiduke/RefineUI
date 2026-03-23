----------------------------------------------------------------------------------------
-- Nameplates Component: Portrait
-- Description: Handles radial status bars, quest icons, and cast icons for nameplates
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
local canaccessvalue = _G.canaccessvalue
local math = math
local pairs, ipairs, select = pairs, ipairs, select
local strmatch = string.match
local wipe = table.wipe

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local UnitGUID = UnitGUID
local UnitName = UnitName
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
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
local MediaTextures = RefineUI.Media.Textures
local ThreatTooltip = THREAT_TOOLTIP:gsub("%%d", "%%d-")
local tooltipCache = {} -- Strong-valued; invalidated on quest events (QUEST_LOG_UPDATE)
local NameplatesUtil = RefineUI.NameplatesUtil
local IsSecret = NameplatesUtil.IsSecret
local HasValue = NameplatesUtil.HasValue
local ReadSafeBoolean = NameplatesUtil.ReadSafeBoolean
local IsTargetNameplateUnitFrame = NameplatesUtil.IsTargetNameplateUnitFrame
local TOOLTIP_LINE_TYPE_QUEST_OBJECTIVE = (_G.Enum and _G.Enum.TooltipDataLineType and _G.Enum.TooltipDataLineType.QuestObjective) or 8
local TOOLTIP_LINE_TYPE_QUEST_TITLE = (_G.Enum and _G.Enum.TooltipDataLineType and _G.Enum.TooltipDataLineType.QuestTitle) or 17
local TOOLTIP_LINE_TYPE_QUEST_PLAYER = (_G.Enum and _G.Enum.TooltipDataLineType and _G.Enum.TooltipDataLineType.QuestPlayer) or 18
local PLAYER_NAME = UnitName("player")
local NO_QUEST_TOOLTIP_RESULT = false
local pendingQuestTooltipCacheReset = false
local pendingQuestPortraitRefresh = false
local PORTRAIT_EVENT_KEY_PREFIX = "Nameplates:Portrait:QuestCache"

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
    CAST_RESET = true,
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
    if Nameplates and Nameplates.GetConfiguredNameplateScale then
        return Nameplates:GetConfiguredNameplateScale()
    end

    local cfg = Config and Config.Nameplates
    local scale = tonumber(cfg and cfg.Scale) or tonumber(cfg and cfg.DynamicPortraitScale) or 1
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

local function CacheQuestTooltipResult(guid, isSecretGuid, result)
    if result ~= nil and not isSecretGuid then
        tooltipCache[guid] = result
    end
    return result
end

local function GetQuestInfoFromTooltip(unit)
    if IsSecret(unit) or type(unit) ~= "string" then return nil end

    local guid = UnitGUID(unit)
    -- Secret Protection: prevent table index is secret error
    local isSecret = IsSecret(guid)

    if not isSecret then
        local cachedResult = tooltipCache[guid]
        if cachedResult ~= nil then
            if cachedResult == NO_QUEST_TOOLTIP_RESULT then
                return nil
            end
            return cachedResult
        end
    end

    local isQuestRelated = nil
    if C_QuestLog and type(C_QuestLog.UnitIsRelatedToActiveQuest) == "function" then
        local ok, related = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, unit)
        if ok then
            isQuestRelated = ReadSafeBoolean(related)
        end
    end

    if isQuestRelated == false then
        return CacheQuestTooltipResult(guid, isSecret, NO_QUEST_TOOLTIP_RESULT)
    end

    local tooltipData = C_TooltipInfo.GetUnit(unit)
    local lines = tooltipData and tooltipData.lines
    if not lines then
        if isQuestRelated then
            return CacheQuestTooltipResult(guid, isSecret, {
                isPercent = false,
                objectiveProgress = 0,
                questType = "DEFAULT",
                questID = nil,
            })
        end
        return CacheQuestTooltipResult(guid, isSecret, NO_QUEST_TOOLTIP_RESULT)
    end

    local fallbackResult = nil
    local currentQuestID = nil
    local currentOwnerIsPlayer = nil
    local playerName = PLAYER_NAME or UnitName("player")

    for _, line in ipairs(lines) do
        if line.type == TOOLTIP_LINE_TYPE_QUEST_TITLE and line.id then
            currentQuestID = line.id
            currentOwnerIsPlayer = nil
            if not fallbackResult then
                fallbackResult = {
                    isPercent = false,
                    objectiveProgress = 0,
                    questType = "DEFAULT",
                    questID = currentQuestID,
                }
            end
        elseif line.type == TOOLTIP_LINE_TYPE_QUEST_PLAYER then
            local ownerName = line.leftText
            if not IsSecret(ownerName) and type(ownerName) == "string" then
                currentOwnerIsPlayer = ownerName == playerName
            else
                currentOwnerIsPlayer = nil
            end
        elseif line.type == TOOLTIP_LINE_TYPE_QUEST_OBJECTIVE and currentQuestID then
            local completed = ReadSafeBoolean(line.completed)
            local progress, isComplete, isPercent = CheckTextForQuest(line.leftText)
            if completed ~= nil then
                isComplete = completed
            elseif progress == nil then
                isComplete = false
            end
            if progress == nil then
                progress = 0
            end

            if fallbackResult == nil then
                fallbackResult = {
                    isPercent = false,
                    objectiveProgress = 0,
                    questType = "DEFAULT",
                    questID = currentQuestID,
                }
            end

            if currentOwnerIsPlayer ~= false and not isComplete then
                return CacheQuestTooltipResult(guid, isSecret, {
                    isPercent = isPercent,
                    objectiveProgress = progress,
                    questType = "DEFAULT",
                    questID = currentQuestID,
                })
            end
        end
    end

    if fallbackResult then
        return CacheQuestTooltipResult(guid, isSecret, fallbackResult)
    end

    if isQuestRelated then
        return CacheQuestTooltipResult(guid, isSecret, {
            isPercent = false,
            objectiveProgress = 0,
            questType = "DEFAULT",
            questID = nil,
        })
    end

    return CacheQuestTooltipResult(guid, isSecret, NO_QUEST_TOOLTIP_RESULT)
end

local function GetCachedQuestInfoForUnit(unit)
    if IsSecret(unit) or type(unit) ~= "string" then
        return nil
    end

    local guid = UnitGUID(unit)
    if IsSecret(guid) then
        return nil
    end

    local cachedResult = tooltipCache[guid]
    if cachedResult == nil or cachedResult == NO_QUEST_TOOLTIP_RESULT then
        return nil
    end

    return cachedResult
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
    local castBarSpellIdentifier = GetCastBarSpellIdentifier(castBar)
    if castBarSpellIdentifier then
        return castBarSpellIdentifier
    end

    if IsSecret(unit) or type(unit) ~= "string" then
        return nil
    end

    local castName, _, _, _, _, _, _, _, castSpellID = UnitCastingInfo(unit)
    if HasValue(castName) then
        return ReadAccessibleSpellIdentifier(castSpellID)
    end

    local channelName, _, _, _, _, _, _, channelSpellID = UnitChannelInfo(unit)
    if HasValue(channelName) then
        return ReadAccessibleSpellIdentifier(channelSpellID)
    end

    return nil
end

local function ReadComparableSignatureValue(value)
    if value == nil or IsSecret(value) then
        return nil
    end
    if canaccessvalue and not canaccessvalue(value) then
        return nil
    end

    local valueType = type(value)
    if valueType == "number" or valueType == "string" or valueType == "boolean" then
        return value
    end

    return nil
end

local function ReadComparableTextureSignature(texture)
    local comparableTexture = ReadComparableSignatureValue(texture)
    if comparableTexture == nil then
        return nil
    end
    return tostring(comparableTexture)
end

local function GetPortraitScaleSignature()
    return tostring(GetConfiguredDynamicPortraitSize())
end

local function GetComparableCastDiscriminator(unit, castBar)
    local spellIdentifier = GetActiveCastSpellIdentifier(unit, castBar)
    if spellIdentifier ~= nil then
        return "spell:" .. tostring(spellIdentifier)
    end

    local texture = castBar and castBar.Icon and castBar.Icon.GetTexture and castBar.Icon:GetTexture() or nil
    local textureSignature = ReadComparableTextureSignature(texture)
    if textureSignature ~= nil then
        return "icon:" .. textureSignature
    end

    return nil
end

local function BuildQuestPortraitVisualSignature(quest, scaleSignature)
    if type(quest) ~= "table" or scaleSignature == nil then
        return nil
    end

    local questType = ReadComparableSignatureValue(quest.questType) or "DEFAULT"
    local questID = ReadComparableSignatureValue(quest.questID)
    local objectiveProgress = ReadComparableSignatureValue(quest.objectiveProgress)
    local isPercent = ReadSafeBoolean(quest.isPercent) == true and "1" or "0"

    local progressSignature = "na"
    if type(objectiveProgress) == "number" then
        progressSignature = tostring(math.floor((objectiveProgress * 1000) + 0.5))
    elseif objectiveProgress ~= nil then
        progressSignature = tostring(objectiveProgress)
    end

    return "quest:" .. scaleSignature .. ":" .. tostring(questType) .. ":" .. tostring(questID or "nil") .. ":" .. isPercent .. ":" .. progressSignature
end

local function BuildCrowdControlPortraitVisualSignature(data, scaleSignature)
    if not data or scaleSignature == nil then
        return nil
    end

    local crowdControlSignature = data.CrowdControlVisualSignature
    if type(crowdControlSignature) ~= "string" or crowdControlSignature == "" then
        return nil
    end

    return "cc:" .. scaleSignature .. ":" .. crowdControlSignature
end

local function BuildPortraitVisualSignatureForGUID(guid, scaleSignature)
    local comparableGUID = ReadComparableSignatureValue(guid)
    if comparableGUID == nil or scaleSignature == nil then
        return nil
    end

    return "portrait:" .. scaleSignature .. ":" .. tostring(comparableGUID)
end

local function ShouldSuppressQuestPortraits()
    if type(Nameplates.IsInGroupInstanceContent) ~= "function" then
        return false
    end

    return Nameplates:IsInGroupInstanceContent()
end

local function RefreshAllQuestPortraits(event)
    local active = RefineUI.ActiveNameplates
    if active then
        for nameplate, unit in pairs(active) do
            RefineUI:UpdateDynamicPortrait(nameplate, unit, event)
        end
        return
    end

    if C_NamePlate and type(C_NamePlate.GetNamePlates) == "function" then
        for _, nameplate in pairs(C_NamePlate.GetNamePlates()) do
            RefineUI:UpdateDynamicPortrait(nameplate, nameplate.UnitFrame and nameplate.UnitFrame.unit, event)
        end
    end
end

local function InvalidateQuestPortraitCache(event)
    if InCombatLockdown and InCombatLockdown() then
        pendingQuestTooltipCacheReset = true
        pendingQuestPortraitRefresh = true
        return
    end

    wipe(tooltipCache)
    RefreshAllQuestPortraits(event)
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

local function IsImportantCastCached(data, spellIdentifier)
    if not data or spellIdentifier == nil then
        return nil
    end

    if data.LastImportantCastSpellIdentifier == spellIdentifier then
        return data.LastImportantCastIsImportant == true
    end

    return nil
end

local function CacheImportantCastResult(data, spellIdentifier, isImportant)
    if not data then
        return isImportant == true
    end

    data.LastImportantCastSpellIdentifier = spellIdentifier
    data.LastImportantCastIsImportant = isImportant == true
    return data.LastImportantCastIsImportant
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

local function ShouldProbeUnitCastState(event, data, previousPortraitMode)
    if event == nil then
        return true
    end

    if CAST_START_EVENTS[event] == true or CAST_STOP_EVENTS[event] == true then
        return true
    end

    if previousPortraitMode == "cast" then
        return true
    end

    return data and data.wasCasting == true
end

local function ResolveNameplateBorderVisualModes(unitFrame, forceCastCheck)
    if not unitFrame then
        return nil
    end

    local unit = unitFrame.unit
    if not unit then
        return nil
    end

    local data = RefineUI.NameplateData[unitFrame]
    if not data then
        return nil
    end

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
                    local cachedImportant = IsImportantCastCached(data, spellIdentifier)
                    if cachedImportant ~= nil then
                        importantCastActive = cachedImportant
                    else
                        importantCastActive = CacheImportantCastResult(data, spellIdentifier, SafeIsSpellImportant(spellIdentifier))
                    end
                elseif data then
                    data.LastImportantCastSpellIdentifier = nil
                    data.LastImportantCastIsImportant = nil
                end
            end
        elseif data then
            data.LastImportantCastSpellIdentifier = nil
            data.LastImportantCastIsImportant = nil
        end
    end

    local isTarget = data.isTarget
    if type(isTarget) ~= "boolean" then
        isTarget = IsTargetNameplateUnitFrame(unitFrame)
        data.isTarget = isTarget
    end

    local nameplatesConfig = Config and Config.Nameplates
    local ccConfig = nameplatesConfig and (nameplatesConfig.CrowdControl or nameplatesConfig.CrowdControlTest)
    local crowdControlEnabled = data.CrowdControlActive == true and ccConfig and ccConfig.Enable ~= false

    local nameplateBorderMode = isTarget and "target" or "default"
    local portraitBorderMode = "default"
    local resolvedCastSignal = ReadSafeBoolean(castSignal)

    if forceCastCheck ~= false and hasCastSignal == true and resolvedCastSignal ~= nil then
        portraitBorderMode = resolvedCastSignal and "cast_signal_noninterruptible" or "cast_signal_interruptible"
    elseif forceCastCheck ~= false and hasActiveCast then
        portraitBorderMode = "cast_color"
    elseif crowdControlEnabled then
        portraitBorderMode = "cc"
    elseif isTarget then
        portraitBorderMode = "target"
    end

    return nameplateBorderMode, portraitBorderMode, importantCastActive == true
end

local function BuildBorderVisualSignature(nameplateBorderMode, portraitBorderMode, importantCastActive)
    if type(nameplateBorderMode) ~= "string" or type(portraitBorderMode) ~= "string" then
        return nil
    end

    local glowState = importantCastActive == true and "1" or "0"
    return "nameplate:" .. nameplateBorderMode .. "|portrait:" .. portraitBorderMode .. "|glow:" .. glowState
end

function RefineUI:GetPredictedNameplateBorderVisualSignature(unitFrame, forceCastCheck)
    local nameplateBorderMode, portraitBorderMode, importantCastActive = ResolveNameplateBorderVisualModes(unitFrame, forceCastCheck)
    if nameplateBorderMode == nil or portraitBorderMode == nil then
        return nil
    end

    return BuildBorderVisualSignature(nameplateBorderMode, portraitBorderMode, importantCastActive)
end

function RefineUI:GetPredictedNameplatePortraitVisualSignature(unitFrame, unit, event)
    if not unitFrame then
        return nil
    end

    local data = RefineUI.NameplateData[unitFrame]
    if not data then
        return nil
    end

    if data.RefineHidden == true then
        return "hidden"
    end

    if data.PortraitFrame and data.PortraitFrame.IsShown and not data.PortraitFrame:IsShown() then
        return "hidden"
    end

    if IsSecret(unit) or type(unit) ~= "string" then
        return nil
    end

    local scaleSignature = GetPortraitScaleSignature()
    local castBar = unitFrame.castBar or unitFrame.CastBar
    local previousPortraitMode = data.lastPortraitMode
    local isCastStartEvent = CAST_START_EVENTS[event] == true
    local isCastStopEvent = CAST_STOP_EVENTS[event] == true
    local castBarActive = IsCastBarActive(castBar)
    local isCasting = castBarActive

    if not isCasting and ShouldProbeUnitCastState(event, data, previousPortraitMode) then
        local castName
        castName = UnitCastingInfo(unit)
        isCasting = HasValue(castName)
        if not isCasting then
            castName = UnitChannelInfo(unit)
            isCasting = HasValue(castName)
        end
    end

    if isCastStopEvent and not isCastStartEvent and not castBarActive then
        isCasting = false
    end

    if isCastStartEvent and not isCasting and castBar and castBar.Icon and castBar.Icon.GetTexture then
        local startTexture = castBar.Icon:GetTexture()
        if HasValue(startTexture) then
            isCasting = true
        end
    end

    if isCasting then
        local castDiscriminator = GetComparableCastDiscriminator(unit, castBar)
        if castDiscriminator == nil or scaleSignature == nil then
            return nil
        end
        return "cast:" .. scaleSignature .. ":" .. castDiscriminator
    end

    if data.CrowdControlActive == true and HasValue(data.CrowdControlIcon) then
        return BuildCrowdControlPortraitVisualSignature(data, scaleSignature)
    end

    local quest = nil
    if not ShouldSuppressQuestPortraits() then
        if InCombatLockdown and InCombatLockdown() then
            quest = GetCachedQuestInfoForUnit(unit)
        else
            quest = GetQuestInfoFromTooltip(unit)
        end
    end
    if quest then
        return BuildQuestPortraitVisualSignature(quest, scaleSignature)
    end

    return BuildPortraitVisualSignatureForGUID(UnitGUID(unit), scaleSignature)
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
                    local cachedImportant = IsImportantCastCached(data, spellIdentifier)
                    if cachedImportant ~= nil then
                        importantCastActive = cachedImportant
                    else
                        importantCastActive = CacheImportantCastResult(data, spellIdentifier, SafeIsSpellImportant(spellIdentifier))
                    end
                elseif data then
                    data.LastImportantCastSpellIdentifier = nil
                    data.LastImportantCastIsImportant = nil
                end
            end
        elseif data then
            data.LastImportantCastSpellIdentifier = nil
            data.LastImportantCastIsImportant = nil
        end
    end
    
    -- Priority 2: Check target status
    local isTarget = data.isTarget
    if type(isTarget) ~= "boolean" then
        isTarget = IsTargetNameplateUnitFrame(unitFrame)
        data.isTarget = isTarget
    end
    
    -- Determine colors
    local nameplatesConfig = Config and Config.Nameplates
    local generalConfig = Config and Config.General
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
    local nameplateBorderMode = isTarget and "target" or "default"
    local portraitBorderMode = "default"

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
            if appliedCastSignal then
                local resolvedCastSignal = ReadSafeBoolean(castSignal)
                if resolvedCastSignal ~= nil then
                    portraitBorderMode = resolvedCastSignal and "cast_signal_noninterruptible" or "cast_signal_interruptible"
                end
            end
        end

        if not appliedCastSignal then
            data.PortraitBorder:SetVertexColor(portraitColorR, portraitColorG, portraitColorB)
            if forceCastCheck ~= false and hasActiveCast then
                portraitBorderMode = "cast_color"
            elseif ccColor then
                portraitBorderMode = "cc"
            elseif targetColor then
                portraitBorderMode = "target"
            end
        end
    elseif forceCastCheck ~= false and hasActiveCast then
        portraitBorderMode = "cast_color"
    elseif ccColor then
        portraitBorderMode = "cc"
    elseif targetColor then
        portraitBorderMode = "target"
    end

    data.BorderVisualSignature = BuildBorderVisualSignature(nameplateBorderMode, portraitBorderMode, importantCastActive)
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
    local portraitScaleSignature = tostring(desiredPortraitSize)

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
        RefineUI.Point(pf, "RIGHT", parent, "LEFT", 8, 0)
        data.PortraitFrame = pf
        data.PortraitScaleApplied = desiredPortraitScale

        local portrait = pf:CreateTexture(nil, "ARTWORK")
        RefineUI.SetInside(portrait, pf, 0, 0)
        data.Portrait = portrait

        local mask = pf:CreateMaskTexture()
        mask:SetTexture(MediaTextures.PortraitMask)
        RefineUI.SetInside(mask, pf, 0, 0)
        portrait:AddMaskTexture(mask)

        local bg = pf:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture(MediaTextures.PortraitBG)
        RefineUI.SetInside(bg, pf, 0, 0)
        bg:AddMaskTexture(mask)

        local border = pf:CreateTexture(nil, "OVERLAY")
        border:SetTexture(MediaTextures.PortraitBorder)
        local borderColor = Config and Config.General and Config.General.BorderColor or DEFAULT_BORDER_COLOR
        local borderR = (type(borderColor) == "table" and borderColor[1]) or DEFAULT_BORDER_COLOR[1]
        local borderG = (type(borderColor) == "table" and borderColor[2]) or DEFAULT_BORDER_COLOR[2]
        local borderB = (type(borderColor) == "table" and borderColor[3]) or DEFAULT_BORDER_COLOR[3]
        local borderA = (type(borderColor) == "table" and borderColor[4]) or DEFAULT_BORDER_COLOR[4]
        border:SetVertexColor(borderR, borderG, borderB, borderA)
        RefineUI.SetOutside(border, pf)
        data.PortraitBorder = border

        local radial = RefineUI.CreateRadialStatusBar(pf)
        RefineUI.SetOutside(radial, pf)
        radial:SetTexture(MediaTextures.PortraitBorder)
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
    local portraitVisualSignature = nil

    -- Hide if requested or if health bar is hidden
    if data.PortraitFrame and (not data.PortraitFrame:IsShown() or data.RefineHidden) then
        portrait:SetTexture(nil)
        if text then text:SetText("") end
        if radial then radial:Hide() end
        SetPortraitImportantCastGlow(data, false)
        if data.PortraitFrame then data.PortraitFrame:Hide() end
        data.lastPortraitMode = "hidden"
        data.lastPortraitGUID = nil
        data.PortraitVisualSignature = "hidden"
        return
    end

    local guid = UnitGUID(unit)
    local castBar = unitFrame.castBar or unitFrame.CastBar
    local previousPortraitMode = data.lastPortraitMode
    
    -- Source of truth for cast state is the Unit API + castbar runtime state.
    -- Avoid persistent suppression flags here; they can stick when events are dropped/reordered.
    local isCastStartEvent = CAST_START_EVENTS[event] == true
    local isCastStopEvent = CAST_STOP_EVENTS[event] == true

    local castBarActive = IsCastBarActive(castBar)
    local castTexture = nil
    if castBar and castBar.Icon and castBar.Icon.GetTexture then
        castTexture = castBar.Icon:GetTexture()
        if not HasValue(castTexture) then
            castTexture = nil
        end
    end

    local isCasting = castBarActive
    if not isCasting and ShouldProbeUnitCastState(event, data, previousPortraitMode) then
        local castName
        castName, _, castTexture = UnitCastingInfo(unit)
        isCasting = HasValue(castName)
        if not isCasting then
            castName, _, castTexture = UnitChannelInfo(unit)
            isCasting = HasValue(castName)
        end
    end

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
        portraitVisualSignature = GetComparableCastDiscriminator(unit, castBar)
        if portraitVisualSignature ~= nil and portraitScaleSignature ~= nil then
            portraitVisualSignature = "cast:" .. portraitScaleSignature .. ":" .. portraitVisualSignature
        else
            portraitVisualSignature = nil
        end
        
        -- Defer border color update to end of this function (coalesced)
        data._borderColorDirty = true
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
            portraitVisualSignature = BuildCrowdControlPortraitVisualSignature(data, portraitScaleSignature)

            data._borderColorDirty = true
        else
            local quest = nil
            if not ShouldSuppressQuestPortraits() then
                if InCombatLockdown and InCombatLockdown() then
                    quest = GetCachedQuestInfoForUnit(unit)
                else
                    quest = GetQuestInfoFromTooltip(unit)
                end
            end
            if quest then
                if radial then
                    radial:SetTexture(MediaTextures.PortraitBorder)
                    radial:SetVertexColor(1, 0.82, 0)
                    radial:SetRadialStatusBarValue(quest.objectiveProgress)
                    radial:Show()
                end

                portrait:SetTexture(MediaTextures.QuestIcon)
                data.lastPortraitMode = "quest"
                data.lastPortraitGUID = nil
                portraitVisualSignature = BuildQuestPortraitVisualSignature(quest, portraitScaleSignature)

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
                portraitVisualSignature = BuildPortraitVisualSignatureForGUID(guid, portraitScaleSignature)
                
                if text then text:SetText("") end
                if radial then
                    radial:SetRadialStatusBarValue(0)
                    radial:Hide()
                end
                
                -- Defer border color reset to end of function (coalesced)
                data._borderColorDirty = true
                data._borderColorForceCastCheck = false
            end
        end
    end
    
    -- Track casting state for next update
    data.isCasting = isCasting
    data.wasCasting = isCasting
    data.PortraitVisualSignature = portraitVisualSignature

    -- Coalesced border color update — runs at most once per UpdateDynamicPortrait call
    if data._borderColorDirty then
        local forceCastCheck = data._borderColorForceCastCheck
        data._borderColorDirty = nil
        data._borderColorForceCastCheck = nil
        if data.SuppressPortraitBorderRefresh ~= true and RefineUI.UpdateBorderColors then
            RefineUI:UpdateBorderColors(unitFrame, forceCastCheck)
        end
    end
end

----------------------------------------------------------------------------------------
-- Setup Events
----------------------------------------------------------------------------------------

local function OnPortraitEvent(event)
    if event == "PLAYER_REGEN_ENABLED" then
        if pendingQuestTooltipCacheReset then
            pendingQuestTooltipCacheReset = false
            wipe(tooltipCache)
        end
        if pendingQuestPortraitRefresh then
            pendingQuestPortraitRefresh = false
            RefreshAllQuestPortraits(event)
        end
        return
    end

    if event == "QUEST_LOG_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        InvalidateQuestPortraitCache(event)
    end
end

RefineUI:OnEvents({ "QUEST_LOG_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }, OnPortraitEvent, PORTRAIT_EVENT_KEY_PREFIX)
