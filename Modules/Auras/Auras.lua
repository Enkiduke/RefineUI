local _, RefineUI = ...
local Auras = RefineUI:RegisterModule("Auras")

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config
local Media = RefineUI.Media

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues 
----------------------------------------------------------------------------------------
local _G = _G
local ipairs = ipairs
local pairs = pairs
local CreateFrame = CreateFrame
local type = type
local tostring = tostring
local max = math.max
local strfind = string.find
local strlower = string.lower
local InCombatLockdown = InCombatLockdown

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local AURAS_SKIN_STATE_REGISTRY = "Auras:SkinState"

local AURA_SIZE = 32
local BUFF_BORDER_INSET_X = 4
local BUFF_BORDER_INSET_Y = 4
local BUFF_BORDER_EDGE_SIZE = 8
local DEBUFF_BORDER_INSET_X = 6
local DEBUFF_BORDER_INSET_Y = 6
local DEBUFF_BORDER_EDGE_SIZE = 12

local HOOK_KEY = {
    BUFF_UPDATE = "Auras:BuffFrame:UpdateAuraButtons",
    BUFF_EDIT = "Auras:BuffFrame:OnEditModeEnter",
    DEBUFF_UPDATE = "Auras:DebuffFrame:UpdateAuraButtons",
    DEBUFF_EDIT = "Auras:DebuffFrame:OnEditModeEnter",
    DEBUFF_EDITMODE_SETTINGS_RETRY = "Auras:DebuffFrame:EditModeSettings:Retry",
}

----------------------------------------------------------------------------------------
-- External State (Secure-safe)
----------------------------------------------------------------------------------------
local SkinState = RefineUI:CreateDataRegistry(AURAS_SKIN_STATE_REGISTRY, "k")

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function BuildAurasHookKey(owner, method)
    local ownerId
    if type(owner) == "table" and owner.GetName then
        ownerId = owner:GetName()
    end
    if not ownerId or ownerId == "" then
        ownerId = tostring(owner)
    end
    return "Auras:" .. ownerId .. ":" .. method
end

local function GetSkinState(frame)
    if not SkinState[frame] then
        SkinState[frame] = {}
    end
    return SkinState[frame]
end

local function IsSecretValue(v)
    local issecret = _G.issecretvalue
    return issecret and issecret(v) or false
end

local function GetAuraFilterFromButtonInfo(buttonInfo)
    if not buttonInfo then return nil end
    local auraType = buttonInfo.auraType
    if auraType == "Debuff" or auraType == "DeadlyDebuff" or buttonInfo.isHarmful then
        return "HARMFUL"
    end
    if auraType == "Buff" or auraType == "TempEnchant" or buttonInfo.isHelpful then
        return "HELPFUL"
    end
    return nil
end

local function ResolveAuraDataFromButtonInfo(buttonInfo)
    if not C_UnitAuras or not buttonInfo then return nil, nil end

    local instanceID = buttonInfo.auraInstanceID
    local filter = GetAuraFilterFromButtonInfo(buttonInfo)

    if instanceID and C_UnitAuras.GetAuraDataByAuraInstanceID then
        local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID("player", instanceID)
        if auraData then
            return auraData, "instanceID"
        end
    end

    if buttonInfo.index and filter and C_UnitAuras.GetAuraDataByIndex then
        local auraData = C_UnitAuras.GetAuraDataByIndex("player", buttonInfo.index, filter)
        if auraData then
            return auraData, "index"
        end
    end

    return nil, nil
end

local function TryGetDebuffColorByTypeName(debuffType)
    if not debuffType or IsSecretValue(debuffType) then
        return nil
    end

    local map = _G.DebuffTypeColor
    local entry = map and map[debuffType]
    if entry and entry.r and entry.g and entry.b then
        return entry.r, entry.g, entry.b, "debuffType"
    end

    return nil
end

local function GetAuraDispelColorCurve()
    if Auras._DispelColorCurve ~= nil then
        return Auras._DispelColorCurve or nil
    end

    if not _G.C_CurveUtil or not _G.C_CurveUtil.CreateColorCurve then
        Auras._DispelColorCurve = false
        return nil
    end

    if not _G.Enum or not _G.Enum.LuaCurveType or not _G.Enum.LuaCurveType.Step then
        Auras._DispelColorCurve = false
        return nil
    end

    local curve = _G.C_CurveUtil.CreateColorCurve()
    if not curve then
        Auras._DispelColorCurve = false
        return nil
    end

    curve:SetType(_G.Enum.LuaCurveType.Step)

    local colorInfo = {
        [0] = _G.DEBUFF_TYPE_NONE_COLOR,
        [1] = _G.DEBUFF_TYPE_MAGIC_COLOR,
        [2] = _G.DEBUFF_TYPE_CURSE_COLOR,
        [3] = _G.DEBUFF_TYPE_DISEASE_COLOR,
        [4] = _G.DEBUFF_TYPE_POISON_COLOR,
        [9] = _G.DEBUFF_TYPE_BLEED_COLOR,
        [11] = _G.DEBUFF_TYPE_BLEED_COLOR,
    }

    for dispelID, color in pairs(colorInfo) do
        if color then
            curve:AddPoint(dispelID, color)
        end
    end

    Auras._DispelColorCurve = curve
    return curve
end

local function TryGetDebuffColorByAuraInstanceID(unit, auraInstanceID)
    if not C_UnitAuras or not C_UnitAuras.GetAuraDispelTypeColor then
        return nil
    end
    if not auraInstanceID or IsSecretValue(auraInstanceID) then
        return nil
    end

    local curve = GetAuraDispelColorCurve()
    if not curve then
        return nil
    end

    local color = C_UnitAuras.GetAuraDispelTypeColor(unit or "player", auraInstanceID, curve)
    if color and not IsSecretValue(color) and color.r and color.g and color.b then
        return color.r, color.g, color.b, "auraDispelTypeColor"
    end

    return nil
end

local function TryGetDebuffColorByAtlas(atlas)
    if not atlas or IsSecretValue(atlas) or type(atlas) ~= "string" then
        return nil
    end

    local lowerAtlas = strlower(atlas)
    if strfind(lowerAtlas, "magic", 1, true) then
        local c = _G.DebuffTypeColor and _G.DebuffTypeColor.Magic
        if c then return c.r, c.g, c.b, "debuffAtlas:Magic" end
    elseif strfind(lowerAtlas, "curse", 1, true) then
        local c = _G.DebuffTypeColor and _G.DebuffTypeColor.Curse
        if c then return c.r, c.g, c.b, "debuffAtlas:Curse" end
    elseif strfind(lowerAtlas, "disease", 1, true) then
        local c = _G.DebuffTypeColor and _G.DebuffTypeColor.Disease
        if c then return c.r, c.g, c.b, "debuffAtlas:Disease" end
    elseif strfind(lowerAtlas, "poison", 1, true) then
        local c = _G.DebuffTypeColor and _G.DebuffTypeColor.Poison
        if c then return c.r, c.g, c.b, "debuffAtlas:Poison" end
    elseif strfind(lowerAtlas, "bleed", 1, true) then
        local c = _G.DebuffTypeColor and _G.DebuffTypeColor.Bleed
        if c then return c.r, c.g, c.b, "debuffAtlas:Bleed" end
    end

    return nil
end

local function RegisterDebuffEditModeSettings()
    if Auras._debuffEditModeSettingsAttached then
        return true
    end

    local lib = RefineUI.LibEditMode
    if not lib or type(lib.AddFrameSettings) ~= "function" or not lib.SettingType then
        return false
    end

    local debuffFrame = _G.DebuffFrame
    if not debuffFrame then
        return false
    end

    -- LibEditMode:AddFrameSettings requires the frame to have been registered with AddFrame first.
    -- On reload (especially in combat) that registration may not exist yet.
    if not (lib.frameSelections and lib.frameSelections[debuffFrame]) then
        return false
    end

    if not Auras._debuffEditModeSettings then
        local settingType = lib.SettingType
        if not settingType.Checkbox then
            return false
        end

        Auras._debuffEditModeSettings = {
            {
                kind = settingType.Checkbox,
                name = "Combat Tooltips",
                desc = "Allow player debuff tooltips in combat.",
                default = false,
                get = function()
                    return Config.Auras and Config.Auras.AllowDebuffTooltipsInCombat == true
                end,
                set = function(_, value)
                    Config.Auras = Config.Auras or {}
                    Config.Auras.AllowDebuffTooltipsInCombat = value and true or false
                end,
            },
        }
    end

    local ok = pcall(lib.AddFrameSettings, lib, debuffFrame, Auras._debuffEditModeSettings)
    if ok then
        Auras._debuffEditModeSettingsAttached = true
        RefineUI:OffEvent("PLAYER_REGEN_ENABLED", HOOK_KEY.DEBUFF_EDITMODE_SETTINGS_RETRY)
        return true
    end

    return false
end


----------------------------------------------------------------------------------------
-- Skinning
----------------------------------------------------------------------------------------
local function StyleAuraButton(frame)
    if not frame or frame:IsForbidden() then return end
    
    local state = GetSkinState(frame)
    if state.isSkinned or frame.isAuraAnchor then return end
    
    local wrapper = CreateFrame("Frame", nil, frame)
    wrapper:SetSize(AURA_SIZE, AURA_SIZE)
    wrapper:SetPoint("CENTER")
    state.wrapper = wrapper
    
    local icon = frame.Icon
    if icon and icon.GetTexture then
        local skinnedIcon = wrapper:CreateTexture(nil, "BACKGROUND")
        skinnedIcon:SetAllPoints(wrapper)
        skinnedIcon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        
        local tex = icon:GetTexture()
        if tex then skinnedIcon:SetTexture(tex) end
        
        RefineUI:HookOnce(BuildAurasHookKey(icon, "SetTexture"), icon, "SetTexture", function(_, t)
            skinnedIcon:SetTexture(t)
        end)
        
        icon:SetAlpha(0)
        state.skinnedIcon = skinnedIcon
    end

    if not state.RefineCooldown then
        local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
        cd:ClearAllPoints()
        cd:SetPoint("TOPLEFT", wrapper, "TOPLEFT", -3, 3)
        cd:SetPoint("BOTTOMRIGHT", wrapper, "BOTTOMRIGHT", 3, -3)
        cd:SetFrameLevel(frame:GetFrameLevel() + 50)
        cd:SetDrawEdge(false)
        cd:SetDrawBling(false)
        cd:SetDrawSwipe(true)
        cd:SetSwipeColor(0, 0, 0, 1)
        cd:SetReverse(true)
        
        if Media and Media.Textures and Media.Textures.CooldownSwipe then
            cd:SetSwipeTexture(Media.Textures.CooldownSwipe)
        end
        
        local regions = {cd:GetRegions()}
        for _, region in ipairs(regions) do
            if region:GetObjectType() == "FontString" then
                region:ClearAllPoints()
                region:SetPoint("BOTTOM", 0, 2)
                RefineUI.Font(region, 12, nil, "OUTLINE")
                break
            end
        end

        state.RefineCooldown = cd
    end
    
    if frame.Count then
        frame.Count:ClearAllPoints()
        frame.Count:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
        RefineUI.Font(frame.Count, 12, nil, "OUTLINE")
    end

    if frame.Duration then
        frame.Duration:Hide()

        RefineUI:HookOnce(BuildAurasHookKey(frame.Duration, "Show:Hide"), frame.Duration, "Show", function(self)
            self:Hide()
        end)

        RefineUI:HookOnce(BuildAurasHookKey(frame.Duration, "SetShown:Hide"), frame.Duration, "SetShown", function(self, shown)
            if shown then
                self:Hide()
            end
        end)
    end
    
    if frame.DebuffBorder then
        frame.DebuffBorder:SetAlpha(0)
    end
    
    if frame.TempEnchantBorder then
        frame.TempEnchantBorder:SetAlpha(0)
    end
    
    RefineUI.CreateBorder(wrapper, BUFF_BORDER_INSET_X, BUFF_BORDER_INSET_Y, BUFF_BORDER_EDGE_SIZE)
    
    RefineUI:HookOnce(BuildAurasHookKey(frame, "Update"), frame, "Update", function(self, buttonInfo)
        local s = GetSkinState(self)
        if not s.wrapper or not s.wrapper.border then return end

        local info = buttonInfo
        local auraData = nil
        local auraDurationObj = nil
        local instanceID = info and info.auraInstanceID
        if info then
            auraData = ResolveAuraDataFromButtonInfo(info)
            if auraData and not instanceID then
                instanceID = auraData.auraInstanceID
            end
        end

        if self.Duration and self.Duration:IsShown() then
            self.Duration:Hide()
        end

        local wantLevel = max(0, s.wrapper:GetFrameLevel() + 1)
        if s.wrapper.border.GetFrameLevel and s.wrapper.border:GetFrameLevel() ~= wantLevel then
            s.wrapper.border:SetFrameLevel(wantLevel)
        end
        
        local color = Config.General.BorderColor
        local r, g, b = color[1], color[2], color[3]
        
        local isDebuff = self.DebuffBorder and self.DebuffBorder:IsShown()
        local isTemp = self.TempEnchantBorder and self.TempEnchantBorder:IsShown()
        
        local isDebuffSecret = IsSecretValue(isDebuff)
        local isTempSecret = IsSecretValue(isTemp)

        if not isDebuffSecret then
            if isDebuff then
                RefineUI.CreateBorder(s.wrapper, DEBUFF_BORDER_INSET_X, DEBUFF_BORDER_INSET_Y, DEBUFF_BORDER_EDGE_SIZE)
            else
                RefineUI.CreateBorder(s.wrapper, BUFF_BORDER_INSET_X, BUFF_BORDER_INSET_Y, BUFF_BORDER_EDGE_SIZE)
            end
        end
        
        if isDebuff and not isDebuffSecret then
            local debuffType = info and info.debuffType
            local cr, cg, cb = TryGetDebuffColorByAuraInstanceID("player", instanceID)
            if not cr then
                cr, cg, cb = TryGetDebuffColorByTypeName(debuffType)
            end
            if not cr and self.DebuffBorder and self.DebuffBorder.GetAtlas then
                cr, cg, cb = TryGetDebuffColorByAtlas(self.DebuffBorder:GetAtlas())
            end

            if cr and cg and cb then
                r, g, b = cr, cg, cb
            else
                local vertexR, vertexG, vertexB = self.DebuffBorder:GetVertexColor()
                r, g, b = vertexR, vertexG, vertexB
                if r == 1 and g == 1 and b == 1 then
                    r, g, b = 0.9, 0.2, 0.2
                end
            end
        elseif isTemp and not isTempSecret then
            r, g, b = 0.6, 0.1, 0.6
        end
        
        s.wrapper.border:SetBackdropBorderColor(r, g, b, 1)
        
        if s.RefineCooldown then
            if s.RefineCooldown:GetFrameLevel() <= s.wrapper:GetFrameLevel() then
                s.RefineCooldown:SetFrameLevel(s.wrapper:GetFrameLevel() + 50)
            end
            
            local set = false

            if C_UnitAuras and C_UnitAuras.GetAuraDuration and instanceID then
                if auraDurationObj == nil then
                    auraDurationObj = C_UnitAuras.GetAuraDuration("player", instanceID)
                end
                -- Duration object existence is the combat-safe signal Blizzard expects for SetCooldownFromDurationObject.
                -- Do not gate this on readable duration values; that can break countdown text in combat.
                if auraDurationObj then
                    s.RefineCooldown:SetCooldownFromDurationObject(auraDurationObj)
                    set = true
                end
            end
            
            if not set and info then
                 local duration = info.duration
                 local expTime = info.expirationTime
                 
                 local isSecret = false
                 if _G.issecretvalue then
                     if _G.issecretvalue(duration) or _G.issecretvalue(expTime) then
                         isSecret = true
                     end
                 end
                 
                 if not isSecret and duration and expTime and duration > 0 then
                     s.RefineCooldown:SetCooldown(expTime - duration, duration)
                     set = true
                 elseif isSecret then
                 end
            end
            
            if set then
                s.RefineCooldown:Show()
            else
                s.RefineCooldown:Hide()
            end
        end
    end)
    
    state.isSkinned = true
end

----------------------------------------------------------------------------------------
-- Hook Handlers
----------------------------------------------------------------------------------------
local function UpdateAuraButtons(self)
    if not self.auraFrames then return end
    for _, frame in ipairs(self.auraFrames) do
        StyleAuraButton(frame)
    end
    if self.exampleAuraFrames then
        for _, frame in ipairs(self.exampleAuraFrames) do
            StyleAuraButton(frame)
        end
    end
end

-- Lifecycle
----------------------------------------------------------------------------------------
function Auras:OnEnable()
    if not Config.Auras.Enable then return end
    if InCombatLockdown and InCombatLockdown() then
        RefineUI:RegisterEventCallback("PLAYER_REGEN_ENABLED", function()
            RegisterDebuffEditModeSettings()
        end, HOOK_KEY.DEBUFF_EDITMODE_SETTINGS_RETRY)
    else
        RegisterDebuffEditModeSettings()
    end
    
    if _G.BuffFrame then
        if type(_G.BuffFrame.UpdateAuraButtons) == "function" then
            RefineUI:HookOnce(HOOK_KEY.BUFF_UPDATE, _G.BuffFrame, "UpdateAuraButtons", UpdateAuraButtons)
        end
        if type(_G.BuffFrame.OnEditModeEnter) == "function" then
            RefineUI:HookOnce(HOOK_KEY.BUFF_EDIT, _G.BuffFrame, "OnEditModeEnter", UpdateAuraButtons)
        end
    end
    
    if _G.DebuffFrame then
        if type(_G.DebuffFrame.UpdateAuraButtons) == "function" then
            RefineUI:HookOnce(HOOK_KEY.DEBUFF_UPDATE, _G.DebuffFrame, "UpdateAuraButtons", UpdateAuraButtons)
        end
        if type(_G.DebuffFrame.OnEditModeEnter) == "function" then
            RefineUI:HookOnce(HOOK_KEY.DEBUFF_EDIT, _G.DebuffFrame, "OnEditModeEnter", UpdateAuraButtons)
        end
    end

    RegisterDebuffEditModeSettings()
end
