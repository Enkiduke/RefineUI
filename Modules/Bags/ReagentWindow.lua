----------------------------------------------------------------------------------------
-- Bags Component: Reagent Window
-- Description: Reagent bag frame and layout logic.
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

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------

local pairs = pairs
local ipairs = ipairs
local next = next
local type = type
local tostring = tostring
local tinsert = tinsert
local tremove = tremove
local wipe = wipe
local floor = math.floor
local max = math.max
local min = math.min
local ceil = math.ceil
local tsort = table.sort
local GetItemInfo = GetItemInfo
local GetItemInfoInstant = GetItemInfoInstant
local GetItemSubClassInfo = GetItemSubClassInfo
local GetItemQualityColor = GetItemQualityColor
local InCombatLockdown = InCombatLockdown

local ITEMCLASS_PROFESSION = (Enum and Enum.ItemClass and Enum.ItemClass.Profession) or 19
local ITEMCLASS_REAGENT = (Enum and Enum.ItemClass and Enum.ItemClass.Reagent) or 5
local ITEMCLASS_TRADEGOODS = (Enum and Enum.ItemClass and (Enum.ItemClass.Tradegoods or Enum.ItemClass.TradeGoods)) or 7
local ITEMCLASS_ITEM_ENHANCEMENT = (Enum and Enum.ItemClass and Enum.ItemClass.ItemEnhancement) or 8
local ITEMCLASS_RECIPE = (Enum and Enum.ItemClass and Enum.ItemClass.Recipe) or 9
local REAGENT_TOP_INSET = 42

----------------------------------------------------------------------------------------
-- Pools
----------------------------------------------------------------------------------------

local reagentHeaderPool = {}
local reagentSlotPool = {}
local activeReagentHeaders = {}
local activeReagentSlots = {}
local reagentSlotCount = 0
local reagentAppliedLayoutRevision = 0

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------

Bags.ReagentSlotFrameByKey = Bags.ReagentSlotFrameByKey or {}
Bags.ReagentSectionFrameByKey = Bags.ReagentSectionFrameByKey or {}

local reagentSlotFrameByKey = Bags.ReagentSlotFrameByKey
local reagentSectionFrameByKey = Bags.ReagentSectionFrameByKey
local slotVisualRevisionByFrame = Bags.slotVisualRevisionByFrame or setmetatable({}, { __mode = "k" })
Bags.slotVisualRevisionByFrame = slotVisualRevisionByFrame

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------

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

local function HasReagentBag()
    return (C_Container.GetContainerNumSlots(5) or 0) > 0
end

----------------------------------------------------------------------------------------
-- Header Lifecycle
----------------------------------------------------------------------------------------

local function AcquireReagentHeader(frame)
    local header = table.remove(reagentHeaderPool)
    if header then
        header:Show()
        return header
    end

    header = CreateFrame("Frame", nil, frame.ItemContainer)
    header:SetHeight(Bags.HEADER_HEIGHT or 18)

    header.Text = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header.Text:SetPoint("LEFT", 2, 0)

    if Bags.ApplyHeaderFont then
        Bags.ApplyHeaderFont(header.Text, 12)
    end

    header.Line = header:CreateTexture(nil, "ARTWORK")
    header.Line:SetHeight(1)
    header.Line:SetPoint("LEFT", header.Text, "RIGHT", 8, 0)
    header.Line:SetPoint("RIGHT", header, "RIGHT", -2, 0)

    return header
end

local function ReleaseReagentHeader(header)
    if not header then return end

    header:Hide()
    header:ClearAllPoints()

    if header.Text then
        header.Text:SetText("")
    end

    table.insert(reagentHeaderPool, header)
end

----------------------------------------------------------------------------------------
-- Slot Lifecycle
----------------------------------------------------------------------------------------

local function AcquireReagentSlot(frame)
    local slot = table.remove(reagentSlotPool)
    if slot then
        slot:SetSize(Bags.SLOT_SIZE, Bags.SLOT_SIZE)
        if Bags.EnsureBagSlotBorderHost then
            Bags.EnsureBagSlotBorderHost(slot)
        end
        slot:Show()
        return slot
    end

    if InCombatLockdown() then
        if Bags.MarkLayoutDirtyAfterCombat then
            Bags.MarkLayoutDirtyAfterCombat()
        end
        return nil
    end

    reagentSlotCount = reagentSlotCount + 1
    local name = "RefineUI_ReagentSlot" .. reagentSlotCount
    slot = CreateFrame("ItemButton", name, frame.ItemContainer, "ContainerFrameItemButtonTemplate")
    slot:SetSize(Bags.SLOT_SIZE, Bags.SLOT_SIZE)

    if slot.ItemSlotBackground then
        slot.ItemSlotBackground:Hide()
    end

    if slot.NormalTexture then
        slot.NormalTexture:SetAlpha(0)
    end

    local normalTex = slot:GetNormalTexture()
    if normalTex then
        normalTex:SetAlpha(0)
    end

    if slot.BattlepayItemTexture then slot.BattlepayItemTexture:SetAlpha(0) end
    if slot.NewItemTexture then slot.NewItemTexture:SetAlpha(0) end
    if slot.BagIndicator then slot.BagIndicator:Hide() end

    if Bags.EnsureBagSlotBorderHost then
        Bags.EnsureBagSlotBorderHost(slot)
    end

    return slot
end

local function ReleaseReagentSlot(slot)
    if not slot then return end

    slot:Hide()
    slot:ClearAllPoints()

    SetItemButtonTexture(slot, 0)
    SetItemButtonCount(slot, 0)
    SetItemButtonQuality(slot, nil)

    if slot.IconBorder then
        slot.IconBorder:Hide()
    end

    if slot.ItemSlotBackground then
        slot.ItemSlotBackground:Show()
    end

    table.insert(reagentSlotPool, slot)
end

----------------------------------------------------------------------------------------
-- Frame Management
----------------------------------------------------------------------------------------

local function EnsureReagentSlotFrame(frame, slotKey)
    local slot = reagentSlotFrameByKey[slotKey]
    if slot then return slot end

    slot = AcquireReagentSlot(frame)
    if not slot then return nil end

    reagentSlotFrameByKey[slotKey] = slot
    return slot
end

local function ReleaseReagentSlotFrame(slotKey)
    local slot = reagentSlotFrameByKey[slotKey]
    if not slot then return end

    reagentSlotFrameByKey[slotKey] = nil
    ReleaseReagentSlot(slot)
end

local function EnsureReagentSectionFrame(frame, sectionKey)
    local header = reagentSectionFrameByKey[sectionKey]
    if header then return header end

    header = AcquireReagentHeader(frame)
    if not header then return nil end

    reagentSectionFrameByKey[sectionKey] = header
    return header
end

local function ReleaseReagentSectionFrame(sectionKey)
    local header = reagentSectionFrameByKey[sectionKey]
    if not header then return end

    reagentSectionFrameByKey[sectionKey] = nil
    ReleaseReagentHeader(header)
end

function Bags.WarmReagentSlotPool(frame, desiredCount)
    if InCombatLockdown() then return end

    frame = frame or (Bags.EnsureReagentWindow and Bags.EnsureReagentWindow()) or Bags.ReagentFrame
    if not frame or not frame.ItemContainer then return end

    local baseCount = desiredCount
    if baseCount == nil and C_Container and C_Container.GetContainerNumSlots then
        baseCount = C_Container.GetContainerNumSlots(5) or 0
    end

    baseCount = tonumber(baseCount) or 0
    if baseCount < 36 then baseCount = 36 end
    local targetCount = baseCount + 8

    local guard = targetCount + 64
    local warmedSlots = {}

    while reagentSlotCount < targetCount and guard > 0 do
        local slot = AcquireReagentSlot(frame)
        if not slot then break end
        table.insert(warmedSlots, slot)
        guard = guard - 1
    end

    for i = 1, #warmedSlots do
        ReleaseReagentSlot(warmedSlots[i])
    end
end

----------------------------------------------------------------------------------------
-- Category Logic
----------------------------------------------------------------------------------------

local function GetItemClassData(itemID, itemLink)
    local source = itemID or itemLink
    if source and GetItemInfoInstant then
        local _, _, _, _, _, _, _, _, _, _, _, classID, subClassID = GetItemInfoInstant(source)
        if classID then
            return classID, subClassID
        end
    end

    local _, _, _, _, _, _, _, _, _, _, _, classID, subClassID = GetItemInfo(itemLink or itemID)
    return classID, subClassID
end

local function GetCategoryNameFromSubclass(classID, subClassID)
    if not classID or subClassID == nil then return nil end

    local name = GetItemSubClassInfo(classID, subClassID)
    if name and name ~= "" then
        return name
    end

    return nil
end

local function GetReagentCategory(itemID, itemLink)
    local classID, subClassID = GetItemClassData(itemID, itemLink)

    if classID == ITEMCLASS_PROFESSION and subClassID ~= nil then
        local name = GetCategoryNameFromSubclass(ITEMCLASS_PROFESSION, subClassID) or ("Profession " .. tostring(subClassID))
        return "PROF:" .. subClassID, name, 1000 + subClassID
    end

    if (classID == ITEMCLASS_REAGENT or classID == ITEMCLASS_TRADEGOODS) and subClassID ~= nil then
        local name = GetCategoryNameFromSubclass(classID, subClassID)
        if name then
            return string.format("MAT:%d:%d", classID, subClassID), name, 3000 + (classID * 100) + subClassID
        end
    end

    if classID == ITEMCLASS_ITEM_ENHANCEMENT then
        return "ITEM_ENHANCEMENT", "Item Enhancement", 7000
    end

    if classID == ITEMCLASS_RECIPE then
        return "RECIPES", AUCTION_CATEGORY_RECIPES or "Recipes", 7100
    end

    return "OTHER", OTHER or "Other", 9999
end

Bags.GetReagentSlotCategory = function(itemID, itemLink)
    return GetReagentCategory(itemID, itemLink)
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
-- Visuals
----------------------------------------------------------------------------------------

local function UpdateReagentSlotVisual(slot, slotState, cfg, borders, forceVisual, lockOnly)
    if not slot or not slotState then return end

    slot:Show()

    if slot:GetBagID() ~= 5 then
        slot:SetBagID(5)
    end

    if slot:GetID() ~= slotState.slotIndex then
        slot:SetID(slotState.slotIndex)
    end

    SetItemButtonTexture(slot, slotState.iconFileID)
    SetItemButtonCount(slot, slotState.stackCount)
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

----------------------------------------------------------------------------------------
-- Active Lists
----------------------------------------------------------------------------------------

local function BuildActiveReagentLists()
    wipe(activeReagentHeaders)
    wipe(activeReagentSlots)

    for _, header in pairs(reagentSectionFrameByKey) do
        table.insert(activeReagentHeaders, header)
    end

    for _, slot in pairs(reagentSlotFrameByKey) do
        table.insert(activeReagentSlots, slot)
    end
end

----------------------------------------------------------------------------------------
-- Main Layout
----------------------------------------------------------------------------------------

local function LayoutReagentSections(frame, snapshot)
    if not frame or not frame.ItemContainer then return end

    local cfg = Bags.GetConfig and Bags.GetConfig() or RefineUI.Config.Bags or {}
    local borders = GetBordersModule()
    local sections = Bags.ReagentSectionList or {}
    local slotStateByKey = Bags.SlotStateByKey or {}

    local SLOT_SIZE = Bags.SLOT_SIZE or 37
    local ITEM_SPACING_X = Bags.ITEM_SPACING_X or 5
    local ITEM_SPACING_Y = Bags.ITEM_SPACING_Y or 5
    local HEADER_HEIGHT = Bags.HEADER_HEIGHT or 18

    local availableWidth = frame.ItemContainer:GetWidth() or 0
    if availableWidth <= 0 then
        availableWidth = frame:GetWidth() - ((Bags.PADDING or 8) * 2)
    end

    local columns = math.floor((availableWidth + ITEM_SPACING_X) / (SLOT_SIZE + ITEM_SPACING_X))
    columns = math.max(1, columns)

    local contentWidth = columns * (SLOT_SIZE + ITEM_SPACING_X) - ITEM_SPACING_X
    local contentStartX = math.max(0, math.floor((availableWidth - contentWidth) * 0.5 + 0.5))
    local MAIN_CAT_GAP = 1

    local visitedSectionKeys = {}
    local visitedSlotKeys = {}
    local yOffset = 0
    local currentCol = 0
    local rowMaxHeight = 0
    local rowStartY = yOffset

    for _, section in ipairs(sections) do
        local slotKeys = section.slotKeys or {}
        local itemCount = #slotKeys

        if itemCount > 0 then
            local colsNeeded = math.min(math.max(itemCount, 1), columns)

            if currentCol > 0 and (currentCol + colsNeeded > columns) then
                yOffset = rowStartY + rowMaxHeight + ITEM_SPACING_Y
                currentCol = 0
                rowMaxHeight = 0
                rowStartY = yOffset
            end

            local header = EnsureReagentSectionFrame(frame, section.key)
            if header then
                visitedSectionKeys[section.key] = true
                header:ClearAllPoints()
                header:SetPoint(
                    "TOPLEFT",
                    frame.ItemContainer,
                    "TOPLEFT",
                    contentStartX + currentCol * (SLOT_SIZE + ITEM_SPACING_X),
                    -yOffset
                )

                local headerWidth = colsNeeded * (SLOT_SIZE + ITEM_SPACING_X) - ITEM_SPACING_X
                header:SetWidth(math.max(50, headerWidth))
                header.Text:SetText(string.format("%s (%d)", section.label or section.key, itemCount))
                header.Text:SetTextColor(1, 0.82, 0)
                header.Line:SetColorTexture(1, 0.82, 0, 0.45)

                if itemCount <= 1 then
                    header.Line:Hide()
                else
                    header.Line:Show()
                end
            end

            local slotColumns = math.max(1, colsNeeded)
            for index, slotKey in ipairs(slotKeys) do
                local slotState = slotStateByKey[slotKey]
                if slotState then
                    local slot = EnsureReagentSlotFrame(frame, slotKey)
                    if slot then
                        visitedSlotKeys[slotKey] = true
                        local idx = index - 1
                        local row = math.floor(idx / slotColumns)
                        local col = currentCol + (idx % slotColumns)
                        local xPos = contentStartX + col * (SLOT_SIZE + ITEM_SPACING_X)
                        local yPos = -(yOffset + HEADER_HEIGHT + row * (SLOT_SIZE + ITEM_SPACING_Y))

                        slot:ClearAllPoints()
                        slot:SetPoint("TOPLEFT", frame.ItemContainer, "TOPLEFT", xPos, yPos)
                        UpdateReagentSlotVisual(slot, slotState, cfg, borders, false, false)
                    end
                end
            end

            local rowsUsed = math.ceil(itemCount / slotColumns)
            local currentCategoryHeight = HEADER_HEIGHT + rowsUsed * (SLOT_SIZE + ITEM_SPACING_Y)
            rowMaxHeight = math.max(rowMaxHeight, currentCategoryHeight)
            currentCol = currentCol + colsNeeded + MAIN_CAT_GAP

            if currentCol >= columns then
                yOffset = rowStartY + rowMaxHeight + ITEM_SPACING_Y
                currentCol = 0
                rowMaxHeight = 0
                rowStartY = yOffset
            end
        end
    end

    if rowMaxHeight > 0 then
        yOffset = rowStartY + rowMaxHeight
    end

    if yOffset > 0 then
        yOffset = math.max(0, yOffset - ITEM_SPACING_Y)
    end

    local staleSections = {}
    for sectionKey in pairs(reagentSectionFrameByKey) do
        if not visitedSectionKeys[sectionKey] then
            table.insert(staleSections, sectionKey)
        end
    end

    for _, sectionKey in ipairs(staleSections) do
        ReleaseReagentSectionFrame(sectionKey)
    end

    local staleSlots = {}
    for slotKey in pairs(reagentSlotFrameByKey) do
        if not visitedSlotKeys[slotKey] then
            table.insert(staleSlots, slotKey)
        end
    end

    for _, slotKey in ipairs(staleSlots) do
        ReleaseReagentSlotFrame(slotKey)
    end

    local freeSlots = snapshot and snapshot.freeSlotsReagent or 0
    if Bags.SetFrameTitle then
        Bags.SetFrameTitle(frame, string.format("%s (%d free)", REAGENT_BAG or "Reagent Bag", freeSlots))
    end

    local contentInset = Bags.CONTENT_INSET or 5
    local chromeTop = REAGENT_TOP_INSET + contentInset
    local chromeBottom = (Bags.PADDING or 8) + contentInset
    local totalHeight = yOffset + chromeTop + chromeBottom

    frame:SetHeight(math.max(150, totalHeight))

    BuildActiveReagentLists()
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

----------------------------------------------------------------------------------------
-- Window Management
----------------------------------------------------------------------------------------

function Bags.EnsureReagentWindow()
    if Bags.ReagentFrame then return Bags.ReagentFrame end
    if not Bags.Frame then return nil end

    local frameTemplate = Bags.BagWindowFrameTemplate
        or (_G.ButtonFrameTemplateNoPortrait and "ButtonFrameTemplateNoPortrait")
        or (_G.ButtonFrameTemplate and "ButtonFrameTemplate")
        or "PortraitFrameFlatTemplate"

    local frame = CreateFrame("Frame", "RefineUI_ReagentBag", UIParent, frameTemplate)
    if Bags.ApplyFlatFrameNoPortraitCorner then
        Bags.ApplyFlatFrameNoPortraitCorner(frame)
    end

    frame:SetSize(340, 360)
    frame:SetFrameStrata(Bags.Frame:GetFrameStrata() or "MEDIUM")
    frame:SetFrameLevel((Bags.Frame:GetFrameLevel() or 1) + 2)
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:Hide()

    if Bags.SetFrameTitle then
        Bags.SetFrameTitle(frame, REAGENT_BAG or "Reagent Bag")
    end

    if frame.PortraitContainer then frame.PortraitContainer:Hide() end

    if frame.CloseButton then
        frame.CloseButton:HookScript("OnClick", function()
            if Bags.SetReagentWindowShown then
                Bags.SetReagentWindowShown(false)
            end
        end)
    end

    local iconParent = (frame.NineSlice and frame.NineSlice.CreateTexture) and frame.NineSlice or frame
    local iconAnchor = (frame.NineSlice and frame.NineSlice.TopLeftCorner) or frame
    frame.ReagentIcon = iconParent:CreateTexture(nil, "OVERLAY", nil, 7)
    frame.ReagentIcon:SetAtlas("bag-reagent", true)
    frame.ReagentIcon:SetScale(1.35)
    frame.ReagentIcon:SetPoint("TOPLEFT", iconAnchor, "TOPLEFT", 0, 0)
    frame.ReagentIcon:SetDrawLayer("OVERLAY", 7)

    local itemContainer = CreateFrame("Frame", nil, frame)
    local contentInset = Bags.CONTENT_INSET or 5
    local contentInsetLeft = Bags.CONTENT_INSET_LEFT or contentInset
    local contentInsetRight = Bags.CONTENT_INSET_RIGHT or contentInset

    itemContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", (Bags.PADDING or 8) + contentInsetLeft, -REAGENT_TOP_INSET - contentInset)
    itemContainer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -((Bags.PADDING or 8) + contentInsetRight), ((Bags.PADDING or 8) + contentInset))
    frame.ItemContainer = itemContainer

    frame:SetScript("OnHide", function()
        if Bags.UpdateReagentToggleArrow then
            Bags.UpdateReagentToggleArrow()
        end
    end)

    frame:HookScript("OnShow", function(self)
        if Bags.ApplyReagentLayoutConfig then
            Bags.ApplyReagentLayoutConfig()
        end
        if Bags.UpdateReagentLayout then
            Bags.UpdateReagentLayout(self)
        end
        if Bags.UpdateReagentToggleArrow then
            Bags.UpdateReagentToggleArrow()
        end
    end)

    Bags.ReagentFrame = frame
    return frame
end

function Bags.ApplyReagentLayoutConfig()
    local frame = Bags.ReagentFrame
    if not frame then return end

    local width = math.floor((Bags.BAG_WIDTH or 600) * 0.58)
    if width < 290 then
        width = 290
    elseif width > 520 then
        width = 520
    end

    frame:SetWidth(width)
end

function Bags.ApplyReagentDelta(frame, delta, opts)
    frame = frame or Bags.ReagentFrame
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

    local cfg = Bags.GetConfig and Bags.GetConfig() or RefineUI.Config.Bags or {}
    local borders = GetBordersModule()

    IterateDeltaBucket(delta.removed, function(slotKey, oldState)
        if oldState and oldState.viewKey == "reagent" then
            ReleaseReagentSlotFrame(slotKey)
        end
    end)

    IterateDeltaBucket(delta.movedFrom, function(slotKey, oldState)
        if oldState and oldState.viewKey == "reagent" then
            local nextState = Bags.SlotStateByKey and Bags.SlotStateByKey[slotKey]
            if not nextState or nextState.viewKey ~= "reagent" then
                ReleaseReagentSlotFrame(slotKey)
            end
        end
    end)

    IterateDeltaBucket(delta.added, function(slotKey, slotState)
        if slotState and slotState.viewKey == "reagent" then
            local slot = EnsureReagentSlotFrame(frame, slotKey)
            if slot then
                UpdateReagentSlotVisual(slot, slotState, cfg, borders, true, false)
            end
        end
    end)

    IterateDeltaBucket(delta.changed, function(slotKey, slotState)
        if slotState and slotState.viewKey == "reagent" then
            local slot = EnsureReagentSlotFrame(frame, slotKey)
            if slot then
                UpdateReagentSlotVisual(slot, slotState, cfg, borders, true, false)
            end
        end
    end)

    IterateDeltaBucket(delta.movedCategory, function(slotKey, slotState)
        if slotState and slotState.viewKey == "reagent" then
            local slot = EnsureReagentSlotFrame(frame, slotKey)
            if slot then
                UpdateReagentSlotVisual(slot, slotState, cfg, borders, true, false)
            end
        end
    end)

    IterateDeltaBucket(delta.lockOnly, function(slotKey, slotState)
        if slotState and slotState.viewKey == "reagent" then
            local slot = EnsureReagentSlotFrame(frame, slotKey)
            if slot then
                UpdateReagentSlotVisual(slot, slotState, cfg, borders, false, true)
            end
        end
    end)

    local dirtyReagent = Bags.DirtySections and Bags.DirtySections.reagent
    local containerWidth = frame.ItemContainer:GetWidth() or 0
    local needsReflow = opts.forceReflow
        or delta.structural
        or next(reagentSectionFrameByKey) == nil
        or (dirtyReagent and next(dirtyReagent) ~= nil)
        or (frame.RefineUILastLayoutWidth ~= containerWidth)
        or (reagentAppliedLayoutRevision ~= (Bags._layoutConfigRevision or 0))

    reagentAppliedLayoutRevision = Bags._layoutConfigRevision or 0
    frame.RefineUILastLayoutWidth = containerWidth

    if needsReflow then
        LayoutReagentSections(frame, Bags._snapshot)
    end

    if Bags.DirtySections then
        Bags.DirtySections.reagent = {}
    end
end

function Bags.UpdateReagentLayout(frame)
    frame = frame or Bags.ReagentFrame
    if not frame then return end

    if not Bags._snapshot and Bags.RefreshBagState then
        Bags.RefreshBagState({ forceBuild = true })
    end

    Bags.ApplyReagentDelta(frame, Bags.PendingDelta, { forceReflow = next(reagentSectionFrameByKey) == nil })
end

function Bags.UpdateReagentToggleArrow()
    local button = Bags.Frame and Bags.Frame.ReagentBagStatus
    if not button or not button.ToggleArrow then return end

    local shown = Bags.ReagentFrame and Bags.ReagentFrame:IsShown()
    local atlas = shown and "common-icon-backarrow" or "common-icon-forwardarrow"
    local ok = pcall(button.ToggleArrow.SetAtlas, button.ToggleArrow, atlas, false)

    if not ok then
        button.ToggleArrow:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
    end

    button.ToggleArrow:SetVertexColor(0.85, 0.85, 0.85, 1)
end

function Bags.UpdateReagentWindowState()
    local main = Bags.Frame
    if not main then return end

    local frame = Bags.EnsureReagentWindow()
    if not frame then return end

    local cfg = Bags.GetConfig and Bags.GetConfig()
    local shouldShow = main:IsShown() and cfg and cfg.ReagentWindowShown == true and HasReagentBag()

    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMRIGHT", main, "BOTTOMLEFT", 0, 0)
    frame:SetFrameStrata(main:GetFrameStrata() or "MEDIUM")
    frame:SetFrameLevel((main:GetFrameLevel() or 1) + 2)

    if shouldShow then
        frame:Show()
        Bags.ApplyReagentLayoutConfig()
        Bags.ApplyReagentDelta(frame, Bags.PendingDelta, { forceReflow = next(reagentSectionFrameByKey) == nil })
    else
        frame:Hide()
    end

    Bags.UpdateReagentToggleArrow()
end

function Bags.SetReagentWindowShown(shown)
    local cfg = Bags.GetConfig and Bags.GetConfig()
    if not cfg then return end

    if shown and not HasReagentBag() then
        shown = false
    end

    cfg.ReagentWindowShown = shown and true or false
    Bags.UpdateReagentWindowState()
end

function Bags.ToggleReagentWindow()
    local cfg = Bags.GetConfig and Bags.GetConfig()
    if not cfg then return end

    Bags.SetReagentWindowShown(not cfg.ReagentWindowShown)
end

C_Timer.After(0, function()
    if Bags.UpdateReagentWindowState then
        Bags.UpdateReagentWindowState()
    end
end)

