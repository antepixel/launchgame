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
-- Only for rollChestSlime's own pool lookup (SLIMES_BY_TIER) and its return
-- type -- the chest rolls from the same shared catalog every other reveal
-- already draws from, never a second copy.
local SlimeData = require(ReplicatedStorage.Config.SlimeData)
local TreasureConfig = require(ReplicatedStorage.Config.TreasureConfig)
local SwingTierVisuals = require(ReplicatedStorage.Config.SwingTierVisuals)
local SwingGeometry = require(ReplicatedStorage.Config.SwingGeometry)
local LaneConfig = require(ReplicatedStorage.Config.LaneConfig)
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

-- BUG FIX (see the written report -- Bug 1, character spawns at the wrong
-- lane): with CharacterAutoLoads left at its default (true), Roblox spawns a
-- character for a newly-joined player automatically, on its own timeline,
-- with no guarantee that happens after onLaneAssignmentPlayerAdded below has
-- had a chance to set player.RespawnLocation to THIS player's own lane spawn
-- -- and RespawnLocation has no retroactive effect on a character that
-- already spawned. When the engine's own auto-spawn won that race, it fell
-- back to choosing among all six enabled Neutral SpawnLocations, landing a
-- player at a random lane instead of their own. Disabling CharacterAutoLoads
-- removes the race outright: no character can exist for a player until this
-- file explicitly calls player:LoadCharacter() itself, strictly after that
-- player's own lane (and RespawnLocation) is already known -- see
-- onLaneAssignmentPlayerAdded below. setupCharacter's own humanoid.Died
-- handler is now also the ONLY thing that ever respawns a player after
-- death, for the same reason (Roblox's automatic post-death respawn is also
-- gated by this flag) -- see its own comment.
Players.CharacterAutoLoads = false

-- BUG FIX (see the written report): a client's WaitForChild("Remotes") could
-- resolve to a Folder that ReplicatedStorage already has a reference to
-- before every remote inside it exists -- Roblox replicates "this Instance
-- now has this Parent" as its own event, independently per instance, so a
-- client watching ReplicatedStorage can observe the FOLDER the instant it's
-- parented, which is not the same instant as "every remote inside it has
-- also finished replicating." The folder used to be parented to
-- ReplicatedStorage FIRST, then populated -- meaning there was a real
-- (if usually brief) window where a client could legitimately see a Remotes
-- folder missing some or all of its remotes, exactly matching the observed
-- "Infinite yield possible on ReplicatedStorage.Remotes:WaitForChild(
-- 'Release')" even though nothing in this script actually throws between
-- creating the folder and creating Release (traced every statement in that
-- window -- Instance.new/.Name=/.Parent= calls only, no yield, no branch,
-- nothing capable of erroring under normal conditions).
--
-- Fixed at the ROOT instead of just bounding the client's wait (see
-- LaunchClient.client.luau, which now also does that, belt-and-braces):
-- the whole folder is now built and fully populated with every remote
-- WHILE UNPARENTED (Parent stays nil, invisible to any client, exactly like
-- a part sitting in nothing), and only parented to ReplicatedStorage as the
-- LAST step, once -- see the bottom of this block. A client's
-- WaitForChild("Remotes") can now only ever resolve to a folder that
-- already has every remote inside it, by construction; there is no
-- intermediate state to observe.
--
-- Also added the SAME stale-folder cleanup SwingStructure already had below
-- (a leftover Remotes folder from a previous run of this exact script
-- without a full server restart -- e.g. a live code-sync re-run -- would
-- otherwise sit there forever, and a client could bind to THAT stale
-- instance instead of the fresh one this run creates).
local existingRemotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if existingRemotesFolder then
	existingRemotesFolder:Destroy()
end

local remotesFolder = Instance.new("Folder")
remotesFolder.Name = "Remotes"
-- NOT parented yet -- see the comment above; parented once, at the bottom
-- of this block, only after every remote below already exists as its child.

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
-- Server -> client: fired ONCE, immediately before SlimeRevealed, and ONLY on
-- a treasure-chest open. Carries the world CFrame the reveal slime should rise
-- out of -- the chest's own top face. Without it the client would place the
-- slime at the last mystery box's position, which is what it used to do (see
-- REPORT.md). The CFrame is sent rather than having the client look up
-- Workspace.GiantSlimeLandmark.TreasureChest, so the client never needs to
-- know the landmark's structure -- same "send what the receiver needs, not
-- where to find it" shape every other remote here uses.
local chestRevealRemote = makeRemote("ChestRevealStarted")
local slimeRevealedRemote = makeRemote("SlimeRevealed")
-- Server -> client: fires ONCE per player, the moment they claim the (single,
-- shared) rider slot -- tells that client "you're the one who should render
-- yourself on the swing." See setupCharacter and the bug-2 fix in the written
-- report for why the client needs to know this now.
local ridingAssignedRemote = makeRemote("RidingAssigned")
-- Client -> server: fired ONCE by a rider's LaunchClient the moment it has
-- finished initialising (past every WaitForChild gate, listening for
-- RidingAssigned, about to start driving the seat/character every
-- RenderStepped) -- see setupCharacter's watchdog below, and the written
-- report on why the server otherwise has no way to tell "a legitimately
-- slow-to-release rider" apart from "a rider whose client never came up at
-- all," both of which look identical from server state alone (state ==
-- "riding", root anchored, no Release received).
local riderReadyRemote = makeRemote("RiderReady")
-- Client -> server: content-free, exactly like Release/BoxPress -- fired by a
-- GROUNDED player's own click-anywhere/tap listener (see LaunchClient.
-- client.luau) once the reward sequence has left them standing wherever they
-- landed. The server derives EVERYTHING from the calling player's own state
-- (states[player] == "grounded") and lane (PlayerProfile.getBaseIndex) --
-- see onReturnToSwing below -- there is no argument here for a modified
-- client to lie about (which lane, which position).
local returnToSwingRemote = makeRemote("ReturnToSwing")
-- Client -> server: content-free, exactly like Release/BoxPress -- fired by
-- the DISMOUNT button, visible only while RIDING (see LaunchClient.client.
-- luau), for a player who mounted but wants off before ever releasing. The
-- server derives EVERYTHING from the calling player's own state
-- (states[player] == "riding") and lane, same as ReturnToSwing above -- see
-- onDismount below.
local dismountRemote = makeRemote("Dismount")
-- Server -> client: fires ONCE, right after onDismount below actually moves
-- the player, so THIS client can clear its own `mounted` flag and stop
-- driving the character onto the seat every RenderStepped -- see the
-- written report (dismount investigation, round 2): without this, the
-- client's own render loop kept PivotTo'ing the character back onto the
-- still-swinging seat every frame, since nothing client-side ever knew the
-- server had dismounted it (only FlightStarted/CharacterAdded ever cleared
-- `mounted` before now) -- the server's own teleport won the race for one
-- Heartbeat and then instantly lost it to the very next RenderStepped.
local dismountedRemote = makeRemote("Dismounted")

-- Reveal the whole subtree ATOMICALLY, now that every remote above already
-- exists as this folder's child -- see the comment at the top of this
-- block. Nothing before this line ever set remotesFolder.Parent.
remotesFolder.Parent = ReplicatedStorage

-- ===== Six per-player swings, one per lane (see the written report --
-- six-lane pass 1). Workspace.SwingPivot/SwingStructure (the ONE hand-placed
-- pivot + one shared structure folder every previous pass built) are GONE:
-- there is no more "the game's one swing" to own module-level. Each
-- connected player gets their OWN pivot + structure folder instead, named
-- SwingPivot_<UserId>/SwingStructure_<UserId> (the same Base_<UserId>
-- naming convention PlayerProfile.luau already uses), built the instant
-- they're assigned a lane and destroyed the instant they leave -- an
-- unoccupied lane has no tier to display, so it renders nothing at all,
-- same as an unjoined player has no base folder either.
--
-- PASS 1 (six-lane geometry) deliberately did NOT touch state/activePlayer/
-- activeCharacter/riderReady/activeFlight/activeBox -- there was still only
-- ONE shared rider slot back then, even though six independent swings
-- already existed to look at. PASS 2 (this pass) is what converts those six
-- into per-player tables (states/activeCharacters/riderReadyFlags/
-- activeFlights/activeBoxes below) so every connected player can actually
-- ride/launch/open a box independently -- see the written report. =====
local baseplate = Workspace:WaitForChild("Baseplate") :: BasePart
-- Ground level -- same reasoning BaseGeometry/SwingGeometry/SwingBuilder
-- already use elsewhere in this project; this file needs its own copy only
-- because the six pivots below are built HERE now, at runtime, rather than
-- hand-placed once in default.project.json.
local groundY = baseplate.Position.Y + baseplate.Size.Y / 2

local function laneInstanceNames(userId: number): (string, string)
	return string.format("SwingPivot_%d", userId), string.format("SwingStructure_%d", userId)
end

-- Every currently-connected player's own pivot/folder -- populated by
-- buildPlayerSwing below the instant that player's lane index is known,
-- cleared by destroyPlayerSwing the instant they leave. Deliberately keyed
-- by Player, not by lane index: activeCharacters/states/activeFlights/
-- activeBoxes below are all Player-keyed too, so every lookup this file
-- needs to do ("which pivot does this player's own rider state belong to")
-- is a single table read, no second index translation.
local playerSwingPivots: { [Player]: BasePart } = {}
local playerSwingFolders: { [Player]: Folder } = {}
-- One live listener per connected player, watching THIS player's own
-- Base_<UserId> folder's "SwingTier" attribute -- see buildPlayerSwing's own
-- comment on why this exists (the profile-load race) and destroyPlayerSwing
-- for where it's torn down. Disconnected explicitly, not left to garbage
-- collection, since the closure it wraps captures this player's own pivot/
-- folder -- letting a stale connection outlive the player would keep firing
-- PivotTo/SwingBuilder.build calls against instances destroyPlayerSwing has
-- already destroyed.
local playerSwingTierConnections: { [Player]: RBXScriptConnection } = {}

-- ===== Swing tier visual: the ENTIRE structure -- posts, beam, bracing,
-- caps, ground pads, seat, chain -- is a genuinely different, procedurally
-- built OBJECT per tier band, not the same four boxes resized/recoloured.
-- See SwingBuilder.luau for the construction code and SwingTierVisuals.luau
-- for every per-tier number/shape/material/colour; this file only ever
-- CALLS SwingBuilder.build(tier, pivot, folder), never authors geometry
-- itself. THIS FILE never touches LaunchConfig.SWING_ROPE_LENGTH/
-- SWING_ARC_HALF_ANGLE_DEGREES/SWING_PERIOD_SECONDS, so swingTheta below
-- stays exactly the same phase math regardless of tier. SwingBuilder.build
-- DOES move the given pivot's Y (see SwingGeometry.luau) so the seat hangs
-- proportionally higher on taller frames -- swingSeatPosition below reads
-- the pivot's Position fresh every call, so it automatically picks up
-- whatever height that lane's CURRENT tier last set, with no further change
-- to this file needed. That move is purely a translation of WHERE the arc
-- sits, not its shape: swingTheta's amplitude and swingPhase's timing read
-- no position at all, so the seat's actual swept position (and therefore
-- the scoring math, which reads that exact position at release) is exactly
-- as sensitive to release timing at every tier, just centred at a different
-- height. Takes an explicit pivot/folder now (used to close over the one
-- module-level swingPivot/swingStructureFolder) -- see every call site
-- below for which player's own instances it's pointed at. =====
local function applySwingVisualForTier(tier: number, pivot: BasePart, folder: Instance)
	SwingBuilder.build(tier, pivot, folder)
end

-- THE PROFILE-LOAD RACE (see the written report): getSwingTier(player) below
-- reads PlayerProfile's own in-memory profile.swingTier, which starts at 1
-- and is only overwritten once that player's DataStore load actually
-- resolves (see PlayerProfile.onPlayerAdded). buildPlayerSwing runs off
-- Players.PlayerAdded too, via onLaneAssignmentPlayerAdded's own
-- waitForBaseIndex poll -- and baseIndex becomes available (profiles[player]
-- gets set) BEFORE that same player's load has even had a chance to yield
-- once on the DataStore call, since PlayerProfile's own onPlayerAdded
-- listener runs to that point synchronously. So THIS call, on every single
-- join, reads getSwingTier before the real tier can possibly be known yet --
-- a player who owns tier 6 gets a tier-1 frame built here, every time,
-- deterministically, not as a rare timing fluke.
--
-- THE FIX: rather than trying to delay this call until the load finishes
-- (there's no clean way to know that from here without PlayerProfile calling
-- back into this file, which would invert its one-way dependency on
-- PlayerProfile), this instead listens for the SAME "SwingTier" attribute
-- BaseClient.client.luau already trusts for the HUD label -- PlayerProfile
-- writes the player's REAL tier there the instant it becomes known, whether
-- that's from a load finishing, a tier purchase, or a dev-panel tier set/
-- wipe (see PlayerProfile.luau: onPlayerAdded's load callback, buyNextTier,
-- devSetSwingTier, devWipeProfile -- every one of them sets this same
-- attribute). Rebuilding on every change means this player's swing is
-- ALWAYS caught up to their real tier within one attribute-replication tick
-- of it becoming known, never waiting on their next release to notice.
local function baseFolderName(userId: number): string
	return string.format("Base_%d", userId)
end

-- Builds (or rebuilds, on a tier change) ONE player's own pivot + structure
-- at their own lane's X, the shared LaneConfig.SWING_PIVOT_Z every lane
-- uses, and their own currently-owned tier. Defensive stale-instance cleanup
-- first, same reasoning the old single-swing setup always used (a leftover
-- instance from a previous run of THIS exact script, e.g. a live code-sync
-- without a full server restart, would otherwise sit there forever).
local function buildPlayerSwing(player: Player, baseIndex: number)
	local pivotName, structureName = laneInstanceNames(player.UserId)

	local existingPivot = Workspace:FindFirstChild(pivotName)
	if existingPivot then
		existingPivot:Destroy()
	end
	local existingFolder = Workspace:FindFirstChild(structureName)
	if existingFolder then
		existingFolder:Destroy()
	end

	local pivot = Instance.new("Part")
	pivot.Name = pivotName
	pivot.Anchored = true
	pivot.CanCollide = false
	pivot.Transparency = 1
	pivot.Size = Vector3.new(2, 0.2, 2)
	-- X is this player's own lane center, never touched again after this --
	-- SwingBuilder.build only ever moves a pivot's Y (see its own header).
	-- Y here is a placeholder (SwingBuilder.build corrects it to the real
	-- tier-scaled height on the very next line) -- same "doesn't matter,
	-- gets overwritten immediately" reasoning SwingGallery.server.luau's own
	-- per-tier pivots use.
	pivot.Position = Vector3.new(LaneConfig.laneCenterX(baseIndex), groundY, LaneConfig.SWING_PIVOT_Z)
	-- Set BEFORE Parent (same "populate then reveal" reasoning the Remotes
	-- folder above uses): LaunchClient reads this attribute straight off
	-- its own pivot to compute its own swingPhase offset (six-lane pass 2),
	-- and must never be able to observe the pivot without it already set --
	-- see swingPhase below and the written report on how server/client phase
	-- offset parity is guaranteed.
	pivot:SetAttribute("LaneIndex", baseIndex)
	pivot.Parent = Workspace

	local structureFolder = Instance.new("Folder")
	structureFolder.Name = structureName
	-- NOT parented until fully built -- same reasoning the old single shared
	-- folder used (invisible to any client until SwingBuilder.build has
	-- finished populating it), just now per-player instead of once.
	applySwingVisualForTier(PlayerProfile.getSwingTier(player), pivot, structureFolder)
	structureFolder.Parent = Workspace

	playerSwingPivots[player] = pivot
	playerSwingFolders[player] = structureFolder

	-- Stale listener cleanup -- same reasoning the pivot/folder cleanup above
	-- uses: buildPlayerSwing only ever runs once per join in practice, but a
	-- leftover connection from a previous run of this exact script (a live
	-- code-sync without a full server restart) must not be allowed to pile
	-- up alongside a fresh one and double-rebuild on every future change.
	local existingConnection = playerSwingTierConnections[player]
	if existingConnection then
		existingConnection:Disconnect()
	end

	-- PlayerProfile.onPlayerAdded always builds this player's own base
	-- folder BEFORE that player's baseIndex is ever readable (see
	-- allocateBaseIndex/buildBaseFolder/profiles[player] there) -- and this
	-- function only ever runs once baseIndex IS readable (see
	-- waitForBaseIndex) -- so the folder is guaranteed to already exist here,
	-- no yield needed.
	local baseFolder = Workspace:FindFirstChild(baseFolderName(player.UserId))
	if baseFolder then
		playerSwingTierConnections[player] = baseFolder:GetAttributeChangedSignal("SwingTier"):Connect(function()
			-- Re-reads playerSwingPivots/playerSwingFolders live (not the
			-- pivot/structureFolder locals captured above) so a LATER tier
			-- change still rebuilds the CURRENT structure even if this exact
			-- closure has fired more than once across this player's session.
			local currentPivot = playerSwingPivots[player]
			local currentFolder = playerSwingFolders[player]
			if currentPivot and currentFolder then
				applySwingVisualForTier(PlayerProfile.getSwingTier(player), currentPivot, currentFolder)
			end
		end)
	end
end

local function destroyPlayerSwing(player: Player)
	local pivot = playerSwingPivots[player]
	if pivot then
		-- Replicated occupant state (see the written report -- frozen remote
		-- players): every other client's own render loop only ever acts on
		-- "riding"/"flying" (see LaunchClient.client.luau's renderOtherLanes),
		-- so this is mostly belt-and-braces -- the pivot is about to be
		-- destroyed outright, which every client observes on its own -- but
		-- it costs nothing and matches the same explicit reset every other
		-- teardown path below now performs.
		pivot:SetAttribute("RiderState", "empty")
		pivot:Destroy()
	end
	local folder = playerSwingFolders[player]
	if folder then
		folder:Destroy()
	end
	local tierConnection = playerSwingTierConnections[player]
	if tierConnection then
		tierConnection:Disconnect()
	end
	playerSwingPivots[player] = nil
	playerSwingFolders[player] = nil
	playerSwingTierConnections[player] = nil
end

-- ===== Six per-lane spawns, replacing the single hand-placed
-- PlaceholderSpawn (see the written report: default.project.json's own copy
-- is removed -- Rojo cannot remove instances from an already-published
-- place, so the old PlaceholderSpawn must be deleted by hand in Studio and
-- republished; this defensive cleanup loop is a safety net for that, not a
-- substitute for actually doing it). Built here, at runtime, from the same
-- LaneConfig.laneCenterX every pivot above uses -- not hand-placed, for the
-- same "derive, don't hardcode six literals" reasoning. Built ONCE, at
-- server start, for all six lanes regardless of who's currently connected
-- (unlike the pivots, an idle spawn nobody is using yet costs nothing and
-- doesn't need a build/destroy lifecycle) -- onLaneAssignmentPlayerAdded
-- below assigns each joining player their OWN lane's spawn via
-- player.RespawnLocation once their lane index is known, so a later respawn
-- returns them next to their own swing instead of Roblox picking any of the
-- six at random. =====
for _, existing in Workspace:GetChildren() do
	if existing.Name == "PlaceholderSpawn" or existing:IsA("SpawnLocation") then
		existing:Destroy()
	end
end

local laneSpawns: { SpawnLocation } = {}
for laneIndex = 0, LaneConfig.LANE_COUNT - 1 do
	local spawnPart = Instance.new("SpawnLocation")
	spawnPart.Name = string.format("LaneSpawn%d", laneIndex)
	spawnPart.Anchored = true
	spawnPart.CanCollide = true
	spawnPart.Neutral = true
	spawnPart.Duration = 0
	spawnPart.Size = Vector3.new(8, 1, 8)
	-- Matches the old single PlaceholderSpawn's own Y (groundY + 1) and Z
	-- (LaneConfig.SPAWN_Z, = the old part's own placed Z) exactly -- only X
	-- now varies, per lane.
	spawnPart.Position = Vector3.new(LaneConfig.laneCenterX(laneIndex), groundY + 1, LaneConfig.SPAWN_Z)
	spawnPart.Parent = Workspace
	laneSpawns[laneIndex + 1] = spawnPart
end

-- ===== Lane assignment lifecycle: build this player's own swing the
-- instant their lane index is known, destroy it the instant they leave.
-- Deliberately a SEPARATE Players.PlayerAdded/PlayerRemoving pair from
-- setupCharacter's own below -- that one is about the single shared rider
-- slot (untouched this pass); this one is purely about per-lane geometry
-- existing/not existing, which has nothing to do with who currently holds
-- the rider slot. =====
--
-- ORDERING (see the written report): PlayerProfile.luau's own
-- Players.PlayerAdded listener is what actually allocates the lane index
-- (PlayerProfile.getBaseIndex) -- and it is a COMPLETELY INDEPENDENT
-- listener on the same event, with no guaranteed order against this file's
-- own. The allocation itself is synchronous/in-memory (instant) once
-- PlayerProfile's listener runs, so the only real ambiguity is WHICH
-- script's top-level :Connect() (or startup Players:GetPlayers() loop)
-- happens to run first -- resolved within, at most, a frame or two in
-- practice, never seconds. Bounded poll/retry here, not an assumption of
-- ordering: matches this file's own existing RIDER_READY_TIMEOUT_SECONDS
-- shape (generous bound, loud warning, fail open/skip rather than hang) --
-- see waitForBaseIndex below.
local LANE_INDEX_WAIT_TIMEOUT_SECONDS = 10
local LANE_INDEX_POLL_INTERVAL_SECONDS = 0.1

local function waitForBaseIndex(player: Player): number?
	local elapsed = 0
	while elapsed < LANE_INDEX_WAIT_TIMEOUT_SECONDS do
		local baseIndex = PlayerProfile.getBaseIndex(player)
		if baseIndex then
			return baseIndex
		end
		if not player.Parent then
			-- Left before ever getting a lane -- nothing to build.
			return nil
		end
		task.wait(LANE_INDEX_POLL_INTERVAL_SECONDS)
		elapsed += LANE_INDEX_POLL_INTERVAL_SECONDS
	end
	return nil
end

local function onLaneAssignmentPlayerAdded(player: Player)
	task.spawn(function()
		local baseIndex = waitForBaseIndex(player)
		if not player.Parent then
			return
		end
		if not baseIndex then
			warn(string.format(
				"[LaunchServer] %s never received a lane index within %d seconds -- PlayerProfile likely failed to allocate one (see its own onPlayerAdded). No swing will be built for them this session.",
				player.Name, LANE_INDEX_WAIT_TIMEOUT_SECONDS
			))
			return
		end
		buildPlayerSwing(player, baseIndex)
		-- This player's OWN lane spawn -- kept as a FALLBACK for Roblox's own
		-- spawn-selection inside LoadCharacter() below (and for any future
		-- engine-driven respawn), not relied on by itself any more (see the
		-- written report -- Bug 1): setupCharacter's own explicit PivotTo,
		-- driven from this same baseIndex, is what actually guarantees this
		-- player ends up standing at their own lane, whether or not this
		-- assignment took effect.
		local spawnPart = laneSpawns[baseIndex + 1]
		if spawnPart then
			player.RespawnLocation = spawnPart
		end

		-- CharacterAutoLoads is now false (see above) -- nothing spawns this
		-- player's FIRST character except this explicit call, made only once
		-- their own lane (and RespawnLocation) is already fully set up, so
		-- there is no longer any window where a character could exist before
		-- its lane is known. Re-checked here, not just relied on the earlier
		-- guard above: buildPlayerSwing/the RespawnLocation assignment are
		-- both synchronous (no yield), so player.Parent cannot actually have
		-- changed since that check, but this keeps the guard sitting directly
		-- next to the call it protects rather than several lines and two
		-- other operations away.
		if player.Parent then
			player:LoadCharacter()
		end
	end)
end

Players.PlayerAdded:Connect(onLaneAssignmentPlayerAdded)
for _, player in Players:GetPlayers() do
	onLaneAssignmentPlayerAdded(player)
end
Players.PlayerRemoving:Connect(destroyPlayerSwing)

-- ===== Swing math =====
-- Per-lane phase offset (six-lane pass 2): each lane's swing is offset by
-- laneIndex * (SWING_PERIOD_SECONDS / LANE_COUNT) seconds of server time --
-- lane 0 unshifted, lane 1 a sixth of a cycle ahead, and so on -- so the six
-- swings no longer move in lockstep. SWING_PERIOD_SECONDS, the sweet-spot
-- window, and SWING_ARC_HALF_ANGLE_DEGREES (read downstream by swingTheta)
-- are untouched by this -- only WHERE in the cycle a given lane starts
-- changes, never the shape or width of the cycle itself. LaunchClient's own
-- copy of this function is byte-for-byte identical, fed the SAME laneIndex
-- (see the written report for how that's guaranteed).
local function swingPhase(laneIndex: number): number
	local t = Workspace:GetServerTimeNow()
	local offset = laneIndex * (LaunchConfig.SWING_PERIOD_SECONDS / LaneConfig.LANE_COUNT)
	return ((t + offset) % LaunchConfig.SWING_PERIOD_SECONDS) / LaunchConfig.SWING_PERIOD_SECONDS
end

local function swingTheta(phase: number): number
	local arc = math.rad(LaunchConfig.SWING_ARC_HALF_ANGLE_DEGREES)
	return arc * math.sin(2 * math.pi * phase)
end

-- Takes an explicit pivot now (used to close over the one module-level
-- swingPivot, which no longer exists -- see the six-per-lane setup above).
-- Its one server call site (onRelease) passes the RELEASING player's own
-- pivot (playerSwingPivots[player]) -- swingTheta's amplitude and
-- swingPhase's timing still read no position at all, so which pivot gets
-- passed in only ever affects WHERE the arc sits, never its shape or timing.
local function swingSeatPosition(theta: number, pivot: BasePart): Vector3
	local pivotPosition = pivot.Position
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
-- SNAP THRESHOLD IS PER-TIER now (see LaunchConfig.SWING_TIER_SNAP_THRESHOLD).
-- Every tier whose entry equals the global SWEET_SPOT_SNAP_THRESHOLD behaves
-- exactly as it did before that table existed -- tiers 1-10 all do, so this
-- change is invisible to them. Tier 11 raises it, which shrinks the dead gap
-- between the threshold and 2.0x and is what hands band 73 back as a hittable
-- outcome; see that constant's own comment. A missing/short table entry falls
-- back to the global value rather than erroring.
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
-- RETURNS (luck, zone). The zone is an explicit enum -- "short" | "road" |
-- "past" -- and every caller branches on IT, never on a luck value that
-- happens to be the maximum.
--
-- PAST THE ROAD USED TO CLAMP, AND THAT IS NOW A BUG RATHER THAN A
-- SAFETY NET. This function's own comment used to say overshooting the road
-- was "still impossible today... but must survive the road shrinking or
-- distances growing later", and clamped to the last band accordingly. Tier 11
-- now deliberately overshoots (see LaunchConfig.SWING_TIER_DISTANCE_SCALE), so
-- a clamp would silently report the platform landing as luck 100,000 -- the
-- best possible band -- fire the normal mystery box, and make the chest
-- landing indistinguishable from a band-73 landing.
--
-- "past" therefore carries luck 0, not the last band's value. Nothing
-- downstream should ever read a luck number off a chest landing, and a 0
-- makes a missed branch fail loudly (no box at all) instead of quietly (a
-- maximum box).
local function bandLuckForLandingZ(landingZ: number): (number, string)
	local distanceFromStart = RunwayGeometry.RUNWAY_START_Z - landingZ
	if distanceFromStart < 0 then
		return 0, "short"
	end
	local index = math.floor(distanceFromStart / LaunchConfig.RUNWAY_BAND_LENGTH_STUDS)
	if index > #LuckCurve.VALUES - 1 then
		return 0, "past"
	end
	return LuckCurve.VALUES[index + 1], "road"
end

-- ===== Flight pose: a cheap static "flailing" silhouette (arms out/up, legs
-- trailing back) applied directly to the rig's shoulder/hip Motor6Ds -- no
-- physics, no ragdoll, no Animation asset. This is a DIRECT CFrame edit, not an
-- animation track: set once at release, held for the whole flight (the body's
-- overall tilt is what moves, via the CLIENT's trajectoryCFrame pitch -- see
-- LaunchClient.client.luau), restored to true neutral the instant the
-- character lands. STAYS SERVER-SIDE (unlike the per-frame position/rotation,
-- which moved to the client this pass): it's set exactly ONCE per flight and
-- held, not written every frame, so it was never the source of the jitter and
-- has nothing to gain from moving. Handles both R15 (space-less joint names,
-- split UpperTorso/LowerTorso) and R6 (spaced names, single Torso) rigs; if a
-- rig has neither, the pose is silently skipped and only the overall body
-- tilt still applies -- never an error.
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

local function findFlightJoints(character: Model): (Motor6D?, Motor6D?, Motor6D?, Motor6D?)
	local upperTorso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	local lowerTorso = character:FindFirstChild("LowerTorso") or character:FindFirstChild("Torso")
	local leftShoulder = findMotor6D(upperTorso, "LeftShoulder", "Left Shoulder")
	local rightShoulder = findMotor6D(upperTorso, "RightShoulder", "Right Shoulder")
	local leftHip = findMotor6D(lowerTorso, "LeftHip", "Left Hip")
	local rightHip = findMotor6D(lowerTorso, "RightHip", "Right Hip")
	return leftShoulder, rightShoulder, leftHip, rightHip
end

-- BUG FIX (see the written report -- compounding flight pose): applyFlightPose
-- used to offset each joint from its CURRENT C0 at apply time. If
-- restoreFlightPose was ever skipped (death or disconnect mid-flight, see
-- clearActiveRider below), the next flight captured the still-bent C0 as
-- "neutral" and added another layer of offset on top -- repeatable without
-- bound, since nothing ever re-anchored to the rig's ACTUAL neutral pose.
-- Fixed by capturing each character's true neutral C0 exactly ONCE, in
-- setupCharacter, before any pose has ever been applied to it, and keeping
-- every later apply/restore anchored to that one stored snapshot instead of
-- whatever the joint currently reads. Weak-keyed so a respawned character's
-- entry (and its now-destroyed Motor6Ds) can be collected instead of leaking
-- for the life of the server.
local characterNeutralPose: { [Model]: PoseJoints } = setmetatable({}, { __mode = "k" }) :: any

local function captureNeutralPose(character: Model): PoseJoints
	local leftShoulder, rightShoulder, leftHip, rightHip = findFlightJoints(character)
	local neutral: PoseJoints = {}
	if leftShoulder then
		neutral[leftShoulder] = leftShoulder.C0
	end
	if rightShoulder then
		neutral[rightShoulder] = rightShoulder.C0
	end
	if leftHip then
		neutral[leftHip] = leftHip.C0
	end
	if rightHip then
		neutral[rightHip] = rightHip.C0
	end
	return neutral
end

-- Always offsets from the STORED neutral captured by captureNeutralPose, never
-- from the joint's current C0 -- see the bug-fix comment above. Returns that
-- same neutral map, which restoreFlightPose below writes straight back: apply
-- and restore always agree on exactly what "neutral" means for this
-- character, so a skipped restore can never compound -- the next apply simply
-- overwrites from neutral again.
local function applyFlightPose(character: Model): PoseJoints
	local neutral = characterNeutralPose[character]
	if not neutral then
		-- Defensive only: setupCharacter captures this for every character
		-- before it can ever become the active rider, so this should be
		-- unreachable. Falls back to capturing now rather than offsetting
		-- from a possibly-already-bent current C0.
		neutral = captureNeutralPose(character)
		characterNeutralPose[character] = neutral
	end

	local leftShoulder, rightShoulder, leftHip, rightHip = findFlightJoints(character)
	if leftShoulder and neutral[leftShoulder] then
		leftShoulder.C0 = neutral[leftShoulder] * CFrame.Angles(-ARM_LIFT, 0, -ARM_SPREAD)
	end
	if rightShoulder and neutral[rightShoulder] then
		rightShoulder.C0 = neutral[rightShoulder] * CFrame.Angles(-ARM_LIFT, 0, ARM_SPREAD)
	end
	if leftHip and neutral[leftHip] then
		leftHip.C0 = neutral[leftHip] * CFrame.Angles(LEG_TRAIL, 0, 0)
	end
	if rightHip and neutral[rightHip] then
		rightHip.C0 = neutral[rightHip] * CFrame.Angles(LEG_TRAIL, 0, 0)
	end
	return neutral
end

local function restoreFlightPose(joints: PoseJoints)
	for joint, neutralC0 in joints do
		joint.C0 = neutralC0
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

-- "grounded" (NEW -- automatic proximity mounting): the default state, both
-- at spawn and after every reset. A grounded character is walked around by
-- the normal Humanoid controller like any other Roblox character -- nothing
-- server- or client-side ever PivotTo's it. The ONLY way OUT of "grounded"
-- is the proximity-mount check below (walking within
-- LaunchConfig.SWING_MOUNT_RADIUS_STUDS, horizontally, of THIS player's OWN
-- swing pivot), which moves them straight to "riding" -- there is no button,
-- prompt, or keypress involved. See the written report for the full state
-- machine.
type LoopState = "grounded" | "riding" | "inflight" | "box" | "cooldown"

-- Every connected player owns their own lane for the whole session (six-lane
-- pass 2) -- no more shared rider slot, so each of these is now a table
-- keyed by Player instead of a single module-level value. A player's own
-- entry is theirs alone from the moment setupCharacter claims it to the
-- moment they leave (destroyPlayerSwing/PlayerRemoving below free it);
-- nothing here ever reads or writes another player's entry.
local states: { [Player]: LoopState } = {}
local activeCharacters: { [Player]: Model } = {}
-- True once THIS player's own LaunchClient has fired RiderReady -- see
-- setupCharacter's watchdog and riderReadyRemote below. Reset to false every
-- time THIS player's character (re)claims its seat (a respawn, same as a
-- fresh join); a stale true from a PREVIOUS character can never leak into a
-- new watchdog check for the same player because that check also compares
-- `activeCharacters[watchedPlayer] == watchedCharacter` (a fresh Model every
-- claim), and can never leak across PLAYERS because this table is keyed by
-- Player to begin with.
local riderReadyFlags: { [Player]: boolean } = {}

-- One flight's fixed, precomputed description -- set once at that player's
-- release, read every Heartbeat until its own duration elapses. Nothing
-- here ever changes mid-flight.
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
	-- "short" | "road" | "past" -- which side of the road this flight ends on
	-- (see bandLuckForLandingZ). Carried on the flight rather than recomputed
	-- at landing so the zone the box/chest branch reads is the exact zone the
	-- landing readout was already scored against.
	zone: string,
	trailRig: TrailRig?,
}
-- Every player currently mid-flight, independently -- see the Heartbeat
-- handler below, which now loops over every entry here instead of checking
-- one shared flight.
local activeFlights: { [Player]: Flight } = {}

-- One player's active mystery box -- set once per landing that earned luck >
-- 0, read and mutated (luck doubling) by every press until it opens.
-- `pending` is true from the moment a press is ACCEPTED until its delayed
-- result fires -- see onBoxPress. `luck` starts at the landing's earned
-- value and only ever doubles; nothing here caps it. No `player` field --
-- the table key already IS the owning player, so there is only ever one
-- place that fact is recorded.
type Box = {
	character: Model,
	luck: number,
	pending: boolean,
}
local activeBoxes: { [Player]: Box } = {}

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
	-- BUG FIX (see written report): this used to fall back to tier 1 whenever
	-- nobody was riding, regardless of who pressed the button or what tier
	-- their OWN profile says -- pressing it while standing built a tier-1
	-- swing even for a tier-9 player, leaving the visible structure (pivot
	-- height, rope length) mismatched against the tier LaunchServer.onRelease
	-- actually computes distance from the next time they ride. Falls back to
	-- the REQUESTING player's own tier instead now (DevPanelServer.server.
	-- luau passes the firing player through Fire()) -- only ever falls all
	-- the way back to 1 if this is invoked with no requesting player at all
	-- (defensive only; DevPanelServer always passes one).
	devRebuildSwingEvent.Event:Connect(function(requestingPlayer: Player?)
		-- Rebuilds the REQUESTING player's own lane -- see the six-per-lane
		-- setup above. "Whichever player is currently riding" doesn't mean
		-- anything any more (six-lane pass 2: every connected player can be
		-- riding/flying/boxing at once, independently, so there is no more
		-- single "the current rider" to prefer over the requester).
		-- No-ops if that player doesn't have a lane pivot yet (e.g. still
		-- mid-join); nothing sensible to rebuild in that case.
		if not requestingPlayer then
			return
		end
		local pivot = playerSwingPivots[requestingPlayer]
		local folder = playerSwingFolders[requestingPlayer]
		if not pivot or not folder then
			return
		end
		applySwingVisualForTier(PlayerProfile.getSwingTier(requestingPlayer), pivot, folder)
	end)
end

-- Frees ONE player's own rider state (on disconnect, death, or a missing
-- character) without otherwise touching that player's swing itself -- the
-- seat keeps swinging empty either way, and no OTHER player's state is ever
-- touched (six-lane pass 2: this used to reset the one shared rider slot;
-- now every table write below is scoped to `player` alone). Clearing
-- activeBoxes[player] here too (on TOP of resetting states[player] away
-- from "box") is what guarantees a player leaving or dying mid-sequence can
-- never leave a stuck box: any in-flight delayed roll for THIS player (see
-- onBoxPress) checks `activeBoxes[player] ~= box or states[player] ~=
-- "box"` the instant its delay elapses and simply bails if either has
-- changed out from under it -- another player's own box is a different
-- table entry entirely and is never affected.
local function clearActiveRider(player: Player)
	-- BUG FIX: an interrupted flight (e.g. the rider dies mid-air, see
	-- setupCharacter's humanoid.Died below -- PlayerRemoving doesn't need
	-- this, since a leaving player's whole character, trail included, is
	-- destroyed by Roblox automatically) used to leave its Trail/Attachments
	-- orphaned on the character forever, since this just discarded
	-- activeFlight without checking it for one first.
	local flight = activeFlights[player]
	if flight then
		destroyFlightTrail(flight.trailRig)
		-- BUG FIX (see the written report -- compounding flight pose): this
		-- also used to discard activeFlight.poseJoints unrestored, leaving a
		-- rider who died or disconnected mid-flight with bent hip/shoulder
		-- C0s forever. Harmless on its own now that applyFlightPose always
		-- offsets from the stored neutral pose (a skipped restore can no
		-- longer compound), but restoring here still matters for a rider who
		-- dies mid-flight and is revived/keeps the same character without a
		-- full respawn -- and it's free.
		restoreFlightPose(flight.poseJoints)
	end
	activeCharacters[player] = nil
	activeFlights[player] = nil
	activeBoxes[player] = nil
	riderReadyFlags[player] = nil
	-- Replicated occupant state (see the written report -- frozen remote
	-- players): a rider who dies or disconnects mid-ride/mid-flight must not
	-- leave their pivot stuck reporting "riding"/"flying" forever -- every
	-- OTHER client's own render loop (LaunchClient.client.luau's
	-- renderOtherLanes) would otherwise keep trying to fly/seat a character
	-- that's already respawned or gone. Reset here unconditionally, the same
	-- "grounded, no matter what they were doing before" reasoning states[
	-- player] below already uses.
	local ownPivot = playerSwingPivots[player]
	if ownPivot then
		ownPivot:SetAttribute("RiderState", "empty")
	end
	-- "grounded", not "riding": this player has no character right now (or is
	-- about to get a fresh one, see setupCharacter) -- there is nothing to
	-- anchor them to, and a fresh/respawned character always starts grounded
	-- regardless of what they were doing before (see the written report).
	states[player] = "grounded"
	-- BUG FIX (see the written report -- six-lane pass 1): this used to
	-- reset the ONE shared swing to a baseline tier-1 look here, since
	-- "nobody riding" meant the single swing had no owner's tier to show.
	-- That concept doesn't exist any more -- every lane always shows its
	-- OWN occupant's own tier, maintained independently by the per-lane
	-- lifecycle above, whether or not that occupant currently holds this
	-- shared rider slot. Resetting to tier 1 here would incorrectly stomp a
	-- departing/dying rider's own owned-tier look with a baseline that has
	-- nothing to do with them.

	-- BUG FIX (see the written report -- mid-flight death): everything above
	-- this point is server-side bookkeeping only -- it never told the OWNING
	-- client's own LaunchClient.client.luau that its flight was cancelled.
	-- That client has no Humanoid.Died listener of its own and no other way
	-- to learn a death happened, so its local flightActive/canRelease state
	-- (set once by FlightStarted/doRelease, see that file's own comments)
	-- was never cleared: the abandoned render loop kept PivotTo'ing whatever
	-- player.Character currently was -- the newly RESPAWNED character, once
	-- the Died handler's own player:LoadCharacter() call produced one --
	-- along the old trajectory, and canRelease stayed stuck false forever
	-- since the Heartbeat flight loop drops this player's flight the
	-- instant states[player] is no longer "inflight."
	-- This is a DEATH/DISCONNECT CANCELLATION signal, not a landing signal
	-- -- reusing resetReadyRemote (rather than adding a second, narrower
	-- remote) because its own OnClientEvent handler already does exactly
	-- "return to neutral: not releasing, not flying, HUD hidden," which is
	-- correct here regardless of what this player was doing when they died.
	-- Guarded on player.Parent, the same guard scheduleLucklessReturn's own
	-- delayed fire already uses -- necessary here because clearActiveRider
	-- also runs from PlayerRemoving, by which point firing to a gone player
	-- would error.
	if player.Parent then
		resetReadyRemote:FireClient(player)
	end
end


-- ===== Player-triggered return to swing (see the written report) =====
-- Computes THIS player's own return position -- their lane's swing X
-- (LaneConfig.laneCenterX), a STANDING height above groundY (see below), and
-- LaneConfig.SWING_PIVOT_Z + LaunchConfig.SWING_RETURN_CLEARANCE_STUDS
-- (verified clear of SWING_MOUNT_RADIUS_STUDS -- see that constant's own
-- comment) -- and moves + unfreezes `character` there in one call: PivotTo,
-- unanchor, AutoRotate back on. Shared by onReturnToSwing (fired from
-- "grounded", after a landing) and onDismount (fired from "riding", before
-- ever releasing) below -- the destination and the unfreeze are identical
-- either way; only the STATE GUARD differs per caller, so each keeps its own
-- checks rather than this function trying to guess which state it was
-- called from.
--
-- BUG FIX (see the written report -- falling through the map on return):
-- groundY is the ground's own TOP surface, but PivotTo places the CHARACTER
-- ROOT (HumanoidRootPart) at the Y it's given, not the character's feet --
-- a root placed AT groundY left roughly half the rig's body embedded in the
-- floor the instant it unanchored, which is what dropped the player through
-- before physics could settle. The correct offset from the ground up to the
-- root's own centre is HipHeight (the gap the rig's legs span between root
-- and feet) plus half the root part's own height (so the root's BOTTOM
-- face, not its centre, is what actually lands at groundY) -- both read
-- live off THIS character's own rig, never a hardcoded guess, so this is
-- correct for whatever body type/HipHeight a given player's avatar has, not
-- just the default rig.
--
-- THIS FILE NOW ALSO PivotTo's A CHARACTER'S FIRST SPAWN/RESPAWN DIRECTLY
-- (see moveToLaneSpawn below and setupCharacter's own comment -- Bug 1,
-- written report): RespawnLocation is kept as a fallback for Roblox's own
-- spawn-selection inside LoadCharacter(), but is no longer trusted alone,
-- so the same standing-height math this function already needed is needed
-- there too, not just here.
local function moveToLaneSpawn(character: Model, humanoid: Humanoid, rootPart: BasePart, laneIndex: number)
	-- Same HipHeight + rootPart.Size.Y / 2 standing-height derivation as
	-- moveToLaneReturn below -- see its own comment for why a bare groundY
	-- would leave the rig embedded in the floor. X is this lane's own
	-- swing-center X (matches LaneSpawn<N>'s own placed X -- see laneSpawns
	-- above); Z is LaneConfig.SPAWN_Z, the SAME Z every LaneSpawn part is
	-- placed at -- this is a SPAWN position, not the "return to swing after
	-- a flight" position moveToLaneReturn computes, so it deliberately does
	-- NOT reuse LaunchConfig.SWING_PIVOT_Z/SWING_RETURN_CLEARANCE_STUDS.
	local standingHeight = humanoid.HipHeight + rootPart.Size.Y / 2
	local spawnPosition = Vector3.new(
		LaneConfig.laneCenterX(laneIndex),
		groundY + standingHeight,
		LaneConfig.SPAWN_Z
	)
	character:PivotTo(CFrame.lookAt(spawnPosition, spawnPosition + Vector3.new(0, 0, -1)))
end

-- THE SIX LANE SPAWNS DO NOT HAVE THIS PROBLEM (checked, not assumed): they
-- are real SpawnLocation parts (see laneSpawns above) that Roblox's own
-- built-in respawn logic places a character ON TOP OF automatically,
-- accounting for hip height itself -- nothing in this file ever PivotTo's a
-- character onto one of those; player.RespawnLocation is all that's set,
-- and the engine does the rest. This standing-height math is only needed
-- here (and would equally be needed anywhere else this file manually
-- PivotTo's a character to a bare ground-level Y -- landing and mounting
-- both intentionally still use their own existing, unrelated height
-- constants, not this one, and are untouched).
local function moveToLaneReturn(character: Model, humanoid: Humanoid, rootPart: BasePart, laneIndex: number, pivot: BasePart?)
	local standingHeight = humanoid.HipHeight + rootPart.Size.Y / 2
	local returnPosition = Vector3.new(
		LaneConfig.laneCenterX(laneIndex),
		groundY + standingHeight,
		LaneConfig.SWING_PIVOT_Z + LaunchConfig.SWING_RETURN_CLEARANCE_STUDS
	)
	character:PivotTo(CFrame.lookAt(returnPosition, returnPosition + Vector3.new(0, 0, -1)))
	rootPart.Anchored = false
	humanoid.AutoRotate = true
	-- Replicated occupant state (see the written report -- frozen remote
	-- players): the ONLY two callers of this function (onReturnToSwing,
	-- onDismount below) are the only two places besides a landing that ever
	-- take a rider off "riding"/"flying" without going through clearActiveRider
	-- -- both now pass this player's own pivot so every other client's render
	-- loop stops touching this character the instant the state flips.
	if pivot then
		pivot:SetAttribute("RiderState", "empty")
	end
end

-- ===== THE TWO LANDINGS END DIFFERENTLY (see the written report) =====
--
-- There used to be ONE scheduleReset shared by both landing outcomes, which
-- flipped states to "grounded" on a timer and left the player anchored,
-- waiting for a click, on both. That is right for exactly one of them:
--
--   LUCKLESS (0 luck, no box, no reveal) -- there is nothing on screen to
--       click, so requiring a click would strand the player on an empty road
--       staring at nothing. This path RETURNS THEM AUTOMATICALLY after
--       RESET_DELAY, and is the whole reason scheduleLucklessReturn below
--       exists as its own function rather than a flag on a shared one.
--
--   REWARD (box opened, slime revealed) -- the reveal panel IS the thing they
--       click, and it stays up until they do (see LaunchClient's
--       SlimeRevealed handler). Nothing on a timer returns them; the server
--       only arms the click by flipping states to "grounded" at the moment
--       the reveal is sent, and onReturnToSwing does the rest whenever it
--       arrives. See onBoxPress.
--
-- Six-lane pass 2: this closure writes states[landedPlayer] and reads that
-- player's own captured character, never a shared module-level variable --
-- two different players' timers can fire at any two overlapping instants and
-- never stomp each other.
local function scheduleLucklessReturn(landedPlayer: Player, landedCharacter: Model)
	task.delay(LaunchConfig.RESET_DELAY, function()
		-- STILL THE SAME LANDING? A death, disconnect or dismount in the
		-- meantime has already reset this player through clearActiveRider (see
		-- its own comment), which sets states to "grounded" -- so anything
		-- other than "cooldown" here means this timer is stale and must not
		-- move a character that has since been respawned or freed.
		if states[landedPlayer] ~= "cooldown" then
			return
		end
		states[landedPlayer] = "grounded"

		-- Same move + unanchor + AutoRotate restore the click-driven path
		-- uses -- one function, so the two paths cannot drift apart on where
		-- a player ends up or on what gets un-frozen. Skipped gracefully if
		-- the rig is gone from under us; the state flip above has already
		-- happened either way, so a missing character can never leave this
		-- player stuck in "cooldown" forever.
		local humanoid = landedCharacter:FindFirstChildOfClass("Humanoid") :: Humanoid?
		local rootPart = humanoid and humanoid.RootPart
		local laneIndex = PlayerProfile.getBaseIndex(landedPlayer)
		if humanoid and rootPart and laneIndex then
			moveToLaneReturn(landedCharacter, humanoid, rootPart, laneIndex, playerSwingPivots[landedPlayer])
		end

		if landedPlayer.Parent then
			resetReadyRemote:FireClient(landedPlayer)
		end
	end)
end

-- ===== THE CHEST LANDING (see TreasureConfig.luau and REPORT.md) =====
-- A perfect tier-11 launch clears the road and lands on the giant slime's
-- platform. No box fires (the landing's zone is "past", which carries luck 0
-- by construction), so none of the box/reveal machinery above runs. Instead:
-- the player is UNFROZEN, walks to the chest, and opens it.
--
-- WHY THE PENDING FLAG IS ON THE PROFILE, NOT HERE. states[player] is
-- session state -- a death, a disconnect or a respawn wipes it. Losing a
-- 20%-Divine reward to a network blip would be the worst failure this feature
-- could have, so the entitlement is persisted (PlayerProfile.markChestPending)
-- and survives all three. It is consumed only by actually opening the chest.
-- The player cannot walk back out here from their base -- the platform is
-- ~3,100 studs down a road with no path -- so a pending chest is not free
-- money, it is just not DESTROYED by bad luck with the network.
local function beginChestLanding(landedPlayer: Player, landedCharacter: Model)
	PlayerProfile.markChestPending(landedPlayer)

	-- Unfreeze. This is the only landing in the game that does this -- see the
	-- Heartbeat handler's own "FROZEN AT LANDING" comment for why every other
	-- one stays anchored.
	local humanoid = landedCharacter:FindFirstChildOfClass("Humanoid") :: Humanoid?
	local rootPart = humanoid and humanoid.RootPart
	if humanoid and rootPart then
		rootPart.Anchored = false
		humanoid.AutoRotate = true
	end
	local landedPivot = playerSwingPivots[landedPlayer]
	if landedPivot then
		landedPivot:SetAttribute("RiderState", "empty")
	end

	-- THE SAFETY NET, and it covers every abandonment case at once: idle,
	-- distracted, wandered off, walked to the far edge. Same
	-- moveToLaneReturn every other return path uses, so the destination
	-- cannot drift. Deliberately does NOT consume the pending chest.
	task.delay(TreasureConfig.CHEST_ABANDON_SECONDS, function()
		-- Stale-timer guard, same shape as scheduleLucklessReturn's: anything
		-- other than "chest" means this landing already ended (opened, died,
		-- disconnected) and this timer must not move a character that has
		-- since been respawned or freed.
		if states[landedPlayer] ~= "chest" then
			return
		end
		states[landedPlayer] = "grounded"
		local h = landedCharacter:FindFirstChildOfClass("Humanoid") :: Humanoid?
		local rp = h and h.RootPart
		local laneIndex = PlayerProfile.getBaseIndex(landedPlayer)
		if h and rp and laneIndex then
			moveToLaneReturn(landedCharacter, h, rp, laneIndex, playerSwingPivots[landedPlayer])
		end
		if landedPlayer.Parent then
			resetReadyRemote:FireClient(landedPlayer)
		end
	end)
end

-- The chest's own roll -- ITS OWN TABLE, never SlimeRoll.distributionForLuck
-- (a 4-tier sliding window whose whole point is that everything outside the
-- window is exactly zero; a chest must be able to award anything). Flat
-- CHEST_DIVINE_CHANCE for Divine off the top, the remainder spread across the
-- other tiers geometrically at CHEST_TIER_WEIGHT_RATIO per tier upward.
--
-- SERVER-SIDE AND SERVER-ONLY. The client's entire contribution to this is a
-- ProximityPrompt.Triggered signal, which carries nothing but the player --
-- no odds, no outcome, no luck. Same shape as onBoxPress.
local function rollChestSlime(): SlimeData.Slime
	local tierCount = #SlimeConfig.SLIME_TIER_NAMES
	local roll = math.random()
	local tier
	if roll < TreasureConfig.CHEST_DIVINE_CHANCE then
		tier = tierCount
	else
		local weights, total = {}, 0
		for i = 1, tierCount - 1 do
			weights[i] = TreasureConfig.CHEST_TIER_WEIGHT_RATIO ^ (i - 1)
			total += weights[i]
		end
		-- Re-drawn rather than rescaling the first roll: one more math.random
		-- is free, and reusing a draw across two different distributions is
		-- the kind of subtle correlation that is hard to notice and hard to
		-- reason about later.
		local inner = math.random() * total
		local cumulative = 0
		tier = tierCount - 1
		for i = 1, tierCount - 1 do
			cumulative += weights[i]
			if inner <= cumulative then
				tier = i
				break
			end
		end
	end
	local pool = SlimeData.SLIMES_BY_TIER[tier]
	return pool[math.random(1, #pool)]
end

-- Fired by a GROUNDED player's own click-anywhere/tap listener once the
-- reward sequence has left them standing, still FROZEN (anchored, AutoRotate
-- off -- see the Heartbeat landing handler's own "FROZEN AT LANDING"
-- comment), wherever they landed. This (and onDismount below) are now the
-- ONLY places, besides mountPlayer's own anchor, that ever touch Anchored/
-- AutoRotate.
--
-- THE ONLY GATE THAT MATTERS: states[player] == "grounded", checked here,
-- server-side, from this player's own table entry -- never trusted from the
-- client. A click/tap while riding, mid-flight, or mid-box is simply
-- ignored; the remote carries no data for a modified client to lie about in
-- the first place (which lane, which position), so there is nothing beyond
-- this one state check for a bad actor to even attempt.
--
-- STALE-CHARACTER GUARD: activeCharacters[player] is read fresh, right here,
-- at the moment of the click -- not a value captured earlier and carried
-- through a delay (there is no delay on this path; the remote fires and this
-- runs in the same tick). It can still be nil, though: clearActiveRider sets
-- states[player] = "grounded" AND activeCharacters[player] = nil together
-- (a death mid-cooldown, see its own comment), so "grounded" alone does not
-- guarantee a live character -- this still has to check for one before
-- touching anything, same defensive shape the old captured-character check
-- had, just against the live table instead of a stale local.
local function onReturnToSwing(player: Player)
	if states[player] ~= "grounded" then
		return
	end
	local character = activeCharacters[player]
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	local rootPart = humanoid and humanoid.RootPart
	local laneIndex = PlayerProfile.getBaseIndex(player)
	if not humanoid or not rootPart or not laneIndex then
		return
	end
	moveToLaneReturn(character, humanoid, rootPart, laneIndex, playerSwingPivots[player])

	-- FIRES RESETREADY ITSELF NOW, where a timer used to fire it BEFORE the
	-- click (see scheduleLucklessReturn's header). On the reward path there is
	-- no such timer any more -- the reveal panel waits indefinitely -- so this
	-- is the only thing that tells the client the sequence is over: re-arm
	-- release, clear the flight readouts, drop back to "grounded". Ordered
	-- after moveToLaneReturn so the client's own setGrounded(true) (which
	-- tears down the reveal panel and every other reward-sequence element)
	-- runs against a character that has already been moved and unanchored,
	-- not one still frozen on the road.
	--
	-- The LUCKLESS path fires its own from its timer instead, because nothing
	-- there ever calls this function.
	if player.Parent then
		resetReadyRemote:FireClient(player)
	end
end

returnToSwingRemote.OnServerEvent:Connect(onReturnToSwing)

-- ===== Player-triggered dismount (the EXIT button, see the written report)
-- =====
-- Fired by the DISMOUNT button, visible only while RIDING (see
-- LaunchClient.client.luau), for a player who mounted but wants off before
-- ever releasing -- rather than being forced to sit through a whole flight
-- they didn't mean to start.
--
-- SAME GATE SHAPE AS onRelease: states[player] ~= "riding" -> bail, no
-- partial/queued dismount, just a flat no-op if it isn't currently valid.
-- This REJECTS a press outright during "inflight", "box", or "cooldown" --
-- exactly the same precedent onRelease's own guard sets for a Release press
-- during any of those -- a dismount can only ever back a player OFF the
-- swing they're currently sitting on, never out of a flight or a reward
-- sequence already in progress.
--
-- GUARD STYLE matches onRelease's own (not onReturnToSwing's) deliberately:
-- "riding" is a state onRelease already assumes implies a live character/
-- humanoid/rootPart (see its own guards), so a genuinely missing one here is
-- the same kind of "something's actually wrong" case onRelease treats as --
-- clearActiveRider(player) resets them to a clean "grounded" rather than
-- leaving them stuck in "riding" with nothing left to act on.
local function onDismount(player: Player)
	if states[player] ~= "riding" then
		return
	end
	local character = activeCharacters[player]
	if not character then
		clearActiveRider(player)
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not humanoid or humanoid.Health <= 0 then
		clearActiveRider(player)
		return
	end
	local rootPart = humanoid.RootPart
	if not rootPart then
		clearActiveRider(player)
		return
	end
	local laneIndex = PlayerProfile.getBaseIndex(player)
	if not laneIndex then
		return
	end
	moveToLaneReturn(character, humanoid, rootPart, laneIndex, playerSwingPivots[player])
	states[player] = "grounded"
	-- Tells THIS client to clear its own `mounted` flag -- see
	-- dismountedRemote's own comment above for why this is required, not
	-- optional: without it, the client's render loop has no way to learn
	-- the server just dismounted it, and keeps driving the character back
	-- onto the seat every frame regardless of what the server just did.
	dismountedRemote:FireClient(player)
end

dismountRemote.OnServerEvent:Connect(onDismount)

-- HUMANOID SETUP, done once per character (not per launch). Ragdoll/FallingDown
-- disabling, the Freefall state-fight, and the fall-damage guard from the
-- physics-flight pass are ALL GONE (see the written report) -- flight is now
-- fully scripted with the root part anchored, so there is no physics event left
-- for any of those to fight.
--
-- AUTOMATIC PROXIMITY MOUNTING (see the written report): a character no
-- longer starts anchored, and AutoRotate is no longer forced off here --
-- every character spawns "grounded" and is walked around by the ordinary
-- Humanoid controller, exactly like any other Roblox character. mountPlayer
-- below is the ONLY place that ever anchors the root / turns AutoRotate off
-- (kinematic PivotTo control while riding or flying fights AutoRotate --
-- same jitter reasoning the client's own comments give).
--
-- FROZEN-AT-LANDING (see the written report): the Heartbeat landing handler
-- used to turn both back the other way -- unanchored, AutoRotate on -- the
-- instant a flight ended, leaving the player free to walk around a landing
-- spot up to ~2,900 studs down an empty road. It no longer does either: the
-- root STAYS anchored (AutoRotate stays off) all the way through landing,
-- the mystery box, and the slime reveal -- there is nothing at the landing
-- spot to walk to, so there is nothing to free the player FOR yet. The one
-- and only OTHER place that ever unanchors / turns AutoRotate back on now is
-- onReturnToSwing, fired by the player's own click/tap once they're ready to
-- leave -- see its own comment.
--
-- Bounded grace period for a freshly-mounted rider's OWN LaunchClient to
-- fire RiderReady (see mountPlayer's watchdog below) -- generous enough to
-- comfortably cover normal loading variance (including LaunchClient's own
-- up-to-10-second bounded WaitForChild chain, see LaunchClient.client.
-- luau's REMOTES_WAIT_TIMEOUT_SECONDS) without leaving a genuinely broken
-- client's rider stuck for long. A module-level constant (not local to
-- mountPlayer) since mountPlayer's own warn() below reads it too.
local RIDER_READY_TIMEOUT_SECONDS = 15

local function setupCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid

	-- Captured once, right away, before this character's joints have ever
	-- been touched by applyFlightPose -- see the bug-fix comment on
	-- characterNeutralPose above. Runs exactly once per character: setupCharacter
	-- itself is only ever invoked from the two CharacterAdded connections/
	-- catch-up checks at the bottom of this file, one call per distinct
	-- character Model, so this can neither be skipped nor run twice for the
	-- same character.
	characterNeutralPose[character] = captureNeutralPose(character)

	-- Explicit lane placement (see the written report -- Bug 1): runs for
	-- EVERY character this script ever sees -- the first one LoadCharacter()
	-- produces in onLaneAssignmentPlayerAdded, and every respawn this same
	-- function's own humanoid.Died handler below triggers -- derived from
	-- THIS player's own baseIndex, the SAME index buildPlayerSwing already
	-- used to place their swing, never a second guess at it. RespawnLocation
	-- (see onLaneAssignmentPlayerAdded) is kept only as a fallback for
	-- whatever Roblox's own spawn-selection inside LoadCharacter() does; this
	-- is what actually guarantees the result, so it is not skipped even when
	-- RespawnLocation was almost certainly already correct. Skipped
	-- gracefully (not an error) if this player's baseIndex somehow isn't
	-- known yet -- shouldn't be reachable (a character can now only ever be
	-- spawned, by this file, after baseIndex is confirmed -- see
	-- onLaneAssignmentPlayerAdded), kept as the same defensive shape every
	-- other baseIndex read in this file already uses.
	do
		local rootPart = humanoid.RootPart
		local laneIndex = PlayerProfile.getBaseIndex(player)
		if rootPart and laneIndex then
			moveToLaneSpawn(character, humanoid, rootPart, laneIndex)
		end
	end

	humanoid.Died:Connect(function()
		-- Guards against a stale Died firing after this exact character has
		-- already been superseded by a respawn (see setupCharacter's own
		-- re-entry on the next CharacterAdded) -- shouldn't be reachable in
		-- practice (a character's Humanoid is destroyed alongside it), kept
		-- as the same "don't trust identity you didn't just check" caution
		-- the watchdog below uses.
		if activeCharacters[player] == character then
			clearActiveRider(player)
		end
		-- BUG FIX (see the written report -- Bug 1): CharacterAutoLoads is now
		-- false (see this file's own top), which also disables Roblox's own
		-- automatic post-death respawn -- without this call, a player who
		-- dies would simply never get a character back. Guarded on
		-- player.Parent, same "don't act on a player who's already gone"
		-- reasoning onLaneAssignmentPlayerAdded's own LoadCharacter guard
		-- uses -- Humanoid.Died can still fire during the brief window after
		-- a disconnect, before PlayerRemoving's own cleanup runs.
		if player.Parent then
			player:LoadCharacter()
		end
	end)

	-- Six-lane pass 2: every player owns their own lane unconditionally for
	-- the whole session -- there is no more shared slot to claim, so this is
	-- no longer gated behind "is anyone else already riding." Runs every
	-- time, for every player, on every CharacterAdded (including a respawn).
	--
	-- AUTOMATIC PROXIMITY MOUNTING: every character starts "grounded," full
	-- stop -- no anchor, no RidingAssigned, no watchdog started here. Nothing
	-- in this file touches this character again until either it walks within
	-- LaunchConfig.SWING_MOUNT_RADIUS_STUDS, horizontally, of its OWN swing
	-- pivot (see the proximity check in the Heartbeat loop below, which is
	-- what actually calls mountPlayer) or it dies/leaves.
	activeCharacters[player] = character
	states[player] = "grounded"
	riderReadyFlags[player] = false

	-- Refresh THIS player's own swing visuals to their currently-owned tier
	-- the moment their character exists -- see applySwingVisualForTier
	-- above. Now purely defensive/idempotent, same reasoning as onRelease's
	-- own refresh: buildPlayerSwing's OWN initial build is racy (it can run
	-- before this player's profile load resolves, see its own written-up
	-- comment), but its SwingTier-attribute listener already corrects that
	-- the instant the real tier becomes known, with no need to wait for a
	-- CharacterAdded either. Skipped gracefully (not an error) on the rare
	-- chance this player's own lane pivot somehow isn't built yet: the
	-- per-lane lifecycle will still finish building it correctly moments
	-- later regardless.
	local ownPivot = playerSwingPivots[player]
	local ownFolder = playerSwingFolders[player]
	if ownPivot and ownFolder then
		applySwingVisualForTier(PlayerProfile.getSwingTier(player), ownPivot, ownFolder)
	end
end

-- Seats a GROUNDED player onto THEIR OWN swing -- see the written report.
-- This is the entire mount interaction: no button, no ProximityPrompt, no
-- keypress. Called ONLY from the proximity check in the Heartbeat loop
-- below, and only ever with pivot/phase already resolved for THIS exact
-- player from THIS player's own playerSwingPivots entry -- see that call
-- site for why a player can never be mounted onto anyone else's swing (there
-- is no code path here, or anywhere upstream of here, that reads a
-- DIFFERENT player's pivot for this player's mount).
local function mountPlayer(player: Player, character: Model, humanoid: Humanoid, rootPart: BasePart, pivot: BasePart, phase: number)
	states[player] = "riding"
	riderReadyFlags[player] = false
	-- Replicated occupant state (see the written report -- frozen remote
	-- players): every OTHER connected client's own render loop (see
	-- LaunchClient.client.luau's renderOtherLanes) reads this attribute to
	-- know whether to seat this player's character on their own swing at
	-- all -- ridingAssignedRemote below still only ever reaches THIS player
	-- (unchanged), so this is the only signal any other client gets.
	pivot:SetAttribute("RiderState", "riding")

	-- Same reasoning the old always-anchored-at-spawn version used: the
	-- CLIENT drives this part's CFrame every RenderStepped once riding (see
	-- LaunchClient.client.luau), so nothing server-side may write to it
	-- again until the next release/landing -- anchoring is what keeps it
	-- from just falling in the meantime, and turning AutoRotate off is what
	-- keeps the humanoid's own controller from fighting that kinematic
	-- control (same jitter reasoning as always).
	humanoid.AutoRotate = false
	rootPart.Anchored = true

	-- Snap straight onto the seat's CURRENT position -- the exact same
	-- swingSeatPosition(swingTheta(phase), pivot) + seat-height-offset math
	-- onRelease uses for a flight's own startPosition, so mounting mid-swing
	-- lands the rider exactly where the seat visually is, not at some
	-- reference rest pose.
	local seatPosition = swingSeatPosition(swingTheta(phase), pivot) + Vector3.new(0, LaunchConfig.RIDER_SEAT_HEIGHT_OFFSET, 0)
	character:PivotTo(CFrame.lookAt(seatPosition, seatPosition + Vector3.new(0, 0, -1)))

	ridingAssignedRemote:FireClient(player)

	-- BUG FIX (see the written report): the anchor above assumes THIS
	-- player's LaunchClient is alive and already listening for
	-- RidingAssigned. If it never acknowledges -- a hung or failed
	-- client-side WaitForChild, a disconnect right as this fires, anything
	-- -- the root stays anchored FOREVER with nothing server-side ever
	-- moving or freeing it: a player stuck in place, unable to move, with no
	-- way out. This bounded watchdog is the recovery: if THIS exact
	-- rider/character (captured below, not re-read from the per-player
	-- tables at fire time) hasn't acknowledged readiness within
	-- RIDER_READY_TIMEOUT_SECONDS, fail OPEN -- unanchor so the player at
	-- least regains ordinary movement, rather than staying frozen
	-- indefinitely. Self-invalidating by construction: if this rider
	-- legitimately released, left, or got cleared before the timeout fires,
	-- activeCharacters[watchedPlayer] will have moved on (or
	-- riderReadyFlags[watchedPlayer] will already be true) and this no-ops
	-- -- and since every table here is keyed by Player, this watchdog can
	-- only ever act on watchedPlayer's OWN entry, never another
	-- concurrently-watched player's.
	local watchedPlayer, watchedCharacter = player, character
	task.delay(RIDER_READY_TIMEOUT_SECONDS, function()
		if activeCharacters[watchedPlayer] ~= watchedCharacter or riderReadyFlags[watchedPlayer] then
			return
		end
		local watchedHumanoid = watchedCharacter:FindFirstChildOfClass("Humanoid")
		local watchedRoot = watchedHumanoid and watchedHumanoid.RootPart
		if watchedRoot and watchedRoot.Anchored then
			warn(string.format(
				"[LaunchServer] %s's LaunchClient never acknowledged readiness within %d seconds -- unanchoring so they aren't stuck.",
				watchedPlayer.Name, RIDER_READY_TIMEOUT_SECONDS
			))
			watchedRoot.Anchored = false
		end
	end)
end

riderReadyRemote.OnServerEvent:Connect(function(player: Player)
	riderReadyFlags[player] = true
end)

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
	if states[player] ~= "riding" then
		return
	end
	local character = activeCharacters[player]
	if not character then
		clearActiveRider(player)
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not humanoid or humanoid.Health <= 0 then
		clearActiveRider(player)
		return
	end
	local rootPart = humanoid.RootPart
	if not rootPart then
		clearActiveRider(player)
		return
	end
	-- This player's own lane pivot/folder/lane index -- see the six-per-lane
	-- setup above. Bails WITHOUT clearing the rider (unlike the guards
	-- above): a missing pivot/lane index here means "this player's own lane
	-- geometry hasn't finished building yet" (buildPlayerSwing runs
	-- asynchronously off PlayerAdded, see onLaneAssignmentPlayerAdded), not
	-- that anything is actually wrong with this rider -- an exceedingly rare,
	-- self-correcting race (a character would need to load, claim this slot,
	-- AND the player press Release, all before a synchronous in-memory table
	-- lookup and one SwingBuilder.build call finish), not worth yanking them
	-- off the swing for. Their next Release attempt succeeds once it catches
	-- up.
	local pivot = playerSwingPivots[player]
	local structureFolder = playerSwingFolders[player]
	local laneIndex = PlayerProfile.getBaseIndex(player)
	if not pivot or not structureFolder or laneIndex == nil then
		return
	end

	-- THE ONLY THING RELEASE POWER IS EVER DERIVED FROM: the server's own
	-- swingPhase(), read at the instant the server itself receives this
	-- event, offset by THIS player's own laneIndex (six-lane pass 2 -- see
	-- swingPhase above). laneIndex here is PlayerProfile's own
	-- profile.baseIndex, the SAME integer buildPlayerSwing stamped onto this
	-- player's pivot as its LaneIndex attribute -- LaunchClient reads that
	-- exact attribute to compute the identical offset for its own
	-- bar-render/prediction, so the two can never disagree (see the written
	-- report). The client sent nothing but a bare signal -- no phase, no
	-- distance -- so there is no number here for a modified client to lie
	-- about.
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
	local phase = swingPhase(laneIndex)
	local riderTierForMultiplier = PlayerProfile.getSwingTier(player)
	local multiplier = launchMultiplier(phase, riderTierForMultiplier)
	-- Swing tier scaling: a plain multiplier on top of the usual timing-based
	-- distance, read once here from THIS PLAYER's OWN tier (see
	-- PlayerProfile.getSwingTier/buyNextTier -- the old server-wide,
	-- hand-edited LaunchConfig.ACTIVE_SWING_TIER is gone). Bands themselves
	-- never change length or count -- this is the ONLY place tier
	-- progression enters the flight, which is what keeps it from having to
	-- touch the trajectory formula, the camera, or the band curve at all.
	local riderTier = riderTierForMultiplier
	local tierScale = LaunchConfig.SWING_TIER_DISTANCE_SCALE[riderTier]
	-- Also refresh the whole swing's cosmetic look here -- now purely
	-- defensive/idempotent (see buildPlayerSwing's own SwingTier-attribute
	-- listener, which already rebuilds the instant a purchase, a dev-panel
	-- tier set, or a slow profile load actually changes this player's tier,
	-- with no need to wait for a launch at all). Kept anyway as a cheap
	-- belt-and-braces call: a no-op rebuild if the listener already caught
	-- up, correct either way if it somehow hasn't.
	applySwingVisualForTier(riderTier, pivot, structureFolder)
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
	-- stops, so this is a moving origin). LaunchConfig.RIDER_SEAT_HEIGHT_
	-- OFFSET, not a second hardcoded 2 -- see the written report: this used
	-- to disagree with LaunchClient's own riding-height offset (2 here,
	-- 1.0 there), producing a visible vertical pop at the instant of
	-- release as the character snapped between the two. Same constant now,
	-- read fresh here, so the two can never drift apart again.
	local startPosition = swingSeatPosition(swingTheta(phase), pivot) + Vector3.new(0, LaunchConfig.RIDER_SEAT_HEIGHT_OFFSET, 0)
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
	local luck, landingZone = bandLuckForLandingZ(landingPosition.Z)

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

	states[player] = "inflight"
	activeFlights[player] = {
		rootPart = rootPart,
		humanoid = humanoid,
		startPosition = startPosition,
		distance = distance,
		archHeight = archHeight,
		duration = duration,
		startTime = startTime,
		poseJoints = poseJoints,
		luck = luck,
		zone = landingZone,
		trailRig = trailRig,
	}

	-- Replicated occupant state (see the written report -- frozen remote
	-- players): the exact same numbers flightStartedRemote below carries to
	-- the flying player alone, ALSO written here as attributes on this
	-- player's own pivot so every OTHER connected client can recompute this
	-- same flight itself (trajectoryCFrame is pure and already byte-
	-- identical client and server -- see LaunchClient.client.luau) with no
	-- new remote and no per-frame server work. Written BEFORE RiderState
	-- flips to "flying" -- see renderOtherLanes' own comment for why a
	-- client must never be able to observe "flying" with a stale or missing
	-- param still attached.
	pivot:SetAttribute("FlightStartTime", startTime)
	pivot:SetAttribute("FlightStartPos", startPosition)
	pivot:SetAttribute("FlightDistance", distance)
	pivot:SetAttribute("FlightArcHeight", archHeight)
	pivot:SetAttribute("FlightDuration", duration)
	pivot:SetAttribute("RiderState", "flying")

	flightStartedRemote:FireClient(player, distance, archHeight, duration, startPosition, startTime, luck)
end

releaseRemote.OnServerEvent:Connect(onRelease)

Players.PlayerRemoving:Connect(function(player)
	clearActiveRider(player)
	-- Unlike a mid-session clear (death, a missing character), this player
	-- is never coming back for THIS Player instance -- drop states[player]
	-- entirely rather than leaving it at "riding" forever, so this table
	-- doesn't quietly accumulate one dead entry per departed player for the
	-- life of the server (same "freed, not left growing" reasoning
	-- PlayerProfile.luau's own freeBaseIndices uses).
	states[player] = nil
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
--
-- SIX-LANE PASS 2: this used to check ONE shared activeFlight/activeCharacter
-- pair and process at most one landing per frame -- with a shared rider slot
-- that was never a problem, since only one player could ever be mid-flight
-- at all. It is now the structural blocker to concurrent flights: it loops
-- over every entry in activeFlights every Heartbeat, so any number of
-- players landing on the same frame (or different frames) are each handled
-- in their own loop iteration, reading and writing only that iteration's own
-- `player` key in every per-player table -- one player's landing can never
-- see or touch another's.
-- ===== Automatic proximity mounting (see the written report) =====
-- DETECTION CHOICE: a plain distance check against the PIVOT's own fixed
-- X/Z, run right here in the already-existing Heartbeat loop, scoped to
-- players currently "grounded" -- not a Touched-based physics trigger, and
-- not a spatial query (Workspace:GetPartBoundsInRadius/Region3). Two
-- reasons:
--   1. There is no server-owned PART that ever sits at a fixed, testable
--      ground position other than the pivot itself. SeatCore is Anchored
--      (see SwingBuilder.luau) but its CFrame is set every RenderStepped by
--      the RIDING PLAYER'S OWN CLIENT, purely locally, for smoothness (see
--      LaunchClient.client.luau) -- the server never positions it and has
--      no authoritative moving Instance to query against. The pivot, unlike
--      the seat, genuinely never moves in X/Z once built (SwingBuilder.build
--      only ever touches its Y -- see SwingGeometry.pivotYForScale) --
--      reading its Position directly is cheap, authoritative, and needs no
--      swingTheta/phase math just to know where to measure from.
--   2. "Don't loop over every player" is the right instinct for a game with
--      an unbounded population, but LaneConfig.LANE_COUNT (6) is a HARD cap
--      on concurrent players here (Players.MaxPlayers, see LaneConfig.luau)
--      -- so "every player" is never more than 6 entries, and this loop only
--      even reaches the distance math for whichever subset of those 6 are
--      currently "grounded" (riding/flying/boxing players are skipped
--      immediately). That's a fixed, tiny amount of work every frame, not a
--      scaling concern -- there is no larger population this could ever
--      need to hold up against.
--
-- WHY THE PIVOT, NOT THE SEAT, AND WHY Y IS DROPPED (see the written
-- report): this used to measure 3D distance to the seat's own LIVE,
-- swinging position (swingSeatPosition(swingTheta(phase), pivot)) -- a small
-- target constantly sweeping SWING_ARC_HALF_ANGLE_DEGREES either side of
-- vertical, so in practice a player had to walk into the seat itself,
-- whatever instant the Heartbeat happened to sample it, to ever register.
-- Measuring HORIZONTAL-ONLY distance from the stationary pivot instead turns
-- mounting into a fixed circle on the ground around the frame's own
-- footprint (see LaunchConfig.SWING_MOUNT_RADIUS_STUDS's own comment for the
-- exact sizing against that footprint and the 40-stud lane pitch) -- standing
-- anywhere near your own swing now works, and dropping Y means a tier-11
-- frame (whose pivot sits far higher above the ground than tier 1's) is
-- exactly as easy to mount as tier 1, since height was never meant to be
-- part of "are you standing at your swing" in the first place.
--
-- OWNERSHIP: this loop reads playerSwingPivots[player] -- THIS iteration's
-- own player, always -- and PlayerProfile.getBaseIndex(player), same. There
-- is no step anywhere in this check that compares one player's position
-- against another player's pivot, so a player can structurally never be
-- mounted onto a swing that isn't their own, independent of proximity.
local function checkProximityMounts()
	for _, player in Players:GetPlayers() do
		if states[player] ~= "grounded" then
			continue
		end
		local character = activeCharacters[player]
		if not character then
			continue
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			continue
		end
		local rootPart = humanoid.RootPart
		if not rootPart then
			continue
		end
		local pivot = playerSwingPivots[player]
		local laneIndex = PlayerProfile.getBaseIndex(player)
		if not pivot or laneIndex == nil then
			continue
		end

		local pivotPosition = pivot.Position
		local horizontalOffset = Vector2.new(rootPart.Position.X - pivotPosition.X, rootPart.Position.Z - pivotPosition.Z)
		if horizontalOffset.Magnitude <= LaunchConfig.SWING_MOUNT_RADIUS_STUDS then
			local phase = swingPhase(laneIndex)
			mountPlayer(player, character, humanoid, rootPart, pivot, phase)
		end
	end
end

RunService.Heartbeat:Connect(function()
	checkProximityMounts()

	local now = Workspace:GetServerTimeNow()
	for player, flight in activeFlights do
		if states[player] ~= "inflight" then
			continue
		end
		-- flight.duration, NOT the config constant directly -- see onRelease,
		-- where duration was computed once per flight from that flight's own
		-- (possibly tier-scaled) distance and stored here, exactly like
		-- distance and archHeight already were.
		local u = (now - flight.startTime) / flight.duration
		if u < 1 then
			continue
		end

		-- Flight complete for THIS player: place exactly at the landing point
		-- (u = 1, deterministic, no drift), LEVEL (not the tipped-forward
		-- landing pitch -- that's for mid-flight only; standing normally
		-- starts from level), restore the limb pose. Removed from
		-- activeFlights immediately (before any of the below can yield) so a
		-- second Heartbeat can never reprocess the same landing.
		--
		-- FROZEN AT LANDING (see the written report): the root STAYS anchored
		-- and AutoRotate STAYS off here -- deliberately NOT restored to normal
		-- walking control the way this used to. The landing spot is up to
		-- ~2,900 studs down an empty road with nothing to walk to; freeing the
		-- player here just let them wander off with no reason to. They stay
		-- frozen exactly where they landed through the box and the slime
		-- reveal, until they choose to leave (a click/tap while grounded --
		-- see LaunchClient.client.luau's returnToSwingRemote and this file's
		-- own onReturnToSwing, the only other place that ever unanchors /
		-- restores AutoRotate).
		activeFlights[player] = nil

		-- BOTH MOVED ABOVE THE CHARACTER GUARD (see the written report --
		-- flight pose sticking). Neither needs `character`: poseJoints is a map
		-- of Motor6D -> neutral C0 captured at release, and trailRig holds its
		-- own instances. They used to sit below the `if not character then
		-- continue end` bail, which meant the one path that takes that bail
		-- left a flight's pose applied and its trail attached forever. That
		-- path is documented as unreachable and I could not find a way to
		-- reach it either -- but "unreachable" is not a reason to leave the
		-- cleanup behind a guard it never needed.
		restoreFlightPose(flight.poseJoints)
		destroyFlightTrail(flight.trailRig)

		local character = activeCharacters[player]
		if not character then
			-- Defensive only: activeFlights[player] is never set without
			-- activeCharacters[player] also set (see onRelease) -- this
			-- can't actually happen, but keeps the type checker honest
			-- instead of asserting it away.
			states[player] = "grounded"
			continue
		end

		-- BUG FIX (see the written report -- character sunk into the road on
		-- landing): trajectoryPosition's u = 1 Y is RunwayGeometry.RUNWAY_TOP_Y,
		-- the road's own TOP SURFACE -- and PivotTo places the character ROOT at
		-- the Y it is given, not the character's feet. Placing the root AT the
		-- surface therefore buried the whole rig from the pelvis down in the band
		-- it landed on, which is exactly the bug moveToLaneReturn/moveToLaneSpawn
		-- already solve for the return/spawn positions (see their own comments).
		-- Same derivation, read live off THIS character's own rig rather than a
		-- hardcoded guess, so it is correct for whatever body type/HipHeight a
		-- given player's avatar has: HipHeight is the gap the legs span between
		-- root and feet, plus half the root part's own height so the root's
		-- BOTTOM face is what lands on the surface.
		--
		-- STRICTLY VERTICAL. X and Z come out of trajectoryPosition untouched, so
		-- the landing Z -- and therefore bandLuckForLandingZ, which takes nothing
		-- but a Z and was already evaluated at release time from this same
		-- trajectoryPosition(u = 1) call (see onRelease) -- cannot be affected by
		-- this in any way. The band awarded and the band stood on are the same
		-- band before and after this fix.
		local landingHumanoid = character:FindFirstChildOfClass("Humanoid")
		local landingRootPart = landingHumanoid and landingHumanoid.RootPart
		local standingHeight = if landingHumanoid and landingRootPart
			then landingHumanoid.HipHeight + landingRootPart.Size.Y / 2
			else 0
		local landingPosition = trajectoryPosition(flight.startPosition, flight.distance, flight.archHeight, 1)
			+ Vector3.new(0, standingHeight, 0)
		character:PivotTo(CFrame.lookAt(landingPosition, landingPosition + Vector3.new(0, 0, -1)))

		-- THE ACTUAL FIX for the pose sticking (see the written report). The
		-- C0 restore above is not what was leaving arms out and legs trailing
		-- -- that pairing is symmetric on every path -- the HUMANOID'S OWN
		-- FREEFALL ANIMATION was. Nothing in this project has ever touched the
		-- Humanoid state machine, and a character whose root is Anchored (see
		-- onRelease) generates no physics contacts, so the Humanoid latches
		-- into Freefall for the flight and the default Animate script plays the
		-- falling animation: arms out, legs trailing, driven through
		-- Motor6D.Transform, which is a completely separate channel from the C0
		-- that restoreFlightPose writes. Restoring C0 therefore could not clear
		-- it, and nothing else was going to either -- the character stays
		-- anchored deliberately all the way through the box and the reveal, so
		-- the state machine never gets a chance to notice it has landed.
		--
		-- Intermittent for exactly the reason the state is a race: whether the
		-- Humanoid had latched Freefall by the time the anchor went on depends
		-- on physics/floor-detection timing at that instant, which is why the
		-- same flight sometimes lands clean and sometimes does not.
		--
		-- Telling it explicitly costs nothing and is the only thing that talks
		-- to that channel at all. Landed drops the fall animation and settles
		-- to idle.
		if landingHumanoid then
			landingHumanoid:ChangeState(Enum.HumanoidStateType.Landed)
		end

		-- Replicated occupant state (see the written report -- frozen remote
		-- players): tells every OTHER client's own render loop to stop
		-- advancing this character along the trajectory the instant the
		-- server's own one-shot landing PivotTo above lands -- see
		-- renderOtherLanes, which only ever acts on "riding"/"flying".
		local landedPivot = playerSwingPivots[player]
		if landedPivot then
			landedPivot:SetAttribute("RiderState", "landed")
		end

		local earnedLuck = flight.luck

		if flight.zone == "past" then
			-- ===== THE CHEST LANDING. Cleared the road entirely and came down
			-- on the giant slime's platform. No box, no box camera, no burst --
			-- the reward here is ARRIVING somewhere, and the player walks to it.
			--
			-- THE ONE LANDING IN THIS GAME THAT UNFREEZES. Every other landing
			-- leaves the character anchored with AutoRotate off, all the way
			-- through the box and the reveal, because there is nothing to walk
			-- to. Here there is, so the anchor comes straight back off. Both
			-- the anchor and AutoRotate are restored on the way out (see
			-- beginChestLanding), so the click-to-return path behaves exactly
			-- as it does everywhere else.
			states[player] = "chest"
			beginChestLanding(player, character)
		elseif earnedLuck > 0 then
			-- Mystery box: the box's STARTING luck is the exact value already
			-- computed at release and already shown in the landing readout
			-- (see onRelease/bandLuckForLandingZ) -- carried forward, not
			-- rerolled or re-derived. Every press from here is scored in
			-- onBoxPress below.
			states[player] = "box"
			activeBoxes[player] = {
				character = character,
				luck = earnedLuck,
				pending = false,
			}
			boxStartedRemote:FireClient(player, earnedLuck)
		else
			-- 0 luck: nothing was earned to gamble with, so no box appears at
			-- all -- straight to the existing reset flow, unchanged from
			-- before this pass. See the written report for why a box here
			-- (doubling zero forever) would just be a dead interaction.
			states[player] = "cooldown"
			-- AUTOMATIC, and only on this path: a luckless landing puts
			-- nothing on screen to click, so the player is moved back to their
			-- swing on RESET_DELAY without being asked. The reward path
			-- deliberately does the opposite -- see scheduleLucklessReturn's
			-- own header.
			scheduleLucklessReturn(player, character)
		end
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
	local box = activeBoxes[player]
	if states[player] ~= "box" or not box then
		return
	end
	-- THE RATE LIMIT, AND NOTHING ELSE (see the written report -- splitting
	-- BOX_ROLL_DELAY_SECONDS). box.pending used to do two jobs at once: it
	-- was the rate limit AND it was implicitly cleared by the delayed result
	-- firing, which meant the pacing of the RESULT and the ceiling on ROLLS
	-- PER SECOND were the same number and could not be tuned apart. The
	-- result is now immediate (below); this flag keeps the ceiling.
	--
	-- STILL FULLY SERVER-SIDE. Every press that arrives while pending is set
	-- returns right here, before math.random is ever reached -- so a modified
	-- client firing BoxPress in a tight loop still gets at most one roll per
	-- BOX_PRESS_COOLDOWN_SECONDS. Nothing about that guarantee depended on
	-- the result being delayed; it only ever depended on this flag, and the
	-- flag now has its own timer instead of borrowing the result's.
	--
	-- Reading activeBoxes[player] (six-lane pass 2) rather than a single
	-- shared activeBox is what makes this safe to run for several different
	-- players' boxes at once: each call only ever reads/writes the CALLING
	-- player's own entry.
	if box.pending then
		return
	end
	box.pending = true

	-- THE CLEAR, on its own timer. Guarded on identity, not just presence:
	-- if this player left, died, or resolved this box and started another
	-- one (see clearActiveRider and the landing handler), activeBoxes[player]
	-- is either nil or a DIFFERENT table, and clearing pending on it would
	-- hand a fresh box a free extra roll. Comparing the captured `box`
	-- against the live entry makes that impossible. On the open branch below
	-- the entry is nil'd immediately, so this simply no-ops -- pending is
	-- irrelevant once the box is gone.
	task.delay(LaunchConfig.BOX_PRESS_COOLDOWN_SECONDS, function()
		if activeBoxes[player] == box then
			box.pending = false
		end
	end)

	-- THE ONLY THING A BOX ROLL IS EVER DERIVED FROM: math.random(), called
	-- here, server-side, synchronously inside the press that asked for it.
	-- The client sent nothing but a bare press signal, so there is no number
	-- in this path for a modified client to influence, let alone force a
	-- double or fake a luck value.
	--
	-- SYNCHRONOUS NOW, where this used to sit inside a task.delay. The state
	-- re-checks that delay needed (activeBoxes[player] ~= box, states[player]
	-- ~= "box") are gone with it -- nothing can have changed between the
	-- guard at the top of this function and here, because there is no longer
	-- a yield in between.
	local doubled = math.random() < LaunchConfig.BOX_DOUBLE_CHANCE
	if not doubled then
		local finalLuck = box.luck
		-- box.character is deliberately NOT captured here any more: this path
		-- no longer schedules anything that moves the player (see the reveal
		-- delay below -- the click does that, through onReturnToSwing, which
		-- reads activeCharacters fresh at the moment it fires rather than a
		-- reference captured seconds earlier and possibly since respawned).
		activeBoxes[player] = nil
		states[player] = "cooldown"
		boxResultRemote:FireClient(player, true, finalLuck)

		-- THE SLIME: rolled immediately, server-side, from this box's own
		-- final luck -- see SlimeRoll.rollSlime. Nothing about WHICH slime is
		-- ever sent to or influenced by the client; only its globalIndex goes
		-- over the wire (see slimeRevealedRemote above), and the client looks
		-- up name/tier/colour/income from the same shared SlimeData table this
		-- rolled from. The roll itself lives in a ServerScriptService module a
		-- client cannot even require, let alone call.
		local slime = SlimeRoll.rollSlime(finalLuck)
		local isNew = PlayerProfile.recordSeen(player, slime.globalIndex)

		-- THE SECOND BEAT: the box's own open is the first -- and on the
		-- client that open now occupies real time of its own (a thrash into a
		-- burst, see LaunchClient's box motion block), which this delay has to
		-- stay longer than or the slime would land on top of a box still
		-- coming apart. It currently is, with room to spare; see that block's
		-- own budget note.
		task.delay(SlimeConfig.REVEAL_BOX_TO_SLIME_DELAY_SECONDS, function()
			-- THE BASE: handed off at the exact moment of the reveal, not
			-- before -- see PlayerProfile.receiveSlime. Auto-placed if a slot
			-- is free, otherwise added to that player's inventory (never
			-- discarded -- see PlayerProfile.luau and the written report).
			--
			-- UNCONDITIONAL, and deliberately ahead of the guard below: the
			-- slime was rolled and recordSeen'd the instant the box opened, so
			-- it is already theirs. Dying during the 0.6s before it appears
			-- must not cost them the prize -- receiveSlime is a no-op for a
			-- player with no profile left, so this is safe on the disconnect
			-- case too.
			PlayerProfile.receiveSlime(player, slime)

			-- BUT ONLY SHOW IT IF THIS LANDING IS STILL LIVE. clearActiveRider
			-- (death, disconnect) resets states away from "cooldown" and has
			-- already fired its own ResetReady, so anything else here means
			-- this reveal belongs to a sequence that was cancelled. Sending it
			-- anyway would pop a panel onto a freshly respawned player -- and
			-- since the panel no longer has a timer, it would sit there until
			-- they clicked it, then teleport them for a landing they no longer
			-- remember. Bail instead: the prize is banked above, the client was
			-- already reset, nothing is owed.
			if states[player] ~= "cooldown" then
				return
			end

			-- ARMING THE CLICK, and that is ALL this does -- no timer, no
			-- move, no ResetReady. The reveal panel stays up until the player
			-- dismisses it (see LaunchClient's SlimeRevealed handler), and
			-- dismissing it IS the return -- so all the server owes them here
			-- is a state that onReturnToSwing will accept. Everything else
			-- happens in that handler, whenever the click actually comes.
			--
			-- Set as the reveal is SENT rather than when the client reports
			-- itself dismissable, so the click can never race ahead of the
			-- guard: by the time the panel is on screen, let alone past its
			-- REVEAL_DISMISS_LOCKOUT_SECONDS, this is already done.
			--
			-- "grounded" while still anchored means "eligible to return", not
			-- "free to walk" -- unchanged in meaning from the shared reset
			-- this replaced. moveToLaneReturn is the only thing that unanchors.
			-- Verified safe to hold indefinitely: checkProximityMounts also
			-- runs on "grounded" players, but the closest a REWARD landing can
			-- be to the swing pivot is RUNWAY_START_Z to SWING_PIVOT_Z, 34.26
			-- studs, against a SWING_MOUNT_RADIUS_STUDS of 18 -- so a player
			-- reading this panel can never be auto-mounted out from under it.
			states[player] = "grounded"
			if player.Parent then
				slimeRevealedRemote:FireClient(player, slime.globalIndex, isNew)
			end
		end)
	else
		-- pending is deliberately NOT cleared here any more -- that is the
		-- cooldown timer's job above, and clearing it now would restore the
		-- old behaviour where a double could be re-pressed instantly.
		box.luck *= 2
		boxResultRemote:FireClient(player, false, box.luck)
	end
end

boxPressRemote.OnServerEvent:Connect(onBoxPress)

-- ===== THE CHEST PROMPT =====
-- ONE chest for the whole server (built by MapBuilder alongside the landmark),
-- gated PER PLAYER here. ProximityPrompt has no per-player enable, and it does
-- not need one: the gate is a server-side check on the CALLING player's own
-- pending flag, which is exactly where every other authority in this project
-- lives. Six players can stand on the platform at once; each one's Triggered
-- consumes only their own entitlement, and a player without one simply gets
-- nothing when they hold the prompt.
--
-- WAITED FOR, NOT ASSUMED: MapBuilder and this file are both top-level server
-- scripts with no guaranteed run order, so this yields rather than erroring if
-- the landmark has not been built yet -- same pattern PlayerProfile uses for
-- MapBlockout.
task.spawn(function()
	local landmark = Workspace:WaitForChild("GiantSlimeLandmark", 30)
	local chest = landmark and landmark:WaitForChild("TreasureChest", 30)
	local chestBase = chest and chest:FindFirstChild("Base")
	local prompt = chestBase and chestBase:FindFirstChild("OpenPrompt")
	local lid = chest and chest:FindFirstChild("Lid")
	if not (prompt and prompt:IsA("ProximityPrompt") and lid and lid:IsA("BasePart")) then
		warn("[LaunchServer] treasure chest never appeared -- the tier-11 platform landing will still work, but the chest cannot be opened this session.")
		return
	end

	local lidClosedCFrame = lid.CFrame
	local hingeZ = lid:GetAttribute("HingeZ")
	local hingeY = lid:GetAttribute("HingeY")

	-- Swings the lid up about its own back-bottom edge, so it opens AWAY from
	-- the approaching player. Rotate-about-a-point, expressed as the standard
	-- move-to-origin / rotate / move-back, using the hinge MapBuilder recorded
	-- rather than re-deriving the chest's assembly here.
	local function setLidOpen(open: boolean)
		if not (typeof(hingeZ) == "number" and typeof(hingeY) == "number") then
			return
		end
		if not open then
			lid.CFrame = lidClosedCFrame
			return
		end
		local hinge = CFrame.new(lid.Position.X, hingeY, hingeZ)
		local toHinge = hinge:ToObjectSpace(lidClosedCFrame)
		lid.CFrame = hinge * CFrame.Angles(-math.rad(TreasureConfig.CHEST_LID_OPEN_DEGREES), 0, 0) * toHinge
	end

	prompt.Triggered:Connect(function(player: Player)
		-- THE GATE, and the only one needed. consumeChestPending is atomic on
		-- the profile: it returns true exactly once per earned chest, so two
		-- Triggered signals from the same player -- a double tap, a modified
		-- client spamming it -- award one slime between them. Nothing about
		-- the prompt's own state is trusted.
		if not PlayerProfile.consumeChestPending(player) then
			return
		end

		local slime = rollChestSlime()
		local isNew = PlayerProfile.recordSeen(player, slime.globalIndex)
		PlayerProfile.receiveSlime(player, slime)
		PlayerProfile.recordChestOpened(player)

		setLidOpen(true)
		task.delay(TreasureConfig.CHEST_LID_RECLOSE_SECONDS, function()
			-- Closes for the next visitor. CHEST_LID_RECLOSE_SECONDS, not the
			-- abandon timeout it used to borrow -- two unrelated concerns
			-- should not share a number. Long enough that the opener never
			-- sees it shut in front of them; the lid is cosmetic and shared,
			-- so a second player arriving mid-window simply finds it open.
			setLidOpen(false)
		end)

		-- Re-freeze and hand the player to the SAME click-to-return path every
		-- other reward uses (see onBoxPress's own reveal block): the panel goes
		-- up, they dismiss it, onReturnToSwing takes them home. This is why the
		-- chest landing needs no return mechanism of its own.
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
		local rootPart = humanoid and humanoid.RootPart
		if rootPart then
			rootPart.Anchored = true
		end
		if humanoid then
			humanoid.AutoRotate = false
		end

		states[player] = "grounded"
		if player.Parent then
			-- ORDER MATTERS: the anchor has to be on the client before the
			-- reveal that reads it. Both are RemoteEvents to the same client,
			-- which Roblox delivers in send order, so this is guaranteed
			-- rather than merely likely.
			--
			-- The slime rises out of the chest's TOP FACE -- the lid's own
			-- world position plus half its height, so the anchor tracks the
			-- chest wherever MapBuilder put it. `toward` points back down the
			-- road (+Z), the direction the player walked in from, so the
			-- mesh's face meets them (see SlimeBuilder's MESH_FACE_AXIS).
			local topY = lidClosedCFrame.Position.Y + lid.Size.Y / 2
			local anchor = CFrame.new(lidClosedCFrame.Position.X, topY, lidClosedCFrame.Position.Z)
			chestRevealRemote:FireClient(player, anchor, Vector3.new(0, 0, 1))
			slimeRevealedRemote:FireClient(player, slime.globalIndex, isNew)
		end
	end)
end)
