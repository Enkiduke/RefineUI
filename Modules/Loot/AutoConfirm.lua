local R, C, L = unpack(RefineUI)
if C.loot.autoConfirmDE ~= true then return end

----------------------------------------------------------------------------------------
--	Disenchant confirmation(tekKrush by Tekkub)
----------------------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("CONFIRM_DISENCHANT_ROLL")
frame:RegisterEvent("CONFIRM_LOOT_ROLL")
frame:RegisterEvent("LOOT_BIND_CONFIRM")
frame:SetScript("OnEvent", function()
	-- Some client versions no longer define STATICPOPUP_NUMDIALOGS; default to 4
	local numDialogs = (type(STATICPOPUP_NUMDIALOGS) == "number" and STATICPOPUP_NUMDIALOGS) or 4
	for i = 1, numDialogs do
		local frame = _G["StaticPopup"..i]
		if frame and (frame.which == "CONFIRM_LOOT_ROLL" or frame.which == "LOOT_BIND") and frame:IsVisible() then
			StaticPopup_OnClick(frame, 1)
		end
	end
end)
