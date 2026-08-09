--!strict
-- Input + UI only. There is exactly one outgoing signal now -- a bare Release,
-- fired once per activation -- and this script never computes distance; the
-- server sends the full, already-final flight description (distance, arc height,
-- duration, start TIME, start position) the instant it processes Release, since
-- the deterministic scripted flight means that number is already fully known
-- before the animation even starts. This script's job is: drive the flight
-- camera and count the distance up live, purely as a client-side rendering of
-- numbers the server already computed -- see FlightStarted below. The sweeping
-- bar/multiplier readout is separate, pre-release, cosmetic prediction: it
-- computes the SAME swingPhase()/swingTheta()/launchMultiplier formulas the
-- server uses, from the same shared LaunchConfig constants and Roblox's
-- server-synced clock (workspace:GetServerTimeNow()), so it visually tracks what
-- the server sees without any per-frame network message. The actual release
-- timing that determines power is read by the SERVER, from the SERVER's own
-- clock, the instant it receives Release -- see LaunchServer.server.luau.
--
-- RIDING is ALSO rendered entirely here: the swing seat and the rider character
-- (if this client IS the assigned rider -- see RidingAssigned below) are
-- repositioned every RenderStepped from the exact same swingTheta()/
-- swingSeatPosition() math the server used to run itself, once per Heartbeat.
-- FLIGHT now works the same way: the character is positioned every
-- RenderStepped from trajectoryCFrame, the SAME u already computed for the
-- chase camera on that same frame. In both cases the server no longer touches
-- the character's CFrame at all during that phase -- see the written report for
-- why watching a Heartbeat-then-replicated character with a full-frame-rate
-- camera reads as jitter/stutter, for riding and flight alike.
--
-- ===== THIS FILE WAS SPLIT (see REPORT.md). It reached Luau's hard limit of
-- 200 locals in one function scope -- a script's own body is a function, and
-- everything here was declared at its top level, so the 201st declaration
-- (renderOtherLanes) refused to compile. Four subsystems moved out into
-- ModuleScripts under ReplicatedStorage.LaunchClient, each one lifted VERBATIM,
-- bodies and comments both:
--
--   LaunchFormulas      every formula this client mirrors from LaunchServer.
--                       Pure, stateless, closes over nothing.
--   LaunchHud           the flight HUD: the widgets and the writes to them.
--                       Built by create(), below, at the same point in this
--                       file's startup the construction used to sit at.
--   LaunchRewardScene   the box, its camera, the character's invisibility,
--                       the suppressed HUDs, the box's motion, the reveal
--                       slime, and the single teardown that releases all of
--                       them. One module because they are one lifetime --
--                       see its own header on why splitting it further would
--                       have weakened the acquire/release structure.
--   LaunchRemoteLanes   the other five lanes, drawn from replicated
--                       attributes. Always was a deliberately separate
--                       system; now it is a separate file.
--
-- WHAT STAYED HERE: the bootstrap (remotes, this client's own pivot/lane/
-- tier/structure), this client's own state (grounded/mounted/canRelease, the
-- flight readout values, the box flags), every remote handler, the input
-- handler, and the two render loops' connect sites. In other words, this file
-- is now the client's WIRING -- what happens when, in what order, and who is
-- told about it -- and the four modules are what it wires together. =====
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local LaunchConfig = require(ReplicatedStorage.Config.LaunchConfig)
local LuckCurve = require(ReplicatedStorage.Config.LuckCurve)
local SlimeConfig = require(ReplicatedStorage.Config.SlimeConfig)
local SlimeData = require(ReplicatedStorage.Config.SlimeData)
local SwingGeometry = require(ReplicatedStorage.Config.SwingGeometry)
local RunwayGeometry = require(ReplicatedStorage.Config.RunwayGeometry)

-- The four subsystems this file was split into -- see the header. Requiring a
-- module runs its body, and every one of these four bodies only DECLARES
-- things: no instance is created, no connection is made and no attribute is
-- read at require time. That is what makes it safe for these to sit up here
-- with the config requires while the two that build something
-- (LaunchHud.create, LaunchRewardScene.create) are still called further down,
-- at the exact points their construction used to happen.
--
-- FROM ReplicatedStorage, NOT FROM script.Parent, and that is a startup
-- CORRECTNESS requirement rather than a preference (see REPORT.md). These four
-- lived beside this script in StarterPlayerScripts for exactly one pass, and
-- this line threw "LaunchFormulas is not a valid member of PlayerScripts" on
-- the first run: PlayerScripts is populated per player by CLONING
-- StarterPlayerScripts' children, and a LocalScript in there can start
-- executing before its own siblings have finished arriving. There is no
-- ordering to rely on and no amount of care in this file can create one.
-- ReplicatedStorage has no such hazard -- it is part of the initial DataModel
-- the client receives before any script of its runs, which is why every
-- ReplicatedStorage.Config require in this project (and in the six other
-- client scripts) has always been a plain index with no WaitForChild.
local LaunchFormulas = require(ReplicatedStorage.LaunchClient.LaunchFormulas)
local LaunchHud = require(ReplicatedStorage.LaunchClient.LaunchHud)
local LaunchRewardScene = require(ReplicatedStorage.LaunchClient.LaunchRewardScene)
local LaunchRemoteLanes = require(ReplicatedStorage.LaunchClient.LaunchRemoteLanes)
local ConveyorScroll = require(ReplicatedStorage.LaunchClient.ConveyorScroll)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera :: Camera

-- BUG FIX (see the written report): bounding the Remotes FOLDER wait alone
-- wasn't enough -- LaunchServer now builds that folder fully off-tree and
-- only parents it once every remote already exists inside it (see
-- LaunchServer.server.luau), which closes the specific race that let a
-- client see a half-built folder in the first place. This bounded wait (and
-- every other one below) is the belt-and-braces backstop on TOP of that
-- structural fix, not a substitute for it: every single WaitForChild in
-- this script is now bounded, and ANY of them failing shows the same
-- visible error instead of leaving this script hung partway through with
-- nothing past that point -- including all HUD construction -- ever
-- running (which is exactly what "no release bar rendering" was).
local REMOTES_WAIT_TIMEOUT_SECONDS = 10
local SWING_STRUCTURE_WAIT_TIMEOUT_SECONDS = 10

local function failLaunchHud(missingDescription: string)
	warn(string.format(
		"[LaunchClient] %s never appeared after %d seconds -- LaunchServer likely errored during startup. Launch HUD will not render this session; the rest of the client is unaffected.",
		missingDescription, REMOTES_WAIT_TIMEOUT_SECONDS
	))
	local errorGui = Instance.new("ScreenGui")
	errorGui.Name = "LaunchHud"
	errorGui.ResetOnSpawn = false
	errorGui.IgnoreGuiInset = true
	errorGui.Parent = playerGui

	local errorLabel = Instance.new("TextLabel")
	errorLabel.Name = "LaunchUnavailable"
	errorLabel.AnchorPoint = Vector2.new(0.5, 0)
	errorLabel.Position = UDim2.new(0.5, 0, 0.05, 0)
	errorLabel.Size = UDim2.new(0, 480, 0, 40)
	errorLabel.BackgroundTransparency = 1
	errorLabel.Font = Enum.Font.GothamBold
	errorLabel.TextScaled = true
	errorLabel.TextColor3 = Color3.new(1, 0.35, 0.3)
	errorLabel.TextStrokeTransparency = 0.3
	errorLabel.Text = "Launch HUD unavailable -- server failed to start up"
	errorLabel.Parent = errorGui
end

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", REMOTES_WAIT_TIMEOUT_SECONDS)
if not remotesFolder then
	failLaunchHud("ReplicatedStorage.Remotes")
	return
end

-- Every remote bounded individually now, not just the folder -- see the
-- comment above. Once the folder itself is confirmed present, these should
-- all resolve essentially instantly (LaunchServer only ever reveals the
-- folder after every remote already exists inside it), so this is purely
-- defensive; the timeout is only ever meant to fire if something is
-- genuinely broken.
local releaseRemoteMaybe = remotesFolder:WaitForChild("Release", REMOTES_WAIT_TIMEOUT_SECONDS)
local flightStartedRemoteMaybe = remotesFolder:WaitForChild("FlightStarted", REMOTES_WAIT_TIMEOUT_SECONDS)
local resetReadyRemoteMaybe = remotesFolder:WaitForChild("ResetReady", REMOTES_WAIT_TIMEOUT_SECONDS)
local boxStartedRemoteMaybe = remotesFolder:WaitForChild("BoxStarted", REMOTES_WAIT_TIMEOUT_SECONDS)
local boxPressRemoteMaybe = remotesFolder:WaitForChild("BoxPress", REMOTES_WAIT_TIMEOUT_SECONDS)
local boxResultRemoteMaybe = remotesFolder:WaitForChild("BoxResult", REMOTES_WAIT_TIMEOUT_SECONDS)
local slimeRevealedRemoteMaybe = remotesFolder:WaitForChild("SlimeRevealed", REMOTES_WAIT_TIMEOUT_SECONDS)
-- Server -> client, chest reveals only -- arms the reveal's world anchor just
-- before SlimeRevealed. See its own handler below.
local chestRevealRemoteMaybe = remotesFolder:WaitForChild("ChestRevealStarted", REMOTES_WAIT_TIMEOUT_SECONDS)
local ridingAssignedRemoteMaybe = remotesFolder:WaitForChild("RidingAssigned", REMOTES_WAIT_TIMEOUT_SECONDS)
-- Client -> server ack -- see LaunchServer.server.luau's setupCharacter
-- watchdog: fired once this script has made it all the way through every
-- gate below and is about to start driving the rider's seat/character every
-- frame, so the server can tell "client is alive" apart from "client never
-- came up," which otherwise look identical from server state alone.
local riderReadyRemoteMaybe = remotesFolder:WaitForChild("RiderReady", REMOTES_WAIT_TIMEOUT_SECONDS)
-- Client -> server: content-free, exactly like Release/BoxPress -- fired by
-- the click-anywhere/tap listener below while THIS client is grounded. See
-- LaunchServer.server.luau's onReturnToSwing for the server-side gate
-- (states[player] == "grounded") and the actual teleport.
local returnToSwingRemoteMaybe = remotesFolder:WaitForChild("ReturnToSwing", REMOTES_WAIT_TIMEOUT_SECONDS)
-- Client -> server: content-free, exactly like Release/BoxPress -- fired by
-- the DISMOUNT button (visible only while riding, see below). See
-- LaunchServer.server.luau's onDismount for the server-side gate
-- (states[player] == "riding") and the actual teleport.
local dismountRemoteMaybe = remotesFolder:WaitForChild("Dismount", REMOTES_WAIT_TIMEOUT_SECONDS)
-- Server -> client: fires ONCE, right after LaunchServer.server.luau's
-- onDismount actually moves this player -- see its own comment for why
-- this exists: without an explicit signal, this client's own render loop
-- has no way to learn the server just dismounted it, and keeps driving the
-- character back onto the seat every frame regardless.
local dismountedRemoteMaybe = remotesFolder:WaitForChild("Dismounted", REMOTES_WAIT_TIMEOUT_SECONDS)

if not (
	releaseRemoteMaybe
	and flightStartedRemoteMaybe
	and resetReadyRemoteMaybe
	and boxStartedRemoteMaybe
	and boxPressRemoteMaybe
	and boxResultRemoteMaybe
	and slimeRevealedRemoteMaybe
	and chestRevealRemoteMaybe
	and ridingAssignedRemoteMaybe
	and riderReadyRemoteMaybe
	and returnToSwingRemoteMaybe
	and dismountRemoteMaybe
	and dismountedRemoteMaybe
) then
	failLaunchHud("one or more remotes inside ReplicatedStorage.Remotes")
	return
end

local releaseRemote = releaseRemoteMaybe :: RemoteEvent
local flightStartedRemote = flightStartedRemoteMaybe :: RemoteEvent
local resetReadyRemote = resetReadyRemoteMaybe :: RemoteEvent
local boxStartedRemote = boxStartedRemoteMaybe :: RemoteEvent
local boxPressRemote = boxPressRemoteMaybe :: RemoteEvent
local boxResultRemote = boxResultRemoteMaybe :: RemoteEvent
local slimeRevealedRemote = slimeRevealedRemoteMaybe :: RemoteEvent
local chestRevealRemote = chestRevealRemoteMaybe :: RemoteEvent
local ridingAssignedRemote = ridingAssignedRemoteMaybe :: RemoteEvent
local riderReadyRemote = riderReadyRemoteMaybe :: RemoteEvent
local returnToSwingRemote = returnToSwingRemoteMaybe :: RemoteEvent
local dismountRemote = dismountRemoteMaybe :: RemoteEvent
local dismountedRemote = dismountedRemoteMaybe :: RemoteEvent

-- BUG FIX (see the written report -- six-lane pass 1): this used to be a
-- bare "SwingPivot"/"SwingStructure" WaitForChild -- the single shared
-- names every previous pass used. There are up to six now, one per player
-- (SwingPivot_<UserId>/SwingStructure_<UserId>, the same Base_<UserId>
-- naming convention BaseClient.client.luau already uses), so this client
-- computes ITS OWN pair from player.UserId -- no server round-trip, no
-- ordering dependency on when any other client's own swing gets built.
local ownSwingPivotName = string.format("SwingPivot_%d", player.UserId)
local ownSwingStructureName = string.format("SwingStructure_%d", player.UserId)
local swingPivotMaybe = Workspace:WaitForChild(ownSwingPivotName, SWING_STRUCTURE_WAIT_TIMEOUT_SECONDS)
local swingStructureFolderMaybe = Workspace:WaitForChild(ownSwingStructureName, SWING_STRUCTURE_WAIT_TIMEOUT_SECONDS)
if not swingPivotMaybe or not swingStructureFolderMaybe then
	failLaunchHud(string.format("Workspace.%s or Workspace.%s", ownSwingPivotName, ownSwingStructureName))
	return
end
local swingPivot = swingPivotMaybe :: BasePart
local swingStructureFolder = swingStructureFolderMaybe

-- This player's own lane index (six-lane pass 2) -- read straight off THIS
-- client's own swing pivot, which LaunchServer's buildPlayerSwing stamps
-- with a LaneIndex attribute BEFORE ever parenting the pivot to Workspace
-- (same "populate then reveal" guarantee the Remotes folder above relies
-- on), so it is guaranteed already present the instant the WaitForChild
-- above resolved -- no separate remote, no separate wait. This is what
-- guarantees the swingPhase offset computed below can never disagree with
-- the server's own: both this client and LaunchServer's onRelease derive
-- their offset from this exact same integer (PlayerProfile's own
-- profile.baseIndex), never two independently-sent copies of it.
local ownLaneIndexAttribute = swingPivot:GetAttribute("LaneIndex")
if typeof(ownLaneIndexAttribute) ~= "number" then
	failLaunchHud(string.format("Workspace.%s.LaneIndex attribute", ownSwingPivotName))
	return
end
local ownLaneIndex = ownLaneIndexAttribute :: number

-- THIS PLAYER's own swing tier. The HUD needs it for exactly one reason: the
-- snap threshold is PER-TIER (LaunchConfig.SWING_TIER_SNAP_THRESHOLD), so
-- launchMultiplier below cannot grade a release without knowing which tier it
-- is grading -- see snapThresholdForTier, and see REPORT.md for the bug that
-- came of grading it against the global value instead.
--
-- Read off the SAME replicated Base_<UserId> "SwingTier" attribute
-- BaseClient's tier label and LaunchServer's own swing-rebuild listener
-- already trust: PlayerProfile writes this player's real tier there the
-- instant it becomes known -- a load finishing, a purchase, a dev-panel set,
-- a wipe -- so it is the one source that is always caught up, with no new
-- remote and no round trip at release time. Cached and refreshed on change
-- (same as BaseClient/ShopClient) rather than read on every frame of the bar.
--
-- BOUNDED wait, and a fallback rather than failLaunchHud: the base folder is
-- built server-side before this player's swing pivot even exists (see
-- PlayerProfile.onPlayerAdded), so it is always already there by the time the
-- pivot WaitForChild above has resolved. If it somehow is not, tier 1 is the
-- right thing to assume -- it is exactly what PlayerProfile.getSwingTier
-- itself falls back to -- and being wrong here costs a mislabelled outcome
-- word, never a wrong flight: the SERVER grades the launch, from its own copy
-- of the tier, and this file never sends a multiplier anywhere.
local ownBaseFolderName = string.format("Base_%d", player.UserId)
local ownBaseFolder = Workspace:WaitForChild(ownBaseFolderName, SWING_STRUCTURE_WAIT_TIMEOUT_SECONDS)
local ownSwingTier = 1

local function refreshOwnSwingTier()
	local tier = if ownBaseFolder then ownBaseFolder:GetAttribute("SwingTier") else nil
	ownSwingTier = if typeof(tier) == "number" then tier else 1
end

if ownBaseFolder then
	ownBaseFolder:GetAttributeChangedSignal("SwingTier"):Connect(refreshOwnSwingTier)
	refreshOwnSwingTier()
else
	warn(string.format(
		"[LaunchClient] Workspace.%s never appeared -- the outcome readout will grade every release as tier 1. The flight itself is unaffected (the server grades it).",
		ownBaseFolderName
	))
end

-- The swing STRUCTURE (posts/beam/seat/chain) is built by SwingBuilder.luau
-- and completely REBUILT (destroyed and recreated) every time the rider's
-- tier changes -- see the written report. That means SwingSeat/
-- SwingChainAnchorLeft/SwingChainAnchorRight/SwingChainLinks are NOT stable
-- references for the life of the server the way SwingPivot is; a cached
-- reference can go stale (its .Parent becomes nil) the instant a tier
-- purchase rebuilds the structure. ensureSwingReferences() below
-- re-acquires them on demand, cheaply checked every frame, rather than
-- requiring this script to somehow learn "the structure just rebuilt" as a
-- separate event.
local swingSeatModelMaybe = swingStructureFolder:WaitForChild("SwingSeat", SWING_STRUCTURE_WAIT_TIMEOUT_SECONDS)
local swingChainAnchorLeftMaybe = swingStructureFolder:WaitForChild("SwingChainAnchorLeft", SWING_STRUCTURE_WAIT_TIMEOUT_SECONDS)
local swingChainAnchorRightMaybe = swingStructureFolder:WaitForChild("SwingChainAnchorRight", SWING_STRUCTURE_WAIT_TIMEOUT_SECONDS)
local swingChainLinksFolderMaybe = swingStructureFolder:WaitForChild("SwingChainLinks", SWING_STRUCTURE_WAIT_TIMEOUT_SECONDS)
if not (swingSeatModelMaybe and swingChainAnchorLeftMaybe and swingChainAnchorRightMaybe and swingChainLinksFolderMaybe) then
	failLaunchHud("one or more parts inside Workspace.SwingStructure")
	return
end
local swingSeatModel = swingSeatModelMaybe :: Model
local swingChainAnchorLeft = swingChainAnchorLeftMaybe :: BasePart
local swingChainAnchorRight = swingChainAnchorRightMaybe :: BasePart
local swingChainLinksFolder = swingChainLinksFolderMaybe :: Folder

local function ensureSwingReferences()
	if not swingSeatModel.Parent then
		swingSeatModel = swingStructureFolder:WaitForChild("SwingSeat") :: Model
	end
	if not swingChainAnchorLeft.Parent then
		swingChainAnchorLeft = swingStructureFolder:WaitForChild("SwingChainAnchorLeft") :: BasePart
	end
	if not swingChainAnchorRight.Parent then
		swingChainAnchorRight = swingStructureFolder:WaitForChild("SwingChainAnchorRight") :: BasePart
	end
	if not swingChainLinksFolder.Parent then
		swingChainLinksFolder = swingStructureFolder:WaitForChild("SwingChainLinks") :: Folder
	end
end

-- THIS CLIENT'S OWN SEAT, and the reason it did not move to LaunchFormulas
-- with the rest of the swing math: it closes over swingPivot. Mirrors
-- LaunchServer's own swingSeatPosition exactly -- same formula, same
-- derivation, just read from the replicated pivot instead of computed fresh,
-- since the server is the only thing that ever moves it. LaunchRemoteLanes
-- has the same three lines against a pivot it is handed per lane
-- (seatPositionForPivot); the two were left separate rather than merged --
-- see REPORT.md.
local function swingSeatPosition(theta: number): Vector3
	local pivotPosition = swingPivot.Position
	-- Effective rope length for WHATEVER tier is currently built -- derived
	-- from the pivot's own live (replicated) Y, not a raw LaunchConfig.
	-- SWING_ROPE_LENGTH read, since the rope is now scaled by tier right
	-- alongside the pivot (see SwingBuilder.luau/SwingGeometry.luau). Mirrors
	-- LaunchServer's own swingSeatPosition exactly -- same formula, same
	-- derivation, just read from the replicated pivot instead of computed
	-- fresh, since the server is the only thing that ever moves it.
	local length = SwingGeometry.ropeLengthForPivotY(pivotPosition.Y)
	return pivotPosition + Vector3.new(0, -length * math.cos(theta), -length * math.sin(theta))
end

-- Splits the shared SwingChainLinks folder by each link's own "Side"
-- attribute (set once at build time, see SwingBuilder.luau) and repositions
-- each side against its OWN anchor and OWN seat attachment. The seat
-- attachments live on SeatCore and move (and TILT) with it every frame via
-- swingSeatModel:PivotTo below, so reading their WorldPosition here always
-- reflects THIS frame's actual seat corner -- never a flat world-space
-- +-seatWidth/2 guess that would drift once the seat tilts off theta=0.
local function repositionChainLinks()
	if not swingChainAnchorLeft.Parent or not swingChainAnchorRight.Parent then
		return
	end
	local seatCore = swingSeatModel.PrimaryPart
	if not seatCore then
		return
	end
	local leftAttachment = seatCore:FindFirstChild("ChainBottomAttachmentLeft") :: Attachment?
	local rightAttachment = seatCore:FindFirstChild("ChainBottomAttachmentRight") :: Attachment?
	if not leftAttachment or not rightAttachment then
		return
	end

	local leftLinks, rightLinks = {}, {}
	for _, link in swingChainLinksFolder:GetChildren() do
		local side = link:GetAttribute("Side")
		if side == "Left" then
			table.insert(leftLinks, link)
		elseif side == "Right" then
			table.insert(rightLinks, link)
		end
	end
	LaunchFormulas.repositionChainSide(leftLinks, swingChainAnchorLeft.Position, leftAttachment.WorldPosition)
	LaunchFormulas.repositionChainSide(rightLinks, swingChainAnchorRight.Position, rightAttachment.WorldPosition)
end

-- Which band a flight came down on, and which zone -- "short" | "road" |
-- "past", the same three-value enum LaunchServer's bandLuckForLandingZ returns
-- and the same arithmetic, half-open floor division and all.
--
-- NO LONGER A PREDICTION (see REPORT.md). This used to take a phase and a tier
-- and re-derive the launch origin from this client's own seat, one hop before
-- the server graded the real release. It now takes the origin and the distance
-- the SERVER computed and sent on FlightStarted -- the exact two numbers
-- trajectoryPosition(startPosition, distance, archHeight, 1) reduces to at u=1,
-- since the arc only ever moves Y. Same inputs, same formula, same shared
-- RunwayGeometry/LuckCurve constants: this cannot disagree with the server
-- about which band a flight reached, because there is nothing left to disagree
-- about.
--
-- BOTH READOUTS BRANCH ON THIS. The ring word wants "road, and the last band".
-- The landing headline wants "past" -- not to say anything (a player standing
-- on the platform can see where they are), but to say NOTHING: a chest landing
-- carries luck 0 by design, so without the zone it cannot be told apart from a
-- whiff and inherits "No luck (short of the road)". See LaunchHud's
-- showLandingResult.
local function landingBandZone(originZ: number, distance: number): (number, string)
	local distanceFromStart = RunwayGeometry.RUNWAY_START_Z - (originZ - distance)
	if distanceFromStart < 0 then
		return -1, "short"
	end
	local index = math.floor(distanceFromStart / LaunchConfig.RUNWAY_BAND_LENGTH_STUDS)
	if index > #LuckCurve.VALUES - 1 then
		return index, "past"
	end
	return index, "road"
end

-- ===== Flight/countup state (set once per flight by FlightStarted) =====
local flightActive = false
local flightStartTime = 0
local flightDuration = 0
local flightDistance = 0
local flightArcHeight = 0
local flightStartPosition = Vector3.zero
local flightLuck = 0

-- BUG FIX (see the written report -- mid-flight death): the ONLY other place
-- flightActive ever went false was the render loop reaching u >= 1 on its
-- own -- a passive, time-based self-clear with no cancellation input. A
-- death mid-flight left this true forever (no Humanoid.Died listener exists
-- in this file, see (b) of the written report), so the abandoned render
-- loop kept PivotTo'ing whatever player.Character currently was -- the
-- newly RESPAWNED character -- along the old trajectory. Called from
-- resetReadyRemote's handler below, now fired by the server for BOTH a
-- normal landing AND a death/disconnect cancellation (see LaunchServer.
-- server.luau's clearActiveRider) -- resetting already-false/already-zero
-- values on a normal landing is a harmless no-op, which is what makes this
-- safe to call from both.
local function resetFlightState()
	flightActive = false
	flightStartTime = 0
	flightDuration = 0
	flightDistance = 0
	flightArcHeight = 0
	flightStartPosition = Vector3.zero
	flightLuck = 0
end

-- ===== Mystery box state (set by BoxStarted, driven by BoxResult) =====
-- boxActive gates whether a press does anything at all -- true from BoxStarted
-- until the box opens (BoxResult with opened = true) or a reset wipes it
-- defensively (see resetReadyRemote below). It is also what makes the box
-- press and the click-anywhere-to-RETURN listener mutually exclusive: see the
-- InputBegan handler.
--
-- The "already pressed, don't send another" guard is NOT here any more -- it
-- was a boolean latch cleared by BoxResult, and it is now a timestamp
-- (lastBoxPressClock, declared beside doBoxPress). See that declaration for
-- why the change was necessary rather than cosmetic.
local boxActive = false

-- The WIDER window: true from BoxStarted until the whole reward sequence has
-- resolved (the box opened, the slime was revealed, ResetReady arrived), where
-- boxActive covers only the part where the box is still pressable. The two
-- differ for the entire thrash + burst + reveal tail, which is exactly the gap
-- the flight HUD was reappearing in -- see refreshFlightHud.
local rewardSequenceActive = false

-- Whether a click right now would dismiss the slime reveal AND return the
-- player to their swing (one action, see dismissRevealAndReturn). False while
-- the panel is not up at all, AND for the first
-- SlimeConfig.REVEAL_DISMISS_LOCKOUT_SECONDS after it appears -- that lockout
-- exists so a click already travelling down from pressing the box cannot skip
-- the reveal before it has been read. Flipping this true is also what puts the
-- in-panel prompt on screen, so the promise and the behaviour turn on together.
local revealDismissable = false

-- ===== UI =====
--
-- BUILT HERE, at the exact point in this file's startup the construction used
-- to sit at -- after every remote has resolved, so a server that never came up
-- shows the failure label and returns above without ever putting a live HUD on
-- screen. See LaunchHud's own header.
local Hud = LaunchHud.create(playerGui)

-- ===== The reward scene: box, box camera, character invisibility, suppressed
-- HUDs, box motion, reveal slime, and the single teardown for all of them.
-- Lives in LaunchRewardScene -- see its header for why those six are one
-- module and why none of the acquire/release halves are on this table. =====
--
-- The two remotes it needs are handed in from the single bootstrap above, and
-- so is a READ of boxActive -- which stays owned here, by setBoxActive, since
-- the input handler below gates on it too. See LaunchRewardScene.create.
local RewardScene = LaunchRewardScene.create(playerGui, boxPressRemote, returnToSwingRemote, function()
	return boxActive
end)

-- ITS OWN CONNECTION, not an addition to the flight/riding render loop below.
-- That loop is the character-and-camera path and is gated on flightActive/
-- mounted; this box is on an unrelated schedule and the two have no
-- frame-ordering relationship at all -- the box only ever exists while the
-- character is frozen, i.e. while that loop is doing nothing to it. Both
-- halves early-return to nothing whenever no box (and no box camera
-- transition) is running, which is nearly always.
RunService.RenderStepped:Connect(RewardScene.update)

-- The conveyor belts' ridge textures -- ONE connection driving BOTH halves
-- (see ConveyorScroll.luau), not one per part.
--
-- ITS OWN CONNECTION, for the same reason the reward scene above has one: the
-- flight/riding render loop further down is gated on flightActive/mounted, and
-- the belts must keep scrolling whether or not this player is riding, flying,
-- or standing still on the other side of the map. Folding it in there would
-- have stopped the world's conveyors whenever the local player happened to be
-- mid-launch. It is a no-op (an empty list, one length check) until MapBuilder
-- has actually built the belts.
RunService.RenderStepped:Connect(ConveyorScroll.update)

-- The SLIME REVEAL PANEL used to be built here -- a centre-screen Frame with
-- a tier-coloured UIStroke border, a NEW/Duplicate badge, a tier line and a
-- name line, plus the in-panel dismiss prompt added with it. All of it is
-- gone: the reveal is a real slime standing in the world where the box was
-- (see showSlimeReveal), and its name/tier/NEW text rides on a billboard above
-- that slime. Deleted with the panel: slimeRevealFrame, slimeRevealCorner,
-- slimeRevealBorder, newBadgeLabel, slimeTierLabel, slimeNameLabel and
-- revealDismissLabel.

-- ===== State =====

-- characterIsFrozen() used to be declared here. It moved UP, above the box
-- block, because releaseBoxCamera needs it -- see its own definition there.

local canRelease = true
-- AUTOMATIC PROXIMITY MOUNTING (see the written report): true only between
-- this client's own RidingAssigned (server-side proximity mount) and the
-- moment its own flight starts -- the local replacement for the old
-- anchor-implied "am I riding" gate the RenderStepped loop used to infer
-- from canRelease/flightActive alone. While false, this character is NEVER
-- PivotTo'd by this script -- normal Humanoid movement drives it, exactly
-- like a grounded, not-yet-mounted (or already-dismounted) player. Reset to
-- false on every fresh CharacterAdded (see below) so a respawn -- e.g. after
-- dying mid-ride, which the server also resets to "grounded" for, see
-- LaunchServer.server.luau's clearActiveRider -- never leaves a stale true
-- behind that would otherwise PivotTo a brand-new character onto a seat the
-- server no longer thinks it owns. Also drives the DISMOUNT button's own
-- visibility (see setMounted) -- visible only in exactly this window, a
-- narrower one than flightHudFrame's own "riding, flying, or box."
local mounted = false

local function setMounted(value: boolean)
	mounted = value
	Hud.setDismountVisible(value)
end

-- PLAYER-TRIGGERED RETURN (see the written report): true exactly when the
-- server's own states[player] == "grounded" -- starts true (a fresh/
-- respawned character always starts grounded, same reasoning `mounted`
-- starts false), flips false the instant this client's own RidingAssigned
-- arrives (mounting), and flips back true the instant ResetReady arrives
-- (the reward sequence -- landing, box, reveal -- has fully resolved). Those
-- are the SAME two remotes that already drive `mounted`/`canRelease`, so
-- `grounded` never needs its own server round-trip to stay in sync -- it is
-- always the logical complement of "currently riding/flying/boxing," which
-- is exactly what those two events already bracket. Also drives
-- flightHudFrame's own visibility (see setGrounded) -- the OPPOSITE of
-- `grounded`, since the whole flight HUD only means something in exactly
-- the window `grounded` is false.
local grounded = true

-- The single owner of `boxActive`, in the same shape as setMounted/setGrounded
-- above: the flag and everything that depends on it move together, so no
-- handler has to remember to refresh anything after flipping it. Every write
-- to boxActive in this file goes through here.
--
-- No longer refreshes anything: the flight HUD gate reads rewardSequenceActive
-- (see refreshFlightHud) and the return prompt this used to drive is gone --
-- it lives inside the reveal panel now and is owned by the reveal's own
-- lockout timer, not by this flag.
local function setBoxActive(value: boolean)
	boxActive = value
end

-- The single owner of `rewardSequenceActive`, same shape. Set true by
-- BoxStarted and false by hideFlightBoxRevealUI, which every path back out of
-- the sequence already funnels through -- so this can never be left true by a
-- path that forgot about it.
local function setRewardSequenceActive(value: boolean)
	rewardSequenceActive = value
	Hud.refreshFlightHud(grounded, rewardSequenceActive)
end

-- BUG FIX (see the written report -- HUD elements persisting after return):
-- neither the box nor the reveal is UI at all any more -- both are Instances
-- in Workspace -- so flightHudFrame.Visible alone never touches either.
-- This used to be hidden only inline inside resetReadyRemote's own handler,
-- which meant it only ever ran on THAT one path back to "grounded" -- a
-- fresh/respawned CharacterAdded or a Dismounted re-entering "grounded" never
-- cleared either, structurally, even though neither is reachable from those
-- two paths TODAY. Centralised here instead, called from setGrounded itself,
-- so every path that ever re-enters "grounded" clears the same set by
-- construction, not by each remote's own handler remembering to.
--
-- destroyWorldBox() replaces what used to be `boxFrame.Visible = false` plus a
-- startBoxMotion("none") to put the panel back on its rest transform. A part
-- has no "hidden" state worth keeping around -- there is nothing to re-show
-- and nothing stale to reset, because the NEXT landing builds a brand-new box
-- from scratch (see showWorldBox) -- so the destroy subsumes both.
-- ONE ACTION, not two. The slime goes away, the camera eases back, the
-- character reappears and the player is sent home, all on the same click --
-- there is deliberately no intermediate state where the reveal has been
-- dismissed but they are still standing on the road looking at nothing.
--
-- Torn down LOCALLY AND IMMEDIATELY rather than waiting for the server to
-- confirm: the click is unambiguous, and holding the scene for a round trip
-- would make it feel like the click missed. If the server rejected the return
-- (it re-checks states[player] == "grounded" in onReturnToSwing, which is the
-- actual gate) the worst case is a cleared scene and a still-frozen player --
-- recoverable by the backstop branch in InputBegan, and not reachable in
-- practice because the server flips to "grounded" as it sends the reveal, well
-- before this can fire.
--
-- revealDismissable is cleared here, so the second click of a double-click
-- cannot fire a second ReturnToSwing.
local function dismissRevealAndReturn()
	RewardScene.endScene()
	revealDismissable = false
	-- DEFERRED IF THE CAMERA IS EASING, immediate otherwise. endRewardScene's
	-- releaseBoxCamera above decides which: it only animates when there is
	-- still a frozen character for the captured view to be framing, and takes
	-- the instant path otherwise -- in which case there is no ease to wait for
	-- and nothing to defer behind. Either way the remote fires exactly once.
	RewardScene.completeDismiss()
end

local function hideFlightBoxRevealUI()
	setBoxActive(false)
	setRewardSequenceActive(false)
	RewardScene.endScene()
	revealDismissable = false
end

-- CALLED ON BOTH TRANSITIONS NOW, not just the return to "grounded" (see the
-- written report -- box camera restoration). The teardown was previously
-- gated on `value` because the only thing it did was hide UI a mounting
-- player could not have up anyway; now it also releases the CAMERA, and a
-- camera left Scriptable is a soft-lock rather than a cosmetic leftover. The
-- mount path (RidingAssigned -> setGrounded(false)) cannot have a box up
-- today, but "cannot today" is exactly the kind of reasoning that stopped
-- being true for the HUD elements this function was written to fix -- so it
-- runs unconditionally and is a no-op when there is nothing to tear down.
local function setGrounded(value: boolean)
	grounded = value
	-- hideFlightBoxRevealUI FIRST, then the refresh: it clears
	-- rewardSequenceActive, so by the time this runs both of the gate's inputs
	-- are settled. Refreshing again here rather than relying on that inner
	-- call is deliberate -- it makes setGrounded correct on its own terms
	-- whatever hideFlightBoxRevealUI does or stops doing later.
	hideFlightBoxRevealUI()
	Hud.refreshFlightHud(grounded, rewardSequenceActive)
end

player.CharacterAdded:Connect(function()
	setMounted(false)
	setGrounded(true)
end)

local function doRelease()
	-- Refuse while not actually seated -- pressing Release/Space while just
	-- walking around (never mounted, or already dismounted after a flight)
	-- must be a complete no-op: the server's own onRelease already rejects
	-- a release from a non-"riding" state, but withOUT this local guard the
	-- HUD would still flip canRelease false and freeze on "0.0 studs" as if
	-- a flight had started, then never recover -- ResetReady/FlightStarted,
	-- the only two things that ever flip canRelease back, would never
	-- arrive, since the server never entered a flight for this press.
	--
	-- BUG FIX (see written report): also refuse while a PREVIOUS flight's local
	-- animation is still counting up. canRelease alone isn't enough to prevent
	-- this -- ResetReady and this client's own flight-completion are governed by
	-- two independently-timed things (the server's RESET_DELAY countdown, and
	-- this client's own render loop reaching u=1), so under enough latency
	-- ResetReady could arrive and re-enable canRelease before flightActive had
	-- naturally cleared. Firing a second Release in that window would overwrite
	-- the still-displaying flight's distance/duration/start data with the new
	-- one's, abandoning the first flight's true final number mid-count.
	if not mounted or not canRelease or flightActive then
		return
	end

	-- NO GRADING HAPPENS HERE ANY MORE (see REPORT.md). This used to compute a
	-- multiplier from this client's own phase and paint the outcome word from
	-- it, one network hop before the server graded the real release -- which is
	-- how a launch the server scored 1.93 could announce itself as
	-- "Perfect!  2.00x". The word and the number are now written by the
	-- FlightStarted handler, from the multiplier the SERVER actually used.
	--
	-- It costs nothing visible: nothing about a flight starts until that same
	-- message arrives. The only things this function still does are freeze the
	-- bar, blank the distance and send the signal -- and the outcome label is
	-- already empty at this point (resetFlightHudText cleared it at the last
	-- ResetReady), so there is no stale text sitting in the gap either.
	--
	-- The phase is still read HERE, and only for the bar freeze below: that
	-- readout is a record of where THIS PLAYER released, which is the one thing
	-- the server's copy cannot tell them.
	local releasePhase = LaunchFormulas.swingPhase(ownLaneIndex)

	-- Freeze the bar/multiplier readout at this EXACT phase -- see
	-- renderBarForPhase's comment. canRelease flips false right below, and the
	-- RenderStepped loop's own "if not canRelease then return end" guard means
	-- nothing overwrites this again until canRelease goes true (ResetReady, at
	-- the start of the next swing).
	Hud.renderBarForPhase(releasePhase, ownSwingTier)

	canRelease = false
	-- Zero the countup through the SAME formatter every other distance goes
	-- through (was a hand-written "0.0 studs" literal) -- so this can never be
	-- the one place left showing a decimal after the format changes.
	Hud.setLiveDistance(0)
	releaseRemote:FireServer()
end

-- GuiButton Mouse* events fire for touch taps too (Roblox synthesizes them), so
-- this covers mouse, touch, and gamepad activation of the on-screen button.
Hud.releaseButton.MouseButton1Click:Connect(doRelease)

-- EXIT button: lets a player who mounted but hasn't released yet back off
-- their swing instead of being forced to sit through a flight they didn't
-- mean to start. Refuses locally while not actually mounted -- same
-- "don't let the HUD get out of sync with a press the server was always
-- going to reject anyway" reasoning doRelease's own `mounted` guard uses --
-- though the button is only ever visible while `mounted` in the first
-- place (see setMounted), so this is a defensive backstop, not the primary
-- gate. LaunchServer.server.luau's onDismount is the REAL gate
-- (states[player] == "riding"), re-checked server-side regardless of
-- anything this button claims.
local function doDismount()
	if not mounted then
		return
	end
	dismountRemote:FireServer()
end

Hud.dismountButton.MouseButton1Click:Connect(doDismount)

-- ===== Pointer input: three gestures, one handler =====
--
-- A mouse click or a touch tap means one of three things depending on where
-- the player is in the reward sequence -- press the box, dismiss the reveal
-- and go home, or the frozen-on-the-road backstop. The handler below takes
-- them in that order, which is also the order they occur in, and each one
-- returns rather than falling through.
--
-- SERVER-AUTHORITATIVE throughout: returnToSwingRemote and BoxPress both
-- carry no data at all, and LaunchServer re-checks states[player] itself
-- before acting on either. The local gates here exist to avoid firing
-- pointless remotes and (for touch) to avoid hijacking movement -- they are
-- not a trust boundary.
--
-- TOUCH SPECIFICALLY (see the written report): Roblox's default mobile
-- control scheme drives ordinary walking via tap-to-move, which fires this
-- SAME InputBegan event, with gameProcessedEvent == false, for every movement
-- tap -- the built-in character controller consumes it through its own bound
-- action, not through GUI hit-testing, so gameProcessedEvent cannot
-- distinguish "tapped to walk" from "tapped to continue". What resolves it is
-- that the server keeps a landed player Anchored for the whole box and reveal
-- (see the Heartbeat landing handler): while that is true, tap-to-move has
-- nothing to compete for, so a tap can only mean the gesture this handler is
-- offering. The instant onReturnToSwing unanchors the root, taps go back to
-- meaning "walk" -- and by then all three branches below are already false.
-- ===== The two input sets, and why they are different sizes =====
--
-- PRESSING THE BOX is deliberately permissive: any mouse button, a touch tap,
-- or Space. It is a repeated action the player may be hammering, nothing is
-- lost by an extra one landing (the server rate-limits it regardless -- see
-- BOX_PRESS_COOLDOWN_SECONDS), and being generous about which button counts
-- costs nothing.
local POINTER_TRIGGER_MOUSE_TYPES = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.MouseButton2] = true,
	[Enum.UserInputType.MouseButton3] = true,
}

-- DISMISSING THE REVEAL is deliberately narrow: primary click or touch tap,
-- and nothing else. This action is destructive in a way the box press is not
-- -- it ends the sequence and teleports the player away -- and it is the one
-- thing standing between them and the reward they just earned, so it should
-- only fire on the gesture that unambiguously means "yes, continue".
--
-- Right and middle click are out because they are camera and utility buttons
-- a player may use while LOOKING at the slime. Space is out because it is the
-- key they were just pressing to open the box, which makes it exactly the
-- input most likely to arrive by momentum rather than intent -- the same
-- reason REVEAL_DISMISS_LOCKOUT_SECONDS exists at all.
local REVEAL_DISMISS_INPUT_TYPES = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.Touch] = true,
}

-- Space does double duty -- release the swing, or press the box -- and never
-- both at once, since boxActive and canRelease cannot be true together (see
-- resetReadyRemote's own guard). It does NOT dismiss the reveal.
UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	-- THE BUTTON EXCLUSION, for the box press as much as for the return.
	-- gameProcessedEvent is true exactly when the engine already routed this
	-- input to a GUI element -- a TextButton, a scrolling frame, anything
	-- Active -- so bailing here is what keeps "press anywhere" from also
	-- meaning "and also fire whatever button you actually aimed at". It is the
	-- engine's own hit test, not a list of rectangles this file has to keep in
	-- sync with four other scripts' layouts.
	--
	-- Belt and braces on top of it: the only two persistently-visible buttons
	-- in the game (ShopClient's SWING SHOP, InventoryClient's INVENTORY) are
	-- disabled outright for the whole box sequence -- see
	-- BOX_SUPPRESSED_HUD_NAMES -- and this file's own release/dismount buttons
	-- are already hidden by then. So during a box there is normally nothing on
	-- screen for this check to have to exclude; it is the guarantee, not the
	-- mechanism.
	--
	-- NOT true for ordinary movement taps on mobile: Roblox's touch controls
	-- consume those through their own bound action rather than through GUI hit
	-- testing, so they arrive here with gameProcessedEvent false -- which is
	-- what lets a tap anywhere on a phone press the box.
	if gameProcessedEvent then
		return
	end
	if input.KeyCode == Enum.KeyCode.Space then
		-- Presses the box or releases the swing -- but deliberately does NOT
		-- dismiss the reveal (see REVEAL_DISMISS_INPUT_TYPES). During a reveal
		-- this falls through to doRelease, which refuses outright (not
		-- mounted), so Space is simply inert while the slime is up.
		if boxActive then
			RewardScene.press()
		else
			doRelease()
		end
		return
	end

	local isPointerTrigger = POINTER_TRIGGER_MOUSE_TYPES[input.UserInputType]
		or input.UserInputType == Enum.UserInputType.Touch

	-- PRESS ANYWHERE. The ClickDetector on the box itself is still there and
	-- still works (see buildWorldBox); this is the fallback for every pixel
	-- that is not the box -- which matters because the box is only ~13% of the
	-- frame's width at the current camera distance, and on touch, aiming at it
	-- is a real ask.
	--
	-- MUTUALLY EXCLUSIVE WITH THE RETURN GESTURE BELOW, by construction rather
	-- than by ordering: this branch requires boxActive, the return branch
	-- requires `grounded`, and those two can never be true together. boxActive
	-- spans BoxStarted -> BoxResult(opened), and `grounded` is false from
	-- RidingAssigned until ResetReady, which the server only fires after the
	-- box has fully resolved (see LaunchServer's onBoxPress -> scheduleReset).
	-- The early `return` makes it belt-and-braces on top of that: a click
	-- during a box cannot fall through to the return check even if that
	-- invariant were ever broken. The server enforces the same thing
	-- independently -- onReturnToSwing rejects anything that is not
	-- states[player] == "grounded", and a boxing player is states[player] ==
	-- "box".
	if boxActive then
		if isPointerTrigger then
			RewardScene.press()
		end
		return
	end

	-- DISMISS THE REVEAL AND RETURN, in one action. This is the click the
	-- whole reward sequence ends on: the panel is the thing on screen, so the
	-- panel is the thing you click, and clicking it both clears it and sends
	-- you home. revealDismissable is false until the panel has been up for
	-- SlimeConfig.REVEAL_DISMISS_LOCKOUT_SECONDS, so a click still travelling
	-- down from the box press cannot skip it.
	--
	-- Ordered AFTER the box branch and BEFORE the grounded one, which is also
	-- the order these states occur in. It cannot collide with either:
	-- boxActive is already false by the time a reveal exists (BoxResult
	-- cleared it), and `grounded` is false on the client for the whole reveal
	-- because ResetReady is not fired until onReturnToSwing has actually moved
	-- the player -- i.e. until after this very click.
	if revealDismissable then
		-- Its OWN input set, not isPointerTrigger -- see
		-- REVEAL_DISMISS_INPUT_TYPES. Still returns unconditionally: a right
		-- click while the slime is up must be swallowed here rather than
		-- falling through to the backstop below, or it would return the player
		-- through a path that never meant to handle this case.
		if REVEAL_DISMISS_INPUT_TYPES[input.UserInputType] then
			dismissRevealAndReturn()
		end
		return
	end

	-- THE BACKSTOP, and only that now. Both real paths out of a landing are
	-- handled elsewhere -- the reward path by the branch above, the luckless
	-- path automatically server-side (see scheduleLucklessReturn) -- so a
	-- player who is grounded AND still frozen is in a state nothing should
	-- produce. Kept because if one ever did, a click is the difference between
	-- recovering and being stuck on the road forever. Silent by design: there
	-- is no prompt for it, because advertising it would put a floating hint
	-- back on the road for a case that should never happen.
	if not grounded then
		return
	end
	if isPointerTrigger and RewardScene.characterIsFrozen() then
		returnToSwingRemote:FireServer()
		-- BUG FIX (see the written report -- HUD elements persisting after
		-- return): this used to call refreshReturnAffordance() here, on the
		-- assumption that characterIsFrozen() would already read false by
		-- this point -- it never does: FireServer() doesn't yield, so this
		-- runs synchronously, before the server has even received the
		-- click, let alone unanchored the root. refreshReturnAffordance()
		-- therefore recomputed the exact same true it already had, and
		-- onReturnToSwing fires no remote back to the client, so nothing
		-- ever corrected it afterward either -- the hint stayed up until
		-- the player's NEXT setGrounded transition (their next mount).
	end
end)

-- FlightStarted: the server has already computed the FULL, final flight -- this
-- just frames the shot and starts rendering the countup/character. Nothing here
-- can change the outcome; it's rendering numbers the server already settled.
--
-- CAMERA: an INITIAL FRAMING, not a locked view. Roblox won't let you position
-- the default Custom camera directly -- while CameraType is Custom, the built-in
-- camera controller recalculates CFrame from the subject + player input every
-- frame and simply overwrites anything set from a script. The standard, widely-
-- used way around that (the same trick games use for a cutscene-into-gameplay
-- handoff): flip to Scriptable just long enough to set the one CFrame you want,
-- then flip straight back to Custom in the SAME tick, with no yield in between
-- -- no frame is ever rendered in the Scriptable state, so nothing is "locked."
-- Roblox's default camera controller doesn't snap back to some canned default
-- on taking over; it reads its starting distance/angle from wherever the camera
-- CFrame currently is, so it continues smoothly from the chase framing we just
-- set. From this point on we never touch camera.CFrame or CameraType again for
-- the rest of this flight -- normal mouse/touch camera input works immediately,
-- and the built-in controller keeps following the character on its own (the
-- character is repositioned every RenderStepped below, same as before, so
-- there's a fresh subject position for it to follow every frame).
--
-- THE OTHER CAMERA PATH (see the box camera block above): these two are the
-- only things in this file that write CameraType, and they cannot fight or
-- leave it in the wrong mode. Both END on Custom, unconditionally -- this one
-- within the same tick it flips to Scriptable, the box camera at the end of
-- its own eased return -- so neither can hand the other a Scriptable camera
-- to inherit. They also cannot overlap in the first place: a box only exists
-- from a landing until the reward sequence resolves, and reaching a
-- FlightStarted requires mounting first, which now tears down any box and
-- releases its camera through setGrounded(false) -> hideFlightBoxRevealUI.
-- Even if that ordering were ever broken, the failure would be cosmetic (one
-- path's CFrame writes losing to the other's) rather than a stuck Scriptable
-- camera, because neither leaves the mode set.
--
-- BUG FIX (see written report): u is now measured against startTime using
-- Workspace:GetServerTimeNow() (the same synced clock the swing already used),
-- not os.clock() from the moment this event happened to arrive. That's what
-- makes this client's u match the server's u at every instant regardless of how
-- long this message took to get here -- previously, a late-arriving message
-- meant this client's countup could still be short of the true distance when
-- the server's OWN (earlier-starting) timeline had already finished and told
-- the server to reset, occasionally letting a second release overwrite the
-- first flight's still-incomplete display (see doRelease's guard above too).
flightStartedRemote.OnClientEvent:Connect(function(distance: number, archHeight: number, duration: number, startPosition: Vector3, startTime: number, luck: number, multiplier: number)
	-- No longer "riding" the instant a flight starts -- see the `mounted`
	-- declaration above. The RenderStepped loop below is about to take over
	-- positioning this character from trajectoryCFrame instead, and once the
	-- flight ends the server puts this player back in "grounded" (via
	-- box/cooldown, see LaunchServer.server.luau), not straight back onto
	-- the seat -- so nothing should try to PivotTo them onto the seat again
	-- until a fresh RidingAssigned actually arrives. Also hides the DISMOUNT
	-- button -- there is nothing left to dismount FROM once a flight is
	-- already underway (the server's own onDismount would reject it too,
	-- see its own guard). flightHudFrame stays visible regardless -- see
	-- setGrounded -- `grounded` doesn't change here, only `mounted`.
	setMounted(false)
	flightDistance = distance
	flightArcHeight = archHeight
	flightDuration = duration
	flightStartPosition = startPosition
	flightStartTime = startTime
	flightLuck = luck
	flightActive = true

	-- ===== THE OUTCOME READOUT, FROM THE SERVER'S OWN NUMBER. Moved here from
	-- doRelease (see its comment, and REPORT.md): `multiplier` is the value
	-- LaunchServer graded this exact release at, not this client's prediction of
	-- it, so the word and the number can no longer claim a launch that did not
	-- happen. Nothing else about the timing changes -- this message is what
	-- starts the flight, so the word now lands on the same frame the character
	-- leaves the seat instead of a round trip earlier.
	--
	-- The ring is decided from the SERVER's origin and distance too (see
	-- landingBandZone), so all three parts of the readout -- word, number and
	-- ring -- now come from the same authoritative pair.
	local bandIndex, landingZone = landingBandZone(startPosition.Z, distance)
	local outcomeText: string
	local outcomeStyle: LaunchHud.OutcomeStyle
	local isRing = landingZone == "road" and bandIndex == #LuckCurve.VALUES - 1
	if isRing then
		outcomeText = LaunchConfig.LAST_BAND_OUTCOME_TEXT
		outcomeStyle = LaunchHud.LAST_BAND_OUTCOME_STYLE
	else
		local outcomeIndex = LaunchFormulas.outcomeBandIndex(multiplier)
		outcomeText = LaunchConfig.OUTCOME_BANDS[outcomeIndex].text
		outcomeStyle = LaunchHud.OUTCOME_STYLES[outcomeIndex]
	end
	-- ONLY A PERFECT GETS THE RAINBOW, and "perfect" is tested the same way the
	-- top OUTCOME_BANDS entry defines it -- the launch returned the SNAPPED
	-- value, at whatever threshold its own tier snaps at -- rather than by
	-- matching an index or a word. `not isRing` is belt and braces: a ring
	-- landing is graded below the snap by definition and so can never be a
	-- perfect, but the two are decided by different things (a band, a
	-- multiplier) and this keeps them from ever both being true.
	local isPerfect = not isRing and multiplier >= LaunchConfig.SWEET_SPOT_MULTIPLIER
	Hud.setOutcome(outcomeText, outcomeStyle, multiplier, isPerfect)
	-- And the bar's own number, which doRelease froze a moment ago at this
	-- client's predicted value -- corrected to the real one so the two readouts
	-- on screen cannot disagree. The bar INDICATOR is deliberately left where it
	-- was: its position is the record of where this player released, which is
	-- the one thing the server's copy cannot tell them.
	Hud.setMultiplierReadout(multiplier)

	-- Where the camera stands for this flight, computed ONCE and not re-adjusted
	-- mid-flight. NO LONGER READS archHeight -- see
	-- LaunchFormulas.releaseCameraPullback for why the arc must not move the
	-- camera and how the cap is derived from the map's own back edge.
	local cameraBehindOffset = LaunchFormulas.releaseCameraPullback(startPosition.Z, distance)

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = LaunchFormulas.chaseCameraCFrame(startPosition, cameraBehindOffset)
	camera.CameraType = Enum.CameraType.Custom
end)

-- BUG FIX (see the written report -- mid-flight death): this remote now has
-- TWO callers server-side, not one -- a normal landing (LaunchServer.
-- server.luau's scheduleReset, unchanged) AND a death/disconnect
-- cancellation (clearActiveRider, newly added) -- so everything in this
-- handler must be safe to run with no flight or box ever having been in
-- progress. It already was: setGrounded(true) unconditionally calls
-- hideFlightBoxRevealUI regardless of whether a box was actually up (see
-- its own comment), and resetFlightState/resetFlightHudText below just
-- assign fixed reset values, which is a no-op when those variables/labels
-- are already at that value -- nothing here reads or depends on a flight
-- having actually completed. Also naturally idempotent for the same
-- reason, which matters because clearActiveRider's own new fire CAN land
-- alongside an already-scheduled landing fire for the same player (see the
-- written report's double-fire trace) -- a second run of this handler just
-- re-applies the same reset values, not a problem to guard against.
resetReadyRemote.OnClientEvent:Connect(function()
	canRelease = true
	resetFlightState()
	-- The reward sequence (landing, box, reveal) has fully resolved -- the
	-- player is grounded again, right where they landed (see the written
	-- report: the return is no longer automatic). Shows the click-anywhere
	-- hint and re-arms the listener above. setGrounded(true) itself now also
	-- tears down the whole reward scene -- box, slime, camera, character
	-- visibility, suppressed HUDs (see hideFlightBoxRevealUI) --
	-- this used to be inlined here as a defensive backstop specific to this
	-- one handler; centralising it means every OTHER path back to "grounded"
	-- (a fresh/respawned CharacterAdded, Dismounted) gets the exact same
	-- guarantee, not just this one.
	setGrounded(true)
	Hud.resetFlightHudText()
end)

-- BoxStarted: fired once per landing that earned luck > 0 (see LaunchServer's
-- Heartbeat landing handler) -- a 0-luck landing never fires this, so the box
-- simply never appears for a whiff (see the written report).
boxStartedRemote.OnClientEvent:Connect(function(luck: number)
	setBoxActive(true)
	-- The wider flag, which does NOT come back down when the box opens -- it
	-- keeps the flight HUD off through the thrash, the burst and the whole
	-- slime reveal, until hideFlightBoxRevealUI clears it at ResetReady.
	setRewardSequenceActive(true)
	-- Builds the cube in front of this player's own frozen character and
	-- stamps the landing's earned luck onto it -- see showWorldBox. There is
	-- no "press to open" status line any more: the box is a box with a "?" on
	-- it, standing at arm's length, and clicking it is the only thing there is
	-- to do at the landing spot.
	RewardScene.showBox(luck)
end)

-- BoxResult: the server's answer to exactly one press, now arriving on the
-- same frame the press was sent -- the roll is synchronous inside onBoxPress
-- and no longer sits behind a delay (see BOX_PRESS_COOLDOWN_SECONDS for what
-- became of the old one). So in practice this lands while the press's own
-- nudge is still playing.
--
-- A double (opened = false) reads as ESCALATION: the box SURVIVES, and it
-- takes NO NEW MOTION to say so. The nudge doBoxPress already started is the
-- whole animation -- the box was knocked and it held -- and the luck number
-- floating above it climbs to the new value in a hot, energetic colour. It
-- stays standing there and stays pressable throughout (boxActive was never
-- cleared on this branch).
--
-- An open (opened = true) reads as DESTRUCTION, and this is the only place in
-- the whole sequence that starts the violent motion: the box thrashes for
-- BOX_THRASH_SECONDS and then bursts. Distinguishable from a single frame with
-- no motion history at all -- one branch has a box quietly sitting there, the
-- other has one coming apart.
boxResultRemote.OnClientEvent:Connect(function(opened: boolean, luck: number)
	if opened then
		setBoxActive(false)
		-- Recolours the luck readout and starts the thrash -- both inside
		-- markBoxOpened, so the box's own colours stay private to the scene.
		--
		-- Overrides the press's own nudge mid-decay. The discontinuity is one
		-- frame at BOX_NUDGE_AMPLITUDE_STUDS (0.12 studs, a fraction of the
		-- hover's own travel) dropping to the thrash's own ramp starting at
		-- zero -- far below what is visible at this camera distance, and worth
		-- it for a thrash that unambiguously starts from stillness and builds.
		--
		-- The thrash chains into the burst itself when it finishes (see
		-- updateBoxMotion) rather than being scheduled here, so the pair stays
		-- one continuous event. Their combined length is checked against
		-- REVEAL_BOX_TO_SLIME_DELAY_SECONDS -- see the motion block's header.
		RewardScene.markBoxOpened(luck)
	else
		RewardScene.markBoxDoubled(luck)
		-- Deliberately no startBoxMotion call: the nudge is already running and
		-- IS the fail's animation. Starting anything here would make the
		-- common outcome the loud one again, which is the whole thing this
		-- retune set out to fix.
	end
end)

-- SlimeRevealed: THE SECOND beat -- arrives REVEAL_BOX_TO_SLIME_DELAY_SECONDS
-- after BoxResult(opened=true) (see LaunchServer's onBoxPress), which is just
-- after the burst has finished destroying the box. The slime takes the box's
-- exact place, on the box's exact camera.
--
-- THE CAMERA DOES NOT MOVE FOR ANY OF THIS. It was acquired when the box
-- appeared and is not released until the player dismisses the reveal (see
-- endRewardScene's two callers) -- so the burst, the slime rising out of it
-- and the whole time spent reading the name are one continuous shot with no
-- second transition anywhere in it.
--
-- THE SLIME HAS NO TIMER. It stands there for as long as the player wants to
-- look at it, and ONE primary click or tap dismisses it AND returns them, in
-- the same action -- see dismissRevealAndReturn.
-- ChestRevealStarted: arrives immediately BEFORE SlimeRevealed, and only for a
-- treasure chest. All it does is arm the anchor the reveal is about to read --
-- there is no camera take, no character hiding and no HUD suppression here,
-- deliberately: the player walked to this chest and is standing in control,
-- and taking any of that away at the moment they arrive would undo the one
-- thing that makes this reward different from the box (see REPORT.md).
--
-- Everything armed here is released in endRewardScene, the same single point
-- that already releases the box, the camera and the character.
chestRevealRemote.OnClientEvent:Connect(function(anchor: CFrame, toward: Vector3)
	-- Arms the anchor AND this reveal's own rise and duration -- all four
	-- assignments moved into the scene module together, since that is where the
	-- reveal reads them. See LaunchRewardScene.armChestReveal.
	RewardScene.armChestReveal(anchor, toward)
end)

slimeRevealedRemote.OnClientEvent:Connect(function(globalIndex: number, isNew: boolean)
	local slime = SlimeData.SLIMES[globalIndex]
	if not slime then
		return
	end
	-- Normally already gone: the burst destroys the box after
	-- BOX_OPEN_BURST_SECONDS (0.3), and this fires at 0.6. Kept as the
	-- structural guarantee that the box and the slime can never share the
	-- spot even if either number is retuned past the other -- destroyWorldBox
	-- is a no-op on an already-destroyed box, and deliberately NOT
	-- endRewardScene here, which would release the camera mid-reveal.
	RewardScene.destroyBox()

	-- Up, but NOT yet dismissable, and saying so by staying quiet: there is no
	-- prompt until the lockout below expires, so nothing ever promises a click
	-- that would currently be swallowed.
	revealDismissable = false
	RewardScene.showSlime(slime, isNew)

	-- THE LOCKOUT (see SlimeConfig.REVEAL_DISMISS_LOCKOUT_SECONDS): the player
	-- has just been clicking to press the box and this lands 0.6s after it
	-- opened, so a click may already be on its way down. Ignoring input for a
	-- beat is what stops the reveal being skipped before it is seen.
	--
	-- Re-checks the slime it armed for is still the one standing there: a
	-- death, respawn or dismount inside the lockout tears the reveal down
	-- (endRewardScene), and this timer must not then arm a dismiss branch for
	-- a slime that is gone. Identity, not mere presence -- a second landing
	-- resolving this fast would be a DIFFERENT model, and arming for it here
	-- would skip its own lockout.
	local armedModel = RewardScene.revealModel()
	task.delay(SlimeConfig.REVEAL_DISMISS_LOCKOUT_SECONDS, function()
		if RewardScene.revealModel() ~= armedModel or not armedModel then
			return
		end
		revealDismissable = true
	end)
end)

ridingAssignedRemote.OnClientEvent:Connect(function()
	-- The server just auto-mounted THIS client's character onto its own
	-- swing seat (see LaunchServer.server.luau's mountPlayer -- automatic
	-- proximity mounting, no button/prompt/keypress involved). This is the
	-- one and only place `mounted` is set true -- see its declaration above
	-- for every place it goes false again. Also shows the DISMOUNT button.
	setMounted(true)
	-- No longer grounded -- hides the click-anywhere hint, disarms the
	-- return listener, and shows the rest of the flight HUD (distance/
	-- multiplier/bar/release button) for the duration of the ride/flight/box
	-- sequence -- see setGrounded.
	setGrounded(false)

	-- Ack readiness -- see LaunchServer.server.luau's mountPlayer watchdog.
	-- Reaching this line at all already proves every WaitForChild gate above
	-- succeeded and this script is listening/about to drive the character
	-- every RenderStepped, which is exactly what the server is asking about.
	riderReadyRemote:FireServer()
end)

-- Dismounted: the server just moved THIS client's character off the swing
-- via the DISMOUNT button (see LaunchServer.server.luau's onDismount) --
-- the ONLY thing that ever clears `mounted` outside of FlightStarted/
-- CharacterAdded. REQUIRED, not optional (see the written report -- dismount
-- investigation, round 2): without an explicit signal, `mounted` stayed
-- true after a dismount, so the RenderStepped loop below kept PivotTo'ing
-- the character back onto the seat's still-swinging position every single
-- frame -- the server's own teleport won for one Heartbeat and then
-- instantly lost to the very next RenderStepped, which is exactly what
-- made the button look like it did nothing. Same two calls RidingAssigned's
-- own handler makes, just the reverse direction -- no longer mounted, and
-- grounded again (shows the return hint, re-arms the click-anywhere
-- listener, shows the rest of the flight HUD as hidden), matching exactly
-- what a normal post-landing return already does.
dismountedRemote.OnClientEvent:Connect(function()
	setMounted(false)
	setGrounded(true)
end)

-- BUG FIX (real cause of the flight stutter, see the written report): a plain
-- RunService.RenderStepped:Connect() is DOCUMENTED by Roblox to run at
-- Enum.RenderPriority.Last -- i.e. AFTER the engine's own built-in camera
-- update (which runs at Enum.RenderPriority.Camera, well before Last), every
-- single frame. Since FlightStarted hands the camera back to Roblox's normal
-- Custom-type follow behaviour (see below) and never touches camera.CFrame
-- again, that built-in update reads the character's position ONCE per frame,
-- at Camera priority -- which, under a plain :Connect(), was always the
-- PREVIOUS frame's position: this script's own PivotTo (moving the character
-- to THIS frame's position) didn't run until Last, strictly after the camera
-- had already looked. Both character and camera were per-frame and
-- client-side, exactly as the earlier jitter fix intended, but with an
-- undeclared one-frame ordering gap between them on every single frame --
-- invisible while riding at normal walking-scale motion, but readable as
-- stutter during flight, where a single frame of lag is a large,
-- speed-proportional position gap (tens of studs at these flight speeds).
-- BindToRenderStep with an explicit priority BEFORE Camera guarantees this
-- script's PivotTo (and the swing seat's CFrame) always lands before the
-- built-in camera reads the character that same frame, closing the gap
-- entirely instead of relying on both sides happening to be "per frame."
local RENDER_STEP_NAME = "LaunchClientSwingAndFlightUpdate"
RunService:BindToRenderStep(RENDER_STEP_NAME, Enum.RenderPriority.Camera.Value - 1, function()
	-- THE PERFECT TEXT'S RAINBOW SWEEP, on the HUD's existing render loop rather
	-- than a connection of its own -- see LaunchHud's updateOutcomeRainbow. It
	-- sits FIRST, ahead of every early return below, because those returns are
	-- about riding and flying and this is about a label that stays on screen
	-- through all of those states and past the landing. When no perfect is up it
	-- is a single boolean test.
	--
	-- Chosen over the other two connections in this client deliberately: the
	-- reward scene's RenderStepped belongs to LaunchRewardScene and calling into
	-- the HUD from there would cross a module boundary, and LaunchRemoteLanes'
	-- is about other players entirely. This loop is already the one that drives
	-- this client's own HUD (renderBarForPhase, at the bottom).
	Hud.updateOutcomeRainbow()

	-- Cheap (a couple of .Parent checks) every frame; only ever actually
	-- re-fetches anything in the rare frame right after a tier purchase
	-- rebuilds the structure -- see ensureSwingReferences's own comment.
	ensureSwingReferences()

	local phase = LaunchFormulas.swingPhase(ownLaneIndex)

	-- The swing itself always swings, for every viewer, whether or not anyone
	-- is riding it right now -- matches "it just swings, forever" regardless of
	-- a rider. Every connected client computes and shows this identically; it's
	-- cheap, pure math, no reason to gate it to just the rider's own client.
	local theta = LaunchFormulas.swingTheta(phase)
	local seatPosition = swingSeatPosition(theta)
	-- :PivotTo, not .CFrame -- the seat is a Model (see SwingBuilder.luau,
	-- PrimaryPart = SeatCore) even though every tier now builds the exact
	-- same single flat-plank SeatCore, so a future seat addition can still
	-- move rigidly as one unit without this call site changing, same
	-- mechanism the character itself already uses.
	swingSeatModel:PivotTo(CFrame.new(seatPosition) * CFrame.Angles(theta, 0, 0))
	repositionChainLinks()

	-- BUG FIX (see written report): this used to be the SERVER repositioning the
	-- rider every Heartbeat and replicating the result -- arriving at whatever
	-- rate Roblox batches property replication (well under 60Hz), which read as
	-- stutter. Now this client positions its OWN character locally, every
	-- RenderStepped, from the exact same swing math -- full render-rate
	-- smoothness, no network dependency.
	--
	-- AUTOMATIC PROXIMITY MOUNTING (see the written report): gated on
	-- `mounted` now, not `canRelease` -- canRelease alone used to double as
	-- "am I riding" because riding WAS the default/rest state, but that's no
	-- longer true (the default/rest state is grounded, driven by the normal
	-- Humanoid controller, never PivotTo). `mounted` is the explicit local
	-- flag for exactly this: true only from this client's own RidingAssigned
	-- until its own flight starts (see `mounted`'s declaration above) --
	-- while false, this character is NEVER PivotTo'd here, so a grounded
	-- player (including the whole post-landing box/cooldown window, and
	-- every moment before ever mounting for the first time) is driven
	-- entirely by ordinary walking.
	if mounted and not flightActive then
		local character = player.Character
		if character then
			character:PivotTo(LaunchFormulas.riderCFrame(seatPosition))
		end
	end

	if flightActive then
		local u = math.clamp((Workspace:GetServerTimeNow() - flightStartTime) / flightDuration, 0, 1)

		-- BUG FIX (jitter, see written report): the character used to be
		-- positioned server-side, every Heartbeat, then replicated -- at a rate
		-- well under render rate, which is what read as jitter once the camera
		-- was looking directly at it. Positioned here every RenderStepped
		-- instead. The camera is NO LONGER driven here at all (see FlightStarted
		-- above) -- it was given its initial framing once, at release, then
		-- handed back to the player as a normal Custom camera, which follows
		-- this same PivotTo'd position on its own from here on.
		local character = player.Character
		if character then
			character:PivotTo(LaunchFormulas.trajectoryCFrame(flightStartPosition, flightDistance, flightArcHeight, u))
		end

		if u >= 1 then
			-- Landed: swap the live countup for the final result. LUCK is the
			-- headline now (see the written report -- the player launches for
			-- luck, not studs), distance demoted to the small sub-readout below
			-- it. Server already computed luck at release from the same landing
			-- Z the character is now standing at (see LaunchServer's
			-- bandLuckForLandingZ) -- this is purely display, nothing here can
			-- change or re-derive the value. Held on screen for the rest of
			-- RESET_DELAY (unchanged), same as before.
			--
			-- THE ZONE GOES WITH IT (see REPORT.md). Luck alone cannot describe a
			-- landing: a flight that cleared the road carries luck 0 BY DESIGN
			-- (bandLuckForLandingZ's "past" branch -- a chest landing earns no
			-- luck), and reading only `luck > 0` is what made the best outcome in
			-- the game announce itself as "No luck (short of the road)". Derived
			-- from the server's own origin and distance, the same pair the ring
			-- word uses, so the headline branches on exactly the enum the server
			-- itself branched on when it chose the chest.
			local _, landingZone = landingBandZone(flightStartPosition.Z, flightDistance)
			Hud.showLandingResult(flightLuck, flightDistance, landingZone)
			if landingZone == "past" then
				-- THE CHEST PATH'S MISSING REWARD-SEQUENCE SIGNAL (see REPORT.md).
				-- The flight HUD is gated on `not grounded and not
				-- rewardSequenceActive`, and rewardSequenceActive had exactly one
				-- writer: the BoxStarted handler. A chest landing never fires
				-- BoxStarted -- the server goes straight to states = "chest" -- so
				-- the flag stayed false, `grounded` stayed false until ResetReady
				-- at the very end, and the readout for a launch that was already
				-- over sat on screen through the walk, the open and the reveal.
				--
				-- The box learns its sequence has begun from a remote; this path
				-- learns it from the landing it just computed one line above. Same
				-- flag, same single owner (setRewardSequenceActive), and cleared by
				-- the same hideFlightBoxRevealUI every route back to "grounded"
				-- already funnels through -- the chest's return, its abandon timer,
				-- a death and a dismount all reach it.
				--
				-- ONLY "past". A luckless landing is "short" or "road" and keeps
				-- its HUD for RESET_DELAY exactly as before; a box landing is
				-- "road" and is still driven entirely by BoxStarted.
				setRewardSequenceActive(true)
			end
			flightActive = false
			return
		end

		-- Count the distance UP live -- horizontal progress is exactly linear in
		-- u for this trajectory, so this number always matches exactly how far
		-- along the flight the character visibly is, not a decoupled animation.
		Hud.setLiveDistance(flightDistance * u)
		return
	end

	-- Bar/multiplier HUD is riding-only now, same as the character-positioning
	-- gate above -- a grounded player walking to their base/the shop has
	-- nothing to release, so there's nothing useful for this readout to show.
	if not mounted or not canRelease then
		return
	end
	Hud.renderBarForPhase(phase, ownSwingTier)
end)

-- ===== Six-lane rendering (frozen remote players -- see the written report)
-- =====
-- Everything above this point renders exactly ONE lane -- this client's own,
-- resolved once from player.UserId -- and never touches the other five
-- SwingPivot_*/SwingStructure_* pairs LaunchServer.server.luau also builds.
-- That was fine for the seat's own sway (nobody was watching it) but meant
-- every OTHER connected player's swing sat dead still, and every other
-- player's own character never moved while riding or flying, since ALL
-- per-frame positioning was (deliberately, see the loop above) local-only.
--
-- THE FIX, SAME SHAPE AS THE LOCAL LOOP: swingTheta/swingSeatPosition/
-- riderCFrame/trajectoryCFrame are all pure functions of shared config, an
-- explicit pivot's own (replicated) Position, and Workspace:GetServerTimeNow()
-- -- there is nothing server-only about any of that math. LaunchServer.
-- server.luau now ALSO writes a RiderState attribute ("empty" | "riding" |
-- "flying" | "landed") on each player's own pivot, plus (only while flying)
-- the five FlightStartTime/FlightStartPos/FlightDistance/FlightArcHeight/
-- FlightDuration attributes -- see its own mountPlayer/onRelease/Heartbeat
-- landing handler/moveToLaneReturn/clearActiveRider comments for exactly
-- where each is written. Every one of those is an ordinary attribute on an
-- ordinary Workspace instance -- already replicated, like LaneIndex always
-- was -- so this needs no new remote and adds no per-frame server work.
--
-- DELIBERATELY A SEPARATE CONNECTION, not a rewrite of the loop above: the
-- local player's own render path (this client's own seat, its own riding/
-- flight positioning) is untouched, byte-for-byte, by anything below this
-- line -- see the written report on why that guarantee mattered enough to
-- keep the two loops structurally apart rather than merging them.
RunService.RenderStepped:Connect(LaunchRemoteLanes.render)
