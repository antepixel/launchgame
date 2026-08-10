--!strict
-- DEV-ONLY tooling: renders every swing tier side by side, from the SAME
-- SwingBuilder.luau the real game uses -- see SwingBuilder.luau's own
-- written report for the refactor that made this possible (build() now
-- takes an explicit pivot part + parent per call, no module-level
-- singleton state, so more than one swing can exist at once).
--
-- WHY THIS FILE LIVES OUTSIDE src/: gallery.project.json includes this
-- script deliberately; default.project.json (the real game) syncs the
-- WHOLE src/ServerScriptService directory as one unit
-- ("$path": "src/ServerScriptService"), so anything placed inside it ships
-- automatically, with no per-file opt-out. Living outside src/ entirely is
-- what makes "must never ship" a structural guarantee rather than a
-- reminder to remember -- default.project.json cannot see this file at
-- all, regardless of Rojo version or config. See the written report.
--
-- No launching, no seat riding, no UI, no player logic, no persistence, no
-- remotes: this exists purely to look at and measure geometry, every
-- tiers at once, against the real 40-stud lane pitch, in one screenshot.
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local SwingBuilder = require(ServerScriptService.SwingBuilder)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LaunchConfig = require(ReplicatedStorage.Config.LaunchConfig)

-- DERIVED, not a literal (it used to be a hardcoded 11). The ladder went from
-- eleven tiers to ten and this file kept rendering an eleventh, which
-- SwingTierVisuals.forTier silently clamped -- so the gallery drew the top
-- swing twice and called the copy a tier. Reading the same array every other
-- consumer reads (PlayerProfile, ShopClient, DevPanelClient) means the gallery
-- cannot fall behind the ladder again.
local TIER_COUNT = #LaunchConfig.SWING_TIER_DISTANCE_SCALE
-- The REAL lane pitch (see the written report on swing lanes), not a
-- gallery-only convenience number -- this is exactly what makes a tier 7+
-- swing overflowing into a neighbour's lane visible directly in the
-- screenshot, instead of something you have to read off a printed width
-- and do arithmetic on.
local LANE_SPACING_STUDS = 40
local PIVOT_Z = 0

local baseplate = Workspace:WaitForChild("Baseplate") :: BasePart
local groundY = baseplate.Position.Y + baseplate.Size.Y / 2

local galleryFolder = Instance.new("Folder")
galleryFolder.Name = "SwingGallery"
galleryFolder.Parent = Workspace

-- ===== Lane boundary markers -- one thin strip at every 40-stud lane
-- edge: TIER_COUNT + 1 of them bracketing the TIER_COUNT lanes (a boundary
-- sits at pivotX +/- LANE_SPACING/2 for every pivot; adjacent lanes share
-- one). Purely visual, never read by anything else in this script -- if a
-- swing's own geometry crosses one of these in the screenshot, that IS the
-- overflow, no number-reading required. =====
for i = 0, TIER_COUNT do
	local boundaryX = (i - 0.5) * LANE_SPACING_STUDS
	local marker = Instance.new("Part")
	marker.Name = string.format("LaneBoundary%02d", i)
	marker.Anchored = true
	marker.CanCollide = false
	marker.Material = Enum.Material.Neon
	marker.Color = Color3.new(1, 1, 1)
	marker.Size = Vector3.new(0.5, 0.1, baseplate.Size.Z - 4)
	marker.Position = Vector3.new(boundaryX, groundY + 0.06, PIVOT_Z)
	marker.Parent = galleryFolder
end

-- ===== Explicit world-axis AABB -- REPLACES Model:GetExtentsSize()/
-- GetBoundingBox(). Both of those orient to the model's PrimaryPart when
-- one is set, and (per observed Studio behaviour, NOT the "falls back to
-- world axes" the docs imply) to some other internal reference frame when
-- it isn't -- which part ends up supplying that frame differs by tier, so
-- the W/H/D axes those calls report get silently PERMUTED, differently
-- per tier. See the written report.
--
-- This instead walks every descendant BasePart, transforms all 8 corners
-- of ITS OWN oriented box by ITS OWN CFrame into world space, and takes
-- the min/max across every one of those world-space corners. There is no
-- "which part's rotation do we orient to" question to get wrong, by
-- construction -- W is always the X extent, H is always Y, D is always Z,
-- regardless of PrimaryPart, regardless of how any individual part inside
-- the model happens to be rotated.
--
-- Runs IDENTICALLY under Lune and Studio: rbxshim.luau (the dev Lune shim
-- used to iterate on this file outside Studio) implements GetDescendants,
-- IsA("BasePart"), CFrame, and Size the same way real Roblox does, so this
-- exact function -- not a second hand-rolled formula living only in the
-- shim -- is what both platforms execute. Studio and the shim can no
-- longer disagree about W/H/D, because they're now running the same code
-- against the same per-part CFrame/Size data instead of each computing
-- its own notion of "bounding box."
local CORNER_SIGNS = {
	Vector3.new(-1, -1, -1),
	Vector3.new(-1, -1, 1),
	Vector3.new(-1, 1, -1),
	Vector3.new(-1, 1, 1),
	Vector3.new(1, -1, -1),
	Vector3.new(1, -1, 1),
	Vector3.new(1, 1, -1),
	Vector3.new(1, 1, 1),
}

local function measureWorldAABB(model: Model): (Vector3, Vector3)
	local minPoint = Vector3.new(math.huge, math.huge, math.huge)
	local maxPoint = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			local part = descendant :: BasePart
			local cf = part.CFrame
			local half = part.Size / 2
			for _, sign in CORNER_SIGNS do
				local corner = cf * Vector3.new(half.X * sign.X, half.Y * sign.Y, half.Z * sign.Z)
				minPoint = Vector3.new(
					math.min(minPoint.X, corner.X),
					math.min(minPoint.Y, corner.Y),
					math.min(minPoint.Z, corner.Z)
				)
				maxPoint = Vector3.new(
					math.max(maxPoint.X, corner.X),
					math.max(maxPoint.Y, corner.Y),
					math.max(maxPoint.Z, corner.Z)
				)
			end
		end
	end
	return minPoint, maxPoint
end

type Measurement = {
	tier: number,
	width: number,
	height: number,
	depth: number,
	ratio: number,
	minX: number,
	maxX: number,
	minY: number,
	topY: number,
}
local measurements: { Measurement } = {}

print("===== Swing Gallery: measured bounding boxes (explicit world-axis AABB) =====")

-- ===== One swing per tier, 1..TIER_COUNT left to right, each built from the exact
-- SwingBuilder.build the real game calls -- not a copy, not a fork. Each
-- gets its OWN pivot Part and its OWN Model (a Model, not a Folder, so the
-- AABB below walks the actual parts SwingBuilder created, never a formula
-- reconstruction of them -- if SwingBuilder's own geometry ever changes,
-- these numbers change with it automatically). =====
for tier = 1, TIER_COUNT do
	local pivotX = (tier - 1) * LANE_SPACING_STUDS

	local pivot = Instance.new("Part")
	pivot.Name = string.format("Pivot%02d", tier)
	pivot.Anchored = true
	pivot.CanCollide = false
	pivot.Transparency = 1
	pivot.Size = Vector3.new(2, 0.2, 2)
	pivot.Position = Vector3.new(pivotX, groundY, PIVOT_Z)
	pivot.Parent = galleryFolder

	local swingModel = Instance.new("Model")
	swingModel.Name = string.format("Swing%02d", tier)
	swingModel.Parent = galleryFolder

	SwingBuilder.build(tier, pivot, swingModel)

	-- ===== DIAGNOSTIC ONLY, tiers 1/5/top -- NOT used for the measurement
	-- below. Prints swingModel's own PrimaryPart (expected nil: neither
	-- this script nor SwingBuilder.build ever sets it -- only the SEPARATE
	-- nested SwingSeat model gets a PrimaryPart, and that's a different
	-- Model than swingModel) and what Model:GetBoundingBox() -- the OLD,
	-- now-unused API -- reports as its rotation basis (XVector/YVector/
	-- ZVector). Run this in real Studio and compare against the shim's own
	-- printout: the shim's GetBoundingBox always reports identity rotation
	-- (it's a straight world-axis AABB by construction -- see rbxshim.luau)
	-- and nil PrimaryPart at every tier; if Studio's XVector/YVector/
	-- ZVector are NOT (1,0,0)/(0,1,0)/(0,0,1) at some tier despite
	-- PrimaryPart also printing nil there, that CONFIRMS the axis-
	-- permutation bug is real and is NOT simply "PrimaryPart is set" --
	-- it's Studio's undocumented no-PrimaryPart fallback choosing some
	-- other reference frame instead of true world axes. =====
	if tier == 1 or tier == 5 or tier == TIER_COUNT then
		local diagnosticCFrame = swingModel:GetBoundingBox()
		local primaryPartName = if swingModel.PrimaryPart then swingModel.PrimaryPart.Name else "nil"
		print(string.format(
			"Tier %2d DIAGNOSTIC: PrimaryPart=%s  GetBoundingBox rotation X=(%.3f,%.3f,%.3f) Y=(%.3f,%.3f,%.3f) Z=(%.3f,%.3f,%.3f)",
			tier,
			primaryPartName,
			diagnosticCFrame.XVector.X, diagnosticCFrame.XVector.Y, diagnosticCFrame.XVector.Z,
			diagnosticCFrame.YVector.X, diagnosticCFrame.YVector.Y, diagnosticCFrame.YVector.Z,
			diagnosticCFrame.ZVector.X, diagnosticCFrame.ZVector.Y, diagnosticCFrame.ZVector.Z
		))
	end

	-- MEASURED, not computed from any formula -- real per-part CFrame/Size
	-- queries against the parts SwingBuilder actually created for THIS
	-- tier, just now, folded through the explicit world-axis AABB above.
	-- Named IMMEDIATELY by axis (width = X = beam span, height = Y =
	-- vertical, depth = Z = leg splay) so every consumer below reads
	-- `width`/`height`/`depth` by NAME, never `size.X`/`size.Y`/`size.Z`
	-- positionally.
	local minPoint, maxPoint = measureWorldAABB(swingModel)
	local width = maxPoint.X - minPoint.X
	local height = maxPoint.Y - minPoint.Y
	local depth = maxPoint.Z - minPoint.Z
	local ratio = if height > 0 then width / height else 0

	local measurement: Measurement = {
		tier = tier,
		width = width,
		height = height,
		depth = depth,
		ratio = ratio,
		minX = minPoint.X,
		maxX = maxPoint.X,
		minY = minPoint.Y,
		topY = maxPoint.Y,
	}
	table.insert(measurements, measurement)

	print(string.format(
		"Tier %2d: W=%6.2f  H=%6.2f  D=%6.2f  W:H=%.2f",
		tier, width, height, depth, ratio
	))

	-- ===== Floating readout -- tier, MEASURED W x H x D, MEASURED W:H
	-- ratio. Every number on this label comes from `width`/`height`/
	-- `depth`/`ratio` above (the SAME AABB just measured), never
	-- recomputed from SwingTierVisuals scale or any other formula.
	--
	-- Two fixes over the previous version, both driven by the same
	-- problem: at gallery viewing distance the labels piled into an
	-- unreadable stack, worse toward the high tiers.
	--   1. STAGGER: alternate tiers sit at a higher offset above their own
	--      topY than their neighbours, so tier N and tier N+1 never share
	--      a label Y -- true regardless of how close two tiers' own
	--      topY values happen to land.
	--   2. SCALE, not Offset: BillboardGui.Size's OFFSET component is in
	--      SCREEN PIXELS -- a fixed apparent size regardless of camera
	--      distance, same as a player nametag. That's exactly why the
	--      previous (Offset-sized) labels completely covered the swings at
	--      the far framing: every label rendered the same pixel size no
	--      matter how far back the camera pulled to fit every tier in
	--      frame. Using the SCALE component instead ties the label's real
	--      on-screen size to labelAnchor's own Size (in STUDS), which DOES
	--      shrink/grow under normal perspective with camera distance, same
	--      as the swing it's labelling -- so labelAnchor is sized off this
	--      tier's own MEASURED width (not a scale constant), and the
	--      label reads at a size proportioned to that swing specifically,
	--      at any camera distance.
	-- =====
	local LABEL_BASE_GAP_STUDS = 6
	local LABEL_STAGGER_STEP_STUDS = 8
	local staggerExtra = if tier % 2 == 0 then LABEL_STAGGER_STEP_STUDS else 0
	local labelY = measurement.topY + LABEL_BASE_GAP_STUDS + staggerExtra

	-- RETUNED (see the written report): sizing the adornee to
	-- measurement.width and the billboard to a FRACTION (0.6) of Scale
	-- undershot badly -- Scale's relationship to its adornee's real Size
	-- isn't the simple "1.0 = adornee's full extent, linear below that"
	-- this assumed, so 0.6 came out too small to read at any distance.
	-- Sidesteps that uncertainty entirely now: labelAnchor's own Size IS
	-- the exact real-world stud dimensions the label should render at
	-- (computed directly from measurement.width, not a mystery constant
	-- multiplied through a possibly-nonlinear Scale mapping), and the
	-- billboard's Scale is exactly (1, 1) -- "render at exactly my
	-- adornee's real size," the one Scale value that cannot be
	-- ambiguous regardless of the exact conversion Roblox otherwise
	-- applies. Still shrinks/grows correctly with camera distance (real
	-- Vector3 studs, normal perspective), same reason Scale was chosen
	-- over Offset in the first place.
	local LABEL_WIDTH_FRACTION_OF_SWING = 0.8
	local labelWidthStuds = measurement.width * LABEL_WIDTH_FRACTION_OF_SWING
	local labelHeightStuds = labelWidthStuds * (90 / 220)

	local labelAnchor = Instance.new("Part")
	labelAnchor.Name = "LabelAnchor"
	labelAnchor.Anchored = true
	labelAnchor.CanCollide = false
	labelAnchor.Transparency = 1
	labelAnchor.Size = Vector3.new(labelWidthStuds, labelHeightStuds, 1)
	labelAnchor.Position = Vector3.new(pivotX, labelY, PIVOT_Z)
	labelAnchor.Parent = galleryFolder

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "MeasurementLabel"
	billboard.Size = UDim2.fromScale(1, 1)
	billboard.AlwaysOnTop = true
	billboard.Parent = labelAnchor

	local background = Instance.new("Frame")
	background.BackgroundColor3 = Color3.new(0, 0, 0)
	background.BackgroundTransparency = 0.25
	background.BorderSizePixel = 0
	background.Size = UDim2.fromScale(1, 1)
	background.Parent = billboard

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.5
	label.Text = string.format(
		"Tier %d\nW %.1f  H %.1f  D %.1f\nW:H %.2f",
		tier, width, height, depth, ratio
	)
	label.Parent = background
end

-- ===== Overflow summary -- reuses the SAME measured `width` from above,
-- compared against the real lane width, nothing recomputed. =====
print("===== Tiers exceeding the 40-stud lane width =====")
local anyOverflow = false
for _, measurement in measurements do
	local overflow = measurement.width - LANE_SPACING_STUDS
	if overflow > 0 then
		anyOverflow = true
		print(string.format("Tier %2d: %.2f studs wide -- overflows by %.2f studs", measurement.tier, measurement.width, overflow))
	end
end
if not anyOverflow then
	print("(none)")
end

-- ===== Camera framing -- derived from the ACTUAL measured world AABB of
-- the built row (every gallery swing's real minX/maxX/minY/topY above),
-- not assumed fractions of it. Both cameras are built the same way:
--   - eye X = the row's true centre X (average of the row's own min/max X,
--     not a guess)
--   - eye Y = the row's true MID height (average of the row's own min/max
--     Y) -- and the look-AT target uses the exact same Y, so the camera is
--     dead level (no downward tilt) by construction, not by picking two
--     fractions (0.55 vs 0.4) that happened to differ.
--   - eye Z = pulled back along +Z (matching the LaunchConfig/
--     RunwayGeometry flight-direction convention used elsewhere) far
--     enough that the row's full WIDTH fits inside the camera's
--     HORIZONTAL field of view, not its vertical one -- Roblox's
--     Camera.FieldOfView is a VERTICAL angle, so fitting a horizontal
--     extent (width) against the vertical half-angle understates how much
--     horizontal room a widescreen viewport actually has, which is why
--     the previous version's framing came out too far back (row reads
--     small). The horizontal half-angle here is derived from the vertical
--     one via a reference 16:9 aspect ratio (Studio's common default;
--     retune ASSUMED_ASPECT_RATIO if your viewport is materially
--     different).
--   - distance also checks the HEIGHT fit against the vertical half-angle,
--     and takes whichever (width or height) needs more room, plus a 15%
--     margin so nothing clips the frame edge.
-- =====
local function rowAABB(list: { Measurement }): (number, number, number, number)
	local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
	for _, measurement in list do
		minX = math.min(minX, measurement.minX)
		maxX = math.max(maxX, measurement.maxX)
		minY = math.min(minY, measurement.minY)
		maxY = math.max(maxY, measurement.topY)
	end
	return minX, maxX, minY, maxY
end

local VERTICAL_FOV_DEGREES = 70 -- Roblox Studio's default Camera.FieldOfView (vertical)
local ASSUMED_ASPECT_RATIO = 16 / 9 -- viewport width:height used to derive the horizontal FOV
local FRAME_MARGIN = 1.15

local VERTICAL_HALF_FOV_RADIANS = math.rad(VERTICAL_FOV_DEGREES / 2)
local HORIZONTAL_HALF_FOV_RADIANS = math.atan(math.tan(VERTICAL_HALF_FOV_RADIANS) * ASSUMED_ASPECT_RATIO)

local function frameRow(list: { Measurement }): (Vector3, Vector3)
	local minX, maxX, minY, maxY = rowAABB(list)
	local centerX = (minX + maxX) / 2
	local midY = (minY + maxY) / 2
	local halfWidth = (maxX - minX) / 2
	local halfHeight = (maxY - minY) / 2

	local distanceForWidth = halfWidth / math.tan(HORIZONTAL_HALF_FOV_RADIANS)
	local distanceForHeight = halfHeight / math.tan(VERTICAL_HALF_FOV_RADIANS)
	local cameraDistance = math.max(distanceForWidth, distanceForHeight) * FRAME_MARGIN

	local cameraPosition = Vector3.new(centerX, midY, PIVOT_Z + cameraDistance)
	local cameraTarget = Vector3.new(centerX, midY, PIVOT_Z)
	return cameraPosition, cameraTarget
end

local function buildCameraMarker(name: string, position: Vector3, target: Vector3)
	local marker = Instance.new("Part")
	marker.Name = name
	marker.Anchored = true
	marker.CanCollide = false
	marker.Material = Enum.Material.Neon
	marker.Color = Color3.fromRGB(255, 60, 60)
	marker.Shape = Enum.PartType.Ball
	marker.Size = Vector3.new(2, 2, 2)
	marker.CFrame = CFrame.lookAt(position, target)
	marker.Parent = galleryFolder
end

-- FAR camera: every tier, for comparing silhouettes side by side.
local farPosition, farTarget = frameRow(measurements)
buildCameraMarker("GalleryCameraMarkerFar", farPosition, farTarget)

-- CLOSE camera: the top three tiers only, for judging one swing's own detail.
local closeTierMeasurements: { Measurement } = {}
for _, measurement in measurements do
	if measurement.tier >= 9 then
		table.insert(closeTierMeasurements, measurement)
	end
end
local closePosition, closeTarget = frameRow(closeTierMeasurements)
buildCameraMarker("GalleryCameraMarkerClose", closePosition, closeTarget)

-- The exact, reproducible framing CFrames -- printed here (not hardcoded as
-- a comment) because they depend on THIS run's measured extents, not a
-- fixed constant. Paste either printed line straight into Studio's command
-- bar to snap the viewport camera to that framing; the two
-- GalleryCameraMarker parts (red balls, above) hold the same CFrames in
-- their own Properties panels if you'd rather select-and-align instead.
print("===== FAR camera (all tiers) -- paste into the Studio command bar =====")
print(string.format(
	"game.Workspace.CurrentCamera.CFrame = CFrame.lookAt(Vector3.new(%.2f, %.2f, %.2f), Vector3.new(%.2f, %.2f, %.2f))",
	farPosition.X, farPosition.Y, farPosition.Z,
	farTarget.X, farTarget.Y, farTarget.Z
))
print(string.format("===== CLOSE camera (tiers %d-%d only) -- paste into the Studio command bar =====", TIER_COUNT - 2, TIER_COUNT))
print(string.format(
	"game.Workspace.CurrentCamera.CFrame = CFrame.lookAt(Vector3.new(%.2f, %.2f, %.2f), Vector3.new(%.2f, %.2f, %.2f))",
	closePosition.X, closePosition.Y, closePosition.Z,
	closeTarget.X, closeTarget.Y, closeTarget.Z
))
