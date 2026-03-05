----------------------------------------------------------------------------------------
-- Maps for RefineUI
-- Description: Core module for Minmap and WorldMap management.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Maps = RefineUI:RegisterModule("Maps")

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local _G = _G
local pairs, ipairs, unpack, select = pairs, ipairs, unpack, select

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------

function Maps:OnInitialize()
    self.db = RefineUI.DB and RefineUI.DB.Maps or RefineUI.Config.Maps
    self.positions = RefineUI.DB and RefineUI.DB.Positions or RefineUI.Positions
end

function Maps:OnEnable()
    if self.SetupMinimap then self:SetupMinimap() end
    if self.SetupPortals then self:SetupPortals() end
    if self.SetupWorldMap then self:SetupWorldMap() end
    if self.SetupButtonCollect then self:SetupButtonCollect() end
    if self.SetupWorldQuestList then self:SetupWorldQuestList() end
end
