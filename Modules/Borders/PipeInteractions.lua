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
local tostring = tostring
local tonumber = tonumber
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
    UPDATE_JOB_KEY = "Borders:EncounterJournal:LootRefresh",
}

local EVENT_KEY = {
    TRADE_UPDATE = "Borders_TradeUpdate",
    TRADE_SHOW = "Borders_TradeShow",
    TRADE_PLAYER_ITEM_CHANGED = "Borders_TradePlayer",
    TRADE_TARGET_ITEM_CHANGED = "Borders_TradeTarget",
    ADDON_LOADED_PROF = "Borders_PROFLoad",
    MAIL_SHOW = "Borders_MailShow",
    MAIL_SEND_INFO_UPDATE = "Borders_MailInfo",
    MAIL_SEND_SUCCESS = "Borders_MailSuccess",
    ADDON_LOADED_ENCOUNTER_JOURNAL = "Borders_EncounterJournalLoad",
    EJ_LOOT_DATA_RECIEVED = "Borders_EncounterJournalLootData",
    EJ_DIFFICULTY_UPDATE = "Borders_EncounterJournalDifficulty",
}

local HOOK_KEY = {
    TRADESKILLFRAME_RECIPELIST_SET_SELECTED = "Borders:TradeSkillFrame:RecipeList:SetSelectedRecipeID",
    OPENMAIL_UPDATE = "Borders:OpenMail_Update",
    INBOXFRAME_UPDATE = "Borders:InboxFrame_Update",
    LOOTFRAME_ELEMENT_MIXIN_INIT = "Borders:LootFrameElementMixin:Init",
    QUESTINFO_DISPLAY = "Borders:QuestInfo_Display",
    MERCHANTFRAME_UPDATE = "Borders:MerchantFrame_Update",
    ENCOUNTER_JOURNAL_LOOT_CONTAINER_ON_SHOW = "Borders:EncounterJournal:LootContainer:OnShow",
    ENCOUNTER_JOURNAL_LOOT_JOURNAL_ON_SHOW = "Borders:EncounterJournal:LootJournal:OnShow",
    ENCOUNTER_JOURNAL_ON_SHOW = "Borders:EncounterJournal:OnShow",
    ENCOUNTER_JOURNAL_ON_HIDE = "Borders:EncounterJournal:OnHide",
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

function Borders:UpdateTradeSkillFrame(recipeID)
    if not TradeSkillFrame or not TradeSkillFrame:IsShown() then return end
    if not recipeID and C_TradeSkillUI.GetSelectedRecipeID then
        recipeID = C_TradeSkillUI.GetSelectedRecipeID()
    end
    if not recipeID then return end

    if TradeSkillFrame.DetailsFrame and TradeSkillFrame.DetailsFrame.Contents and TradeSkillFrame.DetailsFrame.Contents.ResultIcon then
        local resultLink = C_TradeSkillUI.GetRecipeItemLink(recipeID)
        local resultFrame = TradeSkillFrame.DetailsFrame.Contents.ResultIcon
        self:ApplyItemBorder(resultFrame, resultLink)
    end

    if TradeSkillFrame.DetailsFrame and TradeSkillFrame.DetailsFrame.Contents and TradeSkillFrame.DetailsFrame.Contents.Reagents then
        for i = 1, C_TradeSkillUI.GetRecipeNumReagents(recipeID) do
            local reagentFrame = TradeSkillFrame.DetailsFrame.Contents.Reagents[i] and TradeSkillFrame.DetailsFrame.Contents.Reagents[i].Icon
            local reagentLink = C_TradeSkillUI.GetRecipeReagentItemLink(recipeID, i)
            if reagentFrame then
                self:ApplyItemBorder(reagentFrame, reagentLink)
            end
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

local function ResolveCollectibleKnownState(itemLink, itemID)
    if Borders and Borders.ResolveCollectibleKnownState then
        return Borders:ResolveCollectibleKnownState(itemLink, itemID)
    end

    if itemID and C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
    end
    return false, nil
end

local function GetEncounterKnownIconParent(frame)
    if frame and frame.border then
        return frame.border
    end
    return frame
end

local function GetEncounterKnownIcon(frame)
    if not frame then
        return nil
    end

    local parent = GetEncounterKnownIconParent(frame)
    local icon = frame.RefineUIEncounterKnownIcon
    if icon and icon:GetParent() ~= parent then
        icon:SetParent(parent)
    end

    if not icon then
        icon = parent:CreateTexture(nil, "OVERLAY", nil, 7)
        icon:SetSize(EJ.KNOWN_ICON_SIZE, EJ.KNOWN_ICON_SIZE)
        icon:SetDrawLayer("OVERLAY", 7)
        frame.RefineUIEncounterKnownIcon = icon
    end

    icon:ClearAllPoints()
    icon:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", EJ.KNOWN_ICON_INSET_X, EJ.KNOWN_ICON_INSET_Y)
    return icon
end

local function UpdateEncounterKnownIcon(frame, itemLink, itemID)
    if not frame then
        return
    end

    local icon = frame.RefineUIEncounterKnownIcon
    if not itemLink and not itemID then
        if icon then
            icon:Hide()
        end
        return
    end

    local applicable, known = ResolveCollectibleKnownState(itemLink, itemID)
    if not applicable then
        if icon then
            icon:Hide()
        end
        return
    end

    icon = GetEncounterKnownIcon(frame)
    local atlas = known and EJ.KNOWN_ICON_ATLAS_KNOWN or EJ.KNOWN_ICON_ATLAS_UNKNOWN
    local ok = pcall(icon.SetAtlas, icon, atlas, false)
    if not ok then
        icon:Hide()
        return
    end
    icon:Show()
end

----------------------------------------------------------------------------------------
-- Encounter Journal
----------------------------------------------------------------------------------------
function Borders:UpdateEncounterJournalLoot()
    local function UpdateScrollBox(scrollBox, keyPrefix)
        if not (scrollBox and scrollBox.GetFrames) then
            return
        end

        local frames = scrollBox:GetFrames()
        if not frames then
            return
        end

        local key = tostring(keyPrefix or "EncounterJournal")
        for _, row in ipairs(frames) do
            local proxy = row and RefineUI:RegistryGet(QUEST_PROXY_REGISTRY, row, key) or nil
            if row and row:IsShown() then
                local itemLink = ResolveEncounterJournalRowLink(row)
                local itemID = ResolveEncounterJournalRowItemID(row, itemLink)
                local icon = ResolveEncounterJournalRowIcon(row)
                if icon then
                    proxy = proxy or GetProxyFrame(row, key)
                    proxy:ClearAllPoints()
                    proxy:SetAllPoints(icon)
                    self:ApplyItemBorder(proxy, itemLink, nil, EJ.BORDER_STYLE)
                    UpdateEncounterKnownIcon(proxy, itemLink, itemID)
                elseif proxy then
                    self:ApplyItemBorder(proxy, nil, nil, EJ.BORDER_STYLE)
                    UpdateEncounterKnownIcon(proxy, nil, nil)
                end
            elseif proxy then
                self:ApplyItemBorder(proxy, nil, nil, EJ.BORDER_STYLE)
                UpdateEncounterKnownIcon(proxy, nil, nil)
            end
        end
    end

    local encounterInfo = _G.EncounterJournalEncounterFrameInfo
    local lootContainer = encounterInfo and encounterInfo.LootContainer
    local lootScrollBox = lootContainer and lootContainer.ScrollBox
    UpdateScrollBox(lootScrollBox, "EncounterJournalEncounterLoot")

    local lootJournal = _G.EncounterJournal and _G.EncounterJournal.LootJournal
    local lootJournalScrollBox = lootJournal and lootJournal.ScrollBox
    UpdateScrollBox(lootJournalScrollBox, "EncounterJournalLootJournal")
end

----------------------------------------------------------------------------------------
-- Pipe Registration
----------------------------------------------------------------------------------------
local function SetupInteractionPipe(self)
    RefineUI:RegisterEventCallback("TRADE_UPDATE", function() self:UpdateTradeFrame() end, EVENT_KEY.TRADE_UPDATE)
    RefineUI:RegisterEventCallback("TRADE_SHOW", function() self:UpdateTradeFrame() end, EVENT_KEY.TRADE_SHOW)
    RefineUI:RegisterEventCallback("TRADE_PLAYER_ITEM_CHANGED", function() self:UpdateTradeFrame() end, EVENT_KEY.TRADE_PLAYER_ITEM_CHANGED)
    RefineUI:RegisterEventCallback("TRADE_TARGET_ITEM_CHANGED", function() self:UpdateTradeFrame() end, EVENT_KEY.TRADE_TARGET_ITEM_CHANGED)

    local function HookTradeSkill()
        if TradeSkillFrame and TradeSkillFrame.RecipeList then
            RefineUI:HookOnce(HOOK_KEY.TRADESKILLFRAME_RECIPELIST_SET_SELECTED, TradeSkillFrame.RecipeList, "SetSelectedRecipeID", function()
                self:UpdateTradeSkillFrame()
            end)
        end
    end

    if TradeSkillFrame then
        HookTradeSkill()
    else
        RefineUI:RegisterEventCallback("ADDON_LOADED", function(_, addon)
            if addon == "Blizzard_TradeSkillUI" then
                HookTradeSkill()
            end
        end, EVENT_KEY.ADDON_LOADED_PROF)
    end

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

    RefineUI:HookOnce(HOOK_KEY.QUESTINFO_DISPLAY, "QuestInfo_Display", function()
        self:UpdateQuestRewards()
    end)

    RefineUI:HookOnce(HOOK_KEY.MERCHANTFRAME_UPDATE, "MerchantFrame_Update", function()
        self:UpdateMerchantFrame()
    end)

    local function HookEncounterJournal()
        if not RefineUI:IsUpdateJobRegistered(EJ.UPDATE_JOB_KEY) then
            RefineUI:RegisterUpdateJob(EJ.UPDATE_JOB_KEY, 0.1, function()
                self:UpdateEncounterJournalLoot()
            end, {
                enabled = false,
                predicate = function()
                    return _G.EncounterJournal and _G.EncounterJournal:IsShown()
                end,
            })
        end

        local function EnableEncounterRefresh()
            RefineUI:SetUpdateJobEnabled(EJ.UPDATE_JOB_KEY, true, true)
            RefineUI:RunUpdateJobNow(EJ.UPDATE_JOB_KEY)
        end

        local function DisableEncounterRefresh()
            RefineUI:SetUpdateJobEnabled(EJ.UPDATE_JOB_KEY, false, true)
        end

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
                EnableEncounterRefresh()
            end)
            RefineUI:HookScriptOnce(HOOK_KEY.ENCOUNTER_JOURNAL_ON_HIDE, _G.EncounterJournal, "OnHide", function()
                DisableEncounterRefresh()
            end)
        end

        if _G.EncounterJournal and _G.EncounterJournal:IsShown() then
            EnableEncounterRefresh()
        else
            DisableEncounterRefresh()
        end
    end

    if _G.EncounterJournal then
        HookEncounterJournal()
    else
        RefineUI:RegisterEventCallback("ADDON_LOADED", function(_, addon)
            if addon == "Blizzard_EncounterJournal" then
                HookEncounterJournal()
            end
        end, EVENT_KEY.ADDON_LOADED_ENCOUNTER_JOURNAL)
    end

    RefineUI:RegisterEventCallback("EJ_LOOT_DATA_RECIEVED", function()
        self:UpdateEncounterJournalLoot()
    end, EVENT_KEY.EJ_LOOT_DATA_RECIEVED)
    RefineUI:RegisterEventCallback("EJ_DIFFICULTY_UPDATE", function()
        self:UpdateEncounterJournalLoot()
    end, EVENT_KEY.EJ_DIFFICULTY_UPDATE)
end

Borders:RegisterSource("Interactions", SetupInteractionPipe)

