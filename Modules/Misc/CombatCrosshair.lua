----------------------------------------------------------------------------------------
-- Combat Crosshair (lean event-only, driver-proof, no alpha bugs)
----------------------------------------------------------------------------------------

local R, C, L = unpack(RefineUI)
if not (C and C.combatcrosshair and C.combatcrosshair.enable) then return end

local SIZE   = C.combatcrosshair.size   or 16
local OFFX   = C.combatcrosshair.offsetx or 0
local OFFY   = C.combatcrosshair.offsety or 0
local ALPHA  = (C.combatcrosshair.alpha and C.combatcrosshair.alpha > 0) and C.combatcrosshair.alpha or 0.6
local STRATA = C.combatcrosshair.strata or "TOOLTIP"
local BLEND  = C.combatcrosshair.blend  or "ADD" -- try "ADD" if you want glow
local FADE   = (C.combatcrosshair.fade ~= false)   -- allow toggle via config
local DEBUG  = C.combatcrosshair.debug == true
local IGNORE_PARENT_ALPHA = C.combatcrosshair.ignoreParentAlpha == true
local UnitAffectingCombat = UnitAffectingCombat

-- If an older secure-driver version exists, detach its driver so it can't fight us
do
  local old = _G.RefineUI_CombatCrosshair
  if old and type(UnregisterStateDriver) == "function" then
    pcall(UnregisterStateDriver, old, "visibility")
  end
end

-- Use a fresh name to avoid collisions with the secure version
local crosshair = CreateFrame("Frame", "RefineUI_CombatCrosshair_Event", UIParent)
crosshair:SetSize(SIZE, SIZE)
crosshair:SetPoint("CENTER", UIParent, "CENTER", OFFX, OFFY)
crosshair:SetFrameStrata(STRATA)
crosshair:SetFrameLevel(9999)
crosshair:EnableMouse(false)
crosshair:Hide()                   -- start hidden
crosshair:SetAlpha(1)              -- keep frame alpha at 1; we animate the texture
if IGNORE_PARENT_ALPHA and crosshair.SetIgnoreParentAlpha then
  crosshair:SetIgnoreParentAlpha(true)
end

local tex = crosshair:CreateTexture(nil, "ARTWORK")
tex:SetTexture(C.combatcrosshair.texture)
tex:SetAllPoints()
tex:SetVertexColor(1, 1, 1, 1)
tex:SetBlendMode(BLEND)
if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(true); tex:SetTexelSnappingBias(0) end

-- Optional fade: animate TEXTURE alpha only; never the frame alpha
local fadeIn, fadeOut
if FADE then
  fadeIn  = tex:CreateAnimationGroup()
  local a = fadeIn:CreateAnimation("Alpha"); a:SetFromAlpha(0); a:SetToAlpha(ALPHA); a:SetDuration(0.12); a:SetSmoothing("OUT")
  fadeIn:SetScript("OnPlay",     function() tex:SetAlpha(0); crosshair:SetAlpha(1) end)
  fadeIn:SetScript("OnFinished", function() tex:SetAlpha(ALPHA) end)
  fadeIn:SetScript("OnStop",     function() tex:SetAlpha(ALPHA) end)

  fadeOut = tex:CreateAnimationGroup()
  local b = fadeOut:CreateAnimation("Alpha"); b:SetFromAlpha(ALPHA); b:SetToAlpha(0); b:SetDuration(0.12); b:SetSmoothing("IN")
  fadeOut:SetScript("OnFinished", function() tex:SetAlpha(ALPHA); crosshair:Hide() end)
  fadeOut:SetScript("OnStop",     function() tex:SetAlpha(ALPHA) end)
end

-- Helpers to centralize show/hide behavior
local function ensureTexture()
  if not C.combatcrosshair.texture then
    if DEBUG then print("|cffff8800CombatCrosshair: missing texture in config|r") end
    return false
  end
  return true
end

local function showCrosshairImmediate()
  if not ensureTexture() then return end
  tex:SetAlpha(ALPHA)
  crosshair:Show()
end

local function showCrosshair()
  if not ensureTexture() then return end
  if FADE and fadeIn then
    if fadeOut then fadeOut:Stop() end
    crosshair:Show()
    fadeIn:Stop()
    fadeIn:Play()
  else
    showCrosshairImmediate()
  end
end

local function hideCrosshair()
  if FADE and fadeOut then
    if fadeIn then fadeIn:Stop() end
    fadeOut:Stop()
    fadeOut:Play()
  else
    crosshair:Hide()
  end
end

-- Event wiring (simple, no OnUpdate)
crosshair:RegisterEvent("PLAYER_ENTERING_WORLD")
crosshair:RegisterEvent("PLAYER_REGEN_DISABLED")
crosshair:RegisterEvent("PLAYER_REGEN_ENABLED")
crosshair:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_ENTERING_WORLD" then
    if UnitAffectingCombat("player") then
      showCrosshairImmediate() -- no fade on init
      if DEBUG then print("|cff00ff88Crosshair: INIT in combat|r") end
    else
      self:Hide()
      if DEBUG then print("|cffff8888Crosshair: INIT out of combat|r") end
    end
    return
  end

  if event == "PLAYER_REGEN_DISABLED" then
    showCrosshair()
    if DEBUG then print("|cff00ff88Crosshair: ENTER combat|r") end
  else -- PLAYER_REGEN_ENABLED
    hideCrosshair()
    if DEBUG then print("|cffff8888Crosshair: LEAVE combat|r") end
  end
end)
