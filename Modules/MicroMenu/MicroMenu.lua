local R, C, L = unpack(RefineUI)

local addonName, addon = ...

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
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(text, r or 0.8, g or 0.8, b or 1)
end

-- Unified disable predicate for micro buttons (declared early so mixin can use it)
local function IsQuickKeybindMode()
    return type(KeybindFrames_InQuickKeybindMode) == "function" and KeybindFrames_InQuickKeybindMode()
end

local function MicroButtons_ShouldDisable()
    if GameMenuFrame and GameMenuFrame:IsShown() then return true end
    if IsQuickKeybindMode() then return true end
    return false
end

-- Cache last known repair cost at vendor for estimates away from vendor
-- Removed repair cost caching/estimation per request

-- =========================
-- Guild online overlay
-- =========================
local f = CreateFrame("Frame", "GuildOnlineCountFrame", UIParent)

-- Table to store class colors
local RAID_CLASS_COLORS = (rawget(_G, 'CUSTOM_CLASS_COLORS') or RAID_CLASS_COLORS)
local NORMAL_COLOR = NORMAL_FONT_COLOR or { r = 1, g = 1, b = 1 }
local FRIENDS_TEX_ON = FRIENDS_TEXTURE_ONLINE or "Interface\\FriendsFrame\\StatusIcon-Online"
local FRIENDS_TEX_AFK = FRIENDS_TEXTURE_AFK or "Interface\\FriendsFrame\\StatusIcon-Away"
local FRIENDS_TEX_DND = FRIENDS_TEXTURE_DND or "Interface\\FriendsFrame\\StatusIcon-DnD"

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

-- Lightweight helper when only the count is needed
local function GetGuildOnlineCount()
    if not IsInGuild then return 0 end
    if not IsInGuild() then return 0 end
    local _, numOnline = GetNumGuildMembers()
    return numOnline or 0
end

local function RequestGuildRosterUpdate()
	if IsInGuild() then
		C_GuildInfo.GuildRoster()
	end
end

local guildCountText


local function UpdateGuildOnlineCount()
	local numOnline = GetGuildOnlineCount()
	if GuildMicroButton and not guildCountText then
		guildCountText = GuildMicroButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		guildCountText:SetFont(C.media.normalFont, 12, "OUTLINE")
		guildCountText:SetTextColor(1, 1, 1)
		guildCountText:SetPoint("BOTTOM", GuildMicroButton, "BOTTOM", 1, 2)
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
		print("|cFFFF0000GuildOnlineCount Error:|r " .. tostring(err))
	end
end

local SafeUpdateGuildOnlineCount = function() SafeCall(UpdateGuildOnlineCount) end
local SafeRequestGuildRosterUpdate = function() SafeCall(RequestGuildRosterUpdate) end

f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("GUILD_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_ENTERING_WORLD")

f:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
		SafeRequestGuildRosterUpdate()
	end
	SafeUpdateGuildOnlineCount()
end)

C_Timer.NewTicker(300, SafeRequestGuildRosterUpdate)

-- Adjust overlay when micro menu updates
hooksecurefunc("UpdateMicroButtons", UpdateGuildOnlineCount)

-- Enhance guild tooltip with online members list
GuildMicroButton:HookScript("OnEnter", function()
    if not IsInGuild() then return end
    local onlineMembers, numOnlineMembers = GetOnlineGuildMembers()
    AddSectionHeader("Online Guild Members (" .. numOnlineMembers .. ")")
    local currentRank
    for i, member in ipairs(onlineMembers) do
		if i > MAX_GUILD_TOOLTIP_LIST then
			GameTooltip:AddLine("... and " .. (numOnlineMembers - MAX_GUILD_TOOLTIP_LIST) .. " more")
			break
		end
		if currentRank ~= member.rank then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("----" .. member.rank .. "----")
			currentRank = member.rank
		end
		local classColor = RAID_CLASS_COLORS[member.class] or RAID_CLASS_COLORS["PRIEST"]
        local statusIcon = (member.status == 1 and "|T"..FRIENDS_TEX_AFK..":14:14:0:0|t")
            or (member.status == 2 and "|T"..FRIENDS_TEX_DND..":14:14:0:0|t") or ""
		GameTooltip:AddDoubleLine(statusIcon .. member.name, "Level " .. member.level, classColor.r, classColor.g, classColor.b, 1, 1, 1)
	end
	GameTooltip:Show()
end)

-- =========================
-- Base micro button mixin/factory
-- =========================
local ExtraMicroButtons = {}

local function UpdateAllExtraMicroButtons()
    for _, b in ipairs(ExtraMicroButtons) do
        if b and b.UpdateMicroButton then b:UpdateMicroButton() end
    end
end

local function RestoreExtraMicroButtonsVisuals()
    for _, b in ipairs(ExtraMicroButtons) do
        if b then
            -- Ensure full opacity after menu fades
            if b.SetAlpha then b:SetAlpha(1) end
            if b.Icon then b.Icon:SetDesaturated(false); b.Icon:SetAlpha(1) end
            if b.Text then b.Text:SetAlpha(1) end
            -- Respect disable predicate
            if MicroButtons_ShouldDisable() then
                if b.DisableButton then b:DisableButton() end
            else
                if b.EnableButton then b:EnableButton() end
            end
        end
    end
end

local RefineMicroButtonMixin = CreateFromMixins(MainMenuBarMicroButtonMixin)

function RefineMicroButtonMixin:OnLoadCommon(cfg)
    self.cfg = cfg
    self:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    if cfg.events then
        for _, e in ipairs(cfg.events) do
            local ok = pcall(self.RegisterEvent, self, e)
            if not ok then
                -- Silently ignore unknown events on this client version
            end
        end
    end
    -- For secure action buttons, do not replace the OnClick handler; hook it instead
    if cfg.secure then
        self:HookScript("OnClick", function(_, btn)
            if cfg.onClick then cfg.onClick(self, btn) end
        end)
    else
        self:SetScript("OnClick", function(_, btn) if cfg.onClick then cfg.onClick(self, btn) end end)
    end
    self:SetScript("OnEvent", function(_, event, ...) if cfg.onEvent then cfg.onEvent(self, event, ...) end self:UpdateMicroButton() end)
    self:SetScript("OnEnter", function()
        if MainMenuBarMicroButtonMixin and MainMenuBarMicroButtonMixin.OnEnter then
            MainMenuBarMicroButtonMixin.OnEnter(self)
        end
        if self.IconHighlight then self.IconHighlight:Show() end
        if cfg.onEnter then cfg.onEnter(self) end
    end)
    self:SetScript("OnLeave", function()
        if MainMenuBarMicroButtonMixin and MainMenuBarMicroButtonMixin.OnLeave then
            MainMenuBarMicroButtonMixin.OnLeave(self)
        end
        if self.IconHighlight then self.IconHighlight:Hide() end
        GameTooltip_Hide()
    end)
    self.Background = self:CreateTexture(nil, "BACKGROUND")
    self.PushedBackground = self:CreateTexture(nil, "BACKGROUND"); self.PushedBackground:Hide()
    self.Background:SetAtlas(cfg.bgAtlasUp or "UI-HUD-MicroMenu-Character-Up", true)
    self.PushedBackground:SetAtlas(cfg.bgAtlasDown or "UI-HUD-MicroMenu-Character-Down", true)
    -- Provide a proper hover highlight like Blizzard's micro buttons
    if self.SetHighlightAtlas then
        -- Button:SetHighlightAtlas expects (atlas[, blendMode]) on retail; omit size flag
        self:SetHighlightAtlas("UI-HUD-MicroMenu-Button-Highlight")
    else
        self:SetHighlightTexture("Interface\\Buttons\\UI-MicroButton-Hilight", "ADD")
        local hl = self.GetHighlightTexture and self:GetHighlightTexture()
        if hl then hl:ClearAllPoints(); hl:SetAllPoints(self) end
    end
    self.Icon = self:CreateTexture(nil, "ARTWORK")
    if cfg.iconAtlas then self.Icon:SetAtlas(cfg.iconAtlas) else self.Icon:SetTexture(cfg.iconPath) end
    -- Icon positioning: allow config overrides
    local iconPoint = cfg.iconPoint or "CENTER"
    local iconRelTo = cfg.iconRelativeTo or self
    local iconRelPoint = cfg.iconRelativePoint or "CENTER"
    local iconX = cfg.iconX or 0
    local iconY = cfg.iconY or 2
    self.Icon:SetPoint(iconPoint, iconRelTo, iconRelPoint, iconX, iconY)
    self.Icon:SetSize(cfg.iconSize or 24, cfg.iconSize or 24)
    if (cfg.iconPoint or cfg.iconRelativeTo or cfg.iconRelativePoint or cfg.iconX or cfg.iconY) and not cfg.customIconPos then
        -- Respect custom icon anchors during push/normal state updates
        cfg.customIconPos = true
    end
    -- Simple, reliable hover light effect using additive overlay
    self.IconHighlight = self:CreateTexture(nil, "OVERLAY")
    if cfg.iconAtlas then self.IconHighlight:SetAtlas(cfg.iconAtlas) else self.IconHighlight:SetTexture(cfg.iconPath) end
    self.IconHighlight:SetAllPoints(self.Icon)
    self.IconHighlight:SetBlendMode("ADD")
    self.IconHighlight:SetAlpha(0.35)
    self.IconHighlight:Hide()

    if cfg.text then
        self.Text = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        self.Text:SetFont(C.media.normalFont, cfg.text.size or 12, cfg.text.flags or "OUTLINE")
        self.Text:SetPoint(cfg.text.point or "BOTTOM", cfg.text.x or 0, cfg.text.y or 2)
    end
    self:UpdateMicroButton()
end

function RefineMicroButtonMixin:SetNormal()
	self.Background:Show(); self.PushedBackground:Hide()
	if self.Icon then self.Icon:SetVertexColor(1, 1, 1) end
	-- Don't override custom positioning for specific buttons
	if not (self.cfg and self.cfg.customIconPos) then
		if self.Icon then self.Icon:ClearAllPoints(); self.Icon:SetPoint("CENTER", self, "CENTER", 0, 2) end
	end
	self:SetButtonState("NORMAL", true)
end

function RefineMicroButtonMixin:SetPushed()
	self.Background:Hide(); self.PushedBackground:Show()
	if self.Icon then self.Icon:SetVertexColor(0.5, 0.5, 0.5) end
	-- Don't override custom positioning for specific buttons
	if not (self.cfg and self.cfg.customIconPos) then
		if self.Icon then self.Icon:ClearAllPoints(); self.Icon:SetPoint("CENTER", self, "CENTER", 1, 1) end
	end
	self:SetButtonState("PUSHED", true)
end

function RefineMicroButtonMixin:EnableButton()
	self:Enable(); if self.Icon then self.Icon:SetDesaturated(false); self.Icon:SetAlpha(1) end

	if self.Text then self.Text:SetAlpha(1) end
end

function RefineMicroButtonMixin:DisableButton()
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
    local parent = MicroMenuContainer or UIParent
    -- Ensure secure template is applied alongside the Blizzard micro button look
    -- Prefer SecureActionButtonTemplate first when creating secure action buttons
    local template
    if cfg and cfg.template then
        template = cfg.template
    else
        if cfg and cfg.secure then
            -- Use Blizzard's composite template ordering to remain compatible with edit-mode expectations
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

-- One-time hooks for updates and layout
hooksecurefunc("UpdateMicroButtons", UpdateAllExtraMicroButtons)

hooksecurefunc(MicroMenuContainer, "Layout", function(self)
	local spacing, width, prev = -2, 0, nil
	for _, btnName in ipairs(MICRO_BUTTONS) do
		local b = _G[btnName]
		if b and b:IsShown() then
			b:ClearAllPoints()
			if prev then b:SetPoint("TOPLEFT", prev, "TOPRIGHT", spacing, 0) else b:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0) end
			width, prev = width + b:GetWidth() + spacing, b
		end
	end
	self:SetWidth(math.max(0, width - spacing))
end)

-- Ensure our custom buttons re-enable after Game Menu fade-out
local gmHooksAdded = false
local function EnsureGameMenuHooks()
    if gmHooksAdded then return end
    local frame = rawget(_G, "GameMenuFrame")
    if not frame then return end
    frame:HookScript("OnShow", UpdateAllExtraMicroButtons)
    frame:HookScript("OnHide", function()
        -- Update immediately, then once more next frame to ensure visuals restore without delay
        UpdateAllExtraMicroButtons()
        if not frame._refineRestoreScheduled then
            frame._refineRestoreScheduled = true
            C_Timer.After(0, function()
                RestoreExtraMicroButtonsVisuals()
                frame._refineRestoreScheduled = false
            end)
        end
    end)
    gmHooksAdded = true
end

hooksecurefunc("ToggleGameMenu", EnsureGameMenuHooks)
C_Timer.After(1, EnsureGameMenuHooks)

-- =========================
-- Specific buttons
-- =========================
-- Hide the in-game shop micro button entirely
local function SuppressStoreMicroButton()
    local b = rawget(_G, "StoreMicroButton") or rawget(_G, "ShopMicroButton")
    if not b then return end
    b:Hide()
    b:SetShown(false)
end

C_Timer.After(0.1, SuppressStoreMicroButton)
hooksecurefunc("UpdateMicroButtons", SuppressStoreMicroButton)
-- Hide alert/pulse on PlayerSpells to avoid noise
local function HideAlert(microButton)
	if microButton == PlayerSpellsMicroButton then MainMenuMicroButton_HideAlert(microButton) end
end
local function HidePulse(microButton)
	if microButton == PlayerSpellsMicroButton then MicroButtonPulseStop(microButton) end
end
hooksecurefunc("MainMenuMicroButton_ShowAlert", HideAlert)
hooksecurefunc("MicroButtonPulse", HidePulse)

-- =========================
-- Talent Button Spec Change Menu
-- =========================
local specChangeMenu

local function CreateSpecChangeMenu()
	if specChangeMenu then return specChangeMenu end
	
	specChangeMenu = CreateFrame("Frame", "RefineSpecChangeMenu", UIParent, "UIDropDownMenuTemplate")
	return specChangeMenu
end

local function GetPlayerSpecs()
	local specs = {}
	local numSpecs = GetNumSpecializations()
	local currentSpec = GetSpecialization()
	
	for i = 1, numSpecs do
		local specID, name, description, icon = GetSpecializationInfo(i)
		if specID then
			specs[#specs + 1] = {
				index = i,
				name = name,
				icon = icon,
				isCurrent = (i == currentSpec)
			}
		end
	end
	
	return specs, currentSpec
end

local function SpecChangeMenu_OnClick(self, specIndex)
	if specIndex and specIndex ~= GetSpecialization() then
		C_SpecializationInfo.SetSpecialization(specIndex)
	end
	CloseDropDownMenus()
end

local function InitializeSpecChangeMenu(self, level)
	if level ~= 1 then return end
	
	local specs, currentSpec = GetPlayerSpecs()
	
	for _, spec in ipairs(specs) do
		local info = UIDropDownMenu_CreateInfo()
		info.text = spec.name
		info.icon = spec.icon
		info.func = function() SpecChangeMenu_OnClick(self, spec.index) end
		info.checked = spec.isCurrent
		info.notCheckable = false
		info.keepShownOnClick = false
		
		-- Disable if it's the current spec or if player is in combat
		if spec.isCurrent or InCombatLockdown() then
			info.disabled = true
		end
		
		UIDropDownMenu_AddButton(info, level)
	end
	
	-- Add separator and note about combat restriction
	if InCombatLockdown() then
		local info = UIDropDownMenu_CreateInfo()
		info.text = ""
		info.isTitle = true
		info.notCheckable = true
		UIDropDownMenu_AddButton(info, level)
		
		local info2 = UIDropDownMenu_CreateInfo()
		info2.text = "Cannot change spec in combat"
		info2.isTitle = true
		info2.notCheckable = true
		info2.colorCode = "|cFFFF0000"
		UIDropDownMenu_AddButton(info2, level)
	end
end

-- Hook the PlayerSpells micro button for right-click spec changing
local function HookPlayerSpellsButton()
	if PlayerSpellsMicroButton and not PlayerSpellsMicroButton.refineHooked then
		-- Store the original OnClick function
		local originalOnClick = PlayerSpellsMicroButton:GetScript("OnClick")
		
		PlayerSpellsMicroButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		
		PlayerSpellsMicroButton:SetScript("OnClick", function(self, button)
			if button == "RightButton" then
				-- Create and show spec change menu
				local menu = CreateSpecChangeMenu()
				UIDropDownMenu_Initialize(menu, InitializeSpecChangeMenu, "MENU")
				ToggleDropDownMenu(1, nil, menu, self, 30, 115)
			else
				-- Call the original left-click behavior
				if originalOnClick then
					originalOnClick(self, button)
				end
			end
		end)
		
		-- Hook the tooltip to add right-click info
		PlayerSpellsMicroButton:HookScript("OnEnter", function()
			if GameTooltip:IsOwned(PlayerSpellsMicroButton) then
				GameTooltip:AddLine(" ")
				GameTooltip:AddLine("Right-Click: Change Specialization", 0.7, 0.7, 0.7)
				GameTooltip:Show()
			end
		end)
		
		PlayerSpellsMicroButton.refineHooked = true
	end
end

-- Hook when the button is available
C_Timer.After(1, HookPlayerSpellsButton)
hooksecurefunc("UpdateMicroButtons", HookPlayerSpellsButton)

-- Friends
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
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local cmd = (self and self.commandName) or "TOGGLESOCIAL"
    if type(MicroButtonTooltipText) == "function" then
        GameTooltip:SetText(MicroButtonTooltipText(SOCIAL_BUTTON, cmd), 1, 1, 1)
    else
        GameTooltip:SetText(SOCIAL_BUTTON, 1, 1, 1)
    end

	-- Totals
	local numBNetOnline, totalBNet = GetBNetOnlineCount()
	local numWoWOnline = (GetWoWOnlineCount())
	local totalOnline = numBNetOnline + numWoWOnline

	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine("Online:", tostring(totalOnline), 1,1,1, 1,1,1)

    -- Battle.net friends (online only)
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
				GameTooltip:AddDoubleLine(left, right, 1,1,1, 1,1,1)
                listed = listed + 1
                if listed >= MAX_FRIENDS_TOOLTIP_LIST then break end
            end
        end
    end

    -- WoW friends (online only)
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
				local left = string.format("|T%s:16|t %s, %s: %s %s", statusIcon, info.name or "Friend", LEVEL, tostring(info.level or 0), info.className or "")
				local right = info.area or ""
				GameTooltip:AddDoubleLine(left, right, classColor.r, classColor.g, classColor.b, 1,1,1)
                listed = listed + 1
                if listed >= MAX_FRIENDS_TOOLTIP_LIST then break end
            end
        end
    end

	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Left-Click: Open Friends List", 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

local function Friends_Update(self)
	local bnetOnline = select(1, GetBNetOnlineCount())
	local wowOnline = select(1, GetWoWOnlineCount())
	local total = (bnetOnline or 0) + (wowOnline or 0)
	if self.Text then self.Text:SetText(total > 0 and total or "") end
end

CreateRefineMicroButton("RefineFriendsMicroButton", {
    events = { "PLAYER_ENTERING_WORLD", "UPDATE_BINDINGS", "FRIENDLIST_UPDATE", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE", "BN_FRIEND_INFO_CHANGED" },
    iconPath = "Interface\\AddOns\\RefineUI\\Media\\Textures\\Social.blp",
    bgAtlasUp = "UI-HUD-MicroMenu-SocialJournal-Up",
    bgAtlasDown = "UI-HUD-MicroMenu-SocialJournal-Down",
    text = { size = 12, point = "BOTTOM", x = 1, y = 2 },
    commandName = "TOGGLESOCIAL",
    onClick = function() if not KeybindFrames_InQuickKeybindMode() then ToggleFriendsFrame(1) end end,
    onEnter = Friends_OnEnter,
    update = Friends_Update,
    isActive = function() return FriendsFrame and FriendsFrame:IsShown() end,
})
InsertMicroButton("RefineFriendsMicroButton", "GuildMicroButton")

-- Great Vault
local function GV_OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:SetText(GREAT_VAULT_REWARDS, 1, 1, 1);
	local activities = C_WeeklyRewards.GetActivities() or {}
	local types = {
		[Enum.WeeklyRewardChestThresholdType.Activities] = "Mythic+",
		[Enum.WeeklyRewardChestThresholdType.Raid] = "Raid",
		[Enum.WeeklyRewardChestThresholdType.RankedPvP] = "Rated PvP",
		[Enum.WeeklyRewardChestThresholdType.World] = "World",
	}
	
	-- Group activities by type for better organization
	local groupedActivities = {}
	for _, a in ipairs(activities) do
		local typeName = types[a.type] or "Unknown"
		if not groupedActivities[typeName] then
			groupedActivities[typeName] = {}
		end
		table.insert(groupedActivities[typeName], a)
	end
	
    -- Display each type
    local typeOrder = {"Mythic+", "Raid", "Rated PvP", "World"}
    for _, typeName in ipairs(typeOrder) do
        local typeActivities = groupedActivities[typeName]
        if typeActivities then
            AddSectionHeader(typeName, 0.8, 0.8, 1)
			
			-- Sort by index to show slots 1, 2, 3 in order
			table.sort(typeActivities, function(a, b) return (a.index or 0) < (b.index or 0) end)
			
			for _, a in ipairs(typeActivities) do
				local slotText = "Slot " .. (a.index or 1)
				local statusText, r, g, b
				
				if a.progress >= a.threshold then
					statusText = "Unlocked"
					r, g, b = 0.2, 1, 0.2  -- Bright green
				else
					statusText = string.format("%d/%d", a.progress or 0, a.threshold or 0)
					r, g, b = 1, 1, 1  -- White
				end
				
				GameTooltip:AddDoubleLine(slotText, statusText, 0.9, 0.9, 0.9, r, g, b)
			end
		end
	end
	
	GameTooltip:Show();
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

local GreatVaultButton = CreateRefineMicroButton("RefineGreatVaultMicroButton", {
    events = { "PLAYER_ENTERING_WORLD", "WEEKLY_REWARDS_UPDATE" },
    iconAtlas = "GreatVault-32x32",
    iconSize = 28,
    -- Centered icon position via config (replaces post-creation adjust)
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
			if HideUIPanel then HideUIPanel(frame) else frame:Hide() end
		else
			WeeklyRewards_ShowUI()
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

-- Keep Great Vault button state in sync when the frame shows/hides (even if closed via Esc/X)
local gvHooksAdded = false
local function EnsureWeeklyRewardsHooks()
    if gvHooksAdded then return end
    local frame = rawget(_G, "WeeklyRewardsFrame")
    if not frame then return end
    frame:HookScript("OnShow", function()
        if GreatVaultButton then GreatVaultButton:UpdateMicroButton() end
    end)
    frame:HookScript("OnHide", function()
        if GreatVaultButton then GreatVaultButton:UpdateMicroButton() end
    end)
    gvHooksAdded = true
end

hooksecurefunc("WeeklyRewards_ShowUI", EnsureWeeklyRewardsHooks)
C_Timer.After(1, EnsureWeeklyRewardsHooks)

-- Durability
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
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    local cmd = (self and self.commandName) or "TOGGLECHARACTER0"
    if type(MicroButtonTooltipText) == "function" then
        GameTooltip:SetText(MicroButtonTooltipText("Equipment Durability", cmd), 1, 1, 1)
    else
        GameTooltip:SetText("Equipment Durability", 1, 1, 1)
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

    -- Overall
    local overall = select(1, Durability_Overall()) or 0
    local orr, org, orb = gradientColor((overall or 0) / 100)
    local overallLeft = string.format("%3.0f%%  |TInterface\\Minimap\\Tracking\\Repair:16:16:0:0:64:64:8:56:8:56|t Overall", overall)
    GameTooltip:AddDoubleLine(overallLeft, " ", orr, org, orb, 1, 1, 1)
    GameTooltip:AddLine(" ")

    -- Items below 100%
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
        GameTooltip:AddDoubleLine(left, " ", pr, pg, pb, 1, 1, 1)
    end

    -- Repair cost intentionally omitted per request

    GameTooltip:Show()
end

CreateRefineMicroButton("RefineDurabilityMicroButton", {
    events = { "PLAYER_ENTERING_WORLD", "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED", "MERCHANT_CLOSED" },
    iconPath = "Interface\\AddOns\\RefineUI\\Media\\Textures\\Anvil.blp",
    text = { size = 11, point = "BOTTOM", x = 2, y = 2 },
    commandName = "TOGGLECHARACTER0",
    onClick = function() ToggleCharacter("PaperDollFrame") end,
    onEnter = Durability_OnEnter,
    update = Durability_Update,
    isActive = function() return PaperDollFrame and PaperDollFrame:IsShown() end,
})
InsertMicroButton("RefineDurabilityMicroButton", "CharacterMicroButton")

-- =========================
-- Character Micro Button Item Level Enhancement
-- =========================
local characterItemLevelText

local function GetPlayerItemLevel()
	local totalItemLevel = 0
	local itemCount = 0
	
	-- Slots to check (excluding shirt and tabard)
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
	
	if itemCount > 0 then
		return math.floor(totalItemLevel / itemCount)
	end
	return 0
end

local function GetItemLevelColor(itemLevel)
	-- Color coding based on item level ranges (rough guide for current content)
	if itemLevel >= 630 then
		return 1, 0.5, 0 -- Orange for very high ilvl (Mythic raid)
	elseif itemLevel >= 620 then
		return 0.64, 0.21, 0.93 -- Purple for high ilvl (Heroic raid)
	elseif itemLevel >= 610 then
		return 0, 0.44, 0.87 -- Blue for decent ilvl (Normal raid)
	elseif itemLevel >= 590 then
		return 0.12, 1, 0 -- Green for moderate ilvl (LFR/M+ low)
	elseif itemLevel >= 570 then
		return 1, 1, 1 -- White for basic max level gear
	elseif itemLevel >= 500 then
		return 0.62, 0.62, 0.62 -- Gray for leveling gear
	else
		return 1, 0, 0 -- Red for very low gear
	end
end

local function UpdateCharacterItemLevel()
	if CharacterMicroButton and not characterItemLevelText then
		characterItemLevelText = CharacterMicroButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		characterItemLevelText:SetFont(C.media.normalFont, 11, "OUTLINE")
		characterItemLevelText:SetPoint("BOTTOM", CharacterMicroButton, "BOTTOM", 2, 2)
		characterItemLevelText:SetJustifyH("CENTER")
		characterItemLevelText:SetJustifyV("BOTTOM")
	end
	
	if characterItemLevelText then
		local itemLevel = GetPlayerItemLevel()
		if itemLevel > 0 then
			characterItemLevelText:SetText(itemLevel)
			local r, g, b = GetItemLevelColor(itemLevel)
			characterItemLevelText:SetTextColor(r, g, b)
		else
			characterItemLevelText:SetText("")
		end
	end
end

-- Create frame to handle events for item level updates
local itemLevelFrame = CreateFrame("Frame", "CharacterItemLevelFrame", UIParent)
itemLevelFrame:RegisterEvent("PLAYER_LOGIN")
itemLevelFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
itemLevelFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
itemLevelFrame:RegisterEvent("BAG_UPDATE")

itemLevelFrame:SetScript("OnEvent", function(_, event)
	-- Coalesce bursts of events into a single update
	if not itemLevelFrame._pendingILvl then
		itemLevelFrame._pendingILvl = true
		C_Timer.After(0.1, function()
			UpdateCharacterItemLevel()
			itemLevelFrame._pendingILvl = false
		end)
	end
end)

-- Update when micro buttons are updated
hooksecurefunc("UpdateMicroButtons", UpdateCharacterItemLevel)

-- =========================
-- Game Menu Micro Button: Latency Text
-- =========================
do
    local latencyText

    local function GetLatency()
        if type(GetNetStats) == "function" then
            local _, _, homeMS, worldMS = GetNetStats()
            return worldMS or homeMS or 0
        end
        return 0
    end

    local function LatencyColor(ms)
        if ms <= 60 then return 0, 1, 0 end      -- green
        if ms <= 120 then return 1, 1, 0 end     -- yellow
        return 1, 0, 0                           -- red
    end

    local function EnsureLatencyText()
        local b = rawget(_G, "MainMenuMicroButton")
        if not b then return end
        if not latencyText then
            latencyText = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            latencyText:SetFont(C.media.normalFont, 11, "OUTLINE")
            latencyText:SetPoint("BOTTOM", b, "BOTTOM", 2, 2)
            latencyText:SetJustifyH("CENTER")
        end
        return b, latencyText
    end

    local function UpdateLatency()
        local b = EnsureLatencyText()
        if not b or not latencyText then return end
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

    -- Periodic updates + on common moments
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("ZONE_CHANGED")
    f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    f:SetScript("OnEvent", function() C_Timer.After(0.1, UpdateLatency) end)

    C_Timer.NewTicker(5, UpdateLatency)
    hooksecurefunc("UpdateMicroButtons", UpdateLatency)
end

-- =========================
-- Group Finder: Queue Time Text
-- =========================
do
    local LFGButton = rawget(_G, "LFDMicroButton") or rawget(_G, "GroupFinderMicroButton")
    local lfgText, lfgTicker, lfgStart
    -- Forward declare so closures capture local, not global
    local LFG_IsQueued
    local LFG_GetStartTime

    local function SecondsToMMSS(sec)
        sec = math.max(0, math.floor(sec or 0))
        local m = math.floor(sec / 60)
        local s = sec % 60
        return string.format("%d:%02d", m, s)
    end

    local function EnsureLFGButton()
        if not LFGButton then
            LFGButton = rawget(_G, "LFDMicroButton") or rawget(_G, "GroupFinderMicroButton")
        end
        if LFGButton and not lfgText then
            lfgText = LFGButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            lfgText:SetFont(C.media.normalFont, 10, "OUTLINE")
            lfgText:SetPoint("BOTTOM", LFGButton, "BOTTOM", 2, 2)
            lfgText:SetTextColor(0, 1, 0)
            lfgText:SetJustifyH("CENTER")
            lfgText:Hide()
        end

        -- Hook to mimic minimap queue button behavior (tooltip + right-click menu)
        local function LFG_ShowDefaultTooltip(owner)
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            local title = GROUP_FINDER or "Group Finder"
            local cmd = (owner and owner.commandName) or "TOGGLEGROUPFINDER"
            if type(MicroButtonTooltipText) == "function" then
                GameTooltip:SetText(MicroButtonTooltipText(title, cmd), 1, 1, 1)
            else
                GameTooltip:SetText(title, 1, 1, 1)
            end

            -- Saved Raids
            local anyRaid = false
            if type(GetNumSavedInstances) == "function" and type(GetSavedInstanceInfo) == "function" then
                local n = GetNumSavedInstances() or 0
                for i = 1, n do
                    local name, _, _, _, locked, extended, _, isRaid, _, difficultyName, numEncounters, encounterProgress = GetSavedInstanceInfo(i)
                    if isRaid then
                        if (encounterProgress and encounterProgress > 0) or locked or extended then
                            if not anyRaid then AddSectionHeader("Saved Raids"); anyRaid = true end
                            local left = string.format("%s (%s)", name or UNKNOWN, difficultyName or "")
                            local right = string.format("%d/%d", tonumber(encounterProgress or 0) or 0, tonumber(numEncounters or 0) or 0)
                            GameTooltip:AddDoubleLine(left, right, 0.9, 0.9, 1, 1, 1, 1)
                        end
                    end
                end
            end
            if not anyRaid then
                AddSectionHeader("Saved Raids")
                GameTooltip:AddLine("No recent raid progress", 0.7, 0.7, 0.7)
            end

            -- Mythic+ section
            local hasM = false
            if C_MythicPlus then
                local level = C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel()
                local mapID = C_MythicPlus.GetOwnedKeystoneMapID and C_MythicPlus.GetOwnedKeystoneMapID()
                local mapName
                if mapID and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
                    mapName = C_ChallengeMode.GetMapUIInfo(mapID)
                end
                local affixes = C_MythicPlus.GetCurrentAffixes and C_MythicPlus.GetCurrentAffixes()
                if level or (affixes and #affixes > 0) then
                    AddSectionHeader("Mythic+", 0.6, 1, 0.6)
                    hasM = true
                    if level and level > 0 then
                        local keyText = string.format("Keystone: %s +%d", mapName or "Unknown", level)
                        GameTooltip:AddLine(keyText, 1, 1, 1)
                    else
                        GameTooltip:AddLine("No keystone owned", 0.7, 0.7, 0.7)
                    end
                    if affixes and #affixes > 0 then
                        local names = {}
                        for _, info in ipairs(affixes) do
                            local name = (C_ChallengeMode and C_ChallengeMode.GetAffixInfo and select(1, C_ChallengeMode.GetAffixInfo(info.id))) or (info and info.name)
                            if name then table.insert(names, name) end
                        end
                        if #names > 0 then
                            GameTooltip:AddLine("Affixes: " .. table.concat(names, ", "), 0.9, 0.9, 0.9)
                        end
                    end
                end
            end
            if not hasM then
                AddSectionHeader("Mythic+", 0.6, 1, 0.6)
                GameTooltip:AddLine("No active information", 0.7, 0.7, 0.7)
            end

            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Left-Click: Open Group Finder", 0.7, 0.7, 0.7)
            GameTooltip:AddLine("Right-Click: Queue Menu", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end

        local function Refine_ShowQueueTooltip(owner)
            if LFG_IsQueued and LFG_IsQueued() then
                if QueueStatusFrame and QueueStatusFrame.Update then
                    GameTooltip:Hide()
                    QueueStatusFrame:Update()
                    QueueStatusFrame:ClearAllPoints()
                    QueueStatusFrame:SetPoint("TOPLEFT", owner, "TOPRIGHT", 0, 25)
                    QueueStatusFrame:Show()
                    return
                elseif type(QueueStatusMinimapButton_OnEnter) == "function" then
                    GameTooltip:Hide()
                    QueueStatusMinimapButton_OnEnter(owner)
                    return
                end
            end
            -- Fallback: show custom summary when not queued or Blizzard handlers unavailable
            LFG_ShowDefaultTooltip(owner)
        end

        local function Refine_HideQueueTooltip()
            if QueueStatusFrame and QueueStatusFrame.Hide then
                QueueStatusFrame:Hide()
            else
                GameTooltip_Hide()
            end
        end

        local function Refine_ShowQueueContextMenu(owner)
            if MenuUtil and MenuUtil.CreateContextMenu then
                MenuUtil.CreateContextMenu(owner, function(menuOwner, root)
                    root:SetTag("MENU_QUEUE_STATUS_FRAME")

                    if C_LobbyMatchmakerInfo and C_LobbyMatchmakerInfo.IsInQueue and C_LobbyMatchmakerInfo.IsInQueue() then
                        if type(QueueStatusDropdown_AddPlunderstormButtons) == "function" then
                            QueueStatusDropdown_AddPlunderstormButtons(root)
                        end
                    end

                    if NUM_LE_LFG_CATEGORYS and type(GetLFGMode) == "function" then
                        for i = 1, NUM_LE_LFG_CATEGORYS do
                            local mode, submode = GetLFGMode(i)
                            if mode and submode ~= "noteleport" then
                                if type(QueueStatusDropdown_AddLFGButtons) == "function" then
                                    QueueStatusDropdown_AddLFGButtons(root, i)
                                end
                            end
                        end
                    end

                    if C_LFGList and C_LFGList.HasActiveEntryInfo and C_LFGList.HasActiveEntryInfo() then
                        if type(QueueStatusDropdown_AddLFGListButtons) == "function" then
                            QueueStatusDropdown_AddLFGListButtons(root)
                        end
                    end

                    if C_LFGList and C_LFGList.GetApplications then
                        local apps = C_LFGList.GetApplications()
                        for i = 1, (apps and #apps or 0) do
                            local _, appStatus = C_LFGList.GetApplicationInfo(apps[i])
                            if appStatus == "applied" then
                                if type(QueueStatusDropdown_AddLFGListApplicationButtons) == "function" then
                                    QueueStatusDropdown_AddLFGListApplicationButtons(root, apps[i])
                                end
                            end
                        end
                    end

                    local inProgress, _, _, _, _, isBattleground = GetLFGRoleUpdate and GetLFGRoleUpdate()
                    if inProgress and isBattleground and type(QueueStatusDropdown_AddPVPRoleCheckButtons) == "function" then
                        QueueStatusDropdown_AddPVPRoleCheckButtons(root)
                    end

                    if type(GetMaxBattlefieldID) == "function" then
                        for i = 1, GetMaxBattlefieldID() do
                            local status = select(1, GetBattlefieldStatus(i))
                            if status and status ~= "none" then
                                if type(QueueStatusDropdown_AddBattlefield) == "function" then
                                    QueueStatusDropdown_AddBattlefield(root, i)
                                elseif type(QueueStatusDropdown_AddBattlefieldButtons) == "function" then
                                    QueueStatusDropdown_AddBattlefieldButtons(root, i)
                                end
                            end
                        end
                    end

                    if MAX_WORLD_PVP_QUEUES and type(GetWorldPVPQueueStatus) == "function" then
                        for i = 1, MAX_WORLD_PVP_QUEUES do
                            local status = select(1, GetWorldPVPQueueStatus(i))
                            if status and status ~= "none" then
                                if type(QueueStatusDropdown_AddWorldPvPButtons) == "function" then
                                    QueueStatusDropdown_AddWorldPvPButtons(root, i)
                                end
                            end
                        end
                    end

                    if CanHearthAndResurrectFromArea and CanHearthAndResurrectFromArea() then
                        local name = GetRealZoneText and GetRealZoneText() or ""
                        if name ~= "" and root.CreateTitle then
                            root:CreateTitle("|cff19ff19"..name.."|r")
                        end
                        if root.CreateButton and type(HearthAndResurrectFromArea) == "function" then
                            root:CreateButton(string.format(LEAVE_ZONE, name), function() HearthAndResurrectFromArea() end)
                        end
                    end

                    if C_PetBattles and C_PetBattles.GetPVPMatchmakingInfo and C_PetBattles.GetPVPMatchmakingInfo() then
                        if type(QueueStatusDropdown_AddPetBattleButtons) == "function" then
                            QueueStatusDropdown_AddPetBattleButtons(root)
                        end
                    end
                end)
                return
            end

            -- Fallback to Blizzard click handler if available
            if type(QueueStatusMinimapButton_OnClick) == "function" then
                QueueStatusMinimapButton_OnClick(owner, "RightButton")
            end
        end

        if LFGButton and not LFGButton._refineLFGHooked then
            local originalOnClick = LFGButton:GetScript("OnClick")
            LFGButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            LFGButton:SetScript("OnClick", function(self, button)
                if button == "RightButton" then
                    -- Ensure any tooltip/QueueStatusFrame is closed before opening the menu
                    if GameTooltip then GameTooltip:Hide() end
                    if type(Refine_HideQueueTooltip) == "function" then Refine_HideQueueTooltip() end
                    Refine_ShowQueueContextMenu(self)
                else
                    if originalOnClick then originalOnClick(self, button) end
                end
            end)

            LFGButton:HookScript("OnEnter", function(self)
                Refine_ShowQueueTooltip(self)
            end)

            LFGButton:HookScript("OnLeave", function()
                Refine_HideQueueTooltip()
            end)
            LFGButton._refineLFGHooked = true
        end
    end

    function LFG_IsQueued()
        -- Prefer built-in queue indicator if present
        local qmb = rawget(_G, "QueueStatusMinimapButton")
        if qmb and qmb:IsShown() then return true end
        -- Check PvP queues
        if type(GetBattlefieldStatus) == "function" then
            local MAX_BATTLEFIELD_QUEUES = 3
            for i = 1, MAX_BATTLEFIELD_QUEUES do
                local status = GetBattlefieldStatus(i)
                if status and status ~= "none" then return true end
            end
        end
        -- Check dungeon/scenario/LFR queues if available
        if type(GetLFGMode) == "function" then
            local categories = { _G.LE_LFG_CATEGORY_LFD, _G.LE_LFG_CATEGORY_SCENARIO, _G.LE_LFG_CATEGORY_LFR } 
            for _, cat in ipairs(categories) do
                if cat then
                    local mode = GetLFGMode(cat)
                    if mode and mode ~= "none" then return true end
                end
            end
        end
        return false
    end

    -- Determine the earliest queue start time across queue systems
    function LFG_GetStartTime()
        local earliest
        local function consider(ts)
            if ts and ts > 0 then
                if not earliest or ts < earliest then earliest = ts end
            end
        end

        -- Plunderstorm / Lobby queue
        if C_LobbyMatchmakerInfo and C_LobbyMatchmakerInfo.GetQueueStartTime then
            consider(C_LobbyMatchmakerInfo.GetQueueStartTime()) -- returns absolute start timestamp (seconds)
        end

        -- LFG categories (dungeon/scenario/LFR/RF/etc.)
        if NUM_LE_LFG_CATEGORYS and type(GetLFGQueueStats) == "function" then
            for i = 1, NUM_LE_LFG_CATEGORYS do
                local activeID = select(18, GetLFGQueueStats(i))
                if activeID then
                    local _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, queuedTime = GetLFGQueueStats(i, activeID)
                    consider(queuedTime) -- Blizzard uses this as absolute start time
                end
            end
        end

        -- Battlefield queues (BG/Arena): API returns waited ms; convert to start timestamp
        if type(GetMaxBattlefieldID) == "function" and type(GetBattlefieldStatus) == "function" then
            local now = GetTime()
            for i = 1, GetMaxBattlefieldID() do
                local status, _, _, _, suspend = GetBattlefieldStatus(i)
                if status == "queued" and not suspend then
                    local waitedMS = GetBattlefieldTimeWaited(i)
                    if waitedMS and waitedMS > 0 then
                        consider(now - (waitedMS / 1000))
                    end
                end
            end
        end

        -- World PvP queues: API returns queuedTime ms and average ; Blizzard divides by 1000 and treats as start timestamp
        if MAX_WORLD_PVP_QUEUES and type(GetWorldPVPQueueStatus) == "function" then
            for i = 1, MAX_WORLD_PVP_QUEUES do
                local status, _, _, _, _, queuedTime = GetWorldPVPQueueStatus(i)
                if status == "queued" and queuedTime and queuedTime > 0 then
                    consider(queuedTime / 1000)
                end
            end
        end

        -- Pet Battles PvP: returns status, estimatedTime, queuedTime (seconds)
        if C_PetBattles and C_PetBattles.GetPVPMatchmakingInfo then
            local status, _, queuedTime = C_PetBattles.GetPVPMatchmakingInfo()
            if status == "queued" and queuedTime and queuedTime > 0 then
                consider(queuedTime)
            end
        end

        return earliest
    end

    local function LFG_UpdateText()
        EnsureLFGButton()
        if not LFGButton or not lfgText then return end
        if lfgStart then
            local elapsed = GetTime() - lfgStart
            lfgText:SetText(SecondsToMMSS(elapsed))
            lfgText:Show()
        else
            lfgText:SetText("")
            lfgText:Hide()
        end
    end

    local function LFG_Start()
        EnsureLFGButton()
        if not LFGButton then return end
        lfgStart = LFG_GetStartTime() or GetTime()
        if not lfgTicker then lfgTicker = C_Timer.NewTicker(1, LFG_UpdateText) end
        LFG_UpdateText()
    end

    local function LFG_Stop()
        lfgStart = nil
        if lfgTicker then lfgTicker:Cancel(); lfgTicker = nil end
        LFG_UpdateText()
    end

    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_LOGIN")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("LFG_QUEUE_STATUS_UPDATE")
    eventFrame:RegisterEvent("LFG_UPDATE")
    -- Retail no longer fires PVP_QUEUE_STATUS_UPDATE; rely on UPDATE_BATTLEFIELD_STATUS
    eventFrame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
    eventFrame:SetScript("OnEvent", function()
        EnsureLFGButton()
        if LFG_IsQueued() then LFG_Start() else LFG_Stop() end
    end)

    local function EnsureLFGHooks()
        EnsureLFGButton()
        local qmb = rawget(_G, "QueueStatusMinimapButton")
        if qmb and not qmb._refineLFGHooked then
            qmb:HookScript("OnShow", function() LFG_Start() end)
            qmb:HookScript("OnHide", function() LFG_Stop() end)
            if qmb:IsShown() then LFG_Start() end
            qmb._refineLFGHooked = true
        end
    end

    C_Timer.After(0.5, EnsureLFGHooks)
    hooksecurefunc("UpdateMicroButtons", EnsureLFGHooks)
end

-- =========================
-- Bags/Backpack Micro Button
-- =========================
do
    local function Bag_GetNumSlots(bag)
        if C_Container and C_Container.GetContainerNumSlots then
            return C_Container.GetContainerNumSlots(bag) or 0
        elseif GetContainerNumSlots then
            return GetContainerNumSlots(bag) or 0
        end
        return 0
    end

    local function Bag_GetNumFreeSlots(bag)
        if C_Container and C_Container.GetContainerNumFreeSlots then
            return C_Container.GetContainerNumFreeSlots(bag) or 0
        elseif GetContainerNumFreeSlots then
            return GetContainerNumFreeSlots(bag) or 0
        end
        return 0
    end

    local function Bag_GetName(bag)
        if C_Container and C_Container.GetBagName then
            return C_Container.GetBagName(bag)
        end
        if bag == 0 then return BACKPACK_TOOLTIP or "Backpack" end
        if type(FormatLargeNumber) == "function" then return string.format("Bag %d", bag) end
        return "Bag"
    end

    local function IterateCarriedBags()
        local ids = {0,1,2,3,4}
        if type(REAGENTBAG_CONTAINER) == "number" then table.insert(ids, REAGENTBAG_CONTAINER) end
        return ids
    end

    local function Bags_TotalSlots()
        local total = 0
        for _, bag in ipairs(IterateCarriedBags()) do
            total = total + (Bag_GetNumSlots(bag) or 0)
        end
        return total
    end

    local function rgbToHex(r, g, b)
        r = math.floor((r or 1) * 255 + 0.5)
        g = math.floor((g or 1) * 255 + 0.5)
        b = math.floor((b or 1) * 255 + 0.5)
        return string.format("%02x%02x%02x", r, g, b)
    end

    local function Bags_CountFree()
        local totalFree = 0
        for _, bag in ipairs(IterateCarriedBags()) do
            totalFree = totalFree + (Bag_GetNumFreeSlots(bag) or 0)
        end
        return totalFree
    end

    local function Bags_OnEnter(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        local title = BAGSLOT or "Bags"
        local cmd = (self and self.commandName) or "TOGGLEBACKPACK"
        if type(MicroButtonTooltipText) == "function" then
            GameTooltip:SetText(MicroButtonTooltipText(title, cmd), 1, 1, 1)
        else
            GameTooltip:SetText(title, 1, 1, 1)
        end

        -- Overall summary
        local totalSlots = Bags_TotalSlots()
        local totalFree = Bags_CountFree()
        local ratio = (totalSlots > 0) and (totalFree / totalSlots) or 1
        local fr, fg, fb = 0.2, 1, 0.2
        if ratio < 0.1 then fr, fg, fb = 1, 0, 0 elseif ratio < 0.3 then fr, fg, fb = 1, 1, 0 end
        local freeHex = rgbToHex(fr, fg, fb)
        AddSectionHeader("Capacity", 0.8, 0.8, 1)
        GameTooltip:AddDoubleLine("Total", string.format("%d/%d — |cff%s%d|r free", totalSlots - totalFree, totalSlots, freeHex, totalFree), 0.9, 0.9, 0.9, 1, 1, 1)

        -- Per-bag breakdown
        AddSectionHeader("Bags", 0.8, 0.8, 1)
        for _, bag in ipairs(IterateCarriedBags()) do
            local total = Bag_GetNumSlots(bag)
            if total and total > 0 then
                local free = Bag_GetNumFreeSlots(bag) or 0
                local used = total - free
                local name = Bag_GetName(bag) or (bag == 0 and (BACKPACK_TOOLTIP or "Backpack") or ("Bag "..bag))

                local nr, ng, nb = 1, 1, 1
                local invSlot = ContainerIDToInventoryID and ContainerIDToInventoryID(bag)
                if invSlot then
                    local link = GetInventoryItemLink and GetInventoryItemLink("player", invSlot)
                    if link and GetItemInfo then
                        local _, _, quality = GetItemInfo(link)
                        if quality and GetItemQualityColor then
                            nr, ng, nb = GetItemQualityColor(quality)
                        end
                    end
                end

                local rr, rg, rb = 0.2, 1, 0.2
                local ratioB = total > 0 and (free / total) or 1
                if ratioB < 0.1 then rr, rg, rb = 1, 0, 0 elseif ratioB < 0.3 then rr, rg, rb = 1, 1, 0 end
                local freeHexB = rgbToHex(rr, rg, rb)
                local right = string.format("%d/%d — |cff%s%d|r free", used, total, freeHexB, free)
                GameTooltip:AddDoubleLine(name, right, nr, ng, nb, 1, 1, 1)
            end
        end

        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-Click: Toggle Bags", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end

    local function Bags_Update(self)
        local free = Bags_CountFree()
        if self.Text then self.Text:SetText(free > 0 and tostring(free) or "") end
    end

    CreateRefineMicroButton("RefineBagsMicroButton", {
        events = { "PLAYER_ENTERING_WORLD", "BAG_UPDATE", "BAG_UPDATE_DELAYED", "BAG_SLOT_FLAGS_UPDATED" },
        iconPath = "Interface\\AddOns\\RefineUI\\Media\\Textures\\Backpack.blp",
        text = { size = 11, point = "BOTTOM", x = 2, y = 2 },
        commandName = "TOGGLEBACKPACK",
        onClick = function()
            if not KeybindFrames_InQuickKeybindMode or not KeybindFrames_InQuickKeybindMode() then
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
end

-- =========================
-- Hearth/Teleport Micro Button
-- =========================

