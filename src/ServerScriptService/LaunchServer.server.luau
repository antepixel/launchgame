--!strict
-- Authoritative launch loop: charge timing, launch velocity, landing detection, and
-- distance measurement all happen HERE, driven only by the server's own physics
-- simulation and its own clock. The client only ever sends two content-free signals
-- ("I'm holding" / "I let go") -- it never sends a power value or a distance value,
-- so there is nothing for a modified client to lie about. See onRelease and the
-- Heartbeat landing check below for exactly where that trust boundary sits.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local LaunchConfig = require(ReplicatedStorage.Config.LaunchConfig)

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
local chargeStartRemote = makeRemote("ChargeStart")
local releaseRemote = makeRemote("Release")
-- Server -> client: server-computed results only.
local launchResultRemote = makeRemote("LaunchResult")
local resetReadyRemote = makeRemote("ResetReady")

local launchPoint = Workspace:WaitForChild("LaunchPoint") :: BasePart
local ball = Workspace:WaitForChild("LaunchBall") :: BasePart

ball.Shape = Enum.PartType.Ball
ball.Size = Vector3.new(LaunchConfig.BALL_RADIUS * 2, LaunchConfig.BALL_RADIUS * 2, LaunchConfig.BALL_RADIUS * 2)
ball.CustomPhysicalProperties = PhysicalProperties.new(
	1, -- density (irrelevant to launch speed -- we set velocity directly, not impulse)
	LaunchConfig.BALL_FRICTION,
	LaunchConfig.BALL_ELASTICITY
)

type LoopState = "idle" | "charging" | "inflight" | "cooldown"

local state: LoopState = "idle"
local chargeStartClock: number? = nil
local flightStartClock: number? = nil
local stillForSeconds = 0
local activePlayer: Player? = nil

local function resetBall()
	ball.Anchored = true
	ball.AssemblyLinearVelocity = Vector3.zero
	ball.AssemblyAngularVelocity = Vector3.zero
	ball.CFrame = launchPoint.CFrame + Vector3.new(0, LaunchConfig.BALL_RADIUS + 0.5, 0)
	state = "idle"
	chargeStartClock = nil
	flightStartClock = nil
	stillForSeconds = 0
	activePlayer = nil
end

resetBall()

local function launchDirection(): Vector3
	local angle = math.rad(LaunchConfig.RAMP_ANGLE_DEGREES)
	-- Forward is -Z (Roblox's default character-forward axis), tilted up by the ramp angle.
	return Vector3.new(0, math.sin(angle), -math.cos(angle)).Unit
end

local function onChargeStart(player: Player)
	if state ~= "idle" then
		return -- one shared ball for this prototype: ignore a second player mid-cycle
	end
	state = "charging"
	activePlayer = player
	-- The ONLY thing "charge power" is ever derived from: the server's own wall-clock
	-- reading, taken the instant the server itself receives this event. The client
	-- cannot backdate or fake this timestamp.
	chargeStartClock = os.clock()
end

local function onRelease(player: Player)
	if state ~= "charging" or player ~= activePlayer or chargeStartClock == nil then
		return
	end
	-- Power = elapsed SERVER time between the two remotes, clamped. No numeric value
	-- from the client ever enters this calculation -- a modified client sending
	-- Release instantly or never at all can only shorten or lengthen its OWN hold,
	-- exactly like a legitimate player would, and the server measures whatever
	-- actually happened rather than being told what happened.
	local elapsed = math.clamp(os.clock() - chargeStartClock, 0, LaunchConfig.MAX_CHARGE_TIME)
	local power = elapsed / LaunchConfig.MAX_CHARGE_TIME
	local speed = LaunchConfig.MIN_LAUNCH_SPEED + (LaunchConfig.MAX_LAUNCH_SPEED - LaunchConfig.MIN_LAUNCH_SPEED) * power

	ball.Anchored = false
	-- CRITICAL anti-spoof line: force network ownership of the ball to the server.
	-- An unanchored BasePart's physics ownership otherwise auto-assigns to whichever
	-- client is nearest, and Roblox trusts a physics-owning client's replicated
	-- position -- that's a standard exploit vector (a client that owns a part can
	-- just teleport it and the server accepts the replication). Pinning ownership to
	-- the server (nil) means the SERVER's own physics engine simulates this ball;
	-- no client input can move it except through the two content-free remotes above.
	ball:SetNetworkOwner(nil)
	ball.AssemblyLinearVelocity = launchDirection() * speed

	state = "inflight"
	flightStartClock = os.clock()
	stillForSeconds = 0
	chargeStartClock = nil
end

chargeStartRemote.OnServerEvent:Connect(onChargeStart)
releaseRemote.OnServerEvent:Connect(onRelease)

Players.PlayerRemoving:Connect(function(player)
	if player == activePlayer then
		resetBall()
	end
end)

RunService.Heartbeat:Connect(function(dt: number)
	if state ~= "inflight" or flightStartClock == nil then
		return
	end

	if LaunchConfig.AIR_DRAG_COEFFICIENT > 0 then
		local velocity = ball.AssemblyLinearVelocity
		ball.AssemblyLinearVelocity = velocity - velocity * LaunchConfig.AIR_DRAG_COEFFICIENT * dt
	end

	local speed = ball.AssemblyLinearVelocity.Magnitude
	if speed < LaunchConfig.LANDED_VELOCITY_THRESHOLD then
		stillForSeconds += dt
	else
		stillForSeconds = 0
	end

	local flightElapsed = os.clock() - flightStartClock
	local landed = stillForSeconds >= LaunchConfig.LANDED_STILL_TIME or flightElapsed >= LaunchConfig.MAX_FLIGHT_TIME
	if not landed then
		return
	end

	-- THE MEASUREMENT: server reads its own simulated ball's Position (never a
	-- client-reported number) and the fixed LaunchPoint Position, both server-side
	-- Instances, and computes horizontal displacement between them. This is the
	-- entire "distance" stat -- there is no other code path that produces it.
	local delta = ball.Position - launchPoint.Position
	local distance = Vector3.new(delta.X, 0, delta.Z).Magnitude

	local landedPlayer = activePlayer
	state = "cooldown"
	if landedPlayer then
		launchResultRemote:FireClient(landedPlayer, distance)
	end

	task.delay(LaunchConfig.RESET_DELAY, function()
		resetBall()
		if landedPlayer and landedPlayer.Parent then
			resetReadyRemote:FireClient(landedPlayer)
		end
	end)
end)
