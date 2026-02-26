----------------------------------------------------------------------------------------
-- RefineUI EditMode Handling
-- Description: Manages the WoW Edit Mode system to ensure our frames stay put.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Module = RefineUI:RegisterModule("EditMode")

local LibEditModeOverride = LibStub("LibEditModeOverride-1.0", true)
RefineUI.LibEditMode = LibStub("LibEditMode", true)
local C_AddOns = C_AddOns

if not LibEditModeOverride or not RefineUI.LibEditMode then
    print("|cffff0000RefineUI Error:|r EditMode libraries not found. Edit Mode functionality will be disabled.")
    return
end

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

function Module:OnInitialize()
    -- Nothing to do early
end

function Module:OnEnable()
    -- Register Custom Frames with LibEditMode if they exist
    self:RegisterCustomFrames()
    
    -- Ensure Layout (Do not auto-create, let Installer handle that if missing)
    self:EnsureRefineUILayout(false, false)
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
    if not LibEditModeOverride:IsReady() then return end
    
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
                     LibEditModeOverride:ReanchorFrame(frame, point, relativeTo, relativePoint, x, y)
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
        LibEditModeOverride:ReanchorFrame(damageMeterSystem, point, relativeTo, relativePoint, x, y)
    end

    -- 2. Specific Settings
    if LibEditModeOverride:GetActiveLayout() == "RefineUI" then
        -- Enable Blizzard Duration Bars (MirrorTimerContainer) by default for the RefineUI layout.
        if Enum.EditModeAccountSetting and Enum.EditModeAccountSetting.ShowTimerBars then
            LibEditModeOverride:SetGlobalSetting(Enum.EditModeAccountSetting.ShowTimerBars, 1)
        end

        -- Hide MainMenuBar Art & Scrolling
        if MainActionBar then
            LibEditModeOverride:SetFrameSetting(MainActionBar, Enum.EditModeActionBarSetting.HideBarArt, 1)
            LibEditModeOverride:SetFrameSetting(MainActionBar, Enum.EditModeActionBarSetting.HideBarScrolling, 1)
            LibEditModeOverride:SetFrameSetting(MainActionBar, Enum.EditModeActionBarSetting.AlwaysShowButtons, 0)
            LibEditModeOverride:SetFrameSetting(MainActionBar, Enum.EditModeActionBarSetting.IconPadding, 4)
        end
        
        -- Action Bars 2-5 baseline settings
        for _, bar in ipairs({MultiBarBottomLeft, MultiBarBottomRight, MultiBarRight, MultiBarLeft}) do
            if bar then
                LibEditModeOverride:SetFrameSetting(bar, Enum.EditModeActionBarSetting.AlwaysShowButtons, 0)
                LibEditModeOverride:SetFrameSetting(bar, Enum.EditModeActionBarSetting.IconPadding, 4)
            end
        end

        -- Keep Action Bars 2-4 visible by default.
        for _, bar in ipairs({MultiBarBottomLeft, MultiBarBottomRight, MultiBarRight}) do
            if bar then
                LibEditModeOverride:SetFrameSetting(bar, Enum.EditModeActionBarSetting.VisibleSetting, Enum.ActionBarVisibleSetting.Always)
            end
        end

        -- Action Bars 3, 4, and 5 default to 10 icons in 2 rows.
        local horizontalOrientation = (Enum.ActionBarOrientation and Enum.ActionBarOrientation.Horizontal) or 0
        for _, bar in ipairs({MultiBarBottomRight, MultiBarRight, MultiBarLeft}) do
            if bar then
                LibEditModeOverride:SetFrameSetting(bar, Enum.EditModeActionBarSetting.Orientation, horizontalOrientation)
                LibEditModeOverride:SetFrameSetting(bar, Enum.EditModeActionBarSetting.NumRows, 2)
                LibEditModeOverride:SetFrameSetting(bar, Enum.EditModeActionBarSetting.NumIcons, 10)
            end
        end
        
        -- Hide Action Bars 5/6/7/8 (MultiBarLeft, MultiBar5/6/7) by default.
        -- Use system-index lookup so this still works when globals are not ready yet.
        for _, barIndex in ipairs({5, 6, 7, 8}) do
            local bar = GetActionBarFrameByIndex(barIndex)
            if bar then
                LibEditModeOverride:SetFrameSetting(bar, Enum.EditModeActionBarSetting.VisibleSetting, Enum.ActionBarVisibleSetting.Hidden)
            end
        end
        
        -- Stance Bar Padding
        if StanceBar then
            LibEditModeOverride:SetFrameSetting(StanceBar, Enum.EditModeActionBarSetting.IconPadding, 4)
        end

        -- Pet Bar Padding
        if PetActionBar then
            LibEditModeOverride:SetFrameSetting(PetActionBar, Enum.EditModeActionBarSetting.IconPadding, 4)
        end

        -- Force Raid-Style Party Frames
        if PartyFrame then
            LibEditModeOverride:SetFrameSetting(PartyFrame, Enum.EditModeUnitFrameSetting.UseRaidStylePartyFrames, 1)
            LibEditModeOverride:SetFrameSetting(PartyFrame, Enum.EditModeUnitFrameSetting.SortPlayersBy, Enum.SortPlayersBy.Role)
            LibEditModeOverride:SetFrameSetting(PartyFrame, Enum.EditModeUnitFrameSetting.FrameWidth, 72)
            LibEditModeOverride:SetFrameSetting(PartyFrame, Enum.EditModeUnitFrameSetting.FrameHeight, 28)
        end
        
        -- Set BuffFrame settings
        -- NOTE: We only use LibEditModeOverride:SetFrameSetting() to configure BuffFrame.
        -- DO NOT call BuffFrame:UpdateSystemSettingIconSize() or similar - they trigger
        -- Blizzard's internal Update() which compares expirationTime (a SECRET value in 12.0)
        -- and causes Lua errors. The EditMode system applies settings automatically.
        if BuffFrame then
            LibEditModeOverride:SetFrameSetting(BuffFrame, Enum.EditModeAuraFrameSetting.IconSize, 10)
            LibEditModeOverride:SetFrameSetting(BuffFrame, Enum.EditModeAuraFrameSetting.IconLimitBuffFrame, 12)
            LibEditModeOverride:SetFrameSetting(BuffFrame, Enum.EditModeAuraFrameSetting.IconPadding, 10)
        end
        
        -- Set MicroMenu Size
        local microMenu = GetSystemFrame(Enum.EditModeSystem.MicroMenu)
        if microMenu then
            LibEditModeOverride:SetFrameSetting(microMenu, Enum.EditModeMicroMenuSetting.Size, 9)
        end

        -- Damage Meter defaults
        local damageMeter = GetSystemFrame(Enum.EditModeSystem.DamageMeter)
        if damageMeter and Enum.EditModeDamageMeterSetting then
            LibEditModeOverride:SetFrameSetting(damageMeter, Enum.EditModeDamageMeterSetting.FrameWidth, DAMAGE_METER_SETTING_FRAME_WIDTH)
            LibEditModeOverride:SetFrameSetting(damageMeter, Enum.EditModeDamageMeterSetting.FrameHeight, DAMAGE_METER_SETTING_FRAME_HEIGHT)
            LibEditModeOverride:SetFrameSetting(damageMeter, Enum.EditModeDamageMeterSetting.BarHeight, DAMAGE_METER_SETTING_BAR_HEIGHT)
            LibEditModeOverride:SetFrameSetting(damageMeter, Enum.EditModeDamageMeterSetting.Padding, DAMAGE_METER_SETTING_PADDING)
            LibEditModeOverride:SetFrameSetting(damageMeter, Enum.EditModeDamageMeterSetting.BackgroundTransparency, DAMAGE_METER_SETTING_BACKGROUND_OPACITY)
            LibEditModeOverride:SetFrameSetting(damageMeter, Enum.EditModeDamageMeterSetting.TextSize, DAMAGE_METER_SETTING_TEXT_SIZE)
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
            LibEditModeOverride:SetFrameSetting(timerBars, Enum.EditModeTimerBarsSetting.Size, TIMER_BARS_SETTING_SIZE)
        end
        
        -- Target Frame Settings
        if TargetFrame then
            LibEditModeOverride:SetFrameSetting(TargetFrame, Enum.EditModeUnitFrameSetting.BuffsOnTop, 1)
        end

        -- Focus Frame Settings
        if FocusFrame then
            LibEditModeOverride:SetFrameSetting(FocusFrame, Enum.EditModeUnitFrameSetting.UseLargerFrame, 1)
            LibEditModeOverride:SetFrameSetting(FocusFrame, Enum.EditModeUnitFrameSetting.BuffsOnTop, 1)
        end
    end
end

function Module:EnsureRefineUILayout(forceReload, allowCreate)
    local attempts = 0
    local maxAttempts = 40 -- 20 seconds at 0.5s interval

    local function try()
        if not LibEditModeOverride or not LibEditModeOverride:IsReady() then
            attempts = attempts + 1
            if attempts >= maxAttempts then
                RefineUI:Error("EditMode override never became ready; skipping EnsureRefineUILayout.")
                return
            end
            C_Timer.After(0.5, try)
            return
        end

        -- Load layouts
        LibEditModeOverride:LoadLayouts()

        -- Create "RefineUI" layout if missing
        if not LibEditModeOverride:DoesLayoutExist("RefineUI") then
            -- Keep Bar 5 disabled until our layout exists/applies to avoid Blizzard
            -- right-action-bar auto-scale issues on startup with missing layout.
            if SetActionBarToggles then
                SetActionBarToggles(true, true, true, false, false, false, false, true)
            end

            if allowCreate then
                LibEditModeOverride:AddLayout(Enum.EditModeLayoutType.Account, "RefineUI")
                LibEditModeOverride:SaveOnly()
                LibEditModeOverride:LoadLayouts() -- Refresh
            else
                -- If we aren't allowed to create, stop here.
                -- This allows the Install module to detect missing layout and prompt user.
                return
            end
        end

        -- Activate "RefineUI" layout
        if LibEditModeOverride:GetActiveLayout() ~= "RefineUI" then
             LibEditModeOverride:SetActiveLayout("RefineUI")
        end
        
        -- Apply Settings & Positions
        if allowCreate then
            self:ConfigureRefineUILayout()
        end
        
        LibEditModeOverride:SaveOnly()
        
        -- Force Apply
        LibEditModeOverride:ApplyChanges()

        -- Final post-layout action-bar toggles:
        -- Keep Bars 2-4 enabled and Bars 5-8 disabled by default.
        if allowCreate and SetActionBarToggles then
            SetActionBarToggles(true, true, true, false, false, false, false, true)
        end

        if forceReload then 
            C_UI.Reload()
        end
    end
    
    try()
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
    local PulseGlow = RefineUI.CreateGlow and RefineUI.CreateGlow(f, 6)
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
    if EditModeManagerFrame then
        hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
            C_Timer.After(0.5, function()
                Module:ShowReloadPrompt()
            end)
        end)
    end
end

-- Init Hook
local originalEnable = Module.OnEnable
function Module:OnEnable()
    originalEnable(self)
    self:HookExitEditMode()
end
