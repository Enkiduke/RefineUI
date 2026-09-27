----------------------------------------------------------------------------------------
-- Nameplates Component: TextAndTitles
-- Description: Name/health text updates and NPC title extraction/rendering.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local Nameplates = RefineUI:GetModule("Nameplates")
if not Nameplates then
    return
end

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local type = type
local tostring = tostring
local pairs = pairs
local ipairs = ipairs
local pcall = pcall
local strfind = string.find
local strmatch = string.match
local strgsub = string.gsub
local strsub = string.sub
local wipe = table.wipe
local tinsert = table.insert

local UnitHealthPercent = UnitHealthPercent
local UnitIsPlayer = UnitIsPlayer
local UnitIsFriend = UnitIsFriend
local UnitGUID = UnitGUID
local UnitAffectingCombat = UnitAffectingCombat
local IsInInstance = IsInInstance
local C_TooltipInfo = C_TooltipInfo
local C_NamePlate = C_NamePlate
local TOOLTIP_UNIT_LEVEL = TOOLTIP_UNIT_LEVEL

local EMPTY_TEXT_OPTS = {
    emptyText = "",
}

----------------------------------------------------------------------------------------
-- Locals
----------------------------------------------------------------------------------------
local Private = Nameplates:GetPrivate()
local Util = Private.Util
local Runtime = Private.Runtime
local Constants = Private.Constants
local ActiveNameplates = Private.ActiveNameplates
local NameplateData = RefineUI.NameplateData
local IsNameOnly = Util.IsNameOnly
local HEALTH_BAR_TEXTURE = Private.Textures.HEALTH_BAR

local function GetCacheableUnitGUID(unit)
    local guid = UnitGUID(unit)

    -- Protected NPCs can return a secret value whose type is still "string".
    -- Gate it before any comparison or table indexing.
    if not Util.IsAccessibleValue(guid) or type(guid) ~= "string" or guid == "" then
        return nil
    end

    return guid
end

local function GetNativeNameSource(unitFrame)
    return unitFrame.name or (unitFrame.NameContainer and unitFrame.NameContainer.Name)
end

local function IsNpcTitleFeatureEnabled()
    return Nameplates:GetConfiguredNameplatesConfig().ShowNPCTitles ~= false
end

local function ShouldSuppressNpcTitleScanning()
    return Util.ReadSafeBoolean(UnitAffectingCombat("player")) == true or IsInInstance() == true
end

local function TrimTooltipLineText(text)
    if type(text) ~= "string" or not Util.IsAccessibleValue(text) then
        return nil
    end

    local trimmed = strmatch(text, "^%s*(.-)%s*$")
    if trimmed == "" then
        return nil
    end

    return trimmed
end

local function NormalizeNpcTitleText(text)
    local normalized = TrimTooltipLineText(text)
    if normalized and strsub(normalized, 1, 1) == "<" and strsub(normalized, -1) == ">" then
        normalized = TrimTooltipLineText(strsub(normalized, 2, -2))
    end

    return normalized
end

local function IsEligibleNpcTitleUnit(unit, data)
    local isPlayerUnit
    if data.isPlayer ~= nil then
        isPlayerUnit = data.isPlayer == true
    else
        isPlayerUnit = Util.ReadSafeBoolean(UnitIsPlayer(unit)) == true
    end

    if isPlayerUnit then
        return false
    end

    return Util.ReadSafeBoolean(UnitIsFriend("player", unit)) == true
end

local function EnsureNpcTitleFontString(unitFrame, data)
    if not data.RefineName then
        return nil
    end

    if not data.RefineNpcTitle then
        data.RefineNpcTitle = unitFrame:CreateFontString(nil, "OVERLAY")
        RefineUI.Font(data.RefineNpcTitle, Constants.NPC_TITLE_FONT_SIZE, nil, "OUTLINE")
        data.RefineNpcTitle:SetTextColor(Constants.NPC_TITLE_COLOR[1], Constants.NPC_TITLE_COLOR[2], Constants.NPC_TITLE_COLOR[3])
        data.RefineNpcTitle:SetJustifyH("CENTER")
        data.RefineNpcTitle:SetJustifyV("MIDDLE")
        data.RefineNpcTitle:Hide()
    end

    if data.RefineNpcTitleAnchor ~= data.RefineName then
        data.RefineNpcTitle:ClearAllPoints()
        RefineUI.Point(data.RefineNpcTitle, "TOP", data.RefineName, "BOTTOM", 0, -1)
        data.RefineNpcTitleAnchor = data.RefineName
    end

    return data.RefineNpcTitle
end

local function BuildUnitLevelPattern()
    if Runtime.unitLevelPattern ~= nil then
        return Runtime.unitLevelPattern
    end

    if type(TOOLTIP_UNIT_LEVEL) ~= "string" or not Util.IsAccessibleValue(TOOLTIP_UNIT_LEVEL) then
        return nil
    end

    local escaped = strgsub(TOOLTIP_UNIT_LEVEL, "([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    escaped = strgsub(escaped, "%%%%s", ".+")
    escaped = strgsub(escaped, "%%%%d", "%%d+")

    Runtime.unitLevelPattern = "^" .. escaped
    return Runtime.unitLevelPattern
end

local function IsTooltipLevelLine(text)
    local pattern = BuildUnitLevelPattern()
    return pattern ~= nil and strfind(text, pattern) ~= nil
end

local function GetTooltipLineText(line)
    if not line or not Util.IsAccessibleValue(line) then
        return nil
    end

    return TrimTooltipLineText(Util.SafeTableIndex(line, "leftText"))
        or TrimTooltipLineText(Util.SafeTableIndex(line, "text"))
end

local function ExtractNpcTitleFromTooltipData(tooltipData)
    if not Util.IsAccessibleValue(tooltipData) then
        return nil
    end

    local lines = Util.SafeTableIndex(tooltipData, "lines")
    if type(lines) ~= "table" or not Util.IsAccessibleValue(lines) then
        return nil
    end

    local nameLineIndex = nil
    for i, line in ipairs(lines) do
        if Util.SafeTableIndex(line, "type") == Constants.TOOLTIP_LINE_TYPE_UNIT_NAME then
            nameLineIndex = i
            break
        end
    end

    if not nameLineIndex then
        return nil
    end

    local candidate = nil
    for i = nameLineIndex + 1, #lines do
        local text = GetTooltipLineText(lines[i])
        if text then
            if IsTooltipLevelLine(text) then
                return NormalizeNpcTitleText(candidate)
            end
            candidate = text
        end
    end

    return nil
end

-- Returns title, isResolved. Unresolved means tooltip data was not ready yet.
local function ResolveNpcTitle(unit, cacheGUID)
    local ok, tooltipData = pcall(C_TooltipInfo.GetUnit, unit)
    if not ok then
        return nil, true
    end
    if tooltipData == nil then
        return nil, false
    end

    local title = ExtractNpcTitleFromTooltipData(tooltipData)
    if cacheGUID then
        Runtime.npcTitleCacheByGUID[cacheGUID] = title or false
    end

    return title, true
end

local function NormalizeNameText(text, unit)
    if Util.IsUsableUnitToken(unit) and Util.ReadSafeBoolean(UnitIsPlayer(unit)) == true then
        text = text:gsub(" %(*.*%)", ""):gsub("%-.*", "")
    end

    return text
end

local function SetRegionShownIfChanged(region, shouldShow)
    if region:IsShown() == shouldShow then
        return false
    end

    region:SetShown(shouldShow)
    return true
end

function Nameplates:IsNativeNameShown(unitFrame, nameSource)
    local nativeName = nameSource or GetNativeNameSource(unitFrame)
    return nativeName ~= nil and nativeName:IsShown() == true
end

function Nameplates:ApplyRefineTextVisibility(data, nativeNameShown)
    local shouldShowName = nativeNameShown == true

    -- The name's height feeds the enemy aura anchors; re-anchor when it appears or hides.
    if data.RefineName and SetRegionShownIfChanged(data.RefineName, shouldShowName) then
        data.AuraLayoutStale = true
    end

    if data.RefineHealth then
        SetRegionShownIfChanged(data.RefineHealth, shouldShowName and data.RefineHidden ~= true)
    end
end

-- Blizzard's name update runs on every health change, so normalization only reruns
-- when the native text actually changes.
function Nameplates:SyncRefineNameFromNative(unitFrame, unit, nameSource)
    local data = NameplateData[unitFrame]
    if not data or not data.RefineName then
        return false
    end

    local nativeName = nameSource or GetNativeNameSource(unitFrame)
    local nativeNameShown = self:IsNativeNameShown(unitFrame, nativeName)
    local text = nativeNameShown and nativeName:GetText() or ""

    if Util.IsSecret(text) then
        data.RefineName:SetText(text)
        data.RefineNameRaw = nil
    elseif text ~= data.RefineNameRaw then
        data.RefineNameRaw = text
        data.RefineName:SetText(NormalizeNameText(text, unit))
        data.AuraLayoutStale = true
    end

    self:ApplyRefineTextVisibility(data, nativeNameShown)
    return nativeNameShown
end

----------------------------------------------------------------------------------------
-- Shared Color Helpers (used by Threat component)
----------------------------------------------------------------------------------------
function Nameplates:SetNameColorIfChanged(data, r, g, b)
    if not data.RefineName then
        return
    end

    if data.NameColorR == r and data.NameColorG == g and data.NameColorB == b then
        return
    end

    data.RefineName:SetTextColor(r, g, b)
    data.NameColorR = r
    data.NameColorG = g
    data.NameColorB = b
end

function Nameplates:SetBarColorIfChanged(statusbar, r, g, b)
    local cr, cg, cb = statusbar:GetStatusBarColor()
    if cr ~= r or cg ~= g or cb ~= b then
        statusbar:SetStatusBarColor(r, g, b)
    end
end

----------------------------------------------------------------------------------------
-- NPC Title API
----------------------------------------------------------------------------------------
-- ApplyNpcTitleVisual modes:
--   nil       passive refresh: show a cached title, never scan the tooltip
--   "resolve" scan the tooltip now, or queue it when many plates are visible
--   "queue"   drained from the resolve queue
--   "retry"   delayed rescan after tooltip data was not ready
local function ShouldDeferNpcTitleResolve(data)
    if data.RefineHidden == true then
        return true
    end

    local threshold = Constants.NPC_TITLE_DEFER_ACTIVE_PLATE_THRESHOLD
    local count = 0
    for _ in pairs(ActiveNameplates) do
        count = count + 1
        if count >= threshold then
            return true
        end
    end

    return false
end

local function DrainNpcTitleResolveQueue()
    Nameplates:DrainNpcTitleResolveQueue()
end

function Nameplates:SetNpcTitleResolveJobEnabled(enabled)
    RefineUI:SetUpdateJobEnabled(Constants.NPC_TITLE_RESOLVE_JOB_KEY, enabled == true, false)
end

function Nameplates:EnsureNpcTitleResolveJob()
    if RefineUI:IsUpdateJobRegistered(Constants.NPC_TITLE_RESOLVE_JOB_KEY) then
        return
    end

    RefineUI:RegisterUpdateJob(
        Constants.NPC_TITLE_RESOLVE_JOB_KEY,
        Constants.NPC_TITLE_RESOLVE_INTERVAL_SECONDS,
        DrainNpcTitleResolveQueue,
        {
            enabled = false,
            safe = true,
            disableOnError = true,
        }
    )
end

function Nameplates:CancelNpcTitleResolve(unitFrame)
    local queued = Runtime.npcTitleResolveQueuedByFrame[unitFrame]
    if queued then
        queued.cancelled = true
        Runtime.npcTitleResolveQueuedByFrame[unitFrame] = nil
    end
end

function Nameplates:ClearNpcTitleResolveQueue()
    wipe(Runtime.npcTitleResolveQueue)
    wipe(Runtime.npcTitleResolveQueuedByFrame)
    Runtime.npcTitleResolveHead = 1
    self:SetNpcTitleResolveJobEnabled(false)
end

function Nameplates:EnqueueNpcTitleResolve(nameplate, unitFrame, unit)
    local existing = Runtime.npcTitleResolveQueuedByFrame[unitFrame]
    if existing then
        existing.unit = unit
        existing.nameplate = nameplate
        existing.cancelled = false
        return
    end

    self:EnsureNpcTitleResolveJob()

    local entry = {
        nameplate = nameplate,
        unitFrame = unitFrame,
        unit = unit,
        cancelled = false,
    }
    Runtime.npcTitleResolveQueuedByFrame[unitFrame] = entry
    tinsert(Runtime.npcTitleResolveQueue, entry)
    self:SetNpcTitleResolveJobEnabled(true)
end

function Nameplates:DrainNpcTitleResolveQueue()
    local queue = Runtime.npcTitleResolveQueue
    local head = Runtime.npcTitleResolveHead
    local tail = #queue
    local budget = Constants.NPC_TITLE_RESOLVE_BUDGET_PER_TICK
    local processed = 0

    while processed < budget and head <= tail do
        local entry = queue[head]
        queue[head] = nil
        head = head + 1

        local unitFrame = entry.unitFrame
        if Runtime.npcTitleResolveQueuedByFrame[unitFrame] == entry then
            Runtime.npcTitleResolveQueuedByFrame[unitFrame] = nil
        end

        if not entry.cancelled then
            local nameplate = unitFrame:GetParent()
            if nameplate and nameplate.UnitFrame == unitFrame then
                local unit = Util.ResolveUnitToken(entry.unit, unitFrame.unit)
                if unit then
                    self:ApplyNpcTitleVisual(nameplate, unit, "queue")
                end
            end
        end

        processed = processed + 1
    end

    if head > tail then
        wipe(queue)
        Runtime.npcTitleResolveHead = 1
        self:SetNpcTitleResolveJobEnabled(false)
    else
        Runtime.npcTitleResolveHead = head
    end
end

function Nameplates:CancelNpcTitleRetry(unitFrame)
    local data = NameplateData[unitFrame]
    if not data then
        return
    end

    data.NpcTitleRetryGUID = nil
    if data.NpcTitleRetryPending then
        data.NpcTitleRetryPending = nil
        RefineUI:CancelTimer(data.NpcTitleTimerKey)
    end
end

function Nameplates:SetNpcTitleText(data, title)
    local titleText = data.RefineNpcTitle
    if not titleText then
        return
    end

    if type(title) ~= "string" or not Util.IsAccessibleValue(title) then
        title = nil
    end

    if title then
        local formattedTitle = "<" .. title .. ">"
        if data.RefineNpcTitleFormatted ~= formattedTitle then
            titleText:SetText(formattedTitle)
            data.RefineNpcTitleFormatted = formattedTitle
        end
        titleText:Show()
        return
    end

    if data.RefineNpcTitleFormatted ~= "" then
        titleText:SetText("")
        data.RefineNpcTitleFormatted = ""
    end
    if titleText:IsShown() then
        titleText:Hide()
    end
end

local function ClearNpcTitle(unitFrame, data)
    Nameplates:CancelNpcTitleResolve(unitFrame)
    Nameplates:CancelNpcTitleRetry(unitFrame)
    Nameplates:SetNpcTitleText(data, nil)
end

function Nameplates:ScheduleNpcTitleRetry(unitFrame, data, expectedGUID)
    data.NpcTitleTimerKey = data.NpcTitleTimerKey or (Constants.NPC_TITLE_TIMER_KEY_PREFIX .. tostring(unitFrame))
    data.NpcTitleRetryGUID = expectedGUID
    data.NpcTitleRetryPending = true

    RefineUI:After(data.NpcTitleTimerKey, Constants.NPC_TITLE_RETRY_DELAY_SECONDS, function()
        data.NpcTitleRetryGUID = nil
        data.NpcTitleRetryPending = nil

        if unitFrame:IsForbidden() then
            return
        end

        local retryNameplate = unitFrame:GetParent()
        if not retryNameplate or retryNameplate.UnitFrame ~= unitFrame then
            return
        end

        local retryUnit = Util.ResolveUnitToken(unitFrame.unit)
        if not retryUnit then
            return
        end

        if expectedGUID and GetCacheableUnitGUID(retryUnit) ~= expectedGUID then
            return
        end

        self:ApplyNpcTitleVisual(retryNameplate, retryUnit, "retry")
    end)
end

function Nameplates:ApplyNpcTitleVisual(nameplate, unit, mode)
    local unitFrame = nameplate and nameplate.UnitFrame
    if not unitFrame then
        return
    end

    local data = self:GetNameplateData(unitFrame)
    local resolvedUnit = Util.ResolveUnitToken(unit, unitFrame.unit)

    if not resolvedUnit
        or not IsNpcTitleFeatureEnabled()
        or not self:IsNativeNameShown(unitFrame)
        or not IsEligibleNpcTitleUnit(resolvedUnit, data) then
        ClearNpcTitle(unitFrame, data)
        return
    end

    if not EnsureNpcTitleFontString(unitFrame, data) then
        return
    end

    local cacheGUID = GetCacheableUnitGUID(resolvedUnit)
    if cacheGUID then
        local cachedTitle = Runtime.npcTitleCacheByGUID[cacheGUID]
        if cachedTitle ~= nil then
            self:CancelNpcTitleResolve(unitFrame)
            self:CancelNpcTitleRetry(unitFrame)
            self:SetNpcTitleText(data, cachedTitle or nil)
            return
        end
    end

    if mode ~= "retry" and cacheGUID and data.NpcTitleRetryGUID == cacheGUID then
        self:SetNpcTitleText(data, nil)
        return
    end

    if ShouldSuppressNpcTitleScanning() then
        ClearNpcTitle(unitFrame, data)
        return
    end

    -- Passive refreshes leave any queued resolve or pending retry in place.
    if mode == nil then
        self:SetNpcTitleText(data, nil)
        return
    end

    if mode == "resolve" and ShouldDeferNpcTitleResolve(data) then
        self:EnqueueNpcTitleResolve(nameplate, unitFrame, resolvedUnit)
        self:SetNpcTitleText(data, nil)
        return
    end

    local resolvedTitle, isResolved = ResolveNpcTitle(resolvedUnit, cacheGUID)
    if isResolved then
        self:CancelNpcTitleResolve(unitFrame)
        self:CancelNpcTitleRetry(unitFrame)
        self:SetNpcTitleText(data, resolvedTitle)
        return
    end

    self:SetNpcTitleText(data, nil)

    if mode ~= "retry" then
        self:ScheduleNpcTitleRetry(unitFrame, data, cacheGUID)
    end
end

----------------------------------------------------------------------------------------
-- Text Rendering API
----------------------------------------------------------------------------------------
-- Blizzard only sets the native name's text and visibility in CompactUnitFrame_UpdateName,
-- which the Runtime hook already mirrors through UpdateName.
local function HookNativeName(name)
    RefineUI:HookOnce(Nameplates:BuildHookKey(name, "SetAlpha"), name, "SetAlpha", function(nameObj, alpha)
        if alpha ~= 0 then
            nameObj:SetAlpha(0)
        end
    end)
end

function Nameplates:UpdateName(nameplate, unit)
    local unitFrame = nameplate and nameplate.UnitFrame
    local name = unitFrame and GetNativeNameSource(unitFrame)
    if not name then
        return
    end

    local data = self:GetNameplateData(unitFrame)
    local desiredNameFontSize = self:GetScaledNameplateNameFontSize()

    if not data.RefineName then
        local health = unitFrame.healthBar or unitFrame.HealthBar
        data.RefineName = unitFrame:CreateFontString(nil, "OVERLAY")
        RefineUI.Font(data.RefineName, desiredNameFontSize)
        RefineUI.Point(data.RefineName, "BOTTOM", health or unitFrame, health and "TOP" or "CENTER", 0, health and 4 or 0)
        data.RefineNameFontSize = desiredNameFontSize
    elseif data.RefineNameFontSize ~= desiredNameFontSize then
        RefineUI.Font(data.RefineName, desiredNameFontSize)
        data.RefineNameFontSize = desiredNameFontSize
        data.AuraLayoutStale = true
    end

    if data.NameSource ~= name then
        data.NameSource = name
        HookNativeName(name)
    end

    if name:GetAlpha() ~= 0 then
        name:SetAlpha(0)
    end

    -- This runs on every health change; the title only depends on name visibility here.
    local nativeNameShown = self:SyncRefineNameFromNative(unitFrame, unit, name)
    if data.NpcTitleNameShown ~= nativeNameShown then
        data.NpcTitleNameShown = nativeNameShown
        self:ApplyNpcTitleVisual(nameplate, unit)
    end
end

function Nameplates:UpdateHealth(nameplate, unit)
    local unitFrame = nameplate and nameplate.UnitFrame
    local health = unitFrame and (unitFrame.healthBar or unitFrame.HealthBar)
    local data = health and NameplateData[unitFrame]
    if not data or not unit then
        return
    end

    local nativeNameShown = self:IsNativeNameShown(unitFrame)
    if data.RefineHidden or not nativeNameShown then
        -- Hides the health text; the name follows the native name.
        self:ApplyRefineTextVisibility(data, nativeNameShown)
        if data.RefineHealth then
            RefineUI:SetFontStringValue(data.RefineHealth, nil, EMPTY_TEXT_OPTS)
        end
        return
    end

    local desiredHealthFontSize = self:GetScaledNameplateHealthFontSize()

    if not data.RefineHealth then
        local parent = (data.HealthBorderOverlay and data.HealthBorderOverlay.border) or health
        data.RefineHealth = parent:CreateFontString(nil, "OVERLAY")
        RefineUI.Font(data.RefineHealth, desiredHealthFontSize, nil, "OUTLINE")
        RefineUI.Point(data.RefineHealth, "CENTER", health, "CENTER", 0, -2)
        data.RefineHealthFontSize = desiredHealthFontSize
    elseif data.RefineHealthFontSize ~= desiredHealthFontSize then
        RefineUI.Font(data.RefineHealth, desiredHealthFontSize, nil, "OUTLINE")
        data.RefineHealthFontSize = desiredHealthFontSize
    end

    if not data.HealthTextureApplied then
        health:SetStatusBarTexture(HEALTH_BAR_TEXTURE)
        health:SetStatusBarDesaturated(true)
        data.HealthTextureApplied = true
    end

    self:ApplyRefineTextVisibility(data, true)

    -- Keep health-percent transport direct so secret-capable values never flow through addon math.
    RefineUI:SetFontStringValue(data.RefineHealth, UnitHealthPercent(unit, true, RefineUI.GetPercentCurve()), EMPTY_TEXT_OPTS)
end

----------------------------------------------------------------------------------------
-- Public API (Compatibility)
----------------------------------------------------------------------------------------
function Nameplates:HideAllNpcTitleFontStrings()
    for _, nameplate in pairs(C_NamePlate.GetNamePlates()) do
        local unitFrame = nameplate.UnitFrame
        if unitFrame then
            self:CancelNpcTitleRetry(unitFrame)

            local data = NameplateData[unitFrame]
            if data then
                self:SetNpcTitleText(data, nil)
            end
        end
    end
end

function RefineUI:RefreshAllNameplateNpcTitles()
    for _, nameplate in pairs(C_NamePlate.GetNamePlates()) do
        local unitFrame = nameplate.UnitFrame
        if unitFrame then
            Nameplates:ApplyNpcTitleVisual(nameplate, unitFrame.unit, "resolve")
        end
    end
end

local function RefreshAllNameplateText(resolveTitles)
    for _, nameplate in pairs(C_NamePlate.GetNamePlates()) do
        local unitFrame = nameplate.UnitFrame
        local unit = unitFrame and Util.ResolveUnitToken(unitFrame.unit)
        if unit then
            Nameplates:UpdateName(nameplate, unit)
            if not IsNameOnly(unitFrame) then
                Nameplates:UpdateHealth(nameplate, unit)
            end
            if resolveTitles then
                Nameplates:ApplyNpcTitleVisual(nameplate, unit, "resolve")
            end
        end
    end
end

function RefineUI:RefreshAllNameplateTextScales()
    RefreshAllNameplateText(false)
end

function RefineUI:RefreshAllNameplateNameRules()
    RefreshAllNameplateText(true)
end

function Nameplates:RegisterNpcTitleEvents()
    RefineUI:RegisterEventCallback("PLAYER_REGEN_DISABLED", function()
        Nameplates:ClearNpcTitleResolveQueue()
        Nameplates:HideAllNpcTitleFontStrings()
    end, "Nameplates:NPCTitles:CombatStart")

    RefineUI:RegisterEventCallback("PLAYER_REGEN_ENABLED", function()
        RefineUI:RefreshAllNameplateNpcTitles()
    end, "Nameplates:NPCTitles:CombatEnd")

    RefineUI:RegisterEventCallback("PLAYER_ENTERING_WORLD", function()
        if ShouldSuppressNpcTitleScanning() then
            Nameplates:ClearNpcTitleResolveQueue()
        end
        RefineUI:RefreshAllNameplateNpcTitles()
    end, "Nameplates:NPCTitles:WorldEntry")
end
