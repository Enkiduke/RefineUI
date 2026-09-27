----------------------------------------------------------------------------------------
-- FadeIn for RefineUI
-- Description: Creates a cinematic black-to-transparent transition when entering the world.
----------------------------------------------------------------------------------------

local _, RefineUI = ...

----------------------------------------------------------------------------------------
-- Module Registration
----------------------------------------------------------------------------------------
local FadeIn = RefineUI:RegisterModule("FadeIn", "FadeIn")

----------------------------------------------------------------------------------------
-- WoW Globals (Upvalues)
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local UIParent = UIParent
local min = math.min

----------------------------------------------------------------------------------------
-- Locals
----------------------------------------------------------------------------------------
local FADE_DURATION = 1.25
-- Post-loading-screen frames report large elapsed values; cap each step so a hitch
-- cannot consume the whole fade in one frame.
local MAX_STEP = 1 / 30
local EVENT_KEY = "FadeIn:LOADING_SCREEN_DISABLED"

local frame
local remaining = 0

----------------------------------------------------------------------------------------
-- Update Function
----------------------------------------------------------------------------------------

local function OnUpdate(self, elapsed)
    remaining = remaining - min(elapsed, MAX_STEP)
    if remaining <= 0 then
        self:Hide()
    else
        self:SetAlpha(remaining / FADE_DURATION)
    end
end

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------

function FadeIn:OnEnable()
    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetAllPoints(UIParent)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetScript("OnUpdate", OnUpdate)
    frame:Hide()

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(0, 0, 0, 1)

    RefineUI:RegisterEventCallback("LOADING_SCREEN_DISABLED", function()
        remaining = FADE_DURATION
        frame:SetAlpha(1)
        frame:Show()
    end, EVENT_KEY)
end
