-- Solves the 10-tier swing ladder: visual scale first, then rope, then seat
-- offset, then the distance scale that lands a perfect launch on the CENTRE of
-- each target band. See REPORT.md.
--
--   lune run dev/analysis/solve_ladder.luau
--
-- Run from the REPO ROOT. Pure closed form, no sampling, no seed.
--
-- WHY THE ORDER MATTERS. Distance scale and visual scale are coupled through
-- the rope: the seat hangs at SWING_PIVOT_Z - ropeLength * sin(35 deg) at
-- sweet-spot phase, so a BIGGER swing starts its flight CLOSER to band 0 and
-- needs less distance to reach the same band. Solving distance first and
-- picking a visual scale afterwards lands tiers up to half a band out --
-- ECONOMY_DUMP.md made exactly that error by treating reach as raw launch
-- distance.
--
-- WHAT IS MIRRORED RATHER THAN REQUIRED: LaunchServer.server.luau is a .server
-- script and cannot be required. The three formulas taken from it are cited at
-- their use sites below. dev/analysis/common.luau is required READ-ONLY, for
-- the shim and the config modules only.
local C = require("./common")

local LaunchConfig = C.LaunchConfig
local LaneConfig = C.LaneConfig
local RunwayGeometry = C.RunwayGeometry
local SwingGeometry = C.SwingGeometry
local SwingTierVisuals = C.SwingTierVisuals

local SIN_SWEET_SPOT_THETA = math.sin(math.rad(LaunchConfig.SWING_ARC_HALF_ANGLE_DEGREES))
local BAND = LaunchConfig.RUNWAY_BAND_LENGTH_STUDS
local PERFECT_MULTIPLIER = LaunchConfig.SWEET_SPOT_MULTIPLIER

-- LaunchServer.server.luau:602-610 (swingSeatPosition) + :591-594 (swingTheta at
-- SWEET_SPOT_PHASE 0.25, where sin(2*pi*phase) = 1 so theta is the full arc).
local function seatZForScale(scale: number): number
	return LaneConfig.SWING_PIVOT_Z - SwingGeometry.ropeLengthForScale(scale) * SIN_SWEET_SPOT_THETA
end

-- How far the seat sits IN FRONT of band 0, i.e. how much of the launch
-- distance is spent before the road even starts.
local function seatOffsetForScale(scale: number): number
	return seatZForScale(scale) - RunwayGeometry.RUNWAY_START_Z
end

-- LaunchServer.server.luau:1882 (distance), :683-688 (trajectoryPosition at
-- u = 1), :736-746 (bandLuckForLandingZ).
local function landingForScales(visualScale: number, distanceScale: number)
	local distance = LaunchConfig.DISTANCE_PER_MULTIPLIER * PERFECT_MULTIPLIER * distanceScale
	local landingZ = seatZForScale(visualScale) - distance
	local fromStart = RunwayGeometry.RUNWAY_START_Z - landingZ
	local band = math.floor(fromStart / BAND)
	local zone = if fromStart < 0 then "short" elseif band > #C.LuckCurve.VALUES - 1 then "past" else "road"
	return distance, landingZ, fromStart, band, zone
end

--=================== 1d: the offset on the CURRENT ladder ===================--
print("== current ladder: seat offset per tier (1d) ==")
print("tier  visualScale  rope    seatZ    offset from band 0")
for tier = 1, #LaunchConfig.SWING_TIER_DISTANCE_SCALE do
	local scale = SwingTierVisuals.forTier(tier).scale
	print(string.format("%4d  %11.4f  %6.3f  %7.3f  %6.3f",
		tier, scale, SwingGeometry.ropeLengthForScale(scale), seatZForScale(scale), seatOffsetForScale(scale)))
end

--============================ The new ladder ============================--
-- Tier 1 and tier 10 are FIXED: tier 1 because baseDistance in the flight
-- duration formula is not tier-scaled and tier 1 is its normaliser; tier 10
-- because it is old tier 11 unchanged, the one that clears the road.
local TIER_COUNT = 10
local TARGET_BAND = { 4, 12, 20, 28, 36, 44, 52, 60, 68 } -- tiers 1..9; tier 10 leaves the road
local FIXED_VISUAL = { [1] = 1.0, [10] = 3.60 }
local FIXED_DISTANCE = { [1] = 1.0, [10] = 15.3552 }

-- Visual scale is GEOMETRIC between the two fixed ends. The old 11-entry
-- series was geometric to within a few percent (its ratios run 1.10-1.21 with
-- a geometric mean of 3.60^(1/10) = 1.1372), so this preserves the ladder's
-- existing character rather than imposing a new one; it also keeps every step
-- the same proportional jump, which is what "smoothly" has to mean for a
-- quantity that multiplies rather than adds.
local VISUAL_RATIO = FIXED_VISUAL[10] ^ (1 / (TIER_COUNT - 1))

local solved = {}
for tier = 1, TIER_COUNT do
	local visual = FIXED_VISUAL[tier]
	if not visual then
		-- Rounded to 2 dp, matching the precision every existing entry is
		-- written at. The distance scale is solved AFTER the rounding, against
		-- the rounded value, so the pair stays exactly consistent.
		visual = math.floor(VISUAL_RATIO ^ (tier - 1) * 100 + 0.5) / 100
	end
	local rope = SwingGeometry.ropeLengthForScale(visual)
	local offset = seatOffsetForScale(visual)

	local distanceScale
	if FIXED_DISTANCE[tier] then
		distanceScale = FIXED_DISTANCE[tier]
	else
		-- Solve for the CENTRE of the target band, not its edge.
		local targetFromStart = TARGET_BAND[tier] * BAND + BAND / 2
		local exact = (targetFromStart + offset) / (LaunchConfig.DISTANCE_PER_MULTIPLIER * PERFECT_MULTIPLIER)
		-- 4 dp = 0.02 studs of landing precision, far inside the 20-stud margin.
		distanceScale = math.floor(exact * 10000 + 0.5) / 10000
	end

	local distance, landingZ, fromStart, band, zone = landingForScales(visual, distanceScale)
	local lowEdge = band * BAND
	local highEdge = (band + 1) * BAND
	solved[tier] = {
		tier = tier,
		visualScale = visual,
		ropeLength = rope,
		seatOffset = offset,
		distanceScale = distanceScale,
		distance = distance,
		landingZ = landingZ,
		fromStart = fromStart,
		band = band,
		zone = zone,
		targetBand = TARGET_BAND[tier],
		marginToLowEdge = fromStart - lowEdge,
		marginToHighEdge = highEdge - fromStart,
	}
end

print("\n== solved ladder ==")
print("tier  visual  rope    offset   distScale   distance   landingZ    fromStart  band  target  margin-low  margin-high  flag")
for tier = 1, TIER_COUNT do
	local s = solved[tier]
	local targetText = if s.targetBand then tostring(s.targetBand) else "past"
	local ok = if s.zone == "past" then s.targetBand == nil else s.band == s.targetBand
	local tight = s.zone == "road" and (s.marginToLowEdge < 5 or s.marginToHighEdge < 5)
	print(string.format("%4d  %6.2f  %6.2f  %7.3f  %9.4f  %9.2f  %10.2f  %9.2f  %4d  %6s  %10.2f  %11.2f  %s",
		tier, s.visualScale, s.ropeLength, s.seatOffset, s.distanceScale, s.distance, s.landingZ,
		s.fromStart, s.band, targetText, s.marginToLowEdge, s.marginToHighEdge,
		(if ok then "ok" else "BAND MISMATCH") .. (if tight then " TIGHT (<5 studs)" else "")))
end

print("\n-- band step between consecutive tiers --")
for tier = 2, TIER_COUNT do
	local a, b = solved[tier - 1], solved[tier]
	print(string.format("  tier %d -> %d: %s", tier - 1, tier,
		if b.zone == "past" then "leaves the road (chest platform)" else tostring(b.band - a.band) .. " bands"))
end

print("\n-- the arrays to write --")
local visualOut, distanceOut = {}, {}
for tier = 1, TIER_COUNT do
	table.insert(visualOut, string.format("%.2f", solved[tier].visualScale))
	table.insert(distanceOut, if solved[tier].distanceScale == math.floor(solved[tier].distanceScale)
		then string.format("%.1f", solved[tier].distanceScale)
		else string.format("%.4f", solved[tier].distanceScale))
end
print("SWING_TIER_DISTANCE_SCALE = { " .. table.concat(distanceOut, ", ") .. " },")
print("visual scale per tier      = { " .. table.concat(visualOut, ", ") .. " }")
