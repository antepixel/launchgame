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
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local LaunchConfig = require(ReplicatedStorage.Config.LaunchConfig)
local RunwayGeometry = require(ReplicatedStorage.Config.RunwayGeometry)
local LuckCurve = require(ReplicatedStorage.Config.LuckCurve)
local SlimeConfig = require(ReplicatedStorage.Config.SlimeConfig)
local SwingTierVisuals = require(ReplicatedStorage.Config.SwingTierVisuals)
local SwingGeometry = require(ReplicatedStorage.Config.SwingGeometry)
-- Server-only siblings (see each module's own header for why these live in
-- ServerScriptService, not ReplicatedStorage, specifically).
local SlimeRoll = require(ServerScriptService.SlimeRoll)
local SwingBuilder = require(ServerScriptService.SwingBuilder)
-- Per-player base + income + collection + persistence + swing tier (see
-- PlayerProfile.luau). Reads here are scoped to exactly what a launch needs
-- to know (getSwingTier) and the two reveal-time calls from before
-- (recordSeen/placeSlime) -- nothing about the reveal's or the swing's own
-- timing/sequencing changes; see applySwingVisualForTier below for the
-- cosmetic state this file owns (the swing structure's per-tier look).
local PlayerProfile = require(ServerScriptService.PlayerProfile)

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
-- Server -> client: fires ONCE per landing that earned luck > 0, carrying the
-- box's starting luck (see the Heartbeat landing handler below). A 0-luck
-- landing never fires this -- see the written report for why no box appears
-- at all in that case.
local boxStartedRemote = makeRemote("BoxStarted")
-- Client -> server: content-free, exactly like Release -- a bare "I pressed"
-- signal. The server alone decides open-or-double; see onBoxPress.
local boxPressRemote = makeRemote("BoxPress")
-- Server -> client: fires once per resolved press, (opened: boolean, luck:
-- number) -- luck is either the DOUBLED value (opened = false, press again)
-- or the FINAL value (opened = true, sequence over).
local boxResultRemote = makeRemote("BoxResult")
-- Server -> client: fires ONCE per box that opens, REVEAL_BOX_TO_SLIME_DELAY_
-- SECONDS after BoxResult(opened=true) -- the second beat of the reveal (see
-- onBoxPress). Carries (globalIndex: number, isNew: boolean) -- the ONLY
-- slime identifier ever sent; the client looks up name/tier/colour/income
-- from the shared SlimeData table by this index, never from anything else
-- the server says.
local slimeRevealedRemote = makeRemote("SlimeRevealed")
-- Server -> client: fires ONCE per player, the moment they claim the (single,
-- shared) rider slot -- tells that client "you're the one who should render
-- yourself on the swing." See setupCharacter and the bug-2 fix in the written
-- report for why the client needs to know this now.
local ridingAssignedRemote = makeRemote("RidingAssigned")

local swingPivot = Workspace:WaitForChild("SwingPivot") :: BasePart

-- ===== The one real game swing's structure folder: this used to be owned
-- (created once, module-level) by SwingBuilder.luau itself; that module now
-- takes an explicit pivot/folder per call instead (see its own written
-- report -- the gallery refactor let more than one swing exist, and this
-- file's swingPivot/swingStructureFolder pair is what makes "the game's one
-- swing" specifically). The defensive stale-folder cleanup that used to live
-- in SwingBuilder moves here with it, for the exact same reason it existed
-- before: a folder left over from a previous run of THIS script (e.g. a
-- live code-sync without a full server restart) would never otherwise be
-- cleaned up, and would sit there forever at whatever tier/scale it was
-- last built at. =====
for _, existing in Workspace:GetChildren() do
	if existing.Name == "SwingStructure" then
		existing:Destroy()
	end
end
local swingStructureFolder = Instance.new("Folder")
swingStructureFolder.Name = "SwingStructure"
swingStructureFolder.Parent = Workspace

-- ===== Swing tier visual: the ENTIRE structure -- posts, beam, bracing,
-- caps, ground pads, seat, chain -- is a genuinely different, procedurally
-- built OBJECT per tier band, not the same four boxes resized/recoloured.
-- See SwingBuilder.luau for the construction code and SwingTierVisuals.luau
-- for every per-tier number/shape/material/colour; this file only ever
-- CALLS SwingBuilder.build(tier, swingPivot, swingStructureFolder), never
-- authors geometry itself. THIS FILE never touches LaunchConfig.
-- SWING_ROPE_LENGTH/SWING_ARC_HALF_ANGLE_DEGREES/SWING_PERIOD_SECONDS, so
-- swingTheta below stays exactly the same phase math regardless of tier.
-- SwingBuilder.build DOES move swingPivot's Y (see SwingGeometry.luau) so
-- the seat hangs proportionally higher on taller frames -- swingSeatPosition
-- below reads swingPivot.Position fresh every call, so it automatically
-- picks up whatever height the CURRENT rider's tier last set, with no
-- further change to this file needed. That move is purely a translation of
-- WHERE the arc sits, not its shape: swingTheta's amplitude and swingPhase's
-- timing read no position at all, so the seat's actual swept position (and
-- therefore the scoring math, which reads that exact position at release)
-- is exactly as sensitive to release timing at every tier, just centred at
-- a different height. =====
local function applySwingVisualForTier(tier: number)
	SwingBuilder.build(tier, swingPivot, swingStructureFolder)
end

-- BUG FIX: the swing used to exist from the moment the place file loaded --
-- SwingPost1/2/SwingBeam/SwingSeat were hand-placed, static parts in
-- default.project.json, so a fresh server had SOMETHING visible even before
-- applySwingVisualForTier was ever called (every call site below is inside a
-- player event handler -- clearActiveRider, setupCharacter, onRelease --
-- none of which fire at server startup). Now that the whole structure is
-- built by SwingBuilder instead of pre-placed, nothing would exist at all
-- until the first such event -- an empty server would show only the
-- invisible SwingPivot until a player joined and did something. Building
-- tier 1 once, right here, restores "the swing exists from server start."
applySwingVisualForTier(1)

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
	local pivotPosition = swingPivot.Position
	-- Effective rope length for WHATEVER tier is currently built -- derived
	-- from the pivot's own live Y (see SwingGeometry.ropeLengthForPivotY),
	-- not a raw LaunchConfig.SWING_ROPE_LENGTH read, since the rope is now
	-- scaled by tier right alongside the pivot (see SwingBuilder.luau).
	local length = SwingGeometry.ropeLengthForPivotY(pivotPosition.Y)
	return pivotPosition + Vector3.new(0, -length * math.cos(theta), -length * math.sin(theta))
end

local function circularPhaseDistance(a: number, b: number): number
	local d = math.abs(a - b) % 1
	return math.min(d, 1 - d)
end

-- The power curve: two ramps with a deliberate jump between them, not one
-- continuous curve and not a flat snap. Outside the sweet-spot window, a
-- gradual ramp from 0.75x (farthest point in the cycle) up to 1.5x (right at
-- the window's edge). Crossing INTO the window jumps straight to 1.8x -- that
-- gap is what makes a hit feel like a hit -- then ramps again, smoothly, up to
-- 2.0x at dead centre, so centring still rewards precision instead of the
-- whole window being an identical plateau. Anything graded at or above
-- SWEET_SPOT_SNAP_THRESHOLD then snaps up to exactly 2.0x -- landing on the
-- single exact centre phase is luck, not skill, so "close enough" is a real,
-- reachable perfect instead of a vanishingly rare bullseye.
local function launchMultiplier(phase: number): number
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
		if graded >= LaunchConfig.SWEET_SPOT_SNAP_THRESHOLD then
			return LaunchConfig.SWEET_SPOT_MULTIPLIER
		end
		return graded
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
-- Y no longer returns to startPosition.Y at u=1 -- it lerps from launch
-- height down to the road surface (RunwayGeometry.RUNWAY_TOP_Y) over the
-- WHOLE flight, with the SAME parabolic bump layered on top it always had.
-- archHeight itself is computed exactly as before (see onRelease) and still
-- adds exactly archHeight at u=0.5 relative to this now-sloped baseline --
-- only where u=1 lands changed, from launch height back to itself, to the
-- actual road surface (see the written report: without this, a taller
-- tier's launch height keeps climbing, per SwingGeometry, but the road
-- surface never moves, so the character would land further and further
-- above it as tier grows).
local function trajectoryPosition(startPosition: Vector3, distance: number, archHeight: number, u: number): Vector3
	local x = startPosition.X
	local z = startPosition.Z - distance * u
	local descentY = startPosition.Y + (RunwayGeometry.RUNWAY_TOP_Y - startPosition.Y) * u
	local heightOffset = archHeight * 4 * u * (1 - u)
	return Vector3.new(x, descentY + heightOffset, z)
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
-- impossible today (100-stud DISTANCE_PER_MULTIPLIER vs. a curve now ~2960
-- studs long -- see the written report) but must survive the road shrinking
-- or distances growing later. Clamped to the LAST band -- never an
-- out-of-range index, and never worse to travel farther than to travel less
-- far.
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

-- ===== Flight trail + launch burst (new this pass -- see SwingTierVisuals
-- for every per-tier number). Both are ordinary REPLICATED Instances created
-- SERVER-side (not in a LocalScript) specifically so every connected client
-- sees the same effect on the same character -- "visible from across the
-- map" requires that, not just the flying player's own view. =====

type TrailInstance = {
	trail: Trail,
	attachment0: Attachment,
	attachment1: Attachment,
}
type TrailRig = { TrailInstance }

-- Turns a list of 1+ colours into an EVENLY-SPACED ColorSequence -- a real
-- multi-stop gradient along the trail's length, not a flat hue, per the
-- written report (a single-colour list still produces a valid, uniform
-- ColorSequence).
local function colorSequenceFromList(colors: { Color3 }): ColorSequence
	if #colors <= 1 then
		return ColorSequence.new(colors[1] or Color3.new(1, 1, 1))
	end
	local keypoints = {}
	for i, color in colors do
		table.insert(keypoints, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), color))
	end
	return ColorSequence.new(keypoints)
end

-- One configured Trail + its two Attachments. `lateralOffset` shifts the
-- whole attachment pair sideways on the root part -- how the SECOND, layered
-- trail (top tiers only) sits beside the first instead of directly
-- overlapping it.
local function buildTrailInstance(
	rootPart: BasePart,
	colors: { Color3 },
	widthStart: number,
	widthEnd: number,
	lateralOffset: number,
	visual: SwingTierVisuals.TierVisual,
	name: string
): TrailInstance
	local attachment0 = Instance.new("Attachment")
	attachment0.Name = name .. "Attachment0"
	attachment0.Position = Vector3.new(lateralOffset - widthStart / 2, 0, 0)
	attachment0.Parent = rootPart

	local attachment1 = Instance.new("Attachment")
	attachment1.Name = name .. "Attachment1"
	attachment1.Position = Vector3.new(lateralOffset + widthStart / 2, 0, 0)
	attachment1.Parent = rootPart

	local trail = Instance.new("Trail")
	trail.Name = name
	trail.Attachment0 = attachment0
	trail.Attachment1 = attachment1
	trail.Color = colorSequenceFromList(colors)
	-- Fades from the tier's brightest point up to fully invisible over its
	-- own Lifetime -- a fixed flat transparency would just be a solid ribbon
	-- with a hard-cut end, not a fading streak.
	trail.Transparency = NumberSequence.new(visual.trailMinTransparency, 1)
	trail.Lifetime = visual.trailLifetime
	-- Tapers the attachment-defined base width DOWN toward the tail (1.0 at
	-- the character, widthEnd/widthStart at the far end) -- the "NumberSequence
	-- tapering the tail" the written report calls for, independent of the
	-- absolute width the attachments themselves define.
	trail.WidthScale = NumberSequence.new(1, if widthStart > 0 then widthEnd / widthStart else 0)
	trail.LightEmission = visual.trailLightEmission
	trail.FaceCamera = true
	-- Below this length the trail doesn't bother drawing a segment at all --
	-- avoids a flickery sliver of trail during near-stationary moments.
	-- NOT a custom Texture/TextureMode -- deliberately left at Roblox's
	-- default (a plain built-in fill), since a chain-link-style or custom
	-- texture would need an actual image asset, which the "no external
	-- assets" constraint rules out; Color/Transparency/WidthScale/
	-- LightEmission alone already give the tapering, gradient, glowing look
	-- asked for.
	trail.MinLength = visual.trailMinLength
	trail.Parent = rootPart

	return { trail = trail, attachment0 = attachment0, attachment1 = attachment1 }
end

-- nil at low tiers (visual.trailEnabled = false) -- "nothing at tier 1" is a
-- real absence, not a trail with transparency so high it can't be seen. A
-- SECOND, offset trail layers in at the top tiers (visual.secondTrailEnabled)
-- for a doubled-streak look, not just one wider ribbon.
local function createFlightTrail(rootPart: BasePart, visual: SwingTierVisuals.TierVisual): TrailRig?
	if not visual.trailEnabled then
		return nil
	end
	local rig: TrailRig = {
		buildTrailInstance(rootPart, visual.trailColors, visual.trailWidthStart, visual.trailWidthEnd, 0, visual, "FlightTrail"),
	}
	if visual.secondTrailEnabled then
		table.insert(
			rig,
			buildTrailInstance(
				rootPart,
				visual.secondTrailColors,
				visual.trailWidthStart * 0.6,
				visual.trailWidthEnd * 0.6,
				visual.secondTrailOffset,
				visual,
				"FlightTrail2"
			)
		)
	end
	return rig
end

local function destroyFlightTrail(rig: TrailRig?)
	if not rig then
		return
	end
	for _, instance in rig do
		instance.trail:Destroy()
		instance.attachment0:Destroy()
		instance.attachment1:Destroy()
	end
end

-- A ONE-SHOT puff at the exact instant/position of release -- never a
-- continuously-running emitter (Enabled stays false; :Emit fires the whole
-- burst in a single call). Cleans itself up on its own timer shortly after
-- its own particles would have faded, independent of the flight/landing
-- timeline entirely -- deliberately brief (see SwingTierVisuals.burstLifetime)
-- so it can never still be in frame interfering with the flight chase camera.
local function fireLaunchBurst(rootPart: BasePart, visual: SwingTierVisuals.TierVisual)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "LaunchBurst"
	emitter.Color = ColorSequence.new(visual.burstColor)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, visual.burstSize),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(visual.burstLifetime * 0.7, visual.burstLifetime)
	emitter.Speed = NumberRange.new(6, 14)
	emitter.SpreadAngle = Vector2.new(45, 45)
	emitter.Rate = 0
	emitter.Enabled = false
	emitter.Parent = rootPart
	emitter:Emit(visual.burstCount)

	task.delay(visual.burstLifetime + 0.1, function()
		if emitter.Parent then
			emitter:Destroy()
		end
	end)
end

type LoopState = "riding" | "inflight" | "box" | "cooldown"

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
	duration: number,
	startTime: number,
	poseJoints: PoseJoints,
	luck: number,
	trailRig: TrailRig?,
}
local activeFlight: Flight? = nil

-- The active mystery box -- set once per landing that earned luck > 0, read
-- and mutated (luck doubling) by every press until it opens. `pending` is
-- true from the moment a press is ACCEPTED until its delayed result fires --
-- see onBoxPress. `luck` starts at the landing's earned value and only ever
-- doubles; nothing here caps it.
type Box = {
	player: Player,
	character: Model,
	luck: number,
	pending: boolean,
}
local activeBox: Box? = nil

-- ===== DEV PANEL SUPPORT: rebuild the current rider's swing structure at
-- their CURRENT tier, touching no profile/tier state at all -- lets
-- SwingBuilder.luau/SwingTierVisuals.luau edits show up on an
-- already-seated rider without forcing an actual tier change (the only
-- other thing that ever calls applySwingVisualForTier). A BindableEvent,
-- not a RemoteEvent: DevPanelServer.server.luau (the only thing that ever
-- fires this) already owns both real gates (Studio-only + UserId
-- allowlist, re-checked per action) -- this is server-internal plumbing a
-- client can never reach directly regardless. Still created only in Studio,
-- same as DevPanelServer's own Gate 1, purely so no dev-only Instance
-- exists at all in a published server. =====
if RunService:IsStudio() then
	local devRebuildSwingEvent = Instance.new("BindableEvent")
	devRebuildSwingEvent.Name = "DevRebuildCurrentSwing"
	devRebuildSwingEvent.Parent = ServerScriptService
	devRebuildSwingEvent.Event:Connect(function()
		local tier = if activePlayer then PlayerProfile.getSwingTier(activePlayer) else 1
		applySwingVisualForTier(tier)
	end)
end

-- Frees the rider slot (on disconnect, death, or a missing character) without
-- otherwise touching the swing itself -- the seat keeps swinging empty either
-- way. Clearing activeBox here too (on TOP of resetting state away from
-- "box") is what guarantees a player leaving or dying mid-sequence can never
-- leave a stuck box: any in-flight delayed roll (see onBoxPress) checks
-- `activeBox ~= box or state ~= "box"` the instant its delay elapses and
-- simply bails if either has changed out from under it.
local function clearActiveRider()
	-- BUG FIX: an interrupted flight (e.g. the rider dies mid-air, see
	-- setupCharacter's humanoid.Died below -- PlayerRemoving doesn't need
	-- this, since a leaving player's whole character, trail included, is
	-- destroyed by Roblox automatically) used to leave its Trail/Attachments
	-- orphaned on the character forever, since this just discarded
	-- activeFlight without checking it for one first.
	if activeFlight then
		destroyFlightTrail(activeFlight.trailRig)
	end
	activePlayer = nil
	activeCharacter = nil
	activeFlight = nil
	activeBox = nil
	state = "riding"
	-- Nobody's riding -- the shared swing shows its baseline (tier 1) look
	-- rather than holding on to whatever the last rider's tier looked like.
	applySwingVisualForTier(1)
end

-- Shared by both the 0-luck landing path (no box) and the box's own "opened"
-- path -- identical reset behaviour either way, just reached from two places
-- now instead of one inline block.
local function scheduleReset(landedPlayer: Player, landedCharacter: Model)
	task.delay(LaunchConfig.RESET_DELAY, function()
		if landedPlayer.Character == landedCharacter and landedCharacter.Parent then
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
		if landedPlayer.Parent then
			resetReadyRemote:FireClient(landedPlayer)
		end
	end)
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
		-- Show THIS rider's own tier the moment they claim the seat -- see
		-- applySwingVisualForTier above.
		applySwingVisualForTier(PlayerProfile.getSwingTier(player))
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
	-- Swing tier scaling: a plain multiplier on top of the usual timing-based
	-- distance, read once here from THIS PLAYER's OWN tier (see
	-- PlayerProfile.getSwingTier/buyNextTier -- the old server-wide,
	-- hand-edited LaunchConfig.ACTIVE_SWING_TIER is gone). Bands themselves
	-- never change length or count -- this is the ONLY place tier
	-- progression enters the flight, which is what keeps it from having to
	-- touch the trajectory formula, the camera, or the band curve at all.
	local riderTier = PlayerProfile.getSwingTier(player)
	local tierScale = LaunchConfig.SWING_TIER_DISTANCE_SCALE[riderTier]
	-- Also refresh the whole swing's cosmetic look here -- covers a purchase
	-- made while already sitting on the swing (setupCharacter only stamps
	-- this once, at the moment the seat is claimed) showing up by the very
	-- next launch, not just the next time someone re-claims the seat.
	applySwingVisualForTier(riderTier)
	local distance = LaunchConfig.DISTANCE_PER_MULTIPLIER * multiplier * tierScale
	local archHeight = distance * LaunchConfig.ARC_HEIGHT_FRACTION
	-- Flight duration now scales WITH distance instead of staying fixed --
	-- see FLIGHT_DURATION_EXPONENT's comment in LaunchConfig for why a square
	-- root (not linear, not flat). baseDistance is deliberately NOT tier-
	-- scaled -- it's the fixed tier-1-perfect-launch anchor point that
	-- FLIGHT_DURATION_SECONDS was tuned against, the same reference for every
	-- tier's duration, not a per-tier moving target.
	local baseDistance = LaunchConfig.DISTANCE_PER_MULTIPLIER * LaunchConfig.SWEET_SPOT_MULTIPLIER
	local duration = LaunchConfig.FLIGHT_DURATION_SECONDS
		* (distance / baseDistance) ^ LaunchConfig.FLIGHT_DURATION_EXPONENT

	-- Launch from wherever the seat actually is right now (the swing never
	-- stops, so this is a moving origin).
	local startPosition = swingSeatPosition(swingTheta(phase)) + Vector3.new(0, 2, 0)
	character:PivotTo(CFrame.lookAt(startPosition, startPosition + Vector3.new(0, 0, -1)))

	-- Launch burst + flight trail: same per-tier visual record
	-- applySwingVisualForTier above just applied to the swing structure
	-- itself, reused here for the character. The burst fires once, right
	-- now, at the exact instant/position the character was just placed at.
	-- The trail (if this tier has one) attaches now and rides along for the
	-- rest of the flight -- see destroyFlightTrail in the Heartbeat landing
	-- handler below for where it comes off.
	local tierVisual = SwingTierVisuals.forTier(riderTier)
	fireLaunchBurst(rootPart, tierVisual)
	local trailRig = createFlightTrail(rootPart, tierVisual)

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
		duration = duration,
		startTime = startTime,
		poseJoints = poseJoints,
		luck = luck,
		trailRig = trailRig,
	}

	flightStartedRemote:FireClient(player, distance, archHeight, duration, startPosition, startTime, luck)
end

releaseRemote.OnServerEvent:Connect(onRelease)

Players.PlayerRemoving:Connect(function(player)
	if player == activePlayer then
		clearActiveRider()
	end
	-- PlayerProfile owns its own PlayerRemoving connection (save + base
	-- teardown, see PlayerProfile.luau) -- nothing to do here anymore.
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
	-- flight.duration, NOT the config constant directly -- see onRelease,
	-- where duration was computed once per flight from that flight's own
	-- (possibly tier-scaled) distance and stored here, exactly like distance
	-- and archHeight already were.
	local u = (Workspace:GetServerTimeNow() - flight.startTime) / flight.duration

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
	destroyFlightTrail(flight.trailRig)
	flight.rootPart.Anchored = false
	flight.humanoid.AutoRotate = true

	local landedPlayer = activePlayer
	local landedCharacter = activeCharacter
	local earnedLuck = flight.luck
	activeFlight = nil

	if not landedPlayer then
		-- Defensive only: activeFlight is never set without activePlayer (see
		-- onRelease) -- this can't actually happen, but keeps the type
		-- checker honest about Player? instead of asserting it away.
		state = "riding"
		return
	end

	if earnedLuck > 0 then
		-- Mystery box: the box's STARTING luck is the exact value already
		-- computed at release and already shown in the landing readout (see
		-- onRelease/bandLuckForLandingZ) -- carried forward, not rerolled or
		-- re-derived. Every press from here is scored in onBoxPress below.
		state = "box"
		activeBox = {
			player = landedPlayer,
			character = landedCharacter,
			luck = earnedLuck,
			pending = false,
		}
		boxStartedRemote:FireClient(landedPlayer, earnedLuck)
	else
		-- 0 luck: nothing was earned to gamble with, so no box appears at all
		-- -- straight to the existing reset flow, unchanged from before this
		-- pass. See the written report for why a box here (doubling zero
		-- forever) would just be a dead interaction.
		state = "cooldown"
		scheduleReset(landedPlayer, landedCharacter)
	end
end)

-- ===== Mystery box presses =====
-- After a landing with luck > 0, the player presses to open the box: each
-- accepted press is a fresh, independent, server-rolled coin flip
-- (BOX_DOUBLE_CHANCE to DOUBLE the luck and allow another press, the rest to
-- open) -- see LaunchConfig.BOX_DOUBLE_CHANCE. Uncapped by design: nothing
-- here stops the luck from doubling indefinitely -- a long chain is meant to
-- be rare and memorable, not something the game protects the player from.
local function onBoxPress(player: Player)
	if state ~= "box" or not activeBox or player ~= activeBox.player then
		return
	end
	-- RATE LIMIT + THE BEAT, same mechanism: a press is only even ACCEPTED
	-- (activeBox.pending flips true) once, and ignored on every repeat until
	-- its own delayed result has fired. A script mashing BoxPress as fast as
	-- it can therefore gets exactly one roll every BOX_ROLL_DELAY_SECONDS --
	-- the server never evaluates faster than that, no matter how many Presses
	-- arrive in between.
	if activeBox.pending then
		return
	end
	activeBox.pending = true
	local box = activeBox

	task.delay(LaunchConfig.BOX_ROLL_DELAY_SECONDS, function()
		-- The box (player left/died, see clearActiveRider) or the whole rider
		-- slot may have been torn down while this was pending. Bail without
		-- touching anything if this delayed roll is no longer the current one.
		if activeBox ~= box or state ~= "box" then
			return
		end

		-- THE ONLY THING A BOX ROLL IS EVER DERIVED FROM: math.random(),
		-- called here, server-side, the instant this delay elapses. The
		-- client sent nothing but a bare press signal, so there is no number
		-- in this path for a modified client to influence, let alone force a
		-- double or fake a luck value.
		local doubled = math.random() < LaunchConfig.BOX_DOUBLE_CHANCE
		if not doubled then
			local finalLuck = box.luck
			local landedPlayer = box.player
			local landedCharacter = box.character
			activeBox = nil
			state = "cooldown"
			boxResultRemote:FireClient(landedPlayer, true, finalLuck)

			-- THE SLIME: rolled immediately, server-side, from this box's own
			-- final luck -- see SlimeRoll.rollSlime. Nothing about WHICH
			-- slime is ever sent to or influenced by the client; only its
			-- globalIndex goes over the wire (see slimeRevealedRemote above),
			-- and the client looks up name/tier/colour/income from the same
			-- shared SlimeData table this rolled from. The roll itself lives
			-- in a ServerScriptService module a client cannot even require,
			-- let alone call.
			local slime = SlimeRoll.rollSlime(finalLuck)
			local isNew = PlayerProfile.recordSeen(landedPlayer, slime.globalIndex)

			-- THE SECOND BEAT: the box's own "OPENED!" is already the first
			-- (see BOX_ROLL_DELAY_SECONDS) -- this is a SEPARATE delay before
			-- the slime itself appears, so the two don't land in the same
			-- instant (see the written report for why). scheduleReset moves
			-- HERE too, not before -- RESET_DELAY should count down from the
			-- LATEST thing the player needs to read (the slime), not the
			-- box's own open moment.
			task.delay(SlimeConfig.REVEAL_BOX_TO_SLIME_DELAY_SECONDS, function()
				if landedPlayer.Parent then
					slimeRevealedRemote:FireClient(landedPlayer, slime.globalIndex, isNew)
				end
				-- THE BASE: handed off at the exact moment of the reveal, not
				-- before -- see PlayerProfile.receiveSlime. Auto-placed if a
				-- slot is free, otherwise added to that player's inventory
				-- (never discarded -- see PlayerProfile.luau and the written
				-- report); nothing here needs the return value.
				PlayerProfile.receiveSlime(landedPlayer, slime)
				scheduleReset(landedPlayer, landedCharacter)
			end)
		else
			box.luck *= 2
			box.pending = false
			boxResultRemote:FireClient(box.player, false, box.luck)
		end
	end)
end

boxPressRemote.OnServerEvent:Connect(onBoxPress)
