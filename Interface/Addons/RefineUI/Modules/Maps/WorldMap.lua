----------------------------------------------------------------------------------------
-- WorldMap for RefineUI
-- Description: Restyles Blizzard's WorldMap coordinates and adds a quest counter.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Maps = RefineUI:GetModule("Maps")

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local _G = _G
local ipairs = ipairs
local select = select

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local CreateFont = CreateFont
local hooksecurefunc = hooksecurefunc
local C_QuestLog = C_QuestLog
local WorldMapFrame = _G.WorldMapFrame
local QuestMapFrame = _G.QuestMapFrame

----------------------------------------------------------------------------------------
-- Functions
----------------------------------------------------------------------------------------

-- Own font object so changes to Blizzard's shared font objects never restyle the labels.
local function CreateCoordsFont()
    local font = CreateFont("RefineUI_WorldMapCoordsFont")
    RefineUI.Font(font, 16, nil, "THICKOUTLINE")
    font:SetTextColor(1, 0.82, 0)
    font:SetJustifyH("CENTER")
    return font
end

local function StyleCoordsRow(row, font)
    local label = row.Label
    row:SetHeight(20)
    label:SetFontObject(font)
    label:ClearAllPoints()
    label:SetPoint("BOTTOM")
end

-- Blizzard's coords panel re-docks itself in PostRefresh on every map change.
local function AnchorCoordsPanel(panel)
    panel:ClearAllPoints()
    panel:SetPoint("BOTTOM", WorldMapFrame:GetCanvasContainer(), "BOTTOM", 0, 4)
end

local function SetupCoordsPanel()
    local postRefresh = _G.WorldMapCoordsPanelMixin.PostRefresh
    for _, frame in ipairs(WorldMapFrame.overlayFrames) do
        if frame.PostRefresh == postRefresh then
            local font = CreateCoordsFont()
            StyleCoordsRow(frame.CursorCoords, font)
            StyleCoordsRow(frame.PlayerCoords, font)
            hooksecurefunc(frame, "PostRefresh", AnchorCoordsPanel)
            AnchorCoordsPanel(frame)
            return
        end
    end
end

function Maps:SetupWorldMap()
    if not self.db or self.db.WorldMap ~= true then return end
    if self._worldMapSetupDone then return end
    self._worldMapSetupDone = true

    SetupCoordsPanel()

    local numQuest = CreateFrame("Frame", nil, QuestMapFrame)
    numQuest.text = numQuest:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    numQuest.text:SetPoint("TOP", QuestMapFrame, "TOP", 0, -21)

    local lastNumQuests, lastMaxQuests

    local function UpdateQuestCounter()
        if not WorldMapFrame:IsShown() then return end
        local numQuests = select(2, C_QuestLog.GetNumQuestLogEntries())
        local maxQuests = C_QuestLog.GetMaxNumQuestsCanAccept()
        if numQuests ~= lastNumQuests or maxQuests ~= lastMaxQuests then
            lastNumQuests, lastMaxQuests = numQuests, maxQuests
            numQuest.text:SetFormattedText("%d/%d", numQuests, maxQuests)
        end
    end

    WorldMapFrame:HookScript("OnShow", UpdateQuestCounter)
    RefineUI:RegisterEventCallback("QUEST_LOG_UPDATE", UpdateQuestCounter, "Maps:WorldMapQuestCount")
end
