----------------------------------------------------------------------------------------
-- Chat Edit Mode settings for RefineUI
----------------------------------------------------------------------------------------

local _, RefineUI = ...

local Chat = RefineUI:GetModule("Chat")
if not Chat then
    return
end

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local type = type
local C_CVar = C_CVar

----------------------------------------------------------------------------------------
-- Locals
----------------------------------------------------------------------------------------
local TIMESTAMP_FORMATS = {
    { text = "24 Hour", value = "|cff808080[%H:%M]|r " },
    { text = "24 Hour + Sec", value = "|cff808080[%H:%M:%S]|r " },
    { text = "12 Hour", value = "|cff808080[%I:%M %p]|r " },
    { text = "12 Hour + Sec", value = "|cff808080[%I:%M:%S %p]|r " },
}

local editModeSettingsRegistered = false

local function GetChatConfig()
    Chat.db = Chat.db or (RefineUI.DB and RefineUI.DB.Chat) or RefineUI.Config.Chat or {}
    if Chat.db.TimeStamps == nil then
        Chat.db.TimeStamps = true
    end
    if type(Chat.db.TimestampFormat) ~= "string" or Chat.db.TimestampFormat == "" then
        Chat.db.TimestampFormat = TIMESTAMP_FORMATS[1].value
    end
    if Chat.db.ItemLevelLinks == nil then
        Chat.db.ItemLevelLinks = true
    end
    if Chat.db.RoleIcons == nil then
        Chat.db.RoleIcons = true
    end
    if Chat.db.ChatIcons == nil then
        Chat.db.ChatIcons = true
    end
    if Chat.db.ShortChannels == nil then
        Chat.db.ShortChannels = true
    end
    return Chat.db
end

function Chat:ResolveTimestampFormat()
    local cfg = GetChatConfig()
    local value = cfg.TimestampFormat
    for index = 1, #TIMESTAMP_FORMATS do
        if TIMESTAMP_FORMATS[index].value == value then
            return value
        end
    end
    return TIMESTAMP_FORMATS[1].value
end

function Chat:ApplyTimestampSetting()
    local cfg = GetChatConfig()
    if not C_CVar or type(C_CVar.SetCVar) ~= "function" then
        return
    end

    if cfg.TimeStamps then
        C_CVar.SetCVar("showTimestamps", self:ResolveTimestampFormat())
    else
        C_CVar.SetCVar("showTimestamps", "none")
    end
end

function Chat:RefreshRuntimeSettings()
    self.db = GetChatConfig()
    self:ApplyTimestampSetting()

    if self.SetupIcons then
        self:SetupIcons()
    end
    if self.SetupRoleIcons then
        self:SetupRoleIcons()
    end
end

function Chat:InitializeEditModeSettings()
    if editModeSettingsRegistered then
        return
    end

    local lib = RefineUI.LibEditMode
    if not lib or not lib.SettingType or type(lib.AddSystemSettings) ~= "function" then
        return
    end

    local Enum = _G.Enum
    if not Enum or not Enum.EditModeSystem or not Enum.EditModeSystem.ChatFrame then
        return
    end

    local settingType = lib.SettingType
    local settings = {
        {
            kind = settingType.Checkbox,
            name = "Show Timestamps",
            default = true,
            get = function()
                return GetChatConfig().TimeStamps ~= false
            end,
            set = function(_, value)
                GetChatConfig().TimeStamps = value and true or false
                Chat:RefreshRuntimeSettings()
            end,
        },
        {
            kind = settingType.Dropdown,
            name = "Timestamp Format",
            default = TIMESTAMP_FORMATS[1].value,
            values = TIMESTAMP_FORMATS,
            get = function()
                return Chat:ResolveTimestampFormat()
            end,
            set = function(_, value)
                GetChatConfig().TimestampFormat = value
                Chat:RefreshRuntimeSettings()
            end,
        },
        {
            kind = settingType.Checkbox,
            name = "Show Item-Level In Links",
            default = true,
            get = function()
                return GetChatConfig().ItemLevelLinks ~= false
            end,
            set = function(_, value)
                GetChatConfig().ItemLevelLinks = value and true or false
            end,
        },
        {
            kind = settingType.Checkbox,
            name = "Show Role Icons",
            default = true,
            get = function()
                return GetChatConfig().RoleIcons ~= false
            end,
            set = function(_, value)
                GetChatConfig().RoleIcons = value and true or false
                Chat:RefreshRuntimeSettings()
            end,
        },
        {
            kind = settingType.Checkbox,
            name = "Show Chat Link Icons",
            default = true,
            get = function()
                return GetChatConfig().ChatIcons ~= false
            end,
            set = function(_, value)
                GetChatConfig().ChatIcons = value and true or false
                Chat:RefreshRuntimeSettings()
            end,
        },
        {
            kind = settingType.Checkbox,
            name = "Shorten Channel Names",
            default = true,
            get = function()
                return GetChatConfig().ShortChannels ~= false
            end,
            set = function(_, value)
                GetChatConfig().ShortChannels = value and true or false
            end,
        },
    }

    lib:AddSystemSettings(Enum.EditModeSystem.ChatFrame, settings)
    editModeSettingsRegistered = true
end
