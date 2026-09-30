----------------------------------------------------------------------------------------
-- MicroMenu for RefineUI
-- Description: Ports RefineUI_OLD's MicroMenu with integrated status info.
----------------------------------------------------------------------------------------

local AddOnName, RefineUI = ...
local MicroMenu = RefineUI:RegisterModule("MicroMenu")

local _G = _G
local unpack = unpack
local ipairs = ipairs
local pairs = pairs
local format = string.format
local floor = math.floor
local ceil = math.ceil
local GOLD_R, GOLD_G, GOLD_B = 1, 0.82, 0

-- Small constants to avoid magic numbers
local MAX_GUILD_TOOLTIP_LIST = 30
local MAX_FRIENDS_TOOLTIP_LIST = 20
local GV_TOTAL_SLOTS = 9
local BUTTON_SPACING = -2
local TIMER_KEY = {
    SUPPRESS_DEFAULT_BUTTONS = "MicroMenu:SuppressDefaultButtons",
}

-- Layout order; hidden buttons are skipped. StoreMicroButton is removed in OnEnable.
local MICRO_BUTTON_ORDER = {
    "CharacterMicroButton",
    "RefineDurabilityMicroButton",
    "RefineBagsMicroButton",
    "ProfessionMicroButton",
    "PlayerSpellsMicroButton",
    "AchievementMicroButton",
    "RefineGreatVaultMicroButton",
    "QuestLogMicroButton",
    "HousingMicroButton",
    "GuildMicroButton",
    "RefineFriendsMicroButton",
    "LFDMicroButton",
    "CollectionsMicroButton",
    "EJMicroButton",
    "MainMenuMicroButton",
    "HelpMicroButton",
}
local layoutButtons = {}

-- Unified disable predicate for micro buttons
local function IsQuickKeybindMode()
    return type(_G.KeybindFrames_InQuickKeybindMode) == "function" and _G.KeybindFrames_InQuickKeybindMode()
end

local function MicroButtons_ShouldDisable()
    if _G.GameMenuFrame and _G.GameMenuFrame:IsShown() then return true end
    if IsQuickKeybindMode() then return true end
    return false
end

-- =========================
-- Tooltip style
-- =========================
-- Matches Blizzard micro button tooltips: white title with gold keybind, gold section
-- headers, white primary text, gray secondary text.
local RAID_CLASS_COLORS = (rawget(_G, 'CUSTOM_CLASS_COLORS') or _G.RAID_CLASS_COLORS)
local HEADER_COLOR = _G.NORMAL_FONT_COLOR
local TEXT_COLOR = _G.HIGHLIGHT_FONT_COLOR
local SUBTEXT_COLOR = _G.GRAY_FONT_COLOR
local AFK_ICON = "|TInterface\\FriendsFrame\\StatusIcon-Away:14:14|t "
local DND_ICON = "|TInterface\\FriendsFrame\\StatusIcon-DnD:14:14|t "
-- Item/currency icon with the default border cropped, followed by its name.
local ICON_TEXT = "|T%s:14:14:0:0:64:64:4:60:4:60|t %s"

local function SetTooltipTitle(owner, text)
    local tooltip = _G.GameTooltip
    tooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local command = owner.cfg.commandName
    GameTooltip_SetTitle(tooltip, command and MicroButtonTooltipText(text, command) or text)
end

-- Section headers get a hairline divider in the gap below them; completion bars sit on
-- blank lines. Both are created on first use, reused across hovers, and hidden when the
-- tooltip clears. Dividers live on the tooltip below its text layer.
local HEADER_RULE_FROM, HEADER_RULE_TO = CreateColor(1, 1, 1, 0.25), CreateColor(1, 1, 1, 0.05)
local BAR_HEIGHT = 6
local BAR_MIN_TOOLTIP_WIDTH = 200
local headerRules, numHeaderRules = {}, 0
local tooltipBars, numTooltipBars = {}, 0

local function HideTooltipExtras(tooltip)
    for i = 1, numHeaderRules do
        headerRules[i]:Hide()
    end
    if numTooltipBars > 0 then
        for i = 1, numTooltipBars do
            tooltipBars[i]:Hide()
        end
        tooltip:SetMinimumWidth(0)
    end
    numHeaderRules, numTooltipBars = 0, 0
end

local function AddHeaderRule(tooltip, line)
    numHeaderRules = numHeaderRules + 1
    local rule = headerRules[numHeaderRules]
    if not rule then
        RefineUI:HookScriptOnce("MicroMenu:GameTooltip:OnTooltipCleared", tooltip, "OnTooltipCleared", HideTooltipExtras)
        rule = tooltip:CreateTexture(nil, "BORDER")
        rule:SetColorTexture(1, 1, 1)
        rule:SetGradient("HORIZONTAL", HEADER_RULE_FROM, HEADER_RULE_TO)
        rule:SetHeight(1)
        headerRules[numHeaderRules] = rule
    end
    rule:ClearAllPoints()
    rule:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, -1)
    rule:SetPoint("RIGHT", tooltip, "RIGHT", -10, 0)
    rule:Show()
end

local function AddTooltipHeader(text, count)
    local tooltip = _G.GameTooltip
    GameTooltip_AddBlankLineToTooltip(tooltip)
    tooltip:AddDoubleLine(text, count, HEADER_COLOR.r, HEADER_COLOR.g, HEADER_COLOR.b, HEADER_COLOR.r, HEADER_COLOR.g, HEADER_COLOR.b)
    AddHeaderRule(tooltip, tooltip:GetLeftLine(tooltip:NumLines()))
end

local function AddTooltipRow(left, right, leftColor, rightColor)
    leftColor, rightColor = leftColor or TEXT_COLOR, rightColor or SUBTEXT_COLOR
    _G.GameTooltip:AddDoubleLine(left, right, leftColor.r, leftColor.g, leftColor.b, rightColor.r, rightColor.g, rightColor.b)
end

-- A label/count row followed by a thin bar on its own blank line, so the bar never
-- overlaps tooltip text.
local function AddTooltipBar(tooltip, label, value, maxValue)
    tooltip:AddDoubleLine(label, BreakUpLargeNumbers(value) .. " / " .. BreakUpLargeNumbers(maxValue),
        TEXT_COLOR.r, TEXT_COLOR.g, TEXT_COLOR.b, TEXT_COLOR.r, TEXT_COLOR.g, TEXT_COLOR.b)
    tooltip:AddLine(" ")
    numTooltipBars = numTooltipBars + 1
    local bar = tooltipBars[numTooltipBars]
    if not bar then
        RefineUI:HookScriptOnce("MicroMenu:GameTooltip:OnTooltipCleared", tooltip, "OnTooltipCleared", HideTooltipExtras)
        bar = CreateFrame("StatusBar", nil, tooltip)
        bar:SetHeight(BAR_HEIGHT)
        bar:SetStatusBarTexture(RefineUI.Media.Textures.Smooth)
        bar:SetStatusBarColor(GOLD_R, GOLD_G, GOLD_B)
        local track = bar:CreateTexture(nil, "BACKGROUND")
        track:SetAllPoints()
        track:SetColorTexture(1, 1, 1, 0.1)
        tooltipBars[numTooltipBars] = bar
    end
    bar:ClearAllPoints()
    bar:SetPoint("LEFT", tooltip:GetLeftLine(tooltip:NumLines()), "LEFT")
    bar:SetPoint("RIGHT", tooltip, "RIGHT", -10, 0)
    bar:SetMinMaxValues(0, maxValue)
    bar:SetValue(value)
    bar:Show()
    tooltip:SetMinimumWidth(BAR_MIN_TOOLTIP_WIDTH)
end

local function AddTooltipNote(text)
    _G.GameTooltip:AddLine(text, SUBTEXT_COLOR.r, SUBTEXT_COLOR.g, SUBTEXT_COLOR.b)
end

-- Gray footer naming what a right click does.
local function AddRightClickHint(tooltip, action)
    GameTooltip_AddBlankLineToTooltip(tooltip)
    AddTooltipNote("Right-click: " .. action)
end

local function StatusIcon(isAFK, isDND)
    return isAFK and AFK_ICON or isDND and DND_ICON or ""
end

local function ColorText(color, text)
    return format("|cff%02x%02x%02x%s|r", color.r * 255, color.g * 255, color.b * 255, text)
end

-- Friend APIs return localized class names; RAID_CLASS_COLORS is keyed by class file.
local classFileByName
local function GetClassFileByName(className)
    if not classFileByName then
        classFileByName = {}
        for file, name in pairs(LocalizedClassList(false)) do classFileByName[name] = file end
        for file, name in pairs(LocalizedClassList(true)) do classFileByName[name] = file end
    end
    return className and classFileByName[className]
end

local function ClassColor(classFile)
    return classFile and RAID_CLASS_COLORS[classFile] or TEXT_COLOR
end

-- Markup strings are cached so hovering only concatenates.
local classIcons = {}
local function ClassIcon(classFile)
    if not classFile then return "" end
    local icon = classIcons[classFile]
    if not icon then
        icon = CreateAtlasMarkup(GetClassAtlas(classFile:lower()), 14, 14) .. " "
        classIcons[classFile] = icon
    end
    return icon
end

-- Unknown or empty clients fall back to the Battle.net app icon.
local clientIcons = {}
local function ClientIcon(client)
    client = client or ""
    local icon = clientIcons[client]
    if not icon then
        icon = BNet_GetClientEmbeddedAtlas(client, 14) .. " "
        clientIcons[client] = icon
    end
    return icon
end

-- =========================
-- Guild online overlay
-- =========================
local function SortByRankIndex(a, b)
    return a.rankIndex < b.rankIndex
end

-- Member rows are reused across hovers.
local guildMemberPool, onlineMembers = {}, {}
local function GetOnlineGuildMembers()
    wipe(onlineMembers)
    local numTotalMembers, numOnlineMembers = GetNumGuildMembers()
    for i = 1, numTotalMembers do
        local name, rank, rankIndex, _, _, _, _, _, online, status, class = GetGuildRosterInfo(i)
        if online then
            local n = #onlineMembers + 1
            local member = guildMemberPool[n]
            if not member then
                member = {}
                guildMemberPool[n] = member
            end
            member.name, member.rank, member.rankIndex, member.status, member.class = Ambiguate(name, "guild"), rank, rankIndex, status, class
            onlineMembers[n] = member
        end
    end
    table.sort(onlineMembers, SortByRankIndex)
    return onlineMembers, numOnlineMembers
end

local function RequestGuildRosterUpdate()
    if IsInGuild() then
        C_GuildInfo.GuildRoster()
    end
end

local guildCountText

local function GetOverlayFrame(button)
    if not button.OverlayFrame then
        button.OverlayFrame = CreateFrame("Frame", nil, button)
        button.OverlayFrame:SetAllPoints()
        button.OverlayFrame:SetFrameStrata("HIGH")
        button.OverlayFrame:SetFrameLevel(100)
    end
    return button.OverlayFrame
end

local function UpdateGuildOnlineCount()
    local numOnline = 0
    if IsInGuild() then
        local _, online = GetNumGuildMembers()
        numOnline = online or 0
    end
    guildCountText:SetText(numOnline > 0 and numOnline or "")
end

local function Guild_AppendTooltip()
    if not IsInGuild() then return end
    local onlineMembers, numOnlineMembers = GetOnlineGuildMembers()
    AddTooltipHeader("Online", numOnlineMembers)
    for i, member in ipairs(onlineMembers) do
        if i > MAX_GUILD_TOOLTIP_LIST then
            AddTooltipNote(format("+%d more", numOnlineMembers - MAX_GUILD_TOOLTIP_LIST))
            break
        end
        local name = StatusIcon(member.status == 1, member.status == 2) .. ClassIcon(member.class) .. member.name
        AddTooltipRow(name, member.rank, ClassColor(member.class))
    end
end

-- =========================
-- Base micro button mixin/factory
-- =========================
local ExtraMicroButtons = {}

local RefineMicroButtonMixin = CreateFromMixins(_G.MainMenuBarMicroButtonMixin)

function RefineMicroButtonMixin:OnLoadCommon(cfg)
    self.cfg = cfg
    self:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    for _, e in ipairs(cfg.events) do
        self:RegisterEvent(e)
    end

    -- The template's OnMouseDown pushes the button; resync once the click has acted.
    self:SetScript("OnClick", function(_, btn)
        cfg.onClick(self, btn)
        self:UpdateMicroButton()
    end)
    self:SetScript("OnEvent", cfg.update)
    self:SetScript("OnEnter", function()
        self.IconHighlight:Show()
        cfg.onEnter(self)
    end)
    self:SetScript("OnLeave", function()
        self.IconHighlight:Hide()
        _G.GameTooltip:Hide()
    end)
    self.Background = self:CreateTexture(nil, "BACKGROUND")
    self.PushedBackground = self:CreateTexture(nil, "BACKGROUND"); self.PushedBackground:Hide()
    self.Background:SetAtlas(cfg.bgAtlasUp or "UI-HUD-MicroMenu-Character-Up", true)
    self.PushedBackground:SetAtlas(cfg.bgAtlasDown or "UI-HUD-MicroMenu-Character-Down", true)
    self:SetHighlightAtlas("UI-HUD-MicroMenu-Button-Highlight")

    self.Icon = self:CreateTexture(nil, "ARTWORK")
    if cfg.iconAtlas then self.Icon:SetAtlas(cfg.iconAtlas) else self.Icon:SetTexture(cfg.iconPath) end
    self.Icon:SetPoint("CENTER", self, "CENTER", cfg.iconX or 0, cfg.iconY or 2)
    self.Icon:SetSize(cfg.iconSize or 24, cfg.iconSize or 24)

    self.IconHighlight = self:CreateTexture(nil, "OVERLAY")
    if cfg.iconAtlas then self.IconHighlight:SetAtlas(cfg.iconAtlas) else self.IconHighlight:SetTexture(cfg.iconPath) end
    self.IconHighlight:SetAllPoints(self.Icon)
    self.IconHighlight:SetBlendMode("ADD")
    self.IconHighlight:SetAlpha(0.35)
    self.IconHighlight:Hide()

    self.Text = GetOverlayFrame(self):CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.Text:SetFont(RefineUI.Media.Fonts.Default, cfg.text.size, "OUTLINE")
    self.Text:SetPoint("BOTTOM", cfg.text.x, 2)

    self:UpdateMicroButton()
    cfg.update(self)
end

function RefineMicroButtonMixin:SetNormal()
    self.Background:Show(); self.PushedBackground:Hide()
    self.Icon:SetVertexColor(1, 1, 1)
    if not self.cfg.customIconPos then
        self.Icon:ClearAllPoints(); self.Icon:SetPoint("CENTER", self, "CENTER", 0, 2)
    end
    self:SetButtonState("NORMAL", true)
end

function RefineMicroButtonMixin:SetPushed()
    self.Background:Hide(); self.PushedBackground:Show()
    self.Icon:SetVertexColor(0.5, 0.5, 0.5)
    if not self.cfg.customIconPos then
        self.Icon:ClearAllPoints(); self.Icon:SetPoint("CENTER", self, "CENTER", 1, 1)
    end
    self:SetButtonState("PUSHED", true)
end

function RefineMicroButtonMixin:EnableButton()
    self:SetAlpha(1)
    self:Enable(); self.Icon:SetDesaturated(false); self.Icon:SetAlpha(1)
    self.Text:SetAlpha(1)
end

function RefineMicroButtonMixin:DisableButton()
    self:SetAlpha(0.5)
    self:Disable(); self.Icon:SetDesaturated(true); self.Icon:SetAlpha(0.5)
    self.Text:SetAlpha(0.5)
end

-- Visual state only; data text refreshes from each button's own events.
function RefineMicroButtonMixin:UpdateMicroButton()
    local active = self.cfg.isActive and self.cfg.isActive(self)
    if active then self:SetPushed() else self:SetNormal() end
    if MicroButtons_ShouldDisable() then self:DisableButton() else self:EnableButton() end
end

local function CreateRefineMicroButton(name, cfg)
    local parent = _G.MicroMenu
    local b = CreateFrame("Button", name, parent, "MainMenuBarMicroButton")
    Mixin(b, RefineMicroButtonMixin); b:OnLoadCommon(cfg)
    b:SetFrameLevel(parent:GetFrameLevel() + 1)
    b:EnableMouse(true); b:Show()
    ExtraMicroButtons[#ExtraMicroButtons + 1] = b
    return b
end

-- =========================
-- Skinning Logic (RefineUI Style)
-- =========================
local function MicroButton_OnEnter(self)
    if self.border then
        self.border:SetBackdropBorderColor(GOLD_R, GOLD_G, GOLD_B)
    end
end

local function MicroButton_OnLeave(self)
    if self.border then
        local color = RefineUI.Config and RefineUI.Config.General and RefineUI.Config.General.BorderColor
        if color then
            self.border:SetBackdropBorderColor(unpack(color))
        else
            self.border:SetBackdropBorderColor(0.3, 0.3, 0.3)
        end
    end
end

local function SkinMicroButtons()
    for _, name in ipairs(MICRO_BUTTON_ORDER) do
        local button = _G[name]
        if button then
            RefineUI.CreateBorder(button, 0, 0, 12)
            button:HookScript("OnEnter", MicroButton_OnEnter)
            button:HookScript("OnLeave", MicroButton_OnLeave)
        end
    end
end

-- =========================
-- Layout
-- =========================
-- Runs after Blizzard's grid layout (also used by the vehicle/pet battle override bar).
-- Sizing MicroMenu lets Blizzard size MicroMenuContainer, the Edit Mode selection,
-- and the queue status anchor with its own scale math.
local function MicroMenu_OnLayout(self)
    local count = 0
    for _, name in ipairs(MICRO_BUTTON_ORDER) do
        local b = _G[name]
        if b and b:IsShown() then
            count = count + 1
            layoutButtons[count] = b
        end
    end
    if count == 0 then return end

    -- isStacked is only reset by the next override, so honor it only while overridden.
    local stacked = self.isStacked and self:GetParent() ~= _G.MicroMenuContainer
    local perRow = stacked and ceil(count / 2) or count
    local width, rowWidth, height, rowStart, prev = 0, 0, 0, nil, nil
    for i = 1, count do
        local b = layoutButtons[i]
        layoutButtons[i] = nil
        b:ClearAllPoints()
        if not prev then
            b:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
            rowStart, height = b, b:GetHeight()
        elseif (i - 1) % perRow == 0 then
            b:SetPoint("TOPLEFT", rowStart, "BOTTOMLEFT", 0, BUTTON_SPACING)
            rowStart, rowWidth = b, 0
            height = height + BUTTON_SPACING + b:GetHeight()
        else
            b:SetPoint("TOPLEFT", prev, "TOPRIGHT", BUTTON_SPACING, 0)
        end
        rowWidth = rowWidth + b:GetWidth() + (rowWidth > 0 and BUTTON_SPACING or 0)
        if rowWidth > width then width = rowWidth end
        prev = b
    end

    self:SetSize(width, height)
end

-- =========================
-- Friends
-- =========================
-- Battle.net rows follow the friends list: blue account name, class-colored character
-- when in this game, zone or rich presence on the right.
local function Friends_OnEnter(self)
    SetTooltipTitle(self, _G.SOCIAL_BUTTON)

    local numBNet, numBNetOnline = BNGetNumFriends()
    numBNetOnline = numBNetOnline or 0
    local numWoWOnline = C_FriendList.GetNumOnlineFriends() or 0

    if numBNetOnline > 0 then
        AddTooltipHeader(ClientIcon() .. "Battle.net", numBNetOnline)
        local listed = 0
        for i = 1, numBNet or 0 do
            local acc = C_BattleNet.GetFriendAccountInfo(i)
            local game = acc and acc.gameAccountInfo
            if game and game.isOnline then
                if listed == MAX_FRIENDS_TOOLTIP_LIST then
                    AddTooltipNote(format("+%d more", numBNetOnline - listed))
                    break
                end
                local left = StatusIcon(acc.isAFK or game.isGameAFK, acc.isDND or game.isGameBusy) .. ClientIcon(game.clientProgram) .. (acc.accountName or "")
                local right = game.richPresence or ""
                if game.clientProgram == BNET_CLIENT_WOW and game.wowProjectID == WOW_PROJECT_ID and game.characterName then
                    local classFile = GetClassFileByName(game.className)
                    left = left .. " " .. ClassIcon(classFile) .. ColorText(ClassColor(classFile), game.characterName)
                    right = game.areaName or right
                end
                AddTooltipRow(left, right, _G.FRIENDS_BNET_NAME_COLOR)
                listed = listed + 1
            end
        end
    end

    if numWoWOnline > 0 then
        AddTooltipHeader(ClientIcon(BNET_CLIENT_WOW) .. "World of Warcraft", numWoWOnline)
        local listed = 0
        for i = 1, C_FriendList.GetNumFriends() or 0 do
            local info = C_FriendList.GetFriendInfoByIndex(i)
            if info and info.connected then
                if listed == MAX_FRIENDS_TOOLTIP_LIST then
                    AddTooltipNote(format("+%d more", numWoWOnline - listed))
                    break
                end
                local classFile = GetClassFileByName(info.className)
                AddTooltipRow(StatusIcon(info.afk, info.dnd) .. ClassIcon(classFile) .. info.name, info.area or "", ClassColor(classFile))
                listed = listed + 1
            end
        end
    end

    if numBNetOnline + numWoWOnline == 0 then
        GameTooltip_AddBlankLineToTooltip(_G.GameTooltip)
        AddTooltipNote("No friends online")
    end
    _G.GameTooltip:Show()
end

local function Friends_Update(self)
    local _, bnetOnline = BNGetNumFriends()
    local total = (bnetOnline or 0) + (C_FriendList.GetNumOnlineFriends() or 0)
    self.Text:SetText(total > 0 and total or "")
end

-- =========================
-- Great Vault
-- =========================
-- Rows follow the vault's own order (raid, dungeons, world).
local GV_RAID = Enum.WeeklyRewardChestThresholdType.Raid
local GV_DUNGEONS = Enum.WeeklyRewardChestThresholdType.Activities
local GV_WORLD = Enum.WeeklyRewardChestThresholdType.World
local GV_PVP = Enum.WeeklyRewardChestThresholdType.RankedPvP
local RAID_ICON = CreateAtlasMarkup("questlog-questtypeicon-raid", 14, 14) .. " "
local DUNGEON_ICON = CreateAtlasMarkup("questlog-questtypeicon-dungeon", 14, 14) .. " "
local GV_TYPES = {
    { type = GV_RAID, label = RAID_ICON .. "Raid" },
    { type = GV_DUNGEONS, label = DUNGEON_ICON .. "Dungeons" },
    { type = GV_WORLD, label = CreateAtlasMarkup("questlog-questtypeicon-delves", 14, 14) .. " World" },
    { type = GV_PVP, label = CreateAtlasMarkup("questlog-questtypeicon-pvp", 14, 14) .. " Rated PvP" },
}
local GV_SLOT_UNLOCKED = CreateAtlasMarkup("common-icon-checkmark", 14, 14)
local GV_SLOT_LOCKED = CreateAtlasMarkup("ui-journeys-greatvault-lock", 14, 14)

-- Reward level of an unlocked slot, as WeeklyRewardsActivityMixin:SetProgressText shows it.
local function GV_SlotLabel(activity)
    local level = activity.level
    if activity.type == GV_RAID then
        return DifficultyUtil.GetDifficultyName(level) or ""
    elseif activity.type == GV_DUNGEONS then
        if C_WeeklyRewards.GetDifficultyIDForActivityTier(activity.activityTierID) == DifficultyUtil.ID.DungeonHeroic then
            return _G.WEEKLY_REWARDS_HEROIC
        end
        return format(_G.WEEKLY_REWARDS_MYTHIC, level)
    elseif activity.type == GV_PVP then
        return PVPUtil.GetTierName(level) or ""
    end
    return format(_G.GREAT_VAULT_WORLD_TIER, level)
end

-- One row per track: progress toward the next slot in gray, unlocked reward levels and
-- slot checkmarks on the right.
local function GV_OnEnter(self)
    local tooltip = _G.GameTooltip
    SetTooltipTitle(self, _G.GREAT_VAULT_REWARDS)
    if C_WeeklyRewards.HasAvailableRewards() then
        local color = _G.GREEN_FONT_COLOR
        tooltip:AddLine(_G.WEEKLY_REWARDS_RETURN_TO_CLAIM, color.r, color.g, color.b, true)
    end
    GameTooltip_AddBlankLineToTooltip(tooltip)

    local activities = C_WeeklyRewards.GetActivities() or {}
    local shown = false
    for _, track in ipairs(GV_TYPES) do
        local total, progress, nextThreshold, levels, slots = 0, 0, nil, nil, ""
        for _, a in ipairs(activities) do
            if a.type == track.type then
                total = total + 1
                progress = a.progress
                if a.progress >= a.threshold then
                    local label = GV_SlotLabel(a)
                    levels = levels and (levels .. ", " .. label) or label
                    slots = slots .. GV_SLOT_UNLOCKED
                else
                    if not nextThreshold or a.threshold < nextThreshold then
                        nextThreshold = a.threshold
                    end
                    slots = slots .. GV_SLOT_LOCKED
                end
            end
        end
        if total > 0 then
            local left = track.label
            if nextThreshold then
                left = left .. "  " .. ColorText(SUBTEXT_COLOR, format("%d/%d", progress, nextThreshold))
            end
            AddTooltipRow(left, levels and (levels .. "  " .. slots) or slots, nil, nextThreshold and TEXT_COLOR or _G.GREEN_FONT_COLOR)
            shown = true
        end
    end

    if not shown then
        AddTooltipNote("No vault progress this week")
    end
    _G.GameTooltip:Show()
end

local function GV_Update(self)
    local unlockedCount = 0
    for _, activity in ipairs(C_WeeklyRewards.GetActivities() or {}) do
        if activity.progress >= activity.threshold then
            unlockedCount = unlockedCount + 1
        end
    end
    self.Text:SetText(unlockedCount .. "/" .. GV_TOTAL_SLOTS)
end

-- =========================
-- Durability
-- =========================
local function Durability_Overall()
    local totalCur, totalMax, lowest = 0, 0, 101
    for i = 1, 19 do if i ~= 4 then
        local cur, max = GetInventoryItemDurability(i)
        if cur and max and max > 0 then totalCur, totalMax = totalCur + cur, totalMax + max; local p = (cur/max)*100; if p < lowest then lowest = p end end
    end end
    if totalMax == 0 then return 100, 100 end
    return (totalCur/totalMax)*100, lowest
end

local function Durability_Update(self)
    local overall, lowest = Durability_Overall()
    self.Text:SetText(string.format("%.0f", overall))
    local r,g,b = 0.6,0.6,0.6
    if lowest < 20 then
        r,g,b = 1,0,0
    elseif lowest < 50 then
        r,g,b = 1,1,0
    elseif lowest <= 100 then
        r,g,b = 0,1,0
    end
    self.Text:SetTextColor(r,g,b)
end

-- Red at 0, yellow at half, green at 1.
local function GradientColor(p)
    if p >= 0.5 then
        local t = (p - 0.5) / 0.5
        return 1 - t, 1, 0
    else
        local t = p / 0.5
        return 1, t, 0
    end
end

local function SortByPct(a, b)
    return a.pct < b.pct
end

local function AddDurabilityRow(left, pct)
    local r, g, b = GradientColor(pct)
    _G.GameTooltip:AddDoubleLine(left, format("%.0f%%", pct * 100), TEXT_COLOR.r, TEXT_COLOR.g, TEXT_COLOR.b, r, g, b)
end

-- Overall first, then damaged items (lowest first) with their quality-colored names.
local function Durability_OnEnter(self)
    SetTooltipTitle(self, "Durability")
    GameTooltip_AddBlankLineToTooltip(_G.GameTooltip)
    AddDurabilityRow("Overall", Durability_Overall() / 100)

    local items = {}
    for slot = 1, 19 do
        if slot ~= 4 then
            local cur, max = GetInventoryItemDurability(slot)
            if cur and max and max > 0 and cur < max then
                local link = GetInventoryItemLink("player", slot)
                items[#items + 1] = {
                    pct = cur / max,
                    texture = GetInventoryItemTexture("player", slot) or 134400,
                    name = link and link:gsub("[%[%]]", "") or "",
                }
            end
        end
    end

    if #items > 0 then
        table.sort(items, SortByPct)
        GameTooltip_AddBlankLineToTooltip(_G.GameTooltip)
        for _, it in ipairs(items) do
            AddDurabilityRow(format(ICON_TEXT, it.texture, it.name), it.pct)
        end
    end
    _G.GameTooltip:Show()
end

-- =========================
-- Bags
-- =========================
local REAGENT_BAG = Enum.BagIndex.ReagentBag
local BACKPACK_ICON_TEXT = "|TInterface\\AddOns\\RefineUI\\Media\\Textures\\Backpack.blp:14:14|t %s"

-- Reagent bag slots only hold reagents, so the button counts the regular bags.
local function Bags_CountFree()
    local totalFree = 0
    for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do totalFree = totalFree + (C_Container.GetContainerNumFreeSlots(bag) or 0) end
    return totalFree
end

local function AddBagRow(bag)
    local slots = C_Container.GetContainerNumSlots(bag) or 0
    if slots == 0 then return end
    local free = C_Container.GetContainerNumFreeSlots(bag) or 0
    local name = C_Container.GetBagName(bag) or ""
    local left
    if bag == BACKPACK_CONTAINER then
        left = format(BACKPACK_ICON_TEXT, name)
    else
        left = format(ICON_TEXT, GetInventoryItemTexture("player", C_Container.ContainerIDToInventoryID(bag)) or 134400, name)
    end
    local r, g, b = GradientColor(free / slots)
    _G.GameTooltip:AddDoubleLine(left, free .. "/" .. slots, TEXT_COLOR.r, TEXT_COLOR.g, TEXT_COLOR.b, r, g, b)
end

-- Per-bag free slots, then gold and backpack-tracked currencies (the hidden bag bar's info).
local function Bags_OnEnter(self)
    local tooltip = _G.GameTooltip
    SetTooltipTitle(self, "Bags")
    GameTooltip_AddBlankLineToTooltip(tooltip)
    for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do AddBagRow(bag) end
    AddBagRow(REAGENT_BAG)

    GameTooltip_AddBlankLineToTooltip(tooltip)
    AddTooltipRow("Gold", GetMoneyString(GetMoney(), true), nil, TEXT_COLOR)
    local index = 1
    local currency = C_CurrencyInfo.GetBackpackCurrencyInfo(index)
    while currency do
        AddTooltipRow(format(ICON_TEXT, currency.iconFileID, currency.name), BreakUpLargeNumbers(currency.quantity), nil, TEXT_COLOR)
        index = index + 1
        currency = C_CurrencyInfo.GetBackpackCurrencyInfo(index)
    end
    tooltip:Show()
end

local function Bags_Update(self)
    local free = Bags_CountFree()
    self.Text:SetText(free)
    if free > 0 then
        self.Text:SetTextColor(1, 1, 1)
    else
        self.Text:SetTextColor(1, 0, 0)
    end
end

-- =========================
-- Character Item Level
-- =========================
local characterItemLevelText

-- Mirrors the character sheet (PaperDollFrame_SetItemLevel).
local function GetEquippedItemLevel()
    local _, avgItemLevelEquipped = GetAverageItemLevel()
    return floor(math.max(C_PaperDollInfo.GetMinItemLevel() or 0, avgItemLevelEquipped or 0))
end

local function UpdateCharacterItemLevel()
    local itemLevel = GetEquippedItemLevel()
    characterItemLevelText:SetText(itemLevel > 0 and itemLevel or "")
end

-- =========================
-- Blizzard button tooltips
-- =========================
-- Blizzard rebuilds these tooltips in EvaluateTooltipVisibility on enter, enable, and
-- disable, so a per-button post-hook keeps the appended lines through every rebuild.
-- Appending only adds lines; no Blizzard state is written.
local function AppendMicroTooltip(button, append)
    RefineUI:HookOnce("MicroMenu:" .. button:GetName() .. ":EvaluateTooltipVisibility", button, "EvaluateTooltipVisibility", function(self)
        local tooltip = _G.GameTooltip
        if self:IsEnabled() and tooltip:IsOwned(self) then
            append(tooltip)
            tooltip:Show()
        end
    end)
end

-- Character: item level, loot spec, and only the gear that needs attention.
local MISSING_ENCHANT_ICON = CreateAtlasMarkup("UI-LFG-DeclineMark", 14, 14) .. " "
local EMPTY_SOCKET_ICON = "|TInterface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic:14:14|t "
local GEAR_OK_ICON = CreateAtlasMarkup("common-icon-checkmark", 14, 14) .. " "

local function Character_AppendTooltip(tooltip)
    GameTooltip_AddBlankLineToTooltip(tooltip)
    AddTooltipRow("Item Level", GetEquippedItemLevel(), nil, TEXT_COLOR)

    local specID = GetLootSpecialization()
    if specID == 0 then
        specID = PlayerUtil.GetCurrentSpecID()
    end
    local _, specName, _, specIcon = GetSpecializationInfoByID(specID)
    if specName then
        AddTooltipRow("Loot Spec", format(ICON_TEXT, specIcon, specName), nil, TEXT_COLOR)
    end

    local isEnchantEligible = RefineUI:GetModule("Skins").IsEnchantEligible
    local issues = 0
    for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local missingEnchant = isEnchantEligible(slot, link) and link:match("item:%d+:(%d*)") == ""
            local numSockets = C_Item.GetItemNumSockets(link)
            local emptySockets = 0
            for i = 1, numSockets do
                if not C_Item.GetItemGemID(link, i) then emptySockets = emptySockets + 1 end
            end
            if missingEnchant or emptySockets > 0 then
                if issues == 0 then GameTooltip_AddBlankLineToTooltip(tooltip) end
                issues = issues + 1
                local problem = missingEnchant and (MISSING_ENCHANT_ICON .. "Enchant") or ""
                if emptySockets > 0 then
                    problem = problem .. (missingEnchant and "  " or "") .. EMPTY_SOCKET_ICON .. (emptySockets > 1 and emptySockets .. " Sockets" or "Socket")
                end
                AddTooltipRow(format(ICON_TEXT, GetInventoryItemTexture("player", slot), (link:gsub("[%[%]]", ""))), problem, nil, _G.RED_FONT_COLOR)
            end
        end
    end
    if issues == 0 then
        tooltip:AddLine(GEAR_OK_ICON .. "Enchants and gems complete", _G.GREEN_FONT_COLOR.r, _G.GREEN_FONT_COLOR.g, _G.GREEN_FONT_COLOR.b)
    end
    AddRightClickHint(tooltip, "Equipment sets")
end

-- Talents: the loadout the talent frame's dropdown would show, with the spec icon.
local function Talents_AppendTooltip(tooltip)
    local specID = PlayerUtil.GetCurrentSpecID()
    local _, _, _, specIcon = GetSpecializationInfoByID(specID)
    local loadout, color
    if C_ClassTalents.GetStarterBuildActive() then
        loadout, color = _G.TALENT_FRAME_DROP_DOWN_STARTER_BUILD, _G.BLUE_FONT_COLOR
    else
        local configID = C_ClassTalents.GetLastSelectedSavedConfigID(specID)
        local info = configID and C_Traits.GetConfigInfo(configID)
        if info then
            loadout, color = info.name, TEXT_COLOR
        else
            loadout, color = _G.TALENT_FRAME_DROP_DOWN_DEFAULT, SUBTEXT_COLOR
        end
    end
    GameTooltip_AddBlankLineToTooltip(tooltip)
    AddTooltipRow("Loadout", format(ICON_TEXT, specIcon, loadout), nil, color)
    AddRightClickHint(tooltip, "Talent loadouts")
end

-- Professions: skill for each, with concentration when the profession has it.
local function AddProfessionRow(tooltip, index)
    if not index then return end
    local name, icon, rank, maxRank, _, _, skillLine = GetProfessionInfo(index)
    local r, g, b = GradientColor(maxRank > 0 and rank / maxRank or 0)
    tooltip:AddDoubleLine(format(ICON_TEXT, icon, name), rank .. "/" .. maxRank, TEXT_COLOR.r, TEXT_COLOR.g, TEXT_COLOR.b, r, g, b)
    local currencyID = C_TradeSkillUI.GetConcentrationCurrencyID(skillLine)
    if currencyID ~= 0 then
        local currency = C_CurrencyInfo.GetCurrencyInfo(currencyID)
        AddTooltipRow("      Concentration", currency.quantity .. "/" .. currency.maxQuantity, SUBTEXT_COLOR, TEXT_COLOR)
    end
end

local function Professions_AppendTooltip(tooltip)
    local prof1, prof2, archaeology, fishing, cooking = GetProfessions()
    if not (prof1 or prof2 or archaeology or fishing or cooking) then return end
    GameTooltip_AddBlankLineToTooltip(tooltip)
    AddProfessionRow(tooltip, prof1)
    AddProfessionRow(tooltip, prof2)
    AddProfessionRow(tooltip, cooking)
    AddProfessionRow(tooltip, fishing)
    AddProfessionRow(tooltip, archaeology)
end

local ACHIEVEMENT_ICON = "|TInterface\\AchievementFrame\\UI-Achievement-TinyShield:14:14:0:0:32:32:0:20:0:20|t "

local function Achievements_AppendTooltip(tooltip)
    GameTooltip_AddBlankLineToTooltip(tooltip)
    AddTooltipRow(ACHIEVEMENT_ICON .. "Achievement Points", BreakUpLargeNumbers(GetTotalAchievementPoints()), nil, TEXT_COLOR)
end

-- Collections: mount and pet counts need full journal scans, so they are cached until the
-- journal changes. Toy counts match the Toy Box progress bar.
local mountCountsDirty = true
local ownedMounts, totalMounts = 0, 0
local petCountsDirty = true
local ownedSpecies, totalSpecies = 0, 0
local speciesOwned = {}

local function UpdateMountCounts()
    ownedMounts, totalMounts = 0, 0
    for _, mountID in ipairs(C_MountJournal.GetMountIDs()) do
        local _, _, _, _, _, _, _, _, _, hideOnChar, isCollected = C_MountJournal.GetMountInfoByID(mountID)
        if hideOnChar ~= true then
            totalMounts = totalMounts + 1
            if isCollected then ownedMounts = ownedMounts + 1 end
        end
    end
    mountCountsDirty = false
end

-- Unique species collected out of those the pet journal lists. The list follows the
-- journal's filters, so this only runs while they are at their defaults.
local function UpdatePetCounts()
    wipe(speciesOwned)
    ownedSpecies, totalSpecies = 0, 0
    for index = 1, C_PetJournal.GetNumPets() do
        local _, speciesID, isOwned = C_PetJournal.GetPetInfoByIndex(index)
        local seen = speciesOwned[speciesID]
        if seen == nil then
            totalSpecies = totalSpecies + 1
        end
        if isOwned and not seen then
            ownedSpecies = ownedSpecies + 1
        end
        speciesOwned[speciesID] = seen or isOwned
    end
    petCountsDirty = false
end

local function Collections_AppendTooltip(tooltip)
    if mountCountsDirty then UpdateMountCounts() end
    GameTooltip_AddBlankLineToTooltip(tooltip)
    if totalMounts > 0 then
        AddTooltipBar(tooltip, "Mounts", ownedMounts, totalMounts)
    end
    local totalToys = C_ToyBox.GetNumTotalDisplayedToys()
    if totalToys > 0 then
        AddTooltipBar(tooltip, "Toys", C_ToyBox.GetNumLearnedDisplayedToys(), totalToys)
    end
    local journalUnfiltered = C_PetJournal.IsUsingDefaultFilters() and C_PetJournal.GetSearchFilter() == ""
    if journalUnfiltered and petCountsDirty then UpdatePetCounts() end
    if journalUnfiltered and totalSpecies > 0 then
        AddTooltipBar(tooltip, "Pets", ownedSpecies, totalSpecies)
    else
        local _, ownedPets = C_PetJournal.GetNumPets()
        AddTooltipRow("Pets", BreakUpLargeNumbers(ownedPets), nil, TEXT_COLOR)
    end
end

-- Group Finder: Mythic+ rating and the keystone in your bags.
local function LFD_AppendTooltip(tooltip)
    local score = C_ChallengeMode.GetOverallDungeonScore()
    local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    if score == 0 and not mapID then return end
    GameTooltip_AddBlankLineToTooltip(tooltip)
    if score > 0 then
        local color = C_ChallengeMode.GetDungeonScoreRarityColor(score)
        tooltip:AddDoubleLine("Mythic+ Rating", BreakUpLargeNumbers(score), TEXT_COLOR.r, TEXT_COLOR.g, TEXT_COLOR.b, color.r, color.g, color.b)
    end
    if mapID then
        local name, _, _, texture = C_ChallengeMode.GetMapUIInfo(mapID)
        local keystone = format("%s +%d", name, C_MythicPlus.GetOwnedKeystoneLevel())
        AddTooltipRow("Keystone", texture and format(ICON_TEXT, texture, keystone) or keystone, nil, TEXT_COLOR)
    end
end

-- Adventure Guide: current lockouts (RaidFrame requests them on entering the world).
local function EJ_AppendTooltip()
    local shown = false
    for i = 1, GetNumSavedInstances() do
        local name, _, _, _, locked, extended, _, isRaid, _, difficultyName, numEncounters, encounterProgress = GetSavedInstanceInfo(i)
        if locked or extended then
            if not shown then
                AddTooltipHeader("Lockouts")
                shown = true
            end
            AddTooltipRow((isRaid and RAID_ICON or DUNGEON_ICON) .. name, format("%s  %d/%d", difficultyName, encounterProgress, numEncounters),
                nil, encounterProgress >= numEncounters and _G.GREEN_FONT_COLOR or TEXT_COLOR)
        end
    end
end

-- =========================
-- Right-click menus
-- =========================
-- These Blizzard buttons register every mouse button and toggle their panel on any of
-- them, so right clicks are unregistered (quick keybind mode ignores left and right
-- clicks) and open a menu on mouse up instead. Menu actions call C APIs directly:
-- Blizzard's panel flows keep state on their frames, which addon calls would taint.
local function AddMicroContextMenu(button, isPanelShown, generator)
    button:RegisterForClicks("LeftButtonUp", "MiddleButtonUp", "Button4Up", "Button5Up")
    RefineUI:HookScriptOnce("MicroMenu:" .. button:GetName() .. ":ContextMenu", button, "OnMouseUp", function(self, mouseButton)
        if mouseButton ~= "RightButton" or not self:IsEnabled() or IsQuickKeybindMode() then return end
        -- OnMouseDown pushed the button, and only a click would restore it.
        if not isPanelShown() then self:SetNormal() end
        if _G.GameTooltip:IsOwned(self) then _G.GameTooltip:Hide() end
        MenuUtil.CreateContextMenu(self, generator)
    end)
end

-- Character: equipment sets, equipped through Blizzard's locked-item and casting checks.
local function IsCharacterPanelShown()
    return _G.CharacterFrame:IsShown()
end

local function IsEquipmentSetEquipped(setID)
    return select(4, C_EquipmentSet.GetEquipmentSetInfo(setID))
end

local function EquipSet(setID)
    EquipmentManager_EquipSet(setID)
end

local function Character_ContextMenu(_, root)
    root:CreateTitle("Equipment Sets")
    local setIDs = C_EquipmentSet.GetEquipmentSetIDs()
    for _, setID in ipairs(setIDs) do
        local name, icon = C_EquipmentSet.GetEquipmentSetInfo(setID)
        root:CreateRadio(format(ICON_TEXT, icon, name), IsEquipmentSetEquipped, EquipSet, setID)
    end
    if #setIDs == 0 then
        root:CreateButton("No equipment sets"):SetEnabled(false)
    end
end

-- Talents: loadouts for the current spec. Mirrors ClassTalentsFrameMixin:LoadConfigInternal:
-- the last-selected loadout is saved, and a Starter Build flag cleared, only once the
-- commit finishes, since clearing the flag earlier cancels the pending load.
local STARTER_BUILD_ID = Constants.TraitConsts.STARTER_BUILD_TRAIT_CONFIG_ID
local LOADOUT_COMMIT_KEY = "MicroMenu:LoadoutCommit"
local pendingSpecID, pendingConfigID, pendingUnflagStarter

local function IsTalentPanelShown()
    local frame = rawget(_G, "PlayerSpellsFrame")
    return frame and frame:IsShown()
end

local function FinishLoadout(specID, configID, unflagStarter)
    C_ClassTalents.UpdateLastSelectedSavedConfigID(specID, configID)
    if unflagStarter then
        C_ClassTalents.SetStarterBuildActive(false)
    end
end

local function OnLoadoutCommitEvent(event, configID)
    if event == "TRAIT_CONFIG_UPDATED" and configID ~= C_ClassTalents.GetActiveConfigID() then return end
    RefineUI:OffEvent("TRAIT_CONFIG_UPDATED", LOADOUT_COMMIT_KEY)
    RefineUI:OffEvent("CONFIG_COMMIT_FAILED", LOADOUT_COMMIT_KEY)
    if event == "TRAIT_CONFIG_UPDATED" then
        FinishLoadout(pendingSpecID, pendingConfigID, pendingUnflagStarter)
    end
end

local function LoadTalentLoadout(configID)
    if configID == STARTER_BUILD_ID then
        C_ClassTalents.SetStarterBuildActive(true)
        return
    end

    local specID = PlayerUtil.GetCurrentSpecID()
    local unflagStarter = C_ClassTalents.GetStarterBuildActive()
    local result, changeError = C_ClassTalents.LoadConfig(configID, true)
    if result == Enum.LoadConfigResult.Error then
        if changeError and changeError ~= "" then
            local color = _G.RED_FONT_COLOR
            _G.UIErrorsFrame:AddMessage(changeError, color.r, color.g, color.b)
        end
    elseif result == Enum.LoadConfigResult.NoChangesNecessary then
        FinishLoadout(specID, configID, unflagStarter)
    elseif result == Enum.LoadConfigResult.LoadInProgress then
        pendingSpecID, pendingConfigID, pendingUnflagStarter = specID, configID, unflagStarter
        RefineUI:RegisterEventCallback("TRAIT_CONFIG_UPDATED", OnLoadoutCommitEvent, LOADOUT_COMMIT_KEY)
        RefineUI:RegisterEventCallback("CONFIG_COMMIT_FAILED", OnLoadoutCommitEvent, LOADOUT_COMMIT_KEY)
    end
end

local function IsLoadoutSelected(configID)
    if C_ClassTalents.GetStarterBuildActive() then
        return configID == STARTER_BUILD_ID
    end
    return configID == C_ClassTalents.GetLastSelectedSavedConfigID(PlayerUtil.GetCurrentSpecID())
end

local function Talents_ContextMenu(_, root)
    local specID = PlayerUtil.GetCurrentSpecID()
    local _, specName, _, specIcon = GetSpecializationInfoByID(specID)
    root:CreateTitle(format(ICON_TEXT, specIcon, specName) .. " Loadouts")

    local canChange, _, changeError = C_ClassTalents.CanChangeTalents()
    local configIDs = C_ClassTalents.GetConfigIDsBySpecID(specID)
    if C_ClassTalents.GetHasStarterBuild() then
        local starterText = _G.BLUE_FONT_COLOR:WrapTextInColorCode(_G.TALENT_FRAME_DROP_DOWN_STARTER_BUILD)
        root:CreateRadio(starterText, IsLoadoutSelected, LoadTalentLoadout, STARTER_BUILD_ID):SetEnabled(canChange)
    elseif #configIDs == 0 then
        root:CreateButton("No saved loadouts"):SetEnabled(false)
    end
    for _, configID in ipairs(configIDs) do
        root:CreateRadio(C_Traits.GetConfigInfo(configID).name, IsLoadoutSelected, LoadTalentLoadout, configID):SetEnabled(canChange)
    end

    if not canChange and changeError and changeError ~= "" then
        root:CreateDivider()
        root:CreateTitle(_G.RED_FONT_COLOR:WrapTextInColorCode(changeError))
    end
end

-- =========================
-- Latency
-- =========================
local latencyText

local function LatencyColor(ms)
    if ms <= 60 then return 0, 1, 0 end
    if ms <= 120 then return 1, 1, 0 end
    return 1, 0, 0
end

local function UpdateLatency()
    local _, _, homeMS, worldMS = GetNetStats()
    local ms = worldMS or homeMS or 0
    if ms > 0 then
        latencyText:SetText(ms)
        latencyText:SetTextColor(LatencyColor(ms))
    else
        latencyText:SetText("")
    end
end

-- =========================
-- Extras
-- =========================
-- Hide default backpack/bag bar; Edit Mode can show them again.
local function SuppressDefaultButtons()
    local backpack = rawget(_G, "MainMenuBarBackpackButton")
    if backpack then backpack:Hide() end

    local bagsBar = rawget(_G, "BagsBar")
    if bagsBar then bagsBar:Hide() end
end

-- UpdateMicroButtons runs on every panel toggle; keep this to visual state only.
local function OnUpdateMicroButtons()
    for i = 1, #ExtraMicroButtons do
        ExtraMicroButtons[i]:UpdateMicroButton()
    end
    SuppressDefaultButtons()
end

local function CreateOverlayText(button, size)
    local text = GetOverlayFrame(button):CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetFont(RefineUI.Media.Fonts.Default, size, "OUTLINE")
    text:SetTextColor(1, 1, 1)
    text:SetPoint("BOTTOM", button, "BOTTOM", 2, 2)
    text:SetJustifyH("CENTER")
    return text
end

----------------------------------------------------------------------------------------
-- Initialize
----------------------------------------------------------------------------------------
function MicroMenu:OnEnable()
    -- Blizzard re-shows the store button on every UpdateMicroButtons; reparenting it
    -- keeps it hidden without Show/Hide forcing MicroMenuContainer relayouts.
    RefineUI.Kill(_G.StoreMicroButton)

    -- Guild
    guildCountText = CreateOverlayText(_G.GuildMicroButton, 12)
    guildCountText:SetPoint("BOTTOM", _G.GuildMicroButton, "BOTTOM", 1, 2)

    local function UpdateGuildRoster(event)
        if event == "PLAYER_ENTERING_WORLD" then
            RequestGuildRosterUpdate()
        end
        UpdateGuildOnlineCount()
    end

    RefineUI:RegisterEventCallback("GUILD_ROSTER_UPDATE", UpdateGuildRoster, "MicroMenu_GuildRoster")
    RefineUI:RegisterEventCallback("PLAYER_GUILD_UPDATE", UpdateGuildRoster, "MicroMenu_GuildRoster")
    RefineUI:RegisterEventCallback("PLAYER_ENTERING_WORLD", UpdateGuildRoster, "MicroMenu_GuildRoster")
    C_Timer.NewTicker(300, RequestGuildRosterUpdate)
    RequestGuildRosterUpdate()
    UpdateGuildOnlineCount()

    -- Character item level
    characterItemLevelText = CreateOverlayText(_G.CharacterMicroButton, 11)
    characterItemLevelText:SetJustifyV("BOTTOM")
    RefineUI:RegisterEventCallback("PLAYER_AVG_ITEM_LEVEL_UPDATE", UpdateCharacterItemLevel, "MicroMenu_ItemLevel")
    RefineUI:RegisterEventCallback("PLAYER_ENTERING_WORLD", UpdateCharacterItemLevel, "MicroMenu_ItemLevel")
    UpdateCharacterItemLevel()

    -- Blizzard button tooltips
    RefineUI:RegisterEventCallback("NEW_MOUNT_ADDED", function() mountCountsDirty = true end, "MicroMenu_Mounts")
    RefineUI:RegisterEventCallback("PET_JOURNAL_LIST_UPDATE", function() petCountsDirty = true end, "MicroMenu_Pets")
    AppendMicroTooltip(_G.CharacterMicroButton, Character_AppendTooltip)
    AppendMicroTooltip(_G.PlayerSpellsMicroButton, Talents_AppendTooltip)
    AppendMicroTooltip(_G.ProfessionMicroButton, Professions_AppendTooltip)
    AppendMicroTooltip(_G.AchievementMicroButton, Achievements_AppendTooltip)
    AppendMicroTooltip(_G.GuildMicroButton, Guild_AppendTooltip)
    AppendMicroTooltip(_G.LFDMicroButton, LFD_AppendTooltip)
    AppendMicroTooltip(_G.CollectionsMicroButton, Collections_AppendTooltip)
    AppendMicroTooltip(_G.EJMicroButton, EJ_AppendTooltip)

    -- Right-click menus
    AddMicroContextMenu(_G.CharacterMicroButton, IsCharacterPanelShown, Character_ContextMenu)
    AddMicroContextMenu(_G.PlayerSpellsMicroButton, IsTalentPanelShown, Talents_ContextMenu)

    -- Latency
    latencyText = CreateOverlayText(_G.MainMenuMicroButton, 11)
    C_Timer.NewTicker(5, UpdateLatency)
    UpdateLatency()

    -- Create Extra Buttons
    CreateRefineMicroButton("RefineFriendsMicroButton", {
        events = { "PLAYER_ENTERING_WORLD", "FRIENDLIST_UPDATE", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE" },
        iconPath = "Interface\\AddOns\\RefineUI\\Media\\Textures\\Social.blp",
        bgAtlasUp = "UI-HUD-MicroMenu-SocialJournal-Up",
        bgAtlasDown = "UI-HUD-MicroMenu-SocialJournal-Down",
        text = { size = 12, x = 1 },
        commandName = "TOGGLESOCIAL",
        onClick = function() if not IsQuickKeybindMode() then ToggleFriendsFrame(1) end end,
        onEnter = Friends_OnEnter,
        update = Friends_Update,
        isActive = function() return FriendsFrame and FriendsFrame:IsShown() end,
    })

    local greatVaultButton = CreateRefineMicroButton("RefineGreatVaultMicroButton", {
        events = { "PLAYER_ENTERING_WORLD", "WEEKLY_REWARDS_UPDATE" },
        iconAtlas = "GreatVault-32x32",
        iconSize = 28,
        iconX = 1,
        iconY = -1,
        customIconPos = true,
        text = { size = 11, x = 2 },
        bgAtlasUp = "UI-HUD-MicroMenu-GreatVault-Up",
        bgAtlasDown = "UI-HUD-MicroMenu-GreatVault-Down",
        onClick = function()
            local frame = rawget(_G, "WeeklyRewardsFrame")
            if frame and frame:IsShown() then
                HideUIPanel(frame)
            else
                _G.WeeklyRewards_ShowUI()
            end
        end,
        onEnter = GV_OnEnter,
        update = GV_Update,
        isActive = function()
            local frame = rawget(_G, "WeeklyRewardsFrame")
            return frame and frame:IsShown()
        end,
    })

    CreateRefineMicroButton("RefineDurabilityMicroButton", {
        events = { "PLAYER_ENTERING_WORLD", "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED" },
        iconPath = "Interface\\AddOns\\RefineUI\\Media\\Textures\\Anvil.blp",
        text = { size = 11, x = 2 },
        commandName = "TOGGLECHARACTER0",
        onClick = function() ToggleCharacter("PaperDollFrame") end,
        onEnter = Durability_OnEnter,
        update = Durability_Update,
    })

    -- WeeklyRewardsFrame is load-on-demand and doesn't call UpdateMicroButtons.
    local function WatchWeeklyRewardsFrame()
        local frame = rawget(_G, "WeeklyRewardsFrame")
        if not frame then return end
        local function UpdateGreatVaultButton() greatVaultButton:UpdateMicroButton() end
        RefineUI:HookScriptOnce("MicroMenu:WeeklyRewardsFrame:OnShow", frame, "OnShow", UpdateGreatVaultButton)
        RefineUI:HookScriptOnce("MicroMenu:WeeklyRewardsFrame:OnHide", frame, "OnHide", UpdateGreatVaultButton)
    end
    EventUtil.ContinueOnAddOnLoaded("Blizzard_WeeklyRewards", WatchWeeklyRewardsFrame)

    -- The RefineUI Bags module replaces Blizzard's bag frames and rebinds the bag keys
    -- to its own window, so follow that window when the module is on.
    local bagsModule = RefineUI:IsModuleStartupEnabled("Bags") and RefineUI:GetModule("Bags")
    local bagWindow = bagsModule and bagsModule.Frame

    -- Toggle on the same state the button shows; ToggleAllBags reopens when any bag
    -- it counts (e.g. the reagent bag) is closed.
    local bagsButton = CreateRefineMicroButton("RefineBagsMicroButton", {
        events = { "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED" },
        iconPath = "Interface\\AddOns\\RefineUI\\Media\\Textures\\Backpack.blp",
        text = { size = 11, x = 2 },
        commandName = "OPENALLBAGS",
        onClick = function()
            if IsQuickKeybindMode() then return end
            if bagWindow then
                bagsModule.ToggleBags()
            elseif IsAnyBagOpen() then
                CloseAllBags()
            else
                OpenAllBags()
            end
        end,
        onEnter = Bags_OnEnter,
        update = Bags_Update,
        isActive = bagWindow and function() return bagWindow:IsShown() end or IsAnyBagOpen,
    })
    local function UpdateBagsButton() bagsButton:UpdateMicroButton() end
    if bagWindow then
        RefineUI:HookScriptOnce("MicroMenu:RefineUI_Bags:OnShow", bagWindow, "OnShow", UpdateBagsButton)
        RefineUI:HookScriptOnce("MicroMenu:RefineUI_Bags:OnHide", bagWindow, "OnHide", UpdateBagsButton)
    else
        -- Every Blizzard bag frame (combined or individual) fires these from OnShow/OnHide.
        _G.EventRegistry:RegisterCallback("ContainerFrame.OpenBag", UpdateBagsButton, bagsButton)
        _G.EventRegistry:RegisterCallback("ContainerFrame.CloseBag", UpdateBagsButton, bagsButton)
    end

    SkinMicroButtons()

    -- Layout
    local scale = RefineUI.Config.MicroMenu and RefineUI.Config.MicroMenu.Scale or 1
    _G.MicroMenuContainer:SetScale(scale)
    RefineUI:HookOnce("MicroMenu:MicroMenu:Layout", _G.MicroMenu, "Layout", MicroMenu_OnLayout)
    MicroMenu_OnLayout(_G.MicroMenu)

    RefineUI:After(TIMER_KEY.SUPPRESS_DEFAULT_BUTTONS, 0.1, SuppressDefaultButtons)
    RefineUI:HookOnce("MicroMenu:UpdateMicroButtons", "UpdateMicroButtons", OnUpdateMicroButtons)
    OnUpdateMicroButtons()
end
