----------------------------------------------------------------------------------------
-- RefineUI Toasts: Alerts
-- Description: Alert toasts for things Blizzard only marks with an icon or a chat line.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Toasts = RefineUI:GetModule("Toasts")
local L = RefineUI.Locale.Toasts

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local floor = math.floor
local ipairs = ipairs
local pairs = pairs
local min = math.min

local C_Calendar = C_Calendar
local C_ChallengeMode = C_ChallengeMode
local C_Container = C_Container
local C_Item = C_Item
local C_MythicPlus = C_MythicPlus
local C_VignetteInfo = C_VignetteInfo
local C_WeeklyRewards = C_WeeklyRewards
local GetInventoryItemDurability = GetInventoryItemDurability
local GetLatestThreeSenders = GetLatestThreeSenders
local GetServerTime = GetServerTime
local HasNewMail = HasNewMail

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local MAIL_ICON = "Interface\\Icons\\INV_Letter_15"
local AUCTION_ICON = "Interface\\Icons\\INV_Misc_Coin_02"
local BAG_ICON = "Interface\\Icons\\INV_Misc_Bag_08"
local DURABILITY_ICON = "Interface\\Icons\\Trade_BlackSmithing"
local CALENDAR_ICON = "Interface\\Icons\\INV_Misc_PocketWatch_01"
local VAULT_ATLAS = "greatVault-whole-normal"
local KEYSTONE_ITEM_ID = 180653

-- Auction system chat lines (localized Blizzard strings) and their alert titles.
local AUCTION_STRINGS = {
    { "ERR_AUCTION_SOLD_S", "AuctionSold" },
    { "ERR_AUCTION_EXPIRED_S", "AuctionExpired" },
    { "ERR_AUCTION_OUTBID_S", "AuctionOutbid" },
    { "ERR_AUCTION_WON_S", "AuctionWon" },
}

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
local auctionPatterns = {}
local hadMail, bagsLow, durabilityLow, vaultShown
local pendingInvites = 0
local saved     -- per character: Shown[key] = server time last shown; KeystoneMapID/KeystoneLevel = last keystone shown
local cooldown  -- seconds

local function Alert(entry)
    entry.alert = true
    Toasts:Add(entry)
end

-- State alerts repeat at most once per cooldown; reloads, loading screens, and quick relogs don't reset it.
local function AlertOnCooldown(key, entry)
    local now = GetServerTime()
    local last = saved.Shown[key]
    if last and now - last < cooldown then
        return
    end
    saved.Shown[key] = now
    entry.key = key
    Alert(entry)
end

local function OpenCharacter()
    ToggleCharacter("PaperDollFrame")
end

----------------------------------------------------------------------------------------
-- Mail / Auction
----------------------------------------------------------------------------------------
local function OnPendingMail()
    local hasMail = HasNewMail()
    if hasMail and not hadMail then
        AlertOnCooldown("alert:mail", { icon = MAIL_ICON, title = L.NewMail, text = GetLatestThreeSenders() })
    end
    hadMail = hasMail
end

local function OnSystemMessage(_, text)
    -- Chat text is secret during chat messaging lockdown.
    if RefineUI:IsSecretValue(text) then
        return
    end
    for i = 1, #auctionPatterns do
        local item = text:match(auctionPatterns[i])
        if item then
            Alert({ icon = AUCTION_ICON, title = L[AUCTION_STRINGS[i][2]], text = item })
            return
        end
    end
end

----------------------------------------------------------------------------------------
-- Bags / Durability / Keystone
----------------------------------------------------------------------------------------
local function CheckBags(threshold)
    local free = 0
    for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
        local slots, family = C_Container.GetContainerNumFreeSlots(bag)
        if family == 0 then
            free = free + slots
        end
    end

    local low = free < threshold
    if low and not bagsLow then
        AlertOnCooldown("alert:bags", { icon = BAG_ICON, title = L.BagsFull, text = L.FreeSlots:format(free) })
    end
    bagsLow = low
end

-- Each keystone alerts once; the last one shown is saved, so reloads and relogs stay quiet.
local function CheckKeystone()
    local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    local level = C_MythicPlus.GetOwnedKeystoneLevel()
    if not mapID or not level or (mapID == saved.KeystoneMapID and level == saved.KeystoneLevel) then
        return
    end

    local previousLevel = saved.KeystoneLevel
    saved.KeystoneMapID, saved.KeystoneLevel = mapID, level

    local name, _, _, texture = C_ChallengeMode.GetMapUIInfo(mapID)
    Alert({
        key = "alert:keystone",
        icon = texture or C_Item.GetItemIconByID(KEYSTONE_ITEM_ID),
        title = (previousLevel and level > previousLevel) and L.KeystoneUpgraded or L.NewKeystone,
        text = L.KeystoneFormat:format(level, name),
    })
end

local function CheckDurability(threshold)
    local lowest = 1
    for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
        local current, maximum = GetInventoryItemDurability(slot)
        if current and maximum > 0 then
            lowest = min(lowest, current / maximum)
        end
    end

    local percent = floor(lowest * 100)
    local low = percent < threshold
    if low and not durabilityLow then
        AlertOnCooldown("alert:durability", { icon = DURABILITY_ICON, title = L.LowDurability, text = L.DurabilityPercent:format(percent), onClick = OpenCharacter })
    end
    durabilityLow = low
end

local function OnWeeklyRecord(_, mapID, _, level)
    local name, _, _, texture = C_ChallengeMode.GetMapUIInfo(mapID)
    Alert({ icon = texture or C_Item.GetItemIconByID(KEYSTONE_ITEM_ID), title = L.WeeklyBest, text = L.KeystoneFormat:format(level, name) })
end

----------------------------------------------------------------------------------------
-- World / Weekly
----------------------------------------------------------------------------------------
local function OnVignette(_, vignetteGUID, onMinimap)
    if not onMinimap or RefineUI:IsSecretValue(vignetteGUID) then
        return
    end
    local info = C_VignetteInfo.GetVignetteInfo(vignetteGUID)
    if not info or info.isDead then
        return
    end
    local atlas = info.atlasName
    if RefineUI:IsSecretValue(atlas) then
        return
    end

    local title
    if info.type == Enum.VignetteType.Treasure then
        title = L.Treasure
    elseif atlas:lower():find("vignettekill", 1, true) then
        title = L.Rare
    else
        return
    end

    AlertOnCooldown("alert:vignette:" .. vignetteGUID, { atlas = atlas, title = title, text = info.name })
end

local function OnPendingInvites()
    local count = C_Calendar.GetNumPendingInvites()
    if count > pendingInvites then
        AlertOnCooldown("alert:calendar", { icon = CALENDAR_ICON, title = L.CalendarInvite, text = L.PendingInvites:format(count) })
    end
    pendingInvites = count
end

local function OnWeeklyRewards()
    if not vaultShown and C_WeeklyRewards.HasAvailableRewards() then
        vaultShown = true
        AlertOnCooldown("alert:vault", { atlas = VAULT_ATLAS, title = L.VaultReady, text = L.VaultRewards })
    end
end

----------------------------------------------------------------------------------------
-- Enable
----------------------------------------------------------------------------------------
function Toasts:EnableAlerts()
    local alerts = self.db.Alerts
    cooldown = alerts.Cooldown * 60

    RefineUI.DB.ToastAlerts = RefineUI.DB.ToastAlerts or { Shown = {} }
    saved = RefineUI.DB.ToastAlerts
    local now = GetServerTime()
    for key, time in pairs(saved.Shown) do
        if now - time >= cooldown then
            saved.Shown[key] = nil
        end
    end

    if alerts.Mail then
        RefineUI:RegisterEventCallback("UPDATE_PENDING_MAIL", OnPendingMail, "Toasts:UPDATE_PENDING_MAIL")
    end

    if alerts.Auction then
        for i, strings in ipairs(AUCTION_STRINGS) do
            local pattern = _G[strings[1]]:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)")
            auctionPatterns[i] = "^" .. pattern
        end
        RefineUI:RegisterEventCallback("CHAT_MSG_SYSTEM", OnSystemMessage, "Toasts:CHAT_MSG_SYSTEM")
    end

    if alerts.Bags or alerts.Keystone then
        local bagSlots = alerts.BagSlots
        RefineUI:RegisterEventCallback("BAG_UPDATE_DELAYED", function()
            if alerts.Bags then
                CheckBags(bagSlots)
            end
            if alerts.Keystone then
                CheckKeystone()
            end
        end, "Toasts:BAG_UPDATE_DELAYED")
    end

    if alerts.Keystone then
        RefineUI:RegisterEventCallback("MYTHIC_PLUS_NEW_WEEKLY_RECORD", OnWeeklyRecord, "Toasts:MYTHIC_PLUS_NEW_WEEKLY_RECORD")
    end

    if alerts.Durability then
        local percent = alerts.DurabilityPercent
        RefineUI:RegisterEventCallback("UPDATE_INVENTORY_DURABILITY", function()
            CheckDurability(percent)
        end, "Toasts:UPDATE_INVENTORY_DURABILITY")
    end

    if alerts.Rares then
        RefineUI:RegisterEventCallback("VIGNETTE_MINIMAP_UPDATED", OnVignette, "Toasts:VIGNETTE_MINIMAP_UPDATED")
    end

    if alerts.Calendar then
        RefineUI:RegisterEventCallback("CALENDAR_UPDATE_PENDING_INVITES", OnPendingInvites, "Toasts:CALENDAR_UPDATE_PENDING_INVITES")
    end

    if alerts.Vault then
        RefineUI:RegisterEventCallback("WEEKLY_REWARDS_UPDATE", OnWeeklyRewards, "Toasts:WEEKLY_REWARDS_UPDATE")
    end
end
