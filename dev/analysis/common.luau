-- Shared harness for the swing-tier economy measurement (see REPORT.md).
--
-- EVERYTHING THAT CAN BE REQUIRED IS REQUIRED, not reimplemented: the roll
-- distribution comes from the real src/ServerScriptService/SlimeRoll.luau, the
-- upgrade formulas from the real SlimeUpgrade.luau, every constant from the
-- real Config modules, all loaded through dev/rbxshim.luau exactly the way
-- dev/run_gallery.luau already loads SwingBuilder. Nothing here duplicates a
-- number that exists in the source tree.
--
-- THE ONE EXCEPTION, stated loudly because it matters: LaunchServer.server.
-- luau is a .server script, not a ModuleScript, so bandLuckForLandingZ,
-- trajectoryPosition, swingSeatPosition and rollChestSlime CANNOT be required.
-- The four are re-derived below from the same constants, line-for-line against
-- the source, and each carries a comment naming the exact lines it mirrors. If
-- LaunchServer's flight math changes, this file goes stale and nothing will
-- warn you.
local shim = require("../rbxshim")

local Config = shim.ReplicatedStorage:FindFirstChild("Config")

-- rbxshim already registers LaunchConfig / SwingTierVisuals / SwingGeometry /
-- LaneConfig / RunwayGeometry / BaseConfig / BaseGeometry / GroundConfig /
-- PathConfig / StallConfig. These are the economy modules it does not.
shim.registerModule(Config, "SlimeConfig", "src/ReplicatedStorage/Config/SlimeConfig.luau")
shim.registerModule(Config, "SlimeData", "src/ReplicatedStorage/Config/SlimeData.luau")
shim.registerModule(Config, "SlimeUpgradeConfig", "src/ReplicatedStorage/Config/SlimeUpgradeConfig.luau")
shim.registerModule(Config, "SlimeUpgrade", "src/ReplicatedStorage/Config/SlimeUpgrade.luau")
shim.registerModule(Config, "ShopConfig", "src/ReplicatedStorage/Config/ShopConfig.luau")
shim.registerModule(Config, "InventoryConfig", "src/ReplicatedStorage/Config/InventoryConfig.luau")
shim.registerModule(Config, "TreasureConfig", "src/ReplicatedStorage/Config/TreasureConfig.luau")
shim.registerModule(Config, "LuckCurve", "src/ReplicatedStorage/Config/LuckCurve.luau")

local M = {}

M.shim = shim
M.SlimeConfig = shim.loadLuauModule("src/ReplicatedStorage/Config/SlimeConfig.luau")
M.SlimeData = shim.loadLuauModule("src/ReplicatedStorage/Config/SlimeData.luau")
M.SlimeRoll = shim.loadLuauModule("src/ServerScriptService/SlimeRoll.luau")
M.SlimeUpgrade = shim.loadLuauModule("src/ReplicatedStorage/Config/SlimeUpgrade.luau")
M.SlimeUpgradeConfig = shim.loadLuauModule("src/ReplicatedStorage/Config/SlimeUpgradeConfig.luau")
M.ShopConfig = shim.loadLuauModule("src/ReplicatedStorage/Config/ShopConfig.luau")
M.InventoryConfig = shim.loadLuauModule("src/ReplicatedStorage/Config/InventoryConfig.luau")
M.TreasureConfig = shim.loadLuauModule("src/ReplicatedStorage/Config/TreasureConfig.luau")
M.LuckCurve = shim.loadLuauModule("src/ReplicatedStorage/Config/LuckCurve.luau")
M.LaunchConfig = shim.loadLuauModule("src/ReplicatedStorage/Config/LaunchConfig.luau")
M.LaneConfig = shim.loadLuauModule("src/ReplicatedStorage/Config/LaneConfig.luau")
M.RunwayGeometry = shim.loadLuauModule("src/ReplicatedStorage/Config/RunwayGeometry.luau")
M.SwingGeometry = shim.loadLuauModule("src/ReplicatedStorage/Config/SwingGeometry.luau")
M.SwingTierVisuals = shim.loadLuauModule("src/ReplicatedStorage/Config/SwingTierVisuals.luau")
M.BaseConfig = shim.loadLuauModule("src/ReplicatedStorage/Config/BaseConfig.luau")

M.SWING_TIER_COUNT = #M.LaunchConfig.SWING_TIER_DISTANCE_SCALE
M.SLOT_COUNT = M.BaseConfig.SLOT_COUNT

-- ===== Swing tier -> the luck value a PERFECT launch earns =====
-- Mirrors, in order:
--   LaunchServer.server.luau:1864  multiplier  (SWEET_SPOT_MULTIPLIER at a perfect release)
--   LaunchServer.server.luau:1882  distance = DISTANCE_PER_MULTIPLIER * multiplier * tierScale
--   LaunchServer.server.luau:591   swingTheta(phase) = arc * sin(2*pi*phase)
--   LaunchServer.server.luau:602   swingSeatPosition -> pivot + (0, -L cos t, -L sin t)
--   LaunchServer.server.luau:683   trajectoryPosition -> z = startZ - distance * u, u = 1
--   LaunchServer.server.luau:736   bandLuckForLandingZ
-- SWEET_SPOT_PHASE = 0.25 puts sin(2*pi*phase) = 1, i.e. theta = the full arc
-- half-angle: the forward extreme of the swing, which is where a perfect
-- release happens.
function M.perfectLaunchForTier(tier: number): { [string]: any }
	local scale = M.SwingTierVisuals.forTier(tier).scale
	local ropeLength = M.SwingGeometry.ropeLengthForScale(scale)
	local theta = math.rad(M.LaunchConfig.SWING_ARC_HALF_ANGLE_DEGREES) * math.sin(2 * math.pi * M.LaunchConfig.SWEET_SPOT_PHASE)
	local seatZ = M.LaneConfig.SWING_PIVOT_Z - ropeLength * math.sin(theta)
	local tierScale = M.LaunchConfig.SWING_TIER_DISTANCE_SCALE[tier]
	local distance = M.LaunchConfig.DISTANCE_PER_MULTIPLIER * M.LaunchConfig.SWEET_SPOT_MULTIPLIER * tierScale
	local landingZ = seatZ - distance
	local distanceFromStart = M.RunwayGeometry.RUNWAY_START_Z - landingZ

	local zone, luck, bandIndex
	if distanceFromStart < 0 then
		zone, luck, bandIndex = "short", 0, -1
	else
		bandIndex = math.floor(distanceFromStart / M.LaunchConfig.RUNWAY_BAND_LENGTH_STUDS)
		if bandIndex > #M.LuckCurve.VALUES - 1 then
			zone, luck = "past", 0
		else
			zone, luck = "road", M.LuckCurve.VALUES[bandIndex + 1]
		end
	end
	return {
		tier = tier,
		scale = scale,
		tierScale = tierScale,
		distance = distance,
		seatZ = seatZ,
		landingZ = landingZ,
		distanceFromStart = distanceFromStart,
		bandIndex = bandIndex,
		luck = luck,
		zone = zone,
	}
end

-- ===== Reading SOURCE FILES for structural checks =====
-- Any test that greps the tree must go through this rather than fs.readFile.
--
-- WHY, and it is not hypothetical -- it silently broke a check before it was
-- noticed: this repo is developed on Windows with git's autocrlf on, so files
-- arrive from disk with CRLF line endings. A needle written the obvious way,
-- "someCall()\n\tnextLine", then matches NOTHING, because the real bytes are
-- "someCall()\r\n\tnextLine". The failure mode is the dangerous direction: a
-- structural assertion that silently stops finding what it was written to find
-- still PASSES if it was phrased as "this must not appear", and a `find`
-- falling back to a default still produces a plausible-looking result.
--
-- Normalising to LF here means every needle in every analysis script can be
-- written the way it reads in the editor, and none of them has to know what
-- platform produced the checkout.
local fs = require("@lune/fs")

function M.readSource(relPath: string): string
	return (string.gsub(fs.readFile(relPath), "\r\n", "\n"))
end

-- ===== Flight duration for a tier =====
-- Mirrors LaunchServer.server.luau's onRelease, which is now:
--   duration = FLIGHT_DURATION_BASE_SECONDS + tier * FLIGHT_DURATION_PER_TIER_SECONDS
-- i.e. tier N flies for N + 1 seconds at the current constants.
--
-- IT NO LONGER TAKES A DISTANCE. The previous form was
--   FLIGHT_DURATION_SECONDS * (distance / baseDistance) ^ FLIGHT_DURATION_EXPONENT
-- and both of those constants have been REMOVED from LaunchConfig, so every
-- caller in this directory that used to inline that expression now calls this
-- instead -- one mirror of the live formula, not five copies. Callers that
-- want the OLD number for a before/after comparison (see flight_pacing.luau)
-- carry the retired constants as their own locals, clearly marked as historical.
--
-- Consequence worth knowing when reading any cycle table below: duration is now
-- independent of the release quality, so a mistimed launch at tier N takes
-- exactly as long as a perfect one. The perfect-play cycle figures are
-- therefore also the cycle figures for every other release at that tier.
function M.flightDurationForTier(tier: number): number
	return M.LaunchConfig.FLIGHT_DURATION_BASE_SECONDS
		+ tier * M.LaunchConfig.FLIGHT_DURATION_PER_TIER_SECONDS
end

-- ===== The mystery box, as a luck multiplier =====
-- LaunchServer.server.luau:2356 -- each press doubles with BOX_DOUBLE_CHANCE
-- and otherwise opens, so the number of doublings D is geometric:
-- P(D = d) = p^d * (1 - p), and the luck fed to SlimeRoll.rollSlime is
-- bandLuck * 2^D. Uncapped by design (see that function's header), so D has no
-- maximum -- but the distribution stops moving once luck passes the high
-- anchor (SLIME_EXTRAPOLATION_T_MAX clamps t), which is what makes the exact
-- mixture below finite.
M.BOX_P = M.LaunchConfig.BOX_DOUBLE_CHANCE

function M.sampleBoxDoublings(): number
	local d = 0
	while math.random() < M.BOX_P do
		d += 1
	end
	return d
end

-- The within-tier split, matching SlimeRoll.pickSlimeInTier exactly: shares are
-- ratio^-(i-1) over the tier's own list, normalised, from
-- SlimeConfig.SLIME_TIER_WEIGHT_RATIO. A ratio of 1.0 returns nil rather than a
-- table of 1/n, so the callers below can keep their original
-- `mass / #pool` arithmetic for uniform tiers -- same expression, same
-- rounding, bit-identical results to before this table existed.
local shareCache: { [number]: { number }? } = {}
local shareCacheFilled: { [number]: boolean } = {}
local function withinTierShares(tier: number): { number }?
	if shareCacheFilled[tier] then
		return shareCache[tier]
	end
	shareCacheFilled[tier] = true
	local ratios = (M.SlimeConfig :: any).SLIME_TIER_WEIGHT_RATIO
	local ratio = if ratios then ratios[tier] else 1.0
	if typeof(ratio) ~= "number" or ratio == 1 then
		shareCache[tier] = nil
		return nil
	end
	local pool = M.SlimeData.SLIMES_BY_TIER[tier]
	local weights, total = table.create(#pool, 0), 0
	for i = 1, #pool do
		weights[i] = ratio ^ -(i - 1)
		total += weights[i]
	end
	for i = 1, #pool do
		weights[i] /= total
	end
	shareCache[tier] = weights
	return weights
end
M.withinTierShares = withinTierShares

-- Exact per-slime probability mass for one roll at a given pre-box band luck,
-- integrating the box's doubling chain analytically. Every distribution comes
-- from the real SlimeRoll.distributionForLuck; the only thing done here is
-- weighting them by P(D = d) and splitting each tier's mass the same way
-- SlimeRoll.pickSlimeInTier does.
--
-- TWO ASSUMPTIONS WERE FIXED HERE, both of which were correct when written and
-- silently stopped being so (see REPORT.md):
--
--   1. THE CLAMP IS DERIVED, NOT ASSUMED. This used to read
--      `clampLuck = SLIME_LUCK_ANCHOR_HIGH`, which is where t clamps only while
--      SLIME_EXTRAPOLATION_T_MAX is exactly 1.0. It is 1.35 now, so the real
--      clamp is LOW * (HIGH/LOW)^T_MAX = 1,089,047 and the old expression
--      collapsed the doubling tail 9x too early -- understating box value by
--      0.3% at tier 1 rising to 1.9% at tier 9.
--   2. THE WITHIN-TIER SPLIT IS NO LONGER ASSUMED UNIFORM. It used to divide a
--      tier's mass by #pool unconditionally, which stopped matching the game
--      when SLIME_TIER_WEIGHT_RATIO gave Divine a 1.40 ratio. Uniform tiers
--      still take the identical `mass / #pool` expression.
--
-- The tail is EXACT, not truncated: past the clamp every further doubling
-- produces a bit-identical distribution, so all remaining mass P(D >= dClamp)
-- is assigned to it in one term.
function M.rollPmfForBandLuck(bandLuck: number): { number }
	local slimes = M.SlimeData.SLIMES
	local pmf = table.create(#slimes, 0)
	if bandLuck <= 0 then
		return pmf
	end
	local clampLuck = M.SlimeConfig.SLIME_LUCK_ANCHOR_LOW
		* (M.SlimeConfig.SLIME_LUCK_ANCHOR_HIGH / M.SlimeConfig.SLIME_LUCK_ANCHOR_LOW)
			^ M.SlimeConfig.SLIME_EXTRAPOLATION_T_MAX
	local remaining = 1.0
	local d = 0
	while true do
		local luck = bandLuck * 2 ^ d
		local weight
		if luck >= clampLuck then
			weight = remaining -- everything from here up is the same distribution
		else
			weight = remaining * (1 - M.BOX_P)
		end
		local tierWeights = M.SlimeRoll.distributionForLuck(luck)
		for tier, tierMass in tierWeights do
			if tierMass > 0 then
				local pool = M.SlimeData.SLIMES_BY_TIER[tier]
				local shares = withinTierShares(tier)
				if shares then
					for i, slime in pool do
						pmf[slime.globalIndex] += weight * tierMass * shares[i]
					end
				else
					local share = weight * tierMass / #pool
					for _, slime in pool do
						pmf[slime.globalIndex] += share
					end
				end
			end
		end
		if luck >= clampLuck then
			break
		end
		remaining -= weight
		d += 1
	end
	return pmf
end

-- The chest's table (the top tier's perfect launch clears the road entirely and
-- lands on the chest platform -- see perfectLaunchForTier). Mirrors
-- LaunchServer.server.luau's rollChestSlime exactly: a flat
-- CHEST_DIVINE_CHANCE for Divine off the top, the rest spread over tiers
-- 1..n-1 geometrically at CHEST_TIER_WEIGHT_RATIO, then split within the tier
-- by SlimeRoll.pickSlimeInTier -- which the chest now calls too, so the same
-- SLIME_TIER_WEIGHT_RATIO applies here. Uniform tiers keep the identical
-- `tierMass / #pool` expression they always had.
function M.chestPmf(): { number }
	local slimes = M.SlimeData.SLIMES
	local pmf = table.create(#slimes, 0)
	local tierCount = #M.SlimeConfig.SLIME_TIER_NAMES
	local weights, total = {}, 0
	for i = 1, tierCount - 1 do
		weights[i] = M.TreasureConfig.CHEST_TIER_WEIGHT_RATIO ^ (i - 1)
		total += weights[i]
	end
	for tier = 1, tierCount do
		local tierMass
		if tier == tierCount then
			tierMass = M.TreasureConfig.CHEST_DIVINE_CHANCE
		else
			tierMass = (1 - M.TreasureConfig.CHEST_DIVINE_CHANCE) * weights[tier] / total
		end
		local pool = M.SlimeData.SLIMES_BY_TIER[tier]
		local shares = withinTierShares(tier)
		if shares then
			for i, slime in pool do
				pmf[slime.globalIndex] += tierMass * shares[i]
			end
		else
			for _, slime in pool do
				pmf[slime.globalIndex] += tierMass / #pool
			end
		end
	end
	return pmf
end

function M.expectedIncomeOfPmf(pmf: { number }): number
	local total = 0
	for index, p in pmf do
		total += p * M.SlimeData.SLIMES[index].incomePerSecond
	end
	return total
end

-- Cost, in SECONDS OF BASE INCOME, of taking one slime from level 1 to
-- MAX_LEVEL. Derived from the real SlimeUpgrade.totalUpgradeCost against a
-- $1/s base rather than restated as a literal.
function M.costToMaxMultiplier(): number
	local cost = M.SlimeUpgrade.totalUpgradeCost(1, 1, M.SlimeUpgradeConfig.MAX_LEVEL)
	return cost
end

function M.maxLevelMultiplier(): number
	return M.SlimeUpgrade.incomeMultiplier(M.SlimeUpgradeConfig.MAX_LEVEL)
end

function M.fmt(n: number): string
	if n ~= n then
		return "nan"
	end
	local abs = math.abs(n)
	if abs >= 1e15 then
		return string.format("%.3gQa", n / 1e15)
	elseif abs >= 1e12 then
		return string.format("%.3gT", n / 1e12)
	elseif abs >= 1e9 then
		return string.format("%.3gB", n / 1e9)
	elseif abs >= 1e6 then
		return string.format("%.3gM", n / 1e6)
	elseif abs >= 1e3 then
		return string.format("%.3gK", n / 1e3)
	end
	return string.format("%.3g", n)
end

return M
