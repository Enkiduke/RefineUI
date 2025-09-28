local R, C, L = unpack(RefineUI)

----------------------------------------------------------------------------------------
-- Upvalues and Constants
----------------------------------------------------------------------------------------

-- Localize global functions for performance
local format, floor, GetTime = string.format, math.floor, GetTime
local CreateFrame, hooksecurefunc = CreateFrame, hooksecurefunc
local UIParent = UIParent
local UI_SCALE = UIParent:GetEffectiveScale()
local day, hour, minute = 86400, 3600, 60

-- Configuration Constants
local LOW_TIME_THRESHOLD = 5 -- Seconds below which text color changes
local MIN_VISIBLE_SCALE = 0.5 -- Minimum scale relative to UIParent for the timer text to be visible

-- ----------------------------------------------------------------------------------------
-- -- Time Formatting
-- ----------------------------------------------------------------------------------------

-- local function GetFormattedTime(s)
--     if s >= day then
--         return format("%dd", floor(s / day + 0.5)), s % day
--     elseif s >= hour then
--         return format("%dh", floor(s / hour + 0.5)), s % hour
--     elseif s >= minute then
--         return format("%dm", floor(s / minute + 0.5)), s % minute
--     end
--     return floor(s + 0.5), s - floor(s)
-- end

-- ----------------------------------------------------------------------------------------
-- -- Timer Methods
-- ----------------------------------------------------------------------------------------

-- local function Timer_Stop(self)
--     self.enabled = nil
--     self:Hide()
-- end

-- local function Timer_ForceUpdate(self)
--     self.nextUpdate = 0
--     self:Show()
-- end

-- local function Timer_OnSizeChanged(self, width)
--     local fontScale = R.Round(width) / 40
--     if fontScale == self.fontScale then return end

--     self.fontScale = fontScale
--     if fontScale < MIN_VISIBLE_SCALE then
--         self:Hide()
--     else
--         self.text:SetFont(unpack(C.font.cooldownTimers))
--         self.text:SetShadowOffset(1, -1)
--         if self.enabled then Timer_ForceUpdate(self) end
--     end
-- end

-- -- Consolidated timer driver
-- local activeTimers = {}
-- local driver = CreateFrame("Frame")
-- driver:Hide()
-- local driverNext = 0

-- local function EnsureDriver()
--     if not driver:IsShown() then
--         driverNext = 0
--         driver:Show()
--     end
-- end

-- local function Timer_Update(self)
--     if not self.text:IsShown() then return 1 end

--     if (self:GetEffectiveScale() / UI_SCALE) < MIN_VISIBLE_SCALE then
--         self.text:SetText("")
--         return 1
--     end

--     local remain = self.duration - (GetTime() - self.start)
--     if remain > 0 then
--         local time, nextUpdate = GetFormattedTime(remain)
--         self.text:SetText(time)
--         self.text:SetTextColor(remain > LOW_TIME_THRESHOLD and 1 or 0.85, remain > LOW_TIME_THRESHOLD and 1 or 0.27, remain > LOW_TIME_THRESHOLD and 1 or 0.27)
--         return nextUpdate
--     else
--         activeTimers[self] = nil
--         Timer_Stop(self)
--         return nil
--     end
-- end

-- driver:SetScript("OnUpdate", function(_, elapsed)
--     driverNext = driverNext - elapsed
--     if driverNext > 0 then return end

--     local minNext = math.huge
--     for timer in pairs(activeTimers) do
--         if timer.enabled then
--             local nextUpdate = Timer_Update(timer)
--             if nextUpdate and nextUpdate > 0 and nextUpdate < minNext then
--                 minNext = nextUpdate
--             end
--         else
--             activeTimers[timer] = nil
--         end
--     end

--     if minNext == math.huge then
--         driver:Hide()
--         driverNext = 0
--     else
--         driverNext = minNext
--     end
-- end)

-- ----------------------------------------------------------------------------------------
-- -- Timer Creation
-- ----------------------------------------------------------------------------------------

-- local function Timer_Create(self)
--     local scaler = CreateFrame("Frame", nil, self)
--     scaler:SetAllPoints(self)

--     local timer = CreateFrame("Frame", nil, scaler)
--     timer:Hide()
--     timer:SetAllPoints(scaler)

--     local text = timer:CreateFontString(nil, "OVERLAY")
--     text:SetPoint("CENTER", 0, 0)
--     text:SetJustifyH("CENTER")
--     timer.text = text

--     Timer_OnSizeChanged(timer, scaler:GetSize())
--     scaler:SetScript("OnSizeChanged", function(_, ...) Timer_OnSizeChanged(timer, ...) end)

--     self.timer = timer
--     return timer
-- end

-- ----------------------------------------------------------------------------------------
-- -- Cooldown Handling
-- ----------------------------------------------------------------------------------------

-- local sampleCooldown = rawget(_G, "ActionButton1Cooldown")
-- if not sampleCooldown then
--     local ab1 = rawget(_G, "ActionButton1")
--     if ab1 then sampleCooldown = ab1.cooldown end
-- end
-- if not sampleCooldown then
--     sampleCooldown = CreateFrame("Cooldown", nil, UIParent, "CooldownFrameTemplate")
-- end
-- local Cooldown_MT = getmetatable(sampleCooldown).__index
-- local hideNumbers = {}

-- local function deactivateDisplay(cooldown)
--     if cooldown.timer then
--         activeTimers[cooldown.timer] = nil
--         Timer_Stop(cooldown.timer)
--     end
-- end

-- local function setHideCooldownNumbers(cooldown, hide)
--     hideNumbers[cooldown] = hide or nil
--     if hide then deactivateDisplay(cooldown) end
-- end

-- hooksecurefunc(Cooldown_MT, "SetCooldown", function(cooldown, start, duration, modRate)
--     local parent = cooldown:GetParent()
--     if not parent or not parent:GetName() then
--         return
--     end

--     -- Check if the parent button is one of the action buttons
--     if not parent:GetName():match("ActionButton") and
--         not parent:GetName():match("MultiBarBottomLeftButton") and
--         not parent:GetName():match("MultiBarLeftButton") and
--         not parent:GetName():match("MultiBarRightButton") and
--         not parent:GetName():match("MultiBarBottomRightButton") and
--         not parent:GetName():match("MultiBar5Button") and
--         not parent:GetName():match("MultiBar6Button") and
--         not parent:GetName():match("MultiBar7Button") and
--         not parent:GetName():match("OverrideActionBarButton") then
--         return
--     end

--     if cooldown.noCooldownCount or cooldown:IsForbidden() or hideNumbers[cooldown] then return end

--     if start and start > 0 and duration and duration > 2 and (modRate == nil or modRate > 0) then
--         if parent and parent.chargeCooldown == cooldown then return end

--         local timer = cooldown.timer or Timer_Create(cooldown)
--         timer.start = start -- Store the exact start time
--         timer.duration = duration -- Store the full duration
--         timer.enabled = true
--         timer.nextUpdate = 0
--         if timer.fontScale >= MIN_VISIBLE_SCALE then timer:Show() end -- Only show if scale is adequate
--         activeTimers[timer] = true
--         EnsureDriver()
--     else
--         deactivateDisplay(cooldown)
--     end
-- end)

-- hooksecurefunc(Cooldown_MT, "Clear", deactivateDisplay)
-- hooksecurefunc(Cooldown_MT, "SetHideCountdownNumbers", setHideCooldownNumbers)
-- hooksecurefunc("CooldownFrame_SetDisplayAsPercentage", function(cooldown)
--     setHideCooldownNumbers(cooldown, true)
-- end)
