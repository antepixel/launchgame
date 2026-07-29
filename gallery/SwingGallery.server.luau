--!strict
-- DEV-ONLY tooling: renders all 11 swing tiers side by side, from the SAME
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
-- remotes: this exists purely to look at and measure geometry, all 11
-- tiers at once, against the real 40-stud lane pitch, in one screenshot.
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local SwingBuilder = require(ServerScriptService.SwingBuilder)

local TIER_COUNT = 11
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

type Measurement = {
	tier: number,
	width: number,
	height: number,
	depth: number,
	ratio: number,
	minX: number,
	maxX: number,
	topY: number,
}
local measurements: { Measurement } = {}

print("===== Swing Gallery: measured bounding boxes (Model:GetExtentsSize) =====")

-- ===== Eleven swings, tier 1..11 left to right, each built from the exact
-- SwingBuilder.build the real game calls -- not a copy, not a fork. Each
-- gets its OWN pivot Part and its OWN Model (a Model, not a Folder, so
-- GetExtentsSize/GetBoundingBox below are real Roblox measurements of the
-- actual parts SwingBuilder created, never a formula reconstruction of
-- them -- if SwingBuilder's geometry ever changes, these numbers change
-- with it automatically). =====
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

	-- MEASURED, not computed from any formula -- real Roblox geometry
	-- queries against the parts SwingBuilder actually created for THIS
	-- tier, just now. Named IMMEDIATELY by axis (width = X = beam span,
	-- height = Y = vertical, depth = Z = leg splay) so every consumer below
	-- reads `width`/`height`/`depth` by NAME, never `size.X`/`size.Y`/
	-- `size.Z` positionally -- a previous pass printed the raw components
	-- in a fixed X,Y,Z order but labelled them W/H/D, which reads correctly
	-- ONLY if a viewer already knows X=width/Y=height/Z=depth; this makes
	-- that mapping the one and only place it's ever stated, instead of an
	-- assumption repeated at every print/label call site.
	local size = swingModel:GetExtentsSize()
	local width, height, depth = size.X, size.Y, size.Z
	local boundsCFrame = swingModel:GetBoundingBox()
	-- W:H from the REAL width and height above, not "the first two
	-- components" -- if width/height are ever reassigned from different
	-- axes (e.g. GetExtentsSize's own convention ever changed), this still
	-- computes the right ratio, because it never looks at .X/.Y again.
	local ratio = if height > 0 then width / height else 0

	local measurement: Measurement = {
		tier = tier,
		width = width,
		height = height,
		depth = depth,
		ratio = ratio,
		minX = boundsCFrame.Position.X - width / 2,
		maxX = boundsCFrame.Position.X + width / 2,
		topY = boundsCFrame.Position.Y + height / 2,
	}
	table.insert(measurements, measurement)

	print(string.format(
		"Tier %2d: W=%6.2f  H=%6.2f  D=%6.2f  W:H=%.2f",
		tier, width, height, depth, ratio
	))

	-- ===== Floating readout -- tier, MEASURED W x H x D, MEASURED W:H
	-- ratio. Every number on this label comes from `width`/`height`/
	-- `depth`/`ratio` above (the SAME GetExtentsSize call just printed),
	-- never recomputed from SwingTierVisuals scale or any other formula --
	-- if SwingBuilder's own geometry ever drifts from what this label says,
	-- that means SwingBuilder changed, not this label going stale. =====
	local labelAnchor = Instance.new("Part")
	labelAnchor.Name = "LabelAnchor"
	labelAnchor.Anchored = true
	labelAnchor.CanCollide = false
	labelAnchor.Transparency = 1
	labelAnchor.Size = Vector3.new(1, 1, 1)
	labelAnchor.Position = Vector3.new(pivotX, measurement.topY + 6, PIVOT_Z)
	labelAnchor.Parent = galleryFolder

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "MeasurementLabel"
	billboard.Size = UDim2.new(0, 220, 0, 90)
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

-- ===== Camera marker -- positioned from the ACTUAL measured overall
-- extent above (every gallery swing's real minX/maxX/topY), not a guess,
-- so moving the viewport camera to this marker's CFrame exactly reproduces
-- "all 11 swings, head-on, fully in frame" every time this script runs,
-- regardless of any future geometry change. Framed along +Z looking toward
-- -Z (the same flight-direction convention LaunchConfig/RunwayGeometry use
-- elsewhere in the real game), pulled back far enough for a ~70-degree
-- vertical FOV (Roblox Studio's default) to fit BOTH the full measured
-- width and the tallest swing's height, whichever needs more room, plus a
-- 15% margin. =====
local overallMinX, overallMaxX, overallMaxTopY = math.huge, -math.huge, -math.huge
for _, measurement in measurements do
	overallMinX = math.min(overallMinX, measurement.minX)
	overallMaxX = math.max(overallMaxX, measurement.maxX)
	overallMaxTopY = math.max(overallMaxTopY, measurement.topY)
end

local galleryCenterX = (overallMinX + overallMaxX) / 2
local galleryWidth = overallMaxX - overallMinX
local HALF_FOV_RADIANS = math.rad(35) -- Roblox Studio's default vertical FOV is 70 degrees
local distanceForWidth = (galleryWidth / 2) / math.tan(HALF_FOV_RADIANS)
local distanceForHeight = overallMaxTopY / math.tan(HALF_FOV_RADIANS)
local cameraDistance = math.max(distanceForWidth, distanceForHeight) * 1.15
local cameraPosition = Vector3.new(galleryCenterX, overallMaxTopY * 0.55, PIVOT_Z + cameraDistance)
local cameraTarget = Vector3.new(galleryCenterX, overallMaxTopY * 0.4, PIVOT_Z)
local cameraCFrame = CFrame.lookAt(cameraPosition, cameraTarget)

local cameraMarker = Instance.new("Part")
cameraMarker.Name = "GalleryCameraMarker"
cameraMarker.Anchored = true
cameraMarker.CanCollide = false
cameraMarker.Material = Enum.Material.Neon
cameraMarker.Color = Color3.fromRGB(255, 60, 60)
cameraMarker.Shape = Enum.PartType.Ball
cameraMarker.Size = Vector3.new(2, 2, 2)
cameraMarker.CFrame = cameraCFrame
cameraMarker.Parent = galleryFolder

-- The exact, reproducible framing CFrame -- printed here (not hardcoded as
-- a comment) because it depends on THIS run's measured gallery extent, not
-- a fixed constant. Paste the printed line straight into Studio's command
-- bar to snap the viewport camera to the same framing every time; the
-- GalleryCameraMarker part (a red ball, above) shows/holds the same CFrame
-- in its own Properties panel if you'd rather select-and-align instead.
print("===== Camera framing (paste into the Studio command bar) =====")
print(string.format(
	"game.Workspace.CurrentCamera.CFrame = CFrame.lookAt(Vector3.new(%.2f, %.2f, %.2f), Vector3.new(%.2f, %.2f, %.2f))",
	cameraPosition.X, cameraPosition.Y, cameraPosition.Z,
	cameraTarget.X, cameraTarget.Y, cameraTarget.Z
))
