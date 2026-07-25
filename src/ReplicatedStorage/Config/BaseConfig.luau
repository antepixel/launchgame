--!strict
-- Every base/income constant lives here, and ONLY here -- same rule as
-- LaunchConfig.luau and SlimeConfig.luau, just for the base-and-income
-- system bolted onto a slime reveal's outcome (see the written report).
--
-- THIS PASS: bases are per-player (see BaseGeometry.luau and
-- PlayerProfile.luau) -- SLOT_COUNT and the inner-grid constants describe
-- ONE player's own base; the BASE_SIDE_START_STUDS..BASE_ROW_SPACING_STUDS
-- block below is what places different players' bases next to each other
-- without overlapping. There used to be a single BASE_OFFSET_FROM_SWING for
-- the one shared base -- gone now, replaced by that block.

export type BaseConfig = {
	SLOT_COUNT: number,
	BASE_INCOME_TICK_SECONDS: number,
	BASE_GRID_COLUMNS: number,
	BASE_SLOT_SPACING_STUDS: number,
	BASE_SIDE_START_STUDS: number,
	BASE_COLUMN_SPACING_STUDS: number,
	BASE_COLUMNS_PER_ROW: number,
	BASE_ROW_START_STUDS: number,
	BASE_ROW_SPACING_STUDS: number,
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

	-- ===== Placing DIFFERENT players' bases next to each other (see
	-- BaseGeometry.luau's blockOrigin) -- fans outward from the swing,
	-- alternating left/right of it so consecutive joiners land on opposite
	-- sides, filling BASE_COLUMNS_PER_ROW block-columns per side before
	-- wrapping to a new row further from the swing. Sized to keep every
	-- block within the existing Baseplate (240 studs wide, Z 10-60) for a
	-- modest player count -- see the written report for the exact capacity
	-- and what happens past it (blocks start landing off the platform's
	-- edge; not addressed this pass). =====
	-- Studs from the swing's own X to the FIRST block-column's center, on
	-- either side -- clear of the swing posts (at X = +-6).
	BASE_SIDE_START_STUDS = 30,
	-- Studs between successive block-columns on the same side.
	BASE_COLUMN_SPACING_STUDS = 35,
	-- Block-columns per side before wrapping to a new row (further from the
	-- swing in +Z). 3 keeps every column's block (16-stud half-width, see
	-- BASE_GRID_COLUMNS/BASE_SLOT_SPACING_STUDS above) inside the
	-- Baseplate's +-120 stud width with margin to spare.
	BASE_COLUMNS_PER_ROW = 3,
	-- Studs from the swing's own Z to the FIRST row's center.
	BASE_ROW_START_STUDS = 10,
	-- Studs between successive rows. 16 keeps a second row's block (4-stud
	-- half-depth) just inside the Baseplate's Z <= 60 edge.
	BASE_ROW_SPACING_STUDS = 16,

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
