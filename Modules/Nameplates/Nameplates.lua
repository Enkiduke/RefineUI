local R, C, L = unpack(RefineUI)
local _, ns = ...
local oUF = ns.oUF
local NP = R.NP or {}
R.NP = NP

----------------------------------------------------------------------------------------
-- Style Function
----------------------------------------------------------------------------------------
local function CreateNameplate(self, unit)
    -- Rely on oUF/Blizzard visibility; avoid zero-delay timers
    
    NP.ConfigureNameplate(self, unit)

    NP.CreateHealthBar(self, unit)

    NP.CreatePowerBar(self, unit)

    NP.CreateNameText(self)

    -- Heavy elements (portrait, castbar, auras) are created lazily on demand in NP.Callback

    -- Crowd Control bar is created lazily in NP.Callback when needed

    NP.CreateRaidIcon(self, unit)

    if C.nameplate.targetIndicator then
        NP.CreateTargetIndicator(self)
    end

    if C.nameplate.targetGlow then
        NP.CreateTargetGlow(self)
    end

    -- Auras created lazily in NP.Callback when needed

    return self
end

----------------------------------------------------------------------------------------
-- Register Style and Spawn NamePlates
----------------------------------------------------------------------------------------
oUF:RegisterStyle("RefineUINameplates", CreateNameplate)
oUF:SetActiveStyle("RefineUINameplates")
oUF:SpawnNamePlates("RefineUINameplates", NP.Callback)

-- Centralize target updates to avoid per-plate event handlers
local targetEventFrame = CreateFrame("Frame")
targetEventFrame:SetScript("OnEvent", function()
    local old = NP._lastTargetFrame
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("target") or nil
    local new = plate and rawget(plate, "__Refine") or nil
    if old and old ~= new then
        NP.UpdateTarget(old)
    end
    if new then
        NP.UpdateTarget(new)
    end
    NP._lastTargetFrame = new
    -- Ensure all plates reflect correct alpha immediately (fallback to per-plate in case CVar propagation lags)
    if NP.ApplyAlphaAll then NP.ApplyAlphaAll() end
end)
targetEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
targetEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

-- Maintain a GUID->plate reference map for O(1) lookups (used by CLEU handlers)
local _mapFrame = CreateFrame("Frame")
_mapFrame:SetScript("OnEvent", function(_, event, unit)
    if not unit then return end
    local guid = UnitGUID(unit)
    if not guid then return end
    if event == "NAME_PLATE_UNIT_ADDED" then
        local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
        local ref = plate and rawget(plate, "__Refine") or nil
        if ref then
            NP._plateByGUID = NP._plateByGUID or {}
            NP._plateByGUID[guid] = ref
        end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if NP._plateByGUID then
            NP._plateByGUID[guid] = nil
        end
    end
end)
_mapFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
_mapFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")

-- Centralize threat updates for performance (single dispatcher vs per-plate listeners)
local threatEventFrame = CreateFrame("Frame")
threatEventFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_THREAT_SITUATION_UPDATE" or event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_FLAGS" or event == "NAME_PLATE_UNIT_ADDED" then
        if unit and C_NamePlate and C_NamePlate.GetNamePlateForUnit then
            local plate = C_NamePlate.GetNamePlateForUnit(unit)
            local ref = plate and rawget(plate, "__Refine") or nil
            if ref and NP and NP.ThreatEvent then
                if C and C.nameplate and C.nameplate.disableFriendlyHealth and UnitIsFriend("player", unit) then
                    return
                end
                NP.ThreatEvent(ref, event, unit)
            end
        end
    elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
        if C_NamePlate and C_NamePlate.GetNamePlates then
            local plates = C_NamePlate.GetNamePlates()
            for i = 1, #plates do
                local ref = rawget(plates[i], "__Refine")
                if ref and NP and NP.ThreatEvent then
                    if not (C and C.nameplate and C.nameplate.disableFriendlyHealth and ref.unit and UnitIsFriend("player", ref.unit)) then
                        NP.ThreatEvent(ref, event, ref.unit)
                    end
                end
            end
        end
    end
end)
threatEventFrame:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
threatEventFrame:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
threatEventFrame:RegisterEvent("UNIT_FLAGS")
threatEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
threatEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
threatEventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
