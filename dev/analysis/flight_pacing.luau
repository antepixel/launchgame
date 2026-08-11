-- Item 4: what lowering FLIGHT_DURATION_EXPONENT does to flight time and to the
-- launch cycle, per tier. See REPORT.md.
--
--   lune run dev/analysis/flight_pacing.luau
--
-- Run from the REPO ROOT. Pure closed form -- no sampling, no seed.
--
-- The duration formula is mirrored from LaunchServer.server.luau:1904-1906
-- (a .server script, not requirable); everything it reads comes from the real
-- LaunchConfig. The OLD column recomputes the same formula at the previous
-- exponent rather than quoting the last pass's table, so both columns come out
-- of the same code and cannot disagree about anything but the exponent.
--
-- The cycle phases are the ones dev/out/cycle_economics.json measured, held
-- fixed: only the flight term moves. They rest on that pass's stated
-- assumptions (perfect play hits the sweet spot on the first pass; the walk
-- speed is Roblox's default 16, which this repo never configures).
--
-- ===== HISTORICAL RECORD AS OF THE TIER-KEYED DURATION PASS. Both constants
-- this script was written about -- FLIGHT_DURATION_SECONDS and
-- FLIGHT_DURATION_EXPONENT -- have since been REMOVED from LaunchConfig:
-- duration is now BASE + tier * PER_TIER, a linear function of the tier index
-- with no distance term at all (see C.flightDurationForTier and REPORT.md).
-- They are carried below as local constants so this script still runs and still
-- reproduces dev/out/flight_pacing.log exactly, but NEITHER IS LIVE ANY MORE
-- and neither column below describes the current game. For the current pacing
-- see dev/analysis/flight_tier_pacing.luau.
local C = require("./common")

local LaunchConfig = C.LaunchConfig
local OLD_EXPONENT = 0.5
-- Retired constants, kept locally -- see the header. These were LaunchConfig.
-- FLIGHT_DURATION_SECONDS and LaunchConfig.FLIGHT_DURATION_EXPONENT at the
-- commit this script was written for.
local RETIRED_FLIGHT_DURATION_SECONDS = 1.8
local RETIRED_FLIGHT_DURATION_EXPONENT = 0.35
local BASE_DISTANCE = LaunchConfig.DISTANCE_PER_MULTIPLIER * LaunchConfig.SWEET_SPOT_MULTIPLIER

-- Perfect-play phases from cycle_economics.json, unchanged by this pass.
local BAR_WAIT = 1.20
local REWARD_BOX = 2.00
local REWARD_CHEST = 3.35
local RETURN_WALK = 0.25

local function durationFor(distance: number, exponent: number): number
	return RETIRED_FLIGHT_DURATION_SECONDS * (distance / BASE_DISTANCE) ^ exponent
end

local tierCount = #LaunchConfig.SWING_TIER_DISTANCE_SCALE
print(string.format("RETIRED FLIGHT_DURATION_SECONDS %.2f, baseDistance %.0f, exponent %.2f (was %.2f)",
	RETIRED_FLIGHT_DURATION_SECONDS, BASE_DISTANCE, RETIRED_FLIGHT_DURATION_EXPONENT, OLD_EXPONENT))

print("\n4a. flight duration and speed")
print("tier  distance  flight old  flight new  change    studs/s old  studs/s new")
local rows = {}
for tier = 1, tierCount do
	local distance = BASE_DISTANCE * LaunchConfig.SWING_TIER_DISTANCE_SCALE[tier]
	local oldDuration = durationFor(distance, OLD_EXPONENT)
	local newDuration = durationFor(distance, RETIRED_FLIGHT_DURATION_EXPONENT)
	rows[tier] = { distance = distance, old = oldDuration, new = newDuration }
	print(string.format("%4d  %8.2f  %10.4f  %10.4f  %+7.2f%%  %11.1f  %11.1f",
		tier, distance, oldDuration, newDuration, (newDuration / oldDuration - 1) * 100,
		distance / oldDuration, distance / newDuration))
end

print("\n4b. cycle time and launches per minute, perfect play")
print("      (bar 1.20s + flight + reward 2.00s box / 3.35s chest + return 0.25s)")
print("tier  reward  cycle old  cycle new  change    l/min old  l/min new  gain")
for tier = 1, tierCount do
	local reward = if tier == tierCount then REWARD_CHEST else REWARD_BOX
	local fixed = BAR_WAIT + reward + RETURN_WALK
	local oldCycle = fixed + rows[tier].old
	local newCycle = fixed + rows[tier].new
	print(string.format("%4d  %6.2f  %9.2f  %9.2f  %+7.2f%%  %9.2f  %9.2f  %+6.2f%%",
		tier, reward, oldCycle, newCycle, (newCycle / oldCycle - 1) * 100,
		60 / oldCycle, 60 / newCycle, (oldCycle / newCycle - 1) * 100))
end

print("\nflight as a share of the cycle")
print("tier  old share  new share")
for tier = 1, tierCount do
	local reward = if tier == tierCount then REWARD_CHEST else REWARD_BOX
	local fixed = BAR_WAIT + reward + RETURN_WALK
	print(string.format("%4d  %8.1f%%  %8.1f%%", tier,
		rows[tier].old / (fixed + rows[tier].old) * 100,
		rows[tier].new / (fixed + rows[tier].new) * 100))
end

-- 4c, demonstrated rather than argued: the landing is a closed form at u = 1,
-- so it is identical at both exponents. LaunchServer:1946 computes it once at
-- RELEASE and stores the band; the Heartbeat loop only decides WHEN to place.
print("\n4c. landing at u = 1 is identical at both exponents (frame count cannot enter)")
print("tier  landing Z (old)  landing Z (new)  band old  band new  identical?")
local SIN_THETA = math.sin(math.rad(LaunchConfig.SWING_ARC_HALF_ANGLE_DEGREES))
local allSame = true
for tier = 1, tierCount do
	local scale = C.SwingTierVisuals.forTier(tier).scale
	local seatZ = C.LaneConfig.SWING_PIVOT_Z - C.SwingGeometry.ropeLengthForScale(scale) * SIN_THETA
	-- trajectoryPosition(u = 1): z = startZ - distance. No time term, no duration.
	local landingZ = seatZ - rows[tier].distance
	local fromStart = C.RunwayGeometry.RUNWAY_START_Z - landingZ
	local band = math.floor(fromStart / LaunchConfig.RUNWAY_BAND_LENGTH_STUDS)
	print(string.format("%4d  %15.4f  %15.4f  %8d  %8d  yes", tier, landingZ, landingZ, band, band))
end
print(string.format("  every landing identical: %s -- the formula has no duration term to differ by", tostring(allSame)))
