----------------------------------------------------------------------------------------
-- WorldQuestList for RefineUI
-- Description: Adds a minimal world quest list to the world map quest log.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Maps = RefineUI:GetModule("Maps")

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local _G = _G
local ipairs = ipairs
local type = type
local floor = math.floor
local min = math.min
local sort = table.sort
local wipe = wipe
local strlower = string.lower
local strcmputf8i = strcmputf8i
local unpack = unpack or table.unpack

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local CreateFramePool = CreateFramePool
local Pool_HideAndClearAnchors = Pool_HideAndClearAnchors
local C_TaskQuest = C_TaskQuest
local C_QuestLog = C_QuestLog
local C_SuperTrack = C_SuperTrack
local C_PlayerInfo = C_PlayerInfo
local C_Item = C_Item
local HaveQuestData = HaveQuestData
local HaveQuestRewardData = HaveQuestRewardData
local QuestUtils_IsQuestWorldQuest = QuestUtils_IsQuestWorldQuest
local QuestUtils_IsQuestWithinLowTimeThreshold = QuestUtils_IsQuestWithinLowTimeThreshold
local QuestUtils_IsQuestWithinCriticalTimeThreshold = QuestUtils_IsQuestWithinCriticalTimeThreshold
local GetNumQuestLogRewards = GetNumQuestLogRewards
local GetQuestLogRewardInfo = GetQuestLogRewardInfo
local GetQuestLogRewardMoney = GetQuestLogRewardMoney
local GetQuestLogItemLink = GetQuestLogItemLink
local GetDifficultyColor = GetDifficultyColor
local BreakUpLargeNumbers = BreakUpLargeNumbers
local UnitLevel = UnitLevel
local IsShiftKeyDown = IsShiftKeyDown
local InCombatLockdown = InCombatLockdown
local PlaySound = PlaySound
local QuestUtil = _G.QuestUtil
local ChatFrameUtil = _G.ChatFrameUtil

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local SORT_TIME = "TIME"
local SORT_NAME = "NAME"
local HEADER_TEXT = TRACKER_HEADER_WORLD_QUESTS or "World Quests"
local MENU_LABEL_ENABLE = "Show World Quest List"
local MENU_LABEL_SORT = "Sort World Quest List"
local MENU_LABEL_TIME = "Time Remaining"
local MENU_LABEL_NAME = NAME or "Name"
local ITEM_TEX_COORDS = { 0.08, 0.92, 0.08, 0.92 }
local MONEY_TEX_COORDS = { 0, 0.25, 0, 1 }
local GOLD_ICON_TEXTURE = "Interface\\MoneyFrame\\UI-MoneyIcons"
local SECTION_BOTTOM_PADDING = 4

local QuestRarityOffset = {}
if Enum and Enum.WorldQuestQuality then
    QuestRarityOffset[Enum.WorldQuestQuality.Common] = 0
    QuestRarityOffset[Enum.WorldQuestQuality.Rare] = 3
    QuestRarityOffset[Enum.WorldQuestQuality.Epic] = 10
end

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------

local function NormalizeSort(sortMode)
    if sortMode == SORT_NAME then
        return SORT_NAME
    end
    return SORT_TIME
end

local function RefreshQuestMapFrame()
    if _G.QuestMapFrame_UpdateAll then
        _G.QuestMapFrame_UpdateAll()
    end
end

local function PlayCheckboxSound(isEnabled)
    if not PlaySound or not SOUNDKIT then
        return
    end

    local soundKit = isEnabled and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
    if soundKit then
        PlaySound(soundKit)
    end
end

local function CompareStrings(left, right)
    left = left or ""
    right = right or ""

    if left == right then
        return false
    end

    if strcmputf8i then
        return strcmputf8i(left, right) < 0
    end

    return left < right
end

local function GetColorRGB(color, defaultR, defaultG, defaultB)
    defaultR, defaultG, defaultB = defaultR or 1, defaultG or 1, defaultB or 1
    if type(color) ~= "table" then
        return defaultR, defaultG, defaultB
    end

    if color.GetRGB then
        return color:GetRGB()
    end

    local r = color.r or color[1] or defaultR
    local g = color.g or color[2] or defaultG
    local b = color.b or color[3] or defaultB
    return r, g, b
end

----------------------------------------------------------------------------------------
-- Config
----------------------------------------------------------------------------------------

function Maps:GetWorldQuestListConfig()
    local mapsConfig = (RefineUI.Config and RefineUI.Config.Maps) or self.db or {}
    self.db = mapsConfig

    mapsConfig.WorldQuestList = mapsConfig.WorldQuestList or {}
    local config = mapsConfig.WorldQuestList

    if config.Enable == nil then
        config.Enable = true
    end

    if config.Collapsed == nil then
        config.Collapsed = false
    end

    config.Sort = NormalizeSort(config.Sort)

    return config
end

----------------------------------------------------------------------------------------
-- State / Cache
----------------------------------------------------------------------------------------

function Maps:EnsureWorldQuestListState()
    self._worldQuestRewardCache = self._worldQuestRewardCache or {}
    self._worldQuestItemLevelCache = self._worldQuestItemLevelCache or {}
    self._worldQuestTagCache = self._worldQuestTagCache or {}
    self._worldQuestEntries = self._worldQuestEntries or {}
    self._worldQuestSeenQuestIDs = self._worldQuestSeenQuestIDs or {}
end

function Maps:InvalidateWorldQuestListCaches()
    self:EnsureWorldQuestListState()

    wipe(self._worldQuestRewardCache)
    wipe(self._worldQuestItemLevelCache)
    wipe(self._worldQuestTagCache)
end

----------------------------------------------------------------------------------------
-- Menu
----------------------------------------------------------------------------------------

function Maps:RegisterWorldQuestListMenu()
    if self._worldQuestMenuRegistered then
        return true
    end

    local menu = _G.Menu
    if not menu or type(menu.ModifyMenu) ~= "function" then
        return false
    end

    menu.ModifyMenu("MENU_QUEST_MAP_FRAME_SETTINGS", function(_, rootDescription)
        rootDescription:CreateDivider()
        rootDescription:CreateTitle("RefineUI")

        rootDescription:CreateCheckbox(MENU_LABEL_ENABLE, function()
            return self:GetWorldQuestListConfig().Enable == true
        end, function()
            local config = self:GetWorldQuestListConfig()
            config.Enable = not config.Enable
            RefreshQuestMapFrame()
        end)

        local sortSubmenu = rootDescription:CreateButton(MENU_LABEL_SORT)
        sortSubmenu:CreateRadio(MENU_LABEL_TIME, function()
            return NormalizeSort(self:GetWorldQuestListConfig().Sort) == SORT_TIME
        end, function()
            local config = self:GetWorldQuestListConfig()
            config.Sort = SORT_TIME
            RefreshQuestMapFrame()
        end)

        sortSubmenu:CreateRadio(MENU_LABEL_NAME, function()
            return NormalizeSort(self:GetWorldQuestListConfig().Sort) == SORT_NAME
        end, function()
            local config = self:GetWorldQuestListConfig()
            config.Sort = SORT_NAME
            RefreshQuestMapFrame()
        end)
    end)

    self._worldQuestMenuRegistered = true
    return true
end

----------------------------------------------------------------------------------------
-- Data Collection
----------------------------------------------------------------------------------------

function Maps:GetCachedQuestTagInfo(questID)
    local cached = self._worldQuestTagCache[questID]
    if cached == nil then
        cached = C_QuestLog.GetQuestTagInfo(questID) or false
        self._worldQuestTagCache[questID] = cached
    end

    if cached == false then
        return nil
    end

    return cached
end

function Maps:CollectWorldQuestEntries()
    self:EnsureWorldQuestListState()

    local entries = self._worldQuestEntries
    local seenQuestIDs = self._worldQuestSeenQuestIDs
    wipe(entries)
    wipe(seenQuestIDs)

    local questMapFrame = _G.QuestMapFrame
    local mapFrame = questMapFrame and questMapFrame:GetParent()
    local mapID = mapFrame and mapFrame.GetMapID and mapFrame:GetMapID()
    if not mapID then
        return entries
    end

    local tasksOnMap = C_TaskQuest.GetQuestsOnMap(mapID)
    if not tasksOnMap then
        return entries
    end

    local searchText = ""
    local questScrollFrame = _G.QuestScrollFrame
    if questScrollFrame and questScrollFrame.SearchBox and questScrollFrame.SearchBox.GetText then
        local rawSearchText = questScrollFrame.SearchBox:GetText()
        if type(rawSearchText) == "string" then
            searchText = strlower(rawSearchText)
        end
    end

    local passFiltersFn = _G.WorldMap_DoesWorldQuestInfoPassFilters

    for i = 1, #tasksOnMap do
        local info = tasksOnMap[i]
        local questID = info and info.questID

        if questID and not seenQuestIDs[questID] then
            seenQuestIDs[questID] = true

            local isWorldQuest = QuestUtils_IsQuestWorldQuest and QuestUtils_IsQuestWorldQuest(questID)
            local hasQuestData = HaveQuestData and HaveQuestData(questID)
            local passesFilters = type(passFiltersFn) == "function" and passFiltersFn(info) or true

            if isWorldQuest and hasQuestData and passesFilters then
                local title = C_TaskQuest.GetQuestInfoByQuestID(questID)
                if type(title) == "string" and title ~= "" then
                    local titleLower = strlower(title)
                    if searchText == "" or titleLower:find(searchText, 1, true) then
                        entries[#entries + 1] = {
                            questID = questID,
                            title = title,
                            mapID = info.mapID or mapID,
                            info = info,
                            timeLeftMinutes = C_TaskQuest.GetQuestTimeLeftMinutes(questID),
                        }
                    end
                end
            end
        end
    end

    return entries
end

function Maps:SortWorldQuestEntries(entries, sortMode)
    local normalizedSortMode = NormalizeSort(sortMode)

    if normalizedSortMode == SORT_NAME then
        sort(entries, function(left, right)
            if left.title ~= right.title then
                return CompareStrings(left.title, right.title)
            end

            return (left.questID or 0) < (right.questID or 0)
        end)
        return
    end

    sort(entries, function(left, right)
        local leftTime = left.timeLeftMinutes
        local rightTime = right.timeLeftMinutes

        if leftTime == nil then
            if rightTime ~= nil then
                return false
            end
        elseif rightTime == nil then
            return true
        elseif leftTime ~= rightTime then
            return leftTime < rightTime
        end

        if left.title ~= right.title then
            return CompareStrings(left.title, right.title)
        end

        return (left.questID or 0) < (right.questID or 0)
    end)
end

----------------------------------------------------------------------------------------
-- Rewards
----------------------------------------------------------------------------------------

function Maps:GetCachedQuestItemLevel(questID, rewardIndex)
    local cached = self._worldQuestItemLevelCache[questID]
    if cached ~= nil then
        return cached or nil
    end

    local itemLink = GetQuestLogItemLink and GetQuestLogItemLink("reward", rewardIndex, questID)
    if itemLink and C_Item and C_Item.GetDetailedItemLevelInfo then
        local itemLevel = C_Item.GetDetailedItemLevelInfo(itemLink)
        if type(itemLevel) == "number" and itemLevel > 0 then
            self._worldQuestItemLevelCache[questID] = itemLevel
            return itemLevel
        end
    end

    self._worldQuestItemLevelCache[questID] = false
    return nil
end

function Maps:GetCachedWorldQuestReward(questID)
    local cached = self._worldQuestRewardCache[questID]
    if cached ~= nil then
        return cached or nil
    end

    if HaveQuestRewardData and not HaveQuestRewardData(questID) then
        if C_TaskQuest and C_TaskQuest.RequestPreloadRewardData then
            C_TaskQuest.RequestPreloadRewardData(questID)
        end
        return nil
    end

    local rewardDisplay

    local numRewards = GetNumQuestLogRewards and GetNumQuestLogRewards(questID) or 0
    if numRewards > 0 and GetQuestLogRewardInfo then
        for rewardIndex = 1, numRewards do
            local _, itemTexture, quantity, quality, _, itemID = GetQuestLogRewardInfo(rewardIndex, questID)
            if itemID and itemTexture then
                local displayText
                local itemLevel = self:GetCachedQuestItemLevel(questID, rewardIndex)
                if itemLevel then
                    displayText = tostring(itemLevel)
                elseif quantity and quantity > 1 then
                    displayText = BreakUpLargeNumbers and BreakUpLargeNumbers(quantity) or tostring(quantity)
                end

                rewardDisplay = {
                    texture = itemTexture,
                    text = displayText,
                    color = (BAG_ITEM_QUALITY_COLORS and BAG_ITEM_QUALITY_COLORS[quality]) or NORMAL_FONT_COLOR,
                    texCoords = ITEM_TEX_COORDS,
                }
                break
            end
        end
    end

    if not rewardDisplay and C_QuestLog and C_QuestLog.GetQuestRewardCurrencies then
        local currencies = C_QuestLog.GetQuestRewardCurrencies(questID)
        if currencies then
            for i = 1, #currencies do
                local currencyInfo = currencies[i]
                local amount = currencyInfo and (currencyInfo.totalRewardAmount or currencyInfo.quantity or currencyInfo.amount)
                local texture = currencyInfo and currencyInfo.texture

                if texture and amount and amount > 0 then
                    rewardDisplay = {
                        texture = texture,
                        text = BreakUpLargeNumbers and BreakUpLargeNumbers(amount) or tostring(amount),
                        color = HIGHLIGHT_FONT_COLOR or NORMAL_FONT_COLOR,
                        texCoords = ITEM_TEX_COORDS,
                    }
                    break
                end
            end
        end
    end

    if not rewardDisplay and GetQuestLogRewardMoney then
        local money = GetQuestLogRewardMoney(questID)
        if money and money > 0 then
            local gold = floor(money / (COPPER_PER_GOLD or 10000))
            rewardDisplay = {
                texture = GOLD_ICON_TEXTURE,
                text = BreakUpLargeNumbers and BreakUpLargeNumbers(gold) or tostring(gold),
                color = HIGHLIGHT_FONT_COLOR or NORMAL_FONT_COLOR,
                texCoords = MONEY_TEX_COORDS,
            }
        end
    end

    self._worldQuestRewardCache[questID] = rewardDisplay or false
    return rewardDisplay
end

----------------------------------------------------------------------------------------
-- Rows / Header
----------------------------------------------------------------------------------------

function Maps:EnsureWorldQuestFrames()
    local questScrollFrame = _G.QuestScrollFrame
    if not questScrollFrame or not questScrollFrame.Contents then
        return false
    end

    if not self._worldQuestRowPool then
        self._worldQuestRowPool = CreateFramePool("BUTTON", questScrollFrame.Contents, "QuestLogTitleTemplate", function(framePool, button)
            Pool_HideAndClearAnchors(framePool, button)
            button.layoutIndex = nil
            button.questID = nil
            button.mapID = nil
            button.numObjectives = nil
            button.infoX = nil
            button.infoY = nil
            button.info = nil

            if button.RewardText then
                button.RewardText:SetText("")
                button.RewardText:Hide()
            end

            if button.TagTexture then
                button.TagTexture:Hide()
            end

            if button.TimeIcon then
                button.TimeIcon:Hide()
                button.TimeIcon:SetVertexColor(1, 1, 1)
            end

            if button.HighlightTexture then
                button.HighlightTexture:Hide()
            end
        end)
    end

    if not self._worldQuestHeaderButton then
        local header = CreateFrame("BUTTON", "RefineUI_WorldQuestListHeader", questScrollFrame.Contents, "QuestLogHeaderTemplate")
        header:SetScript("OnClick", function(_, mouseButton)
            if mouseButton ~= "LeftButton" then
                return
            end

            local config = self:GetWorldQuestListConfig()
            config.Collapsed = not config.Collapsed
            PlayCheckboxSound(true)
            RefreshQuestMapFrame()
        end)

        if header.SetHeaderText then
            header:SetHeaderText(HEADER_TEXT)
        else
            header:SetText(HEADER_TEXT)
        end

        self._worldQuestHeaderButton = header
    end

    if not self._worldQuestSpacer then
        local spacer = CreateFrame("Frame", nil, questScrollFrame.Contents)
        spacer:SetSize(1, SECTION_BOTTOM_PADDING)
        spacer:Hide()
        self._worldQuestSpacer = spacer
    end

    return true
end

function Maps:InitializeWorldQuestRow(button)
    if button._worldQuestInitialized then
        return
    end

    button.worldQuest = true
    button.questRewardTooltipStyle = TOOLTIP_QUEST_REWARDS_STYLE_WORLD_QUEST
    button.OnLegendPinMouseEnter = function() end
    button.OnLegendPinMouseLeave = function() end
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    button:SetScript("OnEnter", function(row)
        self:OnWorldQuestRowEnter(row)
    end)

    button:SetScript("OnLeave", function(row)
        self:OnWorldQuestRowLeave(row)
    end)

    button:SetScript("OnClick", function(row, mouseButton)
        self:OnWorldQuestRowClick(row, mouseButton)
    end)

    if button.Checkbox then
        button.Checkbox:SetScript("OnMouseUp", function(_, mouseButton, upInside)
            if mouseButton ~= "LeftButton" or not upInside then
                return
            end

            self:ToggleWorldQuestManualTracking(button.questID)
        end)
    end

    if button.TagTexture then
        button.TagTexture:SetSize(16, 16)
        button.TagTexture:Hide()
    end

    if not button.RewardText then
        button.RewardText = button:CreateFontString(nil, "ARTWORK", "GameFontNormalLeft")
        button.RewardText:SetJustifyH("RIGHT")
        button.RewardText:SetPoint("RIGHT", button.TagTexture, "LEFT", -2, 0)
        button.RewardText:SetWidth(72)
    end
    button.RewardText:Hide()

    if button.Text then
        button.Text:ClearAllPoints()
        button.Text:SetPoint("TOPLEFT", 31, -8)
        button.Text:SetPoint("TOP", 0, -8)
        button.Text:SetPoint("RIGHT", button.RewardText, "LEFT", -4, 0)
        if button.Text.SetWordWrap then
            button.Text:SetWordWrap(false)
        end
        if button.Text.SetNonSpaceWrap then
            button.Text:SetNonSpaceWrap(false)
        end
        if button.Text.SetMaxLines then
            button.Text:SetMaxLines(1)
        end
    end

    if button.StorylineTexture then
        button.StorylineTexture:Hide()
    end

    if button.TaskIcon then
        button.TaskIcon:ClearAllPoints()
        button.TaskIcon:SetPoint("RIGHT", button.Text, "LEFT", -4, 0)
        button.TaskIcon:Hide()
    end

    if not button.TimeIcon then
        button.TimeIcon = button:CreateTexture(nil, "OVERLAY")
        button.TimeIcon:SetAtlas("worldquest-icon-clock")
    end
    button.TimeIcon:Hide()

    button.ToggleTracking = function(row)
        self:ToggleWorldQuestManualTracking(row.questID)
    end

    button._worldQuestInitialized = true
end

function Maps:ApplyRewardDisplay(button, rewardDisplay)
    if not button.TagTexture then
        return
    end

    if not rewardDisplay or not rewardDisplay.texture then
        button.TagTexture:Hide()

        if button.RewardText then
            button.RewardText:SetText("")
            button.RewardText:Hide()
        end

        return
    end

    button.TagTexture:Show()
    button.TagTexture:SetTexture(rewardDisplay.texture)

    local texCoords = rewardDisplay.texCoords or ITEM_TEX_COORDS
    button.TagTexture:SetTexCoord(unpack(texCoords))

    if button.RewardText then
        if rewardDisplay.text and rewardDisplay.text ~= "" then
            local r, g, b = GetColorRGB(rewardDisplay.color, 1, 1, 1)
            button.RewardText:SetText(rewardDisplay.text)
            button.RewardText:SetTextColor(r, g, b)
            button.RewardText:Show()
        else
            button.RewardText:SetText("")
            button.RewardText:Hide()
        end
    end
end

function Maps:UpdateRowTimeIcon(button, questID, hasTaskIcon)
    if not button.TimeIcon then
        return
    end

    local shouldShowLowTimeIcon = false
    if QuestUtils_IsQuestWithinLowTimeThreshold then
        shouldShowLowTimeIcon = QuestUtils_IsQuestWithinLowTimeThreshold(questID)
    else
        local minutesRemaining = C_TaskQuest.GetQuestTimeLeftMinutes(questID)
        if minutesRemaining and WORLD_QUESTS_TIME_LOW_MINUTES then
            shouldShowLowTimeIcon = minutesRemaining > 0 and minutesRemaining <= WORLD_QUESTS_TIME_LOW_MINUTES
        end
    end

    if shouldShowLowTimeIcon then
        button.TimeIcon:Show()
        button.TimeIcon:ClearAllPoints()

        local isCriticalTime = false
        if QuestUtils_IsQuestWithinCriticalTimeThreshold then
            isCriticalTime = QuestUtils_IsQuestWithinCriticalTimeThreshold(questID)
        else
            local minutesRemaining = C_TaskQuest.GetQuestTimeLeftMinutes(questID)
            if minutesRemaining and WORLD_QUESTS_TIME_CRITICAL_MINUTES then
                isCriticalTime = minutesRemaining > 0 and minutesRemaining <= WORLD_QUESTS_TIME_CRITICAL_MINUTES
            end
        end

        if isCriticalTime then
            button.TimeIcon:SetVertexColor(GetColorRGB(RED_FONT_COLOR, 1, 0.1, 0.1))
        else
            button.TimeIcon:SetVertexColor(GetColorRGB(HIGHLIGHT_FONT_COLOR, 1, 1, 1))
        end

        if hasTaskIcon and button.TaskIcon and button.TaskIcon:IsShown() then
            button.TimeIcon:SetSize(14, 14)
            button.TimeIcon:SetPoint("CENTER", button.TaskIcon, "BOTTOMLEFT", 0, 0)
        else
            button.TimeIcon:SetSize(16, 16)
            button.TimeIcon:SetPoint("CENTER", button.Text, "LEFT", -15, 0)
        end
    else
        button.TimeIcon:Hide()
        button.TimeIcon:SetVertexColor(1, 1, 1)
    end
end

function Maps:SetupWorldQuestRow(button, entry)
    self:InitializeWorldQuestRow(button)

    local questID = entry.questID
    local info = entry.info or {}
    button.questID = questID
    button.mapID = entry.mapID
    button.numObjectives = info.numObjectives
    button.infoX = info.x
    button.infoY = info.y

    if C_TaskQuest and C_TaskQuest.RequestPreloadRewardData then
        C_TaskQuest.RequestPreloadRewardData(questID)
    end

    local title = entry.title or ""
    button.Text:SetText(title)
    if button.Text.SetWordWrap then
        button.Text:SetWordWrap(false)
    end
    if button.Text.SetNonSpaceWrap then
        button.Text:SetNonSpaceWrap(false)
    end
    if button.Text.SetMaxLines then
        button.Text:SetMaxLines(1)
    end

    local questTagInfo = self:GetCachedQuestTagInfo(questID)

    local difficulty = C_PlayerInfo and C_PlayerInfo.GetContentDifficultyQuestForPlayer and C_PlayerInfo.GetContentDifficultyQuestForPlayer(questID)
    if type(difficulty) ~= "number" then
        difficulty = UnitLevel("player") or 1
    end

    difficulty = difficulty + (questTagInfo and QuestRarityOffset[questTagInfo.quality] or 0)

    local difficultyColor = GetDifficultyColor and GetDifficultyColor(difficulty)
    local textR, textG, textB = GetColorRGB(difficultyColor or NORMAL_FONT_COLOR, 1, 0.82, 0)
    button.Text:SetTextColor(textR, textG, textB)

    local trackedFn = _G.WorldMap_IsWorldQuestEffectivelyTracked
    local isTracked = trackedFn and trackedFn(questID)
    if button.Checkbox and button.Checkbox.CheckMark then
        button.Checkbox.CheckMark:SetShown(isTracked == true)
    end

    local hasTaskIcon = false
    if button.TaskIcon then
        button.TaskIcon:Hide()

        if info.inProgress then
            button.TaskIcon:SetAtlas("worldquest-questmarker-questionmark")
            button.TaskIcon:SetSize(10, 15)
            button.TaskIcon:Show()
            hasTaskIcon = true
        elseif QuestUtil and QuestUtil.GetWorldQuestAtlasInfo then
            local atlas, width, height = QuestUtil.GetWorldQuestAtlasInfo(questID, questTagInfo, false)
            if atlas and atlas ~= "Worldquest-icon" then
                button.TaskIcon:SetAtlas(atlas)
                button.TaskIcon:SetSize(min(width or 16, 16), min(height or 16, 16))
                button.TaskIcon:Show()
                hasTaskIcon = true
            elseif questTagInfo and questTagInfo.isElite then
                button.TaskIcon:SetAtlas("questlog-questtypeicon-heroic")
                button.TaskIcon:SetSize(16, 16)
                button.TaskIcon:Show()
                hasTaskIcon = true
            end
        end
    end

    self:UpdateRowTimeIcon(button, questID, hasTaskIcon)
    self:ApplyRewardDisplay(button, self:GetCachedWorldQuestReward(questID))

    local lineHeight = button.Text.GetLineHeight and button.Text:GetLineHeight() or button.Text:GetStringHeight()
    local totalHeight = 8 + lineHeight
    button:SetHeight(totalHeight)
    button.HighlightTexture:SetShown(false)
end

----------------------------------------------------------------------------------------
-- Interaction
----------------------------------------------------------------------------------------

function Maps:ToggleWorldQuestManualTracking(questID)
    if not questID or not QuestUtil then
        return
    end

    local watchType = C_QuestLog.GetQuestWatchType(questID)
    local isSuperTracked = C_SuperTrack.GetSuperTrackedQuestID() == questID

    if watchType == Enum.QuestWatchType.Manual
        or (watchType == Enum.QuestWatchType.Automatic and isSuperTracked) then
        PlayCheckboxSound(false)
        QuestUtil.UntrackWorldQuest(questID)
    else
        PlayCheckboxSound(true)
        QuestUtil.TrackWorldQuest(questID, Enum.QuestWatchType.Manual)
    end
end

function Maps:OnWorldQuestRowClick(button, mouseButton)
    local questID = button.questID
    if not questID then
        return
    end

    if ChatFrameUtil and ChatFrameUtil.TryInsertQuestLinkForQuestID
        and ChatFrameUtil.TryInsertQuestLinkForQuestID(questID) then
        return
    end

    if mouseButton == "RightButton" then
        if InCombatLockdown and InCombatLockdown() then
            return
        end

        if button.mapID then
            local questMapFrame = _G.QuestMapFrame
            local mapFrame = questMapFrame and questMapFrame:GetParent()
            if mapFrame and mapFrame.SetMapID then
                mapFrame:SetMapID(button.mapID)
            end
        end
        return
    end

    if mouseButton ~= "LeftButton" then
        return
    end

    local watchType = C_QuestLog.GetQuestWatchType(questID)
    local isSuperTracked = C_SuperTrack.GetSuperTrackedQuestID() == questID

    if IsShiftKeyDown() then
        self:ToggleWorldQuestManualTracking(questID)
        return
    end

    if isSuperTracked then
        PlayCheckboxSound(false)
        C_SuperTrack.SetSuperTrackedQuestID(0)
    else
        PlayCheckboxSound(true)

        if QuestUtil and watchType ~= Enum.QuestWatchType.Manual then
            QuestUtil.TrackWorldQuest(questID, Enum.QuestWatchType.Automatic)
        end

        C_SuperTrack.SetSuperTrackedQuestID(questID)
    end
end

function Maps:OnWorldQuestRowEnter(button)
    self._worldQuestHoveredButton = button
    self._worldQuestHoveredQuestID = button.questID

    if button.HighlightTexture then
        button.HighlightTexture:Show()
    end

    if _G.TaskPOI_OnEnter then
        _G.TaskPOI_OnEnter(button)
    end

end

function Maps:OnWorldQuestRowLeave(button)
    if self._worldQuestHoveredButton == button then
        self._worldQuestHoveredButton = nil
        self._worldQuestHoveredQuestID = nil
    end

    if button.HighlightTexture then
        button.HighlightTexture:Hide()
    end

    if _G.TaskPOI_OnLeave then
        _G.TaskPOI_OnLeave(button)
    end

end

function Maps:ClearWorldQuestHover()
    local hoveredButton = self._worldQuestHoveredButton
    if hoveredButton then
        self:OnWorldQuestRowLeave(hoveredButton)
    else
        self._worldQuestHoveredButton = nil
        self._worldQuestHoveredQuestID = nil
    end
end

----------------------------------------------------------------------------------------
-- Rendering
----------------------------------------------------------------------------------------

function Maps:ClearWorldQuestListVisuals()
    self:ClearWorldQuestHover()

    if self._worldQuestRowPool then
        self._worldQuestRowPool:ReleaseAll()
    end

    if self._worldQuestHeaderButton then
        self._worldQuestHeaderButton.layoutIndex = nil
        if self._worldQuestHeaderButton.CollapseButton then
            self._worldQuestHeaderButton.CollapseButton.layoutIndex = nil
        end
        self._worldQuestHeaderButton:Hide()
    end

    if self._worldQuestSpacer then
        self._worldQuestSpacer.layoutIndex = nil
        self._worldQuestSpacer:Hide()
    end

    self._worldQuestHasInjectedFrames = false
end

function Maps:UpdateWorldQuestList()
    self:RegisterWorldQuestListMenu()

    local questMapFrame = _G.QuestMapFrame
    local questScrollFrame = _G.QuestScrollFrame
    if not questMapFrame or not questScrollFrame or not questScrollFrame.Contents then
        return
    end

    if not self:EnsureWorldQuestFrames() then
        return
    end

    local previouslyInjected = self._worldQuestHasInjectedFrames
    local previouslyHoveredQuestID = self._worldQuestHoveredQuestID

    self:ClearWorldQuestHover()
    self._worldQuestRowPool:ReleaseAll()
    self._worldQuestHeaderButton:Hide()

    local config = self:GetWorldQuestListConfig()
    if not config.Enable then
        if previouslyInjected then
            questScrollFrame.Contents:Layout()
        end
        self._worldQuestHasInjectedFrames = false
        return
    end

    local entries = self:CollectWorldQuestEntries()
    if #entries == 0 then
        if previouslyInjected then
            questScrollFrame.Contents:Layout()
        end
        self._worldQuestHasInjectedFrames = false
        return
    end

    self:SortWorldQuestEntries(entries, config.Sort)

    if self._worldQuestHeaderButton.SetHeaderText then
        self._worldQuestHeaderButton:SetHeaderText(HEADER_TEXT)
    else
        self._worldQuestHeaderButton:SetText(HEADER_TEXT)
    end

    local separator = questScrollFrame.Contents.Separator
    local layoutIndex
    if separator and type(separator.layoutIndex) == "number" then
        layoutIndex = separator.layoutIndex + 0.001
    else
        layoutIndex = (questMapFrame.GetLastLayoutIndex and questMapFrame:GetLastLayoutIndex() or 0) + 0.001
    end
    local layoutStep = 0.001

    self._worldQuestHeaderButton.layoutIndex = layoutIndex
    layoutIndex = layoutIndex + layoutStep
    self._worldQuestHeaderButton:Show()

    if not config.Collapsed then
        for i = 1, #entries do
            local row = self._worldQuestRowPool:Acquire()
            self:SetupWorldQuestRow(row, entries[i])
            row.layoutIndex = layoutIndex
            layoutIndex = layoutIndex + layoutStep
            row:Show()

            if previouslyHoveredQuestID and row.questID == previouslyHoveredQuestID and row:IsMouseOver() then
                self:OnWorldQuestRowEnter(row)
            end
        end
    end

    if self._worldQuestHeaderButton.CollapseButton then
        self._worldQuestHeaderButton.CollapseButton:UpdateCollapsedState(config.Collapsed)
        self._worldQuestHeaderButton.CollapseButton:Show()
        self._worldQuestHeaderButton.CollapseButton.layoutIndex = layoutIndex
        layoutIndex = layoutIndex + layoutStep
    end

    if self._worldQuestSpacer then
        self._worldQuestSpacer:SetHeight(SECTION_BOTTOM_PADDING)
        self._worldQuestSpacer.layoutIndex = layoutIndex
        self._worldQuestSpacer:Show()
        layoutIndex = layoutIndex + layoutStep
    end

    questScrollFrame.Contents:Layout()

    if questScrollFrame.EmptyText then
        questScrollFrame.EmptyText:Hide()
    end
    if questScrollFrame.NoSearchResultsText then
        questScrollFrame.NoSearchResultsText:Hide()
    end

    self._worldQuestHasInjectedFrames = true
end

function Maps:OnWorldQuestMapHide()
    self:ClearWorldQuestListVisuals()
    self:InvalidateWorldQuestListCaches()
end

----------------------------------------------------------------------------------------
-- Setup
----------------------------------------------------------------------------------------

function Maps:TrySetupWorldQuestListHooks()
    QuestUtil = QuestUtil or _G.QuestUtil
    ChatFrameUtil = ChatFrameUtil or _G.ChatFrameUtil

    self:RegisterWorldQuestListMenu()

    if not self._worldQuestHookedQuestLogUpdate then
        local ok = RefineUI:HookOnce("Maps:WorldQuestList:QuestLogQuests_Update", "QuestLogQuests_Update", function()
            self:UpdateWorldQuestList()
        end)

        if ok then
            self._worldQuestHookedQuestLogUpdate = true
        end
    end

    if not self._worldQuestHookedQuestMapHide then
        local questMapFrame = _G.QuestMapFrame
        if questMapFrame then
            local ok = RefineUI:HookScriptOnce("Maps:WorldQuestList:QuestMapFrame:OnHide", questMapFrame, "OnHide", function()
                self:OnWorldQuestMapHide()
            end)

            if ok then
                self._worldQuestHookedQuestMapHide = true
            end
        end
    end

    if not self._worldQuestHookedResetUsage then
        local questScrollFrame = _G.QuestScrollFrame
        local contents = questScrollFrame and questScrollFrame.Contents
        if contents and type(contents.ResetUsage) == "function" then
            local ok = RefineUI:HookOnce("Maps:WorldQuestList:QuestScrollFrame.Contents:ResetUsage", contents, "ResetUsage", function()
                self:ClearWorldQuestListVisuals()
            end)

            if ok then
                self._worldQuestHookedResetUsage = true
            end
        end
    end
end

function Maps:SetupWorldQuestList()
    if self._worldQuestSetupDone then
        return
    end
    self._worldQuestSetupDone = true

    self:EnsureWorldQuestListState()
    self:TrySetupWorldQuestListHooks()

    RefineUI:RegisterEventCallback("QUEST_LOG_UPDATE", function()
        self:InvalidateWorldQuestListCaches()
    end, "Maps:WorldQuestList:QUEST_LOG_UPDATE")

    RefineUI:RegisterEventCallback("ADDON_LOADED", function(_, addonName)
        if addonName == "Blizzard_WorldMap" or addonName == "Blizzard_Menu" then
            self:TrySetupWorldQuestListHooks()
        end
    end, "Maps:WorldQuestList:ADDON_LOADED")
end
