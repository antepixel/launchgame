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
-- The slots sit on a strictly REGULAR grid (30 studs across, 14 along, 80
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
-- That measurement was taken on the previous 22-stud column pitch, and has
-- NOT been re-run since the columns moved to 30 (see BaseConfig's
-- SLOT_COLUMN_HALF_WIDTH). Not re-running it is the point of the choice
-- rather than an omission: what failed before was two hashes whose output
-- depended on the grid's own arithmetic regularities, which is exactly why
-- the pitch mattered to them. A PRNG seeded from an injective packing of the
-- position does not care what the pitch is -- any change of position gives a
-- different seed and an independent draw. Re-measure if the pitch is ever
-- retuned to something that could collide under the quarter-stud
-- quantisation below (it would have to bring two slots within 0.25 studs).
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
--
-- The phase is the FIRST draw off that generator, and a pure function of the
-- position -- so a re-derivation would produce an identical value and no state
-- here can go stale. (In practice it is never re-derived: the whole entry is
-- captured once and cached, see entryFor.)
local PHASE_QUANTISATION_PER_STUD = 4
local PHASE_AXIS_OFFSET = 32768
local PHASE_AXIS_STRIDE = 65536

local function phaseFor(position: Vector3): number
	local qx = math.round(position.X * PHASE_QUANTISATION_PER_STUD) + PHASE_AXIS_OFFSET
	local qy = math.round(position.Y * PHASE_QUANTISATION_PER_STUD) + PHASE_AXIS_OFFSET
	local qz = math.round(position.Z * PHASE_QUANTISATION_PER_STUD) + PHASE_AXIS_OFFSET
	local seed = qx + qy * PHASE_AXIS_STRIDE + qz * PHASE_AXIS_STRIDE * PHASE_AXIS_STRIDE
	local rng = Random.new(seed)
	return rng:NextNumber()
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
	for _, name in FACE_PART_NAMES do
		local facePart = model:FindFirstChild(name)
		if facePart and facePart:IsA("MeshPart") then
			-- Offset AND relative rotation in one measurement. Both parts of
			-- the template carry identity rotation and the model is only ever
			-- moved rigidly, so this rotation is identity in practice -- kept
			-- anyway so a future asset with a tilted face part still works
			-- without a second pass through this file.
			local relative = bodyCFrame:ToObjectSpace((facePart :: MeshPart).CFrame)
			table.insert(faceParts, {
				part = facePart :: MeshPart,
				baseSize = (facePart :: MeshPart).Size,
				baseOffset = relative.Position,
				baseRotation = relative.Rotation,
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

	local position = bodyPart.Position
	local phase = phaseFor(position)
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

		-- Every face part breathes on exactly the same terms as the body, and
		-- is positioned through the body's live CFrame so it inherits the
		-- facing rotation and the grounding correction for free.
		local scale = Vector3.new(sxz, sy, sxz)
		for _, face in entry.faceParts do
			local part = face.part
			if not part.Parent then
				continue
			end
			local faceSize = face.baseSize
			part.Size = Vector3.new(faceSize.X * sxz, faceSize.Y * sy, faceSize.Z * sxz)
			part.CFrame = bodyCFrame * CFrame.new(face.baseOffset * scale) * face.baseRotation
		end
	end
end

RunService.RenderStepped:Connect(renderIdleSlimes)
