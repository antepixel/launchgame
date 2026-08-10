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
-- LANE_COUNT = 6 and RUNWAY_WIDTH_STUDS = 360 this gives a 60-stud pitch
-- and centers -150, -90, -30, 30, 90, 150.
--
-- THE PITCH IS NOW THE PLOT GAP TOO (see REPORT.md): plots ride this same
-- function, their true footprint is 40 studs, so the bare ground between
-- neighbouring plots is exactly pitch - 40 -- 20 studs at the current width,
-- 0 at the previous 240. Nothing else expresses that gap; it is this
-- subtraction and nothing more.
--
-- The top tier's swing footprint (35.01 studs, see SwingTierVisuals' own
-- footprint clamp) now clears its neighbour by 24.99 studs, up from 4.99 at
-- the old 40-stud pitch -- so the widening only ever relieves that
-- constraint, never tightens it.
--
-- DEFINED FOR INDICES OUTSIDE 0..LANE_COUNT-1, deliberately and by
-- construction: the arithmetic is a plain linear map with no clamp, so
-- laneCenterX(-1) and laneCenterX(LANE_COUNT) return the next grid position
-- beyond each end of the row. StallConfig uses exactly those two to place
-- the shops, which is why the shops track the pitch automatically instead of
-- needing their own literal. Do not add a clamp here without giving that
-- caller another way to ask the same question.
function LaneConfig.laneCenterX(laneIndex: number): number
	local pitch = LaunchConfig.RUNWAY_WIDTH_STUDS / LaneConfig.LANE_COUNT
	local offsetFromCenter = (laneIndex - (LaneConfig.LANE_COUNT - 1) / 2) * pitch
	return LaneConfig.ROAD_CENTER_X + offsetFromCenter
end

-- Studs between adjacent BASE lane centers. NOW EQUAL TO THE SWING PITCH,
-- and derived from it rather than stated (see REPORT.md -- the straightening
-- pass).
--
-- IT USED TO BE 80, an independent literal, on the reasoning that a swing
-- must sit on the fixed-width road but a plot needn't, so plots were free to
-- breathe on a wider pitch. That reasoning was sound in isolation and wrong
-- in composition: it put plot i at exactly TWICE its swing's X, so the
-- walkway connector between them had to cover a gap that GREW with distance
-- from centre -- 100 studs of X in 33 studs of Z at the outer lanes, a link
-- running 71.7 degrees off axis. That outward fan of diagonals is what this
-- pass removes, and the only way to remove it is for the two pitches to be
-- the same number. Kept as a named constant rather than deleted because it
-- is still the documented SEAM: if plots ever need their own pitch again,
-- this is where it goes back, and baseLaneCenterX below is where it is read.
LaneConfig.BASE_LANE_PITCH_STUDS = LaunchConfig.RUNWAY_WIDTH_STUDS / LaneConfig.LANE_COUNT

-- Lane i's BASE world X -- now DELEGATES to laneCenterX, so a plot sits
-- directly above its own swing by construction and cannot drift out of
-- alignment again the way two independently-maintained formulas did. At
-- LANE_COUNT = 6 and RUNWAY_WIDTH_STUDS = 360 this gives centers -150, -90,
-- -30, 30, 90, 150 -- the same six numbers laneCenterX returns, because they
-- ARE the same six numbers now.
--
-- STILL A SEPARATE FUNCTION on purpose: every plot-dressing caller
-- (BaseGeometry's mat/path/edges/slots/sign, PlayerProfile's slime facing)
-- goes through this name, and every swing/flight caller goes through
-- laneCenterX. Collapsing the two call sites into one would erase the
-- distinction between "where this lane's PLOT is" and "where this lane's
-- SWING is" -- which is exactly the information a future pass would need to
-- pull them apart again.
function LaneConfig.baseLaneCenterX(laneIndex: number): number
	return LaneConfig.laneCenterX(laneIndex)
end

return LaneConfig
