----------------------------------------------------------------------------------------
-- RefineUI Toasts: Sources
-- Description: RefineUI toasts for loot, currency, gold, and routed Battle.net toasts.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Toasts = RefineUI:GetModule("Toasts")

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local ipairs = ipairs
local tonumber = tonumber

local C_BattleNet = C_BattleNet
local C_CurrencyInfo = C_CurrencyInfo
local C_Item = C_Item
local GetCVarBool = GetCVarBool
local GetMoney = GetMoney
local Item = Item

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local MONEY_ICON = "Interface\\Icons\\INV_Misc_Coin_01"
local BN_ICON = "Interface\\FriendsFrame\\UI-Toast-ToastIcons"
local BN_COORDS_FRIEND = { 0, 0.25, 0.5, 1 }
local BN_COORDS_BROADCAST = { 0, 0.25, 0, 0.5 }
local BN_COORDS_INVITE = { 0.75, 1, 0, 0.5 }
local BN_COORDS_CLUB = { 0.5, 0.75, 0, 0.5 }

-- BNToastFrame toast types (locals in Blizzard_BNet/Mainline/BNet.lua).
local BN_TOAST_TYPE_ONLINE = 1
local BN_TOAST_TYPE_OFFLINE = 2
local BN_TOAST_TYPE_BROADCAST = 3
local BN_TOAST_TYPE_PENDING_INVITES = 4
local BN_TOAST_TYPE_NEW_INVITE = 5
local BN_TOAST_TYPE_CLUB_INVITATION = 6
local BN_TOAST_TYPE_CLUB_FINDER_INVITATION = 7

-- Self-loot chat lines; multiple-quantity forms must match first.
local LOOT_STRINGS = {
    "LOOT_ITEM_SELF_MULTIPLE",
    "LOOT_ITEM_PUSHED_SELF_MULTIPLE",
    "LOOT_ITEM_CREATED_SELF_MULTIPLE",
    "LOOT_ITEM_SELF",
    "LOOT_ITEM_PUSHED_SELF",
    "LOOT_ITEM_CREATED_SELF",
}

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
local lootPatterns = {}
local lastMoney

----------------------------------------------------------------------------------------
-- Click Actions (mirror the Blizzard toasts' OnClick handlers)
----------------------------------------------------------------------------------------
local function OpenItemBag(entry)
    local bag = SearchBagsForItemLink(entry.link)
    if bag >= 0 then
        OpenBag(bag)
    end
end

local function OpenCurrency()
    ToggleCharacter("TokenFrame")
end

local function WhisperFriend(entry)
    local accountInfo = C_BattleNet.GetAccountInfoByID(entry.bnetAccountID)
    if accountInfo then
        ChatFrameUtil.SendBNetTell(accountInfo.accountName)
    end
end

local function OpenFriendRequests()
    if SocialUIControl and SocialUIControl.IsEnabled() then
        SocialUIControl.OpenToTab(SocialUITabType.FriendRequests)
        return
    end
    if not FriendsFrame:IsShown() then
        ToggleFriendsFrame(FRIEND_TAB_FRIENDS)
    end
    if GetCVarBool("friendInvitesCollapsed") then
        FriendsListFrame_ToggleInvites()
    end
    FriendsTabHeader:SelectTab(FriendsTabHeader.friendsTabID)
end

local function OpenClub(entry)
    ShowUIPanel(CommunitiesFrame)
    CommunitiesFrame:SelectClub(entry.clubID)
end

----------------------------------------------------------------------------------------
-- Loot
----------------------------------------------------------------------------------------
local AddItem
AddItem = function(link, count)
    local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(link)
    if not name then
        Item:CreateFromItemLink(link):ContinueOnItemLoad(function()
            AddItem(link, count)
        end)
        return
    end
    if quality < Toasts.db.LootQuality then
        return
    end

    Toasts:Add({
        key = "item:" .. C_Item.GetItemInfoInstant(link),
        icon = icon,
        title = YOU_RECEIVED_LABEL,
        text = name,
        quality = quality,
        count = count,
        link = link,
        onClick = OpenItemBag,
    })
end

local function OnChatLoot(_, text)
    -- Chat text is secret during chat messaging lockdown.
    if RefineUI:IsSecretValue(text) then
        return
    end
    for i = 1, #lootPatterns do
        local link, quantity = text:match(lootPatterns[i])
        if link then
            if link:find("|Hitem:", 1, true) then
                AddItem(link, tonumber(quantity) or 1)
            end
            return
        end
    end
end

----------------------------------------------------------------------------------------
-- Currency / Gold
----------------------------------------------------------------------------------------
local function OnCurrencyUpdate(_, currencyID, _, quantityChange)
    if not currencyID or not quantityChange or quantityChange <= 0 then
        return
    end
    local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
    -- Undiscovered, header, and recharging (e.g. skyriding charge) entries are not player-facing gains.
    if not info or info.isHeader or not info.discovered or info.name == "" or info.rechargingCycleDurationMS > 0 then
        return
    end
    Toasts:Add({
        key = "currency:" .. currencyID,
        icon = info.iconFileID,
        title = CURRENCY,
        text = info.name,
        quality = info.quality,
        count = quantityChange,
        countFormat = "+",
        onClick = OpenCurrency,
    })
end

local function OnPlayerMoney()
    local money = GetMoney()
    local delta = money - lastMoney
    lastMoney = money
    if delta <= 0 then
        return
    end
    Toasts:Add({
        key = "money",
        icon = MONEY_ICON,
        title = MONEY,
        count = delta,
        countFormat = "money",
    })
end

----------------------------------------------------------------------------------------
-- Battle.net (BNToastMixin:ShowToast)
----------------------------------------------------------------------------------------
local function AddFriend(accountID, title, text, coords, textColor)
    Toasts:Add({
        key = "bnet:" .. accountID,
        icon = BN_ICON,
        iconCoords = coords,
        title = title,
        text = text,
        color = FRIENDS_BNET_NAME_COLOR,
        textColor = textColor or FRIENDS_BNET_NAME_COLOR,
        bnetAccountID = accountID,
        onClick = WhisperFriend,
    })
end

local function AddFriendRequests(text)
    Toasts:Add({ key = "bnet:invites", icon = BN_ICON, iconCoords = BN_COORDS_INVITE, text = text, color = FRIENDS_BNET_NAME_COLOR, onClick = OpenFriendRequests })
end

local BN_TOASTS = {
    [BN_TOAST_TYPE_ONLINE] = function(accountID)
        local accountInfo = C_BattleNet.GetAccountInfoByID(accountID)
        if accountInfo then
            AddFriend(accountID, BN_TOAST_ONLINE, accountInfo.accountName, BN_COORDS_FRIEND)
        end
    end,

    [BN_TOAST_TYPE_OFFLINE] = function(accountID)
        local accountInfo = C_BattleNet.GetAccountInfoByID(accountID)
        if accountInfo then
            AddFriend(accountID, BN_TOAST_OFFLINE, accountInfo.accountName, BN_COORDS_FRIEND)
        end
    end,

    [BN_TOAST_TYPE_BROADCAST] = function(accountID)
        local accountInfo = C_BattleNet.GetAccountInfoByID(accountID)
        if accountInfo and accountInfo.customMessage ~= "" then
            AddFriend(accountID, accountInfo.accountName, accountInfo.customMessage, BN_COORDS_BROADCAST, HIGHLIGHT_FONT_COLOR)
        end
    end,

    [BN_TOAST_TYPE_PENDING_INVITES] = function(listSize)
        AddFriendRequests(BN_TOAST_PENDING_INVITES:format(listSize))
    end,

    [BN_TOAST_TYPE_NEW_INVITE] = function()
        AddFriendRequests(BN_TOAST_NEW_INVITE)
    end,

    [BN_TOAST_TYPE_CLUB_INVITATION] = function(invitation)
        local club = invitation.club
        Toasts:Add({ icon = BN_ICON, iconCoords = BN_COORDS_CLUB, text = BN_TOAST_NEW_CLUB_INVITATION:format(club.name), color = FRIENDS_BNET_NAME_COLOR, clubID = club.clubId, onClick = OpenClub })
    end,

    [BN_TOAST_TYPE_CLUB_FINDER_INVITATION] = function(clubInfo)
        Toasts:Add({ icon = BN_ICON, iconCoords = BN_COORDS_CLUB, text = BN_TOAST_NEW_CLUB_INVITATION:format(clubInfo.name), color = FRIENDS_BNET_NAME_COLOR })
    end,
}

-- Blizzard's toast CVars and filters already decided to show this; RefineUI only displays it.
function Toasts:RouteBNToast(frame)
    local handler = BN_TOASTS[frame.toastType]
    if handler then
        handler(frame.toastData)
    end
    -- BNToastMixin:OnHide shows its next queued toast, which routes here again.
    frame:Hide()
end

----------------------------------------------------------------------------------------
-- Enable
----------------------------------------------------------------------------------------
function Toasts:EnableSources()
    local db = self.db

    if db.Loot then
        for i, name in ipairs(LOOT_STRINGS) do
            local pattern = _G[name]:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
            lootPatterns[i] = "^" .. pattern
        end
        RefineUI:RegisterEventCallback("CHAT_MSG_LOOT", OnChatLoot, "Toasts:CHAT_MSG_LOOT")
    end

    if db.Currency then
        RefineUI:RegisterEventCallback("CURRENCY_DISPLAY_UPDATE", OnCurrencyUpdate, "Toasts:CURRENCY_DISPLAY_UPDATE")
    end

    if db.Money then
        lastMoney = GetMoney()
        RefineUI:RegisterEventCallback("PLAYER_MONEY", OnPlayerMoney, "Toasts:PLAYER_MONEY")
    end
end
