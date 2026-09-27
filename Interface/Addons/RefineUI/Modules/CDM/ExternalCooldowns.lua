----------------------------------------------------------------------------------------
-- CDM Component: ExternalCooldowns
-- Description: Trinket, racial ability, and consumable discovery and cooldown payloads.
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
local tostring = tostring
local pcall = pcall
local sort = table.sort
local wipe = _G.wipe or table.wipe

local UnitRace = UnitRace
local GetInventoryItemID = GetInventoryItemID
local GetInventoryItemCooldown = GetInventoryItemCooldown
local C_Container = C_Container
local C_Item = C_Item
local C_Spell = C_Spell
local C_SpellBook = C_SpellBook
local issecretvalue = _G.issecretvalue

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local RACIAL_ID_OFFSET = 1000000000
local TRINKET_ID_OFFSET = 1100000000
local CONSUMABLE_ID_OFFSET = 1200000000
local EXTERNAL_ID_LIMIT = 1300000000
local TRINKET_SLOTS = { 13, 14 }
local MAX_BAG_INDEX = _G.NUM_TOTAL_EQUIPPED_BAG_SLOTS or 5
local CONSUMABLE_CLASS_ID = Enum and Enum.ItemClass and Enum.ItemClass.Consumable or 0
local CONSUMABLE_SUBCLASS = Enum and Enum.ItemConsumableSubclass
local COMBAT_CONSUMABLE_SUBCLASSES = {
    [(CONSUMABLE_SUBCLASS and CONSUMABLE_SUBCLASS.Generic) or 0] = true,
    [(CONSUMABLE_SUBCLASS and CONSUMABLE_SUBCLASS.Potion) or 1] = true,
    [(CONSUMABLE_SUBCLASS and CONSUMABLE_SUBCLASS.Elixir) or 2] = true,
    [(CONSUMABLE_SUBCLASS and CONSUMABLE_SUBCLASS.Flasksphials) or 3] = true,
    [(CONSUMABLE_SUBCLASS and CONSUMABLE_SUBCLASS.Fooddrink) or 5] = true,
    [(CONSUMABLE_SUBCLASS and CONSUMABLE_SUBCLASS.Itemenhancement) or 6] = true,
    [(CONSUMABLE_SUBCLASS and CONSUMABLE_SUBCLASS.Bandage) or 7] = true,
    [(CONSUMABLE_SUBCLASS and CONSUMABLE_SUBCLASS.VantusRune) or 9] = true,
    [(CONSUMABLE_SUBCLASS and CONSUMABLE_SUBCLASS.CombatCurio) or 11] = true,
}
local PLAYER_SPELL_BANK = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player

-- Candidate spell IDs are resolved against the player's spellbook. Variant IDs are
-- intentionally retained because several racials use class-specific spell records.
local RACIAL_SPELLS = {
    Human = { 59752 },
    Dwarf = { 20594 },
    NightElf = { 58984 },
    Gnome = { 20589 },
    Draenei = { 28880 },
    Worgen = { 68992 },
    Orc = { 20572, 33697, 33702 },
    Scourge = { 7744 },
    Tauren = { 20549 },
    Troll = { 26297 },
    BloodElf = { 28730, 50613, 80483, 129597, 155145, 202719, 232633 },
    Goblin = { 69070 },
    Pandaren = { 107079 },
    VoidElf = { 256948 },
    LightforgedDraenei = { 255647 },
    DarkIronDwarf = { 265221 },
    KulTiran = { 287712 },
    Mechagnome = { 312924 },
    Nightborne = { 260364 },
    HighmountainTauren = { 255654 },
    MagharOrc = { 274738 },
    ZandalariTroll = { 291944 },
    Vulpera = { 312411 },
    Dracthyr = { 357214, 368970 },
    EarthenDwarf = { 436343 },
}

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
local externalInfoByID = {}
local categoryIDs = {
    [CDM.EXTERNAL_CATEGORY_KEYS.TRINKETS] = {},
    [CDM.EXTERNAL_CATEGORY_KEYS.RACIALS] = {},
    [CDM.EXTERNAL_CATEGORY_KEYS.CONSUMABLES] = {},
}
local allExternalIDs = {}
local cooldownPayloadByID = {}

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function ClearTable(tbl)
    if wipe then
        wipe(tbl)
        return
    end
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local function GetItemName(itemID)
    if C_Item and type(C_Item.GetItemNameByID) == "function" then
        local name = C_Item.GetItemNameByID(itemID)
        if not IsSecret(name) and type(name) == "string" and name ~= "" then
            return name
        end
    end
    return tostring(itemID)
end

local function GetItemIcon(itemID)
    if C_Item and type(C_Item.GetItemIconByID) == "function" then
        local icon = C_Item.GetItemIconByID(itemID)
        if not IsSecret(icon) and icon then
            return icon
        end
    end
    if C_Item and type(C_Item.GetItemInfoInstant) == "function" then
        local _, _, _, _, icon = C_Item.GetItemInfoInstant(itemID)
        if not IsSecret(icon) and icon then
            return icon
        end
    end
    return 134400
end

local function GetItemSpellID(itemID)
    if not C_Item or type(C_Item.GetItemSpell) ~= "function" then
        return nil
    end
    local _, spellID = C_Item.GetItemSpell(itemID)
    if not IsSecret(spellID) and type(spellID) == "number" and spellID > 0 then
        return spellID
    end
    return nil
end

local function IsKnownRacialSpell(spellID)
    if not C_SpellBook then
        return false
    end

    if type(C_SpellBook.FindSpellBookSlotForSpell) == "function" then
        local ok, slotIndex = pcall(
            C_SpellBook.FindSpellBookSlotForSpell,
            spellID,
            true,
            true,
            false,
            false
        )
        if ok and type(slotIndex) == "number" then
            return true
        end
    end

    if type(C_SpellBook.IsSpellKnownOrInSpellBook) == "function" then
        local ok, known = pcall(C_SpellBook.IsSpellKnownOrInSpellBook, spellID, PLAYER_SPELL_BANK, true)
        return ok and known == true
    end

    return false
end

local function AddExternalInfo(categoryKey, cooldownID, info)
    info.cooldownID = cooldownID
    info.externalCategory = categoryKey
    externalInfoByID[cooldownID] = info
    categoryIDs[categoryKey][#categoryIDs[categoryKey] + 1] = cooldownID
    allExternalIDs[#allExternalIDs + 1] = cooldownID
end

local function ScanTrinkets()
    if not GetInventoryItemID or not C_Item then
        return
    end

    for i = 1, #TRINKET_SLOTS do
        local slot = TRINKET_SLOTS[i]
        local itemID = GetInventoryItemID("player", slot)
        if type(itemID) == "number" and itemID > 0 and GetItemSpellID(itemID) then
            AddExternalInfo(CDM.EXTERNAL_CATEGORY_KEYS.TRINKETS, TRINKET_ID_OFFSET + slot, {
                externalType = "trinket",
                inventorySlot = slot,
                itemID = itemID,
                name = GetItemName(itemID),
                icon = GetItemIcon(itemID),
            })
        end
    end
end

local function ScanRacials()
    if not UnitRace or not C_Spell then
        return
    end

    local _, raceKey = UnitRace("player")
    if IsSecret(raceKey) or type(raceKey) ~= "string" then
        return
    end

    local candidates = RACIAL_SPELLS[raceKey]
    if type(candidates) ~= "table" then
        return
    end

    local seen = {}
    for i = 1, #candidates do
        local spellID = candidates[i]
        if type(C_Spell.GetOverrideSpell) == "function" then
            local overrideSpellID = C_Spell.GetOverrideSpell(spellID)
            if not IsSecret(overrideSpellID)
                and type(overrideSpellID) == "number"
                and overrideSpellID > 0
            then
                spellID = overrideSpellID
            end
        end

        if not seen[spellID] and IsKnownRacialSpell(spellID) then
            local spellInfo = type(C_Spell.GetSpellInfo) == "function" and C_Spell.GetSpellInfo(spellID) or nil
            if type(spellInfo) == "table"
                and not IsSecret(spellInfo.name)
                and type(spellInfo.name) == "string"
            then
                seen[spellID] = true
                AddExternalInfo(CDM.EXTERNAL_CATEGORY_KEYS.RACIALS, RACIAL_ID_OFFSET + spellID, {
                    externalType = "racial",
                    spellID = spellID,
                    name = spellInfo.name,
                    icon = spellInfo.iconID or 134400,
                })
            end
        end
    end
end

-- Item class and use spell never change, so each item ID is classified once:
-- false = not a combat consumable, table = { spellID, icon }.
local consumableClassByItemID = {}

local function GetConsumableClass(itemID)
    local cached = consumableClassByItemID[itemID]
    if cached ~= nil then
        return cached
    end

    local _, _, _, _, icon, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    if classID ~= CONSUMABLE_CLASS_ID or not COMBAT_CONSUMABLE_SUBCLASSES[subClassID] then
        consumableClassByItemID[itemID] = false
        return false
    end

    -- Not cached when the use spell is missing: item data may not be loaded yet.
    local spellID = GetItemSpellID(itemID)
    if not spellID then
        return false
    end

    cached = { spellID = spellID, icon = icon }
    consumableClassByItemID[itemID] = cached
    return cached
end

local function ScanConsumables()
    if not C_Container or not C_Item
        or type(C_Container.GetContainerNumSlots) ~= "function"
        or type(C_Container.GetContainerItemID) ~= "function"
        or type(C_Item.GetItemInfoInstant) ~= "function"
    then
        return
    end

    local seen = {}
    for bag = 0, MAX_BAG_INDEX do
        local slotCount = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slotCount do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if type(itemID) == "number" and itemID > 0 and not seen[itemID] then
                seen[itemID] = true
                local consumable = GetConsumableClass(itemID)
                if consumable then
                    AddExternalInfo(CDM.EXTERNAL_CATEGORY_KEYS.CONSUMABLES, CONSUMABLE_ID_OFFSET + itemID, {
                        externalType = "consumable",
                        itemID = itemID,
                        spellID = consumable.spellID,
                        name = GetItemName(itemID),
                        icon = consumable.icon or GetItemIcon(itemID),
                    })
                end
            end
        end
    end

    sort(categoryIDs[CDM.EXTERNAL_CATEGORY_KEYS.CONSUMABLES], function(leftID, rightID)
        local left = externalInfoByID[leftID]
        local right = externalInfoByID[rightID]
        return (left and left.name or "") < (right and right.name or "")
    end)
end

local function GetSpellCooldownDuration(spellID)
    if not C_Spell or type(C_Spell.GetSpellCooldownDuration) ~= "function" then
        return nil
    end

    local ok, duration = pcall(C_Spell.GetSpellCooldownDuration, spellID, true)
    if not ok then
        ok, duration = pcall(C_Spell.GetSpellCooldownDuration, spellID)
    end
    if ok then
        return duration
    end
    return nil
end

local function GetItemCooldown(itemID)
    if not C_Item or type(C_Item.GetItemCooldown) ~= "function" then
        return nil, nil
    end
    local ok, startTime, duration = pcall(C_Item.GetItemCooldown, itemID)
    if ok then
        return startTime, duration
    end
    return nil, nil
end

local function RemoveGlobalCooldown(startTime, duration)
    if not IsSecret(duration) and type(duration) == "number" and duration <= 1.5 then
        return 0, 0
    end
    return startTime, duration
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function CDM:IsExternalCooldownID(cooldownID)
    if type(cooldownID) ~= "number" then
        return false
    end
    if cooldownID >= RACIAL_ID_OFFSET and cooldownID < TRINKET_ID_OFFSET then
        return true
    end
    if cooldownID == TRINKET_ID_OFFSET + TRINKET_SLOTS[1]
        or cooldownID == TRINKET_ID_OFFSET + TRINKET_SLOTS[2]
    then
        return true
    end
    return cooldownID >= CONSUMABLE_ID_OFFSET and cooldownID < EXTERNAL_ID_LIMIT
end

function CDM:IsExternalSourceCategory(categoryKey)
    return categoryKey == self.EXTERNAL_CATEGORY_KEYS.TRINKETS
        or categoryKey == self.EXTERNAL_CATEGORY_KEYS.RACIALS
        or categoryKey == self.EXTERNAL_CATEGORY_KEYS.CONSUMABLES
end

function CDM:ScanExternalCooldowns()
    ClearTable(externalInfoByID)
    ClearTable(allExternalIDs)
    ClearTable(categoryIDs[self.EXTERNAL_CATEGORY_KEYS.TRINKETS])
    ClearTable(categoryIDs[self.EXTERNAL_CATEGORY_KEYS.RACIALS])
    ClearTable(categoryIDs[self.EXTERNAL_CATEGORY_KEYS.CONSUMABLES])

    ScanTrinkets()
    ScanRacials()
    ScanConsumables()

    if self.InvalidateCooldownDisplayNameCache then
        self:InvalidateCooldownDisplayNameCache()
    end
    if self.MarkAssignedCooldownSnapshotDirty then
        self:MarkAssignedCooldownSnapshotDirty()
    end
end

function CDM:GetCooldownInfo(cooldownID)
    if self:IsExternalCooldownID(cooldownID) then
        return externalInfoByID[cooldownID]
    end
    return self.GetCooldownCatalogInfo and self:GetCooldownCatalogInfo(cooldownID) or nil
end

function CDM:GetValidExternalCooldownIDs()
    return allExternalIDs
end

function CDM:GetUnassignedExternalCooldownIDs(categoryKey, assignments, assigned)
    local source = categoryIDs[categoryKey]
    if type(source) ~= "table" then
        return {}
    end

    assigned = assigned or self:GetAssignedIDSet(assignments)
    local result = {}
    for i = 1, #source do
        local cooldownID = source[i]
        if not assigned[cooldownID] then
            result[#result + 1] = cooldownID
        end
    end
    return result
end

function CDM:GetExternalCooldownIcon(cooldownID)
    local info = externalInfoByID[cooldownID]
    return info and info.icon or nil
end

function CDM:SetExternalCooldownTooltip(tooltip, cooldownID)
    local info = externalInfoByID[cooldownID]
    if not tooltip or not info then
        return false
    end

    if info.externalType == "trinket" and type(tooltip.SetInventoryItem) == "function" then
        tooltip:SetInventoryItem("player", info.inventorySlot)
        return true
    end
    if info.itemID and type(tooltip.SetItemByID) == "function" then
        tooltip:SetItemByID(info.itemID)
        return true
    end
    if info.itemID and type(tooltip.SetHyperlink) == "function" then
        tooltip:SetHyperlink("item:" .. tostring(info.itemID))
        return true
    end
    if info.spellID and type(tooltip.SetSpellByID) == "function" then
        tooltip:SetSpellByID(info.spellID, false)
        return true
    end
    return false
end

function CDM:GetExternalCooldownPayload(cooldownID)
    local info = externalInfoByID[cooldownID]
    if not info then
        return nil
    end

    local payload = cooldownPayloadByID[cooldownID]
    if not payload then
        payload = { cooldownID = cooldownID }
        cooldownPayloadByID[cooldownID] = payload
    end
    payload.icon = info.icon
    payload.duration = nil
    payload.cooldownStartTime = nil
    payload.cooldownDuration = nil
    payload.cooldownModRate = nil

    if info.externalType == "racial" then
        payload.duration = GetSpellCooldownDuration(info.spellID)
    elseif info.externalType == "trinket" and GetInventoryItemCooldown then
        local ok, startTime, duration = pcall(GetInventoryItemCooldown, "player", info.inventorySlot)
        if ok then
            startTime, duration = RemoveGlobalCooldown(startTime, duration)
            payload.cooldownStartTime = startTime
            payload.cooldownDuration = duration
            payload.cooldownModRate = 1
        end
    elseif info.itemID then
        local startTime, duration = GetItemCooldown(info.itemID)
        startTime, duration = RemoveGlobalCooldown(startTime, duration)
        payload.cooldownStartTime = startTime
        payload.cooldownDuration = duration
        payload.cooldownModRate = 1
    end

    return payload
end
