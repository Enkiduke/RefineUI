local R, C, L = unpack(RefineUI)
local frame = CreateFrame("Frame")
-- Upvalue hot-path WoW APIs
local GetCVar, SetCVar = GetCVar, SetCVar
local IsInInstance, UnitInBattleground = IsInInstance, UnitInBattleground
local UnitExists, UnitAffectingCombat = UnitExists, UnitAffectingCombat
local ipairs, pairs, tostring, tonumber, type = ipairs, pairs, tostring, tonumber, type

-- Cache last computed state and last CVar values to avoid redundant writes
local lastState = {
    inCombat = nil,
    inGroupContent = nil,
    hasTarget = nil,
}
local lastCVars = {}

-- Only write CVars when values actually change
local function SetCVarIfChanged(cvar, value)
    if cvar == nil then return end
    local desired
    if type(value) == "boolean" then
        desired = value and "1" or "0"
    else
        desired = tostring(value)
    end

    local current = GetCVar and GetCVar(cvar) or nil
    if current == nil then
        SetCVar(cvar, desired)
        return
    end

    local curNum = tonumber(current)
    local desNum = tonumber(desired)
    if curNum and desNum then
        if math.abs(curNum - desNum) > 1e-6 then
            SetCVar(cvar, desired)
        end
    else
        if current ~= desired then
            SetCVar(cvar, desired)
        end
    end
end

-- Extra gate: also skip when our last computed desired value for this session hasn’t changed
local function SetCVarGated(cvar, value)
    local desired = (type(value) == "boolean") and (value and "1" or "0") or tostring(value)
    if lastCVars[cvar] == desired then return end
    lastCVars[cvar] = desired
    SetCVarIfChanged(cvar, value)
end

local function UpdateNameplateCVars(inCombat)
    local inInstance, instanceType = IsInInstance()
    local inBattleground = UnitInBattleground("player")
    local inGroupContent = (instanceType == 'party' or instanceType == 'raid') or inBattleground

    -- Early-out if nothing material changed since last computation
    local hasTarget = UnitExists("target") and true or false
    if lastState.inCombat == inCombat and lastState.inGroupContent == inGroupContent and lastState.hasTarget == hasTarget then
        return
    end

    -- nameplateMotion: 0=Overlapping, 1=Stacking, 2=Spreading
    -- Desired behavior: Out of combat -> Overlapping (0); In combat -> Stacking (1)
    SetCVarGated("nameplateMotion", inCombat and 1 or 0)
    SetCVarGated("nameplateShowFriends", (not inGroupContent and not inCombat) and 1 or 0)
    SetCVarGated("nameplateShowFriendlyNPCs", inGroupContent and 0 or 1)

    -- Adjust notSelectedAlpha depending on whether there is a target
    local desiredAlpha = hasTarget and (C.nameplate.alpha or .9) or (C.nameplate.noTargetAlpha or 1)
    SetCVarGated("nameplateNotSelectedAlpha", desiredAlpha)

    -- Update cached state after successful evaluation
    lastState.inCombat = inCombat
    lastState.inGroupContent = inGroupContent
    lastState.hasTarget = hasTarget
end

local function InitializeNameplates()
    -- Set nameplate fonts
    local fontPath = C.media.normalFont or "Interface\\AddOns\\RefineUI\\Media\\Fonts\\Barlow-Bold-Upper.ttf"
    local fontObjects = {
        _G.SystemFont_NamePlate,
        _G.SystemFont_NamePlateFixed,
        _G.SystemFont_LargeNamePlate,
        _G.SystemFont_LargeNamePlateFixed
    }
    for i, fontObject in ipairs(fontObjects) do
        local size = i > 2 and 10 or 8
        fontObject:SetFont(fontPath, size, "OUTLINE")
    end

    -- Set threat-related CVars
    if C.nameplate.enhanceThreat then
        SetCVarIfChanged("threatWarning", 3)
    end

    -- Set general nameplate CVars
    local generalCVars = {
        nameplateGlobalScale = 1,
        namePlateMinScale = 1,
        namePlateMaxScale = 1,
        nameplateLargerScale = 1,
        nameplateSelectedScale = 1,
        nameplateMinAlpha = .5,
        nameplateMaxAlpha = 1,
        nameplateMaxDistance = 60,
        nameplateMinAlphaDistance = 0,
        nameplateMaxAlphaDistance = 40,
        nameplateOccludedAlphaMult = .1,
    nameplateSelectedAlpha = 1,
    nameplateNotSelectedAlpha = C.nameplate.alpha or .9,
        nameplateLargeTopInset = 0.08,
        nameplateOtherTopInset = C.nameplate.clamp and 0.08 or -1,
        nameplateOtherBottomInset = C.nameplate.clamp and 0.1 or -1,
        clampTargetNameplateToScreen = C.nameplate.clamp and "1" or "0",
        nameplatePlayerMaxDistance = 60,
        nameplateShowOnlyNames = C.nameplate.onlyName and 1 or 0
    }

    for cvar, value in pairs(generalCVars) do
        SetCVarIfChanged(cvar, value)
    end

    -- Change nameplate fonts
    local function changeFont(fontObject, size)
        local mult = size or 1
        fontObject:SetFont(C.font.nameplates.default[1], C.font.nameplates.default[2] * mult, C.font.nameplates.default[3])
        fontObject:SetShadowOffset(1, -1)
    end
    changeFont(SystemFont_NamePlateFixed)
    changeFont(SystemFont_LargeNamePlateFixed, 2)

    -- Apply first-time settings without pre-seeding lastState so we don't early-out
    lastState.inCombat = nil
    lastState.inGroupContent = nil
    lastState.hasTarget = nil
    UpdateNameplateCVars(false)
end

frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        InitializeNameplates()
        return
    end

    if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_ENTERING_WORLD" then
        if C.nameplate.combat then
            UpdateNameplateCVars(event == "PLAYER_REGEN_DISABLED")
        else
            UpdateNameplateCVars(false)
        end
        return
    end

    if event == "PLAYER_TARGET_CHANGED" then
        -- Update the non-selected alpha when acquiring/clearing target
        UpdateNameplateCVars(UnitAffectingCombat("player"))
        return
    end
end)

frame:RegisterEvent("PLAYER_LOGIN")
if C.nameplate.combat then
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
end
frame:RegisterEvent("PLAYER_TARGET_CHANGED")