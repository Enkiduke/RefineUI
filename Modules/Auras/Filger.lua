local R, C, L = unpack(RefineUI)
if C.filger.enable ~= true then return end

--------------------------------------------------------------------------------
-- Upvalues / locals
--------------------------------------------------------------------------------
local _G = _G
local pairs, ipairs, select, type = pairs, ipairs, select, type
local floor = math.floor
local AuraUtil = AuraUtil
local C_Timer = C_Timer

-- hot path stdlib locals (used inside scanners/sorters)
local tinsert = table.insert
local twipe   = wipe or table.wipe
local sort    = table.sort
local min     = math.min
local max     = math.max
local now     = GetTime -- use as function call: now()

----------------------------------------------------------------------------------------
--	Lightweight buff/debuff tracking (Filger by Nils Ruesch, editors Affli/SinaC/Ildyria)
--	Refactored for SOLID, DRY, and KISS principles
----------------------------------------------------------------------------------------

-- Constants and Configuration
local FILGER_CONSTANTS = {
    FRAME_STRATA = "BACKGROUND",
    COOLDOWN_THRESHOLD = 1.5,
    MAX_COOLDOWN_DURATION = 900,
    UPDATE_INTERVAL = 0.1,
    MIN_REMAINING_TIME = 0.3,
    COOLDOWN_OFFSET = 0.1,
    FRAME_LEVEL_OFFSET = 1,
    TOOLTIP_SPELL_ID_THRESHOLD = 20,

    FILTERS = {
        HELPFUL = "HELPFUL",
        HARMFUL = "HARMFUL",
        BUFF = "BUFF",
        DEBUFF = "DEBUFF",
        CD = "CD",
        ICD = "ICD",
        MISSING = "MISSING",
        STACKS = "STACKS"
    },

    DIRECTIONS = {
        UP = "UP",
        DOWN = "DOWN",
        LEFT = "LEFT",
        RIGHT = "RIGHT"
    }
}

local MY_UNITS = { player = true, vehicle = true, pet = true }

-- Optional tiny table pool (disabled by default for KISS/YAGNI)
R.Filger._usePool = R.Filger._usePool == true -- only true if explicitly set elsewhere
local _pool = {}
local function take()
    if not R.Filger._usePool then return {} end
    local t = _pool[#_pool]
    if t then _pool[#_pool] = nil; return t end
    return {}
end
local function give(t)
    if not R.Filger._usePool or not t then return end
    for k in pairs(t) do t[k] = nil end
    _pool[#_pool+1] = t
end

--------------------------------------------------------------------------------
-- Aura scan helper: uses AuraUtil.ForEachAura when available, falls back to index loop
--------------------------------------------------------------------------------
local function ForEachAura(unit, filter, callback)
    if AuraUtil and AuraUtil.ForEachAura then
        -- Use Blizzard's iterator to reduce C->Lua crossings
        AuraUtil.ForEachAura(unit, filter, nil, function(aura)
            callback(
                aura.name, aura.icon, aura.applications or aura.stackCount or 0,
                aura.duration, aura.expirationTime, aura.sourceUnit, aura.spellId
            )
        end, true)
        return
    end
    -- Fallback for older clients
    local index = 1
    while true do
        local name, icon, count, _, duration, expirationTime, sourceUnit, _, _, spellId = UnitAura(unit, index, filter)
        if not name then break end
        callback(name, icon, count or 0, duration, expirationTime, sourceUnit, spellId)
        index = index + 1
    end
end

-- Core Filger System
local FilgerSystem = {
    frames = {},
    spellGroups = {},
    anchors = {}
}

-- Namespace setup
R.Filger = R.Filger or {}

-- Anchor Management (Single Responsibility)
local AnchorManager = {
    configs = {
        LEFT_BUFF = { position = C.position.filger.left_buff, size = C.filger.buffs_size },
        RIGHT_BUFF = { position = C.position.filger.right_buff, size = C.filger.buffs_size },
        BOTTOM_BUFF = { position = C.position.filger.bottom_buff, size = C.filger.buffs_size }
    }
}

function AnchorManager:InitializeAnchors()
    SpellActivationOverlayFrame:SetFrameStrata(FILGER_CONSTANTS.FRAME_STRATA)

    for anchorName, config in pairs(self.configs) do
        local anchor = _G[anchorName .. "_Anchor"]
        if anchor then
            anchor:SetPoint(unpack(config.position))
            anchor:SetSize(config.size, config.size)
            FilgerSystem.anchors[anchorName] = anchor
        end
    end
    self._initialized = true
end

-- expose for use by coalesced updater guard
R.Filger.AnchorManager = AnchorManager

-- Spell Data Management (Single Responsibility)
local SpellDataManager = {}

-- Helper function to check if a spell should be shown based on spec filtering
function SpellDataManager:ShouldShowSpellForSpec(spellData)
    -- If no global spec filter is set, show all spells
    if not R.Filger or not R.Filger.SpecFilter then
        return true
    end

    local globalSpecFilter = R.Filger.SpecFilter

    -- If global filter is "ALL", show all spells
    if globalSpecFilter == "ALL" then
        return true
    end

    -- If spell has no spec requirement, show it
    if not spellData.spec or spellData.spec == "ALL" then
        return true
    end

    -- If spell spec matches global filter, show it
    if spellData.spec == globalSpecFilter then
        return true
    end

    -- If spell spec matches current player spec, show it
    if type(spellData.spec) == "number" and spellData.spec == R.Spec then
        return true
    end

    return false
end

function SpellDataManager:CreateSpellDataObject(spellData, sortIndex)
    if not spellData or not spellData.spellID then
        return nil
    end

    local spellID = spellData.spellID
    local name, _, icon = GetSpellInfo(spellID)
    if not name then
        return nil
    end

    return {
        spellID = spellID,
        name = name,
        icon = icon,
        filter = spellData.filter or FILGER_CONSTANTS.FILTERS.BUFF,
        caster = spellData.caster or "player",
        absID = spellData.absID,
        color = spellData.color,
        duration = spellData.duration,
        unitID = spellData.unitID or "player",
        spec = spellData.spec or "ALL", -- Include spec information
        sort = sortIndex or 1,
        custom = true
    }
end

function SpellDataManager:RefreshSpellGroups()
    twipe(FilgerSystem.spellGroups)

    local enabledGroups = {
        ["LEFT_BUFF"] = C.filger.show_buff,
        ["RIGHT_BUFF"] = C.filger.show_proc,
        ["BOTTOM_BUFF"] = C.filger.show_special,
    }

    local groupIndex = 1

    for location, spellList in pairs(R.Filger.ManagedSpells or {}) do
        if enabledGroups[location] and spellList and #spellList > 0 then
            local group = self:CreateSpellGroup(location, spellList, groupIndex)
            if group and next(group.spells) then
                FilgerSystem.spellGroups[groupIndex] = group
                groupIndex = groupIndex + 1
            end
        end
    end
end

function SpellDataManager:CreateSpellGroup(location, spellList, groupId)
    local group = {
        Name = location,
        Id = groupId,
        spells = {},
        Mode = "ICON"
    }

    -- Configure group based on location
    local locationConfig = {
        ["LEFT_BUFF"] = { direction = FILGER_CONSTANTS.DIRECTIONS.LEFT, anchor = "LEFT_BUFF_Anchor" },
        ["RIGHT_BUFF"] = { direction = FILGER_CONSTANTS.DIRECTIONS.RIGHT, anchor = "RIGHT_BUFF_Anchor" },
        ["BOTTOM_BUFF"] = { direction = FILGER_CONSTANTS.DIRECTIONS.LEFT, anchor = "BOTTOM_BUFF_Anchor" }
    }

    local config = locationConfig[location]
    if config then
        group.Direction = config.direction
        group.Position = { "TOP", FilgerSystem.anchors[location:gsub("_BUFF", "_BUFF")] }
    end

    -- Process spells
    local sortIndex = 1
    for _, spellData in ipairs(spellList) do
        -- Check if spell should be shown based on spec filtering
        if self:ShouldShowSpellForSpec(spellData) then
            local spellObj = self:CreateSpellDataObject(spellData, sortIndex)
            if spellObj then
                group.spells[spellObj.spellID] = spellObj
                sortIndex = sortIndex + 1
            elseif spellData.spellID then
                print("|cFFFFD200Warning:|r Could not get info for spell ID", spellData.spellID, "in group", location)
            end
        end
    end

    return group
end

-- Aura Scanner (Single Responsibility)
local AuraScanner = {}

function AuraScanner:ScanUnit(frame, unit)
    -- Clear non-CD/ICD auras for this unit
    self:ClearUnitAuras(frame, unit)

    -- Scan both helpful and harmful auras
    for i = 1, 2 do
        local filter = (i == 1) and FILGER_CONSTANTS.FILTERS.HELPFUL or FILGER_CONSTANTS.FILTERS.HARMFUL
        self:ProcessAuraFilter(frame, unit, filter)
    end
end

function AuraScanner:ClearUnitAuras(frame, unit)
    for spellId in pairs(frame.actives or {}) do
        local activeData = frame.actives[spellId]
        if activeData.data.filter ~= FILGER_CONSTANTS.FILTERS.CD and
            activeData.data.filter ~= FILGER_CONSTANTS.FILTERS.ICD and
            activeData.data.filter ~= FILGER_CONSTANTS.FILTERS.MISSING and
            activeData.data.filter ~= FILGER_CONSTANTS.FILTERS.STACKS and
            activeData.data.unitID == unit then
            frame.actives[spellId] = nil
        end
    end
end

function AuraScanner:ProcessAuraFilter(frame, unit, filter)
    ForEachAura(unit, filter, function(name, icon, count, duration, expirationTime, caster, spellId)
        local spellData = self:GetManagedSpellData(frame, spellId)
        if spellData and self:ValidateAuraConditions(spellData, caster, unit, count, filter) then
            local e = take()
            e.data = spellData; e.name = name; e.icon = icon; e.count = count
            e.start = (expirationTime and duration) and (expirationTime - duration) or 0
            e.duration = duration; e.spid = spellId; e.sort = spellData.sort; e.color = spellData.color
            frame.actives[spellId] = e
        end
    end)
end

function AuraScanner:GetManagedSpellData(frame, spellId)
    local spellGroup = FilgerSystem.spellGroups[frame.Id]
    return spellGroup and spellGroup.spells[spellId]
end

function AuraScanner:ValidateAuraConditions(spellData, caster, unit, count, filter)
    -- Validate caster
    local casterValid = (spellData.caster ~= 1 and
            (caster == spellData.caster or spellData.caster == "all")) or
        MY_UNITS[caster]

    -- Validate unit
    local unitValid = not spellData.unitID or spellData.unitID == unit

    -- Validate absolute ID
    local absIdValid = not spellData.absID or spellData.absID == spellData.spellID

    -- Validate spec filtering
    local specValid = true
    if spellData.spec then
        if spellData.spec == "ALL" then
            specValid = true
        elseif type(spellData.spec) == "number" then
            specValid = spellData.spec == R.Spec
        end
    end

    -- Validate filter type and count
    local filterValid = (spellData.filter == FILGER_CONSTANTS.FILTERS.BUFF and filter == FILGER_CONSTANTS.FILTERS.HELPFUL) or
        (spellData.filter == FILGER_CONSTANTS.FILTERS.DEBUFF and filter == FILGER_CONSTANTS.FILTERS.HARMFUL)
    -- Note: STACKS type is handled separately by StacksManager, not by AuraScanner
    local countValid = not spellData.count or count >= spellData.count

    return casterValid and unitValid and absIdValid and specValid and filterValid and countValid
end

-- Cooldown Manager (Single Responsibility)
local CooldownManager = {}

function CooldownManager:UpdateCooldowns(frame)
    -- Clear existing CD actives first
    self:ClearCooldownActives(frame)

    -- Check managed spells for cooldowns
    local spellGroup = FilgerSystem.spellGroups[frame.Id]
    if not spellGroup then return end

    for spellId, spellData in pairs(spellGroup.spells) do
        if self:IsCooldownSpell(spellData) then
            self:ProcessCooldownSpell(frame, spellId, spellData)
        end
    end
end

function CooldownManager:ClearCooldownActives(frame)
    for spellId in pairs(frame.actives or {}) do
        if frame.actives[spellId].data.filter == FILGER_CONSTANTS.FILTERS.CD then
            frame.actives[spellId] = nil
        end
    end
end

function CooldownManager:IsCooldownSpell(spellData)
    -- Check if it's a cooldown spell
    if spellData.filter ~= FILGER_CONSTANTS.FILTERS.CD then
        return false
    end

    -- Check spec filtering
    if spellData.spec then
        if spellData.spec == "ALL" then
            return true
        elseif type(spellData.spec) == "number" then
            return spellData.spec == R.Spec
        end
    end

    -- Default to true if no spec specified (backward compatibility)
    return true
end

function CooldownManager:ProcessCooldownSpell(frame, spellId, spellData)
    if not spellData.spellID then return end

    local name, _, icon = GetSpellInfo(spellData.spellID)
    if not name then return end

    local start, duration = C_Spell.GetSpellCooldown(spellData.spellID)

    if self:IsValidCooldown(duration) then
        frame.actives[spellId] = {
            data = spellData,
            name = name,
            icon = icon,
            count = nil,
            start = start,
            duration = duration,
            spid = spellId,
            sort = spellData.sort,
            color = spellData.color
        }
    end
end

function CooldownManager:IsValidCooldown(duration)
    return duration and
        duration > FILGER_CONSTANTS.COOLDOWN_THRESHOLD and
        duration < FILGER_CONSTANTS.MAX_COOLDOWN_DURATION
end

function CooldownManager:UpdateCooldownTimer(bar)
    local remainingTime = bar.value.start + bar.value.duration - GetTime()

    if remainingTime < 0 then
        local frame = bar:GetParent()
        frame.actives[bar.value.spid] = nil
        bar:SetScript("OnUpdate", nil)
        DisplayManager:RefreshDisplay(frame)
    end
end

-- Missing Buff Manager (Single Responsibility)
local MissingBuffManager = {}

function MissingBuffManager:UpdateMissingBuffs(frame)
    -- Only show missing buffs in combat
    if not InCombatLockdown() then
        self:ClearMissingBuffs(frame)
        return
    end

    local spellGroup = FilgerSystem.spellGroups[frame.Id]
    if not spellGroup then return end

    for spellId, spellData in pairs(spellGroup.spells) do
        if self:IsMissingBuffSpell(spellData) then
            self:ProcessMissingBuffSpell(frame, spellId, spellData)
        end
    end
end

function MissingBuffManager:ClearMissingBuffs(frame)
    for spellId in pairs(frame.actives or {}) do
        if frame.actives[spellId].data.filter == FILGER_CONSTANTS.FILTERS.MISSING then
            frame.actives[spellId] = nil
        end
    end
end

function MissingBuffManager:IsMissingBuffSpell(spellData)
    if spellData.filter ~= FILGER_CONSTANTS.FILTERS.MISSING then
        return false
    end

    -- Check spec filtering
    if spellData.spec then
        if spellData.spec == "ALL" then
            return true
        elseif type(spellData.spec) == "number" then
            return spellData.spec == R.Spec
        end
    end

    -- Default to true if no spec specified (backward compatibility)
    return true
end

function MissingBuffManager:ProcessMissingBuffSpell(frame, spellId, spellData)
    if not spellData.spellID then return end

    local name, _, icon = GetSpellInfo(spellData.spellID)
    if not name then return end

    -- Check if the buff is actually missing on the specified unit
    local unit = spellData.unitID or "player"
    local hasBuff = self:HasBuff(unit, spellData.spellID, spellData.caster)

    if not hasBuff then
        -- Show the missing buff icon
        frame.actives[spellId] = {
            data = spellData,
            name = name,
            icon = icon,
            count = nil,
            start = nil,
            duration = nil,
            spid = spellId,
            sort = spellData.sort,
            color = spellData.color
        }
    else
        -- Remove if buff is present
        frame.actives[spellId] = nil
    end
end

function MissingBuffManager:HasBuff(unit, spellID, requiredCaster)
    if not UnitExists(unit) then return false end

    -- Scan through all buffs on the unit
    local index = 1
    while true do
        local name, icon, count, _, duration, expirationTime, caster, _, _, foundSpellId = UnitAura(unit, index,
            "HELPFUL")
        if not name then break end

        if foundSpellId == spellID then
            -- Found the buff, check caster if specified
            if not requiredCaster or requiredCaster == "all" then
                return true
            elseif requiredCaster == "player" and MY_UNITS[caster] then
                return true
            elseif caster == requiredCaster then
                return true
            end
        end

        index = index + 1
    end

    return false
end

-- Stacks Manager (Single Responsibility)
local StacksManager = {}

function StacksManager:UpdateStacksTracking(frame)
    local spellGroup = FilgerSystem.spellGroups[frame.Id]
    if not spellGroup then return end

    for spellId, spellData in pairs(spellGroup.spells) do
        if self:IsStacksSpell(spellData) then
            self:ProcessStacksSpell(frame, spellId, spellData)
        end
    end
end

function StacksManager:IsStacksSpell(spellData)
    if spellData.filter ~= FILGER_CONSTANTS.FILTERS.STACKS then
        return false
    end

    -- Check spec filtering
    if spellData.spec then
        if spellData.spec == "ALL" then
            return true
        elseif type(spellData.spec) == "number" then
            return spellData.spec == R.Spec
        end
    end

    -- Default to true if no spec specified (backward compatibility)
    return true
end

function StacksManager:ProcessStacksSpell(frame, spellId, spellData)
    if not spellData.spellID then return end

    local name, _, icon = GetSpellInfo(spellData.spellID)
    if not name then return end

    -- Check if the buff exists and get its stack count and duration info
    local unit = spellData.unitID or "player"
    local stackCount, duration, expirationTime = self:GetStackInfo(unit, spellData.spellID, spellData.caster)

    if stackCount > 0 then
        -- Show the stacks icon with stack count and duration info
        local start = nil
        if duration and expirationTime then
            start = expirationTime - duration
        end

        frame.actives[spellId] = {
            data = spellData,
            name = name,
            icon = icon,
            count = stackCount,
            start = start,
            duration = duration,
            spid = spellId,
            sort = spellData.sort,
            color = spellData.color,
            isStacks = true -- Flag to identify this as a stacks entry
        }
    else
        -- Remove if buff is not present
        frame.actives[spellId] = nil
    end
end

function StacksManager:GetStackInfo(unit, spellID, requiredCaster)
    if not UnitExists(unit) then return 0, nil, nil end

    -- Scan through all buffs on the unit
    local index = 1
    while true do
        local name, icon, count, _, duration, expirationTime, caster, _, _, foundSpellId = UnitAura(unit, index,
            "HELPFUL")
        if not name then break end

        if foundSpellId == spellID then
            -- Found the buff, check caster if specified
            if not requiredCaster or requiredCaster == "all" then
                return count or 1, duration, expirationTime
            elseif requiredCaster == "player" and MY_UNITS[caster] then
                return count or 1, duration, expirationTime
            elseif caster == requiredCaster then
                return count or 1, duration, expirationTime
            end
        end

        index = index + 1
    end

    return 0, nil, nil
end

-- UI Display Manager (Single Responsibility)
local DisplayManager = {}

function DisplayManager:RefreshDisplay(frame)
    if not frame.actives then return end

    local settings = self:GetFrameSettings(frame)
    local activeList = self:SortActives(frame)

    self:UpdateBarVisuals(frame, activeList, settings)
    self:HideUnusedBars(frame, #activeList)
end

function DisplayManager:GetFrameSettings(frame)
    local frameSettings = R.Filger.FrameSettings and R.Filger.FrameSettings[frame.Name] or {}
    return {
        iconSize = frameSettings.size or C.filger.buffs_size or 36,
        spacing = frameSettings.space or C.filger.buffs_space or 3,
        limit = (C.actionbars.buttonSize * 12) / (frameSettings.size or C.filger.buffs_size or 36)
    }
end

function DisplayManager:SortActives(frame)
    local activeList = {}
    for _, value in pairs(frame.actives) do
        tinsert(activeList, value)
    end

    sort(activeList, function(a, b)
        if C.filger.expiration == true and a.data.filter == FILGER_CONSTANTS.FILTERS.CD then
            return a.start + a.duration < b.start + b.duration
        else
            return a.sort < b.sort
        end
    end)

    return activeList
end

function DisplayManager:UpdateBarVisuals(frame, activeList, settings)
    frame.bars = frame.bars or {}
    local previous = nil

    for i, activeData in ipairs(activeList) do
        if i >= settings.limit then break end

        local bar = self:GetOrCreateBar(frame, i, previous, settings)
        self:ConfigureBar(bar, activeData, settings)

        previous = bar
    end
end

function DisplayManager:GetOrCreateBar(frame, index, previous, settings)
    local bar = frame.bars[index]

    if not bar then
        bar = self:CreateNewBar(frame, index, previous, settings)
        frame.bars[index] = bar
    end

    return bar
end

function DisplayManager:CreateNewBar(frame, index, previous, settings)
    local bar = CreateFrame("Frame", "FilgerAnchor" .. frame.Id .. "Frame" .. index, frame)
    bar:SetTemplate("Icon")

    -- Position the bar
    self:PositionBar(bar, frame, index, previous, settings.spacing)

    -- Create bar components
    self:CreateBarComponents(bar)

    return bar
end

function DisplayManager:PositionBar(bar, frame, index, previous, spacing)
    if index == 1 then
        bar:SetPoint(unpack(frame.Position))
    else
        local direction = frame.Direction
        if direction == FILGER_CONSTANTS.DIRECTIONS.UP then
            bar:SetPoint("BOTTOM", previous, "TOP", 0, spacing)
        elseif direction == FILGER_CONSTANTS.DIRECTIONS.RIGHT then
            bar:SetPoint("LEFT", previous, "RIGHT", spacing, 0)
        elseif direction == FILGER_CONSTANTS.DIRECTIONS.LEFT then
            bar:SetPoint("RIGHT", previous, "LEFT", -spacing, 0)
        else
            bar:SetPoint("TOP", previous, "BOTTOM", 0, -spacing)
        end
    end
end

function DisplayManager:CreateBarComponents(bar)
    -- Icon
    bar.icon = bar:CreateTexture("$parentIcon", "BORDER")
    bar.icon:SetPoint("TOPLEFT", 2, -2)
    bar.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    bar.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)

    -- Cooldown frame
    bar.cooldown = CreateFrame("Cooldown", "$parentCD", bar, "CooldownFrameTemplate")
    bar.cooldown:SetAllPoints(bar.icon)
    bar.cooldown:SetReverse(true)
    bar.cooldown:SetDrawEdge(false)
    bar.cooldown:SetFrameLevel(3)

    -- Disable the built-in cooldown text to prevent double text display
    bar.cooldown:SetHideCountdownNumbers(true)

    -- Count text
    bar.count = bar:CreateFontString("$parentCount", "OVERLAY")
    bar.count:SetFont(unpack(C.font.filger.count))
    bar.count:SetShadowOffset(1, -1)
    bar.count:SetPoint("BOTTOMRIGHT", 1, -2)
    bar.count:SetJustifyH("RIGHT")

    -- Duration text
    bar.duration = bar:CreateFontString(nil, "OVERLAY")
    bar.duration:SetFont(unpack(C.font.filger.time))
    bar.duration:SetShadowOffset(1, -1)
    bar.duration:SetPoint("CENTER", 0, 0)
end

function DisplayManager:ConfigureBar(bar, activeData, settings)
    bar.spellName = activeData.name
    bar.spellID = activeData.spid

    -- Clear any existing OnUpdate script to prevent race conditions
    bar:SetScript("OnUpdate", nil)

    -- Set size and basic properties
    bar:SetSize(settings.iconSize, settings.iconSize)
    bar:SetAlpha(activeData.data.opacity or 1)
    bar:Show()

    -- Configure icon
    bar.icon:SetTexture(activeData.icon)

    -- Configure count
    self:UpdateBarCount(bar, activeData)

    -- Configure cooldown and duration
    self:UpdateBarCooldown(bar, activeData)

    -- Configure tooltip
    self:UpdateBarTooltip(bar)

    -- Configure border color
    self:UpdateBarBorder(bar, activeData)

    -- Configure frame levels
    self:UpdateBarFrameLevels(bar)

    -- Configure flashing for Missing type buffs
    self:UpdateBarFlashing(bar, activeData)
end

function DisplayManager:UpdateBarFlashing(bar, activeData)
    local shouldFlash = activeData.data.filter == FILGER_CONSTANTS.FILTERS.MISSING and C.filger.missing_flash

    -- Only change animation state if the flashing requirement has changed
    if shouldFlash and not bar.isFlashing then
        -- Start flashing
        self:StartFlashingAnimation(bar)
        bar.isFlashing = true
    elseif not shouldFlash and bar.isFlashing then
        -- Stop flashing
        if bar.flashAnimation then
            bar.flashAnimation:Stop()
        end
        bar.isFlashing = false
    end
    -- If shouldFlash == bar.isFlashing, do nothing to avoid interrupting animation
end

function DisplayManager:StartFlashingAnimation(bar)
    -- Create animation group if it doesn't exist
    if not bar.flashAnimation then
        bar.flashAnimation = bar:CreateAnimationGroup()
        bar.flashAnimation:SetLooping("REPEAT")

        -- Single smooth breathing animation - uses built-in ping-pong effect
        local breathe = bar.flashAnimation:CreateAnimation("Alpha")
        breathe:SetFromAlpha(0.9)
        breathe:SetToAlpha(0.2)
        breathe:SetDuration(.75)
        breathe:SetSmoothing("IN_OUT")

        -- Use the animation's built-in ping-pong looping
        bar.flashAnimation:SetLooping("BOUNCE")
    end

    -- Start the animation
    bar.flashAnimation:Play()
end

function DisplayManager:UpdateBarCount(bar, activeData)
    -- Handle STACKS type specially - show stack count prominently in center
    if activeData.data.filter == FILGER_CONSTANTS.FILTERS.STACKS then
        if activeData.count and activeData.count > 0 then
            -- Hide normal count text - stacks will be shown in duration text area
            bar.count:Hide()
        else
            bar.count:Hide()
        end
    else
        -- Normal count display for non-stacks
        if activeData.count and activeData.count > 1 then
            bar.count:SetText(activeData.count)
            bar.count:Show()
        else
            bar.count:Hide()
        end
    end
end

function DisplayManager:UpdateBarCooldown(bar, activeData)
    -- Handle STACKS type specially - show cooldown if exists, but display stack count as text
    if activeData.data.filter == FILGER_CONSTANTS.FILTERS.STACKS then
        -- IMPORTANT: Clear any existing OnUpdate script first to prevent race conditions
        bar:SetScript("OnUpdate", nil)

        if activeData.duration and activeData.duration > 0 then
            -- Show cooldown swipe for duration
            local remainingTime = activeData.start + activeData.duration - GetTime()

            if remainingTime > FILGER_CONSTANTS.MIN_REMAINING_TIME then
                bar.cooldown:SetCooldown(activeData.start + FILGER_CONSTANTS.COOLDOWN_OFFSET, activeData.duration)
            end

            bar.cooldown:Show()
        else
            bar.cooldown:Hide()
        end

        -- Always show stack count as duration text for STACKS type
        if activeData.count and activeData.count > 0 then
            bar.duration:SetText(tostring(activeData.count))
            bar.duration:Show()
        else
            bar.duration:Hide()
        end

        return
    end

    if activeData.duration and activeData.duration > 0 then
        local remainingTime = activeData.start + activeData.duration - GetTime()

        if remainingTime > FILGER_CONSTANTS.MIN_REMAINING_TIME then
            bar.cooldown:SetCooldown(activeData.start + FILGER_CONSTANTS.COOLDOWN_OFFSET, activeData.duration)
        end

        if activeData.data.filter == FILGER_CONSTANTS.FILTERS.CD or
            activeData.data.filter == FILGER_CONSTANTS.FILTERS.ICD then
            bar.value = activeData
            bar:SetScript("OnUpdate", CooldownManager.UpdateCooldownTimer)
        else
            self:SetupDurationUpdate(bar, activeData)
        end

        bar.cooldown:Show()
        bar.duration:Show()
    else
        bar.cooldown:Hide()
        bar.duration:Hide()
        bar:SetScript("OnUpdate", nil)
    end
end

function DisplayManager:SetupDurationUpdate(bar, activeData)
    bar:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = (self.elapsed or 0) + elapsed
        if self.elapsed >= FILGER_CONSTANTS.UPDATE_INTERVAL then
            local timeLeft = activeData.start + activeData.duration - GetTime()
            if timeLeft > 0 then
                self.duration:SetText(R.FormatTime(timeLeft))
            else
                self.duration:SetText("")
                self:SetScript("OnUpdate", nil)
            end
            self.elapsed = 0
        end
    end)
end

function DisplayManager:UpdateBarTooltip(bar)
    if C.filger.show_tooltip then
        bar:EnableMouse(true)
        bar:SetScript("OnEnter", TooltipHandler.OnEnter)
        bar:SetScript("OnLeave", TooltipHandler.OnLeave)
    end
end

function DisplayManager:UpdateBarBorder(bar, activeData)
    if activeData.data.color then
        bar.border:SetBackdropBorderColor(unpack(activeData.data.color))
    else
        local r, g, b = unpack(R.oUF_colors.class[R.class])
        bar.border:SetBackdropBorderColor(r, g, b, 1)
    end
end

function DisplayManager:UpdateBarFrameLevels(bar)
    bar.cooldown:SetFrameLevel(bar:GetFrameLevel() + FILGER_CONSTANTS.FRAME_LEVEL_OFFSET)
    bar.cooldown:SetSwipeTexture("Interface\\AddOns\\RefineUI\\Media\\Textures\\CDBig.blp")
    bar.cooldown:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
    bar.cooldown:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)
end

function DisplayManager:HideUnusedBars(frame, activeCount)
    local bars = frame.bars or {}
    for i = activeCount + 1, #bars do
        local bar = bars[i]
        -- Stop any flashing animation when hiding bars
        if bar.flashAnimation then
            bar.flashAnimation:Stop()
        end
        bar.isFlashing = false -- Reset flashing state
        bar:Hide()
    end
end

-- Tooltip Handler (Single Responsibility)
local TooltipHandler = {}

function TooltipHandler:OnEnter()
    if self.spellID and self.spellID > FILGER_CONSTANTS.TOOLTIP_SPELL_ID_THRESHOLD then
        GameTooltip:ClearLines()
        GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT", 0, 3)
        GameTooltip:SetHyperlink(format("spell:%s", self.spellID))
        GameTooltip:Show()
    end
end

function TooltipHandler:OnLeave()
    GameTooltip:Hide()
end

-- Event Handler (Single Responsibility)
local EventHandler = {}

local EVENT_HANDLERS = {
    ["UNIT_AURA"] = function(frame, unit)
        if unit == "player" or unit == "target" or unit == "pet" or unit == "focus" then
            AuraScanner:ScanUnit(frame, unit)
            MissingBuffManager:UpdateMissingBuffs(frame)
            StacksManager:UpdateStacksTracking(frame)
            DisplayManager:RefreshDisplay(frame)
        end
    end,

    ["SPELL_UPDATE_COOLDOWN"] = function(frame)
        CooldownManager:UpdateCooldowns(frame)
        DisplayManager:RefreshDisplay(frame)
    end,

    ["PLAYER_ENTERING_WORLD"] = function(frame)
        frame.actives = {}
        AuraScanner:ScanUnit(frame, "player")
        if UnitExists("pet") then
            AuraScanner:ScanUnit(frame, "pet")
        end
        CooldownManager:UpdateCooldowns(frame)
        MissingBuffManager:UpdateMissingBuffs(frame)
        StacksManager:UpdateStacksTracking(frame)
        DisplayManager:RefreshDisplay(frame)
    end,

    ["PLAYER_TARGET_CHANGED"] = function(frame)
        AuraScanner:ScanUnit(frame, "target")
        MissingBuffManager:UpdateMissingBuffs(frame)
        StacksManager:UpdateStacksTracking(frame)
        DisplayManager:RefreshDisplay(frame)
    end,

    ["PLAYER_FOCUS_CHANGED"] = function(frame)
        AuraScanner:ScanUnit(frame, "focus")
        MissingBuffManager:UpdateMissingBuffs(frame)
        StacksManager:UpdateStacksTracking(frame)
        DisplayManager:RefreshDisplay(frame)
    end,

    ["PLAYER_REGEN_DISABLED"] = function(frame)
        -- Entered combat - update missing buffs
        MissingBuffManager:UpdateMissingBuffs(frame)
        DisplayManager:RefreshDisplay(frame)
    end,

    ["PLAYER_REGEN_ENABLED"] = function(frame)
        -- Left combat - clear missing buffs
        MissingBuffManager:ClearMissingBuffs(frame)
        DisplayManager:RefreshDisplay(frame)
    end
}

function EventHandler:OnEvent(frame, event, unit, _, castID)
    local handler = EVENT_HANDLERS[event]
    if handler then
        -- Call handler with appropriate arguments based on event type
        if event == "UNIT_SPELLCAST_SUCCEEDED" and castID then
            handler(frame, unit, castID)
        else
            handler(frame, unit)
        end
    end
end

-- Frame Manager (Single Responsibility)
local FrameManager = {}

function FrameManager:SynchronizeFrames()
    local currentFrames = self:IndexCurrentFrames()
    local newFrames = {}

    -- Create/update frames based on spell groups
    for i, groupData in ipairs(FilgerSystem.spellGroups) do
        local frame = self:GetOrCreateFrame(currentFrames, groupData, i)
        table.insert(newFrames, frame)
        self:RegisterFrameEvents(frame, groupData)
    end

    -- Clean up unused frames
    self:CleanupUnusedFrames(currentFrames)

    -- Update global frame table
    self:UpdateGlobalFrameTable(newFrames)
end

function FrameManager:IndexCurrentFrames()
    local currentFrames = {}
    for _, frame in ipairs(FilgerSystem.frames) do
        currentFrames[frame.Name] = frame
    end
    return currentFrames
end

function FrameManager:GetOrCreateFrame(currentFrames, groupData, index)
    local frame = currentFrames[groupData.Name]

    if not frame then
        frame = self:CreateNewFrame(groupData, index)
    else
        frame.Id = index                    -- Update ID in case order changed
        currentFrames[groupData.Name] = nil -- Remove from cleanup list
    end

    return frame
end

function FrameManager:CreateNewFrame(groupData, index)
    local frameSettings = R.Filger.FrameSettings and R.Filger.FrameSettings[groupData.Name] or {}

    local frame = CreateFrame("Frame", "FilgerFrame" .. index .. "_" .. groupData.Name, UIParent)
    frame.Id = index
    frame.Name = groupData.Name
    frame.Direction = groupData.Direction or FILGER_CONSTANTS.DIRECTIONS.DOWN
    frame.IconSide = groupData.IconSide or "LEFT"
    frame.Mode = "ICON"
    frame.Interval = frameSettings.space or C.filger.buffs_space or 3
    frame.IconSize = frameSettings.size or C.filger.buffs_size or 36
    frame.Position = groupData.Position
    frame.actives = {}

    frame:SetAlpha(groupData.Alpha or 1)
    frame:SetPoint(unpack(frame.Position))
    frame:SetScript("OnEvent", function(self, event, unit, _, castID)
        EventHandler:OnEvent(self, event, unit, _, castID)
    end)

    return frame
end

function FrameManager:RegisterFrameEvents(frame, groupData)
    local eventConfig = self:DetermineRequiredEvents(groupData)

    frame:UnregisterAllEvents()
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")

    if eventConfig.aura then frame:RegisterEvent("UNIT_AURA") end
    if eventConfig.cooldown then frame:RegisterEvent("SPELL_UPDATE_COOLDOWN") end
    if eventConfig.cast then frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED") end
    if eventConfig.target then frame:RegisterEvent("PLAYER_TARGET_CHANGED") end
    if eventConfig.focus then frame:RegisterEvent("PLAYER_FOCUS_CHANGED") end
    if eventConfig.missing then
        frame:RegisterEvent("PLAYER_REGEN_DISABLED")
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
end

function FrameManager:DetermineRequiredEvents(groupData)
    local events = { aura = false, cooldown = false, cast = false, target = false, focus = false, missing = false, stacks = false }

    for _, spellData in pairs(groupData.spells) do
        if spellData.filter == FILGER_CONSTANTS.FILTERS.BUFF or
            spellData.filter == FILGER_CONSTANTS.FILTERS.DEBUFF then
            events.aura = true
        end
        if spellData.filter == FILGER_CONSTANTS.FILTERS.CD then
            events.cooldown = true
        end
        if spellData.filter == FILGER_CONSTANTS.FILTERS.MISSING then
            events.missing = true
            events.aura = true -- Also need aura events to detect when buffs change
        end
        if spellData.filter == FILGER_CONSTANTS.FILTERS.STACKS then
            events.stacks = true
            events.aura = true -- Also need aura events to detect when stack counts change
        end
        if spellData.unitID == "target" then
            events.target = true
        end
        if spellData.unitID == "focus" then
            events.focus = true
        end
    end

    return events
end

function FrameManager:CleanupUnusedFrames(currentFrames)
    for _, frame in pairs(currentFrames) do
        frame:Hide()
        frame:UnregisterAllEvents()
    end
end

function FrameManager:UpdateGlobalFrameTable(newFrames)
    wipe(FilgerSystem.frames)
    for _, frame in ipairs(newFrames) do
        tinsert(FilgerSystem.frames, frame)
    end
end

-- Legacy compatibility function (maintains FindAuras global access)
function FindAuras(frame, unit)
    AuraScanner:ScanUnit(frame, unit)
    DisplayManager:RefreshDisplay(frame)
end

-- Public API Implementation
function R.Filger:RefreshTrackedSpells()
    SpellDataManager:RefreshSpellGroups()
    FrameManager:SynchronizeFrames()
end

-- simple coalesce flag for rebuilds
R.Filger._pendingUpdate = false
R.Filger._updateDelaySec = R.Filger._updateDelaySec or 0.05 -- tiny delay to collapse bursts

-- Internal: does the actual rebuild (was UpdateAuras)
function R.Filger:DoUpdateAuras()
    self:RefreshTrackedSpells()

    -- Force update on all frames
    for _, frame in ipairs(FilgerSystem.frames) do
        if self._usePool and frame.actives then
            for _, e in pairs(frame.actives) do
                give(e)
            end
        end
        frame.actives = {}

        if frame:IsEventRegistered("UNIT_AURA") then
            AuraScanner:ScanUnit(frame, "player")
            if UnitExists("target") then AuraScanner:ScanUnit(frame, "target") end
            if UnitExists("pet") then AuraScanner:ScanUnit(frame, "pet") end
            if UnitExists("focus") then AuraScanner:ScanUnit(frame, "focus") end
        end

        if frame:IsEventRegistered("SPELL_UPDATE_COOLDOWN") then
            CooldownManager:UpdateCooldowns(frame)
        end

        DisplayManager:RefreshDisplay(frame)
    end
end

-- Public: coalesced entrypoint; preserves external API
function R.Filger:UpdateAuras()
    if self._pendingUpdate then return end
    self._pendingUpdate = true
    C_Timer.After(self._updateDelaySec, function()
        self._pendingUpdate = false
        -- safety: if anchors are required, ensure initialized before rebuilds
        if AnchorManager and not self.AnchorManagerInitialized then
            AnchorManager:InitializeAnchors()
            self.AnchorManagerInitialized = true
        end
        self:DoUpdateAuras()
    end)
end

function R.Filger:UpdateDisplaySettings(frameName, layoutName, settings)
    for _, frame in ipairs(FilgerSystem.frames) do
        if frame.Name == frameName then
            local changed = false

            -- Ensure FrameSettings exists for this frame
            R.Filger.FrameSettings = R.Filger.FrameSettings or {}
            R.Filger.FrameSettings[frameName] = R.Filger.FrameSettings[frameName] or {}

            if settings.size and frame.IconSize ~= settings.size then
                frame.IconSize = settings.size
                R.Filger.FrameSettings[frameName].size = settings.size
                changed = true
            end

            if settings.space and frame.Interval ~= settings.space then
                frame.Interval = settings.space
                R.Filger.FrameSettings[frameName].space = settings.space

                -- Clear existing bars to force repositioning with new spacing
                if frame.bars then
                    for _, bar in ipairs(frame.bars) do
                        bar:ClearAllPoints()
                    end
                end

                changed = true
            end

            if settings.alpha and frame:GetAlpha() ~= settings.alpha then
                frame:SetAlpha(settings.alpha)
            end

            if changed then
                DisplayManager:RefreshDisplay(frame)
            end

            break
        end
    end
end

-- Initialize the system
AnchorManager:InitializeAnchors()
R.Filger:RefreshTrackedSpells()

-- Expose for backwards compatibility
_G.FilgerFrames = FilgerSystem.frames
_G.SpellGroups = FilgerSystem.spellGroups
_G.FindAuras = FindAuras
