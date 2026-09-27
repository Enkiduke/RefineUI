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

local function SetTooltipTitle(owner, text)
    local tooltip = _G.GameTooltip
    tooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local command = owner.cfg.commandName
    GameTooltip_SetTitle(tooltip, command and MicroButtonTooltipText(text, command) or text)
end

local function AddTooltipHeader(text, count)
    local tooltip = _G.GameTooltip
    GameTooltip_AddBlankLineToTooltip(tooltip)
    tooltip:AddDoubleLine(text, count, HEADER_COLOR.r, HEADER_COLOR.g, HEADER_COLOR.b, HEADER_COLOR.r, HEADER_COLOR.g, HEADER_COLOR.b)
end

local function AddTooltipRow(left, right, leftColor, rightColor)
    leftColor, rightColor = leftColor or TEXT_COLOR, rightColor or SUBTEXT_COLOR
    _G.GameTooltip:AddDoubleLine(left, right, leftColor.r, leftColor.g, leftColor.b, rightColor.r, rightColor.g, rightColor.b)
end

local function AddTooltipNote(text)
    _G.GameTooltip:AddLine(text, SUBTEXT_COLOR.r, SUBTEXT_COLOR.g, SUBTEXT_COLOR.b)
end

local function StatusIcon(isAFK, isDND)
    return isAFK and AFK_ICON or isDND and DND_ICON or ""
end

local function ColorText(color, text)
    return format("|cff%02x%02x%02x%s|r", color.r * 255, color.g * 255, color.b * 255, text)
end

-- Friend APIs return localized class names; RAID_CLASS_COLORS is keyed by class file.
local classFileByName
local function GetClassColorByName(className)
    if not classFileByName then
        classFileByName = {}
        for file, name in pairs(LocalizedClassList(false)) do classFileByName[name] = file end
        for file, name in pairs(LocalizedClassList(true)) do classFileByName[name] = file end
    end
    local file = className and classFileByName[className]
    return file and RAID_CLASS_COLORS[file] or TEXT_COLOR
end

-- =========================
-- Guild online overlay
-- =========================
local function SortByRankIndex(a, b)
    return a.rankIndex < b.rankIndex
end

local function GetOnlineGuildMembers()
    local onlineMembers = {}
    local numTotalMembers, numOnlineMembers = GetNumGuildMembers()
    for i = 1, numTotalMembers do
        local name, rank, rankIndex, _, _, _, _, _, online, status, class = GetGuildRosterInfo(i)
        if online then
            onlineMembers[#onlineMembers + 1] = { name = Ambiguate(name, "guild"), rank = rank, rankIndex = rankIndex, status = status, class = class }
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

-- Appends to Blizzard's guild button tooltip; skip when Blizzard didn't show one.
local function GuildMicroButton_OnEnter(self)
    if not IsInGuild() or _G.GameTooltip:GetOwner() ~= self then return end
    local onlineMembers, numOnlineMembers = GetOnlineGuildMembers()
    AddTooltipHeader("Online", numOnlineMembers)
    for i, member in ipairs(onlineMembers) do
        if i > MAX_GUILD_TOOLTIP_LIST then
            AddTooltipNote(format("+%d more", numOnlineMembers - MAX_GUILD_TOOLTIP_LIST))
            break
        end
        local name = StatusIcon(member.status == 1, member.status == 2) .. member.name
        AddTooltipRow(name, member.rank, RAID_CLASS_COLORS[member.class])
    end
    _G.GameTooltip:Show()
end

-- =========================
-- Base micro button mixin/factory
-- =========================
local ExtraMicroButtons = {}

local RefineMicroButtonMixin = CreateFromMixins(_G.MainMenuBarMicroButtonMixin)

function RefineMicroButtonMixin:OnLoadCommon(cfg)
    self.cfg = cfg
    self.iconR, self.iconG, self.iconB = 1, 1, 1
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
    self.Icon:SetVertexColor(self.iconR, self.iconG, self.iconB)
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
        AddTooltipHeader("Battle.net", numBNetOnline)
        local listed = 0
        for i = 1, numBNet or 0 do
            local acc = C_BattleNet.GetFriendAccountInfo(i)
            local game = acc and acc.gameAccountInfo
            if game and game.isOnline then
                if listed == MAX_FRIENDS_TOOLTIP_LIST then
                    AddTooltipNote(format("+%d more", numBNetOnline - listed))
                    break
                end
                local left = StatusIcon(acc.isAFK or game.isGameAFK, acc.isDND or game.isGameBusy) .. (acc.accountName or "")
                local right = game.richPresence or ""
                if game.clientProgram == BNET_CLIENT_WOW and game.wowProjectID == WOW_PROJECT_ID and game.characterName then
                    left = left .. " " .. ColorText(GetClassColorByName(game.className), game.characterName)
                    right = game.areaName or right
                end
                AddTooltipRow(left, right, _G.FRIENDS_BNET_NAME_COLOR)
                listed = listed + 1
            end
        end
    end

    if numWoWOnline > 0 then
        AddTooltipHeader("World of Warcraft", numWoWOnline)
        local listed = 0
        for i = 1, C_FriendList.GetNumFriends() or 0 do
            local info = C_FriendList.GetFriendInfoByIndex(i)
            if info and info.connected then
                if listed == MAX_FRIENDS_TOOLTIP_LIST then
                    AddTooltipNote(format("+%d more", numWoWOnline - listed))
                    break
                end
                AddTooltipRow(StatusIcon(info.afk, info.dnd) .. info.name, info.area or "", GetClassColorByName(info.className))
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
local GV_TYPES = {
    { type = Enum.WeeklyRewardChestThresholdType.Raid, label = "Raid" },
    { type = Enum.WeeklyRewardChestThresholdType.Activities, label = "Dungeons" },
    { type = Enum.WeeklyRewardChestThresholdType.World, label = "World" },
    { type = Enum.WeeklyRewardChestThresholdType.RankedPvP, label = "Rated PvP" },
}

-- One row per track: unlocked slots on the right, progress toward the next slot in gray.
local function GV_OnEnter(self)
    SetTooltipTitle(self, _G.GREAT_VAULT_REWARDS)
    GameTooltip_AddBlankLineToTooltip(_G.GameTooltip)

    local activities = C_WeeklyRewards.GetActivities() or {}
    local shown = false
    for _, track in ipairs(GV_TYPES) do
        local unlocked, total, progress, nextThreshold = 0, 0, 0, nil
        for _, a in ipairs(activities) do
            if a.type == track.type then
                total = total + 1
                progress = a.progress
                if a.progress >= a.threshold then
                    unlocked = unlocked + 1
                elseif not nextThreshold or a.threshold < nextThreshold then
                    nextThreshold = a.threshold
                end
            end
        end
        if total > 0 then
            local slots = unlocked .. "/" .. total
            if nextThreshold then
                AddTooltipRow(track.label .. "  " .. ColorText(SUBTEXT_COLOR, format("%d/%d", progress, nextThreshold)), slots, nil, TEXT_COLOR)
            else
                AddTooltipRow(track.label, slots, nil, _G.GREEN_FONT_COLOR)
            end
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
    for i = 1, 19 do if i ~= 4 and i ~= 5 then
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
    self.iconR, self.iconG, self.iconB = r, g, b
    self.Icon:SetVertexColor(r,g,b); self.Text:SetTextColor(r,g,b)
end

local function DurabilityGradientColor(p)
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
    local r, g, b = DurabilityGradientColor(pct)
    _G.GameTooltip:AddDoubleLine(left, format("%.0f%%", pct * 100), TEXT_COLOR.r, TEXT_COLOR.g, TEXT_COLOR.b, r, g, b)
end

-- Overall first, then damaged items (lowest first) with their quality-colored names.
local function Durability_OnEnter(self)
    SetTooltipTitle(self, "Durability")
    GameTooltip_AddBlankLineToTooltip(_G.GameTooltip)
    AddDurabilityRow("Overall", Durability_Overall() / 100)

    local items = {}
    for slot = 1, 19 do
        if slot ~= 4 and slot ~= 5 then
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
            AddDurabilityRow(format("|T%s:14:14:0:0:64:64:4:60:4:60|t %s", it.texture, it.name), it.pct)
        end
    end
    _G.GameTooltip:Show()
end

-- =========================
-- Bags
-- =========================
local function Bags_TotalSlots()
    local total = 0
    for i = 0, 4 do total = total + (C_Container.GetContainerNumSlots(i) or 0) end
    if type(REAGENTBAG_CONTAINER) == "number" then total = total + (C_Container.GetContainerNumSlots(REAGENTBAG_CONTAINER) or 0) end
    return total
end

local function Bags_CountFree()
    local totalFree = 0
    for i = 0, 4 do totalFree = totalFree + (C_Container.GetContainerNumFreeSlots(i) or 0) end
    if type(REAGENTBAG_CONTAINER) == "number" then totalFree = totalFree + (C_Container.GetContainerNumFreeSlots(REAGENTBAG_CONTAINER) or 0) end
    return totalFree
end

local function Bags_OnEnter(self)
    SetTooltipTitle(self, "Bags")
    GameTooltip_AddBlankLineToTooltip(_G.GameTooltip)
    local free = Bags_CountFree()
    AddTooltipRow("Free Slots", free .. "/" .. Bags_TotalSlots(), nil, free > 0 and TEXT_COLOR or _G.RED_FONT_COLOR)
    _G.GameTooltip:Show()
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
local function UpdateCharacterItemLevel()
    local _, avgItemLevelEquipped = GetAverageItemLevel()
    local itemLevel = floor(math.max(C_PaperDollInfo.GetMinItemLevel() or 0, avgItemLevelEquipped or 0))
    characterItemLevelText:SetText(itemLevel > 0 and itemLevel or "")
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
    _G.GuildMicroButton:HookScript("OnEnter", GuildMicroButton_OnEnter)
    RequestGuildRosterUpdate()
    UpdateGuildOnlineCount()

    -- Character item level
    characterItemLevelText = CreateOverlayText(_G.CharacterMicroButton, 11)
    characterItemLevelText:SetJustifyV("BOTTOM")
    RefineUI:RegisterEventCallback("PLAYER_AVG_ITEM_LEVEL_UPDATE", UpdateCharacterItemLevel, "MicroMenu_ItemLevel")
    RefineUI:RegisterEventCallback("PLAYER_ENTERING_WORLD", UpdateCharacterItemLevel, "MicroMenu_ItemLevel")
    UpdateCharacterItemLevel()

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
    WatchWeeklyRewardsFrame()
    RefineUI:RegisterEventCallback("ADDON_LOADED", function(_, name)
        if name == "Blizzard_WeeklyRewards" then WatchWeeklyRewardsFrame() end
    end, "MicroMenu:ADDON_LOADED")

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
