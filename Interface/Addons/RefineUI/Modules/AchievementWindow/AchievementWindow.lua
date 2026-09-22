local _, RefineUI = ...
local Window = RefineUI:RegisterModule("AchievementWindow")

-- Keep Blizzard category IDs and achievement indices intact. The extra rows are
-- presentation-only filters, never synthetic IDs passed to achievement APIs.
local function IsPersonalView()
    -- Blizzard's achievementFunctions is local, so use its public tab state.
    return AchievementFrame.selectedTab == 1
        and AchievementFrameTab_OnClick ~= AchievementFrameComparisonTab_OnClick
end
Window.IsPersonalView = IsPersonalView

local function IsDungeonCategory(categoryID)
    local seen = {}
    while type(categoryID) == "number" and categoryID > 0 and not seen[categoryID] do
        if categoryID == 168 then return true end
        seen[categoryID] = true
        local _, parent = GetCategoryInfo(categoryID)
        categoryID = parent
    end
    return false
end

function Window:BuildGroups()
    if self.groups then return end
    local groups = {}
    for instanceID, instance in pairs(RefineUI.AchievementInstanceData) do
        for _, achievementID in ipairs(instance.ids) do
            if C_AchievementInfo.IsValidAchievement(achievementID) then
                local categoryID = GetAchievementCategory(achievementID)
                if IsDungeonCategory(categoryID) then
                    local group = groups[categoryID]
                    if not group then
                        group = { instances = {}, byID = {} }
                        groups[categoryID] = group
                    end
                    local entry = group.byID[instanceID]
                    if not entry then
                        local name = EJ_GetInstanceInfo and EJ_GetInstanceInfo(instanceID)
                        entry = { instanceID = instanceID, name = name or instance.name, ids = {} }
                        group.byID[instanceID] = entry
                        group.instances[#group.instances + 1] = entry
                    end
                    entry.ids[achievementID] = true
                end
            end
        end
    end
    for _, group in pairs(groups) do
        table.sort(group.instances, function(a, b)
            if a.name == b.name then return a.instanceID < b.instanceID end
            return a.name < b.name
        end)
    end
    self.groups = groups
end

function Window:GetGroup(categoryID)
    self:BuildGroups()
    local group = self.groups[categoryID]
    -- Categories already dedicated to one instance need no extra nesting.
    return group and #group.instances > 1 and group or nil
end

function Window:SelectInstance(entry)
    self.revealID = nil
    self.activeInstance = entry
    local scrollBox = AchievementFrameCategories.ScrollBox
    local scrollPercentage = scrollBox:GetScrollPercentage()
    AchievementFrameCategories_UpdateDataProvider()
    scrollBox:SetScrollPercentage(scrollPercentage, ScrollBoxConstants.NoScrollInterpolation)
    AchievementFrameAchievements_UpdateDataProvider()
    AchievementFrameAchievements.ScrollBox:ScrollToBegin()
    if self.QueueSearch then self:QueueSearch() end
end

function Window:OnCategorySelected(elementData)
    if self.almostPanel and self.almostPanel:IsShown() then
        self.almostPanel:Hide()
        if elementData.id == "summary" then AchievementFrame_ShowSubFrame(AchievementFrameSummary) end
    end
    self.currentCategory = elementData.id
    self.revealID = nil
    if not IsPersonalView() then
        self.expandedCategory, self.activeInstance = nil, nil
        return
    end
    self.activeInstance = nil
    self.expandedCategory = not self.collapseNext and self:GetGroup(elementData.id) and elementData.id or nil
    AchievementFrameCategories_UpdateDataProvider()
    AchievementFrameCategories.ScrollBox:ScrollToElementDataByPredicate(function(row)
        return row.id == elementData.id and not row.refineInstanceRow
    end, self.expandedCategory and ScrollBoxConstants.AlignBegin or ScrollBoxConstants.AlignNearest)
    -- Also required when clicking the already-selected category or following a
    -- search/chat link into the current category: Blizzard skips that refresh.
    if type(elementData.id) == "number" then
        AchievementFrameAchievements_UpdateDataProvider()
    end
    if self.QueueSearch then self:QueueSearch() end
end

function Window:UpdateCategories()
    self:UpdateResetButton()
    if not IsPersonalView() then
        self.expandedCategory, self.activeInstance = nil, nil
        return
    end
    local categoryID = self.expandedCategory
    local group = categoryID and self:GetGroup(categoryID)
    local scrollBox = AchievementFrameCategories.ScrollBox
    local source = scrollBox:GetDataProvider()
    if not source then return end
    local provider = CreateDataProvider()
    for _, element in source:Enumerate() do
        provider:Insert(element)
        if element.id == "summary" and self.ShowAlmostCompleted then
            provider:Insert({ id = "summary", parent = "summary", isChild = true, refineAlmostRow = true })
        end
        if group and element.id == categoryID then
            provider:Insert({ id = categoryID, parent = categoryID, isChild = true,
                refineInstanceRow = true, name = ALL or "All", selected = not self.activeInstance })
            for _, entry in ipairs(group.instances) do
                provider:Insert({ id = categoryID, parent = categoryID, isChild = true,
                    refineInstanceRow = true, instance = entry, name = entry.name,
                    selected = self.activeInstance == entry })
            end
        end
    end
    scrollBox:SetDataProvider(provider, ScrollBoxConstants.RetainScrollPosition)
end

function Window:DecorateCategory(frame)
    local element = frame:GetElementData()
    if not frame.refineOriginalClick then
        frame.refineOriginalClick = frame.Button:GetScript("OnClick")
        frame.Button:SetScript("OnClick", function(button, ...)
            local data = frame:GetElementData()
            if data.refineAlmostRow and IsPersonalView() then
                self:ShowAlmostCompleted()
            elseif data.refineInstanceRow and IsPersonalView() then
                self:SelectInstance(data.instance)
            else
                self.collapseNext = self.expandedCategory == data.id and not self.activeInstance
                frame.refineOriginalClick(button, ...)
                self.collapseNext = nil
            end
        end)
    end
    if not IsPersonalView() then return end
    if element.refineAlmostRow then
        frame.Button.Label:SetText("Almost Completed")
        frame.Button.name = "Almost Completed"
        frame.Button.showTooltipFunc = nil
        frame:UpdateSelectionState(self.almostPanel and self.almostPanel:IsShown())
    elseif element.id == "summary" and self.almostPanel and self.almostPanel:IsShown() then
        frame:UpdateSelectionState(false)
    elseif element.refineInstanceRow then
        frame.Button:SetWidth(ACHIEVEMENTUI_CATEGORIESWIDTH - 39)
        frame.Button.Label:SetFontObject("GameFontHighlightSmall")
        frame.Button.Label:SetText(element.name)
        frame.Button.name = element.name
        local total, completed = 0, 0
        if element.instance then
            for achievementID in pairs(element.instance.ids) do
                total = total + 1
                if self:IsComplete(achievementID) then completed = completed + 1 end
            end
            frame.Button.numAchievements = total
            frame.Button.numCompleted = completed
            frame.Button.numCompletedText = completed .. "/" .. total
        elseif self:GetSettings().CharacterCompletion then
            for _, row in ipairs(self:GetCategoryRows(element.id)) do
                total = total + 1
                if self:IsComplete(row.id) then completed = completed + 1 end
            end
            frame.Button.numAchievements = total
            frame.Button.numCompleted = completed
            frame.Button.numCompletedText = completed .. "/" .. total
        end
        frame:UpdateSelectionState(element.selected)
    elseif self:GetGroup(element.id) then
        local name = GetCategoryInfo(element.id)
        frame.Button.Label:SetText((self.expandedCategory == element.id and "- " or "+ ") .. name)
        if self.expandedCategory == element.id then frame:UpdateSelectionState(false) end
    end
end

function Window:FilterAchievements()
    self:UpdateResetButton()
    if self.emptyText then self.emptyText:Hide() end
    if not IsPersonalView() then return end
    local scrollBox = AchievementFrameAchievements.ScrollBox
    local source = scrollBox:GetDataProvider()
    if not source then return end
    local rows = {}
    for _, element in source:Enumerate() do
        if self.activeInstance and element.category ~= self.expandedCategory then return end
        rows[#rows + 1] = element
    end
    local category = self:GetSelectedCategory()
    if (self:GetSettings().CharacterCompletion or self.revealID) and type(category) == "number" then
        rows = self:GetCategoryRows(category)
    end
    local provider = self:ProcessRows(rows)
    scrollBox:SetDataProvider(provider)
    if provider:GetSize() == 0 then
        if not self.emptyText then
            self.emptyText = AchievementFrameAchievements:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            self.emptyText:SetPoint("TOP", 0, -24)
            self.emptyText:SetWidth(440)
            self.emptyText:SetText("No achievements match the selected filters.")
        end
        self.emptyText:Show()
    end
end

function Window:Install()
    if self.installed or not AchievementFrameCategories or not AchievementFrameAchievements then return end
    if not AchievementFrameCategories.ScrollBox or not AchievementFrameAchievements.ScrollBox
        or not ScrollUtil or not ScrollUtil.AddInitializedFrameCallback
        or type(AchievementFrameCategories_SelectElementData) ~= "function" then return end
    self.installed = true
    self:InstallFilterMenu()
    self:InstallSearch()
    ScrollUtil.AddInitializedFrameCallback(AchievementFrameCategories.ScrollBox, function(_, frame)
        self:DecorateCategory(frame)
    end, self)
    hooksecurefunc("AchievementFrameCategories_UpdateDataProvider", function() self:UpdateCategories() end)
    hooksecurefunc("AchievementFrameCategories_SelectElementData", function(element) self:OnCategorySelected(element) end)
    hooksecurefunc("AchievementFrameAchievements_UpdateDataProvider", function() self:FilterAchievements() end)
    hooksecurefunc("AchievementFrame_SetFilter", function()
        self.revealID = nil
        self:QueueSearch()
    end)
    -- The native dropdown uses a local setter and calls ForceUpdate directly.
    hooksecurefunc("AchievementFrameAchievements_ForceUpdate", function()
        if not IsPersonalView() then return end
        if self.revealID then
            self.revealID = nil
            AchievementFrameAchievements_UpdateDataProvider()
        end
        self:QueueSearch()
    end)
    hooksecurefunc("AchievementFrame_SelectAchievement", function(id)
        if not IsPersonalView() or self.revealing then return end
        local displayed = AchievementFrame_FindDisplayedAchievement(id)
        if not displayed or not C_AchievementInfo.IsValidAchievement(displayed) then return end
        if not self:MatchesFilters(displayed) then
            self.revealing = true
            self.revealID = displayed
            AchievementFrameAchievements_UpdateDataProvider()
            AchievementFrame_SelectAndScrollToAchievementId(AchievementFrameAchievements.ScrollBox, displayed)
            self.revealing = nil
        end
    end)
    -- Blizzard returns early for links into the already-selected category.
    -- Clear the filter before its caller searches the provider for that link.
    hooksecurefunc("AchievementFrame_UpdateAndSelectCategory", function()
        if IsPersonalView() and self.activeInstance then
            self.activeInstance = nil
            AchievementFrameCategories_UpdateDataProvider()
            AchievementFrameAchievements_UpdateDataProvider()
        end
    end)
    hooksecurefunc("AchievementFrameBaseTab_OnClick", function()
        if self.almostPanel then self.almostPanel:Hide() end
        self.expandedCategory, self.activeInstance = nil, nil
        AchievementFrameCategories_UpdateDataProvider()
        if IsPersonalView() and AchievementFrameAchievements:IsShown() then
            AchievementFrameAchievements_UpdateDataProvider()
        end
    end)
    if AchievementFrame:IsShown() then AchievementFrameCategories_UpdateDataProvider() end
end

function Window:OnEnable()
    RefineUI:RegisterEventCallback("ADDON_LOADED", function(_, name)
        if name == "Blizzard_AchievementUI" then self:Install() end
    end, "AchievementWindow:ADDON_LOADED")
    RefineUI:RegisterEventCallback("ITEM_DATA_LOAD_RESULT", function(_, itemID)
        if self.almostPendingItems and self.almostPendingItems[itemID] == true then
            self.almostPendingItems[itemID] = "requested"
            self:RenderAlmostCompleted()
        end
        if self.pendingRewardItems and self.pendingRewardItems[itemID] == true then
            self.pendingRewardItems[itemID] = "requested"
            if self.installed then self:RefreshFilters() end
        end
    end, "AchievementWindow:RewardItems")
    for _, event in ipairs({"ACHIEVEMENT_EARNED", "CRITERIA_UPDATE", "RECEIVED_ACHIEVEMENT_LIST"}) do
        RefineUI:RegisterEventCallback(event, function(_, achievementID)
            if self.InvalidateAlmostCompleted then self:InvalidateAlmostCompleted(event, achievementID) end
            self.searchCacheDirty = true
            if self.installed then
                if event == "ACHIEVEMENT_EARNED" then self:RefreshFilters()
                else self:QueueSearch() end
            end
        end, "AchievementWindow:" .. event)
    end
    self:Install()
end
