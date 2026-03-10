----------------------------------------------------------------------------------------
-- RefineUI EditMode Handling
-- Description: Manages the WoW Edit Mode system to ensure our frames stay put.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Module = RefineUI:RegisterModule("EditMode")

local LibEditModeOverride = LibStub("LibEditModeOverride-1.0", true)
RefineUI.LibEditMode = LibStub("LibEditMode", true)
local C_AddOns = C_AddOns
local C_Timer = C_Timer
local ReloadUI = ReloadUI

if not LibEditModeOverride or not RefineUI.LibEditMode then
    print("|cffff0000RefineUI Error:|r EditMode libraries not found. Edit Mode functionality will be disabled.")
    return
end

local INSTALL_LAYOUT_NAME = "RefineUI"
local READY_WAIT_INTERVAL = 0.5
local READY_WAIT_ATTEMPTS = 60

-- Stored EditMode slider values for Damage Meter.
-- Display equivalents: width=314, height=294, bar=15, padding=5, bg=0, text=100.
local DAMAGE_METER_SETTING_FRAME_WIDTH = 14
local DAMAGE_METER_SETTING_FRAME_HEIGHT = 174
local DAMAGE_METER_SETTING_BAR_HEIGHT = 14
local DAMAGE_METER_SETTING_PADDING = 4
local DAMAGE_METER_SETTING_BACKGROUND_OPACITY = 0
local DAMAGE_METER_SETTING_TEXT_SIZE = 7
local TIMER_BARS_SETTING_SIZE = 2 -- Blizzard Edit Mode "Duration Bars" scale percentage

local function GetPosition(name)
    if RefineUI.Positions and RefineUI.Positions[name] then
        return unpack(RefineUI.Positions[name])
    end
end

local function GetSystemFrame(systemID)
    if not EditModeManagerFrame or not EditModeManagerFrame.registeredSystemFrames then return end
    for _, frame in ipairs(EditModeManagerFrame.registeredSystemFrames) do
        if frame.system == systemID then
            return frame
        end
    end
end

local function GetSystemFrameByIndex(systemID, systemIndex)
    if not EditModeManagerFrame or not EditModeManagerFrame.registeredSystemFrames then return end
    for _, frame in ipairs(EditModeManagerFrame.registeredSystemFrames) do
        if frame.system == systemID and frame.systemIndex == systemIndex then
            return frame
        end
    end
end

local ACTION_BAR_NAMES_BY_INDEX = {
    [2] = "MultiBarBottomLeft",
    [3] = "MultiBarBottomRight",
    [4] = "MultiBarRight",
    [5] = "MultiBarLeft",
    [6] = "MultiBar5",
    [7] = "MultiBar6",
    [8] = "MultiBar7",
}

local function GetActionBarFrameByIndex(index)
    local frameName = ACTION_BAR_NAMES_BY_INDEX[index]
    if frameName and _G[frameName] then
        return _G[frameName]
    end

    local actionBarSystem = (Enum.EditModeSystem and Enum.EditModeSystem.ActionBar) or 1
    return GetSystemFrameByIndex(actionBarSystem, index)
end

local function ResolveRelativeFrame(relativeTo)
    if type(relativeTo) == "string" then
        return _G[relativeTo] or UIParent
    end
    return relativeTo or UIParent
end

local function CallOverride(method, ...)
    local fn = LibEditModeOverride and LibEditModeOverride[method]
    if type(fn) ~= "function" then
        return false, "missing_method:" .. tostring(method)
    end
    return pcall(fn, LibEditModeOverride, ...)
end

local function TrySetFrameSetting(frame, setting, value)
    if not frame then
        return true
    end
    local ok, err = CallOverride("SetFrameSetting", frame, setting, value)
    if not ok then
        return false, err
    end
    return true
end

local function TryReanchorFrame(frame, point, relativeTo, relativePoint, x, y)
    if not frame then
        return true
    end
    local ok, err = CallOverride("ReanchorFrame", frame, point, relativeTo, relativePoint, x, y)
    if not ok then
        return false, err
    end
    return true
end

local function TrySetGlobalSetting(setting, value)
    local ok, err = CallOverride("SetGlobalSetting", setting, value)
    if not ok then
        return false, err
    end
    return true
end

function Module:OnInitialize()
    -- Nothing to do early
end

function Module:OnEnable()
    -- During transient install/bootstrap states, avoid mutating Edit Mode.
    local db = RefineUI.DB
    if not db or db.InstallState ~= "ready" then
        return
    end

    -- Register Custom Frames with LibEditMode if they exist
    self:RegisterCustomFrames()

    self:HookExitEditMode()
end

function Module:RegisterCustomFrames()
    -- Helper to register RefineUI frames that support EditMode
    local customFrames = {
        ["RefineUI_AutoButton"] = "Auto Button",
        ["RefineUI_GhostFrame"] = "Ghost Frame",
        ["RefineUI_PlayerCastBarMover"] = "Player Cast Bar",
    }
    
    for frameName, humanName in pairs(customFrames) do
        -- Force create known movers if they don't exist yet (Load Order fix)
        if not _G[frameName] then
            if frameName:find("CastBarMover") then
                local f = CreateFrame("Frame", frameName, UIParent)
                f:SetSize(220, 20)
                f:SetFrameStrata("DIALOG")
            end
        end

        local frame = _G[frameName]
        if frame then
            local p, r, rp, x, y = GetPosition(frameName)
            if p then
                -- FORCE APPLY POSITION (Fix for invisible movers)
                frame:ClearAllPoints()
                local relativeTo = (type(r) == "string" and _G[r]) or r or UIParent
                frame:SetPoint(p, relativeTo, rp, x, y)
                
                local default = { point = p, x = x, y = y }
                RefineUI.LibEditMode:AddFrame(frame, function() end, default, humanName)
            end
        end
    end
end

function Module:ConfigureRefineUILayout()
    -- Enforce settings for the "RefineUI" layout
    local readyOk, isReady = CallOverride("IsReady")
    if not readyOk then
        return false, isReady
    end
    if not isReady then
        return false, "editmode_not_ready"
    end
    
    -- 1. Apply System Frame Positions
    for name, posTable in pairs(RefineUI.Positions) do
        -- Damage Meter must be anchored through the EditMode system frame, not a session child window.
        if name ~= "DamageMeterSessionWindow1" then
            local frame = _G[name]
            if frame then
                 -- Deep copy posTable so we don't modify the config itself
                 local point, relativeTo, relativePoint, x, y = unpack(posTable)
                 relativeTo = ResolveRelativeFrame(relativeTo)
                 
                 if frame.system or frame.systemIndex then
                     -- EditMode System Frame
                     local ok, err = TryReanchorFrame(frame, point, relativeTo, relativePoint, x, y)
                     if not ok then
                         return false, err
                     end
                 else
                     -- Custom Frame or Non-System Frame (RefineUI Mover)
                     frame:ClearAllPoints()
                     frame:SetPoint(point, relativeTo, relativePoint, x, y)
                 end
            end
        end
    end

    -- Explicit Damage Meter system anchor (supports either Positions.DamageMeter or legacy Positions.DamageMeterSessionWindow1).
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.LoadAddOn and not C_AddOns.IsAddOnLoaded("Blizzard_DamageMeter") then
        C_AddOns.LoadAddOn("Blizzard_DamageMeter")
    end
    local damageMeterPos = RefineUI.Positions.DamageMeter or RefineUI.Positions.DamageMeterSessionWindow1
    local damageMeterSystem = GetSystemFrame(Enum.EditModeSystem.DamageMeter)
    if damageMeterPos and damageMeterSystem then
        local point, relativeTo, relativePoint, x, y = unpack(damageMeterPos)
        relativeTo = ResolveRelativeFrame(relativeTo)
        local ok, err = TryReanchorFrame(damageMeterSystem, point, relativeTo, relativePoint, x, y)
        if not ok then
            return false, err
        end
    end

    -- 2. Specific Settings
    local activeOk, activeLayout = CallOverride("GetActiveLayout")
    if not activeOk then
        return false, activeLayout
    end
    if activeLayout == INSTALL_LAYOUT_NAME then
        -- Enable Blizzard Duration Bars (MirrorTimerContainer) by default for the RefineUI layout.
        if Enum.EditModeAccountSetting and Enum.EditModeAccountSetting.ShowTimerBars then
            local ok, err = TrySetGlobalSetting(Enum.EditModeAccountSetting.ShowTimerBars, 1)
            if not ok then
                return false, err
            end
        end

        -- Hide MainMenuBar Art & Scrolling
        if MainActionBar then
            local ok, err = TrySetFrameSetting(MainActionBar, Enum.EditModeActionBarSetting.HideBarArt, 1)
            if not ok then return false, err end
            ok, err = TrySetFrameSetting(MainActionBar, Enum.EditModeActionBarSetting.HideBarScrolling, 1)
            if not ok then return false, err end
            ok, err = TrySetFrameSetting(MainActionBar, Enum.EditModeActionBarSetting.AlwaysShowButtons, 0)
            if not ok then return false, err end
            ok, err = TrySetFrameSetting(MainActionBar, Enum.EditModeActionBarSetting.IconPadding, 4)
            if not ok then return false, err end
        end
        
        -- Action Bars 2-5 baseline settings
        for _, bar in ipairs({MultiBarBottomLeft, MultiBarBottomRight, MultiBarRight, MultiBarLeft}) do
            if bar then
                local ok, err = TrySetFrameSetting(bar, Enum.EditModeActionBarSetting.AlwaysShowButtons, 0)
                if not ok then return false, err end
                ok, err = TrySetFrameSetting(bar, Enum.EditModeActionBarSetting.IconPadding, 4)
                if not ok then return false, err end
            end
        end

        -- Keep Action Bars 2-4 visible by default.
        for _, bar in ipairs({MultiBarBottomLeft, MultiBarBottomRight, MultiBarRight}) do
            if bar then
                local ok, err = TrySetFrameSetting(bar, Enum.EditModeActionBarSetting.VisibleSetting, Enum.ActionBarVisibleSetting.Always)
                if not ok then return false, err end
            end
        end

        -- Action Bars 3, 4, and 5 default to 10 icons in 2 rows.
        local horizontalOrientation = (Enum.ActionBarOrientation and Enum.ActionBarOrientation.Horizontal) or 0
        for _, bar in ipairs({MultiBarBottomRight, MultiBarRight, MultiBarLeft}) do
            if bar then
                local ok, err = TrySetFrameSetting(bar, Enum.EditModeActionBarSetting.Orientation, horizontalOrientation)
                if not ok then return false, err end
                ok, err = TrySetFrameSetting(bar, Enum.EditModeActionBarSetting.NumRows, 2)
                if not ok then return false, err end
                ok, err = TrySetFrameSetting(bar, Enum.EditModeActionBarSetting.NumIcons, 10)
                if not ok then return false, err end
            end
        end
        
        -- Hide Action Bars 5/6/7/8 (MultiBarLeft, MultiBar5/6/7) by default.
        -- Use system-index lookup so this still works when globals are not ready yet.
        for _, barIndex in ipairs({5, 6, 7, 8}) do
            local bar = GetActionBarFrameByIndex(barIndex)
            if bar then
                local ok, err = TrySetFrameSetting(bar, Enum.EditModeActionBarSetting.VisibleSetting, Enum.ActionBarVisibleSetting.Hidden)
                if not ok then return false, err end
            end
        end
        
        -- Stance Bar Padding
        if StanceBar then
            local ok, err = TrySetFrameSetting(StanceBar, Enum.EditModeActionBarSetting.IconPadding, 4)
            if not ok then return false, err end
        end

        -- Pet Bar Padding
        if PetActionBar then
            local ok, err = TrySetFrameSetting(PetActionBar, Enum.EditModeActionBarSetting.IconPadding, 4)
            if not ok then return false, err end
        end

        -- Force Raid-Style Party Frames
        if PartyFrame then
            local ok, err = TrySetFrameSetting(PartyFrame, Enum.EditModeUnitFrameSetting.UseRaidStylePartyFrames, 1)
            if not ok then return false, err end
            ok, err = TrySetFrameSetting(PartyFrame, Enum.EditModeUnitFrameSetting.SortPlayersBy, Enum.SortPlayersBy.Role)
            if not ok then return false, err end
            ok, err = TrySetFrameSetting(PartyFrame, Enum.EditModeUnitFrameSetting.FrameWidth, 72)
            if not ok then return false, err end
            ok, err = TrySetFrameSetting(PartyFrame, Enum.EditModeUnitFrameSetting.FrameHeight, 28)
            if not ok then return false, err end
            ok, err = TrySetFrameSetting(PartyFrame, Enum.EditModeUnitFrameSetting.AuraOrganizationType, Enum.RaidAuraOrganizationType.BuffsRightDebuffsLeft)
            if not ok then return false, err end
        end
        
        -- Set BuffFrame settings
        if BuffFrame then
            local ok, err = TrySetFrameSetting(BuffFrame, Enum.EditModeAuraFrameSetting.IconSize, 10)
            if not ok then return false, err end
            ok, err = TrySetFrameSetting(BuffFrame, Enum.EditModeAuraFrameSetting.IconLimitBuffFrame, 12)
            if not ok then return false, err end
            ok, err = TrySetFrameSetting(BuffFrame, Enum.EditModeAuraFrameSetting.IconPadding, 10)
            if not ok then return false, err end
        end
        
        -- Set DebuffFrame settings
        if DebuffFrame then
            local ok, err = TrySetFrameSetting(DebuffFrame, Enum.EditModeAuraFrameSetting.IconWrap, Enum.AuraFrameIconWrap.Up)
            if not ok then return false, err end
            ok, err = TrySetFrameSetting(DebuffFrame, Enum.EditModeAuraFrameSetting.IconDirection, Enum.AuraFrameIconDirection.Right)
            if not ok then return false, err end
            ok, err = TrySetFrameSetting(DebuffFrame, Enum.EditModeAuraFrameSetting.IconSize, 5)
            if not ok then return false, err end
            ok, err = TrySetFrameSetting(DebuffFrame, Enum.EditModeAuraFrameSetting.IconLimitDebuffFrame, 5)
            if not ok then return false, err end
            ok, err = TrySetFrameSetting(DebuffFrame, Enum.EditModeAuraFrameSetting.IconPadding, 8)
            if not ok then return false, err end
        end

        -- Set MicroMenu Size
        local microMenu = GetSystemFrame(Enum.EditModeSystem.MicroMenu)
        if microMenu then
            local ok, err = TrySetFrameSetting(microMenu, Enum.EditModeMicroMenuSetting.Size, 9)
            if not ok then return false, err end
        end

        -- Damage Meter defaults
        local damageMeter = GetSystemFrame(Enum.EditModeSystem.DamageMeter)
        if damageMeter and Enum.EditModeDamageMeterSetting then
            local ok, err = TrySetFrameSetting(damageMeter, Enum.EditModeDamageMeterSetting.FrameWidth, DAMAGE_METER_SETTING_FRAME_WIDTH)
            if not ok then return false, err end
            ok, err = TrySetFrameSetting(damageMeter, Enum.EditModeDamageMeterSetting.FrameHeight, DAMAGE_METER_SETTING_FRAME_HEIGHT)
            if not ok then return false, err end
            ok, err = TrySetFrameSetting(damageMeter, Enum.EditModeDamageMeterSetting.BarHeight, DAMAGE_METER_SETTING_BAR_HEIGHT)
            if not ok then return false, err end
            ok, err = TrySetFrameSetting(damageMeter, Enum.EditModeDamageMeterSetting.Padding, DAMAGE_METER_SETTING_PADDING)
            if not ok then return false, err end
            ok, err = TrySetFrameSetting(damageMeter, Enum.EditModeDamageMeterSetting.BackgroundTransparency, DAMAGE_METER_SETTING_BACKGROUND_OPACITY)
            if not ok then return false, err end
            ok, err = TrySetFrameSetting(damageMeter, Enum.EditModeDamageMeterSetting.TextSize, DAMAGE_METER_SETTING_TEXT_SIZE)
            if not ok then return false, err end
        end

        -- Duration Bars (MirrorTimerContainer) default size in Blizzard Edit Mode.
        if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.LoadAddOn and not C_AddOns.IsAddOnLoaded("Blizzard_MirrorTimer") then
            C_AddOns.LoadAddOn("Blizzard_MirrorTimer")
        end
        local timerBars = Enum.EditModeSystem and Enum.EditModeSystem.TimerBars and GetSystemFrame(Enum.EditModeSystem.TimerBars)
        if not timerBars then
            timerBars = _G.MirrorTimerContainer
        end
        if timerBars and Enum.EditModeTimerBarsSetting then
            local ok, err = TrySetFrameSetting(timerBars, Enum.EditModeTimerBarsSetting.Size, TIMER_BARS_SETTING_SIZE)
            if not ok then return false, err end
        end
        
        -- Target Frame Settings
        if TargetFrame then
            local ok, err = TrySetFrameSetting(TargetFrame, Enum.EditModeUnitFrameSetting.BuffsOnTop, 1)
            if not ok then return false, err end
        end

        -- Focus Frame Settings
        if FocusFrame then
            local ok, err = TrySetFrameSetting(FocusFrame, Enum.EditModeUnitFrameSetting.UseLargerFrame, 1)
            if not ok then return false, err end
            ok, err = TrySetFrameSetting(FocusFrame, Enum.EditModeUnitFrameSetting.BuffsOnTop, 1)
            if not ok then return false, err end
        end
    end

    return true
end

function Module:EnsureRefineUILayout(forceReload, allowCreate, callbacks)
    callbacks = callbacks or {}

    if self._ensureFlow and self._ensureFlow.cleanup then
        self._ensureFlow.cleanup(true)
    end

    local flow = {
        callbacks = callbacks,
        finished = false,
        attempts = 0,
    }
    self._ensureFlow = flow

    local waitEventKey = "EditMode:EnsureReady:" .. tostring(GetTimePreciseSec and GetTimePreciseSec() or GetTime())

    local function fireCallback(name, payload)
        local fn = flow.callbacks[name]
        if type(fn) == "function" then
            fn(payload)
        end
    end

    local function cleanup(cancelled)
        if flow.finished then
            return
        end
        flow.finished = true
        RefineUI:OffEvent("EDIT_MODE_LAYOUTS_UPDATED", waitEventKey)
        if self._ensureFlow == flow then
            self._ensureFlow = nil
        end
        if cancelled == true then
            return
        end
    end
    flow.cleanup = cleanup

    local function fail(code, message, phase)
        cleanup(false)
        fireCallback("onFailure", {
            code = code,
            message = message,
            phase = phase,
        })
    end

    local function block(code, message, phase)
        cleanup(false)
        fireCallback("onBlocked", {
            code = code,
            message = message,
            phase = phase,
        })
    end

    local function succeed(payload)
        cleanup(false)
        fireCallback("onSuccess", payload or {})
        if forceReload then
            ReloadUI()
        end
    end

    local function runFlow()
        if flow.finished or self._ensureFlow ~= flow then
            return
        end

        if InCombatLockdown() then
            block("combat_locked", "Cannot apply the RefineUI layout while in combat.", "apply_layout")
            return
        end

        local ok, loadErr = CallOverride("LoadLayouts")
        if not ok then
            fail("unexpected_error", tostring(loadErr), "preflight")
            return
        end

        local existsOk, layoutExists = CallOverride("DoesLayoutExist", INSTALL_LAYOUT_NAME)
        if not existsOk then
            fail("unexpected_error", tostring(layoutExists), "preflight")
            return
        end

        local created = false
        if not layoutExists then
            if not allowCreate then
                fail("layout_not_found", "RefineUI layout is missing.", "create_layout")
                return
            end

            fireCallback("onPhaseChanged", { state = "running", phase = "create_layout" })

            local addOk, addErr = CallOverride("AddLayout", Enum.EditModeLayoutType.Account, INSTALL_LAYOUT_NAME)
            if not addOk then
                fail("layout_create_failed", tostring(addErr), "create_layout")
                return
            end

            local saveOk, saveErr = CallOverride("SaveOnly")
            if not saveOk then
                fail("layout_create_failed", tostring(saveErr), "create_layout")
                return
            end

            ok, loadErr = CallOverride("LoadLayouts")
            if not ok then
                fail("layout_create_failed", tostring(loadErr), "create_layout")
                return
            end

            existsOk, layoutExists = CallOverride("DoesLayoutExist", INSTALL_LAYOUT_NAME)
            if not existsOk then
                fail("layout_create_failed", tostring(layoutExists), "create_layout")
                return
            end
            if not layoutExists then
                fail("layout_missing_after_create", "RefineUI layout still does not exist after creation.", "create_layout")
                return
            end

            created = true
        end

        fireCallback("onPhaseChanged", { state = "running", phase = "activate_layout" })

        local activeOk, activeLayout = CallOverride("GetActiveLayout")
        if not activeOk then
            fail("layout_activate_failed", tostring(activeLayout), "activate_layout")
            return
        end

        if activeLayout ~= INSTALL_LAYOUT_NAME then
            local setOk, setErr = CallOverride("SetActiveLayout", INSTALL_LAYOUT_NAME)
            if not setOk then
                fail("layout_activate_failed", tostring(setErr), "activate_layout")
                return
            end

            local saveOk, saveErr = CallOverride("SaveOnly")
            if not saveOk then
                fail("layout_activate_failed", tostring(saveErr), "activate_layout")
                return
            end

            ok, loadErr = CallOverride("LoadLayouts")
            if not ok then
                fail("layout_activate_failed", tostring(loadErr), "activate_layout")
                return
            end

            activeOk, activeLayout = CallOverride("GetActiveLayout")
            if not activeOk then
                fail("layout_activate_failed", tostring(activeLayout), "activate_layout")
                return
            end
            if activeLayout ~= INSTALL_LAYOUT_NAME then
                fail("layout_activate_failed", "RefineUI layout could not be activated.", "activate_layout")
                return
            end
        end

        fireCallback("onPhaseChanged", { state = "running", phase = "apply_layout" })

        if allowCreate then
            local configureOk, configureErr = self:ConfigureRefineUILayout()
            if not configureOk then
                fail("layout_apply_failed", tostring(configureErr), "apply_layout")
                return
            end
        end

        local saveOk, saveErr = CallOverride("SaveOnly")
        if not saveOk then
            fail("layout_apply_failed", tostring(saveErr), "apply_layout")
            return
        end

        local applyOk, applyErr = CallOverride("ApplyChanges")
        if not applyOk then
            if tostring(applyErr):find("combat", 1, true) then
                block("combat_locked", "Cannot apply the RefineUI layout while in combat.", "apply_layout")
                return
            end
            fail("layout_apply_failed", tostring(applyErr), "apply_layout")
            return
        end

        ok, loadErr = CallOverride("LoadLayouts")
        if not ok then
            fail("layout_apply_failed", tostring(loadErr), "apply_layout")
            return
        end

        existsOk, layoutExists = CallOverride("DoesLayoutExist", INSTALL_LAYOUT_NAME)
        if not existsOk then
            fail("layout_apply_failed", tostring(layoutExists), "apply_layout")
            return
        end
        if not layoutExists then
            fail("layout_not_found", "RefineUI layout disappeared after applying changes.", "apply_layout")
            return
        end

        activeOk, activeLayout = CallOverride("GetActiveLayout")
        if not activeOk then
            fail("layout_apply_failed", tostring(activeLayout), "apply_layout")
            return
        end
        if activeLayout ~= INSTALL_LAYOUT_NAME then
            fail("layout_activate_failed", "RefineUI layout is no longer active after applying changes.", "apply_layout")
            return
        end

        if allowCreate and SetActionBarToggles then
            pcall(SetActionBarToggles, true, true, true, false, false, false, false, true)
        end

        succeed({
            layoutName = INSTALL_LAYOUT_NAME,
            created = created,
            phase = "apply_layout",
        })
    end

    local function waitForReady()
        if flow.finished or self._ensureFlow ~= flow then
            return
        end

        local readyOk, isReady = CallOverride("IsReady")
        if readyOk and isReady then
            runFlow()
            return
        end

        if flow.attempts == 0 then
            fireCallback("onPhaseChanged", { state = "awaiting_editmode", phase = "preflight" })
            RefineUI:RegisterEventCallback("EDIT_MODE_LAYOUTS_UPDATED", function()
                if flow.finished or self._ensureFlow ~= flow then
                    return
                end
                waitForReady()
            end, waitEventKey)
        end

        flow.attempts = flow.attempts + 1
        if flow.attempts >= READY_WAIT_ATTEMPTS then
            fail("editmode_not_ready", "Edit Mode did not become ready within 30 seconds.", "preflight")
            return
        end

        C_Timer.After(READY_WAIT_INTERVAL, waitForReady)
    end

    waitForReady()
end

-- Deprecated: Manual re-anchoring
function Module:ReanchorFrames()
    -- No-op since we use EditMode now
end

----------------------------------------------------------------------------------------
-- Reload Prompt (Golden Glow)
----------------------------------------------------------------------------------------

local function CreatePulse(frame)
    if frame.PulseAnim then return end
    local animGroup = frame:CreateAnimationGroup()
    animGroup:SetLooping("BOUNCE")
    
    local alpha = animGroup:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0.2)
    alpha:SetToAlpha(0.8)
    alpha:SetDuration(0.6)
    alpha:SetSmoothing("IN_OUT")
    
    frame.PulseAnim = animGroup
end

local function PlayPulse(frame)
    if not frame.PulseAnim then CreatePulse(frame) end
    if not frame.PulseAnim:IsPlaying() then frame.PulseAnim:Play() end
end


function Module:ShowReloadPrompt()
    if self.ReloadPrompt then 
        self.ReloadPrompt:Show()
        return 
    end

    local f = CreateFrame("Frame", "RefineUI_EditModeReloadPrompt", UIParent)
    RefineUI:AddAPI(f)
    f:SetSize(350, 140)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:CreateBackdrop()
    f:SetTemplate("Transparent")
    f:EnableMouse(true)
    
    -- Golden Glow
    local PulseGlow = RefineUI.CreateGlow and RefineUI.CreateGlow(f, 2)
    if PulseGlow then
        PulseGlow:SetFrameStrata(f:GetFrameStrata())
        PulseGlow:SetFrameLevel(f:GetFrameLevel() + 5)
        PulseGlow:SetBackdropBorderColor(1, 0.82, 0, 0.8) -- Gold color
        PulseGlow:Show()
        PlayPulse(PulseGlow)
        f.PulseGlow = PulseGlow
    end
    
    -- Header overlay
    local header = CreateFrame("Frame", nil, f)
    RefineUI:AddAPI(header)
    header:SetSize(350, 26)
    header:SetPoint("TOP", f, "TOP", 0, 0)
    header:CreateBackdrop()
    header:SetTemplate("Overlay")
    
    -- Header text
    local title = header:CreateFontString(nil, "OVERLAY")
    RefineUI:AddAPI(title)
    title:Font(14, nil, nil, true)
    title:SetPoint("CENTER", header, 0, 0)
    title:SetText("Edit Mode Complete")
    title:SetTextColor(1, 0.82, 0)
    
    -- Message text
    local msg = f:CreateFontString(nil, "OVERLAY")
    RefineUI:AddAPI(msg)
    msg:Font(12, nil, nil, true)
    msg:SetPoint("TOP", header, "BOTTOM", 0, -15)
    msg:SetWidth(320)
    msg:SetText("A UI reload is recommended to ensure\nall frames display correctly.")
    
    -- Reload button
    local reloadBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    RefineUI:AddAPI(reloadBtn)
    reloadBtn:SetSize(100, 26)
    reloadBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -10, 15)
    reloadBtn:SkinButton()
    reloadBtn:SetText("Reload")
    reloadBtn:SetScript("OnClick", function()
        ReloadUI()
    end)
    
    -- Later button
    local laterBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    RefineUI:AddAPI(laterBtn)
    laterBtn:SetSize(100, 26)
    laterBtn:SetPoint("BOTTOMLEFT", f, "BOTTOM", 10, 15)
    laterBtn:SkinButton()
    laterBtn:SetText("Later")
    laterBtn:SetScript("OnClick", function()
        f:Hide()
    end)
    
    self.ReloadPrompt = f
end

function Module:HookExitEditMode()
    if not EditModeManagerFrame then
        return
    end

    RefineUI:HookOnce("Core:EditMode:EditModeManagerFrame:ExitEditMode", EditModeManagerFrame, "ExitEditMode", function()
        C_Timer.After(0.5, function()
            Module:ShowReloadPrompt()
        end)
    end)
end
