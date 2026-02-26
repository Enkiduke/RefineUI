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

local format = string.format
local lower = string.lower
local find = string.find
local gsub = string.gsub
local tostring = tostring
local type = type
local tinsert = table.insert
local ipairs = ipairs

local GetItemInfo = C_Item and C_Item.GetItemInfo
local GetItemInfoInstant = C_Item and C_Item.GetItemInfoInstant
local GetItemSubClassInfo = C_Item and C_Item.GetItemSubClassInfo

local ItemClassEnum = Enum and Enum.ItemClass

----------------------------------------------------------------------------------------
--	Constants
----------------------------------------------------------------------------------------

local function GetItemClassEnumValue(...)
    if type(ItemClassEnum) ~= "table" then
        return nil
    end
    for i = 1, select("#", ...) do
        local key = select(i, ...)
        local value = rawget(ItemClassEnum, key)
        if value ~= nil then
            return value
        end
    end
    return nil
end

local ITEM_CLASS_CONSUMABLE = GetItemClassEnumValue("Consumable")
local ITEM_CLASS_ENHANCEMENT = GetItemClassEnumValue("ItemEnhancement")
local ITEM_CLASS_QUESTITEM = GetItemClassEnumValue("Questitem", "QuestItem", "Quest")
local ITEM_CLASS_TRADEGOODS = GetItemClassEnumValue("Tradegoods", "TradeGoods")

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

local FIXED_CATEGORY_DEFINITIONS = {
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

local allowedClass = {
    Consumable = true,
    ItemEnhancement = true,
    ["Item Enhancement"] = true,
    Quest = true,
    QuestItem = true,
    Questitem = true,
    ["Quest Item"] = true,
    TradeGoods = true,
    Tradegoods = true,
    ["Trade Goods"] = true,
}

if ITEM_CLASS_CONSUMABLE then
    allowedClass[ITEM_CLASS_CONSUMABLE] = true
end
if ITEM_CLASS_ENHANCEMENT then
    allowedClass[ITEM_CLASS_ENHANCEMENT] = true
end
if ITEM_CLASS_QUESTITEM then
    allowedClass[ITEM_CLASS_QUESTITEM] = true
end
if ITEM_CLASS_TRADEGOODS then
    allowedClass[ITEM_CLASS_TRADEGOODS] = true
end

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

local function GetItemDetails(itemID)
    local instantA, instantB, instantClassID, instantSubClassID
    if GetItemInfoInstant then
        local _, a, b, _, _, classID, subClassID = GetItemInfoInstant(itemID)
        instantA, instantB, instantClassID, instantSubClassID = a, b, classID, subClassID
    end
    local classID = (type(instantA) == "number") and instantA or instantClassID
    local subClassID = (type(instantB) == "number") and instantB or instantSubClassID
    local itemType = (type(instantA) == "string") and instantA or nil
    local itemSubType = (type(instantB) == "string") and instantB or nil
    local itemName

    local info1, _, _, infoLevel, _, infoType, infoSubType, _, _, _, _, infoClassID, infoSubClassID
    if GetItemInfo then
        info1, _, _, infoLevel, _, infoType, infoSubType, _, _, _, _, infoClassID, infoSubClassID = GetItemInfo(itemID)
    end
    local itemLevel = infoLevel

    if type(info1) == "table" then
        local info = info1
        itemName = info.name or info.itemName
        itemLevel = info.currentItemLevel or info.itemLevel or info.baseItemLevel
        infoClassID = info.classID or info.itemClassID
        infoSubClassID = info.subclassID or info.itemSubClassID or info.subClassID
        infoType = info.itemType or info.itemClassName
        infoSubType = info.itemSubType or info.itemSubclassName
    else
        itemName = info1
    end

    if not classID then classID = infoClassID end
    if not subClassID then subClassID = infoSubClassID end
    if not itemType then itemType = infoType end
    if not itemSubType then itemSubType = infoSubType end

    return classID or itemType, subClassID or itemSubType, itemLevel, itemName, itemSubType
end

local function GetSubClassLabel(classID, subClassID, fallbackSubType)
    if type(subClassID) == "string" then
        return subClassID
    end
    if type(classID) == "number" and type(subClassID) == "number" and GetItemSubClassInfo then
        return GetItemSubClassInfo(classID, subClassID) or fallbackSubType
    end
    return fallbackSubType
end

local function IsQuestClass(classID)
    return classID == ITEM_CLASS_QUESTITEM
        or classID == "Quest"
        or classID == "QuestItem"
        or classID == "Questitem"
        or classID == "Quest Item"
end

local function IsEnhancementClass(classID)
    return classID == ITEM_CLASS_ENHANCEMENT
        or classID == "ItemEnhancement"
        or classID == "Item Enhancement"
end

local function IsConsumableClass(classID)
    return classID == ITEM_CLASS_CONSUMABLE or classID == "Consumable"
end

local function IsTradeGoodsClass(classID)
    return classID == ITEM_CLASS_TRADEGOODS
        or classID == "TradeGoods"
        or classID == "Tradegoods"
        or classID == "Trade Goods"
end

local function ResolveFoodDrinkCategory(itemName)
    local name = lower(itemName or "")
    if name == "" then
        return CATEGORY_KEYS.FOOD
    end

    local looksLikeDrink = ContainsAny(name, {
        "water", "drink", "juice", "tea", "coffee", "ale", "wine", "milk", "brew", "cider", "soda", "nectar",
    })
    local looksLikeFood = ContainsAny(name, {
        "food", "feast", "fish", "bread", "meat", "stew", "soup", "cake", "ration", "snack", "cheese", "meal",
    })

    if looksLikeDrink and not looksLikeFood then
        return CATEGORY_KEYS.DRINKS
    end

    return CATEGORY_KEYS.FOOD
end

local function ResolveEnhancementCategory(normalizedSubClass, normalizedName, rawName)
    if ContainsAny(normalizedSubClass, { "manaoil" })
        or ContainsAny(normalizedName, { "manaoil", "wizardoil", "brilliantmanaoil", "lessermanaoil", "superiormanaoil" })
        or ContainsAny(lower(rawName or ""), { "mana oil", "wizard oil" }) then
        return CATEGORY_KEYS.MANA_OILS
    end

    if ContainsAny(normalizedSubClass, { "sharpen", "stone", "whetstone", "weightstone" })
        or ContainsAny(normalizedName, { "sharpeningstone", "whetstone", "weightstone", "grindstone", "sharpening" }) then
        return CATEGORY_KEYS.SHARPENING_STONES
    end

    return CATEGORY_KEYS.OTHER
end

local function ResolveCategoryKey(classID, subClassID, itemName, itemSubType)
    local subClassLabel = GetSubClassLabel(classID, subClassID, itemSubType)
    local normalizedSubClass = NormalizeText(subClassLabel)
    local normalizedName = NormalizeText(itemName)
    local loweredName = lower(itemName or "")

    if ContainsAny(normalizedName, { "vantusrune" }) then
        return CATEGORY_KEYS.VANTUS_RUNE
    end

    if ContainsAny(normalizedName, { "augmentrune", "augmentationrune", "draconicaugmentrune" }) then
        return CATEGORY_KEYS.AUGMENT_RUNE
    end

    if ContainsAny(normalizedName, { "manaoil", "wizardoil" }) then
        return CATEGORY_KEYS.MANA_OILS
    end

    if ContainsAny(normalizedName, { "sharpeningstone", "whetstone", "weightstone", "grindstone" }) then
        return CATEGORY_KEYS.SHARPENING_STONES
    end

    if ContainsAny(normalizedName, { "bandage" }) then
        return CATEGORY_KEYS.BANDAGES
    end

    if IsQuestClass(classID) or ContainsAny(normalizedSubClass, { "questitem", "quest" }) then
        return CATEGORY_KEYS.QUEST_ITEM
    end

    if IsTradeGoodsClass(classID) then
        if ContainsAny(normalizedSubClass, { "explosive", "explosives", "device", "devices" })
            or ContainsAny(normalizedName, { "bomb", "dynamite", "grenade", "explosive", "device" }) then
            return CATEGORY_KEYS.EXPLOSIVES_DEVICES
        end
        return nil
    end

    if ContainsAny(normalizedSubClass, { "container" }) then
        return CATEGORY_KEYS.CONTAINER
    end

    if ContainsAny(normalizedSubClass, { "groupconsumable", "groupconsumables" }) then
        return CATEGORY_KEYS.GROUP_CONSUMABLES
    end

    if ContainsAny(normalizedSubClass, { "bandage", "bandages" }) then
        return CATEGORY_KEYS.BANDAGES
    end

    if ContainsAny(normalizedSubClass, { "augmentrune", "augmentation", "augmentationrune", "augment" }) then
        return CATEGORY_KEYS.AUGMENT_RUNE
    end

    if ContainsAny(normalizedSubClass, { "vantusrune", "vantus" }) then
        return CATEGORY_KEYS.VANTUS_RUNE
    end

    if ContainsAny(normalizedSubClass, { "elixir", "elixirs" }) then
        return CATEGORY_KEYS.ELIXIRS
    end

    if ContainsAny(normalizedSubClass, { "flask", "flasks", "phial", "phials" }) then
        return CATEGORY_KEYS.FLASKS_PHIALS
    end

    if ContainsAny(normalizedSubClass, { "potion", "potions" }) then
        if loweredName == ""
            or ContainsAny(loweredName, { "health", "healing", "mana", "rejuvenation", "restore", "restorative" }) then
            return CATEGORY_KEYS.POTIONS
        end
        return CATEGORY_KEYS.OTHER
    end

    if ContainsAny(normalizedSubClass, { "foodanddrink", "food", "drink", "drinks" }) then
        return ResolveFoodDrinkCategory(itemName)
    end

    if ContainsAny(normalizedSubClass, { "explosive", "explosives", "device", "devices" }) then
        return CATEGORY_KEYS.EXPLOSIVES_DEVICES
    end

    if IsEnhancementClass(classID) or ContainsAny(normalizedSubClass, { "itemenhancement", "enhancement", "oil", "stone", "whetstone", "weightstone", "sharpen" }) then
        return ResolveEnhancementCategory(normalizedSubClass, normalizedName, itemName)
    end

    if IsConsumableClass(classID) then
        return CATEGORY_KEYS.OTHER
    end

    return nil
end

function AutoItemBar:BuildCategoryDefinitions()
    if self.categoryDefinitions and self.categoryByKey then
        return self.categoryDefinitions
    end

    local definitions = {}
    local byKey = {}

    for _, data in ipairs(FIXED_CATEGORY_DEFINITIONS) do
        local def = {
            key = data.key,
            label = data.label,
            defaultEnabled = data.defaultEnabled and true or false,
        }
        tinsert(definitions, def)
        byKey[def.key] = def
    end

    self.categoryDefinitions = definitions
    self.categoryByKey = byKey
    return definitions
end

function AutoItemBar:GetCategoryDefinitions()
    return self:BuildCategoryDefinitions()
end

function AutoItemBar:GetCategoryByKey(key)
    if not key then return nil end
    self:BuildCategoryDefinitions()
    return self.categoryByKey and self.categoryByKey[key] or nil
end

function AutoItemBar:GetItemCategoryKey(itemID)
    self:BuildCategoryDefinitions()
    local classID, subClassID, _, itemName, itemSubType = GetItemDetails(itemID)
    return ResolveCategoryKey(classID, subClassID, itemName, itemSubType)
end

function AutoItemBar:IsItemAutoTracked(itemID)
    local classID, _, itemLevel = GetItemDetails(itemID)
    if not allowedClass[classID] then return false end

    local cfg = self:GetConfig()
    local minItemLevel = cfg.MinItemLevel or 0
    if minItemLevel > 0 and itemLevel and itemLevel < minItemLevel then
        return false
    end

    local categoryKey = self:GetItemCategoryKey(itemID)
    if not categoryKey then return false end

    return self:IsTrackingCategoryEnabled(categoryKey)
end

function AutoItemBar:ShouldDisplayItem(itemID)
    if self:IsItemHidden(itemID) then
        return false
    end
    return self:IsItemManuallyTracked(itemID) or self:IsItemAutoTracked(itemID)
end

function AutoItemBar:SortItems(a, b)
    if not a or not b then return false end

    local trackedA = self:IsItemManuallyTracked(a)
    local trackedB = self:IsItemManuallyTracked(b)
    local categoryA = self:GetItemCategoryKey(a)
    local categoryB = self:GetItemCategoryKey(b)
    local sortIndexA
    local sortIndexB

    if trackedA then
        sortIndexA = self:GetEnabledSortIndexForItem(a)
    else
        sortIndexA = self:GetEnabledSortIndexForCategory(categoryA)
    end
    if trackedB then
        sortIndexB = self:GetEnabledSortIndexForItem(b)
    else
        sortIndexB = self:GetEnabledSortIndexForCategory(categoryB)
    end

    if sortIndexA ~= sortIndexB then
        return sortIndexA < sortIndexB
    end

    local categoryIndexA = self:GetCategorySortIndex(categoryA)
    local categoryIndexB = self:GetCategorySortIndex(categoryB)
    if categoryIndexA ~= categoryIndexB then
        return categoryIndexA < categoryIndexB
    end

    local classA, subA = GetItemDetails(a)
    local classB, subB = GetItemDetails(b)
    local classKeyA = type(classA) == "number" and format("%03d", classA) or tostring(classA or "")
    local classKeyB = type(classB) == "number" and format("%03d", classB) or tostring(classB or "")
    local subKeyA = type(subA) == "number" and format("%03d", subA) or tostring(subA or "")
    local subKeyB = type(subB) == "number" and format("%03d", subB) or tostring(subB or "")

    if classKeyA == classKeyB then
        if subKeyA == subKeyB then
            return a < b
        end
        return subKeyA < subKeyB
    end

    return classKeyA < classKeyB
end
