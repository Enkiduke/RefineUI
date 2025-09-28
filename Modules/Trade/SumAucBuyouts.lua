local R, C, L = unpack(RefineUI)
if C.trade.sum_buyouts ~= true then return end

----------------------------------------------------------------------------------------
--	Sum up all current auctions(Sigma by Ailae) - Performance Optimized
----------------------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, _, addon)
	if addon == "Blizzard_AuctionHouseUI" then
		local f = CreateFrame("Frame", nil, AuctionHouseFrame)
		f:SetSize(200, 20)
		f:SetPoint("LEFT", AuctionHouseFrame.MoneyFrameBorder, "RIGHT", 38, -1)

		local text = f:CreateFontString(nil, "OVERLAY", "PriceFont")
		text:SetPoint("LEFT")

		-- Performance: Cache last update to avoid redundant calculations
		local lastUpdateTime = 0
		local UPDATE_THROTTLE = 0.1 -- 100ms throttle
		
		-- Performance: Pre-allocate strings to avoid garbage collection
		local textCache = {
			bids = "",
			buyout = "",
			both = "",
			empty = ""
		}

		local function updateDisplay()
			local currentTime = GetTime()
			if currentTime - lastUpdateTime < UPDATE_THROTTLE then
				return
			end
			lastUpdateTime = currentTime

			local totalBuyout = 0
			local totalBid = 0
			local numAuctions = C_AuctionHouse.GetNumOwnedAuctions()

			-- Performance: Batch API calls and minimize iterations
			for i = 1, numAuctions do
				local info = C_AuctionHouse.GetOwnedAuctionInfo(i)
				if info then
					-- Performance: Direct property access without intermediate variables
					if info.buyoutAmount and info.quantity then
						totalBuyout = totalBuyout + (info.buyoutAmount * info.quantity)
					end
					if info.bidAmount then
						totalBid = totalBid + info.bidAmount
					end
				end
			end

			-- Performance: Use cached strings and single SetText call
			if totalBid > 0 and totalBuyout > 0 then
				if textCache.both == "" then
					textCache.both = BIDS..": %s     "..BUYOUT..": %s"
				end
				text:SetFormattedText(textCache.both, 
					C_CurrencyInfo.GetCoinTextureString(totalBid),
					C_CurrencyInfo.GetCoinTextureString(totalBuyout))
			elseif totalBid > 0 then
				if textCache.bids == "" then
					textCache.bids = BIDS..": %s"
				end
				text:SetFormattedText(textCache.bids, C_CurrencyInfo.GetCoinTextureString(totalBid))
			elseif totalBuyout > 0 then
				if textCache.buyout == "" then
					textCache.buyout = BUYOUT..": %s"
				end
				text:SetFormattedText(textCache.buyout, C_CurrencyInfo.GetCoinTextureString(totalBuyout))
			else
				text:SetText("")
			end
		end

		f:RegisterEvent("OWNED_AUCTIONS_UPDATED")
		f:SetScript("OnEvent", updateDisplay)
	end
end)