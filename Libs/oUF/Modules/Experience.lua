--[[ Home:header
# Element: Experience

Adds support for an element that updates and displays the player's experience or honor as a
StatusBar widget.

## Widgets

- `Experience`
	A statusbar which displays the player's current experience or honor until the next level.  
	Has drop-in support for `AnimatedStatusBarTemplate`.
- `Experience.Rested`
	An optional background-layered statusbar which displays the exhaustion the player current has.  
	**Must** be parented to the `Experience` widget if used.

## Options

- `inAlpha` - Alpha used when the mouse is over the element (default: `1`)
- `outAlpha` - Alpha used when the mouse is outside of the element (default: `1`)
- `restedAlpha` - Alpha used for the `Rested` sub-widget (default: `0.15`)
- `tooltipAnchor` - Anchor for the tooltip (default: `"ANCHOR_BOTTOMRIGHT"`)

## Extras

- [Callbacks](Callbacks)
- [Overrides](Overrides)
- [Tags](Tags)

## Colors

This plug-in adds colors for experience (normal and rested) as well as honor.  
Accessible through `oUF.colors.experience` and `oUF.colors.honor`.

## Notes

- A default texture will be applied if the widget(s) is a StatusBar and doesn't have a texture set.
- Tooltip and mouse interaction options are only enabled if the element is mouse-enabled.
- Backgrounds/backdrops **must** be parented to the `Rested` sub-widget if used.
- Toggling honor-tracking is done through the PvP UI
- Remember to set the plug-in as an optional dependency for the layout if not embedding.

## Example implementation

```lua
-- Position and size
local Experience = CreateFrame('StatusBar', nil, self)
Experience:SetPoint('BOTTOM', 0, -50)
Experience:SetSize(200, 20)
Experience:EnableMouse(true) -- for tooltip/fading support

-- Position and size the Rested sub-widget
local Rested = CreateFrame('StatusBar', nil, Experience)
Rested:SetAllPoints(Experience)

-- Text display
local Value = Experience:CreateFontString(nil, 'OVERLAY')
Value:SetAllPoints(Experience)
Value:SetFontObject(GameFontHighlight)
self:Tag(Value, '[experience:cur] / [experience:max]')

-- Add a background
local Background = Rested:CreateTexture(nil, 'BACKGROUND')
Background:SetAllPoints(Experience)
Background:SetTexture('Interface\\ChatFrame\\ChatFrameBackground')

-- Register with oUF
self.Experience = Experience
self.Experience.Rested = Rested
```
--]]

local _, addon = ...
local oUF = (addon and addon.oUF) or rawget(_G, 'oUF')
if not oUF then return end

oUF.colors.experience = {
	oUF:CreateColor(0.58, 0, 0.55), -- Normal
	oUF:CreateColor(0, 0.39, 0.88), -- Rested
}

oUF.colors.honor = {
	oUF:CreateColor(1, 0.71, 0), -- Normal
}

oUF.colors.renown = {
	oUF:CreateColor(0.4, 0.2, 0.8), -- Default Renown purple
}

oUF.colors.reputation = {
	oUF:CreateColor(0, 0.6, 1), -- Default Reputation blue
}

-- Define Renown Events
local RENOWN_EVENTS = {
    "MAJOR_FACTION_RENOWN_LEVEL_CHANGED",
    "MAJOR_FACTION_UNLOCKED",
}

-- Forward declare getValues for tag scope
local getValues

--[[ Tags:header
A few basic tags are included:
- `[experience:cur]`       - the player's current experience/honor
- `[experience:max]`       - the player's maximum experience/honor
- `[experience:per]`       - the player's percentage of experience/honor in to the current level
- `[experience:level]`     - the player's current experience/honor level
- `[experience:currested]` - the player's current exhaustion
- `[experience:perrested]` - the player's percentage of exhaustion

See the [Examples](./#example-implementation) section on how to use the tags.
--]]

local function getValues()
    -- Determine player state
    local pLevel = UnitLevel('player')
    local maxLevel = GetMaxLevelForPlayerExpansion()
    local maxPlayerLevel = rawget(_G, 'MAX_PLAYER_LEVEL') or 0
    if maxLevel == 0 and maxPlayerLevel > 0 then maxLevel = maxPlayerLevel end
    local pIsMaxLevel = pLevel >= maxLevel

    -- 1. Check for faction explicitly watched via "Show as Experience Bar"
    local watchedFactionData = C_Reputation.GetWatchedFactionData()
    if watchedFactionData and watchedFactionData.isWatched then
        local name = rawget(watchedFactionData, 'name')
        local factionID = rawget(watchedFactionData, 'factionID')

        -- Compute reputation progress using thresholds
        local reaction = rawget(watchedFactionData, 'reaction') or 0
        local currentStanding = rawget(watchedFactionData, 'currentStanding') or 0
        local currentThreshold = rawget(watchedFactionData, 'currentReactionThreshold') or 0
        local nextThreshold = rawget(watchedFactionData, 'nextReactionThreshold')
        local cur = math.max(0, currentStanding - currentThreshold)
        local max = (nextThreshold and (nextThreshold - currentThreshold)) or 1
        if max <= 0 then max = 1 end -- Prevent division by zero
        if cur > max then cur = max end
        local perc = math.floor(cur / max * 100 + 0.5)

        -- Determine if it's a Major Faction (Renown)
        local C_MajorFactions = rawget(_G, 'C_MajorFactions')
        if C_MajorFactions and C_MajorFactions.GetMajorFactionData and factionID then
            local majorFactionData = C_MajorFactions.GetMajorFactionData(factionID)
            if majorFactionData and majorFactionData.renownLevel then
                local rCur = majorFactionData.renownReputationEarned or 0
                local rMax = majorFactionData.renownLevelThreshold or 1
                if rMax <= 0 then rMax = 1 end
                if rCur > rMax then rCur = rMax end
                local rPerc = math.floor(rCur / rMax * 100 + 0.5)
                return rCur, rMax, rPerc, 0, 0, majorFactionData.renownLevel, "renown", majorFactionData.name or name
            end
        end

        -- Not a Major Faction: return Reputation with standing text
        local standingText = _G['FACTION_STANDING_LABEL' .. reaction] or tostring(reaction)
        return cur, max, perc, 0, 0, standingText, "reputation", name
    end

    -- If nothing explicitly watched, continue with other checks...

    -- 2. Smart renown auto-selection: find the closest-to-next-level renown (only at max level)
    if pIsMaxLevel then
        local C_MajorFactions = rawget(_G, 'C_MajorFactions')
        if C_MajorFactions and C_MajorFactions.GetMajorFactionIDs then
            local bestRenown = nil
            local bestProgress = -1
            local currentExpansionID = GetExpansionLevel and GetExpansionLevel() or GetMaxLevelForLatestExpansion and GetMaxLevelForLatestExpansion() or 10 -- fallback to current
            
            local majorFactionIDs = C_MajorFactions.GetMajorFactionIDs() or {}
            for _, factionID in ipairs(majorFactionIDs) do
                local majorFactionData = C_MajorFactions.GetMajorFactionData(factionID)
                if majorFactionData and majorFactionData.isUnlocked and not majorFactionData.isMaxLevel then
                    -- Only consider factions from current expansion
                    local expansionID = majorFactionData.expansionID or 0
                    if expansionID == currentExpansionID then
                        local rCur = majorFactionData.renownReputationEarned or 0
                        local rMax = majorFactionData.renownLevelThreshold or 1
                        if rMax > 0 then
                            local progress = rCur / rMax
                            -- Prefer higher progress (closer to next level)
                            if progress > bestProgress then
                                bestProgress = progress
                                bestRenown = majorFactionData
                            end
                        end
                    end
                end
            end
            
            if bestRenown then
                local rCur = bestRenown.renownReputationEarned or 0
                local rMax = bestRenown.renownLevelThreshold or 1
                if rMax <= 0 then rMax = 1 end
                if rCur > rMax then rCur = rMax end
                local rPerc = math.floor(rCur / rMax * 100 + 0.5)
                return rCur, rMax, rPerc, 0, 0, bestRenown.renownLevel, "renown", bestRenown.name
            end
        end
    end

    -- 3. Check for Honor (only at max level, if not showing Renown/Reputation)
    local pIsMaxHonorLevel = C_PvP and C_PvP.GetNextHonorLevelForReward and not C_PvP.GetNextHonorLevelForReward(UnitHonorLevel('player'))
    local shouldShowHonorBar = pIsMaxLevel and IsWatchingHonorAsXP()
    if shouldShowHonorBar and not pIsMaxHonorLevel then
        local cur = UnitHonor('player')
        local max = UnitHonorMax('player') or 1
        if max <= 0 then max = 1 end
        local level = UnitHonorLevel('player')
        local perc = math.floor(cur / max * 100 + 0.5)
        return cur, max, perc, 0, 0, level, "honor", nil
    end

    -- 4. Default to Experience (if not max level)
    if not pIsMaxLevel then
        local cur = UnitXP('player')
        local max = UnitXPMax('player') or 1
        if max <= 0 then max = 1 end
        local rested = GetXPExhaustion() or 0
        local perc = math.floor(cur / max * 100 + 0.5)
        local restedPerc = math.floor(rested / max * 100 + 0.5)
        return cur, max, perc, rested, restedPerc, pLevel, "experience", nil
    end

    -- 5. Fallback: At max level, display data from GetWatchedFactionData even if not explicitly watched
    if pIsMaxLevel then
        -- Re-fetch watched data, maybe it exists even if isWatched was false earlier
        local fallbackWatchedData = C_Reputation.GetWatchedFactionData()
        if fallbackWatchedData then
            local name = rawget(fallbackWatchedData, 'name')
            local factionID = rawget(fallbackWatchedData, 'factionID')

            local reaction = rawget(fallbackWatchedData, 'reaction') or 0
            local currentStanding = rawget(fallbackWatchedData, 'currentStanding') or 0
            local currentThreshold = rawget(fallbackWatchedData, 'currentReactionThreshold') or 0
            local nextThreshold = rawget(fallbackWatchedData, 'nextReactionThreshold')
            local cur = math.max(0, currentStanding - currentThreshold)
            local max = (nextThreshold and (nextThreshold - currentThreshold)) or 1
            if max <= 0 then max = 1 end
            if cur > max then cur = max end
            local perc = math.floor(cur / max * 100 + 0.5)

            -- Check for Major Faction (Renown)
            local C_MajorFactions = rawget(_G, 'C_MajorFactions')
            if C_MajorFactions and C_MajorFactions.GetMajorFactionData and factionID then
                local majorFactionData = C_MajorFactions.GetMajorFactionData(factionID)
                if majorFactionData and majorFactionData.renownLevel then
                    local rCur = majorFactionData.renownReputationEarned or 0
                    local rMax = majorFactionData.renownLevelThreshold or 1
                    if rMax <= 0 then rMax = 1 end
                    if rCur > rMax then rCur = rMax end
                    local rPerc = math.floor(rCur / rMax * 100 + 0.5)
                    return rCur, rMax, rPerc, 0, 0, majorFactionData.renownLevel, "renown", majorFactionData.name or name
                end
            end

            local standingText = _G['FACTION_STANDING_LABEL' .. reaction] or tostring(reaction)
            return cur, max, perc, 0, 0, standingText, "reputation", name
        end
    end

    -- Final fallback if absolutely nothing else applies
    return 0, 1, 0, 0, 0, pLevel, "none", nil
end

for tag, func in next, {
	['experience:cur'] = function(unit)
        if unit ~= 'player' then return 0 end
		local cur = select(1, getValues()) -- Use select to avoid unpack returning multiple values
        return cur or 0
	end,
	['experience:max'] = function(unit)
        if unit ~= 'player' then return 1 end
        local max = select(2, getValues())
		return max or 1
	end,
	['experience:per'] = function(unit)
        if unit ~= 'player' then return 0 end
        local cur, max = (oUF.Tags.Methods and oUF.Tags.Methods['experience:cur'] and oUF.Tags.Methods['experience:cur'](unit)) or 0,
                         (oUF.Tags.Methods and oUF.Tags.Methods['experience:max'] and oUF.Tags.Methods['experience:max'](unit)) or 1
        if max and max > 0 then
		    return math.floor(cur / max * 100 + 0.5)
        else
            return 0
        end
	end,
	['experience:level'] = function(unit)
        if unit ~= 'player' then return 0 end
        local level, barType, name = select(6, getValues()) -- Get level, type, name
        -- Special handling for reputation 'level' which is standing text
        if barType == "reputation" then
             local watchedFactionData = C_Reputation.GetWatchedFactionData()
             if watchedFactionData then
                 local reaction = watchedFactionData.reaction or 0
                 local standingText = _G['FACTION_STANDING_LABEL' .. reaction]
                 return standingText or (level or 0)
             end
             return level or 0
        end
		return level or 0
	end,
	['experience:currested'] = function(unit)
        if unit ~= 'player' then return nil end
        local rested, barType = select(4, getValues()) -- Get rested, type
        -- Only return rested if the bar is actually showing experience
		return (barType == "experience") and rested or nil
	end,
	['experience:perrested'] = function(unit)
        if unit ~= 'player' then return nil end
        local rested = (oUF.Tags.Methods and oUF.Tags.Methods['experience:currested'] and oUF.Tags.Methods['experience:currested'](unit)) or nil
		if(rested and rested > 0) then
            local max = (oUF.Tags.Methods and oUF.Tags.Methods['experience:max'] and oUF.Tags.Methods['experience:max'](unit)) or 1
            if max and max > 0 then
			    return math.floor(rested / max * 100 + 0.5)
            end
		end
        return nil -- Return nil if no rested applies or max is 0
	end,
} do
	oUF.Tags.Methods[tag] = func
    -- Update relevant events for tags. Should cover all bar types now.
	oUF.Tags.Events[tag] = table.concat({
        'PLAYER_XP_UPDATE', 'UPDATE_EXHAUSTION', 'HONOR_XP_UPDATE',
        'ZONE_CHANGED', 'ZONE_CHANGED_NEW_AREA', 'UPDATE_FACTION',
        'PLAYER_LEVEL_UP', 'HONOR_LEVEL_UPDATE'
    }, ' ') .. ' ' .. table.concat(RENOWN_EVENTS, ' ')
end

local function UpdateTooltip(element)
    local cur, max, perc, rested, restedPerc, level, barType, name = getValues()

    local title = ""
    local line = ""
    local restedLine = nil

    if barType == "renown" then
        local RENOWN = rawget(_G, 'RENOWN') or 'Renown'
        local RENOWN_LEVEL_LABEL = rawget(_G, 'RENOWN_LEVEL_LABEL') or 'Level %d'
        title = string.format("%s - %s", name or RENOWN, string.format(RENOWN_LEVEL_LABEL, level or 0))
        line = string.format("%s / %s (%d%%)", BreakUpLargeNumbers(cur or 0), BreakUpLargeNumbers(max or 1), perc or 0)
    elseif barType == "reputation" then
        title = string.format("%s - %s", name or REPUTATION, level or "") -- level is standingText here
        line = string.format("%s / %s (%d%%)", BreakUpLargeNumbers(cur or 0), BreakUpLargeNumbers(max or 1), perc or 0)
    elseif barType == "honor" then
        title = HONOR_LEVEL_LABEL:format(level or 0)
        line = string.format("%s / %s (%d%%)", BreakUpLargeNumbers(cur or 0), BreakUpLargeNumbers(max or 1), perc or 0)
    elseif barType == "experience" then
        title = COMBAT_XP_GAIN
        line = string.format("%s / %s (%d%%)", BreakUpLargeNumbers(cur or 0), BreakUpLargeNumbers(max or 1), perc or 0)
        if rested and rested > 0 then
            restedLine = string.format("%s: %s (%d%%)", TUTORIAL_TITLE26, BreakUpLargeNumbers(rested), restedPerc or 0)
        end
    else -- "none" or fallback
        GameTooltip:Hide()
        return
    end

    GameTooltip:SetText(title, 1, 1, 1)
    GameTooltip:AddLine(line, 1, 1, 1)
    if restedLine then
        GameTooltip:AddLine(restedLine, 0, 1, 0) -- Use different color for rested line
    end

    GameTooltip:Show()
end

local function OnEnter(element)
	element:SetAlpha(element.inAlpha)
	GameTooltip:SetOwner(element, element.tooltipAnchor)

	--[[ Overrides:header
	### element:OverrideUpdateTooltip()

	Used to completely override the internal function for updating the tooltip.

	- `self` - the Experience element
	--]]
	if element.OverrideUpdateTooltip then
		element:OverrideUpdateTooltip()
	else
		UpdateTooltip(element)
	end
end

local function OnLeave(element)
	GameTooltip:Hide()
	element:SetAlpha(element.outAlpha)
end

local function UpdateColor(element, barType, isRested)
    local colorTbl
    local ownerColors = element.__owner.colors

    if barType == "renown" then
        colorTbl = ownerColors.renown[1]
    elseif barType == "reputation" then
        colorTbl = ownerColors.reputation[1]
    elseif barType == "honor" then
        colorTbl = ownerColors.honor[1]
    elseif barType == "experience" then
        colorTbl = ownerColors.experience[isRested and 2 or 1] -- Use rested color if applicable
    else -- Default/fallback color (e.g., grey)
        element:SetStatusBarColor(0.5, 0.5, 0.5)
        if element.SetAnimatedTextureColors then
            element:SetAnimatedTextureColors(0.5, 0.5, 0.5)
        end
        if element.Rested then
            element.Rested:SetStatusBarColor(0.5, 0.5, 0.5, element.restedAlpha)
        end
        return
    end

    local r, g, b = colorTbl:GetRGB()
    element:SetStatusBarColor(r, g, b)
    if element.SetAnimatedTextureColors then
        element:SetAnimatedTextureColors(r, g, b)
    end

    -- Rested bar only applies to experience
    if element.Rested then
        if barType == "experience" and isRested then
            local restedColor = ownerColors.experience[2]
            local restedR, restedG, restedB = restedColor:GetRGB()
            element.Rested:SetStatusBarColor(restedR, restedG, restedB, element.restedAlpha)
            element.Rested:Show()
        else
            element.Rested:Hide()
        end
    end
end

local function Update(self, event, unit)
	if self.unit ~= unit or unit ~= 'player' then
		return
	end

	local element = self.Experience
	if not element then return end

	--[[ Callbacks:header
	### element:PreUpdate(_unit_)

	Called before the element has been updated.

	- `self` - the Experience element
	- `unit` - the unit for which the update has been triggered _(string)_
	--]]
	if element.PreUpdate then
		element:PreUpdate(unit)
	end

    -- Get all relevant values
    local cur, max, perc, rested, restedPerc, level, barType, name = getValues()

    -- Update main status bar
    if element.SetAnimatedValues then
        element:SetAnimatedValues(cur, 0, max, level) -- Pass level for potential animation logic
    else
        element:SetMinMaxValues(0, max)
        element:SetValue(cur)
    end

    -- Update rested status bar (only for experience)
    if element.Rested then
        if barType == "experience" and rested and rested > 0 then
            element.Rested:SetMinMaxValues(0, max)
            -- The rested value represents *bonus* XP, so add it to current for display
            element.Rested:SetValue(math.min(cur + rested, max))
            element.Rested:Show()
        else
            element.Rested:Hide()
        end
    end

    -- Update colors
    --[[ Overrides:header
    ### element:OverrideUpdateColor(_barType, isRested_)

    Used to completely override the internal function for updating the widget's colors.

    - `self`     - the Experience element
    - `barType`  - indicates the type of bar being displayed ("renown", "reputation", "honor", "experience", "none") _(string)_
    - `isRested` - indicates if the player has any exhaustion (only relevant for "experience") _(boolean)_
    --]]
    (element.OverrideUpdateColor or UpdateColor)(element, barType, rested and rested > 0)

    -- Ensure any oUF tags attached to this frame refresh alongside the bar
    if self.UpdateTags then
        self:UpdateTags()
    end

    --[[ Callbacks:header
    ### element:PostUpdate(_unit, cur, max, rested, level, barType, name_)

    Called after the element has been updated.

    - `self`    - the Experience element
    - `unit`    - the unit for which the update has been triggered _(string)_
    - `cur`     - the player's current value (Renown/Rep/Honor/XP) _(number)_
    - `max`     - the player's maximum value for the current level (Renown/Rep/Honor/XP) _(number)_
    - `rested`  - the player's current exhaustion (only non-zero if barType is "experience") _(number)_
    - `level`   - the player's current level (Renown/Rep Standing/Honor/XP) _(number|string)_
    - `barType` - indicates the type of bar being displayed ("renown", "reputation", "honor", "experience", "none") _(string)_
    - `name`    - the name of the Renown/Reputation faction, if applicable _(string|nil)_
    --]]
    if element.PostUpdate then
		-- Pass the comprehensive set of values
		return element:PostUpdate(unit, cur, max, rested, level, barType, name)
	end
end

local function Path(self, ...)
	--[[ Overrides:header
	### element.Override(_self, event, unit_)

	Used to completely override the internal update function.  
	Overriding this function also disables the [Callbacks](Callbacks).

	- `self`  - the parent object
	- `event` - the event triggering the update _(string)_
	- `unit`  - the unit accompanying the event _(variable(s))_
	--]]
	return (self.Experience.Override or Update)(self, ...)
end

local function ElementEnable(self)
	local element = self.Experience
    if not element then return end

	self:RegisterEvent('PLAYER_XP_UPDATE', Path, true)
	self:RegisterEvent('HONOR_XP_UPDATE', Path, true)
	self:RegisterEvent('ZONE_CHANGED', Path, true)
	self:RegisterEvent('ZONE_CHANGED_NEW_AREA', Path, true)
    self:RegisterEvent('UPDATE_FACTION', Path, true) -- For watched reputation changes

    -- Register Renown events
    for _, eventName in ipairs(RENOWN_EVENTS) do
    -- Guard against client flavors missing certain events
    pcall(self.RegisterEvent, self, eventName, Path, true)
    end

	if element.Rested then
		self:RegisterEvent('UPDATE_EXHAUSTION', Path, true)
	end

	element:Show()
	element:SetAlpha(element.outAlpha or 1)

	Path(self, 'ElementEnable', 'player')
end

local function ElementDisable(self)
    local element = self.Experience
    if not element then return end

	self:UnregisterEvent('PLAYER_XP_UPDATE', Path)
	self:UnregisterEvent('HONOR_XP_UPDATE', Path)
	self:UnregisterEvent('ZONE_CHANGED', Path)
	self:UnregisterEvent('ZONE_CHANGED_NEW_AREA', Path)
    self:UnregisterEvent('UPDATE_FACTION', Path)

    -- Unregister Renown events
    for _, eventName in ipairs(RENOWN_EVENTS) do
    pcall(self.UnregisterEvent, self, eventName, Path)
    end

	if element.Rested then
		self:UnregisterEvent('UPDATE_EXHAUSTION', Path)
	end

	element:Hide()

	-- No need to call Path here, as the element is hidden
end

local function Visibility(self, event, unit)
    -- Only react to player unit events or specific non-unit events
    if unit and unit ~= "player" and event ~= 'UPDATE_FACTION' and not tContains(RENOWN_EVENTS, event) then
        return
    end

    local element = self.Experience
    if not element then return end

    local shouldEnable = false
    if not UnitHasVehicleUI('player') then
        local _, _, _, _, _, _, barType = getValues()
        -- Enable if getValues determined a valid bar type other than "none"
        if barType and barType ~= "none" then
            -- Additional check for experience: don't show if XP is disabled
            if barType == "experience" and IsXPUserDisabled() then
                shouldEnable = false
            else
                shouldEnable = true
            end
        end
    end

    -- Check if the state actually changed
    local isCurrentlyEnabled = self:IsEventRegistered('PLAYER_XP_UPDATE', Path)

    if shouldEnable and not isCurrentlyEnabled then
        ElementEnable(self)
    elseif not shouldEnable and isCurrentlyEnabled then
        ElementDisable(self)
    elseif shouldEnable and isCurrentlyEnabled then
        -- If already enabled, still force an update check in case the *type* of bar changed
        Path(self, event or 'VisibilityCheck', unit or 'player')
    end
end

local function VisibilityPath(self, ...)
	--[[ Overrides:header
	### element.OverrideVisibility(_self, event, unit_)

	Used to completely override the element's visibility update process.  
	The internal function is also responsible for (un)registering events related to the updates.

	- `self`  - the parent object
	- `event` - the event triggering the update _(string)_
	- `unit`  - the unit accompanying the event _(variable(s))_
	--]]
	return (self.Experience.OverrideVisibility or Visibility)(self, ...)
end

local function ForceUpdate(element)
	return VisibilityPath(element.__owner, 'ForceUpdate', element.__owner.unit)
end

local function Enable(self, unit)
	local element = self.Experience
	if element and unit == 'player' then
		element.__owner = self

		element.ForceUpdate = ForceUpdate
		element.restedAlpha = element.restedAlpha or 0.15

		self:RegisterEvent('PLAYER_LEVEL_UP', VisibilityPath, true)
		self:RegisterEvent('HONOR_LEVEL_UPDATE', VisibilityPath, true)
		self:RegisterEvent('DISABLE_XP_GAIN', VisibilityPath, true)
		self:RegisterEvent('ENABLE_XP_GAIN', VisibilityPath, true)
		self:RegisterEvent('UPDATE_EXPANSION_LEVEL', VisibilityPath, true)
		self:RegisterEvent('UPDATE_FACTION', VisibilityPath, true)

		hooksecurefunc('SetWatchingHonorAsXP', function()
			if self:IsElementEnabled('Experience') then
				VisibilityPath(self, 'SetWatchingHonorAsXP', 'player')
                if self.UpdateTags then self:UpdateTags() end
			end
		end)

        -- When the watched faction changes via Reputation UI, force visibility + tag refresh
        if rawget(_G, 'SetWatchedFactionIndex') then
            hooksecurefunc('SetWatchedFactionIndex', function()
                if self:IsElementEnabled('Experience') then
                    VisibilityPath(self, 'SetWatchedFactionIndex', 'player')
                    if self.UpdateTags then self:UpdateTags() end
                end
            end)
        end

		local child = element.Rested
		if child then
			child:SetFrameLevel(element:GetFrameLevel() - 1)

			if not child:GetStatusBarTexture() then
				child:SetStatusBarTexture([[Interface\TargetingFrame\UI-StatusBar]])
			end
		end

		if not element:GetStatusBarTexture() then
			element:SetStatusBarTexture([[Interface\TargetingFrame\UI-StatusBar]])
		end

		if element:IsMouseEnabled() then
			element.tooltipAnchor = element.tooltipAnchor or 'ANCHOR_BOTTOMRIGHT'
			element.inAlpha = element.inAlpha or 1
			element.outAlpha = element.outAlpha or 1

			if not element:GetScript('OnEnter') then
				element:SetScript('OnEnter', OnEnter)
			end

			if not element:GetScript('OnLeave') then
				element:SetScript('OnLeave', OnLeave)
			end
		end

		return true
	end
end

local function Disable(self)
	local element = self.Experience
	if element then
		self:UnregisterEvent('PLAYER_LEVEL_UP', VisibilityPath)
		self:UnregisterEvent('HONOR_LEVEL_UPDATE', VisibilityPath)
		self:UnregisterEvent('DISABLE_XP_GAIN', VisibilityPath)
		self:UnregisterEvent('ENABLE_XP_GAIN', VisibilityPath)
		self:UnregisterEvent('UPDATE_EXPANSION_LEVEL', VisibilityPath)

		ElementDisable(self)
	end
end

oUF:AddElement('Experience', VisibilityPath, Enable, Disable)
