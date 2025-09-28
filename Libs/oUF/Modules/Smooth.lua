local R, C, L = unpack(RefineUI)

----------------------------------------------------------------------------------------
-- Smooth statusbar (HP/Power) with instant snaps + combat-only mode
-- - Weak-key cache (no leaks)
-- - Exponential smoothing (configurable speeds up/down)
-- - Instant snaps on death, resurrect, disconnect, invisible, or out-of-combat
-- - Optional "big jump" snap
-- - Per-bar enable/disable via bar.SmoothEnabled = false
----------------------------------------------------------------------------------------

local _, ns = ...
local RefineUF = rawget(_G, "oUF") or ns.oUF or R.oUF

-- Hoist globals to locals for speed
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsConnected = UnitIsConnected
local UnitIsVisible = UnitIsVisible
local pairs = pairs
local ipairs = ipairs

-- Read smoothing config from C.unitframes with safe fallbacks
local cfg = (C and C.unitframes) or {}
local SPEED_UP = tonumber(cfg.smoothSpeedUp) or 14
local SPEED_DOWN = tonumber(cfg.smoothSpeedDown) or 20
local SNAP_ABS = tonumber(cfg.smoothSnapAbs) or 0.5
local ELAPSED_MAX = tonumber(cfg.smoothElapsedMax) or 0.20
local SKIP_HIDDEN = cfg.smoothSkipHidden == nil and true or not not cfg.smoothSkipHidden
local SMOOTH_ONLY_IN_COMBAT = cfg.smoothOnlyInCombat == nil and true or not not cfg.smoothOnlyInCombat
local SNAP_ON_DEATH = cfg.smoothSnapOnDeath == nil and true or not not cfg.smoothSnapOnDeath
local SNAP_ON_RESURRECT = cfg.smoothSnapOnResurrect == nil and true or not not cfg.smoothSnapOnResurrect
local SNAP_ON_DISCONNECT = cfg.smoothSnapOnDisconnect == nil and true or not not cfg.smoothSnapOnDisconnect
local SNAP_ON_INVISIBLE = cfg.smoothSnapOnInvisible == nil and true or not not cfg.smoothSnapOnInvisible
local BIG_JUMP_FRAC = tonumber(cfg.smoothBigJumpFrac) or 0

-- ===== State =====
local abs = math.abs
local exp = math.exp
local min = math.min
local max = math.max

-- Weak-key table so recycled/destroyed bars don't stick around
local smoothing = setmetatable({}, { __mode = "k" })

-- Forward decl
local EnsureDriver

-- Programmatic snap helper
local function SmoothSnap(bar, value)
  local target = smoothing[bar] -- read first (fixes previous bug)
  smoothing[bar] = nil
  if value == nil then value = target or bar:GetValue() end
  if bar.SetValue_ then
    bar:SetValue_(value)
  else
    bar:SetValue(value)
  end
end

-- Determine if we should snap instantly instead of smoothing
local function ShouldInstantSnap(bar, target)
  -- Out-of-combat: everything snaps if combat-only mode
  if SMOOTH_ONLY_IN_COMBAT and not InCombatLockdown() then
    return true
  end

  -- Respect bar-level opt-out
  if bar.SmoothEnabled == false then
    return true
  end

  -- Only apply special rules to health bars
  if not bar._isHealth then
    return false
  end

  local owner = bar.__owner
  local unit  = owner and owner.unit
  if not unit then return false end

  -- Death / ghost -> snap to 0
  if SNAP_ON_DEATH and (UnitIsDeadOrGhost(unit) or (target or 0) <= 0) then
    return true
  end

  -- Resurrect: 0 -> >0 and not dead anymore
  if SNAP_ON_RESURRECT then
    local cur = bar:GetValue()
    if cur <= 0 and (target or 0) > 0 and not UnitIsDeadOrGhost(unit) then
      return true
    end
  end

  -- Disconnect / invisible
  if SNAP_ON_DISCONNECT and not UnitIsConnected(unit) then
    return true
  end
  if SNAP_ON_INVISIBLE and not UnitIsVisible(unit) then
    return true
  end

  return false
end

-- Our hooked SetValue (queues smoothing or snaps)
local function Smooth_SetValue(bar, value)
  -- Clamp to bar range (avoid NaNs)
  local minV, maxV = bar:GetMinMaxValues()
  if value < minV then value = minV elseif value > maxV then value = maxV end

  -- Snap paths first
  if ShouldInstantSnap(bar, value) then
    smoothing[bar] = nil
    return bar:SetValue_(value)
  end

  -- Optional "big jump" snap (global or per-bar override)
  local frac = (bar.smoothMaxDeltaFrac ~= nil) and bar.smoothMaxDeltaFrac or BIG_JUMP_FRAC
  if frac and frac > 0 then
    local cur = bar:GetValue()
    if abs(value - cur) >= frac * (maxV - minV) then
      smoothing[bar] = nil
      return bar:SetValue_(value)
    end
  end

  -- No change -> clear any pending smoothing
  if value == bar:GetValue() or value == nil then
    smoothing[bar] = nil
    return bar:SetValue_(value)
  end

  -- Queue for smoothing and ensure driver is running
  smoothing[bar] = value
  EnsureDriver()
end

-- Hook a statusbar one time
local function HookStatusBar(bar)
  if not bar or bar._smoothHooked then return end

  bar.SetValue_ = bar.SetValue
  bar.SetValue  = Smooth_SetValue

  -- Clamp targets when min/max changes
  bar.SetMinMaxValues_ = bar.SetMinMaxValues
  bar.SetMinMaxValues  = function(self, minV, maxV)
    self:SetMinMaxValues_(minV, maxV)
    local target = smoothing[self]
    if target ~= nil then
      if target < minV then target = minV elseif target > maxV then target = maxV end
      smoothing[self] = target
      self:SetValue_(min(max(self:GetValue(), minV), maxV))
    else
      self:SetValue_(min(max(self:GetValue(), minV), maxV))
    end
  end

  -- Expose snap API
  bar.SmoothSnap = SmoothSnap

  bar._smoothHooked = true
end

-- ===== Driver frame =====
local driver = CreateFrame("Frame")
driver:Hide()

driver:SetScript("OnUpdate", function(_, elapsed)
  -- Keep the cheap early-out; protects against odd ordering/races
  if not next(smoothing) then driver:Hide(); return end

  elapsed = (elapsed and elapsed > 0) and min(elapsed, ELAPSED_MAX) or 0

  for bar, target in pairs(smoothing) do
    if not bar then
      smoothing[bar] = nil

    elseif SKIP_HIDDEN and not bar:IsVisible() then
      -- When not visible, snap to target and stop
      bar:SetValue_(target)
      smoothing[bar] = nil

    elseif ShouldInstantSnap(bar, target) then
      -- Conditions changed mid-animation -> snap now
      bar:SetValue_(target)
      smoothing[bar] = nil

    else
      local cur = bar:GetValue()
      if cur == target or target == nil then
        bar:SetValue_(target or cur)
        smoothing[bar] = nil
      else
        local speed = (target > cur) and (bar.smoothSpeedUp or SPEED_UP)
                                   or (bar.smoothSpeedDown or SPEED_DOWN)
        -- Exponential step; smooth and framerate-independent
        local step = (target - cur) * (1 - exp(-speed * elapsed))
        local new  = cur + step

        if new ~= new then new = target end -- NaN guard
        if (target > cur and new > target) or (target < cur and new < target) then
          new = target
        end

        if abs(target - new) <= (bar.smoothSnapAbs or SNAP_ABS) then
          bar:SetValue_(target)
          smoothing[bar] = nil
        else
          bar:SetValue_(new)
        end
      end
    end
  end

  -- Hide driver if last bar finished this frame
  if not next(smoothing) then driver:Hide() end
end)

function EnsureDriver()
  if next(smoothing) and (not SMOOTH_ONLY_IN_COMBAT or InCombatLockdown()) then
    driver:Show()
  else
    driver:Hide()
  end
end

-- ===== Combat watcher (singleton) =====
R.__smooth = R.__smooth or {}
R.__smooth.combatWatcher = R.__smooth.combatWatcher or CreateFrame("Frame")
local combatWatcher = R.__smooth.combatWatcher
combatWatcher:UnregisterAllEvents()
combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
combatWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
combatWatcher:SetScript("OnEvent", function(_, event)
  if not SMOOTH_ONLY_IN_COMBAT then return end
  if event == "PLAYER_REGEN_ENABLED" then
    -- Snap any in-flight animations and stop driver
    for bar, target in pairs(smoothing) do
      if bar and target ~= nil then bar:SetValue_(target) end
      smoothing[bar] = nil
    end
    driver:Hide()
  elseif event == "PLAYER_REGEN_DISABLED" then
    -- Driver will be started by next Smooth_SetValue call
  end
end)

-- ===== oUF integration =====
local function SmoothBar(_, bar)
  HookStatusBar(bar)
end

local function hook(frame)
  frame.SmoothBar = SmoothBar
  if frame.Health and frame.Health.Smooth then
    frame.Health._isHealth = true
    frame.Health.__owner   = frame
    SmoothBar(frame, frame.Health)
  end
  if frame.Power and frame.Power.Smooth then
    frame.Power.__owner = frame
    SmoothBar(frame, frame.Power)
  end
end

for _, frame in ipairs(RefineUF.objects) do hook(frame) end
RefineUF:RegisterInitCallback(hook)
