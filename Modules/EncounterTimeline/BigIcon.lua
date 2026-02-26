----------------------------------------------------------------------------------------
-- EncounterTimeline Component: BigIcon
-- Description: Big icon rendering, layout, cooldown visuals, and countdown audio
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
local C_Timer = C_Timer
local GetTime = GetTime
local PlaySoundFile = PlaySoundFile
local UIParent = UIParent
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local math_floor = math.floor
local math_max = math.max
local next = next
local pcall = pcall
local tonumber = tonumber
local tostring = tostring
local type = type
local issecretvalue = _G.issecretvalue
local canaccessvalue = _G.canaccessvalue
local bit_band = (bit and bit.band) or (bit32 and bit32.band)

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local BIG_ICON_TEXCOORD_MAX = 0.92
local BIG_ICON_TEXCOORD_MIN = 0.08
local DEFAULT_POINT = "CENTER"
local DEFAULT_OFFSET_X = 0
local DEFAULT_OFFSET_Y = -180
local AUDIO_COUNTDOWN_MAX = 5
local AUDIO_COUNTDOWN_MIN = 1
local BIG_ICON_REFRESH_INTERVAL = 0.05
local COOLDOWN_FONT_SIZE = 24
local EFFECT_MASK_DEADLY = 1
local EFFECT_MASK_ENRAGE = 2
local EFFECT_MASK_BLEED = 4
local EFFECT_MASK_MAGIC = 8
local EFFECT_MASK_DISEASE = 16
local EFFECT_MASK_CURSE = 32
local EFFECT_MASK_POISON = 64
local ROLE_MASK_TANK = 128
local ROLE_MASK_HEALER = 256
local ROLE_MASK_DPS = 512
local ROLE_MASK_ANY = ROLE_MASK_TANK + ROLE_MASK_HEALER + ROLE_MASK_DPS
local BIG_ICON_INDICATOR_COUNT_ROLE = 2
local BIG_ICON_INDICATOR_COUNT_OTHER = 2
local BIG_ICON_INDICATOR_MIN_SIZE = 12
local BIG_ICON_INDICATOR_SIZE_SCALE = 0.22
local BIG_ICON_INDICATOR_SPACING = 2
local BIG_ICON_INDICATOR_OFFSET_Y = 2
local BIG_ICON_ICON_MASK_ALL_FALLBACK = 1023
local BIG_ICON_ICON_MASK_OTHER_FALLBACK = 127
local QUEUED_INDICATOR_PULSE_INTERVAL_SECONDS = 1
local BIG_ICON_ICON_MASK_ORDER = {
    ROLE_MASK_TANK,
    ROLE_MASK_HEALER,
    ROLE_MASK_DPS,
    EFFECT_MASK_DEADLY,
    EFFECT_MASK_ENRAGE,
    EFFECT_MASK_BLEED,
    EFFECT_MASK_MAGIC,
    EFFECT_MASK_DISEASE,
    EFFECT_MASK_CURSE,
    EFFECT_MASK_POISON,
}

----------------------------------------------------------------------------------------
-- Position Helpers
----------------------------------------------------------------------------------------
local function ResolveRelativeFrame(relativeTo)
    if type(relativeTo) == "string" then
        return _G[relativeTo] or UIParent
    end
    return relativeTo or UIParent
end

local function ResolveBigIconDefaultPosition()
    local positions = RefineUI.Positions or {}
    local position = positions[EncounterTimeline.BIG_ICON_FRAME_NAME]
    if type(position) ~= "table" then
        return {
            point = DEFAULT_POINT,
            x = DEFAULT_OFFSET_X,
            y = DEFAULT_OFFSET_Y,
        }
    end

    return {
        point = position[1] or DEFAULT_POINT,
        x = position[4] or DEFAULT_OFFSET_X,
        y = position[5] or DEFAULT_OFFSET_Y,
    }
end

function EncounterTimeline:ApplyStoredBigIconPosition(frame)
    if not frame then
        return
    end

    local positions = RefineUI.Positions or {}
    local position = positions[self.BIG_ICON_FRAME_NAME]

    frame:ClearAllPoints()
    if type(position) == "table" then
        local point = position[1] or DEFAULT_POINT
        local relativeTo = ResolveRelativeFrame(position[2])
        local relativePoint = position[3] or point
        local x = position[4] or 0
        local y = position[5] or 0
        frame:SetPoint(point, relativeTo, relativePoint, x, y)
    else
        frame:SetPoint(DEFAULT_POINT, UIParent, DEFAULT_POINT, DEFAULT_OFFSET_X, DEFAULT_OFFSET_Y)
    end
end

function EncounterTimeline:SaveBigIconPosition(point, x, y)
    RefineUI.Positions = RefineUI.Positions or {}
    RefineUI.Positions[self.BIG_ICON_FRAME_NAME] = { point, "UIParent", point, x, y }
end

----------------------------------------------------------------------------------------
-- Slot Helpers
----------------------------------------------------------------------------------------
local function SetScaledSize(frame, width, height)
    if not frame then
        return
    end

    if frame.Size then
        frame:Size(width, height)
    else
        frame:SetSize(RefineUI:Scale(width), RefineUI:Scale(height))
    end
end

local function ClearCooldown(cooldown)
    if not cooldown then
        return
    end

    if cooldown.Clear then
        cooldown:Clear()
    else
        cooldown:SetCooldown(0, 0)
    end
end

local function ClearCooldownText(fontString)
    if not fontString or type(fontString.SetText) ~= "function" then
        return
    end
    pcall(fontString.SetText, fontString, "")
end

local function SetCooldownBuiltinNumbersHidden(cooldown, hidden)
    if not cooldown or type(cooldown.SetHideCountdownNumbers) ~= "function" then
        return
    end
    pcall(cooldown.SetHideCountdownNumbers, cooldown, hidden == true)
end

local function ApplyCooldownTextStyle(cooldown)
    if not cooldown then
        return
    end

    if cooldown.SetMinimumCountdownDuration then
        pcall(cooldown.SetMinimumCountdownDuration, cooldown, 0)
    end
    if cooldown.SetCountdownFont and RefineUI.Media and RefineUI.Media.Fonts and RefineUI.Media.Fonts.Number then
        pcall(cooldown.SetCountdownFont, cooldown, RefineUI.Media.Fonts.Number)
    end

    if type(cooldown.GetRegions) == "function" then
        local regions = { cooldown:GetRegions() }
        for index = 1, #regions do
            local region = regions[index]
            if region and type(region.GetObjectType) == "function" and region:GetObjectType() == "FontString" then
                RefineUI.Font(region, COOLDOWN_FONT_SIZE, RefineUI.Media.Fonts.Number, "OUTLINE", true)
            end
        end
    end
end

local function ApplyManualCooldownTextStyle(fontString)
    if not fontString then
        return
    end

    RefineUI.Font(fontString, COOLDOWN_FONT_SIZE, RefineUI.Media.Fonts.Number, "OUTLINE", true)
    if type(fontString.GetFont) == "function" and type(fontString.SetFont) == "function" then
        local okFont, fontPath = pcall(fontString.GetFont, fontString)
        if not okFont or type(fontPath) ~= "string" or fontPath == "" then
            local fallbackFont = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
            pcall(fontString.SetFont, fontString, fallbackFont, RefineUI:Scale(COOLDOWN_FONT_SIZE), "OUTLINE")
        end
    end
    if fontString.SetJustifyH then
        fontString:SetJustifyH("CENTER")
    end
    if fontString.SetJustifyV then
        fontString:SetJustifyV("MIDDLE")
    end
end

local function GetCountdownSwipeTexture()
    local media = RefineUI.Media
    local textures = media and media.Textures
    if type(textures) ~= "table" then
        return nil
    end
    return textures.CooldownSwipe or textures.CooldownSwipeSmall
end

local function ApplyCooldownSwipeStyle(cooldown)
    if not cooldown then
        return
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
    if cooldown.SetUseCircularEdge then
        pcall(cooldown.SetUseCircularEdge, cooldown, false)
    end

    local swipeTexture = GetCountdownSwipeTexture()
    if swipeTexture and cooldown.SetSwipeTexture then
        pcall(cooldown.SetSwipeTexture, cooldown, swipeTexture)
    end
    if cooldown.SetSwipeColor then
        pcall(cooldown.SetSwipeColor, cooldown, 0, 0, 0, 0.85)
    end
    if cooldown.SetAlpha then
        pcall(cooldown.SetAlpha, cooldown, 1)
    end
end

local function ResetBigIconSlotCooldown(slot, hideCooldown)
    if not slot then
        return
    end

    local cooldown = slot.Cooldown
    if cooldown then
        ClearCooldown(cooldown)
        SetCooldownBuiltinNumbersHidden(cooldown, false)
        if hideCooldown and cooldown.Hide then
            pcall(cooldown.Hide, cooldown)
        end
    end

    if slot.CooldownText then
        ClearCooldownText(slot.CooldownText)
    end

    slot.CooldownTimerApplied = nil
    slot.CooldownTimerEventID = nil
end

local function ResetQueuedIndicatorVisualState(queuedIndicator)
    if not queuedIndicator then
        return
    end

    if queuedIndicator.ShowAnimation and queuedIndicator.ShowAnimation.Stop then
        pcall(queuedIndicator.ShowAnimation.Stop, queuedIndicator.ShowAnimation)
    end

    if queuedIndicator.HideAnimation and queuedIndicator.HideAnimation.Stop then
        pcall(queuedIndicator.HideAnimation.Stop, queuedIndicator.HideAnimation)
    end

    local dot1 = queuedIndicator.Dot1
    local dot2 = queuedIndicator.Dot2
    local dot3 = queuedIndicator.Dot3

    if dot2 then
        dot2:ClearAllPoints()
        dot2:SetPoint("CENTER")
    end

    if dot1 then
        dot1:ClearAllPoints()
        if dot2 then
            dot1:SetPoint("RIGHT", dot2, "LEFT")
        else
            dot1:SetPoint("CENTER")
        end
    end

    if dot3 then
        dot3:ClearAllPoints()
        if dot2 then
            dot3:SetPoint("LEFT", dot2, "RIGHT")
        else
            dot3:SetPoint("CENTER")
        end
    end
end

local function CancelBigIconQueuedIndicatorTicker(slot)
    if not slot then
        return
    end

    local ticker = slot.QueuedIndicatorTicker
    if ticker and type(ticker.Cancel) == "function" then
        pcall(ticker.Cancel, ticker)
    end
    slot.QueuedIndicatorTicker = nil
end

local function PlayBigIconQueuedIndicatorPulse(slot)
    if not slot or not slot.QueuedIndicator then
        return
    end

    local queuedIndicator = slot.QueuedIndicator
    ResetQueuedIndicatorVisualState(queuedIndicator)
    local showAnimation = queuedIndicator.ShowAnimation
    if showAnimation and type(showAnimation.Play) == "function" then
        queuedIndicator:Show()
        pcall(showAnimation.Play, showAnimation)
        return
    end

    if type(queuedIndicator.AnimateShow) == "function" then
        if queuedIndicator.IsShown and queuedIndicator:IsShown() then
            queuedIndicator:Hide()
        end
        pcall(queuedIndicator.AnimateShow, queuedIndicator)
        return
    end

    queuedIndicator:Show()
end

local function EnsureBigIconQueuedIndicatorTicker(slot)
    if not slot or slot.QueuedIndicatorTicker then
        return
    end
    if not C_Timer or type(C_Timer.NewTicker) ~= "function" then
        return
    end

    slot.QueuedIndicatorTicker = C_Timer.NewTicker(QUEUED_INDICATOR_PULSE_INTERVAL_SECONDS, function()
        if slot.QueuedIndicatorShown ~= true then
            return
        end
        PlayBigIconQueuedIndicatorPulse(slot)
    end)
end

local function HideBigIconQueuedIndicator(slot, immediate)
    if not slot or not slot.QueuedIndicator then
        return
    end

    CancelBigIconQueuedIndicatorTicker(slot)

    local queuedIndicator = slot.QueuedIndicator
    local isShown = (queuedIndicator.IsShown and queuedIndicator:IsShown()) and true or false
    if slot.QueuedIndicatorShown ~= true and not isShown then
        return
    end

    slot.QueuedIndicatorShown = false
    if immediate == true then
        ResetQueuedIndicatorVisualState(queuedIndicator)
        queuedIndicator:Hide()
        return
    end

    if type(queuedIndicator.AnimateHide) == "function" then
        pcall(queuedIndicator.AnimateHide, queuedIndicator)
    else
        ResetQueuedIndicatorVisualState(queuedIndicator)
        queuedIndicator:Hide()
    end
end

local function ShowBigIconQueuedIndicator(slot)
    if not slot or not slot.QueuedIndicator then
        return
    end

    local queuedIndicator = slot.QueuedIndicator
    if slot.QueuedIndicatorShown == true then
        if queuedIndicator.IsShown and not queuedIndicator:IsShown() then
            queuedIndicator:Show()
        end
        EnsureBigIconQueuedIndicatorTicker(slot)
        return
    end

    slot.QueuedIndicatorShown = true
    PlayBigIconQueuedIndicatorPulse(slot)
    EnsureBigIconQueuedIndicatorTicker(slot)
end

local function GetDefaultBorderColor()
    local color = RefineUI.Config and RefineUI.Config.General and RefineUI.Config.General.BorderColor
    if type(color) == "table" then
        return color[1] or 0.6, color[2] or 0.6, color[3] or 0.6, color[4] or 1
    end
    return 0.6, 0.6, 0.6, 1
end

local function ResolveCenteredOffset(index, slotCount, step)
    return ((index - 1) * step) - (((slotCount - 1) * step) / 2)
end

local function ResolveBigIconSlotOffset(index, slotCount, step, orientation, direction)
    local orientationTokens = EncounterTimeline.BIG_ICON_ORIENTATION or {}
    local directionTokens = EncounterTimeline.BIG_ICON_GROW_DIRECTION or {}
    local isVertical = (orientation == orientationTokens.VERTICAL)

    if isVertical then
        if direction == directionTokens.DOWN then
            return 0, -((index - 1) * step)
        end
        if direction == directionTokens.CENTERED then
            return 0, ResolveCenteredOffset(index, slotCount, step)
        end
        return 0, ((index - 1) * step)
    end

    if direction == directionTokens.LEFT then
        return -((index - 1) * step), 0
    end
    if direction == directionTokens.CENTERED then
        return ResolveCenteredOffset(index, slotCount, step), 0
    end
    return ((index - 1) * step), 0
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

local function GetSafeFrameLevel(frame, fallback)
    local safeFallback = type(fallback) == "number" and fallback or 0
    if not frame or type(frame.GetFrameLevel) ~= "function" then
        return safeFallback
    end

    local ok, value = pcall(frame.GetFrameLevel, frame)
    if not ok or IsUnreadableValue(value) or type(value) ~= "number" then
        return safeFallback
    end

    return value
end

local function GetSafeFrameStrata(frame, fallback)
    local safeFallback = (type(fallback) == "string" and fallback ~= "") and fallback or "MEDIUM"
    if not frame or type(frame.GetFrameStrata) ~= "function" then
        return safeFallback
    end

    local ok, value = pcall(frame.GetFrameStrata, frame)
    if not ok or IsUnreadableValue(value) or type(value) ~= "string" or value == "" then
        return safeFallback
    end

    return value
end

local function CopyValidEventIDList(eventIDs, validator)
    local copy = {}
    if type(eventIDs) ~= "table" then
        return copy
    end

    for index = 1, #eventIDs do
        local eventID = eventIDs[index]
        if validator(eventID) then
            copy[#copy + 1] = eventID
        end
    end

    return copy
end

local function HasValue(value)
    if value == nil then
        return false
    end
    if IsUnreadableValue(value) then
        return true
    end
    if type(RefineUI.HasValue) == "function" then
        return RefineUI:HasValue(value)
    end
    return true
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

local function IsEditModeActive()
    local lib = RefineUI.LibEditMode
    if not lib or type(lib.IsInEditMode) ~= "function" then
        return false
    end

    local ok, inEditMode = pcall(lib.IsInEditMode, lib)
    if not ok or IsUnreadableValue(inEditMode) or type(inEditMode) ~= "boolean" then
        return false
    end

    return inEditMode
end

local function ApplyIconTexture(textureRegion, textureToken)
    if not textureRegion or not HasValue(textureToken) then
        return false
    end

    local ok = pcall(textureRegion.SetTexture, textureRegion, textureToken)
    return ok and true or false
end

local function GetBigIconIndicatorMasks()
    local roleMask = ROLE_MASK_ANY
    local otherMask = BIG_ICON_ICON_MASK_OTHER_FALLBACK
    local allMask = BIG_ICON_ICON_MASK_ALL_FALLBACK

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

        local allMaskValue = iconMasks.EncounterTimelineAllIcons
        if type(allMaskValue) == "number" and not IsUnreadableValue(allMaskValue) then
            allMask = allMaskValue
        end
    end

    return roleMask, otherMask, allMask
end

local function HasIndicatorTexturePayload(textureRegion)
    if not textureRegion then
        return false
    end

    if type(textureRegion.GetAtlas) == "function" then
        local okAtlas, atlas = pcall(textureRegion.GetAtlas, textureRegion)
        if okAtlas and HasValue(atlas) then
            if IsUnreadableValue(atlas) then
                return true
            end
            if type(atlas) ~= "string" or atlas ~= "" then
                return true
            end
        end
    end

    if type(textureRegion.GetTexture) == "function" then
        local okTexture, textureToken = pcall(textureRegion.GetTexture, textureRegion)
        if okTexture and HasValue(textureToken) then
            if IsUnreadableValue(textureToken) then
                return true
            end
            if type(textureToken) ~= "string" or textureToken ~= "" then
                return true
            end
        end
    end

    return false
end

local function IsRenderableIndicatorTexture(textureRegion)
    if not textureRegion then
        return false
    end

    return HasIndicatorTexturePayload(textureRegion)
end

----------------------------------------------------------------------------------------
-- Frame Setup
----------------------------------------------------------------------------------------
function EncounterTimeline:EnsureBigIconFrame()
    if self.bigIconFrame then
        return self.bigIconFrame
    end

    local frame = CreateFrame("Frame", self.BIG_ICON_FRAME_NAME, UIParent)
    RefineUI:AddAPI(frame)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(220)
    frame:EnableMouse(false)
    frame.Slots = {}

    self:ApplyStoredBigIconPosition(frame)
    SetScaledSize(frame, 1, 1)

    frame:Hide()
    self.bigIconFrame = frame
    return frame
end

function EncounterTimeline:CreateBigIconSlot(slotIndex)
    local frame = self:EnsureBigIconFrame()
    if not frame then
        return nil
    end

    frame.Slots = frame.Slots or {}
    local slot = frame.Slots[slotIndex]
    if slot then
        return slot
    end

    slot = CreateFrame("Frame", nil, frame)
    RefineUI:AddAPI(slot)
    slot:SetFrameStrata(GetSafeFrameStrata(frame, "DIALOG"))
    slot:SetFrameLevel(GetSafeFrameLevel(frame, 220) + 2)
    RefineUI.SetTemplate(slot, "Icon")
    RefineUI.CreateBorder(slot, 4, 4, 12)

    slot.IconTexture = slot:CreateTexture(nil, "ARTWORK")
    RefineUI.SetInside(slot.IconTexture, slot, 1, 1)
    slot.IconTexture:SetTexCoord(BIG_ICON_TEXCOORD_MIN, BIG_ICON_TEXCOORD_MAX, BIG_ICON_TEXCOORD_MIN, BIG_ICON_TEXCOORD_MAX)

    slot.IndicatorContainer = CreateFrame("Frame", nil, slot)
    slot.IndicatorContainer:SetFrameStrata(GetSafeFrameStrata(slot, "DIALOG"))
    slot.IndicatorContainer:SetFrameLevel(GetSafeFrameLevel(slot, 0) + 6)
    slot.IndicatorContainer:EnableMouse(false)
    slot.IndicatorContainer:SetPoint("BOTTOM", slot, "TOP", 0, BIG_ICON_INDICATOR_OFFSET_Y)
    SetScaledSize(slot.IndicatorContainer, 1, 1)

    slot.IndicatorRoleIcons = {}
    slot.IndicatorOtherIcons = {}
    slot.IndicatorAllIcons = {}

    for index = 1, BIG_ICON_INDICATOR_COUNT_ROLE do
        local texture = slot.IndicatorContainer:CreateTexture(nil, "OVERLAY", nil, 3)
        slot.IndicatorRoleIcons[index] = texture
        slot.IndicatorAllIcons[#slot.IndicatorAllIcons + 1] = texture
    end

    for index = 1, BIG_ICON_INDICATOR_COUNT_OTHER do
        local texture = slot.IndicatorContainer:CreateTexture(nil, "OVERLAY", nil, 3)
        slot.IndicatorOtherIcons[index] = texture
        slot.IndicatorAllIcons[#slot.IndicatorAllIcons + 1] = texture
    end

    slot.Cooldown = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
    slot.Cooldown:SetAllPoints(slot.IconTexture)
    slot.Cooldown:SetFrameStrata(GetSafeFrameStrata(slot, "DIALOG"))
    slot.Cooldown:SetFrameLevel(GetSafeFrameLevel(slot, 0) + 5)
    slot.Cooldown:EnableMouse(false)
    slot.Cooldown:SetAlpha(1)
    SetCooldownBuiltinNumbersHidden(slot.Cooldown, false)
    ApplyCooldownSwipeStyle(slot.Cooldown)

    ApplyCooldownTextStyle(slot.Cooldown)
    slot.CooldownText = slot.Cooldown:CreateFontString(nil, "OVERLAY")
    slot.CooldownText:SetPoint("CENTER", slot.Cooldown, "CENTER", 0, 0)
    ApplyManualCooldownTextStyle(slot.CooldownText)

    slot.QueuedIndicator = CreateFrame("Frame", nil, slot, "EncounterTimelineQueuedIconContainerTemplate")
    if slot.QueuedIndicator then
        slot.QueuedIndicator:SetFrameStrata(GetSafeFrameStrata(slot, "DIALOG"))
        slot.QueuedIndicator:SetFrameLevel(GetSafeFrameLevel(slot, 0) + 7)
        slot.QueuedIndicator:EnableMouse(false)
        slot.QueuedIndicator:ClearAllPoints()
        slot.QueuedIndicator:SetPoint("CENTER", slot, "CENTER", 0, 0)
        slot.QueuedIndicator:Hide()
    end
    slot.QueuedIndicatorShown = false

    slot:Hide()

    frame.Slots[slotIndex] = slot
    return slot
end

function EncounterTimeline:HideBigIconSlots(fromIndex)
    local frame = self.bigIconFrame
    if not frame or type(frame.Slots) ~= "table" then
        return
    end

    local start = tonumber(fromIndex) or 1
    for index = start, #frame.Slots do
        local slot = frame.Slots[index]
        if slot then
            ResetBigIconSlotCooldown(slot, true)
            HideBigIconQueuedIndicator(slot, true)
            self:ClearBigIconIndicators(slot)
            slot:Hide()
        end
    end
end

function EncounterTimeline:IsQueuedTrackEvent(eventID)
    if not self:IsValidEventID(eventID) then
        return false
    end

    local queuedTrack = _G.Enum and _G.Enum.EncounterTimelineTrack and _G.Enum.EncounterTimelineTrack.Queued
    if type(queuedTrack) ~= "number" then
        return false
    end

    local track = nil
    if C_EncounterTimeline and type(C_EncounterTimeline.GetEventTrack) == "function" then
        local okTrack, trackValue = pcall(C_EncounterTimeline.GetEventTrack, eventID)
        if okTrack and not IsUnreadableValue(trackValue) then
            track = trackValue
        end
    end

    if track == nil then
        local eventFrame = self:GetEventFrameByEventID(eventID)
        if eventFrame and type(eventFrame.eventID) == "number" and eventFrame.eventID ~= eventID then
            eventFrame = nil
        end

        if eventFrame and type(eventFrame.GetEventTrack) == "function" then
            local okFrameTrack, frameTrack = pcall(eventFrame.GetEventTrack, eventFrame)
            if okFrameTrack and not IsUnreadableValue(frameTrack) then
                track = frameTrack
            end
        elseif eventFrame and not IsUnreadableValue(eventFrame.eventTrack) then
            track = eventFrame.eventTrack
        end
    end

    return track == queuedTrack
end

function EncounterTimeline:ShouldShowQueuedBigIconIndicator(eventID)
    if not self:IsQueuedTrackEvent(eventID) then
        return false
    end

    local timeRemaining = self:ResolveEventTimeRemaining(eventID)
    if type(timeRemaining) == "number" and timeRemaining > 0 then
        return false
    end

    return true
end

function EncounterTimeline:ClearBigIconIndicators(slot)
    if not slot then
        return
    end

    local allIndicators = slot.IndicatorAllIcons
    if type(allIndicators) == "table" then
        for index = 1, #allIndicators do
            local texture = allIndicators[index]
            if texture then
                texture:ClearAllPoints()
                pcall(texture.SetAtlas, texture, nil)
                pcall(texture.SetTexture, texture, nil)
                texture:SetShown(false)
            end
        end
    end

    if slot.IndicatorContainer then
        slot.IndicatorContainer:Hide()
    end
end

function EncounterTimeline:LayoutBigIconIndicators(slot)
    if not slot or not slot.IndicatorContainer then
        return
    end

    local visibleIndicators = {}
    local allIndicators = slot.IndicatorAllIcons
    if type(allIndicators) ~= "table" then
        slot.IndicatorContainer:Hide()
        return
    end

    for index = 1, #allIndicators do
        local texture = allIndicators[index]
        if IsRenderableIndicatorTexture(texture) then
            visibleIndicators[#visibleIndicators + 1] = texture
        else
            texture:SetShown(false)
        end
    end

    if #visibleIndicators == 0 then
        slot.IndicatorContainer:Hide()
        return
    end

    local bigIconSize = self:GetConfig().BigIconSize
    local indicatorSize = BIG_ICON_INDICATOR_MIN_SIZE
    if type(bigIconSize) == "number" and bigIconSize > 0 then
        local scaledSize = math_floor((bigIconSize * BIG_ICON_INDICATOR_SIZE_SCALE) + 0.5)
        indicatorSize = math_max(BIG_ICON_INDICATOR_MIN_SIZE, scaledSize)
    end

    local rowWidth = (#visibleIndicators * indicatorSize) + ((#visibleIndicators - 1) * BIG_ICON_INDICATOR_SPACING)
    SetScaledSize(slot.IndicatorContainer, rowWidth, indicatorSize)
    slot.IndicatorContainer:ClearAllPoints()
    slot.IndicatorContainer:SetPoint("BOTTOM", slot, "TOP", 0, BIG_ICON_INDICATOR_OFFSET_Y)

    for index = 1, #visibleIndicators do
        local texture = visibleIndicators[index]
        SetScaledSize(texture, indicatorSize, indicatorSize)
        texture:ClearAllPoints()
        if index == 1 then
            texture:SetPoint("LEFT", slot.IndicatorContainer, "LEFT", 0, 0)
        else
            texture:SetPoint("LEFT", visibleIndicators[index - 1], "RIGHT", BIG_ICON_INDICATOR_SPACING, 0)
        end
        texture:SetShown(true)
    end

    slot.IndicatorContainer:Show()
end

function EncounterTimeline:GetBigIconWantedIconMask(eventID)
    if not self:IsValidEventID(eventID) then
        return nil
    end

    local eventFrame = self:GetEventFrameByEventID(eventID)
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

function EncounterTimeline:ApplyBigIconIndicators(slot, eventID)
    if not slot then
        return
    end

    if not self:IsValidEventID(eventID)
        or not C_EncounterTimeline
        or type(C_EncounterTimeline.SetEventIconTextures) ~= "function"
        or type(slot.IndicatorRoleIcons) ~= "table"
        or type(slot.IndicatorOtherIcons) ~= "table" then
        self:ClearBigIconIndicators(slot)
        return
    end

    self:ClearBigIconIndicators(slot)

    local iconMask = nil
    if type(self.ResolveEventIconMask) == "function" then
        local okMask, resolvedMask = pcall(self.ResolveEventIconMask, self, nil, eventID, nil)
        if okMask and type(resolvedMask) == "number" and not IsUnreadableValue(resolvedMask) then
            iconMask = resolvedMask
        end
    end

    if type(iconMask) == "number" and bit_band and type(slot.IndicatorAllIcons) == "table" then
        local assignedCount = 0
        for index = 1, #BIG_ICON_ICON_MASK_ORDER do
            local maskBit = BIG_ICON_ICON_MASK_ORDER[index]
            local okHasBit, hasBit = pcall(function()
                return bit_band(iconMask, maskBit) ~= 0
            end)
            if okHasBit and hasBit == true then
                local targetTexture = slot.IndicatorAllIcons[assignedCount + 1]
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
            self:LayoutBigIconIndicators(slot)
            return
        end
    end

    local roleMask, otherMask, allMask = GetBigIconIndicatorMasks()
    local wantedMask = self:GetBigIconWantedIconMask(eventID)
    if type(wantedMask) == "number" and not IsUnreadableValue(wantedMask) and bit_band then
        local okRole, filteredRoleMask = pcall(bit_band, roleMask, wantedMask)
        if okRole and type(filteredRoleMask) == "number" then
            roleMask = filteredRoleMask
        end

        local okOther, filteredOtherMask = pcall(bit_band, otherMask, wantedMask)
        if okOther and type(filteredOtherMask) == "number" then
            otherMask = filteredOtherMask
        end
    end

    local okRole = pcall(C_EncounterTimeline.SetEventIconTextures, eventID, roleMask, slot.IndicatorRoleIcons)
    local okOther = pcall(C_EncounterTimeline.SetEventIconTextures, eventID, otherMask, slot.IndicatorOtherIcons)

    if (not okRole or not okOther) and type(allMask) == "number" and type(slot.IndicatorAllIcons) == "table" then
        local okAll = pcall(C_EncounterTimeline.SetEventIconTextures, eventID, allMask, slot.IndicatorAllIcons)
        if not okAll and not okRole and not okOther then
            self:ClearBigIconIndicators(slot)
            return
        end
    elseif not okRole and not okOther then
        self:ClearBigIconIndicators(slot)
        return
    end

    self:LayoutBigIconIndicators(slot)
end

function EncounterTimeline:ApplyBigIconSlotBorder(slot, eventID)
    if not slot then
        return
    end

    if self:IsValidEventID(eventID) and type(self.ApplyEventColorBorder) == "function" then
        self:ApplyEventColorBorder({
            IconContainer = slot,
        }, eventID)
        return
    end

    local borderFrame = slot.border or slot.RefineBorder
    if borderFrame and type(borderFrame.SetBackdropBorderColor) == "function" then
        local r, g, b, a = GetDefaultBorderColor()
        borderFrame:SetBackdropBorderColor(r, g, b, a)
    end
end

function EncounterTimeline:LayoutBigIconSlots(slotCount)
    local frame = self.bigIconFrame
    if not frame then
        return
    end

    if type(slotCount) ~= "number" or slotCount <= 0 then
        SetScaledSize(frame, 1, 1)
        return
    end

    local config = self:GetConfig()
    local size = config.BigIconSize
    local spacing = config.BigIconSpacing
    local orientation = config.BigIconOrientation
    local growDirection = config.BigIconGrowDirection
    local step = size + spacing

    local minX, maxX = 0, 0
    local minY, maxY = 0, 0

    for index = 1, slotCount do
        local x, y = ResolveBigIconSlotOffset(index, slotCount, step, orientation, growDirection)

        if x < minX then
            minX = x
        end
        if x > maxX then
            maxX = x
        end
        if y < minY then
            minY = y
        end
        if y > maxY then
            maxY = y
        end
    end

    local totalWidth = (maxX - minX) + size
    local totalHeight = (maxY - minY) + size
    SetScaledSize(frame, totalWidth, totalHeight)

    for index = 1, slotCount do
        local slot = self:CreateBigIconSlot(index)
        if slot then
            local x, y = ResolveBigIconSlotOffset(index, slotCount, step, orientation, growDirection)
            slot:ClearAllPoints()
            if slot.Point then
                slot:Point("BOTTOMLEFT", frame, "BOTTOMLEFT", x - minX, y - minY)
            else
                slot:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", RefineUI:Scale(x - minX), RefineUI:Scale(y - minY))
            end
            SetScaledSize(slot, size, size)
        end
    end
end

----------------------------------------------------------------------------------------
-- Edit Mode
----------------------------------------------------------------------------------------
function EncounterTimeline:RegisterBigIconEditModeFrame()
    if self.bigIconEditModeFrameRegistered then
        return
    end
    if not RefineUI.LibEditMode or type(RefineUI.LibEditMode.AddFrame) ~= "function" then
        return
    end

    local frame = self:EnsureBigIconFrame()
    if not frame then
        return
    end

    local default = ResolveBigIconDefaultPosition()
    RefineUI.LibEditMode:AddFrame(frame, function(targetFrame, _, point, x, y)
        targetFrame:ClearAllPoints()
        targetFrame:SetPoint(point, UIParent, point, x, y)
        EncounterTimeline:SaveBigIconPosition(point, x, y)
    end, default, "Encounter Timeline Big Icon")

    if type(self.AttachBigIconEditModeSettings) == "function" then
        self:AttachBigIconEditModeSettings(frame)
    end

    self.bigIconEditModeFrameRegistered = true
end

function EncounterTimeline:RegisterBigIconEditModeCallbacks()
    if self.bigIconEditModeCallbacksRegistered then
        return
    end
    if not RefineUI.LibEditMode or type(RefineUI.LibEditMode.RegisterCallback) ~= "function" then
        return
    end

    RefineUI.LibEditMode:RegisterCallback("enter", function()
        EncounterTimeline.bigIconPreviewActive = true
        C_Timer.After(0, function()
            EncounterTimeline:RefreshBigIconVisualState()
            EncounterTimeline:UpdateBigIconSchedulerState()
        end)
    end)

    RefineUI.LibEditMode:RegisterCallback("exit", function()
        EncounterTimeline.bigIconPreviewActive = nil
        C_Timer.After(0, function()
            EncounterTimeline:RefreshBigIconVisualState()
            EncounterTimeline:UpdateBigIconSchedulerState()
        end)
    end)

    self.bigIconEditModeCallbacksRegistered = true
end

----------------------------------------------------------------------------------------
-- Event Resolution
----------------------------------------------------------------------------------------
function EncounterTimeline:ResolveBigIconTextureFromEventFrame(eventFrame, eventID)
    if not eventFrame or not eventFrame.IconContainer or not eventFrame.IconContainer.IconTexture then
        return nil
    end

    local ok, textureToken = pcall(eventFrame.IconContainer.IconTexture.GetTexture, eventFrame.IconContainer.IconTexture)
    if not ok or not HasValue(textureToken) then
        return nil
    end

    if self:IsValidEventID(eventID) then
        self:SetEventMetadataField(eventID, "bigIconTextureToken", textureToken)
    end

    return textureToken
end

function EncounterTimeline:ResolveBigIconTextureFromEventFrameInfo(eventFrame, eventID)
    if not eventFrame or type(eventFrame.GetEventInfo) ~= "function" then
        return nil
    end

    local okInfo, eventInfo = pcall(eventFrame.GetEventInfo, eventFrame)
    if not okInfo or not HasValue(eventInfo) then
        return nil
    end

    local okIcon, iconFileID = pcall(function(info)
        return info.iconFileID
    end, eventInfo)
    if not okIcon or not HasValue(iconFileID) then
        return nil
    end

    if self:IsValidEventID(eventID) then
        self:SetEventMetadataField(eventID, "bigIconTextureToken", iconFileID)
    end

    return iconFileID
end

function EncounterTimeline:ResolveBigIconTextureFromEventInfo(eventID)
    if not self:IsValidEventID(eventID) then
        return nil
    end
    if not C_EncounterTimeline or type(C_EncounterTimeline.GetEventInfo) ~= "function" then
        return nil
    end

    local ok, eventInfo = pcall(C_EncounterTimeline.GetEventInfo, eventID)
    if not ok or not HasValue(eventInfo) then
        return nil
    end

    if not IsUnreadableValue(eventInfo) and type(eventInfo) == "table" then
        self:UpdateEventMetadataFromInfo(eventID, eventInfo)
    end

    local okIcon, iconFileID = pcall(function(info)
        return info.iconFileID
    end, eventInfo)
    if not okIcon or not HasValue(iconFileID) then
        return nil
    end

    self:SetEventMetadataField(eventID, "bigIconTextureToken", iconFileID)
    return iconFileID
end

function EncounterTimeline:ResolveBigIconTexture(eventID)
    local eventFrame = self:GetEventFrameByEventID(eventID)
    local frameTexture = self:ResolveBigIconTextureFromEventFrame(eventFrame, eventID)
    if HasValue(frameTexture) then
        return frameTexture
    end

    local frameInfoTexture = self:ResolveBigIconTextureFromEventFrameInfo(eventFrame, eventID)
    if HasValue(frameInfoTexture) then
        return frameInfoTexture
    end

    local infoTexture = self:ResolveBigIconTextureFromEventInfo(eventID)
    if HasValue(infoTexture) then
        return infoTexture
    end

    local metadata = self:GetEventMetadata(eventID)
    if type(metadata) == "table" and HasValue(metadata.bigIconTextureToken) then
        return metadata.bigIconTextureToken
    end

    return nil
end

function EncounterTimeline:ResolveEventTimeRemaining(eventID)
    if not self:IsValidEventID(eventID) then
        return nil
    end

    if C_EncounterTimeline and type(C_EncounterTimeline.GetEventTimeRemaining) == "function" then
        local ok, timeRemaining = pcall(C_EncounterTimeline.GetEventTimeRemaining, eventID)
        if ok and not IsUnreadableValue(timeRemaining) and type(timeRemaining) == "number" then
            return timeRemaining
        end
    end

    local eventFrame = self:GetEventFrameByEventID(eventID)
    if eventFrame and type(eventFrame.GetEventTimeRemaining) == "function" then
        local okFrame, frameRemaining = pcall(eventFrame.GetEventTimeRemaining, eventFrame)
        if okFrame and not IsUnreadableValue(frameRemaining) and type(frameRemaining) == "number" then
            return frameRemaining
        end
    end

    if C_EncounterTimeline and type(C_EncounterTimeline.GetEventTimer) == "function" then
        local okTimer, durationObject = pcall(C_EncounterTimeline.GetEventTimer, eventID)
        if okTimer and HasValue(durationObject) and type(durationObject.GetRemainingDuration) == "function" then
            local okDuration, durationRemaining = pcall(durationObject.GetRemainingDuration, durationObject)
            if okDuration and not IsUnreadableValue(durationRemaining) and type(durationRemaining) == "number" then
                return durationRemaining
            end
        end
    end

    return nil
end

function EncounterTimeline:GetEventSourceCountdownFrame(eventID)
    if not self:IsValidEventID(eventID) then
        return nil
    end

    local eventFrame = self:GetEventFrameByEventID(eventID)
    if not eventFrame then
        return nil
    end

    if type(eventFrame.GetCountdownFrame) == "function" then
        local okCountdown, countdown = pcall(eventFrame.GetCountdownFrame, eventFrame)
        if okCountdown and countdown then
            return countdown
        end
    end

    if eventFrame.Countdown then
        return eventFrame.Countdown
    end

    return nil
end

function EncounterTimeline:ApplyBigIconTimerFromSourceCountdown(slot, eventID)
    if not slot or not slot.Cooldown or not self:IsValidEventID(eventID) then
        return false
    end

    local sourceCountdown = self:GetEventSourceCountdownFrame(eventID)
    if not sourceCountdown then
        return false
    end

    local textApplied = false

    if type(sourceCountdown.GetCountdownFontString) == "function" then
        local okFontString, sourceFontString = pcall(sourceCountdown.GetCountdownFontString, sourceCountdown)
        if okFontString and sourceFontString and type(sourceFontString.GetText) == "function" then
            local okText, displayText = pcall(sourceFontString.GetText, sourceFontString)
            if okText and HasValue(displayText) then
                if type(displayText) == "string" and displayText == "" then
                    return false
                end
                if type(RefineUI.SetFontStringValue) == "function" then
                    textApplied = RefineUI:SetFontStringValue(slot.CooldownText, displayText, { emptyText = "" }) and true or false
                else
                    local okSetText = pcall(slot.CooldownText.SetText, slot.CooldownText, displayText)
                    textApplied = okSetText and true or false
                end
            end
        end
    end

    return textApplied
end

function EncounterTimeline:ApplyBigIconTimerFromSourceCountdownTimes(slot, eventID)
    if not slot or not slot.Cooldown or not self:IsValidEventID(eventID) then
        return false
    end

    local sourceCountdown = self:GetEventSourceCountdownFrame(eventID)
    if not sourceCountdown then
        return false
    end

    if type(sourceCountdown.GetCooldownTimes) ~= "function" or type(slot.Cooldown.SetCooldown) ~= "function" then
        return false
    end

    local okTimes, startTimeMS, durationMS = pcall(sourceCountdown.GetCooldownTimes, sourceCountdown)
    if not okTimes then
        return false
    end

    if IsUnreadableValue(startTimeMS) or IsUnreadableValue(durationMS) then
        return false
    end

    if type(startTimeMS) ~= "number" or type(durationMS) ~= "number" then
        return false
    end

    local startTimeSeconds = startTimeMS / 1000
    local durationSeconds = durationMS / 1000
    if durationSeconds <= 0 then
        return false
    end

    local okApply = pcall(slot.Cooldown.SetCooldown, slot.Cooldown, startTimeSeconds, durationSeconds)
    return okApply and true or false
end

function EncounterTimeline:ApplyBigIconTimerToSlot(slot, eventID)
    if not slot or not slot.Cooldown then
        return
    end
    if not self:IsValidEventID(eventID) then
        ResetBigIconSlotCooldown(slot, true)
        HideBigIconQueuedIndicator(slot, true)
        return
    end

    local cooldown = slot.Cooldown
    local timerApplied = false
    local sourceTextApplied = false
    local reuseExistingCooldown = (slot.CooldownTimerApplied == true and slot.CooldownTimerEventID == eventID)

    if self:ShouldShowQueuedBigIconIndicator(eventID) then
        ResetBigIconSlotCooldown(slot, true)
        ShowBigIconQueuedIndicator(slot)
        return
    end

    HideBigIconQueuedIndicator(slot, true)

    sourceTextApplied = self:ApplyBigIconTimerFromSourceCountdown(slot, eventID) and true or false

    if reuseExistingCooldown then
        timerApplied = true
    end

    if not timerApplied
        and C_EncounterTimeline
        and type(C_EncounterTimeline.GetEventTimeRemaining) == "function"
        and cooldown.SetCooldownDuration then
        local okRemaining, timeRemaining = pcall(C_EncounterTimeline.GetEventTimeRemaining, eventID)
        if okRemaining and HasValue(timeRemaining) then
            local okApply = pcall(cooldown.SetCooldownDuration, cooldown, timeRemaining)
            timerApplied = okApply and true or false
        end
    end

    if not timerApplied
        and C_EncounterTimeline
        and type(C_EncounterTimeline.GetEventTimer) == "function"
        and cooldown.SetCooldownFromDurationObject then
        local okTimer, durationObject = pcall(C_EncounterTimeline.GetEventTimer, eventID)
        if okTimer and HasValue(durationObject) then
            local okApply = pcall(cooldown.SetCooldownFromDurationObject, cooldown, durationObject)
            timerApplied = okApply and true or false
        end
    end

    if not timerApplied then
        timerApplied = self:ApplyBigIconTimerFromSourceCountdownTimes(slot, eventID) and true or false
    end

    if not timerApplied then
        if C_EncounterTimeline and type(C_EncounterTimeline.GetEventTimeRemaining) == "function" and cooldown.SetCooldown then
            local okRemaining, timeRemaining = pcall(C_EncounterTimeline.GetEventTimeRemaining, eventID)
            if okRemaining and HasValue(timeRemaining) then
                local okApply = pcall(cooldown.SetCooldown, cooldown, GetTime(), timeRemaining)
                timerApplied = okApply and true or false
            end
        end
    end

    if not timerApplied then
        ResetBigIconSlotCooldown(slot, true)
        return
    end

    slot.CooldownTimerApplied = true
    slot.CooldownTimerEventID = eventID

    ApplyCooldownSwipeStyle(cooldown)

    if cooldown.Show then
        pcall(cooldown.Show, cooldown)
    end

    if sourceTextApplied then
        SetCooldownBuiltinNumbersHidden(cooldown, true)
        return
    end

    local timeRemaining = self:ResolveEventTimeRemaining(eventID)
    if type(timeRemaining) == "number" and timeRemaining > 0 then
        local okSeconds, roundedSeconds = pcall(math.ceil, timeRemaining)
        if okSeconds and type(roundedSeconds) == "number" and roundedSeconds > 0 then
            SetCooldownBuiltinNumbersHidden(cooldown, true)
            if type(RefineUI.SetFontStringValue) == "function" then
                RefineUI:SetFontStringValue(slot.CooldownText, tostring(roundedSeconds), { emptyText = "" })
            else
                pcall(slot.CooldownText.SetText, slot.CooldownText, tostring(roundedSeconds))
            end
            return
        end
    end

    SetCooldownBuiltinNumbersHidden(cooldown, false)
    ClearCooldownText(slot.CooldownText)
end

function EncounterTimeline:GetSortedVisibleEventIDs(maxDuration)
    if not C_EncounterTimeline or type(C_EncounterTimeline.GetSortedEventList) ~= "function" then
        local cached = CopyValidEventIDList(self.bigIconLastSortedEventIDs, function(eventID)
            return self:IsValidEventID(eventID)
        end)
        if #cached > 0 then
            return cached
        end
        return {}
    end

    local ok, events = pcall(C_EncounterTimeline.GetSortedEventList, nil, maxDuration, true, true)
    if ok and not IsUnreadableValue(events) and type(events) == "table" then
        local filtered = {}
        for index = 1, #events do
            local eventID = events[index]
            if self:IsValidEventID(eventID) then
                filtered[#filtered + 1] = eventID
            end
        end

        self.bigIconLastSortedEventIDs = filtered
        return filtered
    end

    local cached = CopyValidEventIDList(self.bigIconLastSortedEventIDs, function(eventID)
        return self:IsValidEventID(eventID)
    end)
    if #cached > 0 then
        return cached
    end

    local mappedFallback = {}
    local mappedFrames = self.eventFramesByEventID
    if type(mappedFrames) == "table" then
        for eventID, eventFrame in next, mappedFrames do
            local shown = GetShownState(eventFrame)
            local isVisible = (shown ~= false)
            if isVisible and self:IsValidEventID(eventID) then
                mappedFallback[#mappedFallback + 1] = eventID
            end
        end
    end

    if #mappedFallback > 0 and type(maxDuration) == "number" and maxDuration > 0 then
        local thresholdFiltered = {}
        for index = 1, #mappedFallback do
            local eventID = mappedFallback[index]
            local timeRemaining = self:ResolveEventTimeRemaining(eventID)
            if type(timeRemaining) ~= "number" or timeRemaining <= maxDuration then
                thresholdFiltered[#thresholdFiltered + 1] = eventID
            end
        end
        mappedFallback = thresholdFiltered
    end

    self.bigIconLastSortedEventIDs = CopyValidEventIDList(mappedFallback, function(eventID)
        if self:IsValidEventID(eventID) then
            return true
        end
        return false
    end)

    return CopyValidEventIDList(self.bigIconLastSortedEventIDs, function(eventID)
        return self:IsValidEventID(eventID)
    end)
end

function EncounterTimeline:GetBigIconCandidateEventIDs()
    if not self:CanProcessVisibleTimelineEvents() then
        return {}
    end

    local threshold = self:GetConfig().BigIconThresholdSeconds
    return self:GetSortedVisibleEventIDs(threshold)
end

----------------------------------------------------------------------------------------
-- Big Icon Render
----------------------------------------------------------------------------------------
function EncounterTimeline:RenderBigIconEvents(eventIDs, previewOnly)
    local frame = self:EnsureBigIconFrame()
    if not frame then
        return
    end

    local config = self:GetConfig()
    local renderedCount = 0

    if previewOnly then
        local slot = self:CreateBigIconSlot(1)
        if slot then
            ApplyIconTexture(slot.IconTexture, config.BigIconIconFallback)
            ResetBigIconSlotCooldown(slot, true)
            HideBigIconQueuedIndicator(slot, true)
            self:ClearBigIconIndicators(slot)
            self:ApplyBigIconSlotBorder(slot, nil)
            slot:Show()
            renderedCount = 1
        end
        self:SetActiveBigIconEventIDs({})
    else
        self:SetActiveBigIconEventIDs(eventIDs)
        for index = 1, #eventIDs do
            local eventID = eventIDs[index]
            if self:IsValidEventID(eventID) then
                local slotIndex = renderedCount + 1
                local slot = self:CreateBigIconSlot(slotIndex)
                if slot then
                    local resolvedTexture = self:ResolveBigIconTexture(eventID)
                    local applied = false
                    if HasValue(resolvedTexture) then
                        applied = ApplyIconTexture(slot.IconTexture, resolvedTexture)
                    end

                    if not applied then
                        local metadata = self:GetEventMetadata(eventID)
                        local cachedTexture = type(metadata) == "table" and metadata.bigIconTextureToken or nil
                        if HasValue(cachedTexture) then
                            applied = ApplyIconTexture(slot.IconTexture, cachedTexture)
                        end
                    end

                    if not applied then
                        ResetBigIconSlotCooldown(slot, true)
                        HideBigIconQueuedIndicator(slot, true)
                        self:ClearBigIconIndicators(slot)
                        slot:Hide()
                    else
                        self:ApplyBigIconTimerToSlot(slot, eventID)
                        self:ApplyBigIconIndicators(slot, eventID)
                        self:ApplyBigIconSlotBorder(slot, eventID)
                        slot:Show()
                        renderedCount = renderedCount + 1
                    end
                end
            end
        end
    end

    self:HideBigIconSlots(renderedCount + 1)

    if renderedCount > 0 then
        self:LayoutBigIconSlots(renderedCount)
        frame:Show()
    else
        self:HideBigIcon()
    end
end

function EncounterTimeline:HideBigIcon()
    self:SetActiveBigIconEventIDs({})

    local frame = self.bigIconFrame
    if not frame then
        return
    end

    self:HideBigIconSlots(1)
    frame:Hide()
end

function EncounterTimeline:RefreshBigIconVisualState()
    local config = self:GetConfig()
    if config.BigIconEnable ~= true then
        self:HideBigIcon()
        return
    end

    local frame = self:EnsureBigIconFrame()
    if not frame then
        return
    end

    self:RegisterBigIconEditModeFrame()
    self:RegisterBigIconEditModeCallbacks()
    self:ApplyStoredBigIconPosition(frame)

    if not IsEditModeActive() then
        self.bigIconPreviewActive = nil
    end

    local events = self:GetBigIconCandidateEventIDs()
    if #events > 0 then
        self:RenderBigIconEvents(events, false)
        return
    end

    if self.bigIconPreviewActive then
        self:RenderBigIconEvents({}, true)
    else
        self:HideBigIcon()
    end
end

function EncounterTimeline:ShowBigIconForEvent(eventID)
    if self:IsValidEventID(eventID) then
        self.audioLatestEventID = eventID
    end
    self:RefreshBigIconVisualState()
end

----------------------------------------------------------------------------------------
-- Audio Countdown
----------------------------------------------------------------------------------------
function EncounterTimeline:PlayBigIconCountdownSecond(second)
    local config = self:GetConfig()
    if config.AudioCountdownEnable ~= true then
        return
    end

    local key = config.AudioCountdownVoicePrefix .. tostring(second)
    local sounds = RefineUI.Media and RefineUI.Media.Sounds
    local soundFile = sounds and sounds[key]
    if type(soundFile) ~= "string" or soundFile == "" then
        return
    end

    PlaySoundFile(soundFile, config.AudioCountdownChannel)
end

function EncounterTimeline:GetPlayerRoleMask()
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")
    if role == "TANK" then
        return ROLE_MASK_TANK
    elseif role == "HEALER" then
        return ROLE_MASK_HEALER
    elseif role == "DAMAGER" then
        return ROLE_MASK_DPS
    end
    return 0
end

function EncounterTimeline:ResolveAudioEventMetadata(eventID)
    if not self:IsValidEventID(eventID) then
        return {}
    end

    local metadata = self:ResolveTimelineEventMetadata(eventID)
    if type(metadata) ~= "table" then
        metadata = {}
    end

    if not HasValue(metadata.iconMask) and type(self.ResolveEventIconMask) == "function" then
        metadata.iconMask = self:ResolveEventIconMask(nil, eventID, nil)
    end

    return metadata
end

function EncounterTimeline:PassesAudioSourceFilter(metadata)
    local config = self:GetConfig()
    local sourceFilter = config.AudioCountdownSourceFilter
    if sourceFilter == self.AUDIO_SOURCE_FILTER.ALL then
        return true
    end

    local sourceToken = metadata and metadata.sourceToken
    if type(sourceToken) ~= "string" then
        return false
    end

    if sourceFilter == self.AUDIO_SOURCE_FILTER.ENCOUNTER then
        return sourceToken == self.AUDIO_SOURCE_FILTER.ENCOUNTER
    elseif sourceFilter == self.AUDIO_SOURCE_FILTER.SCRIPT then
        return sourceToken == self.AUDIO_SOURCE_FILTER.SCRIPT
    end

    return true
end

function EncounterTimeline:PassesAudioSeverityFilter(metadata)
    local config = self:GetConfig()
    local severity = metadata and metadata.severity
    if type(severity) ~= "number" then
        local policy = config.AudioCountdownUnknownSeverityPolicy
        if policy == self.AUDIO_UNKNOWN_SEVERITY_POLICY.INCLUDE then
            return true
        elseif policy == self.AUDIO_UNKNOWN_SEVERITY_POLICY.AS_MEDIUM then
            return config.AudioCountdownSeverityMedium == true
        end
        return false
    end

    local low = _G.Enum and _G.Enum.EncounterEventSeverity and _G.Enum.EncounterEventSeverity.Low or 0
    local medium = _G.Enum and _G.Enum.EncounterEventSeverity and _G.Enum.EncounterEventSeverity.Medium or 1
    local high = _G.Enum and _G.Enum.EncounterEventSeverity and _G.Enum.EncounterEventSeverity.High or 2

    if severity == low then
        return config.AudioCountdownSeverityLow == true
    elseif severity == medium then
        return config.AudioCountdownSeverityMedium == true
    elseif severity == high then
        return config.AudioCountdownSeverityHigh == true
    end

    return false
end

function EncounterTimeline:PassesAudioRoleFilter(metadata)
    local config = self:GetConfig()
    if config.AudioCountdownRoleFilterEnabled ~= true then
        return true
    end
    if not bit_band then
        return false
    end

    local iconMask = metadata and metadata.iconMask
    local roleMask = (type(iconMask) == "number") and bit_band(iconMask, ROLE_MASK_ANY) or 0
    if roleMask == 0 then
        return config.AudioCountdownIncludeRoleless == true
    end

    local playerRoleMask = self:GetPlayerRoleMask()
    if playerRoleMask == 0 then
        return false
    end

    return bit_band(roleMask, playerRoleMask) ~= 0
end

function EncounterTimeline:ShouldAllowAudioCountdownForEvent(eventID, metadata)
    if not self:IsValidEventID(eventID) then
        return false
    end
    if not self:PassesAudioSourceFilter(metadata) then
        return false
    end
    if not self:PassesAudioSeverityFilter(metadata) then
        return false
    end
    if not self:PassesAudioRoleFilter(metadata) then
        return false
    end
    return true
end

function EncounterTimeline:GetAudioCountdownSecondToPlay(eventID, timeRemaining)
    if type(timeRemaining) ~= "number" then
        return nil
    end

    for second = AUDIO_COUNTDOWN_MAX, AUDIO_COUNTDOWN_MIN, -1 do
        if timeRemaining <= second and timeRemaining > (second - 1) then
            if not self:HasPlayedAudioSecond(eventID, second) then
                return second
            end
            break
        end
    end

    return nil
end

function EncounterTimeline:CollectAudioCountdownCandidates()
    local config = self:GetConfig()
    if config.AudioCountdownEnable ~= true then
        return {}
    end

    local eventIDs = self:GetActiveBigIconEventIDs()
    if type(eventIDs) ~= "table" or #eventIDs == 0 then
        eventIDs = self:GetSortedVisibleEventIDs(AUDIO_COUNTDOWN_MAX)
    end

    local candidates = {}
    for index = 1, #eventIDs do
        local eventID = eventIDs[index]
        local timeRemaining = self:ResolveEventTimeRemaining(eventID)
        if type(timeRemaining) == "number" and timeRemaining > 0 and timeRemaining <= AUDIO_COUNTDOWN_MAX then
            local metadata = self:ResolveAudioEventMetadata(eventID)
            if self:ShouldAllowAudioCountdownForEvent(eventID, metadata) then
                candidates[#candidates + 1] = {
                    eventID = eventID,
                    timeRemaining = timeRemaining,
                }
            end
        end
    end

    table.sort(candidates, function(a, b)
        if a.timeRemaining ~= b.timeRemaining then
            return a.timeRemaining < b.timeRemaining
        end
        return a.eventID < b.eventID
    end)

    return candidates
end

function EncounterTimeline:SelectAudioCountdownCandidate(candidates)
    if type(candidates) ~= "table" or #candidates == 0 then
        return nil
    end

    local config = self:GetConfig()
    if config.AudioCountdownMode == self.AUDIO_COUNTDOWN_MODE.LATEST_WINS then
        local latestID = self.audioLatestEventID
        if self:IsValidEventID(latestID) then
            for index = 1, #candidates do
                local candidate = candidates[index]
                if candidate.eventID == latestID then
                    return candidate
                end
            end
        end
    end

    return candidates[1]
end

function EncounterTimeline:EvaluateBigIconAudioCountdown()
    local config = self:GetConfig()
    if config.AudioCountdownEnable ~= true then
        return
    end
    if not self:IsBigIconContextActive() then
        return
    end

    local candidates = self:CollectAudioCountdownCandidates()
    local candidate = self:SelectAudioCountdownCandidate(candidates)
    if not candidate then
        return
    end

    local second = self:GetAudioCountdownSecondToPlay(candidate.eventID, candidate.timeRemaining)
    if not second then
        return
    end

    self:PlayBigIconCountdownSecond(second)
    self:MarkAudioSecondPlayed(candidate.eventID, second)
end

----------------------------------------------------------------------------------------
-- Scheduler
----------------------------------------------------------------------------------------
function EncounterTimeline:IsBigIconContextActive()
    if self.bigIconPreviewActive then
        return true
    end

    local config = self:GetConfig()
    if config.BigIconEnable ~= true then
        return false
    end

    if self:IsTimelineVisible() then
        return true
    end

    local active = self:GetActiveBigIconEventIDs()
    return type(active) == "table" and #active > 0
end

function EncounterTimeline:RegisterBigIconRefreshJob()
    if self.bigIconRefreshJobRegistered then
        return
    end
    if type(RefineUI.RegisterUpdateJob) ~= "function" then
        return
    end

    local jobKey = self:BuildKey("BigIcon", "Refresh")
    local ok = RefineUI:RegisterUpdateJob(jobKey, BIG_ICON_REFRESH_INTERVAL, function()
        EncounterTimeline:OnBigIconRefreshTick()
    end, {
        enabled = false,
    })

    if ok then
        self.bigIconRefreshJobKey = jobKey
        self.bigIconRefreshJobRegistered = true
    end
end

function EncounterTimeline:OnBigIconRefreshTick()
    if not self:IsEnabled() then
        self:HideBigIcon()
        if self.bigIconRefreshJobKey and type(RefineUI.SetUpdateJobEnabled) == "function" then
            RefineUI:SetUpdateJobEnabled(self.bigIconRefreshJobKey, false, false)
        end
        return
    end

    if not self:IsBigIconContextActive() then
        self:HideBigIcon()
        if self.bigIconRefreshJobKey and type(RefineUI.SetUpdateJobEnabled) == "function" then
            RefineUI:SetUpdateJobEnabled(self.bigIconRefreshJobKey, false, false)
        end
        return
    end

    self:RefreshBigIconVisualState()
    self:EvaluateBigIconAudioCountdown()
end

function EncounterTimeline:UpdateBigIconSchedulerState()
    self:RegisterBigIconRefreshJob()
    if not self.bigIconRefreshJobKey or type(RefineUI.SetUpdateJobEnabled) ~= "function" then
        return
    end

    local shouldEnable = self:IsEnabled() and self:IsBigIconContextActive()
    RefineUI:SetUpdateJobEnabled(self.bigIconRefreshJobKey, shouldEnable, false)

    if shouldEnable and type(RefineUI.RunUpdateJobNow) == "function" then
        RefineUI:RunUpdateJobNow(self.bigIconRefreshJobKey)
    end
end

----------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------
function EncounterTimeline:InitializeBigIcon()
    self:RegisterBigIconEditModeCallbacks()
    self:RegisterBigIconRefreshJob()
end
