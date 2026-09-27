local _, RefineUI = ...
local Data = {}
RefineUI.PlannerData = Data

-- Identities come from the bundled MidnightChores, MidnightHelper, MidnightRoutine
-- and Plumber references and the Season 2 guides named per entry. Live quest-log,
-- quest-line, task and completion APIs still decide what the Planner shows.
Data.maps = { 2393, 2395, 2437, 2413, 2405, 2509, 2512 }
Data.quests = {}
local function Quest(ids, category, mapID, options)
    for _, id in ipairs(ids) do
        local entry = { category = category, mapID = mapID }
        for key, value in pairs(options or {}) do entry[key] = value end
        Data.quests[id] = entry
    end
end
local weekly = { weekly = true }
local function Range(first, last, step)
    local ids = {}
    for id = first, last, step or 1 do ids[#ids + 1] = id end
    return ids
end

Quest({ 93784 }, "Delves", nil, weekly)
Quest({ 95843 }, "Ritual Sites", 2393, weekly)
Quest({ 96995 }, "Sparks", 2512, { weekly = true, reward = "spark" })
Quest({ 95520 }, "World", 2509, weekly)
Quest({ 96639, 96640, 96641, 96642, 96643, 96644, 98420 }, "World", 2509)
Quest({ 93890, 93767, 94457, 93909, 93911, 93769, 96727, 93912, 93889, 93892, 95842, 93913, 93766,
    93593, 93595, 93599, 93598, 93600, 93611, 93612, 93605,
    93891, 93761, 93164, 95468, 94836, 96713, 96717, 96718 }, "Weekly quests", 2393, weekly)
Quest({ 98232 }, "Weekly quests", 2393, { weekly = true, reward = "spark" })
Quest({ 93910 }, "Prey", 2393, weekly)
Quest(Range(93751, 93758), "Dungeons", 2393, weekly)
Quest(Range(90573, 90576), "World", 2395, weekly)
Quest({ 89507 }, "World", nil, weekly)
Quest(Range(88993, 88999), "World", 2413, weekly)
Quest({ 94385 }, "World", 2395); Quest({ 94386 }, "World", 2437)
Quest({ 90962 }, "World", 2405, { weekly = true, worldQuest = true })
Quest({ 98172 }, "Sparks", 2393, { weekly = true, reward = "spark" })
-- Zerella's War Mode weekly rotates by zone; the Coiled Isle variant was added in 12.1.
Quest({ 93423, 93424, 93425, 93426, 96808 }, "PvP", 2393, { weekly = true, reward = "spark", optional = true })
-- World Tour is a one-time Season 2 Spark catch-up, not a weekly.
Quest({ 95245 }, "Sparks", 2393, { oneTime = true, reward = "sparkCatchUp" })
for id, mapID in pairs({ [92034] = 2413, [92123] = 2437, [92560] = 2395, [92636] = 2405 }) do
    Quest({ id }, "World bosses", mapID, { weekly = true, worldQuest = true, reward = "worldBoss", icon = 132154 })
end
Quest({ 91390, 91796, 92063, 92139, 92145, 93013, 93244, 93438 }, "Special Assignments", nil, { reward = "assignment" })

-- Pick-up leads for givers whose offer cannot be read before visiting them.
-- Coordinates belong to the named giver; entries without one open the map only.
Data.givers = {
    { key = "spark:vereesa", giver = "Vereesa Windrunner", questIDs = { 98172 }, mapID = 2393,
        position = { x = 0.4910, y = 0.6464 }, category = "Sparks", reward = "Trailing Xal'atath • Spark Dust", weight = 90 },
    { key = "spark:lorthemar", giver = "Lor'themar Theron", questIDs = { 95245 }, mapID = 2393,
        position = { x = 0.4539, y = 0.7033 }, category = "Sparks", reward = "World Tour • one-time Spark catch-up", weight = 80, oneTime = true },
    { key = "spark:zela", giver = "Talon Commander Zela", questIDs = { 96995 }, mapID = 2512,
        position = { x = 0.5870, y = 0.4586 }, category = "Sparks", reward = "Turn Back the Surge • three Curse Surges", weight = 87, note = "Coiled Isle" },
    { key = "spark:zerella", giver = "Zerella", questIDs = { 93423, 93424, 93425, 93426, 96808 }, mapID = 2393,
        position = { x = 0.3626, y = 0.8118 }, category = "PvP", reward = "Sparks of War • War Mode weekly", weight = 61, note = "War Mode", optional = true },
    { key = "weekly:liadrin", giver = "Lady Liadrin", questIDs = { 98232, 93766, 93769, 93889, 93890,
        93891, 93892, 93909, 93910, 93911, 93913, 94457, 95842, 95843 }, mapID = 2393,
        position = { x = 0.4900, y = 0.6460 }, category = "Weekly quests", reward = "Choose one of four weekly objectives", weight = 65 },
    { key = "weekly:halduron", giver = "Halduron Brightwing", questIDs = { 93761, 93164, 95468 },
        mapID = 2393, category = "Weekly quests", reward = "Rotating dungeon weekly", weight = 60 },
    { key = "weekly:aethas", giver = "Aethas Sunreaver", questIDs = { 93600, 94836, 93611 },
        mapID = 2393, category = "Weekly quests", reward = "Event or Timewalking weekly", weight = 55 },
    { key = "weekly:abdumati", giver = "Warleader Abdumati", questIDs = { 95520 }, mapID = 2509,
        category = "Weekly quests", reward = "Purging the Vaults", weight = 62, note = "Vaults of Atal'Utek" },
}
Data.pickupByQuestID = {}
for _, giver in ipairs(Data.givers) do
    if giver.position then
        for _, id in ipairs(giver.questIDs) do Data.pickupByQuestID[id] = giver end
    end
end

-- Weekly Knowledge sources from MidnightRoutine's Midnight profession table.
-- Each hidden tracking quest is flagged complete until the weekly reset.
-- Keys are the parent skill lines returned by GetProfessionInfo.
local SERVICE = { x = 0.4500, y = 0.5560 }
Data.professions = {
    [171] = { quest = { 93690 }, questKP = 1, point = SERVICE, treatise = 95127, treatiseItem = 245755, drops = { 93528, 93529 }, dropKP = 1 },
    [164] = { quest = { 93691 }, questKP = 2, point = SERVICE, treatise = 95128, treatiseItem = 245763, drops = { 93530, 93531 }, dropKP = 2 },
    [333] = { quest = { 93697, 93698, 93699 }, questKP = 3, point = { x = 0.4797, y = 0.5363 }, treatise = 95129, treatiseItem = 245759,
        drops = { 93532, 93533 }, dropKP = 2, gather = Range(95048, 95052), gatherKP = 1, bonus = 95053, bonusKP = 4 },
    [202] = { quest = { 93692 }, questKP = 1, point = SERVICE, treatise = 95138, treatiseItem = 245809, drops = { 93534, 93535 }, dropKP = 1 },
    [182] = { quest = Range(93700, 93704), questKP = 3, point = { x = 0.4820, y = 0.5152 }, treatise = 95130, treatiseItem = 245761,
        gather = Range(81425, 81429), gatherKP = 1, bonus = 81430, bonusKP = 4 },
    [773] = { quest = { 93693 }, questKP = 4, point = SERVICE, treatise = 95131, treatiseItem = 245757, drops = { 93536, 93537 }, dropKP = 2 },
    [755] = { quest = { 93694 }, questKP = 3, point = SERVICE, treatise = 95133, treatiseItem = 245760, drops = { 93538, 93539 }, dropKP = 2 },
    [165] = { quest = { 93695 }, questKP = 2, point = SERVICE, treatise = 95134, treatiseItem = 245758, drops = { 93540, 93541 }, dropKP = 2 },
    [186] = { quest = Range(93705, 93709), questKP = 3, point = { x = 0.4268, y = 0.5284 }, treatise = 95135, treatiseItem = 245762,
        gather = Range(88673, 88677), gatherKP = 1, bonus = 88678, bonusKP = 3 },
    [393] = { quest = Range(93710, 93714), questKP = 3, point = { x = 0.4327, y = 0.5559 }, treatise = 95136, treatiseItem = 245828,
        gather = { 88534, 88549, 88536, 88537, 88530 }, gatherKP = 1, bonus = 88529, bonusKP = 3 },
    [197] = { quest = { 93696 }, questKP = 2, point = SERVICE, treatise = 95137, treatiseItem = 245756, drops = { 93542, 93543 }, dropKP = 2 },
}
Data.treatisePoint = { x = 0.4500, y = 0.5560 }
for _, profession in pairs(Data.professions) do
    for _, id in ipairs(profession.quest) do
        Quest({ id }, "Professions", 2393, { weekly = true, reward = "knowledge", profession = true })
    end
end

-- Hidden per-hunt completion flags (MidnightRoutine Prey module). Season 2 guides
-- recommend four hunts a week; later hunts give sharply reduced progress.
Data.prey = { target = 4, giver = "Astalor Bloodsworn", mapID = 2393, ids = {} }
for _, ids in ipairs({ Range(91095, 91124), Range(91210, 91242, 2), Range(91243, 91255),
    Range(91211, 91241, 2), Range(91256, 91269), Range(95021, 95024) }) do
    for _, id in ipairs(ids) do Data.prey.ids[#Data.prey.ids + 1] = id end
end

-- Bountiful Delve area POIs by zone (MidnightRoutine Delves module). A POI is
-- only returned by C_AreaPoiInfo while that Delve is Bountiful.
Data.bountifulDelves = {
    [2393] = { 8426, 8440 }, [2424] = { 8428 }, [2395] = { 8438 }, [2405] = { 8432, 8430 },
    [2413] = { 8434, 8436 }, [2437] = { 8444, 8442 }, [2512] = { 8763, 8760 },
}
Data.coffer = { key = 3028, shards = 3310, tier = 8 }

Data.resources = {}
local function Resource(ids, category, minBuild, maxBuild, options)
    for _, id in ipairs(ids) do
        local entry = { currencyID = id, category = category, minBuild = minBuild, maxBuild = maxBuild }
        for key, value in pairs(options or {}) do entry[key] = value end
        Data.resources[#Data.resources + 1] = entry
    end
end
Resource({ 3347, 3345, 3343, 3341, 3383 }, "Crests", 120000, 120999)
Resource({ 3378 }, "Catalyst", 120000, 120999)
Resource({ 3446, 3445, 3444, 3443, 3442 }, "Crests", 121000, 121999)
Resource({ 3465 }, "Catalyst", 121000, 121999)
Resource({ 3310, 3028 }, "Delves", 120000, 121999)
-- 3509 counts Season 2 Spark acquisition; the spendable Sparks are item 274476.
Resource({ 3509 }, "Sparks", 121000, 121999, { heldItemID = 274476 })

function Data.ResourceIDs(build)
    local result = {}
    for _, entry in ipairs(Data.resources) do
        if build >= entry.minBuild and build <= entry.maxBuild then result[entry.currencyID] = entry end
    end
    return result
end

-- Recommendation value by reward class; higher sorts first within a priority tier.
Data.weights = { vaultClaim = 100, turnIn = 95, spark = 90, vault = 84, cofferKey = 80, sparkCatchUp = 80,
    prey = 76, worldBoss = 74, bountiful = 72, knowledge = 60, weekly = 58, assignment = 50, daily = 42, quest = 35 }
