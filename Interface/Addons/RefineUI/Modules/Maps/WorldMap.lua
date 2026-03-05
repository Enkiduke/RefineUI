----------------------------------------------------------------------------------------
-- WorldMap for RefineUI
-- Description: Displays player and cursor coordinates on the WorldMap.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Maps = RefineUI:GetModule("Maps")

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local _G = _G
local select = select
local format = string.format

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local CreateVector2D = CreateVector2D
local UnitPosition = UnitPosition
local UnitName = UnitName
local C_Map = C_Map
local C_QuestLog = C_QuestLog
local WorldMapFrame = _G.WorldMapFrame
local QuestMapFrame = _G.QuestMapFrame

----------------------------------------------------------------------------------------
-- Functions
----------------------------------------------------------------------------------------

function Maps:SetupWorldMap()
    if not self.db or self.db.WorldMap ~= true then return end
    if self._worldMapSetupDone then return end
    self._worldMapSetupDone = true

    local coords = CreateFrame("Frame", "RefineUI_WorldMapCoords", WorldMapFrame)
    coords:SetFrameLevel(WorldMapFrame.BorderFrame:GetFrameLevel() + 2)
    coords:SetFrameStrata(WorldMapFrame.BorderFrame:GetFrameStrata())

    coords.PlayerText = coords:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    coords.PlayerText:SetPoint("BOTTOMLEFT", WorldMapFrame.ScrollContainer, "BOTTOM", -40, 20)
    coords.PlayerText:SetJustifyH("LEFT")

    coords.MouseText = coords:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    coords.MouseText:SetJustifyH("LEFT")
    coords.MouseText:SetPoint("BOTTOMLEFT", coords.PlayerText, "TOPLEFT", 0, 5)

    local maxQuest = 35
    local numQuest = CreateFrame("Frame", nil, QuestMapFrame)
    numQuest.text = numQuest:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    numQuest.text:SetPoint("TOP", QuestMapFrame, "TOP", 0, -21)
    numQuest.text:SetJustifyH("LEFT")

    local mapRects, tempVec2D = {}, CreateVector2D(0, 0)
    local function GetPlayerMapPos(mapID)
        tempVec2D.x, tempVec2D.y = UnitPosition("player")
        if not tempVec2D.x then return end

        local mapRect = mapRects[mapID]
        if not mapRect then
            local _, pos1 = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
            local _, pos2 = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(1, 1))
            if not pos1 or not pos2 then return end
            mapRect = {pos1, pos2}
            mapRect[2]:Subtract(mapRect[1])
            mapRects[mapID] = mapRect
        end
        tempVec2D:Subtract(mapRect[1])

        return (tempVec2D.y/mapRect[2].y), (tempVec2D.x/mapRect[2].x)
    end

    local updateInterval = 0.2
    local timeSinceLastUpdate = 0
    local playerName = UnitName("player")
    local boundsText = "|cffff0000Bounds|r"
    local lastPlayerText
    local lastMouseText
    local lastQuestText

    local function SetPlayerText(text)
        if text ~= lastPlayerText then
            coords.PlayerText:SetText(text)
            lastPlayerText = text
        end
    end

    local function SetMouseText(text)
        if text ~= lastMouseText then
            coords.MouseText:SetText(text)
            lastMouseText = text
        end
    end

    local function UpdateQuestCounter()
        if not numQuest or not numQuest.text then return end
        local text = format("%d/%d", select(2, C_QuestLog.GetNumQuestLogEntries()), maxQuest)
        if text ~= lastQuestText then
            numQuest.text:SetText(text)
            lastQuestText = text
        end
    end

    WorldMapFrame:HookScript("OnUpdate", function(_, elapsed)
        timeSinceLastUpdate = timeSinceLastUpdate + elapsed
        if timeSinceLastUpdate < updateInterval then return end
        timeSinceLastUpdate = 0

        local unitMap = C_Map.GetBestMapForUnit("player")
        local x, y = 0, 0

        if unitMap then
            x, y = GetPlayerMapPos(unitMap)
        end

        if x and y and x >= 0 and y >= 0 then
            SetPlayerText(format("%s: %.0f,%.0f", playerName, x * 100, y * 100))
        else
            SetPlayerText(format("%s: %s", playerName, boundsText))
        end

        if WorldMapFrame.ScrollContainer:IsMouseOver() then
            local mouseX, mouseY = WorldMapFrame.ScrollContainer:GetNormalizedCursorPosition()
            if mouseX and mouseY and mouseX >= 0 and mouseY >= 0 then
                SetMouseText(format("Cursor: %.0f,%.0f", mouseX * 100, mouseY * 100))
            else
                SetMouseText("Cursor: " .. boundsText)
            end
        else
            SetMouseText("Cursor: " .. boundsText)
        end
    end)

    WorldMapFrame:HookScript("OnShow", UpdateQuestCounter)
    RefineUI:RegisterEventCallback("QUEST_LOG_UPDATE", UpdateQuestCounter, "Maps:WorldMapQuestCount")
    RefineUI:RegisterEventCallback("PLAYER_ENTERING_WORLD", UpdateQuestCounter, "Maps:WorldMapQuestOnWorldEntry")
    UpdateQuestCounter()
end
