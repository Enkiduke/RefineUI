local _, RefineUI = ...
local Module = RefineUI:GetModule("CooldownAuraTrackers")

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

local SETTINGS_BUCKET_ORDER = { "Left", "Right", "Bottom", Module.NOT_TRACKED_KEY }
local CUSTOM_DISPLAY_MODE = "refineui"
local CUSTOM_TAB_TOOLTIP = "RefineUI"
local CUSTOM_TAB_ATLAS = "minimap-genericevent-hornicon-small"
local CUSTOM_TAB_TEXTURE = (RefineUI.Media and RefineUI.Media.Logo) or [[Interface\AddOns\RefineUI\Media\Logo\Logo.blp]]
local AURA_MODE_REFINED = "refineui"
local AURA_MODE_BLIZZARD = "blizzard"
local PANEL_REFRESH_TIMER_KEY = "CooldownAuraTrackers:Settings:PanelRefresh"
local SEARCH_DEBOUNCE_KEY = "CooldownAuraTrackers:Settings:SearchRefresh"
local DRAG_MARKER_UPDATE_JOB_KEY = "CooldownAuraTrackers:Settings:DragMarkerUpdate"

local function IsFilterActive(filterText)
    return type(filterText) == "string" and #filterText > 1
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
        if ok and checked ~= nil then
            return checked and true or false
        end
    end

    if type(tab.IsChecked) == "function" then
        local ok, checked = pcall(tab.IsChecked, tab)
        if ok and checked ~= nil then
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
    overlay:SetFrameLevel((parent:GetFrameLevel() or 1) + 30)
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

function Module:EnsureNativeModeOverlay(settingsFrame)
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
            Module:SetAuraMode(AURA_MODE_BLIZZARD)
            if settingsFrame.SetDisplayMode then
                settingsFrame:SetDisplayMode("auras")
            end
            Module:RefreshSettingsSection()
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

function Module:EnsureRefineModeOverlay(settingsFrame)
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
            Module:SetAuraMode(AURA_MODE_REFINED)
            Module:ShowRefineTabPanel(settingsFrame)
            Module:RefreshSettingsSection()
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

function Module:UpdateAuraModeOverlays(settingsFrame, displayMode)
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

local function EnsureDragWatcher(self)
    if self.dragWatcher then
        return self.dragWatcher
    end

    local frame = CreateFrame("Frame")
    frame:Hide()
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "GLOBAL_MOUSE_UP" then
            local button = ...
            Module:OnInjectedGlobalMouseUp(button)
        end
    end)

    self.dragWatcher = frame
    return frame
end

local function EnsureDragMarkerUpdateJob(self)
    if self.dragMarkerUpdateJobRegistered then
        return true
    end
    if not RefineUI.RegisterUpdateJob then
        return false
    end

    local ok = RefineUI:RegisterUpdateJob(DRAG_MARKER_UPDATE_JOB_KEY, 0, function()
        Module:UpdateInjectedReorderMarker()
    end, {
        enabled = false,
        safe = true,
        disableOnError = true,
    })
    if ok then
        self.dragMarkerUpdateJobRegistered = true
        return true
    end
    return false
end

local function SetDragMarkerUpdateEnabled(self, enabled)
    if not EnsureDragMarkerUpdateJob(self) then
        return
    end
    if RefineUI.SetUpdateJobEnabled then
        RefineUI:SetUpdateJobEnabled(DRAG_MARKER_UPDATE_JOB_KEY, enabled, true)
    end
    if enabled and RefineUI.RunUpdateJobNow then
        RefineUI:RunUpdateJobNow(DRAG_MARKER_UPDATE_JOB_KEY)
    end
end

local function EnsureDragCursor(self)
    if self.dragCursor then
        return self.dragCursor
    end

    local cursor = CreateFrame("Frame", nil, GetAppropriateTopLevelParent(), "CooldownViewerSettingsDraggedItemTemplate")
    cursor:Hide()
    self.dragCursor = cursor
    return cursor
end

local function EnsureReorderMarker(self, settingsFrame)
    if self.reorderMarker then
        return self.reorderMarker
    end

    local state = GetSettingsState(self, settingsFrame)
    local panel = state.panel
    local marker = panel and panel.ReorderMarker
    if not marker and _G.CooldownViewerSettingsReorderMarkerTemplate then
        local ok, created = pcall(CreateFrame, "Frame", nil, panel, "CooldownViewerSettingsReorderMarkerTemplate")
        if ok then
            marker = created
        end
    end

    if not marker then
        marker = CreateFrame("Frame", nil, panel)
        marker:SetSize(8, 52)
        marker.Texture = marker:CreateTexture(nil, "OVERLAY")
        marker.Texture:SetAllPoints()
        marker.Texture:SetColorTexture(1, 1, 1, 0.85)
    end

    if not marker.SetVertical then
        function marker:SetVertical()
            self:SetSize(8, 52)
            if self.Texture and self.Texture.SetAtlas then
                self.Texture:SetAtlas("cdm-vertical", true)
            end
        end
    end

    if not marker.SetHorizontal then
        function marker:SetHorizontal()
            self:SetSize(52, 8)
            if self.Texture and self.Texture.SetAtlas then
                self.Texture:SetAtlas("cdm-horizontal", true)
            end
        end
    end

    marker:Hide()
    self.reorderMarker = marker
    return marker
end

function Module:GetInjectedItemData(item)
    if not item then
        return nil
    end
    return {
        bucketKey = self:StateGet(item, "bucketKey"),
        cooldownID = self:StateGet(item, "cooldownID"),
        isEmpty = self:StateGet(item, "isEmpty", false),
        displayIndex = self:StateGet(item, "displayIndex", 1),
        assignmentIndex = self:StateGet(item, "assignmentIndex"),
    }
end

function Module:SetInjectedDragTarget(categoryFrame, itemFrame)
    local drag = self.dragState
    if not drag then
        return
    end

    if categoryFrame then
        drag.targetCategory = categoryFrame
    end
    drag.targetItem = itemFrame
end

function Module:OnInjectedCategoryEnter(categoryFrame)
    self:SetInjectedDragTarget(categoryFrame, nil)
end

function Module:OnInjectedItemEnter(itemFrame)
    local categoryFrame = self:StateGet(itemFrame, "categoryFrame")
    self:SetInjectedDragTarget(categoryFrame, itemFrame)

    local data = self:GetInjectedItemData(itemFrame)
    if not data then
        return
    end

    if data.isEmpty then
        GameTooltip:SetOwner(itemFrame, "ANCHOR_RIGHT")
        GameTooltip_SetTitle(GameTooltip, "Empty Slot")
        GameTooltip:Show()
        return
    end

    local info = self:GetCooldownInfo(data.cooldownID)
    local spellID = self:ResolveCooldownSpellID(info)
    if spellID then
        GameTooltip:SetOwner(itemFrame, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(spellID, false)
        GameTooltip:Show()
    end
end

function Module:OnInjectedItemLeave()
    GameTooltip_Hide()
end

function Module:OnInjectedGlobalMouseUp(button)
    local drag = self.dragState
    if not drag then
        return
    end

    if drag.eatNextGlobalMouseUp == button then
        drag.eatNextGlobalMouseUp = nil
        return
    end

    if PlaySound and SOUNDKIT and SOUNDKIT.UI_CURSOR_DROP_OBJECT then
        PlaySound(SOUNDKIT.UI_CURSOR_DROP_OBJECT)
    end

    if button == "LeftButton" then
        self:EndInjectedOrderChange(true)
    elseif button == "RightButton" then
        self:EndInjectedOrderChange(false)
    end
end

function Module:UpdateInjectedReorderMarker()
    local drag = self.dragState
    if not drag then
        return
    end

    local marker = self.reorderMarker
    if not marker then
        return
    end

    local targetCategory = drag.targetCategory
    if not targetCategory then
        marker:Hide()
        return
    end

    local cursorX, cursorY = GetCursorPosition()
    local scale = GetAppropriateTopLevelParent():GetScale()
    cursorX, cursorY = cursorX / scale, cursorY / scale

    local targetItem = targetCategory:GetBestCooldownItemTarget(cursorX, cursorY)
    marker:SetShown(targetItem ~= nil)
    if not targetItem then
        return
    end

    drag.targetItem = targetItem
    marker:ClearAllPoints()
    marker:SetVertical()
    local centerX = targetItem:GetCenter()
    if centerX and cursorX < centerX then
        marker:SetPoint("CENTER", targetItem, "LEFT", -4, 0)
        drag.reorderOffset = 0
    else
        marker:SetPoint("CENTER", targetItem, "RIGHT", 4, 0)
        drag.reorderOffset = 1
    end
end

function Module:EndInjectedOrderChange(applyDrop)
    local drag = self.dragState
    if not drag then
        return
    end

    local sourceData = self:GetInjectedItemData(drag.sourceItem)
    local targetCategoryData = drag.targetCategory and self:StateGet(drag.targetCategory, "categoryData")
    local targetItemData = self:GetInjectedItemData(drag.targetItem)

    if applyDrop and sourceData and sourceData.cooldownID and targetCategoryData then
        local cooldownID = sourceData.cooldownID
        local sourceBucket = sourceData.bucketKey
        local sourceAssignmentIndex = sourceData.assignmentIndex
        local targetBucket = targetCategoryData.bucketKey

        if targetBucket == Module.NOT_TRACKED_KEY then
            self:UnassignCooldownID(cooldownID)
        elseif targetBucket and targetBucket ~= Module.NOT_TRACKED_KEY then
            local destIndex
            if targetItemData and not targetItemData.isEmpty and targetItemData.assignmentIndex then
                destIndex = targetItemData.assignmentIndex + (drag.reorderOffset or 0)
            else
                local list = self:GetBucketCooldownIDs(targetBucket)
                destIndex = #list + 1
            end

            if sourceBucket == targetBucket and sourceAssignmentIndex and destIndex and sourceAssignmentIndex < destIndex then
                destIndex = destIndex - 1
            end

            self:AssignCooldownToBucket(cooldownID, targetBucket, destIndex)
        end
    end

    if drag.sourceItem and drag.sourceItem.RefreshIconState then
        drag.sourceItem:SetReorderLocked(false)
    end

    if self.reorderMarker then
        self.reorderMarker:Hide()
    end
    if self.dragCursor then
        self.dragCursor:Hide()
    end
    if self.dragWatcher then
        self.dragWatcher:UnregisterEvent("GLOBAL_MOUSE_UP")
        self.dragWatcher:Hide()
    end
    SetDragMarkerUpdateEnabled(self, false)

    self.dragState = nil
    self:RequestRefresh()
end

function Module:BeginInjectedOrderChange(settingsFrame, itemFrame, eatNextGlobalMouseUp)
    if self.dragState then
        return
    end

    local itemData = self:GetInjectedItemData(itemFrame)
    if not itemData or itemData.isEmpty or not itemData.cooldownID then
        return
    end

    local marker = EnsureReorderMarker(self, settingsFrame)
    local cursor = EnsureDragCursor(self)
    local watcher = EnsureDragWatcher(self)

    self.dragState = {
        settingsFrame = settingsFrame,
        sourceItem = itemFrame,
        targetCategory = self:StateGet(itemFrame, "categoryFrame"),
        targetItem = itemFrame,
        reorderOffset = 0,
        eatNextGlobalMouseUp = eatNextGlobalMouseUp,
    }

    itemFrame:SetReorderLocked(true)
    marker:Hide()
    cursor:SetToCursor(itemFrame)

    watcher:RegisterEvent("GLOBAL_MOUSE_UP")
    watcher:Show()
    SetDragMarkerUpdateEnabled(self, true)
end

function Module:InitializeInjectedItem(settingsFrame, itemFrame, categoryFrame)
    if self:StateGet(itemFrame, "injectedInitialized", false) then
        self:StateSet(itemFrame, "categoryFrame", categoryFrame)
        return
    end

    itemFrame:SetScript("OnDragStart", function(frame)
        if PlaySound and SOUNDKIT and SOUNDKIT.UI_CURSOR_PICKUP_OBJECT then
            PlaySound(SOUNDKIT.UI_CURSOR_PICKUP_OBJECT)
        end
        Module:BeginInjectedOrderChange(settingsFrame, frame)
    end)

    itemFrame:SetScript("OnMouseUp", function(frame, button, upInside)
        if not upInside then
            return
        end
        if button == "LeftButton" then
            if PlaySound and SOUNDKIT and SOUNDKIT.UI_CURSOR_PICKUP_OBJECT then
                PlaySound(SOUNDKIT.UI_CURSOR_PICKUP_OBJECT)
            end
            Module:BeginInjectedOrderChange(settingsFrame, frame, button)
        elseif button == "RightButton" then
            local data = Module:GetInjectedItemData(frame)
            if data and data.cooldownID then
                Module:UnassignCooldownID(data.cooldownID)
                Module:RequestRefresh()
            end
        end
    end)

    itemFrame:SetScript("OnEnter", function(frame)
        Module:OnInjectedItemEnter(frame)
    end)

    itemFrame:SetScript("OnLeave", function()
        Module:OnInjectedItemLeave()
    end)

    self:StateSet(itemFrame, "injectedInitialized", true)
    self:StateSet(itemFrame, "categoryFrame", categoryFrame)
end

function Module:DoesCooldownIDMatchFilter(cooldownID, filterText)
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

function Module:LayoutInjectedCategory(settingsFrame, categoryFrame, categoryData, filterText)
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

function Module:EnsureInjectedCategory(settingsFrame, bucketKey)
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
        Module:OnInjectedCategoryEnter(frame)
    end)
    if categoryFrame.Container then
        categoryFrame.Container:HookScript("OnEnter", function()
            Module:OnInjectedCategoryEnter(categoryFrame)
        end)
    end

    state.categories[bucketKey] = categoryFrame
    self:StateSet(categoryFrame, "categoryData", { bucketKey = bucketKey, cooldownIDs = {} })
    return categoryFrame
end

function Module:HideNativeSettingsContent(settingsFrame)
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

function Module:RestoreNativeSettingsContent(settingsFrame)
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

function Module:HideRefineTabPanel(settingsFrame)
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

function Module:ShowRefineTabPanel(settingsFrame)
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

function Module:RequestRefineTabPanelRefresh(settingsFrame)
    local state = GetSettingsState(self, settingsFrame)
    if state.panelRefreshQueued then
        return
    end

    state.panelRefreshQueued = true
    local function RunRefresh()
        state.panelRefreshQueued = nil
        if settingsFrame and settingsFrame:IsShown() then
            Module:RefreshRefineTabPanel(settingsFrame)
        end
    end

    if RefineUI.After then
        RefineUI:After(PANEL_REFRESH_TIMER_KEY, 0, RunRefresh)
    else
        RunRefresh()
    end
end

function Module:RefreshRefineTabPanel(settingsFrame)
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
        [Module.NOT_TRACKED_KEY] = { cooldownIDs = notTrackedIDs, assignmentIndices = nil },
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

local function IsShowingUnlearned()
    return GetCVarBool and GetCVarBool("cooldownViewerShowUnlearned") or false
end

local function ToggleShowUnlearned()
    SetCVar("cooldownViewerShowUnlearned", not IsShowingUnlearned())
end

function Module:EnsureRefineTabPanel(settingsFrame)
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
                Module:RequestRefineTabPanelRefresh(settingsFrame)
            end)
        else
            Module:RequestRefineTabPanelRefresh(settingsFrame)
        end
    end)
    panel.SearchBox = searchBox

    local settingsDropdown = CreateFrame("DropdownButton", nil, panel, "UIPanelIconDropdownButtonTemplate")
    settingsDropdown:SetPoint("LEFT", searchBox, "RIGHT", 5, 0)
    if settingsDropdown.SetupMenu then
        settingsDropdown:SetupMenu(function(_owner, rootDescription)
            rootDescription:CreateCheckbox(COOLDOWN_VIEWER_SETTINGS_SHOW_UNLEARNED or "Show Unlearned", IsShowingUnlearned, function()
                ToggleShowUnlearned()
                Module:RequestRefresh()
            end)
        end)
    end
    panel.SettingsDropdown = settingsDropdown

    local sourceNote = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sourceNote:SetPoint("TOPLEFT", panel, "TOPLEFT", 72, -59)
    sourceNote:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -48, -59)
    sourceNote:SetJustifyH("LEFT")
    sourceNote:SetText("RefineUI list mirrors Blizzard Buffs. Add/remove tracked buffs in Blizzard Buffs tab.")
    panel.SourceNote = sourceNote

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "ScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 17, -90)
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
        Module:RequestRefineTabPanelRefresh(settingsFrame)
    end)

    panel:HookScript("OnShow", function()
        scrollChild:SetWidth(scrollFrame:GetWidth())
        Module:RequestRefineTabPanelRefresh(settingsFrame)
    end)

    panel.ScrollFrame = scrollFrame
    panel.ScrollChild = scrollChild

    state.panel = panel
    state.filterText = state.filterText or ""
    return panel
end

function Module:EnsureRefineTabButton(settingsFrame)
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
        Module:ShowRefineTabPanel(settingsFrame)
    end)
    tab:Hide()

    RefineUI:HookOnce("CooldownAuraTrackers:Settings:RefineTab:SetChecked", tab, "SetChecked", function()
        ApplyCustomTabIcon(tab)
    end)
    RefineUI:HookScriptOnce("CooldownAuraTrackers:Settings:RefineTab:OnShow", tab, "OnShow", function()
        ApplyCustomTabIcon(tab)
    end)

    state.tabButton = tab
    return tab
end

function Module:InstallSettingsHooks()
    local settingsFrame = self:GetCooldownViewerSettingsFrame()
    if not settingsFrame or self.settingsHooksInstalled then
        return
    end

    self:EnsureRefineTabPanel(settingsFrame)
    self:EnsureRefineTabButton(settingsFrame)

    RefineUI:HookOnce("CooldownAuraTrackers:Settings:SetDisplayMode", settingsFrame, "SetDisplayMode", function(_, mode)
        local state = GetSettingsState(Module, settingsFrame)
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
        Module:HideRefineTabPanel(settingsFrame)
        Module:UpdateAuraModeOverlays(settingsFrame, mode)
    end)
    RefineUI:HookScriptOnce("CooldownAuraTrackers:Settings:OnShow", settingsFrame, "OnShow", function()
        local state = GetSettingsState(Module, settingsFrame)
        if state.tabButton then
            if settingsFrame.AurasTab then
                state.tabButton:ClearAllPoints()
                state.tabButton:SetPoint("TOP", settingsFrame.AurasTab, "BOTTOM", 0, -3)
            end
            state.tabButton:Show()
        end
        Module:HideRefineTabPanel(settingsFrame)
        Module:UpdateAuraModeOverlays(settingsFrame, state.currentDisplayMode or settingsFrame.displayMode)
    end)
    RefineUI:HookScriptOnce("CooldownAuraTrackers:Settings:OnHide", settingsFrame, "OnHide", function()
        local state = GetSettingsState(Module, settingsFrame)
        if state.tabButton then
            state.tabButton:Hide()
        end
        if RefineUI.CancelDebounce then
            RefineUI:CancelDebounce(SEARCH_DEBOUNCE_KEY)
        end
        if RefineUI.CancelTimer then
            RefineUI:CancelTimer(PANEL_REFRESH_TIMER_KEY)
        end
        Module:HideRefineTabPanel(settingsFrame)
        Module:UpdateAuraModeOverlays(settingsFrame, state.currentDisplayMode)
        Module:EndInjectedOrderChange(false)
        if Module.ShowReloadRecommendationIfPending then
            Module:ShowReloadRecommendationIfPending()
        end
    end)

    local state = GetSettingsState(self, settingsFrame)
    if state.tabButton then
        state.tabButton:SetShown(settingsFrame:IsShown())
    end

    self.settingsHooksInstalled = true
end

function Module:InitializeSettingsInjection()
    local function TryInstall()
        Module:InstallSettingsHooks()
    end

    RefineUI:RegisterEventCallback("ADDON_LOADED", function(_event, addonName)
        if addonName == "Blizzard_CooldownViewer" then
            TryInstall()
        end
    end, "CooldownAuraTrackers:SettingsAddonLoaded")

    if self:GetCooldownViewerSettingsFrame() then
        TryInstall()
    end
end

function Module:RefreshSettingsSection()
    local settingsFrame = self:GetCooldownViewerSettingsFrame()
    if settingsFrame and settingsFrame:IsShown() then
        if self.ProcessPendingTrackedBuffSync then
            self:ProcessPendingTrackedBuffSync()
        end
        self:RefreshRefineTabPanel(settingsFrame)
        self:UpdateAuraModeOverlays(settingsFrame)
    end
end
