-- Does raising the slot count move the exhaustion curve? A sweep of K against
-- swing tier, joined to the two prior passes' JSON, plus a modelled mutation
-- arm. See REPORT.md.
--
--   lune run dev/analysis/slot_sweep.luau [runsPerCell] [mutationRuns]
--
-- Run from the REPO ROOT. Writes dev/out/slot_sweep.json.
--
-- REFUSES TO RUN against stale joins: both dev/out/roll_economics.json and
-- dev/out/cycle_economics.json must record the current HEAD.
--
-- METHOD, unchanged in kind from dev/analysis/slot_sim.luau (read, not edited):
-- the held set only changes when a roll BEATS the current worst slot, and rolls
-- are i.i.d., so the number of rolls to the next improvement is geometric with
-- q = P(income > worst). Sampling that gap directly is EXACT, not an
-- approximation of rolling one at a time.
--
-- WHAT IS NEW HERE, and why it is needed at K = 51: the held set is carried as
-- a COUNT VECTOR over the distribution's distinct income values rather than a
-- sorted array or a heap. The worst-held value is a pointer into that vector
-- that only ever moves UP, so an improvement is two increments and an amortised
-- pointer bump -- O(1) instead of O(K) or O(log K). Nothing about the sampled
-- process changes; this is the same simulation, faster.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local C = require("./common")

local RUNS = tonumber(process.args[1]) or 10000
local MUTATION_RUNS = tonumber(process.args[2]) or 2000
local HORIZON = 20000
local SEED_SWEEP = 20260812
local SEED_MUTATION = 20260813

-- K and K+1 both swept: step 6 prices ONE more slot, which is a difference
-- between K and K+1, not a slope between swept points.
local SLOT_COUNTS = { 10, 11, 15, 16, 20, 21, 30, 31, 50, 51 }
local HEADLINE_SLOTS = { 10, 15, 20, 30, 50 }
local MUTATION_P = { 0.5, 0.1, 0.02, 0.01 }
local MUTATION_M = { 2, 5, 10, 50 }
local MUTATION_SLOTS = { 10, 20 }
local MUTATION_TIERS = { 5, 8, 10, 11 }

local commit = (process.exec("git", { "rev-parse", "HEAD" }).stdout:gsub("%s+$", ""))
local econ = serde.decode("json", fs.readFile("dev/out/roll_economics.json"))
local cycle = serde.decode("json", fs.readFile("dev/out/cycle_economics.json"))
if econ.gitCommit ~= commit then
	error("STOP: dev/out/roll_economics.json is at " .. tostring(econ.gitCommit) .. ", HEAD is " .. commit)
end
if cycle.gitCommit ~= commit then
	error("STOP: dev/out/cycle_economics.json is at " .. tostring(cycle.gitCommit) .. ", HEAD is " .. commit)
end

local COST_TO_MAX = C.costToMaxMultiplier() -- SlimeUpgrade.totalUpgradeCost(1, 1, 25), derived
local MAX_MULT = C.maxLevelMultiplier()
local TIERS = C.SWING_TIER_COUNT
local DOLLARS_PER_INCOME = C.SlimeUpgradeConfig.UPGRADE_PAYBACK_SECONDS

--================================== The grid ==================================--
-- Geometric, plus every checkpoint the brief asks for, plus the EXACT double of
-- every point up to the horizon -- the exhaustion test needs mean income at N
-- and at 2N, and interpolating one of them would blur the crossing.
local grid, gridIndexOf = {}, {}
do
	local seen = {}
	local function add(n)
		if n >= 1 and n <= HORIZON and not seen[n] then
			seen[n] = true
			table.insert(grid, n)
		end
	end
	for n = 1, 12 do add(n) end
	local x = 12.0
	while x <= HORIZON do
		add(math.floor(x + 0.5))
		x *= 2 ^ 0.125 -- ~9% spacing: exhaustion is reported to the nearest grid point
	end
	for _, n in { 50, 100, 500, 1000, 5000, 10000, 20000 } do add(n) end
	local base = table.clone(grid)
	for _, n in base do add(2 * n) end
	table.sort(grid)
	for i, n in grid do
		gridIndexOf[n] = i
	end
end
local GRID_N = #grid

--============================== Value machinery ==============================--
-- Collapses a per-slime PMF into distinct income VALUES with their masses. The
-- mutation arm (step 7, modelled) splits each value into an unmutated and a
-- mutated copy before this runs.
local function valueTable(pmf: { number }, mutationChance: number?, mutationMultiplier: number?)
	local byValue = {}
	local p = mutationChance or 0
	local m = mutationMultiplier or 1
	for index, mass in pmf do
		if mass > 0 then
			local base = C.SlimeData.SLIMES[index].incomePerSecond
			if p > 0 then
				byValue[base] = (byValue[base] or 0) + mass * (1 - p)
				byValue[base * m] = (byValue[base * m] or 0) + mass * p
			else
				byValue[base] = (byValue[base] or 0) + mass
			end
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
	end
	for i = 1, #values do
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

--=============================== The simulation ===============================--
-- Policy: keep the best K slimes ever rolled, by base income/s. The GAME has no
-- such policy (see step 0a and the first pass) -- this is optimal hand play.
local function simulate(vt, slots: number, runs: number)
	local incomeAt, spendAt = {}, {}
	for g = 1, GRID_N do
		incomeAt[g] = table.create(runs, 0)
		spendAt[g] = table.create(runs, 0)
	end
	local counts = table.create(vt.count, 0)

	for run = 1, runs do
		table.clear(counts)
		for i = 1, vt.count do
			counts[i] = 0
		end
		local total, spend = 0, 0
		local minIdx = vt.count
		local n, g = 0, 1

		local function recordUpTo(untilRoll: number)
			while g <= GRID_N and grid[g] <= untilRoll do
				incomeAt[g][run] = total
				spendAt[g][run] = spend
				g += 1
			end
		end

		-- Fill phase: the first K rolls land in an empty slot (receiveSlime's
		-- first-empty-slot rule; no choice is involved).
		for _ = 1, slots do
			local idx = drawIndexAbove(vt, 0)
			counts[idx] += 1
			local v = vt.values[idx]
			total += v
			spend += COST_TO_MAX * v
			if idx < minIdx then
				minIdx = idx
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
			spend += COST_TO_MAX * v
			while counts[minIdx] == 0 do
				minIdx += 1
			end
			recordUpTo(n)
		end
		recordUpTo(HORIZON)
	end

	local stats = table.create(GRID_N)
	for gi = 1, GRID_N do
		local incomes, spends = incomeAt[gi], spendAt[gi]
		local meanIncome, meanSpend = 0, 0
		for run = 1, runs do
			meanIncome += incomes[run]
			meanSpend += spends[run]
		end
		table.sort(incomes)
		local function pct(p)
			return incomes[math.clamp(math.floor(p * runs + 0.5), 1, runs)]
		end
		stats[gi] = {
			n = grid[gi],
			mean = meanIncome / runs,
			p10 = pct(0.10),
			p50 = pct(0.50),
			p90 = pct(0.90),
			meanSpend = meanSpend / runs,
		}
	end
	return stats
end

local function at(stats, n: number)
	local gi = gridIndexOf[n]
	return if gi then stats[gi] else nil
end

-- Exhaustion, THE definition used throughout: the first grid point N where the
-- mean forward gain rate over [N, 2N) falls below 1% of the mean income held at
-- N. Every doubled point is on the grid by construction, so no interpolation.
local function exhaustionRoll(stats): number?
	for gi = 1, GRID_N do
		local a = stats[gi]
		local b = at(stats, 2 * a.n)
		if b and a.mean > 0 then
			local rate = (b.mean - a.mean) / (b.n - a.n)
			if rate < 0.01 * a.mean then
				return a.n
			end
		end
	end
	return nil
end

-- The PREVIOUS pass's definition, kept only so step 4's reproduction check
-- compares like with like: the forward rate between CONSECUTIVE grid points.
local function exhaustionRollPriorDefinition(stats): number?
	for gi = 1, GRID_N - 1 do
		local a, b = stats[gi], stats[gi + 1]
		if a.mean > 0 then
			local rate = (b.mean - a.mean) / (b.n - a.n)
			if rate < 0.01 * a.mean then
				return a.n
			end
		end
	end
	return nil
end

local function rollsToCeilingFraction(stats, ceiling: number, fraction: number): number?
	for gi = 1, GRID_N do
		if stats[gi].p50 >= fraction * ceiling then
			return stats[gi].n
		end
	end
	return nil
end

--================================ The sweep ================================--
math.randomseed(SEED_SWEEP)
local tierPmf, tierCeilingValue = {}, {}
for tier = 1, TIERS do
	local facts = C.perfectLaunchForTier(tier)
	tierPmf[tier] = if facts.zone == "past" then C.chestPmf() else C.rollPmfForBandLuck(facts.luck)
end

local sweep = {}
local sweepIndex = {}
print(string.format("runs/cell %d, horizon %d, grid points %d, costToMax %.4f", RUNS, HORIZON, GRID_N, COST_TO_MAX))
for _, slots in SLOT_COUNTS do
	for tier = 1, TIERS do
		local vt = valueTable(tierPmf[tier])
		local stats = simulate(vt, slots, RUNS)
		local ceiling = slots * vt.max
		local i100, i1000, i10000, i20000 = at(stats, 100), at(stats, 1000), at(stats, 10000), at(stats, 20000)
		local drainWindowLow = at(stats, 10000)
		local drainPerRoll = (i20000.meanSpend - drainWindowLow.meanSpend) / (20000 - 10000)
		local entry = {
			slots = slots,
			tier = tier,
			ceiling = ceiling,
			maxSlimeIncome = vt.max,
			income = {
				["100"] = { mean = i100.mean, p10 = i100.p10, p50 = i100.p50, p90 = i100.p90 },
				["1000"] = { mean = i1000.mean, p10 = i1000.p10, p50 = i1000.p50, p90 = i1000.p90 },
				["10000"] = { mean = i10000.mean, p10 = i10000.p10, p50 = i10000.p50, p90 = i10000.p90 },
				["20000"] = { mean = i20000.mean, p10 = i20000.p10, p50 = i20000.p50, p90 = i20000.p90 },
			},
			rollsToCeiling50 = rollsToCeilingFraction(stats, ceiling, 0.50),
			rollsToCeiling90 = rollsToCeilingFraction(stats, ceiling, 0.90),
			rollsToCeiling99 = rollsToCeilingFraction(stats, ceiling, 0.99),
			rollsToExhaustion = exhaustionRoll(stats),
			rollsToExhaustionPriorDefinition = exhaustionRollPriorDefinition(stats),
			remaxSpendPerRollAtEquilibrium = drainPerRoll,
			levellingCapacityAt1000 = COST_TO_MAX * i1000.p50,
			levellingCapacityAt10000 = COST_TO_MAX * i10000.p50,
			levellingCapacityAtCeiling = COST_TO_MAX * ceiling,
		}
		for _, key in { "100", "1000", "10000", "20000" } do
			local b = entry.income[key]
			b.p90OverP10 = if b.p10 > 0 then b.p90 / b.p10 else nil
		end
		table.insert(sweep, entry)
		sweepIndex[slots .. ":" .. tier] = entry
	end
	print(string.format("  K=%d done (tier 10: p50@1k $%s, p50@10k $%s, exhaust %s rolls)",
		slots, C.fmt(sweepIndex[slots .. ":10"].income["1000"].p50),
		C.fmt(sweepIndex[slots .. ":10"].income["10000"].p50),
		tostring(sweepIndex[slots .. ":10"].rollsToExhaustion)))
end

--=========================== Real time and dead time ===========================--
local MODELS = { "perfect", "hit50", "hit20" }
local function cycleSeconds(tier: number, model: string): number
	return cycle.tiers[tier].byPlayerModel[model].totalCycleSeconds
end

for _, e in sweep do
	e.minutesToExhaustion, e.minutesToCeiling90 = {}, {}
	for _, model in MODELS do
		local cs = cycleSeconds(e.tier, model)
		e.minutesToExhaustion[model] = if e.rollsToExhaustion then e.rollsToExhaustion * cs / 60 else nil
		e.minutesToCeiling90[model] = if e.rollsToCeiling90 then e.rollsToCeiling90 * cs / 60 else nil
	end
end

-- Affordability: the prior pass's NON-CIRCULAR method, unchanged -- integrate
-- income along the measured held-set growth curve from an empty base, banking
-- at the measured cadence, until the next tier's price is met. Curve points are
-- the medians at 0 / 100 / 1,000 / 10,000 rolls (the same four the prior pass
-- used, so K = 10 is comparable), linearly interpolated, flat past the last.
local function affordRolls(e, nextPrice: number, cs: number, maxed: boolean, drainPerRoll: number): number?
	local pts = {
		{ 0, 0 },
		{ 100, e.income["100"].p50 },
		{ 1000, e.income["1000"].p50 },
		{ 10000, e.income["10000"].p50 },
	}
	local multiplier = if maxed then MAX_MULT else 1
	local drain = if maxed then drainPerRoll else 0
	local money = 0
	local k = 1
	for n = 1, 500000 do
		local income
		if n >= pts[#pts][1] then
			income = pts[#pts][2]
		else
			while n > pts[k + 1][1] do
				k += 1
			end
			local a, b = pts[k], pts[k + 1]
			income = a[2] + (b[2] - a[2]) * (n - a[1]) / (b[1] - a[1])
		end
		money += income * multiplier * cs - drain
		if money >= nextPrice then
			return n
		end
	end
	return nil
end

local deadTime = {}
for _, e in sweep do
	local nextPrice = if e.tier < TIERS then econ.tiers[e.tier + 1].price else nil
	e.affordability = {}
	for _, model in MODELS do
		local cs = cycleSeconds(e.tier, model)
		local row = { model = model }
		if nextPrice then
			local rollsA = affordRolls(e, nextPrice, cs, false, 0)
			local rollsB = affordRolls(e, nextPrice, cs, true, e.remaxSpendPerRollAtEquilibrium)
			row.minutesUnlevelled = if rollsA then rollsA * cs / 60 else nil
			row.minutesMaxed = if rollsB then rollsB * cs / 60 else nil
			local exhaustion = e.minutesToExhaustion[model]
			row.deadMinutesUnlevelled = if row.minutesUnlevelled and exhaustion then row.minutesUnlevelled - exhaustion else nil
			row.deadMinutesMaxed = if row.minutesMaxed and exhaustion then row.minutesMaxed - exhaustion else nil
		end
		e.affordability[model] = row
	end
	table.insert(deadTime, {
		slots = e.slots, tier = e.tier,
		minutesToExhaustion = e.minutesToExhaustion.perfect,
		perfect = e.affordability.perfect,
		hit50 = e.affordability.hit50,
		hit20 = e.affordability.hit20,
	})
end

-- Per-K totals over tiers 1-10 (tier 11 has no next tier), perfect play.
local totals = {}
for _, slots in SLOT_COUNTS do
	local content, deadA, deadB = 0, 0, 0
	for tier = 1, 10 do
		local e = sweepIndex[slots .. ":" .. tier]
		content += e.minutesToExhaustion.perfect or 0
		deadA += e.affordability.perfect.deadMinutesUnlevelled or 0
		deadB += e.affordability.perfect.deadMinutesMaxed or 0
	end
	totals[tostring(slots)] = {
		contentMinutes = content,
		deadMinutesUnlevelled = deadA,
		deadMinutesMaxed = deadB,
		contentHours = content / 60,
		deadHoursUnlevelled = deadA / 60,
		deadHoursMaxed = deadB / 60,
		contentToDeadUnlevelled = if deadA ~= 0 then content / deadA else nil,
		contentToDeadMaxed = if deadB ~= 0 then content / deadB else nil,
	}
end

print("\nK    content(h)  dead unlevelled(h)  dead maxed(h)  content:dead (unlev)")
for _, slots in SLOT_COUNTS do
	local t = totals[tostring(slots)]
	print(string.format("%-4d %-11.2f %-19.1f %-14.1f %s",
		slots, t.contentHours, t.deadHoursUnlevelled, t.deadHoursMaxed,
		t.contentToDeadUnlevelled and string.format("1 : %.0f", 1 / t.contentToDeadUnlevelled) or "n/a"))
end

--============================ Step 5: solve for K ============================--
-- Dead time as a function of K, per tier, interpolated between swept points on
-- log K (it is far closer to linear there than on K). Extrapolated beyond 50
-- from the last two swept points, and flagged.
local requiredSlots = {}
for tier = 1, 10 do
	for _, bracket in { "Unlevelled", "Maxed" } do
		local xs, ys = {}, {}
		for _, slots in HEADLINE_SLOTS do
			local e = sweepIndex[slots .. ":" .. tier]
			local dead = e.affordability.perfect["deadMinutes" .. bracket]
			if dead then
				table.insert(xs, math.log(slots))
				table.insert(ys, dead)
			end
		end
		local solution, extrapolated = nil, false
		for i = 1, #xs - 1 do
			if (ys[i] >= 0 and ys[i + 1] <= 0) or (ys[i] <= 0 and ys[i + 1] >= 0) then
				local t = ys[i] / (ys[i] - ys[i + 1])
				solution = math.exp(xs[i] + (xs[i + 1] - xs[i]) * t)
				break
			end
		end
		if not solution and #xs >= 2 then
			local i = #xs
			local slope = (ys[i] - ys[i - 1]) / (xs[i] - xs[i - 1])
			if slope ~= 0 then
				local logK = xs[i] - ys[i] / slope
				solution = math.exp(logK)
				extrapolated = true
			end
		end
		table.insert(requiredSlots, {
			tier = tier,
			bracket = string.lower(bracket),
			requiredK = solution,
			extrapolated = extrapolated,
			deadAtK10 = sweepIndex["10:" .. tier].affordability.perfect["deadMinutes" .. bracket],
			deadAtK50 = sweepIndex["50:" .. tier].affordability.perfect["deadMinutes" .. bracket],
		})
	end
end

--=========================== Step 6: price the slot ===========================--
local slotPricing = {}
for _, slots in HEADLINE_SLOTS do
	for tier = 1, TIERS do
		local a = sweepIndex[slots .. ":" .. tier]
		local b = sweepIndex[(slots + 1) .. ":" .. tier]
		local cs = cycleSeconds(tier, "perfect")
		local function realisedFrom(e, key: string, stat: string): number
			return MAX_MULT * e.income[key][stat] - e.remaxSpendPerRollAtEquilibrium / cs
		end
		local d1000 = realisedFrom(b, "1000", "p50") - realisedFrom(a, "1000", "p50")
		local d10000 = realisedFrom(b, "10000", "p50") - realisedFrom(a, "10000", "p50")
		local dMean1000 = realisedFrom(b, "1000", "mean") - realisedFrom(a, "1000", "mean")
		local dMean10000 = realisedFrom(b, "10000", "mean") - realisedFrom(a, "10000", "mean")
		local base1000 = b.income["1000"].p50 - a.income["1000"].p50
		local base10000 = b.income["10000"].p50 - a.income["10000"].p50
		table.insert(slotPricing, {
			fromSlots = slots,
			toSlots = slots + 1,
			tier = tier,
			deltaBaseIncome1000 = base1000,
			deltaBaseIncome10000 = base10000,
			deltaRealisedIncome1000 = d1000,
			deltaRealisedIncome10000 = d10000,
			deltaRealisedIncomeMean1000 = dMean1000,
			deltaRealisedIncomeMean10000 = dMean10000,
			breakEvenPrice1000 = d1000 * DOLLARS_PER_INCOME,
			breakEvenPrice10000 = d10000 * DOLLARS_PER_INCOME,
			breakEvenPriceMean1000 = dMean1000 * DOLLARS_PER_INCOME,
			breakEvenPriceMean10000 = dMean10000 * DOLLARS_PER_INCOME,
			levellingCapacityAt10000 = a.levellingCapacityAt10000,
		})
	end
end

-- The candidate ladder. THE TIER ASSIGNMENT IS AN ASSUMPTION, stated in the
-- report: two slots per swing tier from tier 3 up, since that is roughly the
-- rate at which the measured progression moves through tiers.
local ladder = {}
for slot = 11, 30 do
	local tier = math.clamp(3 + (slot - 11) // 2, 3, 10)
	-- Nearest swept pair bracketing this slot count.
	local from = 10
	for _, s in HEADLINE_SLOTS do
		if s <= slot - 1 then
			from = s
		end
	end
	local a = sweepIndex[from .. ":" .. tier]
	local b = sweepIndex[(from + 1) .. ":" .. tier]
	local cs = cycleSeconds(tier, "perfect")
	-- Mean, not median: see the marginal block above for why.
	local function realised(e): number
		return MAX_MULT * e.income["10000"].mean - e.remaxSpendPerRollAtEquilibrium / cs
	end
	local delta = realised(b) - realised(a)
	table.insert(ladder, {
		slot = slot,
		assumedTier = tier,
		measuredAtSlots = from,
		deltaRealisedIncome = delta,
		breakEvenPrice = delta * DOLLARS_PER_INCOME,
		swingTierPriceForComparison = econ.tiers[tier].price,
	})
end

--===================== Step 7: the mutation arm (MODELLED) =====================--
-- NO MUTATION SYSTEM EXISTS IN THE SOURCE. This is a model applied inside this
-- script only: with probability p a rolled slime is worth m times its base
-- income, independent of which slime was rolled.
math.randomseed(SEED_MUTATION)
local mutation = {}
for _, slots in MUTATION_SLOTS do
	for _, tier in MUTATION_TIERS do
		for _, p in MUTATION_P do
			for _, m in MUTATION_M do
				local vt = valueTable(tierPmf[tier], p, m)
				local stats = simulate(vt, slots, MUTATION_RUNS)
				local rolls = exhaustionRoll(stats)
				local cs = cycleSeconds(tier, "perfect")
				table.insert(mutation, {
					modelled = true,
					slots = slots,
					tier = tier,
					mutationChance = p,
					mutationMultiplier = m,
					averageIncomeMultiplier = 1 + p * (m - 1),
					ceiling = slots * vt.max,
					rollsToExhaustion = rolls,
					minutesToExhaustionPerfect = if rolls then rolls * cs / 60 else nil,
					p50IncomeAt1000 = at(stats, 1000).p50,
					p50IncomeAt10000 = at(stats, 10000).p50,
				})
			end
		end
	end
end

print("\nmutation arm (MODELLED), tier 10, K=10 -- minutes to exhaustion at perfect play")
print("p \\ m        2         5         10        50")
for _, p in MUTATION_P do
	local row = string.format("%-6.2f", p)
	for _, m in MUTATION_M do
		for _, e in mutation do
			if e.slots == 10 and e.tier == 10 and e.mutationChance == p and e.mutationMultiplier == m then
				row ..= string.format("  %-8s", e.minutesToExhaustionPerfect and string.format("%.1f", e.minutesToExhaustionPerfect) or "none")
			end
		end
	end
	print(row)
end

--=================================== Output ===================================--
local out = {
	gitCommit = commit,
	sourceJson = {
		rollEconomics = { path = "dev/out/roll_economics.json", gitCommit = econ.gitCommit },
		cycleEconomics = { path = "dev/out/cycle_economics.json", gitCommit = cycle.gitCommit },
	},
	facts = {
		slotCount = C.SLOT_COUNT,
		duplicatesAllowed = true,
		duplicatesEvidence = "PlayerProfile.receiveSlime:865-873 and placeFromInventory:907-919 write profile.slots[i] = globalIndex after scanning only for an EMPTY slot; neither compares against the indices already held, and nothing else writes profile.slots",
		ceilingRule = "K * max(base income) = K * 350000",
		maxKWithoutSchemaChange = 12,
		maxKBindingConstraint = "plot mat depth: BASE_SLOT_Z_START 117 + 14/row (BASE_SLOT_ROW_SPACING_STUDS) + 4 (half of BASE_SLOT_PAD_SIZE.Z) must stay inside the mat's far edge at BASE_PLOT_CENTER_Z 150 + BASE_MAT_SIZE.Z/2 = 192, and clear of the back edge part at Z 192; 6 rows x BASE_GRID_COLUMNS 2 = 12",
		dataStoreCarriesAnyK = true,
		slotNameFormatCap = 99,
		incomeSumsAllSlots = true,
		levelResetHolds = true,
		remaxCostDependsOnKOnlyViaTotalBaseIncome = true,
	},
	sweep = sweep,
	deadTime = { perSlotTier = deadTime, totals = totals },
	requiredSlots = requiredSlots,
	slotPricing = { marginal = slotPricing, candidateLadder = ladder },
	mutationArm = { modelled = true, grid = mutation },
	constants = {
		costToMaxMultiplier = COST_TO_MAX,
		maxLevelIncomeMultiplier = MAX_MULT,
		dollarsPerIncomePerSecond = DOLLARS_PER_INCOME,
		horizonRolls = HORIZON,
		exhaustionDefinition = "first grid N where (mean(2N) - mean(N)) / N < 0.01 * mean(N)",
		ceilingPercentDefinition = "median held-set base income/s against K * 350000, NOT against a horizon value",
	},
	seeds = { sweep = SEED_SWEEP, mutation = SEED_MUTATION },
	sampleCounts = {
		runsPerCell = RUNS,
		mutationRunsPerCell = MUTATION_RUNS,
		slotCounts = SLOT_COUNTS,
		tiers = TIERS,
		gridPoints = GRID_N,
	},
}
if not fs.isDir("dev/out") then
	fs.writeDir("dev/out")
end
fs.writeFile("dev/out/slot_sweep.json", serde.encode("json", out, true))
print("\nwrote dev/out/slot_sweep.json  (commit " .. commit .. ")")
