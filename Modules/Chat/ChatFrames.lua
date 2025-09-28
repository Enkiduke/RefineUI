local R, C, L = unpack(RefineUI)

-- Cache frequently used global functions
local _G = _G
local select = select
local type = type
local match = string.match
local gsub = string.gsub
local strsub = string.sub
local format = string.format
local ipairs = ipairs
local pairs = pairs
local string = string
local unpack = unpack
local strfind = string.find
local wipe = wipe
local math = math
local ChatFrame_AddMessageEventFilter = ChatFrame_AddMessageEventFilter
local FCF_GetChatWindowInfo = FCF_GetChatWindowInfo
local FCF_SetChatWindowFontSize = FCF_SetChatWindowFontSize
local FCF_SavePositionAndDimensions = FCF_SavePositionAndDimensions
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local IsPartyLFG = IsPartyLFG
local IsInGuild = IsInGuild
local UnitName = UnitName
local UnitClass = UnitClass
local GetNumGroupMembers = GetNumGroupMembers
local GetRaidRosterInfo = GetRaidRosterInfo
local UnitGUID = UnitGUID
local GetPlayerInfoByGUID = GetPlayerInfoByGUID
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local GetRealmName = GetRealmName
local C_Item = C_Item
local ChatEdit_AddHistory = ChatEdit_AddHistory
local IsShiftKeyDown = IsShiftKeyDown
local ChatEdit_UpdateHeader = ChatEdit_UpdateHeader
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local NORMAL_FONT_COLOR = NORMAL_FONT_COLOR

-- Local functions for performance
--[[ REMOVE THIS FUNCTION
local function Strip(info, name)
	return format("|Hplayer:%s|h[%s]|h", info, name:gsub("%-[^|]+", ""))
end
]]

local origs = {}
-- Precompile patterns used in AddMessage
local PAT_LEVEL_SIMPLIFY = "|h%[(%d+)%. .-%]|h"  -- "|h[100. Name]|h" -> "|h[100]|h"

local function AddMessage(self, text, ...)
	if type(text) == "string" then
		-- Simplify level display only if we actually match the pattern
		if match(text, PAT_LEVEL_SIMPLIFY) then
			text = gsub(text, PAT_LEVEL_SIMPLIFY, "|h[%1]|h")
		end
		-- Strip realm from player links e.g., |Hplayer:info|h[Name-Realm]|h -> |Hplayer:info|h[Name]|h
		-- Correctly handles names with hyphens like [Secret-Dredger's Sabatons]
		--[[ -- Temporarily disable realm stripping to test color bleed issue
		text = text:gsub("(|Hplayer:(.-)|h%[)(.-)(%]|h)", function(prefix, playerInfo, fullName, suffix)
			-- Remove only the part after the last hyphen (the realm)
			local nameOnly = fullName:gsub("%-[^%-]+$", "")
			return prefix .. nameOnly .. suffix
		end)
		--]]
	end
	return origs[self](self, text, ...)
end

-- Global strings
local GLOBAL_STRINGS = {
	CHAT_INSTANCE_CHAT_GET = "|Hchannel:INSTANCE_CHAT|h[" .. L_CHAT_INSTANCE_CHAT .. "]|h %s:\32",
	CHAT_INSTANCE_CHAT_LEADER_GET = "|Hchannel:INSTANCE_CHAT|h[" .. L_CHAT_INSTANCE_CHAT_LEADER .. "]|h %s:\32",
	CHAT_BN_WHISPER_GET = L_CHAT_BN_WHISPER .. " %s:\32",
	CHAT_GUILD_GET = "|Hchannel:GUILD|h[" .. L_CHAT_GUILD .. "]|h %s:\32",
	CHAT_OFFICER_GET = "|Hchannel:OFFICER|h[" .. L_CHAT_OFFICER .. "]|h %s:\32",
	CHAT_PARTY_GET = "|Hchannel:PARTY|h[" .. L_CHAT_PARTY .. "]|h %s:\32",
	CHAT_PARTY_LEADER_GET = "|Hchannel:PARTY|h[" .. L_CHAT_PARTY_LEADER .. "]|h %s:\32",
	CHAT_PARTY_GUIDE_GET = CHAT_PARTY_LEADER_GET,
	CHAT_RAID_GET = "|Hchannel:RAID|h[" .. L_CHAT_RAID .. "]|h %s:\32",
	CHAT_RAID_LEADER_GET = "|Hchannel:RAID|h[" .. L_CHAT_RAID_LEADER .. "]|h %s:\32",
	CHAT_RAID_WARNING_GET = "[" .. L_CHAT_RAID_WARNING .. "] %s:\32",
	CHAT_PET_BATTLE_COMBAT_LOG_GET = "|Hchannel:PET_BATTLE_COMBAT_LOG|h[" .. L_CHAT_PET_BATTLE .. "]|h:\32",
	CHAT_PET_BATTLE_INFO_GET = "|Hchannel:PET_BATTLE_INFO|h[" .. L_CHAT_PET_BATTLE .. "]|h:\32",
	CHAT_SAY_GET = "%s:\32",
	CHAT_WHISPER_GET = L_CHAT_WHISPER .. " %s:\32",
	CHAT_YELL_GET = "%s:\32",
	CHAT_FLAG_AFK = "|cffE7E716" .. L_CHAT_AFK .. "|r ",
	CHAT_FLAG_DND = "|cffFF0000" .. L_CHAT_DND .. "|r ",
	CHAT_FLAG_GM = "|cff4154F5" .. L_CHAT_GM .. "|r ",
	ERR_FRIEND_ONLINE_SS = "|Hplayer:%s|h[%s]|h " .. L_CHAT_COME_ONLINE,
	ERR_FRIEND_OFFLINE_S = "[%s] " .. L_CHAT_GONE_OFFLINE
}

for k, v in pairs(GLOBAL_STRINGS) do
    _G[k] = v
end

-- Hide chat bubble menu button
ChatFrameMenuButton:Kill()

-- Kill channel and voice buttons
ChatFrameChannelButton:Kill()
ChatFrameToggleVoiceDeafenButton:Kill()
ChatFrameToggleVoiceMuteButton:Kill()

local function SetChatStyle(frame)
	local id = frame:GetID()
	local chat = frame:GetName()
	local _, fontSize = FCF_GetChatWindowInfo(id)

	local chatFrame = _G[chat]
	local editBox = _G[chat .. "EditBox"]
	local tab = _G[format("ChatFrame%sTab", id)]

	chatFrame:SetFrameLevel(5)
	chatFrame:SetClampedToScreen(false)
	chatFrame:SetFading(false)

	editBox:ClearAllPoints()
	editBox:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", -10, 23)
	editBox:SetPoint("BOTTOMRIGHT", ChatFrame1, "TOPRIGHT", 11, 23)
	editBox:SetFont(C.font.chat[1], fontSize, C.font.chat[3])

	for i = 1, NUM_CHAT_WINDOWS do
		local frame = _G[format("ChatFrame%d", i)]
		frame.editBox.header:SetFont(C.font.chat[1], fontSize + 2, C.font.chat[3])
	end

	for _, textureName in ipairs(CHAT_FRAME_TEXTURES) do
		_G[chat .. textureName]:SetTexture(nil)
	end

    local elementsToKill = {
        tab and tab.Left, tab and tab.Middle, tab and tab.Right,
        tab and tab.ActiveLeft, tab and tab.ActiveMiddle, tab and tab.ActiveRight,
        tab and tab.HighlightLeft, tab and tab.HighlightMiddle, tab and tab.HighlightRight,
        _G[format("ChatFrame%sButtonFrameMinimizeButton", id)],
        _G[format("ChatFrame%sButtonFrame", id)],
        _G[format("ChatFrame%sEditBoxLeft", id)],
        _G[format("ChatFrame%sEditBoxMid", id)],
        _G[format("ChatFrame%sEditBoxRight", id)],
        _G[format("ChatFrame%sTabGlow", id)]
    }

    for _, element in ipairs(elementsToKill) do
        if element and element.Kill then element:Kill() end
    end

    if frame.ScrollBar and frame.ScrollBar.Kill then frame.ScrollBar:Kill() end
    if frame.ScrollToBottomButton and frame.ScrollToBottomButton.Kill then frame.ScrollToBottomButton:Kill() end

    local a, b, c = select(6, editBox:GetRegions())
    if a and a.Kill then a:Kill() end
    if b and b.Kill then b:Kill() end
    if c and c.Kill then c:Kill() end

	if tab.conversationIcon then tab.conversationIcon:Kill() end

	editBox:SetAltArrowKeyMode(false)
	editBox:Hide()

	local function EditBoxToggle(self, gained)
		if gained or self:GetText() ~= "" then
			self:Show()
		else
			self:Hide()
		end
	end

	editBox:HookScript("OnEditFocusGained", function(self) EditBoxToggle(self, true) end)
	editBox:HookScript("OnEditFocusLost", function(self) EditBoxToggle(self, false) end)

	tab:HookScript("OnClick", function() editBox:Hide() end)

	if _G[chat] == _G["ChatFrame2"] then
		local combatLog = CombatLogQuickButtonFrame_Custom
		combatLog:StripTextures()
		combatLog:CreateBackdrop("Transparent")
		combatLog.backdrop:SetPoint("TOPLEFT", 1, -4)
		combatLog.backdrop:SetPoint("BOTTOMRIGHT", -22, 0)
		CombatLogQuickButtonFrame_CustomAdditionalFilterButton:SetSize(12, 12)
		CombatLogQuickButtonFrame_CustomAdditionalFilterButton:SetHitRectInsets(0, 0, 0, 0)
		CombatLogQuickButtonFrame_CustomProgressBar:ClearAllPoints()
		CombatLogQuickButtonFrame_CustomProgressBar:SetPoint("TOPLEFT", combatLog.backdrop, 2, -2)
		CombatLogQuickButtonFrame_CustomProgressBar:SetPoint("BOTTOMRIGHT", combatLog.backdrop, -2, 2)
		CombatLogQuickButtonFrame_CustomProgressBar:SetStatusBarTexture(C.media.texture)
		CombatLogQuickButtonFrameButton1:SetPoint("BOTTOM", 0, 0)
	end

	-- Hook AddMessage once (skip combat log frame 2)
	local cf = _G[chat]
	if cf ~= _G["ChatFrame2"] and not origs[cf] then
		origs[cf] = cf.AddMessage
		cf.AddMessage = AddMessage
	end

	frame.skinned = true
end

local function SetupChat()
	for i = 1, NUM_CHAT_WINDOWS do
		local frame = _G[format("ChatFrame%s", i)]
		SetChatStyle(frame)
	end

	-- Remember last channel
	local stickyTypes = {
		"SAY", "PARTY", "PARTY_LEADER", "GUILD", "OFFICER", "RAID",
		"RAID_WARNING", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "WHISPER",
		"BN_WHISPER", "CHANNEL"
	}
	for _, chatType in ipairs(stickyTypes) do
		ChatTypeInfo[chatType].sticky = 1
	end
end

local function SetupChatPosAndFont()
	for i = 1, NUM_CHAT_WINDOWS do
		local chat = _G[format("ChatFrame%s", i)]
		local id = chat:GetID()
		local _, fontSize = FCF_GetChatWindowInfo(id)

		fontSize = math.max(fontSize, 11)
		FCF_SetChatWindowFontSize(nil, chat, fontSize)

		chat:SetFont(C.font.chat[1], fontSize, C.font.chat[3])
		chat:SetShadowOffset(1, -1)

		if i == 1 then
			chat:ClearAllPoints()
			chat:SetSize(C.chat.width, C.chat.height)
			chat:SetPoint(unpack(C.position.chat))
			FCF_SavePositionAndDimensions(chat)
			ChatFrame1.Selection:SetAllPoints(chat)
		elseif i == 2 and C.chat.combatlog ~= true then
			FCF_DockFrame(chat)
			ChatFrame2Tab:EnableMouse(false)
			ChatFrame2Tab.Text:Hide()
			ChatFrame2Tab:SetWidth(0.001)
			ChatFrame2Tab.SetWidth = R.dummy
			FCF_DockUpdate()
		end

		chat:SetScript("OnMouseWheel", FloatingChatFrame_OnMouseScroll)
	end

	QuickJoinToastButton:ClearAllPoints()
	QuickJoinToastButton:SetPoint("TOPLEFT", 0, 90)
	QuickJoinToastButton.ClearAllPoints = R.dummy
	QuickJoinToastButton.SetPoint = R.dummy

	QuickJoinToastButton.Toast:ClearAllPoints()
	QuickJoinToastButton.Toast:SetPoint(unpack(C.position.bnPopup))
	QuickJoinToastButton.Toast.Background:SetTexture("")
	QuickJoinToastButton.Toast:SetWidth(C.chat.width + 7)
	QuickJoinToastButton.Toast.Text:SetWidth(C.chat.width - 20)

	BNToastFrame:ClearAllPoints()
	BNToastFrame:SetPoint(unpack(C.position.bnPopup))

	hooksecurefunc(BNToastFrame, "SetPoint", function(self, _, anchor)
		if anchor ~= C.position.bnPopup[2] then
			self:ClearAllPoints()
			self:SetPoint(unpack(C.position.bnPopup))
		end
	end)
end

GeneralDockManagerOverflowButton:SetPoint("BOTTOMRIGHT", ChatFrame1, "TOPRIGHT", 0, 5)
hooksecurefunc(GeneralDockManagerScrollFrame, "SetPoint", function(self, point, anchor, attachTo, x, y)
	if anchor == GeneralDockManagerOverflowButton and x == 0 and y == 0 then
		self:SetPoint(point, anchor, attachTo, 0, -4)
	end
end)

local UIChat = CreateFrame("Frame")
UIChat:RegisterEvent("ADDON_LOADED")
UIChat:RegisterEvent("PLAYER_ENTERING_WORLD")
UIChat:SetScript("OnEvent", function(self, event, addon)
	if event == "ADDON_LOADED" and addon == "Blizzard_CombatLog" then
		self:UnregisterEvent("ADDON_LOADED")
        SetupChat()
	elseif event == "PLAYER_ENTERING_WORLD" then
		self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        SetupChatPosAndFont()
	end
end)

local function SetupTempChat()
	local frame = FCF_GetCurrentChatFrame()
	if not frame.skinned then
		SetChatStyle(frame)
	end
end
hooksecurefunc("FCF_OpenTemporaryWindow", SetupTempChat)

local old = FCFManager_GetNumDedicatedFrames
function FCFManager_GetNumDedicatedFrames(...)
	return select(1, ...) ~= "PET_BATTLE_COMBAT_LOG" and old(...) or 1
end

local function RemoveRealmName(_, _, msg, author, ...)
	local realm = gsub(R.realm, " ", "")
	if msg:find("-" .. realm) then
		return false, gsub(msg, "%-" .. realm, ""), author, ...
	end
end
ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", RemoveRealmName)

local function TypoHistory_Posthook_AddMessage(chat, text)
	if text and strfind(text, HELP_TEXT_SIMPLE) then
		ChatEdit_AddHistory(chat.editBox)
	end
end

for i = 1, NUM_CHAT_WINDOWS do
    if i ~= 2 then
        hooksecurefunc(_G["ChatFrame" .. i], "AddMessage", TypoHistory_Posthook_AddMessage)
    end
end

-- Switch channels by Tab
local cycles = {
	{ chatType = "SAY",           use = function() return 1 end },
	{ chatType = "PARTY",         use = function() return IsInGroup(LE_PARTY_CATEGORY_HOME) end },
	{ chatType = "RAID",          use = function() return IsInRaid(LE_PARTY_CATEGORY_HOME) end },
	{ chatType = "INSTANCE_CHAT", use = function() return IsPartyLFG() end },
	{ chatType = "GUILD",         use = function() return IsInGuild() end },
	{ chatType = "SAY",           use = function() return 1 end },
}

local function UpdateTabChannelSwitch(self)
	local txt = self:GetText() or ""
	if strsub(txt, 1, 1) == "/" then return end
	local currChatType = self:GetAttribute("chatType")
	local n = #cycles
	for i = 1, n do
		local curr = cycles[i]
		if curr.chatType == currChatType then
			local h, r, step = i + 1, n, 1
			if IsShiftKeyDown() then h, r, step = i - 1, 1, -1 end
			for j = h, r, step do
				local nextCycle = cycles[j]
				if nextCycle:use() then
					self:SetAttribute("chatType", nextCycle.chatType)
                    ChatEdit_UpdateHeader(self)
					return
				end
			end
		end
	end
end
hooksecurefunc("ChatEdit_CustomTabPressed", UpdateTabChannelSwitch)

-- Return the module
return UIChat
