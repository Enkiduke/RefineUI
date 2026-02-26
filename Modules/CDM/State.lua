----------------------------------------------------------------------------------------
-- CDM Component: State
-- Description: External state registry helpers and reload recommendation prompt UI.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local CDM = RefineUI:GetModule("CDM")
if not CDM then
    return
end

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config
local Media = RefineUI.Media
local Colors = RefineUI.Colors
local Locale = RefineUI.Locale

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local type = type
local CreateFrame = CreateFrame
local UIParent = UIParent
local ReloadUI = ReloadUI

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function CDM:StateGet(owner, key, defaultValue)
    return RefineUI:RegistryGet(self.STATE_REGISTRY, owner, key, defaultValue)
end

function CDM:StateSet(owner, key, value)
    return RefineUI:RegistrySet(self.STATE_REGISTRY, owner, key, value)
end

function CDM:StateClear(owner, key)
    return RefineUI:RegistryClear(self.STATE_REGISTRY, owner, key)
end

function CDM:MarkReloadRecommendationPending()
    self.reloadRecommendationPending = true
end

function CDM:ShowReloadRecommendationPrompt()
    if self.ReloadPrompt then
        self.ReloadPrompt:Show()
        return
    end

    local frame = CreateFrame("Frame", "RefineUI_CDM_ReloadPrompt", UIParent)
    RefineUI:AddAPI(frame)
    frame:Size(360, 150)
    frame:Point("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetTemplate("Transparent")
    frame:EnableMouse(true)

    local header = CreateFrame("Frame", nil, frame)
    RefineUI:AddAPI(header)
    header:Size(360, 26)
    header:Point("TOP", frame, "TOP", 0, 0)
    header:SetTemplate("Overlay")

    local title = header:CreateFontString(nil, "OVERLAY")
    RefineUI:AddAPI(title)
    title:Font(14, nil, nil, true)
    title:SetPoint("CENTER", header, "CENTER", 0, 0)
    title:SetText("Cooldown Settings Updated")
    title:SetTextColor(1, 0.82, 0)

    local message = frame:CreateFontString(nil, "OVERLAY")
    RefineUI:AddAPI(message)
    message:Font(12, nil, nil, true)
    message:SetPoint("TOP", header, "BOTTOM", 0, -15)
    message:SetWidth(330)
    message:SetText("A UI reload is recommended after changing\ntracked cooldown aura settings.")

    local reloadButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    RefineUI:AddAPI(reloadButton)
    reloadButton:Size(110, 26)
    reloadButton:Point("BOTTOMRIGHT", frame, "BOTTOM", -12, 15)
    reloadButton:SkinButton()
    reloadButton:SetText("Reload")
    reloadButton:SetScript("OnClick", function()
        ReloadUI()
    end)

    local laterButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    RefineUI:AddAPI(laterButton)
    laterButton:Size(110, 26)
    laterButton:Point("BOTTOMLEFT", frame, "BOTTOM", 12, 15)
    laterButton:SkinButton()
    laterButton:SetText("Later")
    laterButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    self.ReloadPrompt = frame
end

function CDM:ShowReloadRecommendationIfPending()
    if not self.reloadRecommendationPending then
        return
    end

    self.reloadRecommendationPending = nil
    self:ShowReloadRecommendationPrompt()
end
