--!strict
-- Single source of truth for where a GIVEN player's base -- and the plot of
-- ground it sits on -- lives in world space, same role RunwayGeometry plays
-- for the runway. baseIndex (a stable, freed-on-leave slot -- see
-- PlayerProfile's allocateBaseIndex) is that player's LANE index; a base's
-- position is derived from that lane's own BASE world X (LaneConfig.
-- baseLaneCenterX -- a wider, independent pitch from the swing lanes, see
-- the written report on the map blockout), never from an offset fanned out
-- from any specific swing instance.
--
-- ONE KIND OF CALLER now (map blockout pass): MapBuilder.server.luau, which
-- builds EVERYTHING this module describes -- the TEN SLOT PADS (reads
-- slotPosition/slotPositions) and the surrounding static plot dressing --
-- mat, central path, side/back edges (reads matPosition/centralPathPosition/
-- sideEdgePositions/backEdgePosition) -- for all LANE_COUNT lanes at server
-- start, whether or not that lane's player has joined yet. PlayerProfile no
-- longer builds any of this; it only finds the pads MapBuilder already built
-- for its own lane (by lane index + slot number) and places slime parts onto
-- them. Every position here shares the same baseX (LaneConfig.
-- baseLaneCenterX) for a given lane -- there is still only one source of
-- truth for a lane's own X, just two different Z schemes layered on top of
-- it (the slot grid, and the plot that grid sits inside).
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseConfig = require(ReplicatedStorage.Config.BaseConfig)
local LaneConfig = require(ReplicatedStorage.Config.LaneConfig)
local PathConfig = require(ReplicatedStorage.Config.PathConfig)

local baseplate = Workspace:WaitForChild("Baseplate") :: BasePart

local BaseGeometry = {}

-- Ground level -- the baseplate's own TOP surface, not any swing pivot's
-- height (a pivot sits well above the ground, at seat-post height; a
-- base's pads belong on the ground, not floating at seat height). Read
-- from the part, not hardcoded, same reasoning as RunwayGeometry deriving
-- RUNWAY_START_Z from Baseplate instead of a raw number.
local groundY = baseplate.Position.Y + baseplate.Size.Y / 2

-- ===== HOW MANY SLOTS THE PLOT CAN ACTUALLY HOLD, asserted at load.
-- SLOT_COUNT reads like a freely tunable constant and is not one: the grid
-- below marches DOWN the plot in Z, one row per BASE_GRID_COLUMNS slots, and
-- runs out of mat. Nothing else in the game notices -- the pads would simply
-- be built past the plot's back edge, floating over the grass with the back
-- edge part through them -- so this is the check that turns a silent layout
-- bug into a refusal to load.
--
-- THE DERIVATION, from the constants and nothing hardcoded:
--   row r's pads are centred at BASE_SLOT_Z_START + r * BASE_SLOT_ROW_SPACING_
--   STUDS and are BASE_SLOT_PAD_SIZE.Z deep, so the far edge of row r sits at
--   BASE_SLOT_Z_START + r * pitch + padDepth/2. That must stay clear of the
--   plot's own back boundary, which is the NEARER of the mat's far edge
--   (BASE_PLOT_CENTER_Z + BASE_MAT_SIZE.Z/2) and the near face of the back
--   edge part (BASE_BACK_EDGE_Z - BASE_BACK_EDGE_SIZE.Z/2).
-- At today's values that is 191.5 (the back edge part, 0.5 studs tighter than
-- the mat), giving r <= 5.0357, so 6 rows and TWELVE slots. SLOT_COUNT is 10,
-- i.e. one spare row.
local SLOT_GRID_BACK_LIMIT_Z = math.min(
	BaseConfig.BASE_PLOT_CENTER_Z + BaseConfig.BASE_MAT_SIZE.Z / 2,
	BaseConfig.BASE_BACK_EDGE_Z - BaseConfig.BASE_BACK_EDGE_SIZE.Z / 2
)
local SLOT_GRID_MAX_ROWS = 1
	+ math.floor(
		(SLOT_GRID_BACK_LIMIT_Z - BaseConfig.BASE_SLOT_Z_START - BaseConfig.BASE_SLOT_PAD_SIZE.Z / 2)
			/ BaseConfig.BASE_SLOT_ROW_SPACING_STUDS
	)
local SLOT_GRID_MAX_SLOTS = SLOT_GRID_MAX_ROWS * BaseConfig.BASE_GRID_COLUMNS
assert(
	BaseConfig.SLOT_COUNT <= SLOT_GRID_MAX_SLOTS,
	string.format(
		"BaseConfig.SLOT_COUNT is %d, but the plot holds at most %d (%d rows of %d): row %d's pads would reach Z %.1f against a back limit of %.1f (%s). Move BASE_SLOT_Z_START, BASE_SLOT_ROW_SPACING_STUDS, BASE_GRID_COLUMNS or the mat before raising it.",
		BaseConfig.SLOT_COUNT,
		SLOT_GRID_MAX_SLOTS,
		SLOT_GRID_MAX_ROWS,
		BaseConfig.BASE_GRID_COLUMNS,
		SLOT_GRID_MAX_ROWS,
		BaseConfig.BASE_SLOT_Z_START + SLOT_GRID_MAX_ROWS * BaseConfig.BASE_SLOT_ROW_SPACING_STUDS + BaseConfig.BASE_SLOT_PAD_SIZE.Z / 2,
		SLOT_GRID_BACK_LIMIT_Z,
		if BaseConfig.BASE_BACK_EDGE_Z - BaseConfig.BASE_BACK_EDGE_SIZE.Z / 2 <= BaseConfig.BASE_PLOT_CENTER_Z + BaseConfig.BASE_MAT_SIZE.Z / 2
			then "the back edge part"
			else "the mat's far edge"
	)
)

-- ===== Slot grid: a real 2-column grid (see BaseConfig.BASE_GRID_COLUMNS) --
-- X = baseX +-15 (half of BASE_SLOT_COLUMN_SPACING_STUDS), Z =
-- BASE_SLOT_Z_START + row*BASE_SLOT_ROW_SPACING_STUDS (117, 131, 145, 159,
-- 173 at the current ten slots). The world position of slot i (1-indexed)
-- within the given lane's base -- Y already includes BASE_SLOT_PAD_Y_OFFSET,
-- same "the returned position IS the part's center, offset baked in" shape as
-- matPosition/centralPathPosition/etc below, so this lands the pad flush on
-- top of the mat rather than centered at bare groundY (which would bury it
-- half inside the mat). =====
function BaseGeometry.slotPosition(baseIndex: number, slotNumber: number): Vector3
	local baseX = LaneConfig.baseLaneCenterX(baseIndex)
	local columns = BaseConfig.BASE_GRID_COLUMNS
	local columnSpacing = BaseConfig.BASE_SLOT_COLUMN_SPACING_STUDS
	local halfWidth = (columns - 1) * columnSpacing / 2

	local col = (slotNumber - 1) % columns
	local row = (slotNumber - 1) // columns
	local x = baseX - halfWidth + col * columnSpacing
	local z = BaseConfig.BASE_SLOT_Z_START + row * BaseConfig.BASE_SLOT_ROW_SPACING_STUDS
	return Vector3.new(x, groundY + BaseConfig.BASE_SLOT_PAD_Y_OFFSET, z)
end

-- All SLOT_COUNT positions for one player's base, in slot order -- a
-- convenience wrapper over slotPosition above for callers that want the
-- whole grid at once (building the pads, laying out a nameplate, ...).
function BaseGeometry.slotPositions(baseIndex: number): { Vector3 }
	local positions: { Vector3 } = {}
	for i = 1, BaseConfig.SLOT_COUNT do
		positions[i] = BaseGeometry.slotPosition(baseIndex, i)
	end
	return positions
end

-- The mat's own TOP surface -- what anything laid ON the mat (the slot pads,
-- the collect pads) has to sit flush against. BASE_SLOT_PAD_Y_OFFSET (0.7)
-- is this same number plus that pad's own half-height, hand-computed once in
-- BaseConfig; the collect pad computes it instead, so retuning the mat can
-- never leave it half-buried.
local matTopY = groundY + BaseConfig.BASE_MAT_Y_OFFSET + BaseConfig.BASE_MAT_SIZE.Y / 2

-- ===== The COLLECT PAD for one slot: where it goes and how big it is, both
-- DERIVED from the slot pad's own geometry and the central path's own width
-- -- no literal position, no literal size (see BaseConfig's own collect-pad
-- block for the tuning fractions and for why the channel is the binding
-- constraint). Returns (position, size), position being the part's CENTRE
-- with its Y offset already baked in, the same shape every other function
-- here returns.
--
-- IN FRONT = TOWARD baseX, by the SAME rule PlayerProfile.spawnSlimeVisual
-- uses to decide which way the slime faces: a pad LEFT of the base's centre
-- (lower X) has its slime looking toward +X, one RIGHT of centre toward -X.
-- Deriving the side from the pad's MEASURED X rather than from the slot
-- number's parity keeps this correct whatever the grid is retuned to --
-- exactly the reasoning spawnSlimeVisual already gives for its own copy of
-- this test.
--
-- X AND Z ARE INDEPENDENT, and answer to different constraints.
--
-- X (across the channel) is BASE_COLLECT_PAD_WIDTH_STUDS, CENTRED in the
-- CHANNEL between the slot pad's inner edge and the path's near edge, with
-- whatever the channel has left over becoming clearance split evenly on both
-- sides. It cannot overlap the walk-in path or the slot pad: the column
-- spacing is derived from this width plus that clearance in the first place
-- (see BaseConfig's SLOT_COLUMN_HALF_WIDTH), and the math.min below is the
-- backstop for the case where the plot's own side limit clamps the columns
-- short of what the pad asked for -- the pad narrows to the channel it
-- actually got rather than spilling onto the path. That clamp is INACTIVE at
-- current values (4-stud width, 6-stud channel).
--
-- Z (along the channel) is BASE_COLLECT_PAD_DEPTH_STUDS, the slot pad's own
-- depth, so the two line up end to end. The channel does not constrain it at
-- all -- it runs ALONG the channel, not across it -- so NO clearance in X is
-- a function of it. What bounds it is the ROW PITCH: at the slot pad's own
-- 8-stud depth against a 14-stud pitch, adjacent rows' pads keep 6 studs of
-- bare mat between them.
--
-- The two columns' collect pads are separated by the full width of the path
-- plus both clearances; adjacent rows by the row pitch less this depth.
function BaseGeometry.collectPadPlacement(baseIndex: number, slotNumber: number): (Vector3, Vector3)
	local baseX = LaneConfig.baseLaneCenterX(baseIndex)
	local slotPos = BaseGeometry.slotPosition(baseIndex, slotNumber)
	local towardCenterX = if slotPos.X < baseX then 1 else -1

	-- The two walls of the channel: the slot pad's edge facing the path, and
	-- the path's edge facing this column.
	local slotInnerEdgeX = slotPos.X + towardCenterX * BaseConfig.BASE_SLOT_PAD_SIZE.X / 2
	local pathEdgeX = baseX - towardCenterX * BaseConfig.BASE_PATH_SIZE.X / 2
	local channelWidth = math.abs(pathEdgeX - slotInnerEdgeX)

	local size = Vector3.new(
		math.min(BaseConfig.BASE_COLLECT_PAD_WIDTH_STUDS, channelWidth),
		BaseConfig.BASE_COLLECT_PAD_HEIGHT_STUDS,
		BaseConfig.BASE_COLLECT_PAD_DEPTH_STUDS
	)
	local position = Vector3.new(
		(slotInnerEdgeX + pathEdgeX) / 2,
		matTopY + size.Y / 2,
		-- Same row as its own slime, so the pad sits squarely in front of it
		-- rather than in front of the gap between two slimes.
		slotPos.Z
	)
	return position, size
end

-- ===== Plot dressing: the mat, its central path, and the raised edges
-- framing it -- all centred on BaseConfig.BASE_PLOT_CENTER_Z (150), except
-- the back edge, which sits at its own BASE_BACK_EDGE_Z (192). Every Y is
-- groundY (read from the Baseplate above, never hardcoded) plus that
-- element's own offset -- see BaseConfig for why the central path's offset
-- isn't simply size.Y/2 like the others. =====
function BaseGeometry.matPosition(baseIndex: number): Vector3
	local baseX = LaneConfig.baseLaneCenterX(baseIndex)
	return Vector3.new(baseX, groundY + BaseConfig.BASE_MAT_Y_OFFSET, BaseConfig.BASE_PLOT_CENTER_Z)
end

function BaseGeometry.centralPathPosition(baseIndex: number): Vector3
	local baseX = LaneConfig.baseLaneCenterX(baseIndex)
	return Vector3.new(baseX, groundY + BaseConfig.BASE_PATH_Y_OFFSET, BaseConfig.BASE_PLOT_CENTER_Z)
end

-- Two side edges, one on each side of the plot -- returned as (left, right)
-- so the caller never has to re-derive the +-offset itself.
function BaseGeometry.sideEdgePositions(baseIndex: number): (Vector3, Vector3)
	local baseX = LaneConfig.baseLaneCenterX(baseIndex)
	local y = groundY + BaseConfig.BASE_SIDE_EDGE_Y_OFFSET
	local left = Vector3.new(baseX - BaseConfig.BASE_SIDE_EDGE_X_OFFSET, y, BaseConfig.BASE_PLOT_CENTER_Z)
	local right = Vector3.new(baseX + BaseConfig.BASE_SIDE_EDGE_X_OFFSET, y, BaseConfig.BASE_PLOT_CENTER_Z)
	return left, right
end

-- Where this lane's wooden entrance sign stands (see SignBuilder.luau) --
-- the point its BASE should rest on, so the caller bottom-aligns to this Y
-- rather than treating it as a centre.
--
-- Z -- OUT IN FRONT OF THE PLOT, AT THE MOUTH OF THE ENTRANCE, derived,
-- never a literal. Players approach from the walkway
-- (PathConfig.BACK_WALKWAY_Z = 76) through the spur, moving in +Z, so the
-- entrance is the plot's LOW-Z end. The plot's own front edge is
-- BASE_PLOT_CENTER_Z minus half the mat's depth (150 - 84/2 = 108); the sign
-- used to stand exactly there, level with the plot, which meant a player only
-- read it once they had already arrived. Stepping
-- BASE_SIGN_ENTRANCE_SETBACK_FRACTION of the way from that edge toward the
-- walkway (108 - 32/3 = ~97.3) moves it out to where the spur meets the plot,
-- so it reads on approach. It stands beside the spur, not on it: the X
-- offset below keeps it clear of the corridor for the corridor's whole
-- length, and ~97.3 leaves the mat behind it and the walkway ahead of it both
-- clear by roughly 9 and 10 studs once the sign's own yawed footprint is
-- counted. Being off the mat entirely, it also no longer has to clear the
-- slot pads (BASE_SLOT_Z_START = 117) at all.
--
-- X -- CLEAR OF THE WALK-IN, derived from the corridor's own width, and
-- UNCHANGED by the move out front. The central path is BASE_PATH_SIZE.X wide,
-- centred on baseX, and the spur feeding it (PathConfig.SPUR_SIZE.X) is the
-- same 10 studs wide on the same centre, so the walk-in corridor runs
-- baseX +-5 for its whole length -- one offset is correct whether the sign
-- stands beside the path or beside the spur. Offsetting by half that corridor
-- plus half the sign's own width puts the sign's INNER edge exactly on the
-- corridor edge -- flanking the entrance without ever standing in it,
-- whatever either width is retuned to. At the current 10-wide corridor and
-- 8-wide sign that is baseX - 9, spanning baseX -13 to -5.
--
-- NOTE this is deliberately FLUSH, not cleared by a margin: the sign's inner
-- edge lands on the corridor boundary exactly. The yaw applied by the caller
-- turns the board's near end slightly away, so the built sign ends up a
-- hair (~0.02 studs) outside rather than a hair inside -- touching, never
-- overlapping. If a real gap is ever wanted, add the margin here rather than
-- relying on the yaw for it.
--
-- The -X side is arbitrary between two symmetric options; it is simply the
-- left-hand side as a player walks in.
function BaseGeometry.entranceSignPosition(baseIndex: number): Vector3
	local baseX = LaneConfig.baseLaneCenterX(baseIndex)
	local frontZ = BaseConfig.BASE_PLOT_CENTER_Z - BaseConfig.BASE_MAT_SIZE.Z / 2
	local gapToWalkway = frontZ - PathConfig.BACK_WALKWAY_Z
	local z = frontZ - gapToWalkway * BaseConfig.BASE_SIGN_ENTRANCE_SETBACK_FRACTION
	local xOffset = BaseConfig.BASE_PATH_SIZE.X / 2 + BaseConfig.BASE_SIGN_WIDTH_STUDS / 2
	return Vector3.new(baseX - xOffset, groundY, z)
end

function BaseGeometry.backEdgePosition(baseIndex: number): Vector3
	local baseX = LaneConfig.baseLaneCenterX(baseIndex)
	return Vector3.new(baseX, groundY + BaseConfig.BASE_BACK_EDGE_Y_OFFSET, BaseConfig.BASE_BACK_EDGE_Z)
end

return BaseGeometry
