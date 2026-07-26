--!strict
-- The slime-leveling formulas -- income multiplier and upgrade cost -- built
-- from SlimeUpgradeConfig's raw numbers, same split as SlimeConfig (data) /
-- SlimeRoll (the module that turns it into a roll). SHARED (ReplicatedStorage,
-- not ServerScriptService) because both sides need the SAME numbers: the
-- server (PlayerProfile.upgradeSlime) as the sole authority on what a
-- purchase actually costs, and the client (InventoryClient's upgrade buttons)
-- to show a cost preview BEFORE clicking, exactly the same way the inventory
-- panel's sell-value preview already reads InventoryConfig directly rather
-- than asking the server first. The server is still the only one who ever
-- actually charges money -- see PlayerProfile.upgradeSlime.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SlimeConfig = require(ReplicatedStorage.Config.SlimeConfig)
local SlimeData = require(ReplicatedStorage.Config.SlimeData)
local SlimeUpgradeConfig = require(ReplicatedStorage.Config.SlimeUpgradeConfig)

local SlimeUpgrade = {}

-- ===== Per-tier max multiplier -- GENERATED (not hand-authored), same
-- philosophy as SlimeData.luau/LuckCurve.luau: a repeated, formulaic list is
-- a loop's job. Tier 1 (Common) anchors at INCOME_MAX_MULTIPLIER_BASE; each
-- tier above multiplies by INCOME_MAX_MULTIPLIER_RATIO again -- see that
-- config's own written report for the fit this reproduces.
local maxMultiplierByTier: { number } = {}
for tier = 1, #SlimeConfig.SLIME_TIER_NAMES do
	maxMultiplierByTier[tier] = SlimeUpgradeConfig.INCOME_MAX_MULTIPLIER_BASE * SlimeUpgradeConfig.INCOME_MAX_MULTIPLIER_RATIO ^ (tier - 1)
end

-- Every external caller (PlayerProfile.luau, InventoryClient.client.luau)
-- only ever has a slime's BASE income/s on hand, not its tier index -- so
-- rather than thread a tier argument through every one of those call sites,
-- this reverse-maps base income back to its tier from EVERY one of the 65
-- individual slimes in SlimeData (not a flat per-tier value -- each slime
-- now has its own MEASURED income, see SlimeConfig.SLIME_INCOME_BY_TIER).
-- Relies on every one of the 65 slimes having a DISTINCT income/s -- true
-- today by inspection (each tier's own values are listed worst-to-best with
-- no repeats, and no two tiers' ranges overlap: Common tops out at $10/s,
-- Uncommon starts at $15/s, ... Secret tops out at $20K/s, Divine starts at
-- $50K/s) -- if a future data update ever gives two slimes (in the same or
-- different tiers) the SAME income, this lookup becomes ambiguous and
-- silently picks whichever was inserted first; worth revisiting (properly,
-- by passing tier explicitly) if that ever stops being true.
local tierByBaseIncome: { [number]: number } = {}
for _, slime in SlimeData.SLIMES do
	if not tierByBaseIncome[slime.incomePerSecond] then
		tierByBaseIncome[slime.incomePerSecond] = slime.tier
	end
end

-- The shared curve SHAPE's own raw value at MAX_LEVEL -- a fixed constant,
-- computed once, used purely to NORMALIZE that shape below so it can be
-- rescaled to land exactly on each tier's own max multiplier instead of one
-- flat number shared by every tier.
local SHAPE_VALUE_AT_MAX_LEVEL = SlimeUpgradeConfig.INCOME_LEVEL_LINEAR_COEFF * (SlimeUpgradeConfig.MAX_LEVEL - 1)
	+ SlimeUpgradeConfig.INCOME_LEVEL_QUADRATIC_COEFF * (SlimeUpgradeConfig.MAX_LEVEL - 1) ^ 2

-- Floors and clamps to [1, MAX_LEVEL] -- the ONE place a level value is ever
-- forced into range, so a hand-edited save, a dev-panel typo, or a client-
-- supplied number can never leave a slime above the cap or below 1.
function SlimeUpgrade.clampLevel(level: number): number
	return math.clamp(math.floor(level), 1, SlimeUpgradeConfig.MAX_LEVEL)
end

-- income(level) = base * multiplier(level). multiplier(1) = 1 exactly (a
-- fresh, never-upgraded slime earns exactly its base income), and
-- multiplier(MAX_LEVEL) = exactly this slime's OWN tier's max multiplier --
-- see the written report. The curve's SHAPE (the relative growth between
-- any two levels) is identical for every tier; only the amplitude it's
-- scaled to differs, via `scale` below.
function SlimeUpgrade.incomeMultiplier(baseIncomePerSecond: number, level: number): number
	local x = level - 1
	local shape = SlimeUpgradeConfig.INCOME_LEVEL_LINEAR_COEFF * x + SlimeUpgradeConfig.INCOME_LEVEL_QUADRATIC_COEFF * x * x

	local tier = tierByBaseIncome[baseIncomePerSecond]
	local maxMultiplier = maxMultiplierByTier[tier] or SlimeUpgradeConfig.INCOME_MAX_MULTIPLIER_BASE
	local scale = (maxMultiplier - 1) / SHAPE_VALUE_AT_MAX_LEVEL

	return 1 + scale * shape
end

function SlimeUpgrade.incomeForLevel(baseIncomePerSecond: number, level: number): number
	return baseIncomePerSecond * SlimeUpgrade.incomeMultiplier(baseIncomePerSecond, level)
end

-- Cost (in seconds of the slime's OWN base income) to upgrade FROM `level`
-- TO `level + 1` -- linear in level, per SlimeUpgradeConfig's written report.
-- Undefined at level >= MAX_LEVEL (there is no next level to price) --
-- callers never reach that case because totalUpgradeCost below always caps
-- the count of levels bought to what's actually available.
local function upgradeCostSeconds(level: number): number
	return SlimeUpgradeConfig.UPGRADE_COST_SECONDS_AT_LEVEL_1 + SlimeUpgradeConfig.UPGRADE_COST_SECONDS_SLOPE_PER_LEVEL * (level - 1)
end

-- The total price to buy UP TO `count` consecutive levels starting from
-- `fromLevel` -- the SUM of each individual level's own cost (never count *
-- the first level's cost), per the task's requirement that buying 10 or 100
-- charges the sum of the individual level costs. Automatically capped at
-- MAX_LEVEL: asking for more levels than remain (e.g. count=100 at level 950)
-- buys only what's left (50 levels here) rather than failing outright --
-- returns the ACTUAL count bought alongside the cost, so a caller (the +100
-- button near the cap) can show "this button will only buy 50 more" instead
-- of silently disabling itself long before the slime is actually maxed.
-- Closed-form (an arithmetic series), not a loop -- upgradeCostSeconds(L) is
-- linear in L, so summing `n` consecutive values from `fromLevel` is exactly
-- n*first + slope*(0+1+...+(n-1)).
function SlimeUpgrade.totalUpgradeCost(baseIncomePerSecond: number, fromLevel: number, count: number): (number, number)
	local maxLevel = SlimeUpgradeConfig.MAX_LEVEL
	local actualCount = math.max(0, math.min(count, maxLevel - fromLevel))
	if actualCount <= 0 then
		return 0, 0
	end

	local firstSeconds = upgradeCostSeconds(fromLevel)
	local slope = SlimeUpgradeConfig.UPGRADE_COST_SECONDS_SLOPE_PER_LEVEL
	local totalSeconds = actualCount * firstSeconds + slope * (actualCount * (actualCount - 1) / 2)
	return baseIncomePerSecond * totalSeconds, actualCount
end

return SlimeUpgrade
