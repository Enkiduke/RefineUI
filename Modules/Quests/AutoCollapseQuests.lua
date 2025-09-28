local addonName, addon = ...

-- Initialize default settings (do not mutate this table at runtime)
addon.defaultSettings = {
    autoCollapseMode = "NONE", -- Default to no auto-collapse
}

local function ShallowCopy(tbl)
    local t = {}
    for k, v in pairs(tbl) do t[k] = v end
    return t
end

-- Initialize saved variables
function addon:OnAddonLoaded(event, loadedAddonName)
    if loadedAddonName ~= addonName then return end
    
    -- Initialize or load saved variables with a shallow copy of defaults
    if type(ObjectiveTrackerCollapseSettings) ~= "table" then
        ObjectiveTrackerCollapseSettings = ShallowCopy(addon.defaultSettings)
    else
        -- Fill in any missing keys from defaults without overwriting existing values
        for k, v in pairs(addon.defaultSettings) do
            if ObjectiveTrackerCollapseSettings[k] == nil then
                ObjectiveTrackerCollapseSettings[k] = v
            end
        end
    end
    
    addon:SetupMenu()
    addon:SetupAutoCollapse()
end

-- Create the right-click menu
function addon:SetupMenu()
    if addon.menuHooked then return end

    local function tryHook()
        if not ObjectiveTrackerFrame or not ObjectiveTrackerFrame.Header or not ObjectiveTrackerFrame.Header.MinimizeButton then
            return false
        end

        local minimizeButton = ObjectiveTrackerFrame.Header.MinimizeButton
        local menuFrame = CreateFrame("Frame", "ObjectiveTrackerCollapseMenu", UIParent, "UIDropDownMenuTemplate")

        local function MenuOnClick(self, arg1)
            ObjectiveTrackerCollapseSettings.autoCollapseMode = arg1
            CloseDropDownMenus()
            addon:SetupAutoCollapse() -- Refresh auto-collapse behavior
        end

        local function currentModeLabel()
            local m = ObjectiveTrackerCollapseSettings and ObjectiveTrackerCollapseSettings.autoCollapseMode or "NONE"
            if m == "RAID" then return "Raid" end
            if m == "SCENARIO" then return "Scenario" end
            if m == "RELOAD" then return "On Reload" end
            return "None"
        end

        local menuList = {
            {text = "Auto Collapse Mode", isTitle = true, notCheckable = true},
            {text = "None", arg1 = "NONE", func = MenuOnClick, checked = function() return ObjectiveTrackerCollapseSettings.autoCollapseMode == "NONE" end},
            {text = "In Raid", arg1 = "RAID", func = MenuOnClick, checked = function() return ObjectiveTrackerCollapseSettings.autoCollapseMode == "RAID" end},
            {text = "In Scenario", arg1 = "SCENARIO", func = MenuOnClick, checked = function() return ObjectiveTrackerCollapseSettings.autoCollapseMode == "SCENARIO" end},
            {text = "On Reload", arg1 = "RELOAD", func = MenuOnClick, checked = function() return ObjectiveTrackerCollapseSettings.autoCollapseMode == "RELOAD" end},
        }

    -- Register only left clicks for OnClick; we'll use OnMouseUp for right-click menu so it doesn't toggle
    minimizeButton:RegisterForClicks("LeftButtonUp")
        minimizeButton:HookScript("OnMouseUp", function(self, button)
            if button == "RightButton" then
                if InCombatLockdown() then return end
                EasyMenu(menuList, menuFrame, "cursor", 0, 0, "MENU")
            end
        end)

        -- Tooltip
        minimizeButton:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Objective Tracker Controls")
            GameTooltip:AddLine("Left-click: Collapse/Expand", 1, 1, 1)
            GameTooltip:AddLine("Right-click: Auto-collapse Settings", 1, 1, 1)
            GameTooltip:AddLine("Mode: "..currentModeLabel(), 0.9, 0.9, 0.9)
            GameTooltip:Show()
        end)
        minimizeButton:HookScript("OnLeave", function() GameTooltip:Hide() end)

        addon.menuHooked = true
        return true
    end

    if not tryHook() then
        -- Retry shortly until the tracker is ready
        local attempts = 0
        local function retry()
            attempts = attempts + 1
            if addon.menuHooked then return end
            if tryHook() then return end
            if attempts < 20 then
                C_Timer.After(0.25, retry)
            end
        end
        C_Timer.After(0.25, retry)
    end
end

-- Setup auto-collapse behavior
function addon:SetupAutoCollapse()
    local pendingAction -- "collapse" | "expand" | nil
    addon.autoCollapseState = addon.autoCollapseState or { collapsedByAddon = false, reloadApplied = false }

    local function doSetCollapsed(collapsed)
        if not ObjectiveTrackerFrame then return end

        -- Prefer API if available
        if type(ObjectiveTrackerFrame.SetCollapsed) == "function" then
            ObjectiveTrackerFrame:SetCollapsed(collapsed)
            addon.autoCollapseState.collapsedByAddon = collapsed and true or false
            return
        end
        -- Fallback: click the button to toggle if state differs
        local btn = ObjectiveTrackerFrame.Header and ObjectiveTrackerFrame.Header.MinimizeButton
        if btn then
            local isCollapsed = ObjectiveTrackerFrame.isCollapsed or (type(ObjectiveTrackerFrame.GetCollapsed) == "function" and ObjectiveTrackerFrame:GetCollapsed())
            if isCollapsed ~= collapsed then
                btn:Click()
                addon.autoCollapseState.collapsedByAddon = collapsed and true or false
            else
                addon.autoCollapseState.collapsedByAddon = collapsed and true or false
            end
        end
    end

    local function safePerform(action)
        if InCombatLockdown() then
            pendingAction = action
            return
        end
        C_Timer.After(0.1, function()
            if action == "collapse" then
                doSetCollapsed(true)
            elseif action == "expand" then
                doSetCollapsed(false)
            end
        end)
    end

    local function CollapseObjectiveTracker()
        safePerform("collapse")
    end
    
    local function ExpandObjectiveTracker()
        safePerform("expand")
    end
    
    local function OnEvent()
        local mode = ObjectiveTrackerCollapseSettings.autoCollapseMode
        local inInstance, instanceType = IsInInstance()

        -- Debounce: compute desired state and avoid redundant ops
        local desiredAction

        if mode == "RAID" then
            if inInstance and (instanceType == "raid" or IsInRaid()) then
                desiredAction = "collapse"
            else
                desiredAction = addon.autoCollapseState.collapsedByAddon and "expand" or nil
            end
        elseif mode == "SCENARIO" then
            local inScenario = C_Scenario and C_Scenario.IsInScenario and C_Scenario.IsInScenario()
            if inScenario then
                desiredAction = "collapse"
            else
                desiredAction = addon.autoCollapseState.collapsedByAddon and "expand" or nil
            end
        elseif mode == "RELOAD" then
            -- Collapse once after reload/entering world
            if not addon.autoCollapseState.reloadApplied then
                desiredAction = "collapse"
                addon.autoCollapseState.reloadApplied = true
            else
                desiredAction = nil
            end
        else -- NONE
            desiredAction = nil -- Don't force state in NONE mode
        end

        if desiredAction == "collapse" then
            CollapseObjectiveTracker()
        elseif desiredAction == "expand" then
            ExpandObjectiveTracker()
        end
    end
    
    -- Remove existing event listener if any
    if addon.autoCollapseFrame then
        addon.autoCollapseFrame:UnregisterAllEvents()
        addon.autoCollapseFrame:SetScript("OnEvent", nil)
    end
    
    -- Setup new event listener
    addon.autoCollapseFrame = addon.autoCollapseFrame or CreateFrame("Frame")
    addon.autoCollapseFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    addon.autoCollapseFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    addon.autoCollapseFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    addon.autoCollapseFrame:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
    addon.autoCollapseFrame:RegisterEvent("SCENARIO_UPDATE")
    addon.autoCollapseFrame:RegisterEvent("SCENARIO_CRITERIA_UPDATE")
    addon.autoCollapseFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    addon.autoCollapseFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" and pendingAction then
            local action = pendingAction
            pendingAction = nil
            safePerform(action)
        else
            OnEvent()
        end
    end)
    
    -- Initial setup
    OnEvent()
end

-- Register events
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    addon:OnAddonLoaded(event, ...)
end)