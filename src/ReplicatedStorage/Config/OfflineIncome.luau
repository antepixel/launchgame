--!strict
-- The offline-earnings ARITHMETIC, next to the constants it reads -- same
-- arrangement SlimeUpgrade.luau has with SlimeUpgradeConfig.luau, and for the
-- same two reasons: the formula belongs beside its tuning, and a pure function
-- with no service dependencies can be loaded and TESTED on the command line
-- (see dev/analysis/verify_offline.luau) rather than only inside a running
-- Studio session.
--
-- That second reason is the whole point of this module existing rather than the
-- five lines living inside PlayerProfile.creditOfflineIncome, where they
-- started. PlayerProfile requires Players, HttpService, a DataStore-backed
-- PlayerStore and a built Workspace.MapBlockout at module scope, so nothing in
-- it can be exercised outside the game. The decisions that actually matter here
-- -- what a missing timestamp credits, what a clock running backwards credits,
-- what happens at and past the cap -- are decisions about three numbers, and
-- they are now checkable against the REAL code instead of a copy of it.
--
-- SERVER-SIDE CALLERS ONLY, though it lives in ReplicatedStorage (with every
-- other Config module). Nothing here trusts an argument: `lastSeen` is
-- deliberately typed `any` because its ONLY source is a DataStore record, which
-- may be absent, from a save written before this feature existed, or
-- hand-edited. The caller must pass a server clock (os.time()); this module
-- cannot enforce that and does not pretend to.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseConfig = require(ReplicatedStorage.Config.BaseConfig)

local OfflineIncome = {}

-- How many seconds of absence to actually pay for, given a saved `lastSeen` and
-- the current server time. Always in [0, OFFLINE_CAP_SECONDS].
--
-- THREE CASES, all deliberate:
--
--   lastSeen missing or not a number -> 0. A brand-new profile has no save at
--     all, and every save written before this feature existed has no such
--     field. Both must mean "no offline time," NOT "last seen at the epoch" --
--     `lastSeen or 0` would have handed every pre-existing player the full cap
--     on their first join after the update, which is why the nil case is
--     tested here rather than defaulted upstream.
--
--   now < lastSeen -> 0. os.time() is each machine's own wall clock and a
--     player can be saved by one server and loaded by another running a few
--     seconds behind. The low clamp turns that into "credit nothing" instead of
--     a negative credit that would SUBTRACT from a pot the player legitimately
--     earned before logging off.
--
--   now - lastSeen > cap -> cap. The DESIGN limit -- 12 hours, see
--     BaseConfig.OFFLINE_CAP_SECONDS for why that number and why capping at all
--     protects the returning player rather than punishing the absent one.
--     Everything past it is simply not paid, so a day, a week and three months
--     all return the identical figure. Note this is the only one of the three
--     cases that is a DESIGN decision; the two above are corrupt-input handling
--     and neither goes anywhere near the cap.
function OfflineIncome.elapsedSeconds(lastSeen: any, now: number): number
	if typeof(lastSeen) ~= "number" then
		return 0
	end
	-- NaN fails every comparison, so it would survive math.clamp unchanged and
	-- poison the credit. Caught explicitly: a NaN timestamp is a corrupt one,
	-- and a corrupt one credits nothing.
	if lastSeen ~= lastSeen then
		return 0
	end
	return math.clamp(now - lastSeen, 0, BaseConfig.OFFLINE_CAP_SECONDS)
end

-- What to add to a pending pot for a player who was away, given the rate that
-- pot earns at. Never negative.
--
-- CALLED ONCE PER SLOT NOW, not once per player (see PlayerProfile.
-- creditOfflineIncome): `incomePerSecond` is that ONE SLOT's own rate, from the
-- same slotIncomePerSecond the online tick credits with -- not a re-derivation,
-- and not a share of a total worked out by a second formula. Since `elapsed`
-- depends only on the timestamps, the per-slot credits sum to exactly what one
-- call at the summed rate would have returned, which is what makes the
-- distribution proportional by construction.
--
-- The only thing separating offline from online is OFFLINE_RATE_MULTIPLIER, and
-- it is applied HERE and nowhere else -- deliberately the single knob between
-- them.
--
-- A rate of zero (an empty slot, or an empty base) credits zero however long the
-- absence was -- offline income is SELF-SCALING, a multiple of what the player
-- has actually built, never a flat grant.
function OfflineIncome.creditFor(lastSeen: any, now: number, incomePerSecond: number): number
	if incomePerSecond <= 0 then
		return 0
	end
	local elapsed = OfflineIncome.elapsedSeconds(lastSeen, now)
	if elapsed <= 0 then
		return 0
	end
	return elapsed * incomePerSecond * BaseConfig.OFFLINE_RATE_MULTIPLIER
end

return OfflineIncome
