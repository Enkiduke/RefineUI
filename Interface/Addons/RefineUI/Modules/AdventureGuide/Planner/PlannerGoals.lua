local _, RefineUI = ...
local Goals, Evidence = {}, RefineUI.PlannerEvidence
RefineUI.PlannerGoals = Goals

function Goals.Build(records, now)
    local goals, byID = {}, {}
    for _, record in ipairs(records) do
        local goalType = record.goalType
        if not goalType and record.kind == "Activity" then goalType = "quest" end
        if goalType then
            local fact = record.facts and record.facts.progress
            local known = Evidence.Valid(fact, now, { ownerKey = record.ownerKey, scope = record.scope,
                resetKey = record.resetKey, season = record.season, context = record.context }) and fact.verification ~= "snapshot"
            local goal = { id = record.goalID or record.id, recordID = record.id,
                outcomeID = record.outcomeID or record.goalID or record.id,
                type = goalType, title = record.title, category = record.category,
                current = record.current, target = record.target, evidence = fact,
                state = known and (record.state == "complete" and "complete" or "incomplete") or "unknown",
                importance = record.importance or "core", scope = record.scope, ownerKey = record.ownerKey,
                factionID = record.factionID, weeklyCapped = record.weeklyCapped,
                record = record }
            if not byID[goal.id] then goals[#goals + 1] = goal; byID[goal.id] = goal end
        end
    end
    return goals, byID
end
