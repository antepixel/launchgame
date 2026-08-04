--!strict
-- Every connective-path constant lives here, and ONLY here -- the paved
-- links between a lane's swing and its base, and the walkway tying every
-- lane together. Built at runtime by MapBuilder.server.luau, same
-- "generated, not hand-authored" reasoning as RunwayBuilder -- only the
-- Baseplate itself belongs in default.project.json.
--
-- Distinct from BaseConfig's own BASE_PATH_* (the short central path
-- inside one player's plot) even though they share a colour -- these three
-- are MAP-level connectors, not owned by any one base.
--
-- WALKWAY MOVED FROM BEHIND THE BASES TO BETWEEN THE SWINGS AND THE BASES
-- (see the written report): it used to sit at the FAR back of the map
-- (Z = 174, past every plot), so returning to a swing and then reaching a
-- shop meant walking the full ~200-stud length of your own base first. It
-- now sits at Z = 76, right after the swing and before the plot, so
-- swing -> shop -> base all fall on one line, in that order, with nothing
-- to backtrack past.
--
-- Z = 76, NOT 62 (see the written report -- return position margin pass):
-- an earlier pass put it at 62, which put its own front edge (53) only 1
-- stud past the player's post-flight return position (LaunchConfig.
-- SWING_PIVOT_Z + SWING_RETURN_CLEARANCE_STUDS = 52) and left tier 11's own
-- seat sweep (up to Z ~50.6) almost touching it too. Moved to 76 instead of
-- touching SWING_RETURN_CLEARANCE_STUDS -- that constant is tuned against
-- the mount radius (see its own comment in LaunchConfig.luau) and has
-- nothing to do with the walkway. 76 puts the walkway's front edge at 67:
-- 15 studs clear of the return position, 16 clear of tier 11's furthest
-- seat sweep.
--
-- ALL THREE PARTS NOW MEET EDGE-TO-EDGE, NOT CENTER-OVERLAPPING (see the
-- written report -- z-fighting pass 2): an earlier pass had the angled link
-- and spur run all the way to the walkway's own CENTER, deliberately
-- overlapping it, with the walkway itself dropped to a lower Y offset so
-- the three didn't share an exact top height across that overlap. That
-- still read as visibly wrong in practice. This pass takes the other option
-- instead: the angled link now stops exactly at the walkway's own NEAR edge
-- (67) and the spur now starts exactly at its own FAR edge (85), so there
-- is no Z range where more than one of the three parts exists at all -- and
-- all three sit at the SAME Y_OFFSET (0.15) again, forming one continuous
-- flat surface with no seam to fight over. The knock-on effect is BOTH
-- connectors changing role: the angled link now runs from the swing to the
-- WALKWAY (not to the base), and the spur now runs from the WALKWAY back to
-- the plot (the reverse of its old "plot to walkway" direction). The PLOT
-- itself does NOT move for any of this -- only the spur's own length
-- changes to still reach it. =====

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
	-- computed at build time, never a stored constant.
	--
	-- END_Z stops exactly at the walkway's own NEAR edge (BACK_WALKWAY_Z -
	-- BACK_WALKWAY_SIZE.Z / 2 = 76 - 9 = 67) -- touched, not overlapped, so
	-- the link and the walkway occupy disjoint Z ranges and can never share
	-- a Z where both exist at the same height (see this file's own header).
	-- =====
	ANGLED_LINK_START_Z = 34,
	ANGLED_LINK_END_Z = 67,
	ANGLED_LINK_WIDTH = 9,
	ANGLED_LINK_THICKNESS = 0.3,
	-- Sits flush on the ground (Y offset = thickness/2), added to groundY at
	-- build time -- never hardcoded, same reasoning as BaseGeometry. Same
	-- value as the walkway and the spur below -- all three form one
	-- continuous flat surface now, not a stack of overlapping ones.
	ANGLED_LINK_Y_OFFSET = 0.15,

	-- ===== Spur: one per lane, bridging the WALKWAY to that lane's own
	-- plot, at baseX (from LaneConfig, not stored here) -- the reverse
	-- direction from before (used to run FROM the plot's own back edge TO
	-- the walkway; now runs FROM the walkway TO the plot's own front edge,
	-- since the walkway is reached first now). Starts exactly at the
	-- walkway's own FAR edge (BACK_WALKWAY_Z + BACK_WALKWAY_SIZE.Z / 2 = 76
	-- + 9 = 85 -- touched, not overlapped, same reasoning as the angled
	-- link above) and runs to the plot's own front edge
	-- (BaseConfig.BASE_PLOT_CENTER_Z - BaseConfig.BASE_MAT_SIZE.Z / 2 = 150
	-- - 42 = 108, touched exactly, no gap and no need to overlap further --
	-- the mat itself picks up from there) -- a span of 23 studs (108 - 85),
	-- centred at 96.5 ((85 + 108) / 2). The plot didn't move -- only this
	-- span got shorter again (was 32 studs, then 46 before that). =====
	SPUR_SIZE = Vector3.new(10, 0.3, 23),
	SPUR_Y_OFFSET = 0.15,
	SPUR_Z = 96.5,

	-- ===== Walkway: ONE part, spanning every lane -- X is the road's own
	-- centerline (LaneConfig.ROAD_CENTER_X), not stored here. Sits at
	-- Z = 76, between the swings (Z = 30) and the plots (front edge at
	-- Z = 108) -- see this file's own header for why 76, not 62, and for
	-- why the connectors now stop at its edges (67, 85) instead of running
	-- through its centre. Same Y_OFFSET as both connectors (0.15) -- all
	-- three are one continuous flat surface now. =====
	BACK_WALKWAY_SIZE = Vector3.new(440, 0.3, 18),
	BACK_WALKWAY_Y_OFFSET = 0.15,
	BACK_WALKWAY_Z = 76,

	-- Shared by all three.
	PATH_COLOR = Color3.fromRGB(214, 210, 198),
	PATH_MATERIAL = Enum.Material.Concrete,
}

return PathConfig
