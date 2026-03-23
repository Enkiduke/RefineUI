----------------------------------------------------------------------------------------
-- ChatFrames for RefineUI (Direct Port)
-- Description: Customizes chat frame styling, positioning, and behavior
----------------------------------------------------------------------------------------

local _, RefineUI = ...

local Chat = RefineUI:GetModule("Chat")
if not Chat then
    return
end

function Chat:OnInitialize()
    self.db = RefineUI.DB and RefineUI.DB.Chat or RefineUI.Config.Chat
    self.positions = RefineUI.DB and RefineUI.DB.Positions or RefineUI.Positions
    if self.SyncTimestampConfigFromCVar then
        self:SyncTimestampConfigFromCVar()
    end
end

----------------------------------------------------------------------------------------
-- Lib Globals (Upvalues)
----------------------------------------------------------------------------------------
local _G = _G
local ipairs, unpack, select = ipairs, unpack, select
local format, strfind = string.format, string.find
local type, tostring = type, tostring
local math = math
local tonumber = tonumber

----------------------------------------------------------------------------------------
-- WoW Globals (Upvalues)
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local FCF_GetChatWindowInfo = FCF_GetChatWindowInfo
local FCF_SetChatWindowFontSize = FCF_SetChatWindowFontSize
local FCF_SavePositionAndDimensions = FCF_SavePositionAndDimensions
local FCF_DockFrame = FCF_DockFrame
local FCF_DockUpdate = FCF_DockUpdate
local FCF_GetCurrentChatFrame = FCF_GetCurrentChatFrame
local ChatFrameUtil = ChatFrameUtil
local ChatFrameEditBoxBaseMixin = ChatFrameEditBoxBaseMixin
local ChatFrameEditBoxMixin = ChatFrameEditBoxMixin
local hooksecurefunc = hooksecurefunc
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
local _didInstallRuntime = false
local _didInitialChatSetup = false
local _didCombatSafeChatVisualSetup = false
local _styledFrames = {}
local _visuallyStyledFrames = {}
local _hiddenRegionLocks = setmetatable({}, { __mode = "k" })
local _editBoxBorderColorHooks = setmetatable({}, { __mode = "k" })
local _editBoxBorderOverlays = setmetatable({}, { __mode = "k" })
local _editBoxBackgrounds = setmetatable({}, { __mode = "k" })
local _editBoxBackgroundMasks = setmetatable({}, { __mode = "k" })
local _editBoxHeaderHookInstalled = false
local _quickJoinToastRepositioning = setmetatable({}, { __mode = "k" })
local CHAT_REGEN_SETUP_KEY = "ChatFrames:DeferredSetup"
local CHAT_WORLD_SETUP_KEY = "ChatFrames:PlayerEnteringWorld"
local CHAT_ENABLE_REGEN_SETUP_KEY = "ChatFrames:DeferredOnEnableSetup"
local CHAT_DOCK_UPDATE_REGEN_KEY = "ChatFrames:DeferredDockUpdate"
local CHAT_ENCOUNTER_STATE_KEY = "ChatFrames:EncounterStateChanged"
local CHAT_DOCK_UPDATE_TIMER_KEY = "ChatFrames:DeferredDockUpdate:Timer"
local USE_EDITBOX_BORDER_ONLY = true
local HIDE_BLIZZ_EDITBOX_BORDER_TEXTURE = true -- Hide native border/focus textures
local EDITBOX_MIN_HEIGHT = 22
local EDITBOX_HEIGHT_PADDING = 10
local EDITBOX_BORDER_EDGE_SIZE = 12
local EDITBOX_BACKGROUND_INSET = 0
local EDITBOX_BACKGROUND_ALPHA = 0.25
local EDITBOX_BACKGROUND_MASK = (RefineUI.Media and RefineUI.Media.Textures and RefineUI.Media.Textures.FrameMask)
    or "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local EDITBOX_IDLE_ALPHA = 0
local EDITBOX_ACTIVE_ALPHA = 1
local EDITBOX_ANCHOR_X = 6
local EDITBOX_ANCHOR_Y = 28
local MAX_CHAT_EDITBOX_SCAN = 40
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

local function BuildChatFramesTimerKey(owner, suffix)
    local ownerId
    if type(owner) == "table" and owner.GetName then
        ownerId = owner:GetName()
    end
    if not ownerId or ownerId == "" then
        ownerId = tostring(owner)
    end
    return "ChatFrames:" .. ownerId .. ":Timer:" .. suffix
end

local function GetEditBoxHeight(fontSize)
    local size = tonumber(fontSize) or 12
    return math.max(EDITBOX_MIN_HEIGHT, size + EDITBOX_HEIGHT_PADDING)
end

local function ApplyEditBoxLayout(editBox, chatFrame)
    if not editBox or not chatFrame then
        return
    end

    editBox:ClearAllPoints()
    editBox:SetPoint("BOTTOMLEFT", chatFrame, "TOPLEFT", -EDITBOX_ANCHOR_X, EDITBOX_ANCHOR_Y)
    editBox:SetPoint("BOTTOMRIGHT", chatFrame, "TOPRIGHT", EDITBOX_ANCHOR_X, EDITBOX_ANCHOR_Y)
    editBox:SetAltArrowKeyMode(false)
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
    if not frame then return end
    RefineUI:After(BuildChatFramesTimerKey(frame, "WidthFix"), 0, function()
        if not frame or not frame.GetWidth or not frame.SetWidth then return end
        if frame:GetWidth() > ((width or 0.001) + 0.009) then
            frame:SetWidth(width or 0.001)
        end
    end)
end

local function QueueFramePointFix(frame, applyFn)
    if not frame or not applyFn then return end
    RefineUI:After(BuildChatFramesTimerKey(frame, "PointFix"), 0, function()
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

    RefineUI:After(CHAT_DOCK_UPDATE_TIMER_KEY, 0, function()
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
end

local function ApplyChatFrameTypography(chatFrame, fontSize)
    if not chatFrame then return end
    local size = math.max(tonumber(fontSize) or 11, 11)
    chatFrame:SetFont(RefineUI.Media.Fonts.Attachment, size, "THINOUTLINE")
    chatFrame:SetShadowOffset(1, -1)
end

local function GetConfiguredPrimaryChatSize()
    local width = (Chat.db and Chat.db.Width) or 380
    local height = (Chat.db and Chat.db.Height) or 155
    return width, height
end

local function GetPrimaryChatSize()
    local defaultWidth, defaultHeight = GetConfiguredPrimaryChatSize()
    if ChatFrame1 and ChatFrame1.GetWidth and ChatFrame1.GetHeight then
        local width = ChatFrame1:GetWidth()
        local height = ChatFrame1:GetHeight()
        if width and width > 0 and height and height > 0 then
            return width, height
        end
    end
    return defaultWidth, defaultHeight
end

local function UpdatePrimaryChatLinkedWidths()
    local width = GetPrimaryChatSize()
    if QuickJoinToastButton and QuickJoinToastButton.Toast then
        QuickJoinToastButton.Toast:SetWidth(width + 7)
        if QuickJoinToastButton.Toast.Text then
            QuickJoinToastButton.Toast.Text:SetWidth(width - 20)
        end
    end
end

local function HookPrimaryChatSizeUpdates()
    -- Avoid attaching script hooks to Blizzard chat frames. Those hooks taint the
    -- frame object, and encounter-time message handling later runs on that same
    -- frame through Blizzard-owned OnEvent/MessageEventHandler paths.
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

local function GetEditBoxBorderOverlay(editBox)
    if not editBox then
        return nil
    end

    local overlay = _editBoxBorderOverlays[editBox]
    if not overlay then
        overlay = CreateFrame("Frame", nil, editBox)
        overlay:EnableMouse(false)
        _editBoxBorderOverlays[editBox] = overlay
    end

    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", editBox, "TOPLEFT", -4, 4)
    overlay:SetPoint("BOTTOMRIGHT", editBox, "BOTTOMRIGHT", 4, -4)
    overlay:SetFrameStrata(editBox:GetFrameStrata())
    overlay:SetFrameLevel(math.max(0, editBox:GetFrameLevel() + 2))
    if overlay.SetClipsChildren then
        overlay:SetClipsChildren(true)
    end

    RefineUI.CreateBorder(overlay, 0, 0, EDITBOX_BORDER_EDGE_SIZE)
    return overlay
end

local function EnsureRefineEditBoxBackground(editBox)
    if not editBox then
        return nil
    end

    local background = _editBoxBackgrounds[editBox]
    if not background then
        background = editBox:CreateTexture(nil, "BACKGROUND", nil, -8)
        _editBoxBackgrounds[editBox] = background
    end

    background:ClearAllPoints()
    background:SetPoint("TOPLEFT", editBox, "TOPLEFT", EDITBOX_BACKGROUND_INSET, -EDITBOX_BACKGROUND_INSET)
    background:SetPoint("BOTTOMRIGHT", editBox, "BOTTOMRIGHT", -EDITBOX_BACKGROUND_INSET, EDITBOX_BACKGROUND_INSET)
    background:SetColorTexture(0, 0, 0, EDITBOX_BACKGROUND_ALPHA)

    local backgroundMask = _editBoxBackgroundMasks[editBox]
    if not backgroundMask and editBox.CreateMaskTexture and background.AddMaskTexture then
        backgroundMask = editBox:CreateMaskTexture()
        _editBoxBackgroundMasks[editBox] = backgroundMask
        background:AddMaskTexture(backgroundMask)
    end
    if backgroundMask then
        backgroundMask:SetAllPoints(background)
        backgroundMask:SetTexture(EDITBOX_BACKGROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    end

    return background
end

local function EnsureRefineEditBoxBorder(editBox)
    if not editBox then return end
    EnsureRefineEditBoxBackground(editBox)
    local overlay = GetEditBoxBorderOverlay(editBox)
    if not overlay then return end

    overlay:SetFrameStrata(editBox:GetFrameStrata())
    overlay:SetFrameLevel(math.max(0, editBox:GetFrameLevel() + 2))
    overlay:SetAlpha(1)
    overlay:Show()

    local border = overlay.border
    if not border then return end
    border:SetAlpha(1)
    border:Show()
    if border.EnableMouse then
        border:EnableMouse(false)
    end
end

local function UpdateEditBoxMouseState(editBox)
    if not editBox or not editBox.EnableMouse then
        return
    end

    local canClick = editBox.IsShown and editBox:IsShown() and editBox.HasFocus and editBox:HasFocus()
    editBox:EnableMouse(canClick == true)
end

local function UpdateEditBoxAlpha(editBox)
    if not editBox then return end
    local alpha = EDITBOX_IDLE_ALPHA
    if editBox.HasFocus and editBox:HasFocus() then
        alpha = EDITBOX_ACTIVE_ALPHA
    end
    editBox:SetAlpha(alpha)
    local overlay = _editBoxBorderOverlays[editBox]
    if overlay then
        overlay:SetAlpha(alpha)
    end
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
    local regions = { editBox:GetRegions() }
    for i = 1, #regions do
        local region = regions[i]
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
    if not editBox then return end
    RemoveBlizzardEditBoxArt(editBox, chatName, id)
    ForceHideAllChatEditBoxBorderRegions()
end

local function SuppressChatWidget(widget)
    if not widget then
        return
    end

    if widget.SetAlpha then
        widget:SetAlpha(0)
    end

    if widget.Hide then
        widget:Hide()
    end

    if widget.EnableMouse then
        widget:EnableMouse(false)
    end

    if widget.Disable then
        pcall(widget.Disable, widget)
    end

    if widget.SetShown then
        hooksecurefunc(widget, "SetShown", function(self, shown)
            if shown then
                self:SetAlpha(0)
                self:Hide()
            end
        end)
    end

    if widget.Show then
        hooksecurefunc(widget, "Show", function(self)
            self:SetAlpha(0)
            self:Hide()
        end)
    end
end

local function GetEditBoxColorInfo(editBox)
    if not editBox then
        return nil
    end

    local chatType
    if editBox.GetChatType then
        chatType = editBox:GetChatType()
    else
        chatType = editBox:GetAttribute("chatType")
    end

    if type(chatType) ~= "string" or chatType == "" then
        return nil
    end

    if chatType == "CHANNEL" and editBox.GetChannelTarget then
        local localID = editBox:GetChannelTarget()
        if type(localID) == "number" and localID > 0 then
            local channelInfo = ChatTypeInfo["CHANNEL" .. localID]
            if channelInfo then
                return channelInfo
            end
        end
    end

    return ChatTypeInfo[chatType]
end

-- Update editbox border color and hide header text
local function UpdateEditBoxStyle(editBox)
	if not editBox then return end
	
	-- Update border color based on channel
	local overlay = _editBoxBorderOverlays[editBox]
	if overlay and overlay.border then
        local info = GetEditBoxColorInfo(editBox)
        if info then
            overlay.border:SetBackdropBorderColor(info.r, info.g, info.b, 1)
            return
        end

        local c = RefineUI.Config and RefineUI.Config.General and RefineUI.Config.General.BorderColor
        if c then
            overlay.border:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1)
        end
	end
end

local function RefreshEditBoxVisualState(editBox)
    if not editBox then
        return
    end

    EnsureRefineEditBoxBorder(editBox)
    UpdateEditBoxStyle(editBox)
    UpdateEditBoxAlpha(editBox)
    UpdateEditBoxMouseState(editBox)
end

local function HookSingleEditBoxBorderColor(editBox)
    if not editBox or _editBoxBorderColorHooks[editBox] then
        return
    end

    _editBoxBorderColorHooks[editBox] = true
    RefineUI:HookScriptOnce(BuildChatFramesHookKey(editBox, "OnShow", "RefineBorder"), editBox, "OnShow", RefreshEditBoxVisualState)
    RefineUI:HookScriptOnce(BuildChatFramesHookKey(editBox, "OnHide", "RefineBorder"), editBox, "OnHide", RefreshEditBoxVisualState)
    RefineUI:HookScriptOnce(BuildChatFramesHookKey(editBox, "OnTextChanged", "RefineBorder"), editBox, "OnTextChanged", RefreshEditBoxVisualState)
    RefineUI:HookScriptOnce(BuildChatFramesHookKey(editBox, "OnEditFocusGained", "RefineBorder"), editBox, "OnEditFocusGained", RefreshEditBoxVisualState)
    RefineUI:HookScriptOnce(BuildChatFramesHookKey(editBox, "OnEditFocusLost", "RefineBorder"), editBox, "OnEditFocusLost", RefreshEditBoxVisualState)
end

local function HookEditBoxBorderColor()
    if CHAT_FRAMES then
        for _, frameName in ipairs(CHAT_FRAMES) do
            local frame = _G[frameName]
            if frame and frame.editBox then
                HookSingleEditBoxBorderColor(frame.editBox)
            end
        end
        return
    end

    for index = 1, NUM_CHAT_WINDOWS do
        local editBox = _G[format("ChatFrame%sEditBox", index)]
        if editBox then
            HookSingleEditBoxBorderColor(editBox)
        end
    end
end

local function RefreshAllChatEditBoxVisualState()
    if CHAT_FRAMES then
        for _, frameName in ipairs(CHAT_FRAMES) do
            local chatFrame = _G[frameName]
            if chatFrame and chatFrame.editBox then
                RefreshEditBoxVisualState(chatFrame.editBox)
            end
        end
        return
    end

    for index = 1, NUM_CHAT_WINDOWS do
        local editBox = _G[format("ChatFrame%sEditBox", index)]
        if editBox then
            RefreshEditBoxVisualState(editBox)
        end
    end
end

local function InstallEditBoxHeaderRefreshHook()
    if _editBoxHeaderHookInstalled then
        return
    end

    _editBoxHeaderHookInstalled = true
    RefineUI:HookOnce("ChatFrames:ChatEdit_UpdateHeader:RefineBorder", "ChatEdit_UpdateHeader", function(editBox)
        local chatFrame = editBox and editBox.chatFrame
        if chatFrame and not IsPlayerInCombat() then
            ApplyEditBoxLayout(editBox, chatFrame)
        end
        if chatFrame and chatFrame.GetName and chatFrame.GetID and HIDE_BLIZZ_EDITBOX_BORDER_TEXTURE then
            EnsureBlizzardEditBoxArtHidden(editBox, chatFrame:GetName(), chatFrame:GetID())
        end
        RefreshEditBoxVisualState(editBox)
        if Chat.UpdateTabAlpha then
            Chat:UpdateTabAlpha()
        end
    end)

    if ChatFrameUtil then
        RefineUI:HookOnce("ChatFrames:ChatFrameUtil:ActivateChat", ChatFrameUtil, "ActivateChat", function(editBox)
            local chatFrame = editBox and editBox.chatFrame
            if chatFrame and not IsPlayerInCombat() then
                ApplyEditBoxLayout(editBox, chatFrame)
            end
            RefreshEditBoxVisualState(editBox)
            if Chat.UpdateTabAlpha then
                Chat:UpdateTabAlpha()
            end
        end)
        RefineUI:HookOnce("ChatFrames:ChatFrameUtil:DeactivateChat", ChatFrameUtil, "DeactivateChat", function(editBox)
            RefreshEditBoxVisualState(editBox)
            if editBox and editBox.Hide then
                editBox:Hide()
            end
            if Chat.UpdateTabAlpha then
                Chat:UpdateTabAlpha()
            end
        end)
    end

    local editBoxMixin = ChatFrameEditBoxMixin or ChatFrameEditBoxBaseMixin
    if editBoxMixin then
        RefineUI:HookOnce("ChatFrames:ChatFrameEditBoxMixin:SetChatType", editBoxMixin, "SetChatType", function(editBox)
            if editBox and editBox.IsShown and editBox:IsShown() then
                RefreshEditBoxVisualState(editBox)
            end
        end)
        RefineUI:HookOnce("ChatFrames:ChatFrameEditBoxMixin:SetChannelTarget", editBoxMixin, "SetChannelTarget", function(editBox)
            if editBox and editBox.IsShown and editBox:IsShown() then
                RefreshEditBoxVisualState(editBox)
            end
        end)
        RefineUI:HookOnce("ChatFrames:ChatFrameEditBoxMixin:Deactivate", editBoxMixin, "Deactivate", function(editBox)
            if editBox and editBox.Hide and (not editBox.HasFocus or not editBox:HasFocus()) then
                editBox:Hide()
            end
            if editBox then
                RefreshEditBoxVisualState(editBox)
            end
            if Chat.UpdateTabAlpha then
                Chat:UpdateTabAlpha()
            end
        end)
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

    -- Keep Blizzard's native chat edit box ownership. Encounter-time whisper and
    -- temporary chat windows run through protected header/layout paths.

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
                if element.SetTexture then
                    element:SetTexture(nil)
                end
                SuppressChatWidget(element)
            end
        end
	end

	if frame.ScrollBar then
        if visualOnly then
            if frame.ScrollBar.SetAlpha then frame.ScrollBar:SetAlpha(0) end
        else
            SuppressChatWidget(frame.ScrollBar)
        end
    end
	if frame.ScrollToBottomButton then
        if visualOnly then
            if frame.ScrollToBottomButton.SetAlpha then frame.ScrollToBottomButton:SetAlpha(0) end
        else
            SuppressChatWidget(frame.ScrollToBottomButton)
        end
    end

	if tab and tab.conversationIcon then
        if visualOnly then
            if tab.conversationIcon.SetAlpha then tab.conversationIcon:SetAlpha(0) end
        else
            SuppressChatWidget(tab.conversationIcon)
        end
    end

    if not visualOnly and editBox then
        if not IsPlayerInCombat() then
            ApplyEditBoxLayout(editBox, chatFrame)
        end
        ApplyEditBoxTypography(editBox, fontSize)

        if USE_EDITBOX_BORDER_ONLY then
            if HIDE_BLIZZ_EDITBOX_BORDER_TEXTURE then
                EnsureBlizzardEditBoxArtHidden(editBox, chat, id)
            end
            RefreshEditBoxVisualState(editBox)
            HookEditBoxBorderColor()
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

    RefreshAllChatEditBoxVisualState()
    HookEditBoxBorderColor()

    -- Avoid mutating Blizzard chat metadata tables. Those tables participate in
    -- encounter-time chat handling and secret-safe formatting.

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
		if i == 1 then
			chat:ClearAllPoints()
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

	end
    if CHAT_FRAMES then
        for _, frameName in ipairs(CHAT_FRAMES) do
            local chat = _G[frameName]
            if chat and chat.GetID and chat:GetID() > NUM_CHAT_WINDOWS then
                local _, fontSize = FCF_GetChatWindowInfo(chat:GetID())
                fontSize = math.max(tonumber(fontSize) or 11, 11)
                FCF_SetChatWindowFontSize(nil, chat, fontSize)
                ApplyChatFrameTypography(chat, fontSize)
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
        UpdatePrimaryChatLinkedWidths()
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

    UpdatePrimaryChatLinkedWidths()
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
        RefreshEditBoxVisualState(frame.editBox)
        HookEditBoxBorderColor()
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
    if ChatFrameMenuButton then SuppressChatWidget(ChatFrameMenuButton) end
    if ChatFrameChannelButton then SuppressChatWidget(ChatFrameChannelButton) end
    if ChatFrameToggleVoiceDeafenButton then SuppressChatWidget(ChatFrameToggleVoiceDeafenButton) end
    if ChatFrameToggleVoiceMuteButton then SuppressChatWidget(ChatFrameToggleVoiceMuteButton) end

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

    -- Hook temporary window creation
    RefineUI:HookOnce("ChatFrames:FCF_OpenTemporaryWindow", "FCF_OpenTemporaryWindow", SetupTempChat)
    InstallEditBoxHeaderRefreshHook()

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
    HookPrimaryChatSizeUpdates()
    SetupChatPosAndFontSafe()
    Chat:SetupTabs()
    Chat:SetupCopy()

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
    if Chat.SyncEncounterState then
        Chat:SyncEncounterState()
    end

    if not _didInitialChatSetup then
        RunInitialChatSetup()
        return
    end

    SetupChatPosAndFontSafe()
end

local function HandleEncounterStateChanged(_, isInProgress)
    if Chat.SetEncounterActive then
        Chat:SetEncounterActive(isInProgress == true)
    end
end

function Chat:OnEnable()
    if not self.db or self.db.Enable ~= true then
        return
    end

    if self.SetupIcons then
        self:SetupIcons()
    end
    if self.SetupLootIcons then
        self:SetupLootIcons()
    end
    if self.SetupRoleIcons then
        self:SetupRoleIcons()
    end
    if self.InitializeEditModeSettings then
        self:InitializeEditModeSettings()
    end
    if self.InstallMessagePipeline then
        self:InstallMessagePipeline()
    end
    if self.SyncEncounterState then
        self:SyncEncounterState()
    end

    if not RunInitialChatSetup() then
        RunCombatSafeChatVisualSetup()
        RefineUI:RegisterEventCallback("PLAYER_REGEN_ENABLED", function()
            RunInitialChatSetup()
        end, CHAT_ENABLE_REGEN_SETUP_KEY)
    end
    
    -- Re-apply position/font rules when entering world, but only after initial chat setup has safely run.
    RefineUI:RegisterEventCallback("PLAYER_ENTERING_WORLD", HandlePlayerEnteringWorldChatSetup, CHAT_WORLD_SETUP_KEY)
    RefineUI:RegisterEventCallback("ENCOUNTER_STATE_CHANGED", HandleEncounterStateChanged, CHAT_ENCOUNTER_STATE_KEY)
end
