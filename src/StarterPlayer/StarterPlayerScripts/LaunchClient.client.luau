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

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera :: Camera

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local releaseRemote = remotesFolder:WaitForChild("Release") :: RemoteEvent
local flightStartedRemote = remotesFolder:WaitForChild("FlightStarted") :: RemoteEvent
local resetReadyRemote = remotesFolder:WaitForChild("ResetReady") :: RemoteEvent
local boxStartedRemote = remotesFolder:WaitForChild("BoxStarted") :: RemoteEvent
local boxPressRemote = remotesFolder:WaitForChild("BoxPress") :: RemoteEvent
local boxResultRemote = remotesFolder:WaitForChild("BoxResult") :: RemoteEvent
local slimeRevealedRemote = remotesFolder:WaitForChild("SlimeRevealed") :: RemoteEvent
local ridingAssignedRemote = remotesFolder:WaitForChild("RidingAssigned") :: RemoteEvent

local swingPivot = Workspace:WaitForChild("SwingPivot") :: BasePart
local swingSeatPart = Workspace:WaitForChild("SwingSeat") :: BasePart

-- Mirrors LaunchServer's swingPhase()/swingTheta() exactly -- same shared
-- constants, same clock. Kept in this one script rather than a shared module
-- since it's a handful of small pure functions and this project keeps ONE
-- tuning module, not a library of shared math helpers.
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

local function riderCFrame(seatPosition: Vector3): CFrame
	local standPosition = seatPosition + Vector3.new(0, 2, 0)
	return CFrame.lookAt(standPosition, standPosition + Vector3.new(0, 0, -1))
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
		return LaunchConfig.SWEET_SPOT_MULTIPLIER
	end
	local t = 1 - (distanceFromSweetSpot - halfWidth) / (0.5 - halfWidth)
	t = math.clamp(t, 0, 1)
	return LaunchConfig.WORST_MULTIPLIER + (LaunchConfig.EDGE_MULTIPLIER - LaunchConfig.WORST_MULTIPLIER) * t
end

local function inSweetSpot(phase: number): boolean
	return circularPhaseDistance(phase, LaunchConfig.SWEET_SPOT_PHASE) <= LaunchConfig.SWEET_SPOT_WIDTH / 2
end

-- Mirrors LaunchServer's trajectoryPosition exactly -- same shared distance/arc
-- height numbers, received once in FlightStarted below, not recomputed locally.
local function trajectoryPosition(startPosition: Vector3, distance: number, archHeight: number, u: number): Vector3
	local horizontal = startPosition + Vector3.new(0, 0, -distance * u)
	local heightOffset = archHeight * 4 * u * (1 - u)
	return horizontal + Vector3.new(0, heightOffset, 0)
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
local MAX_FLIGHT_PITCH = math.rad(25)
local function trajectoryPitch(distance: number, archHeight: number, u: number): number
	local verticalRate = archHeight * 4 * (1 - 2 * u)
	return math.clamp(math.atan2(verticalRate, distance), -MAX_FLIGHT_PITCH, MAX_FLIGHT_PITCH)
end

local function trajectoryCFrame(startPosition: Vector3, distance: number, archHeight: number, u: number): CFrame
	local position = trajectoryPosition(startPosition, distance, archHeight, u)
	local pitch = trajectoryPitch(distance, archHeight, u)
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

-- True once this client has been told (via RidingAssigned) that it's the one
-- shared rider -- gates whether THIS client positions its own character on the
-- swing seat. Without this, every connected client would try to sit its own
-- character on the same seat, not just the one the server actually considers
-- "riding." Set once, true for the rest of the session (this prototype's rider
-- slot is never reassigned to someone else once claimed).
local isRider = false

-- ===== UI =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LaunchHud"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

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
distanceLabel.Parent = screenGui

-- The bar track: a fixed vertical strip. The moving indicator's Y POSITION inside
-- it (not its size) is the swing position -- "the bar IS the swing position."
local barTrack = Instance.new("Frame")
barTrack.Name = "SwingBarTrack"
barTrack.AnchorPoint = Vector2.new(1, 0.5)
barTrack.Position = UDim2.new(0.97, 0, 0.5, 0)
barTrack.Size = UDim2.new(0, 36, 0, 360)
barTrack.BackgroundColor3 = Color3.new(0.1, 0.1, 0.1)
barTrack.BackgroundTransparency = 0.25
barTrack.BorderSizePixel = 0
barTrack.Parent = screenGui

local barTrackCorner = Instance.new("UICorner")
barTrackCorner.CornerRadius = UDim.new(0, 8)
barTrackCorner.Parent = barTrack

-- Sweet-spot band: a static highlight at the TOP of the track (fill = 1 is the
-- forward extreme of the arc -- see LaunchConfig.SWEET_SPOT_PHASE). Its height is
-- computed from SWEET_SPOT_WIDTH using the same sine relationship as the server's
-- circularPhaseDistance check, so it visually represents the actual accepted
-- window, not an approximation of it.
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
	sweetBand.BackgroundTransparency = 0.35
	sweetBand.BorderSizePixel = 0
	sweetBand.ZIndex = 2
	sweetBand.Parent = barTrack

	local sweetBandCorner = Instance.new("UICorner")
	sweetBandCorner.CornerRadius = UDim.new(0, 8)
	sweetBandCorner.Parent = sweetBand
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

-- Live multiplier readout, right above the bar. Updated every frame alongside
-- the indicator (same RenderStepped loop below) -- normal styling for the
-- gradual-ramp range, a distinct bigger/brighter look when in the sweet spot.
local multiplierLabel = Instance.new("TextLabel")
multiplierLabel.Name = "MultiplierReadout"
multiplierLabel.AnchorPoint = Vector2.new(1, 1)
multiplierLabel.Position = UDim2.new(0.97, 0, 0.5, -190)
multiplierLabel.Size = UDim2.new(0, 120, 0, 40)
multiplierLabel.BackgroundTransparency = 1
multiplierLabel.Font = Enum.Font.GothamBold
multiplierLabel.TextScaled = true
multiplierLabel.TextColor3 = Color3.new(1, 1, 1)
multiplierLabel.TextStrokeTransparency = 0.4
multiplierLabel.Text = "0.75x"
multiplierLabel.Parent = screenGui

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
releaseButton.Parent = screenGui

local releaseButtonCorner = Instance.new("UICorner")
releaseButtonCorner.CornerRadius = UDim.new(0, 10)
releaseButtonCorner.Parent = releaseButton

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

-- ===== State =====
local canRelease = true

local function doRelease()
	-- BUG FIX (see written report): also refuse while a PREVIOUS flight's local
	-- animation is still counting up. canRelease alone isn't enough to prevent
	-- this -- ResetReady and this client's own flight-completion are governed by
	-- two independently-timed things (the server's RESET_DELAY countdown, and
	-- this client's own render loop reaching u=1), so under enough latency
	-- ResetReady could arrive and re-enable canRelease before flightActive had
	-- naturally cleared. Firing a second Release in that window would overwrite
	-- the still-displaying flight's distance/duration/start data with the new
	-- one's, abandoning the first flight's true final number mid-count.
	if not canRelease or flightActive then
		return
	end
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

-- Space does double duty: release the swing normally, or press the box when
-- one's up -- never both at once, since boxActive and canRelease can't be
-- simultaneously true (see resetReadyRemote's guard below).
UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end
	if input.KeyCode == Enum.KeyCode.Space then
		if boxActive then
			doBoxPress()
		else
			doRelease()
		end
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
	isRider = true
end)

RunService.RenderStepped:Connect(function()
	local phase = swingPhase()

	-- The swing itself always swings, for every viewer, whether or not anyone
	-- is riding it right now -- matches "it just swings, forever" regardless of
	-- a rider. Every connected client computes and shows this identically; it's
	-- cheap, pure math, no reason to gate it to just the rider's own client.
	local theta = swingTheta(phase)
	local seatPosition = swingSeatPosition(theta)
	swingSeatPart.CFrame = CFrame.new(seatPosition) * CFrame.Angles(theta, 0, 0)

	-- BUG FIX (see written report): this used to be the SERVER repositioning the
	-- rider every Heartbeat and replicating the result -- arriving at whatever
	-- rate Roblox batches property replication (well under 60Hz), which read as
	-- stutter. Now the assigned rider's own client (isRider, set once by
	-- RidingAssigned) positions its OWN character locally, every RenderStepped,
	-- from the exact same swing math -- full render-rate smoothness, no network
	-- dependency. Gated on canRelease (not just isRider) so this doesn't run
	-- during the brief post-landing cooldown window, when the character should
	-- still be standing at the landing spot, not already back on the swing.
	if isRider and canRelease and not flightActive then
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
			-- Landed: swap the live countup for the final result -- distance AND
			-- the luck it earned, together, since the luck IS the result of the
			-- launch (see the written report). Server already computed luck at
			-- release from the same landing Z the character is now standing at
			-- (see LaunchServer's bandLuckForLandingZ) -- this is purely display,
			-- nothing here can change or re-derive the value. Held on screen for
			-- the rest of RESET_DELAY (unchanged), same as the plain distance
			-- readout was before.
			if flightLuck > 0 then
				distanceLabel.Text = string.format("%.1f studs  --  Luck x%s!", flightDistance, LuckCurve.formatLuck(flightLuck))
				distanceLabel.TextColor3 = Color3.new(1, 0.85, 0.2)
			else
				distanceLabel.Text = string.format("%.1f studs  --  No luck (short of the road)", flightDistance)
				distanceLabel.TextColor3 = Color3.new(1, 1, 1)
			end
			flightActive = false
			return
		end

		-- Count the distance UP live -- horizontal progress is exactly linear in
		-- u for this trajectory, so this number always matches exactly how far
		-- along the flight the character visibly is, not a decoupled animation.
		distanceLabel.Text = string.format("%.1f studs", flightDistance * u)
		return
	end

	if not canRelease then
		return
	end
	local fill = fillFraction(phase)
	barIndicator.Position = UDim2.new(0.5, 0, 1 - fill, 0)

	if inSweetSpot(phase) then
		multiplierLabel.Text = "2x!"
		multiplierLabel.TextColor3 = Color3.new(0.2, 1, 0.35)
	else
		multiplierLabel.Text = string.format("%.2fx", launchMultiplier(phase))
		multiplierLabel.TextColor3 = Color3.new(1, 1, 1)
	end
end)
