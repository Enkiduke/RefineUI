----------------------------------------------------------------------------------------
-- Chat formatting pipeline for RefineUI
----------------------------------------------------------------------------------------

local _, RefineUI = ...

local Chat = RefineUI:GetModule("Chat")
if not Chat then
    return
end

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local _G = _G
local format = string.format
local gsub = string.gsub
local lower = string.lower
local find = string.find
local match = string.match
local strsub = string.sub
local tonumber = tonumber
local tostring = tostring
local type = type
local pcall = pcall

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local C_ChatInfo = C_ChatInfo
local C_Item = C_Item
local C_Club = C_Club
local ChatFrameUtil = ChatFrameUtil
local ChatTypeInfo = ChatTypeInfo
local RemoveExtraSpaces = RemoveExtraSpaces
local GetPlayerLink = GetPlayerLink
local GetBNPlayerLink = GetBNPlayerLink
local GetPlayerCommunityLink = GetPlayerCommunityLink
local GetBNPlayerCommunityLink = GetBNPlayerCommunityLink
local BetterDate = BetterDate

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local LEVEL_LINK_PATTERN = "|h%[(%d+)%. .-%]|h"
local LEVEL_LINK_REPLACEMENT = "|h[%1]|h"
local ACCESS_CACHE = {
    index = 1,
    byToken = {},
    byID = {},
}
local ITEM_LEVEL_CACHE = {}

local SHORT_CHANNEL_ALIASES = {
    Community = "Comm",
    General = "Gen",
    GuildRecruitment = "GR",
    LookingForGroup = "LFG",
    LocalDefense = "LD",
    Newcomer = "New",
    Services = "Svc",
    Trade = "Trade",
    WorldDefense = "WD",
}

local function IsAccessibleValue(value)
    if RefineUI.IsAccessibleValue then
        return RefineUI:IsAccessibleValue(value)
    end
    return value == nil
end

local function IsAccessibleString(value)
    if RefineUI.IsAccessibleString then
        return RefineUI:IsAccessibleString(value)
    end
    return type(value) == "string"
end

local function SafeFormat(pattern, ...)
    if not IsAccessibleString(pattern) then
        return nil
    end

    local count = select("#", ...)
    for i = 1, count do
        if not IsAccessibleValue(select(i, ...)) then
            return nil
        end
    end

    local ok, formatted = pcall(format, pattern, ...)
    if not ok or not IsAccessibleString(formatted) then
        return nil
    end
    return formatted
end

local function NormalizeTokenPart(value)
    if value == nil then
        return ""
    end
    if not IsAccessibleValue(value) then
        return nil
    end

    local valueType = type(value)
    if valueType ~= "string" and valueType ~= "number" then
        return nil
    end

    local ok, normalized = pcall(tostring, value)
    if not ok or not IsAccessibleString(normalized) then
        return nil
    end
    return normalized
end

local function SimplifyLevelLinks(message)
    if not IsAccessibleString(message) then
        return message
    end
    if not find(message, "|h[", 1, true) then
        return message
    end

    local ok, simplified = pcall(gsub, message, LEVEL_LINK_PATTERN, LEVEL_LINK_REPLACEMENT)
    if ok and IsAccessibleString(simplified) then
        return simplified
    end
    return message
end

local function SafeExternalCall(func, ...)
    if type(func) ~= "function" then
        return nil
    end
    local ok, result = pcall(func, ...)
    if ok then
        return result
    end
    return nil
end

local function AddTimestamp(message, event)
    if not IsAccessibleString(message) or not IsAccessibleString(event) then
        return message
    end
    if strsub(event, 1, 8) ~= "CHAT_MSG" then
        return message
    end

    local getTimestampFormat = ChatFrameUtil and ChatFrameUtil.GetTimestampFormat
    if type(getTimestampFormat) ~= "function" or type(BetterDate) ~= "function" then
        return message
    end

    local timestampFormat = SafeExternalCall(getTimestampFormat)
    if not IsAccessibleString(timestampFormat) or timestampFormat == "" then
        return message
    end

    local timestamp = SafeExternalCall(BetterDate, timestampFormat, time())
    if not IsAccessibleString(timestamp) or timestamp == "" then
        return message
    end

    return timestamp .. message
end

local function StripRealmFromSystemMessage(message)
    if not IsAccessibleString(message) then
        return message
    end

    local realm = type(RefineUI.MyRealm) == "string" and gsub(RefineUI.MyRealm, " ", "") or nil
    if not realm or realm == "" or not find(message, "-" .. realm, 1, true) then
        return message
    end

    local ok, stripped = pcall(gsub, message, "%-" .. realm, "")
    if ok and IsAccessibleString(stripped) then
        return stripped
    end
    return message
end

local function GetCachedItemLevel(itemLink)
    if not IsAccessibleString(itemLink) or itemLink == "" then
        return nil
    end

    local cached = ITEM_LEVEL_CACHE[itemLink]
    if cached ~= nil then
        return cached or nil
    end

    if not C_Item or type(C_Item.GetDetailedItemLevelInfo) ~= "function" then
        ITEM_LEVEL_CACHE[itemLink] = false
        return nil
    end

    local ok, itemLevel = pcall(C_Item.GetDetailedItemLevelInfo, itemLink)
    if ok and type(itemLevel) == "number" and itemLevel > 0 then
        ITEM_LEVEL_CACHE[itemLink] = itemLevel
        return itemLevel
    end

    ITEM_LEVEL_CACHE[itemLink] = false
    return nil
end

local function DecorateItemLinksWithLevel(message)
    if not IsAccessibleString(message) then
        return message
    end
    if not find(message, "|Hitem:", 1, true) then
        return message
    end

    local ok, decorated = pcall(gsub, message, "(|Hitem:[^|]+|h)%[([^%]]+)%](|h)", function(linkPrefix, linkText, linkSuffix)
        if not IsAccessibleString(linkText) or linkText == "" then
            return linkPrefix .. "[" .. (linkText or "") .. "]" .. linkSuffix
        end

        local itemLink = linkPrefix .. "[" .. linkText .. "]" .. linkSuffix
        local itemLevel = GetCachedItemLevel(itemLink)
        if type(itemLevel) ~= "number" then
            return itemLink
        end

        local displayName = linkText
        local legacyLevel, legacyName = match(linkText, "^(%d+)%.%s+(.+)$")
        if legacyName and legacyLevel then
            displayName = legacyName
        else
            local currentName, currentLevel = match(linkText, "^(.+)%s+%((%d+)%)$")
            if currentName and currentLevel then
                displayName = currentName
            elseif match(linkText, "^%d+$") then
                return itemLink
            end
        end

        return linkPrefix .. "[" .. displayName .. " (" .. itemLevel .. ")]" .. linkSuffix
    end)
    if ok and IsAccessibleString(decorated) then
        return decorated
    end
    return message
end

local function ShortenChannelCoreName(channelName)
    if not IsAccessibleString(channelName) or channelName == "" then
        return channelName
    end

    local coreName = channelName
    local dash = find(coreName, " - ", 1, true)
    if dash then
        coreName = strsub(coreName, 1, dash - 1)
    end

    return SHORT_CHANNEL_ALIASES[coreName] or coreName
end

local function ShortenChannelLabel(label)
    if not IsAccessibleString(label) or label == "" then
        return label
    end

    local numberedPrefix, channelName = match(label, "^(%d+%.)%s*(.+)$")
    if numberedPrefix and channelName then
        local shortened = ShortenChannelCoreName(channelName)
        if IsAccessibleString(shortened) and shortened ~= "" then
            return numberedPrefix .. " " .. shortened
        end
        return label
    end

    local shortened = ShortenChannelCoreName(label)
    if IsAccessibleString(shortened) and shortened ~= "" then
        return shortened
    end
    return label
end

local function ShortenRenderedChannels(message)
    if not IsAccessibleString(message) then
        return message
    end
    if not find(message, "|Hchannel:", 1, true) then
        return message
    end

    local ok, shortened = pcall(gsub, message, "(|Hchannel:[^|]+|h%[)([^%]]+)(%]|h)", function(prefix, label, suffix)
        local newLabel = ShortenChannelLabel(label)
        return prefix .. (newLabel or label) .. suffix
    end)
    if ok and IsAccessibleString(shortened) then
        return shortened
    end
    return message
end

local function ResolveDisplayName(coloredName, author)
    if IsAccessibleString(coloredName) and coloredName ~= "" then
        return coloredName
    end
    if IsAccessibleString(author) and author ~= "" then
        return author
    end
    return nil
end

local function ResolveLinkTarget(chatTarget)
    if chatTarget == nil then
        return nil
    end
    if not IsAccessibleValue(chatTarget) then
        return nil
    end
    local targetType = type(chatTarget)
    if targetType == "string" or targetType == "number" then
        return chatTarget
    end
    return nil
end

local function BuildPlayerLink(chatType, author, displayText, lineID, chatGroup, chatTarget, bnetIDAccount)
    if not IsAccessibleString(author) or author == "" then
        return displayText
    end

    local safeTarget = ResolveLinkTarget(chatTarget)

    if chatType == "BN_WHISPER" or chatType == "BN_WHISPER_INFORM" then
        local link = SafeExternalCall(GetBNPlayerLink, author, displayText, bnetIDAccount, lineID, chatGroup, safeTarget)
        return link or displayText
    end

    local link = SafeExternalCall(GetPlayerLink, author, displayText, lineID, chatGroup, safeTarget)
    return link or displayText
end

local function BuildCommunityPlayerLink(author, displayText, bnetIDAccount)
    if not IsAccessibleString(author) or author == "" then
        return displayText
    end

    local getInfo = C_Club and C_Club.GetInfoFromLastCommunityChatLine
    if type(getInfo) ~= "function" then
        return displayText
    end

    local ok, messageInfo, clubID, streamID = pcall(getInfo)
    if not ok or not messageInfo or not messageInfo.messageId then
        return displayText
    end

    local epoch = messageInfo.messageId.epoch
    local position = messageInfo.messageId.position
    if bnetIDAccount and bnetIDAccount ~= 0 then
        return SafeExternalCall(GetBNPlayerCommunityLink, author, displayText, bnetIDAccount, clubID, streamID, epoch, position) or displayText
    end

    return SafeExternalCall(GetPlayerCommunityLink, author, displayText, clubID, streamID, epoch, position) or displayText
end

function Chat:GetAccessID(chatType, chatTarget, chanSender)
    local typePart = NormalizeTokenPart(chatType)
    local targetPart = NormalizeTokenPart(chatTarget)
    local senderPart = NormalizeTokenPart(chanSender)
    if not typePart or targetPart == nil or senderPart == nil then
        return nil
    end

    local ok, loweredType = pcall(lower, typePart)
    if not ok or not IsAccessibleString(loweredType) then
        return nil
    end

    local token = loweredType .. ";;" .. targetPart .. ";;" .. senderPart
    local accessID = ACCESS_CACHE.byToken[token]
    if accessID then
        return accessID
    end

    accessID = ACCESS_CACHE.index
    ACCESS_CACHE.index = ACCESS_CACHE.index + 1
    ACCESS_CACHE.byToken[token] = accessID
    ACCESS_CACHE.byID[accessID] = {
        chatType = chatType,
        chatTarget = chatTarget,
        chanSender = chanSender,
    }

    return accessID
end

function Chat:GetAccessInfo(accessID)
    local info = ACCESS_CACHE.byID[accessID]
    if not info then
        return nil, nil, nil
    end
    return info.chatType, info.chatTarget, info.chanSender
end

function Chat:AddMessageEdits(frame, body, meta)
    if not IsAccessibleString(body) then
        return body
    end

    local edited = body
    local infoID = meta and meta.infoID
    local event = meta and meta.event
    local fromPipeline = meta and meta.fromPipeline == true

    if fromPipeline then
        edited = AddTimestamp(edited, event)
    end

    edited = SimplifyLevelLinks(edited)

    if infoID == (ChatTypeInfo and ChatTypeInfo.SYSTEM and ChatTypeInfo.SYSTEM.id) or event == "CHAT_MSG_SYSTEM" then
        edited = StripRealmFromSystemMessage(edited)
    end

    if not self.db or self.db.ItemLevelLinks ~= false then
        edited = DecorateItemLinksWithLevel(edited)
    end

    if not self.db or self.db.ShortChannels ~= false then
        edited = ShortenRenderedChannels(edited)
    end

    if self.TransformMessageIcons then
        edited = self:TransformMessageIcons(edited)
    end
    if self.TransformRenderedRoleIcons then
        edited = self:TransformRenderedRoleIcons(edited)
    end
    if self.TransformLootMoneyMessage then
        edited = self:TransformLootMoneyMessage(edited, infoID, event)
    end

    return edited
end

function Chat:MessageFormatter(frame, info, chatType, chatGroup, chatTarget, coloredName, message, author, languageName, channelDisplayName, specialFlag, zoneChannelID, channelIndex, lineID, senderGUID, bnetIDAccount, isMobile, hideRaidIcons)
    if not IsAccessibleString(message) then
        return message
    end

    local formattedMessage = message
    formattedMessage = SimplifyLevelLinks(formattedMessage)

    if C_ChatInfo and C_ChatInfo.ReplaceIconAndGroupExpressions then
        local canExpand = ChatFrameUtil and ChatFrameUtil.CanChatGroupPerformExpressionExpansion and ChatFrameUtil.CanChatGroupPerformExpressionExpansion(chatGroup)
        local ok, expanded = pcall(C_ChatInfo.ReplaceIconAndGroupExpressions, formattedMessage, hideRaidIcons, not canExpand)
        if ok and IsAccessibleString(expanded) then
            formattedMessage = expanded
        end
    end

    if type(RemoveExtraSpaces) == "function" then
        local ok, condensed = pcall(RemoveExtraSpaces, formattedMessage)
        if ok and IsAccessibleString(condensed) then
            formattedMessage = condensed
        end
    end

    local showLink = true
    if strsub(chatType, 1, 7) == "MONSTER" or strsub(chatType, 1, 9) == "RAID_BOSS" then
        showLink = false
    else
        local ok, escaped = pcall(gsub, formattedMessage, "%%", "%%%%")
        if ok and IsAccessibleString(escaped) then
            formattedMessage = escaped
        end
    end

    local defaultLanguage = frame and frame.defaultLanguage
    local altLanguage = frame and frame.alternativeDefaultLanguage
    local relevantDefaultLanguage = ((chatType == "SAY" or chatType == "YELL") and altLanguage) or defaultLanguage
    local usingDifferentLanguage = IsAccessibleString(languageName) and languageName ~= "" and languageName ~= relevantDefaultLanguage
    local usingEmote = chatType == "EMOTE" or chatType == "TEXT_EMOTE"

    local displayName = ResolveDisplayName(coloredName, author) or ""
    local linkDisplayText = displayName
    if (usingDifferentLanguage or not usingEmote) and displayName ~= "" then
        local wrapped = SafeFormat("[%s]", displayName)
        if wrapped then
            linkDisplayText = wrapped
        end
    end

    local pflag = ""
    if ChatFrameUtil and ChatFrameUtil.GetPFlag then
        local value = SafeExternalCall(ChatFrameUtil.GetPFlag, specialFlag, zoneChannelID, channelIndex)
        if IsAccessibleString(value) then
            pflag = value
        end
    end

    local speaker = IsAccessibleString(author) and author or ""
    local playerLink = linkDisplayText
    if showLink and speaker ~= "" then
        if chatType == "COMMUNITIES_CHANNEL" then
            playerLink = BuildCommunityPlayerLink(speaker, linkDisplayText, bnetIDAccount)
        else
            playerLink = BuildPlayerLink(chatType, speaker, linkDisplayText, lineID, chatGroup, chatTarget, bnetIDAccount)
        end
    end

    if isMobile and ChatFrameUtil and ChatFrameUtil.GetMobileEmbeddedTexture and info then
        local mobileTexture = SafeExternalCall(ChatFrameUtil.GetMobileEmbeddedTexture, info.r, info.g, info.b)
        if IsAccessibleString(mobileTexture) then
            formattedMessage = mobileTexture .. formattedMessage
        end
    end

    local formatKey = ChatFrameUtil and ChatFrameUtil.GetOutMessageFormatKey and SafeExternalCall(ChatFrameUtil.GetOutMessageFormatKey, chatType)
    if not IsAccessibleString(formatKey) then
        return formattedMessage
    end

    local outMessage
    if usingDifferentLanguage then
        local languageHeader = SafeFormat("[%s] ", languageName) or ""
        local formatString = formatKey .. languageHeader .. formattedMessage
        outMessage = SafeFormat(formatString, pflag .. (showLink and playerLink or speaker))
    elseif not showLink or speaker == "" then
        if chatType == "TEXT_EMOTE" then
            outMessage = formattedMessage
        else
            outMessage = SafeFormat(formatKey .. formattedMessage, pflag .. speaker, speaker)
        end
    else
        if chatType == "EMOTE" then
            outMessage = SafeFormat(formatKey .. formattedMessage, pflag .. playerLink)
        elseif chatType == "TEXT_EMOTE" and speaker ~= "" then
            local ok, replaced = pcall(gsub, formattedMessage, speaker, pflag .. playerLink, 1)
            outMessage = ok and replaced or formattedMessage
        else
            outMessage = SafeFormat(formatKey .. formattedMessage, pflag .. playerLink)
        end
    end

    if not IsAccessibleString(outMessage) then
        outMessage = formattedMessage
    end

    if IsAccessibleString(channelDisplayName) and channelDisplayName ~= "" and channelIndex ~= nil then
        local prefix = SafeFormat("|Hchannel:channel:%s|h[%s]|h ", channelIndex, channelDisplayName)
        if prefix then
            outMessage = prefix .. outMessage
        end
    end

    return outMessage
end
