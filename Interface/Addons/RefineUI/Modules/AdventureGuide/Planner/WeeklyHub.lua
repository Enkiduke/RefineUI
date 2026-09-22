local _, RefineUI = ...
local Module = RefineUI:GetModule("AdventureGuidePlanner")

function Module:SelectWeeklyHub()
    EJ_ContentTab_Select(self.weeklyHubTab:GetID())
end

function Module:LayoutWeeklyHubTabs()
    local journal, tab = EncounterJournal, self.weeklyHubTab
    if not tab or self.weeklyHubLayingOut then return end
    self.weeklyHubLayingOut = true
    local order = { tab }
    local first = journal.JourneysTab or journal.Tabs[1]
    if first ~= tab then order[#order + 1] = first end
    for _, button in ipairs(journal.Tabs) do
        if button ~= tab and button ~= first then order[#order + 1] = button end
    end
    journal.maxTabWidth = (journal:GetWidth() - 22 - 3 * (#order - 1)) / #order
    local x = 11
    for _, button in ipairs(order) do
        PanelTemplates_TabResize(button, 0, nil, nil, journal.maxTabWidth)
        button:ClearAllPoints()
        -- Anchor to the journal itself so a native ID-order layout cannot
        -- create a dependency cycle between the first and last tabs.
        button:SetPoint("TOPLEFT", journal, "BOTTOMLEFT", x, 2)
        x = x + button:GetWidth() + 3
    end
    self.weeklyHubLayingOut = nil
end

function Module:InstallWeeklyHub()
    if self.weeklyHub then return end
    local journal = EncounterJournal
    if not journal.Tabs or not journal.Tabs[1] then return end
    local tab = CreateFrame("Button", "RefineUIWeeklyHubTab", journal, "BottomEncounterTierTabTemplate")
    self.weeklyHubTab = tab
    -- Some client versions register template-created tabs during CreateFrame.
    -- Reuse that slot; appending twice makes native anchoring target itself.
    local tabID
    for index, button in ipairs(journal.Tabs) do
        if button == tab then tabID = index; break end
    end
    if not tabID then
        tabID = #journal.Tabs + 1
        journal.Tabs[tabID] = tab
    end
    tab:SetID(tabID); tab:SetText("Planner")
    PanelTemplates_SetNumTabs(journal, #journal.Tabs)
    self:LayoutWeeklyHubTabs()
    hooksecurefunc("PanelTemplates_AnchorTabs", function(frame)
        if frame == journal then self:LayoutWeeklyHubTabs() end
    end)
    journal:HookScript("OnSizeChanged", function() self:LayoutWeeklyHubTabs() end)
    for _, button in ipairs(journal.Tabs) do
        button:HookScript("OnShow", function() self:LayoutWeeklyHubTabs() end)
    end
    -- Custom IDs stay local; never pass them to C_EncounterJournal.SetTab.
    tab:SetScript("OnClick", function() self:SelectWeeklyHub() end)
    local page = self:CreatePlannerPage(journal)
    hooksecurefunc("EJ_ContentTab_Select", function(id)
        self:LayoutWeeklyHubTabs()
        local active = id == tab:GetID()
        if active then
            EJ_HideNonInstancePanels()
            journal.instanceSelect:Hide(); journal.encounter:Hide()
            journal.navBar:Hide(); journal.searchBox:Hide()
            if EncounterJournal_HideGreatVaultButton then EncounterJournal_HideGreatVaultButton() end
            journal:SetTitle(ADVENTURE_JOURNAL)
        end
        page:SetShown(active)
    end)
    journal:HookScript("OnShow", function() self:SelectWeeklyHub() end)
    if journal:IsShown() then self:SelectWeeklyHub() end
end
