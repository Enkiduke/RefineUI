----------------------------------------------------------------------------------------
-- Skins module bootstrap for RefineUI
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Skins = RefineUI:RegisterModule("Skins", "Skins")

----------------------------------------------------------------------------------------
-- Shared Aliases
----------------------------------------------------------------------------------------
local Config = RefineUI.Config
local Media = RefineUI.Media
local Colors = RefineUI.Colors
local Locale = RefineUI.Locale

----------------------------------------------------------------------------------------
-- Config
----------------------------------------------------------------------------------------
-- Defaults come from Config/Config.lua and are merged into the profile on load.
function Skins:GetCharacterPanelConfig()
    return Config.Skins.CharacterPanel
end

function Skins:IsCharacterPanelEnabled()
    return Config.Skins.Enable ~= false and Config.Skins.CharacterPanel.Enable ~= false
end

----------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------
function Skins:OnEnable()
    if self.SetupAdventureGuideSkin then
        self:SetupAdventureGuideSkin()
    end
    if self:IsCharacterPanelEnabled() and self.SetupCharacterPanel then
        self:SetupCharacterPanel()
    end
    if self.InitDamageMeterSkinner then
        self:InitDamageMeterSkinner()
    end
    if self.SetupGossipFrameSkin then
        self:SetupGossipFrameSkin()
    end
    if self.SetupItemTextFrameSkin then
        self:SetupItemTextFrameSkin()
    end
    if self.SetupLootRollSkin then
        self:SetupLootRollSkin()
    end
    if self.SetupSCT then
        self:SetupSCT()
    end
    if self.SetupStatusBars then
        self:SetupStatusBars()
    end
    if self.SetupZoneTextSkin then
        self:SetupZoneTextSkin()
    end
end
