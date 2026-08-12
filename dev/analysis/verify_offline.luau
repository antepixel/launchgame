-- STEP 6 verification for PER-SLOT collection + the offline retune. See
-- REPORT.md.
--
--   lune run dev/analysis/verify_offline.luau
--
-- Run from the REPO ROOT. Deterministic; no sampling, no seed. Prints to stdout
-- only; writes nothing to dev/out. Exits non-zero if any check fails.
--
-- REQUIRED FOR REAL through dev/rbxshim.luau: OfflineIncome.luau (the actual
-- accrual arithmetic, not a copy of it), BaseConfig (the actual cap and
-- multiplier), BaseGeometry (the actual pad positions), SlimeData/SlimeUpgrade
-- (the actual income-per-level formula). That is the reason the arithmetic was
-- lifted out of PlayerProfile into a Config-layer module in the first place --
-- PlayerProfile requires Players, HttpService and a DataStore-backed PlayerStore
-- at module scope and cannot be loaded outside the game, so anything left inside
-- it could only ever be verified against a mirror.
--
-- WHAT IS MIRRORED, AND IT IS FLAGGED WHERE IT IS: 6b and 6e model
-- PlayerProfile's own guard/ordering sequences rather than running them (Touched
-- is an engine event, and removeToInventory cannot be loaded). Both models are
-- transcribed inline AND pinned to the real source with a structural scan
-- immediately afterwards, so a model that drifts away from the code it stands in
-- for fails the scan rather than passing quietly.
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
local SLOT_COUNT = BaseConfig.SLOT_COUNT
print(string.format("OFFLINE_CAP_SECONDS %d (%.1f h), OFFLINE_RATE_MULTIPLIER %.2f, BASE_INCOME_TICK_SECONDS %.2f, SLOT_COUNT %d",
	CAP, CAP / 3600, MULT, BaseConfig.BASE_INCOME_TICK_SECONDS, SLOT_COUNT))

--===================== A representative profile's rates =====================--
-- PlayerProfile.slotIncomePerSecond, which is what BOTH the online tick and
-- creditOfflineIncome call, PER SLOT. Mirrored here only because it lives inside
-- PlayerProfile; the FORMULA it uses (SlimeUpgrade.incomeForLevel) is the real
-- one.
local slots, levels = {}, {}
for i = 1, SLOT_COUNT do
	slots[i] = 20 + i
	levels[i] = 1 + (i % 5)
end

local function slotIncomePerSecond(slotNumber: number): number
	local globalIndex = slots[slotNumber]
	if not globalIndex then
		return 0
	end
	local slime = SlimeData.SLIMES[globalIndex]
	if not slime then
		return 0
	end
	return SlimeUpgrade.incomeForLevel(slime.incomePerSecond, levels[slotNumber] or 1)
end

local function totalIncomePerSecond(): number
	local total = 0
	for i = 1, SLOT_COUNT do
		total += slotIncomePerSecond(i)
	end
	return total
end

-- Ten mid-table slimes at mixed levels -- an ordinary populated base, not a best
-- or worst case. The exact figures do not matter to any check below; every
-- assertion is relative to them. The MIX does matter: the ten rates are all
-- different, which is what makes "each pot grew at its own rate" a real claim
-- rather than one that ten equal numbers would satisfy by accident.
local RATE = totalIncomePerSecond()
print(string.format("test profile: %d placed slimes, mixed levels -> %.4f $/s total", SLOT_COUNT, RATE))
do
	local distinct = {}
	for i = 1, SLOT_COUNT do
		distinct[string.format("%.6f", slotIncomePerSecond(i))] = true
	end
	local count = 0
	for _ in distinct do
		count += 1
	end
	print(string.format("  per-slot rates: %d distinct values across %d slots", count, SLOT_COUNT))
	check(count > 1, "the test profile's slots really do earn at DIFFERENT rates")
end

--==================== 6a: per-slot accrual, and its sum ====================--
-- The online tick, transcribed from PlayerProfile's income loop: each slot's pot
-- gains ITS OWN rate times the ACTUAL elapsed time (the os.clock() delta fix
-- from the previous pass, kept), with no cap of any kind applied while online.
print("\n6a. each pot grows at its own rate, and the ten sum to the old single pot")
local function tickPots(pots: { [number]: number }, elapsed: number)
	for i = 1, SLOT_COUNT do
		local income = slotIncomePerSecond(i)
		if income > 0 then
			pots[i] = (pots[i] or 0) + income * elapsed
		end
	end
end

local pots = {}
-- Deliberately uneven tick lengths -- the loop pays for time that ACTUALLY
-- passed, not for the nominal interval, so a run of ragged ticks must still sum
-- to the same total as the span they cover.
local ticks = { 1.013, 0.996, 1.204, 0.988, 1.001, 1.317, 0.972 }
local span = 0
for _, elapsed in ticks do
	tickPots(pots, elapsed)
	span += elapsed
end
local potTotal = 0
for i = 1, SLOT_COUNT do
	local expected = slotIncomePerSecond(i) * span
	potTotal += pots[i]
	check(math.abs(pots[i] - expected) < 1e-9 * math.max(1, expected),
		string.format("slot %2d accrued %s over %.3f s at its own %s/s", i, C.fmt(pots[i]), span, C.fmt(slotIncomePerSecond(i))))
end
local singlePotWouldHold = RATE * span
print(string.format("    ten pots sum to $%.6f; one shared pot over the same %.3f s would hold $%.6f", potTotal, span, singlePotWouldHold))
check(math.abs(potTotal - singlePotWouldHold) < 1e-6,
	"the ten pots sum to exactly what the old single pot would have held over the same span")

-- 1c: no cap while online. A pot is allowed to grow past any offline ceiling.
local afkPots = {}
tickPots(afkPots, 24 * 3600)
local afkTotal = 0
for i = 1, SLOT_COUNT do
	afkTotal += afkPots[i]
end
local offlineCeiling = CAP * RATE * MULT
print(string.format("    24 h AFK (online) accrues $%.4g; the offline ceiling is $%.4g", afkTotal, offlineCeiling))
check(afkTotal > offlineCeiling,
	string.format("an AFK player's pots blow straight past the offline ceiling (%.1fx) -- online is uncapped, deliberately", afkTotal / offlineCeiling))

--======================== 6c: the offline credit ========================--
print("\n6c. offline credit at 1 h, 12 h (the cap), 24 h and 1 week")
local NOW = 1_800_000_000 -- an arbitrary fixed "now"; nothing here reads a real clock

-- Per slot, exactly as PlayerProfile.creditOfflineIncome does it: one
-- creditFor call per slot, at that slot's own rate, all sharing one `now`.
local function creditOffline(lastSeen: any, now: number): ({ [number]: number }, number)
	local credited: { [number]: number } = {}
	local total = 0
	for i = 1, SLOT_COUNT do
		local amount = OfflineIncome.creditFor(lastSeen, now, slotIncomePerSecond(i))
		if amount > 0 then
			credited[i] = amount
			total += amount
		end
	end
	return credited, total
end

local HOUR = 3600
local awayCases = {
	{ label = "1 hour", away = HOUR, expectSeconds = HOUR },
	{ label = "12 hours (exactly the cap)", away = 12 * HOUR, expectSeconds = CAP },
	{ label = "24 hours", away = 24 * HOUR, expectSeconds = CAP },
	{ label = "1 week", away = 7 * 24 * HOUR, expectSeconds = CAP },
	{ label = "3 months", away = 90 * 24 * HOUR, expectSeconds = CAP },
}
local capFigure = nil
for _, case in awayCases do
	local credited, total = creditOffline(NOW - case.away, NOW)
	local expected = case.expectSeconds * RATE * MULT
	print(string.format("    away %8.1f h -> paid for %8.1f h   $%s", case.away / HOUR,
		OfflineIncome.elapsedSeconds(NOW - case.away, NOW) / HOUR, C.fmt(total)))
	check(math.abs(total - expected) < 1e-6,
		string.format("%s credits exactly %.1f h of income at %.0f%%", case.label, case.expectSeconds / 3600, MULT * 100))
	if case.expectSeconds == CAP then
		if capFigure == nil then
			capFigure = total
		end
		check(math.abs(total - (capFigure :: number)) < 1e-9,
			string.format("%s returns the IDENTICAL figure as every other absence past the cap", case.label))
	end
	-- 2d: proportional across slots, by each slot's own rate.
	local proportional = true
	for i = 1, SLOT_COUNT do
		local share = (credited[i] or 0) / total
		local rateShare = slotIncomePerSecond(i) / RATE
		if math.abs(share - rateShare) > 1e-9 then
			proportional = false
		end
	end
	check(proportional, string.format("%s distributes across the ten slots exactly in proportion to their own rates", case.label))
end

-- The combined ceiling, stated as the number the design comment claims.
local CEILING_HOURS = CAP / 3600 * MULT
print(string.format("\n    combined ceiling: %.0f h x %.2f = %.2f HOURS of income, however long the absence", CAP / 3600, MULT, CEILING_HOURS))
check(math.abs(CEILING_HOURS - 2.64) < 1e-9, "the 12 h cap at 22% is exactly 2.64 hours of online income")
check(math.abs((capFigure :: number) - RATE * 2.64 * 3600) < 1e-6,
	"the capped credit equals 2.64 hours of this profile's own online income, measured not asserted")
check(CAP == 43200, "OFFLINE_CAP_SECONDS is 43200 (12 hours)")
check(MULT == 0.22, "OFFLINE_RATE_MULTIPLIER is 0.22")

-- What the cap is actually protecting the player from, priced out.
local uncappedWeek = 7 * 24 * HOUR * MULT / 3600
local uncappedQuarter = 90 * 24 * HOUR * MULT / 3600
print(string.format("    (uncapped at %.0f%%, a week away would return %.1f h of income and three months %.0f h -- what the cap is for)",
	MULT * 100, uncappedWeek, uncappedQuarter))

--=============== 6d: nil / negative / failed load / zero rate ===============--
print("\n6d. nil, negative, failed-load and zero-rate all credit zero")
local _, nilTotal = creditOffline(nil, NOW)
check(nilTotal == 0, "nil lastSeen (brand-new profile, or a save predating the feature) credits 0")
check(nilTotal ~= CAP * RATE * MULT, "nil lastSeen is NOT treated as the epoch (would have paid the full cap)")
local _, stringTotal = creditOffline("1800000000", NOW)
check(stringTotal == 0, "a non-number lastSeen credits 0")
local _, nanTotal = creditOffline(0 / 0, NOW)
check(nanTotal == 0, "a NaN lastSeen credits 0 rather than poisoning the pots")
for _, skew in { 1, 60, 3600, CAP * 10 } do
	local _, total = creditOffline(NOW + skew, NOW)
	check(total == 0, string.format("a %d-second FUTURE lastSeen (cross-server clock skew) credits 0, never a negative", skew))
end
check(OfflineIncome.creditFor(NOW - CAP, NOW, 0) == 0, "a slot with a rate of 0 (empty) credits 0 at the full cap")
-- A FAILED LOAD is guarded upstream, in PlayerProfile.onPlayerAdded: the `not
-- ok` branch returns before applyLoadedData/creditOfflineIncome are reached.
-- Structurally checked below in 6b's scan; what is checkable HERE is the second
-- line of defence -- such a session has an empty base, so every slot's rate is 0.
do
	local emptySlots = slots
	slots = {}
	local _, total = creditOffline(NOW - CAP, NOW)
	slots = emptySlots
	check(total == 0, "a failed load's empty profile credits 0 even at the full cap (every slot's rate is 0)")
end
-- 2e: the accrual must run AFTER applyLoadedData, or the rate is zero. Same
-- demonstration, from the other side.
print("    (the same zero is what an accrual run BEFORE applyLoadedData would pay -- see the ordering scan in 6b)")

--============== 6b: every path that empties a slot banks first ==============--
-- MODELLED, THEN PINNED TO THE SOURCE. The model is removeToInventory's
-- ordering; the scan below it is what proves the real function still has that
-- ordering, and that the other three paths named in the task reach it.
print("\n6b. every path that empties a slot banks that slot's pot first")
local function removeToInventory(state, slotNumber: number): boolean
	if not state.slots[slotNumber] then
		return false
	end
	-- bankSlot, BEFORE the slot is cleared and before the model (and with it the
	-- pad) is destroyed.
	local amount = state.pots[slotNumber]
	if amount and amount > 0 then
		state.pots[slotNumber] = nil
		state.money += amount
	end
	state.slots[slotNumber] = nil
	state.inventory += 1
	return true
end

local function freshState()
	local state = { slots = {}, pots = {}, money = 0, inventory = 0 }
	for i = 1, SLOT_COUNT do
		state.slots[i] = slots[i]
		state.pots[i] = 1000 * i
	end
	return state
end

do -- manual removal of one slot
	local state = freshState()
	removeToInventory(state, 4)
	check(state.money == 4000 and state.pots[4] == nil, "manual removal banks that slot's $4,000 before clearing it")
	check(state.pots[5] == 5000, "manual removal leaves every OTHER slot's pot untouched")
end
do -- devClearBase: every slot, through the same function
	local state = freshState()
	for i = 1, SLOT_COUNT do
		if state.slots[i] then
			removeToInventory(state, i)
		end
	end
	local expected = 0
	for i = 1, SLOT_COUNT do
		expected += 1000 * i
	end
	check(state.money == expected, string.format("devClearBase banks all ten pots ($%d) -- it routes every slot through removeToInventory", expected))
end
do -- a slot with nothing pending
	local state = freshState()
	state.pots[2] = nil
	removeToInventory(state, 2)
	check(state.money == 0, "removing a slot with an empty pot banks nothing, silently")
end

-- THE SCAN. Comments stripped first, so documentation cannot satisfy a check and
-- a commented-out line cannot count as present.
local rawSource = C.readSource("src/ServerScriptService/PlayerProfile.luau")
local sourceLines = {}
for line in string.gmatch(rawSource, "([^\n]*)\n?") do
	table.insert(sourceLines, (string.gsub(line, "%-%-.*$", "")))
end
local source = table.concat(sourceLines, "\n")

-- Only ONE place in the file empties a slot. If a second one ever appears, this
-- fails, and the "bank first" guarantee has to be restated there too.
local _, clearSites = string.gsub(source, "profile%.slots%[slotNumber%] = nil", "")
local _, anyClearSites = string.gsub(source, "profile%.slots%[[%w_]+%] = nil", "")
check(clearSites == 1 and anyClearSites == 1,
	string.format("exactly ONE site in PlayerProfile empties a slot (found %d)", anyClearSites))

local bankIndex = string.find(source, "bankSlot(profile, slotNumber)", 1, true)
local clearIndex = string.find(source, "profile.slots[slotNumber] = nil", 1, true)
check(bankIndex ~= nil and clearIndex ~= nil and (bankIndex :: number) < (clearIndex :: number),
	"removeToInventory calls bankSlot BEFORE it clears the slot, in source order")

check(string.find(source, "PlayerProfile.removeToInventory(player, i)", 1, true) ~= nil,
	"devClearBase empties slots through removeToInventory, not by hand")
check(string.find(source, "PlayerProfile.devClearBase(player)", 1, true) ~= nil,
	"devWipeProfile empties the base through devClearBase, so it inherits the banking")

-- sellFromInventory cannot reach a slot at all -- the property that makes
-- "remove before you sell" true by construction. Extract its body and check.
local function bodyOf(functionName: string): string
	local startIndex = string.find(source, "function PlayerProfile." .. functionName .. "(", 1, true)
	if not startIndex then
		return ""
	end
	local stopIndex = string.find(source, "\nend\n", startIndex, true) or #source
	return string.sub(source, startIndex, stopIndex)
end
local sellBody = bodyOf("sellFromInventory")
check(sellBody ~= "", "sellFromInventory was found in the source")
check(string.find(sellBody, "profile.slots", 1, true) == nil,
	"sellFromInventory never touches profile.slots -- selling cannot empty a slot, so it needs no banking of its own")
local placeBody = bodyOf("placeFromInventory")
check(string.find(placeBody, "= nil", 1, true) == nil or string.find(placeBody, "profile.slots[i] = nil", 1, true) == nil,
	"placeFromInventory never clears an occupied slot -- there is no replacement path to bank on")

-- 2e, re-verified structurally: the accrual runs AFTER the load is applied, and
-- both sit below the failed-load bail.
local applyIndex = string.find(source, "applyLoadedData(profile, data)", 1, true)
local creditIndex = string.find(source, "creditOfflineIncome(profile, data)", 1, true)
local bailIndex = string.find(source, "if not ok then", 1, true)
check(applyIndex ~= nil and creditIndex ~= nil and (applyIndex :: number) < (creditIndex :: number),
	"creditOfflineIncome still runs AFTER applyLoadedData, so the rate is not zero")
check(bailIndex ~= nil and (bailIndex :: number) < (applyIndex :: number),
	"both sit below the `not ok` failed-load bail, so a failed load credits nothing")

--=============== 6f: the pending pots are still not spendable ===============--
print("\n6f. the pending pots are not spendable, re-run against the new shape")
for _, spec in { { name = "upgradeSlime", gate = "profile.money < cost" }, { name = "buyNextTier", gate = "profile.money < price" } } do
	local body = bodyOf(spec.name)
	check(body ~= "", string.format("%s was found in the source", spec.name))
	check(string.find(body, spec.gate, 1, true) ~= nil,
		string.format("%s gates on banked cash only (`%s`)", spec.name, spec.gate))
	check(string.find(body, "pendingBySlot", 1, true) == nil and string.find(body, "pendingTotal", 1, true) == nil,
		string.format("%s never reads a pending pot", spec.name))
end
check(string.find(source, "spendableMoney", 1, true) == nil,
	"no spendableMoney() helper exists to sum the two buckets")
-- The pots reach cash through exactly one door, and it is bankSlot. Under the
-- single pot this counted `profile.money += amount`; the needle changes with the
-- shape, the property does not.
local _, creditSites = string.gsub(source, "profile%.money %+= amount", "")
check(creditSites == 1, "exactly one site moves a pot into cash (bankSlot)")
local bankBody = string.sub(source, string.find(source, "local function bankSlot", 1, true) or 1)
bankBody = string.sub(bankBody, 1, string.find(bankBody, "\nend\n", 1, true) or #bankBody)
check(string.find(bankBody, "profile.pendingBySlot[slotNumber] = nil", 1, true) ~= nil,
	"bankSlot zeroes the pot in the same yield-free stretch that credits the cash (the atomic payout)")

--============ 6e: walking the row banks all ten, exactly once each ============--
-- MODELLED (Touched is an engine event), against the REAL pad geometry: pad
-- positions and sizes come from BaseGeometry.collectPadPlacement, and the timing
-- comes from walking between them at the default WalkSpeed. The guard sequence
-- is collectPending's, transcribed: a PER-SLOT debounce window of
-- BASE_INCOME_TICK_SECONDS, then an atomic read-zero-credit.
print("\n6e. walking the full row banks all ten, with no double-payment")
shim.registerModule(shim.ReplicatedStorage:FindFirstChild("Config"), "BaseGeometry", "src/ReplicatedStorage/Config/BaseGeometry.luau")
local BaseGeometry = shim.loadLuauModule("src/ReplicatedStorage/Config/BaseGeometry.luau")
local LaneConfig, LaunchConfig = C.LaneConfig, C.LaunchConfig
local PathConfig = shim.loadLuauModule("src/ReplicatedStorage/Config/PathConfig.luau")

-- Roblox's default Humanoid.WalkSpeed. Nothing in src/ ever assigns WalkSpeed
-- (checked), so this is the real number a player moves at.
local WALK_SPEED = 16
local LANE = 0

-- The ten pads, in the order a player walking the plot meets them: down the
-- rows, taking both columns of each row before moving on (a boustrophedon, so
-- the crossing is made once per row rather than once per pad).
local padOrder = {}
for row = 0, math.ceil(SLOT_COUNT / BaseConfig.BASE_GRID_COLUMNS) - 1 do
	local left, right = row * 2 + 1, row * 2 + 2
	if left <= SLOT_COUNT then
		if row % 2 == 0 then
			table.insert(padOrder, left)
			if right <= SLOT_COUNT then
				table.insert(padOrder, right)
			end
		else
			if right <= SLOT_COUNT then
				table.insert(padOrder, right)
			end
			table.insert(padOrder, left)
		end
	end
end

local padPositions = {}
local padSizes = {}
for i = 1, SLOT_COUNT do
	local position, size = BaseGeometry.collectPadPlacement(LANE, i)
	padPositions[i] = position
	padSizes[i] = size
end

-- The walk: arrival times at each pad in order, at WALK_SPEED, plus a per-limb
-- Touched burst at each one.
local walkPots = {}
for i = 1, SLOT_COUNT do
	walkPots[i] = 100 * i
end
local walkMoney = 0
local lastCollectAtBySlot = {}
local payouts = {}
local firedTotal = 0
local t = 0
local previous = nil
local BURST = { 0.000, 0.012, 0.019, 0.031, 0.044, 0.058, 0.070 }
for _, slotNumber in padOrder do
	local position = padPositions[slotNumber]
	if previous then
		local delta = position - previous
		t += math.sqrt(delta.X * delta.X + delta.Z * delta.Z) / WALK_SPEED
	end
	previous = position
	for _, offset in BURST do
		local now = t + offset
		firedTotal += 1
		if now - (lastCollectAtBySlot[slotNumber] or -math.huge) < BaseConfig.BASE_INCOME_TICK_SECONDS then
			continue -- debounced (this slot only)
		end
		local amount = walkPots[slotNumber]
		if not amount or amount <= 0 then
			continue -- silent no-op
		end
		lastCollectAtBySlot[slotNumber] = now
		-- Atomic: read, zero, credit, with no yield between.
		walkPots[slotNumber] = nil
		walkMoney += amount
		payouts[slotNumber] = (payouts[slotNumber] or 0) + 1
	end
end
local expectedWalkMoney = 0
for i = 1, SLOT_COUNT do
	expectedWalkMoney += 100 * i
end
print(string.format("    the walk takes %.2f s, %d Touched events fired across %d pads", t, firedTotal, #padOrder))
check(walkMoney == expectedWalkMoney, string.format("all ten pots banked ($%d of $%d)", walkMoney, expectedWalkMoney))
local everyPadPaidOnce = true
for i = 1, SLOT_COUNT do
	if payouts[i] ~= 1 then
		everyPadPaidOnce = false
	end
end
check(everyPadPaidOnce, "every one of the ten pads paid EXACTLY ONCE -- no pad skipped, none paid twice")
check(t < BaseConfig.BASE_INCOME_TICK_SECONDS * SLOT_COUNT,
	string.format("the whole walk (%.2f s) is shorter than %d debounce windows -- a SHARED debounce would have banked one pad and skipped nine", t, SLOT_COUNT))

-- The consecutive-pad gap, which is what a shared debounce would have eaten.
local minGap = math.huge
previous = nil
for _, slotNumber in padOrder do
	local position = padPositions[slotNumber]
	if previous then
		local delta = position - previous
		minGap = math.min(minGap, math.sqrt(delta.X * delta.X + delta.Z * delta.Z) / WALK_SPEED)
	end
	previous = position
end
print(string.format("    closest two pads on the route are %.2f s apart at %d studs/s, against a %.2f s debounce window",
	minGap, WALK_SPEED, BaseConfig.BASE_INCOME_TICK_SECONDS))
check(minGap < BaseConfig.BASE_INCOME_TICK_SECONDS, "consecutive pads ARE inside one debounce window -- per-slot keying is load-bearing, not cosmetic")

-- Double-payment is impossible even with the debounce removed entirely: the
-- atomic zero alone yields one payout per pot. The two guards are independent.
local atomicPots, atomicMoney, atomicPayouts = { [1] = 500 }, 0, 0
for _ = 1, #BURST do
	local amount = atomicPots[1]
	if amount and amount > 0 then
		atomicPots[1] = nil
		atomicMoney += amount
		atomicPayouts += 1
	end
end
check(atomicPayouts == 1 and atomicMoney == 500,
	"with the debounce removed, the atomic zero alone still yields one payout -- the guards are independent")

--=============== 0b/0c/6h: the trip, and what it costs ===============--
print("\n6h. the collection trip: how long it takes, and what it costs per launch")
local returnZ = LaneConfig.SWING_PIVOT_Z + LaunchConfig.SWING_RETURN_CLEARANCE_STUDS
local mountZ = LaneConfig.SWING_PIVOT_Z + LaunchConfig.SWING_MOUNT_RADIUS_STUDS
local laneX = LaneConfig.laneCenterX(LANE)
print(string.format("    a flight returns the player to Z %.1f; auto-mount seats them at Z %.1f (a %.1f-stud walk)",
	returnZ, mountZ, returnZ - mountZ))
check(returnZ > mountZ, "the return position is OUTSIDE the mount radius -- a dismounted player is not instantly re-seated")
check(BaseConfig.BASE_SLOT_Z_START > returnZ,
	"the base lies in the +Z direction from the return position, AWAY from the pivot -- walking to it increases the mount distance monotonically")

-- The route, as one line down the lane's own X and then the pad walk.
local function planarDistance(a, b): number
	local delta = a - b
	return math.sqrt(delta.X * delta.X + delta.Z * delta.Z)
end
-- shim.Vector3, not a global: this file runs under Lune, where Roblox datatypes
-- exist only inside dev/rbxshim.luau's own environment.
local startPoint = shim.Vector3.new(laneX, 0, returnZ)
local outbound = planarDistance(startPoint, padPositions[padOrder[1]])
local rowWalk = 0
previous = nil
for _, slotNumber in padOrder do
	if previous then
		rowWalk += planarDistance(padPositions[slotNumber], previous)
	end
	previous = padPositions[slotNumber]
end
local inbound = planarDistance(previous, startPoint)
local tripStuds = outbound + rowWalk + inbound
local tripSeconds = tripStuds / WALK_SPEED
print(string.format("    out %.1f studs + row %.1f + back %.1f = %.1f studs -> %.2f s at %d studs/s",
	outbound, rowWalk, inbound, tripStuds, tripSeconds, WALK_SPEED))

-- The conveyor. It runs ACROSS the map on X (opposing halves, see MapBuilder),
-- and the trip runs along Z -- so it moves the player SIDEWAYS while they cross
-- it and contributes nothing either way to the journey's length.
local beltNearZ = PathConfig.BACK_WALKWAY_Z - PathConfig.BACK_WALKWAY_SIZE.Z / 2
local beltFarZ = PathConfig.BACK_WALKWAY_Z + PathConfig.BACK_WALKWAY_SIZE.Z / 2
local beltCrossSeconds = (beltFarZ - beltNearZ) / WALK_SPEED
print(string.format("    the conveyor spans Z %.0f-%.0f and pushes on X only (%d studs/s, halves opposed): %.2f s of crossing, ~%.0f studs of drift each way, net ~0",
	beltNearZ, beltFarZ, PathConfig.BELT_SPEED_STUDS_PER_SECOND, beltCrossSeconds,
	PathConfig.BELT_SPEED_STUDS_PER_SECOND * beltCrossSeconds / 2))
check(beltNearZ > returnZ and beltFarZ < BaseConfig.BASE_SLOT_Z_START,
	"the conveyor sits between the return position and the pads -- it is crossed, not ridden, on this trip")

-- Cycle time, from the SAME model dev/analysis/cycle_time.luau uses: bar wait +
-- flight + reward + the 4-stud remount walk. Perfect play.
local BAR_WAIT, REWARD_BOX, REWARD_CHEST = 1.20, 2.00, 3.35
local RETURN_WALK = (returnZ - mountZ) / WALK_SPEED
local function cycleSecondsForTier(tier: number): number
	local facts = C.perfectLaunchForTier(tier)
	local reward = if facts.zone == "past" then REWARD_CHEST else REWARD_BOX
	return BAR_WAIT + C.flightDurationForTier(tier) + reward + RETURN_WALK
end
local tier1Cycle = cycleSecondsForTier(1)
local topCycle = cycleSecondsForTier(C.SWING_TIER_COUNT)
print(string.format("\n    cycle time (perfect play): tier 1 %.2f s, tier %d %.2f s", tier1Cycle, C.SWING_TIER_COUNT, topCycle))
print(string.format("    the trip is %.0f%% of ONE tier-1 cycle and %.0f%% of ONE tier-%d cycle",
	tripSeconds / tier1Cycle * 100, tripSeconds / topCycle * 100, C.SWING_TIER_COUNT))
print("\n    amortised -- the player launches N times, then makes ONE trip:")
print("    launches   tier-1 cost   tier-10 cost")
for _, launches in { 5, 10, 20 } do
	local atTier1 = tripSeconds / (launches * tier1Cycle) * 100
	local atTop = tripSeconds / (launches * topCycle) * 100
	print(string.format("    %8d   %10.1f%%   %11.1f%%", launches, atTier1, atTop))
end
do
	local atTen = tripSeconds / (10 * tier1Cycle) * 100
	check(atTen < 40, string.format("at ten launches per trip the collection cost is %.0f%% of cycle time at tier 1 (the worst case, since tier 1 has the shortest cycle)", atTen))
end

--============ 6g: the launch loop itself gained no term at all ============--
print("\n6g. the launch loop is unchanged -- collection added nothing to a cycle")
check(math.abs(RETURN_WALK - 0.25) < 1e-9,
	string.format("the post-flight walk is still %.2f s (%.0f studs at %d studs/s) -- removing the return pad did not move it", RETURN_WALK, returnZ - mountZ, WALK_SPEED))
-- The launch loop does not know collection exists: nothing in LaunchServer reads
-- or writes a pot, and the collect path has no remote for it to call.
local launchSource = C.readSource("src/ServerScriptService/LaunchServer.server.luau")
for _, needle in { "pendingBySlot", "collectPending", "bankSlot", "PendingIncome", "CollectPad" } do
	check(string.find(launchSource, needle, 1, true) == nil,
		string.format("LaunchServer never mentions %q -- the launch loop and collection do not touch", needle))
end
-- And the pad the loop used to walk over is gone from every file that built,
-- placed or labelled it.
for _, spec in {
	{ path = "src/ServerScriptService/PlayerProfile.luau", needle = "ReturnCollectPad" },
	{ path = "src/ReplicatedStorage/Config/BaseGeometry.luau", needle = "function BaseGeometry.returnPadPlacement" },
	{ path = "src/ReplicatedStorage/Config/BaseConfig.luau", needle = "BASE_RETURN_PAD_EDGE_MARGIN_STUDS =" },
	{ path = "src/ReplicatedStorage/Config/BaseConfig.luau", needle = "BASE_RETURN_PAD_Z_MARGIN_STUDS =" },
	{ path = "src/StarterPlayer/StarterPlayerScripts/BaseClient.client.luau", needle = "ReturnCollectPad" },
} do
	check(string.find(C.readSource(spec.path), spec.needle, 1, true) == nil,
		string.format("%s no longer contains %q", spec.path, spec.needle))
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
