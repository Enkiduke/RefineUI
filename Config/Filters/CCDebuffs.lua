local R, C, L = unpack(RefineUI)

-- Crowd Control debuffs whitelist for Nameplates CC bar
-- Map of spellID -> true
R.CCDebuffs = {
    -- Evoker
    [355689] = true, -- Landslide
    [370898] = true, -- Permeating Chill
    [408544] = true, -- Seismic Slam (Stun)
    [360806] = true, -- Sleep Walk
    -- Death Knight
    [47476]  = true, -- Strangulate
    [108194] = true, -- Asphyxiate UH
    [221562] = true, -- Asphyxiate Blood
    [207171] = true, -- Winter is Coming
    [206961] = true, -- Tremble Before Me
    [207167] = true, -- Blinding Sleet
    [212540] = true, -- Flesh Hook (Pet)
    [91807]  = true, -- Shambling Rush (Pet)
    [204085] = true, -- Deathchill
    [233395] = true, -- Frozen Center
    [212332] = true, -- Smash (Pet)
    [212337] = true, -- Powerful Smash (Pet)
    [91800]  = true, -- Gnaw (Pet)
    [91797]  = true, -- Monstrous Blow (Pet)
    [210141] = true, -- Zombie Explosion
    -- Demon Hunter
    [207685] = true, -- Sigil of Misery
    [217832] = true, -- Imprison
    [221527] = true, -- Imprison (Banished)
    [204490] = true, -- Sigil of Silence
    [179057] = true, -- Chaos Nova
    [211881] = true, -- Fel Eruption
    [205630] = true, -- Illidan's Grasp
    [208618] = true, -- Illidan's Grasp (Afterward)
    [213491] = true, -- Demonic Trample 1
    [208645] = true, -- Demonic Trample 2
    -- Druid
    [81261]  = true, -- Solar Beam
    [5211]   = true, -- Mighty Bash
    [163505] = true, -- Rake
    [203123] = true, -- Maim
    [202244] = true, -- Overrun
    [99]     = true, -- Incapacitating Roar
    [33786]  = true, -- Cyclone
    [45334]  = true, -- Immobilized
    [102359] = true, -- Mass Entanglement
    [339]    = true, -- Entangling Roots
    [2637]   = true, -- Hibernate
    [102793] = true, -- Ursol's Vortex
    -- Hunter
    [202933] = true, -- Spider Sting 1
    [233022] = true, -- Spider Sting 2
    [213691] = true, -- Scatter Shot
    [19386]  = true, -- Wyvern Sting
    [3355]   = true, -- Freezing Trap
    [203337] = true, -- Freezing Trap (PvP Talent)
    [209790] = true, -- Freezing Arrow
    [24394]  = true, -- Intimidation
    [117526] = true, -- Binding Shot
    [190927] = true, -- Harpoon
    [201158] = true, -- Super Sticky Tar
    [162480] = true, -- Steel Trap
    [212638] = true, -- Tracker's Net
    [200108] = true, -- Ranger's Net
    [356727] = true, -- Spider Venom (Silence)
    [407032] = true, -- Super Sticky Tar Bomb (Disarm)
    [407031] = true, -- Super Sticky Tar Bomb #2 (Disarm)
    [451517] = true, -- Catch Out (Root)
    -- Mage
    [61721]  = true, -- Rabbit
    [61305]  = true, -- Black Cat
    [28272]  = true, -- Pig
    [28271]  = true, -- Turtle
    [126819] = true, -- Porcupine
    [161354] = true, -- Monkey
    [161353] = true, -- Polar Bear
    [61780]  = true, -- Turkey
    [161355] = true, -- Penguin
    [161372] = true, -- Peacock
    [277787] = true, -- Direhorn
    [277792] = true, -- Bumblebee
    [118]    = true, -- Polymorph
    [82691]  = true, -- Ring of Frost
    [31661]  = true, -- Dragon's Breath
    [122]    = true, -- Frost Nova
    [33395]  = true, -- Freeze
    [157997] = true, -- Ice Nova
    [228600] = true, -- Glacial Spike
    [198121] = true, -- Frostbite
    [461489] = true, -- New Polymorph Variant
    [460392] = true, -- New Polymorph Variant
    [391622] = true, -- New Polymorph Variant
    [383121] = true, -- Mass Polymorph
    [449700] = true, -- Gravity Lapse (Root)
    -- Monk
    [119381] = true, -- Leg Sweep
    [202346] = true, -- Double Barrel
    [115078] = true, -- Paralysis
    [198909] = true, -- Song of Chi-Ji
    [202274] = true, -- Incendiary Brew
    [233759] = true, -- Grapple Weapon
    [123407] = true, -- Spinning Fire Blossom
    [116706] = true, -- Disable
    [232055] = true, -- Fists of Fury
    [324382] = true, -- Clash (Root)
    -- Paladin
    [853]    = true, -- Hammer of Justice
    [20066]  = true, -- Repentance
    [105421] = true, -- Blinding Light
    [31935]  = true, -- Avenger's Shield
    [217824] = true, -- Shield of Virtue
    [205290] = true, -- Wake of Ashes 1
    [255941] = true, -- Wake of Ashes 2
    -- Priest
    [9484]   = true, -- Shackle Undead
    [200196] = true, -- Holy Word: Chastise
    [200200] = true, -- Holy Word: Chastise
    [605]    = true, -- Mind Control
    [8122]   = true, -- Psychic Scream
    [15487]  = true, -- Silence
    [64044]  = true, -- Psychic Horror
    [453]    = true, -- Mind Soothe
    -- Rogue
    [2094]   = true, -- Blind
    [6770]   = true, -- Sap
    [1776]   = true, -- Gouge
    [1330]   = true, -- Garrote - Silence
    [207777] = true, -- Dismantle
    [408]    = true, -- Kidney Shot
    [1833]   = true, -- Cheap Shot
    [207736] = true, -- Shadowy Duel
    [212182] = true, -- Smoke Bomb
    -- Shaman
    [51514]  = true, -- Hex
    [211015] = true, -- Hex (Cockroach)
    [211010] = true, -- Hex (Snake)
    [211004] = true, -- Hex (Spider)
    [210873] = true, -- Hex (Compy)
    [196942] = true, -- Hex (Voodoo Totem)
    [269352] = true, -- Hex (Skeletal Hatchling)
    [277778] = true, -- Hex (Zandalari Tendonripper)
    [277784] = true, -- Hex (Wicker Mongrel)
    [118905] = true, -- Static Charge
    [77505]  = true, -- Earthquake (Knocking down)
    [118345] = true, -- Pulverize (Pet)
    [204399] = true, -- Earthfury
    [204437] = true, -- Lightning Lasso
    [157375] = true, -- Gale Force
    [64695]  = true, -- Earthgrab
    [197214] = true, -- Sundering (CC)
    -- Warlock
    [710]    = true, -- Banish
    [6789]   = true, -- Mortal Coil
    [118699] = true, -- Fear
    [6358]   = true, -- Seduction
    [171017] = true, -- Meteor Strike (Infernal)
    [22703]  = true, -- Infernal Awakening
    [30283]  = true, -- Shadowfury
    [89766]  = true, -- Axe Toss
    [233582] = true, -- Entrenched in Flame
    [130616] = true, -- Fear Standstill
    -- Warrior
    [5246]   = true, -- Intimidating Shout
    [132169] = true, -- Storm Bolt
    [132168] = true, -- Shockwave
    [199085] = true, -- Warpath
    [199042] = true, -- Thunderstruck
    [236077] = true, -- Disarm
    [105771] = true, -- Charge
    [316593] = true, -- Intimidating Shout Standstill
    [316595] = true, -- Intimidating Shout Standstill Others
    [385954] = true, -- Shield Charge (Stun)
    -- Racial
    [20549]  = true, -- War Stomp
    [107079] = true, -- Quaking Palm
    -- Uncategorized
    [389831] = true, -- Snowdrift (Stun)
}

-- Build a name->id map for environments where UnitAura may not return spellID
R.CCDebuffsByName = R.CCDebuffsByName or {}
for id, _ in pairs(R.CCDebuffs) do
    local name = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
    if name then
        R.CCDebuffsByName[name] = id
    end
end

return R
