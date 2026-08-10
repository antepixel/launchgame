--!strict
-- Every tier-dependent VISUAL constant for the swing lives here, and ONLY
-- here -- same rule as every other Config module in this project. This is
-- COSMETIC ONLY: nothing here feeds distance, timing, or scoring (that's
-- LaunchConfig.SWING_TIER_DISTANCE_SCALE, untouched). One record per swing
-- tier, indexed 1-11 same as SWING_TIER_DISTANCE_SCALE/ShopConfig.SWING_
-- TIER_PRICES -- must stay exactly as many entries as those two.
--
-- FOUR MATERIAL BANDS (approved four-band scheme -- exact per-tier values,
-- not a reinterpretation): the frame darkens per tier WITHIN a band so no
-- two tiers are identical, and both material and accentColor change
-- completely ACROSS a band boundary -- see SwingBuilder.luau, which reads
-- every field below to construct (and, on a tier change, completely
-- rebuild) the swing:
--   1-3   Wood -- weathered brown, darkens tier to tier.
--   4-6   Industrial steel (DiamondPlate) -- cool grey, warm gold accent.
--   7-9   Engineered titanium (Metal) -- bright silver, blue accent.
--   10-11 Obsidian (Metal) -- near-black, violet accent, full neon trim.
-- The A-FRAME SILHOUETTE itself (scale, postAngleDegrees, postShape,
-- beamShape) is UNCHANGED by this scheme and must stay that way -- see the
-- written report on the A-frame rebuild this scheme was layered on top of.
local SwingTierVisuals = {}

export type ChainStyle = "Rope" | "Chain" | "Rod" | "Energy"

export type TierVisual = {
	-- ===== Frame proportions ===== all in studs/degrees BEFORE `scale` is
	-- applied -- see SwingBuilder.build, which multiplies every dimension by
	-- `scale` uniformly so the whole structure grows together, never just
	-- one axis. MUST NOT CHANGE as part of the four-band visual scheme --
	-- the A-frame silhouette is a separate, frozen concern.
	scale: number,
	-- Degrees each post splays outward from vertical at the BOTTOM (0 = dead
	-- vertical steel/chrome column; >0 = classic A-frame). The post's TOP
	-- stays fixed under the beam regardless -- only the ground contact point
	-- moves outward, same idea as a real A-frame leg.
	postAngleDegrees: number,
	postShape: Enum.PartType,
	beamShape: Enum.PartType,

	-- ===== X-bracing -- two crossed struts per level, between the two legs
	-- of ONE A-frame side (see SwingBuilder.buildBraces). Count per tier:
	-- 0,0,0,0,1,2,2,3,3,4,5 -- exact, approved values. =====
	braceCount: number,
	-- ===== Beam collars -- cylinders encircling the beam, centred on it, NO
	-- rotation needed (see SwingBuilder.buildBeamCollars). Count per tier:
	-- 0,0,0,0,0,0,1,2,3,4,5 -- exact, approved values. =====
	collarCount: number,

	-- ===== Glow trim -- ONE accentColor rod along the beam underside plus
	-- one along each of the four legs (see SwingBuilder.buildTrim). Tiers
	-- 1-5: frameMaterial, opaque (glowAccent = false, glowTransparency
	-- unused). Tiers 6-11: Neon, per-tier glowTransparency
	-- (0.55/0.45/0.38/0.30/0.22/0.14 for tiers 6/7/8/9/10/11). =====
	glowAccent: boolean,
	glowTransparency: number,

	-- ===== Ground pads: Wood tiers 1-3, Slate tiers 4-11. Colour is always
	-- frameColor lerped 40% toward black -- computed in SwingBuilder, not
	-- stored here. =====
	groundPadMaterial: Enum.Material,

	-- ===== Chains and seat: Wood tiers 1-3, Metal tiers 4-11. Colour is
	-- always frameColor lerped 22% toward (210,210,215), reflectance is
	-- always this tier's `reflectance` x 0.5 -- both computed in
	-- SwingBuilder, not stored here. =====
	chainSeatMaterial: Enum.Material,

	-- ===== Chain/rope/rod/energy tether =====
	chainStyle: ChainStyle,
	chainLinkCount: number, -- ignored when chainStyle == "Energy"

	-- ===== Frame + accent -- per the approved four-band table: frameColor/
	-- accentColor/frameMaterial/reflectance, exact per tier. =====
	frameMaterial: Enum.Material,
	frameColor: Color3,
	accentColor: Color3,
	reflectance: number,

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

-- Upper bound on the FOOTPRINT scale (see SwingBuilder.build) -- the
-- factor applied to every dimension that drives the frame's X (width) or
-- Z (depth) extent: standHalfWidth, beamOverhang, legSplayHalfDepth,
-- postThickness, beamThickness, and the seat's own width/depth/thickness.
-- Every tier's HEIGHT scale (visual.scale, above) is UNCLAMPED and
-- unchanged -- postHeight, the pivot height, and the rope length all keep
-- growing the full 1.00-3.60x every tier already used. Only the
-- horizontal footprint stops growing past this factor, so a swing keeps
-- getting taller (and its silhouette proportions stay internally
-- consistent -- footprint scale still applies EQUALLY to width and depth,
-- so an A-frame never reads deeper than it is wide) without spilling out
-- of its 40-stud road lane. 2.21 is tuned so the TOP tier (the largest,
-- scale = 3.60 -- tier 10 since the ladder renumber, tier 11 before it)
-- lands just under 35 studs wide -- tier 1 measures 15.84
-- studs wide at scale 1.0, and 35.01 / 15.84 = 2.21 -- see the written
-- report for the measured numbers this was tuned against.
SwingTierVisuals.FOOTPRINT_SCALE_MAX = 2.21

SwingTierVisuals.TIERS = {
	-- Tier 1: small wooden A-frame, weathered brown, a plain plank seat on
	-- rope. The baseline every other tier is a departure from.
	{
		scale = 1.0,
		postAngleDegrees = 12,
		postShape = Enum.PartType.Block,
		beamShape = Enum.PartType.Block,
		braceCount = 0,
		collarCount = 0,
		glowAccent = false,
		glowTransparency = 0,
		groundPadMaterial = Enum.Material.Wood,
		chainSeatMaterial = Enum.Material.Wood,
		chainStyle = "Rope",
		chainLinkCount = 5,
		frameMaterial = Enum.Material.Wood,
		frameColor = Color3.fromRGB(146, 104, 64),
		accentColor = Color3.fromRGB(120, 86, 54),
		reflectance = 0.00,
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
		scale = 1.15,
		postAngleDegrees = 12,
		postShape = Enum.PartType.Block,
		beamShape = Enum.PartType.Block,
		braceCount = 0,
		collarCount = 0,
		glowAccent = false,
		glowTransparency = 0,
		groundPadMaterial = Enum.Material.Wood,
		chainSeatMaterial = Enum.Material.Wood,
		chainStyle = "Rope",
		chainLinkCount = 5,
		frameMaterial = Enum.Material.Wood,
		frameColor = Color3.fromRGB(122, 84, 52),
		accentColor = Color3.fromRGB(150, 118, 78),
		reflectance = 0.00,
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
		scale = 1.33,
		postAngleDegrees = 11,
		postShape = Enum.PartType.Block,
		beamShape = Enum.PartType.Block,
		braceCount = 0,
		collarCount = 0,
		glowAccent = false,
		glowTransparency = 0,
		groundPadMaterial = Enum.Material.Wood,
		chainSeatMaterial = Enum.Material.Wood,
		chainStyle = "Rope",
		chainLinkCount = 6,
		frameMaterial = Enum.Material.Wood,
		frameColor = Color3.fromRGB(96, 64, 40),
		accentColor = Color3.fromRGB(168, 132, 84),
		reflectance = 0.00,
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
	-- Tier 4: industrial steel begins -- diamond-plate frame, a real
	-- chain-link seat chain. No X-bracing yet -- that starts at tier 5.
	{
		scale = 1.53,
		postAngleDegrees = 0,
		postShape = Enum.PartType.Cylinder,
		beamShape = Enum.PartType.Cylinder,
		braceCount = 0,
		collarCount = 0,
		glowAccent = false,
		glowTransparency = 0,
		groundPadMaterial = Enum.Material.Slate,
		chainSeatMaterial = Enum.Material.Metal,
		chainStyle = "Chain",
		chainLinkCount = 7,
		frameMaterial = Enum.Material.DiamondPlate,
		frameColor = Color3.fromRGB(112, 118, 126),
		accentColor = Color3.fromRGB(214, 156, 58),
		reflectance = 0.04,
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
	-- Tier 5: industrial steel, darker frame, the first X-brace level.
	{
		scale = 1.77,
		postAngleDegrees = 0,
		postShape = Enum.PartType.Cylinder,
		beamShape = Enum.PartType.Cylinder,
		braceCount = 1,
		collarCount = 0,
		glowAccent = false,
		glowTransparency = 0,
		groundPadMaterial = Enum.Material.Slate,
		chainSeatMaterial = Enum.Material.Metal,
		chainStyle = "Chain",
		chainLinkCount = 7,
		frameMaterial = Enum.Material.DiamondPlate,
		frameColor = Color3.fromRGB(94, 100, 110),
		accentColor = Color3.fromRGB(222, 164, 62),
		reflectance = 0.05,
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
	-- Tier 6: the biggest, heaviest industrial rig -- darkest steel in the
	-- band, and the first tier with neon accent trim (glowAccent begins
	-- here, not at the titanium band).
	{
		scale = 2.04,
		postAngleDegrees = 0,
		postShape = Enum.PartType.Cylinder,
		beamShape = Enum.PartType.Cylinder,
		braceCount = 2,
		collarCount = 0,
		glowAccent = true,
		glowTransparency = 0.55,
		groundPadMaterial = Enum.Material.Slate,
		chainSeatMaterial = Enum.Material.Metal,
		chainStyle = "Chain",
		chainLinkCount = 8,
		frameMaterial = Enum.Material.DiamondPlate,
		frameColor = Color3.fromRGB(76, 82, 92),
		accentColor = Color3.fromRGB(230, 172, 66),
		reflectance = 0.06,
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
	-- Tier 7: engineered titanium begins -- bright silver frame, blue
	-- accent, thick "rod" instead of a chain, the first beam collar.
	{
		scale = 2.35,
		postAngleDegrees = 0,
		postShape = Enum.PartType.Cylinder,
		beamShape = Enum.PartType.Cylinder,
		braceCount = 2,
		collarCount = 1,
		glowAccent = true,
		glowTransparency = 0.45,
		groundPadMaterial = Enum.Material.Slate,
		chainSeatMaterial = Enum.Material.Metal,
		chainStyle = "Rod",
		chainLinkCount = 3,
		frameMaterial = Enum.Material.Metal,
		frameColor = Color3.fromRGB(206, 212, 220),
		accentColor = Color3.fromRGB(86, 164, 214),
		reflectance = 0.14,
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
	-- Tier 8: engineered titanium, brighter frame, second beam collar.
	{
		scale = 2.71,
		postAngleDegrees = 0,
		postShape = Enum.PartType.Cylinder,
		beamShape = Enum.PartType.Cylinder,
		braceCount = 3,
		collarCount = 2,
		glowAccent = true,
		glowTransparency = 0.38,
		groundPadMaterial = Enum.Material.Slate,
		chainSeatMaterial = Enum.Material.Metal,
		chainStyle = "Rod",
		chainLinkCount = 3,
		frameMaterial = Enum.Material.Metal,
		frameColor = Color3.fromRGB(182, 190, 202),
		accentColor = Color3.fromRGB(72, 152, 208),
		reflectance = 0.17,
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
	-- Tier 9: the sleekest, largest engineered rig -- the last titanium
	-- tier before obsidian takes over.
	{
		scale = 3.12,
		postAngleDegrees = 0,
		postShape = Enum.PartType.Cylinder,
		beamShape = Enum.PartType.Cylinder,
		braceCount = 3,
		collarCount = 3,
		glowAccent = true,
		glowTransparency = 0.30,
		groundPadMaterial = Enum.Material.Slate,
		chainSeatMaterial = Enum.Material.Metal,
		chainStyle = "Rod",
		chainLinkCount = 2,
		frameMaterial = Enum.Material.Metal,
		frameColor = Color3.fromRGB(156, 166, 182),
		accentColor = Color3.fromRGB(58, 140, 202),
		reflectance = 0.20,
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
	-- Tier 10 (the top tier, and the old tier 11 unchanged -- see
	-- LaunchConfig.SWING_TIER_DISTANCE_SCALE for what happened to the tier
	-- that used to sit here): the flex -- darkest obsidian frame, brightest
	-- violet neon, the biggest single jump of the whole curve, everything at
	-- maximum. This is the tier that clears the road and lands on the chest
	-- platform, which is the whole reason it survived the cut.
	{
		scale = 3.6,
		postAngleDegrees = 0,
		postShape = Enum.PartType.Cylinder,
		beamShape = Enum.PartType.Cylinder,
		braceCount = 5,
		collarCount = 5,
		glowAccent = true,
		glowTransparency = 0.14,
		groundPadMaterial = Enum.Material.Slate,
		chainSeatMaterial = Enum.Material.Metal,
		chainStyle = "Energy",
		chainLinkCount = 0,
		frameMaterial = Enum.Material.Metal,
		frameColor = Color3.fromRGB(24, 20, 36),
		accentColor = Color3.fromRGB(206, 172, 255),
		reflectance = 0.32,
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
