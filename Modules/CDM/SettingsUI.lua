----------------------------------------------------------------------------------------
-- CDM Component: SettingsUI
-- Description: Settings panel injection, refine tab UI, and refresh integration.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local CDM = RefineUI:GetModule("CDM")
if not CDM then
    return
end

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config
local Media = RefineUI.Media
local Colors = RefineUI.Colors
local Locale = RefineUI.Locale

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local type = type
local tinsert = table.insert
local wipe = _G.wipe or table.wipe
local strfind = string.find
local strlower = string.lower
local max = math.max
local CreateFrame = CreateFrame
local UIParent = UIParent
local PlaySound = PlaySound
local SOUNDKIT = _G.SOUNDKIT
local GetCursorPosition = GetCursorPosition
local GetAppropriateTopLevelParent = GetAppropriateTopLevelParent
local GameTooltip = GameTooltip
local GameTooltip_SetTitle = GameTooltip_SetTitle
local GameTooltip_Hide = GameTooltip_Hide
local GetCVarBool = GetCVarBool
local SetCVar = SetCVar

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local SETTINGS_BUCKET_ORDER = { "Left", "Right", "Bottom", CDM.NOT_TRACKED_KEY }
local CUSTOM_DISPLAY_MODE = "refineui"
local CUSTOM_TAB_TOOLTIP = "RefineUI"
local CUSTOM_TAB_ATLAS = "minimap-genericevent-hornicon-small"
local CUSTOM_TAB_TEXTURE = (RefineUI.Media and RefineUI.Media.Logo) or [[Interface\AddOns\RefineUI\Media\Logo\Logo.blp]]
local AURA_MODE_REFINED = "refineui"
local AURA_MODE_BLIZZARD = "blizzard"
local PANEL_REFRESH_TIMER_KEY = CDM:BuildKey("Settings", "PanelRefresh")
local SEARCH_DEBOUNCE_KEY = CDM:BuildKey("Settings", "SearchRefresh")

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function IsFilterActive(filterText)
    return type(filterText) == "string" and #filterText > 1
end


local function EnsureCooldownViewerSettingsLoaded()
    local settingsFrame = CDM:GetCooldownViewerSettingsFrame()
    if settingsFrame then
        return settingsFrame
    end

    local addonsAPI = _G.C_AddOns
    if addonsAPI and type(addonsAPI.LoadAddOn) == "function" then
        addonsAPI.LoadAddOn("Blizzard_CooldownViewer")
    elseif type(_G.LoadAddOn) == "function" then
        _G.LoadAddOn("Blizzard_CooldownViewer")
    end

    return CDM:GetCooldownViewerSettingsFrame()
end


local function GetSettingsState(self, settingsFrame)
    local state = self:StateGet(settingsFrame, "settingsInjectionState")
    if not state then
        state = {}
        self:StateSet(settingsFrame, "settingsInjectionState", state)
    end
    return state
end


local function IsTabButton(child, settingsFrame)
    if not child then
        return false
    end

    if settingsFrame and (child == settingsFrame.SpellsTab or child == settingsFrame.AurasTab) then
        return true
    end

    local name = child:GetName()
    return name and strfind(name, "Tab") ~= nil
end


local function IsTabSelected(tab)
    if not tab then
        return false
    end

    if type(tab.GetChecked) == "function" then
        local ok, checked = pcall(tab.GetChecked, tab)
        if ok and checked ~= nil and not (_G.issecretvalue and _G.issecretvalue(checked)) then
            return checked and true or false
        end
    end

    if type(tab.IsChecked) == "function" then
        local ok, checked = pcall(tab.IsChecked, tab)
        if ok and checked ~= nil and not (_G.issecretvalue and _G.issecretvalue(checked)) then
            return checked and true or false
        end
    end

    return false
end


local function ApplyCustomTabIcon(tab)
    if not tab or not tab.Icon then
        return
    end

    tab.Icon:SetTexture(CUSTOM_TAB_TEXTURE)
    tab.Icon:SetTexCoord(0, 1, 0, 1)
    tab.Icon:SetSize(18, 18)
end


local function EnsureModeOverlayBase(parent, titleText, bodyText, buttonText, onClick)
    local overlay = CreateFrame("Frame", nil, parent)
    overlay:SetFrameStrata("DIALOG")
    local parentLevel = 1
    if parent and type(parent.GetFrameLevel) == "function" then
        local ok, level = pcall(parent.GetFrameLevel, parent)
        if ok and not (_G.issecretvalue and _G.issecretvalue(level)) and type(level) == "number" then
            parentLevel = level
        end
    end
    overlay:SetFrameLevel(parentLevel + 30)
    overlay:Hide()

    overlay.BG = overlay:CreateTexture(nil, "BACKGROUND")
    overlay.BG:SetAllPoints()
    overlay.BG:SetColorTexture(0, 0, 0, 0.78)

    overlay.Title = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    overlay.Title:SetPoint("TOP", 0, -120)
    overlay.Title:SetText(titleText)

    overlay.Text = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    overlay.Text:SetPoint("TOP", overlay.Title, "BOTTOM", 0, -12)
    overlay.Text:SetWidth(280)
    overlay.Text:SetJustifyH("CENTER")
    overlay.Text:SetText(bodyText)

    overlay.Button = CreateFrame("Button", nil, overlay, "UIPanelButtonTemplate")
    overlay.Button:SetSize(180, 24)
    overlay.Button:SetPoint("TOP", overlay.Text, "BOTTOM", 0, -18)
    overlay.Button:SetText(buttonText)
    overlay.Button:SetScript("OnClick", onClick)

    return overlay
end


local function MakePseudoCategoryObject(bucketKey, titleText)
    local obj = {
        bucketKey = bucketKey,
        titleText = titleText,
        collapsed = false,
    }

    function obj:GetCategory()
        return self.bucketKey
    end

    function obj:GetTitle()
        return self.titleText
    end

    function obj:ShouldDisplayInfo(_info)
        return true
    end

    function obj:SetCollapsed(collapsed)
        self.collapsed = collapsed and true or false
    end

    function obj:IsCollapsed()
        return self.collapsed == true
    end

    function obj:GetItemDisplayType()
        return "icon"
    end

    function obj:GetCategoryAssignmentText()
        return self.titleText
    end

    return obj
end


local function IsShowingUnlearned()
    return GetCVarBool and GetCVarBool("cooldownViewerShowUnlearned") or false
end


local function ToggleShowUnlearned()
    SetCVar("cooldownViewerShowUnlearned", not IsShowingUnlearned())
end


----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function CDM:EnsureNativeModeOverlay(settingsFrame)
    local state = GetSettingsState(self, settingsFrame)
    if state.nativeModeOverlay then
        return state.nativeModeOverlay
    end

    local overlay = EnsureModeOverlayBase(
        settingsFrame,
        "Blizzard Buffs Disabled",
        "RefineUI Auras mode is active. Switch modes to edit Blizzard tracked buffs.",
        "Use Blizzard Buffs",
        function()
            CDM:SetAuraMode(AURA_MODE_BLIZZARD)
            if settingsFrame.SetDisplayMode then
                settingsFrame:SetDisplayMode("auras")
            end
            CDM:RefreshSettingsSection()
        end
    )

    if settingsFrame.Inset then
        overlay:SetPoint("TOPLEFT", settingsFrame.Inset, "TOPLEFT")
        overlay:SetPoint("BOTTOMRIGHT", settingsFrame.Inset, "BOTTOMRIGHT")
    else
        overlay:SetAllPoints(settingsFrame)
    end

    state.nativeModeOverlay = overlay
    return overlay
end


function CDM:EnsureRefineModeOverlay(settingsFrame)
    local state = GetSettingsState(self, settingsFrame)
    if state.refineModeOverlay then
        return state.refineModeOverlay
    end

    if not state.panel then
        return nil
    end

    local overlay = EnsureModeOverlayBase(
        state.panel,
        "RefineUI Auras Disabled",
        "Blizzard Buffs mode is active. Switch modes to edit RefineUI Left/Right/Bottom trackers.",
        "Use RefineUI Auras",
        function()
            CDM:SetAuraMode(AURA_MODE_REFINED)
            CDM:ShowRefineTabPanel(settingsFrame)
            CDM:RefreshSettingsSection()
        end
    )

    if state.panel.Inset then
        overlay:SetPoint("TOPLEFT", state.panel.Inset, "TOPLEFT")
        overlay:SetPoint("BOTTOMRIGHT", state.panel.Inset, "BOTTOMRIGHT")
    else
        overlay:SetAllPoints(state.panel)
    end

    state.refineModeOverlay = overlay
    return overlay
end


function CDM:UpdateAuraModeOverlays(settingsFrame, displayMode)
    local state = GetSettingsState(self, settingsFrame)
    local auraMode = (self.GetAuraMode and self:GetAuraMode()) or AURA_MODE_REFINED
    local mode = displayMode or state.currentDisplayMode or settingsFrame.displayMode
    if not mode then
        if state.panel and state.panel:IsShown() then
            mode = CUSTOM_DISPLAY_MODE
        elseif IsTabSelected(settingsFrame.AurasTab) then
            mode = "auras"
        elseif IsTabSelected(settingsFrame.SpellsTab) then
            mode = "spells"
        end
    end
    state.currentDisplayMode = mode

    local nativeOverlay = self:EnsureNativeModeOverlay(settingsFrame)
    local refineOverlay = self:EnsureRefineModeOverlay(settingsFrame)
    local showingRefinePanel = state.panel and state.panel:IsShown()

    if nativeOverlay then
        local showNativeOverlay = auraMode == AURA_MODE_REFINED and mode == "auras" and not showingRefinePanel
        nativeOverlay:SetShown(showNativeOverlay)
    end

    if refineOverlay then
        local showRefineOverlay = auraMode == AURA_MODE_BLIZZARD and showingRefinePanel
        refineOverlay:SetShown(showRefineOverlay)
    end
end


function CDM:InitializeInjectedItem(settingsFrame, itemFrame, categoryFrame)
    if self:StateGet(itemFrame, "injectedInitialized", false) then
        self:StateSet(itemFrame, "categoryFrame", categoryFrame)
        if self.RegisterVisualItemFrame then
            self:RegisterVisualItemFrame(itemFrame)
        end
        return
    end

    itemFrame:SetScript("OnDragStart", function(frame)
        if PlaySound and SOUNDKIT and SOUNDKIT.UI_CURSOR_PICKUP_OBJECT then
            PlaySound(SOUNDKIT.UI_CURSOR_PICKUP_OBJECT)
        end
        CDM:BeginInjectedOrderChange(settingsFrame, frame)
    end)

    itemFrame:SetScript("OnMouseUp", function(frame, button, upInside)
        if not upInside then
            return
        end
        if button == "LeftButton" then
            if PlaySound and SOUNDKIT and SOUNDKIT.UI_CURSOR_PICKUP_OBJECT then
                PlaySound(SOUNDKIT.UI_CURSOR_PICKUP_OBJECT)
            end
            CDM:BeginInjectedOrderChange(settingsFrame, frame, button)
        elseif button == "RightButton" then
            local data = CDM:GetInjectedItemData(frame)
            if data and data.cooldownID and not data.isEmpty then
                if type(frame.DisplayContextMenu) == "function" then
                    frame:DisplayContextMenu()
                else
                    CDM:UnassignCooldownID(data.cooldownID)
                    CDM:RequestRefresh()
                end
            end
        end
    end)

    itemFrame:SetScript("OnEnter", function(frame)
        CDM:OnInjectedItemEnter(frame)
    end)

    itemFrame:SetScript("OnLeave", function()
        CDM:OnInjectedItemLeave()
    end)

    self:StateSet(itemFrame, "injectedInitialized", true)
    self:StateSet(itemFrame, "categoryFrame", categoryFrame)
    if self.RegisterVisualItemFrame then
        self:RegisterVisualItemFrame(itemFrame)
    end
end


function CDM:DoesCooldownIDMatchFilter(cooldownID, filterText)
    if not IsFilterActive(filterText) then
        return true
    end

    local lowerName
    if self.GetCooldownDisplayNameLower then
        lowerName = self:GetCooldownDisplayNameLower(cooldownID)
    else
        local name = self:GetCooldownDisplayName(cooldownID)
        lowerName = strlower(name or "")
    end
    return strfind(lowerName, filterText, 1, true) ~= nil
end


function CDM:LayoutInjectedCategory(settingsFrame, categoryFrame, categoryData, filterText)
    local sourceList = categoryData.cooldownIDs
    local assignmentIndices = categoryData.assignmentIndices
    local container = categoryFrame.Container

    categoryFrame.itemPool:ReleaseAll()

    local shownItems = 0
    for listIndex = 1, #sourceList do
        local cooldownID = sourceList[listIndex]
        if self:DoesCooldownIDMatchFilter(cooldownID, filterText) then
            shownItems = shownItems + 1
            local assignmentIndex = (type(assignmentIndices) == "table" and assignmentIndices[listIndex]) or listIndex
            local item = categoryFrame.itemPool:Acquire()
            item.layoutIndex = shownItems
            item:Show()
            item:SetAsCooldown(cooldownID, assignmentIndex)
            item:SetSize(38, 38)

            self:InitializeInjectedItem(settingsFrame, item, categoryFrame)
            self:StateSet(item, "bucketKey", categoryData.bucketKey)
            self:StateSet(item, "cooldownID", cooldownID)
            self:StateSet(item, "isEmpty", false)
            self:StateSet(item, "displayIndex", shownItems)
            self:StateSet(item, "assignmentIndex", assignmentIndex)
        end
    end

    if shownItems == 0 then
        local emptyItem = categoryFrame.itemPool:Acquire()
        emptyItem.layoutIndex = 1
        emptyItem:Show()
        emptyItem:SetAsEmptyCategory(categoryFrame:GetCategoryObject())
        emptyItem:SetSize(38, 38)

        self:InitializeInjectedItem(settingsFrame, emptyItem, categoryFrame)
        self:StateSet(emptyItem, "bucketKey", categoryData.bucketKey)
        self:StateSet(emptyItem, "cooldownID", nil)
        self:StateSet(emptyItem, "isEmpty", true)
        self:StateSet(emptyItem, "displayIndex", 1)
        self:StateSet(emptyItem, "assignmentIndex", nil)
    end

    container:Layout()
    categoryFrame:SetCollapsed(categoryFrame:GetCategoryObject():IsCollapsed())

    local headerHeight = categoryFrame.Header:GetHeight() or 22
    if categoryFrame:IsCollapsed() then
        categoryFrame:SetHeight(headerHeight)
    else
        local contentHeight = container:GetHeight() or 0
        categoryFrame:SetHeight(headerHeight + 15 + contentHeight)
    end
end


function CDM:EnsureInjectedCategory(settingsFrame, bucketKey)
    local state = GetSettingsState(self, settingsFrame)
    state.categories = state.categories or {}
    local categoryFrame = state.categories[bucketKey]
    if categoryFrame then
        return categoryFrame
    end

    local panel = state.panel
    local scrollChild = panel and panel.ScrollChild
    if not scrollChild then
        return nil
    end

    local title = self.BUCKET_LABELS[bucketKey] or bucketKey
    local categoryObj = MakePseudoCategoryObject(bucketKey, title)
    categoryFrame = CreateFrame("Frame", nil, scrollChild, "CooldownViewerSettingsCategoryTemplate")
    categoryFrame:Init(categoryObj)
    categoryFrame:SetCollapsed(false)
    categoryFrame:Show()

    categoryFrame:HookScript("OnEnter", function(frame)
        CDM:OnInjectedCategoryEnter(frame)
    end)
    if categoryFrame.Container then
        categoryFrame.Container:HookScript("OnEnter", function()
            CDM:OnInjectedCategoryEnter(categoryFrame)
        end)
    end

    state.categories[bucketKey] = categoryFrame
    self:StateSet(categoryFrame, "categoryData", { bucketKey = bucketKey, cooldownIDs = {} })
    return categoryFrame
end


function CDM:HideNativeSettingsContent(settingsFrame)
    local state = GetSettingsState(self, settingsFrame)
    if state.nativeHidden then
        return
    end

    state.hiddenChildren = {}
    for _, child in ipairs({ settingsFrame:GetChildren() }) do
        if child:IsShown() and child ~= state.panel and not IsTabButton(child, settingsFrame) then
            child:Hide()
            tinsert(state.hiddenChildren, child)
        end
    end
    state.nativeHidden = true
end


function CDM:RestoreNativeSettingsContent(settingsFrame)
    local state = GetSettingsState(self, settingsFrame)
    if state.hiddenChildren then
        for i = 1, #state.hiddenChildren do
            local child = state.hiddenChildren[i]
            if child and not child:IsShown() then
                child:Show()
            end
        end
    end
    state.hiddenChildren = nil
    state.nativeHidden = false
end


function CDM:HideRefineTabPanel(settingsFrame)
    self:EndInjectedOrderChange(false)

    local state = GetSettingsState(self, settingsFrame)
    if state.panel then
        state.panel:Hide()
    end
    if state.tabButton then
        state.tabButton:SetChecked(false)
    end
    self:RestoreNativeSettingsContent(settingsFrame)
    self:UpdateAuraModeOverlays(settingsFrame, state.currentDisplayMode)
end


function CDM:ShowRefineTabPanel(settingsFrame)
    local state = GetSettingsState(self, settingsFrame)
    if not state.panel then
        return
    end

    self:HideNativeSettingsContent(settingsFrame)

    if settingsFrame.SpellsTab then
        settingsFrame.SpellsTab:SetChecked(false)
    end
    if settingsFrame.AurasTab then
        settingsFrame.AurasTab:SetChecked(false)
    end
    if state.tabButton then
        state.tabButton:SetChecked(true)
    end

    state.panel:Show()
    self:RefreshRefineTabPanel(settingsFrame)
    self:UpdateAuraModeOverlays(settingsFrame, CUSTOM_DISPLAY_MODE)
end


function CDM:OpenSettingsPanel()
    local settingsFrame = EnsureCooldownViewerSettingsLoaded()
    if not settingsFrame then
        RefineUI:Print("CDM settings are unavailable right now.")
        return false
    end

    if self.InstallSettingsHooks then
        self:InstallSettingsHooks()
    end

    if type(settingsFrame.ShowUIPanel) == "function" then
        settingsFrame:ShowUIPanel()
    elseif type(_G.ShowUIPanel) == "function" then
        _G.ShowUIPanel(settingsFrame)
    else
        settingsFrame:Show()
    end

    if self.ShowRefineTabPanel then
        self:ShowRefineTabPanel(settingsFrame)
    end
    if self.RefreshSettingsSection then
        self:RefreshSettingsSection()
    end

    return true
end


function CDM:RequestRefineTabPanelRefresh(settingsFrame)
    local state = GetSettingsState(self, settingsFrame)
    if state.panelRefreshQueued then
        return
    end

    state.panelRefreshQueued = true
    local function RunRefresh()
        state.panelRefreshQueued = nil
        if settingsFrame and settingsFrame:IsShown() then
            CDM:RefreshRefineTabPanel(settingsFrame)
        end
    end

    if RefineUI.After then
        RefineUI:After(PANEL_REFRESH_TIMER_KEY, 0, RunRefresh)
    else
        RunRefresh()
    end
end


function CDM:RefreshRefineTabPanel(settingsFrame)
    local state = GetSettingsState(self, settingsFrame)
    local panel = state.panel
    if not panel or not panel:IsShown() then
        self:UpdateAuraModeOverlays(settingsFrame, state.currentDisplayMode)
        return
    end

    if panel.SetPortraitToSpecIcon then
        panel:SetPortraitToSpecIcon()
    end

    if self.assignmentsPruneDirty then
        self:PruneCurrentLayoutAssignments()
    end

    local assignments = self:GetCurrentAssignments()
    local validAuraIDs = self:GetValidAuraCooldownIDs()
    state.validAuraSetScratch = state.validAuraSetScratch or {}
    local validAuraSet = state.validAuraSetScratch
    if wipe then
        wipe(validAuraSet)
    else
        for key in pairs(validAuraSet) do
            validAuraSet[key] = nil
        end
    end
    for i = 1, #validAuraIDs do
        validAuraSet[validAuraIDs[i]] = true
    end
    local notTrackedIDs = self:GetSortedNotTrackedIDs(validAuraIDs, assignments)
    local filterText = state.filterText

    local leftIDs, leftAssignmentIndices = self:GetVisibleBucketCooldownIDs(assignments.Left, validAuraSet)
    local rightIDs, rightAssignmentIndices = self:GetVisibleBucketCooldownIDs(assignments.Right, validAuraSet)
    local bottomIDs, bottomAssignmentIndices = self:GetVisibleBucketCooldownIDs(assignments.Bottom, validAuraSet)

    local categoryInput = {
        Left = { cooldownIDs = leftIDs, assignmentIndices = leftAssignmentIndices },
        Right = { cooldownIDs = rightIDs, assignmentIndices = rightAssignmentIndices },
        Bottom = { cooldownIDs = bottomIDs, assignmentIndices = bottomAssignmentIndices },
        [CDM.NOT_TRACKED_KEY] = { cooldownIDs = notTrackedIDs, assignmentIndices = nil },
    }

    local previousCategory
    local yOffset = 0
    for i = 1, #SETTINGS_BUCKET_ORDER do
        local bucketKey = SETTINGS_BUCKET_ORDER[i]
        local categoryFrame = self:EnsureInjectedCategory(settingsFrame, bucketKey)
        local input = categoryInput[bucketKey] or {}
        local categoryData = {
            bucketKey = bucketKey,
            cooldownIDs = input.cooldownIDs or {},
            assignmentIndices = input.assignmentIndices,
        }
        self:StateSet(categoryFrame, "categoryData", categoryData)

        categoryFrame:ClearAllPoints()
        if previousCategory then
            categoryFrame:SetPoint("TOPLEFT", previousCategory, "BOTTOMLEFT", 0, -18)
            categoryFrame:SetPoint("TOPRIGHT", previousCategory, "BOTTOMRIGHT", 0, -18)
            yOffset = yOffset + 18
        else
            categoryFrame:SetPoint("TOPLEFT", panel.ScrollChild, "TOPLEFT", 0, 0)
            categoryFrame:SetPoint("TOPRIGHT", panel.ScrollChild, "TOPRIGHT", 0, 0)
        end

        self:LayoutInjectedCategory(settingsFrame, categoryFrame, categoryData, filterText)
        categoryFrame:Show()
        yOffset = yOffset + (categoryFrame:GetHeight() or 0)
        previousCategory = categoryFrame
    end

    panel.ScrollChild:SetHeight(max(1, yOffset + 20))
    if panel.ScrollFrame and panel.ScrollFrame.UpdateScrollChildRect then
        panel.ScrollFrame:UpdateScrollChildRect()
    end

    self:UpdateAuraModeOverlays(settingsFrame, CUSTOM_DISPLAY_MODE)
end


function CDM:EnsureRefineTabPanel(settingsFrame)
    local state = GetSettingsState(self, settingsFrame)
    if state.panel then
        return state.panel
    end

    local panel = CreateFrame("Frame", nil, settingsFrame, "ButtonFrameTemplate")
    panel:SetAllPoints(settingsFrame)
    panel:Hide()

    if panel.Inset and panel.Inset.Bg then
        panel.Inset.Bg:SetAtlas("character-panel-background", true)
        panel.Inset.Bg:SetHorizTile(false)
        panel.Inset.Bg:SetVertTile(false)
    end
    if panel.TitleContainer and panel.TitleContainer.TitleText then
        panel.TitleContainer.TitleText:SetText("Cooldown Settings")
    end

    local searchBox = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
    searchBox:SetSize(290, 30)
    searchBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 72, -30)
    if searchBox.Instructions then
        searchBox.Instructions:SetText(COOLDOWN_VIEWER_SETTINGS_SEARCH_INSTRUCTIONS or "Search")
    end
    searchBox:SetScript("OnTextChanged", function(editBox)
        if editBox.Instructions then
            editBox.Instructions:SetShown(editBox:GetText() == "")
        end
        local updatedFilter = strlower(editBox:GetText() or "")
        if updatedFilter == state.filterText then
            return
        end
        state.filterText = updatedFilter
        if RefineUI.Debounce then
            RefineUI:Debounce(SEARCH_DEBOUNCE_KEY, 0.05, function()
                CDM:RequestRefineTabPanelRefresh(settingsFrame)
            end)
        else
            CDM:RequestRefineTabPanelRefresh(settingsFrame)
        end
    end)
    panel.SearchBox = searchBox

    local settingsDropdown = CreateFrame("DropdownButton", nil, panel, "UIPanelIconDropdownButtonTemplate")
    settingsDropdown:SetPoint("LEFT", searchBox, "RIGHT", 5, 0)
    if settingsDropdown.SetupMenu then
        settingsDropdown:SetupMenu(function(_owner, rootDescription)
            rootDescription:CreateCheckbox(COOLDOWN_VIEWER_SETTINGS_SHOW_UNLEARNED or "Show Unlearned", IsShowingUnlearned, function()
                ToggleShowUnlearned()
                CDM:RequestRefresh()
            end)
        end)
    end
    panel.SettingsDropdown = settingsDropdown

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "ScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 17, -70)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 29)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(300, 1)
    scrollChild:SetPoint("TOPLEFT", 0, 0)
    scrollChild:SetPoint("TOPRIGHT", 0, 0)
    scrollFrame:SetScrollChild(scrollChild)
    if scrollFrame.ScrollBar then
        scrollFrame.ScrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 6, 0)
        scrollFrame.ScrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 6, 0)
    end

    scrollFrame:SetScript("OnSizeChanged", function(frame)
        scrollChild:SetWidth(frame:GetWidth())
        CDM:RequestRefineTabPanelRefresh(settingsFrame)
    end)

    panel:HookScript("OnShow", function()
        scrollChild:SetWidth(scrollFrame:GetWidth())
        CDM:RequestRefineTabPanelRefresh(settingsFrame)
    end)

    panel.ScrollFrame = scrollFrame
    panel.ScrollChild = scrollChild

    state.panel = panel
    state.filterText = state.filterText or ""
    return panel
end


function CDM:EnsureRefineTabButton(settingsFrame)
    local state = GetSettingsState(self, settingsFrame)
    if state.tabButton then
        return state.tabButton
    end

    local aurasTab = settingsFrame.AurasTab
    if not aurasTab then
        return nil
    end

    local tab = CreateFrame("Button", nil, UIParent, "CooldownViewerSettingsTabTemplate")
    tab.tooltipText = CUSTOM_TAB_TOOLTIP
    tab.displayMode = CUSTOM_DISPLAY_MODE
    tab.activeAtlas = CUSTOM_TAB_ATLAS
    tab.inactiveAtlas = CUSTOM_TAB_ATLAS
    tab:SetChecked(false)
    ApplyCustomTabIcon(tab)
    tab:SetPoint("TOP", aurasTab, "BOTTOM", 0, -3)
    tab:SetScript("OnClick", function()
        CDM:ShowRefineTabPanel(settingsFrame)
    end)
    tab:Hide()

    RefineUI:HookOnce("CDM:Settings:RefineTab:SetChecked", tab, "SetChecked", function()
        ApplyCustomTabIcon(tab)
    end)
    RefineUI:HookScriptOnce("CDM:Settings:RefineTab:OnShow", tab, "OnShow", function()
        ApplyCustomTabIcon(tab)
    end)

    state.tabButton = tab
    return tab
end


function CDM:InstallSettingsHooks()
    local settingsFrame = self:GetCooldownViewerSettingsFrame()
    if not settingsFrame or self.settingsHooksInstalled then
        return
    end

    self:EnsureRefineTabPanel(settingsFrame)
    self:EnsureRefineTabButton(settingsFrame)

    RefineUI:HookOnce("CDM:Settings:SetDisplayMode", settingsFrame, "SetDisplayMode", function(_, mode)
        local state = GetSettingsState(CDM, settingsFrame)
        state.currentDisplayMode = mode
        local spellsTab = settingsFrame.SpellsTab
        local aurasTab = settingsFrame.AurasTab
        if spellsTab then
            spellsTab:SetChecked(mode == "spells")
        end
        if aurasTab then
            aurasTab:SetChecked(mode == "auras")
        end
        if state.tabButton then
            state.tabButton:SetChecked(mode == CUSTOM_DISPLAY_MODE)
        end
        CDM:HideRefineTabPanel(settingsFrame)
        CDM:UpdateAuraModeOverlays(settingsFrame, mode)
    end)
    RefineUI:HookScriptOnce("CDM:Settings:OnShow", settingsFrame, "OnShow", function()
        local state = GetSettingsState(CDM, settingsFrame)
        if state.tabButton then
            if settingsFrame.AurasTab then
                state.tabButton:ClearAllPoints()
                state.tabButton:SetPoint("TOP", settingsFrame.AurasTab, "BOTTOM", 0, -3)
            end
            state.tabButton:Show()
        end
        CDM:HideRefineTabPanel(settingsFrame)
        CDM:UpdateAuraModeOverlays(settingsFrame, state.currentDisplayMode or settingsFrame.displayMode)
    end)
    RefineUI:HookScriptOnce("CDM:Settings:OnHide", settingsFrame, "OnHide", function()
        local state = GetSettingsState(CDM, settingsFrame)
        if state.tabButton then
            state.tabButton:Hide()
        end
        if RefineUI.CancelDebounce then
            RefineUI:CancelDebounce(SEARCH_DEBOUNCE_KEY)
        end
        if RefineUI.CancelTimer then
            RefineUI:CancelTimer(PANEL_REFRESH_TIMER_KEY)
        end
        CDM:HideRefineTabPanel(settingsFrame)
        CDM:UpdateAuraModeOverlays(settingsFrame, state.currentDisplayMode)
        CDM:EndInjectedOrderChange(false)
        if CDM.ShowReloadRecommendationIfPending then
            CDM:ShowReloadRecommendationIfPending()
        end
    end)

    local state = GetSettingsState(self, settingsFrame)
    if state.tabButton then
        state.tabButton:SetShown(settingsFrame:IsShown())
    end

    self.settingsHooksInstalled = true
end


function CDM:InitializeSettingsInjection()
    local function TryInstall()
        CDM:InstallSettingsHooks()
    end

    RefineUI:RegisterEventCallback("ADDON_LOADED", function(_event, addonName)
        if addonName == "Blizzard_CooldownViewer" then
            TryInstall()
        end
    end, "CDM:SettingsAddonLoaded")

    if self:GetCooldownViewerSettingsFrame() then
        TryInstall()
    end
end


function CDM:RefreshSettingsSection()
    local settingsFrame = self:GetCooldownViewerSettingsFrame()
    if settingsFrame and settingsFrame:IsShown() then
        if self.ProcessPendingInitialTrackedBuffClear then
            self:ProcessPendingInitialTrackedBuffClear()
        end
        if self.ProcessPendingTrackedBuffSync then
            self:ProcessPendingTrackedBuffSync()
        end
        self:RefreshRefineTabPanel(settingsFrame)
        self:UpdateAuraModeOverlays(settingsFrame)
    end
end
