----------------------------------------------------------------------------------------
-- Nameplates Edit Mode for RefineUI
-- Description: Adds a fake test nameplate and Nameplates settings to Edit Mode.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Nameplates = RefineUI:GetModule("Nameplates")
local C = RefineUI.Config

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local _G = _G
local floor = math.floor
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
local SetCVar = SetCVar
local UIParent = UIParent
local SetPortraitTexture = SetPortraitTexture
local UnitExists = UnitExists
local UnitCanAttack = UnitCanAttack
local hooksecurefunc = hooksecurefunc

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
        C and C.Nameplates and C.Nameplates.CastBar and C.Nameplates.CastBar.Colors and C.Nameplates.CastBar.Colors.Interruptible,
        { 1, 0.7, 0 }
    ),
    NonInterruptible = ResolveDefaultColor(
        C and C.Nameplates and C.Nameplates.CastBar and C.Nameplates.CastBar.Colors and C.Nameplates.CastBar.Colors.NonInterruptible,
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
local DEFAULT_TEXT_SCALE = 1
local DEFAULT_DYNAMIC_PORTRAIT_SCALE = 1
local NAMEPLATE_TEXT_SCALE_MIN = 0.5
local NAMEPLATE_TEXT_SCALE_MAX = 2.0
local NAMEPLATE_SCALE_STEP = 0.1
local PREVIEW_NAME_FONT_SIZE = 12
local PREVIEW_HEALTH_FONT_SIZE = 14
local PREVIEW_PORTRAIT_BASE_SIZE = 36
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

local function FormatScaleValue(value)
    local rounded = RoundToStep(
        ClampNumber(value, NAMEPLATE_TEXT_SCALE_MIN, NAMEPLATE_TEXT_SCALE_MAX, DEFAULT_TEXT_SCALE),
        NAMEPLATE_SCALE_STEP
    )
    return format("%.1f", rounded)
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
    if not C.Nameplates then
        C.Nameplates = {}
    end
    if not C.Nameplates.CastBar then
        C.Nameplates.CastBar = {}
    end
    if not C.Nameplates.CastBar.Colors then
        C.Nameplates.CastBar.Colors = {}
    end
    if not C.Nameplates.Size then
        C.Nameplates.Size = { DEFAULT_PLATE_SIZE[1], DEFAULT_PLATE_SIZE[2] }
    end
    if not C.Nameplates.Threat then
        C.Nameplates.Threat = {}
    end
    if not C.Nameplates.CrowdControl then
        C.Nameplates.CrowdControl = {}
    end
    if C.Nameplates.ShowNPCTitles == nil then
        C.Nameplates.ShowNPCTitles = true
    end
    if C.Nameplates.ShowPetNames == nil then
        C.Nameplates.ShowPetNames = false
    end
    C.Nameplates.UnitNameScale = RoundToStep(
        ClampNumber(
            C.Nameplates.UnitNameScale,
            NAMEPLATE_TEXT_SCALE_MIN,
            NAMEPLATE_TEXT_SCALE_MAX,
            DEFAULT_TEXT_SCALE
        ),
        NAMEPLATE_SCALE_STEP
    )
    C.Nameplates.HealthTextScale = RoundToStep(
        ClampNumber(
            C.Nameplates.HealthTextScale,
            NAMEPLATE_TEXT_SCALE_MIN,
            NAMEPLATE_TEXT_SCALE_MAX,
            DEFAULT_TEXT_SCALE
        ),
        NAMEPLATE_SCALE_STEP
    )
    C.Nameplates.DynamicPortraitScale = RoundToStep(
        ClampNumber(
            C.Nameplates.DynamicPortraitScale,
            NAMEPLATE_TEXT_SCALE_MIN,
            NAMEPLATE_TEXT_SCALE_MAX,
            DEFAULT_DYNAMIC_PORTRAIT_SCALE
        ),
        NAMEPLATE_SCALE_STEP
    )

    local castColors = C.Nameplates.CastBar.Colors
    EnsureColorTable(castColors, "Interruptible", DEFAULT_CAST_COLORS.Interruptible)
    EnsureColorTable(castColors, "NonInterruptible", DEFAULT_CAST_COLORS.NonInterruptible)

    local threat = C.Nameplates.Threat
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

    local crowdControl = C.Nameplates.CrowdControl
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

    return C.Nameplates
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
    RefineUI.Positions = RefineUI.Positions or {}
    RefineUI.Positions[EDITMODE_FRAME_NAME] = { point, "UIParent", point, x, y }
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
    local castConfig = config.CastBar or {}
    local castColors = castConfig.Colors or {}
    local interruptibleColor = castColors.Interruptible or DEFAULT_CAST_COLORS.Interruptible
    local plateWidth = ClampNumber(config.Size and config.Size[1], 120, 320, DEFAULT_PLATE_SIZE[1])
    local plateHeight = ClampNumber(config.Size and config.Size[2], 10, 48, DEFAULT_PLATE_SIZE[2])
    local castHeight = ClampNumber(castConfig.Height, 8, 48, 20)
    local scaledPlateWidth = (type(RefineUI.Scale) == "function" and RefineUI:Scale(plateWidth)) or plateWidth
    local scaledPlateHeight = (type(RefineUI.Scale) == "function" and RefineUI:Scale(plateHeight)) or plateHeight
    local scaledCastHeight = (type(RefineUI.Scale) == "function" and RefineUI:Scale(castHeight)) or castHeight
    local sideInset = (type(RefineUI.Scale) == "function" and RefineUI:Scale(12)) or 12
    local unitFrameWidth = scaledPlateWidth + (sideInset * 2)

    for nameplate in pairs(active) do
        local unitFrame = nameplate and nameplate.UnitFrame
        if unitFrame then
            local unitToken = unitFrame.unit
            if type(unitToken) ~= "string" or (issecretvalue and issecretvalue(unitToken)) then
                unitToken = nil
            end

            if unitFrame.SetWidth then
                unitFrame:SetWidth(unitFrameWidth)
            end

            local healthContainer = unitFrame.HealthBarsContainer
            if healthContainer and healthContainer.SetHeight then
                healthContainer:SetHeight(scaledPlateHeight)
            end

            local health = unitFrame.healthBar or unitFrame.HealthBar
            if health and health.SetHeight then
                health:SetHeight(scaledPlateHeight)
            end

            if config.TargetIndicator ~= false and type(RefineUI.CreateTargetArrows) == "function" then
                RefineUI:CreateTargetArrows(unitFrame)
            end
            if type(RefineUI.UpdateTarget) == "function" then
                RefineUI:UpdateTarget(unitFrame)
            end

            local castBar = unitFrame.castBar or unitFrame.CastBar
            if castBar then
                local hpHeight = healthContainer and healthContainer:GetHeight()
                local safeHeight = 12
                if hpHeight and (not issecretvalue or not issecretvalue(hpHeight)) and hpHeight > 0 then
                    safeHeight = hpHeight
                end

                castBar:ClearAllPoints()
                RefineUI.Point(castBar, "TOPLEFT", unitFrame, "TOPLEFT", 12, -(safeHeight - 4))
                RefineUI.Point(castBar, "TOPRIGHT", unitFrame, "TOPRIGHT", -12, -(safeHeight - 4))
                castBar:SetHeight(scaledCastHeight)

                local castR = ClampNumber(interruptibleColor[1], 0, 1, 1)
                local castG = ClampNumber(interruptibleColor[2], 0, 1, 0.7)
                local castB = ClampNumber(interruptibleColor[3], 0, 1, 0)
                if castBar.SetStatusBarColor then
                    castBar:SetStatusBarColor(castR, castG, castB)
                end
                if castBar.border and castBar.border.SetBackdropBorderColor then
                    castBar.border:SetBackdropBorderColor(castR, castG, castB, 1)
                end
                if castBar.Background and castBar.Background.SetVertexColor then
                    castBar.Background:SetVertexColor(castR * 0.24, castG * 0.24, castB * 0.24, 0.95)
                end
                if castBar.UpdateUnitEvents and unitToken then
                    castBar:UpdateUnitEvents(unitToken)
                end
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
end

local function RefreshPreviewFrame()
    if not editModeFrame then
        return
    end

    local config = GetNameplatesConfig()
    local castConfig = config.CastBar or {}
    local castColors = castConfig.Colors or {}
    local threatConfig = config.Threat or {}
    local ccConfig = config.CrowdControl or {}
    local reactionColors = (RefineUI.Colors and RefineUI.Colors.Reaction) or {}
    local hostileReaction = reactionColors[2] or reactionColors[1] or { r = 1, g = 0.25, b = 0.25 }
    local borderColor = config.TargetBorderColor or { 0.8, 0.8, 0.8 }
    local defaultBorderColor = (C.General and C.General.BorderColor) or { 0.35, 0.35, 0.35 }
    local castColor = castColors.Interruptible or DEFAULT_CAST_COLORS.Interruptible
    local castNonInterruptibleColor = castColors.NonInterruptible or DEFAULT_CAST_COLORS.NonInterruptible
    local threatWarningColor = threatConfig.WarningColor or DEFAULT_THREAT_COLORS.WarningColor
    local threatEnabled = threatConfig.Enable ~= false
    local ccEnabled = ccConfig.Enable ~= false
    local showNpcTitles = config.ShowNPCTitles ~= false
    local ccColor = ccConfig.Color or DEFAULT_CC_COLORS.Color

    local unitNameScale = ClampNumber(config.UnitNameScale, NAMEPLATE_TEXT_SCALE_MIN, NAMEPLATE_TEXT_SCALE_MAX, DEFAULT_TEXT_SCALE)
    local healthTextScale = ClampNumber(config.HealthTextScale, NAMEPLATE_TEXT_SCALE_MIN, NAMEPLATE_TEXT_SCALE_MAX, DEFAULT_TEXT_SCALE)
    local dynamicPortraitScale = ClampNumber(
        config.DynamicPortraitScale,
        NAMEPLATE_TEXT_SCALE_MIN,
        NAMEPLATE_TEXT_SCALE_MAX,
        DEFAULT_DYNAMIC_PORTRAIT_SCALE
    )

    local plateWidth = ClampNumber(config.Size and config.Size[1], 120, 320, DEFAULT_PLATE_SIZE[1])
    local plateHeight = ClampNumber(config.Size and config.Size[2], 10, 48, DEFAULT_PLATE_SIZE[2])
    local castHeight = ClampNumber(castConfig.Height, 8, 48, 20)
    local ccHeight = 10
    local portraitSize = RefineUI:Scale(PREVIEW_PORTRAIT_BASE_SIZE * dynamicPortraitScale)
    local nameFontSize = floor((PREVIEW_NAME_FONT_SIZE * unitNameScale) + 0.5)
    local healthFontSize = floor((PREVIEW_HEALTH_FONT_SIZE * healthTextScale) + 0.5)

    local borderR = ClampNumber(borderColor[1], 0, 1, 0.8)
    local borderG = ClampNumber(borderColor[2], 0, 1, 0.8)
    local borderB = ClampNumber(borderColor[3], 0, 1, 0.8)
    local defaultBorderR = ClampNumber(defaultBorderColor[1], 0, 1, 0.35)
    local defaultBorderG = ClampNumber(defaultBorderColor[2], 0, 1, 0.35)
    local defaultBorderB = ClampNumber(defaultBorderColor[3], 0, 1, 0.35)
    local castR = ClampNumber(castColor[1], 0, 1, 1)
    local castG = ClampNumber(castColor[2], 0, 1, 0.7)
    local castB = ClampNumber(castColor[3], 0, 1, 0)
    local castShieldR = ClampNumber(castNonInterruptibleColor[1], 0, 1, 0.5)
    local castShieldG = ClampNumber(castNonInterruptibleColor[2], 0, 1, 0.5)
    local castShieldB = ClampNumber(castNonInterruptibleColor[3], 0, 1, 0.5)
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
    local ccBorderR = ccR
    local ccBorderG = ccG
    local ccBorderB = ccB

    local extraHeight = ccEnabled and (ccHeight + 10) or 0
    editModeFrame:SetSize(plateWidth + portraitSize + 94, plateHeight + castHeight + 62 + extraHeight)

    if editModeFrame.Plate then
        editModeFrame.Plate:SetSize(plateWidth, plateHeight)
        if editModeFrame.Plate.border and editModeFrame.Plate.border.SetBackdropBorderColor then
            if config.TargetIndicator == false then
                editModeFrame.Plate.border:SetBackdropBorderColor(defaultBorderR, defaultBorderG, defaultBorderB, 1)
            else
                editModeFrame.Plate.border:SetBackdropBorderColor(borderR, borderG, borderB, 1)
            end
        end
    end

    if editModeFrame.Health then
        editModeFrame.Health:SetStatusBarTexture(RefineUI.Media.Textures.HealthBar)
        editModeFrame.Health:SetStatusBarDesaturated(true)
        editModeFrame.Health:SetMinMaxValues(0, 100)
        editModeFrame.Health:SetValue(67)
        editModeFrame.Health:SetStatusBarColor(threatR, threatG, threatB)
    end
    if editModeFrame.HealthBG then
        editModeFrame.HealthBG:SetTexture(RefineUI.Media.Textures.HealthBar)
        editModeFrame.HealthBG:SetVertexColor(0.22, 0.22, 0.22, 0.95)
    end
    if editModeFrame.NameText then
        RefineUI.Font(editModeFrame.NameText, nameFontSize, nil, "OUTLINE")
        editModeFrame.NameText:SetText("Raging Marauder")
        if threatEnabled then
            editModeFrame.NameText:SetTextColor(threatR, threatG, threatB)
        else
            editModeFrame.NameText:SetTextColor(1, 1, 1)
        end
    end
    if editModeFrame.TitleText then
        editModeFrame.TitleText:SetText("<Innkeeper>")
        if showNpcTitles then
            editModeFrame.TitleText:Show()
        else
            editModeFrame.TitleText:Hide()
        end
    end
    if editModeFrame.HealthText then
        RefineUI.Font(editModeFrame.HealthText, healthFontSize, nil, "OUTLINE")
        editModeFrame.HealthText:SetText("67")
        editModeFrame.HealthText:SetTextColor(1, 1, 1)
    end

    if editModeFrame.PortraitFrame then
        editModeFrame.PortraitFrame:SetSize(portraitSize, portraitSize)
    end
    if editModeFrame.PortraitBorder then
        editModeFrame.PortraitBorder:SetTexture(RefineUI.Media.Textures.PortraitBorder)
        editModeFrame.PortraitBorder:SetVertexColor(borderR, borderG, borderB)
    end
    if editModeFrame.PortraitBG then
        editModeFrame.PortraitBG:SetTexture(RefineUI.Media.Textures.PortraitBG)
    end
    if editModeFrame.Portrait then
        SetPreviewPortraitTexture(editModeFrame.Portrait)
    end

    if editModeFrame.CastBar then
        editModeFrame.CastBar:SetSize(plateWidth, castHeight)
        editModeFrame.CastBar:SetStatusBarTexture(RefineUI.Media.Textures.HealthBar)
        editModeFrame.CastBar:SetStatusBarDesaturated(true)
        editModeFrame.CastBar:SetMinMaxValues(0, 100)
        editModeFrame.CastBar:SetValue(48)
        editModeFrame.CastBar:SetStatusBarColor(castR, castG, castB)
        if editModeFrame.CastBar.border and editModeFrame.CastBar.border.SetBackdropBorderColor then
            editModeFrame.CastBar.border:SetBackdropBorderColor(castR, castG, castB, 1)
        end
    end
    if editModeFrame.CastBarBG then
        editModeFrame.CastBarBG:SetTexture(RefineUI.Media.Textures.HealthBar)
        editModeFrame.CastBarBG:SetVertexColor(castR * 0.24, castG * 0.24, castB * 0.24, 0.95)
    end
    if editModeFrame.CastText then
        editModeFrame.CastText:SetText("Shadow Bolt")
    end
    if editModeFrame.CastTime then
        editModeFrame.CastTime:SetText("1.4")
        editModeFrame.CastTime:SetTextColor(castShieldR, castShieldG, castShieldB)
    end

    if editModeFrame.CrowdControlBar then
        if ccEnabled then
            editModeFrame.CrowdControlBar:Show()
            editModeFrame.CrowdControlBar:SetSize(plateWidth, ccHeight)
            editModeFrame.CrowdControlBar:SetStatusBarTexture(RefineUI.Media.Textures.HealthBar)
            editModeFrame.CrowdControlBar:SetStatusBarDesaturated(true)
            editModeFrame.CrowdControlBar:SetMinMaxValues(0, 100)
            editModeFrame.CrowdControlBar:SetValue(74)
            editModeFrame.CrowdControlBar:SetStatusBarColor(ccR, ccG, ccB)

            if editModeFrame.CrowdControlBar.border and editModeFrame.CrowdControlBar.border.SetBackdropBorderColor then
                editModeFrame.CrowdControlBar.border:SetBackdropBorderColor(ccBorderR, ccBorderG, ccBorderB, 1)
            end

            if editModeFrame.CrowdControlBG then
                editModeFrame.CrowdControlBG:SetTexture(RefineUI.Media.Textures.HealthBar)
                editModeFrame.CrowdControlBG:SetVertexColor(ccR * 0.24, ccG * 0.24, ccB * 0.24, 0.95)
            end

            if editModeFrame.CrowdControlText then
                editModeFrame.CrowdControlText:SetText("Stunned")
            end
            if editModeFrame.CrowdControlTime then
                editModeFrame.CrowdControlTime:SetText("3.2")
            end
        else
            editModeFrame.CrowdControlBar:Hide()
        end
    end

    if editModeFrame.Label then
        editModeFrame.Label:ClearAllPoints()
        local anchor = editModeFrame.CastBar
        if ccEnabled and editModeFrame.CrowdControlBar and editModeFrame.CrowdControlBar:IsShown() then
            anchor = editModeFrame.CrowdControlBar
        end
        editModeFrame.Label:SetPoint("TOP", anchor, "BOTTOM", 0, -8)
    end

    if editModeFrame.TargetArrows then
        editModeFrame.TargetArrows.Left:SetVertexColor(borderR, borderG, borderB)
        editModeFrame.TargetArrows.Right:SetVertexColor(borderR, borderG, borderB)

        if config.TargetIndicator == false then
            editModeFrame.TargetArrows:Hide()
        else
            editModeFrame.TargetArrows:Show()
        end
    end
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

    local plate = CreateFrame("Frame", nil, frame)
    plate:SetPoint("TOP", frame, "TOP", 0, -8)
    plate:EnableMouse(false)
    RefineUI.SetTemplate(plate, "Transparent")
    RefineUI.CreateBorder(plate, 6, 6, 12)
    frame.Plate = plate

    local health = CreateFrame("StatusBar", nil, plate)
    health:EnableMouse(false)
    RefineUI.SetInside(health, plate, 1, 1)
    frame.Health = health

    local healthBG = health:CreateTexture(nil, "BACKGROUND")
    healthBG:SetAllPoints()
    healthBG:SetTexture(RefineUI.Media.Textures.HealthBar)
    healthBG:SetVertexColor(0.22, 0.22, 0.22, 0.95)
    frame.HealthBG = healthBG

    local nameText = plate:CreateFontString(nil, "OVERLAY")
    RefineUI.Font(nameText, PREVIEW_NAME_FONT_SIZE, nil, "OUTLINE")
    nameText:SetPoint("BOTTOM", plate, "TOP", 0, 4)
    nameText:SetText("Training Dummy")
    frame.NameText = nameText

    local titleText = plate:CreateFontString(nil, "OVERLAY")
    RefineUI.Font(titleText, 10, nil, "OUTLINE")
    titleText:SetPoint("TOP", nameText, "BOTTOM", 0, -1)
    titleText:SetText("<Innkeeper>")
    titleText:SetTextColor(1, 0.82, 0)
    frame.TitleText = titleText

    local healthText = plate:CreateFontString(nil, "OVERLAY")
    RefineUI.Font(healthText, PREVIEW_HEALTH_FONT_SIZE, nil, "OUTLINE")
    healthText:SetPoint("CENTER", plate, "CENTER", 0, -1)
    healthText:SetText("67")
    frame.HealthText = healthText

    local portraitFrame = CreateFrame("Frame", nil, frame)
    portraitFrame:SetPoint("RIGHT", plate, "LEFT", 6, 0)
    portraitFrame:EnableMouse(false)
    frame.PortraitFrame = portraitFrame

    local portrait = portraitFrame:CreateTexture(nil, "ARTWORK")
    RefineUI.SetInside(portrait, portraitFrame, 0, 0)
    frame.Portrait = portrait

    local mask = portraitFrame:CreateMaskTexture()
    mask:SetTexture(RefineUI.Media.Textures.PortraitMask)
    RefineUI.SetInside(mask, portraitFrame, 0, 0)
    portrait:AddMaskTexture(mask)
    frame.PortraitMask = mask

    local portraitBG = portraitFrame:CreateTexture(nil, "BACKGROUND")
    portraitBG:SetTexture(RefineUI.Media.Textures.PortraitBG)
    RefineUI.SetInside(portraitBG, portraitFrame, 0, 0)
    portraitBG:AddMaskTexture(mask)
    frame.PortraitBG = portraitBG

    local portraitBorder = portraitFrame:CreateTexture(nil, "OVERLAY")
    portraitBorder:SetTexture(RefineUI.Media.Textures.PortraitBorder)
    RefineUI.SetOutside(portraitBorder, portraitFrame, 0, 0)
    frame.PortraitBorder = portraitBorder

    local arrows = CreateFrame("Frame", nil, plate)
    arrows:SetAllPoints()
    arrows:EnableMouse(false)
    frame.TargetArrows = arrows

    local leftArrow = arrows:CreateTexture(nil, "OVERLAY")
    leftArrow:SetTexture(RefineUI.Media.Textures.TargetArrowLeft)
    leftArrow:SetSize(20, 20)
    leftArrow:SetPoint("RIGHT", plate, "LEFT", -4, 0)
    arrows.Left = leftArrow

    local rightArrow = arrows:CreateTexture(nil, "OVERLAY")
    rightArrow:SetTexture(RefineUI.Media.Textures.TargetArrowRight)
    rightArrow:SetSize(20, 20)
    rightArrow:SetPoint("LEFT", plate, "RIGHT", 4, 0)
    arrows.Right = rightArrow

    local castBar = CreateFrame("StatusBar", nil, frame)
    castBar:SetPoint("TOP", plate, "BOTTOM", 0, -8)
    castBar:EnableMouse(false)
    RefineUI.CreateBorder(castBar, 6, 6, 12)
    frame.CastBar = castBar

    local castBarBG = castBar:CreateTexture(nil, "BACKGROUND")
    castBarBG:SetAllPoints()
    castBarBG:SetTexture(RefineUI.Media.Textures.HealthBar)
    castBarBG:SetVertexColor(0.18, 0.18, 0.18, 0.95)
    frame.CastBarBG = castBarBG

    local castText = castBar:CreateFontString(nil, "OVERLAY")
    RefineUI.Font(castText, 10, nil, "OUTLINE")
    castText:SetPoint("BOTTOMLEFT", castBar, "BOTTOMLEFT", 4, 0)
    castText:SetText("Shadow Bolt")
    frame.CastText = castText

    local castTime = castBar:CreateFontString(nil, "OVERLAY")
    RefineUI.Font(castTime, 10, nil, "OUTLINE")
    castTime:SetPoint("BOTTOMRIGHT", castBar, "BOTTOMRIGHT", -4, 0)
    castTime:SetText("1.4")
    frame.CastTime = castTime

    local crowdControlBar = CreateFrame("StatusBar", nil, frame)
    crowdControlBar:SetPoint("TOP", castBar, "BOTTOM", 0, -6)
    crowdControlBar:EnableMouse(false)
    RefineUI.CreateBorder(crowdControlBar, 6, 6, 12)
    frame.CrowdControlBar = crowdControlBar

    local crowdControlBG = crowdControlBar:CreateTexture(nil, "BACKGROUND")
    crowdControlBG:SetAllPoints()
    crowdControlBG:SetTexture(RefineUI.Media.Textures.HealthBar)
    crowdControlBG:SetVertexColor(0.1, 0.3, 0.5, 0.95)
    frame.CrowdControlBG = crowdControlBG

    local crowdControlText = crowdControlBar:CreateFontString(nil, "OVERLAY")
    RefineUI.Font(crowdControlText, 10, nil, "OUTLINE")
    crowdControlText:SetPoint("BOTTOMLEFT", crowdControlBar, "BOTTOMLEFT", 4, 0)
    crowdControlText:SetText("Stunned")
    frame.CrowdControlText = crowdControlText

    local crowdControlTime = crowdControlBar:CreateFontString(nil, "OVERLAY")
    RefineUI.Font(crowdControlTime, 10, nil, "OUTLINE")
    crowdControlTime:SetPoint("BOTTOMRIGHT", crowdControlBar, "BOTTOMRIGHT", -4, 0)
    crowdControlTime:SetText("3.2")
    frame.CrowdControlTime = crowdControlTime

    local label = frame:CreateFontString(nil, "OVERLAY")
    RefineUI.Font(label, 11, nil, "OUTLINE")
    label:SetPoint("TOP", crowdControlBar, "BOTTOM", 0, -8)
    label:SetText("Nameplates")
    label:SetTextColor(1, 0.82, 0)
    frame.Label = label

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
        name = "Nameplate Width",
        default = DEFAULT_PLATE_SIZE[1],
        minValue = 120,
        maxValue = 320,
        valueStep = 1,
        get = function()
            return ClampNumber(GetNameplatesConfig().Size[1], 120, 320, DEFAULT_PLATE_SIZE[1])
        end,
        set = function(_, value)
            local config = GetNameplatesConfig()
            config.Size[1] = floor(ClampNumber(value, 120, 320, DEFAULT_PLATE_SIZE[1]) + 0.5)
            RefreshPreviewFrame()
            RefreshLiveNameplates()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.Slider,
        name = "Nameplate Height",
        default = DEFAULT_PLATE_SIZE[2],
        minValue = 10,
        maxValue = 48,
        valueStep = 1,
        get = function()
            return ClampNumber(GetNameplatesConfig().Size[2], 10, 48, DEFAULT_PLATE_SIZE[2])
        end,
        set = function(_, value)
            local config = GetNameplatesConfig()
            config.Size[2] = floor(ClampNumber(value, 10, 48, DEFAULT_PLATE_SIZE[2]) + 0.5)
            RefreshPreviewFrame()
            RefreshLiveNameplates()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.Slider,
        name = "Unit Name Scale",
        default = DEFAULT_TEXT_SCALE,
        minValue = NAMEPLATE_TEXT_SCALE_MIN,
        maxValue = NAMEPLATE_TEXT_SCALE_MAX,
        valueStep = NAMEPLATE_SCALE_STEP,
        formatter = FormatScaleValue,
        get = function()
            return RoundToStep(
                ClampNumber(GetNameplatesConfig().UnitNameScale, NAMEPLATE_TEXT_SCALE_MIN, NAMEPLATE_TEXT_SCALE_MAX, DEFAULT_TEXT_SCALE),
                NAMEPLATE_SCALE_STEP
            )
        end,
        set = function(_, value)
            local config = GetNameplatesConfig()
            config.UnitNameScale = RoundToStep(
                ClampNumber(value, NAMEPLATE_TEXT_SCALE_MIN, NAMEPLATE_TEXT_SCALE_MAX, DEFAULT_TEXT_SCALE),
                NAMEPLATE_SCALE_STEP
            )
            RefreshPreviewFrame()
            RefreshLiveNameplates()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.Slider,
        name = "HP Text Scale",
        default = DEFAULT_TEXT_SCALE,
        minValue = NAMEPLATE_TEXT_SCALE_MIN,
        maxValue = NAMEPLATE_TEXT_SCALE_MAX,
        valueStep = NAMEPLATE_SCALE_STEP,
        formatter = FormatScaleValue,
        get = function()
            return RoundToStep(
                ClampNumber(GetNameplatesConfig().HealthTextScale, NAMEPLATE_TEXT_SCALE_MIN, NAMEPLATE_TEXT_SCALE_MAX, DEFAULT_TEXT_SCALE),
                NAMEPLATE_SCALE_STEP
            )
        end,
        set = function(_, value)
            local config = GetNameplatesConfig()
            config.HealthTextScale = RoundToStep(
                ClampNumber(value, NAMEPLATE_TEXT_SCALE_MIN, NAMEPLATE_TEXT_SCALE_MAX, DEFAULT_TEXT_SCALE),
                NAMEPLATE_SCALE_STEP
            )
            RefreshPreviewFrame()
            RefreshLiveNameplates()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.Slider,
        name = "Portrait Scale",
        default = DEFAULT_DYNAMIC_PORTRAIT_SCALE,
        minValue = NAMEPLATE_TEXT_SCALE_MIN,
        maxValue = NAMEPLATE_TEXT_SCALE_MAX,
        valueStep = NAMEPLATE_SCALE_STEP,
        formatter = FormatScaleValue,
        get = function()
            return RoundToStep(
                ClampNumber(
                    GetNameplatesConfig().DynamicPortraitScale,
                    NAMEPLATE_TEXT_SCALE_MIN,
                    NAMEPLATE_TEXT_SCALE_MAX,
                    DEFAULT_DYNAMIC_PORTRAIT_SCALE
                ),
                NAMEPLATE_SCALE_STEP
            )
        end,
        set = function(_, value)
            local config = GetNameplatesConfig()
            config.DynamicPortraitScale = RoundToStep(
                ClampNumber(value, NAMEPLATE_TEXT_SCALE_MIN, NAMEPLATE_TEXT_SCALE_MAX, DEFAULT_DYNAMIC_PORTRAIT_SCALE),
                NAMEPLATE_SCALE_STEP
            )
            RefreshPreviewFrame()
            RefreshLiveNameplates()
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
        default = 0.8,
        minValue = 0.1,
        maxValue = 1,
        valueStep = 0.05,
        get = function()
            return ClampNumber(GetNameplatesConfig().Alpha, 0.1, 1, 0.8)
        end,
        set = function(_, value)
            local alpha = RoundToStep(ClampNumber(value, 0.1, 1, 0.8), 0.05)
            local config = GetNameplatesConfig()
            config.Alpha = alpha
            SetCVar("nameplateMinAlpha", alpha)
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
