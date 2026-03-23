----------------------------------------------------------------------------------------
-- CDM Component: SettingsUI
-- Description: Standalone RefineUI settings panel for tracked aura assignments.
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
local pairs = pairs
local pcall = pcall
local wipe = _G.wipe or table.wipe
local strfind = string.find
local strlower = string.lower
local max = math.max
local CreateFrame = CreateFrame
local CreateFramePool = CreateFramePool
local UIParent = UIParent
local GetCursorPosition = GetCursorPosition
local GetTime = GetTime
local GetCVarBool = GetCVarBool
local SetCVar = SetCVar
local ShowUIPanel = ShowUIPanel
local HideUIPanel = HideUIPanel
local InCombatLockdown = InCombatLockdown

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local SETTINGS_BUCKET_ORDER = { "Left", "Right", "Bottom", "Radial", CDM.NOT_TRACKED_KEY }
local PANEL_REFRESH_TIMER_KEY = CDM:BuildKey("Settings", "PanelRefresh")
local SEARCH_DEBOUNCE_KEY = CDM:BuildKey("Settings", "SearchRefresh")
local HEADER_HEIGHT = 32
local ITEM_SIZE = 38
local ITEM_SPACING = 6
local ITEM_COLUMNS = 10
local PANEL_WIDTH = 900
local PANEL_HEIGHT = 640
local DISPLAY_MODE_SPELLS = "spells"
local DISPLAY_MODE_AURAS = "auras"
local DISPLAY_MODE_REFINE = "refineui"
local EMPTY_ICON_TEXTURE = 134400
local ICON_BORDER_TEXTURE = [[Interface\Buttons\UI-Quickslot2]]
local ICON_HIGHLIGHT_TEXTURE = [[Interface\Buttons\ButtonHilight-Square]]
local ITEM_BACKGROUND_TEXTURE = [[Interface\Buttons\WHITE8x8]]
local BLIZZARD_FALLBACK_WIDTH = 860
local BLIZZARD_FALLBACK_HEIGHT = 620
local BLIZZARD_SETTINGS_REDIRECT_HOOK_KEY = "CDM:Settings:Blizzard:RedirectOnShow"
local POST_RELOAD_OPEN_TIMER_KEY = CDM:BuildKey("Settings", "PostReloadOpen")
local REFINE_TAB_TOOLTIP = "RefineUI"
local REFINE_TAB_ATLAS = "minimap-genericevent-hornicon-small"
local REFINE_TAB_TEXTURE = (RefineUI.Media and RefineUI.Media.Logo) or [[Interface\AddOns\RefineUI\Media\Logo\Logo.blp]]
local SPELLS_TAB_TOOLTIP = _G.COOLDOWN_VIEWER_SETTINGS_TAB_SPELLS or "Spells"
local AURAS_TAB_TOOLTIP = _G.COOLDOWN_VIEWER_SETTINGS_TAB_BUFFS or "Auras"
local SPELLS_TAB_ATLAS = "icon_cooldownmanager"
local AURAS_TAB_ATLAS = "icon_trackedbuffs"
local BLIZZARD_OWNER_OVERLAY_TITLE = "Blizzard CDM Disabled"
local BLIZZARD_OWNER_OVERLAY_TEXT = "RefineUI CDM is enabled. Enable Blizzard CDM for this tab to edit Blizzard cooldown settings here."
local BLIZZARD_OWNER_OVERLAY_BUTTON = "Enable Blizzard CDM"
local REFINE_OWNER_OVERLAY_TITLE = "RefineUI CDM Disabled"
local REFINE_OWNER_OVERLAY_TEXT = "Blizzard CDM is enabled. Enable RefineUI CDM for this tab to edit RefineUI tracker assignments here."
local REFINE_OWNER_OVERLAY_BUTTON = "Enable RefineUI CDM"
local POST_COMBAT_SETTINGS_OPEN_DELAY = 0.75

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function IsFilterActive(filterText)
    return type(filterText) == "string" and #filterText > 1
end

local function GetSettingsState(self, settingsFrame)
    local state = self:StateGet(settingsFrame, "settingsInjectionState")
    if not state then
        state = {}
        self:StateSet(settingsFrame, "settingsInjectionState", state)
    end
    return state
end

local function IsShowingUnlearned()
    return GetCVarBool and GetCVarBool("cooldownViewerShowUnlearned") or false
end

local function ToggleShowUnlearned()
    SetCVar("cooldownViewerShowUnlearned", not IsShowingUnlearned())
end

local function CreateOwnerOverlay(parent, titleText, bodyText, buttonText, onClick)
    local overlay = CreateFrame("Frame", nil, parent)
    overlay:EnableMouse(true)
    overlay:SetFrameStrata("DIALOG")

    local frameLevel = 1
    if parent and type(parent.GetFrameLevel) == "function" then
        local ok, level = pcall(parent.GetFrameLevel, parent)
        if ok and type(level) == "number" then
            frameLevel = level
        end
    end
    overlay:SetFrameLevel(frameLevel + 30)
    overlay:Hide()

    overlay.Background = overlay:CreateTexture(nil, "BACKGROUND")
    overlay.Background:SetAllPoints()
    overlay.Background:SetColorTexture(0, 0, 0, 0.8)

    overlay.Title = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    overlay.Title:SetPoint("TOP", overlay, "TOP", 0, -120)
    overlay.Title:SetText(titleText)

    overlay.Text = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    overlay.Text:SetPoint("TOP", overlay.Title, "BOTTOM", 0, -12)
    overlay.Text:SetWidth(300)
    overlay.Text:SetJustifyH("CENTER")
    overlay.Text:SetText(bodyText)

    overlay.Button = CreateFrame("Button", nil, overlay, "UIPanelButtonTemplate")
    overlay.Button:SetSize(180, 24)
    overlay.Button:SetPoint("TOP", overlay.Text, "BOTTOM", 0, -18)
    overlay.Button:SetText(buttonText)
    overlay.Button:SetScript("OnClick", onClick)

    return overlay
end

local function EnsureCategoryObject(bucketKey, titleText)
    local obj = {
        bucketKey = bucketKey,
        titleText = titleText,
        collapsed = false,
    }

    function obj:GetCategory()
        return self.bucketKey
    end

    function obj:GetTitle()
        return self.titleText
    end

    function obj:ShouldDisplayInfo(_info)
        return true
    end

    function obj:SetCollapsed(collapsed)
        self.collapsed = collapsed and true or false
    end

    function obj:IsCollapsed()
        return self.collapsed == true
    end

    return obj
end

local function CreateFrameWithTemplate(frameType, parent, template)
    local ok, frame = pcall(CreateFrame, frameType, nil, parent, template)
    if ok and frame then
        return frame
    end
    return nil
end

local function AddToUISpecialFrames(frameName)
    local specialFrames = _G.UISpecialFrames
    if type(specialFrames) ~= "table" or type(frameName) ~= "string" or frameName == "" then
        return
    end

    for i = 1, #specialFrames do
        if specialFrames[i] == frameName then
            return
        end
    end

    specialFrames[#specialFrames + 1] = frameName
end

local function ResolveSpellIcon(cooldownID)
    local info = CDM:GetCooldownInfo(cooldownID)
    local spellID = CDM:ResolveCooldownSpellID(info)
    if type(spellID) == "number" and C_Spell and type(C_Spell.GetSpellTexture) == "function" then
        local texture = C_Spell.GetSpellTexture(spellID)
        if texture then
            return texture
        end
    end
    return EMPTY_ICON_TEXTURE
end

local function CreateInsetFrame(parent)
    local templates = {
        "InsetFrameTemplate3",
        "InsetFrameTemplate",
    }

    for i = 1, #templates do
        local ok, frame = pcall(CreateFrame, "Frame", nil, parent, templates[i])
        if ok and frame then
            return frame
        end
    end

    local frame = CreateFrame("Frame", nil, parent)
    frame.Bg = frame.Bg or frame:CreateTexture(nil, "BACKGROUND")
    frame.Bg:SetAllPoints()
    frame.Bg:SetTexture(ITEM_BACKGROUND_TEXTURE)
    frame.Bg:SetVertexColor(0.03, 0.03, 0.03, 0.72)
    return frame
end

local function EnsureRefineItemBorder(itemFrame)
    if not itemFrame then
        return nil
    end

    if not itemFrame.SetTemplate then
        RefineUI:AddAPI(itemFrame)
    end

    if not itemFrame.border and itemFrame.SetTemplate then
        itemFrame:SetTemplate("Icon")
    end

    return itemFrame.border
end

local function HideTextureRegion(region)
    if region and type(region.SetAlpha) == "function" then
        region:SetAlpha(0)
    end
end

local function RegisterStandalonePanelWindow(frameName)
    local panelWindows = _G.UIPanelWindows
    if type(panelWindows) ~= "table" or type(frameName) ~= "string" or frameName == "" then
        return
    end

    if type(panelWindows[frameName]) ~= "table" then
        panelWindows[frameName] = {
            area = "left",
            pushable = 1,
            whileDead = 1,
        }
    end
end

local function SanitizeItemArt(itemFrame)
    if not itemFrame then
        return
    end

    local border = EnsureRefineItemBorder(itemFrame)
    if border then
        if type(border.SetBackdropColor) == "function" then
            border:SetBackdropColor(0, 0, 0, 0)
        end
    end

    if itemFrame.bg and type(itemFrame.bg.SetAlpha) == "function" then
        itemFrame.bg:SetAlpha(0)
    end
    if itemFrame.RefineBackdrop and type(itemFrame.RefineBackdrop.SetAlpha) == "function" then
        itemFrame.RefineBackdrop:SetAlpha(0)
    end
    if itemFrame.Bg and type(itemFrame.Bg.SetAlpha) == "function" then
        itemFrame.Bg:SetAlpha(0)
    end

    if border then
        if border.bg and type(border.bg.SetAlpha) == "function" then
            border.bg:SetAlpha(0)
        end
        if border.Bg and type(border.Bg.SetAlpha) == "function" then
            border.Bg:SetAlpha(0)
        end
    end

    if itemFrame.IconBorder and type(itemFrame.IconBorder.SetAlpha) == "function" then
        itemFrame.IconBorder:SetAlpha(0)
    end
    HideTextureRegion(itemFrame.Border)
    HideTextureRegion(itemFrame.SelectedTexture)
    HideTextureRegion(itemFrame.Selection)
    HideTextureRegion(itemFrame.Glow)
    HideTextureRegion(itemFrame.Ring)
    HideTextureRegion(itemFrame.HighlightTexture)
    HideTextureRegion(itemFrame.NormalTexture)
    HideTextureRegion(itemFrame.PushedTexture)
    HideTextureRegion(itemFrame.CheckedTexture)
    HideTextureRegion(itemFrame.DisabledTexture)

    if type(itemFrame.GetNormalTexture) == "function" then
        HideTextureRegion(itemFrame:GetNormalTexture())
    end
    if type(itemFrame.GetPushedTexture) == "function" then
        HideTextureRegion(itemFrame:GetPushedTexture())
    end
    if type(itemFrame.GetHighlightTexture) == "function" then
        HideTextureRegion(itemFrame:GetHighlightTexture())
    end
    if type(itemFrame.GetCheckedTexture) == "function" then
        HideTextureRegion(itemFrame:GetCheckedTexture())
    end
end

local function ApplyItemBorder(itemFrame, cooldownID)
    if not itemFrame then
        return
    end

    local color
    if type(cooldownID) == "number" and cooldownID > 0 then
        if CDM.GetCooldownBorderColor then
            color = CDM:GetCooldownBorderColor(cooldownID)
        end
    elseif CDM.GetDefaultBorderColor then
        color = CDM:GetDefaultBorderColor()
    else
        color = { 1, 1, 1, 0.92 }
    end

    SanitizeItemArt(itemFrame)

    local border = EnsureRefineItemBorder(itemFrame)
    if border and type(border.SetBackdropBorderColor) == "function" then
        border:SetBackdropBorderColor(color[1], color[2], color[3], color[4] or 1)
    end
    if itemFrame.SelectionGlow then
        itemFrame.SelectionGlow:SetVertexColor(1, 0.82, 0.05, 0.65)
    end
end

local function UpdateItemVisualState(itemFrame)
    if not itemFrame then
        return
    end

    if itemFrame.Highlight then
        itemFrame.Highlight:SetShown(itemFrame:IsMouseOver() and not itemFrame.dragLocked)
    end

    if itemFrame.Background then
        if itemFrame.dragLocked then
            itemFrame.Background:SetVertexColor(0.08, 0.08, 0.08, 0.96)
        elseif itemFrame.isEmpty then
            itemFrame.Background:SetVertexColor(0.06, 0.06, 0.06, 0.78)
        else
            itemFrame.Background:SetVertexColor(0.02, 0.02, 0.02, 0.9)
        end
    end

    itemFrame:SetAlpha(itemFrame.dragLocked and 0.5 or (itemFrame.isEmpty and 0.55 or 1))
end

local function CreateItemArt(itemFrame)
    SanitizeItemArt(itemFrame)

    itemFrame.Background = itemFrame:CreateTexture(nil, "BACKGROUND")
    itemFrame.Background:SetAllPoints()
    itemFrame.Background:SetTexture(ITEM_BACKGROUND_TEXTURE)
    itemFrame.Background:SetVertexColor(0.02, 0.02, 0.02, 0.9)

    itemFrame.Icon = itemFrame:CreateTexture(nil, "ARTWORK")
    itemFrame.Icon:SetPoint("TOPLEFT", itemFrame, "TOPLEFT", 5, -5)
    itemFrame.Icon:SetPoint("BOTTOMRIGHT", itemFrame, "BOTTOMRIGHT", -5, 5)
    itemFrame.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    itemFrame.IconBorder = itemFrame:CreateTexture(nil, "OVERLAY")
    itemFrame.IconBorder:SetAllPoints()
    itemFrame.IconBorder:SetTexture(ICON_BORDER_TEXTURE)
    itemFrame.IconBorder:SetBlendMode("BLEND")
    itemFrame.IconBorder:SetAlpha(0)

    itemFrame.Highlight = itemFrame:CreateTexture(nil, "HIGHLIGHT")
    itemFrame.Highlight:SetAllPoints()
    itemFrame.Highlight:SetTexture(ICON_HIGHLIGHT_TEXTURE)
    itemFrame.Highlight:SetBlendMode("ADD")
    itemFrame.Highlight:SetAlpha(0.3)
    itemFrame.Highlight:Hide()

    itemFrame.SelectionGlow = itemFrame:CreateTexture(nil, "OVERLAY")
    itemFrame.SelectionGlow:SetTexture([[Interface\Buttons\UI-ActionButton-Border]])
    itemFrame.SelectionGlow:SetBlendMode("ADD")
    itemFrame.SelectionGlow:SetSize(64, 64)
    itemFrame.SelectionGlow:SetPoint("CENTER")
    itemFrame.SelectionGlow:Hide()

    itemFrame.EmptyText = itemFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    itemFrame.EmptyText:SetPoint("CENTER", itemFrame, "CENTER", 0, 0)
    itemFrame.EmptyText:SetText("+")
    itemFrame.EmptyText:Hide()

    itemFrame:HookScript("OnEnter", function(frame)
        if frame.Highlight and not frame.dragLocked then
            frame.Highlight:Show()
        end
        if frame.SelectionGlow and not frame.isEmpty then
            frame.SelectionGlow:Show()
        end
    end)
    itemFrame:HookScript("OnLeave", function(frame)
        if frame.Highlight then
            frame.Highlight:Hide()
        end
        if frame.SelectionGlow then
            frame.SelectionGlow:Hide()
        end
    end)
end

local function CreateCategoryHeader(categoryFrame, titleText)
    categoryFrame.Header = CreateFrame("Frame", nil, categoryFrame)
    categoryFrame.Header:SetPoint("TOPLEFT", categoryFrame, "TOPLEFT", 0, 0)
    categoryFrame.Header:SetPoint("TOPRIGHT", categoryFrame, "TOPRIGHT", 0, 0)
    categoryFrame.Header:SetHeight(HEADER_HEIGHT)

    categoryFrame.HeaderBg = categoryFrame.Header:CreateTexture(nil, "BACKGROUND")
    categoryFrame.HeaderBg:SetAllPoints()
    categoryFrame.HeaderBg:SetTexture(ITEM_BACKGROUND_TEXTURE)
    categoryFrame.HeaderBg:SetVertexColor(0.14, 0.14, 0.14, 0.9)

    categoryFrame.HeaderTop = categoryFrame.Header:CreateTexture(nil, "BORDER")
    categoryFrame.HeaderTop:SetPoint("TOPLEFT", categoryFrame.Header, "TOPLEFT", 0, 0)
    categoryFrame.HeaderTop:SetPoint("TOPRIGHT", categoryFrame.Header, "TOPRIGHT", 0, 0)
    categoryFrame.HeaderTop:SetHeight(1)
    categoryFrame.HeaderTop:SetTexture(ITEM_BACKGROUND_TEXTURE)
    categoryFrame.HeaderTop:SetVertexColor(1, 1, 1, 0.08)

    categoryFrame.HeaderBottom = categoryFrame.Header:CreateTexture(nil, "BORDER")
    categoryFrame.HeaderBottom:SetPoint("BOTTOMLEFT", categoryFrame.Header, "BOTTOMLEFT", 0, 0)
    categoryFrame.HeaderBottom:SetPoint("BOTTOMRIGHT", categoryFrame.Header, "BOTTOMRIGHT", 0, 0)
    categoryFrame.HeaderBottom:SetHeight(1)
    categoryFrame.HeaderBottom:SetTexture(ITEM_BACKGROUND_TEXTURE)
    categoryFrame.HeaderBottom:SetVertexColor(0, 0, 0, 0.65)

    categoryFrame.Title = categoryFrame.Header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    categoryFrame.Title:SetPoint("LEFT", categoryFrame.Header, "LEFT", 12, 0)
    categoryFrame.Title:SetPoint("RIGHT", categoryFrame.Header, "RIGHT", -12, 0)
    categoryFrame.Title:SetJustifyH("LEFT")
    categoryFrame.Title:SetText(titleText)
end

local function CreateCategoryContainer(categoryFrame)
    local inset = CreateInsetFrame(categoryFrame)
    inset:SetPoint("TOPLEFT", categoryFrame.Header, "BOTTOMLEFT", 0, -8)
    inset:SetPoint("TOPRIGHT", categoryFrame.Header, "BOTTOMRIGHT", 0, -8)
    inset:SetHeight(1)
    inset:EnableMouse(true)

    local container = CreateFrame("Frame", nil, inset)
    container:SetPoint("TOPLEFT", inset, "TOPLEFT", 10, -10)
    container:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -10, -10)
    container:SetHeight(1)
    container:EnableMouse(true)

    categoryFrame.ContainerInset = inset
    categoryFrame.Container = container
end

local function GetNearestVisibleItemWeighted(itemIterator)
    local cursorX, cursorY = GetCursorPosition()
    local scale = UIParent:GetScale()
    cursorX, cursorY = cursorX / scale, cursorY / scale

    local nearestItem
    local nearestVertical = math.huge
    local nearestHorizontal = math.huge

    for item in itemIterator do
        local left, right, bottom, top = item:GetLeft(), item:GetRight(), item:GetBottom(), item:GetTop()
        if left and right and bottom and top and item:IsShown() then
            local centerX = (left + right) / 2
            local centerY = (bottom + top) / 2
            local horizontalDistance = math.abs(centerX - cursorX)
            local verticalDistance = math.abs(centerY - cursorY)
            if cursorY > bottom and cursorY < top then
                verticalDistance = 0
            end
            if verticalDistance < nearestVertical
                or (verticalDistance == nearestVertical and horizontalDistance < nearestHorizontal)
            then
                nearestItem = item
                nearestVertical = verticalDistance
                nearestHorizontal = horizontalDistance
            end
        end
    end

    return nearestItem
end

local function UpdateCategoryHeight(categoryFrame, shownItems)
    local rows = math.max(1, math.ceil(shownItems / ITEM_COLUMNS))
    local contentHeight = rows * ITEM_SIZE + ((rows - 1) * ITEM_SPACING)
    categoryFrame.Container:SetHeight(contentHeight)

    if categoryFrame.ContainerInset then
        categoryFrame.ContainerInset:SetHeight(contentHeight + 20)
    end

    categoryFrame:SetHeight(HEADER_HEIGHT + 8 + (categoryFrame.ContainerInset and categoryFrame.ContainerInset:GetHeight() or contentHeight))
end

local function ResetNativePooledItem(_, itemFrame)
    itemFrame:Hide()
    itemFrame.layoutIndex = nil
    itemFrame.cooldownID = nil
    itemFrame.assignmentIndex = nil
end

local function TryCreateNativeCategory(scrollChild, categoryObject)
    local categoryFrame = CreateFrameWithTemplate("Frame", scrollChild, "CooldownViewerSettingsCategoryTemplate")
    if not categoryFrame then
        return nil
    end

    if type(categoryFrame.Init) == "function" then
        categoryFrame:Init(categoryObject)
    elseif categoryFrame.Header and type(categoryFrame.Header.SetHeaderText) == "function" then
        categoryFrame.Header:SetHeaderText(categoryObject:GetTitle())
    end

    if categoryFrame.Header then
        if categoryFrame.Header.CollapseButton then
            categoryFrame.Header.CollapseButton:Hide()
            categoryFrame.Header.CollapseButton:Disable()
        end
        if categoryFrame.Header.Toggle then
            categoryFrame.Header.Toggle:Hide()
            categoryFrame.Header.Toggle:Disable()
        end
    end

    if not categoryFrame.Container then
        categoryFrame.Container = CreateFrame("Frame", nil, categoryFrame)
        categoryFrame.Container:SetPoint("TOPLEFT", categoryFrame, "TOPLEFT", 0, 0)
        categoryFrame.Container:SetPoint("TOPRIGHT", categoryFrame, "TOPRIGHT", 0, 0)
    end

    if CreateFramePool then
        local ok, itemPool = pcall(CreateFramePool, "Frame", categoryFrame.Container, "CooldownViewerSettingsItemTemplate", ResetNativePooledItem)
        if ok and itemPool then
            categoryFrame.itemPool = itemPool
        end
    end

    function categoryFrame:GetNearestItemToCursorWeighted()
        if not self.itemPool then
            return nil
        end
        return GetNearestVisibleItemWeighted(self.itemPool:EnumerateActive())
    end

    function categoryFrame:GetBestCooldownItemTarget()
        return self:GetNearestItemToCursorWeighted()
    end

    function categoryFrame:SetCollapsed(collapsed)
        self.collapsed = collapsed and true or false
        if self.categoryObject and type(self.categoryObject.SetCollapsed) == "function" then
            self.categoryObject:SetCollapsed(self.collapsed)
        end
        if self.Header and type(self.Header.UpdateCollapsedState) == "function" then
            self.Header:UpdateCollapsedState(self.collapsed)
        end
        if self.Container then
            self.Container:SetShown(not self.collapsed)
            if self.Container.Layout then
                self.Container:Layout()
            end
        end
    end

    function categoryFrame:IsCollapsed()
        return self.collapsed == true
    end

    function categoryFrame:GetCategoryObject()
        return self.categoryObject
    end

    function categoryFrame:ToggleCollapsed()
        self:SetCollapsed(not self:IsCollapsed())
        CDM:RequestRefineTabPanelRefresh(CDM:GetCooldownViewerSettingsFrame())
    end

    categoryFrame.categoryObject = categoryObject
    categoryFrame:SetCollapsed(categoryObject:IsCollapsed())

    if categoryFrame.Header and type(categoryFrame.Header.SetClickHandler) == "function" then
        categoryFrame.Header:SetClickHandler(function(_, button)
            if button == "LeftButton" then
                categoryFrame:ToggleCollapsed()
            end
        end)
    elseif categoryFrame.Header then
        categoryFrame.Header:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" then
                categoryFrame:ToggleCollapsed()
            end
        end)
    end

    return categoryFrame
end

local function UpdateSettingsDropdownState(settingsFrame)
    if not settingsFrame or not settingsFrame.SettingsDropdown then
        return
    end

    local disabled = CDM:IsStandaloneSettingsReadOnly()
    settingsFrame.SettingsDropdown:SetEnabled(not disabled)
    settingsFrame.SettingsDropdown:SetAlpha(disabled and 0.45 or 1)
end

local function InitializeInjectedItem(settingsFrame, itemFrame, categoryFrame)
    if CDM:StateGet(itemFrame, "standaloneInitialized", false) then
        CDM:StateSet(itemFrame, "categoryFrame", categoryFrame)
        SanitizeItemArt(itemFrame)
        return
    end

    if type(itemFrame.SetNormalTexture) == "function" then
        itemFrame:SetNormalTexture("")
    end
    if type(itemFrame.SetPushedTexture) == "function" then
        itemFrame:SetPushedTexture("")
    end
    if type(itemFrame.SetHighlightTexture) == "function" then
        itemFrame:SetHighlightTexture("")
    end
    if type(itemFrame.SetCheckedTexture) == "function" then
        itemFrame:SetCheckedTexture("")
    end
    if type(itemFrame.SetDisabledTexture) == "function" then
        itemFrame:SetDisabledTexture("")
    end
    SanitizeItemArt(itemFrame)

    itemFrame:HookScript("OnDragStart", function(frame)
        CDM:BeginInjectedOrderChange(settingsFrame, frame)
    end)
    itemFrame:HookScript("OnMouseUp", function(frame, button, upInside)
        if upInside == false then
            return
        end
        if CDM:IsStandaloneSettingsReadOnly() then
            return
        end

        if button == "LeftButton" then
            CDM:BeginInjectedOrderChange(settingsFrame, frame, button)
        elseif button == "RightButton" then
            local data = CDM:GetInjectedItemData(frame)
            if data and data.cooldownID and not data.isEmpty then
                if type(frame.DisplayContextMenu) == "function" then
                    frame:DisplayContextMenu()
                elseif CDM.OpenCooldownSettingsContextMenu and CDM:OpenCooldownSettingsContextMenu(frame) then
                else
                    CDM:UnassignCooldownID(data.cooldownID)
                    CDM:RequestRefresh()
                end
            end
        end
    end)
    itemFrame:HookScript("OnEnter", function(frame)
        CDM:OnInjectedItemEnter(frame)
    end)
    itemFrame:HookScript("OnLeave", function()
        CDM:OnInjectedItemLeave()
    end)

    CDM:StateSet(itemFrame, "standaloneInitialized", true)
    CDM:StateSet(itemFrame, "categoryFrame", categoryFrame)
end

local function ApplyRefineTabIcon(tab)
    if not tab or not tab.Icon then
        return
    end

    tab.Icon:SetTexture(REFINE_TAB_TEXTURE)
    tab.Icon:SetTexCoord(0, 1, 0, 1)
    tab.Icon:SetSize(18, 18)
end

local function HookRefineTabIcon(tab, hookKey)
    if not tab then
        return
    end

    ApplyRefineTabIcon(tab)
    RefineUI:HookOnce(hookKey .. ":SetChecked", tab, "SetChecked", function()
        ApplyRefineTabIcon(tab)
    end)
    RefineUI:HookScriptOnce(hookKey .. ":OnShow", tab, "OnShow", function()
        ApplyRefineTabIcon(tab)
    end)
end

local function SetTabMouseUpHandler(tab, handler)
    if not tab or type(handler) ~= "function" then
        return
    end

    if type(tab.SetCustomOnMouseUpHandler) == "function" then
        tab:SetCustomOnMouseUpHandler(function(self, button, upInside)
            if button == "LeftButton" and upInside then
                handler(self)
            end
        end)
        return
    end

    tab:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            handler(self)
        end
    end)
end

local function SetPanelShown(frame, shown)
    if not frame then
        return false
    end

    if shown then
        if (not InCombatLockdown or not InCombatLockdown()) and type(frame.ShowUIPanel) == "function" then
            local ok = pcall(frame.ShowUIPanel, frame, false)
            if ok and frame:IsShown() then
                return true
            end
        end

        if (not InCombatLockdown or not InCombatLockdown()) and type(ShowUIPanel) == "function" then
            local ok, didShow = pcall(ShowUIPanel, frame)
            if ok and didShow ~= false then
                return true
            end
        end

        frame:Show()
        return frame:IsShown()
    end

    if (not InCombatLockdown or not InCombatLockdown()) and type(HideUIPanel) == "function" then
        local ok = pcall(HideUIPanel, frame)
        if ok then
            return true
        end
    end

    frame:Hide()
    return true
end

local function GetRemainingPostCombatOpenDelay(self)
    if type(GetTime) ~= "function" then
        return 0
    end

    local activeTrackerEntryCount = type(self.activeTrackerEntryCount) == "number" and self.activeTrackerEntryCount or 0
    local lastCombatEndedTime = self.lastCombatEndedTime
    if activeTrackerEntryCount <= 0 or type(lastCombatEndedTime) ~= "number" then
        return 0
    end

    local remaining = POST_COMBAT_SETTINGS_OPEN_DELAY - (GetTime() - lastCombatEndedTime)
    if remaining > 0 then
        return remaining
    end

    return 0
end

local function GetSettingsOpenGuardReason(self)
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return "combat"
    end

    if GetRemainingPostCombatOpenDelay(self) > 0 then
        return "stabilizing"
    end

    return nil
end

local function SyncSettingsWindowGeometry(sourceFrame, targetFrame)
    if not targetFrame then
        return
    end

    if sourceFrame and sourceFrame ~= targetFrame then
        local width, height = sourceFrame:GetSize()
        if type(width) == "number" and width > 0 and type(height) == "number" and height > 0 then
            targetFrame:SetSize(width, height)
        end

        local point, relativeTo, relativePoint, xOfs, yOfs = sourceFrame:GetPoint(1)
        if point then
            targetFrame:ClearAllPoints()
            targetFrame:SetPoint(point, relativeTo or UIParent, relativePoint or point, xOfs or 0, yOfs or 0)
            return
        end
    end

    if targetFrame:GetNumPoints() == 0 then
        targetFrame:SetSize(BLIZZARD_FALLBACK_WIDTH, BLIZZARD_FALLBACK_HEIGHT)
        targetFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

local function SyncStandaloneFrameGeometry(frame)
    SyncSettingsWindowGeometry(_G.CooldownViewerSettings, frame)
end

local function CreateSettingsShellTab(parent, tooltipText, atlas, point, relativeTo, relativePoint, xOffset, yOffset)
    local tab = CreateFrame("Button", nil, parent, "CooldownViewerSettingsTabTemplate")
    tab.tooltipText = tooltipText
    tab.activeAtlas = atlas
    tab.inactiveAtlas = atlas
    tab:SetChecked(false)
    tab:SetPoint(point, relativeTo, relativePoint, xOffset, yOffset)
    return tab
end

local function GetBlizzardSettingsFrame()
    return _G.CooldownViewerSettings
end

local function EnsureBlizzardSettingsFrameAvailable()
    local settingsFrame = GetBlizzardSettingsFrame()
    if settingsFrame then
        return settingsFrame
    end

    local addonsAPI = _G.C_AddOns
    if addonsAPI and type(addonsAPI.LoadAddOn) == "function" then
        pcall(addonsAPI.LoadAddOn, "Blizzard_CooldownViewer")
    elseif type(_G.LoadAddOn) == "function" then
        pcall(_G.LoadAddOn, "Blizzard_CooldownViewer")
    end

    return GetBlizzardSettingsFrame()
end

local function AnchorBlizzardRefineTab(tab, settingsFrame)
    if not tab or not settingsFrame then
        return
    end

    local anchor = settingsFrame.AurasTab or settingsFrame.SpellsTab or settingsFrame
    local point = anchor == settingsFrame and "TOPLEFT" or "TOPLEFT"
    local relativePoint = anchor == settingsFrame and "TOPRIGHT" or "BOTTOMLEFT"
    local xOffset = anchor == settingsFrame and 0 or 0
    local yOffset = anchor == settingsFrame and -28 or -3

    tab:ClearAllPoints()
    tab:SetPoint(point, anchor, relativePoint, xOffset, yOffset)

    if type(settingsFrame.GetFrameStrata) == "function" then
        tab:SetFrameStrata(settingsFrame:GetFrameStrata())
    end
    if type(settingsFrame.GetFrameLevel) == "function" then
        tab:SetFrameLevel(settingsFrame:GetFrameLevel() + 4)
    end
end

local function EnsureItemFrame(parent, index)
    parent.itemFrames = parent.itemFrames or {}
    local itemFrame = parent.itemFrames[index]
    if itemFrame then
        return itemFrame
    end

    itemFrame = CreateFrame("Button", nil, parent)
    RefineUI:AddAPI(itemFrame)
    itemFrame:Size(ITEM_SIZE, ITEM_SIZE)
    itemFrame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    itemFrame:RegisterForDrag("LeftButton")
    itemFrame:SetNormalTexture("")
    itemFrame:SetPushedTexture("")
    itemFrame:SetHighlightTexture("")
    CreateItemArt(itemFrame)
    itemFrame.dragLocked = false

    function itemFrame:SetAsCooldown(cooldownID, assignmentIndex)
        self.cooldownID = cooldownID
        self.assignmentIndex = assignmentIndex
        self.isEmpty = false
        self.Icon:SetTexture(ResolveSpellIcon(cooldownID))
        self.Icon:SetDesaturated(false)
        self.EmptyText:Hide()
        if self.SelectionGlow then
            self.SelectionGlow:Hide()
        end
        ApplyItemBorder(self, cooldownID)
        UpdateItemVisualState(self)
    end

    function itemFrame:SetAsEmptyCategory(_categoryObject)
        self.cooldownID = nil
        self.assignmentIndex = nil
        self.isEmpty = true
        self.Icon:SetTexture(EMPTY_ICON_TEXTURE)
        self.Icon:SetDesaturated(true)
        self.EmptyText:Show()
        if self.SelectionGlow then
            self.SelectionGlow:Hide()
        end
        ApplyItemBorder(self, nil)
        UpdateItemVisualState(self)
    end

    function itemFrame:SetReorderLocked(locked)
        self.dragLocked = locked and true or false
        UpdateItemVisualState(self)
    end

    function itemFrame:RefreshIconState()
    end

    parent.itemFrames[index] = itemFrame
    return itemFrame
end

local function EnsureCategoryFrame(scrollChild, bucketKey, titleText)
    scrollChild.categories = scrollChild.categories or {}
    local categoryFrame = scrollChild.categories[bucketKey]
    if categoryFrame then
        return categoryFrame
    end

    local categoryObject = EnsureCategoryObject(bucketKey, titleText)
    categoryFrame = TryCreateNativeCategory(scrollChild, categoryObject)
    if not categoryFrame then
        categoryFrame = CreateFrame("Frame", nil, scrollChild)
        RefineUI:AddAPI(categoryFrame)
        CreateCategoryHeader(categoryFrame, titleText)
        CreateCategoryContainer(categoryFrame)
        categoryFrame.categoryObject = categoryObject
        categoryFrame.collapsed = false

        function categoryFrame:GetCategoryObject()
            return self.categoryObject
        end

        function categoryFrame:SetCollapsed(collapsed)
            self.collapsed = collapsed and true or false
            self.categoryObject:SetCollapsed(self.collapsed)
            if self.ContainerInset then
                self.ContainerInset:SetShown(not self.collapsed)
            end
        end

        function categoryFrame:IsCollapsed()
            return self.collapsed == true
        end

        function categoryFrame:GetBestCooldownItemTarget()
            if not self.Container or not self.Container.itemFrames then
                return nil
            end

            local index = 0
            return GetNearestVisibleItemWeighted(function()
                index = index + 1
                while self.Container.itemFrames[index] and not self.Container.itemFrames[index]:IsShown() do
                    index = index + 1
                end
                return self.Container.itemFrames[index]
            end)
        end
    end

    categoryFrame:HookScript("OnEnter", function(frame)
        CDM:OnInjectedCategoryEnter(frame)
    end)
    categoryFrame.Header:HookScript("OnEnter", function()
        CDM:OnInjectedCategoryEnter(categoryFrame)
    end)
    categoryFrame.Container:HookScript("OnEnter", function()
        CDM:OnInjectedCategoryEnter(categoryFrame)
    end)

    scrollChild.categories[bucketKey] = categoryFrame
    return categoryFrame
end

local function UpdateReadOnlyState(settingsFrame)
    local state = GetSettingsState(CDM, settingsFrame)
    local inCombat = type(InCombatLockdown) == "function" and InCombatLockdown()
    state.readOnly = inCombat and true or false

    if settingsFrame.ShowUnlearnedButton then
        settingsFrame.ShowUnlearnedButton:SetEnabled(not inCombat)
        settingsFrame.ShowUnlearnedButton:SetAlpha(inCombat and 0.45 or 1)
    end
    UpdateSettingsDropdownState(settingsFrame)

    if settingsFrame.ReadOnlyNotice then
        settingsFrame.ReadOnlyNotice:SetShown(inCombat)
    end
end

----------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------
function CDM:IsStandaloneSettingsReadOnly()
    local settingsFrame = self:GetCooldownViewerSettingsFrame()
    if not settingsFrame then
        return false
    end
    local state = GetSettingsState(self, settingsFrame)
    return state.readOnly == true
end

function CDM:RefreshStandaloneSettingsItemVisual(itemFrame)
    if not itemFrame then
        return
    end

    local data = self.GetInjectedItemData and self:GetInjectedItemData(itemFrame)
    if data and data.cooldownID and not data.isEmpty then
        ApplyItemBorder(itemFrame, data.cooldownID)
        UpdateItemVisualState(itemFrame)
        return
    end

    ApplyItemBorder(itemFrame, nil)
    UpdateItemVisualState(itemFrame)
end

function CDM:DoesCooldownIDMatchFilter(cooldownID, filterText)
    if not IsFilterActive(filterText) then
        return true
    end

    local lowerName
    if self.GetCooldownDisplayNameLower then
        lowerName = self:GetCooldownDisplayNameLower(cooldownID)
    else
        local name = self:GetCooldownDisplayName(cooldownID)
        lowerName = strlower(name or "")
    end
    return strfind(lowerName, filterText, 1, true) ~= nil
end

function CDM:LayoutInjectedCategory(settingsFrame, categoryFrame, categoryData, filterText)
    if categoryFrame.itemPool then
        local sourceList = categoryData.cooldownIDs or {}
        local assignmentIndices = categoryData.assignmentIndices
        local container = categoryFrame.Container

        categoryFrame.itemPool:ReleaseAll()

        local shownItems = 0
        for listIndex = 1, #sourceList do
            local cooldownID = sourceList[listIndex]
            if self:DoesCooldownIDMatchFilter(cooldownID, filterText) then
                shownItems = shownItems + 1
                local assignmentIndex = (type(assignmentIndices) == "table" and assignmentIndices[listIndex]) or listIndex
                local item = categoryFrame.itemPool:Acquire()
                item.layoutIndex = shownItems
                item:Show()
                item:SetAsCooldown(cooldownID, assignmentIndex)
                item:SetSize(ITEM_SIZE, ITEM_SIZE)
                ApplyItemBorder(item, cooldownID)

                InitializeInjectedItem(settingsFrame, item, categoryFrame)
                self:StateSet(item, "bucketKey", categoryData.bucketKey)
                self:StateSet(item, "cooldownID", cooldownID)
                self:StateSet(item, "isEmpty", false)
                self:StateSet(item, "displayIndex", shownItems)
                self:StateSet(item, "assignmentIndex", assignmentIndex)
                self:RefreshStandaloneSettingsItemVisual(item)
            end
        end

        if shownItems == 0 then
            local emptyItem = categoryFrame.itemPool:Acquire()
            emptyItem.layoutIndex = 1
            emptyItem:Show()
            emptyItem:SetAsEmptyCategory(categoryFrame:GetCategoryObject())
            emptyItem:SetSize(ITEM_SIZE, ITEM_SIZE)
            ApplyItemBorder(emptyItem, nil)

            InitializeInjectedItem(settingsFrame, emptyItem, categoryFrame)
            self:StateSet(emptyItem, "bucketKey", categoryData.bucketKey)
            self:StateSet(emptyItem, "cooldownID", nil)
            self:StateSet(emptyItem, "isEmpty", true)
            self:StateSet(emptyItem, "displayIndex", 1)
            self:StateSet(emptyItem, "assignmentIndex", nil)
            self:RefreshStandaloneSettingsItemVisual(emptyItem)
        end

        if container and container.Layout then
            container:Layout()
        end
        categoryFrame:SetCollapsed(categoryFrame:GetCategoryObject():IsCollapsed())

        local headerHeight = categoryFrame.Header and categoryFrame.Header:GetHeight() or 22
        if categoryFrame:IsCollapsed() then
            categoryFrame:SetHeight(headerHeight)
        else
            local contentHeight = container and container:GetHeight() or 0
            categoryFrame:SetHeight(headerHeight + 15 + contentHeight)
        end
        return
    end

    local container = categoryFrame.Container
    container.itemFrames = container.itemFrames or {}
    local shownItems = 0

    for listIndex = 1, #(categoryData.cooldownIDs or {}) do
        local cooldownID = categoryData.cooldownIDs[listIndex]
        if self:DoesCooldownIDMatchFilter(cooldownID, filterText) then
            shownItems = shownItems + 1
            local assignmentIndex = categoryData.assignmentIndices and categoryData.assignmentIndices[listIndex] or listIndex
            local item = EnsureItemFrame(container, shownItems)
            item.layoutIndex = shownItems
            item:ClearAllPoints()

            local column = (shownItems - 1) % ITEM_COLUMNS
            local row = math.floor((shownItems - 1) / ITEM_COLUMNS)
            item:SetPoint("TOPLEFT", container, "TOPLEFT", column * (ITEM_SIZE + ITEM_SPACING), -(row * (ITEM_SIZE + ITEM_SPACING)))
            item:SetAsCooldown(cooldownID, assignmentIndex)
            item:Show()

            self:StateSet(item, "categoryFrame", categoryFrame)
            self:StateSet(item, "bucketKey", categoryData.bucketKey)
            self:StateSet(item, "cooldownID", cooldownID)
            self:StateSet(item, "isEmpty", false)
            self:StateSet(item, "displayIndex", shownItems)
            self:StateSet(item, "assignmentIndex", assignmentIndex)
            self:RefreshStandaloneSettingsItemVisual(item)

            InitializeInjectedItem(settingsFrame, item, categoryFrame)
        end
    end

    if shownItems == 0 then
        shownItems = 1
        local emptyItem = EnsureItemFrame(container, shownItems)
        emptyItem.layoutIndex = 1
        emptyItem:ClearAllPoints()
        emptyItem:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
        emptyItem:SetAsEmptyCategory(categoryFrame:GetCategoryObject())
        emptyItem:Show()

        self:StateSet(emptyItem, "categoryFrame", categoryFrame)
        self:StateSet(emptyItem, "bucketKey", categoryData.bucketKey)
        self:StateSet(emptyItem, "cooldownID", nil)
        self:StateSet(emptyItem, "isEmpty", true)
        self:StateSet(emptyItem, "displayIndex", 1)
        self:StateSet(emptyItem, "assignmentIndex", nil)
        self:RefreshStandaloneSettingsItemVisual(emptyItem)
    end

    for i = shownItems + 1, #container.itemFrames do
        container.itemFrames[i]:Hide()
    end

    UpdateCategoryHeight(categoryFrame, shownItems)
end

function CDM:RequestRefineTabPanelRefresh(settingsFrame)
    local state = GetSettingsState(self, settingsFrame)
    if state.panelRefreshQueued then
        return
    end

    state.panelRefreshQueued = true
    local function RunRefresh()
        state.panelRefreshQueued = nil
        if settingsFrame and settingsFrame:IsShown() then
            CDM:RefreshRefineTabPanel(settingsFrame)
        end
    end

    if RefineUI.After then
        RefineUI:After(PANEL_REFRESH_TIMER_KEY, 0, RunRefresh)
    else
        RunRefresh()
    end
end

function CDM:RefreshRefineTabPanel(settingsFrame)
    if not settingsFrame then
        return
    end

    self:RefreshSettingsOwnerOverlays(nil, settingsFrame)
    if not self:CanRefreshRefineSettingsPanel(settingsFrame) then
        return
    end

    local state = GetSettingsState(self, settingsFrame)
    UpdateReadOnlyState(settingsFrame)

    if self.assignmentsPruneDirty then
        self:PruneCurrentLayoutAssignments()
    end

    local assignments = self:GetCurrentAssignments()
    local validAuraIDs = self:GetValidAuraCooldownIDs()
    state.validAuraSetScratch = state.validAuraSetScratch or {}
    local validAuraSet = state.validAuraSetScratch
    if wipe then
        wipe(validAuraSet)
    else
        for key in pairs(validAuraSet) do
            validAuraSet[key] = nil
        end
    end
    for i = 1, #validAuraIDs do
        validAuraSet[validAuraIDs[i]] = true
    end

    local notTrackedIDs = self:GetSortedNotTrackedIDs(validAuraIDs, assignments)
    local filterText = state.filterText or ""
    local leftIDs, leftAssignmentIndices = self:GetVisibleBucketCooldownIDs(assignments.Left, validAuraSet)
    local rightIDs, rightAssignmentIndices = self:GetVisibleBucketCooldownIDs(assignments.Right, validAuraSet)
    local bottomIDs, bottomAssignmentIndices = self:GetVisibleBucketCooldownIDs(assignments.Bottom, validAuraSet)
    local radialIDs, radialAssignmentIndices = self:GetVisibleBucketCooldownIDs(assignments.Radial, validAuraSet)

    local categoryInput = {
        Left = { cooldownIDs = leftIDs, assignmentIndices = leftAssignmentIndices },
        Right = { cooldownIDs = rightIDs, assignmentIndices = rightAssignmentIndices },
        Bottom = { cooldownIDs = bottomIDs, assignmentIndices = bottomAssignmentIndices },
        Radial = { cooldownIDs = radialIDs, assignmentIndices = radialAssignmentIndices },
        [CDM.NOT_TRACKED_KEY] = { cooldownIDs = notTrackedIDs, assignmentIndices = nil },
    }

    local previousCategory = nil
    local yOffset = 0
    for i = 1, #SETTINGS_BUCKET_ORDER do
        local bucketKey = SETTINGS_BUCKET_ORDER[i]
        local categoryFrame = EnsureCategoryFrame(settingsFrame.ScrollChild, bucketKey, self.BUCKET_LABELS[bucketKey] or bucketKey)
        local input = categoryInput[bucketKey] or {}
        local categoryData = {
            bucketKey = bucketKey,
            cooldownIDs = input.cooldownIDs or {},
            assignmentIndices = input.assignmentIndices,
        }

        self:StateSet(categoryFrame, "categoryData", categoryData)
        categoryFrame:ClearAllPoints()
        if previousCategory then
            categoryFrame:SetPoint("TOPLEFT", previousCategory, "BOTTOMLEFT", 0, -18)
            categoryFrame:SetPoint("TOPRIGHT", previousCategory, "BOTTOMRIGHT", 0, -18)
            yOffset = yOffset + 18
        else
            categoryFrame:SetPoint("TOPLEFT", settingsFrame.ScrollChild, "TOPLEFT", 0, 0)
            categoryFrame:SetPoint("TOPRIGHT", settingsFrame.ScrollChild, "TOPRIGHT", 0, 0)
        end

        self:LayoutInjectedCategory(settingsFrame, categoryFrame, categoryData, filterText)
        categoryFrame:Show()
        yOffset = yOffset + (categoryFrame:GetHeight() or 0)
        previousCategory = categoryFrame
    end

    settingsFrame.ScrollChild:SetHeight(max(1, yOffset + 20))
    if settingsFrame.ScrollFrame and settingsFrame.ScrollFrame.UpdateScrollChildRect then
        settingsFrame.ScrollFrame:UpdateScrollChildRect()
    end

end

function CDM:RefreshSettingsSection()
    local settingsFrame = self:GetCooldownViewerSettingsFrame()
    if settingsFrame and settingsFrame:IsShown() then
        self:RefreshRefineTabPanel(settingsFrame)
    end
end

function CDM:SyncSettingsWindowGeometry(sourceFrame, targetFrame)
    SyncSettingsWindowGeometry(sourceFrame, targetFrame)
end

function CDM:IsRefineSettingsOwnerActive()
    if self.IsEnabled and not self:IsEnabled() then
        return false
    end
    return self.GetAuraMode and self:GetAuraMode() == DISPLAY_MODE_REFINE
end

function CDM:ShouldManageBlizzardSettingsOwnership()
    return self.IsRefineSettingsOwnerActive and self:IsRefineSettingsOwnerActive()
end

function CDM:CancelStandaloneSettingsWork(settingsFrame)
    if not settingsFrame then
        return
    end

    local state = GetSettingsState(self, settingsFrame)
    state.panelRefreshQueued = nil
    state.lastRefineTabRefreshToken = nil

    if RefineUI.CancelDebounce then
        RefineUI:CancelDebounce(SEARCH_DEBOUNCE_KEY)
    end
    if RefineUI.CancelTimer then
        RefineUI:CancelTimer(PANEL_REFRESH_TIMER_KEY)
    end

    self:EndInjectedOrderChange(false)

    if settingsFrame.ScrollChild and type(settingsFrame.ScrollChild.categories) == "table" then
        for _, categoryFrame in pairs(settingsFrame.ScrollChild.categories) do
            if categoryFrame.itemPool and type(categoryFrame.itemPool.ReleaseAll) == "function" then
                categoryFrame.itemPool:ReleaseAll()
            end
            if categoryFrame.Container and type(categoryFrame.Container.itemFrames) == "table" then
                for i = 1, #categoryFrame.Container.itemFrames do
                    categoryFrame.Container.itemFrames[i]:Hide()
                end
            end
            categoryFrame:Hide()
        end
    end

    if settingsFrame.ScrollChild then
        settingsFrame.ScrollChild:SetHeight(1)
    end
    if settingsFrame.ScrollFrame and settingsFrame.ScrollFrame.UpdateScrollChildRect then
        settingsFrame.ScrollFrame:UpdateScrollChildRect()
    end
end

function CDM:EnsureBlizzardOwnerOverlay(settingsFrame)
    if not settingsFrame then
        return nil
    end

    local state = GetSettingsState(self, settingsFrame)
    if state.blizzardOwnerOverlay then
        return state.blizzardOwnerOverlay
    end

    local parent = settingsFrame.Inset or settingsFrame
    local overlay = CreateOwnerOverlay(
        parent,
        BLIZZARD_OWNER_OVERLAY_TITLE,
        BLIZZARD_OWNER_OVERLAY_TEXT,
        BLIZZARD_OWNER_OVERLAY_BUTTON,
        function()
            if CDM.ShowCooldownManagerSwitchPrompt then
                CDM:ShowCooldownManagerSwitchPrompt("blizzard")
            elseif CDM.SetAuraMode then
                CDM:SetAuraMode("blizzard")
            end
            CDM:RefreshSettingsOwnerOverlays(settingsFrame, CDM:GetCooldownViewerSettingsFrame())
        end
    )

    if settingsFrame.Inset then
        overlay:SetPoint("TOPLEFT", settingsFrame.Inset, "TOPLEFT", 0, 0)
        overlay:SetPoint("BOTTOMRIGHT", settingsFrame.Inset, "BOTTOMRIGHT", 0, 0)
    else
        overlay:SetAllPoints(settingsFrame)
    end

    state.blizzardOwnerOverlay = overlay
    return overlay
end

function CDM:EnsureRefineOwnerOverlay(settingsFrame)
    if not settingsFrame then
        return nil
    end

    local state = GetSettingsState(self, settingsFrame)
    if state.refineOwnerOverlay then
        return state.refineOwnerOverlay
    end

    local parent = settingsFrame.Inset or settingsFrame
    local overlay = CreateOwnerOverlay(
        parent,
        REFINE_OWNER_OVERLAY_TITLE,
        REFINE_OWNER_OVERLAY_TEXT,
        REFINE_OWNER_OVERLAY_BUTTON,
        function()
            if CDM.ShowCooldownManagerSwitchPrompt then
                CDM:ShowCooldownManagerSwitchPrompt(DISPLAY_MODE_REFINE)
            elseif CDM.SetAuraMode then
                CDM:SetAuraMode(DISPLAY_MODE_REFINE)
            end
            CDM:RefreshSettingsOwnerOverlays(nil, settingsFrame)
            CDM:RequestRefineTabPanelRefresh(settingsFrame)
        end
    )

    if settingsFrame.Inset then
        overlay:SetPoint("TOPLEFT", settingsFrame.Inset, "TOPLEFT", 0, 0)
        overlay:SetPoint("BOTTOMRIGHT", settingsFrame.Inset, "BOTTOMRIGHT", 0, 0)
    else
        overlay:SetAllPoints(settingsFrame)
    end

    state.refineOwnerOverlay = overlay
    return overlay
end

function CDM:CanRefreshRefineSettingsPanel(settingsFrame)
    if not settingsFrame or not settingsFrame:IsShown() then
        return false
    end
    if not self:IsRefineSettingsOwnerActive() then
        return false
    end

    local state = GetSettingsState(self, settingsFrame)
    if state.refineOwnerOverlay and state.refineOwnerOverlay:IsShown() then
        return false
    end

    return true
end

function CDM:RequestDeferredSettingsOpen(reason)
    if reason == "combat" then
        if self.settingsOpenGuardReason ~= reason then
            RefineUI:Print("CDM settings will open after combat ends.")
            self.settingsOpenGuardReason = reason
        end
        return false
    end

    if self.settingsOpenGuardReason ~= reason then
        RefineUI:Print("CDM settings are temporarily blocked while combat cooldowns settle.")
        self.settingsOpenGuardReason = reason
    end
    return false
end

function CDM:RefreshSettingsOwnerOverlays(blizzardFrame, refineFrame)
    local manageBlizzardOwnership = self:ShouldManageBlizzardSettingsOwnership()
    if blizzardFrame == nil and manageBlizzardOwnership then
        blizzardFrame = GetBlizzardSettingsFrame()
    end
    refineFrame = refineFrame or self:GetCooldownViewerSettingsFrame()

    local ownerActive = self:IsRefineSettingsOwnerActive()
    local showBlizzardOverlay = false
    if manageBlizzardOwnership and blizzardFrame and blizzardFrame:IsShown() and not self.settingsRouteInProgress then
        showBlizzardOverlay = ownerActive
    end

    local blizzardOverlay = nil
    if blizzardFrame then
        local blizzardState = GetSettingsState(self, blizzardFrame)
        blizzardOverlay = blizzardState.blizzardOwnerOverlay
        if showBlizzardOverlay and not blizzardOverlay then
            blizzardOverlay = self:EnsureBlizzardOwnerOverlay(blizzardFrame)
        end
    end
    if blizzardOverlay then
        blizzardOverlay:SetShown(showBlizzardOverlay)
    end

    local showRefineOverlay = refineFrame and refineFrame:IsShown() and (not ownerActive) and not self.settingsRouteInProgress
    local refineOverlay = nil
    if refineFrame then
        local refineState = GetSettingsState(self, refineFrame)
        refineOverlay = refineState.refineOwnerOverlay
        if showRefineOverlay and not refineOverlay then
            refineOverlay = self:EnsureRefineOwnerOverlay(refineFrame)
        end
    end
    if refineOverlay then
        refineOverlay:SetShown(showRefineOverlay)
    end

    if showRefineOverlay and refineFrame then
        self:CancelStandaloneSettingsWork(refineFrame)
    end
end

function CDM:HandleSettingsOwnerStateChanged(ownerActive)
    if ownerActive == nil then
        ownerActive = self:IsRefineSettingsOwnerActive()
    else
        ownerActive = ownerActive and true or false
    end

    if self.settingsOwnerStateKnown and self.settingsOwnerActive == ownerActive then
        return
    end

    self.settingsOwnerStateKnown = true
    self.settingsOwnerActive = ownerActive

    if ownerActive and self.EnsureBlizzardSettingsOwnerHooks then
        self:EnsureBlizzardSettingsOwnerHooks()
    end

    local refineFrame = self:GetCooldownViewerSettingsFrame()
    if refineFrame then
        local state = GetSettingsState(self, refineFrame)
        state.lastRefineTabRefreshToken = nil
        if not ownerActive then
            self:CancelStandaloneSettingsWork(refineFrame)
        end
    end

    self:RefreshSettingsOwnerOverlays(nil, refineFrame)

    if ownerActive and refineFrame and refineFrame:IsShown() then
        self:RequestRefineTabPanelRefresh(refineFrame)
    end
end

function CDM:RefreshStandaloneSettingsTabs(settingsFrame)
    settingsFrame = settingsFrame or self:GetCooldownViewerSettingsFrame()
    if not settingsFrame or type(settingsFrame.SettingsTabs) ~= "table" then
        return
    end

    local tabs = settingsFrame.SettingsTabs
    if tabs.Spells then
        tabs.Spells:SetChecked(false)
    end
    if tabs.Auras then
        tabs.Auras:SetChecked(false)
    end
    if tabs.RefineUI then
        tabs.RefineUI:SetChecked(true)
        ApplyRefineTabIcon(tabs.RefineUI)
    end
end

function CDM:OpenRefineSettingsPanelFromBlizzard(sourceFrame, skipGuard)
    if self.settingsRouteInProgress then
        return false
    end
    if not skipGuard then
        local reason = GetSettingsOpenGuardReason(self)
        if reason then
            return self:RequestDeferredSettingsOpen(reason)
        end
    end

    local targetFrame = self:CreateStandaloneSettingsFrame()
    if not targetFrame then
        RefineUI:Print("CDM settings are unavailable right now.")
        return false
    end

    sourceFrame = sourceFrame or GetBlizzardSettingsFrame()
    local manageBlizzardOwnership = self:ShouldManageBlizzardSettingsOwnership()

    self.settingsRouteInProgress = true

    SyncSettingsWindowGeometry(sourceFrame, targetFrame)
    UpdateReadOnlyState(targetFrame)
    self:RefreshStandaloneSettingsTabs(targetFrame)

    local sourceWasShown = sourceFrame and sourceFrame:IsShown()
    if sourceWasShown then
        SetPanelShown(sourceFrame, false)
    end

    local shown = SetPanelShown(targetFrame, true)
    if not shown and sourceWasShown then
        SetPanelShown(sourceFrame, true)
    end

    self.settingsRouteInProgress = nil

    if shown then
        self.settingsOpenGuardReason = nil
        if manageBlizzardOwnership then
            self:RefreshSettingsOwnerOverlays(sourceFrame, targetFrame)
        else
            self:RefreshSettingsOwnerOverlays(nil, targetFrame)
        end
        self:RefreshStandaloneSettingsTabs(targetFrame)
        self:RefreshRefineTabPanel(targetFrame)
        return true
    end

    return false
end

function CDM:OpenBlizzardSettingsPanelFromRefine(displayMode, sourceFrame)
    if self.settingsRouteInProgress then
        return false
    end

    if self.IsRefineRuntimeOwnerActive and self:IsRefineRuntimeOwnerActive() then
        if self.ShowCooldownManagerSwitchPrompt then
            self:ShowCooldownManagerSwitchPrompt("blizzard", { displayMode = displayMode })
        else
            RefineUI:Print("Blizzard cooldown settings are disabled while RefineUI CDM is active.")
        end
        return false
    end

    if displayMode ~= DISPLAY_MODE_SPELLS and displayMode ~= DISPLAY_MODE_AURAS then
        displayMode = DISPLAY_MODE_SPELLS
    end

    local targetFrame = EnsureBlizzardSettingsFrameAvailable()
    if not targetFrame then
        RefineUI:Print("Blizzard cooldown settings are unavailable right now.")
        return false
    end

    if self.InstallBlizzardSettingsIntegration then
        self:InstallBlizzardSettingsIntegration()
    end
    if self.EnsureBlizzardSettingsOwnerHooks then
        self:EnsureBlizzardSettingsOwnerHooks()
    end

    self.settingsRouteInProgress = true

    SyncSettingsWindowGeometry(sourceFrame, targetFrame)

    if type(targetFrame.SetDisplayMode) == "function" then
        pcall(targetFrame.SetDisplayMode, targetFrame, displayMode)
    end

    local sourceWasShown = sourceFrame and sourceFrame:IsShown()
    if sourceWasShown then
        SetPanelShown(sourceFrame, false)
    end

    local shown = SetPanelShown(targetFrame, true)
    if not shown and sourceWasShown then
        SetPanelShown(sourceFrame, true)
    end

    if shown and type(targetFrame.SetDisplayMode) == "function" and targetFrame.displayMode ~= displayMode then
        pcall(targetFrame.SetDisplayMode, targetFrame, displayMode)
    end

    self.settingsRouteInProgress = nil

    if shown then
        self:RefreshSettingsOwnerOverlays(targetFrame, sourceFrame)
        if self.blizzardRefineTab then
            self.blizzardRefineTab:SetChecked(false)
            ApplyRefineTabIcon(self.blizzardRefineTab)
        end
        return true
    end

    return false
end

function CDM:RequestPendingPostReloadSettingsOpen()
    if self.pendingPostReloadSettingsOpenQueued then
        return
    end

    local pendingRequest = self.GetPendingPostReloadSettingsOpen and self:GetPendingPostReloadSettingsOpen() or nil
    if type(pendingRequest) ~= "table" then
        return
    end

    self.pendingPostReloadSettingsOpenQueued = true

    local function TryOpen()
        CDM.pendingPostReloadSettingsOpenQueued = nil

        local request = CDM.GetPendingPostReloadSettingsOpen and CDM:GetPendingPostReloadSettingsOpen() or nil
        if type(request) ~= "table" then
            return
        end

        local opened = false
        if request.mode == DISPLAY_MODE_REFINE then
            opened = CDM:OpenSettingsPanel(true)
        elseif request.mode == "blizzard" then
            local displayMode = request.displayMode
            if displayMode ~= DISPLAY_MODE_AURAS and displayMode ~= DISPLAY_MODE_SPELLS then
                displayMode = DISPLAY_MODE_SPELLS
            end
            opened = CDM:OpenBlizzardSettingsPanelFromRefine(displayMode, nil)
        end

        if opened and CDM.ClearPendingPostReloadSettingsOpen then
            CDM:ClearPendingPostReloadSettingsOpen()
        end
    end

    if RefineUI.After then
        RefineUI:After(POST_RELOAD_OPEN_TIMER_KEY, 0, TryOpen)
    else
        TryOpen()
    end
end

function CDM:RefreshBlizzardSettingsRefineTab()
    local tab = self.blizzardRefineTab
    local host = self.blizzardRefineTabHost
    local settingsFrame = GetBlizzardSettingsFrame()
    if not tab then
        return
    end

    if settingsFrame and settingsFrame:IsShown() then
        AnchorBlizzardRefineTab(tab, settingsFrame)
        tab:SetChecked(false)
        ApplyRefineTabIcon(tab)
        if host then
            host:Show()
        end
        tab:Show()
    else
        tab:SetChecked(false)
        tab:Hide()
        if host then
            host:Hide()
        end
    end

    if self:ShouldManageBlizzardSettingsOwnership() then
        self:RefreshSettingsOwnerOverlays(settingsFrame, self:GetCooldownViewerSettingsFrame())
    end
end

function CDM:HandleBlizzardSettingsPanelShown(settingsFrame)
    if self.settingsRouteInProgress or self.blizzardSettingsRedirectInProgress then
        return
    end
    if not (self.IsRefineRuntimeOwnerActive and self:IsRefineRuntimeOwnerActive()) then
        return
    end
    if not settingsFrame or not settingsFrame:IsShown() then
        return
    end

    self.blizzardSettingsRedirectInProgress = true
    self:OpenRefineSettingsPanelFromBlizzard(settingsFrame)
    self.blizzardSettingsRedirectInProgress = nil
end

function CDM:InstallBlizzardSettingsRedirect()
    local settingsFrame = GetBlizzardSettingsFrame()
    if not settingsFrame or self.blizzardSettingsRedirectInstalled then
        return
    end

    RefineUI:HookScriptOnce(BLIZZARD_SETTINGS_REDIRECT_HOOK_KEY, settingsFrame, "OnShow", function()
        CDM:HandleBlizzardSettingsPanelShown(settingsFrame)
    end)

    self.blizzardSettingsRedirectInstalled = true
end

function CDM:EnsureBlizzardSettingsOwnerHooks()
    local settingsFrame = GetBlizzardSettingsFrame()
    if not settingsFrame then
        return
    end
    if not self:ShouldManageBlizzardSettingsOwnership() then
        return
    end
    if self.blizzardSettingsOwnerHooksInstalled then
        return
    end

    RefineUI:HookOnce("CDM:Settings:Blizzard:SetDisplayMode", settingsFrame, "SetDisplayMode", function()
        if not CDM:ShouldManageBlizzardSettingsOwnership() then
            return
        end
        CDM:RefreshSettingsOwnerOverlays(settingsFrame, CDM:GetCooldownViewerSettingsFrame())
    end)

    self.blizzardSettingsOwnerHooksInstalled = true
end

function CDM:InstallBlizzardSettingsIntegration()
    local settingsFrame = GetBlizzardSettingsFrame()
    if not settingsFrame then
        return
    end

    self:InstallBlizzardSettingsRedirect()

    if not self.blizzardRefineTabHost then
        local host = CreateFrame("Frame", nil, UIParent)
        host:Hide()
        self.blizzardRefineTabHost = host
    end

    if not self.blizzardRefineTab then
        local anchor = settingsFrame.AurasTab or settingsFrame.SpellsTab or settingsFrame
        local anchorPoint = anchor == settingsFrame and "TOPLEFT" or "TOPLEFT"
        local relativePoint = anchor == settingsFrame and "TOPRIGHT" or "BOTTOMLEFT"
        local xOffset = 0
        local yOffset = anchor == settingsFrame and -28 or -3
        local tab = CreateSettingsShellTab(
            self.blizzardRefineTabHost,
            REFINE_TAB_TOOLTIP,
            REFINE_TAB_ATLAS,
            anchorPoint,
            anchor,
            relativePoint,
            xOffset,
            yOffset
        )
        HookRefineTabIcon(tab, "CDM:Settings:BlizzardRefineTab")
        SetTabMouseUpHandler(tab, function()
            CDM:OpenRefineSettingsPanelFromBlizzard(GetBlizzardSettingsFrame())
        end)
        tab:Hide()
        self.blizzardRefineTab = tab
    end

    AnchorBlizzardRefineTab(self.blizzardRefineTab, settingsFrame)
    self:EnsureBlizzardSettingsOwnerHooks()

    if self.blizzardSettingsIntegrationInstalled then
        self:RefreshBlizzardSettingsRefineTab()
        return
    end

    RefineUI:HookScriptOnce("CDM:Settings:Blizzard:OnShow", settingsFrame, "OnShow", function()
        CDM:RefreshBlizzardSettingsRefineTab()
    end)
    RefineUI:HookScriptOnce("CDM:Settings:Blizzard:OnHide", settingsFrame, "OnHide", function()
        CDM:RefreshBlizzardSettingsRefineTab()
    end)

    self.blizzardSettingsIntegrationInstalled = true
    self:RefreshBlizzardSettingsRefineTab()
end

function CDM:CreateStandaloneSettingsFrame()
    if self.settingsFrame then
        return self.settingsFrame
    end

    local frame = CreateFrame("Frame", self.SETTINGS_FRAME_NAME, UIParent, "ButtonFrameTemplate")
    RefineUI:AddAPI(frame)
    frame:Size(BLIZZARD_FALLBACK_WIDTH, BLIZZARD_FALLBACK_HEIGHT)
    frame:Point("CENTER")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(selfFrame)
        if not InCombatLockdown or not InCombatLockdown() then
            selfFrame:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(selfFrame)
        selfFrame:StopMovingOrSizing()
    end)
    frame:Hide()
    AddToUISpecialFrames(self.SETTINGS_FRAME_NAME)
    RegisterStandalonePanelWindow(self.SETTINGS_FRAME_NAME)

    if frame.Inset and frame.Inset.Bg then
        frame.Inset.Bg:SetAtlas("character-panel-background", true)
        frame.Inset.Bg:SetHorizTile(false)
        frame.Inset.Bg:SetVertTile(false)
    end
    if frame.TopTileStreaks then
        frame.TopTileStreaks:Hide()
    end
    if frame.TitleContainer and frame.TitleContainer.TitleText then
        frame.TitleContainer.TitleText:SetText("Cooldown Settings")
    end
    if frame.portrait then
        frame.portrait:SetTexture(134400)
    end
    if frame.CloseButton then
        frame.CloseButton:SetScript("OnClick", function()
            if (not InCombatLockdown or not InCombatLockdown()) and type(HideUIPanel) == "function" then
                HideUIPanel(frame)
            else
                frame:Hide()
            end
        end)
    end

    local spellsTab = CreateSettingsShellTab(
        frame,
        SPELLS_TAB_TOOLTIP,
        SPELLS_TAB_ATLAS,
        "TOPLEFT",
        frame,
        "TOPRIGHT",
        0,
        -28
    )
    local aurasTab = CreateSettingsShellTab(
        frame,
        AURAS_TAB_TOOLTIP,
        AURAS_TAB_ATLAS,
        "TOP",
        spellsTab,
        "BOTTOM",
        0,
        -3
    )
    local refineTab = CreateSettingsShellTab(
        frame,
        REFINE_TAB_TOOLTIP,
        REFINE_TAB_ATLAS,
        "TOP",
        aurasTab,
        "BOTTOM",
        0,
        -3
    )
    HookRefineTabIcon(refineTab, "CDM:Settings:StandaloneRefineTab")
    SetTabMouseUpHandler(spellsTab, function()
        CDM:OpenBlizzardSettingsPanelFromRefine(DISPLAY_MODE_SPELLS, frame)
    end)
    SetTabMouseUpHandler(aurasTab, function()
        CDM:OpenBlizzardSettingsPanelFromRefine(DISPLAY_MODE_AURAS, frame)
    end)
    SetTabMouseUpHandler(refineTab, function()
        CDM:RefreshStandaloneSettingsTabs(frame)
    end)
    frame.SettingsTabs = {
        Spells = spellsTab,
        Auras = aurasTab,
        RefineUI = refineTab,
    }

    local searchBox = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
    searchBox:SetSize(290, 30)
    searchBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 72, -30)
    if searchBox.Instructions then
        searchBox.Instructions:SetText("Enter search text")
    end
    frame.SearchBox = searchBox

    local settingsDropdown = CreateFrame("DropdownButton", nil, frame, "UIPanelIconDropdownButtonTemplate")
    settingsDropdown:SetPoint("LEFT", searchBox, "RIGHT", 5, 0)
    if settingsDropdown.SetupMenu then
        settingsDropdown:SetupMenu(function(_owner, rootDescription)
            rootDescription:CreateCheckbox("Show Unlearned", IsShowingUnlearned, function()
                if CDM:IsStandaloneSettingsReadOnly() then
                    return
                end
                ToggleShowUnlearned()
                CDM:RequestRefresh(true)
            end)
        end)
    end
    frame.SettingsDropdown = settingsDropdown
    frame.ShowUnlearnedButton = settingsDropdown

    local readOnlyNotice = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    readOnlyNotice:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -42, -38)
    readOnlyNotice:SetText("|cffff5555Read-only in combat|r")
    readOnlyNotice:Hide()
    frame.ReadOnlyNotice = readOnlyNotice

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "ScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 17, -72)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 29)
    frame.ScrollFrame = scrollFrame

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(300, 1)
    scrollChild:SetPoint("TOPLEFT", 0, 0)
    scrollChild:SetPoint("TOPRIGHT", 0, 0)
    scrollFrame:SetScrollChild(scrollChild)
    if scrollFrame.ScrollBar then
        scrollFrame.ScrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 6, 0)
        scrollFrame.ScrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 6, 0)
    end
    frame.ScrollChild = scrollChild

    scrollFrame:SetScript("OnSizeChanged", function(selfFrame)
        scrollChild:SetWidth(selfFrame:GetWidth())
        CDM:RequestRefineTabPanelRefresh(frame)
    end)

    searchBox:SetScript("OnTextChanged", function(editBox)
        if editBox.Instructions then
            editBox.Instructions:SetShown(editBox:GetText() == "")
        end

        local state = GetSettingsState(CDM, frame)
        local updatedFilter = strlower(editBox:GetText() or "")
        if updatedFilter == state.filterText then
            return
        end

        state.filterText = updatedFilter
        if RefineUI.Debounce then
            RefineUI:Debounce(SEARCH_DEBOUNCE_KEY, 0.05, function()
                CDM:RequestRefineTabPanelRefresh(frame)
            end)
        else
            CDM:RequestRefineTabPanelRefresh(frame)
        end
    end)

    frame:HookScript("OnShow", function()
        local state = GetSettingsState(CDM, frame)
        UpdateReadOnlyState(frame)
        if frame.SetPortraitToSpecIcon then
            frame:SetPortraitToSpecIcon()
        end
        if frame.SearchBox then
            frame.SearchBox:SetText(state.filterText or "")
            if frame.SearchBox.Instructions then
                frame.SearchBox.Instructions:SetShown((state.filterText or "") == "")
            end
        end
        CDM:RefreshStandaloneSettingsTabs(frame)
        CDM:RefreshSettingsOwnerOverlays(nil, frame)
        scrollChild:SetWidth(scrollFrame:GetWidth())
        if CDM:CanRefreshRefineSettingsPanel(frame) then
            CDM:RequestRefineTabPanelRefresh(frame)
        else
            CDM:CancelStandaloneSettingsWork(frame)
        end
    end)

    frame:HookScript("OnHide", function()
        CDM:CancelStandaloneSettingsWork(frame)
        CDM:RefreshSettingsOwnerOverlays(nil, frame)
    end)

    self.settingsFrame = frame
    local state = GetSettingsState(self, frame)
    state.filterText = state.filterText or ""
    self:RefreshStandaloneSettingsTabs(frame)
    SyncStandaloneFrameGeometry(frame)
    return frame
end

function CDM:OpenSettingsPanel(skipGuard)
    if not skipGuard then
        local reason = GetSettingsOpenGuardReason(self)
        if reason then
            return self:RequestDeferredSettingsOpen(reason)
        end
    end

    self.settingsOpenGuardReason = nil

    local blizzardSettingsFrame = GetBlizzardSettingsFrame()
    if blizzardSettingsFrame and blizzardSettingsFrame:IsShown() then
        return self:OpenRefineSettingsPanelFromBlizzard(blizzardSettingsFrame)
    end

    local settingsFrame = self:CreateStandaloneSettingsFrame()
    if not settingsFrame then
        RefineUI:Print("CDM settings are unavailable right now.")
        return false
    end

    UpdateReadOnlyState(settingsFrame)
    self:RefreshStandaloneSettingsTabs(settingsFrame)
    SetPanelShown(settingsFrame, true)
    self:RefreshSettingsOwnerOverlays(nil, settingsFrame)
    self:RefreshRefineTabPanel(settingsFrame)
    return true
end

function CDM:InitializeSettingsInjection()
    if self.settingsInjectionInitialized then
        return
    end

    self:CreateStandaloneSettingsFrame()

    if _G.CooldownViewerSettings then
        self:InstallBlizzardSettingsIntegration()
    end

    if not self.settingsIntegrationAddonHookRegistered and RefineUI.RegisterEventCallback then
        RefineUI:RegisterEventCallback("ADDON_LOADED", function(_event, addonName)
            if addonName ~= "Blizzard_CooldownViewer" then
                return
            end
            if CDM.InstallBlizzardSettingsIntegration then
                CDM:InstallBlizzardSettingsIntegration()
            end
        end, "CDM:Settings:AddonLoaded")
        self.settingsIntegrationAddonHookRegistered = true
    end

    self.settingsInjectionInitialized = true
end
