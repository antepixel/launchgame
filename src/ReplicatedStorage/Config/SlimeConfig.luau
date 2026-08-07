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
	SLIME_COLOR_BY_TIER: { { Color3 } },
	SLIME_INCOME_BY_TIER: { { number } },
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
	REVEAL_DISMISS_LOCKOUT_SECONDS: number,
	SLIME_REVEAL_WIDTH_STUDS: number,
	SLIME_REVEAL_ENTRANCE_SECONDS: number,
	SLIME_REVEAL_RISE_STUDS: number,
	SLIME_REVEAL_LABEL_HEIGHT_STUDS: number,
	SLIME_REVEAL_LABEL_WIDTH_PIXELS: number,
	SLIME_REVEAL_LABEL_HEIGHT_PIXELS: number,
	SLIME_TIER_TEXT_SIZE_BASE: number,
	SLIME_TIER_TEXT_SIZE_STEP: number,
}

local SlimeConfig: SlimeConfig = {
	-- ===== The catalog (see SlimeData.luau for the generator that reads
	-- these into 65 actual slime records) =====
	-- Ordered low-to-high rarity -- every array below (COUNTS, COLORS,
	-- INCOME_BY_TIER) is indexed by this SAME position, and the roll's
	-- window/peak math further down works in these same 1-8 tier-index terms.
	SLIME_TIER_NAMES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret", "Divine" },
	-- How many distinct slimes exist in each tier -- 65 total
	-- (6+6+6+6+6+6+21+8). Secret is the deliberate outlier: a wide bucket of
	-- equally-weighted individuals rather than a narrow one, matching the
	-- reference game's own shape (a big "junk rare" bucket below the true
	-- top tier).
	SLIME_TIER_COUNTS = { 6, 6, 6, 6, 6, 6, 21, 8 },
	-- Placeholder colours ONLY -- swapped for real art later. This is the
	-- TIER's own colour -- kept as a SEPARATE field on every slime (see
	-- SlimeData.luau's `tierColor`), read wherever a tier needs to read as
	-- "obviously different" from the tiers around it (the reveal panel,
	-- inventory rows -- see the written report): dull grey at the bottom,
	-- escalating through green/blue/purple/orange/red to a deep "mysterious"
	-- violet for Secret and a bright warm gold-white for Divine --
	-- deliberately the two furthest-apart colours in the list.
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
	-- Placeholder colours ONLY -- swapped for real art later, same as
	-- SLIME_TIER_COLORS above. PER-SLIME, not per-tier (see the written
	-- report -- every slime used to just inherit its tier's own colour,
	-- making every slime within a tier visually identical): one array per
	-- tier, one entry per slime in that tier, SAME SHAPE and SAME per-tier
	-- indexing as SLIME_INCOME_BY_TIER below (SlimeData.luau's generator
	-- reads this the identical way, entry i to "<TierName> Slime i", and
	-- asserts its length against SLIME_TIER_COUNTS the same way too) --
	-- deliberately the least-restructuring fit for that existing loop.
	--
	-- AUTHORED, not generated -- every value below is a hand-picked RGB
	-- triple, not a computed hue rotation. Common through Mythic (the six
	-- 6-slime tiers) each use the SAME six hues, in the SAME order --
	-- green/red/blue/yellow/purple/orange -- so colours repeat ACROSS tiers
	-- (every tier's own "Slime 1" is green) but never WITHIN one, which is
	-- the only invariant that actually matters here (tier identity already
	-- comes from SLIME_TIER_COLORS above, not from this array). Secret (21)
	-- reuses those same six for its first six slimes, then adds 15 further
	-- authored hues, distinct from the six AND from each other, so all 21
	-- stay pairwise distinct within the tier. Divine (8) reuses the same six
	-- plus the FIRST TWO of Secret's own 15 extra hues -- reused rather than
	-- reinvented, since only within-tier uniqueness is required, never
	-- cross-tier uniqueness.
	SLIME_COLOR_BY_TIER = {
		{ -- Common
			Color3.fromRGB(70, 200, 80), Color3.fromRGB(225, 60, 60), Color3.fromRGB(60, 120, 240),
			Color3.fromRGB(245, 215, 55), Color3.fromRGB(165, 80, 220), Color3.fromRGB(250, 140, 40),
		},
		{ -- Uncommon
			Color3.fromRGB(70, 200, 80), Color3.fromRGB(225, 60, 60), Color3.fromRGB(60, 120, 240),
			Color3.fromRGB(245, 215, 55), Color3.fromRGB(165, 80, 220), Color3.fromRGB(250, 140, 40),
		},
		{ -- Rare
			Color3.fromRGB(70, 200, 80), Color3.fromRGB(225, 60, 60), Color3.fromRGB(60, 120, 240),
			Color3.fromRGB(245, 215, 55), Color3.fromRGB(165, 80, 220), Color3.fromRGB(250, 140, 40),
		},
		{ -- Epic
			Color3.fromRGB(70, 200, 80), Color3.fromRGB(225, 60, 60), Color3.fromRGB(60, 120, 240),
			Color3.fromRGB(245, 215, 55), Color3.fromRGB(165, 80, 220), Color3.fromRGB(250, 140, 40),
		},
		{ -- Legendary
			Color3.fromRGB(70, 200, 80), Color3.fromRGB(225, 60, 60), Color3.fromRGB(60, 120, 240),
			Color3.fromRGB(245, 215, 55), Color3.fromRGB(165, 80, 220), Color3.fromRGB(250, 140, 40),
		},
		{ -- Mythic
			Color3.fromRGB(70, 200, 80), Color3.fromRGB(225, 60, 60), Color3.fromRGB(60, 120, 240),
			Color3.fromRGB(245, 215, 55), Color3.fromRGB(165, 80, 220), Color3.fromRGB(250, 140, 40),
		},
		{ -- Secret (21): the six above, then 15 further authored hues
			Color3.fromRGB(70, 200, 80), Color3.fromRGB(225, 60, 60), Color3.fromRGB(60, 120, 240),
			Color3.fromRGB(245, 215, 55), Color3.fromRGB(165, 80, 220), Color3.fromRGB(250, 140, 40),
			Color3.fromRGB(35, 190, 175), -- teal
			Color3.fromRGB(235, 55, 150), -- magenta
			Color3.fromRGB(160, 225, 45), -- lime
			Color3.fromRGB(95, 55, 195), -- indigo
			Color3.fromRGB(55, 200, 230), -- sky cyan
			Color3.fromRGB(140, 35, 55), -- maroon
			Color3.fromRGB(150, 145, 30), -- olive
			Color3.fromRGB(240, 110, 95), -- coral
			Color3.fromRGB(95, 105, 170), -- slate blue
			Color3.fromRGB(110, 225, 165), -- mint
			Color3.fromRGB(150, 55, 115), -- plum
			Color3.fromRGB(70, 150, 190), -- steel blue
			Color3.fromRGB(170, 110, 45), -- amber brown
			Color3.fromRGB(215, 90, 130), -- rose
			Color3.fromRGB(200, 220, 70), -- chartreuse
		},
		{ -- Divine (8): the six above, then the first two of Secret's own extra hues
			Color3.fromRGB(70, 200, 80), Color3.fromRGB(225, 60, 60), Color3.fromRGB(60, 120, 240),
			Color3.fromRGB(245, 215, 55), Color3.fromRGB(165, 80, 220), Color3.fromRGB(250, 140, 40),
			Color3.fromRGB(35, 190, 175), -- teal
			Color3.fromRGB(235, 55, 150), -- magenta
		},
	},
	-- MEASURED economy -- income-per-second for every one of the 65 slimes,
	-- read off the reference game's own index screen, one array per tier IN
	-- THE SAME ORDER as that tier's slimes (SlimeData.luau's generator zips
	-- entry i of this array to "<TierName> Slime i"). Replaces the old
	-- guessed, flat-per-tier placeholder (every slime in a tier sharing one
	-- number) -- these are real, distinct per-slime values, worst-to-best
	-- within each tier, and the RATIOS between tiers (not just within one)
	-- are now real too: Common's cheapest ($5/s) to Divine's priciest
	-- ($350K/s) spans ~70,000x on its own, before any leveling. Each inner
	-- array's length MUST match SLIME_TIER_COUNTS' entry at that same index
	-- -- SlimeData.luau asserts this at load time rather than silently
	-- truncating or leaving a slime's income nil.
	SLIME_INCOME_BY_TIER = {
		{ 5, 6, 7, 8, 9, 10 }, -- Common
		{ 15, 17, 19, 21, 23, 25 }, -- Uncommon
		{ 35, 40, 45, 50, 55, 60 }, -- Rare
		{ 80, 95, 110, 125, 140, 150 }, -- Epic
		{ 250, 300, 350, 400, 450, 500 }, -- Legendary
		{ 800, 950, 1100, 1250, 1400, 1500 }, -- Mythic
		-- Secret: 21 entries -- the deliberate wide "junk rare" bucket (see
		-- SLIME_TIER_COUNTS' own comment), so its income spread is the
		-- widest of any tier too (3000..20000, not a clean arithmetic step).
		{ 3000, 3500, 4000, 4500, 5000, 5500, 6000, 6500, 7000, 8000, 9000, 10000, 11000, 12500, 14000, 15500, 16500, 17500, 18500, 19250, 20000 },
		{ 50000, 65000, 80000, 100000, 130000, 170000, 220000, 350000 }, -- Divine
	},

	-- ===== The roll: luck slides a WINDOW of tiers, and reshapes the
	-- weighting within it -- see SlimeRoll.luau for the full model and why.
	-- Every number below is a LOW/HIGH pair, linearly interpolated on LOG-
	-- luck between the two anchors and clamped to [EXTRAPOLATION_T_MIN,
	-- EXTRAPOLATION_T_MAX] beyond them. Retuning the curve's shape is
	-- changing these numbers, never rewriting SlimeRoll's formula. =====

	-- The two reference points everything else is anchored to. These are
	-- NOT measured the same way -- HIGH is an OBSERVED post-box-chaining
	-- luck value (see the written report), but the original LOW (25) was the
	-- reference game's raw, pre-chaining band value. Mixing a pre-chain point
	-- with a post-chain point stretched the whole curve wrong: a swing-tier-2
	-- player rolls at band 15 (luck 75), then a mystery box multiplies that
	-- by ~3x on average before the roll actually happens, landing around luck
	-- 220 -- well past where the old anchor's Common/Uncommon-heavy shape
	-- still applied, so nearly every tier-2 pull came out Rare or above.
	-- LOW is now 220 instead -- also a post-chain figure, matching HIGH's
	-- measurement basis, and specifically tier 2's typical post-box luck, so
	-- the anchor's own shape (see PEAK_OFFSET/SPREAD/SHAPE below -- roughly
	-- 10% Common / 71% Uncommon / 16% Rare / 3% Epic) lands exactly where
	-- tier-2 players actually roll instead of at a pre-chain value nobody's
	-- actual roll uses.
	SLIME_LUCK_ANCHOR_LOW = 220,
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
	-- from the window's bottom tier. CONSTANT at 1.0 across the whole curve
	-- (used to be 0.0 at low luck, peak AT the bottom tier -- that put the
	-- modal result one tier too low for tier 2's target (Uncommon, not
	-- Common) and left no room for a fading tier BELOW the peak). 1.0
	-- everywhere means the peak always sits one tier in from the window's
	-- bottom -- Uncommon at low luck, Mythic at high luck -- so every stage
	-- gets the SAME three-part shape: a fading tier below the peak, the peak
	-- itself, and a tail above.
	SLIME_PEAK_OFFSET_LOW = 1.0,
	SLIME_PEAK_OFFSET_HIGH = 1.0,
	-- Decay rate BELOW the peak (toward lower tiers) and ABOVE it (toward
	-- higher tiers) -- kept SEPARATE (not one symmetric spread) so the
	-- fading tier below the peak and the tail above it can shrink at
	-- different rates.
	--
	-- These LOW values (and SHAPE_LOW below) are constrained by a SECOND
	-- invariant, not just "hit these percentages at luck 220": expected tier
	-- value -- E[tier index], 1=Common..8=Divine, weighted by the roll's own
	-- probabilities -- must never DECREASE as luck increases. An earlier
	-- version of these three numbers (2.3 / 0.68 / 1.35) hit the luck-220
	-- target exactly but broke that invariant badly: SHAPE and SPREAD_UP
	-- interpolate continuously toward SHAPE_HIGH/SPREAD_UP_HIGH across the
	-- ENTIRE anchor range, independent of which discrete 4-tier window is
	-- currently active, and because the peak sits 1 tier below the window's
	-- top but 2 tiers below nothing (it's 1-in-from-the-bottom, so there are
	-- 2 tiers ABOVE it and only 1 below), rising concentration always drains
	-- the upper tail faster than it can be offset by the fading tier below --
	-- expected value fell continuously for the entire span BETWEEN two
	-- window-advance jumps, only recovering when the window itself slid to
	-- the next 4-tier range. That's why (with the old values) luck 600 rolled
	-- BETTER on average than luck 2000 despite being strictly lower luck --
	-- both sat inside the same Uncommon-Legendary window, and 2000 was
	-- further along that internal decay. Verified by brute force: every
	-- window segment showed the same pattern, dips of 2-7% relative.
	--
	-- The only way to make that dip EXACTLY zero is SHAPE_LOW/SPREAD_*_LOW
	-- literally equal to their _HIGH twins (concentration constant, only the
	-- window slides) -- but _HIGH can't move (it's the observed 120,000
	-- reference), so that would revert the LOW anchor to the exact same
	-- 15/78/6/1 spike shape as the high end, undoing this reshape entirely.
	-- Instead, these values were solved to make the residual dip NEGLIGIBLE
	-- (worst case ~0.002% relative, over 1000x smaller than the old 2-7%,
	-- and only in the extrapolated region below luck 220) while keeping a
	-- real three-tier spread at luck 220 (~10% Common / ~71% Uncommon / ~16%
	-- Rare / ~3% Epic tail) -- see the written report for the search and the
	-- full checkpoint table.
	SLIME_SPREAD_DOWN_LOW = 0.54,
	SLIME_SPREAD_DOWN_HIGH = 0.520,
	SLIME_SPREAD_UP_LOW = 0.69,
	SLIME_SPREAD_UP_HIGH = 0.292,
	-- The generalised-Gaussian shape exponent: weight ~ exp(-(distance/
	-- spread)^shape). LOW is 1.08 -- much closer to SHAPE_HIGH (0.764) than
	-- earlier attempts at this curve used, specifically because the gap
	-- between LOW and HIGH is what drives the expected-value dip described
	-- in SPREAD_DOWN_LOW's comment above: the closer LOW sits to HIGH, the
	-- smaller that dip, at the cost of a less dramatic shape change across
	-- the climb. HIGH (0.764, a sharp single spike with a longer tail --
	-- "concentrated in one tier with a thin rare tail") is unchanged --
	-- that's the observed high-luck reference, not part of this reshape.
	SLIME_SHAPE_LOW = 1.08,
	SLIME_SHAPE_HIGH = 0.764,
	-- How far past the two observed anchors (in the same log-luck t units,
	-- where the anchors are t=0 and t=1) the interpolation is allowed to
	-- extrapolate before clamping. MIN=-0.5 lets luck somewhat below 220
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
	-- Seconds between the server sending BoxResult(opened) and the slime
	-- itself appearing -- THE SECOND beat, long enough to read as a separate
	-- moment rather than a continuation of the same instant.
	--
	-- ALSO A BUDGET, not just a pause: the client's whole open animation runs
	-- inside this window -- a thrash into a burst, LaunchConfig's
	-- BOX_THRASH_SECONDS + BOX_OPEN_BURST_SECONDS = 0.55 -- so the box has
	-- destroyed itself before the reveal takes the screen. Lowering this, or
	-- raising either of those two, means re-checking that sum against it or
	-- the two beats start to overlap.
	REVEAL_BOX_TO_SLIME_DELAY_SECONDS = 0.6,
	-- Seconds the reveal panel REFUSES to be dismissed after it appears.
	--
	-- THE PANEL HAS NO LIFETIME OF ITS OWN ANY MORE. It used to auto-hide on a
	-- timer (this constant was that timer, 0.6), which dropped the player back
	-- onto an empty road still needing a second, separate click to return.
	-- Now it stays up indefinitely and ONE click dismisses it and returns them
	-- in the same action -- so the only thing left to time is the short window
	-- at the start where that click must NOT count.
	--
	-- WHAT THE LOCKOUT IS FOR: the player has just been clicking to press the
	-- box, possibly repeatedly. The reveal lands 0.6s after the box opens
	-- (REVEAL_BOX_TO_SLIME_DELAY_SECONDS above), which is well inside the
	-- window where another click may already be on its way down. Without this
	-- the reveal could be skipped before it was ever read -- the one thing the
	-- whole sequence exists to show. 0.5 is comfortably longer than the gap
	-- between two deliberate clicks and short enough that a player who wants
	-- to move on never notices it.
	--
	-- The in-panel "click to continue" prompt appears on exactly this timer
	-- too (see LaunchClient's SlimeRevealed handler), so the prompt is never
	-- on screen while the click it describes would be ignored.
	REVEAL_DISMISS_LOCKOUT_SECONDS = 0.5,

	-- ===== The reveal is a SLIME IN THE WORLD now, not a screen panel =====
	-- It is built with SlimeBuilder at the box's own position as the burst
	-- finishes, and the camera does not move for it -- see LaunchClient's
	-- reveal-slime block. These are its numbers.
	--
	-- Body width in studs, and THE lever for how big the reveal reads -- see
	-- the written report for why this was raised rather than the camera being
	-- pulled in.
	--
	-- The camera cannot come closer. It sits at 34 studs so the 7-stud box
	-- subtends 15.6 degrees of width, just inside the 17.4 the giant slime
	-- landmark subtends from a tier-1 landing -- which is the only reason the
	-- landmark shows past the box at all. Inside ~31 studs the box swallows it.
	-- And the camera may not move BETWEEN the box and the slime, so any
	-- distance chosen is a distance both have to live with. Growing the slime
	-- instead leaves the box's framing (and its backdrop) untouched and fixes
	-- the only thing that was wrong.
	--
	-- The mesh is ~0.677 as tall as it is wide, so 16 studs is ~10.8 tall:
	-- 22.7% of frame height against the box's 18.4%, up from 9 studs' 12.8%.
	-- The reward now reads bigger than the container it came out of, which is
	-- the right way round, and its hover spin is large enough on screen to be
	-- worth watching.
	--
	-- BOUNDED BY THE ROAD, not by taste, at the top end: the slime is centred
	-- where the box was, 8 studs up, so half its height plus the hover's own
	-- travel has to stay under that. 16 leaves 2.2 studs of clearance; 21
	-- would leave 0.5 and start clipping on the down-beat of the hover.
	SLIME_REVEAL_WIDTH_STUDS = 16,
	-- Seconds for the entrance: the slime rises through
	-- SLIME_REVEAL_RISE_STUDS while scaling up from nothing to full size.
	-- Short -- this is the punctuation on the burst, not a scene of its own,
	-- and the player is waiting to see WHICH slime they got.
	SLIME_REVEAL_ENTRANCE_SECONDS = 0.35,
	-- Studs below its resting height the slime starts the entrance at, so it
	-- travels UP into place rather than simply inflating. Roughly a third of
	-- its own height: enough to read as emerging, not so much that it appears
	-- to be climbing out of the road. Scaled up with the body above.
	SLIME_REVEAL_RISE_STUDS = 3.5,
	-- Studs above the slime's centre its name/tier billboard floats. Must clear
	-- the body's own half-height -- 5.4 studs at the width above -- or the text
	-- sits inside the mesh. 7.5 leaves a clean 2-stud gap above the crown, and
	-- has to be raised again if SLIME_REVEAL_WIDTH_STUDS ever is.
	SLIME_REVEAL_LABEL_HEIGHT_STUDS = 7.5,
	-- Billboard size in pixels. Fixed pixels rather than studs, same reasoning
	-- as the box's own luck readout: the text stays equally readable whatever
	-- the camera is doing. Tall enough for three stacked lines (tier, name,
	-- NEW/Duplicate).
	SLIME_REVEAL_LABEL_WIDTH_PIXELS = 300,
	SLIME_REVEAL_LABEL_HEIGHT_PIXELS = 108,
	-- Tier name text size (pixels): BASE at tier 1 (Common), +STEP per tier
	-- above it -- so Divine (tier 8) renders at BASE + 7*STEP. This, plus the
	-- tier's own colour, is what makes a Divine reveal "obviously a bigger
	-- deal" than a Common one using nothing but text and colour.
	SLIME_TIER_TEXT_SIZE_BASE = 28,
	SLIME_TIER_TEXT_SIZE_STEP = 6,
}

return SlimeConfig
