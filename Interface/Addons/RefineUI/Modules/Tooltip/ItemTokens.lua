local _, RefineUI = ...
local Tooltip = RefineUI:GetModule("Tooltip")
local classLabels = {}
local CHECK = "|A:UI-QuestTracker-Tracker-Check:14:14|a "
local MISSING = "|A:UI-QuestTracker-Objective-Fail:14:14|a "
local COLLECTED_STATUS = CHECK .. COLLECTED
local UNCOLLECTED_STATUS = MISSING .. "Uncollected"

function Tooltip:InitializeItemTokens()
    self:RegisterItemHandler(function(tooltip, data)
        local itemID = self:ReadSafeNumber(data.id)
        if not itemID or not RefineUI.TokenAppearanceData[itemID]
            or not self:IsAugmentableTooltipFrame(tooltip) then return end
        local _, link = tooltip:GetItem()
        link = self:ReadSafeString(link)
        local _, _, rows = RefineUI:GetTokenAppearanceStatus(link, itemID)
        if not rows then return end
        tooltip:AddLine(" ")
        local statusWidth
        local maxTotal = 1
        for i = 1, #rows do
            maxTotal = math.max(maxTotal, rows[i].total)
        end
        local widthSuffix = maxTotal > 1 and (" (" .. maxTotal .. "/" .. maxTotal .. ")") or ""
        for i = 1, #rows do
            local row = rows[i]
            local label = classLabels[row.classID]
            if not label then
                local name, class = GetClassInfo(row.classID)
                local color = RAID_CLASS_COLORS[class]
                label = color and color:WrapTextInColorCode(name) or name
                classLabels[row.classID] = label
            end
            local complete = row.collected == row.total
            local status
            if not row.ready then
                status = RETRIEVING_DATA
            elseif complete then
                status = COLLECTED_STATUS
            else
                status = UNCOLLECTED_STATUS
            end
            if row.ready and row.total > 1 then
                status = status .. " (" .. row.collected .. "/" .. row.total .. ")"
            end
            tooltip:AddDoubleLine(label, status, 1, 1, 1,
                complete and 0.2 or 1, complete and 1 or 0.3, 0.2)
            local lineIndex = self:ReadSafeNumber(tooltip:NumLines())
            local rightLine = lineIndex and tooltip:GetRightLine(lineIndex)
            if rightLine and row.ready then
                -- Measure using this tooltip's font, once per render. Both statuses
                -- reserve the same width, even when every class has the same status.
                if statusWidth == nil then
                    rightLine:SetText(COLLECTED_STATUS .. widthSuffix)
                    local collectedWidth = self:ReadSafeNumber(rightLine:GetStringWidth())
                    rightLine:SetText(UNCOLLECTED_STATUS .. widthSuffix)
                    local uncollectedWidth = self:ReadSafeNumber(rightLine:GetStringWidth())
                    rightLine:SetText(status)
                    -- Tooltip geometry can be secret even for our own text.
                    -- Leave native sizing in place when measurements are restricted.
                    statusWidth = collectedWidth and uncollectedWidth
                        and math.ceil(math.max(collectedWidth, uncollectedWidth)) or false
                end
                if statusWidth then
                    rightLine:SetWidth(statusWidth)
                    rightLine:SetJustifyH("RIGHT")
                end
            end
        end
    end)
end
