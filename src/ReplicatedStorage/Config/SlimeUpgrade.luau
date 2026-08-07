--!strict
-- The slime-leveling formulas -- income multiplier and upgrade cost -- built
-- from SlimeUpgradeConfig's raw numbers, same split as SlimeConfig (data) /
-- SlimeRoll (the module that turns it into a roll). SHARED (ReplicatedStorage,
-- not ServerScriptService) because both sides need the SAME numbers: the
-- server (PlayerProfile.upgradeSlime) as the sole authority on what a
-- purchase actually costs, and the client (InventoryClient's upgrade buttons,
-- SlimeUpgradeTagClient's on-slime strip) to show a cost preview BEFORE
-- clicking, exactly the same way the inventory panel's sell-value preview
-- already reads InventoryConfig directly rather than asking the server first.
-- The server is still the only one who ever actually charges money -- see
-- PlayerProfile.upgradeSlime, which recomputes every cost here from its own
-- state and never trusts a number the client sends.
--
-- ===== REBUILT (see SlimeUpgradeConfig's own header and REPORT.md). This
-- module used to carry a per-tier max-multiplier table generated from
-- INCOME_MAX_MULTIPLIER_BASE/RATIO, a normalisation constant for a quadratic
-- income shape, and a reverse lookup from base income back to tier so that
-- callers holding only an income could find their tier's multiplier. ALL OF
-- THAT IS GONE. Growth is now the same for every tier, so there is no tier to
-- look up, nothing to normalise, and no table to generate. This module no
-- longer reads SlimeConfig or SlimeData at all.
--
-- The fragile part that went with it is worth naming: the tier reverse lookup
-- depended on all 65 slimes having DISTINCT base incomes, and silently picked
-- whichever was inserted first if two ever collided. That failure mode no
-- longer exists because nothing here needs to know a slime's tier. =====
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SlimeUpgradeConfig = require(ReplicatedStorage.Config.SlimeUpgradeConfig)

local SlimeUpgrade = {}

-- The per-level income factor, named once so the formulas below read as the
-- compounding they are.
local GROWTH = 1 + SlimeUpgradeConfig.UPGRADE_GROWTH_RATE

-- Floors and clamps to [1, MAX_LEVEL] -- the ONE place a level value is ever
-- forced into range, so a hand-edited save, a dev-panel typo, or a client-
-- supplied number can never leave a slime above the cap or below 1.
--
-- THIS IS ALSO THE SAVE MIGRATION. Profiles written before the rebuild hold
-- levels up to 1000; PlayerProfile.applyLoadedData runs every loaded level
-- through here, so anything above MAX_LEVEL lands on MAX_LEVEL the first time
-- that profile is read. See REPORT.md for what that costs a player who had
-- one.
function SlimeUpgrade.clampLevel(level: number): number
	return math.clamp(math.floor(level), 1, SlimeUpgradeConfig.MAX_LEVEL)
end

-- multiplier(level) = GROWTH^(level - 1). multiplier(1) = 1 exactly (a fresh,
-- never-upgraded slime earns exactly its base income) and
-- multiplier(MAX_LEVEL) = GROWTH^(MAX_LEVEL - 1) = 28.63x at the current
-- constants -- THE SAME FOR EVERY TIER. The base income argument is not
-- needed to compute this and is not taken.
function SlimeUpgrade.incomeMultiplier(level: number): number
	return GROWTH ^ (level - 1)
end

function SlimeUpgrade.incomeForLevel(baseIncomePerSecond: number, level: number): number
	return baseIncomePerSecond * SlimeUpgrade.incomeMultiplier(level)
end

-- The total price to buy UP TO `count` consecutive levels starting from
-- `fromLevel`. Automatically capped at MAX_LEVEL: asking for more levels than
-- remain (which the MAX button deliberately does -- it sends MAX_LEVEL and
-- lets this cap it) buys only what's left rather than failing outright, and
-- returns the ACTUAL count alongside the cost so a caller can label the
-- button with what it will really buy.
--
-- CLOSED FORM, not a loop. One level from income I costs
-- PAYBACK * GROWTH_RATE * I, and each level multiplies I by GROWTH, so the
-- cost of n consecutive levels is a geometric series:
--     sum = PAYBACK * RATE * I * (1 + G + G^2 + ... + G^(n-1))
--         = PAYBACK * RATE * I * (G^n - 1) / (G - 1)
-- and since G - 1 IS RATE, the RATE cancels outright:
--     sum = PAYBACK * I * (G^n - 1)
-- which is what's computed below. That cancellation is why the payback
-- identity holds for a multi-level purchase too, not just for single levels:
-- n levels cost PAYBACK * I * (G^n - 1) and buy an income gain of exactly
-- I * (G^n - 1), so the ratio is PAYBACK for every n.
function SlimeUpgrade.totalUpgradeCost(baseIncomePerSecond: number, fromLevel: number, count: number): (number, number)
	local actualCount = math.max(0, math.min(count, SlimeUpgradeConfig.MAX_LEVEL - fromLevel))
	if actualCount <= 0 then
		return 0, 0
	end
	local currentIncome = SlimeUpgrade.incomeForLevel(baseIncomePerSecond, fromLevel)
	local cost = SlimeUpgradeConfig.UPGRADE_PAYBACK_SECONDS * currentIncome * (GROWTH ^ actualCount - 1)
	return cost, actualCount
end

return SlimeUpgrade
