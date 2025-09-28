local R, C, L = unpack(RefineUI)
-- if C.raidframe.plugins_aura_watch ~= true then return end

----------------------------------------------------------------------------------------
--	Based on oUF_AuraWatch(by Astromech)
----------------------------------------------------------------------------------------
local _, ns = ...
local oUF = ns.oUF

-- Use local references for frequently accessed globals
local CreateFrame, GetSpellInfo, UnitAura, UnitGUID = CreateFrame, GetSpellInfo, UnitAura, UnitGUID
local pairs, next, setmetatable = pairs, next, setmetatable

-- Upvalue constants
local PLAYER_UNITS = {
    player = true,
    vehicle = true,
    pet = true,
}

-- Use a single table for GUIDs to reduce table creation/deletion
local GUIDs = setmetatable({}, {__mode = "k"})

-- Optimize setupGUID function
local function setupGUID(guid)
    if not GUIDs[guid] then
        GUIDs[guid] = setmetatable({}, {__mode = "k"})
    end
    return GUIDs[guid]
end

-- Optimize icon management functions
local function resetIcon(icon, count, duration, remaining)
    icon:Show()
    if icon.cd then
        if duration and duration > 0 then
            icon.cd:SetCooldown(remaining - duration, duration)
            icon.cd:Show()
        else
            icon.cd:Hide()
        end
    end
    if icon.count then
        icon.count:SetText(count > 1 and count or "")
    end
    icon:SetAlpha(1)
end

local function expireIcon(icon)
    if icon.cd then icon.cd:Hide() end
    if icon.count then icon.count:SetText("") end
    icon:SetAlpha(0)
    icon:Show()
end

-- Optimize Update function
local function Update(frame, _, unit)
    if frame.unit ~= unit then return end
    local watch = frame.AuraWatch
    local icons = watch.watched
    local guid = UnitGUID(unit)
    if not guid then return end
    
    local guidTable = setupGUID(guid)
    
    for _, icon in pairs(icons) do
        icon:Hide()
    end

    for i = 1, 40 do
        local name, _, count, _, duration, expirationTime, caster, _, _, spellID = UnitAura(unit, i)
        if not name then break end
        
        local key = watch.strictMatching and spellID or name
        local icon = icons[key]
        
        if icon and not R.RaidBuffsIgnore[spellID] and (icon.anyUnit or (caster and icon.fromUnits and icon.fromUnits[caster])) then
            local remaining = expirationTime and (expirationTime - GetTime()) or 0
            resetIcon(icon, count or 0, duration or 0, remaining)
            guidTable[key] = true
        end
    end

    for key, icon in pairs(icons) do
        if not guidTable[key] then
            expireIcon(icon)
        end
    end
end

-- Optimize setupIcons function
local function setupIcons(self)
    local watch = self.AuraWatch
    local icons = watch.icons
    watch.watched = {}

    for _, icon in pairs(icons) do
        local name, _, image = GetSpellInfo(icon.spellID)
        if name then
            icon.name = name

            if not icon.cd and not (watch.hideCooldown or icon.hideCooldown) then
                local cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
                cd:SetAllPoints(icon)
                cd:SetDrawEdge(false)
                cd:SetReverse(true)
                icon.cd = cd
            end

            if not icon.icon then
                local tex = icon:CreateTexture(nil, "BACKGROUND")
                tex:SetAllPoints(icon)
                tex:SetTexture(image)
                icon.icon = tex
            end

            if not icon.count and not (watch.hideCount or icon.hideCount) then
                local count = icon:CreateFontString(nil, "OVERLAY")
                count:SetFontObject(NumberFontNormal)
                count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 0)
                icon.count = count
            end

            icon.fromUnits = icon.fromUnits or watch.fromUnits or PLAYER_UNITS
            icon.anyUnit = icon.anyUnit == nil and watch.anyUnit or icon.anyUnit

            watch.watched[watch.strictMatching and icon.spellID or name] = icon

            if watch.PostCreateIcon then watch:PostCreateIcon(icon, icon.spellID, name, self) end
        else
            print("|cffff0000RefineUI: AuraWatch spell ID ["..tostring(icon.spellID).."] no longer exists!|r")
        end
    end
end

-- Keep Enable and Disable functions largely the same
local function Enable(self)
    if self.AuraWatch then
        self:RegisterEvent("UNIT_AURA", Update)
        setupIcons(self)
        return true
    end
    return false
end

local function Disable(self)
    if self.AuraWatch then
        self:UnregisterEvent("UNIT_AURA", Update)
        for _, icon in pairs(self.AuraWatch.icons) do
            icon:Hide()
        end
    end
end

oUF:AddElement("AuraWatch", Update, Enable, Disable)