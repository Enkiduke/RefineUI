local R, C, L = unpack(RefineUI)

----------------------------------------------------------------------------------------
--  Spell/Item IDs (idTip by Silverwind) — refactored for performance and clarity
----------------------------------------------------------------------------------------

-- Hot locals
local _G                 = _G
local tostring           = tostring
local strfind            = string.find
local IsShiftKeyDown     = IsShiftKeyDown
local IsAltKeyDown       = IsAltKeyDown
local TooltipDataProcessor = TooltipDataProcessor
local C_UnitAuras        = C_UnitAuras
local GameTooltip        = GameTooltip
local ItemRefTooltip     = ItemRefTooltip
local ShoppingTooltip1   = ShoppingTooltip1
local ShoppingTooltip2   = ShoppingTooltip2
local ItemRefShoppingTooltip1 = ItemRefShoppingTooltip1
local ItemRefShoppingTooltip2 = ItemRefShoppingTooltip2

-- Only show IDs when Shift or Alt is held
local function ModKeyActive()
    return IsShiftKeyDown() or IsAltKeyDown()
end

-- Safe hook for OnTooltipCleared (some frames may not support HookScript yet)
local function HookTooltipCleared(tt)
    if not tt or not tt.HookScript then return end
    if tt._refine_idtip_hooked then return end
    tt:HookScript("OnTooltipCleared", function(self)
        self._refine_idtip_cache = nil
    end)
    tt._refine_idtip_hooked = true
end

-- Hook commonly used tooltips once (skip nils safely)
HookTooltipCleared(GameTooltip)
HookTooltipCleared(ItemRefTooltip)
HookTooltipCleared(ItemRefShoppingTooltip1)
HookTooltipCleared(ItemRefShoppingTooltip2)
HookTooltipCleared(ShoppingTooltip1)
HookTooltipCleared(ShoppingTooltip2)

-- Decide if we should add the ID line (avoid duplicates cheaply)
local function ShouldAddIdLine(self, idStr)
    -- Fast path: per-tooltip cache
    local cache = self._refine_idtip_cache
    if cache and cache[idStr] then return false end

    -- Scan existing lines; handle anonymous tooltips safely
    local tipName    = (self.GetName and self:GetName()) or "GameTooltip"
    local namePrefix = tipName .. "TextLeft"
    local n          = (self.NumLines and self:NumLines()) or 0

    -- Localized/fallback labels
    local spellLabel = (L_TOOLTIP_SPELL_ID or "Spell ID:") .. " "
    local itemLabel  = (L_TOOLTIP_ITEM_ID  or "Item ID:")  .. " "

    for i = 1, n do
        local fs = _G[namePrefix .. i]
        if not fs then break end
        local txt = fs:GetText()
        if txt then
            -- If our labeled line or the id string is already present, skip adding
            if ((strfind(txt, spellLabel, 1, true) or strfind(txt, itemLabel, 1, true)) and strfind(txt, idStr, 1, true))
               or strfind(txt, idStr, 1, true) then
                return false
            end
        end
    end

    return true
end

local function addLine(self, id, isItem)
    if not ModKeyActive() then return end
    if not self or (self.IsForbidden and self:IsForbidden()) then return end

    local idStr = tostring(id or "")
    if idStr == "" then return end
    if not ShouldAddIdLine(self, idStr) then return end

    if isItem then
        self:AddLine("|cffffffff" .. (L_TOOLTIP_ITEM_ID or "Item ID:") .. " " .. idStr)
    else
        self:AddLine("|cffffffff" .. (L_TOOLTIP_SPELL_ID or "Spell ID:") .. " " .. idStr)
    end
    self:Show() -- ensure the new line is visible immediately

    -- Remember we added this id to avoid re-scanning on the same tooltip content
    self._refine_idtip_cache = self._refine_idtip_cache or {}
    self._refine_idtip_cache[idStr] = true
end

-- Spells (auras on units)
hooksecurefunc(GameTooltip, "SetUnitAura", function(self, unit, index, filter)
    if not ModKeyActive() then return end
    local auraInfo = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex and C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
    if auraInfo and auraInfo.spellId then
        addLine(self, auraInfo.spellId)
    end
end)

local function attachByAuraInstanceID(self, unit, auraInstanceID)
    if not ModKeyActive() then return end
    local aura = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID and C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
    if aura and aura.spellId then
        addLine(self, aura.spellId)
    end
end

hooksecurefunc(GameTooltip, "SetUnitBuffByAuraInstanceID", attachByAuraInstanceID)
hooksecurefunc(GameTooltip, "SetUnitDebuffByAuraInstanceID", attachByAuraInstanceID)

-- Spell links in chat / itemref
hooksecurefunc("SetItemRef", function(link)
    if not ModKeyActive() then return end
    local id = link and link:match("spell:(%d+)")
    if id then addLine(ItemRefTooltip, tonumber(id)) end
end)

-- Spells (data path)
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(self, data)
    if not ModKeyActive() then return end
    if self ~= GameTooltip or (self.IsForbidden and self:IsForbidden()) then return end
    if data and data.id then
        addLine(self, data.id)
    end
end)

-- Items: prefer name-based check so we don’t index nil frames at load
local whiteTooltipNames = {
    GameTooltip = true,
    ItemRefTooltip = true,
    ItemRefShoppingTooltip1 = true,
    ItemRefShoppingTooltip2 = true,
    ShoppingTooltip1 = true,
    ShoppingTooltip2 = true,
}
local function isWhiteTooltip(tt)
    local n = tt and tt.GetName and tt:GetName()
    return n and whiteTooltipNames[n]
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(self, data)
    if not ModKeyActive() then return end
    if (self.IsForbidden and self:IsForbidden()) then return end
    if isWhiteTooltip(self) and data and data.id then
        addLine(self, data.id, true)
    end
end)

-- Macros
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Macro, function(self, data)
    if not ModKeyActive() then return end
    if self.IsForbidden and self:IsForbidden() then return end

    local lineData = data and data.lines and data.lines[1]
    local tooltipType = lineData and lineData.tooltipType
    local id = lineData and lineData.tooltipID
    if not (tooltipType and id) then return end

    if tooltipType == 0 then     -- item
        addLine(self, id, true)
    elseif tooltipType == 1 then -- spell
        addLine(self, id)
    end
end)

-- Toys
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Toy, function(self, data)
    if not ModKeyActive() then return end
    if self ~= GameTooltip or (self.IsForbidden and self:IsForbidden()) then return end
    if data and data.id then
        addLine(self, data.id, true)
    end
end)
