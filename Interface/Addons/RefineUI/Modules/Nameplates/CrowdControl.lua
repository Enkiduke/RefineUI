-- Nameplates Component: CrowdControl
-- Description: CC bar and portrait icon driven by Blizzard's managed AuraContainer.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Nameplates = RefineUI:GetModule("Nameplates")
if not Nameplates then
    return
end
local Config = RefineUI.Config
local Media = RefineUI.Media

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local type = type
local pcall = pcall
local math_abs = math.abs

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local AuraUtil = AuraUtil
local C_StringUtil = C_StringUtil
local Enum = Enum

----------------------------------------------------------------------------------------
-- Locals
----------------------------------------------------------------------------------------
local NAMEPLATE_CC_STATE_REGISTRY = "NameplateCrowdControlState"
local CrowdControlState = RefineUI:CreateDataRegistry(NAMEPLATE_CC_STATE_REGISTRY, "k")
local NAMEPLATE_CC_AURAFRAME_STATE_REGISTRY = "NameplateCrowdControlAuraFrameState"
local CrowdControlAuraFrameState = RefineUI:CreateDataRegistry(NAMEPLATE_CC_AURAFRAME_STATE_REGISTRY, "k")
local CC_SLOT_KEY = "CrowdControl"
local DEFAULT_COLOR = { 0.2, 0.6, 1.0 }
-- Above the portrait's quest radial (+5) so the CC icon covers it.
local PORTRAIT_OVERLAY_LEVEL_OFFSET = 6
local timerFormatter
local NameplatesUtil = RefineUI.NameplatesUtil
local IsAccessibleValue = NameplatesUtil.IsAccessibleValue
local ReadSafeBoolean = NameplatesUtil.ReadSafeBoolean
local IsUsableUnitToken = NameplatesUtil.IsUsableUnitToken
local SafeTableIndex = NameplatesUtil.SafeTableIndex
local BuildHookKey = NameplatesUtil.BuildHookKey
local BuildCrowdControlHookKey = function(owner, method)
    return BuildHookKey("NameplateCrowdControl", owner, method)
end

local legacyConfigMigrated = false

local function IsNameplateUnitToken(unit)
    if not IsUsableUnitToken(unit) then
        return false
    end
    return unit:match("^nameplate%d+$") ~= nil
end

local function GetAuraFrameState(aurasFrame)
    if not aurasFrame then return nil end
    local state = CrowdControlAuraFrameState[aurasFrame]
    if not state then
        state = {}
        CrowdControlAuraFrameState[aurasFrame] = state
    end
    return state
end

local function GetCrowdControlConfig()
    local nameplates = Config and Config.Nameplates
    if type(nameplates) ~= "table" then
        return nil
    end

    local cfg = nameplates.CrowdControl
    local legacyCfg = nameplates.CrowdControlTest

    if not legacyConfigMigrated and type(cfg) == "table" and type(legacyCfg) == "table" then
        local function IsDefaultCCConfig(t)
            local function NearlyEqual(a, b)
                if type(a) ~= "number" or type(b) ~= "number" then
                    return false
                end
                return math_abs(a - b) < 0.0001
            end

            if type(t) ~= "table" then return false end
            local color = t.Color
            local borderColor = t.BorderColor
            local isDefaultColor = type(color) == "table"
                and NearlyEqual(color[1], 0.2)
                and NearlyEqual(color[2], 0.6)
                and NearlyEqual(color[3], 1.0)
            local isDefaultBorderColor = type(borderColor) == "table"
                and NearlyEqual(borderColor[1], 0.2)
                and NearlyEqual(borderColor[2], 0.6)
                and NearlyEqual(borderColor[3], 1.0)

            return t.Enable == true
                and t.HideWhileCasting == true
                and isDefaultColor
                and isDefaultBorderColor
        end

        if IsDefaultCCConfig(cfg) then
            if legacyCfg.Enable ~= nil then
                cfg.Enable = legacyCfg.Enable
            end
            if legacyCfg.HideWhileCasting ~= nil then
                cfg.HideWhileCasting = legacyCfg.HideWhileCasting
            end
            if type(legacyCfg.Color) == "table" then
                cfg.Color = {
                    legacyCfg.Color[1] or 0.2,
                    legacyCfg.Color[2] or 0.6,
                    legacyCfg.Color[3] or 1.0,
                    legacyCfg.Color[4],
                }
            end
            if type(legacyCfg.BorderColor) == "table" then
                cfg.BorderColor = {
                    legacyCfg.BorderColor[1] or 0.2,
                    legacyCfg.BorderColor[2] or 0.6,
                    legacyCfg.BorderColor[3] or 1.0,
                    legacyCfg.BorderColor[4],
                }
            end
        end

        legacyConfigMigrated = true
    end

    if type(cfg) == "table" then
        return cfg
    end

    if type(legacyCfg) == "table" then
        return legacyCfg
    end

    return nil
end

local function ShouldHideCrowdControlAuraFrame(cfg)
    if not cfg or cfg.Enable == false then
        return false
    end
    return cfg.HideAuraIcons ~= false
end

-- Returns the unit frame's aura container and its crowd-control list frame when both are accessible.
local function GetCrowdControlListFrames(unitFrame)
    if not unitFrame then
        return nil
    end

    local aurasFrame = SafeTableIndex(unitFrame, "AurasFrame")
    if not aurasFrame then
        return nil
    end

    local ccListFrame = SafeTableIndex(aurasFrame, "CrowdControlListFrame")
    if not ccListFrame or not IsAccessibleValue(ccListFrame) then
        return nil
    end

    return aurasFrame, ccListFrame
end

local function EnsureCrowdControlAuraFrameHooks(unitFrame)
    local aurasFrame, ccListFrame = GetCrowdControlListFrames(unitFrame)
    if not aurasFrame then
        return
    end

    local state = GetAuraFrameState(aurasFrame)
    if not state then
        return
    end
    if state.hooksRegistered then
        return
    end

    local hideIfEnabled = function(frameObj)
        local cfg = GetCrowdControlConfig()
        if not ShouldHideCrowdControlAuraFrame(cfg) then
            return
        end

        local frame = SafeTableIndex(frameObj, "CrowdControlListFrame")
        if frame and IsAccessibleValue(frame) and frame:IsShown() then
            frame:Hide()
        end

        local hookState = GetAuraFrameState(frameObj)
        if hookState then
            hookState.suppressed = true
        end
    end

    RefineUI:HookOnce(
        BuildCrowdControlHookKey(aurasFrame, "UpdateEnemyNpcAuraFrames"),
        aurasFrame,
        "UpdateEnemyNpcAuraFrames",
        hideIfEnabled
    )

    RefineUI:HookOnce(
        BuildCrowdControlHookKey(aurasFrame, "UpdateShownState"),
        aurasFrame,
        "UpdateShownState",
        hideIfEnabled
    )

    RefineUI:HookOnce(
        BuildCrowdControlHookKey(ccListFrame, "Show"),
        ccListFrame,
        "Show",
        function(frame)
            local cfg = GetCrowdControlConfig()
            if ShouldHideCrowdControlAuraFrame(cfg) then
                frame:Hide()
            end
        end
    )

    state.hooksRegistered = true
end

local function SyncCrowdControlAuraFrameVisibility(unitFrame, cfg)
    local aurasFrame, ccListFrame = GetCrowdControlListFrames(unitFrame)
    if not aurasFrame then
        return
    end

    local state = GetAuraFrameState(aurasFrame)
    if not state then
        return
    end

    if ShouldHideCrowdControlAuraFrame(cfg) then
        EnsureCrowdControlAuraFrameHooks(unitFrame)
        if ccListFrame:IsShown() then
            ccListFrame:Hide()
        end
        state.suppressed = true
        return
    end

    if state.suppressed then
        if type(aurasFrame.UpdateShownState) == "function" then
            pcall(aurasFrame.UpdateShownState, aurasFrame)
        end
        state.suppressed = false
    end
end

----------------------------------------------------------------------------------------
-- Managed CC Display
----------------------------------------------------------------------------------------
-- 12.1 treats aura data as secret in combat, so addon code can no longer read which
-- CC is on a unit. Blizzard's AuraContainer tracks a CROWD_CONTROL aura slot itself and
-- drives the bar, timer, spell name, and portrait icon we register on its button; the
-- button shows only while a CC aura exists. Everything must be set up inside
-- initializeFrame, before Blizzard restricts access to the button.

local function GetState(unitFrame)
    local state = CrowdControlState[unitFrame]
    if not state then
        state = {}
        CrowdControlState[unitFrame] = state
    end
    return state
end

local function IsCastInProgress(castBar)
    if not castBar or not castBar:IsShown() then
        return false
    end

    return ReadSafeBoolean(castBar.casting) == true
        or ReadSafeBoolean(castBar.channeling) == true
        or ReadSafeBoolean(castBar.reverseChanneling) == true
end

local function GetTimerFormatter()
    if not timerFormatter then
        timerFormatter = C_StringUtil.CreateNumericRuleFormatter()
        timerFormatter:AddBreakpoint({ threshold = 0, format = "%.1f" })
    end
    return timerFormatter
end

local function BuildCrowdControlButton(button, castBar, healthBar, portraitFrame, cfg)
    local color = cfg.Color or DEFAULT_COLOR
    local r, g, b = color[1] or DEFAULT_COLOR[1], color[2] or DEFAULT_COLOR[2], color[3] or DEFAULT_COLOR[3]
    local borderColor = cfg.BorderColor or color
    local br, bg, bb = borderColor[1] or r, borderColor[2] or g, borderColor[3] or b

    -- The CC bar occupies the cast bar's rect; casts hide it via the holder alpha.
    button:ClearAllPoints()
    button:SetAllPoints(castBar)

    local bar = CreateFrame("StatusBar", nil, button)
    bar:SetAllPoints(button)
    -- The border occupies the next level; both must remain below the HP background.
    bar:SetFrameStrata(healthBar:GetFrameStrata())
    bar:SetFrameLevel(math.max(0, healthBar:GetFrameLevel() - 2))
    bar:SetStatusBarTexture(Media.Textures.HealthBar)
    bar:SetStatusBarDesaturated(true)
    bar:SetStatusBarColor(r, g, b)
    RefineUI.CreateBorder(bar, 6, 6, 12)
    bar.border:SetBackdropBorderColor(br, bg, bb, borderColor[4] or 1)

    local background = bar:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(bar)
    background:SetTexture(Media.Textures.HealthBar)
    background:SetVertexColor(r * 0.25, g * 0.25, b * 0.25, 1)

    local spellName = bar:CreateFontString(nil, "OVERLAY")
    RefineUI.Font(spellName, 10, nil, "OUTLINE")
    RefineUI.Point(spellName, "BOTTOMLEFT", bar, "BOTTOMLEFT", 4, 0)
    spellName:SetDrawLayer("OVERLAY", 6)

    local timer = bar:CreateFontString(nil, "OVERLAY")
    RefineUI.Font(timer, 12, nil, "OUTLINE")
    RefineUI.Point(timer, "BOTTOMRIGHT", bar, "BOTTOMRIGHT", -2, 0)
    timer:SetDrawLayer("OVERLAY", 7)

    -- Portrait overlay: covers the unit portrait/quest icon with the CC icon and a
    -- CC-colored ring, matching the portrait's mask and border art.
    local iconFrame = CreateFrame("Frame", nil, button)
    iconFrame:SetAllPoints(portraitFrame)
    iconFrame:SetFrameLevel(portraitFrame:GetFrameLevel() + PORTRAIT_OVERLAY_LEVEL_OFFSET)

    local icon = iconFrame:CreateTexture(nil, "ARTWORK")
    RefineUI.SetInside(icon, iconFrame, 0, 0)
    local mask = iconFrame:CreateMaskTexture()
    mask:SetTexture(Media.Textures.PortraitMask)
    RefineUI.SetInside(mask, iconFrame, 0, 0)
    icon:AddMaskTexture(mask)

    local ring = iconFrame:CreateTexture(nil, "OVERLAY")
    ring:SetTexture(Media.Textures.PortraitBorder)
    RefineUI.SetOutside(ring, iconFrame)
    ring:SetVertexColor(br, bg, bb, 1)

    button:SetDurationBar(bar, {
        interpolation = Enum.StatusBarInterpolation.Immediate,
        direction = Enum.StatusBarTimerDirection.RemainingTime,
    })
    button:SetDurationText(timer, { textFormatter = GetTimerFormatter() })
    button:SetSpellName(spellName)
    button:SetIcon(icon)
end

-- Built lazily once per pooled unit frame; needs the portrait frame to anchor the icon.
local function EnsureCrowdControlDisplay(unitFrame, data, cfg)
    local state = GetState(unitFrame)
    if state.container then
        return state
    end

    local portraitFrame = data.PortraitFrame
    local castBar = NameplatesUtil.GetNameplateCastBar(unitFrame)
    local healthBar = unitFrame.healthBar or unitFrame.HealthBar
    if not portraitFrame or not castBar or not healthBar or not AuraUtil.AuraFilters.CrowdControl then
        return nil
    end

    -- Owns show/hide and hide-while-casting alpha; the bar and portrait icon set their own levels.
    local holder = CreateFrame("Frame", nil, unitFrame)
    holder:SetAllPoints(unitFrame)
    holder:SetFrameLevel(castBar:GetFrameLevel() + 2)

    local container = CreateFrame("AuraContainer", nil, holder, "CustomAuraContainerTemplate")
    container:SetAllPoints(holder)
    container:AddAuraSlot(CC_SLOT_KEY, AuraUtil.CreateFilterString(
        AuraUtil.AuraFilters.Harmful,
        AuraUtil.AuraFilters.CrowdControl,
        AuraUtil.AuraFilters.IncludeNameplateOnly
    ), {
        initializeFrame = function(button)
            BuildCrowdControlButton(button, castBar, healthBar, portraitFrame, cfg)
        end,
    })

    state.holder = holder
    state.container = container
    return state
end

function RefineUI:ClearNameplateCrowdControl(unitFrame)
    if not unitFrame then
        return
    end

    SyncCrowdControlAuraFrameVisibility(unitFrame, GetCrowdControlConfig())

    local state = CrowdControlState[unitFrame]
    if state and state.container then
        state.container:SetEnabled(false)
        state.holder:Hide()
        state.unit = nil
    end
end

function RefineUI:UpdateNameplateCrowdControl(unitFrame, unit)
    if not unitFrame then
        return
    end

    unit = unit or unitFrame.unit
    local cfg = GetCrowdControlConfig()
    local data = Nameplates:GetNameplateData(unitFrame)
    if not IsNameplateUnitToken(unit) or not cfg or cfg.Enable == false or data.RefineHidden then
        self:ClearNameplateCrowdControl(unitFrame)
        return
    end

    SyncCrowdControlAuraFrameVisibility(unitFrame, cfg)

    local state = EnsureCrowdControlDisplay(unitFrame, data, cfg)
    if not state then
        return
    end

    -- Unit removal and name-only transitions clear state.unit, so a reused token rebinds.
    if state.unit ~= unit then
        state.holder:Show()
        state.container:SetUnit(unit)
        state.container:SetEnabled(true)
        state.unit = unit
    end

    -- Cast visuals take priority: hide the whole CC display (bar and portrait icon).
    -- Only a cast in progress counts; a stun ends the cast, and the fading bar that
    -- remains (barType still set) must not keep the CC display hidden.
    local castBar = NameplatesUtil.GetNameplateCastBar(unitFrame)
    local hideForCast = cfg.HideWhileCasting ~= false and IsCastInProgress(castBar)
    state.holder:SetAlpha(hideForCast and 0 or 1)
end
