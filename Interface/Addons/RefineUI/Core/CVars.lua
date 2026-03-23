----------------------------------------------------------------------------------------
-- RefineUI CVars
-- Description: Shared CVar helpers plus install-only recommended defaults.
----------------------------------------------------------------------------------------

local _, RefineUI = ...

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local type = type
local tostring = tostring
local pcall = pcall

local C_CVar = C_CVar
local GetCVar = GetCVar
local SetCVar = SetCVar

----------------------------------------------------------------------------------------
-- Install Defaults
----------------------------------------------------------------------------------------
local INSTALL_DEFAULT_CVARS = {
    { name = "buffDurations", value = 1 },
    { name = "damageMeterEnabled", value = 1 },
    { name = "countdownForCooldowns", value = 1 },
    { name = "chatMouseScroll", value = 1 },
    { name = "screenshotQuality", value = 10 },
    { name = "showTutorials", value = 0 },
    { name = "autoQuestWatch", value = 1 },
    { name = "alwaysShowActionBars", value = 1 },
    { name = "statusText", value = 1 },
    { name = "statusTextDisplay", value = "BOTH" },
    { name = "UnitNameOwn", value = 0 },
    { name = "UnitNameNPC", value = 1 },
    { name = "UnitNameFriendlySpecialNPCName", value = 0 },
    { name = "UnitNameHostleNPC", value = 0 },
    { name = "UnitNameInteractiveNPC", value = 0 },
    { name = "UnitNameNonCombatCreatureName", value = 1 },
    { name = "UnitNameFriendlyPlayerName", value = 1 },
    { name = "UnitNameFriendlyMinionName", value = 1 },
    { name = "UnitNameEnemyPlayerName", value = 1 },
    { name = "UnitNameEnemyMinionName", value = 1 },
    { name = "raidFramesDisplayClassColor", value = 1 },
    { name = "nameplateShowEnemies", value = 1 },
    { name = "nameplateShowEnemyMinions", value = 1 },
    { name = "nameplateShowEnemyMinus", value = 1 },
    { name = "nameplateShowFriends", value = 1 },
    { name = "nameplateShowFriendlyPlayers", value = 1 },
    { name = "nameplateShowFriendlyPlayerMinions", value = 1 },
    { name = "nameplateShowFriendlyNpcs", value = 1 },
    { name = "nameplateStackingTypes", value = 1 },
    { name = "nameplateUseClassColorForFriendlyPlayerUnitNames", value = 1 },
    { name = "nameplateMinScale", value = 1 },
    { name = "nameplateMaxScale", value = 1 },
    { name = "nameplateLargerScale", value = 1 },
    { name = "nameplateSelectedScale", value = 1 },
    { name = "nameplateMinAlpha", value = 0.5 },
    { name = "nameplateMaxAlpha", value = 1 },
    { name = "nameplateMaxDistance", value = 60 },
    { name = "nameplateMinAlphaDistance", value = 0 },
    { name = "nameplateMaxAlphaDistance", value = 40 },
    { name = "nameplateOccludedAlphaMult", value = 0.1 },
    { name = "nameplateSelectedAlpha", value = 1 },
    { name = "WorldTextScale_v2", value = 0.1 },
}

local DEFAULT_TIMESTAMP_FORMAT = "|cff808080[%H:%M]|r "

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
function RefineUI:SetCVarValue(name, value)
    if type(name) ~= "string" or name == "" then
        return false
    end

    if C_CVar and type(C_CVar.SetCVar) == "function" then
        local ok = pcall(C_CVar.SetCVar, name, value)
        if ok then
            return true
        end
    end

    if type(SetCVar) == "function" then
        local ok = pcall(SetCVar, name, value)
        if ok then
            return true
        end
    end

    return false
end

function RefineUI:SetCVarIfChanged(name, value)
    local desired = tostring(value)
    local current = type(GetCVar) == "function" and GetCVar(name) or nil
    if current == desired then
        return true
    end

    return self:SetCVarValue(name, desired)
end

local function GetConfiguredTimestampValue()
    local chatConfig = RefineUI.Config and RefineUI.Config.Chat or nil
    if type(chatConfig) ~= "table" then
        return DEFAULT_TIMESTAMP_FORMAT
    end

    if chatConfig.TimeStamps == false then
        return "none"
    end

    local formatValue = chatConfig.TimestampFormat
    if type(formatValue) ~= "string" or formatValue == "" then
        formatValue = DEFAULT_TIMESTAMP_FORMAT
    end

    return formatValue
end

----------------------------------------------------------------------------------------
-- Install API
----------------------------------------------------------------------------------------
function RefineUI:GetInstallDefaultCVars()
    return INSTALL_DEFAULT_CVARS
end

function RefineUI:ApplyInstallCVars()
    for i = 1, #INSTALL_DEFAULT_CVARS do
        local cvar = INSTALL_DEFAULT_CVARS[i]
        self:SetCVarIfChanged(cvar.name, cvar.value)
    end

    self:SetCVarIfChanged("showTimestamps", GetConfiguredTimestampValue())

    local general = self.Config and self.Config.General or nil
    if general and general.UseUIScale and type(self.SetUIScale) == "function" then
        self:SetUIScale()
    end
end
