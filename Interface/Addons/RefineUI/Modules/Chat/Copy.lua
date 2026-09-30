----------------------------------------------------------------------------------------
-- Chat copy for RefineUI
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Chat = RefineUI:GetModule("Chat")

----------------------------------------------------------------------------------------
-- Lua / WoW Globals
----------------------------------------------------------------------------------------
local _G = _G
local CreateFrame = CreateFrame
local floor = math.floor
local format = string.format
local gsub = string.gsub
local pairs = pairs
local setmetatable = setmetatable
local table_concat = table.concat
local type = type

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local MAX_COPY_LINES = 300
local MAX_COPY_BYTES = 60000
local PROTECTED_LINE = "|cff808080<protected>|r"
local RAID_TARGET_PATTERN_1 = "|T[^\\]+\\[^\\]+\\[Uu][Ii]%-[Rr][Aa][Ii][Dd][Tt][Aa][Rr][Gg][Ee][Tt][Ii][Nn][Gg][Ii][Cc][Oo][Nn]_(%d)[^|]+|t"
local RAID_TARGET_PATTERN_2 = "|T13700([1-8])[^|]+|t"
local GOLD_ICON_PATTERN = "|TInterface\\MoneyFrame\\UI%-GoldIcon.-|t"
local SILVER_ICON_PATTERN = "|TInterface\\MoneyFrame\\UI%-SilverIcon.-|t"
local COPPER_ICON_PATTERN = "|TInterface\\MoneyFrame\\UI%-CopperIcon.-|t"
local TEXTURE_PATTERN = "|T.-|t"
local ATLAS_PATTERN = "|A.-|a"
local HYPERLINK_PATTERN = "|H.-|h(.-)|h"

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
local copyButtons = setmetatable({}, { __mode = "k" })

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local function IsCopySuspended()
    return Chat and Chat.ShouldSuspendOptionalEnhancements and Chat:ShouldSuspendOptionalEnhancements() == true
end

local function IsAccessibleNumber(value)
    if Chat and Chat.IsAccessibleValue and not Chat:IsAccessibleValue(value) then
        return false
    end
    return type(value) == "number"
end

local function ClampColorByte(value)
    if not IsAccessibleNumber(value) then
        return 255
    end
    if value < 0 then value = 0 end
    if value > 1 then value = 1 end
    return floor(value * 255 + 0.5)
end

local function GetColorCode(r, g, b)
    return format("|cff%02x%02x%02x", ClampColorByte(r), ClampColorByte(g), ClampColorByte(b))
end

local function MessageIsProtected(message)
    if Chat and Chat.MessageIsProtected then
        return Chat:MessageIsProtected(message)
    end
    return type(message) ~= "string"
end

local function SanitizeCopyLine(message, r, g, b)
    if not Chat:IsAccessibleString(message) or MessageIsProtected(message) then
        return PROTECTED_LINE
    end

    local clean = gsub(message, RAID_TARGET_PATTERN_1, "{rt%1}")
    clean = gsub(clean, RAID_TARGET_PATTERN_2, "{rt%1}")
    clean = gsub(clean, GOLD_ICON_PATTERN, "g")
    clean = gsub(clean, SILVER_ICON_PATTERN, "s")
    clean = gsub(clean, COPPER_ICON_PATTERN, "c")
    clean = gsub(clean, HYPERLINK_PATTERN, "%1")
    clean = gsub(clean, TEXTURE_PATTERN, "")
    clean = gsub(clean, ATLAS_PATTERN, "")

    local baseColor = GetColorCode(r, g, b)
    clean = gsub(clean, "|r", "|r" .. baseColor)
    return baseColor .. clean .. "|r"
end

local function ApplyCopyButtonState(button)
    if not button then
        return
    end

    if IsCopySuspended() then
        button:SetAlpha(0)
        button:Hide()
        button:EnableMouse(false)
        return
    end

    button:Show()
    button:SetAlpha(0.4)
    button:EnableMouse(true)
end

local function GetChatLines(chatFrame)
    local reverseLines = {}
    local bytesUsed = 0
    local count = chatFrame:GetNumMessages()
    local first = math.max(1, count - MAX_COPY_LINES + 1)

    for index = count, first, -1 do
        local message, r, g, b = chatFrame:GetMessageInfo(index)
        local line = SanitizeCopyLine(message, r, g, b)
        local separatorBytes = #reverseLines > 0 and 1 or 0
        if bytesUsed + separatorBytes + #line > MAX_COPY_BYTES then
            break
        end

        reverseLines[#reverseLines + 1] = line
        bytesUsed = bytesUsed + separatorBytes + #line
    end

    local lines = {}
    for index = #reverseLines, 1, -1 do
        lines[#lines + 1] = reverseLines[index]
    end
    return table_concat(lines, "\n")
end

local function ShowCopyFrame(chatFrame)
    if IsCopySuspended() then
        return
    end

    RefineUI:ShowCopyWindow("Copy Chat — Ctrl+C", GetChatLines(chatFrame))
end

local function CreateCopyButton(chatFrame)
    if not chatFrame or copyButtons[chatFrame] then
        return
    end

    local button = CreateFrame("Button", nil, chatFrame)
    RefineUI.Size(button, 20, 20)
    RefineUI.Point(button, "BOTTOMRIGHT", chatFrame, "BOTTOMRIGHT", 2, -2)

    local texture = button:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints()
    texture:SetTexture(RefineUI.Media.Textures.ChatCopy)
    texture:SetVertexColor(1, 0.824, 0)

    button:SetScript("OnEnter", function(self)
        if not IsCopySuspended() then
            self:SetAlpha(1)
        end
    end)
    button:SetScript("OnLeave", function(self)
        if not IsCopySuspended() then
            self:SetAlpha(0.4)
        end
    end)
    button:SetScript("OnClick", function()
        ShowCopyFrame(chatFrame)
    end)

    copyButtons[chatFrame] = button
    ApplyCopyButtonState(button)
end

----------------------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------------------
function Chat:SetupCopyForFrame(chatFrame)
    CreateCopyButton(chatFrame)
end

function Chat:SetupCopy()
    local chatFrames = _G.CHAT_FRAMES
    if chatFrames then
        for _, frameName in pairs(chatFrames) do
            CreateCopyButton(_G[frameName])
        end
    end

    for index = 1, _G.NUM_CHAT_WINDOWS do
        CreateCopyButton(_G["ChatFrame" .. index])
    end
end

function Chat:GetCopyButton(chatFrame)
    return copyButtons[chatFrame]
end

function Chat:RefreshCopyButtons()
    for _, button in pairs(copyButtons) do
        ApplyCopyButtonState(button)
    end

    if IsCopySuspended() then
        RefineUI:HideCopyWindow()
    end
end
