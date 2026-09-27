----------------------------------------------------------------------------------------
-- AdventureGuideInstances UI
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local AdventureGuideInstances = RefineUI:GetModule("AdventureGuideInstances")
if not AdventureGuideInstances then
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

----------------------------------------------------------------------------------------
-- UI Creation
----------------------------------------------------------------------------------------
function AdventureGuideInstances:CreateCustomSideTab(infoFrame)
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

function AdventureGuideInstances:CreateCustomPanel(infoFrame)
    if self.customPanel or not infoFrame or not infoFrame.detailsScroll then
        return
    end

    local panel = CreateFrame("Frame", nil, infoFrame)
    local panelAnchorFrame = infoFrame.model or infoFrame.detailsScroll
    panel:SetPoint("TOPLEFT", panelAnchorFrame, "TOPLEFT", 0, 0)
    panel:SetPoint("BOTTOMRIGHT", panelAnchorFrame, "BOTTOMRIGHT", 0, 0)
    -- Stay in the journal's strata so other windows can still cover the panel.
    panel:SetFrameLevel(infoFrame:GetFrameLevel() + 40)
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

function AdventureGuideInstances:InstallNativeVisibilityGuards(infoFrame)
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

function AdventureGuideInstances:EnsureUI()
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

function AdventureGuideInstances:GetCurrentJournalEncounterID()
    local journal = _G.EncounterJournal
    local encounterID = journal and journal.encounterID or nil
    if type(encounterID) == "number" and encounterID > 0 then
        return encounterID
    end
    return nil
end

function AdventureGuideInstances:GetBossFilterAllLabel()
    return format("%s %s", _G.ALL, _G.BOSSES)
end

function AdventureGuideInstances:BuildBossFilterOptions()
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
            token = self:NormalizeCompletionToken(label),
        }
        optionMap[encounterID] = true

        index = index + 1
    end

    return options, optionMap
end

function AdventureGuideInstances:EnsureBossFilterState(instanceID)
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

function AdventureGuideInstances:GetSelectedBossFilterOption()
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

function AdventureGuideInstances:SetupBossFilterDropdown()
    local panel = self.customPanel
    local dropdown = panel and panel.BossDropdown
    if not dropdown or not dropdown.SetupMenu then
        return
    end

    local options = self.currentBossFilterOptions or {}
    if dropdown.encounterAchievementOptions == options then
        return
    end
    dropdown.encounterAchievementOptions = options
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

-- The label follows the selected radio. SetDefaultText only applies when nothing is
-- selected, so a programmatic selection change (for example opening a boss) needs Update.
function AdventureGuideInstances:UpdateBossFilterDropdownText()
    local dropdown = self.customPanel and self.customPanel.BossDropdown
    if dropdown and dropdown:GetMenuDescription() then
        dropdown:Update()
    end
end

function AdventureGuideInstances:FilterRowsByBoss(rows)
    if type(rows) ~= "table" then
        return {}
    end

    local selectedOption = self:GetSelectedBossFilterOption()
    if not selectedOption or selectedOption.encounterID == BOSS_FILTER_ALL then
        return rows
    end

    if self._filteredSourceRows == rows and self._filteredBossToken == selectedOption.token then
        return self._filteredRows
    end
    local filtered = {}
    for index = 1, #rows do
        local row = rows[index]
        if self:RowMatchesBossFilter(row, selectedOption) then
            filtered[#filtered + 1] = row
        end
    end

    self._filteredSourceRows = rows
    self._filteredBossToken = selectedOption.token
    self._filteredRows = filtered
    return filtered
end

function AdventureGuideInstances:ResetBossFilterSelection()
    self.selectedBossFilterEncounterID = nil
    self.bossFilterUserSelected = false
end

----------------------------------------------------------------------------------------
-- UI Helpers
----------------------------------------------------------------------------------------
function AdventureGuideInstances:ShowNativeDifficultyByCurrentTab()
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
local function SetTabSelected(tab, selected)
    tab.selected:SetShown(selected)
    tab.unselected:SetShown(not selected)
    if selected then
        tab:LockHighlight()
    else
        tab:UnlockHighlight()
    end
end

-- Accepts nil entries so optional native frames can be listed inline.
local function SetFramesShown(shown, ...)
    for index = 1, select("#", ...) do
        local frame = select(index, ...)
        if frame then
            frame:SetShown(shown)
        end
    end
end

function AdventureGuideInstances:SetCustomTabSelected(selected)
    if self.customTabButton then
        SetTabSelected(self.customTabButton, selected)
    end
end

function AdventureGuideInstances:ClearNativeTabSelection()
    local _, _, infoFrame = GetEncounterFrames()
    if not infoFrame then
        return
    end

    for _, tabKey in ipairs(NATIVE_TAB_KEYS) do
        local tab = infoFrame[tabKey]
        if tab then
            SetTabSelected(tab, false)
        end
    end
end

function AdventureGuideInstances:HideNativeEncounterContent()
    local _, encounterFrame, infoFrame = GetEncounterFrames()
    if not infoFrame then
        return
    end

    local model, overview, details, loot = infoFrame.model, infoFrame.overviewScroll, infoFrame.detailsScroll, infoFrame.LootContainer
    SetFramesShown(false,
        infoFrame.BG, infoFrame.leftShadow, infoFrame.rightShadow, infoFrame.encounterTitle, infoFrame.difficulty,
        model, model and model.dungeonBG, overview, overview and overview.child, details, details and details.child,
        loot, loot and loot.classClearFilter, encounterFrame.overviewFrame, encounterFrame.infoFrame,
        -- Instance lore sits on Blizzard's HIGH strata, above this panel, so it must be hidden.
        encounterFrame.instance)
    _G.EncounterJournal_HideCreatures()
end

function AdventureGuideInstances:ShowNativeEncounterContent()
    local journal, encounterFrame, infoFrame = GetEncounterFrames()
    if not infoFrame then
        return
    end

    -- Blizzard shows the lore on instance pages (DisplayInstance) and hides it on boss
    -- pages (ClearDetails). Restore that even while hidden, so reopening is correct.
    if encounterFrame.instance then
        encounterFrame.instance:SetShown(journal.encounterID == nil)
    end

    if not journal:IsShown() or not encounterFrame:IsShown() then
        return
    end

    self:ShowNativeDifficultyByCurrentTab()

    local model, overview, details = infoFrame.model, infoFrame.overviewScroll, infoFrame.detailsScroll
    SetFramesShown(true,
        infoFrame.BG, infoFrame.leftShadow, model and model.dungeonBG, overview and overview.child,
        details and details.child, encounterFrame.overviewFrame, encounterFrame.infoFrame)

    -- Blizzard's SetTab restores the selected tab's own frames, title and shadows.
    local hasVisibleNativeFrame = (overview and overview:IsShown()) or (details and details:IsShown())
        or (infoFrame.LootContainer and infoFrame.LootContainer:IsShown()) or (model and model:IsShown())
    if not hasVisibleNativeFrame then
        _G.EncounterJournal_SetTab(infoFrame.tab or infoFrame.overviewTab:GetID())
    end
end

function AdventureGuideInstances:SetPanelHeader(instanceName, achievementCount, categoryID, totalCount)
    local panel = self.customPanel
    if not panel then
        return
    end

    local displayName = instanceName
    if type(displayName) ~= "string" or displayName == "" then
        displayName = _G.ACHIEVEMENTS or "Achievements"
    end

    -- No count while rows are loading, so the header never reports a false zero.
    panel.HeaderText:SetText(achievementCount and format("%s (%d)", displayName, achievementCount) or displayName)

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

function AdventureGuideInstances:SetPanelEmptyState(message, hideList)
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

function AdventureGuideInstances:EnsureAchievementListView()
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

function AdventureGuideInstances:PopulateAchievementRows(rows, instanceID)
    local panel = self.customPanel
    if not panel then
        return
    end

    -- Navigation hooks refresh several times per click. When the same rows are
    -- already listed, only re-read the visible rows' completion state.
    if panel.displayedRows == rows then
        panel.ScrollBox:ReinitializeFrames()
        return
    end
    panel.displayedRows = rows
    panel.ScrollBox:SetDataProvider(_G.CreateDataProvider(rows))

    if panel.lastInstanceID ~= instanceID and panel.ScrollBox.ScrollToBegin then
        panel.ScrollBox:ScrollToBegin()
    end
    panel.lastInstanceID = instanceID
end

----------------------------------------------------------------------------------------
-- Public UI Methods
----------------------------------------------------------------------------------------
function AdventureGuideInstances:IsSupportedContentTab(tabID)
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

function AdventureGuideInstances:UpdateCustomTabAvailability()
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

function AdventureGuideInstances:ActivateCustomTab()
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

function AdventureGuideInstances:DeactivateCustomTab()
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

    if not self:IsCompletionVisible() then
        self:CancelPendingInstanceRowBuilds()
    end

    self:ShowNativeEncounterContent()
end

function AdventureGuideInstances:RefreshCustomTabContent()
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
        self:SetPanelHeader()
        self:SetPanelEmptyState(EMPTY_STATE_NO_INSTANCE, true)
        return
    end
    self.currentInstanceID = instanceID

    local instanceName, _, _, _, _, _, _, _, _, _, _, isRaid = EJ_GetInstanceInfo(instanceID)
    local rows, categoryID, isPending = self:GetCachedInstanceAchievementRows(instanceID)
    self:EnsureBossFilterState(instanceID)
    self:SetupBossFilterDropdown()
    self:UpdateBossFilterDropdownText()

    if type(rows) ~= "table" then
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
            -- The no-timer path can complete and render inside the callback.
            if self:GetCachedInstanceAchievementRows(instanceID) then
                return
            end
        end

        self:SetPanelHeader(instanceName)
        self:SetPanelEmptyState(EMPTY_STATE_LOADING, true)
        return
    end

    self.pendingRowRefreshInstanceID = nil
    local totalCount = #rows
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

    if not self:EnsureAchievementListView() then
        if not self:IsAchievementUIReady() then
            if not self.pendingAchievementUILoadFromTab then
                self.pendingAchievementUILoadFromTab = true
                _G.C_Timer.After(0, function()
                    self.pendingAchievementUILoadFromTab = false
                    if not self.customTabActive then
                        return
                    end
                    local loaded = self:EnsureAchievementUILoaded()
                    if self.customTabActive and self.currentInstanceID == instanceID then
                        if loaded then
                            self:RefreshCustomTabContent()
                        else
                            self:SetPanelEmptyState(EMPTY_STATE_NO_UI, true)
                        end
                    end
                end)
            end

            self:SetPanelEmptyState(EMPTY_STATE_LOADING, true)
            return
        end

        self:SetPanelEmptyState(EMPTY_STATE_NO_SCROLL, true)
        return
    end

    self:SetPanelEmptyState(nil, false)
    self:PopulateAchievementRows(filteredRows, instanceID)
end

function AdventureGuideInstances:OnAchievementsTabClicked()
    if not self.customTabAvailable then
        return
    end

    if type(PlaySound) == "function" and type(SOUNDKIT) == "table" and SOUNDKIT.IG_ABILITY_PAGE_TURN then
        PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN)
    end

    self:ActivateCustomTab()
end
