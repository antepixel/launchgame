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
	SLIME_NAME_BY_TIER: { { string } },
	SLIME_COLOR_BY_TIER: { { Color3 } },
	SLIME_INCOME_BY_TIER: { { number } },
	SLIME_SKIN_BY_TIER: { [number]: { [number]: string } },
	SLIME_TIER_WEIGHT_RATIO: { number },
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
	SLIME_SPREAD_FLOOR: number,
	SLIME_SHAPE_FLOOR: number,
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
	-- ===== THE NAMES. One per slime, same [tier][indexInTier] indexing as
	-- COLOR_BY_TIER and INCOME_BY_TIER, and SlimeData asserts the lengths
	-- against SLIME_TIER_COUNTS the same way.
	--
	-- AUTHORED, and this table is why the generator no longer builds a name.
	-- SlimeData used to format "%s Slime %d" from the tier name and the index,
	-- which is the right call for a placeholder and the wrong one for a
	-- collection game: the names are half the appeal and a formula cannot
	-- write them.
	--
	-- TWO THINGS PICK EACH NAME. The TIER sets the register -- Common is
	-- kitchen-and-garden, Rare is gemstones, Mythic is monsters, Divine is
	-- cosmic -- and the POSITION picks the hue word, because position i is
	-- bound to colour i for good (see SLIME_COLOR_BY_TIER below: every tier's
	-- slime 1 is green, 2 red, 3 blue, 4 yellow, 5 purple, 6 orange). So a
	-- name must fit both, and moving a colour means renaming its slime.
	--
	-- KEPT SHORT ON PURPOSE -- 12 characters or under. These render on the
	-- pad nametag (PlayerProfile's "%s (Lv %d)") and in the inventory row
	-- (InventoryClient's "Slot %d: %s -- Lv %d -- %s"), and both already
	-- carry more than the name.
	--
	-- LEGENDARY IS NAMED FOR ITS DESIGN, NOT ITS HUE, and it is the one row
	-- that breaks the rule above. Legendary slimes carry a painted sheet, and
	-- MeshPart.Color does not tint a textured MeshPart (measured -- see
	-- dev/out/u2u3.log), so the palette colour is INVISIBLE on them. Naming
	-- Legendary 1 "Moss" for its green would name it after the one property
	-- of it nobody can see. It is the tiger, so it is Tigerback.
	--
	--   THE DESIGN-TO-POSITION MAPPING IS AUTHORED HERE AND NOWHERE ELSE.
	--   It is a DECISION, not a discovery -- there was no such mapping to
	--   find. BUILD_LEGENDARY_PAINT's DESIGNS array is authoring order;
	--   BUILD_LEGENDARY's own HUES list runs blue/green/red/... against this
	--   file's green/red/blue/..., so it is not a mapping either; and the
	--   painted designs carry their own two colours (tiger is tangerine and
	--   deep indigo) rather than a palette hue, so nothing ties a design to a
	--   slot. This table and SLIME_SKIN_BY_TIER below are the mapping, and
	--   they must agree: position i's name and position i's sheet are the
	--   same design. Only tiger is uploaded today; the other five names are
	--   already in place so that wiring a sheet is one line and no rename.
	SLIME_NAME_BY_TIER = {
		-- green        red           blue          yellow        purple        orange
		{ "Moss", "Tomato", "Puddle", "Butter", "Grape", "Apricot" }, -- Common
		{ "Fern", "Cinder", "Drizzle", "Honey", "Thistle", "Rust" }, -- Uncommon
		{ "Jade", "Garnet", "Sapphire", "Amber", "Amethyst", "Coral" }, -- Rare
		{ "Wildvine", "Wildfire", "Riptide", "Sunflare", "Nightshade", "Emberfall" }, -- Epic
		-- Legendary: tiger, koi, sweeps, harlequin, split, cow -- the designs,
		-- in the order this file hereby assigns them to positions 1..6.
		{ "Tigerback", "Koi Royal", "Pinwheel", "Harlequin", "Highsplit", "Dappleback" }, -- Legendary
		{ "Basilisk", "Phoenix", "Leviathan", "Griffin", "Wyvern", "Chimera" }, -- Mythic
		-- Secret (21): the six hues above, then the 15 extra ones in
		-- SLIME_COLOR_BY_TIER's own order -- teal, magenta, lime, indigo, sky
		-- cyan, maroon, olive, coral, slate blue, mint, plum, steel blue,
		-- amber brown, rose, chartreuse.
		{
			"Mossglitch", "Redshift", "Deepsignal", "Flicker", "Voidbloom", "Hexflare",
			"Tealwake", "Neonhush", "Limeglow", "Deepnull", "Skyghost", "Duskblood",
			"Olivedrift", "Coralwisp", "Slatewisp", "Mintghost", "Plumshade", "Steelhush",
			"Amberdust", "Roseglitch", "Acidbloom",
		}, -- Secret
		-- Divine (8): the six, then teal and magenta.
		{ "Aurora", "Supernova", "Empyrean", "Halo", "Eventide", "Helion", "Aether", "Zenith" }, -- Divine
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
		-- Divine: a 1.50x geometric ladder from 50,000, rounded to 3 significant
		-- figures -- see the block above this table for why it was steepened from
		-- the old 1.32x (50,000..350,000, a 7x spread) to 17x, and why that lands
		-- as a jackpot rather than as inflation only because
		-- SLIME_TIER_WEIGHT_RATIO makes the top of it rare.
		{ 50000, 75000, 113000, 169000, 253000, 380000, 570000, 854000 }, -- Divine
	},

	-- ===== PAINTED SKINS. A baked 512x512 sheet bound to the body MeshPart's
	-- TextureID, keyed [tier][indexInTier] -- the SAME 1-8 tier indexing and
	-- the same within-tier position as COLOR_BY_TIER and INCOME_BY_TIER.
	--
	-- SPARSE ON PURPOSE, unlike every other table above. Those are dense
	-- because every slime HAS a colour and an income; almost no slime has a
	-- skin, and writing 65 empty strings to say so would be 65 places to make
	-- a typo in service of a length check. SlimeData validates this one by
	-- CONTENT instead -- every key must land inside SLIME_TIER_COUNTS and
	-- every value must be a well-formed rbxassetid:// -- which catches the
	-- failures a length check could not (a wrong index, a malformed id).
	--
	-- WHY THE PER-SLIME COLOUR STILL APPLIES UNDERNEATH. MeshPart.Color DOES
	-- NOT TINT A TEXTURED MeshPart -- measured on both the EditableImage and
	-- the asset path, in edit mode and on a real server (dev/out/u2u3.log).
	-- So SlimeBuilder still writes body.Color exactly as it always did, and a
	-- painted slime simply shows its two authored sheet colours instead. That
	-- is correct by itself: a painted Legendary is its design, not its palette
	-- entry multiplied into it. Nothing here has to switch the colour off.
	--
	-- THE UPLOAD IS LOSSLESS, so the sheet on the body is the bake byte for
	-- byte -- 0 class flips, 0 texel error, checked against dev/out/bake/
	-- tiger.png (dev/legendary/encode_probe.py, dev/out/u2u3.log). The
	-- narrowest tiger bar stays 19.6 px at the base framing against an 8 px
	-- floor.
	--
	-- ONE OF SIX TODAY. dev/legendary/BUILD_LEGENDARY_PAINT.luau authors six
	-- Legendary designs -- tiger, koi, sweeps, harlequin, split, cow -- and
	-- all six are baked to dev/out/bake/. Only tiger has been uploaded, so
	-- only tiger is wired; the other five want an asset id and one line each.
	SLIME_SKIN_BY_TIER = {
		-- Legendary (tier 5), first slime in the tier.
		[5] = { [1] = "rbxassetid://104689541793385" }, -- tiger
	},

	-- ===== HOW MASS SPLITS *WITHIN* ONE TIER. One entry per tier, same
	-- 1-8 indexing as every other array above.
	--
	-- Slime i of a tier of n (1-indexed, ASCENDING income -- the same order
	-- SLIME_INCOME_BY_TIER is written in) gets weight `ratio ^ -(i - 1)`,
	-- normalised across that tier. So a ratio of 1.0 is exactly uniform (every
	-- slime equally likely, which is what the game did everywhere before this
	-- table existed) and a ratio above 1.0 makes each step up the tier's own
	-- income ladder that much rarer than the step below it.
	--
	-- THIS REDISTRIBUTES WITHIN A TIER AND NEVER BETWEEN TIERS. The tier's
	-- total mass is whatever SlimeRoll's window/Gaussian gave it, untouched --
	-- P(Divine) is identical before and after, and only the split inside
	-- Divine moves. Verified to 1e-12 (see REPORT.md); a change here can make
	-- the best slime in a tier rarer, never the tier itself.
	--
	-- READ IN TWO PLACES, both through SlimeRoll.pickSlimeInTier: the mystery
	-- box's roll (SlimeRoll.rollSlime) and the treasure chest's own roll
	-- (LaunchServer's rollChestSlime). The chest picks its TIER from its own
	-- table -- CHEST_DIVINE_CHANCE and CHEST_TIER_WEIGHT_RATIO, untouched by
	-- this -- and then splits within that tier by the same rule, so a Divine
	-- from a chest and a Divine from a box are the same lottery.
	--
	-- WHY ONLY DIVINE IS NON-UNIFORM. Divine is the one tier whose members
	-- differ by more than an order of magnitude ($50K to $854K, 17x), so a
	-- flat pick inside it makes the top Divine as common as the bottom one and
	-- the tier's expected value sits well above what "a Divine" feels like.
	-- 1.40 pulls the top entry to ~3% of the tier's own mass (from a flat
	-- 12.5%) while leaving P(Divine) alone, which is what makes the steepened
	-- income ladder land as a rare jackpot rather than as inflation. Every
	-- other tier's members are within ~2x of each other, where a flat pick is
	-- the honest model and this table is a no-op.
	SLIME_TIER_WEIGHT_RATIO = { 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.40 },

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
	-- TRADE-OFF, RECORDED DELIBERATELY: the luck VALUES of both anchors are
	-- unchanged, but the observed SHAPE at this HIGH one is no longer
	-- reproduced. The reference game's 120,000 distribution (~15% Legendary /
	-- 78% Mythic / 6% Secret / 1% Divine) is a distribution whose expected
	-- INCOME is lower than that of the luck below it, because it concentrates
	-- as luck rises. Reproducing it and holding the monotonicity invariant
	-- (see SLIME_SPREAD_DOWN_LOW) are mutually exclusive, so the invariant
	-- wins and this shape is now ~8.7% / 71.8% / 15.2% / 4.5%.
	--
	-- The visible consequence is that HIGH-LUCK ROLLS ARE WORTH ABOUT 2.8x
	-- MORE than they were: expected income at the top of the curve goes from
	-- ~$3.07K to ~$8.69K per slot. That is a real economy change and the
	-- swing prices above tier 7 were not retuned for it -- if the late game
	-- now inflates, this is the number that did it, not the upgrade curve.
	--
	-- ===== RAISED TO 1,000,000 BY THE LADDER RENUMBER AND PUT BACK. Recorded
	-- because the mistake is an easy one to make twice.
	--
	-- The reasoning for raising it was sound as far as it went: the mystery box
	-- multiplies luck by 2^D with no ceiling (LaunchServer's onBoxPress), but t
	-- clamps at SLIME_EXTRAPOLATION_T_MAX, so every doubling past the clamp
	-- buys exactly nothing -- which is why band 68's box measured 1.01x. What
	-- it missed is that THIS CONSTANT DOES TWO JOBS AT ONCE. It sets where t
	-- clamps, and it sets the RATE at which t advances with luck, because
	--     t = ln(luck / 220) / ln(HIGH / 220)
	-- Raising HIGH stretches the denominator, so every luck value maps to a
	-- smaller t and every window transition slides DOWN the road. At 1,000,000
	-- the t = 0.875 transition needed luck 349,000 against a top band of
	-- 100,000: the Legendary-Divine window stopped being reachable by landing
	-- at all, band 68's pre-box expected income fell from $8.87K to $877, and
	-- tiers 1-2 lost their box value to the same dilution. Measured, see
	-- REPORT.md.
	--
	-- THE KNOB FOR BOX HEADROOM IS SLIME_EXTRAPOLATION_T_MAX, not this. Raising
	-- T_MAX clamps t later without touching the luck-to-t mapping, so the road
	-- keeps the shape three measurement passes validated and only the
	-- doubling chain gains anything. This value is back at its measured
	-- reference and should stay there: it is an OBSERVED anchor (the reference
	-- game's 120,000 distribution), not a free parameter.
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
	-- ===== THE MONOTONICITY INVARIANT, and the one thing these six numbers
	-- exist to satisfy: EXPECTED INCOME PER ROLL MUST NEVER DECREASE AS LUCK
	-- INCREASES. More luck can never be worth less. A player buys a swing
	-- tier to reach a further band, and a further band must not roll cheaper
	-- slimes than the one behind it.
	--
	-- THIS INVARIANT USED TO BE STATED AGAINST THE WRONG QUANTITY, and that
	-- is what broke it. The previous version of this comment protected
	-- E[TIER INDEX] -- the probability-weighted mean of 1=Common..8=Divine --
	-- and reported the residual dip as "~0.002% relative", which is true of a
	-- single step along the curve. Two things were wrong with it:
	--
	--   1. TIER INDEX IS LINEAR; INCOME IS GEOMETRIC. Tier mean incomes climb
	--      2.4x, 2.5x, 3.2x, 3.1x, 8.9x and 14.1x per step (see
	--      SLIME_INCOME_BY_TIER). Losing a point of probability off the top of
	--      the window and gaining it at the peak barely moves an index average
	--      and moves an income average enormously -- in the top two windows the
	--      +2 tail carries roughly HALF of all expected income at 1-2%
	--      probability. Measured: over the Legendary-Divine window E[index]
	--      falls 0.39% while E[income] falls 12.71%, a ~32x understatement.
	--   2. THE DIP IS CUMULATIVE, NOT PER-STEP. A 0.002% drop between adjacent
	--      luck values compounds across a whole window segment. Measured on the
	--      old constants, EVERY segment declined end to end: -12.43%, -6.00%,
	--      -7.63%, -11.73%, -12.71% of expected income. The per-step figure was
	--      real and the conclusion drawn from it was not.
	--
	-- The consequence in play: five of the ten swing-tier purchases LOWERED
	-- expected income -- tiers 2, 4, 7, 9 and 10, with tier 9 down 11.3%. The
	-- player paid and got less.
	--
	-- ===== WHAT CHANGED, AND WHAT DID NOT =====
	-- The three _LOW values are UNTOUCHED. The luck-220 shape is measured data
	-- (see SLIME_LUCK_ANCHOR_LOW) and it still reproduces exactly: 10.13%
	-- Common / 70.91% Uncommon / 15.93% Rare / 3.02% Epic. Early game is
	-- bit-for-bit what it was. Buying monotonicity by making low luck WORSE
	-- was available and was rejected -- an early solve did exactly that
	-- (Common 10% -> 20%) and it is the wrong direction for a player.
	--
	-- The three _HIGH values moved, and this is the real cost of the fix:
	-- SPREAD_UP_HIGH 0.292 -> 0.640, SPREAD_DOWN_HIGH 0.520 -> 0.378,
	-- SHAPE_HIGH 0.764 -> 0.900. The upper tail now WIDENS with luck instead
	-- of narrowing. That is not a tuning nudge, it is a sign flip, and it is
	-- forced: within a fixed window the only term that can raise expected
	-- income is the weight on the tiers above the peak, so if concentration
	-- rises with luck then expected income falls with luck, always. The two
	-- cannot both hold. See the trade-off note under SLIME_LUCK_ANCHOR_HIGH.
	--
	-- Solved as a constrained fit (least squares against both anchor shapes,
	-- subject to: no decrease in expected income anywhere; the +2 tail inside
	-- the stated 1-5%; every swing tier gaining at least 1%). Verified over
	-- 1,000,000 log-spaced luck values from 1e-3 to 1e10: ZERO decreasing
	-- steps, +2 tail range 2.49%-4.47%.
	SLIME_SPREAD_DOWN_LOW = 0.54,
	SLIME_SPREAD_DOWN_HIGH = 0.378,
	SLIME_SPREAD_UP_LOW = 0.69,
	SLIME_SPREAD_UP_HIGH = 0.640,
	-- The generalised-Gaussian shape exponent: weight ~ exp(-(distance/
	-- spread)^shape). LOW is 1.08, unchanged, and holds the observed luck-220
	-- shape. HIGH is 0.900 (was 0.764): a lower exponent lifts every off-peak
	-- weight relative to the peak, so this pulls in the same direction as
	-- SPREAD_UP_HIGH above -- toward a window that stays genuinely four tiers
	-- wide at high luck rather than collapsing onto its peak. Both are part of
	-- the same solve; neither is meaningful alone.
	SLIME_SHAPE_LOW = 1.08,
	SLIME_SHAPE_HIGH = 0.900,

	-- ===== SAFETY FLOORS on the three interpolated values above. Purely
	-- defensive: at the current constants and the current
	-- SLIME_EXTRAPOLATION_T_MAX, NEITHER FLOOR IS EVER REACHED, and applying
	-- them changes no distribution anywhere (verified: zero deviation over
	-- 2,000,000 log-spaced luck values from 1e-4 to 1e12).
	--
	-- WHAT THEY PREVENT. All six LOW/HIGH constants are interpolated with a
	-- plain lerp, which is unbounded: spreadDown reaches zero at t = 3.333,
	-- shape at t = 6.0, spreadUp at t = 13.8. Past spreadDown's crossing the
	-- spread is NEGATIVE, so (|dist| / spread) is negative, a fractional power
	-- of a negative number is NaN, and every weight in the window becomes NaN.
	-- SlimeRoll.rollTier's cumulative comparison then never fires -- every
	-- `roll <= cumulative` test against NaN is false -- and it falls through to
	-- its floating-point safety net, `return #weights`, which is the LAST tier.
	-- The failure is therefore silent, and it is maximally generous: every roll
	-- returns Divine.
	--
	-- THIS IS LATENT, NOT LIVE. T_MAX = 1.0 clamps t before any crossing, so
	-- the region is unreachable today and no player can hit it -- confirmed by
	-- scanning the live module over the same 2,000,000 values and finding no
	-- NaN. What these floors buy is that T_MAX stops being load-bearing for
	-- SAFETY as well as for design: raising or removing it becomes a decision
	-- about the curve's shape only, and can no longer reintroduce a
	-- guaranteed-Divine failure by accident.
	--
	-- CHOSEN WELL BELOW ANYTHING IN NORMAL PLAY. Over the whole allowed t
	-- range the minimum values actually reached are spreadDown 0.378,
	-- spreadUp 0.640 (both at t = 1.0) and shape 0.900 (also at t = 1.0). The
	-- floors sit 7.6x, 12.8x and 9.0x below those. They are also above the
	-- point where the shape degenerates rather than merely at zero: a spread
	-- of 0.05 already puts the nearest off-peak tier at exp(-(1/0.05)^0.1) ~=
	-- 0.22 of the peak, so a floored window is still a window rather than a
	-- single spike, and a shape of 0.10 keeps the exponent positive so weights
	-- still decay with distance instead of inverting.
	SLIME_SPREAD_FLOOR = 0.05,
	SLIME_SHAPE_FLOOR = 0.10,
	-- How far past the two observed anchors (in the same log-luck t units,
	-- where the anchors are t=0 and t=1) the interpolation is allowed to
	-- extrapolate before clamping. MIN=-0.5 lets luck somewhat below 220
	-- still produce a smoothly-extrapolated (not wildly distorted)
	-- distribution -- verified safe (SHAPE stays comfortably positive down
	-- to well past this bound).
	--
	-- ===== MAX=1.35, RAISED FROM 1.0, AND THIS IS THE ONLY KNOB FOR BOX
	-- HEADROOM. It moves where t stops, and nothing else: the luck-to-t
	-- mapping is a function of the two ANCHORS, so raising this cannot slide a
	-- window transition, cannot change what any band on the road rolls, and
	-- cannot touch the four transitions three measurement passes validated.
	-- The top band (luck 100,000) sits at t = 0.9711, under 1.0, so the road is
	-- untouched by construction. Everything above 1.0 is reachable only by the
	-- box's doubling chain -- from band 68 (luck 75,000, t = 0.9254) the
	-- doublings land at t = 1.0354 / 1.1454 / 1.2554 / 1.3654, so four of them
	-- now move the distribution where one used to.
	--
	-- WHY 1.35 AND WHAT ACTUALLY BOUNDS IT. The binding quantity is
	-- spreadDown: it lerps 0.54 -> 0.378, so it reaches SLIME_SPREAD_FLOOR
	-- (0.05) at t = 3.0247 and the floor engages from there. spreadUp reaches
	-- its floor at t = 12.80 and shape reaches SLIME_SHAPE_FLOOR at t = 5.44,
	-- both far above. peak cannot go out of range at any t at all --
	-- SLIME_PEAK_OFFSET_LOW and _HIGH are both 1.0, so peakOffset is constant
	-- and peak is always windowStart + 1, one tier inside the window. So the
	-- largest safe value is 3.02; 1.35 is chosen well inside it because the
	-- returns are small and flatten out (P(Divine) at the top of the window
	-- goes 4.47% at t = 1.0 to 5.12% at t = 1.35), not because anything breaks
	-- above it. Measured in REPORT.md.
	--
	-- CORRECTING THE CLAIM THIS BLOCK USED TO MAKE: it said the shape exponent
	-- "crosses ZERO at t=1.21 and goes NEGATIVE beyond that". Against the
	-- current constants that is simply false -- shape lerps 1.08 -> 0.90, so it
	-- crosses zero at t = 6.0 and hits its floor at 5.44. The 1.21 predates the
	-- retune that set these values and was the stated reason T_MAX could not be
	-- raised; anyone trusting it would have believed this change unsafe.
	--
	-- WINDOW SATURATION IS STILL REAL, and it is what caps the gain: windowStart
	-- reaches its ceiling of 5 at t = 0.875 and cannot advance further (8 tiers,
	-- a 4-wide window -- there is nowhere above Legendary-Divine to go). Past
	-- that point extra t only sharpens the shape WITHIN the top window, which is
	-- worth about 10% of expected income, not a new tier of reward. Raising this
	-- number further does not change that; more window would need more tiers.
	SLIME_EXTRAPOLATION_T_MIN = -0.5,
	SLIME_EXTRAPOLATION_T_MAX = 1.35,

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
