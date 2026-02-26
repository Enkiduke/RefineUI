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
local type = type
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
local CUSTOM_HIDDEN_BG = { 0.22, 0.1, 0.11, 0.72 }
local CUSTOM_HIDDEN_TEXT = { 0.95, 0.6, 0.6 }
local CUSTOM_HIDDEN_BORDER = { 0.6, 0.34, 0.34, 0.55 }
local DRAG_TEXTURE = "Interface\\AddOns\\RefineUI\\Media\\Textures\\drag.blp"

local function GetItemDisplayName(itemID)
    if not itemID then
        return "Unknown Item"
    end

    local info = GetItemInfo and GetItemInfo(itemID)
    if type(info) == "table" then
        local name = info.name or info.itemName
        if type(name) == "string" and name ~= "" then
            return name
        end
    elseif type(info) == "string" and info ~= "" then
        return info
    end

    return "Item #" .. itemID
end

function AutoItemBar:IsSettingsDialogForAutoItemBar(selection)
    local lib = RefineUI.LibEditMode
    local dialog = lib and lib.internal and lib.internal.dialog
    local activeSelection = selection or (dialog and dialog.selection)
    return activeSelection and self.Mover and activeSelection.parent == self.Mover
end

function AutoItemBar:UpdateCategoryRowVisual(row, enabled, isDropTarget)
    if not row or not row.bg or not row.text then return end
    local bg = enabled and ENABLED_BG or DISABLED_BG
    local text = enabled and ENABLED_TEXT or DISABLED_TEXT
    local border = enabled and ENABLED_BORDER or DISABLED_BORDER

    if isDropTarget then
        row.bg:SetColorTexture(0.95, 0.8, 0.15, 0.78)
        row.text:SetTextColor(1, 0.95, 0.75)
        if row.order then
            row.order:SetTextColor(1, 0.95, 0.75)
        end
        if row.dragHandle and row.dragHandle.icon then
            row.dragHandle.icon:SetVertexColor(1, 0.95, 0.75, 0.95)
        end
        if row.border then
            row.border:SetBackdropBorderColor(HIGHLIGHT_BORDER[1], HIGHLIGHT_BORDER[2], HIGHLIGHT_BORDER[3], HIGHLIGHT_BORDER[4])
        end
    else
        row.bg:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
        row.text:SetTextColor(text[1], text[2], text[3])
        if row.order then
            row.order:SetTextColor(text[1], text[2], text[3], 0.9)
        end
        if row.dragHandle and row.dragHandle.icon then
            row.dragHandle.icon:SetVertexColor(text[1], text[2], text[3], 0.95)
        end
        if row.border then
            row.border:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
        end
    end
end

function AutoItemBar:UpdateCustomRowVisual(row, isHidden)
    if not row or not row.bg or not row.text then return end

    local bg = isHidden and CUSTOM_HIDDEN_BG or CUSTOM_BG
    local text = isHidden and CUSTOM_HIDDEN_TEXT or CUSTOM_TEXT
    local border = isHidden and CUSTOM_HIDDEN_BORDER or CUSTOM_BORDER

    row.bg:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
    row.text:SetTextColor(text[1], text[2], text[3])
    if row.order then
        row.order:SetTextColor(text[1], text[2], text[3], 0.9)
    end
    if row.dragHandle and row.dragHandle.icon then
        row.dragHandle.icon:SetVertexColor(text[1], text[2], text[3], 0.95)
    end
    if row.border then
        row.border:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
    end
end

local function EnsureRowDragHandle(row)
    if not row or row.dragHandle or not row.check then
        return
    end

    row.dragHandle = CreateFrame("Frame", nil, row)
    row.dragHandle:SetSize(12, 12)
    row.dragHandle:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.dragHandle:SetFrameLevel(row:GetFrameLevel() + 2)
    row.dragHandle:SetAlpha(0.85)

    row.dragHandle.icon = row.dragHandle:CreateTexture(nil, "ARTWORK")
    row.dragHandle.icon:SetAllPoints()
    row.dragHandle.icon:SetTexture(DRAG_TEXTURE)
    row.dragHandle.icon:SetVertexColor(0.78, 0.78, 0.78, 0.95)
end

function AutoItemBar:HandleCategoryMouseWheel(delta)
    local window = self.CategoryManagerWindow
    if not window or not window.Scroll then
        return
    end

    local step = (CATEGORY_ROW_HEIGHT + CATEGORY_ROW_SPACING) * 2
    local scroll = window.Scroll

    if scroll.ScrollToOffset and scroll.GetDerivedScrollOffset then
        local current = scroll:GetDerivedScrollOffset() or 0
        local nextOffset = current - (delta * step)
        if nextOffset < 0 then
            nextOffset = 0
        end
        scroll:ScrollToOffset(nextOffset)
        if scroll.FullUpdate then
            local updateNow = ScrollBoxConstants and ScrollBoxConstants.UpdateImmediately or true
            scroll:FullUpdate(updateNow)
        end
        return
    end

    if scroll.GetVerticalScroll and scroll.GetVerticalScrollRange and scroll.SetVerticalScroll then
        local current = scroll:GetVerticalScroll() or 0
        local maxOffset = scroll:GetVerticalScrollRange() or 0
        local nextOffset = current - (delta * step)
        if nextOffset < 0 then
            nextOffset = 0
        elseif nextOffset > maxOffset then
            nextOffset = maxOffset
        end
        scroll:SetVerticalScroll(nextOffset)
    end
end

----------------------------------------------------------------------------------------
--	View Hierarchy
----------------------------------------------------------------------------------------

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

    local hasModernScroll = (type(ScrollUtil) == "table")
        and (type(ScrollUtil.InitScrollBoxWithScrollBar) == "function")
        and (type(CreateScrollBoxLinearView) == "function")

    local scroll
    local content
    local scrollBar
    local scrollView
    local contentWidthPadding = 2
    if hasModernScroll then
        scroll = CreateFrame("Frame", nil, listContainer, "WowScrollBox")
        scroll:SetPoint("TOPLEFT", listContainer, "TOPLEFT", 4, -6)
        scroll:SetPoint("BOTTOMRIGHT", listContainer, "BOTTOMRIGHT", -18, 6)
        scroll:SetInterpolateScroll(true)
        scroll:EnableMouseWheel(true)

        scrollBar = CreateFrame("EventFrame", nil, listContainer, "MinimalScrollBar")
        scrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, -2)
        scrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 2, 0)
        scrollBar:SetHideIfUnscrollable(true)
        scrollBar:SetInterpolateScroll(true)

        scrollView = CreateScrollBoxLinearView()
        scrollView:SetPanExtent(14)
    else
        scroll = CreateFrame("ScrollFrame", nil, listContainer, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", listContainer, "TOPLEFT", 5, -5)
        scroll:SetPoint("BOTTOMRIGHT", listContainer, "BOTTOMRIGHT", -27, 5)
        scroll:EnableMouseWheel(true)
        contentWidthPadding = 6
    end
    window.Scroll = scroll

    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    if hasModernScroll then
        content.scrollable = true
        content:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
        content:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, 0)
        ScrollUtil.InitScrollBoxWithScrollBar(scroll, scrollBar, scrollView)
        if scroll.SetScrollTarget then
            scroll:SetScrollTarget(content)
        end
        window.ScrollBar = scrollBar
        window.ScrollView = scrollView
    else
        scroll:SetScrollChild(content)
    end
    window.Content = content
    window.Rows = {}
    window.CustomRows = {}
    window._contentWidthPadding = contentWidthPadding

    local customHeader = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    customHeader:Hide()
    window.CustomHeader = customHeader

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
        local contentWidth = (width or scrollSelf:GetWidth() or 1) - (window._contentWidthPadding or 6)
        if contentWidth < 1 then
            contentWidth = 1
        end
        content:SetWidth(contentWidth)
    end)
    listContainer:EnableMouseWheel(true)
    listContainer:SetScript("OnMouseWheel", function(_, delta)
        AutoItemBar:HandleCategoryMouseWheel(delta)
    end)
    content:EnableMouseWheel(true)
    content:SetScript("OnMouseWheel", function(_, delta)
        AutoItemBar:HandleCategoryMouseWheel(delta)
    end)
    if not hasModernScroll then
        scroll:SetScript("OnMouseWheel", function(_, delta)
            AutoItemBar:HandleCategoryMouseWheel(delta)
        end)
    end

    window:SetScript("OnMouseUp", function(_, mouseButton)
        if mouseButton == "LeftButton" then
            if self._categoryDragKey then
                self:FinishCategoryDrag()
            elseif self._customDragItemID then
                self:FinishCustomItemDrag()
            end
        end
    end)
    window:SetScript("OnUpdate", function()
        AutoItemBar:UpdateCategoryDrag()
    end)

    self.CategoryManagerWindow = window
    return window
end

----------------------------------------------------------------------------------------
--	Drag and Drop
----------------------------------------------------------------------------------------

function AutoItemBar:StartCategoryDrag(categoryKey, enabled)
    if not enabled then return end
    if self._customDragItemID then
        self:FinishCustomItemDrag()
    end
    local window = self:EnsureCategoryManagerWindow()
    local enabledEntries = self:GetEnabledEntries()
    local targetToken = self:GetCategoryToken(categoryKey)
    local startIndex = 1
    local dragLabel
    for i, entry in ipairs(enabledEntries) do
        if entry.token == targetToken then
            startIndex = i
            dragLabel = entry.label
            break
        end
    end

    self._categoryDragKey = categoryKey
    self._categoryInsertIndex = startIndex
    self._categoryDragLabel = dragLabel
    self._categoryDragWasMoved = false

    if window.DragGhost then
        window.DragGhost.text:SetText(dragLabel or "")
        window.DragGhost:Show()
    end

    self:RefreshCategoryManagerWindow()
end

function AutoItemBar:GetCategoryInsertIndexFromCursor()
    return self:GetEnabledInsertIndexFromCursor(self:GetCategoryToken(self._categoryDragKey))
end

function AutoItemBar:GetEnabledInsertIndexFromCursor(dragToken)
    local window = self.CategoryManagerWindow
    if not window or not window.Content then
        return 1
    end

    local cursorX, cursorY = GetCursorPosition()
    local scale = window.Content:GetEffectiveScale()
    if not scale or scale <= 0 then
        scale = UIParent:GetEffectiveScale()
    end
    local cursorYScaled = cursorY / scale

    local top = window.Content:GetTop() or window:GetTop()
    local offset = top and (top - cursorYScaled) or 0
    local step = CATEGORY_ROW_HEIGHT + CATEGORY_ROW_SPACING
    local rawIndex = floor((offset + (step * 0.5)) / step) + 1

    local enabledEntries = self:GetEnabledEntries()
    local maxInsertIndex = #enabledEntries + 1
    if dragToken then
        for _, entry in ipairs(enabledEntries) do
            if entry.token == dragToken then
                maxInsertIndex = maxInsertIndex - 1
                break
            end
        end
    end

    return min(max(rawIndex, 1), maxInsertIndex)
end

function AutoItemBar:GetCustomInsertIndexFromCursor()
    return self:GetEnabledInsertIndexFromCursor(self:GetItemToken(self._customDragItemID))
end

function AutoItemBar:StartCustomItemDrag(itemID)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then return end
    if self._categoryDragKey then
        self:FinishCategoryDrag()
    end

    local enabledEntries = self:GetEnabledEntries()
    local targetToken = self:GetItemToken(itemID)
    local startIndex
    for index, entry in ipairs(enabledEntries) do
        if entry.token == targetToken then
            startIndex = index
            break
        end
    end
    if not startIndex then
        return
    end

    local window = self:EnsureCategoryManagerWindow()
    self._customDragItemID = itemID
    self._customInsertIndex = startIndex
    self._customDragWasMoved = false

    if window.DragGhost then
        window.DragGhost.text:SetText(GetItemDisplayName(itemID))
        window.DragGhost:Show()
    end

    self:RefreshCategoryManagerWindow()
end

function AutoItemBar:UpdateCategoryDrag()
    if not self._categoryDragKey and not self._customDragItemID then return end

    local window = self.CategoryManagerWindow
    if not window or not window:IsShown() then
        if self._categoryDragKey then
            self:FinishCategoryDrag()
        elseif self._customDragItemID then
            self:FinishCustomItemDrag()
        end
        return
    end

    if not IsMouseButtonDown("LeftButton") then
        if self._categoryDragKey then
            self:FinishCategoryDrag()
        elseif self._customDragItemID then
            self:FinishCustomItemDrag()
        end
        return
    end

    if self._categoryDragKey then
        local insertIndex = self:GetCategoryInsertIndexFromCursor()
        if insertIndex ~= self._categoryInsertIndex then
            self._categoryInsertIndex = insertIndex
            self._categoryDragWasMoved = true
            self:RefreshCategoryManagerWindow()
        end
    elseif self._customDragItemID then
        local customInsertIndex = self:GetCustomInsertIndexFromCursor()
        if customInsertIndex ~= self._customInsertIndex then
            self._customInsertIndex = customInsertIndex
            self._customDragWasMoved = true
            self:RefreshCategoryManagerWindow()
        end
    end

    local ghost = window.DragGhost
    if ghost and ghost:IsShown() then
        local cursorX, cursorY = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        ghost:SetFrameStrata(window:GetFrameStrata() or "DIALOG")
        ghost:SetFrameLevel((window:GetFrameLevel() or 220) + 40)
        ghost:ClearAllPoints()
        ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cursorX / scale, cursorY / scale)
    end
end

function AutoItemBar:FinishCategoryDrag()
    if not self._categoryDragKey then return end

    local dragKey = self._categoryDragKey
    local insertIndex = self._categoryInsertIndex or 1
    local wasMoved = self._categoryDragWasMoved == true

    self._categoryDragKey = nil
    self._categoryInsertIndex = nil
    self._categoryDragLabel = nil
    self._categoryDragWasMoved = nil

    local window = self.CategoryManagerWindow
    if window then
        if window.InsertLine then
            window.InsertLine:Hide()
        end
        if window.DragGhost then
            window.DragGhost:Hide()
        end
    end

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

    local window = self.CategoryManagerWindow
    if window then
        if window.InsertLine then
            window.InsertLine:Hide()
        end
        if window.DragGhost then
            window.DragGhost:Hide()
        end
    end

    if wasMoved then
        self:MoveTrackedItemToIndex(dragItemID, insertIndex)
    else
        self:RefreshCategoryManagerWindow()
    end
end

function AutoItemBar:RefreshCategoryManagerWindow()
    local window = self:EnsureCategoryManagerWindow()
    local rows = window.Rows
    local enabledEntries = self:GetEnabledEntries()
    local categories = self:GetOrderedCategories(true)
    local disabledCategories = {}
    for _, category in ipairs(categories) do
        if not category.enabled then
            tinsert(disabledCategories, category)
        end
    end
    local rowHeight = CATEGORY_ROW_HEIGHT
    local spacing = CATEGORY_ROW_SPACING
    local contentWidth = (window.Scroll:GetWidth() or 1) - (window._contentWidthPadding or 6)
    local dragKey = self._categoryDragKey
    local customDragItemID = self._customDragItemID
    local activeDragToken
    local placeholderIndex

    if dragKey then
        activeDragToken = self:GetCategoryToken(dragKey)
        placeholderIndex = self._categoryInsertIndex
    elseif customDragItemID then
        activeDragToken = self:GetItemToken(customDragItemID)
        placeholderIndex = self._customInsertIndex
    end

    if contentWidth < 1 then
        contentWidth = 1
    end
    window.Content:SetWidth(contentWidth)
    if window.DragGhost then
        window.DragGhost:SetWidth(contentWidth)
    end

    local enabledCountExcludingDrag = #enabledEntries
    if activeDragToken then
        for _, entry in ipairs(enabledEntries) do
            if entry.token == activeDragToken then
                enabledCountExcludingDrag = enabledCountExcludingDrag - 1
                break
            end
        end
    end

    if activeDragToken then
        local maxInsert = enabledCountExcludingDrag + 1
        placeholderIndex = min(max(placeholderIndex or 1, 1), maxInsert)
    end

    local renderedCount = 0
    local enabledOrdinal = 0

    for _, entry in ipairs(enabledEntries) do
        local row = rows[renderedCount + 1]
        if not row then
            row = CreateFrame("Button", nil, window.Content)
            row:SetHeight(rowHeight)
            row:EnableMouse(true)
            row:RegisterForClicks("LeftButtonUp")

            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()

            row.border = CreateFrame("Frame", nil, row, "BackdropTemplate")
            row.border:SetAllPoints()
            row.border:SetBackdrop({
                bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
                edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]],
                edgeSize = 10,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            row.border:SetBackdropColor(0, 0, 0, 0)

            row.order = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.order:SetPoint("LEFT", 10, 0)
            row.order:SetJustifyH("LEFT")

            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.text:SetPoint("LEFT", row.order, "RIGHT", 6, 0)
            row.text:SetJustifyH("LEFT")

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
            EnsureRowDragHandle(row)
            row.order:ClearAllPoints()
            row.order:SetPoint("LEFT", row.dragHandle, "RIGHT", 6, 0)
            row.text:ClearAllPoints()
            row.text:SetPoint("LEFT", row.order, "RIGHT", 6, 0)
            row.text:SetPoint("RIGHT", row.check, "LEFT", -18, 0)

            row:SetScript("OnMouseDown", function(rowSelf, button)
                if button == "LeftButton" then
                    if rowSelf.check and rowSelf.check:IsMouseOver() then
                        return
                    end
                    if rowSelf._entryType == "item" then
                        AutoItemBar:StartCustomItemDrag(rowSelf.itemID)
                    else
                        AutoItemBar:StartCategoryDrag(rowSelf.categoryKey, rowSelf.enabled)
                    end
                end
            end)
            row:SetScript("OnMouseUp", function(rowSelf, button)
                if button == "LeftButton" then
                    if rowSelf._entryType == "item" and AutoItemBar._customDragItemID then
                        AutoItemBar:FinishCustomItemDrag()
                    elseif rowSelf._entryType == "category" and AutoItemBar._categoryDragKey then
                        AutoItemBar:FinishCategoryDrag()
                    end
                end
            end)
            row.check:SetScript("OnClick", function(checkSelf)
                local parent = checkSelf:GetParent()
                if parent._entryType == "item" then
                    if not checkSelf:GetChecked() then
                        AutoItemBar:RemoveTrackedItem(parent.itemID)
                    else
                        checkSelf:SetChecked(true)
                    end
                else
                    AutoItemBar:SetTrackingCategoryEnabled(parent.categoryKey, checkSelf:GetChecked() and true or false)
                end
            end)

            rows[renderedCount + 1] = row
        end

        local isDraggedRow = activeDragToken and entry.token == activeDragToken
        if isDraggedRow then
            row._entryType = entry.type
            row.categoryKey = entry.key
            row.itemID = entry.itemID
            row:Hide()
        else
            enabledOrdinal = enabledOrdinal + 1
            local visualIndex = enabledOrdinal
            if placeholderIndex and visualIndex >= placeholderIndex then
                visualIndex = visualIndex + 1
            end

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -((visualIndex - 1) * (rowHeight + spacing)))
            row:SetPoint("TOPRIGHT", -2, -((visualIndex - 1) * (rowHeight + spacing)))
            row.order:SetText(("%d."):format(visualIndex))
            row._entryType = entry.type
            row.categoryKey = entry.key
            row.itemID = entry.itemID
            EnsureRowDragHandle(row)
            if row.dragHandle then
                row.dragHandle:Show()
            end
            if entry.type == "item" then
                row.text:SetText(GetItemDisplayName(entry.itemID))
                row.check:SetChecked(true)
                row.enabled = true
                self:UpdateCustomRowVisual(row, false)
            else
                row.text:SetText(entry.label)
                row.check:SetChecked(true)
                row.enabled = true
                self:UpdateCategoryRowVisual(row, true, false)
            end
            row.check:Enable()
            row:Show()
            renderedCount = renderedCount + 1
        end
    end

    if window.CustomHeader then
        window.CustomHeader:Hide()
    end

    local disabledStartIndex = enabledCountExcludingDrag
    if placeholderIndex then
        disabledStartIndex = disabledStartIndex + 1
    end

    local disabledOrdinal = 0
    for _, category in ipairs(disabledCategories) do
        local row = rows[renderedCount + 1]
        if not row then
            row = CreateFrame("Button", nil, window.Content)
            row:SetHeight(rowHeight)
            row:EnableMouse(true)
            row:RegisterForClicks("LeftButtonUp")

            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()

            row.border = CreateFrame("Frame", nil, row, "BackdropTemplate")
            row.border:SetAllPoints()
            row.border:SetBackdrop({
                bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
                edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]],
                edgeSize = 10,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            row.border:SetBackdropColor(0, 0, 0, 0)

            row.order = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.order:SetPoint("LEFT", 10, 0)
            row.order:SetJustifyH("LEFT")

            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.text:SetPoint("LEFT", row.order, "RIGHT", 6, 0)
            row.text:SetJustifyH("LEFT")

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
            EnsureRowDragHandle(row)
            row.order:ClearAllPoints()
            row.order:SetPoint("LEFT", row.dragHandle, "RIGHT", 6, 0)
            row.text:ClearAllPoints()
            row.text:SetPoint("LEFT", row.order, "RIGHT", 6, 0)
            row.text:SetPoint("RIGHT", row.check, "LEFT", -18, 0)
            row:SetScript("OnMouseDown", function(rowSelf, button)
                if button == "LeftButton" then
                    if rowSelf.check and rowSelf.check:IsMouseOver() then
                        return
                    end
                    AutoItemBar:StartCategoryDrag(rowSelf.categoryKey, rowSelf.enabled)
                end
            end)
            row:SetScript("OnMouseUp", function(rowSelf, button)
                if button == "LeftButton" and rowSelf._entryType == "category" and AutoItemBar._categoryDragKey then
                    AutoItemBar:FinishCategoryDrag()
                end
            end)
            row.check:SetScript("OnClick", function(checkSelf)
                local parent = checkSelf:GetParent()
                AutoItemBar:SetTrackingCategoryEnabled(parent.categoryKey, checkSelf:GetChecked() and true or false)
            end)

            rows[renderedCount + 1] = row
        end
        renderedCount = renderedCount + 1
        disabledOrdinal = disabledOrdinal + 1
        local visualIndex = disabledStartIndex + disabledOrdinal
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -((visualIndex - 1) * (rowHeight + spacing)))
        row:SetPoint("TOPRIGHT", -2, -((visualIndex - 1) * (rowHeight + spacing)))
        row.order:SetText(("%d."):format(visualIndex))
        row.text:SetText(category.label)
        row.check:SetChecked(false)
        row.check:Enable()
        row._entryType = "category"
        row.categoryKey = category.key
        row.enabled = false
        row.itemID = nil
        if row.dragHandle then
            row.dragHandle:Hide()
        end
        self:UpdateCategoryRowVisual(row, false, false)
        row:Show()
    end

    for index = renderedCount + 1, #rows do
        rows[index]:Hide()
    end

    if window.CustomRows then
        for index = 1, #window.CustomRows do
            window.CustomRows[index]:Hide()
        end
    end

    if window.InsertLine then
        if activeDragToken then
            local lineOffset = ((placeholderIndex or 1) - 1) * (rowHeight + spacing)
            window.InsertLine:ClearAllPoints()
            window.InsertLine:SetPoint("TOPLEFT", window.Content, "TOPLEFT", 0, -lineOffset)
            window.InsertLine:SetPoint("TOPRIGHT", window.Content, "TOPRIGHT", -2, -lineOffset)
            window.InsertLine:Show()
        else
            window.InsertLine:Hide()
        end
    end

    local totalRows = #enabledEntries + #disabledCategories
    if activeDragToken then
        totalRows = totalRows + 1
    end
    local height = totalRows * (rowHeight + spacing)
    if height < 1 then height = 1 end
    window.Content:SetHeight(height)
    if window.Scroll and window.Scroll.FullUpdate then
        local updateNow = ScrollBoxConstants and ScrollBoxConstants.UpdateImmediately or true
        window.Scroll:FullUpdate(updateNow)
    end
end

function AutoItemBar:HideCategoryManagerWindow()
    if self.CategoryManagerWindow then
        if self.CategoryManagerWindow.InsertLine then
            self.CategoryManagerWindow.InsertLine:Hide()
        end
        if self.CategoryManagerWindow.DragGhost then
            self.CategoryManagerWindow.DragGhost:Hide()
        end
        self.CategoryManagerWindow:Hide()
    end
    self._categoryDragKey = nil
    self._categoryInsertIndex = nil
    self._categoryDragLabel = nil
    self._categoryDragWasMoved = nil
    self._customDragItemID = nil
    self._customInsertIndex = nil
    self._customDragWasMoved = nil
end

function AutoItemBar:RefreshCategoryManagerVisibility(selection)
    local lib = RefineUI.LibEditMode
    local dialog = lib and lib.internal and lib.internal.dialog

    if not self._editModeActive then
        self:HideCategoryManagerWindow()
        if self.HideEditModeTutorial then
            self:HideEditModeTutorial(false)
        end
        return
    end

    if not dialog or not dialog:IsShown() or not self:IsSettingsDialogForAutoItemBar(selection) then
        self:HideCategoryManagerWindow()
        if self.HideEditModeTutorial then
            self:HideEditModeTutorial(false)
        end
        return
    end

    local window = self:EnsureCategoryManagerWindow()
    window:ClearAllPoints()
    window:SetFrameStrata(dialog:GetFrameStrata() or "DIALOG")
    window:SetFrameLevel((dialog:GetFrameLevel() or 200) + 10)
    window:SetWidth(dialog:GetWidth() or 300)
    window:SetPoint("TOPRIGHT", dialog, "TOPLEFT", -8, 0)
    window:SetHeight(dialog:GetHeight())
    self:RefreshCategoryManagerWindow()
    window:Show()
    if self.TryShowEditModeTutorial then
        self:TryShowEditModeTutorial()
    end
end

function AutoItemBar:HookCategoryManagerToDialog()
    if self._categoryDialogHooked then return end

    local lib = RefineUI.LibEditMode
    local dialog = lib and lib.internal and lib.internal.dialog
    if not dialog then return end

    hooksecurefunc(dialog, "Update", function(dialogSelf, selection)
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

