local R, C, L = unpack(RefineUI)

-- Localize frequently used globals for performance and clarity
local floor = math.floor
local min, max = math.min, math.max
local format = string.format
local tonumber = tonumber
-- Do not localize UIParent directly as `local UIParent = UIParent` would resolve to nil in Lua.
local _G = _G
local UIParentRef = _G.UIParent

----------------------------------------------------------------------------------------
--	PIXEL PERFECT
----------------------------------------------------------------------------------------
local function round(x)
    return floor(x + 0.5)
end

local function calculateUIScale(screenHeight)
    local baseScale = 768 / screenHeight
    local uiScale = baseScale

    -- Apply multipliers for very tall screens, then clamp to sane bounds
    if screenHeight >= 2400 then
        uiScale = uiScale * 3
    elseif screenHeight >= 1600 then
        uiScale = uiScale * 2
    end

    uiScale = min(2, max(0.20, uiScale))

    return tonumber(format("%.5f", uiScale))
end

-- Main scaling logic
R.low_resolution = R.screenWidth <= 1440

if C.general.autoScale then
    C.general.uiScale = calculateUIScale(R.screenHeight)
end

R.mult = 768 / R.screenHeight / C.general.uiScale
R.noscalemult = R.mult * C.general.uiScale

R.Scale = function(x)
    local m = R.mult
    if m == 0 then return 0 end
    return m * floor(x / m + 0.5)
end

-- Optional font scaling (opt-in via C.general.scaleFonts and C.general.fontScaleFactor)
do
    if C.general and C.general.scaleFonts and not R.__fontsScaled then
        local factor = tonumber(C.general.fontScaleFactor) or 1
        if factor ~= 1 and C.font then
            local function scaleFonts(node)
                if type(node) ~= "table" then return end
                -- Font triplets look like { fontPath, size, style }
                if type(node[1]) == "string" and type(node[2]) == "number" then
                    node[2] = math.max(1, round(node[2] * factor))
                    return
                end
                for _, v in pairs(node) do
                    scaleFonts(v)
                end
            end

            scaleFonts(C.font)

            -- Scale numeric size fields (e.g., tooltip_size)
            for k, v in pairs(C.font) do
                if type(v) == "number" and type(k) == "string" and k:lower():find("size") then
                    C.font[k] = math.max(1, round(v * factor))
                end
            end
        end
        R.__fontsScaled = true
    end
end

----------------------------------------------------------------------------------------
--	PIXEL PERFECT FUNCTIONS
----------------------------------------------------------------------------------------
function R.PixelPerfect(x)
    local scale = UIParentRef:GetEffectiveScale()
    return floor(x / scale + 0.5) * scale
end

function R.PixelSnap(frame)
    if not frame or not frame.GetPoint then return end

    local getNumPoints = frame.GetNumPoints
    local numPoints = getNumPoints and getNumPoints(frame) or 0
    if numPoints == 0 then return end -- No anchors set

    local scale = (frame.GetEffectiveScale and frame:GetEffectiveScale()) or 1

    -- Collect adjusted anchors first to preserve original set
    local anchors = {}
    for i = 1, numPoints do
        local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint(i)
        if point then
            local parentScale = (relativeTo and relativeTo.GetEffectiveScale and relativeTo:GetEffectiveScale()) or scale
            xOfs = xOfs or 0
            yOfs = yOfs or 0

            xOfs = R.PixelPerfect((xOfs * scale) / parentScale) / scale
            yOfs = R.PixelPerfect((yOfs * scale) / parentScale) / scale

            anchors[#anchors + 1] = { point, relativeTo, relativePoint, xOfs, yOfs }
        end
    end

    if #anchors == 0 then return end

    frame:ClearAllPoints()
    for i = 1, #anchors do
        frame:SetPoint(anchors[i][1], anchors[i][2], anchors[i][3], anchors[i][4], anchors[i][5])
    end
end

function R.SetPixelSize(frame, width, height)
    local scale = frame:GetEffectiveScale()
    width = width and R.PixelPerfect(width * scale) / scale or frame:GetWidth()
    height = height and R.PixelPerfect(height * scale) / scale or frame:GetHeight()
    frame:SetSize(width, height)
end

function R.SetPixelBackdrop(frame, edgeSize)
    if not frame or not frame.SetBackdrop then return end -- Ensure BackdropTemplate was used at creation
    local scale = frame:GetEffectiveScale()
    edgeSize = floor(edgeSize * scale + 0.5) / scale

    frame:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = edgeSize,
    })
end

function R.CreatePixelLine(parent, orientation, thickness, r, g, b, a)
    local line = parent:CreateTexture(nil, "OVERLAY")

    local horizontal = orientation == "HORIZONTAL"
    local parentLength = horizontal and parent:GetWidth() or parent:GetHeight()
    local w = horizontal and (parentLength > 0 and parentLength or thickness) or thickness
    local h = horizontal and thickness or (parentLength > 0 and parentLength or thickness)

    R.SetPixelSize(line, w, h)
    line:SetColorTexture(r, g, b, a)

    -- If parent size isn't known yet, adjust once it is
    if parentLength == 0 and parent.HookScript then
        parent:HookScript("OnSizeChanged", function(p)
            if not line or not line.SetSize then return end
            local len = horizontal and p:GetWidth() or p:GetHeight()
            if len and len > 0 then
                if horizontal then
                    R.SetPixelSize(line, len, thickness)
                else
                    R.SetPixelSize(line, thickness, len)
                end
            end
        end)
    end

    return line
end
