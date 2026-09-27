----------------------------------------------------------------------------------------
-- Tooltip Item Count
-- Description: Cross-character item counts for bag, bank, and equipped inventories.
----------------------------------------------------------------------------------------

local _, RefineUI = ...

----------------------------------------------------------------------------------------
-- Module
----------------------------------------------------------------------------------------
local Tooltip = RefineUI:GetModule("Tooltip")

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local pairs = pairs
local select = select
local type = type
local format = string.format
local floor = math.floor
local sort = table.sort
local wipe = wipe
local strlower = string.lower

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local C_Bank = _G.C_Bank
local C_Container = _G.C_Container
local GetRealmName = GetRealmName
local UnitName = UnitName
local UnitFactionGroup = UnitFactionGroup
local UnitClass = UnitClass
local GetInventoryItemID = GetInventoryItemID
local GameTooltip = _G.GameTooltip

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local STORAGE_KEY = "TooltipItemCount"
local OWNED_TEXT = "Owned"
local YOU_TEXT = _G.YOU or "You"

local ITEM_COUNT_EVENT_BAG_UPDATE_KEY = "Tooltip:ItemCount:BAG_UPDATE"
local ITEM_COUNT_EVENT_BAG_DELAYED_KEY = "Tooltip:ItemCount:BAG_UPDATE_DELAYED"
local ITEM_COUNT_EVENT_BANK_OPEN_KEY = "Tooltip:ItemCount:BANKFRAME_OPENED"
local ITEM_COUNT_EVENT_BANK_CLOSE_KEY = "Tooltip:ItemCount:BANKFRAME_CLOSED"
local ITEM_COUNT_EVENT_BANK_SLOTS_KEY = "Tooltip:ItemCount:PLAYERBANKSLOTS_CHANGED"
local ITEM_COUNT_EVENT_BANK_TABS_KEY = "Tooltip:ItemCount:BANK_TABS_CHANGED"
local ITEM_COUNT_EVENT_EQUIPMENT_KEY = "Tooltip:ItemCount:PLAYER_EQUIPMENT_CHANGED"
local ITEM_COUNT_BANK_TIMER_KEY = "Tooltip:ItemCount:UpdateBank"

local BAG_INDEX = _G.Enum and _G.Enum.BagIndex
local BANK_TYPE = _G.Enum and _G.Enum.BankType
local FIRST_BAG_ID = (BAG_INDEX and BAG_INDEX.Backpack) or 0
local LAST_BAG_ID = rawget(_G, "REAGENTBAG_CONTAINER") or (BAG_INDEX and BAG_INDEX.ReagentBag) or 5
local CHARACTER_BANK_TYPE = BANK_TYPE and BANK_TYPE.Character

----------------------------------------------------------------------------------------
-- Runtime State
----------------------------------------------------------------------------------------
local ITEM_COUNT_LINES_CACHE = {}
local CHARACTER_ROSTER = {}
local CHARACTER_BANK_TAB_IDS = {}

local bagCountScratch = {}
local bankCountScratch = {}
local equippedCountScratch = {}

local currentStorage
local currentRealmData
local currentPlayerName
local currentFaction
local bankOpen = false
local bankUpdateScheduled = false
local playerBagsDirty = false

----------------------------------------------------------------------------------------
-- Storage Helpers
----------------------------------------------------------------------------------------
local function EnsureCurrentCharacterStorage()
    if currentStorage then
        return currentStorage
    end

    local db = _G.RefineDB
    if type(db) ~= "table" then
        return nil
    end

    local realm = RefineUI.MyRealm or GetRealmName()
    local playerName = RefineUI.MyName or UnitName("player")
    if not realm or not playerName then
        return nil
    end

    db[realm] = db[realm] or {}
    db[realm][playerName] = db[realm][playerName] or {}

    local profile = db[realm][playerName]
    profile[STORAGE_KEY] = profile[STORAGE_KEY] or {}
    local storage = profile[STORAGE_KEY]

    storage.faction = UnitFactionGroup("player")
    storage.class = RefineUI.MyClass or select(2, UnitClass("player"))
    storage.bags = type(storage.bags) == "table" and storage.bags or {}
    storage.bank = type(storage.bank) == "table" and storage.bank or {}
    storage.equipped = type(storage.equipped) == "table" and storage.equipped or {}

    currentStorage = storage
    currentRealmData = db[realm]
    currentPlayerName = playerName
    currentFaction = storage.faction
    return storage
end

local function AddCount(countTable, itemID, count)
    if not itemID then
        return
    end
    countTable[itemID] = (countTable[itemID] or 0) + count
end

local function CommitCounts(storageKey, newCounts)
    local oldCounts = currentStorage[storageKey]

    for itemID, oldCount in pairs(oldCounts) do
        if newCounts[itemID] ~= oldCount then
            ITEM_COUNT_LINES_CACHE[itemID] = nil
        end
    end
    for itemID in pairs(newCounts) do
        if oldCounts[itemID] == nil then
            ITEM_COUNT_LINES_CACHE[itemID] = nil
        end
    end

    currentStorage[storageKey] = newCounts
    wipe(oldCounts)
    return oldCounts
end

local function ScanContainer(countTable, containerID)
    local numSlots = C_Container.GetContainerNumSlots(containerID)
    if not numSlots or numSlots <= 0 then
        return
    end

    for slot = 1, numSlots do
        local itemInfo = C_Container.GetContainerItemInfo(containerID, slot)
        if itemInfo and itemInfo.itemID then
            AddCount(countTable, itemInfo.itemID, itemInfo.stackCount or 1)
        end
    end
end

local function UpdateBagCounts()
    if not C_Container or not EnsureCurrentCharacterStorage() then
        return
    end

    wipe(bagCountScratch)
    for bagID = FIRST_BAG_ID, LAST_BAG_ID do
        ScanContainer(bagCountScratch, bagID)
    end
    bagCountScratch = CommitCounts("bags", bagCountScratch)
end

local function UpdateBankCounts()
    if not bankOpen or not C_Container or not C_Bank or not C_Bank.FetchPurchasedBankTabIDs
        or CHARACTER_BANK_TYPE == nil or not EnsureCurrentCharacterStorage() then
        return
    end

    local bankTabIDs = C_Bank.FetchPurchasedBankTabIDs(CHARACTER_BANK_TYPE)
    if type(bankTabIDs) ~= "table" then
        return
    end

    wipe(CHARACTER_BANK_TAB_IDS)
    wipe(bankCountScratch)
    for index = 1, #bankTabIDs do
        local bankTabID = bankTabIDs[index]
        CHARACTER_BANK_TAB_IDS[bankTabID] = true
        ScanContainer(bankCountScratch, bankTabID)
    end
    bankCountScratch = CommitCounts("bank", bankCountScratch)
end

local function UpdateEquippedCounts()
    if not EnsureCurrentCharacterStorage() then
        return
    end

    wipe(equippedCountScratch)

    local firstEquipped = _G.INVSLOT_FIRST_EQUIPPED or 1
    local lastEquipped = _G.INVSLOT_LAST_EQUIPPED or 19
    for slot = firstEquipped, lastEquipped do
        AddCount(equippedCountScratch, GetInventoryItemID("player", slot), 1)
    end

    if C_Container and C_Container.ContainerIDToInventoryID then
        for bagID = FIRST_BAG_ID + 1, LAST_BAG_ID do
            local inventoryID = C_Container.ContainerIDToInventoryID(bagID)
            if inventoryID then
                AddCount(equippedCountScratch, GetInventoryItemID("player", inventoryID), 1)
            end
        end
    end

    equippedCountScratch = CommitCounts("equipped", equippedCountScratch)
end

----------------------------------------------------------------------------------------
-- Tooltip Rendering
----------------------------------------------------------------------------------------
local function GetClassColorPrefix(classToken)
    local classColors = _G.CUSTOM_CLASS_COLORS or _G.RAID_CLASS_COLORS
    local classColor = classColors and classToken and classColors[classToken]
    if not classColor then
        return "|cffffffff"
    end

    if type(classColor.colorStr) == "string" and classColor.colorStr ~= "" then
        if classColor.colorStr:sub(1, 2) == "|c" then
            return classColor.colorStr
        end
        if #classColor.colorStr == 8 then
            return "|c" .. classColor.colorStr
        end
    end

    if type(classColor.r) == "number" and type(classColor.g) == "number" and type(classColor.b) == "number" then
        local r = floor(classColor.r * 255 + 0.5)
        local g = floor(classColor.g * 255 + 0.5)
        local b = floor(classColor.b * 255 + 0.5)
        return format("|cff%02x%02x%02x", r, g, b)
    end

    return "|cffffffff"
end

local function SortCharacterRoster(a, b)
    if a.isCurrent ~= b.isCurrent then
        return a.isCurrent
    end
    if a.sortName == b.sortName then
        return a.name < b.name
    end
    return a.sortName < b.sortName
end

local function BuildCharacterRoster()
    wipe(CHARACTER_ROSTER)
    if type(currentRealmData) ~= "table" then
        return
    end

    for playerName, profile in pairs(currentRealmData) do
        if type(playerName) == "string" and type(profile) == "table" then
            local storage = profile[STORAGE_KEY]
            if type(storage) == "table" and storage.faction == currentFaction then
                storage.bags = type(storage.bags) == "table" and storage.bags or {}
                storage.bank = type(storage.bank) == "table" and storage.bank or {}
                storage.equipped = type(storage.equipped) == "table" and storage.equipped or {}

                local isCurrent = playerName == currentPlayerName
                local displayName = isCurrent and YOU_TEXT or playerName
                CHARACTER_ROSTER[#CHARACTER_ROSTER + 1] = {
                    name = playerName,
                    sortName = strlower(playerName),
                    isCurrent = isCurrent,
                    storage = storage,
                    lineLabel = GetClassColorPrefix(storage.class) .. displayName .. "|r",
                }
            end
        end
    end

    sort(CHARACTER_ROSTER, SortCharacterRoster)
end

local function GetItemCountLines(itemID)
    if type(itemID) ~= "number" then
        return nil
    end

    local cachedLines = ITEM_COUNT_LINES_CACHE[itemID]
    if cachedLines ~= nil then
        return cachedLines ~= false and cachedLines or nil
    end

    local lines
    local grandTotal = 0
    local currentTotal = 0
    for index = 1, #CHARACTER_ROSTER do
        local entry = CHARACTER_ROSTER[index]
        local storage = entry.storage
        local bags = storage.bags
        local bank = storage.bank
        local equipped = storage.equipped
        local total = (bags[itemID] or 0) + (bank[itemID] or 0) + (equipped[itemID] or 0)

        if total > 0 then
            lines = lines or { 0 }
            grandTotal = grandTotal + total
            if entry.isCurrent then
                currentTotal = total
            end
            lines[#lines + 1] = entry.lineLabel
            lines[#lines + 1] = total
        end
    end

    if lines then
        lines[1] = grandTotal
        lines.showOwned = grandTotal ~= currentTotal
    end
    ITEM_COUNT_LINES_CACHE[itemID] = lines or false
    return lines
end

----------------------------------------------------------------------------------------
-- Event Handling
----------------------------------------------------------------------------------------
local function RunScheduledBankUpdate()
    bankUpdateScheduled = false
    UpdateBankCounts()
end

local function ScheduleBankUpdate()
    if not bankOpen or bankUpdateScheduled then
        return
    end

    bankUpdateScheduled = true
    RefineUI:After(ITEM_COUNT_BANK_TIMER_KEY, 0, RunScheduledBankUpdate)
end

local function HandleBagUpdate(_, containerID)
    if type(containerID) ~= "number" then
        return
    end

    if containerID >= FIRST_BAG_ID and containerID <= LAST_BAG_ID then
        playerBagsDirty = true
    elseif bankOpen and CHARACTER_BANK_TAB_IDS[containerID] then
        ScheduleBankUpdate()
    end
end

local function HandleBagUpdateDelayed()
    if not playerBagsDirty then
        return
    end

    playerBagsDirty = false
    UpdateBagCounts()
end

local function HandleBankOpened()
    bankOpen = true
    ScheduleBankUpdate()
end

local function HandleBankClosed()
    bankOpen = false
    bankUpdateScheduled = false
    RefineUI:CancelTimer(ITEM_COUNT_BANK_TIMER_KEY)
end

local function HandleBankTabsChanged(_, bankType)
    if bankType == CHARACTER_BANK_TYPE then
        ScheduleBankUpdate()
    end
end

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------
function Tooltip:InitializeItemCountStorage()
    if not EnsureCurrentCharacterStorage() then
        return
    end

    UpdateBagCounts()
    UpdateEquippedCounts()
    BuildCharacterRoster()
end

function Tooltip:InitializeItemCount()
    RefineUI:RegisterEventCallback("BAG_UPDATE", HandleBagUpdate, ITEM_COUNT_EVENT_BAG_UPDATE_KEY)
    RefineUI:RegisterEventCallback("BAG_UPDATE_DELAYED", HandleBagUpdateDelayed, ITEM_COUNT_EVENT_BAG_DELAYED_KEY)
    RefineUI:RegisterEventCallback("BANKFRAME_OPENED", HandleBankOpened, ITEM_COUNT_EVENT_BANK_OPEN_KEY)
    RefineUI:RegisterEventCallback("BANKFRAME_CLOSED", HandleBankClosed, ITEM_COUNT_EVENT_BANK_CLOSE_KEY)
    RefineUI:RegisterEventCallback("PLAYERBANKSLOTS_CHANGED", ScheduleBankUpdate, ITEM_COUNT_EVENT_BANK_SLOTS_KEY)
    RefineUI:RegisterEventCallback("BANK_TABS_CHANGED", HandleBankTabsChanged, ITEM_COUNT_EVENT_BANK_TABS_KEY)
    RefineUI:RegisterEventCallback("PLAYER_EQUIPMENT_CHANGED", UpdateEquippedCounts, ITEM_COUNT_EVENT_EQUIPMENT_KEY)

    Tooltip:RegisterItemHandler(function(tooltip, data)
        if tooltip ~= GameTooltip then
            return
        end

        local lines = GetItemCountLines(Tooltip:ReadSafeNumber(data.id))
        if not lines then
            return
        end

        tooltip:AddLine(" ")
        if lines.showOwned then
            tooltip:AddDoubleLine(OWNED_TEXT, lines[1])
        end
        for index = 2, #lines, 2 do
            tooltip:AddDoubleLine(lines[index], lines[index + 1])
        end
    end)
end
