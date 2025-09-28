local R, C, L = unpack(RefineUI)
local UF = R.UF
local LibEditModeOverride = LibStub("LibEditModeOverride-1.0")
local LEM = LibStub('LibEditMode')
local DEBUG = false

-- Initialize RefineUIPositions at the top level
RefineUIPositions = RefineUIPositions or {}

-- Debounced/scheduled application of Edit Mode changes to avoid fragile
-- Blizzard EditMode exit paths during login (e.g., BuffFrame nil compares).
local applyScheduled = false
local applyAfterCombat
local applyRetryCount = 0
local MAX_APPLY_RETRIES = 5
local function TryApplyNow()
    if not LibEditModeOverride or not LibEditModeOverride.IsReady or not LibEditModeOverride:IsReady() then
        if applyRetryCount < MAX_APPLY_RETRIES then
            applyRetryCount = applyRetryCount + 1
            C_Timer.After(0.75, TryApplyNow)
        else
            if DEBUG then
                print("RefineUI EditMode: ApplyChanges skipped; not ready after retries")
            end
            -- allow future scheduling attempts
            applyScheduled = false
        end
        return
    end
    if InCombatLockdown() then
        if not applyAfterCombat then
            applyAfterCombat = CreateFrame("Frame")
            applyAfterCombat:RegisterEvent("PLAYER_REGEN_ENABLED")
            applyAfterCombat:SetScript("OnEvent", function(self)
                self:UnregisterAllEvents()
                self:SetScript("OnEvent", nil)
                applyAfterCombat = nil
                local ok2, err2 = pcall(function()
                    LibEditModeOverride:ApplyChanges()
                end)
                if not ok2 and DEBUG then
                    print("RefineUI EditMode: post-combat ApplyChanges failed:", err2)
                end
                applyScheduled = false
            end)
        end
        return
    end
    local ok, err = pcall(function()
        LibEditModeOverride:ApplyChanges()
    end)
    if not ok and DEBUG then
        print("RefineUI EditMode: ApplyChanges failed:", err)
    end
    -- allow future scheduling attempts regardless of success
    applyScheduled = false
end

local function ScheduleApplyChanges(delay)
    -- reset retry counter for a fresh attempt
    applyRetryCount = 0
    if applyScheduled then return end
    applyScheduled = true
    C_Timer.After(delay or 1.5, function()
        TryApplyNow()
    end)
end

local function onPositionChanged(frame, layoutName, point, x, y)
    if DEBUG then
        print("Frame:", frame)
        print("Frame Name:", frame:GetName())
        print("Layout Name:", layoutName)
        print("Point:", point)
        print("X:", x)
        print("Y:", y)
    end

    if not frame or not layoutName then
    if DEBUG then print("Error: Invalid frame or layoutName in onPositionChanged") end
        return
    end

    -- Initialize the table structure if it doesn't exist
    RefineUIPositions[layoutName] = RefineUIPositions[layoutName] or {}
    local frameName = frame:GetName()
    if not frameName then
    if DEBUG then print("Error: Frame has no name in onPositionChanged") end
        return
    end
    RefineUIPositions[layoutName][frameName] = RefineUIPositions[layoutName][frameName] or {}

    -- Now we can safely save the position
    local frameData = RefineUIPositions[layoutName][frameName]
    frameData.point = point
    frameData.x = x
    frameData.y = y

    -- Apply the new position immediately
    frame:ClearAllPoints()
    -- Per LibEditMode docs, use 3-arg SetPoint with implicit UIParent/relativePoint
    frame:SetPoint(point, x, y)

    if DEBUG then print("Position saved and applied for frame:", frameName) end
end

-- Assuming defaultPosition is defined somewhere
local function ConvertPosition(positionTable)
    return {
        point = positionTable[1],
        x = positionTable[4],
        y = positionTable[5]
    }
end

    local customFrames = {
        {"RefineUI_Player", C.position.unitframes.player},
        {"RefineUI_Target", C.position.unitframes.target},
        {"RefineUI_Focus", C.position.unitframes.focus},
        {"RefineUI_Party", C.position.unitframes.party},
        {"RefineUI_Raid", C.position.unitframes.raid},
        {"RefineUI_Boss", C.position.unitframes.boss},
        {"RefineUI_Arena", C.position.unitframes.arena},
        {"RefineUI_ExperienceBar", C.position.unitframes.experienceBar},
        {"RefineUI_Buffs", C.position.playerBuffs},
        {"RefineUI_SelfBuffsReminder", C.position.selfBuffs},
        {"DetailsBaseFrame1", C.position.details},
        {"RefineUI_AutoItemBar", C.position.autoitembar},
        {"AutoButtonAnchor", C.position.autoButton},
        {"RefineUI_LeftBuff", C.position.filger.left_buff},
        {"RefineUI_RightBuff", C.position.filger.right_buff},
        {"RefineUI_BottomBuff", C.position.filger.bottom_buff},
        {"RefineUI_BWTimeline", C.position.bwtimeline},
    }

    -- Re-register hook: try to register frames as they appear, avoiding duplicates
    local registeredFrames = {}
    local function TryRegisterFrames()
        local total = #customFrames
        local done = 0
        for _, frameInfo in ipairs(customFrames) do
            local name, pos = frameInfo[1], frameInfo[2]
            if registeredFrames[name] then
                done = done + 1
            else
                local frame = _G[name]
                if frame then
                    local ok, err = pcall(function()
                        LEM:AddFrame(frame, onPositionChanged, ConvertPosition(pos))
                    end)
                    if ok then
                        registeredFrames[name] = true
                        done = done + 1
                        if DEBUG then print("LEM registered:", name) end
                    elseif DEBUG then
                        print("LEM register failed for", name, err)
                    end
                end
            end
        end
        return done, total
    end

    -- Initial attempt at file load (for already-present frames)
    TryRegisterFrames()

    -- Event-driven retries for late-created frames
    local reg = CreateFrame("Frame")
    reg:RegisterEvent("ADDON_LOADED")
    reg:RegisterEvent("PLAYER_ENTERING_WORLD")
    reg:SetScript("OnEvent", function()
        local done, total = TryRegisterFrames()
        if done == total then
            reg:UnregisterAllEvents()
        end
    end)

    -- Short post-login ticker to catch delayed creations
    local attempts = 8
    local ticker
    local function maybeStop()
        local done, total = TryRegisterFrames()
        attempts = attempts - 1
        if done == total or attempts <= 0 then
            if ticker and ticker.Cancel then ticker:Cancel() end
        end
    end
    ticker = C_Timer.NewTicker(1, maybeStop, attempts)

-- if _G['RefineUI_Player'] then LEM:AddFrame(_G['RefineUI_Player'], onPositionChanged, ConvertPosition(C.position.unitframes.player)) end
-- if _G['RefineUI_Target'] then LEM:AddFrame(_G['RefineUI_Target'], onPositionChanged, ConvertPosition(C.position.unitframes.target)) end
-- if _G['RefineUI_ExperienceBar'] then LEM:AddFrame(_G['RefineUI_ExperienceBar'], onPositionChanged, ConvertPosition(C.position.unitframes.experienceBar)) end

-- if _G['DetailsBaseFrame1'] then LEM:AddFrame(_G['DetailsBaseFrame1'], onPositionChanged, ConvertPosition(C.position.details)) end

-- additional (anonymous) callbacks
LEM:RegisterCallback('enter', function()
    -- Add any enter logic here
end)

LEM:RegisterCallback('exit', function()
    -- Add any exit logic here
end)

LEM:RegisterCallback('layout', function(layoutName)
    -- Initialize the layout table if it doesn't exist
    RefineUIPositions[layoutName] = RefineUIPositions[layoutName] or {}

    -- Apply saved positions to all registered frames
    for frameName, frameData in pairs(RefineUIPositions[layoutName]) do
        local frame = _G[frameName]
        if frame then
            frame:ClearAllPoints()
            frame:SetPoint(frameData.point, frameData.x, frameData.y)
        end
    end
    -- Also (re)apply default positions for Blizzard systems when using RefineUI
    if layoutName == 'RefineUI' then
        pcall(function()
            PositionRefineUILayout()
            LibEditModeOverride:SaveOnly()
        end)
    end
end)


local function ConfigureRefineUILayout()
    LibEditModeOverride:LoadLayouts()
    if LibEditModeOverride:GetActiveLayout() == "RefineUI" then
        -- Set HideBarArt for MainBar
        LibEditModeOverride:SetFrameSetting(MainMenuBar, Enum.EditModeActionBarSetting.HideBarArt, 1)
        
        -- Set HideBarScrolling for MainBar
        LibEditModeOverride:SetFrameSetting(MainMenuBar, Enum.EditModeActionBarSetting.HideBarScrolling, 1)
        
        -- Set VisibleSetting to Hidden for ExtraBar1, ExtraBar2, and ExtraBar3
        LibEditModeOverride:SetFrameSetting(MultiBar5, Enum.EditModeActionBarSetting.VisibleSetting, Enum.ActionBarVisibleSetting.Hidden)
        LibEditModeOverride:SetFrameSetting(MultiBar6, Enum.EditModeActionBarSetting.VisibleSetting, Enum.ActionBarVisibleSetting.Hidden)
        LibEditModeOverride:SetFrameSetting(MultiBar7, Enum.EditModeActionBarSetting.VisibleSetting, Enum.ActionBarVisibleSetting.Hidden)
    end
end

local function SafeReanchor(frameName, pos)
    local frame = type(frameName) == 'string' and _G[frameName] or frameName
    if not frame or not pos then return end
    -- Prefer EditMode-aware positioning when available
    local okHas, has = pcall(function() return LibEditModeOverride:HasEditModeSettings(frame) end)
    if okHas and has then
        pcall(function() LibEditModeOverride:ReanchorFrame(frame, unpack(pos)) end)
    else
        -- Fallback direct anchoring for frames not managed by Edit Mode
        pcall(function()
            frame:ClearAllPoints()
            frame:SetPoint(pos[1], pos[2], pos[3], pos[4], pos[5])
        end)
    end
end

local function PositionRefineUILayout()
    LibEditModeOverride:LoadLayouts()
    if LibEditModeOverride:GetActiveLayout() ~= "RefineUI" then return end
    -- Blizzard EditMode-managed systems
    SafeReanchor('MinimapCluster', C.position.minimap)
    SafeReanchor('MainMenuBar', C.position.mainBar)
    SafeReanchor('MultiBarBottomLeft', C.position.multiBarBottomLeft)
    SafeReanchor('MultiBarBottomRight', C.position.multiBarBottomRight)
    SafeReanchor('MultiBarRight', C.position.multiBarRight)
    SafeReanchor('MultiBarLeft', C.position.multiBarLeft)
    -- Extra bars if present
    SafeReanchor('MultiBar5', C.position.multiBar5)
    SafeReanchor('MultiBar6', C.position.multiBar6)
    SafeReanchor('MultiBar7', C.position.multiBar7)
    SafeReanchor('MainMenuBarVehicleLeaveButton', C.position.vehicle)
    SafeReanchor('PetActionBar', C.position.petBar)
    SafeReanchor('StanceBar', C.position.stanceBar)
    SafeReanchor('MicroMenuContainer', C.position.microMenu)
    SafeReanchor('ObjectiveTrackerFrame', C.position.objectiveTracker)
    -- Widgets and zone button systems
    SafeReanchor('StatusTrackingBarManager', C.position.experienceBar)
    SafeReanchor('ZoneAbilityFrame', C.position.zoneButton)
    SafeReanchor('UIWidgetTopCenterContainerFrame', C.position.uiwidgetTop)
    SafeReanchor('UIWidgetBelowMinimapContainerFrame', C.position.uiwidgetBelow)
    -- Non-EditMode frames: fallback to direct anchoring
    SafeReanchor('ChatFrame1', C.position.chat)
    SafeReanchor('GameTooltipDefaultContainer', C.position.tooltip)
end

local function InitializeRefineUILayout()
    if DEBUG then print("RefineUI EditMode: Initializing RefineUI layout...") end
    LibEditModeOverride:LoadLayouts()
    if not LibEditModeOverride:DoesLayoutExist("RefineUI") then
        if DEBUG then print("RefineUI EditMode: Adding layout 'RefineUI'") end
        LibEditModeOverride:AddLayout(Enum.EditModeLayoutType.Account, "RefineUI")
    end
    -- Make RefineUI the active layout and apply our defaults
    LibEditModeOverride:SetActiveLayout("RefineUI")
    PositionRefineUILayout()
    ConfigureRefineUILayout()
    -- Persist the changes without immediately toggling Edit Mode UI
    LibEditModeOverride:SaveOnly()
    if DEBUG then print("RefineUI EditMode: Layout saved and set active") end
    -- Schedule a single, delayed apply once the UI is fully initialized
    ScheduleApplyChanges(1.5)
end

-- Ensure layout creation even if called before the library is "ready"
local function EnsureRefineUILayout(forceReload)
    local retries = 0
    local function try()
        if not LibEditModeOverride or not LibEditModeOverride.IsReady or not LibEditModeOverride:IsReady() then
            retries = retries + 1
            C_Timer.After(0.75, try)
            return
        end
        if DEBUG and retries > 0 then print("RefineUI EditMode: Ready after", retries, "retries") end
        -- Load, create if missing, then verify by reloading
        local ok, err = pcall(function()
            LibEditModeOverride:LoadLayouts()
            if not LibEditModeOverride:DoesLayoutExist("RefineUI") then
                if DEBUG then print("RefineUI EditMode: Creating 'RefineUI' layout") end
                LibEditModeOverride:AddLayout(Enum.EditModeLayoutType.Account, "RefineUI")
                LibEditModeOverride:SaveOnly()
                -- Refresh in-memory layouts and verify
                LibEditModeOverride:LoadLayouts()
            end
            -- Activate and configure regardless
            LibEditModeOverride:SetActiveLayout("RefineUI")
            PositionRefineUILayout()
            ConfigureRefineUILayout()
            LibEditModeOverride:SaveOnly()
            if forceReload then
                -- Ensure everything initializes cleanly under the new layout
                ReloadUI()
                return
            end
            ScheduleApplyChanges(1.0)
            -- Run a couple of delayed passes to catch late-created frames
            C_Timer.After(1.0, function()
                pcall(function()
                    PositionRefineUILayout()
                    LibEditModeOverride:SaveOnly()
                end)
            end)
            C_Timer.After(2.0, function()
                pcall(function()
                    PositionRefineUILayout()
                    LibEditModeOverride:SaveOnly()
                end)
            end)
        end)
        if not ok and DEBUG then print("RefineUI EditMode: EnsureRefineUILayout error:", err) end
    end
    try()
end

-- Popups to guide creating or switching to the RefineUI layout
StaticPopupDialogs["REFINEUI_CREATE_LAYOUT"] = {
    text = "RefineUI Edit Mode layout is missing. Create and use it now?",
    button1 = "Create & Use",
    button2 = "Cancel",
    OnAccept = function()
        -- Creating and switching to a new layout benefits from a clean reload
        EnsureRefineUILayout(true)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["REFINEUI_SWITCH_LAYOUT"] = {
    text = "Switch to the RefineUI Edit Mode layout now?",
    button1 = "Use",
    button2 = "Cancel",
    OnAccept = function()
        EnsureRefineUILayout()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        local function proceed()
            if not LibEditModeOverride or not LibEditModeOverride.IsReady or not LibEditModeOverride:IsReady() then
                C_Timer.After(0.75, proceed)
                return
            end
            LibEditModeOverride:LoadLayouts()
            local exists = LibEditModeOverride:DoesLayoutExist("RefineUI")
            local active = LibEditModeOverride:GetActiveLayout()
            if not exists then
                StaticPopup_Show("REFINEUI_CREATE_LAYOUT")
            elseif active ~= "RefineUI" then
                -- Force switch and apply with a slight delay to avoid fragile early paths
                LibEditModeOverride:SetActiveLayout("RefineUI")
                PositionRefineUILayout()
                ConfigureRefineUILayout()
                LibEditModeOverride:SaveOnly()
                -- Apply shortly after to give Blizzard systems time to init
                ScheduleApplyChanges(1.5)
                C_Timer.After(2.5, function()
                    pcall(function()
                        PositionRefineUILayout()
                        LibEditModeOverride:SaveOnly()
                        ScheduleApplyChanges(0.5)
                    end)
                end)
            else
                -- Already using RefineUI; reanchor frames and enforce settings
                PositionRefineUILayout()
                ConfigureRefineUILayout()
                LibEditModeOverride:SaveOnly()
                -- Apply with slight delay to avoid BuffFrame/EditMode early teardown errors
                ScheduleApplyChanges(1.5)
                -- One delayed pass to catch late-created frames and re-apply
                C_Timer.After(2.5, function()
                    pcall(function()
                        PositionRefineUILayout()
                        LibEditModeOverride:SaveOnly()
                        ScheduleApplyChanges(0.5)
                    end)
                end)
            end
            self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        end
        proceed()
    end
end)

if _G['DetailsBaseFrame1'] then _G['DetailsBaseFrame1']:SetSize(300, 279) end

-- local framesToReanchor = {
--     { "MinimapCluster",                 C.position.minimap },
--     { "MainMenuBar",                    C.position.mainBar },
--     { "MultiBarBottomLeft",             C.position.multiBarBottomLeft },
--     { "MultiBarBottomRight",            C.position.multiBarBottomRight },
--     { "MultiBarRight",                  C.position.multiBarRight },
--     { "MultiBarLeft",                   C.position.multiBarLeft },
--     { "MainMenuBarVehicleLeaveButton",  C.position.vehicle },
--     { "PetActionBar",                   C.position.petBar },
--     { "StanceBar",                      C.position.stanceBar },
--     { "MicroMenuContainer",             C.position.microMenu },
--     { "ObjectiveTrackerFrame",          C.position.objectiveTracker },
--     { "ChatFrame1",                     C.position.chat },
--     { "GameTooltipDefaultContainer",    C.position.tooltip },
--     { "RefineUI_ExperienceBarAnchor",   C.position.experienceBar },
--     { "RefineUI_Player",                C.position.unitframes.player },
--     { "RefineUI_Target",                C.position.unitframes.target },
--     { "ZoneAbilityFrame",               C.position.zoneButton },
--     { "UIWidgetPowerBarContainerFrame", C.position.uiwidgetTop },
--     { "VigorBar",                       C.position.uiwidgetTop },
--     { "DetailsBaseFrame1",              C.position.details },
-- }


-- local function InitializeRefineUILayout()
--     LibEditModeOverride:LoadLayouts()
--     if not LibEditModeOverride:DoesLayoutExist("RefineUI") then
--         LibEditModeOverride:AddLayout(Enum.EditModeLayoutType.Account, "RefineUI")
--         LibEditModeOverride:ApplyChanges()
--     end

--     if LibEditModeOverride:GetActiveLayout() == "RefineUI" then
--         print("Reanchoring frames")
--         for _, frameInfo in ipairs(framesToReanchor) do
--             local frame = _G[frameInfo[1]]
--             if frame then
--                 pcall(function()
--                     LibEditModeOverride:ReanchorFrame(frame, unpack(frameInfo[2]))
--                 end)
--             end
--         end
--     end
-- end



-- -- Table to store frame configurations
-- local editModeFrames = {}

-- -- Function to get position from C.position
-- local function GetPosition(positionPath)
--     local position = C.position
--     for _, key in ipairs(positionPath) do
--         position = position[key]
--         if not position then return nil end
--     end
--     return position
-- end

-- -- Function to convert position table to LibEditMode format
-- local function ConvertPosition(positionTable)
--     return {
--         point = positionTable[1],
--         relativePoint = positionTable[2],
--         x = positionTable[4],
--         y = positionTable[5]
--     }
-- end

-- -- Function to add a frame to the edit mode system
-- local function AddEditModeFrame(frameName, frame, positionPath)
--     local position = GetPosition(positionPath)
--     if not position then
--         print("Warning: Position not found for " .. frameName)
--         return
--     end

--     editModeFrames[frameName] = {
--         frame = frame,
--         defaultPosition = ConvertPosition(position),
--         positionPath = positionPath
--     }
-- end

-- RefineUIPositions = RefineUIPositions or {}

-- -- Function to initialize all added frames with LibEditMode
-- local function InitializeEditModeFrames()
--     for frameName, frameConfig in pairs(editModeFrames) do
--         local frame = frameConfig.frame
--         local defaultPosition = frameConfig.defaultPosition

--         local function onPositionChanged(_, layoutName, point, x, y)
--             if not RefineUIPositions[frameName] then
--                 RefineUIPositions[frameName] = {}
--             end
--             RefineUIPositions[frameName][layoutName] = {point = point, x = x, y = y}
--         end

--         LEM:AddFrame(frame, onPositionChanged, defaultPosition)

--         LEM:RegisterCallback('layout', function(layoutName)
--             if not RefineUIPositions[frameName] then
--                 RefineUIPositions[frameName] = {}
--             end
--             if not RefineUIPositions[frameName][layoutName] then
--                 RefineUIPositions[frameName][layoutName] = CopyTable(defaultPosition)
--             end

--             local savedPosition = RefineUIPositions[frameName][layoutName]
--             frame:ClearAllPoints()
--             frame:SetPoint(savedPosition.point, UIParent, savedPosition.point, savedPosition.x, savedPosition.y)
--         end)
--     end

--     -- Additional callbacks (enter, exit) remain the same
-- end

-- -- Example usage:
-- AddEditModeFrame('Player', _G['RefineUI_Player'], {'unitframes', 'player'})
-- AddEditModeFrame('Target', _G['RefineUI_Target'], {'unitframes', 'target'})
-- AddEditModeFrame('Details', _G['DetailsBaseFrame1'], {'details'})
-- AddEditModeFrame('ZoneAbility', _G['ZoneAbilityFrame'], {'zoneButton'})
-- AddEditModeFrame('UIWidget', _G['UIWidgetPowerBarContainerFrame'], {'uiwidgetTop'})
-- AddEditModeFrame('VigorBar', _G['VigorBar'], {'uiwidgetTop'})




-- -- Initialize all added frames with LibEditMode
-- InitializeEditModeFrames()

-- local function ResetAllFrames()
--     for frameName, frameConfig in pairs(editModeFrames) do
--         local defaultPosition = frameConfig.defaultPosition

--         -- Reset saved positions
--         RefineUIPositions[frameName] = {
--             ["RefineUI"] = {  -- Assuming "RefineUI" is your layout name
--                 point = defaultPosition.point,
--                 relativePoint = defaultPosition.relativePoint,
--                 x = defaultPosition.x,
--                 y = defaultPosition.y
--             }
--         }
--     end

--     print("All frame positions have been reset to default in settings.")
--     print("Please reload your UI to apply the changes.")

--     -- Show reload UI popup
--     StaticPopup_Show("REFINEUI_RESET_RELOAD")
-- end

-- StaticPopupDialogs["REFINEUI_RESET_RELOAD"] = {
--     text = "Frame positions have been reset to default. Reload UI to apply changes?",
--     button1 = "Reload UI",
--     button2 = "Later",
--     OnAccept = function()
--         ReloadUI()
--     end,
--     timeout = 0,
--     whileDead = true,
--     hideOnEscape = true,
--     preferredIndex = 3,
-- }

-- -- Slash command to reset frames
-- SLASH_RESETUF1 = "/resetuf"
-- SlashCmdList["RESETUF"] = function(msg)
--     ResetAllFrames()
-- end

-- Simple slash to (re)create/select and apply the RefineUI layout on demand
SLASH_REFINEUILAYOUT1 = "/refineuilayout"
SlashCmdList["REFINEUILAYOUT"] = function()
    EnsureRefineUILayout()
end

-- local function ApplyLayoutChanges()
--     local layoutName = "RefineUI"
--     local LibEditModeOverride = LibStub("LibEditModeOverride-1.0")
--     local layoutExists = LibEditModeOverride:DoesLayoutExist(layoutName)

--     print("Checking for RefineUI layout...")
--     print("Layout exists:", layoutExists)

--     if not layoutExists then
--         print("RefineUI layout doesn't exist. Creating layout and reinstalling UI...")
--         local success, errorMsg = pcall(function()
--             LibEditModeOverride:AddLayout(Enum.EditModeLayoutType.Account, layoutName)
--         end)

--         if not success then
--             print("Error creating layout:", errorMsg)
--             return
--         end

--         print("Layout created successfully.")
--         -- Trigger UI installation
--         -- This will cause a reload, so we don't need to continue execution
--         return
--     end

--     LibEditModeOverride:LoadLayouts()
--     LibEditModeOverride:SetActiveLayout(layoutName)

--     local framesToReanchor = {
--         {"MinimapCluster", C.position.minimap},
--         {"MainMenuBar", C.position.mainBar},
--         {"MultiBarBottomLeft", C.position.multiBarBottomLeft},
--         {"MultiBarBottomRight", C.position.multiBarBottomRight},
--         {"MultiBarRight", C.position.multiBarRight},
--         {"MultiBarLeft", C.position.multiBarLeft},
--         {"MainMenuBarVehicleLeaveButton", C.position.vehicle},
--         {"PetActionBar", C.position.petBar},
--         {"StanceBar", C.position.stanceBar},
--         {"MicroMenuContainer", C.position.microMenu},
--         {"ObjectiveTrackerFrame", C.position.objectiveTracker},
--         {"ChatFrame1", C.position.chat},
--         {"GameTooltipDefaultContainer", C.position.tooltip},
--         {"RefineUI_ExperienceBarAnchor", C.position.experienceBar},
--         {"RefineUI_Player", C.position.unitframes.player},
--         {"RefineUI_Target", C.position.unitframes.target},
--         {"ZoneAbilityFrame", C.position.zoneButton},
--         {"UIWidgetPowerBarContainerFrame", C.position.uiwidgetTop},
--         {"VigorBar", C.position.uiwidgetTop},
--         {"DetailsBaseFrame1", C.position.details},
--     }

--     for _, frameInfo in ipairs(framesToReanchor) do
--         local frame = _G[frameInfo[1]]
--         if frame then
--             pcall(function()
--                 LibEditModeOverride:ReanchorFrame(frame, unpack(frameInfo[2]))
--             end)
--         end
--     end

--     _G["DetailsBaseFrame1"]:SetHeight(280)
--     _G["DetailsBaseFrame1"]:SetWidth(300)

--     LibEditModeOverride:ApplyChanges()
--     print("Layout changes applied successfully.")
-- end

-- local function InitializeEditMode()
--     if LibEditModeOverride:IsReady() then
--         LibEditModeOverride:LoadLayouts()
--         InitializeEditModeFrames()
--         ApplyLayoutChanges()
--     end
-- end

-- C_Timer.After(1, function()
--     local success, error = pcall(InitializeEditMode)
--     if not success then
--         print("Error in InitializeEditMode:", error)
--     end
-- end)
