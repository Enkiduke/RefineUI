----------------------------------------------------------------------------------------
-- Tooltip Style
-- Description: Tooltip frame styling, line typography, and border-color application.
----------------------------------------------------------------------------------------

local _, RefineUI = ...

----------------------------------------------------------------------------------------
-- Module
----------------------------------------------------------------------------------------
local Tooltip = RefineUI:GetModule("Tooltip")
if not Tooltip then
    return
end

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
local max = math.max
local pcall = pcall
local select = select

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local GameTooltipStatusBar = _G.GameTooltipStatusBar
local ALL_TOOLTIP_TYPES = TooltipDataProcessor and TooltipDataProcessor.AllTypes
local TOOLTIP_DATA_TYPE = Enum and Enum.TooltipDataType

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local TOOLTIP_POSTCALL_ALL_TYPES_KEY = "Tooltip:PostCall:AllTypes"
local TOOLTIP_POSTCALL_ITEM_KEY = "Tooltip:PostCall:Item"
local TOOLTIP_DISCOVER_ON_ADDON_LOADED_KEY = "Tooltip:DiscoverTooltipsOnAddonLoaded"
local EMBEDDED_ICON_BORDER_STYLE = {
    inset = 4,
    edgeSize = 12,
    forceRefresh = true,
}

----------------------------------------------------------------------------------------
-- Styling
----------------------------------------------------------------------------------------
local function StyleTooltipLines(tt, includeEmbedded)
    if not Tooltip:IsGameTooltipFrameSafe(tt) then
        return
    end
    if not includeEmbedded and Tooltip:IsEmbeddedTooltipFrame(tt) then
        return
    end
    if type(tt.NumLines) ~= "function" then
        return
    end

    local numLines = tt:NumLines()
    if not numLines or numLines <= 0 then
        return
    end

    local tooltipName = Tooltip:GetTooltipNameSafe(tt)
    if not tooltipName then
        return
    end

    local styledFontStrings = Tooltip:GetStyledFontStringRegistry()
    local lineCache = Tooltip:GetLineCache()
    for lineIndex = 1, numLines do
        local leftLine = Tooltip:GetCachedLine(tt, lineIndex)
        if leftLine and not styledFontStrings[leftLine] then
            RefineUI.Font(leftLine, lineIndex == 1 and 14 or 12, nil, "OUTLINE")
            styledFontStrings[leftLine] = true
        end

        local rightLineKey = tooltipName .. "TextRight" .. lineIndex
        local rightLine = lineCache[rightLineKey] or _G[rightLineKey]
        if rightLine then
            lineCache[rightLineKey] = rightLine
            if not styledFontStrings[rightLine] then
                RefineUI.Font(rightLine, 12, nil, "OUTLINE")
                styledFontStrings[rightLine] = true
            end
        end
    end
end

local function GetEmbeddedIconBorderHost(tt, ownerFrame, iconRegion)
    local state = Tooltip:GetTooltipSkinState(tt)
    if not state then
        return nil
    end

    local host = state.embeddedIconBorderHost
    if not host or type(host.SetPoint) ~= "function" then
        host = CreateFrame("Frame", nil, ownerFrame)
        host._disableBagStatusIcon = true
        if host.EnableMouse then
            host:EnableMouse(false)
        end
        state.embeddedIconBorderHost = host
    end

    if type(host.GetParent) == "function" and host:GetParent() ~= ownerFrame then
        host:SetParent(ownerFrame)
    end

    if type(ownerFrame.GetFrameLevel) == "function" then
        host:SetFrameLevel(ownerFrame:GetFrameLevel() + 1)
    end
    if type(ownerFrame.GetFrameStrata) == "function" then
        host:SetFrameStrata(ownerFrame:GetFrameStrata())
    end

    host:ClearAllPoints()
    host:SetAllPoints(iconRegion)
    return host
end

local function ClearEmbeddedItemIconBorder(tt)
    local state = Tooltip:GetTooltipSkinState(tt)
    local host = state and state.embeddedIconBorderHost
    if not host then
        return
    end

    if host.RefineUIBorderItemLevel then
        host.RefineUIBorderItemLevel:Hide()
    end
    host:Hide()
end

local function ApplyEmbeddedItemIconBorder(tt, data)
    if not Tooltip:IsEmbeddedTooltipFrame(tt) then
        return
    end

    local borders = RefineUI:GetModule("Borders")
    if not borders or type(borders.ApplyItemBorder) ~= "function" then
        return
    end

    local okOwner, ownerFrame = Tooltip:SafeObjectMethodCall(tt, "GetOwner")
    if not okOwner or not Tooltip:CanAccessObjectSafe(ownerFrame) or Tooltip:IsForbiddenFrameSafe(ownerFrame) then
        ClearEmbeddedItemIconBorder(tt)
        return
    end

    local iconRegion, okIcon = Tooltip:SafeGetField(ownerFrame, "Icon")
    if not okIcon or not Tooltip:CanAccessObjectSafe(iconRegion) then
        ClearEmbeddedItemIconBorder(tt)
        return
    end

    local itemLink = nil
    local itemID = nil

    if Tooltip:CanAccessObjectSafe(data) and type(data) == "table" then
        local dataLink, okDataLink = Tooltip:SafeGetField(data, "hyperlink")
        local dataID, okDataID = Tooltip:SafeGetField(data, "id")
        itemLink = okDataLink and Tooltip:ReadSafeString(dataLink) or nil
        itemID = okDataID and Tooltip:ReadSafeNumber(dataID) or nil
    end

    if not itemLink or not itemID then
        local okItem, _, tooltipItemLink, tooltipItemID = Tooltip:SafeObjectMethodCall(tt, "GetItem")
        if okItem then
            itemLink = itemLink or Tooltip:ReadSafeString(tooltipItemLink)
            itemID = itemID or Tooltip:ReadSafeNumber(tooltipItemID)
        end
    end

    if not itemID then
        local ownerItemID, okOwnerItemID = Tooltip:SafeGetField(ownerFrame, "itemID")
        if okOwnerItemID then
            itemID = Tooltip:ReadSafeNumber(ownerItemID)
        end
    end
    if not itemLink then
        local ownerItemLink, okOwnerItemLink = Tooltip:SafeGetField(ownerFrame, "itemLink")
        if okOwnerItemLink then
            itemLink = Tooltip:ReadSafeString(ownerItemLink)
        end
    end

    if not itemLink and not itemID then
        ClearEmbeddedItemIconBorder(tt)
        return
    end

    local host = GetEmbeddedIconBorderHost(tt, ownerFrame, iconRegion)
    if not host then
        ClearEmbeddedItemIconBorder(tt)
        return
    end

    borders:ApplyItemBorder(host, itemLink, itemID, EMBEDDED_ICON_BORDER_STYLE)
    if host.RefineUIBorderItemLevel then
        host.RefineUIBorderItemLevel:Hide()
    end
    host:Show()
end

local function TryApplyItemQualityBorderOnShow(tt)
    if not Tooltip:IsGameTooltipFrameSafe(tt) then
        return false, false
    end

    local getItem, okGetItem = Tooltip:SafeGetField(tt, "GetItem")
    if not okGetItem or type(getItem) ~= "function" then
        return false, false
    end

    local okItem, _, itemLink, itemID = pcall(getItem, tt)
    if not okItem then
        return false, false
    end

    local safeItemLink = Tooltip:ReadSafeString(itemLink)
    local safeItemID = Tooltip:ReadSafeNumber(itemID)
    if not safeItemLink and not safeItemID then
        return false, false
    end

    local quality = Tooltip:GetItemQualityFromLink(safeItemLink)
    if not quality and safeItemID then
        quality = Tooltip:GetItemQualityFromID(safeItemID)
    end
    if not quality then
        return true, false
    end

    local r, g, b, a = Tooltip:GetItemQualityBorderColor(quality)
    if not r or not g or not b then
        return true, false
    end

    Tooltip:SetTooltipBorderColor(tt, r, g, b, a)
    return true, true
end

function Tooltip:SetBackdropStyle(tt)
    if not Tooltip:IsGameTooltipFrameSafe(tt) or Tooltip:IsEmbeddedTooltipFrame(tt) then
        return
    end

    local state = Tooltip:GetTooltipSkinState(tt)
    if not state then
        return
    end

    local borderHost = state.borderHost
    if not borderHost or type(borderHost.SetPoint) ~= "function" then
        borderHost = CreateFrame("Frame", nil, tt)
        if borderHost.EnableMouse then
            borderHost:EnableMouse(false)
        end
        state.borderHost = borderHost
    end

    borderHost:SetFrameLevel(max(0, tt:GetFrameLevel() - 1))
    borderHost:SetFrameStrata(tt:GetFrameStrata())
    RefineUI.SetOutside(borderHost, tt, 0, 0)

    local borderInset, borderEdgeSize = Tooltip:GetTooltipBorderParams()
    RefineUI.SetTemplate(borderHost, "Transparent")
    RefineUI.CreateBorder(borderHost, borderInset, borderInset, borderEdgeSize)

    if borderHost.Show then
        borderHost:Show()
    end

    local nineSlice, okNineSlice = Tooltip:SafeGetField(tt, "NineSlice")
    if okNineSlice and nineSlice then
        Tooltip:SafeObjectMethodCall(nineSlice, "SetAlpha", 0)
    end

    StyleTooltipLines(tt)
end

function Tooltip:SetTooltipBorderColor(tt, r, g, b, a)
    if not Tooltip:IsGameTooltipFrameSafe(tt) or Tooltip:IsEmbeddedTooltipFrame(tt) then
        return
    end

    Tooltip:SetBackdropStyle(tt)

    local state = Tooltip:GetTooltipSkinState(tt)
    local borderHost = state and state.borderHost
    local border = borderHost and (borderHost.RefineBorder or borderHost.border)
    if border and border.SetBackdropBorderColor then
        border:SetBackdropBorderColor(r, g, b, a or 1)
    end
end

function Tooltip:ResetTooltipBorderColor(tt)
    local r, g, b, a = Tooltip:GetDefaultTooltipBorderColor()
    Tooltip:SetTooltipBorderColor(tt, r, g, b, a)
end

function Tooltip:ApplyItemQualityBorderColor(tt, data)
    local quality = Tooltip:ResolveTooltipItemQuality(tt, data)
    local r, g, b, a = Tooltip:GetItemQualityBorderColor(quality)
    if r and g and b then
        Tooltip:SetTooltipBorderColor(tt, r, g, b, a)
    else
        Tooltip:ResetTooltipBorderColor(tt)
    end
end

function Tooltip:ApplyUnitBorderColor(tt, unitToken)
    local r, g, b, a = Tooltip:GetUnitBorderColor(unitToken)
    if r and g and b then
        Tooltip:SetTooltipBorderColor(tt, r, g, b, a)
    else
        Tooltip:ResetTooltipBorderColor(tt)
    end
end

function Tooltip:ApplyUnitBorderColorFromData(tt, data)
    local r, g, b, a = Tooltip:GetUnitBorderColorFromTooltipData(data)
    if r and g and b then
        Tooltip:SetTooltipBorderColor(tt, r, g, b, a)
        return true
    end
    return false
end

function Tooltip:RegisterTooltipFrame(tt)
    if not Tooltip:IsGameTooltipFrameSafe(tt) or Tooltip:IsEmbeddedTooltipFrame(tt) then
        return
    end

    Tooltip:SetBackdropStyle(tt)

    local state = Tooltip:GetTooltipSkinState(tt)
    if state and not state.onShowHooked then
        local hookKey = Tooltip:BuildTooltipHookKey(tt, "OnShow")
        local ok, reason = RefineUI:HookScriptOnce(hookKey, tt, "OnShow", function(frame)
            Tooltip:SetBackdropStyle(frame)

            local unitToken = Tooltip:ResolveTooltipUnitToken(frame)
            if not unitToken then
                local okPrimaryData, primaryData = Tooltip:SafeObjectMethodCall(frame, "GetPrimaryTooltipData")
                if okPrimaryData then
                    unitToken = Tooltip:ResolveTooltipUnitToken(frame, primaryData)
                end
            end
            if unitToken then
                Tooltip:ApplyUnitBorderColor(frame, unitToken)
                return
            end

            local hasItemTooltip = false
            hasItemTooltip = select(1, TryApplyItemQualityBorderOnShow(frame))
            if hasItemTooltip then
                return
            end

            Tooltip:ResetTooltipBorderColor(frame)
        end)
        if ok or reason == "already_hooked" then
            state.onShowHooked = true
        end
    end

    local compareHeader, okCompare = Tooltip:SafeGetField(tt, "CompareHeader")
    if okCompare and Tooltip:CanAccessObjectSafe(compareHeader) then
        if not Tooltip:SafeObjectMethodCall(compareHeader, "StripTexture") then
            Tooltip:SafeObjectMethodCall(compareHeader, "StripTextures")
        end
    end
end

function Tooltip:DiscoverGlobalTooltips()
    for _, globalValue in pairs(_G) do
        if Tooltip:IsGameTooltipFrameSafe(globalValue) then
            Tooltip:RegisterTooltipFrame(globalValue)
        end
    end

    local questScrollFrame = _G.QuestScrollFrame
    if questScrollFrame then
        Tooltip:RegisterTooltipFrame(questScrollFrame.StoryTooltip)
        Tooltip:RegisterTooltipFrame(questScrollFrame.CampaignTooltip)
    end
end

function Tooltip:StyleTooltips()
    local knownFrames = Tooltip:GetKnownTooltipFrameNames()
    for index = 1, #knownFrames do
        local tooltipName = knownFrames[index]
        Tooltip:RegisterTooltipFrame(_G[tooltipName])
    end

    Tooltip:DiscoverGlobalTooltips()

    RefineUI:RegisterEventCallback("ADDON_LOADED", function()
        RefineUI:Debounce(Tooltip:GetTooltipDiscoverDebounceKey(), 0.05, function()
            Tooltip:DiscoverGlobalTooltips()
        end)
    end, TOOLTIP_DISCOVER_ON_ADDON_LOADED_KEY)
end

function Tooltip:StyleCloseButton()
    local itemRefTooltip = _G.ItemRefTooltip
    if not itemRefTooltip or not itemRefTooltip.CloseButton then
        return
    end

    local closeButton = itemRefTooltip.CloseButton
    RefineUI.StripTextures(closeButton)

    local closeTexturePath = RefineUI.Media
        and RefineUI.Media.Textures
        and RefineUI.Media.Textures.Close
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

function Tooltip:StyleHealthBar()
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
    Tooltip:StyleHealthBar()
    Tooltip:StyleTooltips()
    Tooltip:StyleCloseButton()

    if ALL_TOOLTIP_TYPES ~= nil then
        Tooltip:AddTooltipPostCallOnce(TOOLTIP_POSTCALL_ALL_TYPES_KEY, ALL_TOOLTIP_TYPES, function(tt, data)
            if not Tooltip:IsGameTooltipFrameSafe(tt) then
                return
            end
            if Tooltip:IsEmbeddedTooltipFrame(tt) then
                StyleTooltipLines(tt, true)

                local tooltipType = Tooltip:GetTooltipDataType(data)
                if TOOLTIP_DATA_TYPE and tooltipType == TOOLTIP_DATA_TYPE.Item then
                    ApplyEmbeddedItemIconBorder(tt, data)
                else
                    ClearEmbeddedItemIconBorder(tt)
                end
                return
            end

            Tooltip:RegisterTooltipFrame(tt)
            StyleTooltipLines(tt)

            local tooltipType = Tooltip:GetTooltipDataType(data)
            local unitToken = Tooltip:ResolveTooltipUnitToken(tt, data)
            if TOOLTIP_DATA_TYPE and tooltipType == TOOLTIP_DATA_TYPE.Item then
                return
            end
            if unitToken then
                Tooltip:ApplyUnitBorderColor(tt, unitToken)
            elseif TOOLTIP_DATA_TYPE and tooltipType == TOOLTIP_DATA_TYPE.Unit then
                if not Tooltip:ApplyUnitBorderColorFromData(tt, data) then
                    Tooltip:ResetTooltipBorderColor(tt)
                end
            else
                Tooltip:ResetTooltipBorderColor(tt)
            end
        end)
    end

    if TOOLTIP_DATA_TYPE and TOOLTIP_DATA_TYPE.Item then
        Tooltip:AddTooltipPostCallOnce(TOOLTIP_POSTCALL_ITEM_KEY, TOOLTIP_DATA_TYPE.Item, function(tt, data)
            if not Tooltip:IsGameTooltipFrameSafe(tt) then
                return
            end
            if Tooltip:IsEmbeddedTooltipFrame(tt) then
                return
            end

            Tooltip:RegisterTooltipFrame(tt)
            Tooltip:ApplyItemQualityBorderColor(tt, data)
            Tooltip:DispatchItemHandlers(tt, data)
        end)
    end
end
