----------------------------------------------------------------------------------------
-- UnitFrames Class Resources: Segmented
-- Description: Shared segmented resource update paths.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local UnitFrames = RefineUI:GetModule("UnitFrames")
if not UnitFrames then
    return
end

local Private = UnitFrames:GetPrivate()
local CR = Private.ClassResources
local K = CR.Constants

local CreateFrame = CreateFrame
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local GetSpecialization = GetSpecialization
local GetRuneCooldown = GetRuneCooldown
local GetPlayerAuraBySpellID = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID or GetPlayerAuraBySpellID
local max = math.max
local floor = math.floor
local issecretvalue = _G.issecretvalue

function CR.UpdateSegmentedBar(resource)
    local minimumValue
    local maximumValue
    local barCount
    local powerType
    local class = CR.PlayerClass
    local spec = GetSpecialization()

    if resource.Type == "CLASS_POWER" then
        powerType = resource.PowerType
        if class == "WARLOCK" and spec == 3 then
            minimumValue = UnitPower("player", powerType, true)
            maximumValue = UnitPowerMax("player", powerType, true)
            barCount = 5
        else
            minimumValue = UnitPower("player", powerType)
            maximumValue = UnitPowerMax("player", powerType)
            barCount = maximumValue
        end
    elseif resource.Type == "MAELSTROM" then
        local aura = GetPlayerAuraBySpellID(K.ENHANCEMENT_MAELSTROM_WEAPON_AURA_SPELL_ID)
        minimumValue = aura and aura.applications or 0
        maximumValue = 10
        barCount = 10
    elseif resource.Type == "RUNES" then
        minimumValue = 0
        maximumValue = 6
        barCount = 6
    end

    if not barCount or barCount == 0 then
        return
    end

    if resource.LastBarCount and resource.LastBarCount ~= barCount then
        for index = 1, max(barCount, resource.LastBarCount) do
            local segment = resource.Segments[index]
            if segment then
                segment:SetValue(0)
                segment:SetAlpha(0)
                if segment.animGroup then
                    segment.animGroup:Stop()
                end
            end
        end
    end
    resource.LastBarCount = barCount

    local barWidth = resource.Bar:GetWidth()
    if (issecretvalue and issecretvalue(barWidth)) or (not barWidth or barWidth == 0) then
        barWidth = RefineUI:Scale(resource.Bar._width or 120)
    end

    local spacing = 2
    local totalSpacing = (barCount - 1) * spacing
    local runeCoolingActive = false

    for index = 1, barCount do
        local segment = resource.Segments[index]
        if not segment then
            segment = CreateFrame("StatusBar", nil, resource.Bar)
            RefineUI:AddAPI(segment)
            segment:SetFrameLevel(resource.Bar:GetFrameLevel() + 5)
            segment:SetStatusBarTexture(K.RESOURCE_BAR_TEXTURE)
            segment:SetAlpha(0)
            segment:SetScript("OnValueChanged", function(self)
                local value = self:GetValue()
                local minValue, maxValue = self:GetMinMaxValues()
                local isSecret = issecretvalue and issecretvalue(value)
                local fillPercent = 0

                if not isSecret then
                    fillPercent = (maxValue > minValue) and ((value - minValue) / (maxValue - minValue)) or 0
                end

                if isSecret or fillPercent >= 0.99 then
                    if resource.Type == "RUNES" and self._isCooling then
                        self:SetAlpha(0.5)
                    else
                        if self:GetAlpha() < 1 then
                            self:FadeIn()
                        end
                    end
                elseif fillPercent > 0 then
                    if resource.Type == "RUNES" and self._isCooling then
                        self:SetAlpha(0.5)
                    else
                        self:SetAlpha(1)
                    end
                else
                    if self:GetAlpha() > 0 then
                        self:FadeOut(0.15, 0)
                    end
                end
            end)
            resource.Segments[index] = segment
        end

        local width = floor((barWidth - totalSpacing) * index / barCount) - floor((barWidth - totalSpacing) * (index - 1) / barCount)
        segment:SetSize(width, resource.Height)
        segment:ClearAllPoints()
        if index == 1 then
            segment:SetPoint("LEFT", resource.Bar, "LEFT", 0, 0)
        else
            segment:SetPoint("LEFT", resource.Segments[index - 1], "RIGHT", spacing, 0)
        end

        local r, g, b = CR.GetResourceColor(resource.Type, index, barCount)
        segment:SetStatusBarColor(r, g, b)

        if resource.Type == "RUNES" then
            local start, duration, ready = GetRuneCooldown(index)
            if ready then
                minimumValue = minimumValue + 1
                segment:SetMinMaxValues(0, 1)
                segment:SetValue(1)
                segment._isCooling = false
                segment._runeStart = nil
                segment._runeDuration = nil
                if segment.animGroup then
                    segment.animGroup:Stop()
                end
                segment:FadeIn()
            elseif start then
                segment:SetMinMaxValues(0, duration)
                segment._runeStart = start
                segment._runeDuration = duration
                segment._isCooling = true
                segment:FadeOut(0.25, 0.75)
            else
                segment._isCooling = false
                segment._runeStart = nil
                segment._runeDuration = nil
            end

            if segment._isCooling then
                runeCoolingActive = true
            end
        elseif resource.Type == "CLASS_POWER" and class == "WARLOCK" and spec == 3 then
            local barMin, barMax = (index - 1) * 10, index * 10
            segment:SetMinMaxValues(barMin, barMax)
            segment:SetValue(minimumValue)
        else
            segment:SetMinMaxValues(index - 1, index)
            segment:SetValue(minimumValue)
        end
    end

    if resource.Type == "RUNES" then
        CR.SetRuneSchedulerEnabled(runeCoolingActive)
    end

    for index = barCount + 1, #resource.Segments do
        resource.Segments[index]:Hide()
    end

    CR.UpdateGlowState(resource, minimumValue, barCount)

    if resource.Type == "RUNES" then
        local glowR, glowG, glowB = CR.GetResourceColor(resource.Type, nil, barCount)
        if resource.PulseGlow then
            resource.PulseGlow:SetBackdropBorderColor(glowR, glowG, glowB, 0.8)
        end
        if resource.Bar and resource.Bar.border and minimumValue == barCount then
            resource.Bar.border:SetBackdropBorderColor(glowR, glowG, glowB, 1)
        end
    end

    if resource.Text then
        if (issecretvalue and issecretvalue(minimumValue)) or minimumValue ~= 0 then
            resource.Text:SetText(minimumValue)
        else
            resource.Text:SetText("")
        end
        resource.Text:Show()
        resource.Text:SetAlpha(1)

        if class == "PALADIN" and resource.Type == "CLASS_POWER" then
            if not resource.TextColorBar then
                local colorBar = CreateFrame("StatusBar", nil, resource.Bar)
                colorBar:SetSize(1, 1)
                colorBar:SetAlpha(0)
                colorBar:SetPoint("CENTER")
                colorBar:SetScript("OnValueChanged", function(self)
                    local value = self:GetValue()
                    local _, maxValue = self:GetMinMaxValues()
                    if maxValue > 0 then
                        local curve = CR.GetPaladinTextColorCurve(maxValue)
                        local color = curve:Evaluate(value)
                        if resource.Text and color then
                            local r, g, b, a = color:GetRGBA()
                            resource.Text:SetTextColor(r, g, b, a)
                        end
                    end
                end)
                resource.TextColorBar = colorBar
            end

            resource.TextColorBar:SetMinMaxValues(0, barCount)
            resource.TextColorBar:SetValue(minimumValue)
        else
            resource.Text:SetTextColor(1, 1, 1)
        end
    end
end
