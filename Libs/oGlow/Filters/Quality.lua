local oGlow = rawget(_G, "oGlow")
local function quality(...)
    local quality = -1
    local numItems = select("#", ...)

    for i = 1, numItems do
        local itemLink = select(i, ...)
        if itemLink then
            local _, _, itemQuality = C_Item.GetItemInfo(itemLink)
            if itemQuality and itemQuality > quality then
                quality = itemQuality
                if quality == 5 then  -- Legendary quality, no need to check further
                    break
                end
            end
        end
    end

    return quality >= 1 and quality or nil
end

oGlow:RegisterFilter("Quality border", "Border", quality)