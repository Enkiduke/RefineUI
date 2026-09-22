local _, RefineUI = ...
local Registry = { quests = {}, resources = {} }
RefineUI.PlannerRegistry = Registry
Registry.validation = { build = "12.1.0.69814", sourceRevision = "4e3cbb8c5609e4bfc332c0aebbfa4d79731fab59",
    status = "Semantic discovery candidates; live APIs must establish availability and values" }

-- IDs are metadata from References/Plumber's MID_Activity/ActivityUtil,
-- SharedData and the named sources below. Live log or quest-line evidence is
-- required for availability; registry cadence is only an observation bucket.
-- Entries do not assert rotation, reward entitlement or account completion.
local function Quest(id, category, mapID)
    Registry.quests[id] = { questID = id, category = category, mapID = mapID,
        expansion = 11, source = "Plumber MID_Activity/ActivityUtil", requireOnQuest = true }
end

local function WeeklyQuest(id, category, mapID, options)
    Quest(id, category, mapID)
    local entry = Registry.quests[id]
    entry.cadence, entry.weeklyQuest = "weekly", true
    for key, value in pairs(options or {}) do entry[key] = value end
    return entry
end
Quest(93784, "Delves")
Quest(95843, "Ritual Sites", 2393)
Quest(96995, "World", 2512); Quest(95520, "World", 2509)
for _, id in ipairs({ 96639, 96640, 96641, 96642, 96643, 96644, 98420 }) do Quest(id, "World", 2509) end
for _, id in ipairs({ 98232, 93890, 93767, 94457, 93909, 93911, 93769, 96727,
    93910, 93912, 95843, 93889, 93892, 95842, 93913, 93766 }) do Quest(id, "Weekly events", 2393) end
for id = 93751, 93758 do Quest(id, "Dungeons", 2393) end
Registry.quests[95843].category = "Ritual Sites"
Registry.quests[93910].category = "Prey"
-- MidnightChores separates activity completion IDs from the rotating meta
-- quests. Keep those identities distinct and never use lifetime quest flags.
for _, id in ipairs({ 90573, 90574, 90575, 90576 }) do Quest(id, "World", 2395) end
Quest(89507, "World")
for id = 88993, 88999 do Quest(id, "World", 2413) end
for _, id in ipairs({ 93593, 93595, 93599, 93598, 93600, 93611, 93612, 93605 }) do Quest(id, "Weekly events", 2393) end
Quest(94385, "World", 2395); Quest(94386, "World", 2437)
Quest(90962, "World", 2405)
Registry.quests[90962].activeWorldQuest = true
Registry.quests[90962].cadence = "weekly"
Registry.quests[90962].source = "MidnightChores Constants: Stormarion weekly activity"

-- Named reset quests from MidnightChores/Plumber. Metadata supplies cadence;
-- the live quest-line listing or quest log must still establish availability.
for _, id in ipairs({ 93784, 96995, 95520, 98232, 93890, 93767, 94457, 93909, 93911,
    93769, 96727, 93910, 93912, 95843, 93889, 93892, 95842, 93913, 93766,
    89507, 93593, 93595, 93599, 93598, 93600, 93611, 93612, 93605 }) do
    Registry.quests[id].cadence = "weekly"
    Registry.quests[id].weeklyQuest = true
end
for id = 93751, 93758 do Registry.quests[id].cadence = "weekly"; Registry.quests[id].weeklyQuest = true end
for id = 88993, 88999 do Registry.quests[id].cadence = "weekly"; Registry.quests[id].weeklyQuest = true end
for id = 90573, 90576 do Registry.quests[id].cadence = "weekly"; Registry.quests[id].weeklyQuest = true end

-- Additional reset-routine identities measured in the bundled MidnightHelper
-- reference. They remain discovery candidates: the live quest log or quest-line
-- listing must still establish that a quest is actionable for this character.
for _, id in ipairs({ 93891, 93761, 93164, 95468, 94836, 96713, 96717, 96718 }) do
    WeeklyQuest(id, "Weekly events", 2393, { source = "MidnightHelper ResetRoutine measured weekly pool" })
end
WeeklyQuest(98172, "Sparks", 2393, { source = "MidnightHelper measured quest-log identity", rewardClass = "spark" })
Registry.quests[96995].rewardClass = "spark"
Registry.quests[98232].rewardClass = "spark" -- Current-season reward is conditional on the Spark cap.
-- Zerella's War Mode quest rotates across zones; the Coiled Isle variant was
-- added in 12.1. All variants are one weekly choice, not five separate chores.
for _, id in ipairs({ 93423, 93424, 93425, 93426, 96808 }) do
    WeeklyQuest(id, "PvP", 2393, { rewardClass = "spark", optional = true,
        source = "Warcraft Wiki Sparks of War; Method Season 2 weekly guide" })
end
-- World Tour is a one-time Season 2 catch-up, not a repeating Spark weekly.
-- Observe it in the weekly quest cache while active, but never infer cadence
-- from that bookkeeping bucket or recommend it after lifetime completion.
Quest(95245, "Sparks", 2393)
Registry.quests[95245].oneTime = true
Registry.quests[95245].observationCadence = "weekly"
Registry.quests[95245].rewardClass = "sparkCatchUp"
Registry.quests[95245].source = "MidnightHelper CampaignLeadIn and Blizzard World Tour quest"

-- Verified profession trainer/service weeklies. These entries only make an
-- available quest discoverable; they do not infer completion or weekly KP totals.
local professionWeeklies = {
    [171] = { 93690 }, [164] = { 93691 }, [333] = { 93697, 93698, 93699 },
    [202] = { 93692 }, [182] = { 93700, 93701, 93702, 93703, 93704 },
    [773] = { 93693 }, [755] = { 93694 }, [165] = { 93695 },
    [186] = { 93705, 93706, 93707, 93708, 93709 },
    [393] = { 93710, 93711, 93712, 93713, 93714 }, [197] = { 93696 },
}
Registry.professionWeeklies = professionWeeklies
Registry.professionServices = { [171] = true, [164] = true, [202] = true, [773] = true,
    [755] = true, [165] = true, [197] = true }
-- Normalized Silvermoon coordinates from MidnightHelper's ResetRoutine.
-- Service quests use its Work Order station; Enchanting/gathering use trainers.
Registry.professionPickupPoints = {
    [171] = { x = 0.4500, y = 0.5560 }, [164] = { x = 0.4500, y = 0.5560 },
    [202] = { x = 0.4500, y = 0.5560 }, [773] = { x = 0.4500, y = 0.5560 },
    [755] = { x = 0.4500, y = 0.5560 }, [165] = { x = 0.4500, y = 0.5560 },
    [197] = { x = 0.4500, y = 0.5560 }, [333] = { x = 0.4797, y = 0.5363 },
    [182] = { x = 0.4820, y = 0.5152 }, [186] = { x = 0.4268, y = 0.5284 },
    [393] = { x = 0.4327, y = 0.5559 },
}
for skillLineID, quests in pairs(professionWeeklies) do
    for _, id in ipairs(quests) do
        WeeklyQuest(id, "Professions", 2393, { professionSkillLineID = skillLineID,
            rewardClass = "professionKnowledge", source = "MidnightHelper verified profession weekly table" })
    end
end

-- These are leads for a deliberate "check this giver" step, never proof that
-- the quest is currently offered. Coordinates belong to the named giver, not
-- the shared Silvermoon hub. Unverified pickup locations intentionally have
-- no position, so clicking them opens a map without placing a misleading pin.
Registry.discovery = {
    { key = "spark:vereesa", giver = "Vereesa Windrunner", questIDs = { 98172 }, mapID = 2393,
        position = { x = 0.4910, y = 0.6464 }, category = "Sparks", reward = "Trailing Xal'atath • potential Spark Dust", minLevel = 90, weight = 90,
        source = "Method Season 2 weekly guide" },
    { key = "spark:lorthemar", giver = "Lor'themar Theron", questIDs = { 95245 }, mapID = 2393,
        position = { x = 0.4539, y = 0.7033 }, category = "Sparks", reward = "World Tour • one-time Spark catch-up", minLevel = 90, weight = 80,
        oneTime = true, source = "Method Season 2 pickup; Blizzard World Tour" },
    { key = "spark:zela", giver = "Talon Commander Zela", questIDs = { 96995 }, mapID = 2512,
        position = { x = 0.5870, y = 0.4586 }, category = "Sparks", reward = "Turn Back the Surge • complete three Curse Surges", minLevel = 90, weight = 87,
        accessNote = "Coiled Isle", source = "Method Season 2 weekly guide" },
    { key = "spark:zerella", giver = "Zerella", questIDs = { 93423, 93424, 93425, 93426, 96808 }, mapID = 2393,
        position = { x = 0.3626, y = 0.8118 }, category = "PvP", reward = "Rotating Sparks of War weekly • collect 100", minLevel = 90, weight = 61,
        accessNote = "War Mode", source = "Warcraft Wiki; Method Season 2 weekly guide" },
    { key = "weekly:liadrin", giver = "Lady Liadrin", questIDs = { 98232, 93766, 93769, 93889, 93890,
        93891, 93892, 93909, 93910, 93911, 93913, 94457, 95842, 95843 }, mapID = 2393,
        position = { x = 0.4900, y = 0.6460 }, category = "Weekly quests", reward = "Choose one of four weekly objectives", minLevel = 90, weight = 65,
        source = "Warcraft Wiki Unity Against the Void; Blizzard Season 2 hotfixes" },
    { key = "weekly:halduron", giver = "Halduron Brightwing", questIDs = { 93761, 93164, 95468 },
        mapID = 2393, category = "Weekly quests", reward = "Rotating dungeon weekly", minLevel = 90, weight = 60,
        source = "MidnightHelper ResetRoutine" },
    { key = "weekly:aethas", giver = "Aethas Sunreaver", questIDs = { 93600, 94836, 93611 },
        mapID = 2393, category = "Weekly quests", reward = "Event or Timewalking weekly may be active", minLevel = 90, weight = 55,
        source = "MidnightHelper ResetRoutine" },
    { key = "weekly:abdumati", giver = "Warleader Abdumati", questIDs = { 95520 }, mapID = 2509,
        category = "Weekly quests", reward = "Purging the Vaults • weekly Vaults objective", minLevel = 90, weight = 62,
        accessNote = "Vaults of Atal'Utek", source = "Warcraft Wiki Purging the Vaults" },
}
Registry.pickupByQuestID = {}
for _, definition in ipairs(Registry.discovery) do
    if definition.position then
        for _, id in ipairs(definition.questIDs) do
            Registry.pickupByQuestID[id] = { mapID = definition.mapID, position = definition.position }
        end
    end
end

-- World boss rotation is only surfaced when its task is visible to this
-- character. These IDs are activity identities, never lifetime completion flags.
for id, mapID in pairs({ [92034] = 2413, [92123] = 2437, [92560] = 2395, [92636] = 2405 }) do
    Quest(id, "World bosses", mapID)
    Registry.quests[id].activeWorldQuest = true
    Registry.quests[id].cadence = "weekly"
    Registry.quests[id].icon = 132154
    Registry.quests[id].source = "MidnightChores Constants: WORLD_BOSS_QUEST_IDS"
end
for _, id in ipairs({ 91390, 91796, 92063, 92139, 92145, 93013, 93244, 93438 }) do
    Quest(id, "Special Assignments")
    Registry.quests[id].source = "MidnightChores Constants: SPECIAL_ASSIGNMENT_QUEST_IDS"
end

local function Resource(id, category, minBuild, maxBuild)
    Registry.resources[#Registry.resources + 1] = { currencyID = id, category = category,
        minBuild = minBuild, maxBuild = maxBuild, source = "Plumber SharedData", requireDiscovered = true }
end
for _, id in ipairs({ 3347, 3345, 3343, 3341, 3383 }) do Resource(id, "Crests", 120000, 120999) end
Resource(3378, "Catalyst", 120000, 120999)
for _, id in ipairs({ 3446, 3445, 3444, 3443, 3442 }) do Resource(id, "Crests", 121000, 121999) end
Resource(3465, "Catalyst", 121000, 121999)
Resource(3310, "Delves", 120000, 121999)
Resource(3028, "Delves", 120000, 121999)
Registry.resources[#Registry.resources].source = "MidnightChores Constants: restored coffer keys"
-- MidnightChores/Core/Constants.lua documents the Season 2 acquisition counter.
-- Its totalEarned/maxQuantity describe catch-up; quantity is not spendable Sparks.
Resource(3509, "Sparks", 121000, 121999)
Registry.resources[#Registry.resources].source = "MidnightChores Constants: Tidal Spark Dust"
Registry.resources[#Registry.resources].heldItemID = 274476

function Registry.ResourceIDs(build)
    local result = {}
    for _, entry in ipairs(Registry.resources) do
        if build >= entry.minBuild and build <= entry.maxBuild then result[entry.currencyID] = entry end
    end
    return result
end
