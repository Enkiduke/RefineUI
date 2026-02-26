----------------------------------------------------------------------------------------
-- RefineUI Style API
-- Description: Provides mixins for borders, templates, and consistent styling.
----------------------------------------------------------------------------------------

local _, RefineUI = ...

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local _G = _G
local select = select
local unpack = unpack
local type = type
local pairs = pairs
local ipairs = ipairs
local max = math.max
local issecretvalue = issecretvalue
local canaccessvalue = canaccessvalue

-- External Style State Registry (Weak Keys)
local STYLE_STATE_REGISTRY = "CoreStyleState"
local StyleState = RefineUI:CreateDataRegistry(STYLE_STATE_REGISTRY, "k")

-- Forward Declarations
local AddAPI

----------------------------------------------------------------------------------------
-- WoW Globals
----------------------------------------------------------------------------------------
local CreateFrame = CreateFrame

----------------------------------------------------------------------------------------
-- Theme Caching (Performance + Refresh Support)
----------------------------------------------------------------------------------------
local BORDER_FILE, EDGE_SIZE
local BR, BG, BB, BA  -- Border color
local DR, DG, DB, DA  -- Backdrop color

local function RefreshTheme()
    local textures = RefineUI.Media and RefineUI.Media.Textures
    BORDER_FILE = (textures and (textures.RefineBorder or textures.Border)) or [[Interface\AddOns\RefineUI\Media\Textures\RefineBorder.blp]]
    EDGE_SIZE = 12
    
    if RefineUI.Config and RefineUI.Config.General and RefineUI.Config.General.BorderColor then
        local color = RefineUI.Config.General.BorderColor
        BR, BG, BB = color[1], color[2], color[3]
        BA = color[4] or 1
    else
        BR, BG, BB, BA = 0.3, 0.3, 0.3, 1
    end
    
    DR, DG, DB, DA = 0.1, 0.1, 0.1, 0.8  -- Default backdrop
end

-- Initial theme load
RefreshTheme()

-- Expose for runtime refresh
RefineUI.RefreshTheme = RefreshTheme

----------------------------------------------------------------------------------------
-- Hidden Frame
----------------------------------------------------------------------------------------
RefineUI.HiddenFrame = CreateFrame("Frame")
RefineUI.HiddenFrame:Hide()

----------------------------------------------------------------------------------------
-- Kill: Hide and Disable
----------------------------------------------------------------------------------------
local function Kill(self)
    if not self then return end
    if issecretvalue and issecretvalue(self) then return end
    if canaccessvalue and not canaccessvalue(self) then return end

    if self.UnregisterAllEvents then
        self:UnregisterAllEvents()
        if not self:IsProtected() then
            self:SetParent(RefineUI.HiddenFrame)
        end
    else
        self.Show = self.Hide
    end
    
    if not self:IsProtected() then
        self:Hide()
    end
end

local function CanAccessObject(value)
    if value == nil then return false end
    if issecretvalue and issecretvalue(value) then return false end
    if canaccessvalue and not canaccessvalue(value) then return false end
    return true
end

local function CanCreateBorderPieces(frame)
    return CanAccessObject(frame)
        and type(frame.CreateTexture) == "function"
        and type(frame.HookScript) == "function"
end

local function IsManagedRefineBorder(borderFrame, owner)
    if not CanCreateBorderPieces(borderFrame) then
        return false
    end

    if borderFrame._refineBorderOwner and borderFrame._refineBorderOwner == owner then
        return true
    end

    if borderFrame._refineBorderPieces or borderFrame._refineBorderTexture then
        return true
    end

    return false
end

local function ResolveManagedRefineBorder(owner)
    if not CanAccessObject(owner) then
        return nil
    end

    local refineBorder = owner.RefineBorder
    if IsManagedRefineBorder(refineBorder, owner) then
        return refineBorder
    end

    local legacyBorder = owner.border
    if legacyBorder ~= refineBorder and IsManagedRefineBorder(legacyBorder, owner) then
        return legacyBorder
    end

    return nil
end

local function EnsureBorderCompatMethods(borderFrame)
    if not CanAccessObject(borderFrame) then
        return
    end

    if borderFrame._refineBorderCompatMethods then
        return
    end

    borderFrame._refineBorderCompatMethods = true

    borderFrame.SetBackdrop = function() end
    borderFrame.SetBackdropColor = function() end
    borderFrame.GetBackdropColor = function() return 0, 0, 0, 0 end
    borderFrame.SetBackdropBorderColor = function(self, r, g, b, a)
        if not CanAccessObject(self) then
            return
        end

        local pr, pg, pb, pa = r or 1, g or 1, b or 1, a or 1
        local pieces = self._refineBorderPieces
        if pieces then
            for i = 1, #pieces do
                local tex = pieces[i]
                if CanAccessObject(tex) and tex.SetVertexColor then
                    tex:SetVertexColor(pr, pg, pb, pa)
                end
            end
            return
        end

        local tex = self._refineBorderTexture
        if CanAccessObject(tex) and tex.SetVertexColor then
            tex:SetVertexColor(pr, pg, pb, pa)
        end
    end
    borderFrame.GetBackdropBorderColor = function(self)
        if not CanAccessObject(self) then
            return 1, 1, 1, 1
        end

        local pieces = self._refineBorderPieces
        if pieces and CanAccessObject(pieces[1]) and pieces[1].GetVertexColor then
            return pieces[1]:GetVertexColor()
        end

        local tex = self._refineBorderTexture
        if CanAccessObject(tex) and tex.GetVertexColor then
            return tex:GetVertexColor()
        end
        return 1, 1, 1, 1
    end
end

local function EnsureBackdropCompatMethods(texture)
    if not CanAccessObject(texture) then
        return
    end

    if texture._refineBackdropCompatMethods then
        return
    end

    texture._refineBackdropCompatMethods = true
    texture.SetBackdrop = function() end
    texture.SetBackdropBorderColor = function() end
    texture.GetBackdropBorderColor = function() return 1, 1, 1, 1 end
    texture.SetBackdropColor = function(self, r, g, b, a)
        self:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
    end
    texture.GetBackdropColor = function(self)
        return self:GetVertexColor()
    end
end

local BORDER_COORD_START = 0.0625
local BORDER_PIECE_ORDER = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge",
}
local BORDER_TEXTURE_UVS = {
    TopLeftCorner = { ULx = 0.5078125, ULy = BORDER_COORD_START, LLx = 0.5078125, LLy = 0.9375, URx = 0.6171875, URy = BORDER_COORD_START, LRx = 0.6171875, LRy = 0.9375 },
    TopRightCorner = { ULx = 0.6328125, ULy = BORDER_COORD_START, LLx = 0.6328125, LLy = 0.9375, URx = 0.7421875, URy = BORDER_COORD_START, LRx = 0.7421875, LRy = 0.9375 },
    BottomLeftCorner = { ULx = 0.7578125, ULy = BORDER_COORD_START, LLx = 0.7578125, LLy = 0.9375, URx = 0.8671875, URy = BORDER_COORD_START, LRx = 0.8671875, LRy = 0.9375 },
    BottomRightCorner = { ULx = 0.8828125, ULy = BORDER_COORD_START, LLx = 0.8828125, LLy = 0.9375, URx = 0.9921875, URy = BORDER_COORD_START, LRx = 0.9921875, LRy = 0.9375 },
    TopEdge = { ULx = 0.2578125, ULy = "repeatX", LLx = 0.3671875, LLy = "repeatX", URx = 0.2578125, URy = BORDER_COORD_START, LRx = 0.3671875, LRy = BORDER_COORD_START },
    BottomEdge = { ULx = 0.3828125, ULy = "repeatX", LLx = 0.4921875, LLy = "repeatX", URx = 0.3828125, URy = BORDER_COORD_START, LRx = 0.4921875, LRy = BORDER_COORD_START },
    LeftEdge = { ULx = 0.0078125, ULy = BORDER_COORD_START, LLx = 0.0078125, LLy = "repeatY", URx = 0.1171875, URy = BORDER_COORD_START, LRx = 0.1171875, LRy = "repeatY" },
    RightEdge = { ULx = 0.1328125, ULy = BORDER_COORD_START, LLx = 0.1328125, LLy = "repeatY", URx = 0.2421875, URy = BORDER_COORD_START, LRx = 0.2421875, LRy = "repeatY" },
}

local function ResolveBorderCoord(value, repeatX, repeatY)
    if value == "repeatX" then
        return repeatX
    elseif value == "repeatY" then
        return repeatY
    end
    return value
end

local function SetBorderPieceTexCoord(region, pieceSetup, repeatX, repeatY)
    region:SetTexCoord(
        ResolveBorderCoord(pieceSetup.ULx, repeatX, repeatY),
        ResolveBorderCoord(pieceSetup.ULy, repeatX, repeatY),
        ResolveBorderCoord(pieceSetup.LLx, repeatX, repeatY),
        ResolveBorderCoord(pieceSetup.LLy, repeatX, repeatY),
        ResolveBorderCoord(pieceSetup.URx, repeatX, repeatY),
        ResolveBorderCoord(pieceSetup.URy, repeatX, repeatY),
        ResolveBorderCoord(pieceSetup.LRx, repeatX, repeatY),
        ResolveBorderCoord(pieceSetup.LRy, repeatX, repeatY)
    )
end

local function UpdateBorderTextureCoordinates(borderFrame)
    if not CanAccessObject(borderFrame) then
        return
    end

    local width = borderFrame.GetWidth and borderFrame:GetWidth() or 0
    local height = borderFrame.GetHeight and borderFrame:GetHeight() or 0
    local effectiveScale = borderFrame.GetEffectiveScale and borderFrame:GetEffectiveScale() or 1
    local edgeSize = borderFrame.__es or EDGE_SIZE

    local secret = issecretvalue and (
        issecretvalue(width)
        or issecretvalue(height)
        or issecretvalue(effectiveScale)
        or issecretvalue(edgeSize)
    )

    local repeatX, repeatY = 0, 0
    if not secret
        and type(width) == "number"
        and type(height) == "number"
        and type(effectiveScale) == "number"
        and type(edgeSize) == "number"
        and edgeSize > 0
    then
        repeatX = max(0, (width / edgeSize) * effectiveScale - 2 - BORDER_COORD_START)
        repeatY = max(0, (height / edgeSize) * effectiveScale - 2 - BORDER_COORD_START)
    end

    for pieceName, pieceSetup in pairs(BORDER_TEXTURE_UVS) do
        local region = borderFrame[pieceName]
        if region then
            SetBorderPieceTexCoord(region, pieceSetup, repeatX, repeatY)
        end
    end
end

local function LayoutBorderPieces(borderFrame, edgeSize)
    if not CanAccessObject(borderFrame) then
        return
    end

    local tl = borderFrame.TopLeftCorner
    local tr = borderFrame.TopRightCorner
    local bl = borderFrame.BottomLeftCorner
    local br = borderFrame.BottomRightCorner
    local t = borderFrame.TopEdge
    local b = borderFrame.BottomEdge
    local l = borderFrame.LeftEdge
    local r = borderFrame.RightEdge
    if not (tl and tr and bl and br and t and b and l and r) then
        return
    end
    if not (CanAccessObject(tl) and CanAccessObject(tr) and CanAccessObject(bl) and CanAccessObject(br)
        and CanAccessObject(t) and CanAccessObject(b) and CanAccessObject(l) and CanAccessObject(r)) then
        return
    end

    tl:ClearAllPoints()
    tr:ClearAllPoints()
    bl:ClearAllPoints()
    br:ClearAllPoints()
    t:ClearAllPoints()
    b:ClearAllPoints()
    l:ClearAllPoints()
    r:ClearAllPoints()

    tl:SetPoint("TOPLEFT", borderFrame, "TOPLEFT", 0, 0)
    tr:SetPoint("TOPRIGHT", borderFrame, "TOPRIGHT", 0, 0)
    bl:SetPoint("BOTTOMLEFT", borderFrame, "BOTTOMLEFT", 0, 0)
    br:SetPoint("BOTTOMRIGHT", borderFrame, "BOTTOMRIGHT", 0, 0)

    tl:SetSize(edgeSize, edgeSize)
    tr:SetSize(edgeSize, edgeSize)
    bl:SetSize(edgeSize, edgeSize)
    br:SetSize(edgeSize, edgeSize)

    t:SetPoint("TOPLEFT", tl, "TOPRIGHT", 0, 0)
    t:SetPoint("TOPRIGHT", tr, "TOPLEFT", 0, 0)
    t:SetHeight(edgeSize)

    b:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT", 0, 0)
    b:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT", 0, 0)
    b:SetHeight(edgeSize)

    l:SetPoint("TOPLEFT", tl, "BOTTOMLEFT", 0, 0)
    l:SetPoint("BOTTOMLEFT", bl, "TOPLEFT", 0, 0)
    l:SetWidth(edgeSize)

    r:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT", 0, 0)
    r:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT", 0, 0)
    r:SetWidth(edgeSize)
end

local function EnsureBorderTexture(borderFrame, textureFile, blendMode)
    if not CanCreateBorderPieces(borderFrame) then
        return nil
    end

    local edgeTexture = textureFile or BORDER_FILE
    local edgeBlendMode = blendMode or "BLEND"
    local edgeSize = borderFrame.__es or EDGE_SIZE
    local pieces = borderFrame._refineBorderPieces
    if not pieces then
        pieces = {}
        for i = 1, #BORDER_PIECE_ORDER do
            local pieceName = BORDER_PIECE_ORDER[i]
            local tex = borderFrame:CreateTexture(nil, "OVERLAY", nil, 7)
            tex:SetBlendMode(edgeBlendMode)
            tex:SetTexture(edgeTexture, true, true)
            borderFrame[pieceName] = tex
            pieces[i] = tex
        end

        borderFrame._refineBorderPieces = pieces
        borderFrame._refineBorderTexture = borderFrame.TopEdge or pieces[1]

        if not borderFrame._refineBorderHooks then
            borderFrame._refineBorderHooks = true
            borderFrame:HookScript("OnSizeChanged", UpdateBorderTextureCoordinates)
            borderFrame:HookScript("OnShow", UpdateBorderTextureCoordinates)
        end
    end

    for i = 1, #pieces do
        local tex = pieces[i]
        if CanAccessObject(tex) then
            tex:SetBlendMode(edgeBlendMode)
            tex:SetTexture(edgeTexture, true, true)
        end
    end

    LayoutBorderPieces(borderFrame, edgeSize)
    UpdateBorderTextureCoordinates(borderFrame)
    return borderFrame._refineBorderTexture
end

----------------------------------------------------------------------------------------
-- Strip Textures (with recursive Blizzard child handling)
----------------------------------------------------------------------------------------
local StripTexturesBlizzFrames = {
    "Inset", "inset", "InsetFrame", "LeftInset", "RightInset", 
    "NineSlice", "BG", "Bg", "border", "Border",
    "BorderFrame", "bottomInset", "BottomInset", 
}

local function StripTextures(self, doKill)
    if not self then return end
    if not StyleState[self] then StyleState[self] = {} end
    local state = StyleState[self]
    if state.stripped and (not doKill or state.strippedKilled) then return end
    
    for i = 1, self:GetNumRegions() do
        local region = select(i, self:GetRegions())
        if region and region:IsObjectType("Texture") then
            if doKill and region.Kill then
                region:Kill()
            else
                region:SetTexture("")
                if region.SetAtlas then region:SetAtlas("") end
                if doKill then
                    region:Hide()
                    region.Show = region.Hide
                end
            end
        end
    end
    state.stripped = true
    if doKill then state.strippedKilled = true end
    
    -- Recursive: strip known Blizzard child frames
    local frameName = self.GetName and self:GetName()
    for _, key in pairs(StripTexturesBlizzFrames) do
        local sub = self[key] or (frameName and _G[frameName .. key])
        if sub and sub ~= self and sub.GetNumRegions then
            StripTextures(sub, doKill)
        end
    end
end

----------------------------------------------------------------------------------------
-- Position Helpers
----------------------------------------------------------------------------------------
local function SetOutside(self, anchor, offsetX, offsetY)
    offsetX = offsetX or 2
    offsetY = offsetY or 2
    anchor = anchor or self:GetParent()
    
    if self.ClearAllPoints then self:ClearAllPoints() end
    self:SetPoint("TOPLEFT", anchor, "TOPLEFT", -offsetX, offsetY)
    self:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", offsetX, -offsetY)
end

local function SetInside(self, anchor, offsetX, offsetY)
    offsetX = offsetX or 2
    offsetY = offsetY or 2
    anchor = anchor or self:GetParent()
    
    if self.ClearAllPoints then self:ClearAllPoints() end
    self:SetPoint("TOPLEFT", anchor, "TOPLEFT", offsetX, -offsetY)
    self:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -offsetX, offsetY)
end

local function SyncBackdropToBorderInsets(owner, insetX, insetY)
    if not CanAccessObject(owner) then
        return
    end

    local bg = owner.bg
    if not CanAccessObject(bg) then
        return
    end

    -- Keep backdrop aligned to the owner's actual bounds.
    -- Border insets grow the border frame outward and should not push backdrop outside.
    if bg.ClearAllPoints then
        bg:ClearAllPoints()
    end
    bg:SetPoint("TOPLEFT", owner, "TOPLEFT", 0, 0)
    bg:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", 0, 0)
end

----------------------------------------------------------------------------------------
-- Scaled Size/Point
----------------------------------------------------------------------------------------
local function Size(self, width, height)
    self:SetSize(RefineUI:Scale(width), RefineUI:Scale(height or width))
end

local function Point(self, anchor, parent, anchor2, x, y)
    self:SetPoint(anchor, parent, anchor2, RefineUI:Scale(x or 0), RefineUI:Scale(y or 0))
end

local function GetSafeFrameLevel(frame, fallback)
    local safeFallback = type(fallback) == "number" and fallback or 0
    if not CanAccessObject(frame) or type(frame.GetFrameLevel) ~= "function" then
        return safeFallback
    end

    local ok, frameLevel = pcall(frame.GetFrameLevel, frame)
    if not ok or (issecretvalue and issecretvalue(frameLevel)) or type(frameLevel) ~= "number" then
        return safeFallback
    end

    return frameLevel
end

local function GetSafeFrameStrata(frame, fallback)
    local safeFallback = (type(fallback) == "string" and fallback ~= "") and fallback or "MEDIUM"
    if not CanAccessObject(frame) or type(frame.GetFrameStrata) ~= "function" then
        return safeFallback
    end

    local ok, strata = pcall(frame.GetFrameStrata, frame)
    if not ok or (issecretvalue and issecretvalue(strata)) or type(strata) ~= "string" or strata == "" then
        return safeFallback
    end

    return strata
end

----------------------------------------------------------------------------------------
-- Font Styling
----------------------------------------------------------------------------------------
local function Font(self, size, font, flag, shadow)
    if not self or not self.SetFont then return end
    
    local cfg = RefineUI.Config and RefineUI.Config.General and RefineUI.Config.General.Appearance
    if not cfg then return end
    
    font = font or (RefineUI.Media and RefineUI.Media.Fonts and RefineUI.Media.Fonts.Default) or cfg.Font
    size = size or 12
    flag = flag or cfg.FontFlag
    
    self:SetFont(font, RefineUI:Scale(size), flag)
    
    if shadow ~= false then
        local sx, sy = unpack(cfg.ShadowOffset)
        self:SetShadowOffset(sx, sy)
        self:SetShadowColor(unpack(cfg.ShadowColor))
    else
        self:SetShadowOffset(0, 0)
        self:SetShadowColor(0, 0, 0, 0)
    end
end

----------------------------------------------------------------------------------------
-- CreateBorder (Idempotent - creates or updates)
----------------------------------------------------------------------------------------
local function CreateBorder(self, insetX, insetY, edgeSize)
    if not CanAccessObject(self) then return end
    if self.IsForbidden and self:IsForbidden() then return end
    if type(self.CreateTexture) ~= "function" then return end
    
    insetX = insetX or 6
    insetY = insetY or 6
    edgeSize = edgeSize or EDGE_SIZE
    
    local b = ResolveManagedRefineBorder(self)
    if b then
        if not CanAccessObject(b) then
            return nil
        end
        if b.IsForbidden and b:IsForbidden() then
            return nil
        end

        -- Update existing border
        local needsAnchor = (b.__ix ~= insetX) or (b.__iy ~= insetY)
        local needsEdge = (b.__es ~= edgeSize) or (b.__edgeFile ~= BORDER_FILE)
        
        if needsAnchor then
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", self, "TOPLEFT", -insetX, insetY)
            b:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", insetX, -insetY)
            b.__ix, b.__iy = insetX, insetY
            SyncBackdropToBorderInsets(self, insetX, insetY)
        end
        
        if needsEdge or not b._refineBorderPieces then
            b.__es, b.__edgeFile = edgeSize, BORDER_FILE
            EnsureBorderTexture(b, BORDER_FILE, "BLEND")
            SyncBackdropToBorderInsets(self, insetX, insetY)
        end

        EnsureBorderCompatMethods(b)
        
        local want = max(0, GetSafeFrameLevel(self, 0) + 1)
        if GetSafeFrameLevel(b, want) ~= want and type(b.SetFrameLevel) == "function" then
            b:SetFrameLevel(want)
        end

        local strata = GetSafeFrameStrata(self, "MEDIUM")
        if GetSafeFrameStrata(b, strata) ~= strata and type(b.SetFrameStrata) == "function" then
            b:SetFrameStrata(strata)
        end

        b._refineBorderOwner = self
        self.RefineBorder = b
        self.border = b
        
        return b
    end
    
    -- Create new border
    b = CreateFrame("Frame", nil, self)
    b:SetPoint("TOPLEFT", self, "TOPLEFT", -insetX, insetY)
    b:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", insetX, -insetY)
    SyncBackdropToBorderInsets(self, insetX, insetY)

    b.__ix, b.__iy, b.__es, b.__edgeFile = insetX, insetY, edgeSize, BORDER_FILE
    b._refineBorderOwner = self
    EnsureBorderTexture(b, BORDER_FILE, "BLEND")
    EnsureBorderCompatMethods(b)
    b:SetBackdropBorderColor(BR, BG, BB, BA)

    b:SetFrameLevel(max(0, GetSafeFrameLevel(self, 0) + 1))
    b:SetFrameStrata(GetSafeFrameStrata(self, "MEDIUM"))
    if b.EnableMouse then
        b:EnableMouse(false)
    end
    self.border = b
    self.RefineBorder = b -- Safe unique alias
    return b
end

----------------------------------------------------------------------------------------
-- CreatePulse (Idempotent - adds animation group)
----------------------------------------------------------------------------------------
local function CreatePulse(self, from, to, duration)
    if self.PulseAnim then return self.PulseAnim end
    
    local animGroup = self:CreateAnimationGroup()
    animGroup:SetLooping("BOUNCE")
    
    local alpha = animGroup:CreateAnimation("Alpha")
    alpha:SetFromAlpha(from or 0.3)
    alpha:SetToAlpha(to or 1)
    alpha:SetDuration(duration or 0.6)
    alpha:SetSmoothing("IN_OUT")
    
    self.PulseAnim = animGroup
    return animGroup
end

----------------------------------------------------------------------------------------
-- CreateGlow (Idempotent - creates/updates glow backdrop)
----------------------------------------------------------------------------------------
local function CreateGlow(self, size)
    if not CanAccessObject(self) then return end
    if self.IsForbidden and self:IsForbidden() then return end
    size = size or 6
    local edgeFile = (RefineUI.Media and RefineUI.Media.Textures and RefineUI.Media.Textures.Glow) or [[Interface\AddOns\RefineUI\Media\Textures\Glow.tga]]

    local g = self.glow
    if g then
        if not CanAccessObject(g) then
            return nil
        end

        if g.__gs ~= size then
            RefineUI.SetOutside(g, self, size, size)
            g.__gs = size
        end
        if (g.__es ~= size) or (g.__edgeFile ~= edgeFile) or not g._refineBorderPieces then
            g.__es = size
            g.__edgeFile = edgeFile
            EnsureBorderTexture(g, edgeFile, "ADD")
        end

        g:SetFrameLevel(max(0, GetSafeFrameLevel(self, 0) - 1)) -- Behind by default
        g:SetFrameStrata(GetSafeFrameStrata(self, "MEDIUM"))
        EnsureBorderCompatMethods(g)
        return g
    end

    local g = CreateFrame("Frame", nil, self)
    g:SetFrameLevel(max(0, GetSafeFrameLevel(self, 0) - 1)) -- Behind by default
    g:SetFrameStrata(GetSafeFrameStrata(self, "MEDIUM"))
    RefineUI.SetOutside(g, self, size, size)

    g.__es = size
    g.__gs = size
    g.__edgeFile = edgeFile
    EnsureBorderTexture(g, edgeFile, "ADD")
    EnsureBorderCompatMethods(g)
    g:SetBackdropBorderColor(1, 0.82, 0, 1) -- RefineUI Gold
    g:Hide()
    
    self.glow = g
    self.RefineGlow = g
    AddAPI(g)
    return g
end

----------------------------------------------------------------------------------------
-- SetTemplate (Idempotent - unified styling)
----------------------------------------------------------------------------------------
local function SetTemplate(self, template)
    if not CanAccessObject(self) then return end
    if self.IsForbidden and self:IsForbidden() then return end
    if type(self.CreateTexture) ~= "function" then return end
    
    local dr, dg, db, da = DR, DG, DB, DA
    local bgTexture = (RefineUI.Media and RefineUI.Media.Textures and RefineUI.Media.Textures.Blank) or "Interface\\Buttons\\WHITE8x8"
    
    local inset = 6
    local hasBackdrop = true
    
    if template == "Transparent" then
        da = 0.8
        inset = 4
    elseif template == "Icon" then
        da = 0
        inset = 4
    elseif template == "Aura" then
        da = 1
        inset = 4
    elseif template == "Empty" or template == "Zero" then
        da = 0
        inset = 4
    elseif template == "Overlay" then
        da = 1
        inset = 4
    elseif template == "ClassColor" then
        local border = CreateBorder(self, inset, inset)
        if border and border.SetBackdropBorderColor then
            border:SetBackdropBorderColor(1, 0.82, 0, 1)
        end
        return
    end
    
    -- Handle Backdrop (.bg)
    if hasBackdrop then
        local b = self.bg
        if not b then
            b = self:CreateTexture(nil, "BACKGROUND", nil, -8)
            EnsureBackdropCompatMethods(b)

            self.bg = b
            self.RefineBackdrop = b -- Safe unique alias
        elseif b.IsForbidden and b:IsForbidden() then
            return
        end
        if b.SetTexture then
            b:SetTexture(bgTexture)
        end
        if b.SetBackdropColor then
            b:SetBackdropColor(dr, dg, db, da)
        elseif b.SetVertexColor then
            b:SetVertexColor(dr, dg, db, da)
        end
        SyncBackdropToBorderInsets(self, inset, inset)
    end
    
    -- Handle Border (.border)
    CreateBorder(self, inset, inset)
end

----------------------------------------------------------------------------------------
-- CreateBackdrop (Compatibility Wrapper)
----------------------------------------------------------------------------------------
local function CreateBackdrop(self, template)
    if not CanAccessObject(self) then return end
    if (self.IsForbidden and self:IsForbidden()) or self.bg then return end
    SetTemplate(self, template or "Default")
    self.RefineBackdrop = self.bg -- Safe unique alias
end

----------------------------------------------------------------------------------------
-- StyleButton (for action buttons, checkboxes, etc.)
----------------------------------------------------------------------------------------
local function StyleButton(self, skipPushed, size)
    size = size or 2
    
    -- Hover texture
    if self.SetHighlightTexture and not self.hover then
        local hover = self:CreateTexture()
        hover:SetColorTexture(1, 1, 1, 0.3)
        hover:SetPoint("TOPLEFT", self, size, -size)
        hover:SetPoint("BOTTOMRIGHT", self, -size, size)
        self.hover = hover
        self:SetHighlightTexture(hover)
    end
    
    -- Pushed texture
    if not skipPushed and self.SetPushedTexture and not self.pushed then
        local pushed = self:CreateTexture()
        pushed:SetColorTexture(0.9, 0.8, 0.1, 0.3)
        pushed:SetPoint("TOPLEFT", self, size, -size)
        pushed:SetPoint("BOTTOMRIGHT", self, -size, size)
        self.pushed = pushed
        self:SetPushedTexture(pushed)
    end
    
    -- Checked texture
    if self.SetCheckedTexture and not self.checked then
        local checked = self:CreateTexture()
        checked:SetColorTexture(0, 1, 0, 0.3)
        checked:SetPoint("TOPLEFT", self, size, -size)
        checked:SetPoint("BOTTOMRIGHT", self, -size, size)
        self.checked = checked
        self:SetCheckedTexture(checked)
    end
    
    -- Style cooldown if exists
    local cooldown = self:GetName() and _G[self:GetName() .. "Cooldown"]
    if cooldown then
        cooldown:ClearAllPoints()
        cooldown:SetPoint("TOPLEFT", self, size, -size)
        cooldown:SetPoint("BOTTOMRIGHT", self, -size, size)
    end
end

----------------------------------------------------------------------------------------
-- SkinButton (Full Blizzard button reskin)
----------------------------------------------------------------------------------------
local function SetModifiedBackdrop(self)
    local border = self.RefineBorder or self.border
    if self:IsEnabled() and border and border.SetBackdropBorderColor then
        border:SetBackdropBorderColor(1, 0.82, 0, 1)
    end
end

local function SetOriginalBackdrop(self)
    local border = self.RefineBorder or self.border
    if border and border.SetBackdropBorderColor then
        border:SetBackdropBorderColor(BR, BG, BB, BA or 1)
    end
end

local function SkinButton(self, strip)
    if not StyleState[self] then StyleState[self] = {} end
    if StyleState[self].skinned then return end
    StyleState[self].skinned = true
    
    if strip and self.StripTextures then self:StripTextures() end
    
    -- Hide default button textures
    if self.SetNormalTexture then self:SetNormalTexture(0) end
    if self.SetHighlightTexture then self:SetHighlightTexture(0) end
    if self.SetPushedTexture then self:SetPushedTexture(0) end
    if self.SetDisabledTexture then self:SetDisabledTexture(0) end
    
    -- Hide common Blizzard button pieces
    local hidePieces = { "Left", "Right", "Middle", "LeftSeparator", "RightSeparator", "Flash",
        "TopLeft", "TopRight", "BottomLeft", "BottomRight", "TopMiddle", 
        "MiddleLeft", "MiddleRight", "BottomMiddle", "MiddleMiddle" }
    
    for _, piece in pairs(hidePieces) do
        if self[piece] then
            if self[piece].SetAlpha then self[piece]:SetAlpha(0) end
            if self[piece].Hide then self[piece]:Hide() end
        end
    end
    
    -- Apply styling
    SetTemplate(self, "Overlay")
    
    -- Hover effects
    self:HookScript("OnEnter", SetModifiedBackdrop)
    self:HookScript("OnLeave", SetOriginalBackdrop)
end

-- API Injection (Fixed: Safe Instance Injection)
----------------------------------------------------------------------------------------
AddAPI = function(self, object)
    if not object or type(object) ~= "table" then object = self end
    
    -- All functions MUST be defined before this point!
    local inject = {
        Kill = Kill,
        StripTextures = StripTextures,
        SetOutside = SetOutside,
        SetInside = SetInside,
        Size = Size,
        Point = Point,
        Font = Font,
        CreateBorder = CreateBorder,
        SetTemplate = SetTemplate,
        CreateBackdrop = CreateBackdrop,
        StyleButton = StyleButton,
        SkinButton = SkinButton,
        CreatePulse = CreatePulse,
        CreateGlow = CreateGlow,
        FadeIn = function(self, duration, alpha) RefineUI:FadeIn(self, duration, alpha) end,
        FadeOut = function(self, duration, alpha) RefineUI:FadeOut(self, duration, alpha) end,
    }
    
    for k, func in pairs(inject) do
        if object[k] == nil then
            object[k] = func
        end
    end
end

-- Expose for manual use
RefineUI.AddAPI = AddAPI

----------------------------------------------------------------------------------------
-- Auto-inject API into common widget types
----------------------------------------------------------------------------------------
-- DEPRECATED: Modifying metatables of global widgets causes TAINT.
-- Do not auto-inject. Modules must explicitly call RefineUI:AddAPI(frame)
-- or use the static helper functions (RefineUI.SetTemplate, etc).
-- local function SetupWidgetAPI() ... end


----------------------------------------------------------------------------------------
-- Safe Error Handling Wrapper
----------------------------------------------------------------------------------------
local function SafeCall(func)
    return xpcall(func, function(err)
        local msg = "|cffff5555RefineUI skin error:|r " .. tostring(err)
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage(msg)
        else
            print(msg)
        end
    end)
end

RefineUI.SafeCall = SafeCall

----------------------------------------------------------------------------------------
-- Skin Functions Registry
----------------------------------------------------------------------------------------
RefineUI.SkinFuncs = RefineUI.SkinFuncs or {}
RefineUI.SkinFuncs["RefineUI"] = RefineUI.SkinFuncs["RefineUI"] or {}

local function LoadBlizzardSkin(_, event, addon)
    if event == "ADDON_LOADED" then
        local bucket = RefineUI.SkinFuncs[addon]
        if bucket then
            if type(bucket) == "function" then
                SafeCall(bucket)
            else
                for _, func in pairs(bucket) do
                    SafeCall(func)
                end
            end
            RefineUI.SkinFuncs[addon] = nil
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        for addonName, bucket in pairs(RefineUI.SkinFuncs) do
            if C_AddOns and C_AddOns.IsAddOnLoaded(addonName) then
                if type(bucket) == "function" then
                    SafeCall(bucket)
                else
                    for _, func in pairs(bucket) do
                        SafeCall(func)
                    end
                end
                RefineUI.SkinFuncs[addonName] = nil
            end
        end
    end
end

local BlizzardSkinLoader = CreateFrame("Frame")
BlizzardSkinLoader:RegisterEvent("ADDON_LOADED")
BlizzardSkinLoader:RegisterEvent("PLAYER_ENTERING_WORLD")
BlizzardSkinLoader:SetScript("OnEvent", LoadBlizzardSkin)

----------------------------------------------------------------------------------------
-- Expose Helper Functions
----------------------------------------------------------------------------------------
RefineUI.CreateBorder = CreateBorder
RefineUI.CreateGlow = CreateGlow
RefineUI.CreatePulse = CreatePulse
RefineUI.SetTemplate = SetTemplate
RefineUI.CreateBackdrop = CreateBackdrop
RefineUI.StyleButton = StyleButton
RefineUI.SkinButton = SkinButton
RefineUI.Font = Font
RefineUI.SetOutside = SetOutside
RefineUI.SetInside = SetInside
RefineUI.Kill = Kill
RefineUI.StripTextures = StripTextures
RefineUI.Size = Size
RefineUI.Point = Point

----------------------------------------------------------------------------------------
-- Create Standard Settings Button
----------------------------------------------------------------------------------------
function RefineUI.EnsureSettingsButtonIcon(button, atlasName)
	if not button then
		return
	end

	local icon = button._refineSettingsIcon
	if not icon then
		icon = button:CreateTexture(nil, "OVERLAY")
		icon:SetAllPoints(button)
		button._refineSettingsIcon = icon
	end

	local atlas = atlasName or "GM-icon-settings"
	local atlasApplied = false
	if icon.SetAtlas then
		local ok = pcall(icon.SetAtlas, icon, atlas, true)
		if ok then
			if icon.GetAtlas then
				atlasApplied = (icon:GetAtlas() == atlas)
			else
				atlasApplied = icon:GetTexture() ~= nil
			end
		end
	end

	if atlasApplied then
		icon:SetTexCoord(0, 1, 0, 1)
	else
		-- Support direct texture paths (for example Interface\\AddOns\\...\\Settings.blp).
		if icon.SetAtlas then
			pcall(icon.SetAtlas, icon, nil)
		end
		icon:SetTexture(atlas)
		if icon:GetTexture() then
			icon:SetTexCoord(0, 1, 0, 1)
		else
			icon:SetTexture("Interface\\WorldMap\\Gear_64")
			icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
		end
	end

	if atlasName and atlasName ~= "GM-icon-settings" then
		icon:SetVertexColor(1, 1, 1)
	else
		icon:SetVertexColor(1, 0.82, 0)
	end
	icon:Show()
	button:SetNormalTexture("")
end

function RefineUI.CreateSettingsButton(parent, name, size, atlasName)
	local button = CreateFrame("Button", name, parent)
	button:SetSize(size or 28, size or 28)

	if not atlasName or atlasName == "GM-icon-settings" then
		button:SetNormalAtlas("GM-icon-settings")
		button:SetPushedAtlas("GM-icon-settings-pressed")
		button:SetHighlightAtlas("GM-icon-settings-hover")
		button:SetDisabledAtlas("GM-icon-settings-disabled")

		-- Color it RefineUI Gold
		local r, g, b = 1, 0.82, 0
		local normal = button:GetNormalTexture()
		if normal and normal.SetVertexColor then
			normal:SetVertexColor(r, g, b)
		end
		local pushed = button:GetPushedTexture()
		if pushed and pushed.SetVertexColor then
			pushed:SetVertexColor(r, g, b)
		end
		local highlight = button:GetHighlightTexture()
		if highlight and highlight.SetVertexColor then
			highlight:SetVertexColor(r, g, b)
		end
	else
		button:SetNormalTexture("")
		button:SetPushedTexture("")
		button:SetHighlightTexture("")
		button:SetDisabledTexture("")
	end
	RefineUI.EnsureSettingsButtonIcon(button, atlasName)

	return button
end
