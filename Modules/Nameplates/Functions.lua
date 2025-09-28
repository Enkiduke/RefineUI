local R, C, L = unpack(RefineUI)
local _, ns = ...
local oUF = ns.oUF
local NP = R.NP or {}
R.NP = NP
-- Map unit GUID -> our nameplate ref for O(1) lookups from CLEU
NP._plateByGUID = NP._plateByGUID or {}
local plateByGUID = NP._plateByGUID
-- Upvalue commonly used API functions to reduce global lookups in hot paths
local AuraUtil = AuraUtil
local UnitGUID = UnitGUID
local UnitIsUnit = UnitIsUnit
local UnitIsPlayer = UnitIsPlayer
local UnitIsFriend = UnitIsFriend
local UnitReaction = UnitReaction
local UnitSelectionColor = UnitSelectionColor
local UnitIsDead = UnitIsDead
local UnitExists = UnitExists
local UnitAffectingCombat = UnitAffectingCombat
local UnitIsTapDenied = UnitIsTapDenied
local UnitThreatSituation = UnitThreatSituation
local UnitName = UnitName
local UnitNameplateShowsWidgetsOnly = UnitNameplateShowsWidgetsOnly
local UnitWidgetSet = UnitWidgetSet

----------------------------------------------------------------------------------------
-- Helper Functions
----------------------------------------------------------------------------------------

-- Simple portrait border color logic - no complex priority system
-- Manager-aware helper to set a portrait border color.
-- Preferred signature: SetPortraitBorderColor(frame, portraitBorder, r, g, b)
-- If a PortraitManager is present, attempt RequestColor(frame, r,g,b, reason).
-- If the manager declines or is absent, ensure any stale claim is cleared and set the color directly.
-- SafeClearClaim: consumer helper that clears any manager claim safely.
-- It prefers the centralized PortraitManager helpers when available and falls back
-- to directly clearing metadata and bumping the claim version to protect recycled frames.
local function SafeClearClaim(frame)
    if not frame then return end
    if R and R.PortraitManager and type(R.PortraitManager.EnsureClearClaim) == 'function' then
        R.PortraitManager.EnsureClearClaim(frame)
        return
    end
    if R and R.PortraitManager and type(R.PortraitManager.ClearClaim) == 'function' then
        R.PortraitManager.ClearClaim(frame)
        return
    end
    if R and R.PortraitManager and type(R.PortraitManager.Invalidate) == 'function' then
        R.PortraitManager.Invalidate(frame)
        return
    end
    -- Final fallback: ensure claim is cleared consistently
    SafeClearClaim(frame)
end

local function SetPortraitBorderColor(frame, portraitBorder, r, g, b)
    if not portraitBorder then return end
    -- Try cooperative API first
    if frame and R and R.PortraitManager and type(R.PortraitManager.RequestColor) == 'function' then
        local applied = R.PortraitManager.RequestColor(frame, r, g, b, 'np')
        if R.PortraitManager._debug then
            print(("|[NP] SetPortraitBorderColor: RequestColor r=%.2f g=%.2f b=%.2f applied=%s"):format(r or 0, g or 0, b or 0, tostring(applied)))
        end
        if applied then return end
    end

    -- Manager absent or declined: clear any stale claim then apply directly
    if frame then
        SafeClearClaim(frame)
    end

    local cr, cg, cb = portraitBorder:GetVertexColor()
    if R and R.PortraitManager and R.PortraitManager._debug then
        print(("|[NP] SetPortraitBorderColor before r=%.2f g=%.2f b=%.2f -> want r=%.2f g=%.2f b=%.2f"):format(cr or 0,
            cg or 0, cb or 0, r or 0, g or 0, b or 0))
    end
    if cr ~= r or cg ~= g or cb ~= b then
        portraitBorder:SetVertexColor(r, g, b)
        if R and R.PortraitManager and R.PortraitManager._debug then
            local cr2, cg2, cb2 = portraitBorder:GetVertexColor()
            print(("|[NP] SetPortraitBorderColor after r=%.2f g=%.2f b=%.2f"):format(cr2 or 0, cg2 or 0, cb2 or 0))
        end
    end
end


local UnitIsOwnerOrControllerOfUnit = UnitIsOwnerOrControllerOfUnit
local GetNumGroupMembers = GetNumGroupMembers
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitDetailedThreatSituation = UnitDetailedThreatSituation
local IsInRaid = IsInRaid
local GetTime = GetTime
local strsplit = strsplit
local floor = math.floor
local format = string.format
local C_NamePlate = C_NamePlate
local GetNamePlateForUnit, GetNamePlates = C_NamePlate.GetNamePlateForUnit, C_NamePlate.GetNamePlates
local GetSpellCooldown = GetSpellCooldown
local GetPlayerInfoByGUID = GetPlayerInfoByGUID

-- Precomputed color tuples to avoid unpack each time
local COLOR_INTR = R.oUF_colors and R.oUF_colors.interruptible or { 1, 0.8, 0 }
local COLOR_NOT_INTR = R.oUF_colors and R.oUF_colors.notinterruptible or { 0.7, 0.1, 0.1 }
local COLOR_KICK_CD = { 1, 0.5, 0 } -- Orange when interrupt is on cooldown
local COLOR_CAST_DEFAULT = { 1, 0.8, 0 }
local C_Timer_After = C_Timer and C_Timer.After

-- Upvalue textures
local TEX_NP_GLOW = C.media.nameplateGlow
-- Upvalue frequently used colors
local BORDER_R, BORDER_G, BORDER_B = C.media.borderColor[1], C.media.borderColor[2], C.media.borderColor[3]
-- Small performance helpers to avoid redundant work in hot paths
local function SetAlphaIfChanged(frame, a)
    if not frame then return end
    local cur = frame:GetAlpha()
    if cur ~= a then frame:SetAlpha(a) end
end

----------------------------------------------------------------------------------------
-- Interrupt tracking for player class colors
----------------------------------------------------------------------------------------
local interruptTracker = {}
local INTERRUPT_TIMEOUT = 5 -- Keep interrupt data for 5 seconds
local lastCleanupTime = 0
local CLEANUP_INTERVAL = 30 -- Clean up expired entries every 30 seconds

-- Periodic cleanup of expired interrupt data
local function CleanupInterruptTracker()
    local currentTime = GetTime()
    if currentTime - lastCleanupTime < CLEANUP_INTERVAL then
        return
    end

    lastCleanupTime = currentTime
    for guid, data in pairs(interruptTracker) do
        if currentTime - data.timestamp > INTERRUPT_TIMEOUT then
            interruptTracker[guid] = nil
        end
    end
end

-- Get the class color for an interrupted spell
local function GetInterrupterClassColor(unitGUID)
    if not C.nameplate.interruptColor then
        return nil -- Feature disabled
    end

    local interruptData = interruptTracker[unitGUID]
    if not interruptData then
        return nil -- No interrupt data
    end

    local currentTime = GetTime()
    -- Check if interrupt data is still fresh
    if currentTime - interruptData.timestamp > INTERRUPT_TIMEOUT then
        interruptTracker[unitGUID] = nil
        return nil
    end

    -- Try to get class info from the interrupter GUID
    local interrupterGUID = interruptData.interrupterGUID
    if interrupterGUID then
        -- Extract class from player GUID (format: Player-realm-playerID)
        local guidType = strsplit("-", interrupterGUID)
        if guidType == "Player" then
            -- Try to get class from current group members or inspect cache
            local className = select(2, GetPlayerInfoByGUID(interrupterGUID))
            if className and R.oUF_colors and R.oUF_colors.class and R.oUF_colors.class[className] then
                local classColor = R.oUF_colors.class[className]
                return classColor[1], classColor[2], classColor[3]
            end
        end
    end

    return nil -- Couldn't determine class color
end

-- Combat log event handler to track interrupts
local function OnCombatLogEvent(timestamp, subevent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
                                destGUID, destName, destFlags, destRaidFlags, spellId, spellName, spellSchool,
                                extraSpellID, extraSpellName, extraSchool)
    if subevent == "SPELL_INTERRUPT" and sourceGUID and destGUID then
        -- Clean up old entries periodically for performance
        CleanupInterruptTracker()

        -- Store interrupt information with timestamp
        interruptTracker[destGUID] = {
            interrupterGUID = sourceGUID,
            interrupterName = sourceName,
            timestamp = GetTime(),
            spellId = extraSpellID -- The interrupted spell ID
        }

        -- Immediately apply color to any active castbars for this unit via GUID -> plate map
        local ref = plateByGUID and plateByGUID[destGUID]
        if ref then
            local castbar = ref.Castbar
            if castbar and castbar:IsShown() and castbar.Text then
                local r, g, b = GetInterrupterClassColor(destGUID)
                if r and g and b then
                    castbar.Text:SetTextColor(r, g, b)
                    castbar._lastInterruptColor = { r, g, b }
                end
            end
        end
    end
end

-- Initialize combat log tracking
local combatFrame = CreateFrame("Frame")
if C and C.nameplate and C.nameplate.interruptColor then
    combatFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end
combatFrame:SetScript("OnEvent", function(self, event)
    OnCombatLogEvent(CombatLogGetCurrentEventInfo())
end)

----------------------------------------------------------------------------------------

local function SetBarColorIfChanged(statusbar, r, g, b)
    if not statusbar then return end
    local cr, cg, cb = statusbar:GetStatusBarColor()
    if cr ~= r or cg ~= g or cb ~= b then
        statusbar:SetStatusBarColor(r, g, b)
    end
end

local function SetTexColorIfChanged(tex, r, g, b, a)
    if not tex then return end
    local lr, lg, lb, la = tex._lr, tex._lg, tex._lb, tex._la
    if lr ~= r or lg ~= g or lb ~= b or la ~= a then
        tex:SetColorTexture(r, g, b, a)
        tex._lr, tex._lg, tex._lb, tex._la = r, g, b, a
    end
end
----------------------------------------------------------------------------------------
-- CC detection (to decide whether to suppress Interrupted hold)
----------------------------------------------------------------------------------------
local function UnitHasActiveCC(unit)
    if not unit or not AuraUtil or not AuraUtil.ForEachAura then return false end
    local found = false
    AuraUtil.ForEachAura(unit, "HARMFUL", nil, function(data)
        if found then return true end
        if data and data.isHarmful then
            local sid = data.spellId
            local whitelisted = (sid and R.CCDebuffs and R.CCDebuffs[sid])
            if not whitelisted and data.name and R.CCDebuffsByName then
                whitelisted = R.CCDebuffsByName[data.name] ~= nil
            end
            if whitelisted then
                local remain = (data.expirationTime or 0) - GetTime()
                if remain and remain > 0 then
                    found = true
                    return true -- stop
                end
            end
        end
        return false
    end, true)
    return found
end


----------------------------------------------------------------------------------------
-- Aura Timer
----------------------------------------------------------------------------------------
local day, hour, minute = 86400, 3600, 60
local FormatTime = function(s)
    if s >= day then
        return format("%dd", floor(s / day + 1))
    elseif s >= hour then
        return format("%dh", floor(s / hour + 1))
    elseif s >= minute then
        return format("%dm", floor(s / minute + 1))
    elseif s >= 5 then
        return floor(s + 1)
    end
    return format("%d", s)
end

local function CreateAuraTimer(self, elapsed)
    self.elapsed = (self.elapsed or 0) + elapsed
    if self.elapsed < 0.25 then return end

    -- If aura timers are disabled in config, stop updates entirely
    if not (C and C.nameplate and C.nameplate.auraTimer) then
        self:SetScript("OnUpdate", nil)
        return
    end

    if self.first then
        self.timeLeft = self.timeLeft - GetTime()
        self.first = false
    else
        self.timeLeft = self.timeLeft - self.elapsed
    end

    if self.timeLeft > 0 then
        self.remaining:SetText(FormatTime(self.timeLeft))
    else
        self:SetScript("OnUpdate", nil)
    end
    self.elapsed = 0
end

----------------------------------------------------------------------------------------
-- Name Functions
----------------------------------------------------------------------------------------
function NP.threatColor(self, forced)
    if UnitIsPlayer(self.unit) then
        return
    end

    if UnitIsTapDenied(self.unit) then
        self.Health:SetStatusBarColor(0.6, 0.6, 0.6)
        return
    end

    if not UnitAffectingCombat("player") or not UnitAffectingCombat(self.unit) then
        -- Not in combat: use default reaction/mob color so bar doesn't lag behind name color
        local r, g, b
        if C.nameplate.mobColorEnable and R.ColorPlate[self.npcID] then
            r, g, b = unpack(R.ColorPlate[self.npcID])
        else
            local reaction = UnitReaction(self.unit, "player")
            local rc = reaction and R.oUF_colors and R.oUF_colors.reaction and R.oUF_colors.reaction[reaction]
            if rc then
                r, g, b = rc[1], rc[2], rc[3]
            else
                r, g, b = UnitSelectionColor(self.unit, true)
            end
        end
        SetBarColorIfChanged(self.Health, r, g, b)
        return
    end

    local threatStatus = UnitThreatSituation("player", self.unit)
    local color

    if threatStatus == 3 then -- securely tanking, highest threat
        if R.Role == "Tank" then
            color = C.nameplate.mobColorEnable and R.ColorPlate[self.npcID] or C.nameplate.goodColor
        else
            color = C.nameplate.badColor
        end
    elseif threatStatus == 2 or threatStatus == 1 then -- insecurely tanking or not tanking, higher threat than tank
        color = C.nameplate.nearColor
    elseif threatStatus == 0 then                      -- not tanking, lower threat than tank
        if R.Role == "Tank" then
            if IsInRaid() then
                NP._offtankCache = NP._offtankCache or {}
                NP._offtankScanTS = NP._offtankScanTS or {}
                local now = GetTime()
                local guid = UnitGUID(self.unit) or self.unit
                local throttle = (C and C.nameplate and C.nameplate.offtankScanThrottle) or 0.5
                -- On forced updates (from UNIT_THREAT_*), bypass throttle for instant sync with name tag
                if forced or ((NP._offtankScanTS[guid] or 0) + throttle < now) then
                    local offTank = false
                    for i = 1, GetNumGroupMembers() do
                        local u = "raid" .. i
                        if UnitExists(u) and not UnitIsUnit(u, "player") and UnitGroupRolesAssigned(u) == "TANK" then
                            if UnitDetailedThreatSituation(u, self.unit) then
                                offTank = true
                                break
                            end
                        end
                    end
                    NP._offtankCache[guid] = offTank
                    NP._offtankScanTS[guid] = now
                end
                color = (NP._offtankCache[guid] and C.nameplate.offtankColor) or C.nameplate.badColor
            else
                color = C.nameplate.badColor
            end
        else
            color = C.nameplate.mobColorEnable and R.ColorPlate[self.npcID] or C.nameplate.goodColor
        end
    end

    if color then
        SetBarColorIfChanged(self.Health, color[1], color[2], color[3])
    end
end

-- Update the health bar color immediately when threat changes so it stays in lockstep with name tag color
function NP.ThreatEvent(self, event, unit)
    -- For unit events, ignore if this isn't our unit
    if unit and unit ~= self.unit then return end
    if not self or not self.unit or not self.Health then return end
    -- Skip threat processing for friendly units when friendly health is disabled
    if C.nameplate.disableFriendlyHealth and UnitIsFriend("player", self.unit) then
        return
    end
    if not C.nameplate.enhanceThreat or UnitIsPlayer(self.unit) then
        -- If threat coloring is off or on players, fall back to reaction/mob color to avoid visible mismatch
        local r, g, b
        if C.nameplate.mobColorEnable and R.ColorPlate[self.npcID] then
            r, g, b = unpack(R.ColorPlate[self.npcID])
        else
            local reaction = UnitReaction(self.unit, "player")
            local rc = reaction and R.oUF_colors and R.oUF_colors.reaction and R.oUF_colors.reaction[reaction]
            if rc then
                r, g, b = rc[1], rc[2], rc[3]
            else
                r, g, b = UnitSelectionColor(self.unit, true)
            end
        end
        SetBarColorIfChanged(self.Health, r, g, b)
        return
    end
    -- Apply threat color now; respects combat/tap checks inside
    NP.threatColor(self, true)
end

----------------------------------------------------------------------------------------
-- Utility Functions
----------------------------------------------------------------------------------------
function NP.CreateBorderFrame(frame, point)
    -- Delegate to core helper to keep a single source of truth; arguments match current visuals
    R.CreateThinBorder(frame, 3, 3, 7, 1)
end

-- Shared glow-border creator for nameplate target highlight and similar effects
-- opts: { edgeFile, edgeSize, offset, color = {r,g,b,a}, frameLevel }
function NP.CreateGlowFrame(frame, opts)
    opts = opts or {}
    local edgeFile = opts.edgeFile or TEX_NP_GLOW
    local edgeSize = opts.edgeSize or 6
    local offset = opts.offset or 3
    local color = opts.color or { 0.9, 0.9, 0.9, 1 }
    local level = opts.frameLevel

    local glow = frame.Glow
    if not glow or glow:GetObjectType() ~= "Frame" then
        glow = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        frame.Glow = glow
    end

    glow:ClearAllPoints()
    glow:SetPoint("TOPLEFT", frame, "TOPLEFT", -offset, offset)
    glow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", offset, -offset)
    glow:SetBackdrop({ edgeFile = edgeFile, edgeSize = edgeSize })
    glow:SetBackdropBorderColor(color[1], color[2], color[3], color[4] or 1)

    if level ~= nil then
        glow:SetFrameLevel(level)
    end

    glow:Hide()
    return glow
end

-- Centralized icon border creator; currently mirrors CreateBorderFrame to avoid any visual change
function NP.CreateBorderFrameIcon(frame)
    return NP.CreateBorderFrame(frame)
end

local function SetColorBorder(frame, r, g, b)
    if not frame or not frame.border then return end
    local br = frame.border
    local cr, cg, cb = br:GetBackdropBorderColor()
    if cr ~= r or cg ~= g or cb ~= b then
        br:SetBackdropBorderColor(r, g, b, 1)
    end
end

-- Reset any target-specific visuals so hidden plates don't "remember" target state
function NP.ClearTargetVisuals(self)
    if not self then return end
    local dr, dg, db = BORDER_R, BORDER_G, BORDER_B
    if self.Health then
        SetColorBorder(self.Health, dr, dg, db)
    end
    -- Reset per-plate alpha (fallback if CVars not applied yet); skip player's personal nameplate
    if not UnitIsUnit(self.unit, "player") then
        if not UnitExists("target") then
            SetAlphaIfChanged(self, C.nameplate.noTargetAlpha or 1)
        else
            SetAlphaIfChanged(self, C.nameplate.alpha or .9)
        end
    end
    local castingActive = self.Castbar and self.Castbar:IsShown() and (self.Castbar.casting or self.Castbar.channeling)
    -- Portrait border is managed by Dynamic Portrait module
    -- No need to set it here to avoid conflicts
    if self.Glow and self.Glow:IsShown() then self.Glow:Hide() end
    if self.PortraitGlow and self.PortraitGlow:IsShown() then self.PortraitGlow:Hide() end
    if self.RTargetIndicator and self.RTargetIndicator:IsShown() then self.RTargetIndicator:Hide() end
    if self.LTargetIndicator and self.LTargetIndicator:IsShown() then self.LTargetIndicator:Hide() end
    -- Invalidate portrait manager state for this frame so any pending manager
    -- reapply timers won't touch a recycled frame.
        if R and R.PortraitManager and type(R.PortraitManager.EnsureClearClaim) == 'function' then
            R.PortraitManager.EnsureClearClaim(self)
        else
            if R and R.PortraitManager and type(R.PortraitManager.Invalidate) == 'function' then
                R.PortraitManager.Invalidate(self)
            elseif R and R.PortraitManager and type(R.PortraitManager.ClearClaim) == 'function' then
                R.PortraitManager.ClearClaim(self)
                self._portraitClaimVersion = (self._portraitClaimVersion or 0) + 1
            else
                SafeClearClaim(self)
                self._portraitClaimVersion = (self._portraitClaimVersion or 0) + 1
            end
    end
end

----------------------------------------------------------------------------------------
-- Auras Functions
----------------------------------------------------------------------------------------
function NP.AurasCustomFilter(element, unit, data)
    if UnitIsFriend("player", unit) then return false end

    if data.isHarmful then
        if C.nameplate.trackDebuffs and (data.isPlayerAura or data.sourceUnit == "pet") then
            return (data.nameplateShowAll or data.nameplateShowPersonal) and not R.DebuffBlackList[data.name] or
                R.DebuffWhiteList[data.name]
        end
    else
        return R.BuffWhiteList[data.name] or data.isStealable
    end

    return false
end

function NP.AurasPostCreateIcon(element, button)
    NP.CreateBorderFrameIcon(button)

    -- Disable external cooldown text overlays (e.g., OmniCC) and Blizzard numbers as configured
    local showNumbers = (C and C.nameplate and C.nameplate.auraTimer) == true
    button.Cooldown.noCooldownCount = not showNumbers
    if button.Cooldown.SetHideCountdownNumbers then
        button.Cooldown:SetHideCountdownNumbers(not showNumbers)
    end

    button.Icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)

    button.Count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, 1)
    button.Count:SetJustifyH("CENTER")
    button.Count:SetFont(unpack(C.font.nameplates.aurasCount))
    button.Count:SetShadowOffset(1, -1)

    -- Honor element.disableCooldown (configured in CreateAuras)
    if element.disableCooldown then
        button.Cooldown:Hide()
    else
        button.Cooldown:Show()
        button.Cooldown:SetSwipeTexture(C.media.auraCooldown)
        button.Cooldown:SetReverse(true)
        button.Cooldown:SetDrawEdge(false)
        button.Cooldown:SetSwipeColor(0, 0, 0, 0.8)
        button.Cooldown:SetPoint("TOPLEFT", button, "TOPLEFT", -1, 1)
        button.Cooldown:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
    end

    -- Ensure count draws above cooldown without creating an extra parent frame
    if button.Count and button.Count.SetDrawLayer then
        button.Count:SetDrawLayer("OVERLAY", 7)
    end

    -- Create a parent frame for elements that need to draw above the cooldown
    local parent = CreateFrame("Frame", nil, button)
    parent:SetFrameLevel(button.Cooldown:GetFrameLevel() + 1)
    button.Count:SetParent(parent)
    button.parent = parent
end

function NP.AurasPostUpdateIcon(element, button, unit, data)
    -- Toggle cooldown swipe per element setting (runtime-safe if user changes C.nameplate.cooldownSwipe)
    local wantSwipe = not element.disableCooldown
    local swipeShown = button.Cooldown:IsShown()
    if wantSwipe and not swipeShown then
        button.Cooldown:Show()
    elseif not wantSwipe and swipeShown then
        button.Cooldown:Hide()
    end

    -- Toggle countdown numbers per config at runtime
    local showNumbers = (C and C.nameplate and C.nameplate.auraTimer) == true
    button.Cooldown.noCooldownCount = not showNumbers
    if button.Cooldown.SetHideCountdownNumbers then
        button.Cooldown:SetHideCountdownNumbers(not showNumbers)
    end

    if not UnitIsFriend("player", unit) then
        if data.isHarmful then
            if C.nameplate.trackDebuffs and (data.isPlayerAura or data.sourceUnit == "pet") then
                if C.nameplate.trackBuffs then
                    local dr, dg, db = unpack(C.media.borderColor)
                    -- Gate recolor
                    if button.border then
                        local cr, cg, cb = button.border:GetBackdropBorderColor()
                        if cr ~= dr or cg ~= dg or cb ~= db then
                            button.border:SetBackdropBorderColor(dr, dg, db, 1)
                        end
                    else
                        SetColorBorder(button, dr, dg, db)
                    end
                end
            end
        else
            local tr, tg, tb
            if R.BuffWhiteList[data.name] then
                tr, tg, tb = 0, 0.5, 0
            elseif data.isStealable then
                tr, tg, tb = 1, 0.85, 0
            end
            if tr then
                if button.border then
                    local cr, cg, cb = button.border:GetBackdropBorderColor()
                    if cr ~= tr or cg ~= tg or cb ~= tb then
                        button.border:SetBackdropBorderColor(tr, tg, tb, 1)
                    end
                else
                    SetColorBorder(button, tr, tg, tb)
                end
            end
        end
    end
    button.first = true
end

-- Post Updates
----------------------------------------------------------------------------------------
local function ApplyCastColors(self, color)
    local r, g, b = color[1], color[2], color[3]
    SetBarColorIfChanged(self, r, g, b)
    if self.bg then
        local la = self.bg._la or 1
        SetTexColorIfChanged(self.bg, r * .2, g * .2, b * .2, la)
    end
    SetColorBorder(self, r, g, b)
    -- Also attempt to update portrait border to keep visuals in sync. Some
    -- setups manage portrait borders in a separate module; only update if
    -- the portrait border object exists and wasn't explicitly delegated.
    local parent = self:GetParent()
    if parent and parent.PortraitBorder then
        local applied = false
        if R and R.PortraitManager and type(R.PortraitManager.RequestColor) == 'function' then
            applied = R.PortraitManager.RequestColor(parent, r, g, b, 'cast')
            if R.PortraitManager._debug then
                print(('[NP] ApplyCastColors requested portrait color r=%.2f g=%.2f b=%.2f applied=%s'):format(r, g, b,
                    tostring(applied)))
            end
        end
        if not applied then
            -- If manager isn't present/handling, clear any stale claim first then apply color directly
            if parent then
                if R and R.PortraitManager and type(R.PortraitManager.EnsureClearClaim) == 'function' then
                    R.PortraitManager.EnsureClearClaim(parent)
                elseif R and R.PortraitManager and type(R.PortraitManager.Invalidate) == 'function' then
                    R.PortraitManager.Invalidate(parent)
                elseif R and R.PortraitManager and type(R.PortraitManager.ClearClaim) == 'function' then
                    R.PortraitManager.ClearClaim(parent)
                    parent._portraitClaimVersion = (parent._portraitClaimVersion or 0) + 1
                else
                    -- Final fallback: clear local metadata and bump version to invalidate pending timers
                    SafeClearClaim(parent)
                    parent._portraitClaimVersion = (parent._portraitClaimVersion or 0) + 1
                end
            end
            SetPortraitBorderColor(parent, parent.PortraitBorder, r, g, b)
        end
    end
end

-- Restore portrait border to default configured border color
function NP.RestorePortraitBorder(frame)
    if not frame then return end
    -- If DynamicPortrait/CombinedPortrait is enabled on this frame, it manages
    -- portrait restorations itself; avoid clobbering its state.
    if type(frame.IsElementEnabled) == 'function' and frame:IsElementEnabled('CombinedPortrait') then return end
    local pb = frame.PortraitBorder
    if not pb then return end
    -- Use configured media border color as default
    local dr, dg, db = BORDER_R, BORDER_G, BORDER_B
    if R and R.PortraitManager and R.PortraitManager._debug then
        print(("|[NP] RestorePortraitBorder: calling SetPortraitBorderColor -> r=%.2f g=%.2f b=%.2f"):format(dr, dg, db))
    end
    -- Clear any portrait manager claim first so our direct restore cannot be stomped by pending reapply timers
    if R and R.PortraitManager and type(R.PortraitManager.EnsureClearClaim) == 'function' then
        R.PortraitManager.EnsureClearClaim(frame)
    else
        if R and R.PortraitManager and type(R.PortraitManager.Invalidate) == 'function' then
            R.PortraitManager.Invalidate(frame)
        elseif R and R.PortraitManager and type(R.PortraitManager.ClearClaim) == 'function' then
            R.PortraitManager.ClearClaim(frame)
            frame._portraitClaimVersion = (frame._portraitClaimVersion or 0) + 1
        else
            -- Final fallback
            SafeClearClaim(frame)
            frame._portraitClaimVersion = (frame._portraitClaimVersion or 0) + 1
        end
    end
    SetPortraitBorderColor(frame, pb, dr, dg, db)
end

function NP.PostCastStart(self)
    local parent = self:GetParent()
    local unit = parent.unit
    -- Ensure layout is restored in case a new cast begins during an interrupt hold
    if NP and NP.RestoreCastbarLayout then
        NP.RestoreCastbarLayout(self)
    end
    -- Immediately hide CC bar when a cast/channel/empower starts to avoid overlap
    if parent and parent.CrowdControl and parent.CrowdControl:IsShown() then
        parent.CrowdControl:Hide()
        if NP and NP.UpdateBarsLayout then
            NP.UpdateBarsLayout(parent)
        end
    end
    -- Sanity recheck: validate interruptibility flag against fresh API data to avoid
    -- stale event races (late *_INTERRUPTIBLE from previous cast)
    if unit and (self.casting or self.channeling or self.empowering) then
        local _, _, _, _, _, _, _, apiNotInt, apiSpellID = UnitCastingInfo(unit)
        if not apiNotInt then
            _, _, _, _, _, _, apiNotInt, apiSpellID = UnitChannelInfo(unit)
        end
        if apiSpellID and self.spellID and apiSpellID == self.spellID and apiNotInt ~= nil and apiNotInt ~= self.notInterruptible then
            self.notInterruptible = apiNotInt
            if self.Shield then self.Shield:SetShown(apiNotInt) end
        end
    end

    -- Decide desired color variant; only apply when state changes
    local variant, color
    if self.notInterruptible then
        variant, color = "NI", COLOR_NOT_INTR
    else
        if C.nameplate.kickColor then
            local kickID = C and C.nameplate and C.nameplate.kickSpellID
            local start = kickID and (select(1, GetSpellCooldown(kickID)) or 0) or 0
            if start ~= 0 then
                variant, color = "KCD", COLOR_KICK_CD
            else
                variant, color = "KRDY", COLOR_CAST_DEFAULT
            end
        else
            variant, color = "INTR", COLOR_INTR
        end
    end

    if self._lastCastVariant ~= variant then
        ApplyCastColors(self, color)
        self._lastCastVariant = variant
    end


    -- Optional cast border overrides (only when actually interruptible)
    if C.nameplate.castColor and not self.notInterruptible then
        if R.InterruptCast[self.spellID] then
            SetColorBorder(self, 1, 0.8, 0)
        elseif R.ImportantCast[self.spellID] then
            SetColorBorder(self, 1, 0, 0)
        else
            SetColorBorder(self, BORDER_R, BORDER_G, BORDER_B)
        end
    end
end

function NP.PostCastStop(self)
    local parent = self:GetParent()
    local unit = parent.unit
    -- Portrait border is managed by Dynamic Portrait module
    -- It will automatically update when the cast ends
    -- Clear variant so next cast will re-evaluate
    self._lastCastVariant = nil
    -- Re-evaluate CC immediately after cast ends so CC bar can reshow without delay
    if parent and parent.CrowdControl and parent.CrowdControl.ForceUpdate then
        parent.CrowdControl:ForceUpdate()
    end
    -- Ensure any portrait manager claim left by the cast is cleared so the
    -- CombinedPortrait (or other owners) can restore the default border color
    -- immediately when the cast ends.
    if parent then
        if R and R.PortraitManager and type(R.PortraitManager.ReleaseClaimAndRestore) == 'function' then
            if R.PortraitManager._debug then print("|[NP] PostCastStop: calling PortraitManager.ReleaseClaimAndRestore") end
            R.PortraitManager.ReleaseClaimAndRestore(parent)
        else
            -- Fallback to previous behavior but prefer centralized helper
            if R and R.PortraitManager and type(R.PortraitManager.EnsureClearClaim) == 'function' then
                R.PortraitManager.EnsureClearClaim(parent)
            else
                if R and R.PortraitManager and type(R.PortraitManager.Invalidate) == 'function' then
                    R.PortraitManager.Invalidate(parent)
                elseif R and R.PortraitManager and type(R.PortraitManager.ClearClaim) == 'function' then
                    R.PortraitManager.ClearClaim(parent)
                else
                    -- Final fallback
                    SafeClearClaim(parent)
                    parent._portraitClaimVersion = (parent._portraitClaimVersion or 0) + 1
                end
            end
            if R and R.PortraitManager and type(R.PortraitManager.RestoreDefault) == 'function' then
                if R.PortraitManager._debug then print(
                    "|[NP] PostCastStop: cleared claim and calling PortraitManager.RestoreDefault (fallback)") end
                R.PortraitManager.RestoreDefault(parent)
            end
        end
    end
end

-- When a cast fails or is interrupted, we briefly show the bar with a centered label.
function NP.PostCastFail(self)
    local parent = self:GetParent()

    -- If a CC bar is showing, suppress the interrupt hold to avoid overlap
    local ccBarShown = parent and parent.CrowdControl and parent.CrowdControl:IsShown()
    if parent and ccBarShown then
        self.holdTime = 0
        self:Hide()
        if NP and NP.RestorePortraitBorder then
            NP.RestorePortraitBorder(parent)
        end
        -- Also clear any portrait manager claim left by the cast and request a restore
        if parent then
            if R and R.PortraitManager and type(R.PortraitManager.ReleaseClaimAndRestore) == 'function' then
                if R.PortraitManager._debug then print(
                    "|[NP] PostCastFail: calling PortraitManager.ReleaseClaimAndRestore") end
                R.PortraitManager.ReleaseClaimAndRestore(parent)
            else
                -- Prefer centralized Invalidate/ClearClaim helper when available
                if R and R.PortraitManager and type(R.PortraitManager.Invalidate) == 'function' then
                    R.PortraitManager.Invalidate(parent)
                elseif R and R.PortraitManager and type(R.PortraitManager.EnsureClearClaim) == 'function' then
                    R.PortraitManager.EnsureClearClaim(parent)
                else
                    if R and R.PortraitManager and type(R.PortraitManager.ClearClaim) == 'function' then
                        R.PortraitManager.ClearClaim(parent)
                    else
                        SafeClearClaim(parent)
                        parent._portraitClaimVersion = (parent._portraitClaimVersion or 0) + 1
                    end
                end
                if R and R.PortraitManager and type(R.PortraitManager.RestoreDefault) == 'function' then
                    if R.PortraitManager._debug then print(
                        "|[NP] PostCastFail: cleared claim and calling PortraitManager.RestoreDefault (fallback)") end
                    R.PortraitManager.RestoreDefault(parent)
                end
            end
        end
        return
    end

    -- Portrait border is managed by Dynamic Portrait module
    -- It will automatically update when the cast fails

    -- Empty the bar and position the "Interrupted" text with class color if available
    self:SetValue(0)
    if self.Text then
        self.Text:ClearAllPoints()
        self.Text:SetPoint("BOTTOM", self, "BOTTOM", 0, 1)
        self.Text:SetJustifyH("CENTER")
        self._textHiddenByInterrupt = false

        -- Apply interrupter's class color if feature is enabled and we have the data
        if parent and parent.unit then
            local unitGUID = UnitGUID(parent.unit)

            -- Try to get fresh color data
            local r, g, b = GetInterrupterClassColor(unitGUID)

            -- If no fresh data, check if we have cached color on the castbar itself
            if not r and self._lastInterruptColor then
                r, g, b = self._lastInterruptColor[1], self._lastInterruptColor[2], self._lastInterruptColor[3]
            end

            if r and g and b then
                self.Text:SetTextColor(r, g, b)
                -- Cache the color on the castbar for subsequent calls
                self._lastInterruptColor = { r, g, b }
            else
                -- Fallback to default color (white)
                self.Text:SetTextColor(1, 1, 1)
                self._lastInterruptColor = nil
            end
        end
    end

    -- Hide the time text during interrupt hold
    if self.Time then
        self.Time:Hide()
        self._timeHiddenByInterrupt = true
    end

    -- Clear variant so next cast will re-evaluate colors (same as PostCastStop)
    self._lastCastVariant = nil
    -- Always clear any portrait manager claim left by the failed/interrupting cast
    -- and request a restore so the portrait border doesn't remain stuck.
    if parent then
        if R and R.PortraitManager and type(R.PortraitManager.ReleaseClaimAndRestore) == 'function' then
            if R.PortraitManager._debug then print(
                "|[NP] PostCastFail: calling PortraitManager.ReleaseClaimAndRestore (final)") end
            R.PortraitManager.ReleaseClaimAndRestore(parent)
        else
            if R and R.PortraitManager and type(R.PortraitManager.EnsureClearClaim) == 'function' then
                R.PortraitManager.EnsureClearClaim(parent)
            else
                if R and R.PortraitManager and type(R.PortraitManager.Invalidate) == 'function' then
                    R.PortraitManager.Invalidate(parent)
                elseif R and R.PortraitManager and type(R.PortraitManager.ClearClaim) == 'function' then
                    R.PortraitManager.ClearClaim(parent)
                else
                    -- Final fallback
                    SafeClearClaim(parent)
                end
            end
            if R and R.PortraitManager and type(R.PortraitManager.RestoreDefault) == 'function' then
                if R.PortraitManager._debug then print(
                    "|[NP] PostCastFail: cleared claim and calling PortraitManager.RestoreDefault (final,fallback)") end
                R.PortraitManager.RestoreDefault(parent)
            end
        end
    end
end

-- Restore original castbar text layout after the hold ends or the castbar hides
function NP.RestoreCastbarLayout(castbar)
    if not castbar or not castbar.Text then return end
    local t = castbar.Text
    t:ClearAllPoints()
    local pt = castbar._origTextPoint
    if pt then
        t:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5])
    else
        t:SetPoint("BOTTOMLEFT", castbar, "BOTTOMLEFT", 2, 1)
    end
    local justify = castbar._origTextJustify or "LEFT"
    t:SetJustifyH(justify)
    -- Reset text color to default (white)
    t:SetTextColor(1, 1, 1)
    -- Clear cached interrupt color
    castbar._lastInterruptColor = nil
    -- Clear interrupt flags and restore the time text visibility
    castbar._textHiddenByInterrupt = false
    castbar._timeHiddenByInterrupt = false
    if castbar.Time then
        castbar.Time:Show()
    end
end

function NP.HealthPostUpdate(self, unit, cur, max)
    local main = self:GetParent()
    local isDead = UnitIsDead(unit)
    local nameplate = main._nameplate or (GetNamePlateForUnit and GetNamePlateForUnit(unit))
    local visible = nameplate and nameplate.IsVisible and nameplate:IsVisible()
    -- Let oUF/nameplate engine handle hiding dead plates. If needed, gate any custom work once per state change.
    if isDead ~= main._wasDead then
        main._wasDead = isDead
        -- place for any one-time transitions on death/res if desired
    end

    local perc = 0
    if max and max > 0 then
        perc = cur / max
    end

    local r, g, b
    local mu = self.bg.multiplier
    local isPlayer = UnitIsPlayer(unit)
    local unitReaction = UnitReaction(unit, "player")
    if C.nameplate.enhanceThreat == true and not UnitIsPlayer(unit) then
        NP.threatColor(main, false)
    else
        if not UnitIsUnit("player", unit) and isPlayer and (unitReaction and unitReaction >= 5) then
            r, g, b = unpack(R.oUF_colors.power["MANA"])
            self:SetStatusBarColor(r, g, b)
        elseif not UnitIsTapDenied(unit) and not isPlayer then
            if C.nameplate.mobColorEnable and R.ColorPlate[main.npcID] then
                r, g, b = unpack(R.ColorPlate[main.npcID])
            else
                local reaction = R.oUF_colors.reaction[unitReaction]
                if reaction then
                    r, g, b = reaction[1], reaction[2], reaction[3]
                else
                    r, g, b = UnitSelectionColor(unit, true)
                end
            end

            SetBarColorIfChanged(self, r, g, b)
        end

        if isPlayer then
            if perc <= 0.5 and perc >= 0.2 then
                SetColorBorder(self, 1, 1, 0)
            elseif perc < 0.2 then
                SetColorBorder(self, 1, 0, 0)
            else
                SetColorBorder(self, BORDER_R, BORDER_G, BORDER_B)
            end
        end
    end
end

-- Update Functions


function NP.UpdateTarget(self)
    if not self or not self.unit then return end
    local isMe = UnitIsUnit(self.unit, "player")
    local castingActive = self.Castbar and self.Castbar:IsShown() and (self.Castbar.casting or self.Castbar.channeling)

    -- Robust target verification: require both GUID match and the target plate to be this frame
    local targetExists = UnitExists("target")
    local isTarget = false
    local tGUID = targetExists and UnitGUID("target") or nil
    local uGUID = UnitGUID(self.unit)
    if tGUID and uGUID and tGUID == uGUID then
        isTarget = true
    end

    local plateMatches = false
    if isTarget then
        local tPlate = GetNamePlateForUnit and GetNamePlateForUnit("target") or nil
        if tPlate then
            -- prefer explicit backref check, fallback to direct plate match
            local tref = rawget(tPlate, "__Refine")
            plateMatches = (tref == self) or (self._nameplate and self._nameplate == tPlate)
        end
    end

    if isTarget and plateMatches and not isMe then
        -- Selected plate should be fully opaque (fallback if CVars not applied)
        SetAlphaIfChanged(self, 1)
        local tr, tg, tb = unpack(C.nameplate.targetBorderColor)
        SetColorBorder(self.Health, tr, tg, tb)
        -- Portrait border is managed by Dynamic Portrait module
        -- No need to set it here to avoid conflicts
        if C.nameplate.targetGlow then
            if self.Glow and not self.Glow:IsShown() then self.Glow:Show() end
            if self.PortraitGlow and not self.PortraitGlow:IsShown() then self.PortraitGlow:Show() end
        end

        if C.nameplate.targetIndicator then
            if UnitIsFriend("player", self.unit) then
                if not self.RTargetIndicator:IsShown() then
                    self.RTargetIndicator:SetPoint("LEFT", self.Name, "RIGHT", 1, 1)
                    self.LTargetIndicator:SetPoint("RIGHT", self.Name, "LEFT", -1, 1)
                end
            else
                if not self.RTargetIndicator:IsShown() then
                    self.RTargetIndicator:SetPoint("LEFT", self.Health, "RIGHT", 1, 0)
                    self.LTargetIndicator:SetPoint("RIGHT", self.Health, "LEFT", -1, 0)
                end
            end
            if not self.RTargetIndicator:IsShown() then self.RTargetIndicator:Show() end
            if not self.LTargetIndicator:IsShown() then self.LTargetIndicator:Show() end
        end
    else
        SetColorBorder(self.Health, BORDER_R, BORDER_G, BORDER_B)
        -- Portrait border is managed by Dynamic Portrait module
        -- No need to set it here to avoid conflicts
        if C.nameplate.targetGlow then
            if self.Glow and self.Glow:IsShown() then self.Glow:Hide() end
            if self.PortraitGlow and self.PortraitGlow:IsShown() then self.PortraitGlow:Hide() end
        end
        if C.nameplate.targetIndicator then
            if self.RTargetIndicator:IsShown() then self.RTargetIndicator:Hide() end
            if self.LTargetIndicator:IsShown() then self.LTargetIndicator:Hide() end
        end
        -- Non-selected plates use configured alpha depending on target existence
        if not isMe then
            if UnitExists("target") then
                SetAlphaIfChanged(self, C.nameplate.alpha or .9)
            else
                SetAlphaIfChanged(self, C.nameplate.noTargetAlpha or 1)
            end
        end
    end
end

-- Fallback: apply configured alpha to all visible plates when target changes
function NP.ApplyAlphaAll()
    if not GetNamePlates then return end
    local plates = GetNamePlates()
    local hasTarget = UnitExists("target")
    for i = 1, #plates do
        local plate = plates[i]
        local ref = plate and rawget(plate, "__Refine") or nil
        if ref and ref.unit and not UnitIsUnit(ref.unit, "player") then
            if UnitIsUnit(ref.unit, "target") then
                SetAlphaIfChanged(ref, 1)
            else
                if hasTarget then
                    SetAlphaIfChanged(ref, C.nameplate.alpha or .9)
                else
                    SetAlphaIfChanged(ref, C.nameplate.noTargetAlpha or 1)
                end
            end
        end
    end
end

function NP.Callback(self, event, unit, nameplate)
    if not self then
        return
    end
    if unit then
        local unitGUID = UnitGUID(unit)
        if unitGUID and unitGUID ~= self._lastGUID then
            self.npcID = select(6, strsplit('-', unitGUID))
            self._lastGUID = unitGUID
            -- bump portrait claim version to invalidate any pending reapply timers
            self._portraitClaimVersion = (self._portraitClaimVersion or 0) + 1
        end
        self.unitName = UnitName(unit)
        self.widgetsOnly = UnitNameplateShowsWidgetsOnly(unit)
        self:Show()

        if UnitIsUnit(unit, "player") then
            if self.Power then 
                if self.IsElementEnabled and not self:IsElementEnabled("Power") then self:EnableElement("Power") end
                self.Power:Show()
            end
            self.Name:Hide()
            SetAlphaIfChanged(self.Castbar, 0)
            SetAlphaIfChanged(self.RaidTargetIndicator, 0)
        else
            if self.Power then 
                if self.IsElementEnabled and self:IsElementEnabled("Power") then self:DisableElement("Power") end
                self.Power:Hide()
            end
            self.Name:Show()
            SetAlphaIfChanged(self.Castbar, 1)
            SetAlphaIfChanged(self.RaidTargetIndicator, 1)

            if not UnitIsFriend("player", unit) and (self.widgetsOnly or (UnitWidgetSet(unit) and UnitIsOwnerOrControllerOfUnit("player", unit))) then
                SetAlphaIfChanged(self.Health, 0)
                -- self.Level
                SetAlphaIfChanged(self.Name, 0)
                SetAlphaIfChanged(self.Castbar, 0)
            else
                SetAlphaIfChanged(self.Health, 1)
                -- self.Level
                SetAlphaIfChanged(self.Name, 1)
                SetAlphaIfChanged(self.Castbar, 1)
            end

            local nameplate = GetNamePlateForUnit and GetNamePlateForUnit(unit)
            if nameplate then
                self._nameplate = nameplate
                -- store a weak back-reference via rawset to avoid linter complaints about new fields
                rawset(nameplate, "__Refine", self)
                if nameplate.UnitFrame then
                    local widgetContainer = rawget(nameplate.UnitFrame, "WidgetContainer")
                    if widgetContainer and widgetContainer.SetParent and widgetContainer:GetParent() ~= nameplate then
                        widgetContainer:SetParent(nameplate)
                    end
                end
            end

            -- Lazy-create heavy elements based on unit friendliness and settings
            local isFriendly = UnitIsFriend("player", unit)
            if isFriendly then
                -- Friendly units: only create heavy elements if explicitly enabled
                if not C.nameplate.disableFriendlyCastbar then
                    if not self.Castbar then NP.CreateCastBar(self) end
                    if self.Castbar and not self:IsElementEnabled('Castbar') then self:EnableElement('Castbar') end
                end
                if not C.nameplate.disableFriendlyAuras then
                    if not self.Auras then NP.CreateAuras(self) end
                    if self.Auras and not self:IsElementEnabled('Auras') then self:EnableElement('Auras') end
                end
                -- Portrait: skip creation for friendly-only to reduce draw calls unless names-only is off
                if not C.nameplate.onlyName and not self.PortraitFrame then
                    NP.CreatePortraitAndQuestIcon(self)
                    if NP.EnableDynamicPortrait then NP.EnableDynamicPortrait(self) end
                end
            else
                -- Hostile units: ensure heavy elements are available
                if not self.Castbar then NP.CreateCastBar(self) end
                if self.Castbar and not self:IsElementEnabled('Castbar') then self:EnableElement('Castbar') end
                if not self.Auras then NP.CreateAuras(self) end
                if self.Auras and not self:IsElementEnabled('Auras') then self:EnableElement('Auras') end
                if not self.PortraitFrame then
                    NP.CreatePortraitAndQuestIcon(self)
                    if NP.EnableDynamicPortrait then NP.EnableDynamicPortrait(self) end
                end
                if not self.CrowdControl then NP.CreateCrowdControlBar(self) end
                -- Ensure the oUF CrowdControl element is enabled so it updates
                if self.CrowdControl and not self:IsElementEnabled('CrowdControl') then
                    self:EnableElement('CrowdControl')
                end
            end

            if C.nameplate.onlyName then
                local isFriendly = UnitIsFriend("player", unit)
                local desiredState = isFriendly and "FRIENDLY_NAMES_ONLY" or "HOSTILE_FULL"
                if self._friendLayout ~= desiredState then
                    if isFriendly then
                        SetAlphaIfChanged(self.Health, 0)
                        if self.Castbar then SetAlphaIfChanged(self.Castbar, 0) end
                        if C.nameplate.targetGlow and self.Glow then SetAlphaIfChanged(self.Glow, 0) end
                        if self.Title then self.Title:Show() end
                        if self.PortraitFrame then self.PortraitFrame:Hide() end
                        self.Name:ClearAllPoints()
                        self.Name:SetPoint("TOP", self, "BOTTOM", 0, 0)
                    else
                        SetAlphaIfChanged(self.Health, 1)
                        if self.Castbar then SetAlphaIfChanged(self.Castbar, 1) end
                        if self.Title then self.Title:Hide() end
                        if self.PortraitFrame then self.PortraitFrame:Show() end
                        self.Name:ClearAllPoints()
                        self.Name:SetPoint("BOTTOM", self.Health, "TOP", 0, 1)
                        if C.nameplate.targetGlow and self.Glow then SetAlphaIfChanged(self.Glow, 1) end
                    end
                    self._friendLayout = desiredState
                end
            end

            -- Portrait border is managed by Dynamic Portrait module
            -- No need to set it here to avoid conflicts

            -- Ensure target visuals are correct if this plate appears after targeting
            do
                local targetExists = UnitExists("target")
                if targetExists and UnitGUID(unit) == UnitGUID("target") then
                    local tPlate = GetNamePlateForUnit and GetNamePlateForUnit("target") or nil
                    local plateMatches = tPlate and
                    ((rawget(tPlate, "__Refine") == self) or (self._nameplate and self._nameplate == tPlate)) or false
                    if plateMatches then
                        NP.UpdateTarget(self)
                    else
                        NP.ClearTargetVisuals(self)
                    end
                else
                    -- Proactively clear any target visuals for reused frames
                    NP.ClearTargetVisuals(self)
                end
            end

            -- Per-plate target updates and extra cast interrupts are centralized/handled elsewhere
        end

        -- Performance gating: disable heavy elements on friendly plates if configured
        local isFriendly = UnitIsFriend("player", unit)
        if isFriendly then
            if C.nameplate.disableFriendlyHealth and self.Health and self:IsElementEnabled('Health') then
                self:DisableElement('Health')
                self.Health:Hide()
            end
            if C.nameplate.disableFriendlyCastbar and self.Castbar and self:IsElementEnabled('Castbar') then
                self:DisableElement('Castbar')
                self.Castbar:Hide()
            end
            if C.nameplate.disableFriendlyAuras and self.Auras and self:IsElementEnabled('Auras') then
                self:DisableElement('Auras')
                self.Auras:Hide()
            end
            if C.nameplate.disableFriendlyPower and (not UnitIsUnit(unit, 'player')) and self.Power and self:IsElementEnabled('Power') then
                self:DisableElement('Power')
                self.Power:Hide()
            end
        else
            -- Ensure elements are enabled for hostile units
            if self.Health and not self:IsElementEnabled('Health') then self:EnableElement('Health') end
            if self.Castbar and not self:IsElementEnabled('Castbar') then self:EnableElement('Castbar') end
            if self.Auras and not self:IsElementEnabled('Auras') then self:EnableElement('Auras') end
            -- Only enable Power for non-player plates if explicitly desired (kept hidden by default in this layout)
            if self.Power and not self:IsElementEnabled('Power') and UnitIsUnit(unit, 'player') then self:EnableElement(
                'Power') end
        end
    end
end

-- Set the metatable to R
-- Explicitly export NP only; avoid metatable tricks on R for clarity
R.NP = NP
return R
