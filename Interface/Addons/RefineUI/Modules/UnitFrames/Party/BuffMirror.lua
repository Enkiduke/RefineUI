----------------------------------------------------------------------------------------
-- UnitFrames Party: Buff Mirror
-- Description: RefineUI-owned visual mirror for Compact Party/Raid buff icons.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local UnitFrames = RefineUI:GetModule("UnitFrames")
if not UnitFrames then
    return
end

local UF = UnitFrames
local P = UnitFrames:GetPrivate().Party
if not P then return end

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame
local CooldownFrame_Set = CooldownFrame_Set
local CooldownFrame_Clear = CooldownFrame_Clear
local InCombatLockdown = InCombatLockdown
local ipairs = ipairs
local pairs = pairs
local type = type
local floor = math.floor
local wipe = wipe

local GetPartyData = P.GetData
local GetPartyAuraData = P.GetAuraData
local GetSafeFrameLevel = P.GetSafeFrameLevel
local GetSafeFrameStrata = P.GetSafeFrameStrata
local TrySetFrameLevel = P.TrySetFrameLevel
local TrySetFrameStrata = P.TrySetFrameStrata
local IsUnreadableNumber = P.IsUnreadableNumber
local IsPartyRaidCompactFrame = P.IsCompactFrame

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local PARTY_BUFF_MIRROR_STATE_REGISTRY = "UnitFramesPartyBuffMirrorState"

local BUFF_MIRROR_REGULAR = "regular"
local BUFF_MIRROR_IMPORTANT = "important"

local REGULAR_CONTAINER_NAME = "RefineCompactBuffMirrorRegular"
local IMPORTANT_CONTAINER_NAME = "RefineCompactBuffMirrorImportant"

local regularSourcesScratch = {}
local importantSourcesScratch = {}

local BuffMirrorState = RefineUI:CreateDataRegistry(PARTY_BUFF_MIRROR_STATE_REGISTRY, "k")

local function WipeTable(tbl)
    if wipe then
        wipe(tbl)
        return tbl
    end

    for key in pairs(tbl) do
        tbl[key] = nil
    end
    return tbl
end

local function GetBuffMirrorState(frame)
    if not frame then
        return {}
    end

    local state = BuffMirrorState[frame]
    if not state then
        state = {}
        BuffMirrorState[frame] = state
    end
    return state
end

----------------------------------------------------------------------------------------
-- Gating
----------------------------------------------------------------------------------------
local function IsCompactBuffMirrorEnabled(frame)
    return frame
        and not frame:IsForbidden()
        and IsPartyRaidCompactFrame(frame)
        and type(frame.buffFrames) == "table"
end

local function IsNativeCompactRowBuff(frame, buffFrame)
    if not frame or not buffFrame or type(frame.buffFrames) ~= "table" then
        return false
    end

    for index = 1, #frame.buffFrames do
        if frame.buffFrames[index] == buffFrame then
            return true
        end
    end

    return false
end

----------------------------------------------------------------------------------------
-- Mirror Creation
----------------------------------------------------------------------------------------
local function CreateMirrorContainer(parent, debugName)
    local frame = CreateFrame("Frame", nil, parent)
    frame.debugName = debugName
    frame:SetSize(1, 1)
    frame:Hide()
    if frame.EnableMouse then
        frame:EnableMouse(false)
    end
    return frame
end

local function CreateMirrorButton(parent)
    local button = CreateFrame("Frame", nil, parent)
    button:SetSize(1, 1)
    button:Hide()
    if button.EnableMouse then
        button:EnableMouse(false)
    end

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button)
    button.icon = icon

    local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -1)
    count:SetJustifyH("RIGHT")
    count:SetJustifyV("BOTTOM")
    button.count = count

    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(button)
    if cooldown.SetReverse then
        cooldown:SetReverse(true)
    end
    if cooldown.SetHideCountdownNumbers then
        cooldown:SetHideCountdownNumbers(true)
    end
    if cooldown.GetCountdownFontString then
        local countdownText = cooldown:GetCountdownFontString()
        if countdownText and countdownText.Hide then
            countdownText:Hide()
        end
    end
    button.cooldown = cooldown

    return button
end

local function EnsureMirrorButtonPool(state, frame, kind, count)
    local containerKey = kind == BUFF_MIRROR_IMPORTANT and "importantContainer" or "regularContainer"
    local poolKey = kind == BUFF_MIRROR_IMPORTANT and "importantButtons" or "regularButtons"
    local container = state[containerKey]
    if not container then
        return nil
    end

    local buttons = state[poolKey]
    if type(buttons) ~= "table" then
        buttons = {}
        state[poolKey] = buttons
    end

    for index = #buttons + 1, count do
        buttons[index] = CreateMirrorButton(container)
    end

    return buttons
end

local function UpdateMirrorLayer(frame, container)
    if not frame or not container then
        return
    end

    TrySetFrameStrata(container, GetSafeFrameStrata(frame, "MEDIUM"))
    TrySetFrameLevel(container, GetSafeFrameLevel(frame, 0) + 40)
end

local function EnsureBuffMirrorForFrame(frame)
    if not IsCompactBuffMirrorEnabled(frame) then
        return nil
    end

    local state = GetBuffMirrorState(frame)
    if state.ready then
        UpdateMirrorLayer(frame, state.regularContainer)
        UpdateMirrorLayer(frame, state.importantContainer)
        return state
    end

    if InCombatLockdown() then
        state.pendingCreate = true
        return nil
    end

    if not state.regularContainer then
        state.regularContainer = CreateMirrorContainer(frame, REGULAR_CONTAINER_NAME)
    end
    if not state.importantContainer then
        state.importantContainer = CreateMirrorContainer(frame, IMPORTANT_CONTAINER_NAME)
    end

    UpdateMirrorLayer(frame, state.regularContainer)
    UpdateMirrorLayer(frame, state.importantContainer)

    local maxBuffs = type(frame.maxBuffs) == "number" and frame.maxBuffs or 0
    EnsureMirrorButtonPool(state, frame, BUFF_MIRROR_REGULAR, maxBuffs)
    EnsureMirrorButtonPool(state, frame, BUFF_MIRROR_IMPORTANT, maxBuffs)

    state.pendingCreate = nil
    state.ready = true
    return state
end

----------------------------------------------------------------------------------------
-- Native Buff Suppression
----------------------------------------------------------------------------------------
local function SetTextureAlpha(texture, alpha)
    if texture and texture.SetAlpha then
        texture:SetAlpha(alpha)
    end
end

local function SetCompactNativeBuffVisualSuppressed(buffFrame, suppressed)
    if not buffFrame then
        return
    end

    local auraData = GetPartyAuraData(buffFrame)
    local alpha = suppressed and 0 or 1

    SetTextureAlpha(buffFrame.icon, alpha)
    SetTextureAlpha(buffFrame.Icon, alpha)

    if buffFrame.count and buffFrame.count.SetAlpha then
        buffFrame.count:SetAlpha(alpha)
    end

    local cooldown = buffFrame.cooldown or buffFrame.Cooldown
    if cooldown and cooldown.SetAlpha then
        cooldown:SetAlpha(alpha)
    end

    local blizzardBorder = buffFrame.border or buffFrame.DebuffBorder
    SetTextureAlpha(blizzardBorder, alpha)

    if suppressed then
        if type(P.HideCompactAuraBorder) == "function" then
            P.HideCompactAuraBorder(buffFrame)
        end
    elseif auraData.classBuffEntryKey and type(P.ApplyCompactBuffBorderColor) == "function" then
        P.ApplyCompactBuffBorderColor(buffFrame)
    end

    auraData.nativeBuffVisualSuppressed = suppressed and true or nil
end

local function RestoreCompactNativeBuffVisuals(frame)
    if not frame or type(frame.buffFrames) ~= "table" then
        return
    end

    for _, buffFrame in ipairs(frame.buffFrames) do
        SetCompactNativeBuffVisualSuppressed(buffFrame, false)
    end
end

----------------------------------------------------------------------------------------
-- Mirror Source Collection
----------------------------------------------------------------------------------------
local function GetSourceCountText(buffFrame)
    if not buffFrame or not buffFrame.count then
        return nil
    end
    if not buffFrame.count.IsShown or not buffFrame.count:IsShown() then
        return nil
    end
    if buffFrame.count.GetText then
        local text = buffFrame.count:GetText()
        if type(text) == "string" and text ~= "" then
            return text
        end
    end
    return nil
end

local function CollectShownBuffSources(frame, regularSources, importantSources)
    local regular = WipeTable(regularSources)
    local important = WipeTable(importantSources)

    if not frame or type(frame.buffFrames) ~= "table" then
        return regular, important
    end

    for _, buffFrame in ipairs(frame.buffFrames) do
        if buffFrame and buffFrame:IsShown() then
            local auraData = GetPartyAuraData(buffFrame)
            local settings = nil
            if auraData.classBuffEntryKey then
                settings = P.GetTrackedClassBuffSettings(auraData.classBuffEntryKey)
            end

            if settings and settings.Important == true then
                important[#important + 1] = buffFrame
            else
                regular[#regular + 1] = buffFrame
            end
        end
    end

    if #important > 1 then
        local mode = P.GetTrackedClassBuffSortMode()
        local sortMode = P.IMPORTANT_SORT_MODE
        local descending = mode == sortMode and sortMode.DESCENDING or false
        if mode == sortMode.ASCENDING or mode == sortMode.DESCENDING then
            table.sort(important, function(a, b)
                local remainingA = P.GetAuraRemainingSecondsFromData(GetPartyAuraData(a))
                local remainingB = P.GetAuraRemainingSecondsFromData(GetPartyAuraData(b))

                if remainingA == nil and remainingB == nil then
                    return P.GetTrackedClassBuffManualOrderRank(GetPartyAuraData(a).classBuffEntryKey) < P.GetTrackedClassBuffManualOrderRank(GetPartyAuraData(b).classBuffEntryKey)
                elseif remainingA == nil then
                    return false
                elseif remainingB == nil then
                    return true
                elseif remainingA == remainingB then
                    return P.GetTrackedClassBuffManualOrderRank(GetPartyAuraData(a).classBuffEntryKey) < P.GetTrackedClassBuffManualOrderRank(GetPartyAuraData(b).classBuffEntryKey)
                elseif descending then
                    return remainingA > remainingB
                end

                return remainingA < remainingB
            end)
        else
            table.sort(important, function(a, b)
                local rankA = P.GetTrackedClassBuffManualOrderRank(GetPartyAuraData(a).classBuffEntryKey)
                local rankB = P.GetTrackedClassBuffManualOrderRank(GetPartyAuraData(b).classBuffEntryKey)
                if rankA ~= rankB then
                    return rankA < rankB
                end

                local spellA = GetPartyAuraData(a).auraSpellID or 0
                local spellB = GetPartyAuraData(b).auraSpellID or 0
                return spellA < spellB
            end)
        end
    end

    return regular, important
end

----------------------------------------------------------------------------------------
-- Mirror Rendering
----------------------------------------------------------------------------------------
local function SyncMirrorButtonFont(button, sourceFrame)
    local sourceCount = sourceFrame and sourceFrame.count
    if not button or not button.count or not sourceCount or not sourceCount.GetFont then
        return
    end

    local fontName, fontSize, fontFlags = sourceCount:GetFont()
    if fontName and fontSize then
        button.count:SetFont(fontName, fontSize, fontFlags)
    end
    if sourceCount.GetTextColor then
        local r, g, b, a = sourceCount:GetTextColor()
        button.count:SetTextColor(r or 1, g or 1, b or 1, a or 1)
    end
end

local function ApplyMirrorButtonCooldown(frame, button, sourceData)
    if not frame or not button or not button.cooldown then
        return
    end

    local cooldown = button.cooldown
    local auraAPI = _G.C_UnitAuras
    local getAuraDuration = auraAPI and auraAPI.GetAuraDuration
    local auraInstanceID = sourceData and sourceData.auraInstanceID
    local unit = frame.displayedUnit or frame.unit

    if type(getAuraDuration) == "function"
        and type(unit) == "string"
        and auraInstanceID ~= nil
        and cooldown.SetCooldownFromDurationObject then
        local ok, durationObject = pcall(getAuraDuration, unit, auraInstanceID)
        if ok and durationObject then
            cooldown:SetCooldownFromDurationObject(durationObject)
            return
        end
    end

    local expirationTime = sourceData and sourceData.auraExpirationTime
    local duration = sourceData and sourceData.auraDuration
    if type(expirationTime) == "number"
        and type(duration) == "number"
        and expirationTime > 0
        and not IsUnreadableNumber(expirationTime)
        and not IsUnreadableNumber(duration) then
        CooldownFrame_Set(cooldown, expirationTime - duration, duration, true)
        return
    end

    CooldownFrame_Clear(cooldown)
end

local function ConfigureMirrorButton(frame, button, sourceFrame)
    if not frame or not button or not sourceFrame then
        return
    end

    local sourceData = GetPartyAuraData(sourceFrame)
    local mirrorData = GetPartyAuraData(button)
    local size = sourceFrame:GetWidth() or 0
    if size <= 0 then
        size = sourceFrame:GetHeight() or 0
    end
    if size <= 0 then
        size = 16
    end

    button:SetSize(size, size)

    if button.icon and sourceFrame.icon and sourceFrame.icon.GetTexture then
        button.icon:SetTexture(sourceFrame.icon:GetTexture())
        if sourceFrame.icon.GetTexCoord and button.icon.SetTexCoord then
            button.icon:SetTexCoord(sourceFrame.icon:GetTexCoord())
        end
        if sourceFrame.icon.GetVertexColor and button.icon.SetVertexColor then
            button.icon:SetVertexColor(sourceFrame.icon:GetVertexColor())
        end
        button.icon:SetAlpha(1)
    end

    local countText = GetSourceCountText(sourceFrame)
    if countText then
        button.count:SetText(countText)
        button.count:Show()
    else
        button.count:Hide()
        button.count:SetText(nil)
    end
    SyncMirrorButtonFont(button, sourceFrame)

    mirrorData.auraInstanceID = sourceData.auraInstanceID
    mirrorData.auraSpellID = sourceData.auraSpellID
    mirrorData.auraDuration = sourceData.auraDuration
    mirrorData.auraExpirationTime = sourceData.auraExpirationTime
    mirrorData.classBuffEntryKey = sourceData.classBuffEntryKey

    ApplyMirrorButtonCooldown(frame, button, sourceData)
    P.ApplyCompactBuffBorderColor(button)
    button:Show()
end

local function HideMirrorButtons(buttons, startingIndex)
    if type(buttons) ~= "table" then
        return
    end

    for index = startingIndex or 1, #buttons do
        local button = buttons[index]
        if button then
            button:Hide()
        end
    end
end

local function LayoutMirrorContainer(frame, container, point, relativeTo, relativePoint, x, y)
    if not frame or not container or type(point) ~= "string" or not relativeTo then
        return false
    end

    container:ClearAllPoints()
    container:SetPoint(point, relativeTo, relativePoint, x or 0, y or 0)
    UpdateMirrorLayer(frame, container)
    container:Show()
    return true
end

local function LayoutMirrorButtons(buttons, sourceFrames, layoutAnchorPoint, spacing, direction)
    if type(buttons) ~= "table" or type(sourceFrames) ~= "table" then
        return
    end

    local dirX = direction and type(direction.x) == "number" and direction.x or 0
    local dirY = direction and type(direction.y) == "number" and direction.y or 0
    local stride = direction and direction.stride or nil
    stride = type(stride) == "number" and stride or nil

    for index = 1, #sourceFrames do
        local button = buttons[index]
        local sourceFrame = sourceFrames[index]
        if button and sourceFrame then
            local width = button:GetWidth() or 0
            local height = button:GetHeight() or width
            local col
            local row

            if stride and stride > 1 then
                col = (index - 1) % stride
                row = floor((index - 1) / stride)
            else
                col = index - 1
                row = 0
            end

            local offsetX = col * ((width > 0 and width or 0) + spacing) * dirX
            local offsetY = row * ((height > 0 and height or 0) + spacing) * dirY

            button:ClearAllPoints()
            button:SetPoint(layoutAnchorPoint, button:GetParent(), layoutAnchorPoint, offsetX, offsetY)
        end
    end
end

local function RenderBuffMirrorGroup(frame, state, kind, sourceFrames, anchorPoint, relativeTo, relativePoint, x, y, layoutSpec)
    local container = kind == BUFF_MIRROR_IMPORTANT and state.importantContainer or state.regularContainer
    local buttons = kind == BUFF_MIRROR_IMPORTANT and state.importantButtons or state.regularButtons
    if not container or type(buttons) ~= "table" then
        return
    end

    if #sourceFrames == 0 then
        container:Hide()
        HideMirrorButtons(buttons, 1)
        return
    end

    if not LayoutMirrorContainer(frame, container, anchorPoint, relativeTo, relativePoint, x, y) then
        container:Hide()
        HideMirrorButtons(buttons, 1)
        return
    end

    for index = 1, #sourceFrames do
        ConfigureMirrorButton(frame, buttons[index], sourceFrames[index])
    end

    local spacing = P.GetCompactAuraIconSpacing()
    local direction = layoutSpec and layoutSpec.direction or nil
    if kind == BUFF_MIRROR_IMPORTANT then
        direction = { x = -1, y = -1, stride = layoutSpec and layoutSpec.stride or 3 }
        LayoutMirrorButtons(buttons, sourceFrames, "TOPRIGHT", spacing, direction)
    else
        direction = {
            x = direction and direction.x or -1,
            y = direction and direction.y or -1,
            stride = layoutSpec and layoutSpec.stride or 3,
        }
        LayoutMirrorButtons(buttons, sourceFrames, anchorPoint, spacing, direction)
    end

    HideMirrorButtons(buttons, #sourceFrames + 1)
end

local function HideCompactBuffMirror(frame)
    local state = GetBuffMirrorState(frame)
    if state.regularContainer then
        state.regularContainer:Hide()
    end
    if state.importantContainer then
        state.importantContainer:Hide()
    end
    HideMirrorButtons(state.regularButtons, 1)
    HideMirrorButtons(state.importantButtons, 1)
end

local function UpdateCompactBuffMirrorForFrame(frame)
    if not IsCompactBuffMirrorEnabled(frame) then
        return
    end

    local state = EnsureBuffMirrorForFrame(frame)
    if not state then
        RestoreCompactNativeBuffVisuals(frame)
        HideCompactBuffMirror(frame)
        return
    end

    local regularSources, importantSources = CollectShownBuffSources(frame, regularSourcesScratch, importantSourcesScratch)
    local layoutSpec = P.GetCompactAuraLayoutSpec(frame, P.COMPACT_AURA_CONTAINER_BUFF)
    local point, relativeTo, relativePoint, x, y = P.GetCompactAuraAnchorPoint(frame, P.COMPACT_AURA_CONTAINER_BUFF)
    local importantAnchor = P.EnsureCompactImportantBuffAnchor(frame)

    if type(point) ~= "string" or not relativeTo then
        RestoreCompactNativeBuffVisuals(frame)
        HideCompactBuffMirror(frame)
        return
    end
    if #importantSources > 0 and not importantAnchor then
        RestoreCompactNativeBuffVisuals(frame)
        HideCompactBuffMirror(frame)
        return
    end

    RenderBuffMirrorGroup(frame, state, BUFF_MIRROR_REGULAR, regularSources, point, relativeTo, relativePoint, x, y, layoutSpec)
    if importantAnchor then
        RenderBuffMirrorGroup(frame, state, BUFF_MIRROR_IMPORTANT, importantSources, "TOPRIGHT", importantAnchor, "TOPRIGHT", 0, 0, layoutSpec)
    else
        HideMirrorButtons(state.importantButtons, 1)
        if state.importantContainer then
            state.importantContainer:Hide()
        end
    end

    for _, buffFrame in ipairs(frame.buffFrames) do
        if buffFrame and buffFrame:IsShown() then
            SetCompactNativeBuffVisualSuppressed(buffFrame, true)
        else
            SetCompactNativeBuffVisualSuppressed(buffFrame, false)
        end
    end
end

local function InvalidateCompactBuffMirror(frame)
    if not frame then
        return
    end

    HideCompactBuffMirror(frame)
    RestoreCompactNativeBuffVisuals(frame)

    local state = GetBuffMirrorState(frame)
    state.lastToken = nil
end

----------------------------------------------------------------------------------------
-- Shared Internal Exports
----------------------------------------------------------------------------------------
P.IsCompactBuffMirrorEnabled = IsCompactBuffMirrorEnabled
P.IsNativeCompactRowBuff = IsNativeCompactRowBuff
P.EnsureCompactBuffMirrorForFrame = EnsureBuffMirrorForFrame
P.UpdateCompactBuffMirrorForFrame = UpdateCompactBuffMirrorForFrame
P.HideCompactBuffMirror = HideCompactBuffMirror
P.InvalidateCompactBuffMirror = InvalidateCompactBuffMirror
P.SetCompactNativeBuffVisualSuppressed = SetCompactNativeBuffVisualSuppressed
