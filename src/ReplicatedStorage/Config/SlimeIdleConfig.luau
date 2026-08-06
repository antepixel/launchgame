--!strict
-- Every constant for the idle squash-and-stretch on slime meshes lives here,
-- and ONLY here -- same rule as LaunchConfig.luau/SlimeConfig.luau, just for
-- a different subsystem.
--
-- Kept as its own file rather than folded into SlimeConfig: that module's own
-- header scopes it to slime-COLLECTION constants (the catalog, the roll
-- window/peak math), and none of this is collection data. It is also not
-- GiantSlimeConfig material, because the same numbers drive BOTH the placed
-- slot slimes and the landmark -- the animation is a property of the mesh,
-- not of either place it appears. See
-- StarterPlayerScripts/SlimeIdleClient.client.luau, the only reader.

export type SlimeIdleConfig = {
	IDLE_AMPLITUDE: number,
	IDLE_PERIOD_SECONDS: number,
	IDLE_RESCAN_INTERVAL_SECONDS: number,
	BLINK_DURATION_SECONDS: number,
	BLINK_CLOSED_FACTOR: number,
	BLINK_INTERVAL_MIN_SECONDS: number,
	BLINK_INTERVAL_MAX_SECONDS: number,
}

local SlimeIdleConfig: SlimeIdleConfig = {
	-- How far the vertical scale swings either side of 1. At 0.08 the body
	-- ranges 0.92x to 1.08x tall, and (volume conserved -- see the client's
	-- own sxz = 1/sqrt(sy) comment) about 1.04x to 0.96x wide. Deliberately
	-- small: this is meant to read as "alive", not as a bounce. Past roughly
	-- 0.15 the linear-vs-volume-conserving difference starts to show as the
	-- slime appearing to grow and shrink rather than deform.
	IDLE_AMPLITUDE = 0.08,
	-- Seconds for one full squash-stretch-squash cycle. Slow on purpose --
	-- a breathing rate, not a pulse.
	IDLE_PERIOD_SECONDS = 2.0,
	-- How often the client re-walks Workspace looking for slimes that have
	-- appeared or gone. Its OWN value rather than a borrow of
	-- LaunchConfig.REMOTE_LANE_RESCAN_INTERVAL_SECONDS (which happens to
	-- share this number): the swing system's rescan cadence and this one
	-- answer to different pressures and should be retunable apart. Slimes
	-- appear only on a placement or a player joining, so this can be lazy --
	-- the cost being throttled is the Workspace WALK, never the per-frame
	-- animation, which always runs from the cache.
	IDLE_RESCAN_INTERVAL_SECONDS = 0.5,

	-- ===== Blink. Applies to eye_dark and eye_white ONLY -- blush and the
	-- body are untouched by it. Costs no extra per-frame writes: the eyes are
	-- already having Size and CFrame written every frame by the breathing, and
	-- the blink only changes the Y number inside the Size that is being built
	-- anyway. =====
	-- How long one whole blink takes, closed and open again. Raised from 0.12:
	-- together with the softer closed factor below it turns each blink into a
	-- slow shutter rather than a snap.
	BLINK_DURATION_SECONDS = 0.22,
	-- How far the eyes squash vertically at the shut point, as a multiple of
	-- their normal height. Never zero: a MeshPart at Size.Y = 0 is degenerate,
	-- and a sliver of eye left at the shut point reads as a closed lid rather
	-- than as the eye vanishing. Raised from 0.06 -- not shutting all the way
	-- is most of what makes the blink read as soft.
	BLINK_CLOSED_FACTOR = 0.14,
	-- Range the per-slime blink interval is drawn from -- see the client's
	-- own rhythmFor, which takes it as a SECOND draw off the same
	-- position-seeded generator the breathing phase comes from, so it is
	-- stable across rescans for exactly the same reason the phase is.
	--
	-- Raised from 3-7 s, which was roughly TWICE a human blink rate and read
	-- as twitchy with ten slimes in view -- the eye catches the group, not the
	-- individual, so ten slimes blinking at a human rate is ten times too much
	-- movement. At 7-15 s any one slime blinks rarely, while a base's worth
	-- still shows a blink every second or two.
	BLINK_INTERVAL_MIN_SECONDS = 7.0,
	BLINK_INTERVAL_MAX_SECONDS = 15.0,
}

return SlimeIdleConfig
