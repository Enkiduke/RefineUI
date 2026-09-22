----------------------------------------------------------------------------------------
-- Instance Tracker Header for RefineUI
-- Description: Uses the instance name as the scenario tracker header and compacts the
--              redundant dungeon, raid, and Delve banners.
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
local C_EncounterJournal = C_EncounterJournal
local C_RaidLocks = C_RaidLocks
local RequestRaidInfo = RequestRaidInfo
local C_Timer = C_Timer
local C_Scenario = C_Scenario
local C_ScenarioInfo = C_ScenarioInfo
local C_Map = C_Map
local C_ChallengeMode = C_ChallengeMode
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
local BOSS_COUNT_WIDTH = 42
local HEADER_TEXT_GAP = 6
local INSTANCE_ICON_SIZE = 32
local INSTANCE_ICON_GAP = 8
local DELVE_ICON_ATLAS = "delves-bountiful"
local DELVE_WIDGET_BACKGROUND_ATLAS = "perks-list-borderlines"
local DELVE_WIDGET_HEIGHT = 28
local DELVE_TIER_OFFSET_Y = -6
local MYTHIC_PLUS_BLOCK_HEIGHT = 52
local MYTHIC_PLUS_BAR_WIDTH = 232
local MYTHIC_PLUS_BAR_HEIGHT = 16
local MYTHIC_PLUS_AFFIX_SIZE = 30
local MYTHIC_PLUS_AFFIX_SPACING = 4
local MYTHIC_PLUS_AFFIX_RIGHT_INSET = 15
local MYTHIC_PLUS_TIME_FOR_3 = 0.60
local MYTHIC_PLUS_TIME_FOR_2 = 0.80
local MYTHIC_PLUS_COLOR_3 = { 1, 0.82, 0 }
local MYTHIC_PLUS_COLOR_2 = { 0.78, 0.78, 0.82 }
local scenarioLayoutPending = false

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

local function RequestScenarioLayout(tracker)
    if not tracker or not tracker.MarkDirty then
        return
    end

    if (InCombatLockdown and InCombatLockdown()) or AurasAreSecret() then
        scenarioLayoutPending = true
        return
    end

    scenarioLayoutPending = false
    tracker:MarkDirty()
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

    return {
        atlas = DELVE_ICON_ATLAS,
        instanceType = "delve",
        key = "delve",
        name = name,
    }
end

local function ReadScenarioBossProgress(context)
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
        local read, info = pcall(C_ScenarioInfo.GetCriteriaInfo, index)
        if read and type(info) == "table" and not info.isWeightedProgress
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
                    local encounterRead, _, encounterID, isKilled =
                        pcall(GetSavedInstanceEncounterInfo, index, encounterIndex)
                    if encounterRead and isKilled == true and RefineUI:IsAccessibleValue(encounterID)
                        and type(encounterID) == "number" then
                        defeated[encounterID] = true
                    end
                end
            end
            return math_max(0, completed), total, defeated
        end
    end

    return nil
end

function Quests:GetInstanceHeaderEncounters(context)
    self.instanceHeaderEncounterCache = self.instanceHeaderEncounterCache or {}

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

    local encounters = {}
    local index = 1
    while true do
        local read, _, _, journalEncounterID, _, _, _, dungeonEncounterID, encounterMapID =
            pcall(EJ_GetEncounterInfoByIndex, index, journalInstanceID)
        if not read or type(journalEncounterID) ~= "number" or journalEncounterID <= 0 then
            break
        end

        encounters[#encounters + 1] = {
            dungeonEncounterID = dungeonEncounterID,
            journalEncounterID = journalEncounterID,
            mapID = encounterMapID,
        }
        index = index + 1
    end

    if #encounters == 0 then
        return nil
    end

    self.instanceHeaderEncounterCache[journalInstanceID] = encounters
    return encounters
end

function Quests:GetInstanceHeaderBossProgress(context)
    local scenarioCompleted, scenarioTotal = ReadScenarioBossProgress(context)
    if scenarioTotal then
        return scenarioCompleted, scenarioTotal
    end

    local completed, total, savedDefeated = ReadSavedBossProgress(context)
    if total then
        local additional = 0
        for encounterID in pairs(self.instanceHeaderBossKills or {}) do
            if not savedDefeated[encounterID] then
                additional = additional + 1
            end
        end
        return math_min(total, completed + additional), total
    end

    local encounters = self:GetInstanceHeaderEncounters(context)
    if not encounters then
        return nil
    end

    local killed = self.instanceHeaderBossKills or {}
    completed = 0
    for index = 1, #encounters do
        local encounter = encounters[index]
        local isComplete = killed[encounter.dungeonEncounterID] or killed[encounter.journalEncounterID]

        if not isComplete and C_RaidLocks and type(C_RaidLocks.IsEncounterComplete) == "function"
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
            isComplete = checked and RefineUI:IsAccessibleValue(result) and result == true
        end

        if isComplete then
            completed = completed + 1
        end
    end

    return completed, #encounters
end

function Quests:RecordInstanceHeaderBossKill(encounterID)
    if not RefineUI:IsAccessibleValue(encounterID) or type(encounterID) ~= "number" then
        return
    end
    self.instanceHeaderBossKills = self.instanceHeaderBossKills or {}
    self.instanceHeaderBossKills[encounterID] = true
end

local function RestoreStageBlock(block)
    if not block or not block.__refineuiInstanceHeaderHidden then
        return false
    end

    local height = block.__refineuiInstanceHeaderHeight or 83
    block.height = height
    if block.SetHeight then
        block:SetHeight(height)
    end
    block.__refineuiInstanceHeaderHidden = nil

    if block.used and block.Show then
        block:Show()
    end

    return true
end

local function SuppressStageBlock(block)
    if not block then
        return false
    end

    -- Some scenarios replace the banner with functional widgets. Preserve
    -- those; the redundant dungeon/raid name banner has no widget set.
    if block.widgetSetID then
        return RestoreStageBlock(block)
    end

    if not block.__refineuiInstanceHeaderHeight then
        local height = block.height
        if type(height) ~= "number" and block.GetHeight then
            height = block:GetHeight()
        end
        block.__refineuiInstanceHeaderHeight = type(height) == "number" and height or 83
    end

    local changed = not block.__refineuiInstanceHeaderHidden
    block.__refineuiInstanceHeaderHidden = true
    block.height = 0
    if block.SetHeight then
        block:SetHeight(1)
    end
    if block.Hide then
        block:Hide()
    end

    return changed
end

local function CapturePoints(frame)
    local points = {}
    if frame and frame.GetNumPoints and frame.GetPoint then
        for index = 1, frame:GetNumPoints() do
            points[index] = { frame:GetPoint(index) }
        end
    end
    return points
end

local function RestorePoints(frame, points)
    if not frame or not frame.ClearAllPoints or not frame.SetPoint then
        return
    end

    frame:ClearAllPoints()
    for index = 1, #(points or {}) do
        frame:SetPoint(unpack(points[index]))
    end
end

local function RestoreDelveWidget(widget)
    local layout = widget and widget.__refineuiDelveLayout
    if not layout or not widget.__refineuiDelveApplied then
        return false
    end

    widget.__refineuiDelveApplied = nil
    widget:SetHeight(layout.height)
    if widget.RefineUIDelveWidgetBackground then
        widget.RefineUIDelveWidgetBackground:Hide()
    end
    layout.frame:SetShown(layout.frameShown)
    layout.headerText:SetShown(layout.headerTextShown)
    layout.decoration:SetShown(layout.decorationShown)

    layout.tierFrame:SetParent(layout.tierParent)
    RestorePoints(layout.tierFrame, layout.tierPoints)
    RestorePoints(layout.spellContainer, layout.spellPoints)
    RestorePoints(layout.currencyContainer, layout.currencyPoints)

    return true
end

local function RestoreDelveStageBlock(block)
    if not block or not block.__refineuiDelveHeaderHeight then
        return false
    end

    local height = block.__refineuiDelveHeaderHeight
    block.__refineuiDelveHeaderHeight = nil
    block.height = height
    block:SetHeight(height)
    return true
end

local function ApplyDelveWidget(tracker, stageBlock, widget)
    local header = tracker and tracker.Header
    local tierFrame = widget and widget.TierFrame
    local spellContainer = widget and widget.SpellContainer
    local currencyContainer = widget and widget.CurrencyContainer
    if not header or not tierFrame or not spellContainer or not currencyContainer
        or not widget.Frame or not widget.HeaderText or not widget.DecorationBottomLeft then
        return false
    end

    if not widget.__refineuiDelveLayout then
        widget.__refineuiDelveLayout = {
            height = widget:GetHeight(),
            frame = widget.Frame,
            frameShown = widget.Frame:IsShown(),
            headerText = widget.HeaderText,
            headerTextShown = widget.HeaderText:IsShown(),
            decoration = widget.DecorationBottomLeft,
            decorationShown = widget.DecorationBottomLeft:IsShown(),
            tierFrame = tierFrame,
            tierParent = tierFrame:GetParent(),
            tierPoints = CapturePoints(tierFrame),
            spellContainer = spellContainer,
            spellPoints = CapturePoints(spellContainer),
            currencyContainer = currencyContainer,
            currencyPoints = CapturePoints(currencyContainer),
        }
    end

    local changed = not widget.__refineuiDelveApplied
        or widget:GetHeight() ~= DELVE_WIDGET_HEIGHT
        or tierFrame:GetParent() ~= header
        or stageBlock.height ~= DELVE_WIDGET_HEIGHT

    widget.__refineuiDelveApplied = true
    widget.Frame:Hide()
    widget.HeaderText:Hide()
    widget.DecorationBottomLeft:Hide()
    widget:SetHeight(DELVE_WIDGET_HEIGHT)

    if not widget.RefineUIDelveWidgetBackground then
        local background = widget:CreateTexture(nil, "BACKGROUND")
        background:SetAtlas(DELVE_WIDGET_BACKGROUND_ATLAS, false)
        background:SetPoint("TOPLEFT", widget, "TOPLEFT")
        background:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT")
        widget.RefineUIDelveWidgetBackground = background
    end
    widget.RefineUIDelveWidgetBackground:Show()

    tierFrame:SetParent(header)
    tierFrame:ClearAllPoints()
    if header.MinimizeButton then
        tierFrame:SetPoint("RIGHT", header.MinimizeButton, "LEFT", -7, DELVE_TIER_OFFSET_Y)
    else
        tierFrame:SetPoint("RIGHT", header, "RIGHT", -24, DELVE_TIER_OFFSET_Y)
    end
    tierFrame:Show()

    spellContainer:ClearAllPoints()
    spellContainer:SetPoint("CENTER", widget, "CENTER", 0, 0)
    currencyContainer:ClearAllPoints()
    currencyContainer:SetPoint("TOPRIGHT", widget, "TOPRIGHT", 0, 0)

    if not stageBlock.__refineuiDelveHeaderHeight then
        stageBlock.__refineuiDelveHeaderHeight = stageBlock.height or stageBlock:GetHeight()
    end
    stageBlock.height = DELVE_WIDGET_HEIGHT
    stageBlock:SetHeight(DELVE_WIDGET_HEIGHT)

    if changed and widget.widgetContainer and widget.widgetContainer.MarkDirtyLayout then
        widget.widgetContainer:MarkDirtyLayout()
    end

    return changed
end

local function ReanchorMythicPlusAffixes(block)
    if not block or not block.GetNumChildren then
        return
    end

    local affixes = {}
    for index = 1, block:GetNumChildren() do
        local child = select(index, block:GetChildren())
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
                -MYTHIC_PLUS_AFFIX_RIGHT_INSET - totalWidth, -2)
        end
        previous = affix
    end
end

local function UpdateInstanceObjectiveText(tracker, criteriaCount)
    local suffix = _G.BOSS_DEAD
    local block = tracker and tracker.ObjectivesBlock
    local lines = block and block.usedLines
    if type(lines) ~= "table" or not C_Scenario or not C_ScenarioInfo then
        return
    end

    if type(criteriaCount) ~= "number" then
        criteriaCount = select(3, C_Scenario.GetStepInfo())
    end
    if not RefineUI:IsAccessibleValue(criteriaCount) or type(criteriaCount) ~= "number" then
        return
    end

    for criteriaIndex = 1, criteriaCount do
        local read, info = pcall(C_ScenarioInfo.GetCriteriaInfo, criteriaIndex)
        local line = lines[criteriaIndex]
        if read and info and info.isWeightedProgress and line then
            local progressBar = line.progressBar
            if not progressBar and info.completed and block.lastRegion == line and block.AddProgressBar then
                progressBar = block:AddProgressBar(criteriaIndex, tracker.progressBarLineSpacing)
            end

            if progressBar then
                local lineHeight = line:GetHeight()
                local lineSpacing = tracker.lineSpacing or 12
                local previousLine = lines[criteriaIndex - 1]
                progressBar:ClearAllPoints()
                if previousLine then
                    progressBar:SetPoint("TOPLEFT", previousLine, "BOTTOMLEFT", 0, -lineSpacing)
                else
                    progressBar:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -lineSpacing)
                end

                if type(lineHeight) == "number" and lineHeight > 0 then
                    local progressSpacing = tracker.progressBarLineSpacing or 2
                    block.height = math_max(0, (block.height or 0) - lineHeight - progressSpacing)
                    block:SetHeight(block.height)
                    line:SetHeight(0)
                end
                if line.Text then line.Text:SetText("") end
                if line.Icon then line.Icon:Hide() end

                local label = progressBar.Bar and progressBar.Bar.Label
                if info.completed and label then
                    label:SetText("|A:ui-questtracker-tracker-check:14:14|a")
                end
            end
        elseif read and info and not info.isWeightedProgress
            and RefineUI:IsAccessibleValue(info.totalQuantity) and info.totalQuantity == 1
            and type(suffix) == "string" and suffix ~= ""
            and RefineUI:IsAccessibleValue(info.description) and type(info.description) == "string"
            and #info.description > #suffix and info.description:sub(-#suffix) == suffix
            and line and line.Text then
            line.Text:SetText((info.description:sub(1, -#suffix - 1):gsub("%s+$", "")))
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

local function EnsureMythicPlusMarker(block, key, text, fraction, color)
    local marker = block[key]
    if not marker then
        marker = block.StatusBar:CreateTexture(nil, "OVERLAY")
        marker:SetColorTexture(color[1], color[2], color[3], 0.9)

        local label = block:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetText(text)
        label:SetTextColor(color[1], color[2], color[3])
        marker.Label = label
        block[key] = marker
    end

    marker:ClearAllPoints()
    marker:SetSize(1, MYTHIC_PLUS_BAR_HEIGHT)
    marker:SetPoint("LEFT", block.StatusBar, "LEFT", MYTHIC_PLUS_BAR_WIDTH * fraction, 0)
    marker.Label:ClearAllPoints()
    marker.Label:SetPoint("CENTER", marker, "CENTER")
    RefineUI.Font(marker.Label, 12, nil, "OUTLINE")
    return marker
end

local function ApplyMythicPlusChallengeBlock(block)
    if not block or not block.StatusBar or not block.Level or not block.TimeLeft then
        return false
    end

    local changed = not block.__refineuiMythicPlusStyled
        or block.height ~= MYTHIC_PLUS_BLOCK_HEIGHT
        or block:GetHeight() ~= MYTHIC_PLUS_BLOCK_HEIGHT
    if not changed then
        return false
    end

    block.__refineuiMythicPlusStyled = true
    block.height = MYTHIC_PLUS_BLOCK_HEIGHT
    block:SetHeight(MYTHIC_PLUS_BLOCK_HEIGHT)

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

    if block.RefineUIMythicPlusBackground then
        block.RefineUIMythicPlusBackground:Hide()
    end
    block.Level:Hide()

    block.TimeLeft:ClearAllPoints()
    block.TimeLeft:SetPoint("BOTTOMLEFT", block, "BOTTOMLEFT", 0, 22)
    RefineUI.Font(block.TimeLeft, 24, nil, "OUTLINE")

    block.StatusBar:ClearAllPoints()
    block.StatusBar:SetPoint("BOTTOMLEFT", block, "BOTTOMLEFT", 0, 2)
    block.StatusBar:SetSize(MYTHIC_PLUS_BAR_WIDTH, MYTHIC_PLUS_BAR_HEIGHT)
    block.StatusBar:SetStatusBarTexture(RefineUI.Media.Textures.Statusbar)
    block.StatusBar:SetStatusBarColor(0.85, 0.72, 0.20)
    if not block.StatusBar.__refineuiMythicPlusStyled then
        RefineUI.SetTemplate(block.StatusBar)
        block.StatusBar.__refineuiMythicPlusStyled = true
    end

    local marker3 = EnsureMythicPlusMarker(block, "RefineUIMythicPlusMarker3", "+3",
        1 - MYTHIC_PLUS_TIME_FOR_3, MYTHIC_PLUS_COLOR_3)
    local marker2 = EnsureMythicPlusMarker(block, "RefineUIMythicPlusMarker2", "+2",
        1 - MYTHIC_PLUS_TIME_FOR_2, MYTHIC_PLUS_COLOR_2)
    marker3:Show()
    marker3.Label:Show()
    marker2:Show()
    marker2.Label:Show()

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
    return changed
end

local function UpdateMythicPlusChallengeTime(block, elapsedTime)
    if not block or not RefineUI:IsAccessibleValue(elapsedTime) or type(elapsedTime) ~= "number"
        or not RefineUI:IsAccessibleValue(block.timeLimit) or type(block.timeLimit) ~= "number" then
        return
    end

    ApplyMythicPlusChallengeBlock(block)
    local elapsedSecond = math_floor(elapsedTime)
    if block.__refineuiMythicPlusElapsed == elapsedSecond then
        return
    end
    block.__refineuiMythicPlusElapsed = elapsedSecond

    local timeLimit = block.timeLimit
    if elapsedSecond > timeLimit then
        block.TimeLeft:SetText("+" .. SecondsToClock(elapsedSecond - timeLimit, false))
        block.TimeLeft:SetTextColor(1, 0.2, 0.2)
    end

    local marker3 = block.RefineUIMythicPlusMarker3
    local marker2 = block.RefineUIMythicPlusMarker2
    local show3 = elapsedSecond < timeLimit * MYTHIC_PLUS_TIME_FOR_3
    local show2 = elapsedSecond < timeLimit * MYTHIC_PLUS_TIME_FOR_2
    if marker3 then
        marker3:SetShown(show3)
        marker3.Label:SetShown(show3)
    end
    if marker2 then
        marker2:SetShown(show2)
        marker2.Label:SetShown(show2)
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
    if header.Text and header.Text.GetWidth then
        local width = header.Text:GetWidth()
        if type(width) == "number" and width > 0 then
            header.__refineuiInstanceTitleWidth = width
        end
    end
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

local function SetHeaderLayout(tracker, context, reserveCount, rightFrame)
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
        if rightFrame then
            title:SetPoint("RIGHT", rightFrame, "LEFT", -HEADER_TEXT_GAP, 0)
        elseif reserveCount and header.RefineUIInstanceBossCount then
            title:SetPoint("RIGHT", header.RefineUIInstanceBossCount, "LEFT", -HEADER_TEXT_GAP, 0)
        elseif header.MinimizeButton then
            title:SetPoint("RIGHT", header.MinimizeButton, "LEFT", -7, 0)
        else
            title:SetPoint("RIGHT", header, "RIGHT", -24, 0)
        end
    else
        if icon then
            icon:Hide()
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
local HookMythicPlusChallengeBlock

function Quests:ApplyInstanceTrackerHeader()
    local tracker = _G.ScenarioObjectiveTracker
    if not tracker then
        return
    end

    local stageBlock = tracker.StageBlock or tracker.stageBlock
    local challengeBlock = tracker.ChallengeModeBlock
    local delveWidget = FindDelveWidget(stageBlock)
    local context = GetDelveTrackerContext(delveWidget) or GetInstanceTrackerContext()
    local bossCount = EnsureBossCountText(tracker)

    if delveWidget then
        HookDelveWidget(self, tracker, stageBlock, delveWidget)
    end

    if self.activeDelveWidget and self.activeDelveWidget ~= delveWidget then
        RestoreDelveWidget(self.activeDelveWidget)
        RestoreDelveStageBlock(stageBlock)
        self.activeDelveWidget = nil
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
            RefineUI:SetFontStringValue(tracker.Header.Text, title)
        end

        local completed, total
        if context.instanceType ~= "delve" then
            completed, total = self:GetInstanceHeaderBossProgress(context)
        end
        local showBossCount = type(completed) == "number" and type(total) == "number" and total > 0
        if bossCount then
            if showBossCount then
                bossCount:SetText(completed .. "/" .. total)
                bossCount:Show()
            else
                bossCount:Hide()
            end
        end
        local layoutChanged
        local mythicPlusEnabled = RefineUI:IsModuleStartupEnabled("MythicPlus")
        if context.instanceType == "party" then
            UpdateInstanceObjectiveText(tracker)
        end
        if context.instanceType == "delve" and delveWidget then
            self.activeDelveWidget = delveWidget
            RestoreStageBlock(stageBlock)
            layoutChanged = ApplyDelveWidget(tracker, stageBlock, delveWidget)
            SetHeaderLayout(tracker, context, false, delveWidget.TierFrame)
        elseif context.isMythicPlus then
            RestoreDelveStageBlock(stageBlock)
            SetHeaderLayout(tracker, context, showBossCount)
            RestoreStageBlock(stageBlock)
            if mythicPlusEnabled then
                layoutChanged = ApplyMythicPlusChallengeBlock(challengeBlock)
            end
        else
            RestoreDelveStageBlock(stageBlock)
            SetHeaderLayout(tracker, context, showBossCount)
            layoutChanged = SuppressStageBlock(stageBlock)
        end

        if layoutChanged then
            -- The first pass may already have reserved the stock 83px height.
            -- One new layout pass consumes the replacement block height.
            RequestScenarioLayout(tracker)
        end
    else
        self.instanceHeaderContextKey = nil
        self.instanceHeaderBossKills = nil
        if self.activeDelveWidget then
            RestoreDelveWidget(self.activeDelveWidget)
            self.activeDelveWidget = nil
        end
        RestoreDelveStageBlock(stageBlock)
        if bossCount then bossCount:Hide() end
        SetHeaderLayout(tracker, nil, false)
        RestoreStageBlock(stageBlock)
    end
end

HookMythicPlusChallengeBlock = function(quests, tracker, block)
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
        RequestScenarioLayout(tracker)
    end)
    RefineUI:HookOnce("Quests:MythicPlus:SetUpAffixes", block, "SetUpAffixes", function(hookedBlock)
        ReanchorMythicPlusAffixes(hookedBlock)
    end)
    RefineUI:HookOnce("Quests:MythicPlus:UpdateDeathCount", block, "UpdateDeathCount", function(hookedBlock)
        UpdateMythicPlusDeathDetail(hookedBlock)
    end)
    ApplyMythicPlusChallengeBlock(block)
end

local function HookStageBlock(quests, block)
    if not block or block.__refineuiInstanceHeaderHooked then
        return
    end
    block.__refineuiInstanceHeaderHooked = true

    for _, method in ipairs({ "UpdateStageBlock", "UpdateWidgetRegistration", "SetupStageTransition" }) do
        if type(block[method]) == "function" then
            RefineUI:HookOnce("Quests:InstanceTrackerHeader:" .. tostring(block) .. ":" .. method,
                block, method, function()
                    quests:ApplyInstanceTrackerHeader()
                end)
        end
    end
end

HookDelveWidget = function(quests, tracker, stageBlock, widget)
    if not widget or widget.__refineuiDelveHeaderHooked then
        return
    end
    widget.__refineuiDelveHeaderHooked = true

    if type(widget.Setup) == "function" then
        RefineUI:HookOnce("Quests:InstanceTrackerHeader:" .. tostring(widget) .. ":Setup",
            widget, "Setup", function()
                quests:ApplyInstanceTrackerHeader()
            end)
    end

    if type(widget.OnReset) == "function" then
        RefineUI:HookOnce("Quests:InstanceTrackerHeader:" .. tostring(widget) .. ":OnReset",
            widget, "OnReset", function()
                RestoreDelveWidget(widget)
                RestoreDelveStageBlock(stageBlock)
                if quests.activeDelveWidget == widget then
                    quests.activeDelveWidget = nil
                    SetHeaderLayout(tracker, nil, false)
                end
            end)
    end
end

function Quests:InitializeInstanceTrackerHeader()
    local tracker = _G.ScenarioObjectiveTracker
    if not tracker then
        return
    end

    HookStageBlock(self, tracker.StageBlock or tracker.stageBlock)
    RefineUI:HookOnce("Quests:InstanceTrackerHeader:UpdateCriteria", tracker, "UpdateCriteria",
        function(_, criteriaCount)
            local context = GetInstanceTrackerContext()
            if context and context.instanceType == "party" then
                UpdateInstanceObjectiveText(tracker, criteriaCount)
            end
        end)
    if RefineUI:IsModuleStartupEnabled("MythicPlus") then
        HookMythicPlusChallengeBlock(self, tracker, tracker.ChallengeModeBlock)
    end

    RefineUI:OnEvents({
        "PLAYER_ENTERING_WORLD",
        "PLAYER_REGEN_ENABLED",
        "ADDON_RESTRICTION_STATE_CHANGED",
        "ZONE_CHANGED_NEW_AREA",
        "GROUP_ROSTER_UPDATE",
        "UPDATE_INSTANCE_INFO",
        "CHALLENGE_MODE_START",
        "SCENARIO_CRITERIA_UPDATE",
        "SCENARIO_UPDATE",
        "BOSS_KILL",
        "ENCOUNTER_END",
    }, function(event, ...)
        if event == "BOSS_KILL" then
            self:RecordInstanceHeaderBossKill((...))
        elseif event == "ENCOUNTER_END" then
            local encounterID, _, _, _, success = ...
            if RefineUI:IsAccessibleValue(success) and success == 1 then
                self:RecordInstanceHeaderBossKill(encounterID)
            end
        end

        self:ApplyInstanceTrackerHeader()
        if event ~= "PLAYER_REGEN_ENABLED" and event ~= "ADDON_RESTRICTION_STATE_CHANGED"
            or scenarioLayoutPending then
            RequestScenarioLayout(tracker)
        end
        if (event == "BOSS_KILL" or event == "ENCOUNTER_END") and RequestRaidInfo then
            RequestRaidInfo()
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                self:ApplyInstanceTrackerHeader()
            end)
        end
    end, "Quests:InstanceTrackerHeader")

    self:ApplyInstanceTrackerHeader()
end
