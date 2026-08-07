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

	-- NO BLINK, AND DO NOT ADD ONE. Two mechanisms were built and both were
	-- rejected on sight: squashing the eye parts read as the whole eye
	-- deforming and popping back, and sinking them along the face normal read
	-- as the eyes vanishing and reappearing. The mesh has no eyelid, so there
	-- is nothing to close -- the asset cannot fake a blink, only hide or
	-- distort the eye. A blink needs a new asset, not new numbers here.
}

return SlimeIdleConfig
