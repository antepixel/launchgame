--!strict
-- Builds one wooden entrance sign Model from the imported mesh template (see
-- assets/Sign.rbxmx, synced into ReplicatedStorage.Assets.Sign by
-- default.project.json) -- replaces the floating "<name>'s Base" BillboardGui
-- that used to hang over slot 1 (see the written report: a BillboardGui sized
-- in pixel Offset holds a FIXED screen size at every distance, which is what
-- put a grey band on the horizon; a SurfaceGui on real geometry scales with
-- the world and simply shrinks away).
--
-- PURE ASSEMBLY ONLY, same contract as SlimeBuilder: clones the template,
-- flattens it, scales it, colours it, and hands back an UNPOSITIONED,
-- UNPARENTED Model. Every placement decision -- where it goes, which way it
-- faces, what surface it rests on -- belongs to the CALLER (PlayerProfile.
-- luau's buildBaseFolder, which reads BaseGeometry.entranceSignPosition). No
-- lane maths, nothing placement-specific lives in this file.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseConfig = require(ReplicatedStorage.Config.BaseConfig)

local SignBuilder = {}

-- The template's own part names, INSIDE the importer's wrapper Models
-- ("board_Node" > "board", "post_Node" > "post"). build() flattens those
-- wrappers away, so callers address model.board and model.post directly --
-- see flatten() below for why that happens in code rather than by hand in
-- Studio.
local BOARD_PART_NAME = "board"
local POST_PART_NAME = "post"

local assetsFolder = ReplicatedStorage:WaitForChild("Assets")
local template = assetsFolder:WaitForChild("Sign") :: Model
local templateBoard = template:FindFirstChild(BOARD_PART_NAME, true) :: MeshPart
local templatePost = template:FindFirstChild(POST_PART_NAME, true) :: MeshPart

-- MEASURED, DERIVED ONCE AT LOAD -- NOT HARDCODED (same reasoning as
-- SlimeBuilder's own UNIT_WIDTH_STUDS): Model:ScaleTo takes an ABSOLUTE
-- scale, not a multiplier, and an imported model does NOT arrive at scale 1.
-- This one arrives at ~5.962 (the slime arrived at 15.83), so the board's
-- CURRENT Size.X of ~16.098 studs is not its width-at-scale-1. Dividing the
-- current width by the current scale reverses that back out to the
-- width-at-scale-1 constant -- ~2.70 studs, the board's native width --
-- computed fresh from the live template every time this module loads. If the
-- asset is ever re-imported at a different scale, or the mesh itself changes,
-- this stays correct automatically.
local UNIT_WIDTH_STUDS = templateBoard.Size.X / template:GetScale()

-- The board face's own height/width ratio, measured rather than assumed (the
-- board is ~2.70 x 1.30, so ~0.481). A SurfaceGui's canvas covers the whole
-- face, so an element given THIS fraction of the canvas WIDTH and the full
-- canvas HEIGHT comes out exactly square -- which is how the avatar below
-- gets sized off the board's height without hardcoding an aspect ratio or
-- stretching. The text then takes the remaining (1 - this) of the width.
-- Both parts scale uniformly, so the template's ratio is the built sign's
-- ratio at any width.
local BOARD_FACE_ASPECT = templateBoard.Size.Y / templateBoard.Size.X

-- ===== The crown (see SignBuilder.setCrown). Every dimension is a fraction
-- of the BUILT board's own measured width, so it stays proportional at any
-- BASE_SIGN_WIDTH_STUDS rather than needing a second retune. A quarter of the
-- board's width reads clearly from the walkway without competing with the
-- name on the board itself.
local CROWN_PART_NAME = "Crown"
local CROWN_WIDTH_FRACTION = 0.25
local CROWN_HEIGHT_RATIO = 0.6
local CROWN_DEPTH_RATIO = 0.35
local CROWN_COLOR = Color3.fromRGB(235, 195, 60)

-- The player's headshot, as a Roblox-generated thumbnail: rbxthumb content
-- strings are resolved by the engine from data it already has, so this costs
-- no upload, no asset id and no web request of our own.
--
-- SIZE -- MATCHED TO WHAT THE BOARD CAN ACTUALLY RESOLVE, not just the
-- largest available. rbxthumb only accepts a fixed set of dimensions for
-- AvatarHeadShot (48/60/100/150/180/352/420). A SurfaceGui at its default
-- PixelsPerStud of 50 gives an 8-stud-wide board a canvas of 400 x ~193
-- pixels, and the avatar is a square the canvas's HEIGHT -- so ~193 pixels
-- across. 180 is the largest offered size that isn't simply being downscaled
-- on arrival; 352 would be fetching four times the pixels to throw most of
-- them away.
local AVATAR_THUMBNAIL_PIXELS = 180
local AVATAR_THUMBNAIL_FORMAT = "rbxthumb://type=AvatarHeadShot&id=%d&w=%d&h=%d"

-- BOARD FACE AXIS -- DETERMINED FROM GEOMETRY, NOT ASSUMED (same approach as
-- SlimeBuilder's own MESH_FACE_AXIS): every CFrame in assets/Sign.rbxmx
-- carries IDENTITY rotation (R00..R22 = the identity matrix, on the model,
-- both wrapper Models and both MeshParts alike), so the template's own local
-- space and world space are the same thing here -- comparing raw positions
-- directly IS comparing them in the template's unrotated local space.
--
-- The board is a thin slab (0.10 studs deep against 2.70 x 1.30 of face), so
-- BOTH of its large faces lie on the Z axis and the only question is which
-- one the post is behind. Measured from the asset itself, in native units
-- relative to the post's own centre:
--   post:  Z -0.120 .. +0.120
--   board: Z -0.221 .. -0.121
-- They touch at Z ~= -0.12 and do not overlap. The board sits entirely on
-- the post's NEGATIVE-Z side, which means the post is behind the board's +Z
-- face and the board's -Z face is the flat, completely unobstructed one.
-- That -Z face is where the text goes.
--
-- WORTH FLAGGING: the brief for this pass described the board as sitting on
-- the post's +Z side (Z +0.121 .. +0.221). The magnitudes match exactly but
-- the SIGN is inverted -- the asset as saved has the board on -Z. Everything
-- below is measured from the asset rather than taken from the brief, and is
-- written to survive a re-export flipping it back.
local boardOffsetZ = templateBoard.Position.Z - templatePost.Position.Z
local BOARD_ON_NEGATIVE_Z = boardOffsetZ < 0

-- The board's exposed face, as a direction in the template's own local space.
SignBuilder.BOARD_FACE_AXIS = if BOARD_ON_NEGATIVE_Z then Vector3.new(0, 0, -1) else Vector3.new(0, 0, 1)

-- The same face, as the NormalId a SurfaceGui needs. NOTE the Roblox naming
-- trap this resolves: Enum.NormalId.Front is a part's -Z face and
-- Enum.NormalId.Back is its +Z face (a CFrame's LookVector is its own local
-- -Z, and "front" follows the LookVector) -- so the board's exposed -Z face
-- is Front, NOT Back. Reading "the board's +Z side" as "Back" would have put
-- the text on the side the post is bolted to.
local BOARD_TEXT_FACE = if BOARD_ON_NEGATIVE_Z then Enum.NormalId.Front else Enum.NormalId.Back

-- The 8 sign combinations for a box's own corners, relative to its center.
local CORNER_SIGNS = {
	Vector3.new(-1, -1, -1), Vector3.new(-1, -1, 1), Vector3.new(-1, 1, -1), Vector3.new(-1, 1, 1),
	Vector3.new(1, -1, -1), Vector3.new(1, -1, 1), Vector3.new(1, 1, -1), Vector3.new(1, 1, 1),
}

local function eachBasePart(model: Model): { BasePart }
	local parts: { BasePart } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

-- Explicit WORLD-AXIS AABB over every descendant BasePart's own 8 transformed
-- corners -- deliberately NOT Model:GetBoundingBox(), which returns an
-- ORIENTED bounding box whose axes can come back permuted relative to world
-- space rather than reliably world-axis-aligned. Callers use this to
-- bottom-align a built (and already positioned/rotated) sign against a
-- surface Y without needing to know anything about the mesh's own internal
-- pivot/origin offset. Returns (minCorner, maxCorner) in WORLD space,
-- reflecting the model's CURRENT CFrame at call time -- call it again after
-- moving the model if the answer needs to reflect a new position.
--
-- Deliberately a local copy of SlimeBuilder's identical helper rather than a
-- shared geometry library, matching this project's established shape: one
-- self-contained module per asset, no library of shared helpers (same
-- reasoning as PlayerProfile keeping its own money formatter).
function SignBuilder.worldAABB(model: Model): (Vector3, Vector3)
	local minCorner = Vector3.new(math.huge, math.huge, math.huge)
	local maxCorner = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, part in eachBasePart(model) do
		local halfSize = part.Size / 2
		local cframe = part.CFrame
		for _, sign in CORNER_SIGNS do
			local corner = cframe:PointToWorldSpace(Vector3.new(halfSize.X * sign.X, halfSize.Y * sign.Y, halfSize.Z * sign.Z))
			minCorner = Vector3.new(math.min(minCorner.X, corner.X), math.min(minCorner.Y, corner.Y), math.min(minCorner.Z, corner.Z))
			maxCorner = Vector3.new(math.max(maxCorner.X, corner.X), math.max(maxCorner.Y, corner.Y), math.max(maxCorner.Z, corner.Z))
		end
	end
	return minCorner, maxCorner
end

-- The CFrame that puts a sign at `position` with its BOARD FACE pointing
-- along `faceDirection` (a world-space direction). Callers should use this
-- rather than calling CFrame.lookAt themselves: lookAt always aims a CFrame's
-- local -Z at its target, which happens to be exactly the board's own face
-- axis as the asset is currently authored -- but if a re-export ever moves
-- the board to the post's +Z side, aiming -Z at the target would point the
-- board's BACK at the player. This handles both cases off the measured axis.
function SignBuilder.faceCFrame(position: Vector3, faceDirection: Vector3): CFrame
	local aim = if BOARD_ON_NEGATIVE_Z then faceDirection else -faceDirection
	return CFrame.lookAt(position, position + aim)
end

-- FLATTEN THE IMPORTER'S WRAPPER NESTING, IN CODE (see the module header):
-- the asset arrives as board_Node (Model) > board (MeshPart) and post_Node
-- (Model) > post (MeshPart). Reparenting the parts up to the model root and
-- destroying the now-empty wrappers lets callers address model.board and
-- model.post, and keeps Model:ScaleTo/worldAABB walking a flat hierarchy.
-- Doing it here rather than by hand in Studio means a re-import of the asset
-- needs no manual re-flattening to keep working.
--
-- Reparenting a BasePart does NOT move it: parts carry world CFrames, and a
-- Model applies no transform to its children, so every part stays exactly
-- where the import put it. GetDescendants returns a snapshot, so mutating
-- parents while iterating it is safe.
local function flatten(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Parent ~= model then
			descendant.Parent = model
		end
	end
	for _, child in model:GetChildren() do
		if child:IsA("Model") then
			child:Destroy()
		end
	end
end

-- Clones the template, flattens it, scales it to `widthStuds` wide (ABSOLUTE
-- ScaleTo -- see UNIT_WIDTH_STUDS above), strips the imported textures so the
-- configured wood colours actually show, and hangs a SurfaceGui on the
-- board's exposed face carrying `userId`'s headshot on the left and `text` on
-- the right. Returns the Model UNPOSITIONED (wherever the template's own
-- clone happens to sit) and UNPARENTED -- the caller places and parents it.
--
-- Takes a bare userId rather than a Player deliberately: the only thing this
-- module needs from a player is the number that goes in the thumbnail URL,
-- and taking the Player itself would invite the builder to start composing
-- the sign's TEXT too ("<name>'s Base"), which is base-naming policy and
-- belongs to the caller. A userId also keeps the module testable and usable
-- for any sign, not only a live player's base.
function SignBuilder.build(text: string, userId: number, widthStuds: number): Model
	local model = template:Clone()
	flatten(model)
	model:ScaleTo(widthStuds / UNIT_WIDTH_STUDS)

	local board = model:FindFirstChild(BOARD_PART_NAME) :: MeshPart
	local post = model:FindFirstChild(POST_PART_NAME) :: MeshPart
	model.PrimaryPart = board

	-- Both MeshParts arrive with a baked TextureID and Material Plastic. The
	-- texture has to go FIRST -- while it is set it tints over Color, so the
	-- configured browns would simply not show.
	board.TextureID = ""
	board.Material = Enum.Material.Wood
	board.Color = BaseConfig.BASE_SIGN_BOARD_COLOR

	post.TextureID = ""
	post.Material = Enum.Material.Wood
	post.Color = BaseConfig.BASE_SIGN_POST_COLOR

	for _, part in eachBasePart(model) do
		part.Anchored = true
		part.CanCollide = false
	end

	-- The text, on the board's own measured exposed face (see
	-- BOARD_TEXT_FACE). SizingMode is left at its default (PixelsPerStud) ON
	-- PURPOSE and no pixel-offset sizing is set anywhere: a SurfaceGui in
	-- that mode is painted onto the surface itself and so scales with the
	-- world, shrinking with distance like the board it sits on. That is the
	-- whole point of moving off the old BillboardGui, whose pixel-Offset Size
	-- held a fixed screen size at any range and read as a band on the
	-- horizon.
	local surface = Instance.new("SurfaceGui")
	surface.Name = "SignText"
	surface.Face = BOARD_TEXT_FACE
	surface.Parent = board

	-- Avatar on the LEFT, sized off the board's HEIGHT so it stays square
	-- (see BOARD_FACE_ASPECT). ScaleType.Fit is belt-and-braces on top of
	-- that arithmetic: even if the board's proportions ever change, Fit
	-- letterboxes the headshot inside its frame rather than stretching it.
	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.BackgroundTransparency = 1
	avatar.BorderSizePixel = 0
	avatar.Position = UDim2.fromScale(0, 0)
	avatar.Size = UDim2.fromScale(BOARD_FACE_ASPECT, 1)
	avatar.ScaleType = Enum.ScaleType.Fit
	avatar.Image = string.format(AVATAR_THUMBNAIL_FORMAT, userId, AVATAR_THUMBNAIL_PIXELS, AVATAR_THUMBNAIL_PIXELS)
	avatar.Parent = surface

	-- Text on the RIGHT, taking exactly what the avatar left. Same colour,
	-- font and TextScaled behaviour as before -- TextScaled simply refits it
	-- to the narrower box.
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Position = UDim2.fromScale(BOARD_FACE_ASPECT, 0)
	label.Size = UDim2.fromScale(1 - BOARD_FACE_ASPECT, 1)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.TextStrokeTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = BaseConfig.BASE_SIGN_TEXT_COLOR
	label.Text = text
	label.Parent = surface

	-- The crown, built ALWAYS and hidden by default (see setCrown). Built here
	-- rather than on demand because the sign is assembled before its owner's
	-- profile has finished loading -- there is no moment at build time when
	-- "has this player opened a chest" is knowable.
	--
	-- Sized and placed off the board's OWN measured geometry so it sits on the
	-- top edge at any sign width: worldAABB (not GetBoundingBox -- see its own
	-- comment) gives the built model's real extents after scaling, and the
	-- crown is a fraction of the board's width centred on it.
	local minCorner, maxCorner = SignBuilder.worldAABB(model)
	local boardWidth = maxCorner.X - minCorner.X
	local crownWidth = boardWidth * CROWN_WIDTH_FRACTION
	local crown = Instance.new("Part")
	crown.Name = CROWN_PART_NAME
	crown.Anchored = true
	crown.CanCollide = false
	crown.Size = Vector3.new(crownWidth, crownWidth * CROWN_HEIGHT_RATIO, crownWidth * CROWN_DEPTH_RATIO)
	crown.Color = CROWN_COLOR
	crown.Material = Enum.Material.Metal
	crown.Transparency = 1
	crown.CFrame = CFrame.new(
		(minCorner.X + maxCorner.X) / 2,
		maxCorner.Y + crown.Size.Y / 2,
		(minCorner.Z + maxCorner.Z) / 2
	)
	crown.Parent = model

	return model
end

-- Shows or hides a built sign's crown. A SETTER, not a build argument, and
-- that is load-order driven rather than stylistic: PlayerProfile builds the
-- sign in buildBaseFolder, which runs BEFORE the DataStore read that says
-- whether this player has ever opened a chest resolves. A build argument
-- would always be false on the first frame and need a rebuild afterwards.
-- A setter also handles earning the crown mid-session with no rebuild at all.
--
-- Tolerant of a sign built before this existed (returns quietly), so a live
-- server mid-rollout cannot error here.
function SignBuilder.setCrown(model: Model, visible: boolean)
	local crown = model:FindFirstChild(CROWN_PART_NAME)
	if crown and crown:IsA("BasePart") then
		crown.Transparency = if visible then 0 else 1
	end
end

return SignBuilder
