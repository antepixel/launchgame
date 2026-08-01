--!strict
-- Single source of truth for where a GIVEN player's base sits in world space
-- -- same role RunwayGeometry plays for the runway, extended to be
-- per-player: baseIndex (a stable, freed-on-leave slot -- see
-- PlayerProfile's allocateBaseIndex) is now also that player's LANE index
-- (see the written report -- six-lane pass 1: one parallel index, not two),
-- so a base's position is derived directly from that lane's own world X,
-- never from an offset fanned out from any specific swing instance.
-- PlayerProfile (which builds each base's visuals AND places slime parts
-- into it) is the only reader of this module.
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

-- ===== Per-player block placement =====
-- Each player's base is a small BASE_GRID_COLUMNS-wide grid (see
-- slotPosition below), placed directly behind that SAME player's own lane:
-- X = that lane's own center (LaneConfig.laneCenterX(baseIndex) -- the
-- identical X their swing pivot sits at), Z = a fixed offset behind that
-- lane's own swing (LaneConfig.SWING_PIVOT_Z + BASE_ROW_START_STUDS).
--
-- BUG FIX (see the written report): this used to fan bases OUTWARD from a
-- single shared swing, alternating left/right and wrapping into new rows as
-- more players joined -- a scheme that only made sense when there was one
-- central swing to fan out from. There are up to LANE_COUNT independent
-- swings now, one per lane, so each base sits directly behind its OWN
-- lane's swing instead -- no side/column/row arithmetic left at all, and no
-- risk of two bases ever landing in the same place, since two players can
-- never share a lane index.
local function blockOrigin(baseIndex: number): Vector3
	local x = LaneConfig.laneCenterX(baseIndex)
	local z = LaneConfig.SWING_PIVOT_Z + BaseConfig.BASE_ROW_START_STUDS
	return Vector3.new(x, groundY, z)
end

-- The world position of slot i (1-indexed) within the given player's base --
-- same inner grid math the old single shared base used, just centered on
-- THIS player's own block origin instead of one fixed point.
function BaseGeometry.slotPosition(baseIndex: number, slotNumber: number): Vector3
	local origin = blockOrigin(baseIndex)
	local columns = BaseConfig.BASE_GRID_COLUMNS
	local spacing = BaseConfig.BASE_SLOT_SPACING_STUDS
	local rows = math.ceil(BaseConfig.SLOT_COUNT / columns)
	local halfWidth = (columns - 1) * spacing / 2
	local halfDepth = (rows - 1) * spacing / 2

	local col = (slotNumber - 1) % columns
	local row = (slotNumber - 1) // columns
	local x = origin.X - halfWidth + col * spacing
	local z = origin.Z - halfDepth + row * spacing
	return Vector3.new(x, origin.Y, z)
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

return BaseGeometry
