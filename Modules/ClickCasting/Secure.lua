----------------------------------------------------------------------------------------
-- RefineUI ClickCasting Secure
-- Description: Secure snippets for frame enter/leave key rebinding.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local ClickCasting = RefineUI:GetModule("ClickCasting")
if not ClickCasting then
    return
end

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local ClearOverrideBindings = ClearOverrideBindings
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local tostring = tostring
local type = type
local tonumber = tonumber
local sort = table.sort

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local SECURE_HEADER_NAME = "RefineUI_ClickCastingSecureHeader"
local FRAME_REF_KEY = "refine_clickcasting_setup_frame"
local FRAME_STATE_REGISTRY = "ClickCastingFrameState"
local RESERVED_UNIT_MENU_KEY = "BUTTON2"
local RESERVED_UNIT_MENU_BUTTON = "RightButton"
local RESERVED_UNIT_MENU_FALLBACK_KEYS = {
    "ALT-BUTTON2",
    "CTRL-BUTTON2",
    "SHIFT-BUTTON2",
}

local function GetFrameState(frameStateRegistry, frame)
    local state = frameStateRegistry[frame]
    if not state then
        state = {}
        frameStateRegistry[frame] = state
    end
    return state
end

local function BuildAttributeName(prefix, attr, suffix)
    local hasPrefix = type(prefix) == "string" and prefix ~= ""
    local numericSuffix = tonumber(suffix) ~= nil
    local suffixText = tostring(suffix)

    if hasPrefix then
        if numericSuffix then
            return string.format("%s-%s%s", prefix, attr, suffixText)
        end
        return string.format("%s-%s-%s", prefix, attr, suffixText)
    end

    if numericSuffix then
        return string.format("%s%s", attr, suffixText)
    end

    return string.format("%s-%s", attr, suffixText)
end

local function BuildClearLinesForSlot(prefix, suffix, lines)
    lines[#lines + 1] = string.format("frame:SetAttribute(%q, nil)", BuildAttributeName(prefix, "type", suffix))
    lines[#lines + 1] = string.format("frame:SetAttribute(%q, nil)", BuildAttributeName(prefix, "spell", suffix))
    lines[#lines + 1] = string.format("frame:SetAttribute(%q, nil)", BuildAttributeName(prefix, "macro", suffix))
end

local function BuildClearLinesForRouting(prefix, suffix, lines)
    lines[#lines + 1] = string.format("frame:SetAttribute(%q, nil)", BuildAttributeName(prefix, "helpbutton", suffix))
    lines[#lines + 1] = string.format("frame:SetAttribute(%q, nil)", BuildAttributeName(prefix, "harmbutton", suffix))
end

local function BuildSetupLinesForAction(prefix, suffix, actionType, actionID, actionName, lines)
    lines[#lines + 1] = string.format("frame:SetAttribute(%q, %q)", BuildAttributeName(prefix, "type", suffix), actionType)
    if actionType == "spell" then
        if type(actionName) == "string" and actionName ~= "" then
            lines[#lines + 1] = string.format("frame:SetAttribute(%q, %q)", BuildAttributeName(prefix, "spell", suffix), actionName)
        else
            lines[#lines + 1] = string.format("frame:SetAttribute(%q, %d)", BuildAttributeName(prefix, "spell", suffix), tonumber(actionID) or 0)
        end
        lines[#lines + 1] = string.format("frame:SetAttribute(%q, nil)", BuildAttributeName(prefix, "macro", suffix))
    else
        local macroIndex = tonumber(actionID)
        if macroIndex and macroIndex > 0 then
            lines[#lines + 1] = string.format("frame:SetAttribute(%q, %d)", BuildAttributeName(prefix, "macro", suffix), macroIndex)
        elseif type(actionName) == "string" and actionName ~= "" then
            lines[#lines + 1] = string.format("frame:SetAttribute(%q, %q)", BuildAttributeName(prefix, "macro", suffix), actionName)
        else
            lines[#lines + 1] = string.format("frame:SetAttribute(%q, nil)", BuildAttributeName(prefix, "macro", suffix))
        end
        lines[#lines + 1] = string.format("frame:SetAttribute(%q, nil)", BuildAttributeName(prefix, "spell", suffix))
    end
end

local function ParseMouseBindingKey(key)
    if type(key) ~= "string" or key == "" then
        return nil, nil
    end

    local buttonNum = key:match("BUTTON(%d+)$")
    if not buttonNum then
        return nil, nil
    end

    local prefix = key:sub(1, #key - #("BUTTON" .. buttonNum))
    if prefix:sub(-1, -1) == "-" then
        prefix = prefix:sub(1, -2)
    end

    return prefix:lower(), buttonNum
end

local function BuildActionSlotToken(prefix, suffix)
    return tostring(prefix or "") .. ":" .. tostring(suffix or "")
end

local function EnsureDefaultUnitMenuAttribute(frame)
    if not frame or not frame.SetAttribute or not frame.GetAttribute then
        return
    end
    local hasType2 = frame:GetAttribute("type2") ~= nil
    local hasWildcardType2 = frame:GetAttribute("*type2") ~= nil
    if not hasType2 and not hasWildcardType2 then
        frame:SetAttribute("type2", "togglemenu")
    end
end

----------------------------------------------------------------------------------------
-- Header
----------------------------------------------------------------------------------------
function ClickCasting:EnsureSecureHeader()
    if self.secureHeader then
        return self.secureHeader
    end

    local header = CreateFrame("Frame", SECURE_HEADER_NAME, UIParent, "SecureHandlerBaseTemplate")
    header:SetAttribute("refine_onenter", "")
    header:SetAttribute("refine_onleave", "")
    header:SetAttribute("refine_setup_actions", "")
    header:SetAttribute("refine_clear_actions", "")
    self.secureHeader = header
    return header
end

function ClickCasting:InitializeSecureSystem()
    self:EnsureSecureHeader()
    self.frameStateRegistry = self.frameStateRegistry or RefineUI:CreateDataRegistry(FRAME_STATE_REGISTRY, "k")
    self.registeredFrames = self.registeredFrames or {}
    self.frameRegistrationQueue = self.frameRegistrationQueue or {}
    self.lastKnownActionSlots = self.lastKnownActionSlots or {}
    self.lastKnownRoutingSlots = self.lastKnownRoutingSlots or {}
    self.lastKnownKeys = self.lastKnownKeys or {}
end

----------------------------------------------------------------------------------------
-- Snippet Programs
----------------------------------------------------------------------------------------
function ClickCasting:BuildSecurePrograms()
    local activeKeyActions = self:GetRuntimeActiveKeyActions()
    local sortedActions = {}
    for i = 1, #activeKeyActions do
        sortedActions[i] = activeKeyActions[i]
    end
    sort(sortedActions, function(a, b)
        return (a.key or "") < (b.key or "")
    end)

    local currentActionSlots = {}
    local currentRoutingSlots = {}
    local currentKeys = {}
    local setupLines = {
        string.format("local frame = self:GetFrameRef(%q)", FRAME_REF_KEY),
        "if not frame then return end",
    }
    local clearLines = {
        string.format("local frame = self:GetFrameRef(%q)", FRAME_REF_KEY),
        "if not frame then return end",
    }
    local onEnterLines = {
        "local clickableButton = self:GetName()",
        "if not clickableButton then return end",
        "local unit = self:GetAttribute('unit')",
        "if not unit then return end",
        -- Reserve plain right-click for Blizzard unit menus on non-player unit frames.
        "local reserveUnitMenu = (unit ~= 'player')",
    }
    local onLeaveLines = {}
    local onEnterActionBindings = {}
    local hasPrimaryRightClickAction = false

    for index = 1, #sortedActions do
        local action = sortedActions[index]
        local key = action.key
        currentKeys[key] = true

        if key == RESERVED_UNIT_MENU_KEY then
            hasPrimaryRightClickAction = true
        end

        local keyPrefix, mouseButtonSuffix = ParseMouseBindingKey(key)
        local attrPrefix
        local attrSuffix
        if mouseButtonSuffix then
            attrPrefix = keyPrefix or ""
            attrSuffix = mouseButtonSuffix
        else
            attrPrefix = ""
            attrSuffix = "rfcc_" .. tostring(index)
            onEnterActionBindings[#onEnterActionBindings + 1] = {
                key = key,
                suffix = attrSuffix,
            }
        end

        action.suffix = attrSuffix
        local actionSlotToken = BuildActionSlotToken(attrPrefix, attrSuffix)
        currentActionSlots[actionSlotToken] = {
            prefix = attrPrefix,
            suffix = attrSuffix,
        }

        -- Route both friendly and hostile units through explicit action slots.
        -- Mirrors Clique's help/harm strategy for hybrid spells like Holy Shock.
        local helpSuffix = "rfcc_help_" .. tostring(index)
        local harmSuffix = "rfcc_harm_" .. tostring(index)
        setupLines[#setupLines + 1] = string.format(
            "frame:SetAttribute(%q, %q)",
            BuildAttributeName(attrPrefix, "helpbutton", attrSuffix),
            helpSuffix
        )
        setupLines[#setupLines + 1] = string.format(
            "frame:SetAttribute(%q, %q)",
            BuildAttributeName(attrPrefix, "harmbutton", attrSuffix),
            harmSuffix
        )

        local routingSlotToken = BuildActionSlotToken(attrPrefix, attrSuffix)
        currentRoutingSlots[routingSlotToken] = {
            prefix = attrPrefix,
            suffix = attrSuffix,
        }
        local helpSlotToken = BuildActionSlotToken(attrPrefix, helpSuffix)
        currentActionSlots[helpSlotToken] = {
            prefix = attrPrefix,
            suffix = helpSuffix,
        }
        local harmSlotToken = BuildActionSlotToken(attrPrefix, harmSuffix)
        currentActionSlots[harmSlotToken] = {
            prefix = attrPrefix,
            suffix = harmSuffix,
        }
        BuildSetupLinesForAction(attrPrefix, helpSuffix, action.actionType, action.actionID, action.actionName, setupLines)
        BuildSetupLinesForAction(attrPrefix, harmSuffix, action.actionType, action.actionID, action.actionName, setupLines)

        BuildSetupLinesForAction(attrPrefix, attrSuffix, action.actionType, action.actionID, action.actionName, setupLines)
    end

    local reservedMenuKey = RESERVED_UNIT_MENU_KEY
    if hasPrimaryRightClickAction then
        reservedMenuKey = nil
        for _, fallbackKey in ipairs(RESERVED_UNIT_MENU_FALLBACK_KEYS) do
            if not currentKeys[fallbackKey] then
                reservedMenuKey = fallbackKey
                break
            end
        end
    end
    local menuPrefix, menuButtonSuffix = ParseMouseBindingKey(reservedMenuKey)
    if reservedMenuKey and menuButtonSuffix then
        local normalizedMenuPrefix = menuPrefix or ""
        local menuSlotToken = BuildActionSlotToken(normalizedMenuPrefix, menuButtonSuffix)
        currentActionSlots[menuSlotToken] = {
            prefix = normalizedMenuPrefix,
            suffix = menuButtonSuffix,
        }
        setupLines[#setupLines + 1] = string.format(
            "frame:SetAttribute(%q, %q)",
            BuildAttributeName(normalizedMenuPrefix, "type", menuButtonSuffix),
            "togglemenu"
        )
        setupLines[#setupLines + 1] = string.format(
            "frame:SetAttribute(%q, nil)",
            BuildAttributeName(normalizedMenuPrefix, "spell", menuButtonSuffix)
        )
        setupLines[#setupLines + 1] = string.format(
            "frame:SetAttribute(%q, nil)",
            BuildAttributeName(normalizedMenuPrefix, "macro", menuButtonSuffix)
        )
    end
    local reservePrimaryRightClick = (reservedMenuKey == RESERVED_UNIT_MENU_KEY)
    if reservedMenuKey then
        onEnterLines[#onEnterLines + 1] = string.format(
            "if reserveUnitMenu then self:SetBindingClick(true, %q, clickableButton, %q) end",
            reservedMenuKey,
            RESERVED_UNIT_MENU_BUTTON
        )
    end

    for index = 1, #onEnterActionBindings do
        local actionBinding = onEnterActionBindings[index]
        local key = actionBinding.key
        local suffix = actionBinding.suffix
        onEnterLines[#onEnterLines + 1] = string.format(
            "if not (reserveUnitMenu and %s and %q == %q) then self:SetBindingClick(true, %q, clickableButton, %q) end",
            reservePrimaryRightClick and "true" or "false",
            key,
            RESERVED_UNIT_MENU_KEY,
            key,
            suffix
        )
    end

    for _, slot in pairs(self.lastKnownActionSlots or {}) do
        BuildClearLinesForSlot(slot.prefix, slot.suffix, clearLines)
    end
    for _, slot in pairs(currentActionSlots) do
        BuildClearLinesForSlot(slot.prefix, slot.suffix, clearLines)
    end
    for _, slot in pairs(self.lastKnownRoutingSlots or {}) do
        BuildClearLinesForRouting(slot.prefix, slot.suffix, clearLines)
    end
    for _, slot in pairs(currentRoutingSlots) do
        BuildClearLinesForRouting(slot.prefix, slot.suffix, clearLines)
    end

    local keysToClear = {
        [RESERVED_UNIT_MENU_KEY] = true,
    }
    for _, fallbackKey in ipairs(RESERVED_UNIT_MENU_FALLBACK_KEYS) do
        keysToClear[fallbackKey] = true
    end
    for key in pairs(self.lastKnownKeys or {}) do
        keysToClear[key] = true
    end
    for key in pairs(currentKeys) do
        keysToClear[key] = true
    end
    for key in pairs(keysToClear) do
        onLeaveLines[#onLeaveLines + 1] = string.format("self:ClearBinding(%q)", key)
    end

    self.lastKnownActionSlots = currentActionSlots
    self.lastKnownRoutingSlots = currentRoutingSlots
    self.lastKnownKeys = currentKeys
    self.runtimeSecureActions = sortedActions

    local setupSnippet = table.concat(setupLines, "\n")
    local clearSnippet = table.concat(clearLines, "\n")
    local onEnterSnippet = table.concat(onEnterLines, "\n")
    local onLeaveSnippet = table.concat(onLeaveLines, "\n")

    return setupSnippet, clearSnippet, onEnterSnippet, onLeaveSnippet
end

----------------------------------------------------------------------------------------
-- Frame Registration
----------------------------------------------------------------------------------------
function ClickCasting:RegisterSecureFrame(frame)
    if not frame or type(frame) ~= "table" then
        return false
    end
    if frame.IsForbidden and frame:IsForbidden() then
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

    if not frameState.wrapped then
        if frame.RegisterForClicks then
            -- Keep key-driven click-casting responsive (AnyDown), but preserve
            -- native unit-menu behavior on right-click release.
            frame:RegisterForClicks("AnyDown", "RightButtonUp")
        end
        EnsureDefaultUnitMenuAttribute(frame)

        local okEnter = pcall(header.WrapScript, header, frame, "OnEnter", [[
            local snippet = control:GetAttribute("refine_onenter")
            if snippet and snippet ~= "" then
                control:RunFor(self, snippet)
            end
        ]])
        local okLeave = pcall(header.WrapScript, header, frame, "OnLeave", [[
            local snippet = control:GetAttribute("refine_onleave")
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
    header:Execute(header:GetAttribute("refine_clear_actions"), frame)
    header:Execute(header:GetAttribute("refine_setup_actions"), frame)
    EnsureDefaultUnitMenuAttribute(frame)
    return true
end

function ClickCasting:FlushPendingFrameRegistrations()
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
function ClickCasting:ClearRuntimeOverrideBindings()
    if InCombatLockdown() then
        self.pendingSecureApply = true
        return
    end
    for frame in pairs(self.registeredFrames or {}) do
        if frame and not (frame.IsForbidden and frame:IsForbidden()) then
            pcall(ClearOverrideBindings, frame)
        end
    end
end

function ClickCasting:ApplySecureSystem()
    if InCombatLockdown() then
        self.pendingSecureApply = true
        return
    end

    self:FlushPendingFrameRegistrations()

    local header = self:EnsureSecureHeader()
    local setupSnippet, clearSnippet, onEnterSnippet, onLeaveSnippet = self:BuildSecurePrograms()

    header:SetAttribute("refine_setup_actions", setupSnippet or "")
    header:SetAttribute("refine_clear_actions", clearSnippet or "")
    header:SetAttribute("refine_onenter", onEnterSnippet or "")
    header:SetAttribute("refine_onleave", onLeaveSnippet or "")

    for frame in pairs(self.registeredFrames or {}) do
        if frame and not (frame.IsForbidden and frame:IsForbidden()) then
            header:SetFrameRef(FRAME_REF_KEY, frame)
            header:Execute(header:GetAttribute("refine_clear_actions"), frame)
            header:Execute(header:GetAttribute("refine_setup_actions"), frame)
            EnsureDefaultUnitMenuAttribute(frame)
            pcall(ClearOverrideBindings, frame)
        end
    end
end

function ClickCasting:DisableSecureSystem(reason)
    if InCombatLockdown() then
        self.pendingSecureApply = true
        return
    end

    local header = self:EnsureSecureHeader()
    header:SetAttribute("refine_onenter", "")
    header:SetAttribute("refine_onleave", "")

    local clearLines = {
        string.format("local frame = self:GetFrameRef(%q)", FRAME_REF_KEY),
        "if not frame then return end",
    }
    for _, slot in pairs(self.lastKnownActionSlots or {}) do
        BuildClearLinesForSlot(slot.prefix, slot.suffix, clearLines)
    end
    for _, slot in pairs(self.lastKnownRoutingSlots or {}) do
        BuildClearLinesForRouting(slot.prefix, slot.suffix, clearLines)
    end
    local clearSnippet = table.concat(clearLines, "\n")
    header:SetAttribute("refine_clear_actions", clearSnippet)
    header:SetAttribute("refine_setup_actions", "")

    for frame in pairs(self.registeredFrames or {}) do
        if frame and not (frame.IsForbidden and frame:IsForbidden()) then
            header:SetFrameRef(FRAME_REF_KEY, frame)
            header:Execute(header:GetAttribute("refine_clear_actions"), frame)
            EnsureDefaultUnitMenuAttribute(frame)
            pcall(ClearOverrideBindings, frame)
        end
    end

    self.runtimeSecureActions = {}
    self.lastKnownKeys = {}
    self.lastKnownActionSlots = {}
    self.lastKnownRoutingSlots = {}
    self.suspendReason = reason
end
