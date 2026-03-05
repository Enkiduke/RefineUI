local AddOnName, RefineUI = ...
local LootFilter = RefineUI:RegisterModule("LootFilter")

-- Lib Globals
local _G = _G
local select = select
local unpack = unpack
local pairs = pairs
local tonumber = tonumber
local tinsert = table.insert
local wipe = table.wipe
local format = string.format
local floor = math.floor

-- WoW Globals
local CreateFrame = CreateFrame
local GetItemInfo = C_Item.GetItemInfo
local GetDetailedItemLevelInfo = C_Item.GetDetailedItemLevelInfo
local GetItemIcon = C_Item.GetItemIconByID
local GetLootSlotType = GetLootSlotType
local GetLootSlotLink = GetLootSlotLink
local GetLootSlotInfo = GetLootSlotInfo
local GetNumLootItems = GetNumLootItems
local LootSlot = LootSlot
local CloseLoot = CloseLoot
local IsFishingLoot = IsFishingLoot
local UnitClass = UnitClass
local SetCVar = SetCVar
local C_TransmogCollection = C_TransmogCollection

-- Locals
local LootableSlots = {}
local PlayerClass
local RefineUILootFilterDB -- SavedVariables

----------------------------------------------------------------------------------------
--	Filter Lists
----------------------------------------------------------------------------------------

-- Items that shouldn't be looted
local LootFilterItems = {
	-- Tradeskill Items
	[2589] = "Linen Cloth",
	[4306] = "Silk Cloth",
	[25649] = "Fel Hide",
	[36908] = "Frost Lotus",
	[124113] = "Felhide",
	[124106] = "Felwort",
	[124444] = "Infernal Brimstone",
	[173204] = "Lightless Silk",

	-- Annoying Quest Items
	[6522] = "Hardened Walleye",
	[124129] = "Fel Blood",
	[124131] = "Undivided Hide",
	[124130] = "Stormscale Spark",
	[178040] = "Devoured Anima",
	[180248] = "Mawsworn Emblem",
	[180479] = "Rugged Carapace",
	[187322] = "Korthian Repository",

	-- Special fish
	[6358] = "Oily Blackmouth",
	[6359] = "Firefin Snapper",
	[13422] = "Stonescale Eel",
	[13757] = "Lightning Eel",

	-- Common elemental items
	[120945] = "Primal Spirit",
	[37700] = "Crystallized Fire",
	[37701] = "Crystallized Earth",
	[52325] = "Volatile Earth",
	[52326] = "Volatile Fire",
	-- [190315] = "Rousing Earth",
	-- [190320] = "Rousing Fire",

	-- Pigments
	[39151] = "Alabaster Pigment",
	[39334] = "Dusky Pigment",
	[39338] = "Golden Pigment",
}

-- Currency types that will not be looted
local LootFilterCurrency = {
	-- Shadowlands
	[1828] = true,		-- Soul Ash
	[1906] = true,		-- Soul Cinders
	[2009] = true,		-- Cosmic Flux
	[1979] = true,		-- Cyphers of the First Ones
	
	-- Draenor & Legion
	[824] = true,		-- Garrison Resources
	[1220] = true,		-- Order Resources
}

-- Custom filter list (merged with SavedVariables)
local LootFilterCustom = {}

----------------------------------------------------------------------------------------
--	Transmog Data
----------------------------------------------------------------------------------------
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

----------------------------------------------------------------------------------------
--	Utilities
----------------------------------------------------------------------------------------
local function GoldToCopper(gold)
	return floor((gold or 0) * 10000)
end

local itemIDPattern = "item:(%d+)"
local function GetItemIDFromLink(link)
	return link and tonumber(link:match(itemIDPattern))
end

-- Check if a value exists in a table
local function tContains(table, value)
	for _, v in pairs(table) do
		if v == value then return true end
	end
	return false
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

----------------------------------------------------------------------------------------
--	Logic
----------------------------------------------------------------------------------------
local function ShouldLootItem(itemDetails, isFishingLoot)
	if not itemDetails then return false end

	local itemID = GetItemIDFromLink(itemDetails.Link)
	local cfg = RefineUI.Config.Loot.LootFilter

	-- Check filter lists
	if LootFilterItems[itemID] or LootFilterCustom[itemID] then
		return false
	end

	-- Quality threshold
	if itemDetails.Quality >= cfg.MinQuality then
		return true
	end

	-- Vendor price override
	if (itemDetails.Price or 0) >= GoldToCopper(cfg.GearPriceOverride) then
		return true
	end

	-- Tier tokens
	if itemDetails.Type == "Miscellaneous" and itemDetails.Subtype == "Junk" and itemDetails.Quality >= 3 then
		return true
	end

	-- Enchanting materials
	if itemDetails.Type == "Tradeskill" and itemDetails.Subtype == "Enchanting" then
		return true
	end

	-- Fishing loot
	if isFishingLoot then
		return (itemDetails.Type == "Tradeskill" and itemDetails.Subtype == "Cooking")
			or (itemDetails.Quality == 0 and (itemDetails.Price or 0) >= GoldToCopper(cfg.JunkMinPrice))
	end

	-- Tradeskill reagents
	if itemDetails.Type == "Tradeskill" then
		if cfg.IgnoreOldExpansionTradeskill and itemDetails.Expansion < GetExpansionLevel() then
			return false
		end
		return itemDetails.Quality >= cfg.TradeskillMinQuality
	end

	-- Armor/weapon
	if itemDetails.Type == "Weapon" or itemDetails.Type == "Armor" then
		local isUsableTransmog = false
		if PlayerClass and Transmog[PlayerClass] then
			isUsableTransmog = itemDetails.EquipSlot == "INVTYPE_CLOAK" or
				(itemDetails.Type == "Weapon" and tContains(Transmog[PlayerClass]["Weapons"], itemDetails.SubtypeID)) or
				(itemDetails.Type == "Armor" and tContains(Transmog[PlayerClass]["Armor"], itemDetails.SubtypeID))
		end

		if isUsableTransmog then
			local sourceID = select(2, C_TransmogCollection.GetItemInfo(itemDetails.Link))
			if sourceID then
				local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
				if cfg.GearUnknown and not sourceInfo.isCollected then
					return true
				end
			end
		end

		if itemDetails.Quality >= cfg.GearMinQuality then
			return true
		end
	end

	return false
end

local function ProcessLoot()
	local numItems = GetNumLootItems()
	local cfg = RefineUI.Config.Loot.LootFilter

	for i = numItems, 1, -1 do
		local slotType = GetLootSlotType(i)
		local link = GetLootSlotLink(i)
		local _, _, _, _, _, locked, isQuestItem = GetLootSlotInfo(i)

		if not locked then
			local itemDetails = GetItemDetails(link)
			if itemDetails then
				itemDetails.Link = link
			end

			local itemID = GetItemIDFromLink(link)
			local iconString = itemID and ("|T" .. (GetItemIcon(itemID) or "") .. ":0|t ") or ""

			if LootFilterItems[itemID] then
				RefineUI:Print("|cFFFFD200Filtered:|r %s%s (Ignored item)", iconString, link or "Unknown Item")
			elseif slotType == 3 and LootFilterCurrency[itemID] then
				RefineUI:Print("|cFFFFD200Filtered:|r %s%s (Ignored currency)", iconString, link or "Unknown Currency")
			elseif isQuestItem or slotType == 2 or slotType == 3 then
				tinsert(LootableSlots, i)
			elseif itemDetails and itemDetails.Quality == 0 and not IsFishingLoot() then
				if (itemDetails.Price or 0) < GoldToCopper(cfg.JunkMinPrice) then
					RefineUI:Print("|cFFFFD200Filtered:|r %s%s |cFFFFFFFF(Min Price)|r", iconString, link or "Unknown Junk Item")
				else
					tinsert(LootableSlots, i)
				end
			elseif ShouldLootItem(itemDetails, IsFishingLoot()) then
				tinsert(LootableSlots, i)
			else
				RefineUI:Print("|cFFFFD200Filtered:|r %s%s (Does not meet loot criteria)", iconString, link or "Unknown Item")
			end
		end
	end
end

----------------------------------------------------------------------------------------
--	Events
----------------------------------------------------------------------------------------
function LootFilter:LOOT_READY()
	if not RefineUI.Config.Loot.LootFilter.Enable then return end
	wipe(LootableSlots)
	ProcessLoot()
end

function LootFilter:LOOT_OPENED()
	if not RefineUI.Config.Loot.LootFilter.Enable then return end
	if #LootableSlots > 0 then
		for i = 1, #LootableSlots do
			LootSlot(LootableSlots[i])
		end
	end
	-- Close the loot window after processing all items
	CloseLoot()
end

function LootFilter:LOOT_CLOSED()
	wipe(LootableSlots)
end

----------------------------------------------------------------------------------------
--	Custom Filter Management
----------------------------------------------------------------------------------------
local function SaveCustomFilters()
	RefineUILootFilterDB = RefineUILootFilterDB or {}
	wipe(RefineUILootFilterDB)
	for itemID, value in pairs(LootFilterCustom) do
		RefineUILootFilterDB[itemID] = value
	end
end

local function AddToCustomFilter(input)
	local itemID = tonumber(input) or GetItemIDFromLink(input)
	if not itemID then
		RefineUI:Print("Invalid input. Please use an item ID or item link.")
		return
	end
	local itemName, itemLink = GetItemInfo(itemID)
	if itemName then
		LootFilterCustom[itemID] = true
		SaveCustomFilters()
		RefineUI:Print("Added %s to custom exclusion list. This item will not be looted.", itemLink or itemName)
	else
		RefineUI:Print("Invalid item. Item not found.")
	end
end

local function RemoveFromCustomFilter(input)
	local itemID = tonumber(input) or GetItemIDFromLink(input)
	if not itemID then
		RefineUI:Print("Invalid input. Please use an item ID or item link.")
		return
	end
	if LootFilterCustom[itemID] then
		local itemName, itemLink = GetItemInfo(itemID)
		LootFilterCustom[itemID] = nil
		SaveCustomFilters()
		RefineUI:Print("Removed %s from custom exclusion list. This item can now be looted.",
			itemLink or itemName or "Unknown Item")
	else
		RefineUI:Print("Item not found in custom exclusion list.")
	end
end

local function ClearCustomFilter()
	wipe(LootFilterCustom)
	wipe(RefineUILootFilterDB)
	RefineUI:Print("Cleared all items from the custom exclusion list.")
end

local function ListCustomFilter()
	RefineUI:Print("Custom Exclusion List (items that will not be looted):")
	local count = 0
	for itemID in pairs(LootFilterCustom) do
		local itemName, itemLink = GetItemInfo(itemID)
		RefineUI:Print("- %s", itemLink or itemName or format("Unknown Item (ID: %d)", itemID))
		count = count + 1
	end
	if count == 0 then
		RefineUI:Print("The custom exclusion list is empty.")
	end
end

local function SetupSlashCommands()
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
			RefineUI:Print("|cFFFFD200Loot Filter Commands:|r")
			RefineUI:Print("|cFFFFD200/lf add [itemID or item link]|r - Add an item to the custom filter")
			RefineUI:Print("|cFFFFD200/lf remove [itemID or item link]|r - Remove an item from the custom filter")
			RefineUI:Print("|cFFFFD200/lf list|r - List all items in the custom filter")
			RefineUI:Print("|cFFFFD200/lf clear|r - Clear all items from the custom filter")
		end
	end
end

----------------------------------------------------------------------------------------
--	Initialize
----------------------------------------------------------------------------------------
function LootFilter:OnEnable()
	if not RefineUI.Config.Loot.LootFilter or not RefineUI.Config.Loot.LootFilter.Enable or not RefineUI.Config.Loot.Enable then
		return
	end

	-- Disable default auto loot if enabled, as this module handles it
	SetCVar("autoLootDefault", "0")

	PlayerClass = select(2, UnitClass("player"))
	
	RefineUILootFilterDB = RefineUILootFilterDB or {}
	for itemID, value in pairs(RefineUILootFilterDB) do
		LootFilterCustom[itemID] = value
	end

	RefineUI:RegisterEventCallback("LOOT_READY", function() self:LOOT_READY() end, "LootFilter:Ready")
	RefineUI:RegisterEventCallback("LOOT_OPENED", function() self:LOOT_OPENED() end, "LootFilter:Opened")
	RefineUI:RegisterEventCallback("LOOT_CLOSED", function() self:LOOT_CLOSED() end, "LootFilter:Closed")

	SetupSlashCommands()
end
