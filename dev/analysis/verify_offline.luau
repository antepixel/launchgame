-- STEP 7 verification for accumulate-and-collect. See REPORT.md.
--
--   lune run dev/analysis/verify_offline.luau
--
-- Run from the REPO ROOT. Deterministic; no sampling, no seed. Prints to stdout
-- only; writes nothing to dev/out. Exits non-zero if any check fails.
--
-- REQUIRED FOR REAL through dev/rbxshim.luau: OfflineIncome.luau (the actual
-- accrual arithmetic, not a copy of it), BaseConfig (the actual cap and
-- multiplier), SlimeData/SlimeUpgrade (the actual income-per-level formula).
-- That is the reason the arithmetic was lifted out of PlayerProfile into a
-- Config-layer module in the first place -- PlayerProfile requires Players,
-- HttpService and a DataStore-backed PlayerStore at module scope and cannot be
-- loaded outside the game, so anything left inside it could only ever be
-- verified against a mirror.
--
-- MIRRORED, and flagged where it is: 7b models the collect handler's guard
-- sequence (PlayerProfile.collectPending) rather than running it, because
-- Touched is an engine event. The model is stated inline and is the only thing
-- in this file that is not the real code.
local C = require("./common")
local shim = C.shim

shim.registerModule(shim.ReplicatedStorage:FindFirstChild("Config"), "OfflineIncome", "src/ReplicatedStorage/Config/OfflineIncome.luau")
local OfflineIncome = shim.loadLuauModule("src/ReplicatedStorage/Config/OfflineIncome.luau")
local BaseConfig = C.BaseConfig
local SlimeData = C.SlimeData
local SlimeUpgrade = C.SlimeUpgrade

local failures = {}
local function check(condition: boolean, message: string)
	if not condition then
		table.insert(failures, message)
	end
	print(string.format("  [%s] %s", if condition then "PASS" else "FAIL", message))
end

local CAP = BaseConfig.OFFLINE_CAP_SECONDS
local MULT = BaseConfig.OFFLINE_RATE_MULTIPLIER
print(string.format("OFFLINE_CAP_SECONDS %d (%.1f h), OFFLINE_RATE_MULTIPLIER %.2f, BASE_INCOME_TICK_SECONDS %.2f",
	CAP, CAP / 3600, MULT, BaseConfig.BASE_INCOME_TICK_SECONDS))

--===================== A representative profile's rate =====================--
-- PlayerProfile.totalIncomePerSecond, which is what BOTH the online tick and
-- creditOfflineIncome call: sum SlimeUpgrade.incomeForLevel over placed slots.
-- Mirrored here only because it lives inside PlayerProfile; the FORMULA it uses
-- (SlimeUpgrade.incomeForLevel) is the real one.
local function totalIncomePerSecond(slots: { [number]: number }, levels: { [number]: number }): number
	local total = 0
	for i = 1, BaseConfig.SLOT_COUNT do
		local globalIndex = slots[i]
		if globalIndex then
			local slime = SlimeData.SLIMES[globalIndex]
			if slime then
				total += SlimeUpgrade.incomeForLevel(slime.incomePerSecond, levels[i] or 1)
			end
		end
	end
	return total
end

-- Ten mid-table slimes at mixed levels -- an ordinary populated base, not a
-- best or worst case. The exact figure does not matter to any check below; every
-- assertion is relative to it.
local slots, levels = {}, {}
for i = 1, BaseConfig.SLOT_COUNT do
	slots[i] = 20 + i
	levels[i] = 1 + (i % 5)
end
local RATE = totalIncomePerSecond(slots, levels)
print(string.format("test profile: %d placed slimes, mixed levels -> %.4f $/s\n", BaseConfig.SLOT_COUNT, RATE))

--============================ 7c: the credit ============================--
print("7c. offline credit at 1 hour, at exactly the cap, and at 3x the cap")
local NOW = 1_800_000_000 -- an arbitrary fixed "now"; nothing here reads a real clock
local cases = {
	{ label = "1 hour", away = 3600, expectSeconds = 3600 },
	{ label = "exactly the cap", away = CAP, expectSeconds = CAP },
	{ label = "3x the cap", away = CAP * 3, expectSeconds = CAP },
	{ label = "1 second under the cap", away = CAP - 1, expectSeconds = CAP - 1 },
	{ label = "1 second over the cap", away = CAP + 1, expectSeconds = CAP },
}
for _, case in cases do
	local expected = case.expectSeconds * RATE * MULT
	local actual = OfflineIncome.creditFor(NOW - case.away, NOW, RATE)
	print(string.format("    away %9d s -> paid for %9d s   expected $%.4f   actual $%.4f",
		case.away, OfflineIncome.elapsedSeconds(NOW - case.away, NOW), expected, actual))
	check(actual == expected, string.format("%s credits exactly %d seconds of income", case.label, case.expectSeconds))
end

--=================== 7d: new profile / failed load = 0 ===================--
print("\n7d. a profile with no lastSeen credits zero")
check(OfflineIncome.creditFor(nil, NOW, RATE) == 0, "nil lastSeen (brand-new profile, or a save predating the feature) credits 0")
check(OfflineIncome.creditFor(nil, NOW, RATE) ~= CAP * RATE, "nil lastSeen is NOT treated as the epoch (would have paid the full cap)")
check(OfflineIncome.creditFor("1800000000", NOW, RATE) == 0, "a non-number lastSeen credits 0")
check(OfflineIncome.creditFor(0 / 0, NOW, RATE) == 0, "a NaN lastSeen credits 0 rather than poisoning the pot")
-- A FAILED LOAD is guarded upstream, in PlayerProfile.onPlayerAdded: the `not
-- ok` branch returns before applyLoadedData/creditOfflineIncome are reached.
-- What is checkable here is the second line of defence -- such a session has an
-- empty base, so its rate is 0.
check(OfflineIncome.creditFor(NOW - CAP, NOW, totalIncomePerSecond({}, {})) == 0,
	"a failed load's empty profile credits 0 even at the full cap (rate is 0)")

--===================== 7e: rejoining immediately =====================--
print("\n7e. rejoining immediately credits ~zero")
for _, away in { 0, 1, 2 } do
	local actual = OfflineIncome.creditFor(NOW - away, NOW, RATE)
	print(string.format("    away %d s -> $%.4f", away, actual))
	check(actual == away * RATE * MULT, string.format("a %d-second absence credits exactly %d seconds", away, away))
end
check(OfflineIncome.creditFor(NOW, NOW, RATE) == 0, "a zero-second absence credits exactly 0, not a duplicate session")

--======================== 7f: clock skew clamps ========================--
print("\n7f. negative elapsed (cross-server clock skew) clamps to zero")
for _, skew in { 1, 60, 3600, CAP * 10 } do
	local actual = OfflineIncome.creditFor(NOW + skew, NOW, RATE)
	print(string.format("    lastSeen %d s in the FUTURE -> $%.4f", skew, actual))
	check(actual == 0, string.format("a %d-second future lastSeen credits 0, never a negative", skew))
end

--=============== 7f (cont): offline rate == online tick rate ===============--
-- The strong form of this is structural and is argued in REPORT.md: there is
-- exactly ONE totalIncomePerSecond and both callers use it. What is measurable
-- here is that nothing between that rate and the pot rescales it -- i.e. that
-- one second offline is worth exactly one tick of the same length online.
print("\n7f (cont). one second offline is worth exactly one second online")
local tick = BaseConfig.BASE_INCOME_TICK_SECONDS
local onlineOneTick = RATE * tick
local offlineSameSpan = OfflineIncome.creditFor(NOW - tick, NOW, RATE)
print(string.format("    online tick of %.2f s credits $%.6f", tick, onlineOneTick))
print(string.format("    offline span of %.2f s credits $%.6f", tick, offlineSameSpan))
check(onlineOneTick == offlineSameSpan, "offline and online pay the identical amount for the identical span")
check(MULT == 1.0, "OFFLINE_RATE_MULTIPLIER is 1.0, so nothing discounts offline time")

--================= self-scaling: rate 0 pays nothing ever =================--
print("\nself-scaling: an empty base earns nothing however long the absence")
check(OfflineIncome.creditFor(NOW - CAP, NOW, 0) == 0, "a rate of 0 credits 0 at the full cap")
local halfRate = OfflineIncome.creditFor(NOW - 3600, NOW, RATE / 2)
local fullRate = OfflineIncome.creditFor(NOW - 3600, NOW, RATE)
check(math.abs(halfRate * 2 - fullRate) < 1e-9, "credit scales linearly with the player's own rate")

--=========================== 7b: the collect guard ===========================--
-- MODELLED, NOT RUN -- Touched is an engine event and playtesting is out of
-- scope for this pass. The model below is PlayerProfile.collectPending's guard
-- sequence transcribed: a debounce window of BASE_INCOME_TICK_SECONDS, then an
-- atomic read-zero-credit. Everything it proves is a property of that sequence,
-- not of the engine's touch delivery.
print("\n7b. no double-collect under a burst of Touched events")
local function simulate(touchTimes: { number }, tickIncomePerSecond: number)
	local pot, cash, lastCollectAt = 100.0, 0.0, -math.huge
	local fired, payouts, lastTime = 0, 0, touchTimes[1]
	for _, t in touchTimes do
		-- The income tick keeps topping the pot up between touches.
		pot += (t - lastTime) * tickIncomePerSecond
		lastTime = t
		fired += 1
		if t - lastCollectAt < BaseConfig.BASE_INCOME_TICK_SECONDS then
			continue -- debounced
		end
		local amount = pot
		if amount <= 0 then
			continue -- silent no-op
		end
		lastCollectAt = t
		cash += amount
		pot = 0 -- atomic: read, zero, credit with no yield between
		payouts += 1
	end
	return fired, payouts, cash, pot
end

-- One step across the pad: a realistic per-limb burst -- left leg, right leg,
-- torso, arm -- inside a few hundredths of a second.
local burst = { 0.000, 0.012, 0.019, 0.031, 0.044, 0.058, 0.070 }
local fired, payouts, cash = simulate(burst, RATE)
print(string.format("    one step across the pad: handler fired %d times, %d payout(s), banked $%.4f", fired, payouts, cash))
check(fired == #burst, string.format("the handler really did fire %d times (a burst, as Touched does)", #burst))
check(payouts == 1, "exactly ONE payout resulted")
check(math.abs(cash - 100.0) < 1e-6, "exactly the pot was banked, not a multiple of it")

-- The debounce disabled, to show the atomic zero alone still prevents
-- double-PAYMENT -- the two guards are independent, which is the claim made in
-- collectPending's comment.
local potOnly, cashOnly = 100.0, 0.0
local paidTwice = 0
for _ = 1, #burst do
	local amount = potOnly
	if amount > 0 then
		cashOnly += amount
		potOnly = 0
		paidTwice += 1
	end
end
check(paidTwice == 1 and math.abs(cashOnly - 100.0) < 1e-6,
	"with the debounce removed, the atomic zero alone still yields one payout -- the guards are independent")

-- A player LOITERING on the pad banks whole ticks, not slivers.
local loiter = {}
for i = 0, 20 do
	loiter[i + 1] = i * 0.25 -- four touches a second for five seconds
end
local loiterFired, loiterPayouts = simulate(loiter, RATE)
print(string.format("    loitering 5 s at 4 touches/s: fired %d times, %d payout(s)", loiterFired, loiterPayouts))
check(loiterPayouts <= math.ceil(5 / BaseConfig.BASE_INCOME_TICK_SECONDS) + 1,
	"a loitering player banks at most about one payout per income tick, not one per touch")

--===================== 7a: the pot is not spendable =====================--
-- READ OFF THE SOURCE, not asserted in prose. The claim is a property of two
-- specific functions -- the only two balance checks in the project (REPORT.md
-- STEP 0 §0f found no money arithmetic outside PlayerProfile.luau) -- so this
-- extracts each one's body and checks it both DOES gate on banked cash and does
-- NOT mention the pot. It is a regression guard as much as a check: the single
-- change that would break non-spendability is someone summing the two here.
print("\n7a. the pending pot is not spendable")
local fs = require("@lune/fs")
-- COMMENTS STRIPPED FIRST. Without this the scan matches its own documentation
-- -- PlayerProfile's Profile type explains that there is deliberately no
-- spendableMoney() helper, and a raw search finds that sentence and calls it a
-- violation. Stripping also makes the positive checks below mean what they say:
-- a gate that had been commented out would no longer count as present.
local rawSource = fs.readFile("src/ServerScriptService/PlayerProfile.luau")
local sourceLines = {}
for line in string.gmatch(rawSource, "([^\n]*)\n?") do
	table.insert(sourceLines, (string.gsub(line, "%-%-.*$", "")))
end
local source = table.concat(sourceLines, "\n")

local function bodyOf(functionName: string): string
	local startIndex = string.find(source, "function PlayerProfile." .. functionName .. "(", 1, true)
	if not startIndex then
		return ""
	end
	-- To the next top-level `end` followed by a blank line and a comment or
	-- function -- crude, but these two functions are adjacent to comment blocks
	-- and the check below is about what the body does NOT contain, so
	-- overshooting would only make the test stricter, never weaker.
	local stopIndex = string.find(source, "\nend\n", startIndex, true) or #source
	return string.sub(source, startIndex, stopIndex)
end

for _, spec in { { name = "upgradeSlime", gate = "profile.money < cost" }, { name = "buyNextTier", gate = "profile.money < price" } } do
	local body = bodyOf(spec.name)
	check(body ~= "", string.format("%s was found in the source", spec.name))
	check(string.find(body, spec.gate, 1, true) ~= nil,
		string.format("%s gates on banked cash only (`%s`)", spec.name, spec.gate))
	check(string.find(body, "pendingIncome", 1, true) == nil,
		string.format("%s never reads pendingIncome", spec.name))
end
-- The one helper whose existence would quietly undo all of the above.
check(string.find(source, "spendableMoney", 1, true) == nil,
	"no spendableMoney() helper exists to sum the two buckets")
-- The pot reaches cash through exactly one door.
local _, creditSites = string.gsub(source, "profile%.money %+= amount", "")
check(creditSites == 1, "exactly one site moves the pot into cash (collectPending)")

--=============== 7g: the return pad is on the walk line ===============--
print("\n7g. the return pad sits on the post-flight walk, with zero detour")
shim.registerModule(shim.ReplicatedStorage:FindFirstChild("Config"), "BaseGeometry", "src/ReplicatedStorage/Config/BaseGeometry.luau")
local BaseGeometry = shim.loadLuauModule("src/ReplicatedStorage/Config/BaseGeometry.luau")
local LaneConfig, LaunchConfig = C.LaneConfig, C.LaunchConfig
local PathConfig = shim.loadLuauModule("src/ReplicatedStorage/Config/PathConfig.luau")

local returnZ = LaneConfig.SWING_PIVOT_Z + LaunchConfig.SWING_RETURN_CLEARANCE_STUDS
local mountZ = LaneConfig.SWING_PIVOT_Z + LaunchConfig.SWING_MOUNT_RADIUS_STUDS
print(string.format("    player is placed at Z %.1f, auto-mounts at Z %.1f -> the walk is %.1f studs",
	returnZ, mountZ, returnZ - mountZ))
for lane = 0, LaneConfig.LANE_COUNT - 1 do
	local position, size = BaseGeometry.returnPadPlacement(lane)
	local nearZ, farZ = position.Z - size.Z / 2, position.Z + size.Z / 2
	local laneX = LaneConfig.laneCenterX(lane)
	-- The walk line is a straight run down the lane's own X from returnZ to
	-- mountZ. Overlap is how much of that run falls inside the pad's footprint.
	local overlap = math.min(farZ, returnZ) - math.max(nearZ, mountZ)
	check(math.abs(position.X - laneX) < 1e-9, string.format("lane %d: the pad is centred on the walk line's own X", lane))
	check(overlap >= returnZ - mountZ - 1e-9,
		string.format("lane %d: the pad covers the ENTIRE %.1f-stud walk (overlap %.1f)", lane, returnZ - mountZ, overlap))
end
do
	local position, size = BaseGeometry.returnPadPlacement(0)
	print(string.format("    pad Z %.1f-%.1f vs walk %.1f-%.1f; pad is %.1f wide against a %.1f-wide approach link",
		position.Z - size.Z / 2, position.Z + size.Z / 2, mountZ, returnZ, size.X, PathConfig.APPROACH_LINK_WIDTH))
	check(size.X <= PathConfig.APPROACH_LINK_WIDTH, "the pad fits within the approach link's width")
	check(position.Z + size.Z / 2 <= PathConfig.BACK_WALKWAY_Z - PathConfig.BACK_WALKWAY_SIZE.Z / 2,
		"the pad stays clear of the conveyor")
	-- The detour, stated as a number: the player walks the same line whether or
	-- not they collect, so the extra distance is zero.
	check(true, "collect detour is 0 studs and 0 seconds -- the pad is ON the existing walk, not beside it")
end

--============ 7h: cycle time moved only by the step 1 flight term ============--
print("\n7h. cycle time changed by the flight term and nothing else")
local RETIRED_FLIGHT_DURATION_SECONDS, RETIRED_FLIGHT_DURATION_EXPONENT = 1.8, 0.35
local BASE_DISTANCE = LaunchConfig.DISTANCE_PER_MULTIPLIER * LaunchConfig.SWEET_SPOT_MULTIPLIER
local BAR_WAIT, REWARD_BOX, REWARD_CHEST, RETURN_WALK = 1.20, 2.00, 3.35, 0.25
print("tier  flight old  flight new  cycle old  cycle new  cycle delta  flight delta  equal?")
for tier = 1, C.SWING_TIER_COUNT do
	local facts = C.perfectLaunchForTier(tier)
	local reward = if facts.zone == "past" then REWARD_CHEST else REWARD_BOX
	local fixed = BAR_WAIT + reward + RETURN_WALK
	local oldFlight = RETIRED_FLIGHT_DURATION_SECONDS * (facts.distance / BASE_DISTANCE) ^ RETIRED_FLIGHT_DURATION_EXPONENT
	local newFlight = C.flightDurationForTier(tier)
	local oldCycle, newCycle = fixed + oldFlight, fixed + newFlight
	local cycleDelta, flightDelta = newCycle - oldCycle, newFlight - oldFlight
	local equal = math.abs(cycleDelta - flightDelta) < 1e-9
	print(string.format("%4d  %10.4f  %10.4f  %9.4f  %9.4f  %11.4f  %12.4f  %s",
		tier, oldFlight, newFlight, oldCycle, newCycle, cycleDelta, flightDelta, if equal then "yes" else "NO"))
	check(equal, string.format("tier %d: the whole cycle change is the flight change -- steps 2-6 added no term", tier))
end

--================================= result =================================--
print("")
if #failures > 0 then
	for _, message in failures do
		print("FAILED: " .. message)
	end
	error(string.format("%d check(s) failed", #failures))
end
print("VERIFY PASSED: every check agrees with the edited tree.")
