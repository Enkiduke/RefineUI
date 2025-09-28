local R, C, L = unpack(RefineUI)

-- Hover chat links to show tooltips (based on tekKompare)
-- Performance > KISS: no gating on initial show; let Tooltip.lua skin/position later.

local origEnter, origLeave = {}, {}

local linktypes = {
  item=true, enchant=true, spell=true, quest=true, unit=true,
  talent=true, achievement=true, glyph=true, instancelock=true, currency=true,
  battlepet=true, -- handled specially
}

local GameTooltip          = GameTooltip
local BattlePetTooltip     = BattlePetTooltip
local BattlePetToolTip_Show= BattlePetToolTip_Show
local strmatch, strsplit   = string.match, strsplit
local tonumber             = tonumber

local lastFrame, lastLink  = nil, nil

local function ShowHyperlinkTooltip(frame, link)
  local ltype = strmatch(link, "^([^:]+)")
  if not ltype then return end

  if ltype == "battlepet" then
    -- Don't show a blank GameTooltip underneath; just use the pet tooltip.
    GameTooltip:Hide()
    local _, speciesID, level, quality, hp, power, speed = strsplit(":", link)
    BattlePetToolTip_Show(tonumber(speciesID), tonumber(level), tonumber(quality), tonumber(hp), tonumber(power), tonumber(speed))
    return
  end

  if linktypes[ltype] then
    -- Respect your default anchor override in Tooltip.lua
    GameTooltip:SetOwner(frame, "ANCHOR_NONE")
    GameTooltip_SetDefaultAnchor(GameTooltip, frame)
    GameTooltip:SetHyperlink(link)
  end
end

local function OnHyperlinkEnter(frame, link, ...)
  -- If we’re still on the same frame+link, fall through to original (no duplicate work)
  if lastFrame == frame and lastLink == link then
    if origEnter[frame] then return origEnter[frame](frame, link, ...) end
    return
  end

  lastFrame, lastLink = frame, link
  ShowHyperlinkTooltip(frame, link)

  if origEnter[frame] then return origEnter[frame](frame, link, ...) end
end

local function OnHyperlinkLeave(frame, link, ...)
  -- Always hide both (pet tooltip may be up instead of GameTooltip)
  if BattlePetTooltip and BattlePetTooltip:IsShown() then BattlePetTooltip:Hide() end
  GameTooltip:Hide()

  -- Reset re-hover guard so the same link can show again immediately
  lastFrame, lastLink = nil, nil

  if origLeave[frame] then return origLeave[frame](frame, link, ...) end
end

for i = 1, NUM_CHAT_WINDOWS do
  local cf = _G["ChatFrame"..i]
  origEnter[cf] = cf:GetScript("OnHyperlinkEnter")
  cf:SetScript("OnHyperlinkEnter", OnHyperlinkEnter)

  origLeave[cf] = cf:GetScript("OnHyperlinkLeave")
  cf:SetScript("OnHyperlinkLeave", OnHyperlinkLeave)
end
