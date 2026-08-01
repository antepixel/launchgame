--!strict
-- Every base/income constant lives here, and ONLY here -- same rule as
-- LaunchConfig.luau and SlimeConfig.luau, just for the base-and-income
-- system bolted onto a slime reveal's outcome (see the written report).
--
-- THIS PASS: bases are per-LANE now, not fanned out from a shared swing
-- (see BaseGeometry.luau and the written report -- six-lane pass 1). SLOT_
-- COUNT and the inner-grid constants describe ONE player's own base; a
-- base's WORLD X comes from LaneConfig.laneCenterX (that player's own lane,
-- the same index their swing pivot uses), never from an offset computed
-- here. BASE_ROW_START_STUDS is the only placement constant left in this
-- file -- how far behind a lane's own swing (in Z) that lane's base sits.
-- The old BASE_SIDE_START_STUDS/BASE_COLUMN_SPACING_STUDS/BASE_COLUMNS_PER_
-- ROW/BASE_ROW_SPACING_STUDS side/column/row fan-out is gone outright, not
-- just its dead row-wrap term -- that whole scheme assumed one central
-- swing to fan out from, which no longer exists.

export type BaseConfig = {
	SLOT_COUNT: number,
	BASE_INCOME_TICK_SECONDS: number,
	BASE_GRID_COLUMNS: number,
	BASE_SLOT_SPACING_STUDS: number,
	BASE_ROW_START_STUDS: number,
	BASE_SLOT_PAD_SIZE: Vector3,
	BASE_SLOT_PAD_COLOR: Color3,
	BASE_SLIME_PART_SIZE: Vector3,
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

	-- ===== One player's own grid (see BaseGeometry.luau's slotPosition) =====
	-- Slots are laid out in a grid, wrapping to a new row every this many
	-- columns -- 5 gives a 5x2 grid for the default 10-slot count.
	BASE_GRID_COLUMNS = 5,
	-- Studs between adjacent slot centers, both across a row and between rows.
	BASE_SLOT_SPACING_STUDS = 8,

	-- ===== Placing one player's base behind their OWN lane (see
	-- BaseGeometry.luau's blockOrigin) -- X comes from LaneConfig.
	-- laneCenterX(baseIndex), the same lane center that player's own swing
	-- pivot sits at; this is the only placement constant left in this
	-- file. =====
	-- Studs from a lane's own swing Z (LaneConfig.SWING_PIVOT_Z) to that
	-- lane's base row center, further along +Z (away from the runway,
	-- which runs -Z).
	BASE_ROW_START_STUDS = 10,

	-- ===== Visuals (placeholder only -- see the written report) =====
	-- Each slot's pad -- a flat marker showing where a slime would go,
	-- whether or not it currently holds one.
	BASE_SLOT_PAD_SIZE = Vector3.new(6, 1, 6),
	BASE_SLOT_PAD_COLOR = Color3.fromRGB(90, 90, 96),
	-- The placeholder "slime" itself once a slot is filled: a plain coloured
	-- block in the slime's own tier colour (see SlimeConfig.SLIME_TIER_
	-- COLORS), sized well clear of its pad. No models -- see the written
	-- report.
	BASE_SLIME_PART_SIZE = Vector3.new(4, 4, 4),
}

return BaseConfig
