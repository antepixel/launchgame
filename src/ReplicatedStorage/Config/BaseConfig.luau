--!strict
-- Every base/income constant lives here, and ONLY here -- same rule as
-- LaunchConfig.luau and SlimeConfig.luau, just for the base-and-income
-- system bolted onto a slime reveal's outcome (see the written report).
--
-- THIS PASS (map blockout): bases sit on their OWN lane pitch now (see
-- LaneConfig.baseLaneCenterX), decoupled from the swing lanes -- a base's
-- WORLD X still comes from that player's own lane index, just a wider,
-- independent pitch, never an offset computed here. The ten slot pads are
-- a real 2-column x 5-row grid (BASE_GRID_COLUMNS = 2), landing exactly on
-- X = baseX +-15, Z = 117/131/145/159/173 -- see BaseGeometry.luau's
-- slotPosition, which reads every grid constant below. The pads, same as
-- the surrounding plot (mat, central path, side/back edges), are static
-- per-lane world dressing built once at server start by
-- MapBuilder.server.luau (see BaseGeometry's matPosition/
-- centralPathPosition/sideEdgePositions/backEdgePosition/slotPosition),
-- independent of whether that lane's player has joined yet -- so every
-- plot reads as a base whether or not anyone is in it. PlayerProfile no
-- longer builds any of this; it only finds the pads MapBuilder already
-- built for its lane and places slime parts onto them.

export type BaseConfig = {
	SLOT_COUNT: number,
	BASE_INCOME_TICK_SECONDS: number,
	BASE_GRID_COLUMNS: number,
	BASE_SLOT_COLUMN_SPACING_STUDS: number,
	BASE_SLOT_ROW_SPACING_STUDS: number,
	BASE_SLOT_Z_START: number,
	BASE_SLOT_PAD_SIZE: Vector3,
	BASE_SLOT_PAD_COLOR: Color3,
	BASE_SLOT_PAD_MATERIAL: Enum.Material,
	BASE_SLOT_PAD_Y_OFFSET: number,

	BASE_COLLECT_PAD_WIDTH_STUDS: number,
	BASE_COLLECT_PAD_DEPTH_STUDS: number,
	BASE_COLLECT_PAD_HEIGHT_STUDS: number,
	BASE_COLLECT_PAD_COLOR: Color3,
	BASE_COLLECT_PAD_MATERIAL: Enum.Material,

	BASE_PLOT_CENTER_Z: number,
	BASE_MAT_SIZE: Vector3,
	BASE_MAT_Y_OFFSET: number,
	BASE_MAT_COLOR: Color3,
	BASE_MAT_MATERIAL: Enum.Material,
	BASE_PATH_SIZE: Vector3,
	BASE_PATH_Y_OFFSET: number,
	BASE_PATH_COLOR: Color3,
	BASE_PATH_MATERIAL: Enum.Material,
	BASE_SIDE_EDGE_SIZE: Vector3,
	BASE_SIDE_EDGE_X_OFFSET: number,
	BASE_SIDE_EDGE_Y_OFFSET: number,
	BASE_BACK_EDGE_SIZE: Vector3,
	BASE_BACK_EDGE_Z: number,
	BASE_BACK_EDGE_Y_OFFSET: number,
	BASE_EDGE_COLOR: Color3,
	BASE_EDGE_MATERIAL: Enum.Material,

	BASE_SIGN_WIDTH_STUDS: number,
	BASE_SIGN_BOARD_COLOR: Color3,
	BASE_SIGN_POST_COLOR: Color3,
	BASE_SIGN_TEXT_COLOR: Color3,
	BASE_SIGN_ENTRANCE_SETBACK_FRACTION: number,
	BASE_SIGN_YAW_DEGREES: number,
}

-- ===== Sizes that OTHER values below are derived from, hoisted out of the
-- table so the derivations can read them. Each is still exported unchanged
-- under its own BASE_* key -- these locals are the single copy, not a second
-- one to keep in step. =====
local SLOT_PAD_SIZE = Vector3.new(8, 0.6, 8)
-- WIDTH 38, WAS 44 (see REPORT.md -- the straightening pass). The plots now
-- sit on the SWING lanes' own 40-stud pitch (LaneConfig.baseLaneCenterX
-- delegates to laneCenterX) so each plot is directly above its own swing,
-- which removes the diagonal walkway links. 44 does not fit a 40 pitch --
-- adjacent plots would overlap by 4 studs. The binding limit is actually
-- tighter than the mat itself: the raised side trim sits at mat/2 + 0.5 and
-- is 1 stud wide, so no-overlap needs mat + 2 <= 40, i.e. mat <= 38. At
-- exactly 38 the trim of adjacent plots lands FLUSH -- outer faces meeting
-- at baseX +-20, precisely half the pitch -- so the six plots read as one
-- continuous row divided by trim lines rather than six islands. Depth is
-- untouched; only the frontage narrowed.
local MAT_SIZE = Vector3.new(38, 0.4, 84)
local PATH_SIZE = Vector3.new(10, 0.5, 84)

-- ===== HOW FAR APART THE TWO SLOT COLUMNS SIT, DERIVED FROM WHAT HAS TO FIT
-- BETWEEN THEM rather than picked. It used to be a flat 22 (columns at
-- baseX +-11), which left a 2-stud channel between a slot pad's inner edge
-- (+-7) and the central path's edge (+-5) -- room only for a 1.6-stud
-- stripe of a collect pad against an 8-stud slot pad. The columns move
-- OUTWARD, toward the plot's side edges, to open that channel up.
--
-- WANTED is the half-width at which a collect pad COLLECT_PAD_WIDTH_STUDS
-- across fits in the channel with COLLECT_PAD_CLEARANCE_STUDS of bare mat on
-- each side: path half + clearance + pad + clearance + slot pad half =
-- 5 + 1 + 4 + 1 + 4 = 15. Note this reads the pad's WIDTH (X) only -- the
-- channel is an X-axis constraint, and the pad's DEPTH (Z) runs along the
-- channel rather than across it, so lengthening the pad in Z does not move
-- the columns.
--
-- LIMIT is how far out they CAN go before the slot pads reach the plot's
-- side. The mat is 44 wide (edges at baseX +-22) and the side edge blocks
-- stand at +-22.5, 1 wide, so their INNER faces are at +-22 too -- the mat
-- edge and the side edge are the same line, and one number covers both. A
-- slot pad is 8 wide, so its centre can reach +-18 before its outer edge
-- touches that line; SLOT_PAD_PLOT_EDGE_MARGIN_STUDS holds it back from
-- being flush, giving +-16.
--
-- WANTED (15) comes first, so that is what is used -- the columns move only
-- as far as the collect pad actually needs, leaving 3 studs of bare mat
-- outside each slot pad rather than crowding the edge. The math.min is not
-- decoration: raise the collect pad size or its clearance far enough and the
-- limit takes over, and the pad is clamped to the channel it actually gets
-- (see BaseGeometry.collectPadPlacement) instead of quietly overlapping the
-- path.
--
-- NOTE the doubling below assumes BASE_GRID_COLUMNS = 2, which is what makes
-- "spacing" and "distance from centre to each column" differ by exactly a
-- factor of two -- BaseGeometry.slotPosition's own halfWidth is
-- (columns - 1) * spacing / 2. With a third column the middle one would land
-- on the central path and this whole derivation would need rethinking, not
-- just rescaling.
--
-- ===== The collect pad's own two dimensions, feeding the derivation above.
-- X AND Z ARE INDEPENDENT, and deliberately so -- they answer to different
-- constraints. The width (X) is half the slot pad's, sized to fit ACROSS the
-- channel, and is the one the column spacing above is built from; the depth
-- (Z) is the slot pad's own, so the collect pad and the slime's pad line up
-- end to end along Z and read as one unit, and it runs ALONG the channel so
-- it feeds nothing above. =====
local COLLECT_PAD_WIDTH_FRACTION = 0.5
local COLLECT_PAD_DEPTH_FRACTION = 1
local COLLECT_PAD_CLEARANCE_STUDS = 1
local SLOT_PAD_PLOT_EDGE_MARGIN_STUDS = 2

local COLLECT_PAD_WIDTH_STUDS = SLOT_PAD_SIZE.X * COLLECT_PAD_WIDTH_FRACTION
local COLLECT_PAD_DEPTH_STUDS = SLOT_PAD_SIZE.Z * COLLECT_PAD_DEPTH_FRACTION
local SLOT_COLUMN_HALF_WIDTH_WANTED = PATH_SIZE.X / 2
	+ COLLECT_PAD_CLEARANCE_STUDS
	+ COLLECT_PAD_WIDTH_STUDS
	+ COLLECT_PAD_CLEARANCE_STUDS
	+ SLOT_PAD_SIZE.X / 2
local SLOT_COLUMN_HALF_WIDTH_LIMIT = MAT_SIZE.X / 2
	- SLOT_PAD_SIZE.X / 2
	- SLOT_PAD_PLOT_EDGE_MARGIN_STUDS
local SLOT_COLUMN_HALF_WIDTH = math.min(SLOT_COLUMN_HALF_WIDTH_WANTED, SLOT_COLUMN_HALF_WIDTH_LIMIT)

local BaseConfig: BaseConfig = {
	-- How many slots EACH player's base has. A slime revealed once every
	-- slot in that player's own base already holds one goes to that
	-- player's inventory instead -- see PlayerProfile.receiveSlime.
	SLOT_COUNT = 10,

	-- Seconds between income payouts -- a DISCRETE lump (every placed
	-- slime's incomePerSecond, summed, times this interval) added all at
	-- once, not a smooth per-frame crawl -- see PlayerProfile.luau's income
	-- loop. 1 matches "once a second" literally; raise it for a chunkier,
	-- more obviously-ticking readout, or lower it for a smoother one -- the
	-- effective EARN RATE stays the same either way, only how coarsely it's
	-- paid out changes.
	BASE_INCOME_TICK_SECONDS = 1,

	-- ===== One player's own grid (see BaseGeometry.luau's slotPosition) --
	-- a real 2x5 grid, not a 5x2 one: 2 columns (X = baseX +-15) x 5 rows
	-- (Z = 117, 131, 145, 159, 173). =====
	BASE_GRID_COLUMNS = 2,
	-- Studs between the two columns (X): halfWidth = (columns-1)*this/2 =
	-- SLOT_COLUMN_HALF_WIDTH = 15, putting the ten pads on X = baseX +-15.
	-- DERIVED, not chosen -- see SLOT_COLUMN_HALF_WIDTH above for what sets
	-- it and what limits it.
	BASE_SLOT_COLUMN_SPACING_STUDS = SLOT_COLUMN_HALF_WIDTH * 2,
	-- Studs between adjacent rows (Z).
	BASE_SLOT_ROW_SPACING_STUDS = 14,
	-- Z of the FIRST row (slot 1/2). Rows then run 117, 131, 145, 159, 173 --
	-- shifted +46 along with the whole plot (see BASE_PLOT_CENTER_Z below)
	-- when the shop walkway moved from behind the bases to between the
	-- swings and the bases -- see the written report.
	BASE_SLOT_Z_START = 117,

	-- ===== Visuals =====
	-- Each slot's pad -- a flat marker showing where a slime would go,
	-- whether or not it currently holds one.
	BASE_SLOT_PAD_SIZE = SLOT_PAD_SIZE,
	BASE_SLOT_PAD_COLOR = Color3.fromRGB(182, 182, 188),
	BASE_SLOT_PAD_MATERIAL = Enum.Material.Concrete,
	-- How far ABOVE groundY the pad's CENTER sits (baked into BaseGeometry.
	-- slotPosition, same "position already includes its own offset" shape as
	-- BASE_MAT_Y_OFFSET etc below). Must clear the mat's own top surface
	-- (BASE_MAT_Y_OFFSET + BASE_MAT_SIZE.Y / 2 = 0.2 + 0.2 = 0.4), not just
	-- groundY -- a pad centered at groundY (the old behaviour) sits HALF
	-- BURIED in the mat, since the mat's top is above groundY and the pad's
	-- own half-height (0.3) isn't enough to clear it. 0.7 = mat top (0.4) +
	-- pad half-height (0.3), so the pad's BOTTOM face lands exactly flush on
	-- the mat's top face -- reads as sitting ON the mat, not sunk into it.
	BASE_SLOT_PAD_Y_OFFSET = 0.7,
	-- The slime itself, once a slot is filled, is now the imported mesh (see
	-- SlimeBuilder.luau) -- its size is a width-in-studs argument passed to
	-- SlimeBuilder.build (PlayerProfile.luau's own SLOT_SLIME_WIDTH_STUDS),
	-- not a config value here; there is no separate placeholder-part size to
	-- own any more.

	-- ===== The COLLECT PAD: one green pad on the ground IN FRONT OF each
	-- occupied slot -- the spot a player will eventually stand on to take
	-- that slime's accumulated money. THIS PASS IS THE PAD ONLY: geometry,
	-- colour and placement. There is no collection logic and no accumulated-
	-- money system behind it yet; income still ticks straight into Money
	-- exactly as before (see PlayerProfile's income loop, untouched).
	--
	-- NO TEXT ON IT, deliberately. A green pad on the floor already reads as
	-- "stand here" -- a SurfaceGui saying COLLECT would be ten more labels
	-- per base competing with the nametags and the button strips already
	-- hanging over these same pads.
	--
	-- IN FRONT means TOWARD THE CENTRAL PATH -- the direction the slime
	-- itself faces (see PlayerProfile.spawnSlimeVisual's facing correction,
	-- which aims each slime across the path toward the base's own centre X).
	-- Its POSITION is not written here: it is DERIVED from the slot pad's own
	-- geometry in BaseGeometry.collectPadPlacement, which reads the slot pad's
	-- real position and size and the path's real width. Only the size and the
	-- look live here.
	--
	-- A TILE OF A NAMED SIZE, CENTRED IN THE CHANNEL -- not a fraction of
	-- whatever the channel happens to be. It used to be the latter, and with
	-- the old 2-stud channel that made it 1.6 x 8: a stripe reading as a
	-- painted line rather than as something to stand on. The columns moved
	-- outward to make room (see SLOT_COLUMN_HALF_WIDTH above, derived from
	-- this WIDTH), so the size can be stated directly and the leftover channel
	-- becomes clearance instead of the size becoming whatever is left.
	--
	-- WIDTH (X) -- HALF THE SLOT PAD'S: 4 studs against the slime's own 8.
	-- Big enough to stand on with room to spare (a character's footprint is
	-- about 2 x 1), clearly a tile rather than a strip, and visibly
	-- subordinate to the pad the slime stands on rather than competing with
	-- it. This is the dimension the channel constrains, and the one
	-- SLOT_COLUMN_HALF_WIDTH_WANTED is built from.
	BASE_COLLECT_PAD_WIDTH_STUDS = COLLECT_PAD_WIDTH_STUDS,
	-- DEPTH (Z) -- THE SLOT PAD'S OWN, all 8 studs of it, so the collect pad
	-- and the slime's pad have matching ends and read as one unit laid across
	-- the mat rather than as a small tile parked beside a big one. It was
	-- briefly square (4 x 4) and looked like a separate object.
	--
	-- Z is unconstrained by the channel -- it runs ALONG it -- so this is free
	-- in X terms: every clearance to the path and to the slot pad is a
	-- function of the WIDTH above and is untouched by this. What it does cost
	-- is row-to-row room: the 14-stud row pitch less this 8 leaves 6 studs of
	-- bare mat between one row's collect pad and the next's (was 10 at 4
	-- deep).
	BASE_COLLECT_PAD_DEPTH_STUDS = COLLECT_PAD_DEPTH_STUDS,
	-- Deliberately SHALLOWER than the slot pad's own 0.6: a step you walk
	-- onto, not a block you walk into. Its Y is derived (mat top + half this)
	-- in BaseGeometry, so changing this keeps it flush automatically.
	BASE_COLLECT_PAD_HEIGHT_STUDS = 0.4,
	-- BRIGHT GLOWING GREEN. Being spotted from the path without a label is the
	-- pad's entire purpose, and Neon's glow is what does that against a Pebble
	-- mat and Concrete pads that are both near-neutral. This was once darkened
	-- so white numbers would sit on it legibly; it stopped reading as a button,
	-- which cost more than it bought. The pad stays bright.
	--
	-- FOR WHOEVER BUILDS THE MONEY READOUT: white text over this pad needs a
	-- dark stroke on the GLYPHS -- TextStrokeTransparency at 0 with a dark
	-- TextStrokeColor3 -- not a darker pad. A stroked glyph carries its own
	-- contrast and so reads on any background, bright or dark, while darkening
	-- the pad trades the thing it exists for against the text. Solve it on the
	-- text. (The nametag labels in PlayerProfile.spawnSlimeVisual set
	-- TextStrokeTransparency = 1 to turn their stroke OFF -- that is the same
	-- property, wanted the other way round, for labels that hang in the air
	-- rather than sitting on a colour.)
	BASE_COLLECT_PAD_COLOR = Color3.fromRGB(61, 211, 93),
	BASE_COLLECT_PAD_MATERIAL = Enum.Material.Neon,

	-- ===== Plot dressing: the mat, its central path, and the raised edges
	-- framing it -- everything centred on this single Z per lane (X still
	-- comes from LaneConfig.baseLaneCenterX(baseIndex)). All Y offsets are
	-- ABOVE ground level (BaseGeometry's own groundY, read from the
	-- Baseplate, never hardcoded), even though they happen to equal the
	-- literal numbers given while groundY is 0 on this map.
	--
	-- MOVED +46 (was 104, see the written report): the shop walkway used to
	-- sit BEHIND every plot (PathConfig.BACK_WALKWAY_Z, then 174) --
	-- reaching a shop meant walking past your entire base first. The
	-- walkway moved to Z = 62, between the swings and the bases, so the
	-- plots had to move back by the same +46 to keep clear of it: the mat's
	-- own front edge (BASE_PLOT_CENTER_Z - BASE_MAT_SIZE.Z / 2 = 150 - 42 =
	-- 108) now sits past the walkway's own back edge (62 + 9 = 71), with
	-- PathConfig's new Spur bridging the 62-108 gap between them -- see
	-- PathConfig.luau. =====
	BASE_PLOT_CENTER_Z = 150,

	-- The mat: sits flush on the ground (Y offset = size.Y/2).
	BASE_MAT_SIZE = MAT_SIZE,
	BASE_MAT_Y_OFFSET = 0.2,
	BASE_MAT_COLOR = Color3.fromRGB(158, 94, 70),
	BASE_MAT_MATERIAL = Enum.Material.Pebble,

	-- The central path: deliberately sits slightly ABOVE flush (0.3, not
	-- size.Y/2 = 0.25) so it reads as a raised walkway laid over the mat,
	-- not a slab buried halfway into it.
	BASE_PATH_SIZE = PATH_SIZE,
	BASE_PATH_Y_OFFSET = 0.3,
	BASE_PATH_COLOR = Color3.fromRGB(214, 210, 198),
	BASE_PATH_MATERIAL = Enum.Material.Concrete,

	-- Side edges: one on each side of the plot, at X = baseX +-this. The
	-- offset is MAT_SIZE.X / 2 + half this part's own width -- unchanged as a
	-- RULE; only the mat it is measured against narrowed (44 -> 38), taking
	-- this from 22.5 to 19.5 with it. At a 40-stud lane pitch that puts each
	-- edge's outer face on baseX +-20, exactly half the pitch, so adjacent
	-- plots' trim meets flush with no overlap and the row is continuous.
	BASE_SIDE_EDGE_SIZE = Vector3.new(1, 1.1, 86),
	BASE_SIDE_EDGE_X_OFFSET = 19.5,
	BASE_SIDE_EDGE_Y_OFFSET = 0.55,

	-- Back edge: one per lane, closing off the far end of the plot. Shifted
	-- +46 along with BASE_PLOT_CENTER_Z above (146 -> 192 = new plot centre
	-- 150 + mat half-depth 42, same relationship as before). Its WIDTH is the
	-- mat plus both side edges (38 + 1 + 1), so it closes the plot corner to
	-- corner -- same rule as before, restated against the narrower mat
	-- (was 46 = 44 + 2).
	BASE_BACK_EDGE_SIZE = Vector3.new(40, 1.1, 1),
	BASE_BACK_EDGE_Z = 192,
	BASE_BACK_EDGE_Y_OFFSET = 0.55,

	-- Side and back edges share one colour/material.
	BASE_EDGE_COLOR = Color3.fromRGB(232, 230, 222),
	BASE_EDGE_MATERIAL = Enum.Material.Concrete,

	-- ===== The entrance sign: a physical wooden post-and-board (see
	-- SignBuilder.luau and assets/Sign.rbxmx), replacing the floating
	-- "<name>'s Base" billboard that used to hang over slot 1. Unlike that
	-- billboard, this is real geometry -- it shrinks with distance like
	-- everything else on the map instead of holding a fixed pixel size on
	-- the horizon. Its POSITION is derived in BaseGeometry.
	-- entranceSignPosition, not here. =====
	--
	-- How wide (studs) the board is built. Height follows automatically from
	-- the asset's own fixed 2.62/2.70 height/width ratio, not a second number
	-- here -- 8 studs wide comes out ~7.76 studs tall, with the board face
	-- itself spanning Y ~3.26 to ~7.11 above ground (comfortably at and above
	-- a character's eye level). 8 reads from the walkway ~25 studs away
	-- without dominating the plot: it's 8 of the mat's own 44 studs of width
	-- (BASE_MAT_SIZE.X), under a fifth of the frontage.
	BASE_SIGN_WIDTH_STUDS = 8,
	-- Warm brown board, slightly darker post, so the two read as separate
	-- pieces of timber rather than one flat silhouette. The imported mesh
	-- arrives with its own baked TextureID, which SignBuilder clears -- these
	-- colours only show once it has.
	BASE_SIGN_BOARD_COLOR = Color3.fromRGB(120, 80, 45),
	BASE_SIGN_POST_COLOR = Color3.fromRGB(95, 62, 35),
	-- Cream, for contrast against the warm brown board above.
	BASE_SIGN_TEXT_COLOR = Color3.fromRGB(247, 239, 219),

	-- How far OUT of the plot, toward the walkway, the sign stands -- as a
	-- fraction of the gap between the plot's own front edge
	-- (BASE_PLOT_CENTER_Z - BASE_MAT_SIZE.Z / 2 = 108) and the walkway
	-- (PathConfig.BACK_WALKWAY_Z = 76). It used to sit ON the front edge,
	-- level with the plot, which meant a player only read it once they had
	-- already arrived. A third of the way out (Z ~= 97.3) puts it at the
	-- MOUTH of the entrance instead -- alongside the spur that bridges the
	-- walkway to the plot, so it reads on approach rather than on arrival --
	-- while still clearing both the mat behind it and the walkway ahead by
	-- ~9 and ~10 studs. See BaseGeometry.entranceSignPosition, which does
	-- the derivation; nothing here or there hardcodes a Z.
	BASE_SIGN_ENTRANCE_SETBACK_FRACTION = 1 / 3,
	-- How far the sign turns in toward the central path, the way a real sign
	-- at the mouth of a driveway angles to greet you rather than staring
	-- straight down the road. The sign stands on the path's -X side, so this
	-- turns its board face toward +X. Modest on purpose: past ~25 degrees the
	-- board starts to foreshorten badly for anyone walking straight up the
	-- spur, which is the one approach it most needs to be readable from.
	BASE_SIGN_YAW_DEGREES = 20,
}

return BaseConfig
