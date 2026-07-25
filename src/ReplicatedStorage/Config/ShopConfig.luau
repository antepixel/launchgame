--!strict
-- Every swing-shop constant lives here, and ONLY here -- same rule as every
-- other Config module in this project. Tier PROGRESSION FEEL (how much
-- farther each tier launches) stays in LaunchConfig.SWING_TIER_DISTANCE_
-- SCALE, unchanged and untouched by this task -- this file is just what
-- buying into that curve costs, and how much bigger the swing itself looks
-- once you have.

export type ShopConfig = {
	SWING_TIER_PRICES: { number },
	SWING_VISUAL_SCALE_MIN: number,
	SWING_VISUAL_SCALE_MAX: number,
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
	-- NOTE on scale: tiers 10 and 11 (5e18, 2.5e20) exceed float64's exact-
	-- integer range (~9.007e15, i.e. 2^53) -- see the written report for why
	-- that's fine for a >= affordability check and a rounded-to-1-decimal
	-- display, but not something to build exact-equality logic against.
	SWING_TIER_PRICES = {
		0,
		50000,
		250000,
		1000000,
		10000000,
		100000000,
		1000000000,
		500000000000,
		500000000000000,
		5000000000000000000,
		250000000000000000000,
	},

	-- The swing SEAT's cosmetic size multiplier at tier 1 and at the max
	-- tier -- linearly interpolated between them by tier number (see
	-- LaunchServer.server.luau's applySwingVisualForTier). Purely visual:
	-- nothing here feeds into distance, timing, or the seat's actual
	-- POSITION (still driven entirely by the swing's existing phase math,
	-- completely untouched) -- see the written report for why size-only,
	-- seat-only was chosen as this pass's "something simple."
	SWING_VISUAL_SCALE_MIN = 1.0,
	SWING_VISUAL_SCALE_MAX = 1.5,
}

return ShopConfig
