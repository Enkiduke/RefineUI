local _, RefineUI = ...
local Module = RefineUI:GetModule("AdventureGuideInstances")

function Module:GetGuideSettings()
    RefineUI.Config.AdventureGuide = RefineUI.Config.AdventureGuide or {}
    return RefineUI.Config.AdventureGuide
end

function Module:IsGuideOptionEnabled(key)
    return self:GetGuideSettings()[key] ~= false
end

function Module:ApplyGuideSettings()
    self:ReleaseExpansionCompletionRequests()
    local journal = _G.EncounterJournal
    local scroll = journal and journal.instanceSelect and journal.instanceSelect.ScrollBox
    if scroll and scroll.GetFrames then
        for _, button in ipairs(scroll:GetFrames()) do
            RefineUI.InstanceCompletion:ReleaseSummary(button)
            button.RefineExpansionInstanceID = nil
            self:DecorateExpansionCompletion(button)
            if button.RefineExpansionSummary then self:RenderExpansionCompletion(button, button.RefineExpansionSummary) end
        end
    end
    self:RequestExpansionCompletion()
    self:RefreshGuideLockoutCards()
end

function Module:BuildGuideSettingsMenu(root)
    root:CreateTitle("Adventure Guide")
    local function Toggle(menu, label, key)
        menu:CreateCheckbox(label, function() return self:IsGuideOptionEnabled(key) end, function()
            local settings = self:GetGuideSettings()
            settings[key] = not self:IsGuideOptionEnabled(key)
            self:ApplyGuideSettings()
        end)
    end
    Toggle(root, "Show card collection progress", "Cards")
    Toggle(root, "Show completed categories", "ShowCompletedCategories")
    Toggle(root, "Show card lockouts", "Lockouts")
    local categories = root:CreateButton("Card reward categories")
    for _, entry in ipairs({ { "Achievements", "achievements" }, { "Appearances", "appearances" },
        { "Pets", "pets" }, { "Mounts", "mounts" }, { "Toys", "toys" } }) do
        Toggle(categories, entry[1], entry[2])
    end
    root:CreateDivider()
    root:CreateButton("Reset Guide settings", function()
        RefineUI.Config.AdventureGuide = {}
        self:ApplyGuideSettings()
    end)
end

function Module:InstallGuideSettings()
    if self.guideSettingsButton then return end
    local journal = _G.EncounterJournal
    -- The title-bar artwork lives on the raised NineSlice, above journal children.
    local chrome = journal.NineSlice or journal
    local button = RefineUI.CreateSettingsButton(chrome, "RefineUI_AdventureGuideSettings", 16)
    button:SetFrameLevel(math.max(chrome:GetFrameLevel(),
        journal.CloseButton and journal.CloseButton:GetFrameLevel() or journal:GetFrameLevel()) + 1)
    button:SetPoint("TOPRIGHT", journal, "TOPRIGHT", -34, -7)
    button:SetScript("OnEnter", function(owner)
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetText("Adventure Guide settings")
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnMouseDown", function(owner)
        MenuUtil.CreateContextMenu(owner, function(_, root) self:BuildGuideSettingsMenu(root) end)
    end)
    self.guideSettingsButton = button
end
