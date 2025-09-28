-- Modules/ActionBars/ButtonGlow.lua
local R, C, L = unpack(RefineUI)

--------------------------------------------------------------------------------
-- Config / Guards
--------------------------------------------------------------------------------
local cfg = C and C.actionbars or nil
if cfg and cfg.pixelProcGlow == false then return end

-- Lib (hard requirement)
local LibStub = LibStub
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
if not LCG then return end

-- Mode toggles
local HARD_REPLACE                  = not (cfg and cfg.replaceSpellActivationAlert == false)
local KILL_AUTOCAST                 = not (cfg and cfg.killAutoCastShine == false)

--------------------------------------------------------------------------------
-- Upvalues / Locals
--------------------------------------------------------------------------------
local _G                            = _G
local ipairs, type                  = ipairs, type
local CreateFrame, hooksecurefunc   = CreateFrame, hooksecurefunc
local ActionButtonSpellAlertManager = _G.ActionButtonSpellAlertManager
local C_ActionBar                   = _G.C_ActionBar
local IsAssistedCombatAction        = C_ActionBar and C_ActionBar.IsAssistedCombatAction

-- Tunables (unchanged defaults)
local COLOR                         = { 1, 0.82, 0, 1 } -- gold pixel border default
local NUM_PIXELS                    = 8
local FREQ                          = 0.5
local LENGTH                        = 5
local THICK                         = 4
local XOFF, YOFF                    = 0, 0
local BORDER                        = false
local GLOW_KEY                      = "RefineUI_PixelGlow_Proc"

-- Weak map of buttons currently glowing
local active                        = setmetatable({}, { __mode = "k" })

-- Prefix list (use shared if provided)
local prefixes                      = R.ActionBarAllPrefixes or {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button",
    "MultiBar6Button", "MultiBar7Button", "PetActionButton", "StanceButton",
    "OverrideActionBarButton",
}

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------
R.ButtonGlow                        = R.ButtonGlow or {}

local function StartPixelGlow(btn, r, g, b, a)
    if not btn then return end
    -- Keep legacy behavior: passing r,g,b[,a] updates default COLOR persistently
    if r then COLOR[1], COLOR[2], COLOR[3], COLOR[4] = r, g, b, a or COLOR[4] end
    if not active[btn] then
        LCG.PixelGlow_Start(btn, COLOR, NUM_PIXELS, FREQ, LENGTH, THICK, XOFF, YOFF, BORDER, GLOW_KEY)
        active[btn] = true
    end
end
R.ButtonGlow.Start = StartPixelGlow

local function StopPixelGlow(btn)
    if btn and active[btn] then
        LCG.PixelGlow_Stop(btn, GLOW_KEY)
        active[btn] = nil
    end
end
R.ButtonGlow.Stop = StopPixelGlow

function R.ButtonGlow.IsActive(btn)
    return not not active[btn]
end

function R.ButtonGlow.SetColor(r, g, b, a)
    if type(r) == "table" then
        COLOR[1], COLOR[2], COLOR[3], COLOR[4] = r[1], r[2], r[3], r[4] or COLOR[4]
    else
        COLOR[1], COLOR[2], COLOR[3], COLOR[4] = r, g, b, a or COLOR[4]
    end
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local function KillAutoCast(btn)
    if not (KILL_AUTOCAST and btn) then return end
    local shine = btn.AutoCastShine
    if shine then
        shine:Hide()
        if not shine.__RefineUI_Killed then
            shine.__RefineUI_Killed = true
            shine.Show = function() end -- hard kill to avoid churn
        end
    end
end

local function EnsureDummyAlert(btn)
    if not btn then return end
    local alert = btn.SpellActivationAlert
    if alert and alert.__RefineUI_Dummy then
        return alert
    end
    if alert then
        alert:Hide()
    end

    local f = CreateFrame("Frame", nil, btn)
    f:Hide()
    f.__RefineUI_Dummy = true
    f:SetAllPoints(btn)

    -- Textures Blizzard may poke
    f.ProcStartFlipbook = f:CreateTexture(nil, "OVERLAY"); f.ProcStartFlipbook:SetAlpha(0)
    f.ProcLoopFlipbook = f:CreateTexture(nil, "OVERLAY"); f.ProcLoopFlipbook:SetAlpha(0)
    f.ProcAltGlow = f:CreateTexture(nil, "OVERLAY"); f.ProcAltGlow:SetAlpha(0)
    f.spark = f:CreateTexture(nil, "OVERLAY"); f.spark:SetAlpha(0)
    f.innerGlow = f:CreateTexture(nil, "OVERLAY"); f.innerGlow:SetAlpha(0)
    f.innerGlowOver = f:CreateTexture(nil, "OVERLAY"); f.innerGlowOver:SetAlpha(0)
    f.outerGlow = f:CreateTexture(nil, "OVERLAY"); f.outerGlow:SetAlpha(0)
    f.outerGlowOver = f:CreateTexture(nil, "OVERLAY"); f.outerGlowOver:SetAlpha(0)
    f.ants = f:CreateTexture(nil, "OVERLAY"); f.ants:SetAlpha(0)

    -- Animation groups Blizzard may call
    f.ProcStartAnim          = f:CreateAnimationGroup()
    f.ProcLoop               = f:CreateAnimationGroup()

    btn.SpellActivationAlert = f
    return f
end

local function HideBlizzOverlay(btn)
    local alert = btn and btn.SpellActivationAlert
    if not alert then return end
    alert:Hide()
    if not alert.__RefineUI_Hooked then
        alert.__RefineUI_Hooked = true
        hooksecurefunc(alert, "Show", alert.Hide) -- ensure it stays hidden if poked
    end
end

local function EnsureAssistedDummy(btn)
    local acr = btn and btn.AssistedCombatRotationFrame
    if acr and not acr.SpellActivationAlert then
        acr.SpellActivationAlert = EnsureDummyAlert(btn)
    end
end

local function OnButtonHide(self)
    StopPixelGlow(self)
end

local function InitButton(btn)
    if not btn or btn.__RefineUI_ButtonGlowInit then return end
    btn.__RefineUI_ButtonGlowInit = true
    btn:HookScript("OnHide", OnButtonHide)
    KillAutoCast(btn)
    HideBlizzOverlay(btn)
    EnsureDummyAlert(btn)
    EnsureAssistedDummy(btn)
end

-- Pre-scan existing Blizzard buttons (covers most layouts; safe upper bound 24)
function R.ButtonGlow.ScanButtons(customPrefixes, maxIndex)
    local list = customPrefixes or prefixes
    local last = maxIndex or 24
    for _, prefix in ipairs(list) do
        for i = 1, last do
            local b = _G[prefix .. i]
            if b then InitButton(b) end
        end
    end
end

--------------------------------------------------------------------------------
-- Bootstrap
--------------------------------------------------------------------------------
do R.ButtonGlow.ScanButtons() end

--------------------------------------------------------------------------------
-- Implementation modes
--------------------------------------------------------------------------------
if HARD_REPLACE then
    -- Hard replace Blizzard functions
    _G.ActionButton_ShowOverlayGlow = function(btn)
        if not btn then return end
        HideBlizzOverlay(btn)
        EnsureDummyAlert(btn)
        KillAutoCast(btn)
        StartPixelGlow(btn)
    end

    _G.ActionButton_HideOverlayGlow = function(btn)
        if not btn then return end
        HideBlizzOverlay(btn)
        StopPixelGlow(btn)
    end

    _G.ActionButton_GetOverlayGlow = function(btn)
        return EnsureDummyAlert(btn)
    end
else
    -- Hook mode (respect Blizzard calls; replace visuals)
    hooksecurefunc("ActionButton_ShowOverlayGlow", function(btn)
        if not btn then return end
        HideBlizzOverlay(btn)
        KillAutoCast(btn)
        StartPixelGlow(btn)
    end)

    hooksecurefunc("ActionButton_HideOverlayGlow", function(btn)
        if not btn then return end
        HideBlizzOverlay(btn)
        StopPixelGlow(btn)
    end)

    hooksecurefunc("ActionButton_GetOverlayGlow", function(btn)
        EnsureDummyAlert(btn)
    end)
end

--------------------------------------------------------------------------------
-- Retail 11.1.7+ manager path
--------------------------------------------------------------------------------
if ActionButtonSpellAlertManager and IsAssistedCombatAction then
    hooksecurefunc(ActionButtonSpellAlertManager, "ShowAlert", function(_, actionButton, _alertType)
        if not actionButton then return end
        EnsureDummyAlert(actionButton)
        EnsureAssistedDummy(actionButton)
        HideBlizzOverlay(actionButton)
        StartPixelGlow(actionButton)
    end)

    hooksecurefunc(ActionButtonSpellAlertManager, "HideAlert", function(_, actionButton, _alertType)
        if not actionButton then return end
        HideBlizzOverlay(actionButton)
        StopPixelGlow(actionButton)
    end)
end
