local R, C, L = unpack(RefineUI)

----------------------------------------------------------------------------------------
--	Spell Databases for Advanced Combat Log
----------------------------------------------------------------------------------------
R.spells = {
    taunts = {
        -- Death Knight
        [56222] = true,  -- Dark Command
        [49576] = true,  -- Death Grip (for Blood death knights)
        -- Demon Hunter
        [185245] = true, -- Torment
        -- Druid
        [6795] = true,   -- Growl (Bear Form)
        -- Hunter
        [2649] = true,   -- Growl (pet ability)
        -- Monk
        [115546] = true, -- Provoke
        -- Paladin
        [62124] = true,  -- Hand of Reckoning
        -- Warrior
        [355] = true,    -- Taunt
        -- Warlock
        [17735] = true,  -- Suffering (Voidwalker minion)
    },
    interrupts = {
        -- Death Knight
        [47528] = true,   -- Mind Freeze
        [91802] = true,   -- Shambling Rush (Abomination Limb)
        -- Demon Hunter
        [183752] = true,  -- Disrupt
        [217832] = true,  -- Imprison
        -- Druid
        [93985] = true,   -- Skull Bash
        [106839] = true,  -- Skull Bash (Feral)
        [97547] = true,   -- Solar Beam
        -- Evoker
        [351338] = true,  -- Quell
        -- Hunter
        [147362] = true,  -- Counter Shot
        [187707] = true,  -- Muzzle
        -- Mage
        [2139] = true,    -- Counterspell
        -- Monk
        [116705] = true,  -- Spear Hand Strike
        -- Paladin
        [96231] = true,   -- Rebuke
        [31935] = true,   -- Avenger's Shield
        -- Priest
        [15487] = true,   -- Silence
        -- Rogue
        [1766] = true,    -- Kick
        -- Shaman
        [57994] = true,   -- Wind Shear
        -- Warlock
        [19647] = true,   -- Spell Lock (Felhunter)
        [115781] = true,  -- Optical Blast (Observer)
        [132409] = true,  -- Spell Lock (Command Demon)
        -- Warrior
        [6552] = true,    -- Pummel
    },
    dispels = {
        -- Druid
        [2782] = true,   -- Remove Corruption
        [88423] = true,  -- Nature's Cure
        -- Evoker
        [365585] = true, -- Expunge
        [360823] = true, -- Naturalize
        -- Mage
        [475] = true,    -- Remove Curse
        -- Monk
        [115450] = true, -- Detox
        -- Paladin
        [4987] = true,   -- Cleanse
        -- Priest
        [527] = true,    -- Purify
        [213634] = true, -- Purify Disease
        [32375] = true,  -- Mass Dispel
        -- Shaman
        [51886] = true,  -- Cleanse Spirit
        [77130] = true,  -- Purify Spirit
        -- Warlock
        [89808] = true,  -- Singe Magic (Imp)
        [119905] = true, -- Command Demon (when Imp is active)
    },
    crowdControl = {
        -- Warrior
        [5246] = true,   -- Intimidating Shout
        [132168] = true, -- Shockwave
        [6552] = true,   -- Pummel
        [132169] = true, -- Storm Bolt

        -- Warlock
        [118699] = true, -- Fear
        [6789] = true,   -- Mortal Coil
        [19647] = true,  -- Spelllock
        [30283] = true,  -- Shadowfury
        [710] = true,    -- Banish
        [212619] = true, -- Call Felhunter
        [5484] = true,   -- Howl of Terror

        -- Mage
        [118] = true,    -- Polymorph
        [61305] = true,  -- Polymorph (black cat)
        [28271] = true,  -- Polymorph Turtle
        [161354] = true, -- Polymorph Monkey
        [161353] = true, -- Polymorph Polar Bear Cub
        [126819] = true, -- Polymorph Porcupine
        [277787] = true, -- Polymorph Direhorn
        [61721] = true,  -- Polymorph Rabbit
        [28272] = true,  -- Polymorph Pig
        [277792] = true, -- Polymorph Bumblebee
        [391622] = true, -- Polymorph Duck
        [82691] = true,  -- Ring of Frost
        [122] = true,    -- Frost Nova
        [157997] = true, -- Ice Nova
        [31661] = true,  -- Dragon's Breath
        [157981] = true, -- Blast Wave

        -- Priest
        [205364] = true, -- Mind Control (talent)
        [605] = true,    -- Mind Control
        [8122] = true,   -- Psychic Scream
        [9484] = true,   -- Shackle Undead
        [200196] = true, -- Holy Word: Chastise
        [200200] = true, -- Holy Word: Chastise (talent)
        [226943] = true, -- Mind Bomb
        [64044] = true,  -- Psychic Horror
        [15487] = true,  -- Silence

        -- Rogue
        [2094] = true,   -- Blind
        [427773] = true, -- Blind (AoE)
        [1833] = true,   -- Cheap Shot
        [408] = true,    -- Kidney Shot
        [6770] = true,   -- Sap
        [1776] = true,   -- Gouge

        -- Paladin
        [853] = true,    -- Hammer of Justice
        [20066] = true,  -- Repentance
        [105421] = true, -- Blinding Light
        [217824] = true, -- Shield of Virtue
        [10326] = true,  -- Turn Evil

        -- Death Knight
        [221562] = true, -- Asphyxiate
        [108194] = true, -- Asphyxiate (talent)
        [91807] = true,  -- Shambling Rush
        [207167] = true, -- Blinding Sleet
        [334693] = true, -- Absolute Zero

        -- Druid
        [339] = true,    -- Entangling Roots
        [2637] = true,   -- Hibernate
        [61391] = true,  -- Typhoon
        [102359] = true, -- Mass Entanglement
        [99] = true,     -- Incapacitating Roar
        [236748] = true, -- Intimidating Roar
        [5211] = true,   -- Mighty Bash
        [45334] = true,  -- Immobilized
        [203123] = true, -- Maim
        [50259] = true,  -- Dazed (from Wild Charge)
        [209753] = true, -- Cyclone (PvP talent)
        [33786] = true,  -- Cyclone (PvP talent - resto druid)
        [163505] = true, -- Rake
        [127797] = true, -- Ursol's Vortex

        -- Hunter
        [187707] = true, -- Muzzle
        [3355] = true,   -- Freezing Trap / Diamond Ice
        [19577] = true,  -- Intimidation
        [190927] = true, -- Harpoon
        [162480] = true, -- Steel Trap
        [24394] = true,  -- Intimidation
        [117405] = true, -- Binding Shot (trigger)
        [117526] = true, -- Binding Shot (triggered)
        [1513] = true,   -- Scare Beast

        -- Monk
        [119381] = true, -- Leg Sweep
        [115078] = true, -- Paralysis
        [198909] = true, -- Song of Chi-Ji
        [116706] = true, -- Disable
        [107079] = true, -- Quaking Palm (racial)
        [116705] = true, -- Spear Hand Strike

        -- Shaman
        [118905] = true, -- Static Charge (Capacitor Totem)
        [51514] = true,  -- Hex
        [210873] = true, -- Hex (Compy)
        [211004] = true, -- Hex (Spider)
        [211010] = true, -- Hex (Snake)
        [211015] = true, -- Hex (Cockroach)
        [269352] = true, -- Hex (Skeletal Hatchling)
        [277778] = true, -- Hex (Zandalari Tendonripper)
        [277784] = true, -- Hex (Wicker Mongrel)
        [309328] = true, -- Hex (Living Honey)
        [64695] = true,  -- Earthgrab
        [197214] = true, -- Sundering

        -- Demon Hunter
        [179057] = true, -- Chaos Nova
        [217832] = true, -- Imprison
        [200166] = true, -- Metamorphosis
        [207685] = true, -- Sigil of Misery
        [211881] = true, -- Fel Eruption

        -- Evoker
        [372245] = true, -- Terror of the Skies
        [360806] = true, -- Sleep Walk

        -- Covenant (Venthyr)
        [331866] = true, -- Agent of Chaos (Nadia soulbind)
    },

    -- Utilities (scoped announcements)
    utilities = {
        bots = {
            [22700] = true,  -- 修理機器人74A型
            [44389] = true,  -- 修理機器人110G型
            [54711] = true,  -- 廢料機器人
            [67826] = true,  -- 吉福斯
            [126459] = true, -- 布靈登4000型
            [157066] = true, -- 沃特
            [161414] = true, -- 布靈登5000型
            [199109] = true, -- 自動鐵錘
            [200061] = true, -- 召喚劫福斯
            [200204] = true, -- 自動鐵錘模式
            [200205] = true, -- 自動鐵錘模式
            [200210] = true, -- 滅團偵測水晶塔
            [200211] = true, -- 滅團偵測水晶塔
            [200212] = true, -- 煙火展示模式
            [200214] = true, -- 煙火展示模式
            [200215] = true, -- 點心發送模式
            [200216] = true, -- 點心發送模式
            [200217] = true, -- 閃亮模式
            [200218] = true, -- 閃亮模式
            [200219] = true, -- 機甲戰鬥模式
            [200220] = true, -- 機甲戰鬥模式
            [200221] = true, -- 蟲洞生成模式
            [200222] = true, -- 蟲洞生成模式
            [200223] = true, -- 熱能鐵砧模式
            [200225] = true, -- 熱能鐵砧模式
            [226241] = true, -- 靜心寶典
            [256230] = true, -- 寧神寶典
            [298926] = true, -- 布靈登7000型
            [324029] = true, -- 寧心寶典
            [453942] = true, -- 阿爾加修理機器人11O
        },
        feasts = {
            [104958] = true, -- 熊貓人盛宴
            [126492] = true, -- 燒烤盛宴
            [126494] = true, -- 豪華燒烤盛宴
            [126495] = true, -- 快炒盛宴
            [126496] = true, -- 豪華快炒盛宴
            [126497] = true, -- 燉煮盛宴
            [126498] = true, -- 豪華燉煮盛宴
            [126499] = true, -- 蒸煮盛宴
            [126500] = true, -- 豪華蒸煮盛宴
            [126501] = true, -- 烘烤盛宴
            [126502] = true, -- 豪華烘烤盛宴
            [126503] = true, -- 美酒盛宴
            [126504] = true, -- 豪華美酒盛宴
            [145166] = true, -- 拉麵推車
            [145169] = true, -- 豪華拉麵推車
            [145196] = true, -- 熊貓人國寶級拉麵推車
            [188036] = true, -- 靈魂大鍋
            [201351] = true, -- 澎湃盛宴
            [201352] = true, -- 蘇拉瑪爾豪宴
            [259409] = true, -- 艦上盛宴
            [259410] = true, -- 豐盛的船長饗宴
            [276972] = true, -- 神秘大鍋
            [286050] = true, -- 血潤盛宴
            [297048] = true, -- 超澎湃饗宴
            [298861] = true, -- 強效神秘大鍋
            [307157] = true, -- 永恆大鍋
            [308458] = true, -- 意外可口盛宴
            [308462] = true, -- 暴食享樂盛宴
            [382423] = true, -- 雨莎的澎湃燉肉
            [382427] = true, -- 卡魯耶克的豪華盛宴
            [383063] = true, -- 製作加料龍族佳餚大餐
            [455960] = true, -- 大雜燴
            [457283] = true, -- 神聖日盛宴
            [457285] = true, -- 午夜化妝舞會盛宴
            [457302] = true, -- 特級壽司
            [457487] = true, -- 澎湃大雜燴
            [462211] = true, -- 澎湃特級壽司
            [462212] = true, -- 澎湃神聖日盛宴
            [462213] = true, -- 澎湃午夜化妝舞會盛宴
        },
        feasts_cast_succeeded = {
            [359336] = true, -- 準備石頭湯之壺
            [432877] = true, -- 準備阿爾加精煉藥劑大鍋
            [432878] = true, -- 準備阿爾加精煉藥劑大鍋
            [432879] = true, -- 準備阿爾加精煉藥劑大鍋
            [433292] = true, -- 準備阿爾加藥水大鍋
            [433293] = true, -- 準備阿爾加藥水大鍋
            [433294] = true, -- 準備阿爾加藥水大鍋
        },
        portals = {
            -- 聯盟
            [10059] = true,  -- 傳送門：暴風城
            [11416] = true,  -- 傳送門：鐵爐堡
            [11419] = true,  -- 傳送門：達納蘇斯
            [32266] = true,  -- 傳送門：艾克索達
            [33691] = true,  -- 傳送門：撒塔斯
            [49360] = true,  -- 傳送門：塞拉摩
            [88345] = true,  -- 傳送門：托巴拉德
            [132620] = true, -- 傳送門：恆春谷
            [176246] = true, -- 傳送門：暴風之盾
            [281400] = true, -- 傳送門：波拉勒斯
            -- 部落
            [11417] = true,  -- 傳送門：奧格瑪
            [11418] = true,  -- 傳送門：幽暗城
            [11420] = true,  -- 傳送門：雷霆崖
            [32267] = true,  -- 傳送門：銀月城
            [35717] = true,  -- 傳送門：撒塔斯
            [49361] = true,  -- 傳送門：斯通納德
            [88346] = true,  -- 傳送門：托巴拉德
            [132626] = true, -- 傳送門：恆春谷
            [176244] = true, -- 傳送門：戰爭之矛
            [281402] = true, -- 傳送門：達薩亞洛
            -- 中立
            [53142] = true,  -- 傳送門：達拉然－北裂境
            [120146] = true, -- 遠古傳送門：達拉然
            [224871] = true, -- 傳送門：達拉然－破碎群島
            [344597] = true, -- 傳送門：奧睿博司
            [395289] = true, -- 傳送門：沃卓肯
            [446534] = true, -- 傳送門：多恩諾加
        },
    },

    -- Combat Res only
    combatRes = {
        [20484] = true,  -- Druid: Rebirth
        [61999] = true,  -- Death Knight: Raise Ally
        [391054] = true, -- Paladin: Intercession
        [20707] = true,  -- Warlock: Soulstone Resurrection (when used)
    },
} 
