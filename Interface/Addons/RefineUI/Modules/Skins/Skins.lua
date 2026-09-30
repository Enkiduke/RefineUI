----------------------------------------------------------------------------------------
-- Skins module bootstrap for RefineUI
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Skins = RefineUI:RegisterModule("Skins", "Skins")

----------------------------------------------------------------------------------------
-- Shared Aliases
----------------------------------------------------------------------------------------
local Config = RefineUI.Config

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
    self:SetupAdventureGuideSkin()
    if self:IsCharacterPanelEnabled() then
        self:SetupCharacterPanel()
    end
    self:InitDamageMeterSkinner()
    self:SetupGossipFrameSkin()
    self:SetupItemTextFrameSkin()
    self:SetupLootRollSkin()
    self:SetupLSToastsSkin()
    if Config.Skins.QueueTimer.Enable ~= false then
        self:SetupQueueTimerSkin()
    end
    self:SetupSCT()
    self:SetupStatusBars()
    self:SetupZoneTextSkin()
end
