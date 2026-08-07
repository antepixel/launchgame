--!strict
-- Upgrade controls attached to the placed slimes in THIS player's own base --
-- +1/+5/MAX with live prices, so a slime can be levelled by walking up to it
-- instead of opening the inventory panel.
--
-- NOT A SECOND UPGRADE PATH. Every button here fires the SAME
-- UpgradeRemotes.UpgradeSlime(slotNumber, count) that InventoryClient's own
-- three buttons fire, with the same two arguments and the same meaning, and
-- UpgradeServer/PlayerProfile.upgradeSlime does all of the deciding exactly as
-- before: whether the slot is occupied, how many levels are actually
-- available, what they cost, and whether this player can afford them. Nothing
-- in this file is trusted by anything. The prices it draws are a PREVIEW
-- computed from the shared SlimeUpgrade module -- the same preview the
-- inventory panel already draws, from the same module, for the same reason
-- (see SlimeUpgrade.luau's own header on why that module is in
-- ReplicatedStorage at all).
--
-- THIS PLAYER'S OWN BASE ONLY, structurally: the only folder this file ever
-- reads or attaches anything to is Workspace.Base_<LocalPlayer.UserId>. That
-- is not a politeness -- the remote's slot argument is interpreted by the
-- server against the CALLING player's own profile, so a button drawn on
-- somebody else's slime would silently upgrade the presser's own slot of the
-- same number. Building them only over one's own slimes is what makes that
-- impossible rather than merely unlikely.
--
-- ENTIRELY CLIENT-SIDE AND NON-REPLICATING, the same way
-- SlimeIdleClient.client.luau is: the BillboardGui and its buttons are created
-- here, on this client, and parented into an already-replicated part. They
-- exist on no other client and on no server. The server-built NameTag on that
-- same part is NOT touched -- not resized, not reparented, not restyled: this
-- is a second, separate billboard with its own placement and its own
-- MaxDistance, so PlayerProfile.refreshSlimeVisualLabel keeps owning the
-- name/level/income lines and this file keeps owning the buttons, with no
-- shared instance for the two to fight over.
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local MoneyFormat = require(ReplicatedStorage.Config.MoneyFormat)
local SlimeData = require(ReplicatedStorage.Config.SlimeData)
local SlimeUpgrade = require(ReplicatedStorage.Config.SlimeUpgrade)
local SlimeUpgradeConfig = require(ReplicatedStorage.Config.SlimeUpgradeConfig)

local player = Players.LocalPlayer

-- Bounded waits + a warn rather than a hang, the same pattern (and the same
-- reasoning) as BaseClient/InventoryClient's own gates -- extended to the
-- children inside each folder, not just the folders, since a folder existing
-- has never implied its contents do.
local WAIT_TIMEOUT_SECONDS = 10
-- Separate, shorter budget for a slime model's own body part. A base folder
-- arriving late is a server-setup failure worth ten seconds of patience; a
-- Model already in the tree whose parts have not replicated yet is an ordinary
-- one-frame race that either resolves immediately or means the model was
-- destroyed mid-placement.
local BODY_WAIT_TIMEOUT_SECONDS = 5

local function failUpgradeTags(reason: string)
	warn(string.format(
		"[SlimeUpgradeTagClient] %s never appeared after %d seconds -- on-slime upgrade buttons will not render this session. The inventory panel's own upgrade buttons are unaffected.",
		reason, WAIT_TIMEOUT_SECONDS
	))
end

local baseFolderName = string.format("Base_%d", player.UserId)
local baseFolder = Workspace:WaitForChild(baseFolderName, WAIT_TIMEOUT_SECONDS)
if not baseFolder then
	failUpgradeTags(baseFolderName)
	return
end

local upgradeRemotesFolder = ReplicatedStorage:WaitForChild("UpgradeRemotes", WAIT_TIMEOUT_SECONDS)
if not upgradeRemotesFolder then
	failUpgradeTags("ReplicatedStorage.UpgradeRemotes")
	return
end
local upgradeSlimeRemoteMaybe = upgradeRemotesFolder:WaitForChild("UpgradeSlime", WAIT_TIMEOUT_SECONDS)
if not upgradeSlimeRemoteMaybe then
	failUpgradeTags("ReplicatedStorage.UpgradeRemotes.UpgradeSlime")
	return
end
local upgradeSlimeRemote = upgradeSlimeRemoteMaybe :: RemoteEvent

-- The body MeshPart's name in every slime model (see SlimeBuilder.luau) -- the
-- part the server already anchors its NameTag to, so the buttons hang off the
-- same part the name does and the two can never end up on different pieces of
-- the same slime.
local BODY_PART_NAME = "slime"

-- The same three buttons InventoryClient's own upgrade strip sends, in the
-- same order -- deliberately the same interaction, not a second one invented
-- for a different surface. +1 / +5 / MAX, sized for a 25-level cap (the old
-- +1/+10/+100 was built for MAX_LEVEL = 1000). MAX sends MAX_LEVEL and lets
-- the server cap it to what is actually left; the server caps whatever
-- arrives regardless (see SlimeUpgrade.totalUpgradeCost's own capping and
-- PlayerProfile.upgradeSlime, which re-derives the price from its own state),
-- so this is only ever "which button is this."
local UPGRADE_BUTTONS = {
	{ count = 1, label = "+1" },
	{ count = 5, label = "+5" },
	{ count = SlimeUpgradeConfig.MAX_LEVEL, label = "MAX" },
}

-- ===== Placement and reach =====
-- How far from the CAMERA the button strip still draws -- MUCH shorter than
-- the NameTag's own 40 (see PlayerProfile.NAMETAG_MAX_DISTANCE_STUDS), and
-- that gap is the whole design.
--
-- The ten pads are a 2x5 grid, columns 30 studs apart and rows 14 apart (see
-- BaseGeometry.slotPosition), and the default third-person camera sits ~12
-- studs back. So standing AT a slot puts its own camera distance at ~12, its
-- nearest neighbour at ~26 (14 + 12), the diagonal one at ~45 and the one
-- straight across the path at ~42. 22 admits the slime you are standing at
-- and excludes every other one -- one strip on screen, occasionally two if
-- you stand between two pads.
--
-- The columns moved out from +-11 to +-15 to open up the collect-pad channel
-- (see BaseConfig's SLOT_COLUMN_HALF_WIDTH), which only strengthens this: the
-- binding neighbour was always the NEXT ROW at 14 studs, and that is
-- unchanged, while everything in the other column moved further away. The 22
-- matching the old column spacing exactly was a coincidence, not a
-- derivation -- this number comes from 14 + 12, not from the column pitch.
--
-- That is what keeps the readability promise: names and income still read from
-- 40 studs exactly as before (that tag is untouched), while the button strips
-- -- the dense part -- only ever appear one at a time. Ten sets of buttons are
-- never on screen together, so the overlap MaxDistance was introduced to solve
-- is not reintroduced; it is applied a second time, harder.
--
-- Note this bounds CLUTTER, not legibility or reach: a BillboardGui's
-- pixel-Offset Size is screen space, so the strip is the same
-- UPGRADE_TAG_WIDTH_PIXELS x UPGRADE_TAG_HEIGHT_PIXELS and the same click
-- target at 22 studs as at 2.
local UPGRADE_TAG_MAX_DISTANCE_STUDS = 22

-- 180, MATCHING THE NAMETAG'S OWN WIDTH above it (see PlayerProfile.
-- spawnSlimeVisual's `nameTag.Size = UDim2.new(0, 180, ...)`) -- was 240,
-- and that mismatch was itself a misalignment cue: the strip was a third
-- wider than the label it hangs under, so the two billboards over one slime
-- read as two unrelated widths rather than one stacked column.
--
-- It is also what stops the strip overhanging the pad. A BillboardGui's
-- Offset size is SCREEN PIXELS, so its width in STUDS shrinks with distance:
-- at UPGRADE_TAG_MAX_DISTANCE_STUDS (22, the furthest it ever draws) 240 px
-- covers very nearly the whole 8-stud pad, and any further and it would
-- spill past the edges -- which is exactly where it reads as belonging to
-- the floor rather than to the slime. 180 keeps it inside the pad across the
-- whole range it is visible in.
--
-- The buttons keep their 0.32 share, so they go 76.8 px -> 57.6 px wide.
-- TextScaled still fits "MAX +24" over "$12.3K" in that; it simply picks a
-- slightly smaller size for the price line.
local UPGRADE_TAG_WIDTH_PIXELS = 180
local UPGRADE_TAG_HEIGHT_PIXELS = 36
local UPGRADE_TAG_BUTTON_GAP_PIXELS = 3
-- Each button's share of the strip's width. Three at 0.32 leaves 4% for the
-- two gaps above and the edges -- at the current 180 px strip that is 57.6 px
-- per button plus 6 px of gaps = 178.2 of 180, so the UIListLayout's own
-- Center alignment has 0.9 px of slack to distribute either side and the row
-- is centred on the slime to within a pixel.
local UPGRADE_TAG_BUTTON_WIDTH_SCALE = 0.32

-- How far ABOVE THE SLIME'S OWN FEET the strip's centre sits.
--
-- THIS IS THE MISALIGNMENT FIX. The offset used to be "0.75 x the body's
-- FULL height, below the body's CENTRE", on the stated theory that it would
-- land around the slime's base, on the pad. It does not, and the arithmetic
-- is not close: a slot slime is 7 studs wide and so 7 * 0.677 = 4.741 studs
-- tall, its centre sits 2.371 studs above the pad's top face (it is
-- bottom-aligned onto it, see spawnSlimeVisual), and 0.75 * 4.741 = 3.556.
-- 2.371 - 3.556 = -1.185: the strip was anchored 1.185 studs BELOW the pad's
-- top surface -- 0.185 studs below ground level, buried in the mat. Drawn
-- AlwaysOnTop it stayed visible, but it was hanging off a point under the
-- floor, which is why it read as sitting past the pad's edge and belonging
-- to the ground rather than to the slime standing on it.
--
-- Measuring from the body's own BOTTOM (its live centre minus half its live
-- height) instead of guessing a fraction of its height fixes that, and
-- brings a second property with it: it is EXACTLY STEADY under the idle
-- breathing. SlimeIdleClient pins a breathing slime's base to the pad by
-- writing the centre as restY + (baseHeight * sy) / 2 while the height is
-- baseHeight * sy -- so centre minus half-height is identically restY at
-- every phase, and the sy terms cancel. The old fraction did not cancel: it
-- multiplied the breath, so the strip bobbed up and down by 0.25 x the
-- amplitude all by itself. This one cannot move at all.
--
-- 1.0 stud of lift puts the strip at the slime's ankles: clear of the pad
-- face beneath it, and still a full model height below the NameTag above
-- (which sits ~1 stud above the model's measured top, ~4.7 studs up), so the
-- name lines and the buttons still cannot overlap at any distance or angle.
local UPGRADE_TAG_LIFT_STUDS = 1.0

local BUTTON_AFFORDABLE_COLOR = Color3.new(0.15, 0.55, 0.25)
local BUTTON_DISABLED_COLOR = Color3.new(0.22, 0.22, 0.25)
local BUTTON_MAXED_COLOR = Color3.new(0.35, 0.35, 0.38)
local BUTTON_TEXT_COLOR = Color3.new(1, 1, 1)
local BUTTON_DISABLED_TEXT_COLOR = Color3.new(0.55, 0.55, 0.58)

type SlotTag = {
	slotNumber: number,
	buttons: { TextButton },
}

local tagsByModel: { [Model]: SlotTag } = {}
-- Models whose body part is still being waited on. Kept separate from
-- tagsByModel (which only ever holds FINISHED tags) purely so a second
-- discovery of the same model -- the startup sweep racing ChildAdded -- cannot
-- start a second attach across the yield in attachTag.
local attachingModels: { [Model]: boolean } = {}

local function readMoney(): number
	local money = baseFolder:GetAttribute("Money")
	return if typeof(money) == "number" then money else 0
end

-- Decodes the base folder's own replicated Slots attribute (see
-- PlayerProfile.syncClientState) into slot -> globalIndex and slot -> level.
-- Deliberately a local decode rather than a shared one with InventoryClient:
-- every client script in this game reads the attributes it needs directly
-- (BaseClient the money, ShopClient the tier, InventoryClient these), and
-- this file needs a strictly smaller subset than the panel does.
local function readSlots(): ({ [number]: number }, { [number]: number })
	local slotsByNumber: { [number]: number } = {}
	local levelsByNumber: { [number]: number } = {}

	local slotsJson = baseFolder:GetAttribute("Slots")
	if typeof(slotsJson) ~= "string" or slotsJson == "" then
		return slotsByNumber, levelsByNumber
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, slotsJson)
	if not (ok and typeof(decoded) == "table") then
		return slotsByNumber, levelsByNumber
	end
	for _, entry in decoded do
		if typeof(entry) == "table" and typeof(entry.slot) == "number" and typeof(entry.globalIndex) == "number" then
			slotsByNumber[entry.slot] = entry.globalIndex
			levelsByNumber[entry.slot] = if typeof(entry.level) == "number" then entry.level else 1
		end
	end
	return slotsByNumber, levelsByNumber
end

-- Repaints ONE slime's three buttons in place -- text, colour, and whether
-- they take a click. Same nominal count/cost/enabled logic as the inventory
-- panel's own rows (see InventoryClient's buildBaseRow), reading the same
-- SlimeUpgrade.totalUpgradeCost, so the two surfaces can never quote different
-- prices for the same purchase.
--
-- In place, never rebuilt: this runs on every Money change, i.e. once a second
-- off the income tick, so it writes at most 10 slots x 3 buttons of Text/
-- Color3/Active per second and allocates nothing. (The inventory panel gates
-- its own money refresh on being open because it DESTROYS AND REBUILDS whole
-- rows -- a different cost with a different answer.)
local function refreshTag(tag: SlotTag, slotsByNumber: { [number]: number }, levelsByNumber: { [number]: number }, money: number)
	local globalIndex = slotsByNumber[tag.slotNumber]
	local slime = if globalIndex then SlimeData.SLIMES[globalIndex] else nil
	if not slime then
		-- The slot has been emptied (removed or sold) but this Model has not
		-- been destroyed yet -- the attribute change and the Destroy are two
		-- separate replicated events. Hiding rather than erroring means the
		-- gap between them shows nothing rather than a stale price.
		for _, button in tag.buttons do
			button.Visible = false
		end
		return
	end

	local level = levelsByNumber[tag.slotNumber] or 1
	for index, spec in UPGRADE_BUTTONS do
		local cost, actualCount = SlimeUpgrade.totalUpgradeCost(slime.incomePerSecond, level, spec.count)
		local atMax = actualCount <= 0
		local affordable = not atMax and money >= cost

		local button = tag.buttons[index]
		button.Visible = true
		-- actualCount, not the requested count: near the cap the +5 button
		-- honestly reads "+2" for what it will actually buy, and MAX always
		-- names the number of levels it is about to hand over -- exactly as
		-- the inventory panel's own strip does.
		if atMax then
			button.Text = "MAXED"
		elseif spec.label == "MAX" then
			button.Text = string.format("MAX +%d\n%s", actualCount, MoneyFormat.format(cost))
		else
			button.Text = string.format("+%d\n%s", actualCount, MoneyFormat.format(cost))
		end
		button.BackgroundColor3 = if atMax
			then BUTTON_MAXED_COLOR
			elseif affordable then BUTTON_AFFORDABLE_COLOR
			else BUTTON_DISABLED_COLOR
		button.TextColor3 = if affordable then BUTTON_TEXT_COLOR else BUTTON_DISABLED_TEXT_COLOR
		-- Local affordability gate ONLY, for the same reason the inventory
		-- panel greys its own buttons: it stops a press that the server was
		-- always going to refuse, it does not decide anything. A client that
		-- forced this true would just get a rejection from upgradeSlime.
		button.Active = affordable
		button.AutoButtonColor = affordable
	end
end

local function refreshAllTags()
	local money = readMoney()
	local slotsByNumber, levelsByNumber = readSlots()
	for _, tag in tagsByModel do
		refreshTag(tag, slotsByNumber, levelsByNumber, money)
	end
end

local function buildTag(model: Model, body: MeshPart, slotNumber: number): SlotTag
	local gui = Instance.new("BillboardGui")
	gui.Name = "UpgradeTag"
	gui.Size = UDim2.fromOffset(UPGRADE_TAG_WIDTH_PIXELS, UPGRADE_TAG_HEIGHT_PIXELS)
	-- Body BOTTOM (centre - half height) + lift. StudsOffset is measured from
	-- the adornee's own centre, and the facing correction is a pure yaw, so
	-- the body's local Y is world up and this is straight down in world space
	-- -- and, crucially, it is the same straight down whatever the breathing
	-- is doing (see UPGRADE_TAG_LIFT_STUDS).
	gui.StudsOffset = Vector3.new(0, -body.Size.Y / 2 + UPGRADE_TAG_LIFT_STUDS, 0)
	-- ON TOP, unlike the NameTag right above it -- and the difference is
	-- deliberate. A name that hides behind the scenery it is standing among is
	-- correct; a BUTTON you can see the edge of but cannot reliably click is
	-- not. The strip sits low on the slime, so its own body would occlude it
	-- from most angles otherwise. UPGRADE_TAG_MAX_DISTANCE_STUDS is what keeps
	-- that affordable: only the slime you are standing at ever draws one.
	gui.AlwaysOnTop = true
	gui.MaxDistance = UPGRADE_TAG_MAX_DISTANCE_STUDS
	gui.Parent = body

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, UPGRADE_TAG_BUTTON_GAP_PIXELS)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = gui

	local buttons: { TextButton } = {}
	for index, spec in UPGRADE_BUTTONS do
		local button = Instance.new("TextButton")
		button.Name = "Upgrade" .. spec.label
		button.LayoutOrder = index
		button.Size = UDim2.new(UPGRADE_TAG_BUTTON_WIDTH_SCALE, 0, 1, 0)
		button.BackgroundColor3 = BUTTON_DISABLED_COLOR
		button.BorderSizePixel = 0
		button.Font = Enum.Font.GothamBold
		button.TextScaled = true
		button.TextColor3 = BUTTON_TEXT_COLOR
		button.Text = ""
		button.Parent = gui

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 5)
		corner.Parent = button

		button.MouseButton1Click:Connect(function()
			-- The ONLY outgoing signal in this file, and it carries exactly
			-- what the inventory panel's equivalent button carries: a slot
			-- number and a count. No price, no level, no slime identity --
			-- there is nothing here for a modified client to inflate, and
			-- PlayerProfile.upgradeSlime recomputes all three from its own
			-- state regardless.
			upgradeSlimeRemote:FireServer(slotNumber, spec.count)
		end)

		buttons[index] = button
	end

	return { slotNumber = slotNumber, buttons = buttons }
end

local function attachTag(model: Model)
	if tagsByModel[model] or attachingModels[model] then
		return
	end
	-- THE FILTER, and the only one needed. The EntranceSign is a Model in this
	-- same folder and would otherwise be a candidate; it has no SlotNumber, so
	-- it never gets past here. Set by the server before the Model is parented
	-- (see PlayerProfile.spawnSlimeVisual), so it is always readable by the
	-- time any ChildAdded for that Model fires.
	local slotNumber = model:GetAttribute("SlotNumber")
	if typeof(slotNumber) ~= "number" then
		return
	end

	attachingModels[model] = true
	task.spawn(function()
		local body = model:WaitForChild(BODY_PART_NAME, BODY_WAIT_TIMEOUT_SECONDS)
		attachingModels[model] = nil
		-- Re-checked AFTER the yield: the slime may have been removed, sold,
		-- or the whole base torn down while this was waiting, and a tag built
		-- onto a destroyed model would linger in the registry forever.
		if not (body and body:IsA("MeshPart")) or model.Parent ~= baseFolder or tagsByModel[model] then
			return
		end
		tagsByModel[model] = buildTag(model, body :: MeshPart, slotNumber)
		refreshAllTags()
	end)
end

local function onBaseChild(child: Instance)
	if child:IsA("Model") then
		attachTag(child :: Model)
	end
end

for _, child in baseFolder:GetChildren() do
	onBaseChild(child)
end
baseFolder.ChildAdded:Connect(onBaseChild)

-- The BillboardGui itself dies with the Model (it is parented inside it), so
-- this only drops the registry entry -- without it, tagsByModel would grow by
-- one dead Model per slime ever removed, and refreshAllTags would keep
-- repainting buttons that no longer exist.
baseFolder.ChildRemoved:Connect(function(child)
	if child:IsA("Model") then
		tagsByModel[child :: Model] = nil
		attachingModels[child :: Model] = nil
	end
end)

-- Slots changes on every place/remove/sell/upgrade (it carries the levels, so
-- an upgrade landing IS a Slots change -- that is what makes the prices on
-- these buttons step up the instant a purchase goes through, alongside the
-- server's own refresh of the name/income lines above them). Money changes
-- every income tick; see refreshTag on why that is repainted unconditionally
-- here rather than gated the way the inventory panel gates its own.
baseFolder:GetAttributeChangedSignal("Slots"):Connect(refreshAllTags)
baseFolder:GetAttributeChangedSignal("Money"):Connect(refreshAllTags)
refreshAllTags()
