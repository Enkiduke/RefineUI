local AddOnName, RefineUI = ...
local Config = RefineUI.Config
local Media = RefineUI.Media

----------------------------------------------------------------------------------------
--	Item/Spell Icons in Tooltips (Modified Tipachu by Tuller)
----------------------------------------------------------------------------------------
-- Call Modules
local TI = RefineUI:RegisterModule("TooltipIcons")

local function setTooltipIcon(self, icon)
    if not icon then return end
    local title = _G[self:GetName().."TextLeft1"]
    if not title then return end
    
    -- GetText() can return a secret value in WoW 12.0, use pcall for safety
    local success, text = pcall(function() return title:GetText() end)
    if not success or not text then return end
    
    -- Check if icon already exists using pcall since text operations on secret values will fail
    local checkSuccess, hasIcon = pcall(function() return text:find("|T"..icon) end)
    
    if checkSuccess and not hasIcon then
        pcall(function()
            -- Simple 20x20 icon with 2px padding crop (4-60 out of 64)
            title:SetFormattedText("|T%s:20:20:0:0:64:64:4:60:4:60|t %s", icon, text)
        end)
    end
end

local whiteTooltip = {
	[GameTooltip] = true,
	[ItemRefTooltip] = true,
	[ItemRefShoppingTooltip1] = true,
	[ItemRefShoppingTooltip2] = true,
	[ShoppingTooltip1] = true,
	[ShoppingTooltip2] = true,
}

function TI:OnEnable()
    -- Use consolidated Item dispatcher for item icons
    local TT = RefineUI:GetModule("Tooltip")
    if TT and TT.RegisterItemHandler then
        TT:RegisterItemHandler("TooltipIcons", function(tooltip, data)
            if whiteTooltip[tooltip] then
                local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(data.id)
                setTooltipIcon(tooltip, icon)
            end
        end)
    end

    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(self, data)
        if whiteTooltip[self] and not self:IsForbidden() then
            if data and data.id then
                local icon = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(data.id))
                setTooltipIcon(self, icon)
            end
        end
    end)

    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Macro, function(self, data)
        if whiteTooltip[self] and not self:IsForbidden() then
            local lineData = data.lines and data.lines[1]
            local tooltipType = lineData and lineData.tooltipType
            if not tooltipType then return end

            if tooltipType == 0 then -- item
                local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(lineData.tooltipID)
                setTooltipIcon(self, icon)
            elseif tooltipType == 1 then -- spell
                local icon = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(lineData.tooltipID))
                setTooltipIcon(self, icon)
            end
        end
    end)
end
