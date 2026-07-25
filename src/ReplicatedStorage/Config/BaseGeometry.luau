--!strict
-- Single source of truth for where a GIVEN player's base sits in world space
-- -- same role RunwayGeometry plays for the runway, extended to be
-- per-player: baseIndex (a stable, freed-on-leave slot -- see
-- PlayerProfile's allocateBaseIndex) picks WHICH block of the world a
-- player's own 10 slots belong to, laid out so no two players' bases ever
-- overlap. PlayerProfile (which builds each base's visuals AND places slime
-- parts into it) is the only reader of this module.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseConfig = require(ReplicatedStorage.Config.BaseConfig)

local swingPivot = Workspace:WaitForChild("SwingPivot") :: BasePart
local baseplate = Workspace:WaitForChild("Baseplate") :: BasePart

local BaseGeometry = {}

-- Ground level -- the baseplate's own TOP surface, not swingPivot's height
-- (swingPivot sits well above the ground, at seat-post height; a base's
-- pads belong on the ground, not floating at seat height). Read from the
-- part, not hardcoded, same reasoning as RunwayGeometry deriving
-- RUNWAY_START_Z from Baseplate instead of a raw number.
local groundY = baseplate.Position.Y + baseplate.Size.Y / 2

-- ===== Per-player block placement =====
-- Each player's base is a small BASE_GRID_COLUMNS-wide grid (see
-- slotPosition below), placed at one of a sequence of block origins that
-- fan OUTWARD from the swing, alternating left/right, so consecutive
-- players land on opposite sides rather than piling onto one:
-- baseIndex 0 -> first column, LEFT of the swing; 1 -> first column, RIGHT;
-- 2 -> second column, LEFT; 3 -> second column, RIGHT; and so on. Within a
-- side, blocks fill BASE_COLUMNS_PER_ROW columns (moving further from the
-- swing in X) before wrapping to a new row (further from the swing in Z).
--
-- CAPACITY NOTE (see the written report): this keeps every base within the
-- existing Baseplate's bounds for a modest number of concurrent players; it
-- does not grow the platform itself, so a very large number of simultaneous
-- players will eventually place rows past the platform's edge. Not a
-- concern for this pass's playtesting scale.
local function blockOrigin(baseIndex: number): Vector3
	local side = if baseIndex % 2 == 0 then -1 else 1
	local sideSlot = baseIndex // 2
	local column = sideSlot % BaseConfig.BASE_COLUMNS_PER_ROW
	local row = sideSlot // BaseConfig.BASE_COLUMNS_PER_ROW

	local x = swingPivot.Position.X + side * (BaseConfig.BASE_SIDE_START_STUDS + column * BaseConfig.BASE_COLUMN_SPACING_STUDS)
	local z = swingPivot.Position.Z + BaseConfig.BASE_ROW_START_STUDS + row * BaseConfig.BASE_ROW_SPACING_STUDS
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
