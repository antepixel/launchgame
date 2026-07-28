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
}

return ShopConfig
