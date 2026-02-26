----------------------------------------------------------------------------------------
-- RefineUI Install
-- Description: First-time setup, GUI wizard, and CVar enforcement.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Install = RefineUI:RegisterModule("Install")

local LibEditModeOverride = LibStub("LibEditModeOverride-1.0", true)

----------------------------------------------------------------------------------------
-- Logic
----------------------------------------------------------------------------------------
function Install:SetupCVars()
    local C_CVar = C_CVar
    local GetCVar = GetCVar
    
    -- Helper to only set CVar if value differs
    local function SetCVarIfDifferent(cvar, value)
        local current = GetCVar(cvar)
        if current ~= tostring(value) then
            C_CVar.SetCVar(cvar, value)
        end
    end
    
    -- Graphical & Gameplay CVars
    SetCVarIfDifferent("buffDurations", 1)
    SetCVarIfDifferent("damageMeterEnabled", 1)
    SetCVarIfDifferent("countdownForCooldowns", 1)
    SetCVarIfDifferent("chatMouseScroll", 1)
    SetCVarIfDifferent("screenshotQuality", 10)
    SetCVarIfDifferent("showTutorials", 0)
    SetCVarIfDifferent("autoQuestWatch", 1)
    SetCVarIfDifferent("alwaysShowActionBars", 1)
    SetCVarIfDifferent("statusText", 1)
    SetCVarIfDifferent("statusTextDisplay", "BOTH")
    SetCVarIfDifferent("nameplateUseClassColorForFriendlyPlayerUnitNames", 1)
    SetCVarIfDifferent("UnitNameNPC", 1)
    SetCVarIfDifferent("nameplateMinScale", 1)
    SetCVarIfDifferent("nameplateMaxScale", 1)
    SetCVarIfDifferent("nameplateLargerScale", 1)
    SetCVarIfDifferent("nameplateSelectedScale", 1)
    SetCVarIfDifferent("nameplateMinAlpha", 0.5)
    SetCVarIfDifferent("nameplateMaxAlpha", 1)
    SetCVarIfDifferent("nameplateMaxDistance", 60)
    SetCVarIfDifferent("nameplateMinAlphaDistance", 0)
    SetCVarIfDifferent("nameplateMaxAlphaDistance", 40)
    SetCVarIfDifferent("nameplateOccludedAlphaMult", 0.1)
    SetCVarIfDifferent("nameplateSelectedAlpha", 1)
    
    -- API (modern): SetActionBarToggles(bar1, bar2, bar3, bar4, bar5, bar6, bar7, alwaysShow)
    -- bar1=BottomLeft(Bar 2), bar2=BottomRight(Bar 3), bar3=Right(Bar 4), bar4=Left(Bar 5)
    -- bar5=ActionBar6(MultiBar5), bar6=ActionBar7(MultiBar6), bar7=ActionBar8(MultiBar7)
    -- Keep Bar 5 disabled until RefineUI EditMode layout is applied to avoid
    -- Blizzard right-bar auto-scale issues before installation/layout creation.
    if SetActionBarToggles then
        SetActionBarToggles(true, true, true, false, false, false, false, true)
    end
    
    print("|cffffd200Refine|rUI:|r CVars setup complete.")
end

function Install:DoInstall()
    -- 1. Setup CVars
    self:SetupCVars()
    
    -- 2. FACTORY RESET: Wipe settings and restore defaults
    -- This ensures "Installer" = "Refresh Defaults" as requested
    local defaults = RefineUI.DefaultConfig or RefineUI.Defaults
    if defaults then
        wipe(RefineUI.DB)
        -- Restore Defaults
        RefineUI:CopyDefaults(defaults, RefineUI.DB)
        RefineUI:Print("Factory Reset complete. Defaults restored.")
    end

    -- 3. Mark Installed (Before async flow potentially invalidates)
    RefineUI.DB.Installed = true

    -- 3. Setup EditMode & Reload
    local EditMode = RefineUI:GetModule("EditMode")
    if EditMode and EditMode.EnsureRefineUILayout then
        EditMode:EnsureRefineUILayout(true, true) -- true = reload when done, true = allow create
    else
        ReloadUI() -- Fallback if EditMode module missing
    end
end

----------------------------------------------------------------------------------------
-- GUI
----------------------------------------------------------------------------------------
function Install:CreateFrame()
    if self.Frame then return end
    
    -- Main Frame
    local f = CreateFrame("Frame", "RefineUI_InstallFrame", UIParent)
    RefineUI.AddAPI(f)
    f:SetSize(450, 200)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:CreateBackdrop()
    f:SetTemplate("Transparent")
    
    -- Decoration: Header Line
    local topOverlay = CreateFrame("Frame", nil, f)
    RefineUI.AddAPI(topOverlay)
    topOverlay:SetSize(450, 30)
    topOverlay:SetPoint("TOP", f, "TOP", 0, 0)
    topOverlay:CreateBackdrop()
    topOverlay:SetTemplate("Overlay")
    
    -- Header Text
    local header = topOverlay:CreateFontString(nil, "OVERLAY")
    RefineUI.AddAPI(header)
    header:Font(16, nil, nil, true)
    header:SetPoint("CENTER", topOverlay, 0, 0)
    header:SetText("RefineUI Installation")
    header:SetTextColor(1, 0.82, 0)
    
    -- Welcome Text
    local welcome = f:CreateFontString(nil, "OVERLAY")
    RefineUI.AddAPI(welcome)
    welcome:Font(14, nil, nil, true)
    welcome:SetPoint("TOP", topOverlay, "BOTTOM", 0, -20)
    welcome:SetWidth(400)
    welcome:SetText("Welcome to |cffffd200Refine|rUI! This wizard will help you set up the interface.\n\nIt will configure your chat, CVars, and position your unit frames using WoW's Edit Mode.")
    
    -- Complete Button
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    RefineUI.AddAPI(b)
    b:SetSize(200, 30)
    b:SetPoint("BOTTOM", f, "BOTTOM", 0, 20)
    b:SkinButton()
    b:SetText("Complete Installation")
    b:SetScript("OnClick", function()
        self:DoInstall()
    end)
    
    self.Frame = f
    self.Frame:Hide()
end

function Install:Toggle(show)
    if not self.Frame then self:CreateFrame() end
    
    if show then
        if InCombatLockdown() then
            RefineUI:RegisterEventCallback("PLAYER_REGEN_ENABLED", function(...) self:OnEvent(...) end, "Install:RegenEnabled")
            print("|cffffd200Refine|rUI:|r Waiting for combat to end to show installer...")
            return
        end
        self.Frame:Show()
    else
        self.Frame:Hide()
    end
end

----------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------
function Install:OnEvent(event)
    if event == "PLAYER_ENTERING_WORLD" then
        -- Wait for EditMode Lib to be ready
        if LibEditModeOverride and LibEditModeOverride.IsReady and not LibEditModeOverride:IsReady() then
             C_Timer.After(1, function() self:OnEvent("PLAYER_ENTERING_WORLD") end)
             return
        end
        
        -- Check if installed (Safe navigation)
        local isInstalled = RefineUI.DB and RefineUI.DB.Installed
        
        -- Check if EditMode layout exists
        local layoutExists = false
        if LibEditModeOverride and LibEditModeOverride.DoesLayoutExist then
            LibEditModeOverride:LoadLayouts() -- API requires this before checking existence
            layoutExists = LibEditModeOverride:DoesLayoutExist("RefineUI")
        end
        
        -- Trigger if NOT installed OR Layout missing
        if not isInstalled or not layoutExists then
            C_Timer.After(2, function() -- Wait a bit for other things to load
                self:Toggle(true)
            end)
        end
        
    elseif event == "PLAYER_REGEN_DISABLED" then
        if self.Frame and self.Frame:IsShown() then
            self.Frame:Hide()
            self.wasShown = true
        end
        
    elseif event == "PLAYER_REGEN_ENABLED" then
        if self.wasShown then
            self.Frame:Show()
            self.wasShown = false
        end
        RefineUI:OffEvent("PLAYER_REGEN_ENABLED", "Install:RegenEnabled")
    end
end

function Install:OnInitialize()
    RefineUI:RegisterEventCallback("PLAYER_ENTERING_WORLD", function(...) self:OnEvent(...) end, "Install:PEW")
    RefineUI:RegisterEventCallback("PLAYER_REGEN_DISABLED", function(...) self:OnEvent(...) end, "Install:RegenDisabled")
end

function Install:OnEnable()
    -- Check immediately on login in case we missed PEW
    self:OnEvent("PLAYER_ENTERING_WORLD")
end
