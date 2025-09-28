local R, C, L = unpack(RefineUI)
local _G = _G

-- Localize frequently used functions and common tables
local CreateFrame, hooksecurefunc, pairs, ipairs, select = CreateFrame, hooksecurefunc, pairs, ipairs, select
local CF, CM, BORDER = C.font, C.media, C.media.borderColor
local actionbarsSetup = false
local _pressedBorderColor = {1, 1, 1, 1} -- white when pressed

-- Centralized button prefix sets (shared across modules via R)
if not R.ActionBarPrimaryPrefixes then
    R.ActionBarPrimaryPrefixes = {
        "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
        "MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button",
        "MultiBar6Button", "MultiBar7Button",
    }
end
if not R.ActionBarAllPrefixes then
    local t = {}
    for i, v in ipairs(R.ActionBarPrimaryPrefixes) do t[i] = v end
    t[#t+1] = "PetActionButton"; t[#t+1] = "StanceButton"; t[#t+1] = "OverrideActionBarButton"; t[#t+1] = "ExtraActionButton"
    R.ActionBarAllPrefixes = t
end

-- Ensure a per-button overlay container that sits above the styled border
local function EnsureCooldownOverlay(parent)
    if parent.__RefineCooldownOverlay then return parent.__RefineCooldownOverlay end
    local overlay = CreateFrame("Frame", nil, parent)
    overlay:SetAllPoints(parent)
    -- Use a high strata to guarantee it draws above the border frame (Style.lua sets MEDIUM)
    overlay:SetFrameStrata("DIALOG")
    overlay:SetFrameLevel((parent:GetFrameLevel() or 0) + 60)
    overlay:EnableMouse(false)
    parent.__RefineCooldownOverlay = overlay
    -- Keep level roughly in sync if the parent changes
    if not parent.__RefineCooldownOverlaySynced then
        parent:HookScript("OnShow", function(p)
            local ov = p.__RefineCooldownOverlay
            if ov then ov:SetFrameLevel((p:GetFrameLevel() or 0) + 60) end
        end)
        parent.__RefineCooldownOverlaySynced = true
    end
    return overlay
end

-- Initialize hotkey element as hidden without permanently disabling updates
local function NeutralizeKeybind(button)
    if not button then return end
    local hotkey = button.HotKey or (button.GetName and _G[button:GetName() .. "HotKey"]) or nil
    if not hotkey then return end
    -- Clear current text and hide initially; allow hooks to re-show/configure
    hotkey:SetText("")
    hotkey:Hide()
end

-- Fast check for whether a frame name belongs to an action bar button we manage
local function IsManagedActionButtonName(name)
    if not name then return false end
    local prefixes = R.ActionBarAllPrefixes
    for i = 1, #prefixes do
        local p = prefixes[i]
        if name:find(p, 1, true) == 1 then
            return true
        end
    end
    return false
end

local function StyleButton(button)
    if button.isSkinned then return end

    button:SetTemplate("Zero")

    local name = button:GetName()
    local icon = _G[name .. "Icon"]
    local count = _G[name .. "Count"]

    -- Set up the icon
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)

    -- Ensure count is on top
    count:SetParent(button)
	count:SetJustifyH("RIGHT")
    count:SetPoint("BOTTOMRIGHT", -3, 3)
    count:SetDrawLayer("OVERLAY", 1)

    -- Cooldown styling is handled centrally via the global cooldown metatable hook

    -- Remove keybind text permanently for this button
    NeutralizeKeybind(button)

    -- Hide Blizzard's "pressed" overlay; we'll handle the press visual ourselves
    if button.PushedTexture then
        button.PushedTexture:SetAlpha(0)
    elseif button.GetPushedTexture then
        local pt = button:GetPushedTexture()
        if pt then pt:SetAlpha(0) end
    end

    -- Pre-create a holder for original border color so we can restore after press
    do
        local br = button.border
        if br and br.GetBackdropBorderColor then
            local r, g, b, a = br:GetBackdropBorderColor()
            button.__RefineOriginalBorder = { r, g, b, a }
        else
            button.__RefineOriginalBorder = button.__RefineOriginalBorder or { unpack(BORDER) }
        end
    end

    -- Lazily create a tiny shake animation; reused on every press
    if not button.__RefineShake then
        local ag = button:CreateAnimationGroup()
        local a1 = ag:CreateAnimation("Translation"); a1:SetOffset(3, -3);  a1:SetDuration(0.05); a1:SetOrder(1); a1:SetSmoothing("IN")
        local a2 = ag:CreateAnimation("Translation"); a2:SetOffset(-3, 3);  a2:SetDuration(0.10); a2:SetOrder(2)
        local a3 = ag:CreateAnimation("Translation"); a3:SetOffset(0, 0);   a3:SetDuration(0.05); a3:SetOrder(3)
        ag:SetLooping("NONE")
        button.__RefineShake = ag
    end

    -- Helper to apply/remove our pressed visuals (called from hooks below)
    if not button.__RefineSetPressedVisual then
        button.__RefineSetPressedVisual = function(self, pressed)
            local border = self.border
            if pressed then
                if self.__RefineShake then self.__RefineShake:Stop(); self.__RefineShake:Play() end
                if border and border.GetBackdropBorderColor then
                    local r, g, b, a = border:GetBackdropBorderColor()
                    self.__RefineRestoreBorder = { r, g, b, a }
                    border:SetBackdropBorderColor(unpack(_pressedBorderColor))
                end
            else
                local border = self.border
                if border and self.__RefineRestoreBorder then
                    border:SetBackdropBorderColor(unpack(self.__RefineRestoreBorder))
                elseif border and self.__RefineOriginalBorder then
                    border:SetBackdropBorderColor(unpack(self.__RefineOriginalBorder))
                end
            end
        end
    end

    -- Lightweight mouse hooks as a fallback for any buttons not covered by mixin/state hooks
    if not button.__RefineMouseHooked then
        button:HookScript("OnMouseDown", function(self)
            if self.__RefineSetPressedVisual then self:__RefineSetPressedVisual(true) end
        end)
        button:HookScript("OnMouseUp", function(self)
            if self.__RefineSetPressedVisual then self:__RefineSetPressedVisual(false) end
        end)
        button.__RefineMouseHooked = true
    end

    button.isSkinned = true
end

local function StyleButtons(buttonNames, count)
    for _, name in ipairs(buttonNames) do
        for i = 1, count do
            local button = _G[name .. i]
            if button then StyleButton(button) end
        end
    end
end

local function SetupActionBars()
    if InCombatLockdown() then return end
    if actionbarsSetup then return end

    local buttonGroups = {
        { names = R.ActionBarPrimaryPrefixes, count = 12 },
        { names = {"PetActionButton"}, count = NUM_PET_ACTION_SLOTS },
        { names = {"StanceButton"}, count = 10 },
        { names = {"OverrideActionBarButton"}, count = NUM_OVERRIDE_BUTTONS },
    }

    for _, group in ipairs(buttonGroups) do
        StyleButtons(group.names, group.count)
    end

    StyleButton(ExtraActionButton1)
    actionbarsSetup = true
end

local hotkeyHooked = false
local nameUpdateHooked = false
local function ConfigureButtonText()
    local showHotkeys = C.actionbars.hotkey

    local patterns = nil
    if showHotkeys then
        patterns = {
            ["Middle Mouse"] = "M3", ["Mouse Wheel Down"] = "WD", ["Mouse Wheel Up"] = "WU",
            ["Mouse Button "] = "M", ["Num Pad "] = "N", ["Spacebar"] = "SB",
            ["Capslock"] = "CL", ["Num Lock"] = "NL", ["a%-"] = "A", ["c%-"] = "C", ["s%-"] = "S",
        }
    end

    local function UpdateHotkey(self)
        local hotkey = self and self.HotKey
        if not hotkey then return end
        -- If we are configured to hide hotkeys, ensure they stay hidden and exit early
        if not showHotkeys then
            hotkey:Hide()
            return
        end

        local text = hotkey:GetText()
        if not text or not patterns then return end

        for k, v in pairs(patterns) do
            text = text:gsub(k, v)
        end
        hotkey:SetText(text)
        hotkey:SetTextColor(unpack(BORDER))
        hotkey:SetFont(unpack(CF.actionbars.hotkey))
    end

    local buttonNames = R.ActionBarPrimaryPrefixes

    -- Install a safe hook that normalizes (or hides) hotkey text for action buttons
    if not hotkeyHooked then
        local globalUpdate = rawget(_G, "ActionButton_UpdateHotkeys")
        if type(globalUpdate) == "function" then
            hooksecurefunc("ActionButton_UpdateHotkeys", UpdateHotkey)
            hotkeyHooked = true
        else
            -- Retail uses ActionButtonMixin:UpdateHotkeys on the ActionButton frame type
            local ActionButtonGlobal = rawget(_G, "ActionButton")
            if ActionButtonGlobal and type(ActionButtonGlobal.UpdateHotkeys) == "function" then
                hooksecurefunc(ActionButtonGlobal, "UpdateHotkeys", function(self)
                    UpdateHotkey(self)
                end)
                hotkeyHooked = true
            end
        end
    end

    -- Ensure the name visibility follows the same toggle reliably using a safe hook
    if not nameUpdateHooked and type(rawget(_G, "ActionButton_Update")) == "function" then
        hooksecurefunc("ActionButton_Update", function(self)
            local btnName = self and self.GetName and self:GetName()
            if not btnName then return end
            local nameText = _G[btnName .. "Name"]
            local hotkeyText = _G[btnName .. "HotKey"]
            if nameText then
                if showHotkeys then nameText:Show() else nameText:Hide() end
            end
            if hotkeyText and not showHotkeys then
                hotkeyText:Hide()
            end
        end)
        nameUpdateHooked = true
    end

    for _, btnName in ipairs(buttonNames) do
        for i = 1, NUM_ACTIONBAR_BUTTONS do
            local button = _G[btnName .. i]
            if button then
                local hotkeyText = _G[btnName .. i .. "HotKey"]
                local nameText = _G[btnName .. i .. "Name"]

                if showHotkeys then
                    if hotkeyText then hotkeyText:Show() end
                    if nameText then nameText:Show() end
                else
                    if hotkeyText then hotkeyText:Hide() end
                    if nameText then nameText:Hide() end
                end
            end
        end
    end
end

-- Scale cooldown timer text for action bar buttons using project font settings
local function ScaleCooldownTimerText(cooldown)
    if not cooldown or cooldown:IsForbidden() then return end
    local parent = cooldown:GetParent()
    -- Our cooldowns may be reparented into an anonymous overlay; climb up one level if needed
    local host = parent
    if host and (not (host.GetName and host:GetName())) and host.GetParent then
        host = host:GetParent()
    end
    if not host or not host.GetName then return end
    local pname = host:GetName() or ""
    if not IsManagedActionButtonName(pname) then
        return
    end

    local timer = cooldown.timer

    -- Desired font
    local baseArgs = CF.cooldownTimers
    if type(baseArgs) ~= "table" then baseArgs = { CM.boldFont, 20, "THICKOUTLINE" } end
    local fontFile, fontSize, fontFlags = baseArgs[1], baseArgs[2], baseArgs[3]
    local overrideSize = C.actionbars and C.actionbars.cooldownFontSize
    if type(overrideSize) == "number" and overrideSize > 0 then fontSize = overrideSize end

    local function apply(fs)
        if not fs or fs:GetObjectType() ~= "FontString" then return end
        local curFile, curSize, curFlags = fs:GetFont()
        if curFile ~= fontFile or curSize ~= fontSize or curFlags ~= fontFlags then
            fs:SetFont(fontFile, fontSize, fontFlags)
        end
        cooldown.__timerFS = fs
    end

    if timer and timer.text then apply(timer.text) end

    -- Fallback: some implementations attach their own FontString to the cooldown frame
    local function applyToFontString(fs)
        if not fs or not fs.GetObjectType or fs:GetObjectType() ~= "FontString" then return false end
        apply(fs)
        return true
    end

    -- Only scan if we haven't identified a specific FontString yet
    if not cooldown.__timerFS then
        -- Only scan the cooldown frame's own regions to avoid scaling stack count/name texts
        if cooldown.EnumerateRegions then
            for region in cooldown:EnumerateRegions() do
                if applyToFontString(region) then break end
            end
        else
            local i = 1
            while true do
                local region = select(i, cooldown:GetRegions())
                if not region then break end
                if applyToFontString(region) then break end
                i = i + 1
            end
        end
    elseif cooldown.__timerFS then
        if cooldown.__timerFS.GetObjectType and cooldown.__timerFS:GetObjectType() == "FontString" then
            apply(cooldown.__timerFS)
        else
            cooldown.__timerFS = nil
            -- Retry a light scan if cached ref became invalid
            if cooldown.EnumerateRegions then
                for region in cooldown:EnumerateRegions() do
                    if applyToFontString(region) then break end
                end
            else
                local i = 1
                while true do
                    local region = select(i, cooldown:GetRegions())
                    if not region then break end
                    if applyToFontString(region) then break end
                    i = i + 1
                end
            end
        end
    end
end

-- Scan existing cooldown timers and apply scaling
local function ScanAndScaleExistingCooldowns()
    local bases = R.ActionBarAllPrefixes
    for _, base in ipairs(bases) do
        local max = (base == "PetActionButton") and (NUM_PET_ACTION_SLOTS or 10)
            or (base == "StanceButton" and 10)
            or (base == "ExtraActionButton" and 1)
            or (NUM_ACTIONBAR_BUTTONS or 12)
        for i = 1, max do
            local btn = _G[base .. i]
            if btn then
                local cd = _G[btn:GetName() .. "Cooldown"] or btn.cooldown
                if cd then
                    ScaleCooldownTimerText(cd)
                    if C_Timer and C_Timer.After then
                        C_Timer.After(0, function()
                            if cd and cd:IsShown() then ScaleCooldownTimerText(cd) end
                        end)
                    end
                end
            end
        end
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ADDON_LOADED")
local cooldownsScanned = false
-- Overlay resync no longer needed; we style base cooldowns only

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_ENTERING_WORLD" then
        SetupActionBars()
        if not cooldownsScanned then
            ScanAndScaleExistingCooldowns()
            cooldownsScanned = true
        end
    elseif event == "ADDON_LOADED" and arg1 == "RefineUI" then
        ConfigureButtonText()
        if not cooldownsScanned then
            ScanAndScaleExistingCooldowns()
            cooldownsScanned = true
        end
    end
end)
-- Hook Blizzard cooldown SetCooldown so future timers are scaled immediately
do
    local sample = rawget(_G, "ActionButton1Cooldown")
    if not sample then
        local ab1 = rawget(_G, "ActionButton1")
        if ab1 then sample = ab1.cooldown end
    end
    if not sample then
        sample = CreateFrame("Cooldown", nil, UIParent, "CooldownFrameTemplate")
    end
    local mt = getmetatable(sample)
    if mt and mt.__index then
        local COOLDOWN_MT = mt.__index

        local function SetupCooldownIntoOverlay(cd, overlay)
            if not cd or not overlay then return end
            if cd:GetParent() ~= overlay then cd:SetParent(overlay) end
            cd:ClearAllPoints()
            cd:SetAllPoints(overlay)
            cd:SetDrawEdge(false)
            cd:SetDrawSwipe(true)
            cd:SetReverse(false)
            if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(false) end
            if C.media and C.media.actionbarCooldown then
                pcall(cd.SetSwipeTexture, cd, C.media.actionbarCooldown)
            end
            cd:SetSwipeColor(0, 0, 0, 0.8)
            cd:EnableMouse(false)
        end

        hooksecurefunc(COOLDOWN_MT, "SetCooldown", function(cooldown, start, duration, modRate)
            local parent = cooldown and cooldown:GetParent()
            if not parent or not parent.GetName then return end
            local pname = parent:GetName() or ""
            if not IsManagedActionButtonName(pname) then return end

            -- Create/find an overlay that sits above our border to host Blizzard's cooldowns
            local overlay = EnsureCooldownOverlay(parent)

            -- Move Blizzard base cooldown into the overlay and style it
            SetupCooldownIntoOverlay(cooldown, overlay)

            -- Do the same for charges cooldown if present
            local cc = parent.chargeCooldown
            if cc then
                SetupCooldownIntoOverlay(cc, overlay)
                -- Ensure charge cooldown text is scaled consistently
                if start and start > 0 and duration and duration > 0 then
                    ScaleCooldownTimerText(cc)
                    if C_Timer and C_Timer.After then
                        C_Timer.After(0, function()
                            if cc and cc:IsShown() then ScaleCooldownTimerText(cc) end
                        end)
                        C_Timer.After(0.05, function()
                            if cc and cc:IsShown() then ScaleCooldownTimerText(cc) end
                        end)
                    end
                end
                if not cc.__refineUIOnShowHooked then
                    cc:HookScript("OnShow", function(self)
                        ScaleCooldownTimerText(self)
                    end)
                    cc.__refineUIOnShowHooked = true
                end
                if not cc.__refineUIOnSizeHooked then
                    cc:HookScript("OnSizeChanged", function(self)
                        ScaleCooldownTimerText(self)
                    end)
                    cc.__refineUIOnSizeHooked = true
                end
            end

            -- Scale numeric text if present and ensure delayed-created FS (e.g. OmniCC) are handled
            if start and start > 0 and duration and duration > 0 then
                ScaleCooldownTimerText(cooldown)
                -- Some addons create their FontStrings after SetCooldown; schedule deferred passes
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, function()
                        if cooldown and cooldown:IsShown() then ScaleCooldownTimerText(cooldown) end
                    end)
                    C_Timer.After(0.05, function()
                        if cooldown and cooldown:IsShown() then ScaleCooldownTimerText(cooldown) end
                    end)
                end
            end

            -- Also hook OnShow once to rescale when the cooldown frame appears
            if not cooldown.__refineUIOnShowHooked then
                cooldown:HookScript("OnShow", function(self)
                    ScaleCooldownTimerText(self)
                end)
                cooldown.__refineUIOnShowHooked = true
            end
            -- And rescale when size changes (Blizzard adjusts text height on size)
            if not cooldown.__refineUIOnSizeHooked then
                cooldown:HookScript("OnSizeChanged", function(self)
                    ScaleCooldownTimerText(self)
                end)
                cooldown.__refineUIOnSizeHooked = true
            end
        end)
    end
end

-- Hide extra styles
if ExtraActionButton1 and ExtraActionButton1.style then
    ExtraActionButton1.style:SetAlpha(0)
    ExtraActionButton1.style:Hide()
end
if ZoneAbilityFrame and ZoneAbilityFrame.Style then
    ZoneAbilityFrame.Style:SetAlpha(0)
    ZoneAbilityFrame.Style:Hide()
end

----------------------------------------------------------------------------------------
-- Press detection hooks (simple & low cost)
----------------------------------------------------------------------------------------
-- 1) Hook the mixin so any programmatic press (keyboard, secure click, etc.) triggers our visuals.
local ABMixin = rawget(_G, "ActionBarActionButtonMixin")
if ABMixin and type(ABMixin.SetButtonStateOverride) == "function" then
    hooksecurefunc(ABMixin, "SetButtonStateOverride", function(self, state)
        -- Keep Blizzard's pressed art hidden every time they re-apply it
        if self.PushedTexture then self.PushedTexture:SetAlpha(0) end
        if self.__RefineSetPressedVisual then
            if state == "PUSHED" then
                self:__RefineSetPressedVisual(true)
            else
                self:__RefineSetPressedVisual(false)
            end
        end
    end)
end

-- 2) Belt-and-suspenders: also listen to the global down/up helpers so pet/stance/override
--    buttons without the mixin still get the effect.
do
    local __abd = rawget(_G, "ActionButtonDown")
    local __abup = rawget(_G, "ActionButtonUp")
    local __mabd = rawget(_G, "MultiActionButtonDown")
    local __mabup = rawget(_G, "MultiActionButtonUp")
    local __gafid = rawget(_G, "GetActionButtonForID")

    local function setPressed(id, pressed)
        if not __gafid then return end
        local b = __gafid(id)
        if b and b.__RefineSetPressedVisual then b:__RefineSetPressedVisual(pressed) end
    end

    if type(__abd) == "function" and type(__gafid) == "function" then
        hooksecurefunc("ActionButtonDown", function(id) setPressed(id, true) end)
    end
    if type(__abup) == "function" and type(__gafid) == "function" then
        hooksecurefunc("ActionButtonUp", function(id) setPressed(id, false) end)
    end

    local __BAR_MAP = {
        MULTIACTIONBAR1 = "MultiBarBottomLeft",
        MULTIACTIONBAR2 = "MultiBarBottomRight",
        MULTIACTIONBAR3 = "MultiBarRight",
        MULTIACTIONBAR4 = "MultiBarLeft",
        MULTIACTIONBAR5 = "MultiBar5",
        MULTIACTIONBAR6 = "MultiBar6",
        MULTIACTIONBAR7 = "MultiBar7",
    }
    local function getMultiBarButton(bar, id)
        if not bar or not id then return nil end
        local btn = _G[bar .. "Button" .. id]
        if btn then return btn end
        local mapped = __BAR_MAP[bar]
        if mapped then
            return _G[mapped .. "Button" .. id]
        end
        return nil
    end
    if type(__mabd) == "function" then
        hooksecurefunc("MultiActionButtonDown", function(bar, id)
            local b = getMultiBarButton(bar, id)
            if b and b.__RefineSetPressedVisual then b:__RefineSetPressedVisual(true) end
        end)
    end
    if type(__mabup) == "function" then
        hooksecurefunc("MultiActionButtonUp", function(bar, id)
            local b = getMultiBarButton(bar, id)
            if b and b.__RefineSetPressedVisual then b:__RefineSetPressedVisual(false) end
        end)
    end

    local __pad = rawget(_G, "PetActionButtonDown")
    local __pau = rawget(_G, "PetActionButtonUp")
    if type(__pad) == "function" then
        hooksecurefunc("PetActionButtonDown", function(id)
            local b = _G["PetActionButton" .. id]
            if b and b.__RefineSetPressedVisual then b:__RefineSetPressedVisual(true) end
        end)
    end
    if type(__pau) == "function" then
        hooksecurefunc("PetActionButtonUp", function(id)
            local b = _G["PetActionButton" .. id]
            if b and b.__RefineSetPressedVisual then b:__RefineSetPressedVisual(false) end
        end)
    end

    -- Stance / Shapeshift
    local __sbd = rawget(_G, "StanceButtonDown") or rawget(_G, "ShapeshiftButtonDown")
    local __sbu = rawget(_G, "StanceButtonUp") or rawget(_G, "ShapeshiftButtonUp")
    if type(__sbd) == "function" then
        hooksecurefunc(type(rawget(_G, "StanceButtonDown")) == "function" and "StanceButtonDown" or "ShapeshiftButtonDown", function(id)
            local b = _G["StanceButton" .. id] or _G["ShapeshiftButton" .. id]
            if b and b.__RefineSetPressedVisual then b:__RefineSetPressedVisual(true) end
        end)
    end
    if type(__sbu) == "function" then
        hooksecurefunc(type(rawget(_G, "StanceButtonUp")) == "function" and "StanceButtonUp" or "ShapeshiftButtonUp", function(id)
            local b = _G["StanceButton" .. id] or _G["ShapeshiftButton" .. id]
            if b and b.__RefineSetPressedVisual then b:__RefineSetPressedVisual(false) end
        end)
    end
end
