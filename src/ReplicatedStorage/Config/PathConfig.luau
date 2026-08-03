--!strict
-- Every connective-path constant lives here, and ONLY here -- the paved
-- links between a lane's swing and its base, and the walkway tying every
-- lane together at the back of the map. Built at runtime by
-- MapBuilder.server.luau, same "generated, not hand-authored" reasoning as
-- RunwayBuilder -- only the Baseplate itself belongs in
-- default.project.json.
--
-- Distinct from BaseConfig's own BASE_PATH_* (the short central path
-- inside one player's plot) even though they share a colour -- these three
-- are MAP-level connectors, not owned by any one base.

export type PathConfig = {
	ANGLED_LINK_START_Z: number,
	ANGLED_LINK_END_Z: number,
	ANGLED_LINK_WIDTH: number,
	ANGLED_LINK_THICKNESS: number,
	ANGLED_LINK_Y_OFFSET: number,

	SPUR_SIZE: Vector3,
	SPUR_Y_OFFSET: number,
	SPUR_Z: number,

	BACK_WALKWAY_SIZE: Vector3,
	BACK_WALKWAY_Y_OFFSET: number,
	BACK_WALKWAY_Z: number,

	PATH_COLOR: Color3,
	PATH_MATERIAL: Enum.Material,
}

local PathConfig: PathConfig = {
	-- ===== Angled link: one per lane, from [swingX, .., START_Z] to
	-- [baseX, .., END_Z] -- swingX/baseX come from LaneConfig at build time,
	-- never stored here. Oriented along the line between the two points
	-- (see MapBuilder), so WIDTH is the only crosswise dimension needed;
	-- length is however far apart that lane's swing and base X happen to be,
	-- computed at build time, never a stored constant. =====
	ANGLED_LINK_START_Z = 34,
	ANGLED_LINK_END_Z = 62,
	ANGLED_LINK_WIDTH = 9,
	ANGLED_LINK_THICKNESS = 0.3,
	-- Sits flush on the ground (Y offset = thickness/2), added to groundY at
	-- build time -- never hardcoded, same reasoning as BaseGeometry.
	ANGLED_LINK_Y_OFFSET = 0.15,

	-- ===== Spur: one per lane, behind that lane's own plot, at baseX (from
	-- LaneConfig, not stored here). =====
	SPUR_SIZE = Vector3.new(10, 0.3, 28),
	SPUR_Y_OFFSET = 0.15,
	SPUR_Z = 160,

	-- ===== Back walkway: ONE part, spanning every lane -- X is the road's
	-- own centerline (LaneConfig.ROAD_CENTER_X), not stored here. =====
	BACK_WALKWAY_SIZE = Vector3.new(440, 0.3, 18),
	BACK_WALKWAY_Y_OFFSET = 0.15,
	BACK_WALKWAY_Z = 174,

	-- Shared by all three.
	PATH_COLOR = Color3.fromRGB(214, 210, 198),
	PATH_MATERIAL = Enum.Material.Concrete,
}

return PathConfig
