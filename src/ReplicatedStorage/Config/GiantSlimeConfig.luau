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
-- SIZE IS DERIVED, NOT GUESSED (see the written report for the full
-- derivation): BODY_HEIGHT_STUDS below is chosen so the body subtends
-- roughly 15% of the default camera's vertical field of view (70 degrees)
-- as seen from the swing pivot (LaunchConfig.SWING_PIVOT_Z) at the
-- landmark's own derived distance -- large enough to read as a clear,
-- unmistakable landmark (comparable to how a large building reads from
-- roughly a kilometre away), not a speck on the horizon, without
-- overwhelming the frame at closer range during a flight down the road.
-- The formula: at viewing distance D, the full vertical span visible at
-- that distance is 2 * D * tan(FOV / 2); this targets ~15% of that span.
-- With this road's own current geometry (RUNWAY_START_Z ~= -4.26, 74 bands
-- at 40 studs each, Z_OFFSET_PAST_LAST_BAND_STUDS below), D from the swing
-- pivot works out to ~3694 studs, giving a target height of ~776 studs --
-- rounded to the clean 800 below. If the road's own length or the swing
-- pivot's position ever changes, D changes with it (this file reads none of
-- those directly -- see MapBuilder.server.luau's own placement math, which
-- derives the landmark's position from RunwayGeometry/LuckCurve/LaunchConfig
-- fresh every time), so this comment's own numbers may drift out of date --
-- the DERIVATION shape is what matters, not these specific studs.
export type GiantSlimeConfig = {
	BODY_WIDTH_STUDS: number,
	BODY_HEIGHT_STUDS: number,
	BODY_COLOR: Color3,
	EYE_DIAMETER_FRACTION: number,
	EYE_SPACING_FRACTION: number,
	EYE_HEIGHT_FRACTION: number,
	EYE_FORWARD_FRACTION: number,
	EYE_COLOR: Color3,
	PUPIL_DIAMETER_FRACTION: number,
	PUPIL_COLOR: Color3,
	PUPIL_FORWARD_OFFSET_STUDS: number,
	Z_OFFSET_PAST_LAST_BAND_STUDS: number,
	GROUND_PATCH_MARGIN_STUDS: number,
	GROUND_PATCH_THICKNESS_STUDS: number,
}

local GiantSlimeConfig: GiantSlimeConfig = {
	-- Vertical extent of the body -- see the derivation above. Well clear of
	-- Roblox's 2048-stud-per-axis part size limit.
	BODY_HEIGHT_STUDS = 800,
	-- Wider than it is tall (see the written report -- "a rounded dome body
	-- wider than it is tall") -- 1.3125x the height, a clearly squashed
	-- silhouette rather than a ball. Also well clear of the 2048 limit.
	BODY_WIDTH_STUDS = 1050,
	-- Classic, saturated slime green -- bright and distinct against sky/road
	-- from a few thousand studs away, which is the whole point of this
	-- object.
	BODY_COLOR = Color3.fromRGB(70, 220, 100),

	-- ===== Eye proportions -- all expressed as FRACTIONS of the body's own
	-- dimensions, not absolute studs, so retuning BODY_HEIGHT_STUDS/
	-- BODY_WIDTH_STUDS keeps the face proportioned automatically instead of
	-- needing every eye number re-tuned to match. =====
	-- Eye diameter, as a fraction of BODY_HEIGHT_STUDS.
	EYE_DIAMETER_FRACTION = 0.12,
	-- Horizontal distance between the two eyes' centers, as a fraction of
	-- BODY_WIDTH_STUDS.
	EYE_SPACING_FRACTION = 0.35,
	-- How far above the body's own center the eyes sit, as a fraction of
	-- BODY_HEIGHT_STUDS.
	EYE_HEIGHT_FRACTION = 0.25,
	-- How far toward the viewer (the swing, +Z) the eyes sit, as a fraction
	-- of the body's own horizontal radius (BODY_WIDTH_STUDS / 2) -- close to
	-- 1.0 sits them right on the body's front surface facing the road.
	EYE_FORWARD_FRACTION = 0.85,
	EYE_COLOR = Color3.new(1, 1, 1),

	-- Pupil diameter, as a fraction of the EYE diameter (not the body).
	PUPIL_DIAMETER_FRACTION = 0.45,
	PUPIL_COLOR = Color3.fromRGB(15, 15, 20),
	-- Extra absolute nudge past the eye's own forward position, purely so
	-- the pupil renders proud of the white and never z-fights with it --
	-- small and constant regardless of body scale, unlike the fractional
	-- proportions above.
	PUPIL_FORWARD_OFFSET_STUDS = 15,

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
