--!strict
-- EVERY FORMULA LaunchClient MIRRORS FROM LaunchServer, and nothing else.
--
-- SPLIT OUT OF LaunchClient.client.luau (see REPORT.md -- that file hit
-- Luau's hard 200-locals-per-function-scope limit). Lives in
-- ReplicatedStorage.LaunchClient, not beside its caller: see LaunchClient's own
-- require comment for the PlayerScripts ordering hazard that forced the move.
-- THIS one is the module with a genuine claim on ReplicatedStorage anyway --
-- nothing in it is client-specific; it is the client's mirror of formulas
-- LaunchServer also computes. Every function here was
-- moved VERBATIM, bodies and comments both; the only edits were removing the
-- `local` keyword's file scope and adding the export table at the bottom.
--
-- WHAT BELONGS HERE: a function belongs in this module if it is PURE -- a
-- function of its arguments and the shared config modules alone, holding no
-- state, touching no HUD, and closing over nothing this client owns. That is
-- also exactly the property that makes each one safe to mirror against
-- LaunchServer's own copy: two files can only be proved to agree about a
-- number if neither of them is reading anything the other cannot see.
--
-- WHAT DOES NOT: anything that reads this client's own swing pivot, its own
-- lane, its own tier or its own HUD. swingSeatPosition and landsOnLastBand
-- both stayed in LaunchClient for exactly that reason -- they close over
-- swingPivot -- and LaunchRemoteLanes keeps its own seatPositionForPivot for
-- the same reason in reverse (it is handed a pivot per lane). Those two
-- bodies are the same three lines against two different pivots; they were
-- left as they were found rather than merged, since merging them is a
-- behaviour-neutral change this pass was told not to make. See REPORT.md.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LaunchConfig = require(ReplicatedStorage.Config.LaunchConfig)
local LaneConfig = require(ReplicatedStorage.Config.LaneConfig)
local RunwayGeometry = require(ReplicatedStorage.Config.RunwayGeometry)
-- For BASE_BACK_EDGE_Z only -- the back of the plots, one of the two edges the
-- release camera is parked between. See releaseCameraPullback.
local BaseConfig = require(ReplicatedStorage.Config.BaseConfig)

local LaunchFormulas = {}

-- Mirrors LaunchServer's swingPhase()/swingTheta() exactly -- same shared
-- constants, same clock, same per-lane offset formula (six-lane pass 2).
-- Every call site passes a lane index explicitly -- this client's own
-- ownLaneIndex from LaunchClient, or a discovered lane's own from
-- LaunchRemoteLanes -- see ownLaneIndex's own comment there for how that is
-- guaranteed to match the server's copy.
local function swingPhase(laneIndex: number): number
	local t = Workspace:GetServerTimeNow()
	local offset = laneIndex * (LaunchConfig.SWING_PERIOD_SECONDS / LaneConfig.LANE_COUNT)
	return ((t + offset) % LaunchConfig.SWING_PERIOD_SECONDS) / LaunchConfig.SWING_PERIOD_SECONDS
end

local function swingTheta(phase: number): number
	local arc = math.rad(LaunchConfig.SWING_ARC_HALF_ANGLE_DEGREES)
	return arc * math.sin(2 * math.pi * phase)
end

-- BUG FIX (see the written report): this used to be a SEPARATE local
-- constant from LaunchServer's own flight-start offset -- two
-- independently-tuned copies of the same "how high above the seat does a
-- rider's root sit" number, which is exactly how they drifted apart and
-- produced a visible vertical pop at the instant of release. Both now read
-- LaunchConfig.RIDER_SEAT_HEIGHT_OFFSET -- see that constant's own comment.

local function riderCFrame(seatPosition: Vector3): CFrame
	local seatedPosition = seatPosition + Vector3.new(0, LaunchConfig.RIDER_SEAT_HEIGHT_OFFSET, 0)
	return CFrame.lookAt(seatedPosition, seatedPosition + Vector3.new(0, 0, -1))
end

-- Repositions every discrete chain-link part (Rope/Chain/Rod tiers -- see
-- SwingBuilder.luau), one side at a time, between THAT side's own fixed
-- anchor and THAT side's own seat attachment -- never a shared centre point
-- for both sides (see the written report on the crossed-chain bug this
-- fixed). Energy tiers build zero of these -- their tether is a Beam, which
-- auto-tracks its Attachments at the engine level and needs no script here
-- at all, so this is a cheap no-op for them (GetChildren on an empty
-- folder). Same "explicit basis vectors" orientation technique SwingBuilder
-- itself uses server-side, for the same reason: no rotation-sign ambiguity
-- to get backwards. "Chain" style's alternating 90-degree twist (the
-- classic linked-chain read) is stored as a Twist90 attribute at build time
-- and re-applied here every frame, since this function recomputes each
-- link's orientation from scratch rather than nudging whatever it had last
-- frame.
local function repositionChainSide(links: { Instance }, topPoint: Vector3, seatTopPosition: Vector3)
	local count = #links
	if count == 0 then
		return
	end
	table.sort(links, function(a, b)
		local indexA = (a:GetAttribute("ChainIndex") :: number?) or 0
		local indexB = (b:GetAttribute("ChainIndex") :: number?) or 0
		return indexA < indexB
	end)

	for i, link in links do
		if link:IsA("BasePart") then
			local segStart = topPoint:Lerp(seatTopPosition, (i - 1) / count)
			local segEnd = topPoint:Lerp(seatTopPosition, i / count)
			local delta = segEnd - segStart
			local length = delta.Magnitude
			if length > 1e-4 then
				if link.Shape == Enum.PartType.Cylinder then
					local xAxis = delta.Unit
					local reference = if math.abs(xAxis.Y) > 0.9 then Vector3.new(1, 0, 0) else Vector3.new(0, 1, 0)
					local yAxis = xAxis:Cross(reference).Unit
					link.CFrame = CFrame.fromMatrix((segStart + segEnd) / 2, xAxis, yAxis)
					link.Size = Vector3.new(length, link.Size.Y, link.Size.Z)
				else
					local yAxis = delta.Unit
					-- BUG FIX (chain links flipping thick/thin, see REPORT.md).
					-- This used to pick the reference the same way the Cylinder
					-- branch above still does:
					--   if math.abs(yAxis.Y) > 0.9 then (1,0,0) else (0,1,0)
					-- For a CYLINDER that is harmless -- it is radially symmetric
					-- about its length axis, so which perpendicular you pick can
					-- never be seen. For "Chain" style it is a visible bug: those
					-- links are BLOCKS with a 2:1 cross-section (chainThickness by
					-- chainThickness*0.5), so the reference decides which face is
					-- presented to the camera. The chain hangs at the swing's own
					-- theta, |cos(theta)| crosses 0.9 at theta = 25.84 degrees, and
					-- the swing travels +-35 -- so the branch flipped four times a
					-- cycle and took EVERY link's apparent thickness with it,
					-- inverting the whole alternating pattern mid-swing. Which
					-- thickness sat at the top was therefore a function of the
					-- swing's current angle, not of the link's index.
					--
					-- (1,0,0) UNCONDITIONALLY is correct here, not a workaround:
					-- each side's chain runs from an anchor at X = +-seatHalfWidth
					-- to a seat attachment at the SAME X, so delta.X is exactly
					-- zero and the chain direction always lies in the YZ plane.
					-- World X is the swing-plane normal -- perpendicular to yAxis
					-- by construction at every theta, so it can never go
					-- degenerate, and it is continuous where the old branch was
					-- not. It is also the exact branch SwingBuilder's own
					-- cframeFacingAlongY takes when it builds these links at the
					-- theta=0 reference pose, so the first repositioned frame now
					-- matches the built pose instead of popping.
					local reference = Vector3.new(1, 0, 0)
					local xAxis = reference:Cross(yAxis).Unit
					local cf = CFrame.fromMatrix((segStart + segEnd) / 2, xAxis, yAxis)
					if link:GetAttribute("Twist90") then
						cf = cf * CFrame.Angles(0, math.rad(90), 0)
					end
					link.CFrame = cf
					link.Size = Vector3.new(link.Size.X, length, link.Size.Z)
				end
			end
		end
	end
end

local function fillFraction(phase: number): number
	-- theta = ARC * sin(2pi*phase); fill = (theta/ARC + 1) / 2, i.e. just the sine
	-- itself remapped from [-1, 1] to [0, 1]. ARC cancels out entirely, so the bar
	-- doesn't even need the arc-angle constant.
	return (math.sin(2 * math.pi * phase) + 1) / 2
end

-- Circular distance between two phases in [0, 1) -- mirrors LaunchServer's
-- circularPhaseDistance/launchMultiplier exactly, same shared constants, so the
-- number shown here can never disagree with what a release would actually score.
local function circularPhaseDistance(a: number, b: number): number
	local d = math.abs(a - b) % 1
	return math.min(d, 1 - d)
end

-- Mirrors LaunchServer's snapThresholdForTier exactly -- same table, same
-- typeof check, same fallback to the global for a missing/short entry. The
-- snap threshold has been per-tier since the tier-11 pass; this file did not
-- get the memo, which is the whole of the bug in REPORT.md: the HUD snapped
-- tier 11's display to 2.00x at 1.90 while the server, on 1.95, sent the
-- graded value and the flight came down on the road. A launch is "perfect"
-- when it SNAPPED, and only the tier's own threshold decides that.
local function snapThresholdForTier(tier: number): number
	local perTier = LaunchConfig.SWING_TIER_SNAP_THRESHOLD[tier]
	return if typeof(perTier) == "number" then perTier else LaunchConfig.SWEET_SPOT_SNAP_THRESHOLD
end

local function launchMultiplier(phase: number, tier: number): number
	local distanceFromSweetSpot = circularPhaseDistance(phase, LaunchConfig.SWEET_SPOT_PHASE)
	local halfWidth = LaunchConfig.SWEET_SPOT_WIDTH / 2
	if distanceFromSweetSpot <= halfWidth then
		if halfWidth <= 0 then
			return LaunchConfig.SWEET_SPOT_MULTIPLIER
		end
		-- t = 1 at dead centre (distance 0), t = 0 at the window's edge.
		local t = 1 - (distanceFromSweetSpot / halfWidth)
		local graded = LaunchConfig.SWEET_SPOT_EDGE_MULTIPLIER
			+ (LaunchConfig.SWEET_SPOT_MULTIPLIER - LaunchConfig.SWEET_SPOT_EDGE_MULTIPLIER) * t
		if graded >= snapThresholdForTier(tier) then
			return LaunchConfig.SWEET_SPOT_MULTIPLIER
		end
		return graded
	end
	local t = 1 - (distanceFromSweetSpot - halfWidth) / (0.5 - halfWidth)
	t = math.clamp(t, 0, 1)
	return LaunchConfig.WORST_MULTIPLIER + (LaunchConfig.EDGE_MULTIPLIER - LaunchConfig.WORST_MULTIPLIER) * t
end

local function inSweetSpot(phase: number): boolean
	return circularPhaseDistance(phase, LaunchConfig.SWEET_SPOT_PHASE) <= LaunchConfig.SWEET_SPOT_WIDTH / 2
end

-- LaunchConfig.OUTCOME_BANDS is ordered highest-threshold-first and covers the
-- full multiplier range with no gaps -- first entry the multiplier meets or
-- beats wins. Returns the INDEX (not the band itself) so the style table below,
-- kept in this file rather than in config since colour/size is presentation
-- only, can be looked up in lockstep by position.
local function outcomeBandIndex(multiplier: number): number
	local bands = LaunchConfig.OUTCOME_BANDS
	for i, band in bands do
		if multiplier >= band.threshold then
			return i
		end
	end
	return #bands
end

-- Mirrors LaunchServer's trajectoryPosition exactly -- same shared distance/arc
-- height numbers, received once in FlightStarted below, not recomputed locally.
-- Y no longer returns to startPosition.Y at u=1 -- see LaunchServer's own
-- copy for the full reasoning; this is the same lerp-to-road-surface-plus-
-- bump formula, reading the SAME RunwayGeometry.RUNWAY_TOP_Y the server does.
local function trajectoryPosition(startPosition: Vector3, distance: number, archHeight: number, u: number): Vector3
	local x = startPosition.X
	local z = startPosition.Z - distance * u
	local descentY = startPosition.Y + (RunwayGeometry.RUNWAY_TOP_Y - startPosition.Y) * u
	local heightOffset = archHeight * 4 * u * (1 - u)
	return Vector3.new(x, descentY + heightOffset, z)
end

-- BUG FIX (jitter, see written report): this pitch math, and the character
-- PivotTo that uses it below, USED to run server-side every Heartbeat, with the
-- result only visible here at whatever rate Roblox batched the replication --
-- well under the chase camera's own full-frame-rate RenderStepped updates. That
-- mismatch (character at replication rate, camera at render rate) is what read
-- as jitter, identical in cause to the riding stutter fixed the previous pass.
-- Moved here verbatim (same formula, same clamp) so the character is now driven
-- from the exact same u, the exact same frame, as the camera that's looking at
-- it -- ruling out "camera and character from different u values" by
-- construction, not just by coincidence.
--
-- verticalRate now ALSO includes the constant descent slope trajectoryPosition
-- added above (RUNWAY_TOP_Y - startPosition.Y, the same at every u) -- without
-- it, the pitch would only ever reflect the parabolic bump's own rate and
-- would visibly disagree with the character's actual (now sloped) path,
-- worst at high tiers where the total descent is largest.
local MAX_FLIGHT_PITCH = math.rad(25)
local function trajectoryPitch(startPosition: Vector3, distance: number, archHeight: number, u: number): number
	local descentRate = RunwayGeometry.RUNWAY_TOP_Y - startPosition.Y
	local verticalRate = descentRate + archHeight * 4 * (1 - 2 * u)
	return math.clamp(math.atan2(verticalRate, distance), -MAX_FLIGHT_PITCH, MAX_FLIGHT_PITCH)
end

local function trajectoryCFrame(startPosition: Vector3, distance: number, archHeight: number, u: number): CFrame
	local position = trajectoryPosition(startPosition, distance, archHeight, u)
	local pitch = trajectoryPitch(startPosition, distance, archHeight, u)
	local facing = CFrame.lookAt(position, position + Vector3.new(0, 0, -1))
	return facing * CFrame.Angles(pitch, 0, 0)
end

-- BEHIND-AND-ABOVE CHASE FRAMING: sits a fixed offset relative to the
-- character -- behind (along +Z, opposite the -Z flight direction) and above
-- (tracking the character's CURRENT height, not a fixed world height, so a big
-- sweet-spot arc doesn't need a taller framing to still read as "behind and
-- above"). Orientation is a FIXED forward + downward tilt, not a look-at aimed
-- at the character -- that's deliberate: aiming level "at the character" would
-- center them in frame with the ground barely visible; tilting further down
-- than that puts the character in the upper-middle and lets the ground fill the
-- lower frame and converge toward the horizon ahead, which is the whole point.
-- Used ONCE now, to frame the very first instant of the flight -- see
-- FlightStarted below for why this is no longer computed every frame.
local function chaseCameraCFrame(characterPosition: Vector3, cameraBehindOffset: number): CFrame
	local cameraPosition = characterPosition + Vector3.new(0, LaunchConfig.CAMERA_HEIGHT_OFFSET, cameraBehindOffset)
	return CFrame.new(cameraPosition) * CFrame.Angles(-math.rad(LaunchConfig.CAMERA_DOWNWARD_ANGLE_DEGREES), 0, 0)
end

-- ===== WHERE THE RELEASE CAMERA STANDS. Returns how far BEHIND the rider the
-- camera is placed at the instant of release -- the one number chaseCameraCFrame
-- above takes.
--
-- DECOUPLED FROM ARC HEIGHT (see REPORT.md). This used to be
-- CAMERA_BEHIND_DISTANCE + archHeight * CAMERA_PULLBACK_FACTOR, and it was
-- broken in two separate ways:
--   1. it read ARCH, so retuning the flight's HEIGHT silently reframed the
--      launch -- which makes any arc change impossible to judge, since the
--      camera moves at the same time and by a proportional amount;
--   2. it was unbounded. Tier 11 asked for 1,093 studs. The only thing stopping
--      it was Roblox's default CameraMaxZoomDistance of 400, which this project
--      never sets -- an accident doing load-bearing work. And 400 was still too
--      far: the release camera sat at Z 418.5 with the Baseplate ending at
--      245.74, i.e. 173 studs PAST the back of the world, over void.
--
-- THE CAP IS DERIVED FROM THE MAP, not chosen. The camera is parked at the
-- MIDPOINT between the back of the plots (BaseConfig.BASE_BACK_EDGE_Z) and the
-- back of the world (RunwayGeometry.MAP_BACK_EDGE_Z) -- the point furthest from
-- both, so it is unambiguously inside the Baseplate and unambiguously behind
-- everything built. Both terms are read live, so moving the plots or resizing
-- the Baseplate moves the camera with them and there is no number here to go
-- stale.
--
-- THE SCALED TERM SURVIVES, on DISTANCE rather than arch. Below the cap the
-- camera still pulls back further for a longer flight -- CAMERA_PULLBACK_FACTOR
-- is now studs of pullback per stud of distance, set so the result is
-- numerically identical to what it was before this change. In practice only
-- tier 1 is under the cap, so tier 1's framing is untouched and every tier above
-- it is pinned to the map's own back edge.
local function releaseCameraPullback(startPositionZ: number, distance: number): number
	local requested = LaunchConfig.CAMERA_BEHIND_DISTANCE + distance * LaunchConfig.CAMERA_PULLBACK_FACTOR
	local standZ = (BaseConfig.BASE_BACK_EDGE_Z + RunwayGeometry.MAP_BACK_EDGE_Z) / 2
	return math.min(requested, standZ - startPositionZ)
end

LaunchFormulas.swingPhase = swingPhase
LaunchFormulas.swingTheta = swingTheta
LaunchFormulas.riderCFrame = riderCFrame
LaunchFormulas.repositionChainSide = repositionChainSide
LaunchFormulas.fillFraction = fillFraction
LaunchFormulas.circularPhaseDistance = circularPhaseDistance
LaunchFormulas.snapThresholdForTier = snapThresholdForTier
LaunchFormulas.launchMultiplier = launchMultiplier
LaunchFormulas.inSweetSpot = inSweetSpot
LaunchFormulas.outcomeBandIndex = outcomeBandIndex
LaunchFormulas.trajectoryPosition = trajectoryPosition
LaunchFormulas.trajectoryPitch = trajectoryPitch
LaunchFormulas.trajectoryCFrame = trajectoryCFrame
LaunchFormulas.chaseCameraCFrame = chaseCameraCFrame
LaunchFormulas.releaseCameraPullback = releaseCameraPullback

return LaunchFormulas
