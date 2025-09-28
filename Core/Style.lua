local R, C, L = unpack(RefineUI)

----------------------------------------------------------------------------------------
-- Upvalues
----------------------------------------------------------------------------------------
local _G = _G
local CreateFrame, Mixin, unpack, pairs, gsub, strmatch = CreateFrame, Mixin, unpack, pairs, string.gsub, string.match
local strfind = string.find
local ipairs = ipairs
local max, abs = math.max, math.abs
local BackdropTemplateMixin = BackdropTemplateMixin

----------------------------------------------------------------------------------------
-- Local variables
----------------------------------------------------------------------------------------
R.dummy = R.dummy or function() end

-- Hoisted media/colors; refreshable via R.RefreshTheme()
local BORDER_FILE, EDGE_SIZE
local BR, BG, BB, BA
local DR, DG, DB, DA

function R.RefreshTheme()
    BORDER_FILE = C.media.border
    EDGE_SIZE = (C.media.edgeSize or 12)
    BR, BG, BB, BA = unpack(C.media.borderColor)
    DR, DG, DB, DA = unpack(C.media.backdropColor)
end

R.RefreshTheme()

----------------------------------------------------------------------------------------
-- Utility functions
----------------------------------------------------------------------------------------
-- (none)

----------------------------------------------------------------------------------------
-- Position functions
----------------------------------------------------------------------------------------
local function SetOutside(obj, anchor, xOffset, yOffset)
    xOffset, yOffset = xOffset or 2, yOffset or 2
    anchor = anchor or obj:GetParent()

    if obj.GetNumPoints and obj:GetNumPoints() > 0 then obj:ClearAllPoints() end
    obj:SetPoint("TOPLEFT", anchor, "TOPLEFT", -xOffset, yOffset)
    obj:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", xOffset, -yOffset)
end

local function SetInside(obj, anchor, xOffset, yOffset)
    xOffset, yOffset = xOffset or 2, yOffset or 2
    anchor = anchor or obj:GetParent()

    if obj.GetNumPoints and obj:GetNumPoints() > 0 then obj:ClearAllPoints() end
    obj:SetPoint("TOPLEFT", anchor, "TOPLEFT", xOffset, -yOffset)
    obj:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -xOffset, yOffset)
end

----------------------------------------------------------------------------------------
-- Font functions
----------------------------------------------------------------------------------------
local function FontString(parent, name, fontName, fontHeight, fontStyle)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(fontName, fontHeight, fontStyle)
    fs:SetJustifyH("LEFT")

    if name then
        parent[name] = fs
    else
        parent.text = fs
    end

    return fs
end

----------------------------------------------------------------------------------------
-- Template functions
----------------------------------------------------------------------------------------
local function CreateOverlay(f)
    if f.overlay then return end
    local overlay = f:CreateTexture("$parentOverlay", "BORDER")
    overlay:SetInside()
    overlay:SetTexture(C.media.blank)
    overlay:SetVertexColor(0.1, 0.1, 0.1, 1)
    f.overlay = overlay
end

-- Guard to avoid repeated BackdropTemplateMixin work
local function ensureBackdrop(f)
    if not f.__refine_has_backdrop then
        Mixin(f, BackdropTemplateMixin)
        f.__refine_has_backdrop = true
    end
end

local function CreateBorder(f, insetX, insetY)
		insetX = insetX or 6
		insetY = insetY or 6
		local edgeSize = (C.media and C.media.edgeSize) or 12
		local b = f.border
		if b and b.SetBackdrop then
			local needsAnchor = (b.__ix ~= insetX) or (b.__iy ~= insetY)
			local needsEdge = (b.__es ~= edgeSize)
			if needsAnchor then
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", f, "TOPLEFT", -insetX, insetY)
				b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", insetX, -insetY)
				b.__ix, b.__iy = insetX, insetY
			end
			if needsEdge or b.__edgeFile ~= BORDER_FILE then
				b:SetBackdrop({ edgeFile = BORDER_FILE, edgeSize = edgeSize })
				b.__es = edgeSize
				b.__edgeFile = BORDER_FILE
			end
			local want = max(0, f:GetFrameLevel() + 1)
			if b.GetFrameLevel and b:GetFrameLevel() ~= want then
				b:SetFrameLevel(want)
			end
			return b
		end

		b = CreateFrame("Frame", nil, f, "BackdropTemplate")
		b:SetPoint("TOPLEFT", f, "TOPLEFT", -insetX, insetY)
		b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", insetX, -insetY)
		b:SetBackdrop({ edgeFile = BORDER_FILE, edgeSize = edgeSize })
		b:SetBackdropBorderColor(BR, BG, BB, BA)
		b:SetFrameLevel(max(0, f:GetFrameLevel() + 1))
		b.__ix, b.__iy, b.__es = insetX, insetY, edgeSize
		b.__edgeFile = BORDER_FILE
		f.border = b
		return b
end

local function GetTemplateColors(t)
    return BR, BG, BB, BA, DR, DG, DB, DA
end

local function SetTemplate(f, t)
    ensureBackdrop(f)
    local br, bg, bb, ba, dr, dg, db, da = GetTemplateColors(t)

	-- Cache backdrop spec to avoid redundant SetBackdrop
	local wantBg = C.media.blank
	if f.__bgFile ~= wantBg then
		f:SetBackdrop({ bgFile = wantBg, insets = { left = 0, right = 0, top = 0, bottom = 0 } })
		f.__bgFile = wantBg
	end

    local alpha = da
    if t == "Anchor" then
        alpha = 0
    elseif t == "Icon" then
        alpha = 0
        if not f.border then CreateBorder(f, 5, 5) end
    elseif t == "Aura" then
        alpha = 1
        CreateBorder(f, 4, 4)
    elseif t == "Transparent" then
        alpha = C.media.backdropAlpha or 0.5
        CreateBorder(f, 4, 4)
    elseif t == "Zero" then
        alpha = 0
        CreateBorder(f, 4, 4)
    elseif t == "Overlay" then
        alpha = 1
        CreateBorder(f, 4, 4)
        CreateOverlay(f)
    else
        if not f.border then CreateBorder(f) end
    end

    f:SetBackdropColor(dr, dg, db, alpha)
    if f.border then
        -- re-tint border with current theme colors
        if not (f.border.__lr == br and f.border.__lg == bg and f.border.__lb == bb and f.border.__la == ba) then
            f.border:SetBackdropBorderColor(br, bg, bb, ba)
            f.border.__lr, f.border.__lg, f.border.__lb, f.border.__la = br, bg, bb, ba
        end
    end
end

local function CreatePanel(f, t, w, h, a1, p, a2, x, y)
    ensureBackdrop(f)

    local br, bg, bb, ba, dr, dg, db, da = GetTemplateColors(t)

    f:SetSize(w, h)
    f:SetFrameLevel(3)
    f:SetFrameStrata("BACKGROUND")
    f:SetPoint(a1, p, a2, x, y)
	if f.__bgFile ~= C.media.blank then
		f:SetBackdrop({ bgFile = C.media.blank })
		f.__bgFile = C.media.blank
	end

	if not f.border then f.border = CreateFrame("Frame", nil, f, "BackdropTemplate") end
    f.border:SetPoint("TOPLEFT", f, "TOPLEFT", -4, 4)
    f.border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 4, -4)
    local edgeSize = (C.media and C.media.edgeSize) or 12
    f.border:SetBackdrop({ edgeFile = C.media.border, edgeSize = edgeSize })

    local alpha = da
    local borderAlpha = ba
    if t == "Transparent" then
        alpha = C.media.backdropAlpha or 0.5
    elseif t == "Overlay" then
        alpha = 1
        CreateOverlay(f)
    elseif t == "Invisible" then
        alpha, borderAlpha = 0, 0
    end

    f:SetBackdropColor(dr, dg, db, alpha)
    f.border:SetBackdropBorderColor(br, bg, bb, borderAlpha)
end

local function CreateBackdrop(f, t)
    if f.backdrop then return end
    t = t or "Default"

    local b = CreateFrame("Frame", "$parentBackdrop", f)
    b:SetOutside()
    b:SetTemplate(t)

    b:SetFrameLevel(max(0, f:GetFrameLevel() - 1))

    f.backdrop = b
end

----------------------------------------------------------------------------------------
-- StripTextures function
----------------------------------------------------------------------------------------
local StripTexturesBlizzFrames = {
    "Inset", "inset", "InsetFrame", "LeftInset", "RightInset", "NineSlice", "BG", "Bg", "border", "Border",
    "BorderFrame", "bottomInset", "BottomInset", "bgLeft", "bgRight", "FilligreeOverlay", "PortraitOverlay",
    "ArtOverlayFrame", "Portrait", "portrait", "ScrollFrameBorder",
}

local function StripTextures(object, kill)
    if not object or object.__refine_stripped or not object.GetNumRegions then return end
    object.__refine_stripped = true

    local num = object:GetNumRegions()
    if num and num > 0 then
        local i = 1
        while i <= num do
            local region = select(i, object:GetRegions())
            if region and region.IsObjectType and region:IsObjectType("Texture") then
                if kill and region.Kill then
                    region:Kill()
                else
                    if region.SetTexture then region:SetTexture("") end
                    if region.SetAtlas then region:SetAtlas("") end
                end
            end
            i = i + 1
        end
    end

    local frameName = object.GetName and object:GetName()
    for _, key in pairs(StripTexturesBlizzFrames) do
        local sub = object[key] or (frameName and _G[frameName .. key])
        if sub and sub ~= object then
            StripTextures(sub, kill)
        end
    end
end

----------------------------------------------------------------------------------------
-- Kill object function
----------------------------------------------------------------------------------------
local HiddenFrame = CreateFrame("Frame")
HiddenFrame:Hide()
R.Hider = HiddenFrame

local function Kill(object)
    if object.UnregisterAllEvents then
        object:UnregisterAllEvents()
        object:SetParent(HiddenFrame)
    else
        object.Show = R.dummy
    end
    object:Hide()
end

----------------------------------------------------------------------------------------
-- Style functions
----------------------------------------------------------------------------------------
local function StyleButton(button, skipPushed, size, setBackdrop)
    size = size or 2
    if button.SetHighlightTexture and not button.hover then
        local hover = button:CreateTexture()
        hover:SetColorTexture(1, 1, 1, 0.3)
        hover:SetPoint("TOPLEFT", button, size, -size)
        hover:SetPoint("BOTTOMRIGHT", button, -size, size)
        button.hover = hover
        button:SetHighlightTexture(hover)
    end

    if not skipPushed and button.SetPushedTexture and not button.pushed then
        local pushed = button:CreateTexture()
        pushed:SetColorTexture(0.9, 0.8, 0.1, 0.3)
        pushed:SetPoint("TOPLEFT", button, size, -size)
        pushed:SetPoint("BOTTOMRIGHT", button, -size, size)
        button.pushed = pushed
        button:SetPushedTexture(pushed)
    end

    if button.SetCheckedTexture and not button.checked then
        local checked = button:CreateTexture()
        checked:SetColorTexture(0, 1, 0, 0.3)
        checked:SetPoint("TOPLEFT", button, size, -size)
        checked:SetPoint("BOTTOMRIGHT", button, -size, size)
        button.checked = checked
        button:SetCheckedTexture(checked)
    end

    local cooldown = button:GetName() and _G[button:GetName() .. "Cooldown"]
    if cooldown then
        cooldown:ClearAllPoints()
        cooldown:SetPoint("TOPLEFT", button, size, -size)
        cooldown:SetPoint("BOTTOMRIGHT", button, -size, size)
    end
end

local function SetModifiedBackdrop(self)
    if self:IsEnabled() then
		local br, bg, bb, ba = unpack(C.media.borderColor)
		self:SetBackdropBorderColor(br, bg, bb, ba)
        if self.overlay then
            self.overlay:SetVertexColor(C.media.borderColor[1] * 0.3, C.media.borderColor[2] * 0.3,
                C.media.borderColor[3] * 0.3, 1)
        end
    end
end

local function SetOriginalBackdrop(self)
	local br, bg, bb, ba = unpack(C.media.borderColor)
	self:SetBackdropBorderColor(br, bg, bb, ba)
    if self.overlay then
        self.overlay:SetVertexColor(0.1, 0.1, 0.1, 1)
    end
end

local function SkinButton(f, strip)
    if f.__refine_skinned then return end
    f.__refine_skinned = true
    if strip then f:StripTextures() end

    f:SetNormalTexture(0)
    f:SetHighlightTexture(0)
    f:SetPushedTexture(0)
    f:SetDisabledTexture(0)

    if f.Left then f.Left:SetAlpha(0) end
    if f.Right then f.Right:SetAlpha(0) end
    if f.Middle then f.Middle:SetAlpha(0) end
    if f.LeftSeparator then f.LeftSeparator:SetAlpha(0) end
    if f.RightSeparator then f.RightSeparator:SetAlpha(0) end
    if f.Flash then f.Flash:SetAlpha(0) end

    if f.TopLeft then f.TopLeft:Hide() end
    if f.TopRight then f.TopRight:Hide() end
    if f.BottomLeft then f.BottomLeft:Hide() end
    if f.BottomRight then f.BottomRight:Hide() end
    if f.TopMiddle then f.TopMiddle:Hide() end
    if f.MiddleLeft then f.MiddleLeft:Hide() end
    if f.MiddleRight then f.MiddleRight:Hide() end
    if f.BottomMiddle then f.BottomMiddle:Hide() end
    if f.MiddleMiddle then f.MiddleMiddle:Hide() end

    f:SetTemplate("Overlay")
    f:HookScript("OnEnter", SetModifiedBackdrop)
    f:HookScript("OnLeave", SetOriginalBackdrop)
end

-- Minimal, safe scrollbar skinner to avoid undefined global and provide consistent look
local function SkinScrollBar(scrollBar)
    if not scrollBar or type(scrollBar) ~= "table" then return end

    -- Hide default track pieces if present
    if scrollBar.Back and scrollBar.Back.SetAlpha then
        scrollBar.Back:SetAlpha(0)
    end
    if scrollBar.Track and scrollBar.Track.SetAlpha then
        scrollBar.Track:SetAlpha(0)
    end

    -- Style thumb texture
    local thumb = scrollBar.Thumb or (scrollBar.GetThumbTexture and scrollBar:GetThumbTexture())
    if thumb then
        if thumb.SetTexture then thumb:SetTexture(C.media.blank) end
        if thumb.SetVertexColor then thumb:SetVertexColor(unpack(C.media.borderColor)) end
    end

    -- Give the scrollbar a border/backdrop if supported via our API
    if scrollBar.SetTemplate then
        scrollBar:SetTemplate("Overlay")
    end
end

local function SkinIcon(icon, t, parent)
    if not icon or not icon.SetTexCoord then return end
    parent = parent or icon:GetParent()

    if t then
        if not icon.b then
            icon.b = CreateFrame("Frame", nil, parent)
            icon.b:SetTemplate("Default")
            icon.b:SetOutside(icon)
        end
    else
        if not parent.backdrop then parent:CreateBackdrop("Default") end
        parent.backdrop:SetOutside(icon)
    end

    icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    icon:SetParent(t and icon.b or parent)
end

local function CropIcon(icon)
    icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    icon:SetInside()
end

----------------------------------------------------------------------------------------
-- More style functions
----------------------------------------------------------------------------------------
function R.SkinTab(tab, bg)
    if not tab then return end

    for _, object in pairs({ "LeftDisabled", "MiddleDisabled", "RightDisabled", "Left", "Middle", "Right" }) do
        local tex = tab:GetName() and _G[tab:GetName() .. object]
        if tex then
            tex:SetTexture(nil)
        end
    end

    if tab.GetHighlightTexture and tab:GetHighlightTexture() then
        tab:GetHighlightTexture():SetTexture(nil)
    else
        tab:StripTextures()
    end

    tab.backdrop = CreateFrame("Frame", nil, tab)
    tab.backdrop:SetFrameLevel(max(0, tab:GetFrameLevel() - 1))
    if bg then
        tab.backdrop:SetTemplate("Overlay")
        tab.backdrop:SetPoint("TOPLEFT", 2, -9)
        tab.backdrop:SetPoint("BOTTOMRIGHT", -2, -2)
    else
        tab.backdrop:SetTemplate("Transparent")
        tab.backdrop:SetPoint("TOPLEFT", 0, -3)
        tab.backdrop:SetPoint("BOTTOMRIGHT", 0, 3)
    end
end

function R.SkinNextPrevButton(btn, left, scroll)
    local normal, pushed, disabled
    local frameName = btn.GetName and btn:GetName()
    local isPrevButton = frameName and
        (string.find(frameName, "Left") or string.find(frameName, "Prev") or string.find(frameName, "Decrement") or string.find(frameName, "Back")) or
        left
    local isScrollUpButton = frameName and string.find(frameName, "ScrollUp") or scroll == "Up"
    local isScrollDownButton = frameName and string.find(frameName, "ScrollDown") or scroll == "Down"

    btn:StripTextures()

    if scroll == "Up" or scroll == "Down" or scroll == "Any" then
        normal = nil
        pushed = nil
        disabled = nil
    end

    if not normal then
        if isPrevButton then
            normal = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up"
        elseif isScrollUpButton then
            normal = "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up"
        elseif isScrollDownButton then
            normal = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up"
        else
            normal = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up"
        end
    end

    -- Compute derived textures first, then set
    if normal and not pushed then pushed = normal:gsub("%-Up$", "-Down") end
    if normal and not disabled then disabled = normal:gsub("%-Up$", "-Disabled") end
    btn:SetNormalTexture(normal)
    if pushed then btn:SetPushedTexture(pushed) end
    if disabled then btn:SetDisabledTexture(disabled) end

    btn:SetTemplate("Overlay")
    local w, h = btn:GetWidth(), btn:GetHeight()
    btn:SetSize(max(1, w - 7), max(1, h - 7))

    -- Auto-derive pushed/disabled from normal if available so texcoords apply consistently
    if normal and not pushed then pushed = normal:gsub("%-Up$", "-Down") end
    if normal and not disabled then disabled = normal:gsub("%-Up$", "-Disabled") end

    if normal and pushed and disabled then
        btn:GetNormalTexture():SetTexCoord(0.3, 0.29, 0.3, 0.81, 0.65, 0.29, 0.65, 0.81)
        if btn:GetPushedTexture() then
            btn:GetPushedTexture():SetTexCoord(0.3, 0.35, 0.3, 0.81, 0.65, 0.35, 0.65, 0.81)
        end
        if btn:GetDisabledTexture() then
            btn:GetDisabledTexture():SetTexCoord(0.3, 0.29, 0.3, 0.75, 0.65, 0.29, 0.65, 0.75)
        end

        btn:GetNormalTexture():ClearAllPoints()
        btn:GetNormalTexture():SetPoint("TOPLEFT", 2, -2)
        btn:GetNormalTexture():SetPoint("BOTTOMRIGHT", -2, 2)
        if btn:GetDisabledTexture() then
            btn:GetDisabledTexture():SetAllPoints(btn:GetNormalTexture())
        end
        if btn:GetPushedTexture() then
            btn:GetPushedTexture():SetAllPoints(btn:GetNormalTexture())
        end
        if btn:GetHighlightTexture() then
            btn:GetHighlightTexture():SetColorTexture(1, 1, 1, 0.3)
            btn:GetHighlightTexture():SetAllPoints(btn:GetNormalTexture())
        end
    end
end

----------------------------------------------------------------------------------------
-- Add API to objects
----------------------------------------------------------------------------------------
local function addAPI(object)
    if not object then return end
    local mt = getmetatable(object)
    mt = mt and mt.__index
    if type(mt) ~= "table" then return end
    local inject = {
        SetOutside = SetOutside,
        SetInside = SetInside,
        CreateOverlay = CreateOverlay,
        CreateBorder = CreateBorder,
        SetTemplate = SetTemplate,
        FontString = FontString,
        CreatePanel = CreatePanel,
        CreateBackdrop = CreateBackdrop,
        StripTextures = StripTextures,
        Kill = Kill,
        StyleButton = StyleButton,
        SkinButton = SkinButton,
        SkinIcon = SkinIcon,
        CropIcon = CropIcon,
        SkinTab = R.SkinTab,
        FadeIn = R.FadeIn,
        FadeOut = R.FadeOut,
    }
    for k, func in pairs(inject) do
        if mt[k] == nil then mt[k] = func end
    end
end

-- Avoid leaking globals; expose helpers on R only

----------------------------------------------------------------------------------------
-- Apply API to core widget types once (avoids EnumerateFrames taint/perf)
if not R.__apiAugmented then
    local parent = R.Hider or CreateFrame("Frame")
    parent:Hide()
    local base = CreateFrame("Frame", nil, parent)
    addAPI(base)
    addAPI(base:CreateTexture())
    addAPI(base:CreateFontString())

    local widgetTypes = {
        "Button",
        "StatusBar",
        "CheckButton",
        "Slider",
        "EditBox",
        "ScrollFrame",
    }
    for _, wt in ipairs(widgetTypes) do
        local ok, obj = pcall(CreateFrame, wt, nil, parent)
        if ok and obj then
            addAPI(obj)
            if wt == "EditBox" then
                if obj.SetAutoFocus then obj:SetAutoFocus(false) end
                if obj.ClearFocus then obj:ClearFocus() end
            end
            if obj.Hide then obj:Hide() end
        end
    end

    R.__apiAugmented = true
end

----------------------------------------------------------------------------------------
-- Skin functions
----------------------------------------------------------------------------------------
R.SkinFuncs = R.SkinFuncs or {}
R.SkinFuncs["RefineUI"] = R.SkinFuncs["RefineUI"] or {}
R.SkinScrollBar = SkinScrollBar
R.FontString = FontString

-- Thin border helper matching Nameplates' existing visuals (no style change)
function R.CreateThinBorder(frame, insetX, insetY, edgeSize, frameLevelAdjust)
    if not frame then return end
    if frame.border and frame.border.GetObjectType and frame.border:GetObjectType() == "Frame" then
        return frame.border
    end

    insetX = insetX or 3
    insetY = insetY or 3
    edgeSize = edgeSize or 7
    local lvlAdjust = frameLevelAdjust or 1

    local b = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    b:SetPoint("TOPLEFT", frame, "TOPLEFT", -insetX, insetY)
    b:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", insetX, -insetY)
    b:SetBackdrop({ edgeFile = C.media.border, edgeSize = edgeSize })
    b:SetBackdropBorderColor(unpack(C.media.borderColor))
    b:SetFrameLevel(frame:GetFrameLevel() + lvlAdjust)
    frame.border = b
    return b
end
local function _safe_call(func)
    return xpcall(func, function(err)
        local msg = "|cffff5555RefineUI skin error:|r "..tostring(err)
        if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(msg) else print(msg) end
    end)
end

local function LoadBlizzardSkin(_, event, addon)
    if event == "ADDON_LOADED" then
        local bucket = R.SkinFuncs[addon]
        if bucket then
            if type(bucket) == "function" then
                _safe_call(bucket)
            else
                for _, func in pairs(bucket) do _safe_call(func) end
            end
            R.SkinFuncs[addon] = nil
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        for _addon, bucket in pairs(R.SkinFuncs) do
            if C_AddOns.IsAddOnLoaded(_addon) then
                if type(bucket) == "function" then
                    _safe_call(bucket)
                else
                    for _, func in pairs(bucket) do _safe_call(func) end
                end
                R.SkinFuncs[_addon] = nil
            end
        end
        R.SkinFuncs["RefineUI"] = nil
    end
end

local BlizzardSkinLoader = CreateFrame("Frame")
BlizzardSkinLoader:RegisterEvent("ADDON_LOADED")
BlizzardSkinLoader:RegisterEvent("PLAYER_ENTERING_WORLD")
BlizzardSkinLoader:SetScript("OnEvent", LoadBlizzardSkin)

----------------------------------------------------------------------------------------
-- Additional utility functions
----------------------------------------------------------------------------------------
function R.ReplaceIconString(frame, text)
    if not text then text = frame:GetText() end
    if not text or text == "" then return end

    if frame.__refine_lastIconString == text then return end
    local newText, count = gsub(text, "|T([^:]-):[%d+:]+|t", "|T%1:14:14:0:0:64:64:5:59:5:59|t")
    if count > 0 then
        frame:SetText(newText)
        frame.__refine_lastIconString = newText
    else
        frame.__refine_lastIconString = text
    end
end

----------------------------------------------------------------------------------------
-- Icon border coloring
----------------------------------------------------------------------------------------
local EPS = 1e-4
local iconColors = (function()
    local br, bg, bb = unpack(C.media.borderColor)
    return {
        ["uncollected"] = { r = br, g = bg, b = bb },
        ["gray"]        = { r = br, g = bg, b = bb },
        ["white"]       = { r = br, g = bg, b = bb },
        ["green"]       = BAG_ITEM_QUALITY_COLORS[2],
        ["blue"]        = BAG_ITEM_QUALITY_COLORS[3],
        ["purple"]      = BAG_ITEM_QUALITY_COLORS[4],
        ["orange"]      = BAG_ITEM_QUALITY_COLORS[5],
        ["artifact"]    = BAG_ITEM_QUALITY_COLORS[6],
        ["account"]     = BAG_ITEM_QUALITY_COLORS[7]
    }
end)()

local ATLAS_COLOR_CACHE = {}

local function _setBorderColorCached(border, r, g, b, a)
    if not (border.__lr and abs(border.__lr - r) <= EPS) or
       not (border.__lg and abs(border.__lg - g) <= EPS) or
       not (border.__lb and abs(border.__lb - b) <= EPS) or
       not (border.__la and abs(border.__la - a) <= EPS) then
        border:SetBackdropBorderColor(r, g, b, a)
        border.__lr, border.__lg, border.__lb, border.__la = r, g, b, a
    end
end

function R.SkinIconBorder(frame, parent)
    if frame.__refine_skinIconBorder or frame.__refine_hooked then return end
    frame.__refine_skinIconBorder = true
    frame.__refine_hooked = true

    local p = parent or frame:GetParent()
    local border = p and (p.backdrop or p.border)
    if not border or not border.SetBackdropBorderColor then return end
    if frame.GetAlpha and (frame:GetAlpha() or 1) > 0.001 then frame:SetAlpha(0) end
    local dr, dg, db, da = unpack(C.media.borderColor)
    hooksecurefunc(frame, "SetVertexColor", function(_, r, g, b)
        local q = BAG_ITEM_QUALITY_COLORS[1]
        if r ~= q.r or g ~= q.g or b ~= q.b then
            _setBorderColorCached(border, r, g, b, 1)
        else
            _setBorderColorCached(border, dr, dg, db, da)
        end
    end)

    hooksecurefunc(frame, "SetAtlas", function(_, atlas)
        if frame.__refine_lastAtlas == atlas then return end
        frame.__refine_lastAtlas = atlas
        local c = atlas and ATLAS_COLOR_CACHE[atlas]
        if c == nil and atlas then
            local atlasAbbr = strmatch(atlas, "%-(%w+)$")
            c = atlasAbbr and iconColors[atlasAbbr]
            ATLAS_COLOR_CACHE[atlas] = c or false
        end
        if c then _setBorderColorCached(border, c.r, c.g, c.b, 1) end
    end)

    hooksecurefunc(frame, "Hide", function()
        _setBorderColorCached(border, dr, dg, db, da)
    end)

    hooksecurefunc(frame, "SetShown", function(_, show)
        if not show then _setBorderColorCached(border, dr, dg, db, da) end
    end)
end

----------------------------------------------------------------------------------------
-- Pet Battle Hider
----------------------------------------------------------------------------------------
R_PetBattleFrameHider = CreateFrame("Frame", "RefineUI_PetBattleFrameHider", UIParent, "SecureHandlerStateTemplate")
R_PetBattleFrameHider:SetAllPoints(UIParent)
R_PetBattleFrameHider:SetFrameStrata("LOW")
RegisterStateDriver(R_PetBattleFrameHider, "visibility", "[petbattle] hide; show")

return R
