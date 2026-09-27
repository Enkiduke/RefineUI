----------------------------------------------------------------------------------------
-- Tooltip Style
-- Description: Tooltip frame styling, line typography, and border-color application.
----------------------------------------------------------------------------------------

local _, RefineUI = ...

----------------------------------------------------------------------------------------
-- Module
----------------------------------------------------------------------------------------
local Tooltip = RefineUI:GetModule("Tooltip")
local Private = Tooltip.Private

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Media = RefineUI.Media
local IsTooltip = Private.IsTooltip
local IsStyledTooltip = Private.IsStyledTooltip
local IsAccessibleTable = Private.IsAccessibleTable
local ReadSafeNumber = Private.ReadSafeNumber
local ReadSafeString = Private.ReadSafeString

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local pairs = pairs
local pcall = pcall
local rawget = rawget
local type = type
local tostring = tostring
local max = math.max
local setmetatable = setmetatable

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local GameTooltipStatusBar = _G.GameTooltipStatusBar
local AddTooltipPostCall = TooltipDataProcessor.AddTooltipPostCall
local ALL_TOOLTIP_TYPES = TooltipDataProcessor.AllTypes
local ITEM_TOOLTIP_TYPE = Enum.TooltipDataType.Item
local UNIT_TOOLTIP_TYPE = Enum.TooltipDataType.Unit

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local BORDER_INSET = 6
local BORDER_EDGE_SIZE = 12

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

Private.BORDER_INSET = BORDER_INSET

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
local borderHosts = setmetatable({}, { __mode = "k" })
local styledLineCounts = setmetatable({}, { __mode = "k" })
local styledMoneyText = setmetatable({}, { __mode = "k" })
local registeredTooltips = setmetatable({}, { __mode = "k" })
-- Data post-calls style the tooltip right before Blizzard shows it; skip that OnShow.
local skipNextOnShow = setmetatable({}, { __mode = "k" })

----------------------------------------------------------------------------------------
-- Typography
----------------------------------------------------------------------------------------
-- Line font strings are created once per index and reused, so each is styled once.
local function StyleLines(tt)
    local numLines = tt:NumLines()
    local styledCount = styledLineCounts[tt] or 0
    if numLines <= styledCount then
        return
    end

    for index = styledCount + 1, numLines do
        local leftLine = tt:GetLeftLine(index)
        if leftLine then
            RefineUI.Font(leftLine, index == 1 and 14 or 12, nil, "OUTLINE")
        end
        local rightLine = tt:GetRightLine(index)
        if rightLine then
            RefineUI.Font(rightLine, 12, nil, "OUTLINE")
        end
    end
    styledLineCounts[tt] = numLines
end

local function StyleMoneyText(fontString)
    if fontString and not styledMoneyText[fontString] then
        RefineUI.Font(fontString, 12, nil, "OUTLINE")
        styledMoneyText[fontString] = true
    end
end

local function StyleMoneyFrames(tt)
    local count = tt.shownMoneyFrames
    local tooltipName = tt:GetName()
    if not count or count <= 0 or not tooltipName then
        return
    end

    for index = 1, count do
        local moneyFrame = _G[tooltipName .. "MoneyFrame" .. index]
        if moneyFrame then
            StyleMoneyText(moneyFrame.PrefixText)
            StyleMoneyText(moneyFrame.SuffixText)
        end
    end
end

local function StyleText(tt)
    StyleLines(tt)
    StyleMoneyFrames(tt)
end

----------------------------------------------------------------------------------------
-- Border
----------------------------------------------------------------------------------------
function Tooltip:SetBackdropStyle(tt)
    local host = borderHosts[tt]
    if not host then
        host = CreateFrame("Frame", nil, tt)
        host:EnableMouse(false)
        RefineUI.SetOutside(host, tt, 0, 0)
        RefineUI.SetTemplate(host, "Transparent")
        RefineUI.CreateBorder(host, BORDER_INSET, BORDER_INSET, BORDER_EDGE_SIZE)
        borderHosts[tt] = host
    end

    local frameLevel = ReadSafeNumber(tt:GetFrameLevel())
    if frameLevel then
        frameLevel = max(0, frameLevel - 1)
        if host:GetFrameLevel() ~= frameLevel then
            host:SetFrameLevel(frameLevel)
        end
    end

    local frameStrata = ReadSafeString(tt:GetFrameStrata())
    if frameStrata and host:GetFrameStrata() ~= frameStrata then
        host:SetFrameStrata(frameStrata)
    end

    if tt.NineSlice then
        tt.NineSlice:SetAlpha(0)
    end

    return host
end

local function SetBorderColor(tt, r, g, b, a)
    local host = Tooltip:SetBackdropStyle(tt)
    if host.borderR == r and host.borderG == g and host.borderB == b and host.borderA == a then
        return
    end

    host.RefineBorder:SetBackdropBorderColor(r, g, b, a)
    host.borderR, host.borderG, host.borderB, host.borderA = r, g, b, a
end

local function SetBorderColorOrDefault(tt, r, g, b, a)
    if r then
        SetBorderColor(tt, r, g, b, a)
    else
        SetBorderColor(tt, Tooltip:GetDefaultTooltipBorderColor())
    end
end

----------------------------------------------------------------------------------------
-- Tooltip Hooks
----------------------------------------------------------------------------------------
local function OnTooltipShow(tt)
    if skipNextOnShow[tt] then
        skipNextOnShow[tt] = nil
        return
    end

    local unitToken = Tooltip:ResolveTooltipUnitToken(tt)
    if unitToken then
        SetBorderColorOrDefault(tt, Tooltip:GetUnitBorderColor(unitToken))
    else
        SetBorderColorOrDefault(tt, Tooltip:GetItemQualityBorderColor(Tooltip:ResolveTooltipItemQuality(tt)))
    end
    StyleText(tt)
end

local function OnTooltipHide(tt)
    skipNextOnShow[tt] = nil
end

local function RegisterTooltipFrame(tt)
    if registeredTooltips[tt] or not IsStyledTooltip(tt) then
        return
    end
    registeredTooltips[tt] = true

    local hookKey = "Tooltip:" .. (tt:GetName() or tostring(tt))
    RefineUI:HookScriptOnce(hookKey .. ":OnShow", tt, "OnShow", OnTooltipShow)
    RefineUI:HookScriptOnce(hookKey .. ":OnHide", tt, "OnHide", OnTooltipHide)

    if tt.CompareHeader then
        RefineUI.StripTextures(tt.CompareHeader)
    end
end

local function RegisterKnownTooltipFrames()
    for index = 1, #KNOWN_TOOLTIP_FRAME_NAMES do
        RegisterTooltipFrame(_G[KNOWN_TOOLTIP_FRAME_NAMES[index]])
    end

    local questScrollFrame = _G.QuestScrollFrame
    if questScrollFrame then
        RegisterTooltipFrame(questScrollFrame.StoryTooltip)
        RegisterTooltipFrame(questScrollFrame.CampaignTooltip)
    end
end

-- Widgets store their userdata at [0]; rawget skips addon metatables that error on lookup.
local function RegisterGlobalTooltip(value)
    if type(rawget(value, 0)) == "userdata" then
        RegisterTooltipFrame(value)
    end
end

local function DiscoverGlobalTooltips()
    for _, value in pairs(_G) do
        if type(value) == "table" then
            pcall(RegisterGlobalTooltip, value)
        end
    end
end

----------------------------------------------------------------------------------------
-- Tooltip Data Post-Calls
----------------------------------------------------------------------------------------
-- Blizzard runs AllTypes post-calls before type-specific ones, then shows the tooltip.
local function OnAnyTooltipData(tt, data)
    if not IsTooltip(tt) then
        return
    end
    if tt.IsEmbedded then
        StyleLines(tt)
        return
    end

    RegisterTooltipFrame(tt)
    skipNextOnShow[tt] = true

    local dataType = IsAccessibleTable(data) and ReadSafeNumber(data.type)
    if dataType == ITEM_TOOLTIP_TYPE then
        return
    end

    local unitToken = Tooltip:ResolveTooltipUnitToken(tt, data)
    if unitToken then
        SetBorderColorOrDefault(tt, Tooltip:GetUnitBorderColor(unitToken))
    elseif dataType == UNIT_TOOLTIP_TYPE then
        SetBorderColorOrDefault(tt, Tooltip:GetUnitBorderColorFromTooltipData(data))
    else
        SetBorderColorOrDefault(tt)
    end
    StyleText(tt)
end

local function OnItemTooltipData(tt, data)
    if not IsStyledTooltip(tt) then
        return
    end

    SetBorderColorOrDefault(tt, Tooltip:GetItemQualityBorderColor(Tooltip:ResolveTooltipItemQuality(tt, data)))
    Tooltip:DispatchItemHandlers(tt, data)
    StyleText(tt)
end

----------------------------------------------------------------------------------------
-- Frame Skins
----------------------------------------------------------------------------------------
local function StyleCloseButton()
    local closeButton = _G.ItemRefTooltip and _G.ItemRefTooltip.CloseButton
    if not closeButton then
        return
    end

    RefineUI.StripTextures(closeButton)

    local closeTexturePath = Media.Textures.Close
    if closeTexturePath then
        local tex = closeButton:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(closeTexturePath)
        tex:SetVertexColor(0.8, 0.8, 0.8, 1)
        RefineUI.Point(tex, "CENTER", -6, -6)
        RefineUI.Size(tex, 12, 12)
        closeButton.Texture = tex
    end

    RefineUI:HookScriptOnce("Tooltip:ItemRefCloseButton:OnEnter", closeButton, "OnEnter", function(self)
        if self.Texture then
            self.Texture:SetVertexColor(1, 0, 0)
        end
    end)
    RefineUI:HookScriptOnce("Tooltip:ItemRefCloseButton:OnLeave", closeButton, "OnLeave", function(self)
        if self.Texture then
            self.Texture:SetVertexColor(0.8, 0.8, 0.8, 1)
        end
    end)
end

local function HideHealthBar()
    if not GameTooltipStatusBar then
        return
    end

    GameTooltipStatusBar:SetScript("OnShow", nil)
    GameTooltipStatusBar:Hide()
    RefineUI:HookOnce("Tooltip:GameTooltipStatusBar:Show", GameTooltipStatusBar, "Show", function(bar)
        bar:Hide()
    end)
end

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------
function Tooltip:InitializeTooltipStyle()
    HideHealthBar()
    StyleCloseButton()

    RegisterKnownTooltipFrames()
    DiscoverGlobalTooltips()
    RefineUI:RegisterEventCallback("ADDON_LOADED", RegisterKnownTooltipFrames, "Tooltip:DiscoverTooltipsOnAddonLoaded")

    RefineUI:HookOnce("Tooltip:SetTooltipMoney", "SetTooltipMoney", function(frame)
        if IsStyledTooltip(frame) then
            StyleMoneyFrames(frame)
        end
    end)

    RefineUI:HookOnce("Tooltip:SharedTooltip_SetBackdropStyle", "SharedTooltip_SetBackdropStyle", function(tt)
        if IsStyledTooltip(tt) then
            RegisterTooltipFrame(tt)
            Tooltip:SetBackdropStyle(tt)
            StyleText(tt)
        end
    end)

    AddTooltipPostCall(ALL_TOOLTIP_TYPES, OnAnyTooltipData)
    AddTooltipPostCall(ITEM_TOOLTIP_TYPE, OnItemTooltipData)
end
