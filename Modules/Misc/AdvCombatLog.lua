----------------------------------------------------------------------------------------
--  Adv Combat Log (Refined & Scoped)
--  Only announces: Combat Res, Dispels, Interrupts (incl. failed), Taunts, and Utilities
--  Utilities: Feasts, Portals, Repair Bots, etc.
--  Performance: fast bitmask filtering; no GUID scans; no damage/CC tracking
----------------------------------------------------------------------------------------

local R, C, L = unpack(RefineUI)

----------------------------------------------------------------------------------------
--  Config helpers and constants
----------------------------------------------------------------------------------------
local bit_band = bit.band
local string_format = string.format
local GetTime = GetTime
local strsplit = strsplit
local wipe = wipe

local GROUP_AFFILIATION_MASK = bit.bor(
    COMBATLOG_OBJECT_AFFILIATION_MINE,
    COMBATLOG_OBJECT_AFFILIATION_PARTY,
    COMBATLOG_OBJECT_AFFILIATION_RAID
)

local THROTTLE_INTERVAL = 0.1 -- seconds
local lastProcessedTime = {    -- throttle map (pre-init common types)
    INT = {},
    INT_FAIL = {},
    DISPEL = {},
    SCS = {},
    RES = {},
}
local CLEAN_EVERY = 10        -- seconds
local EXPIRE_AFTER = 2.0      -- seconds (> THROTTLE_INTERVAL)
local nextSweep = 0

-- Option gates (defaults to true if nil)
local function enabled(opt)
    if not C or not C.advcombatlog then return true end
    local v = C.advcombatlog[opt]
    if v == nil then return true end
    return v
end

----------------------------------------------------------------------------------------
--  Coloring & spell link helpers
----------------------------------------------------------------------------------------
local classColorCache = {}
local spellInfoCache = {}

local function GetClassColor(unitGUID)
    if not unitGUID then return "|cffffffff" end
    local cached = classColorCache[unitGUID]
    if cached then return cached end
    local _, class = GetPlayerInfoByGUID(unitGUID)
    if class and RAID_CLASS_COLORS[class] then
        local c = RAID_CLASS_COLORS[class]
        local hex = string_format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
        classColorCache[unitGUID] = hex
        return hex
    end
    return "|cffffffff"
end

local function IsPlayerGUID(guid)
    return guid and guid:sub(1,6) == "Player" or false
end
local function IsCreatureOrVehicleGUID(guid)
    if not guid then return false end
    local p = guid:sub(1,7)
    return p == "Creature" or p == "Vehicle"
end

local function ColorUnitName(name, guid, flags)
    if not name then return "Unknown" end

    -- Player class coloring
    if IsPlayerGUID(guid) then
        return GetClassColor(guid) .. name .. "|r"
    end

    -- Reaction-based coloring if flags are provided
    if flags then
        if bit_band(flags, COMBATLOG_OBJECT_REACTION_HOSTILE) ~= 0 then
            local r,g,b = 1,0,0
            if R.oUF_colors and R.oUF_colors.reaction and R.oUF_colors.reaction[2] then
                r,g,b = unpack(R.oUF_colors.reaction[2])
            end
            return string_format("|cff%02x%02x%02x%s|r", r*255, g*255, b*255, name)
        elseif bit_band(flags, COMBATLOG_OBJECT_REACTION_NEUTRAL) ~= 0 then
            local r,g,b = 1,1,0
            if R.oUF_colors and R.oUF_colors.reaction and R.oUF_colors.reaction[4] then
                r,g,b = unpack(R.oUF_colors.reaction[4])
            end
            return string_format("|cff%02x%02x%02x%s|r", r*255, g*255, b*255, name)
        elseif bit_band(flags, COMBATLOG_OBJECT_REACTION_FRIENDLY) ~= 0 then
            local r,g,b = 0,1,0
            if R.oUF_colors and R.oUF_colors.reaction and R.oUF_colors.reaction[5] then
                r,g,b = unpack(R.oUF_colors.reaction[5])
            end
            return string_format("|cff%02x%02x%02x%s|r", r*255, g*255, b*255, name)
        end
    end

    -- Default creature/vehicle assumed hostile red if guid indicates non-player
    if IsCreatureOrVehicleGUID(guid) then
        local r,g,b = 1,0,0
        if R.oUF_colors and R.oUF_colors.reaction and R.oUF_colors.reaction[2] then
            r,g,b = unpack(R.oUF_colors.reaction[2])
        end
        return string_format("|cff%02x%02x%02x%s|r", r*255, g*255, b*255, name)
    end

    -- Fallback white
    return "|cffffffff" .. name .. "|r"
end

local function CreateCustomSpellLink(spellId, spellName)
    local name = type(spellName) == "table" and spellName.name or spellName
    name = name or tostring(spellId)
    return string_format("|Hspell:%d|h[%s]|h", spellId, name)
end

local function GetSpellLinkWithIcon(spellId)
    local cached = spellInfoCache[spellId]
    if cached then
        return cached.icon .. "|cff71d5ff" .. cached.link .. "|r"
    end
    local info = C_Spell.GetSpellInfo(spellId)
    local icon = C_Spell.GetSpellTexture(spellId)
    if info and icon then
        local size = (C and C.advcombatlog and C.advcombatlog.iconSize) or 16
        local iconString = "|T" .. icon .. ":" .. size .. ":" .. size .. ":0:0:64:64:4:60:4:60|t "
        local link = CreateCustomSpellLink(spellId, info.name)
        spellInfoCache[spellId] = { icon = iconString, link = link }
        return iconString .. "|cff71d5ff" .. link .. "|r"
    end
    return "[Unknown Spell]"
end

----------------------------------------------------------------------------------------
--  Message output (instance-only as requested)
----------------------------------------------------------------------------------------
local function InInstance()
    local inInstance = IsInInstance()
    return inInstance
end

local function OutputMessage(message)
    -- Show always if in instance only (per request)
    if not InInstance() then return end
    local prefix = "|cFFFFD200>>|r "
    local fullMessage = prefix .. message
    if not C or not C.advcombatlog or C.advcombatlog.outputLocal then
        print(fullMessage)
    end
    if C and C.advcombatlog and C.advcombatlog.outputChat then
        local stripped = fullMessage:gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        C_ChatInfo.SendChatMessage(stripped, C.advcombatlog.chatChannel or "SAY")
    end
end

----------------------------------------------------------------------------------------
--  Fast filters & throttle
----------------------------------------------------------------------------------------
local function FromOurGroup(flags)
    return bit_band(flags or 0, GROUP_AFFILIATION_MASK) ~= 0
end

local function IsPetFlag(flags)
    return bit_band(flags or 0, COMBATLOG_OBJECT_TYPE_PET) ~= 0
end

-- Forward declarations for cross-section use
local ResolveActor

local function ShouldProcessEvent(eventType, sourceGUID, destGUID)
    local now = GetTime()

    -- Opportunistic GC to bound memory growth
    if now >= nextSweep then
        for _, perType in pairs(lastProcessedTime) do
            for s, byDest in pairs(perType) do
                for d, t in pairs(byDest) do
                    if now - t > EXPIRE_AFTER then byDest[d] = nil end
                end
                if not next(byDest) then perType[s] = nil end
            end
        end
        nextSweep = now + CLEAN_EVERY
    end

    local perType = lastProcessedTime[eventType]
    if not perType then perType = {}; lastProcessedTime[eventType] = perType end
    local bySource = perType[sourceGUID or 0]
    if not bySource then bySource = {}; perType[sourceGUID or 0] = bySource end
    local last = bySource[destGUID or 0]
    if not last or (now - last) >= THROTTLE_INTERVAL then
        bySource[destGUID or 0] = now
        return true
    end
    return false
end

----------------------------------------------------------------------------------------
--  Lightweight death tracking (last hit only)
----------------------------------------------------------------------------------------
local lastHit = {}

local ENVIRONMENTAL_NAMES = {
    DROWNING = "Drowning",
    FALLING = "Falling",
    FATIGUE = "Fatigue",
    FIRE = "Fire",
    LAVA = "Lava",
    SLIME = "Slime",
}

local function RecordLastHit(destGUID, destFlags, sourceName, sourceGUID, sourceFlags, spellId, damageType)
    if not FromOurGroup(destFlags) then return end
    if IsPetFlag(destFlags) then return end -- skip pet deaths
    -- Attribute pet sources to their owners for death messages
    local rName, rGUID, rFlags = ResolveActor(sourceName, sourceGUID, sourceFlags)
    local rec = lastHit[destGUID]
    if not rec then rec = {}; lastHit[destGUID] = rec end
    rec.t = GetTime()
    rec.srcName = rName
    rec.srcGUID = rGUID
    rec.srcFlags = rFlags
    rec.spellId = spellId
    rec.dmgType = damageType -- for environmental
end

local function HandleDeath(destGUID, destName, destFlags)
    if not enabled("enableDeath") then return end
    if not FromOurGroup(destFlags) then return end
    if IsPetFlag(destFlags) then return end -- ignore pet deaths
    local hit = lastHit[destGUID]
    local now = GetTime()
    local destColor = ColorUnitName(destName, destGUID, destFlags)
    local msg
    if hit and (now - (hit.t or 0)) <= 6 then
        local src = hit.srcName and ColorUnitName(hit.srcName, hit.srcGUID, hit.srcFlags) or "Unknown"
        if hit.dmgType then
            local env = ENVIRONMENTAL_NAMES[hit.dmgType] or hit.dmgType
            msg = string_format("%s died to %s.", destColor, env)
        elseif hit.spellId == 6603 or hit.spellId == 0 then
            msg = string_format("%s died to Melee from %s.", destColor, src)
        elseif hit.spellId then
            local spellLink = GetSpellLinkWithIcon(hit.spellId)
            if hit.srcName then
                msg = string_format("%s died to %s from %s.", destColor, spellLink, src)
            else
                msg = string_format("%s died to %s.", destColor, spellLink)
            end
        end
    end
    if not msg then
        msg = string_format("%s has died.", destColor)
    end
    OutputMessage(msg)
    lastHit[destGUID] = nil -- clear to avoid stale data
end

----------------------------------------------------------------------------------------
--  Utility classification
----------------------------------------------------------------------------------------
local function UtilityCategory(spellId)
    local u = R.spells and R.spells.utilities
    if not u then return nil end
    if u.bots and u.bots[spellId] then return "Repair Bot" end
    if (u.feasts and u.feasts[spellId]) or (u.feasts_cast_succeeded and u.feasts_cast_succeeded[spellId]) then return "Feast" end
    if u.portals and u.portals[spellId] then return "Portal" end
    return nil
end

----------------------------------------------------------------------------------------
--  Pet owner resolution
----------------------------------------------------------------------------------------
local petOwnerByGUID = {}

local function UpdatePetOwners()
    wipe(petOwnerByGUID)
    -- Player and pet
    local playerGUID = UnitGUID("player")
    local playerName = UnitName and UnitName("player") or nil
    local petGUID = UnitGUID("pet")
    if petGUID and playerGUID and playerName then
        petOwnerByGUID[petGUID] = { name = playerName, guid = playerGUID }
    end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local oGUID = UnitGUID("raid" .. i)
            local oName = UnitName and UnitName("raid" .. i) or nil
            local pGUID = UnitGUID("raidpet" .. i)
            if pGUID and oGUID and oName then
                petOwnerByGUID[pGUID] = { name = oName, guid = oGUID }
            end
        end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do
            local oGUID = UnitGUID("party" .. i)
            local oName = UnitName and UnitName("party" .. i) or nil
            local pGUID = UnitGUID("partypet" .. i)
            if pGUID and oGUID and oName then
                petOwnerByGUID[pGUID] = { name = oName, guid = oGUID }
            end
        end
    end
end

ResolveActor = function(name, guid, flags)
    if IsPetFlag(flags) and guid and petOwnerByGUID[guid] then
        local owner = petOwnerByGUID[guid]
        return (owner.name .. " (Pet)"), owner.guid, flags
    end
    return name, guid, flags
end

----------------------------------------------------------------------------------------
--  Event Handlers (scoped)
----------------------------------------------------------------------------------------
local eventHandlers = {}

-- Interrupts
local function HandleInterrupt(spellId, sourceName, sourceGUID, sourceFlags, destName, destGUID, destFlags, extraSpellId, extraSpellName)
    if not enabled("enableInterrupt") then return end
    if not FromOurGroup(sourceFlags) then return end
    local dispName, dispGUID, dispFlags = ResolveActor(sourceName, sourceGUID, sourceFlags)
    local sourceColor = ColorUnitName(dispName, dispGUID, dispFlags)
    local destColor = ColorUnitName(destName, destGUID, destFlags)
    local spellLink = GetSpellLinkWithIcon(spellId)
    local extraLink = extraSpellId and GetSpellLinkWithIcon(extraSpellId) or (extraSpellName or "a spell")
    OutputMessage(string_format("%s interrupted %s's %s with %s.", sourceColor, destColor, extraLink, spellLink))
end

-- Failed interrupts (distinct visual)
local function HandleFailedInterrupt(sourceName, sourceGUID, sourceFlags, destName, destGUID, destFlags, spellId)
    if not enabled("enableInterrupt") then return end
    if not FromOurGroup(sourceFlags) then return end
    local dispName, dispGUID, dispFlags = ResolveActor(sourceName, sourceGUID, sourceFlags)
    local sourceColor = ColorUnitName(dispName, dispGUID, dispFlags)
    local destColor = ColorUnitName(destName, destGUID, destFlags)
    local spellLink = GetSpellLinkWithIcon(spellId)
    local prefix = "|cffff5555[FAILED]|r "
    OutputMessage(prefix .. string_format("%s tried %s on %s.", sourceColor, spellLink, destColor))
end

-- Dispels
local function HandleDispel(spellId, sourceName, sourceGUID, sourceFlags, destName, destGUID, destFlags, extraSpellId, extraSpellName)
    if not enabled("enableDispel") then return end
    if not (FromOurGroup(sourceFlags) or FromOurGroup(destFlags)) then return end
    local dispName, dispGUID, dispFlags = ResolveActor(sourceName, sourceGUID, sourceFlags)
    local sourceColor = ColorUnitName(dispName, dispGUID, dispFlags)
    local destColor = ColorUnitName(destName, destGUID, destFlags)
    local spellLink = GetSpellLinkWithIcon(spellId)
    local extraLink = extraSpellId and GetSpellLinkWithIcon(extraSpellId) or (extraSpellName or "an effect")
    OutputMessage(string_format("%s dispelled %s's %s with %s.", sourceColor, destColor, extraLink, spellLink))
end

-- Taunts
local function HandleTaunt(spellId, sourceName, sourceGUID, sourceFlags, destName, destGUID, destFlags)
    if not enabled("enableTaunt") then return end
    if not FromOurGroup(sourceFlags) then return end
    if not (R.spells and R.spells.taunts and R.spells.taunts[spellId]) then return end
    local dispName, dispGUID, dispFlags = ResolveActor(sourceName, sourceGUID, sourceFlags)
    local sourceColor = ColorUnitName(dispName, dispGUID, dispFlags)
    local destColor = ColorUnitName(destName, destGUID, destFlags)
    local spellLink = GetSpellLinkWithIcon(spellId)
    OutputMessage(string_format("%s taunted %s with %s.", sourceColor, destColor, spellLink))
end

-- Utilities (Feasts, Portals, Repair Bots)
local function HandleUtility(spellId, sourceName, sourceGUID, sourceFlags)
    if C and C.advcombatlog and C.advcombatlog.enableUtilities == false then return end
    if not FromOurGroup(sourceFlags) then return end
    local category = UtilityCategory(spellId)
    if not category then return end
    local sourceColor = ColorUnitName(sourceName, sourceGUID, sourceFlags)
    local spellLink = GetSpellLinkWithIcon(spellId)
    local verb = (category == "Repair Bot" and "deployed") or (category == "Feast" and "dropped") or (category == "Portal" and "opened") or "cast"
    OutputMessage(string_format("%s %s %s: %s.", sourceColor, verb, category, spellLink))
end

-- Combat Res
local function HandleResurrect(sourceName, sourceGUID, sourceFlags, destName, destGUID, destFlags, spellId)
    if not enabled("enableResurrect") then return end
    if not (FromOurGroup(sourceFlags) or FromOurGroup(destFlags)) then return end
    if not (R.spells and R.spells.combatRes and R.spells.combatRes[spellId]) then return end
    local sourceColor = ColorUnitName(sourceName, sourceGUID, sourceFlags)
    local destColor = ColorUnitName(destName, destGUID, destFlags)
    local spellLink = GetSpellLinkWithIcon(spellId)
    OutputMessage(string_format("%s used %s on %s.", sourceColor, spellLink, destColor))
end

----------------------------------------------------------------------------------------
--  Main CL routing
----------------------------------------------------------------------------------------
local function ProcessCombatLogEvent(...)
    local _, subevent, _, sourceGUID, sourceName, sourceFlags, _, destGUID, destName, destFlags = ...

    -- Cache spell tables
    local spells = R.spells
    local taunts = spells and spells.taunts
    local utilities = spells and spells.utilities

    if subevent == "SPELL_INTERRUPT" then
        local spellId, _, _, extraSpellId, extraSpellName = select(12, ...)
        if not FromOurGroup(sourceFlags) then return end
        if ShouldProcessEvent("INT", sourceGUID, destGUID) then
            HandleInterrupt(spellId, sourceName, sourceGUID, sourceFlags, destName, destGUID, destFlags, extraSpellId, extraSpellName)
        end
    elseif subevent == "SPELL_CAST_FAILED" then
        local spellId, _, _, failedType = select(12, ...)
        if failedType ~= "INTERRUPTED" then return end
        if not FromOurGroup(sourceFlags) then return end
        if ShouldProcessEvent("INT_FAIL", sourceGUID, destGUID) then
            HandleFailedInterrupt(sourceName, sourceGUID, sourceFlags, destName, destGUID, destFlags, spellId)
        end
    elseif subevent == "SPELL_DISPEL" then
        local spellId, _, _, extraSpellId, extraSpellName = select(12, ...)
        if not (FromOurGroup(sourceFlags) or FromOurGroup(destFlags)) then return end
        if ShouldProcessEvent("DISPEL", sourceGUID, destGUID) then
            HandleDispel(spellId, sourceName, sourceGUID, sourceFlags, destName, destGUID, destFlags, extraSpellId, extraSpellName)
        end
    elseif subevent == "SPELL_CAST_SUCCESS" then
        local spellId = select(12, ...)
        local isTaunt = taunts and taunts[spellId]
        local utilCat = (not isTaunt) and (utilities and UtilityCategory(spellId)) or nil
        if not isTaunt and not utilCat then return end
        if not FromOurGroup(sourceFlags) then return end
        if ShouldProcessEvent("SCS", sourceGUID, destGUID) then
            if isTaunt then
                HandleTaunt(spellId, sourceName, sourceGUID, sourceFlags, destName, destGUID, destFlags)
            else
                HandleUtility(spellId, sourceName, sourceGUID, sourceFlags)
            end
        end
    elseif subevent == "SPELL_DAMAGE" then
        local spellId = select(12, ...)
        if FromOurGroup(destFlags) then
            RecordLastHit(destGUID, destFlags, sourceName, sourceGUID, sourceFlags, spellId)
        end
    elseif subevent == "SWING_DAMAGE" then
        local amount = select(12, ...)
        if FromOurGroup(destFlags) then
            RecordLastHit(destGUID, destFlags, sourceName, sourceGUID, sourceFlags, 6603)
        end
    elseif subevent == "RANGE_DAMAGE" then
        local spellId = select(12, ...)
        if FromOurGroup(destFlags) then
            RecordLastHit(destGUID, destFlags, sourceName, sourceGUID, sourceFlags, spellId)
        end
    elseif subevent == "SPELL_PERIODIC_DAMAGE" then
        local spellId = select(12, ...)
        if FromOurGroup(destFlags) then
            RecordLastHit(destGUID, destFlags, sourceName, sourceGUID, sourceFlags, spellId)
        end
    elseif subevent == "ENVIRONMENTAL_DAMAGE" then
        local damageType = select(12, ...)
        if FromOurGroup(destFlags) then
            RecordLastHit(destGUID, destFlags, sourceName, sourceGUID, sourceFlags, 0, damageType)
        end
    elseif subevent == "UNIT_DIED" then
        HandleDeath(destGUID, destName, destFlags)
    elseif subevent == "SPELL_RESURRECT" then
        local spellId = select(12, ...)
        if not (FromOurGroup(sourceFlags) or FromOurGroup(destFlags)) then return end
        if ShouldProcessEvent("RES", sourceGUID, destGUID) then
            HandleResurrect(sourceName, sourceGUID, sourceFlags, destName, destGUID, destFlags, spellId)
        end
    end
end
local f = CreateFrame("Frame")

local function SafeProcess(...)
    local ok, err = pcall(ProcessCombatLogEvent, ...)
    if not ok and C and C.advcombatlog and C.advcombatlog.debug then
        print("ACL ERR:", tostring(err))
    end
end

local processFunc = ProcessCombatLogEvent

local function RefreshActive()
    local inInstance = IsInInstance()
    if inInstance then
        f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    else
        f:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        wipe(lastProcessedTime); wipe(lastHit)
    end
    processFunc = (C and C.advcombatlog and C.advcombatlog.debug) and SafeProcess or ProcessCombatLogEvent
end

f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("UNIT_PET")

f:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        RefreshActive()
        if SetupChatHyperlinkHandlers then SetupChatHyperlinkHandlers() end
        UpdatePetOwners()
        return
    end
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        processFunc(CombatLogGetCurrentEventInfo())
    elseif event == "GROUP_ROSTER_UPDATE" or event == "UNIT_PET" then
        UpdatePetOwners()
    end
end)

-- Initial setup
RefreshActive()
UpdatePetOwners()

----------------------------------------------------------------------------------------
--	Chat Link Handling
----------------------------------------------------------------------------------------
-- We'll install hyperlink handlers once the default chat frame is available
local chatFrame
local originalOnHyperlinkClick
local originalOnHyperlinkEnter
local originalOnHyperlinkLeave

-- Custom OnHyperlinkClick handler
local function CustomOnHyperlinkClick(self, link, text, button)
    if not link then
        return originalOnHyperlinkClick and originalOnHyperlinkClick(self, link, text, button)
    end

    local linkType, spellId = link:match("^([^:]+):(%d+)")
    if linkType == "spell" and spellId then
        spellId = tonumber(spellId)
        local getSpellLink = rawget(_G, 'GetSpellLink')
        if getSpellLink then
            local spellLink = getSpellLink(spellId)
            if spellLink then
                ChatEdit_InsertLink(spellLink)
            end
        else
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:SetSpellByID(spellId)
            GameTooltip:Show()
        end
    elseif originalOnHyperlinkClick then
        -- Call original handler for other link types
        originalOnHyperlinkClick(self, link, text, button)
    end
end

-- Custom OnHyperlinkEnter handler
local function CustomOnHyperlinkEnter(self, link, text)
    if not link then
        return originalOnHyperlinkEnter and originalOnHyperlinkEnter(self, link, text)
    end

    local linkType, spellId = link:match("^([^:]+):(%d+)")
    if linkType == "spell" and spellId then
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetSpellByID(tonumber(spellId))
        GameTooltip:Show()
    elseif originalOnHyperlinkEnter then
        -- Call original handler for other link types
        originalOnHyperlinkEnter(self, link, text)
    end
end

-- Custom OnHyperlinkLeave handler
local function CustomOnHyperlinkLeave(self, link, text)
    GameTooltip:Hide()
    if originalOnHyperlinkLeave then
        -- Call original handler
        originalOnHyperlinkLeave(self, link, text)
    end
end

-- Safe installer that waits for DEFAULT_CHAT_FRAME
function SetupChatHyperlinkHandlers()
    if chatFrame and chatFrame == DEFAULT_CHAT_FRAME then
        return -- already set
    end
    if not DEFAULT_CHAT_FRAME then
        return -- not yet available
    end
    chatFrame = DEFAULT_CHAT_FRAME
    -- Store original handlers (may be nil)
    originalOnHyperlinkClick = chatFrame:GetScript("OnHyperlinkClick")
    originalOnHyperlinkEnter = chatFrame:GetScript("OnHyperlinkEnter")
    originalOnHyperlinkLeave = chatFrame:GetScript("OnHyperlinkLeave")
    -- Set custom handlers
    chatFrame:SetScript("OnHyperlinkClick", CustomOnHyperlinkClick)
    chatFrame:SetScript("OnHyperlinkEnter", CustomOnHyperlinkEnter)
    chatFrame:SetScript("OnHyperlinkLeave", CustomOnHyperlinkLeave)
    if C.advcombatlog.debug then print("ACL: Chat hyperlink handlers installed") end
end

-- Try to install immediately in case chat is ready
SetupChatHyperlinkHandlers()

-- Also install on entering world when chat is guaranteed
-- Reuse existing event frame: add call inside PLAYER_ENTERING_WORLD branch above
