----------------------------------------------------------------------------------------
-- EncounterAchievements UI
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local EncounterAchievements = RefineUI:GetModule("EncounterAchievements")
if not EncounterAchievements then
    return
end

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local _G = _G
local CreateFrame = CreateFrame
local PlaySound = PlaySound
local SOUNDKIT = SOUNDKIT
local format = string.format
local ipairs = ipairs
local select = select
local type = type

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local CUSTOM_TAB_ID = 5001
local ROW_EXTENT = 49

local EMPTY_STATE_NO_INSTANCE = "Select a dungeon or raid instance to view achievements."
local EMPTY_STATE_NO_RESULTS = "No dungeon or raid achievements were found for this instance."
local EMPTY_STATE_NO_FILTER_RESULTS = "No achievements match the selected boss filter."
local EMPTY_STATE_LOADING = "Loading achievements..."
local EMPTY_STATE_NO_UI = "Blizzard_AchievementUI is unavailable."
local EMPTY_STATE_NO_SCROLL = "Scroll list API is unavailable."
local BOSS_FILTER_ALL = 0

local NATIVE_TAB_KEYS = {
    "overviewTab",
    "lootTab",
    "bossTab",
    "modelTab",
}

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local function GetEncounterFrames()
    local journal = _G.EncounterJournal
    local encounter = journal and journal.encounter
    local info = encounter and encounter.info
    return journal, encounter, info
end

local function IsValidInstanceID(instanceID)
    return type(instanceID) == "number" and instanceID > 0
end

local function NormalizeTextToken(text)
    if type(text) ~= "string" then
        return ""
    end

    local token = text:lower()
    token = token:gsub("|c%x%x%x%x%x%x%x%x", "")
    token = token:gsub("|r", "")
    token = token:gsub("[%s]+", "")
    token = token:gsub("[%p%c]+", "")
    return token
end

----------------------------------------------------------------------------------------
-- UI Creation
----------------------------------------------------------------------------------------
function EncounterAchievements:CreateCustomSideTab(infoFrame)
    if self.customTabButton or not infoFrame then
        return
    end

    local anchorTab = infoFrame.modelTab
    if not anchorTab then
        return
    end

    local tab = CreateFrame("Button", nil, infoFrame, "EncounterTabTemplate")
    tab:SetID(CUSTOM_TAB_ID)
    tab.tooltip = _G.ACHIEVEMENTS or "Achievements"
    tab:SetPoint("TOP", anchorTab, "BOTTOM", 0, 2)
    tab:SetScript("OnClick", function()
        self:OnAchievementsTabClicked()
    end)

    local atlasName = "ShipMissionIcon-Bonus-Map"

    local unselected = tab:CreateTexture(nil, "OVERLAY")
    unselected:SetSize(42, 42)
    unselected:SetPoint("CENTER", tab, "CENTER", 0, 0)
    unselected:SetAtlas(atlasName)
    unselected:SetVertexColor(0.83, 0.73, 0.58, 0.9)

    local selected = tab:CreateTexture(nil, "OVERLAY")
    selected:SetAllPoints(unselected)
    selected:SetAtlas(atlasName)
    selected:SetVertexColor(1, 0.93, 0.66, 1)
    selected:Hide()

    tab.unselected = unselected
    tab.selected = selected
    tab:Hide()

    self.customTabButton = tab
end

function EncounterAchievements:CreateCustomPanel(infoFrame)
    if self.customPanel or not infoFrame or not infoFrame.detailsScroll then
        return
    end

    local panel = CreateFrame("Frame", nil, infoFrame)
    local panelAnchorFrame = infoFrame.model or infoFrame.detailsScroll
    panel:SetPoint("TOPLEFT", panelAnchorFrame, "TOPLEFT", 0, 0)
    panel:SetPoint("BOTTOMRIGHT", panelAnchorFrame, "BOTTOMRIGHT", 0, 0)
    panel:SetFrameStrata("DIALOG")
    panel:SetFrameLevel((infoFrame:GetFrameLevel() or 1) + 40)
    panel:Hide()

    panel.Bg = panel:CreateTexture(nil, "BACKGROUND")
    panel.Bg:SetAllPoints()
    panel.Bg:SetColorTexture(0.07, 0.055, 0.03, 1)

    panel.HeaderText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.HeaderText:SetPoint("TOPLEFT", panel, "TOPLEFT", 11, -11)
    panel.HeaderText:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -186, -11)
    panel.HeaderText:SetJustifyH("LEFT")
    panel.HeaderText:SetText(_G.ACHIEVEMENTS or "Achievements")
    panel.HeaderText:SetTextColor(0.93, 0.79, 0.62)

    panel.MetaText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.MetaText:SetPoint("TOPLEFT", panel.HeaderText, "BOTTOMLEFT", 0, -2)
    panel.MetaText:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -186, -13)
    panel.MetaText:SetJustifyH("LEFT")
    panel.MetaText:SetTextColor(0.62, 0.51, 0.34)

    panel.BossDropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
    panel.BossDropdown:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -8)
    panel.BossDropdown:SetSize(170, 26)

    panel.Divider = panel:CreateTexture(nil, "ARTWORK")
    panel.Divider:SetPoint("TOPLEFT", panel.MetaText, "BOTTOMLEFT", -1, -5)
    panel.Divider:SetPoint("TOPRIGHT", panel.MetaText, "BOTTOMRIGHT", 1, -5)
    panel.Divider:SetHeight(1)
    panel.Divider:SetColorTexture(0.34, 0.26, 0.16, 0.8)

    panel.ScrollBox = CreateFrame("Frame", nil, panel, "WowScrollBoxList")
    panel.ScrollBox:SetPoint("TOPLEFT", panel.Divider, "BOTTOMLEFT", 0, -6)
    panel.ScrollBox:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -20, 6)

    panel.ScrollBar = CreateFrame("EventFrame", nil, panel, "MinimalScrollBar")
    panel.ScrollBar:SetPoint("TOPLEFT", panel.ScrollBox, "TOPRIGHT", 5, -4)
    panel.ScrollBar:SetPoint("BOTTOMLEFT", panel.ScrollBox, "BOTTOMRIGHT", 5, 4)
    if panel.ScrollBar.SetHideIfUnscrollable then
        panel.ScrollBar:SetHideIfUnscrollable(true)
    end
    if panel.ScrollBar.SetInterpolateScroll then
        panel.ScrollBar:SetInterpolateScroll(true)
    end

    panel.EmptyText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    panel.EmptyText:SetPoint("TOPLEFT", panel.Divider, "BOTTOMLEFT", 18, -24)
    panel.EmptyText:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -34, 18)
    panel.EmptyText:SetJustifyH("CENTER")
    panel.EmptyText:SetJustifyV("MIDDLE")
    panel.EmptyText:SetText(EMPTY_STATE_NO_INSTANCE)
    panel.EmptyText:Hide()

    self.customPanel = panel
end

function EncounterAchievements:InstallNativeVisibilityGuards(infoFrame)
    if self.nativeVisibilityGuardsInstalled or not infoFrame then
        return
    end

    local function GuardFrame(nativeFrame)
        if not nativeFrame or not nativeFrame.HookScript then
            return
        end

        nativeFrame:HookScript("OnShow", function(frame)
            if self.customTabActive then
                frame:Hide()
            end
        end)
    end

    GuardFrame(infoFrame.overviewScroll)
    GuardFrame(infoFrame.LootContainer)
    GuardFrame(infoFrame.detailsScroll)
    GuardFrame(infoFrame.model)
    GuardFrame(infoFrame.overviewScroll and infoFrame.overviewScroll.child)
    GuardFrame(infoFrame.detailsScroll and infoFrame.detailsScroll.child)

    local _, encounterFrame = GetEncounterFrames()
    GuardFrame(encounterFrame and encounterFrame.overviewFrame)
    GuardFrame(encounterFrame and encounterFrame.infoFrame)

    self.nativeVisibilityGuardsInstalled = true
end

function EncounterAchievements:EnsureUI()
    if self.uiInitialized then
        return
    end

    local _, _, infoFrame = GetEncounterFrames()
    if not infoFrame then
        return
    end

    self:CreateCustomSideTab(infoFrame)
    self:CreateCustomPanel(infoFrame)
    self:InstallNativeVisibilityGuards(infoFrame)

    self.uiInitialized = self.customTabButton ~= nil and self.customPanel ~= nil
end

function EncounterAchievements:GetCurrentJournalEncounterID()
    local journal = _G.EncounterJournal
    local encounterID = journal and journal.encounterID or nil
    if type(encounterID) == "number" and encounterID > 0 then
        return encounterID
    end
    return nil
end

function EncounterAchievements:GetBossFilterAllLabel()
    local allLabel = _G.ALL or "All"
    local bossLabel = _G.BOSSES or "Bosses"
    if type(allLabel) ~= "string" or allLabel == "" then
        allLabel = "All"
    end
    if type(bossLabel) ~= "string" or bossLabel == "" then
        bossLabel = "Bosses"
    end
    return format("%s %s", allLabel, bossLabel)
end

function EncounterAchievements:BuildBossFilterOptions()
    local options = {}
    local optionMap = {}

    options[#options + 1] = {
        encounterID = BOSS_FILTER_ALL,
        label = self:GetBossFilterAllLabel(),
        token = "",
    }
    optionMap[BOSS_FILTER_ALL] = true

    if type(EJ_GetEncounterInfoByIndex) ~= "function" then
        return options, optionMap
    end

    local index = 1
    while true do
        local encounterName, _, encounterID = EJ_GetEncounterInfoByIndex(index)
        if type(encounterID) ~= "number" or encounterID <= 0 then
            break
        end

        local label = encounterName
        if type(label) ~= "string" or label == "" then
            label = format("%s %d", _G.BOSS or "Boss", index)
        end

        options[#options + 1] = {
            encounterID = encounterID,
            label = label,
            token = NormalizeTextToken(label),
        }
        optionMap[encounterID] = true

        index = index + 1
    end

    return options, optionMap
end

function EncounterAchievements:EnsureBossFilterState(instanceID)
    if self.bossFilterInstanceID ~= instanceID then
        self.bossFilterInstanceID = instanceID
        self.currentBossFilterOptions = nil
        self.currentBossFilterOptionMap = nil
        self.selectedBossFilterEncounterID = nil
        self.bossFilterUserSelected = false
    end

    if type(self.currentBossFilterOptions) ~= "table" or #self.currentBossFilterOptions == 0 then
        self.currentBossFilterOptions, self.currentBossFilterOptionMap = self:BuildBossFilterOptions()
    end

    local optionMap = self.currentBossFilterOptionMap or {}
    local encounterID = self:GetCurrentJournalEncounterID()
    local defaultEncounterID = optionMap[encounterID] and encounterID or BOSS_FILTER_ALL

    local selectedEncounterID = self.selectedBossFilterEncounterID
    local hasValidSelection = optionMap[selectedEncounterID] == true

    if not hasValidSelection then
        self.selectedBossFilterEncounterID = defaultEncounterID
    elseif not self.bossFilterUserSelected and selectedEncounterID ~= defaultEncounterID then
        self.selectedBossFilterEncounterID = defaultEncounterID
    end
end

function EncounterAchievements:GetSelectedBossFilterOption()
    local options = self.currentBossFilterOptions
    if type(options) ~= "table" then
        return nil
    end

    local selectedEncounterID = self.selectedBossFilterEncounterID
    for _, option in ipairs(options) do
        if option.encounterID == selectedEncounterID then
            return option
        end
    end

    return options[1]
end

function EncounterAchievements:SetupBossFilterDropdown()
    local panel = self.customPanel
    local dropdown = panel and panel.BossDropdown
    if not dropdown or not dropdown.SetupMenu then
        return
    end

    local options = self.currentBossFilterOptions or {}
    dropdown:SetupMenu(function(_, rootDescription)
        rootDescription:SetTag("MENU_EJ_BOSS_FILTER")

        for _, option in ipairs(options) do
            local encounterID = option.encounterID
            local label = option.label
            rootDescription:CreateRadio(label, function()
                return self.selectedBossFilterEncounterID == encounterID
            end, function()
                self.selectedBossFilterEncounterID = encounterID
                self.bossFilterUserSelected = true
                self:UpdateBossFilterDropdownText()
                self:RefreshCustomTabContent()
            end)
        end
    end)
end

function EncounterAchievements:UpdateBossFilterDropdownText()
    local panel = self.customPanel
    local dropdown = panel and panel.BossDropdown
    if not dropdown then
        return
    end

    local selectedOption = self:GetSelectedBossFilterOption()
    local label = selectedOption and selectedOption.label or self:GetBossFilterAllLabel()
    if dropdown.SetDefaultText then
        dropdown:SetDefaultText(label)
    end
end

function EncounterAchievements:GetRowBossMatchToken(row)
    if type(row) ~= "table" then
        return ""
    end

    if type(row._bossMatchToken) == "string" then
        return row._bossMatchToken
    end

    local sourceText = format("%s %s %s", row.name or "", row.description or "", row.categoryPath or "")
    local token = NormalizeTextToken(sourceText)
    row._bossMatchToken = token
    return token
end

function EncounterAchievements:RowMatchesBossFilter(row, selectedOption)
    if type(selectedOption) ~= "table" or selectedOption.encounterID == BOSS_FILTER_ALL then
        return true
    end

    local bossToken = selectedOption.token
    if type(bossToken) ~= "string" or bossToken == "" then
        return false
    end

    local rowToken = self:GetRowBossMatchToken(row)
    return rowToken ~= "" and string.find(rowToken, bossToken, 1, true) ~= nil
end

function EncounterAchievements:FilterRowsByBoss(rows)
    if type(rows) ~= "table" then
        return {}
    end

    local selectedOption = self:GetSelectedBossFilterOption()
    if not selectedOption or selectedOption.encounterID == BOSS_FILTER_ALL then
        return rows
    end

    local filtered = {}
    for index = 1, #rows do
        local row = rows[index]
        if self:RowMatchesBossFilter(row, selectedOption) then
            filtered[#filtered + 1] = row
        end
    end

    return filtered
end

function EncounterAchievements:ResetBossFilterSelection()
    self.selectedBossFilterEncounterID = nil
    self.bossFilterUserSelected = false
end

----------------------------------------------------------------------------------------
-- UI Helpers
----------------------------------------------------------------------------------------
function EncounterAchievements:ShowNativeDifficultyByCurrentTab()
    local _, _, infoFrame = GetEncounterFrames()
    if not infoFrame or not infoFrame.difficulty then
        return
    end

    local shouldDisplayDifficulty = select(9, EJ_GetInstanceInfo()) and (infoFrame.tab ~= 4)
    infoFrame.difficulty:SetShown(shouldDisplayDifficulty)
end

----------------------------------------------------------------------------------------
-- Panel State
----------------------------------------------------------------------------------------
function EncounterAchievements:SetCustomTabSelected(selected)
    local tab = self.customTabButton
    if not tab then
        return
    end

    if selected then
        if tab.selected then
            tab.selected:Show()
        end
        if tab.unselected then
            tab.unselected:Hide()
        end
        tab:LockHighlight()
    else
        if tab.selected then
            tab.selected:Hide()
        end
        if tab.unselected then
            tab.unselected:Show()
        end
        tab:UnlockHighlight()
    end
end

function EncounterAchievements:ClearNativeTabSelection()
    local _, _, infoFrame = GetEncounterFrames()
    if not infoFrame then
        return
    end

    for _, tabKey in ipairs(NATIVE_TAB_KEYS) do
        local tab = infoFrame[tabKey]
        if tab then
            if tab.selected then
                tab.selected:Hide()
            end
            if tab.unselected then
                tab.unselected:Show()
            end
            tab:UnlockHighlight()
        end
    end
end

function EncounterAchievements:HideNativeEncounterContent()
    local _, encounterFrame, infoFrame = GetEncounterFrames()
    if not infoFrame then
        return
    end

    if infoFrame.BG then
        infoFrame.BG:Hide()
    end
    if infoFrame.leftShadow then
        infoFrame.leftShadow:Hide()
    end
    if infoFrame.model and infoFrame.model.dungeonBG then
        infoFrame.model.dungeonBG:Hide()
    end

    if infoFrame.overviewScroll then
        infoFrame.overviewScroll:Hide()
    end
    if infoFrame.LootContainer then
        infoFrame.LootContainer:Hide()
        if infoFrame.LootContainer.classClearFilter then
            infoFrame.LootContainer.classClearFilter:Hide()
        end
    end
    if infoFrame.detailsScroll then
        infoFrame.detailsScroll:Hide()
    end
    if infoFrame.model then
        infoFrame.model:Hide()
    end
    if infoFrame.overviewScroll and infoFrame.overviewScroll.child then
        infoFrame.overviewScroll.child:Hide()
    end
    if infoFrame.detailsScroll and infoFrame.detailsScroll.child then
        infoFrame.detailsScroll.child:Hide()
    end
    if encounterFrame and encounterFrame.overviewFrame then
        encounterFrame.overviewFrame:Hide()
    end
    if encounterFrame and encounterFrame.infoFrame then
        encounterFrame.infoFrame:Hide()
    end

    if type(_G.EncounterJournal_HideCreatures) == "function" then
        _G.EncounterJournal_HideCreatures()
    end

    if infoFrame.encounterTitle then
        infoFrame.encounterTitle:Hide()
    end
    if infoFrame.difficulty then
        infoFrame.difficulty:Hide()
    end
    if infoFrame.rightShadow then
        infoFrame.rightShadow:Hide()
    end
end

function EncounterAchievements:ShowNativeEncounterContent()
    local journal, encounterFrame, infoFrame = GetEncounterFrames()
    if not journal or not encounterFrame or not infoFrame then
        return
    end

    if not journal:IsShown() or not encounterFrame:IsShown() then
        return
    end

    self:ShowNativeDifficultyByCurrentTab()

    if infoFrame.BG then
        infoFrame.BG:Show()
    end
    if infoFrame.leftShadow then
        infoFrame.leftShadow:Show()
    end
    if infoFrame.model and infoFrame.model.dungeonBG then
        infoFrame.model.dungeonBG:Show()
    end

    if infoFrame.overviewScroll and infoFrame.overviewScroll.child then
        infoFrame.overviewScroll.child:Show()
    end
    if infoFrame.detailsScroll and infoFrame.detailsScroll.child then
        infoFrame.detailsScroll.child:Show()
    end
    if encounterFrame and encounterFrame.overviewFrame then
        encounterFrame.overviewFrame:Show()
    end
    if encounterFrame and encounterFrame.infoFrame then
        encounterFrame.infoFrame:Show()
    end

    local hasVisibleNativeFrame = (infoFrame.overviewScroll and infoFrame.overviewScroll:IsShown())
        or (infoFrame.detailsScroll and infoFrame.detailsScroll:IsShown())
        or (infoFrame.LootContainer and infoFrame.LootContainer:IsShown())
        or (infoFrame.model and infoFrame.model:IsShown())
    if hasVisibleNativeFrame then
        return
    end

    if type(_G.EncounterJournal_SetTab) == "function" then
        local selectedNativeTab = type(infoFrame.tab) == "number" and infoFrame.tab
        if not selectedNativeTab and infoFrame.overviewTab then
            selectedNativeTab = infoFrame.overviewTab:GetID()
        end
        if type(selectedNativeTab) == "number" then
            _G.EncounterJournal_SetTab(selectedNativeTab)
        end
    end
end

function EncounterAchievements:SetPanelHeader(instanceName, achievementCount, categoryID, totalCount)
    local panel = self.customPanel
    if not panel then
        return
    end

    local displayName = instanceName
    if type(displayName) ~= "string" or displayName == "" then
        displayName = _G.ACHIEVEMENTS or "Achievements"
    end

    panel.HeaderText:SetText(format("%s (%d)", displayName, achievementCount or 0))

    local metaParts = {}
    if categoryID then
        metaParts[#metaParts + 1] = self:GetCategoryPath(categoryID, " > ")
    end

    if type(totalCount) == "number" and totalCount > 0 and totalCount ~= achievementCount then
        metaParts[#metaParts + 1] = format("Showing %d of %d", achievementCount or 0, totalCount)
    end

    local selectedBoss = self:GetSelectedBossFilterOption()
    if selectedBoss and selectedBoss.encounterID ~= BOSS_FILTER_ALL then
        metaParts[#metaParts + 1] = format("Boss: %s", selectedBoss.label or "")
    end

    panel.MetaText:SetText(table.concat(metaParts, "  |  "))
end

function EncounterAchievements:SetPanelEmptyState(message, hideList)
    local panel = self.customPanel
    if not panel then
        return
    end

    if type(message) == "string" and message ~= "" then
        panel.EmptyText:SetText(message)
        panel.EmptyText:Show()
    else
        panel.EmptyText:Hide()
    end

    if hideList then
        panel.ScrollBox:Hide()
        panel.ScrollBar:Hide()
    else
        panel.ScrollBox:Show()
        panel.ScrollBar:Show()
    end
end

function EncounterAchievements:EnsureAchievementListView()
    if self.customScrollViewInitialized then
        return true
    end

    local panel = self.customPanel
    if not panel then
        return false
    end

    if not self:IsAchievementUIReady() then
        return false
    end

    if type(_G.ScrollUtil) ~= "table" or type(_G.ScrollUtil.InitScrollBoxListWithScrollBar) ~= "function" then
        return false
    end

    if type(_G.CreateScrollBoxListLinearView) ~= "function" then
        return false
    end

    local view = _G.CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_EXTENT)
    view:SetElementInitializer("AchievementFullSearchResultsButtonTemplate", function(button, elementData)
        self:InitializeAchievementRow(button, elementData)
    end)
    view:SetElementResetter(function(button)
        self:ResetAchievementRow(button)
    end)
    view:SetPadding(0, 0, 0, 2, 0)

    local ok = pcall(_G.ScrollUtil.InitScrollBoxListWithScrollBar, panel.ScrollBox, panel.ScrollBar, view)
    if not ok then
        return false
    end

    self.customScrollView = view
    self.customScrollViewInitialized = true
    return true
end

function EncounterAchievements:PopulateAchievementRows(rows, instanceID)
    local panel = self.customPanel
    if not panel then
        return
    end

    if type(_G.CreateDataProvider) ~= "function" then
        self:SetPanelEmptyState(EMPTY_STATE_NO_SCROLL, true)
        return
    end

    local dataProvider = _G.CreateDataProvider()
    for index = 1, #rows do
        local row = rows[index]
        dataProvider:Insert({
            index = index,
            row = row,
            achievementID = row.achievementID,
        })
    end

    panel.ScrollBox:SetDataProvider(dataProvider)

    if panel.lastInstanceID ~= instanceID and panel.ScrollBox.ScrollToBegin then
        panel.ScrollBox:ScrollToBegin()
    end
    panel.lastInstanceID = instanceID
end

----------------------------------------------------------------------------------------
-- Public UI Methods
----------------------------------------------------------------------------------------
function EncounterAchievements:IsSupportedContentTab(tabID)
    local journal = _G.EncounterJournal
    if not journal then
        return false
    end

    local selectedTabID = tabID or journal.selectedTab
    if type(selectedTabID) ~= "number" then
        return false
    end

    local dungeonTabID = journal.dungeonsTab and journal.dungeonsTab:GetID()
    local raidTabID = journal.raidsTab and journal.raidsTab:GetID()

    return selectedTabID == dungeonTabID or selectedTabID == raidTabID
end

function EncounterAchievements:UpdateCustomTabAvailability()
    self:EnsureUI()

    local journal, encounterFrame, _ = GetEncounterFrames()
    local tab = self.customTabButton
    if not journal or not encounterFrame or not tab then
        return
    end

    local selectedTabSupported = self:IsSupportedContentTab(journal.selectedTab)
    local instanceID = self:GetCurrentJournalInstanceID()
    local hasInstance = IsValidInstanceID(instanceID)
    local shouldShow = encounterFrame:IsShown() and selectedTabSupported and hasInstance

    self.customTabAvailable = shouldShow

    if shouldShow then
        tab:Show()
        tab:SetEnabled(true)
    else
        if self.customTabActive then
            self:DeactivateCustomTab()
        end
        tab:SetEnabled(false)
        tab:Hide()
    end
end

function EncounterAchievements:ActivateCustomTab()
    if not self.customTabAvailable then
        return
    end

    self:EnsureUI()
    if not self.customPanel or not self.customTabButton then
        return
    end

    self.customTabActive = true
    self:ResetBossFilterSelection()

    self:SetCustomTabSelected(true)
    self:ClearNativeTabSelection()
    self:HideNativeEncounterContent()

    self.customPanel:Show()
    self:RefreshCustomTabContent()
end

function EncounterAchievements:DeactivateCustomTab()
    if not self.customTabActive then
        self:SetCustomTabSelected(false)
        if self.customPanel then
            self.customPanel:Hide()
        end
        return
    end

    self.customTabActive = false
    self.pendingRowRefreshInstanceID = nil
    self:SetCustomTabSelected(false)

    if self.customPanel then
        self.customPanel:Hide()
    end

    if self.CancelPendingInstanceRowBuilds then
        self:CancelPendingInstanceRowBuilds()
    end

    self:ShowNativeEncounterContent()
end

function EncounterAchievements:RefreshCustomTabContent()
    if not self.customTabActive then
        return
    end

    self:EnsureUI()
    local panel = self.customPanel
    if not panel then
        return
    end

    self:SetCustomTabSelected(true)
    self:HideNativeEncounterContent()

    local instanceID = self.currentInstanceID or self:GetCurrentJournalInstanceID()
    if not IsValidInstanceID(instanceID) then
        self:SetPanelHeader(nil, 0, nil)
        self:SetPanelEmptyState(EMPTY_STATE_NO_INSTANCE, true)
        return
    end
    self.currentInstanceID = instanceID

    local instanceName, _, _, _, _, _, _, _, _, _, _, isRaid = EJ_GetInstanceInfo(instanceID)
    local rows, categoryID, isPending = self:GetCachedInstanceAchievementRows(instanceID)

    if type(rows) ~= "table" then
        self:EnsureBossFilterState(instanceID)
        self:SetupBossFilterDropdown()
        self:UpdateBossFilterDropdownText()

        if not isPending or self.pendingRowRefreshInstanceID ~= instanceID then
            self.pendingRowRefreshInstanceID = instanceID
            self:RequestInstanceAchievementRows(instanceID, isRaid == true, function(doneInstanceID)
                if self.pendingRowRefreshInstanceID == doneInstanceID then
                    self.pendingRowRefreshInstanceID = nil
                end
                if self.customTabActive and self.currentInstanceID == doneInstanceID then
                    self:RefreshCustomTabContent()
                end
            end)
        end

        self:SetPanelHeader(instanceName, 0, nil)
        self:SetPanelEmptyState(EMPTY_STATE_LOADING, true)
        return
    end

    self.pendingRowRefreshInstanceID = nil
    self:EnsureBossFilterState(instanceID)
    self:SetupBossFilterDropdown()
    self:UpdateBossFilterDropdownText()

    local totalCount = (type(rows) == "table") and #rows or 0
    local filteredRows = self:FilterRowsByBoss(rows)
    local filteredCount = #filteredRows

    self:SetPanelHeader(instanceName, filteredCount, categoryID, totalCount)

    if totalCount <= 0 then
        self:SetPanelEmptyState(EMPTY_STATE_NO_RESULTS, true)
        return
    end

    if filteredCount <= 0 then
        self:SetPanelEmptyState(EMPTY_STATE_NO_FILTER_RESULTS, true)
        return
    end

    local listViewReady = self:EnsureAchievementListView()
    if not listViewReady then
        if not self:IsAchievementUIReady() then
            if not self.pendingAchievementUILoadFromTab
                and self.EnsureAchievementUILoaded
                and type(_G.C_Timer) == "table"
                and type(_G.C_Timer.After) == "function" then
                self.pendingAchievementUILoadFromTab = true
                _G.C_Timer.After(0, function()
                    self.pendingAchievementUILoadFromTab = false
                    self:EnsureAchievementUILoaded()
                    if self.customTabActive and self.currentInstanceID == instanceID then
                        self:RefreshCustomTabContent()
                    end
                end)
            end

            self:SetPanelEmptyState(EMPTY_STATE_LOADING, true)
            return
        end

        if not self:EnsureAchievementListView() then
            self:SetPanelEmptyState(EMPTY_STATE_NO_SCROLL, true)
            return
        end
    end

    self:SetPanelEmptyState(nil, false)
    self:PopulateAchievementRows(filteredRows, instanceID)
end

function EncounterAchievements:OnAchievementsTabClicked()
    if not self.customTabAvailable then
        return
    end

    if type(PlaySound) == "function" and type(SOUNDKIT) == "table" and SOUNDKIT.IG_ABILITY_PAGE_TURN then
        PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN)
    end

    self:ActivateCustomTab()
end
