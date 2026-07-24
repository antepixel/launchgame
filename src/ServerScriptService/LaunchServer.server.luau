--!strict
-- Authoritative launch loop. Flight is a computed parabola, not simulated
-- physics: on Release, the server derives a landing distance and arc height
-- DIRECTLY from the multiplier (no speed, no velocity vector, no gravity
-- integration). Same multiplier -> same distance -> same path, always. See
-- trajectoryPosition and onRelease below.
--
-- What changed THIS pass: the server no longer drives the character's CFrame
-- every Heartbeat during flight -- that visual positioning moved to the client
-- (see LaunchClient.client.luau's trajectoryPitch/trajectoryCFrame), for the
-- same reason "riding" moved there the previous pass: a character updated at
-- Heartbeat-then-replication rate, watched by a camera rendering every
-- RenderStepped, reads as jitter. The server still computes the authoritative
-- distance at release and still places the character at the final landing
-- position once, when the flight completes -- see the written report.
--
-- THE PENDULUM IS STILL SCRIPTED (unchanged): the swing's seat position is a
-- sine wave, not a physics constraint -- see swingTheta/swingSeatPosition.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local LaunchConfig = require(ReplicatedStorage.Config.LaunchConfig)
local RunwayGeometry = require(ReplicatedStorage.Config.RunwayGeometry)
local LuckCurve = require(ReplicatedStorage.Config.LuckCurve)

Workspace.Gravity = LaunchConfig.GRAVITY

-- Remotes are created here, synchronously, before any LocalScript can run, so a
-- client's WaitForChild for these can never race a missing folder.
local remotesFolder = Instance.new("Folder")
remotesFolder.Name = "Remotes"
remotesFolder.Parent = ReplicatedStorage

local function makeRemote(name: string): RemoteEvent
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remotesFolder
	return remote
end

-- Client -> server: content-free (no arguments carry any gameplay value).
local releaseRemote = makeRemote("Release")
-- Server -> client: fires ONCE, at release, carrying the FULL deterministic
-- flight description (distance, arc height, duration, start TIME, start
-- position, luck) so the client can independently drive its camera and live
-- distance counter for the whole flight without any further messages -- see
-- LaunchClient.client.luau.
local flightStartedRemote = makeRemote("FlightStarted")
local resetReadyRemote = makeRemote("ResetReady")
-- Server -> client: fires ONCE per player, the moment they claim the (single,
-- shared) rider slot -- tells that client "you're the one who should render
-- yourself on the swing." See setupCharacter and the bug-2 fix in the written
-- report for why the client needs to know this now.
local ridingAssignedRemote = makeRemote("RidingAssigned")

local swingPivot = Workspace:WaitForChild("SwingPivot") :: BasePart

-- ===== Swing math (unchanged from the previous pass) =====

local function swingPhase(): number
	local t = Workspace:GetServerTimeNow()
	return (t % LaunchConfig.SWING_PERIOD_SECONDS) / LaunchConfig.SWING_PERIOD_SECONDS
end

local function swingTheta(phase: number): number
	local arc = math.rad(LaunchConfig.SWING_ARC_HALF_ANGLE_DEGREES)
	return arc * math.sin(2 * math.pi * phase)
end

local function swingSeatPosition(theta: number): Vector3
	local length = LaunchConfig.SWING_ROPE_LENGTH
	return swingPivot.Position + Vector3.new(0, -length * math.cos(theta), -length * math.sin(theta))
end

local function circularPhaseDistance(a: number, b: number): number
	local d = math.abs(a - b) % 1
	return math.min(d, 1 - d)
end

-- The power curve: a flat 2.0x SNAP anywhere inside the sweet-spot window, and a
-- gradual ramp from 0.75x (farthest point in the cycle) up to 1.5x (right at the
-- window's edge) everywhere outside it.
local function launchMultiplier(phase: number): number
	local distanceFromSweetSpot = circularPhaseDistance(phase, LaunchConfig.SWEET_SPOT_PHASE)
	local halfWidth = LaunchConfig.SWEET_SPOT_WIDTH / 2
	if distanceFromSweetSpot <= halfWidth then
		return LaunchConfig.SWEET_SPOT_MULTIPLIER
	end
	local t = 1 - (distanceFromSweetSpot - halfWidth) / (0.5 - halfWidth)
	t = math.clamp(t, 0, 1)
	return LaunchConfig.WORST_MULTIPLIER + (LaunchConfig.EDGE_MULTIPLIER - LaunchConfig.WORST_MULTIPLIER) * t
end

-- ===== Scripted flight math: the SERVER only needs the plain POSITION now (for
-- the one-time authoritative landing placement below) -- the pitched CFrame
-- version moved to the client, which is what actually drives the character's
-- visual CFrame every frame during flight now. See LaunchClient.client.luau's
-- trajectoryPitch/trajectoryCFrame for the pitch math (unchanged formula, just
-- relocated) and the written report for why. =====

-- u in [0,1] is flight progress. Horizontal position is a plain lerp along -Z
-- (forward); height is a symmetric parabola that's exactly 0 at u=0 and u=1 and
-- exactly archHeight at u=0.5 -- the closed form for "starts and ends at the same
-- height, peaks in the middle," which is also what a real constant-gravity
-- projectile's height-over-time looks like for a fixed flight duration, even
-- though nothing here is integrating gravity to get it.
local function trajectoryPosition(startPosition: Vector3, distance: number, archHeight: number, u: number): Vector3
	local horizontal = startPosition + Vector3.new(0, 0, -distance * u)
	local heightOffset = archHeight * 4 * u * (1 - u)
	return horizontal + Vector3.new(0, heightOffset, 0)
end

-- ===== Rainbow band -> luck =====
-- Band index (0-based) a world Z position falls under, using the SAME
-- RunwayGeometry.RUNWAY_START_Z and LaunchConfig.RUNWAY_BAND_LENGTH_STUDS that
-- RunwayBuilder used to physically place the coloured parts (see
-- RunwayGeometry.luau), then looked up in the SAME LuckCurve.VALUES table
-- RunwayBuilder read to label them (see LuckCurve.luau) -- not a re-derived
-- approximation anywhere in this chain, the literal same numbers throughout.
-- That's what guarantees the band awarded here is the band the player is
-- actually standing on when they land, not just usually the same one.
--
-- BOUNDARY RULE: band i owns distance-from-start in the HALF-OPEN interval
-- [i*L, (i+1)*L) -- landing exactly on a seam always resolves to the FARTHER
-- band. Floor division gives this for free with no special-casing: reaching a
-- boundary means you've travelled the full length of the nearer band, so you
-- get the one whose front edge you're now standing on.
--
-- SHORT of band 0 (negative distance-from-start -- landed on the platform,
-- before the runway starts): 0 luck, not a floor/minimum. This is a
-- deliberate whiff signal -- a badly-timed release should read as "no luck,"
-- distinct from barely clipping band 1. A minimum would blur that line and
-- blunt the sweet-spot's whole point of rewarding precision.
--
-- PAST the last band (distance-from-start >= #LuckCurve.VALUES * L): still
-- impossible today (50-stud max distance vs. a curve now ~1480 studs long --
-- see the written report) but must survive the road shrinking or distances
-- growing later. Clamped to the LAST band -- never an out-of-range index, and
-- never worse to travel farther than to travel less far.
local function bandLuckForLandingZ(landingZ: number): number
	local distanceFromStart = RunwayGeometry.RUNWAY_START_Z - landingZ
	if distanceFromStart < 0 then
		return 0
	end
	local index = math.floor(distanceFromStart / LaunchConfig.RUNWAY_BAND_LENGTH_STUDS)
	index = math.clamp(index, 0, #LuckCurve.VALUES - 1)
	return LuckCurve.VALUES[index + 1]
end

-- ===== Flight pose: a cheap static "flailing" silhouette (arms out/up, legs
-- trailing back) applied directly to the rig's shoulder/hip Motor6Ds -- no
-- physics, no ragdoll, no Animation asset. This is a DIRECT CFrame edit, not an
-- animation track: set once at release, held for the whole flight (the body's
-- overall tilt is what moves, via the CLIENT's trajectoryCFrame pitch -- see
-- LaunchClient.client.luau), restored to whatever the joint's C0 actually was
-- the instant the character lands. STAYS SERVER-SIDE (unlike the per-frame
-- position/rotation, which moved to the client this pass): it's set exactly
-- ONCE per flight and held, not written every frame, so it was never the
-- source of the jitter and has nothing to gain from moving. Handles both R15
-- (space-less joint names, split UpperTorso/LowerTorso) and R6 (spaced names,
-- single Torso) rigs; if a rig has neither, the pose is silently skipped and
-- only the overall body tilt still applies -- never an error.
local ARM_SPREAD = math.rad(65)
local ARM_LIFT = math.rad(35)
local LEG_TRAIL = math.rad(20)

type PoseJoints = { [Motor6D]: CFrame }

local function findMotor6D(container: Instance?, nameA: string, nameB: string): Motor6D?
	if not container then
		return nil
	end
	local found = container:FindFirstChild(nameA) or container:FindFirstChild(nameB)
	if found and found:IsA("Motor6D") then
		return found
	end
	return nil
end

local function applyFlightPose(character: Model): PoseJoints
	local upperTorso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	local lowerTorso = character:FindFirstChild("LowerTorso") or character:FindFirstChild("Torso")
	local leftShoulder = findMotor6D(upperTorso, "LeftShoulder", "Left Shoulder")
	local rightShoulder = findMotor6D(upperTorso, "RightShoulder", "Right Shoulder")
	local leftHip = findMotor6D(lowerTorso, "LeftHip", "Left Hip")
	local rightHip = findMotor6D(lowerTorso, "RightHip", "Right Hip")

	local original: PoseJoints = {}
	if leftShoulder then
		original[leftShoulder] = leftShoulder.C0
		leftShoulder.C0 = leftShoulder.C0 * CFrame.Angles(-ARM_LIFT, 0, -ARM_SPREAD)
	end
	if rightShoulder then
		original[rightShoulder] = rightShoulder.C0
		rightShoulder.C0 = rightShoulder.C0 * CFrame.Angles(-ARM_LIFT, 0, ARM_SPREAD)
	end
	if leftHip then
		original[leftHip] = leftHip.C0
		leftHip.C0 = leftHip.C0 * CFrame.Angles(LEG_TRAIL, 0, 0)
	end
	if rightHip then
		original[rightHip] = rightHip.C0
		rightHip.C0 = rightHip.C0 * CFrame.Angles(LEG_TRAIL, 0, 0)
	end
	return original
end

local function restoreFlightPose(joints: PoseJoints)
	for joint, originalC0 in joints do
		joint.C0 = originalC0
	end
end

type LoopState = "riding" | "inflight" | "cooldown"

-- One shared rider slot for this prototype (same limitation every previous pass
-- had): only one player can be on/using the swing at a time.
local state: LoopState = "riding"
local activePlayer: Player? = nil
local activeCharacter: Model? = nil

-- The active flight's fixed, precomputed description -- set once at release,
-- read every Heartbeat until duration elapses. Nothing here ever changes mid-flight.
type Flight = {
	rootPart: BasePart,
	humanoid: Humanoid,
	startPosition: Vector3,
	distance: number,
	archHeight: number,
	startTime: number,
	poseJoints: PoseJoints,
	luck: number,
}
local activeFlight: Flight? = nil

-- Frees the rider slot (on disconnect, death, or a missing character) without
-- otherwise touching the swing itself -- the seat keeps swinging empty either way.
local function clearActiveRider()
	activePlayer = nil
	activeCharacter = nil
	activeFlight = nil
	state = "riding"
end

-- HUMANOID SETUP, done once per character (not per launch). Ragdoll/FallingDown
-- disabling, the Freefall state-fight, and the fall-damage guard from the
-- physics-flight pass are ALL GONE (see the written report) -- flight is now
-- fully scripted with the root part anchored, so there is no physics event left
-- for any of those to fight. AutoRotate stays off continuously from spawn: the
-- rider's character is kinematically repositioned CLIENT-SIDE now, both while
-- riding and while flying (see the written report for the flight half of that),
-- and AutoRotate fighting that is still exactly the kind of jitter the
-- camera-whip fix several passes ago was written to avoid.
local function setupCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.AutoRotate = false

	humanoid.Died:Connect(function()
		if player == activePlayer then
			clearActiveRider()
		end
	end)

	if activePlayer == nil then
		activePlayer = player
		activeCharacter = character
		state = "riding"
		-- The server no longer repositions the rider every Heartbeat (that's the
		-- bug-2 fix -- the CLIENT now drives this visually, every RenderStepped,
		-- from the same shared swing math). Anchoring the root is what keeps the
		-- character from just falling now that nothing server-side is holding it
		-- in place frame to frame; the client is free to set an anchored part's
		-- CFrame locally without anything fighting it, since the server simply
		-- never writes to it while riding.
		local rootPart = humanoid.RootPart
		if rootPart then
			rootPart.Anchored = true
		end
		ridingAssignedRemote:FireClient(player)
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		setupCharacter(player, character)
	end)
	if player.Character then
		setupCharacter(player, player.Character)
	end
end)
for _, player in Players:GetPlayers() do
	player.CharacterAdded:Connect(function(character)
		setupCharacter(player, character)
	end)
	if player.Character then
		setupCharacter(player, player.Character)
	end
end

local function onRelease(player: Player)
	if state ~= "riding" or player ~= activePlayer then
		return
	end
	local character = activeCharacter
	if not character then
		clearActiveRider()
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not humanoid or humanoid.Health <= 0 then
		clearActiveRider()
		return
	end
	local rootPart = humanoid.RootPart
	if not rootPart then
		clearActiveRider()
		return
	end

	-- THE ONLY THING RELEASE POWER IS EVER DERIVED FROM: the server's own
	-- swingPhase(), read at the instant the server itself receives this event.
	-- The client sent nothing but a bare signal -- no phase, no distance -- so
	-- there is no number here for a modified client to lie about.
	--
	-- WHAT THIS FIXES FOR FREE: distance is now a pure function of the
	-- multiplier, computed HERE, before the flight animation even starts. The
	-- previous pass's known weakness -- reading a client-owned character's
	-- Position at landing, which is functionally client-reported data -- no
	-- longer exists, because the server never needs to read the character's
	-- position back out to know the distance. It already knows the exact
	-- distance the instant it computes the multiplier. The client's copy of the
	-- flight (camera, live counter) is downstream, cosmetic, and can't feed
	-- anything back into this number.
	local phase = swingPhase()
	local multiplier = launchMultiplier(phase)
	local distance = LaunchConfig.DISTANCE_PER_MULTIPLIER * multiplier
	local archHeight = distance * LaunchConfig.ARC_HEIGHT_FRACTION

	-- Launch from wherever the seat actually is right now (the swing never
	-- stops, so this is a moving origin).
	local startPosition = swingSeatPosition(swingTheta(phase)) + Vector3.new(0, 2, 0)
	character:PivotTo(CFrame.lookAt(startPosition, startPosition + Vector3.new(0, 0, -1)))

	-- NO PHYSICS: anchor the root part so gravity, collision, and the humanoid's
	-- own controller cannot touch it. BUG FIX (see written report): the server
	-- itself no longer moves this part during flight either -- it stays anchored
	-- for exactly the same reason it did before (nothing may fight it), but the
	-- actual per-frame positioning is now done by the CLIENT (every
	-- RenderStepped, from the same trajectory math), because the character
	-- arriving at Heartbeat-then-replication rate while the chase camera (which
	-- looks directly at it) rendered every RenderStepped is what caused the
	-- flight jitter -- identical in cause to the riding stutter fixed earlier.
	rootPart.Anchored = true
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero

	-- Landing is fully known already, same as distance/archHeight above -- reuse
	-- the EXACT trajectoryPosition call (u = 1) that the Heartbeat loop below
	-- will use to actually place the character at landing, so the Z fed into
	-- bandLuckForLandingZ can never diverge from the Z the character actually
	-- ends up standing at.
	local landingPosition = trajectoryPosition(startPosition, distance, archHeight, 1)
	local luck = bandLuckForLandingZ(landingPosition.Z)

	local poseJoints = applyFlightPose(character)

	-- BUG FIX (see written report): this used to be os.clock(), the SERVER's
	-- own local, unsynced clock. The client independently timed its copy of the
	-- flight from ITS OWN os.clock(), started only once the FlightStarted
	-- message actually arrived -- always at least one network hop later than
	-- this instant, with no guaranteed relationship to the server's timeline.
	-- Under enough latency, the server's OWN flight (and the RESET_DELAY after
	-- it) could complete, and ResetReady arrive, before the client's late-
	-- started local countup had rendered its way up to the true final number --
	-- so the display could get abandoned mid-count, showing a partial value
	-- instead of the real one. Workspace:GetServerTimeNow() is a clock Roblox
	-- keeps synchronized between server and every client (already used for the
	-- swing's phase for exactly this reason): both sides now measure flight
	-- progress from the SAME absolute instant, so the client's u lines up with
	-- the server's regardless of how long the message itself took to arrive.
	local startTime = Workspace:GetServerTimeNow()

	state = "inflight"
	activeFlight = {
		rootPart = rootPart,
		humanoid = humanoid,
		startPosition = startPosition,
		distance = distance,
		archHeight = archHeight,
		startTime = startTime,
		poseJoints = poseJoints,
		luck = luck,
	}

	flightStartedRemote:FireClient(player, distance, archHeight, LaunchConfig.FLIGHT_DURATION_SECONDS, startPosition, startTime, luck)
end

releaseRemote.OnServerEvent:Connect(onRelease)

Players.PlayerRemoving:Connect(function(player)
	if player == activePlayer then
		clearActiveRider()
	end
end)

-- This loop used to ALSO reposition the rider every Heartbeat while "riding"
-- (fixed in the previous pass -- moved to the client, see LaunchClient.client.luau)
-- AND the flier every Heartbeat while "inflight" (fixed THIS pass, same cause,
-- same fix). Both were a ~60Hz SERVER-side write, visible to the player only at
-- whatever rate Roblox's replication batches property changes -- well under
-- 60Hz -- while the client's OWN camera (riding: the bar's cosmetic math;
-- flying: the chase cam) updated every RenderStepped, at full render rate. A
-- previous pass's assumption that flight was exempt from this ("the flying
-- player's camera doesn't watch the replicated character") was wrong -- the
-- chase cam looks directly at the character's trajectory position, so the
-- mismatch between a smoothly-moving camera and a replication-rate-limited
-- character was exactly as visible as the riding stutter had been.
--
-- The server now does NOT touch the character's CFrame at any point during
-- flight. All it does here is wait for the shared, synced-clock-anchored
-- duration to elapse (the SAME check that already existed -- this part is
-- unchanged), then perform the ONE-TIME, authoritative landing placement --
-- a single discrete update has no "rate" to stutter at. Scoring (the swing's
-- phase read fresh from Workspace:GetServerTimeNow() the instant Release
-- arrives, in onRelease above) is completely unaffected by any of this.
RunService.Heartbeat:Connect(function()
	if state ~= "inflight" or not activeFlight or not activeCharacter then
		return
	end
	local flight = activeFlight
	local u = (Workspace:GetServerTimeNow() - flight.startTime) / LaunchConfig.FLIGHT_DURATION_SECONDS

	if u < 1 then
		return
	end

	-- Flight complete: place exactly at the landing point (u = 1, deterministic,
	-- no drift), LEVEL (not the tipped-forward landing pitch -- that's for mid-
	-- flight only; standing normally starts from level), unanchor, restore the
	-- limb pose and normal control.
	local landingPosition = trajectoryPosition(flight.startPosition, flight.distance, flight.archHeight, 1)
	activeCharacter:PivotTo(CFrame.lookAt(landingPosition, landingPosition + Vector3.new(0, 0, -1)))
	restoreFlightPose(flight.poseJoints)
	flight.rootPart.Anchored = false
	flight.humanoid.AutoRotate = true

	local landedPlayer = activePlayer
	local landedCharacter = activeCharacter
	state = "cooldown"
	activeFlight = nil

	task.delay(LaunchConfig.RESET_DELAY, function()
		if landedPlayer and landedPlayer.Character == landedCharacter and landedCharacter.Parent then
			local humanoid = landedCharacter:FindFirstChildOfClass("Humanoid")
			local rootPart = humanoid and humanoid.RootPart
			if rootPart then
				rootPart.AssemblyLinearVelocity = Vector3.zero
				rootPart.AssemblyAngularVelocity = Vector3.zero
				-- Re-anchor: back to "riding," where the CLIENT takes over
				-- positioning again (see setupCharacter's comment) -- nothing
				-- server-side will reposition this part again until the next
				-- release, so it must not be free to fall in the meantime.
				rootPart.Anchored = true
			end
			if humanoid then
				humanoid.AutoRotate = false
			end
		end
		state = "riding"
		if landedPlayer and landedPlayer.Parent then
			resetReadyRemote:FireClient(landedPlayer)
		end
	end)
end)
