----------------------------------------------------------------------------------------
-- UnitFrames Party: Group Buffs
-- Description: RefineUI-styled tracked buffs on Compact Party/Raid frames. 12.1 draws
--              Blizzard's raid-frame auras in a secure environment, so listed spells
--              are hidden there and drawn here with CustomAuraContainers.
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
local InCombatLockdown = InCombatLockdown
local ipairs = ipairs
local huge = math.huge

local GetPartyData = P.GetData
local IsCompactPetUnitToken = P.IsPetUnit
local ForEachCompactPartyRaidFrame = P.ForEachRaidFrame

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local SECTION = UF.GROUP_BUFF_SECTION
local CONTAINER_LEVEL_OFFSET = 6
local COOLDOWN_OFFSET_X = 0
local COOLDOWN_OFFSET_Y = 0.5
local COOLDOWN_SWIPE_ALPHA = 0.8
local ICON_SIZE_BONUS = 2
local COOLDOWN_LEVEL_OFFSET = 50
local FRAME_COLOR_INSET = 6
local ORGANIZATION = Enum.RaidAuraOrganizationType

local settingsVersion = 1
local cachedEntries
local spellIDSets = {}
local colorScratch = {}
local buffFilter

----------------------------------------------------------------------------------------
-- Data Helpers
----------------------------------------------------------------------------------------
local function GetEntries()
    if not cachedEntries then
        cachedEntries = UF.GetGroupBuffEntries()
    end
    return cachedEntries
end

local function GetSpellIDSet(entry)
    local set = spellIDSets[entry.key]
    if not set then
        set = {}
        for _, spellID in ipairs(entry.spellIDs) do
            set[spellID] = true
        end
        spellIDSets[entry.key] = set
    end
    return set
end

local function GetBuffFilter()
    if not buffFilter then
        buffFilter = AuraUtil.CreateFilterString(AuraUtil.AuraFilters.Helpful, AuraUtil.AuraFilters.Player)
    end
    return buffFilter
end

local function GetBorderColorTable(entry)
    colorScratch[1], colorScratch[2], colorScratch[3], colorScratch[4] = UF.GetGroupBuffBorderColor(entry)
    return colorScratch
end

----------------------------------------------------------------------------------------
-- Aura Buttons
----------------------------------------------------------------------------------------
-- Aura buttons are restricted after creation, so all styling happens here.
local function StyleAuraButton(button, size)
    button:SetSize(size, size)
    button:EnableMouse(false)

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetAllPoints(button)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button:SetIcon(icon)

    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetPoint("TOPLEFT", button, "TOPLEFT", -COOLDOWN_OFFSET_X, COOLDOWN_OFFSET_Y)
    cooldown:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", COOLDOWN_OFFSET_X, -COOLDOWN_OFFSET_Y)
    cooldown:SetDrawEdge(false)
    cooldown:SetDrawBling(false)
    cooldown:SetSwipeColor(0, 0, 0, COOLDOWN_SWIPE_ALPHA)
    cooldown:SetSwipeTexture(RefineUI.Media.Textures.CooldownSwipeSmall)
    cooldown:SetReverse(true)
    cooldown:SetHideCountdownNumbers(true)
    cooldown:SetFrameLevel(button:GetFrameLevel() + COOLDOWN_LEVEL_OFFSET)
    button:SetDurationCooldown(cooldown)

    local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
    button:SetApplicationCount(count)

    Auras.CreateManagedBorder(button)
    Auras.UpdateManagedBorder(button, size)
end

local function InitializeBuffButton(frame, entry, button)
    StyleAuraButton(button, frame:GetBuffAuraSize() + ICON_SIZE_BONUS)
    Auras.SetManagedBorderColor(button, GetBorderColorTable(entry))
end

local function InitializeFrameColorButton(frame, entry, state, button)
    button:EnableMouse(false)
    button:SetAllPoints(GetPartyData(frame).healthBarBorderHost or frame)

    local host = CreateFrame("Frame", nil, button)
    host:SetAllPoints(button)
    local border = RefineUI.CreateBorder(host, FRAME_COLOR_INSET, FRAME_COLOR_INSET, RefineUI:Scale(12))
    border:SetBackdropBorderColor(UF.GetGroupBuffBorderColor(entry))
    state.frameColorBorders[entry.key] = border
end

----------------------------------------------------------------------------------------
-- Containers
----------------------------------------------------------------------------------------
local function CreateContainer(frame)
    local container = CreateFrame("AuraContainer", nil, frame, "CustomAuraContainerTemplate")
    container:SetFrameLevel(frame.healthBar:GetFrameLevel() + CONTAINER_LEVEL_OFFSET)
    container:EnableMouse(false)
    return container
end

local function EnsureState(frame)
    local data = GetPartyData(frame)
    local state = data.groupBuffs
    if not state then
        state = {
            important = CreateContainer(frame),
            tracked = CreateContainer(frame),
            importantGroups = {},
            trackedGroups = {},
            frameColorSlots = {},
            frameColorBorders = {},
        }
        data.groupBuffs = state
    end
    return state
end

local function SetFlow(container, anchorPoint, verticalDirection, stride, size, spacing)
    container:SetFlowLayoutAnchorPoint(anchorPoint)
    container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Left, verticalDirection)
    container:SetFlowLayoutMaximumLineSize(stride * size + (stride - 1) * spacing)
end

-- Matches Blizzard's buff placement per Edit Mode aura organization; Important keeps
-- the previous RefineUI anchor.
local function ApplyContainerLayout(frame, state, organization, size, spacing, powerBarUsedHeight)
    local important, tracked = state.important, state.tracked
    local buffsOnTop = organization == ORGANIZATION.BuffsTopDebuffsBottom
    local stride = buffsOnTop and 6 or 3

    important:ClearAllPoints()
    if organization == ORGANIZATION.Legacy then
        important:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -3, 4 + powerBarUsedHeight)
    else
        important:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)
    end
    SetFlow(important, "TOPRIGHT", AnchorUtil.FlowDirection.Down, stride, size, spacing)

    tracked:ClearAllPoints()
    if buffsOnTop then
        tracked:SetPoint("TOPRIGHT", important, "BOTTOMRIGHT", 0, -spacing)
        SetFlow(tracked, "TOPRIGHT", AnchorUtil.FlowDirection.Down, stride, size, spacing)
    else
        tracked:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 2 + powerBarUsedHeight)
        SetFlow(tracked, "BOTTOMRIGHT", AnchorUtil.FlowDirection.Up, stride, size, spacing)
    end
end

local function SyncGroup(frame, container, groups, entry, active, layoutIndex, size, spacing)
    if not active then
        if groups[entry.key] then
            container:SetAuraGroupMaxFrameCount(entry.key, 0)
        end
        return
    end

    if groups[entry.key] then
        container:SetAuraGroupMaxFrameCount(entry.key, huge)
    else
        container:AddAuraGroup(entry.key, GetBuffFilter(), {
            candidateFilters = { includeSpellIDs = GetSpellIDSet(entry) },
            initializeFrame = function(button)
                InitializeBuffButton(frame, entry, button)
            end,
        })
        groups[entry.key] = true
    end

    container:SetAuraGroupLayout(entry.key, {
        elementSpacing = spacing,
        lineSpacing = spacing,
        groupSpacing = spacing,
        groupLineSpacing = spacing,
        elementWidth = size,
        elementHeight = size,
        layoutIndex = layoutIndex,
    })
end

local function SyncFrameColorSlot(frame, state, entry, active)
    local container = state.tracked
    if state.frameColorSlots[entry.key] then
        container:SetAuraSlotCandidateFilters(entry.key, { includeSpellIDs = active and GetSpellIDSet(entry) or {} })
    elseif active then
        container:AddAuraSlot(entry.key, GetBuffFilter(), {
            candidateFilters = { includeSpellIDs = GetSpellIDSet(entry) },
            initializeFrame = function(button)
                InitializeFrameColorButton(frame, entry, state, button)
            end,
        })
        state.frameColorSlots[entry.key] = true
    end
end

local function SyncGroups(frame, state, size, spacing)
    for index, entry in ipairs(GetEntries()) do
        local section = UF.GetGroupBuffSection(entry)
        SyncGroup(frame, state.important, state.importantGroups, entry, section == SECTION.IMPORTANT, index, size, spacing)
        SyncGroup(frame, state.tracked, state.trackedGroups, entry, section == SECTION.TRACKED, index, size, spacing)
        SyncFrameColorSlot(frame, state, entry, section ~= SECTION.UNTRACKED and UF.IsGroupBuffFrameColor(entry))
    end
end

local function RestyleGroup(container, groups, key, size, color)
    if not groups[key] then
        return
    end
    for index = 1, container:GetAuraGroupFrameCount(key) do
        local button = container:GetAuraGroupFrame(key, index)
        button:SetSize(size, size)
        Auras.UpdateManagedBorder(button, size)
        Auras.SetManagedBorderColor(button, color)
    end
end

-- Existing buttons are only accessible while auras are not secret.
local function RestyleButtons(state, size)
    for _, entry in ipairs(GetEntries()) do
        local color = GetBorderColorTable(entry)
        RestyleGroup(state.important, state.importantGroups, entry.key, size, color)
        RestyleGroup(state.tracked, state.trackedGroups, entry.key, size, color)

        local frameColorBorder = state.frameColorBorders[entry.key]
        if frameColorBorder then
            frameColorBorder:SetBackdropBorderColor(color[1], color[2], color[3], color[4])
        end
    end
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
P.StyleCompactAuraButton = StyleAuraButton
P.CreateCompactAuraContainer = CreateContainer

function P.UpdateCompactGroupBuffs(frame)
    local unit = frame.displayedUnit
    local state = GetPartyData(frame).groupBuffs
    if not unit or IsCompactPetUnitToken(unit) then
        if state then
            state.important:Hide()
            state.tracked:Hide()
        end
        return
    end

    state = state or EnsureState(frame)
    state.important:SetUnit(unit)
    state.tracked:SetUnit(unit)
    state.important:Show()
    state.tracked:Show()

    local organization = EditModeManagerFrame:GetRaidFrameAuraOrganizationType(frame.groupType)
    local size = frame:GetBuffAuraSize() + ICON_SIZE_BONUS
    local spacing = Config.UnitFrames.Auras.CompactPartyRaidSpacing
    local powerBarUsedHeight = frame:GetPowerBarUsedHeight()

    local layoutChanged = state.organization ~= organization
        or state.size ~= size
        or state.spacing ~= spacing
        or state.powerBarUsedHeight ~= powerBarUsedHeight
    if layoutChanged then
        state.organization = organization
        state.powerBarUsedHeight = powerBarUsedHeight
        ApplyContainerLayout(frame, state, organization, size, spacing, powerBarUsedHeight)
    end

    if layoutChanged or state.version ~= settingsVersion then
        state.version = settingsVersion
        state.size = size
        state.spacing = spacing
        SyncGroups(frame, state, size, spacing)
        state.restylePending = true
    end

    if state.restylePending and not C_Secrets.ShouldAurasBeSecret() then
        state.restylePending = nil
        RestyleButtons(state, size)
    end
end

-- Blizzard would otherwise draw listed spells a second time (or, when Untracked, at all).
function P.ApplyGroupBuffHiddenList()
    if InCombatLockdown() then
        P.groupBuffHiddenListPending = true
        return
    end
    P.groupBuffHiddenListPending = nil

    local spellIDs = {}
    for _, entry in ipairs(GetEntries()) do
        for _, spellID in ipairs(entry.spellIDs) do
            spellIDs[#spellIDs + 1] = spellID
        end
    end
    C_UnitAuras.SetHiddenGroupBuffs(spellIDs)
end

-- Frames depend only on the ordered entry keys plus saved settings.
local function GetEntriesSignature(entries)
    local parts = {}
    for index, entry in ipairs(entries) do
        parts[index] = entry.hideByDefault and (entry.key .. "!") or entry.key
    end
    return table.concat(parts, ",")
end

-- onlyIfEntriesChanged: Cooldown Manager data changes (e.g. SPELLS_CHANGED in combat)
-- rarely change the entries, and a rebuild marks every button for restyle, which then
-- all lands on the combat-end frame. The hidden list is always re-pushed.
function UF.RefreshGroupBuffs(onlyIfEntriesChanged)
    local previousSignature = onlyIfEntriesChanged and cachedEntries and GetEntriesSignature(cachedEntries)
    cachedEntries = nil
    P.ApplyGroupBuffHiddenList()
    if previousSignature and previousSignature == GetEntriesSignature(GetEntries()) then
        return
    end
    settingsVersion = settingsVersion + 1
    ForEachCompactPartyRaidFrame(true, false, P.UpdateCompactGroupBuffs)
    -- The center big defensive skips spells listed here.
    UF.RefreshGroupDebuffs()
end
