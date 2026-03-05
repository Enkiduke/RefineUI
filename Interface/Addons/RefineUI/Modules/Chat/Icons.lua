----------------------------------------------------------------------------------------
-- ChatIcons for RefineUI (Direct Port)
-- Description: Adds icons to items, spells, etc., in chat links
----------------------------------------------------------------------------------------

local _, RefineUI = ...

local Chat = RefineUI:GetModule("Chat")

----------------------------------------------------------------------------------------
-- Cache Globals
----------------------------------------------------------------------------------------
local format = string.format
local tonumber = tonumber
local select = select
local type = type
local C_Item = C_Item
local C_Spell = C_Spell
local C_CurrencyInfo = C_CurrencyInfo
local C_PetJournal = C_PetJournal
local GetAchievementInfo = GetAchievementInfo

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local ICON_SIZE = 16
local ICON_LINK_PATTERN = "(\124H.-\124h.-\124h)"
local HYPERLINK_MARKER = "\124H"

local function IconizeLink(fullLink)
    local linkData = fullLink:match("\124H(.-)\124h")
    if not linkData then
        return fullLink
    end

    local linkType, id = linkData:match("^(%a+):(%d+)")
    local texture

    if linkType == "item" then
        texture = C_Item.GetItemIconByID(tonumber(id))
    elseif linkType == "spell" then
        texture = C_Spell.GetSpellTexture(tonumber(id))
    elseif linkType == "achievement" then
        texture = select(10, GetAchievementInfo(tonumber(id)))
    elseif linkType == "currency" then
        local info = C_CurrencyInfo.GetCurrencyInfo(tonumber(id))
        if info then
            texture = info.iconFileID
        end
    elseif linkType == "mount" then
        texture = C_Spell.GetSpellTexture(tonumber(id))
    elseif linkType == "battlepet" then
        local speciesID = tonumber(id)
        if speciesID then
            texture = select(2, C_PetJournal.GetPetInfoBySpeciesID(speciesID))
        end
    end

    if texture then
        return format("\124T%s:%d:%d:0:0:64:64:5:59:5:59\124t%s", texture, ICON_SIZE, ICON_SIZE, fullLink)
    end

    return fullLink
end

function Chat:TransformMessageIcons(message)
    if not self._chatIconsEnabled then
        return message
    end
    if type(message) ~= "string" then
        return message
    end
    if not message:find(HYPERLINK_MARKER, 1, true) then
        return message
    end

    return message:gsub(ICON_LINK_PATTERN, IconizeLink)
end

function Chat:SetupIcons()
    local enabled = self.db and self.db.ChatIcons
    if enabled == nil and RefineUI.Config and RefineUI.Config.Chat then
        enabled = RefineUI.Config.Chat.ChatIcons
    end
    self._chatIconsEnabled = enabled ~= false
end
