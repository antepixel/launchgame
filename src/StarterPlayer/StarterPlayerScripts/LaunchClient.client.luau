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
local LaneConfig = require(ReplicatedStorage.Config.LaneConfig)

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

-- Mirrors LaunchServer's swingPhase()/swingTheta() exactly -- same shared
-- constants, same clock, same per-lane offset formula (six-lane pass 2).
-- Kept in this one script rather than a shared module since it's a handful
-- of small pure functions and this project keeps ONE tuning module, not a
-- library of shared math helpers. Every call site below passes ownLaneIndex
-- -- see its own comment above for how that's guaranteed to match the
-- server's copy.
local function swingPhase(laneIndex: number): number
	local t = Workspace:GetServerTimeNow()
	local offset = laneIndex * (LaunchConfig.SWING_PERIOD_SECONDS / LaneConfig.LANE_COUNT)
	return ((t + offset) % LaunchConfig.SWING_PERIOD_SECONDS) / LaunchConfig.SWING_PERIOD_SECONDS
end

local function swingTheta(phase: number): number
	local arc = math.rad(LaunchConfig.SWING_ARC_HALF_ANGLE_DEGREES)
	return arc * math.sin(2 * math.pi * phase)
end

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
					local reference = if math.abs(yAxis.Y) > 0.9 then Vector3.new(1, 0, 0) else Vector3.new(0, 1, 0)
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
	repositionChainSide(leftLinks, swingChainAnchorLeft.Position, leftAttachment.WorldPosition)
	repositionChainSide(rightLinks, swingChainAnchorRight.Position, rightAttachment.WorldPosition)
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

-- Styling for each OUTCOME_BANDS entry, same order/length (5) -- a perfect
-- reads as a celebration (biggest, boldest, gold), a miss reads as flat (small,
-- muted, regular weight, no bold) per the written report: this game is
-- launched hundreds of times, so the low end has to stay gentle, not harsh.
local OUTCOME_STYLES: { { color: Color3, size: UDim2, font: Enum.Font, strokeTransparency: number } } = {
	{ color = Color3.new(1, 0.85, 0.25), size = UDim2.new(0, 320, 0, 46), font = Enum.Font.GothamBlack, strokeTransparency = 0.2 }, -- Perfect!
	{ color = Color3.new(0.4, 1, 0.5), size = UDim2.new(0, 300, 0, 38), font = Enum.Font.GothamBold, strokeTransparency = 0.35 }, -- Great!
	{ color = Color3.new(0.85, 0.85, 1), size = UDim2.new(0, 280, 0, 32), font = Enum.Font.GothamBold, strokeTransparency = 0.5 }, -- Good
	{ color = Color3.new(0.75, 0.75, 0.8), size = UDim2.new(0, 260, 0, 28), font = Enum.Font.GothamBold, strokeTransparency = 0.5 }, -- Okay
	{ color = Color3.new(0.55, 0.55, 0.6), size = UDim2.new(0, 240, 0, 24), font = Enum.Font.Gotham, strokeTransparency = 0.6 }, -- Lock in..
}

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

-- ===== Flight/countup state (set once per flight by FlightStarted) =====
local flightActive = false
local flightStartTime = 0
local flightDuration = 0
local flightDistance = 0
local flightArcHeight = 0
local flightStartPosition = Vector3.zero
local flightLuck = 0

-- ===== Mystery box state (set by BoxStarted, driven by BoxResult) =====
-- boxActive gates whether Space/the box button do anything -- true from
-- BoxStarted until the box opens (BoxResult with opened = true) or a reset
-- wipes it defensively (see resetReadyRemote below). boxWaitingForResult is a
-- LOCAL-only "already pressed, waiting" latch -- purely for not sending a
-- pointless second FireServer while one is in flight; the server's own
-- `pending` guard (see LaunchServer's onBoxPress) is what actually enforces
-- this, so a modified client skipping this latch gains nothing.
local boxActive = false
local boxWaitingForResult = false

-- ===== UI =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LaunchHud"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- Groups every element that only means something while THIS client is
-- riding, flying, or in the box sequence -- the distance readout, the
-- multiplier/bar, the outcome text, and the release button -- behind ONE
-- Visible flip instead of six independent ones (see setGrounded below, the
-- single place this toggles). A plain full-screen, invisible-background
-- Frame, not the ScreenGui itself: returnHintLabel (and the money/tier
-- labels BaseClient.client.luau owns) must stay independently controllable,
-- so the whole LaunchHud ScreenGui can never be the thing toggled here.
-- Sized/positioned to exactly cover the ScreenGui so every child's existing
-- UDim2 (all written relative to the full screen) renders identically
-- whether parented here or directly to screenGui -- reparenting below is
-- purely an organisational change, not a layout one.
--
-- BUG FIX (see the written report -- dismount button not responding): this
-- is a pure grouping container, never meant to be interacted with directly
-- -- only its children (the release button) are. Active is left at its
-- default here for every OTHER label, but a Frame this large (the whole
-- screen) sitting as a SIBLING of dismountButton, both visible at the same
-- time ("riding"), made their relative click-hit priority depend on
-- sibling order Roblox does not actually guarantee -- which is exactly the
-- kind of thing that can silently swallow a click with no error and no
-- visible effect, matching "pressing Dismount does nothing" exactly.
-- Active = false removes the ambiguity outright: this frame can now never
-- capture a click meant for anything else, regardless of sibling order,
-- while its own children (releaseButton) keep receiving their own clicks
-- completely independently of their parent's Active value.
local flightHudFrame = Instance.new("Frame")
flightHudFrame.Name = "FlightHud"
flightHudFrame.Active = false
flightHudFrame.BackgroundTransparency = 1
flightHudFrame.Size = UDim2.fromScale(1, 1)
flightHudFrame.Visible = false
flightHudFrame.Parent = screenGui

local distanceLabel = Instance.new("TextLabel")
distanceLabel.Name = "DistanceReadout"
distanceLabel.AnchorPoint = Vector2.new(0.5, 0)
distanceLabel.Position = UDim2.new(0.5, 0, 0.05, 0)
distanceLabel.Size = UDim2.new(0, 400, 0, 60)
distanceLabel.BackgroundTransparency = 1
distanceLabel.Font = Enum.Font.GothamBold
distanceLabel.TextScaled = true
distanceLabel.TextColor3 = Color3.new(1, 1, 1)
distanceLabel.TextStrokeTransparency = 0.4
distanceLabel.Text = "Time your release!"
distanceLabel.Parent = flightHudFrame

-- The bar track: a fixed vertical strip. The moving indicator's Y POSITION inside
-- it (not its size) is the swing position -- "the bar IS the swing position."
-- LEFT side of the screen, vertically centred (mirrored from its old right-
-- side spot -- see the written report): the DISMOUNT button now takes the
-- middle of the right-hand side instead (see dismountButton below).
local barTrack = Instance.new("Frame")
barTrack.Name = "SwingBarTrack"
barTrack.AnchorPoint = Vector2.new(0, 0.5)
barTrack.Position = UDim2.new(0.03, 0, 0.5, 0)
barTrack.Size = UDim2.new(0, 36, 0, 360)
barTrack.BackgroundColor3 = Color3.new(0.1, 0.1, 0.1)
barTrack.BackgroundTransparency = 0.25
barTrack.BorderSizePixel = 0
barTrack.Parent = flightHudFrame

local barTrackCorner = Instance.new("UICorner")
barTrackCorner.CornerRadius = UDim.new(0, 8)
barTrackCorner.Parent = barTrack

-- A thin rim so the track reads as a distinct object at a glance instead of a
-- flat rectangle, even before the sweet-spot band draws the eye. Subtle by
-- design -- this is polish, not a second signal competing with the indicator.
local barTrackStroke = Instance.new("UIStroke")
barTrackStroke.Name = "TrackRim"
barTrackStroke.Color = Color3.new(1, 1, 1)
barTrackStroke.Transparency = 0.85
barTrackStroke.Thickness = 1.5
barTrackStroke.Parent = barTrack

-- Sweet-spot band: a static highlight at the TOP of the track (fill = 1 is the
-- forward extreme of the arc -- see LaunchConfig.SWEET_SPOT_PHASE). Its height is
-- computed from SWEET_SPOT_WIDTH using the same sine relationship as the server's
-- circularPhaseDistance check, so it visually represents the actual accepted
-- window, not an approximation of it. The vertical gradient across it mirrors
-- the actual grading curve (see LaunchConfig.SWEET_SPOT_EDGE_MULTIPLIER/
-- SWEET_SPOT_MULTIPLIER) instead of just being decoration: brightest at the top
-- of the band (dead centre, the 2.0x peak) fading to dimmer at the bottom (the
-- window's edges, 1.8x) -- so the band ITSELF shows where the grading is
-- heading, not just where the window is.
do
	local halfWidth = LaunchConfig.SWEET_SPOT_WIDTH / 2
	-- fillFraction is symmetric around its peak (phase 0.25), so the fill value at
	-- EITHER edge of the sweet-spot window is the same: cos(2*pi*halfWidth) mapped
	-- into [0,1] the same way fillFraction does.
	local edgeFill = (math.cos(2 * math.pi * halfWidth) + 1) / 2
	local bandHeightFraction = 1 - edgeFill

	-- fill = 1 is the TOP of the track (Y scale 0, per barIndicator's own
	-- convention below), so the band anchors to the top edge and extends downward.
	local sweetBand = Instance.new("Frame")
	sweetBand.Name = "SweetSpotBand"
	sweetBand.AnchorPoint = Vector2.new(0.5, 0)
	sweetBand.Position = UDim2.new(0.5, 0, 0, 0)
	sweetBand.Size = UDim2.new(1, 0, bandHeightFraction, 0)
	sweetBand.BackgroundColor3 = Color3.new(0.2, 1, 0.35)
	sweetBand.BackgroundTransparency = 0.3
	sweetBand.BorderSizePixel = 0
	sweetBand.ZIndex = 2
	sweetBand.Parent = barTrack

	local sweetBandCorner = Instance.new("UICorner")
	sweetBandCorner.CornerRadius = UDim.new(0, 8)
	sweetBandCorner.Parent = sweetBand

	-- Rotation 90 turns the gradient vertical, offset 0 at the top of the frame.
	local sweetBandGradient = Instance.new("UIGradient")
	sweetBandGradient.Rotation = 90
	sweetBandGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(0.6, 1, 0.65)),
		ColorSequenceKeypoint.new(1, Color3.new(0.1, 0.55, 0.25)),
	})
	sweetBandGradient.Parent = sweetBand

	-- A crisp edge on the band is what sells the 1.5->1.8 jump visually: the
	-- moment the indicator crosses this line, it's a hard boundary, not a fade.
	local sweetBandStroke = Instance.new("UIStroke")
	sweetBandStroke.Color = Color3.new(0.6, 1, 0.65)
	sweetBandStroke.Transparency = 0.4
	sweetBandStroke.Thickness = 1.5
	sweetBandStroke.Parent = sweetBand
end

local barIndicator = Instance.new("Frame")
barIndicator.Name = "SwingBarIndicator"
barIndicator.AnchorPoint = Vector2.new(0.5, 0.5)
barIndicator.Position = UDim2.new(0.5, 0, 1, 0)
barIndicator.Size = UDim2.new(1, 8, 0, 10)
barIndicator.BackgroundColor3 = Color3.new(1, 1, 1)
barIndicator.BorderSizePixel = 0
barIndicator.ZIndex = 3
barIndicator.Parent = barTrack

local barIndicatorCorner = Instance.new("UICorner")
barIndicatorCorner.CornerRadius = UDim.new(0, 5)
barIndicatorCorner.Parent = barIndicator

-- Invisible outside the sweet spot, a bright gold glow the instant the indicator
-- is inside it (set every frame below, alongside its size/color) -- this is the
-- "at a glance, without reading" signal item 6 asks for: a distinct pop that
-- doesn't depend on noticing a number change.
local barIndicatorGlow = Instance.new("UIStroke")
barIndicatorGlow.Name = "HitGlow"
barIndicatorGlow.Thickness = 3
barIndicatorGlow.Color = Color3.new(1, 0.85, 0.25)
barIndicatorGlow.Transparency = 1
barIndicatorGlow.Parent = barIndicator

-- Live multiplier readout, right above the bar. Updated every frame alongside
-- the indicator (same RenderStepped loop below) -- normal styling for the
-- gradual-ramp range, a distinct brighter look when in the sweet spot. Reads as
-- a smoothly climbing/falling number now (grading removed the flat "2x!" snap
-- text) -- the hit/miss signal lives in the bar, not in this label freezing.
-- Mirrored to sit right above the bar's own NEW left-side spot (see
-- barTrack above).
local multiplierLabel = Instance.new("TextLabel")
multiplierLabel.Name = "MultiplierReadout"
multiplierLabel.AnchorPoint = Vector2.new(0, 1)
multiplierLabel.Position = UDim2.new(0.03, 0, 0.5, -190)
multiplierLabel.Size = UDim2.new(0, 120, 0, 40)
multiplierLabel.BackgroundTransparency = 1
multiplierLabel.Font = Enum.Font.GothamBold
multiplierLabel.TextScaled = true
multiplierLabel.TextColor3 = Color3.new(1, 1, 1)
multiplierLabel.TextStrokeTransparency = 0.4
multiplierLabel.Text = "0.75x"
multiplierLabel.Parent = flightHudFrame

-- Outcome readout: the short result word (see LaunchConfig.OUTCOME_BANDS),
-- set once per release, in doRelease below, from the same phase the release
-- itself fires on -- this IS the feedback, meant to read instantly without
-- parsing a number, styled per band (OUTCOME_STYLES above) so a perfect looks
-- like a celebration and a miss looks flat. Left up through the whole flight
-- and beyond (nothing clears it until the NEXT release overwrites it), so it
-- also works as a "how did I just do" readout while lining up the next swing,
-- not just an instant flash at release. Stacked directly under the distance
-- readout (same horizontal centre, not a separate corner) so its size
-- changing per band can't overlap that label on a narrow phone screen, where
-- the distance readout's fixed 400px width already spans most of the width.
local outcomeLabel = Instance.new("TextLabel")
outcomeLabel.Name = "OutcomeReadout"
outcomeLabel.AnchorPoint = Vector2.new(0.5, 0)
outcomeLabel.Position = UDim2.new(0.5, 0, 0.05, 64)
outcomeLabel.Size = UDim2.new(0, 260, 0, 28)
outcomeLabel.BackgroundTransparency = 1
outcomeLabel.Font = Enum.Font.GothamBold
outcomeLabel.TextScaled = true
outcomeLabel.TextColor3 = Color3.new(0.75, 0.75, 0.8)
outcomeLabel.TextStrokeTransparency = 0.5
outcomeLabel.Text = ""
outcomeLabel.Parent = flightHudFrame

-- Distance sub-readout: small and muted on purpose -- the player launches for
-- luck, not studs, so luck gets the big primary line (see distanceLabel's
-- landed-text below) and distance is demoted to this quiet footnote instead of
-- being the headline. Positioned below the outcome label's tallest ("Perfect!")
-- size so it never gets covered as that label grows/shrinks per band.
local distanceSubLabel = Instance.new("TextLabel")
distanceSubLabel.Name = "DistanceSubReadout"
distanceSubLabel.AnchorPoint = Vector2.new(0.5, 0)
distanceSubLabel.Position = UDim2.new(0.5, 0, 0.05, 116)
distanceSubLabel.Size = UDim2.new(0, 200, 0, 20)
distanceSubLabel.BackgroundTransparency = 1
distanceSubLabel.Font = Enum.Font.Gotham
distanceSubLabel.TextScaled = true
distanceSubLabel.TextColor3 = Color3.new(0.6, 0.6, 0.65)
distanceSubLabel.TextStrokeTransparency = 0.6
distanceSubLabel.Text = ""
distanceSubLabel.Parent = flightHudFrame

local releaseButton = Instance.new("TextButton")
releaseButton.Name = "ReleaseButton"
releaseButton.AnchorPoint = Vector2.new(0.5, 1)
releaseButton.Position = UDim2.new(0.5, 0, 0.97, 0)
releaseButton.Size = UDim2.new(0, 200, 0, 60)
releaseButton.BackgroundColor3 = Color3.new(0.85, 0.25, 0.1)
releaseButton.Font = Enum.Font.GothamBold
releaseButton.TextScaled = true
releaseButton.TextColor3 = Color3.new(1, 1, 1)
releaseButton.Text = "RELEASE!"
releaseButton.Parent = flightHudFrame

local releaseButtonCorner = Instance.new("UICorner")
releaseButtonCorner.CornerRadius = UDim.new(0, 10)
releaseButtonCorner.Parent = releaseButton

-- Return hint: the ONLY affordance telling a player, once frozen at their
-- landing spot with the reward sequence fully resolved, that a click/tap
-- anywhere sends them back to their own swing -- see the click-anywhere
-- listener and refreshReturnAffordance below. Sits at the same screen
-- position the release button occupies (both anchored/positioned near the
-- bottom-centre) -- safe now that flightHudFrame (which owns the release
-- button) and this label are never visible at the same time: this label
-- only shows while grounded, and flightHudFrame only shows while NOT
-- grounded (see setGrounded). Hidden by default; kept in sync with both
-- `grounded` and whether the character is actually frozen by
-- refreshReturnAffordance, not a plain assignment.
local returnHintLabel = Instance.new("TextLabel")
returnHintLabel.Name = "ReturnHint"
returnHintLabel.AnchorPoint = Vector2.new(0.5, 1)
returnHintLabel.Position = UDim2.new(0.5, 0, 0.86, 0)
returnHintLabel.Size = UDim2.new(0, 420, 0, 32)
returnHintLabel.BackgroundTransparency = 1
returnHintLabel.Font = Enum.Font.GothamBold
returnHintLabel.TextScaled = true
returnHintLabel.TextColor3 = Color3.new(1, 1, 1)
returnHintLabel.TextStrokeTransparency = 0.4
returnHintLabel.Text = "Click or tap anywhere to return to your swing"
returnHintLabel.Visible = false
returnHintLabel.Parent = screenGui

-- Dismount button: visible ONLY while actually RIDING -- narrower than
-- flightHudFrame's own "riding, flying, or box" window (see setMounted
-- below, the single place this and `mounted` change together) -- lets a
-- player back off a swing they mounted but don't want to launch from,
-- without waiting through an unwanted flight/box sequence. Middle of the
-- right-hand side -- the bar moved to the LEFT (see barTrack above) to
-- clear this exact spot. ZIndex explicitly above flightHudFrame's default
-- (see the written report -- dismount button not responding): belt-and-
-- braces on top of flightHudFrame.Active = false, so this is never
-- ambiguous about which of the two wins a click even if that changes later.
local dismountButton = Instance.new("TextButton")
dismountButton.Name = "DismountButton"
dismountButton.AnchorPoint = Vector2.new(1, 0.5)
dismountButton.Position = UDim2.new(0.97, 0, 0.5, 0)
dismountButton.Size = UDim2.new(0, 160, 0, 44)
dismountButton.BackgroundColor3 = Color3.new(0.18, 0.18, 0.22)
dismountButton.Font = Enum.Font.GothamBold
dismountButton.TextScaled = true
dismountButton.TextColor3 = Color3.new(1, 1, 1)
dismountButton.Text = "DISMOUNT"
dismountButton.ZIndex = 2
dismountButton.Visible = false
dismountButton.Parent = screenGui

local dismountButtonCorner = Instance.new("UICorner")
dismountButtonCorner.CornerRadius = UDim.new(0, 10)
dismountButtonCorner.Parent = dismountButton

-- ===== Mystery box UI: hidden until BoxStarted, shown center-screen as a
-- distinct modal-ish panel (not just another HUD label) since this is its own
-- reward beat, not a continuation of the flight readout above it. Text and
-- timing only, per the written report -- no particles/sound/animation
-- systems; every visual change below is an instant property set, and the
-- only "motion" is the server-driven delay before a result lands. =====
local boxFrame = Instance.new("Frame")
boxFrame.Name = "MysteryBox"
boxFrame.AnchorPoint = Vector2.new(0.5, 0.5)
boxFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
boxFrame.Size = UDim2.new(0, 380, 0, 220)
boxFrame.BackgroundColor3 = Color3.new(0.08, 0.08, 0.11)
boxFrame.BackgroundTransparency = 0.05
boxFrame.BorderSizePixel = 0
boxFrame.Visible = false
boxFrame.ZIndex = 5
boxFrame.Parent = screenGui

local boxFrameCorner = Instance.new("UICorner")
boxFrameCorner.CornerRadius = UDim.new(0, 18)
boxFrameCorner.Parent = boxFrame

local boxTitleLabel = Instance.new("TextLabel")
boxTitleLabel.Name = "BoxTitle"
boxTitleLabel.AnchorPoint = Vector2.new(0.5, 0)
boxTitleLabel.Position = UDim2.new(0.5, 0, 0.06, 0)
boxTitleLabel.Size = UDim2.new(1, -20, 0, 30)
boxTitleLabel.BackgroundTransparency = 1
boxTitleLabel.Font = Enum.Font.GothamBold
boxTitleLabel.TextScaled = true
boxTitleLabel.TextColor3 = Color3.new(0.75, 0.75, 0.8)
boxTitleLabel.TextStrokeTransparency = 0.6
boxTitleLabel.Text = "MYSTERY BOX"
boxTitleLabel.ZIndex = 6
boxTitleLabel.Parent = boxFrame

-- The number itself -- the whole point of the box, so it gets the biggest
-- text in the panel. Gold while live, brightens further on an open (see
-- BoxResult below); a double just re-renders this same label with the new
-- (bigger) value, which is what makes the escalation read as "the number
-- climbed" rather than a fresh unrelated event each time.
local boxLuckLabel = Instance.new("TextLabel")
boxLuckLabel.Name = "BoxLuck"
boxLuckLabel.AnchorPoint = Vector2.new(0.5, 0)
boxLuckLabel.Position = UDim2.new(0.5, 0, 0.18, 0)
boxLuckLabel.Size = UDim2.new(1, -20, 0, 70)
boxLuckLabel.BackgroundTransparency = 1
boxLuckLabel.Font = Enum.Font.GothamBlack
boxLuckLabel.TextScaled = true
boxLuckLabel.TextColor3 = Color3.new(1, 0.85, 0.2)
boxLuckLabel.TextStrokeTransparency = 0.3
boxLuckLabel.Text = "Luck x0"
boxLuckLabel.ZIndex = 6
boxLuckLabel.Parent = boxFrame

-- Status line: "press to open," the "..." suspense beat, "DOUBLED!", or
-- "OPENED!" -- the one element whose COLOUR is what tells a double from an
-- open apart at a glance (warm orange escalation vs. bright green
-- resolution), since the luck label above looks the same shape either way.
local boxStatusLabel = Instance.new("TextLabel")
boxStatusLabel.Name = "BoxStatus"
boxStatusLabel.AnchorPoint = Vector2.new(0.5, 0)
boxStatusLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
boxStatusLabel.Size = UDim2.new(1, -20, 0, 34)
boxStatusLabel.BackgroundTransparency = 1
boxStatusLabel.Font = Enum.Font.GothamBold
boxStatusLabel.TextScaled = true
boxStatusLabel.TextColor3 = Color3.new(1, 1, 1)
boxStatusLabel.TextStrokeTransparency = 0.5
boxStatusLabel.Text = ""
boxStatusLabel.ZIndex = 6
boxStatusLabel.Parent = boxFrame

local boxButton = Instance.new("TextButton")
boxButton.Name = "BoxOpenButton"
boxButton.AnchorPoint = Vector2.new(0.5, 1)
boxButton.Position = UDim2.new(0.5, 0, 0.93, 0)
boxButton.Size = UDim2.new(0, 220, 0, 56)
boxButton.BackgroundColor3 = Color3.new(0.15, 0.65, 0.95)
boxButton.Font = Enum.Font.GothamBold
boxButton.TextScaled = true
boxButton.TextColor3 = Color3.new(1, 1, 1)
boxButton.Text = "PRESS"
boxButton.ZIndex = 6
boxButton.Parent = boxFrame

local boxButtonCorner = Instance.new("UICorner")
boxButtonCorner.CornerRadius = UDim.new(0, 10)
boxButtonCorner.Parent = boxButton

-- ===== Slime reveal panel: the box's payoff, shown AFTER the box itself
-- (see SlimeRevealed below) -- never at the same time as boxFrame, which
-- hides the instant this appears. Text and colour only, per the written
-- report -- no particles/sound/animation systems. Rarity reads instantly two
-- ways: the TIER label is coloured with that tier's own colour (see
-- SlimeConfig.SLIME_TIER_COLORS) and sized bigger for higher tiers (see
-- SLIME_TIER_TEXT_SIZE_BASE/STEP), and a plain asterisk flourish (none for
-- Common-Epic, escalating "*" through "****" for Legendary-Divine) frames the
-- tier name -- so a Divine reveal is unmistakably a bigger deal than a
-- Common one without needing anything beyond text and colour. =====
local slimeRevealFrame = Instance.new("Frame")
slimeRevealFrame.Name = "SlimeReveal"
slimeRevealFrame.AnchorPoint = Vector2.new(0.5, 0.5)
slimeRevealFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
slimeRevealFrame.Size = UDim2.new(0, 420, 0, 260)
slimeRevealFrame.BackgroundColor3 = Color3.new(0.05, 0.05, 0.07)
slimeRevealFrame.BackgroundTransparency = 0.05
slimeRevealFrame.BorderSizePixel = 0
slimeRevealFrame.Visible = false
slimeRevealFrame.ZIndex = 5
slimeRevealFrame.Parent = screenGui

local slimeRevealCorner = Instance.new("UICorner")
slimeRevealCorner.CornerRadius = UDim.new(0, 18)
slimeRevealCorner.Parent = slimeRevealFrame

-- Border tinted with the TIER's colour -- the very first thing the eye
-- catches, before reading any text: a Common's border is a dull grey
-- sliver, a Divine's is bright gold.
local slimeRevealBorder = Instance.new("UIStroke")
slimeRevealBorder.Thickness = 3
slimeRevealBorder.Color = Color3.new(1, 1, 1)
slimeRevealBorder.Parent = slimeRevealFrame

local newBadgeLabel = Instance.new("TextLabel")
newBadgeLabel.Name = "NewBadge"
newBadgeLabel.AnchorPoint = Vector2.new(0.5, 0)
newBadgeLabel.Position = UDim2.new(0.5, 0, 0.06, 0)
newBadgeLabel.Size = UDim2.new(1, -20, 0, 30)
newBadgeLabel.BackgroundTransparency = 1
newBadgeLabel.Font = Enum.Font.GothamBold
newBadgeLabel.TextScaled = true
newBadgeLabel.TextColor3 = Color3.new(1, 1, 1)
newBadgeLabel.TextStrokeTransparency = 0.5
newBadgeLabel.Text = ""
newBadgeLabel.ZIndex = 6
newBadgeLabel.Parent = slimeRevealFrame

-- NOT TextScaled -- TextSize is set explicitly per reveal (see
-- SlimeRevealed below) so higher tiers render LITERALLY bigger text, not
-- just auto-fit to the same box.
local slimeTierLabel = Instance.new("TextLabel")
slimeTierLabel.Name = "SlimeTier"
slimeTierLabel.AnchorPoint = Vector2.new(0.5, 0)
slimeTierLabel.Position = UDim2.new(0.5, 0, 0.2, 0)
slimeTierLabel.Size = UDim2.new(1, -20, 0, 60)
slimeTierLabel.BackgroundTransparency = 1
slimeTierLabel.Font = Enum.Font.GothamBlack
slimeTierLabel.TextColor3 = Color3.new(1, 1, 1)
slimeTierLabel.TextStrokeTransparency = 0.2
slimeTierLabel.Text = ""
slimeTierLabel.ZIndex = 6
slimeTierLabel.Parent = slimeRevealFrame

local slimeNameLabel = Instance.new("TextLabel")
slimeNameLabel.Name = "SlimeName"
slimeNameLabel.AnchorPoint = Vector2.new(0.5, 0)
slimeNameLabel.Position = UDim2.new(0.5, 0, 0.58, 0)
slimeNameLabel.Size = UDim2.new(1, -20, 0, 40)
slimeNameLabel.BackgroundTransparency = 1
slimeNameLabel.Font = Enum.Font.GothamBold
slimeNameLabel.TextScaled = true
slimeNameLabel.TextColor3 = Color3.new(1, 1, 1)
slimeNameLabel.TextStrokeTransparency = 0.5
slimeNameLabel.Text = ""
slimeNameLabel.ZIndex = 6
slimeNameLabel.Parent = slimeRevealFrame

-- Draws the bar/multiplier readout for a GIVEN phase -- shared by the live
-- per-frame sweep (RenderStepped below) and doRelease's freeze-on-release
-- (below), so the two can never disagree. BUG FIX (see written report): the
-- live sweep used to keep animating for one extra frame after release --
-- doRelease flips canRelease synchronously, but the bar's last on-screen
-- value was whatever the PREVIOUS RenderStepped frame rendered, a fraction of
-- a frame stale relative to the exact phase doRelease captures for the
-- outcome text. Near the sweet spot's narrow window that stale frame can read
-- a noticeably different multiplier (even flip in or out of a snap), so the
-- bar and the outcome text could disagree. Calling this with the SAME phase
-- doRelease grades the outcome from guarantees they always match.
local function renderBarForPhase(phase: number)
	local fill = fillFraction(phase)
	barIndicator.Position = UDim2.new(0.5, 0, 1 - fill, 0)

	local hit = inSweetSpot(phase)
	multiplierLabel.Text = string.format("%.2fx", launchMultiplier(phase))
	multiplierLabel.TextColor3 = hit and Color3.new(0.4, 1, 0.5) or Color3.new(1, 1, 1)

	if hit then
		barIndicator.Size = UDim2.new(1, 14, 0, 14)
		barIndicator.BackgroundColor3 = Color3.new(1, 0.85, 0.25)
		barIndicatorGlow.Transparency = 0.15
	else
		barIndicator.Size = UDim2.new(1, 8, 0, 10)
		barIndicator.BackgroundColor3 = Color3.new(1, 1, 1)
		barIndicatorGlow.Transparency = 1
	end
end

-- ===== State =====

-- Whether THIS client's own character is currently frozen -- Anchored, with
-- AutoRotate off -- which only happens (see LaunchServer.server.luau's
-- Heartbeat landing handler) between landing and a successful return: the
-- server keeps a landed player anchored all the way through the box and the
-- slime reveal, specifically so the Humanoid controller (and, on mobile,
-- tap-to-move) categorically cannot move them until they choose to leave.
-- Read directly off the character's own RootPart.Anchored (an ordinary
-- replicated BasePart property) rather than a second, locally tracked flag,
-- so this can never drift out of sync with the actual server-side freeze --
-- see refreshReturnAffordance below and the click-anywhere listener further
-- down, both of which call this fresh rather than caching it.
local function characterIsFrozen(): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = humanoid and humanoid.RootPart
	return rootPart ~= nil and rootPart.Anchored
end

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
	dismountButton.Visible = value
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

-- The return hint shows under a NARROWER condition than `grounded` alone
-- (see the written report): `grounded` alone stays true for ordinary
-- walking-around-the-lane time too (right after a return, or at first
-- spawn), where a click/tap must NOT re-fire the return -- only while the
-- character is ALSO still frozen at the landing spot does clicking actually
-- do anything, so the hint only shows then. Called from setGrounded's own
-- transitions (the only two moments frozen state can meaningfully change
-- while this runs) AND, optimistically, right after the click-anywhere
-- listener fires the remote -- see that connection below -- so the hint
-- disappears the instant a return is triggered, not on the next state
-- transition.
local function refreshReturnAffordance()
	returnHintLabel.Visible = grounded and characterIsFrozen()
end

local function setGrounded(value: boolean)
	grounded = value
	flightHudFrame.Visible = not value
	refreshReturnAffordance()
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

	-- Grade THIS release for the outcome readout, from the same phase this
	-- client would show on the bar the instant before firing -- cosmetic
	-- prediction only, same caveat as the rest of this file's mirrored formulas
	-- (the server's own phase, read when the signal actually arrives, is what
	-- really decides the outcome). Close enough under normal latency to be a
	-- trustworthy "what did that feel like" readout without waiting on a round
	-- trip.
	local releasePhase = swingPhase(ownLaneIndex)
	local releaseMultiplier = launchMultiplier(releasePhase)
	local bandIndex = outcomeBandIndex(releaseMultiplier)
	local band = LaunchConfig.OUTCOME_BANDS[bandIndex]
	local style = OUTCOME_STYLES[bandIndex]
	outcomeLabel.Text = string.format("%s  %.2fx", band.text, releaseMultiplier)
	outcomeLabel.TextColor3 = style.color
	outcomeLabel.Size = style.size
	outcomeLabel.Font = style.font
	outcomeLabel.TextStrokeTransparency = style.strokeTransparency

	-- Freeze the bar/multiplier readout at this EXACT phase -- see
	-- renderBarForPhase's comment. canRelease flips false right below, and the
	-- RenderStepped loop's own "if not canRelease then return end" guard means
	-- nothing overwrites this again until canRelease goes true (ResetReady, at
	-- the start of the next swing).
	renderBarForPhase(releasePhase)

	canRelease = false
	distanceLabel.Text = "0.0 studs"
	releaseRemote:FireServer()
end

-- GuiButton Mouse* events fire for touch taps too (Roblox synthesizes them), so
-- this covers mouse, touch, and gamepad activation of the on-screen button.
releaseButton.MouseButton1Click:Connect(doRelease)

-- THE BEAT: boxWaitingForResult flips true the instant a press is sent and the
-- status line switches to "...", then holds until BoxResult actually arrives
-- -- BOX_ROLL_DELAY_SECONDS later, server time (see LaunchServer's
-- onBoxPress). Nothing here times that delay locally; this just waits for the
-- server's own result event, so the pause the player feels is always the
-- real, authoritative one, never a client-guessed approximation of it.
local function doBoxPress()
	if not boxActive or boxWaitingForResult then
		return
	end
	boxWaitingForResult = true
	boxStatusLabel.Text = "..."
	boxStatusLabel.TextColor3 = Color3.new(0.7, 0.7, 0.75)
	boxPressRemote:FireServer()
end

boxButton.MouseButton1Click:Connect(doBoxPress)

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

dismountButton.MouseButton1Click:Connect(doDismount)

-- A MOUSE click OR a TOUCH tap -- while grounded AND actually frozen at the
-- landing spot, nowhere else -- returns the player to their own swing (see
-- the written report). Server-authoritative: returnToSwingRemote carries no
-- data, and LaunchServer.server.luau's onReturnToSwing re-checks
-- states[player] == "grounded" itself before moving anything, so these
-- local gates are purely to avoid firing a pointless remote (and, for
-- touch, to avoid hijacking movement -- see below), not a trust boundary.
--
-- BOTH input types now require characterIsFrozen() (see its own comment,
-- defined above with the rest of this client's state), not just `grounded`
-- alone: `grounded` alone stays true for ordinary walking-around-the-lane
-- time too (right after a return, or at first spawn), where a click must do
-- nothing -- only while the character is ALSO still frozen does clicking
-- actually mean "return."
--
-- TOUCH SPECIFICALLY (see the written report): Roblox's default mobile
-- control scheme drives ordinary walking via tap-to-move, which fires this
-- SAME InputBegan event, with gameProcessedEvent == false, for every
-- movement tap -- the built-in character controller consumes it through its
-- own bound action, not through GUI hit-testing, so gameProcessedEvent
-- can't distinguish "tapped to walk" from "tapped to return." Gating touch
-- on characterIsFrozen() resolves that unambiguously: the server keeps a
-- landed player Anchored all the way through the box and reveal
-- specifically so they categorically CANNOT be moved by the Humanoid
-- controller (see LaunchServer.server.luau's Heartbeat landing handler and
-- onReturnToSwing) -- a tap during that window can ONLY mean "return," tap-
-- to-move has nothing to compete with. The instant onReturnToSwing
-- unanchors the root, taps go back to meaning "walk" and are no longer
-- treated as a return gesture. MOUSE never had this ambiguity to begin with
-- (the default PC control scheme drives walking from WASD, not clicks), but
-- is now gated the same way for consistency with the hint's own visibility
-- (see refreshReturnAffordance) -- what the hint promises is exactly what
-- either input type now does.
local RETURN_TRIGGER_MOUSE_TYPES = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.MouseButton2] = true,
	[Enum.UserInputType.MouseButton3] = true,
}

-- Space does double duty: release the swing normally, or press the box when
-- one's up -- never both at once, since boxActive and canRelease can't be
-- simultaneously true (see resetReadyRemote's guard below).
UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	-- Ignore any click/tap the engine already routed to a GUI element (a
	-- button, this HUD's own panels, the Inventory/Swing Shop windows) --
	-- WITHOUT this check, pressing the Inventory or Swing Shop button would
	-- also count as "click anywhere" and immediately teleport the player
	-- back to their swing on every single press.
	if gameProcessedEvent then
		return
	end
	if input.KeyCode == Enum.KeyCode.Space then
		if boxActive then
			doBoxPress()
		else
			doRelease()
		end
		return
	end
	if not grounded then
		return
	end
	local isReturnTrigger = RETURN_TRIGGER_MOUSE_TYPES[input.UserInputType] or input.UserInputType == Enum.UserInputType.Touch
	if isReturnTrigger and characterIsFrozen() then
		returnToSwingRemote:FireServer()
		-- Optimistic: the ONLY way `characterIsFrozen()` ever goes false
		-- while `grounded` stays true is a successful return (see
		-- onReturnToSwing) -- hide the hint immediately rather than waiting
		-- for a further event, since nothing else will trigger a refresh
		-- until the NEXT setGrounded/setMounted transition.
		refreshReturnAffordance()
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
-- BUG FIX (see written report): u is now measured against startTime using
-- Workspace:GetServerTimeNow() (the same synced clock the swing already used),
-- not os.clock() from the moment this event happened to arrive. That's what
-- makes this client's u match the server's u at every instant regardless of how
-- long this message took to get here -- previously, a late-arriving message
-- meant this client's countup could still be short of the true distance when
-- the server's OWN (earlier-starting) timeline had already finished and told
-- the server to reset, occasionally letting a second release overwrite the
-- first flight's still-incomplete display (see doRelease's guard above too).
flightStartedRemote.OnClientEvent:Connect(function(distance: number, archHeight: number, duration: number, startPosition: Vector3, startTime: number, luck: number)
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
	-- "Pull back as the arc gets bigger": computed ONCE per flight from this
	-- flight's own arc height, not re-adjusted mid-flight.
	local cameraBehindOffset = LaunchConfig.CAMERA_BEHIND_DISTANCE + archHeight * LaunchConfig.CAMERA_PULLBACK_FACTOR

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = chaseCameraCFrame(startPosition, cameraBehindOffset)
	camera.CameraType = Enum.CameraType.Custom
end)

resetReadyRemote.OnClientEvent:Connect(function()
	canRelease = true
	-- The reward sequence (landing, box, reveal) has fully resolved -- the
	-- player is grounded again, right where they landed (see the written
	-- report: the return is no longer automatic). Shows the click-anywhere
	-- hint and re-arms the listener above.
	setGrounded(true)
	-- Defensive cleanup, not the normal path (a box that OPENED already hides
	-- itself below on its own timer): if ResetReady ever arrives while a box
	-- is still marked active for any reason, this guarantees no stuck box UI
	-- survives into the next round -- ResetReady only ever fires once the
	-- server-side sequence (box included) has fully resolved, so seeing it is
	-- always a safe moment to force this closed.
	boxActive = false
	boxWaitingForResult = false
	boxFrame.Visible = false
	-- Same defensive guarantee, extended to the slime panel: a normal open
	-- already hides this itself after RESET_DELAY (see SlimeRevealed below),
	-- but ResetReady arriving is ALWAYS a safe moment to force it closed too.
	slimeRevealFrame.Visible = false
	distanceLabel.Text = "Time your release!"
	distanceLabel.TextColor3 = Color3.new(1, 1, 1)
end)

-- BoxStarted: fired once per landing that earned luck > 0 (see LaunchServer's
-- Heartbeat landing handler) -- a 0-luck landing never fires this, so the box
-- simply never appears for a whiff (see the written report).
boxStartedRemote.OnClientEvent:Connect(function(luck: number)
	boxActive = true
	boxWaitingForResult = false
	boxLuckLabel.Text = string.format("Luck x%s", LuckCurve.formatLuck(luck))
	boxLuckLabel.TextColor3 = Color3.new(1, 0.85, 0.2)
	boxStatusLabel.Text = "Press to open!"
	boxStatusLabel.TextColor3 = Color3.new(1, 1, 1)
	boxFrame.Visible = true
end)

-- BoxResult: the server's answer to exactly one press, always arriving
-- BOX_ROLL_DELAY_SECONDS after that press was accepted -- see onBoxPress. A
-- double (opened = false) reads as ESCALATION: the same luck label just grows
-- a bigger number in a hot, energetic colour, and the status line invites
-- another press -- not an error state, the good outcome. An open
-- (opened = true) reads as RESOLUTION: bright green "OPENED!", the button
-- disabled (boxActive false, so further presses do nothing), and the panel
-- itself lingers for RESET_DELAY -- the same window the player already reads
-- the plain distance/luck result in -- before clearing, so it never gets cut
-- off mid-read.
boxResultRemote.OnClientEvent:Connect(function(opened: boolean, luck: number)
	boxWaitingForResult = false
	boxLuckLabel.Text = string.format("Luck x%s", LuckCurve.formatLuck(luck))
	if opened then
		boxActive = false
		boxLuckLabel.TextColor3 = Color3.new(0.4, 1, 0.5)
		boxStatusLabel.Text = "OPENED!"
		boxStatusLabel.TextColor3 = Color3.new(0.3, 1, 0.4)
		-- boxFrame is deliberately left showing "OPENED!" here -- it hides
		-- itself the instant SlimeRevealed arrives below, not on a separate
		-- client-side timer. That's what guarantees the two beats (box open,
		-- then slime) never overlap and never rely on the client guessing
		-- the server's own REVEAL_BOX_TO_SLIME_DELAY_SECONDS pacing.
	else
		boxLuckLabel.TextColor3 = Color3.new(1, 0.85, 0.2)
		boxStatusLabel.Text = "DOUBLED! Press again!"
		boxStatusLabel.TextColor3 = Color3.new(1, 0.55, 0.15)
	end
end)

-- SlimeRevealed: THE SECOND beat -- arrives REVEAL_BOX_TO_SLIME_DELAY_SECONDS
-- after BoxResult(opened=true), never at the same instant (see
-- LaunchServer's onBoxPress). boxFrame hides right as this shows, so the box
-- and the slime are never on screen together -- a clean handoff, box's job
-- done, slime panel takes over. Held visible for RESET_DELAY (the same
-- window the player already reads every other landing result in), then
-- cleared -- ResetReady's own handler (above) is the defensive backstop if
-- that timer and the real reset ever fall out of step.
slimeRevealedRemote.OnClientEvent:Connect(function(globalIndex: number, isNew: boolean)
	local slime = SlimeData.SLIMES[globalIndex]
	if not slime then
		return
	end
	boxFrame.Visible = false

	local starCount = math.max(0, slime.tier - 4)
	local flourish = string.rep("*", starCount)
	local tierText = string.upper(slime.tierName)
	if flourish ~= "" then
		tierText = flourish .. " " .. tierText .. " " .. flourish
	end
	slimeTierLabel.Text = tierText
	slimeTierLabel.TextColor3 = slime.color
	slimeTierLabel.TextSize = SlimeConfig.SLIME_TIER_TEXT_SIZE_BASE + (slime.tier - 1) * SlimeConfig.SLIME_TIER_TEXT_SIZE_STEP
	slimeRevealBorder.Color = slime.color
	slimeNameLabel.Text = slime.name

	if isNew then
		newBadgeLabel.Text = "* NEW! *"
		newBadgeLabel.TextColor3 = Color3.new(0.3, 1, 0.4)
	else
		newBadgeLabel.Text = "Duplicate"
		newBadgeLabel.TextColor3 = Color3.new(0.6, 0.6, 0.65)
	end

	slimeRevealFrame.Visible = true
	task.delay(LaunchConfig.RESET_DELAY, function()
		slimeRevealFrame.Visible = false
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
	-- Cheap (a couple of .Parent checks) every frame; only ever actually
	-- re-fetches anything in the rare frame right after a tier purchase
	-- rebuilds the structure -- see ensureSwingReferences's own comment.
	ensureSwingReferences()

	local phase = swingPhase(ownLaneIndex)

	-- The swing itself always swings, for every viewer, whether or not anyone
	-- is riding it right now -- matches "it just swings, forever" regardless of
	-- a rider. Every connected client computes and shows this identically; it's
	-- cheap, pure math, no reason to gate it to just the rider's own client.
	local theta = swingTheta(phase)
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
			character:PivotTo(riderCFrame(seatPosition))
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
			character:PivotTo(trajectoryCFrame(flightStartPosition, flightDistance, flightArcHeight, u))
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
			if flightLuck > 0 then
				distanceLabel.Text = string.format("Luck x%s!", LuckCurve.formatLuck(flightLuck))
				distanceLabel.TextColor3 = Color3.new(1, 0.85, 0.2)
			else
				distanceLabel.Text = "No luck (short of the road)"
				distanceLabel.TextColor3 = Color3.new(1, 1, 1)
			end
			distanceSubLabel.Text = string.format("%.1f studs", flightDistance)
			flightActive = false
			return
		end

		-- Count the distance UP live -- horizontal progress is exactly linear in
		-- u for this trajectory, so this number always matches exactly how far
		-- along the flight the character visibly is, not a decoupled animation.
		distanceLabel.Text = string.format("%.1f studs", flightDistance * u)
		return
	end

	-- Bar/multiplier HUD is riding-only now, same as the character-positioning
	-- gate above -- a grounded player walking to their base/the shop has
	-- nothing to release, so there's nothing useful for this readout to show.
	if not mounted or not canRelease then
		return
	end
	renderBarForPhase(phase)
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
-- PERMISSIVE ON PURPOSE (see the written report -- remote lane discovery
-- finding zero lanes in a 6-client Studio test): this used to be
-- "^SwingPivot_(%d+)$" -- %d matches digits ONLY, with no leading-minus-sign
-- case at all, so it silently rejected every SwingPivot_<UserId> whose
-- UserId is negative. Studio multi-client test sessions hand every
-- simulated client a placeholder UserId, and those are commonly negative --
-- the LOCAL lane was never affected by this (ownSwingPivotName below is
-- built with string.format("SwingPivot_%d", player.UserId), which formats a
-- negative number with its sign correctly; nothing about building that
-- string ever runs it back through a digits-only pattern), only the
-- REMOTE-lane discovery in rescanRemoteLanes, which does. ".+" captures
-- everything after the underscore, whatever it looks like, and
-- rescanRemoteLanes' own tonumber(userIdText) check (kept unchanged) is what
-- actually validates it, skipping the entry if it isn't a real number at
-- all -- the same outcome as before for genuine junk, but no longer for a
-- perfectly valid negative UserId.
local SWING_PIVOT_NAME_PATTERN = "^SwingPivot_(.+)$"

-- Same 3-line formula as swingSeatPosition above, just taking an EXPLICIT
-- pivot instead of closing over this client's own -- swingSeatPosition
-- itself is untouched.
local function seatPositionForPivot(pivot: BasePart, theta: number): Vector3
	local pivotPosition = pivot.Position
	local length = SwingGeometry.ropeLengthForPivotY(pivotPosition.Y)
	return pivotPosition + Vector3.new(0, -length * math.cos(theta), -length * math.sin(theta))
end

-- Same body as repositionChainLinks above, generalised to an explicit seat/
-- anchor/folder set instead of this client's own single-lane locals.
-- repositionChainSide itself is already fully generic (no closures over the
-- single-lane globals), so it's reused as-is here, unmodified.
local function repositionChainLinksFor(seatModel: Model, chainAnchorLeft: BasePart, chainAnchorRight: BasePart, chainLinksFolder: Folder)
	if not chainAnchorLeft.Parent or not chainAnchorRight.Parent then
		return
	end
	local seatCore = seatModel.PrimaryPart
	if not seatCore then
		return
	end
	local leftAttachment = seatCore:FindFirstChild("ChainBottomAttachmentLeft") :: Attachment?
	local rightAttachment = seatCore:FindFirstChild("ChainBottomAttachmentRight") :: Attachment?
	if not leftAttachment or not rightAttachment then
		return
	end

	local leftLinks, rightLinks = {}, {}
	for _, link in chainLinksFolder:GetChildren() do
		local side = link:GetAttribute("Side")
		if side == "Left" then
			table.insert(leftLinks, link)
		elseif side == "Right" then
			table.insert(rightLinks, link)
		end
	end
	repositionChainSide(leftLinks, chainAnchorLeft.Position, leftAttachment.WorldPosition)
	repositionChainSide(rightLinks, chainAnchorRight.Position, rightAttachment.WorldPosition)
end

-- One lane's seat sway, for a GIVEN pivot -- every viewer sees every lane
-- swing whether or not anyone is on it (same reasoning the local loop's own
-- comment gives), so this runs unconditionally for every lane found, not
-- just occupied ones. Returns the seat position (needed by
-- renderLaneOccupant below for "riding") or nil if this lane's structure
-- isn't fully built/is mid-rebuild (a tier purchase ClearAllChildren's the
-- structure folder before repopulating it -- see SwingBuilder.build) -- that
-- lane is simply skipped for this one frame, same "cheap, re-checked every
-- frame" shape ensureSwingReferences above uses for this client's own lane,
-- never an error.
local function renderLaneSeat(pivot: BasePart, laneIndex: number, structureFolder: Instance): Vector3?
	local seatModel = structureFolder:FindFirstChild("SwingSeat")
	if not (seatModel and seatModel:IsA("Model") and (seatModel :: Model).PrimaryPart) then
		return nil
	end
	local seat = seatModel :: Model

	local phase = swingPhase(laneIndex)
	local theta = swingTheta(phase)
	local seatPosition = seatPositionForPivot(pivot, theta)
	seat:PivotTo(CFrame.new(seatPosition) * CFrame.Angles(theta, 0, 0))

	local chainAnchorLeft = structureFolder:FindFirstChild("SwingChainAnchorLeft")
	local chainAnchorRight = structureFolder:FindFirstChild("SwingChainAnchorRight")
	local chainLinksFolder = structureFolder:FindFirstChild("SwingChainLinks")
	if
		chainAnchorLeft and chainAnchorLeft:IsA("BasePart")
		and chainAnchorRight and chainAnchorRight:IsA("BasePart")
		and chainLinksFolder and chainLinksFolder:IsA("Folder")
	then
		repositionChainLinksFor(seat, chainAnchorLeft :: BasePart, chainAnchorRight :: BasePart, chainLinksFolder :: Folder)
	end

	return seatPosition
end

-- One lane's OCCUPANT -- driven entirely from RiderState and, while flying,
-- the Flight* attributes LaunchServer.server.luau writes on the same pivot.
-- "landed"/"empty"/unset (a fresh pivot with no rider yet): writes nothing,
-- deliberately -- the character is already wherever the server's own one-
-- shot mount/release/landing/return PivotTo left it, and nothing here may
-- touch it outside exactly these two states.
local function renderLaneOccupant(pivot: BasePart, occupant: Player, seatPosition: Vector3?)
	local character = occupant.Character
	if not character then
		return
	end
	local riderState = pivot:GetAttribute("RiderState")
	if riderState == "riding" then
		if not seatPosition then
			return
		end
		character:PivotTo(riderCFrame(seatPosition))
	elseif riderState == "flying" then
		local startTime = pivot:GetAttribute("FlightStartTime")
		local startPosition = pivot:GetAttribute("FlightStartPos")
		local distance = pivot:GetAttribute("FlightDistance")
		local archHeight = pivot:GetAttribute("FlightArcHeight")
		local duration = pivot:GetAttribute("FlightDuration")
		if
			typeof(startTime) ~= "number"
			or typeof(startPosition) ~= "Vector3"
			or typeof(distance) ~= "number"
			or typeof(archHeight) ~= "number"
			or typeof(duration) ~= "number"
			or duration <= 0
		then
			-- Attributes not fully written yet (see onRelease's own ordering
			-- guarantee -- params before RiderState flips to "flying") or a
			-- lane mid-teardown; skip this lane silently for this one frame.
			return
		end

		-- DELIBERATELY UNCLAMPED, then rejected outside [0, 1) -- see the
		-- written report. Attribute replication gives no ordering guarantee
		-- that observing RiderState == "flying" on a given frame also means
		-- THIS frame's Flight* reads are the NEW flight's values: the
		-- previous flight's own params are all still valid numbers (they
		-- pass the type guard above) right up until the new ones land, so a
		-- client can observe "flying" together with a STALE param set for
		-- one or more frames. A stale flight's startTime is always further
		-- in the past relative to its own (also stale) duration, so its u
		-- is always >= 1 -- clamping to 1 used to render that as "standing
		-- exactly at the old landing spot," silently, for however many
		-- frames the staleness lasted. Rejecting u >= 1 outright (alongside
		-- u < 0, for a startTime whose replication briefly arrives after a
		-- Heartbeat that started before it -- clock skew, not a bug) turns
		-- both stale-read shapes into "write nothing" instead of a wrong
		-- write. This also makes the per-frame render redundant with (not
		-- fighting) the "landed" attribute once it arrives: by the time
		-- RiderState flips to "landed" server-side, this client's own u had
		-- already been rejecting the same trajectory for at least one frame.
		local u = (Workspace:GetServerTimeNow() - (startTime :: number)) / (duration :: number)
		if u < 0 or u >= 1 then
			return
		end
		character:PivotTo(trajectoryCFrame(startPosition :: Vector3, distance :: number, archHeight :: number, u))
	end
end

-- One discovered OTHER lane, cached between rescans -- see rescanRemoteLanes
-- below. `userId` is kept alongside (not re-parsed from pivot.Name every
-- render frame) purely so the per-frame path never touches string/pattern
-- work at all, only table reads and Instance calls.
type RemoteLane = {
	pivot: BasePart,
	laneIndex: number,
	structureFolder: Instance,
	userId: number,
}

local remoteLanes: { RemoteLane } = {}
local lastRemoteLaneScanClock = 0

-- Walks Workspace:GetChildren() ONCE, on a throttle (see rescan call site
-- below and LaunchConfig.REMOTE_LANE_RESCAN_INTERVAL_SECONDS), and replaces
-- the whole cache in one shot -- see the written report: LaneConfig.
-- LANE_COUNT bounds how many PIVOTS this can ever find, but not how many
-- CHILDREN Workspace has to be walked through to find them (road bands,
-- plot pads, stalls, mount-radius discs, per-player base folders, etc. are
-- all direct or indirect Workspace content too), so this walk itself is not
-- free -- it no longer runs every single RenderStepped.
--
-- `userIdText == tostring(player.UserId)` is the guard for "skip
-- LocalPlayer" -- a UserId comparison, not an Instance identity comparison
-- against swingPivot. LaunchServer.server.luau always names a player's own
-- pivot SwingPivot_<player.UserId> (see buildPlayerSwing/laneInstanceNames)
-- and never renames it, so the UserId encoded in a pivot's own Name is
-- stable regardless of whether the underlying Instance is ever destroyed
-- and recreated -- unlike a cached Instance reference, which would go stale
-- (and silently stop matching) the moment that happened. See the written
-- report for what was actually checked about SwingBuilder.build's own
-- rebuild behaviour, cited at this file's own investigation notes -- this
-- guard does not depend on the answer either way.
local function rescanRemoteLanes()
	local scanned: { RemoteLane } = {}
	for _, instance in Workspace:GetChildren() do
		if not instance:IsA("BasePart") then
			continue
		end
		local userIdText = instance.Name:match(SWING_PIVOT_NAME_PATTERN)
		if not userIdText or userIdText == tostring(player.UserId) then
			continue
		end
		local userId = tonumber(userIdText)
		if not userId then
			continue
		end
		local laneIndexAttribute = instance:GetAttribute("LaneIndex")
		if typeof(laneIndexAttribute) ~= "number" then
			continue
		end
		local structureFolder = Workspace:FindFirstChild("SwingStructure_" .. userIdText)
		if not structureFolder then
			continue
		end
		table.insert(scanned, {
			pivot = instance :: BasePart,
			laneIndex = laneIndexAttribute :: number,
			structureFolder = structureFolder,
			userId = userId,
		})
	end
	remoteLanes = scanned
end

-- ===== TEMPORARY DEBUG INSTRUMENTATION -- Bug 3 investigation only, remove
-- once renderOtherLanes' actual behaviour is confirmed from Output.
--
-- BUG FIX (see the written report): the previous version of this only ever
-- printed once, on the FIRST rescan (~REMOTE_LANE_RESCAN_INTERVAL_SECONDS
-- after this client loads) -- which cannot tell "discovery is permanently
-- broken" apart from "the other five players just hadn't joined/built their
-- lane yet at that exact moment," since both look identical (0 lanes, one
-- print, silence forever after). Reports now instead whenever the CACHED
-- LANE COUNT actually CHANGES between rescans, plus unconditionally on the
-- very first rescan regardless of what it finds -- still not per-frame
-- (this only ever runs from inside the same throttled rescan branch
-- renderOtherLanes already gates on).
--
-- Also widened WHAT gets reported: rather than only describing lanes that
-- ALREADY made it into the cache (which tells you nothing about lanes
-- discovery is REJECTING), this does its own independent walk of
-- Workspace:GetChildren(), filtered by a PLAIN string.find for "SwingPivot"
-- (not SWING_PIVOT_NAME_PATTERN, and not restricted to BasePart) -- so a
-- pivot that exists but fails the pattern, the type check, the LaneIndex
-- attribute check, or the SwingStructure_<...> lookup still shows up here,
-- with enough detail to see exactly WHICH check it's failing.
--
-- LOOK FOR: "[LaunchClient][DEBUG-REMOTE-LANES]" in Output. =====
local debugPreviousLaneCount: number? = nil
local function debugReportOnLaneCountChange()
	local currentLaneCount = #remoteLanes
	if debugPreviousLaneCount ~= nil and currentLaneCount == debugPreviousLaneCount then
		return
	end
	debugPreviousLaneCount = currentLaneCount

	local workspaceChildren = Workspace:GetChildren()
	print(string.format(
		"[LaunchClient][DEBUG-REMOTE-LANES] localUserId=%s workspaceChildCount=%d cachedLaneCount=%d",
		tostring(player.UserId),
		#workspaceChildren,
		currentLaneCount
	))
	for _, instance in workspaceChildren do
		if string.find(instance.Name, "SwingPivot", 1, true) then
			-- The pattern's one capture group IS the userIdText a real match
			-- would produce -- reused directly for the structure lookup below
			-- rather than re-deriving it, so this print can never disagree
			-- with what rescanRemoteLanes itself would have done with the
			-- same instance.
			local capturedUserIdText = instance.Name:match(SWING_PIVOT_NAME_PATTERN)
			local laneIndexAttribute = instance:GetAttribute("LaneIndex")
			local structureFound = false
			if capturedUserIdText then
				structureFound = Workspace:FindFirstChild("SwingStructure_" .. capturedUserIdText) ~= nil
			end
			print(string.format(
				"[LaunchClient][DEBUG-REMOTE-LANES]   name=%s className=%s matchesPattern=%s laneIndexValue=%s laneIndexType=%s structureFound=%s",
				instance.Name,
				instance.ClassName,
				tostring(capturedUserIdText ~= nil),
				tostring(laneIndexAttribute),
				typeof(laneIndexAttribute),
				tostring(structureFound)
			))
		end
	end
end
-- ===== END TEMPORARY DEBUG INSTRUMENTATION =====

-- Renders every OTHER connected player's own lane, every frame, from the
-- cache alone -- PivotTo itself must stay per-frame (that's the whole fix),
-- only the Workspace WALK that discovers/refreshes the lane list is
-- throttled (see rescanRemoteLanes above). A stale cache entry -- this
-- lane's occupant left, or a tier purchase is mid-rebuild and briefly
-- destroyed/recreated the structure's children -- is skipped silently for
-- the frame it's used, via ordinary .Parent checks, never an error; the
-- next rescan (at most REMOTE_LANE_RESCAN_INTERVAL_SECONDS later) drops or
-- refreshes it for real. No ChildAdded/ChildRemoved connection exists
-- anywhere in this system, so there is nothing to leak.
local function renderOtherLanes()
	local now = os.clock()
	if now - lastRemoteLaneScanClock >= LaunchConfig.REMOTE_LANE_RESCAN_INTERVAL_SECONDS then
		lastRemoteLaneScanClock = now
		rescanRemoteLanes()
		-- TEMPORARY (see above) -- guarded internally, only prints on the
		-- first rescan and again whenever the cached lane count changes.
		debugReportOnLaneCountChange()
	end

	for _, lane in remoteLanes do
		if not lane.pivot.Parent or not lane.structureFolder.Parent then
			continue
		end
		local seatPosition = renderLaneSeat(lane.pivot, lane.laneIndex, lane.structureFolder)

		local occupant = Players:GetPlayerByUserId(lane.userId)
		if occupant then
			renderLaneOccupant(lane.pivot, occupant, seatPosition)
		end
	end
end

RunService.RenderStepped:Connect(renderOtherLanes)
