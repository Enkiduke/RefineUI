----------------------------------------------------------------------------------------
-- AFK Module
-- Description: Simple AFK module that spins and zooms the camera.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local AFK = RefineUI:RegisterModule("AFK")
local Config = RefineUI.Config

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local GetCameraZoom = GetCameraZoom
local CameraZoomIn = CameraZoomIn
local CameraZoomOut = CameraZoomOut
local MoveViewRightStart = MoveViewRightStart
local MoveViewRightStop = MoveViewRightStop
local UnitIsAFK = UnitIsAFK
local InCombatLockdown = InCombatLockdown
local DoEmote = DoEmote
local UIParent = _G.UIParent

----------------------------------------------------------------------------------------
-- Locals
----------------------------------------------------------------------------------------
local originalZoom
local spinning = false
local zoomFrame

----------------------------------------------------------------------------------------
-- Core Functions
----------------------------------------------------------------------------------------
local function ZoomIn()
    if zoomFrame then zoomFrame:SetScript("OnUpdate", nil) end
    if not zoomFrame then zoomFrame = CreateFrame("Frame") end

    originalZoom = GetCameraZoom()
    local targetZoom = 4
    local zoomSpeed = 0.1

    zoomFrame:SetScript("OnUpdate", function(self)
        local currentZoom = GetCameraZoom()
        if currentZoom > targetZoom then
            CameraZoomIn(zoomSpeed)
        else
            self:SetScript("OnUpdate", nil)
        end
    end)
end

local function ZoomOut()
    if zoomFrame then zoomFrame:SetScript("OnUpdate", nil) end
    if not zoomFrame then zoomFrame = CreateFrame("Frame") end

    if originalZoom then
        zoomFrame:SetScript("OnUpdate", function(self)
            local currentZoom = GetCameraZoom()
            if currentZoom < originalZoom then
                CameraZoomOut(0.4)
            else
                self:SetScript("OnUpdate", nil)
            end
        end)
    end
end

function AFK:SpinStart()
    if spinning then return end
    spinning = true
    MoveViewRightStart(0.1)
    UIParent:Hide()
    ZoomIn()
    DoEmote("SIT")
end

function AFK:SpinStop()
    if not spinning then return end
    spinning = false
    MoveViewRightStop()
    if InCombatLockdown() then return end
    UIParent:Show()
    ZoomOut()
end

----------------------------------------------------------------------------------------
-- Event Handling
----------------------------------------------------------------------------------------
function AFK:OnEvent(event)
    if event == "PLAYER_LEAVING_WORLD" then
        self:SpinStop()
    else
        if UnitIsAFK("player") and not InCombatLockdown() then
            self:SpinStart()
        else
            self:SpinStop()
        end
    end
end

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------
function AFK:OnEnable()
    if not Config.AFK.Enable then 
        return 
    end

    local function EventHandler(event, ...)
        AFK:OnEvent(event, ...)
    end

    RefineUI:RegisterEventCallback("PLAYER_FLAGS_CHANGED", EventHandler, "AFK:AFK:OnEvent")
    RefineUI:RegisterEventCallback("PLAYER_LEAVING_WORLD", EventHandler, "AFK:AFK:OnEvent")
end
