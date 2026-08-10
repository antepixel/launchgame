-- The launch CYCLE: every phase between one release and the next, per swing
-- tier, joined against dev/out/roll_economics.json to turn income-per-roll into
-- income per real minute. See REPORT.md.
--
--   lune run dev/analysis/cycle_time.luau
--
-- Run from the REPO ROOT. Pure analytic plus one fine phase scan -- no random
-- sampling, no seed. Writes dev/out/cycle_economics.json.
--
-- REFUSES TO RUN against a stale join: the git commit recorded in
-- roll_economics.json must equal the current HEAD.
--
-- Requires the REAL LaunchFormulas for the multiplier/pitch math. What it
-- cannot require, and therefore mirrors with the source line cited at each
-- site: LaunchServer.server.luau (a .server script) for the distance, flight
-- duration and band-from-landing formulas, and MapBuilder.server.luau (ditto)
-- for the chest's derived Z.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local C = require("./common")

local commit = (process.exec("git", { "rev-parse", "HEAD" }).stdout:gsub("%s+$", ""))
local econ = serde.decode("json", fs.readFile("dev/out/roll_economics.json"))
if econ.gitCommit ~= commit then
	error(string.format(
		"STOP: dev/out/roll_economics.json was measured at %s but HEAD is %s -- stale join, refusing to proceed",
		tostring(econ.gitCommit), commit))
end

local shim = C.shim
local LaunchFormulas = shim.loadLuauModule("src/ReplicatedStorage/LaunchClient/LaunchFormulas.luau")
local SlimeConfig = C.SlimeConfig
local TreasureConfig = C.TreasureConfig
local LaunchConfig = C.LaunchConfig
local GiantSlimeConfig = shim.loadLuauModule("src/ReplicatedStorage/Config/GiantSlimeConfig.luau")

local PERIOD = LaunchConfig.SWING_PERIOD_SECONDS
local TIERS = C.SWING_TIER_COUNT

--======================== Band from a launch multiplier ========================--
-- Mirrors LaunchServer.server.luau:1882 (distance), :683 (trajectoryPosition at
-- u = 1) and :736 (bandLuckForLandingZ). seatZ is the sweet-spot seat position
-- already derived in common.luau.
local function landingForMultiplier(tier: number, seatZ: number, multiplier: number)
	local distance = LaunchConfig.DISTANCE_PER_MULTIPLIER * multiplier * LaunchConfig.SWING_TIER_DISTANCE_SCALE[tier]
	local landingZ = seatZ - distance
	local fromStart = C.RunwayGeometry.RUNWAY_START_Z - landingZ
	if fromStart < 0 then
		return distance, -1, "short"
	end
	local index = math.floor(fromStart / LaunchConfig.RUNWAY_BAND_LENGTH_STUDS)
	if index > #C.LuckCurve.VALUES - 1 then
		return distance, index, "past"
	end
	return distance, index, "road"
end

--=========================== STEP 2: the bar window ===========================--
-- Scanned against the REAL LaunchFormulas.launchMultiplier at 1e-7 phase
-- resolution (2.4e-7 s), over the whole sweet-spot window. Outside that window
-- the multiplier caps at EDGE_MULTIPLIER (1.5), i.e. 75% of a perfect launch,
-- which lands whole bands short -- so nothing outside it can reach a
-- perfect-launch band and the scan does not need to cover the rest of the sweep.
local SCAN_STEPS = 1200000
local function barWindowsForTier(tier: number, seatZ: number)
	local half = LaunchConfig.SWEET_SPOT_WIDTH / 2
	local lo = LaunchConfig.SWEET_SPOT_PHASE - half
	local step = (2 * half) / SCAN_STEPS
	local _, perfectBand, perfectZone = landingForMultiplier(tier, seatZ, LaunchConfig.SWEET_SPOT_MULTIPLIER)

	local snapSteps, sameOutcomeSteps, chestSteps = 0, 0, 0
	-- The CONSOLATION RING is not "the band below" -- at high tier scales one
	-- band is only a sliver of the graded range, so the band immediately below
	-- the perfect one is often unreachable entirely. It is defined here as the
	-- BEST outcome still reachable that is not the perfect one, found from the
	-- scan itself rather than assumed.
	local bandSteps: { [number]: number } = {}
	for i = 0, SCAN_STEPS do
		local phase = lo + i * step
		local m = LaunchFormulas.launchMultiplier(phase, tier)
		if m >= LaunchConfig.SWEET_SPOT_MULTIPLIER then
			snapSteps += 1
		end
		local _, band, zone = landingForMultiplier(tier, seatZ, m)
		if zone == perfectZone and (zone ~= "road" or band == perfectBand) then
			sameOutcomeSteps += 1
		end
		if zone == "past" then
			chestSteps += 1
		end
		if zone == "road" then
			bandSteps[band] = (bandSteps[band] or 0) + 1
		end
	end
	local ringBand, ringSteps = -1, 0
	for band, steps in bandSteps do
		local isPerfect = perfectZone == "road" and band == perfectBand
		if not isPerfect and band > ringBand then
			ringBand, ringSteps = band, steps
		end
	end
	local perStep = step * PERIOD
	return {
		perfectBand = perfectBand,
		perfectZone = perfectZone,
		snapSeconds = snapSteps * perStep,
		sameOutcomeSeconds = sameOutcomeSteps * perStep,
		chestSeconds = chestSteps * perStep,
		ringBand = ringBand,
		ringSeconds = ringSteps * perStep,
		snapThreshold = LaunchFormulas.snapThresholdForTier(tier),
	}
end

--=========================== STEP 3: the flight ===========================--
-- distance/arch: LaunchServer.server.luau:1882/:1888. duration: :1896-1897 --
-- NOT in LaunchFormulas, see REPORT.md. Launch angle is the client's own
-- trajectoryPitch at u = 0 (LaunchFormulas, required for real).
local BASE_DISTANCE = LaunchConfig.DISTANCE_PER_MULTIPLIER * LaunchConfig.SWEET_SPOT_MULTIPLIER
local function flightForTier(tier: number)
	local facts = C.perfectLaunchForTier(tier)
	local distance = facts.distance
	local archHeight = LaunchConfig.ARC_HEIGHT_SQRT_COEFFICIENT * math.sqrt(distance)
	local duration = LaunchConfig.FLIGHT_DURATION_SECONDS * (distance / BASE_DISTANCE) ^ LaunchConfig.FLIGHT_DURATION_EXPONENT
	-- Launch height: the seat plus the rider offset, exactly as onRelease builds
	-- startPosition (LaunchServer:1906) -- pivot Y from SwingGeometry, minus the
	-- rope's vertical component at the sweet-spot theta.
	local scale = C.SwingTierVisuals.forTier(tier).scale
	local pivotY = C.SwingGeometry.pivotYForScale(scale)
	local rope = C.SwingGeometry.ropeLengthForScale(scale)
	local theta = math.rad(LaunchConfig.SWING_ARC_HALF_ANGLE_DEGREES)
	local startY = pivotY - rope * math.cos(theta) + LaunchConfig.RIDER_SEAT_HEIGHT_OFFSET
	local startPosition = C.shim.Vector3.new(0, startY, facts.seatZ)
	local launchPitch = LaunchFormulas.trajectoryPitch(startPosition, distance, archHeight, 0)
	return {
		distance = distance,
		archHeight = archHeight,
		durationSeconds = duration,
		launchAngleDegrees = math.deg(launchPitch),
		launchAngleClamped = math.abs(math.deg(launchPitch)) >= 24.999,
		startY = startY,
		landingZ = facts.landingZ,
	}
end

--===================== STEP 5: where the chest actually is =====================--
-- Mirrors MapBuilder.server.luau:431-432 and :587-590 exactly.
local lastBandFarEdgeZ = C.RunwayGeometry.RUNWAY_START_Z - (#C.LuckCurve.VALUES * LaunchConfig.RUNWAY_BAND_LENGTH_STUDS)
local slimeCenterZ = lastBandFarEdgeZ - GiantSlimeConfig.Z_OFFSET_PAST_LAST_BAND_STUDS
local groundPatchFootprint = GiantSlimeConfig.BODY_WIDTH_STUDS + 2 * GiantSlimeConfig.GROUND_PATCH_MARGIN_STUDS
local chestStripNearZ = slimeCenterZ + groundPatchFootprint / 2
local bodyNearZ = slimeCenterZ + GiantSlimeConfig.BODY_WIDTH_STUDS / 2
local chestZ = bodyNearZ + (chestStripNearZ - bodyNearZ) * TreasureConfig.CHEST_SETBACK_FRACTION

-- WalkSpeed is never set anywhere in this repo (see REPORT.md) -- this is the
-- Roblox engine default, used explicitly as an assumption, not as a measurement.
local ASSUMED_WALK_SPEED = 16

local returnZ = C.LaneConfig.SWING_PIVOT_Z + LaunchConfig.SWING_RETURN_CLEARANCE_STUDS
local remountWalkStuds = math.max(0, (returnZ - C.LaneConfig.SWING_PIVOT_Z) - LaunchConfig.SWING_MOUNT_RADIUS_STUDS)

--============================ The cycle, assembled ============================--
-- Bar wait model: the sweet spot passes once per SWING_PERIOD_SECONDS. A player
-- arriving at a uniformly random phase waits T/2 on average for the first pass,
-- then one full period per missed pass: E[wait] = T/2 + (1/p - 1) * T.
local PLAYER_MODELS = { { name = "perfect", p = 1.0 }, { name = "hit50", p = 0.5 }, { name = "hit20", p = 0.2 } }
local function barWaitSeconds(p: number): number
	return PERIOD / 2 + (1 / p - 1) * PERIOD
end

local expectedBoxPresses = 1 / (1 - LaunchConfig.BOX_DOUBLE_CHANCE)
local boxPressSeconds = (expectedBoxPresses - 1) * LaunchConfig.BOX_PRESS_COOLDOWN_SECONDS

local results = {}
for tier = 1, TIERS do
	local facts = C.perfectLaunchForTier(tier)
	local flight = flightForTier(tier)
	local bar = barWindowsForTier(tier, facts.seatZ)
	local isChest = facts.zone == "past"

	-- Post-landing reward phase, config floor only (zero human reaction).
	local reward, rewardPhases
	if isChest then
		local walkStuds = math.max(0, math.abs(flight.landingZ - chestZ) - TreasureConfig.CHEST_PROMPT_DISTANCE_STUDS)
		local walkSeconds = walkStuds / ASSUMED_WALK_SPEED
		rewardPhases = {
			walkToChestStuds = walkStuds,
			walkToChestSeconds = walkSeconds,
			promptHoldSeconds = TreasureConfig.CHEST_PROMPT_HOLD_SECONDS,
			revealEntranceSeconds = TreasureConfig.CHEST_REVEAL_ENTRANCE_SECONDS,
			revealDivineEntranceSeconds = TreasureConfig.CHEST_REVEAL_DIVINE_ENTRANCE_SECONDS,
			dismissLockoutSeconds = SlimeConfig.REVEAL_DISMISS_LOCKOUT_SECONDS,
			cameraReturnSeconds = 0, -- the chest path never takes the box camera
		}
		reward = walkSeconds + TreasureConfig.CHEST_PROMPT_HOLD_SECONDS + SlimeConfig.REVEAL_DISMISS_LOCKOUT_SECONDS
	else
		rewardPhases = {
			cameraEnterSeconds = LaunchConfig.BOX_CAMERA_TRANSITION_SECONDS,
			boxPressSeconds = boxPressSeconds,
			expectedPresses = expectedBoxPresses,
			boxToSlimeDelaySeconds = SlimeConfig.REVEAL_BOX_TO_SLIME_DELAY_SECONDS,
			revealEntranceSeconds = SlimeConfig.SLIME_REVEAL_ENTRANCE_SECONDS,
			dismissLockoutSeconds = SlimeConfig.REVEAL_DISMISS_LOCKOUT_SECONDS,
			cameraReturnSeconds = LaunchConfig.BOX_CAMERA_TRANSITION_SECONDS,
		}
		-- Presses may begin the instant the box exists (doBoxPress gates on
		-- boxActive and its own 0.25s clock only, never on the camera), so the
		-- 0.45s camera ease-in overlaps them rather than adding to them.
		reward = math.max(LaunchConfig.BOX_CAMERA_TRANSITION_SECONDS, boxPressSeconds)
			+ SlimeConfig.REVEAL_BOX_TO_SLIME_DELAY_SECONDS
			+ SlimeConfig.REVEAL_DISMISS_LOCKOUT_SECONDS
			+ LaunchConfig.BOX_CAMERA_TRANSITION_SECONDS
	end

	local remountSeconds = remountWalkStuds / ASSUMED_WALK_SPEED
	local perModel = {}
	for _, model in PLAYER_MODELS do
		local wait = barWaitSeconds(model.p)
		local total = wait + flight.durationSeconds + reward + remountSeconds
		perModel[model.name] = {
			barWaitSeconds = wait,
			flightSeconds = flight.durationSeconds,
			rewardSceneSeconds = reward,
			returnSeconds = remountSeconds,
			totalCycleSeconds = total,
			launchesPerMinute = 60 / total,
		}
	end

	results[tier] = {
		swingTier = tier,
		zone = facts.zone,
		rewardSource = if isChest then "chest" else "mysteryBox",
		bandLuck = facts.luck,
		bandIndex = facts.bandIndex,
		snapThreshold = bar.snapThreshold,
		snapWindowSeconds = bar.snapSeconds,
		sameOutcomeWindowSeconds = bar.sameOutcomeSeconds,
		consolationRingBand = bar.ringBand,
		consolationRingSeconds = bar.ringSeconds,
		chestWindowSeconds = bar.chestSeconds,
		flight = flight,
		rewardPhases = rewardPhases,
		remountWalkStuds = remountWalkStuds,
		remountSeconds = remountSeconds,
		byPlayerModel = perModel,
	}
end

--================================ Reporting ================================--
print(string.format("period %.2fs, sweet window %.4fs, mount radius %d, return Z %.1f, remount walk %.2f studs (%.3fs at %d studs/s)",
	PERIOD, LaunchConfig.SWEET_SPOT_WIDTH * PERIOD, LaunchConfig.SWING_MOUNT_RADIUS_STUDS, returnZ,
	remountWalkStuds, remountWalkStuds / ASSUMED_WALK_SPEED, ASSUMED_WALK_SPEED))
print(string.format("chest Z %.2f, tier-11 landing Z %.2f, walk to prompt %.2f studs",
	chestZ, results[11].flight.landingZ, results[11].rewardPhases.walkToChestStuds))
print(string.format("expected box presses %.4f -> %.4fs of enforced press cooldown\n", expectedBoxPresses, boxPressSeconds))

print("tier  snapThr  snapWin(s)  sameBand(s)  ring(band/s)      dist    arch    angle    flight(s)")
for tier = 1, TIERS do
	local r = results[tier]
	print(string.format("%4d  %.2f     %.4f      %.4f       %2d / %.4f    %7.1f  %6.1f  %6.2f  %.4f",
		tier, r.snapThreshold, r.snapWindowSeconds, r.sameOutcomeWindowSeconds, r.consolationRingBand,
		r.consolationRingSeconds, r.flight.distance, r.flight.archHeight, r.flight.launchAngleDegrees,
		r.flight.durationSeconds))
end

for _, model in PLAYER_MODELS do
	print(string.format("\n== player model: %s ==", model.name))
	print("tier  bar    flight  reward  return  total(s)  launches/min  dominant")
	for tier = 1, TIERS do
		local m = results[tier].byPlayerModel[model.name]
		local phases = { { "bar", m.barWaitSeconds }, { "flight", m.flightSeconds }, { "reward", m.rewardSceneSeconds }, { "return", m.returnSeconds } }
		table.sort(phases, function(a, b) return a[2] > b[2] end)
		results[tier].byPlayerModel[model.name].dominantPhase = phases[1][1]
		print(string.format("%4d  %5.2f  %6.2f  %6.2f  %6.2f  %8.2f  %12.2f  %s",
			tier, m.barWaitSeconds, m.flightSeconds, m.rewardSceneSeconds, m.returnSeconds,
			m.totalCycleSeconds, m.launchesPerMinute, phases[1][1]))
	end
end

--============================= STEP 7: the join =============================--
-- Design targets from ShopConfig.luau:39-43 -- the wait for tier N, in seconds.
local TARGET_SECONDS = { [2] = 6 * 60, [3] = 12 * 60, [4] = 24 * 60, [5] = 40 * 60, [6] = 70 * 60,
	[7] = 3 * 3600, [8] = 6 * 3600, [9] = 12 * 3600, [10] = 28 * 3600, [11] = 80 * 3600 }

for tier = 1, TIERS do
	local r = results[tier]
	local e = econ.tiers[tier]
	r.price = e.price
	r.equilibriumIncomePerSecond = e.equilibriumIncomePerSecond
	r.grossIncomePerSecondMaxed = e.grossIncomePerSecondMaxed
	r.rollsTo90Percent = e.rollsTo90Percent
	r.rollsToExhaustionSpecified = e.marginalBelowOnePercentAtRoll
	r.rollsToExhaustionRelative = e.marginalBelowOnePercentOfCurrentAtRoll
	r.remaxSpendPerRoll = e.remaxSpendPerRollAtEquilibrium
	r.joined = {}
	for _, model in PLAYER_MODELS do
		local cycle = r.byPlayerModel[model.name].totalCycleSeconds
		-- The drain is per ROLL; at this cadence it becomes a per-second cost.
		local drainPerSecond = r.remaxSpendPerRoll / cycle
		local realised = r.grossIncomePerSecondMaxed - drainPerSecond
		r.joined[model.name] = {
			cycleSeconds = cycle,
			launchesPerMinute = 60 / cycle,
			remaxDrainDollarsPerSecond = drainPerSecond,
			remaxDrainFraction = drainPerSecond / r.grossIncomePerSecondMaxed,
			realisedIncomePerSecond = realised,
			minutesTo90PercentEquilibrium = (r.rollsTo90Percent * cycle) / 60,
			minutesToExhaustionRelative = (r.rollsToExhaustionRelative * cycle) / 60,
			minutesToExhaustionSpecified = (r.rollsToExhaustionSpecified * cycle) / 60,
		}
	end
end

for _, model in PLAYER_MODELS do
	print(string.format("\n== joined (%s) ==", model.name))
	print("tier  price     realised/s   l/min   rolls->90%  min->90%   dRealised/s  implied$    ratio     payback(h)  aff:eq(m)  aff:L1(m)  aff:max(m)  target(m)  L1/target")
	for tier = 1, TIERS do
		local r = results[tier]
		local j = r.joined[model.name]
		local prev = if tier > 1 then results[tier - 1].joined[model.name] else nil
		local delta = if prev then j.realisedIncomePerSecond - prev.realisedIncomePerSecond else nil
		local implied = if delta then delta * C.SlimeUpgradeConfig.UPGRADE_PAYBACK_SECONDS else nil
		local ratio = if implied and implied ~= 0 then r.price / implied else nil
		local payback = if delta and delta ~= 0 then r.price / delta else nil
		j.deltaRealisedIncomePerSecond = delta
		j.impliedPriceAtExchangeRate = implied
		j.priceToImpliedRatio = ratio
		j.paybackSeconds = payback

		-- Time spent AT this tier banking the next tier's price.
		--
		-- AS SPECIFIED: price / realised income at equilibrium. This is
		-- circular and the report says so -- "equilibrium" is the state after
		-- ~10,000 rolls with every slot maxed, i.e. the richest the player will
		-- ever be at this tier, so it answers "how long would it take if you
		-- were already finished".
		local nextPrice = if tier < TIERS then results[tier + 1].price else nil
		local minutesToAfford = if nextPrice then nextPrice / j.realisedIncomePerSecond / 60 else nil
		j.minutesToAffordNextTier = minutesToAfford

		-- THE NON-CIRCULAR VERSION: integrate income along the actual held-set
		-- growth curve from an empty base, banking every second, until the next
		-- tier's price is reached. The curve is the median base income at 0 /
		-- 100 / 1,000 / 10,000 rolls from roll_economics.json, linearly
		-- interpolated between those points and held flat past the last one --
		-- an approximation of a curve measured at four points, and labelled as
		-- such. Two brackets, the same pair ECONOMY_DUMP used: A never levels
		-- (base income, no drain), B is fully maxed (28.63x, minus the drain).
		if nextPrice then
			local e2 = econ.tiers[tier]
			local pts = {
				{ 0, 0 },
				{ 100, e2.incomeByHorizon["100"].median },
				{ 1000, e2.incomeByHorizon["1000"].median },
				{ 10000, e2.incomeByHorizon["10000"].median },
			}
			local function baseIncomeAtRoll(n: number): number
				if n >= pts[#pts][1] then
					return pts[#pts][2]
				end
				for k = 1, #pts - 1 do
					local a, b = pts[k], pts[k + 1]
					if n <= b[1] then
						local t = (n - a[1]) / (b[1] - a[1])
						return a[2] + (b[2] - a[2]) * t
					end
				end
				return pts[#pts][2]
			end
			local function rollsToBank(scenario: string): number?
				local money = 0
				local cycle = j.cycleSeconds
				local perRollDrain = if scenario == "maxed" then r.remaxSpendPerRoll else 0
				local multiplier = if scenario == "maxed" then econ.constants.maxLevelIncomeMultiplier else 1
				for n = 1, 200000 do
					money += baseIncomeAtRoll(n) * multiplier * cycle - perRollDrain
					if money >= nextPrice then
						return n
					end
				end
				return nil
			end
			local rollsA = rollsToBank("level1")
			local rollsB = rollsToBank("maxed")
			j.rollsToAffordNextTierUnlevelled = rollsA
			j.rollsToAffordNextTierMaxed = rollsB
			j.minutesToAffordNextTierUnlevelled = if rollsA then rollsA * j.cycleSeconds / 60 else nil
			j.minutesToAffordNextTierMaxed = if rollsB then rollsB * j.cycleSeconds / 60 else nil
		end
		local target = TARGET_SECONDS[tier + 1]
		local vsTarget = if minutesToAfford and target then (minutesToAfford * 60) / target else nil
		j.nextTierTargetSeconds = target
		j.measuredOverTarget = vsTarget
		-- The same comparison against the non-circular brackets.
		j.measuredOverTargetUnlevelled = if j.minutesToAffordNextTierUnlevelled and target
			then (j.minutesToAffordNextTierUnlevelled * 60) / target else nil
		j.measuredOverTargetMaxed = if j.minutesToAffordNextTierMaxed and target
			then (j.minutesToAffordNextTierMaxed * 60) / target else nil

		-- Q3: the gap between "this tier has stopped improving" and "the next
		-- tier is affordable", in minutes. Positive = dead time (exhausted,
		-- still grinding); negative = skipped content (affordable while the
		-- tier is still improving).
		if j.minutesToAffordNextTierUnlevelled then
			j.deadTimeMinutesUnlevelled = j.minutesToAffordNextTierUnlevelled - j.minutesToExhaustionRelative
		end
		if j.minutesToAffordNextTierMaxed then
			j.deadTimeMinutesMaxed = j.minutesToAffordNextTierMaxed - j.minutesToExhaustionRelative
		end

		print(string.format("%4d  %-8s  %-11s  %6.2f  %10s  %9.1f  %-11s  %-10s  %-9s  %-10s  %-9s  %-9s  %-9s  %-8s  %s",
			tier, C.fmt(r.price), C.fmt(j.realisedIncomePerSecond), j.launchesPerMinute,
			tostring(r.rollsTo90Percent), j.minutesTo90PercentEquilibrium,
			delta and C.fmt(delta) or "n/a", implied and C.fmt(implied) or "n/a",
			ratio and string.format("%.4g", ratio) or "n/a",
			payback and string.format("%.4g", payback / 3600) or "n/a",
			minutesToAfford and string.format("%.3g", minutesToAfford) or "n/a",
			j.minutesToAffordNextTierUnlevelled and string.format("%.4g", j.minutesToAffordNextTierUnlevelled) or "n/a",
			j.minutesToAffordNextTierMaxed and string.format("%.4g", j.minutesToAffordNextTierMaxed) or "n/a",
			target and string.format("%.4g", target / 60) or "n/a",
			j.measuredOverTargetUnlevelled and string.format("%.3g", j.measuredOverTargetUnlevelled) or "n/a"))
	end
end

--============================ Ping sensitivity ============================--
-- onRelease grades at (now - clamp(GetNetworkPing(), 0, MAX)); anything the
-- clamp cannot cover stays as a one-directional bias against the player.
print("\nping  compensated  residual  residual vs snap half-window (T1-10 / T11)")
for _, ping in { 0, 0.060, 0.150 } do
	local comp = math.clamp(ping, 0, LaunchConfig.RELEASE_PING_COMPENSATION_MAX_SECONDS)
	local residual = ping - comp
	print(string.format("%.0fms  %.0fms         %.0fms      %.1f%% / %.1f%%",
		ping * 1000, comp * 1000, residual * 1000,
		residual / (results[1].snapWindowSeconds / 2) * 100,
		residual / (results[11].snapWindowSeconds / 2) * 100))
end

--================================== Output ==================================--
local out = {
	gitCommit = commit,
	sourceJson = { path = "dev/out/roll_economics.json", gitCommit = econ.gitCommit },
	constants = {
		swingPeriodSeconds = PERIOD,
		sweetSpotWidthPhase = LaunchConfig.SWEET_SPOT_WIDTH,
		sweetSpotWidthSeconds = LaunchConfig.SWEET_SPOT_WIDTH * PERIOD,
		sweetSpotPhase = LaunchConfig.SWEET_SPOT_PHASE,
		sweetSpotMultiplier = LaunchConfig.SWEET_SPOT_MULTIPLIER,
		sweetSpotEdgeMultiplier = LaunchConfig.SWEET_SPOT_EDGE_MULTIPLIER,
		snapThresholdDefault = LaunchConfig.SWEET_SPOT_SNAP_THRESHOLD,
		snapThresholdPerTier = LaunchConfig.SWING_TIER_SNAP_THRESHOLD,
		flightDurationSeconds = LaunchConfig.FLIGHT_DURATION_SECONDS,
		flightDurationExponent = LaunchConfig.FLIGHT_DURATION_EXPONENT,
		archHeightSqrtCoefficient = LaunchConfig.ARC_HEIGHT_SQRT_COEFFICIENT,
		distancePerMultiplier = LaunchConfig.DISTANCE_PER_MULTIPLIER,
		boxCameraTransitionSeconds = LaunchConfig.BOX_CAMERA_TRANSITION_SECONDS,
		boxPressCooldownSeconds = LaunchConfig.BOX_PRESS_COOLDOWN_SECONDS,
		boxDoubleChance = LaunchConfig.BOX_DOUBLE_CHANCE,
		revealBoxToSlimeDelaySeconds = SlimeConfig.REVEAL_BOX_TO_SLIME_DELAY_SECONDS,
		revealDismissLockoutSeconds = SlimeConfig.REVEAL_DISMISS_LOCKOUT_SECONDS,
		slimeRevealEntranceSeconds = SlimeConfig.SLIME_REVEAL_ENTRANCE_SECONDS,
		chestPromptHoldSeconds = TreasureConfig.CHEST_PROMPT_HOLD_SECONDS,
		chestPromptDistanceStuds = TreasureConfig.CHEST_PROMPT_DISTANCE_STUDS,
		chestRevealEntranceSeconds = TreasureConfig.CHEST_REVEAL_ENTRANCE_SECONDS,
		resetDelaySeconds = LaunchConfig.RESET_DELAY,
		swingMountRadiusStuds = LaunchConfig.SWING_MOUNT_RADIUS_STUDS,
		swingReturnClearanceStuds = LaunchConfig.SWING_RETURN_CLEARANCE_STUDS,
		returnZ = returnZ,
		chestZ = chestZ,
		assumedWalkSpeedStudsPerSecond = ASSUMED_WALK_SPEED,
		walkSpeedIsConfigured = false,
		beltSpeedStudsPerSecond = C.shim.loadLuauModule("src/ReplicatedStorage/Config/PathConfig.luau").BELT_SPEED_STUDS_PER_SECOND,
		beltWalkwayZ = C.shim.loadLuauModule("src/ReplicatedStorage/Config/PathConfig.luau").BACK_WALKWAY_Z,
		releasePingCompensationMaxSeconds = LaunchConfig.RELEASE_PING_COMPENSATION_MAX_SECONDS,
	},
	playerModels = { perfect = 1.0, hit50 = 0.5, hit20 = 0.2 },
	barWaitModel = "E[wait] = period/2 + (1/p - 1) * period; one sweet-spot pass per period",
	designTargetSeconds = (function()
		-- String keys: JSON objects cannot take integer keys.
		local out = {}
		for tier, seconds in TARGET_SECONDS do
			out[tostring(tier)] = seconds
		end
		return out
	end)(),
	tiers = results,
}
if not fs.isDir("dev/out") then
	fs.writeDir("dev/out")
end
fs.writeFile("dev/out/cycle_economics.json", serde.encode("json", out, true))
print("\nwrote dev/out/cycle_economics.json  (commit " .. commit .. ")")
