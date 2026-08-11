--!strict
-- The client half of the sound system, and the only place that owns audio which
-- is not tied to one specific gameplay moment. Four jobs, all of them things no
-- other script should have to know about:
--
--   1. Receive the server's world-sound broadcasts and play them positionally.
--   2. Receive private per-player confirmations (the collect) and play them 2D.
--   3. Put a click on EVERY GuiButton in the game, centrally, without any of the
--      fourteen button construction sites being edited.
--   4. The mute toggle, and the conveyor's ambient loop.
--
-- Everything else -- the flight rush, the reward chain, the purchase
-- confirmations -- is played from the script that already owns that moment,
-- because those need the moment's own data (speed, tier, success) and routing
-- them through here would mean inventing a second message for something the
-- owning script already knows.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local SoundConfig = require(ReplicatedStorage.Config.SoundConfig)
local SoundPlayer = require(ReplicatedStorage.SoundPlayer)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ===== SoundService.RespectFilteringEnabled, SET EXPLICITLY rather than left
-- at whatever the default is.
--
-- Every Sound in this game is created by a LocalScript (see SoundPlayer's
-- header -- the server creates none). With this property false, Roblox's legacy
-- behaviour replicates a client's Sound:Play() outward, which would mean every
-- player hearing every other player's button clicks, purchase chimes and collect
-- confirmations -- the exact failure this system's 2D/3D split exists to
-- prevent. Setting it true keeps client-initiated playback local, which is what
-- makes "2D means only I hear it" actually true rather than merely intended.
--
-- Written from the client because it is a local playback policy; the server
-- never plays anything, so it has no stake in this value.
SoundService.RespectFilteringEnabled = true

-- Builds the four SoundGroups under one master, on first touch. Done eagerly
-- here so the master group exists before the mute toggle below can be pressed,
-- rather than appearing only once some other sound happens to play first.
local masterGroup = SoundPlayer.masterGroup()

--============================ Server -> client ============================--
-- Bounded waits, matching BaseClient's own reasoning: SoundBroadcast parents
-- this folder only after both remotes exist, so finding the folder is enough,
-- but the folder itself may not exist yet if this script wins the race against
-- that server module. A timeout rather than an unbounded WaitForChild so a
-- genuinely broken server surfaces as a warning instead of an infinite yield.
local REMOTES_WAIT_TIMEOUT_SECONDS = 10
local soundRemotes = ReplicatedStorage:WaitForChild("SoundRemotes", REMOTES_WAIT_TIMEOUT_SECONDS)
if soundRemotes then
	local worldSoundRemote = soundRemotes:WaitForChild("WorldSound", REMOTES_WAIT_TIMEOUT_SECONDS) :: RemoteEvent?
	local playerSoundRemote = soundRemotes:WaitForChild("PlayerSound", REMOTES_WAIT_TIMEOUT_SECONDS) :: RemoteEvent?

	if worldSoundRemote then
		-- Positional. Every client gets every broadcast; this client's own
		-- rolloff decides whether it hears anything (see SoundBroadcast's
		-- header on why the culling is not done server-side).
		--
		-- The arguments are validated despite coming from the server -- not out
		-- of distrust, but because SoundPlayer's resolve() is the single place
		-- that decides what a bad key does, and letting a malformed payload reach
		-- it as a non-string would error there instead of warning once.
		worldSoundRemote.OnClientEvent:Connect(function(key: string, position: Vector3)
			if typeof(key) ~= "string" or typeof(position) ~= "Vector3" then
				return
			end
			SoundPlayer.playAt(key, position)
		end)
	end

	if playerSoundRemote then
		-- Private and unpositioned: this only ever arrives for something this
		-- player themselves did.
		playerSoundRemote.OnClientEvent:Connect(function(key: string)
			if typeof(key) ~= "string" then
				return
			end
			SoundPlayer.play2D(key)
		end)
	end
else
	warn(string.format(
		"[SoundClient] SoundRemotes never appeared after %d seconds -- world sounds and collect confirmations will not play this session. Local sounds (UI, flight, reward) are unaffected.",
		REMOTES_WAIT_TIMEOUT_SECONDS
	))
end

--=========================== Every button, once ===========================--
-- ONE connection point for all fourteen GuiButton construction sites (the shop's
-- open/close/buy, the inventory's open/close/row actions, the upgrade strips over
-- the slot slimes, the launch HUD's release and dismount, the dev panel). None of
-- those files is edited to get a click sound; they simply create buttons, as they
-- already did.
--
-- Activated, not MouseButton1Click: Activated fires for mouse, touch and gamepad
-- alike, which is what a click sound should follow. MouseButton1Click would go
-- silent on every touch device.
--
-- CONNECTED PER BUTTON AND NEVER DISCONNECTED, deliberately: the connection is
-- owned by the button instance, so it dies when the button does. The panels here
-- build their rows once and toggle Visible rather than rebuilding, but the
-- inventory does rebuild rows on refresh -- and a destroyed button's Activated
-- connection is collected with it, so there is nothing to clean up.
local function wireButton(instance: Instance)
	if instance:IsA("GuiButton") then
		instance.Activated:Connect(function()
			SoundPlayer.play2D("UI_BUTTON_CLICK")
		end)
	end
end

playerGui.DescendantAdded:Connect(wireButton)
for _, descendant in playerGui:GetDescendants() do
	wireButton(descendant)
end

--=========================== The conveyor loop ===========================--
-- The map's one always-on sound. Attached to each of the two belt halves
-- MapBuilder builds (BeltNear / BeltFar inside MapBlockout), so it is genuinely
-- positional and fades out as the player walks up the spur into their plot.
--
-- Rescan-on-appearance rather than a one-shot lookup at startup, for exactly the
-- reason ConveyorScroll gives for the same problem: this is a client script and
-- MapBuilder is a server script, with no guaranteed order between them, so the
-- belts may not exist yet when this runs.
local MAP_FOLDER_NAME = "MapBlockout"
local BELT_NAMES = { "BeltNear", "BeltFar" }

local attachedBelts: { [BasePart]: true } = {}

local function attachBeltLoop(part: Instance)
	if not part:IsA("BasePart") or attachedBelts[part] then
		return
	end
	local isBelt = false
	for _, name in BELT_NAMES do
		if part.Name == name then
			isBelt = true
			break
		end
	end
	if not isBelt then
		return
	end
	attachedBelts[part] = true
	-- No handle kept: this loop lives exactly as long as the belt part does,
	-- and the belt is permanent map dressing. Destroying the part takes its
	-- Sound with it, which is the same "teardown by parentage" the collect pads
	-- already rely on.
	SoundPlayer.startLoop("WORLD_CONVEYOR_LOOP", part)
end

local function watchForBelts()
	local mapFolder = Workspace:FindFirstChild(MAP_FOLDER_NAME)
	if not mapFolder then
		return false
	end
	mapFolder.ChildAdded:Connect(attachBeltLoop)
	for _, child in mapFolder:GetChildren() do
		attachBeltLoop(child)
	end
	return true
end

if not watchForBelts() then
	-- The map folder itself is not up yet. One ChildAdded on Workspace, dropped
	-- as soon as it resolves -- cheaper and less fragile than polling.
	local connection: RBXScriptConnection
	connection = Workspace.ChildAdded:Connect(function(child)
		if child.Name == MAP_FOLDER_NAME and watchForBelts() then
			connection:Disconnect()
		end
	end)
end

--============================== The mute toggle ==============================--
-- ===== THERE IS NO SETTINGS SYSTEM IN THIS PROJECT, and this does not invent
-- one. PlayerProfile persists gameplay state (money, slots, levels, the pending
-- pot); there is no client-preferences store, no settings panel, and nothing
-- that survives a rejoin except the profile itself.
--
-- So this mute is SESSION-ONLY, and that is a real limitation stated rather than
-- hidden: a player who mutes will be unmuted on their next join. The alternative
-- -- adding a `muted` field to the save shape plus a remote to set it -- would
-- put a client preference into the gameplay save schema and add a write path to
-- a profile system built last pass, for a toggle. Rejected on scope; if audio
-- settings grow past one boolean (per-group sliders, say) they want their own
-- store and this becomes its first field.
--
-- BOTH A KEYBIND AND A BUTTON. The keybind follows DevPanelClient's established
-- pattern (a named KeyCode constant in config, read at one InputBegan site); the
-- button exists because a keybind alone excludes every touch player, and this
-- game is built with on-screen buttons for everything else for that reason.
local muted = false

local muteGui = Instance.new("ScreenGui")
muteGui.Name = "SoundHud"
muteGui.ResetOnSpawn = false
muteGui.IgnoreGuiInset = true
muteGui.Parent = playerGui

-- Continues the existing top-right stack: the shop's open button sits at
-- y-offset 0 and the inventory's at 54, both 44 tall against a 0.98 right edge.
-- This takes the next slot at 108. Square rather than 150 wide, so it reads as a
-- utility toggle rather than a third panel.
local muteButton = Instance.new("TextButton")
muteButton.Name = "MuteToggle"
muteButton.AnchorPoint = Vector2.new(1, 0)
muteButton.Position = UDim2.new(0.98, 0, 0.02, 108)
muteButton.Size = UDim2.new(0, 44, 0, 44)
muteButton.BackgroundColor3 = Color3.fromRGB(38, 40, 48)
muteButton.BackgroundTransparency = 0.25
-- Both GuiObject traps this codebase has been bitten by: BorderSizePixel
-- defaults to 1 and a transparent background does not clear it, and
-- TextStrokeTransparency defaults to a visible value.
muteButton.BorderSizePixel = 0
muteButton.Font = Enum.Font.GothamBold
muteButton.TextScaled = true
muteButton.TextColor3 = Color3.new(0.85, 0.88, 0.95)
muteButton.TextStrokeTransparency = 1
muteButton.Text = "🔊"
muteButton.Parent = muteGui

local muteCorner = Instance.new("UICorner")
muteCorner.CornerRadius = UDim.new(0, 8)
muteCorner.Parent = muteButton

-- Drives the MASTER group only, never the four category volumes. That is what
-- guarantees unmuting restores exactly the authored mix (see SoundConfig's
-- GROUP_VOLUMES) rather than flattening everything to one level -- the category
-- balance is never touched, only scaled.
local function applyMute()
	masterGroup.Volume = if muted then 0 else SoundConfig.MASTER_VOLUME
	muteButton.Text = if muted then "🔇" else "🔊"
	muteButton.TextColor3 = if muted then Color3.new(1, 0.55, 0.45) else Color3.new(0.85, 0.88, 0.95)
end

local function toggleMute()
	muted = not muted
	applyMute()
end

muteButton.Activated:Connect(toggleMute)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
	-- gameProcessedEvent guard, same as DevPanelClient's and LaunchClient's:
	-- without it, typing M into any text field would mute the game.
	if gameProcessedEvent then
		return
	end
	if input.KeyCode == SoundConfig.MUTE_TOGGLE_KEYCODE then
		toggleMute()
	end
end)

applyMute()
