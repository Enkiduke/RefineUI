-- RefineUI: ItemCount (bags/bank/reagent/equipped) → tooltip lines per character
-- Priorities: Performance > KISS > YAGNI > DRY > SOLID

local R, C, L = unpack(RefineUI)

-- -----------------------------
-- SavedVariables
-- -----------------------------
RefineUIItems = RefineUIItems or {}

-- -----------------------------
-- Locals
-- -----------------------------
local ADDON_NAME = ...
local frame = CreateFrame("Frame")

-- Events
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("BANKFRAME_OPENED")
frame:RegisterEvent("BANKFRAME_CLOSED")
frame:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

-- State
local pendingBagRescan, pendingBankRescan = false, false
local bankOpen = false

-- Cache: only cache positive strings; zero-count recomputes (cheap)
local countsCache = {} -- [itemID] = "header\nline1\nline2..."
local function InvalidateCountsCache() wipe(countsCache) end

-- Fast locals
local GetRealmName, UnitName, UnitFactionGroup, UnitClass =
      GetRealmName, UnitName, UnitFactionGroup, UnitClass
local C_Container_GetContainerNumSlots = C_Container.GetContainerNumSlots
local C_Container_GetContainerItemInfo = C_Container.GetContainerItemInfo
local C_Timer_After = C_Timer.After
local tonumber, pairs, wipe, format = tonumber, pairs, wipe, string.format

-- Containers
local BACKPACK_CONTAINER       = BACKPACK_CONTAINER or 0
local BANK_CONTAINER_G         = rawget(_G, "BANK_CONTAINER")        or -1
local REAGENTBANK_CONTAINER_G  = rawget(_G, "REAGENTBANK_CONTAINER") or -3
local REAGENTBAG_CONTAINER_G   = rawget(_G, "REAGENTBAG_CONTAINER")  or 5
local NUM_BAG_SLOTS_G          = rawget(_G, "NUM_BAG_SLOTS")         or 4
local NUM_BANKBAGSLOTS_G       = rawget(_G, "NUM_BANKBAGSLOTS")      or 7

local CLASS_COLORS = rawget(_G, "CUSTOM_CLASS_COLORS") or rawget(_G, "RAID_CLASS_COLORS")
local HEADER_TEXT  = (L and L["ITEM_COUNT"]) or "Item Count"

-- -----------------------------
-- Character table guard
-- -----------------------------
local function EnsureChar()
    local realm = frame._realm or GetRealmName()
    local player = frame._player or UnitName("player")

    RefineUIItems[realm] = RefineUIItems[realm] or {}
    local t = RefineUIItems[realm][player]
    if not t then
        t = {
            faction  = UnitFactionGroup("player"),
            class    = select(2, UnitClass("player")),
            bags     = {},
            bank     = {},
            equipped = {},
        }
        RefineUIItems[realm][player] = t
    else
        t.faction  = t.faction  or UnitFactionGroup("player")
        t.class    = t.class    or select(2, UnitClass("player"))
        t.bags     = t.bags     or {}
        t.bank     = t.bank     or {}
        t.equipped = t.equipped or {}
    end
    return realm, player, t
end

-- -----------------------------
-- Debounced scans
-- -----------------------------
local function scheduleBagScan()
    if pendingBagRescan then return end
    pendingBagRescan = true
    C_Timer_After(0.25, function()
        pendingBagRescan = false
        R:UpdateBagCounts()
        InvalidateCountsCache()
    end)
end

local function scheduleBankScan()
    if pendingBankRescan then return end
    pendingBankRescan = true
    C_Timer_After(0.25, function()
        pendingBankRescan = false
        R:UpdateBankCounts()
        InvalidateCountsCache()
    end)
end

-- -----------------------------
-- DRY: container scan helper
-- -----------------------------
local function ScanContainer(targetTbl, bagID)
    local n = C_Container_GetContainerNumSlots(bagID)
    if not n or n <= 0 then return end
    for slot = 1, n do
        local info = C_Container_GetContainerItemInfo(bagID, slot)
        if info and info.itemID then
            local cnt = info.stackCount or 1
            targetTbl[info.itemID] = (targetTbl[info.itemID] or 0) + cnt
        end
    end
end

-- -----------------------------
-- Scanners
-- -----------------------------
function R:UpdateBagCounts()
    local _, _, char = EnsureChar()
    wipe(char.bags)

    for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS_G do
        ScanContainer(char.bags, bag)
    end
    ScanContainer(char.bags, REAGENTBAG_CONTAINER_G) -- reagent bag
end

function R:UpdateBankCounts()
    local _, _, char = EnsureChar()
    wipe(char.bank)

    ScanContainer(char.bank, BANK_CONTAINER_G)
    ScanContainer(char.bank, REAGENTBANK_CONTAINER_G)

    for bag = (NUM_BAG_SLOTS_G + 1), (NUM_BAG_SLOTS_G + NUM_BANKBAGSLOTS_G) do
        ScanContainer(char.bank, bag)
    end
end

function R:UpdateEquippedCounts()
    local _, _, char = EnsureChar()
    wipe(char.equipped)

    local first, last = (INVSLOT_FIRST_EQUIPPED or 1), (INVSLOT_LAST_EQUIPPED or 19)
    for slot = first, last do
        local itemID = GetInventoryItemID("player", slot)
        if itemID then
            char.equipped[itemID] = (char.equipped[itemID] or 0) + 1
        end
    end
end

-- -----------------------------
-- Count → lines
-- -----------------------------
local function GetItemCounts(itemID)
    local realm = frame._realm or GetRealmName()
    local currentPlayer = frame._player or UnitName("player")
    local playerFaction = frame._playerFaction or UnitFactionGroup("player")

    local out = {}
    local realmTbl = RefineUIItems[realm]
    if not realmTbl then return out end

    for player, data in pairs(realmTbl) do
        if type(data) == "table" and data.faction == playerFaction then
            local bag  = (data.bags      and data.bags[itemID])      or 0
            local bank = (data.bank      and data.bank[itemID])      or 0
            local eqp  = (data.equipped  and data.equipped[itemID])  or 0
            local total = bag + bank + eqp
            if total > 0 then
                local c = (CLASS_COLORS and data.class and CLASS_COLORS[data.class])
                local colorStr = (c and c.colorStr) or "ffffffff"
                local name = (player == currentPlayer) and ((L and L["YOU"]) or "You") or player
                out[#out + 1] = format("|c%s%s|r: %d", colorStr, name, total)
            end
        end
    end

    return out
end

local function GetCountsString(itemID)
    local s = countsCache[itemID]
    if s ~= nil then return s end -- positive cache

    local lines = GetItemCounts(itemID)
    if #lines == 0 then
        return nil -- no negative cache: avoids stale states during refreshes
    end

    s = table.concat(lines, "\n")
    countsCache[itemID] = s
    return s
end

-- -----------------------------
-- Tooltip helpers
-- -----------------------------
local function ExtractItemID(tooltip, data)
    if data and data.id then return data.id end
    local _, link = tooltip:GetItem()
    if link then
        local id = tonumber(link:match("item:(%d+)"))
        if id then return id end
    end
    if data and data.hyperlink then
        local id = tonumber(data.hyperlink:match("item:(%d+)"))
        if id then return id end
    end
end

-- Check if our header already exists (handles in-place refreshes)
local function HasHeader(tooltip, header)
    local n = tooltip:NumLines()
    for i = 1, n do
        local line = _G[tooltip:GetName().."TextLeft"..i]
        if line and line:GetText() == header then
            return true
        end
    end
end

local function AddSpacerIfNeeded(tooltip, header)
    local num = tooltip:NumLines()
    if num <= 0 then return end
    local last = _G[tooltip:GetName().."TextLeft"..num]
    if not last then return end
    local txt = last:GetText()
    if not txt or txt == "" or txt == " " or txt == header then return end
    tooltip:AddLine(" ")
end

-- Dedupe: cleared whenever the tooltip clears or hides
local function ClearDedup(tt) tt.__RUIIC_lastID = nil end

local function OnTooltipSetItem(tooltip, data)
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end

    local itemID = ExtractItemID(tooltip, data)
    if not itemID then return end

    -- If the tooltip was refreshed (cleared & rebuilt) while visible, our header is gone.
    -- Allow re-adding regardless of lastID if header is missing.
    if tooltip.__RUIIC_lastID == itemID and HasHeader(tooltip, HEADER_TEXT) then
        return
    end

    local s = GetCountsString(itemID)
    if not s then return end

    if not HasHeader(tooltip, HEADER_TEXT) then
        AddSpacerIfNeeded(tooltip, HEADER_TEXT)
        tooltip:AddLine(s)
    else
        -- Header already present (another post-call ran after us and re-added).
        -- Nothing to do; keep it simple.
    end

    tooltip.__RUIIC_lastID = itemID
end

-- Modern, wide coverage
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltipSetItem)

-- Clear dedupe on both clear and hide to handle live refreshes
local function SafeHookScript(tt, script, fn)
    if not tt or not tt.HookScript or not tt.HasScript then return end
    if tt:HasScript(script) then tt:HookScript(script, fn) end
end
local function HookTooltip(tt)
    SafeHookScript(tt, "OnTooltipCleared", ClearDedup)
    SafeHookScript(tt, "OnHide", ClearDedup)
end

HookTooltip(GameTooltip)
HookTooltip(ItemRefTooltip)
HookTooltip(ShoppingTooltip1)
HookTooltip(ShoppingTooltip2)
HookTooltip(EmbeddedItemTooltip)

-- -----------------------------
-- Events
-- -----------------------------
local function OnEvent(self, event, ...)
    if event == "ADDON_LOADED" then
        local loaded = ...
        if loaded == ADDON_NAME or loaded == "RefineUI" then
            local realm, player = EnsureChar()
            frame._realm = realm
            frame._player = player
            frame._playerFaction = UnitFactionGroup("player")

            R:UpdateBagCounts()
            R:UpdateEquippedCounts()
            InvalidateCountsCache()
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer_After(0.1, scheduleBagScan)
        R:UpdateEquippedCounts()
        InvalidateCountsCache()

    elseif event == "BAG_UPDATE_DELAYED" then
        if bankOpen then scheduleBankScan() else scheduleBagScan() end

    elseif event == "BANKFRAME_OPENED" then
        bankOpen = true
        scheduleBankScan()

    elseif event == "BANKFRAME_CLOSED" then
        bankOpen = false

    elseif event == "PLAYERBANKSLOTS_CHANGED" then
        scheduleBankScan()

    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        R:UpdateEquippedCounts()
        InvalidateCountsCache()
    end
end

frame:SetScript("OnEvent", OnEvent)
