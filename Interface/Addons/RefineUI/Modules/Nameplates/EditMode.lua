----------------------------------------------------------------------------------------
-- Nameplates Edit Mode for RefineUI
-- Description: Adds a fake test nameplate and Nameplates settings to Edit Mode.
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
local floor = math.floor
local max = math.max
local tonumber = tonumber
local unpack = unpack
local type = type
local format = string.format
local issecretvalue = _G.issecretvalue
local CreateColor = CreateColor

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local GetCVar = GetCVar
local SetCVar = SetCVar
local UIParent = UIParent
local SetPortraitTexture = SetPortraitTexture
local UnitExists = UnitExists
local UnitCanAttack = UnitCanAttack
local hooksecurefunc = hooksecurefunc
local GameTooltip = GameTooltip
local GameTooltip_Hide = GameTooltip_Hide
local SettingsPanel = SettingsPanel
local ScrollUtil = ScrollUtil
local EventRegistry = EventRegistry

----------------------------------------------------------------------------------------
-- Locals
----------------------------------------------------------------------------------------
local EDITMODE_FRAME_NAME = "RefineUI_NameplatesEditModeFrame"

local editModeFrame
local editModeRegistered = false
local editModeCallbacksRegistered = false
local editModeSettingsRegistered = false
local editModeSettingsAttached = false
local editModeDialogHooked = false
local editModeSettings

local DEFAULT_PLATE_SIZE = { 150, 20 }
local function ResolveDefaultColor(source, fallback)
    if type(source) ~= "table" then
        return { fallback[1], fallback[2], fallback[3] }
    end

    return {
        tonumber(source[1]) or fallback[1],
        tonumber(source[2]) or fallback[2],
        tonumber(source[3]) or fallback[3],
    }
end

local DEFAULT_CAST_COLORS = {
    Interruptible = ResolveDefaultColor(
        Config and Config.Nameplates and Config.Nameplates.CastBar and Config.Nameplates.CastBar.Colors and Config.Nameplates.CastBar.Colors.Interruptible,
        { 1, 0.7, 0 }
    ),
    NonInterruptible = ResolveDefaultColor(
        Config and Config.Nameplates and Config.Nameplates.CastBar and Config.Nameplates.CastBar.Colors and Config.Nameplates.CastBar.Colors.NonInterruptible,
        { 1, 0.2, 0.2 }
    ),
}
local DEFAULT_THREAT_COLORS = {
    SafeColor = { 0.2, 0.8, 0.2 },
    OffTankColor = { 0, 0.5, 1 },
    TransitionColor = { 1, 1, 0 },
    WarningColor = { 1, 0, 0 },
}
local DEFAULT_CC_COLORS = {
    Color = { 0.2, 0.6, 1.0 },
    BorderColor = { 0.2, 0.6, 1.0 },
}
local DEFAULT_ENEMY_AURA_LAYOUT = {
    BaseOffsetY = 6,
    DebuffOffsetX = 0,
    DebuffOffsetY = 0,
    DebuffSpacing = 2,
    BuffOffsetX = 0,
    BuffOffsetY = 0,
    BuffSpacing = 2,
}
local DEFAULT_TEXT_SCALE = 1
local NAMEPLATE_SCALE_MIN = 0.5
local NAMEPLATE_SCALE_MAX = 2.0
local NAMEPLATE_SCALE_STEP = 0.05
local WORLD_TEXT_SCALE_CVAR = "WorldTextScale_v2"
local WORLD_TEXT_SCALE_DEFAULT = 0.1
local WORLD_TEXT_SCALE_MIN = 0.05
local WORLD_TEXT_SCALE_MAX = 2.0
local WORLD_TEXT_SCALE_STEP = 0.05
local PREVIEW_NAME_FONT_SIZE = 12
local PREVIEW_HEALTH_FONT_SIZE = 18
local PREVIEW_PORTRAIT_BASE_SIZE = 36
local PREVIEW_ARROW_SIZE = 24
local PREVIEW_AURA_SIZE = 20
local PREVIEW_PADDING = 8
local PREVIEW_FRIENDLY_GAP = 16
local PREVIEW_STATE_SECONDS = 2.5
local PREVIEW_STATE_CAST = 1
local PREVIEW_STATE_CAST_LOCKED = 2
local PREVIEW_STATE_CC = 3
local PREVIEW_STATE_IDLE = 4
local PREVIEW_CAST_ICON = "Interface\\Icons\\Spell_Shadow_ShadowBolt"
local PREVIEW_CC_ICON = "Interface\\Icons\\Spell_Nature_Polymorph"
local PREVIEW_DEBUFF_ICONS = {
    "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
    "Interface\\Icons\\Spell_Fire_Immolation",
    "Interface\\Icons\\Spell_Nature_Slow",
}
local PREVIEW_BUFF_ICONS = {
    "Interface\\Icons\\Spell_Holy_PowerWordShield",
    "Interface\\Icons\\Spell_Nature_Rejuvenation",
}
local EDITMODE_DEFAULT_POINT = "TOPLEFT"
local EDITMODE_DEFAULT_X = 500
local EDITMODE_DEFAULT_Y = -250
local EDITMODE_SETTINGS_POINT = "TOPLEFT"
local EDITMODE_SETTINGS_RELATIVE_POINT = "TOPRIGHT"
local EDITMODE_SETTINGS_OFFSET_X = 8
local EDITMODE_SETTINGS_OFFSET_Y = 0
local THREAT_SETTING_ENABLE = "Threat Colors"
local THREAT_SETTING_INSTANCE_ONLY = "Instance Only"
local THREAT_SETTING_SAFE = "Safe"
local THREAT_SETTING_TRANSITION = "Transition"
local THREAT_SETTING_WARNING = "Warning"
local THREAT_DEPENDENT_SETTING_LOOKUP = {
    [THREAT_SETTING_INSTANCE_ONLY] = true,
    [THREAT_SETTING_SAFE] = true,
    [THREAT_SETTING_TRANSITION] = true,
    [THREAT_SETTING_WARNING] = true,
}

local function ResolvePreviewPortraitUnit()
    if UnitExists("target") and UnitCanAttack("player", "target") then
        return "target"
    end
    return "player"
end

local function SetPreviewPortraitTexture(portrait)
    if not portrait or not SetPortraitTexture then
        return
    end

    local unit = ResolvePreviewPortraitUnit()
    local ok = pcall(SetPortraitTexture, portrait, unit)
    if not ok then
        portrait:SetTexture(134400) -- Question mark fallback
    end
end

local function EnsureSelectionInteractive(frame)
    local lib = RefineUI.LibEditMode
    local selection = lib and lib.frameSelections and lib.frameSelections[frame]
    if not selection then
        return nil
    end

    selection.parent = selection.parent or frame
    selection:SetAllPoints(frame)
    selection:SetFrameStrata(frame:GetFrameStrata())
    selection:SetFrameLevel((frame:GetFrameLevel() or 1) + 100)
    selection:EnableMouse(true)

    if type(selection.ShowHighlighted) == "function" then
        selection:ShowHighlighted()
    else
        selection:Show()
    end

    return selection
end

local function SelectPreviewFrame(frame)
    local lib = RefineUI.LibEditMode
    if not lib or type(lib.IsInEditMode) ~= "function" or not lib:IsInEditMode() then
        return
    end

    local selection = EnsureSelectionInteractive(frame)
    if not selection then
        return
    end

    local onMouseDown = selection:GetScript("OnMouseDown")
    if type(onMouseDown) == "function" then
        onMouseDown(selection)
    end
end

local function ClampNumber(value, low, high, fallback)
    local n = tonumber(value)
    if not n then
        n = fallback
    end
    if n < low then
        return low
    end
    if n > high then
        return high
    end
    return n
end

local function RoundToStep(value, step)
    if not step or step <= 0 then
        return value
    end
    return floor((value / step) + 0.5) * step
end

local function FormatScaleValue(value, low, high, fallback, step)
    local rounded = RoundToStep(
        ClampNumber(value, low, high, fallback),
        step
    )
    return format("%.2f", rounded)
end

local function FormatNameplateScaleValue(value)
    return FormatScaleValue(value, NAMEPLATE_SCALE_MIN, NAMEPLATE_SCALE_MAX, DEFAULT_TEXT_SCALE, NAMEPLATE_SCALE_STEP)
end

local function FormatWorldTextScaleValue(value)
    return FormatScaleValue(
        value,
        WORLD_TEXT_SCALE_MIN,
        WORLD_TEXT_SCALE_MAX,
        WORLD_TEXT_SCALE_DEFAULT,
        WORLD_TEXT_SCALE_STEP
    )
end

local function GetConfiguredWorldTextScale()
    local currentValue = type(GetCVar) == "function" and GetCVar(WORLD_TEXT_SCALE_CVAR) or nil
    return RoundToStep(
        ClampNumber(currentValue, WORLD_TEXT_SCALE_MIN, WORLD_TEXT_SCALE_MAX, WORLD_TEXT_SCALE_DEFAULT),
        WORLD_TEXT_SCALE_STEP
    )
end

local function EnsureColorTable(root, key, fallback)
    local current = root and root[key]
    if type(current) ~= "table" then
        current = { fallback[1], fallback[2], fallback[3], fallback[4] }
        root[key] = current
    end

    if current[1] == nil then current[1] = fallback[1] end
    if current[2] == nil then current[2] = fallback[2] end
    if current[3] == nil then current[3] = fallback[3] end
    if fallback[4] ~= nil and current[4] == nil then current[4] = fallback[4] end
    return current
end

local function ColorTableToMixin(color, fallback)
    local r = ClampNumber(color and color[1], 0, 1, fallback[1] or 1)
    local g = ClampNumber(color and color[2], 0, 1, fallback[2] or 1)
    local b = ClampNumber(color and color[3], 0, 1, fallback[3] or 1)
    local a = ClampNumber(color and color[4], 0, 1, fallback[4] or 1)
    return CreateColor(r, g, b, a)
end

local function SaveColorMixinToTable(target, color)
    if type(target) ~= "table" or not color or type(color.GetRGBA) ~= "function" then
        return
    end

    local r, g, b, a = color:GetRGBA()
    target[1] = ClampNumber(r, 0, 1, target[1] or 1)
    target[2] = ClampNumber(g, 0, 1, target[2] or 1)
    target[3] = ClampNumber(b, 0, 1, target[3] or 1)
    target[4] = ClampNumber(a, 0, 1, target[4] or 1)
end

local function GetNameplatesConfig()
    if not Config.Nameplates then
        Config.Nameplates = {}
    end
    if not Config.Nameplates.CastBar then
        Config.Nameplates.CastBar = {}
    end
    if not Config.Nameplates.CastBar.Colors then
        Config.Nameplates.CastBar.Colors = {}
    end
    if not Config.Nameplates.Threat then
        Config.Nameplates.Threat = {}
    end
    if not Config.Nameplates.CrowdControl then
        Config.Nameplates.CrowdControl = {}
    end
    if not Config.Nameplates.EnemyAuras then
        Config.Nameplates.EnemyAuras = {}
    end
    if Config.Nameplates.ShowNPCTitles == nil then
        Config.Nameplates.ShowNPCTitles = true
    end
    if Config.Nameplates.ShowPetNames == nil then
        Config.Nameplates.ShowPetNames = false
    end
    local resolvedScale = DEFAULT_TEXT_SCALE
    if Nameplates and Nameplates.GetConfiguredNameplateScale then
        resolvedScale = Nameplates:GetConfiguredNameplateScale()
    end
    Config.Nameplates.Scale = RoundToStep(
        ClampNumber(
            resolvedScale,
            NAMEPLATE_SCALE_MIN,
            NAMEPLATE_SCALE_MAX,
            DEFAULT_TEXT_SCALE
        ),
        NAMEPLATE_SCALE_STEP
    )
    Config.Nameplates.Alpha = RoundToStep(
        ClampNumber(Config.Nameplates.Alpha, 0.1, 1, 0.5),
        0.05
    )
    Config.Nameplates.NoTargetAlpha = RoundToStep(
        ClampNumber(Config.Nameplates.NoTargetAlpha, 0.1, 1, 1),
        0.05
    )
    Config.Nameplates.CastAlpha = RoundToStep(
        ClampNumber(Config.Nameplates.CastAlpha, 0.1, 1, 0.75),
        0.05
    )

    local castColors = Config.Nameplates.CastBar.Colors
    EnsureColorTable(castColors, "Interruptible", DEFAULT_CAST_COLORS.Interruptible)
    EnsureColorTable(castColors, "NonInterruptible", DEFAULT_CAST_COLORS.NonInterruptible)

    local threat = Config.Nameplates.Threat
    if threat.Enable == nil then
        threat.Enable = true
    end
    if threat.InstanceOnly == nil then
        threat.InstanceOnly = false
    end

    -- Safe/Transition/Warning are used by hybrid threat coloring.
    -- OffTank values are retained for compatibility with older SavedVariables.
    EnsureColorTable(threat, "SafeColor", DEFAULT_THREAT_COLORS.SafeColor)
    EnsureColorTable(threat, "OffTankColor", DEFAULT_THREAT_COLORS.OffTankColor)
    EnsureColorTable(threat, "TransitionColor", DEFAULT_THREAT_COLORS.TransitionColor)
    EnsureColorTable(threat, "WarningColor", DEFAULT_THREAT_COLORS.WarningColor)
    if threat.OffTankScanThrottle == nil then
        threat.OffTankScanThrottle = 0.5
    end

    local crowdControl = Config.Nameplates.CrowdControl
    if crowdControl.Enable == nil then
        crowdControl.Enable = true
    end
    if crowdControl.HideWhileCasting == nil then
        crowdControl.HideWhileCasting = true
    end
    if crowdControl.HideAuraIcons == nil then
        crowdControl.HideAuraIcons = true
    end
    local ccColor = EnsureColorTable(crowdControl, "Color", DEFAULT_CC_COLORS.Color)
    local ccBorderColor = EnsureColorTable(crowdControl, "BorderColor", DEFAULT_CC_COLORS.BorderColor)
    ccBorderColor[1] = ccColor[1]
    ccBorderColor[2] = ccColor[2]
    ccBorderColor[3] = ccColor[3]
    if ccColor[4] ~= nil then
        ccBorderColor[4] = ccColor[4]
    end

    local enemyAuras = Config.Nameplates.EnemyAuras
    enemyAuras.BaseOffsetY = RoundToStep(
        ClampNumber(enemyAuras.BaseOffsetY, -20, 40, DEFAULT_ENEMY_AURA_LAYOUT.BaseOffsetY),
        1
    )
    enemyAuras.DebuffOffsetX = RoundToStep(
        ClampNumber(enemyAuras.DebuffOffsetX, -80, 80, DEFAULT_ENEMY_AURA_LAYOUT.DebuffOffsetX),
        1
    )
    enemyAuras.DebuffOffsetY = RoundToStep(
        ClampNumber(enemyAuras.DebuffOffsetY, -40, 80, DEFAULT_ENEMY_AURA_LAYOUT.DebuffOffsetY),
        1
    )
    enemyAuras.DebuffSpacing = RoundToStep(
        ClampNumber(enemyAuras.DebuffSpacing, 0, 16, DEFAULT_ENEMY_AURA_LAYOUT.DebuffSpacing),
        1
    )
    enemyAuras.BuffOffsetX = RoundToStep(
        ClampNumber(enemyAuras.BuffOffsetX, -80, 80, DEFAULT_ENEMY_AURA_LAYOUT.BuffOffsetX),
        1
    )
    enemyAuras.BuffOffsetY = RoundToStep(
        ClampNumber(enemyAuras.BuffOffsetY, -40, 80, DEFAULT_ENEMY_AURA_LAYOUT.BuffOffsetY),
        1
    )
    enemyAuras.BuffSpacing = RoundToStep(
        ClampNumber(enemyAuras.BuffSpacing, 0, 16, DEFAULT_ENEMY_AURA_LAYOUT.BuffSpacing),
        1
    )

    return Config.Nameplates
end

local function RefreshThreatSettingAvailability()
    local threat = GetNameplatesConfig().Threat
    local disableDependentSettings = threat.Enable == false

    if type(editModeSettings) ~= "table" then
        return
    end

    for i = 1, #editModeSettings do
        local setting = editModeSettings[i]
        if setting and THREAT_DEPENDENT_SETTING_LOOKUP[setting.name] then
            setting.disabled = disableDependentSettings
        end
    end
end

local function ApplyStoredPosition(point, x, y)
    RefineUI:SetPosition(EDITMODE_FRAME_NAME, { point, "UIParent", point, x, y })
end

local function ApplyStoredAnchor(frame)
    if not frame then
        return
    end

    frame:ClearAllPoints()

    local pos = RefineUI.Positions and RefineUI.Positions[EDITMODE_FRAME_NAME]
    if pos then
        local point, relativeTo, relativePoint, x, y = unpack(pos)
        local anchor = (type(relativeTo) == "string" and _G[relativeTo]) or relativeTo or UIParent
        frame:SetPoint(point or "CENTER", anchor, relativePoint or point or "CENTER", x or 0, y or 0)
    else
        frame:SetPoint(EDITMODE_DEFAULT_POINT, UIParent, EDITMODE_DEFAULT_POINT, EDITMODE_DEFAULT_X, EDITMODE_DEFAULT_Y)
    end
end

local function GetEditModeDialog()
    local lib = RefineUI.LibEditMode
    return lib and lib.internal and lib.internal.dialog or nil
end

local function IsSettingsDialogForNameplates(selection)
    local dialog = GetEditModeDialog()
    local activeSelection = selection or (dialog and dialog.selection)
    return activeSelection and editModeFrame and activeSelection.parent == editModeFrame
end

local function AnchorSettingsDialogToPreview(selection)
    local dialog = GetEditModeDialog()
    if not dialog or not dialog:IsShown() then
        return
    end

    if not IsSettingsDialogForNameplates(selection) then
        return
    end

    local frame = editModeFrame
    if not frame or not frame:IsShown() then
        return
    end

    dialog:ClearAllPoints()
    dialog:SetPoint(
        EDITMODE_SETTINGS_POINT,
        frame,
        EDITMODE_SETTINGS_RELATIVE_POINT,
        EDITMODE_SETTINGS_OFFSET_X,
        EDITMODE_SETTINGS_OFFSET_Y
    )
end

local function HookEditModeDialog()
    if editModeDialogHooked then
        return
    end

    local dialog = GetEditModeDialog()
    if not dialog then
        return
    end

    local updateHooked = false
    if type(RefineUI.HookOnce) == "function" then
        local ok = RefineUI:HookOnce("Nameplates:EditModeDialog:Update", dialog, "Update", function(_, selection)
            AnchorSettingsDialogToPreview(selection)
        end)
        updateHooked = ok == true
    end
    if not updateHooked then
        hooksecurefunc(dialog, "Update", function(_, selection)
            AnchorSettingsDialogToPreview(selection)
        end)
    end

    local showHooked = false
    if type(RefineUI.HookScriptOnce) == "function" then
        local ok = RefineUI:HookScriptOnce("Nameplates:EditModeDialog:OnShow", dialog, "OnShow", function()
            AnchorSettingsDialogToPreview()
        end)
        showHooked = ok == true
    end
    if not showHooked then
        dialog:HookScript("OnShow", function()
            AnchorSettingsDialogToPreview()
        end)
    end

    editModeDialogHooked = true
end

local function RefreshLiveNameplates()
    local active = RefineUI.ActiveNameplates
    if type(active) ~= "table" then
        return
    end

    if type(RefineUI.ApplyNameplateSizeSettings) == "function" then
        RefineUI:ApplyNameplateSizeSettings(true)
    end

    local config = GetNameplatesConfig()

    for nameplate in pairs(active) do
        local unitFrame = nameplate and nameplate.UnitFrame
        if unitFrame then
            local unitToken = unitFrame.unit
            if type(unitToken) ~= "string" or (issecretvalue and issecretvalue(unitToken)) then
                unitToken = nil
            end

            Nameplates:ApplyConfiguredNameplateSize(unitFrame)

            if config.TargetIndicator ~= false and type(RefineUI.CreateTargetArrows) == "function" then
                RefineUI:CreateTargetArrows(unitFrame)
            end
            if type(RefineUI.UpdateTarget) == "function" then
                RefineUI:UpdateTarget(unitFrame)
            end

            -- Re-run the live cast bar's own layout and coloring; painting a fixed color here
            -- would override the real cast's interruptibility color.
            local castBar = RefineUI.NameplatesUtil.GetNameplateCastBar(unitFrame)
            if castBar then
                Nameplates:RefreshCastBarForRuntimeMode(castBar)
            end

            if type(RefineUI.UpdateNameplateCrowdControl) == "function" then
                RefineUI:UpdateNameplateCrowdControl(unitFrame, unitToken, "EDIT_MODE_SETTINGS")
            end
            if type(RefineUI.UpdateBorderColors) == "function" then
                RefineUI:UpdateBorderColors(unitFrame)
            end
            if type(RefineUI.UpdateDynamicPortrait) == "function" and unitToken then
                RefineUI:UpdateDynamicPortrait(nameplate, unitToken, "EDIT_MODE_SETTINGS")
            end
        end
    end

    if type(RefineUI.RefreshAllNameplateTextScales) == "function" then
        RefineUI:RefreshAllNameplateTextScales("EDIT_MODE_SETTINGS")
    end

    if type(RefineUI.ApplyNameplateThreatDisplaySettings) == "function" then
        RefineUI:ApplyNameplateThreatDisplaySettings()
    elseif type(RefineUI.RefreshNameplateThreatColors) == "function" then
        RefineUI:RefreshNameplateThreatColors(true)
    end

    if type(RefineUI.RefreshAllNameplateAuraAnchors) == "function" then
        RefineUI:RefreshAllNameplateAuraAnchors("EDIT_MODE_SETTINGS")
    end
end

-- Enemy aura lists grow outward from the health bar corners; spacing is a visual inset
-- per item, matching Nameplates:SkinNamePlateAura.
local function LayoutPreviewAuras(auras, health, point, relativePoint, x, y, size, step, spacing)
    local inset = max(0, RefineUI:Scale(spacing) * 0.5)
    for i = 1, #auras do
        local aura = auras[i]
        aura:SetSize(size, size)
        aura:ClearAllPoints()
        aura:SetPoint(point, health, relativePoint, x + ((i - 1) * step), y)
        RefineUI.SetInside(aura.Icon, aura, 1 + inset, 1 + inset)
        RefineUI.CreateBorder(aura, 6 - inset, 6 - inset, 14)
    end
end

local function RefreshPreviewFrame()
    local frame = editModeFrame
    if not frame then
        return
    end

    local config = GetNameplatesConfig()
    local castConfig = config.CastBar or {}
    local castColors = castConfig.Colors or {}
    local threatConfig = config.Threat or {}
    local ccConfig = config.CrowdControl or {}
    local auraConfig = config.EnemyAuras
    local reactionColors = (RefineUI.Colors and RefineUI.Colors.Reaction) or {}
    local hostileReaction = reactionColors[2] or reactionColors[1] or { r = 1, g = 0.25, b = 0.25 }
    local friendlyReaction = reactionColors[5] or { r = 0.25, g = 1, b = 0.25 }
    local borderColor = config.TargetBorderColor or { 0.8, 0.8, 0.8 }
    local defaultBorderColor = (Config.General and Config.General.BorderColor) or { 0.35, 0.35, 0.35 }
    local threatWarningColor = threatConfig.WarningColor or DEFAULT_THREAT_COLORS.WarningColor
    local threatEnabled = threatConfig.Enable ~= false
    local ccEnabled = ccConfig.Enable ~= false
    local showNpcTitles = config.ShowNPCTitles ~= false
    local targetIndicator = config.TargetIndicator ~= false
    local ccColor = ccConfig.Color or DEFAULT_CC_COLORS.Color

    local state = frame.previewState
    if state == PREVIEW_STATE_CC and not ccEnabled then
        state = PREVIEW_STATE_IDLE
    end
    local isCasting = state == PREVIEW_STATE_CAST or state == PREVIEW_STATE_CAST_LOCKED
    local castColor = castColors.Interruptible or DEFAULT_CAST_COLORS.Interruptible
    if state == PREVIEW_STATE_CAST_LOCKED then
        castColor = castColors.NonInterruptible or DEFAULT_CAST_COLORS.NonInterruptible
    end

    local scale = ClampNumber(config.Scale, NAMEPLATE_SCALE_MIN, NAMEPLATE_SCALE_MAX, DEFAULT_TEXT_SCALE)
    local plateWidth = RefineUI:Scale(DEFAULT_PLATE_SIZE[1] * scale)
    local plateHeight = RefineUI:Scale(DEFAULT_PLATE_SIZE[2] * scale)
    local castHeight = RefineUI:Scale(ClampNumber(castConfig.Height, 8, 48, 20))
    local portraitSize = RefineUI:Scale(PREVIEW_PORTRAIT_BASE_SIZE * scale)
    local arrowSize = RefineUI:Scale(PREVIEW_ARROW_SIZE)
    local auraSize = RefineUI:Scale(PREVIEW_AURA_SIZE)
    local padding = RefineUI:Scale(PREVIEW_PADDING)
    local friendlyGap = RefineUI:Scale(PREVIEW_FRIENDLY_GAP)
    local nameFontSize = max(1, floor((PREVIEW_NAME_FONT_SIZE * scale) + 0.5))
    local healthFontSize = max(1, floor((PREVIEW_HEALTH_FONT_SIZE * scale) + 0.5))

    local borderR = ClampNumber(borderColor[1], 0, 1, 0.8)
    local borderG = ClampNumber(borderColor[2], 0, 1, 0.8)
    local borderB = ClampNumber(borderColor[3], 0, 1, 0.8)
    local plateBorderR, plateBorderG, plateBorderB = borderR, borderG, borderB
    if not targetIndicator then
        plateBorderR = ClampNumber(defaultBorderColor[1], 0, 1, 0.35)
        plateBorderG = ClampNumber(defaultBorderColor[2], 0, 1, 0.35)
        plateBorderB = ClampNumber(defaultBorderColor[3], 0, 1, 0.35)
    end
    local castR = ClampNumber(castColor[1], 0, 1, 1)
    local castG = ClampNumber(castColor[2], 0, 1, 0.7)
    local castB = ClampNumber(castColor[3], 0, 1, 0)
    local threatR = ClampNumber(hostileReaction.r or hostileReaction[1], 0, 1, 1)
    local threatG = ClampNumber(hostileReaction.g or hostileReaction[2], 0, 1, 0.25)
    local threatB = ClampNumber(hostileReaction.b or hostileReaction[3], 0, 1, 0.25)
    if threatEnabled then
        threatR = ClampNumber(threatWarningColor[1], 0, 1, 1)
        threatG = ClampNumber(threatWarningColor[2], 0, 1, 0)
        threatB = ClampNumber(threatWarningColor[3], 0, 1, 0)
    end
    local ccR = ClampNumber(ccColor[1], 0, 1, 0.2)
    local ccG = ClampNumber(ccColor[2], 0, 1, 0.6)
    local ccB = ClampNumber(ccColor[3], 0, 1, 1.0)

    local health = frame.Health
    health:SetSize(plateWidth, plateHeight)
    health:SetStatusBarColor(threatR, threatG, threatB)
    health.border:SetBackdropBorderColor(plateBorderR, plateBorderG, plateBorderB, 1)
    RefineUI.Font(frame.HealthText, healthFontSize, nil, "OUTLINE")

    RefineUI.Font(frame.NameText, nameFontSize)
    if threatEnabled then
        frame.NameText:SetTextColor(threatR, threatG, threatB)
    else
        frame.NameText:SetTextColor(1, 1, 1)
    end

    -- Portrait: cast icon > CC icon > unit portrait, border colored to match (Portrait.lua).
    local portraitR, portraitG, portraitB = plateBorderR, plateBorderG, plateBorderB
    if isCasting then
        frame.PortraitIcon:SetTexture(PREVIEW_CAST_ICON)
        portraitR, portraitG, portraitB = castR, castG, castB
    elseif state == PREVIEW_STATE_CC then
        frame.PortraitIcon:SetTexture(PREVIEW_CC_ICON)
        portraitR, portraitG, portraitB = ccR, ccG, ccB
    else
        SetPreviewPortraitTexture(frame.Portrait)
    end
    frame.PortraitFrame:SetSize(portraitSize, portraitSize)
    frame.PortraitIcon:SetShown(state ~= PREVIEW_STATE_IDLE)
    frame.Portrait:SetShown(state == PREVIEW_STATE_IDLE)
    frame.PortraitBorder:SetVertexColor(portraitR, portraitG, portraitB)

    frame.TargetArrow:SetSize(arrowSize, arrowSize)
    frame.TargetArrow:SetVertexColor(borderR, borderG, borderB)
    frame.TargetArrow:SetShown(targetIndicator)

    local castBar = frame.CastBar
    castBar:SetHeight(castHeight)
    castBar:SetStatusBarColor(castR, castG, castB)
    castBar.border:SetBackdropBorderColor(castR, castG, castB, 1)
    frame.CastBarBG:SetVertexColor(castR * 0.24, castG * 0.24, castB * 0.24, 0.95)
    castBar:SetShown(isCasting)

    local ccBar = frame.CrowdControlBar
    ccBar:SetStatusBarColor(ccR, ccG, ccB)
    ccBar.border:SetBackdropBorderColor(ccR, ccG, ccB, 1)
    frame.CrowdControlBG:SetVertexColor(ccR * 0.25, ccG * 0.25, ccB * 0.25, 1)
    ccBar:SetShown(state == PREVIEW_STATE_CC)

    RefineUI.Font(frame.FriendlyName, nameFontSize)
    frame.FriendlyName:SetTextColor(
        ClampNumber(friendlyReaction.r or friendlyReaction[1], 0, 1, 0.25),
        ClampNumber(friendlyReaction.g or friendlyReaction[2], 0, 1, 1),
        ClampNumber(friendlyReaction.b or friendlyReaction[3], 0, 1, 0.25)
    )
    frame.FriendlyTitle:SetShown(showNpcTitles)

    local nameHeight = frame.NameText:GetStringHeight()
    local baseY = nameHeight + RefineUI:Scale(auraConfig.BaseOffsetY)
    local debuffY = baseY + RefineUI:Scale(auraConfig.DebuffOffsetY)
    local buffY = baseY + RefineUI:Scale(auraConfig.BuffOffsetY)
    LayoutPreviewAuras(frame.Debuffs, health, "BOTTOMLEFT", "TOPLEFT",
        RefineUI:Scale(auraConfig.DebuffOffsetX), debuffY, auraSize, auraSize, auraConfig.DebuffSpacing)
    LayoutPreviewAuras(frame.Buffs, health, "BOTTOMRIGHT", "TOPRIGHT",
        RefineUI:Scale(auraConfig.BuffOffsetX), buffY, auraSize, -auraSize, auraConfig.BuffSpacing)

    -- Size the Edit Mode box around everything the plate can draw.
    local portraitOverhang = (portraitSize - plateHeight) * 0.5
    local topExtent = max(nameHeight + RefineUI:Scale(4), max(debuffY, buffY) + auraSize, portraitOverhang)
    local bottomExtent = max(castHeight - RefineUI:Scale(4), portraitOverhang)
    local sideExtent = max(portraitSize - RefineUI:Scale(8), RefineUI:Scale(4) + arrowSize)
    local friendlyHeight = friendlyGap + frame.FriendlyName:GetStringHeight()
    if showNpcTitles then
        friendlyHeight = friendlyHeight + RefineUI:Scale(1) + frame.FriendlyTitle:GetStringHeight()
    end

    frame:SetSize(
        plateWidth + ((sideExtent + padding) * 2),
        topExtent + plateHeight + bottomExtent + friendlyHeight + (padding * 2)
    )
    health:SetPoint("TOP", frame, "TOP", 0, -(padding + topExtent))
    frame.FriendlyName:SetPoint("TOP", health, "BOTTOM", 0, -(bottomExtent + friendlyGap))
end

local function AdvancePreviewState(frame, elapsed)
    frame.previewElapsed = frame.previewElapsed + elapsed
    if frame.previewElapsed < PREVIEW_STATE_SECONDS then
        return
    end
    frame.previewElapsed = 0

    local state = frame.previewState + 1
    if state == PREVIEW_STATE_CC and GetNameplatesConfig().CrowdControl.Enable == false then
        state = state + 1
    end
    if state > PREVIEW_STATE_IDLE then
        state = PREVIEW_STATE_CAST
    end
    frame.previewState = state
    RefreshPreviewFrame()
end

local function CreatePreviewAura(parent, level, texture, r, g, b)
    local aura = CreateFrame("Frame", nil, parent)
    aura:SetFrameLevel(level)

    local icon = aura:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(texture)
    icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    aura.Icon = icon

    RefineUI.CreateBorder(aura, 6, 6, 14)
    aura.border:SetBackdropBorderColor(r, g, b, 1)
    return aura
end

local function EnsureEditModeFrame()
    if editModeFrame then
        return editModeFrame
    end

    local frame = CreateFrame("Frame", EDITMODE_FRAME_NAME, UIParent)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetScript("OnMouseDown", function(self)
        SelectPreviewFrame(self)
    end)
    frame:Hide()
    ApplyStoredAnchor(frame)
    frame.previewState = PREVIEW_STATE_CAST
    frame.previewElapsed = 0
    -- Cycles cast / uninterruptible cast / CC / idle; runs only while the preview is shown.
    frame:SetScript("OnUpdate", AdvancePreviewState)

    -- Frame levels mirror the live plate: cast and CC bars tuck under the health bar,
    -- auras and the portrait sit above it.
    local level = frame:GetFrameLevel()
    local barTexture = RefineUI.Media.Textures.HealthBar

    local health = CreateFrame("StatusBar", nil, frame)
    health:SetFrameLevel(level + 5)
    health:SetStatusBarTexture(barTexture)
    health:SetStatusBarDesaturated(true)
    health:SetMinMaxValues(0, 100)
    health:SetValue(67)
    RefineUI.CreateBorder(health, 6, 6, 12)
    frame.Health = health

    local healthBG = health:CreateTexture(nil, "BACKGROUND")
    healthBG:SetAllPoints()
    healthBG:SetTexture(barTexture)
    healthBG:SetVertexColor(0.25, 0.25, 0.25, 1)

    local healthText = health.border:CreateFontString(nil, "OVERLAY")
    RefineUI.Font(healthText, PREVIEW_HEALTH_FONT_SIZE, nil, "OUTLINE")
    RefineUI.Point(healthText, "CENTER", health, "CENTER", 0, -2)
    healthText:SetText("67")
    frame.HealthText = healthText

    local nameText = frame:CreateFontString(nil, "OVERLAY")
    RefineUI.Font(nameText, PREVIEW_NAME_FONT_SIZE)
    RefineUI.Point(nameText, "BOTTOM", health, "TOP", 0, 4)
    nameText:SetText("Raging Marauder")
    frame.NameText = nameText

    local portraitFrame = CreateFrame("Frame", nil, health)
    portraitFrame:SetFrameLevel(level + 16)
    RefineUI.Point(portraitFrame, "RIGHT", health, "LEFT", 8, 0)
    frame.PortraitFrame = portraitFrame

    local mask = portraitFrame:CreateMaskTexture()
    mask:SetTexture(RefineUI.Media.Textures.PortraitMask)
    RefineUI.SetInside(mask, portraitFrame, 0, 0)

    local portrait = portraitFrame:CreateTexture(nil, "ARTWORK")
    RefineUI.SetInside(portrait, portraitFrame, 0, 0)
    portrait:AddMaskTexture(mask)
    frame.Portrait = portrait

    local portraitIcon = portraitFrame:CreateTexture(nil, "ARTWORK", nil, 1)
    RefineUI.SetInside(portraitIcon, portraitFrame, 0, 0)
    portraitIcon:AddMaskTexture(mask)
    frame.PortraitIcon = portraitIcon

    local portraitBG = portraitFrame:CreateTexture(nil, "BACKGROUND")
    portraitBG:SetTexture(RefineUI.Media.Textures.PortraitBG)
    RefineUI.SetInside(portraitBG, portraitFrame, 0, 0)
    portraitBG:AddMaskTexture(mask)

    local portraitBorder = portraitFrame:CreateTexture(nil, "OVERLAY")
    portraitBorder:SetTexture(RefineUI.Media.Textures.PortraitBorder)
    RefineUI.SetOutside(portraitBorder, portraitFrame)
    frame.PortraitBorder = portraitBorder

    -- Non-name-only plates show only the right arrow (Targeting.lua).
    local targetArrow = health:CreateTexture(nil, "OVERLAY")
    targetArrow:SetTexture(RefineUI.Media.Textures.TargetArrowRight)
    RefineUI.Point(targetArrow, "LEFT", health, "RIGHT", 4, 0)
    frame.TargetArrow = targetArrow

    local castBar = CreateFrame("StatusBar", nil, frame)
    castBar:SetFrameLevel(level + 1)
    RefineUI.Point(castBar, "TOPLEFT", health, "BOTTOMLEFT", 0, 4)
    RefineUI.Point(castBar, "TOPRIGHT", health, "BOTTOMRIGHT", 0, 4)
    castBar:SetStatusBarTexture(barTexture)
    castBar:SetStatusBarDesaturated(true)
    castBar:SetMinMaxValues(0, 100)
    castBar:SetValue(48)
    RefineUI.CreateBorder(castBar, 6, 6, 12)
    frame.CastBar = castBar

    local castBarBG = castBar:CreateTexture(nil, "BACKGROUND")
    castBarBG:SetAllPoints()
    castBarBG:SetTexture(barTexture)
    frame.CastBarBG = castBarBG

    local castText = castBar:CreateFontString(nil, "OVERLAY")
    RefineUI.Font(castText, 10, nil, "OUTLINE")
    RefineUI.Point(castText, "BOTTOMLEFT", castBar, "BOTTOMLEFT", 4, 0)
    castText:SetText("Shadow Bolt")

    local castTime = castBar:CreateFontString(nil, "OVERLAY")
    RefineUI.Font(castTime, 12, nil, "OUTLINE")
    RefineUI.Point(castTime, "BOTTOMRIGHT", castBar, "BOTTOMRIGHT", -2, 0)
    castTime:SetText("1.4")

    -- The CC bar occupies the cast bar's rect (CrowdControl.lua).
    local crowdControlBar = CreateFrame("StatusBar", nil, frame)
    crowdControlBar:SetFrameLevel(level + 3)
    crowdControlBar:SetAllPoints(castBar)
    crowdControlBar:SetStatusBarTexture(barTexture)
    crowdControlBar:SetStatusBarDesaturated(true)
    crowdControlBar:SetMinMaxValues(0, 100)
    crowdControlBar:SetValue(74)
    RefineUI.CreateBorder(crowdControlBar, 6, 6, 12)
    frame.CrowdControlBar = crowdControlBar

    local crowdControlBG = crowdControlBar:CreateTexture(nil, "BACKGROUND")
    crowdControlBG:SetAllPoints()
    crowdControlBG:SetTexture(barTexture)
    frame.CrowdControlBG = crowdControlBG

    local crowdControlText = crowdControlBar:CreateFontString(nil, "OVERLAY")
    RefineUI.Font(crowdControlText, 10, nil, "OUTLINE")
    RefineUI.Point(crowdControlText, "BOTTOMLEFT", crowdControlBar, "BOTTOMLEFT", 4, 0)
    crowdControlText:SetText("Polymorph")

    local crowdControlTime = crowdControlBar:CreateFontString(nil, "OVERLAY")
    RefineUI.Font(crowdControlTime, 12, nil, "OUTLINE")
    RefineUI.Point(crowdControlTime, "BOTTOMRIGHT", crowdControlBar, "BOTTOMRIGHT", -2, 0)
    crowdControlTime:SetText("3.2")

    local defaultBorderColor = (Config.General and Config.General.BorderColor) or { 0.35, 0.35, 0.35 }
    local debuffs, buffs = {}, {}
    for i = 1, #PREVIEW_DEBUFF_ICONS do
        debuffs[i] = CreatePreviewAura(frame, level + 7, PREVIEW_DEBUFF_ICONS[i], 0.8, 0.1, 0.1)
    end
    for i = 1, #PREVIEW_BUFF_ICONS do
        buffs[i] = CreatePreviewAura(frame, level + 7, PREVIEW_BUFF_ICONS[i],
            defaultBorderColor[1], defaultBorderColor[2], defaultBorderColor[3])
    end
    frame.Debuffs = debuffs
    frame.Buffs = buffs

    -- NPC titles only render on friendly name-only plates, so preview one below.
    local friendlyName = frame:CreateFontString(nil, "OVERLAY")
    RefineUI.Font(friendlyName, PREVIEW_NAME_FONT_SIZE)
    friendlyName:SetText("Innkeeper Allison")
    frame.FriendlyName = friendlyName

    local friendlyTitle = frame:CreateFontString(nil, "OVERLAY")
    RefineUI.Font(friendlyTitle, 9, nil, "OUTLINE")
    RefineUI.Point(friendlyTitle, "TOP", friendlyName, "BOTTOM", 0, -1)
    friendlyTitle:SetTextColor(0.9, 0.9, 0.9)
    friendlyTitle:SetText("<Innkeeper>")
    frame.FriendlyTitle = friendlyTitle

    editModeFrame = frame
    RefreshPreviewFrame()
    return frame
end

local function ShowPreviewFrame()
    local frame = EnsureEditModeFrame()
    if not frame then
        return
    end

    ApplyStoredAnchor(frame)
    RefreshPreviewFrame()
    frame:Show()
    RefreshThreatSettingAvailability()

    -- If this frame was hidden when Edit Mode entered, force the selection to be
    -- interactive now so clicks open the LibEditMode settings dialog.
    EnsureSelectionInteractive(frame)
end

local function RegisterEditModeSettings()
    if editModeSettingsRegistered or not RefineUI.LibEditMode or not RefineUI.LibEditMode.SettingType then
        return
    end

    local settingType = RefineUI.LibEditMode.SettingType
    local settings = {}

    local function AddDivider(label)
        if not settingType.Divider then
            return
        end
        settings[#settings + 1] = {
            kind = settingType.Divider,
            name = label,
        }
    end

    AddDivider("Sizing")

    settings[#settings + 1] = {
        kind = settingType.Slider,
        name = "Scale",
        default = DEFAULT_TEXT_SCALE,
        minValue = NAMEPLATE_SCALE_MIN,
        maxValue = NAMEPLATE_SCALE_MAX,
        valueStep = NAMEPLATE_SCALE_STEP,
        formatter = FormatNameplateScaleValue,
        get = function()
            return RoundToStep(
                ClampNumber(GetNameplatesConfig().Scale, NAMEPLATE_SCALE_MIN, NAMEPLATE_SCALE_MAX, DEFAULT_TEXT_SCALE),
                NAMEPLATE_SCALE_STEP
            )
        end,
        set = function(_, value)
            local config = GetNameplatesConfig()
            config.Scale = RoundToStep(
                ClampNumber(value, NAMEPLATE_SCALE_MIN, NAMEPLATE_SCALE_MAX, DEFAULT_TEXT_SCALE),
                NAMEPLATE_SCALE_STEP
            )
            RefreshPreviewFrame()
            RefreshLiveNameplates()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.Slider,
        name = "Floating Combat Text",
        default = WORLD_TEXT_SCALE_DEFAULT,
        minValue = WORLD_TEXT_SCALE_MIN,
        maxValue = WORLD_TEXT_SCALE_MAX,
        valueStep = WORLD_TEXT_SCALE_STEP,
        formatter = FormatWorldTextScaleValue,
        get = function()
            return GetConfiguredWorldTextScale()
        end,
        set = function(_, value)
            local scale = RoundToStep(
                ClampNumber(value, WORLD_TEXT_SCALE_MIN, WORLD_TEXT_SCALE_MAX, WORLD_TEXT_SCALE_DEFAULT),
                WORLD_TEXT_SCALE_STEP
            )
            SetCVar(WORLD_TEXT_SCALE_CVAR, scale)
        end,
    }

    AddDivider("Target")

    settings[#settings + 1] = {
        kind = settingType.Checkbox,
        name = "Target Indicator",
        default = true,
        get = function()
            return GetNameplatesConfig().TargetIndicator ~= false
        end,
        set = function(_, value)
            local config = GetNameplatesConfig()
            config.TargetIndicator = value and true or false
            RefreshPreviewFrame()
            RefreshLiveNameplates()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.Checkbox,
        name = "Show NPC Titles",
        default = true,
        get = function()
            return GetNameplatesConfig().ShowNPCTitles ~= false
        end,
        set = function(_, value)
            local config = GetNameplatesConfig()
            config.ShowNPCTitles = value and true or false
            RefreshPreviewFrame()
            RefreshLiveNameplates()
            if type(RefineUI.RefreshAllNameplateNpcTitles) == "function" then
                RefineUI:RefreshAllNameplateNpcTitles("EDIT_MODE_SETTINGS")
            end
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.Checkbox,
        name = "Show Pet Names",
        default = false,
        get = function()
            return GetNameplatesConfig().ShowPetNames == true
        end,
        set = function(_, value)
            local config = GetNameplatesConfig()
            config.ShowPetNames = value and true or false
            RefreshPreviewFrame()
            RefreshLiveNameplates()
            if type(RefineUI.ApplyNameplateCVarSettings) == "function" then
                RefineUI:ApplyNameplateCVarSettings()
            end
        end,
    }

    AddDivider("Enemy Auras")

    settings[#settings + 1] = {
        kind = settingType.Slider,
        name = "Aura Base Y",
        default = DEFAULT_ENEMY_AURA_LAYOUT.BaseOffsetY,
        minValue = -20,
        maxValue = 40,
        valueStep = 1,
        get = function()
            local enemyAuras = GetNameplatesConfig().EnemyAuras
            return ClampNumber(enemyAuras.BaseOffsetY, -20, 40, DEFAULT_ENEMY_AURA_LAYOUT.BaseOffsetY)
        end,
        set = function(_, value)
            local enemyAuras = GetNameplatesConfig().EnemyAuras
            enemyAuras.BaseOffsetY = RoundToStep(ClampNumber(value, -20, 40, DEFAULT_ENEMY_AURA_LAYOUT.BaseOffsetY), 1)
            RefreshPreviewFrame()
            RefreshLiveNameplates()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.Slider,
        name = "Debuff X",
        default = DEFAULT_ENEMY_AURA_LAYOUT.DebuffOffsetX,
        minValue = -80,
        maxValue = 80,
        valueStep = 1,
        get = function()
            local enemyAuras = GetNameplatesConfig().EnemyAuras
            return ClampNumber(enemyAuras.DebuffOffsetX, -80, 80, DEFAULT_ENEMY_AURA_LAYOUT.DebuffOffsetX)
        end,
        set = function(_, value)
            local enemyAuras = GetNameplatesConfig().EnemyAuras
            enemyAuras.DebuffOffsetX = RoundToStep(ClampNumber(value, -80, 80, DEFAULT_ENEMY_AURA_LAYOUT.DebuffOffsetX), 1)
            RefreshPreviewFrame()
            RefreshLiveNameplates()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.Slider,
        name = "Debuff Y",
        default = DEFAULT_ENEMY_AURA_LAYOUT.DebuffOffsetY,
        minValue = -40,
        maxValue = 80,
        valueStep = 1,
        get = function()
            local enemyAuras = GetNameplatesConfig().EnemyAuras
            return ClampNumber(enemyAuras.DebuffOffsetY, -40, 80, DEFAULT_ENEMY_AURA_LAYOUT.DebuffOffsetY)
        end,
        set = function(_, value)
            local enemyAuras = GetNameplatesConfig().EnemyAuras
            enemyAuras.DebuffOffsetY = RoundToStep(ClampNumber(value, -40, 80, DEFAULT_ENEMY_AURA_LAYOUT.DebuffOffsetY), 1)
            RefreshPreviewFrame()
            RefreshLiveNameplates()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.Slider,
        name = "Buff X",
        default = DEFAULT_ENEMY_AURA_LAYOUT.BuffOffsetX,
        minValue = -80,
        maxValue = 80,
        valueStep = 1,
        get = function()
            local enemyAuras = GetNameplatesConfig().EnemyAuras
            return ClampNumber(enemyAuras.BuffOffsetX, -80, 80, DEFAULT_ENEMY_AURA_LAYOUT.BuffOffsetX)
        end,
        set = function(_, value)
            local enemyAuras = GetNameplatesConfig().EnemyAuras
            enemyAuras.BuffOffsetX = RoundToStep(ClampNumber(value, -80, 80, DEFAULT_ENEMY_AURA_LAYOUT.BuffOffsetX), 1)
            RefreshPreviewFrame()
            RefreshLiveNameplates()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.Slider,
        name = "Buff Y",
        default = DEFAULT_ENEMY_AURA_LAYOUT.BuffOffsetY,
        minValue = -40,
        maxValue = 80,
        valueStep = 1,
        get = function()
            local enemyAuras = GetNameplatesConfig().EnemyAuras
            return ClampNumber(enemyAuras.BuffOffsetY, -40, 80, DEFAULT_ENEMY_AURA_LAYOUT.BuffOffsetY)
        end,
        set = function(_, value)
            local enemyAuras = GetNameplatesConfig().EnemyAuras
            enemyAuras.BuffOffsetY = RoundToStep(ClampNumber(value, -40, 80, DEFAULT_ENEMY_AURA_LAYOUT.BuffOffsetY), 1)
            RefreshPreviewFrame()
            RefreshLiveNameplates()
        end,
    }

    AddDivider("Cast Colors")

    settings[#settings + 1] = {
        kind = settingType.ColorPicker,
        name = "Interruptible",
        default = ColorTableToMixin(DEFAULT_CAST_COLORS.Interruptible, DEFAULT_CAST_COLORS.Interruptible),
        get = function()
            local castColors = GetNameplatesConfig().CastBar.Colors
            return ColorTableToMixin(castColors.Interruptible, DEFAULT_CAST_COLORS.Interruptible)
        end,
        set = function(_, value)
            local castColors = GetNameplatesConfig().CastBar.Colors
            SaveColorMixinToTable(castColors.Interruptible, value)
            if type(RefineUI.RefreshNameplateCastColors) == "function" then
                RefineUI:RefreshNameplateCastColors(true)
            end
            RefreshPreviewFrame()
            RefreshLiveNameplates()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.ColorPicker,
        name = "Non-Interruptible",
        default = ColorTableToMixin(DEFAULT_CAST_COLORS.NonInterruptible, DEFAULT_CAST_COLORS.NonInterruptible),
        get = function()
            local castColors = GetNameplatesConfig().CastBar.Colors
            return ColorTableToMixin(castColors.NonInterruptible, DEFAULT_CAST_COLORS.NonInterruptible)
        end,
        set = function(_, value)
            local castColors = GetNameplatesConfig().CastBar.Colors
            SaveColorMixinToTable(castColors.NonInterruptible, value)
            if type(RefineUI.RefreshNameplateCastColors) == "function" then
                RefineUI:RefreshNameplateCastColors(true)
            end
            RefreshPreviewFrame()
            RefreshLiveNameplates()
        end,
    }

    AddDivider("Threat Display")

    settings[#settings + 1] = {
        kind = settingType.Checkbox,
        name = THREAT_SETTING_ENABLE,
        default = true,
        get = function()
            return GetNameplatesConfig().Threat.Enable ~= false
        end,
        set = function(_, value)
            local threat = GetNameplatesConfig().Threat
            threat.Enable = value and true or false
            RefreshThreatSettingAvailability()
            local dialog = GetEditModeDialog()
            if dialog and dialog.IsShown and dialog:IsShown() and IsSettingsDialogForNameplates(dialog.selection) then
                dialog:Update(dialog.selection)
            end
            RefreshPreviewFrame()
            RefreshLiveNameplates()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.Checkbox,
        name = THREAT_SETTING_INSTANCE_ONLY,
        default = false,
        get = function()
            local threat = GetNameplatesConfig().Threat
            return threat.InstanceOnly == true
        end,
        set = function(_, value)
            local threat = GetNameplatesConfig().Threat
            threat.InstanceOnly = value and true or false
            RefreshPreviewFrame()
            RefreshLiveNameplates()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.ColorPicker,
        name = THREAT_SETTING_SAFE,
        default = ColorTableToMixin(DEFAULT_THREAT_COLORS.SafeColor, DEFAULT_THREAT_COLORS.SafeColor),
        get = function()
            local threat = GetNameplatesConfig().Threat
            return ColorTableToMixin(threat.SafeColor, DEFAULT_THREAT_COLORS.SafeColor)
        end,
        set = function(_, value)
            local threat = GetNameplatesConfig().Threat
            SaveColorMixinToTable(threat.SafeColor, value)
            RefreshPreviewFrame()
            RefreshLiveNameplates()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.ColorPicker,
        name = THREAT_SETTING_TRANSITION,
        default = ColorTableToMixin(DEFAULT_THREAT_COLORS.TransitionColor, DEFAULT_THREAT_COLORS.TransitionColor),
        get = function()
            local threat = GetNameplatesConfig().Threat
            return ColorTableToMixin(threat.TransitionColor, DEFAULT_THREAT_COLORS.TransitionColor)
        end,
        set = function(_, value)
            local threat = GetNameplatesConfig().Threat
            SaveColorMixinToTable(threat.TransitionColor, value)
            RefreshPreviewFrame()
            RefreshLiveNameplates()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.ColorPicker,
        name = THREAT_SETTING_WARNING,
        default = ColorTableToMixin(DEFAULT_THREAT_COLORS.WarningColor, DEFAULT_THREAT_COLORS.WarningColor),
        get = function()
            local threat = GetNameplatesConfig().Threat
            return ColorTableToMixin(threat.WarningColor, DEFAULT_THREAT_COLORS.WarningColor)
        end,
        set = function(_, value)
            local threat = GetNameplatesConfig().Threat
            SaveColorMixinToTable(threat.WarningColor, value)
            RefreshPreviewFrame()
            RefreshLiveNameplates()
        end,
    }

    AddDivider("Crowd Control")

    settings[#settings + 1] = {
        kind = settingType.Checkbox,
        name = "CC Bar",
        default = true,
        get = function()
            return GetNameplatesConfig().CrowdControl.Enable ~= false
        end,
        set = function(_, value)
            local cc = GetNameplatesConfig().CrowdControl
            cc.Enable = value and true or false
            RefreshPreviewFrame()
            RefreshLiveNameplates()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.ColorPicker,
        name = "CC Color",
        default = ColorTableToMixin(DEFAULT_CC_COLORS.Color, DEFAULT_CC_COLORS.Color),
        get = function()
            local cc = GetNameplatesConfig().CrowdControl
            return ColorTableToMixin(cc.Color, DEFAULT_CC_COLORS.Color)
        end,
        set = function(_, value)
            local cc = GetNameplatesConfig().CrowdControl
            SaveColorMixinToTable(cc.Color, value)
            SaveColorMixinToTable(cc.BorderColor, value)
            RefreshPreviewFrame()
            RefreshLiveNameplates()
        end,
    }

    AddDivider("Alpha")

    settings[#settings + 1] = {
        kind = settingType.Slider,
        name = "Non-Target Alpha",
        default = 0.5,
        minValue = 0.1,
        maxValue = 1,
        valueStep = 0.05,
        get = function()
            return ClampNumber(GetNameplatesConfig().Alpha, 0.1, 1, 0.5)
        end,
        set = function(_, value)
            local alpha = RoundToStep(ClampNumber(value, 0.1, 1, 0.5), 0.05)
            local config = GetNameplatesConfig()
            config.Alpha = alpha
            SetCVar("nameplateMinAlpha", alpha)
            RefreshLiveNameplates()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.Slider,
        name = "Casting Non-Target Alpha",
        default = 0.75,
        minValue = 0.1,
        maxValue = 1,
        valueStep = 0.05,
        get = function()
            return ClampNumber(GetNameplatesConfig().CastAlpha, 0.1, 1, 0.75)
        end,
        set = function(_, value)
            local alpha = RoundToStep(ClampNumber(value, 0.1, 1, 0.75), 0.05)
            local config = GetNameplatesConfig()
            config.CastAlpha = alpha
            RefreshLiveNameplates()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.Slider,
        name = "No Target Alpha",
        default = 1,
        minValue = 0.1,
        maxValue = 1,
        valueStep = 0.05,
        get = function()
            return ClampNumber(GetNameplatesConfig().NoTargetAlpha, 0.1, 1, 1)
        end,
        set = function(_, value)
            local alpha = RoundToStep(ClampNumber(value, 0.1, 1, 1), 0.05)
            GetNameplatesConfig().NoTargetAlpha = alpha
            RefreshLiveNameplates()
        end,
    }

    editModeSettings = settings
    editModeSettingsRegistered = true
end

function Nameplates:RegisterEditModeFrame()
    if editModeRegistered or not RefineUI.LibEditMode or type(RefineUI.LibEditMode.AddFrame) ~= "function" then
        return
    end

    local frame = EnsureEditModeFrame()
    if not frame then
        return
    end

    local pos = RefineUI.Positions and RefineUI.Positions[EDITMODE_FRAME_NAME]
    local default = {
        point = (pos and pos[1]) or EDITMODE_DEFAULT_POINT,
        x = (pos and pos[4]) or EDITMODE_DEFAULT_X,
        y = (pos and pos[5]) or EDITMODE_DEFAULT_Y,
    }

    RefineUI.LibEditMode:AddFrame(frame, function(mover, _, point, x, y)
        mover:ClearAllPoints()
        mover:SetPoint(point, UIParent, point, x, y)
        ApplyStoredPosition(point, x, y)
    end, default, "Nameplates")
    editModeRegistered = true

    RegisterEditModeSettings()
    if editModeSettings and not editModeSettingsAttached and type(RefineUI.LibEditMode.AddFrameSettings) == "function" then
        RefineUI.LibEditMode:AddFrameSettings(frame, editModeSettings)
        editModeSettingsAttached = true
    end
    RefreshThreatSettingAvailability()

    HookEditModeDialog()
end

function Nameplates:RegisterEditModeCallbacks()
    if editModeCallbacksRegistered or not RefineUI.LibEditMode or type(RefineUI.LibEditMode.RegisterCallback) ~= "function" then
        return
    end

    RefineUI.LibEditMode:RegisterCallback("enter", function()
        ShowPreviewFrame()
    end)
    RefineUI.LibEditMode:RegisterCallback("exit", function()
        if editModeFrame then
            editModeFrame:Hide()
        end
    end)

    if type(RefineUI.LibEditMode.IsInEditMode) == "function" and RefineUI.LibEditMode:IsInEditMode() then
        ShowPreviewFrame()
    end

    editModeCallbacksRegistered = true
end

----------------------------------------------------------------------------------------
-- Blizzard Settings Shields
----------------------------------------------------------------------------------------
-- Blizzard Options rows RefineUI owns, keyed by setting variable. Addon-owned shields cover
-- them on the category page and in search results; Blizzard frames and tables are never
-- modified, and Blizzard dispatches these callbacks securely.
local MANAGED_BLIZZARD_SETTINGS = {
    nameplateSize = "Set by Scale on the RefineUI Nameplates frame in Edit Mode.",
    nameplateDebuffPadding = "Set by the aura sliders on the RefineUI Nameplates frame in Edit Mode.",
    nameplateShowFriendlyPlayers = "RefineUI shows friendly nameplates outside combat and group content.",
    nameplateShowFriendlyPlayerMinions = "RefineUI shows friendly nameplates outside combat and group content.",
    nameplateShowFriendlyNpcs = "RefineUI shows friendly nameplates outside combat and group content.",
    UNIT_NAMEPLATES_THREAT_DISPLAY = "RefineUI colors nameplate health bars by threat.",
    nameplateStyle = "RefineUI nameplates are built on the Block style.",
    UNIT_NAMEPLATES_INFO_DISPLAY = "RefineUI shows its own health text and hides these elements.",
    UNIT_NAMEPLATES_CLASS_COLOR = "RefineUI always class-colors player health bars.",
    nameplateUseClassColorForFriendlyPlayerUnitNames = "RefineUI always class-colors player names.",
}
local SETTINGS_DEFAULTED_TIMER_KEY = "Nameplates:BlizzardSettingsDefaulted"
local settingsShields = {}
local settingsShieldOwner = {}
local settingsShieldsRegistered = false

local function OnSettingsShieldEnter(shield)
    GameTooltip:SetOwner(shield, "ANCHOR_TOP")
    GameTooltip:SetText("Managed by RefineUI")
    GameTooltip:AddLine(shield.managedText, 1, 1, 1, true)
    GameTooltip:Show()
end

local function GetManagedSettingText(elementData)
    local getSetting = elementData and elementData.GetSetting
    local setting = getSetting and getSetting(elementData)
    local variable = setting and setting:GetVariable()
    return variable and MANAGED_BLIZZARD_SETTINGS[variable]
end

local function UpdateSettingsShield(_, frame, elementData)
    local shield = settingsShields[frame]
    local managedText = GetManagedSettingText(elementData)
    if not managedText then
        if shield then
            shield:Hide()
        end
        return
    end

    if not shield then
        shield = CreateFrame("Frame", nil, frame)
        shield:SetAllPoints(frame)
        shield:EnableMouse(true)
        shield:SetScript("OnEnter", OnSettingsShieldEnter)
        shield:SetScript("OnLeave", GameTooltip_Hide)
        local overlay = shield:CreateTexture(nil, "OVERLAY")
        overlay:SetAllPoints()
        overlay:SetColorTexture(0, 0, 0, 0.6)
        local logo = shield:CreateTexture(nil, "OVERLAY", nil, 1)
        logo:SetPoint("LEFT")
        logo:SetTexture(RefineUI.Media.Logo)
        shield.Logo = logo
        settingsShields[frame] = shield
    end

    -- Rows are laid out before OnInitializedFrame, so the height is final here.
    local rowHeight = frame:GetHeight()
    shield.Logo:SetSize(rowHeight, rowHeight)
    shield.managedText = managedText
    shield:SetFrameLevel(frame:GetFrameLevel() + 20)
    shield:Show()
end

local function HideSettingsShield(_, frame)
    local shield = settingsShields[frame]
    if shield then
        shield:Hide()
    end
end

local function ReapplyManagedBlizzardSettings()
    Nameplates:ApplyPinnedNameplateStyle()
    Nameplates:UpdateNameplateCVars(true)
    Nameplates:ApplyConfiguredBlizzardNameplateSize(true)
end

-- Defaults buttons still reset the covered settings; restore RefineUI's values afterwards.
local function OnBlizzardSettingsDefaulted()
    RefineUI:After(SETTINGS_DEFAULTED_TIMER_KEY, 0, ReapplyManagedBlizzardSettings)
end

function Nameplates:RegisterBlizzardSettingsShields()
    if settingsShieldsRegistered then
        return
    end

    local scrollBox = SettingsPanel:GetSettingsList().ScrollBox
    ScrollUtil.AddInitializedFrameCallback(scrollBox, UpdateSettingsShield, settingsShieldOwner)
    ScrollUtil.AddReleasedFrameCallback(scrollBox, HideSettingsShield, settingsShieldOwner)
    EventRegistry:RegisterCallback("Settings.CategoryDefaulted", OnBlizzardSettingsDefaulted, settingsShieldOwner)
    EventRegistry:RegisterCallback("Settings.Defaulted", OnBlizzardSettingsDefaulted, settingsShieldOwner)

    settingsShieldsRegistered = true
end
