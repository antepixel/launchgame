-- How much of this game's clock is decided by whether a player finds the
-- upgrade button. See REPORT.md.
--
--   lune run dev/analysis/levelling_gap.luau [runsPerTier]
--
-- Run from the REPO ROOT. Writes dev/out/levelling_gap.json. Prints tables to
-- stdout. Deterministic for a given runs count (fixed seed).
--
-- ===== JOINS NOTHING. Every prior affordability pass read dev/out/
-- roll_economics.json for prices and dev/out/cycle_economics.json for cadence.
-- Both are stale against HEAD (the ladder went 11 tiers -> 10, the flight
-- duration stopped keying off distance, and per-slot collection landed after
-- they were written), and a stale join is worse than no join because it
-- produces a plausible number. This file therefore re-derives everything it
-- needs from the REAL config modules through dev/rbxshim.luau:
--
--   prices     ShopConfig.SWING_TIER_PRICES
--   cadence    the four terms cycle_time.luau assembles, recomputed here from
--              LaunchConfig/SlimeConfig/TreasureConfig -- see cycleSecondsFor
--   rolls      SlimeRoll.distributionForLuck, through common.rollPmfForBandLuck
--              at each tier's own perfect-launch band luck
--   levelling  SlimeUpgrade.totalUpgradeCost / incomeMultiplier
--
-- ===== THE METHOD IS THE PRIOR PASS'S, UNCHANGED IN KIND (see REPORT.md's
-- STEP 1b). Time-to-afford is NOT price / equilibrium income -- that is
-- circular, since equilibrium income is itself a function of how long the
-- player has been rolling. It is an INTEGRATION along the measured held-set
-- growth curve: start from an empty base, roll at the tier's own cadence,
-- bank income every roll, and stop when the next tier's price is met. The
-- growth curve comes from the simulation below, not from a formula.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local C = require("./common")

local RUNS = tonumber(process.args[1]) or 4000
local HORIZON = 20000
local SEED = 20260813

local commit = (process.exec("git", { "rev-parse", "HEAD" }).stdout:gsub("%s+$", ""))

local LaunchConfig = C.LaunchConfig
local SlimeConfig = C.SlimeConfig
local SlimeUpgrade = C.SlimeUpgrade
local SlimeUpgradeConfig = C.SlimeUpgradeConfig
local ShopConfig = C.ShopConfig
local TIERS = C.SWING_TIER_COUNT
local SLOTS = C.SLOT_COUNT

local TreasureConfig = C.TreasureConfig
local GiantSlimeConfig = C.shim.loadLuauModule("src/ReplicatedStorage/Config/GiantSlimeConfig.luau")

--=========================== The levelling brackets ===========================--
-- Four ways to play, all reading the REAL SlimeUpgrade formulas:
--
--   never      level nothing. Income is base; nothing is ever spent.
--   best       level ONE slime -- whichever is currently the best held -- to
--              MAX_LEVEL, and re-level from scratch whenever a better one
--              arrives (the old one's investment is not transferable).
--   allL10     level EVERY held slime to level 10 and stop there.
--   allMax     level EVERY held slime to MAX_LEVEL (25).
--
-- costPerBaseIncome is the price of taking ONE slime of base income 1 from
-- level 1 to that bracket's level -- derived, never written down: at
-- UPGRADE_PAYBACK_SECONDS = 600 and GROWTH = 1.15, maxing costs 16,575.1 x the
-- slime's base income and buys 27.6252 x it, which is the 600-second payback
-- identity restated.
local MAX_LEVEL = SlimeUpgradeConfig.MAX_LEVEL
local L10 = math.min(10, MAX_LEVEL)
local COST_TO_MAX = (SlimeUpgrade.totalUpgradeCost(1, 1, MAX_LEVEL))
local COST_TO_L10 = (SlimeUpgrade.totalUpgradeCost(1, 1, L10 - 1))
local MULT_MAX = SlimeUpgrade.incomeMultiplier(MAX_LEVEL)
local MULT_L10 = SlimeUpgrade.incomeMultiplier(L10)

--============================== The cadence ==============================--
-- One launch cycle, in seconds, at a given tier. This MIRRORS
-- dev/analysis/cycle_time.luau's own assembly line for line (bar wait, flight,
-- reward scene, remount walk) rather than reading its stale JSON output. The
-- one term that has changed since that JSON was written is the flight, and it
-- is the reason the join was dropped:
--
--   flight = FLIGHT_DURATION_BASE_SECONDS + tier * FLIGHT_DURATION_PER_TIER_SECONDS
--
-- i.e. tier N flies N + 1 seconds, keyed off the TIER INDEX and no longer off
-- the distance (the old form was FLIGHT_DURATION_SECONDS * (d/baseD)^EXPONENT,
-- and both of those constants have since been deleted from LaunchConfig).
-- C.flightDurationForTier is the shared mirror of the live formula.
--
-- ASSUMPTION, stated here rather than in a footnote: PERFECT PLAY. The bar wait
-- is PERIOD/2, the average wait for a player who hits the sweet spot on the
-- first pass every time. Real players miss; cycle_time.luau's hit50 and hit20
-- models add (1/p - 1) * PERIOD to this. Perfect play makes every hour figure
-- below an UNDERESTIMATE of real time, in both brackets, by the same factor at
-- a given tier -- so the RATIO between brackets is untouched by it. The hit50
-- sensitivity is reported alongside.
local PERIOD = LaunchConfig.SWING_PERIOD_SECONDS
local ASSUMED_WALK_SPEED = 16 -- Roblox default; never assigned anywhere in src/
local expectedBoxPresses = 1 / (1 - LaunchConfig.BOX_DOUBLE_CHANCE)
local boxPressSeconds = (expectedBoxPresses - 1) * LaunchConfig.BOX_PRESS_COOLDOWN_SECONDS

-- Chest geometry, mirroring MapBuilder's own placement, for the one tier whose
-- perfect launch clears the road entirely.
local lastBandFarEdgeZ = C.RunwayGeometry.RUNWAY_START_Z - (#C.LuckCurve.VALUES * LaunchConfig.RUNWAY_BAND_LENGTH_STUDS)
local slimeCenterZ = lastBandFarEdgeZ - GiantSlimeConfig.Z_OFFSET_PAST_LAST_BAND_STUDS
local groundPatchFootprint = GiantSlimeConfig.BODY_WIDTH_STUDS + 2 * GiantSlimeConfig.GROUND_PATCH_MARGIN_STUDS
local chestStripNearZ = slimeCenterZ + groundPatchFootprint / 2
local bodyNearZ = slimeCenterZ + GiantSlimeConfig.BODY_WIDTH_STUDS / 2
local chestZ = bodyNearZ + (chestStripNearZ - bodyNearZ) * TreasureConfig.CHEST_SETBACK_FRACTION

local returnZ = C.LaneConfig.SWING_PIVOT_Z + LaunchConfig.SWING_RETURN_CLEARANCE_STUDS
local remountStuds = math.max(0, (returnZ - C.LaneConfig.SWING_PIVOT_Z) - LaunchConfig.SWING_MOUNT_RADIUS_STUDS)
local remountSeconds = remountStuds / ASSUMED_WALK_SPEED

local function barWaitSeconds(p: number): number
	return PERIOD / 2 + (1 / p - 1) * PERIOD
end

local function cycleTermsFor(tier: number, hitRate: number)
	local facts = C.perfectLaunchForTier(tier)
	local flight = C.flightDurationForTier(tier)
	local reward
	if facts.zone == "past" then
		local walkStuds = math.max(0, math.abs(facts.landingZ - chestZ) - TreasureConfig.CHEST_PROMPT_DISTANCE_STUDS)
		reward = walkStuds / ASSUMED_WALK_SPEED
			+ TreasureConfig.CHEST_PROMPT_HOLD_SECONDS
			+ SlimeConfig.REVEAL_DISMISS_LOCKOUT_SECONDS
	else
		-- Presses may begin the instant the box exists, so the camera ease-in
		-- overlaps them rather than adding to them -- cycle_time.luau's own
		-- reasoning, reproduced.
		reward = math.max(LaunchConfig.BOX_CAMERA_TRANSITION_SECONDS, boxPressSeconds)
			+ SlimeConfig.REVEAL_BOX_TO_SLIME_DELAY_SECONDS
			+ SlimeConfig.REVEAL_DISMISS_LOCKOUT_SECONDS
			+ LaunchConfig.BOX_CAMERA_TRANSITION_SECONDS
	end
	local bar = barWaitSeconds(hitRate)
	return {
		zone = facts.zone,
		barWaitSeconds = bar,
		flightSeconds = flight,
		rewardSeconds = reward,
		returnSeconds = remountSeconds,
		totalCycleSeconds = bar + flight + reward + remountSeconds,
	}
end

--============================ The held-set growth ============================--
-- Same simulation kind as dev/analysis/slot_sim.luau and slot_sweep.luau (read,
-- not edited): the held set only changes when a roll BEATS the current worst
-- slot, and rolls are i.i.d., so the number of rolls to the next improvement is
-- geometric with q = P(income > worst). Sampling that gap directly is EXACT,
-- not an approximation of rolling one at a time.
--
-- POLICY, and it is optimal hand play rather than what the game does: keep the
-- best SLOT_COUNT slimes ever rolled, by BASE income. The game itself
-- auto-places into the first empty slot and never evicts (PlayerProfile.
-- receiveSlime), so a real player has to remove and place by hand to achieve
-- this. Every figure below is therefore a LOWER bound on real time.
--
-- WHAT THIS FILE RECORDS THAT THE PRIOR SIMS DID NOT: alongside total held base
-- income it tracks the best single held slime and two cumulative acquisition
-- streams, which is what lets the partial-leveller brackets be priced off the
-- same runs rather than a second simulation.
local GRID = { 0, 100, 1000, 10000, 20000 }

local function valueTable(pmf: { number })
	local byValue = {}
	for index, mass in pmf do
		if mass > 0 then
			local v = C.SlimeData.SLIMES[index].incomePerSecond
			byValue[v] = (byValue[v] or 0) + mass
		end
	end
	local values = {}
	for v in byValue do
		table.insert(values, v)
	end
	table.sort(values)
	local cumulative, tailAbove = {}, {}
	local running = 0
	for i, v in values do
		running += byValue[v]
		cumulative[i] = running
	end
	for i = 1, #values do
		cumulative[i] /= running
		tailAbove[i] = 1 - cumulative[i]
	end
	return { values = values, cumulative = cumulative, tailAbove = tailAbove, count = #values, max = values[#values] }
end

local function drawIndexAbove(vt, floorIndex: number): number
	local lowCdf = if floorIndex >= 1 then vt.cumulative[floorIndex] else 0
	local r = lowCdf + math.random() * (1 - lowCdf)
	local lo, hi = floorIndex + 1, vt.count
	while lo < hi do
		local mid = (lo + hi) // 2
		if r <= vt.cumulative[mid] then hi = mid else lo = mid + 1 end
	end
	return lo
end

-- Returns, per grid point: p50 and mean of total held base income, p50 and mean
-- of the best single held base income, and the MEAN cumulative acquisition
-- value streams (mean, because they feed a spend RATE and a median rate is not
-- a rate anyone pays).
local function simulate(vt, slots: number, runs: number)
	local G = #GRID
	local totalAt, bestAt = {}, {}
	local acqAt, bestAcqAt = {}, {}
	for g = 1, G do
		totalAt[g] = table.create(runs, 0)
		bestAt[g] = table.create(runs, 0)
		acqAt[g] = table.create(runs, 0)
		bestAcqAt[g] = table.create(runs, 0)
	end
	local counts = table.create(vt.count, 0)

	for run = 1, runs do
		for i = 1, vt.count do
			counts[i] = 0
		end
		local total, acq, bestAcq = 0, 0, 0
		local minIdx, maxIdx = vt.count, 1
		local n, g = 0, 1

		local function recordUpTo(untilRoll: number)
			while g <= G and GRID[g] <= untilRoll do
				totalAt[g][run] = total
				bestAt[g][run] = if n > 0 then vt.values[maxIdx] else 0
				acqAt[g][run] = acq
				bestAcqAt[g][run] = bestAcq
				g += 1
			end
		end
		recordUpTo(0)

		-- Fill phase: the first K rolls land in an empty slot (receiveSlime's
		-- first-empty-slot rule; no choice is involved).
		for _ = 1, slots do
			local idx = drawIndexAbove(vt, 0)
			counts[idx] += 1
			local v = vt.values[idx]
			total += v
			acq += v
			if idx < minIdx then
				minIdx = idx
			end
			if idx > maxIdx or n == 0 then
				maxIdx = math.max(maxIdx, idx)
				bestAcq += vt.values[maxIdx]
			end
			n += 1
			recordUpTo(n)
		end

		-- Replacement phase, jumping straight to each improving roll.
		while n < HORIZON do
			local q = vt.tailAbove[minIdx]
			if q <= 1e-15 then
				break -- the whole set is at the ceiling; nothing can beat it
			end
			local gap = math.ceil(math.log(math.random()) / math.log(1 - q))
			if gap < 1 then
				gap = 1
			end
			n += gap
			if n > HORIZON then
				break
			end
			local newIdx = drawIndexAbove(vt, minIdx)
			counts[minIdx] -= 1
			counts[newIdx] += 1
			local v = vt.values[newIdx]
			total += v - vt.values[minIdx]
			acq += v
			if newIdx > maxIdx then
				maxIdx = newIdx
				bestAcq += v
			end
			while counts[minIdx] == 0 do
				minIdx += 1
			end
			recordUpTo(n)
		end
		recordUpTo(HORIZON)
	end

	local function summarise(series)
		local sum = 0
		for run = 1, runs do
			sum += series[run]
		end
		local sorted = table.clone(series)
		table.sort(sorted)
		return {
			mean = sum / runs,
			p50 = sorted[math.clamp(math.floor(0.5 * runs + 0.5), 1, runs)],
		}
	end

	local stats = {}
	for g = 1, G do
		stats[g] = {
			n = GRID[g],
			total = summarise(totalAt[g]),
			best = summarise(bestAt[g]),
			acq = summarise(acqAt[g]),
			bestAcq = summarise(bestAcqAt[g]),
		}
	end
	return stats
end

--=========================== Affordability =============================--
-- THE NON-CIRCULAR INTEGRATION. From an empty base, at this tier's own
-- cadence: every roll, income (at the interpolated held-set curve, times this
-- bracket's multiplier) is banked for one cycle's worth of seconds, and this
-- bracket's levelling drain is paid. Stop when the next tier's price is met.
--
-- Curve points are the MEDIAN held base income at 0 / 100 / 1,000 / 10,000
-- rolls, linearly interpolated between them and FLAT past the last -- exactly
-- the four points and the same interpolation the prior pass used, so the
-- figures are comparable to it.
--
-- The drain is the bracket's own measured spend rate per roll at equilibrium:
-- (mean cumulative spend at 20,000 - at 10,000) / 10,000. Also the prior pass's
-- choice. It is a STEADY-STATE rate applied from roll 1, which understates the
-- early cost of the first fill (levelling ten fresh slimes at once) -- see the
-- fullCost sensitivity below, which prices the real cumulative curve instead.
local function interpolatedIncome(pts, n: number): number
	if n >= pts[#pts][1] then
		return pts[#pts][2]
	end
	for k = 1, #pts - 1 do
		local a, b = pts[k], pts[k + 1]
		if n <= b[1] then
			return a[2] + (b[2] - a[2]) * (n - a[1]) / (b[1] - a[1])
		end
	end
	return pts[#pts][2]
end

local ROLL_CAP = 50000000

-- Returns rolls needed, or nil if the price is unreachable at this bracket's
-- net rate. Past the last curve point income is constant, so the tail is solved
-- in closed form rather than iterated -- exact, and it is what makes the
-- hundreds-of-thousands-of-rolls unlevelled cases finite to compute.
local function affordRolls(pts, nextPrice: number, cycleSeconds: number, multiplier: number, drainPerRoll: number): number?
	local money = 0
	local flatFrom = pts[#pts][1]
	for n = 1, flatFrom do
		money += interpolatedIncome(pts, n) * multiplier * cycleSeconds - drainPerRoll
		if money >= nextPrice then
			return n
		end
	end
	local perRoll = pts[#pts][2] * multiplier * cycleSeconds - drainPerRoll
	if perRoll <= 0 then
		return nil
	end
	local extra = math.ceil((nextPrice - money) / perRoll)
	local total = flatFrom + extra
	if total > ROLL_CAP then
		return nil
	end
	return total
end

-- The fullCost sensitivity: the same integration, but paying the bracket's REAL
-- cumulative levelling bill as it falls (interpolated over the same grid)
-- rather than a flat equilibrium rate. Strictly more expensive early.
local function affordRollsFullCost(pts, spendPts, nextPrice: number, cycleSeconds: number, multiplier: number): number?
	local money = 0
	local flatFrom = pts[#pts][1]
	local previousSpend = 0
	for n = 1, flatFrom do
		local spend = interpolatedIncome(spendPts, n)
		money += interpolatedIncome(pts, n) * multiplier * cycleSeconds - (spend - previousSpend)
		previousSpend = spend
		if money >= nextPrice then
			return n
		end
	end
	local tailDrain = (spendPts[#spendPts][2] - spendPts[#spendPts - 1][2])
		/ (spendPts[#spendPts][1] - spendPts[#spendPts - 1][1])
	local perRoll = pts[#pts][2] * multiplier * cycleSeconds - tailDrain
	if perRoll <= 0 then
		return nil
	end
	local extra = math.ceil((nextPrice - money) / perRoll)
	local total = flatFrom + extra
	if total > ROLL_CAP then
		return nil
	end
	return total
end

--================================ Run it ================================--
math.randomseed(SEED)
print(string.format("commit %s | runs/tier %d | horizon %d | slots %d | tiers %d",
	commit, RUNS, HORIZON, SLOTS, TIERS))
print(string.format("MAX_LEVEL %d, growth %.2f -> maxed multiplier %.4fx, cost to max %.1fx base income/s, payback %ds",
	MAX_LEVEL, SlimeUpgradeConfig.UPGRADE_GROWTH_RATE, MULT_MAX, COST_TO_MAX, SlimeUpgradeConfig.UPGRADE_PAYBACK_SECONDS))
print(string.format("level 10 multiplier %.4fx, cost to L10 %.1fx base income/s\n", MULT_L10, COST_TO_L10))

local BRACKETS = {
	{ key = "never", label = "never levels" },
	{ key = "best", label = "best slime only, maxed" },
	{ key = "allL10", label = "all slimes to L10" },
	{ key = "allMax", label = "all slimes maxed" },
}

local tiers = {}
for tier = 1, TIERS do
	local facts = C.perfectLaunchForTier(tier)
	local pmf = if facts.zone == "past" then C.chestPmf() else C.rollPmfForBandLuck(facts.luck)
	local vt = valueTable(pmf)
	local stats = simulate(vt, SLOTS, RUNS)
	local byN = {}
	for _, s in stats do
		byN[s.n] = s
	end

	-- Income curves, one per bracket, over the four prior-pass grid points.
	-- `best` adds the maxed BEST slime's extra income on top of the base total;
	-- the two `all` brackets scale the whole total.
	local function curveFor(key: string)
		local pts = {}
		for i, n in { 0, 100, 1000, 10000 } do
			local s = byN[n]
			local income
			if key == "never" then
				income = s.total.p50
			elseif key == "allMax" then
				income = s.total.p50 * MULT_MAX
			elseif key == "allL10" then
				income = s.total.p50 * MULT_L10
			else
				income = s.total.p50 + (MULT_MAX - 1) * s.best.p50
			end
			pts[i] = { n, income }
		end
		return pts
	end

	local function spendCurveFor(key: string)
		local pts = {}
		for i, n in { 0, 100, 1000, 10000, 20000 } do
			local s = byN[n]
			local spend
			if key == "never" then
				spend = 0
			elseif key == "allMax" then
				spend = s.acq.mean * COST_TO_MAX
			elseif key == "allL10" then
				spend = s.acq.mean * COST_TO_L10
			else
				spend = s.bestAcq.mean * COST_TO_MAX
			end
			pts[i] = { n, spend }
		end
		return pts
	end

	local nextPrice = if tier < TIERS then ShopConfig.SWING_TIER_PRICES[tier + 1] else nil
	local entry = {
		tier = tier,
		zone = facts.zone,
		bandLuck = facts.luck,
		nextTierPrice = nextPrice,
		cycle = cycleTermsFor(tier, 1.0),
		cycleHit50 = cycleTermsFor(tier, 0.5),
		heldSet = {},
		brackets = {},
	}
	for _, n in GRID do
		local s = byN[n]
		entry.heldSet[tostring(n)] = {
			totalBaseIncomeP50 = s.total.p50,
			totalBaseIncomeMean = s.total.mean,
			bestSlimeIncomeP50 = s.best.p50,
			acquiredValueMean = s.acq.mean,
			bestAcquiredValueMean = s.bestAcq.mean,
		}
	end

	for _, bracket in BRACKETS do
		local pts = curveFor(bracket.key)
		local spendPts = spendCurveFor(bracket.key)
		local drain = (spendPts[5][2] - spendPts[4][2]) / (spendPts[5][1] - spendPts[4][1])
		local row = {
			label = bracket.label,
			incomeAt10000 = pts[4][2],
			drainPerRoll = drain,
			netPerRollAtEquilibrium = pts[4][2] * entry.cycle.totalCycleSeconds - drain,
		}
		if nextPrice then
			local cs = entry.cycle.totalCycleSeconds
			local rolls = affordRolls(pts, nextPrice, cs, 1, drain)
			row.rolls = rolls
			row.hours = if rolls then rolls * cs / 3600 else nil
			local rollsFull = affordRollsFullCost(pts, spendPts, nextPrice, cs, 1)
			row.rollsFullCost = rollsFull
			row.hoursFullCost = if rollsFull then rollsFull * cs / 3600 else nil
			local rolls50 = affordRolls(pts, nextPrice, entry.cycleHit50.totalCycleSeconds, 1, drain)
			row.hoursHit50 = if rolls50 then rolls50 * entry.cycleHit50.totalCycleSeconds / 3600 else nil
		end
		entry.brackets[bracket.key] = row
	end

	tiers[tier] = entry
	print(string.format("tier %2d  zone %-5s  cycle %5.2fs  next $%s  p50 income @1k $%s  @10k $%s",
		tier, facts.zone, entry.cycle.totalCycleSeconds,
		if nextPrice then C.fmt(nextPrice) else "n/a",
		C.fmt(byN[1000].total.p50), C.fmt(byN[10000].total.p50)))
end

--================================ Tables ================================--
local function hoursOf(tier: number, key: string): number?
	return tiers[tier].brackets[key].hours
end

print("\n=== Time to afford the NEXT tier, from an empty base, perfect play (hours) ===")
print("step        never    bestOnly   allL10    allMax   |  never/allMax")
local totals = { never = 0, best = 0, allL10 = 0, allMax = 0 }
local anyMissing = false
for tier = 1, TIERS - 1 do
	local n, b, l, m = hoursOf(tier, "never"), hoursOf(tier, "best"), hoursOf(tier, "allL10"), hoursOf(tier, "allMax")
	if n and b and l and m then
		totals.never += n
		totals.best += b
		totals.allL10 += l
		totals.allMax += m
	else
		anyMissing = true
	end
	print(string.format("%2d -> %2d  %9.2f  %9.2f  %8.2f  %8.2f  |  %8.1fx",
		tier, tier + 1, n or 0 / 0, b or 0 / 0, l or 0 / 0, m or 0 / 0, (n or 0) / (m or 1)))
end
print(string.format("TOTAL     %9.2f  %9.2f  %8.2f  %8.2f  |  %8.1fx",
	totals.never, totals.best, totals.allL10, totals.allMax, totals.never / totals.allMax))
print(string.format("gap (never - allMax) = %.2f h;  never / allMax = %.2fx", totals.never - totals.allMax, totals.never / totals.allMax))

print("\n=== Hours LOST per step by never levelling (never - allMax) ===")
print("step       lost(h)   lost(min)   cumulative(h)  share of total")
local cumulative = 0
local lostTotal = totals.never - totals.allMax
local firstBigLoss = nil
for tier = 1, TIERS - 1 do
	local n, m = hoursOf(tier, "never"), hoursOf(tier, "allMax")
	if n and m then
		local lost = n - m
		cumulative += lost
		if lost > 0.5 and firstBigLoss == nil then
			firstBigLoss = { step = tier, toTier = tier + 1, lostHours = lost, lostMinutes = lost * 60 }
		end
		print(string.format("%2d -> %2d  %9.2f  %10.1f  %13.2f  %13.1f%%",
			tier, tier + 1, lost, lost * 60, cumulative, 100 * cumulative / lostTotal))
	end
end
if firstBigLoss then
	print(string.format("first step losing MORE THAN 30 MINUTES: tier %d -> %d (%.0f min behind)",
		firstBigLoss.step, firstBigLoss.toTier, firstBigLoss.lostMinutes))
end

print("\n=== Sensitivity: hit50 play, and levelling paid at its real cumulative cost ===")
print("step      never(hit50)  allMax(hit50)  |  never(full)  allMax(full)")
for tier = 1, TIERS - 1 do
	local t = tiers[tier]
	print(string.format("%2d -> %2d  %12.2f  %13.2f  |  %11.2f  %12.2f",
		tier, tier + 1,
		t.brackets.never.hoursHit50 or 0 / 0, t.brackets.allMax.hoursHit50 or 0 / 0,
		t.brackets.never.hoursFullCost or 0 / 0, t.brackets.allMax.hoursFullCost or 0 / 0))
end

--=========================== The exchange rate ===========================--
-- STEP 3a, verified against the live constants rather than restated.
local PAYBACK = SlimeUpgradeConfig.UPGRADE_PAYBACK_SECONDS
local RATE = SlimeUpgradeConfig.UPGRADE_GROWTH_RATE
local exchange = {}
do
	print("\n=== The exchange rate, checked against the live constants ===")
	local probes = { 1, 7.5, 350, 12000, 350000 }
	local worst = 0
	for _, income in probes do
		local cost = SlimeUpgrade.totalUpgradeCost(income, 1, 1)
		local gain = SlimeUpgrade.incomeForLevel(income, 2) - income
		local dollarsPerIncome = cost / gain
		worst = math.max(worst, math.abs(dollarsPerIncome - PAYBACK))
		print(string.format("  income %10s/s -> one level costs $%-12s buys +%-10s/s -> $%.4f per +1 income/s (payback %.2f s)",
			C.fmt(income), C.fmt(cost), C.fmt(gain), dollarsPerIncome, cost / gain))
	end
	-- And for a MULTI-level purchase, where the growth rate cancels too.
	local multi = SlimeUpgrade.totalUpgradeCost(100, 1, 12)
	local multiGain = SlimeUpgrade.incomeForLevel(100, 13) - 100
	print(string.format("  12 levels at once from $100/s: cost $%s, gain +%s/s -> $%.4f per +1 income/s",
		C.fmt(multi), C.fmt(multiGain), multi / multiGain))
	exchange = {
		paybackSeconds = PAYBACK,
		growthRate = RATE,
		costMultipleOfCurrentIncome = PAYBACK * RATE,
		dollarsPerPlusOneIncomePerSecond = PAYBACK,
		maxLevelMultiplier = MULT_MAX,
		costToMaxAsMultipleOfBaseIncome = COST_TO_MAX,
		singleLevelIdentityMaxError = worst,
		multiLevelDollarsPerIncome = multi / multiGain,
	}
	print(string.format("  identity holds to %.3g across every probe", worst))
end

print("\n=== The held-set growth curve the integration runs along (median base income/s) ===")
print("tier      @0      @100      @1k      @10k     @20k   |  best slime @1k")
for tier = 1, TIERS do
	local h = tiers[tier].heldSet
	print(string.format("%4d  %6s  %8s  %8s  %8s  %8s   |  %s",
		tier, C.fmt(h["0"].totalBaseIncomeP50), C.fmt(h["100"].totalBaseIncomeP50),
		C.fmt(h["1000"].totalBaseIncomeP50), C.fmt(h["10000"].totalBaseIncomeP50),
		C.fmt(h["20000"].totalBaseIncomeP50), C.fmt(h["1000"].bestSlimeIncomeP50)))
end

--=================== One level, seen from the player's side ===================--
-- STEP 3c. Payback is 600 seconds of that slime's own production at EVERY tier
-- and level, by construction (verified above). What varies with tier is how
-- much of the WHOLE BASE's income one level moves, which is what a player
-- watching a money counter rather than a slime's own label would have to
-- detect.
print("\n=== What one level actually changes (step 3c) ===")
print("tier   typical slime/s   +1 level adds/s   share of base income   payback(s)")
local observability = {}
for tier = 1, TIERS do
	local h = tiers[tier].heldSet["1000"]
	local typicalSlime = h.totalBaseIncomeP50 / SLOTS
	local delta = SlimeUpgradeConfig.UPGRADE_GROWTH_RATE * typicalSlime
	local share = if h.totalBaseIncomeP50 > 0 then delta / h.totalBaseIncomeP50 else 0
	local bestDelta = SlimeUpgradeConfig.UPGRADE_GROWTH_RATE * h.bestSlimeIncomeP50
	observability[tier] = {
		typicalSlimeIncomeP50 = typicalSlime,
		oneLevelAddsPerSecond = delta,
		shareOfBaseIncome = share,
		oneLevelOnBestAddsPerSecond = bestDelta,
		shareOfBaseIncomeIfBest = if h.totalBaseIncomeP50 > 0 then bestDelta / h.totalBaseIncomeP50 else 0,
		paybackSeconds = SlimeUpgradeConfig.UPGRADE_PAYBACK_SECONDS,
	}
	print(string.format("%4d  %15s  %16s  %20.2f%%  %10d",
		tier, C.fmt(typicalSlime) .. "/s", "+" .. C.fmt(delta) .. "/s", 100 * share,
		SlimeUpgradeConfig.UPGRADE_PAYBACK_SECONDS))
end

--================== Levelling vs saving, per tier (step 3d) ==================--
-- At a given tier, a player holding $X can either buy levels (which return
-- X / 600 income/s, permanently, immediately) or hoard toward the next swing
-- tier. The comparison that decides it is the next tier's PRICE against the
-- income the same money buys as levels -- and levelling is capped by how much
-- levelling capacity the held set has left.
print("\n=== Levelling capacity against the next tier's price (step 3d) ===")
print("tier  next price     capacity to max all 10   income if spent on levels   price/capacity")
local capacity = {}
for tier = 1, TIERS - 1 do
	local t = tiers[tier]
	local held = t.heldSet["1000"].totalBaseIncomeP50
	local cap = held * COST_TO_MAX
	local price = t.nextTierPrice
	capacity[tier] = {
		heldBaseIncomeP50At1000 = held,
		capacityToMaxAll = cap,
		nextTierPrice = price,
		priceOverCapacity = price / cap,
	}
	print(string.format("%4d  $%-12s  $%-22s  +%-24s  %.2fx",
		tier, C.fmt(price), C.fmt(cap), C.fmt(cap / PAYBACK) .. "/s", price / cap))
end

--============ Levels against the tier, per dollar (steps 3b and 3d) ============--
-- THE COMPARISON A PLAYER WOULD HAVE TO MAKE, priced out. Both sides are
-- "income/s bought per dollar spent":
--
--   LEVELS   exactly 1 / UPGRADE_PAYBACK_SECONDS = 1/600 per dollar, always,
--            at every tier and every level -- immediate, and capped only by how
--            much levelling capacity the held set has left.
--   THE TIER  the equilibrium held-set income at tier t+1 minus at tier t,
--            divided by the tier's price. NOT immediate: the new income only
--            arrives after re-rolling the whole held set at the new tier, which
--            is thousands of rolls (see the growth curve above). Treating it as
--            immediate is generous to the tier, which is the safe direction for
--            a claim that levels win.
print("\n=== Income/s bought per dollar: levels against the next tier (steps 3b, 3d) ===")
print("step      tier gain/s   price      tier $/income   levels $/income   winner (x better)")
local perDollar = {}
for tier = 1, TIERS - 1 do
	local a = tiers[tier].heldSet["10000"].totalBaseIncomeP50
	local b = tiers[tier + 1].heldSet["10000"].totalBaseIncomeP50
	local gain = b - a
	local price = tiers[tier].nextTierPrice
	local tierDollarsPerIncome = if gain > 0 then price / gain else math.huge
	local levelDollarsPerIncome = SlimeUpgradeConfig.UPGRADE_PAYBACK_SECONDS
	local ratio = tierDollarsPerIncome / levelDollarsPerIncome
	perDollar[tier] = {
		equilibriumIncomeAtTier = a,
		equilibriumIncomeAtNextTier = b,
		tierIncomeGain = gain,
		nextTierPrice = price,
		tierDollarsPerIncomePerSecond = tierDollarsPerIncome,
		levelDollarsPerIncomePerSecond = levelDollarsPerIncome,
		levelsBetterByFactor = ratio,
		winner = if ratio > 1 then "levels" else "tier",
	}
	print(string.format("%2d -> %2d  %11s  %-9s  $%-13s  $%-15d  %s (%.1fx)",
		tier, tier + 1, "+" .. C.fmt(gain) .. "/s", "$" .. C.fmt(price),
		C.fmt(tierDollarsPerIncome), levelDollarsPerIncome,
		if ratio > 1 then "levels" else "TIER", if ratio > 1 then ratio else 1 / ratio))
end

--================================ Output ================================--
if not fs.isDir("dev/out") then
	fs.writeDir("dev/out")
end
local out = {
	gitCommit = commit,
	generatedBy = "dev/analysis/levelling_gap.luau",
	runsPerTier = RUNS,
	horizonRolls = HORIZON,
	slots = SLOTS,
	tierCount = TIERS,
	playerModel = "perfect (bar wait = PERIOD/2); hit50 reported per tier as hoursHit50",
	method = "non-circular integration along the measured held-set growth curve from an empty base; medians at 0/100/1000/10000 rolls, linearly interpolated, flat past the last; banked at the tier's own cycle time; drain = measured equilibrium levelling spend per roll",
	exchangeRate = exchange,
	brackets = {
		never = { multiplier = 1, costPerBaseIncome = 0 },
		best = { multiplier = MULT_MAX, appliesTo = "best held slime only", costPerBaseIncome = COST_TO_MAX },
		allL10 = { level = L10, multiplier = MULT_L10, costPerBaseIncome = COST_TO_L10 },
		allMax = { level = MAX_LEVEL, multiplier = MULT_MAX, costPerBaseIncome = COST_TO_MAX },
	},
	totalsHours = {
		never = totals.never,
		best = totals.best,
		allL10 = totals.allL10,
		allMax = totals.allMax,
		gapHours = totals.never - totals.allMax,
		ratio = totals.never / totals.allMax,
		anyStepUnreachable = anyMissing,
	},
	levellingCapacity = capacity,
	oneLevelObservability = observability,
	incomePerDollar = perDollar,
	firstStepLosingMoreThan30Minutes = firstBigLoss,
	tiers = tiers,
}
fs.writeFile("dev/out/levelling_gap.json", serde.encode("json", out, true))
print("\nwrote dev/out/levelling_gap.json  (commit " .. commit .. ")")
