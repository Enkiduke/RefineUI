----------------------------------------------------------------------------------------
-- CDM Component: SettingsDragDrop
-- Description: Standalone drag-and-drop behavior for settings assignment ordering.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local CDM = RefineUI:GetModule("CDM")
if not CDM then
    return
end

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local type = type
local CreateFrame = CreateFrame
local UIParent = UIParent
local GetCursorPosition = GetCursorPosition
local GetAppropriateTopLevelParent = GetAppropriateTopLevelParent
local GameTooltip = GameTooltip
local GameTooltip_SetTitle = GameTooltip_SetTitle
local GameTooltip_Hide = GameTooltip_Hide
local InCombatLockdown = InCombatLockdown

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function GetSettingsState(self, settingsFrame)
    local state = self:StateGet(settingsFrame, "settingsInjectionState")
    if not state then
        state = {}
        self:StateSet(settingsFrame, "settingsInjectionState", state)
    end
    return state
end

local function EnsureDragWatcher(self)
    if self.dragWatcher then
        return self.dragWatcher
    end

    local frame = CreateFrame("Frame")
    frame:Hide()
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "GLOBAL_MOUSE_UP" then
            CDM:OnInjectedGlobalMouseUp(...)
        end
    end)
    frame:SetScript("OnUpdate", function()
        if self.dragState then
            self:UpdateInjectedReorderMarker()
        end
    end)

    self.dragWatcher = frame
    return frame
end

local function EnsureDragCursor(self)
    if self.dragCursor then
        return self.dragCursor
    end

    local cursor = nil
    local ok, templateCursor = pcall(CreateFrame, "Frame", nil, GetAppropriateTopLevelParent(), "CooldownViewerSettingsDraggedItemTemplate")
    if ok and templateCursor then
        cursor = templateCursor
    else
        cursor = CreateFrame("Frame", nil, GetAppropriateTopLevelParent())
        cursor:SetSize(38, 38)

        cursor.Bg = cursor:CreateTexture(nil, "BACKGROUND")
        cursor.Bg:SetAllPoints()
        cursor.Bg:SetTexture([[Interface\Buttons\WHITE8x8]])
        cursor.Bg:SetVertexColor(0.02, 0.02, 0.02, 0.92)

        cursor.Icon = cursor:CreateTexture(nil, "ARTWORK")
        cursor.Icon:SetPoint("TOPLEFT", cursor, "TOPLEFT", 5, -5)
        cursor.Icon:SetPoint("BOTTOMRIGHT", cursor, "BOTTOMRIGHT", -5, 5)
        cursor.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        cursor.Border = cursor:CreateTexture(nil, "OVERLAY")
        cursor.Border:SetAllPoints()
        cursor.Border:SetTexture([[Interface\Buttons\UI-Quickslot2]])
    end

    cursor:SetFrameStrata("TOOLTIP")
    cursor:EnableMouse(false)
    cursor:Hide()
    if not cursor.Icon then
        cursor.Icon = cursor:CreateTexture(nil, "ARTWORK")
        cursor.Icon:SetPoint("TOPLEFT", cursor, "TOPLEFT", 5, -5)
        cursor.Icon:SetPoint("BOTTOMRIGHT", cursor, "BOTTOMRIGHT", -5, 5)
        cursor.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    function cursor:SetToCursor(itemFrame)
        if not itemFrame or not itemFrame.Icon then
            self:Hide()
            return
        end

        self.Icon:SetTexture(itemFrame.Icon:GetTexture())
        self:ClearAllPoints()
        local cursorX, cursorY = GetCursorPosition()
        local scale = UIParent:GetScale()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cursorX / scale, cursorY / scale)
        self:Show()
    end

    cursor:SetScript("OnUpdate", function(selfFrame)
        if not CDM.dragState then
            selfFrame:Hide()
            return
        end

        local cursorX, cursorY = GetCursorPosition()
        local scale = UIParent:GetScale()
        selfFrame:ClearAllPoints()
        selfFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cursorX / scale, cursorY / scale)
    end)

    self.dragCursor = cursor
    return cursor
end

local function EnsureReorderMarker(self, settingsFrame)
    if self.reorderMarker then
        return self.reorderMarker
    end

    local marker = nil
    local ok, templateMarker = pcall(CreateFrame, "Frame", nil, settingsFrame, "CooldownViewerSettingsReorderMarkerTemplate")
    if ok and templateMarker then
        marker = templateMarker
    else
        marker = CreateFrame("Frame", nil, settingsFrame)
        marker.Texture = marker:CreateTexture(nil, "OVERLAY")
        marker.Texture:SetAllPoints()
        marker.Texture:SetColorTexture(1, 0.82, 0, 0.9)
    end
    marker:SetFrameStrata("TOOLTIP")
    marker:Hide()
    if not marker.Texture then
        marker.Texture = marker:CreateTexture(nil, "OVERLAY")
        marker.Texture:SetAllPoints()
        marker.Texture:SetColorTexture(1, 0.82, 0, 0.9)
    end

    function marker:SetVertical()
        self:SetSize(4, 42)
        if self.Texture and self.Texture.SetAtlas then
            self.Texture:SetAtlas("cdm-vertical", true)
        end
    end

    function marker:SetHorizontal()
        self:SetSize(42, 4)
        if self.Texture and self.Texture.SetAtlas then
            self.Texture:SetAtlas("cdm-horizontal", true)
        end
    end

    self.reorderMarker = marker
    return marker
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function CDM:GetInjectedItemData(item)
    if not item then
        return nil
    end

    return {
        bucketKey = self:StateGet(item, "bucketKey"),
        cooldownID = self:StateGet(item, "cooldownID"),
        isEmpty = self:StateGet(item, "isEmpty", false),
        displayIndex = self:StateGet(item, "displayIndex", 1),
        assignmentIndex = self:StateGet(item, "assignmentIndex"),
    }
end

function CDM:SetInjectedDragTarget(categoryFrame, itemFrame)
    local drag = self.dragState
    if not drag then
        return
    end

    if categoryFrame then
        drag.targetCategory = categoryFrame
    end
    drag.targetItem = itemFrame
end

function CDM:OnInjectedCategoryEnter(categoryFrame)
    self:SetInjectedDragTarget(categoryFrame, nil)
end

function CDM:OnInjectedItemEnter(itemFrame)
    local categoryFrame = self:StateGet(itemFrame, "categoryFrame")
    self:SetInjectedDragTarget(categoryFrame, itemFrame)

    local data = self:GetInjectedItemData(itemFrame)
    if not data then
        return
    end

    if data.isEmpty then
        GameTooltip:SetOwner(itemFrame, "ANCHOR_RIGHT")
        GameTooltip_SetTitle(GameTooltip, "Empty Slot")
        GameTooltip:Show()
        return
    end

    local info = self:GetCooldownInfo(data.cooldownID)
    local spellID = self:ResolveCooldownSpellID(info)
    if spellID then
        GameTooltip:SetOwner(itemFrame, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(spellID, false)
        GameTooltip:Show()
    end
end

function CDM:OnInjectedItemLeave()
    GameTooltip_Hide()
end

function CDM:OnInjectedGlobalMouseUp(_button)
    if not self.dragState then
        return
    end
    self:EndInjectedOrderChange(true)
end

function CDM:UpdateInjectedReorderMarker()
    local drag = self.dragState
    if not drag then
        return
    end

    local marker = self.reorderMarker
    if not marker then
        return
    end

    local targetCategory = drag.targetCategory
    if not targetCategory then
        marker:Hide()
        return
    end

    local cursorX, cursorY = GetCursorPosition()
    local scale = GetAppropriateTopLevelParent():GetScale()
    cursorX, cursorY = cursorX / scale, cursorY / scale

    local targetItem = targetCategory:GetBestCooldownItemTarget(cursorX, cursorY)
    marker:SetShown(targetItem ~= nil)
    if not targetItem then
        return
    end

    drag.targetItem = targetItem
    marker:ClearAllPoints()
    marker:SetVertical()
    local centerX = targetItem:GetCenter()
    if centerX and cursorX < centerX then
        marker:SetPoint("CENTER", targetItem, "LEFT", -4, 0)
        drag.reorderOffset = 0
    else
        marker:SetPoint("CENTER", targetItem, "RIGHT", 4, 0)
        drag.reorderOffset = 1
    end
end

function CDM:EndInjectedOrderChange(applyDrop)
    local drag = self.dragState
    if not drag then
        return
    end

    local sourceData = self:GetInjectedItemData(drag.sourceItem)
    local targetCategoryData = drag.targetCategory and self:StateGet(drag.targetCategory, "categoryData")
    local targetItemData = self:GetInjectedItemData(drag.targetItem)

    if applyDrop and not self:IsStandaloneSettingsReadOnly() and sourceData and sourceData.cooldownID and targetCategoryData then
        local cooldownID = sourceData.cooldownID
        local sourceBucket = sourceData.bucketKey
        local sourceAssignmentIndex = sourceData.assignmentIndex
        local targetBucket = targetCategoryData.bucketKey

        if targetBucket == CDM.NOT_TRACKED_KEY then
            self:UnassignCooldownID(cooldownID)
        elseif targetBucket and targetBucket ~= CDM.NOT_TRACKED_KEY then
            local destIndex
            if targetItemData and not targetItemData.isEmpty and targetItemData.assignmentIndex then
                destIndex = targetItemData.assignmentIndex + (drag.reorderOffset or 0)
            else
                local list = self:GetBucketCooldownIDs(targetBucket)
                destIndex = #list + 1
            end

            if sourceBucket == targetBucket and sourceAssignmentIndex and destIndex and sourceAssignmentIndex < destIndex then
                destIndex = destIndex - 1
            end

            self:AssignCooldownToBucket(cooldownID, targetBucket, destIndex)
        end
    end

    if drag.sourceItem then
        drag.sourceItem:SetReorderLocked(false)
    end

    if self.reorderMarker then
        self.reorderMarker:Hide()
    end
    if self.dragCursor then
        self.dragCursor:Hide()
    end
    if self.dragWatcher then
        self.dragWatcher:UnregisterEvent("GLOBAL_MOUSE_UP")
        self.dragWatcher:Hide()
    end

    self.dragState = nil
    self:RequestRefresh(true)
end

function CDM:BeginInjectedOrderChange(settingsFrame, itemFrame)
    if self.dragState or not settingsFrame or not itemFrame then
        return
    end
    if self:IsStandaloneSettingsReadOnly() or (type(InCombatLockdown) == "function" and InCombatLockdown()) then
        return
    end

    local itemData = self:GetInjectedItemData(itemFrame)
    if not itemData or itemData.isEmpty or not itemData.cooldownID then
        return
    end

    local marker = EnsureReorderMarker(self, settingsFrame)
    local cursor = EnsureDragCursor(self)
    local watcher = EnsureDragWatcher(self)

    self.dragState = {
        settingsFrame = settingsFrame,
        sourceItem = itemFrame,
        targetCategory = self:StateGet(itemFrame, "categoryFrame"),
        targetItem = itemFrame,
        reorderOffset = 0,
    }

    itemFrame:SetReorderLocked(true)
    marker:Hide()
    cursor:SetToCursor(itemFrame)

    watcher:RegisterEvent("GLOBAL_MOUSE_UP")
    watcher:Show()
end
