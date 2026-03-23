local AddOnName, RefineUI = ...

----------------------------------------------------------------------------------------
--	Combat Module
--	Consolidates CombatCrosshair, CombatCursor, and CombatTargeting features
----------------------------------------------------------------------------------------
local Combat = RefineUI:RegisterModule("Combat")

-- Lib Globals
local _G = _G
local select = select
local unpack = unpack
local floor = math.floor
local format = string.format
local tonumber = tonumber

-- WoW Globals
local CreateFrame = CreateFrame
local UIParent = UIParent
local GetCursorPosition = GetCursorPosition
local GetCVar = GetCVar
local InCombatLockdown = InCombatLockdown
local UnitExists = UnitExists
local UnitCanAttack = UnitCanAttack
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsFriend = UnitIsFriend
local TargetUnit = TargetUnit
local IsShiftKeyDown = IsShiftKeyDown
local IsControlKeyDown = IsControlKeyDown
local IsAltKeyDown = IsAltKeyDown
local IsMouselooking = IsMouselooking
local MouselookStart = MouselookStart
local MouselookStop = MouselookStop
local ResetCursor = ResetCursor
local WorldFrame = WorldFrame
local C_Timer = C_Timer
local IsInInstance = IsInInstance

-- Locals
local crosshairFrame
local cursorFrame
local cachedUIParentScale
local targetingHooksInstalled = false
local disableRightClickNoticePrinted = false

local CURSOR_UPDATE_JOB_KEY = "Combat:CursorUpdate"

-- Helper: Set deselectOnClick
local function NormalizeCVarBool(value)
    if value == nil then return nil end
    return (value == true or value == 1 or value == "1") and "1" or "0"
end

local function GetDeselectOnClick()
    if C_CVar and C_CVar.GetCVarBool then
        local ok, value = pcall(C_CVar.GetCVarBool, "deselectOnClick")
        if ok and value ~= nil then
            return value and "1" or "0"
        end
    end
    if C_CVar and C_CVar.GetCVar then
        return NormalizeCVarBool(C_CVar.GetCVar("deselectOnClick"))
    end
    if GetCVar then
        return NormalizeCVarBool(GetCVar("deselectOnClick"))
    end
    return nil
end

local function SetDeselectOnClickViaSettings(enable)
    if not Settings then return false end

    -- Blizzard negates this setting (StickyTargeting checkbox), so invert value here.
    local settingValue = not enable

    if Settings.GetSetting then
        local s = Settings.GetSetting("deselectOnClick")
        if s and s.SetValue then
            local ok = pcall(s.SetValue, s, settingValue)
            if ok then return true end
        end
    end

    if Settings.SetValue then
        local ok = pcall(Settings.SetValue, "deselectOnClick", settingValue)
        if ok then return true end

        ok = pcall(Settings.SetValue, Settings, "deselectOnClick", settingValue)
        if ok then return true end
    end

    return false
end

local function SetDeselectOnClick(enable, allowRetry)
    local desired = enable and "1" or "0"

    -- Try settings first; in some builds this succeeds more reliably on edge events.
    SetDeselectOnClickViaSettings(enable)

    -- Enforce desired value directly if setting path didn't stick.
    if GetDeselectOnClick() ~= desired then
        if C_CVar and C_CVar.SetCVar then
            pcall(C_CVar.SetCVar, "deselectOnClick", desired)
        elseif SetCVar then
            pcall(SetCVar, "deselectOnClick", desired)
        end
    end

    -- Edge events can race with other CVar writers; retry one frame later if needed.
    if allowRetry ~= false and C_Timer and C_Timer.After then
        if GetDeselectOnClick() ~= desired then
            C_Timer.After(0, function()
                SetDeselectOnClick(enable, false)
            end)
        end
    end
end

----------------------------------------------------------------------------------------
--	Crosshair Feature
----------------------------------------------------------------------------------------
function Combat:SetupCrosshair()
	if not RefineUI.Config.Combat.CrosshairEnable then return end

	local frame = CreateFrame("Frame", "RefineUI_CombatCrosshair", UIParent)
	frame:SetFrameStrata("DIALOG")
    
    -- Strict API: Use :Size() for pixel perfect scaling
	RefineUI.Size(frame, RefineUI.Config.Combat.CrosshairSize)
    
    -- Strict API: Use :Point() for pixel perfect positioning
	RefineUI.Point(frame, "CENTER", UIParent, "CENTER", RefineUI.Config.Combat.CrosshairOffsetX, RefineUI.Config.Combat.CrosshairOffsetY)
	frame:Hide()

	local texture = frame:CreateTexture(nil, "BACKGROUND")
	texture:SetTexture(RefineUI.Config.Combat.CrosshairTexture)
	texture:SetAllPoints(frame)
	texture:SetVertexColor(1, 1, 1, 0.6)
	
	crosshairFrame = frame
end

----------------------------------------------------------------------------------------
--	Cursor Feature
----------------------------------------------------------------------------------------
local function GetCursorUpdateInterval()
    local config = RefineUI.Config and RefineUI.Config.Combat
    local interval = config and tonumber(config.CursorUpdateInterval)
    if not interval or interval <= 0 then
        return 1 / 30
    end
    return interval
end

local function ShouldDisableCursorInInstances()
    local config = RefineUI.Config and RefineUI.Config.Combat
    return not not (config and config.CursorDisableInInstances)
end

local function IsCursorSuppressedInContext()
    if not cursorFrame then
        return true
    end

    if ShouldDisableCursorInInstances() and IsInInstance then
        local inInstance = IsInInstance()
        if inInstance then
            return true
        end
    end

    return false
end

local function UpdateCursorFramePosition()
    if not cursorFrame or not cursorFrame:IsShown() or IsCursorSuppressedInContext() then
        return
    end

    cachedUIParentScale = cachedUIParentScale or UIParent:GetEffectiveScale()
    local x, y = GetCursorPosition()
    cursorFrame:ClearAllPoints()
    RefineUI.Point(cursorFrame, "CENTER", UIParent, "BOTTOMLEFT", x / cachedUIParentScale, y / cachedUIParentScale)
end

local function SetCombatCursorActive(active)
    if not cursorFrame then
        return
    end

    local shouldShow = active == true and not IsCursorSuppressedInContext()
    cursorFrame:SetShown(shouldShow)

    if RefineUI.SetUpdateJobEnabled and RefineUI.IsUpdateJobRegistered and RefineUI:IsUpdateJobRegistered(CURSOR_UPDATE_JOB_KEY) then
        RefineUI:SetUpdateJobEnabled(CURSOR_UPDATE_JOB_KEY, shouldShow, true)
        if shouldShow and RefineUI.RunUpdateJobNow then
            RefineUI:RunUpdateJobNow(CURSOR_UPDATE_JOB_KEY)
        end
    end
end

function Combat:SetupCursor()
	if not RefineUI.Config.Combat.CursorEnable then return end

	local frame = CreateFrame("Frame", "RefineUI_CombatCursor", UIParent)
	frame:SetFrameStrata("DIALOG")
    
    -- Strict API
	RefineUI.Size(frame, RefineUI.Config.Combat.CursorSize)
	RefineUI.Point(frame, "CENTER", UIParent, "BOTTOMLEFT", 0, 0)
	frame:Hide()

	local texture = frame:CreateTexture(nil, "BACKGROUND")
	texture:SetTexture(RefineUI.Config.Combat.CursorTexture)
	texture:SetAllPoints(frame)
	texture:SetVertexColor(1, 1, 1, 0.9)
	frame.texture = texture

    -- Update cached scale when UI scale changes
    RefineUI:RegisterEventCallback("UI_SCALE_CHANGED", function()
        cachedUIParentScale = UIParent:GetEffectiveScale()
    end, "Combat:ScaleChanged")

    if RefineUI.RegisterUpdateJob then
        RefineUI:RegisterUpdateJob(CURSOR_UPDATE_JOB_KEY, GetCursorUpdateInterval(), function()
            UpdateCursorFramePosition()
        end, {
            enabled = false,
            combatOnly = true,
            predicate = function()
                return cursorFrame and cursorFrame:IsShown() and not IsCursorSuppressedInContext()
            end,
        })
    end

	cursorFrame = frame
end

----------------------------------------------------------------------------------------
--	Combat Targeting Features
----------------------------------------------------------------------------------------

-- Helper: Check if unit can be attacked
local function CanAttack(unit)
	local isFriendly = UnitIsFriend and UnitIsFriend("player", unit)
	return UnitCanAttack("player", unit) and not UnitIsDeadOrGhost(unit) and not isFriendly
end



function Combat:SetupTargeting()
    local useSticky = RefineUI.Config.Combat.StickyTargeting
    -- New setting name
    local useDisableRightClick = RefineUI.Config.Combat.DisableRightClickInteraction
    local useAutoTarget = RefineUI.Config.Combat.AutoTargetOnClick

    if not (useSticky or useDisableRightClick or useAutoTarget) then return end

    -- Sticky Targeting (CVar toggle)
    if useSticky then
        RefineUI:RegisterEventCallback("PLAYER_REGEN_DISABLED", function()
            SetDeselectOnClick(false) 
        end, "Combat:TargetingStart")

        RefineUI:RegisterEventCallback("PLAYER_REGEN_ENABLED", function()
            SetDeselectOnClick(true)
        end, "Combat:TargetingEnd")

        -- Apply current state immediately
        if InCombatLockdown() then
            SetDeselectOnClick(false)
        else
            SetDeselectOnClick(true)
        end
    end

    if not (useDisableRightClick or useAutoTarget) then
        return
    end

    if useDisableRightClick and not disableRightClickNoticePrinted then
        disableRightClickNoticePrinted = true
        self:Print("DisableRightClickInteraction now uses taint-safe fallback behavior.")
    end

    if targetingHooksInstalled then
        return
    end
    targetingHooksInstalled = true

    -- Taint-safe fallback: never replace WorldFrame scripts.
    RefineUI:HookScriptOnce("Combat:WorldFrame:OnMouseDown", WorldFrame, "OnMouseDown", function(_, button)
        if button ~= "RightButton" then return end
        if not useDisableRightClick then return end
        if InCombatLockdown() then return end
        if not IsMouselooking() then
            MouselookStart()
        end
    end)

    RefineUI:HookScriptOnce("Combat:WorldFrame:OnMouseUp", WorldFrame, "OnMouseUp", function(_, button)
        if button == "RightButton" then
            if useDisableRightClick and not InCombatLockdown() and IsMouselooking() then
                MouselookStop()
            end
            return
        end

        if not useAutoTarget then return end
        if button ~= "LeftButton" then return end
        if not InCombatLockdown() then return end
        if IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown() then return end

        local MouseIsOverWorld = rawget(_G, "MouseIsOverWorld")
        if not (MouseIsOverWorld and MouseIsOverWorld()) then
            return
        end

        local targetUnit = "mouseover"
        if UnitExists(targetUnit) and CanAttack(targetUnit) then
            TargetUnit(targetUnit)
        end
    end)
end

----------------------------------------------------------------------------------------
--	Initialization
----------------------------------------------------------------------------------------
function Combat:OnEnable()
	self:SetupCrosshair()
	self:SetupCursor()
    self:SetupTargeting()

    -- Centralized Combat State Handling
    RefineUI:RegisterEventCallback("PLAYER_REGEN_DISABLED", function()
        if crosshairFrame then crosshairFrame:Show() end
        SetCombatCursorActive(true)
    end, "Combat:Enter")

    RefineUI:RegisterEventCallback("PLAYER_REGEN_ENABLED", function()
        if crosshairFrame then crosshairFrame:Hide() end
        SetCombatCursorActive(false)
    end, "Combat:Leave")

    RefineUI:RegisterEventCallback("PLAYER_ENTERING_WORLD", function()
        cachedUIParentScale = UIParent:GetEffectiveScale()
        if InCombatLockdown() then
            SetCombatCursorActive(true)
        else
            SetCombatCursorActive(false)
        end
    end, "Combat:WorldState")

    if InCombatLockdown() then
        if crosshairFrame then crosshairFrame:Show() end
        SetCombatCursorActive(true)
    else
        if crosshairFrame then crosshairFrame:Hide() end
        SetCombatCursorActive(false)
    end
end
