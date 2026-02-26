----------------------------------------------------------------------------------------
-- EncounterTimeline Component: Skin
-- Description: Timeline view/event-frame skinning and border/icon styling
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local EncounterTimeline = RefineUI:GetModule("EncounterTimeline")
if not EncounterTimeline then
    return
end

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config
local Media = RefineUI.Media
local Colors = RefineUI.Colors
local Locale = RefineUI.Locale

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local CreateFrame = CreateFrame
local pairs = pairs
local math_max = math.max
local math_min = math.min
local pcall = pcall
local type = type
local UIParent = UIParent
local issecretvalue = _G.issecretvalue
local canaccessvalue = _G.canaccessvalue
local bit_band = (bit and bit.band) or (bit32 and bit32.band)
local bit_bor = (bit and bit.bor) or (bit32 and bit32.bor)

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local ICON_BORDER_INSET = 4
local VIEW_BORDER_INSET = 6
local EDGE_SIZE = 12
local TRACK_LINE_BAR_THICKNESS = 8
local TRACK_LINE_BORDER_INSET = 6
local TRACK_LINE_ALPHA = 0.5
local TRACK_LINE_FRAME_LEVEL_OFFSET = -2
local TRACK_COUNTDOWN_FONT_SIZE = 22
local TIMER_COUNTDOWN_FONT_SIZE = 18
local TIMER_NAME_FONT_SIZE = 12
local TRACK_NAME_FONT_SIZE = 11
local TRACK_STATUS_FONT_SIZE = 10
local PIP_TEXT_FONT_SIZE = 14
local TRACK_TEXT_ANCHOR_OFFSET = 10
local SPELL_TYPE_ICON_ANCHOR_OFFSET_Y = 2
local SPELL_TYPE_ICON_SPACING = 2
local SPELL_NAME_UNDER_ICON_OFFSET_Y = -2
local SPELL_STATUS_UNDER_NAME_OFFSET_Y = -1
local DEADLY_EFFECT_MASK = 1
local ENRAGE_EFFECT_MASK = 2
local BLEED_EFFECT_MASK = 4
local MAGIC_EFFECT_MASK = 8
local DISEASE_EFFECT_MASK = 16
local CURSE_EFFECT_MASK = 32
local POISON_EFFECT_MASK = 64
local TANK_ROLE_MASK = 128
local HEALER_ROLE_MASK = 256
local DPS_ROLE_MASK = 512
local ROLE_ICON_MASK = TANK_ROLE_MASK + HEALER_ROLE_MASK + DPS_ROLE_MASK
local OTHER_ICON_MASK = DEADLY_EFFECT_MASK + ENRAGE_EFFECT_MASK + BLEED_EFFECT_MASK + MAGIC_EFFECT_MASK + DISEASE_EFFECT_MASK + CURSE_EFFECT_MASK + POISON_EFFECT_MASK
local INDICATOR_ICON_MASK_ORDER = {
    TANK_ROLE_MASK,
    HEALER_ROLE_MASK,
    DPS_ROLE_MASK,
    DEADLY_EFFECT_MASK,
    ENRAGE_EFFECT_MASK,
    BLEED_EFFECT_MASK,
    MAGIC_EFFECT_MASK,
    DISEASE_EFFECT_MASK,
    CURSE_EFFECT_MASK,
    POISON_EFFECT_MASK,
}
local ICON_DISPEL_STYLES = {
    { mask = ENRAGE_EFFECT_MASK, color = { 0.5137254901960784, 0.00392156862745098, 0.00392156862745098, 1 } },
    { mask = BLEED_EFFECT_MASK, color = { 1, 0, 0, 1 } },
    { mask = MAGIC_EFFECT_MASK, color = { 0, 0.5019607843137255, 1, 1 } },
    { mask = DISEASE_EFFECT_MASK, color = { 1, 0.5019607843137255, 0, 1 } },
    { mask = CURSE_EFFECT_MASK, color = { 0.5019607843137255, 0, 1, 1 } },
    { mask = POISON_EFFECT_MASK, color = { 0, 1, 0, 1 } },
}
local ICON_DISPEL_BORDER_THICKNESS = 2
local ICON_DEADLY_GLOW_PADDING = 8
local ICON_DEADLY_GLOW_COLOR = { 1, 0.16, 0.16, 0.8 }
local BORDER_COLOR_BY_ROLE_MASK = {
    [TANK_ROLE_MASK] = { 0.25, 0.54, 1.0, 1.0 },
    [HEALER_ROLE_MASK] = { 0.22, 0.95, 0.45, 1.0 },
    [DPS_ROLE_MASK] = { 1.0, 0.35, 0.25, 1.0 },
}
local BORDER_COLOR_DEADLY = { 1.0, 0.2, 0.2, 1.0 }
local BORDER_COLOR_BY_SEVERITY = {
    [0] = { 0.95, 0.85, 0.34, 1.0 },
    [1] = { 1.0, 0.62, 0.23, 1.0 },
    [2] = { 1.0, 0.28, 0.22, 1.0 },
}
local ICON_PROBE_MASKS = {
    DEADLY_EFFECT_MASK,
    ENRAGE_EFFECT_MASK,
    BLEED_EFFECT_MASK,
    MAGIC_EFFECT_MASK,
    DISEASE_EFFECT_MASK,
    CURSE_EFFECT_MASK,
    POISON_EFFECT_MASK,
    TANK_ROLE_MASK,
    HEALER_ROLE_MASK,
    DPS_ROLE_MASK,
}

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local function IsTimerEventFrame(eventFrame)
    return eventFrame and eventFrame.Bar ~= nil
end

local function IsTrackEventFrame(eventFrame)
    return eventFrame and eventFrame.Countdown ~= nil
end

local function GetStatusbarTexture()
    local media = RefineUI.Media
    local textures = media and media.Textures
    return textures and textures.Statusbar
end

local function IsTrackView(viewFrame)
    return viewFrame and viewFrame.LineStart and viewFrame.LineEnd
end

local function IsUnreadableValue(value)
    if value == nil then
        return false
    end

    if issecretvalue and issecretvalue(value) then
        return true
    end
    if canaccessvalue and not canaccessvalue(value) then
        return true
    end
    if RefineUI.IsSecretValue and RefineUI:IsSecretValue(value) then
        return true
    end
    return false
end

local function IsBlizzardAutoScalingTextElement(fontString)
    if not fontString then
        return false
    end

    -- EncounterWarnings text elements mix in AutoScalingFontStringMixin.
    return type(fontString.SetTextScale) == "function"
        and type(fontString.SetTextToFit) == "function"
        and type(fontString.ScaleTextToFit) == "function"
end

local function HasAnyValue(value)
    return value ~= nil
end

local function GetShownState(frame)
    if not frame or type(frame.IsShown) ~= "function" then
        return nil
    end

    local ok, shown = pcall(frame.IsShown, frame)
    if not ok or IsUnreadableValue(shown) or type(shown) ~= "boolean" then
        return nil
    end

    return shown
end

local function IsFrameShown(frame)
    if not frame then
        return false
    end

    local shown = GetShownState(frame)
    if shown == nil then
        return true
    end
    return shown
end

local function GetSafeFrameLevel(frame, fallback)
    local safeFallback = type(fallback) == "number" and fallback or 0
    if not frame or type(frame.GetFrameLevel) ~= "function" then
        return safeFallback
    end

    local ok, frameLevel = pcall(frame.GetFrameLevel, frame)
    if not ok or IsUnreadableValue(frameLevel) or type(frameLevel) ~= "number" then
        return safeFallback
    end

    return frameLevel
end

local function GetSafeFrameStrata(frame, fallback)
    local safeFallback = (type(fallback) == "string" and fallback ~= "") and fallback or "MEDIUM"
    if not frame or type(frame.GetFrameStrata) ~= "function" then
        return safeFallback
    end

    local ok, frameStrata = pcall(frame.GetFrameStrata, frame)
    if not ok or IsUnreadableValue(frameStrata) or type(frameStrata) ~= "string" or frameStrata == "" then
        return safeFallback
    end

    return frameStrata
end

local function IsSafeNumber(value)
    return type(value) == "number" and not IsUnreadableValue(value)
end

local function IsSafeColorChannel(value)
    return type(value) == "number" and not IsUnreadableValue(value)
end

local function GetCountdownSwipeTexture()
    local media = RefineUI.Media
    local textures = media and media.Textures
    if type(textures) ~= "table" then
        return nil
    end
    return textures.CooldownSwipe or textures.CooldownSwipeSmall
end

local function ApplyCooldownTextStyle(cooldown, fontSize)
    if not cooldown or type(cooldown.GetRegions) ~= "function" then
        return
    end

    local regions = { cooldown:GetRegions() }
    for index = 1, #regions do
        local region = regions[index]
        if region and type(region.GetObjectType) == "function" and region:GetObjectType() == "FontString" then
            if not IsBlizzardAutoScalingTextElement(region) then
                RefineUI.Font(region, fontSize, RefineUI.Media.Fonts.Number, "OUTLINE", true)
            end
        end
    end
end

local function ApplyCooldownSwipeStyle(cooldown)
    if not cooldown then
        return
    end

    local swipeTexture = GetCountdownSwipeTexture()
    if swipeTexture and cooldown.SetSwipeTexture then
        pcall(cooldown.SetSwipeTexture, cooldown, swipeTexture)
    end

    if cooldown.SetDrawEdge then
        pcall(cooldown.SetDrawEdge, cooldown, false)
    end
    if cooldown.SetDrawBling then
        pcall(cooldown.SetDrawBling, cooldown, false)
    end
    if cooldown.SetDrawSwipe then
        pcall(cooldown.SetDrawSwipe, cooldown, true)
    end
end

local function ApplyIconContainerSkin(iconContainer)
    if not iconContainer then
        return
    end

    if iconContainer.bg and iconContainer.bg.SetAlpha then
        iconContainer.bg:SetAlpha(0)
    end
end

function EncounterTimeline:EnsureIconContainerSkinFrame(eventFrame)
    if not eventFrame or not eventFrame.IconContainer then
        return nil
    end

    local iconContainer = eventFrame.IconContainer
    local skinFrame = self:StateGet(eventFrame, "iconContainerSkinFrame")
    if skinFrame and skinFrame.GetParent and skinFrame:GetParent() == iconContainer then
        return skinFrame
    end

    skinFrame = CreateFrame("Frame", nil, iconContainer)
    skinFrame:SetAllPoints(iconContainer)
    skinFrame:SetFrameStrata(GetSafeFrameStrata(iconContainer, "MEDIUM"))
    local okSkinLevel, skinLevel = pcall(function()
        return math_max(0, GetSafeFrameLevel(iconContainer, 0) + 10)
    end)
    skinFrame:SetFrameLevel((okSkinLevel and type(skinLevel) == "number") and skinLevel or 10)
    skinFrame:EnableMouse(false)

    pcall(RefineUI.SetTemplate, skinFrame, "Icon")
    pcall(RefineUI.CreateBorder, skinFrame, ICON_BORDER_INSET, ICON_BORDER_INSET, EDGE_SIZE)

    if skinFrame.bg and skinFrame.bg.SetAlpha then
        skinFrame.bg:SetAlpha(0)
    end

    self:StateSet(eventFrame, "iconContainerSkinFrame", skinFrame)
    return skinFrame
end

local function GetDefaultBorderColor()
    local color = RefineUI.Config and RefineUI.Config.General and RefineUI.Config.General.BorderColor
    if type(color) == "table" then
        return color[1] or 0.6, color[2] or 0.6, color[3] or 0.6, color[4] or 1
    end
    return 0.6, 0.6, 0.6, 1
end

local function GetDangerGlowTexture()
    local media = RefineUI.Media
    local textures = media and media.Textures
    return (type(textures) == "table" and (textures.Glow or textures.Highlight)) or [[Interface\Buttons\WHITE8x8]]
end

local function SetTextureListShown(textureList, shown)
    if type(textureList) ~= "table" then
        return
    end

    for index = 1, #textureList do
        local texture = textureList[index]
        if texture and texture.SetShown then
            texture:SetShown(shown)
        end
    end
end

local function ResolveEventInfo(eventFrame, eventID)
    local eventInfo
    if eventFrame and type(eventFrame.GetEventInfo) == "function" then
        eventInfo = eventFrame:GetEventInfo()
    end

    if IsUnreadableValue(eventInfo) or type(eventInfo) ~= "table" then
        if EncounterTimeline:IsValidEventID(eventID) and C_EncounterTimeline and type(C_EncounterTimeline.GetEventInfo) == "function" then
            local ok, info = pcall(C_EncounterTimeline.GetEventInfo, eventID)
            eventInfo = ok and info or nil
        else
            eventInfo = nil
        end
    end

    if IsUnreadableValue(eventInfo) or type(eventInfo) ~= "table" then
        return nil
    end

    if EncounterTimeline:IsValidEventID(eventID) then
        EncounterTimeline:UpdateEventMetadataFromInfo(eventID, eventInfo)
    end

    return eventInfo
end

local function ResolveEventColor(eventInfo)
    if type(eventInfo) ~= "table" then
        return nil
    end

    local color = eventInfo.color
    if IsUnreadableValue(color) or color == nil then
        return nil
    end

    local r, g, b, a
    if type(color) == "table" then
        if type(color.GetRGB) == "function" then
            local ok, cr, cg, cb = pcall(color.GetRGB, color)
            if ok then
                r, g, b = cr, cg, cb
            end
        else
            r, g, b = color.r, color.g, color.b
        end
        a = color.a
    end

    if IsUnreadableValue(r) or IsUnreadableValue(g) or IsUnreadableValue(b) then
        return nil
    end

    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        return nil
    end

    if IsUnreadableValue(a) or type(a) ~= "number" then
        a = 1
    end

    return r, g, b, a
end

local function ResolveEventSeverity(eventInfo, eventMetadata)
    if type(eventInfo) == "table" then
        local severity = eventInfo.severity
        if not IsUnreadableValue(severity) and type(severity) == "number" then
            return severity
        end
    end

    if type(eventMetadata) == "table" then
        local severity = eventMetadata.severity
        if not IsUnreadableValue(severity) and type(severity) == "number" then
            return severity
        end
    end

    return nil
end

local function HasProbeTextureResult(texture, requireVisibleAlpha)
    if not texture then
        return false
    end

    local alphaReadable = false
    local alpha = nil
    if type(texture.GetAlpha) == "function" then
        local ok, value = pcall(texture.GetAlpha, texture)
        if ok and type(value) == "number" and not IsUnreadableValue(value) then
            alphaReadable = true
            alpha = value
        end
    end

    local hasAtlas = false
    if type(texture.GetAtlas) == "function" then
        local ok, value = pcall(texture.GetAtlas, texture)
        if ok and HasAnyValue(value) then
            if IsUnreadableValue(value) then
                hasAtlas = true
            elseif type(value) == "string" and value ~= "" then
                hasAtlas = true
            end
        end
    end

    local hasTexture = false
    if type(texture.GetTexture) == "function" then
        local ok, value = pcall(texture.GetTexture, texture)
        if ok and HasAnyValue(value) then
            hasTexture = true
        end
    end

    if requireVisibleAlpha == true and alphaReadable == true and alpha <= 0 then
        return false
    end

    return hasAtlas or hasTexture
end

function EncounterTimeline:EnsureEventIconMaskProbe()
    local probeFrame = self.eventIconMaskProbeFrame
    local probeTexture = self.eventIconMaskProbeTexture
    if probeFrame and probeTexture then
        return probeTexture
    end

    probeFrame = CreateFrame("Frame", nil, UIParent)
    probeFrame:SetSize(1, 1)
    probeFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 10000)
    probeFrame:Hide()

    probeTexture = probeFrame:CreateTexture(nil, "BACKGROUND")
    probeTexture:SetAllPoints()
    probeTexture:SetAlpha(0)

    self.eventIconMaskProbeFrame = probeFrame
    self.eventIconMaskProbeTexture = probeTexture

    return probeTexture
end

function EncounterTimeline:ProbeEventIconMask(eventID)
    if not self:IsValidEventID(eventID) then
        return nil
    end
    if not C_EncounterTimeline or type(C_EncounterTimeline.SetEventIconTextures) ~= "function" then
        return nil
    end
    if not bit_band or not bit_bor then
        return nil
    end

    local probeTexture = self:EnsureEventIconMaskProbe()
    if not probeTexture then
        return nil
    end

    local resolvedMask = 0
    for index = 1, #ICON_PROBE_MASKS do
        local mask = ICON_PROBE_MASKS[index]

        probeTexture:SetTexture(nil)
        if probeTexture.SetAlpha then
            probeTexture:SetAlpha(0)
        end

        local ok = pcall(C_EncounterTimeline.SetEventIconTextures, eventID, mask, { probeTexture })
        if ok and HasProbeTextureResult(probeTexture, false) then
            resolvedMask = bit_bor(resolvedMask, mask)
        end
    end

    self:SetEventMetadataField(eventID, "iconMask", resolvedMask)
    return resolvedMask
end

function EncounterTimeline:ResolveEventIconMask(eventFrame, eventID, eventInfo)
    if not self:IsValidEventID(eventID) then
        return nil
    end

    if type(eventInfo) == "table" then
        local mask = eventInfo.icons
        if not IsUnreadableValue(mask) and type(mask) == "number" then
            self:SetEventMetadataField(eventID, "iconMask", mask)
            return mask
        end
    end

    local metadata = self:GetEventMetadata(eventID)
    if type(metadata) == "table" and not IsUnreadableValue(metadata.iconMask) and type(metadata.iconMask) == "number" then
        return metadata.iconMask
    end

    return self:ProbeEventIconMask(eventID)
end

local function ResolveClassificationColor(iconMask)
    if type(iconMask) ~= "number" or IsUnreadableValue(iconMask) or not bit_band then
        return nil
    end

    if bit_band(iconMask, DEADLY_EFFECT_MASK) ~= 0 then
        return BORDER_COLOR_DEADLY
    end

    for index = 1, #ICON_DISPEL_STYLES do
        local style = ICON_DISPEL_STYLES[index]
        if bit_band(iconMask, style.mask) ~= 0 then
            return style.color
        end
    end

    if bit_band(iconMask, TANK_ROLE_MASK) ~= 0 then
        return BORDER_COLOR_BY_ROLE_MASK[TANK_ROLE_MASK]
    end
    if bit_band(iconMask, HEALER_ROLE_MASK) ~= 0 then
        return BORDER_COLOR_BY_ROLE_MASK[HEALER_ROLE_MASK]
    end
    if bit_band(iconMask, DPS_ROLE_MASK) ~= 0 then
        return BORDER_COLOR_BY_ROLE_MASK[DPS_ROLE_MASK]
    end

    return nil
end

function EncounterTimeline:ApplyEventColorBorder(eventFrame, eventID)
    if not eventFrame or not eventFrame.IconContainer then
        return
    end

    local skinFrame
    if IsTrackEventFrame(eventFrame) or IsTimerEventFrame(eventFrame) then
        skinFrame = self:EnsureIconContainerSkinFrame(eventFrame)
    end

    local borderFrame = (skinFrame and (skinFrame.border or skinFrame.RefineBorder))
        or eventFrame.IconContainer.border
        or eventFrame.IconContainer.RefineBorder
    if not borderFrame or type(borderFrame.SetBackdropBorderColor) ~= "function" then
        return
    end

    local eventInfo = ResolveEventInfo(eventFrame, eventID)
    local eventMetadata = self:GetEventMetadata(eventID)
    local config = self:GetConfig()

    local borderColorMode = config.SkinBorderColorMode
    if type(borderColorMode) ~= "string" then
        borderColorMode = self.SKIN_BORDER_COLOR_MODE.ICON_CLASSIFICATION
    end

    local borderState = self:StateGet(eventFrame, "eventColorBorderState")
    if type(borderState) ~= "table" then
        borderState = {}
        self:StateSet(eventFrame, "eventColorBorderState", borderState)
    end

    local color
    if borderColorMode == self.SKIN_BORDER_COLOR_MODE.EVENT_COLOR then
        local r, g, b, a = ResolveEventColor(eventInfo)
        if r ~= nil then
            color = { r, g, b, a or 1 }
        end
    elseif borderColorMode == self.SKIN_BORDER_COLOR_MODE.SEVERITY then
        local severity = ResolveEventSeverity(eventInfo, eventMetadata)
        color = BORDER_COLOR_BY_SEVERITY[severity]
    elseif borderColorMode == self.SKIN_BORDER_COLOR_MODE.ICON_CLASSIFICATION then
        local iconMask = self:ResolveEventIconMask(eventFrame, eventID, eventInfo)
        color = ResolveClassificationColor(iconMask)
        if not color then
            local severity = ResolveEventSeverity(eventInfo, eventMetadata)
            color = BORDER_COLOR_BY_SEVERITY[severity]
        end
    end

    if type(color) == "table"
        and IsSafeColorChannel(color[1])
        and IsSafeColorChannel(color[2])
        and IsSafeColorChannel(color[3]) then
        local alpha = color[4]
        if not IsSafeColorChannel(alpha) then
            alpha = 1
        end

        borderFrame:SetBackdropBorderColor(color[1], color[2], color[3], alpha)
        borderState.lastEventID = eventID
        borderState.lastMode = borderColorMode
        borderState.lastColor = { color[1], color[2], color[3], alpha }
        return
    end

    if borderState.lastEventID == eventID and borderState.lastMode == borderColorMode and type(borderState.lastColor) == "table" then
        local preserved = borderState.lastColor
        borderFrame:SetBackdropBorderColor(preserved[1], preserved[2], preserved[3], preserved[4] or 1)
        return
    end

    if type(color) ~= "table" then
        local r, g, b, a = GetDefaultBorderColor()
        borderFrame:SetBackdropBorderColor(r, g, b, a)
        borderState.lastEventID = eventID
        borderState.lastMode = borderColorMode
        borderState.lastColor = { r, g, b, a }
    else
        local r, g, b, a = GetDefaultBorderColor()
        borderFrame:SetBackdropBorderColor(r, g, b, a)
        borderState.lastEventID = eventID
        borderState.lastMode = borderColorMode
        borderState.lastColor = { r, g, b, a }
    end
end

function EncounterTimeline:EnsureIconMaskStyleState(eventFrame)
    local styleState = self:StateGet(eventFrame, "iconMaskStyleState")
    if styleState then
        return styleState
    end

    local iconContainer = eventFrame and eventFrame.IconContainer
    if not iconContainer then
        return nil
    end

    local overlay = CreateFrame("Frame", nil, iconContainer)
    overlay:SetAllPoints(iconContainer)
    local okOverlayLevel, overlayLevel = pcall(function()
        return math_max(0, GetSafeFrameLevel(iconContainer, 0) + 12)
    end)
    overlay:SetFrameLevel((okOverlayLevel and type(overlayLevel) == "number") and overlayLevel or 12)
    overlay:SetFrameStrata(GetSafeFrameStrata(iconContainer, "MEDIUM"))
    overlay:EnableMouse(false)

    local dangerGlow = overlay:CreateTexture(nil, "OVERLAY", nil, 3)
    dangerGlow:SetPoint("TOPLEFT", iconContainer, "TOPLEFT", -ICON_DEADLY_GLOW_PADDING, ICON_DEADLY_GLOW_PADDING)
    dangerGlow:SetPoint("BOTTOMRIGHT", iconContainer, "BOTTOMRIGHT", ICON_DEADLY_GLOW_PADDING, -ICON_DEADLY_GLOW_PADDING)
    dangerGlow:SetBlendMode("ADD")
    dangerGlow:SetTexture(GetDangerGlowTexture())
    dangerGlow:SetVertexColor(ICON_DEADLY_GLOW_COLOR[1], ICON_DEADLY_GLOW_COLOR[2], ICON_DEADLY_GLOW_COLOR[3], ICON_DEADLY_GLOW_COLOR[4])
    dangerGlow:Hide()

    local dispelBorderByMask = {}
    for index = 1, #ICON_DISPEL_STYLES do
        local style = ICON_DISPEL_STYLES[index]
        local edges = {}

        local topEdge = overlay:CreateTexture(nil, "OVERLAY", nil, 2)
        topEdge:SetPoint("TOPLEFT", iconContainer, "TOPLEFT", 0, 0)
        topEdge:SetPoint("TOPRIGHT", iconContainer, "TOPRIGHT", 0, 0)
        topEdge:SetHeight(ICON_DISPEL_BORDER_THICKNESS)
        topEdge:SetColorTexture(style.color[1], style.color[2], style.color[3], style.color[4])
        topEdge:Hide()
        edges[#edges + 1] = topEdge

        local bottomEdge = overlay:CreateTexture(nil, "OVERLAY", nil, 2)
        bottomEdge:SetPoint("BOTTOMLEFT", iconContainer, "BOTTOMLEFT", 0, 0)
        bottomEdge:SetPoint("BOTTOMRIGHT", iconContainer, "BOTTOMRIGHT", 0, 0)
        bottomEdge:SetHeight(ICON_DISPEL_BORDER_THICKNESS)
        bottomEdge:SetColorTexture(style.color[1], style.color[2], style.color[3], style.color[4])
        bottomEdge:Hide()
        edges[#edges + 1] = bottomEdge

        local leftEdge = overlay:CreateTexture(nil, "OVERLAY", nil, 2)
        leftEdge:SetPoint("TOPLEFT", iconContainer, "TOPLEFT", 0, 0)
        leftEdge:SetPoint("BOTTOMLEFT", iconContainer, "BOTTOMLEFT", 0, 0)
        leftEdge:SetWidth(ICON_DISPEL_BORDER_THICKNESS)
        leftEdge:SetColorTexture(style.color[1], style.color[2], style.color[3], style.color[4])
        leftEdge:Hide()
        edges[#edges + 1] = leftEdge

        local rightEdge = overlay:CreateTexture(nil, "OVERLAY", nil, 2)
        rightEdge:SetPoint("TOPRIGHT", iconContainer, "TOPRIGHT", 0, 0)
        rightEdge:SetPoint("BOTTOMRIGHT", iconContainer, "BOTTOMRIGHT", 0, 0)
        rightEdge:SetWidth(ICON_DISPEL_BORDER_THICKNESS)
        rightEdge:SetColorTexture(style.color[1], style.color[2], style.color[3], style.color[4])
        rightEdge:Hide()
        edges[#edges + 1] = rightEdge

        dispelBorderByMask[style.mask] = edges
    end

    styleState = {
        Overlay = overlay,
        DangerGlow = dangerGlow,
        DispelBorderByMask = dispelBorderByMask,
    }

    self:StateSet(eventFrame, "iconMaskStyleState", styleState)
    return styleState
end

function EncounterTimeline:HideIconMaskStyleState(eventFrame)
    local styleState = self:StateGet(eventFrame, "iconMaskStyleState")
    if not styleState then
        return
    end

    local dangerGlow = styleState.DangerGlow
    if dangerGlow and dangerGlow.SetShown then
        dangerGlow:SetShown(false)
    end

    local dispelBorderByMask = styleState.DispelBorderByMask
    if type(dispelBorderByMask) == "table" then
        for _, edges in pairs(dispelBorderByMask) do
            SetTextureListShown(edges, false)
        end
    end
end

function EncounterTimeline:ApplyIconMaskStyle(eventFrame, eventID)
    local config = self:GetConfig()
    if config.SkinUseIconMaskStyles ~= true then
        self:HideIconMaskStyleState(eventFrame)
        return
    end

    if not self:IsValidEventID(eventID) then
        self:HideIconMaskStyleState(eventFrame)
        return
    end

    local styleState = self:EnsureIconMaskStyleState(eventFrame)
    if not styleState then
        return
    end

    local iconMask = self:ResolveEventIconMask(eventFrame, eventID, nil)
    if type(iconMask) ~= "number" then
        if styleState.LastResolvedEventID == eventID and type(styleState.LastResolvedIconMask) == "number" then
            iconMask = styleState.LastResolvedIconMask
        else
            self:HideIconMaskStyleState(eventFrame)
            styleState.LastResolvedEventID = nil
            styleState.LastResolvedIconMask = nil
            return
        end
    else
        styleState.LastResolvedEventID = eventID
        styleState.LastResolvedIconMask = iconMask
    end

    if IsUnreadableValue(iconMask) then
        return
    end

    if config.SkinDeadlyGlowEnable == true and styleState.DangerGlow and bit_band and bit_band(iconMask, DEADLY_EFFECT_MASK) ~= 0 then
        styleState.DangerGlow:SetTexture(GetDangerGlowTexture())
        styleState.DangerGlow:SetVertexColor(ICON_DEADLY_GLOW_COLOR[1], ICON_DEADLY_GLOW_COLOR[2], ICON_DEADLY_GLOW_COLOR[3], ICON_DEADLY_GLOW_COLOR[4])
        styleState.DangerGlow:Show()
    elseif styleState.DangerGlow then
        styleState.DangerGlow:Hide()
    end

    local dispelBorderByMask = styleState.DispelBorderByMask
    if config.SkinDispelBorderEnable == true and type(dispelBorderByMask) == "table" then
        for index = 1, #ICON_DISPEL_STYLES do
            local style = ICON_DISPEL_STYLES[index]
            local edges = dispelBorderByMask[style.mask]
            if type(edges) == "table" and #edges > 0 then
                local shouldShow = bit_band and bit_band(iconMask, style.mask) ~= 0
                for textureIndex = 1, #edges do
                    local edgeTexture = edges[textureIndex]
                    edgeTexture:SetTexture(nil)
                    edgeTexture:SetColorTexture(style.color[1], style.color[2], style.color[3], style.color[4])
                    edgeTexture:SetShown(shouldShow)
                end
            end
        end
    elseif type(dispelBorderByMask) == "table" then
        for _, edges in pairs(dispelBorderByMask) do
            SetTextureListShown(edges, false)
        end
    end
end

function EncounterTimeline:ApplyEventIconVisualStyling(eventFrame, eventID)
    self:ApplyEventColorBorder(eventFrame, eventID)
    self:ApplyIconMaskStyle(eventFrame, eventID)
end

local function GetIndicatorTextureMaskSets()
    local roleMask = ROLE_ICON_MASK
    local otherMask = OTHER_ICON_MASK

    local constants = _G.Constants
    local iconMasks = constants and constants.EncounterTimelineIconMasks
    if type(iconMasks) == "table" then
        local roleMaskValue = iconMasks.EncounterTimelineRoleIcons
        if type(roleMaskValue) == "number" and not IsUnreadableValue(roleMaskValue) then
            roleMask = roleMaskValue
        end

        local otherMaskValue = iconMasks.EncounterTimelineOtherIcons
        if type(otherMaskValue) == "number" and not IsUnreadableValue(otherMaskValue) then
            otherMask = otherMaskValue
        end
    end

    return roleMask, otherMask
end

local function ClearIndicatorTextureList(textureList)
    if type(textureList) ~= "table" then
        return
    end

    for index = 1, #textureList do
        local texture = textureList[index]
        if texture then
            pcall(texture.SetAtlas, texture, nil)
            pcall(texture.SetTexture, texture, nil)
        end
    end
end

local function GetEventFrameWantedIndicatorMask(eventFrame)
    if not eventFrame then
        return nil
    end

    if type(eventFrame.GetIndicatorIconMask) == "function" then
        local okMask, mask = pcall(eventFrame.GetIndicatorIconMask, eventFrame)
        if okMask and type(mask) == "number" and not IsUnreadableValue(mask) then
            return mask
        end
    end

    local mask = eventFrame.indicatorIconMask
    if type(mask) == "number" and not IsUnreadableValue(mask) then
        return mask
    end

    return nil
end

function EncounterTimeline:ApplyPackedIndicatorIcons(eventFrame, eventID)
    local indicatorContainer = eventFrame and (eventFrame.Indicators or eventFrame.IndicatorContainer)
    if not indicatorContainer then
        return
    end
    if not self:IsValidEventID(eventID) then
        return
    end
    if not C_EncounterTimeline or type(C_EncounterTimeline.SetEventIconTextures) ~= "function" then
        return
    end

    local roleIndicators = indicatorContainer.RoleIndicators
    local otherIndicators = indicatorContainer.OtherIndicators
    if type(roleIndicators) ~= "table" and type(otherIndicators) ~= "table" then
        return
    end

    ClearIndicatorTextureList(roleIndicators)
    ClearIndicatorTextureList(otherIndicators)

    local iconMask = self:ResolveEventIconMask(eventFrame, eventID, nil)
    if type(iconMask) == "number" and not IsUnreadableValue(iconMask) and bit_band then
        local allIndicators = {}
        if type(roleIndicators) == "table" then
            for index = 1, #roleIndicators do
                allIndicators[#allIndicators + 1] = roleIndicators[index]
            end
        end
        if type(otherIndicators) == "table" then
            for index = 1, #otherIndicators do
                allIndicators[#allIndicators + 1] = otherIndicators[index]
            end
        end

        local assignedCount = 0
        for index = 1, #INDICATOR_ICON_MASK_ORDER do
            local maskBit = INDICATOR_ICON_MASK_ORDER[index]
            local okHasBit, hasBit = pcall(function()
                return bit_band(iconMask, maskBit) ~= 0
            end)
            if okHasBit and hasBit == true then
                local targetTexture = allIndicators[assignedCount + 1]
                if not targetTexture then
                    break
                end

                local okAssign = pcall(C_EncounterTimeline.SetEventIconTextures, eventID, maskBit, { targetTexture })
                if okAssign then
                    assignedCount = assignedCount + 1
                end
            end
        end

        if assignedCount > 0 then
            return
        end
    end

    local roleMask, otherMask = GetIndicatorTextureMaskSets()
    local wantedMask = GetEventFrameWantedIndicatorMask(eventFrame)
    if type(wantedMask) == "number" and not IsUnreadableValue(wantedMask) and bit_band then
        local okRoleMask, maskedRole = pcall(function()
            return bit_band(roleMask, wantedMask)
        end)
        if okRoleMask and type(maskedRole) == "number" then
            roleMask = maskedRole
        end

        local okOtherMask, maskedOther = pcall(function()
            return bit_band(otherMask, wantedMask)
        end)
        if okOtherMask and type(maskedOther) == "number" then
            otherMask = maskedOther
        end
    end

    if type(roleIndicators) == "table" then
        pcall(C_EncounterTimeline.SetEventIconTextures, eventID, roleMask, roleIndicators)
    end
    if type(otherIndicators) == "table" then
        pcall(C_EncounterTimeline.SetEventIconTextures, eventID, otherMask, otherIndicators)
    end
end

local function CollectVisibleIndicatorTextures(indicatorContainer)
    local visibleIndicators = {}
    if not indicatorContainer then
        return visibleIndicators
    end

    local function IsRenderableIndicatorTexture(indicatorTexture)
        if not indicatorTexture then
            return false
        end

        local shown = GetShownState(indicatorTexture)
        if shown == false then
            return false
        end

        return HasProbeTextureResult(indicatorTexture, false)
    end

    local function AppendVisible(textureList)
        if type(textureList) ~= "table" then
            return
        end

        for index = 1, #textureList do
            local indicatorTexture = textureList[index]
            if IsRenderableIndicatorTexture(indicatorTexture) then
                visibleIndicators[#visibleIndicators + 1] = indicatorTexture
            end
        end
    end

    AppendVisible(indicatorContainer.RoleIndicators)
    AppendVisible(indicatorContainer.OtherIndicators)
    return visibleIndicators
end

local function GetVisibleFontStringHeight(fontString)
    if not fontString then
        return 0
    end

    local shown = GetShownState(fontString)
    if shown == false then
        return 0
    end

    if type(fontString.GetStringHeight) == "function" then
        local ok, stringHeight = pcall(fontString.GetStringHeight, fontString)
        if ok and not IsUnreadableValue(stringHeight) and type(stringHeight) == "number" and stringHeight > 0 then
            return stringHeight
        end
    end

    if type(fontString.GetHeight) == "function" then
        local ok, regionHeight = pcall(fontString.GetHeight, fontString)
        if ok and not IsUnreadableValue(regionHeight) and type(regionHeight) == "number" and regionHeight > 0 then
            return regionHeight
        end
    end

    return 0
end

local function ComputeTrackIconRowCenterOffsetY(eventFrame)
    if not eventFrame then
        return SPELL_TYPE_ICON_ANCHOR_OFFSET_Y
    end

    local nameHeight = GetVisibleFontStringHeight(eventFrame.NameText)
    local statusHeight = GetVisibleFontStringHeight(eventFrame.StatusText)
    local hasName = nameHeight > 0
    local hasStatus = statusHeight > 0

    if hasName and hasStatus then
        return (nameHeight + statusHeight - SPELL_NAME_UNDER_ICON_OFFSET_Y - SPELL_STATUS_UNDER_NAME_OFFSET_Y) * 0.5
    end

    if hasName then
        return (nameHeight - SPELL_NAME_UNDER_ICON_OFFSET_Y) * 0.5
    end

    if hasStatus then
        return (statusHeight - SPELL_NAME_UNDER_ICON_OFFSET_Y) * 0.5
    end

    return SPELL_TYPE_ICON_ANCHOR_OFFSET_Y
end

function EncounterTimeline:ApplyTrackTextAnchorOverride(eventFrame)
    if not eventFrame or not IsTrackEventFrame(eventFrame) then
        return
    end

    local nameText = eventFrame.NameText
    local statusText = eventFrame.StatusText
    if not nameText or not statusText then
        return
    end

    if IsBlizzardAutoScalingTextElement(nameText) or IsBlizzardAutoScalingTextElement(statusText) then
        return
    end

    local config = self:GetConfig()
    local desiredAnchor = config.TrackTextAnchor or self.TRACK_TEXT_ANCHOR.LEFT
    local iconScale = (type(eventFrame.GetIconScale) == "function" and eventFrame:GetIconScale()) or 1
    if IsUnreadableValue(iconScale) or type(iconScale) ~= "number" then
        iconScale = 1
    end

    local okOffset, scaledOffset = pcall(function()
        return TRACK_TEXT_ANCHOR_OFFSET * iconScale
    end)
    local offset = (okOffset and type(scaledOffset) == "number") and scaledOffset or TRACK_TEXT_ANCHOR_OFFSET
    local pointName = "LEFT"
    local relativePointName = "RIGHT"
    local offsetX = offset
    local nameTopPoint = "BOTTOMLEFT"
    local statusTopPoint = "TOPLEFT"
    local textJustify = "LEFT"

    if desiredAnchor == self.TRACK_TEXT_ANCHOR.LEFT then
        pointName = "RIGHT"
        relativePointName = "LEFT"
        offsetX = -offset
        nameTopPoint = "BOTTOMRIGHT"
        statusTopPoint = "TOPRIGHT"
        textJustify = "RIGHT"
    end

    if type(nameText.SetJustifyH) == "function" then
        nameText:SetJustifyH(textJustify)
    end
    if type(statusText.SetJustifyH) == "function" then
        statusText:SetJustifyH(textJustify)
    end

    local indicatorContainer = eventFrame.Indicators or eventFrame.IndicatorContainer
    local visibleIndicators = CollectVisibleIndicatorTextures(indicatorContainer)

    nameText:ClearAllPoints()
    statusText:ClearAllPoints()

    if #visibleIndicators > 0 then
        local anchorIndicator = visibleIndicators[1]
        if desiredAnchor == self.TRACK_TEXT_ANCHOR.LEFT then
            nameText:SetPoint("TOPRIGHT", anchorIndicator, "BOTTOMRIGHT", 0, SPELL_NAME_UNDER_ICON_OFFSET_Y)
            statusText:SetPoint("TOPRIGHT", nameText, "BOTTOMRIGHT", 0, SPELL_STATUS_UNDER_NAME_OFFSET_Y)
        else
            nameText:SetPoint("TOPLEFT", anchorIndicator, "BOTTOMLEFT", 0, SPELL_NAME_UNDER_ICON_OFFSET_Y)
            statusText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, SPELL_STATUS_UNDER_NAME_OFFSET_Y)
        end
        return
    end

    nameText:SetPoint(pointName, eventFrame, relativePointName, offsetX, 0)
    statusText:SetPoint(statusTopPoint, nameText, nameTopPoint, 0, SPELL_STATUS_UNDER_NAME_OFFSET_Y)
end

function EncounterTimeline:ApplySpellTypeIndicatorAnchorOverride(eventFrame)
    if not eventFrame then
        return
    end

    local eventID = type(eventFrame.GetEventID) == "function" and eventFrame:GetEventID() or nil
    if self:IsValidEventID(eventID) then
        self:ApplyPackedIndicatorIcons(eventFrame, eventID)
    end

    local iconFrame = eventFrame.IconContainer
    local indicatorContainer = eventFrame.Indicators or eventFrame.IndicatorContainer
    if not iconFrame or not indicatorContainer then
        return
    end

    local visibleIndicators = CollectVisibleIndicatorTextures(indicatorContainer)
    if #visibleIndicators == 0 then
        if IsTrackEventFrame(eventFrame) then
            self:ApplyTrackTextAnchorOverride(eventFrame)
        end
        return
    end

    local firstIndicator = visibleIndicators[1]
    local growRightToLeft = false
    local firstPoint = "BOTTOMLEFT"
    local firstRelativePoint = "TOPLEFT"
    local firstOffsetX = 0
    local firstOffsetY = SPELL_TYPE_ICON_ANCHOR_OFFSET_Y

    if IsTrackEventFrame(eventFrame) then
        local hasAutoScalingTrackText = IsBlizzardAutoScalingTextElement(eventFrame.NameText)
            or IsBlizzardAutoScalingTextElement(eventFrame.StatusText)
        local config = self:GetConfig()
        local desiredAnchor = config.TrackTextAnchor or self.TRACK_TEXT_ANCHOR.LEFT
        local iconScale = (type(eventFrame.GetIconScale) == "function" and eventFrame:GetIconScale()) or 1
        if IsUnreadableValue(iconScale) or type(iconScale) ~= "number" then
            iconScale = 1
        end

        local okSideOffset, sideOffsetValue = pcall(function()
            return math.abs(TRACK_TEXT_ANCHOR_OFFSET * iconScale)
        end)
        local sideOffset = (okSideOffset and type(sideOffsetValue) == "number") and sideOffsetValue or TRACK_TEXT_ANCHOR_OFFSET
        local iconWidth = (type(iconFrame.GetWidth) == "function" and iconFrame:GetWidth()) or 0
        if IsUnreadableValue(iconWidth) or type(iconWidth) ~= "number" then
            iconWidth = 0
        end

        local indicatorWidth = (type(firstIndicator.GetWidth) == "function" and firstIndicator:GetWidth()) or 0
        if IsUnreadableValue(indicatorWidth) or type(indicatorWidth) ~= "number" then
            indicatorWidth = 0
        end

        if not hasAutoScalingTrackText then
            firstOffsetY = ComputeTrackIconRowCenterOffsetY(eventFrame)
        end
        firstPoint = "CENTER"
        firstRelativePoint = "CENTER"

        if desiredAnchor == self.TRACK_TEXT_ANCHOR.LEFT then
            growRightToLeft = true
            local okOffsetX, offsetX = pcall(function()
                return -((iconWidth * 0.5) + sideOffset + (indicatorWidth * 0.5))
            end)
            if okOffsetX and type(offsetX) == "number" then
                firstOffsetX = offsetX
            else
                firstOffsetX = -sideOffset
            end
        else
            growRightToLeft = false
            local okOffsetX, offsetX = pcall(function()
                return (iconWidth * 0.5) + sideOffset + (indicatorWidth * 0.5)
            end)
            if okOffsetX and type(offsetX) == "number" then
                firstOffsetX = offsetX
            else
                firstOffsetX = sideOffset
            end
        end
    elseif type(eventFrame.ShouldFlipHorizontally) == "function" then
        local ok, flipped = pcall(eventFrame.ShouldFlipHorizontally, eventFrame)
        if ok and not IsUnreadableValue(flipped) and type(flipped) == "boolean" then
            growRightToLeft = flipped
        end

        if growRightToLeft then
            firstPoint = "BOTTOMRIGHT"
            firstRelativePoint = "TOPRIGHT"
        else
            firstPoint = "BOTTOMLEFT"
            firstRelativePoint = "TOPLEFT"
        end
    end

    firstIndicator:ClearAllPoints()
    firstIndicator:SetPoint(firstPoint, iconFrame, firstRelativePoint, firstOffsetX, firstOffsetY)

    for index = 2, #visibleIndicators do
        local indicatorTexture = visibleIndicators[index]
        local previousTexture = visibleIndicators[index - 1]
        indicatorTexture:ClearAllPoints()
        if growRightToLeft then
            indicatorTexture:SetPoint("RIGHT", previousTexture, "LEFT", -SPELL_TYPE_ICON_SPACING, 0)
        else
            indicatorTexture:SetPoint("LEFT", previousTexture, "RIGHT", SPELL_TYPE_ICON_SPACING, 0)
        end
    end

    if IsTrackEventFrame(eventFrame) then
        if IsBlizzardAutoScalingTextElement(eventFrame.NameText) or IsBlizzardAutoScalingTextElement(eventFrame.StatusText) then
            return
        end
        self:ApplyTrackTextAnchorOverride(eventFrame)
    end
end

local function HideTrackLineTexture(texture)
    if texture and texture.SetAlpha then
        texture:SetAlpha(0)
    end
end

function EncounterTimeline:HideDefaultTrackLineArt(viewFrame)
    if not IsTrackView(viewFrame) then
        return
    end

    HideTrackLineTexture(viewFrame.LineStart)
    HideTrackLineTexture(viewFrame.LineEnd)
    HideTrackLineTexture(viewFrame.LongDivider)
    HideTrackLineTexture(viewFrame.QueueDivider)

    if type(viewFrame.EnumerateLineBreakMaskTextures) == "function" then
        for _, maskTexture in viewFrame:EnumerateLineBreakMaskTextures() do
            HideTrackLineTexture(maskTexture)
        end
    end
end

function EncounterTimeline:EnsureTrackLineBar(viewFrame)
    local barFrame = self:StateGet(viewFrame, "trackLineBar")
    if barFrame then
        return barFrame
    end

    barFrame = CreateFrame("Frame", nil, viewFrame)
    RefineUI:AddAPI(barFrame)
    barFrame:SetFrameStrata(GetSafeFrameStrata(viewFrame, "MEDIUM"))
    barFrame:SetFrameLevel(math_max(0, GetSafeFrameLevel(viewFrame, 0) + TRACK_LINE_FRAME_LEVEL_OFFSET))
    barFrame:SetAlpha(TRACK_LINE_ALPHA)
    RefineUI.SetTemplate(barFrame, "Default")
    RefineUI.CreateBorder(barFrame, TRACK_LINE_BORDER_INSET, TRACK_LINE_BORDER_INSET, EDGE_SIZE)

    local fill = barFrame:CreateTexture(nil, "ARTWORK")
    fill:SetAllPoints()
    fill:SetTexture(GetStatusbarTexture())
    barFrame:Hide()

    self:StateSet(viewFrame, "trackLineBar", barFrame)
    self:StateSet(viewFrame, "trackLineFill", fill)
    return barFrame
end

function EncounterTimeline:UpdateTrackLineBarGeometry(viewFrame, barFrame)
    if not IsTrackView(viewFrame) or not barFrame then
        return false
    end

    local lineStart = viewFrame.LineStart
    local lineEnd = viewFrame.LineEnd
    local viewLeft = viewFrame:GetLeft()
    local viewBottom = viewFrame:GetBottom()
    local left1, right1 = lineStart:GetLeft(), lineStart:GetRight()
    local top1, bottom1 = lineStart:GetTop(), lineStart:GetBottom()
    local left2, right2 = lineEnd:GetLeft(), lineEnd:GetRight()
    local top2, bottom2 = lineEnd:GetTop(), lineEnd:GetBottom()

    local geometryValues = { viewLeft, viewBottom, left1, right1, top1, bottom1, left2, right2, top2, bottom2 }
    for index = 1, #geometryValues do
        local value = geometryValues[index]
        if IsUnreadableValue(value) then
            return nil
        end
        if type(value) ~= "number" then
            return false
        end
    end

    local left = math_min(left1, left2)
    local right = math_max(right1, right2)
    local top = math_max(top1, top2)
    local bottom = math_min(bottom1, bottom2)
    local thickness = RefineUI:Scale(TRACK_LINE_BAR_THICKNESS)

    if (right - left) >= (top - bottom) then
        local centerY = (top + bottom) * 0.5
        top = centerY + (thickness * 0.5)
        bottom = centerY - (thickness * 0.5)
    else
        local centerX = (left + right) * 0.5
        left = centerX - (thickness * 0.5)
        right = centerX + (thickness * 0.5)
    end

    barFrame:ClearAllPoints()
    barFrame:SetPoint("TOPLEFT", viewFrame, "BOTTOMLEFT", left - viewLeft, top - viewBottom)
    barFrame:SetPoint("BOTTOMRIGHT", viewFrame, "BOTTOMLEFT", right - viewLeft, bottom - viewBottom)
    return true
end

function EncounterTimeline:InstallTrackLineHooks(viewFrame)
    if not IsTrackView(viewFrame) then
        return
    end
    if self:StateGet(viewFrame, "trackLineHooksInstalled") == true then
        return
    end
    self:StateSet(viewFrame, "trackLineHooksInstalled", true)

    local updateLineHookKey = self:BuildFrameHookKey(viewFrame, "UpdateLineTextures", "TrackLineSkin")
    RefineUI:HookOnce(updateLineHookKey, viewFrame, "UpdateLineTextures", function(frame)
        EncounterTimeline:ApplyTrackLineSkin(frame, true)
    end)

    local updateViewHookKey = self:BuildFrameHookKey(viewFrame, "UpdateView", "TrackLineSkin")
    RefineUI:HookOnce(updateViewHookKey, viewFrame, "UpdateView", function(frame)
        EncounterTimeline:ApplyTrackLineSkin(frame, true)
    end)

    -- Avoid HookScript on Blizzard EncounterWarnings views; those script hooks taint
    -- Edit Mode secret-value paths. Secure method hooks above plus explicit refreshes
    -- cover normal updates.
end

function EncounterTimeline:ApplyTrackLineSkin(viewFrame, force)
    if not IsTrackView(viewFrame) then
        return
    end
    self:InstallTrackLineHooks(viewFrame)

    local token = "TrackLine:" .. tostring(GetStatusbarTexture())
    if not force and self:StateGet(viewFrame, "trackLineSkinToken") == token then
        return
    end

    if not IsFrameShown(viewFrame) then
        local hiddenBar = self:StateGet(viewFrame, "trackLineBar")
        if hiddenBar then
            hiddenBar:Hide()
        end
        self:StateSet(viewFrame, "trackLineSkinToken", token)
        return
    end

    self:HideDefaultTrackLineArt(viewFrame)

    local barFrame = self:EnsureTrackLineBar(viewFrame)
    local fill = self:StateGet(viewFrame, "trackLineFill")
    if fill then
        fill:SetTexture(GetStatusbarTexture())
    end

    local geometryApplied = self:UpdateTrackLineBarGeometry(viewFrame, barFrame)
    if geometryApplied == true then
        barFrame:Show()
        self:StateClear(viewFrame, "trackLineDeferredQueued")
    elseif geometryApplied == false then
        barFrame:Hide()

        if self:StateGet(viewFrame, "trackLineDeferredQueued") ~= true then
            self:StateSet(viewFrame, "trackLineDeferredQueued", true)
            local deferredHookKey = self:BuildFrameHookKey(viewFrame, "DeferredApply", "TrackLineSkin")
            RefineUI:After(deferredHookKey, 0, function()
                EncounterTimeline:StateClear(viewFrame, "trackLineDeferredQueued")
                if IsFrameShown(viewFrame) then
                    EncounterTimeline:ApplyTrackLineSkin(viewFrame, true)
                end
            end)
        end
    else
        self:StateClear(viewFrame, "trackLineDeferredQueued")
    end

    self:StateSet(viewFrame, "trackLineSkinToken", token)
end

----------------------------------------------------------------------------------------
-- Event Frame Skin
----------------------------------------------------------------------------------------
function EncounterTimeline:ApplyTimerEventSkin(eventFrame, eventID, force)
    if not eventFrame or not IsTimerEventFrame(eventFrame) then
        return
    end

    local token = "Timer:" .. tostring(GetStatusbarTexture())
    if not force and self:StateGet(eventFrame, "timerSkinToken") == token then
        self:ApplyEventIconVisualStyling(eventFrame, eventID)
        return
    end

    ApplyIconContainerSkin(eventFrame.IconContainer)
    self:ApplyEventIconVisualStyling(eventFrame, eventID)

    local bar = eventFrame.Bar
    if bar then
        pcall(RefineUI.SetTemplate, bar, "Default")
        pcall(RefineUI.CreateBorder, bar, VIEW_BORDER_INSET, VIEW_BORDER_INSET, EDGE_SIZE)

        local statusbarTexture = GetStatusbarTexture()
        if statusbarTexture and type(bar.SetStatusBarTexture) == "function" then
            bar:SetStatusBarTexture(statusbarTexture)
        end

        if bar.Duration then
            if not IsBlizzardAutoScalingTextElement(bar.Duration) then
                RefineUI.Font(bar.Duration, TIMER_COUNTDOWN_FONT_SIZE, RefineUI.Media.Fonts.Number, "OUTLINE", true)
            end
        end
        if bar.Name then
            if not IsBlizzardAutoScalingTextElement(bar.Name) then
                RefineUI.Font(bar.Name, TIMER_NAME_FONT_SIZE, RefineUI.Media.Fonts.Medium, "OUTLINE", true)
            end
        end
    end

    local iconHookKey = self:BuildFrameHookKey(eventFrame, "UpdateIconBorder", "MaskStyle")
    RefineUI:HookOnce(iconHookKey, eventFrame, "UpdateIconBorder", function(frame)
        local frameEventID = type(frame.GetEventID) == "function" and frame:GetEventID() or nil
        EncounterTimeline:ApplyEventIconVisualStyling(frame, frameEventID)
    end)

    local indicatorHookKey = self:BuildFrameHookKey(eventFrame, "UpdateIndicatorIcons", "SpellTypeIconAnchor")
    RefineUI:HookOnce(indicatorHookKey, eventFrame, "UpdateIndicatorIcons", function(frame)
        EncounterTimeline:ApplySpellTypeIndicatorAnchorOverride(frame)
    end)

    local layoutHookKey = self:BuildFrameHookKey(eventFrame, "UpdateLayout", "SpellTypeIconAnchor")
    RefineUI:HookOnce(layoutHookKey, eventFrame, "UpdateLayout", function(frame)
        EncounterTimeline:ApplySpellTypeIndicatorAnchorOverride(frame)
    end)
    self:ApplySpellTypeIndicatorAnchorOverride(eventFrame)

    self:StateSet(eventFrame, "timerSkinToken", token)
end

function EncounterTimeline:ApplyTrackEventSkin(eventFrame, eventID, force)
    if not eventFrame or not IsTrackEventFrame(eventFrame) then
        return
    end

    local token = "Track:" .. tostring(GetCountdownSwipeTexture())
    if not force and self:StateGet(eventFrame, "trackSkinToken") == token then
        self:ApplyEventIconVisualStyling(eventFrame, eventID)
        return
    end

    ApplyIconContainerSkin(eventFrame.IconContainer)
    self:ApplyEventIconVisualStyling(eventFrame, eventID)

    if eventFrame.Countdown then
        ApplyCooldownSwipeStyle(eventFrame.Countdown)
        ApplyCooldownTextStyle(eventFrame.Countdown, TRACK_COUNTDOWN_FONT_SIZE)
    end

    if eventFrame.NameText then
        if not IsBlizzardAutoScalingTextElement(eventFrame.NameText) then
            RefineUI.Font(eventFrame.NameText, TRACK_NAME_FONT_SIZE, RefineUI.Media.Fonts.Medium, "OUTLINE", true)
        end
    end
    if eventFrame.StatusText then
        if not IsBlizzardAutoScalingTextElement(eventFrame.StatusText) then
            RefineUI.Font(eventFrame.StatusText, TRACK_STATUS_FONT_SIZE, RefineUI.Media.Fonts.Medium, "OUTLINE", true)
        end
    end

    local iconHookKey = self:BuildFrameHookKey(eventFrame, "UpdateBorderStyle", "MaskStyle")
    RefineUI:HookOnce(iconHookKey, eventFrame, "UpdateBorderStyle", function(frame)
        local frameEventID = type(frame.GetEventID) == "function" and frame:GetEventID() or nil
        EncounterTimeline:ApplyEventIconVisualStyling(frame, frameEventID)
    end)

    local iconographyHookKey = self:BuildFrameHookKey(eventFrame, "UpdateIconography", "SpellTypeIconAnchor")
    RefineUI:HookOnce(iconographyHookKey, eventFrame, "UpdateIconography", function(frame)
        EncounterTimeline:ApplySpellTypeIndicatorAnchorOverride(frame)
    end)

    local orientationHookKey = self:BuildFrameHookKey(eventFrame, "UpdateOrientation", "SpellTypeIconAnchor")
    RefineUI:HookOnce(orientationHookKey, eventFrame, "UpdateOrientation", function(frame)
        EncounterTimeline:ApplySpellTypeIndicatorAnchorOverride(frame)
    end)
    self:ApplySpellTypeIndicatorAnchorOverride(eventFrame)

    local textAnchorHookKey = self:BuildFrameHookKey(eventFrame, "UpdateTextAnchors", "TrackTextAnchor")
    RefineUI:HookOnce(textAnchorHookKey, eventFrame, "UpdateTextAnchors", function(frame)
        EncounterTimeline:ApplyTrackTextAnchorOverride(frame)
    end)
    self:ApplyTrackTextAnchorOverride(eventFrame)

    self:StateSet(eventFrame, "trackSkinToken", token)
end

function EncounterTimeline:ApplyEventFrameSkin(viewFrame, eventFrame, eventID, force)
    if not eventFrame then
        return
    end

    if self:IsValidEventID(eventID) then
        self:MapEventFrame(eventID, eventFrame)
    end

    local config = self:GetConfig()
    if config.SkinEnabled ~= true then
        return
    end

    if config.SkinTimerView and IsTimerEventFrame(eventFrame) then
        self:ApplyTimerEventSkin(eventFrame, eventID, force)
    end

    if config.SkinTrackView and IsTrackEventFrame(eventFrame) then
        self:ApplyTrackEventSkin(eventFrame, eventID, force)
    end

end

----------------------------------------------------------------------------------------
-- View Skin
----------------------------------------------------------------------------------------
function EncounterTimeline:ApplyViewEventFrameSkins(viewFrame, force)
    if not viewFrame or type(viewFrame.EnumerateEventFrames) ~= "function" then
        return
    end
    for eventFrame in viewFrame:EnumerateEventFrames() do
        local eventID = type(eventFrame.GetEventID) == "function" and eventFrame:GetEventID() or nil
        self:ApplyEventFrameSkin(viewFrame, eventFrame, eventID, force)
    end
end

function EncounterTimeline:EnsureViewBorderOverlay(viewFrame)
    if not viewFrame then
        return nil
    end

    local overlay = self:StateGet(viewFrame, "viewBorderOverlay")
    if overlay and type(overlay.SetAllPoints) == "function" then
        return overlay
    end

    overlay = CreateFrame("Frame", nil, viewFrame)
    if not overlay then
        return nil
    end

    if overlay.EnableMouse then
        overlay:EnableMouse(false)
    end
    overlay:SetAllPoints(viewFrame)

    self:StateSet(viewFrame, "viewBorderOverlay", overlay)
    return overlay
end

function EncounterTimeline:ApplyViewBorderSkin(viewFrame)
    local overlay = self:EnsureViewBorderOverlay(viewFrame)
    if not overlay then
        return
    end

    local strata = GetSafeFrameStrata(viewFrame, "MEDIUM")
    local level = GetSafeFrameLevel(viewFrame, 0) + 10

    if type(overlay.SetFrameStrata) == "function" then
        overlay:SetFrameStrata(strata)
    end
    if type(overlay.SetFrameLevel) == "function" then
        overlay:SetFrameLevel(level)
    end

    pcall(RefineUI.CreateBorder, overlay, VIEW_BORDER_INSET, VIEW_BORDER_INSET, EDGE_SIZE)
end

function EncounterTimeline:ApplyViewSkin(viewFrame, force)
    if not viewFrame then
        return
    end
    local config = self:GetConfig()
    if config.SkinEnabled ~= true then
        return
    end

    local timelineFrame = _G.EncounterTimeline
    if timelineFrame then
        if viewFrame == timelineFrame.TrackView and config.SkinTrackView ~= true then
            return
        end
        if viewFrame == timelineFrame.TimerView and config.SkinTimerView ~= true then
            return
        end
    end

    local token = "ViewSkin"
    if not force and self:StateGet(viewFrame, "viewSkinToken") == token then
        return
    end

    self:ApplyViewBorderSkin(viewFrame)

    if viewFrame.PipText then
        RefineUI.Font(viewFrame.PipText, PIP_TEXT_FONT_SIZE, RefineUI.Media.Fonts.Number, "OUTLINE", true)
    end

    self:StateSet(viewFrame, "viewSkinToken", token)

    if IsTrackView(viewFrame) then
        self:ApplyTrackLineSkin(viewFrame, force)
    end

    if type(viewFrame.UpdateView) == "function" then
        local updateViewHookKey = self:BuildFrameHookKey(viewFrame, "UpdateView", "Skin")
        RefineUI:HookOnce(updateViewHookKey, viewFrame, "UpdateView", function(frame)
            EncounterTimeline:ApplyViewSkin(frame, true)
            EncounterTimeline:ApplyViewEventFrameSkins(frame, true)
        end)
    end

    if type(viewFrame.UpdateLineTextures) == "function" then
        local updateLineHookKey = self:BuildFrameHookKey(viewFrame, "UpdateLineTextures", "Skin")
        RefineUI:HookOnce(updateLineHookKey, viewFrame, "UpdateLineTextures", function(frame)
            EncounterTimeline:ApplyViewSkin(frame, true)
        end)
    end
end

function EncounterTimeline:RefreshTimelineSkins(force)
    local timelineFrame = _G.EncounterTimeline
    if not timelineFrame then
        return
    end

    local config = self:GetConfig()
    if config.SkinEnabled ~= true then
        return
    end

    local timerView = timelineFrame.TimerView
    local trackView = timelineFrame.TrackView

    if config.SkinTimerView and timerView then
        self:ApplyViewSkin(timerView, force)
        self:ApplyViewEventFrameSkins(timerView, force)
    end

    if config.SkinTrackView and trackView then
        self:ApplyViewSkin(trackView, force)
        self:ApplyViewEventFrameSkins(trackView, force)
    end
end

----------------------------------------------------------------------------------------
-- Skin Hooks
----------------------------------------------------------------------------------------
function EncounterTimeline:OnTimelineEventFrameAcquired(viewFrame, eventFrame, eventID, _isNewObject)
    if self:IsValidEventID(eventID) then
        self:MapEventFrame(eventID, eventFrame)
    end

    if viewFrame then
        self:ApplyViewSkin(viewFrame, true)
    end
    self:ApplyEventFrameSkin(viewFrame, eventFrame, eventID, true)
end

function EncounterTimeline:OnTimelineEventFrameReleased(_viewFrame, eventFrame)
    self:CleanupReleasedEventFrame(eventFrame)
end

function EncounterTimeline:OnTimelineViewActivated(viewFrame)
    if not viewFrame then
        return
    end
    self:ApplyViewSkin(viewFrame, true)
    self:ApplyViewEventFrameSkins(viewFrame, true)
end

function EncounterTimeline:InstallSkinHooks()
    if self.skinHooksInstalled then
        return
    end
    if not _G.EventRegistry then
        return
    end

    _G.EventRegistry:RegisterCallback("EncounterTimeline.OnEventFrameAcquired", self.OnTimelineEventFrameAcquired, self)
    _G.EventRegistry:RegisterCallback("EncounterTimeline.OnEventFrameReleased", self.OnTimelineEventFrameReleased, self)
    _G.EventRegistry:RegisterCallback("EncounterTimeline.OnViewActivated", self.OnTimelineViewActivated, self)

    self.skinHooksInstalled = true
end
