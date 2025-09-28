----------------------------------------------------------------------------------------
--	AutoPotion Module for RefineUI
--	This module maintains a macro that uses self-healing spells, healthstones, 
--	and healing potions in a prioritized sequence.
--	Priority: Player Healing Spells -> Crimson Vial (optional) -> Healthstone -> Healing Potions
----------------------------------------------------------------------------------------

local R, C, L = unpack(RefineUI)

-- Early return if the module is disabled
if not C.automation.autoPotion then return end

----------------------------------------------------------------------------------------
-- Data: Spells, Potions, and Healthstones
----------------------------------------------------------------------------------------

-- List of supported self-healing spell IDs (prioritized from best to worst)
local healingSpellIDs = {
	-- Class Spells (excluding Crimson Vial - handled separately)
	108238, -- Renewal (Druid)
	109304, -- Exhilaration (Hunter)
	388035, -- Fortitude of the Bear (Druid)
	12975,  -- Last Stand (Warrior)
	383762, -- Bitter Immunity (Evoker)
	19236,  -- Desperate Prayer (Priest)
	322101, -- Expel Harm (Monk)
	122281, -- Healing Elixir (Monk)
	108416, -- Dark Pact (Warlock)
	55233,  -- Vampiric Blood (Death Knight)
	-- Racial Spells (Gift of the Naaru, various versions)
	59545, 59543, 59548, 416250, 121093, 59542, 59544, 370626, 59547, 28880,
	312411, -- Bag of Tricks (Vulpera)
}

-- Crimson Vial handled separately due to config option
local crimsonVialID = 185311

-- Recuperate (Rogue, out of combat only)
local recuperateID = 1231411

-- Prioritized list of healing potion item IDs (Retail)
local healingPotionIDs = {
	-- The War Within
	244839, 244838, 244835, 244849, 244848, 244847,
	-- Dragonflight
	211880, 211879, 211878, 212944, 212943, 212942, 207023, 207022, 207021,
	191380, 191379, 191378,
	-- Shadowlands
	171267, 187802,
	-- Older Expansions
	169451, 152494, 127834, 76097, 57191
}

-- Prioritized list of Healthstone item IDs (Retail)
local healthstoneIDs = { 224464, 5512 } -- Demonic Healthstone, Healthstone

----------------------------------------------------------------------------------------
-- AutoPotion Module
----------------------------------------------------------------------------------------
local AutoPotion = {}

----------------------------------------------------------------------------------------
-- Local Variables
----------------------------------------------------------------------------------------
local combatRetry = 0
local bagUpdateScheduled = false

----------------------------------------------------------------------------------------
-- Helper Functions
----------------------------------------------------------------------------------------
function AutoPotion:GetBestHealthstone()
	for _, itemID in ipairs(healthstoneIDs) do
		if C_Item.GetItemCount(itemID) > 0 then
			return itemID
		end
	end
	return nil
end

function AutoPotion:GetBestHealingPotion()
	for _, itemID in ipairs(healingPotionIDs) do
		if C_Item.GetItemCount(itemID) > 0 then
			return itemID
		end
	end
	return nil
end

function AutoPotion:BuildHealingSpellSequence()
	local spells = {}
	
	-- Add regular healing spells (excluding Crimson Vial)
	for _, spellID in ipairs(healingSpellIDs) do
		if IsSpellKnown(spellID, false) then
			local spellName = GetSpellInfo(spellID)
			if spellName then
				table.insert(spells, spellName)
			end
		end
	end
	
	-- Add Crimson Vial if enabled and known
	if C.automation.autoPotionCrimsonVial and IsSpellKnown(crimsonVialID, false) then
		local spellName = GetSpellInfo(crimsonVialID)
		if spellName then
			table.insert(spells, spellName)
		end
	end
	
	return spells
end

function AutoPotion:BuildMacroSequence()
	local macroSequence = {}
	
	-- 1. Add known self-healing spells
	local healingSpells = self:BuildHealingSpellSequence()
	for _, spellName in ipairs(healingSpells) do
		table.insert(macroSequence, spellName)
	end
	
	-- 2. Find best available items
	local bestHealthstoneID = self:GetBestHealthstone()
	local bestPotionID = self:GetBestHealingPotion()
	
	-- 3. Add items based on priority config
	local stoneEntry = bestHealthstoneID and ("item:" .. bestHealthstoneID) or nil
	local potionEntry = bestPotionID and ("item:" .. bestPotionID) or nil
	
	if C.automation.autoPotionRaidStone then
		-- Lower priority for healthstone (potions first)
		if potionEntry then table.insert(macroSequence, potionEntry) end
		if stoneEntry then table.insert(macroSequence, stoneEntry) end
	else
		-- Default: higher priority for healthstone
		if stoneEntry then table.insert(macroSequence, stoneEntry) end
		if potionEntry then table.insert(macroSequence, potionEntry) end
	end
	
	return macroSequence
end

function AutoPotion:UpdateMacro()
	-- Don't update macro while in combat
	if InCombatLockdown() then
		if combatRetry < 4 then
			combatRetry = combatRetry + 1
			C_Timer.After(0.5, function() self:UpdateMacro() end)
		end
		return
	end
	combatRetry = 0
	
	local macroSequence = self:BuildMacroSequence()
	
	-- Build the final macro string
	local macroBody = ""
	if #macroSequence > 0 then
		local sequenceString = table.concat(macroSequence, ", ")
		macroBody = "/castsequence [@player] reset=combat " .. sequenceString
	end
	
	-- Handle Recuperate separately for out-of-combat use
	local recuperateString = ""
	if IsSpellKnown(recuperateID, false) then
		local recuperateName = GetSpellInfo(recuperateID)
		if recuperateName then
			recuperateString = "/cast [nocombat] " .. recuperateName .. "\n"
		end
	end
	
	-- Build final macro
	local stopCastString = C.automation.autoPotionStopCast and "/stopcasting\n" or ""
	local finalMacroString = "#showtooltip\n" .. stopCastString .. recuperateString .. macroBody
	
	-- Create or update the macro
	local macroName = C.automation.autoPotionMacroName
	local macroExists = GetMacroInfo(macroName)
	if not macroExists then
		CreateMacro(macroName, "INV_Misc_QuestionMark", finalMacroString)
	else
		EditMacro(macroName, nil, nil, finalMacroString)
	end
end

function AutoPotion:OnBagUpdate()
	if bagUpdateScheduled then return end
	bagUpdateScheduled = true
	-- Wait 3 seconds after a bag update to prevent spamming updates
	C_Timer.After(3, function()
		self:UpdateMacro()
		bagUpdateScheduled = false
	end)
end

----------------------------------------------------------------------------------------
-- Event Handling
----------------------------------------------------------------------------------------
function AutoPotion:OnEvent(event, arg1)
	if event == "ADDON_LOADED" and arg1 == "RefineUI" then
		self:UpdateMacro()
	elseif InCombatLockdown() then
		return -- Don't do anything while in combat
	elseif event == "BAG_UPDATE" then
		self:OnBagUpdate()
	elseif event == "PLAYER_ENTERING_WORLD" then
		self:UpdateMacro()
	elseif event == "PLAYER_REGEN_ENABLED" then
		-- Wait a moment after combat ends before updating
		C_Timer.After(0.5, function() self:UpdateMacro() end)
	elseif event == "LEARNED_SPELL_IN_TAB" then
		-- Update when learning new spells
		C_Timer.After(0.5, function() self:UpdateMacro() end)
	end
end

----------------------------------------------------------------------------------------
-- Frame Creation and Registration
----------------------------------------------------------------------------------------
local AutoPotionFrame = CreateFrame("Frame")

-- Apply the mixin to the frame
for k, v in pairs(AutoPotion) do
	AutoPotionFrame[k] = v
end

-- Register events
AutoPotionFrame:RegisterEvent("ADDON_LOADED")
AutoPotionFrame:RegisterEvent("BAG_UPDATE")
AutoPotionFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
AutoPotionFrame:RegisterEvent("PLAYER_REGEN_ENABLED") -- Fires on exiting combat
AutoPotionFrame:RegisterEvent("LEARNED_SPELL_IN_TAB") -- Fires when learning new spells

-- Set up event handling
AutoPotionFrame:SetScript("OnEvent", function(self, event, arg1)
	AutoPotion:OnEvent(event, arg1)
end)
