local R, C, L = unpack(RefineUI)

----------------------------------------------------------------------------------------
--  AlertFrameMove (by Gethe) — RefineUI adjustments
----------------------------------------------------------------------------------------

-- Anchor where the whole stack will grow from
local AchievementAnchor = CreateFrame("Frame", "AchievementAnchor", UIParent)
AchievementAnchor:SetSize(230, 50)
AchievementAnchor:SetPoint(unpack(C.position.achievement))

-- Subsystems we don't want to reposition/manage
local alertBlacklist = {
	GroupLootContainer = true,
	TalkingHeadFrame   = true,
}

-- Growth state
local POSITION, ANCHOR_POINT, YOFFSET, FIRST_YOFFSET = "BOTTOM", "TOP", -9, -11

-- Ensure initialization runs once even if the file is reloaded
local _alertFramesInitialized = false

-- Determine whether we grow up or down based on the anchor's point
local function CheckGrow()
	local point = AchievementAnchor:GetPoint()
	if string.find(point or "", "TOP") or point == "CENTER" or point == "LEFT" or point == "RIGHT" then
		POSITION      = "TOP"
		ANCHOR_POINT  = "BOTTOM"
		YOFFSET       = 9
		FIRST_YOFFSET = YOFFSET - 2
	else
		POSITION      = "BOTTOM"
		ANCHOR_POINT  = "TOP"
		YOFFSET       = -9
		FIRST_YOFFSET = YOFFSET + 2
	end
end

----------------------------------------------------------------------------------------
--  Border helpers (must be defined before initial UpdateAnchors call)
----------------------------------------------------------------------------------------

local function SetFrameBorderColor(frame, r, g, b)
    if not frame then return end
    local target = frame.border or frame
    if target and target.SetBackdropBorderColor then
        target:SetBackdropBorderColor(r, g, b, 1)
    elseif target and target.SetBorderColor then
        target:SetBorderColor(r, g, b, 1)
    end
end

local function ColorLootBorder(frame, itemLink)
    if not frame or not itemLink then return end

    local function apply(link)
        local _, _, quality = GetItemInfo(link)
        if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
            local c = ITEM_QUALITY_COLORS[quality]
            SetFrameBorderColor(frame, c.r, c.g, c.b)
        end
    end

    local item = Item and Item.CreateFromItemLink and Item:CreateFromItemLink(itemLink)
    if item and item.ContinueOnItemLoad then
        item:ContinueOnItemLoad(function()
            apply(item:GetItemLink())
        end)
    else
        apply(itemLink)
    end
end

-- Ensure Blizzard's Achievement UI (defines AchievementShield_* helpers) is loaded
local function EnsureAchievementUILoaded()
    local loaded = false
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        loaded = C_AddOns.IsAddOnLoaded("Blizzard_AchievementUI")
    else
        local isLoadedFn = rawget(_G, "IsAddOnLoaded")
        if isLoadedFn then
            loaded = isLoadedFn("Blizzard_AchievementUI")
        end
    end

    if not loaded then
		if C_AddOns and C_AddOns.LoadAddOn then
			pcall(C_AddOns.LoadAddOn, "Blizzard_AchievementUI")
		else
			-- Fallback for older clients
            local loader = rawget(_G or {}, "UIParentLoadAddOn") or rawget(_G or {}, "LoadAddOn")
            if loader then pcall(loader, "Blizzard_AchievementUI") end
		end
	end
end

-- Replace anchoring behaviors for different alert subsystems
local ReplaceAnchors
do
	local function QueueAdjustAnchors(self, relativeAlert)
		CheckGrow()
		for alertFrame in self.alertFramePool:EnumerateActive() do
			alertFrame:ClearAllPoints()
			alertFrame:SetPoint(POSITION, relativeAlert, ANCHOR_POINT, 0, YOFFSET)
			relativeAlert = alertFrame
		end
		return relativeAlert
	end

	local function SimpleAdjustAnchors(self, relativeAlert)
		CheckGrow()
		if self.alertFrame:IsShown() then
			self.alertFrame:ClearAllPoints()
			self.alertFrame:SetPoint(POSITION, relativeAlert, ANCHOR_POINT, 0, YOFFSET)
			return self.alertFrame
		end
		return relativeAlert
	end

	local function AnchorAdjustAnchors(self, relativeAlert)
		if self.anchorFrame:IsShown() then
			return self.anchorFrame
		end
		return relativeAlert
	end

	function ReplaceAnchors(alertFrameSubSystem)
		if alertFrameSubSystem.alertFramePool then
			if alertBlacklist[alertFrameSubSystem.alertFramePool.frameTemplate] then
				return alertFrameSubSystem.alertFramePool.frameTemplate, true
			else
				alertFrameSubSystem.AdjustAnchors = QueueAdjustAnchors
			end
		elseif alertFrameSubSystem.alertFrame then
			local frame = alertFrameSubSystem.alertFrame
			if alertBlacklist[frame:GetName()] then
				return frame:GetName(), true
			else
				alertFrameSubSystem.AdjustAnchors = SimpleAdjustAnchors
			end
		elseif alertFrameSubSystem.anchorFrame then
			local frame = alertFrameSubSystem.anchorFrame
			if alertBlacklist[frame:GetName()] then
				return frame:GetName(), true
			else
				alertFrameSubSystem.AdjustAnchors = AnchorAdjustAnchors
			end
		end
	end
end

local function SetUpAlert()
	if _alertFramesInitialized then return end
	_alertFramesInitialized = true

	-- Disable mouse on the group loot container if present (less interference)
	if GroupLootContainer then
		GroupLootContainer:EnableMouse(false)
	end

	-- Make sure growth values are correct before creating our anchor
	CheckGrow()

	-- Separate hard anchor for the Blizzard AlertFrame
	local AlertFrameAnchor = CreateFrame("Frame", "AlertFrameAnchor", UIParent)
	AlertFrameAnchor:SetSize(1, 1)
	AlertFrameAnchor:SetPoint(POSITION, AchievementAnchor, POSITION, 2, FIRST_YOFFSET)

	-- Minimal skin pass (optional)
	local function SkinAlertFrame(frame)
		if not frame or frame.__ruiSkinned then return end
		frame.__ruiSkinned = true

		if frame.Background and frame.Background.SetTexture then
			frame.Background:SetTexture("")
			frame.Background:SetAlpha(0)
		end
		-- Hide Blizzard's icon border; we'll add our own
		local iconBorder = frame.IconBorder or (frame.lootItem and frame.lootItem.IconBorder)
		if iconBorder and iconBorder.SetAlpha then
			iconBorder:SetAlpha(0)
		end
		if frame.shine and frame.shine.SetAlpha then
			frame.shine:SetAlpha(0)
		end
		if frame.glow and frame.glow.SetAlpha then
			frame.glow:SetAlpha(0)
		end
		if frame.SetTemplate then
			frame:SetTemplate("Default")
		end

		-- Create and color a custom border around the icon (loot or achievement)
		local isAchievementToast = (frame.Shield ~= nil) or (frame.Unlocked ~= nil)
		local iconFrame = frame.lootItem or (isAchievementToast and frame.Icon) or nil
		if iconFrame and not iconFrame.__ruiIconBorder then
			iconFrame.__ruiIconBorder = CreateFrame("Frame", nil, iconFrame, "BackdropTemplate")
			iconFrame.__ruiIconBorder:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", -4, 4)
			iconFrame.__ruiIconBorder:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", 4, -4)
			iconFrame.__ruiIconBorder:SetBackdrop({ edgeFile = C.media.border, edgeSize = (C.media and C.media.edgeSize) or 12 })
			iconFrame.__ruiIconBorder:SetBackdropBorderColor(unpack(C.media.borderColor))
			iconFrame.__ruiIconBorder:SetFrameLevel((iconFrame:GetFrameLevel() or 1) + 2)
		end

		-- For achievement toasts, hide Blizzard overlay ring on the icon and crop texture
		if isAchievementToast and frame.Icon then
			if frame.Icon.Overlay and frame.Icon.Overlay.SetAlpha then
				frame.Icon.Overlay:SetAlpha(0)
			end
			if frame.Icon.Bling and frame.Icon.Bling.SetAlpha then
				frame.Icon.Bling:SetAlpha(0)
			end
			if frame.Icon.Texture and frame.Icon.Texture.SetTexCoord then
				frame.Icon.Texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			end
		end

		if iconBorder and not iconBorder.__ruiHooked then
			iconBorder.__ruiHooked = true
			hooksecurefunc(iconBorder, "SetVertexColor", function(_, r, g, b)
				local bdr = iconFrame and iconFrame.__ruiIconBorder
				if bdr and bdr.SetBackdropBorderColor then bdr:SetBackdropBorderColor(r, g, b, 1) end
				-- Also color the toast frame border
				SetFrameBorderColor(frame, r, g, b)
			end)
			hooksecurefunc(iconBorder, "Hide", function()
				local bdr = iconFrame and iconFrame.__ruiIconBorder
				if bdr and C and C.media and C.media.borderColor then bdr:SetBackdropBorderColor(unpack(C.media.borderColor)) end
				if C and C.media and C.media.borderColor then SetFrameBorderColor(frame, unpack(C.media.borderColor)) end
			end)
		end
		local iconTex = frame.Icon and frame.Icon.GetObjectType and frame.Icon:GetObjectType() == "Texture" and frame.Icon
		if iconTex and iconTex.SetTexCoord then
			iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		end

		-- Apply an initial border color immediately after templating
		local iconBorder = frame.IconBorder or (frame.lootItem and frame.lootItem.IconBorder)
		if iconBorder and iconBorder.GetVertexColor and iconBorder:IsShown() then
			local r, g, b = iconBorder:GetVertexColor()
			if r and g and b then
				local bdr = iconFrame and iconFrame.__ruiIconBorder
				if bdr and bdr.SetBackdropBorderColor then bdr:SetBackdropBorderColor(r, g, b, 1) end
				SetFrameBorderColor(frame, r, g, b)
			end
		elseif isAchievementToast then
			-- Achievement-style frame: gold for both toast and icon border
			SetFrameBorderColor(frame, 1.00, 0.82, 0.23)
			local bdr = iconFrame and iconFrame.__ruiIconBorder
			if bdr and bdr.SetBackdropBorderColor then bdr:SetBackdropBorderColor(1.00, 0.82, 0.23, 1) end
		end
	end

	local function SkinAllActiveAlertFrames()
		if not AlertFrame or not AlertFrame.alertFrameSubSystems then return end
		for _, subsystem in ipairs(AlertFrame.alertFrameSubSystems) do
			-- Only skin visible/pooled alert frames; skip bare anchorFrame holders
			if subsystem.alertFramePool then
				for frame in subsystem.alertFramePool:EnumerateActive() do
					SkinAlertFrame(frame)
				end
			elseif subsystem.alertFrame then
				SkinAlertFrame(subsystem.alertFrame)
			end
		end
	end

	hooksecurefunc(AlertFrame, "UpdateAnchors", function(self)
		CheckGrow()
		self:ClearAllPoints()
		self:SetPoint(POSITION, AlertFrameAnchor, POSITION)
		SkinAllActiveAlertFrames()
	end)

	hooksecurefunc(AlertFrame, "AddAlertFrameSubSystem", function(_, alertFrameSubSystem)
		local _, isBlacklisted = ReplaceAnchors(alertFrameSubSystem)
		if isBlacklisted then
			for i, alertSubSystem in ipairs(AlertFrame.alertFrameSubSystems) do
				if alertFrameSubSystem == alertSubSystem then
					table.remove(AlertFrame.alertFrameSubSystems, i)
					break
				end
			end
		end
	end)

	-- Apply replacements and strip blacklisted subsystems on init
	for i = #AlertFrame.alertFrameSubSystems, 1, -1 do
		local _, isBlacklisted = ReplaceAnchors(AlertFrame.alertFrameSubSystems[i])
		if isBlacklisted then
			table.remove(AlertFrame.alertFrameSubSystems, i)
		end
	end

	-- Force a refresh
	AlertFrame:UpdateAnchors()
end

SetUpAlert()

----------------------------------------------------------------------------------------
--  Border colors: Achievements = gold, Loot = rarity color
----------------------------------------------------------------------------------------

local function SetFrameBorderColor(frame, r, g, b)
    if not frame then return end
    local target = frame.border or frame
    if target and target.SetBackdropBorderColor then
        target:SetBackdropBorderColor(r, g, b, 1)
    elseif target and target.SetBorderColor then
        target:SetBorderColor(r, g, b, 1)
    end
end

local function ColorLootBorder(frame, itemLink)
    if not frame or not itemLink then return end

    local function apply(link)
        local _, _, quality = GetItemInfo(link)
        if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
            local c = ITEM_QUALITY_COLORS[quality]
            SetFrameBorderColor(frame, c.r, c.g, c.b)
        end
    end

    -- Use dot when checking for method existence; use colon when calling
    local item = Item and Item.CreateFromItemLink and Item:CreateFromItemLink(itemLink)
    if item and item.ContinueOnItemLoad then
        item:ContinueOnItemLoad(function()
            apply(item:GetItemLink())
        end)
    else
        apply(itemLink)
    end
end

-- Coloring is applied in SkinAlertFrame via icon border mirroring


----------------------------------------------------------------------------------------
--  Testing utility: /refinealerts [money|loot|ach] [count]
----------------------------------------------------------------------------------------

local function SpawnTestAlerts(kind, count)
	count = tonumber(count) or 3
	if count <= 0 then return end

	kind              = tostring(kind or "money"):lower()

	local moneySystem = rawget(_G, "MoneyWonAlertSystem")
	local lootSystem  = rawget(_G, "LootWonAlertSystem")
	local achSystem   = rawget(_G, "AchievementAlertSystem")

	-- MONEY
	if kind == "money" and moneySystem and moneySystem.AddAlert then
		for i = 1, count do
			local amount = 12345 * i
			C_Timer.After(0.12 * (i - 1), function()
				if moneySystem and moneySystem.AddAlert then
					moneySystem:AddAlert(amount)
				end
			end)
		end
		return
	end

	-- LOOT (use LootAlertSystem, not LootWon; ensure cached link)
    -- Prefer the system present on this client
    local lootAddSystem = rawget(_G, "LootWonAlertSystem") or rawget(_G, "LootAlertSystem")
    if kind == "loot" and lootAddSystem and lootAddSystem.AddAlert then
		local function getSpecID()
			-- Prefer explicit loot spec if set; otherwise current spec
			local ls = GetLootSpecialization and GetLootSpecialization()
			if ls and ls > 0 then return ls end
			if GetSpecialization and GetSpecialization() then
				local id = select(1, GetSpecializationInfo(GetSpecialization()))
				return id
			end
		end

		local function spawnLootToast(itemID, qty)
			local item = Item:CreateFromItemID(itemID)
			item:ContinueOnItemLoad(function()
				local link = item:GetItemLink()
				local specID = getSpecID()
                if rawget(_G, "LootWonAlertSystem") and lootAddSystem == _G.LootWonAlertSystem then
                    lootAddSystem:AddAlert(link, qty or 1)
                else
                    lootAddSystem:AddAlert(link, qty or 1, specID)
                end
			end)
		end

		-- Prefer a real bag item (guarantees cache)
		local chosenID
		if C_Container and C_Container.GetContainerNumSlots then
			for bag = 0, 4 do
				for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
					local info = C_Container.GetContainerItemInfo(bag, slot)
					if info and info.itemID then
						chosenID = info.itemID
						break
					end
				end
				if chosenID then break end
			end
		end
		chosenID = chosenID or 171267 -- fallback itemID

        for i = 1, count do
            C_Timer.After(0.12 * (i - 1), function() spawnLootToast(chosenID, 1) end)
        end
		return
	end


	-- ACHIEVEMENTS (load Blizzard_AchievementUI first)
	if kind == "ach" and achSystem and achSystem.AddAlert then
		EnsureAchievementUILoaded()

		local ids = { 6, 7, 8, 9, 10 } -- simple old achievements; any valid IDs work
		for i = 1, math.min(count, #ids) do
			local id = ids[i]
			C_Timer.After(0.12 * (i - 1), function()
				if achSystem and achSystem.AddAlert then
					achSystem:AddAlert(id)
				end
			end)
		end
		return
	end
end

SLASH_REFINEALERTS1 = "/refinealerts"
SlashCmdList["REFINEALERTS"] = function(msg)
	local a, b  = msg:match("%s*(%S*)%s*(%S*)")
	local kind  = (a ~= "" and a) or "money"
	local count = tonumber(b) or tonumber(a) or 3
	SpawnTestAlerts(kind, count)
end
