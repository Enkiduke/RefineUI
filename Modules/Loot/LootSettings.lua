----------------------------------------------------------------------------------------
-- LootSettings for RefineUI
-- Description: Bag-adjacent settings button and loot settings context menu.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local LootSettings = RefineUI:RegisterModule("LootSettings")

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
local C_Timer = C_Timer
local GameTooltip = GameTooltip
local InCombatLockdown = InCombatLockdown

local MenuUtil = MenuUtil

----------------------------------------------------------------------------------------
-- Private Helpers
----------------------------------------------------------------------------------------
local function EnsureLootSettingsIcon(button)
    if not button then
        return
    end
    RefineUI.EnsureSettingsButtonIcon(button, "GM-icon-settings")
end

function LootSettings:CreateButton()
    local parent
    if _G["RefineUI_Bags"] and _G["RefineUI_Bags"]:IsShown() then
        parent = _G["RefineUI_Bags"]
    elseif ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
        parent = ContainerFrameCombinedBags
    elseif ContainerFrame1 and ContainerFrame1:IsShown() then
        parent = ContainerFrame1
    end
    
    if not parent then return end

    local button = _G["RefineUILootSettingsButton"]
    
    if not button then
        button = RefineUI.CreateSettingsButton(parent, "RefineUILootSettingsButton", 32, "GM-icon-settings")
        
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Loot Settings")
            GameTooltip:Show()
        end)
        
        button:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        
        button:SetScript("OnMouseDown", function(self)
            if InCombatLockdown() then return end
            
            MenuUtil.CreateContextMenu(self, function(ownerRegion, rootDescription)
                rootDescription:CreateTitle("Loot Settings")

                rootDescription:CreateCheckbox("Auto Confirm", function() return RefineUI.Config.Loot.AutoConfirm end, function()
                    RefineUI.Config.Loot.AutoConfirm = not RefineUI.Config.Loot.AutoConfirm
                    RefineUI:Print("Auto Confirm: " .. (RefineUI.Config.Loot.AutoConfirm and "Enabled" or "Disabled"))
                end)

                rootDescription:CreateCheckbox("Faster Loot", function() return RefineUI.Config.Loot.FasterLoot end, function()
                    RefineUI.Config.Loot.FasterLoot = not RefineUI.Config.Loot.FasterLoot
                    RefineUI:Print("Faster Loot: " .. (RefineUI.Config.Loot.FasterLoot and "Enabled" or "Disabled"))
                end)

                rootDescription:CreateDivider()

                rootDescription:CreateButton("Advanced Loot Rules", function()
                    local module = RefineUI:GetModule("LootRules")
                    if module and module.ToggleLootManager then
                        module:ToggleLootManager(ownerRegion)
                    else
                        RefineUI:Print("LootRules module not found or incompatible.")
                    end
                end)

                rootDescription:CreateButton("Advanced Sell Rules", function()
                    local module = RefineUI:GetModule("LootRules")
                    if module and module.ToggleSellManager then
                        module:ToggleSellManager(ownerRegion)
                    else
                        RefineUI:Print("LootRules module not found or incompatible.")
                    end
                end)

            end)
        end)
    end

    EnsureLootSettingsIcon(button)
    
    button:SetParent(parent)
    button:ClearAllPoints()
    button:SetFrameStrata("HIGH")
    button:SetFrameLevel(parent:GetFrameLevel() + 20)

    local anchor = parent.CloseButton or _G[parent:GetName() .. "CloseButton"] or parent.PortraitButton
    if anchor then
        RefineUI.Point(button, "RIGHT", anchor, "LEFT", -2, 0)
    else
        RefineUI.Point(button, "TOPRIGHT", parent, "TOPRIGHT", -30, -5)
    end
    
    button:Show()
    EnsureLootSettingsIcon(button)
end

function LootSettings:OnEnable()
    if not RefineUI.Config.Loot.Enable then return end

    RefineUI:RegisterEventCallback("BAG_OPEN", function() 
        C_Timer.After(0.1, function() self:CreateButton() end)
    end, "LootSettings:BagOpen")
    
    local function HookBagOnShow(frame, key)
        if not frame then
            return
        end
        if RefineUI.HookScriptOnce then
            RefineUI:HookScriptOnce("LootSettings:" .. key .. ":OnShow", frame, "OnShow", function()
                self:CreateButton()
            end)
        else
            frame:HookScript("OnShow", function()
                self:CreateButton()
            end)
        end
    end

    HookBagOnShow(_G["RefineUI_Bags"], "RefineUIBags")
    HookBagOnShow(ContainerFrameCombinedBags, "CombinedBags")
    HookBagOnShow(ContainerFrame1, "ContainerFrame1")
    
    C_Timer.After(0.5, function()
        self:CreateButton()
    end)
end

