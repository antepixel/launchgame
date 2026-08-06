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
-- X = baseX +-11, Z = 117/131/145/159/173 -- see BaseGeometry.luau's
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
	-- a real 2x5 grid now, not a 5x2 one: 2 columns (X = baseX +-11) x 5
	-- rows (Z = 71, 85, 99, 113, 127), exact approved values. =====
	BASE_GRID_COLUMNS = 2,
	-- Studs between the two columns (X): halfWidth = (columns-1)*this/2 = 11,
	-- giving the exact X = baseX +-11 the ten pads must land on.
	BASE_SLOT_COLUMN_SPACING_STUDS = 22,
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
	BASE_SLOT_PAD_SIZE = Vector3.new(8, 0.6, 8),
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
	BASE_MAT_SIZE = Vector3.new(44, 0.4, 84),
	BASE_MAT_Y_OFFSET = 0.2,
	BASE_MAT_COLOR = Color3.fromRGB(158, 94, 70),
	BASE_MAT_MATERIAL = Enum.Material.Pebble,

	-- The central path: deliberately sits slightly ABOVE flush (0.3, not
	-- size.Y/2 = 0.25) so it reads as a raised walkway laid over the mat,
	-- not a slab buried halfway into it.
	BASE_PATH_SIZE = Vector3.new(10, 0.5, 84),
	BASE_PATH_Y_OFFSET = 0.3,
	BASE_PATH_COLOR = Color3.fromRGB(214, 210, 198),
	BASE_PATH_MATERIAL = Enum.Material.Concrete,

	-- Side edges: one on each side of the plot, at X = baseX +-this.
	BASE_SIDE_EDGE_SIZE = Vector3.new(1, 1.1, 86),
	BASE_SIDE_EDGE_X_OFFSET = 22.5,
	BASE_SIDE_EDGE_Y_OFFSET = 0.55,

	-- Back edge: one per lane, closing off the far end of the plot. Shifted
	-- +46 along with BASE_PLOT_CENTER_Z above (146 -> 192 = new plot centre
	-- 150 + mat half-depth 42, same relationship as before).
	BASE_BACK_EDGE_SIZE = Vector3.new(46, 1.1, 1),
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
