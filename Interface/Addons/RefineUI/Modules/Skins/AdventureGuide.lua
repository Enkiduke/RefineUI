----------------------------------------------------------------------------------------
-- Skins Component: Adventure Guide Typography
-- Description: Improves Adventure Guide text contrast, outline, and shadow.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Skins = RefineUI:GetModule("Skins")
if not Skins then return end

local _G = _G
local type = type

local COMPONENT_KEY = "Skins:AdventureGuide"
local ENCOUNTER_ADDON = "Blizzard_EncounterJournal"
local DARK_LUMINANCE = 0.38
local NEUTRAL_SPREAD = 0.08
local GOLD_RED, GOLD_GREEN, GOLD_BLUE = 1, 0.82, 0
local SIMPLE_HTML_TEXT_TYPES = { "p", "h1", "h2", "h3" }
local refreshQueued

local REFRESH_FUNCTIONS = {
    "EncounterJournal_ListInstances",
    "EncounterJournal_DisplayInstance",
    "EncounterJournal_DisplayEncounter",
    "EncounterJournal_SetTab",
    "EncounterJournal_SetupExpansionDropdown",
}

local function IsUsable(object)
    if not object then return false end
    if object.IsForbidden and object:IsForbidden() then return false end
    return true
end

local function BuildOutlinedFlag(existingFlags)
    local flags = type(existingFlags) == "string" and existingFlags or ""
    if flags:find("OUTLINE", 1, true) then return flags end
    if flags == "" then return "OUTLINE" end
    return flags .. ",OUTLINE"
end

local function GetShadowStyle()
    local appearance = RefineUI.Config and RefineUI.Config.General
        and RefineUI.Config.General.Appearance
    local color = appearance and appearance.ShadowColor or { 0, 0, 0, 1 }
    local offset = appearance and appearance.ShadowOffset or { 1, -1 }
    return color, offset
end

local function GetReadableTextColor(red, green, blue)
    local luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
    if luminance > DARK_LUMINANCE then return end

    local highest = math.max(red, green, blue)
    local lowest = math.min(red, green, blue)
    if highest - lowest <= NEUTRAL_SPREAD then
        return 1, 1, 1
    end

    local isBrown = red >= green and green > blue + 0.02 and red > blue + 0.08
    if isBrown then return GOLD_RED, GOLD_GREEN, GOLD_BLUE end
end

local function StyleTextColor(fontString)
    if type(fontString.GetTextColor) ~= "function"
        or type(fontString.SetTextColor) ~= "function" then return end

    local red, green, blue, alpha = fontString:GetTextColor()
    if type(red) ~= "number" or type(green) ~= "number" or type(blue) ~= "number" then return end

    local readableRed, readableGreen, readableBlue = GetReadableTextColor(red, green, blue)
    if readableRed then
        fontString:SetTextColor(readableRed, readableGreen, readableBlue, alpha or 1)
    end
end

local function SetSimpleHTMLTextWhite(html)
    for _, textType in ipairs(SIMPLE_HTML_TEXT_TYPES) do
        local success, _, _, _, alpha = pcall(html.GetTextColor, html, textType)
        if success then
            pcall(html.SetTextColor, html, textType, 1, 1, 1, alpha or 1)
        end
    end
end

local function SetTextWhite(object)
    if not IsUsable(object) or type(object.GetObjectType) ~= "function"
        or type(object.SetTextColor) ~= "function" then return end

    local objectType = object:GetObjectType()
    if objectType == "SimpleHTML" then
        if type(object.GetTextColor) == "function" then SetSimpleHTMLTextWhite(object) end
        return
    end
    if objectType ~= "FontString" then return end

    local alpha = 1
    if type(object.GetTextColor) == "function" then
        local _, _, _, currentAlpha = object:GetTextColor()
        alpha = currentAlpha or 1
    end
    object:SetTextColor(1, 1, 1, alpha)
end

local function StyleLootRowMetadata(row)
    if not IsUsable(row) then return end
    SetTextWhite(row.slot)
    SetTextWhite(row.armorType)
end

local function StyleVisibleLootMetadata()
    local encounterInfo = _G.EncounterJournalEncounterFrameInfo
    local lootContainer = encounterInfo and encounterInfo.LootContainer
    local scrollBox = lootContainer and lootContainer.ScrollBox
    if not scrollBox or type(scrollBox.GetFrames) ~= "function" then return end

    local rows = scrollBox:GetFrames()
    if type(rows) ~= "table" then return end
    for index = 1, #rows do StyleLootRowMetadata(rows[index]) end
end

-- Walks GetRegions/GetChildren results without building a table per frame.
local function ForEachArg(fn, ...)
    for index = 1, select("#", ...) do fn((select(index, ...))) end
end

local function StyleFrameTextWhite(frame)
    if not IsUsable(frame) then return end
    SetTextWhite(frame)
    ForEachArg(SetTextWhite, frame:GetRegions())
    ForEachArg(StyleFrameTextWhite, frame:GetChildren())
end

local function StyleEncounterPageText()
    local journal = _G.EncounterJournal
    local info = journal and journal.encounter and journal.encounter.info
    if not info then return end

    local overview = info.overviewScroll and info.overviewScroll.child
    local abilities = info.detailsScroll and info.detailsScroll.child
    StyleFrameTextWhite(overview)
    StyleFrameTextWhite(abilities)
end

local function StyleFontString(fontString)
    if not IsUsable(fontString) or type(fontString.GetObjectType) ~= "function"
        or fontString:GetObjectType() ~= "FontString" or type(fontString.GetFont) ~= "function"
        or type(fontString.SetFont) ~= "function" then return end

    local fontPath, fontSize, fontFlags = fontString:GetFont()
    if type(fontPath) ~= "string" or type(fontSize) ~= "number" then return end

    local outlinedFlags = BuildOutlinedFlag(fontFlags)
    if outlinedFlags ~= fontFlags then fontString:SetFont(fontPath, fontSize, outlinedFlags) end

    local color, offset = GetShadowStyle()
    if type(fontString.SetShadowColor) == "function" then
        fontString:SetShadowColor(color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 1)
    end
    if type(fontString.SetShadowOffset) == "function" then
        fontString:SetShadowOffset(offset[1] or 1, offset[2] or -1)
    end
    StyleTextColor(fontString)
end

local function StyleFrameFontStrings(frame)
    if not IsUsable(frame) then return end
    ForEachArg(StyleFontString, frame:GetRegions())
    ForEachArg(StyleFrameFontStrings, frame:GetChildren())
end

function Skins:StyleAdventureGuideText()
    StyleFrameFontStrings(_G.EncounterJournal)
    StyleEncounterPageText()
    StyleVisibleLootMetadata()
end

local function RunQueuedStyle()
    refreshQueued = nil
    Skins:StyleAdventureGuideText()
end

function Skins:QueueAdventureGuideTextStyle()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, RunQueuedStyle)
end

local function InstallHooks()
    local journal = _G.EncounterJournal
    if not IsUsable(journal) then return false end

    for _, functionName in ipairs(REFRESH_FUNCTIONS) do
        if type(_G[functionName]) == "function" then
            RefineUI:HookOnce(COMPONENT_KEY .. ":" .. functionName, functionName, function()
                Skins:QueueAdventureGuideTextStyle()
            end)
        end
    end

    local itemMixin = _G.EncounterJournalItemMixin
    if itemMixin and type(itemMixin.Init) == "function" then
        RefineUI:HookOnce(COMPONENT_KEY .. ":EncounterJournalItemMixin:Init", itemMixin, "Init", function(row)
            StyleLootRowMetadata(row)
        end)
    end

    if type(journal.HookScript) == "function" then
        RefineUI:HookScriptOnce(COMPONENT_KEY .. ":OnShow", journal, "OnShow", function()
            Skins:QueueAdventureGuideTextStyle()
        end)
    end

    Skins:QueueAdventureGuideTextStyle()
    return true
end

function Skins:SetupAdventureGuideSkin()
    if self.adventureGuideSkinSetup then return end
    self.adventureGuideSkinSetup = true

    EventUtil.ContinueOnAddOnLoaded(ENCOUNTER_ADDON, InstallHooks)
end
