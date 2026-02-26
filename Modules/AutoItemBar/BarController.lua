----------------------------------------------------------------------------------------
-- AutoItemBar Component: BarController
-- Description: Creates and updates the visible item action buttons.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local AutoItemBar = RefineUI:GetModule("AutoItemBar")
if not AutoItemBar then return end

local floor = math.floor
local ceil = math.ceil
local min = math.min
local tinsert = table.insert
local tsort = table.sort
local pairs = pairs
local type = type
local InCombatLockdown = InCombatLockdown
local GetCursorInfo = GetCursorInfo
local IsControlKeyDown = IsControlKeyDown
local GetItemIconByID = C_Item.GetItemIconByID
local UnitAffectingCombat = UnitAffectingCombat
local GetAtlasInfo = C_Texture and C_Texture.GetAtlasInfo
local UIParent = UIParent

----------------------------------------------------------------------------------------
--	Locals & Constants
----------------------------------------------------------------------------------------

local currentConsumables = AutoItemBar.currentConsumables
local EDITMODE_TUTORIAL_FRAME_NAME = "RefineUI_AutoItemBarEditModeTutorialTip"
local MAIN_FRAME_NAME = "RefineUI_AutoItemBar"
local MOVER_FRAME_NAME = "RefineUI_AutoItemBarMover"
local PARENT_FRAME_NAME = "ConsumableBarParent"
local ADD_SLOT_ATLAS = "cdm-empty"
local ADD_SLOT_FALLBACK_TEXTURE = "Interface\\AddOns\\RefineUI\\Media\\Textures\\add.blp"
local ADD_SLOT_ICON_INSET = -2
local GOLD_R, GOLD_G, GOLD_B, GOLD_A = 1, 0.82, 0, 1

local function SafeFade(frame, alpha)
    if InCombatLockdown() then
        frame:SetAlpha(alpha)
    else
        UIFrameFadeIn(frame, 0.2, frame:GetAlpha(), alpha)
    end
end

local function GetButtonBorder(button)
    if not button then
        return nil
    end
    local border = button.RefineBorder or button.border
    if border and border.SetBackdropBorderColor then
        return border
    end
    return nil
end

local function GetDefaultBorderColor()
    local color = RefineUI.Config and RefineUI.Config.General and RefineUI.Config.General.BorderColor
    if color then
        return color[1] or 0.3, color[2] or 0.3, color[3] or 0.3, color[4] or 1
    end
    return 0.3, 0.3, 0.3, 1
end

local function ApplyGoldHoverBorder(button, state)
    local border = GetButtonBorder(button)
    if not border or not state then
        return
    end

    if border.GetBackdropBorderColor then
        state.hoverRestoreR, state.hoverRestoreG, state.hoverRestoreB, state.hoverRestoreA = border:GetBackdropBorderColor()
    else
        state.hoverRestoreR, state.hoverRestoreG, state.hoverRestoreB, state.hoverRestoreA = GetDefaultBorderColor()
    end

    border:SetBackdropBorderColor(GOLD_R, GOLD_G, GOLD_B, GOLD_A)
end

local function RestoreHoverBorder(button, state)
    local border = GetButtonBorder(button)
    if not border then
        return
    end

    local r, g, b, a
    if state and state.hoverRestoreR ~= nil then
        r, g, b, a = state.hoverRestoreR, state.hoverRestoreG, state.hoverRestoreB, state.hoverRestoreA
    else
        r, g, b, a = GetDefaultBorderColor()
    end
    border:SetBackdropBorderColor(r, g, b, a or 1)
end

----------------------------------------------------------------------------------------
--	Render Pipeline
----------------------------------------------------------------------------------------

function AutoItemBar:InvalidateLayoutCache()
    if self.ConsumableButtonsFrame then
        self.ConsumableButtonsFrame._lastWidth = nil
        self.ConsumableButtonsFrame._lastHeight = nil
    end
end

function AutoItemBar:GetGridExtents(itemCount)
    local count = itemCount > 0 and itemCount or 1
    local orientation = self:GetOrientation()
    local limit = self:GetButtonLimit()
    local rows, cols

    if orientation == self.ORIENTATION_VERTICAL then
        rows = min(count, limit)
        cols = ceil(count / limit)
    else
        cols = min(count, limit)
        rows = ceil(count / limit)
    end

    return rows, cols
end

function AutoItemBar:GetGridPosition(index, itemCount)
    local orientation = self:GetOrientation()
    local direction = self:GetButtonDirection()
    local wrap = self:GetButtonWrap()
    local limit = self:GetButtonLimit()
    local rows, cols = self:GetGridExtents(itemCount or index)
    local row, col

    if orientation == self.ORIENTATION_VERTICAL then
        row = (index - 1) % limit
        col = floor((index - 1) / limit)

        if direction == self.DIRECTION_REVERSE then
            row = (rows - 1) - row
        end
        if wrap == self.WRAP_REVERSE then
            col = (cols - 1) - col
        end
    else
        row = floor((index - 1) / limit)
        col = (index - 1) % limit

        if direction == self.DIRECTION_REVERSE then
            col = (cols - 1) - col
        end
        if wrap == self.WRAP_REVERSE then
            row = (rows - 1) - row
        end
    end

    return row, col
end

function AutoItemBar:GetFrameDimensions(itemCount)
    local rows, cols = self:GetGridExtents(itemCount)

    local width = cols * (self.buttonSize + self.buttonSpacing) - self.buttonSpacing
    local height = rows * (self.buttonSize + self.buttonSpacing) - self.buttonSpacing
    return width, height
end

function AutoItemBar:EnsureAddSlotButton()
    if self.AddSlotButton then
        return self.AddSlotButton
    end

    local button = CreateFrame("Button", nil, self.ConsumableButtonsFrame, "BackdropTemplate")
    RefineUI.Size(button, self.buttonSize, self.buttonSize)
    RefineUI.SetTemplate(button, "Default")
    RefineUI.StyleButton(button, true)
    button:EnableMouse(true)

    if button.border and button.border.SetBackdropBorderColor then
        button.border:SetBackdropBorderColor(0.15, 1.0, 0.15, 1.0)
    end

    button.icon = button:CreateTexture(nil, "ARTWORK")
    RefineUI.SetInside(button.icon, button, ADD_SLOT_ICON_INSET, ADD_SLOT_ICON_INSET)
    if button.icon.SetAtlas and GetAtlasInfo and GetAtlasInfo(ADD_SLOT_ATLAS) then
        button.icon:SetAtlas(ADD_SLOT_ATLAS, false)
    else
        button.icon:SetTexture(ADD_SLOT_FALLBACK_TEXTURE)
        button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
    button.icon:SetAlpha(0.95)

    button:SetScript("OnEnter", function(selfButton)
        AutoItemBar:ShowBar()
        ApplyGoldHoverBorder(selfButton, AutoItemBar:GetButtonState(selfButton))
    end)
    button:SetScript("OnLeave", function(selfButton)
        RestoreHoverBorder(selfButton, AutoItemBar:GetButtonState(selfButton))
        AutoItemBar:QueueMouseoverRefresh()
    end)
    button:SetScript("OnReceiveDrag", function()
        AutoItemBar:HandleDropFromCursor()
    end)
    button:SetScript("OnMouseUp", function(_, _)
        if GetCursorInfo() then
            AutoItemBar:HandleDropFromCursor()
        end
    end)

    button:Hide()
    self.AddSlotButton = button
    return button
end

function AutoItemBar:UpdateAddSlotButton(itemCount, showAddSlot, inCombat)
    local button = self:EnsureAddSlotButton()

    if not showAddSlot then
        button:Hide()
        return
    end

    local currentCount = (itemCount and itemCount > 0) and itemCount or 1
    local nextIndex = (itemCount or 0) + 1
    local row, col = self:GetGridPosition(nextIndex, currentCount)
    local xOffset = col * (self.buttonSize + self.buttonSpacing)
    local yOffset = -row * (self.buttonSize + self.buttonSpacing)

    if not inCombat then
        if button._buttonSize ~= self.buttonSize then
            RefineUI.Size(button, self.buttonSize, self.buttonSize)
            button._buttonSize = self.buttonSize
        end

        if row ~= button._row or col ~= button._col or xOffset ~= button._xOffset or yOffset ~= button._yOffset then
            RefineUI.Point(button, "TOPLEFT", xOffset, yOffset)
            button._row = row
            button._col = col
            button._xOffset = xOffset
            button._yOffset = yOffset
        end

        if button.border and button.border.SetBackdropBorderColor then
            button.border:SetBackdropBorderColor(0.15, 1.0, 0.15, 1.0)
        end
        button:Show()
    else
        self._pendingCombatRefresh = true
    end
end

function AutoItemBar:ApplyDisplayCountSize(displayCount, inCombat)
    local frameWidth, frameHeight = self:GetFrameDimensions(displayCount)
    if not inCombat then
        if self.ConsumableButtonsFrame._lastWidth ~= frameWidth or self.ConsumableButtonsFrame._lastHeight ~= frameHeight then
            self.ConsumableButtonsFrame:SetSize(frameWidth, frameHeight)
            self.Mover:SetSize(frameWidth, frameHeight)
            self.ConsumableBarParent:SetSize(frameWidth, frameHeight + 10)
            self.ConsumableButtonsFrame._lastWidth = frameWidth
            self.ConsumableButtonsFrame._lastHeight = frameHeight
        end
    elseif self.ConsumableButtonsFrame._lastWidth ~= frameWidth or self.ConsumableButtonsFrame._lastHeight ~= frameHeight then
        self._pendingCombatRefresh = true
    end
end

function AutoItemBar:RefreshAddSlotFromCursor()
    if not self.ConsumableButtonsFrame then
        return
    end

    local inCombat = InCombatLockdown()
    local cursorType = GetCursorInfo()
    local showAddSlot = cursorType == "item"
    local count = self._lastConsumableCount or 0

    self:UpdateAddSlotButton(count, showAddSlot, inCombat)
    self:ApplyDisplayCountSize(count, inCombat)
    self:SyncInteractivity()
end

----------------------------------------------------------------------------------------
--	Interaction Overrides
----------------------------------------------------------------------------------------

function AutoItemBar:IsMouseOverBar()
    if self._editModeActive then return true end
    if self.ConsumableButtonsFrame and self.ConsumableButtonsFrame:IsMouseOver() then return true end
    if self.ConsumableBarParent and self.ConsumableBarParent:IsMouseOver() then return true end

    if self.consumableButtons then
        for _, button in pairs(self.consumableButtons) do
            if button:IsMouseOver() then return true end
        end
    end
    if self.AddSlotButton and self.AddSlotButton:IsShown() and self.AddSlotButton:IsMouseOver() then
        return true
    end

    return false
end

function AutoItemBar:EvaluateMouseoverVisibility()
    if not self.ConsumableButtonsFrame then return end

    local cfg = self:GetConfig()
    local visibilityMode = self:GetBarVisibilityMode()
    local barAlpha = cfg.BarAlpha or 1
    if barAlpha < 0 then
        barAlpha = 0
    elseif barAlpha > 1 then
        barAlpha = 1
    end
    local shouldShow

    if self._editModeActive then
        shouldShow = true
    elseif visibilityMode == self.VISIBILITY_ALWAYS then
        shouldShow = true
    elseif visibilityMode == self.VISIBILITY_IN_COMBAT then
        shouldShow = UnitAffectingCombat("player") == true
    elseif visibilityMode == self.VISIBILITY_OUT_OF_COMBAT then
        shouldShow = UnitAffectingCombat("player") ~= true
    elseif visibilityMode == self.VISIBILITY_MOUSEOVER then
        local cursorType = GetCursorInfo()
        shouldShow = self._mouseOverBar == true or cursorType == "item"
    else
        shouldShow = false
    end

    if self._lastVisibleState == shouldShow then
        return
    end
    self._lastVisibleState = shouldShow

    if shouldShow then
        SafeFade(self.ConsumableButtonsFrame, barAlpha)
    else
        SafeFade(self.ConsumableButtonsFrame, 0)
    end
end

function AutoItemBar:SyncInteractivity()
    local mode = self:GetBarVisibilityMode()
    local interactive = (not self._editModeActive) and (mode ~= self.VISIBILITY_NEVER)
    self:SetInteractive(interactive)
    self:UpdateButtonLayering()
end

function AutoItemBar:UpdateButtonLayering()
    if InCombatLockdown() then
        return
    end

    local moverStrata = (self.Mover and self.Mover:GetFrameStrata()) or "MEDIUM"
    local desiredStrata = self._editModeActive and "LOW" or moverStrata

    if self.ConsumableButtonsFrame and self.ConsumableButtonsFrame.GetFrameStrata then
        local frameStrata = self._editModeActive and "LOW" or moverStrata
        if self.ConsumableButtonsFrame:GetFrameStrata() ~= frameStrata then
            self.ConsumableButtonsFrame:SetFrameStrata(frameStrata)
        end
    end

    if not self.consumableButtons then
        if self.AddSlotButton and self.AddSlotButton.GetFrameStrata and self.AddSlotButton.SetFrameStrata then
            if self.AddSlotButton:GetFrameStrata() ~= desiredStrata then
                self.AddSlotButton:SetFrameStrata(desiredStrata)
            end
        end
        return
    end

    for _, button in pairs(self.consumableButtons) do
        if button and button.GetFrameStrata and button.SetFrameStrata then
            if button:GetFrameStrata() ~= desiredStrata then
                button:SetFrameStrata(desiredStrata)
            end
        end
    end
    if self.AddSlotButton and self.AddSlotButton.GetFrameStrata and self.AddSlotButton.SetFrameStrata then
        if self.AddSlotButton:GetFrameStrata() ~= desiredStrata then
            self.AddSlotButton:SetFrameStrata(desiredStrata)
        end
    end
end

function AutoItemBar:QueueMouseoverRefresh()
    if self._mouseoverRefreshQueued then return end
    self._mouseoverRefreshQueued = true
    C_Timer.After(0, function()
        self._mouseoverRefreshQueued = false
        self._mouseOverBar = self:IsMouseOverBar()
        self:EvaluateMouseoverVisibility()
    end)
end

function AutoItemBar:ShowBar()
    self._mouseOverBar = true
    self:EvaluateMouseoverVisibility()
end

function AutoItemBar:HideBar()
    self:QueueMouseoverRefresh()
end

function AutoItemBar:UpdateBarVisibility()
    if not self.ConsumableButtonsFrame then return end

    self:SyncInteractivity()

    local visibilityMode = self:GetBarVisibilityMode()
    if visibilityMode == self.VISIBILITY_MOUSEOVER then
        self._mouseOverBar = self:IsMouseOverBar()
    else
        self._mouseOverBar = false
    end
    self._lastVisibleState = nil
    self:EvaluateMouseoverVisibility()
end

function AutoItemBar:MarkEditModeTutorialSeen()
    local cfg = self:GetConfig()
    cfg.EditModeTutorialSeen = true
    self._pendingEditModeTutorial = nil
end

function AutoItemBar:HideEditModeTutorial(markSeen)
    if self.EditModeTutorialFrame then
        self.EditModeTutorialFrame:Hide()
    end
    if markSeen then
        self:MarkEditModeTutorialSeen()
    end
end

function AutoItemBar:EnsureEditModeTutorialFrame()
    if self.EditModeTutorialFrame then
        return self.EditModeTutorialFrame
    end

    local frame = CreateFrame("Frame", EDITMODE_TUTORIAL_FRAME_NAME, UIParent, "BackdropTemplate")
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(260)
    frame:SetSize(320, 132)
    RefineUI.SetTemplate(frame, "Transparent")
    frame:Hide()
    if frame.border and frame.border.SetBackdropBorderColor then
        frame.border:SetBackdropBorderColor(1, 0.82, 0, 0.95)
    end

    local glow = RefineUI.CreateGlow and RefineUI.CreateGlow(frame, 8)
    if glow then
        glow:SetFrameStrata(frame:GetFrameStrata())
        glow:SetFrameLevel(frame:GetFrameLevel() - 1)
        if glow.SetBackdropBorderColor then
            glow:SetBackdropBorderColor(1, 0.82, 0, 0.85)
        end
        if RefineUI.CreatePulse then
            RefineUI.CreatePulse(glow, 0.35, 0.95, 0.8)
        end
        frame.goldGlow = glow
    end

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.title:SetPoint("TOPLEFT", 12, -12)
    frame.title:SetText("Auto Item Bar")
    frame.title:SetTextColor(1, 0.82, 0)

    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.text:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -8)
    frame.text:SetPoint("TOPRIGHT", -12, -38)
    frame.text:SetJustifyH("LEFT")
    frame.text:SetJustifyV("TOP")
    frame.text:SetText("Drag an item from your bags onto the bar to add it as a custom tracked item.\n\nHold Ctrl + Right-Click an item on the bar to hide it.")

    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", 0, 0)
    frame.close:SetScript("OnClick", function()
        AutoItemBar:HideEditModeTutorial(true)
    end)

    frame.okay = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.okay:SetSize(70, 20)
    frame.okay:SetPoint("BOTTOMRIGHT", -10, 10)
    frame.okay:SetText(OKAY)
    frame.okay:SetScript("OnClick", function()
        AutoItemBar:HideEditModeTutorial(true)
    end)

    frame:SetScript("OnShow", function(selfFrame)
        if selfFrame.goldGlow then
            selfFrame.goldGlow:Show()
            if selfFrame.goldGlow.PulseAnim and not selfFrame.goldGlow.PulseAnim:IsPlaying() then
                selfFrame.goldGlow.PulseAnim:Play()
            end
        end
    end)

    frame:SetScript("OnHide", function(selfFrame)
        if selfFrame.goldGlow and selfFrame.goldGlow.PulseAnim and selfFrame.goldGlow.PulseAnim:IsPlaying() then
            selfFrame.goldGlow.PulseAnim:Stop()
        end
    end)

    self.EditModeTutorialFrame = frame
    return frame
end

function AutoItemBar:PositionEditModeTutorialFrame()
    local frame = self:EnsureEditModeTutorialFrame()
    frame:ClearAllPoints()

    if self.ConsumableButtonsFrame and self.ConsumableButtonsFrame:IsShown() then
        frame:SetPoint("BOTTOM", self.ConsumableButtonsFrame, "TOP", 0, 10)
    elseif self.Mover then
        frame:SetPoint("BOTTOM", self.Mover, "TOP", 0, 10)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER")
    end
end

function AutoItemBar:TryShowEditModeTutorial()
    if not self._editModeActive then
        return
    end

    local cfg = self:GetConfig()
    if cfg.EditModeTutorialSeen then
        self._pendingEditModeTutorial = nil
        return
    end

    if InCombatLockdown() then
        self._pendingEditModeTutorial = true
        return
    end

    self:PositionEditModeTutorialFrame()
    local frame = self:EnsureEditModeTutorialFrame()
    frame:Show()
    self._pendingEditModeTutorial = nil
end

function AutoItemBar:CreateConsumableButton(itemID, index, itemCount)
    local button = CreateFrame("Button", nil, self.ConsumableButtonsFrame, "SecureActionButtonTemplate")
    local buttonState = self:GetButtonState(button)
    RefineUI.Size(button, self.buttonSize, self.buttonSize)

    local row, col = self:GetGridPosition(index, itemCount)
    local xOffset = col * (self.buttonSize + self.buttonSpacing)
    local yOffset = -row * (self.buttonSize + self.buttonSpacing)

    RefineUI.Point(button, "TOPLEFT", xOffset, yOffset)
    button:SetFrameStrata((self._editModeActive and "LOW") or ((self.Mover and self.Mover:GetFrameStrata()) or "MEDIUM"))
    RefineUI.SetTemplate(button, "Default")
    RefineUI.StyleButton(button, true)

    button:RegisterForClicks("AnyDown", "AnyUp")
    button:EnableMouse(true)
    buttonState.lastUseItem = nil
    buttonState.pendingUseItem = nil
    if self._useActionsEnabled ~= false then
        self:AssignUseAction(button, itemID)
    end

    local iconTexture = button:CreateTexture(nil, "BORDER")
    RefineUI.SetInside(iconTexture)
    iconTexture:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    iconTexture:SetTexture(GetItemIconByID(itemID))

    local countText = button:CreateFontString(nil, "OVERLAY")
    RefineUI.Point(countText, "BOTTOMRIGHT", -1, 3)
    countText:SetJustifyH("RIGHT")
    RefineUI.Font(countText, 12)

    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(iconTexture)
    cooldown:SetFrameLevel(1)
    if cooldown.EnableMouse then
        cooldown:EnableMouse(false)
    end

    buttonState.iconTexture = iconTexture
    buttonState.countText = countText
    buttonState.cooldown = cooldown
    buttonState.itemID = itemID
    buttonState.row = row
    buttonState.col = col
    buttonState.xOffset = xOffset
    buttonState.yOffset = yOffset
    buttonState.buttonSize = self.buttonSize

    button:SetScript("OnEnter", function(selfButton)
        local state = AutoItemBar:GetButtonState(selfButton)
        local targetItemID = state and state.itemID
        if not targetItemID then return end
        GameTooltip:SetOwner(selfButton, "ANCHOR_RIGHT")
        local loc = AutoItemBar.itemLocationById and AutoItemBar.itemLocationById[targetItemID]
        local bag = loc and loc.bag
        local slot = loc and loc.slot
        if type(bag) == "number" and type(slot) == "number" then
            GameTooltip:SetBagItem(bag, slot)
        else
            GameTooltip:SetItemByID(targetItemID)
        end
        GameTooltip:Show()
        AutoItemBar:ShowBar()
        ApplyGoldHoverBorder(selfButton, state)
    end)

    button:SetScript("OnLeave", function(selfButton)
        RestoreHoverBorder(selfButton, AutoItemBar:GetButtonState(selfButton))
        GameTooltip_Hide()
        AutoItemBar:QueueMouseoverRefresh()
    end)

    button:SetScript("OnReceiveDrag", function()
        AutoItemBar:HandleDropFromCursor()
    end)

    button:SetScript("OnMouseUp", function(selfButton, mouseButton)
        if mouseButton == "RightButton" and IsControlKeyDown() then
            local state = AutoItemBar:GetButtonState(selfButton)
            if state and state.itemID then
                AutoItemBar:AddHiddenItem(state.itemID)
            end
            return
        end

        if GetCursorInfo() then
            AutoItemBar:HandleDropFromCursor()
        end
    end)

    return button
end

function AutoItemBar:UpdateConsumableButtons()
    wipe(currentConsumables)
    wipe(self.itemLocationById)

    local consumableCount = {}
    local sortedConsumables = {}
    local inCombat = InCombatLockdown()

    for bag = 0, self.NUM_BAG_SLOTS do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID and self:ShouldDisplayItem(itemID) then
                if not currentConsumables[itemID] then
                    tinsert(sortedConsumables, itemID)
                end
                currentConsumables[itemID] = true
                self.itemLocationById[itemID] = { bag = bag, slot = slot }

                local info = C_Container.GetContainerItemInfo(bag, slot)
                local count = info and info.stackCount or 0
                consumableCount[itemID] = (consumableCount[itemID] or 0) + count
            end
        end
    end

    tsort(sortedConsumables, function(a, b)
        return self:SortItems(a, b)
    end)
    self._lastConsumableCount = #sortedConsumables
    local cursorType = GetCursorInfo()
    local showAddSlot = cursorType == "item"

    for index, itemID in ipairs(sortedConsumables) do
        if not self.consumableButtons[itemID] then
            if inCombat then
                self._pendingCombatRefresh = true
            else
                self.consumableButtons[itemID] = self:CreateConsumableButton(itemID, index, #sortedConsumables)
            end
        end

        local button = self.consumableButtons[itemID]
        if button then
            local buttonState = self:GetButtonState(button)
            local row, col = self:GetGridPosition(index, #sortedConsumables)
            local xOffset = col * (self.buttonSize + self.buttonSpacing)
            local yOffset = -row * (self.buttonSize + self.buttonSpacing)
            buttonState.itemID = itemID
            if self._useActionsEnabled ~= false then
                self:AssignUseAction(button, itemID)
            end

            local icon = GetItemIconByID(itemID)
            if icon and icon ~= buttonState.lastIcon then
                if buttonState.iconTexture then
                    buttonState.iconTexture:SetTexture(icon)
                end
                buttonState.lastIcon = icon
            end

            if not inCombat then
                if buttonState.buttonSize ~= self.buttonSize then
                    RefineUI.Size(button, self.buttonSize, self.buttonSize)
                    buttonState.buttonSize = self.buttonSize
                end

                if row ~= buttonState.row or col ~= buttonState.col or xOffset ~= buttonState.xOffset or yOffset ~= buttonState.yOffset then
                    RefineUI.Point(button, "TOPLEFT", xOffset, yOffset)
                    buttonState.row = row
                    buttonState.col = col
                    buttonState.xOffset = xOffset
                    buttonState.yOffset = yOffset
                end
                button:Show()
            elseif row ~= buttonState.row or col ~= buttonState.col or xOffset ~= buttonState.xOffset or yOffset ~= buttonState.yOffset or buttonState.buttonSize ~= self.buttonSize then
                self._pendingCombatRefresh = true
            end

            local countText = (consumableCount[itemID] and consumableCount[itemID] > 1) and consumableCount[itemID] or ""
            if countText ~= buttonState.lastCountText then
                if buttonState.countText then
                    buttonState.countText:SetText(countText)
                end
                buttonState.lastCountText = countText
            end

            local loc = self.itemLocationById[itemID]
            if loc then
                buttonState.bag = loc.bag
                buttonState.slot = loc.slot
                local start, duration = C_Container.GetContainerItemCooldown(loc.bag, loc.slot)
                if buttonState.cooldown and start and duration and duration > 0 then
                    if start ~= buttonState.lastCooldownStart or duration ~= buttonState.lastCooldownDuration then
                        buttonState.cooldown:SetCooldown(start, duration)
                        buttonState.lastCooldownStart = start
                        buttonState.lastCooldownDuration = duration
                    end
                elseif buttonState.cooldown and (buttonState.lastCooldownStart or buttonState.lastCooldownDuration) then
                    buttonState.cooldown:SetCooldown(0, 0)
                    buttonState.lastCooldownStart = nil
                    buttonState.lastCooldownDuration = nil
                end
            end
        end
    end

    for itemID, button in pairs(self.consumableButtons) do
        if not currentConsumables[itemID] then
            if inCombat then
                self._pendingCombatRefresh = true
            else
                button:Hide()
                self.itemLocationById[itemID] = nil
            end
        end
    end

    self:UpdateAddSlotButton(#sortedConsumables, showAddSlot, inCombat)
    self:ApplyDisplayCountSize(#sortedConsumables, inCombat)

    self:SyncInteractivity()
end

function AutoItemBar:RequestUpdate()
    if self.pendingScan then return end
    if self:GetBarVisibilityMode() == self.VISIBILITY_NEVER and not self._editModeActive then
        if self.ConsumableButtonsFrame then
            self._lastVisibleState = nil
            self:EvaluateMouseoverVisibility()
        end
        return
    end
    self.pendingScan = true
    C_Timer.After(0.05, function()
        self.pendingScan = false
        self:UpdateConsumableButtons()
        self:ApplyPendingButtonActions()
        self:UpdateBarVisibility()
    end)
end

----------------------------------------------------------------------------------------
--	Lifecycle Events
----------------------------------------------------------------------------------------

function AutoItemBar:OnEnable()
    local cfg = self:GetConfig()
    if not cfg.Enable then return end

    self._categoryConfigInitialized = nil
    self:EnsureCategoryConfig()
    self:RebuildTrackedLookup()
    self:RebuildHiddenLookup()

    self.buttonSize = cfg.ButtonSize
    self.buttonSpacing = cfg.ButtonSpacing
    local frameWidth, frameHeight = self:GetFrameDimensions(1)

    self.consumableButtons = {}
    self.itemLocationById = {}

    local moverName = MOVER_FRAME_NAME
    local mover = _G[moverName]
    if not mover then
        mover = CreateFrame("Frame", moverName, UIParent)
        mover:SetSize(frameWidth, frameHeight)
        mover:SetFrameStrata("DIALOG")
    end

    self.Mover = mover

    local defaultPos = RefineUI.Positions[moverName]
    local default = { point = "BOTTOMRIGHT", x = 0, y = 0 }
    if defaultPos then
        local p, r, rp, x, y = unpack(defaultPos)
        default = { point = p, x = x, y = y }
    end

    self:RegisterEditModeSettings()

    if cfg.Position then
        local pos = cfg.Position
        local p, r, rp, x, y = unpack(pos)
        if type(r) == "string" then r = _G[r] or UIParent end
        mover:ClearAllPoints()
        mover:SetPoint(p, r, rp, x, y)
    elseif defaultPos then
        local p, r, rp, x, y = unpack(defaultPos)
        if type(r) == "string" then r = _G[r] or UIParent end
        mover:ClearAllPoints()
        mover:SetPoint(p, r, rp, x, y)
    end

    self.ConsumableButtonsFrame = CreateFrame("Frame", MAIN_FRAME_NAME, mover)
    self.ConsumableButtonsFrame:SetPoint("CENTER", mover, "CENTER")
    self.ConsumableButtonsFrame:SetSize(frameWidth, frameHeight)
    self.ConsumableButtonsFrame:Show()

    self.ConsumableBarParent = CreateFrame("Frame", PARENT_FRAME_NAME, mover)
    self.ConsumableBarParent:SetFrameStrata("BACKGROUND")
    self.ConsumableBarParent:SetPoint("CENTER", mover, "CENTER")
    self.ConsumableBarParent:SetSize(frameWidth, frameHeight + 10)
    self.ConsumableBarParent:SetFrameLevel(self.ConsumableButtonsFrame:GetFrameLevel() + 1)
    self:EnsureAddSlotButton()
    self._mouseOverBar = false
    self._lastVisibleState = nil
    self._mouseoverRefreshQueued = false
    self._editModeActive = RefineUI.LibEditMode and RefineUI.LibEditMode:IsInEditMode() or false
    self._pendingCombatRefresh = false
    self._appliedInteractive = nil
    self._pendingEditModeTutorial = nil
    self._lastConsumableCount = 0
    self._cursorHasPayload = (GetCursorInfo() ~= nil)
    self._useActionsEnabled = nil
    self._pendingUseActionsEnabled = nil
    self._forceUseActionRefresh = true

    if RefineUI.LibEditMode and not self._editModeFrameRegistered then
        RefineUI.LibEditMode:AddFrame(mover, function(frame, layout, point, x, y)
            local config = self:GetConfig()
            config.Position = config.Position or {}
            local pos = config.Position
            pos[1], pos[2], pos[3], pos[4], pos[5] = point, "UIParent", point, x, y
        end, default, "Auto Item Bar")
        self._editModeFrameRegistered = true
    end

    if RefineUI.LibEditMode and self._editModeSettings and not self._editModeSettingsAttached then
        RefineUI.LibEditMode:AddFrameSettings(mover, self._editModeSettings)
        self._editModeSettingsAttached = true
    end

    self:HookCategoryManagerToDialog()

    if RefineUI.LibEditMode and not self._editModeCallbacksRegistered then
        RefineUI.LibEditMode:RegisterCallback("enter", function()
            self._editModeActive = true
            self:SyncInteractivity()
            self:ShowBar()
            self:RefreshCategoryManagerVisibility()
        end)
        RefineUI.LibEditMode:RegisterCallback("exit", function()
            self._editModeActive = false
            self:SyncInteractivity()
            self:QueueMouseoverRefresh()
            self:HideCategoryManagerWindow()
            self:HideEditModeTutorial(false)
        end)
        self._editModeCallbacksRegistered = true
    end

    C_Timer.After(1, function()
        self:UpdateConsumableButtons()
        self:SetUseActionsEnabled(not self._cursorHasPayload)
        self:ApplyPendingButtonActions()
        self:UpdateBarVisibility()
    end)

    RefineUI:RegisterEventCallback("BAG_UPDATE_DELAYED", function() self:RequestUpdate() end, "AutoItemBar:BagUpdate")
    RefineUI:RegisterEventCallback("PLAYER_ENTERING_WORLD", function() self:RequestUpdate() end, "AutoItemBar:EnteringWorld")
    RefineUI:RegisterEventCallback("UNIT_INVENTORY_CHANGED", function(_, unit)
        if unit == "player" then self:RequestUpdate() end
    end, "AutoItemBar:InventoryChanged")
    RefineUI:RegisterEventCallback("PLAYER_REGEN_ENABLED", function()
        if self._pendingUseActionsEnabled ~= nil then
            self._useActionsEnabled = nil
            self._forceUseActionRefresh = true
            self:SetUseActionsEnabled(self._pendingUseActionsEnabled)
        else
            self:SetUseActionsEnabled(not self._cursorHasPayload)
        end
        self:ApplyPendingButtonActions()
        if self._pendingCombatRefresh then
            self._pendingCombatRefresh = false
            self:RequestUpdate()
        end
        if self._pendingEditModeTutorial then
            self:TryShowEditModeTutorial()
        end
        self:SyncInteractivity()
        self:QueueMouseoverRefresh()
    end, "AutoItemBar:RegenEnabled")
    RefineUI:RegisterEventCallback("PLAYER_REGEN_DISABLED", function()
        self:UpdateBarVisibility()
    end, "AutoItemBar:RegenDisabled")
    RefineUI:RegisterEventCallback("CURSOR_CHANGED", function()
        local hasCursor = (GetCursorInfo() ~= nil)
        self._cursorHasPayload = hasCursor
        self:SetUseActionsEnabled(not hasCursor)
        self:RefreshAddSlotFromCursor()
        self:QueueMouseoverRefresh()
    end, "AutoItemBar:CursorChanged")

    self.ConsumableBarParent:SetScript("OnEnter", function() self:ShowBar() end)
    self.ConsumableBarParent:SetScript("OnLeave", function() self:QueueMouseoverRefresh() end)
    self.ConsumableBarParent:SetScript("OnReceiveDrag", function()
        self:HandleDropFromCursor()
    end)
    self.ConsumableBarParent:SetScript("OnMouseUp", function(_, _)
        if GetCursorInfo() then
            self:HandleDropFromCursor()
        end
    end)
    self:SyncInteractivity()
end
