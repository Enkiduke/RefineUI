local R, C, L= unpack(RefineUI)

-- Optimization: Localize frequently used functions
local pairs, ipairs = pairs, ipairs
local CreateFrame = CreateFrame
local C_Timer = C_Timer

-- Debug function (gated by CVAR: refineui_actionbar_debug)
local GetCVarBool = GetCVarBool or function() return false end
local function Debug(...)
    if not GetCVarBool("refineui_actionbar_debug") then return end
    print("|cff33ff99RefineUI ActionBar Fade:|r", ...)
end

-- Configuration (default values)
local defaults = {
    fadeOutDelay = 1,
    fadeOutDuration = 0.1,
    fadeInDuration = 0.1,
    alphaMin = 0,
    alphaMax = 1,
}

-- Bars to fade
local barNames = {
    "MainMenuBar",
    "MultiBarBottomLeft",
    "MultiBarBottomRight",
    "MultiBarRight",
    "MultiBarLeft",
    "MultiBar5",
    "MultiBar6",
    "MultiBar7",
    "StanceBar",
    "PetActionBar",
}

-- Action Bar Fading functionality
R.ActionBars = R.ActionBars or {}
R.ActionBars.Mouseover = {}

function R.ActionBars.Mouseover:Initialize()
    -- Ensure settings exist in RefineUISettings
    if not RefineUISettings.actionBarFade then
        RefineUISettings.actionBarFade = CopyTable(defaults)
    end
    
    self.db = RefineUISettings.actionBarFade
    
    self.bars = {}
    self.barButtons = {}
    for _, barName in ipairs(barNames) do
        local bar = _G[barName]
        if bar then
            self.bars[barName] = bar
            self:HookBar(bar, barName)
            -- Set initial alpha
            bar:SetAlpha(self.db.alphaMin)
        end
    end
    Debug("Mouseover initialized for " .. #barNames .. " bars")
end

function R.ActionBars.Mouseover:HookBar(bar, barName)
    bar:EnableMouse(true)
    
    -- Cache buttons for this bar once
    local buttons = {}
    do
        local buttonPrefix
        if barName == "PetActionBar" then
            buttonPrefix = "PetActionButton"
        elseif barName == "StanceBar" then
            buttonPrefix = "StanceButton"
        else
            buttonPrefix = string.gsub(barName, "Bar", "Button")
        end
        for i = 1, 12 do
            local button = _G[buttonPrefix .. i]
            if button then
                buttons[#buttons + 1] = button
            end
        end
    end
    self.barButtons[barName] = buttons
    
    local function IsMouseOverBarOrButtons()
        if MouseIsOver(bar) then return true end
        for i = 1, #buttons do
            local button = buttons[i]
            if button and MouseIsOver(button) then return true end
        end
        return false
    end

    -- Ensure animations exist
    local function EnsureAnimations()
        if bar.fadeInAG and bar.fadeOutAG then return end
        -- Fade In
        local fadeInAG = bar:CreateAnimationGroup()
        local fadeIn = fadeInAG:CreateAnimation("Alpha")
        fadeIn:SetDuration(self.db.fadeInDuration)
        fadeIn:SetSmoothing("OUT")
        bar.fadeInAG = fadeInAG
        bar.fadeIn = fadeIn
        -- Fade Out
        local fadeOutAG = bar:CreateAnimationGroup()
        local fadeOut = fadeOutAG:CreateAnimation("Alpha")
        fadeOut:SetDuration(self.db.fadeOutDuration)
        fadeOut:SetSmoothing("IN")
        bar.fadeOutAG = fadeOutAG
        bar.fadeOut = fadeOut
    end

    local function HandleMouseEnter()
        EnsureAnimations()
        self:FadeIn(bar)
        if bar.fadeTimer then bar.fadeTimer:Cancel() end
    end

    local function HandleMouseLeave()
        EnsureAnimations()
        bar.fadeTimer = C_Timer.NewTimer(0.1, function()
            if not IsMouseOverBarOrButtons() then
                self:FadeOut(bar)
            end
        end)
    end

    bar:SetScript("OnEnter", HandleMouseEnter)
    bar:SetScript("OnLeave", HandleMouseLeave)
    
    -- Hook individual buttons
    for i = 1, #buttons do
        local button = buttons[i]
        button:HookScript("OnEnter", HandleMouseEnter)
        button:HookScript("OnLeave", HandleMouseLeave)
    end
    
    Debug("Hooked bar and buttons for " .. barName)
end

function R.ActionBars.Mouseover:FadeIn(bar)
    if bar.fadeTimer then bar.fadeTimer:Cancel(); bar.fadeTimer = nil end
    if bar.fadeOutAG and bar.fadeOutAG:IsPlaying() then bar.fadeOutAG:Stop() end
    if not bar.fadeInAG then return end
    local current = bar:GetAlpha()
    bar.fadeIn:SetFromAlpha(current)
    bar.fadeIn:SetToAlpha(self.db.alphaMax)
    bar.fadeIn:SetDuration(self.db.fadeInDuration)
    bar.fadeInAG:Stop()
    bar.fadeInAG:Play()
    Debug("FadeIn called for bar " .. bar:GetName() .. ", to alpha " .. self.db.alphaMax)
end

function R.ActionBars.Mouseover:FadeOut(bar)
    if bar.fadeTimer then bar.fadeTimer:Cancel() end
    if bar.fadeInAG and bar.fadeInAG:IsPlaying() then bar.fadeInAG:Stop() end
    if not bar.fadeOutAG then return end
    bar.fadeTimer = C_Timer.NewTimer(self.db.fadeOutDelay, function()
        local current = bar:GetAlpha()
        bar.fadeOut:SetFromAlpha(current)
        bar.fadeOut:SetToAlpha(self.db.alphaMin)
        bar.fadeOut:SetDuration(self.db.fadeOutDuration)
        bar.fadeOutAG:Stop()
        bar.fadeOutAG:Play()
        Debug("FadeOut started for bar " .. bar:GetName())
    end)
    Debug("FadeOut scheduled for bar " .. bar:GetName() .. ", delay: " .. self.db.fadeOutDelay)
end

function R.ActionBars.Mouseover:UpdateBars()
    for _, bar in pairs(self.bars) do
        bar:SetAlpha(self.db.alphaMax)
    end
    Debug("Updated all bars to alpha " .. self.db.alphaMax)
end

-- Create a new frame for our config menu
local ConfigFrame = CreateFrame("Frame", "RefineUIActionBarFadeConfig", UIParent, "BasicFrameTemplateWithInset")
ConfigFrame:SetSize(300, 350)
ConfigFrame:SetPoint("CENTER", UIParent, "CENTER", -800, 0)
ConfigFrame:Hide()
ConfigFrame.title = ConfigFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
ConfigFrame.title:SetPoint("TOP", ConfigFrame, "TOP", 0, -5)
ConfigFrame.title:SetText("Action Bar Fade Settings")

-- Function to create sliders
local function CreateSlider(parent, name, minVal, maxVal, step)
    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider:SetWidth(200)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider.Text:SetText(name)
    slider.Low:SetText(minVal)
    slider.High:SetText(maxVal)
    return slider
end

-- Create sliders for each option
local fadeOutDelaySlider = CreateSlider(ConfigFrame, "Fade Out Delay", 0, 5, 0.1)
fadeOutDelaySlider:SetPoint("TOP", ConfigFrame, "TOP", 0, -50)

local fadeOutDurationSlider = CreateSlider(ConfigFrame, "Fade Out Duration", 0, 2, 0.05)
fadeOutDurationSlider:SetPoint("TOP", fadeOutDelaySlider, "BOTTOM", 0, -40)

local fadeInDurationSlider = CreateSlider(ConfigFrame, "Fade In Duration", 0, 2, 0.05)
fadeInDurationSlider:SetPoint("TOP", fadeOutDurationSlider, "BOTTOM", 0, -40)

local alphaMinSlider = CreateSlider(ConfigFrame, "Minimum Alpha", 0, 1, 0.05)
alphaMinSlider:SetPoint("TOP", fadeInDurationSlider, "BOTTOM", 0, -40)

local alphaMaxSlider = CreateSlider(ConfigFrame, "Maximum Alpha", 0, 1, 0.05)
alphaMaxSlider:SetPoint("TOP", alphaMinSlider, "BOTTOM", 0, -40)

-- Function to update settings
local function UpdateSettings(slider, value)
    local setting = slider.setting
    R.ActionBars.Mouseover.db[setting] = value
    RefineUISettings.actionBarFade[setting] = value
    R.ActionBars.Mouseover:UpdateBars()
end

-- Set up sliders
fadeOutDelaySlider:SetScript("OnValueChanged", UpdateSettings)
fadeOutDelaySlider.setting = "fadeOutDelay"

fadeOutDurationSlider:SetScript("OnValueChanged", UpdateSettings)
fadeOutDurationSlider.setting = "fadeOutDuration"

fadeInDurationSlider:SetScript("OnValueChanged", UpdateSettings)
fadeInDurationSlider.setting = "fadeInDuration"

alphaMinSlider:SetScript("OnValueChanged", UpdateSettings)
alphaMinSlider.setting = "alphaMin"

alphaMaxSlider:SetScript("OnValueChanged", UpdateSettings)
alphaMaxSlider.setting = "alphaMax"

-- Function to update slider values
local function UpdateSliderValues()
    fadeOutDelaySlider:SetValue(R.ActionBars.Mouseover.db.fadeOutDelay)
    fadeOutDurationSlider:SetValue(R.ActionBars.Mouseover.db.fadeOutDuration)
    fadeInDurationSlider:SetValue(R.ActionBars.Mouseover.db.fadeInDuration)
    alphaMinSlider:SetValue(R.ActionBars.Mouseover.db.alphaMin)
    alphaMaxSlider:SetValue(R.ActionBars.Mouseover.db.alphaMax)
end

-- Function to toggle the config frame
local function ToggleConfigFrame()
    if ConfigFrame:IsShown() then
        Debug("Hiding config frame")
        ConfigFrame:Hide()
    else
        Debug("Showing config frame")
        UpdateSliderValues()
        ConfigFrame:Show()
    end
end


-- Edit Mode Integration
local function InitializeEditModeOptions()
    Debug("Initializing Edit Mode Options")
    
    local function HookEditMode()
        if EditModeManagerFrame then
            Debug("EditModeManagerFrame found")
            hooksecurefunc(EditModeManagerFrame, "SelectSystem", function(self, systemFrame)
                Debug("SelectSystem called", systemFrame.system)
                if systemFrame.system == Enum.EditModeSystem.ActionBar then
                    Debug("Action Bar system selected, toggling config frame")
                    ToggleConfigFrame()
                elseif ConfigFrame:IsShown() then
                    Debug("Non-Action Bar system selected, hiding config frame")
                    ConfigFrame:Hide()
                end
            end)
            return true
        end
        return false
    end

    local retries = 0
    local maxRetries = 10
    local function TryHookEditMode()
        if HookEditMode() then
            Debug("Successfully hooked into Edit Mode")
        else
            retries = retries + 1
            if retries < maxRetries then
                C_Timer.After(1, TryHookEditMode)
                Debug("EditModeManagerFrame not found, retrying in 1 second. Attempt: " .. retries)
            else
                Debug("Failed to hook into Edit Mode after " .. maxRetries .. " attempts")
            end
        end
    end

    TryHookEditMode()
end



-- Hook into RefineUI initialization
local function InitializeMouseover()
    R.ActionBars.Mouseover:Initialize()
    C_Timer.After(1, InitializeEditModeOptions)  -- Delay to ensure EditModeManagerFrame is available
end

if R.InitializeModules then
    table.insert(R.InitializeModules, InitializeMouseover)
else
    C_Timer.After(0, InitializeMouseover)
end

-- Configuration integration (example)
-- This is a placeholder. You'll need to integrate this with your actual configuration system
local function SetupConfig()
    -- Example of how you might set up configuration options
    -- Replace this with your actual configuration setup code
    if R.Config and R.Config.Options and R.Config.Options.Args and R.Config.Options.Args.ActionBars then
        R.Config.Options.Args.ActionBars.Args.Fading = {
            order = 10,
            type = "group",
            name = "Action Bar Fading",
            get = function(info) return RefineUISettings.actionBarFade[info[#info]] end,
            set = function(info, value) 
                RefineUISettings.actionBarFade[info[#info]] = value 
                R.ActionBars.Mouseover.db = RefineUISettings.actionBarFade
                R.ActionBars.Mouseover:UpdateBars()
            end,
            args = {
                fadeOutDelay = {
                    order = 1,
                    type = "range",
                    name = "Fade Out Delay",
                    min = 0, max = 5, step = 0.1,
                },
                fadeOutDuration = {
                    order = 2,
                    type = "range",
                    name = "Fade Out Duration",
                    min = 0, max = 2, step = 0.05,
                },
                fadeInDuration = {
                    order = 3,
                    type = "range",
                    name = "Fade In Duration",
                    min = 0, max = 2, step = 0.05,
                },
                alphaMin = {
                    order = 4,
                    type = "range",
                    name = "Minimum Alpha",
                    min = 0, max = 1, step = 0.05,
                },
                alphaMax = {
                    order = 5,
                    type = "range",
                    name = "Maximum Alpha",
                    min = 0, max = 1, step = 0.05,
                },
            },
        }
    end
end

-- Call this function when your configuration system is ready
SetupConfig()
Debug("RefineUI ActionBar Fade module loaded")