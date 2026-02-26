local AddOnName, RefineUI = ...
local LootFilterUI = RefineUI:RegisterModule("LootFilterUI")

-- WoW Globals
local CreateFrame = CreateFrame
local GameTooltip = GameTooltip
local ReloadUI = ReloadUI

-- Locals
local menuFrame

function LootFilterUI:CreateMenu()
    if menuFrame then return end

    menuFrame = CreateFrame("Frame", "RefineUILootFilterMenu", UIParent, "BackdropTemplate")
    RefineUI.Size(menuFrame, 200, 100)
    RefineUI.SetTemplate(menuFrame, "Default")
    menuFrame:SetFrameStrata("DIALOG")
    menuFrame:Hide()

    local title = menuFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    RefineUI.Point(title, "TOP", 0, -10)
    title:SetText("Loot Filter Settings")

    local function CreateCheckbox(label, configKey, yOffset, tooltip)
        local name = "RefineUILootFilterMenuCB_" .. configKey
        local cb = CreateFrame("CheckButton", name, menuFrame, "ChatConfigCheckButtonTemplate")
        RefineUI.Point(cb, "TOPLEFT", 10, yOffset)
        
        -- Safe text setting
        local text = _G[name .. "Text"] or cb.Text or cb:GetFontString()
        if text then
            text:SetText(label)
        else
            -- CheckButtonTemplate might not have a text region directly accessible if anonymous? 
            -- But we gave it a name, so _G[name.."Text"] should work if the template uses $parentText
            -- Fallback: create one
             local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
             RefineUI.Point(fs, "LEFT", cb, "RIGHT", 4, 0)
             fs:SetText(label)
        end

        cb.tooltip = tooltip
        cb:SetChecked(RefineUI.Config.Loot.LootFilter[configKey])
        cb:SetScript("OnClick", function(self)
            RefineUI.Config.Loot.LootFilter[configKey] = self:GetChecked()
        end)
        return cb
    end

    -- Helper: Create Slider
    local function CreateSlider(label, configKey, yOffset, minVal, maxVal, tooltip)
        local slider = CreateFrame("Slider", "RefineUILootFilterMenuSlider_" .. configKey, menuFrame, "OptionsSliderTemplate")
        RefineUI.Point(slider, "TOPLEFT", 15, yOffset)
        RefineUI.Size(slider, 170, 16)
        slider:SetMinMaxValues(minVal, maxVal)
        slider:SetValueStep(1)
        slider:SetObeyStepOnDrag(true)
        
        local current = RefineUI.Config.Loot.LootFilter[configKey]
        slider:SetValue(current)
        
        _G[slider:GetName() .. "Text"]:SetText(label .. ": " .. current)
        _G[slider:GetName() .. "Low"]:SetText(minVal)
        _G[slider:GetName() .. "High"]:SetText(maxVal)
        
        slider.tooltipText = tooltip
        slider:SetScript("OnValueChanged", function(self, value)
            value = math.floor(value + 0.5)
            RefineUI.Config.Loot.LootFilter[configKey] = value
            _G[self:GetName() .. "Text"]:SetText(label .. ": " .. value)
        end)
        
        -- Skin if possible
        -- if RefineUI.AddAPI then RefineUI.AddAPI(slider) end -- REMOVED
        if slider.CreateBackdrop then 
             -- If it inherits Mixin, fine, but we prefer static
             RefineUI.CreateBackdrop(slider, "Default")
        else
             RefineUI.CreateBackdrop(slider, "Default")
        end
        
        return slider
    end

    CreateCheckbox("Enable Loot Filter", "Enable", -30, "Enable or disable the entire Loot Filter module.")
    CreateCheckbox("Ignore Old Exp. Tradeskill", "IgnoreOldExpansionTradeskill", -55, "Ignore tradeskill items from previous expansions.")
    CreateCheckbox("Loot Unknown Transmog", "GearUnknown", -80, "Always loot gear with uncollected appearances.")
    
    -- Slider for MinQuality
    CreateSlider("Min Quality", "MinQuality", -110, 0, 5, "Minimum item quality to loot (0=Poor, 1=Common, 2=Uncommon, 3=Rare, 4=Epic).")
    
    -- Increase size to fit
    RefineUI.Size(menuFrame, 200, 150)
end

function LootFilterUI:ToggleMenu(anchor)
    if not menuFrame then self:CreateMenu() end
    if menuFrame:IsShown() then
        menuFrame:Hide()
    else
        menuFrame:ClearAllPoints()
        RefineUI.Point(menuFrame, "TOPRIGHT", anchor, "TOPLEFT", -5, 0)
        menuFrame:Show()
    end
end

function LootFilterUI:CreateBagButton()
    -- Determine which frame to attach to
    local parent
    if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
        parent = ContainerFrameCombinedBags
    elseif ContainerFrame1 and ContainerFrame1:IsShown() then
        parent = ContainerFrame1
    end
    
    if not parent then return end
    
    -- Reuse existing button if created
    local button = _G["RefineUILootFilterButton"]
    
    if not button then
        button = RefineUI.CreateSettingsButton(parent, "RefineUILootFilterButton", 20)
        
        -- Force a texture just in case Atlas fails or is invisible
        if not button:GetNormalTexture() then
            local tex = button:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints()
            tex:SetTexture("Interface\\WorldMap\\Gear_64")
            tex:SetTexCoord(0.1, 0.9, 0.1, 0.9)
            button:SetNormalTexture(tex)
            button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
        end
        button:SetScript("OnClick", function()
            self:ToggleMenu(button)
        end)
        
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Loot Filter Settings")
            GameTooltip:Show()
        end)
        
        button:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
    
    button:SetParent(parent)
    button:ClearAllPoints()
    button:SetFrameLevel(parent:GetFrameLevel() + 10)
    
    -- Try to anchor to the Close Button or Portrait
    local anchor = parent.CloseButton or parent.PortraitButton 
    
    if anchor then
        if parent == ContainerFrameCombinedBags then
             -- Combined bags usually have a portrait button on top left or right depending on settings, 
             -- but standard UI has a CloseButton. We want it near there.
             RefineUI.Point(button, "RIGHT", anchor, "LEFT", -2, 0)
        else
            -- Individual bags: Close button is usually top right
            RefineUI.Point(button, "RIGHT", anchor, "LEFT", -2, 0)
        end
    else
        RefineUI.Point(button, "TOPRIGHT", parent, "TOPRIGHT", -30, -5)
    end
    
    button:Show()
end

--[[
function LootFilterUI:OnEnable()
    if not RefineUI.Config.Loot.LootFilter.Enable then return end
    
    -- Hook into bag opening to ensure button is created/shown
    -- Using C_Timer to ensure frame is actually shown/updated
    RefineUI:RegisterEventCallback("BAG_OPEN", function() 
        C_Timer.After(0.1, function() self:CreateBagButton() end)
    end, "LootFilterUI:BagOpen")
    
    -- Also hook OnShow if frames exist
    if ContainerFrameCombinedBags then
        ContainerFrameCombinedBags:HookScript("OnShow", function() self:CreateBagButton() end)
    end
    
    if ContainerFrame1 then
        ContainerFrame1:HookScript("OnShow", function() self:CreateBagButton() end)
    end
    
    -- Try creating immediately after a short delay to allow UI to settle
    C_Timer.After(0.5, function()
        self:CreateBagButton()
    end)
end
]]
