----------------------------------------------------------------------------------------
-- UnitFrames Class Resources: Totems
-- Description: Totem button syncing and visibility management.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local UnitFrames = RefineUI:GetModule("UnitFrames")
if not UnitFrames then
    return
end

local Private = UnitFrames:GetPrivate()
local CR = Private.ClassResources
local K = CR.Constants

local pcall = pcall
local type = type

function CR.UpdateTotemBar(resource)
    if not resource or type(resource.Buttons) ~= "table" then
        return
    end

    local anyActive = false
    local mappedByLayoutIndex = {}
    local totemFrame = _G.TotemFrame

    if totemFrame
        and type(totemFrame.totemPool) == "table"
        and type(totemFrame.totemPool.EnumerateActive) == "function"
    then
        for totemButton in totemFrame.totemPool:EnumerateActive() do
            if totemButton then
                local layoutIndex = totemButton.layoutIndex
                if CR.IsNonSecretNumber(layoutIndex) and layoutIndex >= 1 and layoutIndex <= K.MAX_TOTEMS then
                    mappedByLayoutIndex[layoutIndex] = totemButton
                end
            end
        end
    end

    for index = 1, K.MAX_TOTEMS do
        local button = resource.Buttons[index]
        local sourceButton = mappedByLayoutIndex[index]
        local isActive = sourceButton and type(sourceButton.IsShown) == "function" and sourceButton:IsShown() == true

        if isActive and button then
            local sourceIcon = sourceButton.Icon and sourceButton.Icon.Texture
            local iconTexture = nil
            if sourceIcon and type(sourceIcon.GetTexture) == "function" then
                local okIcon, resolvedTexture = pcall(sourceIcon.GetTexture, sourceIcon)
                if okIcon and CR.IsNonSecretTexture(resolvedTexture) then
                    iconTexture = resolvedTexture
                end
            end

            if iconTexture then
                button.Icon:SetTexture(iconTexture)
            end

            local sourceCooldown = sourceButton.Icon and sourceButton.Icon.Cooldown
            local didApplyCooldown = false
            if sourceCooldown and type(sourceCooldown.GetCooldownTimes) == "function" then
                local okTimes, startMS, durationMS = pcall(sourceCooldown.GetCooldownTimes, sourceCooldown)
                if okTimes
                    and not CR.IsSecret(startMS)
                    and not CR.IsSecret(durationMS)
                    and type(startMS) == "number"
                    and type(durationMS) == "number"
                    and durationMS > 0
                then
                    button.Cooldown:SetCooldown(startMS / 1000, durationMS / 1000)
                    didApplyCooldown = true
                end
            end

            if not didApplyCooldown then
                CR.ClearCooldownSafe(button.Cooldown)
            end

            button:FadeIn()
            anyActive = true
        elseif button then
            CR.ClearCooldownSafe(button.Cooldown)
            button:FadeOut()
        end
    end

    if anyActive then
        resource.Bar:Show()
    else
        resource.Bar:Hide()
    end
end
