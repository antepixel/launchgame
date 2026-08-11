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

-- The PENDING POT, one line further up the same stack (money at the bottom,
-- then tier at -110, then the save warning at -140, then this at -170) -- each
-- 30px line continuing the established pattern rather than inventing a second
-- anchor. This is money the player has EARNED but not yet banked; it becomes
-- spendable only by walking over a collect pad (see PlayerProfile.
-- collectPending), so it is deliberately a different, dimmer green from the
-- money readout below -- close enough to read as money, far enough not to be
-- mistaken for the balance.
--
-- ALWAYS VISIBLE, including at $0. Hiding it when empty would make the whole
-- stack jump every time the player collects, which is more distracting than a
-- line that briefly reads zero.
local pendingLabel = Instance.new("TextLabel")
pendingLabel.Name = "PendingReadout"
pendingLabel.AnchorPoint = Vector2.new(0, 1)
pendingLabel.Position = UDim2.new(0.02, 0, 0.98, -170)
pendingLabel.Size = UDim2.new(0, 480, 0, 30)
pendingLabel.BackgroundTransparency = 1
-- Both traps this codebase has already been bitten by, on every label added
-- here: BorderSizePixel defaults to 1 on every Instance.new GuiObject and a
-- transparent BACKGROUND does not clear the BORDER (separate render pass), and
-- TextStrokeTransparency defaults to a visible value. The three labels already
-- in this file predate that lesson and carry deliberate non-zero strokes for
-- contrast over the 3D world; these new ones set both explicitly.
pendingLabel.BorderSizePixel = 0
pendingLabel.Font = Enum.Font.GothamBold
pendingLabel.TextScaled = true
pendingLabel.TextXAlignment = Enum.TextXAlignment.Left
pendingLabel.TextColor3 = Color3.new(0.55, 0.9, 0.6)
pendingLabel.TextStrokeTransparency = 0.4
pendingLabel.Text = "Pending $0"
pendingLabel.Parent = screenGui

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

local function pendingAmount(): number
	local pending = baseFolder:GetAttribute("PendingIncome")
	return if typeof(pending) == "number" then pending else 0
end

local function offlineAmount(): number
	local credited = baseFolder:GetAttribute("OfflineCredit")
	return if typeof(credited) == "number" then credited else 0
end

-- ===== THE WORLD LABEL OVER THE RETURN PAD, and over that pad ONLY.
--
-- The ten per-slot pads in the plot are deliberately left bare. BaseConfig's own
-- collect-pad block argues that case ("a SurfaceGui saying COLLECT would be ten
-- more labels per base competing with the nametags and the button strips already
-- hanging over these same pads") and it still holds -- those pads already have a
-- slime nametag and an upgrade button strip floating over them. The return pad
-- is alone on an empty stretch of approach link with nothing above it, so one
-- label there reverses nothing.
--
-- A BillboardGui, matching how every other floating-in-the-air label in this
-- project is built (the slot nametags, the upgrade strips, the box's luck
-- readout). SurfaceGui is this codebase's other convention and is for text
-- PAINTED ON geometry -- the sign board, the runway band numbers, the slot pad
-- numbers -- which this is not.
--
-- Carries the three settings the nametags learned the hard way (see
-- PlayerProfile.spawnSlimeVisual and SignBuilder's headers): a finite
-- MaxDistance, AlwaysOnTop off so it sits behind whatever occludes it, and no
-- text stroke. A BillboardGui's Size is in SCREEN PIXELS and so holds a constant
-- size at every distance -- that is exactly what put a grey band on the horizon
-- when the base sign was one of these, and MaxDistance is the clamp that stops
-- six lanes' worth of these doing it again.
local RETURN_PAD_WAIT_TIMEOUT_SECONDS = 10
local COLLECT_LABEL_HEIGHT_PIXELS = 34
local AWAY_LABEL_HEIGHT_PIXELS = 24
-- Same 40 studs the slot nametags use, for the same reason: enough to read from
-- where the player actually stands (they are returned onto this very pad), well
-- short of the distance at which six lanes' labels would stack up on screen.
local COLLECT_LABEL_MAX_DISTANCE_STUDS = 40

local returnPad = baseFolder:WaitForChild("ReturnCollectPad", RETURN_PAD_WAIT_TIMEOUT_SECONDS) :: BasePart?
local refreshPadLabel: () -> ()
if returnPad then
	local padGui = Instance.new("BillboardGui")
	padGui.Name = "CollectTag"
	padGui.Size = UDim2.new(0, 200, 0, COLLECT_LABEL_HEIGHT_PIXELS + AWAY_LABEL_HEIGHT_PIXELS)
	-- Above head height on a flat floor tile, so a player standing ON the pad
	-- (which is where they are placed after a flight) does not have it inside
	-- their own character. AlwaysOnTop is off, so this has to clear the body
	-- rather than draw through it.
	padGui.StudsOffset = Vector3.new(0, 6, 0)
	padGui.AlwaysOnTop = false
	padGui.MaxDistance = COLLECT_LABEL_MAX_DISTANCE_STUDS
	padGui.Parent = returnPad

	-- Stacks the two lines without either hardcoding the other's height -- the
	-- same UIListLayout the slot nametags use for exactly this.
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = padGui

	-- LayoutOrder 1: ABOVE the collect line, shown only while this session's
	-- offline credit is unspent. The first collect zeroes OfflineCredit
	-- server-side (see collectPending, which clears the pot and this together),
	-- so it disappears on its own with nothing here to time or remember.
	local awayLabel = Instance.new("TextLabel")
	awayLabel.Name = "WhileAway"
	awayLabel.LayoutOrder = 1
	awayLabel.BackgroundTransparency = 1
	awayLabel.BorderSizePixel = 0
	awayLabel.Size = UDim2.new(1, 0, 0, AWAY_LABEL_HEIGHT_PIXELS)
	awayLabel.Font = Enum.Font.GothamBold
	awayLabel.TextScaled = true
	awayLabel.TextColor3 = Color3.new(0.85, 0.85, 0.55)
	awayLabel.TextStrokeTransparency = 1
	awayLabel.Visible = false
	awayLabel.Parent = padGui

	local collectLabel = Instance.new("TextLabel")
	collectLabel.Name = "Collect"
	collectLabel.LayoutOrder = 2
	collectLabel.BackgroundTransparency = 1
	collectLabel.BorderSizePixel = 0
	collectLabel.Size = UDim2.new(1, 0, 0, COLLECT_LABEL_HEIGHT_PIXELS)
	collectLabel.Font = Enum.Font.GothamBold
	collectLabel.TextScaled = true
	collectLabel.TextColor3 = Color3.new(0.4, 1, 0.5)
	collectLabel.TextStrokeTransparency = 1
	collectLabel.Text = "Collect $0"
	collectLabel.Parent = padGui

	function refreshPadLabel()
		local pending = pendingAmount()
		local credited = offlineAmount()
		collectLabel.Text = "Collect " .. MoneyFormat.format(pending)
		-- Hidden at zero rather than reading "Collect $0" over an empty pad --
		-- the label is an invitation, and there is nothing to invite the player
		-- to do when the pot is empty. The pad itself stays visible.
		collectLabel.Visible = pending > 0
		awayLabel.Visible = credited > 0
		if credited > 0 then
			awayLabel.Text = MoneyFormat.format(credited) .. " while you were away"
		end
	end
else
	warn(string.format(
		"[BaseClient] ReturnCollectPad never appeared under Base_%d after %d seconds -- the collect label will not render this session. The pad's own collection still works server-side; this is display only.",
		player.UserId, RETURN_PAD_WAIT_TIMEOUT_SECONDS
	))
	function refreshPadLabel() end
end

-- Rendered entirely client-side, from two replicated numbers. The server writes
-- PendingIncome/OfflineCredit only when they actually change (see
-- PlayerProfile.setPending -- once per income tick, once per collect), never per
-- frame, and there is no remote in this path at all.
local function refreshPending()
	pendingLabel.Text = "Pending " .. MoneyFormat.format(pendingAmount())
	refreshPadLabel()
end

baseFolder:GetAttributeChangedSignal("Money"):Connect(refreshMoney)
baseFolder:GetAttributeChangedSignal("SwingTier"):Connect(refreshTier)
baseFolder:GetAttributeChangedSignal("SaveDisabled"):Connect(refreshSaveWarning)
baseFolder:GetAttributeChangedSignal("PendingIncome"):Connect(refreshPending)
baseFolder:GetAttributeChangedSignal("OfflineCredit"):Connect(refreshPending)
refreshMoney()
refreshTier()
refreshSaveWarning()
refreshPending()
