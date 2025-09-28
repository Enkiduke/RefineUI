local R, C, L = unpack(RefineUI)

-- Spells lists initialization

C.nameplate.debuffsList = {}
C.nameplate.buffsList = {}
C.filger.left_buffs_list = {}
C.filger.right_buffs_list = {}
C.filger.bottom_buffs_list = {}

----------------------------------------------------------------------------------------
--	First Time Launch and On Login file
----------------------------------------------------------------------------------------
local function InstallUI()
	-- Don't need to set CVar multiple time
	SetCVar("screenshotQuality", 8)
	SetCVar("cameraDistanceMaxZoomFactor", 2.6)
	SetCVar("showTutorials", 0)
	SetCVar("gameTip", "0")
	SetCVar("UberTooltips", 1)
	SetCVar("chatMouseScroll", 1)
	SetCVar("removeChatDelay", 1)
	SetCVar("WholeChatWindowClickable", 0)
	SetCVar("WhisperMode", "inline")
	SetCVar("colorblindMode", 0)
	SetCVar("lootUnderMouse", 1)
	SetCVar("autoLootDefault", 0)
	SetCVar("RotateMinimap", 0)
	SetCVar("autoQuestProgress", 1)
	SetCVar("scriptErrors", 1)
	SetCVar("taintLog", 0)
	SetCVar("buffDurations", 1)
	SetCVar("autoOpenLootHistory", 0)
	SetCVar("lossOfControl", 1)
	SetCVar("nameplateShowAll", 1)
	SetCVar("nameplateShowSelf", 0)
	SetCVar("nameplateShowFriendlyNPCs", 1)
	SetCVar("lootUnderMouse", 1)

	-- Persist install flags without wiping existing settings
	RefineUISettings = RefineUISettings or {}
	RefineUISettings.Install = true
	RefineUISettings.Coords = (RefineUISettings.Coords ~= false) and true or false

	-- Mark per-character as installed
	RefineUICharDB = RefineUICharDB or {}
	RefineUICharDB.Installed = true

	ReloadUI()
end

----------------------------------------------------------------------------------------
--	Boss Banner Hider
----------------------------------------------------------------------------------------
if C.general.hideBanner == true then
	BossBanner.PlayBanner = function() end
	BossBanner:UnregisterAllEvents()
end

----------------------------------------------------------------------------------------
--	Easy delete good items
----------------------------------------------------------------------------------------
local deleteDialog = StaticPopupDialogs["DELETE_GOOD_ITEM"]
if deleteDialog.OnShow then
	hooksecurefunc(deleteDialog, "OnShow",
		function(s)
			s.EditBox:SetText(DELETE_ITEM_CONFIRM_STRING)
			s.EditBox:SetAutoFocus(false)
			s.EditBox:ClearFocus()
		end)
end

----------------------------------------------------------------------------------------
--	Popups
----------------------------------------------------------------------------------------
StaticPopupDialogs.INSTALL_UI = {
	text = L_POPUP_INSTALLUI,
	button1 = ACCEPT,
	button2 = CANCEL,
	OnAccept = InstallUI,
	OnCancel = function() RefineUISettings.Install = false end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = false,
	preferredIndex = 5,
}

StaticPopupDialogs.RESET_UI = {
	text = L_POPUP_RESETUI,
	button1 = ACCEPT,
	button2 = CANCEL,
	OnAccept = InstallUI,
	OnCancel = function() RefineUISettings.Install = true end,
	showAlert = true,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = true,
	preferredIndex = 5,
}

SLASH_CONFIGURE1 = "/resetui"
SlashCmdList.CONFIGURE = function() StaticPopup_Show("RESET_UI") end


----------------------------------------------------------------------------------------
--	On logon function
----------------------------------------------------------------------------------------
local OnLogon = CreateFrame("Frame")
OnLogon:RegisterEvent("PLAYER_ENTERING_WORLD")
OnLogon:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")

	-- Create empty SavedVariables if they don't exist
	if RefineUISettings == nil then RefineUISettings = {} end
	if RefineUIPositions == nil then RefineUIPositions = {} end
	if RefineUIItems == nil then RefineUIItems = {} end
	if RefineUIAutoSellDB == nil then RefineUIAutoSellDB = { AlwaysSell = {} } end -- Initialize AutoSell DB
	if RefineUISettings.Coords == nil then RefineUISettings.Coords = true end
	if RefineUICharDB == nil then RefineUICharDB = {} end

	if R.screenWidth < 1024 and GetCVar("gxMonitor") == "0" then
		SetCVar("useUiScale", 0)
		StaticPopup_Show("DISABLE_UI")
	else
		SetCVar("useUiScale", 1)
		if C.general.uiScale > 1.28 then C.general.uiScale = 1.28 end

		-- Set our uiScale
		if tonumber(GetCVar("uiScale")) ~= tonumber(C.general.uiScale) then
			SetCVar("uiScale", C.general.uiScale)
		end

		-- Hack for 4K and WQHD Resolution
		if C.general.uiScale < 0.64 then
			UIParent:SetScale(C.general.uiScale)
		end

		-- Install default if we never ran RefineUI on this character
		local installed = (RefineUICharDB and RefineUICharDB.Installed == true) or (RefineUISettings and RefineUISettings.Install == true)
		if not installed then
			StaticPopup_Show("INSTALL_UI")
		else
			-- Sync flags so future loads are stable per character
			if RefineUISettings and RefineUISettings.Install == true then
				RefineUICharDB.Installed = true
			end
			-- If per-character installed is true, ensure account-wide flag reflects it
			if RefineUICharDB and RefineUICharDB.Installed == true then
				RefineUISettings = RefineUISettings or {}
				RefineUISettings.Install = true
			end
		end
	end

	-- Hide the bag button
	if BagsBar then
		BagsBar:Hide()
	end
end)
