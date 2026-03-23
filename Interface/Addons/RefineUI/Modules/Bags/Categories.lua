----------------------------------------------------------------------------------------
-- Bags Component: Categories
-- Description: Managing item category assignments and definitions.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Bags = RefineUI:GetModule("Bags")
if not Bags then return end

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
local type = type
local tostring = tostring
local tonumber = tonumber
local pairs = pairs
local ipairs = ipairs
local math = math
local string = string
local table = table
local tinsert = table.insert
local tremove = table.remove
local pcall = pcall
local bitband = bit and bit.band
local GetItemInfo = GetItemInfo
local GetCursorInfo = GetCursorInfo

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------

Bags.CATEGORY_ORDER = {
    "Recent",
    "Junk",
    "BoE/WuE",
    "Warbound",
    "Equipment Sets",
    "Crafting",
    "Consumable",
    "Weapon",
    "Armor",
    "Gem",
    "Projectile",
    "Quest",
    "Miscellaneous",
    "Container",
    "Glyph",
    "Collections",
}

Bags.CATEGORY_SCHEMA_VERSION = 7
Bags.BINNED_BLOCK_TOKEN = "__BAGS_BINNED_BLOCK__"
Bags.CUSTOM_CATEGORY_KEY_PREFIX = "__BAGS_CUSTOM__"
Bags.CUSTOM_CATEGORY_NAME_MAX_LENGTH = 15

local BACKPACK_BAG_ID = BACKPACK_CONTAINER or 0
local NORMAL_BAG_LAST_ID = NUM_BAG_SLOTS or 4
local REAGENT_BAG_ID = REAGENTBAG_CONTAINER or ((Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or 5)
local PLAYER_BAG_LAST_ID = math.max(NORMAL_BAG_LAST_ID, REAGENT_BAG_ID)

Bags.DEFAULT_PINNED_TOP_CATEGORIES = {
    Recent = true,
}

Bags.DEFAULT_PINNED_BOTTOM_CATEGORIES = {
    Junk = true,
}

local ITEM_BIND_BOE = 2
local ITEM_BIND_WUE = 9

local ITEM_CLASS_PROFESSION = (Enum and Enum.ItemClass and Enum.ItemClass.Profession) or 19
local ITEM_CLASS_HOUSING = (Enum and Enum.ItemClass and Enum.ItemClass.Housing) or 20
local ITEM_CLASS_BATTLEPET = (Enum and Enum.ItemClass and Enum.ItemClass.Battlepet) or 17
local ITEM_CLASS_MISCELLANEOUS = (Enum and Enum.ItemClass and Enum.ItemClass.Miscellaneous) or 15
local ITEM_CLASS_REAGENT = (Enum and Enum.ItemClass and Enum.ItemClass.Reagent) or 5
local ITEM_CLASS_TRADE_GOODS = (Enum and Enum.ItemClass and (Enum.ItemClass.Tradegoods or Enum.ItemClass.TradeGoods)) or 7
local ITEM_CLASS_ITEM_ENHANCEMENT = (Enum and Enum.ItemClass and Enum.ItemClass.ItemEnhancement) or 8
local ITEM_CLASS_RECIPE = (Enum and Enum.ItemClass and Enum.ItemClass.Recipe) or 9
local ITEM_MISC_SUBCLASS_COMPANION_PET = (Enum and Enum.ItemMiscellaneousSubclass and Enum.ItemMiscellaneousSubclass.CompanionPet) or 2
local ITEM_MISC_SUBCLASS_REAGENT = (Enum and Enum.ItemMiscellaneousSubclass and Enum.ItemMiscellaneousSubclass.Reagent) or 1
local ITEM_MISC_SUBCLASS_MOUNT = (Enum and Enum.ItemMiscellaneousSubclass and Enum.ItemMiscellaneousSubclass.Mount) or 5
local ITEM_MISC_SUBCLASS_MOUNT_EQUIPMENT = (Enum and Enum.ItemMiscellaneousSubclass and Enum.ItemMiscellaneousSubclass.MountEquipment) or 6

local LEGACY_CATEGORY_KEY_MAP = {
    ["Battle Pets"] = "Collections",
    ["Profession"] = "Crafting",
    ["Reagent"] = "Crafting",
    ["Trade Goods"] = "Crafting",
    ["Item Enhancement"] = "Crafting",
    ["Recipe"] = "Crafting",
    ["Other"] = "Miscellaneous",
}

local EQUIP_LOC_NAMES = {
    INVTYPE_HEAD = "Head",
    INVTYPE_NECK = "Neck",
    INVTYPE_SHOULDER = "Shoulder",
    INVTYPE_BODY = "Shirt",
    INVTYPE_CHEST = "Chest",
    INVTYPE_ROBE = "Chest",
    INVTYPE_WAIST = "Waist",
    INVTYPE_LEGS = "Legs",
    INVTYPE_FEET = "Feet",
    INVTYPE_WRIST = "Wrist",
    INVTYPE_HAND = "Hands",
    INVTYPE_FINGER = "Finger",
    INVTYPE_TRINKET = "Trinket",
    INVTYPE_CLOAK = "Back",
    INVTYPE_WEAPON = "One-Hand",
    INVTYPE_SHIELD = "Shield",
    INVTYPE_2HWEAPON = "Two-Hand",
    INVTYPE_WEAPONMAINHAND = "Main Hand",
    INVTYPE_WEAPONOFFHAND = "Off Hand",
    INVTYPE_HOLDABLE = "Held In Off-hand",
    INVTYPE_RANGED = "Ranged",
    INVTYPE_THROWN = "Thrown",
    INVTYPE_RANGEDRIGHT = "Ranged",
    INVTYPE_RELIC = "Relic",
    INVTYPE_TABARD = "Tabard",
    INVTYPE_BAG = "Bag",
    INVTYPE_QUIVER = "Quiver",
}

local SLOT_SUBCATEGORIES = {
    ["Armor"] = true,
    ["Weapon"] = true,
}

----------------------------------------------------------------------------------------
-- Item Metadata
----------------------------------------------------------------------------------------

Bags._itemInfoCache = Bags._itemInfoCache or {}
Bags._itemMetadataPending = Bags._itemMetadataPending or {}

local function GetCachedItemMetadata(itemID, itemLink)
    if type(itemID) ~= "number" or itemID <= 0 then
        return nil
    end

    local meta = Bags._itemInfoCache[itemID]
    if not meta then
        meta = {}
        Bags._itemInfoCache[itemID] = meta
    end

    if not meta.loaded then
        if C_Item and C_Item.GetItemInfoInstant then
            local _, itemType, itemSubType, itemEquipLoc, _, itemClassID, itemSubClassID = C_Item.GetItemInfoInstant(itemLink or itemID)
            meta.itemType = meta.itemType or itemType
            meta.itemSubType = meta.itemSubType or itemSubType
            meta.itemEquipLoc = meta.itemEquipLoc or itemEquipLoc
            meta.itemClassID = meta.itemClassID or itemClassID
            meta.itemSubClassID = meta.itemSubClassID or itemSubClassID
        end

        local name, _, quality, _, _, itemType, itemSubType, stackCount, itemEquipLoc, _, _, itemClassID, itemSubClassID, bindType = GetItemInfo(itemLink or itemID)
        if not name then
            meta.loaded = false
            meta.pending = true
            Bags._itemMetadataPending[itemID] = true
            if Bags.QueueItemMetadataPrefetch then
                Bags.QueueItemMetadataPrefetch(itemID)
            end
            return meta
        end

        meta.name = name
        meta.nameLower = string.lower(name)
        meta.quality = quality
        meta.itemType = itemType or meta.itemType
        meta.itemSubType = itemSubType or meta.itemSubType
        meta.stackCount = stackCount or 1
        meta.itemEquipLoc = itemEquipLoc or meta.itemEquipLoc
        meta.itemClassID = itemClassID or meta.itemClassID
        meta.itemSubClassID = itemSubClassID or meta.itemSubClassID
        meta.bindType = bindType
        meta.loaded = true
        meta.pending = nil
        Bags._itemMetadataPending[itemID] = nil
    elseif not meta.nameLower and meta.name then
        meta.nameLower = string.lower(meta.name)
    end

    return meta
end

function Bags.GetItemMetadata(itemID, itemLink)
    local meta = GetCachedItemMetadata(itemID, itemLink)
    if meta and meta.loaded then
        return meta
    end
    return nil
end

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------

local function TrimText(text)
    if type(text) ~= "string" then
        return ""
    end
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

local function NormalizeCustomCategoryName(name)
    local cleaned = TrimText(name)
    cleaned = string.gsub(cleaned, "%s+", " ")
    return cleaned
end

local function BuildLabelLookup(defsByKey)
    local labels = {}
    for _, def in pairs(defsByKey) do
        if def and def.label then
            labels[string.lower(def.label)] = def.key
        end
    end
    return labels
end

local function UnpackEquipmentSetLocation(location)
    if not location or location == 0 or location == -1 then
        return nil
    end

    if _G.EquipmentManager_GetLocationData then
        local ok, locationData = pcall(_G.EquipmentManager_GetLocationData, location)
        if ok and type(locationData) == "table" then
            local isPlayer = locationData.player
            local isBank = (locationData.bank ~= nil and locationData.bank) or locationData.isBank
            local isBags = (locationData.bags ~= nil and locationData.bags) or locationData.isBags
            local isVoid = (locationData.voidStorage ~= nil and locationData.voidStorage) or locationData.isVoidStorage
            return isPlayer, isBank, isBags, isVoid, locationData.slot, locationData.bag
        end
    end

    local unpackLocation = (C_EquipmentSet and C_EquipmentSet.UnpackLocation) or _G.EquipmentManager_UnpackLocation
    if unpackLocation then
        local ok, player, bank, bags, voidStorage, slot, bag = pcall(unpackLocation, location)
        if ok then
            return player, bank, bags, voidStorage, slot, bag
        end
    end

    return nil
end

function Bags.RebuildEquipmentSetLookup()
    local lookup = {
        byBagSlot = {},
    }

    if not C_EquipmentSet or not C_EquipmentSet.GetEquipmentSetIDs then
        Bags._equipmentSetLookup = lookup
        return lookup
    end

    local setIDs = C_EquipmentSet.GetEquipmentSetIDs() or {}
    for _, setID in ipairs(setIDs) do
        local setName = C_EquipmentSet.GetEquipmentSetInfo(setID)
        if setName and setName ~= "" then
            if C_EquipmentSet.GetItemLocations then
                local locations = C_EquipmentSet.GetItemLocations(setID) or {}
                for _, location in pairs(locations) do
                    local _, _, isBags, _, slotIndex, bagID = UnpackEquipmentSetLocation(location)
                    if isBags and bagID and slotIndex then
                        lookup.byBagSlot[bagID] = lookup.byBagSlot[bagID] or {}
                        if not lookup.byBagSlot[bagID][slotIndex] then
                            lookup.byBagSlot[bagID][slotIndex] = setName
                        end
                    end
                end
            end
        end
    end

    Bags._equipmentSetLookup = lookup
    return lookup
end

function Bags.GetEquipmentSetNameForItem(bagID, slotIndex, _)
    local lookup = Bags._equipmentSetLookup or Bags.RebuildEquipmentSetLookup()
    if not lookup then
        return nil
    end

    local bySlot = lookup.byBagSlot[bagID]
    if bySlot and bySlot[slotIndex] then
        return bySlot[slotIndex]
    end

    return nil
end

----------------------------------------------------------------------------------------
-- Category Logic
----------------------------------------------------------------------------------------

local function IsWarboundBoundItem(itemLocation, isItemBound)
    if not isItemBound or not itemLocation then
        return false
    end
    if not C_Bank or not C_Bank.IsItemAllowedInBankType or not Enum.BankType.Account then
        return false
    end
    return C_Bank.IsItemAllowedInBankType(Enum.BankType.Account, itemLocation) and true or false
end

local function IsToyItem(itemID)
    if type(itemID) ~= "number" or itemID <= 0 then
        return false
    end

    if C_ToyBox and C_ToyBox.GetToyInfo then
        local ok, toyItemID = pcall(C_ToyBox.GetToyInfo, itemID)
        if ok and toyItemID then
            return true
        end
    end

    if PlayerHasToy then
        local ok, hasToy = pcall(PlayerHasToy, itemID)
        if ok and hasToy then
            return true
        end
    end

    return false
end

local function IsMountEquipmentItem(itemLocation)
    if not itemLocation or not C_MountJournal or not C_MountJournal.IsItemMountEquipment then
        return false
    end

    local ok, isMountEquipment = pcall(C_MountJournal.IsItemMountEquipment, itemLocation)
    return ok and isMountEquipment and true or false
end

local function IsHousingItem(itemID, itemLink, itemClassID)
    if itemClassID == ITEM_CLASS_HOUSING then
        return true
    end

    if C_Item and C_Item.IsDecorItem then
        local ok, isDecor = pcall(C_Item.IsDecorItem, itemLink or itemID)
        if ok and isDecor then
            return true
        end
    end

    return false
end

local function ResolveSpecialCategory(itemID, itemLink, itemLocation, itemClassID, itemSubClassID)
    if itemClassID == ITEM_CLASS_PROFESSION
        or itemClassID == ITEM_CLASS_REAGENT
        or itemClassID == ITEM_CLASS_TRADE_GOODS
        or itemClassID == ITEM_CLASS_ITEM_ENHANCEMENT
        or itemClassID == ITEM_CLASS_RECIPE
        or (itemClassID == ITEM_CLASS_MISCELLANEOUS and itemSubClassID == ITEM_MISC_SUBCLASS_REAGENT)
    then
        return "Crafting", nil
    end

    if itemClassID == ITEM_CLASS_BATTLEPET
        or (itemClassID == ITEM_CLASS_MISCELLANEOUS and itemSubClassID == ITEM_MISC_SUBCLASS_COMPANION_PET)
    then
        return "Collections", nil
    end

    if itemClassID == ITEM_CLASS_MISCELLANEOUS and itemSubClassID == ITEM_MISC_SUBCLASS_MOUNT_EQUIPMENT then
        return "Collections", nil
    end

    if IsMountEquipmentItem(itemLocation) then
        return "Collections", nil
    end

    if itemClassID == ITEM_CLASS_MISCELLANEOUS and itemSubClassID == ITEM_MISC_SUBCLASS_MOUNT then
        return "Collections", nil
    end

    if IsToyItem(itemID) then
        return "Collections", nil
    end

    if IsHousingItem(itemID, itemLink, itemClassID) then
        return "Collections", nil
    end

    if itemClassID == ITEM_CLASS_MISCELLANEOUS then
        return "Miscellaneous", nil
    end

    return nil, nil
end

function Bags.GetItemCategory(bagID, slotIndex, info)
    info = info or (C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bagID, slotIndex))
    if not info or not info.itemID then
        return nil, nil
    end

    local assignedCustomCategory = Bags.GetAssignedCustomCategoryForItem and Bags.GetAssignedCustomCategoryForItem(info.itemID)
    if assignedCustomCategory then
        return assignedCustomCategory, nil
    end

    local setName = Bags.GetEquipmentSetNameForItem and Bags.GetEquipmentSetNameForItem(bagID, slotIndex, info.itemID)
    if setName then
        return "Equipment Sets", setName
    end

    local itemMeta = GetCachedItemMetadata(info.itemID, info.hyperlink)
    local quality = itemMeta and itemMeta.quality
    local itemType = itemMeta and itemMeta.itemType
    local itemSubType = itemMeta and itemMeta.itemSubType
    local itemEquipLoc = itemMeta and itemMeta.itemEquipLoc
    local itemClassID = itemMeta and itemMeta.itemClassID
    local itemSubClassID = itemMeta and itemMeta.itemSubClassID
    local bindType = itemMeta and itemMeta.bindType
    local itemLocation = nil

    local function ResolveItemLocation()
        if itemLocation ~= nil then
            return itemLocation
        end
        if ItemLocation and ItemLocation.CreateFromBagAndSlot then
            itemLocation = ItemLocation:CreateFromBagAndSlot(bagID, slotIndex)
        else
            itemLocation = false
        end
        return itemLocation or nil
    end

    if quality == 0 then
        return "Junk", nil
    end

    local isItemBound = info.isBound and true or false
    if not isItemBound and C_Item and C_Item.IsBound then
        local location = ResolveItemLocation()
        if location then
            isItemBound = C_Item.IsBound(location) and true or false
        end
    end

    local isWUE = false
    if not isItemBound and C_Item and C_Item.IsBoundToAccountUntilEquip then
        local location = ResolveItemLocation()
        if location then
            isWUE = C_Item.IsBoundToAccountUntilEquip(location) and true or false
        end
    end
    if isWUE or ((bindType == ITEM_BIND_BOE or bindType == ITEM_BIND_WUE) and not isItemBound) then
        return "BoE/WuE", nil
    end

    if IsWarboundBoundItem(ResolveItemLocation(), isItemBound) then
        return "Warbound", nil
    end

    local specialCategoryKey, specialSubCategoryKey = ResolveSpecialCategory(info.itemID, info.hyperlink, ResolveItemLocation(), itemClassID, itemSubClassID)
    if specialCategoryKey then
        return specialCategoryKey, specialSubCategoryKey
    end

    if not itemType or itemType == "" or itemType == "Other" then
        return "Miscellaneous", nil
    end

    if SLOT_SUBCATEGORIES[itemType] and itemEquipLoc and itemEquipLoc ~= "" then
        local slotName = EQUIP_LOC_NAMES[itemEquipLoc] or itemSubType or "Other"
        return itemType, slotName
    end

    return itemType, nil
end

function Bags.MatchesSearch(itemID)
    local searchText = Bags.searchText or ""
    if searchText == "" then
        return true
    end
    if type(itemID) ~= "number" or itemID <= 0 then
        return false
    end

    local itemMeta = GetCachedItemMetadata(itemID, itemID)
    local cachedName = itemMeta and itemMeta.nameLower
    if cachedName and cachedName:find(searchText, 1, true) then
        return true
    end

    if itemMeta and itemMeta.loaded and itemMeta.nameLower then
        return itemMeta.nameLower:find(searchText, 1, true) ~= nil
    end

    if Bags.QueueItemMetadataPrefetch then
        Bags.QueueItemMetadataPrefetch(itemID)
    end

    return false
end

----------------------------------------------------------------------------------------
-- Custom Categories
----------------------------------------------------------------------------------------

local function BuildCategoryDefinitions()
    local definitionsByKey = {}
    for _, key in ipairs(Bags.CATEGORY_ORDER) do
        definitionsByKey[key] = {
            key = key,
            label = key,
            defaultEnabled = true,
            isCustom = false,
        }
    end

    local cfg = Bags.GetConfig and Bags.GetConfig()
    local customCategories = cfg and cfg.CustomCategories or nil
    if type(customCategories) == "table" then
        for key, label in pairs(customCategories) do
            if type(key) == "string" and key:find(Bags.CUSTOM_CATEGORY_KEY_PREFIX, 1, true) == 1 then
                local cleanLabel = NormalizeCustomCategoryName(label)
                if cleanLabel ~= "" then
                    definitionsByKey[key] = {
                        key = key,
                        label = cleanLabel,
                        defaultEnabled = true,
                        isCustom = true,
                    }
                end
            end
        end
    end

    return definitionsByKey
end

local function BuildCategoryIndexMap(order)
    local index = {}
    for i, key in ipairs(order) do
        index[key] = i
    end
    return index
end

local function NormalizeLegacyCategoryKey(key)
    if type(key) ~= "string" then
        return key
    end
    return LEGACY_CATEGORY_KEY_MAP[key] or key
end

local function IsKnownCategory(defsByKey, key)
    return type(key) == "string" and defsByKey[key] ~= nil
end

function Bags.IsCustomCategoryKey(key)
    return type(key) == "string" and key:find(Bags.CUSTOM_CATEGORY_KEY_PREFIX, 1, true) == 1
end

function Bags.GetCategoryLabel(categoryKey)
    local defsByKey = BuildCategoryDefinitions()
    local def = defsByKey[categoryKey]
    return (def and def.label) or categoryKey
end

function Bags.GetCustomCategoryName(categoryKey)
    if not Bags.IsCustomCategoryKey(categoryKey) then
        return nil
    end
    local cfg = Bags.GetConfig and Bags.GetConfig()
    local label = cfg and cfg.CustomCategories and cfg.CustomCategories[categoryKey]
    label = NormalizeCustomCategoryName(label)
    return label ~= "" and label or nil
end

function Bags.IsValidCustomCategoryName(name, existingKey)
    local cleanName = NormalizeCustomCategoryName(name)
    if cleanName == "" then
        return false, nil, "Name must include at least one character."
    end
    if #cleanName > (Bags.CUSTOM_CATEGORY_NAME_MAX_LENGTH or 15) then
        return false, nil, "Name must be 15 characters or fewer."
    end
    if not cleanName:match("[%w]") then
        return false, nil, "Name must include at least one letter or number."
    end
    if not cleanName:match("^[%w ]+$") then
        return false, nil, "Name can only contain letters, numbers, and spaces."
    end

    local defsByKey = BuildCategoryDefinitions()
    local labels = BuildLabelLookup(defsByKey)
    local existingForLabel = labels[string.lower(cleanName)]
    if existingForLabel and existingForLabel ~= existingKey then
        return false, nil, "A category with that name already exists."
    end

    return true, cleanName, nil
end

local function GenerateCustomCategoryKey()
    local cfg = Bags.GetConfig and Bags.GetConfig()
    local customCategories = cfg and cfg.CustomCategories or {}
    for _ = 1, 64 do
        local key = Bags.CUSTOM_CATEGORY_KEY_PREFIX .. tostring(GetServerTime()) .. "_" .. tostring(math.random(1000, 9999))
        if not customCategories[key] then
            return key
        end
    end
    return Bags.CUSTOM_CATEGORY_KEY_PREFIX .. tostring(GetServerTime()) .. "_" .. tostring(math.random(10000, 99999))
end

function Bags.GetNextDefaultCustomCategoryName(baseName)
    local base = NormalizeCustomCategoryName(baseName)
    if base == "" then
        base = "New Category"
    end

    local defsByKey = BuildCategoryDefinitions()
    local labels = BuildLabelLookup(defsByKey)
    if not labels[string.lower(base)] then
        return base
    end

    local index = 2
    while index < 500 do
        local candidate = base .. " " .. tostring(index)
        if not labels[string.lower(candidate)] then
            return candidate
        end
        index = index + 1
    end

    return base .. " " .. tostring(GetServerTime())
end

function Bags.CreateCustomCategory(name)
    local ok, cleanName, err = Bags.IsValidCustomCategoryName(name)
    if not ok then
        return nil, err
    end

    Bags.EnsureCategoryConfig()
    local cfg = Bags.GetConfig and Bags.GetConfig()
    if not cfg then
        return nil, "Missing bag configuration."
    end

    local key = GenerateCustomCategoryKey()
    cfg.CustomCategories[key] = cleanName
    cfg.CategoryPinned[key] = true
    tinsert(cfg.CategoryOrder, 1, key)

    local defsByKey = BuildCategoryDefinitions()
    EnsurePinnedOrder(cfg, defsByKey)
    if Bags.MovePinnedTokenToIndex then
        Bags.MovePinnedTokenToIndex(key, 1)
    end

    return key, nil
end

function Bags.RenameCustomCategory(categoryKey, name)
    if not Bags.IsCustomCategoryKey(categoryKey) then
        return false, "Not a custom category."
    end

    Bags.EnsureCategoryConfig()
    local cfg = Bags.GetConfig and Bags.GetConfig()
    if not cfg or not cfg.CustomCategories or not cfg.CustomCategories[categoryKey] then
        return false, "Custom category not found."
    end

    local ok, cleanName, err = Bags.IsValidCustomCategoryName(name, categoryKey)
    if not ok then
        return false, err
    end

    cfg.CustomCategories[categoryKey] = cleanName
    return true, nil
end

function Bags.DeleteCustomCategory(categoryKey)
    if not Bags.IsCustomCategoryKey(categoryKey) then
        return false, "Not a custom category."
    end

    Bags.EnsureCategoryConfig()
    local cfg = Bags.GetConfig and Bags.GetConfig()
    if not cfg or not cfg.CustomCategories or not cfg.CustomCategories[categoryKey] then
        return false, "Custom category not found."
    end

    cfg.CustomCategories[categoryKey] = nil
    cfg.CategoryPinned[categoryKey] = nil
    cfg.CategoryEnabled[categoryKey] = nil

    for i = #cfg.CategoryOrder, 1, -1 do
        if cfg.CategoryOrder[i] == categoryKey then
            tremove(cfg.CategoryOrder, i)
        end
    end

    for i = #cfg.PinnedOrder, 1, -1 do
        if cfg.PinnedOrder[i] == categoryKey then
            tremove(cfg.PinnedOrder, i)
        end
    end

    for itemID, customKey in pairs(cfg.CustomCategoryItems) do
        if customKey == categoryKey then
            cfg.CustomCategoryItems[itemID] = nil
        end
    end

    return true, nil
end

function Bags.GetAssignedCustomCategoryForItem(itemID)
    if type(itemID) ~= "number" then
        return nil
    end
    local cfg = Bags.GetConfig and Bags.GetConfig()
    local key = cfg and cfg.CustomCategoryItems and cfg.CustomCategoryItems[itemID] or nil
    if key and Bags.GetCustomCategoryName(key) then
        return key
    end
    return nil
end

function Bags.AssignItemToCustomCategory(itemID, categoryKey)
    if type(itemID) ~= "number" then
        return false
    end
    if not Bags.GetCustomCategoryName(categoryKey) then
        return false
    end
    local cfg = Bags.GetConfig and Bags.GetConfig()
    if not cfg then
        return false
    end
    cfg.CustomCategoryItems[itemID] = categoryKey
    return true
end

function Bags.ClearItemCustomCategory(itemID)
    if type(itemID) ~= "number" then
        return false
    end
    local cfg = Bags.GetConfig and Bags.GetConfig()
    if not cfg or type(cfg.CustomCategoryItems) ~= "table" then
        return false
    end
    if cfg.CustomCategoryItems[itemID] == nil then
        return false
    end
    cfg.CustomCategoryItems[itemID] = nil
    return true
end

function Bags.GetCursorItemContext()
    local cursorType, cursorValue, cursorLink = GetCursorInfo()
    local hasCursorItem = (cursorType == "item")
    local itemID = nil
    local isFromPlayerBag = false
    local sourceBagID = nil
    local sourceSlotIndex = nil
    local prefersReagentBag = false

    if cursorType == "item" then
        local link = (type(cursorLink) == "string" and cursorLink) or (type(cursorValue) == "string" and cursorValue) or nil
        if link then
            local itemIDFromLink = tonumber(string.match(link, "item:(%d+)"))
            if itemIDFromLink and itemIDFromLink > 0 then
                itemID = itemIDFromLink
            end
        end

        if not itemID and type(cursorValue) == "number" and cursorValue > 0 then
            itemID = cursorValue
        end

        if not itemID and type(cursorValue) == "table" and C_Item and C_Item.GetItemID then
            local ok, itemIDFromLocation = pcall(C_Item.GetItemID, cursorValue)
            if ok and type(itemIDFromLocation) == "number" and itemIDFromLocation > 0 then
                itemID = itemIDFromLocation
            end
        end
    end

    if C_Cursor and C_Cursor.GetCursorItem then
        local cursorItemLocation = C_Cursor.GetCursorItem()
        if cursorItemLocation then
            if cursorItemLocation.GetBagAndSlot then
                local ok, bagID, slotIndex = pcall(cursorItemLocation.GetBagAndSlot, cursorItemLocation)
                if ok and type(bagID) == "number" and type(slotIndex) == "number" then
                    sourceBagID = bagID
                    sourceSlotIndex = slotIndex
                    isFromPlayerBag = bagID >= BACKPACK_BAG_ID and bagID <= PLAYER_BAG_LAST_ID
                end
            end

            if not itemID and C_Item and C_Item.GetItemID then
                local ok, locationItemID = pcall(C_Item.GetItemID, cursorItemLocation)
                if ok and type(locationItemID) == "number" and locationItemID > 0 then
                    itemID = locationItemID
                    hasCursorItem = true
                end
            end
        end
    end

    if not hasCursorItem and Bags._draggingBagItemActive and type(Bags._draggingBagItemID) == "number" and Bags._draggingBagItemID > 0 then
        hasCursorItem = true
        itemID = Bags._draggingBagItemID
    end

    if type(itemID) == "number" and itemID > 0 and C_Item and C_Item.GetItemFamily and C_Container and C_Container.GetContainerNumFreeSlots then
        local _, reagentBagFamily = C_Container.GetContainerNumFreeSlots(REAGENT_BAG_ID)
        local itemFamily = C_Item.GetItemFamily(itemID)
        if bitband and type(itemFamily) == "number" and itemFamily > 0 and type(reagentBagFamily) == "number" and reagentBagFamily > 0 then
            prefersReagentBag = bitband(itemFamily, reagentBagFamily) ~= 0
        end
    end

    return hasCursorItem, itemID, isFromPlayerBag, prefersReagentBag, sourceBagID, sourceSlotIndex
end

function Bags.GetCursorItemID()
    if not Bags.GetCursorItemContext then
        return nil
    end

    local _, itemID = Bags.GetCursorItemContext()
    if type(itemID) == "number" and itemID > 0 then
        return itemID
    end

    return nil
end

function Bags.HasCursorItem()
    if not Bags.GetCursorItemContext then
        return false
    end

    local hasCursorItem = Bags.GetCursorItemContext()
    return hasCursorItem and true or false
end

function Bags.HandleCustomCategoryDrop(categoryKey)
    local itemID = Bags.GetCursorItemID and Bags.GetCursorItemID()
    if not itemID then
        return false
    end

    if not Bags.AssignItemToCustomCategory or not Bags.AssignItemToCustomCategory(itemID, categoryKey) then
        return false
    end

    ClearCursor()
    if Bags.RequestUpdate then
        Bags.RequestUpdate()
    end
    return true
end

----------------------------------------------------------------------------------------
-- Configuration & Ordering
----------------------------------------------------------------------------------------

EnsurePinnedOrder = function(cfg, defsByKey)
    local marker = Bags.BINNED_BLOCK_TOKEN
    local cleaned = {}
    local seen = {}
    local markerIndex = nil
    local categoryIndex = BuildCategoryIndexMap(cfg.CategoryOrder or {})

    for _, token in ipairs(cfg.PinnedOrder) do
        if token == marker then
            if not markerIndex then
                tinsert(cleaned, marker)
                markerIndex = #cleaned
            end
        elseif IsKnownCategory(defsByKey, token)
            and cfg.CategoryPinned[token]
            and not seen[token]
        then
            seen[token] = true
            tinsert(cleaned, token)
        end
    end

    local missingPinned = {}
    for key, pinned in pairs(cfg.CategoryPinned) do
        if pinned and IsKnownCategory(defsByKey, key) and not seen[key] then
            tinsert(missingPinned, key)
        end
    end

    table.sort(missingPinned, function(a, b)
        return (categoryIndex[a] or 9999) < (categoryIndex[b] or 9999)
    end)

    if not markerIndex then
        for _, key in ipairs(missingPinned) do
            tinsert(cleaned, key)
        end
        tinsert(cleaned, marker)
    else
        for i = #missingPinned, 1, -1 do
            tinsert(cleaned, markerIndex, missingPinned[i])
        end
    end

    cfg.PinnedOrder = cleaned
end

function Bags.GetCategoryDefinitions()
    local defsByKey = BuildCategoryDefinitions()
    local list = {}
    local cfg = Bags.GetConfig and Bags.GetConfig()
    local categoryOrder = (cfg and cfg.CategoryOrder) or Bags.CATEGORY_ORDER
    for _, key in ipairs(categoryOrder) do
        local def = defsByKey[key]
        if def then
            tinsert(list, def)
        end
    end
    return list
end

function Bags.EnsureCategoryConfig()
    if not Bags.GetConfig then
        return
    end

    local cfg = Bags.GetConfig()

    if type(cfg.CategoryOrder) == "table" then
        for i = 1, #cfg.CategoryOrder do
            cfg.CategoryOrder[i] = NormalizeLegacyCategoryKey(cfg.CategoryOrder[i])
        end
    end
    if type(cfg.PinnedOrder) == "table" then
        for i = 1, #cfg.PinnedOrder do
            cfg.PinnedOrder[i] = NormalizeLegacyCategoryKey(cfg.PinnedOrder[i])
        end
    end
    if type(cfg.CategoryPinned) == "table" then
        for legacyKey, mappedKey in pairs(LEGACY_CATEGORY_KEY_MAP) do
            if cfg.CategoryPinned[legacyKey] ~= nil then
                cfg.CategoryPinned[mappedKey] = cfg.CategoryPinned[mappedKey] or cfg.CategoryPinned[legacyKey]
                cfg.CategoryPinned[legacyKey] = nil
            end
        end
    end
    if type(cfg.CategoryEnabled) == "table" then
        for legacyKey, mappedKey in pairs(LEGACY_CATEGORY_KEY_MAP) do
            if cfg.CategoryEnabled[legacyKey] ~= nil then
                cfg.CategoryEnabled[mappedKey] = cfg.CategoryEnabled[mappedKey] or cfg.CategoryEnabled[legacyKey]
                cfg.CategoryEnabled[legacyKey] = nil
            end
        end
    end

    if type(cfg.CustomCategories) ~= "table" then
        cfg.CustomCategories = {}
    end
    if type(cfg.CustomCategoryItems) ~= "table" then
        cfg.CustomCategoryItems = {}
    end

    local normalizedCustom = {}
    for key, label in pairs(cfg.CustomCategories) do
        if Bags.IsCustomCategoryKey(key) then
            local cleanLabel = NormalizeCustomCategoryName(label)
            if cleanLabel ~= "" then
                normalizedCustom[key] = cleanLabel
            end
        end
    end
    cfg.CustomCategories = normalizedCustom

    local defsByKey = BuildCategoryDefinitions()
    local schemaVersion = Bags.CATEGORY_SCHEMA_VERSION or 1
    local schemaChanged = cfg.CategorySchemaVersion ~= schemaVersion

    if schemaChanged then
        if type(cfg.CategoryOrder) ~= "table" then cfg.CategoryOrder = {} end
        if type(cfg.CategoryEnabled) ~= "table" then cfg.CategoryEnabled = {} end
        if type(cfg.CategoryPinned) ~= "table" then cfg.CategoryPinned = {} end
        if type(cfg.PinnedOrder) ~= "table" then cfg.PinnedOrder = {} end
    end

    local mergedOrder = {}
    local seen = {}
    for _, key in ipairs(cfg.CategoryOrder) do
        if IsKnownCategory(defsByKey, key) and not seen[key] then
            seen[key] = true
            tinsert(mergedOrder, key)
        end
    end

    for _, key in ipairs(Bags.CATEGORY_ORDER) do
        if IsKnownCategory(defsByKey, key) and not seen[key] then
            seen[key] = true
            tinsert(mergedOrder, key)
        end
    end

    for key in pairs(cfg.CustomCategories) do
        if IsKnownCategory(defsByKey, key) and not seen[key] then
            seen[key] = true
            tinsert(mergedOrder, key)
        end
    end

    cfg.CategoryOrder = mergedOrder
    cfg.CategoryEnabled = cfg.CategoryEnabled or {}
    cfg.CategoryPinned = cfg.CategoryPinned or {}
    cfg.PinnedOrder = cfg.PinnedOrder or {}
    local shouldSeedPinnedOrder = #cfg.PinnedOrder == 0

    for _, key in ipairs(cfg.CategoryOrder) do
        cfg.CategoryEnabled[key] = true

        if cfg.CategoryPinned[key] == nil then
            if (Bags.DEFAULT_PINNED_TOP_CATEGORIES and Bags.DEFAULT_PINNED_TOP_CATEGORIES[key])
                or (Bags.DEFAULT_PINNED_BOTTOM_CATEGORIES and Bags.DEFAULT_PINNED_BOTTOM_CATEGORIES[key]) then
                cfg.CategoryPinned[key] = true
            else
                cfg.CategoryPinned[key] = false
            end
        else
            cfg.CategoryPinned[key] = cfg.CategoryPinned[key] and true or false
        end

        if Bags.IsCustomCategoryKey(key) then
            cfg.CategoryPinned[key] = true
        end
    end

    if shouldSeedPinnedOrder then
        local seeded = {}
        local seenPinned = {}

        for _, key in ipairs(cfg.CategoryOrder) do
            if Bags.DEFAULT_PINNED_TOP_CATEGORIES and Bags.DEFAULT_PINNED_TOP_CATEGORIES[key] and cfg.CategoryPinned[key] then
                tinsert(seeded, key)
                seenPinned[key] = true
            end
        end

        tinsert(seeded, Bags.BINNED_BLOCK_TOKEN)

        for _, key in ipairs(cfg.CategoryOrder) do
            if Bags.DEFAULT_PINNED_BOTTOM_CATEGORIES and Bags.DEFAULT_PINNED_BOTTOM_CATEGORIES[key]
                and cfg.CategoryPinned[key] and not seenPinned[key] then
                tinsert(seeded, key)
                seenPinned[key] = true
            end
        end

        cfg.PinnedOrder = seeded
    end

    local cleanedCustomAssignments = {}
    for itemID, customKey in pairs(cfg.CustomCategoryItems) do
        local numericItemID = tonumber(itemID)
        if numericItemID and numericItemID > 0 and cfg.CustomCategories[customKey] then
            cleanedCustomAssignments[numericItemID] = customKey
        end
    end
    cfg.CustomCategoryItems = cleanedCustomAssignments

    EnsurePinnedOrder(cfg, defsByKey)
    cfg.CategorySchemaVersion = schemaVersion
end

function Bags.GetPinnedOrderTokens()
    Bags.EnsureCategoryConfig()
    local cfg = Bags.GetConfig and Bags.GetConfig()
    local tokens = {}
    if not cfg then
        return tokens
    end

    for _, token in ipairs(cfg.PinnedOrder) do
        if token == Bags.BINNED_BLOCK_TOKEN then
            tinsert(tokens, token)
        elseif cfg.CategoryPinned[token] then
            tinsert(tokens, token)
        end
    end

    if #tokens == 0 then
        tinsert(tokens, Bags.BINNED_BLOCK_TOKEN)
    end
    return tokens
end

function Bags.GetRenderCategoryOrder()
    Bags.EnsureCategoryConfig()
    local cfg = Bags.GetConfig and Bags.GetConfig()
    local renderOrder = {}
    if not cfg then
        return renderOrder
    end

    local unpinnedCategories = {}
    for _, key in ipairs(cfg.CategoryOrder) do
        if cfg.CategoryPinned[key] ~= true then
            tinsert(unpinnedCategories, key)
        end
    end

    local blockInserted = false
    for _, token in ipairs(cfg.PinnedOrder) do
        if token == Bags.BINNED_BLOCK_TOKEN then
            for _, key in ipairs(unpinnedCategories) do
                tinsert(renderOrder, key)
            end
            blockInserted = true
        elseif cfg.CategoryPinned[token] then
            tinsert(renderOrder, token)
        end
    end

    if not blockInserted then
        for _, key in ipairs(unpinnedCategories) do
            tinsert(renderOrder, key)
        end
    end

    local seen = {}
    for _, key in ipairs(renderOrder) do
        seen[key] = true
    end
    for _, key in ipairs(cfg.CategoryOrder) do
        if not seen[key] then
            tinsert(renderOrder, key)
            seen[key] = true
        end
    end

    return renderOrder
end

function Bags.GetEnabledCategoryOrder()
    return Bags.GetRenderCategoryOrder()
end

function Bags.IsCategoryEnabled(categoryKey)
    return true
end

function Bags.IsCategoryPinned(categoryKey)
    Bags.EnsureCategoryConfig()
    local cfg = Bags.GetConfig and Bags.GetConfig()
    if not cfg then
        return false
    end
    return cfg.CategoryPinned[categoryKey] == true
end

function Bags.SetCategoryPinned(categoryKey, pinned)
    Bags.EnsureCategoryConfig()
    local cfg = Bags.GetConfig and Bags.GetConfig()
    local defsByKey = BuildCategoryDefinitions()
    if not cfg or not IsKnownCategory(defsByKey, categoryKey) then
        return
    end

    local shouldPin = pinned and true or false
    if Bags.IsCustomCategoryKey(categoryKey) then
        shouldPin = true
    end
    cfg.CategoryPinned[categoryKey] = shouldPin

    if not shouldPin then
        for i = #cfg.PinnedOrder, 1, -1 do
            if cfg.PinnedOrder[i] == categoryKey then
                tremove(cfg.PinnedOrder, i)
            end
        end
    end

    EnsurePinnedOrder(cfg, defsByKey)
end

function Bags.SetCategoryEnabled(categoryKey, _)
    Bags.EnsureCategoryConfig()
    local cfg = Bags.GetConfig and Bags.GetConfig()
    local defsByKey = BuildCategoryDefinitions()
    if not cfg or not IsKnownCategory(defsByKey, categoryKey) then
        return
    end

    cfg.CategoryEnabled[categoryKey] = true
    EnsurePinnedOrder(cfg, defsByKey)
end

function Bags.MovePinnedTokenToIndex(token, targetIndex)
    Bags.EnsureCategoryConfig()
    local cfg = Bags.GetConfig and Bags.GetConfig()
    if not cfg or type(token) ~= "string" then
        return
    end

    if token ~= Bags.BINNED_BLOCK_TOKEN and cfg.CategoryPinned[token] ~= true then
        return
    end

    local tokens = Bags.GetPinnedOrderTokens()
    local dragIndex = nil
    for i, existingToken in ipairs(tokens) do
        if existingToken == token then
            dragIndex = i
            break
        end
    end
    if not dragIndex then
        return
    end

    tremove(tokens, dragIndex)

    local insertIndex = tonumber(targetIndex) or (#tokens + 1)
    if insertIndex < 1 then
        insertIndex = 1
    elseif insertIndex > (#tokens + 1) then
        insertIndex = #tokens + 1
    end

    tinsert(tokens, insertIndex, token)
    cfg.PinnedOrder = tokens

    local defsByKey = BuildCategoryDefinitions()
    EnsurePinnedOrder(cfg, defsByKey)
end

function Bags.MovePinnedCategoryToIndex(categoryKey, targetIndex)
    Bags.MovePinnedTokenToIndex(categoryKey, targetIndex)
end
