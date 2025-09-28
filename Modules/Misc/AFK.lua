local R, C, L = unpack(RefineUI)

-- Bail early if AFK spin is disabled
if not (C and C.misc and C.misc.afk) then return end

----------------------------------------------------------------------------------------
-- AFK camera spin (refined)
-- - Smooth zoom via a single ticker (no throwaway OnUpdate frames)
-- - Stops on combat/cinematics/world changes
-- - Uses UI alpha instead of Hide/Show to avoid combat taint
----------------------------------------------------------------------------------------

-- Tunables (override in your config if you like)
local TARGET_ZOOM   = C.misc.afkZoom or 4        -- how close to zoom while AFK
local ZOOM_STEP     = C.misc.afkZoomStep or 0.2  -- zoom delta per tick
local ZOOM_TICK     = C.misc.afkZoomTick or 0.02 -- seconds between zoom ticks
local ROT_SPEED     = C.misc.afkSpinSpeed or 0.1 -- view rotate speed
local HIDE_UI       = (C.misc.afkHideUI ~= false) -- fade UI while AFK (default true)
local USE_EMOTE     = (C.misc.afkEmote ~= false)  -- do a /sit emote on start

-- Locals (bind once)
local abs              = math.abs
local GetCameraZoom    = GetCameraZoom
local CameraZoomIn     = CameraZoomIn
local CameraZoomOut    = CameraZoomOut
local UnitIsAFK        = UnitIsAFK
local InCombatLockdown = InCombatLockdown
local UnitOnTaxi       = UnitOnTaxi
local MoveViewRightStart, MoveViewRightStop = MoveViewRightStart, MoveViewRightStop

-- State
local spinning, originalZoom, zoomTicker

local function CancelZoom()
    if zoomTicker then zoomTicker:Cancel(); zoomTicker = nil end
end

local function ZoomTo(target)
    CancelZoom()
    zoomTicker = C_Timer.NewTicker(ZOOM_TICK, function()
        local current = GetCameraZoom()
        local diff = target - current
        if abs(diff) <= 0.05 then
            CancelZoom()
            return
        end
        if diff < 0 then
            CameraZoomIn( math.min(ZOOM_STEP, -diff) )
        else
            CameraZoomOut( math.min(ZOOM_STEP,  diff) )
        end
    end)
end

local function SafeFadeUI(alpha)
    if not HIDE_UI then return end
    -- alpha changes on UIParent are safe in combat; Hide/Show is not.
    UIParent:SetAlpha(alpha)
end

local function CanStartSpin()
    if InCombatLockdown() then return false end
    if UnitOnTaxi("player") then return false end
    if CinematicFrame and CinematicFrame:IsShown() then return false end
    if MovieFrame and MovieFrame:IsShown() then return false end
    return true
end

local function SpinStart()
    if spinning or not CanStartSpin() then return end
    spinning = true
    originalZoom = GetCameraZoom()

    MoveViewRightStart(ROT_SPEED)
    SafeFadeUI(0)                 -- fade UI out instead of Hide()
    ZoomTo(TARGET_ZOOM)
    if USE_EMOTE then DoEmote("SIT") end
end

local function SpinStop()
    if not spinning then
        -- if something stopped us unexpectedly, still ensure UI/zoom recovery
        SafeFadeUI(1)
        CancelZoom()
        return
    end
    spinning = false

    MoveViewRightStop()
    SafeFadeUI(1)
    ZoomTo(originalZoom or TARGET_ZOOM)
end

-- Event driver
local SpinCam = CreateFrame("Frame", "RefineUI_AFKSpinDriver")
SpinCam:RegisterEvent("PLAYER_FLAGS_CHANGED")   -- AFK flag toggles
SpinCam:RegisterEvent("PLAYER_REGEN_DISABLED")  -- enter combat
SpinCam:RegisterEvent("PLAYER_LEAVING_WORLD")   -- zoning/logout
SpinCam:RegisterEvent("CINEMATIC_START")
SpinCam:RegisterEvent("PLAY_MOVIE")

SpinCam:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_FLAGS_CHANGED" then
        if arg1 ~= "player" then return end
        if UnitIsAFK("player") then
            SpinStart()
        else
            SpinStop()
        end
    else
        -- World change, combat, or cinematic: always stop & restore
        SpinStop()
    end
end)
