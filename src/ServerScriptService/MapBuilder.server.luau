--!strict
-- Builds the map blockout once, at server startup: the kerb along the road
-- edge, each lane's plot (mat, central path, side/back edges), the paved
-- links connecting a lane's swing to its own base, the walkway tying every
-- lane together (between the swings and the bases -- see PathConfig's own
-- header), and the two shop stalls. Purely decorative/static --
-- this script only ever CREATES new Workspace instances and never reads or
-- writes anything the swing/launch/scoring logic depends on, so it cannot
-- affect them.
--
-- GENERATED, NOT HAND-AUTHORED: same reasoning as RunwayBuilder.server.luau
-- -- this is a repeated, formulaic set of parts (six lanes' worth of plots
-- and links, plus two mirrored stalls), which is exactly what a loop is for
-- rather than hand-copying dozens of near-identical JSON blocks into
-- default.project.json. Only the Baseplate itself belongs there.
--
-- The ten slot pads inside each plot ARE built here, same as the mat and
-- edges (see BaseGeometry.slotPosition/slotPositions) -- a pad marking
-- where a slime would go is static per-lane world dressing, same as the
-- plot it sits in, whether or not that lane's player has joined yet.
-- PlayerProfile.luau no longer builds or owns any pad -- it only finds the
-- pad already built here for its own lane + slot number and places a slime
-- part onto it once revealed. Everything in THIS file exists for all
-- LANE_COUNT lanes from the moment the server starts, whether or not that
-- lane's player has joined yet.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LaneConfig = require(ReplicatedStorage.Config.LaneConfig)
local BaseConfig = require(ReplicatedStorage.Config.BaseConfig)
local BaseGeometry = require(ReplicatedStorage.Config.BaseGeometry)
local GroundConfig = require(ReplicatedStorage.Config.GroundConfig)
local PathConfig = require(ReplicatedStorage.Config.PathConfig)
local StallConfig = require(ReplicatedStorage.Config.StallConfig)
-- Only for the mount radius marker below -- SWING_MOUNT_RADIUS_STUDS and its
-- accompanying marker colour/transparency/material/thickness/offset, all
-- owned there alongside checkProximityMounts' own detection math (see
-- LaunchServer.server.luau).
local LaunchConfig = require(ReplicatedStorage.Config.LaunchConfig)

local baseplate = Workspace:WaitForChild("Baseplate") :: BasePart
local groundY = baseplate.Position.Y + baseplate.Size.Y / 2

local mapFolder = Instance.new("Folder")
mapFolder.Name = "MapBlockout"
mapFolder.Parent = Workspace

-- ===== Part factory -- same shape as SwingBuilder's, kept local to this
-- file rather than shared, since nothing here needs SwingBuilder's rod/
-- orientation helpers beyond the flat link builder below. =====
local function newPart(size: Vector3, cf: CFrame, material: Enum.Material, color: Color3, name: string, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = true
	part.Size = size
	part.CFrame = cf
	part.Material = material
	part.Color = color
	part.Parent = parent
	return part
end

local function newBlock(size: Vector3, position: Vector3, material: Enum.Material, color: Color3, name: string, parent: Instance): Part
	return newPart(size, CFrame.new(position), material, color, name, parent)
end

-- A flat horizontal link spanning two points at the SAME Y (every path in
-- this file is flat, so this never has to handle a near-vertical
-- direction) -- oriented so its local Z axis runs along the line between
-- the two points, matching "width" (X) / "thickness" (Y) / "length" (Z) on
-- the returned size.
local function newFlatLink(pointA: Vector3, pointB: Vector3, width: number, thickness: number, material: Enum.Material, color: Color3, name: string, parent: Instance): Part
	local mid = pointA:Lerp(pointB, 0.5)
	local length = (pointB - pointA).Magnitude
	local cf = CFrame.new(mid, pointB)
	return newPart(Vector3.new(width, thickness, length), cf, material, color, name, parent)
end

-- A flat, ground-lying disc -- used only by the mount radius marker below.
-- Roblox's Cylinder shape puts its round faces on the part's own local
-- +-X by default (same convention SwingBuilder.luau's ground pads use);
-- rotating 90 degrees around Z turns that local X axis to point straight up
-- (world +Y), so the round face ends up facing the sky instead of sideways
-- -- a pancake lying flat on the ground, not a drum standing on its end.
local function newFlatDisc(center: Vector3, diameter: number, thickness: number, material: Enum.Material, color: Color3, transparency: number, name: string, parent: Instance): Part
	local part = newPart(Vector3.new(thickness, diameter, diameter), CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), material, color, name, parent)
	part.Shape = Enum.PartType.Cylinder
	part.CanCollide = false
	part.Transparency = transparency
	return part
end

-- ===== Kerb: one part, the full width of the road. =====
newBlock(
	GroundConfig.KERB_SIZE,
	Vector3.new(LaneConfig.ROAD_CENTER_X, groundY + GroundConfig.KERB_Y_OFFSET, GroundConfig.KERB_Z),
	GroundConfig.KERB_MATERIAL,
	GroundConfig.KERB_COLOR,
	"Kerb",
	mapFolder
)

-- ===== Per-lane plot + paths =====
for laneIndex = 0, LaneConfig.LANE_COUNT - 1 do
	local swingX = LaneConfig.laneCenterX(laneIndex)
	local baseX = LaneConfig.baseLaneCenterX(laneIndex)
	local laneSuffix = string.format("%02d", laneIndex)

	local laneFolder = Instance.new("Folder")
	laneFolder.Name = "Lane" .. laneSuffix
	laneFolder.Parent = mapFolder

	-- Mat.
	newBlock(BaseConfig.BASE_MAT_SIZE, BaseGeometry.matPosition(laneIndex), BaseConfig.BASE_MAT_MATERIAL, BaseConfig.BASE_MAT_COLOR, "Mat", laneFolder)

	-- Central path.
	newBlock(BaseConfig.BASE_PATH_SIZE, BaseGeometry.centralPathPosition(laneIndex), BaseConfig.BASE_PATH_MATERIAL, BaseConfig.BASE_PATH_COLOR, "CentralPath", laneFolder)

	-- Side edges (left, right).
	local sideLeft, sideRight = BaseGeometry.sideEdgePositions(laneIndex)
	newBlock(BaseConfig.BASE_SIDE_EDGE_SIZE, sideLeft, BaseConfig.BASE_EDGE_MATERIAL, BaseConfig.BASE_EDGE_COLOR, "SideEdgeLeft", laneFolder)
	newBlock(BaseConfig.BASE_SIDE_EDGE_SIZE, sideRight, BaseConfig.BASE_EDGE_MATERIAL, BaseConfig.BASE_EDGE_COLOR, "SideEdgeRight", laneFolder)

	-- Back edge.
	newBlock(BaseConfig.BASE_BACK_EDGE_SIZE, BaseGeometry.backEdgePosition(laneIndex), BaseConfig.BASE_EDGE_MATERIAL, BaseConfig.BASE_EDGE_COLOR, "BackEdge", laneFolder)

	-- Ten slot pads, flush on top of the mat (BaseGeometry.slotPosition
	-- already bakes in BASE_SLOT_PAD_Y_OFFSET) -- static, numbered markers
	-- showing where a slime would go whether or not this lane's player has
	-- joined yet, or a slime is currently sitting there. PlayerProfile finds
	-- these by lane + slot number (Slot01..Slot10) rather than building its
	-- own -- see PlayerProfile.luau's getSlotPad.
	for slotNumber, slotPosition in BaseGeometry.slotPositions(laneIndex) do
		local pad = newBlock(
			BaseConfig.BASE_SLOT_PAD_SIZE,
			slotPosition,
			BaseConfig.BASE_SLOT_PAD_MATERIAL,
			BaseConfig.BASE_SLOT_PAD_COLOR,
			string.format("Slot%02d", slotNumber),
			laneFolder
		)

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
		label.Text = tostring(slotNumber)
		label.Parent = surfaceGui
	end

	-- Mount radius marker: a flat, non-collidable disc centred on THIS
	-- lane's own swing pivot X/Z (swingX, LaneConfig.SWING_PIVOT_Z --
	-- exactly what checkProximityMounts measures against, see
	-- LaunchServer.server.luau), radius LaunchConfig.SWING_MOUNT_RADIUS_
	-- STUDS -- a visible "here's where auto-mount kicks in" hitbox, built
	-- for every lane whether or not that lane's player has joined yet, same
	-- as the rest of the plot dressing. Colour/transparency/material read
	-- from config (see LaunchConfig's own comment) so this can be tuned or
	-- switched off (Transparency = 1) without touching this file.
	newFlatDisc(
		Vector3.new(swingX, groundY + LaunchConfig.SWING_MOUNT_RADIUS_MARKER_Y_OFFSET, LaneConfig.SWING_PIVOT_Z),
		LaunchConfig.SWING_MOUNT_RADIUS_STUDS * 2,
		LaunchConfig.SWING_MOUNT_RADIUS_MARKER_THICKNESS,
		LaunchConfig.SWING_MOUNT_RADIUS_MARKER_MATERIAL,
		LaunchConfig.SWING_MOUNT_RADIUS_MARKER_COLOR,
		LaunchConfig.SWING_MOUNT_RADIUS_MARKER_TRANSPARENCY,
		"MountRadiusMarker",
		laneFolder
	)

	-- Angled link: swing side -> WALKWAY (see PathConfig's own header --
	-- the walkway now sits between the swings and the bases, not behind
	-- them), oriented along the line between the two (swingX and baseX are
	-- rarely equal, so this is genuinely angled, not just a straight
	-- strip).
	local linkY = groundY + PathConfig.ANGLED_LINK_Y_OFFSET
	local linkStart = Vector3.new(swingX, linkY, PathConfig.ANGLED_LINK_START_Z)
	local linkEnd = Vector3.new(baseX, linkY, PathConfig.ANGLED_LINK_END_Z)
	newFlatLink(linkStart, linkEnd, PathConfig.ANGLED_LINK_WIDTH, PathConfig.ANGLED_LINK_THICKNESS, PathConfig.PATH_MATERIAL, PathConfig.PATH_COLOR, "AngledLink", laneFolder)

	-- Spur: WALKWAY -> plot, still on baseX -- bridges the gap between the
	-- walkway (reached first now) and the plot (moved back to clear it) so
	-- a player can walk swing -> walkway -> base without ever stepping on
	-- bare grass. See PathConfig.SPUR_Z/SPUR_SIZE's own comment for the
	-- exact span.
	local spurPosition = Vector3.new(baseX, groundY + PathConfig.SPUR_Y_OFFSET, PathConfig.SPUR_Z)
	newBlock(PathConfig.SPUR_SIZE, spurPosition, PathConfig.PATH_MATERIAL, PathConfig.PATH_COLOR, "Spur", laneFolder)
end

-- ===== Walkway: ONE part, spanning every lane, between the swings and the
-- bases (see PathConfig's own header for why it moved here). =====
newBlock(
	PathConfig.BACK_WALKWAY_SIZE,
	Vector3.new(LaneConfig.ROAD_CENTER_X, groundY + PathConfig.BACK_WALKWAY_Y_OFFSET, PathConfig.BACK_WALKWAY_Z),
	PathConfig.PATH_MATERIAL,
	PathConfig.PATH_COLOR,
	"BackWalkway",
	mapFolder
)

-- ===== Two stalls, mirrored. face = -sign(x0) points every stall-relative
-- X-offset back toward the road's centerline, so both stalls face inward
-- toward the swings regardless of which side they're built on. =====
for _, x0 in StallConfig.STALL_X_POSITIONS do
	local face = -math.sign(x0)
	local z = StallConfig.STALL_CENTER_Z

	local stallFolder = Instance.new("Folder")
	stallFolder.Name = string.format("Stall%d", x0)
	stallFolder.Parent = mapFolder

	-- Four posts: every combination of X = x0 +- offset, Z = z +- offset.
	local postY = groundY + StallConfig.STALL_POST_Y_OFFSET
	for _, xSign in { -1, 1 } do
		for _, zSign in { -1, 1 } do
			local position = Vector3.new(
				x0 + xSign * StallConfig.STALL_POST_X_OFFSET,
				postY,
				z + zSign * StallConfig.STALL_POST_Z_OFFSET
			)
			local name = string.format("Post_%s%s", if xSign < 0 then "N" else "P", if zSign < 0 then "N" else "P")
			newBlock(StallConfig.STALL_POST_SIZE, position, StallConfig.STALL_POST_MATERIAL, StallConfig.STALL_POST_COLOR, name, stallFolder)
		end
	end

	-- Front panel.
	local panelPosition = Vector3.new(x0 + face * StallConfig.STALL_PANEL_X_OFFSET, groundY + StallConfig.STALL_PANEL_Y_OFFSET, z)
	newBlock(StallConfig.STALL_PANEL_SIZE, panelPosition, StallConfig.STALL_PANEL_MATERIAL, StallConfig.STALL_PANEL_COLOR, "FrontPanel", stallFolder)

	-- Panel rail.
	local railPosition = Vector3.new(x0 + face * StallConfig.STALL_RAIL_X_OFFSET, groundY + StallConfig.STALL_RAIL_Y_OFFSET, z)
	newBlock(StallConfig.STALL_RAIL_SIZE, railPosition, StallConfig.STALL_RAIL_MATERIAL, StallConfig.STALL_RAIL_COLOR, "PanelRail", stallFolder)

	-- Counter top.
	local counterPosition = Vector3.new(x0 + face * StallConfig.STALL_COUNTER_X_OFFSET, groundY + StallConfig.STALL_COUNTER_Y_OFFSET, z)
	newBlock(StallConfig.STALL_COUNTER_SIZE, counterPosition, StallConfig.STALL_COUNTER_MATERIAL, StallConfig.STALL_COUNTER_COLOR, "CounterTop", stallFolder)

	-- Roof deck.
	local roofDeckPosition = Vector3.new(x0, groundY + StallConfig.STALL_ROOF_DECK_Y_OFFSET, z)
	newBlock(StallConfig.STALL_ROOF_DECK_SIZE, roofDeckPosition, StallConfig.STALL_ROOF_DECK_MATERIAL, StallConfig.STALL_ROOF_DECK_COLOR, "RoofDeck", stallFolder)

	-- Roof band.
	local roofBandPosition = Vector3.new(x0, groundY + StallConfig.STALL_ROOF_BAND_Y_OFFSET, z)
	newBlock(StallConfig.STALL_ROOF_BAND_SIZE, roofBandPosition, StallConfig.STALL_ROOF_BAND_MATERIAL, StallConfig.STALL_ROOF_BAND_COLOR, "RoofBand", stallFolder)

	-- Shopkeeper placeholder -- torso + head, named ShopkeeperPlaceholder,
	-- to be replaced with a real NPC later.
	local shopkeeperFolder = Instance.new("Model")
	shopkeeperFolder.Name = "ShopkeeperPlaceholder"
	shopkeeperFolder.Parent = stallFolder
	local shopkeeperX = x0 - face * StallConfig.STALL_SHOPKEEPER_X_OFFSET
	local torsoPosition = Vector3.new(shopkeeperX, groundY + StallConfig.STALL_TORSO_Y_OFFSET, z)
	newBlock(StallConfig.STALL_TORSO_SIZE, torsoPosition, StallConfig.STALL_SHOPKEEPER_MATERIAL, StallConfig.STALL_TORSO_COLOR, "Torso", shopkeeperFolder)
	local headPosition = Vector3.new(shopkeeperX, groundY + StallConfig.STALL_HEAD_Y_OFFSET, z)
	newBlock(StallConfig.STALL_HEAD_SIZE, headPosition, StallConfig.STALL_SHOPKEEPER_MATERIAL, StallConfig.STALL_HEAD_COLOR, "Head", shopkeeperFolder)

	-- Sign: its own Z (STALL_SIGN_Z), not the stall's own centre Z.
	local signX = x0 + face * StallConfig.STALL_SIGN_X_OFFSET
	local signLegPosition = Vector3.new(signX, groundY + StallConfig.STALL_SIGN_LEG_Y_OFFSET, StallConfig.STALL_SIGN_Z)
	newBlock(StallConfig.STALL_SIGN_LEG_SIZE, signLegPosition, StallConfig.STALL_SIGN_LEG_MATERIAL, StallConfig.STALL_SIGN_LEG_COLOR, "SignLeg", stallFolder)
	local signBoardPosition = Vector3.new(signX, groundY + StallConfig.STALL_SIGN_BOARD_Y_OFFSET, StallConfig.STALL_SIGN_Z)
	newBlock(StallConfig.STALL_SIGN_BOARD_SIZE, signBoardPosition, StallConfig.STALL_SIGN_BOARD_MATERIAL, StallConfig.STALL_SIGN_BOARD_COLOR, "SignBoard", stallFolder)
end
