--!strict
-- Builds the treasure chest VISUAL Model from the imported mesh template (see
-- assets/Chest.rbxmx, synced into ReplicatedStorage.Assets.Chest by
-- default.project.json) -- replaces the two hand-built boxes MapBuilder used
-- to assemble (see REPORT.md). Same contract as SlimeBuilder/SignBuilder: PURE
-- ASSEMBLY ONLY. Clones the template, flattens the importer's wrappers, scales
-- it, groups it, colours it, and hands back an unpositioned, unparented Model.
-- Where the chest stands is MapBuilder's decision and lives there.
--
-- WHAT THE TEMPLATE LOOKS LIKE: one Model, twelve MeshParts, each wrapped in
-- its own "<name>_Node" Model by the importer -- exactly the shape
-- assets/Sign.rbxmx arrives in. Parts are named "<group>_<material>":
--   Base_deepgold  Base_gold  Base_iron  Base_plank  Base_plankdark  Base_woodshade
--   Lid_deepgold   Lid_gem    Lid_gold   Lid_plank   Lid_plankdark   Lid_woodshade
-- The wrappers are flattened HERE, in code, not by hand in Studio, so a
-- re-import needs no manual re-flattening to keep working.
--
-- AND THEN REGROUPED INTO TWO. The twelve parts go into child Models "Base"
-- and "Lid", by name prefix, because the lid has to pivot as a unit when the
-- chest opens -- see LaunchServer's setLidOpen and ChestBuilder.lidHinge.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TreasureConfig = require(ReplicatedStorage.Config.TreasureConfig)

local ChestBuilder = {}

local assetsFolder = ReplicatedStorage:WaitForChild("Assets")
local template = assetsFolder:WaitForChild("Chest") :: Model

local BASE_GROUP_NAME = "Base"
local LID_GROUP_NAME = "Lid"

-- The part each group's PrimaryPart is resolved to: the outer gold shell in
-- both cases, which is the one part in each group that spans the whole group.
-- PrimaryPart is set (rather than left nil) so GetPivot/PivotTo are EXACTLY a
-- part's CFrame rather than a bounding-box centre the engine may recompute --
-- setLidOpen composes a closed pose and an open pose against each other and
-- needs that round trip to be exact. Falls back to any part in the group if a
-- re-export ever renames these.
local BASE_PRIMARY_PART_NAME = "Base_gold"
local LID_PRIMARY_PART_NAME = "Lid_gold"

-- WHICH WAY THE CHEST FACES, DERIVED FROM THIS PART (see orientLockToFront).
-- The iron piece is the clasp: 0.26 x 0.29 x 0.055 at scale 1 -- a small, thin,
-- X-centred plate sitting 70% of the way up the base, which is where a clasp
-- meets a lid and is not a shape a hinge strap takes (a strap runs ALONG the
-- hinge, so it would be wide in X and short in Y, and there would be two).
local LOCK_PART_NAME = "Base_iron"

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
-- corners -- deliberately NOT Model:GetBoundingBox(), which returns an oriented
-- box whose axes can come back permuted relative to world space. Its OWN copy
-- rather than SlimeBuilder's or SignBuilder's, which is the house pattern here:
-- each builder carries this helper so it depends on nothing but its own asset.
-- (Requiring SlimeBuilder for it would also make every chest build wait on the
-- Slime asset, which is a coupling this file has no reason to have.)
--
-- Returns (minCorner, maxCorner) in WORLD space, reflecting the model's CURRENT
-- CFrame -- call it again after moving the model.
function ChestBuilder.worldAABB(model: Model): (Vector3, Vector3)
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

-- MEASURED, DERIVED ONCE AT LOAD -- NOT HARDCODED, same reasoning as
-- SlimeBuilder's UNIT_WIDTH_STUDS. Model:ScaleTo takes an ABSOLUTE scale, so
-- turning "12 studs tall" into a scale needs "how tall is this at scale 1".
-- The template's CURRENT height divided by its CURRENT scale reverses out the
-- scale it happened to be imported at. This chest arrives at ScaleFactor 1, but
-- the slime arrived at 15.83 and the sign at 5.96 -- reading GetScale() rather
-- than assuming 1 is what makes a re-import at any scale a no-op here.
local templateMin, templateMax = ChestBuilder.worldAABB(template)
local UNIT_HEIGHT_STUDS = (templateMax.Y - templateMin.Y) / template:GetScale()

-- The material half of "<group>_<material>". Returns "" for a part that does
-- not match the convention, which resolves to no entry in either config table
-- and so leaves that part exactly as the import left it.
local function materialKey(partName: string): string
	return string.match(partName, "^%a+_(%a+)$") or ""
end

-- FLATTEN THE IMPORTER'S WRAPPER NESTING (see the module header). Reparenting
-- a BasePart does NOT move it -- parts carry world CFrames and a Model applies
-- no transform to its children -- so every part stays exactly where the import
-- put it. GetDescendants returns a snapshot, so re-parenting while iterating is
-- safe.
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

-- Moves every flat part whose name starts with `prefix` into a new child Model.
-- Runs AFTER the scale, deliberately: Model:ScaleTo on a flat hierarchy is the
-- exact path SlimeBuilder and SignBuilder already use, and doing the grouping
-- first would ask it to descend into nested Models with their own scales for no
-- benefit. Nothing rescales the chest after this.
local function groupParts(model: Model, groupName: string, prefix: string, primaryPartName: string): Model
	local group = Instance.new("Model")
	group.Name = groupName
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and string.sub(child.Name, 1, #prefix) == prefix then
			child.Parent = group
		end
	end
	local primary = group:FindFirstChild(primaryPartName)
	if primary and primary:IsA("BasePart") then
		group.PrimaryPart = primary
	else
		group.PrimaryPart = group:FindFirstChildWhichIsA("BasePart")
	end
	group.Parent = model
	return group
end

-- WHICH WAY IS FORWARD, MEASURED RATHER THAN ASSUMED -- and this is the one
-- place this module disagrees with the brief it was built from (see REPORT.md).
--
-- The chest has to stand with its front toward the player, who always arrives
-- from +Z (they land on the platform and walk down-road toward the landmark;
-- the reveal's own `toward` is +Z for the same reason). It also has to hinge on
-- the edge AWAY from them, so the lid never opens into their face.
--
-- In the SAVED ASSET the clasp sits on the MINIMUM-Z face, so the mesh's front
-- is its own -Z -- the opposite of the source GLB the measurements came from,
-- which is the ordinary glTF-to-Roblox handedness flip. Rather than encode
-- either answer, this rotates the model 180 degrees about its own vertical
-- centre whenever the clasp is measured on the -Z side. The result is that
-- everything downstream can rely on "+Z is the front" being TRUE of what
-- build() returns, and a re-export that flips the axis back simply stops
-- triggering the rotation.
local function orientLockToFront(model: Model)
	local lock = model:FindFirstChild(LOCK_PART_NAME)
	if not (lock and lock:IsA("BasePart")) then
		return
	end
	local minCorner, maxCorner = ChestBuilder.worldAABB(model)
	local centre = (minCorner + maxCorner) / 2
	if (lock :: BasePart).Position.Z >= centre.Z then
		return
	end
	-- Rotate about the vertical axis through the model's own measured centre,
	-- not through its pivot: the pivot is a part's CFrame and sits off-centre,
	-- and spinning about it would translate the chest as well as turn it.
	local flip = CFrame.new(centre) * CFrame.Angles(0, math.pi, 0) * CFrame.new(-centre)
	model:PivotTo(flip * model:GetPivot())
end

-- THE LID'S HINGE, IN WORLD SPACE: the rear-bottom edge of the lid's own
-- measured bounds -- minimum Y, minimum Z (rear, since build() guarantees +Z is
-- the front), X at the group's centre since the axis runs along X and any point
-- on it describes the same line.
--
-- DERIVED, NOT STORED. The old parts chest stamped HingeY/HingeZ attributes at
-- build time; measuring the lid instead means the answer is correct for
-- wherever the chest currently stands and for whatever a re-export changes
-- about the lid's proportions, with no attribute to go stale. Call it after the
-- chest is in its final position.
function ChestBuilder.lidHinge(chest: Model): Vector3?
	local lid = chest:FindFirstChild(LID_GROUP_NAME)
	if not (lid and lid:IsA("Model")) then
		return nil
	end
	local minCorner, maxCorner = ChestBuilder.worldAABB(lid :: Model)
	return Vector3.new((minCorner.X + maxCorner.X) / 2, minCorner.Y, minCorner.Z)
end

-- The centre of the lid's TOP FACE, in world space -- where the reveal slime
-- rises from. Same derivation as the hinge, off the same measured bounds, so
-- the two cannot disagree about which model they are describing.
function ChestBuilder.lidTopCentre(chest: Model): Vector3?
	local lid = chest:FindFirstChild(LID_GROUP_NAME)
	if not (lid and lid:IsA("Model")) then
		return nil
	end
	local minCorner, maxCorner = ChestBuilder.worldAABB(lid :: Model)
	return Vector3.new((minCorner.X + maxCorner.X) / 2, maxCorner.Y, (minCorner.Z + maxCorner.Z) / 2)
end

-- Clones the template, flattens the wrappers, scales it to
-- TreasureConfig.CHEST_HEIGHT_STUDS tall (ABSOLUTE ScaleTo -- see
-- UNIT_HEIGHT_STUDS), turns it so its front faces +Z, groups it into Base/Lid,
-- and gives every part its configured colour and material. Returns the Model
-- UNPOSITIONED (wherever the template's own clone happens to sit) and
-- UNPARENTED -- the caller places and parents it.
function ChestBuilder.build(): Model
	local model = template:Clone()
	flatten(model)
	model:ScaleTo(TreasureConfig.CHEST_HEIGHT_STUDS / UNIT_HEIGHT_STUDS)
	orientLockToFront(model)

	for _, part in eachBasePart(model) do
		local key = materialKey(part.Name)
		local color = TreasureConfig.CHEST_MATERIAL_COLORS[key]
		if color then
			part.Color = color
		end
		local surface = TreasureConfig.CHEST_MATERIAL_SURFACES[key]
		if surface then
			part.Material = surface
		end
		-- Cleared so the configured colours are what actually shows. The saved
		-- asset ships no TextureID today, so this is defensive rather than
		-- corrective -- but a re-export WITH baked textures would otherwise tint
		-- every colour above by whatever the texture carries, and that is a
		-- confusing failure to diagnose from the outside.
		part.TextureID = ""
		part.Anchored = true
		-- WALKABLE-UP-TO, NOT WALK-THROUGH: every part collides. The chest is a
		-- solid object standing on a platform the player walks across, and the
		-- old parts chest collided too -- this keeps that. The nested shells
		-- (woodshade inside the planks inside the gold) each get their own hull,
		-- which costs a little and changes nothing, since all of them sit inside
		-- the outer shell that actually stops the player. Anchored means none of
		-- it can be pushed.
		--
		-- DO NOT ADD RenderFidelity OR CollisionFidelity HERE. Both require the
		-- Plugin capability and THROW when written from a server or client
		-- script ("the current thread cannot write '<name>'") -- they do not fail
		-- quietly, so one attempt takes the whole chest build down with it. See
		-- SlimeBuilder's own copy of this warning. Changing either means editing
		-- the parts in Studio and re-saving assets/Chest.rbxmx.
		part.CanCollide = true
	end

	local base = groupParts(model, BASE_GROUP_NAME, BASE_GROUP_NAME .. "_", BASE_PRIMARY_PART_NAME)
	groupParts(model, LID_GROUP_NAME, LID_GROUP_NAME .. "_", LID_PRIMARY_PART_NAME)

	-- The chest's own PrimaryPart is the base's, so GetPivot/PivotTo are exact
	-- for the caller placing it, and so there is one obvious BasePart to hang a
	-- ProximityPrompt on.
	model.PrimaryPart = base.PrimaryPart

	return model
end

return ChestBuilder
