--!strict
-- Ground-level world dressing that isn't part of any other domain (not a
-- base, not a path, not a stall) -- currently just the kerb along the road
-- edge. Built at runtime by MapBuilder.server.luau, same "generated, not
-- hand-authored" reasoning as RunwayBuilder -- only the Baseplate itself
-- belongs in default.project.json. X isn't stored here at all -- the kerb
-- runs along the road's own centerline, so MapBuilder reads that straight
-- from LaneConfig.ROAD_CENTER_X, the one source of truth for it.

export type GroundConfig = {
	KERB_SIZE: Vector3,
	KERB_Y_OFFSET: number,
	KERB_Z: number,
	KERB_COLOR: Color3,
	KERB_MATERIAL: Enum.Material,
}

local GroundConfig: GroundConfig = {
	-- Runs the full width of the road (X), sat right where the paved
	-- platform gives way to the runway (Z, just short of RunwayGeometry.
	-- RUNWAY_START_Z) -- a visible edge between "platform" and "runway,"
	-- not a functional barrier (CanCollide is left off by MapBuilder).
	KERB_SIZE = Vector3.new(480, 1.2, 2),
	-- Sits flush on the ground (Y offset = size.Y/2), added to groundY at
	-- build time -- never hardcoded, same reasoning as BaseGeometry.
	KERB_Y_OFFSET = 0.6,
	KERB_Z = -3.3,
	KERB_COLOR = Color3.fromRGB(228, 226, 218),
	KERB_MATERIAL = Enum.Material.Concrete,
}

return GroundConfig
