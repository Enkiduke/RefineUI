----------------------------------------------------------------------------------------
-- RefineUI Install
-- Description: First-time setup, recovery UI, and Edit Mode installation flow.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Install = RefineUI:RegisterModule("Install")

local C_Timer = C_Timer
local ReloadUI = ReloadUI
local wipe = wipe
local pairs = pairs
local LibEditModeOverride = LibStub("LibEditModeOverride-1.0", true)

local INSTALL_STATES = {
    uninstalled = true,
    running = true,
    awaiting_combat = true,
    awaiting_editmode = true,
    failed = true,
    ready = true,
}

local RUNNING_STATES = {
    running = true,
    awaiting_combat = true,
    awaiting_editmode = true,
}

local INSTALL_MODES = {
    full = true,
    repair = true,
}

local INSTALL_PHASES = {
    preflight = true,
    create_layout = true,
    activate_layout = true,
    apply_layout = true,
    finalize = true,
    reload = true,
}

local FAILURE_CODES = {
    combat_locked = true,
    editmode_not_ready = true,
    layout_create_failed = true,
    layout_missing_after_create = true,
    layout_activate_failed = true,
    layout_apply_failed = true,
    layout_not_found = true,
    unexpected_error = true,
}

local PHASE_LABELS = {
    preflight = "Checking Edit Mode readiness",
    create_layout = "Creating the RefineUI layout",
    activate_layout = "Activating the RefineUI layout",
    apply_layout = "Applying RefineUI Edit Mode settings",
    finalize = "Restoring RefineUI defaults",
    reload = "Reloading the UI",
}

local RUN_STATE_MESSAGES = {
    running = "Installation is in progress.",
    awaiting_combat = "Waiting for combat to end. Installation will resume automatically.",
    awaiting_editmode = "Waiting for Blizzard Edit Mode to finish loading.",
}

local EVENT_KEY_REGEN_ENABLED = "Install:RegenEnabled"
local EVENT_KEY_PEW = "Install:PEW"
local EVENT_KEY_REGEN_DISABLED = "Install:RegenDisabled"

local DEFAULT_WINDOW_TEXT = "Welcome to |cffffd200Refine|rUI! This wizard will help you set up the interface.\n\nIt will configure your chat, CVars, and position your unit frames using WoW's Edit Mode."

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------

local function NormalizeMode(mode, fallback)
    if INSTALL_MODES[mode] then
        return mode
    end
    return fallback or "full"
end

local function NormalizePhase(phase, fallback)
    if INSTALL_PHASES[phase] then
        return phase
    end
    return fallback or "preflight"
end

local function NormalizeFailureCode(code)
    if FAILURE_CODES[code] then
        return code
    end
    return nil
end

local function SafeOverrideCall(method, ...)
    local fn = LibEditModeOverride and LibEditModeOverride[method]
    if type(fn) ~= "function" then
        return false
    end
    return pcall(fn, LibEditModeOverride, ...)
end

local function HasAnyManagedLayout()
    local managedLayoutNames = RefineUI.ManagedLayoutNames
    if type(managedLayoutNames) ~= "table" then
        return false
    end

    for _, layoutName in pairs(managedLayoutNames) do
        local existsOk, layoutExists = SafeOverrideCall("DoesLayoutExist", layoutName)
        if existsOk and layoutExists then
            return true
        end
    end

    return false
end

local function GetManagedLayoutTierByName(layoutName)
    local managedLayoutNames = RefineUI.ManagedLayoutNames
    if type(layoutName) ~= "string" or type(managedLayoutNames) ~= "table" then
        return nil
    end

    for tierKey, managedName in pairs(managedLayoutNames) do
        if managedName == layoutName then
            return tierKey
        end
    end

    return nil
end

function Install:GetDB()
    return RefineUI.DB
end

function Install:IsInstallReady()
    local db = self:GetDB()
    return db and db.Installed == true and db.InstallState == "ready"
end

function Install:IsInstallRunning(state)
    local value = state
    if value == nil then
        local db = self:GetDB()
        value = db and db.InstallState
    end
    return RUNNING_STATES[value] == true
end

function Install:NormalizeInstallState()
    local db = self:GetDB()
    if not db then
        return
    end

    db.InstallAttempts = tonumber(db.InstallAttempts) or 0

    if db.InstallState == "pending" then
        db.InstallState = "failed"
        db.InstallMode = NormalizeMode(db.InstallMode, db.Installed and "repair" or "full")
        db.InstallPhase = NormalizePhase(db.InstallPhase, "preflight")
        db.InstallFailureCode = "unexpected_error"
        db.InstallFailureMessage = "A previous installation attempt never completed. Repair the RefineUI layout to continue."
    end

    if not INSTALL_STATES[db.InstallState] then
        db.InstallState = db.Installed and "ready" or "uninstalled"
    end

    db.InstallMode = NormalizeMode(db.InstallMode, db.Installed and "repair" or "full")
    db.InstallPhase = NormalizePhase(db.InstallPhase, db.InstallState == "ready" and "reload" or "preflight")
    db.InstallFailureCode = NormalizeFailureCode(db.InstallFailureCode)

    if db.InstallState == "ready" then
        db.Installed = true
        db.InstallFailureCode = nil
        db.InstallFailureMessage = nil
    elseif db.InstallState ~= "failed" and db.InstallFailureCode == nil then
        db.InstallFailureMessage = nil
    end
end

function Install:GetStatusSnapshot()
    self:NormalizeInstallState()

    local db = self:GetDB() or {}
    return {
        installed = db.Installed == true,
        state = db.InstallState or "uninstalled",
        mode = db.InstallMode or "full",
        phase = db.InstallPhase or "preflight",
        failureCode = db.InstallFailureCode,
        failureMessage = db.InstallFailureMessage,
        attempts = db.InstallAttempts or 0,
    }
end

function Install:SetInstallState(state, opts)
    local db = self:GetDB()
    if not db or not INSTALL_STATES[state] then
        return
    end

    opts = opts or {}

    db.InstallState = state
    db.InstallMode = NormalizeMode(opts.mode, db.InstallMode)
    db.InstallPhase = NormalizePhase(opts.phase, db.InstallPhase)

    if opts.installed ~= nil then
        db.Installed = opts.installed == true
    end

    if state == "ready" then
        db.Installed = true
        db.InstallFailureCode = nil
        db.InstallFailureMessage = nil
    else
        if opts.failureCode ~= nil then
            db.InstallFailureCode = NormalizeFailureCode(opts.failureCode)
        elseif state ~= "failed" then
            db.InstallFailureCode = nil
        end
        if opts.failureMessage ~= nil then
            db.InstallFailureMessage = opts.failureMessage
        elseif state ~= "failed" then
            db.InstallFailureMessage = nil
        end
    end

    if self.Frame then
        self:RefreshFrame()
    end
end

function Install:SetFailure(code, message, phase, mode)
    local db = self:GetDB()
    self:SetInstallState("failed", {
        mode = mode or (db and db.InstallMode) or "repair",
        phase = phase or "preflight",
        installed = db and db.Installed == true or false,
        failureCode = code or "unexpected_error",
        failureMessage = message or "Installation failed for an unknown reason.",
    })
    self:PrintFailureToChat(code, message, phase, mode)
end

function Install:GetPrimaryStatusText(snapshot)
    snapshot = snapshot or self:GetStatusSnapshot()

    if snapshot.state == "failed" then
        if snapshot.failureCode == "layout_not_found" then
            return "The RefineUI Edit Mode layout is missing.\n\nClick Repair Edit Mode Layout to restore it."
        end
        return "RefineUI installation could not finish.\n\nDetails were printed to chat."
    end

    if RUN_STATE_MESSAGES[snapshot.state] then
        return RUN_STATE_MESSAGES[snapshot.state]
    end

    if snapshot.state == "ready" then
        return "RefineUI installation is complete. Reloading your UI..."
    end

    return DEFAULT_WINDOW_TEXT
end

function Install:PrintStatus()
    local snapshot = self:GetStatusSnapshot()
    RefineUI:Print(
        "Install Status: state=%s, mode=%s, phase=%s, attempts=%d",
        snapshot.state,
        snapshot.mode,
        snapshot.phase,
        snapshot.attempts or 0
    )

    if snapshot.failureCode then
        RefineUI:Print("Install Failure: %s", snapshot.failureCode)
    end
    if snapshot.failureMessage then
        RefineUI:Print("Install Message: %s", snapshot.failureMessage)
    end
end

function Install:PrintFailureToChat(code, message, phase, mode)
    if message and message ~= "" then
        RefineUI:Print("Install: %s", message)
    end
    if code or phase or mode then
        RefineUI:Print(
            "Install Detail: code=%s, phase=%s, mode=%s",
            tostring(code or "unexpected_error"),
            tostring(phase or "preflight"),
            tostring(mode or "repair")
        )
    end
end

-- Install Defaults
----------------------------------------------------------------------------------------

function Install:ApplyInstallCVars()
    if type(RefineUI.ApplyInstallCVars) ~= "function" then
        return
    end

    RefineUI:ApplyInstallCVars()
    RefineUI:Print("Install: CVar defaults applied.")
end

function Install:RestoreDefaults()
    local db = self:GetDB()
    local defaults = RefineUI.DefaultConfig or RefineUI.Defaults
    if not db or not defaults then
        return false, "Defaults are not available."
    end

    local attempts = db.InstallAttempts or 0
    local mode = db.InstallMode

    wipe(db)
    RefineUI:CopyDefaults(defaults, db)

    db.InstallAttempts = attempts
    db.InstallMode = mode

    RefineUI:Print("Install: Factory reset complete. Defaults restored.")
    return true
end

----------------------------------------------------------------------------------------
-- Flow
----------------------------------------------------------------------------------------

function Install:ClearPendingRun()
    self.PendingCombatResume = nil
    RefineUI:OffEvent("PLAYER_REGEN_ENABLED", EVENT_KEY_REGEN_ENABLED)
end

function Install:QueueCombatResume(mode, phase, automatic)
    local db = self:GetDB()
    self.PendingCombatResume = {
        mode = NormalizeMode(mode, db and db.InstallMode),
        automatic = automatic == true,
    }

    self:SetInstallState("awaiting_combat", {
        mode = self.PendingCombatResume.mode,
        phase = NormalizePhase(phase, "apply_layout"),
        installed = db and db.Installed == true or false,
        failureCode = "combat_locked",
        failureMessage = "Combat locked the install flow. It will resume automatically once combat ends.",
    })

    RefineUI:RegisterEventCallback("PLAYER_REGEN_ENABLED", function(...)
        self:OnEvent(...)
    end, EVENT_KEY_REGEN_ENABLED)
end

function Install:FinalizeInstall(mode)
    local db = self:GetDB()
    mode = NormalizeMode(mode, db and db.InstallMode)
    local automatic = self.ActiveInstall and self.ActiveInstall.automatic == true

    if mode == "full" then
        self:SetInstallState("running", {
            mode = mode,
            phase = "finalize",
            installed = db and db.Installed == true or false,
        })

        local ok, err = self:RestoreDefaults()
        if not ok then
            self:SetFailure("unexpected_error", err or "Failed to restore default settings.", "finalize", mode)
            self.ActiveInstall = nil
            self:Toggle(true)
            return
        end
        db = self:GetDB()

        self:ApplyInstallCVars()
    end

    self:SetInstallState("ready", {
        mode = mode,
        phase = "reload",
        installed = true,
    })

    self.ActiveInstall = nil
    self:Toggle(false)
    if automatic then
        RefineUI:Print("Install: Reload your UI to finish applying RefineUI.")
        return
    end

    ReloadUI()
end

function Install:HandleLayoutFailure(mode, payload)
    self.ActiveInstall = nil

    local code = payload and payload.code or "unexpected_error"
    local phase = payload and payload.phase or "preflight"
    local message = payload and payload.message or "Installation failed."

    self:SetFailure(code, message, phase, mode)
    self:Toggle(true)
end

function Install:HandleLayoutBlocked(mode, payload)
    local activeInstall = self.ActiveInstall
    self.ActiveInstall = nil

    local code = payload and payload.code or "combat_locked"
    local phase = payload and payload.phase or "apply_layout"

    if code == "combat_locked" then
        self:QueueCombatResume(mode, phase, activeInstall and activeInstall.automatic)
        self:Toggle(true)
        return
    end

    self:HandleLayoutFailure(mode, payload)
end

function Install:RunEditModeInstall(mode, automatic)
    local EditMode = RefineUI:GetModule("EditMode")
    if not EditMode or type(EditMode.EnsureRefineUILayout) ~= "function" then
        self.ActiveInstall = nil
        self:SetFailure("unexpected_error", "Edit Mode support is unavailable.", "preflight", mode)
        self:Toggle(true)
        return
    end

    self.ActiveInstall = {
        mode = mode,
        automatic = automatic == true,
    }

    local targetTier = RefineUI.GetLayoutTier and RefineUI:GetLayoutTier() or nil

    EditMode:EnsureRefineUILayout(false, true, {
        onPhaseChanged = function(payload)
            local db = self:GetDB()
            self:SetInstallState(payload.state or "running", {
                mode = mode,
                phase = payload.phase or "preflight",
                installed = db and db.Installed == true or false,
            })
        end,
        onBlocked = function(payload)
            self:HandleLayoutBlocked(mode, payload)
        end,
        onFailure = function(payload)
            self:HandleLayoutFailure(mode, payload)
        end,
        onSuccess = function()
            self:FinalizeInstall(mode)
        end,
    }, targetTier)
end

function Install:StartInstall(mode, opts)
    local db = self:GetDB()
    if not db then
        return
    end

    self:NormalizeInstallState()

    opts = opts or {}
    mode = NormalizeMode(mode, db.Installed and "repair" or "full")

    if self.ActiveInstall or self.PendingCombatResume then
        return
    end

    db.InstallAttempts = (tonumber(db.InstallAttempts) or 0) + 1

    self:SetInstallState("running", {
        mode = mode,
        phase = "preflight",
        installed = db.Installed == true,
        failureCode = nil,
        failureMessage = nil,
    })

    self.ActiveInstall = {
        mode = mode,
        automatic = opts.automatic == true,
    }
    self:Toggle(true)

    if InCombatLockdown() then
        self.ActiveInstall = nil
        self:QueueCombatResume(mode, "preflight", opts.automatic)
        return
    end

    self:RunEditModeInstall(mode, opts.automatic)
end

function Install:ResumePendingInstall()
    local db = self:GetDB()
    if not db then
        return
    end

    local pending = self.PendingCombatResume
    if pending then
        self.PendingCombatResume = nil
        self:RunEditModeInstall(pending.mode, pending.automatic)
        return
    end

    if self:IsInstallRunning(db.InstallState) then
        self:StartInstall(db.InstallMode, { automatic = false })
    end
end

function Install:CheckInstalledLayout()
    if self.ActiveInstall or self.PendingCombatResume then
        return
    end

    local db = self:GetDB()
    if not db or db.InstallState ~= "ready" then
        return
    end

    local EditMode = RefineUI:GetModule("EditMode")
    if not EditMode or type(EditMode.EnsureRefineUILayout) ~= "function" then
        return
    end

    local readyOk, isReady = SafeOverrideCall("IsReady")
    if not readyOk or not isReady then
        return
    end

    local loadOk = SafeOverrideCall("LoadLayouts")
    if not loadOk then
        return
    end

    local activeOk, activeLayout = SafeOverrideCall("GetActiveLayout")
    if not activeOk then
        return
    end

    if not RefineUI:IsManagedLayoutName(activeLayout) then
        if not HasAnyManagedLayout() then
            self:SetFailure("layout_not_found", "RefineUI could not find any managed Edit Mode layout.", "preflight", "repair")
            self:Toggle(true)
        end
        return
    end

    local activeTier = GetManagedLayoutTierByName(activeLayout)
    EditMode:EnsureRefineUILayout(false, false, {
        onBlocked = function()
            -- Login while in combat can delay layout verification until later.
            self.PendingLoginLayoutCheck = true
            RefineUI:RegisterEventCallback("PLAYER_REGEN_ENABLED", function(...)
                self:OnEvent(...)
            end, EVENT_KEY_REGEN_ENABLED)
        end,
        onFailure = function(payload)
            local code = payload and payload.code or "layout_not_found"
            local message = "RefineUI could not find its Edit Mode layout."
            if code ~= "layout_not_found" then
                message = payload and payload.message or "RefineUI failed to verify its Edit Mode layout."
            end

            self:SetFailure(code, message, "preflight", "repair")
            self:Toggle(true)
        end,
    }, activeTier)
end

function Install:SyncReadyStateWithExistingLayout()
    local db = self:GetDB()
    if not db or db.InstallState ~= "ready" then
        return
    end

    local readyOk, isReady = SafeOverrideCall("IsReady")
    if not readyOk or not isReady then
        return
    end

    local loadOk = SafeOverrideCall("LoadLayouts")
    if not loadOk then
        return
    end

    if not HasAnyManagedLayout() then
        self:SetFailure("layout_not_found", "RefineUI could not find any managed Edit Mode layout.", "preflight", "repair")
    end
end

----------------------------------------------------------------------------------------
-- GUI
----------------------------------------------------------------------------------------

function Install:CreateFrame()
    if self.Frame then
        return
    end

    local f = CreateFrame("Frame", "RefineUI_InstallFrame", UIParent)
    RefineUI.AddAPI(f)
    f:SetSize(450, 220)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:CreateBackdrop()
    f:SetTemplate("Transparent")

    local topOverlay = CreateFrame("Frame", nil, f)
    RefineUI.AddAPI(topOverlay)
    topOverlay:SetSize(450, 30)
    topOverlay:SetPoint("TOP", f, "TOP", 0, 0)
    topOverlay:CreateBackdrop()
    topOverlay:SetTemplate("Overlay")

    local header = topOverlay:CreateFontString(nil, "OVERLAY")
    RefineUI.AddAPI(header)
    header:Font(16, nil, nil, true)
    header:SetPoint("CENTER", topOverlay, 0, 0)
    header:SetText("RefineUI Installation")
    header:SetTextColor(1, 0.82, 0)

    local status = f:CreateFontString(nil, "OVERLAY")
    RefineUI.AddAPI(status)
    status:Font(14, nil, nil, true)
    status:SetPoint("TOP", topOverlay, "BOTTOM", 0, -20)
    status:SetWidth(400)
    status:SetJustifyH("CENTER")
    status:SetJustifyV("TOP")
    status:SetSpacing(4)

    local primary = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    RefineUI.AddAPI(primary)
    primary:SetSize(200, 30)
    primary:SetPoint("BOTTOM", f, "BOTTOM", 0, 20)
    primary:SkinButton()
    primary:SetScript("OnClick", function()
        local snapshot = self:GetStatusSnapshot()
        if snapshot.state == "failed" then
            self:StartInstall("repair")
            return
        end
        if self:IsInstallRunning(snapshot.state) and not self.ActiveInstall and not self.PendingCombatResume then
            self:ResumePendingInstall()
            return
        end
        self:StartInstall("full")
    end)

    local secondary = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    RefineUI.AddAPI(secondary)
    secondary:SetSize(140, 24)
    secondary:SetPoint("BOTTOM", f, "BOTTOM", 0, 20)
    secondary:SkinButton()
    secondary:SetText("Full Reinstall")
    secondary:SetScript("OnClick", function()
        self:StartInstall("full")
    end)

    self.Frame = f
    self.Frame.Status = status
    self.Frame.PrimaryButton = primary
    self.Frame.SecondaryButton = secondary
    self.Frame:Hide()
end

function Install:RefreshFrame()
    if not self.Frame then
        return
    end

    local snapshot = self:GetStatusSnapshot()
    self.Frame.Status:SetText(self:GetPrimaryStatusText(snapshot))

    local primary = self.Frame.PrimaryButton
    local secondary = self.Frame.SecondaryButton

    primary:Enable()
    secondary:Hide()
    primary:ClearAllPoints()
    secondary:ClearAllPoints()

    if snapshot.state == "failed" then
        primary:SetText("Repair Edit Mode Layout")
        primary:SetPoint("BOTTOM", self.Frame, "BOTTOM", 0, 48)
        secondary:Show()
        secondary:SetPoint("BOTTOM", self.Frame, "BOTTOM", 0, 16)
    elseif self:IsInstallRunning(snapshot.state) then
        primary:SetPoint("BOTTOM", self.Frame, "BOTTOM", 0, 20)
        if self.ActiveInstall or self.PendingCombatResume then
            primary:SetText("Working...")
            primary:Disable()
        else
            primary:SetText("Resume Installation")
        end
    else
        primary:SetPoint("BOTTOM", self.Frame, "BOTTOM", 0, 20)
        primary:SetText("Complete Installation")
    end
end

function Install:Toggle(show)
    if not self.Frame then
        self:CreateFrame()
    end

    if show then
        if InCombatLockdown() then
            self.wasShown = true
            RefineUI:RegisterEventCallback("PLAYER_REGEN_ENABLED", function(...)
                self:OnEvent(...)
            end, EVENT_KEY_REGEN_ENABLED)
            RefineUI:Print("Install: Waiting for combat to end to show the installer.")
            return
        end
        self:RefreshFrame()
        self.Frame:Show()
    else
        if self.Frame then
            self.Frame:Hide()
        end
    end
end

----------------------------------------------------------------------------------------
-- Commands
----------------------------------------------------------------------------------------

function Install:HandleCommand(msg)
    local action, rest = (msg or ""):match("^(%S*)%s*(.-)$")
    action = (action or ""):lower()
    rest = rest or ""

    if action == "" then
        self:Toggle(true)
        return
    end

    if action == "status" then
        self:PrintStatus()
        return
    end

    if action == "repair" then
        self:StartInstall("repair")
        return
    end

    if action == "reinstall" then
        self:StartInstall("full")
        return
    end

    if action == "install" then
        local sub = rest:lower()
        if sub == "status" then
            self:PrintStatus()
        else
            self:Toggle(true)
        end
        return
    end

    self:Toggle(true)
end

----------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------

function Install:HandleLoginState()
    self:NormalizeInstallState()

    local snapshot = self:GetStatusSnapshot()
    if snapshot.state == "ready" then
        self:CheckInstalledLayout()
        return
    end

    if snapshot.state == "uninstalled" or snapshot.state == "failed" or self:IsInstallRunning(snapshot.state) then
        self:Toggle(true)
    end
end

function Install:OnEvent(event)
    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(2, function()
            self:HandleLoginState()
        end)
        return
    end

    if event == "PLAYER_REGEN_DISABLED" then
        if self.Frame and self.Frame:IsShown() then
            self.Frame:Hide()
            self.wasShown = true
        end
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        if self.PendingLoginLayoutCheck then
            self.PendingLoginLayoutCheck = nil
            self:CheckInstalledLayout()
        end

        if self.PendingCombatResume then
            local pending = self.PendingCombatResume
            self.PendingCombatResume = nil
            RefineUI:OffEvent("PLAYER_REGEN_ENABLED", EVENT_KEY_REGEN_ENABLED)
            if self.wasShown then
                self.wasShown = false
                self.ActiveInstall = {
                    mode = pending.mode,
                    automatic = pending.automatic == true,
                }
                self:Toggle(true)
            end
            self:RunEditModeInstall(pending.mode, pending.automatic)
            return
        end

        if self.wasShown then
            self.wasShown = false
            self:Toggle(true)
        end

        RefineUI:OffEvent("PLAYER_REGEN_ENABLED", EVENT_KEY_REGEN_ENABLED)
    end
end

function Install:OnInitialize()
    self:NormalizeInstallState()

    RefineUI:RegisterEventCallback("PLAYER_ENTERING_WORLD", function(...)
        self:OnEvent(...)
    end, EVENT_KEY_PEW)
    RefineUI:RegisterEventCallback("PLAYER_REGEN_DISABLED", function(...)
        self:OnEvent(...)
    end, EVENT_KEY_REGEN_DISABLED)
end

function Install:OnEnable()
    -- Perform a best-effort sync before later modules treat the session as ready.
    self:SyncReadyStateWithExistingLayout()
end
