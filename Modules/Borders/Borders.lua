----------------------------------------------------------------------------------------
-- RefineUI Borders Module
-- Description: Shared quality border helpers and source registration for item UI.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Borders = RefineUI:RegisterModule("Borders")

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config
local Colors = RefineUI.Colors
local Media = RefineUI.Media
local Font = RefineUI.Font

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local type = type
local pairs = pairs
local tostring = tostring
local pcall = pcall
local floor = math.floor
local find = string.find
local unpack = unpack
local GetItemInfo = GetItemInfo
local GetItemQualityColor = GetItemQualityColor
local GetDetailedItemLevelInfo = GetDetailedItemLevelInfo
local C_Item = C_Item
local C_TransmogCollection = C_TransmogCollection
local C_PetJournal = C_PetJournal
local C_MountJournal = C_MountJournal
local C_ToyBox = C_ToyBox
local PlayerHasToy = PlayerHasToy

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local CHAR_SLOTS = {
    "Head", "Neck", "Shoulder", "Shirt", "Chest", "Waist", "Legs", "Feet", "Wrist", "Hands",
    "Finger0", "Finger1", "Trinket0", "Trinket1", "Back", "MainHand", "SecondaryHand", "Tabard",
}

local DEFAULT_BORDER_INSET = 5
local ILVL_FONT_SIZE = 12
local ILVL_TEXT_SUBLEVEL = 7
local BAG_STATUS_ICON_SIZE = 32
local BAG_STATUS_ICON_SUBLEVEL = 7
local BAG_STATUS_ICON_OFFSET_X = 4
local BAG_STATUS_ICON_OFFSET_Y = -8
local BAG_STATUS_ICON_ATLAS_UNKNOWN = "UI-QuestTracker-Objective-Fail"
local BAG_UNKNOWN_ICON_SIZE = 16
local BAG_UNKNOWN_ICON_INSET_X = 2
local BAG_UNKNOWN_ICON_INSET_Y = 2
local SQUISH_CURVE_ID = 92181
local SQUISH_THRESHOLD = 250
local FRAME_BORDER_CACHE = setmetatable({}, { __mode = "k" })
local ITEM_LEVEL_CACHE = {}

Borders.CharSlots = CHAR_SLOTS

----------------------------------------------------------------------------------------
-- State / Registries
----------------------------------------------------------------------------------------
local pipes = {}
local pipeOrder = {}

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function GetDefaultBorderColor()
    local r, g, b, a = 0.3, 0.3, 0.3, 1
    if Config and Config.General and Config.General.BorderColor then
        r, g, b, a = unpack(Config.General.BorderColor)
    end
    return r, g, b, a
end

function Borders:GetDefaultBorderColor()
    return GetDefaultBorderColor()
end

function Borders:GetQualityColor(quality)
    if type(quality) ~= "number" then
        return nil
    end

    quality = floor(quality + 0.5)
    if quality < 0 then
        quality = 0
    end

    local qualityColors = Colors and Colors.Quality
    local color = qualityColors and qualityColors[quality]
    if color then
        return color.r, color.g, color.b, color.a or 1
    end

    local r, g, b = GetItemQualityColor(quality)
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then
        return r, g, b, 1
    end

    return nil
end

local function GetPostSquishItemLevel(preSquishItemLevel)
    if not preSquishItemLevel then return 0 end
    if C_CurveUtil and C_CurveUtil.EvaluateGameCurve then
        local squished = C_CurveUtil.EvaluateGameCurve(SQUISH_CURVE_ID, preSquishItemLevel)
        if squished and squished > 0 then
            return floor(squished)
        end
    end
    return preSquishItemLevel
end

local function ResolveCollectibleKnownState(itemLink, itemID)
    if itemID and C_MountJournal and C_MountJournal.GetMountFromItem and C_MountJournal.GetMountInfoByID then
        local mountID = C_MountJournal.GetMountFromItem(itemID)
        if mountID then
            local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
            return true, isCollected == true
        end
    end

    if itemID and C_PetJournal and C_PetJournal.GetPetInfoByItemID and C_PetJournal.GetNumCollectedInfo then
        local _, _, _, _, _, _, _, _, _, _, _, _, speciesID = C_PetJournal.GetPetInfoByItemID(itemID)
        if type(speciesID) == "number" then
            local owned = C_PetJournal.GetNumCollectedInfo(speciesID)
            return true, (owned or 0) > 0
        end
    end

    if itemID and C_ToyBox and C_ToyBox.GetToyInfo and C_ToyBox.PlayerHasToy then
        local toyName = C_ToyBox.GetToyInfo(itemID)
        if toyName then
            return true, C_ToyBox.PlayerHasToy(itemID) == true
        end
    end

    if itemID and C_ToyBox and C_ToyBox.GetToyLink then
        local toyLink = C_ToyBox.GetToyLink(itemID)
        if toyLink then
            if C_ToyBox.PlayerHasToy then
                return true, C_ToyBox.PlayerHasToy(itemID) == true
            end
            if PlayerHasToy then
                return true, PlayerHasToy(itemID) == true
            end
        end
    end

    if itemID and PlayerHasToy then
        if C_ToyBox and C_ToyBox.GetToyInfo and C_ToyBox.GetToyInfo(itemID) then
            return true, PlayerHasToy(itemID) == true
        end
    end

    if itemID and C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
    end

    if itemLink and C_TransmogCollection and C_TransmogCollection.GetItemInfo and C_TransmogCollection.GetSourceInfo then
        local sourceID = select(2, C_TransmogCollection.GetItemInfo(itemLink))
        if sourceID then
            local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
            if sourceInfo then
                return true, sourceInfo.isCollected == true
            end
        end
    end

    return false, nil
end

function Borders:ResolveCollectibleKnownState(itemLink, itemID)
    return ResolveCollectibleKnownState(itemLink, itemID)
end

local function CreateItemLevelText(frame)
    local text = frame.RefineUIBorderItemLevel
    if not text then
        text = frame:CreateFontString(nil, "OVERLAY")
        if Font then
            Font(text, ILVL_FONT_SIZE, nil, "OUTLINE")
        else
            local font = (Media and Media.Fonts and Media.Fonts.Default) or STANDARD_TEXT_FONT
            text:SetFont(font, ILVL_FONT_SIZE, "OUTLINE")
        end
        text:SetDrawLayer("OVERLAY", ILVL_TEXT_SUBLEVEL)
        text:SetPoint("TOPRIGHT", 1, -1)
        text:SetJustifyH("RIGHT")
    end

    frame.RefineUIBorderItemLevel = text
    return text
end

local function GetItemLevelTextParent(frame)
    if not frame then
        return nil
    end

    local bagHost = frame.RefineUIBagBorderHost
    if bagHost and bagHost.border then
        return bagHost.border
    end

    if frame.border then
        return frame.border
    end

    return frame
end

local function GetBagStatusAnchor(frame)
    if not frame then
        return nil
    end

    if frame.icon then
        return frame.icon
    end
    if frame.Icon then
        return frame.Icon
    end
    if frame.IconTexture then
        return frame.IconTexture
    end

    local frameName = frame.GetName and frame:GetName()
    if frameName then
        local namedIcon = _G[frameName .. "IconTexture"]
        if namedIcon then
            return namedIcon
        end
    end

    return frame
end

local function GetBagStatusParent(frame)
    local bagHost = frame and frame.RefineUIBagBorderHost
    if bagHost and bagHost.border then
        return bagHost.border
    end
    if frame and frame.border then
        return frame.border
    end
    return frame
end

local function CreateBagStatusIcon(frame)
    local icon = frame.RefineUIBorderStatusIcon
    if not icon then
        icon = GetBagStatusParent(frame):CreateTexture(nil, "OVERLAY", nil, 7)
        icon:Hide()
    end
    frame.RefineUIBorderStatusIcon = icon
    return icon
end

local function IsRefineBagSlot(frame)
    if not frame then return false end

    local frameName = frame.GetName and frame:GetName()
    if frameName and (find(frameName, "^RefineUI_BagSlot") or find(frameName, "^RefineUI_ReagentSlot")) then
        return true
    end

    local parent = frame.GetParent and frame:GetParent()
    while parent do
        local parentName = parent.GetName and parent:GetName()
        if parentName == "RefineUI_Bags" or parentName == "RefineUI_ReagentBag" then
            return true
        end
        parent = parent.GetParent and parent:GetParent() or nil
    end

    return false
end

local function ResolveBagStatusAtlas(frame)
    if not IsRefineBagSlot(frame) then
        return nil
    end
    if not (frame.GetBagID and frame.GetID and C_Container and C_Container.GetContainerItemInfo) then
        return nil
    end

    local bagID = frame:GetBagID()
    local slotID = frame:GetID()
    if not bagID or not slotID then
        return nil
    end

    local info = C_Container.GetContainerItemInfo(bagID, slotID)
    if not info or not info.itemID then
        return nil
    end

    if C_Container.GetContainerItemQuestInfo then
        local questInfo = C_Container.GetContainerItemQuestInfo(bagID, slotID)
        if questInfo then
            if questInfo.questID and not questInfo.isActive then
                return "Islands-QuestBang"
            end
            if questInfo.isQuestItem or (questInfo.questID and questInfo.isActive) then
                return "Islands-QuestTurnin"
            end
        end
    end

    local applicable, known = ResolveCollectibleKnownState(info.hyperlink, info.itemID)
    if applicable then
        if known ~= true then
            return BAG_STATUS_ICON_ATLAS_UNKNOWN
        end
        return nil
    end

    if info.quality == 0 then
        return "coin-icon"
    end

    return nil
end

local function UpdateBagStatusIcon(frame)
    if not frame then return end
    local icon = frame.RefineUIBorderStatusIcon
    if frame._disableBagStatusIcon then
        if icon then
            icon:Hide()
        end
        return
    end

    local atlas = ResolveBagStatusAtlas(frame)
    if not atlas then
        if icon then
            icon:Hide()
        end
        return
    end

    icon = CreateBagStatusIcon(frame)
    local iconParent = GetBagStatusParent(frame)
    if icon:GetParent() ~= iconParent then
        icon:SetParent(iconParent)
    end

    if atlas == BAG_STATUS_ICON_ATLAS_UNKNOWN then
        icon:SetSize(BAG_UNKNOWN_ICON_SIZE, BAG_UNKNOWN_ICON_SIZE)
        icon:ClearAllPoints()
        icon:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", BAG_UNKNOWN_ICON_INSET_X, BAG_UNKNOWN_ICON_INSET_Y)
    else
        icon:SetSize(BAG_STATUS_ICON_SIZE, BAG_STATUS_ICON_SIZE)
        icon:ClearAllPoints()
        icon:SetPoint("CENTER", GetBagStatusAnchor(frame), "TOPLEFT", BAG_STATUS_ICON_OFFSET_X, BAG_STATUS_ICON_OFFSET_Y)
    end
    icon:SetDrawLayer("OVERLAY", BAG_STATUS_ICON_SUBLEVEL)
    local ok = pcall(icon.SetAtlas, icon, atlas, false)
    if not ok then
        icon:Hide()
        return
    end
    icon:Show()
end

function Borders:GetIterButton(a, b)
    if type(a) == "table" and a.GetObjectType then
        return a
    end
    if type(b) == "table" and b.GetObjectType then
        return b
    end
end

function Borders:IterateFrameItems(frame, callback)
    if not frame or not frame.EnumerateValidItems then return false end
    for a, b in frame:EnumerateValidItems() do
        local button = self:GetIterButton(a, b)
        if button then
            callback(button)
        end
    end
    return true
end

function Borders:IteratePoolItems(pool, callback)
    if not pool or not pool.EnumerateActive then return false end
    for a, b in pool:EnumerateActive() do
        local button = self:GetIterButton(a, b)
        if button then
            callback(button)
        end
    end
    return true
end

function Borders:GetButtonItemData(button)
    if not button then return nil, nil end

    if button.GetBagID and button.GetID then
        local bagID = button:GetBagID()
        local slotID = button:GetID()
        if bagID and slotID and C_Container and C_Container.GetContainerItemInfo then
            local info = C_Container.GetContainerItemInfo(bagID, slotID)
            if info then
                return info.hyperlink, info.itemID
            end
            return nil, nil
        end
    end

    if button.GetBankTabID and button.GetContainerSlotID and C_Container and C_Container.GetContainerItemInfo then
        local bankTabID = button:GetBankTabID()
        local containerSlotID = button:GetContainerSlotID()
        if bankTabID and containerSlotID then
            local info = C_Container.GetContainerItemInfo(bankTabID, containerSlotID)
            if info then
                return info.hyperlink, info.itemID
            end
            return nil, nil
        end
    end

    local itemLocation = (button.GetItemLocation and button:GetItemLocation()) or button.itemLocation
    if itemLocation then
        local bagID, slotID
        if itemLocation.GetBagAndSlot then
            bagID, slotID = itemLocation:GetBagAndSlot()
        else
            bagID = itemLocation.bagID
            slotID = itemLocation.slotIndex or itemLocation.slot
        end

        if bagID and slotID and C_Container and C_Container.GetContainerItemInfo then
            local info = C_Container.GetContainerItemInfo(bagID, slotID)
            if info then
                return info.hyperlink, info.itemID
            end
            return nil, nil
        end

        if C_Item and itemLocation.IsValid and itemLocation:IsValid() then
            local itemID = C_Item.GetItemID and C_Item.GetItemID(itemLocation) or nil
            local link = C_Item.GetItemLink and C_Item.GetItemLink(itemLocation) or nil
            return link, itemID
        end
    end

    return nil, nil
end

----------------------------------------------------------------------------------------
-- Public Styling API
----------------------------------------------------------------------------------------
function Borders:RegisterSource(key, fn)
    if type(fn) ~= "function" then return end
    key = key or tostring(fn)

    if not pipes[key] then
        pipeOrder[#pipeOrder + 1] = key
    end
    pipes[key] = fn
end

function Borders:ApplyItemBorder(frame, itemLink, itemID, borderStyle)
    if not frame then return end
    local isRefineBagSlot = IsRefineBagSlot(frame)

    local borderInset = DEFAULT_BORDER_INSET
    local borderEdgeSize = nil
    local forceRefresh = false
    if type(borderStyle) == "table" then
        if type(borderStyle.inset) == "number" then
            borderInset = borderStyle.inset
        end
        if type(borderStyle.edgeSize) == "number" then
            borderEdgeSize = borderStyle.edgeSize
        end
        forceRefresh = borderStyle.forceRefresh == true
    end

    local signature = tostring(itemLink or "") .. "|" .. tostring(itemID or 0) .. "|" .. tostring(borderInset) .. "|" .. tostring(borderEdgeSize or "")
    local frameCache = FRAME_BORDER_CACHE[frame]
    if not forceRefresh and frameCache and frameCache.signature == signature then
        UpdateBagStatusIcon(frame)
        return
    end

    local quality, itemEquipLoc, classID
    if itemLink then
        local _, _, q, _, _, _, _, _, equipLoc, _, _, itemClassID = GetItemInfo(itemLink)
        quality = q
        itemEquipLoc = equipLoc
        classID = itemClassID
    elseif itemID then
        local _, link, q, _, _, _, _, _, equipLoc, _, _, itemClassID = GetItemInfo(itemID)
        quality = q
        itemEquipLoc = equipLoc
        classID = itemClassID
        itemLink = itemLink or link
    end

    if not isRefineBagSlot then
        RefineUI.CreateBorder(frame, borderInset, borderInset, borderEdgeSize)
    end

    if quality then
        local r, g, b = self:GetQualityColor(quality)
        r = r or 1
        g = g or 1
        b = b or 1

        if frame.border and not isRefineBagSlot then
            frame.border:SetBackdropBorderColor(r, g, b)
        end

        if itemLink then
            local isEquipment = (classID == 2 or classID == 4)
            if isEquipment and itemEquipLoc and itemEquipLoc ~= "" and itemEquipLoc ~= "INVTYPE_NON_EQUIP"
                and itemEquipLoc ~= "INVTYPE_BAG" and itemEquipLoc ~= "INVTYPE_TABARD" and itemEquipLoc ~= "INVTYPE_BODY" then

                local text = CreateItemLevelText(frame)
                local textParent = GetItemLevelTextParent(frame)
                if textParent and text:GetParent() ~= textParent then
                    text:SetParent(textParent)
                end

                local itemLevelKey = itemLink or itemID
                local itemLevel = ITEM_LEVEL_CACHE[itemLevelKey]
                if itemLevel == nil then
                    itemLevel = GetDetailedItemLevelInfo(itemLink)
                    ITEM_LEVEL_CACHE[itemLevelKey] = itemLevel or false
                elseif itemLevel == false then
                    itemLevel = nil
                end
                if itemLevel and itemLevel > SQUISH_THRESHOLD then
                    itemLevel = GetPostSquishItemLevel(itemLevel)
                end

                if itemLevel and itemLevel > 1 then
                    text:SetText(itemLevel)
                    text:SetTextColor(r, g, b)
                    text:Show()
                else
                    text:Hide()
                end
            else
                local text = frame.RefineUIBorderItemLevel
                if text then text:Hide() end
            end
        else
            local text = frame.RefineUIBorderItemLevel
            if text then text:Hide() end
        end
    else
        if frame.border and not isRefineBagSlot then
            local r, g, b, a = GetDefaultBorderColor()
            frame.border:SetBackdropBorderColor(r, g, b, a)
        end
        local text = frame.RefineUIBorderItemLevel
        if text then text:Hide() end
    end

    FRAME_BORDER_CACHE[frame] = FRAME_BORDER_CACHE[frame] or {}
    FRAME_BORDER_CACHE[frame].signature = signature
    UpdateBagStatusIcon(frame)
end

----------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------
function Borders:OnEnable()
    for i = 1, #pipeOrder do
        local key = pipeOrder[i]
        local fn = pipes[key]
        if fn then
            local ok, err = pcall(fn, self)
            if not ok then
                self:Error("Source " .. tostring(key) .. ": " .. tostring(err))
            end
        end
    end
end
