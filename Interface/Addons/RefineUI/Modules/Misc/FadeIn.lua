----------------------------------------------------------------------------------------
-- FadeIn for RefineUI
-- Description: Creates a cinematic black-to-transparent transition when entering the world.
----------------------------------------------------------------------------------------

local AddOnName, RefineUI = ...

----------------------------------------------------------------------------------------
-- Module Registration
----------------------------------------------------------------------------------------
local FadeIn = RefineUI:RegisterModule("FadeIn")

----------------------------------------------------------------------------------------
-- WoW Globals (Upvalues)
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local GetInstanceInfo = GetInstanceInfo
local GetMinimapZoneText = GetMinimapZoneText
local GetRealZoneText = GetRealZoneText

----------------------------------------------------------------------------------------
-- Locals
----------------------------------------------------------------------------------------
local frame
local bg
local zoneText
local subZoneText
local difficultyText
local isFading = false
local bgTimer = 0
local textTimer = 0
local frameCounter = 0
local lastZoneName = ""
local lastTriggerTime = 0
local textIsReady = false

-- Timing constants
local BG_WAIT = 0             -- Start fading immediately
local BG_FADE = 1.25          -- Smooth reveal of the world
local TEXT_WAIT = 1.75        -- How long text stays fully visible *after* it becomes ready
local TEXT_FADE = 1.5         -- How long text takes to fade out
local FRAME_DELAY = 8         -- Increased safety window for the engine
local TEXT_TIMEOUT = 0.5      -- Max time to wait for a zone name change

local function GetZoneColor()
    local pvpType = C_PvP.GetZonePVPInfo()
    if pvpType == "sanctuary" then
        return 0.41, 0.8, 0.94
    elseif pvpType == "arena" then
        return 1.0, 0.1, 0.1
    elseif pvpType == "friendly" then
        return 0.1, 1.0, 0.1
    elseif pvpType == "hostile" then
        return 1.0, 0.1, 0.1
    elseif pvpType == "contested" then
        return 1.0, 0.7, 0.0
    elseif pvpType == "combat" then
        return 1.0, 0.1, 0.1
    else
        return 1.0, 0.9294, 0.7607
    end
end

----------------------------------------------------------------------------------------
-- Utility Functions
----------------------------------------------------------------------------------------

local function GetDifficulty()
    local _, type, difficultyIndex, difficultyName, maxPlayers, dynamicDifficulty, isDynamic, instanceID, instanceGroupSize, LfgDungeonID = GetInstanceInfo()
    if difficultyName and difficultyName ~= "" then
        if maxPlayers > 0 then
            return format("%s (%d player)", difficultyName, maxPlayers)
        else
            return difficultyName
        end
    end
    return nil
end

local function UpdateZoneInfo()
    local zone = GetRealZoneText()
    local subzone = GetMinimapZoneText()
    local difficulty = GetDifficulty()
    local r, g, b = GetZoneColor()

    zoneText:SetText(zone or "")
    zoneText:SetTextColor(r, g, b)
    
    if subzone and subzone ~= "" and subzone ~= zone then
        subZoneText:SetText(subzone)
    else
        subZoneText:SetText("")
    end

    if difficulty then
        difficultyText:SetText(difficulty)
    else
        difficultyText:SetText("")
    end
end

----------------------------------------------------------------------------------------
-- Update Function
----------------------------------------------------------------------------------------

local function OnUpdate(self, elapsed)
    if not isFading then return end

    frameCounter = frameCounter + 1
    if frameCounter < FRAME_DELAY then
        self:SetAlpha(1)
        bg:SetAlpha(1)
        return
    end

    bgTimer = bgTimer + elapsed
    
    -- 1. Handle Background (Black Screen)
    if bgTimer <= BG_WAIT then
        bg:SetAlpha(1)
    elseif bgTimer <= (BG_WAIT + BG_FADE) then
        local bgAlpha = 1 - ((bgTimer - BG_WAIT) / BG_FADE)
        bg:SetAlpha(bgAlpha)
    else
        bg:SetAlpha(0)
    end

    -- 2. Handle Text Readiness (Zone Comparison)
    if not textIsReady then
        local currentZone = GetRealZoneText()
        if (currentZone ~= "" and currentZone ~= lastZoneName) or (bgTimer >= TEXT_TIMEOUT) then
            textIsReady = true
            UpdateZoneInfo()
        else
            -- Keep text hidden until ready
            zoneText:SetAlpha(0)
            subZoneText:SetAlpha(0)
            difficultyText:SetAlpha(0)
        end
    end

    -- 3. Handle Text Fade Sequence (Only starts when ready)
    if textIsReady then
        textTimer = textTimer + elapsed
        
        zoneText:SetAlpha(1)
        subZoneText:SetAlpha(1)
        difficultyText:SetAlpha(1)

        if textTimer <= TEXT_WAIT then
            self:SetAlpha(1)
        elseif textTimer <= (TEXT_WAIT + TEXT_FADE) then
            local textAlpha = 1 - ((textTimer - TEXT_WAIT) / TEXT_FADE)
            self:SetAlpha(textAlpha)
        else
            self:SetAlpha(0)
            isFading = false
            self:Hide()
        end
    end
end

----------------------------------------------------------------------------------------
-- Event Handling
----------------------------------------------------------------------------------------

function FadeIn:StartFade(isReloading)
    if not frame then return end
    
    -- Prevent overlapping events from resetting the fade too quickly (flashing effect)
    local now = GetTime()
    if isFading and (now - lastTriggerTime) < 1 then
        return 
    end
    lastTriggerTime = now
    
    lastZoneName = GetRealZoneText()
    textIsReady = isReloading or false -- Skip wait if it's just a reload
    
    bgTimer = 0
    textTimer = 0
    frameCounter = 0
    isFading = true
    frame:SetAlpha(1)
    bg:SetAlpha(1)
    
    -- Keep text hidden initially until ready
    if not textIsReady then
        zoneText:SetAlpha(0)
        subZoneText:SetAlpha(0)
        difficultyText:SetAlpha(0)
    else
        UpdateZoneInfo()
        zoneText:SetAlpha(1)
        subZoneText:SetAlpha(1)
        difficultyText:SetAlpha(1)
    end
    
    frame:Show()
end

function FadeIn:OnEvent(event, isInitialLogin, isReloading)
    self:StartFade(isReloading)
end

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------

function FadeIn:OnEnable()
    if not (RefineUI.Config.FadeIn and RefineUI.Config.FadeIn.Enable) then return end

    frame = CreateFrame("Frame", "RefineUI_FadeIn", UIParent)
    frame:SetAllPoints(UIParent)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetScript("OnUpdate", OnUpdate)
    frame:Hide()

    bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(0, 0, 0, 1)

    -- Zone Name
    zoneText = frame:CreateFontString(nil, "OVERLAY")
    -- Strict API: Font
    -- 32px might be large, but it's consistent with design intent
    -- SetFontTemplate equivalent is usually handled by internal helpers, 
    -- but here we use strict media references
    zoneText:SetFont(RefineUI.Media.Fonts.Default, RefineUI:Scale(32), "OUTLINE")
    RefineUI.Point(zoneText, "CENTER", frame, "CENTER", 0, 250)
    zoneText:SetTextColor(1, 1, 1)

    -- Subzone Name
    subZoneText = frame:CreateFontString(nil, "OVERLAY")
    subZoneText:SetFont(RefineUI.Media.Fonts.Default, RefineUI:Scale(18), "OUTLINE")
    RefineUI.Point(subZoneText, "TOP", zoneText, "BOTTOM", 0, -5)
    subZoneText:SetTextColor(0.8, 0.8, 0.8)

    -- Difficulty
    difficultyText = frame:CreateFontString(nil, "OVERLAY")
    difficultyText:SetFont(RefineUI.Media.Fonts.Default, RefineUI:Scale(14), "OUTLINE")
    RefineUI.Point(difficultyText, "TOP", subZoneText, "BOTTOM", 0, -5)
    difficultyText:SetTextColor(0.6, 0.6, 0.6)

    frame:SetScript("OnUpdate", OnUpdate)

    RefineUI:RegisterEventCallback("PLAYER_ENTERING_WORLD", function(event, ...) self:OnEvent(event, ...) end, "FadeIn_PEW")

    -- Initial fade if already in world
    if IsLoggedIn() then
        self:StartFade()
    end
end
