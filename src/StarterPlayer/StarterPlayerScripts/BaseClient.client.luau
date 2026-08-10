--!strict
-- Money display -- purely a rendering of THIS player's own Base_<UserId>
-- folder's Money attribute (see PlayerProfile.luau), which Roblox
-- replicates to every client automatically like any other Instance
-- attribute. No remote event needed just to keep a number in sync, and no
-- other client-side logic belongs here: every base (this player's own and
-- everyone else's -- see the written report for why all bases are visible
-- to everyone) is built from ordinary Workspace parts, which already
-- replicate and render for free without this script touching them.
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MoneyFormat = require(ReplicatedStorage.Config.MoneyFormat)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Named deterministically by UserId (see PlayerProfile.buildBaseFolder) so
-- this client can find its OWN base without any remote round-trip.
--
-- BOUNDED wait, not the unbounded WaitForChild this used to be: PlayerProfile.
-- onPlayerAdded builds this folder synchronously, before the profile even
-- starts loading (see its own "Join" comment), so it normally exists within a
-- frame or two of joining regardless of whether the load itself later
-- succeeds or fails -- a LOAD failure alone was never what could make this
-- wait hang. If it's still missing after this timeout, something server-side
-- is actually broken (PlayerProfile errored before creating it, etc.), and an
-- unbounded wait here would leave this player with no money HUD, no visible
-- error, and nothing but an "Infinite yield possible" console warning to go
-- on -- see BASE_FOLDER_WAIT_TIMEOUT_SECONDS below.
local BASE_FOLDER_WAIT_TIMEOUT_SECONDS = 10
local baseFolder = Workspace:WaitForChild(string.format("Base_%d", player.UserId), BASE_FOLDER_WAIT_TIMEOUT_SECONDS)
if not baseFolder then
	warn(string.format(
		"[BaseClient] Base_%d never appeared after %d seconds -- this player's base likely failed to initialise server-side. Money HUD will not render this session; the rest of the client is unaffected.",
		player.UserId, BASE_FOLDER_WAIT_TIMEOUT_SECONDS
	))
	local errorGui = Instance.new("ScreenGui")
	errorGui.Name = "BaseHud"
	errorGui.ResetOnSpawn = false
	errorGui.IgnoreGuiInset = true
	errorGui.Parent = playerGui

	local errorLabel = Instance.new("TextLabel")
	errorLabel.Name = "BaseUnavailable"
	errorLabel.AnchorPoint = Vector2.new(0, 1)
	errorLabel.Position = UDim2.new(0.02, 0, 0.98, 0)
	errorLabel.Size = UDim2.new(0, 480, 0, 40)
	errorLabel.BackgroundTransparency = 1
	errorLabel.Font = Enum.Font.GothamBold
	errorLabel.TextScaled = true
	errorLabel.TextXAlignment = Enum.TextXAlignment.Left
	errorLabel.TextColor3 = Color3.new(1, 0.35, 0.3)
	errorLabel.TextStrokeTransparency = 0.3
	errorLabel.Text = "Money HUD unavailable -- failed to load your base"
	errorLabel.Parent = errorGui
	return
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BaseHud"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- Bottom-left, big and green -- the most prominent number on screen,
-- deliberately bigger than LaunchClient's top-center distance readout
-- (400x60) so money reads as the primary stat, not a secondary HUD element.
local moneyLabel = Instance.new("TextLabel")
moneyLabel.Name = "MoneyReadout"
moneyLabel.AnchorPoint = Vector2.new(0, 1)
moneyLabel.Position = UDim2.new(0.02, 0, 0.98, 0)
moneyLabel.Size = UDim2.new(0, 480, 0, 110)
moneyLabel.BackgroundTransparency = 1
moneyLabel.Font = Enum.Font.GothamBlack
moneyLabel.TextScaled = true
moneyLabel.TextXAlignment = Enum.TextXAlignment.Left
moneyLabel.TextColor3 = Color3.new(0.25, 1, 0.35)
moneyLabel.TextStrokeTransparency = 0.25
moneyLabel.Text = "$0"
moneyLabel.Parent = screenGui

-- Persistent tier readout -- sits just above the money readout, always
-- visible (not tucked inside the shop panel, which is closed by default --
-- see ShopClient.client.luau) so the player's current swing tier is legible
-- at a glance without opening anything.
local tierLabel = Instance.new("TextLabel")
tierLabel.Name = "TierReadout"
tierLabel.AnchorPoint = Vector2.new(0, 1)
tierLabel.Position = UDim2.new(0.02, 0, 0.98, -110)
tierLabel.Size = UDim2.new(0, 480, 0, 30)
tierLabel.BackgroundTransparency = 1
tierLabel.Font = Enum.Font.GothamBold
tierLabel.TextScaled = true
tierLabel.TextXAlignment = Enum.TextXAlignment.Left
tierLabel.TextColor3 = Color3.new(0.6, 0.85, 1)
tierLabel.TextStrokeTransparency = 0.4
tierLabel.Text = "Swing Tier 1"
tierLabel.Parent = screenGui

-- A quiet, secondary warning -- only ever shown if this session's load
-- failed (see PlayerProfile.onPlayerAdded and the written report). Sits
-- above the tier readout (itself above the money readout) so it's easy to
-- notice without competing with either for size/colour, and without
-- overlapping the tier label.
local saveWarningLabel = Instance.new("TextLabel")
saveWarningLabel.Name = "SaveWarning"
saveWarningLabel.AnchorPoint = Vector2.new(0, 1)
saveWarningLabel.Position = UDim2.new(0.02, 0, 0.98, -140)
saveWarningLabel.Size = UDim2.new(0, 480, 0, 30)
saveWarningLabel.BackgroundTransparency = 1
saveWarningLabel.Font = Enum.Font.GothamBold
saveWarningLabel.TextScaled = true
saveWarningLabel.TextXAlignment = Enum.TextXAlignment.Left
saveWarningLabel.TextColor3 = Color3.new(1, 0.55, 0.2)
saveWarningLabel.TextStrokeTransparency = 0.4
saveWarningLabel.Text = "Could not load your save -- this session will not be saved"
saveWarningLabel.Visible = false
saveWarningLabel.Parent = screenGui

-- Shared with ShopClient.client.luau (see MoneyFormat.luau's own header for
-- why this one specifically isn't a local copy like the smaller formatters
-- elsewhere in this project): the money HUD and the shop's prices have to
-- agree exactly on how a given amount reads, all the way up past a
-- quintillion for the top of the old eleven-tier ladder.
local function refreshMoney()
	local money = baseFolder:GetAttribute("Money")
	moneyLabel.Text = MoneyFormat.format(if typeof(money) == "number" then money else 0)
end

local function refreshTier()
	local tier = baseFolder:GetAttribute("SwingTier")
	tierLabel.Text = string.format("Swing Tier %d", if typeof(tier) == "number" then tier else 1)
end

local function refreshSaveWarning()
	saveWarningLabel.Visible = baseFolder:GetAttribute("SaveDisabled") == true
end

baseFolder:GetAttributeChangedSignal("Money"):Connect(refreshMoney)
baseFolder:GetAttributeChangedSignal("SwingTier"):Connect(refreshTier)
baseFolder:GetAttributeChangedSignal("SaveDisabled"):Connect(refreshSaveWarning)
refreshMoney()
refreshTier()
refreshSaveWarning()
