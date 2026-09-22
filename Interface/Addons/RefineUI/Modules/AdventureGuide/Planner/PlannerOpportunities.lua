local _, RefineUI = ...
local Opportunities, E = {}, RefineUI.PlannerEvidence
RefineUI.PlannerOpportunities = Opportunities
local actionable = { available = true, inProgress = true, ready = true, claimable = true }

function Opportunities.Build(records, goals, preferences, now, dailyReset)
    local list, byID = {}, {}
    for _, r in ipairs(records) do
        local availability = r.facts and r.facts.availability
        local explicitlyFocused = preferences.focus and preferences.focus[r.id]
        local recommendationEligible = r.recommendable == true or explicitlyFocused
            or r.state == "ready" or r.state == "claimable"
        if actionable[r.state] and r.destination and r.actionable ~= false
            and recommendationEligible
            and r.kind == "Activity" and E.Valid(availability, now, { ownerKey = r.ownerKey, scope = r.scope,
                resetKey = r.resetKey, season = r.season, context = r.context }) and availability.value == true
            and availability.verification ~= "snapshot" and (not r.expiresAt or r.expiresAt > now)
            and not (preferences.hidden and preferences.hidden[r.id])
            and not (preferences.categories and preferences.categories[r.category]) then
            local o = RefineUI.PlannerModel.Copy(r)
            o.benefits, o.conditionalBenefits, o.reasons = {}, {}, {}
            o.focused = preferences.focus and preferences.focus[r.id] or false
            o.pinned = preferences.pins and preferences.pins[r.id] or false
            local outcomes = {}
            local function Add(goal, relationship, evidence, reason)
                if not goal or goal.state ~= "incomplete" or goal.weeklyCapped then return end
                if goal.scope == "character" and goal.ownerKey ~= r.ownerKey then return end
                if (goal.type == "journey" and goal.weeklyCapped ~= false)
                    or not relationship or not relationship.verified or not E.Valid(evidence, now, { ownerKey = r.ownerKey,
                    scope = r.scope, resetKey = r.resetKey, season = r.season, context = r.context })
                    or evidence.verification == "snapshot" then
                    o.conditionalBenefits[#o.conditionalBenefits + 1] = { goalID = goal.id, reason = reason }
                    return
                end
                if outcomes[goal.outcomeID] then return end
                outcomes[goal.outcomeID] = true
                o.benefits[#o.benefits + 1] = { goalID = goal.id, outcomeID = goal.outcomeID,
                    effect = relationship.effect or "advance", evidence = evidence, source = relationship.source, reason = reason }
                o.reasons[#o.reasons + 1] = reason
                if preferences.focus and preferences.focus[goal.recordID] then o.focused = true end
            end
            local own = goals[r.goalID or r.id]
            Add(own, { verified = true, source = r.source, effect = (r.state == "ready" or r.state == "claimable") and "collect" or "advance" },
                r.facts and r.facts.progress, r.rewardReason or r.detail or "Advances tracked progress")
            if r.contentType == "prey" and r.state ~= "ready" then
                local edge = RefineUI.PlannerDefinitions.relationships.preyWorld
                Add(goals["vault:next:3"], edge, availability, edge.reason)
            end
            for _, reward in ipairs(r.factionRewards or {}) do
                if reward.factionID and reward.rewardAmount and reward.rewardAmount > 0 then
                    local goal = goals["journey:" .. reward.factionID]
                    Add(goal, RefineUI.PlannerDefinitions.relationships.questFaction, reward.evidence,
                        "Rewards reputation toward " .. (goal and goal.title or "a Journey"))
                end
            end
            o.meaningfulGoalsAdvanced = #o.benefits
            o.recommendationWeight = r.recommendationWeight or 0
            o.priorityTier = (r.state == "ready" or r.state == "claimable") and 1
                or r.expiryVerified and r.expiresAt and dailyReset and r.expiresAt <= dailyReset and 2
                or o.focused and 3 or r.importance ~= "optional" and 4 or 5
            -- Cadence, readiness and expiry do not make old content a current
            -- priority. Focus is the player's explicit override; Pin is not.
            if not o.focused and r.contentEra == "legacy" then o.priorityTier = 6
            elseif not o.focused and r.contentEra == "unknown" then o.priorityTier = 5 end
            o.recommendationReason = r.recommendationReason
                or r.state == "ready" and "Ready to turn in"
                or r.state == "claimable" and "Reward ready"
                or o.priorityTier == 2 and "Expires before the daily reset"
                or o.priorityTier == 3 and "Focused by you"
                or r.rewardClass == "vaultMilestone" and "Next Great Vault choice"
                or r.rewardClass == "spark" and "Potential Spark Dust (season cap applies)"
                or r.rewardClass == "sparkCatchUp" and "One-time Spark catch-up"
                or r.rewardClass == "professionKnowledge" and "Profession Knowledge"
                or r.rewardClass == "cofferKey" and "Coffer Key reward"
                or o.priorityTier == 4 and "Weekly priority"
                or o.priorityTier == 5 and "Optional"
                or "Legacy content"
            o.rewardReason = table.concat(o.reasons, " • ")
            o.completesMilestone = r.state == "ready" or r.state == "claimable" or r.remainingActions == 1
            -- Compare effort only when the tied group shares a unit.
            o.effort = r.effort
            if #o.benefits > 0 then list[#list + 1] = o; byID[o.id] = o end
        end
    end
    local units = {}
    local function Group(o) return o.priorityTier .. ":" .. o.meaningfulGoalsAdvanced .. ":" .. tostring(o.completesMilestone) end
    for _, o in ipairs(list) do
        if o.effort then
            local key = Group(o)
            if units[key] == nil then units[key] = o.effort.unit elseif units[key] ~= o.effort.unit then units[key] = false end
        end
    end
    table.sort(list, function(a, b)
        if a.priorityTier ~= b.priorityTier then return a.priorityTier < b.priorityTier end
        if a.recommendationWeight ~= b.recommendationWeight then return a.recommendationWeight > b.recommendationWeight end
        if a.meaningfulGoalsAdvanced ~= b.meaningfulGoalsAdvanced then return a.meaningfulGoalsAdvanced > b.meaningfulGoalsAdvanced end
        if a.completesMilestone ~= b.completesMilestone then return a.completesMilestone == true end
        local ae, be = a.effort, b.effort
        if (ae ~= nil) ~= (be ~= nil) then return ae ~= nil end
        if ae and be and units[Group(a)] then
            if ae.count ~= be.count then return ae.count < be.count end
        end
        return a.id < b.id
    end)
    return list, byID
end
