-- Step 1 of the accumulate-and-collect pass: flight duration becomes a linear
-- function of the TIER INDEX (tier N flies for N + 1 seconds), replacing the
-- power-of-distance form. See REPORT.md.
--
--   lune run dev/analysis/flight_tier_pacing.luau
--
-- Run from the REPO ROOT. Pure closed form -- no sampling, no seed. Prints to
-- stdout only; writes nothing to dev/out.
--
-- The NEW duration comes from the real LaunchConfig, through
-- C.flightDurationForTier, which is the one mirror of LaunchServer's onRelease
-- in this directory. The OLD duration is carried here as two local constants
-- because both were REMOVED from LaunchConfig by this pass -- they are marked
-- as historical below and nothing reads them but the before/after table.
--
-- The cycle phases are the ones dev/out/cycle_economics.json measured, held
-- fixed: only the flight term moves. They rest on that pass's stated
-- assumptions (perfect play hits the sweet spot on the first pass; the walk
-- speed is Roblox's default 16, which this repo never configures).
local C = require("./common")

local LaunchConfig = C.LaunchConfig
local tierCount = #LaunchConfig.SWING_TIER_DISTANCE_SCALE

-- Retired by this pass -- see LaunchConfig's FLIGHT_DURATION_BASE_SECONDS block.
local RETIRED_FLIGHT_DURATION_SECONDS = 1.8
local RETIRED_FLIGHT_DURATION_EXPONENT = 0.35
local BASE_DISTANCE = LaunchConfig.DISTANCE_PER_MULTIPLIER * LaunchConfig.SWEET_SPOT_MULTIPLIER

-- Perfect-play phases from cycle_economics.json, unchanged by this pass.
local BAR_WAIT = 1.20
local REWARD_BOX = 2.00
local REWARD_CHEST = 3.35
local RETURN_WALK = 0.25

local function oldDurationFor(distance: number): number
	return RETIRED_FLIGHT_DURATION_SECONDS * (distance / BASE_DISTANCE) ^ RETIRED_FLIGHT_DURATION_EXPONENT
end

local facts = {}
for tier = 1, tierCount do
	facts[tier] = C.perfectLaunchForTier(tier)
end

print(string.format("FLIGHT_DURATION_BASE_SECONDS %.2f, FLIGHT_DURATION_PER_TIER_SECONDS %.2f -- tier N flies N + 1 s",
	LaunchConfig.FLIGHT_DURATION_BASE_SECONDS, LaunchConfig.FLIGHT_DURATION_PER_TIER_SECONDS))
print(string.format("retired: FLIGHT_DURATION_SECONDS %.2f, FLIGHT_DURATION_EXPONENT %.2f",
	RETIRED_FLIGHT_DURATION_SECONDS, RETIRED_FLIGHT_DURATION_EXPONENT))

--=========== 1a: no exponent can produce evenly spaced durations ===========--
-- Fit the exponent to hit BOTH ends of the wanted table exactly (2 s at tier 1,
-- 11 s at tier 10) and measure what the middle does. Solved, not searched:
-- want 2 * s10^e = 11, so e = ln(11/2) / ln(s10).
print("\n1a. why the exponent form was abandoned")
local topScale = LaunchConfig.SWING_TIER_DISTANCE_SCALE[tierCount]
local fittedExponent = math.log(11 / 2) / math.log(topScale)
print(string.format("  best-fit exponent through both endpoints: %.6f", fittedExponent))
print("tier  distance   want     power-law     error")
local worstError = 0
for tier = 1, tierCount do
	local want = tier + 1
	local got = 2 * (LaunchConfig.SWING_TIER_DISTANCE_SCALE[tier] ^ fittedExponent)
	local err = got - want
	if math.abs(err) > math.abs(worstError) then
		worstError = err
	end
	print(string.format("%4d  %8.1f  %5.2f  %11.4f  %+8.4f", tier, facts[tier].distance, want, got, err))
end
print(string.format("  worst deviation %+.4f s -- the middle of the ladder bulges, which is what rules the form out", worstError))
print("  cause: SWING_TIER_DISTANCE_SCALE is spaced to land each tier on an evenly spaced BAND,")
print("  so distance is near-linear in tier -- and any power of a near-linear sequence is a curve.")

--============== 1f: the before/after table, all ten tiers ==============--
print("\n1f. flight duration, speed, cycle and launches per minute (perfect play)")
print("      (bar 1.20s + flight + reward 2.00s box / 3.35s chest + return 0.25s)")
print("tier  distance  reward  flight old  flight new  change     st/s old  st/s new  cycle old  cycle new  l/min old  l/min new  flight share old  new")
local rows = {}
for tier = 1, tierCount do
	local distance = facts[tier].distance
	local isChest = facts[tier].zone == "past"
	local reward = if isChest then REWARD_CHEST else REWARD_BOX
	local fixed = BAR_WAIT + reward + RETURN_WALK
	local oldDuration = oldDurationFor(distance)
	local newDuration = C.flightDurationForTier(tier)
	local oldCycle = fixed + oldDuration
	local newCycle = fixed + newDuration
	rows[tier] = {
		distance = distance,
		oldDuration = oldDuration,
		newDuration = newDuration,
		oldCycle = oldCycle,
		newCycle = newCycle,
	}
	print(string.format("%4d  %8.1f  %6s  %10.4f  %10.4f  %+7.1f%%  %8.1f  %8.1f  %9.2f  %9.2f  %9.2f  %9.2f  %15.1f%%  %4.1f%%",
		tier, distance, if isChest then "chest" else "box",
		oldDuration, newDuration, (newDuration / oldDuration - 1) * 100,
		distance / oldDuration, distance / newDuration,
		oldCycle, newCycle, 60 / oldCycle, 60 / newCycle,
		oldDuration / oldCycle * 100, newDuration / newCycle * 100))
end

--=== 1c: the landing cannot move, because the formula has no time term ===--
-- trajectoryPosition(startPosition, distance, archHeight, u) is:
--   z = startPosition.Z - distance * u
-- LaunchServer's onRelease calls it ONCE with u = 1 as a literal and resolves
-- bandLuckForLandingZ immediately, so the band and zone are decided before the
-- first frame of flight exists. Duration decides only WHEN the Heartbeat loop
-- places the character. This evaluates the landing under BOTH durations to show
-- the value is bit-identical, not merely close.
print("\n1c. landing under the old duration vs the new one")
print("tier  flight old  flight new   landing Z old    landing Z new  band old  band new  zone      identical")
local allIdentical = true
for tier = 1, tierCount do
	local f = facts[tier]
	-- The same closed form, evaluated twice with the two durations in scope.
	-- Neither expression can reference duration -- that is the point.
	local landingZOld = f.seatZ - f.distance * 1
	local landingZNew = f.seatZ - f.distance * 1
	local fromStartOld = C.RunwayGeometry.RUNWAY_START_Z - landingZOld
	local fromStartNew = C.RunwayGeometry.RUNWAY_START_Z - landingZNew
	local bandOld = math.floor(fromStartOld / LaunchConfig.RUNWAY_BAND_LENGTH_STUDS)
	local bandNew = math.floor(fromStartNew / LaunchConfig.RUNWAY_BAND_LENGTH_STUDS)
	local same = landingZOld == landingZNew and bandOld == bandNew
	if not same then
		allIdentical = false
	end
	print(string.format("%4d  %10.4f  %10.4f  %14.4f  %14.4f  %8d  %8d  %-8s  %s",
		tier, rows[tier].oldDuration, rows[tier].newDuration,
		landingZOld, landingZNew, bandOld, bandNew, f.zone, if same then "yes" else "NO"))
end
print(string.format("  every landing identical: %s", tostring(allIdentical)))

-- What DID change: the same curve is traversed at a different rate. Sampling
-- mid-flight shows the path is the same shape and only the clock differs.
print("\n  mid-flight, to show what actually moved: position at a fixed 1.0 s after release")
print("tier    u old    u new   Z at 1s old   Z at 1s new")
for tier = 1, tierCount do
	local f = facts[tier]
	local uOld = math.min(1, 1.0 / rows[tier].oldDuration)
	local uNew = math.min(1, 1.0 / rows[tier].newDuration)
	print(string.format("%4d  %7.4f  %7.4f  %12.2f  %12.2f",
		tier, uOld, uNew, f.seatZ - f.distance * uOld, f.seatZ - f.distance * uNew))
end
print("  same curve, different clock -- u = 1 is the only point the landing reads, and it is fixed.")

--============ 1e: the outcome word's rainbow sweeps, per tier ============--
-- OUTCOME_RAINBOW_CYCLES_PER_SECOND's own comment reasons about "the flight
-- plus RESET_DELAY -- a few seconds -- so 0.6 gives it two or three visible
-- sweeps." Reported, not changed.
print("\n1e. outcome-word rainbow sweeps (OUTCOME_RAINBOW_CYCLES_PER_SECOND = "
	.. string.format("%.2f, RESET_DELAY = %.2f)", LaunchConfig.OUTCOME_RAINBOW_CYCLES_PER_SECOND, LaunchConfig.RESET_DELAY))
print("tier  on-screen old  on-screen new  sweeps old  sweeps new")
for tier = 1, tierCount do
	local onScreenOld = rows[tier].oldDuration + LaunchConfig.RESET_DELAY
	local onScreenNew = rows[tier].newDuration + LaunchConfig.RESET_DELAY
	print(string.format("%4d  %13.2f  %13.2f  %10.2f  %10.2f",
		tier, onScreenOld, onScreenNew,
		onScreenOld * LaunchConfig.OUTCOME_RAINBOW_CYCLES_PER_SECOND,
		onScreenNew * LaunchConfig.OUTCOME_RAINBOW_CYCLES_PER_SECOND))
end

--=== The within-tier consequence: duration no longer varies with release ===--
-- distance = DISTANCE_PER_MULTIPLIER * multiplier * tierScale, so the worst
-- release covers WORST_MULTIPLIER / SWEET_SPOT_MULTIPLIER of a perfect one's
-- ground. Under the old form the duration shrank with it; now it does not.
print("\nwithin-tier: a mistimed release now takes the SAME time as a perfect one")
local worstRatio = LaunchConfig.WORST_MULTIPLIER / LaunchConfig.SWEET_SPOT_MULTIPLIER
print(string.format("  worst release covers %.3fx the distance (multiplier %.2f vs %.2f)",
	worstRatio, LaunchConfig.WORST_MULTIPLIER, LaunchConfig.SWEET_SPOT_MULTIPLIER))
print(string.format("  old: speed ratio %.3fx (duration shrank as distance^%.2f)",
	worstRatio ^ (1 - RETIRED_FLIGHT_DURATION_EXPONENT), RETIRED_FLIGHT_DURATION_EXPONENT))
print(string.format("  new: speed ratio %.3fx (duration fixed by tier, so speed falls with distance)", worstRatio))
print("tier  perfect st/s  worst st/s (new)  worst flight seconds")
for tier = 1, tierCount do
	local d = rows[tier].newDuration
	print(string.format("%4d  %12.1f  %16.1f  %20.2f",
		tier, rows[tier].distance / d, rows[tier].distance * worstRatio / d, d))
end
