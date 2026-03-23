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
local InCombatLockdown = InCombatLockdown

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

function CDM:SetPendingPostReloadSettingsOpen(mode, displayMode)
    local cfg = self.GetConfig and self:GetConfig() or nil
    if type(cfg) ~= "table" then
        return
    end

    if mode ~= "blizzard" and mode ~= "refineui" then
        cfg.PendingPostReloadSettingsOpen = nil
        return
    end

    local request = {
        mode = mode,
    }

    if displayMode == "spells" or displayMode == "auras" then
        request.displayMode = displayMode
    end

    cfg.PendingPostReloadSettingsOpen = request
end

function CDM:GetPendingPostReloadSettingsOpen()
    local cfg = self.GetConfig and self:GetConfig() or nil
    if type(cfg) ~= "table" or type(cfg.PendingPostReloadSettingsOpen) ~= "table" then
        return nil
    end

    local request = cfg.PendingPostReloadSettingsOpen
    if request.mode ~= "blizzard" and request.mode ~= "refineui" then
        cfg.PendingPostReloadSettingsOpen = nil
        return nil
    end

    return request
end

function CDM:ClearPendingPostReloadSettingsOpen()
    local cfg = self.GetConfig and self:GetConfig() or nil
    if type(cfg) == "table" then
        cfg.PendingPostReloadSettingsOpen = nil
    end
end

function CDM:PrepareReloadRecommendationReload()
    if self.ApplyPendingBlizzardAssignmentSync
        and self.IsRefineRuntimeOwnerActive
        and self:IsRefineRuntimeOwnerActive()
        and self.NeedsBlizzardAssignmentSync
        and self:NeedsBlizzardAssignmentSync()
    then
        if type(InCombatLockdown) == "function" and InCombatLockdown() then
            RefineUI:Print("CDM changes are pending. Leave combat before reloading so Blizzard sync can be saved.")
            return false
        end

        local applied = self:ApplyPendingBlizzardAssignmentSync()
        if not applied and self:NeedsBlizzardAssignmentSync() then
            RefineUI:Print("CDM changes could not be saved to the Blizzard layout yet. Try again out of combat.")
            return false
        end
    end

    return true
end

function CDM:ShowReloadRecommendationPrompt()
    if self.ReloadPrompt then
        self.ReloadPrompt:Show()
        return
    end

    local frame = CreateFrame("Frame", "RefineUI_CDM_ReloadPrompt", UIParent)
    RefineUI:AddAPI(frame)
    frame:Size(400, 182)
    frame:Point("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetTemplate("Transparent")
    frame:EnableMouse(true)

    local header = CreateFrame("Frame", nil, frame)
    RefineUI:AddAPI(header)
    header:Size(400, 26)
    header:Point("TOP", frame, "TOP", 0, 0)
    header:SetTemplate("Overlay")

    local title = header:CreateFontString(nil, "OVERLAY")
    RefineUI:AddAPI(title)
    title:Font(14, nil, nil, true)
    title:SetPoint("CENTER", header, "CENTER", 0, 0)
    title:SetText("Save CDM Changes")
    title:SetTextColor(1, 0.82, 0)

    local message = frame:CreateFontString(nil, "OVERLAY")
    RefineUI:AddAPI(message)
    message:Font(12, nil, nil, true)
    message:SetPoint("TOP", header, "BOTTOM", 0, -15)
    message:SetWidth(360)
    message:SetJustifyH("CENTER")
    message:SetText("Your CDM changes are ready, but they will not be saved until the UI reloads.\n\nReload now to save changes and refresh cooldown tracking.")

    local reloadButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    RefineUI:AddAPI(reloadButton)
    reloadButton:Size(130, 26)
    reloadButton:Point("BOTTOMRIGHT", frame, "BOTTOM", -12, 15)
    reloadButton:SkinButton()
    reloadButton:SetText("Save & Reload")
    reloadButton:SetScript("OnClick", function()
        if CDM.PrepareReloadRecommendationReload and not CDM:PrepareReloadRecommendationReload() then
            return
        end
        ReloadUI()
    end)

    local laterButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    RefineUI:AddAPI(laterButton)
    laterButton:Size(130, 26)
    laterButton:Point("BOTTOMLEFT", frame, "BOTTOM", 12, 15)
    laterButton:SkinButton()
    laterButton:SetText("Keep Editing")
    laterButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    self.ReloadPrompt = frame
end

function CDM:ShowCooldownManagerSwitchPrompt(targetMode, options)
    if targetMode ~= "blizzard" and targetMode ~= "refineui" then
        return
    end

    local modeLabel = targetMode == "blizzard" and "Blizzard CDM" or "RefineUI CDM"
    local frame = self.CooldownManagerSwitchPrompt
    if not frame then
        frame = CreateFrame("Frame", "RefineUI_CDM_SwitchPrompt", UIParent)
        RefineUI:AddAPI(frame)
        frame:Size(380, 162)
        frame:Point("CENTER")
        frame:SetFrameStrata("DIALOG")
        frame:SetTemplate("Transparent")
        frame:EnableMouse(true)

        local header = CreateFrame("Frame", nil, frame)
        RefineUI:AddAPI(header)
        header:Size(380, 26)
        header:Point("TOP", frame, "TOP", 0, 0)
        header:SetTemplate("Overlay")

        local title = header:CreateFontString(nil, "OVERLAY")
        RefineUI:AddAPI(title)
        title:Font(14, nil, nil, true)
        title:SetPoint("CENTER", header, "CENTER", 0, 0)
        title:SetText("Change Cooldown Manager")
        title:SetTextColor(1, 0.82, 0)

        local message = frame:CreateFontString(nil, "OVERLAY")
        RefineUI:AddAPI(message)
        message:Font(12, nil, nil, true)
        message:SetPoint("TOP", header, "BOTTOM", 0, -15)
        message:SetWidth(350)
        frame.Message = message

        local confirmButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        RefineUI:AddAPI(confirmButton)
        confirmButton:Size(130, 26)
        confirmButton:Point("BOTTOMRIGHT", frame, "BOTTOM", -12, 15)
        confirmButton:SkinButton()
        frame.ConfirmButton = confirmButton

        local cancelButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        RefineUI:AddAPI(cancelButton)
        cancelButton:Size(110, 26)
        cancelButton:Point("BOTTOMLEFT", frame, "BOTTOM", 12, 15)
        cancelButton:SkinButton()
        cancelButton:SetText("Cancel")
        cancelButton:SetScript("OnClick", function()
            frame:Hide()
        end)

        confirmButton:SetScript("OnClick", function()
            frame:Hide()
            local requestedMode = frame.requestedMode
            local requestedDisplayMode = frame.requestedDisplayMode
            frame.requestedMode = nil
            frame.requestedDisplayMode = nil
            if requestedMode and CDM.SetAuraMode then
                if CDM.SetPendingPostReloadSettingsOpen then
                    CDM:SetPendingPostReloadSettingsOpen(requestedMode, requestedDisplayMode)
                end
                CDM:SetAuraMode(requestedMode)
                ReloadUI()
            end
        end)

        self.CooldownManagerSwitchPrompt = frame
    end

    frame.requestedMode = targetMode
    frame.requestedDisplayMode = type(options) == "table" and options.displayMode or nil
    frame.Message:SetText("Switch to " .. modeLabel .. "?\nThe UI will reload immediately after the change.")
    frame.ConfirmButton:SetText("Switch & Reload")
    frame:Show()
end

function CDM:RequireReloadForBlizzardIsolation()
    self:MarkReloadRecommendationPending()
    self:ShowReloadRecommendationIfPending()
end

function CDM:ShowReloadRecommendationIfPending()
    if not self.reloadRecommendationPending then
        return
    end

    self.reloadRecommendationPending = nil
    self:ShowReloadRecommendationPrompt()
end
