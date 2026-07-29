--!strict
-- Single source of truth for how ANY swing's PIVOT HEIGHT and ROPE LENGTH
-- both change with tier -- same role RunwayGeometry/BaseGeometry play for
-- the runway/bases: one pair of formulas, derived from the SAME `scale`
-- and the SAME two baseline numbers (LaunchConfig.SWING_ROPE_LENGTH and
-- LaunchConfig.SWING_BASE_PIVOT_HEIGHT_ABOVE_GROUND) every caller reads,
-- not independently-tuned copies.
--
-- READS NO WORKSPACE PIVOT: this module used to capture its baseline pivot
-- height from Workspace.SwingPivot at first require -- which meant its
-- formulas were only ever correct for whichever ONE pivot happened to
-- exist in that particular place file. SwingBuilder.build now takes an
-- explicit pivot part per call (see SwingBuilder.luau's written report --
-- the gallery refactor), so this module has no business assuming there is
-- only one; BASE_PIVOT_HEIGHT_ABOVE_GROUND is a plain config constant
-- instead, and the only Workspace read left here is Baseplate, for
-- groundY, which every swing (the one real game swing, all eleven gallery
-- swings) genuinely does share.
--
-- WHY BOTH PIVOT AND ROPE MOVE, NOT JUST THE PIVOT: an earlier pass raised
-- only the pivot (additively) and left SWING_ROPE_LENGTH fixed at 10 --
-- that made the SEAT's height above ground come out right (by coincidence
-- of how the subtraction worked out), but left the swing's actual ARC
-- RADIUS (SWING_ROPE_LENGTH itself) the same tiny, tier-1-sized number at
-- every tier, while the frame around it grew up to 3.6x -- and it left the
-- chain-anchor-to-pivot gap growing without bound (pivot only crept up by
-- a few studs per tier while the frame's own anchor point, tied to the
-- beam, grew by the full scale factor). Scaling BOTH the pivot's height
-- above ground AND the rope length by the SAME `scale` fixes both: the
-- arc radius grows with the frame instead of staying fixed, and the
-- pivot-to-anchor gap becomes a constant PROPORTION of the frame at every
-- tier instead of a growing absolute one -- see the written report for the
-- exact before/after numbers.
--
-- THIS STILL DOESN'T TOUCH ARC SHAPE OR TIMING: swingPhase() is a pure
-- function of the server clock, swingTheta() is a pure function of phase,
-- launchMultiplier() reads phase only -- none of them read SWING_ROPE_
-- LENGTH or any position at all. SWING_ROPE_LENGTH's role in
-- swingSeatPosition is purely the RADIUS of a translation applied to the
-- pivot's own position; scaling that radius by tier changes how BIG the
-- seat's physical swing is and where it sits, never how fast or how often
-- it swings.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LaunchConfig = require(ReplicatedStorage.Config.LaunchConfig)

local baseplate = Workspace:WaitForChild("Baseplate") :: BasePart

local SwingGeometry = {}

-- Ground level -- same reasoning BaseGeometry/RunwayGeometry already use.
local groundY = baseplate.Position.Y + baseplate.Size.Y / 2

-- This tier's pivot Y: LaunchConfig.SWING_BASE_PIVOT_HEIGHT_ABOVE_GROUND
-- scaled by `scale`, added back onto groundY. At scale = 1 this returns
-- exactly groundY + SWING_BASE_PIVOT_HEIGHT_ABOVE_GROUND -- numerically
-- identical to the place file's originally-placed SwingPivot.Position.Y
-- (13, since Baseplate's own top is also at world Y = 0) -- tier 1 is
-- unaffected by construction. Called directly by SwingBuilder, which
-- already has `scale` in hand from SwingTierVisuals.
function SwingGeometry.pivotYForScale(scale: number): number
	return groundY + LaunchConfig.SWING_BASE_PIVOT_HEIGHT_ABOVE_GROUND * scale
end

-- This tier's EFFECTIVE rope length: LaunchConfig.SWING_ROPE_LENGTH itself
-- never changes (still 10, read fresh every call, never cached here) --
-- this is a derived per-tier value, not a second copy of it. At scale = 1
-- this returns exactly SWING_ROPE_LENGTH.
function SwingGeometry.ropeLengthForScale(scale: number): number
	return LaunchConfig.SWING_ROPE_LENGTH * scale
end

-- Inverse of pivotYForScale -- recovers a swing's CURRENT tier scale from
-- ITS pivot's own live Y position, which already replicates to every
-- client for free (SwingBuilder is the only thing that ever writes it).
-- Lets swingSeatPosition -- called every frame, both server- and
-- client-side, for whichever swing a given script cares about -- derive
-- the correct effective rope length from the SAME scale factor
-- SwingBuilder used to place that swing's pivot, without threading a
-- tier/scale parameter through every caller or introducing a second,
-- independently replicated copy of the same number.
function SwingGeometry.ropeLengthForPivotY(pivotY: number): number
	local scale = (pivotY - groundY) / LaunchConfig.SWING_BASE_PIVOT_HEIGHT_ABOVE_GROUND
	return SwingGeometry.ropeLengthForScale(scale)
end

return SwingGeometry
