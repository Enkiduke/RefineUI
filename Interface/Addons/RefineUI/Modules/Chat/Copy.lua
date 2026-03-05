----------------------------------------------------------------------------------------
-- CopyChat for RefineUI
-- Description: Provides a mechanism to copy text from chat frames.
----------------------------------------------------------------------------------------

local AddOnName, RefineUI = ...
local Chat = RefineUI:GetModule("Chat")

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local _G = _G
local tinsert = table.insert
local table_concat = table.concat
local gsub = string.gsub
local find = string.find

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local UIParent = _G.UIParent
local FCF_GetCurrentChatFrame = _G.FCF_GetCurrentChatFrame
local C_Timer = _G.C_Timer

----------------------------------------------------------------------------------------
-- Locals
----------------------------------------------------------------------------------------
local frame
local scrollArea
local _copyIsSetup = false

-- Patterns for sanitization
local RAID_TARGET_PATTERN_1 = "|T[^\\]+\\[^\\]+\\[Uu][Ii]%-[Rr][Aa][Ii][Dd][Tt][Aa][Rr][Gg][Ee][Tt][Ii][Nn][Gg][Ii][Cc][Oo][Nn]_(%d)[^|]+|t"
local RAID_TARGET_REPLACEMENT_1 = "{rt%1}"
local RAID_TARGET_PATTERN_2 = "|T13700([1-8])[^|]+|t"
local RAID_TARGET_REPLACEMENT_2 = "{rt%1}"
local TEXTURE_PATTERN = "|T[^|]+|t"
local HYPERLINK_PATTERN = "|A[^|]+|a"
local HAS_TEX = "|T"
local HAS_ATLAS = "|A"

local function MessageIsProtected(message)
    local canChangeMessage = function(arg1, id)
        if id and arg1 == "" then return id end
    end

    local success, isProtected = pcall(function()
        return message and (message ~= gsub(message, "(:?|?)|K(.-)|k", canChangeMessage))
    end)

    if not success then return true end -- Fail safe on secret values
    return isProtected
end

local function ScrollDown()
    if scrollArea and scrollArea.GetVerticalScrollRange then
        scrollArea:SetVerticalScroll(scrollArea:GetVerticalScrollRange() or 0)
    end
end

----------------------------------------------------------------------------------------
-- Functions
----------------------------------------------------------------------------------------

local function CreateCopyFrame()
    frame = CreateFrame("Frame", "RefineUI_ChatCopy", UIParent)
    -- RefineUI.AddAPI(frame) -- REMOVED
    RefineUI.SetTemplate(frame, "Transparent")
    RefineUI.Size(frame, 600, 400)
    RefineUI.Point(frame, "CENTER", UIParent, "CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:Hide()

    scrollArea = CreateFrame("ScrollFrame", "RefineUI_ChatCopyScroll", frame, "UIPanelScrollFrameTemplate")
    RefineUI.Point(scrollArea, "TOPLEFT", frame, "TOPLEFT", 10, -30)
    RefineUI.Point(scrollArea, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 10)
    -- RefineUI.AddAPI(scrollArea) -- REMOVED

    local editBox = CreateFrame("EditBox", "RefineUI_ChatCopyEditBox", scrollArea)
    editBox:SetMultiLine(true)
    editBox:SetMaxLetters(0) -- Unlimited
    editBox:EnableMouse(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetWidth(scrollArea:GetWidth() - 25)
    editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
    scrollArea:SetScrollChild(editBox)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT")
    RefineUI.AddAPI(close)
    
    local font = frame:CreateFontString(nil, nil, "GameFontNormal")
    font:Hide()
    frame.font = font

    return frame, editBox
end

local function GetChatLines(chatFrame)
    if not frame then CreateCopyFrame() end
    local font = frame.font
    local lines = {}
    local num = chatFrame:GetNumMessages()
    
    for i = 1, num do
        local line = chatFrame:GetMessageInfo(i)
        if line and not MessageIsProtected(line) then
            font:SetFormattedText("%s \n", line)
            local cleanLine = font:GetText() or ""
            tinsert(lines, cleanLine)
        end
    end

    local text = table_concat(lines)
    
    -- Sanitize
    if find(text, HAS_TEX, 1, true) then
        text = gsub(text, RAID_TARGET_PATTERN_1, RAID_TARGET_REPLACEMENT_1)
        text = gsub(text, RAID_TARGET_PATTERN_2, RAID_TARGET_REPLACEMENT_2)
        text = gsub(text, TEXTURE_PATTERN, "")
    end
    
    if find(text, HAS_ATLAS, 1, true) then
        text = gsub(text, HYPERLINK_PATTERN, "")
    end
    
    return text
end

function Chat:SetupCopy()
    if _copyIsSetup then
        return
    end

    for i = 1, NUM_CHAT_WINDOWS do
        local cf = _G["ChatFrame"..i]
        local btn = CreateFrame("Button", nil, cf)
        RefineUI.Size(btn, 20, 20)
        btn:SetAlpha(0)
        RefineUI.Point(btn, "BOTTOMRIGHT", cf, "BOTTOMRIGHT", 2, -2)
        
        local tex = btn:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints()
        tex:SetTexture(RefineUI.Media.Textures.ChatCopy)
        tex:SetVertexColor(1, 0.824, 0)
        
        btn:SetScript("OnEnter", function(self) RefineUI:FadeIn(self) end)
        btn:SetScript("OnLeave", function(self) 
            if not cf:IsMouseOver() then RefineUI:FadeOut(self) end 
        end)
        
        cf:HookScript("OnEnter", function() RefineUI:FadeIn(btn) end)
        cf:HookScript("OnLeave", function() RefineUI:FadeOut(btn) end)
        
        btn:SetScript("OnClick", function()
            if not frame then CreateCopyFrame() end
            
            local text = GetChatLines(cf)
            local editBox = _G["RefineUI_ChatCopyEditBox"]
            editBox:SetText(text)
            frame:Show()
            
            C_Timer.After(0.1, ScrollDown)
        end)
    end

    _copyIsSetup = true
end
