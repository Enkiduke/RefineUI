----------------------------------------------------------------------------------------
-- FadeIn for RefineUI
-- Description: Creates a cinematic black-to-transparent transition when entering the world.
----------------------------------------------------------------------------------------

local _, RefineUI = ...

----------------------------------------------------------------------------------------
-- Module Registration
----------------------------------------------------------------------------------------
local FadeIn = RefineUI:RegisterModule("FadeIn")

----------------------------------------------------------------------------------------
-- WoW Globals (Upvalues)
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local GetTime = GetTime
local IsLoggedIn = IsLoggedIn
local UIParent = UIParent

----------------------------------------------------------------------------------------
-- Locals
----------------------------------------------------------------------------------------
local frame
local bg
local isFading = false
local bgTimer = 0
local frameCounter = 0
local lastTriggerTime = 0

-- Timing constants
local BG_WAIT = 0
local BG_FADE = 1.25
local FRAME_DELAY = 8
local EVENT_KEY = "FadeIn:PLAYER_ENTERING_WORLD"
local fadeInInitialized = false

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------

local function ClearLegacyFadeInRegions(targetFrame)
    if not targetFrame then return end

    local regions = { targetFrame:GetRegions() }
    for i = 1, #regions do
        local region = regions[i]
        if region and region.GetObjectType then
            local objectType = region:GetObjectType()
            if objectType == "FontString" then
                region:SetText("")
                region:SetAlpha(0)
                region:Hide()
            elseif objectType == "Texture" and region ~= bg then
                region:SetAlpha(0)
            end
        end
    end
end

local function FindFadeTexture(targetFrame)
    if not targetFrame then return nil end

    local regions = { targetFrame:GetRegions() }
    for i = 1, #regions do
        local region = regions[i]
        if region and region.GetObjectType and region:GetObjectType() == "Texture" then
            return region
        end
    end

    return nil
end

local function FinishFade(self)
    if bg then
        bg:SetAlpha(0)
    end

    isFading = false
    self:Hide()
end

----------------------------------------------------------------------------------------
-- Update Function
----------------------------------------------------------------------------------------

local function OnUpdate(self, elapsed)
    if not isFading then return end

    frameCounter = frameCounter + 1
    if frameCounter < FRAME_DELAY then
        self:SetAlpha(1)
        if bg then
            bg:SetAlpha(1)
        end
        return
    end

    bgTimer = bgTimer + elapsed

    if bgTimer <= BG_WAIT then
        bg:SetAlpha(1)
    elseif bgTimer <= (BG_WAIT + BG_FADE) then
        local bgAlpha = 1 - ((bgTimer - BG_WAIT) / BG_FADE)
        bg:SetAlpha(bgAlpha)
    else
        FinishFade(self)
    end
end

----------------------------------------------------------------------------------------
-- Event Handling
----------------------------------------------------------------------------------------

function FadeIn:StartFade()
    if not frame or not bg then return end

    local now = GetTime()
    if isFading and (now - lastTriggerTime) < 1 then
        return
    end
    lastTriggerTime = now

    bgTimer = 0
    frameCounter = 0
    isFading = true
    frame:SetAlpha(1)
    bg:SetAlpha(1)
    frame:Show()
end

function FadeIn:OnEvent()
    self:StartFade()
end

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------

function FadeIn:OnEnable()
    if not (RefineUI.Config.FadeIn and RefineUI.Config.FadeIn.Enable) then return end

    if not fadeInInitialized then
        frame = _G.RefineUI_FadeIn or CreateFrame("Frame", "RefineUI_FadeIn", UIParent)
        frame:SetAllPoints(UIParent)
        frame:SetFrameStrata("FULLSCREEN_DIALOG")
        frame:SetScript("OnUpdate", OnUpdate)
        frame:Hide()

        ClearLegacyFadeInRegions(frame)

        bg = FindFadeTexture(frame)
        if not bg or not bg.SetColorTexture then
            bg = frame:CreateTexture(nil, "BACKGROUND")
        end

        bg:Show()
        bg:SetAllPoints(frame)
        bg:SetColorTexture(0, 0, 0, 1)

        RefineUI:RegisterEventCallback("PLAYER_ENTERING_WORLD", function(event, ...) self:OnEvent(event, ...) end, EVENT_KEY)
        fadeInInitialized = true
    end

    if IsLoggedIn() then
        self:StartFade()
    end
end
