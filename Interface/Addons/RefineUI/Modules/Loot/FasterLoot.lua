----------------------------------------------------------------------------------------
-- FasterLoot for RefineUI
-- Description: Accelerates auto-loot behavior when configured.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local FasterLoot = RefineUI:RegisterModule("FasterLoot", function(cfg)
    local loot = cfg.Loot
    if type(loot) ~= "table" or loot.Enable == false then
        return false
    end
    return loot.FasterLoot ~= false
end)

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
local GetNumLootItems = GetNumLootItems
local LootSlot = LootSlot
local GetCVarBool = GetCVarBool
local IsModifiedClick = IsModifiedClick

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local EVENT_KEY_LOOT_READY = "FasterLoot:LootReady"
local EVENT_KEY_LOOT_CLOSED = "FasterLoot:LootClosed"

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
-- LOOT_READY can fire more than once per loot session; loot each session once.
local lootedThisSession = false

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
			if not lootedThisSession then
				for i = GetNumLootItems(), 1, -1 do
					LootSlot(i)
				end
				lootedThisSession = true
			end
		end
	end, EVENT_KEY_LOOT_READY)

	RefineUI:RegisterEventCallback("LOOT_CLOSED", function()
		lootedThisSession = false
	end, EVENT_KEY_LOOT_CLOSED)
end
