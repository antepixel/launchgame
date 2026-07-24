--!strict
-- Every slime-collection constant lives here, and ONLY here -- same rule as
-- LaunchConfig.luau, just for a different subsystem. Kept as its own file
-- rather than folded into LaunchConfig: LaunchConfig's own header scopes it
-- to "feel-related" LAUNCH constants specifically -- this is a separate
-- system bolted onto the box's open outcome, not a launch-feel number.

export type SlimeConfig = {
	SLIME_TIER_NAMES: { string },
	SLIME_TIER_COUNTS: { number },
	SLIME_TIER_COLORS: { Color3 },
	SLIME_TIER_BASE_INCOME: { number },
	SLIME_LUCK_ANCHOR_LOW: number,
	SLIME_LUCK_ANCHOR_HIGH: number,
	SLIME_WINDOW_WIDTH: number,
	SLIME_WINDOW_START_LOW: number,
	SLIME_WINDOW_START_HIGH: number,
	SLIME_PEAK_OFFSET_LOW: number,
	SLIME_PEAK_OFFSET_HIGH: number,
	SLIME_SPREAD_DOWN_LOW: number,
	SLIME_SPREAD_DOWN_HIGH: number,
	SLIME_SPREAD_UP_LOW: number,
	SLIME_SPREAD_UP_HIGH: number,
	SLIME_SHAPE_LOW: number,
	SLIME_SHAPE_HIGH: number,
	SLIME_EXTRAPOLATION_T_MIN: number,
	SLIME_EXTRAPOLATION_T_MAX: number,
	REVEAL_BOX_TO_SLIME_DELAY_SECONDS: number,
	SLIME_TIER_TEXT_SIZE_BASE: number,
	SLIME_TIER_TEXT_SIZE_STEP: number,
}

local SlimeConfig: SlimeConfig = {
	-- ===== The catalog (see SlimeData.luau for the generator that reads
	-- these into 65 actual slime records) =====
	-- Ordered low-to-high rarity -- every array below (COUNTS, COLORS,
	-- BASE_INCOME) is indexed by this SAME position, and the roll's window/
	-- peak math further down works in these same 1-8 tier-index terms.
	SLIME_TIER_NAMES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret", "Divine" },
	-- How many distinct slimes exist in each tier -- 65 total
	-- (6+6+6+6+6+6+21+8). Secret is the deliberate outlier: a wide bucket of
	-- equally-weighted individuals rather than a narrow one, matching the
	-- reference game's own shape (a big "junk rare" bucket below the true
	-- top tier).
	SLIME_TIER_COUNTS = { 6, 6, 6, 6, 6, 6, 21, 8 },
	-- Placeholder colours ONLY -- swapped for real art later. Each slime's
	-- individual colour (see SlimeData.luau) is simply its tier's colour for
	-- now, so this array alone controls what every slime in the game looks
	-- like at a glance: dull grey at the bottom, escalating through green/
	-- blue/purple/orange/red to a deep "mysterious" violet for Secret and a
	-- bright warm gold-white for Divine -- deliberately the two furthest-
	-- apart colours in the list, since those are the two tiers that most need
	-- to read as "obviously different" from everything below them.
	SLIME_TIER_COLORS = {
		Color3.fromRGB(184, 184, 191), -- Common: light grey
		Color3.fromRGB(77, 217, 89), -- Uncommon: green
		Color3.fromRGB(64, 140, 250), -- Rare: blue
		Color3.fromRGB(166, 64, 242), -- Epic: purple
		Color3.fromRGB(255, 153, 13), -- Legendary: orange
		Color3.fromRGB(242, 38, 77), -- Mythic: crimson
		Color3.fromRGB(140, 26, 191), -- Secret: deep violet
		Color3.fromRGB(255, 237, 153), -- Divine: gold-white
	},
	-- Placeholder economy -- income-per-second per slime, flat within a tier
	-- (no per-slime variance this pass). Nothing reads this yet (no income
	-- accumulation exists) -- it's here so the field exists on every slime
	-- record now rather than being bolted on later. Roughly 2.5-3x per tier,
	-- echoing the luck curve's own tier-to-tier ratio (see LaunchConfig.
	-- SWING_TIER_DISTANCE_SCALE's written report).
	SLIME_TIER_BASE_INCOME = { 1, 3, 8, 20, 50, 125, 400, 1200 },

	-- ===== The roll: luck slides a WINDOW of tiers, and reshapes the
	-- weighting within it -- see SlimeRoll.luau for the full model and why.
	-- Every number below is a LOW/HIGH pair, linearly interpolated on LOG-
	-- luck between the two anchors and clamped to [EXTRAPOLATION_T_MIN,
	-- EXTRAPOLATION_T_MAX] beyond them. Retuning the curve's shape is
	-- changing these numbers, never rewriting SlimeRoll's formula. =====

	-- The two OBSERVED reference points (see the written report) everything
	-- else is anchored to.
	SLIME_LUCK_ANCHOR_LOW = 25,
	SLIME_LUCK_ANCHOR_HIGH = 120000,
	-- How many consecutive tiers are ever eligible at once. 4 reproduces both
	-- anchors exactly (Common-Epic at the low end, Legendary-Divine at the
	-- high end are both 4-tier spans) -- see the written report.
	SLIME_WINDOW_WIDTH = 4,
	-- Window's bottom tier (1-indexed) at each anchor -- 1 (Common) at low
	-- luck, 5 (Legendary) at high luck. Interpolated then ROUNDED to a whole
	-- tier at roll time -- see SlimeRoll.luau for why rounding (not a smooth
	-- fade) is what makes "rolled off entirely" a clean cutoff.
	SLIME_WINDOW_START_LOW = 1,
	SLIME_WINDOW_START_HIGH = 5,
	-- Where the PEAK (most-likely tier) sits within the window, as an offset
	-- from the window's bottom tier. 0 at low luck -- the peak sits AT the
	-- bottom (Common is most likely, decaying upward -- matches "flat
	-- between the top two, small tail"). 1 at high luck -- the peak sits ONE
	-- tier in from the bottom (Mythic, not Legendary -- matches "concentrated
	-- in one tier with a thin rare tail" AND leaves room for a below-peak
	-- tail, which the low-luck anchor's peak-at-the-floor shape cannot have).
	SLIME_PEAK_OFFSET_LOW = 0.0,
	SLIME_PEAK_OFFSET_HIGH = 1.0,
	-- Decay rate BELOW the peak (toward lower tiers) and ABOVE it (toward
	-- higher tiers) -- kept SEPARATE (not one symmetric spread) because the
	-- high-luck anchor is observably asymmetric: Legendary (1 tier below
	-- Mythic) sits at 15%, but Secret (1 tier above) sits at only 6% -- a
	-- symmetric shape could never produce two different weights at the same
	-- distance. Solved from the anchors, not guessed -- see the written
	-- report for the algebra.
	SLIME_SPREAD_DOWN_LOW = 1.668,
	SLIME_SPREAD_DOWN_HIGH = 0.520,
	SLIME_SPREAD_UP_LOW = 1.668,
	SLIME_SPREAD_UP_HIGH = 0.292,
	-- The generalised-Gaussian shape exponent: weight ~ exp(-(distance/
	-- spread)^shape). HIGH (>1) at low luck gives a wide FLAT plateau near
	-- the peak with a steep cliff just past it -- "nearly flat between the
	-- top two available tiers, small tail." LOW (<1) at high luck gives a
	-- sharp single SPIKE with a longer tail -- "concentrated in one tier
	-- with a thin rare tail." The shape itself changing (not just sliding)
	-- is what the task means by "the distribution's shape changes as it
	-- climbs," not just the window moving.
	SLIME_SHAPE_LOW = 4.4,
	SLIME_SHAPE_HIGH = 0.764,
	-- How far past the two observed anchors (in the same log-luck t units,
	-- where the anchors are t=0 and t=1) the interpolation is allowed to
	-- extrapolate before clamping. MIN=-0.5 lets luck somewhat below 25
	-- still produce a smoothly-extrapolated (not wildly distorted)
	-- distribution -- verified safe (SHAPE stays comfortably positive down
	-- to well past this bound).
	--
	-- MAX=1.0, deliberately NOT beyond the high anchor -- the window position
	-- is already fully saturated at t=1 (windowStart's own lerp already
	-- reaches its clamped ceiling there, tiers 5-8, so extrapolating t
	-- further slides nothing), and the shape exponent crosses ZERO at
	-- t=1.21 and goes NEGATIVE beyond that -- undefined/degenerate math, not
	-- "more concentrated." The box's doubling has no ceiling (see
	-- LaunchConfig.BOX_DOUBLE_CHANCE), so luck CAN genuinely exceed 120,000
	-- by a lot on a long chain -- this cap is what keeps an extreme chain's
	-- roll safe: luck at or above 120,000 always uses the exact high-anchor
	-- shape (t pinned to 1), never something further extrapolated.
	SLIME_EXTRAPOLATION_T_MIN = -0.5,
	SLIME_EXTRAPOLATION_T_MAX = 1.0,

	-- ===== The reveal (see LaunchServer's onBoxPress and LaunchClient's
	-- SlimeRevealed handler) =====
	-- Seconds between the box showing "OPENED!" and the slime itself
	-- appearing -- THE SECOND beat, distinct from BOX_ROLL_DELAY_SECONDS
	-- (the first, before the open/double result). Long enough to read as a
	-- separate moment, not a continuation of the same instant.
	REVEAL_BOX_TO_SLIME_DELAY_SECONDS = 0.6,
	-- Tier name text size (pixels): BASE at tier 1 (Common), +STEP per tier
	-- above it -- so Divine (tier 8) renders at BASE + 7*STEP. This, plus the
	-- tier's own colour, is what makes a Divine reveal "obviously a bigger
	-- deal" than a Common one using nothing but text and colour.
	SLIME_TIER_TEXT_SIZE_BASE = 28,
	SLIME_TIER_TEXT_SIZE_STEP = 6,
}

return SlimeConfig
