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
local type, tonumber, pcall = type, tonumber, pcall
local pairs, ipairs = pairs, ipairs
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
local THREAT_TOOLTIP = THREAT_TOOLTIP
local C_TooltipInfo = C_TooltipInfo
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
local IsCastBarActive = NameplatesUtil.IsCastBarActive
local TOOLTIP_LINE_TYPE_QUEST_OBJECTIVE = (_G.Enum and _G.Enum.TooltipDataLineType and _G.Enum.TooltipDataLineType.QuestObjective) or 8
local TOOLTIP_LINE_TYPE_QUEST_TITLE = (_G.Enum and _G.Enum.TooltipDataLineType and _G.Enum.TooltipDataLineType.QuestTitle) or 17
local TOOLTIP_LINE_TYPE_QUEST_PLAYER = (_G.Enum and _G.Enum.TooltipDataLineType and _G.Enum.TooltipDataLineType.QuestPlayer) or 18
local PLAYER_NAME = UnitName("player")
local NO_QUEST_TOOLTIP_RESULT = false
local pendingQuestPortraitRefresh = false
local PORTRAIT_EVENT_KEY_PREFIX = "Nameplates:Portrait:QuestCache"
local QUEST_REFRESH_KEY = "Nameplates:Portrait:QuestRefresh"
local QUEST_REFRESH_DELAY_SECONDS = 0.1

local IMPORTANT_CAST_GLOW_ATLAS = "PowerSwirlAnimation-SpinningGlowys"
local IMPORTANT_CAST_GLOW_PADDING = 0
local IMPORTANT_CAST_GLOW_ALPHA = 1
local IMPORTANT_CAST_GLOW_ROTATION_SECONDS = 1.2
local BASE_PORTRAIT_SIZE = 36
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
local PORTRAIT_UPDATE_EVENTS = {
    UNIT_PORTRAIT_UPDATE = true,
    UNIT_MODEL_CHANGED = true,
}

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
        local total = tonumber(y)
        if total == 0 then
            return nil, false
        end
        return tonumber(x) / total, x == y
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

local function ApplyPortraitCastSignalColor(borderTexture, signal)
    if not borderTexture or signal == nil then
        return false
    end
    if not borderTexture.SetVertexColorFromBoolean then
        return false
    end

    -- Built by RefreshNameplateCastColors (CastBars) before any cast bar is styled.
    local colorObjs = RefineUI.Colors.CastColorObj
    borderTexture:SetVertexColorFromBoolean(signal, colorObjs.NonInterruptible, colorObjs.Interruptible)
    return true
end

local function ShouldSuppressQuestPortraits()
    return Nameplates:IsInGroupInstanceContent()
end

-- QUEST_LOG_UPDATE fires in bursts; coalesce them and spread the tooltip rescans
-- across frames through the budgeted portrait refresh queue.
local function RefreshAllQuestPortraits()
    wipe(tooltipCache)
    for nameplate, unit in pairs(RefineUI.ActiveNameplates) do
        local unitFrame = nameplate.UnitFrame
        if unitFrame then
            Nameplates:QueuePortraitRefresh(unitFrame, unit, "QUEST_LOG_UPDATE")
        end
    end
end

local function InvalidateQuestPortraitCache()
    if InCombatLockdown() then
        pendingQuestPortraitRefresh = true
        return
    end

    RefineUI:Debounce(QUEST_REFRESH_KEY, QUEST_REFRESH_DELAY_SECONDS, RefreshAllQuestPortraits)
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
    -- Alpha carries the important flag (see SetNameplateImportantCast); shown only while casting.
    glow:SetAlpha(0)
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

-- Called from the cast bar's SetIsHighlightedImportantCast hook; the flag can be secret.
function RefineUI:SetNameplateImportantCast(unitFrame, isImportant)
    local glow = EnsurePortraitImportantCastGlow(unitFrame and RefineUI.NameplateData[unitFrame])
    if glow then
        glow:SetAlphaFromBoolean(isImportant, IMPORTANT_CAST_GLOW_ALPHA, 0)
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

function RefineUI:UpdateBorderColors(unitFrame, forceCastCheck)
    if not unitFrame then return end
    local unit = unitFrame.unit
    if not unit then return end
    
    local data = RefineUI.NameplateData[unitFrame]
    if not data then return end
    
    -- Priority 1: Check for active cast
    local castBar = RefineUI.NameplatesUtil.GetNameplateCastBar(unitFrame)
    local castSignal, hasCastSignal
    local castColor
    local castColorR, castColorG, castColorB
    local hasActiveCast = false
    local castBarActive = false
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
    local defaultColor = (generalConfig and generalConfig.BorderColor) or DEFAULT_BORDER_COLOR
    local nameplateColor = targetColor or defaultColor
    local portraitColorR = defaultColor[1] or DEFAULT_BORDER_COLOR[1]
    local portraitColorG = defaultColor[2] or DEFAULT_BORDER_COLOR[2]
    local portraitColorB = defaultColor[3] or DEFAULT_BORDER_COLOR[3]

    if hasActiveCast and castColorR ~= nil and castColorG ~= nil and castColorB ~= nil then
        portraitColorR = castColorR
        portraitColorG = castColorG
        portraitColorB = castColorB
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

    SetPortraitImportantCastGlow(data, hasActiveCast)
    
    -- Apply to portrait border (Cast > CC > Target > Default)
    if data.PortraitBorder then
        local appliedCastSignal = forceCastCheck ~= false and hasCastSignal == true
            and ApplyPortraitCastSignalColor(data.PortraitBorder, castSignal)
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
    local desiredPortraitScale = Nameplates:GetConfiguredNameplateScale()
    local desiredPortraitSize = RefineUI:Scale(BASE_PORTRAIT_SIZE * desiredPortraitScale)

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

        -- Cast and quest icons use their own texture so the rendered portrait survives
        -- them; SetPortraitTexture renders the unit's model.
        local icon = pf:CreateTexture(nil, "ARTWORK", nil, 1)
        RefineUI.SetInside(icon, pf, 0, 0)
        icon:AddMaskTexture(mask)
        icon:Hide()
        data.PortraitIcon = icon

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
    local icon = data.PortraitIcon
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
        data.PortraitRendered = nil
        return
    end

    -- The unit is fixed for a plate assignment (add and pooled reset clear the flag),
    -- so only a portrait/model change needs a new render.
    if PORTRAIT_UPDATE_EVENTS[event] == true then
        data.PortraitRendered = nil
    end

    local castBar = RefineUI.NameplatesUtil.GetNameplateCastBar(unitFrame)
    local previousPortraitMode = data.lastPortraitMode
    
    -- Source of truth for cast state is the Unit API + castbar runtime state.
    -- Avoid persistent suppression flags here; they can stick when events are dropped/reordered.
    local isCastStartEvent = CAST_START_EVENTS[event] == true
    local isCastStopEvent = CAST_STOP_EVENTS[event] == true

    local castBarActive = IsCastBarActive(castBar)
    local borderDirty = false
    local borderForceCastCheck = nil
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
        icon:SetTexture(castTexture or (castBar and castBar.Icon and castBar.Icon:GetTexture()) or 136235) -- Fallback to default spell icon if all fails
        icon:Show()
        portrait:Hide()
        if text then text:SetText("") end
        if radial then
            radial:SetRadialStatusBarValue(0)
            radial:Hide()
        end
        data.lastPortraitMode = "cast"
        borderDirty = true
    else
        -- CC is drawn over the portrait by the CrowdControl AuraContainer overlay.
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
                radial:SetRadialStatusBarValue(quest.objectiveProgress)
                radial:Show()
            end

            icon:SetTexture(MediaTextures.QuestIcon)
            icon:Show()
            portrait:Hide()
            data.lastPortraitMode = "quest"

            if text then
                text:SetText("")
                text:SetTextColor(1, 0.82, 0)
            end
        else
            icon:Hide()
            portrait:Show()
            if not data.PortraitRendered then
                SetPortraitTexture(portrait, unit)
                data.PortraitRendered = true
            end
            data.lastPortraitMode = "portrait"

            if text then text:SetText("") end
            if radial then
                radial:SetRadialStatusBarValue(0)
                radial:Hide()
            end

            borderDirty = true
            borderForceCastCheck = false
        end
    end

    -- Track casting state for next update
    data.isCasting = isCasting
    data.wasCasting = isCasting

    -- Coalesced border color update — runs at most once per UpdateDynamicPortrait call
    if borderDirty and data.SuppressPortraitBorderRefresh ~= true then
        RefineUI:UpdateBorderColors(unitFrame, borderForceCastCheck)
    end
end

----------------------------------------------------------------------------------------
-- Setup Events
----------------------------------------------------------------------------------------

local function OnPortraitEvent(event)
    -- Dungeons, raids, and PvP never show quest portraits; leaving fires PLAYER_ENTERING_WORLD,
    -- which rebuilds the cache.
    if ShouldSuppressQuestPortraits() then
        pendingQuestPortraitRefresh = false
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        if pendingQuestPortraitRefresh then
            pendingQuestPortraitRefresh = false
            RefreshAllQuestPortraits()
        end
        return
    end

    InvalidateQuestPortraitCache()
end

-- Portraits rendered during loading come out blank; the client fires PORTRAITS_UPDATED
-- once they can be drawn, as Blizzard's UnitFrame handles.
local function OnPortraitsUpdated()
    for nameplate, unit in pairs(RefineUI.ActiveNameplates) do
        local unitFrame = nameplate.UnitFrame
        local data = unitFrame and RefineUI.NameplateData[unitFrame]
        if data then
            data.PortraitRendered = nil
            Nameplates:QueuePortraitRefresh(unitFrame, unit, "PORTRAITS_UPDATED")
        end
    end
end

function Nameplates:RegisterPortraitEvents()
    RefineUI:OnEvents({ "QUEST_LOG_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }, OnPortraitEvent, PORTRAIT_EVENT_KEY_PREFIX)
    RefineUI:RegisterEventCallback("PORTRAITS_UPDATED", OnPortraitsUpdated, "Nameplates:Portrait:PortraitsUpdated")
end
