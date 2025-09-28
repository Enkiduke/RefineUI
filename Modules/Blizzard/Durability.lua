----------------------------------------------------------------------------------------
--  Durability value on slot buttons in CharacterFrame (tekability-inspired)
----------------------------------------------------------------------------------------

-- Hot locals (perf)
local _G                         = _G
local CreateFrame                = CreateFrame
local GetInventoryItemDurability = GetInventoryItemDurability
local GetInventorySlotInfo       = GetInventorySlotInfo
local floor                      = math.floor
local min                        = math.min

-- Slot order we actually draw for (matches your original set)
local SLOT_NAMES                 = {
	"Head", "Shoulder", "Chest", "Waist", "Legs", "Feet", "Wrist", "Hands", "MainHand", "SecondaryHand"
}

-- Build slot ids and references once
local SLOT_IDS                   = {}
local SLOT_FRAME                 = {}
for i = 1, #SLOT_NAMES do
	local name    = SLOT_NAMES[i]
	SLOT_IDS[i]   = GetInventorySlotInfo(name .. "Slot")
	SLOT_FRAME[i] = _G["Character" .. name .. "Slot"]
end

-- Placement rules: faithful to original behavior
--  - Head/Shoulder/Chest/Wrist => text to RIGHT of the slot
--  - Hands/Waist/Legs/Feet     => text to LEFT of the slot
--  - MainHand/SecondaryHand    => text at BOTTOM of the slot
local PLACE_RIGHT = { Head = true, Shoulder = true, Chest = true, Wrist = true }
local PLACE_LEFT  = { Hands = true, Waist = true, Legs = true, Feet = true }
-- others (MainHand, SecondaryHand) => bottom

-- Cheap R→Y→G gradient
local function RYGColorGradient(perc)
	local rel = (perc * 2) % 1
	if perc <= 0 then
		return 1, 0, 0
	elseif perc < 0.5 then
		return 1, rel, 0
	elseif perc == 0.5 then
		return 1, 1, 0
	elseif perc < 1.0 then
		return 1 - rel, 1, 0
	else
		return 0, 1, 0
	end
end

-- Pre-create fontstrings; no work on the hot path
local labels = {}
for i = 1, #SLOT_NAMES do

	local btn      = SLOT_FRAME[i]
	if btn then
		local fs = btn:CreateFontString(nil, "OVERLAY", "SystemFont_Outline_Small")
		fs:SetPoint("BOTTOM", btn, "BOTTOM", 1, 1)

		labels[i] = fs
	end
end

-- Worker (runs only on relevant events)
local function RefreshDurability()
	for i = 1, #SLOT_NAMES do
		local id = SLOT_IDS[i]
		local fs = labels[i]
		if fs and id then
			local cur, maxv = GetInventoryItemDurability(id)
			if cur and maxv and maxv > 0 then
				if cur < maxv then
					local perc = cur / maxv
					local r, g, b = RYGColorGradient(perc)
					fs:SetTextColor(r, g, b)
					-- integer percent, rounded (.5 up)
					fs:SetText(floor(perc * 100 + 0.5) .. "%")
				else
					-- 100%: hide text (matches original behavior)
					fs:SetText(nil)
				end
			else
				-- slot empty or no data
				fs:SetText(nil)
			end
		end
	end
end

-- Frame + events: update exactly when durability can change
local f = CreateFrame("Frame", nil, CharacterFrame)
f:SetScript("OnEvent", RefreshDurability)

-- Minimal but sufficient set:
--  - UPDATE_INVENTORY_DURABILITY: core signal
--  - PLAYER_EQUIPMENT_CHANGED: swapping gear changes max/cur
--  - UNIT_INVENTORY_CHANGED: covers some edge cases (repairs via vendors/macros, followers, etc.)
--  - PLAYER_REGEN_ENABLED: in case repairs happen in instance end or after combat locks
--  - PLAYER_ENTERING_WORLD / ADDON_LOADED: initial pass (cheap anyway)
f:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
f:RegisterEvent("UNIT_INVENTORY_CHANGED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ADDON_LOADED")
