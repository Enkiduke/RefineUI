----------------------------------------------------------------------------------------
--	BWTimeline for RefineUI
--	This module provides a timeline interface for BigWigs boss mods in World of Warcraft.
--	It displays upcoming boss abilities and events on a graphical timeline.
--	Based on ElWigo by Oillamp, adapted and enhanced for RefineUI.
----------------------------------------------------------------------------------------

local R, C, L = unpack(RefineUI)
if C.bwtimeline.enable ~= true then
    return
end

----------------------------------------------------------------------------------------
--	Initialization and Setup
----------------------------------------------------------------------------------------

local anchor = CreateFrame("Frame", "RefineUI_BWTimeline", UIParent)
anchor:SetSize(C.bwtimeline.bar_width + C.bwtimeline.icons_width, C.bwtimeline.bar_length)
anchor:SetPoint(unpack(C.position.bwtimeline))

local RefineUIBWTimeline = LibStub("AceAddon-3.0"):NewAddon("RefineUIBWTimeline", "AceTimer-3.0")

local BWT = RefineUIBWTimeline
local pairs, ipairs = pairs, ipairs
local floor = math.floor
local abs, min, max = math.abs, math.min, math.max
local tremove = table.remove
local tsort = table.sort
local tinsert = table.insert
local unpack = unpack
local frameTemplate = "BackdropTemplate"
local IsEncounterInProgress = IsEncounterInProgress
local UnitGUID, UnitExists, UnitLevel, UnitClassification = UnitGUID, UnitExists, UnitLevel, UnitClassification
local IsInInstance = IsInInstance

-- Debug utility
local function NPDBG(...)
    if C and C.bwtimeline and C.bwtimeline.np_debug then
        print("[BWT:NP]", ...)
    end
end

-- Cache some global functions/values used in hot paths (safe rawget)
local GetTime = rawget(_G, 'GetTime') or function() return 0 end
local UnitName = rawget(_G, 'UnitName') or function() return "player" end
local GetSpellInfo = rawget(_G, 'GetSpellInfo') or function() return nil end
local GetSpellTexture = rawget(_G, 'GetSpellTexture') or nil
local GetRaidTargetIndex = rawget(_G, 'GetRaidTargetIndex') or nil
local CombatLogGetCurrentEventInfo = rawget(_G, 'CombatLogGetCurrentEventInfo') or function() return nil end

----------------------------------------------------------------------------------------
--	Utility Functions
----------------------------------------------------------------------------------------

local dirToAnchors = {
    ABOVE = { "TOP", "BOTTOM" },
    BELOW = { "BOTTOM", "TOP" },
    LEFT = { "LEFT", "RIGHT" },
    RIGHT = { "RIGHT", "LEFT" },
    CENTER = { "CENTER", "CENTER" }
}

local function createTimelineBar()
    local f = CreateFrame("Frame", "RefineUI_BWTimelineBar", UIParent, frameTemplate)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(5)
    f:SetTemplate("Transparent")

    f.frames = {}
    f.framesDirty = false
    f.queued = {}
    f._acc = 0

    f.texture = f:CreateTexture(nil, "BACKGROUND")
    f.texture:SetAllPoints()

    return f
end

BWT.bar = createTimelineBar()

----------------------------------------------------------------------------------------
--	Timeline Bar Management
----------------------------------------------------------------------------------------

function BWT:updateTimelineBar()
    local bar = BWT.bar

    -- Cache frequently used config on the bar for hot paths
    bar.max_time = C.bwtimeline.bar_max_time
    bar:ClearAllPoints()
    bar:SetPoint("CENTER", anchor)
    bar:SetSize(C.bwtimeline.bar_width, C.bwtimeline.bar_length)

    bar.startAnchor = C.bwtimeline.bar_reverse and "BOTTOM" or "TOP"
    bar.endAnchor = C.bwtimeline.bar_reverse and "TOP" or "BOTTOM"
    bar.x_mul = 0
    bar.y_mul = C.bwtimeline.bar_reverse and -1 or 1
    bar.lengthPerTime = C.bwtimeline.bar_length / C.bwtimeline.bar_max_time

    bar.icons_height = C.bwtimeline.icons_height
    bar.icons_spacing = C.bwtimeline.icons_spacing
    bar.icons_duration = C.bwtimeline.icons_duration
    bar.max_queue_icons = C.bwtimeline.max_queue_icons or 6
    bar.smoothing = C.bwtimeline.smoothing or 0.15
    bar.eps = C.bwtimeline.snap_eps or 0.25
    bar.update_hz = C.bwtimeline.hz or 120
    if bar.update_hz <= 0 then bar.update_hz = 120 end
    bar.update_dt = 1 / bar.update_hz
    -- Precompute smoothing factor for the common tick to avoid pow() each update
    local smooth = bar.smoothing or 0.15
    bar._kPerTick = 1 - (1 - smooth) ^ (60 / bar.update_hz)
    bar.np_max_concurrent = C.bwtimeline.np_max_concurrent or 6
    bar._acc = 0
    bar._queuedFP = nil

    self:updateTimelineBarVisibility()

    -- Create and update ticks (textures-only on a dedicated layer frame)
    bar.tickLayer = bar.tickLayer or CreateFrame("Frame", nil, bar)
    bar.tickLayer:SetFrameStrata("MEDIUM")
    bar.tickLayer:SetFrameLevel(bar:GetFrameLevel() + (C.bwtimeline.bar_above_icons and 6 or 1))

    bar.ticks = bar.ticks or {}
    bar.tickTexts = bar.tickTexts or {}
    local ticks = bar.ticks
    local tickTexts = bar.tickTexts

    local maxBars = floor(C.bwtimeline.bar_max_time / C.bwtimeline.bar_tick_spacing)
    if C.bwtimeline.bar_max_time % C.bwtimeline.bar_tick_spacing == 0 then
        maxBars = maxBars - 1
    end
    local N = max(#ticks, maxBars)

    for i = 1, N do
        -- Ensure we have a texture for the tick; migrate from old Frame-based ticks if needed
        local prev = ticks[i]
        if (not prev) or (prev.GetObjectType and prev:GetObjectType() ~= "Texture") then
            if prev and prev.Hide then prev:Hide() end
            ticks[i] = bar.tickLayer:CreateTexture(nil, C.bwtimeline.bar_above_icons and "OVERLAY" or "ARTWORK")
        end
        local tex = ticks[i]
        if (not C.bwtimeline.bar_has_ticks) or i > maxBars then
            tex:Hide()
            if tickTexts[i] then tickTexts[i]:Hide() end
        else
            tex:Show()
            local thicknessOffset = floor(C.bwtimeline.bar_tick_width / 2)
            local l = i * C.bwtimeline.bar_tick_spacing * bar.lengthPerTime + thicknessOffset
            tex:ClearAllPoints()
            tex:SetPoint("TOP", bar, bar.endAnchor, bar.x_mul * l, bar.y_mul * l)
            tex:SetSize(C.bwtimeline.bar_tick_length, C.bwtimeline.bar_tick_width)
            tex:SetColorTexture(unpack(C.bwtimeline.bar_tick_color))

            if C.bwtimeline.bar_tick_text then
                if not tickTexts[i] or (tickTexts[i].GetObjectType and tickTexts[i]:GetObjectType() ~= "FontString") then
                    tickTexts[i] = bar.tickLayer:CreateFontString(nil,
                        C.bwtimeline.bar_above_icons and "OVERLAY" or "ARTWORK")
                end
                local txt = tickTexts[i]
                txt:Show()
                local a1, a2 = unpack(dirToAnchors[C.bwtimeline.bar_tick_text_position])
                txt:ClearAllPoints()
                txt:SetPoint(a2, tex, a1)
                txt:SetTextColor(unpack(C.bwtimeline.bar_tick_text_color))
                txt:SetFont(unpack(C.font.bwt.tick))
                txt:SetShadowOffset(1, -1)
                txt:SetText(i * C.bwtimeline.bar_tick_spacing)
            elseif tickTexts[i] then
                tickTexts[i]:Hide()
            end
        end
    end
end

----------------------------------------------------------------------------------------
--	Icon Frame Management
----------------------------------------------------------------------------------------

local FRAME_ID_COUNTER = 0
local framePool = {}
-- Fast lookup indices for O(1) removals
-- inner maps are set to weak-value tables so frames can be GC'd if nothing else references them
local nameIndex, idIndex = {}, {}
-- Make inner maps weak-valued so holding an entry doesn't prevent frame GC if it's otherwise
-- unreferenced (each nameIndex[name] is a table mapping id -> frame; we want its values to be weak)
local function makeWeakValueMap()
    local mt = { __mode = "v" }
    local t = {}
    setmetatable(t, mt)
    return t
end

-- wrapper getters that ensure inner maps use weak-value tables
local function getNameMap(key)
    local m = nameIndex[key]
    if not m then
        m = makeWeakValueMap()
        nameIndex[key] = m
    end
    return m
end

local function getIDMap(key)
    local m = idIndex[key]
    if not m then
        m = makeWeakValueMap()
        idIndex[key] = m
    end
    return m
end

-- Small cache for tostring of keys to avoid churn
local keyCache = setmetatable({}, {
    __index = function(t, k)
        local v = tostring(k)
        rawset(t, k, v)
        return v
    end
})

-- Cache player name and some globals used in hot paths
local PLAYER_NAME = UnitName("player")
do
    local nameUpdater = CreateFrame("Frame")
    nameUpdater:RegisterEvent("UNIT_NAME_UPDATE")
    nameUpdater:SetScript("OnEvent", function(_, event, unit)
        if unit == "player" then PLAYER_NAME = UnitName("player") end
    end)
end

-- Mob frame tracking for efficient label refreshes
local mobFrames = {}
local mobByGUID = {}

function BWT:_MobTrackAdd(frame)
    if not (frame and frame._isMob and frame._mobGUID) then return end
    tinsert(mobFrames, frame)
    frame._mobIndex = #mobFrames
    local arr = mobByGUID[frame._mobGUID]
    if not arr then
        arr = {}
        mobByGUID[frame._mobGUID] = arr
    end
    tinsert(arr, frame)
    frame._mobGuidIndex = #arr
end

function BWT:_MobTrackRemove(frame)
    if not (frame and frame._isMob) then return end
    -- Remove from mobFrames array
    local idx = frame._mobIndex
    if idx then
        local last = mobFrames[#mobFrames]
        mobFrames[idx] = last
        mobFrames[#mobFrames] = nil
        if last then last._mobIndex = idx end
        frame._mobIndex = nil
    end
    -- Remove from GUID list
    local guid = frame._mobGUID
    if guid then
        local arr = mobByGUID[guid]
        if arr then
            local i = frame._mobGuidIndex
            if i then
                local last = arr[#arr]
                arr[i] = last
                arr[#arr] = nil
                if last then last._mobGuidIndex = i end
                frame._mobGuidIndex = nil
            end
            if #arr == 0 then mobByGUID[guid] = nil end
        end
    end
end

-- Cache BigWigs globals pointer; refreshed on ADDON_LOADED below
local BWCore = rawget(_G, 'BigWigs')
local BWLoader = rawget(_G, 'BigWigsLoader')

-- Layout dirty flag: only recompute heavy layout when necessary
BWT._layoutDirty = true

-- helper: binary-insert frames by expTime (stable by id)
local function insertByExp(frames, f)
    local lo, hi = 1, #frames
    while lo <= hi do
        local mid = floor((lo + hi) / 2)
        local mf = frames[mid]
        if mf.expTime < f.expTime or (mf.expTime == f.expTime and mf.id < f.id) then
            lo = mid + 1
        else
            hi = mid - 1
        end
    end
    tinsert(frames, lo, f)
end

local function createIconFrame()
    local f
    if #framePool > 0 then
        f = tremove(framePool)
        f.lastDisplayedSecond = -1
        f.isWithinMaxTime = false
        f:SetFrameStrata("MEDIUM")
        -- Reset position/target values
        f.currentX, f.currentY = 0, 0
        f.targetX, f.targetY = 0, 0
        f.prevXI, f.prevYI = nil, nil
        f.targetAnchorFrame = nil
        f.targetAnchorPoint = nil
        f.targetRelativePoint = nil
        f._prevTargetAnchorPoint = nil
        f._prevTargetRelativePoint = nil
        f.positioned = nil
        f:SetScript("OnUpdate", nil)

        -- Clear per-use state to avoid leaking visuals/logic across pooled frames
        f._isMob = nil
        f._mobGUID = nil
        f._baseLabel = nil
        f._renderedLabel = nil
        f.number = nil
        f._lastBorderR, f._lastBorderG, f._lastBorderB, f._lastBorderA = nil, nil, nil, nil
        f._lastTargeted = nil

        -- Reset dynamic styling (avoid re-applying full template on reuse)
        if f.border and f.border.SetBackdropBorderColor then
            f.border:SetBackdropBorderColor(unpack(C.media.borderColor))
        end
        if f.icon and f.icon.SetDesaturated then
            f.icon:SetDesaturated(false)
        end
        if f.SetAlpha then
            f:SetAlpha(1)
        end
        if f.nameText and f.nameText.SetFont then
            f.nameText:SetFont(unpack(C.font.bwt.default))
            f.nameText:SetShadowOffset(1, -1)
            if f.nameText.SetText then f.nameText:SetText("") end
        end
        if f.durationText and f.durationText.SetFont then
            f.durationText:SetFont(unpack(C.font.bwt.duration))
            f.durationText:SetShadowOffset(1, -1)
            if f.durationText.SetText then f.durationText:SetText("") end
        end
    else
        f = CreateFrame("Frame", nil, UIParent, frameTemplate)
        f:SetFrameStrata("MEDIUM")

        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetAllPoints()

        f.nameText = f:CreateFontString(nil, "OVERLAY")
        f.nameText:SetFont(unpack(C.font.bwt.default))
        f.nameText:SetShadowOffset(1, -1)

        f.durationText = f:CreateFontString(nil, "OVERLAY")
        f.durationText:SetFont(unpack(C.font.bwt.duration))
        f.durationText:SetShadowOffset(1, -1)
        f.durationText:SetPoint("CENTER")

        FRAME_ID_COUNTER = FRAME_ID_COUNTER + 1
        f.id = FRAME_ID_COUNTER

        f.lastDisplayedSecond = -1
        f.isWithinMaxTime = false
        -- Initialize position/target values
        f.currentX, f.currentY = 0, 0
        f.targetX, f.targetY = 0, 0
        f.prevXI, f.prevYI = nil, nil
        f.targetAnchorFrame = nil
        f.targetAnchorPoint = nil
        f.targetRelativePoint = nil
        f._prevTargetAnchorPoint = nil
        f._prevTargetRelativePoint = nil
        f.positioned = nil
        f:SetScript("OnUpdate", nil)

        f:SetTemplate("Icon")  -- only apply template for brand-new frames
        f.border:SetBackdropBorderColor(unpack(C.media.borderColor))
    end

    return f
end

function BWT:updateFrameParameters(frame)
    local w = (frame.iconSettings and frame.iconSettings.width) or C.bwtimeline.icons_width
    local h = (frame.iconSettings and frame.iconSettings.height) or C.bwtimeline.icons_height
    frame:SetSize(w, h)
    frame:SetFrameLevel(frame.bar_:GetFrameLevel() + 4)

    -- Check if the icon name contains the player's name
    if frame.name and PLAYER_NAME and frame.name:find(PLAYER_NAME) then
        frame.textColor = C.mrtreminder.barColor or { 0, 1, 0, 1 }
        local borderColor = C.mrtreminder.barColor or { 0, 1, 0, 1 }
        frame.border:SetBackdropBorderColor(unpack(borderColor))
    else
        frame.textColor = C.bwtimeline.icons_name_color or { 1, 1, 1, 1 }
        frame.border:SetBackdropBorderColor(unpack(C.media.borderColor))
    end

    -- Fonts are assigned at frame creation/reuse. To avoid repeated SetFont calls in this hot
    -- path we don't call SetFont here. Use BWT:Retheme() to reapply fonts when UI theme/settings
    -- change.

    if C.bwtimeline.icons_name then
        frame.nameText:Show()
        frame.nameText:ClearAllPoints()
        local a1, a2 = unpack(dirToAnchors[C.bwtimeline.icons_name_position])
        frame.nameText:SetPoint(a2, frame, a1, 4, 0)
        frame.nameText:SetTextColor(unpack(frame.textColor))

        local label = frame._renderedLabel or frame._baseLabel or frame.displayName or frame.name
        if C.bwtimeline.icons_name_number and frame.number then
            label = label .. " " .. frame.number
        end
        frame.nameText:SetText(label)
        frame.nameText:SetJustifyH("LEFT")
        frame.nameText:SetJustifyV("MIDDLE")
    else
        frame.nameText:Hide()
    end

    if C.bwtimeline.icons_duration then
        frame.durationText:Show()
        frame.durationText:SetTextColor(unpack(C.bwtimeline.icons_duration_color))
    else
        frame.durationText:Hide()
    end

    frame.icon:SetTexture(frame.iconID)
    frame.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    frame.icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)

    -- Ensure mob labels are fully rendered (marker/chevrons) after font setup
    if frame._isMob then BWT:RefreshMobLabel(frame) end
end

function BWT:removeFrame(frame)
    frame:SetScript("OnUpdate", nil)
    frame:Hide()
    frame:ClearAllPoints()
    frame:SetParent(nil)

    -- Untrack mob frames if applicable
    if frame._isMob then
        self:_MobTrackRemove(frame)
    end

    tinsert(framePool, frame)

    local bar = frame.bar_
    local frames = bar.frames
    -- remove from ordered frames table
    for i = #frames, 1, -1 do
        if frames[i] and frames[i].id == frame.id then
            tremove(frames, i)
            break
        end
    end

    -- frames remain sorted after removal; no need to mark framesDirty

    -- remove from indices for O(1) lookups
    if frame.name then
        local nmap = nameIndex[frame.name]
        if nmap then
            nmap[frame.id] = nil
            -- inner maps are weak-valued; if empty we can nil the reference
            if not next(nmap) then nameIndex[frame.name] = nil end
        end
    end
    if frame.spellID then
        local imap = idIndex[frame.spellID]
        if imap then
            imap[frame.id] = nil
            if not next(imap) then idIndex[frame.spellID] = nil end
        end
    end

    if #frames == 0 then
        if bar:GetScript("OnUpdate") then
            bar:SetScript("OnUpdate", nil)
        end
        self:updateTimelineBarVisibility()
    end
end

----------------------------------------------------------------------------------------
--	Frame Update and Positioning
----------------------------------------------------------------------------------------

-- Helper to place frames with minimal churn; only sets points when necessary
local function placeFrame(f, targetFrame, a1, a2, x, y)
    local xi, yi = floor(x + 0.5), floor(y + 0.5)
    local anchorChanged = (f._prevTargetAnchorPoint ~= a1) or (f._prevTargetRelativePoint ~= a2)
    if anchorChanged then f:ClearAllPoints() end
    if (not f.positioned) or anchorChanged or (f.prevXI ~= xi or f.prevYI ~= yi) then
        f:SetPoint(a1, targetFrame, a2, xi, yi)
        f.prevXI, f.prevYI = xi, yi
        f.positioned = true
    end
    f._prevTargetAnchorPoint, f._prevTargetRelativePoint = a1, a2
    if not f:IsShown() then f:Show() end
end

-- duration formatting avoided in hot path; use SetFormattedText in-place

-- Single driver: updates all frames on the bar, sorts when dirty, smooths movement,
-- and caps queue size. Replaces per-frame OnUpdate and the repeating updateAnchors timer.
local function timelineDriver(self, elapsed)
    -- Accumulate elapsed to throttle updates
    self._acc = (self._acc or 0) + (elapsed or 0)
    if self._acc < (self.update_dt or 0) then return end
    local dt = self._acc
    self._acc = 0

    local t = GetTime()
    local frames = self.frames
    local n = #frames
    if n == 0 then
        self:SetScript("OnUpdate", nil)
        BWT:updateTimelineBarVisibility()
        return
    end

    if self.framesDirty then
        tsort(frames, function(a, b)
            if a.expTime == b.expTime then return a.id < b.id end
            return a.expTime < b.expTime
        end)
        self.framesDirty = false
    end

    -- Pre-cached config
    local lengthPerTime = self.lengthPerTime
    local maxTime = self.max_time or 0
    local maxExp = t + maxTime
    local spacing = self.icons_spacing or 0
    local iconH = self.icons_height or 0
    local maxQueue = self.max_queue_icons or 6

    -- Duration text update and visible/queue classification
    local queued = self.queued
    for i = #queued, 1, -1 do queued[i] = nil end

    local lastPos = nil
    local mobShown = 0
    local mobCap = self.np_max_concurrent or 6
    for i = 1, n do
        local f = frames[i]
        local dur = f.expTime - t
        f.remDuration = dur

        if self.icons_duration then
            local sec = floor(dur + 0.5)
            if sec ~= f.lastDisplayedSecond then
                if sec <= 60 then
                    f.durationText:SetFormattedText("%d", sec)
                else
                    f.durationText:SetFormattedText("%d:%02d", floor(sec / 60), sec % 60)
                end
                f.lastDisplayedSecond = sec
            end
        end

        if f.expTime <= maxExp then
            -- Optional cap: limit number of mob icons on the bar
            local skipVisibleLayout = false
            if f._isMob then
                if mobShown >= mobCap then
                    -- Skip layout for this mob icon this tick
                    f.targetAnchorFrame = nil
                    skipVisibleLayout = true
                else
                    mobShown = mobShown + 1
                end
            end

            if not skipVisibleLayout then
                if not f.isWithinMaxTime then
                    f.isWithinMaxTime = true
                end
                local ideal = dur * lengthPerTime
                if lastPos ~= nil then
                    local minDist = iconH + spacing
                    if (ideal - lastPos) < minDist then
                        ideal = lastPos + minDist
                    end
                end
                -- Clamp to bar end
                local maxIdeal = maxTime * lengthPerTime
                if ideal > maxIdeal then ideal = maxIdeal end
                lastPos = ideal

                -- Target relative to bar endAnchor (no SetPoint here)
                f.targetX = ideal * self.x_mul
                f.targetY = ideal * self.y_mul
                f.targetAnchorFrame = self
                f.targetAnchorPoint = "CENTER"
                f.targetRelativePoint = self.endAnchor
            end
        else
            if f.isWithinMaxTime then
                f.isWithinMaxTime = false
            end
            tinsert(queued, f)
        end
    end

    -- Layout queued icons (cap) using a lightweight fingerprint; no SetPoint here
    local qn = (#queued < maxQueue) and #queued or maxQueue
    local fp = qn
    for i = 1, qn do
        local id = queued[i].id or 0
        fp = (fp * 1315423911 + id) % 2147483647
    end
    if self._queuedFP ~= fp then
        for i = 1, #queued do
            local f = queued[i]
            if i <= maxQueue then
                f.targetX = 0
                f.targetY = spacing + (i - 1) * (iconH + spacing)
                f.targetAnchorFrame = self
                f.targetAnchorPoint = "BOTTOM"
                f.targetRelativePoint = "TOP"
            else
                f.targetAnchorFrame = nil
            end
        end
        self._queuedFP = fp
    end

    -- Smooth and apply placement; also remove expired frames
    local smooth = self.smoothing or 0.15
    local k
    if self._kPerTick and abs(dt - (self.update_dt or 0)) < 1e-3 then
        k = self._kPerTick
    else
        k = 1 - (1 - smooth) ^ (dt * 60)
    end
    if k > 1 then k = 1 end

    for i = n, 1, -1 do
        local f = frames[i]
        if t > f.expTime then
            BWT:removeFrame(f)
        elseif f.targetAnchorFrame then
            -- Adjust frame strata based on within-bar status
            if f.isWithinMaxTime then
                if f:GetFrameStrata() ~= "HIGH" then f:SetFrameStrata("HIGH") end
            else
                if f:GetFrameStrata() ~= "MEDIUM" then f:SetFrameStrata("MEDIUM") end
            end

            local anchorChanged = (f._prevTargetAnchorPoint ~= f.targetAnchorPoint) or (f._prevTargetRelativePoint ~= f.targetRelativePoint)
            if not f.positioned or anchorChanged then
                -- Snap immediately when first placed or anchor context changes (queue <-> bar)
                f.currentX, f.currentY = f.targetX, f.targetY
            else
                -- Smooth normally when staying on the same anchor context
                f.currentX = f.currentX + (f.targetX - f.currentX) * k
                f.currentY = f.currentY + (f.targetY - f.currentY) * k
            end
            placeFrame(f, f.targetAnchorFrame, f.targetAnchorPoint, f.targetRelativePoint, f.currentX, f.currentY)
        else
            -- No target anchor this tick; ensure it is hidden
            if f:IsShown() then f:Hide() end
        end
    end
end

function BWT:createTimelineIcon(spellID, name, duration, iconID, customSettings)
    if not duration or type(duration) ~= "number" or duration <= 0 then
        print("Invalid duration for timeline icon:", name, duration)
        return nil
    end

    local frame = createIconFrame()
    local bar = self.bar

    frame.bar_ = bar
    frame.iconSettings = customSettings or C.bwtimeline.icons
    frame.name = name
    frame.spellID = spellID
    frame.size = frame.iconSettings.width or C.bwtimeline.icons_width
    frame.duration = duration
    frame.spawnTime = GetTime()
    frame.expTime = frame.spawnTime + duration
    frame.iconID = iconID
    frame.max_time = bar.max_time
    frame.anchored = false
    frame.lastUpdated = 0
    frame.refresh_rate = C.bwtimeline.refresh_rate

    self:updateFrameParameters(frame)

    -- Insert into ordered frames via binary insert (keeps array mostly sorted)
    insertByExp(bar.frames, frame)
    bar.framesDirty = false

    -- Populate lookup indices for O(1) removals
    if frame.name then
        local nmap = getNameMap(frame.name)
        nmap[frame.id] = frame
    end
    if frame.spellID then
        local imap = getIDMap(frame.spellID)
        imap[frame.id] = frame
    end

    frame:SetParent(bar)
    frame:SetFrameLevel(bar:GetFrameLevel() + 4)
    frame:Hide()

    -- Ensure the driver is running
    if not bar:GetScript("OnUpdate") then
        bar._acc = 0
        bar:SetScript("OnUpdate", timelineDriver)
    end

    self:updateTimelineBarVisibility()
    return frame
end

----------------------------------------------------------------------------------------
--	Anchor and Position Management
----------------------------------------------------------------------------------------



----------------------------------------------------------------------------------------
--	Icon Management Functions
----------------------------------------------------------------------------------------

function BWT:removeAllIcons()
    local frames = self.bar.frames
    for i = #frames, 1, -1 do
        local f = frames[i]
        if not (f and f.name == "Respawn") then
            self:removeFrame(f)
        end
    end
    self:updateTimelineBarVisibility()
end

function BWT:removeIconByName(name, all)
    if not name then return end
    local map = nameIndex[name]
    if not map then return end
    local ids = {}
    for id in pairs(map) do tinsert(ids, id) end
    for i = 1, #ids do
        local f = map[ids[i]]
        if f then self:removeFrame(f) end
        if not all then break end
    end
end

function BWT:removeIconByID(ID, all)
    if not ID then return end
    local map = idIndex[ID]
    if not map then return end
    local ids = {}
    for id in pairs(map) do tinsert(ids, id) end
    for i = 1, #ids do
        local f = map[ids[i]]
        if f then self:removeFrame(f) end
        if not all then break end
    end
end


-- Re-apply fonts/templates to all existing frames and pooled frames.
function BWT:Retheme()
    -- Reapply fonts and border colors for live frames
    if self.bar and self.bar.frames then
        for i = 1, #self.bar.frames do
            local f = self.bar.frames[i]
            if f then
                if f.nameText and f.nameText.SetFont then f.nameText:SetFont(unpack(C.font.bwt.default)) end
                if f.durationText and f.durationText.SetFont then f.durationText:SetFont(unpack(C.font.bwt.duration)) end
                if f.border and f.border.SetBackdropBorderColor then f.border:SetBackdropBorderColor(unpack(C.media.borderColor)) end
            end
        end
    end

    -- Also reapply to pooled frames
    for i = 1, #framePool do
        local f = framePool[i]
        if f then
            if f.nameText and f.nameText.SetFont then f.nameText:SetFont(unpack(C.font.bwt.default)) end
            if f.durationText and f.durationText.SetFont then f.durationText:SetFont(unpack(C.font.bwt.duration)) end
            if f.border and f.border.SetBackdropBorderColor then f.border:SetBackdropBorderColor(unpack(C.media.borderColor)) end
        end
    end
end

function BWT:removeByPrefix(prefix)
    local frames = self.bar.frames
    for i = #frames, 1, -1 do
        local f = frames[i]
        if f and f.name and f.name:sub(1, #prefix) == prefix then
            self:removeFrame(f)
        end
    end
end

----------------------------------------------------------------------------------------
--	Custom Timer Initialization
----------------------------------------------------------------------------------------


function BWT:initializeCustomTimers()
    if not self.engageID then
        return
    end
    local bossSettings = C.bwtimeline.bosses and C.bwtimeline.bosses[self.engageID]
    if not bossSettings then
        return
    end

    for _, extraKey in ipairs(bossSettings.__extras or {}) do
        local p = C.bwtimeline.icons

        if p then
            local icon
            if p.automaticIcon then
                icon = 134400
            end

            local prevTime = 0

            if p.customType == "Time" then
                for i, t in ipairs(p.customTimes) do
                    if i == 1 then
                        self:createTimelineIcon(extraKey, extraKey, t, icon, p)
                    else
                        BWT:ScheduleTimer(BWT.createTimelineIcon, prevTime, BWT, extraKey, extraKey, t - prevTime, icon,
                            p)
                    end
                    prevTime = t
                end
            end
        end
    end
end

----------------------------------------------------------------------------------------
--	Phase Management
----------------------------------------------------------------------------------------

function BWT:updatePhase(stage)
    if type(stage) == "string" then
        local num = tonumber(stage:match("%d+$"))
        stage = num or stage
    end

    if type(stage) == "number" then
        self.phase = stage
        self.phaseCount = (self.phaseCount or 0) + 1 -- Use 0 as default if phaseCount is nil
    end
end

----------------------------------------------------------------------------------------
--	Visibility Management
----------------------------------------------------------------------------------------

function BWT:updateTimelineBarVisibility()
    local bar = self.bar
    if #bar.frames > 0 or self.optionsOpened then -- Show if frames exist OR options are open
        bar:Show()
    else                                          -- Hide only if no frames and options are closed
        bar:Hide()
    end
end

----------------------------------------------------------------------------------------
--	Initialization
----------------------------------------------------------------------------------------

function BWT:OnInitialize()
    self.encounterID = nil
    self.phase = 1
    self.phaseCount = 0
    self.bigWigs:registerAllMessages()

    self:updateTimelineBar()

    -- Optionally disable BigWigs Bars plugin visuals entirely
    local BWCore = rawget(_G, 'BigWigs')
    if BWCore and BWCore.GetPlugin and not C.bwtimeline.show_bigwigs_bars then
        local bars = BWCore:GetPlugin("Bars", true)
        if bars and bars.Disable then bars:Disable() end
    end

    -- Initialize nameplate bridge gating on login
    if self.UpdateNPBridge then
        self:UpdateNPBridge()
    end
end

-- RefineUI: Permanently disable BigWigs boss-mod nameplate icons at the source.
-- Strips the NAMEPLATE bit from ALL boss-module options in the CURRENT BigWigs profile,
-- and keeps it stripped on profile swaps & new module loads.

do
    local bit = bit

    local function stripNameplateBit()
        local loader = rawget(_G, "BigWigsLoader")
        local BW     = rawget(_G, "BigWigs")
        if not (loader and loader.db and loader.db.GetCurrentProfile and BW and BW.C and BW.C.NAMEPLATE) then
            return 0
        end

        local profile = loader.db:GetCurrentProfile()
        local db      = rawget(_G, "BigWigs3DB")
        local CNP     = BW.C.NAMEPLATE
        local changed = 0

        if type(profile) == "string" and type(db) == "table" and type(db.namespaces) == "table" then
            for nsName, ns in next, db.namespaces do
                if type(nsName) == "string"
                    and nsName:find("BigWigs_Bosses", 1, true)
                    and type(ns) == "table"
                    and type(ns.profiles) == "table"
                    and type(ns.profiles[profile]) == "table" then
                    for optKey, optVal in next, ns.profiles[profile] do
                        if type(optVal) == "number" and optVal > 10 and bit.band(optVal, CNP) == CNP then
                            ns.profiles[profile][optKey] = optVal - CNP
                            changed = changed + 1
                        end
                    end
                end
            end
        end

        -- Mirror the plugin's UI toggle so future modules respect the disable
        loader.db.profile.bossModNameplatesDisabled = true
        return changed
    end

    local function nukeAndReport(tag)
        local n = stripNameplateBit()
        -- Only report when something changed, or on manual invocation
        if (n > 0 or tag == "manual") and C and C.bwtimeline and C.bwtimeline.np_debug then
            print(("[BWT:NP] NAMEPLATE bit stripped from %d options%s"):format(n, tag and (" (" .. tag .. ")") or ""))
        end
    end

    -- 1) Run at login and whenever BigWigs loads
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(_, ev, addon)
        if ev == "PLAYER_LOGIN"
            or addon == "BigWigs"
            or addon == "BigWigs_Core"
            or addon == "BigWigs_Plugins" then
            if C and C.bwtimeline and C.bwtimeline.hide_bw_nameplate_icons then
                nukeAndReport("load")
            end
        end
    end)

    -- 2) Re-apply on profile change and when new boss modules register
    local loader = rawget(_G, "BigWigsLoader")
    if loader and loader.RegisterMessage then
        -- DOT call (target first)
        loader.RegisterMessage(BWT, "BigWigs_ProfileUpdate", function() nukeAndReport("profile swap") end)
        loader.RegisterMessage(BWT, "BigWigs_BossModuleRegistered", function() nukeAndReport("new boss") end)
    end

    -- 3) Optional: handy slash to run on demand
    SLASH_RUI_NPNuke1 = "/rui_npnuke"
    SlashCmdList.RUI_NPNuke = function() nukeAndReport("manual") end
end

----------------------------------------------------------------------------------------
--	BigWigs Integration + Nameplate Bridge
----------------------------------------------------------------------------------------

-- Forward declaration for NP cleaner so lifecycle hooks can reference it
local npCleaner

BWT.bigWigs = {}
local BW = BWT.bigWigs
LibStub("AceEvent-3.0"):Embed(BW)

-- Boss filter helper
local function isBossGUID(guid)
    if not guid then return false end
    for i = 1, 5 do
        local u = "boss" .. i
        if UnitExists(u) and UnitGUID(u) == guid then return true end
    end
    local loader = rawget(_G, 'BigWigsLoader')
    if loader and loader.UnitTokenFromGUID then
        local u = loader.UnitTokenFromGUID(guid)
        if u then
            if UnitClassification(u) == "worldboss" then return true end
            if UnitLevel(u) == -1 then return true end
        end
    end
    return false
end

-- Nameplate bridge state and helpers
local npIndex = {}
local function npKey(guid, key) return "NP_" .. (guid or "nil") .. "_" .. keyCache[key] end
local function parseRemaining(length) return type(length) == "table" and length[1] or length end

-- Label helpers for NP icons
local function AbilityLabel(module, key, customIconOrText)
    if type(customIconOrText) == "string" and customIconOrText ~= "" then
        return customIconOrText
    end
    if type(key) == "number" and GetSpellInfo then
        local n = GetSpellInfo(key)
        if n then return n end
    end
    if module and module.SpellName then
        local n = module:SpellName(key)
        if n then return n end
    end
    return tostring(key)
end

local GOLD, WHITE, RESET = "|cffffd100", "|cffffffff", "|r"
local function UnitTokenFromGUIDSafe(guid)
    local loader = rawget(_G, 'BigWigsLoader')
    if loader and loader.UnitTokenFromGUID then
        local u = loader.UnitTokenFromGUID(guid)
        if u and UnitExists(u) then return u end
    end
    for i = 1, 40 do
        local u = ("nameplate%d"):format(i)
        if UnitExists(u) and UnitGUID(u) == guid then
            return u
        end
    end
end

local function RaidMarkerTextureTag(unit, size)
    local idx = unit and GetRaidTargetIndex and GetRaidTargetIndex(unit)
    if not idx then return nil end
    size = size or (C and C.bwtimeline and C.bwtimeline.marker_icon_size) or 14
    return ("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:%d:%d:0:0|t"):format(idx, size, size)
end

function BWT:RefreshMobLabel(frame)
    if not (frame and frame._isMob) then return end
    local guid = frame._mobGUID
    local unit = guid and UnitTokenFromGUIDSafe(guid)
    local isTarget = (guid ~= nil and guid == UnitGUID("target"))

    local base = frame._baseLabel or frame.displayName or frame.name or ""
    if C.bwtimeline.icons_name_number and frame.number then
        base = base .. " " .. frame.number
    end

    local markerIdx = nil
    if unit and GetRaidTargetIndex then
        markerIdx = GetRaidTargetIndex(unit)
    end

    local needLabel = (frame._renderedLabel == nil) or (frame._lastTargeted ~= isTarget) or (frame._lastMarkerIndex ~= markerIdx)
    if needLabel then
        local marker = RaidMarkerTextureTag(unit)
        -- Color the spell name portion: gold if targeted, white otherwise
        local colored = (isTarget and (GOLD .. base .. RESET)) or (WHITE .. base .. RESET)
        local label = marker and (marker .. " " .. colored) or colored
        frame._renderedLabel = label
        if frame.nameText and frame.nameText:IsShown() then
            frame.nameText:SetText(label)
        end
        frame._lastMarkerIndex = markerIdx
    end
    -- Highlight the border for mobs that are currently targeted by the player
    if frame.border and frame.border.SetBackdropBorderColor then
        local r, g, b, a
        if isTarget then
            r, g, b, a = 1, 0.82, 0, 1
        else
            local borderColor
            if frame.name and PLAYER_NAME and frame.name:find(PLAYER_NAME) then
                borderColor = C.mrtreminder.barColor or { 0, 1, 0, 1 }
            else
                borderColor = C.media.borderColor
            end
            r, g, b, a = borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1
        end
        local lr, lg, lb, la = frame._lastBorderR, frame._lastBorderG, frame._lastBorderB, frame._lastBorderA
        if lr ~= r or lg ~= g or lb ~= b or la ~= a then
            frame.border:SetBackdropBorderColor(r, g, b, a)
            frame._lastBorderR, frame._lastBorderG, frame._lastBorderB, frame._lastBorderA = r, g, b, a
        end
        frame._lastTargeted = isTarget
    end
end

function BW:registerAllMessages()
    local loader = rawget(_G, 'BigWigsLoader')
    if not loader or not loader.RegisterMessage then return end

    -- Pass method names as strings so CallbackHandler injects 'self'
    loader.RegisterMessage(self, "BigWigs_StartBar", "startBar")
    loader.RegisterMessage(self, "BigWigs_StopBar", "stopBar")
    loader.RegisterMessage(self, "BigWigs_StopBars", "stopBars")
    loader.RegisterMessage(self, "BigWigs_OnBossDisable", "onBossDisable")
    loader.RegisterMessage(self, "BigWigs_SetStage", "stage")
    loader.RegisterMessage(self, "BigWigs_BarCreated", "barCreated")
    loader.RegisterMessage(self, "BigWigs_BarEmphasized", "barCreated")
    loader.RegisterMessage(self, "BigWigs_OnBossEngaged", "onEncounterStart")
end

-- BigWigs_StartBar(event, module, key, text, duration, icon)
function BW:startBar(_, module, key, text, duration, icon)
    NPDBG("StartBar", module and module.name, key, text, duration, icon)
    BWT:resetTimer(key, text, duration, icon)
end

-- Nameplate bridge handlers (mobs only)
function BW:startNameplate(_, module, guid, key, length, customIconOrText)
    if not C.bwtimeline.nameplates_to_timeline then return end
    -- Optional target-only check
    if C.bwtimeline.np_target_only and guid ~= UnitGUID("target") then return end
    if isBossGUID(guid) then return end

    local remaining = parseRemaining(length)
    if not remaining or remaining <= 0 then return end

    -- Resolve icon
    local icon
    if type(customIconOrText) == "number" then
        icon = customIconOrText
    elseif module and module.SpellTexture then
        icon = module:SpellTexture(key)
    end
    if not icon and type(key) == "number" and GetSpellTexture then
        icon = GetSpellTexture(key)
    end
    if not icon then return end

    -- Base ability label for decoration
    local baseLabel = AbilityLabel(module, key, customIconOrText)
    if C.bwtimeline.np_show_mob_name then
        local loader = rawget(_G, 'BigWigsLoader')
        if loader and loader.UnitTokenFromGUID then
            local u = loader.UnitTokenFromGUID(guid)
            local mob = u and UnitName(u)
            if mob then baseLabel = mob .. ": " .. baseLabel end
        end
    end

    -- Deduplicate bursts (refresh within window)
    local k = npKey(guid, key)
    local now = GetTime()
    local exp = now + remaining
    local prev = npIndex[k]
    if prev and (exp - prev) <= (C.bwtimeline.np_dedupe_window or 0.25) then
        npIndex[k] = exp
        BWT:removeIconByName(k, true)
    else
        npIndex[k] = exp
    end

    local frame = BWT:createTimelineIcon(0, k, remaining, icon, C.bwtimeline.icons)
    if frame then
        frame._isMob = true
        frame._mobGUID = guid
        frame._baseLabel = baseLabel
        BWT:_MobTrackAdd(frame)
        BWT:updateFrameParameters(frame)
        BWT:RefreshMobLabel(frame)
        if C.bwtimeline.mob_desaturate and frame.icon and frame.icon.SetDesaturated then frame.icon:SetDesaturated(true) end
        if C.bwtimeline.mob_alpha and frame.SetAlpha then frame:SetAlpha(C.bwtimeline.mob_alpha) end
    end
end

function BW:stopNameplate(_, module, guid, key)
    local k = npKey(guid, key)
    npIndex[k] = nil
    BWT:removeIconByName(k, true)
end

function BW:clearNameplate(_, _, guid)
    local prefix = "NP_" .. tostring(guid) .. "_"
    for k in pairs(npIndex) do
        if k:sub(1, #prefix) == prefix then
            npIndex[k] = nil
            BWT:removeIconByName(k, true)
        end
    end
end

-- BigWigs_StopBar(event, module, key, text)
function BW:stopBar(_, module, key, text)
    NPDBG("StopBar", module and module.name, key, text)
    BWT:removeIconByName(text, true)
end

function BW:stopBars()
    BWT:removeAllIcons()
end

function BWT:resetTimer(spellID, name, duration, icon)
    self:removeIconByName(name, true)
    self:createTimelineIcon(spellID, name, duration, icon)
end

function BW:onBossDisable()
    BWT.phase = 1
    BWT.phaseCount = 0
end

-- BigWigs_BarCreated / BigWigs_BarEmphasized: (event, plugin, bar [, emphasized])
function BW:barCreated(_, plugin, bar)
    if C.bwtimeline.show_bigwigs_bars then return end
    if not bar then return end

    if C.bwtimeline.bw_alerts then
        -- Keep logic running, hide visuals as safely as possible
        if bar.SetAlpha then bar:SetAlpha(0) end
        if bar.candyBarLabel and bar.candyBarLabel.Hide then bar.candyBarLabel:Hide() end
        if bar.candyBarDuration and bar.candyBarDuration.Hide then bar.candyBarDuration:Hide() end
        if bar.candyBarIconFrame and bar.candyBarIconFrame.Hide then bar.candyBarIconFrame:Hide() end
        if bar.Hide then bar:Hide() end
    else
        -- Fully hide the bar frame (do not stop the bar logic)
        if bar.Hide then bar:Hide() end
    end
end

-- Instance gate: register/unregister nameplate messages only inside instances
BW.npBridgeActive = false
function BW:EnableNPBridge()
    if self.npBridgeActive then return end
    local loader = rawget(_G, 'BigWigsLoader')
    if loader and loader.RegisterMessage and not self._npRegMsgs then
        loader.RegisterMessage(self, "BigWigs_StartNameplate", "startNameplate")
        loader.RegisterMessage(self, "BigWigs_StopNameplate", "stopNameplate")
        loader.RegisterMessage(self, "BigWigs_ClearNameplate", "clearNameplate")
        self._npRegMsgs = true
        NPDBG("NP bridge: listening to loader messages")
    end
    -- Register heavy events only when bridge is active
    if npCleaner and npCleaner.RegisterEvent then
        npCleaner:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        npCleaner:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        npCleaner:RegisterEvent("ENCOUNTER_END")
        npCleaner:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    self.npBridgeActive = not not self._npRegMsgs
end

function BW:DisableNPBridge()
    -- Keep hooks installed (cannot unhook hooksecurefunc), just mark inactive and cleanup.
    if not self.npBridgeActive then return end
    self.npBridgeActive = false

    -- Unregister loader messages if we registered them
    local loader = rawget(_G, 'BigWigsLoader')
    if self._npRegMsgs and loader and loader.UnregisterMessage then
        loader.UnregisterMessage(self, "BigWigs_StartNameplate")
        loader.UnregisterMessage(self, "BigWigs_StopNameplate")
        loader.UnregisterMessage(self, "BigWigs_ClearNameplate")
        self._npRegMsgs = nil
        NPDBG("DisableNPBridge: unregistered loader messages")
    end

    -- Unregister heavy events while inactive
    if npCleaner and npCleaner.UnregisterEvent then
        npCleaner:UnregisterEvent("NAME_PLATE_UNIT_REMOVED")
        npCleaner:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        npCleaner:UnregisterEvent("ENCOUNTER_END")
        npCleaner:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end

    -- Optional safety: remove any NP_ icons already on the bar
    if BWT and BWT.bar and BWT.bar.frames then
        for i = #BWT.bar.frames, 1, -1 do
            local f = BWT.bar.frames[i]
            if f and f.name and f.name:find("^NP_") then
                BWT:removeIconByName(f.name, true)
            end
        end
    end
end

function BW:stage(_, stage)
    if type(stage) == "string" then
        stage = tonumber(stage:match("%d+$"))
    end

    if type(stage) == "number" then
        BWT.phase = stage
        BWT.phaseCount = (BWT.phaseCount or 0) + 1 -- Use 0 as default if phaseCount is nil
    end
end

function BW:onEncounterStart(_, encounterID)
    BWT.encounterID = encounterID
    BWT.phase = 1
    BWT.phaseCount = 0 -- Ensure phaseCount is reset here
    BWT:initializeCustomTimers()
end

function BWT:InitializeBigWigs()
    self.bigWigs:registerAllMessages()
end

-- Instance gating for the nameplate bridge
function BWT:IsInInstancePartyOrRaid()
    local inInstance, instanceType = IsInInstance()
    return inInstance and (instanceType == "party" or instanceType == "raid")
end

function BWT:UpdateNPBridge()
    local inInstance, instanceType = IsInInstance()
    NPDBG("UpdateNPBridge inInstance=", tostring(inInstance), "type=", tostring(instanceType))
    if inInstance and (instanceType == "party" or instanceType == "raid") and C.bwtimeline.nameplates_to_timeline then
        self.bigWigs:EnableNPBridge()
    else
        self.bigWigs:DisableNPBridge()
    end
end

-- =========================
-- FINAL: Hard-kill BW Nameplates
-- =========================


-- Hard kill-switch for BigWigs nameplate icons (works even if Plater/others listen).
-- Keeps your timeline bridge working by forwarding to it only.

-- Minimal overhead gate frame (no AceEvent dependency on BWT)
local npGate = CreateFrame("Frame")
npGate:RegisterEvent("PLAYER_ENTERING_WORLD")
npGate:RegisterEvent("ZONE_CHANGED_NEW_AREA")
npGate:RegisterEvent("ADDON_LOADED")
npGate:SetScript("OnEvent", function(_, event, addonName)
    NPDBG("npGate event", event, addonName)
    if event == "ADDON_LOADED" and (addonName == "BigWigs" or addonName == "BigWigs_Plugins") then
        BWCore = rawget(_G, 'BigWigs')
        BWLoader = rawget(_G, 'BigWigsLoader')
        NPDBG("ADDON_LOADED BigWigs detected; refreshed BigWigs globals")
    end
    if BWT and BWT.UpdateNPBridge then
        BWT:UpdateNPBridge()
    end
end)

-- Eager cleanup of NP icons on plate removal or unit death
npCleaner = CreateFrame("Frame")
-- Heavy event registration is managed by NP bridge enable/disable lifecycle
npCleaner:SetScript("OnEvent", function(_, event, ...)
    if not (BW and BW.npBridgeActive) then return end
    if event == "NAME_PLATE_UNIT_REMOVED" then
        local unit = ...
        local guid = unit and UnitGUID(unit)
        if guid then BW:clearNameplate(nil, nil, guid) end

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, subevent, _, _, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
        if (subevent == "UNIT_DIED" or subevent == "UNIT_DESTROYED" or subevent == "UNIT_DISSIPATES")
           and destGUID then
            BW:clearNameplate(nil, nil, destGUID)
        end

    elseif event == "ENCOUNTER_END" or event == "PLAYER_REGEN_ENABLED" then
        -- optional: clean up any dangling NP_ icons
        if BWT and BWT.removeByPrefix then BWT:removeByPrefix("NP_") end
    end
end)

-- Label refresh dispatcher (no polling)
local labelEvt = CreateFrame("Frame")
labelEvt:RegisterEvent("PLAYER_TARGET_CHANGED")
labelEvt:RegisterEvent("RAID_TARGET_UPDATE")
labelEvt:RegisterEvent("NAME_PLATE_UNIT_ADDED")
labelEvt:SetScript("OnEvent", function(_, event, unit)
    if not BWT then return end
    if event == "PLAYER_TARGET_CHANGED" or event == "RAID_TARGET_UPDATE" then
        for i = 1, #mobFrames do
            local f = mobFrames[i]
            if f then BWT:RefreshMobLabel(f) end
        end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        local guid = unit and UnitGUID(unit)
        if guid then
            local arr = mobByGUID[guid]
            if arr then
                for i = 1, #arr do
                    local f = arr[i]
                    if f then BWT:RefreshMobLabel(f) end
                end
            end
        end
    end
end)


-- Install shim when BigWigs plugins load if setting enabled

-- Keep disabled across BigWigs profile swaps if requested
