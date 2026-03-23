----------------------------------------------------------------------------------------
-- CDM Component: TrackersRender
-- Description: Tracker icon render pipeline and cooldown visual updates.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local CDM = RefineUI:GetModule("CDM")
if not CDM then
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
local type = type
local tonumber = tonumber
local floor = math.floor
local pcall = pcall
local wipe = _G.wipe or table.wipe
local next = next

local CreateFrame = CreateFrame
local UIParent = UIParent
local CooldownFrame_Clear = CooldownFrame_Clear
local CooldownFrame_Set = CooldownFrame_Set
local C_Spell = C_Spell
local GetTime = GetTime
local issecretvalue = _G.issecretvalue

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local ORIENTATION_HORIZONTAL = "HORIZONTAL"
local ORIENTATION_VERTICAL = "VERTICAL"
local DIRECTION_LEFT = "LEFT"
local DIRECTION_RIGHT = "RIGHT"
local DIRECTION_UP = "UP"
local DIRECTION_DOWN = "DOWN"
local DIRECTION_CENTERED = "CENTERED"
local RADIAL_BUCKET = "Radial"
local RADIAL_TEXT_POSITION_CENTER = "CENTER"
local RADIAL_TEXT_POSITION_ABOVE = "ABOVE"
local RADIAL_TEXT_POSITION_BELOW = "BELOW"
local DEFAULT_ICON_BASE_SIZE = 44
local RADIAL_BASE_SIZE = 512
local TRACKER_SWIPE_OVERLAY_INSET = 2
local TRACKER_SWIPE_FRAMELEVEL_OFFSET = 20
local TRACKER_SWIPE_COLOR_R = 0
local TRACKER_SWIPE_COLOR_G = 0
local TRACKER_SWIPE_COLOR_B = 0
local TRACKER_SWIPE_COLOR_A = 0.8
local TRACKER_COOLDOWN_TEXT_SIZE = 22
local RADIAL_BACKGROUND_ALPHA = 0.1
local RADIAL_FILL_ALPHA = 1
local RADIAL_TEXT_GAP = 10
local RADIAL_TIMER_JOB_KEY = "CDM:RadialTimerUpdater"
local RADIAL_TIMER_INTERVAL = 0.05
local ActiveRadialCountdowns = setmetatable({}, { __mode = "k" })
local radialTimerSchedulerInitialized = false


local function ApplyTrackerCooldownTextStyle(cooldown, textSize)
    if not cooldown or type(cooldown.GetRegions) ~= "function" then
        return
    end

    local resolvedTextSize = type(textSize) == "number" and textSize or TRACKER_COOLDOWN_TEXT_SIZE
    local regions = { cooldown:GetRegions() }
    for i = 1, #regions do
        local region = regions[i]
        if region and type(region.GetObjectType) == "function" and region:GetObjectType() == "FontString" then
            region:SetFont(RefineUI.Media.Fonts.Number, resolvedTextSize, "OUTLINE")
        end
    end
end

local function GetTrackerCountdownFontString(cooldown)
    if not cooldown or type(cooldown.GetCountdownFontString) ~= "function" then
        return nil
    end

    local ok, fontString = pcall(cooldown.GetCountdownFontString, cooldown)
    if not ok then
        return nil
    end
    return fontString
end

local function SetRadialCountdownText(radialDisplay, value)
    if not radialDisplay or not radialDisplay.CountdownText then
        return
    end

    local displayValue = value
    if type(value) == "number" and not (issecretvalue and issecretvalue(value)) and RefineUI.FormatTime then
        displayValue = RefineUI:FormatTime(value)
    end

    RefineUI:SetFontStringValue(radialDisplay.CountdownText, displayValue, {
        emptyText = "",
    })
end


local function GetRefineCooldownSwipeTexture()
    local media = RefineUI.Media
    local textures = media and media.Textures
    if type(textures) ~= "table" then
        return nil
    end
    if type(textures.CooldownSwipe) == "string" and textures.CooldownSwipe ~= "" then
        return textures.CooldownSwipe
    end
    if type(textures.CooldownSwipeSmall) == "string" and textures.CooldownSwipeSmall ~= "" then
        return textures.CooldownSwipeSmall
    end
    return nil
end

local function GetRadialTrackerTexture()
    local media = RefineUI.Media
    local textures = media and media.Textures
    if type(textures) ~= "table" then
        return nil
    end
    if type(textures.TickCircle) == "string" and textures.TickCircle ~= "" then
        return textures.TickCircle
    end
    return nil
end


local function GetSafeFrameLevelForTracker(frame)
    if not frame or type(frame.GetFrameLevel) ~= "function" then
        return nil
    end

    local ok, level = pcall(frame.GetFrameLevel, frame)
    if not ok or (issecretvalue and issecretvalue(level)) or type(level) ~= "number" then
        return nil
    end

    return level
end


local function GetSafeFrameStrataForTracker(frame)
    if not frame or type(frame.GetFrameStrata) ~= "function" then
        return nil
    end

    local ok, strata = pcall(frame.GetFrameStrata, frame)
    if not ok or (issecretvalue and issecretvalue(strata)) or type(strata) ~= "string" or strata == "" then
        return nil
    end

    return strata
end


local function ApplyTrackerCooldownSkin(iconFrame)
    if not iconFrame or not iconFrame.Cooldown then
        return
    end

    local cooldown = iconFrame.Cooldown
    local swipeTexture = GetRefineCooldownSwipeTexture()
    local frameLevel = GetSafeFrameLevelForTracker(iconFrame) or 1
    local frameStrata = GetSafeFrameStrataForTracker(iconFrame) or ""
    local skinToken = "fill_v1:" .. tostring(swipeTexture or "") .. ":" .. frameStrata .. ":" .. tostring(frameLevel + TRACKER_SWIPE_FRAMELEVEL_OFFSET)
    if CDM.StateGet and CDM:StateGet(iconFrame, "trackerCooldownSkinToken") == skinToken then
        return
    end

    cooldown:ClearAllPoints()
    cooldown:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", -TRACKER_SWIPE_OVERLAY_INSET, TRACKER_SWIPE_OVERLAY_INSET)
    cooldown:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", TRACKER_SWIPE_OVERLAY_INSET, -TRACKER_SWIPE_OVERLAY_INSET)
    if cooldown.SetFrameStrata then
        local strata = GetSafeFrameStrataForTracker(iconFrame)
        if strata then
            cooldown:SetFrameStrata(strata)
        end
    end
    if cooldown.SetFrameLevel then
        cooldown:SetFrameLevel(frameLevel + TRACKER_SWIPE_FRAMELEVEL_OFFSET)
    end
    cooldown:SetDrawEdge(false)
    if cooldown.SetDrawBling then
        pcall(cooldown.SetDrawBling, cooldown, true)
    end
    cooldown:SetDrawSwipe(true)
    if cooldown.SetReverse then
        pcall(cooldown.SetReverse, cooldown, true)
    end
    if cooldown.SetSwipeColor then
        pcall(cooldown.SetSwipeColor, cooldown, TRACKER_SWIPE_COLOR_R, TRACKER_SWIPE_COLOR_G, TRACKER_SWIPE_COLOR_B, TRACKER_SWIPE_COLOR_A)
    end

    ApplyTrackerCooldownTextStyle(cooldown, TRACKER_COOLDOWN_TEXT_SIZE)

    if swipeTexture and cooldown.SetSwipeTexture then
        pcall(cooldown.SetSwipeTexture, cooldown, swipeTexture)
    end

    if CDM.StateSet then
        CDM:StateSet(iconFrame, "trackerCooldownSkinToken", skinToken)
    end
end

local FRAME_LABELS = {
    Left = "Cooldown Tracker Left",
    Right = "Cooldown Tracker Right",
    Bottom = "Cooldown Tracker Bottom",
}


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


local function ResolveCooldownModRate(value)
    if type(value) == "number" and not IsSecret(value) then
        return value
    end
    return 1
end


local function BuildRenderPrimitive(value, defaultToken)
    if IsSecret(value) then
        return nil, false
    end
    if value == nil then
        return defaultToken, true
    end
    local valueType = type(value)
    if valueType == "number" or valueType == "string" or valueType == "boolean" then
        return tostring(value), true
    end
    return nil, false
end


local function BuildEntryContentToken(entry)
    if type(entry) ~= "table" then
        return "0"
    end

    local parts = {}

    local cooldownID = entry.cooldownID
    if type(cooldownID) == "number" then
        parts[#parts + 1] = tostring(cooldownID)
    else
        parts[#parts + 1] = "0"
    end

    local iconToken, iconOk = BuildRenderPrimitive(entry.icon, "icon_nil")
    if iconOk then
        parts[#parts + 1] = "icon:" .. iconToken
    end

    local auraUnitToken, auraUnitOk = BuildRenderPrimitive(entry.auraUnit, "aura_unit_nil")
    if auraUnitOk then
        parts[#parts + 1] = "aura_unit:" .. auraUnitToken
    end

    local auraInstanceToken, auraInstanceOk = BuildRenderPrimitive(entry.auraInstanceID, "aura_instance_nil")
    if auraInstanceOk then
        parts[#parts + 1] = "aura_instance:" .. auraInstanceToken
    end

    local activeStateToken, activeStateOk = BuildRenderPrimitive(entry.activeStateToken, "active_state_nil")
    if activeStateOk then
        parts[#parts + 1] = "active_state:" .. activeStateToken
    end

    local hasDurationObject = HasValue(entry.duration)
    parts[#parts + 1] = hasDurationObject and "dur_obj:1" or "dur_obj:0"

    local startToken, startOk = BuildRenderPrimitive(entry.cooldownStartTime, "start_nil")
    if startOk then
        parts[#parts + 1] = "start:" .. startToken
    end

    local expirationToken, expirationOk = BuildRenderPrimitive(entry.cooldownExpirationTime, "exp_nil")
    if expirationOk then
        parts[#parts + 1] = "exp:" .. expirationToken
    end

    local durationToken, durationOk = BuildRenderPrimitive(entry.cooldownDuration, "dur_nil")
    if durationOk then
        parts[#parts + 1] = "dur:" .. durationToken
    end

    local modRateToken, modRateOk = BuildRenderPrimitive(entry.cooldownModRate, "mod_nil")
    if modRateOk then
        parts[#parts + 1] = "mod:" .. modRateToken
    end

    local borderToken, borderOk = BuildRenderPrimitive(entry.borderColorToken, "border_nil")
    if borderOk then
        parts[#parts + 1] = "border:" .. borderToken
    end

    local fontToken, fontOk = BuildRenderPrimitive(entry.fontColorToken, "font_nil")
    if fontOk then
        parts[#parts + 1] = "font:" .. fontToken
    end

    return table.concat(parts, ";")
end


local function BuildBucketLayoutToken(count, iconScale, spacing, orientation, direction, inEditMode)
    return table.concat({
        "scale:" .. tostring(iconScale),
        "spacing:" .. tostring(spacing),
        "orientation:" .. tostring(orientation),
        "direction:" .. tostring(direction),
        "edit:" .. (inEditMode and "1" or "0"),
        "count:" .. tostring(count),
    }, "|")
end

local function BuildRadialLayoutToken(iconScale, showDurationText, textSize, textPosition, inEditMode)
    return table.concat({
        "scale:" .. tostring(iconScale),
        "show_text:" .. (showDurationText and "1" or "0"),
        "text_size:" .. tostring(textSize),
        "text_pos:" .. tostring(textPosition),
        "edit:" .. (inEditMode and "1" or "0"),
    }, "|")
end


local function SetScaledPoint(frame, point, relativeTo, relativePoint, x, y)
    if type(frame.Point) == "function" then
        frame:Point(point, relativeTo, relativePoint, x, y)
    else
        frame:SetPoint(point, relativeTo, relativePoint, RefineUI:Scale(x), RefineUI:Scale(y))
    end
end


local function ComputeAxisOffset(index, count, step)
    local halfSpan = ((count - 1) * step) / 2
    return ((index - 1) * step) - halfSpan
end


local function ComputeIconOffset(index, count, iconSize, spacing, orientation, direction)
    local step = iconSize + spacing
    local axisOffset = ComputeAxisOffset(index, count, step)
    local anchoredOffset = (index - 1) * step

    if orientation == ORIENTATION_VERTICAL then
        if direction == DIRECTION_CENTERED then
            return 0, -axisOffset
        end
        if direction == DIRECTION_UP then
            return 0, anchoredOffset
        end
        if direction == DIRECTION_DOWN then
            return 0, -anchoredOffset
        end
        return 0, anchoredOffset
    end

    if direction == DIRECTION_CENTERED then
        return axisOffset, 0
    end
    if direction == DIRECTION_LEFT then
        return -anchoredOffset, 0
    end
    if direction == DIRECTION_RIGHT then
        return anchoredOffset, 0
    end
    return anchoredOffset, 0
end

local function ApplyTrackerCooldownPayload(cooldown, entry, contentChanged)
    if not cooldown then
        return false
    end

    local hasDurationObject = entry and HasValue(entry.duration)
    local hasCooldownExpirationWindow = entry and HasValue(entry.cooldownExpirationTime) and HasValue(entry.cooldownDuration)
    local hasCooldownWindow = entry and HasValue(entry.cooldownStartTime) and HasValue(entry.cooldownDuration)
    local appliedCooldown = false

    if (contentChanged or hasDurationObject or hasCooldownExpirationWindow or hasCooldownWindow)
        and type(cooldown.SetUseAuraDisplayTime) == "function"
    then
        pcall(cooldown.SetUseAuraDisplayTime, cooldown, (hasDurationObject or hasCooldownExpirationWindow or hasCooldownWindow) and true or false)
    end

    if (contentChanged or hasDurationObject)
        and hasDurationObject
        and cooldown.SetCooldownFromDurationObject
    then
        local ok = pcall(cooldown.SetCooldownFromDurationObject, cooldown, entry.duration)
        appliedCooldown = ok and true or false
    end

    if not appliedCooldown
        and (contentChanged or hasCooldownExpirationWindow)
        and hasCooldownExpirationWindow
        and cooldown.SetCooldownFromExpirationTime
    then
        local expirationTime = entry.cooldownExpirationTime
        local duration = entry.cooldownDuration
        local modRate = ResolveCooldownModRate(entry.cooldownModRate)
        local ok = pcall(cooldown.SetCooldownFromExpirationTime, cooldown, expirationTime, duration, modRate)
        appliedCooldown = ok and true or false
    end

    if not appliedCooldown and (contentChanged or hasCooldownWindow) and hasCooldownWindow then
        local startTime = entry.cooldownStartTime
        local duration = entry.cooldownDuration
        local modRate = ResolveCooldownModRate(entry.cooldownModRate)

        if cooldown.SetCooldown then
            local ok = pcall(cooldown.SetCooldown, cooldown, startTime, duration, modRate)
            appliedCooldown = ok and true or false
        end

        if not appliedCooldown and cooldown.SetCooldownDuration then
            local ok = pcall(cooldown.SetCooldownDuration, cooldown, duration, modRate)
            appliedCooldown = ok and true or false
        end

        if not appliedCooldown
            and CooldownFrame_Set
            and not IsSecret(startTime)
            and not IsSecret(duration)
        then
            local ok = pcall(CooldownFrame_Set, cooldown, startTime, duration, true, false, modRate)
            appliedCooldown = ok and true or false
        end
    end

    if not appliedCooldown
        and CooldownFrame_Clear
        and not hasDurationObject
        and not hasCooldownExpirationWindow
        and not hasCooldownWindow
        and contentChanged
    then
        CooldownFrame_Clear(cooldown)
    end

    return appliedCooldown
end

local function SetBuiltinCountdownHidden(cooldown, hidden)
    if not cooldown or type(cooldown.SetHideCountdownNumbers) ~= "function" then
        return
    end
    pcall(cooldown.SetHideCountdownNumbers, cooldown, hidden == true)
end

local function GetCooldownRemainingSeconds(cooldown)
    if not cooldown or type(cooldown.GetCooldownTimes) ~= "function" then
        return nil
    end

    local ok, startMS, durationMS = pcall(cooldown.GetCooldownTimes, cooldown)
    if not ok or IsSecret(startMS) or IsSecret(durationMS) then
        return nil
    end
    if type(startMS) ~= "number" or type(durationMS) ~= "number" or durationMS <= 0 then
        return nil
    end

    local nowMS = GetTime() * 1000
    local expirationMS = startMS + durationMS
    if expirationMS <= nowMS then
        return 0
    end

    return (expirationMS - nowMS) / 1000
end

local function UpdateRadialCountdownText(radialDisplay)
    if not radialDisplay or not radialDisplay.Cooldown then
        return false
    end

    if not radialDisplay:IsShown() or not radialDisplay.CountdownText or not radialDisplay.CountdownText:IsShown() then
        SetRadialCountdownText(radialDisplay, nil)
        return false
    end

    local remainingSeconds = GetCooldownRemainingSeconds(radialDisplay.Cooldown)
    if type(remainingSeconds) ~= "number" then
        SetRadialCountdownText(radialDisplay, nil)
        return false
    end

    if remainingSeconds < 0 then
        remainingSeconds = 0
    end

    SetRadialCountdownText(radialDisplay, remainingSeconds)
    return remainingSeconds > 0
end

local function RadialTimerUpdateJob()
    for radialDisplay in pairs(ActiveRadialCountdowns) do
        if not UpdateRadialCountdownText(radialDisplay) then
            ActiveRadialCountdowns[radialDisplay] = nil
        end
    end

    if next(ActiveRadialCountdowns) == nil and RefineUI.SetUpdateJobEnabled then
        RefineUI:SetUpdateJobEnabled(RADIAL_TIMER_JOB_KEY, false, false)
    end
end

local function EnsureRadialTimerScheduler()
    if radialTimerSchedulerInitialized or not RefineUI.RegisterUpdateJob then
        return
    end

    RefineUI:RegisterUpdateJob(RADIAL_TIMER_JOB_KEY, RADIAL_TIMER_INTERVAL, RadialTimerUpdateJob, {
        enabled = false,
    })
    radialTimerSchedulerInitialized = true
end

local function SetRadialCountdownActive(radialDisplay, enabled)
    if not radialDisplay then
        return
    end

    if enabled then
        ActiveRadialCountdowns[radialDisplay] = true
    else
        ActiveRadialCountdowns[radialDisplay] = nil
        SetRadialCountdownText(radialDisplay, nil)
    end

    EnsureRadialTimerScheduler()
    if radialTimerSchedulerInitialized and RefineUI.SetUpdateJobEnabled then
        RefineUI:SetUpdateJobEnabled(RADIAL_TIMER_JOB_KEY, next(ActiveRadialCountdowns) ~= nil, false)
    end
end

local function ApplyRadialCountdownTextLayout(radialDisplay, showDurationText, textSize, textPosition)
    if not radialDisplay or not radialDisplay.Cooldown or not radialDisplay.CountdownText then
        return
    end

    local cooldown = radialDisplay.Cooldown
    SetBuiltinCountdownHidden(cooldown, true)

    local builtinCountdownText = GetTrackerCountdownFontString(cooldown)
    if builtinCountdownText then
        builtinCountdownText:SetShown(false)
    end

    local countdownText = radialDisplay.CountdownText
    countdownText:ClearAllPoints()
    if textPosition == RADIAL_TEXT_POSITION_ABOVE then
        countdownText:SetPoint("BOTTOM", radialDisplay, "TOP", 0, RADIAL_TEXT_GAP)
    elseif textPosition == RADIAL_TEXT_POSITION_BELOW then
        countdownText:SetPoint("TOP", radialDisplay, "BOTTOM", 0, -RADIAL_TEXT_GAP)
    else
        countdownText:SetPoint("CENTER", radialDisplay, "CENTER", 0, 0)
    end

    countdownText:SetFont(RefineUI.Media.Fonts.Number, textSize, "OUTLINE")
    countdownText:SetShown(showDurationText == true)
end

local function ApplyRadialTrackerSkin(radialDisplay, radialColor, textColor, textSize, showDurationText, textPosition)
    if not radialDisplay or not radialDisplay.Cooldown or not radialDisplay.Background then
        return
    end

    local cooldown = radialDisplay.Cooldown
    local radialTexture = GetRadialTrackerTexture()
    local color = radialColor or { 1, 1, 1, 1 }
    local resolvedTextColor = textColor or { 1, 1, 1, 1 }

    radialDisplay.Background:SetTexture(radialTexture)
    radialDisplay.Background:SetVertexColor(color[1], color[2], color[3], RADIAL_BACKGROUND_ALPHA)

    if cooldown.SetSwipeTexture and radialTexture then
        pcall(cooldown.SetSwipeTexture, cooldown, radialTexture)
    end
    if cooldown.SetSwipeColor then
        pcall(cooldown.SetSwipeColor, cooldown, color[1], color[2], color[3], RADIAL_FILL_ALPHA)
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
    if cooldown.SetReverse then
        pcall(cooldown.SetReverse, cooldown, false)
    end
    if cooldown.SetUseCircularEdge then
        pcall(cooldown.SetUseCircularEdge, cooldown, false)
    end
    if cooldown.SetAlpha then
        pcall(cooldown.SetAlpha, cooldown, 1)
    end
    if cooldown.SetMinimumCountdownDuration then
        pcall(cooldown.SetMinimumCountdownDuration, cooldown, 0)
    end
    ApplyRadialCountdownTextLayout(radialDisplay, showDurationText, textSize, textPosition)
    if radialDisplay.CountdownText then
        radialDisplay.CountdownText:SetTextColor(
            resolvedTextColor[1],
            resolvedTextColor[2],
            resolvedTextColor[3],
            resolvedTextColor[4] or 1
        )
    end
end


----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function CDM:RenderTrackerBucket(frame, activeEntries, iconScale, spacing, orientation, direction)
    local renderStartTime = GetTime()
    local inEditMode = self:IsEditModeActive()
    local count = #activeEntries
    local iconSize = DEFAULT_ICON_BASE_SIZE * iconScale

    if count == 0 and inEditMode then
        activeEntries = {
            {
                icon = 134400,
                duration = nil,
            },
        }
        count = 1
    end

    local bucketLayoutToken = BuildBucketLayoutToken(count, iconScale, spacing, orientation, direction, inEditMode)
    local bucketLayoutChanged = self:StateGet(frame, "trackerBucketLayoutToken") ~= bucketLayoutToken

    if count == 0 then
        if frame.icons then
            for i = 1, #frame.icons do
                frame.icons[i]:Hide()
                self:StateClear(frame.icons[i], "trackerLayoutToken")
                self:StateClear(frame.icons[i], "trackerContentToken")
            end
        end
        frame:Hide()
        self:StateSet(frame, "trackerBucketLayoutToken", bucketLayoutToken)
        self:RecordPerfSample("cdm_tracker_render", GetTime() - renderStartTime)
        self:IncrementPerfCounter("cdm_tracker_render")
        return
    end

    for i = 1, count do
        local entry = activeEntries[i]
        local icon = self:EnsureTrackerIcon(frame, i)
        ApplyTrackerCooldownSkin(icon)
        local iconLayoutToken = bucketLayoutToken .. ":index:" .. tostring(i)
        local iconLayoutChanged = bucketLayoutChanged or self:StateGet(icon, "trackerLayoutToken") ~= iconLayoutToken
        if iconLayoutChanged then
            icon:Size(DEFAULT_ICON_BASE_SIZE, DEFAULT_ICON_BASE_SIZE)
            icon:SetScale(iconScale)
            local xOffset, yOffset = ComputeIconOffset(i, count, iconSize, spacing, orientation, direction)
            icon:ClearAllPoints()
            SetScaledPoint(icon, "CENTER", frame, "CENTER", xOffset, yOffset)
            self:StateSet(icon, "trackerLayoutToken", iconLayoutToken)
        end

        local texture = nil
        if entry then
            texture = entry.icon
        end
        if not HasValue(texture) then
            texture = 134400
        end
        local contentToken = BuildEntryContentToken(entry)
        local previousContentToken = self:StateGet(icon, "trackerContentToken")
        local contentChanged = previousContentToken ~= contentToken
        if contentChanged then
            icon.Icon:SetTexture(texture)
        end

        if contentChanged and self.ApplyTrackerIconVisual then
            self:ApplyTrackerIconVisual(icon, entry and entry.cooldownID)
        elseif contentChanged and icon.border and icon.border.SetBackdropBorderColor then
            local border = self.GetDefaultBorderColor and self:GetDefaultBorderColor() or { 0.6, 0.6, 0.6, 1 }
            icon.border:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
        end

        ApplyTrackerCooldownPayload(icon.Cooldown, entry, contentChanged)

        if contentChanged and self.ApplyTrackerCooldownTextVisual and icon.Cooldown then
            self:ApplyTrackerCooldownTextVisual(icon.Cooldown, entry and entry.cooldownID)
        end

        self:StateSet(icon, "trackerContentToken", contentToken)
        icon:Show()
    end

    for i = count + 1, #(frame.icons or {}) do
        frame.icons[i]:Hide()
        self:StateClear(frame.icons[i], "trackerLayoutToken")
        self:StateClear(frame.icons[i], "trackerContentToken")
    end

    local totalSpan = (iconSize * count) + (spacing * (count - 1))
    if totalSpan < iconSize then
        totalSpan = iconSize
    end
    if bucketLayoutChanged then
        if orientation == ORIENTATION_VERTICAL then
            frame:Size(iconSize, totalSpan)
        else
            frame:Size(totalSpan, iconSize)
        end
        self:StateSet(frame, "trackerBucketLayoutToken", bucketLayoutToken)
    end
    frame:Show()
    self:RecordPerfSample("cdm_tracker_render", GetTime() - renderStartTime)
    self:IncrementPerfCounter("cdm_tracker_render")
end


function CDM:RenderRadialTracker(frame, activeEntries, iconScale, bucketCfg)
    local renderStartTime = GetTime()
    local inEditMode = self:IsEditModeActive()
    local entry = activeEntries[1]
    local radialSize = RADIAL_BASE_SIZE * iconScale

    if not entry and inEditMode then
        entry = {
            cooldownID = nil,
        }
    end

    local radialDisplay = self:EnsureRadialTrackerDisplay(frame)
    local layoutToken = BuildRadialLayoutToken(
        iconScale,
        bucketCfg.ShowDurationText ~= false,
        bucketCfg.TextSize,
        bucketCfg.TextPosition,
        inEditMode
    )
    local layoutChanged = self:StateGet(frame, "trackerRadialLayoutToken") ~= layoutToken

    if not entry then
        if radialDisplay then
            if layoutChanged then
                radialDisplay:SetScale(1)
                radialDisplay:Size(radialSize, radialSize)
                frame:Size(radialSize, radialSize)
            end
            SetRadialCountdownActive(radialDisplay, false)
            radialDisplay:Hide()
        end
        frame:Hide()
        self:StateSet(frame, "trackerRadialLayoutToken", layoutToken)
        self:StateClear(frame, "trackerRadialContentToken")
        self:RecordPerfSample("cdm_tracker_render", GetTime() - renderStartTime)
        self:IncrementPerfCounter("cdm_tracker_render")
        return
    end

    local contentToken = BuildEntryContentToken(entry)
    local contentChanged = self:StateGet(frame, "trackerRadialContentToken") ~= contentToken
    local radialColor = nil
    local textColor = nil
    if entry.cooldownID and self.GetCooldownBorderColor then
        radialColor = self:GetCooldownBorderColor(entry.cooldownID)
    elseif self.GetDefaultBorderColor then
        radialColor = self:GetDefaultBorderColor()
    end
    if entry.cooldownID and self.GetCooldownFontColor then
        textColor = self:GetCooldownFontColor(entry.cooldownID)
    elseif self.GetDefaultFontColor then
        textColor = self:GetDefaultFontColor()
    end

    if layoutChanged then
        radialDisplay:SetScale(1)
        radialDisplay:Size(radialSize, radialSize)
        frame:Size(radialSize, radialSize)
    end

    if contentChanged or layoutChanged then
        ApplyRadialTrackerSkin(
            radialDisplay,
            radialColor,
            textColor,
            bucketCfg.TextSize,
            bucketCfg.ShowDurationText ~= false,
            bucketCfg.TextPosition
        )
    end

    ApplyTrackerCooldownPayload(radialDisplay.Cooldown, entry, contentChanged or layoutChanged)
    UpdateRadialCountdownText(radialDisplay)
    SetRadialCountdownActive(radialDisplay, bucketCfg.ShowDurationText ~= false)

    if (contentChanged or layoutChanged) and self.ApplyTrackerCooldownTextVisual and radialDisplay.Cooldown then
        self:ApplyTrackerCooldownTextVisual(radialDisplay.Cooldown, entry.cooldownID)
    end

    radialDisplay:Show()
    frame:Show()
    self:StateSet(frame, "trackerRadialLayoutToken", layoutToken)
    self:StateSet(frame, "trackerRadialContentToken", contentToken)
    self:RecordPerfSample("cdm_tracker_render", GetTime() - renderStartTime)
    self:IncrementPerfCounter("cdm_tracker_render")
end


function CDM:BuildAssignedTrackerEntry(cooldownID, activePayload)
    if activePayload and HasValue(activePayload.icon) then
        return activePayload
    end

    local icon
    local info = self:GetCooldownInfo(cooldownID)
    local spellID = self:ResolveCooldownSpellID(info)
    if not IsSecret(spellID) and type(spellID) == "number" and C_Spell and type(C_Spell.GetSpellTexture) == "function" then
        local ok, texture = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and HasValue(texture) then
            icon = texture
        end
    end

    if not HasValue(icon) and activePayload and HasValue(activePayload.icon) then
        icon = activePayload.icon
    end
    if not HasValue(icon) then
        icon = 134400
    end

    return {
        cooldownID = cooldownID,
        icon = icon,
        borderColorToken = self.GetCooldownBorderColorToken and self:GetCooldownBorderColorToken(cooldownID) or nil,
        fontColorToken = self.GetCooldownFontColorToken and self:GetCooldownFontColorToken(cooldownID) or nil,
        duration = activePayload and activePayload.duration,
        auraUnit = activePayload and activePayload.auraUnit,
        auraInstanceID = activePayload and activePayload.auraInstanceID,
        activeStateToken = activePayload and activePayload.activeStateToken,
        cooldownExpirationTime = activePayload and activePayload.cooldownExpirationTime,
        cooldownStartTime = activePayload and activePayload.cooldownStartTime,
        cooldownDuration = activePayload and activePayload.cooldownDuration,
        cooldownModRate = activePayload and activePayload.cooldownModRate,
    }
end


function CDM:HideTrackers()
    if not self.trackerFrames then
        self.activeTrackerEntryCount = 0
        return
    end

    self.activeTrackerEntryCount = 0

    for i = 1, #self.TRACKER_BUCKETS do
        local bucket = self.TRACKER_BUCKETS[i]
        local frame = self.trackerFrames[bucket]
        if frame then
            if frame.RadialDisplay then
                SetRadialCountdownActive(frame.RadialDisplay, false)
            end
            frame:Hide()
            self:StateClear(frame, "renderSignature")
            self:StateClear(frame, "renderEntryCount")
            self:StateClear(frame, "trackerBucketLayoutToken")
            self:StateClear(frame, "trackerRadialLayoutToken")
            self:StateClear(frame, "trackerRadialContentToken")
        end
    end
end


function CDM:InitializeTrackers()
    self.trackerFrames = self.trackerFrames or {}
    for i = 1, #self.TRACKER_BUCKETS do
        local bucket = self.TRACKER_BUCKETS[i]
        self:EnsureTrackerFrame(bucket)
    end
end


function CDM:RefreshTrackers(dirtyCooldownIDSet)
    local inEditMode = self:IsEditModeActive()
    if inEditMode and not self:IsRefineAuraModeActive() then
        self:HideTrackers()
        return
    end

    local assignments = self:GetCurrentAssignments()
    local assignedSnapshot = self.GetAssignedCooldownSnapshot and self:GetAssignedCooldownSnapshot() or nil
    local allAssignedIDs = assignedSnapshot and assignedSnapshot.allAssignedIDs or {}
    self.scratchBucketEntries = self.scratchBucketEntries or {}
    if #allAssignedIDs == 0 and not inEditMode then
        self:HideTrackers()
        return
    end

    local dirtyBuckets = nil
    local requestedCooldownIDs = allAssignedIDs
    if not inEditMode and type(dirtyCooldownIDSet) == "table" and next(dirtyCooldownIDSet) ~= nil then
        dirtyBuckets = {}
        requestedCooldownIDs = {}
        local requestedSeen = {}
        local cooldownBuckets = assignedSnapshot and assignedSnapshot.cooldownBuckets or nil
        local bucketCooldownIDs = assignedSnapshot and assignedSnapshot.bucketCooldownIDs or nil
        if type(cooldownBuckets) == "table" then
            for cooldownID in pairs(dirtyCooldownIDSet) do
                local bucketList = cooldownBuckets[cooldownID]
                if type(bucketList) == "table" then
                    for bucketIndex = 1, #bucketList do
                        dirtyBuckets[bucketList[bucketIndex]] = true
                    end
                end
            end
        end

        if next(dirtyBuckets) ~= nil and type(bucketCooldownIDs) == "table" then
            for bucket in pairs(dirtyBuckets) do
                local bucketIDs = bucketCooldownIDs[bucket]
                if type(bucketIDs) == "table" then
                    for bucketIndex = 1, #bucketIDs do
                        local cooldownID = bucketIDs[bucketIndex]
                        if type(cooldownID) == "number" and cooldownID > 0 and not requestedSeen[cooldownID] then
                            requestedSeen[cooldownID] = true
                            requestedCooldownIDs[#requestedCooldownIDs + 1] = cooldownID
                        end
                    end
                end
            end
        else
            requestedCooldownIDs = allAssignedIDs
            dirtyBuckets = nil
        end
    end

    local activeMap = self:GetActiveAuraMap(requestedCooldownIDs)
    local totalActiveEntryCount = 0
    for i = 1, #self.TRACKER_BUCKETS do
        local bucket = self.TRACKER_BUCKETS[i]
        local frame = self:EnsureTrackerFrame(bucket)
        if not dirtyBuckets or dirtyBuckets[bucket] then
            local iconScale, spacing, orientation, direction, bucketCfg = self:GetTrackerVisualSettings(bucket)
            local activeEntries = self.scratchBucketEntries[bucket]
            if not activeEntries then
                activeEntries = {}
                self.scratchBucketEntries[bucket] = activeEntries
            elseif wipe then
                wipe(activeEntries)
            else
                for n = #activeEntries, 1, -1 do
                    activeEntries[n] = nil
                end
            end

            local ids = assignments[bucket]
            for n = 1, #ids do
                local cooldownID = ids[n]
                local payload = activeMap[cooldownID]
                if payload then
                    if self.GetCooldownBorderColorToken then
                        payload.borderColorToken = self:GetCooldownBorderColorToken(cooldownID)
                    end
                    if self.GetCooldownFontColorToken then
                        payload.fontColorToken = self:GetCooldownFontColorToken(cooldownID)
                    end
                    activeEntries[#activeEntries + 1] = payload
                elseif inEditMode then
                    activeEntries[#activeEntries + 1] = self:BuildAssignedTrackerEntry(cooldownID)
                end
            end

            if not inEditMode then
                if bucket == RADIAL_BUCKET then
                    totalActiveEntryCount = totalActiveEntryCount + (activeEntries[1] and 1 or 0)
                else
                    totalActiveEntryCount = totalActiveEntryCount + #activeEntries
                end
            end

            local previousCount = self:StateGet(frame, "renderEntryCount")

            local forceRender = false
            if frame:IsShown() and #activeEntries == 0 and not inEditMode then
                forceRender = true
            elseif (not frame:IsShown()) and (#activeEntries > 0 or inEditMode) then
                forceRender = true
            elseif previousCount ~= #activeEntries then
                forceRender = true
            end

            if forceRender or dirtyBuckets == nil or dirtyBuckets[bucket] then
                if bucket == RADIAL_BUCKET then
                    self:RenderRadialTracker(frame, activeEntries, iconScale, bucketCfg)
                    self:StateSet(frame, "renderEntryCount", activeEntries[1] and 1 or 0)
                else
                    self:RenderTrackerBucket(frame, activeEntries, iconScale, spacing, orientation, direction)
                    self:StateSet(frame, "renderEntryCount", #activeEntries)
                end
            end
        end
    end

    self.activeTrackerEntryCount = inEditMode and 0 or totalActiveEntryCount
end
