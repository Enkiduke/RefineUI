local _, RefineUI = ...
RefineUI.PlannerDefinitions = {
    sourceRevision = "4e3cbb8c5609e4bfc332c0aebbfa4d79731fab59",
    -- No exact credit increment or limited reward is inferred by these edges.
    relationships = {
        preyWorld = { verified = true, source = "Blizzard Prey overview / World Vault", effect = "advance",
            reason = "Contributes to World Great Vault progress" },
        questFaction = { verified = true, source = "C_QuestLog.GetQuestLogMajorFactionReputationRewards", effect = "advance" },
    },
    gates = { preyWeeklyReward = false, surgeDailyReward = false, treatiseConsumption = false,
        patronKnowledgeAmount = false, delveCofferEligibility = false, futurePatch = false },
}
