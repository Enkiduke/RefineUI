----------------------------------------------------------------------------------------
-- GameTime and CombatTimer for RefineUI
-- Description: Displays game time or combat timer at the bottom center of the screen.
----------------------------------------------------------------------------------------

local AddOnName, RefineUI = ...

----------------------------------------------------------------------------------------
-- Module Registration
----------------------------------------------------------------------------------------
local GameTime = RefineUI:RegisterModule("GameTime")

----------------------------------------------------------------------------------------
-- WoW Globals (Upvalues)
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local GetTime = GetTime
local floor = math.floor
local format = string.format
local date = date

----------------------------------------------------------------------------------------
-- Locals
----------------------------------------------------------------------------------------
local combatStartTime = 0
local inCombat = false
local timeTicker = nil

----------------------------------------------------------------------------------------
-- Utility Functions
----------------------------------------------------------------------------------------

local function FormatTime(seconds)
    local m = floor(seconds / 60)
    local s = floor(seconds % 60)
    return format("%02d:%02d", m, s)
end

local function GetGameTimeText()
    return date("%H:%M")
end

----------------------------------------------------------------------------------------
-- Update Functions
----------------------------------------------------------------------------------------

-- Called every frame ONLY during combat
local function OnCombatUpdate(self, elapsed)
    self.elapsed = (self.elapsed or 0) + elapsed
    if self.elapsed < 0.1 then return end
    self.elapsed = 0

    local duration = GetTime() - combatStartTime
    self.Text:SetText(FormatTime(duration))
end

-- Called every second via ticker (out of combat)
local function UpdateGameTime()
    if not inCombat and GameTime.Text then
        GameTime.Text:SetText(GetGameTimeText())
        GameTime.Text:SetTextColor(1, 1, 1) -- White for game time
    end
end

----------------------------------------------------------------------------------------
-- Initialization
----------------------------------------------------------------------------------------

function GameTime:OnEnable()
    if not (RefineUI.Config.GameTime and RefineUI.Config.GameTime.Enable) then return end

    local frame = CreateFrame("Button", "RefineUI_GameTime", UIParent)
    -- Strict API
    RefineUI.Size(frame, 100, 20)
    RefineUI.Point(frame, "BOTTOM", UIParent, "BOTTOM", 0, 10)
    frame:SetScript("OnClick", function(_, button)
        if button == "LeftButton" and not inCombat then
            if _G.ToggleCalendar then
                _G.ToggleCalendar()
            end
        end
    end)

    local text = frame:CreateFontString(nil, "OVERLAY")
    -- Strict API: Font
    text:SetFont(RefineUI.Media.Fonts.Default, RefineUI:Scale(32), "")
    text:SetAlpha(0.5)
    RefineUI.Point(text, "CENTER", frame, "CENTER", 0, 0)
    
    self.Text = text
    frame.Text = text -- Required for OnCombatUpdate script
    self.frame = frame

    -- Use EventBus for combat events
    RefineUI:RegisterEventCallback("PLAYER_REGEN_DISABLED", function()
        inCombat = true
        combatStartTime = GetTime()
        self.Text:SetTextColor(1, 0.2, 0.2) -- Red for combat
        frame:SetScript("OnUpdate", OnCombatUpdate) -- Start fast updates
    end, "GameTime:CombatStart")

    RefineUI:RegisterEventCallback("PLAYER_REGEN_ENABLED", function()
        inCombat = false
        frame:SetScript("OnUpdate", nil) -- Stop fast updates
        UpdateGameTime() -- Immediate update to game time
    end, "GameTime:CombatEnd")

    -- Use ticker for game time updates (1 second interval, only needs minute precision)
    timeTicker = C_Timer.NewTicker(1, UpdateGameTime)
    
    -- Initial update
    UpdateGameTime()
end
