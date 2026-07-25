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
	FLIGHT_DURATION_EXPONENT: number,
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
	RUNWAY_WIDTH_STUDS: number,
	BOX_DOUBLE_CHANCE: number,
	BOX_ROLL_DELAY_SECONDS: number,
	SWING_TIER_DISTANCE_SCALE: { number },
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
	-- Studs of landing distance per 1.0 of multiplier, AT TIER 1 (see
	-- SWING_TIER_DISTANCE_SCALE below for other tiers) -- distance = multiplier
	-- * this * the active tier's scale, a direct deterministic mapping, no
	-- speed/angle/gravity physics involved. 50 is derived, not guessed: a
	-- tier-1 perfect (2.0x) launch must land on band 5 (luck 25) -- see the
	-- written report for the arithmetic (it works back from the swing-to-
	-- runway gap, ~14.26 studs at the sweet-spot phase, plus the target
	-- band's stud range, to this number).
	DISTANCE_PER_MULTIPLIER = 50,
	-- Seconds a flight takes AT THE BASE reference distance (DISTANCE_PER_
	-- MULTIPLIER * SWEET_SPOT_MULTIPLIER, i.e. a tier-1 perfect launch) -- see
	-- FLIGHT_DURATION_EXPONENT below for how every OTHER distance (other
	-- tiers, other release timings) scales off this one anchor point. 1.8s is
	-- enough time for the chase camera and flight pose to read clearly at
	-- 60fps (~108 frames) while staying short enough that back-to-back reps
	-- don't feel padded -- unchanged reasoning from before tiers existed,
	-- just now describing one specific point on a curve instead of a flat
	-- constant.
	FLIGHT_DURATION_SECONDS = 1.8,
	-- Exponent duration scales BY relative to distance: duration =
	-- FLIGHT_DURATION_SECONDS * (distance / baseDistance) ^ this, where
	-- baseDistance is the tier-1 perfect-launch distance above. 1.0 would
	-- hold SPEED constant across every tier -- a tier-11 perfect launch
	-- (14.8x farther) would take 14.8x as long, ~27s, which drags badly. 0.0
	-- would hold DURATION constant regardless of distance -- the same
	-- tier-11 flight would cross ~1480 studs in the same 1.8s as tier 1's
	-- 100 studs, over 800 studs/sec, reading as a teleport, not a flight.
	-- 0.5 (square root) is the middle ground: speed still climbs
	-- noticeably with distance (a bigger tier reads as more powerful, ~55
	-- studs/sec at tier 1 up to ~214 studs/sec at tier 11), but duration
	-- grows far slower than distance does -- that same 14.8x-farther tier-11
	-- flight takes only ~3.8x as long (~6.9s): long enough to register as a
	-- big flight without dragging.
	FLIGHT_DURATION_EXPONENT = 0.5,
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
	-- travel while one band is under you). Unchanged this pass.
	RUNWAY_BAND_LENGTH_STUDS = 20,
	-- Studs wide (crosswise, perpendicular to the flight direction) each band
	-- is -- and, with the support platform below, the whole playable width.
	-- Quadrupled from the original 24: the flight path itself never drifts
	-- sideways (X stays fixed at the launch origin's X for the whole
	-- trajectory), so this was never load-bearing for containing the flight --
	-- it was just too narrow to feel like an open space rather than a strip.
	RUNWAY_WIDTH_STUDS = 96,
	-- Band COUNT and each band's LUCK value are no longer authored here at all
	-- -- see ReplicatedStorage/Config/LuckCurve.luau. The road is now as long
	-- as the generated curve says it is (#LuckCurve.VALUES bands), not a fixed
	-- number tuned by hand.

	-- ===== Mystery box (after landing, before reset -- see LaunchServer's
	-- onBoxPress) =====
	-- Probability [0,1] each press DOUBLES the luck and lets the player press
	-- again, instead of opening the box. The remaining probability (1 -
	-- this) OPENS the box and ends the sequence with whatever luck it
	-- currently holds -- there is no downside branch, only "double and
	-- continue" or "resolve now." Raise this and doubles get more common
	-- (longer average chains, bigger typical payouts, more variance); lower
	-- it and most boxes resolve in one or two presses.
	BOX_DOUBLE_CHANCE = 0.55,
	-- Seconds between a press being ACCEPTED and its result (open or double)
	-- reaching the client. This one number does two jobs: it's the "beat"
	-- that makes a press feel weighed rather than instant, and it IS the rate
	-- limit -- the server does not even evaluate the next press until this
	-- delay has fully elapsed (see onBoxPress's `pending` guard), so spamming
	-- the button faster than a human can never yields more than one roll per
	-- this many seconds, script or not.
	BOX_ROLL_DELAY_SECONDS = 0.4,

	-- ===== Swing tiers (scaling only -- see the written report). Which tier
	-- is ACTIVE is per-player state now, owned by PlayerProfile.luau (see
	-- PlayerProfile.getSwingTier/buyNextTier and ShopConfig.luau for what
	-- each tier costs) -- there used to be a single hard-coded
	-- ACTIVE_SWING_TIER read here by every launch; it's gone, and
	-- LaunchServer.server.luau's onRelease reads the releasing player's own
	-- tier instead. This array itself is UNCHANGED -- still just the
	-- distance-feel curve, nothing about who owns which tier. =====
	-- One distance multiplier per swing tier -- indexed straight by tier
	-- number (tier 1 reads index 1, tier 11 reads index 11; Luau arrays are
	-- 1-indexed, so tier number IS the index, no off-by-one). Applied on top
	-- of DISTANCE_PER_MULTIPLIER * multiplier, before
	-- ARC_HEIGHT_FRACTION/duration -- everything downstream (arc height,
	-- camera pull-back, flight duration) already scales off the resulting
	-- distance, so scaling distance here is the ONLY change needed to make a
	-- whole flight bigger. Bands themselves stay uniform length -- all of the
	-- progression lives in this array, not in the road's geometry. Tier 1 is
	-- fixed at 1.0x by definition (the reference DISTANCE_PER_MULTIPLIER/
	-- FLIGHT_DURATION_SECONDS are both anchored to it); tiers 2-11 were each
	-- derived by picking the reference game's target luck value, finding the
	-- band on THIS game's generated curve (see LuckCurve.luau) closest to
	-- that target, then solving for the scale that lands a perfect (2.0x)
	-- launch safely inside that band's stud range -- see the written report
	-- for the full table and the arithmetic behind each entry. Must stay
	-- exactly 11 entries long (one per tier); tier 11 is deliberately tuned
	-- to land just inside the LAST band on the road (see LuckCurve.VALUES),
	-- not past it.
	SWING_TIER_DISTANCE_SCALE = { 1.0, 3.0, 4.4, 6.4, 8.2, 9.2, 10.8, 11.6, 12.6, 13.8, 14.8 },
}

return LaunchConfig
