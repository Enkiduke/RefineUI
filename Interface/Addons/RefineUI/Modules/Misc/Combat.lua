local AddOnName, RefineUI = ...

----------------------------------------------------------------------------------------
--	Combat Module
--	Consolidates CombatCrosshair, CombatCursor, and CombatTargeting features
----------------------------------------------------------------------------------------
local Combat = RefineUI:RegisterModule("Combat", function(cfg)
    local combat = cfg.Combat
    if type(combat) ~= "table" then
        return true
    end
    return combat.CrosshairEnable ~= false
        or combat.CursorEnable ~= false
        or combat.StickyTargeting == true
        or combat.DisableRightClickInteraction == true
end)

-- WoW Globals
local CreateFrame = CreateFrame
local UIParent = UIParent
local GetCursorPosition = GetCursorPosition
local InCombatLockdown = InCombatLockdown
local IsInInstance = IsInInstance
local IsMouselooking = IsMouselooking
local MouselookStart = MouselookStart
local MouselookStop = MouselookStop
local WorldFrame = WorldFrame
local C_CVar = C_CVar

-- Locals
local crosshairFrame
local cursorFrame
local cursorScale = 1
local useStickyTargeting = false

local CURSOR_UPDATE_JOB_KEY = "Combat:CursorUpdate"

-- Blizzard's Sticky Targeting checkbox is a negated CVar checkbox on "deselectOnClick".
local function SetDeselectOnClick(enable)
    if C_CVar.GetCVarBool("deselectOnClick") ~= enable then
        C_CVar.SetCVar("deselectOnClick", enable and "1" or "0")
    end
end

----------------------------------------------------------------------------------------
--	Crosshair Feature
----------------------------------------------------------------------------------------
function Combat:SetupCrosshair()
    local config = RefineUI.Config.Combat
    if not config.CrosshairEnable then return end

    local frame = CreateFrame("Frame", "RefineUI_CombatCrosshair", UIParent)
    frame:SetFrameStrata("DIALOG")
    RefineUI.Size(frame, config.CrosshairSize)
    RefineUI.Point(frame, "CENTER", UIParent, "CENTER", config.CrosshairOffsetX, config.CrosshairOffsetY)
    frame:Hide()

    local texture = frame:CreateTexture(nil, "BACKGROUND")
    texture:SetTexture(config.CrosshairTexture)
    texture:SetAllPoints(frame)
    texture:SetVertexColor(1, 1, 1, 0.6)

    crosshairFrame = frame
end

----------------------------------------------------------------------------------------
--	Cursor Feature
----------------------------------------------------------------------------------------
local function UpdateCursorFramePosition()
    local x, y = GetCursorPosition()
    cursorFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / cursorScale, y / cursorScale)
end

local function SetCombatCursorActive(active)
    if not cursorFrame then
        return
    end

    -- Instance state only changes across loading screens (PLAYER_ENTERING_WORLD).
    local shouldShow = active and not (RefineUI.Config.Combat.CursorDisableInInstances and IsInInstance())
    cursorFrame:SetShown(shouldShow)
    RefineUI:SetUpdateJobEnabled(CURSOR_UPDATE_JOB_KEY, shouldShow, true)

    if shouldShow then
        cursorScale = UIParent:GetEffectiveScale()
        UpdateCursorFramePosition()
    end
end

function Combat:SetupCursor()
    local config = RefineUI.Config.Combat
    if not config.CursorEnable then return end

    local frame = CreateFrame("Frame", "RefineUI_CombatCursor", UIParent)
    frame:SetFrameStrata("DIALOG")
    RefineUI.Size(frame, config.CursorSize)
    frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", 0, 0)
    frame:Hide()

    local texture = frame:CreateTexture(nil, "BACKGROUND")
    texture:SetTexture(config.CursorTexture)
    texture:SetAllPoints(frame)
    texture:SetVertexColor(1, 1, 1, 0.9)
    frame.texture = texture

    cursorFrame = frame

    RefineUI:RegisterUpdateJob(CURSOR_UPDATE_JOB_KEY, config.CursorUpdateInterval, UpdateCursorFramePosition, {
        enabled = false,
        combatOnly = true,
    })
end

----------------------------------------------------------------------------------------
--	Combat Targeting Features
----------------------------------------------------------------------------------------
function Combat:SetupTargeting()
    local config = RefineUI.Config.Combat

    useStickyTargeting = config.StickyTargeting == true
    if useStickyTargeting then
        SetDeselectOnClick(not InCombatLockdown())
    end

    if not config.DisableRightClickInteraction then return end

    -- Taint-safe: observe WorldFrame clicks, never replace its scripts.
    RefineUI:HookScriptOnce("Combat:WorldFrame:OnMouseDown", WorldFrame, "OnMouseDown", function(_, button)
        if button == "RightButton" and not InCombatLockdown() and not IsMouselooking() then
            MouselookStart()
        end
    end)

    RefineUI:HookScriptOnce("Combat:WorldFrame:OnMouseUp", WorldFrame, "OnMouseUp", function(_, button)
        if button == "RightButton" and not InCombatLockdown() and IsMouselooking() then
            MouselookStop()
        end
    end)
end

----------------------------------------------------------------------------------------
--	Initialization
----------------------------------------------------------------------------------------
local function SetCombatVisualsActive(active)
    if crosshairFrame then crosshairFrame:SetShown(active) end
    SetCombatCursorActive(active)
end

function Combat:OnEnable()
    self:SetupCrosshair()
    self:SetupCursor()
    self:SetupTargeting()

    RefineUI:RegisterEventCallback("PLAYER_REGEN_DISABLED", function()
        if useStickyTargeting then SetDeselectOnClick(false) end
        SetCombatVisualsActive(true)
    end, "Combat:Enter")

    RefineUI:RegisterEventCallback("PLAYER_REGEN_ENABLED", function()
        if useStickyTargeting then SetDeselectOnClick(true) end
        SetCombatVisualsActive(false)
    end, "Combat:Leave")

    if cursorFrame then
        RefineUI:RegisterEventCallback("PLAYER_ENTERING_WORLD", function()
            SetCombatCursorActive(InCombatLockdown())
        end, "Combat:WorldState")
    end

    SetCombatVisualsActive(InCombatLockdown())
end
