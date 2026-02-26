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
local strmatch, strformat = string.match, string.format
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
        return nil
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
        return { r, g, b }
    end

    return nil
end

local function ApplyPortraitCastSignalColor(borderTexture, signal)
    if not borderTexture or signal == nil then
        return false
    end
    if not borderTexture.SetVertexColorFromBoolean then
        return false
    end

    local castColors = RefineUI.Colors.Cast
    borderTexture:SetVertexColorFromBoolean(
        signal,
        CreateColor(unpack(castColors.NonInterruptible)),
        CreateColor(unpack(castColors.Interruptible))
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
    local hasActiveCast = false
    local importantCastActive = false
    if forceCastCheck ~= false then
        if RefineUI.GetNameplateCastInterruptibilitySignal then
            castSignal, hasCastSignal = RefineUI:GetNameplateCastInterruptibilitySignal(unit, castBar)
            hasActiveCast = hasCastSignal == true
        end

        -- Only use cast color while a cast/channel is actually active.
        if hasActiveCast or hasCastSignal == nil then
            castColor = GetNameplateCastRenderedColor(castBar)
            if not castColor then
                castColor = RefineUI:GetCastColor(unit, castBar)
            end
            if hasCastSignal == nil and castColor then
                hasActiveCast = true
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
    local targetColor = isTarget and C.Nameplates.TargetBorderColor
    local ccConfig = C.Nameplates and (C.Nameplates.CrowdControl or C.Nameplates.CrowdControlTest)
    local ccColor = nil
    if data.CrowdControlActive and ccConfig and ccConfig.Enable ~= false then
        ccColor = ccConfig.BorderColor or ccConfig.Color
    end
    local defaultColor = C.General.BorderColor
    local nameplateColor = targetColor or defaultColor
    
    local portraitColor = defaultColor
    if hasActiveCast and castColor then
        portraitColor = castColor
    elseif ccColor then
        portraitColor = ccColor
    elseif targetColor then
        portraitColor = targetColor
    end
    
    -- Apply to nameplate border (Target or Default only)
    if data.RefineBorder then
        SetColorBorder(data.RefineBorder, unpack(nameplateColor))
    end

    SetPortraitImportantCastGlow(data, importantCastActive)
    
    -- Apply to portrait border (Cast > CC > Target > Default)
    if data.PortraitBorder then
        local appliedCastSignal = false
        if forceCastCheck ~= false and hasCastSignal == true then
            appliedCastSignal = ApplyPortraitCastSignalColor(data.PortraitBorder, castSignal)
        end

        if not appliedCastSignal then
            data.PortraitBorder:SetVertexColor(unpack(portraitColor))
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
    
    -- Source of Truth for Icon: Unit API
    -- Workaround: Check event to bypass UnitCastingInfo latency
    
    -- Update persistent state based on events
    local isCastStartEvent = (event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START")
    local isCastStopEvent = (
        event == "UNIT_SPELLCAST_STOP" or
        event == "UNIT_SPELLCAST_FAILED" or
        event == "UNIT_SPELLCAST_INTERRUPTED" or
        event == "UNIT_SPELLCAST_SUCCEEDED" or
        event == "UNIT_SPELLCAST_CHANNEL_STOP"
    )

    if isCastStartEvent then
        data.blockingCast = false
    elseif isCastStopEvent then
        data.blockingCast = true
    end
    
    local castName, _, castTexture = UnitCastingInfo(unit)
    if not HasValue(castName) then
        castName, _, castTexture = UnitChannelInfo(unit)
    end
    
    local isCasting = HasValue(castName)
    
    -- If we recently stopped, block the API result until it syncs
    if data.blockingCast and isCasting then
        isCasting = false
    end
    
    -- Reset blocking if API agrees (cast is done)
    if not HasValue(castName) then
        data.blockingCast = false
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
