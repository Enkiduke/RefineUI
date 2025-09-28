local R, C, L = unpack(RefineUI)
if C and C.lootfilter and C.lootfilter.enable then
	-- LootFilter handles fast, filtered looting; disable this module to avoid conflict.
	return
end

----------------------------------------------------------------------------------------
--	Faster auto looting (only active when loot filter is disabled)
----------------------------------------------------------------------------------------
local tDelay = 0
local LOOT_DELAY = 0.3

local frame = CreateFrame("Frame")
frame:RegisterEvent("LOOT_READY")
frame:SetScript("OnEvent", function ()
	if GetCVarBool("autoLootDefault") ~= IsModifiedClick("AUTOLOOTTOGGLE") then
		if (GetTime() - tDelay) >= LOOT_DELAY then
			for i = GetNumLootItems(), 1, -1 do
				LootSlot(i)
			end
			tDelay = GetTime()
		end
	end
end)

----------------------------------------------------------------------------------------
--	Faster auto looting
----------------------------------------------------------------------------------------
local tDelay = 0
local LOOT_DELAY = 0.3

local frame = CreateFrame("Frame")
frame:RegisterEvent("LOOT_READY")
frame:SetScript("OnEvent", function ()
	if GetCVarBool("autoLootDefault") ~= IsModifiedClick("AUTOLOOTTOGGLE") then
		if (GetTime() - tDelay) >= LOOT_DELAY then
			for i = GetNumLootItems(), 1, -1 do
				LootSlot(i)
			end
			tDelay = GetTime()
		end
	end
end)