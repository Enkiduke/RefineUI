local R, C, L = unpack(RefineUI)

-- Minimal prototype: hide Blizzard Container frames and show a combined bag with headers
local Bags = CreateFrame("Frame", "RefineUI_BagsPrototype", UIParent)
Bags:SetSize(520, 420)
Bags:SetPoint("CENTER")
Bags:Hide()

Bags.bg = Bags:CreateTexture(nil, "BACKGROUND")
Bags.bg:SetAllPoints()
Bags.bg:SetColorTexture(0, 0, 0, 0.75)

Bags.title = Bags:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
Bags.title:SetPoint("TOP", 0, -12)
Bags.title:SetText("Backpack")

-- Close button (simple)
local close = CreateFrame("Button", nil, Bags, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -6, -6)
close:SetScript("OnClick", function() Bags:Hide() end)

local HEADER_HEIGHT = 20
local SLOT_SIZE = 36
local PADDING = 6

-- Safe wrappers for container API (use C_Container when available)
local ContainerAPI = _G.C_Container

-- Cache the most likely container API functions into locals (prefer C_Container)
local c_GetNumSlots = (ContainerAPI and ContainerAPI.GetContainerNumSlots) or _G.GetContainerNumSlots
local c_GetItemID = (ContainerAPI and ContainerAPI.GetContainerItemID) or _G.GetContainerItemID
local c_GetItemInfoFunc = (ContainerAPI and ContainerAPI.GetContainerItemInfo) or _G.GetContainerItemInfo
local c_GetItemLink = (ContainerAPI and ContainerAPI.GetContainerItemLink) or _G.GetContainerItemLink
local c_PickupContainerItem = (ContainerAPI and ContainerAPI.PickupContainerItem) or _G.PickupContainerItem
local c_UseContainerItem = (ContainerAPI and ContainerAPI.UseContainerItem) or _G.UseContainerItem

local function GetNumSlots(bag)
    if type(c_GetNumSlots) == "function" then
        local ok, res = pcall(c_GetNumSlots, bag)
        if ok then return res or 0 end
    end
    return 0
end

local function GetItemIDFromSlot(bag, slot)
    if type(c_GetItemID) == "function" then
        local ok, res = pcall(c_GetItemID, bag, slot)
        if ok and res then return res end
    end
    -- try container info function which may return itemID
    if type(c_GetItemInfoFunc) == "function" then
        local ok, info = pcall(c_GetItemInfoFunc, bag, slot)
        if ok and info then
            if type(info) == "table" and info.itemID then return info.itemID end
            -- older APIs return multiple results; try to find numeric
            if type(info) ~= "table" then
                -- single return value not an itemID
            end
        end
    end
    -- Fallback: return nil if nothing available
    return nil
end

local function GetContainerInfo(bag, slot)
    if type(c_GetItemInfoFunc) == "function" then
        local ok, res = pcall(c_GetItemInfoFunc, bag, slot)
        if ok then return res end
    end
    return nil
end

local function GetContainerLink(bag, slot)
    if type(c_GetItemLink) == "function" then
        local ok, res = pcall(c_GetItemLink, bag, slot)
        if ok then return res end
    end
    return nil
end

local function GetStackCount(bag, slot)
    -- prefer C_Container style table
    if ContainerAPI and ContainerAPI.GetContainerItemInfo then
        local ok, info = pcall(ContainerAPI.GetContainerItemInfo, bag, slot)
        if ok and info and type(info) == "table" and info.stackCount then return info.stackCount end
    end
    -- fallback to classic API
    if GetContainerItemInfo then
        local ok, _, count = pcall(GetContainerItemInfo, bag, slot)
        if ok and count and type(count) == "number" then return count end
    end
    return 0
end

local headerPool = {}
local slotPool = {}
local activeHeaders = {}
local activeSlots = {}
local blizzardPool = {}
local blizzardOriginalParent = {}

local function AcquireHeader()
    local f = tremove(headerPool)
    if f then return f end
    f = CreateFrame("Frame", nil, Bags)
    f:SetSize(1, HEADER_HEIGHT)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.text:SetPoint("LEFT", 8, 0)
    f:EnableMouse(false)
    return f
end

local function ReleaseHeader(f)
    f:Hide()
    f.text:SetText("")
    tinsert(headerPool, f)
end

local function AcquireSlot()
    -- Prefer reusing Blizzard container buttons if available
    local b = tremove(blizzardPool)
    if b then
        -- store original parent so we can restore later
        blizzardOriginalParent[b] = b:GetParent()
        b:SetParent(Bags)
    b.__isBlizzard = true
        b:Show()
        return b
    end

    b = tremove(slotPool)
    if b then return b end
    -- Use Blizzard's secure action button template so clicks are protected-safe
    b = CreateFrame("Button", nil, Bags, "SecureActionButtonTemplate")
    b:SetSize(SLOT_SIZE, SLOT_SIZE)
    -- ItemButtonTemplate provides .icon and .Count on some clients; create fallbacks if missing
    if not b.icon then
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 2, -2)
        b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    end
    if not b.Count and not b.count then
        b.count = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    end
    -- highlight is already provided by template, but ensure frame strata
    b:SetFrameStrata("DIALOG")
    b:SetFrameLevel((Bags:GetFrameLevel() or 1) + 10)
    return b
end

local function ReleaseSlot(b)
    -- If this slot was a Blizzard button, return it to its original parent
    if blizzardOriginalParent[b] then
        local p = blizzardOriginalParent[b]
        blizzardOriginalParent[b] = nil
        b:SetParent(p)
        b.__isBlizzard = nil
        b.bagID = nil
        b.slotIndex = nil
        if b.ClearAllPoints then b:ClearAllPoints() end
        b:Hide()
        return
    end

    b:Hide()
    if b.icon then b.icon:SetTexture(nil) end
    if b.Count then b.Count:SetText("") end
    if b.count then b.count:SetText("") end
    tinsert(slotPool, b)
end

local function CollectBlizzardButtons()
    wipe(blizzardPool)
    -- Combined frame pool
    if _G.ContainerFrameCombinedBags and _G.ContainerFrameCombinedBags.itemButtonPool then
        for btn in _G.ContainerFrameCombinedBags.itemButtonPool:EnumerateActive() do
            if btn and btn:IsObjectType("Button") then tinsert(blizzardPool, btn) end
        end
    end
    -- Individual container frames
    for i = 1, 12 do
        local f = _G["ContainerFrame"..i]
        if f and f.itemButtonPool then
            for btn in f.itemButtonPool:EnumerateActive() do
                if btn and btn:IsObjectType("Button") then tinsert(blizzardPool, btn) end
            end
        elseif f then
            for _, child in ipairs({f:GetChildren()}) do
                if child and child.icon and child:IsObjectType("Button") then tinsert(blizzardPool, child) end
            end
        end
    end
    -- debug: report how many blizzard buttons we found
    print("RefineUI Bags: collected blizzard buttons =", #blizzardPool)
end

local function GetItemCategory(bag, slot)
    local itemID = GetItemIDFromSlot(bag, slot)
    if not itemID then return "Empty" end
    -- Use the item type string (e.g. "Consumable", "Armor", "Misc") when available
    local itemType = select(6, GetItemInfo(itemID))
    if itemType and itemType ~= "" then return itemType end
    return "Other"
end

local function BuildCombined()
    -- try collect Blizzard buttons first so we can reuse secure buttons
    CollectBlizzardButtons()
    -- Release all existing header and slot widgets
    for _, h in ipairs(activeHeaders) do
        ReleaseHeader(h)
    end
    wipe(activeHeaders)
    for _, s in ipairs(activeSlots) do
        ReleaseSlot(s)
    end
    wipe(activeSlots)

    -- Simple grouping: iterate all bag slots and group by item type string
    local groups = {}
    for bag = 0, NUM_BAG_SLOTS do
        local numSlots = GetNumSlots(bag)
        for slot = 1, numSlots do
            local cat = GetItemCategory(bag, slot)
            groups[cat] = groups[cat] or {}
            tinsert(groups[cat], {bag = bag, slot = slot})
        end
    end

    -- Desired category order for display
    local order = {"Consumable", "Trade Goods", "Quest", "Armor", "Container", "Gem", "Miscellaneous", "Empty", "Other"}

    -- Layout starting below title
    local y = -44
    local left = 12
    local cols = 10
    for _, cat in ipairs(order) do
        local items = groups[cat]
        if items and #items > 0 then
            local header = AcquireHeader()
            header:SetPoint("TOPLEFT", left, y)
            header.text:SetText(cat)
            header:Show()
            tinsert(activeHeaders, header)

            y = y - HEADER_HEIGHT - 6

            local col = 0
            local row = 0
            for i, loc in ipairs(items) do
                local slot = AcquireSlot()
                slot:SetPoint("TOPLEFT", left + col * (SLOT_SIZE + 6), y - row * (SLOT_SIZE + 6))
                slot:Show()
                tinsert(activeSlots, slot)

                -- If this is a Blizzard container button, assign bag/slot and call its update function so native behavior remains
                if slot.__isBlizzard then
                    slot.bagID = loc.bag
                    slot.slotIndex = loc.slot
                    if ContainerFrameItemButton_Update then
                        pcall(ContainerFrameItemButton_Update, slot)
                    end
                else
                    -- populate icon using the itemID
                    local itemID = GetItemIDFromSlot(loc.bag, loc.slot)
                    local texture = itemID and select(10, GetItemInfo(itemID))
                    if texture then
                        slot.icon:SetTexture(texture)
                        slot.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
                    end

                    -- show stack count
                    local count = GetStackCount(loc.bag, loc.slot)
                    if count and count > 1 then
                        if slot.Count then slot.Count:SetText(tostring(count)) end
                        if slot.count then slot.count:SetText(tostring(count)) end
                    else
                        if slot.Count then slot.Count:SetText("") end
                        if slot.count then slot.count:SetText("") end
                    end

                    -- secure action: set item attribute so the secure template handles use/pickup without calling protected APIs
                    local itemLink = GetContainerLink(loc.bag, loc.slot)
                    local itemID = GetItemIDFromSlot(loc.bag, loc.slot)
                    local itemAttr = itemLink or (itemID and ("item:" .. tostring(itemID)))
                    if itemAttr then
                        slot:SetAttribute("type", "item")
                        slot:SetAttribute("item", itemAttr)
                    else
                        -- clear
                        slot:SetAttribute("type", nil)
                        slot:SetAttribute("item", nil)
                    end

                    -- tooltip and shift-click link insertion
                    local bbag, bslot = loc.bag, loc.slot
                    slot:HookScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        local link = GetContainerLink(bbag, bslot)
                        if link then GameTooltip:SetHyperlink(link) end
                    end)
                    slot:HookScript("OnLeave", function() GameTooltip:Hide() end)
                    slot:HookScript("OnClick", function(self, button)
                        if IsShiftKeyDown() then
                            local link = GetContainerLink(bbag, bslot)
                            if link and ChatEdit_GetLastActiveWindow then
                                local edit = ChatEdit_GetLastActiveWindow()
                                if edit then edit:Insert(link) end
                            end
                        end
                    end)
                end

                col = col + 1
                if col >= cols then col = 0; row = row + 1 end
            end

            y = y - (row + 1) * (SLOT_SIZE + 6) - 10
        end
    end

    -- Any leftover categories not in order
    for cat, items in pairs(groups) do
        local found
        for _, k in ipairs(order) do if k == cat then found = true break end end
        if not found and #items > 0 then
            local header = AcquireHeader()
            header:SetPoint("TOPLEFT", left, y)
            header.text:SetText(cat)
            header:Show()
            tinsert(activeHeaders, header)

            y = y - HEADER_HEIGHT - 6
            local col = 0
            local row = 0
            for i, loc in ipairs(items) do
                local slot = AcquireSlot()
                slot:SetPoint("TOPLEFT", left + col * (SLOT_SIZE + 6), y - row * (SLOT_SIZE + 6))
                slot:Show()
                tinsert(activeSlots, slot)

                local itemID = GetItemIDFromSlot(loc.bag, loc.slot)
                local texture = itemID and select(10, GetItemInfo(itemID))
                if texture then
                    slot.icon:SetTexture(texture)
                    slot.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
                end

                col = col + 1
                if col >= cols then col = 0; row = row + 1 end
            end

        y = y - (row + 1) * (SLOT_SIZE + 6) - 10
        end
    end

    -- Resize Bags frame to fit content (add some padding)
    local height = math.abs(y) + 48
    Bags:SetHeight(math.max(120, height))
end

-- Safe runner: run BuildCombined in pcall and retry if runtime APIs aren't ready yet
local function SafeBuildCombined()
    local ok, err = pcall(BuildCombined)
    if not ok then
        -- print a useful message and retry once after 1 second
        if type(err) == "string" then
            print("RefineUI Bags: BuildCombined failed - retrying: ", err)
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(1, SafeBuildCombined)
        end
    end
end

local function OnEvent(self, event, ...)
    if event == "PLAYER_LOGIN" or event == "BAG_UPDATE_DELAYED" or event == "BAG_UPDATE" then
        SafeBuildCombined()
    end
end

Bags:SetScript("OnEvent", OnEvent)
Bags:RegisterEvent("PLAYER_LOGIN")
Bags:RegisterEvent("BAG_UPDATE")
Bags:RegisterEvent("BAG_UPDATE_DELAYED")

-- Slash to toggle prototype
SLASH_REFBAGS1 = "/refbags"
SlashCmdList["REFBAGS"] = function()
    if Bags:IsShown() then Bags:Hide() else Bags:Show() end
end

-- Hide Blizzard container frames while our bag is visible
local hiddenFrames = {}
local function HideBlizzardBags()
    -- Combined frame
    if _G.ContainerFrameCombinedBags and _G.ContainerFrameCombinedBags:IsShown() then
        hiddenFrames[#hiddenFrames+1] = _G.ContainerFrameCombinedBags
        _G.ContainerFrameCombinedBags:Hide()
    end
    -- Individual container frames (1..12)
    for i = 1, 12 do
        local f = _G["ContainerFrame"..i]
        if f and f:IsShown() then
            hiddenFrames[#hiddenFrames+1] = f
            f:Hide()
        end
    end
end

local function RestoreBlizzardBags()
    for _, f in ipairs(hiddenFrames) do
        if f and f.Show then f:Show() end
    end
    wipe(hiddenFrames)
end

-- Keep Blizzard hidden while Bags is shown
Bags:HookScript("OnShow", function()
    HideBlizzardBags()
end)
Bags:HookScript("OnHide", function()
    RestoreBlizzardBags()
end)
