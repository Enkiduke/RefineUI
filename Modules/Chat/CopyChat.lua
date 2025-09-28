local R, C, L = unpack(RefineUI)

-- Constants
local COPY_FRAME_WIDTH = 540
local COPY_FRAME_HEIGHT = 300
local COPY_BOX_WIDTH_OFFSET = 40 -- (540 - 500)
local COPY_BOX_HEIGHT_OFFSET = 0 -- (300 - 300) 
local SCROLL_AREA_PADDING_LEFT = 8
local SCROLL_AREA_PADDING_TOP = 30
local SCROLL_AREA_PADDING_RIGHT = 27
local SCROLL_AREA_PADDING_BOTTOM = 8
local BUTTON_SIZE = 20
local BUTTON_ICON_SIZE = 16
local BUTTON_ICON_TEXTURE = "Interface\\BUTTONS\\UI-GuildButton-PublicNote-Up"
local DEFAULT_REPLACEMENT_SIZE = ":12:12"
local RAID_TARGET_PATTERN_1 = "|T[^\\]+\\[^\\]+\\[Uu][Ii]%-[Rr][Aa][Ii][Dd][Tt][Aa][Rr][Gg][Ee][Tt][Ii][Nn][Gg][Ii][Cc][Oo][Nn]_(%d)[^|]+|t"
local RAID_TARGET_REPLACEMENT_1 = "{rt%1}"
local RAID_TARGET_PATTERN_2 = "|T13700([1-8])[^|]+|t"
local RAID_TARGET_REPLACEMENT_2 = "{rt%1}"
local TEXTURE_PATTERN = "|T[^|]+|t"
local HYPERLINK_PATTERN = "|A[^|]+|a"
local HAS_TEX = "|T"
local HAS_ATLAS = "|A"
local gsub = string.gsub
local find = string.find

----------------------------------------------------------------------------------------
-- Module Vars
----------------------------------------------------------------------------------------
local frame = nil
local editBox = nil
local font = nil
local isf = nil
local sizes = { -- Font size patterns to detect and replace (e.g., |cffXXXXXX:...|r)
	":14:14",
	":15:15",
	":16:16",
	":12:20", -- Common in some addons/system messages
	":14"     -- Sometimes only one size value is present
}

----------------------------------------------------------------------------------------
-- Functions
----------------------------------------------------------------------------------------
local function CreatCopyFrame()
	frame = CreateFrame("Frame", "CopyFrame", UIParent)
	frame:SetTemplate("Transparent")
	frame:SetWidth(COPY_FRAME_WIDTH)
	frame:SetHeight(COPY_FRAME_HEIGHT)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
	frame:SetFrameStrata("DIALOG")
	tinsert(UISpecialFrames, "CopyFrame")
	frame:Hide()
	frame:EnableMouse(true)

	editBox = CreateFrame("EditBox", "CopyBox", frame)
	editBox:SetMultiLine(true)
	editBox:SetMaxLetters(0)
	editBox:SetAutoFocus(false)
	editBox:SetFontObject(ChatFontNormal)
	editBox:SetWidth(COPY_FRAME_WIDTH - COPY_BOX_WIDTH_OFFSET)
	editBox:SetHeight(COPY_FRAME_HEIGHT - COPY_BOX_HEIGHT_OFFSET)
	editBox:SetScript("OnEscapePressed", function() frame:Hide() end)

	-- This script runs whenever the text in the CopyBox is set.
	-- It iterates through known font size patterns (like :14:14) that might appear
	-- in chat messages (often embedded in color codes) and replaces them with a 
	-- standard size (DEFAULT_REPLACEMENT_SIZE) to ensure consistency in the copied text.
	-- It avoids replacing patterns followed by ']' to prevent messing up potential texture paths
	-- like |TInterface\Icons\Icon:16:16|t.
	editBox:SetScript("OnTextSet", function(self)
		local text = self:GetText()
		local originalText = text -- Keep original to compare later

		-- Iterate through specified sizes and replace them if not followed by ']'
		for _, sizePattern in ipairs(sizes) do
			-- Escape ':' for Lua pattern matching
			local escapedPattern = sizePattern:gsub(":", "%%:")
			
			-- Pattern to find 'sizePattern' NOT followed by ']'
			local patternFollowed = escapedPattern .. "([^%]])"
			local replacementFollowed = DEFAULT_REPLACEMENT_SIZE .. "%1" -- %1 captures the character after the pattern
			text = string.gsub(text, patternFollowed, replacementFollowed)

			-- Pattern to find 'sizePattern' at the end of the string
			local patternEnd = escapedPattern .. "$"
			local replacementEnd = DEFAULT_REPLACEMENT_SIZE
			text = string.gsub(text, patternEnd, replacementEnd)
		end

		-- Only update if text actually changed to avoid recursion
		if text ~= originalText then
			self:SetText(text)
		end
	end)

    local scrollArea = CreateFrame("ScrollFrame", "CopyScroll", frame, "ScrollFrameTemplate")
	scrollArea:SetPoint("TOPLEFT", frame, "TOPLEFT", SCROLL_AREA_PADDING_LEFT, -SCROLL_AREA_PADDING_TOP)
	scrollArea:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SCROLL_AREA_PADDING_RIGHT, SCROLL_AREA_PADDING_BOTTOM)
	scrollArea:SetScrollChild(editBox)

	-- Check if SkinScrollBar is defined
    local cs = _G and rawget(_G, 'CopyScroll')
    local csb = cs and rawget(cs, 'ScrollBar') or nil
    if R.SkinScrollBar and csb then
        R.SkinScrollBar(csb)
	end

	local close = CreateFrame("Button", "CopyCloseButton", frame, "UIPanelCloseButton")
	
	-- Check if SkinCloseButton is defined
	if R.SkinCloseButton then
		R.SkinCloseButton(close)
	else
		-- Optionally, you can set a default close button appearance here
		close:SetSize(32, 32) -- Set size for the close button -- TODO: Make constant?
		close:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up") -- Default texture -- TODO: Make constant?
		close:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down") -- Pushed texture -- TODO: Make constant?
		close:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight") -- Highlight texture -- TODO: Make constant?
	end

    font = frame:CreateFontString(nil, nil, "GameFontNormal")
	font:Hide()

	isf = true
end

-- Helper function for MessageIsProtected gsub.
-- If called by gsub with an ID capture, it returns the ID.
local canChangeMessage = function(arg1, id)
	if id and arg1 == "" then return id end
end

-- Checks if a message contains protected sequences (like item links |cff...|H...|h[...]|h|r)
-- that should not be altered or included in the plain text copy.
-- Such sequences can cause issues when copied as plain text.
local function MessageIsProtected(message)
	-- The pattern "(:?|?)|K(.-)|k" targets the specific internal representation of links/protected text.
	-- gsub attempts to replace these patterns using canChangeMessage.
	-- If the message string changes after the gsub operation, it means it contained one of these protected patterns.
	return message and (message ~= gsub(message, "(:?|?)|K(.-)|k", canChangeMessage))
end

local scrollDown = function()
    local cs = rawget(_G, 'CopyScroll')
    if cs and cs.GetVerticalScrollRange then
        cs:SetVerticalScroll(cs:GetVerticalScrollRange() or 0)
    end
end

local function Copy(cf)
	if not isf then CreatCopyFrame() end
	local text = ""
	for i = 1, cf:GetNumMessages() do
		local line = cf:GetMessageInfo(i)
		if line and not MessageIsProtected(line) then
            if font and font.SetFormattedText then
                font:SetFormattedText("%s \n", line)
            end
            local cleanLine = (font and font.GetText and font:GetText()) or ""
			text = text..cleanLine
		end
	end
	-- Fast sentinels: only run replacements if patterns are present
	local hasTex = find(text, HAS_TEX, 1, true)
	local hasAtlas = find(text, HAS_ATLAS, 1, true)
	if hasTex then
		text = gsub(text, RAID_TARGET_PATTERN_1, RAID_TARGET_REPLACEMENT_1)
		text = gsub(text, RAID_TARGET_PATTERN_2, RAID_TARGET_REPLACEMENT_2)
		text = gsub(text, TEXTURE_PATTERN, "")
	end
	if hasAtlas then
		text = gsub(text, HYPERLINK_PATTERN, "")
	end
    if frame and frame.IsShown and frame:IsShown() then
        if frame.Hide then frame:Hide() end
        return
    end

    if editBox and editBox.SetText then
        editBox:SetText(text)
    end
    if frame and frame.Show then
        frame:Show()
    end

	C_Timer.After(0, scrollDown)
end

for i = 1, NUM_CHAT_WINDOWS do
	local cf = _G[format("ChatFrame%d", i)]
	local button = CreateFrame("Button", format("ButtonCF%d", i), cf)
	button:SetPoint("BOTTOMRIGHT", 0, 1)
	button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	button:SetAlpha(0)
	button:SetTemplate("Transparent")
	if C and C.media and C.media.borderColor then -- Check if border color is available
		button:SetBackdropBorderColor(unpack(C.media.borderColor))
	else
		button:SetBackdropBorderColor(0, 0, 0, 1) -- Default to black border
	end

	local icon = button:CreateTexture(nil, "BORDER")
	icon:SetPoint("CENTER")
	icon:SetTexture(BUTTON_ICON_TEXTURE)
	icon:SetSize(BUTTON_ICON_SIZE, BUTTON_ICON_SIZE)

	button:SetScript("OnMouseUp", function(_, btn)
		if btn == "RightButton" then
            local cm = rawget(_G, 'ChatMenu')
            if cm then
                ToggleFrame(cm)
            end
		elseif btn == "MiddleButton" then
			RandomRoll(1, 100)
		else
			Copy(cf)
		end
	end)

	-- Remove these lines
	-- button:SetScript("OnEnter", function() button:FadeIn() end)
	-- button:SetScript("OnLeave", function() button:FadeOut() end)

	-- Add hover functionality to the chat frame
	cf:HookScript("OnEnter", function()
		R.FadeIn(button)  -- Call the function from R
	end)
	
	cf:HookScript("OnLeave", function()
		R.FadeOut(button)  -- Call the function from R
	end)
	
	-- Make sure the button stays visible when hovering over it
	button:SetScript("OnEnter", function()
		R.FadeIn(button)  -- Use the existing FadeIn function
	end)
	
	button:SetScript("OnLeave", function()
		if not cf:IsMouseOver() then
			R.FadeOut(button)  -- Use the existing FadeOut function
		end
	end)
end

SlashCmdList.COPY_CHAT = function()
	Copy(_G["ChatFrame1"])
end