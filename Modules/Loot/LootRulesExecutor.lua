----------------------------------------------------------------------------------------
-- LootRules Component: Executor
-- Description: Loot and merchant execution pipelines for evaluated rule actions.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local LootRules = RefineUI:GetModule("LootRules")
if not LootRules then
    return
end

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
local tinsert = table.insert
local tremove = table.remove
local wipe = table.wipe
local tonumber = tonumber
local type = type

local C_Container = C_Container
local C_Item = C_Item
local C_Timer = C_Timer
local C_EquipmentSet = C_EquipmentSet
local C_TransmogCollection = C_TransmogCollection
local C_ToyBox = C_ToyBox
local C_PetJournal = C_PetJournal
local C_MountJournal = C_MountJournal
local GetItemIcon = C_Item and C_Item.GetItemIconByID

local GetLootSlotType = GetLootSlotType
local GetLootSlotLink = GetLootSlotLink
local GetLootSlotInfo = GetLootSlotInfo
local GetNumLootItems = GetNumLootItems
local LootSlot = LootSlot
local CloseLoot = CloseLoot
local GetCursorInfo = GetCursorInfo
local IsUsableItem = IsUsableItem
local GetCVarBool = GetCVarBool
local IsModifiedClick = IsModifiedClick
local GetModifiedClick = GetModifiedClick

local STAGE_LOOT = LootRules.STAGE_LOOT or "LOOT"
local STAGE_SELL = LootRules.STAGE_SELL or "SELL"

local ITEM_BIND_BOE = 2
local ITEM_BIND_WUE = 9
local ITEM_QUALITY_POOR = (Enum and Enum.ItemQuality and Enum.ItemQuality.Poor) or 0
local MAX_BAG_ID = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or 5
local SELL_DELAY_SECONDS = 0.05
local MESSAGE_PREFIX_COLOR = "|cFFFFD200"
local MESSAGE_REASON_COLOR = "|cFFFFFFFF"

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function ScheduleTimer(delay, callback)
    if C_Timer and C_Timer.NewTimer then
        return C_Timer.NewTimer(delay, callback)
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, callback)
    end
    return nil
end

local function GetItemClassEnumValue(...)
    local enum = Enum and Enum.ItemClass
    if type(enum) ~= "table" then
        return nil
    end

    for i = 1, select("#", ...) do
        local key = select(i, ...)
        local value = rawget(enum, key)
        if value ~= nil then
            return value
        end
    end
    return nil
end

local ITEM_CLASS_WEAPON = GetItemClassEnumValue("Weapon")
local ITEM_CLASS_ARMOR = GetItemClassEnumValue("Armor")
local ITEM_CLASS_CONSUMABLE = GetItemClassEnumValue("Consumable")
local ITEM_CLASS_REAGENT = GetItemClassEnumValue("Reagent")
local ITEM_CLASS_TRADEGOODS = GetItemClassEnumValue("Tradegoods", "TradeGoods")
local ITEM_CLASS_RECIPE = GetItemClassEnumValue("Recipe")
local ITEM_CLASS_GEM = GetItemClassEnumValue("Gem")

local function GetItemIDFromLink(link)
    if type(link) ~= "string" then
        return nil
    end
    local itemID = link:match("item:(%d+)")
    return itemID and tonumber(itemID) or nil
end

local function BuildItemIconString(itemID)
    if not itemID or not GetItemIcon then
        return ""
    end
    local icon = GetItemIcon(itemID)
    if not icon then
        return ""
    end
    return ("|T%s:0|t "):format(icon)
end

local function ResolveDisplayItemLink(link, itemID)
    if type(link) == "string" and link ~= "" and link:find("|Hitem:") then
        return link
    end

    local source = link or itemID
    if source and C_Item and C_Item.GetItemInfo then
        local value1, value2 = C_Item.GetItemInfo(source)
        if type(value1) == "table" then
            local info = value1
            local infoLink = info.itemLink or info.hyperlink
            if type(infoLink) == "string" and infoLink ~= "" then
                return infoLink
            end
        elseif type(value2) == "string" and value2 ~= "" then
            return value2
        end
    end

    if type(link) == "string" and link ~= "" then
        return link
    end
    return "Unknown Item"
end

local function PrintItemActionMessage(prefix, itemID, link, reason)
    local iconString = BuildItemIconString(itemID)
    local displayLink = ResolveDisplayItemLink(link, itemID)
    local detail = (type(reason) == "string" and reason ~= "") and reason or nil

    if detail then
        RefineUI:Print("%s%s|r %s%s %s(%s)|r", MESSAGE_PREFIX_COLOR, prefix, iconString, displayLink, MESSAGE_REASON_COLOR, detail)
        return
    end
    RefineUI:Print("%s%s|r %s%s", MESSAGE_PREFIX_COLOR, prefix, iconString, displayLink)
end

local function BuildFilteredLootReasonText(rule)
    local ruleID = rule and rule.id

    if ruleID == "loot_filters_all" then
        return nil
    end
    if type(ruleID) == "string" and ruleID:find("^loot_filter_") then
        return nil
    end

    return "Excluded by Loot Rule"
end

local function PrintFilteredLootMessage(context, rule)
    PrintItemActionMessage("Filtered:", context and context.itemID, context and context.link, BuildFilteredLootReasonText(rule))
end

local function IsForceAutoLootOverrideActive()
    if not IsModifiedClick or not GetCVarBool then
        return false
    end

    local defaultAutoLoot = GetCVarBool("autoLootDefault") and true or false
    local autoLootToggleHeld = IsModifiedClick("AUTOLOOTTOGGLE") and true or false
    return (not defaultAutoLoot) and autoLootToggleHeld
end

function LootRules:GetAutoLootToggleKey()
    if not GetModifiedClick then
        return "NONE"
    end
    local configured = GetModifiedClick("AUTOLOOTTOGGLE")
    if type(configured) ~= "string" or configured == "" then
        return "NONE"
    end
    return configured
end

local function BuildSellReasonText(item)
    local ruleID = item and item.ruleID
    if ruleID == "sell_always_sell_junk" then
        return "Junk"
    end
    if ruleID == "sell_filters_all" then
        return nil
    end
    if type(ruleID) == "string" and ruleID:find("^sell_filter_") then
        return nil
    end
    return "Matched Sell Rule"
end

local function GetItemInfoData(source)
    if source == nil then
        return nil
    end
    if not C_Item or not C_Item.GetItemInfo then
        return nil
    end

    local value1, _, quality, itemLevel, _, itemType, itemSubType, _, itemEquipLoc, _, sellPrice, classID, subClassID, bindType, expansionID = C_Item.GetItemInfo(source)
    if type(value1) == "table" then
        local info = value1
        return {
            quality = info.quality,
            itemLevel = info.currentItemLevel or info.itemLevel or info.baseItemLevel,
            itemType = info.itemType or info.itemClassName,
            itemSubType = info.itemSubType or info.itemSubclassName,
            itemEquipLoc = info.itemEquipLoc or info.inventoryType,
            sellPrice = info.sellPrice,
            classID = info.classID or info.itemClassID,
            subClassID = info.subclassID or info.itemSubClassID or info.subClassID,
            bindType = info.bindType,
            expansionID = info.expansionID or info.expansion,
        }
    end

    return {
        quality = quality,
        itemLevel = itemLevel,
        itemType = itemType,
        itemSubType = itemSubType,
        itemEquipLoc = itemEquipLoc,
        sellPrice = sellPrice,
        classID = classID,
        subClassID = subClassID,
        bindType = bindType,
        expansionID = expansionID,
    }
end

local function FillInstantClassData(source, info)
    if source == nil then
        return
    end
    if not info then
        return
    end
    if info.classID and info.subClassID then
        return
    end
    if not C_Item or not C_Item.GetItemInfoInstant then
        return
    end

    local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(source)
    if not info.classID then
        info.classID = classID
    end
    if not info.subClassID then
        info.subClassID = subClassID
    end
end

local function ResolveRuleCategory(quality, classID, itemType)
    if quality == ITEM_QUALITY_POOR then
        return "junk"
    end

    if classID == ITEM_CLASS_WEAPON or classID == ITEM_CLASS_ARMOR then
        return "equipment"
    end
    if classID == ITEM_CLASS_REAGENT or classID == ITEM_CLASS_TRADEGOODS then
        return "trade_goods"
    end
    if classID == ITEM_CLASS_CONSUMABLE then
        return "consumables"
    end
    if classID == ITEM_CLASS_RECIPE then
        return "recipes"
    end
    if classID == ITEM_CLASS_GEM then
        return "gems"
    end

    if itemType == "Weapon" or itemType == "Armor" then
        return "equipment"
    end
    if itemType == "Trade Goods" or itemType == "Tradeskill" then
        return "trade_goods"
    end
    if itemType == "Consumable" then
        return "consumables"
    end
    if itemType == "Recipe" then
        return "recipes"
    end
    if itemType == "Gem" then
        return "gems"
    end

    return "misc"
end

local function IsUncollectedAppearance(link)
    if not link or not C_TransmogCollection or not C_TransmogCollection.GetItemInfo or not C_TransmogCollection.GetSourceInfo then
        return false
    end

    local sourceID = select(2, C_TransmogCollection.GetItemInfo(link))
    if not sourceID then
        return false
    end

    local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
    return sourceInfo and sourceInfo.isCollected == false
end

local function IsUncollectedToy(itemID)
    if not itemID or not C_ToyBox or not C_ToyBox.GetToyInfo or not C_ToyBox.PlayerHasToy then
        return false
    end
    local toyName = C_ToyBox.GetToyInfo(itemID)
    if not toyName then
        return false
    end
    return C_ToyBox.PlayerHasToy(itemID) ~= true
end

local function IsUncollectedPet(itemID)
    if not itemID or not C_PetJournal or not C_PetJournal.GetPetInfoByItemID or not C_PetJournal.GetNumCollectedInfo then
        return false
    end
    local _, _, _, _, _, _, _, _, _, _, _, _, speciesID = C_PetJournal.GetPetInfoByItemID(itemID)
    if type(speciesID) ~= "number" then
        return false
    end
    local owned = C_PetJournal.GetNumCollectedInfo(speciesID)
    return (owned or 0) <= 0
end

local function IsUncollectedMount(itemID)
    if not itemID or not C_MountJournal or not C_MountJournal.GetMountFromItem or not C_MountJournal.GetMountInfoByID then
        return false
    end
    local mountID = C_MountJournal.GetMountFromItem(itemID)
    if not mountID then
        return false
    end
    local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
    return isCollected ~= true
end

local function IsUncollectedCollectible(link, itemID)
    if IsUncollectedAppearance(link) then
        return true
    end
    if IsUncollectedToy(itemID) then
        return true
    end
    if IsUncollectedPet(itemID) then
        return true
    end
    if IsUncollectedMount(itemID) then
        return true
    end
    return false
end

local function BuildEquipmentSetItemIDLookup()
    local lookup = {}
    if not C_EquipmentSet or not C_EquipmentSet.GetEquipmentSetIDs or not C_EquipmentSet.GetItemIDs then
        return lookup
    end

    local setIDs = C_EquipmentSet.GetEquipmentSetIDs() or {}
    for i = 1, #setIDs do
        local itemIDs = C_EquipmentSet.GetItemIDs(setIDs[i]) or {}
        for _, itemID in pairs(itemIDs) do
            if itemID and itemID > 0 then
                lookup[itemID] = true
            end
        end
    end
    return lookup
end

local function BuildLootItemContext(slot)
    local link = GetLootSlotLink(slot)
    local itemID = GetItemIDFromLink(link)

    local info = GetItemInfoData(link or itemID) or {}
    FillInstantClassData(link or itemID, info)

    local _, _, _, _, _, _, isQuestItem = GetLootSlotInfo(slot)
    local itemLevel = (C_Item and C_Item.GetDetailedItemLevelInfo and link) and C_Item.GetDetailedItemLevelInfo(link) or info.itemLevel
    local quality = info.quality
    local category = ResolveRuleCategory(quality, info.classID, info.itemType)

    return {
        itemID = itemID,
        link = link,
        quality = quality,
        itemLevel = itemLevel,
        itemType = info.itemType,
        itemSubType = info.itemSubType,
        itemClassID = info.classID,
        itemSubClassID = info.subClassID,
        bindType = info.bindType,
        expansion = info.expansionID,
        sellPrice = info.sellPrice or 0,
        stackCount = 1,
        category = category,
        isQuestItem = isQuestItem and true or false,
        isCollectibleUncollected = IsUncollectedCollectible(link, itemID),
        source = "loot",
    }
end

local function BuildBagItemContext(bag, slot, bagInfo, equipmentSetLookup)
    if not bagInfo then
        return nil
    end

    local link = bagInfo.hyperlink or (C_Container and C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag, slot)) or nil
    local itemID = bagInfo.itemID or GetItemIDFromLink(link)
    if not itemID and not link then
        return nil
    end

    local info = GetItemInfoData(link or itemID) or {}
    FillInstantClassData(link or itemID, info)

    local quality = bagInfo.quality or info.quality
    local itemLevel = (C_Item and C_Item.GetDetailedItemLevelInfo and link) and C_Item.GetDetailedItemLevelInfo(link) or info.itemLevel
    local stackCount = bagInfo.stackCount or 1
    local itemLocation = ItemLocation and ItemLocation:CreateFromBagAndSlot(bag, slot) or nil

    local isBound = bagInfo.isBound and true or false
    if not isBound and itemLocation and C_Item and C_Item.IsBound then
        isBound = C_Item.IsBound(itemLocation) and true or false
    end

    local bindType = info.bindType
    local isWarbound = false
    if itemLocation and C_Item and C_Item.IsBoundToAccountUntilEquip then
        isWarbound = C_Item.IsBoundToAccountUntilEquip(itemLocation) and true or false
    end
    if bindType == ITEM_BIND_WUE and not isBound then
        isWarbound = true
    end

    local isBoE = (bindType == ITEM_BIND_BOE) and (not isBound)
    local isSoulbound = isBound and (not isWarbound)
    local usable = nil
    if IsUsableItem and (link or itemID) then
        usable = IsUsableItem(link or itemID) and true or false
    end

    local category = ResolveRuleCategory(quality, info.classID, info.itemType)

    return {
        itemID = itemID,
        link = link,
        quality = quality,
        itemLevel = itemLevel,
        itemType = info.itemType,
        itemSubType = info.itemSubType,
        itemClassID = info.classID,
        itemSubClassID = info.subClassID,
        bindType = bindType,
        isBound = isBound,
        isBoE = isBoE,
        isWarbound = isWarbound,
        isSoulbound = isSoulbound,
        isUsable = usable,
        isInEquipmentSet = equipmentSetLookup and equipmentSetLookup[itemID] and true or false,
        expansion = info.expansionID,
        sellPrice = info.sellPrice or 0,
        stackCount = stackCount,
        category = category,
        bag = bag,
        slot = slot,
        source = "bag",
    }
end

function LootRules:ShouldBypassFasterLoot()
    if not RefineUI.Config or not RefineUI.Config.Loot or not RefineUI.Config.Loot.Enable then
        return false
    end
    return self:HasEnabledRulesForStage(STAGE_LOOT)
end

function LootRules:RebuildLootSlotQueue(suppressMessages)
    self._lootSlotQueue = self._lootSlotQueue or {}
    wipe(self._lootSlotQueue)
    self._lootSkipAnnounced = self._lootSkipAnnounced or {}
    local suppressFilteredMessages = (suppressMessages and true or false) or IsForceAutoLootOverrideActive()

    local numLootItems = GetNumLootItems and GetNumLootItems() or 0
    for slot = numLootItems, 1, -1 do
        local slotType = GetLootSlotType and GetLootSlotType(slot) or nil
        local _, _, _, _, _, locked = GetLootSlotInfo(slot)
        if not locked then
            if slotType ~= 1 then
                tinsert(self._lootSlotQueue, slot)
            else
                local context = BuildLootItemContext(slot)
                local action, rule = self:EvaluateRulesForStage(STAGE_LOOT, context)
                if action ~= "SKIP" then
                    tinsert(self._lootSlotQueue, slot)
                else
                    if not suppressFilteredMessages then
                        local skipKey = tostring(context and context.itemID or 0) .. ":" .. tostring(slot)
                        if not self._lootSkipAnnounced[skipKey] then
                            self._lootSkipAnnounced[skipKey] = true
                            PrintFilteredLootMessage(context, rule)
                        end
                    end
                end
            end
        end
    end
    self._lootQueueBuilt = true
end

function LootRules:OnLootReady()
    if not self:HasEnabledRulesForStage(STAGE_LOOT) then
        self:OnLootClosed()
        return
    end
    self:RebuildLootSlotQueue(false)
end

function LootRules:OnLootOpened()
    if not self:HasEnabledRulesForStage(STAGE_LOOT) then
        self._lootQueueBuilt = false
        return
    end

    if not self._lootQueueBuilt then
        self:RebuildLootSlotQueue(true)
    end

    for i = 1, #(self._lootSlotQueue or {}) do
        LootSlot(self._lootSlotQueue[i])
    end
    CloseLoot()
end

function LootRules:OnLootClosed()
    self._lootSlotQueue = self._lootSlotQueue or {}
    wipe(self._lootSlotQueue)
    self._lootSkipAnnounced = self._lootSkipAnnounced or {}
    wipe(self._lootSkipAnnounced)
    self._lootQueueBuilt = false
end

function LootRules:StopSellQueue()
    if self._sellTimer and self._sellTimer.Cancel then
        self._sellTimer:Cancel()
    end
    self._sellTimer = nil
    self._sellActive = false
    self._sellQueue = self._sellQueue or {}
    wipe(self._sellQueue)
end

function LootRules:ProcessSellQueue()
    if not self._sellActive then
        return
    end

    if not MerchantFrame or not MerchantFrame:IsShown() then
        self:StopSellQueue()
        return
    end

    if GetCursorInfo and GetCursorInfo() then
        self._sellTimer = ScheduleTimer(SELL_DELAY_SECONDS, function()
            LootRules:ProcessSellQueue()
        end)
        return
    end

    local item = tremove(self._sellQueue, 1)
    if not item then
        self:StopSellQueue()
        return
    end

    PrintItemActionMessage("Selling:", item and item.itemID, item and item.link, BuildSellReasonText(item))
    if C_Container and C_Container.UseContainerItem then
        C_Container.UseContainerItem(item.bag, item.slot)
    end

    self._sellTimer = ScheduleTimer(SELL_DELAY_SECONDS, function()
        LootRules:ProcessSellQueue()
    end)
end

function LootRules:OnMerchantShow()
    if not MerchantFrame or not MerchantFrame:IsShown() then
        return
    end
    if MerchantFrame.selectedTab and MerchantFrame.selectedTab ~= 1 then
        return
    end
    if not self:HasEnabledRulesForStage(STAGE_SELL) then
        self:StopSellQueue()
        return
    end

    self:StopSellQueue()
    self._sellQueue = self._sellQueue or {}

    local equipmentSetLookup = BuildEquipmentSetItemIDLookup()
    for bag = 0, MAX_BAG_ID do
        local slots = C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local bagInfo = C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot) or nil
            if bagInfo and not bagInfo.isLocked then
                local context = BuildBagItemContext(bag, slot, bagInfo, equipmentSetLookup)
                if context and (context.sellPrice or 0) > 0 then
                    local action, rule = self:EvaluateRulesForStage(STAGE_SELL, context)
                    if action == "SELL" then
                        tinsert(self._sellQueue, {
                            bag = bag,
                            slot = slot,
                            itemID = context.itemID,
                            link = context.link,
                            itemLevel = context.itemLevel or 0,
                            ruleID = rule and rule.id or nil,
                        })
                    end
                end
            end
        end
    end

    if #self._sellQueue > 0 then
        self._sellActive = true
        self:ProcessSellQueue()
    end
end

function LootRules:OnMerchantClosed()
    self:StopSellQueue()
end

function LootRules:EnableExecutors()
    if self._executorsEnabled then
        return
    end
    self._executorsEnabled = true

    self:GetConfig()
    self._lootSlotQueue = self._lootSlotQueue or {}
    self._lootSkipAnnounced = self._lootSkipAnnounced or {}
    self._sellQueue = self._sellQueue or {}

    RefineUI:RegisterEventCallback("LOOT_READY", function()
        LootRules:OnLootReady()
    end, "LootRules:LootReady")
    RefineUI:RegisterEventCallback("LOOT_OPENED", function()
        LootRules:OnLootOpened()
    end, "LootRules:LootOpened")
    RefineUI:RegisterEventCallback("LOOT_CLOSED", function()
        LootRules:OnLootClosed()
    end, "LootRules:LootClosed")

    RefineUI:RegisterEventCallback("MERCHANT_SHOW", function()
        C_Timer.After(0.1, function()
            if LootRules and LootRules.OnMerchantShow then
                LootRules:OnMerchantShow()
            end
        end)
    end, "LootRules:MerchantShow")
    RefineUI:RegisterEventCallback("MERCHANT_CLOSED", function()
        LootRules:OnMerchantClosed()
    end, "LootRules:MerchantClosed")
end

