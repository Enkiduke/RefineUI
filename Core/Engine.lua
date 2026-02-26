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
RefineUI.Core = {}
RefineUI.Config = {}
RefineUI.Locale = {}
RefineUI.Media = {}
RefineUI.Modules = {}
RefineUI.Libs = {}

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
    -- Sync constants immediately
    if self.UpdatePixelConstants then self:UpdatePixelConstants() end
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
        -- Final Pixel Perfect enforcement (Sets CVars)
        if RefineUI.SetUIScale then RefineUI:SetUIScale() end

        if RefineUI.RunStartupCallbacks then
            RefineUI:RunStartupCallbacks()
        elseif RefineUI.OnEnable then
            -- Backward compatibility fallback
            RefineUI:OnEnable()
        end
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)
