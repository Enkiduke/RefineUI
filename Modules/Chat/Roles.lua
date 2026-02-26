----------------------------------------------------------------------------------------
-- ChatRoleIcons for RefineUI
-- Description: Adds class-colored role icons to party/raid/instance chat messages.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Chat = RefineUI:GetModule("Chat")

----------------------------------------------------------------------------------------
-- Cache Globals
----------------------------------------------------------------------------------------
local _G = _G
local format = string.format
local gsub = string.gsub
local strfind = string.find
local type = type
local pairs = pairs
local floor = math.floor
local issecretvalue = _G.issecretvalue
local canaccessvalue = _G.canaccessvalue
local UnitExists = UnitExists
local UnitGUID = UnitGUID
local UnitClass = UnitClass
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local GetNumGroupMembers = GetNumGroupMembers
local GetNumSubgroupMembers = GetNumSubgroupMembers
local IsInRaid = IsInRaid
local GetPlayerInfoByGUID = GetPlayerInfoByGUID
local GetUnitName = GetUnitName
local Ambiguate = Ambiguate

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local ROLE_ICON_SIZE = 12
local ROLE_TEXTURE_SIZE = 16
local ROLE_TEXTURES = {
    TANK = [[Interface\AddOns\RefineUI\Media\Textures\TANK.blp]],
    HEALER = [[Interface\AddOns\RefineUI\Media\Textures\HEALER.blp]],
    DAMAGER = [[Interface\AddOns\RefineUI\Media\Textures\DAMAGER.blp]],
}

local ROLE_EVENT_KEYS = {
    roster = "ChatRoles:GroupRosterUpdate",
    roles = "ChatRoles:PlayerRolesAssigned",
    world = "ChatRoles:PlayerEnteringWorld",
}

local roleByGUID = {}
local classByGUID = {}
local roleByName = {}
local classByName = {}
local _roleEventsRegistered = false
local ALLOWED_CHANNEL_REFS = {
    "|Hchannel:PARTY|h",
    "|Hchannel:PARTY_LEADER|h",
    "|Hchannel:PARTY_GUIDE|h",
    "|Hchannel:INSTANCE_CHAT|h",
    "|Hchannel:INSTANCE_CHAT_LEADER|h",
    "|Hchannel:RAID|h",
    "|Hchannel:RAID_LEADER|h",
    "|Hchannel:RAID_WARNING|h",
}

local function IsAccessibleString(value)
    if type(value) ~= "string" then
        return false
    end
    if issecretvalue and issecretvalue(value) then
        return false
    end
    if canaccessvalue and not canaccessvalue(value) then
        return false
    end
    return true
end

local function GetMediaRoleTexture(role)
    local textures = RefineUI.Media and RefineUI.Media.Textures
    if role == "TANK" then
        return (textures and textures.RoleTank) or ROLE_TEXTURES.TANK
    elseif role == "HEALER" then
        return (textures and textures.RoleHealer) or ROLE_TEXTURES.HEALER
    elseif role == "DAMAGER" then
        return (textures and textures.RoleDamager) or ROLE_TEXTURES.DAMAGER
    end
end

local function NormalizeName(name)
    if not IsAccessibleString(name) then
        return nil
    end
    return Ambiguate(name, "none")
end

local function GetClassColor(classToken)
    if type(classToken) ~= "string" or classToken == "" then
        return nil
    end

    local blizzColors = _G.CUSTOM_CLASS_COLORS or _G.RAID_CLASS_COLORS
    local blizzColor = blizzColors and blizzColors[classToken]
    if blizzColor then
        return blizzColor.r, blizzColor.g, blizzColor.b
    end

    local classColors = RefineUI.Colors and RefineUI.Colors.Class
    local color = classColors and classColors[classToken]
    if color then
        return color.r or color[1], color.g or color[2], color.b or color[3]
    end

    return nil
end

local function ClampColorChannel(v)
    if type(v) ~= "number" then
        return 255
    end
    if v < 0 then v = 0 end
    if v > 1 then v = 1 end
    return floor(v * 255 + 0.5)
end

local function BuildRoleIcon(role, classToken)
    local texture = GetMediaRoleTexture(role)
    if type(texture) ~= "string" or texture == "" then
        return nil
    end

    local r, g, b = GetClassColor(classToken)
    if not r or not g or not b then
        r, g, b = 1, 1, 1
    end

    local r255 = ClampColorChannel(r)
    local g255 = ClampColorChannel(g)
    local b255 = ClampColorChannel(b)

    return format(
        "|T%s:%d:%d:0:0:%d:%d:0:%d:0:%d:%d:%d:%d:255|t",
        texture,
        ROLE_ICON_SIZE,
        ROLE_ICON_SIZE,
        ROLE_TEXTURE_SIZE,
        ROLE_TEXTURE_SIZE,
        ROLE_TEXTURE_SIZE,
        ROLE_TEXTURE_SIZE,
        r255,
        g255,
        b255
    )
end

local function IsValidRole(role)
    return role == "TANK" or role == "HEALER" or role == "DAMAGER"
end

local function WipeCache()
    for k in pairs(roleByGUID) do
        roleByGUID[k] = nil
    end
    for k in pairs(classByGUID) do
        classByGUID[k] = nil
    end
    for k in pairs(roleByName) do
        roleByName[k] = nil
    end
    for k in pairs(classByName) do
        classByName[k] = nil
    end
end

local function RecordUnit(unit)
    if type(unit) ~= "string" or not UnitExists(unit) then
        return
    end

    local guid = UnitGUID(unit)
    local role = UnitGroupRolesAssigned(unit)
    local _, classToken = UnitClass(unit)

    if not IsAccessibleString(guid) or not IsValidRole(role) then
        return
    end

    roleByGUID[guid] = role
    classByGUID[guid] = classToken

    local fullName = GetUnitName(unit, true)
    local normalized = NormalizeName(fullName)
    if normalized then
        roleByName[normalized] = role
        classByName[normalized] = classToken
    end
end

local function RefreshRoleCache()
    WipeCache()

    RecordUnit("player")

    if IsInRaid() then
        local count = GetNumGroupMembers() or 0
        for i = 1, count do
            RecordUnit("raid" .. i)
        end
    else
        local count = GetNumSubgroupMembers() or 0
        for i = 1, count do
            RecordUnit("party" .. i)
        end
    end
end

local function ExtractGuidFromArgs(...)
    local n = select("#", ...)
    for i = 1, n do
        local v = select(i, ...)
        if IsAccessibleString(v) and v:match("^Player%-%d+%-%x+$") then
            return v
        end
    end
    return nil
end

local function HasAnyRoleIconPrefix(message)
    if type(message) ~= "string" then
        return false
    end

    local textures = RefineUI.Media and RefineUI.Media.Textures
    local tank = (textures and textures.RoleTank) or ROLE_TEXTURES.TANK
    local healer = (textures and textures.RoleHealer) or ROLE_TEXTURES.HEALER
    local damager = (textures and textures.RoleDamager) or ROLE_TEXTURES.DAMAGER

    return message:find(tank, 1, true) or message:find(healer, 1, true) or message:find(damager, 1, true)
end

local function IsSpeechRenderedLine(message)
    if type(message) ~= "string" or message == "" then
        return false
    end

    local L = (RefineUI.Locale and RefineUI.Locale.Chat) or {}
    local sayTag = "[" .. (L.SayShort or "S") .. "]"
    local yellTag = "[" .. (L.YellShort or "Y") .. "]"
    if strfind(message, sayTag, 1, true) or strfind(message, yellTag, 1, true) then
        return true
    end

    local sayTail = type(CHAT_SAY_GET) == "string" and CHAT_SAY_GET or ""
    local yellTail = type(CHAT_YELL_GET) == "string" and CHAT_YELL_GET or ""
    if sayTail ~= "" then
        sayTail = gsub(sayTail, "%%s", "")
        sayTail = gsub(sayTail, "^%s+", "")
        sayTail = gsub(sayTail, "%s+$", "")
    end
    if yellTail ~= "" then
        yellTail = gsub(yellTail, "%%s", "")
        yellTail = gsub(yellTail, "^%s+", "")
        yellTail = gsub(yellTail, "%s+$", "")
    end

    if sayTail ~= "" and strfind(message, sayTail, 1, true) then
        return true
    end
    if yellTail ~= "" and strfind(message, yellTail, 1, true) then
        return true
    end
    return false
end

local function IsAllowedRenderedLine(message)
    if type(message) ~= "string" then
        return false
    end

    for i = 1, #ALLOWED_CHANNEL_REFS do
        if strfind(message, ALLOWED_CHANNEL_REFS[i], 1, true) then
            return true
        end
    end

    return IsSpeechRenderedLine(message)
end

local function ResolveRoleAndClass(author, ...)
    local guid = ExtractGuidFromArgs(...)
    if guid then
        local role = roleByGUID[guid]
        local classToken = classByGUID[guid]
        if IsValidRole(role) then
            return role, classToken
        end

        local _, englishClass = GetPlayerInfoByGUID(guid)
        if type(englishClass) == "string" and englishClass ~= "" then
            classByGUID[guid] = englishClass
            classToken = englishClass
        end
        if IsValidRole(roleByGUID[guid]) then
            return roleByGUID[guid], classToken
        end
    end

    local normalized = NormalizeName(author)
    if normalized then
        local role = roleByName[normalized]
        local classToken = classByName[normalized]
        if IsValidRole(role) then
            return role, classToken
        end
    end

    return nil, nil
end

function Chat:TransformMessageRoleIcons(message, event, author, ...)

    return message
end

local function ExtractAuthorFromRenderedPlayerLink(link)
    if type(link) ~= "string" then
        return nil
    end
    return link:match("|Hplayer:([^:|]+)")
end

local function InsertIconInsidePlayerLink(playerLink, icon)
    if type(playerLink) ~= "string" or type(icon) ~= "string" or icon == "" then
        return playerLink
    end

    local prefix, nameText, suffix = playerLink:match("^(.-|h%[)%s*(.-)(%]|h)$")
    if prefix and nameText and suffix then
        return prefix .. icon .. nameText .. suffix
    end


    return icon .. playerLink
end

function Chat:TransformRenderedRoleIcons(message)
    if not self._chatRoleIconsEnabled then
        return message
    end
    if type(message) ~= "string" then
        return message
    end
    if not IsAllowedRenderedLine(message) then
        return message
    end
    if HasAnyRoleIconPrefix(message) then
        return message
    end

    local prefix, playerLink, suffix = message:match("^(.-)(|Hplayer:[^|]+|h%[[^%]]+%]|h)(.*)$")
    if type(playerLink) ~= "string" or playerLink == "" then
        return message
    end

    local author = ExtractAuthorFromRenderedPlayerLink(playerLink)
    if not IsAccessibleString(author) then
        return message
    end

    local role, classToken = ResolveRoleAndClass(author)
    if not IsValidRole(role) then
        return message
    end

    local icon = BuildRoleIcon(role, classToken)
    if type(icon) ~= "string" or icon == "" then
        return message
    end

    local playerLinkWithIcon = InsertIconInsidePlayerLink(playerLink, icon)
    return prefix .. playerLinkWithIcon .. suffix
end

function Chat:SetupRoleIcons()
    local enabled = self.db and self.db.RoleIcons
    if enabled == nil and RefineUI.Config and RefineUI.Config.Chat then
        enabled = RefineUI.Config.Chat.RoleIcons
    end
    self._chatRoleIconsEnabled = enabled ~= false

    if not _roleEventsRegistered then
        _roleEventsRegistered = true
        RefineUI:RegisterEventCallback("GROUP_ROSTER_UPDATE", RefreshRoleCache, ROLE_EVENT_KEYS.roster)
        RefineUI:RegisterEventCallback("PLAYER_ROLES_ASSIGNED", RefreshRoleCache, ROLE_EVENT_KEYS.roles)
        RefineUI:RegisterEventCallback("PLAYER_ENTERING_WORLD", RefreshRoleCache, ROLE_EVENT_KEYS.world)
    end

    RefreshRoleCache()
end
