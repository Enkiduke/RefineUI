----------------------------------------------------------------------------------------
-- RadBar Component: Customization
-- Description: Customization mode handlers and drag/drop behavior.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local RadBar = RefineUI:GetModule("RadBar")
if not RadBar then
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
local ipairs = ipairs
local InCombatLockdown = InCombatLockdown
local GetCursorInfo = GetCursorInfo
local GetMacroInfo = GetMacroInfo
local ClearCursor = ClearCursor
local IsShiftKeyDown = IsShiftKeyDown
local PickupSpell = PickupSpell
local PickupItem = PickupItem
local PickupMacro = PickupMacro

----------------------------------------------------------------------------------------
-- Public Component Methods
----------------------------------------------------------------------------------------
function RadBar:CURSOR_CHANGED()
    if InCombatLockdown() then
        return
    end

    local private = self.Private or {}
    local isSupportedActionType = private.IsSupportedActionType

    local cType = GetCursorInfo()
    local shouldBindMode = isSupportedActionType and isSupportedActionType(cType)
    self.Core:SetAttribute("bindMode", shouldBindMode and true or nil)
    if shouldBindMode then
        -- Hard guarantee: bind mode never uses fullscreen secure mouse capture.
        self.Core:Hide()
        self:StopUpdate()
        self:ShowForCustomization()
        self:ApplyBindModeVisuals()
    else
        self:HideForCustomization()
    end
end

function RadBar:ACTIONBAR_SHOWGRID()
    if InCombatLockdown() then
        return
    end
    self:CURSOR_CHANGED()
    if not self.isCustomizing then
        self:ShowForCustomization()
    end
end

function RadBar:ACTIONBAR_HIDEGRID()
    if InCombatLockdown() then
        return
    end
    self:CURSOR_CHANGED()
end

function RadBar:ShowForCustomization()
    local bindMode = self.Core:GetAttribute("bindMode")

    if self.Content:IsShown() and self.isCustomizing then
        self:UpdateSlotVisibility()
        if bindMode then
            self.Core:Hide()
            self:StopUpdate()
            self:ApplyBindModeVisuals()
        end
        return
    end

    self.isCustomizing = true

    self.Content:ClearAllPoints()
    RefineUI.Point(self.Content, "CENTER", UIParent, "CENTER", 0, 0)
    self.Content:Show()

    self.CenterButton:EnableMouse(true)
    for _, btn in ipairs(self.Buttons) do
        btn:EnableMouse(true)
    end
    self:UpdateSlotVisibility()
    if bindMode then
        self.Core:Hide() -- Bind mode must never fullscreen-capture mouse input.
        self:StopUpdate()
        self.Content:SetAlpha(1)
        self:ApplyBindModeVisuals()
    else
        self.Core:Show()
        self:StartUpdate()
        self:Fade(self.Content, 1, 0.1)
    end
end

function RadBar:HideForCustomization()
    if not self.Core:IsShown() and not self.Content:IsShown() then
        return
    end
    self.isCustomizing = false
    self:StopUpdate()
    self.CenterButton:EnableMouse(false)
    for _, btn in ipairs(self.Buttons) do
        btn:EnableMouse(false)
    end
    RadBar:Fade(self.Content, 0, 0.1, function(f)
        self.Core:Hide()
        f:Hide()
    end)
end

function RadBar:SetupDrag(btn, idx)
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function()
        if self.Core and self.Core:GetAttribute("bindMode") then
            return
        end
        if not InCombatLockdown() and IsShiftKeyDown() then
            local info
            if idx == 0 then
                info = self.db.Rings["Main"].Center
            else
                info = self.db.Rings["Main"].Slices[idx]
            end

            if not info then
                return
            end
            local picked = false
            if info.type == "spell" then
                PickupSpell(info.value)
                picked = GetCursorInfo() ~= nil
            elseif info.type == "item" then
                PickupItem(info.value)
                picked = GetCursorInfo() ~= nil
            elseif info.type == "macro" then
                local macroRef = info.value
                if _G.type(macroRef) == "table" then
                    macroRef = macroRef.id or macroRef.name
                end
                if _G.type(macroRef) == "string" and macroRef:sub(1, 1) == "/" then
                    picked = false
                elseif macroRef then
                    PickupMacro(macroRef)
                    picked = GetCursorInfo() ~= nil
                end
            elseif info.type == "mount" then
                C_MountJournal.PickupMountByID(info.value)
                picked = GetCursorInfo() ~= nil
            end

            if not picked then
                return
            end

            if idx == 0 then
                self.db.Rings["Main"].Center = nil
            else
                self.db.Rings["Main"].Slices[idx] = nil -- Clear without shifting others
            end

            self:BuildRing("Main")
        end
    end)
    btn:SetScript("OnReceiveDrag", function()
        self:HandleDrop(idx)
    end)
    btn:SetPassThroughButtons("RightButton")
    btn:SetScript("OnClick", function(_, button)
        if GetCursorInfo() then
            self:HandleDrop(idx)
        end
    end)
end

function RadBar:HandleDrop(idx)
    if InCombatLockdown() then
        return
    end

    local private = self.Private or {}
    local isSupportedActionType = private.IsSupportedActionType

    local info = { GetCursorInfo() }
    local cType = info[1]
    if not isSupportedActionType or not isSupportedActionType(cType) then
        return
    end

    local val
    if cType == "spell" then
        val = info[4] -- spellID
    elseif cType == "macro" then
        local name, icon, body = GetMacroInfo(info[2])
        if body and body ~= "" then
            val = {
                id = info[2],
                name = name,
                icon = icon,
                body = body,
            }
        elseif name then
            val = name
        end
    else
        val = info[2] -- itemID, mountID, etc
    end

    if not val then
        return
    end

    if idx == 0 then
        self.db.Rings["Main"].Center = { type = cType, value = val }
    else
        self.db.Rings["Main"].Slices[idx] = { type = cType, value = val }
    end

    ClearCursor()
    self:BuildRing("Main")
end
