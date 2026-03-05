----------------------------------------------------------------------------------------
--	LootIcons (RefineUI)
--	Description: Replaces "You loot..." money text with icons and colors.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local Chat = RefineUI:GetModule("Chat")

----------------------------------------------------------------------------------------
-- Cache Globals
----------------------------------------------------------------------------------------
local gsub = string.gsub
local type = type
local ChatTypeInfo = ChatTypeInfo

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local GOLD_ICON   = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t"
local _moneyChatTypeID

local GOLD_TEXT   = GOLD_AMOUNT:gsub("%%d", "")
local SILVER_TEXT = SILVER_AMOUNT:gsub("%%d", "")
local COPPER_TEXT = COPPER_AMOUNT:gsub("%%d", "")

local function EscapePattern(text)
    return gsub(text, "([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
end

local LOOT_MONEY_TEMPLATE = _G.YOU_LOOT_MONEY or "You loot %s."
local LOOT_MONEY_PREFIX = (LOOT_MONEY_TEMPLATE:match("^(.-)%%s") or "You loot "):gsub("%s+$", "")
local LOOT_MONEY_PREFIX_PATTERN = EscapePattern(LOOT_MONEY_PREFIX)

local function IsMoneyMessage(infoID, event)
    if event == "CHAT_MSG_MONEY" then
        return true
    end
    return _moneyChatTypeID and infoID and infoID == _moneyChatTypeID
end

function Chat:TransformLootMoneyMessage(message, infoID, event)
    if not self._lootMoneyIconsEnabled then
        return message
    end
    if type(message) ~= "string" then
        return message
    end
    if not IsMoneyMessage(infoID, event) then
        return message
    end
    if not message:find(LOOT_MONEY_PREFIX, 1, true) then
        return message
    end

    local msg = message:gsub(GOLD_TEXT, GOLD_ICON)
    msg = msg:gsub(SILVER_TEXT, SILVER_ICON)
    msg = msg:gsub(COPPER_TEXT, COPPER_ICON)
    msg = msg:gsub(",", "")
    msg = msg:gsub(LOOT_MONEY_PREFIX_PATTERN, "|cffffd700" .. LOOT_MONEY_PREFIX .. ":|r |cffffffff", 1) .. "|r"
    return msg
end

function Chat:SetupLootIcons()
    self._lootMoneyIconsEnabled = true
    local moneyInfo = ChatTypeInfo and ChatTypeInfo.MONEY
    _moneyChatTypeID = moneyInfo and moneyInfo.id
end
