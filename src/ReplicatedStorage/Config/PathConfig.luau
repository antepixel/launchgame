--!strict
-- Every connective-path constant lives here, and ONLY here -- the paved
-- links between a lane's swing and its base, and the walkway tying every
-- lane together. Built at runtime by MapBuilder.server.luau, same
-- "generated, not hand-authored" reasoning as RunwayBuilder -- only the
-- Baseplate itself belongs in default.project.json.
--
-- Distinct from BaseConfig's own BASE_PATH_* (the short central path
-- inside one player's plot) even though they share a colour -- these three
-- are MAP-level connectors, not owned by any one base.
--
-- WALKWAY MOVED FROM BEHIND THE BASES TO BETWEEN THE SWINGS AND THE BASES
-- (see the written report): it used to sit at the FAR back of the map
-- (Z = 174, past every plot), so returning to a swing and then reaching a
-- shop meant walking the full ~200-stud length of your own base first. It
-- now sits at Z = 76, right after the swing and before the plot, so
-- swing -> shop -> base all fall on one line, in that order, with nothing
-- to backtrack past.
--
-- Z = 76, NOT 62 (see the written report -- return position margin pass):
-- an earlier pass put it at 62, which put its own front edge (53) only 1
-- stud past the player's post-flight return position (LaunchConfig.
-- SWING_PIVOT_Z + SWING_RETURN_CLEARANCE_STUDS = 52) and left the top tier's own
-- seat sweep (up to Z ~50.6) almost touching it too. Moved to 76 instead of
-- touching SWING_RETURN_CLEARANCE_STUDS -- that constant is tuned against
-- the mount radius (see its own comment in LaunchConfig.luau) and has
-- nothing to do with the walkway. 76 puts the walkway's front edge at 67:
-- 15 studs clear of the return position, 16 clear of the top tier's furthest
-- seat sweep.
--
-- ALL THREE PARTS NOW MEET EDGE-TO-EDGE, NOT CENTER-OVERLAPPING (see the
-- written report -- z-fighting pass 2): an earlier pass had the angled link
-- and spur run all the way to the walkway's own CENTER, deliberately
-- overlapping it, with the walkway itself dropped to a lower Y offset so
-- the three didn't share an exact top height across that overlap. That
-- still read as visibly wrong in practice. This pass takes the other option
-- instead: the angled link now stops exactly at the walkway's own NEAR edge
-- (67) and the spur now starts exactly at its own FAR edge (85), so there
-- is no Z range where more than one of the three parts exists at all -- and
-- all three sit at the SAME Y_OFFSET (0.15) again, forming one continuous
-- flat surface with no seam to fight over. The knock-on effect is BOTH
-- connectors changing role: the angled link now runs from the swing to the
-- WALKWAY (not to the base), and the spur now runs from the WALKWAY back to
-- the plot (the reverse of its old "plot to walkway" direction). The PLOT
-- itself does NOT move for any of this -- only the spur's own length
-- changes to still reach it. =====

export type PathConfig = {
	APPROACH_LINK_START_Z: number,
	APPROACH_LINK_END_Z: number,
	APPROACH_LINK_WIDTH: number,
	APPROACH_LINK_THICKNESS: number,
	APPROACH_LINK_Y_OFFSET: number,

	SPUR_SIZE: Vector3,
	SPUR_Y_OFFSET: number,
	SPUR_Z: number,

	BACK_WALKWAY_SIZE: Vector3,
	BACK_WALKWAY_Y_OFFSET: number,
	BACK_WALKWAY_Z: number,
	BELT_SPEED_STUDS_PER_SECOND: number,
	BELT_COLOR: Color3,
	BELT_MATERIAL: Enum.Material,
	BELT_RIDGE_TEXTURE_ASSET_ID: string,
	BELT_RIDGE_TILE_STUDS: number,
	BELT_RIDGE_SCROLL_SIGN: number,

	PATH_COLOR: Color3,
	PATH_MATERIAL: Enum.Material,
}

-- For the belt's own width only -- it ends a fixed inset short of the shop
-- it serves, and the shops are themselves derived from the lane grid (see
-- StallConfig.STALL_X_POSITIONS). Reading LaneConfig here is what lets the
-- belt follow a pitch change without an edit. No cycle: LaneConfig requires
-- only LaunchConfig, and neither requires this file.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LaneConfig = require(ReplicatedStorage.Config.LaneConfig)

-- Studs the belt stops SHORT of each shop's own centre. The shop straddles
-- the belt's end rather than sitting past it, which is what makes stepping
-- off the belt at the counter read as arriving rather than as running out of
-- floor. 2 is the relationship the original hand-placed pair happened to
-- have (belt half 220 against shops at 222) -- preserved deliberately, since
-- it was the one part of that arrangement that looked right.
local BELT_SHOP_INSET_STUDS = 2
local BELT_HALF_WIDTH = LaneConfig.laneCenterX(LaneConfig.LANE_COUNT) - BELT_SHOP_INSET_STUDS

local PathConfig: PathConfig = {
	-- ===== Approach link: one per lane, from [swingX, .., START_Z] to
	-- [baseX, .., END_Z] -- swingX/baseX come from LaneConfig at build time,
	-- never stored here. Oriented along the line between the two points
	-- (see MapBuilder), so WIDTH is the only crosswise dimension needed;
	-- length is computed at build time, never a stored constant.
	--
	-- RENAMED FROM ANGLED_LINK_* -- IT IS NO LONGER ANGLED (see REPORT.md).
	-- swingX and baseX are the same number now that plots sit on the swing
	-- lanes' own pitch, so this runs dead straight down Z, from the swing to
	-- the walkway. The old name described the one thing about it that this
	-- pass deleted, and a name that lies costs more later than the rename
	-- costs now. Nothing about the geometry below changed -- it is the two X
	-- values either end that stopped disagreeing.
	--
	-- END_Z stops exactly at the walkway's own NEAR edge (BACK_WALKWAY_Z -
	-- BACK_WALKWAY_SIZE.Z / 2 = 76 - 9 = 67) -- touched, not overlapped, so
	-- the link and the walkway occupy disjoint Z ranges and can never share
	-- a Z where both exist at the same height (see this file's own header).
	-- That edge is now also where the STATIC surface ends and the moving
	-- conveyor begins, which makes the disjointness load-bearing rather than
	-- merely tidy: a player steps off the belt onto a part that is standing
	-- still, with no overlap where both could claim them.
	-- =====
	APPROACH_LINK_START_Z = 34,
	APPROACH_LINK_END_Z = 67,
	APPROACH_LINK_WIDTH = 9,
	APPROACH_LINK_THICKNESS = 0.3,
	-- Sits flush on the ground (Y offset = thickness/2), added to groundY at
	-- build time -- never hardcoded, same reasoning as BaseGeometry. Same
	-- value as the walkway and the spur below -- all three form one
	-- continuous flat surface now, not a stack of overlapping ones.
	APPROACH_LINK_Y_OFFSET = 0.15,

	-- ===== Spur: one per lane, bridging the WALKWAY to that lane's own
	-- plot, at baseX (from LaneConfig, not stored here) -- the reverse
	-- direction from before (used to run FROM the plot's own back edge TO
	-- the walkway; now runs FROM the walkway TO the plot's own front edge,
	-- since the walkway is reached first now). Starts exactly at the
	-- walkway's own FAR edge (BACK_WALKWAY_Z + BACK_WALKWAY_SIZE.Z / 2 = 76
	-- + 9 = 85 -- touched, not overlapped, same reasoning as the angled
	-- link above) and runs to the plot's own front edge
	-- (BaseConfig.BASE_PLOT_CENTER_Z - BaseConfig.BASE_MAT_SIZE.Z / 2 = 150
	-- - 42 = 108, touched exactly, no gap and no need to overlap further --
	-- the mat itself picks up from there) -- a span of 23 studs (108 - 85),
	-- centred at 96.5 ((85 + 108) / 2). The plot didn't move -- only this
	-- span got shorter again (was 32 studs, then 46 before that). =====
	SPUR_SIZE = Vector3.new(10, 0.3, 23),
	SPUR_Y_OFFSET = 0.15,
	SPUR_Z = 96.5,

	-- ===== Walkway: the FOOTPRINT of the conveyor, spanning every lane -- X
	-- is the road's own centerline (LaneConfig.ROAD_CENTER_X), not stored
	-- here. Sits at Z = 76, between the swings (Z = 30) and the plots (front
	-- edge at Z = 108) -- see this file's own header for why 76, not 62, and
	-- for why the connectors stop at its edges (67, 85) instead of running
	-- through its centre. Same Y_OFFSET as both connectors (0.15) -- all
	-- three are one continuous flat surface.
	--
	-- NOW BUILT AS TWO PARTS, NOT ONE (see REPORT.md). MapBuilder splits this
	-- footprint down its length into two halves of SIZE.Z / 2 = 9 each,
	-- centred at Z = 76 -+ 4.5, and gives them opposing surface velocities --
	-- a two-way conveyor, so a player can reach any base or either shop in
	-- either direction without walking. The split is DERIVED there from these
	-- same two constants rather than stored as two more; this stays the
	-- single description of where the walkway is and how big it is.
	--
	-- WIDTH IS NOW DERIVED (see BELT_HALF_WIDTH above), not the hand-computed
	-- 276 the last pass left here and not the 440 before that. It is twice
	-- the shop position less the inset, so it follows the lane pitch: 416 at
	-- the current 360-wide road, and it would evaluate to exactly the old 276
	-- at the previous 240. Retuning the road width now moves the road, the
	-- lanes, the plots, the shops AND the belt in one step, with this file
	-- needing no edit at all.
	BACK_WALKWAY_SIZE = Vector3.new(BELT_HALF_WIDTH * 2, 0.3, 18),
	BACK_WALKWAY_Y_OFFSET = 0.15,
	BACK_WALKWAY_Z = 76,

	-- Surface speed of each conveyor half, studs/second, applied as opposing
	-- AssemblyLinearVelocity on X (see MapBuilder). Default walk speed is 16,
	-- so this is 2x walking -- fast enough that the belt reads as transport
	-- rather than a mildly helpful floor, which is the entire point of it.
	-- End to end (276 studs) is 8.6 s; one lane (40 studs) is 1.25 s.
	--
	-- THE COST OF RAISING IT is sideways drift for anyone crossing the belt
	-- rather than riding it: the surface pushes on X no matter which way the
	-- player walks, so crossing one 9-stud half at walk speed takes ~0.56 s
	-- and carries them ~18 studs downstream at this value. The opposed split
	-- very nearly cancels that over BOTH halves (drift one way, then the
	-- other, equal time at equal speed), so a player crossing the full width
	-- lands back on close to their own lane's X having traced a shallow S.
	-- It does NOT cancel for anyone who stops halfway. This is the number to
	-- lower first if the crossing ever feels like being shoved.
	BELT_SPEED_STUDS_PER_SECOND = 32,

	-- ===== MAKING THE BELT LOOK LIKE A BELT (see REPORT.md). Built plain, it
	-- read as walkway -- identical concrete to the static paths it abuts,
	-- with nothing to say it moved or which way. =====
	--
	-- The SURFACE: mid-grey and PLAIN. This was dark DiamondPlate for one
	-- pass, chosen when the direction cue was amber chevrons sitting on top
	-- of it. It is neither of those things now, and both changed for the same
	-- reason -- see BELT_RIDGE_* below.
	--
	-- SmoothPlastic, NOT DiamondPlate: the ridges are a TEXTURE now, and
	-- DiamondPlate carries a strong tread pattern of its own that would run
	-- underneath them at a different pitch. Two competing patterns on one
	-- surface read as noise, and the moving one loses -- which is exactly the
	-- thing that has to stay legible. A plain base gives the scrolling ridges
	-- the whole surface to themselves.
	--
	-- LIGHTER, not dark: the ridges are DARK, so the belt has to be the
	-- lighter of the two for them to read at all. Still clearly a different
	-- KIND of surface from the paths' pale warm concrete (214, 210, 198) --
	-- this is a cooler, darker grey, so the belt still separates from the
	-- approach link and spur it butts against.
	BELT_COLOR = Color3.fromRGB(122, 126, 134),
	BELT_MATERIAL = Enum.Material.SmoothPlastic,

	-- ===== THE SCROLLING RIDGES. The direction cue, replacing 80 static
	-- amber chevrons -- static arrows on a surface that is meant to be moving
	-- were the wrong idea as well as ugly. This is the read every conveyor in
	-- every game of this kind uses: the SURFACE ITSELF appears to move.
	--
	-- A Texture on each half's top face, tiled along the belt's length and
	-- scrolled every frame by LaunchClient/ConveyorScroll.luau. Only the
	-- OFFSET is animated -- no part moves and nothing is rebuilt per frame.
	--
	-- YOU MUST SUPPLY THIS ASSET. Roblox ships no stock texture of belt
	-- ridges, and inventing an ID would either 404 or render somebody else's
	-- art, so this ships EMPTY: the belt renders as plain grey until it is
	-- filled in. The Texture instance is created and scrolled regardless, so
	-- pasting an ID here -- or straight onto the BeltRidges Texture in Studio,
	-- to try one live -- is the only step left. REPORT.md gives the exact
	-- image spec to generate.
	BELT_RIDGE_TEXTURE_ASSET_ID = "rbxassetid://87264921429321",

	-- Studs along the belt per TILE of the image. Note this is the tile, not
	-- the ridge pitch: the uploaded texture carries TWO bars per tile, so a
	-- ridge passes every 4 studs at this value, and the tile size in WORLD
	-- units is also what the image is stretched to.
	--
	-- 8, RAISED FROM 4 -- confirmed strobing, not a guess. At 4 the two bars
	-- put a ridge every 2 studs, and against a 32 studs/second belt that is
	-- 16 ridges past any fixed point per second: fast enough to alias into a
	-- flicker rather than reading as travel. 8 restores the ~8 per second the
	-- pitch was sized for, which reads as motion.
	--
	-- Raise this further if it still shimmers; lower it only if the belt ever
	-- gets much slower, since what matters is ridges-per-second (belt speed
	-- divided by half this value), not the spacing on its own.
	BELT_RIDGE_TILE_STUDS = 8,

	-- Which way a POSITIVE OffsetStudsU shifts the image. Roblox does not
	-- document the U axis's sign for a Top-face Texture and it is not
	-- determinable from code, so this was the one value here that wanted a
	-- look rather than a derivation.
	--
	-- 1, CORRECTED FROM -1 -- looked at, and -1 scrolled the ridges AGAINST
	-- the belt's travel. Flipping this is the whole fix: the scroller
	-- multiplies it by each belt's own live velocity, so both halves flipped
	-- together and stayed correctly opposed, and no velocity was touched.
	BELT_RIDGE_SCROLL_SIGN = 1,

	-- Shared by all three.
	PATH_COLOR = Color3.fromRGB(214, 210, 198),
	PATH_MATERIAL = Enum.Material.Concrete,
}

return PathConfig
