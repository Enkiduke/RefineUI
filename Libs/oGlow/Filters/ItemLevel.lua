local oGlow = rawget(_G, "oGlow")
local itemLevelFilter = function(...)
    for i = 1, select("#", ...) do
        local itemLink = select(i, ...)
        if itemLink then
            local _, _, _, itemEquipLoc, _, itemClassID = C_Item.GetItemInfoInstant(itemLink)
            -- Check if the item is equippable (Armor, Weapon, or specific accessories)
            if itemClassID == Enum.ItemClass.Armor or itemClassID == Enum.ItemClass.Weapon or 
               (itemClassID == Enum.ItemClass.Miscellaneous and itemEquipLoc ~= "") then
                local itemLevel = C_Item.GetDetailedItemLevelInfo(itemLink)
                if itemLevel and itemLevel > 1 then
                    return itemLevel, itemLink
                end
            end
        end
    end
end

oGlow:RegisterFilter("ItemLevel", "ItemLevel", itemLevelFilter)