----------------------------------------------------------------------------------------
-- Instance Tracker Header for RefineUI
-- Description: Uses the instance name as the scenario tracker header and decorates
--              native boss criteria without changing Blizzard's tracker layout.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Quests = RefineUI:GetModule("Quests")

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local type = type
local tostring = tostring
local ipairs = ipairs
local pairs = pairs
local select = select
local pcall = pcall
local unpack = unpack
local math_max = math.max
local math_min = math.min
local math_floor = math.floor
local IsInInstance = IsInInstance
local GetInstanceInfo = GetInstanceInfo
local GetDifficultyInfo = GetDifficultyInfo
local GetNumSavedInstances = GetNumSavedInstances
local GetSavedInstanceInfo = GetSavedInstanceInfo
local GetSavedInstanceEncounterInfo = GetSavedInstanceEncounterInfo
local EJ_GetEncounterInfoByIndex = EJ_GetEncounterInfoByIndex
local EJ_GetCreatureInfo = EJ_GetCreatureInfo
local C_EncounterJournal = C_EncounterJournal
local C_RaidLocks = C_RaidLocks
local RequestRaidInfo = RequestRaidInfo
local C_Scenario = C_Scenario
local C_ScenarioInfo = C_ScenarioInfo
local C_Map = C_Map
local C_ChallengeMode = C_ChallengeMode
local C_Texture = C_Texture
local InCombatLockdown = InCombatLockdown

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local INSTANCE_ATLASES = {
    party = "Dungeon",
    raid = "Raid",
}
local DIFFICULTY_TOKENS = {
    [1] = "N",
    [2] = "H",
    [3] = "N",
    [4] = "N",
    [5] = "H",
    [6] = "H",
    [7] = "LFR",
    [8] = "M+",
    [9] = "N",
    [14] = "N",
    [15] = "H",
    [16] = "M",
    [17] = "LFR",
    [23] = "M",
    [24] = "TW",
    [33] = "TW",
}
local FIXED_RAID_SIZES = {
    [3] = 10,
    [4] = 25,
    [5] = 10,
    [6] = 25,
    [7] = 25,
    [9] = 40,
    [16] = 20,
}
-- Mythic+ headers open the journal on plain Mythic.
local DUNGEON_MYTHIC_DIFFICULTY = 23
local BOSS_COUNT_WIDTH = 42
local HEADER_TEXT_GAP = 6
local INSTANCE_ICON_SIZE = 32
local INSTANCE_ICON_GAP = 8
local DELVE_ICON_ATLAS = "delves-bountiful"
-- Painting inside the parchment and gold frame baked into 512x512 EJ lore images.
local LORE_ART_TEXTURE_SIZE = 512
local LORE_ART_LEFT = 36
local LORE_ART_RIGHT = 356
local LORE_ART_TOP = 48
local LORE_ART_BOTTOM = 290
-- Delve entrance art is 584 wide; the scene fills the left part, a parchment panel the rest.
local DELVE_ART_SCENE_WIDTH = 370
-- Vertical crop position: 0 shows the top of the scene, 1 the bottom.
local DELVE_ART_ANCHOR_Y = 0.65
-- Blizzard only exposes these through the entrance widget set, so map delve instance IDs.
local DELVE_ART_ATLASES = {
    [2664] = "delve-entrance-background-fungal-folly",
    [2679] = "delve-entrance-background-mycomancer-cavern",
    [2680] = "delve-entrance-background-earthcrawl-mines",
    [2681] = "delve-entrance-background-kriegvals-rest",
    [2682] = "delve-entrance-background-zekvirs-lair",
    [2683] = "delve-entrance-background-the-waterworks",
    [2684] = "delve-entrance-background-the-dread-pit",
    [2685] = "delve-entrance-background-skittering-breach",
    [2686] = "delve-entrance-background-nightfall-sanctum",
    [2687] = "delve-entrance-background-the-sinkhole",
    [2688] = "delve-entrance-background-the-spiral-weave",
    [2689] = "delve-entrance-background-tak-rethan-abyss",
    [2690] = "delve-entrance-background-the-underkeep",
    [2767] = "delve-entrance-background-the-sinkhole",
    [2768] = "delve-entrance-background-tak-rethan-abyss",
    [2803] = "delve-entrance-background-archival-assault",
    [2815] = "delve-entrance-background-the-undermine",
    [2826] = "delves-entrance-background-sewers",
    [2831] = "delve-entrance-background-goblin-boss",
    [2836] = "delve-entrance-background-earthcrawl-mines",
    [2933] = "delve-entrance-background-collegiate-calamity",
    [2951] = "delve-entrance-background-voidrazor-sanctuary",
    [2952] = "delve-entrance-background-the-shadow-enclave",
    [2953] = "delve-entrance-background-parhelion-plaza",
    [2961] = "delve-entrance-background-twilight-crypts",
    [2962] = "delve-entrance-background-atal-aman",
    [2963] = "delve-entrance-background-the-grudge-pit",
    [2964] = "delve-entrance-background-gulf-of-memory",
    [2965] = "delve-entrance-background-sunkiller-sanctum",
    [2966] = "delve-entrance-background-torments-rise",
    [2979] = "delve-entrance-background-shadowguard-point",
    [3003] = "delve-entrance-background-the-darkway",
}
-- Art (and the RefineUI border line on its edge) sits this far inside Blizzard's background.
local LORE_ART_INSET = 8
local LORE_ART_ALPHA = 0.75
local LORE_ART_SHADE_LEFT = 0.55
local LORE_ART_SHADE_RIGHT = 1
-- The challenge block keeps Blizzard's fixed layout height.
-- Content sits inside the instance art card: LORE_ART_INSET plus even padding.
local MYTHIC_PLUS_CONTENT_INSET = 14
local MYTHIC_PLUS_AFFIX_TOP = 12
local MYTHIC_PLUS_BAR_HEIGHT = 16
local MYTHIC_PLUS_AFFIX_SIZE = 30
local MYTHIC_PLUS_AFFIX_SPACING = 4
local MYTHIC_PLUS_AFFIX_RIGHT_INSET = 14
local MYTHIC_PLUS_TIME_FOR_3 = 0.60
local MYTHIC_PLUS_TIME_FOR_2 = 0.80
local MYTHIC_PLUS_MARKER_WIDTH = 2
-- Bar color by best upgrade still reachable; 0 is over time.
local MYTHIC_PLUS_TIER_COLORS = {
    [0] = { 0.80, 0.18, 0.18 },
    [1] = { 0.72, 0.45, 0.22 },
    [2] = { 0.72, 0.74, 0.80 },
    [3] = { 0.85, 0.72, 0.20 },
}

local function AurasAreSecret()
    local secrets = _G.C_Secrets
    if not secrets or type(secrets.ShouldAurasBeSecret) ~= "function" then
        return false
    end

    local ok, result = pcall(secrets.ShouldAurasBeSecret)
    if not ok or (_G.issecretvalue and _G.issecretvalue(result)) then
        return true
    end
    return result == true
end

function Quests:CanUpdateObjectiveTracker()
    return not InCombatLockdown() and not AurasAreSecret()
end

-- Everything here is visual only: Blizzard owns scenario layout state. Any
-- addon write it reads (block heights, lines, dirty flags) taints its update
-- and breaks restricted aura reads such as ShouldShowMawBuffs in encounters.
function Quests:QueueInstanceTrackerHeader()
    RefineUI:Debounce("Quests:InstanceHeader", 0, function()
        self:ApplyInstanceTrackerHeader()
    end)
end

----------------------------------------------------------------------------------------
-- Instance Context
----------------------------------------------------------------------------------------
local function GetDifficultyLabel(instanceType, difficultyID, instanceGroupSize)
    local token = DIFFICULTY_TOKENS[difficultyID]
    local isMythicPlus = token == "M+"
    local minimumPlayers, maximumPlayers

    if GetDifficultyInfo then
        local ok, _, _, isHeroic, isChallengeMode, displayHeroic, displayMythic,
            _, isLFR, minimum, maximum = pcall(GetDifficultyInfo, difficultyID)
        if ok then
            if isLFR then
                token = "LFR"
            elseif isChallengeMode then
                isMythicPlus = true
                token = "M+"
                if C_ChallengeMode and type(C_ChallengeMode.GetActiveKeystoneInfo) == "function" then
                    local levelOk, level = pcall(C_ChallengeMode.GetActiveKeystoneInfo)
                    if levelOk and RefineUI:IsAccessibleValue(level)
                        and type(level) == "number" and level > 0 then
                        token = token .. tostring(level)
                    end
                end
            elseif displayMythic then
                token = "M"
            elseif isHeroic or displayHeroic then
                token = "H"
            elseif not token then
                token = "N"
            end
            minimumPlayers = minimum
            maximumPlayers = maximum
        end
    end

    token = token or "N"
    if instanceType == "raid" then
        local size = FIXED_RAID_SIZES[difficultyID]
        if not size and type(instanceGroupSize) == "number" and instanceGroupSize > 0 then
            size = instanceGroupSize
        elseif not size and type(minimumPlayers) == "number" and minimumPlayers > 0
            and minimumPlayers == maximumPlayers then
            size = minimumPlayers
        end
        if size then
            token = token .. tostring(size)
        end
    end

    return " (" .. token .. ")", isMythicPlus
end

local function GetInstanceTrackerContext()
    if not IsInInstance or not GetInstanceInfo then
        return nil
    end

    local inside, instanceType = IsInInstance()
    if not inside or (instanceType ~= "party" and instanceType ~= "raid") then
        return nil
    end

    local name, _, difficultyID, _, _, _, _, mapID, instanceGroupSize = GetInstanceInfo()
    if not RefineUI:IsAccessibleString(name) or name == ""
        or not RefineUI:IsAccessibleValue(difficultyID)
        or not RefineUI:IsAccessibleValue(mapID)
        or type(difficultyID) ~= "number" or type(mapID) ~= "number" then
        return nil
    end

    local difficultyLabel, isMythicPlus = GetDifficultyLabel(instanceType, difficultyID, instanceGroupSize)
    if instanceType == "party" and not isMythicPlus and C_ChallengeMode
        and type(C_ChallengeMode.GetActiveChallengeMapID) == "function" then
        local activeOk, activeMapID = pcall(C_ChallengeMode.GetActiveChallengeMapID)
        if activeOk and RefineUI:IsAccessibleValue(activeMapID)
            and type(activeMapID) == "number" and activeMapID > 0 then
            isMythicPlus = true
            difficultyLabel = " (M+)"
            if type(C_ChallengeMode.GetActiveKeystoneInfo) == "function" then
                local levelOk, level = pcall(C_ChallengeMode.GetActiveKeystoneInfo)
                if levelOk and RefineUI:IsAccessibleValue(level)
                    and type(level) == "number" and level > 0 then
                    difficultyLabel = " (M+" .. tostring(level) .. ")"
                end
            end
        end
    end
    return {
        difficultyID = difficultyID,
        difficultyLabel = difficultyLabel,
        atlas = INSTANCE_ATLASES[instanceType],
        instanceType = instanceType,
        isMythicPlus = isMythicPlus,
        key = tostring(mapID) .. ":" .. tostring(difficultyID),
        mapID = mapID,
        name = name,
    }
end

local function FindDelveWidget(stageBlock)
    local widgetContainer = stageBlock and stageBlock.WidgetContainer
    local widgetFrames = widgetContainer and widgetContainer.widgetFrames
    if type(widgetFrames) ~= "table" then
        return nil
    end

    local delveWidgetType = _G.Enum and _G.Enum.UIWidgetVisualizationType
        and _G.Enum.UIWidgetVisualizationType.ScenarioHeaderDelves

    for _, widget in pairs(widgetFrames) do
        if widget and widget.TierFrame and widget.SpellContainer and widget.CurrencyContainer
            and (not delveWidgetType or widget.widgetType == delveWidgetType) then
            return widget
        end
    end

    return nil
end

local function GetDelveTrackerContext(widget)
    if not widget then
        return nil
    end

    local name
    if C_Map and type(C_Map.GetBestMapForUnit) == "function" and type(C_Map.GetMapInfo) == "function" then
        local mapRead, mapID = pcall(C_Map.GetBestMapForUnit, "player")
        if mapRead and RefineUI:IsAccessibleValue(mapID) and type(mapID) == "number" then
            local infoRead, mapInfo = pcall(C_Map.GetMapInfo, mapID)
            if infoRead and type(mapInfo) == "table" then
                name = mapInfo.name
            end
        end
    end

    if not RefineUI:HasValue(name) and GetInstanceInfo then
        local instanceRead, instanceName = pcall(GetInstanceInfo)
        if instanceRead then
            name = instanceName
        end
    end

    if not RefineUI:HasValue(name) and C_Scenario and type(C_Scenario.GetInfo) == "function" then
        local scenarioRead, scenarioName = pcall(C_Scenario.GetInfo)
        if scenarioRead then
            name = scenarioName
        end
    end

    if not RefineUI:HasValue(name)
        or (RefineUI:IsAccessibleValue(name) and (type(name) ~= "string" or name == "")) then
        return nil
    end

    local instanceMapID = GetInstanceInfo and select(8, GetInstanceInfo())
    if not RefineUI:IsAccessibleValue(instanceMapID) or type(instanceMapID) ~= "number" then
        instanceMapID = nil
    end

    return {
        atlas = DELVE_ICON_ATLAS,
        instanceType = "delve",
        key = "delve:" .. tostring(instanceMapID),
        mapID = instanceMapID,
        name = name,
    }
end

local function GetInstanceCriteriaInfo(quests, index)
    local criteria = quests.instanceHeaderCriteria
    if criteria and criteria[index] ~= nil then return criteria[index] or nil end
    local ok, info = pcall(C_ScenarioInfo.GetCriteriaInfo, index)
    info = ok and info or nil
    if criteria then criteria[index] = info or false end
    return info
end

local function ReadScenarioBossProgress(quests, context)
    if context.instanceType ~= "party" or not C_Scenario or not C_ScenarioInfo
        or type(C_Scenario.GetStepInfo) ~= "function"
        or type(C_ScenarioInfo.GetCriteriaInfo) ~= "function" then
        return nil
    end

    local ok, _, _, criteriaCount = pcall(C_Scenario.GetStepInfo)
    if not ok or not RefineUI:IsAccessibleValue(criteriaCount)
        or type(criteriaCount) ~= "number" or criteriaCount <= 0 then
        return nil
    end

    local completed = 0
    local total = 0
    for index = 1, criteriaCount do
        local info = GetInstanceCriteriaInfo(quests, index)
        if type(info) == "table" and not info.isWeightedProgress
            and RefineUI:IsAccessibleValue(info.completed) then
            total = total + 1
            if info.completed == true then
                completed = completed + 1
            end
        end
    end

    if total > 0 then
        return completed, total
    end
    return nil
end

local function ReadSavedBossProgress(context)
    if not GetNumSavedInstances or not GetSavedInstanceInfo then
        return nil
    end

    local ok, count = pcall(GetNumSavedInstances)
    if not ok or type(count) ~= "number" then
        return nil
    end

    for index = 1, count do
        local read, _, _, _, difficultyID, _, _, _, _, _, _, total, completed, _, mapID =
            pcall(GetSavedInstanceInfo, index)
        if read and RefineUI:IsAccessibleValue(difficultyID) and RefineUI:IsAccessibleValue(mapID)
            and difficultyID == context.difficultyID and mapID == context.mapID
            and RefineUI:IsAccessibleValue(total) and RefineUI:IsAccessibleValue(completed)
            and type(total) == "number" and total > 0 and type(completed) == "number" then
            local defeated = {}
            if GetSavedInstanceEncounterInfo then
                for encounterIndex = 1, total do
                    local encounterRead, bossName, _, isKilled =
                        pcall(GetSavedInstanceEncounterInfo, index, encounterIndex)
                    if encounterRead and isKilled == true and RefineUI:IsAccessibleString(bossName) then
                        defeated[bossName:lower()] = true
                    end
                end
            end
            return math_max(0, completed), total, defeated
        end
    end

    return nil
end

local function GetBossProgressData(quests, context)
    local refresh = quests.instanceHeaderRefresh
    if refresh and refresh.key == context.key then return refresh end
    local completed, total, defeated = ReadSavedBossProgress(context)
    refresh = { key = context.key, completed = completed, total = total, defeated = defeated, killed = {},
        encounters = quests:GetInstanceHeaderEncounters(context) }
    if quests.instanceHeaderLayoutActive then quests.instanceHeaderRefresh = refresh end
    return refresh
end

function Quests:GetInstanceHeaderEncounters(context)
    self.instanceHeaderEncounterCache = self.instanceHeaderEncounterCache or {}

    if not EJ_GetEncounterInfoByIndex and not (InCombatLockdown and InCombatLockdown())
        and C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_EncounterJournal")
        EJ_GetEncounterInfoByIndex = _G.EJ_GetEncounterInfoByIndex
        EJ_GetCreatureInfo = _G.EJ_GetCreatureInfo
    end

    if not C_EncounterJournal or type(C_EncounterJournal.GetInstanceForGameMap) ~= "function"
        or not EJ_GetEncounterInfoByIndex then
        return nil
    end

    local ok, journalInstanceID = pcall(C_EncounterJournal.GetInstanceForGameMap, context.mapID)
    if not ok or type(journalInstanceID) ~= "number" or journalInstanceID <= 0 then
        return nil
    end

    local cached = self.instanceHeaderEncounterCache[journalInstanceID]
    if cached then
        return cached
    end

    local journal = _G.EncounterJournal
    if (InCombatLockdown and InCombatLockdown()) or (journal and journal:IsShown()) then
        return nil
    end

    local encounters = RefineUI.InstanceCompletion:WithJournal(journalInstanceID, nil, function()
        local bosses = {}
        local index = 1
        while true do
            local name, _, journalEncounterID, _, _, _, dungeonEncounterID, encounterMapID =
                EJ_GetEncounterInfoByIndex(index, journalInstanceID)
            if type(journalEncounterID) ~= "number" or journalEncounterID <= 0 then
                break
            end

            bosses[#bosses + 1] = {
                dungeonEncounterID = dungeonEncounterID,
                displayName = name,
                icon = (EJ_GetCreatureInfo and select(5, EJ_GetCreatureInfo(1, journalEncounterID)))
                    or "Interface\\EncounterJournal\\UI-EJ-BOSS-Default",
                journalEncounterID = journalEncounterID,
                mapID = encounterMapID,
                name = RefineUI:IsAccessibleString(name) and name:lower() or nil,
            }
            index = index + 1
        end
        return bosses
    end)

    if not encounters or #encounters == 0 then
        return nil
    end

    self.instanceHeaderEncounterCache[journalInstanceID] = encounters
    return encounters
end

local function IsInstanceHeaderBossKilled(quests, context, encounter, savedDefeated)
    local refresh = quests.instanceHeaderRefresh
    local killed = refresh and refresh.key == context.key and refresh.killed
    if killed and killed[encounter.journalEncounterID] ~= nil then
        return killed[encounter.journalEncounterID]
    end
    if (encounter.name and savedDefeated and savedDefeated[encounter.name])
        or (quests.instanceHeaderBossKills and
            (quests.instanceHeaderBossKills[encounter.dungeonEncounterID]
                or quests.instanceHeaderBossKills[encounter.journalEncounterID])) then
        if killed then killed[encounter.journalEncounterID] = true end
        return true
    end

    if C_RaidLocks and type(C_RaidLocks.IsEncounterComplete) == "function"
        and type(encounter.mapID) == "number" and type(encounter.dungeonEncounterID) == "number" then
        local difficultyID = context.difficultyID
        if type(C_RaidLocks.GetRedirectedDifficultyID) == "function" then
            local redirected, redirectedDifficultyID = pcall(C_RaidLocks.GetRedirectedDifficultyID,
                encounter.mapID, difficultyID)
            if redirected and type(redirectedDifficultyID) == "number" and redirectedDifficultyID > 0 then
                difficultyID = redirectedDifficultyID
            end
        end

        local checked, result = pcall(C_RaidLocks.IsEncounterComplete,
            encounter.mapID, encounter.dungeonEncounterID, difficultyID)
        result = checked and RefineUI:IsAccessibleValue(result) and result == true
        if killed then killed[encounter.journalEncounterID] = result end
        return result
    end

    return false
end

function Quests:GetInstanceHeaderBossProgress(context)
    if context.isMythicPlus then
        local completed, total = ReadScenarioBossProgress(self, context)
        if total then return completed, total end
    end

    local data = GetBossProgressData(self, context)
    local completed, total, savedDefeated, encounters = data.completed, data.total, data.defeated, data.encounters
    if encounters then
        local bossCompleted = 0
        for index = 1, #encounters do
            if IsInstanceHeaderBossKilled(self, context, encounters[index], savedDefeated) then
                bossCompleted = bossCompleted + 1
            end
        end
        return bossCompleted, #encounters
    end

    if total then
        -- Aggregate lockout counts can already include our observed kills.
        return completed, total
    end

    return ReadScenarioBossProgress(self, context)
end

function Quests:RecordInstanceHeaderBossKill(encounterID)
    if not RefineUI:IsAccessibleValue(encounterID) or type(encounterID) ~= "number" then
        return
    end
    local context = GetInstanceTrackerContext()
    if not context then return end
    if self.instanceHeaderContextKey ~= context.key then
        self.instanceHeaderContextKey = context.key
        self.instanceHeaderBossKills = nil
    end
    self.instanceHeaderBossKills = self.instanceHeaderBossKills or {}
    if self.instanceHeaderBossKills[encounterID] then return false end
    -- In a key, store the timer's elapsed seconds so the boss line can show its kill time.
    local block = _G.ScenarioObjectiveTracker and _G.ScenarioObjectiveTracker.ChallengeModeBlock
    self.instanceHeaderBossKills[encounterID] = block and block:IsActive()
        and block.__refineuiMythicPlusElapsed or true
    return true
end

local function ReanchorMythicPlusAffixes(block, affixIDs)
    if not block or not block.affixPool then
        return
    end

    if not affixIDs then
        local _, activeAffixes = C_ChallengeMode.GetActiveKeystoneInfo()
        affixIDs = activeAffixes
    end
    local order = {}
    for index, affixID in ipairs(affixIDs or {}) do order[affixID] = index end
    local affixes = {}
    for child in block.affixPool:EnumerateActive() do
        if child and child.affixID and child.Portrait and child.Border then
            child:SetSize(MYTHIC_PLUS_AFFIX_SIZE, MYTHIC_PLUS_AFFIX_SIZE)
            child.Portrait:ClearAllPoints()
            child.Portrait:SetPoint("CENTER")
            child.Portrait:SetSize(MYTHIC_PLUS_AFFIX_SIZE, MYTHIC_PLUS_AFFIX_SIZE)

            if not child.RefineUIAffixMask then
                local mask = child:CreateMaskTexture(nil, "ARTWORK")
                mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
                mask:SetPoint("TOPLEFT", child.Portrait, "TOPLEFT", 2, -2)
                mask:SetPoint("BOTTOMRIGHT", child.Portrait, "BOTTOMRIGHT", -2, 2)
                child.Portrait:AddMaskTexture(mask)
                child.RefineUIAffixMask = mask
            end

            child.Border:ClearAllPoints()
            child.Border:SetAllPoints(child.Portrait)
            child.Border:SetAtlas("delves-scenario-affix-ring", false)
            child.Border:SetVertexColor(1, 1, 1)
            affixes[#affixes + 1] = child
        end
    end

    table.sort(affixes, function(left, right) return (order[left.affixID] or 0) < (order[right.affixID] or 0) end)

    local totalWidth = #affixes * MYTHIC_PLUS_AFFIX_SIZE
        + math_max(0, #affixes - 1) * MYTHIC_PLUS_AFFIX_SPACING
    local previous
    for index = 1, #affixes do
        local affix = affixes[index]
        affix:ClearAllPoints()
        if previous then
            affix:SetPoint("LEFT", previous, "RIGHT", MYTHIC_PLUS_AFFIX_SPACING, 0)
        else
            affix:SetPoint("TOPLEFT", block, "TOPRIGHT",
                -MYTHIC_PLUS_AFFIX_RIGHT_INSET - totalWidth, -MYTHIC_PLUS_AFFIX_TOP)
        end
        previous = affix
    end
end

-- Criteria lines come from ObjectiveTrackerManager's shared pool, so the
-- portrait must be hidden before Blizzard lays the line out or reuses it.
local function ResetInstanceBossLine(line)
    if line.RefineUIBossIcon then
        line.RefineUIBossIcon:Hide()
        line.RefineUIBossPuck:Hide()
    end
end

local function ShowBossPortrait(line, icon, killed)
    if not line.RefineUIBossIcon then
        local puck = line:CreateTexture(nil, "BACKGROUND")
        puck:SetAtlas("UI-QuestPoi-QuestNumber")
        puck:SetSize(26, 26)
        puck:SetPoint("CENTER", line.Icon, "CENTER")
        line.RefineUIBossPuck = puck
        local portrait = line:CreateTexture(nil, "ARTWORK")
        portrait:SetSize(16, 16)
        portrait:SetPoint("CENTER", line.Icon, "CENTER")
        line.RefineUIBossIcon = portrait
        local mask = line:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(portrait)
        portrait:AddMaskTexture(mask)
    end
    local portrait = line.RefineUIBossIcon
    if killed then
        portrait:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        portrait:SetTexCoord(0, 1, 0, 1)
    else
        portrait:SetTexture(icon)
        portrait:SetTexCoord(0.0625, 0.9375, 0.0625, 0.9375)
    end
    line.Icon:Hide()
    line.RefineUIBossPuck:Show()
    portrait:Show()
end

-- Visual only: Blizzard already laid these lines out. Boss criteria lose the
-- "0/1 ... defeated" wording and gain a portrait; the text only gets shorter,
-- so the line height Blizzard reserved still fits.
local function DecorateInstanceBossLines(quests, tracker, context)
    local block = tracker.ObjectivesBlock
    if not block or context.instanceType ~= "party" or not tracker:ShouldShowCriteria() then return end
    local ok, _, _, criteriaCount = pcall(C_Scenario.GetStepInfo)
    if not ok or not RefineUI:IsAccessibleValue(criteriaCount) or type(criteriaCount) ~= "number" then return end
    local suffix = _G.BOSS_DEAD
    suffix = type(suffix) == "string" and suffix:lower() or ""
    if suffix == "" then return end
    local encounters = GetBossProgressData(quests, context).encounters
    for criteriaIndex = 1, criteriaCount do
        local line = block.usedLines[criteriaIndex]
        local info = line and line.used and line.Text and GetInstanceCriteriaInfo(quests, criteriaIndex)
        if info and not info.isWeightedProgress and RefineUI:IsAccessibleString(info.description)
            and RefineUI:IsAccessibleValue(info.totalQuantity) and info.totalQuantity == 1
            and #info.description > #suffix and info.description:sub(-#suffix):lower() == suffix then
            local bossName = info.description:sub(1, -#suffix - 1):gsub("%s+$", "")
            local completed = RefineUI:IsAccessibleValue(info.completed) and info.completed == true
            local normalizedName = bossName:lower()
            for _, encounter in ipairs(encounters or {}) do
                if encounter.name == normalizedName then
                    local killTime = completed and quests.instanceHeaderBossKills
                        and quests.instanceHeaderBossKills[encounter.dungeonEncounterID]
                    if type(killTime) == "number" then
                        bossName = bossName .. "  |cffffffff" .. SecondsToClock(killTime, false) .. "|r"
                    end
                    ShowBossPortrait(line, encounter.icon, completed)
                    break
                end
            end
            line.Text:SetText(bossName)
        end
    end
end

local function UpdateMythicPlusDeathDetail(block)
    local deathCount = block and block.DeathCount
    if not deathCount then
        return
    end

    if not deathCount.RefineUITimeLost then
        local label = deathCount:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", deathCount.Count, "RIGHT", 5, 0)
        label:SetTextColor(1, 0.25, 0.25)
        RefineUI.Font(label, 12, nil, "OUTLINE")
        deathCount.RefineUITimeLost = label
    end

    local label = deathCount.RefineUITimeLost
    local count = block.deathCount
    local timeLost = block.timeLost
    if RefineUI:IsAccessibleValue(count) and type(count) == "number" and count > 0
        and RefineUI:IsAccessibleValue(timeLost) and type(timeLost) == "number" and timeLost > 0 then
        label:SetText("-" .. SecondsToClock(timeLost, false))
        label:Show()
        deathCount:SetWidth(25 + label:GetStringWidth())
    else
        label:Hide()
        deathCount:SetWidth(20)
    end
end

local function EnsureMythicPlusMarker(block, key, text, fraction)
    local marker = block[key]
    if not marker then
        -- Line and label live on the bar so its fill cannot draw over them.
        marker = block.StatusBar:CreateTexture(nil, "OVERLAY")
        marker:SetColorTexture(0, 0, 0, 1)

        local label = block.StatusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetText(text)
        label:SetPoint("LEFT", marker, "RIGHT", 3, 0)
        RefineUI.Font(label, 12, nil, "THICKOUTLINE")
        marker.Label = label
        block[key] = marker
    end

    marker.fraction = fraction
    marker:SetSize(MYTHIC_PLUS_MARKER_WIDTH, MYTHIC_PLUS_BAR_HEIGHT)
    return marker
end

local function PositionMythicPlusMarker(bar, marker)
    if marker then
        marker:ClearAllPoints()
        marker:SetPoint("CENTER", bar, "LEFT", bar:GetWidth() * marker.fraction, 0)
    end
end

-- The bar stretches with the block, so markers follow its width.
local function PositionMythicPlusMarkers(block)
    PositionMythicPlusMarker(block.StatusBar, block.RefineUIMythicPlusMarker3)
    PositionMythicPlusMarker(block.StatusBar, block.RefineUIMythicPlusMarker2)
end

local function ApplyMythicPlusChallengeBlock(block)
    if not block or not block.StatusBar or not block.Level or not block.TimeLeft
        or block.__refineuiMythicPlusStyled then
        return
    end

    block.__refineuiMythicPlusStyled = true
    block.__refineuiMythicPlusElapsed = nil

    if block.TimerBGBack then block.TimerBGBack:Hide() end
    if block.TimerBG then block.TimerBG:Hide() end
    if block.GetRegions then
        local regions = { block:GetRegions() }
        for index = 1, #regions do
            local region = regions[index]
            if region and region.GetObjectType and region:GetObjectType() == "Texture" then
                if region.SetTexture then
                    region:SetTexture(nil)
                end
                region:Hide()
            end
        end
    end

    block.Level:Hide()

    block.TimeLeft:ClearAllPoints()
    block.TimeLeft:SetPoint("TOPLEFT", block, "TOPLEFT", MYTHIC_PLUS_CONTENT_INSET, -MYTHIC_PLUS_CONTENT_INSET)
    RefineUI.Font(block.TimeLeft, 24, nil, "OUTLINE")

    local nextUpgrade = block:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nextUpgrade:SetPoint("TOPLEFT", block.TimeLeft, "BOTTOMLEFT", 1, -2)
    RefineUI.Font(nextUpgrade, 13, nil, "OUTLINE")
    nextUpgrade:Hide()
    block.RefineUIMythicPlusNext = nextUpgrade

    block.StatusBar:ClearAllPoints()
    block.StatusBar:SetPoint("BOTTOMLEFT", block, "BOTTOMLEFT", MYTHIC_PLUS_CONTENT_INSET, MYTHIC_PLUS_CONTENT_INSET)
    block.StatusBar:SetPoint("BOTTOMRIGHT", block, "BOTTOMRIGHT", -MYTHIC_PLUS_CONTENT_INSET, MYTHIC_PLUS_CONTENT_INSET)
    block.StatusBar:SetHeight(MYTHIC_PLUS_BAR_HEIGHT)
    block.StatusBar:SetStatusBarTexture(RefineUI.Media.Textures.Statusbar)
    if not block.StatusBar.__refineuiMythicPlusStyled then
        RefineUI.SetTemplate(block.StatusBar)
        block.StatusBar.__refineuiMythicPlusStyled = true
    end

    local marker3 = EnsureMythicPlusMarker(block, "RefineUIMythicPlusMarker3", "+3",
        1 - MYTHIC_PLUS_TIME_FOR_3)
    local marker2 = EnsureMythicPlusMarker(block, "RefineUIMythicPlusMarker2", "+2",
        1 - MYTHIC_PLUS_TIME_FOR_2)
    marker3:Show()
    marker3.Label:Show()
    marker2:Show()
    marker2.Label:Show()
    PositionMythicPlusMarkers(block)
    RefineUI:HookScriptOnce("Quests:MythicPlus:BarSize", block.StatusBar, "OnSizeChanged", function()
        PositionMythicPlusMarkers(block)
    end)

    if block.DeathCount then
        block.DeathCount:ClearAllPoints()
        block.DeathCount:SetPoint("LEFT", block.TimeLeft, "RIGHT", 28, 0)
        UpdateMythicPlusDeathDetail(block)
    end
    if block.StartedDepleted then
        block.StartedDepleted:ClearAllPoints()
        block.StartedDepleted:SetPoint("LEFT", block.TimeLeft, "RIGHT", 5, 0)
    end
    if block.TimesUpLootStatus then
        block.TimesUpLootStatus:ClearAllPoints()
        block.TimesUpLootStatus:SetPoint("LEFT", block.TimeLeft, "RIGHT", 5, 0)
    end

    ReanchorMythicPlusAffixes(block)
end

-- Tier is the best upgrade still reachable: 3, 2, 1, or 0 once over time.
local function SetMythicPlusTier(block, tier)
    if block.__refineuiMythicPlusTier == tier then
        return
    end
    block.__refineuiMythicPlusTier = tier

    local color = MYTHIC_PLUS_TIER_COLORS[tier]
    block.StatusBar:SetStatusBarColor(color[1], color[2], color[3])
    if block.RefineUIMythicPlusNext then
        block.RefineUIMythicPlusNext:SetTextColor(color[1], color[2], color[3])
    end

    local marker3 = block.RefineUIMythicPlusMarker3
    local marker2 = block.RefineUIMythicPlusMarker2
    if marker3 then
        marker3:SetShown(tier == 3)
        marker3.Label:SetShown(tier == 3)
    end
    if marker2 then
        marker2:SetShown(tier >= 2)
        marker2.Label:SetShown(tier >= 2)
    end
end

local function UpdateMythicPlusChallengeTime(block, elapsedTime)
    if not block or not RefineUI:IsAccessibleValue(elapsedTime) or type(elapsedTime) ~= "number"
        or not RefineUI:IsAccessibleValue(block.timeLimit) or type(block.timeLimit) ~= "number" then
        return
    end

    local timeLimit = block.timeLimit
    local elapsedSecond = math_floor(elapsedTime)
    if elapsedSecond > timeLimit then
        if block.__refineuiMythicPlusElapsed ~= elapsedSecond then
            block.__refineuiMythicPlusOvertime = "+" .. SecondsToClock(elapsedSecond - timeLimit, false)
        end
        block.TimeLeft:SetText(block.__refineuiMythicPlusOvertime)
        block.TimeLeft:SetTextColor(1, 0.2, 0.2)
        -- Blizzard empties the bar at zero; keep it full so the over-time color shows.
        block.StatusBar:SetValue(timeLimit)
    end
    if block.__refineuiMythicPlusElapsed == elapsedSecond then
        return
    end
    block.__refineuiMythicPlusElapsed = elapsedSecond

    local cutoff3 = timeLimit * MYTHIC_PLUS_TIME_FOR_3
    local cutoff2 = timeLimit * MYTHIC_PLUS_TIME_FOR_2
    local tier = (elapsedSecond < cutoff3 and 3) or (elapsedSecond < cutoff2 and 2)
        or (elapsedSecond <= timeLimit and 1) or 0
    SetMythicPlusTier(block, tier)

    local nextUpgrade = block.RefineUIMythicPlusNext
    if nextUpgrade then
        if tier >= 2 then
            local remaining = math_floor((tier == 3 and cutoff3 or cutoff2) - elapsedSecond)
            nextUpgrade:SetText("+" .. tier .. " in " .. SecondsToClock(remaining, false))
            nextUpgrade:Show()
        else
            nextUpgrade:Hide()
        end
    end
end

----------------------------------------------------------------------------------------
-- Tracker Styling
----------------------------------------------------------------------------------------
local function EnsureBossCountText(tracker)
    local header = tracker and tracker.Header
    if not header or not header.CreateFontString then
        return nil
    end
    if header.RefineUIInstanceBossCount then
        return header.RefineUIInstanceBossCount
    end

    local count = header:CreateFontString(nil, "OVERLAY", "ObjectiveTrackerHeaderFont")
    count:SetWidth(BOSS_COUNT_WIDTH)
    if header.MinimizeButton then
        count:SetPoint("RIGHT", header.MinimizeButton, "LEFT", -7, 0)
    else
        count:SetPoint("RIGHT", header, "RIGHT", -24, 0)
    end
    count:SetJustifyH("RIGHT")
    count:SetTextColor(1, 0.82, 0)
    header.RefineUIInstanceBossCount = count
    return count
end

local function CaptureHeaderTitleLayout(header, title)
    if header.__refineuiInstanceTitlePoints then
        return
    end

    local points = {}
    if title.GetNumPoints and title.GetPoint then
        for index = 1, title:GetNumPoints() do
            points[index] = { title:GetPoint(index) }
        end
    end
    header.__refineuiInstanceTitlePoints = points
end

local function EnsureInstanceIcon(tracker)
    local header = tracker and tracker.Header
    if not header or not header.CreateTexture then
        return nil
    end
    if header.RefineUIInstanceIcon then
        return header.RefineUIInstanceIcon
    end

    local icon = header:CreateTexture(nil, "ARTWORK")
    icon:SetSize(INSTANCE_ICON_SIZE, INSTANCE_ICON_SIZE)
    icon:Hide()
    header.RefineUIInstanceIcon = icon
    return icon
end

local function OpenInstanceJournal(button)
    if not _G.EncounterJournal_OpenJournal and not InCombatLockdown() then
        C_AddOns.LoadAddOn("Blizzard_EncounterJournal")
    end
    if not _G.EncounterJournal_OpenJournal then
        return
    end

    local ok, journalInstanceID = pcall(C_EncounterJournal.GetInstanceForGameMap, button.mapID)
    if ok and type(journalInstanceID) == "number" and journalInstanceID > 0 then
        _G.EncounterJournal_OpenJournal(button.difficultyID, journalInstanceID)
    end
end

-- RefineUI-owned click target over the icon and title; Blizzard's header frame is untouched.
local function EnsureInstanceJournalButton(header, icon, title)
    if header.RefineUIInstanceJournalButton then
        return header.RefineUIInstanceJournalButton
    end

    local button = CreateFrame("Button", nil, header)
    button:SetHeight(INSTANCE_ICON_SIZE)
    button:SetPoint("LEFT", icon, "LEFT")
    button:SetPoint("RIGHT", title, "RIGHT")
    button:SetScript("OnClick", OpenInstanceJournal)
    button:Hide()
    header.RefineUIInstanceJournalButton = button
    return button
end

local function GetInstanceLoreImage(context)
    local getInstanceInfo = _G.EJ_GetInstanceInfo
    if not getInstanceInfo or not C_EncounterJournal
        or type(C_EncounterJournal.GetInstanceForGameMap) ~= "function" then
        return nil
    end

    local ok, journalInstanceID = pcall(C_EncounterJournal.GetInstanceForGameMap, context.mapID)
    if not ok or type(journalInstanceID) ~= "number" or journalInstanceID <= 0 then
        return nil
    end
    return (select(5, getInstanceInfo(journalInstanceID)))
end

local function GetTrackerArt(context)
    if context.instanceType == "delve" then
        local atlas = context.mapID and DELVE_ART_ATLASES[context.mapID]
        local info = atlas and C_Texture.GetAtlasInfo(atlas)
        local file = info and (info.file or info.filename)
        if not file then
            return nil
        end
        return {
            file = file,
            left = info.leftTexCoord,
            right = info.leftTexCoord + (info.rightTexCoord - info.leftTexCoord) * DELVE_ART_SCENE_WIDTH / info.width,
            top = info.topTexCoord,
            bottom = info.bottomTexCoord,
            width = DELVE_ART_SCENE_WIDTH,
            height = info.height,
            anchorY = DELVE_ART_ANCHOR_Y,
        }
    end

    local image = GetInstanceLoreImage(context)
    if not image then
        return nil
    end
    return {
        file = image,
        left = LORE_ART_LEFT / LORE_ART_TEXTURE_SIZE,
        right = LORE_ART_RIGHT / LORE_ART_TEXTURE_SIZE,
        top = LORE_ART_TOP / LORE_ART_TEXTURE_SIZE,
        bottom = LORE_ART_BOTTOM / LORE_ART_TEXTURE_SIZE,
        width = LORE_ART_RIGHT - LORE_ART_LEFT,
        height = LORE_ART_BOTTOM - LORE_ART_TOP,
        anchorY = 0.5,
    }
end

local function SetTrackerArtTarget(art, owner, anchor, fade, overlay)
    if art.anchor == anchor then
        return
    end
    if art.fade then art.fade:SetAlpha(1) end
    if art.overlay then art.overlay:SetAlpha(1) end
    art.anchor, art.fade, art.overlay = anchor, fade, overlay
    if not anchor then
        art:Hide()
        return
    end
    if fade then fade:SetAlpha(0) end
    if overlay then overlay:SetAlpha(0) end
    art:SetParent(owner)
    art:SetFrameLevel(math_max(0, owner:GetFrameLevel() - 1))
    RefineUI.CreateBorder(art)
    art:ClearAllPoints()
    art:SetPoint("TOPLEFT", anchor, "TOPLEFT", LORE_ART_INSET, -LORE_ART_INSET)
    art:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -LORE_ART_INSET, LORE_ART_INSET)
    art:Show()
end

-- Instance art replaces the stage banner, Delve header or Mythic+ block
-- background in a RefineUI-owned frame one level below the block that owns it,
-- so Blizzard's text, spells, currencies and timer still draw on top.
local function ApplyTrackerArt(quests, tracker, context, delveWidget)
    local stage = tracker.StageBlock
    if not stage then
        return
    end

    local owner, anchor, fade, overlay
    if context and context.instanceType == "delve" then
        anchor = delveWidget and delveWidget.Frame
        owner, fade = stage, anchor
    elseif context and context.isMythicPlus then
        -- Only RefineUI's restyled block has its Blizzard timer textures hidden.
        local block = tracker.ChallengeModeBlock
        if block and block.__refineuiMythicPlusStyled then
            owner, anchor = block, block
        end
    elseif context then
        owner, anchor, fade, overlay = stage, stage.NormalBG, stage.NormalBG, stage.ThemeOverlay
    end
    if anchor and not anchor:IsShown() then
        anchor = nil
    end

    if anchor and quests.instanceHeaderArtKey ~= context.key then
        quests.instanceHeaderArt = GetTrackerArt(context)
        quests.instanceHeaderArtKey = quests.instanceHeaderArt and context.key
    end
    local source = anchor and quests.instanceHeaderArtKey and quests.instanceHeaderArt
    local art = quests.instanceHeaderArtFrame
    if not source then
        if art then SetTrackerArtTarget(art, nil) end
        return
    end

    if not art then
        art = CreateFrame("Frame", nil, owner)
        art.Texture = art:CreateTexture(nil, "BACKGROUND")
        art.Texture:SetAllPoints()
        art.Texture:SetGradient("HORIZONTAL",
            CreateColor(LORE_ART_SHADE_LEFT, LORE_ART_SHADE_LEFT, LORE_ART_SHADE_LEFT, LORE_ART_ALPHA),
            CreateColor(LORE_ART_SHADE_RIGHT, LORE_ART_SHADE_RIGHT, LORE_ART_SHADE_RIGHT, LORE_ART_ALPHA))
        quests.instanceHeaderArtFrame = art
    end

    if art.file ~= source.file then
        art.file = source.file
        art.Texture:SetTexture(source.file)
    end
    SetTrackerArtTarget(art, owner, anchor, fade, overlay)

    -- Cover-crop the art to its inset frame's aspect at its vertical anchor.
    local width, height = anchor:GetSize()
    width, height = width - 2 * LORE_ART_INSET, height - 2 * LORE_ART_INSET
    if width > 0 then
        local span = (source.bottom - source.top) * math_min(1, source.width * height / (width * source.height))
        local top = source.top + (source.bottom - source.top - span) * source.anchorY
        art.Texture:SetTexCoord(source.left, source.right, top, top + span)
    end
end


local function SetHeaderLayout(tracker, context, reserveCount)
    local header = tracker and tracker.Header
    local title = header and header.Text
    if not title then
        return
    end

    CaptureHeaderTitleLayout(header, title)
    local icon = EnsureInstanceIcon(tracker)

    if context and icon and title.ClearAllPoints and title.SetPoint then
        icon:ClearAllPoints()
        local headerBar = header.RefineUIHeaderBar
        if headerBar then
            -- Center the badge over the bar's left edge so half of it sits
            -- outside the background instead of consuming its inset.
            icon:SetPoint("CENTER", headerBar, "LEFT", 0, 0)
        else
            icon:SetPoint("CENTER", header, "LEFT", 0, 0)
        end
        icon:SetAtlas(context.atlas, false)
        icon:Show()

        title:ClearAllPoints()
        title:SetPoint("LEFT", icon, "RIGHT", INSTANCE_ICON_GAP, 0)
        if reserveCount and header.RefineUIInstanceBossCount then
            title:SetPoint("RIGHT", header.RefineUIInstanceBossCount, "LEFT", -HEADER_TEXT_GAP, 0)
        elseif header.MinimizeButton then
            title:SetPoint("RIGHT", header.MinimizeButton, "LEFT", -7, 0)
        else
            title:SetPoint("RIGHT", header, "RIGHT", -24, 0)
        end

        local journalButton = EnsureInstanceJournalButton(header, icon, title)
        if context.instanceType ~= "delve" then
            journalButton.mapID = context.mapID
            journalButton.difficultyID = context.isMythicPlus and DUNGEON_MYTHIC_DIFFICULTY or context.difficultyID
            journalButton:Show()
        else
            journalButton:Hide()
        end
    else
        if icon then
            icon:Hide()
        end
        if header.RefineUIInstanceJournalButton then
            header.RefineUIInstanceJournalButton:Hide()
        end
        if title.ClearAllPoints and title.SetPoint then
            title:ClearAllPoints()
            for index = 1, #header.__refineuiInstanceTitlePoints do
                title:SetPoint(unpack(header.__refineuiInstanceTitlePoints[index]))
            end
        end
    end
end

local HookDelveWidget

function Quests:ApplyInstanceTrackerHeader()
    local tracker = _G.ScenarioObjectiveTracker
    if not tracker then
        return
    end

    local delveWidget = FindDelveWidget(tracker.StageBlock or tracker.stageBlock)
    local context = GetDelveTrackerContext(delveWidget) or self.instanceHeaderLayoutContext or GetInstanceTrackerContext()
    local bossCount = EnsureBossCountText(tracker)

    if delveWidget then
        HookDelveWidget(self, delveWidget)
    end

    if context then
        if self.instanceHeaderContextKey ~= context.key then
            self.instanceHeaderContextKey = context.key
            self.instanceHeaderBossKills = {}
        end

        if tracker.Header and tracker.Header.Text then
            local title = context.name
            if context.difficultyLabel then
                title = title .. context.difficultyLabel
            end
            -- Widget SetText: the AutoScalingFontString Lua SetText stores
            -- scaling state that Blizzard's own header updates read.
            GetFontStringMetatable().__index.SetText(tracker.Header.Text, title)
        end

        local completed, total
        if context.instanceType ~= "delve" then
            completed, total = self:GetInstanceHeaderBossProgress(context)
        end
        local showBossCount = type(completed) == "number" and type(total) == "number" and total > 0
        if bossCount then
            if showBossCount then
                local text = completed .. "/" .. total
                if bossCount:GetText() ~= text then
                    bossCount:SetText(text)
                    bossCount:SetWidth(math_max(BOSS_COUNT_WIDTH, bossCount:GetStringWidth() + 2))
                end
                bossCount:Show()
            else
                bossCount:Hide()
            end
        end
        SetHeaderLayout(tracker, context, showBossCount)
        if context.isMythicPlus and RefineUI:IsModuleStartupEnabled("MythicPlus") then
            ApplyMythicPlusChallengeBlock(tracker.ChallengeModeBlock)
        end
        ApplyTrackerArt(self, tracker, context, delveWidget)
        DecorateInstanceBossLines(self, tracker, context)
    else
        self.instanceHeaderContextKey = nil
        self.instanceHeaderBossKills = nil
        if bossCount then bossCount:Hide() end
        SetHeaderLayout(tracker, nil, false)
        ApplyTrackerArt(self, tracker, nil)
    end
end

local function HookMythicPlusChallengeBlock(quests, block)
    if not block or block.__refineuiMythicPlusHooked then
        return
    end
    block.__refineuiMythicPlusHooked = true

    RefineUI:HookOnce("Quests:MythicPlus:UpdateTime", block, "UpdateTime", function(hookedBlock, elapsedTime)
        UpdateMythicPlusChallengeTime(hookedBlock, elapsedTime)
    end)
    RefineUI:HookOnce("Quests:MythicPlus:Activate", block, "Activate", function(hookedBlock, _, elapsedTime)
        ApplyMythicPlusChallengeBlock(hookedBlock)
        hookedBlock.__refineuiMythicPlusElapsed = nil
        UpdateMythicPlusChallengeTime(hookedBlock, elapsedTime)
        quests:ApplyInstanceTrackerHeader()
    end)
    RefineUI:HookOnce("Quests:MythicPlus:SetUpAffixes", block, "SetUpAffixes", function(hookedBlock, affixIDs)
        ReanchorMythicPlusAffixes(hookedBlock, affixIDs)
    end)
    RefineUI:HookOnce("Quests:MythicPlus:UpdateDeathCount", block, "UpdateDeathCount", function(hookedBlock)
        UpdateMythicPlusDeathDetail(hookedBlock)
    end)
    ApplyMythicPlusChallengeBlock(block)
end

-- Delve widgets can finish setup after the scenario layout that created them.
HookDelveWidget = function(quests, widget)
    if not widget or widget.__refineuiDelveHeaderHooked then
        return
    end
    widget.__refineuiDelveHeaderHooked = true

    if type(widget.Setup) == "function" then
        RefineUI:HookOnce("Quests:InstanceTrackerHeader:" .. tostring(widget) .. ":Setup",
            widget, "Setup", function()
                if not quests.instanceHeaderLayoutActive then quests:QueueInstanceTrackerHeader() end
            end)
    end
end

function Quests:InitializeInstanceTrackerHeader()
    local tracker = _G.ScenarioObjectiveTracker
    if not tracker then
        return
    end

    self:StyleObjectiveFrame(tracker.StageBlock)
    RefineUI:HookOnce("Quests:InstanceTrackerHeader:BeginLayout", tracker, "BeginLayout", function()
        self.instanceHeaderLayoutActive = true
        self.instanceHeaderLayoutContext = GetInstanceTrackerContext()
        local contextKey = self.instanceHeaderLayoutContext and self.instanceHeaderLayoutContext.key
        if self.instanceHeaderContextKey ~= contextKey then
            self.instanceHeaderContextKey = contextKey
            self.instanceHeaderBossKills = nil
        end
        self.instanceHeaderRefresh = nil
        self.instanceHeaderCriteria = {}
    end)
    RefineUI:HookOnce("Quests:InstanceTrackerHeader:ResetLines", tracker.ObjectivesBlock, "Reset", function(block)
        for _, line in pairs(block.usedLines) do ResetInstanceBossLine(line) end
    end)
    RefineUI:HookOnce("Quests:InstanceTrackerHeader:FreeLine", tracker.ObjectivesBlock, "FreeLine", function(_, line)
        ResetInstanceBossLine(line)
    end)
    RefineUI:HookOnce("Quests:InstanceTrackerHeader:EndLayout", tracker, "EndLayout", function()
        self:ApplyInstanceTrackerHeader()
        self.instanceHeaderLayoutActive = nil
        self.instanceHeaderLayoutContext = nil
        self.instanceHeaderRefresh = nil
        self.instanceHeaderCriteria = nil
    end)
    if RefineUI:IsModuleStartupEnabled("MythicPlus") then
        HookMythicPlusChallengeBlock(self, tracker.ChallengeModeBlock)
    end

    RefineUI:OnEvents({
        "PLAYER_ENTERING_WORLD",
        "ZONE_CHANGED_NEW_AREA",
        "GROUP_ROSTER_UPDATE",
        "UPDATE_INSTANCE_INFO",
        "CHALLENGE_MODE_START",
        "CHALLENGE_MODE_RESET",
        "PLAYER_DIFFICULTY_CHANGED",
        "BOSS_KILL",
        "ENCOUNTER_END",
    }, function(event, ...)
        local newKill
        if event == "BOSS_KILL" then
            newKill = self:RecordInstanceHeaderBossKill((...))
        elseif event == "ENCOUNTER_END" then
            local encounterID, _, _, _, success = ...
            if RefineUI:IsAccessibleValue(success) and success == 1 then
                newKill = self:RecordInstanceHeaderBossKill(encounterID)
            end
        end

        if event == "PLAYER_ENTERING_WORLD" or event == "CHALLENGE_MODE_START"
            or event == "CHALLENGE_MODE_RESET" then
            self.instanceHeaderBossKills = nil
        end
        self:QueueInstanceTrackerHeader()
        if newKill and RequestRaidInfo then
            RequestRaidInfo()
        end
    end, "Quests:InstanceTrackerHeader")

    self:ApplyInstanceTrackerHeader()
end
