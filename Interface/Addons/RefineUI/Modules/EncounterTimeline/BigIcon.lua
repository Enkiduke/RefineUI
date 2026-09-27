----------------------------------------------------------------------------------------
-- EncounterTimeline Component: BigIcon
-- Description: Big icons for timeline events inside the configured threshold
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local EncounterTimeline = RefineUI:GetModule("EncounterTimeline")

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local C_EncounterTimeline = C_EncounterTimeline
local CreateFrame = CreateFrame
local UIParent = UIParent
local hooksecurefunc = hooksecurefunc
local math_floor = math.floor
local math_max = math.max

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local TEXCOORD_MIN = 0.08
local TEXCOORD_MAX = 0.92
local FRAME_LEVEL = 220
local SLOT_LEVEL = FRAME_LEVEL + 2
local COOLDOWN_FONT_SIZE = 24
local COOLDOWN_OFFSET = 2
local INDICATORS_PER_GROUP = 2
local INDICATOR_MIN_SIZE = 12
local INDICATOR_SIZE_SCALE = 0.22
local INDICATOR_SPACING = 2
local INDICATOR_OFFSET_Y = 2
local MIN_REFRESH_DELAY = 0.05
local REFRESH_TIMER_KEY = "EncounterTimeline:BigIconRefresh"
local ACTIVE_STATE = Enum.EncounterTimelineEventState.Active
local QUEUED_TRACK = Enum.EncounterTimelineTrack.Queued
local ROLE_ICON_MASK = Constants.EncounterTimelineIconMasks.EncounterTimelineRoleIcons
local OTHER_ICON_MASK = Constants.EncounterTimelineIconMasks.EncounterTimelineOtherIcons

-- Membership and state changes arrive as events; threshold crossings use a timer.
local REFRESH_EVENTS = {
    "ENCOUNTER_TIMELINE_VIEW_ACTIVATED",
    "ENCOUNTER_TIMELINE_VIEW_DEACTIVATED",
    "ENCOUNTER_TIMELINE_EVENT_ADDED",
    "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED",
    "ENCOUNTER_TIMELINE_EVENT_TRACK_CHANGED",
    "ENCOUNTER_TIMELINE_EVENT_REMOVED",
}

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
local bigIconFrame
local slots = {}
local shownCount = 0
local previewActive = false

----------------------------------------------------------------------------------------
-- Slots
----------------------------------------------------------------------------------------
local function CreateIndicatorGroup(slot, size)
    local group = {}
    for index = 1, INDICATORS_PER_GROUP do
        local texture = slot.Indicators:CreateTexture(nil, "OVERLAY", nil, 3)
        texture:SetSize(size, size)
        local previous = slot.IndicatorTextures[#slot.IndicatorTextures]
        if previous then
            texture:SetPoint("LEFT", previous, "RIGHT", INDICATOR_SPACING, 0)
        else
            texture:SetPoint("LEFT", slot.Indicators, "LEFT", 0, 0)
        end
        group[index] = texture
        slot.IndicatorTextures[#slot.IndicatorTextures + 1] = texture
    end
    return group
end

local function CreateSlot(index)
    local config = EncounterTimeline:GetConfig()
    local size = config.BigIconSize

    local slot = CreateFrame("Frame", nil, bigIconFrame)
    RefineUI:AddAPI(slot)
    slot:SetFrameLevel(SLOT_LEVEL)
    slot:Size(size, size)
    RefineUI.SetTemplate(slot, "Icon")
    RefineUI.CreateBorder(slot, 6, 6, 16):SetBackdropBorderColor(1, 0, 0, 1)

    local icon = slot:CreateTexture(nil, "ARTWORK")
    RefineUI.SetInside(icon, slot, 1, 1)
    icon:SetTexCoord(TEXCOORD_MIN, TEXCOORD_MAX, TEXCOORD_MIN, TEXCOORD_MAX)
    slot.Icon = icon

    -- SetEventIconTextures drives visibility through (secret) alpha, like Blizzard's fixed indicator grid.
    local indicatorSize = math_max(INDICATOR_MIN_SIZE, math_floor((size * INDICATOR_SIZE_SCALE) + 0.5))
    local indicatorCount = INDICATORS_PER_GROUP * 2
    slot.Indicators = CreateFrame("Frame", nil, slot)
    slot.Indicators:SetFrameLevel(SLOT_LEVEL + 6)
    slot.Indicators:SetPoint("BOTTOM", slot, "TOP", 0, INDICATOR_OFFSET_Y)
    slot.Indicators:SetSize(RefineUI:Scale((indicatorCount * indicatorSize) + ((indicatorCount - 1) * INDICATOR_SPACING)), RefineUI:Scale(indicatorSize))
    slot.IndicatorTextures = {}
    slot.RoleIndicators = CreateIndicatorGroup(slot, RefineUI:Scale(indicatorSize))
    slot.OtherIndicators = CreateIndicatorGroup(slot, RefineUI:Scale(indicatorSize))

    local cooldown = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
    cooldown:SetPoint("TOPLEFT", icon, "TOPLEFT", -COOLDOWN_OFFSET, COOLDOWN_OFFSET)
    cooldown:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", COOLDOWN_OFFSET, -COOLDOWN_OFFSET)
    cooldown:SetFrameLevel(SLOT_LEVEL + 5)
    cooldown:SetDrawEdge(false)
    cooldown:SetDrawBling(false)
    cooldown:SetDrawSwipe(true)
    cooldown:SetUseCircularEdge(false)
    cooldown:SetSwipeTexture(RefineUI.Media.Textures.CooldownSwipe)
    cooldown:SetSwipeColor(0, 0, 0, 0.85)
    cooldown:SetHideCountdownNumbers(false)
    cooldown:SetMinimumCountdownDuration(0)
    RefineUI.Font(cooldown:GetCountdownFontString(), COOLDOWN_FONT_SIZE, RefineUI.Media.Fonts.Number, "OUTLINE", true)
    slot.Cooldown = cooldown

    local queued = CreateFrame("Frame", nil, slot, "EncounterTimelineQueuedIconContainerTemplate")
    queued:SetFrameLevel(SLOT_LEVEL + 7)
    queued:SetPoint("CENTER")
    queued.ShowAnimation:SetLooping("REPEAT")
    queued:Hide()
    slot.Queued = queued

    slot:Hide()
    slots[index] = slot
    return slot
end

local function HideQueued(slot)
    slot.Queued.ShowAnimation:Stop()
    slot.Queued:Hide()
end

local function ResetSlot(slot)
    slot.eventID = nil
    slot.state = nil
    slot.queued = nil
    slot.Cooldown:Clear()
    HideQueued(slot)
    slot:Hide()
end

local function UpdateSlot(slot, eventID, remaining)
    if slot.eventID ~= eventID then
        slot.eventID = eventID
        slot.state = nil
        slot.Icon:SetTexture(C_EncounterTimeline.GetEventInfo(eventID).iconFileID)
        slot.Indicators:Show()
        C_EncounterTimeline.SetEventIconTextures(eventID, ROLE_ICON_MASK, slot.RoleIndicators)
        C_EncounterTimeline.SetEventIconTextures(eventID, OTHER_ICON_MASK, slot.OtherIndicators)
    end
    slot:Show()

    local state = C_EncounterTimeline.GetEventState(eventID)
    local queued = remaining <= 0 and C_EncounterTimeline.GetEventTrack(eventID) == QUEUED_TRACK
    if slot.state == state and slot.queued == queued then
        return
    end
    slot.state = state
    slot.queued = queued

    if queued then
        slot.Cooldown:Clear()
        if not slot.Queued:IsShown() then
            slot.Queued:Show()
            slot.Queued.ShowAnimation:Play()
        end
        return
    end

    HideQueued(slot)
    if state == ACTIVE_STATE then
        slot.Cooldown:SetCooldownDuration(remaining)
    else
        slot.Cooldown:Clear()
    end
end

----------------------------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------------------------
local function LayoutSlots(count)
    local config = EncounterTimeline:GetConfig()
    local size = config.BigIconSize
    local step = size + config.BigIconSpacing
    local vertical = config.BigIconOrientation == "VERTICAL"
    local reverse = config.BigIconGrowDirection == (vertical and "DOWN" or "LEFT")
    local length = ((count - 1) * step) + size

    if vertical then
        bigIconFrame:Size(size, length)
    else
        bigIconFrame:Size(length, size)
    end

    for index = 1, count do
        local offset = reverse and ((count - index) * step) or ((index - 1) * step)
        local slot = slots[index]
        slot:ClearAllPoints()
        if vertical then
            slot:Point("BOTTOMLEFT", bigIconFrame, "BOTTOMLEFT", 0, offset)
        else
            slot:Point("BOTTOMLEFT", bigIconFrame, "BOTTOMLEFT", offset, 0)
        end
    end
end

local function SetShownCount(count)
    for index = count + 1, shownCount do
        ResetSlot(slots[index])
    end

    if count > 0 and count ~= shownCount then
        LayoutSlots(count)
    end
    shownCount = count
    bigIconFrame:SetShown(count > 0)
end

local function ShowPreview()
    local slot = slots[1] or CreateSlot(1)
    ResetSlot(slot)
    slot.Icon:SetTexture(EncounterTimeline:GetConfig().BigIconIconFallback)
    slot.Indicators:Hide()
    slot:Show()
    SetShownCount(1)
end

----------------------------------------------------------------------------------------
-- Refresh
----------------------------------------------------------------------------------------
local function RefreshBigIcon()
    local count = 0
    local nextRefresh

    if _G.EncounterTimeline:IsShown() then
        local threshold = EncounterTimeline:GetConfig().BigIconThresholdSeconds
        local eventIDs = C_EncounterTimeline.GetSortedEventList(nil, nil, true, true)
        -- Sorted by remaining time, so the first event past the threshold is the next to enter.
        for index = 1, #eventIDs do
            local eventID = eventIDs[index]
            local remaining = C_EncounterTimeline.GetEventTimeRemaining(eventID)
            if remaining > threshold then
                local delay = remaining - threshold
                if not nextRefresh or delay < nextRefresh then
                    nextRefresh = delay
                end
                break
            end

            count = count + 1
            UpdateSlot(slots[count] or CreateSlot(count), eventID, remaining)
            -- Refresh when the soonest shown event expires so its queued state is picked up.
            if not nextRefresh and remaining > 0 then
                nextRefresh = remaining
            end
        end
    end

    if count > 0 then
        SetShownCount(count)
    elseif previewActive then
        ShowPreview()
    else
        SetShownCount(0)
    end

    if nextRefresh then
        RefineUI:After(REFRESH_TIMER_KEY, math_max(nextRefresh, MIN_REFRESH_DELAY), RefreshBigIcon)
    end
end

-- Coalesces bursts (encounter start, edit mode) into one refresh on the next frame.
local function RequestRefresh()
    RefineUI:After(REFRESH_TIMER_KEY, 0, RefreshBigIcon)
end

----------------------------------------------------------------------------------------
-- Setup
----------------------------------------------------------------------------------------
local function CreateBigIconFrame()
    local frameName = EncounterTimeline.BIG_ICON_FRAME_NAME
    local position = RefineUI.Positions[frameName]

    local frame = CreateFrame("Frame", frameName, UIParent)
    RefineUI:AddAPI(frame)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(FRAME_LEVEL)
    frame:Size(1, 1)
    frame:SetPoint(position[1], _G[position[2]] or UIParent, position[3], position[4], position[5])
    frame:Hide()

    local lib = RefineUI.LibEditMode
    lib:AddFrame(frame, function(targetFrame, _, point, x, y)
        targetFrame:ClearAllPoints()
        targetFrame:SetPoint(point, UIParent, point, x, y)
        RefineUI:SetPosition(frameName, { point, "UIParent", point, x, y })
    end, { point = position[1], x = position[4], y = position[5] }, "Encounter Timeline Big Icon")

    lib:RegisterCallback("enter", function()
        previewActive = true
        RequestRefresh()
    end)
    lib:RegisterCallback("exit", function()
        previewActive = false
        RequestRefresh()
    end)

    return frame
end

function EncounterTimeline:InstallBigIcon()
    bigIconFrame = CreateBigIconFrame()

    RefineUI:OnEvents(REFRESH_EVENTS, RequestRefresh, "EncounterTimeline:BigIcon")
    -- Timeline visibility gates the big icon; UpdateVisibility runs after every visibility change.
    hooksecurefunc(_G.EncounterTimeline, "UpdateVisibility", RequestRefresh)
    RequestRefresh()
end
