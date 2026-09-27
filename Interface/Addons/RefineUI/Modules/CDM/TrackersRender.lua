----------------------------------------------------------------------------------------
-- CDM Component: TrackersRender
-- Description: Tracker styling, RefineUI-owned icon rendering, and bucket layout.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local CDM = RefineUI:GetModule("CDM")
if not CDM then
    return
end

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local type = type
local pairs = pairs
local tostring = tostring
local tconcat = table.concat
local wipe = _G.wipe or table.wipe

local CooldownFrame_Clear = CooldownFrame_Clear
local C_Spell = C_Spell
local issecretvalue = _G.issecretvalue

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local ORIENTATION_VERTICAL = "VERTICAL"
local DIRECTION_LEFT = "LEFT"
local DIRECTION_RIGHT = "RIGHT"
local DIRECTION_UP = "UP"
local DIRECTION_DOWN = "DOWN"
local DIRECTION_CENTERED = "CENTERED"
local RADIAL_BUCKET = CDM.RADIAL_BUCKET
local RADIAL_TEXT_POSITION_ABOVE = "ABOVE"
local RADIAL_TEXT_POSITION_BELOW = "BELOW"
local DEFAULT_ICON_BASE_SIZE = 44
local RADIAL_BASE_SIZE = 512
local PLACEHOLDER_ICON = 134400
local PLACEHOLDER_KEY = 0
local TRACKER_SWIPE_OVERLAY_INSET = 2
local TRACKER_SWIPE_FRAMELEVEL_OFFSET = 20
local TRACKER_COOLDOWN_TEXT_SIZE = 22
local RADIAL_BACKGROUND_ALPHA = 0.1
local RADIAL_TEXT_GAP = 10
local EXTERNAL_REFRESH_TIMER_KEY = CDM:BuildKey("Refresh", "External")

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function HasValue(value)
    if IsSecret(value) then
        return true
    end
    return value ~= nil
end

local function GetMediaTexture(key)
    local textures = RefineUI.Media and RefineUI.Media.Textures
    local texture = type(textures) == "table" and textures[key] or nil
    if type(texture) == "string" and texture ~= "" then
        return texture
    end
    return nil
end

local function GetRefineCooldownSwipeTexture()
    return GetMediaTexture("CooldownSwipe") or GetMediaTexture("CooldownSwipeSmall")
end

local function BuildRenderPrimitive(value, defaultToken)
    if IsSecret(value) then
        return nil
    end
    if value == nil then
        return defaultToken
    end
    local valueType = type(value)
    if valueType == "number" or valueType == "string" or valueType == "boolean" then
        return tostring(value)
    end
    return nil
end

local contentTokenParts = {}
local function AddTokenPart(label, value, defaultToken)
    local token = BuildRenderPrimitive(value, defaultToken)
    if token then
        contentTokenParts[#contentTokenParts + 1] = label .. token
    end
end

local function BuildEntryContentToken(entry, layoutToken)
    wipe(contentTokenParts)
    contentTokenParts[1] = layoutToken
    AddTokenPart("id:", entry.cooldownID, "0")
    AddTokenPart("icon:", entry.icon, "nil")
    contentTokenParts[#contentTokenParts + 1] = HasValue(entry.duration) and "dur_obj:1" or "dur_obj:0"
    AddTokenPart("start:", entry.cooldownStartTime, "nil")
    AddTokenPart("dur:", entry.cooldownDuration, "nil")
    AddTokenPart("mod:", entry.cooldownModRate, "nil")
    AddTokenPart("border:", entry.borderColorToken, "nil")
    AddTokenPart("font:", entry.fontColorToken, "nil")
    return tconcat(contentTokenParts, ";")
end

local function ComputeIconOffset(index, count, iconSize, spacing, orientation, direction)
    local step = iconSize + spacing
    local anchoredOffset = (index - 1) * step
    local centeredOffset = anchoredOffset - (((count - 1) * step) / 2)

    if orientation == ORIENTATION_VERTICAL then
        if direction == DIRECTION_CENTERED then
            return 0, -centeredOffset
        end
        if direction == DIRECTION_DOWN then
            return 0, -anchoredOffset
        end
        return 0, anchoredOffset
    end

    if direction == DIRECTION_CENTERED then
        return centeredOffset, 0
    end
    if direction == DIRECTION_LEFT then
        return -anchoredOffset, 0
    end
    return anchoredOffset, 0
end

local function SetScaledSize(frame, size)
    local scaled = RefineUI:Scale(size)
    frame:SetSize(scaled, scaled)
end

local function PlaceSlot(slot, frame, size, scale, x, y)
    SetScaledSize(slot, size)
    slot:SetScale(scale)
    slot:ClearAllPoints()
    slot:SetPoint("CENTER", frame, "CENTER", RefineUI:Scale(x), RefineUI:Scale(y))
end

-- The RefineUI-owned icon and radial displays only show sources Blizzard does not
-- track: trinkets, racials, consumables, and Edit Mode previews. Their timers are
-- readable, so they are set directly.
local function ApplyCooldownPayload(cooldown, entry)
    local hasDurationObject = HasValue(entry.duration)
    local hasWindow = HasValue(entry.cooldownStartTime) and HasValue(entry.cooldownDuration)

    cooldown:SetUseAuraDisplayTime(false)
    if hasDurationObject then
        cooldown:SetCooldownFromDurationObject(entry.duration)
    elseif hasWindow
        and not IsSecret(entry.cooldownStartTime)
        and not IsSecret(entry.cooldownDuration)
        and entry.cooldownDuration > 0
    then
        cooldown:SetCooldown(entry.cooldownStartTime, entry.cooldownDuration, entry.cooldownModRate or 1)
    else
        CooldownFrame_Clear(cooldown)
    end
end

local function BuildStaticEntry(cooldownID, icon)
    return {
        cooldownID = cooldownID,
        icon = icon,
    }
end

local function DecorateEntry(entry)
    local cooldownID = entry.cooldownID
    entry.borderColorToken = cooldownID and CDM:GetCooldownBorderColorToken(cooldownID) or nil
    entry.fontColorToken = cooldownID and CDM:GetCooldownFontColorToken(cooldownID) or nil
    return entry
end

local function RenderRefineIcon(icon, entry)
    local contentToken = BuildEntryContentToken(entry, "icon")
    if CDM:StateGet(icon, "trackerContentToken") == contentToken then
        return
    end

    CDM:ApplyTrackerCooldownSkin(icon, icon.Cooldown)
    icon.Icon:SetTexture(HasValue(entry.icon) and entry.icon or PLACEHOLDER_ICON)
    CDM:ApplyTrackerIconVisual(icon, entry.cooldownID)
    ApplyCooldownPayload(icon.Cooldown, entry)
    CDM:ApplyTrackerCooldownTextVisual(icon.Cooldown, entry.cooldownID)
    CDM:StateSet(icon, "trackerContentToken", contentToken)
end

local function RenderRefineRadial(display, entry, bucketCfg)
    local layoutToken = "radial:" .. tostring(bucketCfg.ShowDurationText) .. ":" .. tostring(bucketCfg.TextSize) .. ":" .. tostring(bucketCfg.TextPosition)
    local contentToken = BuildEntryContentToken(entry, layoutToken)
    if CDM:StateGet(display, "trackerContentToken") == contentToken then
        return
    end

    local cooldownID = entry.cooldownID
    local color = cooldownID and CDM:GetCooldownBorderColor(cooldownID) or CDM:GetDefaultBorderColor()
    local textColor = cooldownID and CDM:GetCooldownFontColor(cooldownID) or CDM:GetDefaultFontColor()
    CDM:ApplyRadialTrackerSkin(display, display.Cooldown, display.Background, color, textColor, bucketCfg)
    ApplyCooldownPayload(display.Cooldown, entry)
    CDM:StateSet(display, "trackerContentToken", contentToken)
end

local function GetRefineSlots(frame)
    local slots = frame.refineSlots
    if not slots then
        slots = {}
        frame.refineSlots = slots
    end
    return slots
end

local function GetExternalEntry(cooldownID)
    local payload = CDM:GetExternalCooldownPayload(cooldownID)
    return payload and DecorateEntry(payload) or nil
end

local function GetEditModeEntry(cooldownID)
    local info = CDM:GetCooldownInfo(cooldownID)
    local spellID = CDM:ResolveCooldownSpellID(info)
    local icon = spellID and C_Spell.GetSpellTexture(spellID) or nil
    return DecorateEntry(BuildStaticEntry(cooldownID, icon))
end

local function RenderBucketRefineSlots(frame, bucket, ids, inEditMode)
    local refineSlots = GetRefineSlots(frame)
    wipe(refineSlots)

    local _, _, _, _, bucketCfg = CDM:GetTrackerVisualSettings(bucket)
    local iconIndex = 0
    for n = 1, #ids do
        local cooldownID = ids[n]
        local entry
        if CDM:IsExternalCooldownID(cooldownID) then
            entry = GetExternalEntry(cooldownID)
        elseif inEditMode and not CDM:GetBlizzardTrackerItem(cooldownID) then
            entry = GetEditModeEntry(cooldownID)
        end

        if entry then
            if bucket == RADIAL_BUCKET then
                local display = CDM:EnsureRadialTrackerDisplay(frame)
                RenderRefineRadial(display, entry, bucketCfg)
                refineSlots[cooldownID] = display
                break
            end
            iconIndex = iconIndex + 1
            local icon = CDM:EnsureTrackerIcon(frame, iconIndex)
            RenderRefineIcon(icon, entry)
            refineSlots[cooldownID] = icon
        end
    end

    if #ids == 0 and inEditMode then
        local entry = BuildStaticEntry(nil, PLACEHOLDER_ICON)
        if bucket == RADIAL_BUCKET then
            local display = CDM:EnsureRadialTrackerDisplay(frame)
            RenderRefineRadial(display, entry, bucketCfg)
            refineSlots[PLACEHOLDER_KEY] = display
        else
            iconIndex = iconIndex + 1
            local icon = CDM:EnsureTrackerIcon(frame, iconIndex)
            RenderRefineIcon(icon, entry)
            refineSlots[PLACEHOLDER_KEY] = icon
        end
    end
end

local function HideUnusedRefineSlots(frame, usedSlots)
    local icons = frame.icons
    for i = 1, #icons do
        local icon = icons[i]
        if not usedSlots[icon] then
            icon:Hide()
        end
    end
    local display = frame.RadialDisplay
    if display and not usedSlots[display] then
        display:Hide()
    end
end

----------------------------------------------------------------------------------------
-- Public Methods: Styling
----------------------------------------------------------------------------------------
CDM.TRACKER_SWIPE_COLOR = { 0, 0, 0, 0.8 }

function CDM:ApplyTrackerCooldownSkin(iconFrame, cooldown)
    local swipeTexture = GetRefineCooldownSwipeTexture()
    local frameLevel = iconFrame:GetFrameLevel() + TRACKER_SWIPE_FRAMELEVEL_OFFSET
    local frameStrata = iconFrame:GetFrameStrata()
    local skinToken = "fill_v2:" .. tostring(swipeTexture) .. ":" .. frameStrata .. ":" .. frameLevel
    if self:StateGet(iconFrame, "trackerCooldownSkinToken") == skinToken then
        return
    end

    cooldown:ClearAllPoints()
    cooldown:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", -TRACKER_SWIPE_OVERLAY_INSET, TRACKER_SWIPE_OVERLAY_INSET)
    cooldown:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", TRACKER_SWIPE_OVERLAY_INSET, -TRACKER_SWIPE_OVERLAY_INSET)
    cooldown:SetFrameStrata(frameStrata)
    cooldown:SetFrameLevel(frameLevel)
    cooldown:SetDrawEdge(false)
    cooldown:SetDrawBling(true)
    cooldown:SetDrawSwipe(true)
    cooldown:SetReverse(true)
    local swipeColor = self.TRACKER_SWIPE_COLOR
    cooldown:SetSwipeColor(swipeColor[1], swipeColor[2], swipeColor[3], swipeColor[4])
    if swipeTexture then
        cooldown:SetSwipeTexture(swipeTexture)
    end
    local countdownText = cooldown:GetCountdownFontString()
    countdownText:ClearAllPoints()
    countdownText:SetPoint("CENTER", cooldown, "CENTER", 0, 0)
    countdownText:SetFont(RefineUI.Media.Fonts.Number, TRACKER_COOLDOWN_TEXT_SIZE, "OUTLINE")

    self:StateSet(iconFrame, "trackerCooldownSkinToken", skinToken)
end

-- Radial timers use the cooldown's own countdown text, which stays accurate when
-- Blizzard supplies secret aura timers in combat.
function CDM:ApplyRadialTrackerSkin(anchor, cooldown, background, color, textColor, bucketCfg)
    local radialTexture = GetMediaTexture("TickCircle")
    background:SetTexture(radialTexture)
    background:SetVertexColor(color[1], color[2], color[3], RADIAL_BACKGROUND_ALPHA)

    cooldown:ClearAllPoints()
    cooldown:SetAllPoints(anchor)
    cooldown:SetFrameLevel(anchor:GetFrameLevel() + 1)
    if radialTexture then
        cooldown:SetSwipeTexture(radialTexture)
    end
    cooldown:SetSwipeColor(color[1], color[2], color[3], 1)
    cooldown:SetDrawEdge(false)
    cooldown:SetDrawBling(false)
    cooldown:SetDrawSwipe(true)
    cooldown:SetReverse(false)
    cooldown:SetUseCircularEdge(false)
    cooldown:SetMinimumCountdownDuration(0)
    cooldown:SetHideCountdownNumbers(bucketCfg.ShowDurationText == false)

    local countdownText = cooldown:GetCountdownFontString()
    countdownText:ClearAllPoints()
    if bucketCfg.TextPosition == RADIAL_TEXT_POSITION_ABOVE then
        countdownText:SetPoint("BOTTOM", anchor, "TOP", 0, RADIAL_TEXT_GAP)
    elseif bucketCfg.TextPosition == RADIAL_TEXT_POSITION_BELOW then
        countdownText:SetPoint("TOP", anchor, "BOTTOM", 0, -RADIAL_TEXT_GAP)
    else
        countdownText:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    end
    countdownText:SetFont(RefineUI.Media.Fonts.Number, bucketCfg.TextSize, "OUTLINE")
    countdownText:SetTextColor(textColor[1], textColor[2], textColor[3], textColor[4] or 1)
end

----------------------------------------------------------------------------------------
-- Public Methods: Layout
----------------------------------------------------------------------------------------
function CDM:LayoutTrackerBucket(bucket)
    local frame = self.trackerFrames and self.trackerFrames[bucket]
    if not frame then
        return 0
    end

    local ids = self:GetCurrentAssignments()[bucket]
    local refineSlots = GetRefineSlots(frame)
    local viewerLive = self:IsBlizzardTrackerViewerLive()
    local slots = frame.layoutSlots or {}
    local usedSlots = frame.usedSlots or {}
    frame.layoutSlots = slots
    frame.usedSlots = usedSlots
    wipe(slots)
    wipe(usedSlots)

    for n = 1, #ids do
        local cooldownID = ids[n]
        local item = self:GetBlizzardTrackerItem(cooldownID)
        local slot = refineSlots[cooldownID]
        if item and viewerLive then
            local shown = item:IsShown()
            if not IsSecret(shown) and shown then
                slot = item
            end
        end
        if slot then
            slots[#slots + 1] = slot
        end
    end
    if #slots == 0 and refineSlots[PLACEHOLDER_KEY] then
        slots[1] = refineSlots[PLACEHOLDER_KEY]
    end

    local count = #slots
    if count == 0 then
        HideUnusedRefineSlots(frame, usedSlots)
        frame:Hide()
        return 0
    end

    local iconScale, spacing, orientation, direction = self:GetTrackerVisualSettings(bucket)
    if bucket == RADIAL_BUCKET then
        -- One radial at a time: extra active Blizzard items stay hidden behind alpha.
        local radialSize = RADIAL_BASE_SIZE * iconScale
        for i = 1, count do
            local slot = slots[i]
            slot:SetAlpha(i == 1 and 1 or 0)
        end
        local primary = slots[1]
        PlaceSlot(primary, frame, radialSize, 1, 0, 0)
        usedSlots[primary] = true
        primary:Show()
        HideUnusedRefineSlots(frame, usedSlots)
        SetScaledSize(frame, radialSize)
        frame:Show()
        return 1
    end

    local iconSize = DEFAULT_ICON_BASE_SIZE * iconScale
    for i = 1, count do
        local slot = slots[i]
        local x, y = ComputeIconOffset(i, count, iconSize, spacing, orientation, direction)
        PlaceSlot(slot, frame, DEFAULT_ICON_BASE_SIZE, iconScale, x, y)
        slot:SetAlpha(1)
        usedSlots[slot] = true
        slot:Show()
    end
    HideUnusedRefineSlots(frame, usedSlots)

    local totalSpan = (iconSize * count) + (spacing * (count - 1))
    if orientation == ORIENTATION_VERTICAL then
        frame:SetSize(RefineUI:Scale(iconSize), RefineUI:Scale(totalSpan))
    else
        frame:SetSize(RefineUI:Scale(totalSpan), RefineUI:Scale(iconSize))
    end
    frame:Show()
    return count
end

function CDM:LayoutTrackers()
    if not self.trackerFrames then
        return
    end

    local total = 0
    for i = 1, #self.TRACKER_BUCKETS do
        total = total + self:LayoutTrackerBucket(self.TRACKER_BUCKETS[i])
    end
    self.activeTrackerEntryCount = self:IsEditModeActive() and 0 or total
end

----------------------------------------------------------------------------------------
-- Public Methods: Refresh
----------------------------------------------------------------------------------------
function CDM:HideTrackers()
    self.activeTrackerEntryCount = 0
    self:ReleaseBlizzardTrackerItems()
    if not self.trackerFrames then
        return
    end

    for i = 1, #self.TRACKER_BUCKETS do
        local frame = self.trackerFrames[self.TRACKER_BUCKETS[i]]
        if frame then
            wipe(GetRefineSlots(frame))
            frame:Hide()
        end
    end
end

function CDM:InitializeTrackers()
    for i = 1, #self.TRACKER_BUCKETS do
        self:EnsureTrackerFrame(self.TRACKER_BUCKETS[i])
    end
end

function CDM:RefreshTrackers()
    local inEditMode = self:IsEditModeActive()
    local snapshot = self:GetAssignedCooldownSnapshot()
    if (inEditMode and not self:IsRefineAuraModeActive()) or (not snapshot.hasAssignments and not inEditMode) then
        self:HideTrackers()
        return
    end

    self:MapBlizzardTrackerItems()

    local assignments = self:GetCurrentAssignments()
    for i = 1, #self.TRACKER_BUCKETS do
        local bucket = self.TRACKER_BUCKETS[i]
        RenderBucketRefineSlots(self:EnsureTrackerFrame(bucket), bucket, assignments[bucket], inEditMode)
    end

    self:LayoutTrackers()
end

-- Trinket, racial, and consumable cooldown events only change RefineUI-owned
-- icons, so they skip Blizzard frame mapping and layout.
function CDM:RefreshExternalTrackerIcons()
    if not self.trackerFrames or not self:IsRefineRuntimeOwnerActive() then
        return
    end

    for bucket, frame in pairs(self.trackerFrames) do
        local _, _, _, _, bucketCfg = self:GetTrackerVisualSettings(bucket)
        for cooldownID, slot in pairs(GetRefineSlots(frame)) do
            if cooldownID ~= PLACEHOLDER_KEY and self:IsExternalCooldownID(cooldownID) then
                local entry = GetExternalEntry(cooldownID)
                if entry and bucket == RADIAL_BUCKET then
                    RenderRefineRadial(slot, entry, bucketCfg)
                elseif entry then
                    RenderRefineIcon(slot, entry)
                end
            end
        end
    end
end

function CDM:RequestExternalTrackerRefresh()
    RefineUI:After(EXTERNAL_REFRESH_TIMER_KEY, 0, function()
        CDM:RefreshExternalTrackerIcons()
    end)
end
