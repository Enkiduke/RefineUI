local _, RefineUI = ...
local Window = RefineUI:GetModule("AchievementWindow")
local REWARD_KINDS = { mount = "mounts", pet = "pets", toy = "toys", transmog = "appearances" }

function Window:GetSettings()
    return RefineUI.Config.AchievementWindow
end

function Window:IsComplete(id)
    local _, _, _, completed, _, _, _, _, _, _, _, _, wasEarnedByMe = GetAchievementInfo(id)
    if self:GetSettings().CharacterCompletion then return wasEarnedByMe == true end
    return completed == true
end

function Window:GetCompletionFilter()
    if AchievementFrameFilters then
        if ACHIEVEMENTUI_SELECTEDFILTER == AchievementFrameFilters[2].func then return "complete" end
        if ACHIEVEMENTUI_SELECTEDFILTER == AchievementFrameFilters[3].func then return "incomplete" end
    end
    return "all"
end

-- Only native item associations are used. A reward's localized prose is never
-- parsed to guess its type. In particular there is no reliable title classifier.
function Window:GetRewardOptions()
    local options = { {"all", "All rewards"}, {"has", "Has reward"}, {"none", "No reward"} }
    if not C_AchievementInfo.GetRewardItemID then return options end
    local function Add(key, label, available)
        if available then options[#options + 1] = { key, label } end
    end
    Add("mount", "Mount", C_MountJournal and C_MountJournal.GetMountFromItem)
    Add("pet", "Pet", C_PetJournal and C_PetJournal.GetPetInfoByItemID)
    Add("toy", "Toy", C_ToyBox and C_ToyBox.GetToyInfo)
    Add("transmog", "Transmog", C_TransmogCollection and C_TransmogCollection.GetItemInfo)
    Add("decor", "Housing Decor", C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByItem
        and Enum and Enum.HousingCatalogEntryType and Enum.HousingCatalogEntryType.Decor)
    return options
end

function Window:MatchesReward(id)
    local mode = self.rewardFilter or "all"
    if mode == "all" then return true end
    local itemID = C_AchievementInfo.GetRewardItemID and C_AchievementInfo.GetRewardItemID(id)
    if itemID == 0 then itemID = nil end
    local text = select(11, GetAchievementInfo(id))
    local has = itemID ~= nil or (type(text) == "string" and text:find("%S") ~= nil)
    if mode == "has" then return has end
    if mode == "none" then return not has end
    if not itemID then return false end
    if C_Item and C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(itemID) then
        self.pendingRewardItems = self.pendingRewardItems or {}
        if not self.pendingRewardItems[itemID] then
            self.pendingRewardItems[itemID] = true
            C_Item.RequestLoadItemDataByID(itemID)
        end
    end
    if mode == "decor" then
        local entry = C_HousingCatalog.GetCatalogEntryInfoByItem(itemID, false)
        return entry ~= nil and entry.entryID.entryType == Enum.HousingCatalogEntryType.Decor
    end
    -- Reward items have no link; the item ID resolves the base appearance.
    return RefineUI.Collections:ClassifyItem(itemID, itemID) == REWARD_KINDS[mode]
end

-- Filters and sorting that Blizzard's own achievement provider does not apply.
function Window:HasRowFilters()
    local settings = self:GetSettings()
    return self.activeInstance ~= nil or (self.rewardFilter or "all") ~= "all"
        or settings.CharacterCompletion or (settings.Sort or "default") ~= "default"
end

function Window:MatchesFilters(id)
    if self.activeInstance and not self.activeInstance.ids[id] then return false end
    local completion = self:GetCompletionFilter()
    if completion ~= "all" then
        if self:IsComplete(id) ~= (completion == "complete") then return false end
    end
    return self:MatchesReward(id)
end

function Window:PrepareRow(row, order, ignoreReveal)
    if (ignoreReveal or row.id ~= self.revealID) and not self:MatchesFilters(row.id) then return nil end
    local mode, key = self:GetSettings().Sort, order
    if mode == "name" then key = strlower(select(2, GetAchievementInfo(row.id)) or "")
    elseif mode == "completion" then key = self:IsComplete(row.id) and 1 or 0
    elseif mode == "points" then key = select(3, GetAchievementInfo(row.id)) or 0
    elseif mode == "id" then key = row.id end
    return { row = row, order = order, key = key }
end

function Window:BuildSortedProvider(filtered)
    local settings = self:GetSettings()
    local mode = settings.Sort or "default"
    if mode ~= "default" then
        table.sort(filtered, function(a, b)
            if a.key == b.key then return a.order < b.order end
            if settings.Reverse then return a.key > b.key end
            return a.key < b.key
        end)
    end
    for index, entry in ipairs(filtered) do filtered[index] = entry.row end
    return CreateDataProvider(filtered)
end

function Window:ProcessRows(rows)
    local filtered = {}
    for order, row in ipairs(rows) do
        local prepared = self:PrepareRow(row, order)
        if prepared then filtered[#filtered + 1] = prepared end
    end
    return self:BuildSortedProvider(filtered)
end

function Window:GetCategoryRows(category)
    local rows = {}
    for index = 1, GetCategoryNumAchievements(category) do
        local id = GetAchievementInfo(category, index)
        if id then rows[#rows + 1] = { category = category, index = index, id = id } end
    end
    return rows
end

function Window:GetSelectedCategory()
    -- Blizzard's current-category accessor is local. Read its public category
    -- records instead, including a selection restored while reopening the frame.
    for _, entry in ipairs(ACHIEVEMENT_FUNCTIONS and ACHIEVEMENT_FUNCTIONS.categories or {}) do
        if entry.selected then return entry.id end
    end
    return self.currentCategory
end

function Window:RefreshFilters()
    self.revealID = nil
    if not self:IsPersonalView() then return end
    local scroll = AchievementFrameCategories.ScrollBox
    local offset = scroll:GetScrollPercentage()
    AchievementFrameCategories_UpdateDataProvider()
    scroll:SetScrollPercentage(offset, ScrollBoxConstants.NoScrollInterpolation)
    if type(self:GetSelectedCategory()) == "number" then AchievementFrameAchievements_UpdateDataProvider() end
    self:QueueSearch()
end
