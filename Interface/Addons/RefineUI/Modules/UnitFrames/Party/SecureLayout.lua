----------------------------------------------------------------------------------------
-- UnitFrames Party: Secure Layout
-- Description: Secure-owner spacing helpers for Blizzard Compact Party member frames.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local UnitFrames = RefineUI:GetModule("UnitFrames")
if not UnitFrames then
    return
end

local P = UnitFrames:GetPrivate().Party
if not P then
    return
end

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local SecureHandlerSetFrameRef = SecureHandlerSetFrameRef
local RegisterAttributeDriver = RegisterAttributeDriver
local type = type

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local HANDLER_NAME = "RefineUI_PartySpacingHandler"
local CONTAINER_NAME = "RefineUI_PartySpacingContainer"
local TRIGGER_NAME = "RefineUI_PartySpacingTrigger"
local EDIT_TRIGGER_NAME = "RefineUI_PartySpacingEditTrigger"
local MAX_PARTY_MEMBER_FRAMES = 5

local SECURE_LAYOUT_SNIPPET = [[
local stateOwner = owner or self
local container = stateOwner:GetFrameRef("container")
if container then
    local spacing = stateOwner:GetAttribute("spacing") or 18
    local previous = nil

    for i = 1, 5 do
        local frame = stateOwner:GetFrameRef("member" .. i)
        if frame and frame:IsVisible() then
            frame:ClearAllPoints()
            if previous then
                frame:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -spacing)
            else
                frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
            end
            previous = frame
        end
    end
end
]]

----------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------
local SecureState = {
    handler = nil,
    container = nil,
    trigger = nil,
    editTrigger = nil,
    hooksInstalled = false,
    setPointHooksInstalled = false,
    setupQueued = false,
    applyQueued = false,
    reapplying = false,
}

local ApplySecurePartySpacing

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------
local function GetCompactPartyFrame()
    local partyFrame = _G.CompactPartyFrame
    if partyFrame then
        return partyFrame
    end

    if InCombatLockdown() then
        return nil
    end

    if type(_G.CompactPartyFrame_Generate) == "function" then
        local generatedFrame = _G.CompactPartyFrame_Generate()
        if generatedFrame then
            return generatedFrame
        end
    end

    return _G.CompactPartyFrame
end

local function GetPartyMemberFrame(index)
    return _G["CompactPartyFrameMember" .. tostring(index)]
end

local function GetSpacingValue()
    local spacing = P.GetCompactFrameVerticalGap and P.GetCompactFrameVerticalGap(nil) or 18
    if type(spacing) ~= "number" then
        spacing = 18
    end
    return spacing
end

local function EnsureHandlerFrames(partyFrame)
    if not partyFrame or not SecureHandlerSetFrameRef or not RegisterAttributeDriver then
        return false
    end

    local handler = SecureState.handler
    if not handler then
        handler = CreateFrame("Frame", HANDLER_NAME, UIParent, "SecureHandlerBaseTemplate")
        SecureState.handler = handler
    end

    local container = SecureState.container
    if not container or container:GetParent() ~= partyFrame then
        container = _G[CONTAINER_NAME]
        if not container or container:GetParent() ~= partyFrame then
            container = CreateFrame("Frame", CONTAINER_NAME, partyFrame, "SecureFrameTemplate")
        end
        container:SetAllPoints(partyFrame)
        SecureState.container = container
    end

    local trigger = SecureState.trigger
    if not trigger then
        trigger = CreateFrame("Frame", TRIGGER_NAME, UIParent, "SecureFrameTemplate")
        RegisterAttributeDriver(trigger, "state", "[combat] combat; nocombat")
        SecureState.trigger = trigger
    end

    SecureHandlerSetFrameRef(handler, "container", container)
    SecureHandlerSetFrameRef(handler, "trigger", trigger)

    for i = 1, MAX_PARTY_MEMBER_FRAMES do
        local frame = GetPartyMemberFrame(i)
        if frame then
            SecureHandlerSetFrameRef(handler, "member" .. i, frame)
        end
    end

    handler:SetAttributeNoHandler("spacing", GetSpacingValue())
    return true
end

local function InstallSecureHooks(partyFrame)
    local handler = SecureState.handler
    if SecureState.hooksInstalled or not handler or not partyFrame then
        return
    end

    handler:WrapScript(partyFrame, "OnShow", SECURE_LAYOUT_SNIPPET)

    for i = 1, MAX_PARTY_MEMBER_FRAMES do
        local frame = GetPartyMemberFrame(i)
        if frame then
            handler:WrapScript(frame, "OnShow", SECURE_LAYOUT_SNIPPET)
            handler:WrapScript(frame, "OnHide", SECURE_LAYOUT_SNIPPET)
        end
    end

    local trigger = SecureState.trigger
    if trigger then
        handler:WrapScript(trigger, "OnAttributeChanged", [[
            if name == "state" then
                ]] .. SECURE_LAYOUT_SNIPPET .. [[
            end
        ]])
    end

    if _G.EditModeManagerFrame and _G.EditModeManagerFrame.CloseButton then
        local editTrigger = SecureState.editTrigger
        if not editTrigger then
            editTrigger = CreateFrame("Frame", EDIT_TRIGGER_NAME, _G.EditModeManagerFrame.CloseButton, "SecureFrameTemplate")
            editTrigger:SetAllPoints()
            SecureState.editTrigger = editTrigger
        end
        handler:WrapScript(editTrigger, "OnHide", SECURE_LAYOUT_SNIPPET)
    end

    SecureState.hooksInstalled = true
end

local function InstallSetPointHooks()
    if SecureState.setPointHooksInstalled then
        return
    end

    for i = 1, MAX_PARTY_MEMBER_FRAMES do
        local frame = GetPartyMemberFrame(i)
        if frame then
            RefineUI:HookOnce(UnitFrames:BuildHookKey(frame, "PartySecure:SetPoint"), frame, "SetPoint", function()
                if SecureState.reapplying then
                    return
                end
                ApplySecurePartySpacing()
            end)
        end
    end

    SecureState.setPointHooksInstalled = true
end

ApplySecurePartySpacing = function()
    local handler = SecureState.handler
    if not handler then
        return false
    end

    if InCombatLockdown() then
        SecureState.applyQueued = true
        return false
    end

    SecureState.reapplying = true
    handler:SetAttributeNoHandler("spacing", GetSpacingValue())
    handler:Execute(SECURE_LAYOUT_SNIPPET)
    SecureState.reapplying = false
    SecureState.applyQueued = false
    return true
end

local function SetupSecurePartySpacing()
    if InCombatLockdown() then
        SecureState.setupQueued = true
        return false
    end

    local partyFrame = GetCompactPartyFrame()
    if not partyFrame then
        SecureState.setupQueued = true
        return false
    end

    if not EnsureHandlerFrames(partyFrame) then
        return false
    end

    InstallSecureHooks(partyFrame)
    InstallSetPointHooks()
    SecureState.setupQueued = false
    return ApplySecurePartySpacing()
end

----------------------------------------------------------------------------------------
-- Shared Internal Exports
----------------------------------------------------------------------------------------
P.SetupSecurePartySpacing = SetupSecurePartySpacing
P.ApplySecurePartySpacing = ApplySecurePartySpacing
P.IsSecurePartySpacingQueued = function()
    return SecureState.setupQueued or SecureState.applyQueued
end
