-- Reads the EDITED ladder back and pushes it forward through the real
-- formulas. Nothing here is taken from dev/analysis/solve_ladder.luau: this
-- loads the arrays as the game loads them and re-derives every landing, so a
-- solve that agreed with itself and disagreed with the tree cannot pass.
--
--   lune run dev/analysis/verify_ladder.luau
--
-- Run from the REPO ROOT. Deterministic; no sampling, no seed.
--
-- REQUIRED FOR REAL through dev/rbxshim.luau: LaunchConfig, SwingTierVisuals,
-- SwingGeometry, LaneConfig, RunwayGeometry, LuckCurve, ShopConfig, SlimeConfig,
-- SlimeData and SlimeRoll (the distribution itself, via
-- dev/analysis/common.luau's exact box-chain integrator).
--
-- MIRRORED, because LaunchServer.server.luau is a .server script and cannot be
-- required: the distance formula (:1882), trajectoryPosition at u = 1 (:683),
-- bandLuckForLandingZ (:736-746), the arch height (:1888) and the flight
-- duration (:1896-1897). Each is cited at its use site.
local C = require("./common")

local LaunchConfig = C.LaunchConfig
local SwingGeometry = C.SwingGeometry
local SwingTierVisuals = C.SwingTierVisuals
local LuckCurve = C.LuckCurve
local SlimeConfig = C.SlimeConfig

local TARGET_BAND = { 4, 12, 20, 28, 36, 44, 52, 60, 68 }
local BAND = LaunchConfig.RUNWAY_BAND_LENGTH_STUDS
local SIN_THETA = math.sin(math.rad(LaunchConfig.SWING_ARC_HALF_ANGLE_DEGREES))

local tierCount = #LaunchConfig.SWING_TIER_DISTANCE_SCALE
-- Two severities, because the brief has two. A FAILURE is one of its stop
-- conditions -- an array length, the moved snap override, a band that does not
-- match the solve, a broken monotonicity invariant. A WARNING is a measurement
-- the brief asks to be reported plainly if it comes out a certain way (the
-- 1.5x box-multiple floor); it is a finding about the change, not a defect in
-- applying it, and it must not be buried in a pass/fail line.
local failures, warnings = {}, {}
local function check(condition: boolean, message: string)
	if not condition then
		table.insert(failures, message)
	end
end
local function warnIf(condition: boolean, message: string)
	if not condition then
		table.insert(warnings, message)
	end
end

--============================ Array lengths ============================--
print("== array lengths and the moved override ==")
print(string.format("SWING_TIER_DISTANCE_SCALE  %d entries", tierCount))
print(string.format("SWING_TIER_SNAP_THRESHOLD  %d entries", #LaunchConfig.SWING_TIER_SNAP_THRESHOLD))
print(string.format("SwingTierVisuals.TIERS     %d entries", #SwingTierVisuals.TIERS))
print(string.format("SWING_TIER_PRICES          %d entries", #C.ShopConfig.SWING_TIER_PRICES))
check(tierCount == 10, "SWING_TIER_DISTANCE_SCALE is not 10 entries")
check(#LaunchConfig.SWING_TIER_SNAP_THRESHOLD == tierCount, "snap threshold array length disagrees with the tier count")
check(#SwingTierVisuals.TIERS == tierCount, "SwingTierVisuals.TIERS length disagrees with the tier count")
check(#C.ShopConfig.SWING_TIER_PRICES == tierCount, "SWING_TIER_PRICES length disagrees with the tier count")

-- 3b, read back rather than assumed: the 1.95 override must sit at the top
-- index and nowhere else.
for tier = 1, tierCount do
	local threshold = LaunchConfig.SWING_TIER_SNAP_THRESHOLD[tier]
	local expected = if tier == tierCount then 1.95 else LaunchConfig.SWEET_SPOT_SNAP_THRESHOLD
	check(threshold == expected, string.format("snap threshold at tier %d is %s, expected %s", tier, tostring(threshold), tostring(expected)))
end
print(string.format("snap threshold read back: tier %d = %.2f, every other tier = %.2f",
	tierCount, LaunchConfig.SWING_TIER_SNAP_THRESHOLD[tierCount], LaunchConfig.SWEET_SPOT_SNAP_THRESHOLD))

check(LaunchConfig.SWING_TIER_DISTANCE_SCALE[1] == 1.0, "tier 1 distance scale is not exactly 1.0")
check(SwingTierVisuals.forTier(1).scale == 1.0, "tier 1 visual scale is not exactly 1.0")
check(LaunchConfig.SWING_TIER_DISTANCE_SCALE[tierCount] == 15.3552, "top tier distance scale is not 15.3552")
check(SwingTierVisuals.forTier(tierCount).scale == 3.6, "top tier visual scale is not 3.6")

--======================= Forward through the formulas =======================--
print("\n== landing read back through the real formulas ==")
print("tier  visual  rope    distScale   distance   landingZ    fromStart  band  target  match  preBoxLuck  flight(s)  arch     angle")
local rows = {}
for tier = 1, tierCount do
	local visual = SwingTierVisuals.forTier(tier).scale
	local rope = SwingGeometry.ropeLengthForScale(visual)
	local distanceScale = LaunchConfig.SWING_TIER_DISTANCE_SCALE[tier]
	-- LaunchServer:1882
	local distance = LaunchConfig.DISTANCE_PER_MULTIPLIER * LaunchConfig.SWEET_SPOT_MULTIPLIER * distanceScale
	-- LaunchServer:602-610 seat, then :683-688 trajectoryPosition at u = 1
	local seatZ = C.LaneConfig.SWING_PIVOT_Z - rope * SIN_THETA
	local landingZ = seatZ - distance
	-- LaunchServer:736-746 bandLuckForLandingZ
	local fromStart = C.RunwayGeometry.RUNWAY_START_Z - landingZ
	local band, zone, luck
	if fromStart < 0 then
		band, zone, luck = -1, "short", 0
	else
		band = math.floor(fromStart / BAND)
		if band > #LuckCurve.VALUES - 1 then
			zone, luck = "past", 0
		else
			zone, luck = "road", LuckCurve.VALUES[band + 1]
		end
	end
	-- LaunchServer arch, LaunchFormulas trajectoryPitch at u = 0. Duration is
	-- keyed off the TIER now, not off distance -- see C.flightDurationForTier,
	-- which mirrors the live formula.
	local archHeight = LaunchConfig.ARC_HEIGHT_SQRT_COEFFICIENT * math.sqrt(distance)
	local duration = C.flightDurationForTier(tier)
	local pivotY = SwingGeometry.pivotYForScale(visual)
	local startY = pivotY - rope * math.cos(math.rad(LaunchConfig.SWING_ARC_HALF_ANGLE_DEGREES)) + LaunchConfig.RIDER_SEAT_HEIGHT_OFFSET
	local descentRate = C.RunwayGeometry.RUNWAY_TOP_Y - startY
	local angle = math.deg(math.clamp(math.atan2(descentRate + archHeight * 4, distance), -math.rad(25), math.rad(25)))

	local target = TARGET_BAND[tier]
	local matches = if target then band == target and zone == "road" else zone == "past"
	check(matches, string.format("tier %d landed on band %d (%s), expected %s", tier, band, zone, if target then tostring(target) else "past the road"))
	rows[tier] = { tier = tier, band = band, zone = zone, luck = luck, distance = distance, duration = duration }
	print(string.format("%4d  %6.2f  %6.2f  %9.4f  %9.2f  %10.2f  %9.2f  %4d  %6s  %5s  %10s  %9.4f  %7.2f  %6.2f",
		tier, visual, rope, distanceScale, distance, landingZ, fromStart, band,
		if target then tostring(target) else "past", if matches then "yes" else "NO",
		if zone == "road" then LuckCurve.formatLuck(luck) else "-- (chest)", duration, archHeight, angle))
end

print("\n-- band step between consecutive tiers --")
for tier = 2, tierCount do
	local a, b = rows[tier - 1], rows[tier]
	if b.zone == "past" then
		print(string.format("  tier %d -> %d: leaves the road", tier - 1, tier))
	else
		local step = b.band - a.band
		check(step == 8, string.format("band step from tier %d to %d is %d, expected 8", tier - 1, tier, step))
		print(string.format("  tier %d -> %d: %d bands", tier - 1, tier, step))
	end
end

--=================== Roll value at the new luck clamp ===================--
print(string.format("\n== roll value per tier (SLIME_LUCK_ANCHOR_HIGH = %s, T_MAX = %s) ==",
	tostring(SlimeConfig.SLIME_LUCK_ANCHOR_HIGH), tostring(SlimeConfig.SLIME_EXTRAPOLATION_T_MAX)))
print("tier  preBoxLuck  E[base]/roll no box  E[base]/roll with box  box multiple")
for tier = 1, tierCount do
	local r = rows[tier]
	if r.zone ~= "road" then
		print(string.format("%4d  %10s  (chest table -- no box on this path)", tier, "--"))
		continue
	end
	local weights = C.SlimeRoll.distributionForLuck(r.luck)
	local noBox = 0
	for t, mass in weights do
		if mass > 0 then
			local pool = C.SlimeData.SLIMES_BY_TIER[t]
			local mean = 0
			for _, s in pool do
				mean += s.incomePerSecond
			end
			noBox += mass * mean / #pool
		end
	end
	local withBox = C.expectedIncomeOfPmf(C.rollPmfForBandLuck(r.luck))
	local multiple = withBox / noBox
	warnIf(multiple >= 1.5, string.format("tier %d (luck %s) box multiple is %.3fx, under the 1.5x floor", tier, LuckCurve.formatLuck(r.luck), multiple))
	print(string.format("%4d  %10s  $%-18s  $%-20s  %.2fx", tier, LuckCurve.formatLuck(r.luck), C.fmt(noBox), C.fmt(withBox), multiple))
end

--===================== Monotonicity across all 74 bands =====================--
local worstDrop, worstAt, previous = 0, nil, nil
for _, luck in LuckCurve.VALUES do
	local weights = C.SlimeRoll.distributionForLuck(luck)
	local ev = 0
	for t, mass in weights do
		if mass > 0 then
			local pool = C.SlimeData.SLIMES_BY_TIER[t]
			local mean = 0
			for _, s in pool do
				mean += s.incomePerSecond
			end
			ev += mass * mean / #pool
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
print(string.format("\nmonotonicity over %d band lucks: worst decreasing step %.4e%s",
	#LuckCurve.VALUES, worstDrop, if worstAt then string.format(" at luck %d", worstAt) else " (none)"))
check(worstDrop <= 1e-9, string.format("expected income per roll is NOT monotonic in luck: worst drop %.4e at luck %s", worstDrop, tostring(worstAt)))

--============================ Step 5: the clamp ============================--
-- PlayerProfile.applyLoadedData:640-643 is
--     profile.swingTier = math.clamp(math.floor(data.swingTier), 1, tierCount)
-- with tierCount = #LaunchConfig.SWING_TIER_DISTANCE_SCALE. PlayerProfile
-- itself cannot be required under the shim (it reaches for Players, HttpService
-- and DataStores), so what is exercised here is that exact expression against
-- the same live array -- not a copy of the rule with its own constant.
print("\n== saved swingTier on load (PlayerProfile.applyLoadedData:640-643) ==")
print("saved  loads as  note")
for _, saved in { 1, 9, 10, 11, 12, 99, 0, -3, 10.7 } do
	local loaded = math.clamp(math.floor(saved), 1, tierCount)
	local note = if saved > tierCount then "clamped down to the top tier"
		elseif saved < 1 then "clamped up to tier 1"
		elseif saved ~= math.floor(saved) then "floored"
		else "unchanged"
	print(string.format("%5s  %8d  %s", tostring(saved), loaded, note))
end
check(math.clamp(math.floor(11), 1, tierCount) == tierCount, "a saved tier 11 does not land on the top tier")
check(math.clamp(math.floor(99), 1, tierCount) == tierCount, "a wildly out-of-range saved tier does not clamp to the top tier")
check(math.clamp(math.floor(0), 1, tierCount) == 1, "a saved tier below 1 does not clamp to 1")

--=============================== The verdict ===============================--
if #failures == 0 then
	print("\nVERIFY PASSED: every stop-condition check agrees with the edited tree.")
else
	print(string.format("\nVERIFY FAILED (%d):", #failures))
	for _, f in failures do
		print("  - " .. f)
	end
end
if #warnings > 0 then
	print(string.format("\nWARNINGS (%d) -- reported, not fixed:", #warnings))
	for _, w in warnings do
		print("  - " .. w)
	end
end
