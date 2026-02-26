----------------------------------------------------------------------------------------
-- CDM Component: SettingsDragDrop
-- Description: Drag-and-drop behavior for injected settings assignment ordering.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local CDM = RefineUI:GetModule("CDM")
if not CDM then
    return
end

----------------------------------------------------------------------------------------
-- Shared Aliases (Explicit)
----------------------------------------------------------------------------------------
local Config = RefineUI.Config
local Media = RefineUI.Media
local Colors = RefineUI.Colors
local Locale = RefineUI.Locale

----------------------------------------------------------------------------------------
-- Lua / WoW Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local type = type
local tinsert = table.insert
local wipe = _G.wipe or table.wipe
local strfind = string.find
local strlower = string.lower
local max = math.max
local CreateFrame = CreateFrame
local UIParent = UIParent
local PlaySound = PlaySound
local SOUNDKIT = _G.SOUNDKIT
local GetCursorPosition = GetCursorPosition
local GetAppropriateTopLevelParent = GetAppropriateTopLevelParent
local GameTooltip = GameTooltip
local GameTooltip_SetTitle = GameTooltip_SetTitle
local GameTooltip_Hide = GameTooltip_Hide
local GetCVarBool = GetCVarBool
local SetCVar = SetCVar

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local SETTINGS_BUCKET_ORDER = { "Left", "Right", "Bottom", CDM.NOT_TRACKED_KEY }
local CUSTOM_DISPLAY_MODE = "refineui"
local CUSTOM_TAB_TOOLTIP = "RefineUI"
local CUSTOM_TAB_ATLAS = "minimap-genericevent-hornicon-small"
local CUSTOM_TAB_TEXTURE = (RefineUI.Media and RefineUI.Media.Logo) or [[Interface\AddOns\RefineUI\Media\Logo\Logo.blp]]
local AURA_MODE_REFINED = "refineui"
local AURA_MODE_BLIZZARD = "blizzard"
local DRAG_MARKER_UPDATE_JOB_KEY = CDM:BuildKey("Settings", "DragMarkerUpdate")

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
            local button = ...
            CDM:OnInjectedGlobalMouseUp(button)
        end
    end)

    self.dragWatcher = frame
    return frame
end


local function EnsureDragMarkerUpdateJob(self)
    if self.dragMarkerUpdateJobRegistered then
        return true
    end
    if not RefineUI.RegisterUpdateJob then
        return false
    end

    local ok = RefineUI:RegisterUpdateJob(DRAG_MARKER_UPDATE_JOB_KEY, 0, function()
        CDM:UpdateInjectedReorderMarker()
    end, {
        enabled = false,
        safe = true,
        disableOnError = true,
    })
    if ok then
        self.dragMarkerUpdateJobRegistered = true
        return true
    end
    return false
end


local function SetDragMarkerUpdateEnabled(self, enabled)
    if not EnsureDragMarkerUpdateJob(self) then
        return
    end
    if RefineUI.SetUpdateJobEnabled then
        RefineUI:SetUpdateJobEnabled(DRAG_MARKER_UPDATE_JOB_KEY, enabled, true)
    end
    if enabled and RefineUI.RunUpdateJobNow then
        RefineUI:RunUpdateJobNow(DRAG_MARKER_UPDATE_JOB_KEY)
    end
end


local function EnsureDragCursor(self)
    if self.dragCursor then
        return self.dragCursor
    end

    local cursor = CreateFrame("Frame", nil, GetAppropriateTopLevelParent(), "CooldownViewerSettingsDraggedItemTemplate")
    cursor:Hide()
    self.dragCursor = cursor
    return cursor
end


local function EnsureReorderMarker(self, settingsFrame)
    if self.reorderMarker then
        return self.reorderMarker
    end

    local state = GetSettingsState(self, settingsFrame)
    local panel = state.panel
    local marker = panel and panel.ReorderMarker
    if not marker and _G.CooldownViewerSettingsReorderMarkerTemplate then
        local ok, created = pcall(CreateFrame, "Frame", nil, panel, "CooldownViewerSettingsReorderMarkerTemplate")
        if ok then
            marker = created
        end
    end

    if not marker then
        marker = CreateFrame("Frame", nil, panel)
        marker:SetSize(8, 52)
        marker.Texture = marker:CreateTexture(nil, "OVERLAY")
        marker.Texture:SetAllPoints()
        marker.Texture:SetColorTexture(1, 1, 1, 0.85)
    end

    if not marker.SetVertical then
        function marker:SetVertical()
            self:SetSize(8, 52)
            if self.Texture and self.Texture.SetAtlas then
                self.Texture:SetAtlas("cdm-vertical", true)
            end
        end
    end

    if not marker.SetHorizontal then
        function marker:SetHorizontal()
            self:SetSize(52, 8)
            if self.Texture and self.Texture.SetAtlas then
                self.Texture:SetAtlas("cdm-horizontal", true)
            end
        end
    end

    marker:Hide()
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


function CDM:OnInjectedGlobalMouseUp(button)
    local drag = self.dragState
    if not drag then
        return
    end

    if drag.eatNextGlobalMouseUp == button then
        drag.eatNextGlobalMouseUp = nil
        return
    end

    if PlaySound and SOUNDKIT and SOUNDKIT.UI_CURSOR_DROP_OBJECT then
        PlaySound(SOUNDKIT.UI_CURSOR_DROP_OBJECT)
    end

    if button == "LeftButton" then
        self:EndInjectedOrderChange(true)
    elseif button == "RightButton" then
        self:EndInjectedOrderChange(false)
    end
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

    if applyDrop and sourceData and sourceData.cooldownID and targetCategoryData then
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

    if drag.sourceItem and drag.sourceItem.RefreshIconState then
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
    SetDragMarkerUpdateEnabled(self, false)

    self.dragState = nil
    self:RequestRefresh()
end


function CDM:BeginInjectedOrderChange(settingsFrame, itemFrame, eatNextGlobalMouseUp)
    if self.dragState then
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
        eatNextGlobalMouseUp = eatNextGlobalMouseUp,
    }

    itemFrame:SetReorderLocked(true)
    marker:Hide()
    cursor:SetToCursor(itemFrame)

    watcher:RegisterEvent("GLOBAL_MOUSE_UP")
    watcher:Show()
    SetDragMarkerUpdateEnabled(self, true)
end

