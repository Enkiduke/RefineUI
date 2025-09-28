local addonName, RefineUI = ...
local R, C, L = unpack(RefineUI)
if not C.lootfilter or C.lootfilter.enable ~= true then return end
----------------------------------------------------------------------------------------
--  LootFilter for RefineUI
--  This module provides selective auto-looting functionality for World of Warcraft.
--  It filters loot based on various criteria including item quality, price, and type.
--  Based on Ghuul Addons: Selective Autoloot v1.7.2
----------------------------------------------------------------------------------------
-- Optionally force-disable auto loot default if configured
if C.lootfilter and C.lootfilter.forceDisableAutoLoot == true then
    SetCVar("autoLootDefault", "0")
end

local LootFilter = CreateFrame("Frame")
LootFilter:SetScript("OnEvent", function(self, event, ...) self[event](self, ...) end)

local LootableSlots = {}
local PlayerClass

-- Localize global functions for performance
local GetItemInfo = C_Item.GetItemInfo
local GetItemIcon = C_Item.GetItemIconByID
local tinsert, wipe, select, tonumber, pairs = table.insert, table.wipe, select, tonumber, pairs
local GetLootSlotType, GetLootSlotLink, GetLootSlotInfo = GetLootSlotType, GetLootSlotLink, GetLootSlotInfo
local GetNumLootItems, LootSlot, CloseLoot = GetNumLootItems, LootSlot, CloseLoot
local print, format = print, string.format
local tContains = tContains
local UnitClass = UnitClass
local IsFishingLoot = IsFishingLoot
local C_TransmogCollection = C_TransmogCollection
local IsControlKeyDown = IsControlKeyDown
local IsShiftKeyDown = IsShiftKeyDown
local IsAltKeyDown = IsAltKeyDown

-- Queue filtered messages during selection; print after loot closes to avoid UI flicker
local FilterMessages = {}
local function DebugPrint(msg)
    tinsert(FilterMessages, msg)
end

-- Currency ID from link helper
local currencyIDPattern = "currency:(%d+)"
local function GetCurrencyIDFromLink(link)
    return link and tonumber(link:match(currencyIDPattern))
end

-- Transmog source known cache
local TransmogKnownCache = {}

-- Faster loot throttle
local tDelay = 0
local LOOT_DELAY = (C.lootfilter and C.lootfilter.delay) or 0

-- Auto-loot state helper (honors modified-click)
local function shouldAutoLootNow()
    return GetCVarBool("autoLootDefault") ~= IsModifiedClick("AUTOLOOTTOGGLE")
end

-- Hold-to-keep-open modifier check
local function ShouldKeepWindowOpen()
    local mod = (C.lootfilter and C.lootfilter.keepOpenModifier) or "NONE"
    if mod == "CTRL" then return IsControlKeyDown() end
    if mod == "SHIFT" then return IsShiftKeyDown() end
    if mod == "ALT" then return IsAltKeyDown() end
    return false
end

-- Local utility functions
local function GoldToCopper(gold)
    return math.floor(gold * 10000)
end

local itemIDPattern = "item:(%d+)"
local function GetItemIDFromLink(link)
    return link and tonumber(link:match(itemIDPattern))
end

-- Local item cache
local ItemCache = setmetatable({}, {__mode = "v"})

local function GetItemDetails(link)
    if not link then return nil end
    local itemID = GetItemIDFromLink(link)
    if not itemID then return nil end

    if not ItemCache[itemID] then
        local itemName, _, itemQuality, _, _, itemType, itemSubType, _, itemEquipLoc, _, itemPrice, _, itemSubTypeID, itemBindType, itemExpansion = GetItemInfo(link)
        if not itemName then return nil end -- Item info not available

        ItemCache[itemID] = {
            Name = itemName,
            Quality = itemQuality,
            Type = itemType,
            Subtype = itemSubType,
            EquipSlot = itemEquipLoc,
            Price = itemPrice,
            SubtypeID = itemSubTypeID,
            Bind = itemBindType,
            Expansion = itemExpansion or 0
        }
    end

    return ItemCache[itemID]
end

-- Transmog data (unchanged)
local Transmog = {
    WARRIOR = {
        Weapons = {0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18, 19, 20},
        Armor = {1, 2, 3, 4}
    },
    PALADIN = {
        Weapons = {0, 1, 4, 5, 6, 7, 8, 10, 13, 15, 16, 19, 20},
        Armor = {2, 3, 4}
    },
    HUNTER = {
        Weapons = {0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18, 19},
        Armor = {1, 2, 3}
    },
    ROGUE = {
        Weapons = {0, 2, 3, 4, 7, 8, 10, 13, 15, 16},
        Armor = {1, 2}
    },
    PRIEST = {
        Weapons = {4, 10, 15, 19},
        Armor = {1}
    },
    DEATHKNIGHT = {
        Weapons = {0, 1, 4, 5, 6, 7, 8, 10, 13, 15, 16, 19, 20},
        Armor = {4}
    },
    SHAMAN = {
        Weapons = {0, 1, 4, 5, 10, 13, 15, 16, 19, 20},
        Armor = {2, 3}
    },
    MAGE = {
        Weapons = {4, 7, 10, 15, 19},
        Armor = {1}
    },
    WARLOCK = {
        Weapons = {4, 7, 10, 15, 19},
        Armor = {1}
    },
    MONK = {
        Weapons = {0, 1, 2, 4, 5, 6, 10, 13, 15},
        Armor = {1, 2}
    },
    DRUID = {
        Weapons = {4, 5, 6, 10, 13, 15},
        Armor = {1, 2}
    },
    DEMONHUNTER = {
        Weapons = {2, 3, 7, 8, 10, 13, 16},
        Armor = {1}
    },
    EVOKER = {
        Weapons = {4, 5, 6, 10, 15, 19},
        Armor = {3}
    }
}

-- Main loot filter logic
local function ShouldLootItem(itemDetails, isFishingLoot, link)
    if not itemDetails then return false end

    -- Check filter lists by itemID
    local itemID = link and GetItemIDFromLink(link)
    if itemID and (R.LootFilterItems[itemID] or R.LootFilterCustom[itemID]) then
        return false
    end

    -- Quality threshold
    if itemDetails.Quality and itemDetails.Quality >= (C.lootfilter.minQuality or 0) then
        return true
    end

    -- Vendor price override
    if (itemDetails.Price or 0) >= GoldToCopper(C.lootfilter.gearPriceOverride or 0) then
        return true
    end

    -- Tier tokens (example heuristic)
    if itemDetails.Type == "Miscellaneous" and itemDetails.Subtype == "Junk" and (itemDetails.Quality or 0) >= 3 then
        return true
    end

    -- Enchanting materials
    if itemDetails.Type == "Tradeskill" and itemDetails.Subtype == "Enchanting" then
        return true
    end

    -- Fishing loot
    if isFishingLoot then
        return (itemDetails.Type == "Tradeskill" and itemDetails.Subtype == "Cooking")
            or ((itemDetails.Quality or 0) == 0 and (itemDetails.Price or 0) >= GoldToCopper(C.lootfilter.junkMinPrice or 0))
    end

    -- Tradeskill reagents
    if itemDetails.Type == "Tradeskill" and tContains(C.lootfilter.tradeskillSubtypes or {}, itemDetails.Subtype) then
        return (itemDetails.Quality or 0) >= (C.lootfilter.tradeskillMinQuality or 0)
    end

    -- Armor/weapon and transmog rules
    if itemDetails.Type == "Weapon" or itemDetails.Type == "Armor" then
        if PlayerClass and Transmog[PlayerClass] then
            local isUsableTransmog = itemDetails.EquipSlot == "INVTYPE_CLOAK"
                or (itemDetails.Type == "Weapon" and tContains(Transmog[PlayerClass]["Weapons"], itemDetails.SubtypeID))
                or (itemDetails.Type == "Armor" and tContains(Transmog[PlayerClass]["Armor"], itemDetails.SubtypeID))

            if isUsableTransmog and C.lootfilter.gearUnknown and link then
                local sourceID = select(2, C_TransmogCollection.GetItemInfo(link))
                if sourceID then
                    local known = TransmogKnownCache[sourceID]
                    if known == nil then
                        local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
                        known = sourceInfo and sourceInfo.isCollected or false
                        TransmogKnownCache[sourceID] = known
                    end
                    if not known then
                        return true
                    end
                end
            end
        end

        if (itemDetails.Quality or 0) >= (C.lootfilter.gearMinQuality or 0) then
            return true
        end
    end

    return false
end

local function SelectLootSlots()
    wipe(LootableSlots)
    local numItems = GetNumLootItems()
    if numItems == 0 then return LootableSlots end

    local isFishing = IsFishingLoot()
    local junkMinCopper = GoldToCopper(C.lootfilter.junkMinPrice or 0)

    for i = numItems, 1, -1 do
        local slotType = GetLootSlotType(i)
        local link = GetLootSlotLink(i)
        local _, _, _, _, _, locked, isQuestItem = GetLootSlotInfo(i)

        if not locked then
            if isQuestItem or slotType == 2 then
                tinsert(LootableSlots, i)
            elseif slotType == 3 then
                -- Currency: loot by default, allow optional ignore list if provided
                local currencyID = GetCurrencyIDFromLink(link)
                if currencyID and R.LootFilterCurrency and R.LootFilterCurrency[currencyID] then
                    DebugPrint("|cFFFFD200Filtered:|r " .. (link or "Unknown Currency") .. " (Ignored currency)")
                else
                    tinsert(LootableSlots, i)
                end
            else
                local itemDetails = GetItemDetails(link)
                if itemDetails and itemDetails.Quality == 0 and not isFishing then
                    if (itemDetails.Price or 0) < junkMinCopper then
                        DebugPrint(format("|cFFFFD200Filtered:|r %s (Below min price)", link or "Unknown Junk Item"))
                    else
                        tinsert(LootableSlots, i)
                    end
                elseif ShouldLootItem(itemDetails, isFishing, link) then
                    tinsert(LootableSlots, i)
                else
                    DebugPrint("|cFFFFD200Filtered:|r " .. (link or "Unknown Item") .. " (Does not meet loot criteria)")
                end
            end
        end
    end

    return LootableSlots
end

-- Event handlers
function LootFilter:PLAYER_LOGIN()
    PlayerClass = select(2, UnitClass("player"))
    self:UnregisterEvent("PLAYER_LOGIN")
end

function LootFilter:LOOT_READY()
    -- Only gate on Blizzard autoloot toggle if configured to respect it
    if C.lootfilter and C.lootfilter.respectAutoLootToggle then
        if not shouldAutoLootNow() then return end
    end
    if (GetTime() - tDelay) < LOOT_DELAY then return end

    local slots = SelectLootSlots()
    if #slots > 0 then
        for i = 1, #slots do
            LootSlot(slots[i])
        end
    end
    tDelay = GetTime()
end


function LootFilter:LOOT_OPENED()
    -- If user holds the configured modifier, keep the window open and flush queued messages now.
    if ShouldKeepWindowOpen() then
        if #FilterMessages > 0 then
            for i = 1, #FilterMessages do
                print(FilterMessages[i])
            end
            wipe(FilterMessages)
        end
        return
    end

    -- Otherwise, close on the next frame to avoid any visible flicker and let LOOT_READY finish
    if C.lootfilter == nil or C.lootfilter.closeAfterLoot ~= false then
        C_Timer.After(0, function()
            CloseLoot()
        end)
    end
end

function LootFilter:LOOT_CLOSED()
    -- Print any queued filtered messages now that the loot window is closed
    if #FilterMessages > 0 then
        for i = 1, #FilterMessages do
            print(FilterMessages[i])
        end
        wipe(FilterMessages)
    end
    wipe(LootableSlots)
end

-- Register events
LootFilter:RegisterEvent("PLAYER_LOGIN")
LootFilter:RegisterEvent("LOOT_READY")
LootFilter:RegisterEvent("LOOT_OPENED")
LootFilter:RegisterEvent("LOOT_CLOSED")

-- Custom filter functions
local function SaveCustomFilters()
    RefineUILootFilterDB = RefineUILootFilterDB or {}
    wipe(RefineUILootFilterDB)
    for itemID, value in pairs(R.LootFilterCustom) do
        RefineUILootFilterDB[itemID] = value
    end
end

local function AddToCustomFilter(input)
    local itemID = tonumber(input) or GetItemIDFromLink(input)
    if not itemID then
        print("Invalid input. Please use an item ID or item link.")
        return
    end
    local itemName, itemLink = GetItemInfo(itemID)
    if itemName then
        R.LootFilterCustom[itemID] = true
        SaveCustomFilters()
        print(format("Added %s to custom exclusion list. This item will not be looted.", itemLink or itemName))
    else
        print("Invalid item. Item not found.")
    end
end

local function RemoveFromCustomFilter(input)
    local itemID = tonumber(input) or GetItemIDFromLink(input)
    if not itemID then
        print("Invalid input. Please use an item ID or item link.")
        return
    end
    if R.LootFilterCustom[itemID] then
        local itemName, itemLink = GetItemInfo(itemID)
        R.LootFilterCustom[itemID] = nil
        SaveCustomFilters()
        print(format("Removed %s from custom exclusion list. This item can now be looted.",
            itemLink or itemName or "Unknown Item"))
    else
        print("Item not found in custom exclusion list.")
    end
end

local function ClearCustomFilter()
    wipe(R.LootFilterCustom)
    wipe(RefineUILootFilterDB)
    print("Cleared all items from the custom exclusion list.")
end

local function ListCustomFilter()
    print("Custom Exclusion List (items that will not be looted):")
    local count = 0
    for itemID in pairs(R.LootFilterCustom) do
        local itemName, itemLink = GetItemInfo(itemID)
        print(format("- %s", itemLink or itemName or format("Unknown Item (ID: %d)", itemID)))
        count = count + 1
    end
    if count == 0 then
        print("The custom exclusion list is empty.")
    end
end

-- Slash command handler
SLASH_LOOTFILTER1 = "/lootfilter"
SLASH_LOOTFILTER2 = "/lf"
SlashCmdList["LOOTFILTER"] = function(msg)
    local command, rest = msg:match("^(%S*)%s*(.-)$")
    command = command:lower()

    local commands = {
        add = AddToCustomFilter,
        remove = RemoveFromCustomFilter,
        list = ListCustomFilter,
        clear = ClearCustomFilter
    }

    if commands[command] then
        commands[command](rest ~= "" and rest or nil)
    else
        print("|cFFFFD200Loot Filter Commands:|r")
        print("|cFFFFD200/lf add [itemID or item link]|r - Add an item to the custom filter")
        print("|cFFFFD200/lf remove [itemID or item link]|r - Remove an item from the custom filter")
        print("|cFFFFD200/lf list|r - List all items in the custom filter")
        print("|cFFFFD200/lf clear|r - Clear all items from the custom filter")
    end
end

-- Initialization
local function Initialize()
    RefineUILootFilterDB = RefineUILootFilterDB or {}
    for itemID, value in pairs(RefineUILootFilterDB) do
        R.LootFilterCustom[itemID] = value
    end
end


Initialize()