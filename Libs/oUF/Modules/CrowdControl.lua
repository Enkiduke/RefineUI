local R, C, L = unpack(RefineUI)
local _, ns = ...
local oUF = (ns and ns.oUF) or rawget(_G, "oUF")
if not oUF then return end

-- CrowdControl element: a nameplate-only statusbar that fills up while a player-applied CC debuff lasts.

local AuraUtil = AuraUtil
local GetTime = GetTime

-- Resolve castbar texture at runtime to avoid load-order issues (Libs load before Config)
local function GetCastbarTexture()
    -- Prefer configured texture; fallback to current texture (if any) or UI default
    if C and C.media and C.media.castbarTexture then
        return C.media.castbarTexture
    end
    return [[Interface\TargetingFrame\UI-StatusBar]]
end
local BORDER_COLOR = C and C.media and C.media.borderColor or { .6, .6, .6 }

-- Ensure whitelist is available (loaded from Config/Filters/CCDebuffs.lua via Filters.xml)
R.CCDebuffs = R.CCDebuffs or {}

local function SafeClearClaim(frame)
    if not frame then return end
    if R and R.PortraitManager and type(R.PortraitManager.EnsureClearClaim) == 'function' then
        R.PortraitManager.EnsureClearClaim(frame)
    elseif R and R.PortraitManager and type(R.PortraitManager.ClearClaim) == 'function' then
        R.PortraitManager.ClearClaim(frame)
    elseif R and R.PortraitManager and type(R.PortraitManager.Invalidate) == 'function' then
        R.PortraitManager.Invalidate(frame)
    else
        frame._portraitManagerClaim = nil
        frame._portraitManagerClaimTS = nil
        frame._portraitClaimVersion = (frame._portraitClaimVersion or 0) + 1
    end
end

-- Minimal helper to apply consistent styling to the CC bar when oUF creates it.
local function ApplyBarStyle(element)
    if not element then return end
    -- Ensure a texture is set (use castbar texture fallback)
    if element.SetStatusBarTexture and GetCastbarTexture then
        pcall(function() element:SetStatusBarTexture(GetCastbarTexture()) end)
    end
    -- Default color matches CC tint
    if element.SetStatusBarColor then
        pcall(function() element:SetStatusBarColor(0.2, 0.6, 1) end)
    end
    -- Fonts
    if element.Text and C and C.font and C.font.nameplates and type(C.font.nameplates.spell) == 'table' then
        pcall(function() element.Text:SetFont(unpack(C.font.nameplates.spell)) end)
    end
    if element.Time and C and C.font and C.font.nameplates and type(C.font.nameplates.spelltime) == 'table' then
        pcall(function() element.Time:SetFont(unpack(C.font.nameplates.spelltime)) end)
    end
end

local function IsWhitelistedCCAura(data)
    if not data or not data.isHarmful then return false end
    local sid = data.spellId
    if not sid or not R.CCDebuffs[sid] then
        -- Try by name fallback if needed
        if R.CCDebuffsByName and data.name then
            local id = R.CCDebuffsByName[data.name]
            if not id then return false end
        else
            return false
        end
    end
    -- Accept CC from any player (not limited to you)
    return true
end

local function FindActiveCC(unit)
    local best
    AuraUtil.ForEachAura(unit, "HARMFUL", nil, function(data)
        if IsWhitelistedCCAura(data) then
            -- Prefer the one with the longest remaining time
            local remain = (data.expirationTime or 0) - GetTime()
            if remain > 0 then
                if not best or remain > ((best.expirationTime or 0) - GetTime()) then
                    best = data
                end
            end
        end
        return false -- continue
    end, true)
    return best
end

local function Update(self, event, unit)
    if not unit or self.unit ~= unit then return end
    local element = self.CrowdControl
    if not element then return end

    if element.PreUpdate then element:PreUpdate(unit) end

    -- Hide on friendly/nameplates where it's not useful
    if UnitIsPlayer(unit) or UnitIsFriend("player", unit) then
        -- Restore portrait border when CC hides
        if R and R.PortraitManager and type(R.PortraitManager.ReleaseClaimAndRestore) == 'function' then
            if R.PortraitManager._debug then print("|CrowdControl: calling PortraitManager.ReleaseClaimAndRestore (friendly/hide)") end
            R.PortraitManager.ReleaseClaimAndRestore(self)
        elseif R and R.PortraitManager and type(R.PortraitManager.RestoreDefault) == 'function' then
            if R.PortraitManager._debug then print("|CrowdControl: calling PortraitManager.RestoreDefault (friendly/hide,fallback)") end
            SafeClearClaim(self)
            R.PortraitManager.RestoreDefault(self)
        elseif self.PortraitBorder then
            local dr, dg, db = unpack(C.media.borderColor)
            SafeClearClaim(self)
            if R and R.NP and type(R.NP.RestorePortraitBorder) == 'function' then
                R.NP.RestorePortraitBorder(self)
            else
                self.PortraitBorder:SetVertexColor(dr, dg, db)
            end
        end
        element:Hide()
        if element.OnHideCC then element:OnHideCC(unit) end
        return
    end

    -- Priority: if a castbar is active, don't show CC bar to avoid overlap
    local cb = self.Castbar
    if cb and cb:IsShown() and (cb.casting or cb.channeling or cb.empowering) then
        -- Hide CC while a cast is active; do NOT restore portrait here because
        -- the cast handling will request the proper cast color via PortraitManager.
        element:Hide()
        return
    end

    local data = FindActiveCC(unit)
    if data then
        -- Setup bar min/max and fill direction: fill up as time elapses
        local dur = data.duration or 0
        local exp = data.expirationTime or 0
        local start = exp - dur
        if dur and dur > 0 and exp and exp > 0 then
            element.max = dur
            element.startTime = start
            element.endTime = exp
            element:SetMinMaxValues(0, dur)
            local now = GetTime()
            -- Fill direction
            local fillUp = not (C and C.nameplate and C.nameplate.ccbarFillUp == false)
            local value = fillUp and (now - start) or (exp - now)
            value = math.max(0, math.min(dur, value))
            element:SetValue(value)

            -- Left text option
            if element.Text then
                local mode = C and C.nameplate and C.nameplate.ccbarText or "SPELL"
                if mode == "PLAYER" then
                    -- Prefer the player owner when the source is a pet
                    local function getOwnerUnit(u)
                        if not u then return nil end
                        if u == "pet" or u == "vehicle" then return "player" end
                        local p = u:match("^(party%d+)pet$")
                        if p then return p end
                        local r = u:match("^(raid%d+)pet$")
                        if r then return r end
                        return u
                    end

                    local casterUnit = data.sourceUnit and UnitExists(data.sourceUnit) and data.sourceUnit or nil
                    local ownerUnit = getOwnerUnit(casterUnit)
                    local casterName
                    local classFile
                    if ownerUnit and UnitExists(ownerUnit) and UnitIsPlayer(ownerUnit) then
                        casterName = UnitName(ownerUnit)
                        local _, class = UnitClass(ownerUnit)
                        classFile = class
                    elseif casterUnit and UnitExists(casterUnit) and UnitIsPlayer(casterUnit) then
                        casterName = UnitName(casterUnit)
                        local _, class = UnitClass(casterUnit)
                        classFile = class
                    else
                        casterName = data.casterName or ""
                    end

                    if casterName and casterName ~= "" and classFile then
                        local r, g, b
                        if RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
                            local c = RAID_CLASS_COLORS[classFile]
                            r, g, b = c.r, c.g, c.b
                        elseif R.oUF_colors and R.oUF_colors.class and R.oUF_colors.class[classFile] then
                            local c = R.oUF_colors.class[classFile]
                            r, g, b = c[1], c[2], c[3]
                        end
                        if r and g and b and R.RGBToHex then
                            local hex = R.RGBToHex(r, g, b)
                            element.Text:SetText(hex .. casterName .. "|r")
                        else
                            element.Text:SetText(casterName)
                        end
                    else
                        element.Text:SetText(casterName or "")
                    end
                elseif mode == "NONE" then
                    element.Text:SetText("")
                else
                    element.Text:SetText(data.name or "")
                end
            end
            if element.Time then
                local remain = exp - now
                element.Time:SetText((remain > 600) and "∞" or ("%.1f"):format(remain))
            end
            element.spellID = data.spellId
            element.debuffInstanceID = data.auraInstanceID
            element:Show()

            -- Request portrait border color update via cooperative API so CombinedPortrait
            -- can arbitrate; fallback to direct color change if not handled.
            local applied = false
            if R and R.PortraitManager and type(R.PortraitManager.RequestColor) == 'function' then
                applied = R.PortraitManager.RequestColor(self, 0.2, 0.6, 1, 'cc')
            end
            if not applied then
                -- If manager isn't present/handling, clear any stale claim then apply color directly
                SafeClearClaim(self)
                if self.PortraitBorder then
                    self.PortraitBorder:SetVertexColor(0.2, 0.6, 1)
                end
            end
        else
            -- Restore portrait border when CC hides (CC without valid timing)
            if R and R.PortraitManager and type(R.PortraitManager.ReleaseClaimAndRestore) == 'function' then
                R.PortraitManager.ReleaseClaimAndRestore(self)
            elseif R and R.PortraitManager and type(R.PortraitManager.RestoreDefault) == 'function' then
                SafeClearClaim(self)
                R.PortraitManager.RestoreDefault(self)
            elseif self.PortraitBorder then
                local dr, dg, db = unpack(C.media.borderColor)
                SafeClearClaim(self)
                if R and R.NP and type(R.NP.RestorePortraitBorder) == 'function' then
                    R.NP.RestorePortraitBorder(self)
                else
                    self.PortraitBorder:SetVertexColor(dr, dg, db)
                end
            end
            element:Hide()
        end
    else
        -- No CC active: restore portrait to default
        if R and R.PortraitManager and type(R.PortraitManager.RestoreDefault) == 'function' then
            if R.PortraitManager._debug then print("|CrowdControl: calling PortraitManager.RestoreDefault (cc end)") end
            SafeClearClaim(self)
            R.PortraitManager.RestoreDefault(self)
        elseif self.PortraitBorder then
            local dr, dg, db = unpack(C.media.borderColor)
            SafeClearClaim(self)
            self.PortraitBorder:SetVertexColor(dr, dg, db)
        end
        element:Hide()
    end

    if element.PostUpdate then element:PostUpdate(unit) end
end

local function ForceUpdate(element)
    return Update(element.__owner, 'ForceUpdate', element.__owner.unit)
end

local function onUpdate(self, elapsed)
    if not self:IsShown() or not self.endTime or not self.startTime then return end
    local now = GetTime()
    local dur = self.endTime - self.startTime
    if dur <= 0 then self:Hide() return end
    local fillUp = not (C and C.nameplate and C.nameplate.ccbarFillUp == false)
    if fillUp then
        local prog = now - self.startTime
        if prog >= dur then
            -- CC finished: clear claim and restore portrait
                if R and R.PortraitManager and type(R.PortraitManager.ReleaseClaimAndRestore) == 'function' then
                    if R.PortraitManager._debug then print("|CrowdControl: onUpdate CC finished - calling ReleaseClaimAndRestore") end
                    R.PortraitManager.ReleaseClaimAndRestore(self)
                elseif R and R.PortraitManager and type(R.PortraitManager.RestoreDefault) == 'function' then
                    if R.PortraitManager._debug then print("|CrowdControl: onUpdate CC finished - clearing claim and calling RestoreDefault (fallback)") end
                    SafeClearClaim(self)
                    R.PortraitManager.RestoreDefault(self)
                elseif self.PortraitBorder then
                    local dr, dg, db = unpack(C.media.borderColor)
                    -- Try to clear any claim before restoring the fallback color
                    SafeClearClaim(self)
                    if R and R.NP and type(R.NP.RestorePortraitBorder) == 'function' then
                        R.NP.RestorePortraitBorder(self)
                    else
                        SafeClearClaim(self)
                        self.PortraitBorder:SetVertexColor(dr, dg, db)
                    end
            end
            self:Hide()
            return
        end
        self:SetValue(prog)
    else
        local remain = self.endTime - now
        if remain <= 0 then
            self:Hide()
            return
        end
        self:SetValue(remain)
    end
    if self.Time then
        local remain = self.endTime - now
        self.Time:SetText((remain > 600) and "∞" or ("%.1f"):format(remain))
    end
end

local function Enable(self, unit)
    local element = self.CrowdControl
    if element and unit and self.isNamePlate and not UnitIsUnit(unit, 'player') then
        element.__owner = self
        element.ForceUpdate = ForceUpdate

        ApplyBarStyle(element)

        -- Position and size like the castbar
        local parentLevel = self:GetFrameLevel() or 0
        element:SetFrameLevel(parentLevel + 1)
        element:SetFrameStrata("MEDIUM")
        element:ClearAllPoints()
        element:SetPoint("TOP", self.Health, "BOTTOM", 0, 2)
        element:SetSize(C.nameplate.width, C.nameplate.height + 2)

        element:SetScript('OnUpdate', onUpdate)

    -- Listen to aura updates to refresh when CC is applied/removed
        self:RegisterEvent('UNIT_AURA', Update)
    -- Also respond to cast events so we can hide during casts and reshow after
    self:RegisterEvent('UNIT_SPELLCAST_START', Update)
    self:RegisterEvent('UNIT_SPELLCAST_STOP', Update)
    self:RegisterEvent('UNIT_SPELLCAST_CHANNEL_START', Update)
    self:RegisterEvent('UNIT_SPELLCAST_CHANNEL_STOP', Update)
    self:RegisterEvent('UNIT_SPELLCAST_EMPOWER_START', Update)
    self:RegisterEvent('UNIT_SPELLCAST_EMPOWER_STOP', Update)

        element:Hide()
        return true
    end
end

local function Disable(self)
    local element = self.CrowdControl
    if element then
        element:Hide()
        element:SetScript('OnUpdate', nil)
    self:UnregisterEvent('UNIT_AURA', Update)
    self:UnregisterEvent('UNIT_SPELLCAST_START', Update)
    self:UnregisterEvent('UNIT_SPELLCAST_STOP', Update)
    self:UnregisterEvent('UNIT_SPELLCAST_CHANNEL_START', Update)
    self:UnregisterEvent('UNIT_SPELLCAST_CHANNEL_STOP', Update)
    self:UnregisterEvent('UNIT_SPELLCAST_EMPOWER_START', Update)
    self:UnregisterEvent('UNIT_SPELLCAST_EMPOWER_STOP', Update)
    end
end

oUF:AddElement('CrowdControl', Update, Enable, Disable)
