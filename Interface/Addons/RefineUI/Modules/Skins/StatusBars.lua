----------------------------------------------------------------------------------------
-- Skins Component: Status Bars
-- Description: Suppresses Blizzard status tracking bars and skins mirror timers.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Skins = RefineUI:GetModule("Skins")
if not Skins then
    return
end

----------------------------------------------------------------------------------------
-- Shared Aliases
----------------------------------------------------------------------------------------
local Config = RefineUI.Config
local Media = RefineUI.Media
local Colors = RefineUI.Colors
local Locale = RefineUI.Locale

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local type = type
local ipairs = ipairs
local C_AddOns = C_AddOns

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local COMPONENT_KEY = "Skins:StatusBars"
local STATE_REGISTRY = "SkinsStatusBarsState"
local BLIZZARD_MIRROR_TIMER_ADDON = "Blizzard_MirrorTimer"
local STATUS_BAR_TEXTURE = (Media and Media.Textures and (Media.Textures.Smooth or Media.Textures.Statusbar))

local EVENT_KEY = {
    PLAYER_ENTERING_WORLD = COMPONENT_KEY .. ":Event:PLAYER_ENTERING_WORLD",
}

local HOOK_KEY = {
    MIRROR_TIMER_SETUP = COMPONENT_KEY .. ":Hook:MirrorTimerContainer:SetupTimer",
}

local TIMER_BAR_COLOR = {
    BREATH = { 0.31, 0.45, 0.63 },
    EXHAUSTION = { 1.00, 0.90, 0.00 },
    DEATH = { 1.00, 0.70, 0.00 },
    FEIGNDEATH = { 0.30, 0.70, 0.00 },
}

local STATE_KEY = {
    BASE_SKINNED = "baseSkinned",
    BAR_BACKGROUND = "barBackground",
}

RefineUI:CreateDataRegistry(STATE_REGISTRY, "k")

----------------------------------------------------------------------------------------
-- State Helpers
----------------------------------------------------------------------------------------
local function GetState(owner, key, defaultValue)
    return RefineUI:RegistryGet(STATE_REGISTRY, owner, key, defaultValue)
end

local function SetState(owner, key, value)
    RefineUI:RegistrySet(STATE_REGISTRY, owner, key, value)
end

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function CanSkinObject(frame)
    if not frame then
        return false
    end

    if frame.IsForbidden and frame:IsForbidden() then
        return false
    end

    return true
end

local function SuppressBlizzardStatusTrackingBars()
    local mainContainer = _G.MainStatusTrackingBarContainer
    local secondaryContainer = _G.SecondaryStatusTrackingBarContainer

    if CanSkinObject(mainContainer) then
        RefineUI.Kill(mainContainer)
    end

    if CanSkinObject(secondaryContainer) then
        RefineUI.Kill(secondaryContainer)
    end
end

local function EnsureMirrorTimerBarBackground(statusBar)
    if not CanSkinObject(statusBar) or type(statusBar.CreateTexture) ~= "function" then
        return nil
    end

    local background = GetState(statusBar, STATE_KEY.BAR_BACKGROUND)
    if not background then
        background = statusBar:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        SetState(statusBar, STATE_KEY.BAR_BACKGROUND, background)
    end

    if background then
        if STATUS_BAR_TEXTURE then
            background:SetTexture(STATUS_BAR_TEXTURE)
        end
        background:SetVertexColor(0, 0, 0, 0.45)
    end

    return background
end

local function ApplyMirrorTimerBaseSkin(timerFrame)
    if not CanSkinObject(timerFrame) then
        return
    end

    if not GetState(timerFrame, STATE_KEY.BASE_SKINNED, false) then
        RefineUI.StripTextures(timerFrame, true)

        local statusBar = timerFrame.StatusBar
        if CanSkinObject(statusBar) then
            EnsureMirrorTimerBarBackground(statusBar)
            RefineUI.CreateBorder(statusBar, 6, 6, 12)
        end

        if timerFrame.Text then
            timerFrame.Text:ClearAllPoints()
            if CanSkinObject(statusBar) then
                timerFrame.Text:SetParent(statusBar)
                timerFrame.Text:SetPoint("CENTER", statusBar, "CENTER", 0, 0)
            end
            timerFrame.Text:SetJustifyH("CENTER")
            timerFrame.Text:SetJustifyV("MIDDLE")
            RefineUI.Font(timerFrame.Text, 10)
        end

        SetState(timerFrame, STATE_KEY.BASE_SKINNED, true)
    end
end

local function ApplyMirrorTimerDynamicSkin(timerFrame, timerType)
    if not CanSkinObject(timerFrame) then
        return
    end

    local statusBar = timerFrame.StatusBar
    if not CanSkinObject(statusBar) then
        return
    end

    if STATUS_BAR_TEXTURE and statusBar.SetStatusBarTexture then
        statusBar:SetStatusBarTexture(STATUS_BAR_TEXTURE)
    end

    EnsureMirrorTimerBarBackground(statusBar)

    local color = timerType and TIMER_BAR_COLOR[timerType]
    if color and statusBar.SetStatusBarColor then
        statusBar:SetStatusBarColor(color[1], color[2], color[3])
    end

    if timerFrame.Text then
        RefineUI.Font(timerFrame.Text, 10)
    end
end

local function SkinMirrorTimer(timerFrame, timerType)
    ApplyMirrorTimerBaseSkin(timerFrame)
    ApplyMirrorTimerDynamicSkin(timerFrame, timerType)
end

local function ResolveMirrorTimerFrame(container, timerType)
    if not CanSkinObject(container) then
        return nil
    end

    if timerType and container.GetActiveTimer then
        local activeTimer = container:GetActiveTimer(timerType)
        if activeTimer then
            return activeTimer
        end
    end

    if timerType and container.GetAvailableTimer then
        return container:GetAvailableTimer(timerType)
    end

    return nil
end

local function SkinExistingMirrorTimers(container)
    if not CanSkinObject(container) then
        return
    end

    local mirrorTimers = container.mirrorTimers
    if type(mirrorTimers) ~= "table" then
        return
    end

    for _, timerFrame in ipairs(mirrorTimers) do
        if CanSkinObject(timerFrame) then
            SkinMirrorTimer(timerFrame, timerFrame.timer)
        end
    end
end

----------------------------------------------------------------------------------------
-- Mirror Timer Integration
----------------------------------------------------------------------------------------
local function InstallMirrorTimerSkin()
    local container = _G.MirrorTimerContainer
    if not CanSkinObject(container) then
        return
    end

    RefineUI:HookOnce(HOOK_KEY.MIRROR_TIMER_SETUP, container, "SetupTimer", function(hookedContainer, timerType)
        local timerFrame = ResolveMirrorTimerFrame(hookedContainer, timerType)
        if timerFrame then
            SkinMirrorTimer(timerFrame, timerType)
        end
    end)

    SkinExistingMirrorTimers(container)
end

local function RegisterMirrorTimerSkin()
    RefineUI.SkinFuncs = RefineUI.SkinFuncs or {}

    local existingBucket = RefineUI.SkinFuncs[BLIZZARD_MIRROR_TIMER_ADDON]
    if type(existingBucket) == "function" then
        RefineUI.SkinFuncs[BLIZZARD_MIRROR_TIMER_ADDON] = {
            existingBucket,
            [COMPONENT_KEY] = InstallMirrorTimerSkin,
        }
    elseif type(existingBucket) == "table" then
        existingBucket[COMPONENT_KEY] = InstallMirrorTimerSkin
    else
        RefineUI.SkinFuncs[BLIZZARD_MIRROR_TIMER_ADDON] = {
            [COMPONENT_KEY] = InstallMirrorTimerSkin,
        }
    end

    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(BLIZZARD_MIRROR_TIMER_ADDON) then
        InstallMirrorTimerSkin()
    end
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function Skins:SetupStatusBars()
    SuppressBlizzardStatusTrackingBars()

    -- Re-assert suppression after the world is fully entered in case Blizzard initializes late.
    if RefineUI.OnceEvent then
        RefineUI:OnceEvent("PLAYER_ENTERING_WORLD", function()
            SuppressBlizzardStatusTrackingBars()
        end, EVENT_KEY.PLAYER_ENTERING_WORLD)
    else
        RefineUI:RegisterEventCallback("PLAYER_ENTERING_WORLD", function()
            SuppressBlizzardStatusTrackingBars()
        end, EVENT_KEY.PLAYER_ENTERING_WORLD)
    end

    RegisterMirrorTimerSkin()
end
