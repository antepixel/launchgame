--!strict
-- Every tier-dependent VISUAL constant for the swing lives here, and ONLY
-- here -- same rule as every other Config module in this project. This is
-- COSMETIC ONLY: nothing here feeds distance, timing, or scoring (that's
-- LaunchConfig.SWING_TIER_DISTANCE_SCALE, untouched). One record per swing
-- tier, indexed 1-11 same as SWING_TIER_DISTANCE_SCALE/ShopConfig.SWING_
-- TIER_PRICES -- must stay exactly as many entries as those two.
--
-- FOUR BANDS, each a genuinely different STRUCTURE, not a recolour of the
-- same four boxes -- see SwingBuilder.server.luau, which reads every field
-- below to construct (and, on a tier change, completely rebuild) the swing
-- from ~20-40 parts:
--   1-3   Playground -- wooden A-frame, rope, weathered colours, small.
--   4-6   Industrial -- vertical steel poles, bolted gussets, chain-link
--         seat chain, hazard stripes, taller/heavier.
--   7-9   Engineered -- sleek chrome/foil, glowing accent trim, contoured
--         seat, thick rod "chain", cleaner and larger.
--   10-11 Spectacular -- neon, a floating seat, glowing energy tether
--         instead of a chain, enormous.
-- Within a band, only scale/colour/detail-count differ -- see the written
-- report for why every tier still visibly changes something even when the
-- band (and therefore the SHAPE) stays the same.
local SwingTierVisuals = {}

export type BraceStyle = "ARung" | "CrossGusset" | "DiagonalGusset" | "Strut"
export type ChainStyle = "Rope" | "Chain" | "Rod" | "Energy"
export type SeatStyle = "Plank" | "Bucket" | "Contoured" | "Floating"
export type GroundPad = "Dirt" | "Concrete" | "Metal" | "Glow"

export type TierVisual = {
	-- ===== Frame proportions ===== all in studs/degrees BEFORE `scale` is
	-- applied -- see SwingBuilder.build, which multiplies every dimension by
	-- `scale` uniformly so the whole structure grows together, never just
	-- one axis.
	scale: number,
	-- Degrees each post splays outward from vertical at the BOTTOM (0 = dead
	-- vertical steel/chrome column; >0 = classic A-frame). The post's TOP
	-- stays fixed under the beam regardless -- only the ground contact point
	-- moves outward, same idea as a real A-frame leg.
	postAngleDegrees: number,
	postShape: Enum.PartType,
	beamShape: Enum.PartType,
	capShape: Enum.PartType,
	braceStyle: BraceStyle,
	braceCount: number,
	groundPad: GroundPad,
	hazardStripes: boolean,
	glowAccent: boolean,
	glowColor: Color3,

	-- ===== Seat =====
	seatStyle: SeatStyle,

	-- ===== Chain/rope/rod/energy tether =====
	chainStyle: ChainStyle,
	chainLinkCount: number, -- ignored when chainStyle == "Energy"

	-- ===== Materials/colours -- FOUR independent slots (frame, trim, seat,
	-- chain), never all the same, per "surface variety" =====
	frameMaterial: Enum.Material,
	frameColor: Color3,
	trimMaterial: Enum.Material,
	trimColor: Color3,
	seatMaterial: Enum.Material,
	seatColor: Color3,
	chainMaterial: Enum.Material,
	chainColor: Color3,

	-- ===== Flight trail(s) -- see LaunchServer.server.luau's
	-- createFlightTrail for exactly how every field is applied. =====
	trailEnabled: boolean,
	trailLifetime: number,
	trailWidthStart: number,
	trailWidthEnd: number,
	-- 2+ colours -- a real gradient along the trail, not a flat hue. Roughly
	-- brightest-near-character to a darker/complementary tone at the tail.
	trailColors: { Color3 },
	trailMinTransparency: number,
	trailLightEmission: number,
	trailMinLength: number,
	-- A SECOND trail, offset from the first, at top tiers only -- a layered
	-- double-streak instead of one ribbon.
	secondTrailEnabled: boolean,
	secondTrailColors: { Color3 },
	secondTrailOffset: number,

	-- ===== One-shot launch burst =====
	burstColor: Color3,
	burstCount: number,
	burstSize: number,
	burstLifetime: number,
}

-- Base dimensions (studs), BEFORE `scale`. Every tier's frame is built from
-- these same base numbers times its own `scale` -- see SwingBuilder.build --
-- so "legs thick enough to plausibly hold the structure" and "beam
-- overhangs the apexes slightly" hold true at every size, not just tier 1.
SwingTierVisuals.BASE_POST_HEIGHT = 13
SwingTierVisuals.BASE_STAND_HALF_WIDTH = 6
SwingTierVisuals.BASE_POST_THICKNESS = 1.6
SwingTierVisuals.BASE_BEAM_THICKNESS = 1.3
-- Beam overhang past each apex -- REDUCED from 1.5 to 0.5 in the A-frame
-- rebuild (see the written report) so the beam's total length lands at the
-- specified ~13 studs at tier 1 (2*BASE_STAND_HALF_WIDTH + 2*this = 13),
-- not the old 15.
SwingTierVisuals.BASE_BEAM_OVERHANG = 0.5
-- Half the distance between an A-frame's two feet along Z (depth) -- NEW
-- in the A-frame rebuild (see the written report): the old silhouette was
-- two vertical posts and a crossbar with almost no depth at all (tier 1
-- measured 3.8 studs deep against 14.4 tall); a real A-frame has FOUR legs,
-- two per side, splayed outward along depth from a shared apex down to two
-- feet 2x this far apart (9 studs at tier 1).
SwingTierVisuals.BASE_LEG_SPLAY_HALF_DEPTH = 4.5

SwingTierVisuals.TIERS = {
	-- Tier 1: small wooden A-frame, weathered brown, a plain plank seat on
	-- rope. The baseline every other tier is a departure from.
	{
		scale = 1.0,
		postAngleDegrees = 12,
		postShape = Enum.PartType.Block,
		beamShape = Enum.PartType.Block,
		capShape = Enum.PartType.Ball,
		braceStyle = "ARung",
		braceCount = 1,
		groundPad = "Dirt",
		hazardStripes = false,
		glowAccent = false,
		glowColor = Color3.fromRGB(255, 255, 255),
		seatStyle = "Plank",
		chainStyle = "Rope",
		chainLinkCount = 5,
		frameMaterial = Enum.Material.Wood,
		frameColor = Color3.fromRGB(96, 64, 32),
		trimMaterial = Enum.Material.WoodPlanks,
		trimColor = Color3.fromRGB(70, 46, 22),
		seatMaterial = Enum.Material.WoodPlanks,
		seatColor = Color3.fromRGB(140, 100, 55),
		chainMaterial = Enum.Material.Fabric,
		chainColor = Color3.fromRGB(180, 160, 120),
		trailEnabled = false,
		trailLifetime = 0,
		trailWidthStart = 0,
		trailWidthEnd = 0,
		trailColors = { Color3.fromRGB(255, 255, 255) },
		trailMinTransparency = 1,
		trailLightEmission = 0,
		trailMinLength = 0.1,
		secondTrailEnabled = false,
		secondTrailColors = { Color3.fromRGB(255, 255, 255) },
		secondTrailOffset = 0,
		burstColor = Color3.fromRGB(230, 220, 200),
		burstCount = 4,
		burstSize = 0.6,
		burstLifetime = 0.3,
	},
	-- Tier 2: same playground kit, a size step up, warmer stain.
	{
		scale = 1.12,
		postAngleDegrees = 12,
		postShape = Enum.PartType.Block,
		beamShape = Enum.PartType.Block,
		capShape = Enum.PartType.Ball,
		braceStyle = "ARung",
		braceCount = 1,
		groundPad = "Dirt",
		hazardStripes = false,
		glowAccent = false,
		glowColor = Color3.fromRGB(255, 255, 255),
		seatStyle = "Plank",
		chainStyle = "Rope",
		chainLinkCount = 5,
		frameMaterial = Enum.Material.Wood,
		frameColor = Color3.fromRGB(120, 80, 42),
		trimMaterial = Enum.Material.WoodPlanks,
		trimColor = Color3.fromRGB(90, 58, 28),
		seatMaterial = Enum.Material.WoodPlanks,
		seatColor = Color3.fromRGB(155, 112, 62),
		chainMaterial = Enum.Material.Fabric,
		chainColor = Color3.fromRGB(195, 172, 128),
		trailEnabled = false,
		trailLifetime = 0,
		trailWidthStart = 0,
		trailWidthEnd = 0,
		trailColors = { Color3.fromRGB(255, 255, 255) },
		trailMinTransparency = 1,
		trailLightEmission = 0,
		trailMinLength = 0.1,
		secondTrailEnabled = false,
		secondTrailColors = { Color3.fromRGB(255, 255, 255) },
		secondTrailOffset = 0,
		burstColor = Color3.fromRGB(235, 215, 180),
		burstCount = 5,
		burstSize = 0.7,
		burstLifetime = 0.3,
	},
	-- Tier 3: the biggest, best-kept playground set -- richer wood, and the
	-- first (subtle, short) trail appears here rather than snapping in at
	-- the industrial jump.
	{
		scale = 1.28,
		postAngleDegrees = 11,
		postShape = Enum.PartType.Block,
		beamShape = Enum.PartType.Block,
		capShape = Enum.PartType.Ball,
		braceStyle = "ARung",
		braceCount = 1,
		groundPad = "Dirt",
		hazardStripes = false,
		glowAccent = false,
		glowColor = Color3.fromRGB(255, 255, 255),
		seatStyle = "Plank",
		chainStyle = "Rope",
		chainLinkCount = 6,
		frameMaterial = Enum.Material.WoodPlanks,
		frameColor = Color3.fromRGB(150, 102, 51),
		trimMaterial = Enum.Material.Wood,
		trimColor = Color3.fromRGB(105, 70, 35),
		seatMaterial = Enum.Material.WoodPlanks,
		seatColor = Color3.fromRGB(170, 125, 70),
		chainMaterial = Enum.Material.Fabric,
		chainColor = Color3.fromRGB(205, 182, 135),
		trailEnabled = true,
		trailLifetime = 0.35,
		trailWidthStart = 1.0,
		trailWidthEnd = 0.2,
		trailColors = { Color3.fromRGB(210, 180, 130), Color3.fromRGB(160, 130, 90) },
		trailMinTransparency = 0.75,
		trailLightEmission = 0,
		trailMinLength = 0.1,
		secondTrailEnabled = false,
		secondTrailColors = { Color3.fromRGB(255, 255, 255) },
		secondTrailOffset = 0,
		burstColor = Color3.fromRGB(210, 180, 130),
		burstCount = 8,
		burstSize = 0.9,
		burstLifetime = 0.35,
	},
	-- Tier 4: industrial begins -- vertical steel poles, bolted gusset
	-- braces, a real chain-link seat chain, muted hazard stripes.
	{
		scale = 1.55,
		postAngleDegrees = 0,
		postShape = Enum.PartType.Cylinder,
		beamShape = Enum.PartType.Cylinder,
		capShape = Enum.PartType.Cylinder,
		braceStyle = "CrossGusset",
		braceCount = 2,
		groundPad = "Concrete",
		hazardStripes = true,
		glowAccent = false,
		glowColor = Color3.fromRGB(255, 255, 255),
		seatStyle = "Bucket",
		chainStyle = "Chain",
		chainLinkCount = 7,
		frameMaterial = Enum.Material.Metal,
		frameColor = Color3.fromRGB(90, 95, 100),
		trimMaterial = Enum.Material.DiamondPlate,
		trimColor = Color3.fromRGB(60, 62, 66),
		seatMaterial = Enum.Material.Metal,
		seatColor = Color3.fromRGB(80, 110, 80),
		chainMaterial = Enum.Material.DiamondPlate,
		chainColor = Color3.fromRGB(70, 72, 76),
		trailEnabled = true,
		trailLifetime = 0.45,
		trailWidthStart = 1.2,
		trailWidthEnd = 0.25,
		trailColors = { Color3.fromRGB(140, 200, 140), Color3.fromRGB(70, 120, 70) },
		trailMinTransparency = 0.6,
		trailLightEmission = 0.1,
		trailMinLength = 0.15,
		secondTrailEnabled = false,
		secondTrailColors = { Color3.fromRGB(255, 255, 255) },
		secondTrailOffset = 0,
		burstColor = Color3.fromRGB(150, 210, 150),
		burstCount = 12,
		burstSize = 1.1,
		burstLifetime = 0.4,
	},
	-- Tier 5: industrial, painted a louder safety red, more stripes.
	{
		scale = 1.75,
		postAngleDegrees = 0,
		postShape = Enum.PartType.Cylinder,
		beamShape = Enum.PartType.Cylinder,
		capShape = Enum.PartType.Cylinder,
		braceStyle = "CrossGusset",
		braceCount = 2,
		groundPad = "Concrete",
		hazardStripes = true,
		glowAccent = false,
		glowColor = Color3.fromRGB(255, 255, 255),
		seatStyle = "Bucket",
		chainStyle = "Chain",
		chainLinkCount = 7,
		frameMaterial = Enum.Material.Metal,
		frameColor = Color3.fromRGB(175, 45, 40),
		trimMaterial = Enum.Material.DiamondPlate,
		trimColor = Color3.fromRGB(40, 40, 42),
		seatMaterial = Enum.Material.Metal,
		seatColor = Color3.fromRGB(60, 60, 64),
		chainMaterial = Enum.Material.DiamondPlate,
		chainColor = Color3.fromRGB(80, 82, 86),
		trailEnabled = true,
		trailLifetime = 0.55,
		trailWidthStart = 1.5,
		trailWidthEnd = 0.3,
		trailColors = { Color3.fromRGB(230, 80, 70), Color3.fromRGB(140, 40, 35) },
		trailMinTransparency = 0.5,
		trailLightEmission = 0.15,
		trailMinLength = 0.15,
		secondTrailEnabled = false,
		secondTrailColors = { Color3.fromRGB(255, 255, 255) },
		secondTrailOffset = 0,
		burstColor = Color3.fromRGB(240, 90, 90),
		burstCount = 16,
		burstSize = 1.3,
		burstLifetime = 0.4,
	},
	-- Tier 6: the biggest, heaviest industrial rig -- brushed steel
	-- (DiamondPlate as the PRIMARY frame material now, not just trim),
	-- full hazard-stripe treatment.
	{
		scale = 2.0,
		postAngleDegrees = 0,
		postShape = Enum.PartType.Cylinder,
		beamShape = Enum.PartType.Cylinder,
		capShape = Enum.PartType.Cylinder,
		braceStyle = "CrossGusset",
		braceCount = 3,
		groundPad = "Concrete",
		hazardStripes = true,
		glowAccent = false,
		glowColor = Color3.fromRGB(255, 255, 255),
		seatStyle = "Bucket",
		chainStyle = "Chain",
		chainLinkCount = 8,
		frameMaterial = Enum.Material.DiamondPlate,
		frameColor = Color3.fromRGB(130, 133, 140),
		trimMaterial = Enum.Material.Metal,
		trimColor = Color3.fromRGB(35, 35, 38),
		seatMaterial = Enum.Material.Metal,
		seatColor = Color3.fromRGB(50, 50, 54),
		chainMaterial = Enum.Material.Metal,
		chainColor = Color3.fromRGB(150, 152, 158),
		trailEnabled = true,
		trailLifetime = 0.65,
		trailWidthStart = 1.8,
		trailWidthEnd = 0.35,
		trailColors = { Color3.fromRGB(200, 205, 215), Color3.fromRGB(110, 115, 125) },
		trailMinTransparency = 0.4,
		trailLightEmission = 0.2,
		trailMinLength = 0.2,
		secondTrailEnabled = false,
		secondTrailColors = { Color3.fromRGB(255, 255, 255) },
		secondTrailOffset = 0,
		burstColor = Color3.fromRGB(210, 215, 225),
		burstCount = 20,
		burstSize = 1.6,
		burstLifetime = 0.45,
	},
	-- Tier 7: engineered begins -- chrome, a glowing blue accent strip,
	-- thick chrome "rod" instead of a chain, a contoured seat.
	{
		scale = 2.3,
		postAngleDegrees = 0,
		postShape = Enum.PartType.Cylinder,
		beamShape = Enum.PartType.Cylinder,
		capShape = Enum.PartType.Ball,
		braceStyle = "DiagonalGusset",
		braceCount = 2,
		groundPad = "Metal",
		hazardStripes = false,
		glowAccent = true,
		glowColor = Color3.fromRGB(60, 160, 255),
		seatStyle = "Contoured",
		chainStyle = "Rod",
		chainLinkCount = 3,
		frameMaterial = Enum.Material.Foil,
		frameColor = Color3.fromRGB(210, 213, 224),
		trimMaterial = Enum.Material.Neon,
		trimColor = Color3.fromRGB(60, 160, 255),
		seatMaterial = Enum.Material.Foil,
		seatColor = Color3.fromRGB(230, 232, 240),
		chainMaterial = Enum.Material.Foil,
		chainColor = Color3.fromRGB(220, 223, 232),
		trailEnabled = true,
		trailLifetime = 0.75,
		trailWidthStart = 2.0,
		trailWidthEnd = 0.4,
		trailColors = { Color3.fromRGB(120, 200, 255), Color3.fromRGB(40, 110, 220) },
		trailMinTransparency = 0.3,
		trailLightEmission = 0.4,
		trailMinLength = 0.25,
		secondTrailEnabled = false,
		secondTrailColors = { Color3.fromRGB(255, 255, 255) },
		secondTrailOffset = 0,
		burstColor = Color3.fromRGB(120, 200, 255),
		burstCount = 26,
		burstSize = 1.9,
		burstLifetime = 0.5,
	},
	-- Tier 8: engineered, brighter/warmer accent (gold), bigger.
	{
		scale = 2.55,
		postAngleDegrees = 0,
		postShape = Enum.PartType.Cylinder,
		beamShape = Enum.PartType.Cylinder,
		capShape = Enum.PartType.Ball,
		braceStyle = "DiagonalGusset",
		braceCount = 2,
		groundPad = "Metal",
		hazardStripes = false,
		glowAccent = true,
		glowColor = Color3.fromRGB(255, 195, 60),
		seatStyle = "Contoured",
		chainStyle = "Rod",
		chainLinkCount = 3,
		frameMaterial = Enum.Material.Foil,
		frameColor = Color3.fromRGB(225, 227, 235),
		trimMaterial = Enum.Material.Neon,
		trimColor = Color3.fromRGB(255, 195, 60),
		seatMaterial = Enum.Material.Foil,
		seatColor = Color3.fromRGB(240, 241, 246),
		chainMaterial = Enum.Material.Foil,
		chainColor = Color3.fromRGB(235, 237, 244),
		trailEnabled = true,
		trailLifetime = 0.85,
		trailWidthStart = 2.3,
		trailWidthEnd = 0.45,
		trailColors = { Color3.fromRGB(255, 220, 130), Color3.fromRGB(230, 160, 40) },
		trailMinTransparency = 0.2,
		trailLightEmission = 0.55,
		trailMinLength = 0.25,
		secondTrailEnabled = false,
		secondTrailColors = { Color3.fromRGB(255, 255, 255) },
		secondTrailOffset = 0,
		burstColor = Color3.fromRGB(255, 220, 130),
		burstCount = 32,
		burstSize = 2.2,
		burstLifetime = 0.5,
	},
	-- Tier 9: the sleekest, largest engineered rig -- brighter still, the
	-- last stop before neon takes over entirely.
	{
		scale = 2.8,
		postAngleDegrees = 0,
		postShape = Enum.PartType.Cylinder,
		beamShape = Enum.PartType.Cylinder,
		capShape = Enum.PartType.Ball,
		braceStyle = "DiagonalGusset",
		braceCount = 2,
		groundPad = "Metal",
		hazardStripes = false,
		glowAccent = true,
		glowColor = Color3.fromRGB(255, 255, 255),
		seatStyle = "Contoured",
		chainStyle = "Rod",
		chainLinkCount = 2,
		frameMaterial = Enum.Material.Foil,
		frameColor = Color3.fromRGB(240, 241, 248),
		trimMaterial = Enum.Material.Neon,
		trimColor = Color3.fromRGB(255, 255, 255),
		seatMaterial = Enum.Material.Foil,
		seatColor = Color3.fromRGB(250, 250, 252),
		chainMaterial = Enum.Material.Foil,
		chainColor = Color3.fromRGB(245, 246, 250),
		trailEnabled = true,
		trailLifetime = 0.95,
		trailWidthStart = 2.6,
		trailWidthEnd = 0.5,
		trailColors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(180, 210, 255) },
		trailMinTransparency = 0.1,
		trailLightEmission = 0.7,
		trailMinLength = 0.3,
		secondTrailEnabled = false,
		secondTrailColors = { Color3.fromRGB(255, 255, 255) },
		secondTrailOffset = 0,
		burstColor = Color3.fromRGB(255, 255, 255),
		burstCount = 40,
		burstSize = 2.6,
		burstLifetime = 0.55,
	},
	-- Tier 10: spectacular begins -- neon cyan, a floating seat, an ENERGY
	-- tether instead of a chain, and a second layered trail.
	{
		scale = 3.15,
		postAngleDegrees = 0,
		postShape = Enum.PartType.Cylinder,
		beamShape = Enum.PartType.Cylinder,
		capShape = Enum.PartType.Ball,
		braceStyle = "Strut",
		braceCount = 2,
		groundPad = "Glow",
		hazardStripes = false,
		glowAccent = true,
		glowColor = Color3.fromRGB(50, 230, 255),
		seatStyle = "Floating",
		chainStyle = "Energy",
		chainLinkCount = 0,
		frameMaterial = Enum.Material.Neon,
		frameColor = Color3.fromRGB(50, 230, 255),
		trimMaterial = Enum.Material.Glass,
		trimColor = Color3.fromRGB(180, 250, 255),
		seatMaterial = Enum.Material.Neon,
		seatColor = Color3.fromRGB(50, 230, 255),
		chainMaterial = Enum.Material.Neon,
		chainColor = Color3.fromRGB(80, 240, 255),
		trailEnabled = true,
		trailLifetime = 1.05,
		trailWidthStart = 3.0,
		trailWidthEnd = 0.6,
		trailColors = { Color3.fromRGB(120, 250, 255), Color3.fromRGB(40, 140, 255), Color3.fromRGB(120, 250, 255) },
		trailMinTransparency = 0.05,
		trailLightEmission = 1,
		trailMinLength = 0.3,
		secondTrailEnabled = true,
		secondTrailColors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(120, 250, 255) },
		secondTrailOffset = 1.2,
		burstColor = Color3.fromRGB(100, 245, 255),
		burstCount = 50,
		burstSize = 3.0,
		burstLifetime = 0.6,
	},
	-- Tier 11: the flex -- blazing magenta neon, the biggest single jump of
	-- the whole curve, everything at maximum.
	{
		scale = 3.6,
		postAngleDegrees = 0,
		postShape = Enum.PartType.Cylinder,
		beamShape = Enum.PartType.Cylinder,
		capShape = Enum.PartType.Ball,
		braceStyle = "Strut",
		braceCount = 3,
		groundPad = "Glow",
		hazardStripes = false,
		glowAccent = true,
		glowColor = Color3.fromRGB(255, 25, 190),
		seatStyle = "Floating",
		chainStyle = "Energy",
		chainLinkCount = 0,
		frameMaterial = Enum.Material.Neon,
		frameColor = Color3.fromRGB(255, 25, 190),
		trimMaterial = Enum.Material.Glass,
		trimColor = Color3.fromRGB(255, 190, 240),
		seatMaterial = Enum.Material.Neon,
		seatColor = Color3.fromRGB(255, 25, 190),
		chainMaterial = Enum.Material.Neon,
		chainColor = Color3.fromRGB(255, 60, 210),
		trailEnabled = true,
		trailLifetime = 1.25,
		trailWidthStart = 3.6,
		trailWidthEnd = 0.7,
		trailColors = {
			Color3.fromRGB(255, 255, 255),
			Color3.fromRGB(255, 60, 210),
			Color3.fromRGB(140, 60, 255),
		},
		trailMinTransparency = 0,
		trailLightEmission = 1,
		trailMinLength = 0.3,
		secondTrailEnabled = true,
		secondTrailColors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(140, 60, 255) },
		secondTrailOffset = 1.6,
		burstColor = Color3.fromRGB(255, 90, 220),
		burstCount = 65,
		burstSize = 3.5,
		burstLifetime = 0.65,
	},
} :: { TierVisual }

-- Clamped read, same defensive convention as PlayerProfile's tier clamps.
function SwingTierVisuals.forTier(tier: number): TierVisual
	local tiers = SwingTierVisuals.TIERS
	local index = math.clamp(tier, 1, #tiers)
	return tiers[index]
end

return SwingTierVisuals
