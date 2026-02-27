----------------------------------------------------------------------------------------
-- ChatFrames for RefineUI (Direct Port)
-- Description: Customizes chat frame styling, positioning, and behavior
----------------------------------------------------------------------------------------

local _, RefineUI = ...

local Chat = RefineUI:GetModule("Chat") or RefineUI:RegisterModule("Chat")

function Chat:OnInitialize()
    self.db = RefineUI.DB and RefineUI.DB.Chat or RefineUI.Config.Chat
    self.positions = RefineUI.DB and RefineUI.DB.Positions or RefineUI.Positions
end

----------------------------------------------------------------------------------------
-- Lib Globals (Upvalues)
----------------------------------------------------------------------------------------
local _G = _G
local pairs, ipairs, unpack, select = pairs, ipairs, unpack, select
local format, gsub, strsub, strfind = string.format, string.gsub, string.sub, string.find
local type, tostring = type, tostring
local math = math
local tonumber = tonumber
local issecretvalue = _G.issecretvalue

----------------------------------------------------------------------------------------
-- WoW Globals (Upvalues)
----------------------------------------------------------------------------------------
local ChatFrame_AddMessageEventFilter = ChatFrame_AddMessageEventFilter
local FCF_GetChatWindowInfo = FCF_GetChatWindowInfo
local FCF_SetChatWindowFontSize = FCF_SetChatWindowFontSize
local FCF_SavePositionAndDimensions = FCF_SavePositionAndDimensions
local FCF_DockFrame = FCF_DockFrame
local FCF_DockUpdate = FCF_DockUpdate
local FCF_GetCurrentChatFrame = FCF_GetCurrentChatFrame
local ChatEdit_UpdateHeader = ChatEdit_UpdateHeader
local hooksecurefunc = hooksecurefunc
local C_Timer = C_Timer
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local IsPartyLFG = IsPartyLFG
local IsInGuild = IsInGuild
local IsShiftKeyDown = IsShiftKeyDown
local InCombatLockdown = InCombatLockdown
local UnitAffectingCombat = UnitAffectingCombat
local NUM_CHAT_WINDOWS = NUM_CHAT_WINDOWS
local CHAT_FRAMES = CHAT_FRAMES
local CHAT_FRAME_TEXTURES = {
	"Background", "TopLeftTexture", "BottomLeftTexture", "TopRightTexture", "BottomRightTexture",
	"LeftTexture", "RightTexture", "BottomTexture", "TopTexture",
	"ButtonFrameUpButton", "ButtonFrameDownButton", "ButtonFrameBottomButton",
	"ButtonFrameMinimizeButton", "ButtonFrame"
}
local ChatTypeInfo = ChatTypeInfo

----------------------------------------------------------------------------------------
-- Locals
----------------------------------------------------------------------------------------
local _didInstallGlobals = false
local _didInstallRuntime = false
local _didInitialChatSetup = false
local _didCombatSafeChatVisualSetup = false
local _styledFrames = {}
local _visuallyStyledFrames = {}
local _hiddenRegionLocks = setmetatable({}, { __mode = "k" })
local _editBoxAlphaHooks = setmetatable({}, { __mode = "k" })
local _editBoxBlizzArtHiddenHooks = setmetatable({}, { __mode = "k" })
local _editBoxBlizzArtElapsed = setmetatable({}, { __mode = "k" })
local _editBoxBorderColorHooks = setmetatable({}, { __mode = "k" })
local _editBoxBorderRefreshHooks = setmetatable({}, { __mode = "k" })
local _quickJoinToastRepositioning = setmetatable({}, { __mode = "k" })
local _chatDeferredWidthFixQueued = setmetatable({}, { __mode = "k" })
local _chatDeferredPointFixQueued = setmetatable({}, { __mode = "k" })
local CHAT_REGEN_SETUP_KEY = "ChatFrames:DeferredSetup"
local CHAT_WORLD_SETUP_KEY = "ChatFrames:PlayerEnteringWorld"
local CHAT_ENABLE_REGEN_SETUP_KEY = "ChatFrames:DeferredOnEnableSetup"
local CHAT_DOCK_UPDATE_REGEN_KEY = "ChatFrames:DeferredDockUpdate"
local USE_CUSTOM_EDITBOX_SKIN = false -- Safe baseline while isolating caret regression
local USE_EDITBOX_BORDER_ONLY = true  -- Step 1: border-only reintroduction
local USE_EDITBOX_HEADER_INSETS = false -- Keep Blizzard header labels (Say:/Guild:/etc.)
local HIDE_BLIZZ_EDITBOX_BORDER_TEXTURE = true -- Hide native border/focus textures
local EDITBOX_MIN_HEIGHT = 22
local EDITBOX_HEIGHT_PADDING = 10
local EDITBOX_BORDER_EDGE_SIZE = 12
local EDITBOX_IDLE_ALPHA = 0
local EDITBOX_ACTIVE_ALPHA = 1
local MAX_CHAT_EDITBOX_SCAN = 40
local FILTER_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER",
    "CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_CHANNEL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
    "CHAT_MSG_SYSTEM", "CHAT_MSG_LOOT", "CHAT_MSG_CURRENCY", "CHAT_MSG_MONEY",
    "CHAT_MSG_ACHIEVEMENT", "CHAT_MSG_GUILD_ACHIEVEMENT"
}

local function BuildChatFramesHookKey(owner, method, suffix)
	local ownerId
	if type(owner) == "table" and owner.GetName then
		ownerId = owner:GetName()
	end
	if not ownerId or ownerId == "" then
		ownerId = tostring(owner)
	end
	if suffix and suffix ~= "" then
		return "ChatFrames:" .. ownerId .. ":" .. method .. ":" .. suffix
	end
	return "ChatFrames:" .. ownerId .. ":" .. method
end

local function GetEditBoxHeight(fontSize)
    local size = tonumber(fontSize) or 12
    return math.max(EDITBOX_MIN_HEIGHT, size + EDITBOX_HEIGHT_PADDING)
end

local function ApplyEditBoxTypography(editBox, fontSize)
    if not editBox then return end
    local size = tonumber(fontSize) or 12
    editBox:SetHeight(GetEditBoxHeight(size))
    RefineUI.Font(editBox, size)

    local headerSize = size + 2
    local textParts = {
        editBox.header,
        editBox.headerSuffix,
        editBox.languageHeader,
        editBox.prompt,
        editBox.NewcomerHint,
    }
    for _, fs in ipairs(textParts) do
        if fs and fs.SetFont then
            RefineUI.Font(fs, headerSize)
        end
    end
end

local function IsPlayerInCombat()
    return (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
end

local function QueueFrameWidthFix(frame, width)
    if not frame or _chatDeferredWidthFixQueued[frame] or not C_Timer then return end
    _chatDeferredWidthFixQueued[frame] = true
    C_Timer.After(0, function()
        _chatDeferredWidthFixQueued[frame] = nil
        if not frame or not frame.GetWidth or not frame.SetWidth then return end
        if frame:GetWidth() > ((width or 0.001) + 0.009) then
            frame:SetWidth(width or 0.001)
        end
    end)
end

local function QueueFramePointFix(frame, applyFn)
    if not frame or not applyFn or _chatDeferredPointFixQueued[frame] or not C_Timer then return end
    _chatDeferredPointFixQueued[frame] = true
    C_Timer.After(0, function()
        _chatDeferredPointFixQueued[frame] = nil
        if not frame then return end
        applyFn(frame)
    end)
end

local function RequestDockUpdate()
    if IsPlayerInCombat() then
        RefineUI:RegisterEventCallback("PLAYER_REGEN_ENABLED", function()
            if not IsPlayerInCombat() then
                FCF_DockUpdate()
                RefineUI:OffEvent("PLAYER_REGEN_ENABLED", CHAT_DOCK_UPDATE_REGEN_KEY)
            end
        end, CHAT_DOCK_UPDATE_REGEN_KEY)
        return
    end

    if C_Timer then
        C_Timer.After(0, function()
            if not IsPlayerInCombat() then
                FCF_DockUpdate()
            else
                RefineUI:RegisterEventCallback("PLAYER_REGEN_ENABLED", function()
                    if not IsPlayerInCombat() then
                        FCF_DockUpdate()
                        RefineUI:OffEvent("PLAYER_REGEN_ENABLED", CHAT_DOCK_UPDATE_REGEN_KEY)
                    end
                end, CHAT_DOCK_UPDATE_REGEN_KEY)
            end
        end)
    else
        FCF_DockUpdate()
    end
end

local function ApplyChatFrameTypography(chatFrame, fontSize)
    if not chatFrame then return end
    local size = math.max(tonumber(fontSize) or 11, 11)
    chatFrame:SetFont(RefineUI.Media.Fonts.Attachment, size, "THINOUTLINE")
    chatFrame:SetShadowOffset(1, -1)
end

local function LockHiddenRegion(region)
    if not region then return end
    if _hiddenRegionLocks[region] then
        if region.Hide then region:Hide() end
        if region.SetAlpha then region:SetAlpha(0) end
        return
    end
    _hiddenRegionLocks[region] = true

    if region.SetTexture then
        region:SetTexture(nil)
    end
    if region.SetAtlas then
        pcall(region.SetAtlas, region, nil)
    end
    if region.SetAlpha then
        region:SetAlpha(0)
    end
    if region.Hide then
        region:Hide()
        region.Show = region.Hide
    end

    if region.SetShown then
        hooksecurefunc(region, "SetShown", function(self, shown)
            if shown then self:Hide() end
        end)
    end
    if region.Show then
        hooksecurefunc(region, "Show", function(self)
            self:Hide()
        end)
    end
    if region.SetAlpha then
        hooksecurefunc(region, "SetAlpha", function(self, alpha)
            if alpha and alpha > 0 then
                self:SetAlpha(0)
            end
        end)
    end
end

local function ForceHideAllChatEditBoxBorderRegions()
    local suffixes = { "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }
    for i = 1, MAX_CHAT_EDITBOX_SCAN do
        for _, suffix in ipairs(suffixes) do
            LockHiddenRegion(_G[format("ChatFrame%sEditBox%s", i, suffix)])
        end
    end
    if CHAT_FRAMES then
        for _, frameName in ipairs(CHAT_FRAMES) do
            local id = tonumber(tostring(frameName):match("^ChatFrame(%d+)$"))
            if id then
                for _, suffix in ipairs(suffixes) do
                    LockHiddenRegion(_G[format("ChatFrame%sEditBox%s", id, suffix)])
                end
            end
        end
    end
end

local function EnsureRefineEditBoxBorder(editBox)
    if not editBox then return end
    RefineUI.CreateBorder(editBox, 4, 4, EDITBOX_BORDER_EDGE_SIZE)
    local border = editBox.border
    if not border then return end
    border:SetFrameStrata(editBox:GetFrameStrata())
    border:SetFrameLevel(math.max(0, editBox:GetFrameLevel() + 2))
    border:SetAlpha(1)
    border:Show()
    if border.EnableMouse then
        border:EnableMouse(false)
    end
end

local function UpdateEditBoxAlpha(editBox)
    if not editBox then return end
    local alpha = EDITBOX_IDLE_ALPHA
    if editBox.HasFocus and editBox:HasFocus() then
        alpha = EDITBOX_ACTIVE_ALPHA
    end
    editBox:SetAlpha(alpha)
    if editBox.border then
        editBox.border:SetAlpha(alpha)
    end
end

local function HookEditBoxAlphaBehavior(editBox)
    if not editBox or _editBoxAlphaHooks[editBox] then return end
    _editBoxAlphaHooks[editBox] = true
    RefineUI:HookScriptOnce(BuildChatFramesHookKey(editBox, "OnShow", "RefineAlpha"), editBox, "OnShow", UpdateEditBoxAlpha)
    RefineUI:HookScriptOnce(BuildChatFramesHookKey(editBox, "OnEditFocusGained", "RefineAlpha"), editBox, "OnEditFocusGained", UpdateEditBoxAlpha)
    RefineUI:HookScriptOnce(BuildChatFramesHookKey(editBox, "OnEditFocusLost", "RefineAlpha"), editBox, "OnEditFocusLost", UpdateEditBoxAlpha)
    RefineUI:HookScriptOnce(BuildChatFramesHookKey(editBox, "OnTextChanged", "RefineAlpha"), editBox, "OnTextChanged", UpdateEditBoxAlpha)
    UpdateEditBoxAlpha(editBox)
end

local function RemoveBlizzardEditBoxArt(editBox, chatName, id)
    local chromeRegions = {
        editBox.Left, editBox.Mid, editBox.Right,
        editBox.left, editBox.mid, editBox.right,
        _G[chatName .. "EditBoxLeft"], _G[chatName .. "EditBoxMid"], _G[chatName .. "EditBoxRight"],
        _G[format("ChatFrame%sEditBoxLeft", id)], _G[format("ChatFrame%sEditBoxMid", id)], _G[format("ChatFrame%sEditBoxRight", id)],
        editBox.focusLeft, editBox.focusMid, editBox.focusRight,
        editBox.FocusLeft, editBox.FocusMid, editBox.FocusRight,
        _G[chatName .. "EditBoxFocusLeft"], _G[chatName .. "EditBoxFocusMid"], _G[chatName .. "EditBoxFocusRight"],
        _G[format("ChatFrame%sEditBoxFocusLeft", id)], _G[format("ChatFrame%sEditBoxFocusMid", id)], _G[format("ChatFrame%sEditBoxFocusRight", id)],
    }

    -- Fallback for template/expansion variants: strip any chat input border textures by path.
    for i = 1, editBox:GetNumRegions() do
        local region = select(i, editBox:GetRegions())
        if region and region.IsObjectType and region:IsObjectType("Texture") and region.GetTexture then
            local texture = region:GetTexture()
            if type(texture) == "string" and strfind(texture, "ChatInputBorder", 1, true) then
                chromeRegions[#chromeRegions + 1] = region
            end
        end
    end

    for _, region in ipairs(chromeRegions) do
        LockHiddenRegion(region)
    end
end

local function EnsureBlizzardEditBoxArtHidden(editBox, chatName, id)
    if not editBox or _editBoxBlizzArtHiddenHooks[editBox] then return end
    _editBoxBlizzArtHiddenHooks[editBox] = true

    local function refresh()
        RemoveBlizzardEditBoxArt(editBox, chatName, id)
    end

    refresh()
    ForceHideAllChatEditBoxBorderRegions()
    RefineUI:HookScriptOnce(BuildChatFramesHookKey(editBox, "OnShow", "BlizzEditBoxArt"), editBox, "OnShow", refresh)
    RefineUI:HookScriptOnce(BuildChatFramesHookKey(editBox, "OnEditFocusGained", "BlizzEditBoxArt"), editBox, "OnEditFocusGained", refresh)
    RefineUI:HookScriptOnce(BuildChatFramesHookKey(editBox, "OnEditFocusLost", "BlizzEditBoxArt"), editBox, "OnEditFocusLost", refresh)
    RefineUI:HookScriptOnce(BuildChatFramesHookKey(editBox, "OnTextChanged", "BlizzEditBoxArt"), editBox, "OnTextChanged", refresh)
    RefineUI:HookScriptOnce(BuildChatFramesHookKey(editBox, "OnUpdate", "BlizzEditBoxArt"), editBox, "OnUpdate", function(self, elapsed)
        _editBoxBlizzArtElapsed[self] = (_editBoxBlizzArtElapsed[self] or 0) + (elapsed or 0)
        if _editBoxBlizzArtElapsed[self] >= 0.2 then
            _editBoxBlizzArtElapsed[self] = 0
            refresh()
        end
    end)
end

-- Channel sticky types
local STICKY_TYPES = {
	"SAY", "PARTY", "PARTY_LEADER", "GUILD", "OFFICER", "RAID",
	"RAID_WARNING", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "WHISPER",
	"BN_WHISPER", "CHANNEL"
}

-- Tab channel switch cycles
local CHANNEL_CYCLES = {
	{ chatType = "SAY",           use = function() return 1 end },
	{ chatType = "PARTY",         use = function() return not IsInRaid() and IsInGroup(LE_PARTY_CATEGORY_HOME) end },
	{ chatType = "RAID",          use = function() return IsInRaid(LE_PARTY_CATEGORY_HOME) end },
	{ chatType = "INSTANCE_CHAT", use = function() return IsPartyLFG() end },
	{ chatType = "GUILD",         use = function() return IsInGuild() end },
	{ chatType = "SAY",           use = function() return 1 end },
}

----------------------------------------------------------------------------------------
-- Global String Overrides
----------------------------------------------------------------------------------------
-- Wrapped in function for proper initialization timing
local function InstallGlobalStringsOnce()
    if _didInstallGlobals then return end
    _didInstallGlobals = true

    local L = RefineUI.Locale.Chat or {}
    
    local strings = {
        CHAT_INSTANCE_CHAT_GET = "|Hchannel:INSTANCE_CHAT|h[" .. (L.InstanceChat or "I") .. "]|h %s:\32",
        CHAT_INSTANCE_CHAT_LEADER_GET = "|Hchannel:INSTANCE_CHAT|h[" .. (L.InstanceChatLeader or "IL") .. "]|h %s:\32",
        CHAT_BN_WHISPER_GET = (L.BNWhisper or "BN") .. " %s:\32",
        CHAT_GUILD_GET = "|Hchannel:GUILD|h[" .. (L.Guild or "G") .. "]|h %s:\32",
        CHAT_OFFICER_GET = "|Hchannel:OFFICER|h[" .. (L.Officer or "O") .. "]|h %s:\32",
        CHAT_PARTY_GET = "|Hchannel:PARTY|h[" .. (L.Party or "P") .. "]|h %s:\32",
        CHAT_PARTY_LEADER_GET = "|Hchannel:PARTY|h[" .. (L.PartyLeader or "PL") .. "]|h %s:\32",
        CHAT_PARTY_GUIDE_GET = "|Hchannel:PARTY|h[" .. (L.PartyLeader or "PL") .. "]|h %s:\32",
        CHAT_RAID_GET = "|Hchannel:RAID|h[" .. (L.Raid or "R") .. "]|h %s:\32",
        CHAT_RAID_LEADER_GET = "|Hchannel:RAID|h[" .. (L.RaidLeader or "RL") .. "]|h %s:\32",
        CHAT_RAID_WARNING_GET = "[" .. (L.RaidWarning or "RW") .. "] %s:\32",
        CHAT_PET_BATTLE_COMBAT_LOG_GET = "|Hchannel:PET_BATTLE_COMBAT_LOG|h[" .. (L.PetBattle or "PB") .. "]|h:\32",
        CHAT_PET_BATTLE_INFO_GET = "|Hchannel:PET_BATTLE_INFO|h[" .. (L.PetBattle or "PB") .. "]|h:\32",
        CHAT_FLAG_AFK = "|cffE7E716" .. (L.AFK or "[AFK]") .. "|r ",
        CHAT_FLAG_DND = "|cffFF0000" .. (L.DND or "[DND]") .. "|r ",
        CHAT_FLAG_GM = "|cff4154F5" .. (L.GM or "[GM]") .. "|r ",
        ERR_FRIEND_ONLINE_SS = "|Hplayer:%s|h[%s]|h " .. (L.ComeOnline or "has come online."),
        ERR_FRIEND_OFFLINE_S = "[%s] " .. (L.GoneOffline or "has gone offline.")
    }

    for k, v in pairs(strings) do
        _G[k] = v
    end
end

----------------------------------------------------------------------------------------
-- Utility Functions
----------------------------------------------------------------------------------------

-- Modify chat messages (simplify level display) via filter (taint-safe).
-- Use varargs so newer client payload fields (e.g., bnSenderID) are preserved.
local function ChatMessageFilter(self, event, ...)
    local argc = select("#", ...)
    local args = { ... }
    local msg = args[1]
    local author = args[2]

    -- WoW 12.0+: Check for secret values to prevent crashes.
    if issecretvalue and (issecretvalue(msg) or issecretvalue(author)) then
        return false, unpack(args, 1, argc)
    end

    if type(msg) == "string" then
        -- Simplify level display e.g., |h[100. Foobar]|h -> |h[100]|h
        local success, newText = pcall(string.gsub, msg, "|h%[(%d+)%. .-%]|h", "|h[%1]|h")
        if success then
            args[1] = newText
        end
    end

    return false, unpack(args, 1, argc)
end

-- Update editbox border color and hide header text
local function UpdateEditBoxStyle(editBox)
	if not editBox then return end
	
	-- Update border color based on channel
	if editBox.border then
		local chatType = editBox:GetAttribute("chatType")
		if chatType then
			local info = ChatTypeInfo[chatType]
			if info then
				editBox.border:SetBackdropBorderColor(info.r, info.g, info.b, 1)
            else
                local c = RefineUI.Config and RefineUI.Config.General and RefineUI.Config.General.BorderColor
                if c then
                    editBox.border:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1)
                end
			end
        else
            local c = RefineUI.Config and RefineUI.Config.General and RefineUI.Config.General.BorderColor
            if c then
                editBox.border:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1)
            end
		end
	end
	
	if USE_EDITBOX_HEADER_INSETS then
		-- Optional minimalist mode: hide channel header text.
		if editBox.header then editBox.header:Hide() end
		if editBox.headerSuffix then editBox.headerSuffix:Hide() end
		editBox:SetTextInsets(8, 8, 0, 0)
	else
		if editBox.header then editBox.header:Show() end
		if editBox.headerSuffix then editBox.headerSuffix:Hide() end
	end
end

local function HookSingleEditBoxBorderColor(editBox)
    if not editBox or _editBoxBorderColorHooks[editBox] then return end
    _editBoxBorderColorHooks[editBox] = true
    RefineUI:HookScriptOnce(BuildChatFramesHookKey(editBox, "OnShow", "BorderColor"), editBox, "OnShow", UpdateEditBoxStyle)
    RefineUI:HookScriptOnce(BuildChatFramesHookKey(editBox, "OnTextChanged", "BorderColor"), editBox, "OnTextChanged", UpdateEditBoxStyle)
    RefineUI:HookScriptOnce(BuildChatFramesHookKey(editBox, "OnEditFocusGained", "BorderColor"), editBox, "OnEditFocusGained", UpdateEditBoxStyle)
    RefineUI:HookScriptOnce(BuildChatFramesHookKey(editBox, "OnEditFocusLost", "BorderColor"), editBox, "OnEditFocusLost", UpdateEditBoxStyle)
end

-- Hook editboxes for border color updates
local function HookEditBoxBorderColor()
    if CHAT_FRAMES then
        for _, frameName in ipairs(CHAT_FRAMES) do
            local frame = _G[frameName]
            if frame and frame.editBox and frame.editBox.border then
                HookSingleEditBoxBorderColor(frame.editBox)
            end
        end
    else
	    for i = 1, NUM_CHAT_WINDOWS do
		    local editBox = _G["ChatFrame"..i.."EditBox"]
		    if editBox and editBox.border then
                HookSingleEditBoxBorderColor(editBox)
		    end
	    end
    end
end

-- Remove realm name from system messages
local function RemoveRealmName(_, _, ...)
    local argc = select("#", ...)
    local args = { ... }
    local msg = args[1]

    -- Strict check for secret values or non-strings
    if (issecretvalue and issecretvalue(msg)) or type(msg) ~= "string" then
        return false, unpack(args, 1, argc)
    end
	
    local realm = gsub(RefineUI.MyRealm, " ", "")
    
    -- Safe find
    local success, found = pcall(string.find, msg, "-" .. realm, 1, true)
    
	if success and found then
        -- Safe gsub
        local successGsub, newMsg = pcall(string.gsub, msg, "%-" .. realm, "")
        if successGsub then
            args[1] = newMsg
		    return false, unpack(args, 1, argc)
        end
	end
    
    return false, unpack(args, 1, argc)
end

-- Switch channels by Tab
local function UpdateTabChannelSwitch(self)
	if strsub(tostring(self:GetText()), 1, 1) == "/" then return end
	local currChatType = self:GetAttribute("chatType")
	for i, curr in ipairs(CHANNEL_CYCLES) do
		if curr.chatType == currChatType then
			local h, r, step = i + 1, #CHANNEL_CYCLES, 1
			if IsShiftKeyDown() then h, r, step = i - 1, 1, -1 end
			for j = h, r, step do
				if CHANNEL_CYCLES[j]:use() then
					self:SetAttribute("chatType", CHANNEL_CYCLES[j].chatType)
					ChatEdit_UpdateHeader(self)
					return
				end
			end
		end
	end
end

----------------------------------------------------------------------------------------
-- Styling
----------------------------------------------------------------------------------------

local function SetChatStyle(frame, options)
	if not frame then return end
	options = options or {}
    local visualOnly = options.visualOnly == true

	-- Guard against duplicate styling
	if visualOnly then
        if _visuallyStyledFrames[frame] or _styledFrames[frame] then return end
    else
	    if _styledFrames[frame] then return end
    end
	
	local id = frame:GetID()
	local chat = frame:GetName()
	local _, fontSize = FCF_GetChatWindowInfo(id)

	local chatFrame = _G[chat]
	local editBox = _G[chat .. "EditBox"]
	local tab = _G[format("ChatFrame%sTab", id)]

	chatFrame:SetFrameLevel(5)
	chatFrame:SetClampedToScreen(false)
	chatFrame:SetFading(false)
    ApplyChatFrameTypography(chatFrame, fontSize)

    if editBox and not visualOnly then
	    -- Keep native editbox rendering, only control placement.
        editBox:ClearAllPoints()
	    editBox:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", -10, 23)
	    editBox:SetPoint("BOTTOMRIGHT", ChatFrame1, "TOPRIGHT", 11, 23)
        editBox:SetAltArrowKeyMode(false)
        ApplyEditBoxTypography(editBox, fontSize)
        if HIDE_BLIZZ_EDITBOX_BORDER_TEXTURE then
            EnsureBlizzardEditBoxArtHidden(editBox, chat, id)
        end
        if USE_EDITBOX_BORDER_ONLY then
            EnsureRefineEditBoxBorder(editBox)
            UpdateEditBoxStyle(editBox)
            HookSingleEditBoxBorderColor(editBox)
            if not _editBoxBorderRefreshHooks[editBox] then
                _editBoxBorderRefreshHooks[editBox] = true
                RefineUI:HookScriptOnce(BuildChatFramesHookKey(editBox, "OnShow", "RefineBorderRefresh"), editBox, "OnShow", EnsureRefineEditBoxBorder)
                RefineUI:HookScriptOnce(BuildChatFramesHookKey(editBox, "OnEditFocusGained", "RefineBorderRefresh"), editBox, "OnEditFocusGained", EnsureRefineEditBoxBorder)
            end
        end
        if USE_EDITBOX_HEADER_INSETS then
            if editBox.header then editBox.header:Hide() end
            if editBox.headerSuffix then editBox.headerSuffix:Hide() end
            editBox:SetTextInsets(8, 8, 0, 0)
        else
            if editBox.header then editBox.header:Show() end
            if editBox.headerSuffix then editBox.headerSuffix:Hide() end
        end
        HookEditBoxAlphaBehavior(editBox)
    end

	-- Strip default textures
	for _, textureName in ipairs(CHAT_FRAME_TEXTURES) do
        local tex = _G[chat .. textureName]
		if tex and tex.SetTexture then tex:SetTexture(nil) end
	end

	-- Kill unwanted elements
	local elementsToKill = {
		tab and tab.Left, tab and tab.Middle, tab and tab.Right,
		tab and tab.ActiveLeft, tab and tab.ActiveMiddle, tab and tab.ActiveRight,
		tab and tab.HighlightLeft, tab and tab.HighlightMiddle, tab and tab.HighlightRight,
		_G[format("ChatFrame%sButtonFrameMinimizeButton", id)],
		_G[format("ChatFrame%sButtonFrame", id)],
		_G[format("ChatFrame%sTabGlow", id)]
	}

	for _, element in ipairs(elementsToKill) do
		if element then
            if visualOnly then
                if element.SetTexture then element:SetTexture(nil) end
                if element.SetAlpha then element:SetAlpha(0) end
            else
                RefineUI.Kill(element)
            end
        end
	end

	if frame.ScrollBar then
        if visualOnly then
            if frame.ScrollBar.SetAlpha then frame.ScrollBar:SetAlpha(0) end
        else
            RefineUI.Kill(frame.ScrollBar)
        end
    end
	if frame.ScrollToBottomButton then
        if visualOnly then
            if frame.ScrollToBottomButton.SetAlpha then frame.ScrollToBottomButton:SetAlpha(0) end
        else
            RefineUI.Kill(frame.ScrollToBottomButton)
        end
    end

	if tab and tab.conversationIcon then
        if visualOnly then
            if tab.conversationIcon.SetAlpha then tab.conversationIcon:SetAlpha(0) end
        else
            RefineUI.Kill(tab.conversationIcon)
        end
    end

    if not visualOnly and USE_CUSTOM_EDITBOX_SKIN and editBox then
	    -- Add RefineUI border to editbox
        EnsureBlizzardEditBoxArtHidden(editBox, chat, id)

	    -- RefineUI.AddAPI(editBox) -- REMOVED
        EnsureRefineEditBoxBorder(editBox)
	    if USE_EDITBOX_HEADER_INSETS then
	        if editBox.header then editBox.header:Hide() end
	        if editBox.headerSuffix then editBox.headerSuffix:Hide() end
	        editBox:SetTextInsets(8, 8, 0, 0)
	    else
	        if editBox.header then editBox.header:Show() end
	        if editBox.headerSuffix then editBox.headerSuffix:Hide() end
	    end
    end

	-- Combat log styling
	if not visualOnly and _G[chat] == _G["ChatFrame2"] then
		local combatLog = CombatLogQuickButtonFrame_Custom
		if combatLog then
			-- RefineUI.AddAPI(combatLog) -- REMOVED
			RefineUI.StripTextures(combatLog)
            RefineUI.CreateBackdrop(combatLog, "Transparent")
            combatLog.bg:SetPoint("TOPLEFT", 1, -4)
            combatLog.bg:SetPoint("BOTTOMRIGHT", -22, 0)
		end
		if CombatLogQuickButtonFrame_CustomAdditionalFilterButton then
            CombatLogQuickButtonFrame_CustomAdditionalFilterButton:SetSize(12, 12)
            CombatLogQuickButtonFrame_CustomAdditionalFilterButton:SetHitRectInsets(0, 0, 0, 0)
        end
        if combatLog and combatLog.bg and CombatLogQuickButtonFrame_CustomProgressBar then
            CombatLogQuickButtonFrame_CustomProgressBar:ClearAllPoints()
            CombatLogQuickButtonFrame_CustomProgressBar:SetPoint("TOPLEFT", combatLog.bg, 2, -2)
            CombatLogQuickButtonFrame_CustomProgressBar:SetPoint("BOTTOMRIGHT", combatLog.bg, -2, 2)
            CombatLogQuickButtonFrame_CustomProgressBar:SetStatusBarTexture(RefineUI.Media.Textures.Smooth)
        end
        if CombatLogQuickButtonFrameButton1 then
		    CombatLogQuickButtonFrameButton1:SetPoint("BOTTOM", 0, 0)
        end
	end



    local function ForEachChatTab(callback)
        if CHAT_FRAMES then
            for _, frameName in ipairs(CHAT_FRAMES) do
                local t = _G[frameName .. "Tab"]
                if t then
                    callback(t)
                end
            end
            return
        end
        for i = 1, NUM_CHAT_WINDOWS do
            local t = _G[format("ChatFrame%sTab", i)]
            if t then
                callback(t)
            end
        end
    end
	
	-- Hover logic for TabsMouseOver and CopyButton
    if not visualOnly then
	    frame:HookScript("OnEnter", function()
		    if Chat.db.TabsMouseOver then
                ForEachChatTab(function(t)
                    if t:IsShown() then
                        RefineUI:FadeIn(t)
                    end
                end)
		    end
		    if Chat.CopyButton then
			    RefineUI:FadeIn(Chat.CopyButton)
		    end
	    end)

	    frame:HookScript("OnLeave", function()
		    if Chat.db.TabsMouseOver then
                ForEachChatTab(function(t)
                    if t:IsShown() then
                        RefineUI:FadeOut(t)
                    end
                end)
		    end
		    if Chat.CopyButton then
			    RefineUI:FadeOut(Chat.CopyButton)
		    end
	    end)
    end

    if visualOnly then
        _visuallyStyledFrames[frame] = true
    else
        _styledFrames[frame] = true
        _visuallyStyledFrames[frame] = true
    end
end

----------------------------------------------------------------------------------------
-- Setup Functions
----------------------------------------------------------------------------------------

local function SetupChat()
	for i = 1, NUM_CHAT_WINDOWS do
		local frame = _G[format("ChatFrame%s", i)]

		SetChatStyle(frame)
	end
    if CHAT_FRAMES then
        for _, frameName in ipairs(CHAT_FRAMES) do
            local frame = _G[frameName]
            if frame and not _styledFrames[frame] then
                SetChatStyle(frame)
            end
        end
    end

    -- Keep editbox text/header font style synced with current chat font sizes.
    if CHAT_FRAMES then
        for _, frameName in ipairs(CHAT_FRAMES) do
            local f = _G[frameName]
            if f and f.GetID then
                local _, fontSize = FCF_GetChatWindowInfo(f:GetID())
                ApplyChatFrameTypography(f, fontSize)
                if f.editBox then
                    ApplyEditBoxTypography(f.editBox, fontSize)
                end
            end
        end
    end

	-- Make channels sticky
	for _, chatType in ipairs(STICKY_TYPES) do
		ChatTypeInfo[chatType].sticky = 1
	end

	-- Hook editbox border colors after borders are created
	HookEditBoxBorderColor()
    if HIDE_BLIZZ_EDITBOX_BORDER_TEXTURE then
        ForceHideAllChatEditBoxBorderRegions()
    end

    -- Use native timestamp rendering so timestamps appear at the start of each line.
    if Chat.db and Chat.db.TimeStamps then
        C_CVar.SetCVar("showTimestamps", "|cff808080[%H:%M]|r ")
    else
        C_CVar.SetCVar("showTimestamps", "none")
    end
end

local function SetupChatPosAndFont()
    if IsPlayerInCombat() then
        return false
    end

	for i = 1, NUM_CHAT_WINDOWS do
		local chat = _G[format("ChatFrame%s", i)]
		local id = chat:GetID()
		local _, fontSize = FCF_GetChatWindowInfo(id)

		fontSize = math.max(fontSize, 11)
		FCF_SetChatWindowFontSize(nil, chat, fontSize)

        ApplyChatFrameTypography(chat, fontSize)
        if chat.editBox then
            ApplyEditBoxTypography(chat.editBox, fontSize)
        end

		if i == 1 then
			chat:ClearAllPoints()
			
			-- Use Chat.db which is initialized in OnInitialize
			-- Falls back to Config values if DB not available
			local width = (Chat.db and Chat.db.Width) or 380
			local height = (Chat.db and Chat.db.Height) or 155
			
			chat:SetSize(width, height)
			if Chat.positions.ChatFrame1 then
                chat:SetPoint(unpack(Chat.positions.ChatFrame1))
            end
			FCF_SavePositionAndDimensions(chat)
			ChatFrame1.Selection:SetAllPoints(chat)
		elseif i == 2 and Chat.db.CombatLog ~= true then
			FCF_DockFrame(chat)
			ChatFrame2Tab:EnableMouse(false)
            ChatFrame2Tab.Text:Hide()
            ChatFrame2Tab:SetWidth(0.001)
            RefineUI:HookOnce(BuildChatFramesHookKey(ChatFrame2Tab, "SetWidth"), ChatFrame2Tab, "SetWidth", function(self)
                if self:GetWidth() > 0.01 then
                    QueueFrameWidthFix(self, 0.001)
                end
            end)
			RequestDockUpdate()
		end

        RefineUI:HookScriptOnce(BuildChatFramesHookKey(chat, "OnMouseWheel"), chat, "OnMouseWheel", FloatingChatFrame_OnMouseScroll)
	end
    if CHAT_FRAMES then
        for _, frameName in ipairs(CHAT_FRAMES) do
            local chat = _G[frameName]
            if chat and chat.GetID and chat:GetID() > NUM_CHAT_WINDOWS then
                local _, fontSize = FCF_GetChatWindowInfo(chat:GetID())
                fontSize = math.max(tonumber(fontSize) or 11, 11)
                FCF_SetChatWindowFontSize(nil, chat, fontSize)
                ApplyChatFrameTypography(chat, fontSize)
                if chat.editBox then
                    ApplyEditBoxTypography(chat.editBox, fontSize)
                end
            end
        end
    end

	-- Position QuickJoin button
    if QuickJoinToastButton then
        QuickJoinToastButton:ClearAllPoints()
        QuickJoinToastButton:SetPoint("TOPLEFT", 0, 90)
        
        RefineUI:HookOnce(BuildChatFramesHookKey(QuickJoinToastButton, "SetPoint"), QuickJoinToastButton, "SetPoint", function(self)
             if _quickJoinToastRepositioning[self] then return end
             local p, _, _, x, y = self:GetPoint()
             -- Simple check to avoid loop/churn
             if p ~= "TOPLEFT" or math.abs(x) > 0.1 or math.abs(y - 90) > 0.1 then
                 QueueFramePointFix(self, function(frame)
                     if _quickJoinToastRepositioning[frame] then return end
                     _quickJoinToastRepositioning[frame] = true
                     frame:ClearAllPoints()
                     frame:SetPoint("TOPLEFT", 0, 90)
                     _quickJoinToastRepositioning[frame] = false
                 end)
             end
        end)

        QuickJoinToastButton.Toast:ClearAllPoints()
        if Chat.positions.QuickJoinToastButton then
            QuickJoinToastButton.Toast:SetPoint(unpack(Chat.positions.QuickJoinToastButton))
        end
        QuickJoinToastButton.Toast.Background:SetTexture("")
        QuickJoinToastButton.Toast:SetWidth((Chat.db.Width or 380) + 7)
        QuickJoinToastButton.Toast.Text:SetWidth((Chat.db.Width or 380) - 20)
    end

    if BNToastFrame then
        BNToastFrame:ClearAllPoints()
        if Chat.positions.BNToastFrame then
            BNToastFrame:SetPoint(unpack(Chat.positions.BNToastFrame))

            RefineUI:HookOnce(BuildChatFramesHookKey(BNToastFrame, "SetPoint"), BNToastFrame, "SetPoint", function(self, _, anchor)
                if anchor ~= Chat.positions.BNToastFrame[2] then
                    QueueFramePointFix(self, function(frame)
                        frame:ClearAllPoints()
                        frame:SetPoint(unpack(Chat.positions.BNToastFrame))
                    end)
                end
            end)
        end
    end

    return true
end

local function SetupChatVisualsOnly()
    for i = 1, NUM_CHAT_WINDOWS do
        local frame = _G[format("ChatFrame%s", i)]
        SetChatStyle(frame, { visualOnly = true })
    end

    if CHAT_FRAMES then
        for _, frameName in ipairs(CHAT_FRAMES) do
            local frame = _G[frameName]
            if frame and not _styledFrames[frame] and not _visuallyStyledFrames[frame] then
                SetChatStyle(frame, { visualOnly = true })
            end
        end
    end

    -- Keep the primary chat window width/height close to configured values without touching
    -- dock state, saved layout, or points during combat reload.
    if ChatFrame1 and ChatFrame1.SetSize then
        local width = (Chat.db and Chat.db.Width) or 380
        local height = (Chat.db and Chat.db.Height) or 155
        pcall(ChatFrame1.SetSize, ChatFrame1, width, height)
    end

    if QuickJoinToastButton and QuickJoinToastButton.Toast then
        local width = (Chat.db and Chat.db.Width) or 380
        if QuickJoinToastButton.Toast.SetWidth then
            pcall(QuickJoinToastButton.Toast.SetWidth, QuickJoinToastButton.Toast, width + 7)
        end
        if QuickJoinToastButton.Toast.Text and QuickJoinToastButton.Toast.Text.SetWidth then
            pcall(QuickJoinToastButton.Toast.Text.SetWidth, QuickJoinToastButton.Toast.Text, width - 20)
        end
    end
end

local function SetupChatPosAndFontSafe()
    if SetupChatPosAndFont() then
        RefineUI:OffEvent("PLAYER_REGEN_ENABLED", CHAT_REGEN_SETUP_KEY)
        return
    end

    RefineUI:RegisterEventCallback("PLAYER_REGEN_ENABLED", function()
        if SetupChatPosAndFont() then
            RefineUI:OffEvent("PLAYER_REGEN_ENABLED", CHAT_REGEN_SETUP_KEY)
        end
    end, CHAT_REGEN_SETUP_KEY)
end

local function SetupTempChat()
	local frame = FCF_GetCurrentChatFrame()
    if not frame then return end
	if not _styledFrames[frame] then
		SetChatStyle(frame)
	end
    local _, fontSize = FCF_GetChatWindowInfo(frame:GetID())
    ApplyChatFrameTypography(frame, fontSize)
    if frame.editBox then
        ApplyEditBoxTypography(frame.editBox, fontSize)
        UpdateEditBoxStyle(frame.editBox)
    end
end

----------------------------------------------------------------------------------------
-- Runtime Wiring
----------------------------------------------------------------------------------------

local function InstallRuntimeHooksOnce()
    if _didInstallRuntime then
        return
    end
    _didInstallRuntime = true

    -- Kill chat UI buttons
    if ChatFrameMenuButton then RefineUI.Kill(ChatFrameMenuButton) end
    if ChatFrameChannelButton then RefineUI.Kill(ChatFrameChannelButton) end
    if ChatFrameToggleVoiceDeafenButton then RefineUI.Kill(ChatFrameToggleVoiceDeafenButton) end
    if ChatFrameToggleVoiceMuteButton then RefineUI.Kill(ChatFrameToggleVoiceMuteButton) end

    -- Position overflow button
    if GeneralDockManagerOverflowButton then
        GeneralDockManagerOverflowButton:SetPoint("BOTTOMRIGHT", ChatFrame1, "TOPRIGHT", 0, 5)
    end
    if GeneralDockManagerScrollFrame then
        RefineUI:HookOnce(BuildChatFramesHookKey(GeneralDockManagerScrollFrame, "SetPoint"), GeneralDockManagerScrollFrame, "SetPoint", function(self, point, anchor, attachTo, x, y)
            if anchor == GeneralDockManagerOverflowButton and x == 0 and y == 0 then
                QueueFramePointFix(self, function(frame)
                    frame:SetPoint(point, anchor, attachTo, 0, -4)
                end)
            end
        end)
    end

    -- Register message filters
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", RemoveRealmName)
    for _, event in ipairs(FILTER_EVENTS) do
        ChatFrame_AddMessageEventFilter(event, ChatMessageFilter)
    end

    -- Hook temporary window creation
    RefineUI:HookOnce("ChatFrames:FCF_OpenTemporaryWindow", "FCF_OpenTemporaryWindow", SetupTempChat)

    -- Hook Tab channel switching
    RefineUI:HookOnce("ChatFrames:ChatEdit_CustomTabPressed", "ChatEdit_CustomTabPressed", UpdateTabChannelSwitch)
    if HIDE_BLIZZ_EDITBOX_BORDER_TEXTURE then
        RefineUI:HookOnce("ChatFrames:ChatEdit_UpdateHeader:HideBlizzEditBoxArt", "ChatEdit_UpdateHeader", function(editBox)
            local frame = editBox and editBox.chatFrame
            if frame and frame.GetName and frame.GetID then
                EnsureBlizzardEditBoxArtHidden(editBox, frame:GetName(), frame:GetID())
                HookSingleEditBoxBorderColor(editBox)
                UpdateEditBoxStyle(editBox)
            else
                ForceHideAllChatEditBoxBorderRegions()
            end
        end)
    end

    -- Keep editbox typography in sync when chat font size changes at runtime.
    RefineUI:HookOnce("ChatFrames:FCF_SetChatWindowFontSize", "FCF_SetChatWindowFontSize", function(arg1, arg2, arg3)
        local frame, size
        if type(arg1) == "table" and arg1.GetID then
            frame, size = arg1, arg2
        elseif type(arg2) == "table" and arg2.GetID then
            frame, size = arg2, arg3
        end
        if frame then
            ApplyChatFrameTypography(frame, size)
            if frame.editBox then
                ApplyEditBoxTypography(frame.editBox, size)
                UpdateEditBoxStyle(frame.editBox)
            end
        end
    end)
end

----------------------------------------------------------------------------------------
-- Event Handling
----------------------------------------------------------------------------------------

local function RunInitialChatSetup()
    if _didInitialChatSetup then
        return true
    end

    if IsPlayerInCombat() then
        return false
    end

    InstallRuntimeHooksOnce()
    SetupChat()
    SetupChatPosAndFontSafe()
    Chat:SetupTabs()
    Chat:SetupIcons()
    Chat:SetupLootIcons()
    Chat:SetupCopy()
    if Chat.SetupHistory then
        Chat:SetupHistory()
    end

    _didInitialChatSetup = true
    _didCombatSafeChatVisualSetup = true
    RefineUI:OffEvent("PLAYER_REGEN_ENABLED", CHAT_ENABLE_REGEN_SETUP_KEY)
    return true
end

local function RunCombatSafeChatVisualSetup()
    if _didCombatSafeChatVisualSetup then
        return true
    end

    SetupChatVisualsOnly()
    if Chat.SetupTabsVisualsOnly then
        Chat:SetupTabsVisualsOnly()
    end
    _didCombatSafeChatVisualSetup = true
    return true
end

local function HandlePlayerEnteringWorldChatSetup()
    if not _didInitialChatSetup then
        RunInitialChatSetup()
        return
    end

    SetupChatPosAndFontSafe()
end

function Chat:OnEnable()
    if not self.db or self.db.Enable ~= true then
        return
    end

    InstallGlobalStringsOnce()

    if not RunInitialChatSetup() then
        RunCombatSafeChatVisualSetup()
        RefineUI:RegisterEventCallback("PLAYER_REGEN_ENABLED", function()
            RunInitialChatSetup()
        end, CHAT_ENABLE_REGEN_SETUP_KEY)
    end
    
    -- Re-apply position/font rules when entering world, but only after initial chat setup has safely run.
    RefineUI:RegisterEventCallback("PLAYER_ENTERING_WORLD", HandlePlayerEnteringWorldChatSetup, CHAT_WORLD_SETUP_KEY)
end
