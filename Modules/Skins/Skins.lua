----------------------------------------------------------------------------------------
-- Skins module bootstrap for RefineUI
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Skins = RefineUI:RegisterModule("Skins")

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
local function GetCharacterPanelConfig()
    Config.Skins = Config.Skins or {}
    local skinsConfig = Config.Skins
    if skinsConfig.Enable == nil then
        skinsConfig.Enable = true
    end

    skinsConfig.CharacterPanel = skinsConfig.CharacterPanel or {}
    local characterConfig = skinsConfig.CharacterPanel
    if characterConfig.Enable == nil then
        characterConfig.Enable = true
    end
    if characterConfig.ShowCurrentMaxItemLevel == nil then
        characterConfig.ShowCurrentMaxItemLevel = true
    end
    if characterConfig.ShowSlotIndicators == nil then
        characterConfig.ShowSlotIndicators = true
    end
    if characterConfig.ShowIndicatorText == nil then
        characterConfig.ShowIndicatorText = false
    end
    if characterConfig.ShowHealthTotal == nil then
        characterConfig.ShowHealthTotal = true
    end
    if characterConfig.ShowManaTotal == nil then
        characterConfig.ShowManaTotal = true
    end

    return characterConfig
end

function Skins:GetCharacterPanelConfig()
    return GetCharacterPanelConfig()
end

function Skins:IsCharacterPanelEnabled()
    local characterConfig = GetCharacterPanelConfig()
    return Config.Skins.Enable ~= false and characterConfig.Enable ~= false
end

----------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------
function Skins:OnEnable()
    GetCharacterPanelConfig()
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
    if self.SetupSCT then
        self:SetupSCT()
    end
    if self.SetupStatusBars then
        self:SetupStatusBars()
    end
end
