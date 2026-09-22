----------------------------------------------------------------------------------------
-- Chat formatting helpers for RefineUI
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
local find = string.find
local format = string.format
local gsub = string.gsub
local match = string.match
local pairs = pairs
local pcall = pcall
local tonumber = tonumber
local type = type
local C_ChallengeMode = C_ChallengeMode

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local KEYSTONE_MAP_NAME_CACHE = {}
local ORIGINAL_CHAT_FORMATS = {}
local APPLIED_CHAT_FORMATS = {}

local SHORT_CHAT_FORMATS = {
    CHAT_GUILD_GET = { key = "Guild", fallback = "G", channel = "guild" },
    CHAT_OFFICER_GET = { key = "Officer", fallback = "O", channel = "officer" },
    CHAT_PARTY_GET = { key = "Party", fallback = "P", channel = "party" },
    CHAT_PARTY_LEADER_GET = { key = "PartyLeader", fallback = "PL", channel = "party", leader = true },
    CHAT_PARTY_GUIDE_GET = { key = "PartyGuide", fallback = "PG", channel = "party", leader = true },
    CHAT_RAID_GET = { key = "Raid", fallback = "R", channel = "raid" },
    CHAT_RAID_LEADER_GET = { key = "RaidLeader", fallback = "RL", channel = "raid", leader = true },
    CHAT_RAID_WARNING_GET = { key = "RaidWarning", fallback = "RW", channel = "raidwarning", warning = true },
    CHAT_INSTANCE_CHAT_GET = { key = "InstanceChat", fallback = "I", channel = "instance" },
    CHAT_INSTANCE_CHAT_LEADER_GET = { key = "InstanceChatLeader", fallback = "IL", channel = "instance", leader = true },
    CHAT_SAY_GET = { key = "SayShort", fallback = "S", channel = "say" },
    CHAT_YELL_GET = { key = "YellShort", fallback = "Y", channel = "yell" },
    CHAT_WHISPER_GET = { key = "Whisper", fallback = "W" },
    CHAT_WHISPER_INFORM_GET = { key = "WhisperInform", fallback = "W2" },
    CHAT_BN_WHISPER_GET = { key = "BNWhisper", fallback = "BN" },
    CHAT_BN_WHISPER_INFORM_GET = { key = "BNWhisperInform", fallback = "BN2" },
}

local LEADER_ICON = "|TInterface\\GroupFrame\\UI-Group-LeaderIcon:0|t"
local RAID_WARNING_ICON = "|TInterface\\GroupFrame\\UI-GROUP-MAINASSISTICON:0|t"

----------------------------------------------------------------------------------------
-- Secret-value helpers
----------------------------------------------------------------------------------------
function Chat:IsSecretValue(value)
    if RefineUI.IsSecretValue then
        return RefineUI:IsSecretValue(value)
    end
    return false
end

function Chat:IsAccessibleValue(value)
    if RefineUI.IsAccessibleValue then
        return RefineUI:IsAccessibleValue(value)
    end
    return true
end

function Chat:IsAccessibleString(value)
    if RefineUI.IsAccessibleString then
        return RefineUI:IsAccessibleString(value)
    end
    return type(value) == "string"
end

function Chat:MessageIsProtected(message)
    if not self:IsAccessibleString(message) then
        return true
    end

    return find(message, "|K", 1, true) ~= nil
end


----------------------------------------------------------------------------------------
-- Fixed chat type abbreviations
----------------------------------------------------------------------------------------
local function BuildShortChatFormat(definition)
    local locale = RefineUI.Locale and RefineUI.Locale.Chat or {}
    local label = locale[definition.key] or definition.fallback
    if definition.leader then
        label = label .. LEADER_ICON
    elseif definition.warning then
        label = label .. RAID_WARNING_ICON
    end

    if definition.channel then
        return format("|Hchannel:%s|h[%s]|h %%s: ", definition.channel, label)
    end

    return format("[%s] %%s: ", label)
end

function Chat:ApplyShortChannelFormats()
    local enabled = self.db and self.db.ShortChannels ~= false

    for globalName, definition in pairs(SHORT_CHAT_FORMATS) do
        if ORIGINAL_CHAT_FORMATS[globalName] == nil then
            ORIGINAL_CHAT_FORMATS[globalName] = _G[globalName] or false
        end

        if enabled and type(ORIGINAL_CHAT_FORMATS[globalName]) == "string" then
            local abbreviated = BuildShortChatFormat(definition)
            _G[globalName] = abbreviated
            APPLIED_CHAT_FORMATS[globalName] = abbreviated
        elseif APPLIED_CHAT_FORMATS[globalName] then
            if _G[globalName] == APPLIED_CHAT_FORMATS[globalName] then
                _G[globalName] = ORIGINAL_CHAT_FORMATS[globalName] or nil
            end
            APPLIED_CHAT_FORMATS[globalName] = nil
        end
    end
end

----------------------------------------------------------------------------------------
-- Keystone link decoration
----------------------------------------------------------------------------------------
local function GetKeystoneMapName(challengeModeID)
    local cached = KEYSTONE_MAP_NAME_CACHE[challengeModeID]
    if cached then
        return cached
    end

    if not C_ChallengeMode or type(C_ChallengeMode.GetMapUIInfo) ~= "function" then
        return nil
    end

    local ok, name = pcall(C_ChallengeMode.GetMapUIInfo, challengeModeID)
    if ok and Chat:IsAccessibleString(name) and name ~= "" then
        KEYSTONE_MAP_NAME_CACHE[challengeModeID] = name
        return name
    end
end

function Chat:DecorateKeystoneLinks(message)
    if not self:IsAccessibleString(message) or not find(message, "|Hkeystone:", 1, true) then
        return message
    end

    local ok, decorated = pcall(gsub, message, "(|Hkeystone:[^|]+|h)(%[[^%]]*%])(|h)", function(linkPrefix, linkText, linkSuffix)
        local challengeModeID, level = match(linkPrefix, "^|Hkeystone:%d+:(%d+):(%d+)")
        challengeModeID = tonumber(challengeModeID)
        level = tonumber(level)
        if not challengeModeID or challengeModeID <= 0 or not level or level <= 0 then
            return linkPrefix .. linkText .. linkSuffix
        end

        local dungeonName = GetKeystoneMapName(challengeModeID)
        if not dungeonName then
            return linkPrefix .. linkText .. linkSuffix
        end

        return linkPrefix .. "[" .. dungeonName .. " +" .. level .. "]" .. linkSuffix
    end)
    if ok and self:IsAccessibleString(decorated) then
        return decorated
    end
    return message
end
