local R, C, L = unpack(RefineUI)

-- Localize globals for speed
local _G = _G
local IsUsableAction = IsUsableAction
local IsActionInRange = IsActionInRange
local GetActionCooldown = GetActionCooldown
local GetActionCharges = GetActionCharges
local HasAction = HasAction
local GetActionTexture = GetActionTexture
local C_Spell = C_Spell -- may be nil on some clients; guarded in wrapper
local GetTime = GetTime
local hooksecurefunc = hooksecurefunc
local C_Timer = C_Timer

-- Forward declare to allow references before definition
local CancelButtonCooldownTimer

-- Color definitions (index into arrays to avoid unpack overhead)
local COLORS = {
    NORMAL        = {1.00, 1.00, 1.00},
    COOLDOWN      = {0.40, 0.40, 0.40}, -- darker + desaturated for clear long-CD read
    OUT_OF_RANGE  = {1.00, 0.30, 0.30},
    OUT_OF_POWER  = {0.30, 0.30, 1.00},
    UNUSABLE      = {0.40, 0.40, 0.40},
}

-- Thresholds
local LONG_COOLDOWN_THRESHOLD = 1.5 -- only long CDs dim/desaturate; GCD is usually below this

-- Centralized button prefixes for primary action bars (shared via R)
if not R.ActionBarPrimaryPrefixes then
    R.ActionBarPrimaryPrefixes = {
        "ActionButton",
        "MultiBarBottomLeftButton",
        "MultiBarBottomRightButton",
        "MultiBarRightButton",
        "MultiBarLeftButton",
        "MultiBar5Button",
        "MultiBar6Button",
        "MultiBar7Button",
    }
end
local buttonPrefixes = R.ActionBarPrimaryPrefixes

-- Cached button list to avoid repeated _G lookups
local buttonCache = {}

local function BuildButtonCache()
    buttonCache = {}
    for _, prefix in ipairs(buttonPrefixes) do
        for i = 1, 12 do
            local btn = _G[prefix .. i]
            if btn then
                buttonCache[#buttonCache + 1] = { button = btn }
            end
        end
    end
end

local function GetButtonIcon(button)
    if not button then return nil end
    local n = button.GetName and button:GetName()
    return button.icon
        or button.Icon
        or (n and (_G[n.."Icon"] or _G[n.."IconTexture"]))
end

-- Safe wrapper for GetSpellCooldown that works across client branches
local function GetSpellCooldownSafe(spellID)
    -- Prefer the classic global if present
    if _G.GetSpellCooldown then
        local start, duration, enable = _G.GetSpellCooldown(spellID)
        return start, duration, enable
    end
    -- Retail fallback: C_Spell.GetSpellCooldown may return a table
    if C_Spell and C_Spell.GetSpellCooldown then
        local a, b, c = C_Spell.GetSpellCooldown(spellID)
        if type(a) == "table" then
            -- Normalize to (start, duration, enable-like)
            return a.startTime, a.duration, (a.isEnabled and 1 or 0)
        end
        -- Some builds still return tuple
        return a, b, c
    end
    -- API unavailable; treat as no cooldown
    return nil, nil, nil
end

-- GCD detector: SpellID 61304 is the universal GCD token
-- Cache GCD state for ~1 frame to avoid repeated API calls during bursts
local gcd_cached_until, gcd_active
local function IsGCDActive()
    local now = GetTime()
    if not gcd_cached_until or now > gcd_cached_until then
        local start, duration = GetSpellCooldownSafe(61304)
        gcd_active = (start and start > 0) and (duration and duration > 0) or false
        gcd_cached_until = now + 0.02 -- about one frame
    end
    return gcd_active
end

-- State caches
-- Store last state directly on the icon to avoid per-change table allocations
local buttonCooldownTimers = setmetatable({}, { __mode = "k" })

-- Adjust cooldown swipe alpha for a button (both cooldown and chargeCooldown)
local function SetSwipeAlphaForButton(button, alpha)
    if not button then return end
    if button._lastSwipeAlpha == alpha then return end -- no-op; skip GPU calls

    local cd = button.cooldown or (button.GetName and _G[button:GetName() .. "Cooldown"]) or nil
    if cd and cd.SetSwipeColor then
        local r, g, b = 0, 0, 0
        cd:SetSwipeColor(r, g, b, alpha)
        if cd.SetDrawBling then cd:SetDrawBling(false) end
    end
    local cc = button.chargeCooldown
    if cc and cc.SetSwipeColor then
        local r, g, b = 0, 0, 0
        cc:SetSwipeColor(r, g, b, alpha)
        if cc.SetDrawBling then cc:SetDrawBling(false) end
    end

    button._lastSwipeAlpha = alpha
end

-- Cancel any scheduled per-button cooldown update and clear cooldown state
CancelButtonCooldownTimer = function(button)
    if not button then return end
    local t = buttonCooldownTimers[button]
    if t and type(t.Cancel) == "function" then t:Cancel() end
    buttonCooldownTimers[button] = nil
    button.onCooldown = 0
end

-- Apply icon tint/desaturation (with optional forced reaffirm)
local function applyIconState(icon, r, g, b, desat)
    local pr, pg, pb, pdes = icon.__r, icon.__g, icon.__b, icon.__des
    if pr == r and pg == g and pb == b and pdes == desat then return end
    icon:SetVertexColor(r, g, b)
    icon:SetDesaturated(desat)
    icon.__r, icon.__g, icon.__b, icon.__des = r, g, b, desat
end

-- Helper: treat a button as "cooling down" if a standard cooldown is running
-- or if it has charges and is recharging from zero.
local function IsOnCooldown(button)
    if not button or not button.action or button.action == 0 then
        return false
    end

    local start, duration, enable = GetActionCooldown(button.action)
    local onCooldown = (enable == 1) and duration and duration > LONG_COOLDOWN_THRESHOLD and start and start > 0

    if GetActionCharges then
        local charges, maxCharges, chargeStart, chargeDuration = GetActionCharges(button.action)
        local onRechargeNoCharges = (maxCharges and maxCharges > 0) and (charges == 0) and chargeDuration and chargeDuration > LONG_COOLDOWN_THRESHOLD
        if onRechargeNoCharges then return true end
    end

    return onCooldown or false
end

-- Update single button appearance (range/resource/etc)
local function UpdateButtonState(entry)
    local button = entry.button or entry
    local icon = GetButtonIcon(button)
    if not icon then return end

    local action = button.action
    if not action or action == 0 then
        local c = COLORS.NORMAL
        applyIconState(icon, c[1], c[2], c[3], false)
        SetSwipeAlphaForButton(button, IsGCDActive() and 0.8 or 0.0)
        return
    end

    local isUsable, notEnoughMana = IsUsableAction(action)
    local inRange = IsActionInRange(action)
    local start, duration, enable = GetActionCooldown(action)
    local hasAnyCooldown = (enable == 1) and start and start > 0 and duration and duration > 0
    local isLongCooldown  = hasAnyCooldown and (duration > LONG_COOLDOWN_THRESHOLD)

    local charges, maxCharges, chargeStart, chargeDuration = nil, nil, nil, nil
    if GetActionCharges then charges, maxCharges, chargeStart, chargeDuration = GetActionCharges(action) end

    -- Compute GCD once; still show the rim while keeping proper error tint.
    local gcdNow = IsGCDActive()
    local zeroChargeLong = (maxCharges and maxCharges > 0 and charges == 0 and chargeDuration and chargeDuration > LONG_COOLDOWN_THRESHOLD)

    -- PRIORITY: error states first (OOM / unusable / range), then long CD, then short CD/GCD, else normal.
    if notEnoughMana then
        local c = COLORS.OUT_OF_POWER
        applyIconState(icon, c[1], c[2], c[3], true)
        SetSwipeAlphaForButton(button, gcdNow and 0.8 or 0.0)

    elseif not isUsable then
        local c = COLORS.UNUSABLE
        applyIconState(icon, c[1], c[2], c[3], true)
        SetSwipeAlphaForButton(button, gcdNow and 0.8 or 0.0)

    -- Treat both boolean false and numeric 0 as out of range (API returns 1/0/nil)
    elseif inRange == false or inRange == 0 then
        local c = COLORS.OUT_OF_RANGE
        applyIconState(icon, c[1], c[2], c[3], true)
        SetSwipeAlphaForButton(button, gcdNow and 0.8 or 0.0)

    -- Long CD (button) OR recharging from zero charges counts as "long" styling
    elseif isLongCooldown or zeroChargeLong then
        local c = COLORS.COOLDOWN
        applyIconState(icon, c[1], c[2], c[3], true)
        if isUsable and maxCharges and maxCharges > 1 and charges and charges > 0 then
            SetSwipeAlphaForButton(button, 0.6)
        else
            SetSwipeAlphaForButton(button, 0.8)
        end

    -- GCD or any short cooldown: show rim, keep normal icon
    elseif hasAnyCooldown or gcdNow then
        applyIconState(icon, COLORS.NORMAL[1], COLORS.NORMAL[2], COLORS.NORMAL[3], false)
        SetSwipeAlphaForButton(button, 0.8)

    else
        applyIconState(icon, COLORS.NORMAL[1], COLORS.NORMAL[2], COLORS.NORMAL[3], false)
        SetSwipeAlphaForButton(button, gcdNow and 0.8 or 0.0)
    end
end

local function RefreshAll()
    for i = 1, #buttonCache do
        local entry = buttonCache[i]
        if entry then
            UpdateButtonState(entry)
        end
    end
end

-- Debounce scheduled refresh to coalesce bursty events and avoid intermediate visuals
local scheduledRefreshTimer
local function ScheduleRefresh(delay)
    delay = delay or 0.05
    if scheduledRefreshTimer then
        if type(scheduledRefreshTimer.Cancel) == "function" then scheduledRefreshTimer:Cancel() end
        scheduledRefreshTimer = nil
    end
    scheduledRefreshTimer = C_Timer.NewTimer(delay, function()
        scheduledRefreshTimer = nil
        RefreshAll()
    end)
end

local function UpdateSlot(slot)
    if not slot or slot == 0 then return end
    for _, prefix in ipairs(buttonPrefixes) do
        local btn = _G[prefix .. slot]
        if btn then
            CancelButtonCooldownTimer(btn)
            for i = 1, #buttonCache do
                local e = buttonCache[i]
                if e and e.button == btn then
                    e.icon = GetButtonIcon(btn)
                    UpdateButtonState(e)
                    break
                end
            end
        end
    end
end

-- Per-button cooldown updater (O(1) per affected button)
local function ActionButtonGrey_UpdateCooldown(self)
    if not self then return end
    local icon = GetButtonIcon(self)
    if not icon then return end

    -- Validate that self.action exists and is a valid action slot
    if not self.action or type(self.action) ~= "number" or self.action == 0 then
        CancelButtonCooldownTimer(self)
        SetSwipeAlphaForButton(self, IsGCDActive() and 0.8 or 0.0)
        local c = COLORS.NORMAL
        applyIconState(icon, c[1], c[2], c[3], false)
        return
    end

    -- If slot has no action/texture now, clear cooldown state immediately
    if HasAction and not HasAction(self.action) then
        CancelButtonCooldownTimer(self)
        SetSwipeAlphaForButton(self, IsGCDActive() and 0.8 or 0.0)
        local c = COLORS.NORMAL
        applyIconState(icon, c[1], c[2], c[3], false)
        return
    end

    local start, duration, enable = GetActionCooldown(self.action)

    -- Cancel any previously scheduled finish tick; we will reschedule if needed
    CancelButtonCooldownTimer(self)

    local anyCooldown  = (enable == 1) and start and start > 0 and duration and duration > 0
    local longCooldown = anyCooldown and (duration > LONG_COOLDOWN_THRESHOLD)

    if anyCooldown then
        -- Rim shows via UpdateButtonState; let unified resolver pick icon tint (OOM/range/etc).
        SetSwipeAlphaForButton(self, 0.8)

        -- Schedule a single update at cooldown end to restore immediately
        local timeRemaining = (start + duration) - GetTime()
        if timeRemaining and timeRemaining > 0 and timeRemaining < 1e6 then
            buttonCooldownTimers[self] = C_Timer.NewTimer(timeRemaining + 0.02, function()
                CancelButtonCooldownTimer(self)
                -- Re-evaluate right after cooldown ends
                pcall(function()
                    UpdateButtonState(self)
                end)
            end)
        end
        -- Immediately resolve current state (handles OOM/range during GCD/short CDs).
        UpdateButtonState(self)
        return
    else
        CancelButtonCooldownTimer(self)
        -- Not on cooldown: let the general resolver decide (handles range/mana/etc)
        UpdateButtonState(self)
    end
end

-- Hook the Blizzard cooldown updater if present
if type(rawget(_G, "ActionButton_UpdateCooldown")) == "function" then
    hooksecurefunc("ActionButton_UpdateCooldown", ActionButtonGrey_UpdateCooldown)
end

local frame = CreateFrame("Frame")

-- No periodic combat ticker; event-driven updates are sufficient

-- Hook Blizzard update functions for targeted updates (safe in combat) only if present
if type(rawget(_G, "ActionButton_Update")) == "function" then
    hooksecurefunc("ActionButton_Update", function(self)
        for i = 1, #buttonCache do
            local e = buttonCache[i]
            if e and e.button == self then
                UpdateButtonState(e)
                return
            end
        end
        UpdateButtonState(self)
    end)
end
if type(rawget(_G, "ActionButton_UpdateUsable")) == "function" then
    hooksecurefunc("ActionButton_UpdateUsable", function(self)
        for i = 1, #buttonCache do
            local e = buttonCache[i]
            if e and e.button == self then
                UpdateButtonState(e)
                return
            end
        end
        UpdateButtonState(self)
    end)
end

frame:SetScript("OnEvent", function(_, event, arg1, ...)
    if event == "PLAYER_LOGIN" then
        BuildButtonCache()
        RefreshAll()
    elseif event == "ACTIONBAR_SLOT_CHANGED" then
        UpdateSlot(arg1)
    elseif event == "UNIT_POWER_UPDATE" then
        if arg1 == "player" then ScheduleRefresh() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- no periodic ticker; rely on events
    elseif event == "PLAYER_REGEN_ENABLED" then
        RefreshAll()
    elseif event == "ACTIONBAR_UPDATE_COOLDOWN" then
        -- No global scan here; per-button hook handles visuals.
        -- (Kept empty for performance.)
    elseif event == "ACTION_RANGE_CHECK_UPDATE" then
        UpdateSlot(arg1)
    elseif event == "ACTIONBAR_UPDATE_USABLE" or event == "PLAYER_TARGET_CHANGED" or event == "SPELL_UPDATE_CHARGES" then
        -- coalesce other frequent updates to avoid transient visuals
        ScheduleRefresh()
    elseif event == "ACTIONBAR_PAGE_CHANGED" or event == "UPDATE_SHAPESHIFT_FORM" or event == "UPDATE_VEHICLE_ACTIONBAR" or event == "UPDATE_POSSESS_BAR" or event == "UPDATE_OVERRIDE_ACTIONBAR" then
        -- Page/vehicle/possess swaps: rebuild cache once and refresh
        for i = 1, #buttonCache do
            local e = buttonCache[i]
            if e and e.button then CancelButtonCooldownTimer(e.button) end
        end
        BuildButtonCache()
        RefreshAll()
        ScheduleRefresh(0.03)
    else
        RefreshAll()
    end
end)

local events = {
    "PLAYER_LOGIN",
    "ACTIONBAR_UPDATE_USABLE",
    "ACTIONBAR_UPDATE_COOLDOWN",
    "ACTION_RANGE_CHECK_UPDATE",
    "SPELL_UPDATE_CHARGES",
    "PLAYER_TARGET_CHANGED",
    "UNIT_POWER_UPDATE",
    "ACTIONBAR_SLOT_CHANGED",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "ACTIONBAR_PAGE_CHANGED",
    "UPDATE_SHAPESHIFT_FORM",
    "UPDATE_VEHICLE_ACTIONBAR",
    "UPDATE_POSSESS_BAR",
    "UPDATE_OVERRIDE_ACTIONBAR",
}
for _, e in ipairs(events) do
    frame:RegisterEvent(e)
end

-- Expose the update function for manual updates if needed
R.UpdateButtonState = UpdateButtonState

-- Safely hide Blizzard extra/zone ability styles if present
if ExtraActionButton1 and ExtraActionButton1.style then
    ExtraActionButton1.style:SetAlpha(0)
    ExtraActionButton1.style:Hide()
end

if ZoneAbilityFrame and ZoneAbilityFrame.Style then
    ZoneAbilityFrame.Style:SetAlpha(0)
    ZoneAbilityFrame.Style:Hide()
end
