
----------------------------------------------------------------------------------------
-- AutoOpenBar for RefineUI
-- Description: Automatically surfaces openable containers and learnable bag items.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local AutoOpenBar = RefineUI:RegisterModule("AutoOpenBar", function(cfg)
    local automation = cfg.Automation
    local settings = type(automation) == "table" and automation.AutoOpenBar
    return not (type(settings) == "table" and settings.Enable == false)
end)

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local type = type
local ipairs = ipairs
local tonumber = tonumber
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
local C_QuestLog = C_QuestLog
local C_SpellBook = C_SpellBook
local C_TooltipInfo = C_TooltipInfo
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
    DECOR = "decor",
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

local CATEGORY_DEFINITIONS = {
    { key = CATEGORY_KEYS.CONTAINERS, label = "Openable Containers" },
    { key = CATEGORY_KEYS.DECOR, label = "Decor" },
    { key = CATEGORY_KEYS.MOUNTS, label = "Mounts (Uncollected)" },
    { key = CATEGORY_KEYS.BATTLE_PETS, label = "Battle Pets" },
    { key = CATEGORY_KEYS.COMPANION_PETS, label = "Companion Pets" },
    { key = CATEGORY_KEYS.TRADESKILL_RECIPES, label = "Tradeskill Recipes/Patterns" },
    { key = CATEGORY_KEYS.LEARNABLES, label = "Learnables" },
    { key = CATEGORY_KEYS.TOYS, label = "Unknown Toys" },
    { key = CATEGORY_KEYS.TRANSMOG_SETS, label = "Transmog Sets" },
    { key = CATEGORY_KEYS.TRANSMOG_ILLUSIONS, label = "Transmog Illusions" },
    { key = CATEGORY_KEYS.QUEST_STARTERS, label = "Quest Starters" },
}

local CATEGORY_BY_KEY = {}
for _, definition in ipairs(CATEGORY_DEFINITIONS) do
    CATEGORY_BY_KEY[definition.key] = definition
end

local CATEGORY_SCHEMA_VERSION = 4

local ITEM_CLASS_RECIPE = (Enum and Enum.ItemClass and Enum.ItemClass.Recipe) or 9
local ITEM_CLASS_MISCELLANEOUS = (Enum and Enum.ItemClass and Enum.ItemClass.Miscellaneous) or 15
local ITEM_CLASS_BATTLEPET = (Enum and Enum.ItemClass and Enum.ItemClass.Battlepet) or 17
local ITEM_CLASS_HOUSING = (Enum and Enum.ItemClass and Enum.ItemClass.Housing) or 20
local ITEM_MISC_SUBCLASS_COMPANION_PET = (Enum and Enum.ItemMiscellaneousSubclass and Enum.ItemMiscellaneousSubclass.CompanionPet) or 2
local ITEM_MISC_SUBCLASS_MOUNT = (Enum and Enum.ItemMiscellaneousSubclass and Enum.ItemMiscellaneousSubclass.Mount) or 5
local ITEM_HOUSING_SUBCLASS_DECOR = (Enum and Enum.ItemHousingSubclass and Enum.ItemHousingSubclass.Decor) or 0

local DEFAULTS = {
    ButtonSize = 36,
    ButtonSpacing = 8,
    ButtonLimit = 10,
    Orientation = ORIENTATION.VERTICAL,
    Direction = DIRECTION.DOWN,
}

-- Anything that can change which bag items are usable or already known.
local UPDATE_EVENTS = {
    "BAG_UPDATE_DELAYED",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_LEVEL_UP",
    "SKILL_LINES_CHANGED",
    "QUEST_ACCEPTED",
    "QUEST_REMOVED",
}

local DEBOUNCE_KEY = "AutoOpenBar:RequestUpdate"
local BUTTON_STATE_REGISTRY = "AutoOpenBar:ButtonState"
local PICK_LOCK_SPELL_ID = 1804

local LINE_TYPE = {
    LEARNABLE_SPELL = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.LearnableSpell or 6,
    ITEM_SPELL_TRIGGER_LEARN = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.ItemSpellTriggerLearn or 38,
    LEARN_TRANSMOG_SET = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.LearnTransmogSet or 39,
    LEARN_TRANSMOG_ILLUSION = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.LearnTransmogIllusion or 40,
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

local LOCKED_TEXT = _G.LOCKED
local NOT_HERE_TEXT = _G.SPELL_FAILED_NOT_HERE

----------------------------------------------------------------------------------------
-- State / Registries
----------------------------------------------------------------------------------------
local ButtonState = RefineUI:CreateDataRegistry(BUTTON_STATE_REGISTRY, "k")
local buttons = {}
-- Item IDs whose class and tooltip can never place them on the bar.
local ignoredItemIDs = {}
-- Item IDs scanned before their data loaded; only these rescan on GET_ITEM_INFO_RECEIVED.
local pendingItemIDs = {}

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

local KNOWN_HINTS = {}
for _, source in ipairs(KNOWN_HINT_SOURCES) do
    KNOWN_HINTS[#KNOWN_HINTS + 1] = NormalizeTooltipText(source)
end

local function ClampRound(value, default, minValue, maxValue)
    return floor(min(max(tonumber(value) or default, minValue), maxValue) + 0.5)
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
        return "TOPLEFT", _G.ChatFrame1 or UIParent, "TOPRIGHT", 2, 0
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
    return Config.Automation.AutoOpenBar
end

function AutoOpenBar:NormalizeConfig()
    local cfg = self:GetConfig()

    cfg.ButtonSize = ClampRound(cfg.ButtonSize, DEFAULTS.ButtonSize, 20, 64)
    cfg.ButtonSpacing = ClampRound(cfg.ButtonSpacing, DEFAULTS.ButtonSpacing, 0, 20)
    cfg.ButtonLimit = ClampRound(cfg.ButtonLimit, DEFAULTS.ButtonLimit, 1, 20)

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

    if type(cfg.CategoryOrder) ~= "table" then
        cfg.CategoryOrder = {}
    end
    if type(cfg.CategoryEnabled) ~= "table" then
        cfg.CategoryEnabled = {}
    end
end

----------------------------------------------------------------------------------------
-- Category Model
----------------------------------------------------------------------------------------
local function ResetCategoryConfig(cfg)
    cfg.CategoryOrder = {}
    cfg.CategoryEnabled = {}
    for _, definition in ipairs(CATEGORY_DEFINITIONS) do
        tinsert(cfg.CategoryOrder, definition.key)
        cfg.CategoryEnabled[definition.key] = true
    end

    if cfg.ShowQuestStarters == false then
        cfg.CategoryEnabled[CATEGORY_KEYS.QUEST_STARTERS] = false
    end

    cfg.CategorySchemaVersion = CATEGORY_SCHEMA_VERSION
end

function AutoOpenBar:NormalizeCategoryOrder()
    local cfg = self:GetConfig()
    local enabled = {}
    local disabled = {}

    for _, key in ipairs(cfg.CategoryOrder) do
        if CATEGORY_BY_KEY[key] then
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
    local cfg = self:GetConfig()

    if cfg.CategorySchemaVersion ~= CATEGORY_SCHEMA_VERSION then
        ResetCategoryConfig(cfg)
    else
        local mergedOrder = {}
        local seen = {}

        for _, key in ipairs(cfg.CategoryOrder) do
            if type(key) == "string" and not seen[key] and CATEGORY_BY_KEY[key] then
                seen[key] = true
                tinsert(mergedOrder, key)
            end
        end

        for _, definition in ipairs(CATEGORY_DEFINITIONS) do
            local key = definition.key
            if not seen[key] then
                seen[key] = true
                tinsert(mergedOrder, key)
            end
            cfg.CategoryEnabled[key] = cfg.CategoryEnabled[key] ~= false
        end

        cfg.CategoryOrder = mergedOrder
    end

    self:NormalizeCategoryOrder()
end

function AutoOpenBar:SetTrackingCategoryEnabled(categoryKey, enabled)
    if not CATEGORY_BY_KEY[categoryKey] then
        return
    end

    self:GetConfig().CategoryEnabled[categoryKey] = enabled and true or false
    self:NormalizeCategoryOrder()
    self:RefreshCategoryManagerWindow()
    self:RequestUpdate()
end

function AutoOpenBar:ResetCategoryManagerDefaults()
    ResetCategoryConfig(self:GetConfig())
    self:NormalizeCategoryOrder()
    self:RefreshCategoryManagerWindow()
    self:RequestUpdate()
end
----------------------------------------------------------------------------------------
-- Filtering
----------------------------------------------------------------------------------------
local function HasKnownHint(text)
    local normalized = NormalizeTooltipText(text)
    if not normalized then
        return false
    end

    for index = 1, #KNOWN_HINTS do
        if normalized:find(KNOWN_HINTS[index], 1, true) then
            return true
        end
    end

    return false
end

-- Blizzard colors unmet requirements red (skill, class, race, level, reputation,
-- specialization, achievement, "already known"). Zone-only restrictions are temporary.
local function IsUnmetRequirementLine(lineData)
    local color = lineData.leftColor
    return color ~= nil and color.r > 0.99 and color.g < 0.2 and color.b < 0.2
        and lineData.leftText ~= NOT_HERE_TEXT
end

-- Returns the tooltip-derived category, whether the player cannot use the item now,
-- and whether it is a locked lockbox.
local function ScanTooltip(bag, slot)
    local tooltipData = C_TooltipInfo.GetBagItem(bag, slot)
    local lines = tooltipData and tooltipData.lines
    if not lines then
        return nil, false, false
    end

    local illusion, transmogSet, learnable, locked

    for _, lineData in ipairs(lines) do
        local lineType = lineData.type

        if lineData.leftText == LOCKED_TEXT then
            locked = true
        elseif IsUnmetRequirementLine(lineData) then
            return nil, true, false
        elseif lineType == LINE_TYPE.LEARN_TRANSMOG_ILLUSION then
            illusion = true
        elseif lineType == LINE_TYPE.LEARN_TRANSMOG_SET then
            transmogSet = true
        elseif lineType == LINE_TYPE.LEARNABLE_SPELL or lineType == LINE_TYPE.ITEM_SPELL_TRIGGER_LEARN then
            learnable = true
        elseif (lineType == LINE_TYPE.DISABLED_LINE or lineType == LINE_TYPE.ERROR_LINE) and HasKnownHint(lineData.leftText) then
            return nil, true, false
        end
    end

    local categoryKey
    if illusion then
        categoryKey = CATEGORY_KEYS.TRANSMOG_ILLUSIONS
    elseif transmogSet then
        categoryKey = CATEGORY_KEYS.TRANSMOG_SETS
    elseif learnable then
        categoryKey = CATEGORY_KEYS.LEARNABLES
    end

    return categoryKey, false, locked == true
end

local function IsDecorItem(itemID, classID, subClassID)
    if classID == ITEM_CLASS_HOUSING and subClassID == ITEM_HOUSING_SUBCLASS_DECOR then
        return true
    end

    local ok, isDecor = pcall(C_Item.IsDecorItem, itemID)
    return ok and isDecor == true
end

local function GetClassCategory(itemID, collectible)
    local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)

    if collectible == "mounts" or (classID == ITEM_CLASS_MISCELLANEOUS and subClassID == ITEM_MISC_SUBCLASS_MOUNT) then
        return CATEGORY_KEYS.MOUNTS
    elseif collectible == "toys" then
        return CATEGORY_KEYS.TOYS
    elseif IsDecorItem(itemID, classID, subClassID) then
        return CATEGORY_KEYS.DECOR
    elseif classID == ITEM_CLASS_MISCELLANEOUS and subClassID == ITEM_MISC_SUBCLASS_COMPANION_PET then
        return CATEGORY_KEYS.COMPANION_PETS
    elseif collectible == "pets" or classID == ITEM_CLASS_BATTLEPET then
        return CATEGORY_KEYS.BATTLE_PETS
    elseif classID == ITEM_CLASS_RECIPE then
        return CATEGORY_KEYS.TRADESKILL_RECIPES
    end
end

-- Returns the category key, plus true for a locked lockbox the player can pick.
local function GetItemCategoryKey(bag, slot, info, canPickLock)
    local itemID = info.itemID
    if ignoredItemIDs[itemID] or not info.hyperlink then
        return nil
    end

    local categoryKey
    if info.hasLoot then
        categoryKey = CATEGORY_KEYS.CONTAINERS
    else
        -- Journal kinds only; learnable transmog is identified by tooltip lines.
        local collectible, _, owned = RefineUI.Collections:ClassifyItem(itemID)
        if owned == true then
            return nil
        end
        categoryKey = GetClassCategory(itemID, collectible)
    end

    local isCached = C_Item.IsItemDataCachedByID(itemID)
    if not isCached then
        pendingItemIDs[itemID] = true
    end

    local tooltipCategory, blocked, locked = ScanTooltip(bag, slot)
    if blocked then
        return nil
    end

    if locked and categoryKey == CATEGORY_KEYS.CONTAINERS then
        if canPickLock then
            return categoryKey, true
        end
        return nil
    end

    categoryKey = categoryKey or tooltipCategory
    if categoryKey then
        return categoryKey
    end

    -- Same rule as Blizzard's bag quest "!" overlay, minus quests already done.
    local questInfo = C_Container.GetContainerItemQuestInfo(bag, slot)
    local questID = questInfo.questID
    if not questID then
        if isCached then
            ignoredItemIDs[itemID] = true
        end
        return nil
    end

    if not questInfo.isActive and not C_QuestLog.IsQuestFlaggedCompleted(questID) then
        return CATEGORY_KEYS.QUEST_STARTERS
    end

    return nil
end

local function SortItems(a, b)
    if a.sortIndex ~= b.sortIndex then
        return a.sortIndex < b.sortIndex
    end
    if a.quality ~= b.quality then
        return a.quality > b.quality
    end
    if a.name ~= b.name then
        return a.name < b.name
    end
    return a.itemID < b.itemID
end

function AutoOpenBar:ScanBags()
    local cfg = self:GetConfig()
    local categoryEnabled = cfg.CategoryEnabled
    local categoryOrderIndex = self.categoryOrderIndex
    local canPickLock = C_SpellBook.IsSpellKnown(PICK_LOCK_SPELL_ID)
    local foundItems = {}
    local itemByKey = {}

    for bag = BAG_INDEX_START, BAG_INDEX_END do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then
                local categoryKey, pickLock = GetItemCategoryKey(bag, slot, info, canPickLock)
                if categoryKey and categoryEnabled[categoryKey] ~= false then
                    local itemID = info.itemID
                    -- Locked copies of a lockbox need a different action than opened ones.
                    local entryKey = pickLock and -itemID or itemID
                    local entry = itemByKey[entryKey]
                    local stackCount = info.stackCount or 1

                    if entry then
                        entry.count = entry.count + stackCount
                    else
                        entry = {
                            itemID = itemID,
                            categoryKey = categoryKey,
                            pickLock = pickLock,
                            sortIndex = categoryOrderIndex[categoryKey],
                            bag = bag,
                            slot = slot,
                            link = info.hyperlink,
                            icon = info.iconFileID,
                            quality = info.quality or 0,
                            name = info.itemName or "",
                            count = stackCount,
                        }
                        itemByKey[entryKey] = entry
                        foundItems[#foundItems + 1] = entry
                    end
                end
            end
        end
    end

    tsort(foundItems, SortItems)
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

local function SetLayer(frame, strata, level)
    if frame:GetFrameStrata() ~= strata then
        frame:SetFrameStrata(strata)
    end
    if frame:GetFrameLevel() ~= level then
        frame:SetFrameLevel(level)
    end
end

function AutoOpenBar:UpdateButtonLayering()
    if InCombatLockdown() then
        return
    end

    local isEditMode = self.isEditModeActive == true
    local moverStrata = self.Mover:GetFrameStrata()
    local moverLevel = self.Mover:GetFrameLevel()
    local barStrata = isEditMode and "LOW" or moverStrata
    local barLevel = isEditMode and 1 or (moverLevel + 1)

    SetLayer(self.BarFrame, barStrata, barLevel)
    for index = 1, #buttons do
        local button = buttons[index]
        SetLayer(button, barStrata, barLevel + 1)
        button:EnableMouse(not isEditMode)
    end
    SetLayer(self.PreviewFrame, moverStrata, moverLevel + 10)
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

-- Left and right click share one action; nil arguments clear it.
local function SetClickAction(button, actionType, item, spell, targetBag, targetSlot)
    button:SetAttribute("type1", actionType)
    button:SetAttribute("type2", actionType)
    button:SetAttribute("item1", item)
    button:SetAttribute("item2", item)
    button:SetAttribute("spell1", spell)
    button:SetAttribute("spell2", spell)
    button:SetAttribute("target-bag", targetBag)
    button:SetAttribute("target-slot", targetSlot)
end

local function UpdateCooldown(state)
    local startTime, duration = C_Container.GetContainerItemCooldown(state.bag, state.slot)
    if duration and duration > 0 then
        state.cooldown:SetCooldown(startTime, duration)
    else
        state.cooldown:SetCooldown(0, 0)
    end
end

local function ClearButton(button)
    local state = GetButtonState(button)
    state.itemLink = nil
    state.bag = nil
    state.slot = nil

    SetClickAction(button, nil)
    button:Hide()
end

function AutoOpenBar:UpdateButtonFromItem(button, index, itemData)
    local cfg = self:GetConfig()
    local point, relativePoint, xOffset, yOffset = self:GetButtonPoint(index)
    local bag, slot = itemData.bag, itemData.slot

    RefineUI.Size(button, cfg.ButtonSize, cfg.ButtonSize)
    button:ClearAllPoints()
    button:SetPoint(point, self.BarFrame, relativePoint, xOffset, yOffset)

    if itemData.pickLock then
        SetClickAction(button, "spell", nil, PICK_LOCK_SPELL_ID, bag, slot)
    elseif itemData.categoryKey == CATEGORY_KEYS.CONTAINERS then
        -- Target the exact slot so a still-locked copy of the same box is never chosen.
        SetClickAction(button, "item", bag .. " " .. slot)
    else
        SetClickAction(button, "item", "item:" .. itemData.itemID)
    end

    local state = GetButtonState(button)
    state.itemLink = itemData.link
    state.bag = bag
    state.slot = slot

    state.iconTexture:SetTexture(itemData.icon)
    state.countText:SetText(itemData.count > 1 and itemData.count or "")
    UpdateCooldown(state)

    button:Show()
end

function AutoOpenBar:UpdateVisibleCooldowns()
    for index = 1, #buttons do
        local button = buttons[index]
        if button:IsShown() then
            UpdateCooldown(GetButtonState(button))
        end
    end
end

function AutoOpenBar:UpdateBar()
    if InCombatLockdown() then
        self.pendingCombatRefresh = true
        return
    end

    local items = self:ScanBags()
    local itemCount = #items

    local displayCount = itemCount
    if self.isEditModeActive and displayCount == 0 then
        displayCount = 1
    end

    self:ApplyFrameDimensions(displayCount)

    for index, itemData in ipairs(items) do
        self:UpdateButtonFromItem(self:GetButton(index), index, itemData)
    end
    for index = itemCount + 1, #buttons do
        ClearButton(buttons[index])
    end

    self:UpdateButtonLayering()
    self:RefreshMoverVisibility(itemCount)
end

function AutoOpenBar:RequestUpdate()
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
    local cfg = self:GetConfig()
    local categoryOrder = cfg.CategoryOrder
    local rows = window.Rows
    local yOffset = 0

    for index, key in ipairs(categoryOrder) do
        local enabled = cfg.CategoryEnabled[key] ~= false
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
        row.categoryKey = key
        row.text:SetText(CATEGORY_BY_KEY[key].label)
        row.check:SetChecked(enabled)
        row.check:Enable()

        UpdateCategoryRowVisual(row, enabled)
        row:Show()
    end

    for index = #categoryOrder + 1, #rows do
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
            cfg.ButtonSize = ClampRound(value, DEFAULTS.ButtonSize, 20, 64)
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
            cfg.ButtonSpacing = ClampRound(value, DEFAULTS.ButtonSpacing, 0, 20)
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
            cfg.ButtonLimit = ClampRound(value, DEFAULTS.ButtonLimit, 1, 20)
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
    self.pendingCombatRefresh = false
    self.isEditModeActive = false

    self:NormalizeConfig()
    self:EnsureCategoryConfig()
    self:EnsureFrames()
    self:ApplyMoverPosition()
    self:RegisterEditModeSettings()
    self:RegisterEditModeFrame()
    self:RegisterEditModeCallbacks()
    self:HookCategoryManagerToDialog()

    local function RequestUpdate()
        self:RequestUpdate()
    end

    for _, event in ipairs(UPDATE_EVENTS) do
        RefineUI:RegisterEventCallback(event, RequestUpdate, "AutoOpenBar:" .. event)
    end

    RefineUI:RegisterEventCallback("GET_ITEM_INFO_RECEIVED", function(_, itemID)
        if pendingItemIDs[itemID] then
            pendingItemIDs[itemID] = nil
            self:RequestUpdate()
        end
    end, "AutoOpenBar:GET_ITEM_INFO_RECEIVED")

    RefineUI:RegisterEventCallback("BAG_UPDATE_COOLDOWN", function()
        self:UpdateVisibleCooldowns()
    end, "AutoOpenBar:BAG_UPDATE_COOLDOWN")

    RefineUI:RegisterEventCallback("PLAYER_REGEN_ENABLED", function()
        if self.pendingCombatRefresh then
            self.pendingCombatRefresh = false
            self:RequestUpdate()
        end
    end, "AutoOpenBar:PLAYER_REGEN_ENABLED")

    -- Mount, pet, toy, and appearance learning changes "already collected" results.
    RefineUI.Collections:Subscribe("AutoOpenBar", RequestUpdate)

    self:RequestUpdate()
end
