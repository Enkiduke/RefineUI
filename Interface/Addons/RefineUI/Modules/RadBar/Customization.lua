----------------------------------------------------------------------------------------
-- RadBar Component: Customization
-- Cursor/grid reconciliation and validated slot edits outside combat.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local RadBar = RefineUI:GetModule("RadBar")
if not RadBar then return end

local Private = RadBar.Private
local InCombatLockdown = InCombatLockdown
local GetCursorInfo = GetCursorInfo

function RadBar:CURSOR_CHANGED()
    if InCombatLockdown() or not self.Core then return end
    local bindMode = Private.IsSupportedActionType(GetCursorInfo())
    self.Core:SetAttribute("bindMode", bindMode and true or nil)
    if bindMode or self.gridShown then
        self:ShowForCustomization()
    elseif self.mode == "customizing" then
        self:CloseRing()
    end
end

function RadBar:ACTIONBAR_SHOWGRID()
    self.gridShown = true
    self:CURSOR_CHANGED()
end

function RadBar:ACTIONBAR_HIDEGRID()
    self.gridShown = false
    self:CURSOR_CHANGED()
end

function RadBar:ShowForCustomization()
    if InCombatLockdown() or not self.Core then return end
    self.Core:SetAttribute("customizing", true)
    self.Core:SetAttribute("type", nil)
    self.Core:SetAttribute("typerelease", nil)
    self.Core:SetAttribute("macrotext", nil)
    self.Core:SetAttribute("centerX", UIParent:GetWidth() / 2)
    self.Core:SetAttribute("centerY", UIParent:GetHeight() / 2)
    if self.Core:GetAttribute("bindMode") then
        self.Core:Hide()
    else
        self.Core:Show()
    end
    self:SetPresentationMode("customizing")
end

function RadBar:SetupDrag(btn, index)
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function()
        if InCombatLockdown() or GetCursorInfo() or not IsShiftKeyDown() then return end
        local info = self:GetSlotAction(index)
        if not self:ResolveAction(info) then return end
        if info.type == "spell" then
            PickupSpell(info.value)
        elseif info.type == "item" then
            PickupItem(info.value)
        elseif info.type == "macro" then
            local _, _, reference = self:ResolveMacro(info.value)
            if not reference then return end -- Inline macros have no cursor representation.
            PickupMacro(reference)
        elseif info.type == "mount" then
            C_MountJournal.PickupMountByID(info.value)
        end
        if GetCursorInfo() then
            self:SetSlotAction(index, nil)
        end
    end)
    btn:SetScript("OnReceiveDrag", function()
        self:HandleDrop(index)
    end)
    btn:SetPassThroughButtons("RightButton")
    btn:SetScript("OnClick", function(_, button)
        if button == "LeftButton" and GetCursorInfo() then
            self:HandleDrop(index)
        end
    end)
end

function RadBar:HandleDrop(index)
    if InCombatLockdown() then return end
    local cursorType, cursorID, _, spellID = GetCursorInfo()
    if not Private.IsSupportedActionType(cursorType) then return end
    local value = cursorID
    if cursorType == "spell" then
        value = spellID
    elseif cursorType == "macro" then
        if not Private.IsPositiveInteger(cursorID) then return end
        local name = GetMacroInfo(cursorID)
        if not Private.IsNonEmptyString(name) then return end
        value = { name = name }
    end
    if not self:SetSlotAction(index, { type = cursorType, value = value }) then return end
    ClearCursor()
    -- Explicit reconciliation also works when cursor events are delivered later.
    self:CURSOR_CHANGED()
end
