--!strict
-- Single source of truth for the SIX per-player swing lanes -- lane count,
-- the shared road's own centerline (independent of any specific swing), and
-- each lane's world X, derived from lane count and the road's own width
-- rather than six hand-picked literals.
--
-- WHY THIS EXISTS (see the written report -- six-lane pass 1):
-- RunwayBuilder/BaseGeometry/LaunchServer/LaunchClient used to all read
-- Workspace.SwingPivot.Position.X for "where is the swing," which only ever
-- worked because there was exactly one. There are now up to LANE_COUNT of
-- them, one per player, built and destroyed at runtime (see
-- LaunchServer.server.luau) -- none of them privileged, none of them a
-- valid stand-in for "the" swing any more. Nothing reads a pivot's position
-- for lane placement any more, only this config.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LaunchConfig = require(ReplicatedStorage.Config.LaunchConfig)

local LaneConfig = {}

-- One lane per player, one player per lane, for the life of a session --
-- see PlayerProfile.luau's baseIndex, reused directly as the lane index, no
-- second parallel index. Also the hard cap on concurrent players -- see
-- PlayerProfile.luau's allocateBaseIndex and its Players.MaxPlayers = this.
LaneConfig.LANE_COUNT = 6

-- The shared road's own centerline -- NOT read from any swing's pivot
-- (there are up to six now, none of them privileged). 0 matches the
-- Baseplate's own placed X (see default.project.json) and RunwayBuilder's
-- generated bands, unchanged from every previous pass.
LaneConfig.ROAD_CENTER_X = 0

-- World Z for every lane's pivot -- flat, not derived (there was never a
-- formula behind "how far the swing sits from the platform edge," it was
-- always just a hand-placed number). 30 matches the single SwingPivot's own
-- placed Z in the now-removed default.project.json entry, so every lane's
-- swing sits exactly where the one shared swing used to.
LaneConfig.SWING_PIVOT_Z = 30

-- World Z for every lane's spawn -- same reasoning, matches the now-removed
-- PlaceholderSpawn's own placed Z.
LaneConfig.SPAWN_Z = 55

-- Lane i's world X (0-indexed, matching PlayerProfile's baseIndex
-- directly): LANE_COUNT lanes, evenly spaced across the road's own width
-- (LaunchConfig.RUNWAY_WIDTH_STUDS), centered on ROAD_CENTER_X. At
-- LANE_COUNT = 6 and RUNWAY_WIDTH_STUDS = 240 this gives a 40-stud pitch
-- and centers -100, -60, -20, 20, 60, 100 -- see the written report for the
-- measured confirmation against the tier-11 footprint clamp.
function LaneConfig.laneCenterX(laneIndex: number): number
	local pitch = LaunchConfig.RUNWAY_WIDTH_STUDS / LaneConfig.LANE_COUNT
	local offsetFromCenter = (laneIndex - (LaneConfig.LANE_COUNT - 1) / 2) * pitch
	return LaneConfig.ROAD_CENTER_X + offsetFromCenter
end

return LaneConfig
