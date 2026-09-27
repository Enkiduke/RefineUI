-- Dungeon/Raid list controls. Blizzard still owns the cards and their initializer.
local _, RefineUI = ...
local Module = RefineUI:GetModule("AdventureGuideInstances")
if not Module then return end

local Data = RefineUI.InstanceCompletion
local TYPES = Module.COMPLETION_BADGES

function Module:IsGuideInstanceListVisible()
    local journal = _G.EncounterJournal
    local list = journal and journal.instanceSelect
    return journal and journal:IsShown() and list and list:IsShown()
        and list.ScrollBox and list.ScrollBox:IsShown()
        and self:IsSupportedContentTab(journal.selectedTab)
end

function Module:AreAllGuideTypesSelected()
    for _, entry in ipairs(TYPES) do
        if not self.guideCollectionTypes[entry.key] then return false end
    end
    return true
end

function Module:GuideListNeedsSummaries()
    if not next(self.guideCollectionTypes) then return false end
    return self.guideSortKey ~= nil or not self:AreAllGuideTypesSelected()
end

-- A partial loot catalog is shown with its known counts but is not fully assessed.
local function IsAssessed(summary, key)
    return Module:IsCompletionReady(summary, key) and not (summary.partial and key ~= "achievements")
end

-- Unknown catalogs stay visible until their type can be assessed. A match means
-- at least one selected category has a reward, collected or not.
function Module:GuideInstancePassesFilter(summary)
    if not next(self.guideCollectionTypes) then return false end
    if not summary then return true end
    for _, entry in ipairs(TYPES) do
        if self.guideCollectionTypes[entry.key] then
            local count = summary.instance[entry.key]
            if not IsAssessed(summary, entry.key) or count.unknown > 0 or count.total > 0 then return true end
        end
    end
    return false
end

function Module:GetGuideSortRate(summary)
    if not self.guideSortKey or not summary then return nil end
    local earned, total = 0, 0
    for _, entry in ipairs(TYPES) do
        if self.guideCollectionTypes[entry.key] then
            if not IsAssessed(summary, entry.key) then return nil end
            local count = summary.instance[entry.key]
            if count.unknown > 0 then return nil end
            earned, total = earned + count.earned, total + count.total
        end
    end
    if total == 0 then return nil end
    return earned / total
end

function Module:GetGuideBaseRows()
    local journal = _G.EncounterJournal
    local raid = journal.selectedTab == journal.raidsTab:GetID()
    local tier = EJ_GetCurrentTier()
    local scope = tostring(tier) .. ":" .. tostring(raid) .. ":" .. tostring(self.guideAllExpansions)
    if self._guideBaseScope == scope then return self._guideBaseRows, scope end

    local rows, seen = {}, {}
    local function AddCurrentTier()
        local index = 1
        while true do
            local instanceID, name, description, _, buttonImage, _, _, _, link, _, mapID = EJ_GetInstanceByIndex(index, raid)
            if not instanceID then break end
            if not seen[instanceID] then
                seen[instanceID] = true
                rows[#rows + 1] = {
                    instanceID = instanceID, name = name, description = description,
                    buttonImage = buttonImage, link = link, mapID = mapID,
                    order = #rows + 1,
                }
            end
            index = index + 1
        end
    end

    if self.guideAllExpansions then
        -- The last tier can be a current-season alias. Deduplicate its instances.
        local ok = pcall(function()
            for index = EJ_GetNumTiers(), 1, -1 do
                EJ_SelectTier(index)
                AddCurrentTier()
            end
        end)
        local restored = EJ_GetCurrentTier() == tier or pcall(EJ_SelectTier, tier)
        if not ok or not restored then return nil end
    else
        AddCurrentTier()
    end
    self._guideBaseRows, self._guideBaseScope = rows, scope
    return rows, scope
end

function Module:RefreshGuideInstanceList()
    if not self:IsGuideInstanceListVisible() then return end
    local list = _G.EncounterJournal.instanceSelect
    local custom = self.guideAllExpansions or self.guideSortKey or not self:AreAllGuideTypesSelected()
    if not custom then
        self.guideListEmpty:Hide()
        return -- Blizzard's provider is already installed.
    end
    local baseRows = self:GetGuideBaseRows()
    if not baseRows then return end
    local rows = {}
    for _, row in ipairs(baseRows) do
        local state = Data.summaries[row.instanceID]
        if self:GuideInstancePassesFilter(state and state.summary) then
            rows[#rows + 1] = row
        end
    end
    if self.guideSortKey then
        local scores = {}
        for _, row in ipairs(rows) do
            local state = Data.summaries[row.instanceID]
            scores[row.instanceID] = self:GetGuideSortRate(state and state.summary)
        end
        table.sort(rows, function(a, b)
            local left, right = scores[a.instanceID], scores[b.instanceID]
            if left == nil then return right == nil and a.order < b.order or false end
            if right == nil then return true end
            if left ~= right then
                if self.guideSortDescending then return left > right end
                return left < right
            end
            return a.order < b.order
        end)
    end
    local provider = CreateDataProvider()
    for _, row in ipairs(rows) do provider:Insert(row) end
    list.ScrollBox:SetDataProvider(provider, ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
    local emptyText = not next(self.guideCollectionTypes) and "Select a collection type to show instances."
        or "No instances have rewards in the selected types."
    self.guideListEmpty:SetText(emptyText)
    self.guideListEmpty:SetShown(#rows == 0)
    if self.guideAllExpansions then
        list.bg:Hide()
        list.evergreenBg:Show()
    else
        list.evergreenBg:Hide()
        list.bg:Show()
    end
end

function Module:ScheduleGuideInstanceListRefresh()
    if self._guideListRefreshTimer or not self:IsGuideInstanceListVisible() then return end
    -- Summary callbacks can arrive together. Re-sort on the next frame so every
    -- newly completed summary joins the known group without rebuilding once per callback.
    self._guideListRefreshTimer = C_Timer.NewTimer(0, function()
        self._guideListRefreshTimer = nil
        self:RefreshGuideInstanceList()
    end)
end

function Module:OnGuideSummaryUpdated(summary)
    if not summary or not summary.instanceID or not self:GuideListNeedsSummaries()
        or not self:IsGuideInstanceListVisible() then return end
    local passes = self:GuideInstancePassesFilter(summary)
    local rate = self:GetGuideSortRate(summary)
    local previous = self._guideSummarySortState[summary.instanceID]
    if previous then
        if previous.passes == passes and previous.rate == rate then return end
        previous.passes, previous.rate = passes, rate
    else
        self._guideSummarySortState[summary.instanceID] = { passes = passes, rate = rate }
    end
    self:ScheduleGuideInstanceListRefresh()
end

function Module:UpdateGuideListControls()
    local journal = _G.EncounterJournal
    local show = journal and journal:IsShown() and journal.instanceSelect:IsShown()
        and self:IsSupportedContentTab(journal.selectedTab)
    self.guideSortDropdown:SetShown(show == true)
    self.guideFilterDropdown:SetShown(show == true)
    if not show then self.guideListEmpty:Hide() end
    if self.guideAllExpansions and show then
        journal.instanceSelect.bg:Hide()
        journal.instanceSelect.evergreenBg:Show()
    end
end

function Module:GetGuideSortDropdownText()
    if not self.guideSortKey then return "Sort: Default" end
    return self.guideSortDescending and "Sort: Most Complete" or "Sort: Least Complete"
end

function Module:GetGuideFilterDropdownText()
    local count, label = 0, nil
    for _, entry in ipairs(TYPES) do
        if self.guideCollectionTypes[entry.key] then count, label = count + 1, entry.label end
    end
    return count == #TYPES and "Filter: All types"
        or count == 0 and "Filter: None"
        or count == 1 and "Filter: " .. label
        or "Filter: " .. count .. " types"
end

function Module:UpdateGuideListDropdownText()
    if self.guideSortDropdown:GetMenuDescription() then self.guideSortDropdown:Update() end
    if self.guideFilterDropdown:GetMenuDescription() then self.guideFilterDropdown:Update() end
end

function Module:GuideListSelectionChanged()
    self._guideSummarySortState = {}
    self:UpdateGuideListDropdownText()
    if self:IsGuideInstanceListVisible() then
        EncounterJournal_ListInstances()
        local scroll = _G.EncounterJournal.instanceSelect.ScrollBox
        if scroll.GetFrames then
            for _, button in ipairs(scroll:GetFrames()) do
                if button.RefineExpansionSummary then
                    self:RenderExpansionCompletion(button, button.RefineExpansionSummary)
                end
            end
        end
    end
end

function Module:SelectGuideAllAnchorTier()
    -- Blizzard checks the selected tier before our All provider is installed.
    -- Keep both content tabs available even if the previous tier has only one.
    if EJ_GetInstanceByIndex(1, false) and EJ_GetInstanceByIndex(1, true) then return end
    local previousTier = EJ_GetCurrentTier()
    for tier = EJ_GetNumTiers(), 1, -1 do
        EJ_SelectTier(tier)
        if EJ_GetInstanceByIndex(1, false) and EJ_GetInstanceByIndex(1, true) then return end
    end
    EJ_SelectTier(previousTier)
end

function Module:SetupGuideExpansionDropdown()
    local journal = _G.EncounterJournal
    if not journal or not self:IsSupportedContentTab(journal.selectedTab) then return end
    local dropdown = journal.instanceSelect.ExpansionDropdown
    dropdown:SetupMenu(function(_, root)
        root:SetTag("MENU_EJ_EXPANSION")
        root:CreateRadio("All", function() return self.guideAllExpansions end, function()
            self.guideAllExpansions = true
            self:SelectGuideAllAnchorTier()
            self._guideBaseScope = nil
            EncounterJournal_ListInstances()
        end)
        for tier = 1, EJ_GetNumTiers() do
            local selectedTier = tier
            root:CreateRadio(EJ_GetTierInfo(tier), function()
                return not self.guideAllExpansions and EJ_GetCurrentTier() == selectedTier
            end, function()
                self.guideAllExpansions = false
                self._guideBaseScope = nil
                EncounterJournal_ExpansionDropdown_Select(journal, selectedTier)
            end)
        end
    end)
end

function Module:InstallGuideInstanceList()
    if self._guideInstanceListInstalled then return end
    local journal = _G.EncounterJournal
    local list = journal and journal.instanceSelect
    if not list or not list.ExpansionDropdown or not list.ScrollBox then return end
    self._guideInstanceListInstalled = true
    self.guideCollectionTypes = {}
    for _, entry in ipairs(TYPES) do self.guideCollectionTypes[entry.key] = true end
    self.guideSortKey, self.guideSortDescending = nil, true
    self._guideSummarySortState = {}

    self.guideSortDropdown = CreateFrame("DropdownButton", nil, list, "WowStyle1DropdownTemplate")
    self.guideSortDropdown:SetWidth(182)
    self.guideSortDropdown:SetPoint("RIGHT", list.ExpansionDropdown, "LEFT", -8, 0)
    self.guideSortDropdown:SetSelectionText(function() return self:GetGuideSortDropdownText() end)
    self.guideSortDropdown:SetupMenu(function(_, root)
        root:SetTag("MENU_REFINE_EJ_SORT")
        root:CreateTitle("Completion order")
        root:CreateRadio("Default", function() return self.guideSortKey == nil end, function()
            self.guideSortKey = nil
            self:GuideListSelectionChanged()
        end)
        root:CreateRadio("Least Complete", function()
            return self.guideSortKey == "completion" and not self.guideSortDescending
        end, function()
            self.guideSortKey, self.guideSortDescending = "completion", false
            self:GuideListSelectionChanged()
        end)
        root:CreateRadio("Most Complete", function()
            return self.guideSortKey == "completion" and self.guideSortDescending
        end, function()
            self.guideSortKey, self.guideSortDescending = "completion", true
            self:GuideListSelectionChanged()
        end)
    end)

    self.guideFilterDropdown = CreateFrame("DropdownButton", nil, list, "WowStyle1DropdownTemplate")
    self.guideFilterDropdown:SetWidth(156)
    self.guideFilterDropdown:SetPoint("RIGHT", self.guideSortDropdown, "LEFT", -8, 0)
    self.guideFilterDropdown:SetSelectionText(function() return self:GetGuideFilterDropdownText() end)
    self.guideFilterDropdown:SetupMenu(function(_, root)
        root:SetTag("MENU_REFINE_EJ_COLLECTION_FILTER")
        root:CreateTitle("Collection types")
        root:CreateButton("Select all types", function()
            for _, entry in ipairs(TYPES) do self.guideCollectionTypes[entry.key] = true end
            self:GuideListSelectionChanged()
        end)
        root:CreateButton("Clear types", function()
            for _, entry in ipairs(TYPES) do self.guideCollectionTypes[entry.key] = nil end
            self:GuideListSelectionChanged()
        end)
        root:CreateDivider()
        for _, entry in ipairs(TYPES) do
            local key, label = entry.key, entry.label
            root:CreateCheckbox(label, function() return self.guideCollectionTypes[key] == true end, function()
                if self.guideCollectionTypes[key] then
                    self.guideCollectionTypes[key] = nil
                else
                    self.guideCollectionTypes[key] = true
                end
                self:GuideListSelectionChanged()
            end)
        end
    end)
    self.guideListEmpty = list:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    self.guideListEmpty:SetPoint("CENTER", list.ScrollBox, "CENTER", 0, 0)
    self.guideListEmpty:Hide()

    RefineUI:HookOnce(self:BuildKey("GuideList", "ExpansionMenu"), "EncounterJournal_SetupExpansionDropdown",
        function() self:SetupGuideExpansionDropdown() end)
    RefineUI:HookOnce(self:BuildKey("GuideList", "Instances"), "EncounterJournal_ListInstances",
        function() self:UpdateGuideListControls(); self:RefreshGuideInstanceList() end)
    -- EncounterJournal.TabSet is handled by OnEncounterJournalTabSet; EventRegistry
    -- keeps one callback per owner, so a second registration would replace it.
    self:UpdateGuideListDropdownText()
    self:UpdateGuideListControls()
    self:SetupGuideExpansionDropdown()
    self:RefreshGuideInstanceList()
end
