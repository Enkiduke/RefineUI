local R, C, L = unpack(RefineUI)

----------------------------------------------------------------------------------------
-- Tooltip Icons (inline, zero pop-in)
-- Priorities: Performance > KISS > YAGNI > DRY > SOLID
-- Strategy: prepend a |T...|t to TextLeft1 exactly once in Blizzard's post-build pass.
--           No gating, no reflow, no extra frames, no second rewrite.
----------------------------------------------------------------------------------------

-- Config
local ICON_SIZE = (C and C.tooltip and C.tooltip.iconSize) or 20

-- Keep the surface small and predictable
local whiteTooltip = R.WhiteTooltip or {
    [GameTooltip] = true,
    [ItemRefTooltip] = true,
    [ItemRefShoppingTooltip1] = true,
    [ItemRefShoppingTooltip2] = true,
    [ShoppingTooltip1] = true,
    [ShoppingTooltip2] = true,
}

-- Fast caches (false = negative cache)
local itemIconCache, spellIconCache = {}, {}

local function GetItemIconCached(id)
    local v = itemIconCache[id]
    if v ~= nil then return v or nil end
    v = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or false
    itemIconCache[id] = v
    return v or nil
end

local function GetSpellIconCached(id)
    local v = spellIconCache[id]
    if v ~= nil then return v or nil end
    v = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)) or false
    spellIconCache[id] = v
    return v or nil
end

-- Write the icon once; avoid any follow-up rewrites this frame
local TEX_FMT = "|T%s:%d:%d:0:0:64:64:5:59:5:59:%d|t %s"

local function SetTooltipIcon(tt, icon)
    if not icon or not whiteTooltip[tt] or (tt.IsForbidden and tt:IsForbidden()) then return end

    local title = _G[tt:GetName().."TextLeft1"]; if not title then return end
    local text  = title:GetText();               if not text or text == "" then return end

    -- If an icon already leads the title, do nothing (avoid double-pass flashes)
    if text:find("^|T") then return end

    title:SetFormattedText(TEX_FMT, icon, ICON_SIZE, ICON_SIZE, ICON_SIZE, text)
end

-- Items (first and only pass)
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(self, data)
    if not whiteTooltip[self] or (self.IsForbidden and self:IsForbidden()) then return end
    local id = data and data.id; if not id then return end
    local icon = GetItemIconCached(id); if icon then SetTooltipIcon(self, icon) end
end)

-- Spells
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(self, data)
    if not whiteTooltip[self] or (self.IsForbidden and self:IsForbidden()) then return end
    local id = data and data.id; if not id then return end
    local icon = GetSpellIconCached(id); if icon then SetTooltipIcon(self, icon) end
end)

-- Macros (item=0, spell=1)
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Macro, function(self, data)
    if not whiteTooltip[self] or (self.IsForbidden and self:IsForbidden()) then return end
    local line = data and data.lines and data.lines[1]; if not line then return end
    if line.tooltipType == 0 then
        local icon = GetItemIconCached(line.tooltipID); if icon then SetTooltipIcon(self, icon) end
    elseif line.tooltipType == 1 then
        local icon = GetSpellIconCached(line.tooltipID); if icon then SetTooltipIcon(self, icon) end
    end
end)
