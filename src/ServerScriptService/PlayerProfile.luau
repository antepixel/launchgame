--!strict
-- Per-player base + income + collection + persistence -- this module is the
-- single owner of ALL per-player state that used to be split across the old
-- (server-wide) Base.luau and SlimeCollection.luau: money, slot contents,
-- and which slimes have ever been seen. Every player gets their OWN 10-slot
-- base, in-memory during the session and loaded/saved around a DataStore --
-- see PlayerStore.luau and the written report for the full persistence
-- story (what's saved, when, and exactly what a load failure does).
--
-- The swing's single shared rider slot (see LaunchServer's activePlayer) is
-- UNCHANGED and untouched by any of this -- whoever is currently riding is
-- still the only one who can launch, independent of how many players have
-- their own base sitting here.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local BaseConfig = require(ReplicatedStorage.Config.BaseConfig)
local BaseGeometry = require(ReplicatedStorage.Config.BaseGeometry)
local InventoryConfig = require(ReplicatedStorage.Config.InventoryConfig)
local LaunchConfig = require(ReplicatedStorage.Config.LaunchConfig)
local PersistenceConfig = require(ReplicatedStorage.Config.PersistenceConfig)
local ShopConfig = require(ReplicatedStorage.Config.ShopConfig)
local SlimeData = require(ReplicatedStorage.Config.SlimeData)
local PlayerStore = require(ServerScriptService.PlayerStore)

local PlayerProfile = {}

type Profile = {
	baseIndex: number,
	baseFolder: Folder,
	money: number,
	slots: { [number]: number }, -- slot number -> globalIndex, missing = empty
	visualParts: { [number]: BasePart }, -- slot number -> that slot's placeholder part, missing = empty
	-- UNPLACED copies held, stacked by globalIndex -> count (missing/0 =
	-- none held). Placed copies are NOT counted here -- they're already
	-- fully represented by `slots` above; a slime's TOTAL owned count is
	-- always `(inventory[globalIndex] or 0) + (however many slots hold it)`.
	-- Stacked rather than one entry per individual pull -- see the written
	-- report for why (a player will eventually hold hundreds of copies
	-- across only 65 distinct slimes; a stacked count keeps the list, the
	-- synced client payload, and the save data all bounded by 65, not by
	-- how many times the player has played).
	inventory: { [number]: number },
	seen: { [number]: boolean },
	-- Which swing tier this player has bought up to -- 1 for a fresh
	-- player, never bought DOWN, never skips (see buyNextTier below).
	-- Replaces the old server-wide, hand-edited LaunchConfig.
	-- ACTIVE_SWING_TIER -- see the written report.
	swingTier: number,
	-- false means "this session's load did not succeed" (see PlayerStore.
	-- load) -- while false, NOTHING here is ever saved, for this player, for
	-- the rest of this session. That's the only way to protect a real save
	-- that just happened to be unreadable right now -- see the written
	-- report.
	canSave: boolean,
}

local profiles: { [Player]: Profile } = {}

-- ===== Base index allocation: a stable, freed-on-leave slot per connected
-- player, read by BaseGeometry to decide WHERE that player's base sits.
-- Freed (not left incrementing forever) so a server that sees a lot of
-- join/leave churn over a long lifetime doesn't drift bases further and
-- further out for no reason. =====
local nextBaseIndex = 0
local freeBaseIndices: { number } = {}

local function allocateBaseIndex(): number
	if #freeBaseIndices > 0 then
		return table.remove(freeBaseIndices) :: number
	end
	local index = nextBaseIndex
	nextBaseIndex += 1
	return index
end

local function releaseBaseIndex(index: number)
	table.insert(freeBaseIndices, index)
end

-- ===== Base visuals -- moved here from the old BaseBuilder.server.luau,
-- which built ONE shared base at server start; now each player's base is
-- built on demand, the moment they join. Named deterministically by UserId
-- (Base_<UserId>) so BaseClient.client.luau can find each player's OWN base
-- with a plain WaitForChild, no remote round-trip needed. =====
local function buildBaseFolder(player: Player, baseIndex: number): Folder
	local folder = Instance.new("Folder")
	folder.Name = string.format("Base_%d", player.UserId)
	folder.Parent = Workspace

	local positions = BaseGeometry.slotPositions(baseIndex)
	for i, position in positions do
		local pad = Instance.new("Part")
		pad.Name = string.format("Slot%02d", i)
		pad.Anchored = true
		pad.CanCollide = true
		pad.Material = Enum.Material.SmoothPlastic
		pad.Size = BaseConfig.BASE_SLOT_PAD_SIZE
		pad.Color = BaseConfig.BASE_SLOT_PAD_COLOR
		pad.Position = position
		pad.Parent = folder

		local surfaceGui = Instance.new("SurfaceGui")
		surfaceGui.Name = "SlotLabel"
		surfaceGui.Face = Enum.NormalId.Top
		surfaceGui.LightInfluence = 0
		surfaceGui.PixelsPerStud = 24
		surfaceGui.Parent = pad

		local label = Instance.new("TextLabel")
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		label.Size = UDim2.fromScale(0.8, 0.8)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.5
		label.Text = tostring(i)
		label.Parent = surfaceGui
	end

	-- Nameplate over the whole base -- the one addition over the old
	-- single-shared-base visuals: with several of these now side by side,
	-- something has to say whose is whose at a glance. Text/colour only,
	-- same placeholder philosophy as everything else here.
	local nameplateAnchor = Instance.new("Part")
	nameplateAnchor.Name = "NameplateAnchor"
	nameplateAnchor.Anchored = true
	nameplateAnchor.CanCollide = false
	nameplateAnchor.Transparency = 1
	nameplateAnchor.Size = Vector3.new(1, 1, 1)
	nameplateAnchor.Position = positions[1] + Vector3.new(0, 6, 0)
	nameplateAnchor.Parent = folder

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NameplateGui"
	billboard.Size = UDim2.new(0, 220, 0, 44)
	billboard.AlwaysOnTop = true
	billboard.Parent = nameplateAnchor

	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.fromScale(1, 1)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.Text = string.format("%s's Base", player.Name)
	nameLabel.Parent = billboard

	folder:SetAttribute("Money", 0)
	folder:SetAttribute("SwingTier", 1)
	folder:SetAttribute("SaveDisabled", false)
	return folder
end

-- Matches BaseClient.client.luau's money formatter (itself matching
-- LuckCurve.formatLuck's style) -- kept as its own small local copy rather
-- than a shared module, same reasoning as LaunchClient duplicating the
-- swing math locally: this project keeps ONE tuning module per constant,
-- not a library of shared formatting helpers, and a per-slime income value
-- (SlimeConfig.SLIME_TIER_BASE_INCOME tops out at 1200) will realistically
-- never even need the K/M/B tiers -- kept anyway so a future retune of
-- those base-income numbers doesn't silently start printing an ugly
-- five-digit number.
local function formatIncomePerSecond(perSecond: number): string
	local magnitude = math.abs(perSecond)
	local scale, suffix = 1, ""
	if magnitude >= 1e9 then
		scale, suffix = 1e9, "B"
	elseif magnitude >= 1e6 then
		scale, suffix = 1e6, "M"
	elseif magnitude >= 1e3 then
		scale, suffix = 1e3, "K"
	end

	if suffix == "" then
		return string.format("$%d/s", perSecond)
	end
	local formatted = string.format("%.1f", perSecond / scale)
	formatted = formatted:gsub("%.0$", "")
	return "$" .. formatted .. suffix .. "/s"
end

local function spawnSlimeVisual(profile: Profile, slotNumber: number, slime: SlimeData.Slime)
	local part = Instance.new("Part")
	part.Name = slime.name
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.SmoothPlastic
	part.Size = BaseConfig.BASE_SLIME_PART_SIZE
	part.Color = slime.color

	local slotPosition = BaseGeometry.slotPosition(profile.baseIndex, slotNumber)
	local restHeight = BaseConfig.BASE_SLOT_PAD_SIZE.Y / 2 + BaseConfig.BASE_SLIME_PART_SIZE.Y / 2
	part.Position = slotPosition + Vector3.new(0, restHeight, 0)
	part.Parent = profile.baseFolder
	profile.visualParts[slotNumber] = part

	-- Two stacked lines -- name on top (tier-coloured, as before), income
	-- per second below it (green, matching the money readout's own colour
	-- so "this is money" reads instantly) -- a UIListLayout stacks them so
	-- neither has to hardcode the other's height. Tall/wide enough, and
	-- billboards always face the camera, to read clearly from a player
	-- standing at their own base looking at their slots.
	local nameTag = Instance.new("BillboardGui")
	nameTag.Name = "NameTag"
	nameTag.Size = UDim2.new(0, 180, 0, 60)
	nameTag.StudsOffset = Vector3.new(0, BaseConfig.BASE_SLIME_PART_SIZE.Y / 2 + 1, 0)
	nameTag.AlwaysOnTop = true
	nameTag.Parent = part

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = nameTag

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.LayoutOrder = 1
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, 0, 0, 34)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = slime.color
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.Text = slime.name
	nameLabel.Parent = nameTag

	local incomeLabel = Instance.new("TextLabel")
	incomeLabel.Name = "Income"
	incomeLabel.LayoutOrder = 2
	incomeLabel.BackgroundTransparency = 1
	incomeLabel.Size = UDim2.new(1, 0, 0, 24)
	incomeLabel.Font = Enum.Font.GothamBold
	incomeLabel.TextScaled = true
	incomeLabel.TextColor3 = Color3.new(0.4, 1, 0.5)
	incomeLabel.TextStrokeTransparency = 0.3
	incomeLabel.Text = formatIncomePerSecond(slime.incomePerSecond)
	incomeLabel.Parent = nameTag
end

-- ===== Client sync: the inventory UI (InventoryClient.client.luau) needs
-- structured data no single attribute value can hold on its own, so this
-- JSON-encodes it into TWO string attributes on the base folder -- "Slots"
-- (one {slot, globalIndex} entry per FILLED slot, so the UI can tell which
-- of the 10 are occupied without inspecting the 3D placeholder parts) and
-- "Inventory" (one {globalIndex, count} entry per UNPLACED stack). Same
-- "just an attribute, no remote needed" pattern Money/SwingTier already
-- use -- Roblox replicates attribute changes automatically. Called at the
-- end of every function in this file that touches slots or inventory, so
-- these two attributes are never stale by more than one function call.
local function syncClientState(profile: Profile)
	local slotEntries = {}
	for i = 1, BaseConfig.SLOT_COUNT do
		local globalIndex = profile.slots[i]
		if globalIndex then
			table.insert(slotEntries, { slot = i, globalIndex = globalIndex })
		end
	end
	profile.baseFolder:SetAttribute("Slots", HttpService:JSONEncode(slotEntries))

	local inventoryEntries = {}
	for globalIndex, count in profile.inventory do
		if count > 0 then
			table.insert(inventoryEntries, { globalIndex = globalIndex, count = count })
		end
	end
	profile.baseFolder:SetAttribute("Inventory", HttpService:JSONEncode(inventoryEntries))
end

-- ===== Save-shape adapters: the ONLY place that translates between the
-- in-memory Profile (a hash-set for `seen`, a sparse map for `slots`) and
-- the plain, DataStore-safe table PlayerStore reads/writes (a dense array
-- with a 0 sentinel for an empty slot, since DataStore arrays can't hold
-- holes reliably) -- see PlayerStore.luau. =====
local function toSaveShape(profile: Profile): { [string]: any }
	local slotsOut = table.create(BaseConfig.SLOT_COUNT, 0)
	for i = 1, BaseConfig.SLOT_COUNT do
		slotsOut[i] = profile.slots[i] or 0
	end
	local seenOut = {}
	for globalIndex, _ in profile.seen do
		table.insert(seenOut, globalIndex)
	end
	-- Same {globalIndex, count} record shape as the "Inventory" sync
	-- attribute above -- one representation, two uses, rather than
	-- inventing a second encoding just because one target is a DataStore
	-- and the other is a client-facing attribute.
	local inventoryOut = {}
	for globalIndex, count in profile.inventory do
		if count > 0 then
			table.insert(inventoryOut, { globalIndex = globalIndex, count = count })
		end
	end
	return {
		money = profile.money,
		slots = slotsOut,
		seen = seenOut,
		swingTier = profile.swingTier,
		inventory = inventoryOut,
	}
end

local function applyLoadedData(profile: Profile, data: { [string]: any }?)
	if not data then
		return
	end
	if typeof(data.money) == "number" then
		profile.money = data.money
	end
	local slots = data.slots
	if typeof(slots) == "table" then
		for i = 1, BaseConfig.SLOT_COUNT do
			local globalIndex = slots[i]
			if typeof(globalIndex) == "number" and globalIndex > 0 and SlimeData.SLIMES[globalIndex] then
				profile.slots[i] = globalIndex
			end
		end
	end
	-- Clamped to [1, tierCount], and floored, so a hand-edited or
	-- otherwise-malformed save value can never leave a player with a
	-- fractional or out-of-range tier -- see buyNextTier for the same
	-- tierCount source (#LaunchConfig.SWING_TIER_DISTANCE_SCALE).
	if typeof(data.swingTier) == "number" then
		local tierCount = #LaunchConfig.SWING_TIER_DISTANCE_SCALE
		profile.swingTier = math.clamp(math.floor(data.swingTier), 1, tierCount)
	end
	local seen = data.seen
	if typeof(seen) == "table" then
		for _, globalIndex in seen do
			if typeof(globalIndex) == "number" then
				profile.seen[globalIndex] = true
			end
		end
	end
	local inventory = data.inventory
	if typeof(inventory) == "table" then
		for _, entry in inventory do
			if
				typeof(entry) == "table"
				and typeof(entry.globalIndex) == "number"
				and typeof(entry.count) == "number"
				and entry.count > 0
				and SlimeData.SLIMES[entry.globalIndex]
			then
				profile.inventory[entry.globalIndex] = math.floor(entry.count)
			end
		end
	end
end

-- ===== Join: allocate a base, build its visuals immediately (so it's there
-- even before the load finishes), then load in the background and populate
-- money/slots/seen (and the slot visuals for anything already filled) once
-- it resolves. =====
local function onPlayerAdded(player: Player)
	local baseIndex = allocateBaseIndex()
	local baseFolder = buildBaseFolder(player, baseIndex)

	local profile: Profile = {
		baseIndex = baseIndex,
		baseFolder = baseFolder,
		money = 0,
		slots = {},
		visualParts = {},
		inventory = {},
		seen = {},
		swingTier = 1,
		canSave = false,
	}
	profiles[player] = profile

	task.spawn(function()
		local data, ok = PlayerStore.load(player.UserId)
		-- The player may already be gone by the time this resolves (a very
		-- quick join-then-leave) -- bail without touching anything further;
		-- onPlayerRemoving already cleaned up (or is about to).
		if profiles[player] ~= profile then
			return
		end

		if not ok then
			-- LOAD FAILURE: every retry in PlayerStore.load was exhausted.
			-- This player plays this session on a blank profile -- money 0,
			-- base empty -- but canSave STAYS false for the rest of the
			-- session, which is checked before every single save attempt
			-- below (both the periodic autosave loop and the leave-save).
			-- THAT is what makes this safe: whatever real save already
			-- exists in the DataStore (which is exactly why the read
			-- failed to confirm empty vs. populated) is never touched again
			-- by this session, so it can never be overwritten by the blank
			-- profile this player is about to play on. Flagged visibly too
			-- -- see BaseClient.client.luau's SaveDisabled handling.
			baseFolder:SetAttribute("SaveDisabled", true)
			return
		end

		applyLoadedData(profile, data)
		profile.canSave = true
		baseFolder:SetAttribute("Money", profile.money)
		baseFolder:SetAttribute("SwingTier", profile.swingTier)
		for i = 1, BaseConfig.SLOT_COUNT do
			local globalIndex = profile.slots[i]
			if globalIndex then
				spawnSlimeVisual(profile, i, SlimeData.SLIMES[globalIndex])
			end
		end
		syncClientState(profile)
	end)
end

-- ===== Leave: one last save (if this session was ever safe to save -- see
-- canSave above), then release everything this player's base was holding
-- onto -- the base index goes back to the free list and the visuals are
-- destroyed, so a later joiner handed this same index starts from a clean
-- folder, not one still showing the PREVIOUS owner's slimes. =====
local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	profiles[player] = nil

	if profile.canSave then
		PlayerStore.save(player.UserId, toSaveShape(profile), true)
	end

	profile.baseFolder:Destroy()
	releaseBaseIndex(profile.baseIndex)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- ===== The reveal hook: LaunchServer calls these two, and ONLY these two,
-- at the exact same two points the old SlimeCollection/Base modules were
-- called from (see LaunchServer.server.luau's onBoxPress) -- nothing about
-- the reveal's own sequencing changes. =====

-- Records a reveal and reports whether it was new -- same contract
-- SlimeCollection.recordSeen used to have, just scoped through this
-- player's own profile instead of a server-wide table.
function PlayerProfile.recordSeen(player: Player, globalIndex: number): boolean
	local profile = profiles[player]
	if not profile then
		return true
	end
	local isNew = not profile.seen[globalIndex]
	profile.seen[globalIndex] = true
	return isNew
end

-- Called once per reveal, ONLY from LaunchServer's onBoxPress. Auto-places
-- the revealed slime into the FIRST empty slot of THIS player's own base if
-- one exists -- requirement: don't make the player open a menu for their
-- first ten. If every slot is already full, the slime goes to INVENTORY
-- instead -- nothing is ever discarded anymore (that was the old, TEMPORARY
-- behaviour from before an inventory existed). Returns true if it was
-- placed into a slot, false if it went to inventory instead -- purely
-- informational for the caller (see DevPanelServer's log text); nothing
-- downstream branches on it.
function PlayerProfile.receiveSlime(player: Player, slime: SlimeData.Slime): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	for i = 1, BaseConfig.SLOT_COUNT do
		if not profile.slots[i] then
			profile.slots[i] = slime.globalIndex
			spawnSlimeVisual(profile, i, slime)
			syncClientState(profile)
			return true
		end
	end
	profile.inventory[slime.globalIndex] = (profile.inventory[slime.globalIndex] or 0) + 1
	syncClientState(profile)
	return false
end

-- ===== Inventory actions: place/remove/sell -- see InventoryServer.server.
-- luau (the only caller of any of these three) for the remote plumbing.
-- EVERY validation (ownership, slot availability, quantity) happens here,
-- against this player's own server-held profile -- never against anything
-- the client claims. =====

-- Moves ONE copy of `globalIndex` from inventory into the first free slot.
-- Fails if the player doesn't hold an unplaced copy, or if the base is
-- already full -- deliberately NOT auto-swapping anything out to make
-- room: the player has to REMOVE a slot themselves first (see
-- removeToInventory). Which specific free slot it lands in is not
-- meaningful (slots are otherwise interchangeable), so it's not a
-- parameter -- same "first empty slot" convention used everywhere else in
-- this file.
function PlayerProfile.placeFromInventory(player: Player, globalIndex: number): (boolean, string?)
	local profile = profiles[player]
	if not profile then
		return false, "no profile"
	end
	local slime = SlimeData.SLIMES[globalIndex]
	if not slime then
		return false, "unknown slime"
	end
	local owned = profile.inventory[globalIndex] or 0
	if owned <= 0 then
		return false, "you don't have that slime in your inventory"
	end

	for i = 1, BaseConfig.SLOT_COUNT do
		if not profile.slots[i] then
			profile.slots[i] = globalIndex
			spawnSlimeVisual(profile, i, slime)
			if owned <= 1 then
				profile.inventory[globalIndex] = nil
			else
				profile.inventory[globalIndex] = owned - 1
			end
			syncClientState(profile)
			return true, nil
		end
	end
	return false, "no free slot -- remove one first"
end

-- Moves the slime in slot `slotNumber` back to inventory, freeing the slot.
-- Fails if the slot number is out of range or already empty.
function PlayerProfile.removeToInventory(player: Player, slotNumber: number): (boolean, string?)
	local profile = profiles[player]
	if not profile then
		return false, "no profile"
	end
	if typeof(slotNumber) ~= "number" or slotNumber ~= math.floor(slotNumber) or slotNumber < 1 or slotNumber > BaseConfig.SLOT_COUNT then
		return false, "invalid slot"
	end
	local globalIndex = profile.slots[slotNumber]
	if not globalIndex then
		return false, "that slot is already empty"
	end

	profile.slots[slotNumber] = nil
	local part = profile.visualParts[slotNumber]
	if part then
		part:Destroy()
		profile.visualParts[slotNumber] = nil
	end
	profile.inventory[globalIndex] = (profile.inventory[globalIndex] or 0) + 1
	syncClientState(profile)
	return true, nil
end

-- Sells `quantity` UNPLACED copies of `globalIndex` for money -- ONLY ever
-- reads/decrements `profile.inventory`, never `profile.slots`, which is
-- what makes "you must remove a placed slime before you can sell it" true
-- by construction rather than by a runtime check here (see the written
-- report for why that was chosen over a confirmation prompt). Sell value
-- is incomePerSecond * InventoryConfig.SELL_VALUE_INCOME_MULTIPLIER *
-- quantity -- fails outright (no partial sale) if the player doesn't hold
-- at least `quantity` unplaced copies.
function PlayerProfile.sellFromInventory(player: Player, globalIndex: number, quantity: number): (boolean, string?)
	local profile = profiles[player]
	if not profile then
		return false, "no profile"
	end
	if typeof(quantity) ~= "number" or quantity ~= math.floor(quantity) or quantity < 1 then
		return false, "invalid quantity"
	end
	local slime = SlimeData.SLIMES[globalIndex]
	if not slime then
		return false, "unknown slime"
	end
	local owned = profile.inventory[globalIndex] or 0
	if owned < quantity then
		return false, "you don't have that many in your inventory"
	end

	if owned <= quantity then
		profile.inventory[globalIndex] = nil
	else
		profile.inventory[globalIndex] = owned - quantity
	end

	local proceeds = slime.incomePerSecond * InventoryConfig.SELL_VALUE_INCOME_MULTIPLIER * quantity
	profile.money += proceeds
	profile.baseFolder:SetAttribute("Money", profile.money)
	syncClientState(profile)
	return true, nil
end

-- ===== Swing shop: buy the next tier with money -- see ShopServer.server.
-- luau (the only caller) for the remote plumbing. THIS function is the
-- entire server-side validation: order (always exactly current+1, never a
-- client-supplied tier number), price, and funds are all checked here, from
-- this player's own server-held profile, never from anything the client
-- sent. =====

-- This player's currently-owned swing tier -- read by LaunchServer's
-- onRelease (replacing the old server-wide LaunchConfig.ACTIVE_SWING_TIER)
-- and by the shop UI. Defaults to 1 for a player with no profile yet (e.g.
-- a very early call before onPlayerAdded's join logic has run) -- same
-- "fail toward the harmless default" reasoning as recordSeen's `true`
-- above.
function PlayerProfile.getSwingTier(player: Player): number
	local profile = profiles[player]
	if not profile then
		return 1
	end
	return profile.swingTier
end

-- Buys EXACTLY the next tier after this player's current one -- there is no
-- "which tier" argument anywhere in this call chain (see ShopServer's
-- onBuyTier), so a modified client cannot ask to buy tier 11 while sitting
-- on tier 1: the tier being bought is always `profile.swingTier + 1`,
-- decided here, not supplied over the wire. Returns (true, nil) on success,
-- or (false, reason) on failure -- ShopServer forwards `reason` to the
-- client for a one-line status message; nothing about it is trusted for
-- anything beyond display.
function PlayerProfile.buyNextTier(player: Player): (boolean, string?)
	local profile = profiles[player]
	if not profile then
		return false, "no profile"
	end

	local tierCount = #LaunchConfig.SWING_TIER_DISTANCE_SCALE
	local nextTier = profile.swingTier + 1
	if nextTier > tierCount then
		return false, "already at the max tier"
	end

	local price = ShopConfig.SWING_TIER_PRICES[nextTier]
	if profile.money < price then
		return false, "not enough money"
	end

	profile.money -= price
	profile.swingTier = nextTier
	profile.baseFolder:SetAttribute("Money", profile.money)
	profile.baseFolder:SetAttribute("SwingTier", profile.swingTier)
	return true, nil
end

-- ===== Income: paid out on a fixed TICK, not continuously -- a discrete
-- lump added once every BaseConfig.BASE_INCOME_TICK_SECONDS, not a smooth
-- per-Heartbeat crawl. The lump is totalIncomePerSecond(profile) * the
-- ACTUAL tick length (not always exactly totalIncomePerSecond as-is), so
-- the effective payout rate stays correct however that config value is
-- tuned -- at the default of 1, this is exactly "sum every placed slime's
-- income per second, add that total in one lump, once a second," and at
-- any other interval it still pays the same rate, just chunked coarser or
-- finer. Every connected player's base earns independently of whether they
-- currently hold the swing's shared rider slot.
local function totalIncomePerSecond(profile: Profile): number
	local total = 0
	for i = 1, BaseConfig.SLOT_COUNT do
		local globalIndex = profile.slots[i]
		if globalIndex then
			local slime = SlimeData.SLIMES[globalIndex]
			if slime then
				total += slime.incomePerSecond
			end
		end
	end
	return total
end

task.spawn(function()
	while true do
		task.wait(BaseConfig.BASE_INCOME_TICK_SECONDS)
		for _, profile in profiles do
			local income = totalIncomePerSecond(profile)
			if income > 0 then
				profile.money += income * BaseConfig.BASE_INCOME_TICK_SECONDS
				profile.baseFolder:SetAttribute("Money", profile.money)
			end
		end
	end
end)

-- ===== Periodic autosave: every connected, currently-safe-to-save profile,
-- on a fixed timer -- independent of the Heartbeat loop above (minutes, not
-- frames). =====
task.spawn(function()
	while true do
		task.wait(PersistenceConfig.AUTO_SAVE_INTERVAL_SECONDS)
		for player, profile in profiles do
			if profile.canSave then
				PlayerStore.save(player.UserId, toSaveShape(profile), false)
			end
		end
	end
end)

-- ===== Shutdown: best-effort final save for everyone still connected when
-- the server itself is going down -- same reasoning as the leave-save (a
-- server shutting down removes every remaining player at once, so this is
-- really the same case, just triggered by Roblox instead of a disconnect).
-- Fired CONCURRENTLY (not one after another): Roblox only gives a
-- BindToClose callback a bounded window (~30s) before closing the server
-- regardless, and each individual save can itself take several seconds
-- across retries -- saving players one at a time could mean the ones later
-- in the table never get attempted at all before the window runs out.
-- Different players' saves never contend with each other (PlayerStore's
-- savesInFlight mutex is keyed per UserId), so there's nothing to lose by
-- letting them all run at once.
game:BindToClose(function()
	local pending = 0
	for player, profile in profiles do
		if profile.canSave then
			pending += 1
			task.spawn(function()
				PlayerStore.save(player.UserId, toSaveShape(profile), true)
				pending -= 1
			end)
		end
	end
	while pending > 0 do
		task.wait()
	end
end)

-- ================================================================
-- ===== DEV PANEL SUPPORT -- see DevPanelServer.server.luau ======
-- Only ever called from DevPanelServer.server.luau, which is itself hard-
-- gated on RunService:IsStudio() plus a UserId allowlist checked on every
-- action -- see that file for both gates. These functions are harmless if
-- never called (which is exactly what happens in a published server, since
-- DevPanelServer creates no remotes there at all) -- kept here rather than
-- in DevPanelServer itself only because the task constraint is "dev actions
-- go through PlayerProfile so saves stay consistent," i.e. this is the one
-- place allowed to touch a profile's money/slots/seen directly.
--
-- TO FULLY REMOVE THE DEV PANEL: delete this whole block (down to
-- `return PlayerProfile` below), plus DevPanelServer.server.luau,
-- DevPanelClient.client.luau, and DevConfig.luau -- see the written report
-- for the exact file list. Nothing above this line calls anything below it.
-- ================================================================

-- Sets money to an exact value (clamped to >= 0) -- covers both "set an
-- exact value" and "remove money -> set to zero" (amount = 0).
function PlayerProfile.devSetMoney(player: Player, amount: number)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.money = math.max(0, amount)
	profile.baseFolder:SetAttribute("Money", profile.money)
end

-- Adds a (possibly negative) delta to money, clamped to >= 0 -- covers the
-- fixed +1K/+100K/+10M quick-give buttons AND "subtract" (a negative delta).
function PlayerProfile.devAddMoney(player: Player, delta: number)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.money = math.max(0, profile.money + delta)
	profile.baseFolder:SetAttribute("Money", profile.money)
end

-- Empties every slot in this player's base -- routed through the SAME
-- removeToInventory every real "Remove" button click uses, so a dev action
-- can no longer silently DESTROY a player's slimes now that a real
-- inventory exists to hold them: everything cleared from the base lands
-- back in inventory, exactly as if the player had removed each slot by
-- hand.
function PlayerProfile.devClearBase(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	for i = 1, BaseConfig.SLOT_COUNT do
		if profile.slots[i] then
			PlayerProfile.removeToInventory(player, i)
		end
	end
end

-- Resets this player's ENTIRE profile (money, slots, inventory, collection,
-- swing tier) to a fresh-player state, then immediately persists that fresh
-- state -- so a rejoin shows the true first-time experience right away, not
-- whatever was last saved. Respects the SAME canSave gate as every other
-- save (see onPlayerAdded's LOAD FAILURE handling): if this session's own
-- load never succeeded, the wipe still happens in memory (so the panel
-- visibly does what it says), but is NOT persisted -- a dev action must not
-- become the one path that bypasses the "never write over an unreadable
-- real save" rule the rest of this module enforces.
function PlayerProfile.devWipeProfile(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	PlayerProfile.devClearBase(player)
	profile.money = 0
	profile.baseFolder:SetAttribute("Money", 0)
	profile.inventory = {}
	profile.seen = {}
	profile.swingTier = 1
	profile.baseFolder:SetAttribute("SwingTier", 1)
	syncClientState(profile)
	if profile.canSave then
		PlayerStore.save(player.UserId, toSaveShape(profile), false)
	end
end

-- Sets this player's swing tier DIRECTLY, bypassing price/order checks
-- entirely -- for testing tier feel without grinding or wiring up fake
-- money. Clamped to [1, tierCount] the same way a loaded save value is (see
-- applyLoadedData) so a typo in the dev panel can't leave a profile with an
-- out-of-range tier.
function PlayerProfile.devSetSwingTier(player: Player, tier: number)
	local profile = profiles[player]
	if not profile then
		return
	end
	local tierCount = #LaunchConfig.SWING_TIER_DISTANCE_SCALE
	profile.swingTier = math.clamp(math.floor(tier), 1, tierCount)
	profile.baseFolder:SetAttribute("SwingTier", profile.swingTier)
end
-- ===== END DEV PANEL SUPPORT =====

return PlayerProfile
