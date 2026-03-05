----------------------------------------------------------------------------------------
-- RadBar Component: Ring
-- Description: Ring construction and action/icon/usability logic.
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
local math = math
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local GetMacroInfo = GetMacroInfo
local IsUsableItem = IsUsableItem

----------------------------------------------------------------------------------------
-- Public Component Methods
----------------------------------------------------------------------------------------
function RadBar:BuildRing(ringName)
    if InCombatLockdown() then
        self._pendingBuildRing = ringName or "Main"
        return
    end

    local private = self.Private or {}
    local isSupportedActionType = private.IsSupportedActionType
    local defaultEmptyIcon = private.DEFAULT_EMPTY_ICON or 134400

    local config = self.db.Rings[ringName] or {}
    local slices = config.Slices or {}
    local center = config.Center
    -- Fixed 4-slot layout regardless of how many are populated
    local num = 4
    local radius = 100 -- Tighter radius

    self.Core:SetAttribute("numSlices", num)

    -- Process Center
    if not self.CenterButton then
        local btn = CreateFrame("Button", nil, self.Content) -- Non-secure for scaling
        RefineUI.Size(btn, 52, 52) -- Compact center
        RefineUI.Point(btn, "CENTER", self.Content, "CENTER", 0, 0)
        RefineUI.SetTemplate(btn, "Icon")
        RefineUI.CreateBorder(btn, 6, 6, 14) -- Tighter border
        local glow = RefineUI.CreateGlow(btn, 10)
        glow:CreatePulse(0.3, 1, 0.6)
        btn.Icon = btn:CreateTexture(nil, "ARTWORK")
        btn.Icon:SetAllPoints()
        btn.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        self.CenterButton = btn
    end

    if center then
        local macro = isSupportedActionType and isSupportedActionType(center.type) and self:GetMacroForAction(center.type, center.value) or ""
        if macro ~= "" then
            self.CenterButton:Show()
            self.Core:SetAttribute("center-macro", macro)
            self.CenterButton.Icon:SetTexture(self:GetIconForAction(center.type, center.value))
            self.CenterButton.Icon:SetAlpha(1)
            self.CenterButton.ActionType = center.type
            self.CenterButton.ActionValue = center.value
        else
            self.CenterButton:Hide()
            self.Core:SetAttribute("center-macro", nil)
            self.CenterButton.Icon:SetTexture(defaultEmptyIcon)
            self.CenterButton.Icon:SetAlpha(0.1)
            self.CenterButton.ActionType = nil
            self.CenterButton.ActionValue = nil
        end
    else
        self.CenterButton:Hide()
        self.Core:SetAttribute("center-macro", nil)
        self.CenterButton.Icon:SetTexture(defaultEmptyIcon)
        self.CenterButton.Icon:SetAlpha(0.1)
        self.CenterButton.ActionType = nil
        self.CenterButton.ActionValue = nil
    end
    self:SetIconUsabilityColor(self.CenterButton.Icon, true)
    self:SetupDrag(self.CenterButton, 0)

    -- Process Slices (Fixed 4 slots: Top, Right, Bottom, Left)
    for i = 1, 4 do
        local info = slices[i]
        local btn = self.Buttons[i]
        -- ... rest of creation ...
        if not btn then
            btn = CreateFrame("Button", nil, self.Content) -- Non-secure for scaling
            RefineUI.Size(btn, 40, 40) -- Compact slices
            RefineUI.SetTemplate(btn, "Icon")
            RefineUI.CreateBorder(btn, 6, 6, 12) -- Tighter border
            local glow = RefineUI.CreateGlow(btn, 10)
            glow:CreatePulse(0.3, 1, 0.6)
            btn.Icon = btn:CreateTexture(nil, "ARTWORK")
            btn.Icon:SetAllPoints()
            btn.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            self.Buttons[i] = btn
        end

        btn:Show()
        local sliceAngle = (math.pi * 2 / num)
        local startAngle = math.pi / 2 -- Top
        local posAngle = startAngle - (i - 1) * sliceAngle
        btn:ClearAllPoints()
        RefineUI.Point(btn, "CENTER", self.Content, "CENTER", math.cos(posAngle) * radius, math.sin(posAngle) * radius)

        if info and isSupportedActionType and isSupportedActionType(info.type) then
            local macro = self:GetMacroForAction(info.type, info.value)
            if macro ~= "" then
                self.Core:SetAttribute("child" .. i .. "-macro", macro)
                btn.Icon:SetTexture(self:GetIconForAction(info.type, info.value))
                btn.Icon:SetAlpha(1)
                btn.ActionType = info.type
                btn.ActionValue = info.value
            else
                self.Core:SetAttribute("child" .. i .. "-macro", nil)
                btn.Icon:SetTexture(defaultEmptyIcon) -- Question mark icon
                btn.Icon:SetAlpha(0.1)
                btn.ActionType = nil
                btn.ActionValue = nil
            end
        else
            self.Core:SetAttribute("child" .. i .. "-macro", nil)
            btn.Icon:SetTexture(defaultEmptyIcon) -- Question mark icon
            btn.Icon:SetAlpha(0.1) -- Very faint normally
            btn.ActionType = nil
            btn.ActionValue = nil
        end
        self:SetIconUsabilityColor(btn.Icon, true)
        self:SetupDrag(btn, i)
    end

    for i = num + 1, #self.Buttons do
        self.Buttons[i]:Hide()
    end
    self:UpdateSlotVisibility() -- Ensure visibility syncs after data change
end

----------------------------------------------------------------------------------------
-- Action Logic
----------------------------------------------------------------------------------------
function RadBar:GetMacroForAction(actionType, value)
    if actionType == "spell" then
        local s = C_Spell.GetSpellInfo(value)
        local name = s and s.name
        return "/cast " .. (name or value)
    elseif actionType == "item" then
        local name = C_Item.GetItemInfo(value)
        return "/use " .. (name or value)
    elseif actionType == "mount" then
        local name = C_MountJournal.GetMountInfoByID(value)
        return "/cast " .. (name or value)
    elseif actionType == "macro" then
        if value == nil then
            return ""
        end

        if _G.type(value) == "table" then
            local body = value.body or value.text
            if body and body ~= "" then
                return body
            end

            local ref = value.id or value.name
            if ref then
                local _, _, resolvedBody = GetMacroInfo(ref)
                if resolvedBody and resolvedBody ~= "" then
                    return resolvedBody
                end
            end
            return ""
        elseif _G.type(value) == "number" then
            local _, _, body = GetMacroInfo(value)
            return body or ""
        elseif _G.type(value) == "string" then
            local _, _, body = GetMacroInfo(value)
            if body and body ~= "" then
                return body
            end
            -- Backward-compatible path for inline macro text already stored in DB.
            if value:sub(1, 1) == "/" then
                return value
            end
            return ""
        end
    end
    return ""
end

function RadBar:GetIconForAction(actionType, value)
    local private = self.Private or {}
    local defaultEmptyIcon = private.DEFAULT_EMPTY_ICON or 134400

    if actionType == "spell" then
        local s = C_Spell.GetSpellInfo(value)
        return s and s.iconID or defaultEmptyIcon
    elseif actionType == "item" then
        return C_Item.GetItemIconByID(value) or defaultEmptyIcon
    elseif actionType == "mount" then
        local _, _, icon = C_MountJournal.GetMountInfoByID(value)
        return icon or defaultEmptyIcon
    elseif actionType == "macro" then
        if _G.type(value) == "table" then
            if value.icon then
                return value.icon
            end
            local ref = value.id or value.name
            if ref then
                local _, icon = GetMacroInfo(ref)
                return icon or defaultEmptyIcon
            end
        elseif _G.type(value) == "number" or _G.type(value) == "string" then
            local _, icon = GetMacroInfo(value)
            return icon or defaultEmptyIcon
        end
        return defaultEmptyIcon
    end
    return defaultEmptyIcon
end

function RadBar:SetIconUsabilityColor(icon, isUsable)
    if not icon then
        return
    end

    local private = self.Private or {}

    if isUsable then
        icon:SetVertexColor(
            private.ICON_USABLE_R or 1,
            private.ICON_USABLE_G or 1,
            private.ICON_USABLE_B or 1
        )
    else
        icon:SetVertexColor(
            private.ICON_UNUSABLE_R or 1,
            private.ICON_UNUSABLE_G or 0.2,
            private.ICON_UNUSABLE_B or 0.2
        )
    end
end

function RadBar:IsActionUsable(actionType, actionValue)
    if not actionType or actionValue == nil then
        return true
    end

    if actionType == "spell" then
        if C_Spell and C_Spell.IsSpellUsable then
            local usable = C_Spell.IsSpellUsable(actionValue)
            if usable ~= nil then
                return usable
            end
        end
        return true
    elseif actionType == "item" then
        if C_Item and C_Item.IsUsableItem then
            local usable = C_Item.IsUsableItem(actionValue)
            if usable ~= nil then
                return usable
            end
        end
        if IsUsableItem then
            local usable = IsUsableItem(actionValue)
            if usable ~= nil then
                return usable
            end
        end
        return true
    elseif actionType == "mount" then
        if C_MountJournal and C_MountJournal.GetMountInfoByID then
            local _, _, _, _, isUsable = C_MountJournal.GetMountInfoByID(actionValue)
            if isUsable ~= nil then
                return isUsable
            end
        end
        return true
    end

    -- Macro and unknown types stay neutral.
    return true
end

function RadBar:UpdateUsabilityVisuals(forceClear)
    if not self.Core then
        return
    end

    local canTint = not forceClear
        and self.Core:IsShown()
        and self.Content
        and self.Content:IsShown()
        and not self.isCustomizing
        and not self.Core:GetAttribute("bindMode")

    if self.CenterButton and self.CenterButton.Icon then
        local hasCenter = self.Core:GetAttribute("center-macro")
        if canTint and hasCenter and self.CenterButton.ActionType then
            self:SetIconUsabilityColor(
                self.CenterButton.Icon,
                self:IsActionUsable(self.CenterButton.ActionType, self.CenterButton.ActionValue)
            )
        else
            self:SetIconUsabilityColor(self.CenterButton.Icon, true)
        end
    end

    for i, btn in ipairs(self.Buttons) do
        if btn.Icon then
            local hasAction = self.Core:GetAttribute("child" .. i .. "-macro")
            if canTint and hasAction and btn.ActionType then
                self:SetIconUsabilityColor(btn.Icon, self:IsActionUsable(btn.ActionType, btn.ActionValue))
            else
                self:SetIconUsabilityColor(btn.Icon, true)
            end
        end
    end
end
