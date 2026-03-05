
----------------------------------------------------------------------------------------
-- AutoOpenBar for RefineUI
-- Description: Automatically surfaces openable containers and learnable bag items.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local AutoOpenBar = RefineUI:RegisterModule("AutoOpenBar")

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local type = type
local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local tostring = tostring
local floor = math.floor
local ceil = math.ceil
local min = math.min
local max = math.max
local lower = string.lower
local gsub = string.gsub
local tinsert = table.insert
local tsort = table.sort
local unpack = unpack
local InCombatLockdown = InCombatLockdown
local UIParent = UIParent
local CreateFrame = CreateFrame
local hooksecurefunc = hooksecurefunc

local C_Container = C_Container
local C_Item = C_Item
local C_TooltipInfo = C_TooltipInfo
local C_ToyBox = C_ToyBox
local C_MountJournal = C_MountJournal
local C_PetJournal = C_PetJournal
local PlayerHasToy = PlayerHasToy
local Enum = _G.Enum
local issecretvalue = _G.issecretvalue

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local MODULE_TITLE = "Auto Open Bar"
local MOVER_FRAME_NAME = "RefineUI_AutoOpenBarMover"
local BAR_FRAME_NAME = "RefineUI_AutoOpenBar"
local CATEGORY_MANAGER_FRAME_NAME = "RefineUI_AutoOpenBarCategoryManager"

local CATEGORY_ROW_HEIGHT = 24
local CATEGORY_ROW_SPACING = 2

local ENABLED_BG = { 0.09, 0.19, 0.13, 0.78 }
local DISABLED_BG = { 0.22, 0.1, 0.11, 0.7 }
local ENABLED_TEXT = { 0.58, 0.95, 0.62 }
local DISABLED_TEXT = { 0.96, 0.6, 0.6 }
local ENABLED_BORDER = { 0.34, 0.56, 0.38, 0.65 }
local DISABLED_BORDER = { 0.6, 0.34, 0.34, 0.55 }

local BAG_INDEX_START = (Enum and Enum.BagIndex and Enum.BagIndex.Backpack) or 0
local BAG_INDEX_END = _G.NUM_TOTAL_EQUIPPED_BAG_SLOTS
    or (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag)
    or 5

local DIRECTION = {
    RIGHT = "RIGHT",
    LEFT = "LEFT",
    UP = "UP",
    DOWN = "DOWN",
}

local ORIENTATION = {
    HORIZONTAL = "HORIZONTAL",
    VERTICAL = "VERTICAL",
}

local CATEGORY_KEYS = {
    CONTAINERS = "containers",
    MOUNTS = "mounts",
    BATTLE_PETS = "battle_pets",
    COMPANION_PETS = "companion_pets",
    TRADESKILL_RECIPES = "tradeskill_recipes",
    LEARNABLES = "learnables",
    TOYS = "toys",
    TRANSMOG_SETS = "transmog_sets",
    TRANSMOG_ILLUSIONS = "transmog_illusions",
    QUEST_STARTERS = "quest_starters",
}

local FIXED_CATEGORY_DEFINITIONS = {
    { key = CATEGORY_KEYS.CONTAINERS, label = "Openable Containers", defaultEnabled = true },
    { key = CATEGORY_KEYS.MOUNTS, label = "Mounts (Uncollected)", defaultEnabled = true },
    { key = CATEGORY_KEYS.BATTLE_PETS, label = "Battle Pets", defaultEnabled = true },
    { key = CATEGORY_KEYS.COMPANION_PETS, label = "Companion Pets", defaultEnabled = true },
    { key = CATEGORY_KEYS.TRADESKILL_RECIPES, label = "Tradeskill Recipes/Patterns", defaultEnabled = true },
    { key = CATEGORY_KEYS.LEARNABLES, label = "Learnables", defaultEnabled = true },
    { key = CATEGORY_KEYS.TOYS, label = "Unknown Toys", defaultEnabled = true },
    { key = CATEGORY_KEYS.TRANSMOG_SETS, label = "Transmog Sets", defaultEnabled = true },
    { key = CATEGORY_KEYS.TRANSMOG_ILLUSIONS, label = "Transmog Illusions", defaultEnabled = true },
    { key = CATEGORY_KEYS.QUEST_STARTERS, label = "Quest Starters", defaultEnabled = true },
}

local CATEGORY_SCHEMA_VERSION = 3

local ITEM_CLASS_RECIPE = (Enum and Enum.ItemClass and Enum.ItemClass.Recipe) or 9
local ITEM_CLASS_MISCELLANEOUS = (Enum and Enum.ItemClass and Enum.ItemClass.Miscellaneous) or 15
local ITEM_CLASS_BATTLEPET = (Enum and Enum.ItemClass and Enum.ItemClass.Battlepet) or 17
local ITEM_MISC_SUBCLASS_COMPANION_PET = (Enum and Enum.ItemMiscellaneousSubclass and Enum.ItemMiscellaneousSubclass.CompanionPet) or 2
local ITEM_MISC_SUBCLASS_MOUNT = (Enum and Enum.ItemMiscellaneousSubclass and Enum.ItemMiscellaneousSubclass.Mount) or 5

local DEFAULTS = {
    Enable = true,
    ButtonSize = 48,
    ButtonSpacing = 8,
    ButtonLimit = 10,
    Orientation = ORIENTATION.HORIZONTAL,
    Direction = DIRECTION.LEFT,
}

local EVENT_KEY = {
    BAG_UPDATE = "AutoOpenBar:BAG_UPDATE_DELAYED",
    BAG_COOLDOWN = "AutoOpenBar:BAG_UPDATE_COOLDOWN",
    ITEM_INFO = "AutoOpenBar:GET_ITEM_INFO_RECEIVED",
    TOYS_UPDATED = "AutoOpenBar:TOYS_UPDATED",
    NEW_TOY = "AutoOpenBar:NEW_TOY_ADDED",
    ENTERING_WORLD = "AutoOpenBar:PLAYER_ENTERING_WORLD",
    REGEN_ENABLED = "AutoOpenBar:PLAYER_REGEN_ENABLED",
}

local DEBOUNCE_KEY = "AutoOpenBar:RequestUpdate"
local BUTTON_STATE_REGISTRY = "AutoOpenBar:ButtonState"

local LINE_TYPE = {
    LEARNABLE_SPELL = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.LearnableSpell or 6,
    ITEM_SPELL_TRIGGER_LEARN = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.ItemSpellTriggerLearn or 38,
    LEARN_TRANSMOG_SET = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.LearnTransmogSet or 39,
    LEARN_TRANSMOG_ILLUSION = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.LearnTransmogIllusion or 40,
    SPELL_DESCRIPTION = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.SpellDescription or 34,
    DISABLED_LINE = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.DisabledLine or 42,
    ERROR_LINE = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.ErrorLine or 41,
}

local KNOWN_HINT_SOURCES = {
    _G.ITEM_SPELL_KNOWN,
    _G.ERR_PET_SPELL_ALREADY_KNOWN,
    _G.TRANSMOGRIFY_TOOLTIP_APPEARANCE_KNOWN,
    "already known",
    "collected",
}

----------------------------------------------------------------------------------------
-- State / Registries
----------------------------------------------------------------------------------------
local ButtonState = RefineUI:CreateDataRegistry(BUTTON_STATE_REGISTRY, "k")
local buttons = {}

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local function GetButtonState(button)
    if not button then
        return nil
    end

    local state = ButtonState[button]
    if not state then
        state = {}
        ButtonState[button] = state
    end

    return state
end

local function NormalizeTooltipText(text)
    if issecretvalue and issecretvalue(text) then
        return nil
    end

    if type(text) ~= "string" then
        return nil
    end

    local normalized = gsub(text, "|c%x%x%x%x%x%x%x%x", "")
    normalized = gsub(normalized, "|r", "")
    normalized = gsub(normalized, "%%s", "")
    normalized = lower(normalized)

    if normalized == "" then
        return nil
    end

    return normalized
end

local function ResolveRelativeFrame(relativeTo)
    if type(relativeTo) == "string" then
        return _G[relativeTo] or UIParent
    end
    return relativeTo or UIParent
end

local function GetDefaultPosition()
    local defaultPos = RefineUI.Positions and RefineUI.Positions[MOVER_FRAME_NAME]
    if type(defaultPos) ~= "table" then
        return "BOTTOMRIGHT", _G.ChatFrame1 or UIParent, "TOPRIGHT", 0, 6
    end

    local point, relativeTo, relativePoint, x, y = unpack(defaultPos)
    return point or "BOTTOMRIGHT", ResolveRelativeFrame(relativeTo), relativePoint or point or "BOTTOMRIGHT", x or 0, y or 0
end

local function GetDefaultDirectionForOrientation(orientation)
    if orientation == ORIENTATION.VERTICAL then
        return DIRECTION.DOWN
    end
    return DIRECTION.LEFT
end

local function NormalizeGrowthDirection(orientation, direction)
    if orientation == ORIENTATION.VERTICAL then
        if direction ~= DIRECTION.UP and direction ~= DIRECTION.DOWN then
            return GetDefaultDirectionForOrientation(orientation)
        end
        return direction
    end

    if direction ~= DIRECTION.LEFT and direction ~= DIRECTION.RIGHT then
        return GetDefaultDirectionForOrientation(orientation)
    end
    return direction
end

local function GetGrowthDirectionOptions(orientation)
    if orientation == ORIENTATION.VERTICAL then
        return {
            { text = "Down", value = DIRECTION.DOWN },
            { text = "Up", value = DIRECTION.UP },
        }
    end

    return {
        { text = "Right", value = DIRECTION.RIGHT },
        { text = "Left", value = DIRECTION.LEFT },
    }
end

local function UpdateCategoryRowVisual(row, enabled)
    if not row or not row.bg or not row.text then
        return
    end

    local bg = enabled and ENABLED_BG or DISABLED_BG
    local text = enabled and ENABLED_TEXT or DISABLED_TEXT
    local border = enabled and ENABLED_BORDER or DISABLED_BORDER

    row.bg:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
    row.text:SetTextColor(text[1], text[2], text[3])
    if row.order then
        row.order:SetTextColor(text[1], text[2], text[3], 0.9)
    end
    if row.border then
        row.border:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
    end
end
----------------------------------------------------------------------------------------
-- Config
----------------------------------------------------------------------------------------
function AutoOpenBar:GetConfig()
    Config.Automation = Config.Automation or {}
    Config.Automation.AutoOpenBar = Config.Automation.AutoOpenBar or {}

    local cfg = Config.Automation.AutoOpenBar

    if cfg.Enable == nil then
        cfg.Enable = DEFAULTS.Enable
    end

    local buttonSize = tonumber(cfg.ButtonSize) or DEFAULTS.ButtonSize
    if buttonSize < 20 then
        buttonSize = 20
    elseif buttonSize > 64 then
        buttonSize = 64
    end
    cfg.ButtonSize = floor(buttonSize + 0.5)

    local buttonSpacing = tonumber(cfg.ButtonSpacing) or DEFAULTS.ButtonSpacing
    if buttonSpacing < 0 then
        buttonSpacing = 0
    elseif buttonSpacing > 20 then
        buttonSpacing = 20
    end
    cfg.ButtonSpacing = floor(buttonSpacing + 0.5)

    local buttonLimit = tonumber(cfg.ButtonLimit) or DEFAULTS.ButtonLimit
    if buttonLimit < 1 then
        buttonLimit = 1
    elseif buttonLimit > 20 then
        buttonLimit = 20
    end
    cfg.ButtonLimit = floor(buttonLimit + 0.5)

    if cfg.Orientation == nil then
        if cfg.Direction == DIRECTION.UP or cfg.Direction == DIRECTION.DOWN then
            cfg.Orientation = ORIENTATION.VERTICAL
        else
            cfg.Orientation = DEFAULTS.Orientation
        end
    end

    if cfg.Orientation ~= ORIENTATION.HORIZONTAL and cfg.Orientation ~= ORIENTATION.VERTICAL then
        cfg.Orientation = DEFAULTS.Orientation
    end

    cfg.Direction = NormalizeGrowthDirection(cfg.Orientation, cfg.Direction)

    if cfg.ShowQuestStarters == nil then
        cfg.ShowQuestStarters = true
    end

    if type(cfg.CategoryOrder) ~= "table" then
        cfg.CategoryOrder = {}
    end
    if type(cfg.CategoryEnabled) ~= "table" then
        cfg.CategoryEnabled = {}
    end
    if type(cfg.CategorySchemaVersion) ~= "number" then
        cfg.CategorySchemaVersion = 0
    end

    return cfg
end

----------------------------------------------------------------------------------------
-- Category Model
----------------------------------------------------------------------------------------
function AutoOpenBar:GetCategoryDefaultEnabled(definition)
    if not definition then
        return true
    end
    return definition.defaultEnabled ~= false
end

function AutoOpenBar:BuildCategoryDefinitions()
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

function AutoOpenBar:GetCategoryDefinitions()
    return self:BuildCategoryDefinitions()
end

function AutoOpenBar:GetCategoryByKey(key)
    if not key then
        return nil
    end

    self:BuildCategoryDefinitions()
    return self.categoryByKey and self.categoryByKey[key] or nil
end

function AutoOpenBar:NormalizeCategoryOrder()
    local cfg = self:GetConfig()
    local enabled = {}
    local disabled = {}

    for _, key in ipairs(cfg.CategoryOrder) do
        if self:GetCategoryByKey(key) then
            if cfg.CategoryEnabled[key] == false then
                tinsert(disabled, key)
            else
                tinsert(enabled, key)
            end
        end
    end

    cfg.CategoryOrder = {}
    for _, key in ipairs(enabled) do
        tinsert(cfg.CategoryOrder, key)
    end
    for _, key in ipairs(disabled) do
        tinsert(cfg.CategoryOrder, key)
    end

    self.categoryOrderIndex = {}
    for index, key in ipairs(cfg.CategoryOrder) do
        self.categoryOrderIndex[key] = index
    end
end

function AutoOpenBar:EnsureCategoryConfig()
    if self._categoryConfigInitialized and self.categoryOrderIndex then
        return
    end

    local cfg = self:GetConfig()
    local definitions = self:GetCategoryDefinitions()
    local schemaChanged = cfg.CategorySchemaVersion ~= CATEGORY_SCHEMA_VERSION

    if schemaChanged then
        cfg.CategoryOrder = {}
        cfg.CategoryEnabled = {}
        for _, definition in ipairs(definitions) do
            tinsert(cfg.CategoryOrder, definition.key)
            cfg.CategoryEnabled[definition.key] = self:GetCategoryDefaultEnabled(definition)
        end

        if cfg.ShowQuestStarters == false then
            cfg.CategoryEnabled[CATEGORY_KEYS.QUEST_STARTERS] = false
        end

        cfg.CategorySchemaVersion = CATEGORY_SCHEMA_VERSION
    else
        local previousOrder = cfg.CategoryOrder
        local mergedOrder = {}
        local seen = {}

        for _, key in ipairs(previousOrder) do
            if type(key) == "string" and not seen[key] and self:GetCategoryByKey(key) then
                seen[key] = true
                tinsert(mergedOrder, key)
            end
        end

        for _, definition in ipairs(definitions) do
            local key = definition.key
            if not seen[key] then
                seen[key] = true
                tinsert(mergedOrder, key)
            end

            if cfg.CategoryEnabled[key] == nil then
                cfg.CategoryEnabled[key] = self:GetCategoryDefaultEnabled(definition)
            else
                cfg.CategoryEnabled[key] = cfg.CategoryEnabled[key] and true or false
            end
        end

        cfg.CategoryOrder = mergedOrder
        cfg.CategorySchemaVersion = CATEGORY_SCHEMA_VERSION
    end

    self:NormalizeCategoryOrder()
    self._categoryConfigInitialized = true
end

function AutoOpenBar:GetOrderedCategories(includeDisabled)
    self:EnsureCategoryConfig()

    local cfg = self:GetConfig()
    local ordered = {}

    for _, key in ipairs(cfg.CategoryOrder) do
        local def = self:GetCategoryByKey(key)
        if def then
            local enabled = cfg.CategoryEnabled[key] ~= false
            if includeDisabled or enabled then
                ordered[#ordered + 1] = {
                    key = key,
                    label = def.label,
                    enabled = enabled,
                    definition = def,
                }
            end
        end
    end

    return ordered
end

function AutoOpenBar:IsTrackingCategoryEnabled(categoryKey)
    if not categoryKey then
        return false
    end

    self:EnsureCategoryConfig()
    local cfg = self:GetConfig()
    return cfg.CategoryEnabled[categoryKey] ~= false
end

function AutoOpenBar:SetTrackingCategoryEnabled(categoryKey, enabled)
    if not categoryKey or not self:GetCategoryByKey(categoryKey) then
        return
    end

    self:EnsureCategoryConfig()
    local cfg = self:GetConfig()
    cfg.CategoryEnabled[categoryKey] = enabled and true or false
    self:NormalizeCategoryOrder()

    if self.RefreshCategoryManagerWindow then
        self:RefreshCategoryManagerWindow()
    end
    self:RequestUpdate()
end

function AutoOpenBar:GetCategorySortIndex(categoryKey)
    if not categoryKey then
        return 99999
    end

    self:EnsureCategoryConfig()
    return self.categoryOrderIndex and self.categoryOrderIndex[categoryKey] or 99999
end

function AutoOpenBar:ResetCategoryManagerDefaults()
    local cfg = self:GetConfig()
    local definitions = self:GetCategoryDefinitions()

    cfg.CategoryOrder = {}
    cfg.CategoryEnabled = {}
    for _, definition in ipairs(definitions) do
        tinsert(cfg.CategoryOrder, definition.key)
        cfg.CategoryEnabled[definition.key] = self:GetCategoryDefaultEnabled(definition)
    end

    if cfg.ShowQuestStarters == false then
        cfg.CategoryEnabled[CATEGORY_KEYS.QUEST_STARTERS] = false
    end

    cfg.CategorySchemaVersion = CATEGORY_SCHEMA_VERSION

    self:NormalizeCategoryOrder()

    if self.RefreshCategoryManagerWindow then
        self:RefreshCategoryManagerWindow()
    end
    self:RequestUpdate()
end
----------------------------------------------------------------------------------------
-- Filtering
----------------------------------------------------------------------------------------
function AutoOpenBar:BuildKnownHints()
    self.knownTextHints = {}

    for _, source in ipairs(KNOWN_HINT_SOURCES) do
        local normalized = NormalizeTooltipText(source)
        if normalized then
            self.knownTextHints[normalized] = true
        end
    end

    self.questStarterHint = NormalizeTooltipText(_G.ITEM_STARTS_QUEST)
end

function AutoOpenBar:IsTradeskillRecipeItem(itemID)
    if not itemID or not C_Item or type(C_Item.GetItemInfoInstant) ~= "function" then
        return false
    end

    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
    return classID == ITEM_CLASS_RECIPE
end

function AutoOpenBar:GetItemClassAndSubclass(itemID)
    if not itemID or not C_Item or type(C_Item.GetItemInfoInstant) ~= "function" then
        return nil, nil
    end

    local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    return classID, subClassID
end

function AutoOpenBar:IsUncollectedMountItem(itemID)
    if not itemID or not C_MountJournal or type(C_MountJournal.GetMountFromItem) ~= "function" then
        return false, nil
    end

    local mountID = C_MountJournal.GetMountFromItem(itemID)
    if not mountID then
        return false, nil
    end

    if type(C_MountJournal.GetMountInfoByID) ~= "function" then
        return true, nil
    end

    local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
    return true, isCollected == true
end

function AutoOpenBar:GetPetOwnershipByItem(itemID)
    if not itemID or not C_PetJournal or type(C_PetJournal.GetPetInfoByItemID) ~= "function" then
        return false, nil
    end

    local speciesID, _, _, creatureID = C_PetJournal.GetPetInfoByItemID(itemID)
    if not speciesID and not creatureID then
        return false, nil
    end

    if type(C_PetJournal.GetNumPetsInJournal) == "function" and creatureID then
        local maxAllowed, numPets = C_PetJournal.GetNumPetsInJournal(creatureID)
        if type(numPets) == "number" and type(maxAllowed) == "number" then
            if maxAllowed <= 0 then
                return true, numPets > 0
            end
            return true, numPets >= 1
        end
    end

    return true, nil
end

function AutoOpenBar:HasKnownHint(normalizedText)
    if not normalizedText or type(self.knownTextHints) ~= "table" then
        return false
    end

    for hint in pairs(self.knownTextHints) do
        if normalizedText:find(hint, 1, true) then
            return true
        end
    end

    return false
end

function AutoOpenBar:EvaluateTooltipFlags(bag, slot)
    local flags = {
        hasLearnableLine = false,
        hasLearnableSpellLine = false,
        hasItemSpellTriggerLearnLine = false,
        hasLearnTransmogSetLine = false,
        hasLearnTransmogIllusionLine = false,
        hasQuestStarterLine = false,
    }

    if not C_TooltipInfo or type(C_TooltipInfo.GetBagItem) ~= "function" then
        return flags, false
    end

    local tooltipData = C_TooltipInfo.GetBagItem(bag, slot)
    if not tooltipData or type(tooltipData.lines) ~= "table" then
        return flags, false
    end

    local isAlreadyKnown = false

    for _, lineData in ipairs(tooltipData.lines) do
        local lineType = lineData and lineData.type

        if lineType == LINE_TYPE.LEARNABLE_SPELL then
            flags.hasLearnableLine = true
            flags.hasLearnableSpellLine = true
        elseif lineType == LINE_TYPE.ITEM_SPELL_TRIGGER_LEARN then
            flags.hasLearnableLine = true
            flags.hasItemSpellTriggerLearnLine = true
        elseif lineType == LINE_TYPE.LEARN_TRANSMOG_SET then
            flags.hasLearnableLine = true
            flags.hasLearnTransmogSetLine = true
        elseif lineType == LINE_TYPE.LEARN_TRANSMOG_ILLUSION then
            flags.hasLearnableLine = true
            flags.hasLearnTransmogIllusionLine = true
        elseif lineType == LINE_TYPE.SPELL_DESCRIPTION then
            local normalizedText = NormalizeTooltipText(lineData.leftText)
            if self.questStarterHint and normalizedText and normalizedText:find(self.questStarterHint, 1, true) then
                flags.hasQuestStarterLine = true
            end
        elseif lineType == LINE_TYPE.DISABLED_LINE or lineType == LINE_TYPE.ERROR_LINE then
            local normalizedText = NormalizeTooltipText(lineData.leftText)
            if self:HasKnownHint(normalizedText) then
                isAlreadyKnown = true
            end
        end
    end

    return flags, isAlreadyKnown
end

function AutoOpenBar:GetItemCategoryKey(bag, slot, info)
    if not info or not info.itemID or not info.hyperlink then
        return nil
    end

    if info.hasLoot then
        return CATEGORY_KEYS.CONTAINERS
    end

    local itemID = info.itemID
    local classID, subClassID = self:GetItemClassAndSubclass(itemID)

    local isMountItem, isMountCollected = self:IsUncollectedMountItem(itemID)
    if isMountItem then
        if isMountCollected then
            return nil
        end
        return CATEGORY_KEYS.MOUNTS
    end
    if classID == ITEM_CLASS_MISCELLANEOUS and subClassID == ITEM_MISC_SUBCLASS_MOUNT then
        return CATEGORY_KEYS.MOUNTS
    end

    if C_ToyBox and type(C_ToyBox.GetToyInfo) == "function" and type(PlayerHasToy) == "function" then
        local toyID = C_ToyBox.GetToyInfo(itemID)
        if toyID then
            if PlayerHasToy(itemID) then
                return nil
            end
            return CATEGORY_KEYS.TOYS
        end
    end

    local flags, isAlreadyKnown = self:EvaluateTooltipFlags(bag, slot)
    if isAlreadyKnown then
        return nil
    end

    local isPetItem, isPetCollected = self:GetPetOwnershipByItem(itemID)
    if isPetItem then
        if isPetCollected then
            return nil
        end

        if classID == ITEM_CLASS_BATTLEPET then
            return CATEGORY_KEYS.BATTLE_PETS
        end

        if classID == ITEM_CLASS_MISCELLANEOUS and subClassID == ITEM_MISC_SUBCLASS_COMPANION_PET then
            return CATEGORY_KEYS.COMPANION_PETS
        end

        return CATEGORY_KEYS.BATTLE_PETS
    end
    if classID == ITEM_CLASS_BATTLEPET then
        return CATEGORY_KEYS.BATTLE_PETS
    end
    if classID == ITEM_CLASS_MISCELLANEOUS and subClassID == ITEM_MISC_SUBCLASS_COMPANION_PET then
        return CATEGORY_KEYS.COMPANION_PETS
    end

    if self:IsTradeskillRecipeItem(itemID) then
        return CATEGORY_KEYS.TRADESKILL_RECIPES
    end

    if flags.hasLearnTransmogIllusionLine then
        return CATEGORY_KEYS.TRANSMOG_ILLUSIONS
    end

    if flags.hasLearnTransmogSetLine then
        return CATEGORY_KEYS.TRANSMOG_SETS
    end

    if flags.hasLearnableLine then
        return CATEGORY_KEYS.LEARNABLES
    end

    if flags.hasQuestStarterLine then
        return CATEGORY_KEYS.QUEST_STARTERS
    end

    return nil
end

function AutoOpenBar:ScanBags()
    self:EnsureCategoryConfig()

    local foundItems = {}
    local itemByID = {}

    for bag = BAG_INDEX_START, BAG_INDEX_END do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then
                local categoryKey = self:GetItemCategoryKey(bag, slot, info)
                if categoryKey and self:IsTrackingCategoryEnabled(categoryKey) then
                    local itemID = info.itemID
                    local entry = itemByID[itemID]
                    local stackCount = info.stackCount or 1

                    if entry then
                        entry.count = entry.count + stackCount
                        entry.bag = bag
                        entry.slot = slot
                        entry.link = info.hyperlink or entry.link
                        entry.icon = info.iconFileID or entry.icon
                        entry.quality = info.quality or entry.quality
                        entry.name = info.itemName or entry.name
                    else
                        entry = {
                            itemID = itemID,
                            categoryKey = categoryKey,
                            bag = bag,
                            slot = slot,
                            link = info.hyperlink,
                            icon = info.iconFileID or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)),
                            quality = info.quality or 0,
                            name = info.itemName or tostring(itemID),
                            count = stackCount,
                        }
                        itemByID[itemID] = entry
                        tinsert(foundItems, entry)
                    end
                end
            end
        end
    end

    for _, entry in ipairs(foundItems) do
        if C_Item and C_Item.GetItemCount then
            local totalCount = C_Item.GetItemCount(entry.itemID)
            if type(totalCount) == "number" then
                entry.count = totalCount
            end
        end
    end

    tsort(foundItems, function(a, b)
        local categorySortA = self:GetCategorySortIndex(a.categoryKey)
        local categorySortB = self:GetCategorySortIndex(b.categoryKey)
        if categorySortA ~= categorySortB then
            return categorySortA < categorySortB
        end

        if (a.quality or 0) ~= (b.quality or 0) then
            return (a.quality or 0) > (b.quality or 0)
        end

        local nameA = a.name or ""
        local nameB = b.name or ""
        if nameA ~= nameB then
            return nameA < nameB
        end

        return (a.itemID or 0) < (b.itemID or 0)
    end)

    return foundItems
end
----------------------------------------------------------------------------------------
-- Layout / Rendering
----------------------------------------------------------------------------------------
function AutoOpenBar:GetGridExtents(itemCount)
    local cfg = self:GetConfig()
    local count = (itemCount and itemCount > 0) and itemCount or 1
    local rows, cols

    if cfg.Orientation == ORIENTATION.VERTICAL then
        rows = min(count, cfg.ButtonLimit)
        cols = ceil(count / cfg.ButtonLimit)
    else
        cols = min(count, cfg.ButtonLimit)
        rows = ceil(count / cfg.ButtonLimit)
    end

    return rows, cols
end

function AutoOpenBar:GetFrameDimensions(itemCount)
    local cfg = self:GetConfig()
    local rows, cols = self:GetGridExtents(itemCount)
    local width = cols * (cfg.ButtonSize + cfg.ButtonSpacing) - cfg.ButtonSpacing
    local height = rows * (cfg.ButtonSize + cfg.ButtonSpacing) - cfg.ButtonSpacing
    return width, height
end

function AutoOpenBar:GetButtonPoint(index)
    local cfg = self:GetConfig()
    local idx = index - 1
    local step = cfg.ButtonSize + cfg.ButtonSpacing
    local orientation = cfg.Orientation
    local direction = NormalizeGrowthDirection(orientation, cfg.Direction)
    local col, row

    if orientation == ORIENTATION.HORIZONTAL and direction == DIRECTION.RIGHT then
        col = idx % cfg.ButtonLimit
        row = floor(idx / cfg.ButtonLimit)
        return "TOPLEFT", "TOPLEFT", col * step, -row * step
    elseif orientation == ORIENTATION.HORIZONTAL and direction == DIRECTION.LEFT then
        col = idx % cfg.ButtonLimit
        row = floor(idx / cfg.ButtonLimit)
        return "TOPRIGHT", "TOPRIGHT", -col * step, -row * step
    elseif orientation == ORIENTATION.VERTICAL and direction == DIRECTION.UP then
        row = idx % cfg.ButtonLimit
        col = floor(idx / cfg.ButtonLimit)
        return "BOTTOMLEFT", "BOTTOMLEFT", col * step, row * step
    end

    row = idx % cfg.ButtonLimit
    col = floor(idx / cfg.ButtonLimit)
    return "TOPLEFT", "TOPLEFT", col * step, -row * step
end

function AutoOpenBar:ApplyFrameDimensions(displayCount)
    local width, height = self:GetFrameDimensions(displayCount)

    RefineUI.Size(self.Mover, width, height)
    RefineUI.Size(self.BarFrame, width, height)

    if self.PreviewFrame then
        RefineUI.Size(self.PreviewFrame, width, height)
    end
end

function AutoOpenBar:RefreshMoverVisibility(itemCount)
    local showMover = self.isEditModeActive or itemCount > 0
    if self.Mover then
        self.Mover:SetShown(showMover)
    end

    if self.PreviewFrame then
        self.PreviewFrame:SetShown(self.isEditModeActive and itemCount == 0)
    end
end

function AutoOpenBar:UpdateButtonLayering()
    if InCombatLockdown() then
        return
    end

    local isEditMode = self.isEditModeActive == true
    local moverStrata = (self.Mover and self.Mover.GetFrameStrata and self.Mover:GetFrameStrata()) or "DIALOG"
    local barStrata = isEditMode and "LOW" or moverStrata
    local moverLevel = (self.Mover and self.Mover.GetFrameLevel and self.Mover:GetFrameLevel()) or 1
    local barLevel = isEditMode and 1 or (moverLevel + 1)
    local buttonLevel = barLevel + 1

    if self.BarFrame and self.BarFrame.GetFrameStrata and self.BarFrame.SetFrameStrata then
        if self.BarFrame:GetFrameStrata() ~= barStrata then
            self.BarFrame:SetFrameStrata(barStrata)
        end
    end
    if self.BarFrame and self.BarFrame.GetFrameLevel and self.BarFrame.SetFrameLevel then
        if self.BarFrame:GetFrameLevel() ~= barLevel then
            self.BarFrame:SetFrameLevel(barLevel)
        end
    end

    for index = 1, #buttons do
        local button = buttons[index]
        if button then
            if button.GetFrameStrata and button.SetFrameStrata then
                if button:GetFrameStrata() ~= barStrata then
                    button:SetFrameStrata(barStrata)
                end
            end
            if button.GetFrameLevel and button.SetFrameLevel then
                if button:GetFrameLevel() ~= buttonLevel then
                    button:SetFrameLevel(buttonLevel)
                end
            end
            if button.EnableMouse then
                button:EnableMouse(not isEditMode)
            end
        end
    end

    if self.PreviewFrame then
        if self.PreviewFrame.GetFrameStrata and self.PreviewFrame.SetFrameStrata then
            if self.PreviewFrame:GetFrameStrata() ~= moverStrata then
                self.PreviewFrame:SetFrameStrata(moverStrata)
            end
        end
        if self.PreviewFrame.GetFrameLevel and self.PreviewFrame.SetFrameLevel then
            local previewLevel = moverLevel + 10
            if self.PreviewFrame:GetFrameLevel() ~= previewLevel then
                self.PreviewFrame:SetFrameLevel(previewLevel)
            end
        end
    end
end

function AutoOpenBar:CreateButton(index)
    local button = CreateFrame("Button", "RefineUI_AutoOpenBarButton" .. index, self.BarFrame, "SecureActionButtonTemplate")
    local cfg = self:GetConfig()

    RefineUI.Size(button, cfg.ButtonSize, cfg.ButtonSize)
    RefineUI.SetTemplate(button, "Default")
    RefineUI.StyleButton(button, true)
    button:RegisterForClicks("AnyDown", "AnyUp")

    local state = GetButtonState(button)

    local icon = button:CreateTexture(nil, "ARTWORK")
    RefineUI.SetInside(icon, button, 2, 2)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    state.iconTexture = icon

    local countText = button:CreateFontString(nil, "OVERLAY")
    RefineUI.Point(countText, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 2)
    countText:SetJustifyH("RIGHT")
    RefineUI.Font(countText, 12)
    state.countText = countText

    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(icon)
    cooldown:SetFrameLevel(1)
    if cooldown.EnableMouse then
        cooldown:EnableMouse(false)
    end
    state.cooldown = cooldown

    button:SetScript("OnEnter", function(selfButton)
        local buttonState = GetButtonState(selfButton)
        if not buttonState or not buttonState.itemLink then
            return
        end

        GameTooltip:SetOwner(selfButton, "ANCHOR_RIGHT")
        if type(buttonState.bag) == "number" and type(buttonState.slot) == "number" then
            GameTooltip:SetBagItem(buttonState.bag, buttonState.slot)
        else
            GameTooltip:SetHyperlink(buttonState.itemLink)
        end
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", GameTooltip_Hide)
    button:Hide()

    return button
end

function AutoOpenBar:GetButton(index)
    if not buttons[index] then
        buttons[index] = self:CreateButton(index)
    end
    return buttons[index]
end

local function ClearButton(button)
    if not button then
        return
    end

    local state = GetButtonState(button)
    if state then
        state.itemID = nil
        state.itemLink = nil
        state.bag = nil
        state.slot = nil

        if state.countText then
            state.countText:SetText("")
        end

        if state.cooldown then
            state.cooldown:SetCooldown(0, 0)
        end
    end

    button:SetAttribute("type1", nil)
    button:SetAttribute("item1", nil)
    button:SetAttribute("type2", nil)
    button:SetAttribute("item2", nil)
    button:Hide()
end

function AutoOpenBar:UpdateButtonFromItem(button, index, itemData)
    local cfg = self:GetConfig()
    local point, relativePoint, xOffset, yOffset = self:GetButtonPoint(index)

    RefineUI.Size(button, cfg.ButtonSize, cfg.ButtonSize)
    button:ClearAllPoints()
    button:SetPoint(point, self.BarFrame, relativePoint, xOffset, yOffset)

    local useItem = "item:" .. itemData.itemID
    button:SetAttribute("type1", "item")
    button:SetAttribute("item1", useItem)
    button:SetAttribute("type2", "item")
    button:SetAttribute("item2", useItem)

    local state = GetButtonState(button)
    state.itemID = itemData.itemID
    state.itemLink = itemData.link
    state.bag = itemData.bag
    state.slot = itemData.slot

    if state.iconTexture then
        state.iconTexture:SetTexture(itemData.icon)
    end

    if state.countText then
        if itemData.count and itemData.count > 1 then
            state.countText:SetText(itemData.count)
        else
            state.countText:SetText("")
        end
    end

    if state.cooldown and type(itemData.bag) == "number" and type(itemData.slot) == "number" then
        local startTime, duration = C_Container.GetContainerItemCooldown(itemData.bag, itemData.slot)
        if startTime and duration and duration > 0 then
            state.cooldown:SetCooldown(startTime, duration)
        else
            state.cooldown:SetCooldown(0, 0)
        end
    end

    button:Show()
end

function AutoOpenBar:UpdateVisibleCooldowns()
    for i = 1, #buttons do
        local button = buttons[i]
        if button and button:IsShown() then
            local state = GetButtonState(button)
            if state and state.cooldown and type(state.bag) == "number" and type(state.slot) == "number" then
                local startTime, duration = C_Container.GetContainerItemCooldown(state.bag, state.slot)
                if startTime and duration and duration > 0 then
                    state.cooldown:SetCooldown(startTime, duration)
                else
                    state.cooldown:SetCooldown(0, 0)
                end
            end
        end
    end
end

function AutoOpenBar:UpdateBar()
    if not self.Mover or not self.BarFrame then
        return
    end

    if InCombatLockdown() then
        self.pendingCombatRefresh = true
        return
    end

    local items = self:ScanBags()
    local itemCount = #items
    self.lastItemCount = itemCount

    local displayCount = itemCount
    if self.isEditModeActive and displayCount == 0 then
        displayCount = 1
    end

    self:ApplyFrameDimensions(displayCount)

    for i = 1, #buttons do
        ClearButton(buttons[i])
    end

    for index, itemData in ipairs(items) do
        local button = self:GetButton(index)
        self:UpdateButtonFromItem(button, index, itemData)
    end

    self:UpdateButtonLayering()
    self:RefreshMoverVisibility(itemCount)
end

function AutoOpenBar:RequestUpdate()
    if self:GetConfig().Enable == false then
        return
    end

    RefineUI:Debounce(DEBOUNCE_KEY, 0.05, function()
        self:UpdateBar()
    end)
end
----------------------------------------------------------------------------------------
-- Category Manager
----------------------------------------------------------------------------------------
function AutoOpenBar:IsSettingsDialogForAutoOpenBar(selection)
    local lib = RefineUI.LibEditMode
    local dialog = lib and lib.internal and lib.internal.dialog
    local activeSelection = selection or (dialog and dialog.selection)
    return activeSelection and self.Mover and activeSelection.parent == self.Mover
end

function AutoOpenBar:EnsureCategoryManagerWindow()
    if self.CategoryManagerWindow then
        return self.CategoryManagerWindow
    end

    local window = CreateFrame("Frame", CATEGORY_MANAGER_FRAME_NAME, UIParent, "ResizeLayoutFrame")
    window:SetFrameStrata("DIALOG")
    window:SetFrameLevel(220)
    window:SetSize(300, 350)
    window.widthPadding = 40
    window.heightPadding = 40
    window:Hide()
    window:EnableMouse(true)

    local border = CreateFrame("Frame", nil, window, "DialogBorderTranslucentTemplate")
    border.ignoreInLayout = true
    window.Border = border

    local closeButton = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT")
    closeButton.ignoreInLayout = true
    closeButton:HookScript("OnClick", function()
        AutoOpenBar:HideCategoryManagerWindow()
    end)
    window.Close = closeButton

    local title = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Tracked Categories")
    window.Title = title

    local subtitle = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", window, "TOPLEFT", 14, -36)
    subtitle:SetPoint("TOPRIGHT", window, "TOPRIGHT", -36, -36)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetJustifyV("TOP")
    subtitle:SetText("Toggle which item categories appear on the Auto Open Bar.")
    window.Subtitle = subtitle

    local divider = window:CreateTexture(nil, "ARTWORK")
    divider:SetTexture([[Interface\FriendsFrame\UI-FriendsFrame-OnlineDivider]])
    divider:SetSize(330, 16)
    divider:SetPoint("TOP", subtitle, "BOTTOM", 0, -2)
    window.Divider = divider

    local listContainer = CreateFrame("Frame", nil, window, "InsetFrameTemplate")
    listContainer:SetPoint("TOPLEFT", window, "TOPLEFT", 12, -66)
    listContainer:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -12, 44)
    window.ListContainer = listContainer

    local scroll = CreateFrame("ScrollFrame", nil, listContainer, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", listContainer, "TOPLEFT", 5, -5)
    scroll:SetPoint("BOTTOMRIGHT", listContainer, "BOTTOMRIGHT", -27, 5)
    scroll:EnableMouseWheel(true)
    window.Scroll = scroll

    local content = CreateFrame("Frame", nil, scroll)
    content:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    window.Content = content
    window.Rows = {}

    local resetButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    resetButton:SetSize(130, 22)
    resetButton:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -14, 14)
    resetButton:SetText("Reset to Default")
    resetButton:SetScript("OnClick", function()
        AutoOpenBar:ResetCategoryManagerDefaults()
    end)
    window.ResetButton = resetButton

    local function HandleMouseWheel(_, delta)
        local step = (CATEGORY_ROW_HEIGHT + CATEGORY_ROW_SPACING) * 2
        local current = scroll:GetVerticalScroll() or 0
        local maxOffset = scroll:GetVerticalScrollRange() or 0
        local nextOffset = current - (delta * step)

        if nextOffset < 0 then
            nextOffset = 0
        elseif nextOffset > maxOffset then
            nextOffset = maxOffset
        end

        scroll:SetVerticalScroll(nextOffset)
    end

    listContainer:EnableMouseWheel(true)
    listContainer:SetScript("OnMouseWheel", HandleMouseWheel)
    content:EnableMouseWheel(true)
    content:SetScript("OnMouseWheel", HandleMouseWheel)
    scroll:SetScript("OnMouseWheel", HandleMouseWheel)

    self.CategoryManagerWindow = window
    return window
end

function AutoOpenBar:RefreshCategoryManagerWindow()
    local window = self:EnsureCategoryManagerWindow()
    local categories = self:GetOrderedCategories(true)
    local rows = window.Rows
    local yOffset = 0

    for index, category in ipairs(categories) do
        local row = rows[index]
        if not row then
            row = CreateFrame("Button", nil, window.Content)
            row:SetHeight(CATEGORY_ROW_HEIGHT)
            row:RegisterForClicks("LeftButtonUp")
            row:EnableMouse(true)

            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()

            row.border = CreateFrame("Frame", nil, row, "BackdropTemplate")
            row.border:SetAllPoints()
            row.border:SetBackdrop({
                bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
                edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]],
                edgeSize = 10,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            row.border:SetBackdropColor(0, 0, 0, 0)

            row.order = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.order:SetPoint("LEFT", 10, 0)
            row.order:SetWidth(24)
            row.order:SetJustifyH("CENTER")

            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.text:SetPoint("LEFT", row.order, "RIGHT", 6, 0)
            row.text:SetPoint("RIGHT", row, "RIGHT", -34, 0)
            row.text:SetJustifyH("LEFT")

            row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
            row.highlight:SetAllPoints()
            row.highlight:SetAtlas("Options_List_Hover")
            row.highlight:SetAlpha(0.3)

            row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            row.check:SetPoint("RIGHT", -8, 0)
            row.check:SetScript("OnClick", function(checkSelf)
                local parent = checkSelf:GetParent()
                AutoOpenBar:SetTrackingCategoryEnabled(parent.categoryKey, checkSelf:GetChecked() and true or false)
            end)

            row:SetScript("OnClick", function(rowSelf)
                if rowSelf.check and rowSelf.check:IsMouseOver() then
                    return
                end

                local nextValue = not rowSelf.check:GetChecked()
                rowSelf.check:SetChecked(nextValue)
                AutoOpenBar:SetTrackingCategoryEnabled(rowSelf.categoryKey, nextValue)
            end)

            rows[index] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", window.Content, "TOPLEFT", 0, -yOffset)
        row:SetPoint("TOPRIGHT", window.Content, "TOPRIGHT", -2, -yOffset)
        yOffset = yOffset + CATEGORY_ROW_HEIGHT + CATEGORY_ROW_SPACING

        row.order:SetText(("%d."):format(index))
        row.categoryKey = category.key
        row.text:SetText(category.label)
        row.check:SetChecked(category.enabled)
        row.check:Enable()

        UpdateCategoryRowVisual(row, category.enabled)
        row:Show()
    end

    for index = #categories + 1, #rows do
        rows[index]:Hide()
        rows[index].categoryKey = nil
    end

    local contentWidth = max(220, ((window.ListContainer and window.ListContainer:GetWidth()) or 0) - 38)
    if yOffset < 1 then
        yOffset = 1
    end

    window.Content:SetSize(contentWidth, yOffset)
    if window.Scroll and window.Scroll.UpdateScrollChildRect then
        window.Scroll:UpdateScrollChildRect()
    end
end

function AutoOpenBar:HideCategoryManagerWindow()
    if self.CategoryManagerWindow then
        self.CategoryManagerWindow:Hide()
    end
end

function AutoOpenBar:RefreshCategoryManagerVisibility(selection)
    local lib = RefineUI.LibEditMode
    local dialog = lib and lib.internal and lib.internal.dialog

    if not self.isEditModeActive then
        self:HideCategoryManagerWindow()
        return
    end

    if not dialog or not dialog:IsShown() or not self:IsSettingsDialogForAutoOpenBar(selection) then
        self:HideCategoryManagerWindow()
        return
    end

    local window = self:EnsureCategoryManagerWindow()
    window:ClearAllPoints()
    window:SetFrameStrata(dialog:GetFrameStrata() or "DIALOG")
    window:SetFrameLevel((dialog:GetFrameLevel() or 200) + 10)
    window:SetWidth(dialog:GetWidth() or 300)
    window:SetHeight(dialog:GetHeight() or 350)
    window:SetPoint("TOPRIGHT", dialog, "TOPLEFT", -8, 0)

    self:RefreshCategoryManagerWindow()
    window:Show()
end

function AutoOpenBar:HookCategoryManagerToDialog()
    if self._categoryDialogHooked then
        return
    end

    local lib = RefineUI.LibEditMode
    local dialog = lib and lib.internal and lib.internal.dialog
    if not dialog then
        return
    end

    hooksecurefunc(dialog, "Update", function(_, selection)
        AutoOpenBar:RefreshCategoryManagerVisibility(selection)
    end)

    dialog:HookScript("OnShow", function()
        AutoOpenBar:RefreshCategoryManagerVisibility()
    end)

    dialog:HookScript("OnHide", function()
        AutoOpenBar:HideCategoryManagerWindow()
    end)

    self._categoryDialogHooked = true
end
----------------------------------------------------------------------------------------
-- Edit Mode
----------------------------------------------------------------------------------------
function AutoOpenBar:RegisterEditModeSettings()
    if self._editModeSettingsRegistered or not RefineUI.LibEditMode or not RefineUI.LibEditMode.SettingType then
        return
    end

    local settingType = RefineUI.LibEditMode.SettingType
    local settings = {}

    settings[#settings + 1] = {
        kind = settingType.Dropdown,
        name = "Orientation",
        default = DEFAULTS.Orientation,
        values = {
            { text = "Horizontal", value = ORIENTATION.HORIZONTAL },
            { text = "Vertical", value = ORIENTATION.VERTICAL },
        },
        get = function()
            return self:GetConfig().Orientation
        end,
        set = function(_, value)
            local cfg = self:GetConfig()
            if value ~= ORIENTATION.HORIZONTAL and value ~= ORIENTATION.VERTICAL then
                value = DEFAULTS.Orientation
            end
            cfg.Orientation = value
            cfg.Direction = NormalizeGrowthDirection(cfg.Orientation, cfg.Direction)
            self:RequestUpdate()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.Slider,
        name = "Button Size",
        default = DEFAULTS.ButtonSize,
        minValue = 20,
        maxValue = 64,
        valueStep = 1,
        get = function()
            return self:GetConfig().ButtonSize
        end,
        set = function(_, value)
            local cfg = self:GetConfig()
            local size = tonumber(value) or DEFAULTS.ButtonSize
            if size < 20 then
                size = 20
            elseif size > 64 then
                size = 64
            end
            cfg.ButtonSize = floor(size + 0.5)
            self:RequestUpdate()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.Slider,
        name = "Button Spacing",
        default = DEFAULTS.ButtonSpacing,
        minValue = 0,
        maxValue = 20,
        valueStep = 1,
        get = function()
            return self:GetConfig().ButtonSpacing
        end,
        set = function(_, value)
            local cfg = self:GetConfig()
            local spacing = tonumber(value) or DEFAULTS.ButtonSpacing
            if spacing < 0 then
                spacing = 0
            elseif spacing > 20 then
                spacing = 20
            end
            cfg.ButtonSpacing = floor(spacing + 0.5)
            self:RequestUpdate()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.Slider,
        name = "Buttons Per Line",
        default = DEFAULTS.ButtonLimit,
        minValue = 1,
        maxValue = 20,
        valueStep = 1,
        get = function()
            return self:GetConfig().ButtonLimit
        end,
        set = function(_, value)
            local cfg = self:GetConfig()
            local limit = tonumber(value) or DEFAULTS.ButtonLimit
            if limit < 1 then
                limit = 1
            elseif limit > 20 then
                limit = 20
            end
            cfg.ButtonLimit = floor(limit + 0.5)
            self:RequestUpdate()
        end,
    }

    settings[#settings + 1] = {
        kind = settingType.Dropdown,
        name = "Growth Direction",
        default = DEFAULTS.Direction,
        generator = function(_, rootDescription)
            local cfg = self:GetConfig()
            local options = GetGrowthDirectionOptions(cfg.Orientation)
            for _, option in ipairs(options) do
                rootDescription:CreateRadio(
                    option.text,
                    function(data)
                        return cfg.Direction == data.value
                    end,
                    function(data)
                        cfg.Direction = NormalizeGrowthDirection(cfg.Orientation, data.value)
                        self:RequestUpdate()
                    end,
                    { value = option.value }
                )
            end
        end,
        get = function()
            local cfg = self:GetConfig()
            cfg.Direction = NormalizeGrowthDirection(cfg.Orientation, cfg.Direction)
            return cfg.Direction
        end,
        set = function(_, value)
            local cfg = self:GetConfig()
            cfg.Direction = NormalizeGrowthDirection(cfg.Orientation, value)
            self:RequestUpdate()
        end,
    }

    self._editModeSettings = settings
    self._editModeSettingsRegistered = true
end

function AutoOpenBar:RegisterEditModeFrame()
    if self._editModeFrameRegistered or not self.Mover or not RefineUI.LibEditMode or type(RefineUI.LibEditMode.AddFrame) ~= "function" then
        return
    end

    local defaultPoint, _, _, defaultX, defaultY = GetDefaultPosition()
    RefineUI.LibEditMode:AddFrame(self.Mover, function(_, _, point, x, y)
        local cfg = self:GetConfig()
        cfg.Position = cfg.Position or {}
        cfg.Position[1], cfg.Position[2], cfg.Position[3], cfg.Position[4], cfg.Position[5] = point, "UIParent", point, x, y
    end, {
        point = defaultPoint,
        x = defaultX,
        y = defaultY,
    }, MODULE_TITLE)
    self._editModeFrameRegistered = true

    if self._editModeSettings and not self._editModeSettingsAttached and type(RefineUI.LibEditMode.AddFrameSettings) == "function" then
        RefineUI.LibEditMode:AddFrameSettings(self.Mover, self._editModeSettings)
        self._editModeSettingsAttached = true
    end
end

function AutoOpenBar:RegisterEditModeCallbacks()
    if self._editModeCallbacksRegistered or not RefineUI.LibEditMode or type(RefineUI.LibEditMode.RegisterCallback) ~= "function" then
        return
    end

    RefineUI.LibEditMode:RegisterCallback("enter", function()
        self.isEditModeActive = true
        self:UpdateButtonLayering()
        self:RequestUpdate()
        self:RefreshCategoryManagerVisibility()
    end)

    RefineUI.LibEditMode:RegisterCallback("exit", function()
        self.isEditModeActive = false
        self:HideCategoryManagerWindow()
        self:UpdateButtonLayering()
        self:RequestUpdate()
    end)

    self._editModeCallbacksRegistered = true

    if type(RefineUI.LibEditMode.IsInEditMode) == "function" and RefineUI.LibEditMode:IsInEditMode() then
        self.isEditModeActive = true
        self:UpdateButtonLayering()
        self:RequestUpdate()
        self:RefreshCategoryManagerVisibility()
    end
end

----------------------------------------------------------------------------------------
-- Frame Setup
----------------------------------------------------------------------------------------
function AutoOpenBar:EnsureFrames()
    local mover = self.Mover or _G[MOVER_FRAME_NAME]
    if not mover then
        mover = CreateFrame("Frame", MOVER_FRAME_NAME, UIParent)
        mover:SetFrameStrata("DIALOG")
        mover:SetClampedToScreen(true)
    end
    self.Mover = mover

    local barFrame = self.BarFrame or _G[BAR_FRAME_NAME]
    if not barFrame then
        barFrame = CreateFrame("Frame", BAR_FRAME_NAME, mover, "SecureHandlerStateTemplate")
        barFrame:SetPoint("TOPLEFT", mover, "TOPLEFT")
    end
    self.BarFrame = barFrame

    if not self.PreviewFrame then
        local preview = CreateFrame("Frame", nil, mover)
        preview:SetPoint("TOPLEFT", mover, "TOPLEFT")
        preview:SetFrameStrata("DIALOG")
        preview:SetFrameLevel((mover:GetFrameLevel() or 1) + 5)
        preview:EnableMouse(false)
        RefineUI.SetTemplate(preview, "Transparent")

        local text = preview:CreateFontString(nil, "OVERLAY")
        text:SetPoint("CENTER", preview, "CENTER")
        text:SetJustifyH("CENTER")
        RefineUI.Font(text, 11)
        text:SetText(MODULE_TITLE)
        preview.text = text
        preview:Hide()

        self.PreviewFrame = preview
    end

    self:UpdateButtonLayering()
end

function AutoOpenBar:ApplyMoverPosition()
    if not self.Mover then
        return
    end

    local cfg = self:GetConfig()
    local pos = cfg.Position

    if type(pos) == "table" and type(pos[1]) == "string" then
        local point, relativeTo, relativePoint, x, y = unpack(pos)
        self.Mover:ClearAllPoints()
        self.Mover:SetPoint(point, ResolveRelativeFrame(relativeTo), relativePoint or point, x or 0, y or 0)
        return
    end

    local point, relativeTo, relativePoint, x, y = GetDefaultPosition()
    self.Mover:ClearAllPoints()
    self.Mover:SetPoint(point, relativeTo, relativePoint, x, y)
end

----------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------
function AutoOpenBar:OnEnable()
    local cfg = self:GetConfig()
    if cfg.Enable == false then
        if self.Mover then
            self.Mover:Hide()
        end
        self:HideCategoryManagerWindow()
        return
    end

    if not C_Container or type(C_Container.GetContainerItemInfo) ~= "function" then
        self:Error("Container APIs are unavailable.")
        return
    end

    self.pendingCombatRefresh = false
    self.lastItemCount = 0
    self.isEditModeActive = false
    self._categoryConfigInitialized = nil

    self:EnsureCategoryConfig()
    self:BuildKnownHints()
    self:EnsureFrames()
    self:ApplyMoverPosition()
    self:RegisterEditModeSettings()
    self:RegisterEditModeFrame()
    self:RegisterEditModeCallbacks()
    self:HookCategoryManagerToDialog()

    RefineUI:RegisterEventCallback("BAG_UPDATE_DELAYED", function()
        self:RequestUpdate()
    end, EVENT_KEY.BAG_UPDATE)

    RefineUI:RegisterEventCallback("BAG_UPDATE_COOLDOWN", function()
        self:UpdateVisibleCooldowns()
    end, EVENT_KEY.BAG_COOLDOWN)

    RefineUI:RegisterEventCallback("GET_ITEM_INFO_RECEIVED", function()
        self:RequestUpdate()
    end, EVENT_KEY.ITEM_INFO)

    RefineUI:RegisterEventCallback("TOYS_UPDATED", function()
        self:RequestUpdate()
    end, EVENT_KEY.TOYS_UPDATED)

    RefineUI:RegisterEventCallback("NEW_TOY_ADDED", function()
        self:RequestUpdate()
    end, EVENT_KEY.NEW_TOY)

    RefineUI:RegisterEventCallback("PLAYER_ENTERING_WORLD", function()
        self:RequestUpdate()
    end, EVENT_KEY.ENTERING_WORLD)

    RefineUI:RegisterEventCallback("PLAYER_REGEN_ENABLED", function()
        if self.pendingCombatRefresh then
            self.pendingCombatRefresh = false
            self:RequestUpdate()
        end
    end, EVENT_KEY.REGEN_ENABLED)

    self:RequestUpdate()
end
