local R, C, L = unpack(RefineUI)
if not C_AddOns.IsAddOnLoaded("BigWigs") then return end

----------------------------------------------------------------------------------------
--	BigWigs nameplate icon skinning
--
-- This module automatically skins BigWigs nameplate icons to match RefineUI's styling.
-- Configuration options are available in Config/Settings.lua under the nameplate section:
-- - nameplate.bigwigsSkinning: Enable/disable BigWigs icon skinning
-- - nameplate.bigwigsIconSize: Size of BigWigs nameplate icons
-- - nameplate.bigwigsShowCooldown: Show cooldown swipe on BigWigs icons
-- - nameplate.bigwigsShowCount: Show count text on BigWigs icons
----------------------------------------------------------------------------------------

local BigWigs = rawget(_G, "BigWigs")
if not BigWigs then return end

-- Store skinned icons to avoid double-skinning
local skinnedIcons = {}

-- Function to apply RefineUI styling to BigWigs nameplate icons
local function SkinBigWigsIcon(iconFrame)
    if not iconFrame or skinnedIcons[iconFrame] or not C.nameplate.bigwigsSkinning then return end
    
    -- Apply RefineUI styling similar to aura icons
    if not iconFrame.isRefineUISkinned then
        if C.nameplate.bigwigsDebug then
            print("RefineUI: Skinning BigWigs nameplate icon")
        end
        
        -- Create backdrop using RefineUI's styling system
        iconFrame:CreateBackdrop("Transparent")
        
        -- Style the icon texture
        if iconFrame.icon then
            iconFrame.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
            iconFrame.icon:SetDrawLayer("ARTWORK")
        end
        
        -- Style cooldown if present and enabled
        if iconFrame.cooldown and C.nameplate.bigwigsShowCooldown then
            iconFrame.cooldown:SetSwipeTexture(C.media.auraCooldown or C.media.blank)
            iconFrame.cooldown:SetReverse(true)
            iconFrame.cooldown:SetDrawEdge(false)
            iconFrame.cooldown:SetSwipeColor(0, 0, 0, 0.8)
        elseif iconFrame.cooldown and not C.nameplate.bigwigsShowCooldown then
            iconFrame.cooldown:Hide()
        end
        
        -- Style countdown number if present and enabled
        if iconFrame.countdownNumber and C.nameplate.bigwigsShowCount then
            iconFrame.countdownNumber:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", 1, 1)
            iconFrame.countdownNumber:SetJustifyH("CENTER")
            iconFrame.countdownNumber:SetFont(unpack(C.font.nameplates.aurasCount or C.font.nameplates.default))
            iconFrame.countdownNumber:SetShadowOffset(1, -1)
        elseif iconFrame.countdownNumber and not C.nameplate.bigwigsShowCount then
            iconFrame.countdownNumber:Hide()
        end
        
        iconFrame.isRefineUISkinned = true
        skinnedIcons[iconFrame] = true
    end
end

-- Simple approach: Scan for BigWigs icons on nameplates
local function ScanForBigWigsIcons()
    if not C.nameplate.bigwigsSkinning then return end
    
    -- Scan all nameplates for BigWigs icons
    for i = 1, 40 do
        local nameplate = C_NamePlate.GetNamePlateForUnit("nameplate" .. i)
        if nameplate and nameplate:IsShown() then
            -- Look for BigWigs icons in the nameplate's children
            local function ScanChildren(parent)
                if not parent or not parent.GetChildren then return end
                for _, child in pairs({parent:GetChildren()}) do
                    if child and child.GetObjectType and child:GetObjectType() == "Frame" then
                        -- Check if this looks like a BigWigs icon frame
                        if child.icon and child.cooldown and child.countdownNumber then
                            SkinBigWigsIcon(child)
                        end
                    end
                    ScanChildren(child)
                end
            end
            ScanChildren(nameplate)
        end
    end
end

-- Hook into nameplate creation events
local function HookNameplateEvents()
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    eventFrame:SetScript("OnEvent", function(self, event, unit)
        if event == "NAME_PLATE_UNIT_ADDED" then
            -- Wait a moment for BigWigs to create its icons
            C_Timer.After(0.5, ScanForBigWigsIcons)
        end
    end)
end

-- Alternative approach: Hook into frame creation to catch BigWigs icons as they're created
local function HookFrameCreation()
    -- Hook CreateFrame to catch BigWigs icon creation
    local originalCreateFrame = CreateFrame
    CreateFrame = function(frameType, name, parent, template, id)
        local frame = originalCreateFrame(frameType, name, parent, template, id)
        
        -- Check if this looks like a BigWigs icon frame
        if frame and frameType == "Frame" and not name and parent and parent:GetObjectType() == "Frame" then
            -- Wait a moment for the frame to be fully set up
            C_Timer.After(0.1, function()
                if frame.icon and frame.cooldown and frame.countdownNumber then
                    SkinBigWigsIcon(frame)
                end
            end)
        end
        
        return frame
    end
end

-- Initialize the skinning system
local function InitializeBigWigsSkinning()
    if C.nameplate.bigwigsDebug then
        print("RefineUI: Initializing BigWigs nameplate icon skinning")
    end
    
    -- Set up event hooks
    HookNameplateEvents()
    
    -- Hook frame creation
    HookFrameCreation()
    
    -- Scan for existing icons immediately
    ScanForBigWigsIcons()
    
    -- Set up periodic scanning
    C_Timer.NewTicker(1, ScanForBigWigsIcons)
end

-- Wait for BigWigs to be fully loaded
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName == "BigWigs" or addonName == "BigWigs_Plugins" then
        C_Timer.After(1, InitializeBigWigsSkinning)
        self:UnregisterEvent(event)
    end
end)

-- Also try to initialize immediately if BigWigs is already loaded
if BigWigs and BigWigs.GetPlugin then
    C_Timer.After(0.5, InitializeBigWigsSkinning)
end

-- Export functions for potential future use
R.BigWigsSkinning = {
    SkinIcon = SkinBigWigsIcon,
    Initialize = InitializeBigWigsSkinning,
}

-- Add test commands for debugging
SLASH_REFINEUI_BIGWIGS_TEST1 = "/refineui-bigwigs-test"
SlashCmdList["REFINEUI_BIGWIGS_TEST"] = function()
    print("RefineUI BigWigs Test:")
    print("- BigWigs loaded:", BigWigs and "Yes" or "No")
    print("- BigWigs Nameplate Plugin:", BigWigs and BigWigs:GetPlugin("Nameplate") and "Found" or "Not found")
    print("- Skinning enabled:", C.nameplate.bigwigsSkinning and "Yes" or "No")
    print("- Debug enabled:", C.nameplate.bigwigsDebug and "Yes" or "No")
    
    local iconCount = 0
    for i = 1, 40 do
        local nameplate = C_NamePlate.GetNamePlateForUnit("nameplate" .. i)
        if nameplate and nameplate:IsShown() then
            local function CountIcons(parent)
                if not parent or not parent.GetChildren then return end
                for _, child in pairs({parent:GetChildren()}) do
                    if child and child.GetObjectType and child:GetObjectType() == "Frame" then
                        if child.icon and child.cooldown and child.countdownNumber then
                            iconCount = iconCount + 1
                            print("- BigWigs icon found on nameplate", i, "skinned:", child.isRefineUISkinned and "Yes" or "No")
                        end
                    end
                    CountIcons(child)
                end
            end
            CountIcons(nameplate)
        end
    end
    print("- Total BigWigs icons found:", iconCount)
end

SLASH_REFINEUI_BIGWIGS_SCAN1 = "/refineui-bigwigs-scan"
SlashCmdList["REFINEUI_BIGWIGS_SCAN"] = function()
    print("RefineUI: Manually scanning for BigWigs icons...")
    ScanForBigWigsIcons()
    print("RefineUI: Scan complete!")
end
