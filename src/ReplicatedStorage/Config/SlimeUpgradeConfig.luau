--!strict
-- Every slime-upgrade constant lives here, and ONLY here -- same rule as
-- every other Config module in this project. The FORMULAS that read these
-- (income multiplier, upgrade cost) live in SlimeUpgrade.luau, right next to
-- this file -- same split as SlimeConfig (data) / SlimeRoll (the module that
-- turns it into a roll), just for the leveling system instead of the reveal.

export type SlimeUpgradeConfig = {
	MAX_LEVEL: number,
	INCOME_LEVEL_LINEAR_COEFF: number,
	INCOME_LEVEL_QUADRATIC_COEFF: number,
	INCOME_MAX_MULTIPLIER_BASE: number,
	INCOME_MAX_MULTIPLIER_RATIO: number,
	UPGRADE_COST_SECONDS_AT_LEVEL_1: number,
	UPGRADE_COST_SECONDS_SLOPE_PER_LEVEL: number,
}

local SlimeUpgradeConfig: SlimeUpgradeConfig = {
	-- Every slime can be leveled from 1 (fresh, unleveled -- income exactly
	-- equals base) up to this cap. See SlimeUpgrade.clampLevel, the only
	-- place a level value is ever clamped.
	MAX_LEVEL = 1000,

	-- ===== Income curve SHAPE: multiplier(level) is proportional to
	-- 1 + LINEAR*(level-1) + QUADRATIC*(level-1)^2 -- see SlimeUpgrade.
	-- incomeMultiplier. This is the SAME normalized curve for every tier
	-- (rescaled per tier by INCOME_MAX_MULTIPLIER_BASE/RATIO below, never
	-- reshaped) -- originally fitted (least squares, weighted by relative
	-- error so the small early-level values aren't swamped by the huge
	-- late-level ones) against the reference Secret slime table in the
	-- written report: base $12.5K/s, max relative error ~5.6% across the 10
	-- sampled levels. Change these two numbers to retune the curve's SHAPE
	-- (how front-loaded vs. back-loaded the growth is); change the max-
	-- multiplier numbers below to retune WHERE each tier's curve ends up.
	INCOME_LEVEL_LINEAR_COEFF = 39.0,
	INCOME_LEVEL_QUADRATIC_COEFF = 0.486,

	-- ===== Income curve ENDPOINT, per tier: a maxed (level MAX_LEVEL) slime
	-- earns base * multiplier, where multiplier is generated per tier as
	-- INCOME_MAX_MULTIPLIER_BASE * INCOME_MAX_MULTIPLIER_RATIO^(tier-1) --
	-- tier 1 (Common) anchors at the base value, each tier above multiplies
	-- by the ratio again. Fitted (log-linear regression) against three
	-- independent reference points in the written report -- Common ~1,700x,
	-- Secret ~500,000x (smoothed by the fit to 562,600x), Divine ~1,415,000x
	-- (smoothed to 1,479,700x) -- which line up on a near-perfect geometric
	-- progression at ratio ~2.630. Retuning the WHOLE per-tier ladder (how
	-- much more generous leveling gets per tier) is moving these two
	-- numbers; SlimeUpgrade.luau generates the actual 8-entry table from
	-- them at load time, indexed by SlimeConfig's own tier order (Common..
	-- Divine) -- never hand-authored, so it can't silently drift out of
	-- sync with a tier count/order change there.
	INCOME_MAX_MULTIPLIER_BASE = 1700.0,
	INCOME_MAX_MULTIPLIER_RATIO = 2.63,

	-- ===== Upgrade cost: the price to go from `level` to `level+1` is
	-- base * (AT_LEVEL_1 + SLOPE_PER_LEVEL*(level-1)) -- linear in level, see
	-- SlimeUpgrade.upgradeCostForLevel. AT_LEVEL_1 = 693 is the deliberate
	-- anchor: a fresh slime's FIRST upgrade costs 693 seconds of its own
	-- base income (a Common at $5/s costs ~$3,465; a Divine at $350K/s costs
	-- ~$242.55M -- see the written report). SLOPE_PER_LEVEL is chosen so that
	-- level 901's upgrade costs ~0.65 seconds of ITS OWN (level-901, already
	-- leveled) income against the reference table -- the same inversion the
	-- task describes: cost keeps growing in raw dollars, but income grows
	-- faster (quadratically), so the SECONDS-of-income price of an upgrade
	-- collapses from 693 down to a fraction of a second by the far end.
	UPGRADE_COST_SECONDS_AT_LEVEL_1 = 693.0,
	UPGRADE_COST_SECONDS_SLOPE_PER_LEVEL = 309.0,
}

return SlimeUpgradeConfig
