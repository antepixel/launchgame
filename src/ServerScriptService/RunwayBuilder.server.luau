--!strict
-- Builds the rainbow-road runway once, at server startup: a strip of narrow,
-- fully-saturated bands running crosswise under the flight path, with one
-- distance number per band, laid flat on top, readable from above. Purely
-- decorative -- this script only ever CREATES new Workspace instances and
-- never reads or writes anything the swing/launch/scoring logic depends on, so
-- it cannot affect them.
--
-- GENERATED, NOT HAND-AUTHORED: default.project.json only got one change across
-- this feature (the Baseplate shrunk/widened to just the swing's support
-- platform -- see the written reports from those passes). The bands are a
-- repeated, formulaic set of parts, which is exactly what a loop is for rather
-- than hand-copying dozens of near-identical JSON blocks.
--
-- ONE LABEL PER BAND: each band carries exactly one number, placed directly
-- on it -- that number IS LuckCurve.VALUES[i + 1], the generated luck curve
-- (see LuckCurve.luau), formatted for readability. Band COUNT is no longer
-- authored anywhere either: this loop runs to #LuckCurve.VALUES, whatever
-- that currently is.
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
local RUNWAY_TOP_Y = 0 -- matches the baseplate's own top surface height

local runwayFolder = Instance.new("Folder")
runwayFolder.Name = "Runway"
runwayFolder.Parent = Workspace

-- The band is much wider (RUNWAY_WIDTH_STUDS) than it is long
-- (RUNWAY_BAND_LENGTH_STUDS) now, so a label sized to fill the whole face
-- would size itself against a roughly 5:1 rectangle and then, once rotated 90
-- degrees for correct reading orientation (see below), overflow well past the
-- band's own short edge and clip. Squaring the label off first -- sized to
-- the SHORTER dimension (the band's length) on both axes, centered on the
-- band -- means the 90-degree rotation doesn't change its footprint at all,
-- the same fix the previous pass used for the separate marker parts, just
-- applied to a sub-region of the band instead of a whole separate part.
local LABEL_SQUARE_FRACTION = LaunchConfig.RUNWAY_BAND_LENGTH_STUDS / LaunchConfig.RUNWAY_WIDTH_STUDS

-- Colours repeat every COLOUR_CYCLE_LENGTH bands rather than spreading one hue
-- rotation across the whole (now much longer) road -- a single rotation over
-- ~74 bands would put neighbouring bands within a hue or two of each other,
-- reading as a slow gradient instead of a sequence of distinct colours. Five
-- repeating hues keeps every band visually distinct from its immediate
-- neighbours no matter how long the generated curve gets.
local COLOUR_CYCLE_LENGTH = 5

for i = 0, #LuckCurve.VALUES - 1 do
	local band = Instance.new("Part")
	band.Name = string.format("RunwayBand%02d", i + 1)
	band.Anchored = true
	band.CanCollide = true
	-- NOT Neon: SmoothPlastic holds a set Color3 the truest under normal scene
	-- lighting of any material Roblox offers -- no bump/roughness map (unlike
	-- plain Plastic) and no strong specular highlight (unlike Metal/Foil/Glass)
	-- to wash saturation out in bright spots or dull it elsewhere.
	band.Material = Enum.Material.SmoothPlastic
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

	-- ONE NUMBER PER BAND: this band's luck value from the generated curve,
	-- formatted the same way the HUD formats it on landing (see
	-- LuckCurve.formatLuck) so the two never disagree on how a number reads.
	local luck = LuckCurve.VALUES[i + 1]

	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = "DistanceLabel"
	surfaceGui.Face = Enum.NormalId.Top
	surfaceGui.LightInfluence = 0
	surfaceGui.PixelsPerStud = 24
	surfaceGui.Parent = band

	-- Readable from the chase camera (behind and above, looking forward and
	-- down -- see LaunchClient.client.luau); Rotation = 90 is the confirmed fix
	-- for this face's default orientation from the previous pass. Squared and
	-- centered per the comment above so that rotation doesn't clip it.
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(LABEL_SQUARE_FRACTION, 1)
	label.Rotation = 90
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.new(0, 0, 0)
	label.TextStrokeColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Text = LuckCurve.formatLuck(luck)
	label.Parent = surfaceGui
end
