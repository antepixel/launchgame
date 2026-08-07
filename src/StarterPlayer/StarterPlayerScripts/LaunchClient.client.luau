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
-- The SAME builder every other slime in the game is made with (base slots, the
-- landmark) -- the reveal must not invent a second way to draw a slime.
local SlimeBuilder = require(ReplicatedStorage.SlimeBuilder)

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
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LaunchHud"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- Groups every element that only means something while THIS client is
-- riding or flying -- the distance readout, the multiplier/bar, the outcome
-- text, and the release button -- behind ONE Visible flip instead of six
-- independent ones (see refreshFlightHud below, the single place this
-- toggles).
--
-- BUG FIX (see the written report -- flight HUD showing during the box):
-- "riding, flying, OR IN THE BOX SEQUENCE" is what this used to say, and what
-- setGrounded's `flightHudFrame.Visible = not grounded` actually implemented.
-- That third case is wrong now. Once the box became a real object in the
-- world carrying its own luck readout, everything in this frame during the
-- box window is either stale or duplicated: the distance countup has stopped,
-- the outcome text is about a release that already happened, the RELEASE
-- button controls nothing (doRelease refuses -- not mounted), and the luck
-- line reads the SAME number the box's own billboard is showing a few
-- hundred pixels away. See refreshFlightHud for where the condition lives now
-- and why it is not simply `not grounded`.
--
-- A plain full-screen, invisible-background Frame, not the ScreenGui itself:
-- returnHintLabel (and the money/tier
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

-- returnHintLabel USED TO BE HERE and is deliberately gone (see the written
-- report). It was a floating bottom-of-screen prompt that only appeared once
-- the reward sequence had fully resolved -- i.e. after the reveal panel had
-- already auto-hidden -- which put the player on an empty road being told to
-- click, as a second step separate from the reward they had just been shown.
--
-- There is no return prompt anywhere now. The reveal is a slime standing in
-- the world where the box was (see showSlimeReveal) and a primary click or tap
-- anywhere dismisses it and returns the player in one action -- the same
-- gesture they have just been using to press the box, so it needs no label.
-- The luckless landing has no reveal and needs no prompt either: it returns on
-- its own timer server-side (see LaunchServer's scheduleLucklessReturn).

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

-- Whether THIS client's own character is currently frozen -- Anchored, with
-- AutoRotate off -- which only happens (see LaunchServer.server.luau's
-- Heartbeat landing handler) between landing and a successful return: the
-- server keeps a landed player anchored all the way through the box and the
-- slime reveal, specifically so the Humanoid controller (and, on mobile,
-- tap-to-move) categorically cannot move them until they choose to leave.
-- Read directly off the character's own RootPart.Anchored (an ordinary
-- replicated BasePart property) rather than a second, locally tracked flag,
-- so this can never drift out of sync with the actual server-side freeze --
-- see refreshReturnAffordance and the click-anywhere listener further down,
-- both of which call this fresh rather than caching it.
--
-- DECLARED HERE, above the box block, rather than down with the rest of this
-- client's state where it used to live: releaseBoxCamera below is the one
-- place that decides whether the camera eases back to the pre-box view or
-- snaps out of Scriptable immediately, and "is there still a frozen character
-- standing where that view was framed" is exactly the question it asks.
local function characterIsFrozen(): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = humanoid and humanoid.RootPart
	return rootPart ~= nil and rootPart.Anchored
end

-- ===== Mystery box: A REAL PART IN THE WORLD, not a screen panel =====
--
-- This used to be a centre-screen Frame (boxFrame) with a title, a luck line,
-- a status line and a PRESS button. It read as a dialog asking a question, not
-- as a reward sitting in front of you -- so the whole panel is gone, and what
-- the player looks at now is an actual cube standing in front of their frozen
-- character with a large "?" on every face.
--
-- WHAT DID NOT CHANGE: the BoxStarted / BoxPress / BoxResult flow, in either
-- direction. No new remote exists, the server sends and receives exactly what
-- it did before, and every probability/delay still lives entirely server-side
-- (see LaunchServer's onBoxPress). This block is presentation only.
--
-- ENTIRELY CLIENT-SIDE AND NON-REPLICATING, the same way SlimeIdleClient/
-- SlimeUpgradeTagClient's own instances are: the part is created here, on this
-- client, parented into Workspace, and exists on no other client and on no
-- server. Nothing about it is trusted by anything, and no other player can see
-- it -- which is exactly right, since it is one player's own reward beat
-- happening at their own landing spot.
--
-- THE "?" ON ALL SIX FACES: confirmed working, with one structural caveat
-- worth stating because it drives the loop below -- a SurfaceGui renders on
-- exactly ONE face (its own Face property), so six faces means six
-- SurfaceGuis, not one with six faces selected. All six NormalIds (Front,
-- Back, Left, Right, Top, Bottom) are valid Face values on an ordinary Part
-- and each renders independently, so the marking is complete from every angle.
-- None of them is AlwaysOnTop, deliberately: that would draw the far faces'
-- "?" straight through the near ones and the cube would stop reading as solid.
local BOX_PART_NAME = "MysteryBoxLocal"
local BOX_FACES: { Enum.NormalId } = {
	Enum.NormalId.Front,
	Enum.NormalId.Back,
	Enum.NormalId.Left,
	Enum.NormalId.Right,
	Enum.NormalId.Top,
	Enum.NormalId.Bottom,
}

-- Luck colours, in the same vocabulary the deleted panel used: gold while the
-- box is live, hot orange the instant a press DOUBLES it (the escalation --
-- the number climbed and the box survived), bright green on the open.
local BOX_LUCK_COLOR_LIVE = Color3.new(1, 0.85, 0.2)
local BOX_LUCK_COLOR_DOUBLED = Color3.new(1, 0.55, 0.15)
local BOX_LUCK_COLOR_OPENED = Color3.new(0.4, 1, 0.5)

-- Everything below is nil/empty whenever no box exists, which is nearly
-- always -- see destroyWorldBox, the single teardown every cleanup path calls.
local boxPart: BasePart? = nil
local boxQuestionLabels: { TextLabel } = {}
local boxWorldLuckLabel: TextLabel? = nil
-- The box's UNDEFORMED placement and size, recomputed from the character every
-- frame (see updateBoxMotion) and held here so the shake has something exact
-- to return to -- every shake frame overwrites CFrame and Size outright, so
-- "rest" has to be a value this file owns, not the property's own last state.
local boxRestCFrame = CFrame.identity
local boxRestSize = Vector3.zero
-- The FLAT (horizontal, unit) direction from the box back toward the player,
-- written by boxRestCFrameForCharacter alongside boxRestCFrame. Kept as its
-- own value rather than read back off boxRestCFrame.LookVector, because that
-- CFrame carries the cube's three-quarter display tilt (see
-- BOX_WORLD_PITCH_DEGREES) and its LookVector is therefore NOT horizontal --
-- deriving the camera from it would rock the shot by the same 12 degrees the
-- box is cosmetically tipped by. This is the clean axis the box camera below
-- is built on.
local boxRestTowardPlayer = Vector3.new(0, 0, 1)

-- WHERE THE BOX GOES, derived entirely from the CHARACTER'S OWN CFrame -- no
-- world constant, no landing-spot lookup, no camera reference. Works at any
-- landing spot on the road and at any camera angle, because the only inputs
-- are the character's own position and the direction it is facing.
--
-- The look direction is FLATTENED to horizontal before use: the box must sit
-- level in front of the player regardless of any pitch/roll the character
-- happens to be carrying out of the flight pose, and a box tipped by the
-- character's own landing attitude would read as broken rather than placed.
-- (The server's own landing PivotTo is already level -- see LaunchServer's
-- Heartbeat landing handler -- so this is belt-and-braces, not a correction.)
local function boxRestCFrameForCharacter(): CFrame?
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not (rootPart and rootPart:IsA("BasePart")) then
		return nil
	end
	local rootCFrame = (rootPart :: BasePart).CFrame
	local look = rootCFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-4 then
		-- Degenerate only if the character is somehow facing straight up or
		-- down; -Z is the flight direction every landing faces anyway.
		flat = Vector3.new(0, 0, -1)
	end
	flat = flat.Unit
	boxRestTowardPlayer = -flat

	local centre = rootCFrame.Position
		+ flat * LaunchConfig.BOX_WORLD_DISTANCE_STUDS
		+ Vector3.new(0, LaunchConfig.BOX_WORLD_HEIGHT_OFFSET_STUDS, 0)
	-- Facing back TOWARD the player (centre - flat), then turned by the
	-- configured three-quarter tilt so the cube reads as a cube rather than a
	-- flat square -- see BOX_WORLD_YAW_DEGREES.
	return CFrame.lookAt(centre, centre - flat)
		* CFrame.Angles(
			math.rad(LaunchConfig.BOX_WORLD_PITCH_DEGREES),
			math.rad(LaunchConfig.BOX_WORLD_YAW_DEGREES),
			0
		)
end

-- ===== Box camera: the box alone, against sky =====
--
-- While a box exists the camera leaves the player's control and eases into a
-- low three-quarter hero shot -- underneath the cube, looking UP at it, with
-- the character behind the lens and the road below the bottom edge of the
-- frustum. See BOX_CAMERA_PITCH_DEGREES for why "below the bottom edge" is a
-- guarantee here and not an approximation.
--
-- THE CAMERA DOES NOT FOLLOW THE SHAKE -- deliberately, and this is the one
-- decision in this block worth arguing. Every frame it targets boxRestCFrame,
-- the box's UNDEFORMED placement, never the shaken CFrame actually written to
-- the part. Two reasons:
--   1. A camera rigidly locked to a box thrashing at BOX_SHAKE_FREQUENCY_HZ
--      (18) does not make the box look shaky -- it makes the box look STILL
--      and the entire world look shaky, because the box is the thing held
--      fixed in frame. The build would read as an earthquake, not as a box
--      about to burst, which inverts the whole point of it.
--   2. Full-screen judder at 18 Hz, on a loop the player runs hundreds of
--      times, is a genuine motion-sickness risk and not one worth taking for
--      an effect that reads better without it. Less exposure than it used to
--      be now the violent shake is a quarter-second thrash rather than the
--      whole wait, but the reasoning is unchanged.
-- A stable frame with a violently rattling object inside it is what actually
-- sells the build. If a camera shake is ever wanted it should be its own
-- small, independently-tuned offset, not a rigid lock to this one.
--
-- RESTORATION IS STRUCTURAL, NOT REMEMBERED. The camera lock's lifetime IS
-- the box's lifetime, enforced by there being exactly one acquire call site
-- (showWorldBox) and exactly one release call site (destroyWorldBox), and by
-- nothing else in this file touching CameraType while a box exists. Every
-- path that ends a box already funnels through destroyWorldBox -- that was
-- made true in the pass that built the box -- so every path that ends a box
-- restores the camera by construction, including ones nobody enumerated. A
-- path cannot forget to restore the camera without also forgetting to remove
-- the box, which is visible immediately.
--
-- READS Workspace.CurrentCamera LIVE rather than the `camera` upvalue this
-- file caches at startup. The flight's one-frame CFrame nudge can afford a
-- stale reference (worst case one frame is framed oddly); a MODE change
-- cannot -- leaving a camera Scriptable is a soft-lock, so this path must
-- always be talking to the camera that is actually current.
type BoxCameraPhase = "off" | "entering" | "held" | "returning"
local boxCameraPhase: BoxCameraPhase = "off"
local boxCameraPhaseStart = 0
-- The CFrame the CURRENT transition started from (captured at each phase
-- change) and the pre-box view to ease back to. The latter is captured only
-- on a FRESH acquire -- see acquireBoxCamera.
local boxCameraFrom = CFrame.identity
local boxCameraReturnCFrame = CFrame.identity

-- BUG FIX (see the written report -- camera bolting to the character on
-- dismiss). Set when a dismiss is waiting for the eased camera return to
-- finish before it fires ReturnToSwing.
--
-- THE BOLT WAS A SEQUENCING BUG, not a transition bug. Dismiss used to fire
-- the remote immediately, so the server teleported the player to their swing
-- ~one round trip in -- while the camera was still 0.4s from the end of an
-- ease toward boxCameraReturnCFrame, a view of the LANDING SPOT captured when
-- the box first appeared. The ease itself was fine; what was not is what
-- happened when it finished. Handing back to Custom hands the built-in
-- controller a camera pointing at an empty stretch of road with its subject
-- now thousands of studs away, and it slams across the map to catch up. That
-- is the snap -- it lands at the END of the return, not the start, and the
-- "easing back" seen afterwards is Roblox's own controller settling.
--
-- Deferring the remote until the return completes fixes it at the source: the
-- camera eases back to a view that still has the character in it, Custom takes
-- over with nothing to correct, and only then does the teleport happen -- an
-- ordinary cut, the same one every other teleport in this game already makes.
local returnPendingCameraSettle = false

-- Smoothstep: zero slope at both ends, so the push-in accelerates out of rest
-- and decelerates into the framing instead of starting and stopping abruptly.
local function easeInOut(t: number): number
	return t * t * (3 - 2 * t)
end

-- The framing itself, derived entirely from the box's own rest CFrame and the
-- flat toward-player axis -- so it frames the box identically regardless of
-- which way the player happened to land or where their camera was pointing.
--
-- THE CAMERA IS ON THE PLAYER'S SIDE, BEHIND THEM -- note the PLUS on
-- boxRestTowardPlayer. It looks DOWN-ROAD: over the character's shoulder,
-- through the box, out to the giant slime landmark on the horizon.
--
-- THAT DIRECTION IS THE WHOLE REASON THE CHARACTER IS HIDDEN. The landmark
-- sits at the far, most-negative-Z end of the road (see MapBuilder's own
-- placement) -- BEYOND the landing, in the direction the player was flying --
-- so the only view that has it behind the box is one shot from this side. And
-- from this side the character is unavoidably in frame: they stand only
-- BOX_WORLD_DISTANCE_STUDS (8) from the box, so any camera far enough back to
-- frame the box loosely has them squarely between the lens and it, and no
-- amount of height fixes that (raising the camera also drops the aim, and the
-- two converge -- they stay inside the frustum at every elevation). Hence
-- LocalTransparencyModifier, above: the shot is chosen for the backdrop and
-- the character is removed from it outright, rather than the framing being
-- bent around them.
local function boxCameraCFrame(): CFrame
	local boxPosition = boxRestCFrame.Position
	local pitch = math.rad(LaunchConfig.BOX_CAMERA_PITCH_DEGREES)
	local distance = LaunchConfig.BOX_CAMERA_DISTANCE_STUDS
	local eye = boxPosition
		+ boxRestTowardPlayer * (distance * math.cos(pitch))
		+ Vector3.new(0, -distance * math.sin(pitch), 0)
	return CFrame.lookAt(eye, boxPosition)
end

-- ONE OF EXACTLY TWO CALL SITES that ever touch CameraType in the box path.
-- Called from showWorldBox only.
local function acquireBoxCamera()
	local activeCamera = Workspace.CurrentCamera
	if not activeCamera then
		return
	end
	if boxCameraPhase == "off" then
		-- Captured ONLY on a fresh acquire. showWorldBox destroys any previous
		-- box first, which starts a return -- re-capturing here would then
		-- record the BOX framing itself as the view to restore to, and the
		-- camera would never find its way back to the player.
		boxCameraReturnCFrame = activeCamera.CFrame
	end
	boxCameraFrom = activeCamera.CFrame
	boxCameraPhase = "entering"
	boxCameraPhaseStart = os.clock()
	activeCamera.CameraType = Enum.CameraType.Scriptable
end

-- THE OTHER call site. Called from destroyWorldBox only -- see this block's
-- header for why that is the whole of the restoration guarantee.
--
-- ANIMATED OR INSTANT is decided from live state, not from which caller it
-- was: the eased return only makes sense if there is still a frozen character
-- standing where boxCameraReturnCFrame was framed. On a death/respawn,
-- dismount, or return-to-swing the character is gone or has moved, so easing
-- toward a stale view would be a slow pan to nowhere -- those snap straight
-- back to Custom instead. Deriving it this way means a new teardown path
-- added later gets the right behaviour without knowing this rule exists.
local function releaseBoxCamera()
	if boxCameraPhase == "off" or boxCameraPhase == "returning" then
		return
	end
	local activeCamera = Workspace.CurrentCamera
	if not activeCamera then
		boxCameraPhase = "off"
		return
	end
	if characterIsFrozen() then
		boxCameraFrom = activeCamera.CFrame
		boxCameraPhase = "returning"
		boxCameraPhaseStart = os.clock()
		return
	end
	boxCameraPhase = "off"
	activeCamera.CameraType = Enum.CameraType.Custom
end

-- Runs every frame from the same RenderStepped connection the box motion uses
-- (motion first -- it is what refreshes boxRestCFrame from the character, and
-- this reads it). Outlives the box itself: the return transition still has to
-- play after destroyWorldBox has already removed the part, which is why this
-- is gated on boxCameraPhase rather than on boxPart.
local function updateBoxCamera()
	if boxCameraPhase == "off" then
		return
	end
	local activeCamera = Workspace.CurrentCamera
	if not activeCamera then
		-- The camera this lock was taken on is no longer current. A brand-new
		-- CurrentCamera comes up Custom on its own, so there is nothing left to
		-- restore -- just drop the lock rather than writing to a dead instance.
		boxCameraPhase = "off"
		-- The deferred return still has to fire, though. Abandoning it here
		-- would leave a player who has already dismissed the reveal anchored on
		-- the road with nothing left on screen to click -- the InputBegan
		-- backstop would eventually rescue them, but only if they thought to
		-- try.
		if returnPendingCameraSettle then
			returnPendingCameraSettle = false
			returnToSwingRemote:FireServer()
		end
		return
	end

	local duration = LaunchConfig.BOX_CAMERA_TRANSITION_SECONDS
	local elapsed = os.clock() - boxCameraPhaseStart
	local t = if duration > 0 then math.clamp(elapsed / duration, 0, 1) else 1

	if boxCameraPhase == "returning" then
		activeCamera.CFrame = boxCameraFrom:Lerp(boxCameraReturnCFrame, easeInOut(t))
		if t >= 1 then
			-- THE handoff back to the player. Same mechanism FlightStarted uses
			-- (see its own comment): Roblox's Custom camera controller reads its
			-- starting distance/angle from wherever the camera CFrame currently
			-- is, so it continues smoothly from the view we just eased into
			-- rather than snapping to some canned default.
			boxCameraPhase = "off"
			activeCamera.CameraType = Enum.CameraType.Custom
			-- THE DEFERRED RETURN (see returnPendingCameraSettle). Fired here,
			-- after the handback, so the teleport can never land mid-ease and
			-- leave the built-in controller chasing a subject that has moved.
			if returnPendingCameraSettle then
				returnPendingCameraSettle = false
				returnToSwingRemote:FireServer()
			end
		end
		return
	end

	local target = boxCameraCFrame()
	if boxCameraPhase == "entering" then
		activeCamera.CFrame = boxCameraFrom:Lerp(target, easeInOut(t))
		if t >= 1 then
			boxCameraPhase = "held"
		end
		return
	end

	-- "held": pinned to the rest framing for as long as the box exists. Written
	-- every frame rather than once, so it tracks boxRestCFrame's own per-frame
	-- re-derivation from the character (see updateBoxMotion) instead of drifting
	-- away from it.
	activeCamera.CFrame = target
end

-- ===== Hiding the character for the shot =====
--
-- The box camera above shoots from the PLAYER'S side, looking down-road, so
-- the character is directly between the lens and the box. It is made
-- invisible rather than framed around, because the framing that would exclude
-- it is the one that also excludes the landmark (see boxCameraCFrame).
--
-- NOTHING IS MOVED. LocalTransparencyModifier only, never a reparent or a
-- CFrame write: boxRestCFrameForCharacter re-derives the box's own rest
-- placement from this character's CFrame EVERY FRAME (that per-frame read is
-- what closes the landing replication race -- see updateBoxMotion), so
-- relocating the character to get it out of shot would drag the box along
-- with it.
--
-- BASEPARTS AND DECALS BOTH. A Decal has its own LocalTransparencyModifier
-- and is NOT hidden by its part's -- miss them and the player's face hangs in
-- the air in front of the box. Roblox's own TransparencyController (the
-- first-person fade in the default camera scripts) caches exactly these two
-- classes for the same reason.
--
-- RE-APPLIED EVERY FRAME, NOT WRITTEN ONCE. Three independent reasons, any
-- one sufficient: (1) that same TransparencyController drives these instances
-- itself from the camera update at RenderPriority.Camera, and pushes them back
-- toward 0 in third person -- a single write from here could be undone before
-- the frame is even drawn. (2) The engine resets the property on assorted
-- replication events. (3) Accessories can finish replicating AFTER the box
-- already exists, so the set of instances to hide is not fixed at acquire
-- time. Re-walking the descendants each frame absorbs all three without
-- needing to know which one happened; the walk is a few dozen instances and
-- only runs while a box exists.
--
-- ORDERING IS WHY THAT WORKS, and this file already established the fact it
-- rests on: see RENDER_STEP_NAME's own comment further down, which documents
-- that a plain RunService.RenderStepped:Connect runs at Enum.RenderPriority.
-- Last -- AFTER the engine's own camera update at RenderPriority.Camera. This
-- update rides that same plain connection, so on every frame our write is the
-- last one before the frame renders.
--
-- THE CHARACTER IS CAPTURED, NOT RE-READ. hiddenCharacter holds the exact
-- Model that was hidden. If the player dies and respawns mid-box, the fresh
-- character is a DIFFERENT Model and this loop never touches it -- so it
-- cannot inherit invisibility even for one frame, no matter what order the
-- respawn and the teardown happen in.
local hiddenCharacter: Model? = nil

local function applyCharacterTransparency(character: Model, modifier: number)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			descendant.LocalTransparencyModifier = modifier
		end
	end
end

-- Called from showWorldBox only -- see releaseHiddenCharacter for the other
-- half of the pair.
local function acquireHiddenCharacter()
	local character = player.Character
	if not character then
		return
	end
	hiddenCharacter = character
	applyCharacterTransparency(character, 1)
end

-- Called from destroyWorldBox only. Restores to 0 rather than to a
-- remembered original: 0 is the property's own "no local modification"
-- default, and the value any of these instances would otherwise be carrying
-- is recomputed from scratch by TransparencyController on the very next frame
-- anyway (that is what makes first person work at all) -- so there is nothing
-- meaningful to remember, and no per-instance table to leak.
--
-- SAFE ON AN ALREADY-DESTROYED CHARACTER, which is the respawn case. Destroy
-- unparents every descendant as well as the Model itself, so GetDescendants
-- returns an EMPTY list and this loop does nothing at all -- which is the
-- correct outcome, since a destroyed rig has nothing left to make visible. If
-- the old character has not been destroyed yet (CharacterAdded can fire
-- first), the loop finds it intact and restores it normally. Either ordering
-- is fine, and hiddenCharacter is cleared before the loop either way, so
-- nothing holds a reference to a dead Model past this call.
local function releaseHiddenCharacter()
	local character = hiddenCharacter
	hiddenCharacter = nil
	if character then
		applyCharacterTransparency(character, 0)
	end
end

local function updateHiddenCharacter()
	local character = hiddenCharacter
	if not character then
		return
	end
	applyCharacterTransparency(character, 1)
end

-- ===== Suppressing the OTHER scripts' HUDs =====
--
-- BUG FIX (see the written report -- "the unnecessary screen"): gating this
-- file's own flightHudFrame was necessary but not sufficient, because
-- LaunchClient is not the only script drawing persistent UI. Two other
-- ScreenGuis sit on screen unconditionally and were still there through the
-- whole box sequence: ShopClient's "SWING SHOP" button and InventoryClient's
-- "INVENTORY" button, stacked in the top-right corner. Neither has any
-- business being pressable while the player is looking at a mystery box, and
-- between them they were the entire remaining interface.
--
-- BaseClient's money and swing-tier readouts are deliberately NOT in this
-- list -- see BOX_SUPPRESSED_HUD_NAMES.
--
-- ScreenGui.Enabled, NOT the children's Visible flags. Enabled is a separate
-- axis the owning script never touches, so this cannot disturb whatever state
-- those panels are in: a shop panel left open comes back open, a closed one
-- comes back closed, and neither ShopClient nor InventoryClient needs to know
-- this happens or grow a listener for it. Restoring is unconditionally
-- Enabled = true rather than a remembered value for exactly that reason --
-- both are created Enabled and neither script ever sets it.
local suppressedHuds: { ScreenGui } = {}

-- Called from showWorldBox only.
local function acquireSuppressedHuds()
	for _, hudName in LaunchConfig.BOX_SUPPRESSED_HUD_NAMES do
		local hud = playerGui:FindFirstChild(hudName)
		if hud and hud:IsA("ScreenGui") then
			(hud :: ScreenGui).Enabled = false
			table.insert(suppressedHuds, hud :: ScreenGui)
		end
	end
end

-- Called from destroyWorldBox only. Works off the captured list rather than
-- re-resolving the names, so it restores exactly what it disabled and cannot
-- enable something that was already off for an unrelated reason.
local function releaseSuppressedHuds()
	for _, hud in suppressedHuds do
		hud.Enabled = true
	end
	table.clear(suppressedHuds)
end

-- ===== Box motion: the knock, the thrash, and the burst =====
--
-- MOTION ONLY. Nothing here gates input or decides anything: boxActive and
-- doBoxPress's own cooldown are the only things that have ever governed
-- whether a press is sent, and nothing in this block touches either. The one
-- place motion costs the sequence any TIME at all is the thrash, which sits
-- between BoxResult(opened) and the burst -- see the phase table below and the
-- budget it has to fit in.
--
-- THE VIOLENCE BELONGS TO THE OPEN, NOT TO THE WAIT. An earlier pass ran one
-- rattle that built through the entire round trip and then resolved either
-- way. That spent the loudest motion in the game on a moment whose outcome was
-- still unknown, and -- since BOX_DOUBLE_CHANCE means most presses are fails --
-- made the ordinary, nothing-happened case the most dramatic thing on screen.
-- Now the size of the motion matches what actually happened:
--
--   NUDGE   -- fired on every press, from doBoxPress, before any result
--              exists. Starts at full energy and decays out over
--              BOX_NUDGE_SECONDS: a knock, not a struggle. On a FAIL this is
--              the whole animation -- the box was hit, it moved, it held --
--              and nothing further is started when BoxResult(false) lands.
--   THRASH  -- fired ONLY from BoxResult(opened), and legitimately a
--              prediction: by the time it starts, the server has already told
--              this client the box is coming apart. Ramps UP over
--              BOX_THRASH_SECONDS (see BOX_THRASH_BUILD_EXPONENT) straight
--              into the burst, which it hands off to itself.
--   BURST   -- unchanged, only later: it now begins BOX_THRASH_SECONDS after
--              the result instead of on the same frame.
--
-- THE OPEN TAIL MUST FIT IN REVEAL_BOX_TO_SLIME_DELAY_SECONDS. Thrash (0.25)
-- plus burst (0.3) is 0.55 against that constant's 0.6, so the box is gone
-- before the slime reveal takes the screen -- the same guarantee as before,
-- with less headroom. Raising either duration means re-checking that sum.
--
-- A single frame still tells the two outcomes apart, which was the original
-- point and survives the retune: on a fail there is a box, sitting there,
-- barely moving.
type BoxMotionPhase = "none" | "nudge" | "thrash" | "burst"
local boxMotionPhase: BoxMotionPhase = "none"
local boxMotionStart = 0

local function startBoxMotion(phase: BoxMotionPhase)
	boxMotionPhase = phase
	boxMotionStart = os.clock()
end

-- THE SINGLE TEARDOWN. Every path that used to hide boxFrame calls this
-- instead -- see hideFlightBoxRevealUI, the SlimeRevealed handler, and the
-- burst's own completion below. Safe to call with no box up (the common case),
-- and safe to call twice: Destroy takes the SurfaceGuis, the six "?" labels,
-- the luck billboard and the ClickDetector with it, since all of them are
-- children of the part.
-- ===== The reveal slime: the reward, in the world, where the box was =====
--
-- The slime used to be a centre-screen panel that appeared once the box had
-- burst. It is now an actual SlimeBuilder model standing at the box's own
-- position, on the box's own camera -- the camera does not move between the
-- two at all, so the burst and the thing that came out of it read as one
-- continuous event rather than a cut to a menu.
--
-- Its lifetime is the REWARD SCENE's, not the box's: it outlives the box by
-- design (the box bursts, the slime remains) and is torn down by
-- endRewardScene alongside the camera, the character's invisibility and the
-- suppressed HUDs. That single release point is what stops a slime being left
-- standing on the road -- the same class of bug as a camera left Scriptable,
-- and given the same fix.
local slimeRevealModel: Model? = nil
-- Where it hovers, and the scale SlimeBuilder gave it -- held here because the
-- entrance animates both and needs somewhere exact to animate TO. Rotation is
-- baked into the rest CFrame so the mesh's face (-Z, see SlimeBuilder's own
-- header) points at the camera.
local slimeRevealRestCFrame = CFrame.identity
local slimeRevealBuiltScale = 1
local slimeRevealStartClock = 0

local function destroySlimeReveal()
	local model = slimeRevealModel
	slimeRevealModel = nil
	if model then
		model:Destroy()
	end
end

-- THE BOX ONLY. It no longer releases the camera, the character's visibility
-- or the suppressed HUDs -- see endRewardScene below for why those moved.
--
-- The split is forced by the reveal: the box is destroyed when the burst
-- finishes, but the SLIME comes out of it and is looked at afterwards, on the
-- same camera, with the character still hidden. Releasing any of that at burst
-- time would snap the camera back to the player mid-reveal.
local function destroyWorldBox()
	local part = boxPart
	boxPart = nil
	boxQuestionLabels = {}
	boxWorldLuckLabel = nil
	boxMotionPhase = "none"
	if part then
		part:Destroy()
	end
end

-- THE SINGLE RELEASE POINT for everything the reward sequence takes over: the
-- box, the reveal slime, the camera, the character's visibility and the other
-- scripts' HUDs. Every one of those is acquired in exactly one place
-- (showWorldBox) and released in exactly one place (here), so a teardown path
-- cannot restore some of them and forget the rest -- it either calls this or
-- it does not.
--
-- MOVED OUT OF destroyWorldBox, which used to be that point. It stopped being
-- viable when the slime arrived: the box is destroyed the moment the burst
-- ends, and the reveal is looked at afterwards on the same camera with the
-- character still hidden, so "the box is gone" is no longer the same event as
-- "the scene is over". The structure is unchanged -- one acquire, one release
-- -- only which function holds it.
--
-- Safe to call with nothing up (the common case) and safe to call twice:
-- every release below already no-ops on an absent subject.
local function endRewardScene()
	-- Cleared FIRST: a scene torn down by anything other than a dismiss (death,
	-- respawn, dismount, a fresh landing) must not leave a deferred
	-- ReturnToSwing armed to fire at whoever owns the camera next.
	-- dismissRevealAndReturn re-arms it immediately after calling this, which is
	-- the only path that should.
	returnPendingCameraSettle = false
	destroyWorldBox()
	destroySlimeReveal()
	releaseBoxCamera()
	releaseHiddenCharacter()
	releaseSuppressedHuds()
end

-- THE PRESS. The server answers on the same frame now (see LaunchServer's
-- onBoxPress -- the roll no longer sits behind a delay), so there is no wait to
-- represent here: the box takes its knock and the result is already on its way
-- back.
--
-- THE LOCAL COOLDOWN IS A COURTESY, NOT THE RATE LIMIT. The real one is
-- server-side and unchanged in force: onBoxPress refuses any press arriving
-- while box.pending is set, and that flag is now cleared by its own
-- BOX_PRESS_COOLDOWN_SECONDS timer. Mirroring the same constant here just
-- means a normal player's presses are never silently dropped by that guard --
-- a modified client that skips this check gains nothing but rejections.
--
-- A CLOCK, NOT A LATCH, and that distinction is load-bearing. This used to be
-- a boolean (`boxWaitingForResult`) cleared only by BoxResult arriving, which
-- was safe only while the client could not out-run the server: with the result
-- now immediate the client is free again long before the server's own cooldown
-- expires, so a press could be refused server-side, no BoxResult would ever
-- come, and a boolean latch would stay set forever -- an unpressable box. A
-- timestamp cannot get stuck: worst case a press near the boundary is dropped
-- (one dead click, no state), and the next one is fine.
local lastBoxPressClock = -math.huge

local function doBoxPress()
	if not boxActive then
		return
	end
	if os.clock() - lastBoxPressClock < LaunchConfig.BOX_PRESS_COOLDOWN_SECONDS then
		return
	end
	lastBoxPressClock = os.clock()
	-- The knock, on the same line as the remote fire. On a fail this is the
	-- entire animation; on an open the thrash takes over when BoxResult lands.
	startBoxMotion("nudge")
	boxPressRemote:FireServer()
end

-- The luck readout, ON the box rather than in a panel: a billboard floating
-- just above the cube, so the number and the object holding it are one thing
-- the eye takes in together. AlwaysOnTop, unlike the "?" faces -- a number you
-- can only half-read is useless, and this is the one element that must survive
-- the box expanding past it during a burst.
local function setBoxLuck(luck: number, color: Color3)
	local label = boxWorldLuckLabel
	if not label then
		return
	end
	label.Text = string.format("Luck x%s", LuckCurve.formatLuck(luck))
	label.TextColor3 = color
end

-- Builds the cube, its six "?" faces, its luck billboard and its ClickDetector
-- in one shot, fully off-tree, and only parents it into Workspace once every
-- child already exists -- the same "populate then reveal" ordering LaunchServer
-- uses for the Remotes folder, for the same reason: nothing should ever be able
-- to observe a half-built box.
local function buildWorldBox(): BasePart
	local part = Instance.new("Part")
	part.Name = BOX_PART_NAME
	part.Shape = Enum.PartType.Block
	part.Size = Vector3.one * LaunchConfig.BOX_WORLD_SIZE_STUDS
	part.Color = LaunchConfig.BOX_WORLD_COLOR
	part.Material = LaunchConfig.BOX_WORLD_MATERIAL
	-- Anchored so nothing physical can move it, CanCollide false so it can
	-- never push, block or trap the frozen player standing in front of it (or
	-- collide with the road bands it is standing over). CanQuery STAYS TRUE --
	-- that is what the ClickDetector's own raycast needs to see the part at
	-- all; CanCollide has nothing to do with clickability. CanTouch off since
	-- nothing listens for touches on it.
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = true
	part.CanTouch = false
	-- SHADOW ON, and it is load-bearing rather than decoration: the box hangs
	-- in mid-air with nothing holding it up, and a shadow on the road beneath
	-- it is what tells the eye how far off the ground it actually is. Without
	-- one the hover reads as the box drifting on a flat backdrop.
	--
	-- It lands where it needs to. Nothing in this project configures Lighting,
	-- so Roblox's defaults apply -- ClockTime 14 with GlobalShadows on, a sun
	-- around 40 degrees up -- which throws the shadow of a centre sitting ~6.5
	-- studs up onto the road roughly 7 studs from directly beneath it. The
	-- road is RUNWAY_WIDTH_STUDS (240) across, so there is no landing position
	-- or lane where that offset can walk the shadow off the road's edge, and
	-- with the camera now level (see BOX_CAMERA_PITCH_DEGREES) the ground
	-- immediately below the box sits just under it in frame rather than out of
	-- shot. Fades out on its own during the burst -- a fully transparent part
	-- casts no shadow, so nothing has to unwind this.
	part.CastShadow = true

	for _, face in BOX_FACES do
		local surface = Instance.new("SurfaceGui")
		surface.Name = string.format("Question%s", face.Name)
		surface.Face = face
		surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		surface.PixelsPerStud = LaunchConfig.BOX_WORLD_QUESTION_PIXELS_PER_STUD
		-- Unlit: the "?" must read identically whichever way this face happens
		-- to be turned relative to the sun, since the box is tilted and shaking.
		surface.LightInfluence = 0
		surface.Adornee = part
		surface.Parent = part

		local questionLabel = Instance.new("TextLabel")
		questionLabel.Name = "Question"
		questionLabel.Size = UDim2.fromScale(1, 1)
		questionLabel.BackgroundTransparency = 1
		questionLabel.BorderSizePixel = 0
		questionLabel.Font = Enum.Font.GothamBlack
		questionLabel.TextScaled = true
		questionLabel.TextColor3 = LaunchConfig.BOX_WORLD_QUESTION_COLOR
		questionLabel.TextStrokeTransparency = 0.35
		questionLabel.Text = "?"
		questionLabel.Parent = surface

		table.insert(boxQuestionLabels, questionLabel)
	end

	local luckGui = Instance.new("BillboardGui")
	luckGui.Name = "BoxLuck"
	luckGui.Size = UDim2.fromOffset(
		LaunchConfig.BOX_WORLD_LUCK_LABEL_WIDTH_PIXELS,
		LaunchConfig.BOX_WORLD_LUCK_LABEL_HEIGHT_PIXELS
	)
	-- StudsOffsetWorldSpace, not StudsOffset: the number must sit above the
	-- box in the WORLD, not above it in camera space, or it would swing around
	-- the cube as the player turns the camera.
	luckGui.StudsOffsetWorldSpace = Vector3.new(0, LaunchConfig.BOX_WORLD_LUCK_LABEL_HEIGHT_STUDS, 0)
	luckGui.AlwaysOnTop = true
	luckGui.Adornee = part
	luckGui.Parent = part

	local luckLabel = Instance.new("TextLabel")
	luckLabel.Name = "BoxLuckText"
	luckLabel.Size = UDim2.fromScale(1, 1)
	luckLabel.BackgroundTransparency = 1
	luckLabel.BorderSizePixel = 0
	luckLabel.Font = Enum.Font.GothamBlack
	luckLabel.TextScaled = true
	luckLabel.TextColor3 = BOX_LUCK_COLOR_LIVE
	luckLabel.TextStrokeTransparency = 0.3
	luckLabel.Text = ""
	luckLabel.Parent = luckGui
	boxWorldLuckLabel = luckLabel

	-- HOW A PRESS IS TRIGGERED NOW that the PRESS button is gone: you click or
	-- tap THE BOX. A ClickDetector is the one input that covers mouse and touch
	-- with the same gesture and no on-screen chrome at all -- Roblox raises
	-- MouseClick for a touch tap on the part exactly as it does for a left
	-- click, and it fires locally for a locally-created part. Space still works
	-- too (see the InputBegan handler below, unchanged), so keyboard players
	-- keep the shortcut they had.
	--
	-- No conflict with the click-anywhere-to-return listener: that one is gated
	-- on `grounded`, which is false for the whole box sequence and only flips
	-- true on ResetReady, long after the box is gone.
	local clickDetector = Instance.new("ClickDetector")
	clickDetector.Name = "BoxPressDetector"
	clickDetector.MaxActivationDistance = LaunchConfig.BOX_WORLD_CLICK_DISTANCE_STUDS
	clickDetector.Parent = part
	clickDetector.MouseClick:Connect(function()
		doBoxPress()
	end)

	return part
end

-- Called once per BoxStarted. Tears down any previous reward scene first --
-- defensive only (every path out of one already does), but it makes "a second
-- box, or a leftover slime, can never exist" structural rather than a property
-- of the paths that happen to run first.
local function showWorldBox(luck: number)
	endRewardScene()

	local part = buildWorldBox()
	boxPart = part
	boxRestSize = part.Size
	-- Placed here so the box is already in the right spot on the frame it
	-- appears rather than for one frame at wherever the previous one stood.
	-- Not authoritative, though: updateBoxMotion re-derives this from the
	-- character every single frame (see its own comment on the landing-CFrame
	-- replication race), so a nil character here costs at most one frame, not
	-- a misplaced box.
	local rest = boxRestCFrameForCharacter()
	if rest then
		boxRestCFrame = rest
	end
	-- The UNHOVERED rest pose, not boxHoverCFrame (which is declared further
	-- down, alongside the motion it feeds). Costs at most one frame at up to
	-- BOX_HOVER_AMPLITUDE_STUDS off the hover's current height -- a third of a
	-- stud, before the box has even been parented -- and updateBoxMotion takes
	-- over on the very next frame.
	part.CFrame = boxRestCFrame
	setBoxLuck(luck, BOX_LUCK_COLOR_LIVE)

	startBoxMotion("none")
	part.Parent = Workspace

	-- THE ONLY PLACE the reward scene is acquired -- camera, character
	-- invisibility and HUD suppression together. Last, after boxRestCFrame and
	-- boxRestTowardPlayer are both settled, since the framing is derived from
	-- them. Paired with endRewardScene's three releases, which is the single
	-- point every teardown path funnels through.
	acquireBoxCamera()
	acquireHiddenCharacter()
	acquireSuppressedHuds()
end

local BOX_SHAKE_TAU = 2 * math.pi

-- ===== The hover: the box's MOVING rest pose =====
--
-- Not a motion phase, and deliberately not one. Every phase below builds on
-- top of whatever this returns for the current frame, instead of any of them
-- owning the box's placement outright: at rest the box is exactly this, a
-- press adds the rattle's jitter and tilt on top of it, a fail decays that
-- back down onto it, and the burst expands out of it. That is what makes the
-- hover and the shake compose rather than fight -- there is no frame on which
-- two systems disagree about where the box is, because only one of them ever
-- answers that question and the others are offsets from its answer.
--
-- Driven by the ABSOLUTE clock, exactly like applyBoxShake below and for the
-- same reason: nothing here restarts on a phase change, so there is no
-- discontinuity to snap across when one begins or ends. The bob is a plain
-- sine about the resting height; the spin is unbounded and monotonic, which
-- is fine -- it feeds CFrame.Angles, and every face carries the same "?".
--
-- The BOX CAMERA does not track any of this (it frames boxRestCFrame, not
-- this) -- see its own block on why following the box's own motion would read
-- as the world moving rather than the box.
-- PARAMETERISED so the reveal slime can hover on exactly the same clock as
-- the box did -- identical bob and spin, applied to whatever rest pose is
-- passed in. Behaviour for the box is unchanged: boxHoverCFrame below is the
-- same call it always made, just with the rest CFrame handed in rather than
-- closed over.
local function hoverCFrame(rest: CFrame): CFrame
	local now = os.clock()
	local period = LaunchConfig.BOX_HOVER_PERIOD_SECONDS
	local bob = if period > 0
		then LaunchConfig.BOX_HOVER_AMPLITUDE_STUDS * math.sin(BOX_SHAKE_TAU * now / period)
		else 0
	local spin = math.rad(LaunchConfig.BOX_HOVER_SPIN_DEGREES_PER_SECOND * now)
	return CFrame.new(rest.Position + Vector3.new(0, bob, 0))
		* rest.Rotation
		* CFrame.Angles(0, spin, 0)
end

local function boxHoverCFrame(): CFrame
	return hoverCFrame(boxRestCFrame)
end

-- Builds the reveal slime and starts its entrance. THE ONLY PLACE a reveal
-- slime is created; destroySlimeReveal (via endRewardScene) is the only place
-- one is removed.
--
-- PLACED AT THE BOX'S OWN REST POSITION. boxRestCFrame still holds it: the
-- burst destroys the part but nothing overwrites that value afterwards
-- (updateBoxMotion early-returns once boxPart is nil), and the box camera is
-- framed off the same value -- so the slime lands exactly where the box was,
-- centred in a shot that has not moved and will not move until the player
-- dismisses it.
--
-- FACING: the mesh's face axis is -Z (see SlimeBuilder's header, which
-- measured it rather than assuming), and CFrame.lookAt aims -Z at its target,
-- so looking at boxRestTowardPlayer -- the flat axis from the box back toward
-- the player, which is also where the camera sits -- points the slime's face
-- at the camera with no extra correction.
-- The slime's pose during the entrance: the LIVE hover pose, dropped straight
-- down by `rise` studs in WORLD space. Two things matter about it.
--
-- It reads the hover, so the spin and bob are already running while the slime
-- is still rising and growing -- at rise = 0 this is exactly what
-- updateSlimeReveal settles to, so the entrance ends on the hover rather than
-- cutting to it.
--
-- And the drop is applied to the hover's POSITION, after its rotation, rather
-- than as a local offset -- so the slime always rises straight up regardless
-- of which way the spin currently has it turned.
local function entranceCFrame(rise: number): CFrame
	local hover = hoverCFrame(slimeRevealRestCFrame)
	return CFrame.new(hover.Position - Vector3.new(0, rise, 0)) * hover.Rotation
end

local function showSlimeReveal(slime: SlimeData.Slime, isNew: boolean)
	destroySlimeReveal()

	local model = SlimeBuilder.build(slime.color, SlimeConfig.SLIME_REVEAL_WIDTH_STUDS)
	-- Captured because the entrance animates scale and Model:ScaleTo takes an
	-- ABSOLUTE scale -- animating it means multiplying THIS, not stacking a
	-- second ScaleTo on top of the one build() already applied.
	slimeRevealBuiltScale = model:GetScale()

	local centre = boxRestCFrame.Position
	slimeRevealRestCFrame = CFrame.lookAt(centre, centre + boxRestTowardPlayer)

	-- The name/tier/NEW readout, on the slime rather than in a panel -- same
	-- shape and reasoning as the box's own luck billboard it replaces:
	-- AlwaysOnTop so it is never lost behind the body it labels, fixed pixel
	-- size so it stays readable whatever the camera is doing, and world-space
	-- offset so it sits above the slime rather than orbiting it.
	local labelGui = Instance.new("BillboardGui")
	labelGui.Name = "SlimeRevealLabel"
	labelGui.Size = UDim2.fromOffset(
		SlimeConfig.SLIME_REVEAL_LABEL_WIDTH_PIXELS,
		SlimeConfig.SLIME_REVEAL_LABEL_HEIGHT_PIXELS
	)
	labelGui.StudsOffsetWorldSpace = Vector3.new(0, SlimeConfig.SLIME_REVEAL_LABEL_HEIGHT_STUDS, 0)
	labelGui.AlwaysOnTop = true
	labelGui.Adornee = model.PrimaryPart
	labelGui.Parent = model.PrimaryPart

	-- NEW/Duplicate, tier, then name -- top to bottom. The tier line keeps the
	-- deleted panel's two rarity signals: its own tier colour, and a TextSize
	-- that grows per tier so a Divine reads literally bigger than a Common
	-- rather than just differently coloured. The asterisk flourish comes with
	-- it, unchanged.
	local badgeLabel = Instance.new("TextLabel")
	badgeLabel.Name = "NewBadge"
	badgeLabel.Size = UDim2.new(1, 0, 0.24, 0)
	badgeLabel.Position = UDim2.fromScale(0, 0)
	badgeLabel.BackgroundTransparency = 1
	badgeLabel.BorderSizePixel = 0
	badgeLabel.Font = Enum.Font.GothamBold
	badgeLabel.TextScaled = true
	badgeLabel.TextStrokeTransparency = 0.4
	badgeLabel.Text = if isNew then "* NEW! *" else "Duplicate"
	badgeLabel.TextColor3 = if isNew then Color3.new(0.3, 1, 0.4) else Color3.new(0.6, 0.6, 0.65)
	badgeLabel.Parent = labelGui

	local starCount = math.max(0, slime.tier - 4)
	local flourish = string.rep("*", starCount)
	local tierText = string.upper(slime.tierName)
	if flourish ~= "" then
		tierText = flourish .. " " .. tierText .. " " .. flourish
	end

	local tierLabel = Instance.new("TextLabel")
	tierLabel.Name = "SlimeTier"
	tierLabel.Size = UDim2.new(1, 0, 0.44, 0)
	tierLabel.Position = UDim2.fromScale(0, 0.24)
	tierLabel.BackgroundTransparency = 1
	tierLabel.BorderSizePixel = 0
	tierLabel.Font = Enum.Font.GothamBlack
	-- NOT TextScaled, unlike its neighbours: an explicit per-tier TextSize is
	-- the whole point (see SLIME_TIER_TEXT_SIZE_BASE/STEP), and TextScaled
	-- would flatten every tier back to the same fitted height.
	tierLabel.TextSize = SlimeConfig.SLIME_TIER_TEXT_SIZE_BASE + (slime.tier - 1) * SlimeConfig.SLIME_TIER_TEXT_SIZE_STEP
	tierLabel.TextColor3 = slime.tierColor
	tierLabel.TextStrokeTransparency = 0.2
	tierLabel.Text = tierText
	tierLabel.Parent = labelGui

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "SlimeName"
	nameLabel.Size = UDim2.new(1, 0, 0.28, 0)
	nameLabel.Position = UDim2.fromScale(0, 0.7)
	nameLabel.BackgroundTransparency = 1
	nameLabel.BorderSizePixel = 0
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextStrokeTransparency = 0.5
	nameLabel.Text = slime.name
	nameLabel.Parent = labelGui

	-- Populate-then-reveal, same as the box: nothing is ever in Workspace
	-- half-built. The first frame's placement is written here too so it never
	-- appears for one frame at the template's own origin.
	slimeRevealStartClock = os.clock()
	slimeRevealModel = model
	model:ScaleTo(slimeRevealBuiltScale * 0.001)
	-- THE HOVER POSE, not slimeRevealRestCFrame. The hover's spin runs off the
	-- absolute clock and is continuous, so a slime built at an arbitrary moment
	-- inherits whatever phase that clock is at -- placing it at the bare rest
	-- CFrame (facing the camera) meant it faced forward for the whole entrance
	-- and then snapped to the live spin phase the instant the entrance handed
	-- over to the hover. Starting from the hover instead means the two are the
	-- same pose at every u, including u = 0 and u = 1, so there is nothing to
	-- snap between. See updateSlimeReveal, which applies the rise the same way.
	model:PivotTo(entranceCFrame(SlimeConfig.SLIME_REVEAL_RISE_STUDS))
	model.Parent = Workspace
end

-- THE ENTRANCE, then the hover. Runs every frame from the same RenderStepped
-- connection the box motion and camera use.
--
-- Rising AND growing together, over SLIME_REVEAL_ENTRANCE_SECONDS: it starts
-- at nothing, SLIME_REVEAL_RISE_STUDS below its resting height, and arrives at
-- full size on the spot the box was. That combination is what reads as coming
-- OUT of something rather than fading in on top of it -- a pure scale-up would
-- look like it had always been there and was simply revealed, and a pure rise
-- would look like it had been hiding under the road.
--
-- Eased with the same smoothstep the camera transition uses, so it decelerates
-- into its resting pose instead of stopping dead.
--
-- Once the entrance is over it hovers on hoverCFrame -- the SAME bob and spin,
-- on the same absolute clock, the box was using a moment earlier. That
-- continuity is deliberate: the object changed, the motion did not.
--
-- The idle BREATHING animation does not reach this slime, and is not made to:
-- SlimeIdleClient discovers its subjects by walking Workspace for
-- Base_<UserId> folders and the landmark by name, so animating this one would
-- mean either parenting a reveal prop into a player's base or teaching that
-- file about this one. The hover is what "sits there hovering" needs.
local function updateSlimeReveal()
	local model = slimeRevealModel
	if not model then
		return
	end

	local duration = SlimeConfig.SLIME_REVEAL_ENTRANCE_SECONDS
	local elapsed = os.clock() - slimeRevealStartClock
	local u = if duration > 0 then math.clamp(elapsed / duration, 0, 1) else 1

	if u < 1 then
		local eased = easeInOut(u)
		-- Never exactly zero: Model:ScaleTo rejects a scale of 0, and a model
		-- scaled to nothing has no meaningful pivot to grow back out of.
		model:ScaleTo(slimeRevealBuiltScale * math.max(eased, 0.001))
		model:PivotTo(entranceCFrame(SlimeConfig.SLIME_REVEAL_RISE_STUDS * (1 - eased)))
		return
	end

	model:ScaleTo(slimeRevealBuiltScale)
	model:PivotTo(hoverCFrame(slimeRevealRestCFrame))
end

-- Fades the six "?" faces in step with the body during a burst -- without
-- this the box would dissolve out from behind its own markings and leave six
-- floating question marks hanging in the air for the last few frames.
local function setBoxQuestionTransparency(transparency: number)
	for _, questionLabel in boxQuestionLabels do
		questionLabel.TextTransparency = transparency
		questionLabel.TextStrokeTransparency = math.max(0.35, transparency)
	end
end

-- `energy` is the 0-1 envelope; the oscillation itself is driven by the
-- ABSOLUTE clock, not by time-since-this-phase-started. That's what makes the
-- rattle -> settle handoff seamless: the settle inherits whatever point of the
-- cycle the rattle was at, so the box keeps shaking and merely loses
-- amplitude, instead of snapping back to a zero crossing at the handoff.
--
-- WORLD SPACE, and the same three-frequency spread the screen panel used, now
-- across three axes instead of two: the positional jitter is added to the
-- HOVERING rest POSITION and the box's current rest rotation is applied after
-- it, so the shake never inherits the cube's three-quarter tilt and never
-- collapses into a single diagonal slide along it. Each axis runs at its own
-- multiple of one frequency with its own phase offset (1x/1.7x/1.3x on
-- position, 0.8x/1.9x/1.15x on rotation) -- an irrational-ish spread is what
-- reads as "rattling" rather than "oscillating".
--
-- ON TOP OF THE HOVER, not instead of it (see boxHoverCFrame): the box keeps
-- floating and turning underneath the shake, and at energy 0 this collapses to
-- exactly the hover pose -- so a nudge decaying to nothing and the "none" phase
-- resuming are the same placement, with nothing to snap between.
--
-- SIZE IS PASSED IN, not read from config here: the nudge and the thrash are
-- the same motion at two very different scales (see the phase table above), so
-- the caller supplies which pair of amplitude/tilt constants applies and this
-- stays the one place the actual oscillation is defined.
local function applyBoxShake(energy: number, peakAmplitudeStuds: number, peakRotationDegrees: number)
	local part = boxPart
	if not part then
		return
	end
	local hover = boxHoverCFrame()
	local w = BOX_SHAKE_TAU * LaunchConfig.BOX_SHAKE_FREQUENCY_HZ * os.clock()
	local amplitude = peakAmplitudeStuds * energy
	local jitter = Vector3.new(
		amplitude * math.sin(w),
		amplitude * 0.6 * math.sin(w * 1.7 + 1.1),
		amplitude * 0.8 * math.sin(w * 1.3 + 2.3)
	)
	local tilt = math.rad(peakRotationDegrees) * energy
	part.CFrame = CFrame.new(hover.Position + jitter)
		* hover.Rotation
		* CFrame.Angles(
			tilt * math.sin(w * 0.8 + 0.5),
			tilt * math.sin(w * 1.9 + 2.0),
			tilt * math.sin(w * 1.15 + 4.1)
		)
	part.Size = boxRestSize
end

local function updateBoxMotion()
	local part = boxPart
	if not part then
		return
	end

	-- Re-derived from the character EVERY frame rather than captured once at
	-- BoxStarted (see the written report): the server's landing PivotTo and its
	-- BoxStarted fire on the same Heartbeat, and there is no guarantee the
	-- character's final landed CFrame has replicated to this client by the time
	-- that remote arrives -- capturing once could place the box off a
	-- still-mid-flight position several studs short of the landing spot. The
	-- character is Anchored for the whole box sequence, so re-reading it every
	-- frame is a no-op the instant it settles, and self-corrects that race
	-- rather than racing it. Falls back to the last known rest CFrame if the
	-- character is momentarily absent (a respawn tears the box down anyway --
	-- see hideFlightBoxRevealUI).
	local rest = boxRestCFrameForCharacter()
	if rest then
		boxRestCFrame = rest
	end

	if boxMotionPhase == "none" then
		-- "none" is NOT "still" -- it is the hover, running on its own (see
		-- boxHoverCFrame). This is the only phase where the hover is the whole
		-- of the box's motion rather than the base the rest is added to.
		part.CFrame = boxHoverCFrame()
		part.Size = boxRestSize
		return
	end

	local elapsed = os.clock() - boxMotionStart

	if boxMotionPhase == "nudge" then
		-- Starts at FULL energy and decays out. No ramp, deliberately: the
		-- knock IS the impact, and an impact that faded in would read as the
		-- box starting to move by itself. At u = 1 the energy reaches 0, which
		-- is exactly the hover pose, so the handoff back to "none" is
		-- continuous rather than a snap.
		local duration = LaunchConfig.BOX_NUDGE_SECONDS
		local u = if duration > 0 then elapsed / duration else 1
		if u >= 1 then
			startBoxMotion("none")
			part.CFrame = boxHoverCFrame()
			part.Size = boxRestSize
			return
		end
		applyBoxShake(
			1 - u,
			LaunchConfig.BOX_NUDGE_AMPLITUDE_STUDS,
			LaunchConfig.BOX_NUDGE_ROTATION_DEGREES
		)
		return
	end

	if boxMotionPhase == "thrash" then
		local duration = LaunchConfig.BOX_THRASH_SECONDS
		local u = if duration > 0 then elapsed / duration else 1
		if u >= 1 then
			-- HANDS OFF TO THE BURST ITSELF rather than waiting to be told.
			-- BoxResult already fired and is not coming again, so this phase
			-- is the only thing that knows when the thrash is over -- and
			-- chaining here keeps the two as one continuous event instead of
			-- two client-side timers that could drift apart.
			startBoxMotion("burst")
			return
		end
		-- Ramps UP into the burst, opposite to the nudge above: the box is
		-- losing its fight with whatever is inside it. See
		-- BOX_THRASH_BUILD_EXPONENT for why the ramp is curved rather than
		-- linear.
		applyBoxShake(
			u ^ LaunchConfig.BOX_THRASH_BUILD_EXPONENT,
			LaunchConfig.BOX_THRASH_AMPLITUDE_STUDS,
			LaunchConfig.BOX_THRASH_ROTATION_DEGREES
		)
		return
	end

	-- "burst": the cube blows outward while spinning and fading to nothing,
	-- then is destroyed -- it reads as coming apart, not as swelling, because
	-- it never comes back. Linear in u on all of scale, spin and fade, so the
	-- expansion is fastest-looking at the start, where the size change is
	-- largest relative to what it was.
	local duration = LaunchConfig.BOX_OPEN_BURST_SECONDS
	local u = if duration > 0 then elapsed / duration else 1
	if u >= 1 then
		destroyWorldBox()
		return
	end
	local scale = 1 + (LaunchConfig.BOX_OPEN_BURST_SCALE - 1) * u
	part.Size = boxRestSize * scale
	-- LIFTED BY HALF THE GROWTH, so the cube's underside stays put and the
	-- whole burst travels UPWARD and outward. Two reasons, and the first is
	-- not cosmetic: BOX_WORLD_HEIGHT_OFFSET_STUDS only buys the resting cube
	-- ~2 studs of clearance over the road, and a burst that more than doubles
	-- the cube's size about its own CENTRE would drive its lower half straight
	-- through the road bands and be occluded by them for the last frames of
	-- the animation. This cancels all but the tilt's own share of the downward
	-- growth (the lift matches the axis-aligned half-height, the tilted corner
	-- reaches ~25% further -- see BOX_WORLD_HEIGHT_OFFSET_STUDS's arithmetic),
	-- which at BOX_OPEN_BURST_SCALE leaves the lowest corner still ~1 stud
	-- clear of the road at the end of the burst. It also reads better -- things
	-- that burst go up, they don't grow symmetrically in place.
	--
	-- Launched from the HOVER pose, like every other phase, so the cube starts
	-- coming apart from exactly where it was floating on the previous frame
	-- rather than jumping back to a static rest position first.
	local hover = boxHoverCFrame()
	part.CFrame = CFrame.new(hover.Position + Vector3.new(0, (scale - 1) * boxRestSize.Y * 0.5, 0))
		* hover.Rotation
		* CFrame.Angles(0, math.rad(LaunchConfig.BOX_OPEN_BURST_SPIN_DEGREES * u), 0)
	part.Transparency = u
	setBoxQuestionTransparency(u)
end

-- ITS OWN CONNECTION, not an addition to the flight/riding render loop below.
-- That loop is the character-and-camera path and is gated on flightActive/
-- mounted; this box is on an unrelated schedule and the two have no
-- frame-ordering relationship at all -- the box only ever exists while the
-- character is frozen, i.e. while that loop is doing nothing to it. Both
-- halves early-return to nothing whenever no box (and no box camera
-- transition) is running, which is nearly always.
--
-- ORDER MATTERS, and only in one direction: updateBoxMotion is what refreshes
-- boxRestCFrame from the character each frame, and updateBoxCamera frames
-- itself off that value -- so motion first, always, or the camera spends every
-- frame chasing the previous one's placement.
RunService.RenderStepped:Connect(function()
	updateBoxMotion()
	updateSlimeReveal()
	updateBoxCamera()
	-- Last, and specifically at this connection's default Last priority --
	-- see the hidden-character block on why it has to land after the default
	-- camera scripts' own per-frame LocalTransparencyModifier pass.
	updateHiddenCharacter()
end)

-- The SLIME REVEAL PANEL used to be built here -- a centre-screen Frame with
-- a tier-coloured UIStroke border, a NEW/Duplicate badge, a tier line and a
-- name line, plus the in-panel dismiss prompt added with it. All of it is
-- gone: the reveal is a real slime standing in the world where the box was
-- (see showSlimeReveal), and its name/tier/NEW text rides on a billboard above
-- that slime. Deleted with the panel: slimeRevealFrame, slimeRevealCorner,
-- slimeRevealBorder, newBadgeLabel, slimeTierLabel, slimeNameLabel and
-- revealDismissLabel.

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

-- ===== The two screen-space things `grounded` alone cannot decide =====
--
-- `grounded` is a TWO-valued client mirror of a FIVE-valued server state (see
-- LaunchServer's LoopState: grounded | riding | inflight | box | cooldown).
-- It is a faithful mirror of exactly one bit -- "is the server willing to
-- accept a return from me" -- and both refreshes below need one bit more than
-- that, the same missing bit: whether the box sequence is running. `boxActive`
-- already carries it, exactly, and is maintained through one setter.
--
-- So neither of these gets a new state variable. A third client-side state
-- enum would have to be kept in sync with the server's own for no new
-- information -- `not grounded and not boxActive` IS "riding, flying, or
-- cooling down after a luckless landing", which is precisely the window each
-- of these means something in. See the written report.
local function refreshFlightHud()
	-- NOT `not grounded` (see flightHudFrame's own construction comment): the
	-- reward sequence lives inside `not grounded`, and everything in this
	-- frame is stale or duplicated there. A luckless landing never starts a
	-- reward sequence, so `cooldown` still shows it -- which is what keeps "No
	-- luck (short of the road)" on screen for RESET_DELAY, unchanged.
	--
	-- BUG FIX -- and it is a correction to the previous fix, not an addition:
	-- this read `not boxActive`, which is the WRONG FLAG for this gate.
	-- boxActive means "the box is still pressable" and goes false the instant
	-- BoxResult reports an open -- so the whole flight HUD popped back on for
	-- the thrash, the burst AND the entire slime reveal window, right up until
	-- ResetReady. That is most of the reward sequence, and it is where the
	-- "Luck x700!" line, the outcome text, the bar track and the RELEASE
	-- button were coming back from. rewardSequenceActive spans the thing this
	-- gate actually cares about: BoxStarted through to the sequence being
	-- fully resolved.
	flightHudFrame.Visible = not grounded and not rewardSequenceActive
end

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
	refreshFlightHud()
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
	endRewardScene()
	revealDismissable = false
	-- DEFERRED IF THE CAMERA IS EASING, immediate otherwise. endRewardScene's
	-- releaseBoxCamera above decides which: it only animates when there is
	-- still a frozen character for the captured view to be framing, and takes
	-- the instant path otherwise -- in which case there is no ease to wait for
	-- and nothing to defer behind. Either way the remote fires exactly once.
	if boxCameraPhase == "returning" then
		returnPendingCameraSettle = true
	else
		returnToSwingRemote:FireServer()
	end
end

local function hideFlightBoxRevealUI()
	setBoxActive(false)
	setRewardSequenceActive(false)
	endRewardScene()
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
	refreshFlightHud()
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
			doBoxPress()
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
			doBoxPress()
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
	if isPointerTrigger and characterIsFrozen() then
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

-- BUG FIX (see the written report -- mid-flight death): clears every readout
-- a flight leaves behind -- distance/luck (distanceLabel doubles as both),
-- the distance sub-readout, the live multiplier, and the frozen outcome
-- text -- back to the same values they hold before a player has ever
-- released. Without this, a value left behind by an ABANDONED flight (see
-- resetFlightState's own comment) would sit on an INVISIBLE flightHudFrame
-- indefinitely and get revealed again, unchanged, the next time
-- setGrounded(false) shows it -- which is exactly the "Luck x100,000!" /
-- "Perfect! 2.00x" / "2960.0 studs" still on screen after a respawn. Reset
-- text matches each label's own pre-flight default (see their construction
-- above). One place, called from resetReadyRemote's handler below, the only
-- caller either kind of reset (landing or death/disconnect cancellation)
-- goes through.
local function resetFlightHudText()
	distanceLabel.Text = "Time your release!"
	distanceLabel.TextColor3 = Color3.new(1, 1, 1)
	distanceSubLabel.Text = ""
	multiplierLabel.Text = "0.75x"
	multiplierLabel.TextColor3 = Color3.new(1, 1, 1)
	outcomeLabel.Text = ""
end

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
	resetFlightHudText()
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
	showWorldBox(luck)
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
		setBoxLuck(luck, BOX_LUCK_COLOR_OPENED)
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
		startBoxMotion("thrash")
	else
		setBoxLuck(luck, BOX_LUCK_COLOR_DOUBLED)
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
	destroyWorldBox()

	-- Up, but NOT yet dismissable, and saying so by staying quiet: there is no
	-- prompt until the lockout below expires, so nothing ever promises a click
	-- that would currently be swallowed.
	revealDismissable = false
	showSlimeReveal(slime, isNew)

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
	local armedModel = slimeRevealModel
	task.delay(SlimeConfig.REVEAL_DISMISS_LOCKOUT_SECONDS, function()
		if slimeRevealModel ~= armedModel or not armedModel then
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
