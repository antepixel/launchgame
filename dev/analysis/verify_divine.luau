-- Step 0 (the numeric facts), step 1's backward-compatibility test and step 3's
-- verification for the Divine steepening + within-tier weighting. See REPORT.md.
--
--   lune run dev/analysis/verify_divine.luau
--
-- Run from the REPO ROOT. Deterministic -- no sampling, no seed. Safe to run
-- before the edits (step 0 and the compatibility test do not depend on them)
-- and again after.
--
-- FRESH CODE: this shares nothing with verify_anchor.luau or clamp_effect.luau.
-- It builds its own per-slime PMF and its own box mixture, with the clamp luck
-- derived from T_MAX rather than assumed to be the anchor.
local fs = require("@lune/fs")
local shim = require("../rbxshim")

local Config = shim.ReplicatedStorage:FindFirstChild("Config")
for _, name in { "SlimeConfig", "SlimeData", "LuckCurve", "SlimeUpgradeConfig", "SlimeUpgrade", "MoneyFormat", "TreasureConfig" } do
	if not Config:FindFirstChild(name) then
		shim.registerModule(Config, name, "src/ReplicatedStorage/Config/" .. name .. ".luau")
	end
end
local SlimeConfig = shim.loadLuauModule("src/ReplicatedStorage/Config/SlimeConfig.luau")
local SlimeData = shim.loadLuauModule("src/ReplicatedStorage/Config/SlimeData.luau")
local SlimeUpgrade = shim.loadLuauModule("src/ReplicatedStorage/Config/SlimeUpgrade.luau")
local SlimeUpgradeConfig = shim.loadLuauModule("src/ReplicatedStorage/Config/SlimeUpgradeConfig.luau")
local MoneyFormat = shim.loadLuauModule("src/ReplicatedStorage/Config/MoneyFormat.luau")
local TreasureConfig = shim.loadLuauModule("src/ReplicatedStorage/Config/TreasureConfig.luau")
local LuckCurve = shim.loadLuauModule("src/ReplicatedStorage/Config/LuckCurve.luau")
local LaunchConfig = shim.loadLuauModule("src/ReplicatedStorage/Config/LaunchConfig.luau")
local SlimeRoll = shim.loadLuauModule("src/ServerScriptService/SlimeRoll.luau")
local BaseConfig = shim.loadLuauModule("src/ReplicatedStorage/Config/BaseConfig.luau")

local TIER_COUNT = #SlimeConfig.SLIME_TIER_NAMES
local DIVINE = TIER_COUNT
local BOX_P = LaunchConfig.BOX_DOUBLE_CHANCE
local CLAMP_LUCK = SlimeConfig.SLIME_LUCK_ANCHOR_LOW
	* (SlimeConfig.SLIME_LUCK_ANCHOR_HIGH / SlimeConfig.SLIME_LUCK_ANCHOR_LOW) ^ SlimeConfig.SLIME_EXTRAPOLATION_T_MAX

local failures = {}
local function stop(ok: boolean, label: string, expected: string, actual: string)
	print(string.format("  %-4s %-44s expected %-30s actual %s", if ok then "PASS" else "FAIL", label, expected, actual))
	if not ok then
		table.insert(failures, string.format("%s -- expected %s, actual %s", label, expected, actual))
	end
end
local function money(n: number): string
	local a = math.abs(n)
	if a >= 1e12 then return string.format("$%.4gT", n / 1e12)
	elseif a >= 1e9 then return string.format("$%.4gB", n / 1e9)
	elseif a >= 1e6 then return string.format("$%.4gM", n / 1e6)
	elseif a >= 1e3 then return string.format("$%.4gK", n / 1e3) end
	return string.format("$%.4g", n)
end

--=================== The two within-tier rules, side by side ===================--
-- OLD: every slime in a tier equally likely -- SlimeRoll.rollSlime's
-- math.random(1, #pool), and mass/#pool analytically.
local function uniformShares(tier: number): { number }
	local n = #SlimeData.SLIMES_BY_TIER[tier]
	local out = table.create(n, 0)
	for i = 1, n do
		out[i] = 1 / n
	end
	return out
end
-- NEW: weight_i = ratio^-(i-1), normalised. Read from the config if the field
-- exists yet, so this file runs before AND after step 1's edit.
local function ratioShares(tier: number): { number }
	local n = #SlimeData.SLIMES_BY_TIER[tier]
	local table_ = (SlimeConfig :: any).SLIME_TIER_WEIGHT_RATIO
	local ratio = if table_ then table_[tier] else 1.0
	local weights, total = table.create(n, 0), 0
	for i = 1, n do
		weights[i] = ratio ^ -(i - 1)
		total += weights[i]
	end
	local out = table.create(n, 0)
	for i = 1, n do
		out[i] = weights[i] / total
	end
	return out
end

-- Per-slime PMF for one luck value. `shareFn` decides the within-tier split;
-- the tier masses always come from the real SlimeRoll.
local function pmfForLuck(luck: number, shareFn): { number }
	local pmf = table.create(#SlimeData.SLIMES, 0)
	for tier, tierMass in SlimeRoll.distributionForLuck(luck) do
		if tierMass > 0 then
			local pool = SlimeData.SLIMES_BY_TIER[tier]
			local shares = shareFn(tier)
			for i, slime in pool do
				pmf[slime.globalIndex] += tierMass * shares[i]
			end
		end
	end
	return pmf
end

local function chestPmf(shareFn): { number }
	local pmf = table.create(#SlimeData.SLIMES, 0)
	local weights, total = {}, 0
	for i = 1, TIER_COUNT - 1 do
		weights[i] = TreasureConfig.CHEST_TIER_WEIGHT_RATIO ^ (i - 1)
		total += weights[i]
	end
	for tier = 1, TIER_COUNT do
		local tierMass = if tier == TIER_COUNT
			then TreasureConfig.CHEST_DIVINE_CHANCE
			else (1 - TreasureConfig.CHEST_DIVINE_CHANCE) * weights[tier] / total
		local pool = SlimeData.SLIMES_BY_TIER[tier]
		local shares = shareFn(tier)
		for i, slime in pool do
			pmf[slime.globalIndex] += tierMass * shares[i]
		end
	end
	return pmf
end

local function evOfPmf(pmf: { number }): number
	local ev = 0
	for index, mass in pmf do
		ev += mass * SlimeData.SLIMES[index].incomePerSecond
	end
	return ev
end
local function tierMassOfPmf(pmf: { number }, tier: number): number
	local total = 0
	for _, slime in SlimeData.SLIMES_BY_TIER[tier] do
		total += pmf[slime.globalIndex]
	end
	return total
end

-- The box's doubling chain, integrated exactly against the TRUE clamp.
local function boxPmfWithClamp(bandLuck: number, shareFn, clampLuck: number): { number }
	local pmf = table.create(#SlimeData.SLIMES, 0)
	local remaining, d = 1.0, 0
	while true do
		local luck = bandLuck * 2 ^ d
		local weight = if luck >= clampLuck then remaining else remaining * (1 - BOX_P)
		for index, mass in pmfForLuck(luck, shareFn) do
			pmf[index] += weight * mass
		end
		if luck >= clampLuck then
			return pmf
		end
		remaining -= weight
		d += 1
	end
end
local function boxPmf(bandLuck: number, shareFn): { number }
	return boxPmfWithClamp(bandLuck, shareFn, CLAMP_LUCK)
end

-- The ten tier lucks, re-derived from the ladder rather than hardcoded.
local SwingGeometry = shim.loadLuauModule("src/ReplicatedStorage/Config/SwingGeometry.luau")
local SwingTierVisuals = shim.loadLuauModule("src/ReplicatedStorage/Config/SwingTierVisuals.luau")
local LaneConfig = shim.loadLuauModule("src/ReplicatedStorage/Config/LaneConfig.luau")
local RunwayGeometry = shim.loadLuauModule("src/ReplicatedStorage/Config/RunwayGeometry.luau")
local ladderTiers = #LaunchConfig.SWING_TIER_DISTANCE_SCALE
local tierLuck = {}
for tier = 1, ladderTiers do
	local scale = SwingTierVisuals.forTier(tier).scale
	local seatZ = LaneConfig.SWING_PIVOT_Z
		- SwingGeometry.ropeLengthForScale(scale) * math.sin(math.rad(LaunchConfig.SWING_ARC_HALF_ANGLE_DEGREES))
	local distance = LaunchConfig.DISTANCE_PER_MULTIPLIER * LaunchConfig.SWEET_SPOT_MULTIPLIER * LaunchConfig.SWING_TIER_DISTANCE_SCALE[tier]
	local band = math.floor((RunwayGeometry.RUNWAY_START_Z - (seatZ - distance)) / LaunchConfig.RUNWAY_BAND_LENGTH_STUDS)
	tierLuck[tier] = if band > #LuckCurve.VALUES - 1 then 0 else LuckCurve.VALUES[band + 1]
end

--============================ STEP 0: the facts ============================--
print("================ STEP 0 ================")
print("0a. within-tier split today")
print("    SlimeRoll.rollSlime:130-135 -- `local index = math.random(1, #pool)`, a flat")
print("    pick over the tier's own list, so every slime in a tier is equally likely.")
print(string.format("    tier sizes: %s", (function()
	local out = {}
	for tier = 1, TIER_COUNT do
		table.insert(out, string.format("%s=%d", SlimeConfig.SLIME_TIER_NAMES[tier], #SlimeData.SLIMES_BY_TIER[tier]))
	end
	return table.concat(out, " ")
end)()))

print("\n0c. MoneyFormat at the new magnitudes")
for _, probe in { 854297, 245000000, 14160000000, 2 ^ 53, 1e18, 1e21 } do
	print(string.format("    %-16s -> %s", string.format("%.0f", probe), MoneyFormat.format(probe)))
end
print(string.format("    exact-integer limit of float64: 2^53 = %.0f", 2 ^ 53))

print("\n0e. upgrade cost at the new top Divine")
local topDivine = SlimeConfig.SLIME_INCOME_BY_TIER[DIVINE][#SlimeConfig.SLIME_INCOME_BY_TIER[DIVINE]]
for _, base in { 854297, topDivine } do
	local cost, count = SlimeUpgrade.totalUpgradeCost(base, 1, SlimeUpgradeConfig.MAX_LEVEL)
	print(string.format("    totalUpgradeCost(%d, 1, %d) = %.4f (%s), %d levels, %.6f seconds of base income",
		base, SlimeUpgradeConfig.MAX_LEVEL, cost, MoneyFormat.format(cost), count, cost / base))
end

print("\n0f. dev/analysis/common.luau clamp assumption")
local commonSource = fs.readFile("dev/analysis/common.luau")
local hardcoded = string.find(commonSource, "clampLuck = M.SlimeConfig.SLIME_LUCK_ANCHOR_HIGH", 1, true) ~= nil
print(string.format("    clampLuck hardcoded to SLIME_LUCK_ANCHOR_HIGH: %s", if hardcoded then "YES (stale)" else "no (derived)"))
print(string.format("    true clamp luck at T_MAX %.2f = %.1f", SlimeConfig.SLIME_EXTRAPOLATION_T_MAX, CLAMP_LUCK))

--============== STEP 1: the backward-compatibility stop condition ==============--
print("\n================ STEP 1: backward compatibility ================")
print("Uniform shares vs the ratio mechanism with every configured ratio -- the full")
print("65-slime PMF at all ten tier lucks and at the chest table, compared bitwise.")
local ratioTable = (SlimeConfig :: any).SLIME_TIER_WEIGHT_RATIO
local allUniform = true
if ratioTable then
	for tier = 1, TIER_COUNT do
		if ratioTable[tier] ~= 1.0 then
			allUniform = false
		end
	end
end
local worstDiff, worstWhere = 0, nil
local function compare(label: string, a: { number }, b: { number })
	for i = 1, #SlimeData.SLIMES do
		local diff = math.abs((a[i] or 0) - (b[i] or 0))
		if diff > worstDiff then
			worstDiff, worstWhere = diff, string.format("%s, slime %d", label, i)
		end
	end
end
for tier = 1, ladderTiers do
	local luck = tierLuck[tier]
	if luck > 0 then
		compare(string.format("luck %d", luck), pmfForLuck(luck, uniformShares), pmfForLuck(luck, ratioShares))
	end
end
compare("chest", chestPmf(uniformShares), chestPmf(ratioShares))
if allUniform then
	stop(worstDiff == 0, "PMF identical to the uniform rule (all ratios 1.0)", "exactly 0 (bitwise)",
		string.format("%.3e%s", worstDiff, if worstWhere then " at " .. worstWhere else ""))
else
	print(string.format("  n/a  a non-uniform ratio is configured, so this comparison no longer applies."))
	print(string.format("       (worst |uniform - configured| = %.6e at %s -- expected, that is the change)",
		worstDiff, tostring(worstWhere)))
	print("       The bitwise test was run and PASSED before Divine's ratio was set; see REPORT.md.")
end

--============================ STEP 3: verification ============================--
print("\n================ STEP 3: verification ================")
local shares = ratioShares

print("\n3a. STOP CONDITION -- P(Divine) per tier unchanged by the within-tier split")
local worstTierMassDiff, worstTierMassAt = 0, nil
for tier = 1, ladderTiers do
	local luck = tierLuck[tier]
	if luck > 0 then
		local fromRoll = SlimeRoll.distributionForLuck(luck)[DIVINE]
		local fromPmf = tierMassOfPmf(pmfForLuck(luck, shares), DIVINE)
		local diff = math.abs(fromRoll - fromPmf)
		if diff > worstTierMassDiff then
			worstTierMassDiff, worstTierMassAt = diff, luck
		end
	end
end
local chestDivineDiff = math.abs(tierMassOfPmf(chestPmf(shares), DIVINE) - TreasureConfig.CHEST_DIVINE_CHANCE)
stop(worstTierMassDiff <= 1e-12 and chestDivineDiff <= 1e-12,
	"P(Divine) from the split vs the tier weight", "identical to 1e-12",
	string.format("worst %.3e (road)%s, %.3e (chest)", worstTierMassDiff,
		if worstTierMassAt then string.format(" at luck %d", worstTierMassAt) else "", chestDivineDiff))

print("\n3b. STOP CONDITION -- monotonicity, road and extrapolated range")
local function evAtLuck(luck: number): number
	return evOfPmf(pmfForLuck(luck, shares))
end
local worstDrop, worstAt, previous = 0, nil, nil
for _, luck in LuckCurve.VALUES do
	local ev = evAtLuck(luck)
	if previous and ev < previous then
		local drop = previous - ev
		if drop > worstDrop then worstDrop, worstAt = drop, luck end
	end
	previous = ev
end
local roadDrop, roadAt = worstDrop, worstAt
-- Extrapolated range: geometric probe from the top band to 1,000,000.
previous = nil
local extraDrop, extraAt = 0, nil
for step = 0, 400 do
	local luck = LuckCurve.VALUES[#LuckCurve.VALUES] * (1000000 / LuckCurve.VALUES[#LuckCurve.VALUES]) ^ (step / 400)
	local ev = evAtLuck(luck)
	if previous and ev < previous then
		local drop = previous - ev
		if drop > extraDrop then extraDrop, extraAt = drop, luck end
	end
	previous = ev
end
stop(roadDrop == 0 and extraDrop == 0, "worst decreasing step (74 bands / extrapolated)", "exactly 0 and 0",
	string.format("%.4e%s / %.4e%s", roadDrop, if roadAt then string.format(" at %d", roadAt) else "",
		extraDrop, if extraAt then string.format(" at %.0f", extraAt) else ""))

print("\n3c. STOP CONDITION -- every distribution well-formed")
local worstSum, worstSumAt, anyNaN, anyNegative = 0, nil, false, false
local probes = { }
for _, luck in LuckCurve.VALUES do table.insert(probes, luck) end
for _, luck in { 120000, 250000, 500000, 1000000, 5000000 } do table.insert(probes, luck) end
for _, luck in probes do
	local pmf = pmfForLuck(luck, shares)
	local total = 0
	for _, mass in pmf do
		total += mass
		if mass ~= mass then anyNaN = true end
		if mass < 0 then anyNegative = true end
	end
	local deviation = math.abs(total - 1)
	if deviation > worstSum then worstSum, worstSumAt = deviation, luck end
end
do
	local total = 0
	for _, mass in chestPmf(shares) do total += mass end
	local deviation = math.abs(total - 1)
	if deviation > worstSum then worstSum, worstSumAt = deviation, -1 end
end
stop(worstSum <= 1e-9 and not anyNaN and not anyNegative, "worst |sum - 1| over 79 probes + chest",
	"<= 1e-9, no NaN, no negative mass",
	string.format("%.3e%s, NaN %s, negative %s", worstSum,
		if worstSumAt == -1 then " (chest)" elseif worstSumAt then string.format(" at luck %d", worstSumAt) else "",
		if anyNaN then "YES" else "no", if anyNegative then "YES" else "no"))

print("\n3d. STOP CONDITION -- band 68 pre-box income tracks the Divine change")
local BAND68 = LuckCurve.VALUES[69]
local ev68 = evAtLuck(BAND68)
print(string.format("     band 68 (luck %d) pre-box E[base]/roll = %s", BAND68, money(ev68)))
stop(ev68 >= 8000 and ev68 <= 14000, "band 68 pre-box E[base]/roll", "$8.0K..$14.0K (was $8.872K)", money(ev68))

if #failures > 0 then
	print(string.format("\n==== STOPPED: %d stop condition(s) failed ====", #failures))
	for _, f in failures do print("  - " .. f) end
	return
end
print("\n---- all four stop conditions passed ----")

--=============================== Reporting ===============================--
local PRE_CHANGE_WITH_BOX = { 39.24, 62.80, 98.50, 248.5, 395.5, 1160, 1948.9, 5444.8, 9192.0 }
print("\n3e. per tier")
print("tier  luck     P(Divine)  P(Divine 8)  P(Secret+)  E no box    E with box   vs pre-change")
for tier = 1, ladderTiers do
	local luck = tierLuck[tier]
	if luck == 0 then
		local pmf = chestPmf(shares)
		print(string.format("%4d  %-8s %9.4f%%  %10.4f%%  %9.4f%%  %-10s  %-11s  %s",
			tier, "chest", tierMassOfPmf(pmf, DIVINE) * 100,
			pmf[SlimeData.SLIMES_BY_TIER[DIVINE][8].globalIndex] * 100,
			(tierMassOfPmf(pmf, DIVINE) + tierMassOfPmf(pmf, DIVINE - 1)) * 100,
			"--", money(evOfPmf(pmf)), "chest table"))
		continue
	end
	local noBox = pmfForLuck(luck, shares)
	local withBox = boxPmf(luck, shares)
	local ratio = evOfPmf(withBox) / PRE_CHANGE_WITH_BOX[tier]
	print(string.format("%4d  %-8d %9.4f%%  %10.4f%%  %9.4f%%  %-10s  %-11s  %.4fx",
		tier, luck, tierMassOfPmf(withBox, DIVINE) * 100,
		withBox[SlimeData.SLIMES_BY_TIER[DIVINE][8].globalIndex] * 100,
		(tierMassOfPmf(withBox, DIVINE) + tierMassOfPmf(withBox, DIVINE - 1)) * 100,
		money(evOfPmf(noBox)), money(evOfPmf(withBox)), ratio))
end

print("\n3f. the top Divine at tier 9")
local tier9 = boxPmf(tierLuck[9], shares)
local topIndex = SlimeData.SLIMES_BY_TIER[DIVINE][8].globalIndex
local pTop = tier9[topIndex]
local CYCLE_SECONDS = 10.1
print(string.format("     P(Divine 8) = %.6f%%  =  one in %s rolls  =  %.1f hours at %.1fs per roll",
	pTop * 100, string.format("%.0f", 1 / pTop), (1 / pTop) * CYCLE_SECONDS / 3600, CYCLE_SECONDS))

print("\n3g. the Divine PMF at tier 9, with the box")
print("  Two contribution columns. CONDITIONAL is contribution to the mean of a")
print("  Divine roll (share of the Divine mass x income) -- the one the flat-tier")
print("  comparison is about. UNCONDITIONAL is contribution to the tier's overall")
print("  E[income] per roll, i.e. the same thing times P(Divine).")
print("  slime      income/s     probability    share of Divine   conditional   unconditional")
local divineMass = tierMassOfPmf(tier9, DIVINE)
local conditional, unconditional = {}, {}
for i, slime in SlimeData.SLIMES_BY_TIER[DIVINE] do
	local p = tier9[slime.globalIndex]
	local cond = (p / divineMass) * slime.incomePerSecond
	local uncond = p * slime.incomePerSecond
	table.insert(conditional, cond)
	table.insert(unconditional, uncond)
	print(string.format("  Divine %d   %-11s  %.6f%%     %8.4f%%         %-12s  %s",
		i, money(slime.incomePerSecond), p * 100, p / divineMass * 100, money(cond), money(uncond)))
end
local function spread(list: { number }): (number, number)
	local lo, hi = math.huge, 0
	for _, v in list do
		lo = math.min(lo, v)
		hi = math.max(hi, v)
	end
	return lo, hi
end
local cLo, cHi = spread(conditional)
local uLo, uHi = spread(unconditional)
print(string.format("  conditional spread:   %s to %s (%.2fx) against a %.1fx income spread",
	money(cLo), money(cHi), cHi / cLo, SlimeData.SLIMES_BY_TIER[DIVINE][8].incomePerSecond / SlimeData.SLIMES_BY_TIER[DIVINE][1].incomePerSecond))
print(string.format("  unconditional spread: %s to %s (%.2fx); they sum to %s of the tier's %s",
	money(uLo), money(uHi), uHi / uLo, money((function()
		local total = 0
		for _, v in unconditional do total += v end
		return total
	end)()), money(evOfPmf(tier9))))

print("\n3h/3i. the ceiling and what it costs")
local MAX_MULT = SlimeUpgrade.incomeMultiplier(SlimeUpgradeConfig.MAX_LEVEL)
local COST_TO_MAX = SlimeUpgrade.totalUpgradeCost(1, 1, SlimeUpgradeConfig.MAX_LEVEL)
local top = SlimeData.SLIMES_BY_TIER[DIVINE][8].incomePerSecond
print(string.format("     top Divine base income          %s/s", money(top)))
print(string.format("     ceiling: %d slots x top x %.4f  %s/s", BaseConfig.SLOT_COUNT, MAX_MULT, money(BaseConfig.SLOT_COUNT * top * MAX_MULT)))
print(string.format("     saturated slot price (x600)     %s", money(top * MAX_MULT * SlimeUpgradeConfig.UPGRADE_PAYBACK_SECONDS)))
print(string.format("     cost to max ONE top Divine      %s", money(COST_TO_MAX * top)))
print(string.format("     cost to max a ceiling base      %s", money(COST_TO_MAX * top * BaseConfig.SLOT_COUNT)))

--============ STEP 4: what the stale clamp in common.luau costs ============--
-- common.luau's rollPmfForBandLuck sets clampLuck = SLIME_LUCK_ANCHOR_HIGH,
-- which stopped being the clamp when T_MAX went past 1.0. Measured here on
-- THIS tree so the fix's effect is separated from every other change.
print("\n================ STEP 4: the stale clamp, measured ================")
print(string.format("stale assumption: clamp at SLIME_LUCK_ANCHOR_HIGH = %d", SlimeConfig.SLIME_LUCK_ANCHOR_HIGH))
print(string.format("true clamp:       LOW * (HIGH/LOW)^T_MAX          = %.1f", CLAMP_LUCK))
print("tier  luck     E with box (stale clamp)  E with box (true clamp)  understated by")
for tier = 1, ladderTiers do
	local luck = tierLuck[tier]
	if luck == 0 then
		continue
	end
	local stale = evOfPmf(boxPmfWithClamp(luck, shares, SlimeConfig.SLIME_LUCK_ANCHOR_HIGH))
	local true_ = evOfPmf(boxPmfWithClamp(luck, shares, CLAMP_LUCK))
	print(string.format("%4d  %-8d %-25s %-24s %.2f%%", tier, luck, money(stale), money(true_), (true_ / stale - 1) * 100))
end
