local _, RefineUI = ...
local Window = RefineUI:GetModule("AchievementWindow")
local function Fold(text) return strlower(text or "") end

function Window:BuildSearchCache()
    if self.cacheTicker then return end
    if self.searchCache and not self.searchCacheDirty then return end
    self.searchCacheDirty = false
    self.searchCache = {}
    local categories = GetCategoryList()
    local categoryIndex, index, count = 1, 1, nil
    local pending, seen = nil, {}
    -- Count each criteria read as work too; a very large meta achievement cannot
    -- monopolize a tick. This index contains localized text, not completion state.
    self.cacheTicker = C_Timer.NewTicker(0.02, function(ticker)
        if InCombatLockdown() then return end
        for _ = 1, 40 do
            if pending then
                if pending.criterion <= pending.count then
                    local text = GetAchievementCriteriaInfo(pending.row.id, pending.criterion)
                    pending.text[#pending.text + 1] = text or ""
                    pending.criterion = pending.criterion + 1
                else
                    pending.row.text = Fold(table.concat(pending.text, "\n"))
                    self.searchCache[#self.searchCache + 1] = pending.row
                    pending = nil
                end
            else
                local category = categories[categoryIndex]
                if not category then
                    ticker:Cancel()
                    self.cacheTicker = nil
                    self:QueueSearch()
                    return
                end
                count = count or GetCategoryNumAchievements(category)
                if index > count then
                    categoryIndex, index, count = categoryIndex + 1, 1, nil
                else
                    local id, name, _, _, _, _, _, description, _, _, _, guild, _, _, statistic = GetAchievementInfo(category, index)
                    local row = { id = id, category = category, index = index }
                    index = index + 1
                    if id and not guild and not statistic and not seen[id] then
                        seen[id] = true
                        pending = { row = row, text = {name or "", description or ""},
                            criterion = 1, count = GetAchievementNumCriteria(id) or 0 }
                    end
                end
            end
        end
    end)
end

function Window:QueueSearch()
    self.searchGeneration = (self.searchGeneration or 0) + 1
    local generation = self.searchGeneration
    if self.queryTicker then self.queryTicker:Cancel(); self.queryTicker = nil end
    if not self:IsPersonalView() then return end
    if not self.searchBox:HasFocus() and not AchievementFrame.SearchResults:IsShown() then return end
    local query = self.searchBox:GetText()
    if #query < (MIN_CHARACTER_SEARCH or 3) then
        self.searchRows, self.searchQuery = nil, nil
        return
    end
    -- Debounce typing, then evaluate cached text and native matches in batches.
    C_Timer.After(0.15, function()
        if generation ~= self.searchGeneration or not self:IsPersonalView() then return end
        self:BuildSearchCache()
        local cache = self.searchCache
        local nativeCount = self.searchBox.fullSearchFinished and GetNumFilteredAchievements() or 0
        local cursor, nativeCursor = 1, 1
        local rows, seen, needle = {}, {}, Fold(query)
        self.queryTicker = C_Timer.NewTicker(0.02, function(ticker)
            if generation ~= self.searchGeneration or not self:IsPersonalView()
                or self.searchBox:GetText() ~= query then
                ticker:Cancel()
                return
            end
            for _ = 1, 100 do
                local row
                if nativeCursor <= nativeCount then
                    local id = GetFilteredAchievementID(nativeCursor)
                    nativeCursor = nativeCursor + 1
                    if id and C_AchievementInfo.IsValidAchievement(id) then
                        local _, _, _, _, _, _, _, _, _, _, _, guild, _, _, statistic = GetAchievementInfo(id)
                        if not guild and not statistic then row = { id = id } end
                    end
                elseif cursor <= #cache then
                    -- Cached rows already exclude guild achievements and statistics.
                    local candidate = cache[cursor]
                    cursor = cursor + 1
                    if candidate.text:find(needle, 1, true) then row = candidate end
                else
                    ticker:Cancel()
                    self.queryTicker = nil
                    self.searchRows = self:BuildSortedProvider(rows)
                    self.searchQuery = query
                    self:RenderSearchPreview()
                    if AchievementFrame.SearchResults:IsShown() then self:RenderFullSearch() end
                    return
                end
                if row and not seen[row.id] then
                    seen[row.id] = true
                    -- Do reward/credit lookups within the batch budget too.
                    -- Chat-link reveal exceptions do not apply to search.
                    local prepared = self:PrepareRow(row, #rows + 1, true)
                    if prepared then rows[#rows + 1] = prepared end
                end
            end
        end)
    end)
end

function Window:GetSearchResults()
    if not self:IsPersonalView() or self.searchQuery ~= self.searchBox:GetText() then return nil end
    return self.searchRows
end

function Window:RenderSearchPreview()
    if not self:IsPersonalView() or not self.searchBox:HasFocus() then return end
    if #self.searchBox:GetText() < (MIN_CHARACTER_SEARCH or 3) then return end
    local results = self:GetSearchResults()
    local container = self.searchBox.SearchPreviewContainer
    local count, last = results and results:GetSize() or 0, nil
    for index, button in ipairs(container.searchPreviews) do
        local row = results and results:Find(index)
        button.achievementID = row and row.id or nil
        if row then
            local _, name, _, _, _, _, _, _, _, icon = GetAchievementInfo(row.id)
            button.Name:SetText(name)
            button.Icon:SetTexture(icon)
            button:Show()
            last = button
        else
            button:Hide()
        end
    end
    local all = container.ShowAllSearchResults
    -- The native Show All button also provides a visible empty/indexing state.
    all:SetShown(count > #container.searchPreviews or count == 0)
    if all:IsShown() then
        all.Text:SetText(count == 0 and (self.cacheTicker and "Indexing achievement criteria…"
            or not results and "Searching achievements…" or "No achievements match the selected filters.")
            or string.format(ENCOUNTER_JOURNAL_SHOW_SEARCH_RESULTS, count))
        last = all
    end
    if last then
        container.BorderAnchor:SetPoint("BOTTOM", last, "BOTTOM", 0, -5)
        container.Background:Hide()
        container:Show()
    end
    AchievementFrame_SetSearchPreviewSelection(count > 0 and 1 or #container.searchPreviews + 1)
end

function Window:InitSearchRow(button, row)
    local _, name, _, _, _, _, _, _, _, icon = GetAchievementInfo(row.id)
    button.achievementID = row.id
    button.Name:SetText(name)
    button.Icon:SetTexture(icon)
    button.ResultType:SetText(self:IsComplete(row.id) and ACHIEVEMENTFRAME_FILTER_COMPLETED or ACHIEVEMENTFRAME_FILTER_INCOMPLETE)
    button.Path:SetText(RefineUI.InstanceAchievements:GetCategoryPath(GetAchievementCategory(row.id)))
end

function Window:RenderFullSearch()
    if not self:IsPersonalView() then return end
    local results = self:GetSearchResults()
    local rows = {}
    if results then
        for index, row in results:Enumerate() do rows[index] = { id = row.id, refineSearch = true } end
    end
    local provider = CreateDataProvider(rows)
    AchievementFrame.SearchResults.ScrollBox:SetDataProvider(provider)
    local title = string.format(ENCOUNTER_JOURNAL_SEARCH_RESULTS, self.searchBox:GetText(), provider:GetSize())
    if provider:GetSize() == 0 then
        title = title .. " — " .. (self.cacheTicker and "Indexing criteria…" or not results and "Searching…" or "No achievements match the selected filters.")
    end
    AchievementFrame.SearchResults.TitleText:SetText(title)
end

function Window:InstallSearch()
    local scroll = AchievementFrame.SearchResults.ScrollBox
    -- Keep Blizzard's template and its native click handler. Its default
    -- initializer requires a native search index, so supplemental ID rows use
    -- this public template callback instead of spoofing a global search API.
    scroll:GetView():SetElementInitializer("AchievementFullSearchResultsButtonTemplate", function(button, row)
        if row.refineSearch and self:IsPersonalView() then self:InitSearchRow(button, row)
        else button:Init(row) end
    end)
    self.searchBox:HookScript("OnTextChanged", function() self:QueueSearch() end)
    hooksecurefunc("AchievementFrame_ShowSearchPreviewResults", function()
        self:RenderSearchPreview()
        self:QueueSearch()
    end)
    hooksecurefunc("AchievementFrame_UpdateFullSearchResults", function() self:RenderFullSearch() end)
    hooksecurefunc("AchievementFrame_ShowFullSearch", function()
        if not self:IsPersonalView() then return end
        self:RenderFullSearch()
        AchievementFrame_HideSearchPreview()
        self.searchBox:ClearFocus()
        -- Native code hides the frame when *native* matches are empty, even if
        -- supplemental criteria matches exist. Show the same frame afterward.
        AchievementFrame.SearchResults:Show()
        self:QueueSearch()
    end)
end
