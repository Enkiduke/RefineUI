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
local Colors = RefineUI.Colors
local Locale = RefineUI.Locale

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local C_AddOns = C_AddOns
local C_Timer = C_Timer
local CreateFrame = CreateFrame
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
    ADDON_LOADED = COMPONENT_KEY .. ":ADDON_LOADED",
    PLAYER_ENTERING_WORLD = COMPONENT_KEY .. ":PLAYER_ENTERING_WORLD",
    COMBAT_SESSION_UPDATED = COMPONENT_KEY .. ":DAMAGE_METER_COMBAT_SESSION_UPDATED",
    CURRENT_SESSION_UPDATED = COMPONENT_KEY .. ":DAMAGE_METER_CURRENT_SESSION_UPDATED",
    RESET = COMPONENT_KEY .. ":DAMAGE_METER_RESET",
}

local HOOK_KEY = {
    SESSION_WINDOW_ON_SHOW = COMPONENT_KEY .. ":DamageMeterSessionWindowMixin:OnShow",
    SOURCE_WINDOW_ON_SHOW = COMPONENT_KEY .. ":DamageMeterSourceWindowMixin:OnShow",
}

local STATE_KEY = {
    SKIN_PASS_QUEUED = COMPONENT_KEY .. ":skinPassQueued",
    UPDATE_EVENTS_REGISTERED = COMPONENT_KEY .. ":updateEventsRegistered",
    SKINNER_STARTED = COMPONENT_KEY .. ":skinnerStarted",
}

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
        statusBar.Name:SetTextColor(1, 1, 1, 1)
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
        SetState(frame, "entrySkinned", true)
    end

    LayoutEntry(frame, statusBar)
end

local function SkinScrollTargetChildren(scrollBox)
    local scrollTarget = scrollBox and scrollBox.ScrollTarget
    if not CanSkinObject(scrollTarget) then
        return
    end

    local children = { scrollTarget:GetChildren() }
    for i = 1, #children do
        local child = children[i]
        if child and child.StatusBar and child.Icon then
            SkinDamageMeterEntry(child)
        end
    end
end

local function SkinDamageMeterWindow(window)
    if not CanSkinObject(window) then
        return
    end

    if not GetState(window, "windowSkinned", false) then
        if window.Background then
            window.Background:SetAlpha(0)
            window.Background:Hide()
        end

        local sourceWindow = window.SourceWindow
        if sourceWindow and sourceWindow.Background then
            sourceWindow.Background:SetAlpha(0)
            sourceWindow.Background:Hide()
        end

        if window.ShowBackground then
            window.ShowBackground:Stop()
        end

        SetState(window, "windowSkinned", true)
    end

    if window.LocalPlayerEntry then
        SkinDamageMeterEntry(window.LocalPlayerEntry)
    end

    SkinScrollTargetChildren(window.ScrollBox)
    if window.SourceWindow and window.SourceWindow.ScrollBox then
        SkinScrollTargetChildren(window.SourceWindow.ScrollBox)
    end
end

local function SkinExistingWindows()
    for i = 1, 3 do
        local window = _G["DamageMeterSessionWindow" .. i]
        if window then
            SkinDamageMeterWindow(window)
        end
    end
end

local function ForceSkinPass()
    SkinExistingWindows()
end

local function QueueSkinPass()
    if GetState(Skins, STATE_KEY.SKIN_PASS_QUEUED, false) then
        return
    end

    SetState(Skins, STATE_KEY.SKIN_PASS_QUEUED, true)
    C_Timer.After(0, function()
        SetState(Skins, STATE_KEY.SKIN_PASS_QUEUED, false)
        ForceSkinPass()
    end)
end

local function HookMixins()
    if _G.DamageMeterSessionWindowMixin then
        RefineUI:HookOnce(HOOK_KEY.SESSION_WINDOW_ON_SHOW, _G.DamageMeterSessionWindowMixin, "OnShow", function()
            QueueSkinPass()
        end)
    end

    if _G.DamageMeterSourceWindowMixin then
        RefineUI:HookOnce(HOOK_KEY.SOURCE_WINDOW_ON_SHOW, _G.DamageMeterSourceWindowMixin, "OnShow", function()
            QueueSkinPass()
        end)
    end
end

local function RegisterDamageMeterUpdateEvents()
    if GetState(Skins, STATE_KEY.UPDATE_EVENTS_REGISTERED, false) then
        return
    end
    SetState(Skins, STATE_KEY.UPDATE_EVENTS_REGISTERED, true)

    local function Queue()
        QueueSkinPass()
    end

    RefineUI:RegisterEventCallback("DAMAGE_METER_COMBAT_SESSION_UPDATED", Queue, EVENT_KEY.COMBAT_SESSION_UPDATED)
    RefineUI:RegisterEventCallback("DAMAGE_METER_CURRENT_SESSION_UPDATED", Queue, EVENT_KEY.CURRENT_SESSION_UPDATED)
    RefineUI:RegisterEventCallback("DAMAGE_METER_RESET", Queue, EVENT_KEY.RESET)
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function Skins:StartDamageMeterSkinner()
    if GetState(Skins, STATE_KEY.SKINNER_STARTED, false) then
        return
    end

    SetState(Skins, STATE_KEY.SKINNER_STARTED, true)
    RefineUI:OffEvent("ADDON_LOADED", EVENT_KEY.ADDON_LOADED)

    HookMixins()
    RegisterDamageMeterUpdateEvents()

    QueueSkinPass()
    C_Timer.After(0.25, QueueSkinPass)
    C_Timer.After(1, QueueSkinPass)
    C_Timer.After(2, QueueSkinPass)

    RefineUI:RegisterEventCallback("PLAYER_ENTERING_WORLD", function()
        C_Timer.After(0.1, QueueSkinPass)
        C_Timer.After(0.6, QueueSkinPass)
    end, EVENT_KEY.PLAYER_ENTERING_WORLD)
end

function Skins:InitDamageMeterSkinner()
    if C_AddOns.IsAddOnLoaded("Blizzard_DamageMeter") then
        self:StartDamageMeterSkinner()
    else
        RefineUI:RegisterEventCallback("ADDON_LOADED", function(_, addon)
            if addon == "Blizzard_DamageMeter" then
                self:StartDamageMeterSkinner()
            end
        end, EVENT_KEY.ADDON_LOADED)
    end
end
