local R, C, L = unpack(RefineUI)
local _, ns = ...
local oUF = ns.oUF
-- Use existing UF table if present; otherwise create a new one we assign back at the end
local UF = R.UF or {}

----------------------------------------------------------------------------------------
-- Upvalues and Constants
----------------------------------------------------------------------------------------
local UnitCanAttack, UnitIsPlayer, UnitClass, UnitReaction, GetTime, GetNetStats, UnitChannelInfo, CreateFrame =
    UnitCanAttack, UnitIsPlayer, UnitClass, UnitReaction, GetTime, GetNetStats, UnitChannelInfo, CreateFrame
local UnitIsConnected, UnitIsDead, UnitIsGhost, UnitIsTapDenied, UnitPower, UnitPowerMax, UnitPowerType =
    UnitIsConnected, UnitIsDead, UnitIsGhost, UnitIsTapDenied, UnitPower, UnitPowerMax, UnitPowerType
local UnitIsFriend, UnitFactionGroup, UnitIsPVPFreeForAll, UnitIsPVP =
    UnitIsFriend, UnitFactionGroup, UnitIsPVPFreeForAll, UnitIsPVP
local floor, abs, string, math, pairs, ipairs, next, unpack =
    floor, abs, string, math, pairs, ipairs, next, unpack
local floor, format, min = math.floor, string.format, math.min

local PLAYER = "player"
local VEHICLE = "vehicle"
local MAGIC = "Magic"

----------------------------------------------------------------------------------------
-- Globals
----------------------------------------------------------------------------------------
R.frameWidth = C.unitframes.frameWidth
R.frameHeight = C.unitframes.healthHeight + C.unitframes.powerHeight

R.partyWidth = C.group.partyWidth
R.partyHeight = C.group.partyHealthHeight + C.group.partyPowerHeight

C.group.icon_multiplier = (C.group.partyHealthHeight + C.group.partyPowerHeight) / 26

-- R.raidWidth = C.raid.frameWidth
-- R.raidHeight = C.raid.healthHeight + C.raid.powerHeight

----------------------------------------------------------------------------------------
--	General Functions
----------------------------------------------------------------------------------------
UF.UpdateAllElements = function(frame)
    for _, v in ipairs(frame.__elements) do
        v(frame, "UpdateElement", frame.unit)
    end
end

-- (no-op) UF table already defined above

local playerUnits = {
    player = true,
    pet = true,
    vehicle = true
}

-- per-castbar ticks will be stored on the Castbar instance (Castbar.ticks)

local TIME_UNITS = {
    {86400, "%dd"},
    {3600, "%dh"},
    {60, "%dm"},
    {1, "%d"},
}

----------------------------------------------------------------------------------------
-- Centralized styling helpers
----------------------------------------------------------------------------------------
function UF.ApplyFrameTemplate(frame, template, opts)
    if not frame or not frame.SetTemplate then return end
    opts = opts or {}

    frame:SetTemplate(template or "Default")

    if opts.frameStrata then frame:SetFrameStrata(opts.frameStrata) end
    if opts.frameLevel ~= nil then
        frame:SetFrameLevel(opts.frameLevel)
    elseif opts.levelOffset then
        local lvl = frame:GetFrameLevel() + opts.levelOffset
        if lvl < 0 then lvl = 0 end
        frame:SetFrameLevel(lvl)
    end

    local border = frame.border
    if border and border.SetFrameLevel then
        local borderLvl = frame:GetFrameLevel() + (opts.borderLevelOffset or 1)
        if borderLvl < 0 then borderLvl = 0 end
        border:SetFrameLevel(borderLvl)
    end
    if border and opts.borderStrata then
        border:SetFrameStrata(opts.borderStrata)
    end
end

function UF.ApplyBackdrop(frame, template, opts)
    if not frame or not frame.CreateBackdrop then return end
    opts = opts or {}

    if not frame.backdrop then
        frame:CreateBackdrop(template or "Default")
    else
        if template and frame.backdrop.SetTemplate then
            frame.backdrop:SetTemplate(template)
        end
    end

    local b = frame.backdrop
    if not b then return end
    -- Make backdrop follow parent strata by default
    if opts.backdropStrata then
        b:SetFrameStrata(opts.backdropStrata)
    else
        b:SetFrameStrata(frame:GetFrameStrata())
    end
    if opts.backdropLevel ~= nil then
        b:SetFrameLevel(opts.backdropLevel)
    elseif opts.backdropLevelOffset then
        local lvl = frame:GetFrameLevel() + opts.backdropLevelOffset
        if lvl < 0 then lvl = 0 end
        b:SetFrameLevel(lvl)
    end
    -- Normalize border layering
    if b.border and b.border.SetFrameLevel then
        local bl = b:GetFrameLevel() + (opts.borderLevelOffsetOnBackdrop or 0)
        if bl < 0 then bl = 0 end
        b.border:SetFrameLevel(bl)
    end
    if b.border and opts.borderStrata then
        b.border:SetFrameStrata(opts.borderStrata)
    end
end

local function FormatTime(s)
    for i = 1, #TIME_UNITS do
        if s >= TIME_UNITS[i][1] then
            return format(TIME_UNITS[i][2], floor(s / TIME_UNITS[i][1] + 0.5))
        end
    end
    return format("%.1f", s)
end



----------------------------------------------------------------------------------------
--	Unit Categorization Function
----------------------------------------------------------------------------------------
-- local unitPatterns = {
--     { "^player$",      "player" },
--     { "^target$",      "target" },
--     { "^focus$",       "focus" },
--     { "^pet$",         "pet" },
--     { "^arena%d+$",    "arena" },
--     { "^boss%d+$",     "boss" },
--     { "^party%d+$",    "party" },
--     { "^raid%d+$",     "raid" },
--     { "^partypet%d+$", "pet" },
--     { "^raidpet%d+$",  "pet" },
-- }

-- local singleUnits = {
--     player = true,
--     target = true,
--     focus = true,
--     pet = true,
--     arena = true,
--     boss = true
-- }

-- -- This function categorizes a unit based on its name.
-- function UF.CategorizeUnit(self)
-- 	if self:GetParent():GetName():match("RefineUI_Party") then
-- 		self.isPartyRaid = true
-- 	elseif self:GetParent():GetName():match("RefineUI_Raid") then
-- 		self.isPartyRaid = true
--     else
--         self.isSingleUnit = true
-- 	end

--     for _, pattern in ipairs(unitPatterns) do
--         if string.match(unit, pattern[1]) then
--             local genericType = pattern[2]
--             return {
--                 isSingleUnit = singleUnits[genericType] or false,  -- True if it's a single unit like player, target, etc.
--                 isPartyRaid = genericType == "party" or genericType == "raid", -- True if it's a party or raid member
--                 genericType =
--                     genericType                                    -- The generic type of the unit (e.g., "player", "target", "raid")
--             }
--         end
--     end

--     -- If no match found, treat it as a single unit (default behavior)
--     return {
--         isSingleUnit = true,
--         isPartyRaid = false,
--         genericType = unit
--     }
-- end

----------------------------------------------------------------------------------------
-- Local Functions
----------------------------------------------------------------------------------------
local function SetHealthColor(health, r, g, b)
    health:SetStatusBarColor(r, g, b)
    if health.bg and health.bg.multiplier then
        local mu = health.bg.multiplier
        health.bg:SetVertexColor(r * mu, g * mu, b * mu)
    end
end

local function FormatHealthText(min, max, r, g, b)
    if C.unitframes.colorValue then
        if min ~= max then
            return string.format("|cffAF5050%d|r |cffD7BEA5-|r |cff%02x%02x%02x%d|r",
                floor(min / max * 100),
                r * 255, g * 255, b * 255, floor(min / max * 100))
        else
            return string.format("|cffr")
        end
    else
        return string.format("|cffffffff%d|r", floor(min / max * 100 + 0.5))
    end
end

local function SetCastbarColor(Castbar, r, g, b)
    -- Skip if color unchanged
    if Castbar._lastR == r and Castbar._lastG == g and Castbar._lastB == b then return end

    Castbar:SetStatusBarColor(r, g, b)

    -- Single strategy: tint background to the same hue at low alpha
    if Castbar.bg and Castbar.bg.SetVertexColor then
        Castbar.bg:SetVertexColor(r, g, b, 0.1)
    end

    -- Match border tint with bar color
    if Castbar.border and Castbar.border.SetBackdropBorderColor then
        Castbar.border:SetBackdropBorderColor(r, g, b)
    end
    if Castbar.Button and Castbar.Button.border and Castbar.Button.border.SetBackdropBorderColor then
        Castbar.Button.border:SetBackdropBorderColor(r, g, b)
    end

    Castbar._lastR, Castbar._lastG, Castbar._lastB = r, g, b
end

local function SetButtonColor(button, r, g, b)
    button:SetBackdropBorderColor(r, g, b)
    if button.backdrop and button.backdrop.border then
        button.backdrop.border:SetBackdropBorderColor(r, g, b)
    end
end

-- duplicate removed; using canonical UF.CreateAuraTimer below

-- removed older tick helper; canonical version lives in Cast Bar Functions section below

----------------------------------------------------------------------------------------
-- Portrait helpers (lazy creation to avoid unused high-strata textures)
----------------------------------------------------------------------------------------
function UF.EnsurePortraitRadial(self)
    if not self then return end
    if self.PortraitRadialStatusbar then return self.PortraitRadialStatusbar end
    if not self.PortraitFrame or type(R.CreateRadialStatusBar) ~= "function" then return end

    local radial = R.CreateRadialStatusBar(self.PortraitFrame)
    radial:SetAllPoints(self.PortraitFrame)
    radial:SetTexture("Interface\\AddOns\\RefineUI\\Media\\Textures\\PortraitBorder.blp")
    radial:SetVertexColor(0, 0.8, 0.8, 0.75)
    -- Follow parent strata to keep layering predictable; keep hidden until needed
    radial:SetFrameStrata(self.PortraitFrame:GetFrameStrata())
    radial:Hide()

    self.PortraitRadialStatusbar = radial
    return radial
end

function UF.EnsurePortraitGlow(self)
    if not self then return end
    if self.PortraitGlow then return self.PortraitGlow end
    if not self.PortraitFrame or not self.BorderTexture then return end

    local glow = self.PortraitFrame:CreateTexture(nil, 'BACKGROUND')
    glow:SetAllPoints(self.BorderTexture)
    glow:SetTexture(C.media.portraitGlow)
    glow:SetVertexColor(1, 1, 1, .6)
    glow:SetDrawLayer("OVERLAY", 1)
    glow:Hide()

    self.PortraitGlow = glow
    return glow
end

----------------------------------------------------------------------------------------
-- UnitFrame Functions
----------------------------------------------------------------------------------------
-- Update Health
UF.PostUpdateHealth = function(health, unit, min, max)
    if unit and unit:find("arena%dtarget") then return end
    -- If the underlying unit (GUID) changed, clear cached text/colors so we don't show stale values
    local guid = unit and UnitGUID and UnitGUID(unit)
    if health._lastGUID ~= guid then
        health._lastGUID = guid
        health._lastTextPercent = nil
        health._lastStatusKey = nil
        health._lastTextR, health._lastTextG, health._lastTextB = nil, nil, nil
        health._lastR, health._lastG, health._lastB = nil, nil, nil
    end
    
    local disconnected = not UnitIsConnected(unit)
    local dead = UnitIsDead(unit)
    local ghost = UnitIsGhost(unit)
    
    if disconnected or dead or ghost then
        health:SetValue(0)
        local statusKey = disconnected and "OFFLINE" or (dead and "DEAD" or "GHOST")
        if health._lastStatusKey ~= statusKey then
            health.value:SetText("|cffD7BEA5" .. (disconnected and L_UF_OFFLINE or (dead and L_UF_DEAD or L_UF_GHOST)) .. "|r")
            health._lastStatusKey = statusKey
        end
        return
    end
    
    local r, g, b
    if UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        if class then
            local color = R.oUF_colors.class[class]
            if color then
                r, g, b = color[1], color[2], color[3]
                if health._lastR ~= r or health._lastG ~= g or health._lastB ~= b then
                    health:SetStatusBarColor(r, g, b)
                end
            end
        end
    else
        local reaction = UnitReaction(unit, "player")
        if reaction then
            local color = R.oUF_colors.reaction[reaction]
            if color then
                r, g, b = color[1], color[2], color[3]
                if health._lastR ~= r or health._lastG ~= g or health._lastB ~= b then
                    health:SetStatusBarColor(r, g, b)
                end
            end
        end
    end
    
    if unit == "pet" then
        local _, class = UnitClass("player")
        r, g, b = unpack(R.oUF_colors.class[class])
        if health._lastR ~= r or health._lastG ~= g or health._lastB ~= b then
            health:SetStatusBarColor(r, g, b)
            if health.bg and health.bg.multiplier then
                local mu = health.bg.multiplier
                health.bg:SetVertexColor(r * mu, g * mu, b * mu)
            end
        end
    end
    
    if C.unitframes.barColorValue == true and not UnitIsTapDenied(unit) then
        r, g, b = health:GetStatusBarColor()
        local newr, newg, newb = oUF:ColorGradient(min, max, 1, 0, 0, 1, 1, 0, r, g, b)
        
        local colorChanged = (health._lastR ~= newr or health._lastG ~= newg or health._lastB ~= newb)
        if colorChanged then
            health:SetStatusBarColor(newr, newg, newb)
            if health.bg and health.bg.multiplier then
                local mu = health.bg.multiplier
                health.bg:SetVertexColor(newr * mu, newg * mu, newb * mu)
            end
        end
        r, g, b = newr, newg, newb
    end
    
    if min ~= max then
        local percent = floor(min / max * 100)
        local tr, tg, tb = oUF:ColorGradient(min, max, 0.69, 0.31, 0.31, 0.65, 0.63, 0.35, 0.33, 0.59, 0.33)
        if C.unitframes.colorValue == true then
            if percent ~= health._lastTextPercent or tr ~= (health._lastTextR or -1) or tg ~= (health._lastTextG or -1) or tb ~= (health._lastTextB or -1) then
                health.value:SetFormattedText("|cff%02x%02x%02x%d|r", tr * 255, tg * 255, tb * 255, percent)
                health._lastTextPercent, health._lastTextR, health._lastTextG, health._lastTextB = percent, tr, tg, tb
            end
        else
            if percent ~= health._lastTextPercent then
                health.value:SetFormattedText("|cffffffff%d|r", percent)
                health._lastTextPercent = percent
                health._lastTextR, health._lastTextG, health._lastTextB = nil, nil, nil
            end
        end
    else
        if C.unitframes.colorValue == true then
            if health._lastTextPercent ~= 100 or health._lastTextR ~= 0.33 or health._lastTextG ~= 0.59 or health._lastTextB ~= 0.33 then
                health.value:SetFormattedText("|cff559655%d|r", 100)
                health._lastTextPercent, health._lastTextR, health._lastTextG, health._lastTextB = 100, 0.33, 0.59, 0.33
            end
        else
            if health._lastTextPercent ~= 100 then
                health.value:SetFormattedText("|cffffffff%d|r", 100)
                health._lastTextPercent = 100
                health._lastTextR, health._lastTextG, health._lastTextB = nil, nil, nil
            end
        end
    end

    -- Cache last applied bar color for future comparisons
    if r and g and b then
        health._lastR, health._lastG, health._lastB = r, g, b
    end
end

UF.PostUpdateRaidHealth = function(health, unit, min, max)
    local self = health:GetParent()
    local power = self.Power
    local border = self.backdrop
    if not UnitIsConnected(unit) or UnitIsDead(unit) or UnitIsGhost(unit) then
        health:SetValue(0)
        local key = not UnitIsConnected(unit) and "OFFLINE" or (UnitIsDead(unit) and "DEAD" or "GHOST")
        if health._lastStatusKey ~= key then
            local text = (key == "OFFLINE" and L_UF_OFFLINE) or (key == "DEAD" and L_UF_DEAD) or L_UF_GHOST
            health.value:SetText("|cffD7BEA5" .. text .. "|r")
            health._lastStatusKey = key
        end
    else
        local r, g, b
    if not UnitIsPlayer(unit) and UnitIsFriend(unit, "player") then
            local c = R.oUF_colors.reaction[5]
            if c then
                r, g, b = c[1], c[2], c[3]
                if health._lastR ~= r or health._lastG ~= g or health._lastB ~= b then
                    health:SetStatusBarColor(r, g, b)
                    if health.bg and health.bg.multiplier then
                        local mu = health.bg.multiplier
                        health.bg:SetVertexColor(r * mu, g * mu, b * mu)
                    end
                end
            end
        end
        if C.unitframes.barColorValue == true and not UnitIsTapDenied(unit) then
            r, g, b = health:GetStatusBarColor()
            local newr, newg, newb = oUF:ColorGradient(min, max, 1, 0, 0, 1, 1, 0, r, g, b)
            local changed = (health._lastR ~= newr or health._lastG ~= newg or health._lastB ~= newb)
            if changed then
                health:SetStatusBarColor(newr, newg, newb)
                if health.bg and health.bg.multiplier then
                    local mu = health.bg.multiplier
                    health.bg:SetVertexColor(newr * mu, newg * mu, newb * mu)
                end
            end
        end
        local pct = math.floor(min / max * 100 + .5)
        if health._lastTextPercent ~= pct then
            health.value:SetText("|cffffffff" .. pct .. "|r")
            health._lastTextPercent = pct
        end
    end
    -- Prefer oUF elements' own visuals/updates for indicators; avoid extra per-update color work here.
end

----------------------------------------------------------------------------------------
--	Power Functions
----------------------------------------------------------------------------------------
UF.PreUpdatePower = function(power, unit)
    local _, pToken = UnitPowerType(unit)

    local color = R.oUF_colors.power[pToken]
    if color then
        power:SetStatusBarColor(color[1], color[2], color[3])
    end
end

UF.PostUpdatePower = function(power, unit, cur, _, max)
    if unit and unit:find("arena%dtarget") then return end
    local self = power:GetParent()
    local pType, pToken = UnitPowerType(unit)
    local color = R.oUF_colors.power[pToken]

    if color then
        local r, g, b = color[1], color[2], color[3]
        if power._lastTextR ~= r or power._lastTextG ~= g or power._lastTextB ~= b then
            power.value:SetTextColor(r, g, b)
            power._lastTextR, power._lastTextG, power._lastTextB = r, g, b
        end
    end

    if not UnitIsConnected(unit) or UnitIsDead(unit) or UnitIsGhost(unit) then
        power:SetValue(0)
    end

    if unit == "focus" or unit == "focustarget" or unit == "targettarget" or (self:GetParent():GetName():match("oUF_RaidDPS")) then return end
end

----------------------------------------------------------------------------------------
--\tMana Level Functions (see canonical helpers in Flash Animations section)
----------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------
--	PvP Status Functions
----------------------------------------------------------------------------------------
-- keep a single definition; remove duplicate below
UF.UpdatePvPStatus = function(self)
    local unit = self.unit

    if self.Status then
        local factionGroup = UnitFactionGroup(unit)
        if UnitIsPVPFreeForAll(unit) then
            self.Status:SetText(PVP)
        elseif factionGroup and UnitIsPVP(unit) then
            self.Status:SetText(PVP)
        else
            self.Status:SetText("")
        end
    end
end

----------------------------------------------------------------------------------------
--	Cast Bar Functions
----------------------------------------------------------------------------------------
-- per-castbar ticks for overlay variant
local setBarTicks = function(Castbar, numTicks)
    Castbar.ticks = Castbar.ticks or {}

    local width = Castbar:GetWidth() or 0
    local height = Castbar:GetHeight() or 0
    if numTicks == (Castbar._lastTicks or 0) and math.floor(width) == math.floor(Castbar._lastTickWidth or -1) then
        -- Nothing changed; keep current layout
        return
    end

    -- Hide any existing ticks by default; we'll re-show the needed ones
    for _, v in pairs(Castbar.ticks) do
        v:Hide()
    end

    if numTicks and numTicks > 0 then
        local delta = width / numTicks
        for i = 1, numTicks do
            if not Castbar.ticks[i] then
                local t = Castbar:CreateTexture(nil, "OVERLAY")
                t:SetTexture(C.media.texture)
                t:SetVertexColor(unpack(C.media.borderColor))
                t:SetWidth(1)
                t:SetDrawLayer("OVERLAY", 7)
                Castbar.ticks[i] = t
            end
            local tick = Castbar.ticks[i]
            if tick:GetHeight() ~= height then
                tick:SetHeight(height)
            end
            tick:ClearAllPoints()
            tick:SetPoint("CENTER", Castbar, "RIGHT", -delta * i, 0)
            tick:Show()
        end
    end

    Castbar._lastTicks = numTicks or 0
    Castbar._lastTickWidth = width
end

local function castColor(unit)
    local r, g, b
    if UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        local color = R.oUF_colors.class[class]
        if color then
            r, g, b = color[1], color[2], color[3]
        end
    else
        local reaction = UnitReaction(unit, "player")
        local color = R.oUF_colors.reaction[reaction]
        if color and reaction >= 5 then
            r, g, b = color[1], color[2], color[3]
        else
            r, g, b = 0.85, 0.77, 0.36
        end
    end

    return r, g, b
end

-- duplicate removed; using canonical SetCastbarColor above

-- duplicate removed; using canonical SetButtonColor above

local function SetLimitedText(text, maxLength)
    if #text > maxLength then
        text = text:sub(1, maxLength - 3) .. "..." -- Truncate and add ellipsis
    end

    return (text)
end

UF.PostCastStart = function(Castbar, unit)
    unit = unit == "vehicle" and PLAYER or unit

    local r, g, b
    if UnitCanAttack(PLAYER, unit) then
        r, g, b = unpack(Castbar.notInterruptible and R.oUF_colors.notinterruptible or
            R.oUF_colors.interruptible)
    elseif UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        r, g, b = unpack(R.oUF_colors.class[class])
    else
        local color = R.oUF_colors.reaction[UnitReaction(unit, PLAYER)]
        r, g, b = color[1], color[2], color[3]
    end
    SetCastbarColor(Castbar, r, g, b)

    -- -- Safely set the button border color
    -- if Castbar.Button then
    --     if Castbar.Button.SetBackdropBorderColor then
    --         Castbar.Button:SetBackdropBorderColor(r, g, b, 1)
    --     elseif Castbar.Button.SetBorderColor then
    --         Castbar.Button:SetBorderColor(r, g, b, 1)
    --     elseif Castbar.Button.Border then
    --         Castbar.Button.Border:SetVertexColor(r, g, b, 1)
    --     end
    -- end

    -- if not Castbar.Button.Cooldown then
    --     Castbar.Button.Cooldown = CreateFrame("Cooldown", nil, Castbar.Button, "CooldownFrameTemplate")
    --     Castbar.Button.Cooldown:SetAllPoints()
    --     Castbar.Button.Cooldown:SetReverse(false)
    --     Castbar.Button.Cooldown:SetDrawEdge(false)
    --     Castbar.Button.Cooldown:SetSwipeColor(0, 0, 0, 0.8)
    -- end

    local spellName = GetSpellInfo(Castbar.spellID)     -- Get the spell name using the spell ID
    Castbar.Text:SetText(SetLimitedText(spellName, 20)) -- Limit the text to 20 characters


    local start = GetTime()
    local duration = Castbar.max or 0

    if Castbar.channeling then
        local name, _, _, startTimeMS = UnitChannelInfo(unit)
        if name and startTimeMS then
            start = startTimeMS / 1000
            duration = Castbar.max or (Castbar.endTime and (Castbar.endTime - start)) or 0
        end
    end
    -- Castbar.Button.Cooldown:SetCooldown(start, duration)

    if unit == PLAYER then
        if C.unitframes.castbarLatency and Castbar.Latency then
            local _, _, _, ms = GetNetStats()
            Castbar.Latency:SetFormattedText("%dms", ms)
            Castbar.SafeZone:SetDrawLayer(Castbar.casting and "BORDER" or "ARTWORK")
            Castbar.SafeZone:SetVertexColor(0.85, 0.27, 0.27, Castbar.casting and 1 or 0.75)
        end

        if C.unitframes.castbarTicks then
            if Castbar.casting then
                setBarTicks(Castbar, 0)
            else
                local spell = UnitChannelInfo(unit)
                Castbar.channelingTicks = R.CastBarTicks[spell] or 0
                setBarTicks(Castbar, Castbar.channelingTicks)
            end
        end
    end
end

UF.CustomCastTimeText = function(self, duration)
    if duration > 600 then
        self.Time:SetText("∞")
    else
        self.Time:SetText(("%.1f"):format(self.channeling and duration or self.max - duration))
    end
end

UF.CustomCastDelayText = function(self, duration)
    self.Time:SetText(("%.1f |cffaf5050%s %.1f|r"):format(self.channeling and duration or self.max - duration,
        self.channeling and "-" or "+", abs(self.delay)))
end

----------------------------------------------------------------------------------------
--	Aura Tracking Functions
----------------------------------------------------------------------------------------
UF.AuraTrackerTime = function(self, elapsed)
    if self.active then
        self.timeleft = self.timeleft - elapsed
        if self.timeleft <= 5 then
            self.text:SetTextColor(1, 0, 0)
        else
            self.text:SetTextColor(1, 1, 1)
        end
        if self.timeleft <= 0 then
            self.icon:SetTexture("")
            self.text:SetText("")
        end
        self.text:SetFormattedText("%.1f", self.timeleft)
    end
end

UF.HideAuraFrame = function(self)
    if self.unit == "player" then
        BuffFrame:Hide()
        self.Debuffs:Hide()
    elseif self.unit == "pet" or self.unit == "focus" or self.unit == "focustarget" or self.unit == "targettarget" then
        self.Debuffs:Hide()
    end
end

UF.PostCreateIcon = function(element, button)
    UF.ApplyFrameTemplate(button, "Icon", { borderStrata = "LOW" })

    -- button.timerText = R.SetFontString(button, unpack(C.font.nameplates.auras))
    -- button.timerText:SetPoint("CENTER", button, "CENTER", 1, 1)
    -- button.timerText:SetJustifyH("CENTER")

    button.Cooldown.noCooldownCount = true
    button.Icon:SetPoint("TOPLEFT", 2, -2)
    button.Icon:SetPoint("BOTTOMRIGHT", -2, 2)
    button.Icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)

    button.Count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, 3)
    button.Count:SetJustifyH("RIGHT")
    button.Count:SetFont(unpack(C.font.auras.smallCount))

    element.disableCooldown = false
    local cooldown = button.Cooldown
    cooldown:SetSwipeTexture(C.media.auraCooldown)
    cooldown:SetParent(button)
    cooldown:SetPoint("TOPLEFT", button, "TOPLEFT", -1, 1)
    cooldown:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
    cooldown:SetReverse(true)
    cooldown:SetDrawEdge(false)
    cooldown:SetSwipeColor(0, 0, 0, 0.8)

    -- Castbar.Button.Cooldown = CreateFrame("Cooldown", nil, Castbar.Button, "CooldownFrameTemplate")
    -- Castbar.Button.Cooldown:SetAllPoints()
    -- Castbar.Button.Cooldown:SetReverse(true)
    -- Castbar.Button.Cooldown:SetDrawEdge(false)
    -- Castbar.Button.Cooldown:SetSwipeColor(0, 0, 0, 0.8)


    local parent = CreateFrame("Frame", nil, button)
    parent:SetFrameLevel(cooldown:GetFrameLevel() + 1)
    button.Count:SetParent(parent)

    -- button.timerText:SetParent(parent)
    button.parent = parent
end

-- duplicate removed; using canonical FormatTime above

UF.PostUpdateIcon = function(_, button, unit, data)
    -- Handle the gap spacer between debuffs and buffs: keep space, hide visuals
    local isGap = (button.isGap or not data or not data.name) and true or false
    if isGap then
        if not button._gapHidden then
            if button.Icon then button.Icon:SetTexture(nil) end
            if button.Count then button.Count:SetText("") end
            if button.Cooldown then button.Cooldown:Hide() end
            if button.border then button.border:Hide() end
            button:SetAlpha(0)
            button._gapHidden = true
        end
        return
    else
        if button._gapHidden then
            button._gapHidden = nil
            button:SetAlpha(1)
            if button.border then button.border:Show() end
            if button.Cooldown then button.Cooldown:Show() end
        end
    end
    local isPlayerUnit = (unit == "player" or unit == "pet")

    if data.isHarmful then
        if not UnitIsFriend("player", unit) and not isPlayerUnit then
            if not C.auras.playerAuraOnly then
                local br, bg, bb = unpack(C.media.borderColor)
                if button._lastBorderR ~= br or button._lastBorderG ~= bg or button._lastBorderB ~= bb then
                    button.border:SetBackdropBorderColor(br, bg, bb)
                    button._lastBorderR, button._lastBorderG, button._lastBorderB = br, bg, bb
                end
                if not button._lastDesat then
                    button.Icon:SetDesaturated(true)
                    button._lastDesat = true
                end
            end
        else
            if C.player.debuffColorType == true then
                local color = DebuffTypeColor[data.dispelName] or DebuffTypeColor.none
                if button._lastBorderR ~= color.r or button._lastBorderG ~= color.g or button._lastBorderB ~= color.b then
                    button.border:SetBackdropBorderColor(color.r, color.g, color.b)
                    button._lastBorderR, button._lastBorderG, button._lastBorderB = color.r, color.g, color.b
                end
                if button._lastDesat ~= false then
                    button.Icon:SetDesaturated(false)
                    button._lastDesat = false
                end
            else
                if button._lastBorderR ~= 1 or button._lastBorderG ~= 0 or button._lastBorderB ~= 0 then
                    button:SetBackdropBorderColor(1, 0, 0)
                    button._lastBorderR, button._lastBorderG, button._lastBorderB = 1, 0, 0
                end
            end
        end
    else
        -- This is the buff section
        if (data.isStealable or ((R.class == "MAGE" or R.class == "PRIEST" or R.class == "SHAMAN" or R.class == "HUNTER") and data.dispelName == "Magic")) and not UnitIsFriend("player", unit) then
            if button._lastBorderR ~= 1 or button._lastBorderG ~= 0.85 or button._lastBorderB ~= 0 then
                button.border:SetBackdropBorderColor(1, 0.85, 0)
                button._lastBorderR, button._lastBorderG, button._lastBorderB = 1, 0.85, 0
            end
        elseif data.duration and data.duration > 0 then
            -- Set the border color to green for buffs with duration
            if button._lastBorderR ~= 0 or button._lastBorderG ~= 1 or button._lastBorderB ~= 0 then
                button.border:SetBackdropBorderColor(0, 1, 0)
                button._lastBorderR, button._lastBorderG, button._lastBorderB = 0, 1, 0
            end
        else
            -- Use default border color for permanent/passive buffs
            local br, bg, bb = unpack(C.media.borderColor)
            if button._lastBorderR ~= br or button._lastBorderG ~= bg or button._lastBorderB ~= bb then
                button.border:SetBackdropBorderColor(br, bg, bb)
                button._lastBorderR, button._lastBorderG, button._lastBorderB = br, bg, bb
            end
        end
        if button._lastDesat ~= false then
            button.Icon:SetDesaturated(false)
            button._lastDesat = false
        end
    end
end

UF.CustomFilter = function(element, unit, data)
    if C.auras.playerAuraOnly then
        if data.isHarmful then
            if not UnitIsFriend("player", unit) and not playerUnits[data.sourceUnit] then
                return false
            end
        end
    end
    return true
end

UF.CustomFilterBoss = function(element, unit, data)
    if data.isHarmful then
        if (playerUnits[data.sourceUnit] or data.sourceUnit == unit) then
            if (R.DebuffBlackList and not R.DebuffBlackList[data.name]) or not R.DebuffBlackList then
                return true
            end
        end
        return false
    end
    return true
end

----------------------------------------------------------------------------------------
-- Flash Animations
----------------------------------------------------------------------------------------
local function SetUpAnimGroup(self)
    self.anim = self:CreateAnimationGroup()
    self.anim:SetLooping("BOUNCE")
    self.anim.fade = self.anim:CreateAnimation("Alpha")
    self.anim.fade:SetFromAlpha(1)
    self.anim.fade:SetToAlpha(0)
    self.anim.fade:SetDuration(0.6)
    self.anim.fade:SetSmoothing("IN_OUT")
end

local function Flash(self)
    if not self.anim then
        SetUpAnimGroup(self)
    end

    if not self.anim:IsPlaying() then
        self.anim:Play()
    end
end

local function StopFlash(self)
    if self.anim then
        self.anim:Finish()
    end
end

function UF.UpdateManaLevel(self, elapsed)
    -- Early bails: hidden or missing fontstring
    if not self:IsShown() or not self.ManaLevel then return end

    self._acc = (self._acc or 0) + elapsed
    if self._acc < 0.5 then return end
    self._acc = 0

    local pType = UnitPowerType(PLAYER)
    if pType ~= 0 then
        -- No mana bar active; for non-hybrid classes, keep things hidden and idle
        if R.class ~= "DRUID" and R.class ~= "PRIEST" and R.class ~= "SHAMAN" then
            if self._lowManaShown then
                self.ManaLevel:SetText("")
                StopFlash(self)
                self._lowManaShown = false
            end
        end
        return
    end

    local cur = UnitPower(PLAYER, 0)
    local max = UnitPowerMax(PLAYER, 0)
    local percMana = max > 0 and (cur / max * 100) or 100
    local isLow = (percMana <= 25) and not UnitIsDeadOrGhost(PLAYER)

    if isLow ~= (self._lowManaShown or false) then
        if isLow then
            self.ManaLevel:SetText("|cffaf5050" .. L_UF_MANA .. "|r")
            Flash(self)
        else
            self.ManaLevel:SetText("")
            StopFlash(self)
        end
        self._lowManaShown = isLow
    end
end

----------------------------------------------------------------------------------------
-- PvP Status
----------------------------------------------------------------------------------------
-- duplicate removed

----------------------------------------------------------------------------------------
--	Aura Watch Functions
----------------------------------------------------------------------------------------
-- Pre-compute offsets
local CountOffSets = {
    Normal = {
        { "TOPRIGHT",    0, 0 },
        { "BOTTOMRIGHT", 0, 0 },
        { "BOTTOMLEFT",  0, 0 },
        { "TOPLEFT",     0, 0 },
    },
    Reversed = {
        { "TOPLEFT",     0, 0 },
        { "BOTTOMLEFT",  0, 0 },
        { "BOTTOMRIGHT", 0, 0 },
        { "TOPRIGHT",    0, 0 },
    }
}

-- DEPRECATED: Old AuraWatch functions - replaced by BuffWatch oUF module
-- These are kept for reference but should not be used
--[[
function UF.CreateAuraWatch(self, buffs, name, anchorPoint, size, filter, reverseGrowth)
    -- ... deprecated implementation removed for brevity ...
end

function UF.CreatePlayerBuffWatch(self)
    -- ... deprecated implementation removed for brevity ...
end

function UF.CreatePartyBuffWatch(self)
    -- ... deprecated implementation removed for brevity ...
end

local function InitialAuraCheck(frame)
    -- ... deprecated implementation removed for brevity ...
end

local initialCheckFrame = CreateFrame("Frame")
-- ... deprecated implementation removed for brevity ...
--]]

----------------------------------------------------------------------------------------
--	Health Prediction Functions
----------------------------------------------------------------------------------------
-- UF.CreateHealthPrediction = function(self)
--     local mhpb = self.Health:CreateTexture(nil, "ARTWORK")
--     mhpb:SetTexture(C.media.texture)
--     mhpb:SetVertexColor(0, 1, 0.5, 0.2)

--     local ohpb = self.Health:CreateTexture(nil, "ARTWORK")
--     ohpb:SetTexture(C.media.texture)
--     ohpb:SetVertexColor(0, 1, 0, 0.2)

--     local ahpb = self.Health:CreateTexture(nil, "ARTWORK")
--     ahpb:SetTexture(C.media.texture)
--     ahpb:SetVertexColor(1, 1, 0, 0.2)

--     local hab = self.Health:CreateTexture(nil, "ARTWORK")
--     hab:SetTexture(C.media.texture)
--     hab:SetVertexColor(1, 0, 0, 0.4)

--     local oa = self.Health:CreateTexture(nil, "ARTWORK")
--     oa:SetTexture([[Interface\AddOns\RefineUI\Media\Textures\Cross.tga]], "REPEAT", "REPEAT")
--     oa:SetVertexColor(0.5, 0.5, 1)
--     oa:SetHorizTile(true)
--     oa:SetVertTile(true)
--     oa:SetAlpha(0.4)
--     oa:SetBlendMode("ADD")

--     local oha = self.Health:CreateTexture(nil, "ARTWORK")
--     oha:SetTexture([[Interface\AddOns\RefineUI\Media\Textures\Cross.tga]], "REPEAT", "REPEAT")
--     oha:SetVertexColor(1, 0, 0)
--     oha:SetHorizTile(true)
--     oha:SetVertTile(true)
--     oha:SetAlpha(0.4)
--     oha:SetBlendMode("ADD")

--     self.HealthPrediction = {
--         myBar = mhpb,                                           -- Represents predicted health from your heals
--         otherBar = ohpb,                                        -- Represents predicted health from other heals
--         absorbBar = ahpb,                                       -- Represents predicted absorb shields
--         healAbsorbBar = hab,                                    -- Represents predicted heals that will be absorbed
--         overAbsorb = C.raidframe.plugins_over_absorb and oa,    -- Texture for over-absorption
--         overHealAbsorb = C.raidframe.plugins_over_heal_absorb and oha -- Texture for over-heal-absorb
--     }
-- end

-- Create a metatable
local mt = {
    __index = function(t, k)
        if UF[k] then
            return UF[k]
        else
            return rawget(t, k)
        end
    end
}

-- Set the metatable to R
setmetatable(R, mt)

-- Return R at the end of your file
R.UF = UF
return R
