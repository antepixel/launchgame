--!strict
-- Builds one slime VISUAL Model from the imported mesh template (see
-- assets/Slime.rbxmx, synced into ReplicatedStorage.Assets.Slime by
-- default.project.json) -- replaces the old flat-coloured placeholder cube/
-- ball (see the written report). PURE ASSEMBLY ONLY: clones the template,
-- scales it, colours the body, and hands back an unpositioned, unparented
-- Model. Every placement decision -- where it goes, which way it faces,
-- what surface it rests on -- belongs to the CALLER (PlayerProfile.luau's
-- spawnSlimeVisual, MapBuilder.server.luau's landmark). No road geometry, no
-- lane maths, nothing placement-specific lives in this file.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SlimeBuilder = {}

-- The template's own part names (see assets/Slime.rbxmx's own header): four
-- flat MeshParts, no wrapper Models. Only the body ever gets recoloured --
-- eye_dark/eye_white/blush keep whatever colour the template itself
-- carries (verified against the .rbxmx's own baked Color3uint8 values: they
-- came through the import exactly as authored -- 18,18,28 / 255,255,255 /
-- 222,66,114 -- so nothing here overrides them; if a future re-import ever
-- changes that, this is the one place to add an explicit corrective
-- assignment).
local BODY_PART_NAME = "slime"

local assetsFolder = ReplicatedStorage:WaitForChild("Assets")
local template = assetsFolder:WaitForChild("Slime") :: Model
local templateBody = template:WaitForChild(BODY_PART_NAME) :: MeshPart

-- MESH_FACE_AXIS -- DETERMINED FROM GEOMETRY, NOT ASSUMED (see the written
-- report): every part's CFrame in assets/Slime.rbxmx carries IDENTITY
-- rotation (R00..R22 = the identity matrix, for the body and all three face
-- parts alike), so world space and the template's own local space are the
-- same thing here -- comparing raw XML positions directly IS comparing them
-- in "the template's own unrotated local space." Measured eye_dark/
-- eye_white/blush positions minus the body's own CFrame position, all three:
--   eye_dark:  (-8.00,  0.58, -10.06)
--   eye_white: (-8.92,  2.12, -11.22)
--   blush:     (-7.52, -2.78,  -9.48)
-- Y varies only by normal vertical face-feature layout (eyes above centre,
-- blush below) and isn't a facing candidate. X and Z are BOTH consistently
-- negative and substantial for all three -- not a clean cardinal offset --
-- but Z is the larger component in every single one, by a consistent ~26%
-- (ratios 1.257 / 1.258 / 1.261 -- essentially identical across three
-- independently-placed parts, meaning this is one consistent skew, not
-- random per-feature styling). -Z is therefore the mesh's real face axis:
-- the dominant, nearest-cardinal direction, and -- usefully -- the SAME
-- axis Roblox's own CFrame.lookAt always aims at its target (a CFrame's
-- LookVector is always its own local -Z), so a plain CFrame.lookAt(pos, pos
-- + desiredWorldDirection) call, with no extra axis correction, already
-- points this mesh's face at desiredWorldDirection correctly.
-- CAVEAT, worth knowing about even though it isn't fixed here: the
-- consistent ~26%-of-Z secondary lean toward -X (roughly 38 degrees off a
-- pure -Z) is real and baked into the asset itself (identity rotation on
-- every part rules out "it's just rotated" as the explanation) -- a rigid
-- CFrame rotation applied by a caller can aim -Z exactly where it wants, but
-- can't straighten out that internal skew. The face will read a bit
-- off-centre from dead-on-target because of it; only a re-export of the
-- asset (or an explicit corrective pre-rotation added here, not done as
-- part of this pass) would remove it entirely.
--
-- CONCLUSION: the mesh's face axis is -Z. Callers (PlayerProfile.luau's
-- spawnSlimeVisual, MapBuilder.server.luau's landmark) rely on this by
-- simply calling CFrame.lookAt(pos, pos + desiredWorldDirection) -- no
-- extra axis-correction math needed here or there, since -Z-is-forward is
-- already exactly what that API does.

-- MEASURED, DERIVED ONCE AT LOAD -- NOT HARDCODED (see the written report):
-- Model:ScaleTo takes an ABSOLUTE scale, not a multiplier, so every build
-- needs to know "how many studs wide is the body at scale 1" to turn a
-- requested width in studs into the right absolute scale. templateBody.
-- Size.X is the body's CURRENT width, at whatever scale the template
-- happens to be imported at (template:GetScale()) -- dividing one by the
-- other reverses that back out to the width-at-scale-1 constant, computed
-- fresh from the live template every time this module loads. If the asset
-- is ever re-imported at a different scale (or the mesh itself changes),
-- this stays correct automatically -- nothing here hardcodes the studs-per-
-- scale-unit ratio itself.
local UNIT_WIDTH_STUDS = templateBody.Size.X / template:GetScale()

-- Every BasePart the AABB helper and the Anchored/CanCollide pass below
-- need to visit -- all four MeshParts, flat under the Model.
local function eachBasePart(model: Model): { BasePart }
	local parts: { BasePart } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

-- The 8 sign combinations for a box's own corners, relative to its center.
local CORNER_SIGNS = {
	Vector3.new(-1, -1, -1), Vector3.new(-1, -1, 1), Vector3.new(-1, 1, -1), Vector3.new(-1, 1, 1),
	Vector3.new(1, -1, -1), Vector3.new(1, -1, 1), Vector3.new(1, 1, -1), Vector3.new(1, 1, 1),
}

-- Explicit WORLD-AXIS AABB over every descendant BasePart's own 8
-- transformed corners -- deliberately NOT Model:GetBoundingBox(), which
-- returns an oriented bounding box whose axes can come back permuted
-- relative to world space rather than reliably world-axis-aligned (see the
-- written report). Callers use this to bottom-align a built (and already
-- positioned/rotated) model against a surface Y without needing to know
-- anything about the mesh's own internal pivot/origin offset. Returns
-- (minCorner, maxCorner) in WORLD space, reflecting the model's CURRENT
-- CFrame at call time -- call it again after moving the model if the answer
-- needs to reflect a new position.
function SlimeBuilder.worldAABB(model: Model): (Vector3, Vector3)
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

-- Clones the template, scales it to `widthStuds` wide (ABSOLUTE ScaleTo --
-- see UNIT_WIDTH_STUDS's own comment above), colours the body ONLY, and
-- makes sure every part is Anchored/non-colliding regardless of what the
-- template itself already had. Returns the Model UNPOSITIONED (wherever the
-- template's own clone happens to sit) and UNPARENTED -- the caller places
-- and parents it.
function SlimeBuilder.build(color: Color3, widthStuds: number): Model
	local model = template:Clone()
	model:ScaleTo(widthStuds / UNIT_WIDTH_STUDS)

	local body = model.PrimaryPart :: MeshPart
	body.Color = color

	for _, part in eachBasePart(model) do
		part.Anchored = true
		part.CanCollide = false
	end

	return model
end

return SlimeBuilder
