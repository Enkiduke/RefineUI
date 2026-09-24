----------------------------------------------------------------------------------------
-- BuffReminder Component: Data
-- Description: Buff definitions and default values
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local BuffReminder = RefineUI:GetModule("BuffReminder")
if not BuffReminder then return end

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config
local Media = RefineUI.Media
local Colors = RefineUI.Colors
local Locale = RefineUI.Locale

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local CATEGORY_ORDER = { "raid", "targeted", "self" }
local CATEGORY_LABELS = {
    raid = "Raid",
    targeted = "Target",
    self = "Self",
}

local RAID_BUFFS = {
    { key = "intellect", name = "Arcane Intellect", class = "MAGE", levelRequired = 8, spellID = { 1459, 432778 } },
    { key = "attackPower", name = "Battle Shout", class = "WARRIOR", levelRequired = 10, spellID = 6673 },
    { key = "devotionAura", name = "Devotion Aura", class = "PALADIN", castSpellID = 465, spellID = { 465, 32223, 317920 }, instanceBuffIDs = 465, isForm = true, skipPvP = true },
    { key = "bronze", name = "Blessing of the Bronze", class = "EVOKER", levelRequired = 30, castSpellID = 364342, spellID = { 381732, 381741, 381746, 381748, 381749, 381750, 381751, 381752, 381753, 381754, 381756, 381757, 381758 } },
    { key = "versatility", name = "Mark of the Wild", class = "DRUID", levelRequired = 10, spellID = { 1126, 432661 } },
    { key = "stamina", name = "Power Word: Fortitude", class = "PRIEST", levelRequired = 10, spellID = 21562 },
    { key = "skyfury", name = "Skyfury", class = "SHAMAN", levelRequired = 16, spellID = 462854 },
}

local TARGETED_BUFFS = {
    { key = "beaconOfFaith", name = "Beacon of Faith", class = "PALADIN", spellID = 156910, requireSpecId = 65 },
    { key = "beaconOfLight", name = "Beacon of Light", class = "PALADIN", spellID = 53563, requireSpecId = 65, excludeTalentSpellID = 200025, iconOverride = 236247 },
    { key = "earthShieldOthers", name = "Earth Shield", class = "SHAMAN", spellID = 974 },
    { key = "sourceOfMagic", name = "Source of Magic", class = "EVOKER", spellID = 369459, beneficiaryRole = "HEALER" },
    { key = "symbioticRelationship", name = "Symbiotic Relationship", class = "DRUID", spellID = 474750 },
    { key = "blisteringScales", name = "Blistering Scales", class = "EVOKER", spellID = 360827 },
    { key = "bestowWeyrnstone", name = "Bestow Weyrnstone", class = "EVOKER", spellID = 408233, buffIdOverride = 410318, requireSpecId = 1473 },
    { key = "timelessness", name = "Timelessness", class = "EVOKER", spellID = 412710, requireSpecId = 1473 },
    { key = "soulstone", name = "Soulstone", class = "WARLOCK", spellID = 20707, allowSolo = true, selfCast = true },
}

local SELF_BUFFS = {
    { key = "battleStance", name = "Battle Stance", class = "WARRIOR", spellID = 386164, requireSpecId = 71, customCheck = "stance", reminderType = "self" },
    { key = "berserkerStance", name = "Berserker Stance", class = "WARRIOR", spellID = 386196, requireSpecId = 72, customCheck = "stance", reminderType = "self" },
    { key = "defensiveStance", name = "Defensive Stance", class = "WARRIOR", spellID = 386208, requireSpecId = 73, customCheck = "stance", reminderType = "self" },
    { key = "arcaneFamiliar", name = "Arcane Familiar", class = "MAGE", spellID = 205022, buffIdOverride = 210126, reminderType = "self" },
    { key = "grimoireOfSacrifice", name = "Grimoire of Sacrifice", class = "WARLOCK", spellID = 108503, buffIdOverride = 196099, reminderType = "self" },
    { key = "riteOfAdjuration", name = "Rite of Adjuration", class = "PALADIN", spellID = 433583, enchantID = 7144, reminderType = "self" },
    { key = "riteOfSanctification", name = "Rite of Sanctification", class = "PALADIN", spellID = 433568, enchantID = 7143, reminderType = "self" },
    { key = "roguePoisons", name = "Rogue Poisons", class = "ROGUE", spellID = 2823, customCheck = "roguePoisons", reminderType = "self" },
    { key = "shadowform", name = "Shadowform", class = "PRIEST", spellID = 232698, buffIdOverride = { 232698, 194249 }, reminderType = "self" },
    { key = "earthlivingWeapon", name = "Earthliving Weapon", class = "SHAMAN", spellID = 382021, enchantID = 6498, reminderType = "self" },
    { key = "flametongueWeapon", name = "Flametongue Weapon", class = "SHAMAN", spellID = 318038, enchantID = 5400, reminderType = "self" },
    { key = "windfuryWeapon", name = "Windfury Weapon", class = "SHAMAN", spellID = 33757, enchantID = 5401, reminderType = "self" },
    { key = "tidecallersGuard", name = "Tidecaller's Guard", class = "SHAMAN", spellID = 457481, enchantID = 7528, requireShield = true, enchantSlot = "offhand", targetSlot = 17, reminderType = "self" },
    { key = "thunderstrikeWard", name = "Thunderstrike Ward", class = "SHAMAN", spellID = 462757, enchantID = 7587, requireShield = true, enchantSlot = "offhand", targetSlot = 17, reminderType = "self" },
    { key = "earthShieldSelfEO", name = "Earth Shield (Self)", class = "SHAMAN", spellID = 974, buffIdOverride = 383648, requiresTalentSpellID = 383010, reminderType = "self" },
    { key = "waterLightningShieldEO", name = "Water/Lightning Shield", class = "SHAMAN", spellID = { 192106, 52127 }, requiresTalentSpellID = 383010, iconByRole = { HEALER = 52127, DAMAGER = 192106, TANK = 192106 }, reminderType = "self" },
    { key = "shamanShieldBasic", name = "Shield (No Talent)", class = "SHAMAN", spellID = { 974, 192106, 52127 }, excludeTalentSpellID = 383010, iconByRole = { HEALER = 52127, DAMAGER = 192106, TANK = 192106 }, reminderType = "self" },
    { key = "blackAttunement", name = "Black Attunement", class = "EVOKER", spellID = 403264, buffIdOverride = { 403264, 403265 }, reminderType = "self" },
    { key = "bronzeAttunement", name = "Bronze Attunement", class = "EVOKER", spellID = 403265, buffIdOverride = { 403264, 403265 }, reminderType = "self" },
    { key = "frostMagePet", name = "Water Elemental", class = "MAGE", spellID = 31687, requireSpecId = 64, requiresTalentSpellID = 31687, customCheck = "missingPet", reminderType = "pet" },
    { key = "hunterPet", name = "Hunter Pet", class = "HUNTER", spellID = 883, iconOverride = 132161, customCheck = "hunterMissingPet", reminderType = "pet" },
    { key = "unholyPet", name = "Unholy Ghoul", class = "DEATHKNIGHT", spellID = 46584, requireSpecId = 252, customCheck = "missingPet", reminderType = "pet" },
    { key = "warlockPet", name = "Warlock Demon", class = "WARLOCK", spellID = 688, iconOverride = 136082, excludeTalentSpellID = 108503, customCheck = "missingPet", reminderType = "pet" },
}

local CATEGORY_BUFFS = {
    raid = RAID_BUFFS,
    targeted = TARGETED_BUFFS,
    self = SELF_BUFFS,
}

local BUFF_BENEFICIARIES = {
    intellect = { MAGE = true, WARLOCK = true, PRIEST = true, DRUID = true, SHAMAN = true, MONK = true, EVOKER = true, PALADIN = true, DEMONHUNTER = true },
    attackPower = { WARRIOR = true, ROGUE = true, HUNTER = true, DEATHKNIGHT = true, PALADIN = true, MONK = true, DRUID = true, DEMONHUNTER = true, SHAMAN = true },
}

BuffReminder.CATEGORY_ORDER = CATEGORY_ORDER
BuffReminder.CATEGORY_LABELS = CATEGORY_LABELS
BuffReminder.RAID_BUFFS = RAID_BUFFS
BuffReminder.CATEGORY_BUFFS = CATEGORY_BUFFS
BuffReminder.BUFF_BENEFICIARIES = BUFF_BENEFICIARIES
