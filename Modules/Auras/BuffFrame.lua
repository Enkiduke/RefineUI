--	Player Buff Frame for RefineUI
--	This module styles and manages the player's buff frame, including layout, duration,
--	and visual elements like cooldown swipes and border colors.
--	Based on Tukz's original buff styling
----------------------------------------------------------------------------------------

local R, C, L = unpack(RefineUI)

----------------------------------------------------------------------------------------
--	Upvalues
----------------------------------------------------------------------------------------
local _G = _G
-- hot path locals
local format = string.format
local floor  = math.floor
local sin    = math.sin
local GetTime = GetTime

----------------------------------------------------------------------------------------
--	Constants and Configuration
----------------------------------------------------------------------------------------
local rowbuffs = 16
local alpha = 0
local USE_BLIZZARD_DURATION_TEXT = true -- single source of truth: Blizzard's aura.Duration

----------------------------------------------------------------------------------------
--	Utility Functions
----------------------------------------------------------------------------------------
local GetFormattedTime = function(s)
    if s >= 86400 then
        return format("%dd", floor(s / 86400 + 0.5))
    elseif s >= 3600 then
        return format("%dh", floor(s / 3600 + 0.5))
    elseif s >= 60 then
        return format("%dm", floor(s / 60 + 0.5))
    elseif s > 5 then
        return format("%d", floor(s + 0.5))
    else
        return format("%.1f", s)
    end
end

-- Compact text for Blizzard duration label:
--  * seconds show with NO unit (e.g., "9" instead of "9 s")
--  * minutes/hours/days keep compact unit suffix (e.g., "2m", "1h", "3d")
local function GetCompactDurationText(timeLeft)
	if timeLeft >= 86400 then
		return format("%dd", floor(timeLeft / 86400 + 0.5))
	elseif timeLeft >= 3600 then
		return format("%dh", floor(timeLeft / 3600 + 0.5))
	elseif timeLeft >= 60 then
		return format("%dm", floor(timeLeft / 60 + 0.5))
	else
		return format("%d", floor(timeLeft + 0.5)) -- seconds: no "s"
	end
end

----------------------------------------------------------------------------------------
--	Buff Frame Anchor
----------------------------------------------------------------------------------------
local BuffsAnchor = CreateFrame("Frame", "RefineUI_Buffs", UIParent)
BuffsAnchor:SetPoint(unpack(C.position.playerBuffs))
BuffsAnchor:SetSize((16 * C.player.buffSize) + 42, (C.player.buffSize * 2) + 3)

----------------------------------------------------------------------------------------
--	Aura Update Functions
----------------------------------------------------------------------------------------
local function ApplyAuraFlashAlpha(aura, alpha)
	-- Apply a uniform flash alpha to all visible parts with minimal work
	local icon = aura.Icon
	if icon then icon:SetAlpha(alpha) end

	local iconFrame = aura.iconFrame
	if iconFrame then iconFrame:SetAlpha(alpha) end

	local border = aura.border
	if border and border.SetAlpha then border:SetAlpha(alpha) end

	-- Intentionally do NOT flash the cooldown swipe; keep it steady
	-- If needed, ensure the cooldown frame remains fully opaque for input/layering
	-- local cd = aura.cooldown
	-- if cd then cd:SetAlpha(1) end
end

local function FlashAura(aura, timeLeft)
	if timeLeft and timeLeft < 10 then
		local a = (sin(GetTime() * 5) + 1) / 2
		a = a * 0.5 + 0.5 -- range [0.5, 1]
		ApplyAuraFlashAlpha(aura, a)
	else
		ApplyAuraFlashAlpha(aura, 1)
	end
end

local function UpdateDuration(aura, timeLeft)
    local duration = aura.Duration
    if timeLeft and C.player.buffTimer == true then
        duration:SetVertexColor(1, 1, 1)
        duration:SetFormattedText(GetFormattedTime(timeLeft))
        FlashAura(aura, timeLeft)  -- Call the FlashAura function
    else
        duration:Hide()
        aura:SetAlpha(1)  -- Reset alpha when duration is hidden
    end
end

local function UpdateBorderColor(aura)
    if aura.TempEnchantBorder:IsShown() then
        aura.border:SetBackdropBorderColor(0.6, 0.1, 0.6) -- Purple for temporary enchant
    elseif aura.buttonInfo and aura.buttonInfo.duration and aura.buttonInfo.duration > 0 then
            aura.border:SetBackdropBorderColor(0, 1, 0, 1)                       -- Green for timed buffs
    else
        aura.border:SetBackdropBorderColor(unpack(C.media.borderColor)) -- Default for permanent buffs
    end
end

local function UpdateCooldownSwipe(aura)
    if aura.buttonInfo and aura.buttonInfo.duration and aura.buttonInfo.duration > 0 then
        local start = aura.buttonInfo.expirationTime - aura.buttonInfo.duration
        aura.cooldown:SetCooldown(start, aura.buttonInfo.duration)
        aura.cooldown:Show()
    else
        aura.cooldown:Hide()
    end
    UpdateBorderColor(aura)
end

local function UpdateAura(aura)
    UpdateCooldownSwipe(aura)
end

----------------------------------------------------------------------------------------
--	Buff Frame Styling and Layout
----------------------------------------------------------------------------------------
hooksecurefunc(BuffFrame.AuraContainer, "UpdateGridLayout", function(self, auras)
    local previousBuff, aboveBuff
    for index, aura in ipairs(auras) do
        -- Set size and template
        aura:SetSize(C.player.buffSize, C.player.buffSize)
        aura:SetTemplate("Zero")

        aura.TempEnchantBorder:SetAlpha(0)
        -- Update the hook for the temporary enchant border (guard to prevent multiple hooks)
        if aura.TempEnchantBorder and not aura._tebHooked then
            hooksecurefunc(aura.TempEnchantBorder, "Show", function(self)
                aura.border:SetBackdropBorderColor(0.6, 0.1, 0.6) -- Set to purple when shown
            end)
            hooksecurefunc(aura.TempEnchantBorder, "Hide", function(self)
                UpdateBorderColor(aura) -- Call UpdateBorderColor to set the correct color when hidden
            end)
            aura._tebHooked = true
        end

        -- Position auras in grid layout
        aura:ClearAllPoints()
        if (index > 1) and ((index - 1) % rowbuffs == 0) then
            aura:SetPoint("TOP", aboveBuff, "BOTTOM", 0, -C.player.buffSpacing)
            aboveBuff = aura
        elseif index == 1 then
            aura:SetPoint("TOPRIGHT", BuffsAnchor, "TOPRIGHT", 0, 0)
            aboveBuff = aura
        else
            aura:SetPoint("RIGHT", previousBuff, "LEFT", -C.player.buffSpacing, 0)
        end

        previousBuff = aura

        -- Style icon
        aura.Icon:CropIcon()
        aura.border:SetFrameStrata("LOW")

		-- Create and configure cooldown swipe
		if not aura.cooldown then
			aura.cooldown = CreateFrame("Cooldown", nil, aura, "CooldownFrameTemplate")
			-- Anchor cooldown to the icon with optional padding to enlarge swipe
			aura.cooldown:ClearAllPoints()
			aura.cooldown:SetPoint("TOPLEFT", aura.Icon, "TOPLEFT", -2, 2)
			aura.cooldown:SetPoint("BOTTOMRIGHT", aura.Icon, "BOTTOMRIGHT", 2, -2)
			aura.cooldown:SetDrawBling(false)
			aura.cooldown:SetDrawEdge(false)
			aura.cooldown:SetReverse(true)
			aura.cooldown:SetFrameLevel(aura:GetFrameLevel() + 1)
			-- Hide Blizzard/OmniCC numbers (we use Blizzard Duration label only)
			aura.cooldown:SetHideCountdownNumbers(true)
			aura.cooldown.noCooldownCount = true -- prevent addons like OmniCC from adding numbers
			-- Default swipe visuals (overridden below if project media available)
			aura.cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8X8", 0, 1, 0, 1)
			aura.cooldown:SetSwipeColor(0, 0, 0, 0.8)
			aura.cooldown._baseSwipeAlpha = 0.8

			-- Match ActionBars’ swipe look & darkness (texture + alpha)
			local function StyleAuraCooldown(cd)
				if not cd or cd:IsForbidden() then return end
				if C.media and C.media.auraCooldown then
					pcall(cd.SetSwipeTexture, cd, C.media.auraCooldown, 0, 1, 0, 1)
				end
				cd:SetSwipeColor(0, 0, 0, cd._baseSwipeAlpha or 0.8)
				cd:SetDrawEdge(false)
				cd:SetDrawSwipe(true)
			end
			StyleAuraCooldown(aura.cooldown)
			if not aura._cooldownStyleHooked then
				hooksecurefunc(aura.cooldown, "SetCooldown", function(self)
					StyleAuraCooldown(self)
				end)
				aura._cooldownStyleHooked = true
			end
		end

        if not aura.iconFrame then
            aura.iconFrame = CreateFrame("Frame", nil, aura)
            aura.iconFrame:SetAllPoints(aura)
            aura.iconFrame:SetFrameLevel(aura.cooldown:GetFrameLevel() + 1)
        end

		-- Configure Blizzard duration text (we do NOT create our own)
        local duration = aura.Duration
        if duration then -- Check if duration exists
            duration:ClearAllPoints()
            duration:SetPoint("CENTER", 0, 0)
            duration:SetParent(aura.iconFrame)
            duration:SetFont(C.media.normalFont, 18, "OUTLINE")
            duration:SetShadowOffset(1, -1)
            duration:SetDrawLayer("OVERLAY") -- Set draw layer to overlay
        end
		-- Ensure no competing numeric overlays (Blizzard/OmniCC)
		if aura.cooldown then
			aura.cooldown:SetHideCountdownNumbers(true) -- hide Blizzard numbers
			aura.cooldown.noCooldownCount = true        -- ask OmniCC to skip this cooldown
		end

        -- Configure stack count
        if aura.Count then
            aura.Count:ClearAllPoints()
            aura.Count:SetPoint("BOTTOMRIGHT", 0, 1)
            aura.Count:SetParent(aura.iconFrame)
            aura.Count:SetFont(C.media.normalFont, 14, "OUTLINE")
            aura.Count:SetShadowOffset(1, -1)
            aura.Count:SetDrawLayer("OVERLAY") -- Set draw layer to overlay
        end

		-- Always hook Blizzard's UpdateDuration to adjust formatting/flash on the SAME text.
		if not aura._durationHooked then
			hooksecurefunc(aura, "UpdateDuration", function(self, timeLeft)
				-- Only show text if your setting asks for it; otherwise hide (no second text anywhere).
				local d = self.Duration
				if not d then return end
				if timeLeft and C.player.buffTimer == true then
					d:SetVertexColor(1, 1, 1)
					d:SetText(GetCompactDurationText(timeLeft))
					d:Show()
					FlashAura(self, timeLeft)  -- alpha pulse near expiry
				else
					d:Hide()
					self:SetAlpha(1)
				end
			end)
			aura._durationHooked = true
		end

        UpdateCooldownSwipe(aura)

        -- Hook Update function for cooldown swipe
        if not aura.updateHook then
            hooksecurefunc(aura, "Update", function(self, buttonInfo)
                self.buttonInfo = buttonInfo
                UpdateAura(self)
            end)
            aura.updateHook = true
        end

        -- Initial update
        UpdateAura(aura)
    end
end)

BuffFrame.Selection:SetAllPoints(BuffsAnchor)
DebuffFrame:Hide()
----------------------------------------------------------------------------------------
--	Hide Default UI Elements
----------------------------------------------------------------------------------------
-- Hide collapse button
BuffFrame.CollapseAndExpandButton:Kill()

-- Hide debuffs
DebuffFrame.AuraContainer:Hide()