local R, C, L = unpack(RefineUI)

----------------------------------------------------------------------------------------
--	Based on aTooltip(by ALZA)
----------------------------------------------------------------------------------------

-- Localize frequently used globals/functions for perf (hot paths)
local _G = _G
local UIParent = UIParent
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local IsShiftKeyDown = IsShiftKeyDown
local UnitExists = UnitExists
local UnitIsPlayer = UnitIsPlayer
local UnitClass = UnitClass
local UnitIsTapDenied = UnitIsTapDenied
local UnitIsDead = UnitIsDead
local UnitReaction = UnitReaction
local UnitHealth = UnitHealth
local UnitLevel = UnitLevel
local GetCreatureDifficultyColor = GetCreatureDifficultyColor
local UnitCreatureType = UnitCreatureType
local UnitFactionGroup = UnitFactionGroup
local UnitName = UnitName
local UnitRace = UnitRace
local UnitClassification = UnitClassification
local UnitIsBattlePetCompanion = UnitIsBattlePetCompanion
local GetGuildInfo = GetGuildInfo
local UnitIsInMyGuild = UnitIsInMyGuild
local GetCVar = GetCVar
local GetTime = GetTime
local TooltipDataProcessor = TooltipDataProcessor
local Enum_TooltipDataType_Unit = Enum.TooltipDataType.Unit
local GameTooltip = GameTooltip
local GameTooltipStatusBar = GameTooltipStatusBar
local FACTION = _G.FACTION_BAR_COLORS

local function hex255(x) return math.floor((x or 1) * 255 + 0.5) end

-- Safer access: StoryTooltip might not exist depending on load timing
local StoryTooltip = QuestScrollFrame and QuestScrollFrame.StoryTooltip
if StoryTooltip then StoryTooltip:SetFrameLevel(4) end

local anchor = CreateFrame("Frame", "TooltipAnchor", UIParent)
anchor:SetSize(200, 40)

-- Check if C.position.tooltip is defined before unpacking
if C.position.tooltip then
    anchor:SetPoint(unpack(C.position.tooltip))
else
    -- Fallback position if C.position.tooltip is nil
    local MinimapFrame = rawget(_G, 'Minimap') or UIParent
    anchor:SetPoint("BOTTOM", MinimapFrame, "TOP")
end

-- Lazy cache tooltip line font strings, but only cache when the FS actually exists
local TL = setmetatable({}, {
    __index = function(t, i)
        local fs = _G["GameTooltipTextLeft" .. i]
        if fs then rawset(t, i, fs) end
        return fs
    end
})

local function GameTooltipDefault(tooltip, parent)
    if C.tooltip.cursor == true then
        tooltip:SetOwner(parent, "ANCHOR_CURSOR_RIGHT", 10, 10)
    else
        tooltip:SetOwner(parent, "ANCHOR_NONE")
        tooltip:ClearAllPoints()
        tooltip:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
        tooltip.default = 1
    end
    if InCombatLockdown() and C.tooltip.hideCombat and not IsShiftKeyDown() then
        tooltip:Hide()
    end
end
hooksecurefunc("GameTooltip_SetDefaultAnchor", GameTooltipDefault)


-- Strip PvP line without mutating globals
local function StripPvpLine(tt)
    local n = tt:NumLines() or 0
    for i = 2, n do
        local fs = TL[i]
        local txt = fs and fs:GetText()
        if txt == PVP_ENABLED then
            if fs then fs:SetText("") end
            break
        end
    end
end

-- Statusbar
GameTooltipStatusBar:SetStatusBarTexture(C.media.texture)
GameTooltipStatusBar:ClearAllPoints()
GameTooltipStatusBar:SetPoint("BOTTOMLEFT", GameTooltip, "BOTTOMLEFT", 4, 4)
GameTooltipStatusBar:SetPoint("BOTTOMRIGHT", GameTooltip, "BOTTOMRIGHT", -4, 4)
GameTooltipStatusBar:SetHeight(4) -- Adjust this value to make the bar shorter or taller

-- Initialize status bar text once (move creation out of hot path)
if not GameTooltipStatusBar.text then
    local sbText = GameTooltipStatusBar:CreateFontString(nil, "OVERLAY")
    sbText:SetFont(C.media.normalFont, 12, "OUTLINE")
    sbText:SetPoint("CENTER", GameTooltipStatusBar, 0, 0)
    GameTooltipStatusBar.text = sbText
    GameTooltipStatusBar:SetStatusBarColor(0, 1, 0)
end

----------------------------------------------------------------------------------------
--	Unit tooltip styling
----------------------------------------------------------------------------------------
local function GetColor(unit)
    if not unit then return end
    local r, g, b

    if UnitIsPlayer(unit) then
        local _, classToken = UnitClass(unit)
        local classColors = rawget(_G, 'CUSTOM_CLASS_COLORS') or rawget(_G, 'RAID_CLASS_COLORS')
        local color = classColors and classColors[classToken]
        if color then
            r, g, b = color.r, color.g, color.b
        else
            r, g, b = 1, 1, 1
        end
    elseif UnitIsTapDenied(unit) or UnitIsDead(unit) then
        r, g, b = 0.6, 0.6, 0.6
    else
        local idx = UnitReaction(unit, "player")
        local reactions = R and R.oUF_colors and R.oUF_colors.reaction
        local reaction = reactions and reactions[idx]
        if reaction then
            r, g, b = reaction[1], reaction[2], reaction[3]
        else
            local bc = FACTION and FACTION[idx]
            if bc then
                r, g, b = bc.r, bc.g, bc.b
            else
                r, g, b = 1, 1, 1
            end
        end
    end

    return r, g, b
end

GameTooltipStatusBar:SetScript("OnValueChanged", function(self, value)
    if not value then return end
    local now = GetTime()
    if (self.__next or 0) > now then return end
    self.__next = now + 1 / 30 -- 30 Hz cap

    local minV, maxV = self:GetMinMaxValues()
    if (value < minV) or (value > maxV) or value == self.__last then return end
    self.__last = value

    local _, unit = GameTooltip:GetUnit()
    if unit and self.text then
        self.text:Show()
        self.text:SetText(R.ShortValue(UnitHealth(unit)))
    elseif self.text then
        self.text:Hide()
    end
end)

-- Reset throttle state when tooltip hides to avoid stale caps carrying over
GameTooltip:HookScript("OnHide", function()
    if GameTooltipStatusBar then
        GameTooltipStatusBar.__next = nil
        GameTooltipStatusBar.__last = nil
        if GameTooltipStatusBar.text then GameTooltipStatusBar.text:Hide() end
    end
end)


local function UpdatePlayerTooltip(self, unit, lines, levelColor, race, englishRace, classificationRaw, faction,
                                   playerFaction)
    if UnitIsAFK(unit) then
        self:AppendText((" %s"):format("|cffE7E716" .. L_CHAT_AFK .. "|r"))
    elseif UnitIsDND(unit) then
        self:AppendText((" %s"):format("|cffFF0000" .. L_CHAT_DND .. "|r"))
    end

    if (englishRace == "Pandaren" or englishRace == "Dracthyr") and faction and faction ~= playerFaction then
        local hex = (faction == "Alliance") and "cff69ccf0" or "cffff3333"
        self:AppendText((" [|%s%s|r]"):format(hex, faction:sub(1, 2)))
    end

    local guildName = GetGuildInfo(unit)
    if guildName then
        local line2 = TL[2]
        if line2 then
            line2:SetFormattedText("%s", guildName)
            if UnitIsInMyGuild(unit) then
                line2:SetTextColor(1, 1, 0)
            else
                line2:SetTextColor(0, 1, 1)
            end
        end
    end

    local n = guildName and 3 or 2
    if GetCVar("colorblindMode") == "1" then
        n = n + 1
        local className = UnitClass(unit)
        local targetLine = TL[n]
        if targetLine then
            targetLine:SetFormattedText(
                "|cff%02x%02x%02x%s|r %s %s",
                hex255(levelColor.r), hex255(levelColor.g), hex255(levelColor.b),
                self.__LevelText(unit, classificationRaw),
                race or UNKNOWN,
                className or ""
            )
        end
    else
        local targetLine = TL[n]
        if targetLine then
            targetLine:SetFormattedText(
                "|cff%02x%02x%02x%s|r %s",
                hex255(levelColor.r), hex255(levelColor.g), hex255(levelColor.b),
                self.__LevelText(unit, classificationRaw),
                race or UNKNOWN
            )
        end
    end

    for i = n + 1, lines do
        local line = TL[i]
        if not line then break end
        local txt = line:GetText()
        if not txt then break end
        if txt == FACTION_HORDE or txt == FACTION_ALLIANCE then
            line:SetText()
            break
        end
    end
end

local function UpdateNPCTooltip(self, unit, lines, levelColor, creatureType, classificationSuffix)
    local patternLevel = LEVEL and ("^" .. LEVEL) or nil
    local patternType = creatureType and ("^" .. creatureType) or nil
    for i = 2, lines do
        local line = TL[i]
        if not line or UnitIsBattlePetCompanion(unit) then break end
        local txt = line:GetText()
        if not txt then break end
        if (patternLevel and txt:find(patternLevel)) or (patternType and txt:find(patternType)) then
            line:SetFormattedText(
                "|cff%02x%02x%02x%s%s|r %s",
                hex255(levelColor.r), hex255(levelColor.g), hex255(levelColor.b),
                self.__LevelText(unit),
                classificationSuffix,
                creatureType or ""
            )
            break
        end
    end
end

local OnTooltipSetUnit = function(self)
    if self ~= GameTooltip or (self.IsForbidden and self:IsForbidden()) then return end

    -- Defensive: tooltip data must exist
    local tooltipData = self:GetTooltipData()
    if not tooltipData or not tooltipData.lines then return end

    local lines = self:NumLines() or 0
    local unit = (select(2, self:GetUnit())) or (UnitExists("mouseover") and "mouseover") or nil
    if not unit then return end

    -- Strip PvP line safely
    StripPvpLine(self)

    local name, realm = UnitName(unit)
    local race, englishRace = UnitRace(unit)
    local level = UnitLevel(unit)
    local levelColor = GetCreatureDifficultyColor(level)
    local classificationRaw = UnitClassification(unit)
    local creatureType = UnitCreatureType(unit)
    local _, faction = UnitFactionGroup(unit)
    local _, playerFaction = UnitFactionGroup("player")
    local isPlayer = UnitIsPlayer(unit)

    -- Provide a LevelText method on the tooltip for helper functions
    self.__LevelText = function(_, _unit, _classificationRaw)
        local lvl = level -- capture numeric
        local classification = _classificationRaw or classificationRaw
        if lvl and lvl == -1 then
            if classification == "worldboss" then
                return "|cffff0000" .. (ENCOUNTER_JOURNAL_ENCOUNTER or "Boss") .. "|r"
            else
                return "|cffff0000??|r"
            end
        end
        return tostring(lvl or "")
    end

    local r, g, b = GetColor(unit)
    local titleLine = TL[1]
    if titleLine then
        titleLine:SetFormattedText("|cff%02x%02x%02x%s|r", hex255(r), hex255(g), hex255(b), name or "")
    end

    if realm and realm ~= "" and C.tooltip.realm then
        self:AddLine(FRIENDS_LIST_REALM .. "|cffffffff" .. realm .. "|r")
    end

    -- Map classification to display suffix (keep raw for boss checks)
    local classificationSuffix
    if classificationRaw == "rareelite" then
        classificationSuffix = " R+"
    elseif classificationRaw == "rare" then
        classificationSuffix = " R"
    elseif classificationRaw == "elite" then
        classificationSuffix = "+"
    else
        classificationSuffix = ""
    end

    if isPlayer then
        UpdatePlayerTooltip(self, unit, lines, levelColor, race, englishRace, classificationRaw, faction, playerFaction)
    else
        UpdateNPCTooltip(self, unit, lines, levelColor, creatureType, classificationSuffix)
    end
end

TooltipDataProcessor.AddTooltipPostCall(Enum_TooltipDataType_Unit, OnTooltipSetUnit)

----------------------------------------------------------------------------------------
--	Hide tooltips in combat for action bars, pet bar and stance bar
----------------------------------------------------------------------------------------

local CombatHideActionButtonsTooltip = function(self)
    if (InCombatLockdown()) then
        self:Hide()
    end
end

-- Hook into the SetAction, SetPetAction, and SetShapeshift functions
hooksecurefunc(GameTooltip, "SetAction", CombatHideActionButtonsTooltip)
hooksecurefunc(GameTooltip, "SetPetAction", CombatHideActionButtonsTooltip)
hooksecurefunc(GameTooltip, "SetShapeshift", CombatHideActionButtonsTooltip)

-- Add a new hook for item tooltips
hooksecurefunc(GameTooltip, "SetInventoryItem", CombatHideActionButtonsTooltip)


----------------------------------------------------------------------------------------
--	Fix compare tooltips(by Blizzard)(../FrameXML/GameTooltip.lua)
----------------------------------------------------------------------------------------
hooksecurefunc(TooltipComparisonManager, "AnchorShoppingTooltips", function(self, primaryShown, secondaryItemShown)
    local tooltip = self.tooltip;
    local shoppingTooltip1 = tooltip.shoppingTooltips[1];
    local shoppingTooltip2 = tooltip.shoppingTooltips[2];
    local point = shoppingTooltip1:GetPoint(2)
    if secondaryItemShown then
        if point == "TOP" then
            shoppingTooltip1:ClearAllPoints()
            shoppingTooltip2:ClearAllPoints()
            shoppingTooltip1:SetPoint("TOPLEFT", self.anchorFrame, "TOPRIGHT", 3, -10)
            shoppingTooltip2:SetPoint("TOPLEFT", shoppingTooltip1, "TOPRIGHT", 3, 0)
        elseif point == "RIGHT" then
            shoppingTooltip1:ClearAllPoints()
            shoppingTooltip2:ClearAllPoints()
            shoppingTooltip1:SetPoint("TOPRIGHT", self.anchorFrame, "TOPLEFT", -3, -10)
            shoppingTooltip2:SetPoint("TOPRIGHT", shoppingTooltip1, "TOPLEFT", -3, 0)
        end
    else
        if point == "LEFT" then
            shoppingTooltip1:ClearAllPoints()
            shoppingTooltip1:SetPoint("TOPLEFT", self.anchorFrame, "TOPRIGHT", 3, -10)
        elseif point == "RIGHT" then
            shoppingTooltip1:ClearAllPoints()
            shoppingTooltip1:SetPoint("TOPRIGHT", self.anchorFrame, "TOPLEFT", -3, -10)
        end
    end
end)

----------------------------------------------------------------------------------------
--	Fix GameTooltipMoneyFrame font size
----------------------------------------------------------------------------------------
local function SkinMoneyFrame(prefix)
    if _G[prefix] then
        local pre = _G[prefix .. "PrefixText"]
        local suf = _G[prefix .. "SuffixText"]
        local gold = _G[prefix .. "GoldButton"]
        local silver = _G[prefix .. "SilverButton"]
        local copper = _G[prefix .. "CopperButton"]
        if pre then pre:SetFontObject("GameTooltipText") end
        if suf then suf:SetFontObject("GameTooltipText") end
        if gold then gold:SetNormalFontObject("GameTooltipText") end
        if silver then silver:SetNormalFontObject("GameTooltipText") end
        if copper then copper:SetNormalFontObject("GameTooltipText") end
    end
end

hooksecurefunc("SetTooltipMoney", function()
    for i = 1, 2 do
        SkinMoneyFrame("GameTooltipMoneyFrame" .. i)
        SkinMoneyFrame("ShoppingTooltip1MoneyFrame" .. i)
    end
    -- Custom tooltip from MultiItemRef.lua
    SkinMoneyFrame("ItemRefTooltipMoneyFrame1")
    for i = 2, 4 do
        SkinMoneyFrame("ItemRefTooltip" .. i .. "MoneyFrame1")
    end
end)

----------------------------------------------------------------------------------------
--	Skin GameTooltip.ItemTooltip and EmbeddedItemTooltip
----------------------------------------------------------------------------------------
local function SkinItemTooltipIcon(itemTooltip)
    if not itemTooltip or itemTooltip._refineSkinned then return end
    if itemTooltip.Icon then
        itemTooltip.Icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    end
    itemTooltip:CreateBackdrop("Default")
    if itemTooltip.Icon then
        itemTooltip.backdrop:SetPoint("TOPLEFT", itemTooltip.Icon, "TOPLEFT", -2, 2)
        itemTooltip.backdrop:SetPoint("BOTTOMRIGHT", itemTooltip.Icon, "BOTTOMRIGHT", 2, -2)
    end
    if itemTooltip.Count and itemTooltip.Icon then
        itemTooltip.Count:ClearAllPoints()
        itemTooltip.Count:SetPoint("BOTTOMRIGHT", itemTooltip.Icon, "BOTTOMRIGHT", 1, 0)
    end
    if itemTooltip.IconBorder then
        hooksecurefunc(itemTooltip.IconBorder, "SetVertexColor", function(self, r, g, b)
            self:GetParent().backdrop:SetBackdropBorderColor(r, g, b)
            self:SetTexture("")
        end)
        hooksecurefunc(itemTooltip.IconBorder, "Hide", function(self)
            self:GetParent().backdrop:SetBackdropBorderColor(unpack(C.media.borderColor))
        end)
    end
    itemTooltip._refineSkinned = true
end

-- Apply skins
SkinItemTooltipIcon(GameTooltip and rawget(GameTooltip, 'ItemTooltip'))
SkinItemTooltipIcon(EmbeddedItemTooltip and EmbeddedItemTooltip.ItemTooltip)

BONUS_OBJECTIVE_REWARD_FORMAT = "|T%1$s:16:16:0:0:64:64:5:59:5:59|t %2$s"
BONUS_OBJECTIVE_REWARD_WITH_COUNT_FORMAT = "|T%1$s:16:16:0:0:64:64:5:59:5:59|t |cffffffff%2$d|r %3$s"

hooksecurefunc("GameTooltip_ShowProgressBar", function(tt)
    if not tt or (tt.IsForbidden and tt:IsForbidden()) or not tt.progressBarPool then return end

    local frame = tt.progressBarPool:GetNextActive()
    if (not frame or not frame.Bar) or frame.Bar.backdrop then return end

    local bar = frame.Bar
    local label = bar.Label
    if bar then
        bar:StripTextures()
        bar:CreateBackdrop("Transparent")
        bar.backdrop:SetBackdropColor(0.1, 0.1, 0.1, 1)
        bar:SetStatusBarTexture(C.media.texture)
        label:ClearAllPoints()
        label:SetPoint("CENTER", bar, 0, 0)
        label:SetDrawLayer("OVERLAY")
        label:SetFont(C.media.normalFont, C.media.normalFontSize, C.media.normalFontStyle)
    end
end)

hooksecurefunc("GameTooltip_ShowStatusBar", function(tt)
    if not tt or (tt.IsForbidden and tt:IsForbidden()) or not tt.statusBarPool then return end

    local frame = tt.statusBarPool:GetNextActive()

    if frame and not frame.backdrop then
        frame:StripTextures()
        frame:CreateBackdrop("Transparent")
        frame.backdrop:SetBackdropColor(0.1, 0.1, 0.1, 1)
        frame:SetStatusBarTexture(C.media.texture)
    end
end)
