-- STEP 3f: what raising SLIME_LUCK_ANCHOR_HIGH to 1,000,000 does to the
-- sliding window, to SLIME_EXTRAPOLATION_T_MAX and to the NaN safety floors.
-- Reported, not fixed.
--
--   lune run dev/analysis/clamp_effect.luau
--
-- Run from the REPO ROOT. Pure analytic, reading the REAL SlimeRoll and the
-- REAL SlimeConfig -- t and the window start are recomputed here with the same
-- arithmetic SlimeRoll.distributionForLuck uses (cited below) so they can be
-- printed alongside the distribution the module actually returns.
local C = require("./common")

local SlimeConfig = C.SlimeConfig
local LuckCurve = C.LuckCurve
local SlimeRoll = C.SlimeRoll

local lnLow = math.log(SlimeConfig.SLIME_LUCK_ANCHOR_LOW)
local lnHigh = math.log(SlimeConfig.SLIME_LUCK_ANCHOR_HIGH)

-- SlimeRoll.luau:68-77
local function tForLuck(luck: number): (number, number, boolean)
	local raw = (math.log(math.max(luck, 1e-6)) - lnLow) / (lnHigh - lnLow)
	local clamped = math.clamp(raw, SlimeConfig.SLIME_EXTRAPOLATION_T_MIN, SlimeConfig.SLIME_EXTRAPOLATION_T_MAX)
	local windowStartRaw = SlimeConfig.SLIME_WINDOW_START_LOW
		+ (SlimeConfig.SLIME_WINDOW_START_HIGH - SlimeConfig.SLIME_WINDOW_START_LOW) * clamped
	local windowStart = math.clamp(
		math.round(windowStartRaw),
		1,
		#SlimeConfig.SLIME_TIER_NAMES - SlimeConfig.SLIME_WINDOW_WIDTH + 1
	)
	return clamped, windowStart, raw ~= clamped
end

local function evForLuck(luck: number): number
	local weights = SlimeRoll.distributionForLuck(luck)
	local ev = 0
	for tier, mass in weights do
		if mass > 0 then
			local pool = C.SlimeData.SLIMES_BY_TIER[tier]
			local mean = 0
			for _, s in pool do
				mean += s.incomePerSecond
			end
			ev += mass * mean / #pool
		end
	end
	return ev
end

print(string.format("anchors: LOW %s, HIGH %s   |   T_MIN %s, T_MAX %s   |   window width %d",
	tostring(SlimeConfig.SLIME_LUCK_ANCHOR_LOW), tostring(SlimeConfig.SLIME_LUCK_ANCHOR_HIGH),
	tostring(SlimeConfig.SLIME_EXTRAPOLATION_T_MIN), tostring(SlimeConfig.SLIME_EXTRAPOLATION_T_MAX),
	SlimeConfig.SLIME_WINDOW_WIDTH))

print("\n== window transitions across the 74 road bands ==")
print("band  luck        t        window start  window                       E[base]/roll")
local previousStart = nil
for i, luck in LuckCurve.VALUES do
	local t, windowStart = tForLuck(luck)
	if windowStart ~= previousStart then
		local names = {}
		for tier = windowStart, windowStart + SlimeConfig.SLIME_WINDOW_WIDTH - 1 do
			table.insert(names, SlimeConfig.SLIME_TIER_NAMES[tier])
		end
		print(string.format("%4d  %-10s  %7.4f  %12d  %-27s  $%s",
			i - 1, LuckCurve.formatLuck(luck), t, windowStart,
			names[1] .. "-" .. names[#names], C.fmt(evForLuck(luck))))
		previousStart = windowStart
	end
end

--=========================== Is t clamped anywhere? ===========================--
local topLuck = LuckCurve.VALUES[#LuckCurve.VALUES]
local tTop, startTop, clampedTop = tForLuck(topLuck)
local tBottom, startBottom, clampedBottom = tForLuck(LuckCurve.VALUES[1])
print(string.format("\nbottom of the road (luck %s): t = %.4f%s, window start %d",
	LuckCurve.formatLuck(LuckCurve.VALUES[1]), tBottom,
	if clampedBottom then " (CLAMPED at T_MIN)" else "", startBottom))
print(string.format("top of the road (luck %s):    t = %.4f%s, window start %d",
	LuckCurve.formatLuck(topLuck), tTop, if clampedTop then " (CLAMPED at T_MAX)" else "", startTop))

-- Where does the box's doubling chain actually reach T_MAX from the top band?
local doublings = 0
local luck = topLuck
while select(3, tForLuck(luck)) == false and doublings < 64 do
	luck *= 2
	doublings += 1
end
print(string.format("from the top band, the box needs %d doublings (luck %s) to reach the T_MAX clamp; P(D >= %d) = %.4f%%",
	doublings, C.fmt(luck), doublings, 100 * C.BOX_P ^ doublings))

--============================ The NaN safety floors ============================--
-- SlimeConfig.SLIME_SPREAD_FLOOR exists because a NEGATIVE spread makes
-- (|dist| / spread) negative and a fractional power of a negative is NaN, which
-- rollTier's last-tier fallback would silently turn into an all-Divine roll.
-- Each lerp's zero crossing is a t value; the floors are unreachable only while
-- T_MAX stays below every crossing.
local function crossing(low: number, high: number): number?
	if low == high then
		return nil
	end
	return low / (low - high)
end
print("\n== NaN safety floors: the t at which each lerp would cross zero ==")
print("lerp          low        high       zero crossing at t   reachable at T_MAX?")
for _, row in {
	{ "spreadDown", SlimeConfig.SLIME_SPREAD_DOWN_LOW, SlimeConfig.SLIME_SPREAD_DOWN_HIGH },
	{ "spreadUp", SlimeConfig.SLIME_SPREAD_UP_LOW, SlimeConfig.SLIME_SPREAD_UP_HIGH },
	{ "shape", SlimeConfig.SLIME_SHAPE_LOW, SlimeConfig.SLIME_SHAPE_HIGH },
} do
	local zero = crossing(row[2], row[3])
	print(string.format("%-12s  %9.4f  %9.4f  %18s   %s",
		row[1], row[2], row[3],
		if zero then string.format("%.4f", zero) else "never (parallel)",
		if zero and SlimeConfig.SLIME_EXTRAPOLATION_T_MAX >= zero then "YES -- FLOOR IS LOAD-BEARING" else "no"))
end

--===================== Distribution defined out to 1,000,000? =====================--
print("\n== the distribution above the road, where only the box can reach ==")
print("luck        t        window                       E[base]/roll  sums to 1?")
for _, probe in { 100000, 200000, 500000, 1000000, 2000000, 1e7, 1e9 } do
	local t, windowStart = tForLuck(probe)
	local weights = SlimeRoll.distributionForLuck(probe)
	local total, nan = 0, false
	for _, mass in weights do
		total += mass
		if mass ~= mass then
			nan = true
		end
	end
	local names = {}
	for tier = windowStart, windowStart + SlimeConfig.SLIME_WINDOW_WIDTH - 1 do
		table.insert(names, SlimeConfig.SLIME_TIER_NAMES[tier])
	end
	print(string.format("%-10s  %7.4f  %-27s  $%-12s  %s",
		C.fmt(probe), t, names[1] .. "-" .. names[#names], C.fmt(evForLuck(probe)),
		if nan then "NaN PRESENT" else string.format("%.12f", total)))
end
