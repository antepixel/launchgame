--!strict
-- Every slime-upgrade constant lives here, and ONLY here -- same rule as
-- every other Config module in this project. The FORMULAS that read these
-- (income multiplier, upgrade cost) live in SlimeUpgrade.luau, right next to
-- this file -- same split as SlimeConfig (data) / SlimeRoll (the module that
-- turns it into a roll), just for the leveling system instead of the reveal.
--
-- ===== REBUILT (see REPORT.md). The previous curve was 1000 levels, a
-- quadratic income shape normalised to a PER-TIER maximum multiplier
-- (1,700x for Common up to 1,479,582x for Divine, a geometric ladder at
-- ratio 2.63), and a cost that was a linear-in-level multiple of the slime's
-- BASE income fitted against one reference Secret slime. Three things were
-- wrong with it and all three are gone:
--
--   1. THE COST WAS FITTED TO ONE TIER AND ONLY WORKED THERE. Cost scaled
--      with BASE income while the multiplier that repaid it scaled per tier,
--      so the same nominal upgrade cost a Common 200 seconds of its own
--      income at level 901 and a Secret 0.61 -- a 330x spread for the same
--      action.
--   2. PAYBACK GOT MONOTONICALLY WORSE WITH LEVEL. A Common's single level
--      paid back in 1.5 hours at level 1 and 26 hours at level 900, rising
--      the whole way and converging to a floor from below. Levelling was
--      always least bad the moment you started and never improved.
--   3. THE PER-TIER MULTIPLIER LADDER DOUBLE-COUNTED TIER. Tier already
--      determines base income; scaling the growth by tier as well meant a
--      Divine's level was worth 871x a Common's ON TOP of already earning
--      more per second, so levelling a low-tier slime was never worth doing
--      at any level.
--
-- The replacement is deliberately boring: flat compounding growth, identical
-- for every tier, with a cost pinned to a constant payback time. Tier
-- difference comes from base income alone, which is where it belongs. =====

export type SlimeUpgradeConfig = {
	MAX_LEVEL: number,
	UPGRADE_GROWTH_RATE: number,
	UPGRADE_PAYBACK_SECONDS: number,
}

local SlimeUpgradeConfig: SlimeUpgradeConfig = {
	-- Every slime can be leveled from 1 (fresh, unleveled -- income exactly
	-- equals base) up to this cap. See SlimeUpgrade.clampLevel, the only
	-- place a level value is ever clamped.
	--
	-- 25, down from 1000. A thousand levels was never 1000 decisions: with a
	-- fixed payback per level, every level is the same decision, so 1000 of
	-- them is one decision presented 1000 times. 25 is short enough that
	-- maxing a slime is a visible goal a player can hold in their head and
	-- reach, and short enough that "+1 / +5 / MAX" covers the whole range --
	-- see the button strips in InventoryClient and SlimeUpgradeTagClient.
	MAX_LEVEL = 25,

	-- ===== THE INCOME CURVE. income(level) = base * (1 + this)^(level - 1).
	-- Plain compounding, IDENTICAL FOR EVERY TIER -- there is no per-tier
	-- multiplier any more and no ratio to scale one. A Common and a Divine
	-- both reach exactly (1.15)^24 = 28.63x their own base at level 25.
	--
	-- Chosen against MAX_LEVEL so that a fully maxed slime is worth roughly
	-- one and a half tiers of base income, not five: tier base incomes step
	-- 2.4x-3.2x apart through the mid ladder, so 28.63x is about three tier
	-- steps. That is the intended reading -- maxing a slime should beat
	-- holding a slightly better one and lose to holding a much better one, so
	-- both levelling and rolling stay worth doing. See REPORT.md for the
	-- maxed-Common-against-every-tier table.
	UPGRADE_GROWTH_RATE = 0.15,

	-- ===== THE COST CURVE, and it is defined by its PAYBACK rather than by a
	-- shape. The price of the next level is
	--     UPGRADE_PAYBACK_SECONDS * UPGRADE_GROWTH_RATE * current income/s
	-- (note CURRENT income, not base -- that is the whole trick), which at
	-- these values is 90x current income.
	--
	-- WHY THIS IS EXACTLY 600 SECONDS OF PAYBACK, ALWAYS. One level buys an
	-- income gain of GROWTH * I, where I is the slime's current income. It
	-- costs PAYBACK * GROWTH * I. So
	--     cost / gain = (PAYBACK * GROWTH * I) / (GROWTH * I) = PAYBACK
	-- and both I and GROWTH cancel. The payback time is therefore the same at
	-- every level, for every tier, for every slime in the game, by
	-- construction rather than by fitting -- there is nothing left for a
	-- future retune to accidentally break. It also means this number is
	-- directly meaningful: it IS how long an upgrade takes to pay for itself,
	-- in seconds, and it is the only lever on how expensive levelling feels.
	--
	-- 600 = ten minutes of that slime's own production. Long enough that
	-- levelling is a real commitment against buying a swing tier; short
	-- enough that a slime you have parked for a session has earned its next
	-- level several times over.
	UPGRADE_PAYBACK_SECONDS = 600,
}

return SlimeUpgradeConfig
