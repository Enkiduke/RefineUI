----------------------------------------------------------------------------------------
-- Bags Component: Category Manager
-- Description: UI and logic for managing custom item categories.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Bags = RefineUI:GetModule("Bags")
if not Bags then return end

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
local type = type
local tostring = tostring
local tonumber = tonumber
local ipairs = ipairs
local math = math
local table = table
local tinsert = table.insert
local CreateFrame = CreateFrame
local GetCursorPosition = GetCursorPosition
local pcall = pcall

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------

local ROW_HEIGHT = 24
local ROW_SPACING = 2
local DRAG_TEXTURE = [[Interface\AddOns\RefineUI\Media\Textures\drag.blp]]

local PINNED_BG = { 0.09, 0.19, 0.13, 0.78 }
local PINNED_TEXT = { 0.58, 0.95, 0.62 }
local PINNED_BORDER = { 0.34, 0.56, 0.38, 0.65 }

local UNPINNED_BG = { 0.12, 0.14, 0.18, 0.72 }
local UNPINNED_TEXT = { 0.72, 0.78, 0.9 }
local UNPINNED_BORDER = { 0.3, 0.35, 0.5, 0.58 }

local CUSTOM_BG = { 0.09, 0.13, 0.21, 0.8 }
local CUSTOM_TEXT = { 0.68, 0.83, 1.0 }
local CUSTOM_BORDER = { 0.3, 0.45, 0.7, 0.7 }

local BLOCK_BG = { 0.18, 0.15, 0.08, 0.78 }
local BLOCK_TEXT = { 1, 0.9, 0.58 }
local BLOCK_BORDER = { 0.78, 0.64, 0.2, 0.75 }

local DROP_BORDER = { 1, 0.82, 0.2, 0.95 }

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------

local function GetCategoryLabelMap()
    local map = {}
    if Bags.GetCategoryDefinitions then
        for _, def in ipairs(Bags.GetCategoryDefinitions()) do
            map[def.key] = def.label or def.key
        end
    end
    return map
end

function Bags.IsSettingsDialogForBags(selection)
    local lib = RefineUI.LibEditMode
    local dialog = lib and lib.internal and lib.internal.dialog
    local activeSelection = selection or (dialog and dialog.selection)
    return activeSelection and Bags.Frame and activeSelection.parent == Bags.Frame
end

local function AnchorBagsSettingsDialog(dialog, selection)
    if not dialog or not Bags.Frame then
        return
    end

    local activeSelection = selection or dialog.selection
    if not activeSelection or activeSelection.parent ~= Bags.Frame then
        return
    end

    dialog:ClearAllPoints()
    dialog:SetPoint("TOPRIGHT", Bags.Frame, "TOPLEFT", -8, 0)
end

local function EnsureRowDragHandle(row)
    if not row or row.dragHandle then
        return
    end

    row.dragHandle = CreateFrame("Frame", nil, row)
    row.dragHandle:SetSize(12, 12)
    row.dragHandle:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.dragHandle:SetFrameLevel((row:GetFrameLevel() or 1) + 2)
    row.dragHandle:SetAlpha(0.9)

    row.dragHandle.icon = row.dragHandle:CreateTexture(nil, "ARTWORK")
    row.dragHandle.icon:SetAllPoints()
    row.dragHandle.icon:SetTexture(DRAG_TEXTURE)
    row.dragHandle.icon:SetVertexColor(0.78, 0.78, 0.78, 0.95)
end

local function ApplyManagerFrameLevels(window)
    if not window then
        return
    end

    local baseLevel = window:GetFrameLevel() or 220
    if window.Border then
        window.Border:SetFrameLevel(baseLevel)
    end
    if window.ListContainer then
        window.ListContainer:SetFrameLevel(baseLevel + 5)
    end
    if window.Scroll then
        window.Scroll:SetFrameLevel(baseLevel + 6)
    end
    if window.Content then
        window.Content:SetFrameLevel(baseLevel + 7)
    end
    if window.NameEditor then
        window.NameEditor:SetFrameLevel(baseLevel + 30)
    end
end

----------------------------------------------------------------------------------------
-- Rows & Visuals
----------------------------------------------------------------------------------------

local function CreateCategoryRow(window)
    local row = CreateFrame("Button", nil, window.Content)
    row:SetHeight(ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonUp")
    row:EnableMouse(true)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()

    row.border = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.border:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.border:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    row.border:SetBackdrop({
        edgeFile = [[Interface\Buttons\WHITE8x8]],
        edgeSize = 1,
    })

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetAtlas("Options_List_Hover")
    row.highlight:SetAlpha(0.2)

    EnsureRowDragHandle(row)

    row.order = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.order:SetPoint("LEFT", row, "LEFT", 24, 0)
    row.order:SetWidth(24)
    row.order:SetJustifyH("CENTER")

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row.order, "RIGHT", 6, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -34, 0)
    row.text:SetJustifyH("LEFT")

    row.pin = CreateFrame("Button", nil, row)
    row.pin:SetSize(18, 18)
    row.pin:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.pin:EnableMouse(true)

    row.pinIcon = row.pin:CreateTexture(nil, "ARTWORK")
    row.pinIcon:SetAllPoints()
    row.pinIcon:SetAtlas("friendslist-recentallies-Pin-yellow")

    row.pinHighlight = row.pin:CreateTexture(nil, "HIGHLIGHT")
    row.pinHighlight:SetAllPoints()
    row.pinHighlight:SetColorTexture(1, 1, 1, 0.15)

    row.pin:SetScript("OnClick", function(self)
        local parent = self:GetParent()
        if not parent or not parent.categoryKey then return end

        if parent._entry and parent._entry.type == "custom" then
            if Bags.DeleteCustomCategory and Bags.DeleteCustomCategory(parent.categoryKey) then
                if Bags._renamingCustomKey == parent.categoryKey then
                    Bags._renamingCustomKey = nil
                end
                if Bags._pendingCustomRenameKey == parent.categoryKey then
                    Bags._pendingCustomRenameKey = nil
                end

                Bags.RefreshCategoryManagerWindow()
                if Bags.RequestUpdate then
                    Bags.RequestUpdate()
                end
            end
            return
        end

        local shouldPin = not Bags.IsCategoryPinned(parent.categoryKey)
        Bags.SetCategoryPinned(parent.categoryKey, shouldPin)
        Bags.RefreshCategoryManagerWindow()

        if Bags.RequestUpdate then
            Bags.RequestUpdate()
        end
    end)

    row:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and self._canDrag and self._dragToken then
            if self.pin and self.pin:IsMouseOver() then return end
            Bags.StartPinnedCategoryDrag(self._dragToken)
        end
    end)

    row:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and Bags._dragToken then
            Bags.FinishPinnedCategoryDrag()
        elseif button == "RightButton" and Bags.BeginCustomCategoryRename then
            if self and self._entry and self._entry.type == "custom" and self.categoryKey then
                Bags.BeginCustomCategoryRename(self, self.categoryKey, false)
            end
        end
    end)

    return row
end

local function UpdateRowVisual(row, entry, isDropTarget)
    if not row or not row.bg or not row.text then return end

    local bg, text, border
    if entry.type == "block" then
        bg, text, border = BLOCK_BG, BLOCK_TEXT, BLOCK_BORDER
    elseif entry.type == "custom" then
        bg, text, border = CUSTOM_BG, CUSTOM_TEXT, CUSTOM_BORDER
    elseif entry.pinned then
        bg, text, border = PINNED_BG, PINNED_TEXT, PINNED_BORDER
    else
        bg, text, border = UNPINNED_BG, UNPINNED_TEXT, UNPINNED_BORDER
    end

    row.bg:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
    row.text:SetTextColor(text[1], text[2], text[3], 1)

    if row.order then
        row.order:SetTextColor(text[1], text[2], text[3], 0.9)
    end

    if row.dragHandle and row.dragHandle.icon then
        row.dragHandle.icon:SetVertexColor(text[1], text[2], text[3], 0.95)
    end

    local b = isDropTarget and DROP_BORDER or border
    row.border:SetBackdropBorderColor(b[1], b[2], b[3], b[4])
end

local function HandleCategoryMouseWheel(window, delta)
    if not window or not window.Scroll then return end

    local scroll = window.Scroll
    if not scroll.GetVerticalScroll or not scroll.GetVerticalScrollRange or not scroll.SetVerticalScroll then
        return
    end

    local step = (ROW_HEIGHT + ROW_SPACING) * 2
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

----------------------------------------------------------------------------------------
-- Entries & Renaming
----------------------------------------------------------------------------------------

local function BuildCategoryEntries()
    if Bags.EnsureCategoryConfig then
        Bags.EnsureCategoryConfig()
    end

    local cfg = Bags.GetConfig and Bags.GetConfig()
    local entries = {}
    if not cfg then return entries end

    local labels = GetCategoryLabelMap()
    local unpinnedCategories = {}
    local pinnedByKey = {}

    for _, key in ipairs(cfg.CategoryOrder or Bags.CATEGORY_ORDER or {}) do
        local isCustom = Bags.IsCustomCategoryKey and Bags.IsCustomCategoryKey(key)
        local entry = {
            type = isCustom and "custom" or "category",
            key = key,
            label = labels[key] or key,
            pinned = cfg.CategoryPinned[key] == true,
        }
        if entry.pinned then
            pinnedByKey[key] = entry
        else
            tinsert(unpinnedCategories, entry)
        end
    end

    local pinnedTokens = Bags.GetPinnedOrderTokens and Bags.GetPinnedOrderTokens() or { Bags.BINNED_BLOCK_TOKEN }
    local orderIndex = 0
    local blockInserted = false

    for _, token in ipairs(pinnedTokens) do
        if token == Bags.BINNED_BLOCK_TOKEN then
            blockInserted = true
            orderIndex = orderIndex + 1
            tinsert(entries, {
                type = "block",
                token = token,
                label = "Smart Binned Categories",
                orderIndex = orderIndex,
            })

            for _, entry in ipairs(unpinnedCategories) do
                tinsert(entries, entry)
            end
        elseif pinnedByKey[token] then
            orderIndex = orderIndex + 1
            local pinnedEntry = pinnedByKey[token]
            pinnedEntry.orderIndex = orderIndex
            tinsert(entries, pinnedEntry)
        end
    end

    if not blockInserted then
        orderIndex = orderIndex + 1
        tinsert(entries, {
            type = "block",
            token = Bags.BINNED_BLOCK_TOKEN,
            label = "Smart Binned Categories",
            orderIndex = orderIndex,
        })
        for _, entry in ipairs(unpinnedCategories) do
            tinsert(entries, entry)
        end
    end

    return entries
end

local function AnchorCategoryNameEditor(window, row)
    if not window or not window.NameEditor or not row then
        return
    end

    local editor = window.NameEditor
    editor:ClearAllPoints()
    editor:SetPoint("LEFT", row.text, "LEFT", -2, 0)
    editor:SetPoint("RIGHT", row, "RIGHT", -34, 0)
    editor:SetPoint("TOP", row, "TOP", 0, -2)
    editor:SetPoint("BOTTOM", row, "BOTTOM", 0, 2)
end

local function CommitCustomCategoryRename(applyChanges)
    local window = Bags.CategoryManagerWindow
    if not window or not window.NameEditor or not Bags._renamingCustomKey then
        return
    end

    local editor = window.NameEditor
    if applyChanges then
        local ok = Bags.RenameCustomCategory and Bags.RenameCustomCategory(Bags._renamingCustomKey, editor:GetText())
        if not ok then
            editor:SetTextColor(1, 0.45, 0.45)
            editor:SetFocus()
            return
        end
    end

    editor:SetTextColor(1, 0.82, 0)
    editor:Hide()
    editor:ClearFocus()
    Bags._renamingCustomKey = nil

    Bags.RefreshCategoryManagerWindow()

    if Bags.RequestUpdate then
        Bags.RequestUpdate()
    end
end

function Bags.BeginCustomCategoryRename(row, categoryKey, selectAllText)
    if not row or not categoryKey then return end

    local window = Bags.EnsureCategoryManagerWindow()
    if not window then return end

    if not window.NameEditor then
        local editor = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
        editor:SetAutoFocus(false)
        editor:SetTextInsets(6, 6, 0, 0)
        editor:SetFontObject("GameFontHighlightSmall")
        editor:SetTextColor(1, 0.82, 0)
        editor:SetFrameStrata("DIALOG")
        editor:SetFrameLevel((window:GetFrameLevel() or 220) + 30)
        editor:Hide()

        editor:SetScript("OnEnterPressed", function()
            CommitCustomCategoryRename(true)
        end)
        editor:SetScript("OnEscapePressed", function()
            CommitCustomCategoryRename(false)
        end)
        editor:SetScript("OnEditFocusLost", function()
            CommitCustomCategoryRename(true)
        end)

        window.NameEditor = editor
    end

    Bags._renamingCustomKey = categoryKey
    local editor = window.NameEditor
    editor:SetText(Bags.GetCategoryLabel and Bags.GetCategoryLabel(categoryKey) or row.text:GetText() or "")
    editor:SetTextColor(1, 0.82, 0)
    AnchorCategoryNameEditor(window, row)
    editor:Show()
    editor:SetFocus()

    if selectAllText then
        editor:HighlightText()
    else
        editor:HighlightText(0, 0)
    end
end

----------------------------------------------------------------------------------------
-- Manager Window
----------------------------------------------------------------------------------------

function Bags.EnsureCategoryManagerWindow()
    if Bags.CategoryManagerWindow then
        return Bags.CategoryManagerWindow
    end

    local window = CreateFrame("Frame", "RefineUI_BagsCategoryManager", UIParent, "ResizeLayoutFrame")
    window:SetFrameStrata("DIALOG")
    window:SetFrameLevel(220)
    window:SetSize(300, 350)
    window.widthPadding = 40
    window.heightPadding = 40
    window:Hide()
    window:EnableMouse(true)

    local border = CreateFrame("Frame", nil, window, "DialogBorderTranslucentTemplate")
    border.ignoreInLayout = true
    border:EnableMouse(false)
    window.Border = border

    local closeButton = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT")
    closeButton.ignoreInLayout = true
    closeButton:HookScript("OnClick", function()
        Bags.HideCategoryManagerWindow()
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
    subtitle:SetText("Pin categories to pull them out of smart binning. Right-click custom rows to rename, or click X to delete.")
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

    local scroll = CreateFrame("ScrollFrame", nil, listContainer, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", listContainer, "TOPLEFT", 5, -5)
    scroll:SetPoint("BOTTOMRIGHT", listContainer, "BOTTOMRIGHT", -27, 5)
    scroll:EnableMouseWheel(true)
    window.Scroll = scroll

    local content = CreateFrame("Frame", nil, scroll)
    content:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    window.Content = content
    window.Rows = {}
    window.DragRows = {}
    ApplyManagerFrameLevels(window)

    local insertLine = content:CreateTexture(nil, "OVERLAY")
    insertLine:SetHeight(2)
    insertLine:SetColorTexture(1, 0.84, 0.28, 0.95)
    insertLine:Hide()
    window.InsertLine = insertLine

    local dragGhost = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    dragGhost:SetFrameStrata("DIALOG")
    dragGhost:SetFrameLevel(window:GetFrameLevel() + 40)
    dragGhost:SetSize(220, ROW_HEIGHT)
    if RefineUI.SetTemplate then
        RefineUI.SetTemplate(dragGhost, "Transparent")
    end
    dragGhost:EnableMouse(false)
    dragGhost:Hide()

    dragGhost.bg = dragGhost:CreateTexture(nil, "BACKGROUND")
    dragGhost.bg:SetAllPoints()
    dragGhost.bg:SetColorTexture(0.15, 0.22, 0.16, 0.9)

    dragGhost.text = dragGhost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dragGhost.text:SetPoint("LEFT", 10, 0)
    dragGhost.text:SetPoint("RIGHT", -10, 0)
    dragGhost.text:SetJustifyH("LEFT")
    dragGhost.text:SetTextColor(0.95, 0.95, 0.95)
    dragGhost.text:SetText("")

    window.DragGhost = dragGhost

    local resetButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    resetButton:SetSize(90, 22)
    resetButton:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 14, 14)
    resetButton:SetText("Reset")
    resetButton:SetScript("OnClick", function()
        local cfg = Bags.GetConfig and Bags.GetConfig()
        if not cfg then return end

        cfg.CategoryOrder = {}
        cfg.CategoryPinned = {}
        cfg.PinnedOrder = {}
        cfg.CustomCategories = {}
        cfg.CustomCategoryItems = {}
        cfg.CategorySchemaVersion = 0

        if Bags.EnsureCategoryConfig then
            Bags.EnsureCategoryConfig()
        end
        Bags.RefreshCategoryManagerWindow()
        if Bags.RequestUpdate then
            Bags.RequestUpdate()
        end
    end)
    window.ResetButton = resetButton

    local addCustomButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    addCustomButton:SetSize(160, 22)
    addCustomButton:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -14, 14)
    addCustomButton:SetText("Add Custom Category")
    addCustomButton:SetScript("OnClick", function()
        if not Bags.CreateCustomCategory then return end

        local baseName = (Bags.GetNextDefaultCustomCategoryName and Bags.GetNextDefaultCustomCategoryName("New Category")) or "New Category"
        local key = Bags.CreateCustomCategory(baseName)
        if not key then return end

        Bags._pendingCustomRenameKey = key
        Bags.RefreshCategoryManagerWindow()
        if Bags.RequestUpdate then
            Bags.RequestUpdate()
        end
    end)
    window.AddCustomButton = addCustomButton

    listContainer:EnableMouseWheel(true)
    listContainer:SetScript("OnMouseWheel", function(_, delta)
        HandleCategoryMouseWheel(window, delta)
    end)

    content:EnableMouseWheel(true)
    content:SetScript("OnMouseWheel", function(_, delta)
        HandleCategoryMouseWheel(window, delta)
    end)

    scroll:SetScript("OnMouseWheel", function(_, delta)
        HandleCategoryMouseWheel(window, delta)
    end)

    listContainer:SetScript("OnSizeChanged", function()
        if window:IsShown() then
            Bags.RefreshCategoryManagerWindow()
        end
    end)

    window:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and Bags._dragToken then
            Bags.FinishPinnedCategoryDrag()
        end
    end)

    window:SetScript("OnHide", function()
        if Bags._dragToken then
            Bags.FinishPinnedCategoryDrag()
        end
        if window.NameEditor and window.NameEditor:IsShown() then
            window.NameEditor:Hide()
            window.NameEditor:ClearFocus()
        end
        Bags._renamingCustomKey = nil
        Bags._pendingCustomRenameKey = nil
    end)

    window:SetScript("OnUpdate", function()
        Bags.UpdatePinnedCategoryDrag()
    end)

    Bags.CategoryManagerWindow = window
    return window
end

----------------------------------------------------------------------------------------
-- Drag & Drop Logic
----------------------------------------------------------------------------------------

local function GetDragRowsExcludingDragged(window)
    local rows = {}
    local dragToken = Bags._dragToken
    for _, row in ipairs(window.DragRows or {}) do
        if row and row:IsShown() and row._dragToken ~= dragToken then
            tinsert(rows, row)
        end
    end
    return rows
end

function Bags.GetPinnedInsertIndexFromCursor()
    local window = Bags.CategoryManagerWindow
    if not window then return nil end

    local rows = GetDragRowsExcludingDragged(window)
    if #rows == 0 then return 1 end

    local scale = window:GetEffectiveScale()
    local _, cursorY = GetCursorPosition()
    cursorY = cursorY / scale

    local insertIndex = #rows + 1
    for i, row in ipairs(rows) do
        local top = row:GetTop() or 0
        local bottom = row:GetBottom() or top
        local mid = (top + bottom) * 0.5
        if cursorY >= mid then
            insertIndex = i
            break
        end
    end

    return insertIndex
end

local function UpdateInsertLine(window)
    if not window or not window.InsertLine then return end

    if not Bags._dragToken or not Bags._dragInsertIndex then
        window.InsertLine:Hide()
        return
    end

    local rows = GetDragRowsExcludingDragged(window)
    if #rows == 0 then
        window.InsertLine:Hide()
        return
    end

    local idx = Bags._dragInsertIndex
    if idx < 1 then idx = 1 end
    if idx > (#rows + 1) then idx = #rows + 1 end

    window.InsertLine:ClearAllPoints()
    if idx <= #rows then
        local target = rows[idx]
        window.InsertLine:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
        window.InsertLine:SetPoint("TOPRIGHT", target, "TOPRIGHT", 0, 0)
    else
        local target = rows[#rows]
        window.InsertLine:SetPoint("TOPLEFT", target, "BOTTOMLEFT", 0, 0)
        window.InsertLine:SetPoint("TOPRIGHT", target, "BOTTOMRIGHT", 0, 0)
    end
    window.InsertLine:Show()
end

function Bags.RefreshCategoryManagerWindow()
    local window = Bags.EnsureCategoryManagerWindow()
    if not window then return end

    local entries = BuildCategoryEntries()
    local measuredWidth = ((window.ListContainer and window.ListContainer:GetWidth()) or 0) - 38
    local contentWidth = math.max(220, measuredWidth)
    local dragToken = Bags._dragToken

    window.DragRows = {}
    local yOffset = 0

    for index, entry in ipairs(entries) do
        local row = window.Rows[index]
        if not row then
            row = CreateCategoryRow(window)
            window.Rows[index] = row
        end
        row:SetFrameLevel((window.Content:GetFrameLevel() or window:GetFrameLevel() or 220) + 2)
        if row.pin then
            row.pin:SetFrameLevel((row:GetFrameLevel() or 1) + 2)
        end
        if row.dragHandle then
            row.dragHandle:SetFrameLevel((row:GetFrameLevel() or 1) + 3)
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", window.Content, "TOPLEFT", 0, -yOffset)
        row:SetPoint("TOPRIGHT", window.Content, "TOPRIGHT", 0, -yOffset)
        yOffset = yOffset + ROW_HEIGHT + ROW_SPACING

        row._entry = entry
        row._dragToken = nil
        row._canDrag = false
        row.categoryKey = entry.key

        row.text:SetText(entry.label or "")

        if entry.type == "block" then
            row.order:SetText(entry.orderIndex or "")
            row.pin:Hide()
            row._canDrag = true
            row.dragHandle:Show()
            row._dragToken = entry.token
            tinsert(window.DragRows, row)
        elseif entry.type == "custom" then
            row.pin:Show()
            row.pin:Enable()
            row.pin:SetAlpha(1)
            if row.pinIcon then
                local ok = pcall(row.pinIcon.SetAtlas, row.pinIcon, "common-icon-redx", true)
                if not ok then
                    row.pinIcon:SetTexture([[Interface\Buttons\UI-Panel-MinimizeButton-Up]])
                end
                row.pinIcon:SetDesaturated(false)
                row.pinIcon:SetVertexColor(1, 0.45, 0.45, 1)
            end
            row.order:SetText(entry.orderIndex or "")
            row._canDrag = true
            row._dragToken = entry.key
            row.dragHandle:Show()
            tinsert(window.DragRows, row)
        else
            row.pin:Show()
            row.pin:Enable()
            row.pin:SetAlpha(1)

            if row.pinIcon then
                row.pinIcon:SetAtlas("friendslist-recentallies-Pin-yellow")
                if entry.pinned then
                    row.pinIcon:SetDesaturated(false)
                    row.pinIcon:SetVertexColor(1, 1, 1, 1)
                else
                    row.pinIcon:SetDesaturated(true)
                    row.pinIcon:SetVertexColor(0.62, 0.62, 0.62, 1)
                end
            end

            if entry.pinned then
                row.order:SetText(entry.orderIndex or "")
                row._canDrag = true
                row._dragToken = entry.key
                row.dragHandle:Show()
                tinsert(window.DragRows, row)
            else
                row.order:SetText("-")
                row.dragHandle:Hide()
            end
        end

        if dragToken and row._dragToken and row._dragToken == dragToken then
            row:SetAlpha(0.35)
        else
            row:SetAlpha(1)
        end

        UpdateRowVisual(row, entry, false)
        row:Show()

        if window.NameEditor and window.NameEditor:IsShown() and Bags._renamingCustomKey and entry.type == "custom" and entry.key == Bags._renamingCustomKey then
            AnchorCategoryNameEditor(window, row)
        elseif Bags._pendingCustomRenameKey and entry.type == "custom" and entry.key == Bags._pendingCustomRenameKey then
            Bags._pendingCustomRenameKey = nil
            Bags.BeginCustomCategoryRename(row, entry.key, true)
        end
    end

    for i = #entries + 1, #window.Rows do
        if window.Rows[i] then
            window.Rows[i]:Hide()
            window.Rows[i]._dragToken = nil
            window.Rows[i]._canDrag = false
            window.Rows[i].categoryKey = nil
        end
    end

    window.Content:SetSize(contentWidth, yOffset)
    if window.Scroll and window.Scroll.UpdateScrollChildRect then
        window.Scroll:UpdateScrollChildRect()
        local offset = window.Scroll:GetVerticalScroll() or 0
        local maxOffset = window.Scroll:GetVerticalScrollRange() or 0
        if offset > maxOffset then
            window.Scroll:SetVerticalScroll(maxOffset)
        end
    end
    UpdateInsertLine(window)
end

function Bags.StartPinnedCategoryDrag(token)
    if not token then return end
    if token ~= Bags.BINNED_BLOCK_TOKEN and (not Bags.IsCategoryPinned or not Bags.IsCategoryPinned(token)) then
        return
    end

    local window = Bags.EnsureCategoryManagerWindow()
    local labels = GetCategoryLabelMap()

    Bags._dragToken = token
    Bags._dragInsertIndex = nil

    if window.DragGhost then
        if token == Bags.BINNED_BLOCK_TOKEN then
            window.DragGhost.text:SetText("Smart Binned Categories")
        else
            window.DragGhost.text:SetText(labels[token] or token)
        end
        window.DragGhost:Show()
    end

    Bags.RefreshCategoryManagerWindow()
end

function Bags.UpdatePinnedCategoryDrag()
    if not Bags._dragToken then return end

    local window = Bags.CategoryManagerWindow
    if not window or not window:IsShown() then
        Bags.FinishPinnedCategoryDrag()
        return
    end

    if not IsMouseButtonDown("LeftButton") then
        Bags.FinishPinnedCategoryDrag()
        return
    end

    local insertIndex = Bags.GetPinnedInsertIndexFromCursor()
    if insertIndex ~= Bags._dragInsertIndex then
        Bags._dragInsertIndex = insertIndex
        UpdateInsertLine(window)
    end

    if window.DragGhost then
        local scale = UIParent:GetEffectiveScale()
        local cursorX, cursorY = GetCursorPosition()
        window.DragGhost:ClearAllPoints()
        window.DragGhost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cursorX / scale, (cursorY / scale) + 14)
    end
end

function Bags.FinishPinnedCategoryDrag()
    if not Bags._dragToken then return end

    local dragToken = Bags._dragToken
    local insertIndex = Bags._dragInsertIndex
    local window = Bags.CategoryManagerWindow

    Bags._dragToken = nil
    Bags._dragInsertIndex = nil

    if window and window.InsertLine then
        window.InsertLine:Hide()
    end
    if window and window.DragGhost then
        window.DragGhost:Hide()
    end

    if insertIndex and Bags.MovePinnedTokenToIndex then
        Bags.MovePinnedTokenToIndex(dragToken, insertIndex)
    elseif insertIndex and Bags.MovePinnedCategoryToIndex then
        Bags.MovePinnedCategoryToIndex(dragToken, insertIndex)
    end

    Bags.RefreshCategoryManagerWindow()

    if Bags.RequestUpdate then
        Bags.RequestUpdate()
    end
end

----------------------------------------------------------------------------------------
-- Visibility & Hooks
----------------------------------------------------------------------------------------

function Bags.HideCategoryManagerWindow()
    if Bags._dragToken then
        Bags.FinishPinnedCategoryDrag()
    end

    if Bags.CategoryManagerWindow then
        if Bags.CategoryManagerWindow.InsertLine then
            Bags.CategoryManagerWindow.InsertLine:Hide()
        end
        if Bags.CategoryManagerWindow.DragGhost then
            Bags.CategoryManagerWindow.DragGhost:Hide()
        end
        Bags.CategoryManagerWindow:Hide()
    end
end

function Bags.RefreshCategoryManagerVisibility(selection)
    local lib = RefineUI.LibEditMode
    local dialog = lib and lib.internal and lib.internal.dialog

    if not Bags._editModeActive then
        Bags.HideCategoryManagerWindow()
        return
    end

    if not dialog or not dialog:IsShown() or not Bags.IsSettingsDialogForBags(selection) then
        Bags.HideCategoryManagerWindow()
        return
    end

    AnchorBagsSettingsDialog(dialog, selection)

    local window = Bags.EnsureCategoryManagerWindow()
    window:ClearAllPoints()
    window:SetFrameStrata(dialog:GetFrameStrata() or "DIALOG")
    window:SetFrameLevel((dialog:GetFrameLevel() or 200) + 10)

    local dialogWidth = dialog:GetWidth() or 0
    if dialogWidth < 260 then
        dialogWidth = 300
    end

    window:SetWidth(dialogWidth)
    window:SetHeight(dialog:GetHeight() or 350)
    window:SetPoint("TOPLEFT", dialog, "BOTTOMLEFT", 0, -8)

    if window.DragGhost then
        window.DragGhost:SetFrameStrata(window:GetFrameStrata() or "DIALOG")
        window.DragGhost:SetFrameLevel((window:GetFrameLevel() or 220) + 40)
    end

    ApplyManagerFrameLevels(window)
    Bags.RefreshCategoryManagerWindow()
    window:Show()
end

function Bags.HookCategoryManagerToDialog()
    if Bags._categoryDialogHooked then return end

    local lib = RefineUI.LibEditMode
    local dialog = lib and lib.internal and lib.internal.dialog
    if not dialog then return end

    hooksecurefunc(dialog, "Update", function(_, selection)
        Bags.RefreshCategoryManagerVisibility(selection)
    end)

    dialog:HookScript("OnShow", function()
        Bags.RefreshCategoryManagerVisibility()
    end)

    dialog:HookScript("OnHide", function()
        Bags.HideCategoryManagerWindow()
    end)

    Bags._categoryDialogHooked = true
end

if Bags.InitializeEditMode then
    Bags.InitializeEditMode()
end

if Bags.HookCategoryManagerToDialog then
    Bags.HookCategoryManagerToDialog()
end

C_Timer.After(1, function()
    if Bags.HookCategoryManagerToDialog then
        Bags.HookCategoryManagerToDialog()
    end
end)

