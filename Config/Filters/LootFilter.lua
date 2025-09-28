local R, C, L = unpack(RefineUI)
if C.lootfilter.enable ~= true then return end

----------------------------------------------------------------------------------------
--	Loot Filter
----------------------------------------------------------------------------------------

-- Items that shouldn't be looted
R.LootFilterItems = {
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
R.LootFilterCurrency = {
	-- Shadowlands
	[1828] = true,		-- Soul Ash
	[1906] = true,		-- Soul Cinders
	[2009] = true,		-- Cosmic Flux
	[1979] = true,		-- Cyphers of the First Ones
	
	-- Draenor & Legion
	[824] = true,		-- Garrison Resources
	[1220] = true,		-- Order Resources
}

R.LootFilterCustom = R.LootFilterCustom or {}

-- Merge saved custom filter with R.LootFilterCustom
local function SaveCustomFilters()
    RefineUILootFilterDB = RefineUILootFilterDB or {}
    wipe(RefineUILootFilterDB)
    for itemID, value in pairs(R.LootFilterCustom) do
        RefineUILootFilterDB[itemID] = value
    end
end

-- These helpers are implemented and exposed by `Modules/Loot/LootFilter.lua` via slash commands.

-- Register an event to ensure RefineUILootFilterDB is properly initialized
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
    RefineUILootFilterDB = RefineUILootFilterDB or {}
        -- Re-merge saved filters in case they weren't available when this file first loaded
    for itemID, value in pairs(RefineUILootFilterDB) do
            R.LootFilterCustom[itemID] = value
        end
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)