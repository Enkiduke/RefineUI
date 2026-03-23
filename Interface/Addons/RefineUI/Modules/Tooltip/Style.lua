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
local Media = RefineUI.Media

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
local TOOLTIP_SHARED_BACKDROP_STYLE_HOOK_KEY = "Tooltip:SharedTooltip_SetBackdropStyle"
local TOOLTIP_SET_TOOLTIP_MONEY_HOOK_KEY = "Tooltip:SetTooltipMoney"
local TOOLTIP_BORDER_HOST_FRAME_LEVEL = 0
local TOOLTIP_BORDER_HOST_FRAME_STRATA = "TOOLTIP"

----------------------------------------------------------------------------------------
-- Styling
----------------------------------------------------------------------------------------
local function StyleMoneyFontString(fontString, styledFontStrings, size)
    if not Tooltip:CanAccessObjectSafe(fontString) or Tooltip:IsForbiddenFrameSafe(fontString) then
        return
    end
    if type(fontString.SetFont) ~= "function" then
        return
    end
    if styledFontStrings[fontString] then
        return
    end

    RefineUI.Font(fontString, size or 12, nil, "OUTLINE")
    styledFontStrings[fontString] = true
end

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

    local state = Tooltip:GetTooltipSkinState(tt)
    local maxStyledLineIndex = state and state.maxStyledLineIndex or 0
    if numLines <= maxStyledLineIndex then
        return
    end

    local styledFontStrings = Tooltip:GetStyledFontStringRegistry()
    for lineIndex = maxStyledLineIndex + 1, numLines do
        local leftLine = Tooltip:GetCachedLine(tt, lineIndex)
        if leftLine and not styledFontStrings[leftLine] then
            RefineUI.Font(leftLine, lineIndex == 1 and 14 or 12, nil, "OUTLINE")
            styledFontStrings[leftLine] = true
        end

        local rightLine = Tooltip:GetCachedRightLine(tt, lineIndex)
        if rightLine then
            if not styledFontStrings[rightLine] then
                RefineUI.Font(rightLine, 12, nil, "OUTLINE")
                styledFontStrings[rightLine] = true
            end
        end
    end

    if state then
        state.maxStyledLineIndex = numLines
    end
end

function Tooltip:StyleTooltipFrameLines(tt, includeEmbedded)
    StyleTooltipLines(tt, includeEmbedded)
end

function Tooltip:StyleTooltipMoneyFrames(tt, includeEmbedded)
    if not Tooltip:IsGameTooltipFrameSafe(tt) then
        return
    end
    if not includeEmbedded and Tooltip:IsEmbeddedTooltipFrame(tt) then
        return
    end

    local tooltipName = Tooltip:GetTooltipNameSafe(tt)
    if not tooltipName then
        return
    end

    local styledFontStrings = Tooltip:GetStyledFontStringRegistry()
    local shownMoneyFrames = Tooltip:ReadSafeNumber(select(1, Tooltip:SafeGetField(tt, "shownMoneyFrames")))
    local numMoneyFrames = Tooltip:ReadSafeNumber(select(1, Tooltip:SafeGetField(tt, "numMoneyFrames")))
    local moneyFrameCount = shownMoneyFrames or numMoneyFrames or 0
    if moneyFrameCount <= 0 then
        return
    end

    for moneyFrameIndex = 1, moneyFrameCount do
        local moneyFrame = Tooltip:GetCachedMoneyRegion(tt, moneyFrameIndex, "")
        if Tooltip:CanAccessObjectSafe(moneyFrame) and not Tooltip:IsForbiddenFrameSafe(moneyFrame) then
            local prefixText = Tooltip:GetCachedMoneyRegion(tt, moneyFrameIndex, "PrefixText")
            local suffixText = Tooltip:GetCachedMoneyRegion(tt, moneyFrameIndex, "SuffixText")
            StyleMoneyFontString(prefixText, styledFontStrings, 12)
            StyleMoneyFontString(suffixText, styledFontStrings, 12)
        end
    end
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

local function ResolveBorderHostFrameLevel(tt, borderHost)
    local okLevel, frameLevel = Tooltip:SafeObjectMethodCall(tt, "GetFrameLevel")
    local safeFrameLevel = okLevel and Tooltip:ReadSafeNumber(frameLevel) or nil
    if safeFrameLevel then
        return max(0, safeFrameLevel - 1)
    end

    local okCurrent, currentFrameLevel = Tooltip:SafeObjectMethodCall(borderHost, "GetFrameLevel")
    local safeCurrentFrameLevel = okCurrent and Tooltip:ReadSafeNumber(currentFrameLevel) or nil
    if safeCurrentFrameLevel then
        return safeCurrentFrameLevel
    end

    return TOOLTIP_BORDER_HOST_FRAME_LEVEL
end

local function ResolveBorderHostFrameStrata(tt, borderHost)
    local okStrata, frameStrata = Tooltip:SafeObjectMethodCall(tt, "GetFrameStrata")
    local safeFrameStrata = okStrata and Tooltip:ReadSafeString(frameStrata) or nil
    if safeFrameStrata then
        return safeFrameStrata
    end

    local okCurrent, currentFrameStrata = Tooltip:SafeObjectMethodCall(borderHost, "GetFrameStrata")
    local safeCurrentFrameStrata = okCurrent and Tooltip:ReadSafeString(currentFrameStrata) or nil
    if safeCurrentFrameStrata then
        return safeCurrentFrameStrata
    end

    return TOOLTIP_BORDER_HOST_FRAME_STRATA
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
    local needsHostInitialization = false
    if not borderHost or type(borderHost.SetPoint) ~= "function" then
        borderHost = CreateFrame("Frame", nil, tt)
        if borderHost.EnableMouse then
            borderHost:EnableMouse(false)
        end
        state.borderHost = borderHost
        state.borderHostInitialized = nil
        state.borderHostInset = nil
        state.borderHostEdgeSize = nil
        state.lastBorderColorR = nil
        state.lastBorderColorG = nil
        state.lastBorderColorB = nil
        state.lastBorderColorA = nil
        needsHostInitialization = true
    end

    if type(borderHost.GetParent) == "function" and borderHost:GetParent() ~= tt then
        borderHost:SetParent(tt)
        needsHostInitialization = true
    end

    local desiredFrameLevel = ResolveBorderHostFrameLevel(tt, borderHost)
    if borderHost:GetFrameLevel() ~= desiredFrameLevel then
        borderHost:SetFrameLevel(desiredFrameLevel)
    end

    local desiredFrameStrata = ResolveBorderHostFrameStrata(tt, borderHost)
    if borderHost:GetFrameStrata() ~= desiredFrameStrata then
        borderHost:SetFrameStrata(desiredFrameStrata)
    end

    local borderInset, borderEdgeSize = Tooltip:GetTooltipBorderParams()
    if needsHostInitialization or not state.borderHostInitialized or not borderHost.bg then
        RefineUI.SetOutside(borderHost, tt, 0, 0)
        RefineUI.SetTemplate(borderHost, "Transparent")
        state.borderHostInitialized = true
    end

    if needsHostInitialization
        or state.borderHostInset ~= borderInset
        or state.borderHostEdgeSize ~= borderEdgeSize
        or not (borderHost.RefineBorder or borderHost.border)
    then
        RefineUI.CreateBorder(borderHost, borderInset, borderInset, borderEdgeSize)
        state.borderHostInset = borderInset
        state.borderHostEdgeSize = borderEdgeSize
    end

    if borderHost.Show then
        borderHost:Show()
    end

    local nineSlice, okNineSlice = Tooltip:SafeGetField(tt, "NineSlice")
    if okNineSlice and nineSlice then
        Tooltip:SafeObjectMethodCall(nineSlice, "SetAlpha", 0)
    end
end

function Tooltip:SetTooltipBorderColor(tt, r, g, b, a)
    if not Tooltip:IsGameTooltipFrameSafe(tt) or Tooltip:IsEmbeddedTooltipFrame(tt) then
        return
    end

    Tooltip:SetBackdropStyle(tt)

    local state = Tooltip:GetTooltipSkinState(tt)
    local borderHost = state and state.borderHost
    local border = borderHost and (borderHost.RefineBorder or borderHost.border)
    local borderAlpha = a or 1
    if state
        and border
        and border.SetBackdropBorderColor
        and state.lastBorderColorR == r
        and state.lastBorderColorG == g
        and state.lastBorderColorB == b
        and state.lastBorderColorA == borderAlpha
    then
        return
    end

    if border and border.SetBackdropBorderColor then
        border:SetBackdropBorderColor(r, g, b, borderAlpha)
        if state then
            state.lastBorderColorR = r
            state.lastBorderColorG = g
            state.lastBorderColorB = b
            state.lastBorderColorA = borderAlpha
        end
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

    local state = Tooltip:GetTooltipSkinState(tt)
    if state and not state.onHideHooked then
        local hookKey = Tooltip:BuildTooltipHookKey(tt, "OnHide")
        local ok, reason = RefineUI:HookScriptOnce(hookKey, tt, "OnHide", function(frame)
            Tooltip:ResetTooltipTransientState(frame)
        end)
        if ok or reason == "already_hooked" then
            state.onHideHooked = true
        end
    end

    if state and not state.onShowHooked then
        local hookKey = Tooltip:BuildTooltipHookKey(tt, "OnShow")
        local ok, reason = RefineUI:HookScriptOnce(hookKey, tt, "OnShow", function(frame)
            if Tooltip:ConsumeTooltipPostCallRender(frame) then
                return
            end

            Tooltip:ResetTooltipTransientState(frame)
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
                StyleTooltipLines(frame)
                Tooltip:StyleTooltipMoneyFrames(frame)
                return
            end

            local hasItemTooltip = false
            hasItemTooltip = select(1, TryApplyItemQualityBorderOnShow(frame))
            if hasItemTooltip then
                StyleTooltipLines(frame)
                Tooltip:StyleTooltipMoneyFrames(frame)
                return
            end

            Tooltip:ResetTooltipBorderColor(frame)
            StyleTooltipLines(frame)
            Tooltip:StyleTooltipMoneyFrames(frame)
        end)
        if ok or reason == "already_hooked" then
            state.onShowHooked = true
        end
    end

    local compareHeader, okCompare = Tooltip:SafeGetField(tt, "CompareHeader")
    if state and okCompare and Tooltip:CanAccessObjectSafe(compareHeader) and not state.compareHeaderStripped then
        if not Tooltip:SafeObjectMethodCall(compareHeader, "StripTexture") then
            Tooltip:SafeObjectMethodCall(compareHeader, "StripTextures")
        end
        state.compareHeaderStripped = true
    end
end

function Tooltip:RegisterKnownTooltipFrames()
    local knownFrames = Tooltip:GetKnownTooltipFrameNames()
    for index = 1, #knownFrames do
        local tooltipName = knownFrames[index]
        Tooltip:RegisterTooltipFrame(_G[tooltipName])
    end

    local questScrollFrame = _G.QuestScrollFrame
    if questScrollFrame then
        Tooltip:RegisterTooltipFrame(questScrollFrame.StoryTooltip)
        Tooltip:RegisterTooltipFrame(questScrollFrame.CampaignTooltip)
    end
end

function Tooltip:DiscoverGlobalTooltips()
    for _, globalValue in pairs(_G) do
        if Tooltip:IsGameTooltipFrameSafe(globalValue) then
            Tooltip:RegisterTooltipFrame(globalValue)
        end
    end
end

function Tooltip:StyleTooltips()
    Tooltip:RegisterKnownTooltipFrames()
    Tooltip:DiscoverGlobalTooltips()

    RefineUI:RegisterEventCallback("ADDON_LOADED", function()
        Tooltip:RegisterKnownTooltipFrames()
    end, TOOLTIP_DISCOVER_ON_ADDON_LOADED_KEY)

    RefineUI:HookOnce(TOOLTIP_SET_TOOLTIP_MONEY_HOOK_KEY, "SetTooltipMoney", function(frame)
        if not Tooltip:IsGameTooltipFrameSafe(frame) or Tooltip:IsEmbeddedTooltipFrame(frame) then
            return
        end

        Tooltip:StyleTooltipMoneyFrames(frame)
    end)

    RefineUI:HookOnce(TOOLTIP_SHARED_BACKDROP_STYLE_HOOK_KEY, "SharedTooltip_SetBackdropStyle", function(tt)
        if not Tooltip:IsGameTooltipFrameSafe(tt) or Tooltip:IsEmbeddedTooltipFrame(tt) then
            return
        end
        Tooltip:RegisterTooltipFrame(tt)
        Tooltip:SetBackdropStyle(tt)

        StyleTooltipLines(tt)
        Tooltip:StyleTooltipMoneyFrames(tt)
    end)
end

function Tooltip:StyleCloseButton()
    local itemRefTooltip = _G.ItemRefTooltip
    if not itemRefTooltip or not itemRefTooltip.CloseButton then
        return
    end

    local closeButton = itemRefTooltip.CloseButton
    RefineUI.StripTextures(closeButton)

    local closeTexturePath = Media and Media.Textures and Media.Textures.Close
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
                ClearEmbeddedItemIconBorder(tt)
                return
            end

            Tooltip:RegisterTooltipFrame(tt)
            Tooltip:ResetTooltipRenderFlags(tt)
            Tooltip:MarkTooltipPostCallRender(tt)

            local tooltipType = Tooltip:GetTooltipDataType(data)
            if TOOLTIP_DATA_TYPE and tooltipType == TOOLTIP_DATA_TYPE.Item then
                return
            end

            local unitToken = Tooltip:ResolveTooltipUnitToken(tt, data)
            if unitToken then
                Tooltip:ApplyUnitBorderColor(tt, unitToken)
            elseif TOOLTIP_DATA_TYPE and tooltipType == TOOLTIP_DATA_TYPE.Unit then
                if not Tooltip:ApplyUnitBorderColorFromData(tt, data) then
                    Tooltip:ResetTooltipBorderColor(tt)
                end
            else
                Tooltip:ResetTooltipBorderColor(tt)
            end

            StyleTooltipLines(tt)
            Tooltip:StyleTooltipMoneyFrames(tt)
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
            Tooltip:MarkTooltipPostCallRender(tt)
            Tooltip:ApplyItemQualityBorderColor(tt, data)
            Tooltip:DispatchItemHandlers(tt, data)
            StyleTooltipLines(tt)
            Tooltip:StyleTooltipMoneyFrames(tt)
        end)
    end
end
