----------------------------------------------------------------------------------------
--  Combat Cursor (perf-tuned)
--  - Caches UI scale (updates on scale/size changes)
--  - Throttles updates (default 144 Hz)
--  - Skips SetPoint when the cursor hasn't moved
--  - Only runs OnUpdate while shown (in combat)
----------------------------------------------------------------------------------------

local R, C, L = unpack(RefineUI)
if not (C and C.combatcursor and C.combatcursor.enable) then return end

-- Upvalues for speed
local UIParent            = UIParent
local GetCursorPosition   = GetCursorPosition
local math_abs            = math.abs

-- Tweakable: 144 feels 1:1 on high-refresh displays; 60 is also fine
local UPDATE_HZ = (C.combatcursor.hz and C.combatcursor.hz > 0) and C.combatcursor.hz or 120
local UPDATE_DT = 1 / UPDATE_HZ
local MOVE_EPS  = C.combatcursor.moveEps or 0.25 -- pixels; ignore sub-pixel jitter
local BLEND = C.combatcursor.blend or "ADD"  -- "ADD" = glowy; "BLEND" = normal

-- Cache effective scale; recompute on scale/size changes
local invScale = 1 / UIParent:GetEffectiveScale()
local function RefreshScale()
    invScale = 1 / UIParent:GetEffectiveScale()
end

-- Frame + texture
local combatCursor = CreateFrame("Frame", "RefineUI_CombatCursor", UIParent)
combatCursor:SetFrameStrata(C.combatcursor.strata or "TOOLTIP")
combatCursor:SetSize(C.combatcursor.size, C.combatcursor.size)
combatCursor:EnableMouse(false)
combatCursor:Hide()

local tex = combatCursor:CreateTexture(nil, "ARTWORK")
tex:SetTexture(C.combatcursor.texture)
tex:SetAllPoints(combatCursor)
tex:SetVertexColor(1, 1, 1, C.combatcursor.alpha or 0.9)
tex:SetBlendMode(BLEND)
combatCursor.texture = tex

-- Throttled updater
local accum, lastX, lastY = 0, nil, nil
local function OnUpdate_Throttled(self, elapsed)
    accum = accum + elapsed
    if accum < UPDATE_DT then return end
    accum = 0

    local x, y = GetCursorPosition()
    x, y = x * invScale, y * invScale

    -- Only move if it actually changed by a noticeable amount
    if not lastX or math_abs(x - lastX) > MOVE_EPS or math_abs(y - lastY) > MOVE_EPS then
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
        lastX, lastY = x, y
    end
end

-- Events
combatCursor:RegisterEvent("PLAYER_REGEN_DISABLED")
combatCursor:RegisterEvent("PLAYER_REGEN_ENABLED")
combatCursor:RegisterEvent("UI_SCALE_CHANGED")
combatCursor:RegisterEvent("DISPLAY_SIZE_CHANGED")

combatCursor:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_DISABLED" then
        RefreshScale()
        accum, lastX, lastY = UPDATE_DT, nil, nil -- force an immediate first update
        self:SetScript("OnUpdate", OnUpdate_Throttled)
        self:Show()
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:SetScript("OnUpdate", nil)
        self:Hide()
    else -- scale or resolution changed
        RefreshScale()
    end
end)
