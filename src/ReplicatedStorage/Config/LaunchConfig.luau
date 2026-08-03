--!strict
-- Every feel-related constant for the launch prototype lives here, and ONLY here.
-- Tune the feel by editing numbers in this file -- no other script should hardcode
-- a physics/timing constant. Shared by both LaunchServer (authoritative) and
-- LaunchClient (cosmetic bar/camera/countup prediction only -- the server never
-- trusts the client's copy of these numbers for anything that affects the outcome).

export type LaunchConfig = {
	WORST_MULTIPLIER: number,
	EDGE_MULTIPLIER: number,
	SWEET_SPOT_EDGE_MULTIPLIER: number,
	SWEET_SPOT_MULTIPLIER: number,
	SWEET_SPOT_SNAP_THRESHOLD: number,
	OUTCOME_BANDS: { { threshold: number, text: string } },
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
	SWING_BASE_PIVOT_HEIGHT_ABOVE_GROUND: number,
	RIDER_SEAT_HEIGHT_OFFSET: number,
	SWING_MOUNT_RADIUS_STUDS: number,
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
	-- Multiplier at the EDGE of the sweet-spot window, approached from OUTSIDE --
	-- the top of the gradual outer ramp, just before it jumps.
	EDGE_MULTIPLIER = 1.5,
	-- Multiplier at the EDGE of the sweet-spot window, approached from INSIDE --
	-- the bottom of the inner ramp (see SWEET_SPOT_MULTIPLIER below). Deliberately
	-- NOT continuous with EDGE_MULTIPLIER (1.5 -> 1.8 is a jump, not a slope):
	-- landing in the window has to read as a distinct hit, not the top of a curve
	-- you can back into by accident. This gap is the one thing that must NOT be
	-- softened -- see the written report.
	SWEET_SPOT_EDGE_MULTIPLIER = 1.8,
	-- Multiplier at DEAD CENTRE of the sweet-spot window -- the peak of the inner
	-- ramp and the maximum possible multiplier overall. Anywhere inside the
	-- window now grades smoothly from SWEET_SPOT_EDGE_MULTIPLIER at the boundary
	-- up to this value at the centre, instead of a flat snap -- so hitting the
	-- window is guaranteed to feel like a hit (the 1.5->1.8 jump), but centring
	-- it still rewards extra precision instead of being an identical plateau.
	SWEET_SPOT_MULTIPLIER = 2.0,
	-- Any GRADED value at or above this snaps up to exactly SWEET_SPOT_MULTIPLIER.
	-- Landing on the single exact centre phase is luck, not skill -- this turns
	-- "close enough to centre" into a genuine, reachable perfect instead of a
	-- vanishingly rare bullseye. Only affects the TOP of the inner ramp (see
	-- launchMultiplier in LaunchServer/LaunchClient) -- the outer ramp and the
	-- 1.5->1.8 jump are untouched. Also doubles as the top OUTCOME_BANDS cutoff
	-- below, since anything that snaps to 2.0 should read as "Perfect!" too.
	-- 1.90 snaps the top HALF of the inner ramp's half-width (a graded value
	-- reaches 1.90 at 50% of the way from edge to centre) -- so the "perfect"
	-- zone is 50% of the full sweet-spot width, not a sliver you can only find
	-- by luck.
	SWEET_SPOT_SNAP_THRESHOLD = 1.90,

	-- ===== Scripted flight (this pass: no more velocity/physics -- see the
	-- written report for why) =====
	-- Studs of landing distance per 1.0 of multiplier, AT TIER 1 (see
	-- SWING_TIER_DISTANCE_SCALE below for other tiers) -- distance = multiplier
	-- * this * the active tier's scale, a direct deterministic mapping, no
	-- speed/angle/gravity physics involved. 100 is derived, not guessed: a
	-- tier-1 perfect (2.0x) launch must land on band 5 (luck 25), UNCHANGED
	-- from before RUNWAY_BAND_LENGTH_STUDS doubled to 40 -- see the written
	-- report for the arithmetic. Exactly double the previous value (50)
	-- because RUNWAY_BAND_LENGTH_STUDS below also exactly doubled (from 20 to
	-- 40, to give the road's number signs more visual breathing room): every
	-- distance in the game is DISTANCE_PER_MULTIPLIER * multiplier * tier
	-- scale, so scaling this constant by the same factor as the band depth
	-- scales EVERY flight's distance by that factor too, which is what keeps
	-- every tier landing on the exact same band as before despite the deeper
	-- bands. The swing-to-runway gap also had to scale by the same factor --
	-- see the Baseplate's Size/Position in default.project.json.
	DISTANCE_PER_MULTIPLIER = 100,
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
	-- baseDistance is the tier-1 perfect-launch distance above. Because
	-- baseDistance and every flight's distance scale by the SAME factor (see
	-- DISTANCE_PER_MULTIPLIER/RUNWAY_BAND_LENGTH_STUDS), this ratio -- and
	-- therefore duration -- is UNAFFECTED by that scaling; only the
	-- illustrative stud numbers below changed. 1.0 would hold SPEED constant
	-- across every tier -- a tier-11 perfect launch (14.8x farther) would
	-- take 14.8x as long, ~27s, which drags badly. 0.0 would hold DURATION
	-- constant regardless of distance -- the same tier-11 flight would cross
	-- ~2960 studs in the same 1.8s as tier 1's 200 studs, over 1600
	-- studs/sec, reading as a teleport, not a flight. 0.5 (square root) is
	-- the middle ground: speed still climbs noticeably with distance (a
	-- bigger tier reads as more powerful), but duration grows far slower
	-- than distance does -- that same 14.8x-farther tier-11 flight takes
	-- only ~3.8x as long (~6.9s): long enough to register as a big flight
	-- without dragging.
	--
	-- SPEED DOUBLED AS OF THE BAND-DEPTH-DOUBLING PASS (see the written
	-- report): duration only depends on the distance/baseDistance RATIO,
	-- which is unchanged, so every flight now covers twice the studs (~111
	-- studs/sec at tier 1, ~427 studs/sec at tier 11, up from ~55/~214) in
	-- the SAME duration as before. Left unadjusted deliberately this pass --
	-- see the written report for why and the proposed fix (scale
	-- FLIGHT_DURATION_SECONDS by the same factor to restore the original
	-- per-tier speeds exactly).
	FLIGHT_DURATION_EXPONENT = 0.5,
	-- Peak arc height as a FRACTION of that flight's total distance (not a fixed
	-- stud value) -- a bigger release automatically gets a proportionally
	-- bigger, more dramatic arc, which is also exactly what the camera's
	-- pull-back (CAMERA_PULLBACK_FACTOR below) scales off of. 0.35 gives a
	-- clearly visible rise (~35 studs at the 100-stud DISTANCE_PER_MULTIPLIER
	-- distance) without reading as absurd.
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
	-- BASE studs from the pivot to the seat, at tier 1 (scale = 1.0) -- this
	-- number itself NEVER changes by tier; SwingGeometry.luau derives each
	-- tier's EFFECTIVE rope length as this * scale, and the pivot's own
	-- height above ground scales by the same `scale` right alongside it, so
	-- the seat's height as a fraction of the frame stays constant and the
	-- swing's physical arc radius grows with the frame instead of staying
	-- fixed at this tier-1 size forever (see the written report). Longer =
	-- the seat travels a bigger physical arc at the same angular size/
	-- period, reading as slower, weightier motion.
	SWING_ROPE_LENGTH = 10,
	-- BASE pivot height above ground, at tier 1 (scale = 1.0) -- matches
	-- SwingPivot's placed Y (13) in default.project.json, since the
	-- Baseplate's own top also sits at world Y = 0. A CONFIG constant, not
	-- read from whichever SwingPivot part happens to exist in Workspace, so
	-- SwingGeometry.luau's pivotYForScale works identically for the one
	-- real game swing (LaunchServer.server.luau) and for every independent
	-- swing the dev-only gallery builds (SwingGallery.server.luau), none of
	-- which share a single canonical pivot any more.
	SWING_BASE_PIVOT_HEIGHT_ABOVE_GROUND = 13,
	-- Studs ABOVE the seat's own Y a standing rider's root/pelvis sits --
	-- read by BOTH LaunchServer (onRelease's startPosition, the flight's
	-- actual launch height) and LaunchClient (riderCFrame, the visual
	-- riding position every RenderStepped) from this ONE constant, never
	-- two independently-tuned copies -- see the written report for the bug
	-- this fixes: the two used to disagree, producing a visible vertical pop
	-- at the instant of release as the character snapped from the client's
	-- riding height to the server's flight-start height. Y-only, so this
	-- cannot affect DISTANCE_PER_MULTIPLIER, band reach, or anything else
	-- horizontal -- see the written report for how that was verified, not
	-- assumed.
	RIDER_SEAT_HEIGHT_OFFSET = 2.0,
	-- Studs: how close a GROUNDED player's HumanoidRootPart must come to
	-- their OWN swing seat's CURRENT (moving) position -- swingSeatPosition
	-- (swingTheta(swingPhase(laneIndex)), pivot), the exact same closed-form
	-- point onRelease launches from -- before LaunchServer's proximity check
	-- auto-mounts them. Deliberately modest: at tier 1 the seat's own rest
	-- position already sits only SWING_PIVOT_Z - SWING_ROPE_LENGTH studs from
	-- the pivot, and BaseGeometry.luau places each base's own front row only
	-- BASE_ROW_START_STUDS (10) behind that same pivot -- too large a radius
	-- here would make the seat's own idle position (or a player just
	-- standing at their base) reach into mount range on its own. Kept small
	-- enough to read as "you walked up to it," not "you were nearby."
	SWING_MOUNT_RADIUS_STUDS = 5,
	-- Where in the cycle (0-1, fraction of SWING_PERIOD_SECONDS) counts as the
	-- sweet spot. 0.25 = the forward extreme of the arc, where the swing
	-- momentarily pauses before reversing -- chosen deliberately over the center
	-- (phase 0 or 0.5): the center is crossed TWICE per cycle (once each
	-- direction) and looks IDENTICAL on a position-only bar, so it can't be an
	-- unambiguous sweet spot. Each extreme is visited exactly once per cycle.
	SWEET_SPOT_PHASE = 0.25,
	-- Full width of the sweet-spot window, as a fraction of SWING_PERIOD_SECONDS,
	-- centered on SWEET_SPOT_PHASE (half on each side). Outside this window, the
	-- multiplier ramps gradually from WORST_MULTIPLIER up to EDGE_MULTIPLIER; on
	-- crossing into it, the multiplier jumps to SWEET_SPOT_EDGE_MULTIPLIER and then
	-- ramps again, smoothly, up to SWEET_SPOT_MULTIPLIER at dead centre -- two
	-- ramps with a deliberate jump between them, not one continuous curve. THE
	-- single most feel-critical number here -- see the written report for why
	-- 0.12 was chosen as the starting point and what to retune first.
	SWEET_SPOT_WIDTH = 0.12,

	-- ===== Outcome text: the short result word shown on release (see
	-- LaunchClient's outcomeBandIndex) -- purely cosmetic feedback, reads
	-- the SAME graded multiplier the bar/scoring already produced, just mapped to
	-- a word instead of a number. Ordered HIGHEST threshold first; the first entry
	-- whose threshold the multiplier meets or beats wins, so this list must stay
	-- sorted descending and cover down to WORST_MULTIPLIER with no gaps. Styling
	-- (colour/size/font) lives in LaunchClient, keyed by position in this array --
	-- change the wording here freely, but keep the array the same length (5) or
	-- update the client's parallel style list to match. =====
	OUTCOME_BANDS = {
		-- Matches SWEET_SPOT_SNAP_THRESHOLD -- anything that snaps to a perfect
		-- 2.0x reads as a perfect result, not a coincidence of two separate numbers.
		{ threshold = 1.95, text = "Perfect!" },
		-- The rest of the graded interior of the sweet spot (1.8 up to the snap).
		{ threshold = 1.8, text = "Great!" },
		-- The top slice of the OUTER ramp -- a near miss close enough to the
		-- window's edge (1.5) to deserve positive feedback, not a neutral shrug.
		{ threshold = 1.3, text = "Good" },
		-- The broad middle of the outer ramp -- neither a near miss nor a bad one.
		{ threshold = 1.0, text = "Okay" },
		-- The low end (down to WORST_MULTIPLIER, 0.75) -- deliberately gentle
		-- wording (see the written report): this game is launched hundreds of
		-- times, and a harsh word on a fifth of them would grate fast.
		{ threshold = 0.75, text = "Lock in.." },
	},

	-- ===== Rainbow road: coloured distance bands under the flight path (built by
	-- RunwayBuilder.server.luau -- generated at runtime, not hand-authored in the
	-- project file, since it's a repeated/formulaic set of parts) =====
	-- Studs each COLOURED band spans along the flight direction (how far you
	-- travel while one band is under you). DOUBLED again, from 20 to 40 --
	-- see the written report: the road's number signs (RunwayBuilder's
	-- floating "sign" parts, decoupled from this band's own length since a
	-- couple of passes ago) still looked cramped sitting over a comparatively
	-- shallow 20-stud coloured strip, even though the signs themselves don't
	-- need this to be any bigger to render large text. This and
	-- DISTANCE_PER_MULTIPLIER above (and the Baseplate's Size/Position in
	-- default.project.json, which sets the swing-to-runway gap) all have to
	-- scale together by the exact same factor, every time, or the floor-
	-- division band lookup in LaunchServer's bandLuckForLandingZ drifts and a
	-- tier that used to reach band N reaches a different one.
	RUNWAY_BAND_LENGTH_STUDS = 40,
	-- Studs wide (crosswise, perpendicular to the flight direction) each band
	-- is -- and, with the support platform below, the whole playable width.
	-- The flight path itself never drifts sideways (X stays fixed at the
	-- launch origin's X for the whole trajectory), so this was never load-
	-- bearing for containing the flight -- purely cosmetic, like the band
	-- length above. WIDENED from 96 to 240 -- matches the Baseplate's own
	-- width (default.project.json) so the coloured road now spans the FULL
	-- platform edge-to-edge instead of a narrower strip down the middle, and
	-- -- the actual reason for the change this pass -- gives the road number
	-- labels enough available WIDTH to render large even for the longest
	-- spelled-out values ("100,000"): a label's width budget is capped by
	-- this number regardless of how tall its host sign is, so widening the
	-- road is what let the numbers grow, not just a bigger sign. See
	-- RunwayBuilder.server.luau and the written report.
	RUNWAY_WIDTH_STUDS = 240,
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
