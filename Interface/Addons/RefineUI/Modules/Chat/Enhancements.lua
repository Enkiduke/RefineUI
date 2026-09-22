----------------------------------------------------------------------------------------
-- Secret-safe chat message enhancements for RefineUI
----------------------------------------------------------------------------------------

local _, RefineUI = ...

local Chat = RefineUI:GetModule("Chat")
if not Chat then
    return
end

----------------------------------------------------------------------------------------
-- Lua / WoW Globals
----------------------------------------------------------------------------------------
local _G = _G
local C_CurrencyInfo = C_CurrencyInfo
local C_Item = C_Item
local C_PetJournal = C_PetJournal
local C_Spell = C_Spell
local ChatFrame_AddMessageEventFilter = ChatFrame_AddMessageEventFilter
local GetAchievementInfo = GetAchievementInfo
local GetNumGroupMembers = GetNumGroupMembers
local GetNumSubgroupMembers = GetNumSubgroupMembers
local GetPlayerInfoByGUID = GetPlayerInfoByGUID
local GetUnitName = GetUnitName
local IsInRaid = IsInRaid
local UnitClass = UnitClass
local UnitExists = UnitExists
local UnitGUID = UnitGUID
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local Ambiguate = Ambiguate
local floor = math.floor
local format = string.format
local ipairs = ipairs
local pairs = pairs
local select = select
local tonumber = tonumber
local type = type

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local LINK_ICON_SIZE = 16
local ROLE_ICON_SIZE = 12
local ROLE_TEXTURE_SIZE = 16
local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t"
local MONEY_PREFIX_COLOR = "|cffffd700"

local LINK_PATTERN = "(\124H.-\124h.-\124h)"
local GENERATED_LINK_ICON_PATTERN = format(
    "\124T[^|]-:%d:%d:0:0:64:64:5:59:5:59\124t(\124H.-\124h.-\124h)",
    LINK_ICON_SIZE,
    LINK_ICON_SIZE
)

local ROLE_TEXTURES = {
    TANK = [[Interface\AddOns\RefineUI\Media\Textures\TANK.blp]],
    HEALER = [[Interface\AddOns\RefineUI\Media\Textures\HEALER.blp]],
    DAMAGER = [[Interface\AddOns\RefineUI\Media\Textures\DAMAGER.blp]],
}

local MESSAGE_EVENTS = {
    "CHAT_MSG_ACHIEVEMENT",
    "CHAT_MSG_BN_WHISPER",
    "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_CHANNEL",
    "CHAT_MSG_COMMUNITIES_CHANNEL",
    "CHAT_MSG_CURRENCY",
    "CHAT_MSG_EMOTE",
    "CHAT_MSG_GUILD",
    "CHAT_MSG_GUILD_ACHIEVEMENT",
    "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_LOOT",
    "CHAT_MSG_MONEY",
    "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_SAY",
    "CHAT_MSG_SKILL",
    "CHAT_MSG_SYSTEM",
    "CHAT_MSG_TEXT_EMOTE",
    "CHAT_MSG_TRADESKILLS",
    "CHAT_MSG_WHISPER",
    "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_YELL",
}

local ROLE_CHAT_EVENTS = {
    CHAT_MSG_INSTANCE_CHAT = true,
    CHAT_MSG_INSTANCE_CHAT_LEADER = true,
    CHAT_MSG_PARTY = true,
    CHAT_MSG_PARTY_LEADER = true,
    CHAT_MSG_RAID = true,
    CHAT_MSG_RAID_LEADER = true,
    CHAT_MSG_RAID_WARNING = true,
}

local ROLE_EVENT_KEYS = {
    GROUP_ROSTER_UPDATE = "ChatEnhancements:GroupRosterUpdate",
    PLAYER_ENTERING_WORLD = "ChatEnhancements:PlayerEnteringWorld",
    PLAYER_ROLES_ASSIGNED = "ChatEnhancements:PlayerRolesAssigned",
}

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
local iconByLinkKey = {}
local roleIconByKey = {}
local roleByGUID = {}
local classByGUID = {}
local roleByName = {}
local classByName = {}
local roleEventsRegistered = false

----------------------------------------------------------------------------------------
-- Shared helpers
----------------------------------------------------------------------------------------
local function ClearTable(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local function ClampColorByte(value)
    if type(value) ~= "number" then
        return 255
    end
    if value < 0 then value = 0 end
    if value > 1 then value = 1 end
    return floor(value * 255 + 0.5)
end

local function EscapePattern(text)
    return text:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
end

----------------------------------------------------------------------------------------
-- Link icons
----------------------------------------------------------------------------------------
local function ResolveLinkTexture(linkType, id)
    local cacheKey = linkType .. ":" .. id
    local cached = iconByLinkKey[cacheKey]
    if cached ~= nil then
        return cached or nil
    end

    local numericID = tonumber(id)
    local texture
    if linkType == "item" then
        texture = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(numericID)
    elseif linkType == "spell" or linkType == "mount" then
        texture = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(numericID)
    elseif linkType == "achievement" then
        texture = GetAchievementInfo and select(10, GetAchievementInfo(numericID))
    elseif linkType == "currency" then
        local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(numericID)
        texture = info and info.iconFileID
    elseif linkType == "battlepet" then
        texture = C_PetJournal and C_PetJournal.GetPetInfoBySpeciesID
            and select(2, C_PetJournal.GetPetInfoBySpeciesID(numericID))
    end

    iconByLinkKey[cacheKey] = texture or false
    return texture
end

local function IconizeLink(fullLink)
    local linkData = fullLink:match("\124H(.-)\124h")
    if not linkData then
        return fullLink
    end

    local linkType, id = linkData:match("^(%a+):(%d+)")
    if not linkType or not id then
        return fullLink
    end

    local texture = ResolveLinkTexture(linkType, id)
    if not texture then
        return fullLink
    end

    return format(
        "\124T%s:%d:%d:0:0:64:64:5:59:5:59\124t%s",
        texture,
        LINK_ICON_SIZE,
        LINK_ICON_SIZE,
        fullLink
    )
end

local function AddLinkIcons(message)
    if not message:find("\124H", 1, true) then
        return message
    end

    local normalized = message:gsub(GENERATED_LINK_ICON_PATTERN, "%1")
    return normalized:gsub(LINK_PATTERN, IconizeLink)
end

----------------------------------------------------------------------------------------
-- Loot money icons
----------------------------------------------------------------------------------------
local GOLD_TEXT = type(GOLD_AMOUNT) == "string" and GOLD_AMOUNT:gsub("%%d", "") or ""
local SILVER_TEXT = type(SILVER_AMOUNT) == "string" and SILVER_AMOUNT:gsub("%%d", "") or ""
local COPPER_TEXT = type(COPPER_AMOUNT) == "string" and COPPER_AMOUNT:gsub("%%d", "") or ""
local LOOT_MONEY_TEMPLATE = type(YOU_LOOT_MONEY) == "string" and YOU_LOOT_MONEY or "You loot %s."
local LOOT_MONEY_PREFIX = (LOOT_MONEY_TEMPLATE:match("^(.-)%%s") or "You loot "):gsub("%s+$", "")
local LOOT_MONEY_PREFIX_PATTERN = EscapePattern(LOOT_MONEY_PREFIX)

local function ReplaceMoneyLabel(message, label, icon)
    if label == "" then
        return message
    end
    return message:gsub(EscapePattern(label), icon)
end

local function AddLootMoneyIcons(message)
    if message:find(GOLD_ICON, 1, true)
        or message:find(SILVER_ICON, 1, true)
        or message:find(COPPER_ICON, 1, true) then
        return message
    end

    local decorated = ReplaceMoneyLabel(message, GOLD_TEXT, GOLD_ICON)
    decorated = ReplaceMoneyLabel(decorated, SILVER_TEXT, SILVER_ICON)
    decorated = ReplaceMoneyLabel(decorated, COPPER_TEXT, COPPER_ICON)

    if LOOT_MONEY_PREFIX ~= "" and decorated:find(LOOT_MONEY_PREFIX, 1, true) then
        decorated = decorated:gsub(
            LOOT_MONEY_PREFIX_PATTERN,
            MONEY_PREFIX_COLOR .. LOOT_MONEY_PREFIX .. ":|r |cffffffff",
            1
        ) .. "|r"
    end
    return decorated
end

----------------------------------------------------------------------------------------
-- Group role icons
----------------------------------------------------------------------------------------
local function IsValidRole(role)
    return role == "TANK" or role == "HEALER" or role == "DAMAGER"
end

local function StoreName(name, role, classToken)
    if not Chat:IsAccessibleString(name) then
        return
    end

    roleByName[name] = role
    classByName[name] = classToken

    if Ambiguate then
        local shortName = Ambiguate(name, "short")
        if Chat:IsAccessibleString(shortName) then
            roleByName[shortName] = role
            classByName[shortName] = classToken
        end
    end
end

local function RecordUnit(unit)
    if not UnitExists(unit) then
        return
    end

    local guid = UnitGUID(unit)
    local role = UnitGroupRolesAssigned(unit)
    local _, classToken = UnitClass(unit)
    if not Chat:IsAccessibleString(guid) or not IsValidRole(role) then
        return
    end

    roleByGUID[guid] = role
    classByGUID[guid] = classToken
    StoreName(GetUnitName(unit, true), role, classToken)
end

local function RefreshRoleCache()
    ClearTable(roleByGUID)
    ClearTable(classByGUID)
    ClearTable(roleByName)
    ClearTable(classByName)

    RecordUnit("player")
    if IsInRaid() then
        local count = GetNumGroupMembers() or 0
        for index = 1, count do
            RecordUnit("raid" .. index)
        end
    else
        local count = GetNumSubgroupMembers() or 0
        for index = 1, count do
            RecordUnit("party" .. index)
        end
    end
end

local function ExtractSenderGUID(...)
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if Chat:IsAccessibleString(value) and value:match("^Player%-%d+%-%x+$") then
            return value
        end
    end
end

local function ResolveRoleAndClass(author, ...)
    local guid = ExtractSenderGUID(...)
    if guid and IsValidRole(roleByGUID[guid]) then
        return roleByGUID[guid], classByGUID[guid]
    end

    if Chat:IsAccessibleString(author) then
        local role = roleByName[author]
        local classToken = classByName[author]
        if not IsValidRole(role) and Ambiguate then
            local shortName = Ambiguate(author, "short")
            if Chat:IsAccessibleString(shortName) then
                role = roleByName[shortName]
                classToken = classByName[shortName]
            end
        end
        if IsValidRole(role) then
            return role, classToken
        end
    end

    if guid and GetPlayerInfoByGUID then
        local _, classToken = GetPlayerInfoByGUID(guid)
        return roleByGUID[guid], classToken
    end
end

local function GetClassColor(classToken)
    local colors = _G.CUSTOM_CLASS_COLORS or _G.RAID_CLASS_COLORS
    local color = colors and colors[classToken]
    if color then
        return color.r, color.g, color.b
    end
    return 1, 1, 1
end

local function BuildRoleIcon(role, classToken)
    local cacheKey = role .. ":" .. (classToken or "")
    local cached = roleIconByKey[cacheKey]
    if cached then
        return cached
    end

    local textures = RefineUI.Media and RefineUI.Media.Textures
    local texture = textures and textures["Role" .. role:sub(1, 1) .. role:sub(2):lower()] or ROLE_TEXTURES[role]
    if not texture then
        return nil
    end

    local r, g, b = GetClassColor(classToken)
    local icon = format(
        "|T%s:%d:%d:0:0:%d:%d:0:%d:0:%d:%d:%d:%d:255|t",
        texture,
        ROLE_ICON_SIZE,
        ROLE_ICON_SIZE,
        ROLE_TEXTURE_SIZE,
        ROLE_TEXTURE_SIZE,
        ROLE_TEXTURE_SIZE,
        ROLE_TEXTURE_SIZE,
        ClampColorByte(r),
        ClampColorByte(g),
        ClampColorByte(b)
    )
    roleIconByKey[cacheKey] = icon
    return icon
end

local function AddRoleIcon(message, author, ...)
    local role, classToken = ResolveRoleAndClass(author, ...)
    if not IsValidRole(role) then
        return message
    end

    local icon = BuildRoleIcon(role, classToken)
    if not icon then
        return message
    end
    return icon .. " " .. message
end

local function SetRoleEventsEnabled(enabled)
    if enabled == roleEventsRegistered then
        return
    end

    roleEventsRegistered = enabled
    if enabled then
        for event, key in pairs(ROLE_EVENT_KEYS) do
            RefineUI:RegisterEventCallback(event, RefreshRoleCache, key)
        end
        RefreshRoleCache()
        return
    end

    for event, key in pairs(ROLE_EVENT_KEYS) do
        RefineUI:OffEvent(event, key)
    end
    ClearTable(roleByGUID)
    ClearTable(classByGUID)
    ClearTable(roleByName)
    ClearTable(classByName)
end

----------------------------------------------------------------------------------------
-- Message filter
----------------------------------------------------------------------------------------
local function EnhanceMessage(_, event, message, author, ...)
    if not Chat:IsAccessibleString(message) or Chat:MessageIsProtected(message) then
        return
    end

    local enhanced = message
    if Chat._chatRoleIconsEnabled and ROLE_CHAT_EVENTS[event] then
        enhanced = AddRoleIcon(enhanced, author, ...)
    end
    if Chat._lootMoneyIconsEnabled and event == "CHAT_MSG_MONEY" then
        enhanced = AddLootMoneyIcons(enhanced)
    end
    if Chat._chatLinkIconsEnabled then
        enhanced = AddLinkIcons(enhanced)
    end

    if enhanced ~= message then
        return false, enhanced, author, ...
    end
end

----------------------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------------------
function Chat:SetupMessageEnhancements()
    local db = self.db or {}
    self._chatLinkIconsEnabled = db.ChatIcons ~= false
    self._lootMoneyIconsEnabled = db.LootIcons ~= false
    self._chatRoleIconsEnabled = db.RoleIcons ~= false

    if not self._messageEnhancementsInstalled and type(ChatFrame_AddMessageEventFilter) == "function" then
        for _, event in ipairs(MESSAGE_EVENTS) do
            ChatFrame_AddMessageEventFilter(event, EnhanceMessage)
        end
        self._messageEnhancementsInstalled = true
    end

    SetRoleEventsEnabled(self._messageEnhancementsInstalled and self._chatRoleIconsEnabled)
end
