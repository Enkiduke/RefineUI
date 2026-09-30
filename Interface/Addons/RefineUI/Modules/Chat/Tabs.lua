----------------------------------------------------------------------------------------
-- Chat tab styling for RefineUI
----------------------------------------------------------------------------------------

local _, RefineUI = ...

local Chat = RefineUI:GetModule("Chat")
if not Chat then
    return
end

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local _G = _G
local ipairs = ipairs
local setmetatable = setmetatable

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local CHAT_FRAMES = CHAT_FRAMES
local FCF_DockUpdate = FCF_DockUpdate
local InCombatLockdown = InCombatLockdown
local NUM_CHAT_WINDOWS = NUM_CHAT_WINDOWS
local UnitAffectingCombat = UnitAffectingCombat
local hooksecurefunc = hooksecurefunc

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local TAB_GOLD_R = 1
local TAB_GOLD_G = 0.82
local TAB_GOLD_B = 0
local TAB_REFRESH_TIMER_KEY = "Chat:Tabs:Refresh"
local TAB_DOCK_REFRESH_TIMER_KEY = "Chat:Tabs:DockRefresh"
local TAB_DOCK_REFRESH_REGEN_KEY = "Chat:Tabs:DockRefresh:PLAYER_REGEN_ENABLED"

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
local tabFontHooked = setmetatable({}, { __mode = "k" })
local tabColorHookInstalled = false
local tabRefreshQueued = false
local tabDockRefreshQueued = false
-- Set when Blizzard restyles a tab. FCFDock_UpdateTabs recolors every docked tab
-- when it does real work, but returns early (and is often called every frame from
-- the dock's OnUpdate) when nothing changed.
local tabsRestyled = false

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local function ForEachChatTab(callback)
    if CHAT_FRAMES then
        for _, frameName in ipairs(CHAT_FRAMES) do
            local tab = _G[frameName .. "Tab"]
            if tab then
                callback(tab)
            end
        end
        return
    end

    for index = 1, NUM_CHAT_WINDOWS do
        local tab = _G["ChatFrame" .. index .. "Tab"]
        if tab then
            callback(tab)
        end
    end
end

local function IsPlayerInCombat()
    return (InCombatLockdown and InCombatLockdown())
        or (UnitAffectingCombat and UnitAffectingCombat("player"))
end

local function GetTabChatFrame(tab)
    if not tab or not tab.GetID then
        return nil
    end

    return _G["ChatFrame" .. tab:GetID()]
end

local function ApplyTabVisibility(tab, instant)
    if not tab or tab:GetParent() == _G.ChatConfigFrameChatTabManager then
        if tab and instant then
            tab:SetAlpha(1)
        end
        return
    end

    local chatFrame = GetTabChatFrame(tab)
    if chatFrame and _G.FCFTab_UpdateAlpha then
        _G.FCFTab_UpdateAlpha(chatFrame)
    end

    if tab.EnableMouse then
        tab:EnableMouse(true)
    end
end

local function IsTabSelected(tab, selected)
    if selected ~= nil then
        return selected == true
    end

    local chatFrame = GetTabChatFrame(tab)
    return chatFrame ~= nil and chatFrame == _G.SELECTED_CHAT_FRAME
end

local function ApplyTabFontStyle(tab)
    if not tab then
        return nil
    end

    local fontString = (tab.GetFontString and tab:GetFontString()) or tab.Text
    if not fontString or not fontString.SetFont then
        return nil
    end

    RefineUI.Font(fontString, 16, RefineUI.Media.Fonts.Attachment, "THINOUTLINE")

    if not tabFontHooked[fontString] and fontString.SetFontObject then
        tabFontHooked[fontString] = true
        hooksecurefunc(fontString, "SetFontObject", function(self)
            RefineUI.Font(self, 16, RefineUI.Media.Fonts.Attachment, "THINOUTLINE")
        end)
    end

    return fontString
end

local function UpdateTabTextColor(fontString, selected)
    if selected then
        fontString:SetTextColor(TAB_GOLD_R, TAB_GOLD_G, TAB_GOLD_B)
    else
        fontString:SetTextColor(1, 1, 1)
    end
end

local function UpdateTabStyle(tab, selected)
    if not tab then
        return
    end

    local fontString = ApplyTabFontStyle(tab)
    if not fontString then
        return
    end

    if tab:GetParent() == _G.ChatConfigFrameChatTabManager then
        ApplyTabVisibility(tab, true)
        if selected then
            fontString:SetTextColor(1, 1, 1)
        end
        return
    end

    UpdateTabTextColor(fontString, selected)
    ApplyTabVisibility(tab)
end

local function RefreshTabs(instant)
    ForEachChatTab(function(tab)
        UpdateTabStyle(tab, IsTabSelected(tab))
        ApplyTabVisibility(tab, instant)
    end)
end

local function QueueRefreshTabs()
    if tabRefreshQueued then
        return
    end

    tabRefreshQueued = true
    RefineUI:After(TAB_REFRESH_TIMER_KEY, 0, function()
        tabRefreshQueued = false
        RefreshTabs()
    end)
end

local function RefreshDock()
    tabDockRefreshQueued = false
    FCF_DockUpdate()
end

local function RefreshDockWhenSafe()
    RefineUI:RunAfterCombat(TAB_DOCK_REFRESH_REGEN_KEY, RefreshDock)
end

local function QueueDockRefresh()
    if tabDockRefreshQueued or not FCF_DockUpdate then
        return
    end

    tabDockRefreshQueued = true
    RefineUI:After(TAB_DOCK_REFRESH_TIMER_KEY, 0, RefreshDockWhenSafe)
end

local function InstallTabColorHook()
    if tabColorHookInstalled then
        return
    end

    tabColorHookInstalled = true
    RefineUI:HookOnce("Chat:Tabs:FCFTab_UpdateColors", "FCFTab_UpdateColors", function(tab, selected)
        tabsRestyled = true
        UpdateTabStyle(tab, selected)
    end)
    RefineUI:HookOnce("Chat:Tabs:FCF_StartAlertFlash", "FCF_StartAlertFlash", function()
        QueueRefreshTabs()
    end)
    RefineUI:HookOnce("Chat:Tabs:FCF_StopAlertFlash", "FCF_StopAlertFlash", function()
        QueueRefreshTabs()
    end)
    RefineUI:HookOnce("Chat:Tabs:FCFDock_UpdateTabs", "FCFDock_UpdateTabs", function()
        if tabsRestyled then
            tabsRestyled = false
            QueueRefreshTabs()
        end
    end)
    RefineUI:HookOnce("Chat:Tabs:FCFDock_SelectWindow", "FCFDock_SelectWindow", function()
        QueueRefreshTabs()
    end)
    RefineUI:HookOnce("Chat:Tabs:FCF_OpenTemporaryWindow", "FCF_OpenTemporaryWindow", function()
        QueueRefreshTabs()
        QueueDockRefresh()
    end)
end

----------------------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------------------
function Chat:UpdateTabAlpha(instant)
    -- Intentionally avoid writing Blizzard CHAT_FRAME_TAB_* globals.
    ForEachChatTab(function(tab)
        ApplyTabVisibility(tab, instant)
    end)
end

function Chat:SetupTabsVisualsOnly()
    InstallTabColorHook()

    ForEachChatTab(function(tab)
        ApplyTabFontStyle(tab)
        UpdateTabStyle(tab, IsTabSelected(tab))
    end)
    self:UpdateTabAlpha(true)
    QueueDockRefresh()
end

function Chat:SetupTabs()
    self:UpdateTabAlpha()
    self:SetupTabsVisualsOnly()
    QueueRefreshTabs()
end
