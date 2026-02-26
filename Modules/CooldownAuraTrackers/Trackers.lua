local _, RefineUI = ...
local Module = RefineUI:GetModule("CooldownAuraTrackers")

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

local ORIENTATION_HORIZONTAL = "HORIZONTAL"
local ORIENTATION_VERTICAL = "VERTICAL"
local DIRECTION_LEFT = "LEFT"
local DIRECTION_RIGHT = "RIGHT"
local DIRECTION_UP = "UP"
local DIRECTION_DOWN = "DOWN"
local DIRECTION_CENTERED = "CENTERED"
local DEFAULT_ICON_BASE_SIZE = 44

local FRAME_LABELS = {
    Left = "Cooldown Tracker Left",
    Right = "Cooldown Tracker Right",
    Bottom = "Cooldown Tracker Bottom",
}

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

local function ClampIconScale(value)
    local scale = tonumber(value) or 1
    if scale < 0.5 then
        scale = 0.5
    elseif scale > 2.5 then
        scale = 2.5
    end
    return floor((scale * 100) + 0.5) / 100
end

local function ClampSpacing(value)
    local spacing = floor((tonumber(value) or 6) + 0.5)
    if spacing < 0 then
        spacing = 0
    elseif spacing > 20 then
        spacing = 20
    end
    return spacing
end

local function NormalizeOrientation(value)
    if value == ORIENTATION_VERTICAL then
        return ORIENTATION_VERTICAL
    end
    return ORIENTATION_HORIZONTAL
end

local function NormalizeDirection(bucketName, orientation, value)
    local direction = value
    if direction == "CENTER" then
        direction = DIRECTION_CENTERED
    end

    if orientation == ORIENTATION_VERTICAL then
        if direction == DIRECTION_UP or direction == DIRECTION_DOWN or direction == DIRECTION_CENTERED then
            return direction
        end
        return DIRECTION_UP
    end

    if direction == DIRECTION_LEFT or direction == DIRECTION_RIGHT or direction == DIRECTION_CENTERED then
        return direction
    end

    return Module.TRACKER_DEFAULT_DIRECTION[bucketName] or DIRECTION_RIGHT
end

local function ResolveRelativeFrame(relativeTo)
    if type(relativeTo) == "string" then
        return _G[relativeTo] or UIParent
    end
    return relativeTo or UIParent
end

local function ResolveAnchorPosition(frameName)
    local pos = RefineUI.Positions and RefineUI.Positions[frameName]
    if type(pos) ~= "table" then
        return "CENTER", UIParent, "CENTER", 0, 0
    end

    local point = pos[1] or "CENTER"
    local relativeTo = ResolveRelativeFrame(pos[2])
    local relativePoint = pos[3] or point
    local x = pos[4] or 0
    local y = pos[5] or 0
    return point, relativeTo, relativePoint, x, y
end

local function SaveFramePosition(frameName, point, x, y)
    RefineUI.Positions = RefineUI.Positions or {}
    RefineUI.Positions[frameName] = { point, "UIParent", point, x, y }
end

function Module:IsEditModeActive()
    if RefineUI.LibEditMode
        and type(RefineUI.LibEditMode.IsInEditMode) == "function"
        and RefineUI.LibEditMode:IsInEditMode() then
        return true
    end

    local manager = _G.EditModeManagerFrame
    if not manager then
        return false
    end

    local shown = manager:IsShown()
    if IsSecret(shown) then
        return true
    end
    return shown and true or false
end

function Module:GetTrackerVisualSettings(bucketName)
    local cfg = self:GetConfig()
    cfg.BucketSettings = cfg.BucketSettings or {}
    cfg.BucketSettings[bucketName] = cfg.BucketSettings[bucketName] or {}

    local bucketCfg = cfg.BucketSettings[bucketName]
    local iconScale = bucketCfg.IconScale
    if type(iconScale) ~= "number" then
        local legacyIconSize = bucketCfg.IconSize
        if type(legacyIconSize) == "number" and legacyIconSize > 0 then
            iconScale = legacyIconSize / DEFAULT_ICON_BASE_SIZE
        else
            iconScale = cfg.IconScale or 1
        end
    end
    iconScale = ClampIconScale(iconScale)

    local spacing = ClampSpacing(bucketCfg.Spacing or cfg.Spacing)
    local orientation = NormalizeOrientation(bucketCfg.Orientation)
    local direction = NormalizeDirection(bucketName, orientation, bucketCfg.Direction)

    bucketCfg.IconScale = iconScale
    bucketCfg.Spacing = spacing
    bucketCfg.Orientation = orientation
    bucketCfg.Direction = direction
    return iconScale, spacing, orientation, direction, bucketCfg
end

function Module:BuildEditModeSettings(bucketName)
    self.editModeSettingsByBucket = self.editModeSettingsByBucket or {}
    if self.editModeSettingsByBucket[bucketName] then
        return self.editModeSettingsByBucket[bucketName]
    end

    if not RefineUI.LibEditMode or not RefineUI.LibEditMode.SettingType then
        return nil
    end

    local settings = {}
    settings[#settings + 1] = {
        kind = RefineUI.LibEditMode.SettingType.Dropdown,
        name = "Orientation",
        default = ORIENTATION_HORIZONTAL,
        values = {
            { text = "Horizontal", value = ORIENTATION_HORIZONTAL },
            { text = "Vertical", value = ORIENTATION_VERTICAL },
        },
        get = function()
            local _, _, orientation = Module:GetTrackerVisualSettings(bucketName)
            return orientation
        end,
        set = function(_, value)
            local _, _, _, _, bucketCfg = Module:GetTrackerVisualSettings(bucketName)
            bucketCfg.Orientation = NormalizeOrientation(value)
            bucketCfg.Direction = NormalizeDirection(bucketName, bucketCfg.Orientation, bucketCfg.Direction)
            Module:RequestRefresh()
        end,
    }

    settings[#settings + 1] = {
        kind = RefineUI.LibEditMode.SettingType.Dropdown,
        name = "Icon Direction",
        default = Module.TRACKER_DEFAULT_DIRECTION[bucketName] or DIRECTION_RIGHT,
        generator = function(_, rootDescription)
            local _, _, orientation, direction = Module:GetTrackerVisualSettings(bucketName)
            local options
            if orientation == ORIENTATION_VERTICAL then
                options = {
                    { text = "Up", value = DIRECTION_UP },
                    { text = "Down", value = DIRECTION_DOWN },
                    { text = "Centered", value = DIRECTION_CENTERED },
                }
            else
                options = {
                    { text = "Left", value = DIRECTION_LEFT },
                    { text = "Right", value = DIRECTION_RIGHT },
                    { text = "Centered", value = DIRECTION_CENTERED },
                }
            end

            for i = 1, #options do
                local option = options[i]
                rootDescription:CreateRadio(
                    option.text,
                    function(data)
                        return direction == data.value
                    end,
                    function(data)
                        local _, _, currentOrientation, _, bucketCfg = Module:GetTrackerVisualSettings(bucketName)
                        bucketCfg.Direction = NormalizeDirection(bucketName, currentOrientation, data.value)
                        Module:RequestRefresh()
                    end,
                    { value = option.value }
                )
            end
        end,
        get = function()
            local _, _, _, direction = Module:GetTrackerVisualSettings(bucketName)
            return direction
        end,
        set = function(_, value)
            local _, _, orientation, _, bucketCfg = Module:GetTrackerVisualSettings(bucketName)
            bucketCfg.Direction = NormalizeDirection(bucketName, orientation, value)
            Module:RequestRefresh()
        end,
    }

    settings[#settings + 1] = {
        kind = RefineUI.LibEditMode.SettingType.Slider,
        name = "Icon Scale",
        default = 1,
        minValue = 0.5,
        maxValue = 2.5,
        valueStep = 0.05,
        get = function()
            local iconScale = Module:GetTrackerVisualSettings(bucketName)
            return iconScale
        end,
        set = function(_, value)
            local _, _, _, _, bucketCfg = Module:GetTrackerVisualSettings(bucketName)
            bucketCfg.IconScale = ClampIconScale(value)
            Module:RequestRefresh()
        end,
    }

    settings[#settings + 1] = {
        kind = RefineUI.LibEditMode.SettingType.Slider,
        name = "Icon Spacing",
        default = 6,
        minValue = 0,
        maxValue = 20,
        valueStep = 1,
        get = function()
            local _, spacing = Module:GetTrackerVisualSettings(bucketName)
            return spacing
        end,
        set = function(_, value)
            local _, _, _, _, bucketCfg = Module:GetTrackerVisualSettings(bucketName)
            bucketCfg.Spacing = ClampSpacing(value)
            Module:RequestRefresh()
        end,
    }

    self.editModeSettingsByBucket[bucketName] = settings
    return settings
end

function Module:RegisterTrackerFrameEditMode(frame, bucketName)
    if not frame or not RefineUI.LibEditMode or type(RefineUI.LibEditMode.AddFrame) ~= "function" then
        return
    end

    if self:StateGet(frame, "editModeRegistered", false) then
        return
    end

    local frameName = self.TRACKER_FRAME_NAMES[bucketName]
    local pos = RefineUI.Positions and RefineUI.Positions[frameName]
    local default = {
        point = (pos and pos[1]) or "CENTER",
        x = (pos and pos[4]) or 0,
        y = (pos and pos[5]) or 0,
    }

    RefineUI.LibEditMode:AddFrame(frame, function(targetFrame, _, point, x, y)
        targetFrame:ClearAllPoints()
        targetFrame:SetPoint(point, UIParent, point, x, y)
        SaveFramePosition(frameName, point, x, y)
    end, default, FRAME_LABELS[bucketName] or "Cooldown Tracker")

    local settings = self:BuildEditModeSettings(bucketName)
    if settings and type(RefineUI.LibEditMode.AddFrameSettings) == "function" then
        RefineUI.LibEditMode:AddFrameSettings(frame, settings)
    end

    self:StateSet(frame, "editModeRegistered", true)
end

function Module:EnsureTrackerFrame(bucketName)
    self.trackerFrames = self.trackerFrames or {}
    local frame = self.trackerFrames[bucketName]
    if frame then
        return frame
    end

    local frameName = self.TRACKER_FRAME_NAMES[bucketName]
    frame = CreateFrame("Frame", frameName, UIParent)
    RefineUI.AddAPI(frame)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(25)
    frame.bucketName = bucketName
    frame.icons = {}
    frame:Hide()

    local point, relativeTo, relativePoint, x, y = ResolveAnchorPosition(frameName)
    frame:ClearAllPoints()
    frame:Point(point, relativeTo, relativePoint, x, y)
    frame:Size(44, 44)

    self.trackerFrames[bucketName] = frame
    self:RegisterTrackerFrameEditMode(frame, bucketName)
    return frame
end

function Module:EnsureTrackerIcon(frame, index)
    frame.icons = frame.icons or {}
    local iconFrame = frame.icons[index]
    if iconFrame then
        return iconFrame
    end

    iconFrame = CreateFrame("Frame", nil, frame)
    RefineUI.AddAPI(iconFrame)
    iconFrame:SetFrameLevel(frame:GetFrameLevel() + 1)
    RefineUI.SetTemplate(iconFrame, "Default")
    iconFrame:Hide()

    iconFrame.Icon = iconFrame:CreateTexture(nil, "ARTWORK")
    iconFrame.Icon:SetAllPoints()
    iconFrame.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    iconFrame.Cooldown = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
    iconFrame.Cooldown:SetAllPoints()
    iconFrame.Cooldown:SetDrawEdge(false)
    iconFrame.Cooldown:SetDrawSwipe(true)

    frame.icons[index] = iconFrame
    return iconFrame
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

function Module:RenderTrackerBucket(frame, activeEntries, iconScale, spacing, orientation, direction)
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

        local hasDurationObject = entry and HasValue(entry.duration)
        local hasCooldownWindow = entry and HasValue(entry.cooldownStartTime) and HasValue(entry.cooldownDuration)
        local appliedCooldown = false

        if icon.Cooldown and type(icon.Cooldown.SetUseAuraDisplayTime) == "function" then
            pcall(icon.Cooldown.SetUseAuraDisplayTime, icon.Cooldown, (hasDurationObject or hasCooldownWindow) and true or false)
        end

        if hasDurationObject and icon.Cooldown and icon.Cooldown.SetCooldownFromDurationObject then
            -- Keep this call signature aligned with Blizzard/CooldownCompanion.
            local ok = pcall(icon.Cooldown.SetCooldownFromDurationObject, icon.Cooldown, entry.duration)
            appliedCooldown = ok and true or false
        end

        -- If duration-object path fails (common in secret/taint-sensitive states),
        -- fall back to CDM-provided start/duration values.
        if not appliedCooldown and hasCooldownWindow and icon.Cooldown then
            local startTime = entry.cooldownStartTime
            local duration = entry.cooldownDuration
            local modRate = ResolveCooldownModRate(entry.cooldownModRate)

            -- Prefer direct widget call first so secret timing values are handed
            -- straight to C-side cooldown logic without Lua-side helper math.
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

            -- Some combat-protected start timestamps can fail SetCooldown even when
            -- duration is valid; duration-only path still keeps swipe/text running.
            if not appliedCooldown and icon.Cooldown.SetCooldownDuration then
                local ok = pcall(
                    icon.Cooldown.SetCooldownDuration,
                    icon.Cooldown,
                    duration,
                    modRate
                )
                appliedCooldown = ok and true or false
            end

            -- Keep Blizzard helper as non-secret compatibility fallback.
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

function Module:BuildAssignedTrackerEntry(cooldownID, activePayload)
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
        duration = activePayload and activePayload.duration,
        auraUnit = activePayload and activePayload.auraUnit,
        cooldownStartTime = activePayload and activePayload.cooldownStartTime,
        cooldownDuration = activePayload and activePayload.cooldownDuration,
        cooldownModRate = activePayload and activePayload.cooldownModRate,
    }
end

function Module:HideTrackers()
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

function Module:InitializeTrackers()
    self.trackerFrames = self.trackerFrames or {}
    for i = 1, #self.TRACKER_BUCKETS do
        local bucket = self.TRACKER_BUCKETS[i]
        self:EnsureTrackerFrame(bucket)
    end
end

function Module:RefreshTrackers()
    local assignments = self:GetCurrentAssignments()
    local assignedSnapshot = self.GetAssignedCooldownSnapshot and self:GetAssignedCooldownSnapshot() or nil
    local allAssignedIDs = assignedSnapshot and assignedSnapshot.allAssignedIDs or {}
    self.scratchBucketEntries = self.scratchBucketEntries or {}

    local inEditMode = self:IsEditModeActive()
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
