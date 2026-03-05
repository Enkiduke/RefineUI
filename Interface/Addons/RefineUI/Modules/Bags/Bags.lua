----------------------------------------------------------------------------------------
-- Bags Component: Core
-- Description: Core bag frames, layout, and event handling.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Bags = RefineUI:GetModule("Bags")
if not Bags then return end

if RefineUI.Config.Bags and RefineUI.Config.Bags.Enable == false then
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
local tostring = tostring
local tonumber = tonumber
local pairs = pairs
local ipairs = ipairs
local unpack = unpack
local math = math
local table = table
local pcall = pcall
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------

local DEFAULT_BAG_WIDTH = 600
local DEFAULT_SLOT_SIZE = 37
local DEFAULT_ITEM_SPACING_X = 5
local DEFAULT_ITEM_SPACING_Y = 5
local PADDING = 8
local CONTENT_INSET = 5
local HEADER_HEIGHT = 18
local SUB_HEADER_HEIGHT = 16
local BOTTOM_HEIGHT = 30

local DEFAULT_COLUMNS = math.floor((DEFAULT_BAG_WIDTH - PADDING * 2 + DEFAULT_ITEM_SPACING_X) / (DEFAULT_SLOT_SIZE + DEFAULT_ITEM_SPACING_X))

Bags.BAG_WIDTH = DEFAULT_BAG_WIDTH
Bags.SLOT_SIZE = DEFAULT_SLOT_SIZE
Bags.ITEM_SPACING_X = DEFAULT_ITEM_SPACING_X
Bags.ITEM_SPACING_Y = DEFAULT_ITEM_SPACING_Y
Bags.PADDING = PADDING
Bags.CONTENT_INSET = CONTENT_INSET
Bags.CONTENT_INSET_LEFT = CONTENT_INSET
Bags.CONTENT_INSET_RIGHT = CONTENT_INSET
Bags.HEADER_HEIGHT = HEADER_HEIGHT
Bags.SUB_HEADER_HEIGHT = SUB_HEADER_HEIGHT
Bags.BOTTOM_HEIGHT = BOTTOM_HEIGHT
Bags.COLUMNS = DEFAULT_COLUMNS
Bags.searchText = Bags.searchText or ""
Bags.BagWindowFrameTemplate = _G.ButtonFrameTemplateNoPortrait and "ButtonFrameTemplateNoPortrait"
    or (_G.ButtonFrameTemplate and "ButtonFrameTemplate")
    or "PortraitFrameFlatTemplate"

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------

local function ClampNumber(value, defaultValue, minValue, maxValue)
    local num = tonumber(value) or defaultValue
    if minValue and num < minValue then num = minValue end
    if maxValue and num > maxValue then num = maxValue end
    return num
end

function Bags.ApplyFlatFrameNoPortraitCorner(frame)
    if not frame then return end

    if frame.NineSlice and NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
        if _G.ButtonFrameTemplateNoPortrait then
            local ok = pcall(NineSliceUtil.ApplyLayoutByName, frame.NineSlice, "ButtonFrameTemplateNoPortrait")
            if ok then
                if frame.PortraitContainer then
                    frame.PortraitContainer:Hide()
                end
                return
            end
        end
    end

    if _G.ButtonFrameTemplate_HidePortrait then
        local ok = pcall(_G.ButtonFrameTemplate_HidePortrait, frame)
        if ok then
            return
        end
    elseif frame.PortraitContainer then
        frame.PortraitContainer:Hide()
    end

    if not frame.NineSlice then return end

    local topLeft = frame.NineSlice.TopLeftCorner
    local topRight = frame.NineSlice.TopRightCorner
    if not topLeft or not topRight then return end

    local atlas = topRight.GetAtlas and topRight:GetAtlas()
    if atlas and topLeft.SetAtlas then
        topLeft:SetAtlas(atlas, true)
        if topLeft.SetTexCoord then
            topLeft:SetTexCoord(1, 0, 0, 1)
        end
    end
end

function Bags.SetFrameTitle(frame, titleText)
    if not frame then return end

    if frame.SetTitle then
        frame:SetTitle(titleText)
        return
    end

    if frame.TitleText then
        frame.TitleText:SetText(titleText)
        return
    end

    if frame.NineSlice and frame.NineSlice.Text then
        frame.NineSlice.Text:SetText(titleText)
    end
end

function Bags.ApplyHeaderFont(fontString, size)
    if not fontString then return end
    if RefineUI.Font then
        RefineUI.Font(fontString, size or 12)
    end
end

function Bags.ApplyLayoutConfig()
    local cfg = Bags.GetConfig and Bags.GetConfig() or RefineUI.Config.Bags or {}
    Bags.BAG_WIDTH = ClampNumber(cfg.WindowWidth, DEFAULT_BAG_WIDTH, 420, 1200)
    Bags.SLOT_SIZE = ClampNumber(cfg.SlotSize, DEFAULT_SLOT_SIZE, 24, 56)
    Bags.ITEM_SPACING_X = ClampNumber(cfg.ItemSpacingX, DEFAULT_ITEM_SPACING_X, 0, 20)
    Bags.ITEM_SPACING_Y = ClampNumber(cfg.ItemSpacingY, DEFAULT_ITEM_SPACING_Y, 0, 20)

    local contentPaddingLeft = (Bags.PADDING or PADDING) + (Bags.CONTENT_INSET_LEFT or CONTENT_INSET)
    local contentPaddingRight = (Bags.PADDING or PADDING) + (Bags.CONTENT_INSET_RIGHT or CONTENT_INSET)
    local columns = math.floor((Bags.BAG_WIDTH - contentPaddingLeft - contentPaddingRight + Bags.ITEM_SPACING_X) / (Bags.SLOT_SIZE + Bags.ITEM_SPACING_X))
    Bags.COLUMNS = math.max(1, columns)

    if Bags.Frame then
        Bags.Frame:SetWidth(Bags.BAG_WIDTH)
        if Bags.Frame.SearchBox then
            Bags.Frame.SearchBox:SetWidth(math.max(120, Bags.BAG_WIDTH - 150))
        end
    end

    if Bags.ApplyReagentLayoutConfig then
        Bags.ApplyReagentLayoutConfig()
    end

    Bags._layoutConfigRevision = (Bags._layoutConfigRevision or 0) + 1
end

----------------------------------------------------------------------------------------
-- Frame Pools
----------------------------------------------------------------------------------------

Bags.headerPool = Bags.headerPool or {}
Bags.subHeaderPool = Bags.subHeaderPool or {}
Bags.slotPool = Bags.slotPool or {}
Bags.activeHeaders = Bags.activeHeaders or {}
Bags.activeSubHeaders = Bags.activeSubHeaders or {}
Bags.activeSlots = Bags.activeSlots or {}

----------------------------------------------------------------------------------------
-- Main Frame
----------------------------------------------------------------------------------------

local Frame = CreateFrame("Frame", "RefineUI_Bags", UIParent, Bags.BagWindowFrameTemplate)
Bags.Frame = Frame
Bags.ApplyFlatFrameNoPortraitCorner(Frame)
Frame:SetSize(Bags.BAG_WIDTH or DEFAULT_BAG_WIDTH, 500)

do
    local cfg = Bags.GetConfig and Bags.GetConfig() or {}
    local pos = (type(cfg.Position) == "table" and cfg.Position)
        or (RefineUI.Positions and RefineUI.Positions["RefineUI_Bags"])
        or { "BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -50, 100 }
    local point, relativeTo, relativePoint, x, y = unpack(pos)
    local relFrame = (type(relativeTo) == "string" and _G[relativeTo]) or relativeTo or UIParent
    Frame:SetPoint(point, relFrame, relativePoint, x, y)
end

Frame:SetFrameStrata("MEDIUM")
Frame:SetToplevel(true)
Frame:SetClampedToScreen(true)
Frame:SetMovable(true)
Frame:EnableMouse(true)
Frame:RegisterForDrag("LeftButton")

Frame:SetScript("OnDragStart", function(self)
    if Bags._editModeActive then return end
    if InCombatLockdown() then return end

    if not self:IsMovable() then
        self:SetMovable(true)
    end
    if not self:IsMovable() then return end

    pcall(self.StartMoving, self)
end)

Frame:SetScript("OnDragStop", function(self)
    pcall(self.StopMovingOrSizing, self)
    local cfg = Bags.GetConfig and Bags.GetConfig()
    if not cfg then return end

    local point, _, relativePoint, x, y = self:GetPoint(1)
    if point and relativePoint then
        cfg.Position = cfg.Position or {}
        cfg.Position[1] = point
        cfg.Position[2] = "UIParent"
        cfg.Position[3] = relativePoint
        cfg.Position[4] = x or 0
        cfg.Position[5] = y or 0
    end
end)

Frame:SetScript("OnHide", function()
    C_NewItems.ClearAll()
    if C_Container and C_Container.SetItemSearch then
        C_Container.SetItemSearch("")
    end
    if Bags.ReagentFrame then
        Bags.ReagentFrame:Hide()
    end
    if Bags.UpdateReagentToggleArrow then
        Bags.UpdateReagentToggleArrow()
    end
end)

Frame:Hide()
Bags.SetFrameTitle(Frame, BAG_NAME_BACKPACK or "Backpack")

if Frame.PortraitContainer then
    Frame.PortraitContainer:Hide()
end

local bagIconParent = (Frame.NineSlice and Frame.NineSlice.CreateTexture) and Frame.NineSlice or Frame
local bagIcon = bagIconParent:CreateTexture(nil, "OVERLAY", nil, 7)
bagIcon:SetAtlas("bag-main", true)
bagIcon:SetScale(1.6)
bagIcon:SetPoint("TOPLEFT", Frame.NineSlice.TopLeftCorner, "TOPLEFT", 0, 0)
bagIcon:SetDrawLayer("OVERLAY", 7)
Frame.BagIcon = bagIcon

local itemContainer = CreateFrame("Frame", nil, Frame)
itemContainer:SetPoint("TOPLEFT", Frame, "TOPLEFT", PADDING + (Bags.CONTENT_INSET_LEFT or CONTENT_INSET), -60 - CONTENT_INSET)
itemContainer:SetPoint("BOTTOMRIGHT", Frame, "BOTTOMRIGHT", -(PADDING + (Bags.CONTENT_INSET_RIGHT or CONTENT_INSET)), BOTTOM_HEIGHT + PADDING + CONTENT_INSET)
Frame.ItemContainer = itemContainer

local searchBox = CreateFrame("EditBox", "RefineUI_BagsSearchBox", Frame, "BagSearchBoxTemplate")
searchBox:SetPoint("TOPLEFT", Frame, "TOPLEFT", 60, -32)
searchBox:SetSize(450, 20)
Frame.SearchBox = searchBox

----------------------------------------------------------------------------------------
-- Search logic
----------------------------------------------------------------------------------------

local function ApplySearchVisualToSlot(slot, slotState)
    if not slot or not slotState then return end

    local matches = true
    if Bags.ResolveSearchMatch then
        matches = Bags.ResolveSearchMatch(slotState.itemID, slotState.bagID, slotState.slotIndex)
    elseif Bags.MatchesSearch then
        matches = Bags.MatchesSearch(slotState.itemID)
    end
    slotState.searchMatch = matches and true or false

    local alpha = slotState.searchMatch and 1 or 0.3
    slot:SetAlpha(alpha)

    local icon = slot.icon or slot.Icon
    if icon then
        icon:SetAlpha(alpha)
    end

    if slot.border then
        slot.border:SetAlpha(alpha)
    end

    if slot.RefineUIBagBorderHost then
        slot.RefineUIBagBorderHost:SetAlpha(alpha)
    end

    local itemLevelText = slot.RefineUIBorderItemLevel
    if itemLevelText then
        itemLevelText:SetAlpha(alpha)
    end

    if ContainerFrameItemButton_UpdateSearchResults then
        pcall(ContainerFrameItemButton_UpdateSearchResults, slot)
    end
end

local function ApplySearchVisualToVisibleSlots()
    local slotStateByKey = Bags.SlotStateByKey
    if type(slotStateByKey) ~= "table" then return end

    local mainSlots = Bags.SlotFrameByKey
    if type(mainSlots) == "table" then
        for slotKey, slot in pairs(mainSlots) do
            ApplySearchVisualToSlot(slot, slotStateByKey[slotKey])
        end
    end

    local reagentSlots = Bags.ReagentSlotFrameByKey
    if type(reagentSlots) == "table" then
        for slotKey, slot in pairs(reagentSlots) do
            ApplySearchVisualToSlot(slot, slotStateByKey[slotKey])
        end
    end
end

searchBox:SetScript("OnTextChanged", function(self)
    if SearchBoxTemplate_OnTextChanged then
        SearchBoxTemplate_OnTextChanged(self)
    end

    local text = self:GetText()
    Bags.searchText = type(text) == "string" and text:lower() or ""

    if C_Container and C_Container.SetItemSearch then
        C_Container.SetItemSearch(Bags.searchText)
    end

    ApplySearchVisualToVisibleSlots()

    if Bags.RequestUpdate then
        Bags.RequestUpdate({ renderOnly = true })
    elseif Frame:IsShown() then
        Frame:UpdateLayout()
    end
end)

    if Bags.ApplyLayoutConfig then
        Bags.ApplyLayoutConfig()
    end

    if Bags.EnsureCategoryConfig then
        Bags.EnsureCategoryConfig()
    end

local moneyFrame = CreateFrame("Frame", "RefineUI_BagsMoneyFrame", Frame, "SmallMoneyFrameTemplate")
moneyFrame:SetPoint("BOTTOMRIGHT", Frame, "BOTTOMRIGHT", -8, 8)
SmallMoneyFrame_OnLoad(moneyFrame)
Frame.MoneyFrame = moneyFrame

local freeSlots = Frame:CreateFontString("RefineUI_BagsFreeSlots", "OVERLAY", "GameFontNormalSmall")
freeSlots:SetPoint("BOTTOMLEFT", Frame, "BOTTOMLEFT", 12, 12)
freeSlots:SetTextColor(0.8, 0.8, 0.8)
freeSlots:Hide()
Frame.FreeSlots = freeSlots

local function CreateBagStatusIcon(parent, name, atlas)
    local iconFrame = CreateFrame("Button", name, parent, "BackdropTemplate")
    iconFrame:SetSize(24, 24)
    iconFrame:EnableMouse(true)

    if RefineUI.SetTemplate then
        RefineUI.SetTemplate(iconFrame, "Transparent")
    else
        iconFrame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
    end

    iconFrame.Icon = iconFrame:CreateTexture(nil, "ARTWORK")
    iconFrame.Icon:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 0, 0)
    iconFrame.Icon:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", 0, 0)
    local atlasOK = pcall(iconFrame.Icon.SetAtlas, iconFrame.Icon, atlas, false)
    if not atlasOK then
        iconFrame.Icon:SetAtlas("bag-main", false)
    end

    iconFrame.Count = iconFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    iconFrame.Count:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
    iconFrame.Count:SetText("0")

    return iconFrame
end

local reagentBagStatus = CreateBagStatusIcon(Frame, "RefineUI_BagsReagentStatus", "bag-reagent")
reagentBagStatus:SetPoint("BOTTOMLEFT", Frame, "BOTTOMLEFT", 24, 8)
reagentBagStatus:RegisterForClicks("LeftButtonUp")

reagentBagStatus.ToggleArrow = reagentBagStatus:CreateTexture(nil, "OVERLAY")
reagentBagStatus.ToggleArrow:SetSize(12, 12)
reagentBagStatus.ToggleArrow:SetPoint("RIGHT", reagentBagStatus, "LEFT", 0, 0)
reagentBagStatus.ToggleArrow:SetAtlas("common-icon-forwardarrow", false)
reagentBagStatus.ToggleArrow:SetVertexColor(0.85, 0.85, 0.85, 1)

reagentBagStatus.Highlight = reagentBagStatus:CreateTexture(nil, "HIGHLIGHT")
reagentBagStatus.Highlight:SetAllPoints()
reagentBagStatus.Highlight:SetColorTexture(1, 1, 1, 0.12)

reagentBagStatus:SetScript("OnClick", function()
    if Bags.ToggleReagentWindow then
        Bags.ToggleReagentWindow()
    end
end)
Frame.ReagentBagStatus = reagentBagStatus

local normalBagStatus = CreateBagStatusIcon(Frame, "RefineUI_BagsNormalStatus", "bag-main")
normalBagStatus:SetPoint("LEFT", reagentBagStatus, "RIGHT", 8, 0)
normalBagStatus:EnableMouse(false)
Frame.NormalBagStatus = normalBagStatus

----------------------------------------------------------------------------------------
-- Header Lifecycle
----------------------------------------------------------------------------------------

local function AcquireHeader()
    local f = table.remove(Bags.headerPool)
    if f then
        f:Show()
        return f
    end

    f = CreateFrame("Frame", nil, Frame.ItemContainer)
    f:SetHeight(Bags.HEADER_HEIGHT)

    f.Text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.Text:SetPoint("LEFT", 2, 0)
    Bags.ApplyHeaderFont(f.Text, 12)

    f.Line = f:CreateTexture(nil, "ARTWORK")
    f.Line:SetHeight(1)
    f.Line:SetPoint("LEFT", f.Text, "RIGHT", 8, 0)
    f.Line:SetPoint("RIGHT", f, "RIGHT", -2, 0)

    return f
end

local function ReleaseHeader(f)
    if not f then return end
    f:Hide()
    f:ClearAllPoints()
    f.Text:SetText("")
    table.insert(Bags.headerPool, f)
end

local function AcquireSubHeader()
    local f = table.remove(Bags.subHeaderPool)
    if f then
        f:Show()
        return f
    end

    f = CreateFrame("Frame", nil, Frame.ItemContainer)
    f:SetHeight(Bags.SUB_HEADER_HEIGHT)

    f.Text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.Text:SetPoint("LEFT", 0, 0)
    Bags.ApplyHeaderFont(f.Text, 11)
    f.Text:SetTextColor(0.7, 0.7, 0.7)

    f.Line = f:CreateTexture(nil, "ARTWORK")
    f.Line:SetHeight(1)
    f.Line:SetPoint("LEFT", f.Text, "RIGHT", 4, 0)
    f.Line:SetPoint("RIGHT", f, "RIGHT", -2, 0)
    f.Line:SetColorTexture(0.7, 0.7, 0.7, 0.3)

    return f
end

local function ReleaseSubHeader(f)
    if not f then return end
    f:Hide()
    f:ClearAllPoints()
    f.Text:SetText("")
    table.insert(Bags.subHeaderPool, f)
end

Bags.AcquireHeader = AcquireHeader
Bags.ReleaseHeader = ReleaseHeader
Bags.AcquireSubHeader = AcquireSubHeader
Bags.ReleaseSubHeader = ReleaseSubHeader

----------------------------------------------------------------------------------------
-- Item Slot Functions
----------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------
-- Slot Lifecycle
----------------------------------------------------------------------------------------

local slotCount = 0
local hoveredCustomSlot = nil
local wasRightMouseDown = false
local pendingLayoutAfterCombat = false

local slotDisplayCategoryByFrame = Bags.slotDisplayCategoryByFrame
if type(slotDisplayCategoryByFrame) ~= "table" then
    slotDisplayCategoryByFrame = setmetatable({}, { __mode = "k" })
    Bags.slotDisplayCategoryByFrame = slotDisplayCategoryByFrame
end

local slotClearOverlayByFrame = Bags.slotClearOverlayByFrame
if type(slotClearOverlayByFrame) ~= "table" then
    slotClearOverlayByFrame = setmetatable({}, { __mode = "k" })
    Bags.slotClearOverlayByFrame = slotClearOverlayByFrame
end

local slotBorderHostByFrame = Bags.slotBorderHostByFrame
if type(slotBorderHostByFrame) ~= "table" then
    slotBorderHostByFrame = setmetatable({}, { __mode = "k" })
    Bags.slotBorderHostByFrame = slotBorderHostByFrame
end

local refineSlotLookup = Bags.refineSlotLookup
if type(refineSlotLookup) ~= "table" then
    refineSlotLookup = setmetatable({}, { __mode = "k" })
    Bags.refineSlotLookup = refineSlotLookup
end

local function SetSlotDisplayCategory(slot, categoryKey)
    if not slot then return end
    slotDisplayCategoryByFrame[slot] = categoryKey
end

local function GetSlotDisplayCategory(slot)
    if not slot then return nil end
    return slotDisplayCategoryByFrame[slot]
end

Bags.SetSlotDisplayCategory = SetSlotDisplayCategory

function Bags.MarkLayoutDirtyAfterCombat()
    pendingLayoutAfterCombat = true
end

local function GetDefaultBorderColor()
    local color = RefineUI.Config and RefineUI.Config.General and RefineUI.Config.General.BorderColor
    if type(color) == "table" then
        return color[1] or 0.3, color[2] or 0.3, color[3] or 0.3, color[4] or 1
    end
    return 0.3, 0.3, 0.3, 1
end

function Bags.EnsureBagSlotBorderHost(slot)
    if not slot or not RefineUI.CreateBorder then return nil end

    local host = slotBorderHostByFrame[slot]
    if host then
        slot.RefineUIBagBorderHost = host
        return host
    end

    if InCombatLockdown() then return nil end

    host = CreateFrame("Frame", nil, slot)
    host:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, 0)
    host:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 0, 0)
    if host.EnableMouse then
        host:EnableMouse(false)
    end

    slotBorderHostByFrame[slot] = host
    slot.RefineUIBagBorderHost = host
    RefineUI.CreateBorder(host, 5, 5, 12)

    return host
end

function Bags.ApplyBagSlotBorder(slot, itemInfo)
    if not slot or not RefineUI.CreateBorder then return end

    local host = Bags.EnsureBagSlotBorderHost and Bags.EnsureBagSlotBorderHost(slot)
    if not host then
        if Bags.MarkLayoutDirtyAfterCombat then
            Bags.MarkLayoutDirtyAfterCombat()
        end
        return
    end

    host:SetFrameStrata(slot:GetFrameStrata() or "MEDIUM")
    host:SetFrameLevel((slot:GetFrameLevel() or 1) + 2)

    local border = RefineUI.CreateBorder(host, 5, 5, 12)
    if not border then return end

    local quality = itemInfo and itemInfo.quality
    if quality ~= nil then
        local qualityColor = RefineUI.Colors and RefineUI.Colors.Quality and RefineUI.Colors.Quality[quality]
        local r, g, b
        if qualityColor then
            r, g, b = qualityColor.r, qualityColor.g, qualityColor.b
        else
            r, g, b = GetItemQualityColor(quality)
        end
        border:SetBackdropBorderColor(r or 1, g or 1, b or 1, 1)
    else
        local r, g, b, a = GetDefaultBorderColor()
        border:SetBackdropBorderColor(r, g, b, a)
    end

    host:Show()
end

local function SlotCanClearCustomCategory(slot)
    local displayCategoryKey = GetSlotDisplayCategory(slot)
    if not slot or not displayCategoryKey or not Bags.IsCustomCategoryKey then
        return false
    end
    if not Bags.IsCustomCategoryKey(displayCategoryKey) then
        return false
    end

    local bagID = slot:GetBagID()
    local slotIndex = slot:GetID()
    if not bagID or not slotIndex or not C_Container or not C_Container.GetContainerItemID then
        return false
    end

    local itemID = C_Container.GetContainerItemID(bagID, slotIndex)
    if not itemID then return false end

    local assignedKey = Bags.GetAssignedCustomCategoryForItem and Bags.GetAssignedCustomCategoryForItem(itemID)
    return assignedKey ~= nil and assignedKey == displayCategoryKey
end

local function UpdateCustomCategoryClearCursor(slot, forceHide)
    if not slot then return end

    local overlay = slotClearOverlayByFrame[slot]
    if not overlay then
        if InCombatLockdown() then return end
        overlay = slot:CreateTexture(nil, "OVERLAY", nil, 7)
        overlay:SetSize(14, 14)
        overlay:SetPoint("CENTER", slot, "CENTER", 0, 0)
        local ok = pcall(overlay.SetAtlas, overlay, "common-icon-redx", true)
        if not ok then
            overlay:SetColorTexture(1, 0.1, 0.1, 0.35)
        end
        overlay:Hide()
        slotClearOverlayByFrame[slot] = overlay
    end

    if not forceHide and slot:IsMouseOver() and IsControlKeyDown() and SlotCanClearCustomCategory(slot) then
        overlay:Show()
        return
    end

    if overlay:IsShown() then
        overlay:Hide()
    end
end

local function ClearCustomCategoryFromSlot(slot)
    if not slot then return false end

    local displayCategoryKey = GetSlotDisplayCategory(slot)
    if not (displayCategoryKey and Bags.IsCustomCategoryKey and Bags.IsCustomCategoryKey(displayCategoryKey)) then
        return false
    end

    local bagID = slot:GetBagID()
    local slotIndex = slot:GetID()
    if not bagID or not slotIndex then
        return false
    end

    local itemID = C_Container and C_Container.GetContainerItemID and C_Container.GetContainerItemID(bagID, slotIndex)
    if not itemID then return false end

    local assignedKey = Bags.GetAssignedCustomCategoryForItem and Bags.GetAssignedCustomCategoryForItem(itemID)
    if assignedKey ~= displayCategoryKey then
        return false
    end

    if Bags.ClearItemCustomCategory and Bags.ClearItemCustomCategory(itemID) then
        UpdateCustomCategoryClearCursor(slot, true)
        if Bags.RequestUpdate then
            Bags.RequestUpdate()
        end
        return true
    end

    return false
end

local function AcquireSlot()
    local slot = table.remove(Bags.slotPool)
    if slot then
        slot:SetSize(Bags.SLOT_SIZE, Bags.SLOT_SIZE)
        if Bags.EnsureBagSlotBorderHost then
            Bags.EnsureBagSlotBorderHost(slot)
        end
        slot:Show()
        return slot
    end

    if InCombatLockdown() then
        pendingLayoutAfterCombat = true
        return nil
    end

    slotCount = slotCount + 1
    local name = "RefineUI_BagSlot" .. slotCount
    slot = CreateFrame("ItemButton", name, Frame.ItemContainer, "ContainerFrameItemButtonTemplate")
    slot:SetSize(Bags.SLOT_SIZE, Bags.SLOT_SIZE)
    refineSlotLookup[slot] = true

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

    if slot.BattlepayItemTexture then
        slot.BattlepayItemTexture:SetAlpha(0)
    end

    if slot.NewItemTexture then
        slot.NewItemTexture:SetAlpha(0)
    end

    if slot.BagIndicator then
        slot.BagIndicator:Hide()
    end

    if Bags.EnsureBagSlotBorderHost then
        Bags.EnsureBagSlotBorderHost(slot)
    end

    return slot
end

local function ReleaseSlot(slot)
    if not slot then return end
    slot:Hide()
    slot:ClearAllPoints()
    SetSlotDisplayCategory(slot, nil)
    slot:EnableMouse(true)
    if hoveredCustomSlot == slot then
        hoveredCustomSlot = nil
    end
    local overlay = slotClearOverlayByFrame[slot]
    if overlay and overlay:IsShown() then
        overlay:Hide()
    end
    local borderHost = slotBorderHostByFrame[slot]
    if borderHost and borderHost:IsShown() then
        borderHost:Hide()
    end

    SetItemButtonTexture(slot, 0)
    SetItemButtonCount(slot, 0)
    SetItemButtonQuality(slot, nil)

    if slot.IconBorder then
        slot.IconBorder:Hide()
    end
    if slot.ItemSlotBackground then
        slot.ItemSlotBackground:Show()
    end

    table.insert(Bags.slotPool, slot)
end

Bags.AcquireSlot = AcquireSlot
Bags.ReleaseSlot = ReleaseSlot

local function GetDesiredSlotPoolSize()
    local total = 0
    if C_Container and C_Container.GetContainerNumSlots then
        for bagID = 0, NUM_BAG_SLOTS do
            total = total + (C_Container.GetContainerNumSlots(bagID) or 0)
        end
    end

    if total < 176 then
        total = 176
    end
    return total + 16
end

function Bags.WarmSlotPool(desiredCount)
    if InCombatLockdown() then
        pendingLayoutAfterCombat = true
        return
    end

    desiredCount = desiredCount or GetDesiredSlotPoolSize()
    local guard = desiredCount + 96
    local warmedSlots = {}

    while #Bags.slotPool < desiredCount and guard > 0 do
        local slot = AcquireSlot()
        if not slot then break end
        table.insert(warmedSlots, slot)
        guard = guard - 1
    end

    for i = 1, #warmedSlots do
        ReleaseSlot(warmedSlots[i])
    end
end

function Frame:UpdateLayout(force)
    if Bags.UpdateLayout then
        Bags.UpdateLayout(self, force)
    end
    if Bags.UpdateReagentWindowState then
        Bags.UpdateReagentWindowState()
    end
end

----------------------------------------------------------------------------------------
-- Debounced Updates
----------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------
-- Debounced Updates
----------------------------------------------------------------------------------------

local BAG_REFRESH_DEBOUNCE_KEY = "Bags:SnapshotRefresh"
local BAG_TOGGLE_COMMAND = "REFINEUI_TOGGLEBAGS"
local BAG_OVERRIDE_BINDINGS = {
    "TOGGLEBACKPACK",
    "TOGGLEREAGENTBAG",
    "TOGGLEBAG1",
    "TOGGLEBAG2",
    "TOGGLEBAG3",
    "TOGGLEBAG4",
    "OPENALLBAGS",
}

local updateQueued = false
local bagHooksInstalled = false
local bagSyncQueued = false
local pendingBagSyncMode = nil
local blizzardBagRedirectFrame = nil
local blizzardBagFramesRedirected = false
local bagBindingFrame = CreateFrame("Frame", "RefineUI_BagsBindingRouter")
local bagBindingRefreshPending = false
local OpenBags
local RequestUpdate
local pendingRefreshOptions = {}

local function ResolveBagSyncMode(requestedMode)
    if Bags._editModeActive then return "open" end
    if requestedMode == "open" or requestedMode == "close" then
        return requestedMode
    end
    return Frame:IsShown() and "close" or "open"
end

local function ToggleBags()
    if Bags._editModeActive then
        OpenBags()
        return
    end

    if Frame:IsShown() then
        Frame:Hide()
    else
        OpenBags()
    end
end

OpenBags = function()
    if not Frame:IsShown() then
        Frame:Show()
    end

    local inCombat = InCombatLockdown()

    if Bags._snapshot and Bags.RenderBagSnapshot then
        Bags.RenderBagSnapshot(Frame, Bags._snapshot, {
            force = inCombat and true or false,
        })

        if Bags.UpdateReagentWindowState then
            Bags.UpdateReagentWindowState()
        end

        if Bags._snapshotDirty or Bags._pendingSnapshotRefresh then
            if inCombat then
                Frame:UpdateLayout(true)
            elseif RequestUpdate then
                RequestUpdate()
            else
                Frame:UpdateLayout()
            end
        end
    else
        Frame:UpdateLayout(inCombat and true or false)
    end
end

local function CloseBags()
    if Bags._editModeActive then return end
    if Frame:IsShown() then
        Frame:Hide()
    end
end

Bags.ToggleBags = ToggleBags
Bags.OpenBags = OpenBags
Bags.CloseBags = CloseBags

_G.BINDING_NAME_REFINEUI_TOGGLEBAGS = _G.BINDING_NAME_REFINEUI_TOGGLEBAGS or "Toggle Bags"
_G.RefineUI_ToggleBags = function()
    ToggleBags()
end

----------------------------------------------------------------------------------------
-- Blizzard Integration
----------------------------------------------------------------------------------------

local function EnsureBlizzardBagFramesRedirected()
    if blizzardBagFramesRedirected then return end

    if not blizzardBagRedirectFrame then
        blizzardBagRedirectFrame = CreateFrame("Frame", "RefineUI_BagsSneakyFrame", UIParent)
        blizzardBagRedirectFrame:Hide()
    end

    local hasTargets = false
    if ContainerFrameCombinedBags then
        hasTargets = true
        if ContainerFrameCombinedBags:GetParent() ~= blizzardBagRedirectFrame then
            ContainerFrameCombinedBags:SetParent(blizzardBagRedirectFrame)
        end
    end

    local maxFrames = NUM_TOTAL_BAG_FRAMES or 13
    for i = 1, maxFrames do
        local frame = _G["ContainerFrame" .. i]
        if frame then
            hasTargets = true
            if frame:GetParent() ~= blizzardBagRedirectFrame then
                frame:SetParent(blizzardBagRedirectFrame)
            end
        end
    end

    if hasTargets then
        blizzardBagFramesRedirected = true
    end
end

local function HideBlizzardBags()
    EnsureBlizzardBagFramesRedirected()

    if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
        ContainerFrameCombinedBags:Hide()
    end

    local maxFrames = NUM_TOTAL_BAG_FRAMES or 13
    for i = 1, maxFrames do
        local frame = _G["ContainerFrame" .. i]
        if frame and frame:IsShown() then
            frame:Hide()
        end
    end
end

local function ApplyBagBindingOverrides()
    if not (GetBindingKey and SetOverrideBinding and ClearOverrideBindings) then
        return false
    end
    if InCombatLockdown() then
        bagBindingRefreshPending = true
        return false
    end

    bagBindingRefreshPending = false
    ClearOverrideBindings(bagBindingFrame)

    for _, binding in ipairs(BAG_OVERRIDE_BINDINGS) do
        local key1, key2 = GetBindingKey(binding)
        if key1 then
            SetOverrideBinding(bagBindingFrame, true, key1, BAG_TOGGLE_COMMAND)
        end
        if key2 then
            SetOverrideBinding(bagBindingFrame, true, key2, BAG_TOGGLE_COMMAND)
        end
    end

    return true
end

local function QueueBagSync(mode)
    if mode == "open" or mode == "close" then
        pendingBagSyncMode = mode
    elseif not pendingBagSyncMode then
        pendingBagSyncMode = "toggle"
    end

    if bagSyncQueued then return end
    bagSyncQueued = true

    local function applyMode()
        bagSyncQueued = false
        local requestedMode = pendingBagSyncMode
        pendingBagSyncMode = nil
        local resolvedMode = ResolveBagSyncMode(requestedMode)

        HideBlizzardBags()
        if resolvedMode == "open" then
            OpenBags()
        else
            CloseBags()
        end
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0, applyMode)
    else
        applyMode()
    end
end

local function InstallBlizzardBagHooks()
    if bagHooksInstalled then return end
    bagHooksInstalled = true

    local function InstallHook(key, fnName, mode)
        if _G[fnName] then
            RefineUI:HookOnce(key, fnName, function()
                QueueBagSync(mode)
            end)
        end
    end

    InstallHook("Bags:ToggleBackpack", "ToggleBackpack", "toggle")
    InstallHook("Bags:OpenBackpack", "OpenBackpack", "open")
    InstallHook("Bags:CloseBackpack", "CloseBackpack", "close")

    InstallHook("Bags:ToggleAllBags", "ToggleAllBags", "toggle")
    InstallHook("Bags:OpenAllBags", "OpenAllBags", "open")
    InstallHook("Bags:CloseAllBags", "CloseAllBags", "close")

    InstallHook("Bags:ToggleBag", "ToggleBag", "toggle")
    InstallHook("Bags:OpenBag", "OpenBag", "open")
    InstallHook("Bags:CloseBag", "CloseBag", "close")
end

local function FlushQueuedBagRefresh()
    if RefineUI.CancelDebounce then
        RefineUI:CancelDebounce(BAG_REFRESH_DEBOUNCE_KEY)
    end

    local refreshOpts = pendingRefreshOptions
    pendingRefreshOptions = {}
    if type(refreshOpts) ~= "table" then
        refreshOpts = {}
    end

    Bags._pendingSnapshotRefresh = false

    if Bags.RefreshSnapshot then
        refreshOpts.render = Frame:IsShown()
        refreshOpts.build = true
        Bags.RefreshSnapshot(refreshOpts)
        if Bags.UpdateReagentWindowState then
            Bags.UpdateReagentWindowState()
        end
    elseif Frame:IsShown() then
        Frame:UpdateLayout()
    end
end

local function MergeRefreshOptions(opts)
    if type(opts) ~= "table" then return end
    if opts.renderOnly then pendingRefreshOptions.renderOnly = true end
    if opts.lockOnly then pendingRefreshOptions.lockOnly = true end
    if opts.equipmentSetsChanged then pendingRefreshOptions.equipmentSetsChanged = true end
    if opts.forceReflow then pendingRefreshOptions.forceReflow = true end
    if opts.cursorOnly then pendingRefreshOptions.cursorOnly = true end
    if type(opts.bagID) == "number" then
        pendingRefreshOptions.bagID = opts.bagID
    end
end

RequestUpdate = function(opts)
    if type(opts) ~= "table" then opts = {} end
    MergeRefreshOptions(opts)

    if not opts.renderOnly then
        if Bags.MarkBagSnapshotDirty then
            Bags.MarkBagSnapshotDirty()
        else
            Bags._snapshotDirty = true
        end
    end

    Bags._pendingSnapshotRefresh = true

    if RefineUI.Debounce then
        RefineUI:Debounce(BAG_REFRESH_DEBOUNCE_KEY, 0.05, FlushQueuedBagRefresh)
        return
    end

    if updateQueued then return end
    updateQueued = true
    C_Timer.After(0.05, function()
        updateQueued = false
        FlushQueuedBagRefresh()
    end)
end

Bags.RequestUpdate = RequestUpdate
Bags.RequestRenderUpdate = function()
    RequestUpdate({ renderOnly = true })
end

----------------------------------------------------------------------------------------
-- Event Handling
----------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------

local function WarmBagSlotPools()
    if Bags.WarmSlotPool then
        Bags.WarmSlotPool()
    end
    if Bags.EnsureReagentWindow and Bags.WarmReagentSlotPool then
        local reagentFrame = Bags.EnsureReagentWindow()
        Bags.WarmReagentSlotPool(reagentFrame)
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("UPDATE_BINDINGS")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("BAG_CONTAINER_UPDATE")
eventFrame:RegisterEvent("ITEM_LOCK_CHANGED")
eventFrame:RegisterEvent("ITEM_UNLOCKED")
eventFrame:RegisterEvent("PLAYER_MONEY")
eventFrame:RegisterEvent("EQUIPMENT_SETS_CHANGED")
eventFrame:RegisterEvent("QUEST_ACCEPTED")
eventFrame:RegisterEvent("QUEST_REMOVED")
eventFrame:RegisterEvent("QUEST_TURNED_IN")
eventFrame:RegisterEvent("QUEST_LOG_UPDATE")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        EnsureBlizzardBagFramesRedirected()
        HideBlizzardBags()
        InstallBlizzardBagHooks()
        ApplyBagBindingOverrides()
        RequestUpdate()
        C_Timer.After(0, WarmBagSlotPools)
    elseif event == "PLAYER_REGEN_ENABLED" then
        WarmBagSlotPools()
        if bagBindingRefreshPending then
            ApplyBagBindingOverrides()
        end
        if Bags._pendingSnapshotRefresh then
            FlushQueuedBagRefresh()
        end
        if pendingLayoutAfterCombat then
            pendingLayoutAfterCombat = false
            if Frame:IsShown() then
                Frame:UpdateLayout(true)
            elseif Bags.ReagentFrame and Bags.ReagentFrame:IsShown() and Bags.UpdateReagentLayout then
                Bags.UpdateReagentLayout(Bags.ReagentFrame)
            end
        end
    elseif event == "UPDATE_BINDINGS" then
        ApplyBagBindingOverrides()
    elseif event == "PLAYER_MONEY" then
        if Frame:IsShown() and Frame.MoneyFrame then
            MoneyFrame_Update(Frame.MoneyFrame:GetName(), GetMoney())
        end
    elseif event == "EQUIPMENT_SETS_CHANGED" then
        RequestUpdate({ equipmentSetsChanged = true })
    elseif event == "BAG_UPDATE_DELAYED" then
        if not InCombatLockdown() then
            WarmBagSlotPools()
        end
        RequestUpdate()
    elseif event == "BAG_CONTAINER_UPDATE" then
        local bagID = ...
        RequestUpdate({ bagID = bagID })
    elseif event == "ITEM_LOCK_CHANGED" or event == "ITEM_UNLOCKED" then
        RequestUpdate({ renderOnly = true, lockOnly = true })
    else
        RequestUpdate()
    end
end)

----------------------------------------------------------------------------------------
-- Interaction
----------------------------------------------------------------------------------------

do
    local elapsedAccumulator = 0
    local hadCursorItem = false

    local function FindRefineSlotInFocusChain(focus)
        while focus do
            if refineSlotLookup[focus] then
                return focus
            end
            focus = focus:GetParent()
        end
        return nil
    end

    local function GetHoveredSlotFromMouseFocus()
        if type(GetMouseFocus) == "function" then
            return FindRefineSlotInFocusChain(GetMouseFocus())
        end

        if type(GetMouseFoci) == "function" then
            local foci = GetMouseFoci()
            if type(foci) == "table" then
                for i = 1, #foci do
                    local slot = FindRefineSlotInFocusChain(foci[i])
                    if slot then
                        return slot
                    end
                end
            end
        end

        return nil
    end

    Frame:HookScript("OnUpdate", function(_, elapsed)
        elapsedAccumulator = elapsedAccumulator + (elapsed or 0)
        if elapsedAccumulator < 0.05 then return end
        elapsedAccumulator = 0

        local cursorType = GetCursorInfo()
        if cursorType ~= "item" and not IsMouseButtonDown("LeftButton") then
            Bags._draggingBagItemActive = false
            Bags._draggingBagItemID = nil
        end

        local hasCursorItem = (cursorType == "item")
            or (Bags._draggingBagItemActive and type(Bags._draggingBagItemID) == "number" and Bags._draggingBagItemID > 0)

        if hasCursorItem ~= hadCursorItem then
            hadCursorItem = hasCursorItem
            if not hasCursorItem then
                Bags._draggingBagItemActive = false
                Bags._draggingBagItemID = nil
            end
            RequestUpdate({ renderOnly = true, forceReflow = true, cursorOnly = true })
        end

        local hoveredNow = GetHoveredSlotFromMouseFocus()
        if hoveredNow ~= hoveredCustomSlot and hoveredCustomSlot then
            UpdateCustomCategoryClearCursor(hoveredCustomSlot, true)
        end
        hoveredCustomSlot = hoveredNow

        if hoveredCustomSlot and hoveredCustomSlot:IsShown() then
            UpdateCustomCategoryClearCursor(hoveredCustomSlot)
        end

        local rightDown = IsMouseButtonDown("RightButton")
        if rightDown and not wasRightMouseDown and IsControlKeyDown() and hoveredCustomSlot and hoveredCustomSlot:IsShown() then
            ClearCustomCategoryFromSlot(hoveredCustomSlot)
            UpdateCustomCategoryClearCursor(hoveredCustomSlot)
        end
        wasRightMouseDown = rightDown
    end)
end

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------

table.insert(UISpecialFrames, "RefineUI_Bags")

SLASH_REFINEUIBAGS1 = "/bags"
SlashCmdList["REFINEUIBAGS"] = function()
    ToggleBags()
end

