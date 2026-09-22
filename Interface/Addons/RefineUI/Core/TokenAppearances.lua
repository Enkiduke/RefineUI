-- Shared, on-demand token collection lookup. No item loads, tooltip scans or polling.
local _, RefineUI = ...
local tokens = RefineUI.TokenAppearanceData
local tokenCache = {}
local issecretvalue = issecretvalue

local function IsCollected(appearanceID)
    return RefineUI.Collections:IsAppearanceCollected(appearanceID)
end

-- Resolve the static token variant without loading items or consulting UI state.
function RefineUI:GetTokenAppearanceData(itemLink, itemID)
    if issecretvalue and (issecretvalue(itemID) or issecretvalue(itemLink)) then return false end
    if not itemID and type(itemLink) == "string" then
        itemID = tonumber(itemLink:match("item:(%d+)"))
    end
    local data = tokens[itemID]
    if not data then return false end
    if data.Difficulties then
        if type(itemLink) ~= "string" then return true end
        local payload = itemLink:match("item:([%d:%-]+)")
        local context = payload and tonumber((select(12, strsplit(":", payload))))
        -- Do not guess normal difficulty for a bare ID or an unrecognized context.
        data = context and data.Difficulties[context]
        if not data then return true end
    end
    if data.ALLIANCE or data.HORDE then
        local faction = UnitFactionGroup("player")
        data = faction == "Alliance" and data.ALLIANCE or faction == "Horde" and data.HORDE
        if not data then return true end
    end
    return true, data
end

-- Returns supported token, all collected (nil = unresolved), class count rows.
function RefineUI:GetTokenAppearanceStatus(itemLink, itemID)
    local supported, data = self:GetTokenAppearanceData(itemLink, itemID)
    if not supported then return false end
    if not data then return true end
    local cached = tokenCache[data]
    if cached then return true, cached.collected, cached.rows end

    local rows, allCollected, resolved = {}, true, true
    for classID = 1, GetNumClasses() do
        local appearances = data[classID]
        if appearances and #appearances > 0 then
            local count, ready = 0, true
            for i = 1, #appearances do
                local collected = IsCollected(appearances[i])
                if collected == nil then ready = false end
                if collected then count = count + 1 end
            end
            rows[#rows + 1] = { classID = classID, collected = count, total = #appearances, ready = ready }
            if count ~= #appearances then allCollected = false end
            if not ready then resolved = false end
        end
    end
    if #rows == 0 then return true end
    if not resolved then return true, nil, rows end
    tokenCache[data] = { collected = allCollected, rows = rows }
    return true, allCollected, rows
end

local function RefreshTokenDisplays()
    local borders = RefineUI:GetModule("Borders")
    if borders and borders.RefreshTokenStatusIcons then borders:RefreshTokenStatusIcons() end
    if GameTooltip and GameTooltip:IsShown() and GameTooltip.GetItem then
        local _, link = GameTooltip:GetItem()
        if not (issecretvalue and issecretvalue(link)) and type(link) == "string"
            and tokens[tonumber(link:match("item:(%d+)"))] and GameTooltip.RefreshDataNextUpdate then
            GameTooltip:RefreshDataNextUpdate()
        end
    end
end

local function Invalidate()
    wipe(tokenCache)
    RefineUI:Debounce("TokenAppearances:Refresh", 0.05, RefreshTokenDisplays)
end

RefineUI.Collections:Subscribe("TokenAppearances", Invalidate)
