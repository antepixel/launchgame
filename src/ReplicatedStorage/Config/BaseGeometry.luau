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
-- STUDS), Z = BASE_SLOT_Z_START + row*BASE_SLOT_ROW_SPACING_STUDS (71, 85,
-- 99, 113, 127). The world position of slot i (1-indexed) within the given
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
-- framing it -- all centred on BaseConfig.BASE_PLOT_CENTER_Z (104), except
-- the back edge, which sits at its own BASE_BACK_EDGE_Z (146). Every Y is
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

function BaseGeometry.backEdgePosition(baseIndex: number): Vector3
	local baseX = LaneConfig.baseLaneCenterX(baseIndex)
	return Vector3.new(baseX, groundY + BaseConfig.BASE_BACK_EDGE_Y_OFFSET, BaseConfig.BASE_BACK_EDGE_Z)
end

return BaseGeometry
