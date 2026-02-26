----------------------------------------------------------------------------------------
-- FasterLoot for RefineUI
-- Description: Accelerates auto-loot behavior when configured.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local FasterLoot = RefineUI:RegisterModule("FasterLoot")

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
local GetTime = GetTime
local GetNumLootItems = GetNumLootItems
local LootSlot = LootSlot
local GetCVarBool = GetCVarBool
local IsModifiedClick = IsModifiedClick

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local LOOT_DELAY = 0.3
local EVENT_KEY_LOOT_READY = "FasterLoot:LootReady"

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
local lootDelayTimestamp = 0

function FasterLoot:OnEnable()
	if not RefineUI.Config.Loot.FasterLoot or not RefineUI.Config.Loot.Enable then
		return
	end

	RefineUI:RegisterEventCallback("LOOT_READY", function()
		local lootRules = RefineUI:GetModule("LootRules")
		if lootRules and lootRules.ShouldBypassFasterLoot and lootRules:ShouldBypassFasterLoot() then
			return
		end

		if GetCVarBool("autoLootDefault") ~= IsModifiedClick("AUTOLOOTTOGGLE") then
			if (GetTime() - lootDelayTimestamp) >= LOOT_DELAY then
				for i = GetNumLootItems(), 1, -1 do
					LootSlot(i)
				end
				lootDelayTimestamp = GetTime()
			end
		end
	end, EVENT_KEY_LOOT_READY)
end
