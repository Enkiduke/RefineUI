local R, C, L = unpack(RefineUI)
local oGlow = rawget(_G, "oGlow")

local createItemLevelText = function(self)
    if not self.oGlowItemLevel then
        self.oGlowItemLevel = self:CreateFontString(nil, "OVERLAY")
        self.oGlowItemLevel:SetFont(C.media.normalFont, 12, "OUTLINE")
		self.oGlowItemLevel:SetShadowOffset(1, -1)
        self.oGlowItemLevel:SetPoint("TOPRIGHT", 1, -3)
    end
    return self.oGlowItemLevel
end

local itemLevelDisplay = function(frame, itemLevel, itemLink)
    -- Safety: some pipes may invoke displays with a nil frame (e.g., missing bank slot frames)
    if not frame then return end
    if itemLevel and type(itemLevel) == "number" then
        local text = createItemLevelText(frame)
        local quality = 1  -- Default to common quality
        
        if itemLink then
            quality = select(3, C_Item.GetItemInfo(itemLink)) or 1
        elseif frame.itemLink then
            quality = select(3, C_Item.GetItemInfo(frame.itemLink)) or 1
        end
        
        local r, g, b = C_Item.GetItemQualityColor(quality)
        text:SetText(itemLevel)
        text:SetTextColor(r, g, b)
        text:SetShadowOffset(1, -1)
        text:SetShadowColor(0, 0, 0, 1)
        text:Show()
        return true
    else
        if frame and frame.oGlowItemLevel then
            frame.oGlowItemLevel:Hide()
        end
    end
end

oGlow:RegisterDisplay("ItemLevel", itemLevelDisplay)
