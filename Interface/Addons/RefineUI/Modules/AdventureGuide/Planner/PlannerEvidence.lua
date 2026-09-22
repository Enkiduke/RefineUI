-- Only plain, explicitly selected API fields cross into Planner state.
local _, RefineUI = ...
local Evidence = {}
RefineUI.PlannerEvidence = Evidence

function Evidence.Accessible(value)
    if issecretvalue and issecretvalue(value) then return false end
    if canaccessvalue and not canaccessvalue(value) then return false end
    return true
end

function Evidence.Number(value)
    return Evidence.Accessible(value) and type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

function Evidence.Table(value)
    return Evidence.Accessible(value) and type(value) == "table"
        and (not canaccesstable or canaccesstable(value))
end

local function Fields(numbers, strings, booleans)
    local schema = {}
    for field in (numbers or ""):gmatch("%S+") do schema[field] = "number" end
    for field in (strings or ""):gmatch("%S+") do schema[field] = "string" end
    for field in (booleans or ""):gmatch("%S+") do schema[field] = "boolean" end
    return schema
end
Evidence.Fields = Fields
local objective = Fields("numFulfilled numRequired objectiveType", "text type", "finished")
local reward = Fields("currencyID quantity totalRewardAmount factionID rewardAmount")
local poi = Fields("areaPoiID linkedUiMapID tooltipWidgetSet iconWidgetSet factionID", "name description atlasName uiTextureKit", "isCurrentEvent isLocked isPrimaryMapForPOI")
poi.position = "position"
local currency = Fields("currencyID quantity iconFileID maxQuantity quantityEarnedThisWeek maxWeeklyQuantity totalEarned rechargingCycleDurationMS rechargingAmountPerCycle", "name description", "isHeader isTypeUnused discovered useTotalEarnedForMaxQty isAccountWide isAccountTransferable canEarnPerWeek")
local tierReward = Fields("id quantity rewardType context")
local tier = Fields("tier suggestedILvl difficultyID modifierUIWidgetSetID", "tierDescription lockedReason", "unlocked queueAsLFG")
tier.rewards = { array = tierReward }
local orderReward = Fields("currencyType count", "itemLink")
local order = Fields("orderID itemID spellID skillLineAbilityID orderType orderState expirationTime claimEndTime minQuality npcCustomerCreatureID", "outputItemHyperlink", "isFulfillable")
order.npcOrderRewards = { array = orderReward }
local activity = Fields("type index threshold progress id activityTierID level claimID", "raidString")
activity.rewards = { array = Fields("type id quantity itemDBID") }

Evidence.Schemas = {
    GetMapInfo = Fields("mapID parentMapID mapType", "name"),
    GetInfo = Fields("questID frequency", "title", "isHeader isHidden"),
    GetQuestObjectives = { array = objective },
    GetAvailableQuestLines = { array = Fields("questID", "questName", "isHidden") },
    GetQuestsOnMap = { array = Fields("questID mapID", nil, "isHidden") },
    GetQuestRewardCurrencies = { array = reward },
    GetQuestLogMajorFactionReputationRewards = { array = reward },
    GetQuestTagInfo = Fields("tradeskillLineID tagID"),
    GetActivities = { array = activity },
    GetActivityEncounterInfo = { array = Fields("encounterID bestDifficulty uiOrder instanceID") },
    GetSortedProgressForActivity = { array = Fields("activityTierID difficulty numPoints") },
    GetAllWidgetsBySetID = { array = Fields("widgetID widgetType widgetSetID") },
    GetStatusBarWidgetVisualizationInfo = Fields("shownState barValue barMin barMax", "text overrideBarText"),
    GetDelvesForMap = { array = "number" }, GetEventsForMap = { array = "number" },
    GetAreaPOIInfo = poi,
    GetCurrencyInfo = currency, GetCurrencyListInfo = currency,
    GetItemInteractionInfo = Fields("currencyTypeId interactionType"),
    GetChargeInfo = Fields("timeToNextCharge rechargeRate newChargeAmount"),
    GetMajorFactionIDs = { array = "number" },
    GetMajorFactionData = Fields("factionID expansionID renownLevel maxLevel renownReputationEarned renownLevelThreshold uiPriority", "name textureKit", "isUnlocked"),
    GetMajorFactionRenownInfo = Fields("renownLevel renownReputationEarned renownLevelThreshold"),
    GetDelveEntranceTiers = { array = tier }, GetActiveDelveTier = tier,
    GetCrafterOrders = { array = order },
    GetProfessionInfoBySkillLineID = Fields("profession professionID parentProfessionID skillLevel maxSkillLevel", "professionName expansionName", "isPrimaryProfession"),
    GetChildProfessionInfo = Fields("profession professionID parentProfessionID skillLevel maxSkillLevel", "professionName expansionName", "isPrimaryProfession"),
    GetBaseProfessionInfo = Fields("profession professionID parentProfessionID skillLevel maxSkillLevel", "professionName expansionName", "isPrimaryProfession"),
}

-- Unreadable list entries remain placeholders: removing them would make a
-- partial list look complete, especially for quest objectives and Vault slots.
function Evidence.Normalize(value, schema, depth)
    depth = depth or 0
    if not Evidence.Accessible(value) then return nil, "restricted" end
    if value == nil then return nil, "unknown" end
    if schema == "position" then
        if type(value) ~= "table" and type(value) ~= "userdata" then return nil, "unavailable" end
        if type(value) == "table" and not Evidence.Table(value) then return nil, "restricted" end
        local ok, x, y = pcall(function() return value:GetXY() end)
        if ok and Evidence.Number(x) and Evidence.Number(y) then return { x = x, y = y }, "known" end
        return nil, "restricted"
    end
    if type(schema) == "string" then
        if type(value) ~= schema or (schema == "number" and not Evidence.Number(value)) then return nil, "unavailable" end
        return value, "known"
    end
    if not Evidence.Table(value) or depth > 6 then return nil, "restricted" end
    local result, status = {}, "known"
    if schema.array then
        for index, entry in ipairs(value) do
            if index > 2000 then result._incomplete = true; status = "unavailable"; break end
            local clean, state = Evidence.Normalize(entry, schema.array, depth + 1)
            if state ~= "known" then result._incomplete = true; status = state end
            if clean ~= nil then result[#result + 1] = clean
            elseif type(schema.array) == "table" then result[#result + 1] = { _restricted = true } end
        end
    else
        for field, fieldSchema in pairs(schema) do
            local clean, state = Evidence.Normalize(value[field], fieldSchema, depth + 1)
            result[field] = clean
            if state == "restricted" or state == "unavailable" then
                result._restricted = true; status = state
                result._fieldStatus = result._fieldStatus or {}; result._fieldStatus[field] = state
            end
        end
    end
    return result, status
end

function Evidence.Fact(record, name, value, source, verification, status)
    return { name = name, value = value, status = status or (value == nil and "unknown" or "known"),
        source = source or record.source, verification = verification or record.verification,
        ownerKey = record.ownerKey, scope = record.scope, resetKey = record.resetKey,
        season = record.season, context = record.context, observedAt = record.observedAt,
        validUntil = record.validUntil }
end

function Evidence.Field(record, data, field, source, verification)
    return Evidence.Fact(record, field, data and data[field], source, verification,
        data and data._fieldStatus and data._fieldStatus[field])
end

function Evidence.Valid(fact, now, context)
    if not fact or fact.status ~= "known" or fact.value == nil then return false end
    if fact.verification ~= "live" and fact.verification ~= "observed" and fact.verification ~= "snapshot" then return false end
    if fact.validUntil and fact.validUntil <= now then return false end
    if context then
        for _, key in ipairs({ "ownerKey", "scope", "resetKey", "season", "context", "name" }) do
            if context[key] ~= nil and fact[key] ~= context[key] then return false end
        end
    end
    return true
end
