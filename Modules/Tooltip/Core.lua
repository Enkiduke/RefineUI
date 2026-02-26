----------------------------------------------------------------------------------------
-- Tooltip Core
-- Description: Shared safety helpers, registries, constants, and common data helpers.
----------------------------------------------------------------------------------------

local _, RefineUI = ...

----------------------------------------------------------------------------------------
-- Module
----------------------------------------------------------------------------------------
local Tooltip = RefineUI:GetModule("Tooltip")
if not Tooltip then
    return
end

local Private = Tooltip.Private or {}
Tooltip.Private = Private
Tooltip.ItemHandlers = Tooltip.ItemHandlers or {}

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config
local Media = RefineUI.Media
local Colors = RefineUI.Colors
local Locale = RefineUI.Locale

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local pairs = pairs
local tonumber = tonumber
local tostring = tostring
local type = type
local pcall = pcall
local floor = math.floor
local setmetatable = setmetatable
local issecretvalue = _G.issecretvalue
local canaccessvalue = _G.canaccessvalue

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local GameTooltip = _G.GameTooltip
local AddTooltipPostCall = TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
local C_Item = _G.C_Item
local ColorManager = _G.ColorManager
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
local GetMouseFoci = GetMouseFoci
local UnitExists = UnitExists
local UnitIsPlayer = UnitIsPlayer
local UnitHasVehicleUI = UnitHasVehicleUI
local UnitClass = UnitClass
local UnitReaction = UnitReaction
local UnitCanAttack = UnitCanAttack
local UnitCanAssist = UnitCanAssist
local GameTooltip_UnitColor = _G.GameTooltip_UnitColor
local TooltipUtil = _G.TooltipUtil
local UnitTokenFromGUID = _G.UnitTokenFromGUID
local TOOLTIP_DATA_TYPE = Enum and Enum.TooltipDataType

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local TOOLTIP_SKIN_STATE_REGISTRY = "Tooltip:SkinState"
local TOOLTIP_DISCOVER_DEBOUNCE_KEY = "Tooltip:DiscoverGlobalTooltips"
local TOOLTIP_BORDER_INSET = 6
local TOOLTIP_BORDER_EDGE_SIZE = 12
local TOOLTIP_COMPARISON_GAP = 8
local TOOLTIP_COMPARISON_HOOK_KEY = "Tooltip:TooltipComparisonManager:AnchorShoppingTooltips"
local TOOLTIP_COMPARE_ITEM_HOOK_KEY = "Tooltip:GameTooltip_ShowCompareItem:ComparisonGap"
local UNIT_TOOLTIP_FALLBACK_TOKENS = { "mouseover", "softenemy", "softfriend", "softinteract" }

local KNOWN_TOOLTIP_FRAME_NAMES = {
    "GameTooltip",
    "EmbeddedItemTooltip",
    "GameSmallHeaderTooltip",
    "ItemRefTooltip",
    "ItemRefShoppingTooltip1",
    "ItemRefShoppingTooltip2",
    "FriendsTooltip",
    "ShoppingTooltip1",
    "ShoppingTooltip2",
    "ReputationParagonTooltip",
    "WarCampaignTooltip",
    "QuickKeybindTooltip",
    "LibDBIconTooltip",
    "BattlePetTooltip",
    "SettingsTooltip",
}

local AUGMENTABLE_TOOLTIP_NAMES = {
    GameTooltip = true,
    ItemRefTooltip = true,
    ItemRefShoppingTooltip1 = true,
    ItemRefShoppingTooltip2 = true,
    ShoppingTooltip1 = true,
    ShoppingTooltip2 = true,
}

----------------------------------------------------------------------------------------
-- Shared Helpers
----------------------------------------------------------------------------------------
local function IsSecret(value)
    if not issecretvalue then
        return false
    end

    local ok, secret = pcall(issecretvalue, value)
    if not ok then
        return true
    end

    return secret == true
end

local function ReadSafeBoolean(value)
    if IsSecret(value) then
        return nil
    end
    if type(value) == "boolean" then
        return value
    end
    return nil
end

local function ReadSafeNumber(value)
    if IsSecret(value) then
        return nil
    end
    if type(value) == "number" then
        return value
    end
    return nil
end

local function ReadSafeString(value)
    if IsSecret(value) then
        return nil
    end
    if type(value) == "string" then
        return value
    end
    return nil
end

local function CanAccessObject(value)
    local valueType = type(value)
    if valueType ~= "table" and valueType ~= "userdata" then
        return false
    end
    if IsSecret(value) then
        return false
    end
    if canaccessvalue then
        local ok, accessible = pcall(canaccessvalue, value)
        if not ok or accessible ~= true then
            return false
        end
    end
    return true
end

local function SafeGetField(tbl, key)
    local valueType = type(tbl)
    if valueType ~= "table" and valueType ~= "userdata" then
        return nil, false
    end
    if IsSecret(tbl) then
        return nil, false
    end
    if canaccessvalue then
        local okAccess, canAccess = pcall(canaccessvalue, tbl)
        if not okAccess or canAccess ~= true then
            return nil, false
        end
    end

    local ok, value = pcall(function()
        return tbl[key]
    end)
    if not ok then
        return nil, false
    end

    return value, true
end

local function IsForbiddenFrame(value)
    local valueType = type(value)
    if valueType ~= "table" and valueType ~= "userdata" then
        return false
    end
    if not CanAccessObject(value) then
        return true
    end

    local isForbidden, okField = SafeGetField(value, "IsForbidden")
    if not okField then
        return true
    end
    if type(isForbidden) ~= "function" then
        return false
    end

    local ok, forbidden = pcall(isForbidden, value)
    return ok and forbidden == true
end

local function SafeObjectMethodCall(object, methodName, ...)
    local objectType = type(object)
    if (objectType ~= "table" and objectType ~= "userdata") or not CanAccessObject(object) then
        return false
    end
    if IsForbiddenFrame(object) then
        return false
    end

    local method, okField = SafeGetField(object, methodName)
    if not okField or type(method) ~= "function" then
        return false
    end

    return pcall(method, object, ...)
end

local function GetTooltipIdentifier(tooltip)
    if not CanAccessObject(tooltip) then
        return "InaccessibleTooltip"
    end
    if IsForbiddenFrame(tooltip) then
        return "ForbiddenTooltip"
    end

    local getName, okField = SafeGetField(tooltip, "GetName")
    if okField and type(getName) == "function" then
        local ok, tooltipName = pcall(getName, tooltip)
        local hasAccessibleName = true
        if canaccessvalue then
            local okAccess, canAccess = pcall(canaccessvalue, tooltipName)
            hasAccessibleName = okAccess and canAccess == true
        end
        if ok
            and type(tooltipName) == "string"
            and tooltipName ~= ""
            and not IsSecret(tooltipName)
            and hasAccessibleName
        then
            return tooltipName
        end
    end

    return tostring(tooltip)
end

local function IsGameTooltipFrame(frame)
    if not CanAccessObject(frame) then
        return false
    end
    if IsForbiddenFrame(frame) then
        return false
    end

    local isObjectType, okField = SafeGetField(frame, "IsObjectType")
    if not okField or type(isObjectType) ~= "function" then
        return false
    end

    local ok, isTooltipFrame = pcall(isObjectType, frame, "GameTooltip")
    return ok and isTooltipFrame == true
end

local function ResolveBorderColorComponents(colorTable)
    local valueType = type(colorTable)
    if valueType ~= "table" and valueType ~= "userdata" then
        return nil
    end
    if not CanAccessObject(colorTable) then
        return nil
    end

    local getRGB, okGetRGB = SafeGetField(colorTable, "GetRGB")
    if okGetRGB and type(getRGB) == "function" then
        local okRGB, r, g, b = pcall(getRGB, colorTable)
        r = okRGB and ReadSafeNumber(r) or nil
        g = okRGB and ReadSafeNumber(g) or nil
        b = okRGB and ReadSafeNumber(b) or nil
        if r and g and b then
            local getAlpha, okGetAlpha = SafeGetField(colorTable, "GetAlpha")
            if okGetAlpha and type(getAlpha) == "function" then
                local okAlpha, alpha = pcall(getAlpha, colorTable)
                alpha = okAlpha and ReadSafeNumber(alpha) or nil
                return r, g, b, alpha or 1
            end
            return r, g, b, 1
        end
    end

    local function ReadColorField(key)
        local value, okValue = SafeGetField(colorTable, key)
        if not okValue then
            return nil
        end
        return ReadSafeNumber(value)
    end

    local r = ReadColorField("r") or ReadColorField(1)
    local g = ReadColorField("g") or ReadColorField(2)
    local b = ReadColorField("b") or ReadColorField(3)
    local a = ReadColorField("a") or ReadColorField(4) or 1
    if not r or not g or not b then
        return nil
    end

    return r, g, b, a
end

local function NormalizeItemQuality(quality)
    quality = ReadSafeNumber(quality)
    if not quality then
        return nil
    end

    quality = tonumber(quality)
    if not quality then
        return nil
    end

    quality = floor(quality)
    if quality < 0 then
        return nil
    end

    return quality
end

local function ValidateUnitToken(token)
    token = ReadSafeString(token)
    if not token or token == "" then
        return nil
    end
    if ReadSafeBoolean(UnitExists(token)) ~= true then
        return nil
    end
    return token
end

local function ResolveUnitTokenFromGUID(guid)
    if type(UnitTokenFromGUID) ~= "function" then
        return nil
    end

    guid = ReadSafeString(guid)
    if not guid or guid == "" then
        return nil
    end

    local ok, unitToken = pcall(UnitTokenFromGUID, guid)
    if not ok then
        return nil
    end

    return unitToken
end

local function ResolveUnitTokenFromData(data)
    if not CanAccessObject(data) or type(data) ~= "table" then
        return nil
    end

    local dataUnitToken, okDataUnitToken = SafeGetField(data, "unitToken")
    if okDataUnitToken and dataUnitToken then
        return dataUnitToken
    end

    local guid, okGuid = SafeGetField(data, "guid")
    if okGuid then
        return ResolveUnitTokenFromGUID(guid)
    end

    return nil
end

----------------------------------------------------------------------------------------
-- Core Initialization
----------------------------------------------------------------------------------------
function Tooltip:InitializeTooltipCore()
    RefineUI:CreateDataRegistry(TOOLTIP_SKIN_STATE_REGISTRY, "k")

    Private.lineCache = Private.lineCache or {}
    Private.styledFontStrings = Private.styledFontStrings or setmetatable({}, { __mode = "k" })
    Private.postCallRegistry = Private.postCallRegistry or {}
    Private.itemHandlers = Private.itemHandlers or {}
    Tooltip.ItemHandlers = Private.itemHandlers
end

----------------------------------------------------------------------------------------
-- Shared Interface
----------------------------------------------------------------------------------------
function Tooltip:IsSecretValueSafe(value)
    return IsSecret(value)
end

function Tooltip:ReadSafeBoolean(value)
    return ReadSafeBoolean(value)
end

function Tooltip:ReadSafeNumber(value)
    return ReadSafeNumber(value)
end

function Tooltip:ReadSafeString(value)
    return ReadSafeString(value)
end

function Tooltip:CanAccessObjectSafe(value)
    return CanAccessObject(value)
end

function Tooltip:SafeGetField(value, key)
    return SafeGetField(value, key)
end

function Tooltip:IsForbiddenFrameSafe(frame)
    return IsForbiddenFrame(frame)
end

function Tooltip:IsGameTooltipFrameSafe(frame)
    return IsGameTooltipFrame(frame)
end

function Tooltip:SafeObjectMethodCall(object, methodName, ...)
    return SafeObjectMethodCall(object, methodName, ...)
end

function Tooltip:BuildTooltipHookKey(tooltip, qualifier)
    return "Tooltip:" .. GetTooltipIdentifier(tooltip) .. ":" .. qualifier
end

function Tooltip:GetTooltipSkinState(tooltip)
    if not CanAccessObject(tooltip) then
        return nil
    end
    if IsForbiddenFrame(tooltip) then
        return nil
    end

    local state = RefineUI:RegistryGet(TOOLTIP_SKIN_STATE_REGISTRY, tooltip)
    if type(state) ~= "table" then
        state = {}
        RefineUI:RegistrySet(TOOLTIP_SKIN_STATE_REGISTRY, tooltip, nil, state)
    end

    return state
end

function Tooltip:GetTooltipNameSafe(tooltip)
    local getName, okField = SafeGetField(tooltip, "GetName")
    if not okField or type(getName) ~= "function" then
        return nil
    end
    local ok, tooltipName = pcall(getName, tooltip)
    if not ok then
        return nil
    end
    return ReadSafeString(tooltipName)
end

function Tooltip:GetCachedLine(tooltip, index)
    local cache = Private.lineCache or {}
    Private.lineCache = cache

    local tooltipName = self:GetTooltipNameSafe(tooltip)
    if not tooltipName then
        return nil
    end

    local key = tooltipName .. index
    if not cache[key] then
        cache[key] = _G[tooltipName .. "TextLeft" .. index]
    end
    return cache[key]
end

function Tooltip:GetStyledFontStringRegistry()
    return Private.styledFontStrings
end

function Tooltip:GetLineCache()
    return Private.lineCache
end

function Tooltip:GetKnownTooltipFrameNames()
    return KNOWN_TOOLTIP_FRAME_NAMES
end

function Tooltip:IsAugmentableTooltipFrame(tooltip)
    if not IsGameTooltipFrame(tooltip) then
        return false
    end

    local tooltipName = self:GetTooltipNameSafe(tooltip)
    if not tooltipName then
        return false
    end

    return AUGMENTABLE_TOOLTIP_NAMES[tooltipName] == true
end

function Tooltip:IsEmbeddedTooltipFrame(tooltip)
    if not IsGameTooltipFrame(tooltip) then
        return false
    end

    local isEmbedded, okEmbedded = SafeGetField(tooltip, "IsEmbedded")
    if okEmbedded and ReadSafeBoolean(isEmbedded) == true then
        return true
    end

    local tooltipName = self:GetTooltipNameSafe(tooltip)
    if tooltipName and tooltipName:find("ItemTooltipTooltip", 1, true) then
        return true
    end

    return false
end

function Tooltip:GetTooltipDiscoverDebounceKey()
    return TOOLTIP_DISCOVER_DEBOUNCE_KEY
end

function Tooltip:GetTooltipBorderParams()
    return TOOLTIP_BORDER_INSET, TOOLTIP_BORDER_EDGE_SIZE
end

function Tooltip:GetTooltipComparisonGap()
    return TOOLTIP_COMPARISON_GAP
end

function Tooltip:GetTooltipComparisonHookKey()
    return TOOLTIP_COMPARISON_HOOK_KEY
end

function Tooltip:GetTooltipCompareItemHookKey()
    return TOOLTIP_COMPARE_ITEM_HOOK_KEY
end

function Tooltip:GetTooltipDataType(data)
    if not CanAccessObject(data) or type(data) ~= "table" then
        return nil
    end

    local tooltipType, okType = SafeGetField(data, "type")
    if not okType then
        return nil
    end

    return ReadSafeNumber(tooltipType)
end

function Tooltip:AddTooltipPostCallOnce(key, tooltipDataType, fn)
    if type(key) ~= "string" or key == "" then
        return false, "invalid_key"
    end
    if type(fn) ~= "function" then
        return false, "invalid_callback"
    end
    if Private.postCallRegistry[key] then
        return false, "already_registered"
    end
    if type(AddTooltipPostCall) ~= "function" then
        local processor = _G.TooltipDataProcessor
        local addPostCall = processor and processor.AddTooltipPostCall
        if type(addPostCall) == "function" then
            AddTooltipPostCall = addPostCall
        end
    end
    if type(AddTooltipPostCall) ~= "function" then
        return false, "postcall_unavailable"
    end

    AddTooltipPostCall(tooltipDataType, fn)
    Private.postCallRegistry[key] = true
    return true
end

function Tooltip:RegisterItemHandler(name, handler)
    if type(name) ~= "string" or name == "" then
        return false, "invalid_name"
    end
    if type(handler) ~= "function" then
        return false, "invalid_handler"
    end
    if Tooltip.ItemHandlers[name] then
        return false, "already_registered"
    end

    Tooltip.ItemHandlers[name] = handler
    return true
end

function Tooltip:DispatchItemHandlers(tooltip, data)
    if not IsGameTooltipFrame(tooltip) then
        return
    end
    if not CanAccessObject(data) or type(data) ~= "table" then
        return
    end

    local itemID, okItemID = SafeGetField(data, "id")
    if not okItemID or not itemID then
        return
    end

    for handlerName, handler in pairs(Tooltip.ItemHandlers) do
        local ok, err = pcall(handler, tooltip, data)
        if not ok then
            Tooltip:Error("Item handler '" .. tostring(handlerName) .. "' failed: " .. tostring(err))
        end
    end
end

----------------------------------------------------------------------------------------
-- Border Color Resolution
----------------------------------------------------------------------------------------
function Tooltip:GetDefaultTooltipBorderColor()
    local borderColor = Config and Config.General and Config.General.BorderColor
    if type(borderColor) == "table" then
        local r = ReadSafeNumber(borderColor[1])
        local g = ReadSafeNumber(borderColor[2])
        local b = ReadSafeNumber(borderColor[3])
        local a = ReadSafeNumber(borderColor[4]) or 1
        if r and g and b then
            return r, g, b, a
        end
    end

    return 0.6, 0.6, 0.6, 1
end

function Tooltip:GetItemQualityBorderColor(quality)
    quality = NormalizeItemQuality(quality)
    if not quality then
        return nil
    end

    if ColorManager and type(ColorManager.GetColorDataForItemQuality) == "function" then
        local colorData = ColorManager.GetColorDataForItemQuality(quality)
        local color = colorData and colorData.color
        if color and type(color.GetRGB) == "function" then
            local r, g, b = color:GetRGB()
            if ReadSafeNumber(r) and ReadSafeNumber(g) and ReadSafeNumber(b) then
                return r, g, b, 1
            end
        end
    end

    local qualityColor = Colors and Colors.Quality and Colors.Quality[quality]
    if qualityColor then
        local r, g, b, a = ResolveBorderColorComponents(qualityColor)
        if r and g and b then
            return r, g, b, a
        end
    end

    if type(_G.GetItemQualityColor) == "function" then
        local r, g, b = _G.GetItemQualityColor(quality)
        if ReadSafeNumber(r) and ReadSafeNumber(g) and ReadSafeNumber(b) then
            return r, g, b, 1
        end
    end

    local fallback = _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality]
    return ResolveBorderColorComponents(fallback)
end

function Tooltip:ResolveTooltipItemQuality(tooltip, data)
    if CanAccessObject(data) and type(data) == "table" then
        local quality = NormalizeItemQuality(data.quality)
        if quality then
            return quality
        end

        quality = self:GetItemQualityFromLink(ReadSafeString(data.hyperlink))
        if quality then
            return quality
        end

        local guid = ReadSafeString(data.guid)
        if guid and C_Item and type(C_Item.GetItemLinkByGUID) == "function" then
            local itemLink = C_Item.GetItemLinkByGUID(guid)
            quality = self:GetItemQualityFromLink(itemLink)
            if quality then
                return quality
            end
        end

        quality = self:GetItemQualityFromID(data.id)
        if quality then
            return quality
        end
    end

    if CanAccessObject(tooltip) and not IsForbiddenFrame(tooltip) then
        local getItem, okGetItem = SafeGetField(tooltip, "GetItem")
        if okGetItem and type(getItem) == "function" then
            local okItem, _, itemLink, itemID = pcall(getItem, tooltip)
            if okItem then
                local quality = self:GetItemQualityFromLink(ReadSafeString(itemLink))
                if quality then
                    return quality
                end

                quality = self:GetItemQualityFromID(itemID)
                if quality then
                    return quality
                end
            end
        end
    end

    return nil
end

function Tooltip:GetItemQualityFromLink(itemLink)
    if type(itemLink) ~= "string" or itemLink == "" then
        return nil
    end
    if IsSecret(itemLink) then
        return nil
    end
    if not GetItemInfo then
        return nil
    end

    local _, _, quality = GetItemInfo(itemLink)
    return NormalizeItemQuality(quality)
end

function Tooltip:GetItemQualityFromID(itemID)
    itemID = ReadSafeNumber(itemID)
    if not itemID or not GetItemInfo then
        return nil
    end

    local _, _, quality = GetItemInfo(itemID)
    if not quality and C_Item and type(C_Item.RequestLoadItemDataByID) == "function" then
        C_Item.RequestLoadItemDataByID(itemID)
    end

    return NormalizeItemQuality(quality)
end

function Tooltip:ResolveBorderColorComponents(colorTable)
    return ResolveBorderColorComponents(colorTable)
end

function Tooltip:GetUnitBorderColorFromTooltipData(data)
    if not CanAccessObject(data) or type(data) ~= "table" then
        return nil
    end

    local unitToken = ValidateUnitToken(ResolveUnitTokenFromData(data))
    if unitToken then
        local r, g, b, a = self:GetUnitBorderColor(unitToken)
        if r and g and b then
            return r, g, b, a
        end
    end

    local lines, okLines = SafeGetField(data, "lines")
    if not okLines or type(lines) ~= "table" then
        return nil
    end

    for lineIndex = 1, #lines do
        local lineData = lines[lineIndex]
        if CanAccessObject(lineData) then
            local lineUnitToken, okLineUnitToken = SafeGetField(lineData, "unitToken")
            lineUnitToken = okLineUnitToken and ValidateUnitToken(lineUnitToken) or nil
            if lineUnitToken then
                local r, g, b, a = self:GetUnitBorderColor(lineUnitToken)
                if r and g and b then
                    return r, g, b, a
                end
            end

            local leftColor, okLeftColor = SafeGetField(lineData, "leftColor")
            if okLeftColor and leftColor then
                local r, g, b, a = ResolveBorderColorComponents(leftColor)
                if r and g and b then
                    return r, g, b, a
                end
            end
        end
    end

    return nil
end

function Tooltip:GetUnitBorderColor(unitToken)
    unitToken = ReadSafeString(unitToken)
    if not unitToken or unitToken == "" then
        return nil
    end

    local isPlayer = ReadSafeBoolean(UnitIsPlayer(unitToken)) == true
    local hasVehicleUI = ReadSafeBoolean(UnitHasVehicleUI(unitToken)) == true
    if isPlayer and not hasVehicleUI then
        local _, classFile = UnitClass(unitToken)
        classFile = ReadSafeString(classFile)
        if classFile then
            local classColor = Colors and Colors.Class and Colors.Class[classFile]
            local r, g, b, a = ResolveBorderColorComponents(classColor)
            if r and g and b then
                return r, g, b, a
            end
        end
    end

    local reaction = ReadSafeNumber(UnitReaction(unitToken, "player"))
    if reaction then
        local reactionColor = Colors and Colors.Reaction and Colors.Reaction[reaction]
        local r, g, b, a = ResolveBorderColorComponents(reactionColor)
        if r and g and b then
            return r, g, b, a
        end
    end

    if type(GameTooltip_UnitColor) == "function" then
        local ok, r, g, b = pcall(GameTooltip_UnitColor, unitToken)
        r = ok and ReadSafeNumber(r) or nil
        g = ok and ReadSafeNumber(g) or nil
        b = ok and ReadSafeNumber(b) or nil
        if r and g and b then
            return r, g, b, 1
        end
    end

    local canAttack = UnitCanAttack and ReadSafeBoolean(UnitCanAttack("player", unitToken))
    local canBeAttacked = UnitCanAttack and ReadSafeBoolean(UnitCanAttack(unitToken, "player"))
    local canAssist = UnitCanAssist and ReadSafeBoolean(UnitCanAssist("player", unitToken))

    local fallbackReactionIndex = nil
    if canAttack == true then
        fallbackReactionIndex = (canBeAttacked == true) and 2 or 4
    elseif canAssist == true then
        fallbackReactionIndex = 5
    end

    local fallbackReaction = fallbackReactionIndex and Colors and Colors.Reaction and Colors.Reaction[fallbackReactionIndex]
    return ResolveBorderColorComponents(fallbackReaction)
end

function Tooltip:ResolveTooltipUnitToken(tooltip, data)
    if not IsGameTooltipFrame(tooltip) then
        return nil
    end

    local isUnitTooltip = false
    if TOOLTIP_DATA_TYPE and TOOLTIP_DATA_TYPE.Unit then
        local dataType = self:GetTooltipDataType(data)
        if dataType == TOOLTIP_DATA_TYPE.Unit then
            isUnitTooltip = true
        else
            local okIsUnitType, tooltipIsUnitType = SafeObjectMethodCall(tooltip, "IsTooltipType", TOOLTIP_DATA_TYPE.Unit)
            isUnitTooltip = okIsUnitType and ReadSafeBoolean(tooltipIsUnitType) == true
        end
    end

    local unitToken = nil
    local getUnit, okGetUnit = SafeGetField(tooltip, "GetUnit")
    if okGetUnit and type(getUnit) == "function" then
        local okGet, _, token = pcall(getUnit, tooltip)
        if okGet then
            unitToken = ValidateUnitToken(token)
        end
    end

    if not unitToken and isUnitTooltip and TooltipUtil and type(TooltipUtil.GetDisplayedUnit) == "function" then
        local okDisplayed, _, displayedUnit, guid = pcall(TooltipUtil.GetDisplayedUnit, tooltip)
        if okDisplayed then
            unitToken = ValidateUnitToken(displayedUnit)
            if not unitToken then
                unitToken = ValidateUnitToken(ResolveUnitTokenFromGUID(guid))
            end
        end
    end

    if not unitToken then
        unitToken = ValidateUnitToken(ResolveUnitTokenFromData(data))
    end

    if not unitToken and tooltip == GameTooltip and isUnitTooltip then
        local foci = GetMouseFoci()
        if not IsSecret(foci) then
            local focusRegion = (type(foci) == "table") and foci[1] or nil
            if CanAccessObject(focusRegion) and not IsForbiddenFrame(focusRegion) then
                local getAttribute, okGetAttribute = SafeGetField(focusRegion, "GetAttribute")
                if okGetAttribute and type(getAttribute) == "function" then
                    local okAttr, focusUnit = pcall(getAttribute, focusRegion, "unit")
                    if okAttr then
                        unitToken = ValidateUnitToken(focusUnit)
                    end
                end
            end
        end
    end

    if not unitToken and tooltip == GameTooltip and isUnitTooltip then
        for tokenIndex = 1, #UNIT_TOOLTIP_FALLBACK_TOKENS do
            local fallbackToken = UNIT_TOOLTIP_FALLBACK_TOKENS[tokenIndex]
            local resolved = ValidateUnitToken(fallbackToken)
            if resolved then
                unitToken = resolved
                break
            end
        end
    end

    return ValidateUnitToken(unitToken)
end
