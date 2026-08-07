--!strict
-- Every swing-shop constant lives here, and ONLY here -- same rule as every
-- other Config module in this project. Tier PROGRESSION FEEL (how much
-- farther each tier launches) stays in LaunchConfig.SWING_TIER_DISTANCE_
-- SCALE, unchanged and untouched by this task -- this file is just what
-- buying into that curve costs. How much bigger/flashier the swing looks per
-- tier moved to ReplicatedStorage/Config/SwingTierVisuals.luau (previously a
-- simple SWING_VISUAL_SCALE_MIN/MAX range lived here, but that only ever
-- covered the seat's size -- see the written report for the full per-tier
-- visual overhaul).

export type ShopConfig = {
	SWING_TIER_PRICES: { number },
}

local ShopConfig: ShopConfig = {
	-- Cost to buy INTO tier N, indexed by N directly -- same 1-indexed-by-
	-- tier-number convention as LaunchConfig.SWING_TIER_DISTANCE_SCALE.
	-- Index 1 is unused (0): every player already starts at tier 1, nothing
	-- is ever bought to reach it -- see PlayerProfile.buyNextTier, which
	-- only ever prices tier `currentTier + 1`. Must stay exactly as many
	-- entries as SWING_TIER_DISTANCE_SCALE (11) -- PlayerProfile reads
	-- #LaunchConfig.SWING_TIER_DISTANCE_SCALE as the authoritative tier
	-- count, not a separately-authored number here, so the two can never
	-- silently drift apart in length.
	--
	-- ===== REPRICED (see REPORT.md). The old ladder (50K / 250K / 1M / 10M /
	-- 100M / 1B / 500B / 500T / 5Qi / 250Qi) predated both the roll-
	-- distribution fix and the upgrade-curve rebuild, and its top was not a
	-- progression at all: tier 9 -> 10 measured at 1.75 MILLION YEARS of play
	-- even with a fully maxed base. Every price above tier 6 has come down by
	-- orders of magnitude; tiers 2-6 moved much less.
	--
	-- ===== HOW THESE WERE DERIVED. Each price is the one that makes the wait
	-- for that tier hit a TARGET TIME, given a model of what the player's
	-- income is when they are standing at the tier below. The targets, tier by
	-- tier:
	--
	--   tier 2:   6 min      tier 7:   3 h
	--   tier 3:  12 min      tier 8:   6 h
	--   tier 4:  24 min      tier 9:  12 h
	--   tier 5:  40 min      tier 10: 28 h
	--   tier 6:  70 min      tier 11: 80 h
	--
	-- Roughly doubling per tier through the early game, so each tier is a
	-- session-shaped goal rather than a wall, and tiers 2-6 together fit
	-- inside one sitting alongside levelling slimes and ordinary play.
	--
	-- The income model behind them: ten filled slots earning the expected
	-- income of the tier distribution at that tier's own post-box luck (see
	-- SlimeRoll and LuckCurve), multiplied by a LEVEL MULTIPLIER that ramps
	-- from 1x at tier 1 up to the fully-maxed 28.63x by tier 5 and stays there
	-- afterwards -- the assumption being that a player levels their base
	-- alongside climbing the early ladder and has it maxed by the mid game.
	--
	-- ===== THE RAMP IS GEOMETRIC, and for tiers 3, 4 and 5 that is
	-- LOAD-BEARING rather than a detail. The multiplier is
	--     28.6252 ^ ((tier - 1) / 4)
	-- giving 1.00x / 2.31x / 5.35x / 12.38x / 28.63x at tiers 1-5. Geometric,
	-- not linear, because a level multiplier COMPOUNDS: a player maxes their
	-- best slime first and works down, so the multiplier grows by ratio, not
	-- by equal increments. A linear ramp would read 1.00 / 7.91 / 14.81 /
	-- 21.72 / 28.63 -- crediting the player with 7.9x their base income by
	-- tier 2, which no plausible play pattern produces that early.
	--
	-- The two readings disagree by up to 3.8x on tiers 3-5, and by NOTHING
	-- from tier 6 up, where the ramp has saturated at 28.63x and every reading
	-- is the same number. So this choice only prices tiers 3, 4 and 5; every
	-- other price in this table is independent of it. If the ramp shape is
	-- ever revisited, those three are the only ones that move.
	--
	-- THE RAMP IS STILL A MODEL, NOT A MEASUREMENT. Nobody has watched a
	-- player do this. It is a claim about how levelling and tier-buying
	-- interleave, and it is the single assumption tiers 3-5 rest on. If real
	-- players level faster or slower than the ramp says, those three prices
	-- are wrong in proportion and they are the first thing to re-derive -- not
	-- the target times, which are a design choice, and not the income figures,
	-- which are computed. See REPORT.md for the measured times these actually
	-- produce under both a level-1 base and a fully maxed one; the truth is
	-- bracketed by those two, and the ramp is a claim about where inside that
	-- bracket a real player sits.
	--
	-- ===== ROUNDED TO READABLE NUMBERS, within a 5% accuracy budget. The
	-- exact target-hitting values under the ramp above are $432,844 /
	-- $5,118,433 / $20,017,095 for tiers 3, 4 and 5; they are written as
	-- $450K / $5M / $20M, costing +3.96% / -2.31% / -0.09% of target time.
	-- A price a player reads on a button is worth a few percent of a
	-- twelve-minute target. Tier 3 spends most of the budget on its own: $425K
	-- would have cost only -1.8%, but $450K is the rounder number and 3.96%
	-- is still comfortably inside the budget.
	--
	-- ===== THE MULTIPLIERS BETWEEN TIERS ARE DELIBERATELY LUMPY (about 4.5x,
	-- 11x, 4x, 12.5x, 12x, 2x, 18x, 2.4x, 3.1x). That is not sloppiness and
	-- should not be "cleaned up" into a smooth ladder. Income does not grow
	-- smoothly: the roll window advances in discrete jumps, so expected income
	-- leaps at a window crossing and is nearly flat between crossings. Pricing
	-- smoothly against lumpy income is what produces lumpy TIMES -- some tiers
	-- instant, others walls. Pricing lumpily against lumpy income is what
	-- makes the times come out even, which is the thing the player actually
	-- experiences. Tier 8 at 2x and tier 10 at 2.4x look too cheap next to
	-- tier 9's 18x precisely because income barely moves across those steps.
	--
	-- NOTE on scale: every value now sits far inside float64's exact-integer
	-- range (2^53 ~= 9.007e15), unlike the old tiers 10 and 11 which exceeded
	-- it. Exact-equality logic against these is safe again, though nothing
	-- currently relies on that -- PlayerProfile.buyNextTier still only does a
	-- >= affordability check.
	SWING_TIER_PRICES = {
		0,
		100000,
		450000,
		5000000,
		20000000,
		250000000,
		3000000000,
		6000000000,
		110000000000,
		260000000000,
		800000000000,
	},
}

return ShopConfig
