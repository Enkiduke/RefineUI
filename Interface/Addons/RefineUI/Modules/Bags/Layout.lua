----------------------------------------------------------------------------------------
-- Bags Component: Layout
-- Description: Core layout engine for placing items in the bags.
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
local pairs = pairs
local next = next
local table = table
local math = math
local wipe = wipe
local pcall = pcall
local string = string
local CreateFrame = CreateFrame
local GetItemQualityColor = GetItemQualityColor
local SetItemButtonDesaturated = SetItemButtonDesaturated
local SetItemButtonTexture = SetItemButtonTexture
local SetItemButtonCount = SetItemButtonCount
local SetItemButtonQuality = SetItemButtonQuality
local MoneyFrame_Update = MoneyFrame_Update
local GetMoney = GetMoney
local InCombatLockdown = InCombatLockdown
local GetCursorInfo = GetCursorInfo

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------

local MAIN_CAT_GAP = 1
local COMBINED_SECTION_CATEGORY = "__combined__"
local HEADER_TEXT_PADDING = 12 -- Text left inset, divider gap, and divider right inset.

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------

Bags.customDropPool = Bags.customDropPool or {}
Bags.activeCustomDrops = Bags.activeCustomDrops or {}
Bags.bagSectionDropPool = Bags.bagSectionDropPool or {}
Bags.activeBagSectionDrops = Bags.activeBagSectionDrops or {}
Bags.SlotFrameByKey = Bags.SlotFrameByKey or {}
Bags.SectionFrameByKey = Bags.SectionFrameByKey or {}
Bags.slotVisualRevisionByFrame = Bags.slotVisualRevisionByFrame or setmetatable({}, { __mode = "k" })

local mainSlotFrameByKey = Bags.SlotFrameByKey
local mainSectionFrameByKey = Bags.SectionFrameByKey
local slotVisualRevisionByFrame = Bags.slotVisualRevisionByFrame
local appliedLayoutRevision = 0
local lastHasCursorItem = false

local bordersModule
local function GetBordersModule()
    if bordersModule and bordersModule.ApplyItemBorder then
        return bordersModule
    end
    bordersModule = RefineUI:GetModule("Borders")
    if bordersModule and bordersModule.ApplyItemBorder then
        return bordersModule
    end
    return nil
end

local function AcquireCustomCategoryDropTarget(parent)
    local button = table.remove(Bags.customDropPool)
    if not button then
        button = CreateFrame("Button", nil, parent)
        button:EnableMouse(true)
        button:RegisterForClicks("LeftButtonUp")
        button:RegisterForDrag("LeftButton")
        button:SetHitRectInsets(0, 0, 0, 0)

        button:SetScript("OnReceiveDrag", function(selfButton)
            if Bags.HandleCustomCategoryDrop then
                Bags.HandleCustomCategoryDrop(selfButton._customCategoryKey)
            end
        end)

        button:SetScript("OnMouseUp", function(selfButton, mouseButton)
            if mouseButton == "LeftButton" and GetCursorInfo() and Bags.HandleCustomCategoryDrop then
                Bags.HandleCustomCategoryDrop(selfButton._customCategoryKey)
            end
        end)

        button.SlotBG = button:CreateTexture(nil, "BACKGROUND")
        button.SlotBG:SetAllPoints()
        local slotAtlasOk = pcall(button.SlotBG.SetAtlas, button.SlotBG, "bags-item-slot64", true)
        if not slotAtlasOk then
            button.SlotBG:SetColorTexture(0.12, 0.15, 0.2, 0.85)
        end

        button.Hover = button:CreateTexture(nil, "HIGHLIGHT")
        button.Hover:SetAllPoints()
        button.Hover:SetColorTexture(1, 1, 1, 0.14)

        button.Border = CreateFrame("Frame", nil, button, "BackdropTemplate")
        button.Border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
        button.Border:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)

        if RefineUI.SetTemplate then
            RefineUI.SetTemplate(button.Border, "Transparent", 4, 4)
        else
            button.Border:SetBackdrop({
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            button.Border:SetBackdropBorderColor(0.35, 0.6, 1, 0.85)
        end

        button.RefineUIAddIcon = button:CreateTexture(nil, "OVERLAY")
        button.RefineUIAddIcon:SetPoint("CENTER", button, "CENTER", 0, 0)
        button.RefineUIAddIcon:SetSize(18, 18)
        button.RefineUIAddIcon:SetTexture("Interface\\AddOns\\RefineUI\\Media\\Textures\\add.blp")
        button.RefineUIAddIcon:SetVertexColor(0.65, 0.86, 1, 0.95)
    end

    button:Show()
    if button.Border then button.Border:Show() end
    if button.RefineUIAddIcon then button.RefineUIAddIcon:Show() end
    return button
end

local function ReleaseCustomCategoryDropTargets()
    for _, button in ipairs(Bags.activeCustomDrops) do
        button:Hide()
        button:ClearAllPoints()
        button._customCategoryKey = nil
        table.insert(Bags.customDropPool, button)
    end
    wipe(Bags.activeCustomDrops)
end

local function AcquireBagSectionDropTarget(parent)
    local button = table.remove(Bags.bagSectionDropPool)
    if not button then
        button = CreateFrame("Button", nil, parent)
        button:EnableMouse(true)
        button:RegisterForClicks("LeftButtonUp")
        button:RegisterForDrag("LeftButton")
        button:SetHitRectInsets(0, 0, 0, 0)

        button:SetScript("OnReceiveDrag", function(selfButton)
            if Bags.HandleBagSectionDrop then
                Bags.HandleBagSectionDrop(selfButton._targetBagID)
            end
        end)

        button:SetScript("OnMouseUp", function(selfButton, mouseButton)
            if mouseButton == "LeftButton" and GetCursorInfo() and Bags.HandleBagSectionDrop then
                Bags.HandleBagSectionDrop(selfButton._targetBagID)
            end
        end)

        button.SlotBG = button:CreateTexture(nil, "BACKGROUND")
        button.SlotBG:SetAllPoints()
        local slotAtlasOk = pcall(button.SlotBG.SetAtlas, button.SlotBG, "bags-item-slot64", true)
        if not slotAtlasOk then
            button.SlotBG:SetColorTexture(0.12, 0.15, 0.2, 0.85)
        end

        button.Hover = button:CreateTexture(nil, "HIGHLIGHT")
        button.Hover:SetAllPoints()
        button.Hover:SetColorTexture(1, 1, 1, 0.14)

        button.Border = CreateFrame("Frame", nil, button, "BackdropTemplate")
        button.Border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
        button.Border:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)

        if RefineUI.SetTemplate then
            RefineUI.SetTemplate(button.Border, "Transparent", 4, 4)
        else
            button.Border:SetBackdrop({
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            button.Border:SetBackdropBorderColor(0.35, 0.6, 1, 0.85)
        end

        button.RefineUIAddIcon = button:CreateTexture(nil, "OVERLAY")
        button.RefineUIAddIcon:SetPoint("CENTER", button, "CENTER", 0, 0)
        button.RefineUIAddIcon:SetSize(18, 18)
        button.RefineUIAddIcon:SetTexture("Interface\\AddOns\\RefineUI\\Media\\Textures\\add.blp")
        button.RefineUIAddIcon:SetVertexColor(0.65, 0.86, 1, 0.95)
    end

    button:Show()
    if button.Border then button.Border:Show() end
    if button.RefineUIAddIcon then button.RefineUIAddIcon:Show() end
    return button
end

local function ReleaseBagSectionDropTargets()
    for _, button in ipairs(Bags.activeBagSectionDrops) do
        button:Hide()
        button:ClearAllPoints()
        button._targetBagID = nil
        table.insert(Bags.bagSectionDropPool, button)
    end
    wipe(Bags.activeBagSectionDrops)
end

local function GetStatusColor(freeCount, totalCount)
    if not totalCount or totalCount <= 0 then
        return 0.45, 0.45, 0.45
    end

    local usedRatio = (totalCount - freeCount) / totalCount
    local normalR, normalG, normalB = 0.38, 0.88, 0.42
    local dangerR, dangerG, dangerB = 0.95, 0.32, 0.32

    if usedRatio <= 0.75 then
        return normalR, normalG, normalB
    end

    local t = (usedRatio - 0.75) / 0.25
    t = math.max(0, math.min(1, t))

    local r = normalR + (dangerR - normalR) * t
    local g = normalG + (dangerG - normalG) * t
    local b = normalB + (dangerB - normalB) * t
    return r, g, b
end

local function IsEmptyMap(map)
    return not map or next(map) == nil
end

local function SetSlotLockVisual(slot, locked)
    if SetItemButtonDesaturated then
        SetItemButtonDesaturated(slot, locked and true or false)
    end

    local icon = slot.icon or slot.Icon
    if icon and icon.SetDesaturated then
        icon:SetDesaturated(locked and true or false)
    end
end

----------------------------------------------------------------------------------------
-- Section Packing
----------------------------------------------------------------------------------------

local function GetSectionShape(slotCount, maxCols, minCols, balance)
    if slotCount <= 0 then
        return minCols, 0
    end

    local cols = math.min(slotCount, maxCols)
    if balance then
        cols = math.ceil(slotCount / math.ceil(slotCount / maxCols))
    end
    cols = math.max(cols, minCols)
    return cols, math.ceil(slotCount / cols)
end

function Bags.GetHeaderMinColumns(fontString, cellWidth, spacingX)
    local textWidth = fontString:GetUnboundedStringWidth() or 0
    return math.max(1, math.ceil((textWidth + HEADER_TEXT_PADDING + spacingX) / cellWidth))
end

function Bags.CreateSectionPacker(columns, cellHeight, spacingY)
    return {
        columns = columns,
        cellHeight = cellHeight,
        spacingY = spacingY,
        col = 0,
        rowStartY = 0,
        rowMaxHeight = 0,
    }
end

-- Places sections left to right in shelf rows, preserving section order.
-- Returns the section's first column, column count, and top offset.
function Bags.PackSection(packer, slotCount, minCols, headerHeight, balance)
    local columns = packer.columns
    minCols = math.min(math.max(minCols or 1, 1), columns)

    local cols, rows = GetSectionShape(slotCount, columns, minCols, balance)
    local remaining = columns - packer.col
    if packer.col > 0 and cols > remaining then
        local fitted = false
        -- Use the shelf's leftover width when that does not make the shelf taller.
        if balance and remaining >= minCols then
            local fitCols, fitRows = GetSectionShape(slotCount, remaining, minCols, true)
            if headerHeight + fitRows * packer.cellHeight <= packer.rowMaxHeight then
                cols, rows, fitted = fitCols, fitRows, true
            end
        end

        if not fitted then
            packer.rowStartY = packer.rowStartY + packer.rowMaxHeight + packer.spacingY
            packer.rowMaxHeight = 0
            packer.col = 0
        end
    end

    local startCol = packer.col
    packer.col = startCol + cols + MAIN_CAT_GAP
    packer.rowMaxHeight = math.max(packer.rowMaxHeight, headerHeight + rows * packer.cellHeight)
    return startCol, cols, packer.rowStartY
end

----------------------------------------------------------------------------------------
-- Slot Lifecycle
----------------------------------------------------------------------------------------

local function EnsureMainSlotFrame(slotKey)
    local slot = mainSlotFrameByKey[slotKey]
    if slot then return slot end

    if not Bags.AcquireSlot then return nil end

    slot = Bags.AcquireSlot()
    if not slot then return nil end

    mainSlotFrameByKey[slotKey] = slot
    return slot
end

local function ReleaseMainSlotFrame(slotKey)
    local slot = mainSlotFrameByKey[slotKey]
    if not slot then return end

    mainSlotFrameByKey[slotKey] = nil
    if Bags.ReleaseSlot then
        Bags.ReleaseSlot(slot)
    else
        slot:Hide()
    end
end

----------------------------------------------------------------------------------------
-- Header Lifecycle
----------------------------------------------------------------------------------------

local function EnsureMainSectionFrame(parent, sectionKey)
    local header = mainSectionFrameByKey[sectionKey]
    if header then return header end

    if not Bags.AcquireHeader then return nil end

    header = Bags.AcquireHeader()
    if not header then return nil end

    if header:GetParent() ~= parent then
        header:SetParent(parent)
    end

    mainSectionFrameByKey[sectionKey] = header
    return header
end

local function ReleaseMainSectionFrame(sectionKey)
    local header = mainSectionFrameByKey[sectionKey]
    if not header then return end

    mainSectionFrameByKey[sectionKey] = nil
    if Bags.ReleaseHeader then
        Bags.ReleaseHeader(header)
    else
        header:Hide()
    end
end

----------------------------------------------------------------------------------------
-- Visuals
----------------------------------------------------------------------------------------

local function UpdateMainSlotVisual(slot, slotState, cfg, borders, forceVisual, lockOnly)
    if not slot or not slotState then return end

    slot:Show()

    if slot:GetBagID() ~= slotState.bagID then
        slot:SetBagID(slotState.bagID)
    end

    if slot:GetID() ~= slotState.slotIndex then
        slot:SetID(slotState.slotIndex)
    end

    if Bags.SetSlotDisplayCategory then
        Bags.SetSlotDisplayCategory(slot, slotState.categoryKey)
    end

    SetItemButtonTexture(slot, slotState.iconFileID)
    SetItemButtonCount(slot, slotState.stackCount)
    slot.count = slotState.slotStackCount -- Smart stacks display a merged total; Blizzard reads the physical stack.
    SetItemButtonQuality(slot, slotState.quality, slotState.hyperlink)

    if slot.ItemSlotBackground then
        slot.ItemSlotBackground:Hide()
    end

    if slot.IconBorder and slotState.quality and slotState.quality > 1 then
        local r, g, b = GetItemQualityColor(slotState.quality)
        slot.IconBorder:SetVertexColor(r, g, b)
        slot.IconBorder:Show()
    elseif slot.IconBorder then
        slot.IconBorder:Hide()
    end

    local visualChanged = forceVisual or (slotVisualRevisionByFrame[slot] ~= slotState.visualRevision)
    local needsBorderHost = (cfg.ShowQualityBorder ~= false) and (not slot.RefineUIBagBorderHost)

    if visualChanged or needsBorderHost then
        if cfg.ShowQualityBorder ~= false and Bags.ApplyBagSlotBorder then
            Bags.ApplyBagSlotBorder(slot, slotState)
        end

        if borders then
            borders:ApplyItemBorder(slot, slotState.hyperlink, slotState.itemID)
        end

        slotVisualRevisionByFrame[slot] = slotState.visualRevision
    end

    SetSlotLockVisual(slot, slotState.isLocked)

    local alpha = slotState.searchMatch and 1 or 0.3
    slot:SetAlpha(alpha)

    local icon = slot.icon or slot.Icon
    if icon then icon:SetAlpha(alpha) end
    if slot.border then slot.border:SetAlpha(alpha) end
    if slot.RefineUIBagBorderHost then slot.RefineUIBagBorderHost:SetAlpha(alpha) end

    local itemLevelText = slot.RefineUIBorderItemLevel
    if itemLevelText then itemLevelText:SetAlpha(alpha) end
end

local function UpdateStatusWidgets(frame, snapshot)
    if not frame or not snapshot then return end

    if frame.NormalBagStatus then
        local r, g, b = GetStatusColor(snapshot.freeSlotsBag or 0, snapshot.normalTotal or 0)
        if frame.NormalBagStatus.SetBackdropBorderColor then
            frame.NormalBagStatus:SetBackdropBorderColor(r, g, b, 0.95)
        end
        if frame.NormalBagStatus.Count then
            frame.NormalBagStatus.Count:SetText(tostring(snapshot.freeSlotsBag or 0))
            frame.NormalBagStatus.Count:SetTextColor(0.9, 0.9, 0.9)
        end
    end

    if frame.ReagentBagStatus then
        local reagentTotal = snapshot.reagentTotal or 0
        local r, g, b = GetStatusColor(snapshot.freeSlotsReagent or 0, reagentTotal)
        if frame.ReagentBagStatus.SetBackdropBorderColor then
            frame.ReagentBagStatus:SetBackdropBorderColor(r, g, b, 0.95)
        end
        if frame.ReagentBagStatus.Count then
            if reagentTotal > 0 then
                frame.ReagentBagStatus.Count:SetText(tostring(snapshot.freeSlotsReagent or 0))
            else
                frame.ReagentBagStatus.Count:SetText("-")
            end
            frame.ReagentBagStatus.Count:SetTextColor(0.9, 0.9, 0.9)
        end
        frame.ReagentBagStatus:SetAlpha(reagentTotal > 0 and 1 or 0.6)
    end
end

----------------------------------------------------------------------------------------
-- Active Lists
----------------------------------------------------------------------------------------

local function BuildActiveLists()
    if type(Bags.activeHeaders) == "table" then
        wipe(Bags.activeHeaders)
        for _, header in pairs(mainSectionFrameByKey) do
            table.insert(Bags.activeHeaders, header)
        end
    end

    if type(Bags.activeSubHeaders) == "table" then
        wipe(Bags.activeSubHeaders)
    end

    if type(Bags.activeSlots) == "table" then
        wipe(Bags.activeSlots)
        for _, slot in pairs(mainSlotFrameByKey) do
            table.insert(Bags.activeSlots, slot)
        end
    end
end

----------------------------------------------------------------------------------------
-- Main Layout
----------------------------------------------------------------------------------------

local function LayoutMainSections(frame, snapshot)
    if not frame or not frame.ItemContainer then return end

    local cfg = Bags.GetConfig and Bags.GetConfig() or RefineUI.Config.Bags or {}
    local borders = GetBordersModule()
    local sections = Bags.MainSectionList or {}
    local slotStateByKey = Bags.SlotStateByKey or {}

    local SLOT_SIZE = Bags.SLOT_SIZE
    local ITEM_SPACING_X = Bags.ITEM_SPACING_X
    local ITEM_SPACING_Y = Bags.ITEM_SPACING_Y
    local HEADER_HEIGHT = Bags.HEADER_HEIGHT
    local BOTTOM_HEIGHT = Bags.BOTTOM_HEIGHT
    local PADDING = Bags.PADDING

    local availableWidth = frame.ItemContainer:GetWidth() or 0
    if availableWidth <= 0 then
        local fallbackColumns = Bags.COLUMNS or 1
        availableWidth = fallbackColumns * (SLOT_SIZE + ITEM_SPACING_X) - ITEM_SPACING_X
    end

    local columns = math.max(1, math.floor((availableWidth + ITEM_SPACING_X) / (SLOT_SIZE + ITEM_SPACING_X)))
    local contentWidth = columns * (SLOT_SIZE + ITEM_SPACING_X) - ITEM_SPACING_X
    local contentStartX = math.max(0, math.floor((availableWidth - contentWidth) * 0.5 + 0.5))
    local hasCursorItem = (Bags.HasCursorItem and Bags.HasCursorItem()) or false
    local cursorItemID = nil
    local sourceBagID = nil
    if Bags.GetCursorItemContext then
        hasCursorItem, cursorItemID, _, _, sourceBagID = Bags.GetCursorItemContext()
    end
    local combinedViewEnabled = Bags.IsCombinedViewEnabled and Bags.IsCombinedViewEnabled()
    local bagViewEnabled = Bags.IsBagViewEnabled and Bags.IsBagViewEnabled()

    local cellWidth = SLOT_SIZE + ITEM_SPACING_X
    local cellHeight = SLOT_SIZE + ITEM_SPACING_Y
    local packer = Bags.CreateSectionPacker(columns, cellHeight, ITEM_SPACING_Y)
    local visitedSectionKeys = {}
    local visitedSlotKeys = {}

    ReleaseCustomCategoryDropTargets()
    ReleaseBagSectionDropTargets()

    for _, section in ipairs(sections) do
        local slotKeys = section.slotKeys or {}
        local itemCount = #slotKeys
        local isCustomCategory = Bags.IsCustomCategoryKey and Bags.IsCustomCategoryKey(section.categoryKey)
        local isBagSection = bagViewEnabled and type(section.targetBagID) == "number"
        local showCustomDrop = isCustomCategory and not section.subCategoryKey and hasCursorItem
        local showBagDrop = isBagSection
            and hasCursorItem
            and type(cursorItemID) == "number"
            and Bags.CanAcceptBagSectionDrop
            and Bags.CanAcceptBagSectionDrop(section.targetBagID, cursorItemID, sourceBagID)
        local visibleSlots = itemCount + (showCustomDrop and 1 or 0) + (showBagDrop and 1 or 0)
        local showEmptyCustomHeader = isCustomCategory and itemCount == 0 and not showCustomDrop
        local showEmptyBagHeader = isBagSection and itemCount == 0
        local showSectionHeader = not (combinedViewEnabled and section.categoryKey == COMBINED_SECTION_CATEGORY)

        if visibleSlots > 0 or showEmptyCustomHeader or showEmptyBagHeader then
            local sectionFrame
            local minCols = 1
            local sectionHeaderHeight = showSectionHeader and HEADER_HEIGHT or 0

            if showSectionHeader then
                sectionFrame = EnsureMainSectionFrame(frame.ItemContainer, section.key)
                if sectionFrame then
                    visitedSectionKeys[section.key] = true
                    local label = section.label or section.categoryKey or "Other"
                    sectionFrame.Text:SetText(string.format("%s (%d)", label, itemCount))
                    minCols = Bags.GetHeaderMinColumns(sectionFrame.Text, cellWidth, ITEM_SPACING_X)
                end
            end

            local startCol, slotColumns, sectionTop = Bags.PackSection(packer, visibleSlots, minCols, sectionHeaderHeight, showSectionHeader)
            local sectionX = contentStartX + startCol * cellWidth
            local slotTop = sectionTop + sectionHeaderHeight

            if sectionFrame then
                sectionFrame:ClearAllPoints()
                sectionFrame:SetPoint("TOPLEFT", frame.ItemContainer, "TOPLEFT", sectionX, -sectionTop)
                sectionFrame:SetWidth(math.max(50, slotColumns * cellWidth - ITEM_SPACING_X))

                if section.categoryKey == "Recent" then
                    sectionFrame.Text:SetTextColor(0.3, 1, 0.3)
                    sectionFrame.Line:SetColorTexture(0.3, 1, 0.3, 0.5)
                elseif isCustomCategory then
                    sectionFrame.Text:SetTextColor(0.68, 0.83, 1.0)
                    sectionFrame.Line:SetColorTexture(0.45, 0.65, 0.95, 0.55)
                else
                    sectionFrame.Text:SetTextColor(1, 0.82, 0)
                    sectionFrame.Line:SetColorTexture(1, 0.82, 0, 0.45)
                end

                if itemCount <= 1 then
                    sectionFrame.Line:Hide()
                else
                    sectionFrame.Line:Show()
                end
            end

            for index, slotKey in ipairs(slotKeys) do
                local slotState = slotStateByKey[slotKey]
                if slotState then
                    local slot = EnsureMainSlotFrame(slotKey)
                    if slot then
                        visitedSlotKeys[slotKey] = true
                        local idx = index - 1
                        local xPos = sectionX + (idx % slotColumns) * cellWidth
                        local yPos = -(slotTop + math.floor(idx / slotColumns) * cellHeight)

                        slot:ClearAllPoints()
                        slot:SetPoint("TOPLEFT", frame.ItemContainer, "TOPLEFT", xPos, yPos)
                        UpdateMainSlotVisual(slot, slotState, cfg, borders, false, false)
                    elseif Bags.MarkLayoutDirtyAfterCombat then
                        Bags.MarkLayoutDirtyAfterCombat()
                    end
                end
            end

            if showCustomDrop then
                local dropIndex = itemCount
                local dropX = sectionX + (dropIndex % slotColumns) * cellWidth
                local dropY = -(slotTop + math.floor(dropIndex / slotColumns) * cellHeight)

                local dropButton = AcquireCustomCategoryDropTarget(frame.ItemContainer)
                dropButton:SetFrameStrata(frame:GetFrameStrata() or "MEDIUM")
                dropButton:SetFrameLevel((frame.ItemContainer:GetFrameLevel() or 1) + 25)
                dropButton:SetSize(SLOT_SIZE, SLOT_SIZE)
                dropButton:SetPoint("TOPLEFT", frame.ItemContainer, "TOPLEFT", dropX, dropY)
                dropButton._customCategoryKey = section.categoryKey
                table.insert(Bags.activeCustomDrops, dropButton)
            end

            if showBagDrop then
                local dropIndex = itemCount + (showCustomDrop and 1 or 0)
                local dropX = sectionX + (dropIndex % slotColumns) * cellWidth
                local dropY = -(slotTop + math.floor(dropIndex / slotColumns) * cellHeight)

                local dropButton = AcquireBagSectionDropTarget(frame.ItemContainer)
                dropButton:SetFrameStrata(frame:GetFrameStrata() or "MEDIUM")
                dropButton:SetFrameLevel((frame.ItemContainer:GetFrameLevel() or 1) + 25)
                dropButton:SetSize(SLOT_SIZE, SLOT_SIZE)
                dropButton:SetPoint("TOPLEFT", frame.ItemContainer, "TOPLEFT", dropX, dropY)
                dropButton._targetBagID = section.targetBagID
                table.insert(Bags.activeBagSectionDrops, dropButton)
            end
        end
    end

    local yOffset = packer.rowStartY
    if packer.rowMaxHeight > 0 then
        yOffset = packer.rowStartY + packer.rowMaxHeight + ITEM_SPACING_Y
    end

    local staleSectionKeys = {}
    for sectionKey in pairs(mainSectionFrameByKey) do
        if not visitedSectionKeys[sectionKey] then
            table.insert(staleSectionKeys, sectionKey)
        end
    end

    for _, sectionKey in ipairs(staleSectionKeys) do
        ReleaseMainSectionFrame(sectionKey)
    end

    local staleSlotKeys = {}
    for slotKey in pairs(mainSlotFrameByKey) do
        if not visitedSlotKeys[slotKey] then
            table.insert(staleSlotKeys, slotKey)
        end
    end

    for _, slotKey in ipairs(staleSlotKeys) do
        ReleaseMainSlotFrame(slotKey)
    end

    BuildActiveLists()

    local totalHeight = yOffset + 60 + BOTTOM_HEIGHT + PADDING * 2
    frame:SetHeight(math.max(200, totalHeight))

    if frame.MoneyFrame then
        MoneyFrame_Update(frame.MoneyFrame:GetName(), GetMoney())
    end

    UpdateStatusWidgets(frame, snapshot)
end

----------------------------------------------------------------------------------------
-- Delta Application
----------------------------------------------------------------------------------------

local function IterateDeltaBucket(bucket, fn)
    if not bucket then return end
    for slotKey, slotState in pairs(bucket) do
        fn(slotKey, slotState)
    end
end

local function ApplyMainDelta(frame, delta, opts)
    if not frame or not frame.ItemContainer then return end

    opts = opts or {}
    local cfg = Bags.GetConfig and Bags.GetConfig() or RefineUI.Config.Bags or {}
    local borders = GetBordersModule()

    if Bags.RefreshSortControl then
        Bags.RefreshSortControl()
    end

    IterateDeltaBucket(delta.removed, function(slotKey, oldState)
        if oldState and oldState.viewKey == "main" then
            ReleaseMainSlotFrame(slotKey)
        end
    end)

    IterateDeltaBucket(delta.movedFrom, function(slotKey, oldState)
        if oldState and oldState.viewKey == "main" then
            local nextState = Bags.SlotStateByKey and Bags.SlotStateByKey[slotKey]
            if not nextState or nextState.viewKey ~= "main" then
                ReleaseMainSlotFrame(slotKey)
            end
        end
    end)

    IterateDeltaBucket(delta.added, function(slotKey, slotState)
        if slotState and slotState.viewKey == "main" then
            local slot = EnsureMainSlotFrame(slotKey)
            if slot then
                UpdateMainSlotVisual(slot, slotState, cfg, borders, true, false)
            end
        end
    end)

    IterateDeltaBucket(delta.changed, function(slotKey, slotState)
        if slotState and slotState.viewKey == "main" then
            local slot = EnsureMainSlotFrame(slotKey)
            if slot then
                UpdateMainSlotVisual(slot, slotState, cfg, borders, true, false)
            end
        end
    end)

    IterateDeltaBucket(delta.movedCategory, function(slotKey, slotState)
        if slotState and slotState.viewKey == "main" then
            local slot = EnsureMainSlotFrame(slotKey)
            if slot then
                UpdateMainSlotVisual(slot, slotState, cfg, borders, true, false)
            end
        end
    end)

    IterateDeltaBucket(delta.lockOnly, function(slotKey, slotState)
        if slotState and slotState.viewKey == "main" then
            local slot = EnsureMainSlotFrame(slotKey)
            if slot then
                UpdateMainSlotVisual(slot, slotState, cfg, borders, false, true)
            end
        end
    end)

    local hasCursorItem = (Bags.HasCursorItem and Bags.HasCursorItem()) or false
    local dirtyMain = Bags.DirtySections and Bags.DirtySections.main
    local containerWidth = frame.ItemContainer:GetWidth() or 0
    local needsReflow = opts.forceReflow
        or delta.structural
        or IsEmptyMap(mainSectionFrameByKey)
        or (lastHasCursorItem ~= hasCursorItem)
        or (appliedLayoutRevision ~= (Bags._layoutConfigRevision or 0))
        or (frame.RefineUILastLayoutWidth ~= containerWidth)
        or (dirtyMain and not IsEmptyMap(dirtyMain))

    lastHasCursorItem = hasCursorItem
    appliedLayoutRevision = Bags._layoutConfigRevision or 0
    frame.RefineUILastLayoutWidth = containerWidth

    if needsReflow then
        LayoutMainSections(frame, Bags._snapshot)
    else
        UpdateStatusWidgets(frame, Bags._snapshot)
    end

    if Bags.DirtySections then
        Bags.DirtySections.main = {}
    end
end

----------------------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------------------

function Bags.ApplyBagDelta(frame, delta, opts)
    if not frame or not frame.ItemContainer then return end

    opts = opts or {}
    delta = delta or Bags.PendingDelta or {
        added = {},
        removed = {},
        changed = {},
        movedCategory = {},
        movedFrom = {},
        lockOnly = {},
        structural = true,
    }

    if InCombatLockdown() and not opts.force then
        if Bags.MarkLayoutDirtyAfterCombat then
            Bags.MarkLayoutDirtyAfterCombat()
        end
        return
    end

    ApplyMainDelta(frame, delta, opts)
end

function Bags.RenderBagSnapshot(frame, snapshot, opts)
    frame = frame or Bags.Frame
    if not frame then return end

    opts = opts or {}

    if not Bags._snapshot then
        if Bags.RefreshBagState then
            Bags.RefreshBagState({ forceBuild = true })
        end
    end

    local applyOpts = {
        force = opts.force and true or false,
        forceReflow = opts.forceReflow and true or IsEmptyMap(mainSectionFrameByKey),
    }

    Bags.ApplyBagDelta(frame, Bags.PendingDelta, applyOpts)
end

function Bags.RefreshSnapshot(opts)
    opts = opts or {}
    local shouldBuild = opts.build ~= false and (
        opts.forceBuild
        or Bags._snapshotDirty
        or Bags._pendingSnapshotRefresh
        or not Bags._snapshot
        or (opts.renderOnly and not opts.cursorOnly)
        or opts.lockOnly
        or opts.equipmentSetsChanged
    )

    local snapshot, delta
    if shouldBuild and Bags.RefreshBagState then
        snapshot, delta = Bags.RefreshBagState(opts)
    else
        snapshot = Bags._snapshot
        delta = Bags.PendingDelta
    end

    if opts.render and Bags.Frame and Bags.Frame:IsShown() then
        if InCombatLockdown() and not opts.force then
            if Bags.MarkLayoutDirtyAfterCombat then
                Bags.MarkLayoutDirtyAfterCombat()
            end
        else
            Bags.ApplyBagDelta(Bags.Frame, delta, { forceReflow = opts.force or opts.forceReflow })
        end
    end

    if opts.render and Bags.ReagentFrame and Bags.ReagentFrame:IsShown() and Bags.ApplyReagentDelta then
        if InCombatLockdown() and not opts.force then
            if Bags.MarkLayoutDirtyAfterCombat then
                Bags.MarkLayoutDirtyAfterCombat()
            end
        else
            Bags.ApplyReagentDelta(Bags.ReagentFrame, delta, { forceReflow = opts.force or opts.forceReflow })
        end
    end

    return snapshot, delta
end

function Bags.UpdateLayout(frame, force)
    frame = frame or Bags.Frame
    if not frame or not frame.ItemContainer then return end

    Bags.RefreshSnapshot({
        render = true,
        force = force and true or false,
        forceBuild = true,
        forceReflow = force and true or false,
    })
end
