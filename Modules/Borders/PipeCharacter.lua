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
    if not location or location < 0 then
        return false, false, false, false, 0, 0
    end

    local locType = bit.band(location, 0x3)
    local slot = bit.rshift(location, 2)
    local player, bank, bags, voidStorage, bag

    if locType == 0 then
        player = true
    elseif locType == 1 then
        bank = true
    elseif locType == 2 then
        player = true
        bags = true
        bag = bit.rshift(slot, 5)
        slot = bit.band(slot, 0x1F)
    elseif locType == 3 then
        voidStorage = true
    end

    return player, bank, bags, voidStorage, slot, bag
end

function Borders:UpdateFlyout(button)
    if not button or not button:IsShown() or not button.location then return end

    local location = button.location
    local id, link

    if location then
        if ItemLocation and ItemLocation.CreateFromLocation then
            local itemLoc = ItemLocation:CreateFromLocation(location)
            if itemLoc and itemLoc:IsValid() then
                link = C_Item.GetItemLink(itemLoc)
                id = C_Item.GetItemID(itemLoc)
            end
        end

        if not link and location < EQUIPMENTFLYOUT_FIRST_SPECIAL_LOCATION then
            if EquipmentManager_GetItemInfoByLocation then
                local itemID = EquipmentManager_GetItemInfoByLocation(location)
                if itemID then
                    id = itemID
                end
            end

            if not id then
                local player, bank, bags, voidStorage, slot, bag = UnpackLocation(location)
                if bags then
                    link = C_Container.GetContainerItemLink(bag, slot)
                    id = C_Container.GetContainerItemID(bag, slot)
                elseif not player and not bank and not bags and not voidStorage then
                else
                    link = GetInventoryItemLink("player", slot)
                    id = GetInventoryItemID("player", slot)
                end
            end
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
