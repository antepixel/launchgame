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

-- ===== Slot grid: TEN pads, a real 2-column x 5-row grid (see BaseConfig.
-- BASE_GRID_COLUMNS) -- X = baseX +-11 (half of BASE_SLOT_COLUMN_SPACING_
-- STUDS), Z = BASE_SLOT_Z_START + row*BASE_SLOT_ROW_SPACING_STUDS (117, 131,
-- 145, 159, 173). The world position of slot i (1-indexed) within the given
-- lane's base -- Y already includes BASE_SLOT_PAD_Y_OFFSET, same "the
-- returned position IS the part's center, offset baked in" shape as
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
