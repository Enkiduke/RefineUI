-- LibEasing no longer used
--	Features include customizable text size, colors, animations, and filtering options.
----------------------------------------------------------------------------------------

local R, C, L = unpack(RefineUI)

----------------------------------------------------------------------------------------
--	Libraries
----------------------------------------------------------------------------------------
-- LibEasing removed; no libraries required here

----------------------------------------------------------------------------------------
--	Addon Initialization
----------------------------------------------------------------------------------------
local RefineUI_SCT = {}
RefineUI_SCT.frame = CreateFrame("Frame", nil, UIParent)

-- Disable default floating combat text
SetCVar("floatingCombatTextCombatDamage", 0)
SetCVar("floatingCombatTextCombatHealing", 0)

----------------------------------------------------------------------------------------
--	Local Variables and Constants
----------------------------------------------------------------------------------------
local playerGUID
local unitToGuid = {}
local guidToUnit = {}
-- Active animations tracked in an indexed array for cache-friendly iteration
local animList = {}
local animIndex = {}

-- Forward declaration for local function defined later
local recycleFontString

local function addAnimating(fs)
    if not animIndex[fs] then
        tinsert(animList, fs)
        animIndex[fs] = #animList
    end
end

local function removeAnimating(fs, doRecycle)
    local idx = animIndex[fs]
    if not idx then
        if doRecycle then recycleFontString(fs) end
        return
    end
    local lastIndex = #animList
    local last = animList[lastIndex]
    animList[idx] = last
    animIndex[last] = idx
    animList[lastIndex] = nil
    animIndex[fs] = nil
    if doRecycle then recycleFontString(fs) end
end

-- Constants
local MINIMUM_TEXT_SIZE = 5
local SHADOW_OFFSET_X = 1
local SHADOW_OFFSET_Y = -1

-- Cache frequently used functions
local GetTime = GetTime
local math_random = math.random
local math_max = math.max
local math_min = math.min
local math_abs = math.abs
local string_format = string.format
local string_match = string.match
local bit_band = bit.band
local UnitExists = UnitExists
local UnitIsUnit = UnitIsUnit
local GetNamePlateForUnit = C_NamePlate.GetNamePlateForUnit
local GetSpellTexture = C_Spell.GetSpellTexture
local GetSpellInfo = C_Spell.GetSpellInfo
local tinsert, tremove = table.insert, table.remove

-- Lookup table for power of 10 calculations
local POW10 = setmetatable({ [0] = 1 }, {
    __index = function(t, k)
        if k > 0 then
            local v = t[k - 1] * 10
            t[k] = v
            return v
        end
        return 1 / t[-k]
    end
})

-- Lookup tables for various settings
local SIZE_MULTIPLIERS = {
    small_hits = C.sct.size_small_hits_scale or 0.75,
    crits = C.sct.size_crit_scale or 1.5,
    miss = C.sct.size_miss_scale or 1.25
}

local ANIMATION_TYPES = {
    autoattack = {
        normal = C.sct.animations_autoattack,
        crit = C.sct.animations_autoattackcrit
    },
    ability = {
        normal = C.sct.animations_ability,
        crit = C.sct.animations_crit
    },
    miss = C.sct.animations_miss,
    personal = {
        normal = C.sct.personalanimations_normal,
        crit = C.sct.personalanimations_crit,
        miss = C.sct.personalanimations_miss
    }
}

-- Table recycling system
local tablePools = {}

local function getRecycledTable(poolName)
    local pool = tablePools[poolName]
    if not pool then
        pool = {}
        tablePools[poolName] = pool
    end
    return tremove(pool) or {}
end

local function recycleTable(t, poolName)
    if type(t) ~= "table" then return end
    for k in pairs(t) do t[k] = nil end
    local pool = tablePools[poolName]
    if not pool then
        pool = {}
        tablePools[poolName] = pool
    end
    tinsert(pool, t)
end

-- Animation constants
local ANIMATION = {
    VERTICAL_DISTANCE = 75,
    ARC_X_MIN = 50,
    ARC_X_MAX = 150,
    ARC_Y_TOP_MIN = 10,
    ARC_Y_TOP_MAX = 50,
    ARC_Y_BOTTOM_MIN = 10,
    ARC_Y_BOTTOM_MAX = 50,
    RAINFALL_X_MAX = 75,
    RAINFALL_Y_MIN = 50,
    RAINFALL_Y_MAX = 100,
    RAINFALL_Y_START_MIN = 5,
    RAINFALL_Y_START_MAX = 15
}

-- Small hit constants
local SMALL_HIT = {
    EXPIRY_WINDOW = 30,
    MULTIPLIER = 0.5
}

-- Frame strata levels
local STRATAS = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "TOOLTIP" }

-- Inverse positions for icon placement
local INVERSE_POSITIONS = {
    ["BOTTOM"] = "TOP",
    ["LEFT"] = "RIGHT",
    ["TOP"] = "BOTTOM",
    ["RIGHT"] = "LEFT",
    ["TOPLEFT"] = "BOTTOMRIGHT",
    ["TOPRIGHT"] = "BOTTOMLEFT",
    ["BOTTOMLEFT"] = "TOPRIGHT",
    ["BOTTOMRIGHT"] = "TOPLEFT",
    ["CENTER"] = "CENTER"
}

-- Cache for spell icon textures
local SPELL_ICON_CACHE = {}
local SPELL_ICON_CACHE_ORDER = {}
local ICON_CACHE_MAX = 512

local function cacheSpellIcon(key, texture)
    if not key or not texture then return end
    if SPELL_ICON_CACHE[key] == nil then
        tinsert(SPELL_ICON_CACHE_ORDER, key)
        SPELL_ICON_CACHE[key] = texture
        if #SPELL_ICON_CACHE_ORDER > ICON_CACHE_MAX then
            local old = tremove(SPELL_ICON_CACHE_ORDER, 1)
            SPELL_ICON_CACHE[old] = nil
        end
    else
        SPELL_ICON_CACHE[key] = texture
    end
end

-- Damage school masks (for 9.1 PTR Support)
if not SCHOOL_MASK_PHYSICAL then
    SCHOOL_MASK_PHYSICAL = Enum.Damageclass.MaskPhysical
    SCHOOL_MASK_HOLY = Enum.Damageclass.MaskHoly
    SCHOOL_MASK_FIRE = Enum.Damageclass.MaskFire
    SCHOOL_MASK_NATURE = Enum.Damageclass.MaskNature
    SCHOOL_MASK_FROST = Enum.Damageclass.MaskFrost
    SCHOOL_MASK_SHADOW = Enum.Damageclass.MaskShadow
    SCHOOL_MASK_ARCANE = Enum.Damageclass.MaskArcane
end

-- Damage type colors
local DAMAGE_TYPE_COLORS = {
    [SCHOOL_MASK_PHYSICAL] = "FFFF00",
    [SCHOOL_MASK_HOLY] = "FFE680",
    [SCHOOL_MASK_FIRE] = "FF8000",
    [SCHOOL_MASK_NATURE] = "4DFF4D",
    [SCHOOL_MASK_FROST] = "80FFFF",
    [SCHOOL_MASK_SHADOW] = "8080FF",
    [SCHOOL_MASK_ARCANE] = "FF80FF",
    -- ... (other color combinations)
    ["melee"] = "FFFFFF",
    ["pet"] = "CC8400"
}

-- Miss event strings
local MISS_EVENT_STRINGS = {
    ["ABSORB"] = "Absorbed",
    ["BLOCK"] = "Blocked",
    ["DEFLECT"] = "Deflected",
    ["DODGE"] = "Dodged",
    ["EVADE"] = "Evaded",
    ["IMMUNE"] = "Immune",
    ["MISS"] = "Missed",
    ["PARRY"] = "Parried",
    ["REFLECT"] = "Reflected",
    ["RESIST"] = "Resisted"
}

----------------------------------------------------------------------------------------
--	Utility Functions
----------------------------------------------------------------------------------------
local function commaSeparate(number)
    local left, num, right = string.match(tostring(number), '^([^%d]*%d)(%d*)(.-)$')
    return left .. (num:reverse():gsub('(%d%d%d)', '%1,'):reverse()) .. right
end

local function adjustStrata()
    if C.sct.strata_enable then return end

    if C.sct.strata_target == "BACKGROUND" then
        C.sct.strata_offtarget = "BACKGROUND"
    else
        for k, v in ipairs(STRATAS) do
            if v == C.sct.strata_target then
                C.sct.strata_offtarget = STRATAS[k - 1]
                break
            end
        end
    end
end

----------------------------------------------------------------------------------------
--	FontString Management
----------------------------------------------------------------------------------------
---@class SCTFontString: FontString
---@field distance number
---@field arcTop number
---@field arcBottom number
---@field arcXDist number
---@field deflection number
---@field numShakes number
---@field animation string
---@field animatingDuration number
---@field animatingStartTime number
---@field anchorFrame Frame
---@field unit string
---@field guid string
---@field pow boolean
---@field startHeight number
---@field startAlpha number
---@field icon Texture
---@field rainfallX number
---@field rainfallStartY number
---@field scttext string
---@field baseX number
---@field baseY number
---@field invDuration number
---@field _lastAlpha number
local fontStringCache = {}
local frameCounter = 0

---@return SCTFontString
local function getFontString()
    local fontString = tremove(fontStringCache)
    if not fontString then
        frameCounter = frameCounter + 1
        local fontStringFrame = CreateFrame("Frame", nil, UIParent)
        fontStringFrame:SetFrameStrata(C.sct.strata_target)
        fontStringFrame:SetFrameLevel(frameCounter)
        fontString = fontStringFrame:CreateFontString()
        fontString:SetParent(fontStringFrame)
    end

    ---@cast fontString SCTFontString
    --- Keep base styling here; avoid resetting on every display
    fontString:SetFont(unpack(C.font.sct))
    fontString:SetShadowOffset(SHADOW_OFFSET_X, SHADOW_OFFSET_Y)
    fontString:SetAlpha(1)
    fontString:SetDrawLayer("BACKGROUND")
    fontString:SetText("")
    fontString:Show()

    if C.sct.icon_enable then
        if not fontString.icon then
            fontString.icon = fontString:GetParent():CreateTexture(nil, "BACKGROUND")
        end
        fontString.icon:SetAlpha(1)
        fontString.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        fontString.icon:Hide()
    end

    return fontString
end

---@param fontString SCTFontString
function recycleFontString(fontString)
    fontString:SetAlpha(0)
    fontString:Hide()


    -- Reset properties
    fontString.distance = nil
    fontString.arcTop = nil
    fontString.arcBottom = nil
    fontString.arcXDist = nil
    fontString.deflection = nil
    fontString.numShakes = nil
    fontString.animation = nil
    fontString.animatingDuration = nil
    fontString.animatingStartTime = nil
    fontString.anchorFrame = nil
    fontString.unit = nil
    fontString.guid = nil
    fontString.pow = nil
    fontString.startHeight = nil
    fontString.invDuration = nil
    fontString._lastAlpha = nil

    if fontString.icon then
        fontString.icon:ClearAllPoints()
        fontString.icon:SetAlpha(0)
        fontString.icon:Hide()
    end

    -- Do not reset font and shadow here to avoid redundant work
    fontString:ClearAllPoints()

    tinsert(fontStringCache, fontString)
end

----------------------------------------------------------------------------------------
--	Animation Functions
----------------------------------------------------------------------------------------
local function verticalPath(elapsed, duration, distance)
    -- Inline InQuad easing: y = distance * (elapsed / duration)^2
    local p = elapsed / duration
    return 0, distance * p * p
end

local function arcPath(elapsed, duration, xDist, yStart, yTop, yBottom)
    local progress = elapsed / duration
    local x = progress * xDist

    local a = -2 * yStart + 4 * yTop - 2 * yBottom
    local b = -3 * yStart + 4 * yTop - yBottom

    local y = -a * progress ^ 2 + b * progress + yStart

    return x, y
end

-- powSizing is unused; remove to reduce bytecode and hot path size

local function calculateOffset(fontString, elapsed)
    local xOffset, yOffset = 0, 0
    if fontString.animation == "verticalUp" then
        xOffset, yOffset = verticalPath(elapsed, fontString.animatingDuration, fontString.distance)
    elseif fontString.animation == "verticalDown" then
        xOffset, yOffset = verticalPath(elapsed, fontString.animatingDuration, -fontString.distance)
    elseif fontString.animation == "fountain" then
        xOffset, yOffset = arcPath(elapsed, fontString.animatingDuration, fontString.arcXDist, 0,
            fontString.arcTop, fontString.arcBottom)
    elseif fontString.animation == "rainfall" then
        _, yOffset = verticalPath(elapsed, fontString.animatingDuration, -fontString.distance)
        xOffset = fontString.rainfallX
        yOffset = yOffset + fontString.rainfallStartY
    end
    return xOffset, yOffset
end

local function updateFontStringPosition(fontString, elapsed)
    local xOffset, yOffset = calculateOffset(fontString, elapsed)
    local anchorFrame = fontString.anchorFrame
    if not anchorFrame then
        return false
    end

    local baseX = fontString.baseX or 0
    local baseY = fontString.baseY or 0
    fontString:SetPoint("CENTER", anchorFrame, "CENTER", baseX + xOffset, baseY + yOffset)

    return true
end

local function AnimationOnUpdate()
    local currentTime = GetTime() -- Cache time
    local cfg = C.sct
    local defaultAlpha = cfg.alpha -- Cache default alpha

    local i = 1
    while i <= #animList do
        local fontString = animList[i]
        local remove = false
        if not fontString or not fontString.animatingDuration or not fontString.animatingStartTime or not fontString.unit then
            remove = true
        elseif not UnitExists(fontString.unit) then
            remove = true
        else
            local elapsed = currentTime - fontString.animatingStartTime
            if elapsed > fontString.animatingDuration then
                remove = true
            else
                if not updateFontStringPosition(fontString, elapsed) then
                    remove = true
                else
                    -- Update alpha
                    local inv = fontString.invDuration or (1 / fontString.animatingDuration)
                    local progress = elapsed * inv
                    local startAlpha = fontString.startAlpha or defaultAlpha -- Use cached alpha
                    local endAlpha = 0
                    local currentAlpha = startAlpha + (endAlpha - startAlpha) * progress
                    if not fontString._lastAlpha or math_abs(fontString._lastAlpha - currentAlpha) > 0.01 then
                        fontString:SetAlpha(currentAlpha)
                        fontString._lastAlpha = currentAlpha
                        if fontString.icon then
                            fontString.icon:SetAlpha(currentAlpha)
                        end
                    end
                end
            end
        end

        if remove then
            removeAnimating(fontString, true)
            -- do not increment i; swapped element needs processing
        else
            i = i + 1
        end
    end

    -- stop OnUpdate when there is nothing to animate
    if #animList == 0 then
        RefineUI_SCT.frame:SetScript("OnUpdate", nil)
    end
end

local arcDirection = 1
function RefineUI_SCT:Animate(fontString, anchorFrame, duration, animation)
    fontString.animation = animation
    fontString.animatingDuration = duration
    fontString.animatingStartTime = GetTime()
    fontString.invDuration = 1 / duration
    fontString.anchorFrame = anchorFrame
    local isPersonal = fontString.guid == playerGUID
    fontString.baseX = isPersonal and C.sct.personal_x_offset or C.sct.x_offset
    fontString.baseY = isPersonal and C.sct.personal_y_offset or C.sct.y_offset

    if animation == "verticalUp" or animation == "verticalDown" then
        fontString.distance = ANIMATION.VERTICAL_DISTANCE
    elseif animation == "fountain" then
        fontString.arcTop = math_random(ANIMATION.ARC_Y_TOP_MIN, ANIMATION.ARC_Y_TOP_MAX)
        fontString.arcBottom = -math_random(ANIMATION.ARC_Y_BOTTOM_MIN, ANIMATION.ARC_Y_BOTTOM_MAX)
        fontString.arcXDist = arcDirection * math_random(ANIMATION.ARC_X_MIN, ANIMATION.ARC_X_MAX)
        arcDirection = -arcDirection
    elseif animation == "rainfall" then
        fontString.distance = math_random(ANIMATION.RAINFALL_Y_MIN, ANIMATION.RAINFALL_Y_MAX)
        fontString.rainfallX = math_random(-ANIMATION.RAINFALL_X_MAX, ANIMATION.RAINFALL_X_MAX)
        fontString.rainfallStartY = -math_random(ANIMATION.RAINFALL_Y_START_MIN, ANIMATION.RAINFALL_Y_START_MAX)
    end

    addAnimating(fontString)

    if not RefineUI_SCT.frame:GetScript("OnUpdate") then
        RefineUI_SCT.frame:SetScript("OnUpdate", AnimationOnUpdate)
    end
end

----------------------------------------------------------------------------------------
--	Event Handlers
----------------------------------------------------------------------------------------
function RefineUI_SCT:NAME_PLATE_UNIT_ADDED(_, unitID)
	local guid = UnitGUID(unitID)
	unitToGuid[unitID] = guid
	if guid then
		guidToUnit[guid] = unitID
	end
end

function RefineUI_SCT:NAME_PLATE_UNIT_REMOVED(_, unitID)
	local guid = unitToGuid[unitID]
	unitToGuid[unitID] = nil
	if guid then
		guidToUnit[guid] = nil
	end

    -- Recycle any fontStrings attached to this unit
    for i = #animList, 1, -1 do
        local fontString = animList[i]
        if fontString.unit == unitID then
            removeAnimating(fontString, true)
        end
    end
end

local function shouldProcessEvent(sourceGUID, sourceFlags, destGUID)
    if C.sct.personal_only and C.sct.personal_enable and playerGUID ~= destGUID then
        return false
    end

    local isPlayerEvent = (playerGUID == sourceGUID or (C.sct.personal_enable and playerGUID == destGUID))
    local isPetEvent = (bit_band(sourceFlags, COMBATLOG_OBJECT_TYPE_GUARDIAN) > 0 or
            bit_band(sourceFlags, COMBATLOG_OBJECT_TYPE_PET) > 0) and
        bit_band(sourceFlags, COMBATLOG_OBJECT_AFFILIATION_MINE) > 0

    return isPlayerEvent or isPetEvent
end

-- Create a lookup table for event handlers
local eventHandlers = {
    SWING_DAMAGE = function(self, sourceGUID, _, sourceFlags, destGUID, _, _, amount, overkill, school, _, _, _, critical)
        if shouldProcessEvent(sourceGUID, sourceFlags, destGUID) then
            self:DamageEvent(destGUID, nil, "melee", amount, overkill, school or "physical", critical)
        end
    end,
    RANGE_DAMAGE = function(self, sourceGUID, _, sourceFlags, destGUID, _, _, spellId, spellName, _, amount, overkill,
                            school, _, _, _, critical)
        if shouldProcessEvent(sourceGUID, sourceFlags, destGUID) then
            self:DamageEvent(destGUID, spellId, spellName, amount, overkill, school, critical)
        end
    end,
    SPELL_DAMAGE = function(self, sourceGUID, _, sourceFlags, destGUID, _, _, spellId, spellName, _, amount, overkill,
                            school, _, _, _, critical)
        if shouldProcessEvent(sourceGUID, sourceFlags, destGUID) then
            self:DamageEvent(destGUID, spellId, spellName, amount, overkill, school, critical)
        end
    end,
    SPELL_PERIODIC_DAMAGE = function(self, sourceGUID, _, sourceFlags, destGUID, _, _, spellId, spellName, _, amount,
                                     overkill, school, _, _, _, critical)
        if shouldProcessEvent(sourceGUID, sourceFlags, destGUID) then
            self:DamageEvent(destGUID, spellId, spellName, amount, overkill, school, critical)
        end
    end,
    SWING_MISSED = function(self, sourceGUID, _, sourceFlags, destGUID, _, _, missType)
        if shouldProcessEvent(sourceGUID, sourceFlags, destGUID) then
            self:MissEvent(destGUID, "melee", missType)
        end
    end,
    SPELL_MISSED = function(self, sourceGUID, _, sourceFlags, destGUID, _, _, spellId, spellName, _, missType)
        if shouldProcessEvent(sourceGUID, sourceFlags, destGUID) then
            self:MissEvent(destGUID, spellName, missType, spellId)
        end
    end,
    RANGE_MISSED = function(self, sourceGUID, _, sourceFlags, destGUID, _, _, spellId, spellName, _, missType)
        if shouldProcessEvent(sourceGUID, sourceFlags, destGUID) then
            self:MissEvent(destGUID, spellName, missType, spellId)
        end
    end
}

function RefineUI_SCT:COMBAT_LOG_EVENT_UNFILTERED()
    -- Parse CLEU payload directly to avoid per-event table allocations
    local _, eventType, _,
        sourceGUID, sourceName, sourceFlags, sourceFlags2,
    destGUID, destName, destFlags, destFlags2,
    a1, a2, a3, a4, a5, a6, a7, a8, a9, a10 = CombatLogGetCurrentEventInfo()

    local handler = eventHandlers[eventType]
    if handler then
        -- Preserve the original parameter ordering expected by handlers
        -- (self, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, <extras...>)
        handler(self, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags,
            a1, a2, a3, a4, a5, a6, a7, a8, a9, a10)
    end
end

----------------------------------------------------------------------------------------
--	Display Functions
----------------------------------------------------------------------------------------
local numDamageEvents = 0
local lastDamageEventTime
local runningAverageDamageEvents = 0

function RefineUI_SCT:DamageEvent(destGUID, spellId, spellName, amount, overkill, school, critical)
    -- Cache config values
    local cfg = C.sct
    local fontInfo = C.font.sct
    local offTargetEnable = cfg.offtarget_enable
    local offTargetSize = cfg.offtarget_size
    local offTargetAlpha = cfg.offtarget_alpha
    local defaultFontSize = fontInfo[2]
    local defaultAlpha = cfg.alpha
    local handleSmallHits = cfg.size_small_hits
    local hideSmallHits = cfg.size_small_hits_hide
    local handleCrits = cfg.size_crits
    local showOverkill = cfg.overkill

    local text, animation, pow, size, alpha
    local autoattack = spellName == "melee" or spellName == "pet"
    local isPersonal = destGUID == playerGUID

    -- Select animation using lookup table
    if isPersonal then
    animation = critical and ANIMATION_TYPES.personal.crit or ANIMATION_TYPES.personal.normal
    else
        if autoattack then
        animation = critical and ANIMATION_TYPES.autoattack.crit or ANIMATION_TYPES.autoattack.normal
        else
        animation = critical and ANIMATION_TYPES.ability.crit or ANIMATION_TYPES.ability.normal
        end
    end

    pow = critical

    -- Skip if this damage event is disabled
    if animation == "disabled" then return end

    local unit = guidToUnit[destGUID]
    local isTarget = unit and UnitIsUnit(unit, "target")

    -- Determine size and alpha
    if offTargetEnable and not isTarget and not isPersonal then -- Use cached config
        size = offTargetSize -- Use cached config
        alpha = offTargetAlpha -- Use cached config
    else
        size = defaultFontSize -- Use cached config
        alpha = defaultAlpha -- Use cached config
    end

    -- Truncate and compose text (append Overkill here if enabled), then color once
    local baseText = self:FormatDamageText(amount)
    if overkill > 0 and showOverkill then -- Use cached config
        baseText = baseText .. string_format(" Overkill(%d)", overkill)
    end
    text = self:ColorText(baseText, destGUID, school, spellName)

    -- Handle small hits
    if (handleSmallHits or hideSmallHits) and not isPersonal then -- Use cached config
        size = self:HandleSmallHits(amount, critical, size)
        if not size then return end -- Skip this damage event, it's too small
    end

    -- Adjust crit size using lookup table
    if handleCrits and critical and not isPersonal then -- Use cached config
        if not (autoattack and not handleCrits) then -- Use cached config
            size = size * SIZE_MULTIPLIERS.crits
        end
    end

    -- Ensure minimum size
    size = math_max(size, MINIMUM_TEXT_SIZE)

    -- Handle overkill
    if overkill > 0 and showOverkill then -- Use cached config
        self:DisplayTextOverkill(destGUID, text, size, animation, spellId, pow)
    else
        self:DisplayText(destGUID, text, size, animation, spellId, pow)
    end
end

function RefineUI_SCT:FormatDamageText(amount)
    if C.sct.truncate_enable then
        if amount >= POW10[6] and C.sct.truncate_letter then
            return string_format("%.1fM", amount / POW10[6])
        elseif amount >= POW10[4] then
            local text = string_format("%.0f", amount / POW10[3])
            return C.sct.truncate_letter and text .. "k" or text
        elseif amount >= POW10[3] then
            local text = string_format("%.1f", amount / POW10[3])
            return C.sct.truncate_letter and text .. "k" or text
        end
    end
    return C.sct.truncate_comma and commaSeparate(amount) or tostring(amount)
end

function RefineUI_SCT:HandleSmallHits(amount, crit, size)
    local currentTime = GetTime()
    if not lastDamageEventTime or (lastDamageEventTime + SMALL_HIT.EXPIRY_WINDOW < currentTime) then
        numDamageEvents = 0
        runningAverageDamageEvents = 0
    end

    runningAverageDamageEvents = ((runningAverageDamageEvents * numDamageEvents) + amount) / (numDamageEvents + 1)
    numDamageEvents = numDamageEvents + 1
    lastDamageEventTime = currentTime

    local threshold = SMALL_HIT.MULTIPLIER * runningAverageDamageEvents
    if (not crit and amount < threshold) or (crit and amount / 2 < threshold) then
        if C.sct.size_small_hits_hide then
            return nil -- Skip this damage event
        else
            return size * SIZE_MULTIPLIERS.small_hits
        end
    end
    return size
end

function RefineUI_SCT:MissEvent(guid, spellName, missType, spellId)
    -- Cache config values
    local cfg = C.sct
    local fontInfo = C.font.sct
    local personalDefaultColor = cfg.personal_default_color
    local defaultColor = cfg.default_color
    local offTargetEnable = cfg.offtarget_enable
    local offTargetSize = cfg.offtarget_size
    local offTargetAlpha = cfg.offtarget_alpha
    local defaultFontSize = fontInfo[2]
    local defaultAlpha = cfg.alpha
    local handleMissSize = cfg.size_miss

    local text, animation, pow, size, alpha, color
    local isPersonal = guid == playerGUID

    animation = isPersonal and ANIMATION_TYPES.personal.miss or ANIMATION_TYPES.miss
    color = isPersonal and personalDefaultColor or defaultColor -- Use cached config

    -- No animation set, cancel out
    if animation == "disabled" then return end

    local unit = guidToUnit[guid]
    local isTarget = unit and UnitIsUnit(unit, "target")

    if offTargetEnable and not isTarget and not isPersonal then -- Use cached config
        size = offTargetSize -- Use cached config
        alpha = offTargetAlpha -- Use cached config
    else
        size = defaultFontSize -- Use cached config
        alpha = defaultAlpha -- Use cached config
    end

    -- Ensure size is a number and has a minimum value
    size = tonumber(size) or defaultFontSize -- Use cached config
    size = math.max(size, MINIMUM_TEXT_SIZE)

    -- Adjust miss size using lookup table
    if handleMissSize and not isPersonal then -- Use cached config
        size = size * (SIZE_MULTIPLIERS.miss or 1)
    end

    pow = true

    text = MISS_EVENT_STRINGS[missType] or "Missed"
    text = string_format("|Cff%s%s|r", color, text)

    self:DisplayText(guid, text, size, animation, spellId, pow, spellName)
end

function RefineUI_SCT:DisplayText(guid, text, size, animation, spellId, pow, spellName)
    -- Cache config values
    local cfg = C.sct
    local fontInfo = C.font.sct
    local offTargetEnable = cfg.offtarget_enable
    local offTargetAlpha = cfg.offtarget_alpha
    local defaultAlpha = cfg.alpha
    local iconEnable = cfg.icon_enable
    local iconScale = cfg.icon_scale
    local iconPosition = cfg.icon_position
    local iconXOffset = cfg.icon_x_offset
    local iconYOffset = cfg.icon_y_offset
    local animationSpeed = cfg.animations_speed

    local fontString = getFontString()
    ---@cast fontString SCTFontString
    local unit = guidToUnit[guid]
    local nameplate = unit and GetNamePlateForUnit(unit) or (playerGUID == guid and UIParent)

    if not nameplate then return end

    fontString:SetText(text)
    -- Avoid redundant SetFont/SetShadowOffset; already set on acquire
    fontString.startHeight = math_max(fontString:GetStringHeight(), MINIMUM_TEXT_SIZE)
    fontString.pow = pow
    fontString.unit = unit
    fontString.guid = guid

    -- unit/guid kept externally via animating table keys; use local variables here

    -- Calculate and apply alpha
    local isTarget = unit and UnitIsUnit(unit, "target")
    local alpha
    if offTargetEnable and not isTarget and guid ~= playerGUID then -- Use cached config
        alpha = offTargetAlpha -- Use cached config
    else
        alpha = defaultAlpha -- Use cached config
    end
    fontString:SetAlpha(alpha)
    fontString.startAlpha = alpha

    if iconEnable then -- Use cached config
        local texture
        local cacheKey
        if type(spellId) == "number" then
            cacheKey = spellId
        elseif type(spellName) == "string" then
            cacheKey = spellName
        end

        if cacheKey ~= nil then
            texture = SPELL_ICON_CACHE[cacheKey]
        end

        if texture == nil then
            if type(spellId) == "number" then
                texture = GetSpellTexture(spellId)
            elseif type(spellName) == "string" then
                local spellID = select(7, GetSpellInfo(spellName))
                if spellID then
                    texture = GetSpellTexture(spellID)
                end
            end
            cacheSpellIcon(cacheKey, texture)
        end

        if texture then
            local icon = fontString.icon or fontString:GetParent():CreateTexture(nil, "BACKGROUND")
            icon:Show()
            icon:SetTexture(texture)
            icon:SetSize(size * iconScale, size * iconScale) -- Use cached config
            icon:SetPoint(INVERSE_POSITIONS[iconPosition], fontString, iconPosition, -- Use cached config
                iconXOffset, iconYOffset) -- Use cached config
            icon:SetAlpha(alpha) -- Also apply alpha to the icon
            fontString.icon = icon
        elseif fontString.icon then
            fontString.icon:Hide()
        end
    end
    
    self:Animate(fontString, nameplate, animationSpeed, animation) -- Use cached config
end

function RefineUI_SCT:DisplayTextOverkill(guid, text, size, animation, spellId, pow, spellName)
    self:DisplayText(guid, text, size, animation, spellId, pow, spellName)
end

local function getColor(guid, school, spellName)
    return (guid ~= playerGUID and DAMAGE_TYPE_COLORS[school]) or
        DAMAGE_TYPE_COLORS[spellName] or
        "ffffff"
end

function RefineUI_SCT:ColorText(startingText, guid, school, spellName)
    return string_format("|Cff%s%s|r", getColor(guid, school, spellName), startingText)
end

----------------------------------------------------------------------------------------
--	Initialization
----------------------------------------------------------------------------------------
function RefineUI_SCT:Init()
    -- Setup db
    RefineUI_SCTDB = RefineUI_SCTDB or {}
    self.db = RefineUI_SCTDB

    -- If the addon is turned off in db, turn it off
    if C.sct.enable == false then
        self:Disable()
        self.frame:UnregisterAllEvents()
        while #animList > 0 do
            local fontString = tremove(animList)
            animIndex[fontString] = nil
            recycleFontString(fontString)
        end
    else
        playerGUID = UnitGUID("player")
        self.frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        self.frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        self.frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        self.frame:SetScript("OnEvent", function(_, event, ...)
            if self[event] then
                self[event](self, event, ...)
            end
        end)
    end
end

function RefineUI_SCT:Disable()
    -- Unregister events
    self.frame:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
    self.frame:UnregisterEvent("NAME_PLATE_UNIT_REMOVED")
    self.frame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

    -- Remove scripts
    self.frame:SetScript("OnEvent", nil)
    self.frame:SetScript("OnUpdate", nil) -- Stop animation loop

    -- Recycle any active font strings
    while #animList > 0 do
        local fontString = tremove(animList)
        animIndex[fontString] = nil
        recycleFontString(fontString)
    end

    -- Optional: Clear caches if memory becomes an issue
    -- wipe(fontStringCache)
    -- for poolName in pairs(tablePools) do
    --     wipe(tablePools[poolName])
    -- end
end

-- Initialize the addon
RefineUI_SCT:Init()