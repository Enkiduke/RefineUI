local AddOnName, RefineUI = ...

-- Call Modules
local ErrorFilter = RefineUI:RegisterModule("ErrorFilter")

-- Lib Globals
local _G = _G
local unpack = unpack
local InCombatLockdown = InCombatLockdown

-- WoW Global
local UIErrorsFrame = _G.UIErrorsFrame

function ErrorFilter:SetCombatSuppression(enabled)
	if not UIErrorsFrame or not UIErrorsFrame.SetMessagesSuppressed then
		return
	end

	UIErrorsFrame:SetMessagesSuppressed(enabled and true or false)
	if enabled then
		UIErrorsFrame:Clear()
	end
end

function ErrorFilter:UpdateErrors()
	UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")
	UIErrorsFrame:ClearAllPoints()
    
    -- Ensure API is available (MessageFrame doesn't get it by default)
    -- RefineUI.AddAPI(UIErrorsFrame) -- REMOVED

    -- Strict API: Use :Point()
	RefineUI.Point(UIErrorsFrame, "TOP", _G.UIParent, 0, -222)
    
    -- Strict API: Use :Font() helper on FontString? 
    -- UIErrorsFrame is a Frame that holds messages. We can't strictly use :Font() on it directly 
    -- unless the messages inherit it, but SetFontTemplate is the RefineUI equivalent for FontStrings.
    -- However, the RefineUI API injects :Font() to FontStrings.
    -- UIErrorsFrame has :SetFont() normally? No, it's a MessageFrame. 
    -- It has :SetFont(font, height, flags).
    -- We'll use the proper Media reference.
	UIErrorsFrame:SetFont(RefineUI.Media.Fonts.Default, RefineUI:Scale(16), "OUTLINE")
    
	UIErrorsFrame:SetTimeVisible(1)
	UIErrorsFrame:SetFadeDuration(0.8)
end

function ErrorFilter:OnEnable()
	if (not RefineUI.Config.ErrorsFrame or not RefineUI.Config.ErrorsFrame.Enable) then
		return
	end

	self:UpdateErrors()
	self:SetCombatSuppression(InCombatLockdown())
    
    -- Register Events via EventBus
	RefineUI:RegisterEventCallback("UI_ERROR_MESSAGE", function(_, _, message)
		if InCombatLockdown() then
			return
		end
		UIErrorsFrame:AddMessage(message, unpack(RefineUI.Config.ErrorsFrame.TextColor))
	end, "ErrorFilter:Message")

	RefineUI:RegisterEventCallback("PLAYER_REGEN_DISABLED", function()
		self:SetCombatSuppression(true)
	end, "ErrorFilter:CombatStart")

	RefineUI:RegisterEventCallback("PLAYER_REGEN_ENABLED", function()
		self:SetCombatSuppression(false)
	end, "ErrorFilter:CombatEnd")
end
