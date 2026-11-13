-- Nameplate Combos: finisher damage estimate
--
-- Finds the highest rank of the tracked finisher that the player knows and
-- reads its per-combo-point damage from the spell tooltip, e.g.
--     "1 point  : 224-332 damage"
--     "5 points : 904-1012 damage"
-- Reading the tooltip (instead of hard-coding tables) keeps the numbers right
-- for every rank and works in any client language.

local ADDON_NAME, ns = ...
if ns.disabled then return end

local _, playerClass = UnitClass("player")
local ENERGY = (Enum and Enum.PowerType and Enum.PowerType.Energy) or 3

-- Ranks are listed lowest to highest. The first rank's ID is also used to get
-- the localized spell name.
ns.FINISHERS = {
    ROGUE = {
        { key = "EVISCERATE", name = "Eviscerate",
          ranks = { 2098, 6760, 6761, 6762, 8623, 8624, 11299, 11300, 31016 } },
        { key = "RUPTURE", name = "Rupture",
          ranks = { 1943, 8639, 8640, 11273, 11274, 11275 } },
    },
    DRUID = {
        -- Ferocious Bite also turns energy left over after its cost into damage.
        { key = "FEROCIOUS_BITE", name = "Ferocious Bite", energyCost = 35,
          ranks = { 22568, 22827, 22828, 22829, 31018 } },
        { key = "RIP", name = "Rip",
          ranks = { 1079, 9492, 9493, 9752, 9894, 9896 } },
    },
}

function ns.GetFinishers()
    return ns.FINISHERS[playerClass] or {}
end

function ns.GetTrackedFinisher()
    local list = ns.GetFinishers()
    local key = ns.db and ns.db.overlaySpell[playerClass]
    for _, f in ipairs(list) do
        if f.key == key then return f end
    end
    return list[1]
end

function ns.SetTrackedFinisher(key)
    ns.db.overlaySpell[playerClass] = key
end

function ns.FinisherName(f)
    if not f then return "-" end
    return (GetSpellInfo(f.ranks[1])) or f.name
end

---------------------------------------------------------------------------
-- Rank lookup
---------------------------------------------------------------------------

local function Knows(id)
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    if IsSpellKnown and IsSpellKnown(id) then return true end
    return false
end

-- Returns the spell ID and rank number of the highest known rank.
local function HighestRank(f)
    for i = #f.ranks, 1, -1 do
        if Knows(f.ranks[i]) then return f.ranks[i], i end
    end
    -- Fallback for clients with different spell IDs: look the spell up by name.
    local id = select(7, GetSpellInfo(ns.FinisherName(f)))
    if id then return id, nil end
end

---------------------------------------------------------------------------
-- Tooltip parsing
---------------------------------------------------------------------------

local scanTip

local function TooltipLines(spellID)
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", ADDON_NAME .. "ScanTooltip", nil, "GameTooltipTemplate")
    end
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:ClearLines()
    scanTip:SetSpellByID(spellID)
    local lines = {}
    local prefix = scanTip:GetName() .. "TextLeft"
    for i = 1, scanTip:NumLines() do
        local fs = _G[prefix .. i]
        local text = fs and fs:GetText()
        if text then
            for line in text:gmatch("[^\r\n]+") do lines[#lines + 1] = line end
        end
    end
    scanTip:Hide()
    return lines
end

local function ParseDamage(lines)
    local perPoint, energyBonus = {}, nil
    for _, line in ipairs(lines) do
        line = line:gsub("(%d),(%d%d%d)", "%1%2") -- drop thousands separators
        -- "<n> point(s) : <min>-<max> ..." or "<n> point(s) : <amount> ..."
        local cp, rest = line:match("^%s*(%d+)[^%d:]*:%s*(.+)$")
        cp = tonumber(cp)
        if cp and cp >= 1 and cp <= 10 then
            local lo, hi = rest:match("(%d+)%s*%-%s*(%d+)")
            lo = tonumber(lo) or tonumber(rest:match("(%d+)"))
            hi = tonumber(hi) or lo
            if lo then perPoint[cp] = { lo, hi } end
        end
        -- Ferocious Bite: "...each extra point of energy into 2.5 additional damage"
        local bonus = line:match("([%d%.]+) additional damage")
        if bonus then energyBonus = tonumber(bonus) end
    end
    return perPoint, energyBonus
end

local cache = {}

local function GetData(f)
    local data = cache[f.key]
    if data == nil then
        data = false
        local id, rank = HighestRank(f)
        if id then
            local perPoint, energyBonus = ParseDamage(TooltipLines(id))
            local maxPoint = 0
            for cp in pairs(perPoint) do maxPoint = math.max(maxPoint, cp) end
            if maxPoint > 0 then
                local rankText = GetSpellSubtext and GetSpellSubtext(id)
                if (not rankText or rankText == "") and rank then rankText = "Rank " .. rank end
                data = { id = id, rankText = rankText, perPoint = perPoint,
                         maxPoint = maxPoint, energyBonus = energyBonus }
            end
        end
        cache[f.key] = data
    end
    return data or nil
end

function ns.InvalidateDamageCache()
    wipe(cache)
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

-- Average damage of the tracked finisher at the given combo points, after the
-- user's damage adjustment. nil if the spell isn't known or points is 0.
function ns.EstimateDamage(points)
    if not points or points <= 0 then return nil end
    local f = ns.GetTrackedFinisher()
    local data = f and GetData(f)
    if not data then return nil end
    local range
    for cp = math.min(points, data.maxPoint), 1, -1 do
        range = data.perPoint[cp]
        if range then break end
    end
    if not range then return nil end
    local damage = (range[1] + range[2]) / 2
    if data.energyBonus and f.energyCost then
        local energy = UnitPower("player", ENERGY) or 0
        damage = damage + math.max(0, energy - f.energyCost) * data.energyBonus
    end
    return damage * (ns.db.overlayScale or 1)
end

-- One-line summary for the options panel.
function ns.DescribeTrackedFinisher()
    local f = ns.GetTrackedFinisher()
    local data = f and GetData(f)
    if not data then return "|cff999999Not learned yet|r" end
    local last = data.perPoint[data.maxPoint]
    return string.format("%s: up to %d-%d damage at %d points",
        data.rankText or ns.FinisherName(f), last[1], last[2], data.maxPoint)
end
