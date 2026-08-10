-- STEP 0 (facts) + STEP 1 (raw expected value per roll) of the swing-tier
-- economy measurement. See REPORT.md.
--
--   lune run dev/analysis/roll_ev.luau [sampleCount]
--
-- Run from the REPO ROOT (dev/rbxshim.luau reads sources relative to the
-- current working directory). Default sampleCount is 2,000,000 per tier.
-- Writes dev/out/roll_ev.json, which slot_sim.luau consumes.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local C = require("./common")

local SAMPLES = tonumber(process.args[1]) or 2000000
local SEED = 20260810

local out = {}

--============================ STEP 0: the facts ============================--
print(string.format("SLOT_COUNT = %d (BaseConfig.SLOT_COUNT)", C.SLOT_COUNT))
print(string.format("MAX_LEVEL = %d, UPGRADE_GROWTH_RATE = %s, UPGRADE_PAYBACK_SECONDS = %s",
	C.SlimeUpgradeConfig.MAX_LEVEL, tostring(C.SlimeUpgradeConfig.UPGRADE_GROWTH_RATE), tostring(C.SlimeUpgradeConfig.UPGRADE_PAYBACK_SECONDS)))
print(string.format("max-level multiplier = %.6fx, cost to max from L1 = %.4f seconds of base income",
	C.maxLevelMultiplier(), C.costToMaxMultiplier()))
print(string.format("BOX_DOUBLE_CHANCE = %s, bands = %d, slimes = %d, swing tiers = %d",
	tostring(C.BOX_P), #C.LuckCurve.VALUES, #C.SlimeData.SLIMES, C.SWING_TIER_COUNT))

-- 0f: swing tier -> luck, via the actual flight/band math.
print("\n-- perfect-launch landing per swing tier --")
print("tier  scale  tierScale  distance  seatZ    landZ     fromStart  band  zone   bandLuck  price")
local tierFacts = {}
for tier = 1, C.SWING_TIER_COUNT do
	local f = C.perfectLaunchForTier(tier)
	f.price = C.ShopConfig.SWING_TIER_PRICES[tier]
	tierFacts[tier] = f
	print(string.format("%4d  %5.2f  %9.4f  %8.2f  %7.3f  %8.2f  %9.2f  %4d  %-5s  %8s  %s",
		tier, f.scale, f.tierScale, f.distance, f.seatZ, f.landingZ, f.distanceFromStart, f.bandIndex, f.zone,
		tostring(f.luck), C.fmt(f.price)))
end

-- 0g: the 65 slimes.
local slimeRows = {}
for _, s in C.SlimeData.SLIMES do
	table.insert(slimeRows, {
		id = s.globalIndex,
		name = s.name,
		tier = s.tier,
		tierName = s.tierName,
		baseIncomePerSecond = s.incomePerSecond,
	})
end
out.slimes = slimeRows

--=================== Monotonicity precondition (step 1) ===================--
-- "Expected income per roll must be monotonically non-decreasing in luck."
-- Checked on the RAW band lucks (no box) straight out of the real module, over
-- every band on the road, before any of the tier work below is trusted.
local worstDrop, worstAt = 0, nil
local previous = nil
for i, luck in C.LuckCurve.VALUES do
	local weights = C.SlimeRoll.distributionForLuck(luck)
	local ev = 0
	for tier, mass in weights do
		if mass > 0 then
			local pool = C.SlimeData.SLIMES_BY_TIER[tier]
			local tierMean = 0
			for _, s in pool do
				tierMean += s.incomePerSecond
			end
			ev += mass * tierMean / #pool
		end
	end
	if previous and ev < previous - 1e-12 then
		local drop = previous - ev
		if drop > worstDrop then
			worstDrop, worstAt = drop, luck
		end
	end
	previous = ev
end
print(string.format("\nmonotonicity over %d band lucks: decreasing steps worst drop = %.3e%s",
	#C.LuckCurve.VALUES, worstDrop, worstAt and string.format(" at luck %d", worstAt) or " (none)"))
if worstDrop > 1e-9 then
	error("STOP: expected income per roll is NOT monotonically non-decreasing in luck -- harness or module changed")
end
out.monotonicityWorstDrop = worstDrop

--===================== STEP 1: 2,000,000 rolls per tier =====================--
-- The sampled path is the REAL one, end to end: geometric box-doubling chain
-- (LaunchServer's onBoxPress) feeding SlimeRoll.rollSlime. Tier 11's perfect
-- launch clears the road, so its reward comes from the chest table instead --
-- flagged in the output rather than silently rolled through SlimeRoll.
math.randomseed(SEED)
local tiersOut = {}
for tier = 1, C.SWING_TIER_COUNT do
	local f = tierFacts[tier]
	local isChest = f.zone == "past"
	local analytic = if isChest then C.chestPmf() else C.rollPmfForBandLuck(f.luck)

	local counts = table.create(#C.SlimeData.SLIMES, 0)
	local sumIncome = 0
	if isChest then
		-- Sampled from the analytic chest table (rollChestSlime is a local
		-- inside a .server script and cannot be required -- see common.luau).
		local cumulative = table.create(#analytic, 0)
		local running = 0
		for i, p in analytic do
			running += p
			cumulative[i] = running
		end
		for _ = 1, SAMPLES do
			local r = math.random()
			local lo, hi = 1, #cumulative
			while lo < hi do
				local mid = (lo + hi) // 2
				if r <= cumulative[mid] then hi = mid else lo = mid + 1 end
			end
			counts[lo] += 1
			sumIncome += C.SlimeData.SLIMES[lo].incomePerSecond
		end
	else
		for _ = 1, SAMPLES do
			local luck = f.luck * 2 ^ C.sampleBoxDoublings()
			local slime = C.SlimeRoll.rollSlime(luck)
			counts[slime.globalIndex] += 1
			sumIncome += slime.incomePerSecond
		end
	end

	-- Empirical vs analytic agreement, per slime.
	local worstAbs = 0
	for i = 1, #analytic do
		local diff = math.abs(counts[i] / SAMPLES - analytic[i])
		if diff > worstAbs then
			worstAbs = diff
		end
	end

	local tierHistogram = table.create(#C.SlimeConfig.SLIME_TIER_NAMES, 0)
	for i, p in analytic do
		tierHistogram[C.SlimeData.SLIMES[i].tier] += p
	end

	local entry = {
		swingTier = tier,
		bandLuck = f.luck,
		bandIndex = f.bandIndex,
		zone = f.zone,
		rewardSource = if isChest then "chest" else "mysteryBox",
		price = C.ShopConfig.SWING_TIER_PRICES[tier],
		analyticPmf = analytic,
		sampledExpectedIncome = sumIncome / SAMPLES,
		analyticExpectedIncome = C.expectedIncomeOfPmf(analytic),
		tierHistogram = tierHistogram,
		pDivine = tierHistogram[8],
		pSecretOrBetter = tierHistogram[7] + tierHistogram[8],
		worstPmfDeviation = worstAbs,
	}
	tiersOut[tier] = entry
	print(string.format("tier %2d  luck %8s (%s)  E[base income]/roll: sampled $%s  analytic $%s  (max |dev| %.2e)  P(Divine) %.4f%%  P(Secret+) %.4f%%",
		tier, tostring(f.luck), entry.rewardSource, C.fmt(entry.sampledExpectedIncome), C.fmt(entry.analyticExpectedIncome),
		worstAbs, entry.pDivine * 100, entry.pSecretOrBetter * 100))
end

-- Monotonicity across the swing tiers themselves (the thing the price ladder
-- assumes), reported rather than asserted -- tier 11 is a different table.
for tier = 2, C.SWING_TIER_COUNT do
	local a, b = tiersOut[tier - 1], tiersOut[tier]
	if b.analyticExpectedIncome < a.analyticExpectedIncome - 1e-9 then
		print(string.format("NOTE: tier %d rolls WORSE than tier %d ($%s vs $%s per roll)",
			tier, tier - 1, C.fmt(b.analyticExpectedIncome), C.fmt(a.analyticExpectedIncome)))
	end
end

out.tiers = tiersOut
out.seed = SEED
out.samplesPerTier = SAMPLES
out.constants = {
	slotCount = C.SLOT_COUNT,
	maxLevel = C.SlimeUpgradeConfig.MAX_LEVEL,
	upgradeGrowthRate = C.SlimeUpgradeConfig.UPGRADE_GROWTH_RATE,
	upgradePaybackSeconds = C.SlimeUpgradeConfig.UPGRADE_PAYBACK_SECONDS,
	maxLevelMultiplier = C.maxLevelMultiplier(),
	costToMaxMultiplier = C.costToMaxMultiplier(),
	boxDoubleChance = C.BOX_P,
	chestDivineChance = C.TreasureConfig.CHEST_DIVINE_CHANCE,
	chestTierWeightRatio = C.TreasureConfig.CHEST_TIER_WEIGHT_RATIO,
	sellValueIncomeMultiplier = C.InventoryConfig.SELL_VALUE_INCOME_MULTIPLIER,
}

if not fs.isDir("dev/out") then
	fs.writeDir("dev/out")
end
fs.writeFile("dev/out/roll_ev.json", serde.encode("json", out, true))
print("\nwrote dev/out/roll_ev.json")
