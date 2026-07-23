--!strict
-- Every feel-related constant for the launch prototype lives here, and ONLY here.
-- Tune the feel by editing numbers in this file -- no other script should hardcode
-- a physics/timing constant. Shared by both LaunchServer (authoritative) and
-- LaunchClient (cosmetic bar/camera/countup prediction only -- the server never
-- trusts the client's copy of these numbers for anything that affects the outcome).

export type LaunchConfig = {
	WORST_MULTIPLIER: number,
	EDGE_MULTIPLIER: number,
	SWEET_SPOT_MULTIPLIER: number,
	DISTANCE_PER_MULTIPLIER: number,
	FLIGHT_DURATION_SECONDS: number,
	ARC_HEIGHT_FRACTION: number,
	GRAVITY: number,
	RESET_DELAY: number,
	CAMERA_BEHIND_DISTANCE: number,
	CAMERA_HEIGHT_OFFSET: number,
	CAMERA_DOWNWARD_ANGLE_DEGREES: number,
	CAMERA_PULLBACK_FACTOR: number,
	SWING_PERIOD_SECONDS: number,
	SWING_ARC_HALF_ANGLE_DEGREES: number,
	SWING_ROPE_LENGTH: number,
	SWEET_SPOT_PHASE: number,
	SWEET_SPOT_WIDTH: number,
	RUNWAY_BAND_LENGTH_STUDS: number,
	RUNWAY_BAND_COUNT: number,
	RUNWAY_WIDTH_STUDS: number,
	RUNWAY_LABEL_INCREMENT: number,
}

local LaunchConfig: LaunchConfig = {
	-- ===== Launch power (multiplier, unchanged shape from the previous pass) =====
	-- Multiplier at the WORST possible release timing (the point in the cycle
	-- farthest from the sweet spot). Raising this shrinks the gap between a bad
	-- release and an edge-of-sweet-spot one.
	WORST_MULTIPLIER = 0.75,
	-- Multiplier at the EDGE of the sweet-spot window -- the top of the gradual
	-- ramp, just before it snaps.
	EDGE_MULTIPLIER = 1.5,
	-- Multiplier ANYWHERE inside the sweet-spot window -- a flat snap, not a peak
	-- of the ramp. Deliberately NOT continuous with EDGE_MULTIPLIER (1.5 -> 2.0 is
	-- a jump, not a slope): landing in the window has to read as a distinct hit,
	-- not the top of a curve you can back into by accident.
	SWEET_SPOT_MULTIPLIER = 2.0,

	-- ===== Scripted flight (this pass: no more velocity/physics -- see the
	-- written report for why) =====
	-- Studs of landing distance per 1.0 of multiplier -- distance = multiplier *
	-- this, a direct deterministic mapping, no speed/angle/gravity physics
	-- involved. 25 chosen so the sweet spot (2.0x) lands at 50 studs, matching
	-- the middle of what the OLD physics-simulated flight actually produced for a
	-- 2x release (35-65, noisily) -- same distances, now with zero variance.
	DISTANCE_PER_MULTIPLIER = 25,
	-- Seconds every flight takes, regardless of distance -- FIXED, not scaled by
	-- how far the launch goes (a weak release just crosses less ground in the
	-- same time, which incidentally makes a sweet-spot flight visibly faster --
	-- free spectacle). Too short and the camera moment barely registers; too long
	-- and repeated launches start to drag. 1.8s is enough time for the chase
	-- camera and flight pose to read clearly at 60fps (~108 frames) while staying
	-- short enough that back-to-back reps don't feel padded.
	FLIGHT_DURATION_SECONDS = 1.8,
	-- Peak arc height as a FRACTION of that flight's total distance (not a fixed
	-- stud value) -- a bigger release automatically gets a proportionally
	-- bigger, more dramatic arc, which is also exactly what the camera's
	-- pull-back (CAMERA_PULLBACK_FACTOR below) scales off of. 0.35 gives a
	-- clearly visible rise (~17.5 studs at the 50-stud sweet-spot distance)
	-- without reading as absurd.
	ARC_HEIGHT_FRACTION = 0.35,

	-- ===== Physics environment (only affects normal walking-around now, not
	-- flight, which is fully scripted) =====
	-- Workspace.Gravity (studs/sec^2), applied once at server startup. Roblox's
	-- default is 196.2. No longer touches the flight arc at all (see
	-- ARC_HEIGHT_FRACTION) -- kept only because it still governs the player's
	-- ordinary jump/fall feel while riding up to a launch.
	GRAVITY = 130,

	-- ===== Reset (server) =====
	-- Seconds to pause after landing (so the player can read the distance)
	-- before they're placed back on the swing and can release again. Keep this
	-- under ~2s per the fast-reset requirement.
	RESET_DELAY = 0.75,

	-- ===== Flight camera (the payoff moment -- behind-and-above chase shot) =====
	-- Base studs BEHIND the character (opposite the flight direction) the camera
	-- sits at. Smaller = closer, more intense/speed-y feeling, more risk of the
	-- character filling too much of frame; bigger = calmer, more ground visible
	-- ahead at once.
	CAMERA_BEHIND_DISTANCE = 18,
	-- Studs the camera sits above the CHARACTER's current height (tracked
	-- continuously through the arc, not a fixed world height) -- this is what
	-- keeps the character consistently framed in the upper-middle of the screen
	-- regardless of how high the arc rises, rather than drifting out of frame at
	-- the peak of a big sweet-spot flight.
	CAMERA_HEIGHT_OFFSET = 8,
	-- Degrees the camera tilts down from level. Needs to be noticeably more than
	-- "just enough to look at the character" (which the BEHIND_DISTANCE/
	-- HEIGHT_OFFSET ratio above already gives, ~24 degrees) so the ground --
	-- farther below and ahead than the character -- fills the lower part of the
	-- frame instead of the character sitting dead-center. Too little and this
	-- reads like a level chase cam with no sense of height; too much and the
	-- character crowds the top edge of frame.
	CAMERA_DOWNWARD_ANGLE_DEGREES = 35,
	-- Extra camera distance added per stud of THIS FLIGHT's arc height (see
	-- ARC_HEIGHT_FRACTION) -- "pull back as the arc gets bigger," computed once
	-- per launch, not re-adjusted mid-flight. 1.0 is a starting guess (equal
	-- parts arc height and pull-back); the first thing to retune if a
	-- sweet-spot flight ever clips past the edge of frame or a weak one looks
	-- too zoomed-out.
	CAMERA_PULLBACK_FACTOR = 1.0,

	-- ===== The swing (unchanged from the previous pass) =====
	-- Seconds for one full back-and-forth cycle. Lower = faster/twitchier sweep,
	-- harder to time. Higher = slower, more forgiving, but more waiting between
	-- release opportunities.
	SWING_PERIOD_SECONDS = 2.4,
	-- Degrees the swing travels from vertical on EACH side (so the total sweep is
	-- double this). Bigger = a larger, more dramatic visual arc and a taller rise
	-- at the extremes; does not change timing (period is independent of arc size
	-- for this scripted pendulum, unlike a real one).
	SWING_ARC_HALF_ANGLE_DEGREES = 35,
	-- Studs from the fixed pivot (SwingPivot) to the seat. Longer = the seat
	-- travels a bigger physical arc at the same angular size/period, reading as
	-- slower, weightier motion; also sets how high the pivot/frame needs to be
	-- built in the world.
	SWING_ROPE_LENGTH = 10,
	-- Where in the cycle (0-1, fraction of SWING_PERIOD_SECONDS) counts as the
	-- sweet spot. 0.25 = the forward extreme of the arc, where the swing
	-- momentarily pauses before reversing -- chosen deliberately over the center
	-- (phase 0 or 0.5): the center is crossed TWICE per cycle (once each
	-- direction) and looks IDENTICAL on a position-only bar, so it can't be an
	-- unambiguous sweet spot. Each extreme is visited exactly once per cycle.
	SWEET_SPOT_PHASE = 0.25,
	-- Full width of the sweet-spot window, as a fraction of SWING_PERIOD_SECONDS,
	-- centered on SWEET_SPOT_PHASE (half on each side). Outside this window, the
	-- multiplier ramps gradually from WORST_MULTIPLIER up to EDGE_MULTIPLIER;
	-- anywhere inside it, the multiplier snaps flat to SWEET_SPOT_MULTIPLIER. THE
	-- single most feel-critical number here -- see the written report for why
	-- 0.12 was chosen as the starting point and what to retune first.
	SWEET_SPOT_WIDTH = 0.12,

	-- ===== Rainbow road: coloured distance bands under the flight path (built by
	-- RunwayBuilder.server.luau -- generated at runtime, not hand-authored in the
	-- project file, since it's a repeated/formulaic set of parts) =====
	-- Studs each COLOURED band spans along the flight direction (how far you
	-- travel while one band is under you). Kept as-is this pass -- the length is
	-- good; only the width and the labeling scheme changed.
	RUNWAY_BAND_LENGTH_STUDS = 20,
	-- How many coloured bands the runway has, one full colour cycle across all
	-- of them. 10 * 20 = 200 studs of runway, still 4x the 50-stud maximum
	-- possible landing distance ("well past" it).
	RUNWAY_BAND_COUNT = 10,
	-- Studs wide (crosswise, perpendicular to the flight direction) each band
	-- is -- and, with the support platform below, the whole playable width.
	-- Quadrupled from the original 24: the flight path itself never drifts
	-- sideways (X stays fixed at the launch origin's X for the whole
	-- trajectory), so this was never load-bearing for containing the flight --
	-- it was just too narrow to feel like an open space rather than a strip.
	RUNWAY_WIDTH_STUDS = 96,
	-- The number each successive band's label counts up by -- 5, 10, 15, 20...
	-- -- regardless of RUNWAY_BAND_LENGTH_STUDS. This is a plain label index
	-- multiplier now, not a stud measurement (it used to be, back when bands
	-- were shorter and their own length WAS the distance shown -- see the
	-- written report for why that stopped being true): band i's label is
	-- (i+1) * this, full stop, whatever the bands' actual physical length is.
	RUNWAY_LABEL_INCREMENT = 5,
}

return LaunchConfig
