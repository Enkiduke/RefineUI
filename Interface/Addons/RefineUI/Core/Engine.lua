----------------------------------------------------------------------------------------
-- RefineUI Engine
-- Description: Core engine initialization and namespace setup.
----------------------------------------------------------------------------------------

local AddOnName, RefineUI = ...
local _G = _G
local C_AddOns = C_AddOns
local UnitName = UnitName
local GetRealmName = GetRealmName

----------------------------------------------------------------------------------------
-- Global Access
----------------------------------------------------------------------------------------
_G[AddOnName] = RefineUI

-- Namespace Structure
RefineUI.Config = {}
RefineUI.Locale = {}
RefineUI.Media = {}

----------------------------------------------------------------------------------------
-- Metadata
----------------------------------------------------------------------------------------
RefineUI.Title = C_AddOns.GetAddOnMetadata(AddOnName, "Title")
RefineUI.Version = C_AddOns.GetAddOnMetadata(AddOnName, "Version")
RefineUI.MyName = UnitName("player")
RefineUI.MyRealm = GetRealmName()
RefineUI.MyClass = select(2, UnitClass("player"))

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------
function RefineUI:OnInitialize()
    if self.InitializeDatabase then
        self:InitializeDatabase()
    end

    -- Sync constants immediately
    if self.UpdatePixelConstants then self:UpdatePixelConstants() end

    -- Style.lua cached theme colors from code defaults at load; re-read the saved profile.
    if self.RefreshTheme then self.RefreshTheme() end
end

----------------------------------------------------------------------------------------
-- Event Loop
----------------------------------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")

loader:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addon = ...
        if addon == AddOnName then
            if RefineUI.OnInitialize then RefineUI:OnInitialize() end
            self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        -- Pixel-perfect layout depends on the effective UI scale being established
        -- before the rest of the startup pipeline builds or restyles frames.
        if RefineUI.RestoreUIScale then
            RefineUI:RestoreUIScale()
        end

        RefineUI:RunStartupCallbacks()

        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)
