----------------------------------------------------------------------------------------
-- UnitFrames Class Resources: Builder
-- Description: Resource frame creation and orchestration for the player frame.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local UnitFrames = RefineUI:GetModule("UnitFrames")
if not UnitFrames then
    return
end

local Config = RefineUI.Config
local Private = UnitFrames:GetPrivate()
local CR = Private.ClassResources
local K = CR.Constants

local CreateFrame = CreateFrame
local GetSpecialization = GetSpecialization
local UnitPowerType = UnitPowerType
local floor = math.floor

function UnitFrames:CreateClassResources(frame)
    if frame ~= PlayerFrame then
        return
    end

    local resources = UnitFrames.ClassResources
    local dataBars = Config.UnitFrames.DataBars
    local class = CR.PlayerClass

    local function ResolveResourceAnchor()
        local anchor = (frame.RefineUF and frame.RefineUF.Texture) or frame

        if frame.PlayerFrameContent and frame.PlayerFrameContent.PlayerFrameContentMain then
            local healthBarContainer = frame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer
            if healthBarContainer then
                anchor = healthBarContainer
            end
        end

        return anchor
    end

    local function CreateBaseBar(name, frameType, width, height, yOffset)
        local frameName = "RefineUI_" .. name
        local position = RefineUI.Positions[frameName]
        local anchor = ResolveResourceAnchor()
        local existing = _G[frameName]

        if existing then
            existing:ClearAllPoints()
            if position then
                existing:Point(position[1], anchor, position[3], position[4], position[5])
            else
                existing:Point("BOTTOM", anchor, "TOP", 0, yOffset or dataBars.YOffset or 4)
            end
            return existing, existing.PulseGlow
        end

        local parent = frame.RefineUF or frame
        local barWidth = width or dataBars.Width or 120
        local barHeight = height or dataBars.Height or 4
        local offset = yOffset or dataBars.YOffset or 4
        local bar = CreateFrame(frameType == "STATUS" and "StatusBar" or "Frame", frameName, parent)
        RefineUI:AddAPI(bar)
        bar:Size(barWidth, barHeight)
        bar._width = barWidth

        if position then
            bar:Point(position[1], anchor, position[3], position[4], position[5])
        else
            bar:Point("BOTTOM", anchor, "TOP", 0, offset)
        end

        bar:SetTemplate("Transparent")
        bar:CreateBorder(4, 4, 8)
        bar:Hide()

        if bar.border then
            bar.border:SetFrameLevel(bar:GetFrameLevel() + 10)
        end

        local pulseGlow = RefineUI.CreateGlow and RefineUI.CreateGlow(bar, 2)
        if pulseGlow then
            pulseGlow:SetFrameStrata(bar:GetFrameStrata())
            pulseGlow:SetFrameLevel(bar:GetFrameLevel() + 20)
            pulseGlow:SetBackdropBorderColor(1, 0.5, 0.5, 1)
            pulseGlow:Hide()
        end

        bar.PulseGlow = pulseGlow
        return bar, pulseGlow
    end

    local classPowerType = (class == "ROGUE" or class == "DRUID") and K.POWER_COMBO_POINTS or
        (class == "WARLOCK") and K.POWER_SOUL_SHARDS or
        (class == "PALADIN") and K.POWER_HOLY_POWER or
        (class == "MONK") and K.POWER_CHI or
        (class == "MAGE") and K.POWER_ARCANE_CHARGES or
        (class == "EVOKER") and K.POWER_ESSENCE

    if classPowerType and dataBars.ClassPowerBar then
        local bar, glow = CreateBaseBar("ClassPowerBar", "FRAME")
        if not bar.Text then
            local parent = bar.border or bar
            local text = parent:CreateFontString(nil, "OVERLAY")
            RefineUI:AddAPI(text)
            text:Point("CENTER", bar, 0, 0)
            text:Font(16, nil, "OUTLINE")
            text:Hide()
            bar.Text = text
        end

        if not resources.ClassPower then
            resources.ClassPower = {
                Bar = bar,
                PulseGlow = glow,
                Type = "CLASS_POWER",
                Segments = {},
                Text = bar.Text,
            }
        else
            local resource = resources.ClassPower
            resource.Bar = bar
            resource.PulseGlow = glow
            resource.Type = "CLASS_POWER"
            resource.Height = dataBars.Height or 8
            resource.Text = bar.Text
        end

        resources.ClassPower.PowerType = classPowerType
        resources.ClassPower.Height = dataBars.Height or 8

        bar:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
        bar:RegisterUnitEvent("UNIT_MAXPOWER", "player")
        bar:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
        bar:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        bar:RegisterEvent("PLAYER_ENTERING_WORLD")

        local powerTypeNames = {
            [K.POWER_COMBO_POINTS] = "COMBO_POINTS",
            [K.POWER_SOUL_SHARDS] = "SOUL_SHARDS",
            [K.POWER_HOLY_POWER] = "HOLY_POWER",
            [K.POWER_CHI] = "CHI",
            [K.POWER_ARCANE_CHARGES] = "ARCANE_CHARGES",
            [K.POWER_ESSENCE] = "ESSENCE",
        }
        resources.ClassPower.PowerTypeName = powerTypeNames[classPowerType]

        local function ShouldShowClassPower(spec)
            return (class == "ROGUE" or class == "WARLOCK" or class == "PALADIN" or class == "EVOKER")
                or (class == "DRUID" and UnitPowerType("player") == K.POWER_ENERGY)
                or (class == "MONK" and spec == K.SPEC_MONK_WINDWALKER)
                or (class == "MAGE" and spec == 1)
        end

        local function QueueClassPowerUpdate()
            local resource = resources.ClassPower
            if not resource or resource.updateQueued then
                return
            end
            resource.updateQueued = true
            C_Timer.After(0, function()
                local queuedResource = resources.ClassPower
                if not queuedResource then
                    return
                end
                queuedResource.updateQueued = false

                local spec = GetSpecialization()
                if ShouldShowClassPower(spec) then
                    bar:Show()
                    CR.UpdateSegmentedBar(queuedResource)
                else
                    bar:Hide()
                end
            end)
        end

        bar:SetScript("OnEvent", function(_, event, unit, powerType)
            if event == "UNIT_POWER_UPDATE" then
                if unit ~= "player" then
                    return
                end
                if powerType ~= resources.ClassPower.PowerTypeName then
                    return
                end
            elseif event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
                if unit ~= "player" then
                    return
                end
            end

            QueueClassPowerUpdate()
        end)

        CR.HideBlizzardResource(_G.ComboPointPlayerFrame)
        CR.HideBlizzardResource(_G.WarlockShardBarFrame)
        CR.HideBlizzardResource(_G.PaladinPowerBarFrame)
        CR.HideBlizzardResource(_G.MonkHarmonyBarFrame)
        CR.HideBlizzardResource(_G.MageArcaneChargesFrame)
        CR.HideBlizzardResource(_G.EvokerEssencePlayerFrame)
        CR.HideBlizzardResource(_G.EssencePlayerFrame)
        CR.HideBlizzardResource(_G.EvokerEbonMightBar)

        CR.HideBlizzardResource(_G.ClassNameplateBarRogueFrame)
        CR.HideBlizzardResource(_G.ClassNameplateBarWarlockFrame)
        CR.HideBlizzardResource(_G.ClassNameplateBarPaladinFrame)
        CR.HideBlizzardResource(_G.ClassNameplateBarMonkFrame)
        CR.HideBlizzardResource(_G.ClassNameplateBarMageFrame)
        CR.HideBlizzardResource(_G.ClassNameplateBarDracthyrFrame)
    end

    if (class == "PRIEST" or class == "DRUID" or class == "SHAMAN") and dataBars.SecondaryPowerBar then
        local bar, glow = CreateBaseBar("SecondaryPowerBar", "STATUS", nil, dataBars.HeightLarge or 16, dataBars.YOffset or 4)
        bar:SetStatusBarTexture(K.RESOURCE_BAR_TEXTURE)

        if not bar.Text then
            local parent = bar.border or bar
            local text = parent:CreateFontString(nil, "OVERLAY")
            RefineUI:AddAPI(text)
            text:Point("CENTER", bar, 0, 0)
            text:Font(18, nil, "OUTLINE")
            text:Hide()
            bar.Text = text
        end

        if not resources.SecondaryPower then
            resources.SecondaryPower = {
                Bar = bar,
                PulseGlow = glow,
                Type = "SECONDARY_POWER",
                Text = bar.Text,
            }
        else
            local resource = resources.SecondaryPower
            resource.Bar = bar
            resource.PulseGlow = glow
            resource.Type = "SECONDARY_POWER"
            resource.Text = bar.Text
        end

        bar:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
        bar:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
        bar:RegisterUnitEvent("UNIT_MAXPOWER", "player")
        bar:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
        bar:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        bar:RegisterEvent("PLAYER_ENTERING_WORLD")

        local function QueueSecondaryPowerUpdate()
            local resource = resources.SecondaryPower
            if not resource or resource.updateQueued then
                return
            end
            resource.updateQueued = true
            C_Timer.After(0, function()
                local queuedResource = resources.SecondaryPower
                if not queuedResource then
                    return
                end
                queuedResource.updateQueued = false

                local powerType, powerTypeName = CR.GetPlayerSecondaryPowerInfo()
                if not powerType or not powerTypeName then
                    bar:Hide()
                    return
                end

                queuedResource.PowerType = powerType
                queuedResource.PowerTypeName = powerTypeName
                bar:Show()
                CR.UpdateStatusBar(queuedResource)
            end)
        end

        bar:SetScript("OnEvent", function(_, event, unit)
            if event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" then
                if unit ~= "player" then
                    return
                end
            elseif event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
                if unit ~= "player" then
                    return
                end
            end

            QueueSecondaryPowerUpdate()
        end)

        CR.HideBlizzardResource(_G.AlternatePowerBar)
        CR.HideBlizzardResource(_G.InsanityBarFrame)
    end

    if class == "DEATHKNIGHT" and dataBars.RuneBar then
        local bar, glow = CreateBaseBar("RuneBar", "FRAME", nil, dataBars.HeightLarge or 16)
        if not bar.Background then
            local background = bar:CreateTexture(nil, "ARTWORK", nil, -1)
            background:SetAllPoints(bar)
            background:SetTexture(K.RESOURCE_BAR_TEXTURE)
            background:SetVertexColor(0.06, 0.06, 0.08, 0.9)
            bar.Background = background
        end

        if not resources.Runes then
            resources.Runes = {
                Bar = bar,
                PulseGlow = glow,
                Type = "RUNES",
                Segments = {},
                Height = dataBars.HeightLarge or 16,
            }
        else
            local resource = resources.Runes
            resource.Bar = bar
            resource.PulseGlow = glow
            resource.Height = dataBars.HeightLarge or 16
        end

        bar:RegisterEvent("RUNE_POWER_UPDATE")
        bar:RegisterEvent("PLAYER_ENTERING_WORLD")
        bar:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        bar:SetScript("OnEvent", function()
            bar:Show()
            CR.UpdateSegmentedBar(resources.Runes)
        end)

        CR.HideBlizzardResource(_G.DeathKnightResourceBar)
    end

    if class == "SHAMAN" and dataBars.MaelstromBar then
        local bar, glow = CreateBaseBar("MaelstromBar", "FRAME", nil, dataBars.HeightLarge or 16, dataBars.YOffset or 4)
        local textParent = bar.border or bar

        if not bar.Text then
            local text = textParent:CreateFontString(nil, "OVERLAY")
            RefineUI:AddAPI(text)
            text:Point("CENTER", bar, 0, 0)
            text:Font(22)
            if text.SetDrawLayer then
                text:SetDrawLayer("OVERLAY", 7)
            end
            bar.Text = text
        else
            if bar.Text:GetParent() ~= textParent then
                bar.Text:SetParent(textParent)
            end
            if bar.Text.SetDrawLayer then
                bar.Text:SetDrawLayer("OVERLAY", 7)
            end
        end

        if not resources.Maelstrom then
            resources.Maelstrom = {
                Bar = bar,
                PulseGlow = glow,
                Type = "MAELSTROM",
                Segments = {},
                Height = dataBars.HeightLarge or 16,
                Text = bar.Text,
            }
        else
            local resource = resources.Maelstrom
            resource.Bar = bar
            resource.PulseGlow = glow
            resource.Height = dataBars.HeightLarge or 16
            resource.Text = bar.Text
        end

        bar:RegisterEvent("UNIT_AURA")
        bar:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        bar:RegisterEvent("PLAYER_ENTERING_WORLD")
        bar:SetScript("OnEvent", function()
            if GetSpecialization() == K.SPEC_SHAMAN_ENHANCEMENT then
                bar:Show()
                CR.UpdateSegmentedBar(resources.Maelstrom)
            else
                bar:Hide()
            end
        end)
    end

    if class == "MONK" and dataBars.StaggerBar then
        local bar, glow = CreateBaseBar("StaggerBar", "STATUS", nil, dataBars.HeightLarge or 16, dataBars.YOffset or 4)
        local staggerTextSize = dataBars.StaggerTextSize or 12
        bar:SetStatusBarTexture(K.RESOURCE_BAR_TEXTURE)

        if not bar.Text then
            local text = bar:CreateFontString(nil, "OVERLAY")
            RefineUI:AddAPI(text)
            text:Point("LEFT", bar, 4, -1)
            text:Font(staggerTextSize)
            text:SetJustifyH("LEFT")
            bar.Text = text
        end

        if not bar.TextPer then
            local textPer = bar:CreateFontString(nil, "OVERLAY")
            RefineUI:AddAPI(textPer)
            textPer:Point("RIGHT", bar, -4, -1)
            textPer:Font(staggerTextSize)
            textPer:SetJustifyH("RIGHT")
            bar.TextPer = textPer
        end

        if not resources.Stagger then
            resources.Stagger = {
                Bar = bar,
                PulseGlow = glow,
                Type = "STAGGER",
                Text = bar.Text,
                TextPer = bar.TextPer,
            }
        else
            local resource = resources.Stagger
            resource.Bar = bar
            resource.PulseGlow = glow
            resource.Text = bar.Text
            resource.TextPer = bar.TextPer
        end

        bar:RegisterEvent("UNIT_AURA")
        bar:RegisterEvent("UNIT_MAXPOWER")
        bar:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        bar:RegisterEvent("PLAYER_ENTERING_WORLD")
        bar:SetScript("OnEvent", function()
            if GetSpecialization() == K.SPEC_MONK_BREWMASTER then
                bar:Show()
                CR.UpdateStatusBar(resources.Stagger)
            else
                bar:Hide()
            end
        end)

        CR.HideBlizzardResource(_G.MonkStaggerBar)
    end

    if class == "DEMONHUNTER" and GetSpecialization() == 2 and dataBars.SoulFragmentsBar then
        local bar, glow = CreateBaseBar("SoulFragmentsBar", "STATUS", nil, dataBars.Height or 4, dataBars.YOffset or 4)
        bar:SetStatusBarTexture(K.RESOURCE_BAR_TEXTURE)

        if not bar.Text then
            local text = bar:CreateFontString(nil, "OVERLAY")
            RefineUI:AddAPI(text)
            text:Point("CENTER", bar, 0, 0)
            text:Font(16)
            bar.Text = text
        end

        if not resources.SoulFragments then
            resources.SoulFragments = {
                Bar = bar,
                PulseGlow = glow,
                Type = "SOUL_FRAGMENTS",
                Text = bar.Text,
            }
        else
            local resource = resources.SoulFragments
            resource.Bar = bar
            resource.PulseGlow = glow
            resource.Text = bar.Text
        end

        bar:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
        bar:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        bar:RegisterEvent("PLAYER_ENTERING_WORLD")

        local function QueueSoulFragmentsUpdate()
            local resource = resources.SoulFragments
            if not resource or resource.updateQueued then
                return
            end
            resource.updateQueued = true
            C_Timer.After(0, function()
                local queuedResource = resources.SoulFragments
                if not queuedResource then
                    return
                end
                queuedResource.updateQueued = false
                if GetSpecialization() == 2 then
                    bar:Show()
                    CR.UpdateStatusBar(queuedResource)
                else
                    bar:Hide()
                end
            end)
        end

        bar:SetScript("OnEvent", function(_, event, unit, powerType)
            if event == "UNIT_POWER_UPDATE" then
                if unit ~= "player" then
                    return
                end
                if powerType ~= "SOUL_FRAGMENTS" then
                    return
                end
            end
            QueueSoulFragmentsUpdate()
        end)

        CR.HideBlizzardResource(_G.DemonHunterSoulFragmentsBar)
    end

    if dataBars.TotemBar and (class == "SHAMAN" or class == "DRUID" or class == "MONK") then
        local bar, glow = CreateBaseBar("TotemBar", "FRAME", nil, 14, dataBars.YOffset or 4)
        local buttons = bar.Buttons or {}
        local barWidth = dataBars.Width or 120
        local buttonSize = floor((barWidth - (K.MAX_TOTEMS - 1) * (dataBars.Spacing or 2)) / K.MAX_TOTEMS)

        if not bar.Buttons then
            for index = 1, K.MAX_TOTEMS do
                local button = CreateFrame("Frame", nil, bar)
                RefineUI:AddAPI(button)
                button:SetID(index)
                button:Size(buttonSize, 12)
                button:SetTemplate("Default")
                button:SetAlpha(0)

                if index == 1 then
                    button:Point("LEFT", bar)
                else
                    button:Point("LEFT", buttons[index - 1], "RIGHT", 2, 0)
                end

                button.Icon = button:CreateTexture(nil, "OVERLAY")
                RefineUI.SetInside(button.Icon)
                button.Icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)

                button.Cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
                RefineUI.SetInside(button.Cooldown)
                button.Cooldown:SetHideCountdownNumbers(false)

                if class == "SHAMAN" then
                    local destroyButton = CreateFrame("Button", nil, button, "SecureUnitButtonTemplate")
                    destroyButton:SetID(index)
                    destroyButton:SetAllPoints()
                    destroyButton:RegisterForClicks("RightButtonUp")
                    destroyButton:SetAttribute("type2", "destroytotem")
                    destroyButton:SetAttribute("*totem-slot*", index)
                end

                buttons[index] = button
            end

            bar.Buttons = buttons
        end

        if not resources.Totems then
            resources.Totems = {
                Bar = bar,
                PulseGlow = glow,
                Type = "TOTEM",
                Buttons = buttons,
            }
        else
            local resource = resources.Totems
            resource.Bar = bar
            resource.PulseGlow = glow
            resource.Buttons = buttons
        end

        bar:RegisterEvent("PLAYER_TOTEM_UPDATE")
        bar:RegisterEvent("PLAYER_ENTERING_WORLD")
        bar:SetScript("OnEvent", function()
            bar:Show()
            CR.UpdateTotemBar(resources.Totems)
        end)

        CR.HideBlizzardResource(_G.TotemFrame)
    end
end
