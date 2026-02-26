----------------------------------------------------------------------------------------
-- Tooltip Item Count
-- Description: Cross-character item counts for bag, bank, and equipped inventories.
----------------------------------------------------------------------------------------

local _, RefineUI = ...

----------------------------------------------------------------------------------------
-- Module
----------------------------------------------------------------------------------------
local Tooltip = RefineUI:GetModule("Tooltip")
if not Tooltip then
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
local _G = _G
local pairs = pairs
local select = select
local tonumber = tonumber
local type = type
local format = string.format
local floor = math.floor
local sort = table.sort
local wipe = wipe
local strlower = string.lower

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
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
local ITEM_COUNT_TEXT = "Item Count:"
local YOU_TEXT = "You"
local BAG_UPDATE_DEBOUNCE_KEY = "Tooltip:ItemCount:BagUpdate"

local ITEM_COUNT_HANDLER_KEY = "ItemCount"

local ITEM_COUNT_EVENT_WORLD_KEY = "Tooltip:ItemCount:PLAYER_ENTERING_WORLD"
local ITEM_COUNT_EVENT_BAG_KEY = "Tooltip:ItemCount:BAG_UPDATE"
local ITEM_COUNT_EVENT_BANK_OPEN_KEY = "Tooltip:ItemCount:BANKFRAME_OPENED"
local ITEM_COUNT_EVENT_BANK_SLOTS_KEY = "Tooltip:ItemCount:PLAYERBANKSLOTS_CHANGED"
local ITEM_COUNT_EVENT_EQUIPMENT_KEY = "Tooltip:ItemCount:PLAYER_EQUIPMENT_CHANGED"

----------------------------------------------------------------------------------------
-- Storage Helpers
----------------------------------------------------------------------------------------
local function EnsureCurrentCharacterStorage()
    local db = _G.RefineDB
    if type(db) ~= "table" then
        return nil, nil, nil
    end

    local realm = GetRealmName()
    local playerName = UnitName("player")
    if not realm or not playerName then
        return nil, nil, nil
    end

    db[realm] = db[realm] or {}
    db[realm][playerName] = db[realm][playerName] or {}

    local profile = db[realm][playerName]
    profile[STORAGE_KEY] = profile[STORAGE_KEY] or {}
    local storage = profile[STORAGE_KEY]

    storage.faction = UnitFactionGroup("player")
    storage.class = select(2, UnitClass("player"))
    storage.bags = type(storage.bags) == "table" and storage.bags or {}
    storage.bank = type(storage.bank) == "table" and storage.bank or {}
    storage.equipped = type(storage.equipped) == "table" and storage.equipped or {}

    return storage, db[realm], playerName
end

local function AddCount(countTable, itemID, count)
    itemID = tonumber(itemID)
    if not itemID or not count or count <= 0 then
        return
    end
    countTable[itemID] = (countTable[itemID] or 0) + count
end

local function UpdateBagCounts()
    if not C_Container then
        return
    end

    local storage = EnsureCurrentCharacterStorage()
    if not storage then
        return
    end

    wipe(storage.bags)
    for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        if numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
                if itemInfo and itemInfo.itemID then
                    AddCount(storage.bags, itemInfo.itemID, itemInfo.stackCount or 1)
                end
            end
        end
    end
end

local function UpdateBankCounts()
    if not C_Container then
        return
    end

    local storage = EnsureCurrentCharacterStorage()
    if not storage then
        return
    end

    wipe(storage.bank)

    local bankContainer = rawget(_G, "BANK_CONTAINER") or -1
    local numBagSlots = rawget(_G, "NUM_BAG_SLOTS") or 4
    local numBankBagSlots = rawget(_G, "NUM_BANKBAGSLOTS") or 7

    local function AddBagContents(bagID)
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        if not numSlots or numSlots <= 0 then
            return
        end
        for slot = 1, numSlots do
            local itemInfo = C_Container.GetContainerItemInfo(bagID, slot)
            if itemInfo and itemInfo.itemID then
                AddCount(storage.bank, itemInfo.itemID, itemInfo.stackCount or 1)
            end
        end
    end

    AddBagContents(bankContainer)
    for bag = numBagSlots + 1, numBagSlots + numBankBagSlots do
        AddBagContents(bag)
    end
end

local function UpdateEquippedCounts()
    local storage = EnsureCurrentCharacterStorage()
    if not storage then
        return
    end

    wipe(storage.equipped)

    local firstEquipped = _G.INVSLOT_FIRST_EQUIPPED or 1
    local lastEquipped = _G.INVSLOT_LAST_EQUIPPED or 19
    for slot = firstEquipped, lastEquipped do
        local itemID = GetInventoryItemID("player", slot)
        if itemID then
            AddCount(storage.equipped, itemID, 1)
        end
    end
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

local function GetItemCountLines(itemID)
    itemID = tonumber(itemID)
    if not itemID then
        return {}
    end

    local db = _G.RefineDB
    local realm = GetRealmName()
    local realmData = db and db[realm]
    if type(realmData) ~= "table" then
        return {}
    end

    local currentPlayer = UnitName("player")
    local playerFaction = UnitFactionGroup("player")
    local entries = {}

    for playerName, profile in pairs(realmData) do
        if type(profile) == "table" then
            local storage = profile[STORAGE_KEY]
            if type(storage) == "table" and storage.faction == playerFaction then
                local bags = type(storage.bags) == "table" and storage.bags or nil
                local bank = type(storage.bank) == "table" and storage.bank or nil
                local equipped = type(storage.equipped) == "table" and storage.equipped or nil
                local bagCount = bags and (bags[itemID] or 0) or 0
                local bankCount = bank and (bank[itemID] or 0) or 0
                local equippedCount = equipped and (equipped[itemID] or 0) or 0
                local total = bagCount + bankCount + equippedCount
                if total > 0 then
                    entries[#entries + 1] = {
                        name = playerName,
                        class = storage.class,
                        total = total,
                        isCurrent = playerName == currentPlayer,
                    }
                end
            end
        end
    end

    sort(entries, function(a, b)
        if a.isCurrent ~= b.isCurrent then
            return a.isCurrent
        end
        local aLower = strlower(a.name or "")
        local bLower = strlower(b.name or "")
        if aLower == bLower then
            return (a.name or "") < (b.name or "")
        end
        return aLower < bLower
    end)

    local lines = {}
    for index = 1, #entries do
        local entry = entries[index]
        local displayName = entry.isCurrent and YOU_TEXT or entry.name
        local colorPrefix = GetClassColorPrefix(entry.class)
        lines[#lines + 1] = format("%s%s|r: %d", colorPrefix, displayName, entry.total)
    end

    return lines
end

local function TooltipHasItemCountHeader(tooltip)
    if not Tooltip:IsGameTooltipFrameSafe(tooltip) then
        return false
    end
    local tooltipName = Tooltip:GetTooltipNameSafe(tooltip)
    if not tooltipName or type(tooltip.NumLines) ~= "function" then
        return false
    end

    for lineIndex = 1, tooltip:NumLines() do
        local line = _G[tooltipName .. "TextLeft" .. lineIndex]
        if line and line.GetText then
            local text = line:GetText()
            if type(text) == "string" and text == ITEM_COUNT_TEXT then
                return true
            end
        end
    end

    return false
end

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------
function Tooltip:InitializeItemCountStorage()
    EnsureCurrentCharacterStorage()
    UpdateBagCounts()
    UpdateEquippedCounts()
end

function Tooltip:InitializeItemCount()
    RefineUI:RegisterEventCallback("PLAYER_ENTERING_WORLD", function()
        RefineUI:Debounce(BAG_UPDATE_DEBOUNCE_KEY, 0.1, UpdateBagCounts)
        UpdateEquippedCounts()
    end, ITEM_COUNT_EVENT_WORLD_KEY)

    RefineUI:RegisterEventCallback("BAG_UPDATE", function()
        RefineUI:Debounce(BAG_UPDATE_DEBOUNCE_KEY, 0.1, UpdateBagCounts)
    end, ITEM_COUNT_EVENT_BAG_KEY)

    RefineUI:RegisterEventCallback("BANKFRAME_OPENED", UpdateBankCounts, ITEM_COUNT_EVENT_BANK_OPEN_KEY)
    RefineUI:RegisterEventCallback("PLAYERBANKSLOTS_CHANGED", UpdateBankCounts, ITEM_COUNT_EVENT_BANK_SLOTS_KEY)
    RefineUI:RegisterEventCallback("PLAYER_EQUIPMENT_CHANGED", UpdateEquippedCounts, ITEM_COUNT_EVENT_EQUIPMENT_KEY)

    Tooltip:RegisterItemHandler(ITEM_COUNT_HANDLER_KEY, function(tooltip, data)
        if tooltip ~= GameTooltip then
            return
        end
        if not Tooltip:IsGameTooltipFrameSafe(tooltip) then
            return
        end

        local lines = GetItemCountLines(data and data.id)
        if #lines <= 0 then
            return
        end
        if TooltipHasItemCountHeader(tooltip) then
            return
        end

        tooltip:AddLine(" ")
        tooltip:AddLine(ITEM_COUNT_TEXT)
        for index = 1, #lines do
            tooltip:AddLine(lines[index])
        end
    end)
end
