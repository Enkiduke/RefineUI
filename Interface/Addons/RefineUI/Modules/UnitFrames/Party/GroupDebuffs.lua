----------------------------------------------------------------------------------------
-- UnitFrames Party: Group Debuffs
-- Description: RefineUI-styled debuffs and big defensives on Compact Party/Raid frames.
--              12.1 draws Blizzard's copies in a secure environment, and turning them
--              off from an addon would taint the raid frames, so these only replace
--              Blizzard's while its "Display Debuffs" / "Center Big Defensive" raid
--              frame options are off. Debuff options live in the Party/Raid Edit Mode
--              panels because Blizzard greys its own out while "Display Debuffs" is off.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local Config = RefineUI.Config
local UnitFrames = RefineUI:GetModule("UnitFrames")
if not UnitFrames then
    return
end

local UF = UnitFrames
local P = UnitFrames:GetPrivate().Party
if not P then return end

local Auras = RefineUI:GetModule("Auras")

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local ipairs = ipairs
local pairs = pairs
local wipe = wipe
local floor = math.floor

local GetPartyData = P.GetData
local IsCompactPetUnitToken = P.IsPetUnit
local ForEachCompactPartyRaidFrame = P.ForEachRaidFrame
local StyleAuraButton = P.StyleCompactAuraButton
local CreateContainer = P.CreateCompactAuraContainer

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local DEBUFFS_CVAR = "raidFramesDisplayDebuffs"
local DEFENSIVE_CVAR = "raidFramesCenterBigDefensive"
local DISPELLABLE_ONLY_CVAR = "raidFramesDisplayOnlyDispellableDebuffs"
local LARGER_ROLE_DEBUFFS_CVAR = "raidFramesDisplayLargerRoleSpecificDebuffs"
local SHOW_DEBUFFS_LABEL = "Show Debuffs"
local SHOW_DEBUFFS_PAUSED_LABEL = "Show Debuffs |cffff6060(paused)|r"
local BLIZZARD_DEBUFFS_NOTICE = "Blizzard's Raid Frames \"Display Debuffs\" option is on, so RefineUI party/raid debuffs are paused. Turn it off in Options > Gameplay > Interface > Raid Frames."

local ICON_SIZE_BONUS = 2
local BOSS_SIZE_SCALE = 1.5 -- Blizzard_PrivateAurasUI BOSS_DEBUFF_SCALE_INCREASE
local BOTTOM_OFFSET = 2     -- Blizzard_PrivateAurasUI CUF_AURA_BOTTOM_OFFSET
local STRIDE = 3
local PRIVATE_AURA_COUNT = 2
local PRIVATE_LEVEL_OFFSET = 6
local DISPEL_BORDER_KEY = "dispelBorder"
local DISPEL_BORDER_LEVEL_OFFSET = 10 -- Above Group Buffs frame color borders
local FRAME_BORDER_INSET = 6 -- Matches the health border in FrameStyle.lua
local FRAME_BORDER_EDGE = 12
local DISPEL_GLOW_OFFSET = 2 -- Matches Style.lua GLOW_TEXTURE_ALIGNMENT_OFFSET
local ORGANIZATION = Enum.RaidAuraOrganizationType

local AuraFilters = AuraUtil.AuraFilters
local NOT_DISPELLABLE_FILTER = AuraUtil.CreateFilterString(AuraFilters.Harmful, AuraUtil.AuraFilterNegationPrefix .. AuraFilters.Raid)
local DISPELLABLE_FILTER = AuraUtil.CreateFilterString(AuraFilters.Harmful, AuraFilters.Raid)
local DEBUFF_TYPE = AuraUtil.AuraUpdateChangedType.Debuff

-- Both slots sit in the center; the external one draws on top when a unit has both.
-- Colors match the RefineUI player buff groups.
local DEFENSIVE_SLOTS = {
    {
        key = "external",
        filter = AuraUtil.CreateFilterString(AuraFilters.Helpful, AuraFilters.BigDefensive, AuraFilters.ExternalDefensive),
        colorGroup = "ExternalDefensive",
        levelOffset = 5,
    },
    {
        key = "personal",
        filter = AuraUtil.CreateFilterString(AuraFilters.Helpful, AuraFilters.BigDefensive, AuraUtil.AuraFilterNegationPrefix .. AuraFilters.ExternalDefensive),
        colorGroup = "BigDefensive",
        levelOffset = 0,
    },
}

-- Spells listed in Group Buffs are drawn (or hidden) there, not in the center.
local defensiveCandidateFilters = { excludeSpellIDs = {} }

-- Display order follows Blizzard's debuff priority: boss/role, player-dispellable, rest.
local DEBUFF_GROUPS = {
    {
        key = "boss",
        filter = NOT_DISPELLABLE_FILTER,
        maxFrameCount = 2,
        large = true,
        sortMethod = AuraContainerSortMethod.UnitFrameDebuff,
        candidateFilters = { processedAuraType = DEBUFF_TYPE, isBossOrRoleAura = true },
    },
    {
        key = "dispel",
        filter = DISPELLABLE_FILTER,
        maxFrameCount = 3,
    },
    {
        key = "debuff",
        filter = NOT_DISPELLABLE_FILTER,
        maxFrameCount = 3,
        sortMethod = AuraContainerSortMethod.UnitFrameDebuff,
        candidateFilters = { processedAuraType = DEBUFF_TYPE, isBossOrRoleAura = false },
    },
}

local DISPEL_BORDER_OPTIONS = {
    showWhenHarmful = true,
    showWithoutDispelType = true,
    style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset,
}

local settingsVersion = 0
local showDebuffs, showDefensive, dispellableOnly, largerRoleDebuffs, showDispelBorder, showDispelGlow
local editModeSettingsRegistered, showDebuffsSetting, blizzardDebuffsNoticeShown

----------------------------------------------------------------------------------------
-- Sizes
----------------------------------------------------------------------------------------
-- Matches the Group Buffs icon size.
local function GetDebuffSize(frame)
    return frame:GetBuffAuraSize() + ICON_SIZE_BONUS
end

local function GetBossDebuffSize(frame)
    local size = GetDebuffSize(frame)
    if largerRoleDebuffs then
        return floor(size * BOSS_SIZE_SCALE)
    end
    return size
end

local function GetGroupSize(frame, group)
    return group.large and GetBossDebuffSize(frame) or GetDebuffSize(frame)
end

local function GetDefensiveSize(frame)
    return frame:GetBigDefensiveAuraSize() + ICON_SIZE_BONUS
end

----------------------------------------------------------------------------------------
-- Aura Buttons
----------------------------------------------------------------------------------------
-- Blizzard colors the RefineUI border by dispel type; the pieces become secret after this.
local function AddDispelBorder(button)
    local pieces = button.RefineManagedBorder.Pieces
    for index = 1, #pieces do
        button:AddDispelTypeTexture(pieces[index], DISPEL_BORDER_OPTIONS)
    end
end

local function InitializeDebuffButton(button, size)
    StyleAuraButton(button, size)
    AddDispelBorder(button)
end

-- Covers the health border (and glows around it) while the unit has a debuff the
-- player can dispel.
local function InitializeDispelBorderButton(frame, state, button)
    local host = GetPartyData(frame).healthBarBorderHost or frame
    local width, height = host:GetWidth(), host:GetHeight()
    local level = frame.healthBar:GetFrameLevel() + DISPEL_BORDER_LEVEL_OFFSET
    local edgeSize = RefineUI:Scale(FRAME_BORDER_EDGE)
    button:SetAllPoints(host)
    button:EnableMouse(false)

    -- Built first so the border below ends up as button.RefineManagedBorder.
    Auras.CreateManagedBorder(button, FRAME_BORDER_INSET + DISPEL_GLOW_OFFSET, edgeSize)
    local glow = button.RefineManagedBorder
    glow:SetFrameLevel(level - 1)
    for _, piece in ipairs(glow.Pieces) do
        piece:SetTexture(RefineUI.Media.Textures.Glow, true, true)
        piece:SetBlendMode("ADD")
    end
    Auras.UpdateManagedBorder(button, width, height)
    AddDispelBorder(button)
    glow:SetShown(showDispelGlow)
    state.dispelGlow = glow

    Auras.CreateManagedBorder(button, FRAME_BORDER_INSET, edgeSize)
    local border = button.RefineManagedBorder
    border:SetFrameLevel(level)
    Auras.UpdateManagedBorder(button, width, height)
    AddDispelBorder(button)
    border:SetShown(showDispelBorder)
    state.dispelBorder = border
end

local function InitializeDefensiveButton(frame, slot, button)
    button:SetPoint("CENTER", frame, "CENTER")
    button:SetFrameLevel(button:GetFrameLevel() + slot.levelOffset)
    StyleAuraButton(button, GetDefensiveSize(frame))
    Auras.SetManagedBorderColor(button, Config.Auras.PlayerBuffs.Groups[slot.colorGroup].BorderColor)
end

----------------------------------------------------------------------------------------
-- Containers
----------------------------------------------------------------------------------------
local function EnsureState(frame)
    local data = GetPartyData(frame)
    local state = data.groupDebuffs
    if not state then
        state = {
            debuffs = CreateContainer(frame),
            defensive = CreateContainer(frame),
            privateAnchors = {},
            privateAnchorIDs = {},
        }
        state.defensive:SetAllPoints(frame)
        state.defensiveButtons = {}
        for index, slot in ipairs(DEFENSIVE_SLOTS) do
            state.defensiveButtons[index] = state.defensive:AddAuraSlot(slot.key, slot.filter, {
                sortMethod = AuraContainerSortMethod.BigDefensive,
                candidateFilters = defensiveCandidateFilters,
                initializeFrame = function(button)
                    InitializeDefensiveButton(frame, slot, button)
                end,
            })
        end
        state.defensiveVersion = settingsVersion
        data.groupDebuffs = state
    end
    return state
end

local function ApplyDebuffLayout(frame, container, organization, size, spacing, powerBarUsedHeight)
    local anchorPoint, horizontalDirection, offsetX = "BOTTOMLEFT", AnchorUtil.FlowDirection.Right, 3
    if organization == ORGANIZATION.BuffsTopDebuffsBottom then
        anchorPoint, horizontalDirection, offsetX = "BOTTOMRIGHT", AnchorUtil.FlowDirection.Left, -3
    end

    container:ClearAllPoints()
    container:SetPoint(anchorPoint, frame, anchorPoint, offsetX, BOTTOM_OFFSET + powerBarUsedHeight)
    container:SetFlowLayoutAnchorPoint(anchorPoint)
    container:SetFlowLayoutGrowthDirection(horizontalDirection, AnchorUtil.FlowDirection.Up)
    container:SetFlowLayoutMaximumLineSize(STRIDE * size + (STRIDE - 1) * spacing)
end

local function SyncDebuffGroups(frame, state, spacing)
    local container = state.debuffs
    container:SetAuraProcessingPolicy(CustomAuraContainerAuraProcessingPolicy.ProcessAura, {
        ignoreBuffs = true,
        displayOnlyDispellableDebuffs = dispellableOnly,
    })

    if showDebuffs or state.hasGroups then
        for index, group in ipairs(DEBUFF_GROUPS) do
            if not state.hasGroups then
                container:AddAuraGroup(group.key, group.filter, {
                    maxFrameCount = group.maxFrameCount,
                    sortMethod = group.sortMethod,
                    candidateFilters = group.candidateFilters,
                    initializeFrame = function(button)
                        InitializeDebuffButton(button, GetGroupSize(frame, group))
                    end,
                })
            end

            local size = GetGroupSize(frame, group)
            container:SetAuraGroupMaxFrameCount(group.key, showDebuffs and group.maxFrameCount or 0)
            container:SetAuraGroupLayout(group.key, {
                elementSpacing = spacing,
                lineSpacing = spacing,
                groupSpacing = spacing,
                groupLineSpacing = spacing,
                elementWidth = size,
                elementHeight = size,
                layoutIndex = index,
            })
        end
        state.hasGroups = true
    end

    if (showDispelBorder or showDispelGlow) and not state.hasDispelBorder then
        container:AddAuraSlot(DISPEL_BORDER_KEY, DISPELLABLE_FILTER, {
            initializeFrame = function(button)
                InitializeDispelBorderButton(frame, state, button)
            end,
        })
        state.hasDispelBorder = true
    end
end

-- Existing buttons are only accessible while auras are not secret. Debuff border
-- pieces are secret, so only the button size follows.
local function RestyleButtons(frame, state)
    local container = state.debuffs
    for _, group in ipairs(DEBUFF_GROUPS) do
        local size = GetGroupSize(frame, group)
        for index = 1, container:GetAuraGroupFrameCount(group.key) do
            container:GetAuraGroupFrame(group.key, index):SetSize(size, size)
        end
    end

    local size = GetDefensiveSize(frame)
    for _, button in ipairs(state.defensiveButtons) do
        button:SetSize(size, size)
        Auras.UpdateManagedBorder(button, size)
    end

    if state.dispelBorder then
        state.dispelBorder:SetShown(showDispelBorder)
        state.dispelGlow:SetShown(showDispelGlow)
    end
end

----------------------------------------------------------------------------------------
-- Private Auras
----------------------------------------------------------------------------------------
-- Private auras are part of Blizzard's debuff display, so they need their own anchors
-- while that display is off. Blizzard still draws them.
local function ClearPrivateAnchors(state)
    for index, anchorID in pairs(state.privateAnchorIDs) do
        C_UnitAuras.RemovePrivateAuraAnchor(anchorID)
        state.privateAnchorIDs[index] = nil
    end
    state.privateUnit = nil
end

local function SyncPrivateAnchors(frame, state, unit, size, spacing)
    if state.privateUnit == unit and state.privateSize == size then
        return
    end
    ClearPrivateAnchors(state)

    local borderScale = frame:GetDebuffBorderScale()
    for index = 1, PRIVATE_AURA_COUNT do
        local anchor = state.privateAnchors[index]
        if not anchor then
            anchor = CreateFrame("Frame", nil, frame)
            anchor:SetFrameLevel(frame.healthBar:GetFrameLevel() + PRIVATE_LEVEL_OFFSET)
            state.privateAnchors[index] = anchor
        end
        anchor:SetSize(size, size)
        anchor:ClearAllPoints()
        anchor:SetPoint("TOP", frame, "TOP", (index - (PRIVATE_AURA_COUNT + 1) / 2) * (size + spacing), -3)

        state.privateAnchorIDs[index] = C_UnitAuras.AddPrivateAuraAnchor({
            unitToken = unit,
            auraIndex = index,
            parent = anchor,
            showCooldownFrame = true,
            showCooldownEdge = false,
            showCountdownNumbers = false,
            showDispelIcon = false,
            isContainer = false,
            iconInfo = {
                iconAnchor = { point = "CENTER", relativeTo = anchor, relativePoint = "CENTER", offsetX = 0, offsetY = 0 },
                iconWidth = size,
                iconHeight = size,
                borderScale = borderScale,
            },
        })
    end
    state.privateUnit = unit
    state.privateSize = size
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
local function HideState(state)
    state.debuffs:Hide()
    state.defensive:Hide()
    ClearPrivateAnchors(state)
end

function P.UpdateCompactGroupDebuffs(frame)
    local unit = frame.displayedUnit
    local state = GetPartyData(frame).groupDebuffs
    if not unit or IsCompactPetUnitToken(unit) or not (showDebuffs or showDefensive or showDispelBorder or showDispelGlow) then
        if state then
            HideState(state)
        end
        return
    end

    state = state or EnsureState(frame)
    local spacing = Config.UnitFrames.Auras.CompactPartyRaidSpacing

    if showDefensive then
        state.defensive:SetUnit(unit)
        state.defensive:Show()

        local defensiveSize = GetDefensiveSize(frame)
        if state.defensiveSize ~= defensiveSize then
            state.defensiveSize = defensiveSize
            state.restylePending = true
        end

        if state.defensiveVersion ~= settingsVersion then
            state.defensiveVersion = settingsVersion
            for _, slot in ipairs(DEFENSIVE_SLOTS) do
                state.defensive:SetAuraSlotCandidateFilters(slot.key, defensiveCandidateFilters)
            end
        end
    else
        state.defensive:Hide()
    end

    if showDebuffs then
        SyncPrivateAnchors(frame, state, unit, GetBossDebuffSize(frame), spacing)
    else
        ClearPrivateAnchors(state)
    end

    if not (showDebuffs or showDispelBorder or showDispelGlow) then
        state.debuffs:Hide()
    else
        state.debuffs:SetUnit(unit)
        state.debuffs:Show()

        local organization = EditModeManagerFrame:GetRaidFrameAuraOrganizationType(frame.groupType)
        local size = GetDebuffSize(frame)
        local powerBarUsedHeight = frame:GetPowerBarUsedHeight()
        if state.organization ~= organization
            or state.size ~= size
            or state.spacing ~= spacing
            or state.powerBarUsedHeight ~= powerBarUsedHeight
            or state.version ~= settingsVersion then
            state.organization = organization
            state.size = size
            state.spacing = spacing
            state.powerBarUsedHeight = powerBarUsedHeight
            state.version = settingsVersion
            ApplyDebuffLayout(frame, state.debuffs, organization, size, spacing, powerBarUsedHeight)
            SyncDebuffGroups(frame, state, spacing)
            state.restylePending = true
        end
    end

    if state.restylePending and not C_Secrets.ShouldAurasBeSecret() then
        state.restylePending = nil
        RestyleButtons(frame, state)
    end
end

function P.IsGroupDebuffCVar(name)
    return name == DEBUFFS_CVAR or name == DEFENSIVE_CVAR
end

function UF.RefreshGroupDebuffs()
    local cfg = Config.UnitFrames.Auras
    if cfg.CompactPartyRaidLargerRoleDebuffs == nil then
        cfg.CompactPartyRaidLargerRoleDebuffs = C_CVar.GetCVarBool(LARGER_ROLE_DEBUFFS_CVAR)
    end
    if cfg.CompactPartyRaidOnlyDispellableDebuffs == nil then
        cfg.CompactPartyRaidOnlyDispellableDebuffs = C_CVar.GetCVarBool(DISPELLABLE_ONLY_CVAR)
    end

    local blizzardDebuffs = C_CVar.GetCVarBool(DEBUFFS_CVAR)
    showDebuffs = cfg.CompactPartyRaidShowDebuffs == true and not blizzardDebuffs
    showDefensive = not C_CVar.GetCVarBool(DEFENSIVE_CVAR)
    dispellableOnly = cfg.CompactPartyRaidOnlyDispellableDebuffs == true
    largerRoleDebuffs = cfg.CompactPartyRaidLargerRoleDebuffs == true
    showDispelBorder = cfg.CompactPartyRaidDispelBorder == true
    showDispelGlow = cfg.CompactPartyRaidDispelGlow == true

    if showDebuffsSetting then
        showDebuffsSetting.name = blizzardDebuffs and SHOW_DEBUFFS_PAUSED_LABEL or SHOW_DEBUFFS_LABEL
    end
    if blizzardDebuffs and cfg.CompactPartyRaidShowDebuffs and not blizzardDebuffsNoticeShown then
        blizzardDebuffsNoticeShown = true
        RefineUI:Print(BLIZZARD_DEBUFFS_NOTICE)
    end

    local excludeSpellIDs = wipe(defensiveCandidateFilters.excludeSpellIDs)
    for _, entry in ipairs(UF.GetGroupBuffEntries()) do
        for _, spellID in ipairs(entry.spellIDs) do
            excludeSpellIDs[spellID] = true
        end
    end

    settingsVersion = settingsVersion + 1
    ForEachCompactPartyRaidFrame(true, false, P.UpdateCompactGroupDebuffs)
end

function P.RegisterGroupDebuffEditModeSettings()
    local lib = RefineUI.LibEditMode
    if editModeSettingsRegistered or not lib or not lib.SettingType or type(lib.AddSystemSettings) ~= "function" then
        return
    end

    local function Checkbox(key, name, desc, default)
        return {
            kind = lib.SettingType.Checkbox,
            name = name,
            desc = desc,
            default = default,
            get = function()
                return Config.UnitFrames.Auras[key] == true
            end,
            set = function(_, value)
                Config.UnitFrames.Auras[key] = value and true or false
                UF.RefreshGroupDebuffs()
            end,
        }
    end

    showDebuffsSetting = Checkbox("CompactPartyRaidShowDebuffs", SHOW_DEBUFFS_LABEL,
        "Show RefineUI debuffs. Paused while Blizzard's Raid Frames \"Display Debuffs\" option is on.", true)
    showDebuffsSetting.name = C_CVar.GetCVarBool(DEBUFFS_CVAR) and SHOW_DEBUFFS_PAUSED_LABEL or SHOW_DEBUFFS_LABEL

    local settings = {
        showDebuffsSetting,
        Checkbox("CompactPartyRaidLargerRoleDebuffs", "Bigger Role Debuffs",
            "Show boss and role-specific debuffs larger.", true),
        Checkbox("CompactPartyRaidOnlyDispellableDebuffs", "Only Dispellable Debuffs",
            "Only show debuffs you can dispel, plus boss and priority debuffs.", false),
        Checkbox("CompactPartyRaidDispelBorder", "Dispel Border Color",
            "Color the frame border by the type of a debuff you can dispel.", true),
        Checkbox("CompactPartyRaidDispelGlow", "Dispel Glow",
            "Glow around the frame in the color of a debuff you can dispel.", true),
    }

    local indices = Enum.EditModeUnitFrameSystemIndices
    lib:AddSystemSettings(Enum.EditModeSystem.UnitFrame, settings, indices.Party)
    lib:AddSystemSettings(Enum.EditModeSystem.UnitFrame, settings, indices.Raid)
    editModeSettingsRegistered = true
end
