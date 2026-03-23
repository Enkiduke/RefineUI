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
local gsub = string.gsub
local find = string.find
local match = string.match
local strsub = string.sub
local type = type
local pcall = pcall
local format = string.format

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local C_Item = C_Item
local ChatTypeInfo = ChatTypeInfo

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local LEVEL_LINK_PATTERN = "|h%[(%d+)%. .-%]|h"
local LEVEL_LINK_REPLACEMENT = "|h[%1]|h"
local ITEM_LEVEL_CACHE = {}

local function canChangeMessage(arg1, id)
    if id and arg1 == "" then
        return id
    end
end

----------------------------------------------------------------------------------------
-- Helpers
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

function Chat:NotSecretValue(value)
    if self:IsAccessibleValue(value) then
        return value
    end
    return nil
end

function Chat:MessageIsProtected(message)
    if self:IsSecretValue(message) or type(message) ~= "string" then
        return true
    end

    local ok, protected = pcall(function()
        return message ~= gsub(message, "(:?|?)|K(.-)|k", canChangeMessage)
    end)
    if not ok then
        return true
    end

    return protected
end

local function IsAccessibleString(value)
    return Chat:IsAccessibleString(value)
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

----------------------------------------------------------------------------------------
-- Rendered Line Edits
----------------------------------------------------------------------------------------
function Chat:AddMessageEdits(frame, body, meta)
    if not IsAccessibleString(body) then
        return body
    end

    local edited = SimplifyLevelLinks(body)
    local infoID = meta and meta.infoID
    local event = meta and meta.event

    if infoID == (ChatTypeInfo and ChatTypeInfo.SYSTEM and ChatTypeInfo.SYSTEM.id) or event == "CHAT_MSG_SYSTEM" then
        edited = StripRealmFromSystemMessage(edited)
    end

    if not self.db or self.db.ItemLevelLinks ~= false then
        edited = DecorateItemLinksWithLevel(edited)
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
