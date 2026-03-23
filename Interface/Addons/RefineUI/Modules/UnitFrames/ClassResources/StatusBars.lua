----------------------------------------------------------------------------------------
-- UnitFrames Class Resources: Status Bars
-- Description: Shared status-bar resource update paths.
----------------------------------------------------------------------------------------
local _, RefineUI = ...
local UnitFrames = RefineUI:GetModule("UnitFrames")
if not UnitFrames then
    return
end

local Private = UnitFrames:GetPrivate()
local CR = Private.ClassResources
local K = CR.Constants

local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnitStagger = UnitStagger
local UnitHealthMax = UnitHealthMax
local floor = math.floor
local max = math.max
local type = type
local issecretvalue = _G.issecretvalue

local function UpdateSoulFragmentsSpark(resource, minimumValue, maximumValue, isSecret)
    if not resource or resource.Type ~= "SOUL_FRAGMENTS" then
        return
    end

    local spark = resource.Spark or (resource.Bar and resource.Bar.Spark)
    local bar = resource.Bar
    if not spark or not bar then
        return
    end

    if isSecret or type(minimumValue) ~= "number" or type(maximumValue) ~= "number" or maximumValue <= 0 then
        spark:Hide()
        return
    end

    if type(spark.SetVisuals) == "function" and type(spark.OnBarValuesUpdated) == "function" then
        spark.statusBar = bar
        spark:SetVisuals(K.SOUL_FRAGMENTS_SPARK_VISUAL)
        spark:OnBarValuesUpdated()
        return
    end

    local statusBarTexture = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if not statusBarTexture then
        spark:Hide()
        return
    end

    spark:ClearAllPoints()
    spark:SetPoint("RIGHT", statusBarTexture, "RIGHT", K.SOUL_FRAGMENTS_SPARK_VISUAL.xOffset or 0, 0)
    spark:SetAtlas(K.SOUL_FRAGMENTS_SPARK_VISUAL.atlas, true)

    local scale = 1
    local barHeight = statusBarTexture:GetHeight()
    local sourceHeight = K.SOUL_FRAGMENTS_SPARK_VISUAL.barHeight
    if type(barHeight) == "number" and barHeight > 0 and type(sourceHeight) == "number" and sourceHeight > 0 then
        scale = max(barHeight / sourceHeight, 0.01)
    end
    spark:SetScale(scale)
    spark:SetShown(minimumValue > 0 and (minimumValue < maximumValue or K.SOUL_FRAGMENTS_SPARK_VISUAL.showAtMax))
end

function CR.UpdateStatusBar(resource)
    local minimumValue
    local maximumValue
    local r
    local g
    local b
    local class = CR.PlayerClass
    local bar = resource.Bar

    if resource.Type == "STAGGER" then
        minimumValue, maximumValue = UnitStagger("player"), UnitHealthMax("player")
        if issecretvalue and (issecretvalue(minimumValue) or issecretvalue(maximumValue)) then
            r, g, b = 0.52, 1, 0.52
        else
            if maximumValue == 0 then
                return
            end
            local percentage = minimumValue / maximumValue
            if percentage >= K.STAGGER_RED_TRANSITION then
                r, g, b = 1, 0.52, 0.52
            elseif percentage > K.STAGGER_YELLOW_TRANSITION then
                r, g, b = 1, 0.82, 0.52
            else
                r, g, b = 0.52, 1, 0.52
            end
        end
    elseif resource.Type == "SECONDARY_POWER" then
        minimumValue = UnitPower("player", resource.PowerType)
        maximumValue = UnitPowerMax("player", resource.PowerType)

        local powerColor = RefineUI.Colors.Power[resource.PowerTypeName or ""]
        if powerColor then
            r, g, b = powerColor.r, powerColor.g, powerColor.b
        else
            local classColor = RefineUI.MyClassColor or RefineUI.Colors.Class[class]
            if classColor then
                r, g, b = classColor.r, classColor.g, classColor.b
            else
                r, g, b = 1, 1, 1
            end
        end

        if not maximumValue or (type(maximumValue) == "number" and maximumValue <= 0) then
            maximumValue = 1
            if not minimumValue or (type(minimumValue) == "number" and minimumValue < 0) then
                minimumValue = 0
            end
        end
    elseif resource.Type == "SOUL_FRAGMENTS" then
        minimumValue, maximumValue = CR.GetSoulFragmentsState()
        r, g, b = 0.06, 0.42, 0.92

        if not maximumValue or (type(maximumValue) == "number" and maximumValue <= 0) then
            maximumValue = 1
            if not minimumValue or (type(minimumValue) == "number" and minimumValue < 0) then
                minimumValue = 0
            end
        end
    end

    local isSecret = issecretvalue and (issecretvalue(minimumValue) or issecretvalue(maximumValue))
    local allowSecretPassThrough = (resource.Type == "SECONDARY_POWER")

    if isSecret and not allowSecretPassThrough then
        local safeMax = resource.LastSafeMax
        local safeMin = resource.LastSafeMin

        if type(safeMax) ~= "number" or safeMax <= 0 or (issecretvalue and issecretvalue(safeMax)) then
            safeMax = 1
        end
        if type(safeMin) ~= "number" or (issecretvalue and issecretvalue(safeMin)) then
            safeMin = 0
        end

        if safeMin < 0 then
            safeMin = 0
        end
        if safeMin > safeMax then
            safeMin = safeMax
        end

        bar:SetMinMaxValues(0, safeMax)
        bar:SetValue(safeMin)
    else
        if not isSecret then
            resource.LastSafeMin = minimumValue
            resource.LastSafeMax = maximumValue
        end
        bar:SetMinMaxValues(0, maximumValue)
        bar:SetValue(minimumValue)
    end

    bar:SetStatusBarColor(r, g, b)

    if isSecret then
        if resource.Text then
            if resource.Type == "SECONDARY_POWER" then
                resource.Text:SetText(minimumValue)
            else
                resource.Text:SetText("")
            end
            resource.Text:SetTextColor(1, 1, 1)
        end
        if resource.TextPer then
            resource.TextPer:SetText("")
        end
        CR.HandleResourceGlow(resource, false, r, g, b)
    else
        if resource.Text then
            resource.Text:SetText(RefineUI:ShortValue(minimumValue))
        end
        if resource.Type == "STAGGER" and resource.TextPer then
            resource.TextPer:SetText(floor(minimumValue / maximumValue * 1000) / 10 .. "%")
        end
        CR.HandleResourceGlow(resource, (minimumValue == maximumValue and minimumValue > 0), r, g, b)
    end

    if resource.Text then
        resource.Text:Show()
        resource.Text:SetAlpha(1)

        if resource.Type == "SOUL_FRAGMENTS" then
            local curve = CR.GetSoulFragmentsTextColorCurve(maximumValue)
            local color = curve and curve:Evaluate(minimumValue)
            if color then
                local textR, textG, textB, textA = color:GetRGBA()
                resource.Text:SetTextColor(textR, textG, textB, textA)
            else
                resource.Text:SetTextColor(1, 1, 1)
            end
        end
    end

    UpdateSoulFragmentsSpark(resource, minimumValue, maximumValue, isSecret)
end
