----------------------------------------------------------------------------------------
-- RefineUI Borders Pipe: Character / Inspect / Flyout
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Borders = RefineUI:GetModule("Borders")
if not Borders then return end

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local pairs = pairs
local GetInventoryItemLink = GetInventoryItemLink
local GetInventoryItemID = GetInventoryItemID
local C_Item = C_Item

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local EVENT_KEY = {
    PLAYER_ENTERING_WORLD = "Borders_PEW",
    PLAYER_EQUIPMENT_CHANGED = "Borders_PEC",
    INSPECT_READY = "Borders_Inspect",
    ADDON_LOADED_INSPECT = "Borders:InspectUI:Load",
}

local HOOK_KEY = {
    CHARACTER_FRAME_ON_SHOW = "Borders:CharacterFrame:OnShow",
    INSPECT_FRAME_ON_SHOW = "Borders:InspectFrame:OnShow",
    EQUIPMENT_FLYOUT_DISPLAY_BUTTON = "Borders:EquipmentFlyout:DisplayButton",
}

----------------------------------------------------------------------------------------
-- Update Methods
----------------------------------------------------------------------------------------
function Borders:UpdateCharacterFrame()
    if not CharacterFrame or not CharacterFrame:IsShown() then return end

    for _, slotName in pairs(self.CharSlots) do
        local slotFrame = _G["Character" .. slotName .. "Slot"]
        if slotFrame then
            local slotID = GetInventorySlotInfo(slotName .. "Slot")
            local itemLink = GetInventoryItemLink("player", slotID)
            local itemID = GetInventoryItemID("player", slotID)
            self:ApplyItemBorder(slotFrame, itemLink, itemID)
        end
    end
end

function Borders:UpdateInspectFrame()
    if not InspectFrame or not InspectFrame:IsShown() then return end
    local unit = InspectFrame.unit
    if not unit then return end

    for _, slotName in pairs(self.CharSlots) do
        local slotFrame = _G["Inspect" .. slotName .. "Slot"]
        if slotFrame then
            local slotID = GetInventorySlotInfo(slotName .. "Slot")
            local itemLink = GetInventoryItemLink(unit, slotID)
            self:ApplyItemBorder(slotFrame, itemLink)
        end
    end
end

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function UnpackLocation(location)
    if not location or location == 0 or location == -1 then
        return nil
    end

    if EquipmentManager_GetLocationData then
        local ok, locationData = pcall(EquipmentManager_GetLocationData, location)
        if ok and type(locationData) == "table" then
            local isPlayer = locationData.player
            local isBank = (locationData.bank ~= nil and locationData.bank) or locationData.isBank
            local isBags = (locationData.bags ~= nil and locationData.bags) or locationData.isBags
            local isVoid = (locationData.voidStorage ~= nil and locationData.voidStorage) or locationData.isVoidStorage
            return isPlayer, isBank, isBags, isVoid, locationData.slot, locationData.bag
        end
    end

    local unpackLocation = (C_EquipmentSet and C_EquipmentSet.UnpackLocation) or EquipmentManager_UnpackLocation
    if unpackLocation then
        local ok, player, bank, bags, voidStorage, slot, bag = pcall(unpackLocation, location)
        if ok then
            return player, bank, bags, voidStorage, slot, bag
        end
    end

    return nil
end

function Borders:UpdateFlyout(button)
    if not button or not button:IsShown() or not button.location then return end

    local location = button.location
    local id, link

    if location then
        if location < EQUIPMENTFLYOUT_FIRST_SPECIAL_LOCATION then
            local player, bank, bags, voidStorage, slot, bag = UnpackLocation(location)
            if bags and bag and slot and C_Container then
                link = C_Container.GetContainerItemLink(bag, slot)
                id = C_Container.GetContainerItemID(bag, slot)
            elseif player or bank or voidStorage then
                link = GetInventoryItemLink("player", slot)
                id = GetInventoryItemID("player", slot)
            end
        end

        if (not link or not id) and ItemLocation and ItemLocation.CreateFromLocation then
            local itemLoc = ItemLocation:CreateFromLocation(location)
            if itemLoc and itemLoc:IsValid() then
                link = link or C_Item.GetItemLink(itemLoc)
                id = id or C_Item.GetItemID(itemLoc)
            end
        end

        if not id and EquipmentManager_GetItemInfoByLocation and location < EQUIPMENTFLYOUT_FIRST_SPECIAL_LOCATION then
            id = EquipmentManager_GetItemInfoByLocation(location)
        end
    end

    if link then
        self:ApplyItemBorder(button, link, id)
    elseif id then
        self:ApplyItemBorder(button, nil, id)
    else
        self:ApplyItemBorder(button, nil)
    end
end

----------------------------------------------------------------------------------------
-- Pipe Registration
----------------------------------------------------------------------------------------
local function SetupCharacterPipe(self)
    local function UpdateAll()
        self:UpdateCharacterFrame()
    end

    RefineUI:RegisterEventCallback("PLAYER_ENTERING_WORLD", UpdateAll, EVENT_KEY.PLAYER_ENTERING_WORLD)
    RefineUI:RegisterEventCallback("PLAYER_EQUIPMENT_CHANGED", UpdateAll, EVENT_KEY.PLAYER_EQUIPMENT_CHANGED)
    RefineUI:RegisterEventCallback("INSPECT_READY", function() self:UpdateInspectFrame() end, EVENT_KEY.INSPECT_READY)

    if CharacterFrame then
        RefineUI:HookScriptOnce(HOOK_KEY.CHARACTER_FRAME_ON_SHOW, CharacterFrame, "OnShow", function()
            self:UpdateCharacterFrame()
        end)
    end

    local function HookInspect()
        if not InspectFrame then return false end
        local ok, reason = RefineUI:HookScriptOnce(HOOK_KEY.INSPECT_FRAME_ON_SHOW, InspectFrame, "OnShow", function()
            self:UpdateInspectFrame()
        end)
        return ok or reason == "already_hooked"
    end

    if InspectFrame then
        HookInspect()
    else
        local loadKey = EVENT_KEY.ADDON_LOADED_INSPECT
        RefineUI:RegisterEventCallback("ADDON_LOADED", function(_, addon)
            if addon == "Blizzard_InspectUI" then
                local hooked = HookInspect()
                if hooked then
                    RefineUI:OffEvent("ADDON_LOADED", loadKey)
                end
            end
        end, loadKey)
    end

    RefineUI:HookOnce(HOOK_KEY.EQUIPMENT_FLYOUT_DISPLAY_BUTTON, "EquipmentFlyout_DisplayButton", function(button)
        self:UpdateFlyout(button)
    end)
end

Borders:RegisterSource("CharacterInspectFlyout", SetupCharacterPipe)
