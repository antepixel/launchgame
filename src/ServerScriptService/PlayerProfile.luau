--!strict
-- Per-player base + income + collection + persistence -- this module is the
-- single owner of ALL per-player state that used to be split across the old
-- (server-wide) Base.luau and SlimeCollection.luau: money, slot contents,
-- and which slimes have ever been seen. Every player gets their OWN 10-slot
-- base, in-memory during the session and loaded/saved around a DataStore --
-- see PlayerStore.luau and the written report for the full persistence
-- story (what's saved, when, and exactly what a load failure does).
--
-- The swing/launch loop (see LaunchServer.server.luau) is untouched by any
-- of this -- every player rides/launches/opens boxes on their own lane,
-- independently, and this module never reads or writes any of that state,
-- regardless of how many players have their own base sitting here.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local BaseConfig = require(ReplicatedStorage.Config.BaseConfig)
local BaseGeometry = require(ReplicatedStorage.Config.BaseGeometry)
local GroundConfig = require(ReplicatedStorage.Config.GroundConfig)
local InventoryConfig = require(ReplicatedStorage.Config.InventoryConfig)
local LaneConfig = require(ReplicatedStorage.Config.LaneConfig)
local LaunchConfig = require(ReplicatedStorage.Config.LaunchConfig)
-- For the leaderboard's Money and $/s columns. THE SHARED formatter, not a
-- local copy like formatIncomePerSecond below: the leaderboard's Money column
-- and the HUD's money readout are two views of the same number, and MoneyFormat
-- exists precisely so those cannot render it differently (see its own header,
-- which makes the same argument about the HUD and the shop's prices).
local MoneyFormat = require(ReplicatedStorage.Config.MoneyFormat)
local OfflineIncome = require(ReplicatedStorage.Config.OfflineIncome)
local PersistenceConfig = require(ReplicatedStorage.Config.PersistenceConfig)
local ShopConfig = require(ReplicatedStorage.Config.ShopConfig)
local SignBuilder = require(ReplicatedStorage.SignBuilder)
local SlimeBuilder = require(ReplicatedStorage.SlimeBuilder)
local SlimeData = require(ReplicatedStorage.Config.SlimeData)
local SlimeUpgrade = require(ReplicatedStorage.Config.SlimeUpgrade)
local SlimeUpgradeConfig = require(ReplicatedStorage.Config.SlimeUpgradeConfig)
local PlayerStore = require(ServerScriptService.PlayerStore)
-- Sound is BROADCAST, never played here (see SoundBroadcast.luau). The single
-- call below is a bare notification added beside a decision already made; no
-- collect behaviour changes.
local SoundBroadcast = require(ServerScriptService.SoundBroadcast)

local PlayerProfile = {}

type Profile = {
	baseIndex: number,
	baseFolder: Folder,
	-- ===== THE ROBLOX LEADERBOARD (see REPORT.md). Carried on the profile the
	-- same way baseFolder is, and for the same reason: every function here
	-- already has a profile in hand, so a refresh needs no reverse lookup from
	-- Player and no second registry to keep in step. The three Value instances
	-- are held directly rather than found by name on each refresh -- FindFirstChild
	-- on a three-child folder is cheap, but these never move and never change
	-- identity, so looking them up repeatedly would be re-deriving a constant.
	leaderstats: {
		folder: Folder,
		swing: IntValue,
		money: StringValue,
		rate: StringValue,
	},
	money: number,
	-- ===== THE PENDING POTS: income earned but not yet banked, ONE POT PER
	-- SLOT -- slot number -> dollars, missing = nothing pending. Every second of
	-- income -- online (the tick below) and offline (creditOfflineIncome, on
	-- load) -- lands in the pot of THE SLOT THAT EARNED IT, never straight in
	-- `money`. Walking over slot N's own collect pad moves slot N's pot to
	-- `money` and zeroes it; the other nine are untouched.
	--
	-- ONE POT PER SLOT, REPLACING THE SINGLE PER-PLAYER POT A PREVIOUS PASS
	-- BUILT (see REPORT.md). The single pot came with a single return pad on the
	-- approach link, which made collection free -- and meant the player never
	-- walked into their own base at all: ten slimes, their colours, their
	-- levels, the plot they paid for, all collapsed into one number in the HUD.
	-- The pads in front of the slimes are where the collection fantasy lives, so
	-- the money lives there too, and going to get it is a decision (keep
	-- launching, or go bank) rather than something that happens to the player on
	-- a walk they were already making.
	--
	-- NO CAP WHILE ONLINE. A pot grows unbounded for as long as the player does
	-- not come and take it; an AFK player is ONLINE and earns at full rate. The
	-- cap in OfflineIncome applies to ABSENCE only, and that asymmetry is
	-- deliberate -- see BaseConfig.OFFLINE_CAP_SECONDS.
	--
	-- NOT SPENDABLE, and that is structural rather than enforced: the only two
	-- balance checks in this file (upgradeSlime, buyNextTier) compare against
	-- `money` and nothing sums the two. There is deliberately no
	-- spendableMoney() helper -- adding one is the single change that would
	-- break the property, so the absence is the guarantee.
	pendingBySlot: { [number]: number },
	-- How much was credited by THIS session's offline accrual, TOTALLED across
	-- every slot. Purely for the UI's one-time "while you were away" line, which
	-- is why it is tracked apart from the pots rather than inferred from them --
	-- once the tick has added a second of online income the two are no longer
	-- separable.
	--
	-- ONE FIGURE, NOT TEN (see REPORT.md §2f): the line it feeds is one summary
	-- sentence on the HUD, shown once on return. A per-slot breakdown would have
	-- to be rendered somewhere, and the only surface that could carry it is the
	-- pads themselves -- which already show that slot's pot, of which the
	-- offline share is an invisible fraction the player has no decision to make
	-- about. Zeroed by the first collect at ANY pad, and NEVER persisted: it
	-- describes this session's arrival, and a save that carried it would
	-- re-announce a credit the player has already been shown.
	offlineCredit: number,
	-- os.clock() of this profile's last successful collect PER SLOT, for the
	-- Touched debounce (see collectPending). Keyed by slot, not one number for
	-- the whole player: walking the row crosses up to ten pads inside one
	-- debounce window and every one of them must pay. Lives on the PROFILE
	-- rather than in a module-level table keyed by Player so it is destroyed
	-- with the profile and needs no cleanup in onPlayerRemoving.
	lastCollectAtBySlot: { [number]: number },
	slots: { [number]: number }, -- slot number -> globalIndex, missing = empty
	visualParts: { [number]: Model }, -- slot number -> that slot's slime Model (see SlimeBuilder.luau), missing = empty
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
	-- PLACED slimes only -- slot number -> level (1..SlimeUpgradeConfig.
	-- MAX_LEVEL), missing = that slot is empty (never meaningfully queried
	-- when empty). Deliberately keyed by SLOT, not by globalIndex: a level is
	-- a property of "the individual slime currently working this slot," not
	-- of "this slime species" -- see the written report for why that's what
	-- makes leveling coexist with the stacked, count-only `inventory` above.
	-- Set to 1 the moment a slime is placed into a slot (receiveSlime,
	-- placeFromInventory) and cleared the moment it's removed
	-- (removeToInventory) -- a slime's level is NOT preserved across a trip
	-- back into inventory; it merges back into the fungible, unleveled stack
	-- and starts over at 1 if placed again.
	levels: { [number]: number },
	-- Which swing tier this player has bought up to -- 1 for a fresh
	-- player, never bought DOWN, never skips (see buyNextTier below).
	-- Replaces the old server-wide, hand-edited LaunchConfig.
	-- ACTIVE_SWING_TIER -- see the written report.
	swingTier: number,
	-- ===== TREASURE (see TreasureConfig.luau and REPORT.md) =====
	-- How many chests this player has ever opened. A COUNT, not a boolean, and
	-- the crown on their entrance sign renders off `>= 1`. A boolean would have
	-- matched the requirement exactly ("permanently marks the player"), but a
	-- count costs the same bytes, is not lossy, and answers "how many" later
	-- without a save migration -- and the one thing a boolean buys, that you
	-- cannot accidentally draw three crowns, is better handled by the renderer
	-- only ever asking `>= 1`.
	chestsOpened: number,
	-- An EARNED-BUT-UNOPENED chest. Persisted deliberately: session state is
	-- wiped by death, disconnect and respawn, and losing a 20%-Divine reward to
	-- a network blip would be the worst failure this feature could have. The
	-- player cannot walk back to the platform from their base, so this is not
	-- free money -- it just survives bad luck with the network.
	chestPending: boolean,
	-- false means "this session's load did not succeed" (see PlayerStore.
	-- load) -- while false, NOTHING here is ever saved, for this player, for
	-- the rest of this session. That's the only way to protect a real save
	-- that just happened to be unreadable right now -- see the written
	-- report.
	canSave: boolean,
}

local profiles: { [Player]: Profile } = {}

-- Players.MaxPlayers is read-only at runtime -- it cannot be assigned from
-- a script (assigning it here throws and takes the whole server down with
-- it, since every module below requires this one). It must be set by hand
-- in the PUBLISHED place's Game Settings instead, to LaneConfig.LANE_COUNT
-- (6). That setting is NOT version-controlled: it lives only in the
-- published place, will not update if LANE_COUNT ever changes, and there is
-- nothing in this repo enforcing that the two stay in sync.

-- ===== Base index allocation: a stable, freed-on-leave slot per connected
-- player, read by BaseGeometry to decide WHERE that player's base sits, and
-- (see LaunchServer.server.luau) reused directly as that player's swing
-- lane index -- no second parallel index. Freed (not left incrementing
-- forever) so a server that sees a lot of join/leave churn over a long
-- lifetime doesn't drift bases further and further out for no reason.
--
-- BOUNDED to [0, LaneConfig.LANE_COUNT - 1] now (see the written report):
-- there are only LANE_COUNT physical lanes for a base/swing to occupy, so
-- allocating past that would hand out an index nothing can place. Players.
-- MaxPlayers above is the PRIMARY enforcement (a 7th player should never
-- reach PlayerAdded on this server at all) -- this bound is the
-- defense-in-depth backstop for whatever gets a 7th player in anyway
-- (a Reserved Server, a teleport that bypasses normal matchmaking, a race
-- at the boundary). Fails LOUD, not silently: returns nil rather than
-- handing out an out-of-range 6, so onPlayerAdded below can reject that
-- join outright instead of building a base/lane nothing can display. =====
local nextBaseIndex = 0
local freeBaseIndices: { number } = {}

local function allocateBaseIndex(): number?
	if #freeBaseIndices > 0 then
		return table.remove(freeBaseIndices) :: number
	end
	if nextBaseIndex >= LaneConfig.LANE_COUNT then
		return nil
	end
	local index = nextBaseIndex
	nextBaseIndex += 1
	return index
end

local function releaseBaseIndex(index: number)
	table.insert(freeBaseIndices, index)
end

-- ===== Slot pad lookup -- the ten pads are now static per-lane world
-- dressing built once, for every lane, by MapBuilder.server.luau (see
-- BaseConfig/BaseGeometry's written report on the map blockout). This
-- module never builds a pad -- it only finds the one MapBuilder already
-- built for a given lane + slot number and reads its Position/Size back,
-- so a slime part always lands on the REAL pad instance rather than a
-- second, independently-computed guess at where that pad ought to be.
-- WaitForChild (not FindFirstChild) because MapBuilder.server.luau and this
-- module are both top-level scripts with no guaranteed run order -- this
-- yields, rather than erroring, on the rare case this module resolves
-- first. =====
local mapBlockout = Workspace:WaitForChild("MapBlockout")

local function getSlotPad(baseIndex: number, slotNumber: number): BasePart
	local laneFolder = mapBlockout:WaitForChild(string.format("Lane%02d", baseIndex))
	return laneFolder:WaitForChild(string.format("Slot%02d", slotNumber)) :: BasePart
end

-- ===== Base visuals -- moved here from the old BaseBuilder.server.luau,
-- which built ONE shared base at server start; now each player's base is
-- built on demand, the moment they join. Named deterministically by UserId
-- (Base_<UserId>) so BaseClient.client.luau can find each player's OWN base
-- with a plain WaitForChild, no remote round-trip needed. =====
-- Which way a player is looking when they walk into their own plot -- they
-- come up the spur from the walkway (PathConfig.BACK_WALKWAY_Z) moving in +Z,
-- so the sign's board has to point back down that approach, toward -Z.
local SIGN_FACE_DIRECTION = Vector3.new(0, 0, -1)

-- ===== THE RETURN PAD IS GONE (see REPORT.md STEP 4). An eleventh collect pad
-- used to be built here, on the approach link, banking the whole single pot on
-- the walk back to the swing. With one pot per slot it would let a player bank
-- ten slimes' earnings without ever entering their base, which is exactly the
-- thing this pass exists to stop -- so the pad, its geometry
-- (BaseGeometry.returnPadPlacement), its two margin constants in BaseConfig and
-- its world label in BaseClient all went with it. The ten per-slot pads in the
-- plot are now the only way pending income becomes cash.
local function buildBaseFolder(player: Player, baseIndex: number): Folder
	local folder = Instance.new("Folder")
	folder.Name = string.format("Base_%d", player.UserId)
	folder.Parent = Workspace

	-- A PHYSICAL WOODEN SIGN AT THE PLOT ENTRANCE, replacing the floating
	-- "<name>'s Base" BillboardGui that used to hang over slot 1 (see the
	-- written report). With several bases side by side something still has to
	-- say whose is whose at a glance, but the old billboard did it by hanging
	-- a pixel-Offset-sized GUI in the air -- and a BillboardGui's Offset is
	-- SCREEN PIXELS, so it held a fixed size at every distance and read as a
	-- grey band on the horizon from anywhere on the map. This is real
	-- geometry with a SurfaceGui painted on it, so it shrinks with distance
	-- like everything else and needs no MaxDistance clamp to stay out of the
	-- skyline.
	local sign = SignBuilder.build(
		string.format("%s's Base", player.Name),
		player.UserId,
		BaseConfig.BASE_SIGN_WIDTH_STUDS
	)
	sign.Name = "EntranceSign"

	-- FACE IT AT THE APPROACHING PLAYER, VERIFIED RATHER THAN ASSUMED. The
	-- board's own exposed face is measured from the asset's geometry at
	-- module load (SignBuilder.BOARD_FACE_AXIS -- the post sits behind the
	-- board's +Z side, leaving -Z flat and unobstructed), and faceCFrame
	-- turns "point that face this way" into a CFrame off that measurement
	-- instead of relying on lookAt's -Z-is-forward convention happening to
	-- line up. It currently does line up exactly, but that is a fact about
	-- this export, not something this call depends on.
	--
	-- THEN TURN IT IN TOWARD THE PATH (BASE_SIGN_YAW_DEGREES), the way a sign
	-- at the mouth of a driveway angles to greet you. Composed on the RIGHT,
	-- so it is a yaw in the SIGN'S OWN frame applied on top of whatever
	-- faceCFrame decided -- which is what keeps the asset's self-correction
	-- intact. Working it through both cases: with the board on -Z (today) the
	-- face axis is local -Z and faceCFrame returns identity, so the composed
	-- face lands at (-sin, 0, -cos); with the board re-exported onto +Z the
	-- face axis is local +Z and faceCFrame returns a 180-degree yaw, and the
	-- composed face lands at (-sin, 0, -cos) again -- identical. NEGATIVE
	-- because a positive yaw about +Y would swing the face toward -X, away
	-- from the path; the sign stands on the path's -X side and has to turn
	-- toward +X.
	local signPosition = BaseGeometry.entranceSignPosition(baseIndex)
	local signYaw = CFrame.Angles(0, -math.rad(BaseConfig.BASE_SIGN_YAW_DEGREES), 0)
	sign:PivotTo(SignBuilder.faceCFrame(signPosition, SIGN_FACE_DIRECTION) * signYaw)

	-- Sit it ON the ground -- MEASURED, not a hardcoded rest height (see
	-- SignBuilder.worldAABB: an explicit world-axis AABB over every
	-- descendant's transformed corners, never Model:GetBoundingBox, which
	-- returns an ORIENTED box whose axes can come back permuted). Shifting
	-- the whole model up by (targetY - minCorner.Y) lands the post's foot
	-- exactly on the ground, whatever the mesh's own internal pivot is --
	-- and it is measured AFTER the rotation above, so it reflects the pose
	-- the sign actually ends up in.
	local minCorner = SignBuilder.worldAABB(sign)
	sign:PivotTo(sign:GetPivot() + Vector3.new(0, signPosition.Y - minCorner.Y, 0))
	sign.Parent = folder

	-- Replicated exactly the way Money is -- plain attributes on this player's
	-- own base folder, which Roblox replicates for free. No remote: the pad
	-- labels and the HUD readout are pure renderings of these three values (see
	-- BaseClient.client.luau), and the client is never asked what they are.
	--
	-- PendingIncome is the TOTAL across every slot (what the HUD shows, so a
	-- player standing at the swing can decide whether the trip is worth making);
	-- PendingBySlot is the per-slot breakdown the ten pad labels render from,
	-- JSON-encoded exactly the way Slots/Inventory already are -- see
	-- publishPending.
	folder:SetAttribute("Money", 0)
	folder:SetAttribute("PendingIncome", 0)
	folder:SetAttribute("PendingBySlot", "[]")
	folder:SetAttribute("OfflineCredit", 0)
	folder:SetAttribute("SwingTier", 1)
	folder:SetAttribute("SaveDisabled", false)
	return folder
end

-- ===== THE ROBLOX LEADERBOARD (see REPORT.md). Three columns -- Swing, Money,
-- $/s -- on the built-in player list, which costs no UI work, is always
-- visible, and makes six players' numbers visible to each other. It is also the
-- ONLY place in the game that shows a player their own total income per second:
-- the HUD shows banked money, the current tier and the pending pot's total, and
-- nothing anywhere showed a rate.
--
-- PARENTED TO THE PLAYER, named exactly "leaderstats" -- both are Roblox
-- requirements, not choices: the engine looks for a child of the Player with
-- that exact name and renders its Value children as columns. Built here rather
-- than in a separate script for the same reason the base folder is built here:
-- this module is the single owner of all per-player state, and a second script
-- writing to the same player would need its own copy of the profile lookup.
--
-- COLUMN ORDER IS PARENT ORDER. Roblox's player list shows the values in the
-- order they were parented into the folder, so Swing, Money, $/s below is the
-- order they appear left to right.
--
-- ===== WHY MONEY AND $/s ARE StringValues, AND WHAT IT COSTS.
--
-- An IntValue is a signed 32-bit integer and caps at 2,147,483,647 -- which
-- MoneyFormat renders as "$2.1B". The top swing tier costs $800B, i.e. 373x
-- that cap, and a fully levelled ceiling base earns $244.5M/s and would blow
-- through it in under ten seconds of holding. An integer column would therefore
-- overflow well inside ordinary play, not at some theoretical extreme. A
-- NumberValue (double) would hold the magnitude but renders as raw
-- "8.0000000000e+11" in the player list, which is worse than useless.
--
-- THE COST, STATED PLAINLY SO NOBODY "FIXES" IT LATER: Roblox sorts StringValue
-- columns ALPHABETICALLY, not numerically. So "$9.1M" sorts above "$800B", and
-- the Money and $/s columns are therefore NOT a ranking -- they are readouts
-- that happen to sit next to each other. This is accepted deliberately. The
-- alternative is a custom scoreboard GUI: a ScreenGui, a sorted list, per-player
-- rows, a refresh path, and six rows of layout to maintain -- a great deal of UI
-- for the gain of one column sorting properly. If a real ranking is ever wanted,
-- build the custom board; do NOT convert these to IntValues, which would trade
-- a cosmetic sort problem for silently wrong numbers.
--
-- Swing IS an IntValue, and that is exactly why: the tier is 1-10, reads
-- naturally as a bare number, and sorts numerically -- so the one column where
-- ranking is meaningful and possible gets it.
local function buildLeaderstats(player: Player)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"

	local swing = Instance.new("IntValue")
	swing.Name = "Swing"
	-- 1, not 0: every profile starts on tier 1 (see the Profile literal in
	-- onPlayerAdded and buildBaseFolder's own SwingTier attribute), so this is
	-- the true value for a brand-new player rather than a placeholder that has
	-- to be corrected. See refreshLeaderstats on the load window.
	swing.Value = 1
	swing.Parent = folder

	local money = Instance.new("StringValue")
	money.Name = "Money"
	money.Value = MoneyFormat.format(0)
	money.Parent = folder

	local rate = Instance.new("StringValue")
	-- The column HEADER carries the unit, so the value is a bare money figure --
	-- "$5.4K" under a "$/s" header reads as "$5.4K per second". Appending "/s"
	-- to the value as well (PlayerProfile's own formatIncomePerSecond does, for
	-- the on-slime nametag, which has no header to carry it) would render
	-- "$5.4K/s" under "$/s".
	rate.Name = "$/s"
	rate.Value = MoneyFormat.format(0)
	rate.Parent = folder

	-- Parented LAST, once all three children exist, so the engine can never see
	-- a half-populated leaderstats folder -- the same ordering guarantee
	-- SoundBroadcast's remotes folder and buildBaseFolder's own attributes are
	-- built with.
	folder.Parent = player
	return { folder = folder, swing = swing, money = money, rate = rate }
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

-- How wide (studs) a placed slot slime is built -- see SlimeBuilder.build's
-- own ScaleTo comment for how this turns into an absolute Model scale.
-- Height follows automatically from the mesh's own fixed ~0.677 height/
-- width ratio, not a second number here. 7 (raised from 6, see the written
-- report -- 6 read as small against the 8x8 pad): height comes out to
-- ~4.74 studs (7 * 0.677), leaving ~0.5 studs of pad clearance on every
-- side (8-stud pad minus a ~7-stud footprint, split both sides).
local SLOT_SLIME_WIDTH_STUDS = 7

-- Nametag label heights (pixels) -- named so the BillboardGui's own Size can
-- be COMPUTED from them (see spawnSlimeVisual's own comment) instead of
-- carrying a second, independently-drifting fixed height.
local NAME_LABEL_HEIGHT_PIXELS = 34
local INCOME_LABEL_HEIGHT_PIXELS = 24

-- How far from the CAMERA (not the character -- BillboardGui.MaxDistance is
-- measured camera-side) a slot's tag still draws. The ten pads span Z 117 to
-- 173 (five rows 14 studs apart, see BaseConfig) across two columns 30 studs
-- apart, so the whole grid's own diagonal is ~64 studs. Standing at one slot,
-- the neighbouring slots sit ~14 away (next row, same column) and the
-- diagonal one ~33 (was ~26, before the columns moved out from +-11 to +-15
-- to open the collect-pad channel); the far end of the plot is 56+. 40 covers
-- the near cluster once the default third-person camera's own ~12-stud
-- pullback is added on top (~14 + ~12), while staying comfortably under the
-- 56-stud row span -- so a player at the front of their base draws the front
-- slots' tags and not all ten at once.
--
-- The widening did narrow what this admits: a diagonal neighbour is now ~33 +
-- ~12 = ~45 away and falls outside it, where it used to land just inside at
-- ~38. That is a small tightening in the direction this clamp exists for
-- (fewer tags at once, never more), so the value is left alone.
local NAMETAG_MAX_DISTANCE_STUDS = 40

local function spawnSlimeVisual(profile: Profile, slotNumber: number, slime: SlimeData.Slime, level: number)
	local pad = getSlotPad(profile.baseIndex, slotNumber)
	local padTopY = pad.Position.Y + pad.Size.Y / 2

	-- Per-slime colour, not the tier's (see the written report -- `color` is
	-- the per-slime field; `slime.tierColor` is the shared one). This is the
	-- imported mesh (see SlimeBuilder.luau) -- the one place this colour is
	-- actually visible in-game.
	-- skinTextureId is nil for every slime without a painted sheet, which is
	-- all but one of the 65 today -- see SlimeConfig.SLIME_SKIN_BY_TIER.
	local model = SlimeBuilder.build(slime.color, SLOT_SLIME_WIDTH_STUDS, slime.skinTextureId)
	model.Name = slime.name

	-- FACE INWARD ACROSS THE CENTRAL PATH, NOT OUT OF THE BASE (see the
	-- written report -- this replaces the previous "-Z, out of the base"
	-- facing, which used the mesh's real face axis correctly but aimed it at
	-- the wrong target). The mesh's own FACE axis, verified from geometry
	-- (see SlimeBuilder's own MESH_FACE_AXIS comment): -Z, in the template's
	-- own unrotated local space -- CFrame.lookAt always aims a CFrame's local
	-- -Z at its target, so that's exactly what these calls need to do to
	-- actually point the mesh's face at `target`, not some axis 90 degrees
	-- away from it.
	--
	-- COLUMN DERIVED FROM MEASURED X, NOT SLOT NUMBER (see the written
	-- report): the two-column grid happens to put odd slots in the left
	-- column and even slots in the right (see BaseGeometry.slotPosition),
	-- but reading the SLOT NUMBER's parity would be assuming that layout
	-- rather than measuring it. Comparing this pad's own X against the
	-- base's own centre X (LaneConfig.baseLaneCenterX, the same baseX every
	-- other per-lane position in this file is built from) works regardless
	-- of how the grid itself is laid out. A pad LEFT of centre (lower X)
	-- should look toward +X (in, across the path); a pad RIGHT of centre
	-- (higher X) should look toward -X.
	local baseCenterX = LaneConfig.baseLaneCenterX(profile.baseIndex)
	local padCenterX, padCenterZ = pad.Position.X, pad.Position.Z
	local towardCenterX = if padCenterX < baseCenterX then 1 else -1
	local facing = CFrame.lookAt(
		Vector3.new(padCenterX, 0, padCenterZ),
		Vector3.new(padCenterX, 0, padCenterZ) + Vector3.new(towardCenterX, 0, 0)
	)
	model:PivotTo(facing)

	-- Bottom-align against the pad's own TOP surface -- MEASURED, not a
	-- hardcoded rest height (see SlimeBuilder.worldAABB's own comment: an
	-- explicit world-axis AABB over every descendant's transformed corners,
	-- never Model:GetBoundingBox). minCorner.Y is still the Y = 0 placeholder
	-- pose's own bottom at this point -- shifting the whole model up by
	-- (padTopY - minCorner.Y) lands that bottom exactly on the pad's top
	-- face, whatever the mesh's own internal origin/pivot happens to be.
	local minCorner, maxCorner = SlimeBuilder.worldAABB(model)
	local deltaY = padTopY - minCorner.Y
	model:PivotTo(model:GetPivot() + Vector3.new(0, deltaY, 0))

	-- WHICH SLOT THIS MODEL IS, for the client. Set BEFORE Parent (the same
	-- "populate then reveal" ordering the Remotes folder and the base folder's
	-- own attributes already use) so it is guaranteed present by the time any
	-- client's ChildAdded fires -- a client that saw the Model first and the
	-- attribute a frame later would have to poll for it.
	--
	-- The model's NAME cannot serve this purpose: it is the slime's display
	-- name ("Secret Slime 20"), which is neither unique across slots nor
	-- anything the client could map back to a slot number. Nothing
	-- server-side reads this attribute -- it carries no authority, it is a
	-- label. SlimeUpgradeTagClient.client.luau is its only consumer, and the
	-- upgrade it ultimately requests is still validated entirely by
	-- upgradeSlime below, from server-held state.
	model:SetAttribute("SlotNumber", slotNumber)

	model.Parent = profile.baseFolder
	profile.visualParts[slotNumber] = model

	-- ===== THE COLLECT PAD -- a green pad on the ground in front of this
	-- slime, toward the central path it faces. Geometry only this pass: no
	-- collection logic, no accumulated-money system, nothing reads it yet.
	-- Position and size are DERIVED from the slot pad's own geometry in
	-- BaseGeometry.collectPadPlacement (see BaseConfig's collect-pad block);
	-- nothing about them is written here.
	--
	-- PARENTED INTO THE SLIME MODEL, not alongside it in the base folder, and
	-- that is the whole teardown story: a pad that is a DESCENDANT of the
	-- model cannot outlive it, so every path that already destroys a slot
	-- visual destroys its pad too without any of them having to know the pad
	-- exists. Both of them do -- removeToInventory's `model:Destroy()` and
	-- onPlayerRemoving's `profile.baseFolder:Destroy()` -- and so would any
	-- third one added later, which is the point of doing it structurally
	-- rather than with a second registry to keep in step.
	--
	-- Safe to carry inside the Model: the two client scripts that walk these
	-- models both select parts BY NAME (SlimeIdleClient's slime/eye_dark/
	-- eye_white/blush, SlimeUpgradeTagClient's `slime`), and SlimeBuilder's
	-- own every-part pass has already finished by the time this is added.
	--
	-- ANCHORED, and CanCollide FALSE. Anchored because it is scenery -- there
	-- is no physics here to want. Non-colliding because a player has to be
	-- able to STAND on it, and at 0.4 studs proud of the mat, standing on a
	-- non-colliding pad puts them on the mat at essentially the same height,
	-- reading as on it -- while a colliding one adds a lip to catch on right
	-- beside the walk-in path. CanTouch is left at its default true so the
	-- eventual collection trigger needs no change here.
	local collectPosition, collectSize = BaseGeometry.collectPadPlacement(profile.baseIndex, slotNumber)
	local collectPad = Instance.new("Part")
	collectPad.Name = "CollectPad"
	collectPad.Anchored = true
	collectPad.CanCollide = false
	collectPad.Size = collectSize
	collectPad.Position = collectPosition
	collectPad.Material = BaseConfig.BASE_COLLECT_PAD_MATERIAL
	collectPad.Color = BaseConfig.BASE_COLLECT_PAD_COLOR
	-- Studded top, from the one shared ground-finish constant every other
	-- walkable surface reads (MapBuilder applies the same value to the mats,
	-- paths, belt and slot pads). This is the ONLY surface in the map that
	-- was explicitly Smooth before -- everywhere else was left at the part
	-- default -- so this line is the one guaranteed visible change of the
	-- pass.
	--
	-- CAVEAT, and it is a real one: BASE_COLLECT_PAD_MATERIAL is Neon, which
	-- is self-illuminated and shades almost flat. Stud relief is read from
	-- shading, so the studs may barely register here even though the property
	-- is set. See REPORT.md -- if they do not show, the pad's material is the
	-- reason, not this line.
	collectPad.TopSurface = GroundConfig.GROUND_TOP_SURFACE
	-- Bottom stays Smooth: it sits face-down on the mat and is never seen.
	collectPad.BottomSurface = Enum.SurfaceType.Smooth
	collectPad.Parent = model

	-- Two stacked lines -- name+level on top (tier-coloured, from
	-- slime.tierColor), income per second below it (green, matching the money
	-- readout's own colour so "this is money" reads instantly) -- a
	-- UIListLayout stacks them so neither has to hardcode the other's height.
	-- Tall/wide enough, and billboards always face the camera, to read
	-- clearly from a player standing at their own base looking at their slots.
	--
	-- The name line was briefly cut in a previous pass on the theory that it
	-- was feeding the grey haze; it was not (see buildBaseFolder -- the haze
	-- was the BASE SIGN all along), so it is back as it was. The genuinely
	-- useful parts of that same pass are kept: no stroke, no border, a finite
	-- MaxDistance, and AlwaysOnTop off so tags sit behind what occludes them.
	--
	-- Re-parented to the model's PrimaryPart (the body MeshPart), not the
	-- Model itself (see the written report): BillboardGui only auto-adorns
	-- to a BasePart parent, not a Model, so this is the "equivalent" the
	-- task allowed for -- same effective anchor point the old placeholder
	-- cube gave it, since that cube WAS the whole visual before.
	local primaryPart = model.PrimaryPart :: MeshPart
	-- Height above the body's own CENTER (what StudsOffset is relative to)
	-- that the WHOLE model's top actually reaches, post-placement -- the
	-- face parts (eye_dark/eye_white/blush) sit within the body's own
	-- silhouette, but this reads off the model's real measured top rather
	-- than assuming that. maxCorner.Y is still the pre-shift measurement, so
	-- it's offset by the same deltaY the model itself was just moved by.
	local heightAboveCenter = (maxCorner.Y + deltaY) - primaryPart.Position.Y

	-- Sized to its actual content (both label heights, not a fixed 60), and
	-- on BOTH labels below: BackgroundTransparency = 1 (fill), BorderSizePixel
	-- = 0 (edge -- a separate render pass, so a GuiObject's default 1px border
	-- survives a transparent background) and TextStrokeTransparency = 1
	-- (stroke -- a THIRD pass, painted around the TEXT rather than the
	-- container, so neither of the other two suppresses it). All three off
	-- means only the glyphs paint.
	local nameTag = Instance.new("BillboardGui")
	nameTag.Name = "NameTag"
	nameTag.Size = UDim2.new(0, 180, 0, NAME_LABEL_HEIGHT_PIXELS + INCOME_LABEL_HEIGHT_PIXELS)
	nameTag.StudsOffset = Vector3.new(0, heightAboveCenter + 1, 0)
	nameTag.AlwaysOnTop = false
	nameTag.MaxDistance = NAMETAG_MAX_DISTANCE_STUDS
	nameTag.Parent = primaryPart

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = nameTag

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.LayoutOrder = 1
	nameLabel.BackgroundTransparency = 1
	nameLabel.BorderSizePixel = 0
	nameLabel.Size = UDim2.new(1, 0, 0, NAME_LABEL_HEIGHT_PIXELS)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = slime.tierColor
	nameLabel.TextStrokeTransparency = 1
	nameLabel.Text = string.format("%s (Lv %d)", slime.name, level)
	nameLabel.Parent = nameTag

	local incomeLabel = Instance.new("TextLabel")
	incomeLabel.Name = "Income"
	incomeLabel.LayoutOrder = 2
	incomeLabel.BackgroundTransparency = 1
	incomeLabel.BorderSizePixel = 0
	incomeLabel.Size = UDim2.new(1, 0, 0, INCOME_LABEL_HEIGHT_PIXELS)
	incomeLabel.Font = Enum.Font.GothamBold
	incomeLabel.TextScaled = true
	incomeLabel.TextColor3 = Color3.new(0.4, 1, 0.5)
	incomeLabel.TextStrokeTransparency = 1
	incomeLabel.Text = formatIncomePerSecond(SlimeUpgrade.incomeForLevel(slime.incomePerSecond, level))
	incomeLabel.Parent = nameTag
end

-- Updates an ALREADY-PLACED slime's world billboard (name+level, income) in
-- place after a level change -- called from upgradeSlime and devSetSlimeLevel,
-- so the 3D label over a slot never shows a stale level/income after an
-- upgrade without waiting for the player to re-open the inventory panel.
-- No-op if the slot's visual somehow doesn't exist (defensive only -- every
-- occupied slot always has one, see spawnSlimeVisual's only two callers).
local function refreshSlimeVisualLabel(profile: Profile, slotNumber: number)
	local model = profile.visualParts[slotNumber]
	local globalIndex = profile.slots[slotNumber]
	if not model or not globalIndex then
		return
	end
	local slime = SlimeData.SLIMES[globalIndex]
	if not slime then
		return
	end
	local level = profile.levels[slotNumber] or 1
	-- NameTag now hangs off the model's PrimaryPart, not the model itself
	-- (see spawnSlimeVisual's own comment -- BillboardGui only auto-adorns
	-- to a BasePart parent).
	local primaryPart = model.PrimaryPart
	local nameTag = primaryPart and primaryPart:FindFirstChild("NameTag")
	if not nameTag then
		return
	end
	local nameLabel = nameTag:FindFirstChild("Name") :: TextLabel?
	local incomeLabel = nameTag:FindFirstChild("Income") :: TextLabel?
	if nameLabel then
		nameLabel.Text = string.format("%s (Lv %d)", slime.name, level)
	end
	if incomeLabel then
		incomeLabel.Text = formatIncomePerSecond(SlimeUpgrade.incomeForLevel(slime.incomePerSecond, level))
	end
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
			table.insert(slotEntries, { slot = i, globalIndex = globalIndex, level = profile.levels[i] or 1 })
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

	-- Replicated the same way Money/SwingTier already are -- a plain attribute
	-- on this player's own base folder. Nothing on the client reads it yet;
	-- it is here so a future HUD or the sign's own client-side rendering does
	-- not need a new remote.
	profile.baseFolder:SetAttribute("ChestsOpened", profile.chestsOpened)
end

-- ===== THIS PLAYER'S TOTAL INCOME PER SECOND, from placed slimes only.
-- MOVED UP from beside the income tick (its only caller until this pass) so
-- that creditOfflineIncome below and onPlayerAdded's load path can both see it:
-- a `local function` is only in scope BELOW its own definition, and a reference
-- from above would silently resolve to a nil global rather than to this. The
-- tick itself is unchanged and still lives further down.
--
-- THE SINGLE SOURCE OF THE RATE, and deliberately so. Online income (the tick)
-- and offline income (creditOfflineIncome) both call THIS -- neither re-derives
-- it -- which is what makes offline and online rates impossible to diverge (the
-- one knob between them is OFFLINE_RATE_MULTIPLIER, and it is applied in
-- OfflineIncome, not here). Already accounts for that slot's own level via
-- SlimeUpgrade.incomeForLevel; inventory contributes nothing, only placed
-- slimes earn.
--
-- NOW PER SLOT, and totalIncomePerSecond below is a sum OF THIS rather than a
-- second loop (see REPORT.md STEP 1): every pot is credited its OWN slime's
-- rate, not a share of the total, so a Divine in slot 3 fills slot 3's pot and
-- nobody else's.
local function slotIncomePerSecond(profile: Profile, slotNumber: number): number
	local globalIndex = profile.slots[slotNumber]
	if not globalIndex then
		return 0
	end
	local slime = SlimeData.SLIMES[globalIndex]
	if not slime then
		return 0
	end
	return SlimeUpgrade.incomeForLevel(slime.incomePerSecond, profile.levels[slotNumber] or 1)
end

-- ===== THIS PLAYER'S TOTAL INCOME PER SECOND, from placed slimes only -- the
-- sum of every slot's own rate above. Kept as its own function because it is
-- what a HUD/report/analysis wants to ask for, but it is no longer what either
-- accrual path uses: both now walk the slots and credit each one separately.
local function totalIncomePerSecond(profile: Profile): number
	local total = 0
	for i = 1, BaseConfig.SLOT_COUNT do
		total += slotIncomePerSecond(profile, i)
	end
	return total
end

-- ===== THE LEADERBOARD'S ONE WRITER (see REPORT.md STEP 1e). Every path that
-- can change a tier, a balance or an income rate calls THIS -- there is no
-- second update path, and the three columns are always written together from
-- one read of the profile, so they cannot drift out of step with each other
-- even for a frame.
--
-- TAKES THE PROFILE ALONE, not (player, profile). Everything it needs is on the
-- profile, including the Value instances themselves -- and two of its callers,
-- bankSlot and applyLoadedData, have no Player in scope at all. Requiring one
-- would have meant either threading a player argument through the collect path
-- or a reverse lookup from the profiles table, for no gain.
--
-- $/s IS totalIncomePerSecond, THE SAME FUNCTION the income tick and the
-- offline accrual read (through slotIncomePerSecond), never a re-derivation.
-- That is the whole point: a leaderboard showing a rate that disagrees with the
-- rate actually being paid would be lying about the one thing it exists to
-- display, and the only way to guarantee it cannot is to have one expression.
--
-- WRITES ONLY ON A REAL CHANGE. Assigning a Value its current value is not free
-- -- it fires Changed and replicates -- and this is called from several sites
-- that often fire together (an upgrade changes money AND the rate; a removal
-- banks a pot and then clears a slot). The three comparisons make a redundant
-- call provably free, which is what lets callers be added liberally rather than
-- carefully.
local function refreshLeaderstats(profile: Profile)
	local stats = profile.leaderstats
	if stats.swing.Value ~= profile.swingTier then
		stats.swing.Value = profile.swingTier
	end
	local moneyText = MoneyFormat.format(profile.money)
	if stats.money.Value ~= moneyText then
		stats.money.Value = moneyText
	end
	local rateText = MoneyFormat.format(totalIncomePerSecond(profile))
	if stats.rate.Value ~= rateText then
		stats.rate.Value = rateText
	end
end

-- The sum of every slot's pot -- what the HUD shows, and the number that tells
-- a player at the swing whether the walk is worth making.
local function pendingTotal(profile: Profile): number
	local total = 0
	for _, amount in profile.pendingBySlot do
		total += amount
	end
	return total
end

-- ===== The pots' one PUBLISHER. Every path that changes a pot (the income
-- tick, offline accrual on load, a collect, a removal) mutates
-- profile.pendingBySlot / profile.offlineCredit and then calls this, so the
-- replicated attributes can never drift from the table they mirror -- the same
-- "one place sets it" rule Money already follows.
--
-- THREE ATTRIBUTES, TWO AUDIENCES. PendingIncome is the total, for the HUD
-- readout. PendingBySlot is a JSON array of {slot, pending} for the occupied,
-- non-empty slots only -- the exact shape and encoding syncClientState already
-- uses for Slots/Inventory, deliberately, because that is how per-slot data
-- already reaches the client in this project and a new remote for the same job
-- would be a second convention. Rejected alternative: an attribute on each
-- CollectPad part. It would have been marginally cheaper (no encode, no parse)
-- and the pad already knows its own slot -- but it would mean writing ten
-- attributes per player per tick instead of one, and it would put the value on
-- an instance that only exists while a slime does, so nothing could ever render
-- a pot the pad had not been built for yet.
--
-- OfflineCredit rides along because the UI treats it as part of the same state:
-- the "while you were away" line shows only while it is > 0, and the first
-- collect at any pad zeroes it (see collectPending).
local function publishPending(profile: Profile)
	local entries = {}
	for i = 1, BaseConfig.SLOT_COUNT do
		local amount = profile.pendingBySlot[i]
		if amount and amount > 0 then
			table.insert(entries, { slot = i, pending = amount })
		end
	end
	profile.baseFolder:SetAttribute("PendingIncome", pendingTotal(profile))
	profile.baseFolder:SetAttribute("PendingBySlot", HttpService:JSONEncode(entries))
	profile.baseFolder:SetAttribute("OfflineCredit", profile.offlineCredit)
end

-- ===== THE ONLY DOOR FROM A POT INTO CASH. Every caller -- a collect pad, a
-- slot being emptied, a load-time reconciliation -- goes through this one
-- function, which is what keeps "the pot is not spendable" checkable by reading
-- a single site rather than auditing every `profile.money +=` in the file (see
-- dev/analysis/verify_offline.luau, which counts them).
--
-- ATOMIC, and that is load-bearing rather than tidy: it reads the pot, zeroes
-- it, and adds to cash with NO YIELD in between, so a second caller arriving on
-- the same frame -- the per-limb burst a single step across a pad produces --
-- finds an empty pot and pays nothing. Double-payment is impossible by
-- construction, not by timing. The debounce in collectPending is an independent
-- second guard with a different job (see its own comment).
--
-- Returns the amount banked, 0 if the pot was empty. Banking zero is a silent
-- no-op by design: most pads are empty most of the time.
local function bankSlot(profile: Profile, slotNumber: number): number
	local amount = profile.pendingBySlot[slotNumber]
	if not amount or amount <= 0 then
		return 0
	end
	profile.pendingBySlot[slotNumber] = nil
	profile.money += amount
	profile.baseFolder:SetAttribute("Money", profile.money)
	-- The first collect is exactly when the "while you were away" line has
	-- served its purpose, whichever pad it happened at.
	profile.offlineCredit = 0
	publishPending(profile)
	-- LAST, after the pot has already moved and been published. Deliberately
	-- below the atomic stretch rather than inside it: this is a pure read of
	-- state that is already final, it cannot yield, and putting it here means the
	-- payout's own no-yield guarantee is untouched by it.
	refreshLeaderstats(profile)
	return amount
end

-- ===== Save-shape adapters: the ONLY place that translates between the
-- in-memory Profile (a hash-set for `seen`, a sparse map for `slots`) and
-- the plain, DataStore-safe table PlayerStore reads/writes (a dense array
-- with a 0 sentinel for an empty slot, since DataStore arrays can't hold
-- holes reliably) -- see PlayerStore.luau. =====
-- Shows or hides the crown on this player's own entrance sign. Rendered off
-- `chestsOpened >= 1` -- a count stored, a boolean drawn (see the Profile
-- type). Silently does nothing if the sign is missing, which is the load-order
-- case below, not an error.
local function refreshSignCrown(profile: Profile)
	local sign = profile.baseFolder:FindFirstChild("EntranceSign")
	if sign and sign:IsA("Model") then
		SignBuilder.setCrown(sign, profile.chestsOpened >= 1)
	end
end

local function toSaveShape(profile: Profile): { [string]: any }
	local slotsOut = table.create(BaseConfig.SLOT_COUNT, 0)
	local levelsOut = table.create(BaseConfig.SLOT_COUNT, 1)
	for i = 1, BaseConfig.SLOT_COUNT do
		slotsOut[i] = profile.slots[i] or 0
		levelsOut[i] = profile.levels[i] or 1
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
	-- A DENSE array with a 0 sentinel for "nothing pending", the same shape
	-- `slots` and `levels` above use and for the same reason (DataStore arrays
	-- cannot hold holes reliably). Persisted, so a player who logs off holding
	-- money on eight slimes still has all eight on their next join: it is real
	-- earned income that simply has not been walked over yet, and dropping it on
	-- disconnect would punish exactly the player this whole system exists to
	-- bring back. `offlineCredit` is deliberately NOT here; see its own comment
	-- on the Profile type.
	local pendingOut = table.create(BaseConfig.SLOT_COUNT, 0)
	for i = 1, BaseConfig.SLOT_COUNT do
		pendingOut[i] = profile.pendingBySlot[i] or 0
	end
	return {
		money = profile.money,
		pendingBySlot = pendingOut,
		slots = slotsOut,
		levels = levelsOut,
		seen = seenOut,
		swingTier = profile.swingTier,
		inventory = inventoryOut,
		chestsOpened = profile.chestsOpened,
		chestPending = profile.chestPending,
		-- ===== WHEN THIS PLAYER WAS LAST SEEN, for offline accrual on the next
		-- load. Written UNCONDITIONALLY, on every save -- the periodic autosave,
		-- the leave-save and the shutdown save alike -- because every one of
		-- them is a moment this player was demonstrably still here.
		--
		-- os.time(), server-side, never anything the client supplied: this
		-- number decides how much money the player is handed on their next
		-- join, so a client-writable version would be a free-money button.
		--
		-- DELIBERATELY NOT PlayerStore's `sessionHeartbeat`, which is also an
		-- os.time() written by the server and looks like exactly this field.
		-- It is a session LOCK, and PlayerStore.save nils it out whenever
		-- `releasingSession` is true -- i.e. on the single most common exit
		-- path, a clean leave. Reusing it would credit zero to every player who
		-- logged off normally and pay only the ones who crashed, which is
		-- precisely backwards. PlayerStore's session logic is untouched by this
		-- pass; this is a separate field with a separate job that happens to
		-- share a clock.
		lastSeen = os.time(),
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
	local levels = data.levels
	if typeof(slots) == "table" then
		for i = 1, BaseConfig.SLOT_COUNT do
			local globalIndex = slots[i]
			if typeof(globalIndex) == "number" and globalIndex > 0 and SlimeData.SLIMES[globalIndex] then
				profile.slots[i] = globalIndex
				-- Only meaningful for a slot that's actually occupied -- an
				-- empty slot never gets a `levels` entry, matching the
				-- in-memory invariant everywhere else in this file (missing
				-- = empty). Defaults to 1 (fresh) if the saved level is
				-- missing/malformed -- covers both a pre-leveling save (no
				-- `levels` field at all) and a hand-edited bad value.
				local savedLevel = typeof(levels) == "table" and levels[i]
				profile.levels[i] = SlimeUpgrade.clampLevel(if typeof(savedLevel) == "number" then savedLevel else 1)
			end
		end
	end
	-- Clamped to [1, tierCount], and floored, so a hand-edited or
	-- otherwise-malformed save value can never leave a player with a
	-- fractional or out-of-range tier -- see buyNextTier for the same
	-- tierCount source (#LaunchConfig.SWING_TIER_DISTANCE_SCALE).
	--
	-- THIS IS ALSO THE LADDER-SHRINK MIGRATION, and it needs no code of its
	-- own. The ladder went from eleven tiers to ten (see LaunchConfig.
	-- SWING_TIER_DISTANCE_SCALE); every profile saved with swingTier = 11 loads
	-- as 10, which is the same swing it always was -- old tier 11 IS the new
	-- top tier, unchanged. The value is re-clamped on every load and toSaveShape
	-- only ever writes what is already clamped, so an out-of-range tier cannot
	-- persist. Deliberately a clamp and nothing more: no migration table and no
	-- save version. The one accepted consequence is that a profile saved at old
	-- tier 10 keeps the number 10 and is therefore promoted to the new top tier
	-- for free -- nothing in the save distinguishes it from an old tier 11, and
	-- adding a version field to recover a demotion nobody asked for would cost
	-- more than the promotion does. See REPORT.md.
	if typeof(data.swingTier) == "number" then
		local tierCount = #LaunchConfig.SWING_TIER_DISTANCE_SCALE
		profile.swingTier = math.clamp(math.floor(data.swingTier), 1, tierCount)
	end
	-- Absent on every save written before this feature existed, which reads as
	-- 0/false -- no migration needed, same as `levels` was for a pre-leveling
	-- save. Floored and clamped for the same reason swingTier is: a
	-- hand-edited value must not be able to produce a fractional or negative
	-- crown count.
	if typeof(data.chestsOpened) == "number" then
		profile.chestsOpened = math.max(0, math.floor(data.chestsOpened))
	end
	if typeof(data.chestPending) == "boolean" then
		profile.chestPending = data.chestPending
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

	-- ===== THE POTS, LOADED LAST, AFTER SLOTS AND LEVELS -- deliberately, and
	-- for two separate reasons: the legacy migration below needs this profile's
	-- per-slot RATES (which are a function of slots+levels), and the orphan
	-- reconciliation needs to know which slots actually ended up occupied.
	--
	-- Every value is clamped to > 0 before it is accepted, the same way
	-- `chestsOpened` and `swingTier` are: a hand-edited or corrupted save must
	-- not be able to produce a negative pot, which would silently eat the next
	-- collect. NaN fails `> 0` too, so it lands on nothing rather than poisoning
	-- every later addition.
	local pendingBySlot = data.pendingBySlot
	if typeof(pendingBySlot) == "table" then
		for i = 1, BaseConfig.SLOT_COUNT do
			local amount = pendingBySlot[i]
			if typeof(amount) == "number" and amount > 0 then
				profile.pendingBySlot[i] = amount
			end
		end
	elseif typeof(data.pendingIncome) == "number" and data.pendingIncome > 0 then
		-- ===== MIGRATION FROM THE SINGLE POT (see REPORT.md STEP 1d). Saves
		-- written by the previous pass carry one `pendingIncome` number with no
		-- slot attached to it. It is spread across the slots IN PROPORTION TO
		-- EACH SLOT'S OWN RATE -- the same rule offline accrual uses -- so the
		-- player finds it where they would have earned it. It is NOT dropped and
		-- NOT handed straight to cash: it is money they earned and have not
		-- collected, and the whole point of this pass is that collecting is the
		-- walk.
		--
		-- The one case proportional distribution cannot answer is a base with no
		-- placed slimes at all (rate 0, nothing to be proportional TO). Such a
		-- pot is parked on slot 1 and picked up by the orphan pass immediately
		-- below, which banks it -- there is no pad in an empty base to ever
		-- collect it at, so the alternative is stranding it forever. Routing it
		-- that way rather than adding to `money` here is what keeps bankSlot the
		-- only place in this file that moves a pot into cash.
		local rate = totalIncomePerSecond(profile)
		if rate > 0 then
			for i = 1, BaseConfig.SLOT_COUNT do
				local slotRate = slotIncomePerSecond(profile, i)
				if slotRate > 0 then
					profile.pendingBySlot[i] = data.pendingIncome * (slotRate / rate)
				end
			end
		else
			profile.pendingBySlot[1] = data.pendingIncome
		end
	end

	-- ORPHANED POTS: a pot on a slot that did not end up occupied. It cannot
	-- happen from a save this code wrote (every path that empties a slot banks
	-- its pot first -- see removeToInventory), but it CAN arrive from a
	-- hand-edited save, or from one whose slot held a globalIndex that no longer
	-- exists in SlimeData and was therefore skipped above. There is no pad for
	-- such a pot to ever be collected at, so it is banked rather than stranded
	-- or silently deleted -- through bankSlot, the same single door every other
	-- pot uses, so this adds no second route into cash.
	for i = 1, BaseConfig.SLOT_COUNT do
		if profile.pendingBySlot[i] and not profile.slots[i] then
			bankSlot(profile, i)
		end
	end
end

-- ===== OFFLINE ACCRUAL: pay this player for the time they were away, into the
-- same per-slot pots online income accrues to. Ten slimes means ten pots waiting
-- on return, each holding what that slime earned while the player was gone.
--
-- MUST BE CALLED AFTER applyLoadedData, NEVER BEFORE, and this is the whole
-- trap: the rates come from slotIncomePerSecond, which reads profile.slots and
-- profile.levels. Before applyLoadedData those are empty tables, so every rate
-- is zero and the player is silently credited nothing -- no error, no warning,
-- just an offline reward that never appears. See onPlayerAdded for the enforced
-- ordering, and dev/analysis/verify_offline.luau, which asserts it by reading
-- this file's own source.
--
-- Takes the raw loaded `data` rather than a field on the profile because
-- `lastSeen` is not part of the in-memory Profile at all: it is written fresh
-- from os.time() at every save (see toSaveShape) and read exactly once, here.
-- Keeping it out of the Profile means there is no stale copy to accidentally
-- trust later in the session.
--
-- Returns the amount credited, for the caller to log or ignore.
local function creditOfflineIncome(profile: Profile, data: { [string]: any }?): number
	-- The arithmetic -- the missing-timestamp case, the clock-skew clamp and the
	-- cap -- lives in OfflineIncome.creditFor, beside the two constants it
	-- reads, so it can be tested on the command line against the real module
	-- (see dev/analysis/verify_offline.luau). `data` may be nil (a brand-new
	-- player) and `data.lastSeen` may be absent or malformed; creditFor takes
	-- the raw value and is responsible for every one of those cases.
	--
	-- os.time() here and nowhere else: this is the one place a clock is read for
	-- accrual, and it is read server-side. Read ONCE, before the loop, so every
	-- slot is credited for exactly the same absence -- calling it per slot would
	-- let the clock tick over mid-loop and pay later slots a second more.
	--
	-- ===== PER SLOT, NOT ONE LUMP SPLIT AFTERWARDS (see REPORT.md STEP 2d).
	-- Each slot is credited creditFor(lastSeen, now, ITS OWN rate) -- the same
	-- slotIncomePerSecond the online tick uses, through the same arithmetic --
	-- so the ten credits sum to exactly what one call at the total rate would
	-- have returned (elapsed is identical for every slot, and elapsed * M *
	-- SUM(rate_i) is the sum of elapsed * M * rate_i). That makes the
	-- distribution proportional by construction rather than by a division that
	-- has to be kept in step with the rate, and it needs no special case for a
	-- total rate of zero.
	local now = os.time()
	local credited = 0
	for i = 1, BaseConfig.SLOT_COUNT do
		local slotCredit = OfflineIncome.creditFor(data and data.lastSeen, now, slotIncomePerSecond(profile, i))
		if slotCredit > 0 then
			-- Added to whatever pot was already saved, never replacing it: a
			-- player who logged off holding uncollected pots gets those pots PLUS
			-- their offline earnings.
			profile.pendingBySlot[i] = (profile.pendingBySlot[i] or 0) + slotCredit
			credited += slotCredit
		end
	end
	if credited <= 0 then
		return 0
	end

	-- `offlineCredit` records only THIS session's share, TOTALLED, for the
	-- one-time "while you were away" line -- see its own comment on the Profile
	-- type for why one figure rather than ten.
	profile.offlineCredit = credited
	publishPending(profile)
	return credited
end

-- ================= COLLECTING: pot -> banked cash =================
--
-- ONE HANDLER FOR THE TEN PER-SLOT PADS, AND EACH ONE BANKS ITS OWN SLOT ONLY
-- (see REPORT.md STEP 3). Which slot a pad belongs to is read from the slime
-- Model it is parented inside -- spawnSlimeVisual already stamps that Model with
-- a SlotNumber attribute for the upgrade tags, so the pad needs no second
-- registry and its construction needed no change to opt in. Walking the row
-- banks each slot in turn; walking past one pad banks one slime.
--
-- TOUCHED, not a ProximityPrompt, and that is the point of the whole feature.
-- A prompt is the established interaction pattern in this codebase (the
-- treasure chest uses one) and it is the WRONG one here: a prompt costs a
-- keypress and a hold, and collection has to cost nothing at all on a walk the
-- player is already making. This is the first `.Touched` in src/.

-- How far the player's ROOT may be from the pad's centre and still collect,
-- measured horizontally, as a margin ON TOP of the pad's own half-diagonal (so
-- it adapts to whichever pad was touched rather than assuming the 8x8 one).
--
-- 6 studs of margin: a character's root sits a couple of studs above the pad
-- and up to ~2 studs horizontally from whichever limb actually made contact,
-- and a walking player replicates a little behind where they are. Generous
-- deliberately -- see collectPending on what this check is and is not for.
-- Rejected: a tight ~2-stud tolerance, which would have rejected legitimate
-- collects from a player crossing the pad at walking speed for no gain, since
-- this check is a desync guard rather than an anti-exploit measure.
local COLLECT_DISTANCE_MARGIN_STUDS = 6

-- Banks ONE SLOT's pot, atomically (through bankSlot, the single door into
-- cash). Returns the amount banked, or 0 if nothing happened -- and "nothing
-- happened" is silent by design: with ten pots and one walk past all of them,
-- most pads are empty most of the time, and an empty one is the normal case,
-- not an error worth a sound or a message.
--
-- SERVER-AUTHORITATIVE IN THE ONLY WAY THAT MATTERS: both the slot and the
-- amount are read on the server -- the slot from the Model the touched pad is
-- parented inside, the amount from profile.pendingBySlot. There is no remote, so
-- the client has no way to name a figure, name a slot, or collect anything but
-- its own pots.
--
-- ON THE DISTANCE CHECK, honestly: the position it validates is the character's
-- own, which is client-owned (Roblox gives the player network ownership of their
-- character), and it is the same position that produced the Touched event. So
-- this does NOT stop a modified client teleporting onto a pad -- nothing
-- server-side short of rejecting client physics could. It is a guard against a
-- stale or desynced Touched firing when the player is demonstrably nowhere near,
-- which is a real thing that happens. The reason that is ENOUGH: collecting has
-- no exploit value. It moves the player's OWN already-earned money from one of
-- their own buckets to another, at a rate they already earned it; there is
-- nothing to gain by collecting from the wrong place, only by earning more,
-- which this path cannot do.
local function collectPending(player: Player, profile: Profile, slotNumber: number, pad: BasePart, hit: BasePart): number
	-- ONLY THE OWNER. Without this, any player walking across someone else's
	-- collect pad would bank that player's pot for them -- not theft (the money
	-- still goes to its owner) but a stranger reaching into their state, and it
	-- would fire the owner's "while you were away" line while they were
	-- somewhere else entirely. Six bases stand in a row and nothing stops a
	-- player wandering into a neighbour's plot, so this is a live case, not a
	-- theoretical one.
	local character = player.Character
	if not character or not hit:IsDescendantOf(character) then
		return 0
	end

	-- DEBOUNCE, PER SLOT (see REPORT.md STEP 3b). Touched fires per-limb and
	-- repeatedly -- a single step across a pad produces a burst of events from
	-- the left leg, right leg, torso and whatever else clips it -- so a naive
	-- handler runs several times per step.
	--
	-- Two independent things make that safe, and both are wanted:
	--   1. The payout below is ATOMIC -- bankSlot reads the pot, zeroes it, and
	--      adds to cash with no yield in between -- so even without a debounce
	--      the second fire would find an empty pot and pay nothing.
	--      Double-PAYMENT is impossible by construction, not by timing.
	--   2. This window stops the burst re-firing at all, so a pot is not
	--      re-banked a few cents at a time as the tick tops it up under a player
	--      standing on the pad.
	--
	-- KEYED BY SLOT, NOT ONE WINDOW FOR THE WHOLE PLAYER, and that is the change
	-- this pass required: the ten pads are 14 studs apart down two columns, so
	-- walking the row crosses several of them well inside one
	-- BASE_INCOME_TICK_SECONDS window. A single shared timestamp would have
	-- banked the first pad and silently skipped the rest of the walk -- the
	-- exact failure the per-slot design exists to avoid. Each slot debounces
	-- only against its OWN last collect.
	--
	-- The window is BASE_INCOME_TICK_SECONDS, derived rather than picked: it is
	-- exactly long enough that at most one tick's income can accumulate between
	-- two collects at the same pad, so a lingering player banks whole ticks
	-- instead of slivers. Rejected: a boolean flag reset by task.delay, which
	-- needs a scheduler, and leaks a pending timer if the player leaves inside
	-- the window.
	local now = os.clock()
	if now - (profile.lastCollectAtBySlot[slotNumber] or -math.huge) < BaseConfig.BASE_INCOME_TICK_SECONDS then
		return 0
	end

	local amount = profile.pendingBySlot[slotNumber]
	if not amount or amount <= 0 then
		return 0
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = humanoid and humanoid.RootPart
	if not rootPart then
		return 0
	end
	-- Horizontal only: the pad is a floor tile and the root sits above it by a
	-- hip height that varies with the avatar's rig, so a 3D distance would be
	-- measuring body type as much as position.
	local padSize = pad.Size
	local maxDistance = math.sqrt(padSize.X * padSize.X + padSize.Z * padSize.Z) / 2
		+ COLLECT_DISTANCE_MARGIN_STUDS
	local offset = rootPart.Position - pad.Position
	if Vector2.new(offset.X, offset.Z).Magnitude > maxDistance then
		return 0
	end

	-- ===== THE ATOMIC PAYOUT, in bankSlot -- no yield between reading the pot
	-- and zeroing it, so there is no window in which a second handler could
	-- observe the same money twice. `amount` was captured above only to decide
	-- whether there was anything to do; bankSlot re-reads and is the authority on
	-- what actually moved.
	profile.lastCollectAtBySlot[slotNumber] = now
	local banked = bankSlot(profile, slotNumber)
	if banked <= 0 then
		return 0
	end

	-- PRIVATE, 2D, and to this player alone. A collect is a confirmation of a
	-- thing only its owner did -- broadcasting it would put five other players'
	-- collect chimes in everyone's ears continuously. Sent from here rather than
	-- inferred client-side from the PendingIncome attribute dropping, because
	-- devWipeProfile zeroes it too and an inferred sound would fire for that as
	-- well.
	--
	-- NOW UP TO TEN TIMES PER WALK rather than once per launch cycle -- see
	-- SoundConfig's UI_COLLECT entry, whose brief was rewritten for this pass.
	-- Nothing is done here to space or vary them: they are separate one-shots of
	-- a short, dull sound, and a run of them as the player walks the row is the
	-- read this wants.
	--
	-- AFTER the payout, not before: this line cannot affect whether or how much
	-- was banked, and nothing above it yields, so a failure here could not leave
	-- a pot half-moved.
	SoundBroadcast.playFor(player, "UI_COLLECT")
	return banked
end

-- Attaches the collect handler to one pad, bound to the SLOT that pad belongs
-- to. The slot is read from the slime Model the pad is parented inside --
-- spawnSlimeVisual stamps every such Model with a SlotNumber attribute BEFORE
-- parenting it (see its own comment), and parents the pad into the Model after
-- that, so the attribute is always already there by the time this runs.
--
-- Bound ONCE, at wiring time, not re-read per touch: a pad's slot cannot change
-- (the pad dies with its slime, and a new slime in that slot builds a new pad),
-- so reading it per Touched would be re-deriving a constant several times a
-- step. A pad whose parent carries no SlotNumber is ignored with a warning
-- rather than silently wired to nothing -- that would mean a pad built outside
-- spawnSlimeVisual, which is a bug in whatever built it.
local function wireCollectPad(player: Player, profile: Profile, pad: BasePart)
	local model = pad.Parent
	local slotNumber = model and model:GetAttribute("SlotNumber")
	if typeof(slotNumber) ~= "number" then
		warn(string.format(
			"[PlayerProfile] CollectPad under %s has no SlotNumber on its parent -- not wired. Collect pads must be built inside a slot's slime Model (see spawnSlimeVisual).",
			if model then model:GetFullName() else "(no parent)"
		))
		return
	end
	pad.Touched:Connect(function(hit: BasePart)
		-- The profile may already be gone (a leave mid-touch); the connection
		-- dies with the pad, but a queued event can still arrive.
		if profiles[player] ~= profile then
			return
		end
		collectPending(player, profile, slotNumber, pad, hit)
	end)
end

-- Wires every collect pad in this player's base, now and forever, WITHOUT
-- touching spawnSlimeVisual. The ten pads are created lazily -- one per slime,
-- whenever a slime is placed, which can happen hours after the join -- so a
-- one-shot pass over the folder would catch nothing at all. DescendantAdded
-- picks up each pad at the moment it is parented in, which is what makes a
-- slime placed late fully live; the initial loop covers any pad already present
-- if this is ever called later than it is today.
--
-- STILL CORRECT WITH THE RETURN PAD GONE (checked, not assumed): that pad was
-- the only reason this matched two names, and it was also the only pad the
-- initial loop ever actually found, since it was the only one built
-- synchronously in buildBaseFolder. Everything the ten pads depend on is the
-- DescendantAdded half, which is untouched.
--
-- Matching BY NAME is what keeps this additive: spawnSlimeVisual already names
-- its pad "CollectPad", so it needed no change to opt in.
local function wireCollectPads(player: Player, profile: Profile)
	local function considerDescendant(descendant: Instance)
		if descendant:IsA("BasePart") and descendant.Name == "CollectPad" then
			wireCollectPad(player, profile, descendant)
		end
	end
	profile.baseFolder.DescendantAdded:Connect(considerDescendant)
	for _, descendant in profile.baseFolder:GetDescendants() do
		considerDescendant(descendant)
	end
end

-- ===== Join: allocate a base, build its visuals immediately (so it's there
-- even before the load finishes), then load in the background and populate
-- money/slots/seen (and the slot visuals for anything already filled) once
-- it resolves. =====
local function onPlayerAdded(player: Player)
	local baseIndex = allocateBaseIndex()
	if not baseIndex then
		-- BUG FIX (see the written report): allocateBaseIndex used to be
		-- unbounded, so a 7th player just silently got index 6 and a
		-- base/lane nothing could place. Players.MaxPlayers above should
		-- mean this path is never
		-- actually hit in a normally-matchmade server -- reaching it means
		-- something outside normal matchmaking (a Reserved Server, a
		-- teleport) got a 7th player in anyway. Reject loudly rather than
		-- build a profile for a player with nowhere to stand: Kick is the
		-- only way to "reject a join" once PlayerAdded has already fired --
		-- the player is already in Players by this point, there is no
		-- earlier hook to refuse the connection from inside this script.
		warn(string.format(
			"[PlayerProfile] No free lane for %s (UserId %d) -- all %d lanes are occupied. Kicking.",
			player.Name, player.UserId, LaneConfig.LANE_COUNT
		))
		player:Kick(string.format("This server is full (max %d players).", LaneConfig.LANE_COUNT))
		return
	end
	local baseFolder = buildBaseFolder(player, baseIndex)
	-- ===== BUILT BEFORE THE LOAD, NOT AFTER IT (see REPORT.md STEP 1f), and
	-- that is safe because its three starting values are not placeholders -- they
	-- are the true values of a brand-new profile: tier 1, $0, $0/s. The profile
	-- literal directly below starts at exactly those, so nothing wrong is on
	-- screen during the DataStore read; the leaderboard simply shows a fresh
	-- player until the load says otherwise, and refreshLeaderstats corrects it at
	-- the bottom of the load.
	--
	-- The rejected alternative was building it after the load resolves. It would
	-- have left the player with no leaderboard row at all for the length of a
	-- DataStore read (and its retries), and -- worse -- a FAILED load returns
	-- early, so a player whose load failed would have had no leaderboard for the
	-- whole session. Those sessions play on a blank profile, for which 1/$0/$0 is
	-- the correct display anyway.
	local leaderstats = buildLeaderstats(player)

	local profile: Profile = {
		baseIndex = baseIndex,
		baseFolder = baseFolder,
		leaderstats = leaderstats,
		money = 0,
		pendingBySlot = {},
		offlineCredit = 0,
		-- Empty, so a slot with no entry is never debounced on its first touch
		-- (see collectPending, which reads a missing entry as -math.huge).
		lastCollectAtBySlot = {},
		slots = {},
		visualParts = {},
		inventory = {},
		seen = {},
		levels = {},
		swingTier = 1,
		chestsOpened = 0,
		chestPending = false,
		canSave = false,
	}
	profiles[player] = profile

	-- Wired BEFORE the load starts, not after it. No pad exists yet -- every one
	-- of the ten is born with its slime, and the first of those is spawned at the
	-- bottom of the load below -- so what this actually arms early is the
	-- DescendantAdded watch, which has to be listening before the first
	-- spawnSlimeVisual runs or that slime's pad is never wired at all.
	wireCollectPads(player, profile)

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

		-- ===== ORDER IS LOAD-BEARING HERE. applyLoadedData populates slots and
		-- levels; creditOfflineIncome reads them (through totalIncomePerSecond)
		-- to work out the rate. Running the accrual first would compute a rate
		-- of zero against still-empty tables and credit the player nothing,
		-- silently. The two lines below must stay in this order.
		--
		-- AND BOTH SIT BELOW THE `not ok` BAIL ABOVE, which is what makes a
		-- FAILED LOAD credit zero: a load failure means this session plays on a
		-- blank profile with canSave false, so its slots are empty and its
		-- `data` is nil. Paying offline income against that would invent money
		-- from a profile we explicitly could not read -- and, worse, would do it
		-- for a session that is forbidden from saving, so the credit would
		-- vanish again on the next join. The early return above is the guard;
		-- there is no second check here because there is no path to here.
		applyLoadedData(profile, data)
		creditOfflineIncome(profile, data)
		profile.canSave = true
		-- THE CROWN, applied HERE and not at build time. buildBaseFolder
		-- already ran (it is what created baseFolder for this profile), and it
		-- ran before this DataStore read resolved -- so the sign exists but
		-- nothing knew yet whether this player had ever opened a chest. That
		-- load order is the whole reason SignBuilder exposes setCrown instead
		-- of taking a hasCrown build argument.
		refreshSignCrown(profile)
		baseFolder:SetAttribute("Money", profile.money)
		baseFolder:SetAttribute("SwingTier", profile.swingTier)
		-- Publishes the loaded pots and whatever the accrual just credited, in
		-- the same post-load burst as Money.
		publishPending(profile)
		for i = 1, BaseConfig.SLOT_COUNT do
			local globalIndex = profile.slots[i]
			if globalIndex then
				spawnSlimeVisual(profile, i, SlimeData.SLIMES[globalIndex], profile.levels[i] or 1)
			end
		end
		syncClientState(profile)
		-- LAST, after every piece of the load has landed -- money, tier, slots
		-- and levels are all final by this line, so one call publishes all three
		-- columns correctly. Placing it beside the Money/SwingTier attribute
		-- writes further up would have published a correct tier and balance
		-- against a still-empty slot table, i.e. a $/s of zero, and then left it
		-- there until the player's next purchase.
		refreshLeaderstats(profile)
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
-- ===== Treasure chest state (see TreasureConfig.luau and REPORT.md) =====

-- Records that this player has EARNED a chest by landing on the platform.
-- Idempotent: a second platform landing before the first is opened does not
-- stack. Chests are not a currency.
function PlayerProfile.markChestPending(player: Player)
	local profile = profiles[player]
	if profile then
		profile.chestPending = true
	end
end

-- Claims the pending chest, ATOMICALLY: returns true exactly once per earned
-- chest and false every other time. This is the whole gate on the shared
-- chest's ProximityPrompt -- two Triggered signals from the same player (a
-- double tap, a modified client spamming it) award one slime between them,
-- because the second call finds the flag already cleared.
function PlayerProfile.consumeChestPending(player: Player): boolean
	local profile = profiles[player]
	if not (profile and profile.chestPending) then
		return false
	end
	profile.chestPending = false
	return true
end

-- Permanent once earned -- nothing ever decrements this. Refreshes the crown
-- on this player's own entrance sign immediately, so the mark appears the
-- moment it is earned rather than on next join.
function PlayerProfile.recordChestOpened(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.chestsOpened += 1
	refreshSignCrown(profile)
	syncClientState(profile)
	-- Nothing on the leaderboard changes here (a chest count is not a column),
	-- and refreshLeaderstats writes nothing when nothing differs. It is called
	-- anyway so the rule is exceptionless -- EVERY syncClientState call site is
	-- followed by one -- which is what dev/analysis/verify_leaderstats.luau
	-- checks. A rule with one documented exception is a rule nobody can verify.
	refreshLeaderstats(profile)
end

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
			profile.levels[i] = 1
			spawnSlimeVisual(profile, i, slime, 1)
			syncClientState(profile)
			-- A slime just started earning: $/s moves.
			refreshLeaderstats(profile)
			return true
		end
	end
	profile.inventory[slime.globalIndex] = (profile.inventory[slime.globalIndex] or 0) + 1
	syncClientState(profile)
	-- The base was full, so this went to inventory and NOTHING changed -- an
	-- unplaced slime earns nothing. Called for the exceptionless rule above.
	refreshLeaderstats(profile)
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
			profile.levels[i] = 1
			spawnSlimeVisual(profile, i, slime, 1)
			if owned <= 1 then
				profile.inventory[globalIndex] = nil
			else
				profile.inventory[globalIndex] = owned - 1
			end
			syncClientState(profile)
			-- A slime just started earning: $/s moves.
			refreshLeaderstats(profile)
			return true, nil
		end
	end
	return false, "no free slot -- remove one first"
end

-- Moves the slime in slot `slotNumber` back to inventory, freeing the slot.
-- Fails if the slot number is out of range or already empty.
--
-- ===== BANKS THAT SLOT'S POT FIRST (see REPORT.md STEP 1e). This is the ONLY
-- function in the project that empties a slot -- verified, not assumed: it is
-- the only `profile.slots[n] = nil` in the tree, and the two other paths that
-- could destroy a slime's earnings both route through it (devClearBase calls it
-- per slot; devWipeProfile calls devClearBase). sellFromInventory cannot reach a
-- slot at all -- it only ever reads/decrements profile.inventory, which is
-- exactly what makes "remove before you sell" true by construction -- and there
-- is no replacement path: placeFromInventory refuses when the base is full
-- rather than swapping anything out.
--
-- So this one line is the whole guarantee. A slime carrying $2M that silently
-- lost it when the player pressed Remove would be a trap nobody sees coming, and
-- the pad it would have been collected at is destroyed with the slime a few
-- lines below. Banking goes through bankSlot, the same single door a collect
-- pad uses, so a removal pays exactly what walking over the pad first would
-- have paid.
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

	-- BEFORE the slot is cleared, and before the model (and with it the pad) is
	-- destroyed. Silent if the pot was empty, which is the common case.
	bankSlot(profile, slotNumber)

	profile.slots[slotNumber] = nil
	-- Level is discarded here, not carried into the inventory stack -- see
	-- the `levels` field's own comment on the Profile type for why.
	profile.levels[slotNumber] = nil
	local model = profile.visualParts[slotNumber]
	if model then
		model:Destroy()
		profile.visualParts[slotNumber] = nil
	end
	profile.inventory[globalIndex] = (profile.inventory[globalIndex] or 0) + 1
	syncClientState(profile)
	-- BOTH columns move here, which is why this call is not redundant with the
	-- one bankSlot already made a few lines above: that one published the banked
	-- money while the slot was still occupied and still earning. This one
	-- publishes the rate AFTER the slot was cleared.
	refreshLeaderstats(profile)
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
	-- Money only: selling reads and decrements INVENTORY, never slots, so the
	-- rate cannot move here (see this function's own header).
	refreshLeaderstats(profile)
	return true, nil
end

-- ===== Upgrades: level up a PLACED slime with money -- see UpgradeServer.
-- server.luau (the only caller) for the remote plumbing. THIS function is
-- the entire server-side validation: slot occupancy, the count actually
-- affordable/available, and the price (the SUM of each individual level's
-- own cost, never `count` times the first one) are all decided here, from
-- this player's own server-held profile and SlimeUpgrade's shared formula --
-- never from a cost the client claims. =====

-- Upgrades the slime in slot `slotNumber` by UP TO `count` levels (fewer if
-- the slime hits MAX_LEVEL first, or if the player can only afford fewer --
-- see below), charging the exact sum of each individual level's own cost.
-- Fails outright (no partial charge) if the slime is already at MAX_LEVEL, or
-- if the player can't afford even a single level.
--
-- AFFORDABILITY AND PARTIAL BUYS: unlike sellFromInventory/buyNextTier (all-
-- or-nothing), this deliberately buys as many of the requested `count` levels
-- as the player can actually afford, rather than failing the whole purchase
-- because the LAST of, say, 100 requested levels was one dollar short. Same
-- reasoning as the MAX_LEVEL cap below: a client showing "MAX +12" already
-- knows the cost of exactly 12, but money keeps changing underneath (income ticks
-- every second) -- refusing a purchase entirely over a stale price the UI
-- computed a moment ago would be a worse experience than simply buying what's
-- affordable right now. Returns the actual number of levels bought so the
-- caller can report it.
function PlayerProfile.upgradeSlime(player: Player, slotNumber: number, count: number): (boolean, string?, number?)
	local profile = profiles[player]
	if not profile then
		return false, "no profile", nil
	end
	if typeof(slotNumber) ~= "number" or slotNumber ~= math.floor(slotNumber) or slotNumber < 1 or slotNumber > BaseConfig.SLOT_COUNT then
		return false, "invalid slot", nil
	end
	if typeof(count) ~= "number" or count ~= math.floor(count) or count < 1 then
		return false, "invalid count", nil
	end

	local globalIndex = profile.slots[slotNumber]
	if not globalIndex then
		return false, "that slot is empty", nil
	end
	local slime = SlimeData.SLIMES[globalIndex]
	if not slime then
		return false, "unknown slime", nil
	end

	local currentLevel = profile.levels[slotNumber] or 1
	if currentLevel >= SlimeUpgradeConfig.MAX_LEVEL then
		return false, "already at max level", nil
	end

	-- totalUpgradeCost already caps `count` at however many levels remain
	-- before MAX_LEVEL -- affordability (below) is the only OTHER thing that
	-- can shrink the actual purchase further.
	local fullCost, requestedCount = SlimeUpgrade.totalUpgradeCost(slime.incomePerSecond, currentLevel, count)
	local buyCount = requestedCount
	local cost = fullCost
	if profile.money < cost then
		-- Binary search the largest affordable count in [0, requestedCount] --
		-- cost is monotonically increasing in count (every individual level's
		-- cost is positive), so this always converges to the exact affordable
		-- maximum in a handful of steps. Kept as a search rather than a plain
		-- loop even though MAX_LEVEL is only 25 now: totalUpgradeCost is a
		-- closed form either way, and this stays correct whatever the cap is
		-- retuned to.
		local low, high = 0, requestedCount
		while low < high do
			local mid = (low + high + 1) // 2
			local midCost = SlimeUpgrade.totalUpgradeCost(slime.incomePerSecond, currentLevel, mid)
			if midCost <= profile.money then
				low = mid
			else
				high = mid - 1
			end
		end
		buyCount = low
		cost = SlimeUpgrade.totalUpgradeCost(slime.incomePerSecond, currentLevel, buyCount)
	end

	if buyCount <= 0 then
		return false, "not enough money", nil
	end

	profile.money -= cost
	profile.levels[slotNumber] = currentLevel + buyCount
	profile.baseFolder:SetAttribute("Money", profile.money)
	refreshSlimeVisualLabel(profile, slotNumber)
	syncClientState(profile)
	-- THE ONE MOST LIKELY TO BE MISSED (see REPORT.md STEP 3c): an upgrade moves
	-- money AND the income rate, and a leaderboard wired only to money changes
	-- would show the new balance beside a stale $/s -- which is precisely the
	-- number this column exists to make visible.
	refreshLeaderstats(profile)
	return true, nil, buyCount
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

-- This player's own lane index (see allocateBaseIndex above) -- the SAME
-- index BaseGeometry places their base with, reused directly as their swing
-- lane by LaunchServer.server.luau, never a second parallel index. Returns
-- nil, not a fallback like getSwingTier's 1 above, when no profile exists
-- yet: unlike a tier (where "1" is always a safe, meaningful default), there
-- is no safe default lane index to hand back -- a caller building or
-- looking up per-lane geometry from a wrong guessed index would place it on
-- top of, or destroy, some OTHER player's actual lane. Callers (see
-- LaunchServer.server.luau) are expected to wait/retry rather than treat
-- nil as "lane 0."
function PlayerProfile.getBaseIndex(player: Player): number?
	local profile = profiles[player]
	if not profile then
		return nil
	end
	return profile.baseIndex
end

-- Buys EXACTLY the next tier after this player's current one -- there is no
-- "which tier" argument anywhere in this call chain (see ShopServer's
-- onBuyTier), so a modified client cannot ask to buy the top tier while sitting
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
	-- Swing AND Money both move. Note this function does NOT call
	-- syncClientState (it touches neither slots nor inventory), so this is one of
	-- the sites the "every syncClientState is followed by a refresh" rule does
	-- not reach -- it needs its own call.
	refreshLeaderstats(profile)
	return true, nil
end

-- ===== Income: paid out on a fixed TICK, not continuously -- a discrete lump
-- added once every BaseConfig.BASE_INCOME_TICK_SECONDS, not a smooth
-- per-Heartbeat crawl. The lump is totalIncomePerSecond(profile) (defined above,
-- beside the pot's other writer) times the ACTUAL elapsed time, so the effective
-- payout rate stays correct however that config value is tuned. Every connected
-- player's base earns independently of whether they currently hold the swing's
-- shared rider slot.
--
-- ===== INCOME ACCRUES INTO THE PENDING POTS, NOT INTO CASH, AND EACH SLOT
-- CREDITS ITS OWN POT AT ITS OWN RATE (see REPORT.md STEP 1b) -- never a share
-- of the total. The player banks a slot by walking over that slime's own collect
-- pad; ten slimes are ten independent pots, and walking the row banks all ten.
--
-- The pots are the same destination offline time credits to
-- (creditOfflineIncome), through the same slotIncomePerSecond, which is what
-- keeps the online and offline rates impossible to diverge -- the only thing
-- between them is BaseConfig.OFFLINE_RATE_MULTIPLIER, deliberately the single
-- knob.
--
-- NO CAP, and no clamp of any kind on how large a pot may grow while the player
-- is connected. An AFK player is ONLINE: they earn at the full rate, forever,
-- and the 12-hour offline cap does not touch them. That asymmetry is a design
-- position, not an oversight -- see BaseConfig.OFFLINE_CAP_SECONDS.
--
-- ONE publishPending PER PROFILE PER TICK, after the whole slot loop, not one
-- per slot: publishing is an attribute write plus a JSON encode, and the ten
-- slots of one profile are one state change as far as any client is concerned.
-- ===== PAYS FOR TIME THAT ACTUALLY PASSED, NOT FOR THE INTERVAL WE ASKED FOR.
-- BUG FIX (see REPORT.md). This loop used to credit `rate *
-- BASE_INCOME_TICK_SECONDS` -- the NOMINAL interval -- while task.wait(n)
-- returns after AT LEAST n seconds: it resumes on the first Heartbeat at or
-- after the deadline, so the real gap is n plus up to a full frame, and more
-- than that whenever the server hitches. Every tick therefore dropped the
-- overshoot on the floor, unboundedly and silently.
--
-- Measured at ~0.87% of all idle income on a 60fps-equivalent scheduler (mean
-- overshoot ~7ms on a 1s tick), which is about 31 seconds of income lost per
-- hour online, and it gets WORSE exactly when the server is busiest. It was
-- invisible while income went straight to cash and arrived alongside launch
-- rewards; it would not have stayed invisible in a pot the player watches
-- accumulate.
--
-- os.clock(), not Workspace:GetServerTimeNow(): this needs a monotonic
-- process-local duration, and os.clock cannot jump backwards or be resynced
-- against a time server mid-interval the way a wall clock can.
--
-- DELIBERATELY UNCLAMPED. A 10-second hitch credits 10 seconds, which is
-- correct -- the player WAS online for those 10 seconds and their slimes were
-- earning. There is no runaway to guard against: os.clock is monotonic, so
-- `elapsed` can never be negative, and the only way it gets large is real time
-- really passing. Clamping it would reintroduce the same under-payment this fix
-- removes, just at a higher threshold.
--
-- ONE ACCEPTED IMPRECISION, unchanged from before: a player who joins midway
-- through an interval is paid for the whole of it. It is bounded by one tick
-- (1 second at the current config) and always in the player's favour, so it is
-- not worth a per-profile timestamp to chase.
task.spawn(function()
	local lastTick = os.clock()
	while true do
		task.wait(BaseConfig.BASE_INCOME_TICK_SECONDS)
		local now = os.clock()
		local elapsed = now - lastTick
		lastTick = now
		for _, profile in profiles do
			local credited = false
			for i = 1, BaseConfig.SLOT_COUNT do
				local income = slotIncomePerSecond(profile, i)
				if income > 0 then
					profile.pendingBySlot[i] = (profile.pendingBySlot[i] or 0) + income * elapsed
					credited = true
				end
			end
			if credited then
				publishPending(profile)
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
	refreshLeaderstats(profile)
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
	refreshLeaderstats(profile)
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
	-- devClearBase routes every occupied slot through removeToInventory, which
	-- banks that slot's pot before clearing it -- so by the time the two lines
	-- below run, every pot has already been paid into `money`, and `money` is
	-- then zeroed with everything else. That ordering is deliberate rather than
	-- wasteful: a wipe is a full reset and is SUPPOSED to end at zero, but it
	-- gets there through the same single door every other pot uses, so there is
	-- no second "discard a pot" path in the file for a later reader to find and
	-- copy.
	PlayerProfile.devClearBase(player)
	profile.money = 0
	profile.baseFolder:SetAttribute("Money", 0)
	-- The pots are part of "fresh-player state" -- a wipe that left one would
	-- have the player collect the pre-wipe base's earnings a moment later, which
	-- is exactly the confusion this button exists to avoid. Empty after
	-- devClearBase in every ordinary case; this covers a pot on a slot that was
	-- somehow already empty.
	profile.pendingBySlot = {}
	profile.offlineCredit = 0
	publishPending(profile)
	profile.inventory = {}
	profile.seen = {}
	profile.swingTier = 1
	profile.baseFolder:SetAttribute("SwingTier", 1)
	syncClientState(profile)
	-- All three columns at once: devClearBase emptied every slot (rate -> 0),
	-- money was zeroed, and the tier was reset.
	refreshLeaderstats(profile)
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
	refreshLeaderstats(profile)
end

-- Sets the level of the slime PLACED in slot `slotNumber` directly, bypassing
-- cost entirely -- for testing income/upgrade-cost feel at any level without
-- grinding or faking money. No-op if the slot is empty (there's no slime
-- there to level). Clamped via SlimeUpgrade.clampLevel, same as a loaded save
-- value -- a dev-panel typo can't leave a slot above MAX_LEVEL or below 1.
function PlayerProfile.devSetSlimeLevel(player: Player, slotNumber: number, level: number)
	local profile = profiles[player]
	if not profile then
		return
	end
	if typeof(slotNumber) ~= "number" or slotNumber ~= math.floor(slotNumber) or slotNumber < 1 or slotNumber > BaseConfig.SLOT_COUNT then
		return
	end
	if not profile.slots[slotNumber] then
		return
	end
	profile.levels[slotNumber] = SlimeUpgrade.clampLevel(level)
	refreshSlimeVisualLabel(profile, slotNumber)
	syncClientState(profile)
	-- A level change is a rate change, same as a real upgrade.
	refreshLeaderstats(profile)
end
-- ===== END DEV PANEL SUPPORT =====

return PlayerProfile
