-- STEPS 2-5 of the swing-tier economy measurement: the 10-slot policy, the
-- level-reset drain, the $600-per-income/s exchange rate, and the comparison
-- against the geometric ramp the price ladder was derived from. See REPORT.md.
--
-- V2: a copy of dev/analysis/slot_sim.luau with only its two hardcoded paths
-- moved -- it READS dev/out/roll_ev_v2.json and WRITES
-- dev/out/roll_economics_v2.json. Both originals are read-only baseline
-- artifacts describing commit e12ca51. Seed, sample counts and every formula
-- are untouched.
--
--   lune run dev/analysis/slot_sim_v2.luau [runsPerTier]
--
-- Run from the REPO ROOT, AFTER dev/analysis/roll_ev_v2.luau (this reads
-- dev/out/roll_ev_v2.json for the sampled per-roll figures and the seed).
-- Writes dev/out/roll_economics_v2.json.
--
-- ===== WHY THIS IS EVENT-DRIVEN RATHER THAN ROLL-BY-ROLL. The held set only
-- ever changes when a roll BEATS the current worst slot, and rolls are i.i.d.,
-- so the number of rolls until the next improvement is geometric with
-- q = P(income > worst). Sampling that gap directly is EXACT -- not an
-- approximation of rolling one at a time -- and turns 10,000 runs x 10,000
-- rolls into a few dozen events per run instead of 100,000,000 draws.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local C = require("./common")

local RUNS = tonumber(process.args[1]) or 10000
local HORIZON = 10000 -- rolls simulated per run; the N=5000 window needs 10000
local SEED = 20260811

local rollEv = serde.decode("json", fs.readFile("dev/out/roll_ev_v2.json"))

local COST_TO_MAX = C.costToMaxMultiplier() -- seconds of base income, derived
local MAX_MULT = C.maxLevelMultiplier()

-- Horizons the tier comparison is repeated at. The 10,000-roll figure is the
-- "equilibrium" the brief asks for, but see REPORT.md: every tier converges to
-- the SAME ceiling given enough rolls, so the shorter horizons are where the
-- tiers actually differ from each other.
local HORIZONS = { 100, 1000, 10000 }

--========================= The grid we sample runs on =========================--
local grid = {}
do
	local seen = {}
	local function add(n)
		if n >= 1 and n <= HORIZON and not seen[n] then
			seen[n] = true
			table.insert(grid, n)
		end
	end
	for n = 1, 24 do add(n) end
	for _, n in { 10, 50, 100, 500, 1000, 5000 } do
		add(n - 1); add(n); add(2 * n)
	end
	local x = 25.0
	while x <= HORIZON do
		add(math.floor(x + 0.5))
		x *= 1.15
	end
	add(HORIZON)
	table.sort(grid)
end
local GRID_N = #grid

--============================ Sampling machinery ============================--
-- Collapses a 65-entry slime PMF into distinct income values (ascending) with
-- their masses -- everything the policy needs is the income, and duplicates
-- would only make the threshold comparisons longer.
local function valueTable(pmf: { number })
	local byValue = {}
	for index, p in pmf do
		if p > 0 then
			local v = C.SlimeData.SLIMES[index].incomePerSecond
			byValue[v] = (byValue[v] or 0) + p
		end
	end
	local values = {}
	for v in byValue do
		table.insert(values, v)
	end
	table.sort(values)
	local mass, cumulative = {}, {}
	local running = 0
	for i, v in values do
		mass[i] = byValue[v]
		running += byValue[v]
		cumulative[i] = running
	end
	-- Normalise away float drift so the last cumulative is exactly 1.
	for i = 1, #cumulative do
		cumulative[i] /= running
	end
	return { values = values, mass = mass, cumulative = cumulative, count = #values }
end

local function drawIndexAbove(vt, floorIndex: number): number
	-- Uniform draw restricted to values strictly above values[floorIndex].
	local lowCdf = if floorIndex >= 1 then vt.cumulative[floorIndex] else 0
	local r = lowCdf + math.random() * (1 - lowCdf)
	local lo, hi = floorIndex + 1, vt.count
	while lo < hi do
		local mid = (lo + hi) // 2
		if r <= vt.cumulative[mid] then hi = mid else lo = mid + 1 end
	end
	return lo
end

local function drawIndex(vt): number
	return drawIndexAbove(vt, 0)
end

--=============================== The simulation ===============================--
-- Policy: keep the best SLOT_COUNT slimes ever rolled, by base income/s.
-- See REPORT.md step 0c -- the GAME does not do this automatically; this is the
-- best a player can do by hand with placeFromInventory/removeToInventory.
local function simulateTier(pmf: { number })
	local vt = valueTable(pmf)
	local slots = C.SLOT_COUNT
	local incomeAt = {} -- [gridIndex] = array of per-run values
	local spendAt = {}
	for g = 1, GRID_N do
		incomeAt[g] = table.create(RUNS, 0)
		spendAt[g] = table.create(RUNS, 0)
	end

	local held = table.create(slots, 0) -- ascending, held[1] is the worst
	for run = 1, RUNS do
		table.clear(held)
		local total, spend = 0, 0
		local g = 1
		local n = 0

		local function recordUpTo(untilRoll: number)
			while g <= GRID_N and grid[g] <= untilRoll do
				incomeAt[g][run] = total
				spendAt[g][run] = spend
				g += 1
			end
		end

		-- Fill phase: the first SLOT_COUNT rolls always land in an empty slot
		-- (PlayerProfile.receiveSlime -- first empty slot, no choice involved).
		for _ = 1, slots do
			local idx = drawIndex(vt)
			local v = vt.values[idx]
			n += 1
			total += v
			spend += COST_TO_MAX * v
			-- insert into the ascending held array
			local pos = #held + 1
			table.insert(held, v)
			while pos > 1 and held[pos - 1] > held[pos] do
				held[pos - 1], held[pos] = held[pos], held[pos - 1]
				pos -= 1
			end
			recordUpTo(n)
		end

		-- Replacement phase, jumping straight to each improving roll.
		while n < HORIZON do
			local worst = held[1]
			-- index of the largest value <= worst
			local lo, hi = 1, vt.count
			while lo < hi do
				local mid = (lo + hi + 1) // 2
				if vt.values[mid] <= worst then lo = mid else hi = mid - 1 end
			end
			local floorIndex = lo
			local q = 1 - vt.cumulative[floorIndex]
			if q <= 1e-15 then
				break -- nothing left in the distribution can beat the worst slot
			end
			local gap = math.ceil(math.log(math.random()) / math.log(1 - q))
			if gap < 1 then
				gap = 1
			end
			n += gap
			if n > HORIZON then
				break
			end
			local v = vt.values[drawIndexAbove(vt, floorIndex)]
			total += v - held[1]
			spend += COST_TO_MAX * v
			held[1] = v
			local pos = 1
			while pos < slots and held[pos] > held[pos + 1] do
				held[pos], held[pos + 1] = held[pos + 1], held[pos]
				pos += 1
			end
			recordUpTo(n)
		end
		recordUpTo(HORIZON)
	end

	-- Per-grid-point statistics.
	local stats = {}
	for g = 1, GRID_N do
		local incomes = incomeAt[g]
		local spends = spendAt[g]
		local meanIncome, meanSpend = 0, 0
		for run = 1, RUNS do
			meanIncome += incomes[run]
			meanSpend += spends[run]
		end
		table.sort(incomes)
		table.sort(spends)
		local function pct(sorted, p)
			local i = math.clamp(math.floor(p * RUNS + 0.5), 1, RUNS)
			return sorted[i]
		end
		stats[g] = {
			n = grid[g],
			meanIncome = meanIncome / RUNS,
			medianIncome = pct(incomes, 0.5),
			p10Income = pct(incomes, 0.10),
			p90Income = pct(incomes, 0.90),
			meanSpend = meanSpend / RUNS,
			medianSpend = pct(spends, 0.5),
		}
	end
	local maxValue = vt.values[vt.count]
	return stats, maxValue
end

local function statAt(stats, n: number)
	for _, s in stats do
		if s.n == n then
			return s
		end
	end
	return nil
end

--=========================== Run every swing tier ===========================--
math.randomseed(SEED)
local tierResults = {}
print(string.format("runs/tier = %d, horizon = %d rolls, slots = %d, costToMax = %.4f s of base income",
	RUNS, HORIZON, C.SLOT_COUNT, COST_TO_MAX))

for tier = 1, C.SWING_TIER_COUNT do
	local facts = C.perfectLaunchForTier(tier)
	local isChest = facts.zone == "past"
	local pmf = if isChest then C.chestPmf() else C.rollPmfForBandLuck(facts.luck)
	local stats, maxValue = simulateTier(pmf)

	local final = stats[GRID_N]
	local equilibrium = final.medianIncome
	local function rollsToFraction(f: number): number?
		for _, s in stats do
			if s.medianIncome >= f * equilibrium then
				return s.n
			end
		end
		return nil
	end

	-- Marginal value, two ways (see REPORT.md): the single-roll difference in
	-- the MEAN (noisy at large N, since improvements are rare and large), and
	-- the average per-roll gain over the window [N, 2N), which is what the
	-- "stops paying" question actually wants.
	local function pointMarginal(n: number): number?
		local a, b = statAt(stats, n - 1), statAt(stats, n)
		if not a or not b then return nil end
		return b.meanIncome - a.meanIncome
	end
	local function windowMarginal(n: number): number?
		local a, b = statAt(stats, n), statAt(stats, 2 * n)
		if not a or not b then return nil end
		return (b.meanIncome - a.meanIncome) / n
	end

	-- First grid point where the forward per-roll gain rate falls under 1% of
	-- equilibrium income/s. AS SPECIFIED this is degenerate -- one roll can
	-- never be worth 1% of a ten-slot equilibrium once the set is any good, so
	-- it fires at the very first grid point for every tier -- so the same
	-- crossing measured against the income the player ACTUALLY holds at that
	-- moment is computed alongside it, which is the diminishing-returns
	-- question the brief is really asking.
	local stopsPaying, stopsPayingRelative = nil, nil
	for g = 1, GRID_N - 1 do
		local rate = (stats[g + 1].meanIncome - stats[g].meanIncome) / (stats[g + 1].n - stats[g].n)
		if stopsPaying == nil and rate < 0.01 * equilibrium then
			stopsPaying = stats[g].n
		end
		if stopsPayingRelative == nil and stats[g].meanIncome > 0 and rate < 0.01 * stats[g].meanIncome then
			stopsPayingRelative = stats[g].n
		end
	end

	-- ===== Step 3: the level-reset drain. Every placement arrives at level 1
	-- (PlayerProfile.receiveSlime:868 / placeFromInventory:910) and the old
	-- level is discarded (removeToInventory:942), so re-maxing costs
	-- COST_TO_MAX x the new slime's BASE income, every time.
	local spendPer1000 = statAt(stats, 1000).meanSpend
	local half = statAt(stats, HORIZON // 2)
	local spendPerRollAtEq = (final.meanSpend - half.meanSpend) / (HORIZON - half.n)

	-- The same held-set value read at several roll budgets, because the
	-- 10,000-roll number saturates at the game's ceiling for the upper tiers.
	local byHorizon = {}
	for _, n in HORIZONS do
		local s = statAt(stats, n)
		local halfStat = statAt(stats, n // 2)
		byHorizon[tostring(n)] = {
			rolls = n,
			mean = s.meanIncome,
			median = s.medianIncome,
			p10 = s.p10Income,
			p90 = s.p90Income,
			meanRemaxSpend = s.meanSpend,
			meanRemaxSpendAtHalf = halfStat and halfStat.meanSpend or 0,
		}
	end

	tierResults[tier] = {
		swingTier = tier,
		incomeByHorizon = byHorizon,
		luckValue = facts.luck,
		zone = facts.zone,
		bandIndex = facts.bandIndex,
		visualScale = facts.scale,
		distanceScale = facts.tierScale,
		launchDistanceStuds = facts.distance,
		landingZ = facts.landingZ,
		distanceFromBandZero = facts.distanceFromStart,
		rewardSource = if isChest then "chest" else "mysteryBox",
		price = C.ShopConfig.SWING_TIER_PRICES[tier],
		rawExpectedIncomePerRoll = rollEv.tiers[tier].sampledExpectedIncome,
		analyticExpectedIncomePerRoll = rollEv.tiers[tier].analyticExpectedIncome,
		equilibriumIncomePerSecond = equilibrium,
		equilibriumMean = final.meanIncome,
		equilibriumP10 = final.p10Income,
		equilibriumP90 = final.p90Income,
		asymptoteIncomePerSecond = C.SLOT_COUNT * maxValue,
		rollsTo50Percent = rollsToFraction(0.5),
		rollsTo90Percent = rollsToFraction(0.9),
		rollsTo99Percent = rollsToFraction(0.99),
		marginalPoint = {
			n10 = pointMarginal(10), n50 = pointMarginal(50), n100 = pointMarginal(100),
			n500 = pointMarginal(500), n1000 = pointMarginal(1000), n5000 = pointMarginal(5000),
		},
		marginalWindow = {
			n10 = windowMarginal(10), n50 = windowMarginal(50), n100 = windowMarginal(100),
			n500 = windowMarginal(500), n1000 = windowMarginal(1000), n5000 = windowMarginal(5000),
		},
		marginalBelowOnePercentAtRoll = stopsPaying,
		marginalBelowOnePercentOfCurrentAtRoll = stopsPayingRelative,
		remaxSpendFirst1000Rolls = spendPer1000,
		remaxSpendPerRollAtEquilibrium = spendPerRollAtEq,
		grossIncomePerSecondMaxed = equilibrium * MAX_MULT,
		levellingCapacityCost = COST_TO_MAX * equilibrium,
	}
	print(string.format("tier %2d  eq(base) $%s  [p10 $%s, p90 $%s]  asymptote $%s  rolls->90%% %s  remax/roll@eq $%s",
		tier, C.fmt(equilibrium), C.fmt(final.p10Income), C.fmt(final.p90Income),
		C.fmt(C.SLOT_COUNT * maxValue), tostring(tierResults[tier].rollsTo90Percent), C.fmt(spendPerRollAtEq)))
end

--============ Step 3b: launch cadence, the one thing config can bound ============--
-- Rolls per second is NOT derivable from the source: it needs the player's own
-- click latency and walk-back time. What IS derivable is a FLOOR on the cycle,
-- from the delays the server itself imposes. Using the floor makes every drain
-- figure below an UPPER bound.
local baseDistance = C.LaunchConfig.DISTANCE_PER_MULTIPLIER * C.LaunchConfig.SWEET_SPOT_MULTIPLIER
local expectedPresses = 1 / (1 - C.BOX_P) -- E[D] + 1 presses to resolve a box
for tier = 1, C.SWING_TIER_COUNT do
	local r = tierResults[tier]
	local facts = C.perfectLaunchForTier(tier)
	local flight = C.LaunchConfig.FLIGHT_DURATION_SECONDS
		* (facts.distance / baseDistance) ^ C.LaunchConfig.FLIGHT_DURATION_EXPONENT
	local boxSeconds = if r.rewardSource == "chest" then 0 else expectedPresses * C.LaunchConfig.BOX_PRESS_COOLDOWN_SECONDS
	local revealSeconds = if r.rewardSource == "chest" then 0 else C.SlimeConfig.REVEAL_BOX_TO_SLIME_DELAY_SECONDS
	local cycleFloor = flight + boxSeconds + revealSeconds + C.LaunchConfig.RESET_DELAY
	r.cycleSecondsFloor = cycleFloor
	r.remaxDrainDollarsPerSecond = r.remaxSpendPerRollAtEquilibrium / cycleFloor
	r.remaxDrainFraction = r.remaxDrainDollarsPerSecond / r.grossIncomePerSecondMaxed
	r.realisedIncomePerSecond = r.grossIncomePerSecondMaxed - r.remaxDrainDollarsPerSecond

	-- The same three quantities at each shorter roll budget, since the
	-- 10,000-roll figures above are saturated for half the ladder.
	for _, n in HORIZONS do
		local h = r.incomeByHorizon[tostring(n)]
		local spendRate = (h.meanRemaxSpend - h.meanRemaxSpendAtHalf) / (n - n // 2)
		h.grossMaxedIncomePerSecond = h.median * MAX_MULT
		h.remaxSpendPerRoll = spendRate
		h.remaxDrainDollarsPerSecond = spendRate / cycleFloor
		h.remaxDrainFraction = h.remaxDrainDollarsPerSecond / h.grossMaxedIncomePerSecond
		h.realisedIncomePerSecond = h.grossMaxedIncomePerSecond - h.remaxDrainDollarsPerSecond
		h.levellingCapacityCost = COST_TO_MAX * h.median
	end
end

--============== Step 4: the $600-per-income/s exchange rate check ==============--
local worstDeviation = 0
for _, slime in C.SlimeData.SLIMES do
	for level = 1, C.SlimeUpgradeConfig.MAX_LEVEL - 1 do
		for count = 1, C.SlimeUpgradeConfig.MAX_LEVEL - level do
			local cost = C.SlimeUpgrade.totalUpgradeCost(slime.incomePerSecond, level, count)
			local gain = C.SlimeUpgrade.incomeForLevel(slime.incomePerSecond, level + count)
				- C.SlimeUpgrade.incomeForLevel(slime.incomePerSecond, level)
			local dollarsPerIncome = cost / gain
			local deviation = math.abs(dollarsPerIncome - C.SlimeUpgradeConfig.UPGRADE_PAYBACK_SECONDS)
			if deviation > worstDeviation then
				worstDeviation = deviation
			end
		end
	end
end
print(string.format("\n$/income-per-second across all 65 slimes x every (level, count): %s, worst deviation %.3e",
	tostring(C.SlimeUpgradeConfig.UPGRADE_PAYBACK_SECONDS), worstDeviation))

-- The comparison table, once per roll budget. The 10,000-roll pass is the
-- headline "equilibrium" one and is written into the top level of each tier
-- entry; the shorter budgets are kept alongside it under exchangeByHorizon.
for _, horizon in HORIZONS do
	print(string.format("\n== roll budget %d ==", horizon))
	print("tier  price      dRealised/s   implied$     ratio      payback(s)   payback(h)  capacity$   nextTier/capacity")
	for tier = 2, C.SWING_TIER_COUNT do
		local r, prev = tierResults[tier], tierResults[tier - 1]
		local hr, hp = r.incomeByHorizon[tostring(horizon)], prev.incomeByHorizon[tostring(horizon)]
		local delta = hr.realisedIncomePerSecond - hp.realisedIncomePerSecond
		local implied = delta * C.SlimeUpgradeConfig.UPGRADE_PAYBACK_SECONDS
		local ratio = if implied ~= 0 then r.price / implied else nil
		local payback = if delta ~= 0 then r.price / delta else nil
		local capacityMultiple = r.price / hp.levellingCapacityCost
		r.exchangeByHorizon = r.exchangeByHorizon or {}
		r.exchangeByHorizon[tostring(horizon)] = {
			deltaRealisedIncomePerSecond = delta,
			impliedPriceAtExchangeRate = implied,
			priceToImpliedRatio = ratio,
			paybackSeconds = payback,
			previousTierLevellingCapacityCost = hp.levellingCapacityCost,
			priceOverPreviousCapacity = capacityMultiple,
		}
		if horizon == HORIZON then
			r.deltaRealisedIncomePerSecond = delta
			r.impliedPriceAtExchangeRate = implied
			r.priceToImpliedRatio = ratio
			r.paybackSeconds = payback
			prev.nextTierPriceOverCapacity = capacityMultiple
		end
		print(string.format("%4d  %-9s  %-12s  %-11s  %-9s  %-11s  %-10s  %-10s  %s",
			tier, C.fmt(r.price), C.fmt(delta), C.fmt(implied),
			ratio and string.format("%.4g", ratio) or "n/a",
			payback and C.fmt(payback) or "n/a",
			payback and string.format("%.3g", payback / 3600) or "n/a",
			C.fmt(hp.levellingCapacityCost), string.format("%.3g", capacityMultiple)))
	end
end

--=========== Step 5: the ramp the prices were actually derived from ===========--
-- ShopConfig's own model: ten filled slots earning the expected income of the
-- tier distribution at that tier's post-box luck, times a level multiplier of
-- 28.6252 ^ ((tier - 1) / 4), saturating at the max multiplier.
print("\ntier  rampMult  modelIncome/s   realised@100    realised@1000   realised@10000  m/model@100  @1000   @10000")
for tier = 1, C.SWING_TIER_COUNT do
	local r = tierResults[tier]
	local rampMultiplier = math.min(MAX_MULT ^ ((tier - 1) / 4), MAX_MULT)
	local modelIncome = C.SLOT_COUNT * r.analyticExpectedIncomePerRoll * rampMultiplier
	r.modelRampMultiplier = rampMultiplier
	r.modelIncomePerSecond = modelIncome
	r.measuredOverModel = r.realisedIncomePerSecond / modelIncome
	r.measuredOverModelByHorizon = {}
	for _, n in HORIZONS do
		r.measuredOverModelByHorizon[tostring(n)] = r.incomeByHorizon[tostring(n)].realisedIncomePerSecond / modelIncome
	end
	print(string.format("%4d  %-8.3f  %-14s  %-14s  %-14s  %-14s  %-11.4g  %-6.4g  %.4g",
		tier, rampMultiplier, C.fmt(modelIncome),
		C.fmt(r.incomeByHorizon["100"].realisedIncomePerSecond),
		C.fmt(r.incomeByHorizon["1000"].realisedIncomePerSecond),
		C.fmt(r.incomeByHorizon["10000"].realisedIncomePerSecond),
		r.measuredOverModelByHorizon["100"], r.measuredOverModelByHorizon["1000"], r.measuredOverModelByHorizon["10000"]))
end

--=================================== Output ===================================--
local slimes = {}
for _, s in C.SlimeData.SLIMES do
	table.insert(slimes, { id = s.globalIndex, name = s.name, tier = s.tier, tierName = s.tierName, baseIncomePerSecond = s.incomePerSecond })
end

local commit = (process.exec("git", { "rev-parse", "HEAD" }).stdout:gsub("%s+$", ""))

local out = {
	slimes = slimes,
	tiers = tierResults,
	constants = {
		upgradePaybackSeconds = C.SlimeUpgradeConfig.UPGRADE_PAYBACK_SECONDS,
		upgradeGrowthRate = C.SlimeUpgradeConfig.UPGRADE_GROWTH_RATE,
		maxLevel = C.SlimeUpgradeConfig.MAX_LEVEL,
		maxLevelIncomeMultiplier = MAX_MULT,
		costToMaxMultiplier = COST_TO_MAX,
		dollarsPerIncomePerSecond = C.SlimeUpgradeConfig.UPGRADE_PAYBACK_SECONDS,
		dollarsPerIncomeWorstDeviation = worstDeviation,
		slotCount = C.SLOT_COUNT,
		boxDoubleChance = C.BOX_P,
		chestDivineChance = C.TreasureConfig.CHEST_DIVINE_CHANCE,
		chestTierWeightRatio = C.TreasureConfig.CHEST_TIER_WEIGHT_RATIO,
	},
	seed = { rollEv = rollEv.seed, slotSim = SEED },
	sampleCounts = {
		rollsPerTier = rollEv.samplesPerTier,
		simulationsPerTier = RUNS,
		rollsPerSimulation = HORIZON,
	},
	gitCommit = commit,
}

if not fs.isDir("dev/out") then
	fs.writeDir("dev/out")
end
fs.writeFile("dev/out/roll_economics_v2.json", serde.encode("json", out, true))
print("\nwrote dev/out/roll_economics_v2.json  (commit " .. commit .. ")")
