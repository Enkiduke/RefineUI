----------------------------------------------------------------------------------------
-- AutoItemBar Component: Filtering
-- Description: Auto-discovery logic for resolving item categories.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local AutoItemBar = RefineUI:GetModule("AutoItemBar")
if not AutoItemBar then return end

----------------------------------------------------------------------------------------
--	Globals
----------------------------------------------------------------------------------------

local lower = string.lower
local find = string.find
local gsub = string.gsub
local ipairs = ipairs
local type = type
local tsort = table.sort

local GetItemInfo = C_Item.GetItemInfo
local GetItemInfoInstant = C_Item.GetItemInfoInstant
local GetItemSubClassInfo = C_Item.GetItemSubClassInfo

----------------------------------------------------------------------------------------
--	Constants
----------------------------------------------------------------------------------------

local ITEM_CLASS_CONSUMABLE = Enum.ItemClass.Consumable
local ITEM_CLASS_ENHANCEMENT = Enum.ItemClass.ItemEnhancement
local ITEM_CLASS_QUESTITEM = Enum.ItemClass.Questitem
local ITEM_CLASS_TRADEGOODS = Enum.ItemClass.Tradegoods

local CATEGORY_KEYS = {
    FOOD = "food",
    DRINKS = "drinks",
    POTIONS = "potions_health_mana",
    ELIXIRS = "elixirs",
    FLASKS_PHIALS = "flasks_phials",
    AUGMENT_RUNE = "augment_rune",
    VANTUS_RUNE = "vantus_rune",
    EXPLOSIVES_DEVICES = "explosives_devices",
    MANA_OILS = "mana_oils",
    SHARPENING_STONES = "sharpening_stones",
    BANDAGES = "bandages",
    GROUP_CONSUMABLES = "group_consumables",
    CONTAINER = "container",
    QUEST_ITEM = "quest_item",
    OTHER = "other",
}

local CATEGORY_DEFINITIONS = {
    { key = CATEGORY_KEYS.FOOD, label = "Food", defaultEnabled = true },
    { key = CATEGORY_KEYS.DRINKS, label = "Drinks", defaultEnabled = true },
    { key = CATEGORY_KEYS.POTIONS, label = "Potions (Health and Mana)", defaultEnabled = true },
    { key = CATEGORY_KEYS.ELIXIRS, label = "Elixirs", defaultEnabled = true },
    { key = CATEGORY_KEYS.FLASKS_PHIALS, label = "Flasks & Phials", defaultEnabled = true },
    { key = CATEGORY_KEYS.AUGMENT_RUNE, label = "Augment Rune", defaultEnabled = true },
    { key = CATEGORY_KEYS.VANTUS_RUNE, label = "Vantus Rune", defaultEnabled = true },
    { key = CATEGORY_KEYS.EXPLOSIVES_DEVICES, label = "Explosives and Devices", defaultEnabled = true },
    { key = CATEGORY_KEYS.MANA_OILS, label = "Mana Oils", defaultEnabled = true },
    { key = CATEGORY_KEYS.SHARPENING_STONES, label = "Sharpening stones", defaultEnabled = true },
    { key = CATEGORY_KEYS.BANDAGES, label = "Bandages", defaultEnabled = false },
    { key = CATEGORY_KEYS.GROUP_CONSUMABLES, label = "Group Consumables", defaultEnabled = false },
    { key = CATEGORY_KEYS.CONTAINER, label = "Container", defaultEnabled = false },
    { key = CATEGORY_KEYS.QUEST_ITEM, label = "Quest Item", defaultEnabled = false },
    { key = CATEGORY_KEYS.OTHER, label = "Other", defaultEnabled = false },
}

local CATEGORY_BY_KEY = {}
for _, definition in ipairs(CATEGORY_DEFINITIONS) do
    CATEGORY_BY_KEY[definition.key] = definition
end

local ALLOWED_CLASS = {
    [ITEM_CLASS_CONSUMABLE] = true,
    [ITEM_CLASS_ENHANCEMENT] = true,
    [ITEM_CLASS_QUESTITEM] = true,
    [ITEM_CLASS_TRADEGOODS] = true,
}

local NEEDLES = {
    DRINK_NAME = { "water", "drink", "juice", "tea", "coffee", "ale", "wine", "milk", "brew", "cider", "soda", "nectar" },
    FOOD_NAME = { "food", "feast", "fish", "bread", "meat", "stew", "soup", "cake", "ration", "snack", "cheese", "meal" },
    MANA_OIL_SUBCLASS = { "manaoil" },
    MANA_OIL_NAME = { "manaoil", "wizardoil", "brilliantmanaoil", "lessermanaoil", "superiormanaoil" },
    MANA_OIL_RAW_NAME = { "mana oil", "wizard oil" },
    STONE_SUBCLASS = { "sharpen", "stone", "whetstone", "weightstone" },
    STONE_ENHANCEMENT_NAME = { "sharpeningstone", "whetstone", "weightstone", "grindstone", "sharpening" },
    VANTUS_NAME = { "vantusrune" },
    AUGMENT_NAME = { "augmentrune", "augmentationrune", "draconicaugmentrune" },
    OIL_NAME = { "manaoil", "wizardoil" },
    STONE_NAME = { "sharpeningstone", "whetstone", "weightstone", "grindstone" },
    BANDAGE_NAME = { "bandage" },
    QUEST_SUBCLASS = { "questitem", "quest" },
    EXPLOSIVE_SUBCLASS = { "explosive", "explosives", "device", "devices" },
    EXPLOSIVE_NAME = { "bomb", "dynamite", "grenade", "explosive", "device" },
    CONTAINER_SUBCLASS = { "container" },
    GROUP_SUBCLASS = { "groupconsumable", "groupconsumables" },
    BANDAGE_SUBCLASS = { "bandage", "bandages" },
    AUGMENT_SUBCLASS = { "augmentrune", "augmentation", "augmentationrune", "augment" },
    VANTUS_SUBCLASS = { "vantusrune", "vantus" },
    ELIXIR_SUBCLASS = { "elixir", "elixirs" },
    FLASK_SUBCLASS = { "flask", "flasks", "phial", "phials" },
    POTION_SUBCLASS = { "potion", "potions" },
    RESTORE_POTION_NAME = { "health", "healing", "mana", "rejuvenation", "restore", "restorative" },
    FOOD_SUBCLASS = { "foodanddrink", "food", "drink", "drinks" },
    ENHANCEMENT_SUBCLASS = { "itemenhancement", "enhancement", "oil", "stone", "whetstone", "weightstone", "sharpen" },
}

----------------------------------------------------------------------------------------
--	Query Pipeline
----------------------------------------------------------------------------------------

local function NormalizeText(text)
    if type(text) ~= "string" then
        return ""
    end
    return gsub(lower(text), "[^%w]+", "")
end

local function ContainsAny(text, needles)
    if text == "" then
        return false
    end
    for _, needle in ipairs(needles) do
        if find(text, needle, 1, true) then
            return true
        end
    end
    return false
end

local function ResolveFoodDrinkCategory(itemName)
    local name = lower(itemName or "")
    if name == "" then
        return CATEGORY_KEYS.FOOD
    end

    if ContainsAny(name, NEEDLES.DRINK_NAME) and not ContainsAny(name, NEEDLES.FOOD_NAME) then
        return CATEGORY_KEYS.DRINKS
    end

    return CATEGORY_KEYS.FOOD
end

local function ResolveEnhancementCategory(normalizedSubClass, normalizedName, rawName)
    if ContainsAny(normalizedSubClass, NEEDLES.MANA_OIL_SUBCLASS)
        or ContainsAny(normalizedName, NEEDLES.MANA_OIL_NAME)
        or ContainsAny(lower(rawName or ""), NEEDLES.MANA_OIL_RAW_NAME) then
        return CATEGORY_KEYS.MANA_OILS
    end

    if ContainsAny(normalizedSubClass, NEEDLES.STONE_SUBCLASS)
        or ContainsAny(normalizedName, NEEDLES.STONE_ENHANCEMENT_NAME) then
        return CATEGORY_KEYS.SHARPENING_STONES
    end

    return CATEGORY_KEYS.OTHER
end

local function ResolveCategoryKey(classID, subClassID, itemName, itemSubType)
    local subClassLabel = (classID and subClassID and GetItemSubClassInfo(classID, subClassID)) or itemSubType
    local normalizedSubClass = NormalizeText(subClassLabel)
    local normalizedName = NormalizeText(itemName)

    if ContainsAny(normalizedName, NEEDLES.VANTUS_NAME) then
        return CATEGORY_KEYS.VANTUS_RUNE
    end

    if ContainsAny(normalizedName, NEEDLES.AUGMENT_NAME) then
        return CATEGORY_KEYS.AUGMENT_RUNE
    end

    if ContainsAny(normalizedName, NEEDLES.OIL_NAME) then
        return CATEGORY_KEYS.MANA_OILS
    end

    if ContainsAny(normalizedName, NEEDLES.STONE_NAME) then
        return CATEGORY_KEYS.SHARPENING_STONES
    end

    if ContainsAny(normalizedName, NEEDLES.BANDAGE_NAME) then
        return CATEGORY_KEYS.BANDAGES
    end

    if classID == ITEM_CLASS_QUESTITEM or ContainsAny(normalizedSubClass, NEEDLES.QUEST_SUBCLASS) then
        return CATEGORY_KEYS.QUEST_ITEM
    end

    if classID == ITEM_CLASS_TRADEGOODS then
        if ContainsAny(normalizedSubClass, NEEDLES.EXPLOSIVE_SUBCLASS)
            or ContainsAny(normalizedName, NEEDLES.EXPLOSIVE_NAME) then
            return CATEGORY_KEYS.EXPLOSIVES_DEVICES
        end
        return nil
    end

    if ContainsAny(normalizedSubClass, NEEDLES.CONTAINER_SUBCLASS) then
        return CATEGORY_KEYS.CONTAINER
    end

    if ContainsAny(normalizedSubClass, NEEDLES.GROUP_SUBCLASS) then
        return CATEGORY_KEYS.GROUP_CONSUMABLES
    end

    if ContainsAny(normalizedSubClass, NEEDLES.BANDAGE_SUBCLASS) then
        return CATEGORY_KEYS.BANDAGES
    end

    if ContainsAny(normalizedSubClass, NEEDLES.AUGMENT_SUBCLASS) then
        return CATEGORY_KEYS.AUGMENT_RUNE
    end

    if ContainsAny(normalizedSubClass, NEEDLES.VANTUS_SUBCLASS) then
        return CATEGORY_KEYS.VANTUS_RUNE
    end

    if ContainsAny(normalizedSubClass, NEEDLES.ELIXIR_SUBCLASS) then
        return CATEGORY_KEYS.ELIXIRS
    end

    if ContainsAny(normalizedSubClass, NEEDLES.FLASK_SUBCLASS) then
        return CATEGORY_KEYS.FLASKS_PHIALS
    end

    if ContainsAny(normalizedSubClass, NEEDLES.POTION_SUBCLASS) then
        local loweredName = lower(itemName or "")
        if loweredName == "" or ContainsAny(loweredName, NEEDLES.RESTORE_POTION_NAME) then
            return CATEGORY_KEYS.POTIONS
        end
        return CATEGORY_KEYS.OTHER
    end

    if ContainsAny(normalizedSubClass, NEEDLES.FOOD_SUBCLASS) then
        return ResolveFoodDrinkCategory(itemName)
    end

    if ContainsAny(normalizedSubClass, NEEDLES.EXPLOSIVE_SUBCLASS) then
        return CATEGORY_KEYS.EXPLOSIVES_DEVICES
    end

    if classID == ITEM_CLASS_ENHANCEMENT or ContainsAny(normalizedSubClass, NEEDLES.ENHANCEMENT_SUBCLASS) then
        return ResolveEnhancementCategory(normalizedSubClass, normalizedName, itemName)
    end

    if classID == ITEM_CLASS_CONSUMABLE then
        return CATEGORY_KEYS.OTHER
    end

    return nil
end

-- Item classification never changes, so each item resolves once. Items whose name
-- is not cached yet stay pending and resolve again on the next lookup.
local itemRecords = {}

local function GetItemRecord(itemID)
    local record = itemRecords[itemID]
    if record and not record.pending then
        return record
    end

    local itemName, _, _, itemLevel = GetItemInfo(itemID)
    local _, _, itemSubType, _, _, classID, subClassID = GetItemInfoInstant(itemID)
    if not record then
        record = {}
        itemRecords[itemID] = record
    end
    record.classID = classID
    record.subClassID = subClassID
    record.itemLevel = itemLevel
    record.categoryKey = ResolveCategoryKey(classID, subClassID, itemName, itemSubType)
    record.pending = itemName == nil
    return record
end

function AutoItemBar:GetCategoryDefinitions()
    return CATEGORY_DEFINITIONS
end

function AutoItemBar:GetCategoryByKey(key)
    return key and CATEGORY_BY_KEY[key]
end

function AutoItemBar:GetItemCategoryKey(itemID)
    return GetItemRecord(itemID).categoryKey
end

function AutoItemBar:IsItemAutoTracked(itemID)
    local record = GetItemRecord(itemID)
    if not ALLOWED_CLASS[record.classID] or not record.categoryKey then return false end

    local minItemLevel = self:GetConfig().MinItemLevel or 0
    if minItemLevel > 0 and record.itemLevel and record.itemLevel < minItemLevel then
        return false
    end

    return self:IsTrackingCategoryEnabled(record.categoryKey)
end

function AutoItemBar:ShouldDisplayItem(itemID)
    if self:IsItemHidden(itemID) then
        return false
    end
    return self:IsItemManuallyTracked(itemID) or self:IsItemAutoTracked(itemID)
end

----------------------------------------------------------------------------------------
--	Sorting
----------------------------------------------------------------------------------------

local sortEnabledIndex = {}
local sortCategoryIndex = {}

local function CompareItems(a, b)
    local indexA, indexB = sortEnabledIndex[a], sortEnabledIndex[b]
    if indexA ~= indexB then
        return indexA < indexB
    end

    indexA, indexB = sortCategoryIndex[a], sortCategoryIndex[b]
    if indexA ~= indexB then
        return indexA < indexB
    end

    local recordA, recordB = itemRecords[a], itemRecords[b]
    local classA, classB = recordA.classID or -1, recordB.classID or -1
    if classA ~= classB then
        return classA < classB
    end

    local subA, subB = recordA.subClassID or -1, recordB.subClassID or -1
    if subA ~= subB then
        return subA < subB
    end

    return a < b
end

function AutoItemBar:SortItems(itemIDs)
    for _, itemID in ipairs(itemIDs) do
        local categoryKey = GetItemRecord(itemID).categoryKey
        if self:IsItemManuallyTracked(itemID) then
            sortEnabledIndex[itemID] = self:GetEnabledSortIndexForItem(itemID)
        else
            sortEnabledIndex[itemID] = self:GetEnabledSortIndexForCategory(categoryKey)
        end
        sortCategoryIndex[itemID] = self:GetCategorySortIndex(categoryKey)
    end
    tsort(itemIDs, CompareItems)
end
