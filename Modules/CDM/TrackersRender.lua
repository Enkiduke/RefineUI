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

local CreateFrame = CreateFrame
local UIParent = UIParent
local CooldownFrame_Clear = CooldownFrame_Clear
local CooldownFrame_Set = CooldownFrame_Set
local C_Spell = C_Spell
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
local DEFAULT_ICON_BASE_SIZE = 44
local TRACKER_SWIPE_OVERLAY_INSET = 2
local TRACKER_SWIPE_FRAMELEVEL_OFFSET = 20
local TRACKER_SWIPE_COLOR_R = 0
local TRACKER_SWIPE_COLOR_G = 0
local TRACKER_SWIPE_COLOR_B = 0
local TRACKER_SWIPE_COLOR_A = 0.8
local TRACKER_COOLDOWN_TEXT_SIZE = 22


local function ApplyTrackerCooldownTextStyle(cooldown)
    if not cooldown or type(cooldown.GetRegions) ~= "function" then
        return
    end

    local regions = { cooldown:GetRegions() }
    for i = 1, #regions do
        local region = regions[i]
        if region and type(region.GetObjectType) == "function" and region:GetObjectType() == "FontString" then
            region:SetFont(RefineUI.Media.Fonts.Number, TRACKER_COOLDOWN_TEXT_SIZE, "OUTLINE")
        end
    end
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
    local skinToken = tostring(swipeTexture or "") .. ":" .. frameStrata .. ":" .. tostring(frameLevel + TRACKER_SWIPE_FRAMELEVEL_OFFSET)
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
    if cooldown.SetSwipeColor then
        pcall(cooldown.SetSwipeColor, cooldown, TRACKER_SWIPE_COLOR_R, TRACKER_SWIPE_COLOR_G, TRACKER_SWIPE_COLOR_B, TRACKER_SWIPE_COLOR_A)
    end

    ApplyTrackerCooldownTextStyle(cooldown)

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
    if IsSecret(value) then
        return value
    end
    if type(value) == "number" then
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


local function BuildEntryRenderSignature(entry)
    if type(entry) ~= "table" then
        return "0", true
    end

    local parts = {}
    local cacheable = true

    local cooldownID = entry.cooldownID
    if type(cooldownID) == "number" then
        parts[#parts + 1] = tostring(cooldownID)
    else
        parts[#parts + 1] = "0"
        cacheable = false
    end

    local iconToken, iconOk = BuildRenderPrimitive(entry.icon, "icon_nil")
    if iconOk then
        parts[#parts + 1] = "icon:" .. iconToken
    else
        cacheable = false
    end

    local hasDurationObject = HasValue(entry.duration)
    parts[#parts + 1] = hasDurationObject and "dur_obj:1" or "dur_obj:0"
    if hasDurationObject then
        cacheable = false
    end

    local startToken, startOk = BuildRenderPrimitive(entry.cooldownStartTime, "start_nil")
    if startOk then
        parts[#parts + 1] = "start:" .. startToken
    else
        cacheable = false
    end

    local durationToken, durationOk = BuildRenderPrimitive(entry.cooldownDuration, "dur_nil")
    if durationOk then
        parts[#parts + 1] = "dur:" .. durationToken
    else
        cacheable = false
    end

    local modRateToken, modRateOk = BuildRenderPrimitive(entry.cooldownModRate, "mod_nil")
    if modRateOk then
        parts[#parts + 1] = "mod:" .. modRateToken
    else
        cacheable = false
    end

    local borderToken, borderOk = BuildRenderPrimitive(entry.borderColorToken, "border_nil")
    if borderOk then
        parts[#parts + 1] = "border:" .. borderToken
    else
        cacheable = false
    end

    local fontToken, fontOk = BuildRenderPrimitive(entry.fontColorToken, "font_nil")
    if fontOk then
        parts[#parts + 1] = "font:" .. fontToken
    else
        cacheable = false
    end

    return table.concat(parts, ";"), cacheable
end


local function BuildBucketRenderSignature(activeEntries, iconScale, spacing, orientation, direction, inEditMode)
    local parts = {
        "scale:" .. tostring(iconScale),
        "spacing:" .. tostring(spacing),
        "orientation:" .. tostring(orientation),
        "direction:" .. tostring(direction),
        "edit:" .. (inEditMode and "1" or "0"),
        "count:" .. tostring(#activeEntries),
    }

    local cacheable = true
    for i = 1, #activeEntries do
        local entrySignature, entryCacheable = BuildEntryRenderSignature(activeEntries[i])
        parts[#parts + 1] = entrySignature
        if not entryCacheable then
            cacheable = false
        end
    end

    if not cacheable then
        return nil
    end
    return table.concat(parts, "|")
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


----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function CDM:RenderTrackerBucket(frame, activeEntries, iconScale, spacing, orientation, direction)
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

    if count == 0 then
        if frame.icons then
            for i = 1, #frame.icons do
                frame.icons[i]:Hide()
            end
        end
        frame:Hide()
        return
    end

    for i = 1, count do
        local entry = activeEntries[i]
        local icon = self:EnsureTrackerIcon(frame, i)
        ApplyTrackerCooldownSkin(icon)
        icon:Size(DEFAULT_ICON_BASE_SIZE, DEFAULT_ICON_BASE_SIZE)
        icon:SetScale(iconScale)
        local xOffset, yOffset = ComputeIconOffset(i, count, iconSize, spacing, orientation, direction)
        icon:ClearAllPoints()
        SetScaledPoint(icon, "CENTER", frame, "CENTER", xOffset, yOffset)

        local texture = nil
        if entry then
            texture = entry.icon
        end
        if not HasValue(texture) then
            texture = 134400
        end
        icon.Icon:SetTexture(texture)

        if self.ApplyTrackerIconVisual then
            self:ApplyTrackerIconVisual(icon, entry and entry.cooldownID)
        elseif icon.border and icon.border.SetBackdropBorderColor then
            local border = self.GetDefaultBorderColor and self:GetDefaultBorderColor() or { 0.6, 0.6, 0.6, 1 }
            icon.border:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
        end

        local hasDurationObject = entry and HasValue(entry.duration)
        local hasCooldownWindow = entry and HasValue(entry.cooldownStartTime) and HasValue(entry.cooldownDuration)
        local appliedCooldown = false

        if icon.Cooldown and type(icon.Cooldown.SetUseAuraDisplayTime) == "function" then
            pcall(icon.Cooldown.SetUseAuraDisplayTime, icon.Cooldown, (hasDurationObject or hasCooldownWindow) and true or false)
        end

        if hasDurationObject and icon.Cooldown and icon.Cooldown.SetCooldownFromDurationObject then
            local ok = pcall(icon.Cooldown.SetCooldownFromDurationObject, icon.Cooldown, entry.duration)
            appliedCooldown = ok and true or false
        end

        if not appliedCooldown and hasCooldownWindow and icon.Cooldown then
            local startTime = entry.cooldownStartTime
            local duration = entry.cooldownDuration
            local modRate = ResolveCooldownModRate(entry.cooldownModRate)

            if icon.Cooldown.SetCooldown then
                local ok = pcall(
                    icon.Cooldown.SetCooldown,
                    icon.Cooldown,
                    startTime,
                    duration,
                    modRate
                )
                appliedCooldown = ok and true or false
            end

            if not appliedCooldown and icon.Cooldown.SetCooldownDuration then
                local ok = pcall(
                    icon.Cooldown.SetCooldownDuration,
                    icon.Cooldown,
                    duration,
                    modRate
                )
                appliedCooldown = ok and true or false
            end

            if not appliedCooldown
                and CooldownFrame_Set
                and not IsSecret(startTime)
                and not IsSecret(duration)
            then
                local ok = pcall(
                    CooldownFrame_Set,
                    icon.Cooldown,
                    startTime,
                    duration,
                    true,
                    false,
                    modRate
                )
                appliedCooldown = ok and true or false
            end
        end

        if not appliedCooldown
            and icon.Cooldown
            and CooldownFrame_Clear
            and not hasDurationObject
            and not hasCooldownWindow
        then
            CooldownFrame_Clear(icon.Cooldown)
        end

        if self.ApplyTrackerCooldownTextVisual and icon.Cooldown then
            self:ApplyTrackerCooldownTextVisual(icon.Cooldown, entry and entry.cooldownID)
        end

        icon:Show()
    end

    for i = count + 1, #(frame.icons or {}) do
        frame.icons[i]:Hide()
    end

    local totalSpan = (iconSize * count) + (spacing * (count - 1))
    if totalSpan < iconSize then
        totalSpan = iconSize
    end
    if orientation == ORIENTATION_VERTICAL then
        frame:Size(iconSize, totalSpan)
    else
        frame:Size(totalSpan, iconSize)
    end
    frame:Show()
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
        cooldownStartTime = activePayload and activePayload.cooldownStartTime,
        cooldownDuration = activePayload and activePayload.cooldownDuration,
        cooldownModRate = activePayload and activePayload.cooldownModRate,
    }
end


function CDM:HideTrackers()
    if not self.trackerFrames then
        return
    end

    for i = 1, #self.TRACKER_BUCKETS do
        local bucket = self.TRACKER_BUCKETS[i]
        local frame = self.trackerFrames[bucket]
        if frame then
            frame:Hide()
            self:StateClear(frame, "renderSignature")
            self:StateClear(frame, "renderEntryCount")
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


function CDM:RefreshTrackers()
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

    local activeMap = self:GetActiveAuraMap(allAssignedIDs)
    for i = 1, #self.TRACKER_BUCKETS do
        local bucket = self.TRACKER_BUCKETS[i]
        local frame = self:EnsureTrackerFrame(bucket)
        local iconScale, spacing, orientation, direction = self:GetTrackerVisualSettings(bucket)
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

        local signature = BuildBucketRenderSignature(activeEntries, iconScale, spacing, orientation, direction, inEditMode)
        local previousSignature = self:StateGet(frame, "renderSignature")
        local previousCount = self:StateGet(frame, "renderEntryCount")

        local forceRender = false
        if frame:IsShown() and #activeEntries == 0 and not inEditMode then
            forceRender = true
        elseif (not frame:IsShown()) and (#activeEntries > 0 or inEditMode) then
            forceRender = true
        elseif previousCount ~= #activeEntries then
            forceRender = true
        end

        if forceRender or not signature or signature ~= previousSignature then
            self:RenderTrackerBucket(frame, activeEntries, iconScale, spacing, orientation, direction)
            self:StateSet(frame, "renderSignature", signature)
            self:StateSet(frame, "renderEntryCount", #activeEntries)
        end
    end
end
