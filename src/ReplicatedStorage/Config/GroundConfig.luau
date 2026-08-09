--!strict
-- Ground-level world dressing that isn't part of any other domain (not a
-- base, not a path, not a stall) -- the kerb along the road edge, plus the
-- one shared surface-finish decision every walkable surface in the map
-- answers to (GROUND_TOP_SURFACE below). Built at runtime by
-- MapBuilder.server.luau, same "generated, not hand-authored" reasoning as
-- RunwayBuilder -- only the Baseplate itself belongs in
-- default.project.json. X isn't stored here at all -- the kerb runs along
-- the road's own centerline, so MapBuilder reads that straight from
-- LaneConfig.ROAD_CENTER_X, the one source of truth for it.

export type GroundConfig = {
	GROUND_TOP_SURFACE: Enum.SurfaceType,

	KERB_SIZE: Vector3,
	KERB_Y_OFFSET: number,
	KERB_Z: number,
	KERB_COLOR: Color3,
	KERB_MATERIAL: Enum.Material,
}

local GroundConfig: GroundConfig = {
	-- ===== THE CLASSIC STUDDED TOP, on every walkable surface in the map.
	--
	-- ONE NAMED VALUE BECAUSE IT IS SET IN TWO FILES: MapBuilder applies it
	-- to the paths, the belt, the plot mats and trim, the slot pads and the
	-- kerb; PlayerProfile applies it to the collect pads it builds per slot.
	-- Those are different domains with different builders, so without a
	-- shared constant "the ground is studded" would be two independent
	-- decisions that could silently disagree. It lives HERE, in the
	-- ground-level config, rather than in any one of BaseConfig/PathConfig --
	-- it is not a property of plots or of paths, it is a property of ground.
	--
	-- DELIBERATELY NOT APPLIED IN MapBuilder's part factory. The factory also
	-- builds stall roofs, posts, signs and the giant slime's ground patch,
	-- none of which are walkable ground; each ground surface opts in
	-- explicitly at its own call site instead (see MapBuilder's `asGround`),
	-- so the list of what counts as ground is readable in one place rather
	-- than being whatever happened to go through the factory.
	--
	-- VISUAL ONLY. Surface types are a rendered decoration -- they do not
	-- change a part's Size, its bounding box, or its collision geometry, so
	-- nothing that derives a height or a landing position from these parts is
	-- affected (see REPORT.md, which checks each one).
	--
	-- EXCLUDED, deliberately: the grass Baseplate, the rainbow road bands,
	-- and the giant slime's ground patch. See REPORT.md for the road bands in
	-- particular -- their number labels turn out NOT to sit on the band's own
	-- face, so studs there would not fight them, and the exclusion is a taste
	-- call rather than a technical one.
	GROUND_TOP_SURFACE = Enum.SurfaceType.Studs,

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
