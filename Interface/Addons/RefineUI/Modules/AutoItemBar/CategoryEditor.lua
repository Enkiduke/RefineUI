----------------------------------------------------------------------------------------
-- AutoItemBar Component: CategoryEditor
-- Description: Configuration window for filtering and sorting categories.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local AutoItemBar = RefineUI:GetModule("AutoItemBar")
if not AutoItemBar then return end

local floor = math.floor
local min = math.min
local max = math.max
local tinsert = table.insert
local ipairs = ipairs
local GetCursorPosition = GetCursorPosition
local IsMouseButtonDown = IsMouseButtonDown
local GetItemInfo = C_Item.GetItemInfo
local UIParent = UIParent

----------------------------------------------------------------------------------------
--	Constants
----------------------------------------------------------------------------------------

local MAIN_WINDOW_NAME = "RefineUI_AutoItemBarCategoryManager"
local WINDOW_TEMPLATE = "ResizeLayoutFrame"
local BORDER_TEMPLATE = "DialogBorderTranslucentTemplate"

local CATEGORY_ROW_HEIGHT = 24
local CATEGORY_ROW_SPACING = 2
local CONTENT_WIDTH_PADDING = 2

local ENABLED_BG = { 0.09, 0.19, 0.13, 0.78 }
local DISABLED_BG = { 0.22, 0.1, 0.11, 0.7 }
local ENABLED_TEXT = { 0.58, 0.95, 0.62 }
local DISABLED_TEXT = { 0.96, 0.6, 0.6 }
local ENABLED_BORDER = { 0.34, 0.56, 0.38, 0.65 }
local DISABLED_BORDER = { 0.6, 0.34, 0.34, 0.55 }
local HIGHLIGHT_BORDER = { 1, 0.82, 0.2, 0.95 }
local CUSTOM_BG = { 0.09, 0.13, 0.21, 0.8 }
local CUSTOM_TEXT = { 0.68, 0.83, 1.0 }
local CUSTOM_BORDER = { 0.3, 0.45, 0.7, 0.7 }
local DRAG_TEXTURE = "Interface\\AddOns\\RefineUI\\Media\\Textures\\drag.blp"
local ROW_BACKDROP = {
    bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
    edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]],
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

local function GetItemDisplayName(itemID)
    return GetItemInfo(itemID) or ("Item #" .. itemID)
end

function AutoItemBar:IsSettingsDialogForAutoItemBar(selection)
    local lib = RefineUI.LibEditMode
    local dialog = lib and lib.internal and lib.internal.dialog
    local activeSelection = selection or (dialog and dialog.selection)
    return activeSelection and self.Mover and activeSelection.parent == self.Mover
end

local function ApplyRowColors(row, bg, text, border)
    row.bg:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
    row.text:SetTextColor(text[1], text[2], text[3])
    row.order:SetTextColor(text[1], text[2], text[3], 0.9)
    row.dragHandle.icon:SetVertexColor(text[1], text[2], text[3], 0.95)
    row.border:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
end

function AutoItemBar:UpdateCategoryRowVisual(row, enabled)
    if enabled then
        ApplyRowColors(row, ENABLED_BG, ENABLED_TEXT, ENABLED_BORDER)
    else
        ApplyRowColors(row, DISABLED_BG, DISABLED_TEXT, DISABLED_BORDER)
    end
end

function AutoItemBar:UpdateCustomRowVisual(row)
    ApplyRowColors(row, CUSTOM_BG, CUSTOM_TEXT, CUSTOM_BORDER)
end

function AutoItemBar:HandleCategoryMouseWheel(delta)
    local window = self.CategoryManagerWindow
    if not window then
        return
    end

    local scroll = window.Scroll
    local step = (CATEGORY_ROW_HEIGHT + CATEGORY_ROW_SPACING) * 2
    local nextOffset = (scroll:GetDerivedScrollOffset() or 0) - (delta * step)
    if nextOffset < 0 then
        nextOffset = 0
    end
    scroll:ScrollToOffset(nextOffset)
    scroll:FullUpdate(ScrollBoxConstants.UpdateImmediately)
end

----------------------------------------------------------------------------------------
--	View Hierarchy
----------------------------------------------------------------------------------------

local function OnRowMouseDown(row, button)
    if button ~= "LeftButton" or row.check:IsMouseOver() then
        return
    end
    if row._entryType == "item" then
        AutoItemBar:StartCustomItemDrag(row.itemID)
    else
        AutoItemBar:StartCategoryDrag(row.categoryKey, row.enabled)
    end
end

local function OnRowMouseUp(row, button)
    if button ~= "LeftButton" then
        return
    end
    if row._entryType == "item" and AutoItemBar._customDragItemID then
        AutoItemBar:FinishCustomItemDrag()
    elseif row._entryType == "category" and AutoItemBar._categoryDragKey then
        AutoItemBar:FinishCategoryDrag()
    end
end

local function OnRowCheckClick(check)
    local row = check:GetParent()
    if row._entryType == "item" then
        if not check:GetChecked() then
            AutoItemBar:RemoveTrackedItem(row.itemID)
        else
            check:SetChecked(true)
        end
    else
        AutoItemBar:SetTrackingCategoryEnabled(row.categoryKey, check:GetChecked() and true or false)
    end
end

local function CreateRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(CATEGORY_ROW_HEIGHT)
    row:EnableMouse(true)
    row:RegisterForClicks("LeftButtonUp")

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()

    row.border = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.border:SetAllPoints()
    row.border:SetBackdrop(ROW_BACKDROP)
    row.border:SetBackdropColor(0, 0, 0, 0)

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetAtlas("Options_List_Hover")
    row.highlight:SetAlpha(0.35)

    row.separator = row:CreateTexture(nil, "BORDER")
    row.separator:SetPoint("BOTTOMLEFT", 8, 0)
    row.separator:SetPoint("BOTTOMRIGHT", -8, 0)
    row.separator:SetHeight(1)
    row.separator:SetColorTexture(1, 1, 1, 0.07)

    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetPoint("RIGHT", -8, 0)
    row.check:SetScript("OnClick", OnRowCheckClick)

    row.dragHandle = CreateFrame("Frame", nil, row)
    row.dragHandle:SetSize(12, 12)
    row.dragHandle:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.dragHandle:SetFrameLevel(row:GetFrameLevel() + 2)
    row.dragHandle:SetAlpha(0.85)

    row.dragHandle.icon = row.dragHandle:CreateTexture(nil, "ARTWORK")
    row.dragHandle.icon:SetAllPoints()
    row.dragHandle.icon:SetTexture(DRAG_TEXTURE)

    row.order = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.order:SetPoint("LEFT", row.dragHandle, "RIGHT", 6, 0)
    row.order:SetJustifyH("LEFT")

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.text:SetPoint("LEFT", row.order, "RIGHT", 6, 0)
    row.text:SetPoint("RIGHT", row.check, "LEFT", -18, 0)
    row.text:SetJustifyH("LEFT")

    row:SetScript("OnMouseDown", OnRowMouseDown)
    row:SetScript("OnMouseUp", OnRowMouseUp)

    return row
end

local function PlaceRow(row, visualIndex)
    local offset = -((visualIndex - 1) * (CATEGORY_ROW_HEIGHT + CATEGORY_ROW_SPACING))
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, offset)
    row:SetPoint("TOPRIGHT", -2, offset)
    row.order:SetText(("%d."):format(visualIndex))
end

function AutoItemBar:EnsureCategoryManagerWindow()
    if self.CategoryManagerWindow then
        return self.CategoryManagerWindow
    end

    local window = CreateFrame("Frame", MAIN_WINDOW_NAME, UIParent, WINDOW_TEMPLATE)
    window:SetFrameStrata("DIALOG")
    window:SetFrameLevel(220)
    window:SetSize(300, 350)
    window.widthPadding = 40
    window.heightPadding = 40
    window:Hide()
    window:EnableMouse(true)

    local border = CreateFrame("Frame", nil, window, BORDER_TEMPLATE)
    border.ignoreInLayout = true
    window.Border = border

    local closeButton = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT")
    closeButton.ignoreInLayout = true
    closeButton:HookScript("OnClick", function()
        AutoItemBar:HideCategoryManagerWindow()
    end)
    window.Close = closeButton

    local title = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Tracked Categories")
    window.Title = title

    local subtitle = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", window, "TOPLEFT", 14, -36)
    subtitle:SetPoint("TOPRIGHT", window, "TOPRIGHT", -36, -36)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetJustifyV("TOP")
    subtitle:SetText("Drag enabled rows to reorder. Disable to move to the locked bottom section.")
    window.Subtitle = subtitle

    local divider = window:CreateTexture(nil, "ARTWORK")
    divider:SetTexture([[Interface\FriendsFrame\UI-FriendsFrame-OnlineDivider]])
    divider:SetSize(330, 16)
    divider:SetPoint("TOP", subtitle, "BOTTOM", 0, -2)
    window.Divider = divider

    local listContainer = CreateFrame("Frame", nil, window, "InsetFrameTemplate")
    listContainer:SetPoint("TOPLEFT", window, "TOPLEFT", 12, -66)
    listContainer:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -12, 44)
    window.ListContainer = listContainer

    local scroll = CreateFrame("Frame", nil, listContainer, "WowScrollBox")
    scroll:SetPoint("TOPLEFT", listContainer, "TOPLEFT", 4, -6)
    scroll:SetPoint("BOTTOMRIGHT", listContainer, "BOTTOMRIGHT", -18, 6)
    scroll:SetInterpolateScroll(true)
    scroll:EnableMouseWheel(true)

    local scrollBar = CreateFrame("EventFrame", nil, listContainer, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, -2)
    scrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 2, 0)
    scrollBar:SetHideIfUnscrollable(true)
    scrollBar:SetInterpolateScroll(true)

    local scrollView = CreateScrollBoxLinearView()
    scrollView:SetPanExtent(14)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    content.scrollable = true
    content:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    content:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, 0)
    ScrollUtil.InitScrollBoxWithScrollBar(scroll, scrollBar, scrollView)
    scroll:SetScrollTarget(content)

    window.Scroll = scroll
    window.ScrollBar = scrollBar
    window.ScrollView = scrollView
    window.Content = content
    window.Rows = {}

    local insertLine = content:CreateTexture(nil, "OVERLAY")
    insertLine:SetHeight(2)
    insertLine:SetColorTexture(1, 0.84, 0.28, 0.95)
    insertLine:Hide()
    window.InsertLine = insertLine

    local dragGhost = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    dragGhost:SetFrameStrata("DIALOG")
    dragGhost:SetFrameLevel(window:GetFrameLevel() + 40)
    dragGhost:SetSize(220, CATEGORY_ROW_HEIGHT)
    RefineUI.SetTemplate(dragGhost, "Transparent")
    dragGhost:SetAlpha(0.95)
    dragGhost:EnableMouse(false)
    dragGhost:Hide()

    dragGhost.bg = dragGhost:CreateTexture(nil, "BACKGROUND")
    dragGhost.bg:SetAllPoints()
    dragGhost.bg:SetColorTexture(0.9, 0.74, 0.18, 0.35)

    dragGhost.text = dragGhost:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    dragGhost.text:SetPoint("LEFT", 8, 0)
    dragGhost.text:SetPoint("RIGHT", -8, 0)
    dragGhost.text:SetJustifyH("LEFT")
    dragGhost.text:SetTextColor(1, 0.95, 0.75)
    window.DragGhost = dragGhost

    local resetButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    resetButton:SetSize(130, 22)
    resetButton:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -14, 14)
    resetButton:SetText("Reset to Default")
    resetButton:SetScript("OnClick", function()
        AutoItemBar:ResetCategoryManagerDefaults()
    end)
    window.ResetButton = resetButton

    scroll:SetScript("OnSizeChanged", function(scrollSelf, width)
        content:SetWidth(max((width or scrollSelf:GetWidth() or 1) - CONTENT_WIDTH_PADDING, 1))
    end)
    local function OnMouseWheel(_, delta)
        AutoItemBar:HandleCategoryMouseWheel(delta)
    end
    listContainer:EnableMouseWheel(true)
    listContainer:SetScript("OnMouseWheel", OnMouseWheel)
    content:EnableMouseWheel(true)
    content:SetScript("OnMouseWheel", OnMouseWheel)

    window:SetScript("OnMouseUp", function(_, mouseButton)
        if mouseButton == "LeftButton" then
            if self._categoryDragKey then
                self:FinishCategoryDrag()
            elseif self._customDragItemID then
                self:FinishCustomItemDrag()
            end
        end
    end)

    self.CategoryManagerWindow = window
    return window
end

----------------------------------------------------------------------------------------
--	Drag and Drop
----------------------------------------------------------------------------------------

local function OnDragUpdate()
    AutoItemBar:UpdateCategoryDrag()
end

local function FindEnabledIndex(token)
    for index, entry in ipairs(AutoItemBar:GetConfig().EnabledOrder) do
        if entry == token then
            return index
        end
    end
end

function AutoItemBar:BeginDrag(label)
    local window = self:EnsureCategoryManagerWindow()
    local ghost = window.DragGhost
    ghost.text:SetText(label or "")
    ghost:SetFrameStrata(window:GetFrameStrata())
    ghost:SetFrameLevel(window:GetFrameLevel() + 40)
    ghost:Show()
    window:SetScript("OnUpdate", OnDragUpdate)
    self:RefreshCategoryManagerWindow()
end

function AutoItemBar:EndDrag()
    local window = self.CategoryManagerWindow
    if window then
        window:SetScript("OnUpdate", nil)
        window.InsertLine:Hide()
        window.DragGhost:Hide()
    end
end

function AutoItemBar:StartCategoryDrag(categoryKey, enabled)
    if not enabled then return end
    if self._customDragItemID then
        self:FinishCustomItemDrag()
    end

    local definition = self:GetCategoryByKey(categoryKey)
    self._categoryDragKey = categoryKey
    self._categoryInsertIndex = FindEnabledIndex(self:GetCategoryToken(categoryKey)) or 1
    self._categoryDragWasMoved = false
    self:BeginDrag(definition and definition.label)
end

function AutoItemBar:StartCustomItemDrag(itemID)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then return end
    if self._categoryDragKey then
        self:FinishCategoryDrag()
    end

    local startIndex = FindEnabledIndex(self:GetItemToken(itemID))
    if not startIndex then
        return
    end

    self._customDragItemID = itemID
    self._customInsertIndex = startIndex
    self._customDragWasMoved = false
    self:BeginDrag(GetItemDisplayName(itemID))
end

-- EnabledOrder holds exactly the enabled entries, and the dragged entry is one of
-- them, so the last valid insert position is its length.
function AutoItemBar:GetEnabledInsertIndexFromCursor()
    local content = self.CategoryManagerWindow.Content
    local _, cursorY = GetCursorPosition()
    local offset = content:GetTop() - (cursorY / content:GetEffectiveScale())
    local step = CATEGORY_ROW_HEIGHT + CATEGORY_ROW_SPACING
    local rawIndex = floor((offset + (step * 0.5)) / step) + 1

    return min(max(rawIndex, 1), #self:GetConfig().EnabledOrder)
end

function AutoItemBar:UpdateCategoryDrag()
    local window = self.CategoryManagerWindow
    if not window:IsShown() or not IsMouseButtonDown("LeftButton") then
        if self._categoryDragKey then
            self:FinishCategoryDrag()
        elseif self._customDragItemID then
            self:FinishCustomItemDrag()
        end
        return
    end

    local insertIndex = self:GetEnabledInsertIndexFromCursor()
    if self._categoryDragKey then
        if insertIndex ~= self._categoryInsertIndex then
            self._categoryInsertIndex = insertIndex
            self._categoryDragWasMoved = true
            self:RefreshCategoryManagerWindow()
        end
    elseif self._customDragItemID then
        if insertIndex ~= self._customInsertIndex then
            self._customInsertIndex = insertIndex
            self._customDragWasMoved = true
            self:RefreshCategoryManagerWindow()
        end
    end

    local cursorX, cursorY = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    local ghost = window.DragGhost
    ghost:ClearAllPoints()
    ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cursorX / scale, cursorY / scale)
end

function AutoItemBar:FinishCategoryDrag()
    if not self._categoryDragKey then return end

    local dragKey = self._categoryDragKey
    local insertIndex = self._categoryInsertIndex or 1
    local wasMoved = self._categoryDragWasMoved == true

    self._categoryDragKey = nil
    self._categoryInsertIndex = nil
    self._categoryDragWasMoved = nil
    self:EndDrag()

    if wasMoved then
        self:MoveCategoryToEnabledIndex(dragKey, insertIndex)
    else
        self:RefreshCategoryManagerWindow()
    end
end

function AutoItemBar:FinishCustomItemDrag()
    if not self._customDragItemID then return end

    local dragItemID = self._customDragItemID
    local insertIndex = self._customInsertIndex or 1
    local wasMoved = self._customDragWasMoved == true

    self._customDragItemID = nil
    self._customInsertIndex = nil
    self._customDragWasMoved = nil
    self:EndDrag()

    if wasMoved then
        self:MoveTrackedItemToIndex(dragItemID, insertIndex)
    else
        self:RefreshCategoryManagerWindow()
    end
end

----------------------------------------------------------------------------------------
--	Rendering
----------------------------------------------------------------------------------------

function AutoItemBar:RefreshCategoryManagerWindow()
    local window = self.CategoryManagerWindow
    if not window or not window:IsShown() then
        return
    end

    local rows = window.Rows
    local enabledEntries = self:GetEnabledEntries()
    local disabledCategories = {}
    for _, category in ipairs(self:GetOrderedCategories(true)) do
        if not category.enabled then
            tinsert(disabledCategories, category)
        end
    end

    local contentWidth = max((window.Scroll:GetWidth() or 1) - CONTENT_WIDTH_PADDING, 1)
    window.Content:SetWidth(contentWidth)
    window.DragGhost:SetWidth(contentWidth)

    local activeDragToken
    local placeholderIndex
    if self._categoryDragKey then
        activeDragToken = self:GetCategoryToken(self._categoryDragKey)
        placeholderIndex = self._categoryInsertIndex
    elseif self._customDragItemID then
        activeDragToken = self:GetItemToken(self._customDragItemID)
        placeholderIndex = self._customInsertIndex
    end

    local enabledCountExcludingDrag = #enabledEntries
    if activeDragToken then
        enabledCountExcludingDrag = enabledCountExcludingDrag - 1
        placeholderIndex = min(max(placeholderIndex or 1, 1), enabledCountExcludingDrag + 1)
    end

    local renderedCount = 0
    local enabledOrdinal = 0

    for _, entry in ipairs(enabledEntries) do
        if not (activeDragToken and entry.token == activeDragToken) then
            renderedCount = renderedCount + 1
            local row = rows[renderedCount]
            if not row then
                row = CreateRow(window.Content)
                rows[renderedCount] = row
            end

            enabledOrdinal = enabledOrdinal + 1
            local visualIndex = enabledOrdinal
            if placeholderIndex and visualIndex >= placeholderIndex then
                visualIndex = visualIndex + 1
            end

            PlaceRow(row, visualIndex)
            row._entryType = entry.type
            row.categoryKey = entry.key
            row.itemID = entry.itemID
            row.enabled = true
            row.dragHandle:Show()
            row.check:SetChecked(true)
            row.check:Enable()
            if entry.type == "item" then
                row.text:SetText(GetItemDisplayName(entry.itemID))
                self:UpdateCustomRowVisual(row)
            else
                row.text:SetText(entry.label)
                self:UpdateCategoryRowVisual(row, true)
            end
            row:Show()
        end
    end

    local disabledStartIndex = enabledCountExcludingDrag
    if placeholderIndex then
        disabledStartIndex = disabledStartIndex + 1
    end

    for disabledOrdinal, category in ipairs(disabledCategories) do
        renderedCount = renderedCount + 1
        local row = rows[renderedCount]
        if not row then
            row = CreateRow(window.Content)
            rows[renderedCount] = row
        end

        PlaceRow(row, disabledStartIndex + disabledOrdinal)
        row._entryType = "category"
        row.categoryKey = category.key
        row.itemID = nil
        row.enabled = false
        row.dragHandle:Hide()
        row.text:SetText(category.label)
        row.check:SetChecked(false)
        row.check:Enable()
        self:UpdateCategoryRowVisual(row, false)
        row:Show()
    end

    for index = renderedCount + 1, #rows do
        rows[index]:Hide()
    end

    local step = CATEGORY_ROW_HEIGHT + CATEGORY_ROW_SPACING
    if activeDragToken then
        local lineOffset = (placeholderIndex - 1) * step
        window.InsertLine:ClearAllPoints()
        window.InsertLine:SetPoint("TOPLEFT", window.Content, "TOPLEFT", 0, -lineOffset)
        window.InsertLine:SetPoint("TOPRIGHT", window.Content, "TOPRIGHT", -2, -lineOffset)
        window.InsertLine:Show()
    else
        window.InsertLine:Hide()
    end

    local totalRows = #enabledEntries + #disabledCategories
    if activeDragToken then
        totalRows = totalRows + 1
    end
    window.Content:SetHeight(max(totalRows * step, 1))
    window.Scroll:FullUpdate(ScrollBoxConstants.UpdateImmediately)
end

function AutoItemBar:HideCategoryManagerWindow()
    self:EndDrag()
    if self.CategoryManagerWindow then
        self.CategoryManagerWindow:Hide()
    end
    self._categoryDragKey = nil
    self._categoryInsertIndex = nil
    self._categoryDragWasMoved = nil
    self._customDragItemID = nil
    self._customInsertIndex = nil
    self._customDragWasMoved = nil
end

function AutoItemBar:RefreshCategoryManagerVisibility(selection)
    local lib = RefineUI.LibEditMode
    local dialog = lib and lib.internal and lib.internal.dialog

    if not self._editModeActive
        or not dialog or not dialog:IsShown()
        or not self:IsSettingsDialogForAutoItemBar(selection) then
        self:HideCategoryManagerWindow()
        self:HideEditModeTutorial(false)
        return
    end

    local window = self:EnsureCategoryManagerWindow()
    window:ClearAllPoints()
    window:SetFrameStrata(dialog:GetFrameStrata() or "DIALOG")
    window:SetFrameLevel((dialog:GetFrameLevel() or 200) + 10)
    window:SetWidth(dialog:GetWidth() or 300)
    window:SetPoint("TOPRIGHT", dialog, "TOPLEFT", -8, 0)
    window:SetHeight(dialog:GetHeight())
    window:Show()
    self:RefreshCategoryManagerWindow()
    self:TryShowEditModeTutorial()
end

function AutoItemBar:HookCategoryManagerToDialog()
    if self._categoryDialogHooked then return end

    local lib = RefineUI.LibEditMode
    local dialog = lib and lib.internal and lib.internal.dialog
    if not dialog then return end

    hooksecurefunc(dialog, "Update", function(_, selection)
        AutoItemBar:RefreshCategoryManagerVisibility(selection)
    end)
    dialog:HookScript("OnShow", function()
        AutoItemBar:RefreshCategoryManagerVisibility()
    end)
    dialog:HookScript("OnHide", function()
        AutoItemBar:HideCategoryManagerWindow()
    end)

    self._categoryDialogHooked = true
end
