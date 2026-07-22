--!strict
-- Every feel-related constant for the launch prototype lives here, and ONLY here.
-- Tune the feel by editing numbers in this file -- no other script should hardcode
-- a physics/timing constant. Shared by both LaunchServer (authoritative) and
-- LaunchClient (cosmetic charge-meter prediction only -- the server never trusts
-- the client's copy of these numbers for anything that affects the outcome).

export type LaunchConfig = {
	MIN_LAUNCH_SPEED: number,
	MAX_LAUNCH_SPEED: number,
	MAX_CHARGE_TIME: number,
	RAMP_ANGLE_DEGREES: number,
	GRAVITY: number,
	AIR_DRAG_COEFFICIENT: number,
	BALL_RADIUS: number,
	BALL_FRICTION: number,
	BALL_ELASTICITY: number,
	LANDED_VELOCITY_THRESHOLD: number,
	LANDED_STILL_TIME: number,
	MAX_FLIGHT_TIME: number,
	RESET_DELAY: number,
}

local LaunchConfig: LaunchConfig = {
	-- ===== Power curve =====
	-- Launch speed (studs/sec) at zero charge (a bare tap still does something --
	-- avoids a "dead" zero-power launch that feels like a bug). Raising this shrinks
	-- the effective skill range between a tap and a full hold.
	MIN_LAUNCH_SPEED = 40,
	-- Launch speed (studs/sec) at full charge. Raising this stretches max distance
	-- and makes the top of the power meter feel more rewarding to reach.
	MAX_LAUNCH_SPEED = 160,
	-- Seconds of holding to go from 0% to 100% power. Lower = twitchier, harder to
	-- land a precise mid-power shot. Higher = more forgiving, slower-paced charge.
	MAX_CHARGE_TIME = 1.5,

	-- ===== Launch angle =====
	-- Degrees above horizontal the ball launches at. Lower = flatter, faster-feeling,
	-- shorter hang time. Higher = more arc and hang time, more "floaty," shorter
	-- effective range at the same speed (energy spent going up instead of out).
	RAMP_ANGLE_DEGREES = 35,

	-- ===== Physics environment =====
	-- Workspace.Gravity (studs/sec^2), applied once at server startup. Roblox's
	-- default is 196.2. Lower = longer hang time, floatier arcs, more room to feel
	-- the charge/power difference mid-flight. Higher = snappier, shorter, more
	-- "weighty" arcs. NOTE: this is a global Workspace property, so it also affects
	-- player jump/fall feel, not just the launch ball -- acceptable for this
	-- single-mechanic prototype, but worth knowing before tuning it far from default.
	GRAVITY = 130,
	-- Extra opposing force per unit velocity, applied every Heartbeat while the ball
	-- is in flight (0 = off). 0 by default -- pure ballistic arc, no air resistance.
	-- Raise it to shorten range and add a "thrown through air" heaviness without
	-- touching gravity or speed; it also flattens the back half of the arc.
	AIR_DRAG_COEFFICIENT = 0,

	-- ===== The launch ball itself =====
	-- Radius in studs. Bigger = easier to track visually, but also changes how it
	-- rolls/settles (more radius = more rolling distance after it touches down).
	BALL_RADIUS = 2,
	-- 0-1ish, Roblox PhysicalProperties.Friction. Higher = stops/skids to rest
	-- faster and feels "grippier". Lower = keeps sliding after landing, feels
	-- slippery/icy.
	BALL_FRICTION = 0.3,
	-- 0-1ish, Roblox PhysicalProperties.Elasticity. Higher = bounces more on
	-- landing (can read as fun or as "out of control" past ~0.4). Lower = lands
	-- with a dead thud, no bounce.
	BALL_ELASTICITY = 0.2,

	-- ===== Landed detection (server) =====
	-- Speed (studs/sec) below which the ball is considered "stopped" for landing
	-- purposes. Too high falsely calls a still-rolling ball landed early; too low
	-- makes the result screen wait for a near-perfect stop.
	LANDED_VELOCITY_THRESHOLD = 2,
	-- Seconds the ball must stay under the threshold before it's confirmed landed
	-- (debounces a single-frame velocity dip on bounce/skid so a bounce isn't
	-- mistaken for a stop). Raising this delays the result readout slightly but
	-- makes "landed" more certain.
	LANDED_STILL_TIME = 0.3,
	-- Safety cutoff (seconds) -- if the ball is still moving this long after launch
	-- (e.g. an unexpectedly long skid), force the landing/reset anyway so the loop
	-- can never get stuck. Should sit comfortably above the longest expected real
	-- flight+skid at MAX_LAUNCH_SPEED.
	MAX_FLIGHT_TIME = 12,
	-- Seconds to pause after a confirmed landing (so the player can read the
	-- distance) before the ball snaps back to the launch point and charging is
	-- allowed again. Keep this under ~2s per the fast-reset requirement.
	RESET_DELAY = 0.75,
}

return LaunchConfig
