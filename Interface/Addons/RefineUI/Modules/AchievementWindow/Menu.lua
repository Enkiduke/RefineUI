local _, RefineUI = ...
local Window = RefineUI:GetModule("AchievementWindow")

function Window:HasActiveFilters()
    local settings = self:GetSettings()
    return self:GetCompletionFilter() ~= "all" or self.activeInstance ~= nil
        or (self.rewardFilter or "all") ~= "all" or settings.CharacterCompletion
        or (settings.Sort or "default") ~= "default"
end

function Window:UpdateResetButton()
    if not self.resetButton then return end
    local active = self:HasActiveFilters()
    self.resetButton:SetShown(self:IsPersonalView())
    self.resetButton:SetEnabled(active)
    self.resetButton:SetAlpha(active and 1 or 0.35)
end

function Window:ResetFilters()
    if not self:IsPersonalView() then return end
    local settings = self:GetSettings()
    settings.CharacterCompletion, settings.Sort, settings.Reverse = false, "default", false
    self.rewardFilter, self.activeInstance, self.revealID = "all", nil, nil
    AchievementFrame_SetFilter(1)
    self:RefreshFilters()
    AchievementFrame.FilterDropdown:GenerateMenu()
    self:UpdateResetButton()
end

function Window:InstallResetButton()
    local dropdown = AchievementFrame.FilterDropdown
    if self.resetButton or not dropdown then return end
    -- Retail's own filter-reset template uses auctionhouse-ui-filter-redx.
    local button = CreateFrame("Button", nil, dropdown, "UIResetButtonTemplate")
    -- The shared template only supplies normal/highlight textures. Keep its
    -- icon visible while disabled so the inactive reset control remains clear.
    button:SetDisabledAtlas("auctionhouse-ui-filter-redx")
    button:SetPoint("LEFT", dropdown, "RIGHT", 4, 0)
    button:SetScript("OnClick", function() self:ResetFilters() end)
    button:SetScript("OnEnter", function(owner)
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetText("Reset achievement filters")
        GameTooltip:AddLine("Show all achievements in this category using Warband completion and Blizzard's default order.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.resetButton = button
    dropdown:HookScript("OnShow", function() self:UpdateResetButton() end)
    self:UpdateResetButton()
end

function Window:InstallFilterMenu()
    self:InstallResetButton()
    if not Menu or not Menu.ModifyMenu then return end
    Menu.ModifyMenu("MENU_ACHIEVEMENT_FILTER", function(_, root)
        if not self:IsPersonalView() then return end
        root:CreateDivider()
        local rewards = root:CreateButton("Reward type")
        for _, option in ipairs(self:GetRewardOptions()) do
            local key, label = option[1], option[2]
            local radio = rewards:CreateRadio(label, function() return (self.rewardFilter or "all") == key end, function()
                self.rewardFilter = key
                self:RefreshFilters()
            end)
            radio:SetSelectionIgnored()
        end
        local completion = root:CreateButton("Completed by")
        for _, option in ipairs({ {false, "Any character (Warband)"}, {true, "This character only"} }) do
            local value, label = option[1], option[2]
            local radio = completion:CreateRadio(label, function() return self:GetSettings().CharacterCompletion == value end, function()
                self:GetSettings().CharacterCompletion = value
                self:RefreshFilters()
            end)
            radio:SetSelectionIgnored()
            radio:SetTooltip(function(tooltip)
                GameTooltip_SetTitle(tooltip, label)
                GameTooltip_AddNormalLine(tooltip, value
                    and "Completed and Incomplete filters count only achievements earned by this character. Instance totals use the same rule."
                    or "Completed and Incomplete filters count achievements earned by any character in your Warband.")
            end)
        end
        local sorting = root:CreateButton("Sort by")
        for _, option in ipairs({ {"default", "Blizzard default"}, {"name", "Name"},
            {"completion", "Completion"}, {"points", "Points"}, {"id", "Achievement ID"} }) do
            local key, label = option[1], option[2]
            local radio = sorting:CreateRadio(label, function() return self:GetSettings().Sort == key end, function()
                self:GetSettings().Sort = key
                self:RefreshFilters()
            end)
            radio:SetSelectionIgnored()
        end
        if self:GetSettings().Sort ~= "default" then
            sorting:CreateDivider()
            local reverse = sorting:CreateCheckbox("Reverse direction", function() return self:GetSettings().Reverse end, function()
                self:GetSettings().Reverse = not self:GetSettings().Reverse
                self:RefreshFilters()
            end)
            reverse:SetSelectionIgnored()
        end
    end)
end
