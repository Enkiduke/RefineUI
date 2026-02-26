----------------------------------------------------------------------------------------
-- RefineUI Borders Pipe: Bags / Bank / Guild Bank
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Borders = RefineUI:GetModule("Borders")
if not Borders then return end

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local pairs = pairs

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local EVENT_KEY = {
    BANKFRAME_OPENED = "Borders_BankOpen",
    PLAYERBANKSLOTS_CHANGED = "Borders_BankChange",
    BAG_UPDATE_DELAYED = "Borders_BankBagUpdate",
    ADDON_LOADED_BANK_PANELS = "Borders_BankPanelsLoad",
    ADDON_LOADED_GBANK = "Borders_GBankLoad",
}

local HOOK_KEY = {
    BANKFRAME_ON_SHOW = "Borders:BankFrame:OnShow",
    BANKPANEL_ON_SHOW = "Borders:BankPanel:OnShow",
    BANKPANEL_GENERATE_ITEM_SLOTS = "Borders:BankPanel:GenerateItemSlotsForSelectedTab",
    BANKPANEL_REFRESH_ALL_ITEMS = "Borders:BankPanel:RefreshAllItemsForSelectedTab",
    BANKPANEL_RESET = "Borders:BankPanel:Reset",
    REAGENTBANKFRAME_ON_SHOW = "Borders:ReagentBankFrame:OnShow",
    ACCOUNTBANKPANEL_ON_SHOW = "Borders:AccountBankPanel:OnShow",
    GUILDBANKFRAME_UPDATE = "Borders:GuildBankFrame:Update",
}

----------------------------------------------------------------------------------------
-- Update Methods
----------------------------------------------------------------------------------------
function Borders:UpdateBagFrame(frame)
    if not frame then return end
    self:IterateFrameItems(frame, function(button)
        local bagID = button:GetBagID()
        local slotID = button:GetID()
        local info = C_Container.GetContainerItemInfo(bagID, slotID)
        if info then
            self:ApplyItemBorder(button, info.hyperlink, info.itemID)
        else
            self:ApplyItemBorder(button, nil)
        end
    end)
end

function Borders:UpdateBankFrame()
    local updated = false

    local function UpdateModernBankFrame(frame)
        if frame and frame.IsShown and frame:IsShown() and frame.EnumerateValidItems then
            self:IterateFrameItems(frame, function(button)
                local link, itemID = self:GetButtonItemData(button)
                self:ApplyItemBorder(button, link, itemID)
            end)
            return true
        end
        return false
    end

    local bankPanel = BankPanel or (BankFrame and BankFrame.BankPanel)
    updated = UpdateModernBankFrame(bankPanel) or updated
    updated = UpdateModernBankFrame(BankFrame) or updated
    updated = UpdateModernBankFrame(ReagentBankFrame) or updated
    updated = UpdateModernBankFrame(AccountBankPanel) or updated

    if bankPanel and bankPanel.IsShown and bankPanel:IsShown() then
        updated = self:IteratePoolItems(bankPanel.itemButtonPool, function(button)
            local link, itemID = self:GetButtonItemData(button)
            self:ApplyItemBorder(button, link, itemID)
        end) or updated
        updated = self:IteratePoolItems(bankPanel.ItemButtonPool, function(button)
            local link, itemID = self:GetButtonItemData(button)
            self:ApplyItemBorder(button, link, itemID)
        end) or updated
    end

    if AccountBankPanel and AccountBankPanel.IsShown and AccountBankPanel:IsShown() then
        updated = self:IteratePoolItems(AccountBankPanel.itemButtonPool, function(button)
            local link, itemID = self:GetButtonItemData(button)
            self:ApplyItemBorder(button, link, itemID)
        end) or updated
        updated = self:IteratePoolItems(AccountBankPanel.ItemButtonPool, function(button)
            local link, itemID = self:GetButtonItemData(button)
            self:ApplyItemBorder(button, link, itemID)
        end) or updated
        updated = self:IteratePoolItems(AccountBankPanel.itemSlotPool, function(button)
            local link, itemID = self:GetButtonItemData(button)
            self:ApplyItemBorder(button, link, itemID)
        end) or updated
        updated = self:IteratePoolItems(AccountBankPanel.ItemSlotPool, function(button)
            local link, itemID = self:GetButtonItemData(button)
            self:ApplyItemBorder(button, link, itemID)
        end) or updated
    end

    if updated then return end

    if not BankFrame or not BankFrame:IsShown() then return end
    for i = 1, 28 do
        local slotFrame = _G["BankFrameItem" .. i]
        local info = C_Container.GetContainerItemInfo(-1, i)
        if slotFrame then
            if info then
                self:ApplyItemBorder(slotFrame, info.hyperlink, info.itemID)
            else
                self:ApplyItemBorder(slotFrame, nil)
            end
        end
    end
end

function Borders:UpdateGuildBankNormal()
    if not GuildBankFrame or not GuildBankFrame:IsShown() then return end

    local tab = GetCurrentGuildBankTab() or 1
    for i = 1, MAX_GUILDBANK_SLOTS_PER_TAB or 98 do
        local index = math.fmod(i, 14)
        if index == 0 then index = 14 end
        local column = math.ceil((i - 0.5) / 14)

        if GuildBankFrame.Columns and GuildBankFrame.Columns[column] and GuildBankFrame.Columns[column].Buttons then
            local slotFrame = GuildBankFrame.Columns[column].Buttons[index]
            local slotLink = GetGuildBankItemLink(tab, i)
            if slotFrame then
                self:ApplyItemBorder(slotFrame, slotLink)
            end
        end
    end
end

----------------------------------------------------------------------------------------
-- Pipe Registration
----------------------------------------------------------------------------------------
local function SetupContainerPipe(self)
    local bankRefreshQueued = false
    local function QueueBankRefresh()
        if bankRefreshQueued then return end
        bankRefreshQueued = true
        C_Timer.After(0.05, function()
            bankRefreshQueued = false
            self:UpdateBankFrame()
        end)
    end

    local function RefreshBankNowAndSoon()
        self:UpdateBankFrame()
        QueueBankRefresh()
    end

    RefineUI:RegisterEventCallback("BANKFRAME_OPENED", function() RefreshBankNowAndSoon() end, EVENT_KEY.BANKFRAME_OPENED)
    RefineUI:RegisterEventCallback("PLAYERBANKSLOTS_CHANGED", function() self:UpdateBankFrame() end, EVENT_KEY.PLAYERBANKSLOTS_CHANGED)
    RefineUI:RegisterEventCallback("BAG_UPDATE_DELAYED", function() self:UpdateBankFrame() end, EVENT_KEY.BAG_UPDATE_DELAYED)

    local function HookBankPanels()
        local bankPanel = BankPanel or (BankFrame and BankFrame.BankPanel)

        if BankFrame and BankFrame.HookScript then
            RefineUI:HookScriptOnce(HOOK_KEY.BANKFRAME_ON_SHOW, BankFrame, "OnShow", function()
                RefreshBankNowAndSoon()
            end)
        end
        if bankPanel then
            if bankPanel.HookScript then
                RefineUI:HookScriptOnce(HOOK_KEY.BANKPANEL_ON_SHOW, bankPanel, "OnShow", function()
                    RefreshBankNowAndSoon()
                end)
            end
            if bankPanel.GenerateItemSlotsForSelectedTab then
                RefineUI:HookOnce(HOOK_KEY.BANKPANEL_GENERATE_ITEM_SLOTS, bankPanel, "GenerateItemSlotsForSelectedTab", function()
                    RefreshBankNowAndSoon()
                end)
            end
            if bankPanel.RefreshAllItemsForSelectedTab then
                RefineUI:HookOnce(HOOK_KEY.BANKPANEL_REFRESH_ALL_ITEMS, bankPanel, "RefreshAllItemsForSelectedTab", function()
                    RefreshBankNowAndSoon()
                end)
            end
            if bankPanel.Reset then
                RefineUI:HookOnce(HOOK_KEY.BANKPANEL_RESET, bankPanel, "Reset", function()
                    RefreshBankNowAndSoon()
                end)
            end
        end
        if ReagentBankFrame and ReagentBankFrame.HookScript then
            RefineUI:HookScriptOnce(HOOK_KEY.REAGENTBANKFRAME_ON_SHOW, ReagentBankFrame, "OnShow", function()
                RefreshBankNowAndSoon()
            end)
        end
        if AccountBankPanel and AccountBankPanel.HookScript then
            RefineUI:HookScriptOnce(HOOK_KEY.ACCOUNTBANKPANEL_ON_SHOW, AccountBankPanel, "OnShow", function()
                RefreshBankNowAndSoon()
            end)
        end
    end

    HookBankPanels()
    RefineUI:RegisterEventCallback("ADDON_LOADED", function(_, addon)
        if addon == "Blizzard_UIPanels_Game" or addon == "Blizzard_BankUI" or addon == "Blizzard_WarbandBankUI" then
            HookBankPanels()
            RefreshBankNowAndSoon()
        end
    end, EVENT_KEY.ADDON_LOADED_BANK_PANELS)

    local function HookGuildBank()
        if GuildBankFrame then
            RefineUI:HookOnce(HOOK_KEY.GUILDBANKFRAME_UPDATE, GuildBankFrame, "Update", function()
                self:UpdateGuildBankNormal()
            end)
        end
    end

    if GuildBankFrame then
        HookGuildBank()
    else
        RefineUI:RegisterEventCallback("ADDON_LOADED", function(_, addon)
            if addon == "Blizzard_GuildBankUI" then
                HookGuildBank()
            end
        end, EVENT_KEY.ADDON_LOADED_GBANK)
    end

    local function HookBags()
        local function UpdateContainer(frame)
            self:UpdateBagFrame(frame)
        end

        for i = 1, NUM_CONTAINER_FRAMES do
            local frame = _G["ContainerFrame" .. i]
            if frame then
                RefineUI:HookOnce("Borders:ContainerFrame" .. i .. ":UpdateItems", frame, "UpdateItems", UpdateContainer)
            end
        end

        if ContainerFrameCombinedBags then
            RefineUI:HookOnce("Borders:ContainerFrameCombinedBags:UpdateItems", ContainerFrameCombinedBags, "UpdateItems", UpdateContainer)
        end
    end

    HookBags()
end

Borders:RegisterSource("Containers", SetupContainerPipe)
