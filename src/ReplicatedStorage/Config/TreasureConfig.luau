--!strict
-- Every treasure-chest constant lives here, and ONLY here -- same rule as
-- every other Config module in this project. The chest is what a PERFECT
-- top-tier launch earns: that flight overshoots the road entirely and lands on
-- the giant slime's platform (see LaunchConfig.SWING_TIER_DISTANCE_SCALE's
-- top-tier comment), where there is no mystery box, no box camera and no
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
	CHEST_HEIGHT_STUDS: number,
	CHEST_MATERIAL_COLORS: { [string]: Color3 },
	CHEST_MATERIAL_SURFACES: { [string]: Enum.Material },
	CHEST_SETBACK_FRACTION: number,
	CHEST_PROMPT_DISTANCE_STUDS: number,
	CHEST_PROMPT_HOLD_SECONDS: number,
	CHEST_LID_OPEN_DEGREES: number,
	CHEST_ABANDON_SECONDS: number,
	CHEST_LID_RECLOSE_SECONDS: number,
	CHEST_REVEAL_WIDTH_STUDS: number,
	CHEST_REVEAL_RISE_STUDS: number,
	CHEST_REVEAL_ENTRANCE_SECONDS: number,
	CHEST_REVEAL_EYE_HEIGHT_STUDS: number,
	CHEST_REVEAL_EYE_RISE_STUDS: number,
	CHEST_REVEAL_LID_CLEARANCE_STUDS: number,
	CHEST_REVEAL_LABEL_HEIGHT_STUDS: number,
	CHEST_REVEAL_DIVINE_ENTRANCE_SECONDS: number,
	CHEST_REVEAL_DIVINE_EXTRA_HEIGHT_STUDS: number,
	CHEST_REVEAL_DIVINE_LIGHT_RANGE_STUDS: number,
	CHEST_REVEAL_DIVINE_LIGHT_BRIGHTNESS: number,
	CHEST_DIVINE_CHANCE: number,
	CHEST_TIER_WEIGHT_RATIO: number,
}

local TreasureConfig: TreasureConfig = {
	-- ===== The chest is an IMPORTED MESH now (assets/Chest.rbxmx, assembled by
	-- ChestBuilder.luau) rather than two boxes -- see REPORT.md. The old
	-- CHEST_SIZE / CHEST_LID_HEIGHT_STUDS / CHEST_COLOR / CHEST_TRIM_COLOR /
	-- CHEST_MATERIAL are gone with the parts they described: the mesh brings its
	-- own proportions, and only its overall HEIGHT is a decision left to make.
	--
	-- ONE NUMBER SETS THE SIZE. ChestBuilder measures the template's own height
	-- at scale 1 and scales by targetHeight / unitHeight, so width and depth
	-- follow the mesh's own aspect and never need a second constant that could
	-- drift out of proportion with this one.
	--
	-- 12 studs against a ~5-stud character reads as 2.4x the player: big enough
	-- to be unmistakably the thing you walked 100 studs for, small enough to
	-- still read as an object you open rather than a building. It also has to
	-- survive standing in front of a 1,050-stud slime without becoming a speck,
	-- which is what pushed it above the old parts chest's 10.
	CHEST_HEIGHT_STUDS = 12,

	-- ===== PER-MATERIAL LOOK. The imported mesh arrives as twelve MeshParts
	-- named "<group>_<material>" (Base_gold, Lid_gem, ...) all sharing one flat
	-- import colour and Plastic; these two tables are what turn that back into
	-- a chest. Keyed by the material half of the part name, so a re-export that
	-- adds or renames a material only needs an entry here -- ChestBuilder looks
	-- every part up by name and leaves anything it cannot find alone rather
	-- than erroring.
	CHEST_MATERIAL_COLORS = {
		gold = Color3.fromRGB(237, 144, 6),
		deepgold = Color3.fromRGB(131, 59, 1),
		plank = Color3.fromRGB(82, 30, 9),
		plankdark = Color3.fromRGB(50, 17, 5),
		woodshade = Color3.fromRGB(15, 5, 2),
		iron = Color3.fromRGB(23, 27, 37),
		gem = Color3.fromRGB(13, 171, 255),
	},
	-- The surface each of those reads as. Deliberately conservative -- the
	-- chest is viewed from ~100 studs on approach and then from arm's length,
	-- and heavily-textured materials (DiamondPlate, Cobblestone) turn to noise
	-- at the first distance and to obvious tiling at the second.
	--   gold/deepgold/iron -> Metal. One material, three very different
	--     colours: the metals differ by hue (bright gold, dark gold, near-black
	--     iron) and adding a second metal material on top of that would be
	--     differentiating something already differentiated.
	--   plank/plankdark -> WoodPlanks. The visible outer boards, where a plank
	--     grain is exactly the read wanted.
	--   woodshade -> Wood. The inner/shadowed shell: plain grain rather than
	--     plank seams, so it does not fight the boards sitting over it.
	--   gem -> Neon. THE one deliberate choice here. It is the chest's focal
	--     point and the player first sees it from across the platform, where
	--     Glass (the obvious alternative) all but disappears -- it needs
	--     lighting and depth behind it to read at all, and there is sky behind
	--     this. Neon is lighting-independent, so the gem stays visible for the
	--     whole approach, which is the job it has.
	CHEST_MATERIAL_SURFACES = {
		gold = Enum.Material.Metal,
		deepgold = Enum.Material.Metal,
		plank = Enum.Material.WoodPlanks,
		plankdark = Enum.Material.WoodPlanks,
		woodshade = Enum.Material.Wood,
		iron = Enum.Material.Metal,
		gem = Enum.Material.Neon,
	},

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
	-- is deliberately left alone). SLOWER is still the difference; BIGGER is
	-- not, any more.
	--
	-- WAS 26, WHICH WAS SIZED FOR THE WRONG SCENE (see REPORT.md). At 26 wide
	-- the slime stood 17.6 studs tall -- one and a half times the whole chest
	-- -- so the thing that came out of the chest was larger than the chest, and
	-- getting it clear of a 12-stud lid put its billboard 28 studs above the
	-- player's eyes. 8 wide is 5.4 tall: about a player's own height, which
	-- reads as something you could pick up and carry, and against a 12.9-wide
	-- chest it is unmistakably "what was inside" rather than a second landmark.
	CHEST_REVEAL_WIDTH_STUDS = 8,
	-- How far below its rest pose the slime starts, rising as it scales up.
	-- Unchanged at 9, and it means something different now: the rest pose used
	-- to sit 14 studs clear of the lid, so starting 9 lower still began ABOVE
	-- the chest and the slime never appeared to come out of anything. From the
	-- derived rest height (see below) 9 studs down is inside the chest's own
	-- envelope, so the entrance now genuinely starts within the box it is
	-- emerging from.
	CHEST_REVEAL_RISE_STUDS = 9,
	CHEST_REVEAL_ENTRANCE_SECONDS = 0.9,

	-- ===== WHERE THE SLIME SETTLES, and the whole of it is derived -- see
	-- LaunchRewardScene's showSlimeReveal. The old CHEST_REVEAL_HEIGHT_STUDS
	-- (a flat 14 studs above the lid) is gone: it was a fixed offset from a
	-- chest that has since tripled in height, and it took no account of how
	-- tall the slime itself is or of where the player's eyes are.
	--
	-- THE RULE: settle as close to eye level as the chest allows, but never
	-- inside the lid. In code that is
	--
	--   restY = max(groundY + EYE_HEIGHT + EYE_RISE,            -- where we want it
	--               lidTopY + LID_CLEARANCE + slimeHalfHeight)  -- where it must clear
	--
	-- with the slime's half-height MEASURED off the model that was just built,
	-- so it tracks CHEST_REVEAL_WIDTH_STUDS, and lidTopY measured off the
	-- chest, so it tracks CHEST_HEIGHT_STUDS. Shrink the chest and the first
	-- term takes over and the slime settles at eye level; grow it and the
	-- second does, and the slime rides on top of the lid rather than sinking
	-- into it. Neither number is a hardcoded height.
	--
	-- At today's numbers the chest wins by 6.5 studs -- 12 + 0.75 + 2.71 =
	-- 15.46 against 9 -- which is the honest answer to "how much of this is
	-- the chest's fault": all of it. A 12-stud chest cannot have anything sit
	-- on top of it that a player standing next to it does not look up at.
	--
	-- A STANDING PLAYER'S EYES. R15 default: HipHeight 2 plus a 2-stud root
	-- makes the root centre 3, and the head sits about 5 up. Named here rather
	-- than measured off a live character because the reveal has to be placed
	-- before anyone is necessarily standing anywhere near it.
	CHEST_REVEAL_EYE_HEIGHT_STUDS = 5,
	-- How far ABOVE eye level the slime would like to sit -- enough to read as
	-- presented rather than as level with the horizon, not enough to be a
	-- look-up on its own.
	CHEST_REVEAL_EYE_RISE_STUDS = 4,
	-- The gap between the closed lid's top face and the bottom of the hovering
	-- slime. Small on purpose: this is the visual thread back to the chest, and
	-- the further it floats the more it reads as a separate object that
	-- happened to appear nearby.
	CHEST_REVEAL_LID_CLEARANCE_STUDS = 0.75,
	-- The name/tier/NEW billboard's offset above the slime, for the CHEST path
	-- only -- SlimeConfig.SLIME_REVEAL_LABEL_HEIGHT_STUDS (7.5) still governs
	-- the box, which is looked at on a framed camera where nothing is competing
	-- for vertical room. Here every stud above the slime is another stud the
	-- player has to look up past a 12-stud chest, and the billboard is the part
	-- that was going off screen first.
	CHEST_REVEAL_LABEL_HEIGHT_STUDS = 3.5,

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
	-- WAS 8, which is now most of the frame. The "settles higher" signal is
	-- kept -- it is one of the two things that mark a Divine -- but 2 studs
	-- against a 5.4-stud slime is still a clearly higher hover, and 8 would
	-- have put the billboard straight back out of view and undone the fix above
	-- for one chest in five.
	CHEST_REVEAL_DIVINE_EXTRA_HEIGHT_STUDS = 2,
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
