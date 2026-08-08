--!strict
-- Every treasure-chest constant lives here, and ONLY here -- same rule as
-- every other Config module in this project. The chest is what a PERFECT
-- tier-11 launch earns: that flight overshoots the road entirely and lands on
-- the giant slime's platform (see LaunchConfig.SWING_TIER_DISTANCE_SCALE's
-- tier-11 comment), where there is no mystery box, no box camera and no
-- burst -- the player simply arrives somewhere, walks to a chest, and opens
-- it. Deliberately unlike every other reward in the game, which plays a
-- sequence at you.
--
-- The chest's POSITION is not here. It is derived from the landmark's own
-- geometry in MapBuilder.server.luau, from the same RunwayGeometry/LuckCurve/
-- GiantSlimeConfig numbers that place the platform itself -- so moving the
-- landmark moves the chest with it. Only the size, the look, the interaction
-- and the roll live here.

export type TreasureConfig = {
	CHEST_SIZE: Vector3,
	CHEST_LID_HEIGHT_STUDS: number,
	CHEST_COLOR: Color3,
	CHEST_TRIM_COLOR: Color3,
	CHEST_MATERIAL: Enum.Material,
	CHEST_SETBACK_FRACTION: number,
	CHEST_PROMPT_DISTANCE_STUDS: number,
	CHEST_PROMPT_HOLD_SECONDS: number,
	CHEST_LID_OPEN_DEGREES: number,
	CHEST_ABANDON_SECONDS: number,
	CHEST_LID_RECLOSE_SECONDS: number,
	CHEST_REVEAL_WIDTH_STUDS: number,
	CHEST_REVEAL_RISE_STUDS: number,
	CHEST_REVEAL_HEIGHT_STUDS: number,
	CHEST_REVEAL_ENTRANCE_SECONDS: number,
	CHEST_REVEAL_DIVINE_ENTRANCE_SECONDS: number,
	CHEST_REVEAL_DIVINE_EXTRA_HEIGHT_STUDS: number,
	CHEST_REVEAL_DIVINE_LIGHT_RANGE_STUDS: number,
	CHEST_REVEAL_DIVINE_LIGHT_BRIGHTNESS: number,
	CHEST_DIVINE_CHANCE: number,
	CHEST_TIER_WEIGHT_RATIO: number,
}

local TreasureConfig: TreasureConfig = {
	-- ===== The chest itself, built from parts (a base box and a lid box) --
	-- no asset, no mesh. Sized against two very different references at once:
	-- the player walks to it from ~100 studs away, and it stands in front of a
	-- 1,050-stud slime. 14 x 10 x 10 reads as a clear silhouette at that walk
	-- distance without being a speck against the landmark behind it.
	CHEST_SIZE = Vector3.new(14, 10, 10),
	-- The lid's own slab height, taken off the top of CHEST_SIZE.Y -- so the
	-- base box is (CHEST_SIZE.Y - this) tall and the two together are exactly
	-- CHEST_SIZE.Y. Retuning the chest's height keeps the lid proportional
	-- without a second number needing to move.
	CHEST_LID_HEIGHT_STUDS = 3,
	-- Gold, and metal so it catches light against a Grass-material platform.
	CHEST_COLOR = Color3.fromRGB(212, 175, 55),
	-- Darker banding for the lid, so base and lid read as two pieces rather
	-- than one gold cube.
	CHEST_TRIM_COLOR = Color3.fromRGB(140, 110, 30),
	CHEST_MATERIAL = Enum.Material.Metal,

	-- Where the chest stands, as a fraction of the CLEAR STRIP between the
	-- platform's near edge and the giant slime's own near edge (200 studs at
	-- current landmark geometry), measured FROM THE SLIME back toward the
	-- player. 0.15 puts it ~30 studs in front of the body and ~70 studs ahead
	-- of where a perfect launch lands: far enough that reaching it is a walk
	-- and not a formality, close enough that it is unmistakably the thing you
	-- came for, and framed against the slime from the landing point.
	CHEST_SETBACK_FRACTION = 0.15,

	-- ===== Interaction: a ProximityPrompt, chosen over a ClickDetector or a
	-- Touched trigger. It is the only one of the three that shows its own
	-- on-screen affordance with a hold duration (so opening is deliberate,
	-- not something you walk into), has a native activation distance that is a
	-- real tunable rather than a per-frame distance check, and behaves
	-- identically on mouse, touch and gamepad with no per-input handling.
	CHEST_PROMPT_DISTANCE_STUDS = 18,
	-- A beat of commitment. Long enough that the open is a decision, short
	-- enough that it never feels like a chore.
	CHEST_PROMPT_HOLD_SECONDS = 1.0,
	-- How far the lid swings up when opened, hinged on its BACK edge (the far
	-- side from the approaching player) so it opens away and never occludes
	-- what is inside.
	CHEST_LID_OPEN_DEGREES = 100,

	-- ===== The safety net (see REPORT.md's failure modes). A chest landing is
	-- the ONE landing in this game that leaves the player unfrozen and free to
	-- walk, which means it is also the one landing with no automatic end. If
	-- they never open the chest -- idle, distracted, wandering -- this returns
	-- them to their swing exactly as a luckless landing already does, through
	-- the same moveToLaneReturn, so the destination cannot drift. Their
	-- pending chest is NOT consumed; it survives for a later visit.
	CHEST_ABANDON_SECONDS = 180,
	-- How long the lid stays open. SPLIT from CHEST_ABANDON_SECONDS, which it
	-- used to borrow -- two unrelated concerns sharing one number was a
	-- shortcut, and now that the reveal exists the lid wants its own timing:
	-- long enough to outlast the reveal comfortably, short enough that the
	-- next visitor finds a closed chest.
	CHEST_LID_RECLOSE_SECONDS = 45,

	-- ===== The reveal. ITS OWN SIZE AND TIMING, not SlimeConfig's
	-- SLIME_REVEAL_* set. Those are tuned for a slime viewed on a FRAMED
	-- camera at arm's length from a frozen player; this one is viewed from
	-- wherever a walking player happens to be standing, under a 1,050-stud
	-- landmark, with no camera take at all (see REPORT.md for why the camera
	-- is deliberately left alone). Bigger and slower is the whole difference.
	CHEST_REVEAL_WIDTH_STUDS = 26,
	-- How far below its rest pose the slime starts, rising as it scales up.
	CHEST_REVEAL_RISE_STUDS = 9,
	-- How high above the chest's own top face the slime settles -- enough that
	-- it clears the open lid and reads against the sky rather than against the
	-- chest.
	CHEST_REVEAL_HEIGHT_STUDS = 14,
	CHEST_REVEAL_ENTRANCE_SECONDS = 0.9,

	-- ===== DIVINE. Roughly one chest in five is Divine (see
	-- CHEST_DIVINE_CHANCE), so whatever marks it has to bear repetition --
	-- which rules out anything loud or long. Two changes, both to the SHAPE of
	-- the moment rather than its decoration:
	--   1. it takes longer and settles higher, because time is the strongest
	--      signal available in a game where everything else resolves fast;
	--   2. it lights the platform in its own tier colour.
	-- Deliberately NO screen effect -- no flash, no shake. That is the mystery
	-- box's idiom, and reusing it here would blur exactly the distinction that
	-- makes walking to this reward feel different from being played at.
	CHEST_REVEAL_DIVINE_ENTRANCE_SECONDS = 1.8,
	CHEST_REVEAL_DIVINE_EXTRA_HEIGHT_STUDS = 8,
	CHEST_REVEAL_DIVINE_LIGHT_RANGE_STUDS = 90,
	CHEST_REVEAL_DIVINE_LIGHT_BRIGHTNESS = 6,

	-- ===== The roll. ITS OWN TABLE, deliberately not SlimeRoll.
	-- distributionForLuck: that is a 4-tier sliding window whose whole point
	-- is that tiers outside the window are exactly zero, and a chest has to be
	-- able to award anything. Nothing here reads luck at all -- a chest
	-- landing earns no luck by construction (see LaunchServer's
	-- bandLuckForLandingZ "past" zone).
	--
	-- Flat 20% Divine off the top.
	CHEST_DIVINE_CHANCE = 0.20,
	-- The remaining 80% is spread across the other seven tiers geometrically,
	-- each tier weighted this much more than the one below it. 2.0 is the
	-- simplest shape that is unambiguously top-heavy and needs exactly one
	-- number: weights 1/2/4/8/16/32/64 give Common 0.63% through Secret
	-- 40.32%, so Secret-or-better is 60.3% and Mythic-or-better is 80.5%. A
	-- chest is never a disappointment, and the 0.63% Common tail is there so
	-- the outcome is still a roll rather than a payout.
	CHEST_TIER_WEIGHT_RATIO = 2.0,
}

return TreasureConfig
