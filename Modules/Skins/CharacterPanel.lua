----------------------------------------------------------------------------------------
-- Skins Component: Character Panel
-- Description: Minimal CharacterFrame enhancements (item level, slot indicators, stats).
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Skins = RefineUI:GetModule("Skins")
if not Skins then
    return
end

----------------------------------------------------------------------------------------
-- Shared Aliases
----------------------------------------------------------------------------------------
local Config = RefineUI.Config
local Media = RefineUI.Media
local Colors = RefineUI.Colors
local Locale = RefineUI.Locale

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local type = type
local ipairs = ipairs
local unpack = unpack
local floor = math.floor
local max = math.max
local format = string.format
local tinsert = table.insert
local C_Timer = C_Timer
local C_Item = C_Item
local C_PaperDollInfo = C_PaperDollInfo
local C_TooltipInfo = C_TooltipInfo
local GetAverageItemLevel = GetAverageItemLevel
local GetInventoryItemLink = GetInventoryItemLink
local UnitHealthMax = UnitHealthMax
local UnitPowerMax = UnitPowerMax
local InCombatLockdown = InCombatLockdown
local MenuUtil = MenuUtil
local GameTooltip = GameTooltip

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local COMPONENT_KEY = "Skins:CharacterPanel"
local STATE_REGISTRY = "SkinsCharacterPanelState"

local HOOK_KEY = {
    ITEM_LEVEL = COMPONENT_KEY .. ":Hook:PaperDollFrame_SetItemLevel",
    SLOT_UPDATE = COMPONENT_KEY .. ":Hook:PaperDollItemSlotButton_Update",
    CHARACTER_ON_SHOW = COMPONENT_KEY .. ":Hook:CharacterFrame:OnShow",
    STATS_UPDATE = COMPONENT_KEY .. ":Hook:PaperDollFrame_UpdateStats",
}

local EVENT_KEY = {
    PLAYER_ENTERING_WORLD = COMPONENT_KEY .. ":Event:PLAYER_ENTERING_WORLD",
    PLAYER_EQUIPMENT_CHANGED = COMPONENT_KEY .. ":Event:PLAYER_EQUIPMENT_CHANGED",
    UNIT_INVENTORY_CHANGED = COMPONENT_KEY .. ":Event:UNIT_INVENTORY_CHANGED",
    SOCKET_INFO_UPDATE = COMPONENT_KEY .. ":Event:SOCKET_INFO_UPDATE",
    SPELL_POWER_CHANGED = COMPONENT_KEY .. ":Event:SPELL_POWER_CHANGED",
    UNIT_MAXHEALTH = COMPONENT_KEY .. ":Event:UNIT_MAXHEALTH",
}

local SLOT_IDS = {
    1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18,
}

local SLOT_FRAME_NAME_BY_ID = {
    [1] = "CharacterHeadSlot",
    [2] = "CharacterNeckSlot",
    [3] = "CharacterShoulderSlot",
    [5] = "CharacterChestSlot",
    [6] = "CharacterWaistSlot",
    [7] = "CharacterLegsSlot",
    [8] = "CharacterFeetSlot",
    [9] = "CharacterWristSlot",
    [10] = "CharacterHandsSlot",
    [11] = "CharacterFinger0Slot",
    [12] = "CharacterFinger1Slot",
    [13] = "CharacterTrinket0Slot",
    [14] = "CharacterTrinket1Slot",
    [15] = "CharacterBackSlot",
    [16] = "CharacterMainHandSlot",
    [17] = "CharacterSecondaryHandSlot",
    [18] = "CharacterRangedSlot",
}

local SLOT_PLACEMENT_BY_ID = {
    [1] = "RIGHT",
    [2] = "RIGHT",
    [3] = "RIGHT",
    [5] = "RIGHT",
    [9] = "RIGHT",
    [15] = "RIGHT",

    [6] = "LEFT",
    [7] = "LEFT",
    [8] = "LEFT",
    [10] = "LEFT",
    [11] = "LEFT",
    [12] = "LEFT",
    [13] = "LEFT",
    [14] = "LEFT",

    [16] = "LEFT",
    [17] = "RIGHT",
    [18] = "RIGHT",
}

local ENCHANT_ELIGIBLE_BY_SLOT = {
    [5] = true,
    [7] = true,
    [8] = true,
    [9] = true,
    [11] = true,
    [12] = true,
    [15] = true,
    [16] = true,
    [17] = true,
}

local OPTIONAL_SOCKET_ELIGIBLE_BY_SLOT = {
    [1] = true,  -- Head
    [2] = true,  -- Neck
    [6] = true,  -- Waist
    [9] = true,  -- Wrist
    [11] = true, -- Ring 1
    [12] = true, -- Ring 2
}

local EQUIP_LOC_NO_OFFHAND_ENCHANT = {
    INVTYPE_SHIELD = true,
    INVTYPE_HOLDABLE = true,
}

local STAT_KEY_HEALTH_TOTAL = "REFINE_HEALTH_TOTAL"
local STAT_KEY_MANA_TOTAL = "REFINE_MANA_TOTAL"
local HEALTH_TOTAL_LABEL = "Health (Total)"
local MANA_TOTAL_LABEL = "Mana (Total)"
local REFINE_GOLD_COLOR = "|cffffd200"
local COLOR_RESET = "|r"
local ITEM_LEVEL_SEPARATOR = "|TInterface\\Common\\Indicator-Yellow:8:8:0:0|t"
local ITEM_LEVEL_HEADER_CURRENT = "Current"
local ITEM_LEVEL_HEADER_MAX = "Max"

local INDICATOR_SIZE = 14
local INDICATOR_SPACING = 0
local INDICATOR_SIDE_OFFSET = 8
local INDICATOR_TEXT_OFFSET = 4
local INDICATOR_TEXT_WIDTH = 110
local INDICATOR_TEXT_MAX_CHARS = 28
local INDICATOR_MAX_GEMS = 3
local INDICATOR_MAX_ENTRIES = INDICATOR_MAX_GEMS + 1
local ENCHANT_PRESENT_ATLAS = "common-icon-checkmark"
local FILLED_BORDER_COLOR = { 0.6, 0.6, 0.6, 1 }
local EMPTY_BORDER_COLOR = { 1, 0.2, 0.2, 1 }
local NO_SOCKET_COLOR = { 1, 0.82, 0, 1 }

local SETTINGS_BUTTON_NAME = "RefineUICharacterPanelSettingsButton"
local SETTINGS_BUTTON_SIZE = 32

----------------------------------------------------------------------------------------
-- State / Registries
----------------------------------------------------------------------------------------
RefineUI:CreateDataRegistry(STATE_REGISTRY, "k")

local setupComplete = false
local refreshQueued = false
local statsInjected = false
local eventsRegistered = false
local slotIdByFrame = setmetatable({}, { __mode = "k" })

local function GetState(owner)
    local state = RefineUI:RegistryGet(STATE_REGISTRY, owner)
    if type(state) ~= "table" then
        state = {}
        RefineUI:RegistrySet(STATE_REGISTRY, owner, nil, state)
    end
    return state
end

local function GetModuleState()
    return GetState(Skins)
end

----------------------------------------------------------------------------------------
-- Config Helpers
----------------------------------------------------------------------------------------
local function GetCharacterPanelConfig()
    if Skins.GetCharacterPanelConfig then
        return Skins:GetCharacterPanelConfig()
    end

    Config.Skins = Config.Skins or {}
    Config.Skins.CharacterPanel = Config.Skins.CharacterPanel or {}
    return Config.Skins.CharacterPanel
end

local function IsFeatureEnabled()
    local skinsConfig = Config.Skins
    local characterConfig = GetCharacterPanelConfig()
    return (skinsConfig and skinsConfig.Enable ~= false) and (characterConfig.Enable ~= false)
end

local function ShouldShowIndicatorEntryText(characterConfig, isFilled)
    if isFilled then
        return characterConfig.ShowIndicatorText == true
    end
    return characterConfig.ShowMissingIndicatorText == true
end

local function IsSlotIndicatorKindEnabled(characterConfig, indicatorKind)
    if indicatorKind == "ENCHANT" then
        return characterConfig.ShowEnchantIndicators ~= false
    elseif indicatorKind == "FILLED_GEM" then
        return characterConfig.ShowFilledGemIndicators ~= false
    elseif indicatorKind == "EMPTY_SOCKET" then
        return characterConfig.ShowEmptySocketIndicators ~= false
    elseif indicatorKind == "NO_SOCKET" then
        return characterConfig.ShowNoSocketIndicators ~= false
    elseif indicatorKind == "NO_ITEM" then
        return characterConfig.ShowNoItemIndicators ~= false
    end

    return true
end

----------------------------------------------------------------------------------------
-- Format Helpers
----------------------------------------------------------------------------------------
local function FormatItemLevelValue(value)
    if type(value) ~= "number" then
        return "0"
    end

    local rounded = floor(value * 100 + 0.5) / 100
    local text = format("%.2f", rounded)
    text = text:gsub("%.?0+$", "")
    if text == "" then
        text = "0"
    end
    return text
end

local function SetTextureAtlas(texture, atlas)
    if not texture then
        return false
    end
    texture:SetTexture(nil)
    if texture.SetAtlas then
        local ok = pcall(texture.SetAtlas, texture, atlas, false)
        if ok then
            return true
        end
    end
    return false
end

local function NormalizeDisplayText(text)
    if type(text) ~= "string" then
        return nil
    end

    local normalized = text
    normalized = normalized:gsub("|c%x%x%x%x%x%x%x%x", "")
    normalized = normalized:gsub("|r", "")
    normalized = normalized:gsub("|T.-|t", "")
    normalized = normalized:gsub("^%s+", "")
    normalized = normalized:gsub("%s+$", "")
    normalized = normalized:gsub("%s+", " ")
    if normalized == "" then
        return nil
    end

    local labelPrefix, remainder = normalized:match("^([^:]+):%s*(.+)$")
    if labelPrefix and remainder and not labelPrefix:find("%d") and #labelPrefix <= 18 then
        normalized = remainder
    end

    if #normalized > INDICATOR_TEXT_MAX_CHARS then
        normalized = normalized:sub(1, INDICATOR_TEXT_MAX_CHARS - 3) .. "..."
    end

    return normalized
end

local function BuildOutlinedFlag(existingFlags)
    local flags = type(existingFlags) == "string" and existingFlags or ""
    if flags:find("OUTLINE", 1, true) or flags:find("THICKOUTLINE", 1, true) then
        return flags
    end
    if flags == "" then
        return "OUTLINE"
    end
    return flags .. ",OUTLINE"
end

local function ApplyStyledFont(fontString)
    if not (fontString and fontString.GetFont and fontString.SetFont) then
        return
    end

    local fontPath, fontSize, fontFlags = fontString:GetFont()
    if type(fontPath) ~= "string" or type(fontSize) ~= "number" then
        return
    end

    fontString:SetFont(fontPath, fontSize, BuildOutlinedFlag(fontFlags))
    fontString:SetShadowColor(0, 0, 0, 1)
    fontString:SetShadowOffset(1, -1)
end

local function FormatCurrentMaxItemLevelText(currentItemLevel, maxItemLevel)
    local currentText = FormatItemLevelValue(currentItemLevel)
    local maxText = FormatItemLevelValue(maxItemLevel)
    local maxColored = REFINE_GOLD_COLOR .. maxText .. COLOR_RESET
    return currentText .. "  " .. ITEM_LEVEL_SEPARATOR .. " " .. maxColored, currentText .. " / " .. maxText
end

local function HideItemLevelHeaderLabels(statFrame)
    if not statFrame then
        return
    end

    local state = GetState(statFrame)
    if state.currentHeader then
        state.currentHeader:Hide()
    end
    if state.maxHeader then
        state.maxHeader:Hide()
    end
end

local function EnsureItemLevelHeaderLabels(statFrame)
    if not statFrame then
        return nil
    end

    local state = GetState(statFrame)
    if state.currentHeader and state.maxHeader then
        return state
    end

    local currentHeader = statFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    local maxHeader = statFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if RefineUI.Font then
        RefineUI.Font(currentHeader, 8, nil, "OUTLINE")
        RefineUI.Font(maxHeader, 8, nil, "OUTLINE")
    end

    currentHeader:SetText(ITEM_LEVEL_HEADER_CURRENT)
    maxHeader:SetText(ITEM_LEVEL_HEADER_MAX)
    currentHeader:SetTextColor(0.62, 0.62, 0.62, 1)
    maxHeader:SetTextColor(0.62, 0.62, 0.62, 1)

    currentHeader:ClearAllPoints()
    maxHeader:ClearAllPoints()
    currentHeader:SetPoint("BOTTOMLEFT", statFrame, "TOPLEFT", 40, -6)
    maxHeader:SetPoint("BOTTOMRIGHT", statFrame, "TOPRIGHT", -40, -6)

    state.currentHeader = currentHeader
    state.maxHeader = maxHeader
    return state
end

local function ApplyCharacterPanelTextStyle()
    if not (CharacterStatsPane and CharacterStatsPane:IsShown()) then
        return
    end

    if CharacterStatsPane.ItemLevelFrame and CharacterStatsPane.ItemLevelFrame.Value then
        ApplyStyledFont(CharacterStatsPane.ItemLevelFrame.Value)
    end

    local categories = {
        CharacterStatsPane.ItemLevelCategory,
        CharacterStatsPane.AttributesCategory,
        CharacterStatsPane.EnhancementsCategory,
    }
    for i = 1, #categories do
        local categoryFrame = categories[i]
        if categoryFrame and categoryFrame.Title then
            ApplyStyledFont(categoryFrame.Title)
            categoryFrame.Title:SetTextColor(1, 0.82, 0, 1)
        end
    end

    if CharacterStatsPane.statsFramePool and CharacterStatsPane.statsFramePool.EnumerateActive then
        for statFrame in CharacterStatsPane.statsFramePool:EnumerateActive() do
            if statFrame then
                if statFrame.Label then
                    ApplyStyledFont(statFrame.Label)
                end
                if statFrame.Value then
                    ApplyStyledFont(statFrame.Value)
                end
            end
        end
    end
end

----------------------------------------------------------------------------------------
-- Item Level
----------------------------------------------------------------------------------------
local function ApplyCurrentMaxItemLevel(statFrame, unit)
    if unit ~= "player" then
        HideItemLevelHeaderLabels(statFrame)
        return
    end
    if not IsFeatureEnabled() then
        HideItemLevelHeaderLabels(statFrame)
        return
    end

    local characterConfig = GetCharacterPanelConfig()
    if characterConfig.ShowCurrentMaxItemLevel == false then
        HideItemLevelHeaderLabels(statFrame)
        return
    end

    local avgItemLevel, avgItemLevelEquipped, avgItemLevelPvP = GetAverageItemLevel()
    if type(avgItemLevel) ~= "number" or type(avgItemLevelEquipped) ~= "number" then
        return
    end

    local minItemLevel = (C_PaperDollInfo and C_PaperDollInfo.GetMinItemLevel and C_PaperDollInfo.GetMinItemLevel()) or 0
    if type(minItemLevel) ~= "number" then
        minItemLevel = 0
    end

    local currentItemLevel = max(minItemLevel, avgItemLevelEquipped)
    local maxItemLevel = avgItemLevel
    local displayText, tooltipDisplayText = FormatCurrentMaxItemLevelText(currentItemLevel, maxItemLevel)

    PaperDollFrame_SetLabelAndText(statFrame, STAT_AVERAGE_ITEM_LEVEL, displayText, false, currentItemLevel)
    if statFrame.Value then
        ApplyStyledFont(statFrame.Value)
    end
    local state = EnsureItemLevelHeaderLabels(statFrame)
    if state and state.currentHeader and state.maxHeader then
        ApplyStyledFont(state.currentHeader)
        ApplyStyledFont(state.maxHeader)
        state.currentHeader:Show()
        state.maxHeader:Show()
    end

    statFrame.tooltip = HIGHLIGHT_FONT_COLOR_CODE
        .. format(PAPERDOLLFRAME_TOOLTIP_FORMAT, STAT_AVERAGE_ITEM_LEVEL)
        .. " "
        .. tooltipDisplayText
        .. FONT_COLOR_CODE_CLOSE

    local tooltip2 = STAT_AVERAGE_ITEM_LEVEL_TOOLTIP
    if type(avgItemLevelPvP) == "number" and avgItemLevelPvP > 0 then
        tooltip2 = tooltip2 .. "\n\n" .. STAT_AVERAGE_PVP_ITEM_LEVEL:format(avgItemLevelPvP)
    end
    statFrame.tooltip2 = tooltip2
end

----------------------------------------------------------------------------------------
-- Custom Stats
----------------------------------------------------------------------------------------
local function SetHealthTotal(statFrame, unit)
    if unit ~= "player" then
        statFrame:Hide()
        return
    end

    local characterConfig = GetCharacterPanelConfig()
    if not IsFeatureEnabled() or characterConfig.ShowHealthTotal == false then
        statFrame:Hide()
        return
    end

    local maxHealth = UnitHealthMax("player")
    if type(maxHealth) ~= "number" or maxHealth <= 0 then
        statFrame:Hide()
        return
    end

    local healthText = BreakUpLargeNumbers(maxHealth)
    PaperDollFrame_SetLabelAndText(statFrame, HEALTH_TOTAL_LABEL, healthText, false, maxHealth)
    statFrame.tooltip = HIGHLIGHT_FONT_COLOR_CODE
        .. format(PAPERDOLLFRAME_TOOLTIP_FORMAT, HEALTH_TOTAL_LABEL)
        .. " "
        .. healthText
        .. FONT_COLOR_CODE_CLOSE
    statFrame.tooltip2 = STAT_HEALTH_TOOLTIP
    statFrame:Show()
end

local function SetManaTotal(statFrame, unit)
    if unit ~= "player" then
        statFrame:Hide()
        return
    end

    local characterConfig = GetCharacterPanelConfig()
    if not IsFeatureEnabled() or characterConfig.ShowManaTotal == false then
        statFrame:Hide()
        return
    end

    local maxMana = UnitPowerMax("player", Enum.PowerType.Mana)
    if type(maxMana) ~= "number" or maxMana <= 0 then
        statFrame:Hide()
        return
    end

    local manaText = BreakUpLargeNumbers(maxMana)
    PaperDollFrame_SetLabelAndText(statFrame, MANA_TOTAL_LABEL, manaText, false, maxMana)
    statFrame.tooltip = HIGHLIGHT_FONT_COLOR_CODE
        .. format(PAPERDOLLFRAME_TOOLTIP_FORMAT, MANA_TOTAL_LABEL)
        .. " "
        .. manaText
        .. FONT_COLOR_CODE_CLOSE
    statFrame.tooltip2 = STAT_MANA_TOOLTIP
    statFrame:Show()
end

local function InsertCustomAttributeStats()
    if statsInjected then
        return
    end
    if type(PAPERDOLL_STATINFO) ~= "table" or type(PAPERDOLL_STATCATEGORIES) ~= "table" then
        return
    end

    PAPERDOLL_STATINFO[STAT_KEY_HEALTH_TOTAL] = {
        updateFunc = function(statFrame, unit)
            SetHealthTotal(statFrame, unit)
        end,
    }

    PAPERDOLL_STATINFO[STAT_KEY_MANA_TOTAL] = {
        updateFunc = function(statFrame, unit)
            SetManaTotal(statFrame, unit)
        end,
    }

    local attributesCategory = PAPERDOLL_STATCATEGORIES[1]
    local statsList = attributesCategory and attributesCategory.stats
    if type(statsList) ~= "table" then
        return
    end

    local hasHealth = false
    local hasMana = false
    local staminaIndex = nil

    for index = 1, #statsList do
        local entry = statsList[index]
        if type(entry) == "table" then
            if entry.stat == "STAMINA" and not staminaIndex then
                staminaIndex = index
            elseif entry.stat == STAT_KEY_HEALTH_TOTAL then
                hasHealth = true
            elseif entry.stat == STAT_KEY_MANA_TOTAL then
                hasMana = true
            end
        end
    end

    local insertIndex = (type(staminaIndex) == "number" and staminaIndex) or #statsList

    if not hasHealth then
        insertIndex = insertIndex + 1
        tinsert(statsList, insertIndex, { stat = STAT_KEY_HEALTH_TOTAL })
    end

    if not hasMana then
        insertIndex = insertIndex + 1
        tinsert(statsList, insertIndex, { stat = STAT_KEY_MANA_TOTAL })
    end

    statsInjected = true
end

----------------------------------------------------------------------------------------
-- Slot Indicators
----------------------------------------------------------------------------------------
local function IsEnchantEligible(slotID, itemLink)
    if not ENCHANT_ELIGIBLE_BY_SLOT[slotID] then
        return false
    end

    if slotID ~= 17 then
        return true
    end

    if type(itemLink) ~= "string" or itemLink == "" then
        return true
    end

    if not (C_Item and C_Item.GetItemInfoInstant) then
        return true
    end

    local equipLoc = select(4, C_Item.GetItemInfoInstant(itemLink))
    if type(equipLoc) == "string" and EQUIP_LOC_NO_OFFHAND_ENCHANT[equipLoc] then
        return false
    end

    return true
end

local function IsOptionalSocketEligible(slotID)
    return OPTIONAL_SOCKET_ELIGIBLE_BY_SLOT[slotID] == true
end

local function GetSlotDetails(slotID, itemLink)
    local details = {
        hasEnchant = false,
        enchantText = nil,
        socketCount = 0,
        sockets = {},
    }

    if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem) then
        return details
    end

    local tooltipData = C_TooltipInfo.GetInventoryItem("player", slotID)
    local lines = tooltipData and tooltipData.lines
    if type(lines) ~= "table" then
        return details
    end

    for i = 1, #lines do
        local line = lines[i]
        if type(line) == "table" then
            if line.type == Enum.TooltipDataLineType.ItemEnchantmentPermanent then
                details.hasEnchant = true
                details.enchantText = NormalizeDisplayText(line.leftText or line.rightText)
            elseif line.type == Enum.TooltipDataLineType.GemSocket then
                details.socketCount = details.socketCount + 1
                local socketInfo = {
                    icon = line.gemIcon,
                }

                local lineText = NormalizeDisplayText(line.leftText or line.rightText)
                if lineText then
                    socketInfo.text = lineText
                elseif socketInfo.icon and C_Item and C_Item.GetItemGem and type(itemLink) == "string" then
                    local gemName = C_Item.GetItemGem(itemLink, details.socketCount)
                    socketInfo.text = NormalizeDisplayText(gemName)
                end

                if socketInfo.icon and C_Item and C_Item.GetItemGem and type(itemLink) == "string" then
                    local _, gemLink = C_Item.GetItemGem(itemLink, details.socketCount)
                    if type(gemLink) == "string" and gemLink ~= "" then
                        socketInfo.link = gemLink
                    end
                end

                details.sockets[details.socketCount] = socketInfo
            end
        end
    end

    return details
end

local function GetSlotFrame(slotID)
    local frameName = SLOT_FRAME_NAME_BY_ID[slotID]
    if type(frameName) ~= "string" then
        return nil
    end
    return _G[frameName]
end

local function GetConfiguredBorderColor()
    local borderColor = Config and Config.General and Config.General.BorderColor
    if type(borderColor) == "table" then
        return borderColor[1] or FILLED_BORDER_COLOR[1],
            borderColor[2] or FILLED_BORDER_COLOR[2],
            borderColor[3] or FILLED_BORDER_COLOR[3],
            borderColor[4] or FILLED_BORDER_COLOR[4]
    end
    return FILLED_BORDER_COLOR[1], FILLED_BORDER_COLOR[2], FILLED_BORDER_COLOR[3], FILLED_BORDER_COLOR[4]
end

local function CreateIndicatorEntry(container, placement)
    local entry = CreateFrame("Frame", nil, container)
    entry:SetSize(INDICATOR_SIZE, INDICATOR_SIZE)
    entry:EnableMouse(true)

    RefineUI.SetTemplate(entry, "Icon")
    RefineUI.CreateBorder(entry, 2, 2, 8)

    local icon = entry:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", entry, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", entry, "BOTTOMRIGHT", -1, 1)
    entry.icon = icon

    local label = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if RefineUI.Font then
        RefineUI.Font(label, 8, nil, "OUTLINE")
    end
    label:ClearAllPoints()
    label:SetPoint("CENTER", entry, "CENTER", 1, 0)
    label:SetShadowOffset(0, 0)
    label:SetShadowColor(0, 0, 0, 0)
    label:SetJustifyH("CENTER")
    label:SetJustifyV("MIDDLE")
    entry.label = label

    local detailText = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if RefineUI.Font then
        RefineUI.Font(detailText, 8, nil, "OUTLINE")
    end
    detailText:SetWidth(INDICATOR_TEXT_WIDTH)
    detailText:SetWordWrap(false)
    if placement == "LEFT" then
        detailText:SetPoint("RIGHT", entry, "LEFT", -INDICATOR_TEXT_OFFSET, 0)
        detailText:SetJustifyH("RIGHT")
    else
        detailText:SetPoint("LEFT", entry, "RIGHT", INDICATOR_TEXT_OFFSET, 0)
        detailText:SetJustifyH("LEFT")
    end
    detailText:SetJustifyV("MIDDLE")
    detailText:Hide()
    entry.detailText = detailText

    entry:SetScript("OnEnter", function(self)
        if not (self.tooltipLink or self.tooltipText) then
            return
        end

        GameTooltip:SetOwner(self, self.tooltipAnchor or "ANCHOR_RIGHT")
        if self.tooltipLink then
            GameTooltip:SetHyperlink(self.tooltipLink)
        else
            local title = self.tooltipTitle or "Details"
            GameTooltip:SetText(title, 1, 1, 1)
            GameTooltip:AddLine(self.tooltipText, 0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end
    end)

    entry:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    entry.tooltipAnchor = (placement == "LEFT") and "ANCHOR_LEFT" or "ANCHOR_RIGHT"

    return entry
end

local function ApplyIndicatorEntry(entry, data)
    if not entry then
        return
    end

    local border = entry.border or entry.RefineBorder
    local missingColor = data.missingColor or EMPTY_BORDER_COLOR
    if border and border.SetBackdropBorderColor then
        if data.filled then
            local br, bg, bb, ba = GetConfiguredBorderColor()
            border:SetBackdropBorderColor(br, bg, bb, ba)
        else
            border:SetBackdropBorderColor(unpack(missingColor))
        end
    end

    local iconShown = false
    if data.iconTexture then
        entry.icon:SetTexture(data.iconTexture)
        entry.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        entry.icon:SetVertexColor(1, 1, 1, 1)
        entry.icon:Show()
        iconShown = true
    elseif data.iconAtlas then
        entry.icon:SetTexCoord(0, 1, 0, 1)
        entry.icon:SetVertexColor(1, 1, 1, 1)
        iconShown = SetTextureAtlas(entry.icon, data.iconAtlas)
        if iconShown then
            entry.icon:Show()
        end
    end

    if iconShown then
        entry.label:Hide()
    else
        entry.icon:Hide()
        entry.label:SetText(data.letter or "?")
        if data.filled then
            entry.label:SetTextColor(1, 1, 1, 1)
        else
            entry.label:SetTextColor(unpack(missingColor))
        end
        entry.label:Show()
    end

    if entry.detailText then
        if data.showDetailText and data.detailText then
            entry.detailText:SetText(data.detailText)
            if data.filled then
                entry.detailText:SetTextColor(0.9, 0.9, 0.9, 1)
            else
                entry.detailText:SetTextColor(unpack(missingColor))
            end
            entry.detailText:Show()
        else
            entry.detailText:Hide()
        end
    end

    entry.tooltipLink = nil
    entry.tooltipTitle = nil
    entry.tooltipText = nil
    if data.filled then
        if type(data.tooltipLink) == "string" and data.tooltipLink ~= "" then
            entry.tooltipLink = data.tooltipLink
        elseif type(data.tooltipText) == "string" and data.tooltipText ~= "" then
            entry.tooltipTitle = data.tooltipTitle
            entry.tooltipText = data.tooltipText
        end
    end

    entry:Show()
end

local function LayoutIndicatorEntries(state, visibleCount)
    if not state or not state.entries then
        return
    end

    local entries = state.entries
    local totalHeight = visibleCount * INDICATOR_SIZE + max(visibleCount - 1, 0) * INDICATOR_SPACING
    local startY = (totalHeight - INDICATOR_SIZE) / 2

    for i = 1, #entries do
        local entry = entries[i]
        entry:ClearAllPoints()
        if i <= visibleCount then
            local yOffset = startY - (i - 1) * (INDICATOR_SIZE + INDICATOR_SPACING)
            entry:SetPoint("CENTER", state.container, "CENTER", 0, yOffset)
            entry:Show()
        else
            if entry.detailText then
                entry.detailText:Hide()
            end
            entry:Hide()
        end
    end
end

local function EnsureSlotIndicator(slotFrame, slotID)
    local state = GetState(slotFrame)
    if state.container then
        return state
    end

    if InCombatLockdown and InCombatLockdown() then
        return nil
    end

    local container = CreateFrame("Frame", nil, slotFrame)
    container:EnableMouse(false)
    container:SetFrameStrata(slotFrame:GetFrameStrata())
    container:SetFrameLevel((slotFrame:GetFrameLevel() or 1) + 8)
    local placement = SLOT_PLACEMENT_BY_ID[slotID] or "RIGHT"
    local stackHeight = INDICATOR_SIZE * INDICATOR_MAX_ENTRIES + INDICATOR_SPACING * (INDICATOR_MAX_ENTRIES - 1)

    container:SetSize(INDICATOR_SIZE + 2, stackHeight)
    if placement == "LEFT" then
        container:SetPoint("RIGHT", slotFrame, "LEFT", -INDICATOR_SIDE_OFFSET, 0)
    else
        container:SetPoint("LEFT", slotFrame, "RIGHT", INDICATOR_SIDE_OFFSET, 0)
    end

    local entries = {}
    for i = 1, INDICATOR_MAX_ENTRIES do
        entries[i] = CreateIndicatorEntry(container, placement)
        entries[i]:Hide()
    end

    state.container = container
    state.entries = entries
    state.placement = placement

    slotIdByFrame[slotFrame] = slotID
    return state
end

local function HideSlotIndicator(slotFrame)
    local state = GetState(slotFrame)
    if not state.container then
        return
    end

    state.container:Hide()

    for i = 1, INDICATOR_MAX_ENTRIES do
        local entry = state.entries and state.entries[i]
        if entry then
            if entry.detailText then
                entry.detailText:Hide()
            end
            entry:Hide()
        end
    end
end

local function RenderSlotIndicator(slotFrame, slotID, itemLink)
    local characterConfig = GetCharacterPanelConfig()
    if not IsFeatureEnabled() or characterConfig.ShowSlotIndicators == false then
        HideSlotIndicator(slotFrame)
        return
    end

    local state = EnsureSlotIndicator(slotFrame, slotID)
    if not state or not state.container then
        return
    end

    local hasItem = type(itemLink) == "string" and itemLink ~= ""
    local details = hasItem and GetSlotDetails(slotID, itemLink) or { hasEnchant = false, enchantText = nil, socketCount = 0, sockets = {} }
    local enchantEligible = IsEnchantEligible(slotID, itemLink)
    local socketCount = details.socketCount or 0
    local showNoSocketState = hasItem and socketCount <= 0 and IsOptionalSocketEligible(slotID)
    local gemCount = socketCount
    if gemCount < 1 and (showNoSocketState or not hasItem) then
        gemCount = 1
    end
    if gemCount > INDICATOR_MAX_GEMS then
        gemCount = INDICATOR_MAX_GEMS
    end

    local entryIndex = 1

    if enchantEligible then
        local enchantFilled = hasItem and details.hasEnchant == true
        local enchantIndicatorKind = hasItem and "ENCHANT" or "NO_ITEM"
        local enchantDetailText
        if enchantFilled then
            enchantDetailText = details.enchantText or "Enchanted"
        elseif hasItem then
            enchantDetailText = "Missing Enchant"
        else
            enchantDetailText = "No Item"
        end

        if IsSlotIndicatorKindEnabled(characterConfig, enchantIndicatorKind) then
            ApplyIndicatorEntry(state.entries[entryIndex], {
                filled = enchantFilled,
                iconAtlas = enchantFilled and ENCHANT_PRESENT_ATLAS or nil,
                letter = "E",
                showDetailText = ShouldShowIndicatorEntryText(characterConfig, enchantFilled),
                detailText = NormalizeDisplayText(enchantDetailText),
                tooltipTitle = "Enchant",
                tooltipText = enchantFilled and NormalizeDisplayText(enchantDetailText) or nil,
            })
            entryIndex = entryIndex + 1
        end
    end

    for gemIndex = 1, gemCount do
        local socketInfo = details.sockets and details.sockets[gemIndex]
        local gemFilled = hasItem and socketInfo and socketInfo.icon
        local isNoSocket = hasItem and socketCount <= 0 and IsOptionalSocketEligible(slotID)
        local gemIndicatorKind
        local gemDetailText
        if gemFilled then
            gemIndicatorKind = "FILLED_GEM"
            gemDetailText = (socketInfo and socketInfo.text) or ("Gem " .. gemIndex)
        elseif hasItem and socketCount > 0 then
            gemIndicatorKind = "EMPTY_SOCKET"
            gemDetailText = "Empty Socket"
        elseif hasItem and isNoSocket then
            gemIndicatorKind = "NO_SOCKET"
            gemDetailText = "No Socket"
        elseif hasItem then
            break
        else
            gemIndicatorKind = "NO_ITEM"
            gemDetailText = "No Item"
        end

        if IsSlotIndicatorKindEnabled(characterConfig, gemIndicatorKind) then
            ApplyIndicatorEntry(state.entries[entryIndex], {
                filled = gemFilled and true or false,
                iconTexture = gemFilled and socketInfo.icon or nil,
                letter = "G",
                showDetailText = ShouldShowIndicatorEntryText(characterConfig, gemFilled and true or false),
                detailText = NormalizeDisplayText(gemDetailText),
                tooltipLink = gemFilled and socketInfo.link or nil,
                tooltipTitle = "Gem",
                tooltipText = gemFilled and NormalizeDisplayText(gemDetailText) or nil,
                missingColor = isNoSocket and NO_SOCKET_COLOR or nil,
            })
            entryIndex = entryIndex + 1
        end
        if entryIndex > INDICATOR_MAX_ENTRIES then
            break
        end
    end

    local visibleCount = entryIndex - 1
    if visibleCount < 1 then
        HideSlotIndicator(slotFrame)
        return
    end

    LayoutIndicatorEntries(state, visibleCount)

    state.container:Show()
end

local function EnsureCharacterSlotBorder(slotFrame)
    if not slotFrame or not RefineUI.CreateBorder then
        return
    end

    if (not slotFrame.border) and InCombatLockdown and InCombatLockdown() then
        return
    end

    RefineUI.CreateBorder(slotFrame, 5, 5, 12)
end

----------------------------------------------------------------------------------------
-- Settings Menu
----------------------------------------------------------------------------------------
local function QueueCharacterRefresh()
    if refreshQueued then
        return
    end

    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        if Skins.RefreshCharacterPanel then
            Skins:RefreshCharacterPanel()
        end
    end)
end

local function ToggleCharacterSetting(flagKey)
    local characterConfig = GetCharacterPanelConfig()
    characterConfig[flagKey] = not (characterConfig[flagKey] ~= false)
    QueueCharacterRefresh()
end

local function BuildCharacterPanelMenu(ownerRegion, rootDescription)
    local characterConfig = GetCharacterPanelConfig()

    rootDescription:CreateTitle("Character Panel")

    rootDescription:CreateCheckbox("Enable Character Enhancements", function()
        return characterConfig.Enable ~= false
    end, function()
        ToggleCharacterSetting("Enable")
    end)

    rootDescription:CreateCheckbox("Current | Maximum Item Level", function()
        return characterConfig.ShowCurrentMaxItemLevel ~= false
    end, function()
        ToggleCharacterSetting("ShowCurrentMaxItemLevel")
    end)

    local slotIndicatorsMenu = rootDescription:CreateButton("Slot Indicators")
    slotIndicatorsMenu:CreateCheckbox("Enable", function()
        return characterConfig.ShowSlotIndicators ~= false
    end, function()
        ToggleCharacterSetting("ShowSlotIndicators")
    end)

    slotIndicatorsMenu:CreateCheckbox("Enchants", function()
        return characterConfig.ShowEnchantIndicators ~= false
    end, function()
        ToggleCharacterSetting("ShowEnchantIndicators")
    end)

    slotIndicatorsMenu:CreateCheckbox("Filled Gems", function()
        return characterConfig.ShowFilledGemIndicators ~= false
    end, function()
        ToggleCharacterSetting("ShowFilledGemIndicators")
    end)

    slotIndicatorsMenu:CreateCheckbox("Empty Sockets", function()
        return characterConfig.ShowEmptySocketIndicators ~= false
    end, function()
        ToggleCharacterSetting("ShowEmptySocketIndicators")
    end)

    slotIndicatorsMenu:CreateCheckbox("No Socket", function()
        return characterConfig.ShowNoSocketIndicators ~= false
    end, function()
        ToggleCharacterSetting("ShowNoSocketIndicators")
    end)

    slotIndicatorsMenu:CreateCheckbox("No Item", function()
        return characterConfig.ShowNoItemIndicators ~= false
    end, function()
        ToggleCharacterSetting("ShowNoItemIndicators")
    end)

    slotIndicatorsMenu:CreateCheckbox("Indicator Text", function()
        return characterConfig.ShowIndicatorText == true
    end, function()
        ToggleCharacterSetting("ShowIndicatorText")
    end)

    slotIndicatorsMenu:CreateCheckbox("Missing Text", function()
        return characterConfig.ShowMissingIndicatorText == true
    end, function()
        ToggleCharacterSetting("ShowMissingIndicatorText")
    end)

    rootDescription:CreateCheckbox("Health (Total)", function()
        return characterConfig.ShowHealthTotal ~= false
    end, function()
        ToggleCharacterSetting("ShowHealthTotal")
    end)

    rootDescription:CreateCheckbox("Mana (Total)", function()
        return characterConfig.ShowManaTotal ~= false
    end, function()
        ToggleCharacterSetting("ShowManaTotal")
    end)
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function Skins:CreateCharacterPanelSettingsButton()
    if not CharacterFrame then
        return
    end

    local moduleState = GetModuleState()
    local button = moduleState.settingsButton

    if not button then
        button = RefineUI.CreateSettingsButton(CharacterFrame, SETTINGS_BUTTON_NAME, SETTINGS_BUTTON_SIZE, "GM-icon-settings")
        moduleState.settingsButton = button

        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Character Panel Settings", 1, 1, 1)
            GameTooltip:Show()
        end)

        button:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        button:SetScript("OnMouseDown", function(self)
            if InCombatLockdown and InCombatLockdown() then
                return
            end
            local menuUtil = MenuUtil or _G.MenuUtil
            if not (menuUtil and menuUtil.CreateContextMenu) then
                return
            end
            menuUtil.CreateContextMenu(self, BuildCharacterPanelMenu)
        end)
    end

    button:SetParent(CharacterFrame)
    button:ClearAllPoints()
    if CharacterFrame.CloseButton then
        button:SetPoint("RIGHT", CharacterFrame.CloseButton, "LEFT", -4, 0)
    else
        button:SetPoint("TOPRIGHT", CharacterFrame, "TOPRIGHT", -30, -6)
    end
    button:SetFrameStrata("HIGH")
    button:SetFrameLevel((CharacterFrame:GetFrameLevel() or 1) + 20)
    RefineUI.EnsureSettingsButtonIcon(button, "GM-icon-settings")

    local skinsConfig = Config.Skins
    button:SetShown(not (skinsConfig and skinsConfig.Enable == false))
end

function Skins:RefreshItemLevel()
    if not (CharacterStatsPane and CharacterStatsPane.ItemLevelFrame) then
        return
    end
    PaperDollFrame_SetItemLevel(CharacterStatsPane.ItemLevelFrame, "player")
end

function Skins:RefreshSlotIndicators()
    local characterConfig = GetCharacterPanelConfig()
    local enabled = IsFeatureEnabled() and characterConfig.ShowSlotIndicators ~= false

    for i = 1, #SLOT_IDS do
        local slotID = SLOT_IDS[i]
        local slotFrame = GetSlotFrame(slotID)
        if slotFrame then
            EnsureCharacterSlotBorder(slotFrame)
            if enabled then
                RenderSlotIndicator(slotFrame, slotID, GetInventoryItemLink("player", slotID))
            else
                HideSlotIndicator(slotFrame)
            end
        end
    end
end

function Skins:RefreshCustomAttributes()
    if CharacterFrame and CharacterFrame:IsShown() and PaperDollFrame and PaperDollFrame:IsShown() and PaperDollFrame_UpdateStats then
        PaperDollFrame_UpdateStats()
    end
end

function Skins:RefreshCharacterPanel()
    InsertCustomAttributeStats()
    self:CreateCharacterPanelSettingsButton()
    self:RefreshItemLevel()
    self:RefreshSlotIndicators()
    self:RefreshCustomAttributes()
    ApplyCharacterPanelTextStyle()
end

function Skins:SetupCharacterPanel()
    if setupComplete then
        return
    end
    setupComplete = true

    InsertCustomAttributeStats()

    RefineUI:HookOnce(HOOK_KEY.ITEM_LEVEL, "PaperDollFrame_SetItemLevel", function(statFrame, unit)
        ApplyCurrentMaxItemLevel(statFrame, unit)
    end)

    RefineUI:HookOnce(HOOK_KEY.SLOT_UPDATE, "PaperDollItemSlotButton_Update", function(slotFrame)
        local slotID = slotIdByFrame[slotFrame]
        if not slotID and slotFrame and slotFrame.GetID then
            local id = slotFrame:GetID()
            if SLOT_FRAME_NAME_BY_ID[id] then
                slotID = id
                slotIdByFrame[slotFrame] = id
            end
        end
        if slotID and SLOT_FRAME_NAME_BY_ID[slotID] then
            QueueCharacterRefresh()
        end
    end)

    RefineUI:HookOnce(HOOK_KEY.STATS_UPDATE, "PaperDollFrame_UpdateStats", function()
        ApplyCharacterPanelTextStyle()
    end)

    if CharacterFrame then
        RefineUI:HookScriptOnce(HOOK_KEY.CHARACTER_ON_SHOW, CharacterFrame, "OnShow", function()
            QueueCharacterRefresh()
        end)
    end

    if not eventsRegistered then
        eventsRegistered = true

        RefineUI:RegisterEventCallback("PLAYER_ENTERING_WORLD", function()
            QueueCharacterRefresh()
        end, EVENT_KEY.PLAYER_ENTERING_WORLD)

        RefineUI:RegisterEventCallback("PLAYER_EQUIPMENT_CHANGED", function()
            QueueCharacterRefresh()
        end, EVENT_KEY.PLAYER_EQUIPMENT_CHANGED)

        RefineUI:RegisterEventCallback("UNIT_INVENTORY_CHANGED", function(_, unit)
            if unit == "player" then
                QueueCharacterRefresh()
            end
        end, EVENT_KEY.UNIT_INVENTORY_CHANGED)

        RefineUI:RegisterEventCallback("SOCKET_INFO_UPDATE", function()
            QueueCharacterRefresh()
        end, EVENT_KEY.SOCKET_INFO_UPDATE)

        RefineUI:RegisterEventCallback("SPELL_POWER_CHANGED", function(_, unit)
            if unit == "player" then
                QueueCharacterRefresh()
            end
        end, EVENT_KEY.SPELL_POWER_CHANGED)

        RefineUI:RegisterEventCallback("UNIT_MAXHEALTH", function(_, unit)
            if unit == "player" then
                QueueCharacterRefresh()
            end
        end, EVENT_KEY.UNIT_MAXHEALTH)
    end

    QueueCharacterRefresh()
end
