--!strict
-- The giant slime landmark at the far end of the road (see the written
-- report -- this is the reason a new player has anything to fly toward: a
-- 2,960-stud rainbow road terminating in nothing gives no visual reason to
-- want a better swing). PURELY DECORATIVE -- built once, statically, by
-- MapBuilder.server.luau, for every player, the same way the kerb/stalls/
-- plots already are. No script is ever attached to it; every number that
-- shapes or positions it lives here so it can be retuned by eye without
-- touching MapBuilder.server.luau at all.
--
-- MESH-BASED NOW (see the written report): the body is the same imported
-- slime mesh every slot slime uses (SlimeBuilder.luau), not five separately
-- hand-built ball/eye/pupil Parts -- the eyes/blush are baked into the mesh
-- itself, so every EYE_*/PUPIL_* fraction and PUPIL_FORWARD_OFFSET_STUDS
-- this file used to own is gone; the mesh's own fixed geometry is now the
-- only source of the face. BODY_HEIGHT_STUDS is gone too, for the same
-- reason: SlimeBuilder.build only ever takes a WIDTH -- height follows
-- automatically from the mesh's own fixed ~0.677 height/width ratio, no
-- longer an independent knob.
--
-- WIDTH IS DERIVED, NOT GUESSED (see the written report for the full
-- derivation -- carried over unchanged from the pre-mesh pass, which chose
-- a HEIGHT via this same targeting then derived width as 1.3125x it; the
-- reasoning below is preserved for provenance, but BODY_WIDTH_STUDS is now
-- the primary, independently-tuned number, and retuning the landmark's
-- visible size means changing THIS one -- height simply follows): the body
-- was sized so it subtends roughly 15% of the default camera's vertical
-- field of view (70 degrees) as seen from the swing pivot (LaunchConfig.
-- SWING_PIVOT_Z) at the landmark's own derived distance -- large enough to
-- read as a clear, unmistakable landmark (comparable to how a large
-- building reads from roughly a kilometre away), not a speck on the
-- horizon, without overwhelming the frame at closer range during a flight
-- down the road. The formula: at viewing distance D, the full vertical span
-- visible at that distance is 2 * D * tan(FOV / 2); this targeted ~15% of
-- that span. With this road's own current geometry (RUNWAY_START_Z ~=
-- -4.26, 74 bands at 40 studs each, Z_OFFSET_PAST_LAST_BAND_STUDS below), D
-- from the swing pivot works out to ~3694 studs. If the road's own length or
-- the swing pivot's position ever changes, D changes with it (this file
-- reads none of those directly -- see MapBuilder.server.luau's own
-- placement math, which derives the landmark's position from RunwayGeometry/
-- LuckCurve/LaunchConfig fresh every time).
export type GiantSlimeConfig = {
	BODY_WIDTH_STUDS: number,
	BODY_COLOR: Color3,
	Z_OFFSET_PAST_LAST_BAND_STUDS: number,
	GROUND_PATCH_MARGIN_STUDS: number,
	GROUND_PATCH_THICKNESS_STUDS: number,
}

local GiantSlimeConfig: GiantSlimeConfig = {
	-- Horizontal extent of the body -- see the derivation above. Confirmed
	-- correct and left UNCHANGED by the mesh pass (see the written report) --
	-- well clear of Roblox's 2048-stud-per-axis part size limit. Height is no
	-- longer set here at all -- SlimeBuilder.build derives it automatically
	-- from the mesh's own fixed ~0.677 height/width ratio, giving a visible
	-- height of roughly 711 studs at this width (shorter than the old
	-- BODY_HEIGHT_STUDS = 800 -- expected, see the written report, not a
	-- regression).
	BODY_WIDTH_STUDS = 1050,
	-- Classic, saturated slime green -- bright and distinct against sky/road
	-- from a few thousand studs away, which is the whole point of this
	-- object. Passed straight to SlimeBuilder.build as the body colour, same
	-- as any other slime's tier/per-slime colour would be.
	BODY_COLOR = Color3.fromRGB(70, 220, 100),

	-- Studs PAST the far edge of the last band (band #LuckCurve.VALUES,
	-- currently 74) that the body's own CENTER sits -- see MapBuilder.
	-- server.luau for the exact placement formula. Sized to comfortably
	-- clear both the body's own horizontal radius (BODY_WIDTH_STUDS / 2 --
	-- half the body would otherwise sit back over the road) and the last
	-- band's own floating number sign, which overhangs past the road's own
	-- far edge (see RunwayBuilder.server.luau's SIGN_LENGTH) -- comfortably
	-- larger than both combined, with margin to spare.
	Z_OFFSET_PAST_LAST_BAND_STUDS = 700,

	-- ===== Ground patch (see the written report -- the slime otherwise sits
	-- past the Baseplate's own far edge, over void): a single plain block of
	-- Baseplate-matching ground, sized OFF THE BODY, not a fixed stud count
	-- -- see MapBuilder.server.luau, which derives the patch's own footprint
	-- as BODY_WIDTH_STUDS + 2 * this margin per axis, so resizing the body
	-- later keeps the patch sized to match rather than needing a second,
	-- independently-retuned number. =====
	-- Studs of visible clearance between the body's own horizontal edge and
	-- the patch's own edge, on EVERY side (the patch is centred on the
	-- body).
	GROUND_PATCH_MARGIN_STUDS = 200,
	-- Vertical thickness of the patch slab -- matches the Baseplate's own
	-- Size.Y (see default.project.json) purely for a visually consistent
	-- slab depth; the patch's TOP surface (not this thickness) is what's
	-- actually pinned to RunwayGeometry.RUNWAY_TOP_Y -- see MapBuilder.
	-- server.luau.
	GROUND_PATCH_THICKNESS_STUDS = 4,
}

return GiantSlimeConfig
