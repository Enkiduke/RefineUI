local R, C, L = unpack(RefineUI)

-- Shared function to apply font styling to button count text
local function StyleButtonCount(button)
    if button.Count then
        button.Count:SetFont(C.font.actionbars.count[1], C.font.actionbars.count[2], C.font.actionbars.count[3])
        button.Count:SetShadowOffset(1, -1)
    end
end

-- Style extra action buttons (1-3)
for i = 1, 3 do
    local button = _G["ExtraActionButton" .. i]
    if button then
        button:SetScale(1.25)
        StyleButtonCount(button)
    end
end

-- Style and center zone ability buttons
local function StyleZoneAbilityButtons()
    if not ZoneAbilityFrame or not ZoneAbilityFrame.SpellButtonContainer then
        return
    end
    
    -- Process each active button
    for button in ZoneAbilityFrame.SpellButtonContainer:EnumerateActive() do
        -- Scale button (not the frame to preserve centering)
        button:SetScale(1.25)
        
        -- Apply RefineUI styling once
        if not button.isSkinned then
            -- Apply template and hide default textures
            button:SetTemplate("Zero")
            if button.NormalTexture then
                button.NormalTexture:SetAlpha(0)
            end
            
            -- Style icon
            if button.Icon then
                button.Icon:ClearAllPoints()
                button.Icon:SetPoint("TOPLEFT", button, 2, -2)
                button.Icon:SetPoint("BOTTOMRIGHT", button, -2, 2)
                button.Icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
            end
            
            -- Style count text
            if button.Count then
                button.Count:SetParent(button)
                button.Count:SetJustifyH("RIGHT")
                button.Count:SetPoint("BOTTOMRIGHT", button, -3, 3)
                button.Count:SetDrawLayer("OVERLAY", 1)
                StyleButtonCount(button)
            end
            
            -- Style cooldown
            if button.Cooldown then
                button.Cooldown:ClearAllPoints()
                button.Cooldown:SetAllPoints(button.Icon or button)
            end
            
            button.isSkinned = true
        end
    end
end

-- Initialize zone ability styling
if ZoneAbilityFrame then
    -- Hook to relevant events
    hooksecurefunc(ZoneAbilityFrame, "UpdateDisplayedZoneAbilities", function()
        C_Timer.After(0.01, StyleZoneAbilityButtons)
    end)
    
    ZoneAbilityFrame:HookScript("OnShow", function()
        C_Timer.After(0.01, StyleZoneAbilityButtons)
    end)
    
    -- Initial styling
    C_Timer.After(0.5, StyleZoneAbilityButtons)
end
