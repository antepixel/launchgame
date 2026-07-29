--!strict
-- Builds the rainbow-road runway once, at server startup: a strip of narrow,
-- fully-saturated bands running crosswise under the flight path, with one
-- distance number floating just above each band, readable from above AND
-- from far down the road. Purely decorative -- this script only ever CREATES
-- new Workspace instances and never reads or writes anything the swing/
-- launch/scoring logic depends on, so it cannot affect them.
--
-- GENERATED, NOT HAND-AUTHORED: default.project.json only ever changes for the
-- Baseplate (shrunk/widened to just the swing's support platform, then
-- lengthened/reverted alongside a band-length experiment -- see the written
-- reports from those passes). The bands and signs themselves are a repeated,
-- formulaic set of parts, which is exactly what a loop is for rather than
-- hand-copying dozens of near-identical JSON blocks.
--
-- TWO PARTS PER BAND, NOT ONE (see the written report): the coloured SCORING
-- band (band.Size/Position, CanCollide -- this is what LaunchServer's
-- bandLuckForLandingZ actually measures against, completely unaffected by
-- anything in this file) and a separate, much bigger, floating SIGN that
-- carries the actual number. A number big enough to read at a distance needs
-- far more room than a single RUNWAY_BAND_LENGTH_STUDS band provides, and
-- growing that constant to give it that room means re-deriving
-- DISTANCE_PER_MULTIPLIER and the swing-to-runway gap right along with it
-- (see the written reports -- this has now happened twice). Splitting the
-- number onto its own part decouples "how big can the label be" from "how
-- long is a scoring band" -- SIGN_LENGTH below still scales WITH band depth
-- when that changes, but the two are independent knobs, not the same one.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LaunchConfig = require(ReplicatedStorage.Config.LaunchConfig)
local RunwayGeometry = require(ReplicatedStorage.Config.RunwayGeometry)
local LuckCurve = require(ReplicatedStorage.Config.LuckCurve)

local swingPivot = Workspace:WaitForChild("SwingPivot") :: BasePart

-- The flight always travels in -Z (see LaunchServer.server.luau's
-- launchDirection) -- a fixed fact about this world's layout, not recomputed
-- here. The runway picks up exactly where the (shrunk/widened) support platform
-- ends -- see RunwayGeometry.luau, also read by LaunchServer so the band a
-- landing scores against is always the band physically built here.
local RUNWAY_START_Z = RunwayGeometry.RUNWAY_START_Z
local RUNWAY_X = swingPivot.Position.X
-- Now the SAME single source of truth LaunchServer's trajectoryPosition
-- also reads (see RunwayGeometry.luau), not an independently-computed copy.
local RUNWAY_TOP_Y = RunwayGeometry.RUNWAY_TOP_Y

local runwayFolder = Instance.new("Folder")
runwayFolder.Name = "Runway"
runwayFolder.Parent = Workspace

-- Colours repeat every COLOUR_CYCLE_LENGTH bands rather than spreading one hue
-- rotation across the whole (~74-band) road -- a single rotation over that
-- many bands would put neighbouring bands within a hue or two of each other,
-- reading as a slow gradient instead of a sequence of distinct colours. Five
-- repeating hues keeps every band visually distinct from its immediate
-- neighbours no matter how long the generated curve gets.
local COLOUR_CYCLE_LENGTH = 5

-- ===== Sign geometry =====
-- BUG FIX (climbing height, see the written report): the PREVIOUS pass
-- staggered each sign's elevation by `(i % SIGN_HEIGHT_TIERS) * SIGN_TIER_GAP`
-- -- a band INDEX, multiplied by a gap, used directly as a Y offset -- to
-- keep signs longer than the 20-stud band spacing from visually overlapping
-- their immediate neighbours. That formula was doing exactly what it said:
-- climbing 3 steps higher band-by-band, then resetting every 4th band (the
-- modulo wrapping back to 0) -- which reads as a glitch, not a design, when
-- you're actually flying past it. Every sign now sits at the SAME single
-- fixed height -- no index anywhere feeds into Y any more. Overlap between
-- neighbouring signs is now simply ALLOWED (see SIGN_LENGTH below) rather
-- than engineered away.
local SIGN_CLEARANCE = 0.3 -- studs above the road; just enough to not z-fight with the band's own top surface
-- The sign's own length along the flight direction (Z) -- MUCH bigger than a
-- single RUNWAY_BAND_LENGTH_STUDS band, which is the whole point: this is
-- what actually makes the number big, decoupled from the scoring band's own
-- length. Not sized to avoid overlapping neighbours -- a big number
-- spilling into the next band's floor-space reads better than a small,
-- fully-contained one that's unreadable from a distance. Tied to a multiple
-- of RUNWAY_BAND_LENGTH_STUDS (4x) rather than a bare constant so a deeper
-- band automatically gives the sign more room too -- this pass's band-depth
-- doubling (20 -> 40 studs) is what pushed this from the previous flat 100
-- up to 160, further increasing the text size on top of that as asked for,
-- not just carrying the old absolute number forward unchanged.
local SIGN_LENGTH = 4 * LaunchConfig.RUNWAY_BAND_LENGTH_STUDS

-- Same rotation-exploiting shape as the previous pass (see the written
-- reports): the sign's PRE-rotation box has to stay capped to SIGN_LENGTH on
-- the axis that becomes its footprint HEIGHT after the 90-degree rotation
-- below, while the OTHER axis becomes the footprint WIDTH and has the whole
-- (240-stud) road to work with. Long spelled-out values ("100,000") are
-- WIDTH-bound before they're HEIGHT-bound, which is why RUNWAY_WIDTH_STUDS
-- being wide matters at least as much as SIGN_LENGTH for the longest values.
local LENGTH_MARGIN_FRACTION = 0.9
local LABEL_LENGTH_FRACTION = LENGTH_MARGIN_FRACTION * (SIGN_LENGTH / LaunchConfig.RUNWAY_WIDTH_STUDS)
local WIDTH_COVERAGE_FRACTION = 0.85
local LABEL_WIDTH_SCALE = WIDTH_COVERAGE_FRACTION * (LaunchConfig.RUNWAY_WIDTH_STUDS / SIGN_LENGTH)

-- PixelsPerStud for the SIGN's SurfaceGui (separate from the scoring band,
-- which carries no SurfaceGui at all). The sign's canvas is big in stud terms
-- (240 x 160), so the density is kept low (10) to keep the actual pixel
-- canvas -- and so the rendering cost -- reasonable rather than growing with
-- the physical size. Heavy, bold text doesn't need fine detail, so this
-- stays crisp.
local SIGN_PIXELS_PER_STUD = 10

for i = 0, #LuckCurve.VALUES - 1 do
	-- ===== The scoring band: geometry/position UNCHANGED from every
	-- previous pass. This is what LaunchServer's bandLuckForLandingZ
	-- actually measures a landing against. =====
	local band = Instance.new("Part")
	band.Name = string.format("RunwayBand%02d", i + 1)
	band.Anchored = true
	band.CanCollide = true
	-- Enum.Material.Plastic -- the classic "studded" Roblox surface texture
	-- (the visible grid of little stud bumps), as asked for -- SWAPPED from
	-- SmoothPlastic, which deliberately has NO bump map (that's what made it
	-- the "truest colour" choice before). Plastic's bump/shading DOES read
	-- very slightly less flat/saturated than SmoothPlastic under directional
	-- lighting -- see the written report -- but Color3.fromHSV(hue, 1, 1)
	-- (maximum saturation and value, unchanged below) is still the most
	-- intense version of each hue Roblox can render, so the colours stay
	-- bright and clearly distinct; only the very flattest, poster-like read
	-- SmoothPlastic gave is gone.
	band.Material = Enum.Material.Plastic
	band.Size = Vector3.new(LaunchConfig.RUNWAY_WIDTH_STUDS, 1, LaunchConfig.RUNWAY_BAND_LENGTH_STUDS)

	local centerZ = RUNWAY_START_Z - (i + 0.5) * LaunchConfig.RUNWAY_BAND_LENGTH_STUDS
	band.Position = Vector3.new(RUNWAY_X, RUNWAY_TOP_Y - band.Size.Y / 2, centerZ)

	-- FULL SATURATION: Color3.fromHSV(hue, 1, 1) is the purest, most intense
	-- version of every hue there is -- saturation 1 means no white mixed in (no
	-- pastel), value 1 means no black mixed in (no muddy/dark). Band i gets a
	-- single flat, solid colour -- not a gradient within a band -- so each one
	-- reads as a distinct band; the hue itself repeats every
	-- COLOUR_CYCLE_LENGTH bands (see above) instead of spanning the full road.
	local hue = (i % COLOUR_CYCLE_LENGTH) / COLOUR_CYCLE_LENGTH
	band.Color = Color3.fromHSV(hue, 1, 1)
	band.Parent = runwayFolder

	-- ===== The sign: one per band, floating flat just above its own band,
	-- all at the SAME height (see SIGN_CLEARANCE above). =====
	local luck = LuckCurve.VALUES[i + 1]

	local sign = Instance.new("Part")
	sign.Name = string.format("RunwaySign%02d", i + 1)
	sign.Anchored = true
	sign.CanCollide = false
	-- Fully invisible -- only the text (set below) is ever seen. No background
	-- plate to read as clutter; the number just floats above the road.
	sign.Transparency = 1
	sign.Size = Vector3.new(LaunchConfig.RUNWAY_WIDTH_STUDS, 0.2, SIGN_LENGTH)
	sign.Position = Vector3.new(RUNWAY_X, RUNWAY_TOP_Y + SIGN_CLEARANCE, centerZ)
	sign.Parent = runwayFolder

	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = "DistanceLabel"
	surfaceGui.Face = Enum.NormalId.Top
	surfaceGui.LightInfluence = 0
	surfaceGui.PixelsPerStud = SIGN_PIXELS_PER_STUD
	surfaceGui.Parent = sign

	-- Readable from the chase camera (behind and above, looking forward and
	-- down -- see LaunchClient.client.luau); Rotation = 90 is the confirmed fix
	-- for this face's default orientation from the previous pass -- untouched,
	-- orientation was never the problem. Centered on the sign, sized so the
	-- ROTATED footprint spans most of the road's width without overflowing
	-- SIGN_LENGTH. Plain white, no outline (previously a heavy black stroke --
	-- removed as asked; TextStrokeTransparency = 1 is the "no stroke" value).
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(LABEL_LENGTH_FRACTION, LABEL_WIDTH_SCALE)
	label.Rotation = 90
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 1
	label.Text = LuckCurve.formatLuck(luck)
	label.Parent = surfaceGui
end
