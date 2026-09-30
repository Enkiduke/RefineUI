----------------------------------------------------------------------------------------
-- RefineUI MouseoverCasting Secure
-- Description: Secure snippets for frame enter/leave key rebinding.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local MouseoverCasting = RefineUI:GetModule("MouseoverCasting")
if not MouseoverCasting then
    return
end

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local ClearOverrideBindings = ClearOverrideBindings
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local format = string.format
local type = type
local tonumber = tonumber
local concat = table.concat

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local SECURE_HEADER_NAME = "RefineUI_MouseoverCastingSecureHeader"
local FRAME_REF_KEY = "rfmo_frame"
local FRAME_STATE_REGISTRY = "MouseoverCastingFrameState"
-- Keys click this button instead of the unit frame, keeping them out of
-- SecureUnitButton_OnClick and its click-binding checks.
local KEY_BUTTON_NAME = "RefineUI_MouseoverCastingKeyButton"
local KEY_BUTTON_REF = "rfmo_keybutton"
local SNIPPET_FRAME_LINE = format("local frame = self:GetFrameRef(%q)\nif not frame then return end", FRAME_REF_KEY)
local ONENTER_HEADER_LINE = "local unit = self:GetAttribute(\"unit\")\nif not unit then return end\nkeyButton:SetAttribute(\"unit\", unit)"
local ONLEAVE_SNIPPET = "self:ClearBindings()"
-- Virtual button with no action; right-button presses are remapped to it.
local RIGHT_BUTTON_DOWN_NOOP = "rfmo_rightdown"

local function GetFrameState(frameStateRegistry, frame)
    local state = frameStateRegistry[frame]
    if not state then
        state = {}
        frameStateRegistry[frame] = state
    end
    return state
end

-- Attribute names are prefix .. attr .. suffix. The prefix is "", "*", or "alt-ctrl-" style
-- (SecureButton_GetModifierPrefix); the suffix is already in SecureButton_GetButtonSuffix
-- form: "3" for a mouse button, "-name" for a virtual button.

-- Returns the unit frame clear snippet and the key button clear snippet.
local function BuildClearSnippets(slots)
    local frameLines = { SNIPPET_FRAME_LINE }
    local keyLines = {}
    for _, slot in pairs(slots) do
        local lines = slot.target == "frame" and frameLines or keyLines
        lines[#lines + 1] = format("%s:SetAttribute(%q, nil)", slot.target, slot.prefix .. "type" .. slot.suffix)
        lines[#lines + 1] = format("%s:SetAttribute(%q, nil)", slot.target, slot.prefix .. "spell" .. slot.suffix)
        lines[#lines + 1] = format("%s:SetAttribute(%q, nil)", slot.target, slot.prefix .. "macro" .. slot.suffix)
    end
    return concat(frameLines, "\n"), concat(keyLines, "\n")
end

-- Setup always runs after the clear snippet, so only non-nil attributes are written.
local function BuildSetupLinesForAction(target, prefix, suffix, actionType, actionID, actionName, lines)
    lines[#lines + 1] = format("%s:SetAttribute(%q, %q)", target, prefix .. "type" .. suffix, actionType)
    if actionType == "spell" then
        if type(actionName) == "string" and actionName ~= "" then
            lines[#lines + 1] = format("%s:SetAttribute(%q, %q)", target, prefix .. "spell" .. suffix, actionName)
        else
            lines[#lines + 1] = format("%s:SetAttribute(%q, %d)", target, prefix .. "spell" .. suffix, tonumber(actionID) or 0)
        end
    else
        local macroIndex = tonumber(actionID)
        if macroIndex and macroIndex > 0 then
            lines[#lines + 1] = format("%s:SetAttribute(%q, %d)", target, prefix .. "macro" .. suffix, macroIndex)
        elseif type(actionName) == "string" and actionName ~= "" then
            lines[#lines + 1] = format("%s:SetAttribute(%q, %q)", target, prefix .. "macro" .. suffix, actionName)
        end
    end
end

-- "ALT-CTRL-BUTTON3" -> "alt-ctrl-", "3"; nil for keyboard keys. Binding keys order
-- modifiers ALT-CTRL-SHIFT, matching SecureButton_GetModifierPrefix.
local function ParseMouseKey(key)
    local modifiers, buttonNumber = key:match("^(.-)BUTTON(%d+)$")
    if not buttonNumber then
        return nil
    end
    if modifiers ~= "" then
        return modifiers:lower(), buttonNumber
    end
    -- An unmodified button also fires with an unbound modifier held, so match any
    -- modifier. Left/right click keep Blizzard's "*type1"/"*type2".
    if buttonNumber == "1" or buttonNumber == "2" then
        return "", buttonNumber
    end
    return "*", buttonNumber
end

----------------------------------------------------------------------------------------
-- Header
----------------------------------------------------------------------------------------
function MouseoverCasting:EnsureSecureHeader()
    if self.secureHeader then
        return self.secureHeader
    end

    local header = CreateFrame("Frame", SECURE_HEADER_NAME, UIParent, "SecureHandlerBaseTemplate")
    header:SetAttribute("rfmo_enter", "")
    header:SetAttribute("rfmo_leave", "")
    header:SetAttribute("rfmo_apply", "")
    header:SetAttribute("rfmo_clear", "")

    local keyButton = CreateFrame("Button", KEY_BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
    -- SecureActionButton_OnClick acts on the edge the ActionButtonUseKeyDown CVar selects.
    keyButton:RegisterForClicks("AnyUp", "AnyDown")
    header:SetFrameRef(KEY_BUTTON_REF, keyButton)
    header:Execute(format("keyButton = self:GetFrameRef(%q)", KEY_BUTTON_REF))

    self.secureHeader = header
    return header
end

function MouseoverCasting:InitializeSecureSystem()
    self:EnsureSecureHeader()
    self.frameStateRegistry = self.frameStateRegistry or RefineUI:CreateDataRegistry(FRAME_STATE_REGISTRY, "k")
    self.registeredFrames = self.registeredFrames or {}
    self.frameRegistrationQueue = self.frameRegistrationQueue or {}
    self.lastKnownActionSlots = self.lastKnownActionSlots or {}
end

----------------------------------------------------------------------------------------
-- Snippet Programs
----------------------------------------------------------------------------------------
function MouseoverCasting:BuildSecurePrograms()
    -- Already sorted by key in RebuildActiveSpecBindings.
    local activeKeyActions = self:GetRuntimeActiveKeyActions()
    local currentActionSlots = {}
    local setupLines = { SNIPPET_FRAME_LINE }
    local keySetupLines = {}
    local onEnterLines = { ONENTER_HEADER_LINE }

    for index = 1, #activeKeyActions do
        local action = activeKeyActions[index]
        local key = action.key

        -- Mouse keys map to frame click attributes, prefixed by the key's modifiers since
        -- secure lookups use the modifiers held at click time. Other keys are bound on
        -- enter to a virtual button of the key button; the binding already matched the
        -- modifiers, so its attributes accept any.
        local target, lines = "frame", setupLines
        local attrPrefix, attrSuffix = ParseMouseKey(key)
        if not attrPrefix then
            target, lines = "keyButton", keySetupLines
            local virtualButton = "rfmo_" .. index
            attrPrefix, attrSuffix = "*", "-" .. virtualButton
            onEnterLines[#onEnterLines + 1] = format("self:SetBindingClick(true, %q, %q, %q)", key, KEY_BUTTON_NAME, virtualButton)
        end

        currentActionSlots[target .. ":" .. attrPrefix .. attrSuffix] = {
            target = target,
            prefix = attrPrefix,
            suffix = attrSuffix,
        }
        BuildSetupLinesForAction(target, attrPrefix, attrSuffix, action.actionType, action.actionID, action.actionName, lines)
    end

    -- Clear both the previous and current slots before setup.
    local slotsToClear = self.lastKnownActionSlots
    for token, slot in pairs(currentActionSlots) do
        slotsToClear[token] = slot
    end
    local clearSnippet, keyClearSnippet = BuildClearSnippets(slotsToClear)
    self.lastKnownActionSlots = currentActionSlots

    local hasKeyBindings = #onEnterLines > 1
    local onEnterSnippet = hasKeyBindings and concat(onEnterLines, "\n") or ""
    local onLeaveSnippet = hasKeyBindings and ONLEAVE_SNIPPET or ""
    local keySnippet = keyClearSnippet .. "\n" .. concat(keySetupLines, "\n")

    return concat(setupLines, "\n"), clearSnippet, keySnippet, onEnterSnippet, onLeaveSnippet
end

----------------------------------------------------------------------------------------
-- Frame Registration
----------------------------------------------------------------------------------------
function MouseoverCasting:RegisterSecureFrame(frame)
    if frame:IsForbidden() then
        return false
    end

    if InCombatLockdown() then
        self.frameRegistrationQueue[frame] = true
        self.pendingFrameRegistration = true
        return false
    end

    local header = self:EnsureSecureHeader()
    local frameState = GetFrameState(self.frameStateRegistry, frame)
    self.registeredFrames[frame] = true

    -- Mouse buttons fire on press (AnyDown). The right button also fires on release so
    -- Blizzard's "*type2" = "menu" opens the frame menu. SecureUnitButton_OnClick
    -- runs every registered edge, so the right-button press is remapped to a
    -- no-op button to keep tracked right-click actions to one run, on release.
    -- Reapplied on every call: SecureUnitButton_OnLoad resets RegisterForClicks.
    frame:RegisterForClicks("AnyDown", "RightButtonUp")
    frame:SetAttribute("*downbutton2", RIGHT_BUTTON_DOWN_NOOP)

    if not frameState.wrapped then
        local okEnter = pcall(header.WrapScript, header, frame, "OnEnter", [[
            local snippet = control:GetAttribute("rfmo_enter")
            if snippet and snippet ~= "" then
                control:RunFor(self, snippet)
            end
        ]])
        local okLeave = pcall(header.WrapScript, header, frame, "OnLeave", [[
            local snippet = control:GetAttribute("rfmo_leave")
            if snippet and snippet ~= "" then
                control:RunFor(self, snippet)
            end
        ]])
        if not okEnter or not okLeave then
            self.registeredFrames[frame] = nil
            return false
        end

        frameState.wrapped = true
    end

    header:SetFrameRef(FRAME_REF_KEY, frame)
    header:Execute(header:GetAttribute("rfmo_clear"), frame)
    header:Execute(header:GetAttribute("rfmo_apply"), frame)
    return true
end

function MouseoverCasting:FlushPendingFrameRegistrations()
    if InCombatLockdown() then
        return
    end
    for frame in pairs(self.frameRegistrationQueue) do
        self.frameRegistrationQueue[frame] = nil
        self:RegisterSecureFrame(frame)
    end
    self.pendingFrameRegistration = false
end

----------------------------------------------------------------------------------------
-- Apply/Clear
----------------------------------------------------------------------------------------
-- Apply/Disable run only from FlushRebuild, which defers during combat.
function MouseoverCasting:ApplySecureSystem()
    self:FlushPendingFrameRegistrations()

    local header = self:EnsureSecureHeader()
    local setupSnippet, clearSnippet, keySnippet, onEnterSnippet, onLeaveSnippet = self:BuildSecurePrograms()

    header:Execute(keySnippet)
    header:SetAttribute("rfmo_apply", setupSnippet)
    header:SetAttribute("rfmo_clear", clearSnippet)
    header:SetAttribute("rfmo_enter", onEnterSnippet)
    header:SetAttribute("rfmo_leave", onLeaveSnippet)

    for frame in pairs(self.registeredFrames) do
        if not frame:IsForbidden() then
            header:SetFrameRef(FRAME_REF_KEY, frame)
            header:Execute(clearSnippet, frame)
            header:Execute(setupSnippet, frame)
            ClearOverrideBindings(frame)
        end
    end
end

function MouseoverCasting:DisableSecureSystem()
    local header = self:EnsureSecureHeader()
    local clearSnippet, keyClearSnippet = BuildClearSnippets(self.lastKnownActionSlots)
    header:Execute(keyClearSnippet)
    header:SetAttribute("rfmo_enter", "")
    header:SetAttribute("rfmo_leave", "")
    header:SetAttribute("rfmo_clear", clearSnippet)
    header:SetAttribute("rfmo_apply", "")

    for frame in pairs(self.registeredFrames) do
        if not frame:IsForbidden() then
            header:SetFrameRef(FRAME_REF_KEY, frame)
            header:Execute(clearSnippet, frame)
            ClearOverrideBindings(frame)
        end
    end

    self.lastKnownActionSlots = {}
end
