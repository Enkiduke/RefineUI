local R, C, L = unpack(RefineUI)

----------------------------------------------------------------------------------------
--	RefineUI BuffWatch - Unified buff tracking for party and raid frames
--	
--	This module provides two distinct BuffWatch elements:
--	• PlayerBuffWatch: Shows buffs cast BY the player (with stack counts)
--	• PartyBuffWatch: Shows buffs cast BY party members (with timers)
--	
--	Performance-optimized oUF element that maintains exact functionality
--	and appearance of the original custom AuraWatch implementation.
----------------------------------------------------------------------------------------

local _, ns = ...
local oUF = ns.oUF

----------------------------------------------------------------------------------------
-- Upvalues and Constants
----------------------------------------------------------------------------------------

-- Performance upvalues
local CreateFrame, UnitGUID, GetTime, UnitIsUnit = CreateFrame, UnitGUID, GetTime, UnitIsUnit
local UnitAura = UnitAura
local pairs, ipairs, tinsert, wipe, unpack, math_floor = pairs, ipairs, tinsert, wipe, unpack, math.floor
local string_format = string.format
local C_Spell = C_Spell
local C_UnitAuras = C_UnitAuras
local AuraUtil = AuraUtil

-- Unit constants (must be defined before any function uses them)
local PLAYER = "player"
local VEHICLE = "vehicle"

----------------------------------------------------------------------------------------
-- Aura Retrieval (Modern API with safe fallback)
----------------------------------------------------------------------------------------

local function GetAuraByIndex(unit, index, auraType)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        return C_UnitAuras.GetAuraDataByIndex(unit, index, auraType)
    end
    if UnitAura then
        local name, icon, count, _, duration, expirationTime, sourceUnit, _, _, spellId = UnitAura(unit, index, auraType)
        if not name then return nil end
        return {
            name = name,
            icon = icon,
            applications = count,
            duration = duration,
            expirationTime = expirationTime,
            sourceUnit = sourceUnit,
            spellId = spellId,
        }
    end
    return nil
end

-- Prefer AuraUtil.ForEachAura with packed data; fallback to index walk
local function ForEachAuraPacked(unit, auraType, callback)
    if AuraUtil and AuraUtil.ForEachAura then
        AuraUtil.ForEachAura(unit, auraType, nil, function(data)
            if not data or not data.name then return false end
            callback(data)
            return false -- continue
        end, true)
        return
    end
    for i = 1, 40 do
        local data = GetAuraByIndex(unit, i, auraType)
        if not data or not data.name then break end
        callback(data)
    end
end

-- Fetch a single aura by instance ID (modern API), with safe fallback
local function GetAuraByInstanceID(unit, instanceID)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
        return C_UnitAuras.GetAuraDataByAuraInstanceID(unit, instanceID)
    end
    -- No reliable fallback without scanning; return nil to trigger removal path
    return nil
end

-- Forward declarations for cross-referenced locals
-- These are assigned below to ensure earlier functions capture locals, not globals.
local ShouldTrackAura
local ProcessAuraForElement

-- Build visible icons using cached HELPFUL aura instances, avoiding API scans
local function BuildVisibleIconsFromCache(self, element, visibleIcons)
    local auraByInstance = self._bwAuraByInstance
    if not auraByInstance then return end

    local isPlayerBuffWatch = (element.filter == "HELPFUL|PLAYER")
    local best = element._cacheBest or {}
    wipe(best)

    for _, data in pairs(auraByInstance) do
        local spellID = data.spellId
        local watchIcon = element.icons and element.icons[spellID]
        if watchIcon then
            local isPlayerCaster = data.sourceUnit and (UnitIsUnit(data.sourceUnit, PLAYER) or UnitIsUnit(data.sourceUnit, VEHICLE)) or false
            if ShouldTrackAura(isPlayerBuffWatch, isPlayerCaster, watchIcon) then
                local cur = best[spellID]
                local exp = data.expirationTime or 0
                if not cur or (cur.expirationTime or 0) > exp then
                    best[spellID] = data
                end
            end
        end
    end

    for spellID, data in pairs(best) do
        ProcessAuraForElement(element, visibleIcons, spellID, data.name, data.applications or 0, data.duration or 0, data.expirationTime or 0, data.sourceUnit)
    end
end

-- Timer formatting constants
local TIME_UNITS = {
    {86400, "%dd"},
    {3600, "%dh"},
    {60, "%dm"},
    {1, "%d"},
}

-- Icon positioning offsets
local ICON_OFFSETS = {
    Normal = {
        {"TOPRIGHT",    0, 0},
        {"BOTTOMRIGHT", 0, -2},
        {"BOTTOMLEFT",  -2, -2},
        {"TOPLEFT",     -2, 0},
    },
    Reversed = {
        {"TOPLEFT",     0, 0},
        {"BOTTOMLEFT",  0, -2},
        {"BOTTOMRIGHT", 2, -2},
        {"TOPRIGHT",    2, 0},
    }
}

----------------------------------------------------------------------------------------
-- Utility Functions
----------------------------------------------------------------------------------------

local function FormatTime(seconds)
    for i = 1, #TIME_UNITS do
        local unit = TIME_UNITS[i]
        if seconds >= unit[1] then
            return string_format(unit[2], math_floor(seconds / unit[1] + 0.5))
        end
    end
    return string_format("%.1f", seconds)
end

local function GetElementsList(self)
    -- Reuse a per-frame table to avoid allocations each update
    local elements = self._buffWatchElements or {}
    wipe(elements)
    if self.PlayerBuffWatch then elements[#elements + 1] = self.PlayerBuffWatch end
    if self.PartyBuffWatch then elements[#elements + 1] = self.PartyBuffWatch end
    if self.BuffWatch then elements[#elements + 1] = self.BuffWatch end -- Legacy support
    self._buffWatchElements = elements
    return elements
end

ShouldTrackAura = function(isPlayerBuffWatch, isPlayerCaster, watchIcon)
    if isPlayerBuffWatch then
        -- PlayerBuffWatch: Only show buffs cast BY the player
        return isPlayerCaster
    else
        -- PartyBuffWatch: Never show buffs cast by the player
        -- (regardless of any per-spell flag)
        return not isPlayerCaster
    end
end

local function CleanupIcon(icon)
    if icon.timerText then icon.timerText:Hide() end
    if icon.count then 
        -- Keep count visible if it has text, hide if empty
        local countText = icon.count:GetText()
        if not countText or countText == "" then
            icon.count:Hide()
        end
    end
    icon:SetScript("OnUpdate", nil)
    icon._acc = nil
end

----------------------------------------------------------------------------------------
-- Timer Management
----------------------------------------------------------------------------------------

local function UpdateTimerText(icon, elapsed)
    if not icon.timerText or not icon:IsShown() then
        CleanupIcon(icon)
        return
    end

    local acc = (icon._acc or 0) + elapsed
    local interval = icon._interval or 0.3
    if acc < interval then
        icon._acc = acc
        return
    end
    icon._acc = 0

    if not icon.expirationTime then
        CleanupIcon(icon)
        return
    end

    local remaining = icon.expirationTime - GetTime()
    if remaining > 0 then
        icon.timerText:SetText(FormatTime(remaining))
        -- Color urgency: red for <= 5 seconds, white otherwise
        if remaining <= 5 then
            icon.timerText:SetTextColor(1, 0.3, 0.3)
        else
            icon.timerText:SetTextColor(1, 1, 1)
        end
        if not icon.timerText:IsShown() then 
            icon.timerText:Show() 
        end
    else
        CleanupIcon(icon)
    end
end

----------------------------------------------------------------------------------------
-- Icon Creation and Styling
----------------------------------------------------------------------------------------

local function CreateBuffIcon(parent, spell, iconSize)
    local icon = CreateFrame("Frame", nil, parent)
    icon:SetSize(iconSize, iconSize)
    
    -- Apply RefineUI template and styling
    R.UF.ApplyFrameTemplate(icon, "Icon", {borderStrata = "LOW"})
    icon.border:SetBackdropBorderColor(unpack(spell[2] or C.media.borderColor))

    -- Store spell configuration
    icon.spellID = spell[1]
    icon.anyUnit = spell[4]
    icon.strictMatching = spell[5]

    -- Create icon texture
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints(icon)
    icon.texture:SetTexCoord(0.1, 0.9, 0.1, 0.9)

    -- Set spell texture
    local spellTexture = C_Spell.GetSpellTexture(icon.spellID)
    if spellTexture then
        icon.texture:SetTexture(spellTexture)
    end

    -- Create cooldown overlay
    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cooldown:SetParent(icon)
    icon.cooldown:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
    icon.cooldown:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
    icon.cooldown:SetReverse(true)
    icon.cooldown:SetDrawEdge(false)
    icon.cooldown:SetSwipeColor(0, 0, 0, 0.8)
    icon.cooldown:SetSwipeTexture(C.media.auraCooldown)

    -- Disable cooldown countdown text
    if icon.cooldown.SetHideCountdownNumbers then
        icon.cooldown:SetHideCountdownNumbers(true)
    end
    icon.cooldown.noCooldownCount = true
    icon.cooldown.noOCC = true

    -- Create timer text (center) - but we'll keep it hidden
    icon.timerText = R.SetFontString(icon, unpack(C.font.auras.smallCount))
    icon.timerText:SetPoint("CENTER", icon, "CENTER", 0, 0)
    icon.timerText:SetJustifyH("CENTER")
    icon.timerText:Hide()

    -- Create count text (bottom-right)
    icon.count = R.SetFontString(icon, unpack(C.font.auras.smallCount))
    icon.count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, 1)
    icon.count:SetJustifyH("RIGHT")
    icon.count:Hide()

    icon:Hide()
    return icon
end

----------------------------------------------------------------------------------------
-- Aura Processing and Icon Management
----------------------------------------------------------------------------------------

ProcessAuraForElement = function(element, visibleIcons, spellID, name, count, duration, expirationTime, unitCaster)
    local watchIcon = element.icons[spellID]
    if not watchIcon then return end
    
    local isPlayerBuffWatch = (element.filter == "HELPFUL|PLAYER")
    local isPlayerCaster = unitCaster and (UnitIsUnit(unitCaster, PLAYER) or UnitIsUnit(unitCaster, VEHICLE)) or false
    
    -- Check if this aura should be tracked using strict separation logic
    if not ShouldTrackAura(isPlayerBuffWatch, isPlayerCaster, watchIcon) then
        return
    end
    
    -- Skip ignored spells
    if R.RaidBuffsIgnore and R.RaidBuffsIgnore[spellID] then
        return
    end
    
    -- Store timing information
    watchIcon.expirationTime = expirationTime
    watchIcon.duration = duration

    -- Update cooldown visual
    if duration and duration > 0 and expirationTime and expirationTime > 0 then
        watchIcon.cooldown:SetCooldown(expirationTime - duration, duration)
    else
        watchIcon.cooldown:SetCooldown(0, 0)
    end

    -- Configure display based on element type
    if isPlayerBuffWatch then
        -- PlayerBuffWatch: Show stacks, hide timer
        watchIcon.count:SetText(count > 1 and count or "")
        watchIcon.count:Show()
        watchIcon.timerText:Hide()
        CleanupIcon(watchIcon)
    else
        -- PartyBuffWatch: Show stacks instead of timer (modified behavior)
        watchIcon.count:SetText(count > 1 and count or "")
        watchIcon.count:Show()
        watchIcon.timerText:Hide()
        CleanupIcon(watchIcon)
    end

    tinsert(visibleIcons, watchIcon)
end

local function SelectTopIcons(visibleIcons, maxIcons, out)
    maxIcons = maxIcons or 4
    out = out or {}
    wipe(out)

    for i = 1, #visibleIcons do
        local icon = visibleIcons[i]
        local expirationTime = icon.expirationTime or 0
        local numTop = #out

        if numTop < maxIcons then
            -- Add to list and sort by earliest expiration
            out[numTop + 1] = icon
            local pos = numTop + 1
            while pos > 1 and (out[pos - 1].expirationTime or 0) > expirationTime do
                out[pos], out[pos - 1] = out[pos - 1], out[pos]
                pos = pos - 1
            end
        elseif expirationTime < (out[maxIcons].expirationTime or 0) then
            -- Replace last item and re-sort
            out[maxIcons] = icon
            local pos = maxIcons
            while pos > 1 and (out[pos - 1].expirationTime or 0) > expirationTime do
                out[pos], out[pos - 1] = out[pos - 1], out[pos]
                pos = pos - 1
            end
        end
    end

    return out
end

local function PositionAndShowIcons(element, topIcons)
    local offsetSet = element.reverseGrowth and ICON_OFFSETS.Reversed or ICON_OFFSETS.Normal
    -- Reuse a per-element set for selected icons
    local selectedSet = element._selectedSet or {}
    wipe(selectedSet)
    
    -- Position and show selected icons
    for i = 1, #topIcons do
        local icon = topIcons[i]
        local offset = offsetSet[i]
        
        icon:ClearAllPoints()
        icon:SetPoint(offset[1], element, offset[1], offset[2], offset[3])
        icon:SetAlpha(1)
        icon:Show()
        
        selectedSet[icon] = true
    end
    
    -- Hide non-selected icons
    for _, icon in pairs(element.icons) do
        if not selectedSet[icon] then
            if icon:IsShown() then
                icon:Hide()
                icon:ClearAllPoints()
            end
            CleanupIcon(icon)
        end
    end
    element._selectedSet = selectedSet
end

----------------------------------------------------------------------------------------
-- Main Update Function
----------------------------------------------------------------------------------------

local function Update(self, event, unit, updateInfo)
    if self.unit ~= unit then return end
    
    -- If we received granular UNIT_AURA updates and nothing relevant changed, skip work.
    -- Maintain a per-frame map from auraInstanceID -> spellID and a cache of HELPFUL aura instances.
    if updateInfo and not updateInfo.isFullUpdate then
        local watched = self._bwWatchedSpellIDs
        local map = self._bwAuraMap or {}
        local byInstance = self._bwAuraByInstance or {}
        self._bwAuraMap = map
        self._bwAuraByInstance = byInstance

        local hasRelevant = false

        -- Handle added auras: insert into map and test relevance
        local added = updateInfo.addedAuras
        if added and watched then
            for i = 1, #added do
                local a = added[i]
                -- Only track helpful auras for BuffWatch
                if a and (a.isHelpful == nil or a.isHelpful) then
                    local sid = a.spellId
                    local inst = a.auraInstanceID
                    if inst and sid then
                        map[inst] = sid
                        byInstance[inst] = a
                        if watched[sid] then
                            hasRelevant = true
                            -- do not break; still want to process all to keep map in sync
                        end
                    end
                end
            end
        end

        -- Handle updated auras: check if any updated instance maps to a watched spell
        local updatedIDs = updateInfo.updatedAuraInstanceIDs
        if not hasRelevant and updatedIDs and watched and map then
            for i = 1, #updatedIDs do
                local inst = updatedIDs[i]
                local sid = inst and map[inst]
                -- Refresh cache for this instance if possible
                if inst then
                    local data = GetAuraByInstanceID(unit, inst)
                    if data and (data.isHelpful == nil or data.isHelpful) then
                        byInstance[inst] = data
                        map[inst] = data.spellId
                    else
                        -- Treat as removed if no data or no longer helpful
                        byInstance[inst] = nil
                        map[inst] = nil
                    end
                end
                if sid and watched[sid] then
                    hasRelevant = true
                    break
                end
            end
        end

        -- Handle removed auras: check if any removed instance maps to a watched spell, then remove from map
        local removedIDs = updateInfo.removedAuraInstanceIDs
        if removedIDs and map then
            for i = 1, #removedIDs do
                local inst = removedIDs[i]
                local sid = inst and map[inst]
                if sid and watched and watched[sid] then
                    hasRelevant = true
                end
                if inst then
                    map[inst] = nil
                    byInstance[inst] = nil
                end
            end
        end

        if not hasRelevant then
            return
        end
    end

    local elements = GetElementsList(self)
    if #elements == 0 then return end
    
    -- If all elements are watching helpful auras, scan once and reuse
    local canShareScan = true
    for i = 1, #elements do
        local f = elements[i].filter
        -- Default is HELPFUL; only share when not asking for any harmful auras
        if f and (not string.find(f, "HELPFUL", 1, true) or string.find(f, "HARMFUL", 1, true)) then
            canShareScan = false
            break
        end
    end

    local sharedScan
    if canShareScan then
        local isPartial = (updateInfo and not updateInfo.isFullUpdate) and true or false
        if not isPartial then
        -- Reuse a per-frame aura cache between elements
        sharedScan = self._bwAuraScan or {}
        local count = 0
        -- Rebuild the helpful aura instance map alongside the scan
        local map = self._bwAuraMap or {}
        local byInstance = self._bwAuraByInstance or {}
        wipe(map)
        wipe(byInstance)
        -- Preserve and reuse per-index info tables to avoid churn
        ForEachAuraPacked(unit, "HELPFUL", function(aura)
            count = count + 1
            local info = sharedScan[count]
            if not info then
                info = {}
                sharedScan[count] = info
            end
            info.spellID = aura.spellId
            info.name = aura.name
            info.count = aura.applications or 0
            info.duration = aura.duration or 0
            info.expirationTime = aura.expirationTime or 0
            info.unitCaster = aura.sourceUnit
            if aura.auraInstanceID then
                map[aura.auraInstanceID] = aura.spellId
                byInstance[aura.auraInstanceID] = aura
            end
        end)
        -- Trim any leftover entries from previous scans
        for i = count + 1, #sharedScan do
            sharedScan[i] = nil
        end
        self._bwAuraScan = sharedScan
        self._bwAuraMap = map
        self._bwAuraByInstance = byInstance
        end
    end

    -- Process each BuffWatch element
    for _, element in ipairs(elements) do
        local visibleIcons = element.visibleIcons or {}
        wipe(visibleIcons)
        
        local filter = element.filter or "HELPFUL"

        if sharedScan and canShareScan then
            -- Shared HELPFUL scan; filter per element rules
            for i = 1, #sharedScan do
                local info = sharedScan[i]
                ProcessAuraForElement(element, visibleIcons, info.spellID, info.name, info.count, info.duration, info.expirationTime, info.unitCaster)
            end
        else
            -- Scan unit auras per element
            local auraType = (filter and string.find(filter, "HARMFUL", 1, true)) and "HARMFUL" or "HELPFUL"
            if updateInfo and not updateInfo.isFullUpdate and auraType == "HELPFUL" then
                -- Partial update: rebuild from cache without scanning API
                BuildVisibleIconsFromCache(self, element, visibleIcons)
            else
                -- Full update path or harmful scan: iterate API
                -- If scanning HELPFUL per-element, rebuild the HELPFUL map once
                if auraType == "HELPFUL" and not sharedScan then
                    local map = self._bwAuraMap or {}
                    local byInstance = self._bwAuraByInstance or {}
                    wipe(map)
                    wipe(byInstance)
                    ForEachAuraPacked(unit, "HELPFUL", function(aura)
                        if aura.auraInstanceID then
                            map[aura.auraInstanceID] = aura.spellId
                            byInstance[aura.auraInstanceID] = aura
                        end
                    end)
                    self._bwAuraMap = map
                    self._bwAuraByInstance = byInstance
                end
                ForEachAuraPacked(unit, auraType, function(aura)
                    local name = aura.name
                    local count = aura.applications or 0
                    local duration = aura.duration or 0
                    local expirationTime = aura.expirationTime or 0
                    local unitCaster = aura.sourceUnit
                    local spellID = aura.spellId
                    ProcessAuraForElement(element, visibleIcons, spellID, name, count, duration, expirationTime, unitCaster)
                end)
            end
        end

        -- Select and position top icons; avoid re-layout when membership/order unchanged
        local topIcons = SelectTopIcons(visibleIcons, 4, element._topIcons)
        local sig
        do
            local parts = element._sigParts or {}
            wipe(parts)
            for i = 1, #topIcons do
                local ic = topIcons[i]
                parts[#parts + 1] = tostring(ic.spellID or 0)
                parts[#parts + 1] = ":"
                parts[#parts + 1] = tostring(ic.expirationTime or 0)
                parts[#parts + 1] = ";"
            end
            sig = table.concat(parts)
            element._sigParts = parts
        end
        if element._lastSig ~= sig then
            PositionAndShowIcons(element, topIcons)
            element._lastSig = sig
        end
        
        element.visibleIcons = visibleIcons
        element._topIcons = topIcons
    end
end

----------------------------------------------------------------------------------------
-- Element Lifecycle Management
----------------------------------------------------------------------------------------

local function Enable(self)
    local elements = GetElementsList(self)
    if #elements == 0 then return end

    -- Initialize icons for each element
    for _, element in ipairs(elements) do
        if not element.icons then
            element.icons = {}
            element.visibleIcons = {}
            
            local buffs = element.buffs or {}
            local iconSize = (element.size or 40) / 2 - 1
            
            for i = 1, #buffs do
                local spell = buffs[i]
                if spell[1] then -- Validate spell ID exists
                    local icon = CreateBuffIcon(element, spell, iconSize)
                    element.icons[spell[1]] = icon
                end
            end
        end
    end

    -- Build a per-frame set of watched spellIDs for quick relevance checks on UNIT_AURA updates
    local watched = self._bwWatchedSpellIDs or {}
    wipe(watched)
    for _, element in ipairs(elements) do
        if element.icons then
            for spellID in pairs(element.icons) do
                watched[spellID] = true
            end
        end
    end
    self._bwWatchedSpellIDs = watched
    -- Initialize auraInstanceID -> spellID map for HELPFUL auras
    self._bwAuraMap = self._bwAuraMap or {}

    self:RegisterEvent("UNIT_AURA", Update, true)
    return true
end

local function Disable(self)
    local elements = GetElementsList(self)
    if #elements == 0 then return end
    
    self:UnregisterEvent("UNIT_AURA", Update)
    
    -- Clean up all icons across all elements
    for _, element in ipairs(elements) do
        if element.icons then
            for _, icon in pairs(element.icons) do
                icon:Hide()
                CleanupIcon(icon)
            end
        end
    end
end

----------------------------------------------------------------------------------------
-- oUF Element Registration
----------------------------------------------------------------------------------------

oUF:AddElement("BuffWatch", Update, Enable, Disable)
