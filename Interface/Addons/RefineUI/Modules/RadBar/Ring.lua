----------------------------------------------------------------------------------------
-- RadBar Component: Ring
-- Validated action resolution and shared slot construction.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local RadBar = RefineUI:GetModule("RadBar")
if not RadBar then return end

local Private = RadBar.Private
local InCombatLockdown = InCombatLockdown
local GetMacroInfo = GetMacroInfo

local function IsActionReference(value)
    return Private.IsPositiveInteger(value)
        or (Private.IsNonEmptyString(value) and not value:find("[\r\n]"))
end

function RadBar:ResolveMacro(value)
    local reference, body, icon
    if type(value) == "table" then
        -- Named references survive index shifts. Never execute a stale snapshot when
        -- a referenced macro is deleted or renamed; the user must rebind that name.
        if value.name ~= nil then
            if not IsActionReference(value.name) then return end
            reference = value.name
        elseif value.id ~= nil then
            if not Private.IsPositiveInteger(value.id) then return end
            reference = value.id
        else
            body = value.body or value.text
            icon = value.icon
        end
    elseif type(value) == "string" and value:match("^%s*[/#]") then
        body = value -- Legacy inline macro text remains supported.
    elseif IsActionReference(value) then
        reference = value
    end

    if reference then
        local name
        name, icon, body = GetMacroInfo(reference)
        if not name then return end
    end
    if not Private.IsNonEmptyString(body) then return end
    if type(icon) ~= "number" and type(icon) ~= "string" then
        icon = Private.DEFAULT_EMPTY_ICON
    end
    return body, icon, reference
end

function RadBar:ResolveAction(info)
    if type(info) ~= "table" or not Private.IsSupportedActionType(info.type) then return end
    local actionType, value = info.type, info.value
    local macro, icon
    if actionType == "macro" then
        macro, icon = self:ResolveMacro(value)
    elseif not IsActionReference(value) then
        return
    elseif actionType == "spell" then
        local spell = C_Spell.GetSpellInfo(value)
        if not spell or not spell.name then return end
        macro, icon = "/cast " .. spell.name, spell.iconID
    elseif actionType == "item" then
        -- item:ID works without waiting for the item-name cache and avoids /use 1
        -- being interpreted as an inventory slot.
        local target = Private.IsPositiveInteger(value) and "item:" .. value or value
        macro, icon = "/use " .. target, C_Item.GetItemIconByID(value)
    elseif actionType == "mount" then
        if not Private.IsPositiveInteger(value) then return end
        local name, _, mountIcon = C_MountJournal.GetMountInfoByID(value)
        if not name then return end
        macro, icon = "/cast " .. name, mountIcon
    end
    if not Private.IsNonEmptyString(macro) then return end
    return { type = actionType, value = value, macro = macro, icon = icon or Private.DEFAULT_EMPTY_ICON }
end

-- Compatibility helpers for callers that only need one resolved field.
function RadBar:GetMacroForAction(actionType, value)
    local action = self:ResolveAction({ type = actionType, value = value })
    return action and action.macro or ""
end

function RadBar:GetIconForAction(actionType, value)
    local action = self:ResolveAction({ type = actionType, value = value })
    return action and action.icon or Private.DEFAULT_EMPTY_ICON
end

function RadBar:GetRingConfig(ringName)
    local ring = self.db.Rings[ringName or self.activeRing or "Main"]
    return type(ring) == "table" and ring or nil
end

function RadBar:GetSlotAction(index)
    local ring = self:GetRingConfig()
    if not ring then return end
    if index == 0 then return ring.Center end
    return type(ring.Slices) == "table" and ring.Slices[index] or nil
end

function RadBar:SetSlotAction(index, info)
    if InCombatLockdown() or type(index) ~= "number" or index < 0
        or index > Private.SLOT_COUNT or index ~= math.floor(index) then
        return false
    end
    if info ~= nil and not self:ResolveAction(info) then return false end
    local ring = self:GetRingConfig()
    if not ring then return false end
    if index == 0 then
        ring.Center = info
    else
        ring.Slices = type(ring.Slices) == "table" and ring.Slices or {}
        ring.Slices[index] = info
    end
    self:BuildRing(self.activeRing or "Main")
    return true
end

function RadBar:CreateSlot(index)
    local btn = CreateFrame("Button", nil, self.Content)
    local size = index == 0 and Private.CENTER_SIZE or Private.SLICE_SIZE
    RefineUI.Size(btn, size, size)
    RefineUI.SetTemplate(btn, "Icon")
    RefineUI.CreateBorder(btn, 6, 6, index == 0 and 14 or 12)
    local glow = RefineUI.CreateGlow(btn, 4)
    glow:CreatePulse(0.3, 1, 0.6)
    glow:Hide()
    btn.Icon = btn:CreateTexture(nil, "ARTWORK")
    btn.Icon:SetAllPoints()
    btn.SlotIndex = index
    btn.AttributePrefix = Private.GetSlotPrefix(index)
    btn:EnableMouse(false)
    self:SetupDrag(btn, index)
    return btn
end

function RadBar:AssignSlot(btn, info)
    local action = self:ResolveAction(info)
    self.Core:SetAttribute(btn.AttributePrefix .. "macro", action and action.macro or nil)
    btn.ActionType = action and action.type or nil
    btn.ActionValue = action and action.value or nil
    btn.ActionIcon = action and action.icon or Private.DEFAULT_EMPTY_ICON
    btn.HasAction = action ~= nil
end

function RadBar:BuildRing(ringName)
    ringName = ringName or self.activeRing or "Main"
    if InCombatLockdown() then
        self._pendingBuildRing = ringName
        return
    end
    if not self.Core then return end
    self.activeRing = ringName
    local config = self:GetRingConfig(ringName) or {}
    local slices = type(config.Slices) == "table" and config.Slices or {}
    self.Core:SetAttribute("numSlices", Private.SLOT_COUNT)

    self.CenterButton = self.CenterButton or self:CreateSlot(0)
    self.CenterButton:ClearAllPoints()
    self.CenterButton:SetPoint("CENTER", self.Content, "CENTER", 0, 0)
    self:AssignSlot(self.CenterButton, config.Center)

    for index = 1, Private.SLOT_COUNT do
        local btn = self.Buttons[index] or self:CreateSlot(index)
        self.Buttons[index] = btn
        local angle = math.pi / 2 - (index - 1) * Private.TWO_PI / Private.SLOT_COUNT
        btn:ClearAllPoints()
        RefineUI.Point(btn, "CENTER", self.Content, "CENTER",
            math.cos(angle) * Private.RING_RADIUS, math.sin(angle) * Private.RING_RADIUS)
        self:AssignSlot(btn, slices[index])
    end
    self:UpdateSlotVisibility()
    self:UpdateUsabilityVisuals()
end

function RadBar:SetIconUsabilityColor(icon, isUsable)
    if not icon then return end
    if isUsable then
        icon:SetVertexColor(Private.ICON_USABLE_R, Private.ICON_USABLE_G, Private.ICON_USABLE_B)
    else
        icon:SetVertexColor(Private.ICON_UNUSABLE_R, Private.ICON_UNUSABLE_G, Private.ICON_UNUSABLE_B)
    end
end

function RadBar:IsActionUsable(actionType, actionValue)
    if not actionType or actionValue == nil then return true end
    local usable
    if actionType == "spell" and C_Spell and C_Spell.IsSpellUsable then
        usable = C_Spell.IsSpellUsable(actionValue)
    elseif actionType == "item" then
        if C_Item and C_Item.IsUsableItem then
            usable = C_Item.IsUsableItem(actionValue)
        elseif IsUsableItem then
            usable = IsUsableItem(actionValue)
        end
    elseif actionType == "mount" and C_MountJournal and C_MountJournal.GetMountInfoByID then
        local _, _, _, _, canUse = C_MountJournal.GetMountInfoByID(actionValue)
        usable = canUse
    end
    if usable == nil then return true end
    return usable
end

function RadBar:UpdateUsabilityVisuals(forceClear)
    if not self.Core then return end
    local canTint = not forceClear and self.mode == "selecting"
        and self.Core:IsShown() and self.Content:IsShown()
    for index = 0, Private.SLOT_COUNT do
        local btn = index == 0 and self.CenterButton or self.Buttons[index]
        if btn then
            local usable = true
            if canTint and btn.HasAction then
                usable = self:IsActionUsable(btn.ActionType, btn.ActionValue)
            end
            self:SetIconUsabilityColor(btn.Icon, usable)
        end
    end
end
