--!strict
-- Input + UI only. This script never computes power or distance -- it fires two
-- content-free remotes (ChargeStart/Release) and displays whatever the server
-- sends back. The power meter fills locally between those two remotes purely as
-- visual feedback; if it drifts a frame or two out of sync with the server's own
-- timer under latency, that's cosmetic only -- the server's independent measurement
-- (see LaunchServer.server.luau) is what actually determines the launch.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local LaunchConfig = require(ReplicatedStorage.Config.LaunchConfig)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local chargeStartRemote = remotesFolder:WaitForChild("ChargeStart") :: RemoteEvent
local releaseRemote = remotesFolder:WaitForChild("Release") :: RemoteEvent
local launchResultRemote = remotesFolder:WaitForChild("LaunchResult") :: RemoteEvent
local resetReadyRemote = remotesFolder:WaitForChild("ResetReady") :: RemoteEvent

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
distanceLabel.Text = "Hold to launch"
distanceLabel.Parent = screenGui

local meterBackground = Instance.new("Frame")
meterBackground.Name = "PowerMeterBackground"
meterBackground.AnchorPoint = Vector2.new(0.5, 1)
meterBackground.Position = UDim2.new(0.5, 0, 0.85, 0)
meterBackground.Size = UDim2.new(0, 320, 0, 32)
meterBackground.BackgroundColor3 = Color3.new(0.1, 0.1, 0.1)
meterBackground.BackgroundTransparency = 0.3
meterBackground.BorderSizePixel = 0
meterBackground.Visible = false
meterBackground.Parent = screenGui

local meterCorner = Instance.new("UICorner")
meterCorner.CornerRadius = UDim.new(0, 8)
meterCorner.Parent = meterBackground

local meterFill = Instance.new("Frame")
meterFill.Name = "PowerMeterFill"
meterFill.Size = UDim2.new(0, 0, 1, 0)
meterFill.BackgroundColor3 = Color3.new(1, 0.6, 0.1)
meterFill.BorderSizePixel = 0
meterFill.Parent = meterBackground

local meterFillCorner = Instance.new("UICorner")
meterFillCorner.CornerRadius = UDim.new(0, 8)
meterFillCorner.Parent = meterFill

local launchButton = Instance.new("TextButton")
launchButton.Name = "LaunchButton"
launchButton.AnchorPoint = Vector2.new(0.5, 1)
launchButton.Position = UDim2.new(0.5, 0, 0.97, 0)
launchButton.Size = UDim2.new(0, 200, 0, 60)
launchButton.BackgroundColor3 = Color3.new(0.85, 0.25, 0.1)
launchButton.Font = Enum.Font.GothamBold
launchButton.TextScaled = true
launchButton.TextColor3 = Color3.new(1, 1, 1)
launchButton.Text = "HOLD TO LAUNCH"
launchButton.Parent = screenGui

local buttonCorner = Instance.new("UICorner")
buttonCorner.CornerRadius = UDim.new(0, 10)
buttonCorner.Parent = launchButton

-- ===== State =====
local canCharge = true
local isCharging = false
local chargeStartClock: number? = nil
local heartbeatConnection: RBXScriptConnection? = nil

local function stopMeterUpdates()
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
end

local function beginCharge()
	if not canCharge or isCharging then
		return
	end
	isCharging = true
	chargeStartClock = os.clock()
	meterBackground.Visible = true
	meterFill.Size = UDim2.new(0, 0, 1, 0)
	distanceLabel.Text = "Charging..."
	chargeStartRemote:FireServer()

	stopMeterUpdates()
	heartbeatConnection = RunService.Heartbeat:Connect(function()
		if not chargeStartClock then
			return
		end
		local elapsed = os.clock() - chargeStartClock
		local fraction = math.clamp(elapsed / LaunchConfig.MAX_CHARGE_TIME, 0, 1)
		meterFill.Size = UDim2.new(fraction, 0, 1, 0)
	end)
end

local function endCharge()
	if not isCharging then
		return
	end
	isCharging = false
	canCharge = false
	chargeStartClock = nil
	stopMeterUpdates()
	meterBackground.Visible = false
	distanceLabel.Text = "Flying..."
	releaseRemote:FireServer()
end

-- GuiButton Mouse* events fire for touch taps too (Roblox synthesizes them), so this
-- single pair covers mouse, touch, and gamepad activation of the on-screen button.
launchButton.MouseButton1Down:Connect(beginCharge)
launchButton.MouseButton1Up:Connect(endCharge)

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end
	if input.KeyCode == Enum.KeyCode.F then
		beginCharge()
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessedEvent)
	if input.KeyCode == Enum.KeyCode.F then
		endCharge()
	end
end)

launchResultRemote.OnClientEvent:Connect(function(distance: number)
	distanceLabel.Text = string.format("%.1f studs", distance)
end)

resetReadyRemote.OnClientEvent:Connect(function()
	canCharge = true
	distanceLabel.Text = "Hold to launch"
end)
