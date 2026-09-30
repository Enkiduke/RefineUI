----------------------------------------------------------------------------------------
-- GroupFinder Component: Realm
-- Description: Leader realm location (datacenter or language), color-coded, on search
--              entries.
----------------------------------------------------------------------------------------

local _, RefineUI = ...
local GroupFinder = RefineUI:GetModule("GroupFinder")

----------------------------------------------------------------------------------------
-- WoW Globals (Upvalues)
----------------------------------------------------------------------------------------
local GetCurrentRegion = GetCurrentRegion
local GetNormalizedRealmName = GetNormalizedRealmName
local byte, gsub, lower, match = string.byte, string.gsub, string.lower, string.match
local pairs, ipairs = pairs, ipairs

----------------------------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------------------------
local LOCATIONS = {
    NA = { 0.30, 0.67, 0.97 },
    OCE = { 0.41, 0.86, 0.49 },
    BR = { 1.00, 0.83, 0.23 },
    LA = { 1.00, 0.55, 0.25 },
    EN = { 0.80, 0.80, 0.80 },
    DE = { 1.00, 0.83, 0.23 },
    FR = { 0.30, 0.67, 0.97 },
    ES = { 1.00, 0.55, 0.25 },
    RU = { 1.00, 0.42, 0.42 },
    IT = { 0.41, 0.86, 0.49 },
    PT = { 0.22, 0.85, 0.66 },
}

-- GetCurrentRegion(): 1 = US (Americas and Oceania), 3 = EU. US realms are grouped by
-- datacenter, EU realms by language; unlisted realms use DEFAULT_LOCATION, and
-- Cyrillic EU realm names are RU. Other regions show no tag.
local DEFAULT_LOCATION = { [1] = "NA", [3] = "EN" }
local REALMS = {
    [1] = {
        OCE = {
            "Aman'Thul", "Barthilas", "Caelestrasz", "Dath'Remar", "Dreadmaul", "Frostmourne",
            "Gundrak", "Jubei'Thos", "Khaz'goroth", "Nagrand", "Saurfang", "Thaurissan",
        },
        BR = { "Azralon", "Gallywix", "Goldrinn", "Nemesis", "Tol Barad" },
        LA = { "Drakkari", "Quel'Thalas", "Ragnaros" },
    },
    [3] = {
        DE = {
            "Aegwynn", "Alexstrasza", "Alleria", "Aman'Thul", "Ambossar", "Anetheron", "Antonidas",
            "Anub'arak", "Area 52", "Arthas", "Arygos", "Azshara", "Baelgun", "Blackhand",
            "Blackmoore", "Blackrock", "Blutkessel", "Dalvengyr", "Das Konsortium", "Das Syndikat",
            "Der abyssische Rat", "Der Mithrilorden", "Der Rat von Dalaran", "Destromath",
            "Dethecus", "Die Aldor", "Die Arguswacht", "Die ewige Wacht", "Die Nachtwache",
            "Die Silberne Hand", "Die Todeskrallen", "Dun Morogh", "Durotan", "Echsenkessel",
            "Eredar", "Festung der Stürme", "Forscherliga", "Frostmourne", "Frostwolf", "Garrosh",
            "Gilneas", "Gorgonnash", "Gul'dan", "Kargath", "Kel'Thuzad", "Khaz'goroth",
            "Kil'jaeden", "Krag'jin", "Kult der Verdammten", "Lordaeron", "Lothar", "Madmortem",
            "Mal'Ganis", "Malfurion", "Malorne", "Malygos", "Mannoroth", "Mug'thol", "Nathrezim",
            "Nazjatar", "Nefarian", "Nera'thor", "Nethersturm", "Norgannon", "Nozdormu", "Onyxia",
            "Perenolde", "Proudmoore", "Rajaxx", "Rexxar", "Sen'jin", "Shattrath", "Taerar",
            "Teldrassil", "Terrordar", "Theradras", "Thrall", "Tichondrius", "Tirion", "Todeswache",
            "Ulduar", "Un'Goro", "Vek'lor", "Wrathbringer", "Ysera", "Zirkel des Cenarius",
            "Zuluhed",
        },
        FR = {
            "Arak-arahm", "Arathi", "Archimonde", "Chants éternels", "Cho'gall",
            "Confrérie du Thorium", "Conseil des Ombres", "Culte de la Rive noire", "Dalaran",
            "Drek'Thar", "Eitrigg", "Eldre'Thalas", "Elune", "Garona", "Hyjal", "Illidan",
            "Kael'thas", "Khaz Modan", "Kirin Tor", "Krasus", "La Croisade écarlate",
            "Les Clairvoyants", "Les Sentinelles", "Marécage de Zangar", "Medivh", "Naxxramas",
            "Ner'zhul", "Rashgarroth", "Sargeras", "Sinstralis", "Suramar", "Temple noir",
            "Throk'Feroth", "Uldaman", "Varimathras", "Vol'jin", "Ysondre",
        },
        ES = {
            "C'Thun", "Colinas Pardas", "Dun Modr", "Exodar", "Los Errantes", "Minahonda",
            "Sanguino", "Shen'dralar", "Tyrande", "Uldum", "Zul'jin",
        },
        IT = { "Nemesis", "Pozzo dell'Eternità" },
        PT = { "Aggra (Português)" },
    },
}

----------------------------------------------------------------------------------------
-- Locals
----------------------------------------------------------------------------------------
local labels = RefineUI:CreateDataRegistry("GroupFinder:Realms", "k")
local region, locations -- Current region and its normalized realm -> location lookup

----------------------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------------------

-- Leader names carry the normalized realm, which drops spaces; drop hyphens and
-- apostrophes too and ignore case so list spellings match either form.
local function Normalize(realm)
    return lower((gsub(realm, "[%s%-']", "")))
end

local function BuildLocations()
    region, locations = GetCurrentRegion(), {}
    for location, names in pairs(REALMS[region] or {}) do
        for _, name in ipairs(names) do
            locations[Normalize(name)] = location
        end
    end
end

local function GetLocation(realm)
    if not locations then
        BuildLocations()
    end
    local location = locations[Normalize(realm)]
    if location then
        return location
    end
    local first = byte(realm, 1)
    if region == 3 and (first == 0xD0 or first == 0xD1) then
        return "RU"
    end
    return DEFAULT_LOCATION[region]
end

----------------------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------------------

-- Sits at the right end of the activity line, above the rating. Blizzard resets the
-- activity width on every entry update, so narrowing it needs no restore.
function GroupFinder:UpdateRealm(entry, info)
    local label = labels[entry]
    if label then
        label:SetText("")
    end
    if not self.db.RealmLocation then
        return
    end

    local leader = self.Read(info, "table") and self.Read(info.leaderName, "string")
    if not leader then
        return
    end
    local realm = match(leader, "%-(.+)$") or GetNormalizedRealmName()
    local location = realm and GetLocation(realm)
    if not location then
        return
    end

    if not label then
        label = entry:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        RefineUI.Point(label, "TOPLEFT", entry, "TOPLEFT", 118, -21)
        RefineUI.Size(label, 64, 14)
        label:SetJustifyH("RIGHT")
        labels[entry] = label
    end

    local color = LOCATIONS[location]
    entry.ActivityName:SetWidth(RefineUI:Scale(140))
    label:SetTextColor(color[1], color[2], color[3])
    label:SetText(location)
end
