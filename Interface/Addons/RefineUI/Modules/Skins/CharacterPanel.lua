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
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local type = type
local pairs = pairs
local wipe = wipe
local floor = math.floor
local max = math.max
local min = math.min
local format = string.format
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
    SLOT_UPDATE = COMPONENT_KEY .. ":Hook:PaperDollItemSlotButton_Update",
    CHARACTER_ON_HIDE = COMPONENT_KEY .. ":Hook:CharacterFrame:OnHide",
    STATS_UPDATE = COMPONENT_KEY .. ":Hook:PaperDollFrame_UpdateStats",
}

local EVENT_KEY = {
    UNIT_INVENTORY_CHANGED = COMPONENT_KEY .. ":Event:UNIT_INVENTORY_CHANGED",
    SOCKET_INFO_UPDATE = COMPONENT_KEY .. ":Event:SOCKET_INFO_UPDATE",
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

local EQUIP_LOC_NO_OFFHAND_ENCHANT = {
    INVTYPE_SHIELD = true,
    INVTYPE_HOLDABLE = true,
}

local STAMINA_LABEL = format(STAT_FORMAT, _G["SPELL_STAT" .. LE_UNIT_STAT_STAMINA .. "_NAME"])
local HEALTH_LABEL = format(STAT_FORMAT, "Health")
local MANA_LABEL = format(STAT_FORMAT, "Mana")
local MANA_TOOLTIP = HIGHLIGHT_FONT_COLOR_CODE .. format(PAPERDOLLFRAME_TOOLTIP_FORMAT, "Mana") .. " "
local REFINE_GOLD_COLOR = "|cffffd200"
local COLOR_RESET = "|r"
local ITEM_LEVEL_SEPARATOR = "|TInterface\\Common\\Indicator-Yellow:8:8:0:0|t"
local ITEM_LEVEL_HEADER_CURRENT = "Current"
local ITEM_LEVEL_HEADER_MAX = "Max"

local INDICATOR_SIZE = 12
local INDICATOR_SPACING = 2
local INDICATOR_SIDE_OFFSET = 4
local INDICATOR_TEXT_OFFSET = 4
local INDICATOR_TEXT_WIDTH = 110
local INDICATOR_TEXT_MAX_CHARS = 28
local INDICATOR_MAX_GEMS = 3
local INDICATOR_MAX_ENTRIES = INDICATOR_MAX_GEMS + 1
-- READY_CHECK_NOT_READY_TEXTURE's atlas; empty sockets use the art Blizzard's item tooltips use.
local MISSING_ENCHANT_ATLAS = "UI-LFG-DeclineMark"
local EMPTY_SOCKET_TEXTURE = "Interface\\ItemSocketingFrame\\UI-EmptySocket-%s"

local SETTINGS_BUTTON_NAME = "RefineUICharacterPanelSettingsButton"
local SETTINGS_BUTTON_SIZE = 32

----------------------------------------------------------------------------------------
-- State / Registries
----------------------------------------------------------------------------------------
RefineUI:CreateDataRegistry(STATE_REGISTRY, "k")

local setupComplete = false
local slotFrameByID = {}
local slotIDByFrame = {}
-- Item links carry enchant and gem IDs, so an unchanged link means unchanged indicators.
local renderedLinkBySlot = {}
local styledFontStrings = {}

-- Stat overrides are visual only: Blizzard's text is captured after each PaperDollFrame_UpdateStats
-- so it can be restored, and Blizzard's stat tables and frame fields are never written.
local blizzardItemLevelText
local staminaFrame
local blizzardStaminaValue
local statOverridesApplied = false
local manaRow

local function GetState(owner)
    local state = RefineUI:RegistryGet(STATE_REGISTRY, owner)
    if type(state) ~= "table" then
        state = {}
        RefineUI:RegistrySet(STATE_REGISTRY, owner, nil, state)
    end
    return state
end

----------------------------------------------------------------------------------------
-- Config Helpers
----------------------------------------------------------------------------------------
local function GetCharacterPanelConfig()
    return Skins:GetCharacterPanelConfig()
end

local function IsFeatureEnabled()
    return Skins:IsCharacterPanelEnabled()
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

-- Blizzard never resets these fonts (stat frames are pooled and reused), so style each once.
local function ApplyStyledFont(fontString)
    if styledFontStrings[fontString] then
        return
    end
    styledFontStrings[fontString] = true

    local fontPath, fontSize, fontFlags = fontString:GetFont()
    fontString:SetFont(fontPath, fontSize, BuildOutlinedFlag(fontFlags))
    fontString:SetShadowColor(0, 0, 0, 1)
    fontString:SetShadowOffset(1, -1)
end

local function FormatCurrentMaxItemLevelText(currentItemLevel, maxItemLevel)
    local currentText = FormatItemLevelValue(currentItemLevel)
    local maxText = FormatItemLevelValue(maxItemLevel)
    local maxColored = REFINE_GOLD_COLOR .. maxText .. COLOR_RESET
    return currentText .. "  " .. ITEM_LEVEL_SEPARATOR .. " " .. maxColored
end

local function HideItemLevelHeaderLabels(statFrame)
    local state = GetState(statFrame)
    if state.currentHeader then
        state.currentHeader:Hide()
    end
    if state.maxHeader then
        state.maxHeader:Hide()
    end
end

local function EnsureItemLevelHeaderLabels(statFrame)
    local state = GetState(statFrame)
    if state.currentHeader and state.maxHeader then
        return state
    end

    local currentHeader = statFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    local maxHeader = statFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    RefineUI.Font(currentHeader, 8, nil, "OUTLINE")
    RefineUI.Font(maxHeader, 8, nil, "OUTLINE")
    ApplyStyledFont(currentHeader)
    ApplyStyledFont(maxHeader)

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

local function ApplyCategoryTitleStyle(categoryFrame)
    ApplyStyledFont(categoryFrame.Title)
    categoryFrame.Title:SetTextColor(1, 0.82, 0, 1)
end

local function ApplyCharacterPanelTextStyle()
    ApplyStyledFont(CharacterStatsPane.ItemLevelFrame.Value)
    ApplyCategoryTitleStyle(CharacterStatsPane.ItemLevelCategory)
    ApplyCategoryTitleStyle(CharacterStatsPane.AttributesCategory)
    ApplyCategoryTitleStyle(CharacterStatsPane.EnhancementsCategory)

    for statFrame in CharacterStatsPane.statsFramePool:EnumerateActive() do
        ApplyStyledFont(statFrame.Label)
        ApplyStyledFont(statFrame.Value)
    end
end

----------------------------------------------------------------------------------------
-- Item Level
----------------------------------------------------------------------------------------
-- Blizzard's own tooltip already lists equipped and maximum item level; only the text changes.
local function UpdateItemLevelText()
    local statFrame = CharacterStatsPane.ItemLevelFrame
    if not (IsFeatureEnabled() and GetCharacterPanelConfig().ShowCurrentMaxItemLevel ~= false) then
        statFrame.Value:SetText(blizzardItemLevelText)
        HideItemLevelHeaderLabels(statFrame)
        return
    end

    local avgItemLevel, avgItemLevelEquipped = GetAverageItemLevel()
    local currentItemLevel = max(C_PaperDollInfo.GetMinItemLevel() or 0, avgItemLevelEquipped)
    statFrame.Value:SetText(FormatCurrentMaxItemLevelText(currentItemLevel, avgItemLevel))

    local state = EnsureItemLevelHeaderLabels(statFrame)
    state.currentHeader:Show()
    state.maxHeader:Show()
end

----------------------------------------------------------------------------------------
-- Health / Mana
----------------------------------------------------------------------------------------
-- The Stamina row is relabelled as Health (Blizzard's Stamina tooltip already explains the
-- health it grants), and an addon-owned Mana row is spliced in below it.
local function FindStatFrameAnchoredTo(anchor)
    local enhancementsCategory = CharacterStatsPane.EnhancementsCategory
    local _, relativeTo = enhancementsCategory:GetPoint(1)
    if relativeTo == anchor then
        return enhancementsCategory
    end

    for statFrame in CharacterStatsPane.statsFramePool:EnumerateActive() do
        _, relativeTo = statFrame:GetPoint(1)
        if relativeTo == anchor then
            return statFrame
        end
    end
end

-- Re-anchors the row below `from` onto `to`, then flips the alternating backgrounds of the
-- remaining Attributes rows to account for the inserted or removed Mana row.
local function MoveRowsBelow(from, to)
    local statFrame = FindStatFrameAnchoredTo(from)
    if not statFrame then
        return
    end

    local point, _, relativePoint, x, y = statFrame:GetPoint(1)
    statFrame:SetPoint(point, to, relativePoint, x, y)

    while statFrame and statFrame ~= CharacterStatsPane.EnhancementsCategory do
        statFrame.Background:SetShown(not statFrame.Background:IsShown())
        statFrame = FindStatFrameAnchoredTo(statFrame)
    end
end

local function CreateManaRow()
    manaRow = CreateFrame("Frame", nil, CharacterStatsPane, "CharacterStatFrameTemplate")
    manaRow.Label:SetText(MANA_LABEL)
    manaRow.tooltip2 = STAT_MANA_TOOLTIP
    ApplyStyledFont(manaRow.Label)
    ApplyStyledFont(manaRow.Value)
    manaRow:Hide()
end

local function ShowManaRow(maxMana)
    if not manaRow then
        CreateManaRow()
    end

    local manaText = BreakUpLargeNumbers(maxMana)
    manaRow.Value:SetText(manaText)
    manaRow.tooltip = MANA_TOOLTIP .. manaText .. FONT_COLOR_CODE_CLOSE
    manaRow.Background:SetShown(not staminaFrame.Background:IsShown())

    MoveRowsBelow(staminaFrame, manaRow)
    manaRow:SetPoint("TOP", staminaFrame, "BOTTOM", 0, 0)
    manaRow:Show()
end

local function HideManaRow()
    if not (manaRow and manaRow:IsShown()) then
        return
    end

    MoveRowsBelow(manaRow, staminaFrame)
    manaRow:Hide()
    manaRow:ClearAllPoints()
end

local function UpdateStatOverrides()
    UpdateItemLevelText()

    local enabled = IsFeatureEnabled()
    if not staminaFrame or enabled == statOverridesApplied then
        return
    end
    statOverridesApplied = enabled

    if enabled then
        staminaFrame.Label:SetText(HEALTH_LABEL)
        staminaFrame.Value:SetText(BreakUpLargeNumbers(UnitHealthMax("player")))

        local maxMana = UnitPowerMax("player", Enum.PowerType.Mana)
        if maxMana > 0 then
            ShowManaRow(maxMana)
        end
    else
        staminaFrame.Label:SetText(STAMINA_LABEL)
        staminaFrame.Value:SetText(blizzardStaminaValue)
        HideManaRow()
    end
end

local function OnStatsUpdated()
    ApplyCharacterPanelTextStyle()

    -- Blizzard just rebuilt the layout, so any previous Mana splice is gone.
    if manaRow then
        manaRow:Hide()
        manaRow:ClearAllPoints()
    end
    statOverridesApplied = false
    blizzardItemLevelText = CharacterStatsPane.ItemLevelFrame.Value:GetText()

    staminaFrame = nil
    for statFrame in CharacterStatsPane.statsFramePool:EnumerateActive() do
        if statFrame.Label:GetText() == STAMINA_LABEL then
            staminaFrame = statFrame
            blizzardStaminaValue = statFrame.Value:GetText()
            break
        end
    end

    UpdateStatOverrides()
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

    if not itemLink then
        return true
    end

    local equipLoc = select(4, C_Item.GetItemInfoInstant(itemLink))
    return not EQUIP_LOC_NO_OFFHAND_ENCHANT[equipLoc]
end

local function GetSlotDetails(slotID, itemLink)
    local details = {
        hasEnchant = false,
        enchantText = nil,
        socketCount = 0,
        sockets = {},
    }

    local tooltipData = C_TooltipInfo.GetInventoryItem("player", slotID)
    local lines = tooltipData and tooltipData.lines
    if not lines then
        return details
    end

    for i = 1, #lines do
        local line = lines[i]
        if line.type == Enum.TooltipDataLineType.ItemEnchantmentPermanent then
            details.hasEnchant = true
            details.enchantText = NormalizeDisplayText(line.leftText or line.rightText)
        elseif line.type == Enum.TooltipDataLineType.GemSocket then
            local socketIndex = details.socketCount + 1
            details.socketCount = socketIndex
            local socketInfo = {
                icon = line.gemIcon,
                socketType = line.socketType,
                text = line.leftText,
            }

            if socketInfo.icon then
                local _, gemLink = C_Item.GetItemGem(itemLink, socketIndex)
                if gemLink ~= "" then
                    socketInfo.link = gemLink
                end
            end

            details.sockets[socketIndex] = socketInfo
        end
    end

    return details
end

local function OnIndicatorEnter(self)
    if not (self.tooltipLink or self.tooltipText) then
        return
    end

    GameTooltip:SetOwner(self, self.tooltipAnchor)
    if self.tooltipLink then
        GameTooltip:SetHyperlink(self.tooltipLink)
    else
        GameTooltip:SetText(self.tooltipText, 1, 1, 1)
        GameTooltip:Show()
    end
end

local function CreateIndicatorEntry(container, anchor, placement, offset)
    local entry = CreateFrame("Frame", nil, container)
    entry:SetSize(INDICATOR_SIZE, INDICATOR_SIZE)
    entry:EnableMouse(true)
    if placement == "LEFT" then
        entry:SetPoint("RIGHT", anchor, "LEFT", -offset, 0)
        entry.tooltipAnchor = "ANCHOR_LEFT"
    else
        entry:SetPoint("LEFT", anchor, "RIGHT", offset, 0)
        entry.tooltipAnchor = "ANCHOR_RIGHT"
    end

    entry.icon = entry:CreateTexture(nil, "ARTWORK")
    entry.icon:SetAllPoints()

    entry:SetScript("OnEnter", OnIndicatorEnter)
    entry:SetScript("OnLeave", GameTooltip_Hide)
    entry:Hide()
    return entry
end

-- Marks sit in one row beside the slot, growing toward the character model.
local function EnsureSlotIndicator(slotFrame, slotID)
    local state = GetState(slotFrame)
    if state.container then
        return state
    end

    local placement = SLOT_PLACEMENT_BY_ID[slotID]
    local container = CreateFrame("Frame", nil, slotFrame)
    container:SetAllPoints()
    container:SetFrameLevel(slotFrame:GetFrameLevel() + 8)

    local entries = {}
    local anchor, offset = slotFrame, INDICATOR_SIDE_OFFSET
    for i = 1, INDICATOR_MAX_ENTRIES do
        entries[i] = CreateIndicatorEntry(container, anchor, placement, offset)
        anchor, offset = entries[i], INDICATOR_SPACING
    end

    local enchantText = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    RefineUI.Font(enchantText, 8, nil, "OUTLINE")
    enchantText:SetWidth(INDICATOR_TEXT_WIDTH)
    enchantText:SetWordWrap(false)
    enchantText:SetJustifyH(placement == "LEFT" and "RIGHT" or "LEFT")
    enchantText:SetTextColor(GREEN_FONT_COLOR:GetRGB())

    state.container = container
    state.entries = entries
    state.enchantText = enchantText
    state.placement = placement
    return state
end

local function SetIndicatorEntry(entry, texture, texCoordInset, tooltipLink, tooltipText)
    entry.icon:SetTexture(texture)
    entry.icon:SetTexCoord(texCoordInset, 1 - texCoordInset, texCoordInset, 1 - texCoordInset)
    entry.tooltipLink = tooltipLink
    entry.tooltipText = tooltipText
    entry:Show()
end

local function LayoutEnchantText(state, slotFrame, markCount)
    local text = state.enchantText
    local anchor = markCount > 0 and state.entries[markCount] or slotFrame
    local offset = markCount > 0 and INDICATOR_TEXT_OFFSET or INDICATOR_SIDE_OFFSET
    text:ClearAllPoints()
    if state.placement == "LEFT" then
        text:SetPoint("RIGHT", anchor, "LEFT", -offset, 0)
    else
        text:SetPoint("LEFT", anchor, "RIGHT", offset, 0)
    end
end

-- Only actionable states get a mark: missing enchant, filled gem, empty socket.
local function RenderSlotIndicator(slotFrame, slotID, itemLink)
    local characterConfig = GetCharacterPanelConfig()
    if not itemLink or not IsFeatureEnabled() or characterConfig.ShowSlotIndicators == false then
        local container = GetState(slotFrame).container
        if container then
            container:Hide()
        end
        return
    end

    local state = EnsureSlotIndicator(slotFrame, slotID)
    local entries = state.entries
    local details = GetSlotDetails(slotID, itemLink)
    local markCount = 0

    if characterConfig.ShowEnchantIndicators ~= false and not details.hasEnchant and IsEnchantEligible(slotID, itemLink) then
        markCount = 1
        entries[1].icon:SetAtlas(MISSING_ENCHANT_ATLAS)
        entries[1].tooltipLink = nil
        entries[1].tooltipText = "Missing enchant"
        entries[1]:Show()
    end

    for i = 1, min(details.socketCount, INDICATOR_MAX_GEMS) do
        local socket = details.sockets[i]
        if socket.icon then
            if characterConfig.ShowFilledGemIndicators ~= false then
                markCount = markCount + 1
                SetIndicatorEntry(entries[markCount], socket.icon, 0.08, socket.link, socket.text)
            end
        elseif characterConfig.ShowEmptySocketIndicators ~= false then
            markCount = markCount + 1
            SetIndicatorEntry(entries[markCount], format(EMPTY_SOCKET_TEXTURE, socket.socketType or "Prismatic"), 0, nil, socket.text)
        end
    end

    for i = markCount + 1, INDICATOR_MAX_ENTRIES do
        entries[i]:Hide()
    end

    local enchantText = characterConfig.ShowIndicatorText == true and details.enchantText or nil
    if enchantText then
        state.enchantText:SetText(enchantText)
        LayoutEnchantText(state, slotFrame, markCount)
    end
    state.enchantText:SetShown(enchantText ~= nil)

    state.container:SetShown(markCount > 0 or enchantText ~= nil)
end

-- PaperDollItemSlotButton_Update also runs on every BAG_UPDATE_COOLDOWN (each GCD) while
-- the panel is open, so skip the tooltip scan unless the slot's link changed.
local function UpdateSlotIndicator(slotFrame, slotID)
    local itemLink = GetInventoryItemLink("player", slotID)
    local renderKey = itemLink or false
    if renderedLinkBySlot[slotID] == renderKey then
        return
    end
    renderedLinkBySlot[slotID] = renderKey
    RenderSlotIndicator(slotFrame, slotID, itemLink)
end

local function RefreshSlotIndicators()
    if not PaperDollFrame:IsVisible() then
        return
    end
    for slotID, slotFrame in pairs(slotFrameByID) do
        UpdateSlotIndicator(slotFrame, slotID)
    end
end

----------------------------------------------------------------------------------------
-- Settings Menu
----------------------------------------------------------------------------------------
local function RefreshCharacterPanel()
    wipe(renderedLinkBySlot)
    RefreshSlotIndicators()
    UpdateStatOverrides()
end

local function ToggleCharacterSetting(flagKey)
    local characterConfig = GetCharacterPanelConfig()
    characterConfig[flagKey] = not (characterConfig[flagKey] ~= false)
    RefreshCharacterPanel()
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

    slotIndicatorsMenu:CreateCheckbox("Missing Enchants", function()
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

    slotIndicatorsMenu:CreateCheckbox("Enchant Names", function()
        return characterConfig.ShowIndicatorText == true
    end, function()
        ToggleCharacterSetting("ShowIndicatorText")
    end)
end

local function CreateSettingsButton()
    local button = RefineUI.CreateSettingsButton(CharacterFrame, SETTINGS_BUTTON_NAME, SETTINGS_BUTTON_SIZE, "GM-icon-settings")

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Character Panel Settings", 1, 1, 1)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    button:SetScript("OnMouseDown", function(self)
        if InCombatLockdown() then
            return
        end
        MenuUtil.CreateContextMenu(self, BuildCharacterPanelMenu)
    end)

    button:SetPoint("RIGHT", CharacterFrame.CloseButton, "LEFT", -4, 0)
    button:SetFrameStrata("HIGH")
    button:SetFrameLevel(CharacterFrame:GetFrameLevel() + 20)
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function Skins:SetupCharacterPanel()
    if setupComplete then
        return
    end
    setupComplete = true

    for slotID, frameName in pairs(SLOT_FRAME_NAME_BY_ID) do
        local slotFrame = _G[frameName]
        slotFrameByID[slotID] = slotFrame
        slotIDByFrame[slotFrame] = slotID
        -- Shared with the Borders module, which colors this border by item quality.
        RefineUI.CreateBorder(slotFrame, 5, 5, 12)
    end

    CreateSettingsButton()

    RefineUI:HookOnce(HOOK_KEY.STATS_UPDATE, "PaperDollFrame_UpdateStats", OnStatsUpdated)

    RefineUI:HookOnce(HOOK_KEY.SLOT_UPDATE, "PaperDollItemSlotButton_Update", function(slotFrame)
        local slotID = slotIDByFrame[slotFrame]
        if slotID then
            UpdateSlotIndicator(slotFrame, slotID)
        end
    end)

    -- Re-render every slot on the next open, so a scan made before item data arrived self-heals.
    RefineUI:HookScriptOnce(HOOK_KEY.CHARACTER_ON_HIDE, CharacterFrame, "OnHide", function()
        wipe(renderedLinkBySlot)
    end)

    -- Covers enchants and gems applied to already-equipped items.
    RefineUI:RegisterEventCallback("UNIT_INVENTORY_CHANGED", function(_, unit)
        if unit == "player" then
            RefreshSlotIndicators()
        end
    end, EVENT_KEY.UNIT_INVENTORY_CHANGED)

    RefineUI:RegisterEventCallback("SOCKET_INFO_UPDATE", RefreshSlotIndicators, EVENT_KEY.SOCKET_INFO_UPDATE)
end
