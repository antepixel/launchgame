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
	RELEASE_PING_COMPENSATION_MAX_SECONDS: number,
	OUTCOME_BANDS: { { threshold: number, text: string } },
	LAST_BAND_OUTCOME_TEXT: string,
	OUTCOME_RAINBOW_CYCLES_PER_SECOND: number,
	OUTCOME_RAINBOW_SATURATION: number,
	OUTCOME_RAINBOW_VALUE: number,
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
	SWING_MOUNT_RADIUS_MARKER_COLOR: Color3,
	SWING_MOUNT_RADIUS_MARKER_TRANSPARENCY: number,
	SWING_MOUNT_RADIUS_MARKER_MATERIAL: Enum.Material,
	SWING_MOUNT_RADIUS_MARKER_THICKNESS: number,
	SWING_MOUNT_RADIUS_MARKER_Y_OFFSET: number,
	SWING_RETURN_CLEARANCE_STUDS: number,
	SWEET_SPOT_PHASE: number,
	SWEET_SPOT_WIDTH: number,
	RUNWAY_BAND_LENGTH_STUDS: number,
	RUNWAY_WIDTH_STUDS: number,
	BOX_DOUBLE_CHANCE: number,
	BOX_PRESS_COOLDOWN_SECONDS: number,
	BOX_SUPPRESSED_HUD_NAMES: { string },
	BOX_WORLD_SIZE_STUDS: number,
	BOX_WORLD_DISTANCE_STUDS: number,
	BOX_WORLD_HEIGHT_OFFSET_STUDS: number,
	BOX_WORLD_YAW_DEGREES: number,
	BOX_WORLD_PITCH_DEGREES: number,
	BOX_WORLD_COLOR: Color3,
	BOX_WORLD_MATERIAL: Enum.Material,
	BOX_WORLD_QUESTION_COLOR: Color3,
	BOX_WORLD_QUESTION_PIXELS_PER_STUD: number,
	BOX_WORLD_CLICK_DISTANCE_STUDS: number,
	BOX_WORLD_LUCK_LABEL_HEIGHT_STUDS: number,
	BOX_WORLD_LUCK_LABEL_WIDTH_PIXELS: number,
	BOX_WORLD_LUCK_LABEL_HEIGHT_PIXELS: number,
	BOX_CAMERA_DISTANCE_STUDS: number,
	BOX_CAMERA_PITCH_DEGREES: number,
	BOX_CAMERA_TRANSITION_SECONDS: number,
	BOX_HOVER_AMPLITUDE_STUDS: number,
	BOX_HOVER_PERIOD_SECONDS: number,
	BOX_HOVER_SPIN_DEGREES_PER_SECOND: number,
	BOX_SHAKE_FREQUENCY_HZ: number,
	BOX_NUDGE_AMPLITUDE_STUDS: number,
	BOX_NUDGE_ROTATION_DEGREES: number,
	BOX_NUDGE_SECONDS: number,
	BOX_THRASH_AMPLITUDE_STUDS: number,
	BOX_THRASH_ROTATION_DEGREES: number,
	BOX_THRASH_SECONDS: number,
	BOX_THRASH_BUILD_EXPONENT: number,
	BOX_OPEN_BURST_SCALE: number,
	BOX_OPEN_BURST_SECONDS: number,
	BOX_OPEN_BURST_SPIN_DEGREES: number,
	SWING_TIER_DISTANCE_SCALE: { number },
	SWING_TIER_SNAP_THRESHOLD: { number },
	REMOTE_LANE_RESCAN_INTERVAL_SECONDS: number,
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
	-- 1.5->1.8 jump are untouched.
	--
	-- THIS IS THE FALLBACK, NOT THE VALUE EVERY TIER USES: SWING_TIER_SNAP_
	-- THRESHOLD below overrides it per tier, and tier 11 does. It also does NOT
	-- double as the top OUTCOME_BANDS cutoff any more -- see that table's own
	-- comment for why a second, separately-written copy of "what counts as
	-- perfect" is exactly how the HUD came to disagree with the launch.
	--
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
	-- their OWN swing pivot's X/Z -- HORIZONTAL distance only, Y dropped
	-- entirely -- before LaunchServer's proximity check auto-mounts them
	-- (see checkProximityMounts).
	--
	-- MEASURED FROM THE PIVOT, NOT THE SEAT (see the written report): the
	-- seat is a small target constantly swinging through
	-- SWING_ARC_HALF_ANGLE_DEGREES either side of vertical -- measuring
	-- against its live position meant a player effectively had to walk into
	-- the seat itself, at whatever instant the Heartbeat sampled it, to ever
	-- register. The pivot's X/Z never move (SwingBuilder.build only ever
	-- touches its Y -- see SwingGeometry.pivotYForScale) -- measuring
	-- against that instead, with Y dropped, turns mounting into a fixed
	-- circle on the ground around the frame's own footprint, and makes a
	-- tier-11 frame (whose pivot sits far higher off the ground than tier
	-- 1's) exactly as easy to mount as tier 1, since height was never part
	-- of the check to begin with.
	--
	-- SIZED TO THE FRAME, NOT THE SEAT: SwingTierVisuals' footprint clamp
	-- caps every tier-7-and-up frame at ~35.01 studs wide (half-width
	-- ~17.5), centred on the pivot's own X -- see FOOTPRINT_SCALE_MAX's own
	-- comment. 18 clears that half-width with a small margin (covers
	-- standing anywhere near the frame, not just dead-centre on the seat)
	-- while staying well clear of the ADJACENT lane: lanes sit
	-- LaneConfig.laneCenterX's own 40-stud pitch apart, so two neighbouring
	-- mount circles (18 + 18 = 36) leave a 4-stud gap between them -- this
	-- circle can never reach, let alone overlap, an adjacent lane's own
	-- pivot (40 studs away, more than double this radius).
	SWING_MOUNT_RADIUS_STUDS = 18,
	-- ===== Mount radius marker (see the written report): a flat, non-
	-- collidable disc MapBuilder.server.luau draws on the ground at every
	-- lane's own pivot X/Z, radius SWING_MOUNT_RADIUS_STUDS -- a visible
	-- "here's where auto-mount kicks in" hitbox, built once for all
	-- LANE_COUNT lanes whether or not that lane's player has joined yet,
	-- same as the rest of the plot dressing. Colour/transparency broken out
	-- here, separately from the radius itself, purely so this can be tuned
	-- (or made invisible -- Transparency = 1) without touching the actual
	-- mount-detection math above. =====
	SWING_MOUNT_RADIUS_MARKER_COLOR = Color3.fromRGB(90, 200, 255),
	-- High by design -- a loud, opaque circle would compete with the frame
	-- and the ground beneath it for attention; this should read as a faint
	-- "range ring," visible on inspection, not a bright decal.
	SWING_MOUNT_RADIUS_MARKER_TRANSPARENCY = 0.75,
	-- Neon reads clearly as an indicator/overlay rather than a physical
	-- ground material, distinguishing it at a glance from the mat/path/edge
	-- parts (all Concrete/Pebble) it sits alongside.
	SWING_MOUNT_RADIUS_MARKER_MATERIAL = Enum.Material.Neon,
	-- Vertical thickness of the disc -- thin, a decal-like marker, not a
	-- physical slab.
	SWING_MOUNT_RADIUS_MARKER_THICKNESS = 0.15,
	-- Studs above groundY the disc's CENTER sits -- just enough to clear the
	-- bare ground plane it's drawn on (the swing pivot sits on open ground,
	-- not on the mat -- see LaneConfig.SWING_PIVOT_Z vs. BaseConfig.
	-- BASE_PLOT_CENTER_Z) without z-fighting it.
	SWING_MOUNT_RADIUS_MARKER_Y_OFFSET = 0.05,
	-- Studs ADDED to LaneConfig.SWING_PIVOT_Z (never subtracted -- this is the
	-- spawn/base side of the pivot, the same side SPAWN_Z sits on) to get a
	-- GROUNDED player's return position after a flight's reward sequence
	-- resolves (see LaunchServer.server.luau's onReturnToSwing) -- X is that
	-- lane's own laneCenterX, Y is groundY, so this is the only geometry this
	-- number has to get right.
	--
	-- Must clear SWING_MOUNT_RADIUS_STUDS, or a player who returns gets
	-- auto-remounted the instant they land there. Simpler to verify than it
	-- used to be: checkProximityMounts now measures pure HORIZONTAL (X/Z)
	-- distance from the PIVOT, not 3D distance from the live swinging seat
	-- (see SWING_MOUNT_RADIUS_STUDS's own comment) -- and the return
	-- position shares its X exactly with the pivot's own X (both are that
	-- lane's laneCenterX), so the distance being checked is just this
	-- constant itself, with no tier, phase, or Y term left to sample. 22 >
	-- 18 with a clean 4-stud margin, at every tier, unconditionally.
	SWING_RETURN_CLEARANCE_STUDS = 22,
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

	-- ===== LATENCY COMPENSATION ON RELEASE (see REPORT.md). The server grades a
	-- release from the phase at the instant it PROCESSES the Release event, which
	-- is one network hop later than the instant the player actually clicked --
	-- always later, never earlier, so the error is a systematic bias and not just
	-- noise. LaunchServer's onRelease now subtracts the player's own measured
	-- network latency from the sampled time before grading. THE MULTIPLIER ONLY:
	-- the launch ORIGIN still reads the live seat, so nothing about where the
	-- flight starts moves, and the multiplier-to-distance mapping is untouched.
	--
	-- MEASURED BY THE SERVER, NOT SENT BY THE CLIENT. Player:GetNetworkPing() is
	-- the engine's own measurement of the connection; a modified client cannot
	-- set it, so this opens no exploit surface. (Handing the client its own
	-- release timestamp WOULD, which is why that option was rejected.)
	--
	-- THIS IS THE CLAMP, and it exists because a rolling average can spike: an
	-- absurd reading must not be able to rewind the phase arbitrarily. Applied as
	-- math.clamp(ping, 0, this) -- the zero floor matters too, so a negative or
	-- NaN reading can never push the phase FORWARD.
	--
	-- WHY 0.12s. Two bounds, and the smaller one wins:
	--   * it must comfortably cover real one-way latency. Roblox players on a
	--     distant region sit in the 20-120ms band, and at tier 11 the whole snap
	--     window is +-36ms, so anything less than ~100ms would leave the worst-
	--     connected players still systematically short.
	--   * it must stay BELOW the sweet spot's own half-width
	--     (SWEET_SPOT_WIDTH / 2 * SWING_PERIOD_SECONDS = 0.144s). Above that, a
	--     bad ping reading could rewind a release from outside the window to
	--     inside it -- compensation would stop correcting the outcome and start
	--     inventing one. 0.12 sits under that ceiling with room to spare.
	-- The residual after correction is the JITTER around the average, not the
	-- average itself; see REPORT.md for the before/after tolerance numbers.
	RELEASE_PING_COMPENSATION_MAX_SECONDS = 0.12,

	-- ===== Outcome text: the short result word shown on release (see
	-- LaunchClient's outcomeBandIndex) -- purely cosmetic feedback, reads
	-- the SAME graded multiplier the bar/scoring already produced, just mapped to
	-- a word instead of a number. Ordered HIGHEST threshold first; the first entry
	-- whose threshold the multiplier meets or beats wins, so this list must stay
	-- sorted descending and cover down to WORST_MULTIPLIER with no gaps. Styling
	-- (colour/size/font) lives in LaunchClient, keyed by position in this array --
	-- change the wording here freely, but keep the array the same length (5) or
	-- update the client's parallel style list to match.
	--
	-- ONE ENTRY IS NOT REACHED FROM THIS TABLE: the last-band ring below
	-- (LAST_BAND_OUTCOME_TEXT) is decided by WHERE THE FLIGHT LANDS, not by a
	-- multiplier threshold, so it cannot live in a threshold-ordered list. It
	-- overrides the lookup entirely when it applies -- see LaunchClient's
	-- landsOnLastBand. =====
	OUTCOME_BANDS = {
		-- SWEET_SPOT_MULTIPLIER ITSELF -- i.e. "this launch actually snapped."
		-- NOT a copy of any snap threshold, which is what this used to be.
		--
		-- BUG (see REPORT.md): the cutoff was a hand-written 1.95 whose comment
		-- claimed it "matches SWEET_SPOT_SNAP_THRESHOLD" -- which was 1.90, and
		-- is now per-tier anyway (SWING_TIER_SNAP_THRESHOLD). Any number written
		-- here other than the snapped value is a second, independent definition
		-- of "perfect" that has to be kept in step with every tier's threshold by
		-- hand, forever. Testing for the snapped value instead makes that
		-- impossible by construction: a launch reads "Perfect!" if and only if
		-- launchMultiplier returned SWEET_SPOT_MULTIPLIER, at whatever threshold
		-- that tier snapped at. Numerically identical to the old 1.95 for every
		-- tier that exists today (no tier's graded ramp can produce a value in
		-- [1.95, 2.0) -- the highest snap threshold IS 1.95, so anything that
		-- reaches it has already been replaced by 2.0).
		{ threshold = 2.0, text = "Perfect!" },
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

	-- ===== THE LAST-BAND RING: the outcome word for a flight that comes down on
	-- the FINAL band of the road (band #LuckCurve.VALUES - 1, band 73 today) --
	-- the ring of road immediately before the platform. It replaces whatever
	-- OUTCOME_BANDS above would have said, and nothing else about that lookup
	-- changes.
	--
	-- WHY IT IS NOT A THRESHOLD. Every other outcome word is a function of the
	-- multiplier alone. This one is a function of WHERE THE FLIGHT LANDS, which
	-- is the multiplier scaled by the tier's own SWING_TIER_DISTANCE_SCALE and
	-- measured against the road -- so the same 1.92x that is one band short at
	-- tier 11 is barely a third of the way down the road at tier 5. Deriving it
	-- from the landing (see LaunchClient's landsOnLastBand, which mirrors
	-- LaunchServer's own bandLuckForLandingZ) is also what keeps this honest for
	-- free: it reads the same seat position, the same tier scale and the same
	-- band arithmetic the server scores the flight with, so the word cannot
	-- claim a band the flight did not reach.
	--
	-- WHERE IT APPLIES. Only where the flight can reach the last band at all,
	-- and that falls out of the same arithmetic rather than needing a per-tier
	-- flag: at tiers 1-10 even a snapped 2.0x stops at band 68 (tier 10's best),
	-- so this word is unreachable there and those tiers label EXACTLY as they
	-- did before it existed -- verified over 4,000,000 sampled phases per tier,
	-- see REPORT.md. Tier 11 is the only tier this can fire on today.
	--
	-- THE WORDING. This is the one outcome in the game that is a near miss and a
	-- maximum at the same time: band 73 pays the top of the luck curve (100,000)
	-- and is also the one thing standing between the player and the platform.
	-- "One Step Short!" says both -- "step" is small and countable and maps to
	-- the single coloured band the player can see they stopped on, and "short"
	-- refuses to let it read as a win. A generic "So Close!" would fit a 1.5x
	-- just as well and throws away the specificity that makes this beat land;
	-- anything built around "Last Band" reads as an achievement, which is
	-- exactly the mistake the "Perfect!" bug above was already making.
	LAST_BAND_OUTCOME_TEXT = "One Step Short!",

	-- ===== THE PERFECT TEXT IS A MOVING RAINBOW (see REPORT.md and LaunchHud's
	-- own outcomeRainbow block). Hue travels ALONG the letters rather than the
	-- whole string pulsing as one colour, which is why it is a UIGradient whose
	-- ColorSequence is rebuilt per frame rather than a TextColor3 tween.
	--
	-- ONLY A PERFECT GETS IT. Every other outcome keeps the flat colour from
	-- LaunchHud's OUTCOME_STYLES, untouched.
	--
	-- Full hue rotations per second. The outcome word is on screen for the
	-- flight plus RESET_DELAY -- a few seconds -- so 0.6 gives it two or three
	-- visible sweeps at a pace that reads as motion rather than as a strobe.
	-- This is the number to lower first if it ever feels frantic; there is no
	-- reason to raise it.
	OUTCOME_RAINBOW_CYCLES_PER_SECOND = 0.6,
	-- Saturation and value fed to Color3.fromHSV for every keypoint. 0.9/1.0 is
	-- vivid without going full neon: at S = 1 the blues and magentas read as
	-- cheap against the sky, and at V below 1 the whole thing loses to the
	-- gold "Luck x..." headline sitting above it.
	OUTCOME_RAINBOW_SATURATION = 0.9,
	OUTCOME_RAINBOW_VALUE = 1.0,

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
	-- ===== The rate limit, and ONLY the rate limit =====
	-- This replaces BOX_ROLL_DELAY_SECONDS, which used to do two unrelated
	-- jobs with one number: it delayed the RESULT (a deliberate "the box is
	-- being decided" beat) and it was also the rate limit, because onBoxPress
	-- would not evaluate the next press until the previous one's delayed
	-- result had fired. Those are now split -- see LaunchServer's onBoxPress.
	--
	-- THE RESULT IS NOW IMMEDIATE. The roll happens synchronously inside the
	-- press handler and BoxResult goes back on the same frame, so the box
	-- reacts the instant it is pressed with no round-trip pause of the
	-- server's own making.
	--
	-- THIS number is what survives of the rate limit, and it is still enforced
	-- entirely server-side: onBoxPress sets box.pending on every accepted
	-- press and clears it from a task.delay of exactly this length, refusing
	-- every press that arrives in between. A modified client firing BoxPress
	-- in a tight loop therefore still gets at most one roll per this many
	-- seconds -- the guard never depended on the result's timing, only on the
	-- flag, and the flag now has its own timer.
	--
	-- 0.25 is four presses a second: comfortably above any deliberate human
	-- clicking rate (so a normal player never meets it), comfortably below
	-- what a script could otherwise achieve. Shorter than the 0.4 it replaces,
	-- which is affordable precisely because the press no longer has to wait
	-- out a result. LaunchClient mirrors this same constant locally so a
	-- normal player's presses are never silently dropped -- that mirror is
	-- convenience only and is not what enforces anything.
	BOX_PRESS_COOLDOWN_SECONDS = 0.25,

	-- ScreenGui NAMES (children of PlayerGui) suppressed for the duration of
	-- the box sequence -- see LaunchClient's acquire/release pair. These are
	-- owned by OTHER client scripts and are the only persistently-visible UI
	-- left on screen once LaunchClient has hidden its own: ShopClient's
	-- "SWING SHOP" button and InventoryClient's "INVENTORY" button, both
	-- top-right. Suppressed via ScreenGui.Enabled, which is orthogonal to
	-- their children's own Visible flags -- so whatever state those panels are
	-- in when the box appears is exactly the state they come back to, and
	-- neither owning script needs to know this happens.
	--
	-- DELIBERATELY NOT A LIST OF EVERY HUD. BaseHud (BaseClient's money and
	-- swing-tier readouts) stays up on purpose -- it is ambient information,
	-- not an interaction, and the box does not compete with it. DevPanel stays
	-- up too; it is dev-only and gated elsewhere.
	--
	-- A name that does not resolve is skipped silently: a client script that
	-- failed its own startup gate never created its ScreenGui, and that is not
	-- this list's problem to report.
	BOX_SUPPRESSED_HUD_NAMES = { "ShopHud", "InventoryHud" },

	-- ===== The box itself: a REAL PART IN THE WORLD, built client-side in
	-- front of the frozen player at their landing spot (see LaunchClient's own
	-- world-box block). It replaced a screen-space GUI panel entirely -- see
	-- the written report. Nothing here reaches the server, changes a
	-- probability, or adds a millisecond to the sequence; the BoxStarted /
	-- BoxPress / BoxResult flow is byte-for-byte the same one the panel used.
	-- =====
	-- Edge length of the cube, in studs. The player is frozen roughly 20 studs
	-- from their own chase camera at this point, where a 70-degree vertical
	-- FOV spans ~28 studs -- so a 7-stud cube, seen corner-on at the tilt
	-- below, spans ~9 studs of that: it fills the middle third of frame,
	-- unmistakably the thing being looked at, without covering the landing
	-- readout at the top of the screen. Sized together with
	-- BOX_WORLD_HEIGHT_OFFSET_STUDS below -- see that constant for why a
	-- bigger cube cannot simply be dropped in without also raising it.
	BOX_WORLD_SIZE_STUDS = 7,
	-- Studs IN FRONT of the character (along their own flattened LookVector,
	-- never a world axis -- see LaunchClient's boxRestCFrameForCharacter) the
	-- cube's centre sits. Close enough to dominate the view, far enough that
	-- the default third-person camera -- which sits BEHIND the character --
	-- never ends up inside it.
	BOX_WORLD_DISTANCE_STUDS = 8,
	-- Studs above the character's own HumanoidRootPart (pelvis height, itself
	-- ~3 studs off the ground on R15) the cube's CENTRE sits. This is what
	-- keeps the box clear of the road it is standing over, and it is not a
	-- free number -- a cube this size cannot be centred anywhere near eye
	-- height without burying its lower corners in the ground:
	--
	--   A 7-stud cube has a 3.5-stud half-extent, but it is TILTED (see
	--   BOX_WORLD_YAW/PITCH_DEGREES), SPINNING (BOX_HOVER_SPIN_DEGREES_PER_
	--   SECOND) and SHAKING (BOX_THRASH_ROTATION_DEGREES), and a rotated
	--   cube's vertical reach is its half-extent times the sum of the absolute
	--   values of its rotation matrix's world-Y row. Searched numerically over
	--   the full hover spin and every combination of thrash tilt extremes,
	--   that peaks at 1.70 -- a reach of 5.95 studs below centre -- plus 0.35
	--   of hover travel and 0.42 of downward thrash jitter.
	--
	-- 5.0 puts the centre ~8 studs off the ground, leaving the lowest corner
	-- the box can ever reach ~1.3 studs clear of the road bands at the very
	-- peak of a thrash, and ~2.8 clear at rest. RAISED FROM 3.5 when the
	-- thrash replaced the old rattle: at 3.5 the worst case was 0.2 studs
	-- BELOW the road, i.e. a corner visibly sinking into it at the most
	-- dramatic moment of the sequence.
	--
	-- Raising it costs nothing visually, which is why this was the lever
	-- rather than shrinking the thrash: BOX_CAMERA_PITCH_DEGREES is 0, so the
	-- camera sits at exactly the box's centre height and rises with it, and
	-- the composition is identical -- a level camera puts the horizon at 50%
	-- of frame regardless of how high it is, and 1.5 studs against the
	-- landmark's ~3400 moves it by 0.03 degrees.
	BOX_WORLD_HEIGHT_OFFSET_STUDS = 5.0,
	-- Degrees the cube is turned about its own vertical/horizontal axes from
	-- dead-square-on to the player. A cube viewed exactly face-on renders as a
	-- flat square with no readable depth; this three-quarter tilt is what makes
	-- it read as a BOX at a glance. Cosmetic only -- every face carries the
	-- same "?", so no amount of tilt can hide the marking.
	BOX_WORLD_YAW_DEGREES = 25,
	-- NEGATIVE tips the cube's TOP toward the camera, showing its top face;
	-- positive tips it away, showing its underside. Flipped from +12: leaning
	-- toward the viewer reads as the box presenting itself, leaning away reads
	-- as it turning its back.
	--
	-- GROUND CLEARANCE RE-VERIFIED FOR THE NEW SIGN, not assumed symmetric --
	-- the whole reason BOX_WORLD_HEIGHT_OFFSET_STUDS above is 5.0 is a
	-- numerical search over this rotation, and reversing the pitch changes
	-- which corner hangs lowest. Re-running that search (full hover spin,
	-- every combination of thrash tilt extremes) gives the SAME worst-case
	-- abs-sum of 1.7009 -- 5.95 studs of reach, 1.28 studs of clearance -- but
	-- reached at mirrored tilt combinations: (20,20,20) here where +12 peaked
	-- at (-20,20,-20). That equality is not a coincidence and not luck: the
	-- hover sweeps the yaw through a full 360 degrees and the thrash tilt
	-- range is symmetric about zero, so the two signs reach the same SET of
	-- rotations, just by different routes. It would NOT hold if the spin were
	-- ever bounded to an arc.
	BOX_WORLD_PITCH_DEGREES = -12,
	-- Body colour. Deep violet: distinct from every other colour in the scene
	-- at the landing spot (the rainbow road's bands, the grey/pebble plot
	-- dressing) so the box never blends into whichever band it happens to be
	-- standing on.
	BOX_WORLD_COLOR = Color3.fromRGB(78, 48, 132),
	-- SmoothPlastic, not Neon: a glowing box would wash out the "?" drawn on
	-- its own faces, which is the one thing that has to stay legible.
	BOX_WORLD_MATERIAL = Enum.Material.SmoothPlastic,
	-- Colour of the "?" on all six faces -- gold, the same colour the luck
	-- readout uses, so the box and the number it is holding read as one object.
	BOX_WORLD_QUESTION_COLOR = Color3.fromRGB(255, 214, 60),
	-- SurfaceGui resolution, in GUI pixels per stud of face. The "?" is
	-- TextScaled to fill its face, so this only sets how crisply that single
	-- glyph is rasterised -- 40 x the 8-stud face is a 320px canvas, ample for
	-- one character and far cheaper than the default 50 at six faces.
	BOX_WORLD_QUESTION_PIXELS_PER_STUD = 40,
	-- ClickDetector.MaxActivationDistance, in studs -- measured from the
	-- player's own character, which is frozen BOX_WORLD_DISTANCE_STUDS away
	-- from the box for the entire time the box exists. Generous rather than
	-- tight: this is not a gameplay range check (the box is the only thing to
	-- interact with at the landing spot), just the engine's own cutoff, and it
	-- must never be the reason a press fails to register.
	BOX_WORLD_CLICK_DISTANCE_STUDS = 40,
	-- Studs ABOVE the cube's centre the luck readout billboard floats. Must
	-- clear the cube's own tilted vertical reach (~4.4 studs at rest, see
	-- BOX_WORLD_HEIGHT_OFFSET_STUDS's arithmetic) or the number sits inside
	-- the box -- 6 leaves a clean gap above the top corner. (The billboard is
	-- AlwaysOnTop, so it stays readable through the open burst scaling past it
	-- too.)
	BOX_WORLD_LUCK_LABEL_HEIGHT_STUDS = 6,
	-- The billboard's own screen size in pixels. Fixed pixels, not studs, so
	-- the number stays equally readable regardless of how far the camera has
	-- been pulled back -- same reasoning the on-slime upgrade tags use.
	BOX_WORLD_LUCK_LABEL_WIDTH_PIXELS = 260,
	BOX_WORLD_LUCK_LABEL_HEIGHT_PIXELS = 56,

	-- ===== Box camera (CLIENT-SIDE ONLY -- see LaunchClient's own box camera
	-- block). While the box is up the camera leaves the player's control
	-- (CameraType Scriptable) and frames the box alone against open sky; it
	-- eases back to exactly where it was, and back to Custom, the moment the
	-- box is gone. Nothing here touches the server, the outcome, or the
	-- sequence's timing. =====
	-- Studs from the cube's centre to the camera, along the view ray.
	--
	-- THE SHOT LOOKS DOWN-ROAD AT THE LANDMARK. The camera sits BEHIND the
	-- player (see LaunchClient's boxCameraCFrame) and looks past them, through
	-- the box, out to the giant slime on the horizon -- the box in the near
	-- ground, the rainbow road running away underneath it, the landmark
	-- rising behind. The character is in that line and is made invisible for
	-- the duration rather than framed around; the framing is chosen for the
	-- backdrop, not bent to exclude them.
	--
	-- HOW THIS NUMBER WAS PICKED. The landmark is thousands of studs away, so
	-- moving the camera does not change ITS apparent size at all -- it only
	-- shrinks the box. Pulling back is therefore the single knob that trades
	-- box dominance for backdrop, and with the aim now LEVEL (see
	-- BOX_CAMERA_PITCH_DEGREES) there is a hard threshold in it: the landmark
	-- is 17.4 degrees wide at the worst case (a tier-1 landing, ~3430 studs
	-- out), and the box is wider than that at anything closer than ~31 studs.
	-- Inside that the landmark is simply behind the box and invisible.
	--
	-- 34 clears it: the box is 15.6 degrees wide against the landmark's 17.4,
	-- so even at tier 1 the landmark shows past BOTH sides as well as above,
	-- and from tier 3 up it dwarfs the box entirely. The box still reads as
	-- the subject at ~21% of frame height and ~13% of frame width, centred on
	-- the horizon.
	BOX_CAMERA_DISTANCE_STUDS = 34,
	-- SIGNED tilt: positive tilts the camera UP at the box (camera below it),
	-- negative tilts it DOWN (camera above it).
	--
	-- LEVEL. The camera looks straight down the road at the box, from the box's
	-- own centre height (a level aim puts the camera at exactly boxCentre,
	-- ~6.5 studs off the road -- a couple of studs above the player's eye
	-- height, which is about as natural as this shot gets).
	--
	-- WHAT THE SIGN COSTS, since this used to be -9 and the trade is not
	-- obvious. The landmark stands ON the road, so it always occupies a band
	-- running UPWARD from the horizon; the aim is what decides where that
	-- horizon falls relative to the box, which is centred in frame by
	-- construction. Tilting DOWN lifts the horizon and everything standing on
	-- it away from the box -- which is why -9 gave 11.5 degrees of clear
	-- landmark above the box at tier 1. Level puts the horizon at exactly 50%
	-- of frame, dead behind the box's own centre, and drops that to 4.3
	-- degrees. Tilting UP would be worse still, not better: it pushes the
	-- horizon DOWN the frame and buries more of the landmark behind the box
	-- (+2 degrees leaves only ~2.2). Level is the best of the three for the
	-- backdrop, which is why this is 0 rather than a small positive number.
	--
	-- The landmark still clears the box, but now mostly AROUND it rather than
	-- above it -- see BOX_CAMERA_DISTANCE_STUDS, which was pulled back to 34
	-- specifically to make the box narrower than the landmark so that works.
	--
	-- Not constrained by hiding the character -- that is
	-- LocalTransparencyModifier's job (see LaunchClient's hidden-character
	-- block), which is what freed this constant to be chosen for the backdrop
	-- instead of for occlusion.
	BOX_CAMERA_PITCH_DEGREES = 0,

	-- ===== Box idle hover (CLIENT-SIDE MOTION ONLY) =====
	-- The box is suspended in mid-air with nothing holding it up, and a
	-- perfectly still object hanging there reads as a flat image pasted on the
	-- screen rather than a thing in the world. This is the slow, continuous
	-- "it is floating" motion underneath everything else.
	--
	-- COMPOSES WITH THE SHAKE, DOES NOT REPLACE IT. The hover is not a motion
	-- PHASE -- it is the moving rest pose that every phase is built on top of
	-- (see LaunchClient's boxHoverCFrame): at rest the box just hovers, a
	-- press adds the rattle on top of the hover, a fail decays the rattle back
	-- down onto it, and the burst launches from it. Like the shake, it is
	-- driven by the ABSOLUTE clock rather than by time-since-this-phase-began,
	-- which is what makes every one of those handoffs seamless -- the hover
	-- never restarts, so there is no instant at which the two can disagree
	-- about where the box is.
	-- Peak vertical travel either side of the resting height, in studs. Small
	-- next to the 7-stud cube and sitting between the two shake sizes -- three
	-- times BOX_NUDGE_AMPLITUDE_STUDS, half BOX_THRASH_AMPLITUDE_STUDS -- so
	-- it is a slow drift rather than a bounce and cannot be confused with
	-- either of them, which are both far faster (see BOX_SHAKE_FREQUENCY_HZ).
	BOX_HOVER_AMPLITUDE_STUDS = 0.35,
	-- Seconds for one complete up-and-down cycle. Deliberately far slower than
	-- anything else the box does (the whole thrash is 0.25s): the hover
	-- has to read as ambient rather than as an event, and stay legible
	-- underneath a rattle running ~60x faster.
	BOX_HOVER_PERIOD_SECONDS = 3.2,
	-- Degrees of yaw per second, applied continuously about the box's own
	-- vertical axis. 10 is a full turn every 36 seconds -- slow enough that no
	-- single glance catches it moving, fast enough that the face on screen has
	-- visibly changed by the time a box resolves. Every face carries the same
	-- "?" (see BOX_WORLD_QUESTION_COLOR), so this can rotate indefinitely
	-- without ever showing an unmarked side.
	BOX_HOVER_SPIN_DEGREES_PER_SECOND = 10,
	-- Seconds for the move into that framing, and for the move back out of it
	-- again. Smoothstep-eased at both ends (see LaunchClient's
	-- updateBoxCamera), so it reads as a deliberate push-in rather than a cut
	-- or a linear slide. Short enough not to delay the first press -- pressing
	-- is live throughout, the transition is never an input gate -- and long
	-- enough to read as a camera move rather than a teleport.
	BOX_CAMERA_TRANSITION_SECONDS = 0.45,

	-- ===== Box shake (CLIENT-SIDE MOTION ONLY -- see LaunchClient's own box
	-- motion block). Nothing here reaches the server or changes a probability.
	-- =====
	--
	-- THE SHAKE MOVED. It used to be one rattle that built through the whole
	-- BOX_ROLL_DELAY_SECONDS wait and then resolved either way -- which spent
	-- the game's most violent motion on a moment whose outcome was still
	-- unknown, and made a fail (by far the common case at BOX_DOUBLE_CHANCE)
	-- the loudest thing on screen. It is now TWO separate, differently-sized
	-- events with different meanings:
	--
	--   NUDGE   -- every press. A small knock that decays out. This is the box
	--              acknowledging the press and nothing else, and on a FAIL it
	--              is the entire animation: the box was hit, it moved, it held.
	--   THRASH  -- opens only, and only AFTER BoxResult says so. The box tears
	--              itself apart in the last quarter-second before the burst.
	--
	-- The client cannot start the thrash early -- it learns the outcome only
	-- when BoxResult arrives -- so the thrash necessarily sits BETWEEN that
	-- event and the burst, which is what pushes the burst slightly later than
	-- it used to be. Total open tail is BOX_THRASH_SECONDS +
	-- BOX_OPEN_BURST_SECONDS = 0.55, inside
	-- SlimeConfig.REVEAL_BOX_TO_SLIME_DELAY_SECONDS (0.6) with 0.05 to spare,
	-- so the reveal still cannot overlap the box. Retuning either of those two
	-- upward means checking that sum against that constant again.
	--
	-- Jitter oscillations per second, SHARED by both events -- they differ in
	-- size and envelope, not in character, so a nudge reads as a small version
	-- of the same physical rattle. High on purpose: below ~10 it reads as the
	-- box sliding around, above ~25 it starts to alias against a 60 Hz frame
	-- rate and reads as noise.
	BOX_SHAKE_FREQUENCY_HZ = 18,
	-- ===== NUDGE: every press, and the whole of a fail =====
	-- Peak positional jitter in STUDS, at the instant of the press. Roughly a
	-- fifth of the thrash below and about a third of the hover's own travel --
	-- big enough to register as "that did something", far too small to be
	-- mistaken for the open.
	BOX_NUDGE_AMPLITUDE_STUDS = 0.12,
	-- Peak tilt either side of rest, in degrees. Same reasoning -- a knock,
	-- not a struggle.
	BOX_NUDGE_ROTATION_DEGREES = 3,
	-- Seconds for it to decay from full to nothing. Starts at full energy and
	-- bleeds out (there is no ramp -- the knock IS the impact, and an impact
	-- that fades in would read as the box starting to move on its own). Kept
	-- under BOX_PRESS_COOLDOWN_SECONDS so the box is visibly back at rest by
	-- the time the next press is allowed.
	BOX_NUDGE_SECONDS = 0.18,
	-- ===== THRASH: opens only, immediately before the burst =====
	-- Peak positional jitter in STUDS. Larger than the old single rattle's
	-- 0.55 -- it no longer has to be survivable-looking, because this only
	-- ever plays on a box that is about to come apart.
	BOX_THRASH_AMPLITUDE_STUDS = 0.7,
	-- Peak tilt either side of rest, in degrees, on all three axes. 20 degrees
	-- of thrashing reads as a box that is no longer holding together, which is
	-- exactly what is about to happen to it.
	BOX_THRASH_ROTATION_DEGREES = 20,
	-- Seconds it runs for, between BoxResult(opened) and the burst starting.
	-- Short: this is the inhale before the bang, not a scene of its own, and
	-- every millisecond here delays the payoff.
	BOX_THRASH_SECONDS = 0.25,
	-- Shape of the thrash's ramp: energy = (elapsed / BOX_THRASH_SECONDS) ^
	-- this. 1.0 would be a straight line, which spends most of the window
	-- already at full violence and so has nowhere left to escalate. Above 1
	-- pushes the growth late -- at 2.0 the box is at 4% amplitude a fifth of
	-- the way through and 25% halfway, then climbs hard into the burst. Unlike
	-- the old build curve this one IS a prediction, and legitimately so: by
	-- the time it starts, BoxResult has already told this client the box is
	-- opening.
	BOX_THRASH_BUILD_EXPONENT = 2.0,
	-- OPEN ONLY: the multiple of its own size the cube blows out to as it
	-- vanishes (2.2 = it more than doubles). The open deliberately shares NO
	-- motion vocabulary with the fail -- jitter stops dead, the box expands
	-- through the camera while fading to nothing and is then destroyed, so "it
	-- burst" and "it held" can never be confused at a glance. A single frame is
	-- enough to tell them apart: on a fail the box is still there.
	BOX_OPEN_BURST_SCALE = 2.2,
	-- Seconds for that burst. Well inside
	-- SlimeConfig.REVEAL_BOX_TO_SLIME_DELAY_SECONDS (0.6), so the box is fully
	-- gone before the slime reveal takes the screen.
	BOX_OPEN_BURST_SECONDS = 0.3,
	-- Degrees of yaw the cube sweeps through across that burst -- the spin is
	-- what stops the expansion reading as a slow, weightless swell.
	BOX_OPEN_BURST_SPIN_DEGREES = 140,

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
	-- exactly 11 entries long (one per tier).
	--
	-- ===== TIER 11 IS NO LONGER "just inside the last band" -- it OVERSHOOTS
	-- THE ROAD ENTIRELY and lands on the giant slime's platform (see
	-- TreasureConfig.luau and REPORT.md). Its 15.3552 is DERIVED, not picked,
	-- and the rule is worth stating because it is the only entry in this array
	-- that is not a hand-tuned feel number:
	--
	--   scale_11 = (SWING_PIVOT_Z - roadFarEdgeZ)
	--              / (DISTANCE_PER_MULTIPLIER * snapThreshold_11)
	--
	-- i.e. the scale at which a launch AT tier 11's own snap threshold lands
	-- exactly on the road's far edge. That single equation gives the whole
	-- three-outcome ladder for free:
	--   * anything below the snap lands ON the road, shortest bands first, up
	--     to and including band 73 (luck 100,000) right at the lip;
	--   * the snap to 2.0x is a discontinuous jump of
	--     (2.0 - 1.95) * 100 * 15.3552 = 77 studs, which carries the flight
	--     clean off the end of the road and onto the platform.
	-- Band 73 therefore occupies EXACTLY the top of the graded ramp -- no more
	-- and no less -- which is what makes "one step short" a real, hittable
	-- outcome rather than a sliver. See SWING_TIER_SNAP_THRESHOLD below.
	--
	-- ===== MEASURED CORRECTION TO THE PARAGRAPH ABOVE (no number here changed
	-- -- see REPORT.md for the measurement). That derivation uses SWING_PIVOT_Z
	-- as the launch origin, and the launch origin is NOT the pivot: a flight
	-- starts from the SEAT, which at the sweet spot hangs
	-- ropeLength * sin(SWING_ARC_HALF_ANGLE_DEGREES) forward of the pivot --
	-- 36 * sin(35) = 20.649 studs at tier 11. Every tier-11 flight therefore
	-- travels 20.649 studs further down the road than this equation accounts
	-- for, which is 0.516 of a band.
	--
	-- The ring is still exactly one band wide (the 0.52 : 1 ratio quoted under
	-- SWING_TIER_SNAP_THRESHOLD below is right, and measures 0.519 : 1), but it
	-- is DISPLACED half a band DOWN: band 73 is graded 1.9107 .. 1.9366, not
	-- 1.9239 .. 1.95. The leftover top slice, graded 1.9366 up to the 1.95
	-- snap, clears the road WITHOUT snapping -- so the second bullet above is
	-- wrong that only the snap carries a flight off the end, and the platform
	-- does NOT sit entirely inside a distance no flight can occupy. That slice
	-- is 0.0192s of every cycle against the perfect window's 0.0720s: roughly
	-- one chest landing in five today is earned by a launch that never snapped.
	-- Left as-is deliberately -- fixing it moves tier 11's reach. The outcome
	-- readout does not depend on it either way (it reads the landing, see
	-- LAST_BAND_OUTCOME_TEXT), so the HUD stays honest whichever way it goes.
	--
	-- Tiers 1-10 are untouched and must stay so: they are the feel curve, each
	-- derived by picking the reference game's target luck value, finding the
	-- closest band on THIS game's generated curve (see LuckCurve.luau), then
	-- solving for the scale that lands a perfect launch safely inside it.
	SWING_TIER_DISTANCE_SCALE = { 1.0, 3.0, 4.4, 6.4, 8.2, 9.2, 10.8, 11.6, 12.6, 13.8, 15.3552 },

	-- ===== PER-TIER SWEET-SPOT SNAP THRESHOLD. Overrides
	-- SWEET_SPOT_SNAP_THRESHOLD for one tier; every entry that equals the
	-- global value is a no-op, and tiers 1-10 all do, so their behaviour is
	-- BIT-IDENTICAL to before this table existed (verified numerically, see
	-- REPORT.md).
	--
	-- WHY TIER 11 IS DIFFERENT. The snap is what makes the platform reachable:
	-- nothing ever lands with a multiplier between the threshold and 2.0, so
	-- that gap is a distance no flight can occupy, and the platform sits
	-- inside it. But the gap is also dead space taken out of the top of the
	-- road -- at the global 1.90 it swallowed 3.9 bands' worth of tier-11
	-- distance, leaving band 73 reachable through a window half a frame wide.
	-- Raising tier 11's threshold shrinks the gap, which hands band 73 back.
	--
	-- WHY 1.95 AND NOT 1.97. 1.97 gives a perfect window of ~0.043s. That is
	-- below the input-latency variance of touch devices -- a phone player
	-- could not hit it by skill, only by luck, which is exactly what
	-- SWEET_SPOT_SNAP_THRESHOLD's own comment exists to prevent. 1.95 gives
	-- 0.072s: half of today's 0.144s, a real difficulty step for the endgame,
	-- and still comfortably above that floor. The cost is that band 73's ring
	-- comes out narrower than the perfect window rather than wider (0.52 : 1);
	-- see REPORT.md, where the measured numbers are set against both.
	SWING_TIER_SNAP_THRESHOLD = { 1.90, 1.90, 1.90, 1.90, 1.90, 1.90, 1.90, 1.90, 1.90, 1.90, 1.95 },

	-- ===== Remote-lane rendering (client only -- see LaunchClient.client.
	-- luau's renderOtherLanes/rescanRemoteLanes) =====
	-- Seconds between rescans of Workspace for every OTHER player's own
	-- SwingPivot_*/SwingStructure_* pair. Lanes only change on join, leave,
	-- or a tier purchase rebuilding the structure -- never every frame --
	-- so this is a throttle on the (relatively expensive) Workspace:
	-- GetChildren() walk, not on rendering itself: PivotTo still runs every
	-- single RenderStepped from whatever the cache currently holds,
	-- regardless of this value. A fraction of a second is ample -- a lane
	-- appearing/disappearing/rebuilding is never time-critical to notice.
	REMOTE_LANE_RESCAN_INTERVAL_SECONDS = 0.5,
}

return LaunchConfig
