--!strict
-- Idle squash-and-stretch on every visible slime mesh -- the placed slot
-- slimes in every player's base AND the giant landmark -- so they read as
-- living jelly rather than static props.
--
-- ENTIRELY CLIENT-SIDE AND NON-REPLICATING (see the written report). Every
-- part of every slime is Anchored (SlimeBuilder.build sets Anchored = true /
-- CanCollide = false on all four), and Roblox property replication is
-- one-directional and server-authoritative: a client's Size/CFrame writes
-- stay local and are never sent up. The only client-to-server physics path
-- needs network ownership, which needs an UNANCHORED part, so there is none
-- here to claim. Nothing is fought over either -- the server writes a slime's
-- transform exactly once, at spawn (PlayerProfile.spawnSlimeVisual), and
-- afterwards only ever Destroys it. Doing this server-side instead would be
-- 60 slimes' worth of replicated per-frame CFrame writes: precisely the
-- mistake the six-lane remote-rendering pass was written to undo.
--
-- DELIBERATELY ITS OWN SCRIPT AND ITS OWN RenderStepped, not an addition to
-- LaunchClient.client.luau, which is not touched by this file at all. That
-- file already keeps its local-player render path and its six-lane remote
-- block structurally apart for exactly this reason (see its own comment above
-- SWING_PIVOT_NAME_PATTERN); a third concern belongs in a third connection.
-- Nothing here reads or writes a swing pivot, a SwingStructure_* folder, the
-- character, the nametag BillboardGui, the EntranceSign, or the landmark's
-- GroundPatch -- only Size and CFrame on the four MeshParts of a slime.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local SlimeIdleConfig = require(ReplicatedStorage.Config.SlimeIdleConfig)

-- The template's own part names (see SlimeBuilder.luau, which builds every
-- slime in the game from one flat four-MeshPart model). The body doubles as
-- the DISCOVERY PREDICATE below -- "a Model containing a MeshPart named
-- slime" -- because a slime Model's NAME is the slime's own display name
-- ("Secret Slime 20"), which is neither unique nor stable, and its sibling in
-- the same folder is the EntranceSign, whose parts are board/post.
local BODY_PART_NAME = "slime"
local FACE_PART_NAMES = { "eye_dark", "eye_white", "blush" }

-- Which face parts a blink sinks into the head. The two eyes only -- blush
-- breathes with everything else and is never blinked, and the body is never
-- touched by the blink at all. Read ONCE at capture, where it is baked into
-- each part's FacePart.sinkOffset (zero for blush), so the frame loop never
-- does a name comparison or a branch.
local BLINKING_PART_NAMES: { [string]: boolean } = { eye_dark = true, eye_white = true }

-- The dominant cardinal direction of `v`, as a unit vector -- used to turn the
-- measured face-part layout into the body's face axis (see entryFor).
local function dominantCardinal(v: Vector3): Vector3
	local ax, ay, az = math.abs(v.X), math.abs(v.Y), math.abs(v.Z)
	if ax >= ay and ax >= az then
		return Vector3.new(math.sign(v.X), 0, 0)
	elseif ay >= az then
		return Vector3.new(0, math.sign(v.Y), 0)
	end
	return Vector3.new(0, 0, math.sign(v.Z))
end

-- Spacing for the per-blink jitter (see the blink block in renderIdleSlimes).
-- The golden-ratio conjugate: stepping by it and taking the fractional part
-- gives a low-discrepancy sequence, so successive blink cycles land at
-- well-spread points rather than repeating -- which is what stops a slime
-- settling into a metronomic rhythm. Not a tuning value, so not in config.
local BLINK_JITTER_STRIDE = 0.6180339887498949

-- PERMISSIVE ON PURPOSE, and for the same reason LaunchClient's own
-- SWING_PIVOT_NAME_PATTERN is: "%d+" matches digits ONLY, with no
-- leading-minus case, so it silently rejects every Base_<UserId> whose UserId
-- is negative -- and Studio multi-client test sessions hand out negative
-- placeholder UserIds. ".+" takes whatever is there; the capture itself is
-- never used for anything here, only its presence.
local BASE_FOLDER_NAME_PATTERN = "^Base_(.+)$"
local LANDMARK_NAME = "GiantSlimeLandmark"

local TAU = 2 * math.pi

-- One face part's fixed relationship to the body, measured once. `baseOffset`
-- is in BODY-LOCAL space, not world -- a placed slime is yawed by the facing
-- correction (see spawnSlimeVisual), so a world-space offset would be wrong
-- for every slime that is not axis-aligned, and would additionally have to be
-- re-derived whenever the body moves.
type FacePart = {
	part: MeshPart,
	baseSize: Vector3,
	baseOffset: Vector3,
	baseRotation: CFrame,
	-- Full-depth blink displacement, in BODY-LOCAL space, precomputed at
	-- capture. Vector3.zero for parts that do not blink (blush), which is what
	-- lets the frame loop apply it unconditionally with no branch and no name
	-- comparison. Scaled by 0..1 per frame -- see the blink block in
	-- renderIdleSlimes.
	sinkOffset: Vector3,
}

-- Everything the per-frame path needs about one slime, all of it constant.
-- The frame loop never reads a live Size or CFrame off any part -- see
-- entryFor below for why that is a structural guarantee rather than a
-- discipline.
type SlimeEntry = {
	-- HELD DELIBERATELY, and load-bearing -- see the baselines registry below.
	-- The entry does not otherwise need the Model; it exists so that anything
	-- holding an entry also holds a STRONG Lua reference to the Model whose
	-- baseline it is.
	model: Model,
	body: MeshPart,
	bodyBaseSize: Vector3,
	bodyBaseRotation: CFrame,
	bodyBaseX: number,
	bodyBaseZ: number,
	restY: number,
	phase: number,
	blinkInterval: number,
	faceParts: { FacePart },
}

-- A STABLE PER-MODEL PHASE, so ten slimes in one base do not pulse in
-- lockstep. Derived from the body's own spawn position, which is the only
-- thing about a slime that is both unique among its neighbours and identical
-- on every rescan and every client. (Instance:GetDebugId() would also be
-- stable, but it is PluginSecurity and simply is not callable from a
-- LocalScript -- an option worth ruling out explicitly, since it looks
-- available.)
--
-- A SEEDED PRNG, NOT AN ARITHMETIC HASH -- this was measured, not guessed.
-- The slots sit on a strictly REGULAR grid (22 studs across, 14 along, 80
-- between lanes -- see BaseGeometry.slotPosition), and a regular grid is
-- exactly what arithmetic hashes handle worst. Both obvious candidates were
-- tried against the real 61 positions and both failed: the classic
-- sin-and-fract hash collided outright (two slots landing on the same phase,
-- because 14 studs of row pitch lands within 0.04 of a whole number of sine
-- periods), and a boost-style xor/shift hash_combine collapsed its whole
-- output into the range 0.24-0.35. Seeding Roblox's own PRNG from the
-- position spreads properly: measured 0.0001 to 0.9999 across all 61 slimes,
-- with the ten in any one base covering the whole cycle.
--
-- Determinism is what makes this a valid phase source: the same position
-- always yields the same number, so the phase is identical on every rescan --
-- though note the baseline is captured once anyway (see entryFor), so this is
-- belt-and-braces rather than load-bearing. It need not agree between
-- clients; a purely cosmetic idle animation being a few tenths of a second
-- out of step between two players' screens is unobservable.
--
-- The seed packs the position into one integer, injectively: quarter-stud
-- quantisation (slots are at least 11 studs apart, so this loses nothing) and
-- a 65536 stride per axis, which covers +-8192 studs and stays well under
-- 2^53 so the arithmetic is exact.
-- Returns the breathing phase AND the blink interval, as the first and second
-- draws off ONE generator seeded from the position.
--
-- THE PHASE IS UNCHANGED BY THE BLINK BEING ADDED HERE. It is still the first
-- NextNumber() off a generator seeded exactly as before, and a generator's
-- first draw does not depend on how many draws are taken after it -- so every
-- slime breathes on precisely the phase it did before this pass.
--
-- The interval is the second draw, which is what makes it survive rescans the
-- same way the phase does: both are pure functions of the position, so a
-- re-derivation would produce identical values, and neither adds any state
-- that could go stale. (In practice neither is ever re-derived -- the whole
-- entry is captured once and cached, see entryFor.)
local PHASE_QUANTISATION_PER_STUD = 4
local PHASE_AXIS_OFFSET = 32768
local PHASE_AXIS_STRIDE = 65536

local function rhythmFor(position: Vector3): (number, number)
	local qx = math.round(position.X * PHASE_QUANTISATION_PER_STUD) + PHASE_AXIS_OFFSET
	local qy = math.round(position.Y * PHASE_QUANTISATION_PER_STUD) + PHASE_AXIS_OFFSET
	local qz = math.round(position.Z * PHASE_QUANTISATION_PER_STUD) + PHASE_AXIS_OFFSET
	local seed = qx + qy * PHASE_AXIS_STRIDE + qz * PHASE_AXIS_STRIDE * PHASE_AXIS_STRIDE
	local rng = Random.new(seed)
	local phase = rng:NextNumber()
	local blinkInterval = rng:NextNumber(
		SlimeIdleConfig.BLINK_INTERVAL_MIN_SECONDS,
		SlimeIdleConfig.BLINK_INTERVAL_MAX_SECONDS
	)
	return phase, blinkInterval
end

-- THE BASELINE REGISTRY, keyed by the Model instance itself and holding the
-- ONLY copy of any slime's undeformed measurements.
--
-- STRONG KEYS, AND THIS IS THE BUG FIX (see the written report). This table
-- was weak-keyed, on the reasoning that a Model parented into Workspace is
-- reachable from the DataModel and so could never be collected out from under
-- a rescan. THAT REASONING IS WRONG, and it was measured wrong, not merely
-- doubted: 800 Folders were parented into a live container, given weak-keyed
-- entries, and left with no other Lua reference; after GC pressure across 30
-- frames, ALL 800 entries were gone while ALL 800 instances were still
-- parented. A Lua Instance handle is collectable independently of whether the
-- underlying instance is still in the tree -- DataModel presence keeps the
-- INSTANCE alive, not the wrapper the weak key is holding.
--
-- The consequence was severe rather than cosmetic. Losing a baseline does not
-- stop a slime animating; it makes the next rescan re-measure it, and by then
-- it is mid-oscillation, so whatever squash or stretch it happened to be
-- wearing became its new rest pose. That compounds on every collection, in a
-- direction set by each slime's own phase at that instant -- which is exactly
-- the reported symptom: neighbouring slimes drifting permanently in OPPOSITE
-- directions, one into a tall egg and one nearly flat.
--
-- Two independent things now prevent it, either of which suffices:
--   1. This table is strong-keyed, so nothing here is collectable at all.
--   2. Every SlimeEntry holds its own Model (see the type above), so even
--      under weak keys the key would be strongly reachable from the entry.
-- Dead models are pruned explicitly in rescanSlimes instead, which is what
-- the weak keys were buying and is a fraction of the cost of getting it
-- wrong.
local baselines: { [Model]: SlimeEntry } = {}

local activeEntries: { SlimeEntry } = {}
local lastScanClock = 0

-- Instrumentation for the baseline re-capture bug, kept but OFF: confirmed
-- fixed in a live session (10 captures, all at once, identical baseHeight,
-- then silence). Flip to true to print one line per baseline capture if that
-- class of problem is ever suspected again.
local DEBUG_LOG_CAPTURES = false
local captureCount = 0

-- THE SINGLE PLACE IN THIS FILE THAT EVER READS A LIVE Size OR CFrame, and it
-- cannot read a deformed one. The cache lookup is the first statement, before
-- any measurement happens, so the measuring code below is reachable only for
-- a Model this file has never animated -- a Model only ever enters
-- activeEntries by way of this function, and the frame loop only ever touches
-- activeEntries. A model is therefore always measured strictly before its
-- first deformation, and never again, no matter how many rescans run or from
-- where this is called.
--
-- That ordering is the whole safety property. Re-measuring an
-- already-squashed slime bakes that frame's deformation in as its new rest
-- pose, and every later rescan compounds it -- an unbounded drift into a
-- permanently flattened or inflated slime. Keeping the guard INSIDE this
-- function rather than at its call site is what makes that impossible rather
-- than merely avoided: a second call site added later cannot reintroduce it.
--
-- The guard was always correct; what defeated it was the registry itself
-- losing entries to the garbage collector (see baselines above), so that a
-- Model this file HAD animated looked, on the next rescan, like one it had
-- never seen. The lookup cannot answer correctly if the thing it looks in has
-- been emptied underneath it.
local function entryFor(model: Model): SlimeEntry?
	local cached = baselines[model]
	if cached then
		return cached
	end

	local body = model:FindFirstChild(BODY_PART_NAME)
	if not (body and body:IsA("MeshPart")) then
		return nil
	end
	local bodyPart = body :: MeshPart
	local bodyCFrame = bodyPart.CFrame
	local bodyBaseSize = bodyPart.Size

	local faceParts: { FacePart } = {}
	local faceOffsetSum = Vector3.zero
	for _, name in FACE_PART_NAMES do
		local facePart = model:FindFirstChild(name)
		if facePart and facePart:IsA("MeshPart") then
			-- Offset AND relative rotation in one measurement. Both parts of
			-- the template carry identity rotation and the model is only ever
			-- moved rigidly, so this rotation is identity in practice -- kept
			-- anyway so a future asset with a tilted face part still works
			-- without a second pass through this file.
			local relative = bodyCFrame:ToObjectSpace((facePart :: MeshPart).CFrame)
			faceOffsetSum += relative.Position
			table.insert(faceParts, {
				part = facePart :: MeshPart,
				baseSize = (facePart :: MeshPart).Size,
				baseOffset = relative.Position,
				baseRotation = relative.Rotation,
				sinkOffset = Vector3.zero,
			})
		end
	end

	-- REFUSE AN INCOMPLETE CAPTURE. A Model whose parts have not all arrived
	-- yet would otherwise be measured with a short faceParts list, and that
	-- list would be cached forever -- leaving one eye permanently unanimated,
	-- detached from a body deforming underneath it. Bailing out here just
	-- defers the capture to the next rescan, when the model is whole. Same
	-- family as the guard above: never cache a measurement of a slime that is
	-- not in its true rest state.
	if #faceParts ~= #FACE_PART_NAMES then
		return nil
	end

	-- THE FACE AXIS, MEASURED FROM THIS MODEL'S OWN GEOMETRY -- not assumed,
	-- and not hardcoded. Every face part sits on the face side of the body, so
	-- the MEAN of their offsets from the body centre points along the face,
	-- and its dominant cardinal component is the axis. This is the same
	-- derivation SlimeBuilder documents for the facing correction, reproduced
	-- here from live measurements rather than imported as a constant. Checked
	-- against the asset: the mean offset comes out (-8.147, -0.029, -10.254),
	-- so Z dominates X by a ratio of 1.259 -- matching the consistent ~1.26
	-- lean SlimeBuilder records -- and the axis is -Z. A re-export that turned
	-- the mesh around would be followed automatically.
	--
	-- The blink sinks the eyes BACKWARD along that axis, hence the negation:
	-- the face normal points out of the head, and an eye has to travel into
	-- it to be swallowed by the body geometry.
	local faceAxis = dominantCardinal(faceOffsetSum)
	local sinkDirection = -faceAxis

	-- Each eye's full-depth sink, derived from ITS OWN depth along that axis
	-- rather than any stud figure, so it scales with the slime and with any
	-- future re-export. faceParts is index-aligned with FACE_PART_NAMES here,
	-- guaranteed by the completeness check just above.
	for index, face in faceParts do
		if BLINKING_PART_NAMES[FACE_PART_NAMES[index]] then
			local depthAlongAxis = math.abs(face.baseSize:Dot(faceAxis))
			face.sinkOffset = sinkDirection * (depthAlongAxis * SlimeIdleConfig.BLINK_SINK_DEPTH_FACTOR)
		end
	end

	local position = bodyPart.Position
	local phase, blinkInterval = rhythmFor(position)
	local entry: SlimeEntry = {
		model = model,
		body = bodyPart,
		bodyBaseSize = bodyBaseSize,
		bodyBaseRotation = bodyCFrame.Rotation,
		bodyBaseX = position.X,
		bodyBaseZ = position.Z,
		-- The planted base -- the pad top a slime was bottom-aligned onto at
		-- spawn. The body is the lowest part of the model by a wide margin
		-- (its half-height dwarfs the lowest face part's reach), and the
		-- facing correction is a pure yaw, which leaves the body's local Y
		-- along world Y -- so the body's own centre minus half its height IS
		-- the model's resting ground contact, without re-running an AABB.
		restY = position.Y - bodyBaseSize.Y / 2,
		phase = phase,
		blinkInterval = blinkInterval,
		faceParts = faceParts,
	}
	baselines[model] = entry

	if DEBUG_LOG_CAPTURES then
		captureCount += 1
		print(string.format(
			"[SlimeIdle] capture #%d  %s  baseHeight=%.4f  restY=%.4f",
			captureCount,
			model:GetFullName(),
			bodyBaseSize.Y,
			entry.restY
		))
	end

	return entry
end

-- Collects every slime Model directly under `container` into `out`. Anything
-- that is not a Model, or is a Model without a `slime` MeshPart, is skipped:
-- that is what leaves the EntranceSign (board/post) and the landmark's
-- GroundPatch (a Part, not a Model) alone.
local function collectSlimes(container: Instance, out: { SlimeEntry })
	for _, child in container:GetChildren() do
		if not child:IsA("Model") then
			continue
		end
		local entry = entryFor(child :: Model)
		if entry then
			table.insert(out, entry)
		end
	end
end

-- Walks Workspace:GetChildren() ONCE, on a throttle, and replaces the whole
-- active list in one shot -- the same shape as LaunchClient's own
-- rescanRemoteLanes, and for the same reason: the number of slimes is bounded,
-- but the number of Workspace children that must be walked past to find them
-- (road bands, plot dressing, stalls, per-player base folders, ...) is not, so
-- this walk is not free and does not belong on every frame.
--
-- Note that a rescan cannot disturb an already-animated slime: every Model it
-- finds goes through entryFor, which returns the existing baseline untouched
-- for anything already known.
--
-- The prune replaces what the registry's weak keys used to be for, and does
-- it on a criterion the garbage collector never had: a Destroyed Instance has
-- a nil Parent permanently and can never be re-parented, so "Parent == nil"
-- means gone for good, whereas "unreferenced by Lua" -- which is all a weak
-- key can see -- was true of perfectly live, on-screen slimes. Bounded work:
-- at most one entry per slime that has ever existed this session.
local function rescanSlimes()
	local scanned: { SlimeEntry } = {}
	for _, instance in Workspace:GetChildren() do
		if instance.Name == LANDMARK_NAME or instance.Name:match(BASE_FOLDER_NAME_PATTERN) then
			collectSlimes(instance, scanned)
		end
	end

	for model in baselines do
		if not model.Parent then
			baselines[model] = nil
		end
	end

	activeEntries = scanned
end

-- One frame of idle motion for every discovered slime, from the cache alone.
--
-- VOLUME CONSERVATION: sy is the vertical scale; sxz = 1/sqrt(sy) is what
-- keeps X * Y * Z constant (sxz * sy * sxz = sy / sy = 1), so the slime
-- genuinely deforms instead of appearing to grow and shrink. NOT the linear
-- 2 - sy, which only approximates this near sy = 1 and visibly breaks down as
-- amplitude rises.
--
-- THE BASE STAYS PLANTED: writing Size holds a part's CENTRE, so a body that
-- shrinks vertically would lift its own bottom off the pad -- and rising as
-- it squashes is backwards, reading as a hover rather than as weight.
-- Re-deriving the centre as restY + (baseHeight * sy) / 2 every frame pins
-- the bottom to the pad instead, so the slime only ever compresses downward.
-- The face parts are positioned THROUGH this same live body CFrame, so they
-- inherit both the facing rotation and this grounding correction for free.
--
-- A stale entry -- a slime unplaced, or a whole base folder destroyed when
-- its player left -- is skipped silently via a plain .Parent check for the
-- frames between that happening and the next rescan, exactly as
-- renderOtherLanes does, never an error.
local function renderIdleSlimes()
	local now = os.clock()
	if now - lastScanClock >= SlimeIdleConfig.IDLE_RESCAN_INTERVAL_SECONDS then
		lastScanClock = now
		rescanSlimes()
	end

	local cycles = now / SlimeIdleConfig.IDLE_PERIOD_SECONDS
	local amplitude = SlimeIdleConfig.IDLE_AMPLITUDE

	for _, entry in activeEntries do
		local body = entry.body
		if not body.Parent then
			continue
		end

		local sy = 1 + amplitude * math.sin(TAU * (cycles + entry.phase))
		local sxz = 1 / math.sqrt(sy)
		local baseSize = entry.bodyBaseSize

		body.Size = Vector3.new(baseSize.X * sxz, baseSize.Y * sy, baseSize.Z * sxz)
		local bodyCFrame = CFrame.new(entry.bodyBaseX, entry.restY + baseSize.Y * sy / 2, entry.bodyBaseZ)
			* entry.bodyBaseRotation
		body.CFrame = bodyCFrame

		-- BLINK -- ZERO extra writes and ZERO extra instances. Every eye part
		-- was already having Size and CFrame written this frame by the
		-- breathing; all this does is change the OFFSET fed into the CFrame
		-- being built anyway. The whole cost is the arithmetic below, once per
		-- slime, and the sine only evaluates during the blink itself.
		--
		-- NOT A FIXED RHYTHM. A per-slime interval alone would make each slime
		-- a metronome. The interval sets the cycle LENGTH; within each cycle
		-- the trigger point is re-jittered from the cycle's own index by a
		-- golden-ratio step (BLINK_JITTER_STRIDE), which is a low-discrepancy
		-- sequence -- so consecutive blinks land at well-spread, non-repeating
		-- offsets. Seeding that jitter with the slime's own blinkInterval
		-- decorrelates slimes from each other on top of their already
		-- different cycle lengths. All arithmetic on cached values: no
		-- allocation, no Random object per frame, no new state.
		local sinkAmount = 0
		local blinkWindow = SlimeIdleConfig.BLINK_DURATION_SECONDS / entry.blinkInterval
		local blinkClock = now / entry.blinkInterval
		local blinkCycle = math.floor(blinkClock)
		-- Scaled into [0, 1 - blinkWindow] so a blink can never be clipped by
		-- the end of its own cycle.
		local trigger = ((blinkCycle * BLINK_JITTER_STRIDE + entry.blinkInterval) % 1) * (1 - blinkWindow)
		local intoBlink = (blinkClock - blinkCycle) - trigger
		if intoBlink >= 0 and intoBlink < blinkWindow then
			-- sin runs 0 -> 1 -> 0 across the window, so the eyes sink and
			-- re-emerge smoothly and are exactly back at rest at both ends --
			-- no discontinuity into or out of the blink.
			sinkAmount = math.sin(math.pi * intoBlink / blinkWindow)
		end

		local scale = Vector3.new(sxz, sy, sxz)
		for _, face in entry.faceParts do
			local part = face.part
			if not part.Parent then
				continue
			end
			-- SIZE IS UNTOUCHED BY THE BLINK. Every face part, eyes included,
			-- breathes on exactly the same terms -- squashing the eyes was the
			-- previous mechanism and it flattened the whites along with
			-- everything else, which read as the eye deforming rather than
			-- closing.
			local faceSize = face.baseSize
			part.Size = Vector3.new(faceSize.X * sxz, faceSize.Y * sy, faceSize.Z * sxz)
			-- The blink lives ENTIRELY here, in the offset: the eyes slide
			-- backward along the body's own measured face normal until the
			-- body geometry swallows them. sinkOffset is Vector3.zero for
			-- blush, so this line needs no branch and no name comparison --
			-- non-blinking parts add nothing.
			local offset = face.baseOffset * scale + face.sinkOffset * sinkAmount
			part.CFrame = bodyCFrame * CFrame.new(offset) * face.baseRotation
		end
	end
end

RunService.RenderStepped:Connect(renderIdleSlimes)
