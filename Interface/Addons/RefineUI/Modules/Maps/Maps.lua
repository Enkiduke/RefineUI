----------------------------------------------------------------------------------------
-- Maps for RefineUI
-- Description: Core module for Minmap and WorldMap management.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Maps = RefineUI:RegisterModule("Maps", "Maps")

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local _G = _G
local pairs, ipairs, unpack, select = pairs, ipairs, unpack, select
local C_Map = C_Map
local CreateVector2D = CreateVector2D

----------------------------------------------------------------------------------------
-- Shared
----------------------------------------------------------------------------------------

local mapWorldRects = {}
local MAP_TOP_LEFT, MAP_BOTTOM_RIGHT = CreateVector2D(0, 0), CreateVector2D(1, 1)

-- Converts UnitPosition's returns to normalized map coordinates without allocating.
-- Returns nothing when the position is on a different continent than the map.
function Maps:WorldToMapPosition(mapID, worldX, worldY, _, instanceID)
    if not mapID or not worldX then return end

    local rect = mapWorldRects[mapID]
    if rect == nil then
        local continentID, topLeft = C_Map.GetWorldPosFromMapPos(mapID, MAP_TOP_LEFT)
        local _, bottomRight = C_Map.GetWorldPosFromMapPos(mapID, MAP_BOTTOM_RIGHT)
        rect = topLeft and bottomRight
            and { topLeft.x, topLeft.y, bottomRight.x - topLeft.x, bottomRight.y - topLeft.y, continentID }
            or false
        mapWorldRects[mapID] = rect
    end
    if not rect or instanceID ~= rect[5] then return end

    return (worldY - rect[2]) / rect[4], (worldX - rect[1]) / rect[3]
end

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------

function Maps:OnInitialize()
    self.db = RefineUI.DB and RefineUI.DB.Maps or RefineUI.Config.Maps
    self.positions = RefineUI.DB and RefineUI.DB.Positions or RefineUI.Positions
end

function Maps:OnEnable()
    if self.SetupWaypoint then self:SetupWaypoint() end
    if self.SetupMinimap then self:SetupMinimap() end
    if self.SetupPortals then self:SetupPortals() end
    if self.SetupWorldMap then self:SetupWorldMap() end
    if self.SetupButtonCollect then self:SetupButtonCollect() end
    if self.SetupWorldQuestList then self:SetupWorldQuestList() end
end
