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
-- X = baseX +-11, Z = 71/85/99/113/127 -- see BaseGeometry.luau's
-- slotPosition, which reads every grid constant below. The surrounding
-- plot (mat, central path, side/back edges) is NEW this pass -- static
-- per-lane world dressing built once at server start by
-- MapBuilder.server.luau (see BaseGeometry's matPosition/
-- centralPathPosition/sideEdgePositions/backEdgePosition), independent of
-- whether that lane's player has joined yet. That's different from the ten
-- slot pads above, which PlayerProfile still builds per-player on join --
-- the plot is part of the LANE, the pads (and whatever sits on them) are
-- part of the PLAYER.

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
	BASE_SLIME_PART_SIZE: Vector3,

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
	-- Z of the FIRST row (slot 1/2). Rows then run 71, 85, 99, 113, 127.
	BASE_SLOT_Z_START = 71,

	-- ===== Visuals =====
	-- Each slot's pad -- a flat marker showing where a slime would go,
	-- whether or not it currently holds one.
	BASE_SLOT_PAD_SIZE = Vector3.new(8, 0.6, 8),
	BASE_SLOT_PAD_COLOR = Color3.fromRGB(182, 182, 188),
	BASE_SLOT_PAD_MATERIAL = Enum.Material.Concrete,
	-- The placeholder "slime" itself once a slot is filled: a plain coloured
	-- block in the slime's own tier colour (see SlimeConfig.SLIME_TIER_
	-- COLORS), sized well clear of its pad. No models -- see the written
	-- report.
	BASE_SLIME_PART_SIZE = Vector3.new(4, 4, 4),

	-- ===== Plot dressing: the mat, its central path, and the raised edges
	-- framing it -- everything centred on this single Z per lane (X still
	-- comes from LaneConfig.baseLaneCenterX(baseIndex)). All Y offsets are
	-- ABOVE ground level (BaseGeometry's own groundY, read from the
	-- Baseplate, never hardcoded), even though they happen to equal the
	-- literal numbers given while groundY is 0 on this map. =====
	BASE_PLOT_CENTER_Z = 104,

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

	-- Back edge: one per lane, closing off the far end of the plot.
	BASE_BACK_EDGE_SIZE = Vector3.new(46, 1.1, 1),
	BASE_BACK_EDGE_Z = 146,
	BASE_BACK_EDGE_Y_OFFSET = 0.55,

	-- Side and back edges share one colour/material.
	BASE_EDGE_COLOR = Color3.fromRGB(232, 230, 222),
	BASE_EDGE_MATERIAL = Enum.Material.Concrete,
}

return BaseConfig
