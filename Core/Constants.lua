local R, C, L = unpack(RefineUI)

----------------------------------------------------------------------------------------RefineUI	RefineUI variables
----------------------------------------------------------------------------------------
R.dummy = function() return end
R.name = UnitName("player")
R.class = select(2, UnitClass("player"))
R.level = UnitLevel("player")
R.client = GetLocale()
R.realm = GetRealmName()
local classColors = rawget(_G, "CUSTOM_CLASS_COLORS") or RAID_CLASS_COLORS or {}
R.color = classColors[R.class] or { r = 1, g = 1, b = 1 }
-- R.version = C_AddOns.GetAddOnRefineUIdata("RefineUI", "Version")
R.screenWidth, R.screenHeight = GetPhysicalScreenSize()
R.newPatch = select(4, GetBuildInfo()) >= 110000

----------------------------------------------------------------------------------------
--	Player's role and level check
----------------------------------------------------------------------------------------
local isCaster = {
	DEATHKNIGHT = {nil, nil, nil},
	DEMONHUNTER = {nil, nil},
	DRUID = {true},					-- Balance
	HUNTER = {nil, nil, nil},
	MAGE = {true, true, true},
	MONK = {nil, nil, nil},
	PALADIN = {nil, nil, nil},
	PRIEST = {nil, nil, true},		-- Shadow
	ROGUE = {nil, nil, nil},
	SHAMAN = {true},				-- Elemental
	WARLOCK = {true, true, true},
	WARRIOR = {nil, nil, nil},
	EVOKER = {true, true, true}
}

local function CheckRoleAndLevel(_, _, level)
	local spec = GetSpecialization()
	local role = spec and GetSpecializationRole(spec)

	R.Spec = spec
	if role == "TANK" then
		R.Role = "Tank"
	elseif role == "HEALER" then
		R.Role = "Healer"
	elseif role == "DAMAGER" then
		if isCaster[R.class] and spec and isCaster[R.class][spec] then
			R.Role = "Caster"
		else
			R.Role = "Melee"
		end
	end

	if level then
		R.level = level
	end
end

local Updater = CreateFrame("Frame")
Updater:RegisterEvent("PLAYER_ENTERING_WORLD")
Updater:RegisterEvent("PLAYER_TALENT_UPDATE")
Updater:RegisterEvent("PLAYER_LEVEL_UP")
Updater:SetScript("OnEvent", CheckRoleAndLevel)



-- BETA
GetContainerItemInfo = function(bagIndex, slotIndex)
	local info = C_Container.GetContainerItemInfo(bagIndex, slotIndex)
	if info then
		return info.iconFileID, info.stackCount, info.isLocked, info.quality, info.isReadable, info.hasLoot, info.hyperlink, info.isFiltered, info.hasNoValue, info.itemID, info.isBound
	end
end

UnitAura = function(unit, auraIndex, filter)
	return AuraUtil.UnpackAuraData(C_UnitAuras.GetAuraDataByIndex(unit, auraIndex, filter))
end

UnitBuff = function(unit, auraIndex, filter)
	return AuraUtil.UnpackAuraData(C_UnitAuras.GetBuffDataByIndex(unit, auraIndex, filter))
end

GetSpellInfo = function(data)
	local spellInfo = C_Spell.GetSpellInfo(data)
	if spellInfo then
		return spellInfo.name, nil, spellInfo.iconID, spellInfo.castTime, spellInfo.minRange, spellInfo.maxRange, spellInfo.spellID, spellInfo.originalIconID
	end
end

-- Only define EasyMenu if not already present to avoid clobbering Blizzard's implementation (or other addons)
if not EasyMenu then
local function EasyMenu_Initialize( frame, level, menuList )
	for index = 1, #menuList do
		local value = menuList[index]
		if (value.text) then
			value.index = index;
			UIDropDownMenu_AddButton( value, level );
		end
	end
end

function EasyMenu(menuList, menuFrame, anchor, x, y, displayMode, autoHideDelay )
	if ( displayMode == "MENU" ) then
		menuFrame.displayMode = displayMode;
	end
	UIDropDownMenu_Initialize(menuFrame, EasyMenu_Initialize, displayMode, nil, menuList);
	ToggleDropDownMenu(1, nil, menuFrame, anchor, x, y, menuList, nil, autoHideDelay);
end
end