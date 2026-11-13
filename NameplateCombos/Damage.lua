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

---------------------------------------------------------------------------
-- Spell API: newer clients replaced GetSpellInfo & co. with C_Spell /
-- C_SpellBook. Use whichever this client has.
---------------------------------------------------------------------------

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end

local function SpellIDByName(name)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(name)
        return info and info.spellID
    end
    if GetSpellInfo then return select(7, GetSpellInfo(name)) end
end

local function SpellSubtext(id)
    if C_Spell and C_Spell.GetSpellSubtext then return C_Spell.GetSpellSubtext(id) end
    if GetSpellSubtext then return GetSpellSubtext(id) end
end

local function Knows(id)
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(id) then return true end
    if IsSpellKnown and IsSpellKnown(id) then return true end
    return false
end

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
    return SpellName(f.ranks[1]) or f.name
end

---------------------------------------------------------------------------
-- Rank lookup
---------------------------------------------------------------------------

-- Returns the spell ID and rank number of the highest known rank.
local function HighestRank(f)
    for i = #f.ranks, 1, -1 do
        if Knows(f.ranks[i]) then return f.ranks[i], i end
    end
    -- Fallback for clients with different spell IDs: look the spell up by name.
    local id = SpellIDByName(ns.FinisherName(f))
    if id then return id, nil end
end

---------------------------------------------------------------------------
-- Spell text: tried from several sources, since clients differ in which
-- ones exist and some load spell text in the background.
---------------------------------------------------------------------------

local function SplitLines(text, lines)
    for line in text:gmatch("[^\r\n]+") do lines[#lines + 1] = line end
    return lines
end

-- Newer clients: tooltip data without a tooltip frame.
local function TooltipInfoLines(spellID)
    if not (C_TooltipInfo and C_TooltipInfo.GetSpellByID) then return nil end
    local data = C_TooltipInfo.GetSpellByID(spellID)
    if not (data and data.lines) then return nil end
    local lines = {}
    for _, l in ipairs(data.lines) do
        if l.leftText then SplitLines(l.leftText, lines) end
    end
    return lines
end

local function DescriptionLines(spellID)
    local text = (C_Spell and C_Spell.GetSpellDescription and C_Spell.GetSpellDescription(spellID))
        or (GetSpellDescription and GetSpellDescription(spellID))
    if not text or text == "" then return nil end
    return SplitLines(text, {})
end

local scanTip

local function ScanTooltipLines(spellID)
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", ADDON_NAME .. "ScanTooltip", nil, "GameTooltipTemplate")
    end
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:ClearLines()
    if not scanTip.SetSpellByID then return {} end
    scanTip:SetSpellByID(spellID)
    local lines = {}
    local prefix = scanTip:GetName() .. "TextLeft"
    for i = 1, scanTip:NumLines() do
        local fs = _G[prefix .. i]
        local text = fs and fs:GetText()
        if text then SplitLines(text, lines) end
    end
    scanTip:Hide()
    return lines
end

local SOURCES = {
    { name = "tooltip info", fn = TooltipInfoLines },
    { name = "description", fn = DescriptionLines },
    { name = "scan tooltip", fn = ScanTooltipLines },
}

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

local RETRY_SECONDS = 2
local cache = {}      -- finisher key -> data
local failedAt = {}   -- finisher key -> GetTime() of the last failed lookup
ns.damageDebug = {}   -- finisher key -> what the last lookup found (/ncp debug)

local function Lookup(f)
    local dbg = { sources = {} }
    ns.damageDebug[f.key] = dbg
    local id, rank = HighestRank(f)
    dbg.id, dbg.rank = id, rank
    if not id then return nil end
    if C_Spell and C_Spell.RequestLoadSpellData then C_Spell.RequestLoadSpellData(id) end

    for _, src in ipairs(SOURCES) do
        local ok, lines = pcall(src.fn, id)
        if not ok then
            dbg.sources[#dbg.sources + 1] = src.name .. ": error " .. tostring(lines)
        elseif not lines then
            dbg.sources[#dbg.sources + 1] = src.name .. ": not available"
        else
            local perPoint, energyBonus = ParseDamage(lines)
            local maxPoint = 0
            for cp in pairs(perPoint) do maxPoint = math.max(maxPoint, cp) end
            dbg.sources[#dbg.sources + 1] = string.format("%s: %d lines, %d point entries",
                src.name, #lines, maxPoint)
            if maxPoint == 0 and #lines > 0 then dbg.sample = lines[#lines] end
            if maxPoint > 0 then
                local rankText = SpellSubtext(id)
                if (not rankText or rankText == "") and rank then rankText = "Rank " .. rank end
                dbg.source = src.name
                return { id = id, rankText = rankText, perPoint = perPoint,
                         maxPoint = maxPoint, energyBonus = energyBonus }
            end
        end
    end
end

local function GetData(f)
    local data = cache[f.key]
    if data then return data end
    -- Spell text may still be loading: retry failed lookups every few seconds.
    if failedAt[f.key] and GetTime() - failedAt[f.key] < RETRY_SECONDS then return nil end
    data = Lookup(f)
    if data then
        cache[f.key], failedAt[f.key] = data, nil
    else
        failedAt[f.key] = GetTime()
    end
    return data
end

function ns.InvalidateDamageCache()
    wipe(cache)
    wipe(failedAt)
end

-- Lines for /ncp debug.
function ns.DamageDebugLines()
    local f = ns.GetTrackedFinisher()
    if not f then return { "no finishers for this class" } end
    wipe(failedAt) -- force a fresh lookup now
    cache[f.key] = nil
    local data = GetData(f)
    local dbg = ns.damageDebug[f.key] or {}
    local out = {
        string.format("finisher: %s (%s), spell ID: %s, rank: %s",
            ns.FinisherName(f), f.key, tostring(dbg.id), tostring(dbg.rank)),
    }
    for _, s in ipairs(dbg.sources or {}) do out[#out + 1] = "  " .. s end
    if dbg.sample then out[#out + 1] = "  last line read: " .. dbg.sample end
    if data then
        local parts = {}
        for cp = 1, data.maxPoint do
            local r = data.perPoint[cp]
            if r then parts[#parts + 1] = cp .. ":" .. r[1] .. "-" .. r[2] end
        end
        out[#out + 1] = "  using " .. tostring(dbg.source) .. " -> " .. table.concat(parts, " ")
    else
        out[#out + 1] = "  |cffff5555no damage numbers found|r"
    end
    return out
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
