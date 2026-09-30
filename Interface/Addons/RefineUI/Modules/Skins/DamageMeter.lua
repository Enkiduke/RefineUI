----------------------------------------------------------------------------------------
-- Skins Component: Damage Meter
-- Description: Skins Blizzard Damage Meter windows/entries.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Skins = RefineUI:GetModule("Skins")
if not Skins then
    return
end

----------------------------------------------------------------------------------------
-- Shared Aliases
----------------------------------------------------------------------------------------
local Config = RefineUI.Config
local Media = RefineUI.Media

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local CreateFrame = CreateFrame
local hooksecurefunc = hooksecurefunc
local type = type

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local COMPONENT_KEY = "Skins:DamageMeter"
local DAMAGE_METER_SKIN_STATE_REGISTRY = "SkinsDamageMeterState"
local DAMAGE_METER_BAR_HEIGHT = 12
local DAMAGE_METER_TEXT_SIZE = 11
local DAMAGE_METER_BAR_TEXTURE = (Media and Media.Textures and Media.Textures.Smooth) or (Media and Media.Textures and Media.Textures.Statusbar)

local EVENT_KEY = {
    PLAYER_ENTERING_WORLD = COMPONENT_KEY .. ":PLAYER_ENTERING_WORLD",
    RESET = COMPONENT_KEY .. ":DAMAGE_METER_RESET",
    COMBAT_START = COMPONENT_KEY .. ":PLAYER_REGEN_DISABLED",
    BOSS_PULL = COMPONENT_KEY .. ":ENCOUNTER_START",
}

local HOOK_KEY = {
    SETUP_SESSION_WINDOW = COMPONENT_KEY .. ":DamageMeter:SetupSessionWindow",
}

local TIMER_KEY_SKIN_PASS = COMPONENT_KEY .. ":Timer:SkinPass"

RefineUI:CreateDataRegistry(DAMAGE_METER_SKIN_STATE_REGISTRY, "k")

----------------------------------------------------------------------------------------
-- State Helpers
----------------------------------------------------------------------------------------
local function GetState(owner, key, defaultValue)
    return RefineUI:RegistryGet(DAMAGE_METER_SKIN_STATE_REGISTRY, owner, key, defaultValue)
end

local function SetState(owner, key, value)
    RefineUI:RegistrySet(DAMAGE_METER_SKIN_STATE_REGISTRY, owner, key, value)
end

local QueueSkinPass
local skinPassQueued = false
local lastInstanceID
local lastInstanceDifficulty

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function CanSkinObject(obj)
    if not obj then
        return false
    end
    if obj.IsForbidden and obj:IsForbidden() then
        return false
    end
    return true
end

local function GetConfiguredBorderColor()
    local borderColor = Config and Config.General and Config.General.BorderColor
    local r, g, b, a = 0.3, 0.3, 0.3, 1
    if type(borderColor) == "table" then
        r = borderColor[1] or r
        g = borderColor[2] or g
        b = borderColor[3] or b
        a = borderColor[4] or a
    end
    return r, g, b, a
end

local function EnsureStatusBarBorder(statusBar)
    if not CanSkinObject(statusBar) then
        return
    end

    local border = GetState(statusBar, "borderFrame")
    if not border then
        border = CreateFrame("Frame", nil, statusBar)
        if border and border.EnableMouse then
            border:EnableMouse(false)
        end
        SetState(statusBar, "borderFrame", border)
    end
    if not CanSkinObject(border) then
        return
    end

    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", statusBar, "TOPLEFT", -6, 6)
    border:SetPoint("BOTTOMRIGHT", statusBar, "BOTTOMRIGHT", 6, -6)
    RefineUI.CreateBorder(border, 0, 0, 12)

    local borderVisual = border.border or border
    if borderVisual and borderVisual.SetBackdropBorderColor then
        local r, g, b, a = GetConfiguredBorderColor()
        borderVisual:SetBackdropBorderColor(r, g, b, a)
    end
end

local function EnsureIconSkin(iconFrame)
    if not CanSkinObject(iconFrame) then
        return
    end

    local iconTexture = iconFrame.Icon
    if iconTexture and not GetState(iconFrame, "maskTexture") then
        local mask = iconFrame:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(iconTexture)
        iconTexture:AddMaskTexture(mask)
        SetState(iconFrame, "maskTexture", mask)
    end

    local border = GetState(iconFrame, "borderTexture")
    if not border then
        border = iconFrame:CreateTexture(nil, "OVERLAY", nil, 7)
        border:SetTexture((Media and Media.Textures and Media.Textures.PortraitBorder) or "Interface\\AddOns\\RefineUI\\Media\\Textures\\PortraitBorder.blp")
        RefineUI.Point(border, "TOPLEFT", iconFrame, "TOPLEFT", -6, 6)
        RefineUI.Point(border, "BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", 6, -6)
        SetState(iconFrame, "borderTexture", border)
    end

    if border then
        local r, g, b, a = GetConfiguredBorderColor()
        border:SetDrawLayer("OVERLAY", 7)
        border:SetVertexColor(r, g, b, a)
    end
end

local function UpdateEntryNameColor(frame)
    local color = frame.SetSuppressIcon and frame.classFilename and RAID_CLASS_COLORS[frame.classFilename]
    if color then
        frame.StatusBar.Name:SetTextColor(color.r, color.g, color.b, 1)
    else
        frame.StatusBar.Name:SetTextColor(1, 1, 1, 1)
    end
end

-- Combat values can be secret; leave Blizzard's native text intact in that case.
local function HasSecretValues(frame)
    return issecretvalue(frame.value) or issecretvalue(frame.valuePerSecond) or issecretvalue(frame.sessionTotalValue)
end

-- Runs after every Blizzard UpdateValue. Blizzard's Complete format already shows the
-- percentage, and with the option off Blizzard's text is left untouched.
local function UpdateEntryValueText(frame)
    if not Config.Skins.DamageMeter.ShowPercentage
        or frame:GetNumberDisplayType() == Enum.DamageMeterNumbers.Complete
        or (frame.deathRecapID and frame.deathRecapID ~= 0)
        or HasSecretValues(frame) then
        return
    end

    local value, perSecond, total = frame.value, frame.valuePerSecond, frame.sessionTotalValue
    local mainValue = value or 0
    local secondaryValue
    local perSecondIsPrimary = frame:ShowsValuePerSecondAsPrimary()
    if perSecondIsPrimary then
        mainValue = perSecond or mainValue
    end
    if frame:GetNumberDisplayType() ~= Enum.DamageMeterNumbers.Minimal then
        if perSecondIsPrimary then
            secondaryValue = value or 0
        elseif not frame.suppressValuePerSecond then
            secondaryValue = perSecond or 0
        end
    end

    local text
    if secondaryValue then
        text = DAMAGE_METER_ENTRY_FORMAT_COMPACT:format(AbbreviateLargeNumbers(mainValue), AbbreviateLargeNumbers(secondaryValue))
    else
        text = DAMAGE_METER_ENTRY_FORMAT_MINIMAL:format(AbbreviateLargeNumbers(mainValue))
    end
    local percentage = total and total > 0 and Round((value or 0) / total * 100) or 0
    frame.StatusBar.Value:SetText(("%s [%d%%]"):format(text, percentage))
end

local function LayoutEntry(frame, statusBar)
    if not CanSkinObject(frame) or not CanSkinObject(statusBar) then
        return
    end

    frame:SetClipsChildren(false)
    statusBar:SetStatusBarTexture(DAMAGE_METER_BAR_TEXTURE)

    local baseLevel = frame:GetFrameLevel() or 0
    statusBar:SetFrameLevel(baseLevel + 1)

    local statusBarBorder = GetState(statusBar, "borderFrame")
    if statusBarBorder then
        statusBarBorder:SetFrameStrata(statusBar:GetFrameStrata())
        statusBarBorder:SetFrameLevel(statusBar:GetFrameLevel() + 1)
    end

    local iconFrame = frame.Icon
    local leftOffset = 4
    if iconFrame then
        iconFrame:SetFrameStrata(statusBar:GetFrameStrata())
        iconFrame:SetFrameLevel(statusBar:GetFrameLevel() + 3)
        iconFrame:ClearAllPoints()
        RefineUI.Point(iconFrame, "BOTTOMLEFT", frame, "BOTTOMLEFT", 4, 1)

        if iconFrame:IsShown() then
            leftOffset = 22
        end
    end

    statusBar:ClearAllPoints()
    RefineUI.Point(statusBar, "BOTTOMLEFT", frame, "BOTTOMLEFT", leftOffset, 1)
    RefineUI.Point(statusBar, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    statusBar:SetHeight(RefineUI:Scale(DAMAGE_METER_BAR_HEIGHT))

    if statusBar.Name then
        statusBar.Name:SetDrawLayer("OVERLAY", 7)
        statusBar.Name:ClearAllPoints()
        RefineUI.Point(statusBar.Name, "TOPLEFT", frame, "TOPLEFT", leftOffset + 6, 0)
        RefineUI.Font(statusBar.Name, DAMAGE_METER_TEXT_SIZE)
        UpdateEntryNameColor(frame)
        statusBar.Name:Show()
    end

    if statusBar.Value then
        statusBar.Value:SetDrawLayer("OVERLAY", 7)
        statusBar.Value:ClearAllPoints()
        RefineUI.Point(statusBar.Value, "TOPRIGHT", frame, "TOPRIGHT", -4, -1)
        RefineUI.Font(statusBar.Value, DAMAGE_METER_TEXT_SIZE)
        statusBar.Value:SetTextColor(1, 1, 1, 1)
        statusBar.Value:Show()
    end
end

-- Blizzard's entry Init only updates values, text, icon and color. Row anchors are reset
-- only by UpdateStyle (SetStyle/SetShowBarIcons on row setup or setting changes), so the
-- layout is re-applied only after that instead of on every data update.
local function OnEntryUpdateStyle(frame)
    SetState(frame, "layoutDirty", true)
    QueueSkinPass()
end

local function SkinDamageMeterEntry(frame)
    if not CanSkinObject(frame) then
        return
    end

    local statusBar = frame.StatusBar
    if not CanSkinObject(statusBar) or not statusBar.Name or not statusBar.Value then
        return
    end

    if not GetState(frame, "entrySkinned", false) then
        if not GetState(statusBar, "bgTexture") then
            local bgTexture = statusBar:CreateTexture(nil, "BACKGROUND")
            bgTexture:SetAllPoints()
            bgTexture:SetTexture(DAMAGE_METER_BAR_TEXTURE)
            bgTexture:SetVertexColor(0, 0, 0, 0.5)
            SetState(statusBar, "bgTexture", bgTexture)
        end

        EnsureStatusBarBorder(statusBar)
        EnsureIconSkin(frame.Icon)
        if frame.SetSuppressIcon then
            hooksecurefunc(frame, "UpdateName", UpdateEntryNameColor)
            hooksecurefunc(frame, "UpdateValue", UpdateEntryValueText)
        end
        if frame.UpdateStyle then
            hooksecurefunc(frame, "UpdateStyle", OnEntryUpdateStyle)
        end
        SetState(frame, "entrySkinned", true)
        SetState(frame, "layoutDirty", true)
        SetState(frame, "showPercentage", false)
    end

    if GetState(frame, "layoutDirty", false) then
        SetState(frame, "layoutDirty", false)
        LayoutEntry(frame, statusBar)
    end

    -- Re-render after the option changes; Blizzard's UpdateValue restores its own text and
    -- the hook above re-applies the percentage when enabled.
    local showPercentage = Config.Skins.DamageMeter.ShowPercentage
    if frame.SetSuppressIcon and GetState(frame, "showPercentage") ~= showPercentage then
        SetState(frame, "showPercentage", showPercentage)
        if not HasSecretValues(frame) then
            frame:UpdateValue()
        end
    end
end

local function SkinScrollBoxEntry(frame)
    if frame.StatusBar and frame.Icon then
        SkinDamageMeterEntry(frame)
    end
end

-- Visits only the rows currently in use, without building a child table per pass.
local function SkinScrollTargetChildren(scrollBox)
    if CanSkinObject(scrollBox) and scrollBox.ForEachFrame then
        scrollBox:ForEachFrame(SkinScrollBoxEntry)
    end
end

local function IsShownWindow(window)
    return CanSkinObject(window) and window.IsShown and window:IsShown()
end

local function HookWindow(window)
    if not CanSkinObject(window) or GetState(window, "windowHooked", false) then
        return
    end

    -- Refresh is not hooked: it runs on every combat session update. New rows arrive through
    -- the acquired-frame callback and style resets through each entry's UpdateStyle hook.
    window:HookScript("OnShow", QueueSkinPass)
    ScrollUtil.AddAcquiredFrameCallback(window:GetScrollBox(), QueueSkinPass, Skins)
    SetState(window, "windowHooked", true)
end

local function SkinDamageMeterSourceWindow(window)
    HookWindow(window)
    if not IsShownWindow(window) then
        return
    end

    if not GetState(window, "windowSkinned", false) then
        if window.Background then
            window.Background:SetAlpha(0)
            window.Background:Hide()
        end

        if window.ShowBackground then
            window.ShowBackground:Stop()
        end

        SetState(window, "windowSkinned", true)
    end

    SkinScrollTargetChildren(window:GetScrollBox())
end

local function SkinDamageMeterWindow(window)
    if not CanSkinObject(window) then
        return
    end

    HookWindow(window)
    local sourceWindow = window:GetSourceWindow()
    SkinDamageMeterSourceWindow(sourceWindow)

    if not IsShownWindow(window) then
        return
    end

    if not GetState(window, "windowSkinned", false) then
        local background = window:GetBackground()
        if background then
            background:SetAlpha(0)
            background:Hide()
        end

        if sourceWindow and sourceWindow.Background then
            sourceWindow.Background:SetAlpha(0)
            sourceWindow.Background:Hide()
        end

        if window.ShowBackground then
            window.ShowBackground:Stop()
        end

        SetState(window, "windowSkinned", true)
    end

    local localPlayerEntry = window:GetLocalPlayerEntry()
    if localPlayerEntry then
        SkinDamageMeterEntry(localPlayerEntry)
    end

    SkinScrollTargetChildren(window:GetScrollBox())
end

local function SkinExistingWindows()
    for i = 1, 3 do
        local window = _G["DamageMeterSessionWindow" .. i]
        if window then
            SkinDamageMeterWindow(window)
        end
    end
end

local function RunSkinPass()
    skinPassQueued = false
    SkinExistingWindows()
end

QueueSkinPass = function()
    if skinPassQueued then
        return
    end

    skinPassQueued = true
    RefineUI:After(TIMER_KEY_SKIN_PASS, 0, RunSkinPass)
end

local function RegisterDamageMeterUpdateEvents()
    RefineUI:RegisterEventCallback("DAMAGE_METER_RESET", QueueSkinPass, EVENT_KEY.RESET)
    RefineUI:RegisterEventCallback("PLAYER_REGEN_DISABLED", function()
        if Config.Skins.DamageMeter.AutoResetCombat then
            C_DamageMeter.ResetAllCombatSessions()
        end
    end, EVENT_KEY.COMBAT_START)
    RefineUI:RegisterEventCallback("ENCOUNTER_START", function()
        if Config.Skins.DamageMeter.AutoResetBoss then
            C_DamageMeter.ResetAllCombatSessions()
        end
    end, EVENT_KEY.BOSS_PULL)
end

local function UpdateInstanceReset(isInitialLogin, isReloadingUi)
    local _, instanceType, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
    local isInstance = instanceType == "party" or instanceType == "raid"
        or instanceType == "scenario" or instanceType == "pvp" or instanceType == "arena"
    if isInstance then
        if not isInitialLogin and not isReloadingUi
            and (instanceID ~= lastInstanceID or difficultyID ~= lastInstanceDifficulty)
            and Config.Skins.DamageMeter.AutoResetInstance then
            C_DamageMeter.ResetAllCombatSessions()
        end
        lastInstanceID = instanceID
        lastInstanceDifficulty = difficultyID
    else
        lastInstanceID = nil
        lastInstanceDifficulty = nil
    end
end

local function RegisterDamageMeterSettings()
    local lib = RefineUI.LibEditMode
    if not lib then
        return
    end

    local settings = {}
    local resetOptions = {
        { key = "AutoResetCombat", name = "Auto-Reset on Combat Start", desc = "Clear all recorded sessions when you enter combat." },
        { key = "AutoResetBoss", name = "Auto-Reset on Boss Pull", desc = "Clear all recorded sessions when a boss encounter starts." },
        { key = "AutoResetInstance", name = "Auto-Reset on Entering Instance", desc = "Clear all recorded sessions when entering a dungeon, raid, scenario, battleground, or arena. Login and reload do not reset sessions." },
    }
    for _, option in ipairs(resetOptions) do
        local key = option.key
        settings[#settings + 1] = {
            kind = lib.SettingType.Checkbox,
            name = option.name,
            desc = option.desc,
            default = false,
            get = function()
                return Config.Skins.DamageMeter[key]
            end,
            set = function(_, value)
                Config.Skins.DamageMeter[key] = value
            end,
        }
    end
    settings[#settings + 1] = {
        kind = lib.SettingType.Checkbox,
        name = "Show Percentage",
        desc = "Show each player's share of the session total with any number format. When combat values are secret, Blizzard's native number format is used.",
        get = function()
            return Config.Skins.DamageMeter.ShowPercentage
        end,
        set = function(_, value)
            Config.Skins.DamageMeter.ShowPercentage = value
            QueueSkinPass()
        end,
    }
    lib:AddSystemSettings(Enum.EditModeSystem.DamageMeter, settings)
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
local function StartDamageMeterSkinner()
    -- Windows created later pass through SetupSessionWindow; existing ones are hooked by
    -- the first pass and restyle themselves on show.
    RefineUI:HookOnce(HOOK_KEY.SETUP_SESSION_WINDOW, _G.DamageMeter, "SetupSessionWindow", QueueSkinPass)
    RegisterDamageMeterUpdateEvents()
    RegisterDamageMeterSettings()
    UpdateInstanceReset(true, false)
    QueueSkinPass()

    RefineUI:RegisterEventCallback("PLAYER_ENTERING_WORLD", function(_, isInitialLogin, isReloadingUi)
        UpdateInstanceReset(isInitialLogin, isReloadingUi)
    end, EVENT_KEY.PLAYER_ENTERING_WORLD)
end

function Skins:InitDamageMeterSkinner()
    EventUtil.ContinueOnAddOnLoaded("Blizzard_DamageMeter", StartDamageMeterSkinner)
end
