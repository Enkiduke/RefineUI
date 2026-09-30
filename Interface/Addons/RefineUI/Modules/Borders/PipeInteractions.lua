----------------------------------------------------------------------------------------
-- RefineUI Borders Pipe: Merchant / Trade / Mail / Loot / Quest
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Borders = RefineUI:GetModule("Borders")
if not Borders then return end

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local type = type
local GetItemInfo = GetItemInfo
local C_Item = C_Item

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local QUEST_PROXY_REGISTRY = "BordersProxyFrames"

local EJ = {
    BORDER_STYLE = {
        inset = 4,
        edgeSize = 12,
    },
    KNOWN_ICON_ATLAS_KNOWN = "UI-QuestTracker-Tracker-Check",
    KNOWN_ICON_ATLAS_UNKNOWN = "UI-QuestTracker-Objective-Fail",
    KNOWN_ICON_SIZE = 16,
    KNOWN_ICON_INSET_X = 2,
    KNOWN_ICON_INSET_Y = 2,
    REFRESH_DEBOUNCE_KEY = "Borders:EncounterJournal:LootRefresh",
}

local LOOT_HISTORY = {
    BORDER_STYLE = {
        inset = 4,
        edgeSize = 12,
        forceRefresh = true,
    },
    PROXY_KEY = "GroupLootHistoryItem",
}

local EVENT_KEY = {
    TRADE_UPDATE = "Borders_TradeUpdate",
    TRADE_SHOW = "Borders_TradeShow",
    TRADE_PLAYER_ITEM_CHANGED = "Borders_TradePlayer",
    TRADE_TARGET_ITEM_CHANGED = "Borders_TradeTarget",
    MAIL_SHOW = "Borders_MailShow",
    MAIL_SEND_INFO_UPDATE = "Borders_MailInfo",
    MAIL_SEND_SUCCESS = "Borders_MailSuccess",
    EJ_LOOT_DATA_RECIEVED = "Borders_EncounterJournalLootData",
    EJ_DIFFICULTY_UPDATE = "Borders_EncounterJournalDifficulty",
}

local HOOK_KEY = {
    PROFESSIONS_SETUP_OUTPUT_ICON = "Borders:Professions:SetupOutputIcon",
    PROFESSIONS_REAGENT_BUTTON_UPDATE = "Borders:ProfessionsReagentSlotButtonMixin:Update",
    OPENMAIL_UPDATE = "Borders:OpenMail_Update",
    INBOXFRAME_UPDATE = "Borders:InboxFrame_Update",
    LOOTFRAME_ELEMENT_MIXIN_INIT = "Borders:LootFrameElementMixin:Init",
    QUESTINFO_DISPLAY = "Borders:QuestInfo_Display",
    MERCHANTFRAME_UPDATE = "Borders:MerchantFrame_Update",
    ENCOUNTER_JOURNAL_LOOT_CONTAINER_ON_SHOW = "Borders:EncounterJournal:LootContainer:OnShow",
    ENCOUNTER_JOURNAL_LOOT_JOURNAL_ON_SHOW = "Borders:EncounterJournal:LootJournal:OnShow",
    ENCOUNTER_JOURNAL_ON_SHOW = "Borders:EncounterJournal:OnShow",
    LOOT_HISTORY_ELEMENT_INIT = "Borders:LootHistoryElementMixin:Init",
}

----------------------------------------------------------------------------------------
-- Merchant & Trade
----------------------------------------------------------------------------------------
function Borders:UpdateMerchantFrame()
    if not MerchantFrame or not MerchantFrame:IsShown() then return end

    if MerchantFrame.selectedTab == 1 then
        for i = 1, MERCHANT_ITEMS_PER_PAGE do
            local index = (((MerchantFrame.page - 1) * MERCHANT_ITEMS_PER_PAGE) + i)
            local itemLink = GetMerchantItemLink(index)
            local slotFrame = _G["MerchantItem" .. i .. "ItemButton"]
            if slotFrame then
                self:ApplyItemBorder(slotFrame, itemLink)
            end
        end

        local buyBackLink = GetBuybackItemLink(GetNumBuybackItems())
        if MerchantBuyBackItemItemButton then
            self:ApplyItemBorder(MerchantBuyBackItemItemButton, buyBackLink)
        end
    else
        for i = 1, BUYBACK_ITEMS_PER_PAGE do
            local itemLink = GetBuybackItemLink(i)
            local slotFrame = _G["MerchantItem" .. i .. "ItemButton"]
            if slotFrame then
                self:ApplyItemBorder(slotFrame, itemLink)
            end
        end
    end
end

function Borders:UpdateTradeFrame()
    if not TradeFrame or not TradeFrame:IsShown() then return end

    for i = 1, MAX_TRADE_ITEMS or 8 do
        local playerFrame = _G["TradePlayerItem" .. i .. "ItemButton"]
        local playerLink = GetTradePlayerItemLink(i)
        if playerFrame then
            self:ApplyItemBorder(playerFrame, playerLink)
        end

        local targetFrame = _G["TradeRecipientItem" .. i .. "ItemButton"]
        local targetLink = GetTradeTargetItemLink(i)
        if targetFrame then
            self:ApplyItemBorder(targetFrame, targetLink)
        end
    end
end

----------------------------------------------------------------------------------------
-- Mail & Loot
----------------------------------------------------------------------------------------
function Borders:UpdateMailSend()
    if not SendMailFrame or not SendMailFrame:IsShown() then return end
    for i = 1, ATTACHMENTS_MAX_SEND do
        local slotFrame = _G["SendMailAttachment" .. i]
        local slotLink = GetSendMailItemLink(i)
        if slotFrame then
            self:ApplyItemBorder(slotFrame, slotLink)
        end
    end
end

function Borders:UpdateMailInbox()
    if not InboxFrame or not InboxFrame:IsShown() then return end

    local numItems = GetInboxNumItems()
    local index = ((InboxFrame.pageNum - 1) * INBOXITEMS_TO_DISPLAY) + 1
    for i = 1, INBOXITEMS_TO_DISPLAY do
        local slotFrame = _G["MailItem" .. i .. "Button"]
        if slotFrame and index <= numItems then
            local bestQuality = 0
            for j = 1, ATTACHMENTS_MAX_RECEIVE do
                local link = GetInboxItemLink(index, j)
                if link then
                    local _, _, q = GetItemInfo(link)
                    if q and q > bestQuality then
                        bestQuality = q
                    end
                end
            end

            if slotFrame.border then
                local r, g, b, a
                if bestQuality > 1 then
                    r, g, b, a = self:GetQualityColor(bestQuality)
                end
                if not r then
                    r, g, b, a = self:GetDefaultBorderColor()
                end
                slotFrame.border:SetBackdropBorderColor(r, g, b, a or 1)
            end
        end
        index = index + 1
    end
end

function Borders:UpdateOpenMail()
    if not OpenMailFrame or not OpenMailFrame:IsShown() then return end
    if not InboxFrame.openMailID then return end

    for i = 1, ATTACHMENTS_MAX_RECEIVE do
        local slotFrame = _G["OpenMailAttachmentButton" .. i]
        local itemLink = GetInboxItemLink(InboxFrame.openMailID, i)
        if slotFrame then
            self:ApplyItemBorder(slotFrame, itemLink)
        end
    end
end

function Borders:UpdateLoot(frame)
    if not frame then return end
    local slot = frame.GetSlotIndex and frame:GetSlotIndex()
    local slotFrame = frame.Item
    if slot and slotFrame then
        local itemLink = GetLootSlotLink(slot)
        if itemLink then
            self:ApplyItemBorder(slotFrame, itemLink)
        else
            self:ApplyItemBorder(slotFrame, nil)
        end
    end
end

----------------------------------------------------------------------------------------
-- Quests
----------------------------------------------------------------------------------------
function Borders:UpdateQuestRewards()
    local frames = {
        QuestInfoRewardsFrame,
        MapQuestInfoRewardsFrame,
        QuestMapFrame and QuestMapFrame.DetailsFrame and QuestMapFrame.DetailsFrame.RewardsFrameContainer and QuestMapFrame.DetailsFrame.RewardsFrameContainer.RewardsFrame,
    }

    for _, rewardsFrame in pairs(frames) do
        if rewardsFrame and rewardsFrame:IsShown() and rewardsFrame.RewardButtons then
            for _, button in pairs(rewardsFrame.RewardButtons) do
                if button and button:IsShown() and button.objectType == "item" then
                    local link = GetQuestItemLink(button.type, button:GetID())
                    local icon = button.Icon
                    if not icon and button:GetName() then
                        icon = _G[button:GetName() .. "IconTexture"]
                    end

                    if icon then
                        local proxy = RefineUI:RegistryGet(QUEST_PROXY_REGISTRY, button, "QuestReward")
                        if not proxy then
                            proxy = CreateFrame("Frame", nil, button)
                            proxy:SetFrameLevel(button:GetFrameLevel() + 1)
                            RefineUI:RegistrySet(QUEST_PROXY_REGISTRY, button, "QuestReward", proxy)
                        end
                        proxy:ClearAllPoints()
                        proxy:SetAllPoints(icon)
                        self:ApplyItemBorder(proxy, link)
                    else
                        self:ApplyItemBorder(button, link)
                    end
                else
                    if button then
                        local proxy = RefineUI:RegistryGet(QUEST_PROXY_REGISTRY, button, "QuestReward")
                        if proxy then
                            self:ApplyItemBorder(proxy, nil)
                        end
                    end
                end
            end
        end
    end
end

local function GetProxyFrame(owner, key)
    if not owner then
        return nil
    end

    local proxy = RefineUI:RegistryGet(QUEST_PROXY_REGISTRY, owner, key)
    if proxy then
        return proxy
    end

    proxy = CreateFrame("Frame", nil, owner)
    proxy:SetFrameLevel(owner:GetFrameLevel() + 1)
    proxy._disableBagStatusIcon = true
    RefineUI:RegistrySet(QUEST_PROXY_REGISTRY, owner, key, proxy)
    return proxy
end

----------------------------------------------------------------------------------------
-- Group Loot History
----------------------------------------------------------------------------------------
function Borders:UpdateLootHistoryElement(elementFrame, dropInfo)
    if not elementFrame then
        return
    end

    local itemButton = elementFrame.Item
    if not itemButton then
        return
    end

    local itemLink = dropInfo and dropInfo.itemHyperlink
    if type(itemLink) ~= "string" or itemLink == "" then
        local cachedDropInfo = elementFrame.dropInfo
        itemLink = cachedDropInfo and cachedDropInfo.itemHyperlink or nil
    end

    local icon = itemButton.icon or itemButton.Icon or itemButton.IconTexture
    local borderHost = itemButton
    if icon then
        local proxy = GetProxyFrame(itemButton, LOOT_HISTORY.PROXY_KEY)
        if proxy then
            proxy._disableBagStatusIcon = true
            proxy:SetFrameLevel(itemButton:GetFrameLevel() + 1)
            proxy:ClearAllPoints()
            proxy:SetAllPoints(icon)
            borderHost = proxy
        end
    end

    if itemButton.IconBorder then
        itemButton.IconBorder:SetAlpha(0)
    end

    self:ApplyItemBorder(borderHost, itemLink, nil, LOOT_HISTORY.BORDER_STYLE)
    if borderHost.RefineUIBorderItemLevel then
        borderHost.RefineUIBorderItemLevel:Hide()
    end
end

local function GetItemIDFromLink(link)
    if type(link) ~= "string" then
        return nil
    end
    local itemID = link:match("item:(%d+)")
    return itemID and tonumber(itemID) or nil
end

local function NormalizeItemID(candidate)
    local itemID = tonumber(candidate)
    if not itemID or itemID <= 0 then
        return nil
    end
    return itemID
end

local function GetItemIDFromAny(item)
    if not item then
        return nil
    end

    local direct = NormalizeItemID(item)
    if direct then
        return direct
    end

    if type(item) == "string" then
        if C_Item and C_Item.GetItemInfoInstant then
            local instantID = NormalizeItemID(C_Item.GetItemInfoInstant(item))
            if instantID then
                return instantID
            end
        end
        return GetItemIDFromLink(item)
    end

    return nil
end

local function ResolveEncounterJournalRowLink(row)
    if not row then
        return nil
    end

    if row.link and type(row.link) == "string" then
        return row.link
    end
    if row.itemLink and type(row.itemLink) == "string" then
        return row.itemLink
    end
    if row.data and type(row.data) == "table" then
        local data = row.data
        if data.link and type(data.link) == "string" then
            return data.link
        end
        if data.itemLink and type(data.itemLink) == "string" then
            return data.itemLink
        end
        if data.hyperlink and type(data.hyperlink) == "string" then
            return data.hyperlink
        end
    end

    if row.GetItemLink then
        local ok, link = pcall(row.GetItemLink, row)
        if ok and type(link) == "string" then
            return link
        end
    end

    return nil
end

local function ResolveEncounterJournalRowItemID(row, itemLink)
    local itemID = GetItemIDFromAny(itemLink)
    if itemID then
        return itemID
    end

    if not row then
        return nil
    end

    if row.data and type(row.data) == "table" then
        local data = row.data
        itemID = GetItemIDFromAny(data.itemID) or GetItemIDFromAny(data.itemId) or GetItemIDFromAny(data.id)
        if itemID then
            return itemID
        end
        itemID = GetItemIDFromAny(data.link) or GetItemIDFromAny(data.itemLink) or GetItemIDFromAny(data.hyperlink)
        if itemID then
            return itemID
        end
    end

    if row.itemInfo and type(row.itemInfo) == "table" then
        itemID = GetItemIDFromAny(row.itemInfo.itemID) or GetItemIDFromAny(row.itemInfo.itemId) or GetItemIDFromAny(row.itemInfo.id)
        if itemID then
            return itemID
        end
        itemID = GetItemIDFromAny(row.itemInfo.link) or GetItemIDFromAny(row.itemInfo.itemLink) or GetItemIDFromAny(row.itemInfo.hyperlink)
        if itemID then
            return itemID
        end
    end

    return GetItemIDFromAny(row.itemID) or GetItemIDFromAny(row.ItemID)
end

local function ResolveEncounterJournalRowIcon(row)
    if not row then
        return nil
    end

    local icon = row.Icon or row.icon or row.ItemIcon or row.itemIcon
    if icon then
        return icon
    end

    local rowName = row.GetName and row:GetName()
    if rowName then
        local namedIcon = _G[rowName .. "IconTexture"]
        if namedIcon then
            return namedIcon
        end
    end

    return nil
end

local function GetEncounterKnownIcon(frame)
    local parent = frame.border or frame
    local icon = frame.RefineUIEncounterKnownIcon
    if not icon then
        icon = parent:CreateTexture(nil, "OVERLAY", nil, 7)
        icon:SetSize(EJ.KNOWN_ICON_SIZE, EJ.KNOWN_ICON_SIZE)
        icon:SetDrawLayer("OVERLAY", 7)
        icon:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", EJ.KNOWN_ICON_INSET_X, EJ.KNOWN_ICON_INSET_Y)
        frame.RefineUIEncounterKnownIcon = icon
    elseif icon:GetParent() ~= parent then
        icon:SetParent(parent)
    end
    return icon
end

local function UpdateEncounterKnownIcon(frame, itemLink, itemID)
    local icon = frame.RefineUIEncounterKnownIcon
    if not itemLink and not itemID then
        if icon then
            icon:Hide()
        end
        return
    end

    local applicable, known = Borders:ResolveCollectibleKnownState(itemLink, itemID)
    if not applicable then
        if icon then
            icon:Hide()
        end
        return
    end

    icon = GetEncounterKnownIcon(frame)
    local atlas = known and EJ.KNOWN_ICON_ATLAS_KNOWN or EJ.KNOWN_ICON_ATLAS_UNKNOWN
    if icon.refineAtlas ~= atlas then
        local ok = pcall(icon.SetAtlas, icon, atlas, false)
        if not ok then
            icon.refineAtlas = nil
            icon:Hide()
            return
        end
        icon.refineAtlas = atlas
    end
    icon:Show()
end

----------------------------------------------------------------------------------------
-- Encounter Journal
----------------------------------------------------------------------------------------
local EJ_LOOT_KEY = "EncounterJournalEncounterLoot"
local EJ_LOOT_JOURNAL_KEY = "EncounterJournalLootJournal"

local function GetEncounterLootScrollBox()
    local encounterInfo = _G.EncounterJournalEncounterFrameInfo
    local lootContainer = encounterInfo and encounterInfo.LootContainer
    return lootContainer and lootContainer.ScrollBox
end

local function GetLootJournalScrollBox()
    local lootJournal = _G.EncounterJournal and _G.EncounterJournal.LootJournal
    return lootJournal and lootJournal.ScrollBox
end

function Borders:UpdateEncounterJournalRow(row, key)
    local proxy = RefineUI:RegistryGet(QUEST_PROXY_REGISTRY, row, key)
    local icon = row:IsShown() and ResolveEncounterJournalRowIcon(row)
    if icon then
        local itemLink = ResolveEncounterJournalRowLink(row)
        local itemID = ResolveEncounterJournalRowItemID(row, itemLink)
        if not proxy then
            proxy = GetProxyFrame(row, key)
            proxy:SetAllPoints(icon)
        end
        self:ApplyItemBorder(proxy, itemLink, nil, EJ.BORDER_STYLE)
        UpdateEncounterKnownIcon(proxy, itemLink, itemID)
    elseif proxy then
        self:ApplyItemBorder(proxy, nil, nil, EJ.BORDER_STYLE)
        UpdateEncounterKnownIcon(proxy, nil, nil)
    end
end

function Borders:UpdateEncounterJournalLoot()
    local function UpdateScrollBox(scrollBox, key)
        local frames = scrollBox and scrollBox.GetFrames and scrollBox:GetFrames()
        if not frames then
            return
        end

        for _, row in ipairs(frames) do
            self:UpdateEncounterJournalRow(row, key)
        end
    end

    UpdateScrollBox(GetEncounterLootScrollBox(), EJ_LOOT_KEY)
    UpdateScrollBox(GetLootJournalScrollBox(), EJ_LOOT_JOURNAL_KEY)
end

----------------------------------------------------------------------------------------
-- Pipe Registration
----------------------------------------------------------------------------------------
local function SetupInteractionPipe(self)
    RefineUI:RegisterEventCallback("TRADE_UPDATE", function() self:UpdateTradeFrame() end, EVENT_KEY.TRADE_UPDATE)
    RefineUI:RegisterEventCallback("TRADE_SHOW", function() self:UpdateTradeFrame() end, EVENT_KEY.TRADE_SHOW)
    RefineUI:RegisterEventCallback("TRADE_PLAYER_ITEM_CHANGED", function() self:UpdateTradeFrame() end, EVENT_KEY.TRADE_PLAYER_ITEM_CHANGED)
    RefineUI:RegisterEventCallback("TRADE_TARGET_ITEM_CHANGED", function() self:UpdateTradeFrame() end, EVENT_KEY.TRADE_TARGET_ITEM_CHANGED)

    -- Hooked on the templates addon: reagent buttons copy the mixin when the slot pool creates them.
    local function HookProfessions()
        RefineUI:HookOnce(HOOK_KEY.PROFESSIONS_SETUP_OUTPUT_ICON, Professions, "SetupOutputIcon", function(outputIcon, _, outputItemInfo)
            self:ApplyItemBorder(outputIcon, outputItemInfo.hyperlink)
        end)
        RefineUI:HookOnce(HOOK_KEY.PROFESSIONS_REAGENT_BUTTON_UPDATE, ProfessionsReagentSlotButtonMixin, "Update", function(button)
            local reagent = button:GetReagent()
            self:ApplyItemBorder(button, nil, reagent and reagent.itemID)
        end)
    end
    EventUtil.ContinueOnAddOnLoaded("Blizzard_ProfessionsTemplates", HookProfessions)

    RefineUI:RegisterEventCallback("MAIL_SHOW", function() self:UpdateMailSend() end, EVENT_KEY.MAIL_SHOW)
    RefineUI:RegisterEventCallback("MAIL_SEND_INFO_UPDATE", function() self:UpdateMailSend() end, EVENT_KEY.MAIL_SEND_INFO_UPDATE)
    RefineUI:RegisterEventCallback("MAIL_SEND_SUCCESS", function() self:UpdateMailSend() end, EVENT_KEY.MAIL_SEND_SUCCESS)

    RefineUI:HookOnce(HOOK_KEY.OPENMAIL_UPDATE, "OpenMail_Update", function()
        self:UpdateOpenMail()
    end)
    RefineUI:HookOnce(HOOK_KEY.INBOXFRAME_UPDATE, "InboxFrame_Update", function()
        self:UpdateMailInbox()
    end)

    if LootFrameElementMixin then
        RefineUI:HookOnce(HOOK_KEY.LOOTFRAME_ELEMENT_MIXIN_INIT, LootFrameElementMixin, "Init", function(frame)
            self:UpdateLoot(frame)
        end)
    end

    local lootHistoryElementMixin = _G.LootHistoryElementMixin
    if lootHistoryElementMixin and type(lootHistoryElementMixin.Init) == "function" then
        RefineUI:HookOnce(HOOK_KEY.LOOT_HISTORY_ELEMENT_INIT, lootHistoryElementMixin, "Init", function(elementFrame, dropInfo)
            self:UpdateLootHistoryElement(elementFrame, dropInfo)
        end)
    end

    RefineUI:HookOnce(HOOK_KEY.QUESTINFO_DISPLAY, "QuestInfo_Display", function()
        self:UpdateQuestRewards()
    end)

    RefineUI:HookOnce(HOOK_KEY.MERCHANTFRAME_UPDATE, "MerchantFrame_Update", function()
        self:UpdateMerchantFrame()
    end)

    local function RefreshEncounterJournal()
        self:UpdateEncounterJournalLoot()
    end

    -- Deferred so Blizzard's own handlers (e.g. EncounterJournal_LootCallback re-running
    -- button:Init) update the rows first, and so a collection change clears the
    -- collectible cache before rows re-resolve. Also coalesces per-item event bursts.
    local function QueueEncounterRefresh()
        if _G.EncounterJournal and _G.EncounterJournal:IsShown() then
            RefineUI:Debounce(EJ.REFRESH_DEBOUNCE_KEY, 0.05, RefreshEncounterJournal)
        end
    end

    local function HookEncounterJournal()
        -- OnInitializedFrame fires after the row initializer on every acquire, scroll and data refresh.
        -- Rows that already exist are covered by the OnShow full passes below.
        local function HookScrollBox(scrollBox, key)
            if scrollBox and scrollBox.RegisterCallback then
                ScrollUtil.AddInitializedFrameCallback(scrollBox, function(_, row)
                    self:UpdateEncounterJournalRow(row, key)
                end, self, false)
            end
        end
        HookScrollBox(GetEncounterLootScrollBox(), EJ_LOOT_KEY)
        HookScrollBox(GetLootJournalScrollBox(), EJ_LOOT_JOURNAL_KEY)

        local encounterInfo = _G.EncounterJournalEncounterFrameInfo
        local lootContainer = encounterInfo and encounterInfo.LootContainer
        if lootContainer and lootContainer.HookScript then
            RefineUI:HookScriptOnce(HOOK_KEY.ENCOUNTER_JOURNAL_LOOT_CONTAINER_ON_SHOW, lootContainer, "OnShow", function()
                self:UpdateEncounterJournalLoot()
            end)
        end

        local lootJournal = _G.EncounterJournal and _G.EncounterJournal.LootJournal
        if lootJournal and lootJournal.HookScript then
            RefineUI:HookScriptOnce(HOOK_KEY.ENCOUNTER_JOURNAL_LOOT_JOURNAL_ON_SHOW, lootJournal, "OnShow", function()
                self:UpdateEncounterJournalLoot()
            end)
        end

        if _G.EncounterJournal and _G.EncounterJournal.HookScript then
            RefineUI:HookScriptOnce(HOOK_KEY.ENCOUNTER_JOURNAL_ON_SHOW, _G.EncounterJournal, "OnShow", function()
                self:UpdateEncounterJournalLoot()
            end)
        end
    end

    EventUtil.ContinueOnAddOnLoaded("Blizzard_EncounterJournal", HookEncounterJournal)

    RefineUI:RegisterEventCallback("EJ_LOOT_DATA_RECIEVED", QueueEncounterRefresh, EVENT_KEY.EJ_LOOT_DATA_RECIEVED)
    RefineUI:RegisterEventCallback("EJ_DIFFICULTY_UPDATE", QueueEncounterRefresh, EVENT_KEY.EJ_DIFFICULTY_UPDATE)
    RefineUI.Collections:Subscribe("Borders:EncounterJournal", QueueEncounterRefresh)
end

Borders:RegisterSource("Interactions", SetupInteractionPipe)
