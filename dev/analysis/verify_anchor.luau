-- Step 0 (the interpolated quantities and their ranges) and step 3 (the four
-- stop conditions plus the reporting) for the luck-anchor revert. See REPORT.md.
--
--   lune run dev/analysis/verify_anchor.luau
--
-- Run from the REPO ROOT. Pure analytic -- no sampling, no seed. Safe to run
-- BEFORE the edit (step 0 does not depend on T_MAX) and again after.
--
-- INDEPENDENT PATH BY CONSTRUCTION: this file shares no code with
-- dev/analysis/clamp_effect.luau. It requires the real SlimeRoll and the real
-- config modules through dev/rbxshim.luau, and re-derives t, the window and the
-- box mixture here rather than calling common.luau's integrator -- that one
-- assumes the distribution clamps at SLIME_LUCK_ANCHOR_HIGH, which is only true
-- while T_MAX = 1.0. With T_MAX raised the clamp moves to
-- LOW * (HIGH/LOW)^T_MAX, and using the stale assumption would silently
-- truncate the box chain early.
local fs = require("@lune/fs")
local shim = require("../rbxshim")

local Config = shim.ReplicatedStorage:FindFirstChild("Config")
for _, name in { "SlimeConfig", "SlimeData", "LuckCurve" } do
	if not Config:FindFirstChild(name) then
		shim.registerModule(Config, name, "src/ReplicatedStorage/Config/" .. name .. ".luau")
	end
end
local SlimeConfig = shim.loadLuauModule("src/ReplicatedStorage/Config/SlimeConfig.luau")
local SlimeData = shim.loadLuauModule("src/ReplicatedStorage/Config/SlimeData.luau")
local LuckCurve = shim.loadLuauModule("src/ReplicatedStorage/Config/LuckCurve.luau")
local LaunchConfig = shim.loadLuauModule("src/ReplicatedStorage/Config/LaunchConfig.luau")
local SlimeRoll = shim.loadLuauModule("src/ServerScriptService/SlimeRoll.luau")

local TIER_NAMES = SlimeConfig.SLIME_TIER_NAMES
local TIER_COUNT = #TIER_NAMES
local WINDOW = SlimeConfig.SLIME_WINDOW_WIDTH
local LOW, HIGH = SlimeConfig.SLIME_LUCK_ANCHOR_LOW, SlimeConfig.SLIME_LUCK_ANCHOR_HIGH
local T_MAX = SlimeConfig.SLIME_EXTRAPOLATION_T_MAX
local BOX_P = LaunchConfig.BOX_DOUBLE_CHANCE

local failures = {}
local function stop(ok: boolean, label: string, expected: string, actual: string)
	print(string.format("  %-4s %-46s expected %-28s actual %s", if ok then "PASS" else "FAIL", label, expected, actual))
	if not ok then
		table.insert(failures, string.format("%s -- expected %s, actual %s", label, expected, actual))
	end
end

local function lerp(a: number, b: number, t: number): number
	return a + t * (b - a)
end
local function money(n: number): string
	local a = math.abs(n)
	if a >= 1e9 then return string.format("$%.4gB", n / 1e9)
	elseif a >= 1e6 then return string.format("$%.4gM", n / 1e6)
	elseif a >= 1e3 then return string.format("$%.4gK", n / 1e3) end
	return string.format("$%.4g", n)
end

-- SlimeRoll.luau:68-72
local function tForLuck(luck: number): (number, number)
	local raw = (math.log(math.max(luck, 1e-6)) - math.log(LOW)) / (math.log(HIGH) - math.log(LOW))
	return math.clamp(raw, SlimeConfig.SLIME_EXTRAPOLATION_T_MIN, T_MAX), raw
end
-- SlimeRoll.luau:76-77
local function windowStartForT(t: number): number
	return math.clamp(math.round(lerp(SlimeConfig.SLIME_WINDOW_START_LOW, SlimeConfig.SLIME_WINDOW_START_HIGH, t)), 1, TIER_COUNT - WINDOW + 1)
end

local tierMeanIncome = {}
for tier = 1, TIER_COUNT do
	local pool, total = SlimeData.SLIMES_BY_TIER[tier], 0
	for _, s in pool do
		total += s.incomePerSecond
	end
	tierMeanIncome[tier] = total / #pool
end
local function evForLuck(luck: number): number
	local ev = 0
	for tier, mass in SlimeRoll.distributionForLuck(luck) do
		ev += mass * tierMeanIncome[tier]
	end
	return ev
end

--=========================== STEP 0: the lerps ===========================--
print("================ STEP 0: the interpolated quantities ================")
print(string.format("anchors LOW %s / HIGH %s   T_MIN %s / T_MAX %s   window width %d over %d tiers",
	tostring(LOW), tostring(HIGH), tostring(SlimeConfig.SLIME_EXTRAPOLATION_T_MIN), tostring(T_MAX), WINDOW, TIER_COUNT))

print("\n0a. peak = windowStart + peakOffset  (SlimeRoll.luau:79, :94)")
print(string.format("    peakOffset = lerp(SLIME_PEAK_OFFSET_LOW %.4f, SLIME_PEAK_OFFSET_HIGH %.4f, t)",
	SlimeConfig.SLIME_PEAK_OFFSET_LOW, SlimeConfig.SLIME_PEAK_OFFSET_HIGH))
local peakOffsetIsConstant = SlimeConfig.SLIME_PEAK_OFFSET_LOW == SlimeConfig.SLIME_PEAK_OFFSET_HIGH
print(string.format("    endpoints are %s -> peakOffset is %s in t",
	if peakOffsetIsConstant then "IDENTICAL" else "DIFFERENT",
	if peakOffsetIsConstant then "CONSTANT" else "a function of t"))
print("    peak is NOT an index. It is the real-valued CENTRE of the generalised")
print("    Gaussian, in slime-tier units, used only as `dist = i - peak` inside the")
print("    windowStart..windowStart+3 loop (SlimeRoll.luau:98-104). Nothing indexes")
print("    a table with it, so it cannot be out of range; what it can do is move")
print("    the peak outside the window, which would put the modal weight on a tier")
print("    that gets no weight assigned at all.")

print("\n0b/0c. every t-dependent quantity, at the probe values")
print("  t      windowStart  peakOffset  peak   peak in window?  spreadDown  spreadUp  shape   floors engaged")
local probeT = { 1.00, 1.10, 1.20, 1.30, 1.35, 1.40, 1.50 }
for _, t in probeT do
	local ws = windowStartForT(t)
	local peakOffset = lerp(SlimeConfig.SLIME_PEAK_OFFSET_LOW, SlimeConfig.SLIME_PEAK_OFFSET_HIGH, t)
	local peak = ws + peakOffset
	local rawDown = lerp(SlimeConfig.SLIME_SPREAD_DOWN_LOW, SlimeConfig.SLIME_SPREAD_DOWN_HIGH, t)
	local rawUp = lerp(SlimeConfig.SLIME_SPREAD_UP_LOW, SlimeConfig.SLIME_SPREAD_UP_HIGH, t)
	local rawShape = lerp(SlimeConfig.SLIME_SHAPE_LOW, SlimeConfig.SLIME_SHAPE_HIGH, t)
	local engaged = {}
	if rawDown < SlimeConfig.SLIME_SPREAD_FLOOR then table.insert(engaged, "spreadDown") end
	if rawUp < SlimeConfig.SLIME_SPREAD_FLOOR then table.insert(engaged, "spreadUp") end
	if rawShape < SlimeConfig.SLIME_SHAPE_FLOOR then table.insert(engaged, "shape") end
	print(string.format("  %.2f   %11d  %10.4f  %5.2f  %-15s  %10.4f  %8.4f  %6.4f  %s",
		t, ws, peakOffset, peak,
		if peak >= ws and peak <= ws + WINDOW - 1 then "yes" else "NO",
		rawDown, rawUp, rawShape,
		if #engaged == 0 then "none" else table.concat(engaged, ", ")))
end

print("\n0d. windowStart range check (clamp(round(lerp(1, 5, t)), 1, 5))")
print("  t        raw lerp   rounded   after clamp   saturated at 5?")
for _, t in { 0.875, 1.00, 1.10, 1.20, 1.30, 1.35, 1.40, 1.50, 3.00 } do
	local raw = lerp(SlimeConfig.SLIME_WINDOW_START_LOW, SlimeConfig.SLIME_WINDOW_START_HIGH, t)
	local ws = windowStartForT(t)
	print(string.format("  %.3f    %8.4f   %7d   %11d   %s", t, raw, math.round(raw), ws, if ws == 5 then "yes" else "no"))
end

print("\n0e. the largest T_MAX with nothing out of range and no floor engaged")
local function floorEngagesAt(lowV: number, highV: number, floorV: number): number?
	if lowV == highV then
		return nil
	end
	return (lowV - floorV) / (lowV - highV)
end
local bounds = {
	{ "spreadDown", floorEngagesAt(SlimeConfig.SLIME_SPREAD_DOWN_LOW, SlimeConfig.SLIME_SPREAD_DOWN_HIGH, SlimeConfig.SLIME_SPREAD_FLOOR) },
	{ "spreadUp", floorEngagesAt(SlimeConfig.SLIME_SPREAD_UP_LOW, SlimeConfig.SLIME_SPREAD_UP_HIGH, SlimeConfig.SLIME_SPREAD_FLOOR) },
	{ "shape", floorEngagesAt(SlimeConfig.SLIME_SHAPE_LOW, SlimeConfig.SLIME_SHAPE_HIGH, SlimeConfig.SLIME_SHAPE_FLOOR) },
}
local tSafe = math.huge
for _, b in bounds do
	print(string.format("  %-11s floor engages at t = %s", b[1], if b[2] then string.format("%.4f", b[2]) else "never"))
	if b[2] and b[2] < tSafe then
		tSafe = b[2]
	end
end
if peakOffsetIsConstant then
	print("  peak        never leaves the window (peakOffset constant at 1.0, peak = windowStart + 1)")
else
	print("  peak        MOVES with t -- re-derive its bound before raising T_MAX")
end
print(string.format("  windowStart saturates at %d for every t >= 0.875 and cannot index out of range", TIER_COUNT - WINDOW + 1))
print(string.format("\n  T_MAX_SAFE   = %.4f  (bound: the first floor to engage)", tSafe))
print(string.format("  T_MAX_TARGET = min(1.35, T_MAX_SAFE) = %.4f", math.min(1.35, tSafe)))
print(string.format("  currently configured T_MAX = %s", tostring(T_MAX)))

--===================== The box chain, integrated exactly =====================--
-- Geometric doublings at BOX_DOUBLE_CHANCE, with the tail collapsed once the
-- distribution stops moving. The clamp luck is derived from T_MAX, NOT assumed
-- to be the anchor: t = T_MAX at luck = LOW * (HIGH/LOW)^T_MAX.
local CLAMP_LUCK = LOW * (HIGH / LOW) ^ T_MAX
local function boxMixture(bandLuck: number): ({ number }, number)
	local pmf = table.create(TIER_COUNT, 0)
	local remaining, d = 1.0, 0
	while true do
		local luck = bandLuck * 2 ^ d
		local weight = if luck >= CLAMP_LUCK then remaining else remaining * (1 - BOX_P)
		for tier, mass in SlimeRoll.distributionForLuck(luck) do
			pmf[tier] += weight * mass
		end
		if luck >= CLAMP_LUCK then
			return pmf, d
		end
		remaining -= weight
		d += 1
	end
end
local function evOfPmf(pmf: { number }): number
	local ev = 0
	for tier, mass in pmf do
		ev += mass * tierMeanIncome[tier]
	end
	return ev
end

--============================ STEP 3: verification ============================--
print("\n================ STEP 3: verification ================")
print(string.format("clamp luck (t reaches T_MAX) = %s", money(CLAMP_LUCK):sub(2)))

print("\n3a. STOP CONDITION -- the luck-to-t mapping is restored")
local BAND_68_LUCK = LuckCurve.VALUES[69]
local ev68 = evForLuck(BAND_68_LUCK)
stop(ev68 >= 8000 and ev68 <= 9800, string.format("band 68 (luck %d) pre-box E[base]/roll", BAND_68_LUCK),
	"$8.0K..$9.8K (~$8.87K)", money(ev68))

print("\n3b. STOP CONDITION -- the window transitions are back on the road")
local expectedTransitionBands = { 0, 27, 40, 56, 64 }
local seen, previousStart = {}, nil
for i, luck in LuckCurve.VALUES do
	local t = tForLuck(luck)
	local ws = windowStartForT(t)
	if ws ~= previousStart then
		table.insert(seen, { band = i - 1, luck = luck, t = t, windowStart = ws })
		previousStart = ws
	end
end
for _, row in seen do
	local names = {}
	for tier = row.windowStart, row.windowStart + WINDOW - 1 do
		table.insert(names, TIER_NAMES[tier])
	end
	print(string.format("     band %2d  luck %-8s  t = %.4f  -> window start %d (%s-%s)",
		row.band, LuckCurve.formatLuck(row.luck), row.t, row.windowStart, names[1], names[#names]))
end
local matches = #seen == #expectedTransitionBands
if matches then
	for i, row in seen do
		if row.band ~= expectedTransitionBands[i] then
			matches = false
		end
	end
end
local seenBands = {}
for _, row in seen do
	table.insert(seenBands, tostring(row.band))
end
stop(matches, "window transitions, by band", "0, 27, 40, 56, 64", table.concat(seenBands, ", "))

print("\n3c. STOP CONDITION -- monotonicity across all 74 band lucks")
local worstDrop, worstAt, previous = 0, nil, nil
for _, luck in LuckCurve.VALUES do
	local ev = evForLuck(luck)
	if previous and ev < previous then
		local drop = previous - ev
		if drop > worstDrop then
			worstDrop, worstAt = drop, luck
		end
	end
	previous = ev
end
stop(worstDrop <= 0, "worst decreasing step in E[base]/roll", "0",
	string.format("%.6e%s", worstDrop, if worstAt then string.format(" at luck %d", worstAt) else ""))

print("\n3d. STOP CONDITION -- well-formedness past the old clamp")
local worstSumDeviation, worstSumAt = 0, nil
local anyNaN, anyNegative, anyOutside = false, false, false
for _, luck in { 120000, 250000, 500000, 1000000, 5000000 } do
	local weights = SlimeRoll.distributionForLuck(luck)
	local total = 0
	if #weights ~= TIER_COUNT then
		anyOutside = true
	end
	for tier, mass in weights do
		total += mass
		if mass ~= mass then anyNaN = true end
		if mass < 0 then anyNegative = true end
		if tier < 1 or tier > TIER_COUNT then anyOutside = true end
	end
	local deviation = math.abs(total - 1)
	if deviation > worstSumDeviation then
		worstSumDeviation, worstSumAt = deviation, luck
	end
	print(string.format("     luck %-10s sum %.15f  NaN %s  negative %s",
		money(luck):sub(2), total, if anyNaN then "YES" else "no", if anyNegative then "YES" else "no"))
end
stop(worstSumDeviation <= 1e-9 and not anyNaN and not anyNegative and not anyOutside,
	"worst |sum - 1| over the five probes", "<= 1e-9, no NaN/negative/out-of-range",
	string.format("%.3e%s", worstSumDeviation, if worstSumAt then string.format(" at luck %d", worstSumAt) else ""))

if #failures > 0 then
	print(string.format("\n==== STOPPED: %d stop condition(s) failed ====", #failures))
	for _, f in failures do
		print("  - " .. f)
	end
	return
end
print("\n---- all four stop conditions passed ----")

print("\n3e. does the extrapolation actually reach? (not a stop condition)")
print("  luck        t        P(Divine)   E[base]/roll   TV distance from the previous probe")
local previousWeights = nil
for _, luck in { 120000, 250000, 500000, 1000000 } do
	local t = tForLuck(luck)
	local weights = SlimeRoll.distributionForLuck(luck)
	local tv = 0
	if previousWeights then
		for tier = 1, TIER_COUNT do
			tv += math.abs(weights[tier] - previousWeights[tier])
		end
		tv /= 2
	end
	print(string.format("  %-10s  %.4f   %8.4f%%   %-12s   %s",
		money(luck):sub(2), t, weights[TIER_COUNT] * 100, money(evForLuck(luck)),
		if previousWeights then string.format("%.6f", tv) else "--"))
	previousWeights = weights
end

--============ Per-tier figures for the renumbered 10-tier ladder ============--
-- Band per tier is re-derived from the ladder rather than hardcoded, using the
-- same seat/distance/band arithmetic the previous pass verified.
local SwingGeometry = shim.loadLuauModule("src/ReplicatedStorage/Config/SwingGeometry.luau")
local SwingTierVisuals = shim.loadLuauModule("src/ReplicatedStorage/Config/SwingTierVisuals.luau")
local LaneConfig = shim.loadLuauModule("src/ReplicatedStorage/Config/LaneConfig.luau")
local RunwayGeometry = shim.loadLuauModule("src/ReplicatedStorage/Config/RunwayGeometry.luau")
local ladderTiers = #LaunchConfig.SWING_TIER_DISTANCE_SCALE
local tierLuck = {}
for tier = 1, ladderTiers do
	local scale = SwingTierVisuals.forTier(tier).scale
	local seatZ = LaneConfig.SWING_PIVOT_Z - SwingGeometry.ropeLengthForScale(scale) * math.sin(math.rad(LaunchConfig.SWING_ARC_HALF_ANGLE_DEGREES))
	local distance = LaunchConfig.DISTANCE_PER_MULTIPLIER * LaunchConfig.SWEET_SPOT_MULTIPLIER * LaunchConfig.SWING_TIER_DISTANCE_SCALE[tier]
	local fromStart = RunwayGeometry.RUNWAY_START_Z - (seatZ - distance)
	local band = math.floor(fromStart / LaunchConfig.RUNWAY_BAND_LENGTH_STUDS)
	tierLuck[tier] = if band > #LuckCurve.VALUES - 1 then 0 else LuckCurve.VALUES[band + 1]
end

print("\n3f/3g/3h. per tier on the renumbered ladder")
print("tier  band luck   E[base] no box   E[base] with box   box multiple   doublings that still move the distribution")
for tier = 1, ladderTiers do
	local luck = tierLuck[tier]
	if luck == 0 then
		print(string.format("%4d  %-10s  %-15s  %-17s  %-13s  %s", tier, "-- (chest)", "--", "--", "--", "-- (no box on the chest path)"))
		continue
	end
	local pmf, doublings = boxMixture(luck)
	local noBox = evForLuck(luck)
	local withBox = evOfPmf(pmf)
	print(string.format("%4d  %-10s  %-15s  %-17s  %-13s  %d", tier, LuckCurve.formatLuck(luck),
		money(noBox), money(withBox), string.format("%.2fx", withBox / noBox), doublings))
end

local under = {}
for tier = 1, ladderTiers do
	local luck = tierLuck[tier]
	if luck > 0 then
		local pmf = boxMixture(luck)
		if evOfPmf(pmf) / evForLuck(luck) < 1.5 then
			table.insert(under, tier)
		end
	end
end
if #under == 0 then
	print("\nevery road tier's box multiple is at or above 1.5x")
else
	local names = {}
	for _, tier in under do
		table.insert(names, tostring(tier))
	end
	print(string.format("\nUNDER 1.5x: tier(s) %s -- reported plainly, not a stop condition", table.concat(names, ", ")))
end
