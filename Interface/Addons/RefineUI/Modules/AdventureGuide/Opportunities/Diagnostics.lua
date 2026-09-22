-- On-demand snapshot of cached evidence. No API scans and no persistent log.
local _, RefineUI = ...
local Engine = RefineUI.OpportunityEngine
local function Value(value)
    if value == nil then return "unavailable" end
    if type(value) == "table" then
        local parts={};for _,v in ipairs(value) do parts[#parts+1]=tostring(v) end
        return table.concat(parts,",")
    end
    return tostring(value)
end
function Engine:DiagnosticReport(category, preferences)
    category = category or "mount"
    preferences = preferences or {};local hidden = preferences.hidden or {}
    local c=self:GetCoverage(category)
    local lines={"Opportunities diagnostic snapshot", "Dataset: "..tostring(self.data.version),
        string.format("Category=%s catalog=%d evaluable=%d owned=%d blocked=%d unknown=%d pending=%d matched=%d",
            category,c.catalog,c.supported,c.owned,c.blocked,c.unknown,c.pending,c.match),
        "Search="..tostring(preferences.search or "").."; all routes included regardless of search/hiding.",
        "Catalog totals include historical/unavailable records. Unimported routes are not evaluated."}
    for index,reward in ipairs(self.data.rewards) do
        local kind=reward[1]=="mountSpell" and "mount" or reward[1]
        if category=="collectibles" or category==kind then
            local ownership=self.ownership[index]
            local key=reward[1]..":"..reward[2]
            lines[#lines+1]=string.format("\n%s | %s | item=%s | hidden=%s",key,ownership and ownership.name or "Name not cached",reward[3],tostring(hidden[key]==true))
            lines[#lines+1]="  Ownership="..(ownership and Value(ownership.owned) or "not checked")
                .."; "..(ownership and ownership.reason or "")
            if ownership and ownership.eligibilityRequired then lines[#lines+1]="  Collectability="..Value(ownership.eligible) end
            for offerID,offer in ipairs(self.data.offers) do
                if offer[1]==index then
                    local source=self.data.sources[offer[2]]
                    local result=self.results[offerID]
                    lines[#lines+1]=string.format("  Route %d: %s source=%s map=%s state=%s %s",offerID,source[1],source[2],source[3],self.evaluation[offerID] or "pending",result and result.label or "")
                    for _,req in ipairs(self.data.requirements[offer[3]]) do
                        local cached=self.dependencies[req[1]..":"..req[2]..":"..req[4]]
                        local passed=Engine.Check(req,cached and cached.value)
                        lines[#lines+1]=string.format("    %s id=%s scope=%s target=%s actual=%s => %s%s",
                            req[1],req[2],req[4],Value(req[3]),cached and Value(cached.value) or "not checked",
                            passed==true and "PASS" or passed==false and "FAIL" or "UNKNOWN",
                            cached and cached.reason and ("; "..cached.reason) or "")
                    end
                end
            end
    end end
    return table.concat(lines,"\n")
end

local Module=RefineUI:GetModule("AdventureGuideOpportunities")
function Module:ShowDiagnosticReport()
    local runtime=RefineUI.Opportunities
    if not self.page or not runtime.engine then return end
    local panel=self.diagnostics
    if not panel then
        panel=CreateFrame("Frame",nil,self.page);self.diagnostics=panel
        panel:SetAllPoints();panel:SetFrameLevel(self.page:GetFrameLevel()+10)
        local bg=panel:CreateTexture(nil,"BACKGROUND");bg:SetAllPoints();bg:SetColorTexture(.03,.04,.05,1)
        local title=panel:CreateFontString(nil,"OVERLAY","GameFontNormal")
        title:SetPoint("TOPLEFT",20,-20);title:SetText("Diagnostic snapshot • Ctrl+A, Ctrl+C to copy")
        local close=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate")
        close:SetSize(80,24);close:SetPoint("TOPRIGHT",-20,-12);close:SetText("Back")
        close:SetScript("OnClick",function() panel.edit:ClearFocus();panel:Hide() end)
        local scroll=CreateFrame("ScrollFrame",nil,panel,"UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT",20,-50);scroll:SetPoint("BOTTOMRIGHT",-40,20)
        local edit=CreateFrame("EditBox",nil,scroll);panel.edit=edit
        edit:SetMultiLine(true);edit:SetAutoFocus(false);edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(math.max(100,self.page:GetWidth()-70));edit:SetHeight(1)
        edit:SetScript("OnEscapePressed",function() edit:ClearFocus();panel:Hide() end)
        scroll:SetScrollChild(edit)
        panel:SetScript("OnHide",function() edit:ClearFocus() end)
    end
    local category=self.category or "collectibles"
    if category=="achievements" then category="mount" end
    panel.edit:SetText(runtime.engine:DiagnosticReport(category,runtime:Preferences()))
    panel:Show();panel.edit:SetFocus();panel.edit:HighlightText()
end
