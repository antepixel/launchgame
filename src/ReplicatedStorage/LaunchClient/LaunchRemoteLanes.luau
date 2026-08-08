--!strict
-- SIX-LANE RENDERING: every OTHER connected player's swing and rider, drawn
-- from replicated attributes alone.
--
-- SPLIT OUT OF LaunchClient.client.luau (see REPORT.md -- that file hit Luau's
-- hard 200-locals-per-function-scope limit). Lives in
-- ReplicatedStorage.LaunchClient -- see LaunchClient's own require comment for
-- why. Reads Players.LocalPlayer at module scope, which is nil on a server and
-- harmless there: nothing on the server requires this, and the read itself
-- cannot error. The block moved VERBATIM, bodies
-- and comments both, and it is the cleanest cut in the whole file: it was
-- already written as a deliberately separate system with its own connection
-- (see the header LaunchClient keeps at the connect site), it reads nothing
-- this client owns, and nothing above it read anything of its.
--
-- THE STALE-ATTRIBUTE GUARD IS STRUCTURAL AND STAYED WHOLE. renderLaneOccupant
-- captures all five Flight* attributes, type-checks them TOGETHER, computes u
-- UNCLAMPED and rejects it outside [0, 1) -- one function, one capture, one
-- rejection, no part of it reachable or overridable from outside this module.
-- Nothing about that sequence crosses the module boundary: the capture and the
-- rejection are three lines apart in the same local function, exactly as they
-- were, and renderLaneOccupant is not exported. See REPORT.md for why that
-- shape is load-bearing (attribute replication gives no ordering guarantee
-- between RiderState and the params, so a "flying" read can arrive alongside
-- the PREVIOUS flight's still-valid numbers).
--
-- ITS OWN COPY OF seatPositionForPivot, unchanged. LaunchFormulas holds the
-- pure math both lane renderers share, but not this: LaunchClient's own
-- swingSeatPosition is the same three lines against the one pivot it closes
-- over, and merging the two is a behaviour-neutral edit this pass was told not
-- to make. Left as found, and written down in REPORT.md instead.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local LaunchConfig = require(ReplicatedStorage.Config.LaunchConfig)
local SwingGeometry = require(ReplicatedStorage.Config.SwingGeometry)
local LaunchFormulas = require(ReplicatedStorage.LaunchClient.LaunchFormulas)

local player = Players.LocalPlayer

local LaunchRemoteLanes = {}

-- PERMISSIVE ON PURPOSE (see the written report -- remote lane discovery
-- finding zero lanes in a 6-client Studio test): this used to be
-- "^SwingPivot_(%d+)$" -- %d matches digits ONLY, with no leading-minus-sign
-- case at all, so it silently rejected every SwingPivot_<UserId> whose
-- UserId is negative. Studio multi-client test sessions hand every
-- simulated client a placeholder UserId, and those are commonly negative --
-- the LOCAL lane was never affected by this (ownSwingPivotName below is
-- built with string.format("SwingPivot_%d", player.UserId), which formats a
-- negative number with its sign correctly; nothing about building that
-- string ever runs it back through a digits-only pattern), only the
-- REMOTE-lane discovery in rescanRemoteLanes, which does. ".+" captures
-- everything after the underscore, whatever it looks like, and
-- rescanRemoteLanes' own tonumber(userIdText) check (kept unchanged) is what
-- actually validates it, skipping the entry if it isn't a real number at
-- all -- the same outcome as before for genuine junk, but no longer for a
-- perfectly valid negative UserId.
local SWING_PIVOT_NAME_PATTERN = "^SwingPivot_(.+)$"

-- Same 3-line formula as swingSeatPosition above, just taking an EXPLICIT
-- pivot instead of closing over this client's own -- swingSeatPosition
-- itself is untouched.
local function seatPositionForPivot(pivot: BasePart, theta: number): Vector3
	local pivotPosition = pivot.Position
	local length = SwingGeometry.ropeLengthForPivotY(pivotPosition.Y)
	return pivotPosition + Vector3.new(0, -length * math.cos(theta), -length * math.sin(theta))
end

-- Same body as repositionChainLinks above, generalised to an explicit seat/
-- anchor/folder set instead of this client's own single-lane locals.
-- repositionChainSide itself is already fully generic (no closures over the
-- single-lane globals), so it's reused as-is here, unmodified.
local function repositionChainLinksFor(seatModel: Model, chainAnchorLeft: BasePart, chainAnchorRight: BasePart, chainLinksFolder: Folder)
	if not chainAnchorLeft.Parent or not chainAnchorRight.Parent then
		return
	end
	local seatCore = seatModel.PrimaryPart
	if not seatCore then
		return
	end
	local leftAttachment = seatCore:FindFirstChild("ChainBottomAttachmentLeft") :: Attachment?
	local rightAttachment = seatCore:FindFirstChild("ChainBottomAttachmentRight") :: Attachment?
	if not leftAttachment or not rightAttachment then
		return
	end

	local leftLinks, rightLinks = {}, {}
	for _, link in chainLinksFolder:GetChildren() do
		local side = link:GetAttribute("Side")
		if side == "Left" then
			table.insert(leftLinks, link)
		elseif side == "Right" then
			table.insert(rightLinks, link)
		end
	end
	LaunchFormulas.repositionChainSide(leftLinks, chainAnchorLeft.Position, leftAttachment.WorldPosition)
	LaunchFormulas.repositionChainSide(rightLinks, chainAnchorRight.Position, rightAttachment.WorldPosition)
end

-- One lane's seat sway, for a GIVEN pivot -- every viewer sees every lane
-- swing whether or not anyone is on it (same reasoning the local loop's own
-- comment gives), so this runs unconditionally for every lane found, not
-- just occupied ones. Returns the seat position (needed by
-- renderLaneOccupant below for "riding") or nil if this lane's structure
-- isn't fully built/is mid-rebuild (a tier purchase ClearAllChildren's the
-- structure folder before repopulating it -- see SwingBuilder.build) -- that
-- lane is simply skipped for this one frame, same "cheap, re-checked every
-- frame" shape ensureSwingReferences above uses for this client's own lane,
-- never an error.
local function renderLaneSeat(pivot: BasePart, laneIndex: number, structureFolder: Instance): Vector3?
	local seatModel = structureFolder:FindFirstChild("SwingSeat")
	if not (seatModel and seatModel:IsA("Model") and (seatModel :: Model).PrimaryPart) then
		return nil
	end
	local seat = seatModel :: Model

	local phase = LaunchFormulas.swingPhase(laneIndex)
	local theta = LaunchFormulas.swingTheta(phase)
	local seatPosition = seatPositionForPivot(pivot, theta)
	seat:PivotTo(CFrame.new(seatPosition) * CFrame.Angles(theta, 0, 0))

	local chainAnchorLeft = structureFolder:FindFirstChild("SwingChainAnchorLeft")
	local chainAnchorRight = structureFolder:FindFirstChild("SwingChainAnchorRight")
	local chainLinksFolder = structureFolder:FindFirstChild("SwingChainLinks")
	if
		chainAnchorLeft and chainAnchorLeft:IsA("BasePart")
		and chainAnchorRight and chainAnchorRight:IsA("BasePart")
		and chainLinksFolder and chainLinksFolder:IsA("Folder")
	then
		repositionChainLinksFor(seat, chainAnchorLeft :: BasePart, chainAnchorRight :: BasePart, chainLinksFolder :: Folder)
	end

	return seatPosition
end

-- One lane's OCCUPANT -- driven entirely from RiderState and, while flying,
-- the Flight* attributes LaunchServer.server.luau writes on the same pivot.
-- "landed"/"empty"/unset (a fresh pivot with no rider yet): writes nothing,
-- deliberately -- the character is already wherever the server's own one-
-- shot mount/release/landing/return PivotTo left it, and nothing here may
-- touch it outside exactly these two states.
local function renderLaneOccupant(pivot: BasePart, occupant: Player, seatPosition: Vector3?)
	local character = occupant.Character
	if not character then
		return
	end
	local riderState = pivot:GetAttribute("RiderState")
	if riderState == "riding" then
		if not seatPosition then
			return
		end
		character:PivotTo(LaunchFormulas.riderCFrame(seatPosition))
	elseif riderState == "flying" then
		local startTime = pivot:GetAttribute("FlightStartTime")
		local startPosition = pivot:GetAttribute("FlightStartPos")
		local distance = pivot:GetAttribute("FlightDistance")
		local archHeight = pivot:GetAttribute("FlightArcHeight")
		local duration = pivot:GetAttribute("FlightDuration")
		if
			typeof(startTime) ~= "number"
			or typeof(startPosition) ~= "Vector3"
			or typeof(distance) ~= "number"
			or typeof(archHeight) ~= "number"
			or typeof(duration) ~= "number"
			or duration <= 0
		then
			-- Attributes not fully written yet (see onRelease's own ordering
			-- guarantee -- params before RiderState flips to "flying") or a
			-- lane mid-teardown; skip this lane silently for this one frame.
			return
		end

		-- DELIBERATELY UNCLAMPED, then rejected outside [0, 1) -- see the
		-- written report. Attribute replication gives no ordering guarantee
		-- that observing RiderState == "flying" on a given frame also means
		-- THIS frame's Flight* reads are the NEW flight's values: the
		-- previous flight's own params are all still valid numbers (they
		-- pass the type guard above) right up until the new ones land, so a
		-- client can observe "flying" together with a STALE param set for
		-- one or more frames. A stale flight's startTime is always further
		-- in the past relative to its own (also stale) duration, so its u
		-- is always >= 1 -- clamping to 1 used to render that as "standing
		-- exactly at the old landing spot," silently, for however many
		-- frames the staleness lasted. Rejecting u >= 1 outright (alongside
		-- u < 0, for a startTime whose replication briefly arrives after a
		-- Heartbeat that started before it -- clock skew, not a bug) turns
		-- both stale-read shapes into "write nothing" instead of a wrong
		-- write. This also makes the per-frame render redundant with (not
		-- fighting) the "landed" attribute once it arrives: by the time
		-- RiderState flips to "landed" server-side, this client's own u had
		-- already been rejecting the same trajectory for at least one frame.
		local u = (Workspace:GetServerTimeNow() - (startTime :: number)) / (duration :: number)
		if u < 0 or u >= 1 then
			return
		end
		character:PivotTo(LaunchFormulas.trajectoryCFrame(startPosition :: Vector3, distance :: number, archHeight :: number, u))
	end
end

-- One discovered OTHER lane, cached between rescans -- see rescanRemoteLanes
-- below. `userId` is kept alongside (not re-parsed from pivot.Name every
-- render frame) purely so the per-frame path never touches string/pattern
-- work at all, only table reads and Instance calls.
type RemoteLane = {
	pivot: BasePart,
	laneIndex: number,
	structureFolder: Instance,
	userId: number,
}

local remoteLanes: { RemoteLane } = {}
local lastRemoteLaneScanClock = 0

-- Walks Workspace:GetChildren() ONCE, on a throttle (see rescan call site
-- below and LaunchConfig.REMOTE_LANE_RESCAN_INTERVAL_SECONDS), and replaces
-- the whole cache in one shot -- see the written report: LaneConfig.
-- LANE_COUNT bounds how many PIVOTS this can ever find, but not how many
-- CHILDREN Workspace has to be walked through to find them (road bands,
-- plot pads, stalls, mount-radius discs, per-player base folders, etc. are
-- all direct or indirect Workspace content too), so this walk itself is not
-- free -- it no longer runs every single RenderStepped.
--
-- `userIdText == tostring(player.UserId)` is the guard for "skip
-- LocalPlayer" -- a UserId comparison, not an Instance identity comparison
-- against swingPivot. LaunchServer.server.luau always names a player's own
-- pivot SwingPivot_<player.UserId> (see buildPlayerSwing/laneInstanceNames)
-- and never renames it, so the UserId encoded in a pivot's own Name is
-- stable regardless of whether the underlying Instance is ever destroyed
-- and recreated -- unlike a cached Instance reference, which would go stale
-- (and silently stop matching) the moment that happened. See the written
-- report for what was actually checked about SwingBuilder.build's own
-- rebuild behaviour, cited at this file's own investigation notes -- this
-- guard does not depend on the answer either way.
local function rescanRemoteLanes()
	local scanned: { RemoteLane } = {}
	for _, instance in Workspace:GetChildren() do
		if not instance:IsA("BasePart") then
			continue
		end
		local userIdText = instance.Name:match(SWING_PIVOT_NAME_PATTERN)
		if not userIdText or userIdText == tostring(player.UserId) then
			continue
		end
		local userId = tonumber(userIdText)
		if not userId then
			continue
		end
		local laneIndexAttribute = instance:GetAttribute("LaneIndex")
		if typeof(laneIndexAttribute) ~= "number" then
			continue
		end
		local structureFolder = Workspace:FindFirstChild("SwingStructure_" .. userIdText)
		if not structureFolder then
			continue
		end
		table.insert(scanned, {
			pivot = instance :: BasePart,
			laneIndex = laneIndexAttribute :: number,
			structureFolder = structureFolder,
			userId = userId,
		})
	end
	remoteLanes = scanned
end

-- Renders every OTHER connected player's own lane, every frame, from the
-- cache alone -- PivotTo itself must stay per-frame (that's the whole fix),
-- only the Workspace WALK that discovers/refreshes the lane list is
-- throttled (see rescanRemoteLanes above). A stale cache entry -- this
-- lane's occupant left, or a tier purchase is mid-rebuild and briefly
-- destroyed/recreated the structure's children -- is skipped silently for
-- the frame it's used, via ordinary .Parent checks, never an error; the
-- next rescan (at most REMOTE_LANE_RESCAN_INTERVAL_SECONDS later) drops or
-- refreshes it for real. No ChildAdded/ChildRemoved connection exists
-- anywhere in this system, so there is nothing to leak.
local function renderOtherLanes()
	local now = os.clock()
	if now - lastRemoteLaneScanClock >= LaunchConfig.REMOTE_LANE_RESCAN_INTERVAL_SECONDS then
		lastRemoteLaneScanClock = now
		rescanRemoteLanes()
	end

	for _, lane in remoteLanes do
		if not lane.pivot.Parent or not lane.structureFolder.Parent then
			continue
		end
		local seatPosition = renderLaneSeat(lane.pivot, lane.laneIndex, lane.structureFolder)

		local occupant = Players:GetPlayerByUserId(lane.userId)
		if occupant then
			renderLaneOccupant(lane.pivot, occupant, seatPosition)
		end
	end
end

LaunchRemoteLanes.render = renderOtherLanes

return LaunchRemoteLanes
