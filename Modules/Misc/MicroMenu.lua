----------------------------------------------------------------------------------------
-- MicroMenu for RefineUI
-- Description: Ports RefineUI_OLD's MicroMenu with integrated status info.
----------------------------------------------------------------------------------------

local AddOnName, RefineUI = ...
local MicroMenu = RefineUI:RegisterModule("MicroMenu")

local _G = _G
local select = select
local string = string
local unpack = unpack
local pairs = pairs
local ipairs = ipairs
local format = string.format
local type = type
local GOLD_R, GOLD_G, GOLD_B = 1, 0.82, 0

-- Safe helper: find index of a value in a sequential array
local function indexOf(list, value)
    if type(list) ~= "table" then return nil end
    for i = 1, #list do
        if list[i] == value then
            return i
        end
    end
    return nil
end

-- Small constants to avoid magic numbers
local MAX_GUILD_TOOLTIP_LIST = 30
local MAX_FRIENDS_TOOLTIP_LIST = 20
local GV_TOTAL_SLOTS = 9

-- Tooltip helper: consistent section spacing + header color
local function AddSectionHeader(text, r, g, b)
    _G.GameTooltip:AddLine(" ")
    _G.GameTooltip:AddLine(text, r or 0.8, g or 0.8, b or 1)
end

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
-- Guild online overlay
-- =========================
local guildCountFrame
local RAID_CLASS_COLORS = (rawget(_G, 'CUSTOM_CLASS_COLORS') or _G.RAID_CLASS_COLORS)
local NORMAL_COLOR = _G.NORMAL_FONT_COLOR or { r = 1, g = 1, b = 1 }
local FRIENDS_TEX_ON = _G.FRIENDS_TEXTURE_ONLINE or "Interface\\FriendsFrame\\StatusIcon-Online"
local FRIENDS_TEX_AFK = _G.FRIENDS_TEXTURE_AFK or "Interface\\FriendsFrame\\StatusIcon-Away"
local FRIENDS_TEX_DND = _G.FRIENDS_TEXTURE_DND or "Interface\\FriendsFrame\\StatusIcon-DnD"

local function GetOnlineGuildMembers()
    local onlineMembers = {}
    local numTotalMembers, numOnlineMembers = GetNumGuildMembers()
    for i = 1, numTotalMembers do
        local name, rank, rankIndex, level, _, _, _, _, online, status, class = GetGuildRosterInfo(i)
        if online then
            onlineMembers[#onlineMembers + 1] = { name = name, rank = rank, rankIndex = rankIndex, level = level, status = status, class = class }
        end
    end
    table.sort(onlineMembers, function(a, b) return a.rankIndex < b.rankIndex end)
    return onlineMembers, numOnlineMembers
end

local function GetGuildOnlineCount()
    if not IsInGuild or not IsInGuild() then return 0 end
    local _, numOnline = GetNumGuildMembers()
    return numOnline or 0
end

local function RequestGuildRosterUpdate()
    if IsInGuild() then
        C_GuildInfo.GuildRoster()
    end
end

local guildCountText

local function GetOverlayFrame(button)
    if not button then return end
    if not button.OverlayFrame then
        button.OverlayFrame = CreateFrame("Frame", nil, button)
        button.OverlayFrame:SetAllPoints()
        button.OverlayFrame:SetFrameStrata("HIGH")
        button.OverlayFrame:SetFrameLevel(100)
    end
    return button.OverlayFrame
end

local function UpdateGuildOnlineCount()
    local numOnline = GetGuildOnlineCount()
    if _G.GuildMicroButton and not guildCountText then
        guildCountText = GetOverlayFrame(_G.GuildMicroButton):CreateFontString(nil, "OVERLAY", "GameFontNormal")
        guildCountText:SetFont(RefineUI.Media.Fonts.Default, 12, "OUTLINE")
        guildCountText:SetTextColor(1, 1, 1)
        guildCountText:SetPoint("BOTTOM", _G.GuildMicroButton, "BOTTOM", 1, 2)
        guildCountText:SetJustifyH("CENTER")
    end
    if guildCountText then
        guildCountText:SetText(numOnline > 0 and numOnline or "")
    end
end

-- Error handling wrapper
local function SafeCall(func, ...)
    local ok, err = pcall(func, ...)
    if not ok then
        RefineUI:Print("|cFFFF0000GuildOnlineCount Error:|r %s", tostring(err))
    end
end

local SafeUpdateGuildOnlineCount = function() SafeCall(UpdateGuildOnlineCount) end
local SafeRequestGuildRosterUpdate = function() SafeCall(RequestGuildRosterUpdate) end

-- =========================
-- Base micro button mixin/factory
-- =========================
local ExtraMicroButtons = {}

local function UpdateAllExtraMicroButtons()
    for _, b in ipairs(ExtraMicroButtons) do
        if b and b.UpdateMicroButton then b:UpdateMicroButton() end
    end
end

local RefineMicroButtonMixin = CreateFromMixins(_G.MainMenuBarMicroButtonMixin)

function RefineMicroButtonMixin:OnLoadCommon(cfg)
    self.cfg = cfg
    self:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    if cfg.events then
        for _, e in ipairs(cfg.events) do
            local ok = pcall(self.RegisterEvent, self, e)
        end
    end
    
    if cfg.secure then
        self:HookScript("OnClick", function(_, btn)
            if cfg.onClick then cfg.onClick(self, btn) end
        end)
    else
        self:SetScript("OnClick", function(_, btn) if cfg.onClick then cfg.onClick(self, btn) end end)
    end
    self:SetScript("OnEvent", function(_, event, ...) if cfg.onEvent then cfg.onEvent(self, event, ...) end self:UpdateMicroButton() end)
    self:SetScript("OnEnter", function()
        if _G.MainMenuBarMicroButtonMixin and _G.MainMenuBarMicroButtonMixin.OnEnter then
            _G.MainMenuBarMicroButtonMixin.OnEnter(self)
        end
        if self.IconHighlight then self.IconHighlight:Show() end
        if cfg.onEnter then cfg.onEnter(self) end
    end)
    self:SetScript("OnLeave", function()
        if _G.MainMenuBarMicroButtonMixin and _G.MainMenuBarMicroButtonMixin.OnLeave then
            _G.MainMenuBarMicroButtonMixin.OnLeave(self)
        end
        if self.IconHighlight then self.IconHighlight:Hide() end
        _G.GameTooltip_Hide()
    end)
    self.Background = self:CreateTexture(nil, "BACKGROUND")
    self.PushedBackground = self:CreateTexture(nil, "BACKGROUND"); self.PushedBackground:Hide()
    self.Background:SetAtlas(cfg.bgAtlasUp or "UI-HUD-MicroMenu-Character-Up", true)
    self.PushedBackground:SetAtlas(cfg.bgAtlasDown or "UI-HUD-MicroMenu-Character-Down", true)
    
    -- Standard highlight
    if self.SetHighlightAtlas then
        self:SetHighlightAtlas("UI-HUD-MicroMenu-Button-Highlight")
    else
        self:SetHighlightTexture("Interface\\Buttons\\UI-MicroButton-Hilight", "ADD")
        local hl = self.GetHighlightTexture and self:GetHighlightTexture()
        if hl then hl:ClearAllPoints(); hl:SetAllPoints(self) end
    end
    
    self.Icon = self:CreateTexture(nil, "ARTWORK")
    if cfg.iconAtlas then self.Icon:SetAtlas(cfg.iconAtlas) else self.Icon:SetTexture(cfg.iconPath) end
    
    local iconPoint = cfg.iconPoint or "CENTER"
    local iconRelTo = cfg.iconRelativeTo or self
    local iconRelPoint = cfg.iconRelativePoint or "CENTER"
    local iconX = cfg.iconX or 0
    local iconY = cfg.iconY or 2
    self.Icon:SetPoint(iconPoint, iconRelTo, iconRelPoint, iconX, iconY)
    self.Icon:SetSize(cfg.iconSize or 24, cfg.iconSize or 24)
    if (cfg.iconPoint or cfg.iconRelativeTo or cfg.iconRelativePoint or cfg.iconX or cfg.iconY) and not cfg.customIconPos then
        cfg.customIconPos = true
    end
    
    self.IconHighlight = self:CreateTexture(nil, "OVERLAY")
    if cfg.iconAtlas then self.IconHighlight:SetAtlas(cfg.iconAtlas) else self.IconHighlight:SetTexture(cfg.iconPath) end
    self.IconHighlight:SetAllPoints(self.Icon)
    self.IconHighlight:SetBlendMode("ADD")
    self.IconHighlight:SetAlpha(0.35)
    self.IconHighlight:Hide()

    if cfg.text then
        self.Text = GetOverlayFrame(self):CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        self.Text:SetFont(RefineUI.Media.Fonts.Default, cfg.text.size or 12, cfg.text.flags or "OUTLINE")
        self.Text:SetPoint(cfg.text.point or "BOTTOM", cfg.text.x or 0, cfg.text.y or 2)
    end
    self:UpdateMicroButton()
end

function RefineMicroButtonMixin:SetNormal()
    self.Background:Show(); self.PushedBackground:Hide()
    if self.Icon then self.Icon:SetVertexColor(1, 1, 1) end
    if not (self.cfg and self.cfg.customIconPos) then
        if self.Icon then self.Icon:ClearAllPoints(); self.Icon:SetPoint("CENTER", self, "CENTER", 0, 2) end
    end
    self:SetButtonState("NORMAL", true)
end

function RefineMicroButtonMixin:SetPushed()
    self.Background:Hide(); self.PushedBackground:Show()
    if self.Icon then self.Icon:SetVertexColor(0.5, 0.5, 0.5) end
    if not (self.cfg and self.cfg.customIconPos) then
        if self.Icon then self.Icon:ClearAllPoints(); self.Icon:SetPoint("CENTER", self, "CENTER", 1, 1) end
    end
    self:SetButtonState("PUSHED", true)
end

function RefineMicroButtonMixin:EnableButton()
    self:SetAlpha(1)
    self:Enable(); if self.Icon then self.Icon:SetDesaturated(false); self.Icon:SetAlpha(1) end
    if self.Text then self.Text:SetAlpha(1) end
end

function RefineMicroButtonMixin:DisableButton()
    self:SetAlpha(0.5)
    self:Disable(); if self.Icon then self.Icon:SetDesaturated(true); self.Icon:SetAlpha(0.5) end
    if self.Text then self.Text:SetAlpha(0.5) end
end

function RefineMicroButtonMixin:UpdateMicroButton()
    local active = self.cfg.isActive and self.cfg.isActive(self)
    if active then self:SetPushed() else self:SetNormal() end
    if MicroButtons_ShouldDisable() then self:DisableButton() else self:EnableButton() end
    if self.cfg.update then self.cfg.update(self) end
end

local function CreateRefineMicroButton(name, cfg)
    local parent
    if _G.CharacterMicroButton then
        parent = _G.CharacterMicroButton:GetParent()
    end
    if not parent then
        parent = _G.MicroMenuContainer or _G.UIParent
    end
    local template
    if cfg and cfg.template then
        template = cfg.template
    else
        if cfg and cfg.secure then
            template = "MainMenuBarMicroButton, SecureActionButtonTemplate"
        else
            template = "MainMenuBarMicroButton"
        end
    end
    local b = CreateFrame("Button", name, parent, template)
    Mixin(b, RefineMicroButtonMixin); b:OnLoadCommon(cfg)
    if parent then b:SetFrameLevel(parent:GetFrameLevel() + 1) end
    b:EnableMouse(true); b:Show()
    if cfg.commandName then b.commandName = cfg.commandName end
    ExtraMicroButtons[#ExtraMicroButtons + 1] = b
    return b
end

local function InsertMicroButton(name, afterName)
    local buttonsTbl = rawget(_G, 'MICRO_BUTTONS')
    if type(buttonsTbl) ~= 'table' then return end
    local idx = indexOf(buttonsTbl, afterName) or #buttonsTbl
    table.insert(buttonsTbl, idx + 1, name)
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

local function SkinMicroButton(button)
    if not button then return end
    if button.IsSkinned then return end

    -- RefineUI.AddAPI(button) -- REMOVED
    
    RefineUI.CreateBorder(button, 0, 0, 12)

    button:HookScript("OnEnter", MicroButton_OnEnter)
    button:HookScript("OnLeave", MicroButton_OnLeave)

    button.IsSkinned = true
end

local function SkinMicroButtons()
    if not _G.MICRO_BUTTONS then return end

    for _, name in ipairs(_G.MICRO_BUTTONS) do
        local button = _G[name]
        if button then
            SkinMicroButton(button)
        end
    end
    -- Also skin our extra buttons if not already
    for _, button in ipairs(ExtraMicroButtons) do
        SkinMicroButton(button)
    end
end

-- =========================
-- Friends
-- =========================
local function GetBNetOnlineCount()
    local numOnline, total = 0, BNGetNumFriends() or 0
    for i = 1, total do
        local acc = C_BattleNet.GetFriendAccountInfo(i)
        if acc and acc.gameAccountInfo and acc.gameAccountInfo.isOnline then numOnline = numOnline + 1 end
    end
    return numOnline, total
end

local function GetWoWOnlineCount()
    return C_FriendList.GetNumOnlineFriends() or 0, C_FriendList.GetNumFriends() or 0
end

local function Friends_OnEnter(self)
    _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local cmd = (self and self.commandName) or "TOGGLESOCIAL"
    if type(_G.MicroButtonTooltipText) == "function" then
        _G.GameTooltip:SetText(_G.MicroButtonTooltipText(_G.SOCIAL_BUTTON, cmd), 1, 1, 1)
    else
        _G.GameTooltip:SetText(_G.SOCIAL_BUTTON, 1, 1, 1)
    end

    local numBNetOnline, totalBNet = GetBNetOnlineCount()
    local numWoWOnline = (GetWoWOnlineCount())
    local totalOnline = numBNetOnline + numWoWOnline

    _G.GameTooltip:AddLine(" ")
    _G.GameTooltip:AddDoubleLine("Online:", tostring(totalOnline), 1,1,1, 1,1,1)

    if numBNetOnline > 0 then
        AddSectionHeader("Battle.net Friends", 0.1, 0.6, 0.8)
        local listed = 0
        for i = 1, totalBNet do
            local acc = C_BattleNet.GetFriendAccountInfo(i)
            local game = acc and acc.gameAccountInfo
            if game and game.isOnline then
                local isAFK = ((acc and acc.isAFK) or (game and game.isGameAFK)) and true or false
                local isDND = ((acc and acc.isDND) or (game and game.isGameBusy)) and true or false
                local statusIcon = FRIENDS_TEX_ON
                if isAFK then statusIcon = FRIENDS_TEX_AFK elseif isDND then statusIcon = FRIENDS_TEX_DND end
                local left = string.format("|T%s:16|t %s", statusIcon, (acc and acc.accountName) or "Battlenet")
                local charName = (game and game.characterName) or ""
                local zone = (game and game.areaName) or ""
                local right
                if charName ~= "" and zone ~= "" then right = string.format("%s - %s", charName, zone)
                elseif charName ~= "" then right = charName else right = zone end
                _G.GameTooltip:AddDoubleLine(left, right, 1,1,1, 1,1,1)
                listed = listed + 1
                if listed >= MAX_FRIENDS_TOOLTIP_LIST then break end
            end
        end
    end

    if numWoWOnline > 0 then
        AddSectionHeader("World of Warcraft Friends", 0.1, 0.6, 0.8)
        local _, total = GetWoWOnlineCount()
        local listed = 0
        for i = 1, total do
            local info = C_FriendList.GetFriendInfoByIndex(i)
            if info and info.connected then
                local isAFK = info and info.afk
                local isDND = info and info.dnd
                local statusIcon = FRIENDS_TEX_ON
                if isAFK then statusIcon = FRIENDS_TEX_AFK elseif isDND then statusIcon = FRIENDS_TEX_DND end
                local classColor = RAID_CLASS_COLORS[info.className] or NORMAL_COLOR
                local left = string.format("|T%s:16|t %s, %s: %s %s", statusIcon, info.name or "Friend", _G.LEVEL, tostring(info.level or 0), info.className or "")
                local right = info.area or ""
                _G.GameTooltip:AddDoubleLine(left, right, classColor.r, classColor.g, classColor.b, 1,1,1)
                listed = listed + 1
                if listed >= MAX_FRIENDS_TOOLTIP_LIST then break end
            end
        end
    end

    _G.GameTooltip:AddLine(" ")
    _G.GameTooltip:AddLine("Left-Click: Open Friends List", 0.7, 0.7, 0.7)
    _G.GameTooltip:Show()
end

local function Friends_Update(self)
    local bnetOnline = select(1, GetBNetOnlineCount())
    local wowOnline = select(1, GetWoWOnlineCount())
    local total = (bnetOnline or 0) + (wowOnline or 0)
    if self.Text then self.Text:SetText(total > 0 and total or "") end
end

-- =========================
-- Great Vault
-- =========================
local function GV_OnEnter(self)
    _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    _G.GameTooltip:SetText(_G.GREAT_VAULT_REWARDS, 1, 1, 1);
    local activities = C_WeeklyRewards.GetActivities() or {}
    local types = {
        [Enum.WeeklyRewardChestThresholdType.Activities] = "Mythic+",
        [Enum.WeeklyRewardChestThresholdType.Raid] = "Raid",
        [Enum.WeeklyRewardChestThresholdType.RankedPvP] = "Rated PvP",
        [Enum.WeeklyRewardChestThresholdType.World] = "World",
    }
    
    local groupedActivities = {}
    for _, a in ipairs(activities) do
        local typeName = types[a.type] or "Unknown"
        if not groupedActivities[typeName] then
            groupedActivities[typeName] = {}
        end
        table.insert(groupedActivities[typeName], a)
    end
    
    local typeOrder = {"Mythic+", "Raid", "Rated PvP", "World"}
    for _, typeName in ipairs(typeOrder) do
        local typeActivities = groupedActivities[typeName]
        if typeActivities then
            AddSectionHeader(typeName, 0.8, 0.8, 1)
            table.sort(typeActivities, function(a, b) return (a.index or 0) < (b.index or 0) end)
            for _, a in ipairs(typeActivities) do
                local slotText = "Slot " .. (a.index or 1)
                local statusText, r, g, b
                if a.progress >= a.threshold then
                    statusText = "Unlocked"
                    r, g, b = 0.2, 1, 0.2
                else
                    statusText = string.format("%d/%d", a.progress or 0, a.threshold or 0)
                    r, g, b = 1, 1, 1
                end
                _G.GameTooltip:AddDoubleLine(slotText, statusText, 0.9, 0.9, 0.9, r, g, b)
            end
        end
    end
    _G.GameTooltip:Show();
end

local function GV_GetUnlockedRewards()
    local activities = C_WeeklyRewards.GetActivities() or {}
    local unlockedCount = 0
    for _, activity in ipairs(activities) do
        if activity.progress >= activity.threshold then
            unlockedCount = unlockedCount + 1
        end
    end
    return unlockedCount
end

local function GV_Update(self)
    local unlockedCount = GV_GetUnlockedRewards()
    if self.Text then
        self.Text:SetText(unlockedCount .. "/" .. GV_TOTAL_SLOTS)
    end
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
    if self.Text then self.Text:SetText(string.format("%.0f", overall)) end
    local r,g,b = 0.6,0.6,0.6
    if lowest < 20 then
        r,g,b = 1,0,0
    elseif lowest < 50 then
        r,g,b = 1,1,0
    elseif lowest <= 100 then
        r,g,b = 0,1,0
    end
    self.Icon:SetVertexColor(r,g,b); if self.Text then self.Text:SetTextColor(r,g,b) end
end

local function Durability_OnEnter(self)
    _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    _G.GameTooltip:ClearLines()
    local cmd = (self and self.commandName) or "TOGGLECHARACTER0"
    if type(_G.MicroButtonTooltipText) == "function" then
        _G.GameTooltip:SetText(_G.MicroButtonTooltipText("Equipment Durability", cmd), 1, 1, 1)
    else
        _G.GameTooltip:SetText("Equipment Durability", 1, 1, 1)
    end

    local function gradientColor(p)
        if p >= 0.5 then
            local t = (p - 0.5) / 0.5
            return 1 - t, 1, 0
        else
            local t = p / 0.5
            return 1, t, 0
        end
    end

    local overall = select(1, Durability_Overall()) or 0
    local orr, org, orb = gradientColor((overall or 0) / 100)
    local overallLeft = string.format("%3.0f%%  |TInterface\\Minimap\\Tracking\\Repair:16:16:0:0:64:64:8:56:8:56|t Overall", overall)
    _G.GameTooltip:AddDoubleLine(overallLeft, " ", orr, org, orb, 1, 1, 1)
    _G.GameTooltip:AddLine(" ")

    local items = {}
    for slot = 1, 19 do
        if slot ~= 4 and slot ~= 5 then
            local cur, max = GetInventoryItemDurability(slot)
            if cur and max and max > 0 then
                local p = cur / max
                if p < 1 then
                    local tex = GetInventoryItemTexture("player", slot) or 134400
                    local link = GetInventoryItemLink("player", slot)
                    local name, quality
                    if link then
                        local iName, _, iQuality = GetItemInfo(link)
                        name, quality = iName or name, iQuality
                    end
                    items[#items + 1] = { pct = p, texture = tex, name = name, quality = quality }
                end
            end
        end
    end
    table.sort(items, function(a, b) return (a.pct or 0) < (b.pct or 0) end)

    for _, it in ipairs(items) do
        local pr, pg, pb = gradientColor(it.pct or 0)
        local percent = string.format("%3.0f%%", (it.pct or 0) * 100)
        local left
        if it.quality and GetItemQualityColor then
            local _, _, _, hex = GetItemQualityColor(it.quality)
            local colored = (hex and ("|c"..hex) or "|cffffffff") .. (it.name or "") .. "|r"
            left = string.format("%s  |T%s:16:16:0:0:64:64:4:60:4:60|t %s", percent, tostring(it.texture), colored)
        else
            left = string.format("%s  |T%s:16:16:0:0:64:64:4:60:4:60|t %s", percent, tostring(it.texture), it.name or "")
        end
        _G.GameTooltip:AddDoubleLine(left, " ", pr, pg, pb, 1, 1, 1)
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
    _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    _G.GameTooltip:ClearLines()
    local title = BAGSLOT or "Bags"
    local cmd = (self and self.commandName) or "TOGGLEBACKPACK"
    if type(_G.MicroButtonTooltipText) == "function" then
        _G.GameTooltip:SetText(_G.MicroButtonTooltipText(title, cmd), 1, 1, 1)
    else
        _G.GameTooltip:SetText(title, 1, 1, 1)
    end

    local totalSlots = Bags_TotalSlots()
    local totalFree = Bags_CountFree()
    
    AddSectionHeader("Capacity", 0.8, 0.8, 1)
    _G.GameTooltip:AddDoubleLine("Total Free", totalFree, 1, 1, 1, 0, 1, 0)
    _G.GameTooltip:AddDoubleLine("Total Slots", totalSlots, 1, 1, 1, 1, 1, 1)
    
    _G.GameTooltip:AddLine(" ")
    _G.GameTooltip:AddLine("Left-Click: Toggle Bags", 0.7, 0.7, 0.7)
    _G.GameTooltip:Show()
end

local function Bags_Update(self)
	-- Throttle updates to once per 0.5s since bag count doesn't need instant updates
    if RefineUI.Throttle then
		RefineUI:Throttle("MicroMenu:BagsUpdate", 0.5, function()
			local free = Bags_CountFree()
			if self.Text then
				if free > 0 then
					self.Text:SetText(tostring(free))
					self.Text:SetTextColor(1, 1, 1)
				else
					self.Text:SetText("0")
					self.Text:SetTextColor(1, 0, 0)
				end
			end
		end)
	else
		-- Fallback if no throttle
		local free = Bags_CountFree()
		if self.Text then
			self.Text:SetText(tostring(free > 0 and free or 0))
			self.Text:SetTextColor(free > 0 and 1 or 1, free > 0 and 1 or 0, free > 0 and 1 or 0)
		end
	end
end

-- =========================
-- Character Item Level
-- =========================
local characterItemLevelText

local function GetPlayerItemLevel()
    local totalItemLevel = 0
    local itemCount = 0
    local slots = {1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18}
    
    for _, slot in ipairs(slots) do
        local itemLink = GetInventoryItemLink("player", slot)
        if itemLink then
            local itemLevel = C_Item.GetCurrentItemLevel(ItemLocation:CreateFromEquipmentSlot(slot))
            if itemLevel and itemLevel > 0 then
                totalItemLevel = totalItemLevel + itemLevel
                itemCount = itemCount + 1
            end
        end
    end
    
    if itemCount > 0 then return math.floor(totalItemLevel / itemCount) end
    return 0
end

local function UpdateCharacterItemLevel()
    if _G.CharacterMicroButton and not characterItemLevelText then
        characterItemLevelText = GetOverlayFrame(_G.CharacterMicroButton):CreateFontString(nil, "OVERLAY", "GameFontNormal")
        characterItemLevelText:SetFont(RefineUI.Media.Fonts.Default, 11, "OUTLINE")
        characterItemLevelText:SetPoint("BOTTOM", _G.CharacterMicroButton, "BOTTOM", 2, 2)
        characterItemLevelText:SetJustifyH("CENTER")
        characterItemLevelText:SetJustifyV("BOTTOM")
    end
    
    if characterItemLevelText then
        local itemLevel = GetPlayerItemLevel()
        if itemLevel > 0 then
            characterItemLevelText:SetText(itemLevel)
            characterItemLevelText:SetTextColor(1, 1, 1)
        else
            characterItemLevelText:SetText("")
        end
    end
end

-- =========================
-- Latency
-- =========================
local latencyText

local function GetLatency()
    local _, _, homeMS, worldMS = GetNetStats()
    return worldMS or homeMS or 0
end

local function LatencyColor(ms)
    if ms <= 60 then return 0, 1, 0 end
    if ms <= 120 then return 1, 1, 0 end
    return 1, 0, 0
end

local function UpdateLatency()
    if _G.MainMenuMicroButton and not latencyText then
        latencyText = GetOverlayFrame(_G.MainMenuMicroButton):CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        latencyText:SetFont(RefineUI.Media.Fonts.Default, 11, "OUTLINE")
        latencyText:SetPoint("BOTTOM", _G.MainMenuMicroButton, "BOTTOM", 2, 2)
        latencyText:SetJustifyH("CENTER")
    end
    if latencyText then
        local ms = GetLatency()
        if ms and ms > 0 then
            local r, g, bcol = LatencyColor(ms)
            latencyText:SetText(tostring(ms))
            latencyText:SetTextColor(r, g, bcol)
            latencyText:Show()
        else
            latencyText:SetText("")
        end
    end
end

-- =========================
-- Extras
-- =========================
-- Hide Default Buttons (Store, Backpack)
local function SuppressDefaultButtons()
    local store = rawget(_G, "StoreMicroButton") or rawget(_G, "ShopMicroButton")
    if store then store:Hide(); store:SetShown(false) end

    local backpack = rawget(_G, "MainMenuBarBackpackButton")
    if backpack then backpack:Hide(); backpack:SetShown(false) end

    local bagsBar = rawget(_G, "BagsBar")
    if bagsBar then bagsBar:Hide(); bagsBar:SetShown(false) end

    local container = rawget(_G, "MicroButtonAndBagsBar")
    if container then
        -- RefineUI.AddAPI(container) -- REMOVED
        RefineUI.StripTextures(container)
    end
end

-- =========================
-- Consolidated UpdateMicroButtons Hook
-- =========================
local function OnUpdateMicroButtons()
    UpdateGuildOnlineCount()
    UpdateAllExtraMicroButtons()
    SkinMicroButtons()
    UpdateCharacterItemLevel()
    UpdateLatency()
    SuppressDefaultButtons()
end

----------------------------------------------------------------------------------------
-- Initialize
----------------------------------------------------------------------------------------
function MicroMenu:OnEnable()
    -- Guild Roster Events
    -- Guild Roster Events
    local function UpdateGuildRoster(_, event)
        if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
            SafeRequestGuildRosterUpdate()
        end
        SafeUpdateGuildOnlineCount()
    end

    RefineUI:RegisterEventCallback("PLAYER_LOGIN", UpdateGuildRoster, "MicroMenu_GuildRoster")
    RefineUI:RegisterEventCallback("GUILD_ROSTER_UPDATE", UpdateGuildRoster, "MicroMenu_GuildRoster")
    RefineUI:RegisterEventCallback("PLAYER_ENTERING_WORLD", UpdateGuildRoster, "MicroMenu_GuildRoster")

    C_Timer.NewTicker(300, SafeRequestGuildRosterUpdate)
    
    -- Guild Tooltip
    if _G.GuildMicroButton then
        _G.GuildMicroButton:HookScript("OnEnter", function()
            if not IsInGuild() then return end
            local onlineMembers, numOnlineMembers = GetOnlineGuildMembers()
            AddSectionHeader("Online Guild Members (" .. numOnlineMembers .. ")")
            local currentRank
            for i, member in ipairs(onlineMembers) do
                if i > MAX_GUILD_TOOLTIP_LIST then
                    _G.GameTooltip:AddLine("... and " .. (numOnlineMembers - MAX_GUILD_TOOLTIP_LIST) .. " more")
                    break
                end
                if currentRank ~= member.rank then
                    _G.GameTooltip:AddLine(" ")
                    _G.GameTooltip:AddLine("----" .. member.rank .. "----")
                    currentRank = member.rank
                end
                local classColor = RAID_CLASS_COLORS[member.class] or RAID_CLASS_COLORS["PRIEST"]
                local statusIcon = (member.status == 1 and "|T"..FRIENDS_TEX_AFK..":14:14:0:0|t")
                    or (member.status == 2 and "|T"..FRIENDS_TEX_DND..":14:14:0:0|t") or ""
                _G.GameTooltip:AddDoubleLine(statusIcon .. member.name, "Level " .. member.level, classColor.r, classColor.g, classColor.b, 1, 1, 1)
            end
            _G.GameTooltip:Show()
        end)
    end

    -- Create Extra Buttons
    CreateRefineMicroButton("RefineFriendsMicroButton", {
        events = { "PLAYER_ENTERING_WORLD", "UPDATE_BINDINGS", "FRIENDLIST_UPDATE", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE", "BN_FRIEND_INFO_CHANGED" },
        iconPath = "Interface\\AddOns\\RefineUI\\Media\\Textures\\Social.blp",
        bgAtlasUp = "UI-HUD-MicroMenu-SocialJournal-Up",
        bgAtlasDown = "UI-HUD-MicroMenu-SocialJournal-Down",
        text = { size = 12, point = "BOTTOM", x = 1, y = 2 },
        commandName = "TOGGLESOCIAL",
        onClick = function() if not IsQuickKeybindMode() then ToggleFriendsFrame(1) end end,
        onEnter = Friends_OnEnter,
        update = Friends_Update,
        isActive = function() return FriendsFrame and FriendsFrame:IsShown() end,
    })
    InsertMicroButton("RefineFriendsMicroButton", "GuildMicroButton")

    local GreatVaultButton = CreateRefineMicroButton("RefineGreatVaultMicroButton", {
        events = { "PLAYER_ENTERING_WORLD", "WEEKLY_REWARDS_UPDATE" },
        iconAtlas = "GreatVault-32x32",
        iconSize = 28,
        iconPoint = "CENTER",
        iconRelativePoint = "CENTER",
        iconX = 1,
        iconY = -1,
        customIconPos = true,
        text = { size = 11, point = "BOTTOM", x = 2, y = 2 },
        bgAtlasUp = "UI-HUD-MicroMenu-GreatVault-Up",
        bgAtlasDown = "UI-HUD-MicroMenu-GreatVault-Down",
        onClick = function(self)
            if not self:IsEnabled() then return end
            local frame = rawget(_G, "WeeklyRewardsFrame")
            if frame and frame:IsShown() then
                if _G.HideUIPanel then _G.HideUIPanel(frame) else frame:Hide() end
            else
                _G.WeeklyRewards_ShowUI()
            end
            self:UpdateMicroButton()
        end,
        onEnter = GV_OnEnter,
        update = GV_Update,
        isActive = function()
            local frame = rawget(_G, "WeeklyRewardsFrame")
            return frame and frame:IsShown()
        end,
    })
    InsertMicroButton("RefineGreatVaultMicroButton", "AchievementMicroButton")

    CreateRefineMicroButton("RefineDurabilityMicroButton", {
        events = { "PLAYER_ENTERING_WORLD", "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED", "MERCHANT_CLOSED" },
        iconPath = "Interface\\AddOns\\RefineUI\\Media\\Textures\\Anvil.blp",
        text = { size = 11, point = "BOTTOM", x = 2, y = 2 },
        commandName = "TOGGLECHARACTER0",
        onClick = function() ToggleCharacter("PaperDollFrame") end,
        onEnter = Durability_OnEnter,
        update = Durability_Update,
    })
    InsertMicroButton("RefineDurabilityMicroButton", "CharacterMicroButton")
    
    CreateRefineMicroButton("RefineBagsMicroButton", {
        events = { "PLAYER_ENTERING_WORLD", "BAG_UPDATE", "BAG_UPDATE_DELAYED", "BAG_SLOT_FLAGS_UPDATED" },
        iconPath = "Interface\\AddOns\\RefineUI\\Media\\Textures\\Backpack.blp",
        text = { size = 11, point = "BOTTOM", x = 2, y = 2 },
        commandName = "TOGGLEBACKPACK",
        onClick = function()
            if not IsQuickKeybindMode() then
                if ToggleAllBags then ToggleAllBags() elseif ToggleBackpack then ToggleBackpack() end
            end
        end,
        onEnter = Bags_OnEnter,
        update = Bags_Update,
        isActive = function()
            local f = rawget(_G, "ContainerFrameCombinedBags")
            if f and f.IsShown then return f:IsShown() end
            return false
        end,
    })
    InsertMicroButton("RefineBagsMicroButton", "RefineDurabilityMicroButton")

    -- Layout Hook
    if _G.MicroMenuContainer then
        local scale = RefineUI.Config.MicroMenu and RefineUI.Config.MicroMenu.Scale or 1
        _G.MicroMenuContainer:SetScale(scale)
    end

    if _G.MicroMenuContainer and _G.MicroMenuContainer.Layout then
        RefineUI:HookOnce("MicroMenu:MicroMenuContainer:LayoutButtons", _G.MicroMenuContainer, "Layout", function(self)
            local spacing, width, prev = -2, 0, nil
            for _, btnName in ipairs(_G.MICRO_BUTTONS) do
                local b = _G[btnName]
                if b and b:IsShown() then
                    b:ClearAllPoints()
                    -- Fix: Ensure we don't anchor to ourselves or create circular dependency
                    if prev and prev ~= b then 
                        b:SetPoint("TOPLEFT", prev, "TOPRIGHT", spacing, 0) 
                    else 
                        b:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0) 
                    end
                    width, prev = width + b:GetWidth() + spacing, b
                end
            end
            local totalWidth = math.max(0, width - spacing)
            self:SetWidth(totalWidth)
        end)
    end

    if _G.MicroMenuContainer then
        local function FixSelectionSize()
            local f = _G.MicroMenuContainer
            if f and f.Selection then
                local extra = (#ExtraMicroButtons * 18)
                f.Selection:ClearAllPoints()
                f.Selection:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
                f.Selection:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", extra, 0)
            end
        end

        RefineUI:HookOnce("MicroMenu:MicroMenuContainer:LayoutSelection", _G.MicroMenuContainer, "Layout", FixSelectionSize)
        if _G.MicroMenuContainer.Selection then
             RefineUI:HookOnce("MicroMenu:MicroMenuContainerSelection:SetPoint", _G.MicroMenuContainer.Selection, "SetPoint", function(self)
                if self.changing then return end
                self.changing = true
                FixSelectionSize()
                self.changing = false
            end)
        end
    end

    -- Update Loops
    C_Timer.NewTicker(5, UpdateLatency)
    C_Timer.After(0.1, SuppressDefaultButtons)
    
    -- Hook update function
    RefineUI:HookOnce("MicroMenu:UpdateMicroButtons", "UpdateMicroButtons", OnUpdateMicroButtons)
    
    -- Initial Update
    OnUpdateMicroButtons()
end
