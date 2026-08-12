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
-- For JSONDecode of the per-slot pending breakdown only -- the same encoding
-- PlayerProfile.syncClientState already uses for Slots/Inventory, which
-- InventoryClient decodes the same way.
local HttpService = game:GetService("HttpService")

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

-- The PENDING TOTAL, one line further up the same stack (money at the bottom,
-- then tier at -110, then the save warning at -140, then this at -170) -- each
-- 30px line continuing the established pattern rather than inventing a second
-- anchor. This is money the player has EARNED but not yet banked; it becomes
-- spendable only by walking over the collect pad of the slime that earned it
-- (see PlayerProfile.collectPending), so it is deliberately a different, dimmer
-- green from the money readout below -- close enough to read as money, far
-- enough not to be mistaken for the balance.
--
-- ===== THE TOTAL ACROSS ALL TEN SLOTS, and that is what makes it worth keeping
-- on the HUD now that the money lives on ten pads inside the base (see REPORT.md
-- STEP 5d). The pads say what is waiting on each slime; this says what is
-- waiting in total, and it is readable from the swing -- which is exactly where
-- the player decides whether to launch again or go and bank. Collection is a
-- trip now, and this is the number the trip is worth.
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

-- The "WHILE YOU WERE AWAY" LINE, one more 30px step up the same stack (-200).
--
-- IT LIVES ON THE HUD NOW because there is nowhere else left to put it (see
-- REPORT.md STEP 5c). It used to hang over the return pad -- one pad, on the
-- walk, that the player was standing on within a second of joining. There are
-- ten pads now, spread across the plot, and the credit is spread across them
-- too; hanging the summary over one of them would be arbitrary, and hanging it
-- over all ten would say the same sentence ten times.
--
-- ONE SUMMARY, SHOWN ONCE. The server zeroes OfflineCredit on the first collect
-- at ANY pad (see PlayerProfile.bankSlot), so this disappears the moment the
-- player banks anything, with nothing here to time or remember. Hidden entirely
-- while zero -- unlike the pending line below it, this one has nothing to say
-- most of the session, and a permanent "$0 while you were away" would be noise.
local awayLabel = Instance.new("TextLabel")
awayLabel.Name = "WhileAwayReadout"
awayLabel.AnchorPoint = Vector2.new(0, 1)
awayLabel.Position = UDim2.new(0.02, 0, 0.98, -200)
awayLabel.Size = UDim2.new(0, 480, 0, 30)
awayLabel.BackgroundTransparency = 1
-- Both traps again, explicitly, on this new label -- see pendingLabel above.
awayLabel.BorderSizePixel = 0
awayLabel.Font = Enum.Font.GothamBold
awayLabel.TextScaled = true
awayLabel.TextXAlignment = Enum.TextXAlignment.Left
-- Warm, not green: this is a one-time notice about time, not a live money
-- readout, and it sits directly above one.
awayLabel.TextColor3 = Color3.new(0.85, 0.85, 0.55)
awayLabel.TextStrokeTransparency = 0.4
awayLabel.Text = ""
awayLabel.Visible = false
awayLabel.Parent = screenGui

local function pendingAmount(): number
	local pending = baseFolder:GetAttribute("PendingIncome")
	return if typeof(pending) == "number" then pending else 0
end

local function offlineAmount(): number
	local credited = baseFolder:GetAttribute("OfflineCredit")
	return if typeof(credited) == "number" then credited else 0
end

-- ===== THE AMOUNT PAINTED ON EACH COLLECT PAD.
--
-- A SurfaceGui ON THE PAD'S TOP FACE, not a BillboardGui above it, and that is
-- the whole decision (see REPORT.md STEP 5a and BaseConfig's collect-pad block,
-- which records the same reasoning beside the pad's own constants). Every slot
-- already carries a nametag AND an upgrade button strip floating over it; a
-- third label in the air would stack three things above every slime across six
-- bases. Text PAINTED ON GEOMETRY is this codebase's other convention -- the
-- entrance sign board, the runway band numbers, the slot pad numbers MapBuilder
-- paints -- and it puts the number at ground level, where the player is walking
-- and where the pad they are deciding whether to step on actually is.
--
-- The rejected alternative was a BillboardGui with a MaxDistance clamp, matching
-- the nametags. It would have been readable from further away, which is the one
-- thing a SurfaceGui gives up here -- but "readable from across the plot" is not
-- what this label is for. The HUD total answers "is a trip worth it" from
-- anywhere; this answers "is THIS pad worth stepping on" from the path beside
-- it.
--
-- Same three properties MapBuilder's slot-number labels use (Face = Top,
-- LightInfluence = 0 so the Neon pad's glow does not wash the glyphs out,
-- PixelsPerStud = 24), so the two read as the same kind of marking on the same
-- kind of surface.
local PAD_LABEL_PIXELS_PER_STUD = 24
-- How long to wait for a slime Model's own CollectPad to appear. This is a race
-- with the next few lines of spawnSlimeVisual, not with a DataStore load, so it
-- resolves within a frame in practice -- the timeout exists so a slime built by
-- something OTHER than spawnSlimeVisual (which would have no pad at all) warns
-- and moves on instead of yielding this connection forever.
local PAD_WAIT_TIMEOUT_SECONDS = 5

-- WHITE GLYPHS WITH A DARK STROKE, exactly as BaseConfig's own
-- BASE_COLLECT_PAD_COLOR comment prescribes for text over this pad: the pad is
-- bright Neon green and stays that way (being spotted from the path is its
-- entire purpose), so the contrast is solved on the TEXT rather than by
-- darkening the surface underneath it.
local PAD_LABEL_TEXT_COLOR = Color3.new(1, 1, 1)
local PAD_LABEL_STROKE_COLOR = Color3.new(0, 0.12, 0.03)

-- Every pad label this client has built, slot number -> its TextLabel. Rebuilt
-- as slimes come and go: a pad is a descendant of its slime's Model (see
-- PlayerProfile.spawnSlimeVisual) and dies with it, so the entry is dropped when
-- the Model leaves.
local padLabels: { [number]: TextLabel } = {}

local function pendingBySlot(): { [number]: number }
	local encoded = baseFolder:GetAttribute("PendingBySlot")
	local bySlot: { [number]: number } = {}
	if typeof(encoded) ~= "string" then
		return bySlot
	end
	-- The server writes this with HttpService:JSONEncode and nothing else can
	-- (it is an attribute on a server-owned Instance), but a decode failure must
	-- not take the whole HUD down with it -- pcall'd in exactly the form
	-- InventoryClient already decodes the Slots/Inventory attributes with.
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, encoded)
	if not ok or typeof(decoded) ~= "table" then
		return bySlot
	end
	for _, entry in decoded do
		if typeof(entry) == "table" and typeof(entry.slot) == "number" and typeof(entry.pending) == "number" then
			bySlot[entry.slot] = entry.pending
		end
	end
	return bySlot
end

local function refreshPadLabels()
	local bySlot = pendingBySlot()
	for slotNumber, label in padLabels do
		local amount = bySlot[slotNumber] or 0
		-- HIDDEN AT ZERO, not showing "$0". An empty pad is the normal state for
		-- most slots most of the time, and a row of ten "$0"s would turn the
		-- thing that says "there is money here" into wallpaper. The pad itself
		-- stays visible -- it is still where the slime's money will appear.
		label.Visible = amount > 0
		if amount > 0 then
			label.Text = MoneyFormat.format(amount)
		end
	end
end

-- Builds the SurfaceGui for one slime Model's pad, if it has not been built
-- already. Called for every Model that appears under this player's base folder;
-- silently does nothing for anything that is not a slot slime (the entrance
-- sign, for one).
local function considerSlimeModel(child: Instance)
	if not child:IsA("Model") then
		return
	end
	local slotNumber = child:GetAttribute("SlotNumber")
	if typeof(slotNumber) ~= "number" then
		return
	end
	-- The pad is parented in a moment AFTER the Model itself is (see
	-- spawnSlimeVisual), so a ChildAdded that fires on the Model can arrive
	-- before the pad exists. WaitForChild with a timeout rather than
	-- FindFirstChild: this is a race with a few lines of server code, not a
	-- load, so it resolves within a frame in practice.
	local pad = child:WaitForChild("CollectPad", PAD_WAIT_TIMEOUT_SECONDS) :: BasePart?
	if not pad then
		warn(string.format(
			"[BaseClient] slot %d's slime has no CollectPad after %d seconds -- no amount will be painted on it this session. Collection itself is server-side and unaffected.",
			slotNumber, PAD_WAIT_TIMEOUT_SECONDS
		))
		return
	end
	if pad:FindFirstChild("PendingLabel") then
		return
	end

	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = "PendingLabel"
	surfaceGui.Face = Enum.NormalId.Top
	surfaceGui.LightInfluence = 0
	surfaceGui.PixelsPerStud = PAD_LABEL_PIXELS_PER_STUD
	surfaceGui.Parent = pad

	local label = Instance.new("TextLabel")
	label.Name = "Amount"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.95, 0.6)
	label.BackgroundTransparency = 1
	-- Both GuiObject traps, explicitly (see pendingLabel above): a transparent
	-- background does NOT clear the 1px default border, and the text stroke is a
	-- third render pass neither of the other two suppresses. Here the stroke is
	-- wanted ON (0 = fully opaque) rather than off -- see PAD_LABEL_STROKE_COLOR.
	label.BorderSizePixel = 0
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = PAD_LABEL_STROKE_COLOR
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = PAD_LABEL_TEXT_COLOR
	label.Text = ""
	label.Visible = false
	label.Parent = surfaceGui

	padLabels[slotNumber] = label
	-- A slime placed mid-session may already have a pot (offline credit landed
	-- on it, or the tick has run since) -- render immediately rather than
	-- waiting for the next attribute change.
	refreshPadLabels()

	-- The pad dies with its slime and the label dies with the pad, so the only
	-- thing left to clean up is this table's entry -- without which a slot that
	-- was emptied and refilled would hold a destroyed label and never render.
	child.Destroying:Connect(function()
		if padLabels[slotNumber] == label then
			padLabels[slotNumber] = nil
		end
	end)
end

-- Rendered entirely client-side, from replicated attributes. The server writes
-- PendingIncome/PendingBySlot/OfflineCredit only when they actually change (see
-- PlayerProfile.publishPending -- once per income tick, once per collect), never
-- per frame, and there is no remote in this path at all.
local function refreshPending()
	pendingLabel.Text = "Pending " .. MoneyFormat.format(pendingAmount())
	local credited = offlineAmount()
	awayLabel.Visible = credited > 0
	if credited > 0 then
		awayLabel.Text = MoneyFormat.format(credited) .. " earned while you were away"
	end
	refreshPadLabels()
end

-- ChildAdded, not a one-shot pass: a slime can be placed at any point in the
-- session (a reveal, or the inventory panel), and its pad is born with it. The
-- initial loop covers anything already there if this script starts late.
-- task.spawn'd because considerSlimeModel yields on WaitForChild -- a slime
-- present at start must not delay the attribute wiring below it.
baseFolder.ChildAdded:Connect(considerSlimeModel)
for _, child in baseFolder:GetChildren() do
	task.spawn(considerSlimeModel, child)
end

baseFolder:GetAttributeChangedSignal("Money"):Connect(refreshMoney)
baseFolder:GetAttributeChangedSignal("SwingTier"):Connect(refreshTier)
baseFolder:GetAttributeChangedSignal("SaveDisabled"):Connect(refreshSaveWarning)
baseFolder:GetAttributeChangedSignal("PendingIncome"):Connect(refreshPending)
baseFolder:GetAttributeChangedSignal("PendingBySlot"):Connect(refreshPending)
baseFolder:GetAttributeChangedSignal("OfflineCredit"):Connect(refreshPending)
refreshMoney()
refreshTier()
refreshSaveWarning()
refreshPending()
