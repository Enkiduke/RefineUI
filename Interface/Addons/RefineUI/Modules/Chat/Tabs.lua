----------------------------------------------------------------------------------------
--	Based on Fane(by Haste) (Direct Port)
----------------------------------------------------------------------------------------

local _, RefineUI = ...

local Chat = RefineUI:GetModule("Chat")
local CHAT_FRAMES = CHAT_FRAMES
local TAB_GOLD_R, TAB_GOLD_G, TAB_GOLD_B = 1, 0.82, 0
local TAB_FONT_OBJECT_HOOKED = setmetatable({}, { __mode = "k" })
local tabRefreshQueued = false

local function IsTabSelected(tab, selected)
    if selected ~= nil then
        return selected and true or false
    end
    if not tab then return false end
    if tab.chatFrame and SELECTED_CHAT_FRAME then
        return tab.chatFrame == SELECTED_CHAT_FRAME
    end
    local id = tab.GetID and tab:GetID()
    return (SELECTED_CHAT_FRAME and SELECTED_CHAT_FRAME.GetID and id and id == SELECTED_CHAT_FRAME:GetID()) and true or false
end

local function ForEachChatTab(callback)
    if CHAT_FRAMES then
        for _, frameName in ipairs(CHAT_FRAMES) do
            local tab = _G[frameName .. "Tab"]
            if tab then callback(tab) end
        end
        return
    end
    for i = 1, NUM_CHAT_WINDOWS do
        local tab = _G["ChatFrame"..i.."Tab"]
        if tab then callback(tab) end
    end
end

local function ApplyTabFontStyle(tab)
    if not tab then return nil end
    local fstring = (tab.GetFontString and tab:GetFontString()) or tab.Text
    if not fstring or not fstring.SetFont then return nil end

    RefineUI.Font(fstring, 16, RefineUI.Media.Fonts.Attachment, "THINOUTLINE")

    if not TAB_FONT_OBJECT_HOOKED[fstring] and fstring.SetFontObject then
        TAB_FONT_OBJECT_HOOKED[fstring] = true
        hooksecurefunc(fstring, "SetFontObject", function(self)
            RefineUI.Font(self, 16, RefineUI.Media.Fonts.Attachment, "THINOUTLINE")
        end)
    end

    return fstring
end

function Chat:UpdateTabAlpha()
    -- Intentionally avoid writing Blizzard CHAT_FRAME_TAB_* globals.
    -- Those are consumed by protected dock update code and can taint FCFDock paths.
end

local updateFS = function(self, _, ...)
	local fstring = ApplyTabFontStyle(self)
    if not fstring then return end

	if (...) then
		local r, g, b = ...
		local cr, cg, cb = fstring:GetTextColor()
		if cr ~= r or cg ~= g or cb ~= b then
			fstring:SetTextColor(r, g, b)
		end
	end
end

local OnEnter = function(self)
	local id = self:GetID()
    local flash = _G["ChatFrame"..id.."TabFlash"]
    local emphasis = flash and flash:IsShown()
	updateFS(self, emphasis, TAB_GOLD_R, TAB_GOLD_G, TAB_GOLD_B)
	
	if Chat.db.TabsMouseOver then
		RefineUI:FadeIn(self)
	end
end

local OnLeave = function(self)
	local r, g, b
	local id = self:GetID()
    local flash = _G["ChatFrame"..id.."TabFlash"]
    local emphasis = flash and flash:IsShown()

	if IsTabSelected(self, nil) then
		r, g, b = TAB_GOLD_R, TAB_GOLD_G, TAB_GOLD_B
	elseif emphasis then
		r, g, b = 1, 0, 0
	else
		r, g, b = 1, 1, 1
	end

	updateFS(self, emphasis, r, g, b)
	
	if Chat.db.TabsMouseOver then
		RefineUI:FadeOut(self)
	end
end

local function faneifyTab(frame, selected)
    if not frame then return end
	local i = frame:GetID()

	if frame:GetParent() == _G.ChatConfigFrameChatTabManager then
		if selected then
			frame.Text:SetTextColor(1, 1, 1)
		end

		frame:SetAlpha(1)
		return
	end

    local frameName = frame:GetName() or tostring(frame)
    RefineUI:HookScriptOnce("ChatTabs:" .. frameName .. ":OnEnter", frame, "OnEnter", OnEnter)
    RefineUI:HookScriptOnce("ChatTabs:" .. frameName .. ":OnLeave", frame, "OnLeave", OnLeave)
    RefineUI:HookScriptOnce("ChatTabs:" .. frameName .. ":OnClick", frame, "OnClick", function()
        C_Timer.After(0, function()
            ForEachChatTab(function(tab)
                faneifyTab(tab, IsTabSelected(tab))
            end)
        end)
    end)

    if Chat.db.TabsMouseOver ~= true then
        frame:SetAlpha(1)
        if i == 2 and CombatLogQuickButtonFrame_Custom then
            CombatLogQuickButtonFrame_Custom:SetAlpha(0.4)
        end
    else
        frame:SetAlpha(0)
    end

	if IsTabSelected(frame, selected) then
		updateFS(frame, nil, TAB_GOLD_R, TAB_GOLD_G, TAB_GOLD_B)
		if Chat.db.TabsMouseOver and not frame:IsMouseOver() then
			frame:SetAlpha(0)
		end
	else
		updateFS(frame, nil, 1, 1, 1)
		if Chat.db.TabsMouseOver and not frame:IsMouseOver() then
			frame:SetAlpha(0)
		end
	end
end

local function RefreshTabs()
    ForEachChatTab(function(tab)
        faneifyTab(tab, IsTabSelected(tab))
    end)
end

local function QueueRefreshTabs()
    if tabRefreshQueued then
        return
    end
    tabRefreshQueued = true
    C_Timer.After(0, function()
        tabRefreshQueued = false
        RefreshTabs()
    end)
end

function Chat:SetupTabsVisualsOnly()
    ForEachChatTab(function(tab)
        if not tab then return end

        local selected = IsTabSelected(tab)
        local id = tab.GetID and tab:GetID()
        local flash = id and _G["ChatFrame"..id.."TabFlash"]
        local emphasis = flash and flash:IsShown()

        ApplyTabFontStyle(tab)

        if selected then
            updateFS(tab, nil, TAB_GOLD_R, TAB_GOLD_G, TAB_GOLD_B)
        elseif emphasis then
            updateFS(tab, true, 1, 0, 0)
        else
            updateFS(tab, nil, 1, 1, 1)
        end

        if tab:GetParent() == _G.ChatConfigFrameChatTabManager then
            tab:SetAlpha(1)
            return
        end

        -- Keep tabs visible during the combat-safe phase; hover fade hooks are installed
        -- later in the full setup pass.
        tab:SetAlpha(1)
    end)
end

function Chat:SetupTabs()
    self:UpdateTabAlpha()
    
    RefineUI:HookOnce("ChatTabs:FCF_StartAlertFlash", "FCF_StartAlertFlash", function(frame)
        local tab = _G["ChatFrame"..frame:GetID().."Tab"]
        C_Timer.After(0, function()
            updateFS(tab, true, 1, 0, 0)
        end)
    end)

    RefineUI:HookOnce("ChatTabs:FCFTab_UpdateColors", "FCFTab_UpdateColors", function()
        QueueRefreshTabs()
    end)
    RefineUI:HookOnce("ChatTabs:FCFTab_UpdateAlpha", "FCFTab_UpdateAlpha", function(tab)
        QueueRefreshTabs()
    end)
    RefineUI:HookOnce("ChatTabs:FCFDock_UpdateTabs", "FCFDock_UpdateTabs", function()
        QueueRefreshTabs()
    end)
    RefineUI:HookOnce("ChatTabs:FCFDock_SelectWindow", "FCFDock_SelectWindow", function()
        QueueRefreshTabs()
    end)

    RefreshTabs()
    
    RefineUI:HookOnce("ChatTabs:FCF_OpenTemporaryWindow", "FCF_OpenTemporaryWindow", function()
        local cf = FCF_GetCurrentChatFrame()
        if not cf then return end
        local tab = _G[cf:GetName().."Tab"]
        if tab then
            faneifyTab(tab)
            QueueRefreshTabs()
        end
    end)
    
    local Fane = CreateFrame("Frame")
    Fane:RegisterEvent("ADDON_LOADED")
    Fane:SetScript("OnEvent", function(self, event, addon)
        if addon == "Blizzard_CombatLog" then
            self:UnregisterEvent(event)
            if CombatLogQuickButtonFrame_Custom then
                CombatLogQuickButtonFrame_Custom:SetAlpha(0.4)
            end
        end
    end)
end
