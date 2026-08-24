--!strict
-- EXPLORE_PATTERNS.luau -- PATTERN EXPLORATION RIG FOR THE SLIME SKINS.
--
-- Paste the whole file into the Studio command bar and it builds
-- workspace.PatternLab from nothing: ten variants of one hue, laid out in a row,
-- every one calibrated to the same white fraction so the SHAPES are compared and
-- nothing else. No other file needs to be present.
--
-- NOT SHIPPING CODE and deliberately NOT under src/ (Rojo syncs that). This is a
-- design instrument, not a build script -- BUILD_SKINS.luau is the real one, and
-- whatever wins here gets folded into it.
--
-- ============================ WHAT THIS IS FOR =============================
--
-- THE HUE IS THE IDENTITY. A blue slime has to read as BLUE. At the 50/50 split
-- the spirals read as "blue and white" rather than as blue, which is fine for a
-- beach ball and wrong for a creature. So white drops to roughly a quarter --
-- enough to be a real pattern, not enough to dilute what colour the thing is.
--
-- EVERY VARIANT IS CALIBRATED TO THE SAME WHITE FRACTION. Each shape has exactly
-- one scalar knob and the build binary-searches it against the real texel set
-- until measured white hits WHITE_TARGET. Without that the comparison is
-- worthless: a shape would look better simply for carrying less white.
--
-- THE FRAME IS ALIGNED TO THE FACE, WHICH IS THE NEW IDEA HERE. Every pattern
-- tried so far -- bands, caps, splits, spirals -- was axisymmetric about the
-- VERTICAL axis, so the body might as well not have had a front. Real creature
-- markings are almost never like that: they are bilaterally symmetric about the
-- animal's own midline, and they relate to its features. A white belly, a bib, a
-- blaze over the muzzle, socks. So q is resolved into
--     f  forward, toward the face
--     s  sideways, the bilateral axis
--     y  up
-- and anything depending on s^2 or |s| rather than s is symmetric left-to-right
-- the way a marking on an animal is.
--
-- THE TEST IS "DELIBERATE CREATURE MARKING, OR SHAPE IMPOSED ON A SPHERE?"
-- Spirals passed it by reading as a beach ball, which is a real object. Straight
-- bisections failed it by reading as a painted egg. That is the only question
-- these ten are here to answer.
--
-- ===================== THE TERMINATOR RULE (learned here) =================
--
-- A MARKING HAS TO CROSS THE LIGHT BOUNDARY TO READ AS A MARKING. If it lies
-- along one side of that boundary instead, the renderer is already drawing the
-- same shape for free, and the eye takes the cheaper explanation: not a marked
-- creature, just a lit one. This is what killed countershade, and in hindsight
-- it is what killed the tonal accents before it. Both put their edge exactly
-- where the light already puts one.
--
-- IT IS NOT THE TONE AND IT IS NOT THE EDGE. Both were A/B'd against
-- countershade at 40 studs, on the body, at matched white fraction, and neither
-- moves it:
--     cream  (252,251,247) on the belly renders  144.9
--     pure   (255,255,255) on the belly renders  146.8   -- 2 of 255, invisible
--     the SAME cream on an up-facing crown renders 234.1 -- 90 of 255
-- The grey is the shading, not the paint; the accent was already 1.2% off pure
-- white, so there was never any grey in it to remove. Likewise the boundary
-- already resolves in about 2 px at 40 studs, and a 6x harder texture edge
-- moved exactly one pixel. THIS IS WHY BOTH KNOBS EXIST AS PER-VARIANT
-- OVERRIDES rather than having been deleted: proving a knob does not matter is
-- worth keeping, and it should not cost a scratch edit to prove it again.
--
-- SO IT IS MEASURED, NOT EYEBALLED -- lightFit() reports two numbers per
-- variant, and they answer different halves of the question.
--
--   J   Youden's J of the best single height threshold. All a light does is
--       fall off monotonically from top to bottom, so this asks how much of the
--       marking a plain gradient could account for. 1.00 = a light draws it
--       exactly. Measured: socks 1.00, cap-tilt 0.73, countershade 0.51,
--       blaze 0.13, stripes4 0.05, plastron 0.01.
--
--   lit Mean lambert over the white, against mean lambert over the whole body.
--       Where the marking SITS rather than what shape it is, and the one that
--       matches what the pixels did. Countershade measures 0.01 -- its white is
--       entirely under the equator, which is exactly the 144.9-against-234.1
--       above. Wanted: near 1, meaning the marking straddles the boundary.
--       Measured: socks 0.00, countershade 0.01, bib 0.16, stripes2 0.70,
--       plastron 1.00, blaze 1.47, crest 1.74, cap-tilt 3.02.
--
-- BOTH ARE FLAGGED, NEVER ASSERTED. A high J or a lopsided lit is a reason to
-- look, not proof of a bad marking -- and the flag is two-sided, because
-- hiding in the shade (countershade) and sitting in the highlight (cap-tilt)
-- are the same mistake wearing different clothes.
--
-- THE COROLLARY, AND IT IS THE USEFUL HALF: A MARKING THAT NEVER MENTIONS
-- HEIGHT CANNOT BE MISTAKEN FOR A HEIGHT GRADIENT. Every shape here that
-- scores well is a function of f and s alone -- mane 0.10, brackets 0.11,
-- blaze 0.13, stripes4 0.05 -- and every shape that scores badly has y in it.
-- That is not a coincidence, it is the definition of J restated.
--
-- IT IS A TRADE, NOT A TUNING PROBLEM, once y is in the formula. A chevron
-- band |y + 0.45|s| - c| was swept across four offsets looking for one that
-- both straddles the light and stays unpredictable:
--     c = 0.18   J 0.40   lit 0.21     buried in the shade
--     c = 0.30   J 0.50   lit 0.57
--     c = 0.45   J 0.70   lit 1.66
--     c = 0.60   J 0.88   lit 3.31     sitting in the highlight
-- lit passes through 1 somewhere around c = 0.35, where J is already ~0.6.
-- Raising a y-dependent marking ACROSS the light boundary is the same act as
-- making it more predictable FROM height. There is no setting where it is both,
-- so the family was dropped rather than tuned. Reach for f and s instead.
--
-- WHAT THESE NUMBERS DO NOT MEASURE IS BOLDNESS. They say whether a shape can
-- be mistaken for lighting; they say nothing about how loud it is, which is
-- what a rarity ladder is actually ordering. Keep judging that by eye.
-- ===========================================================================
--
-- ======================== THE SECOND ACCENT ===============================
--
-- THIS IS A STRUCTURAL CHANGE, NOT A CONFIG VALUE, and it is written down here
-- because everything else in this file assumes a skin is TWO colours meeting at
-- ONE boundary. `core` gives a variant a third colour inside its marking:
-- the outer band in `white`, an inner region in `core.color` covering
-- `core.fraction` of the marking's own coverage.
--
-- THE CORE IS CALIBRATED, NOT SCALED. k is a threshold in g-space and it is
-- NEGATIVE for several variants here -- anything written as -(f/l) -- so
-- k * fraction moves the boundary the WRONG WAY for half the file. The core
-- gets its own bisection, to WHITE_TARGET * fraction. Sign-agnostic by
-- construction, at the cost of a second search per variant.
--
-- WHAT IT COSTS, all four of these being real and none of them hypothetical:
--
--   A SECOND BOUNDARY. This file has argued repeatedly for exactly one -- the
--   crown cap was turned off for being "a white disc sitting on the pole",
--   and the adaptive rim before it drew "a faint disc floating around the
--   face, competing with the one boundary that is supposed to be the design".
--   A core reintroduces that second edge deliberately. It has to earn it.
--
--   THE FEATURE FLOOR NOW BINDS ON THE CORE. The core is narrower than the
--   marking by construction, so it -- not the marking -- is what approaches
--   8 px first. It is measured separately and tracked against the same floor;
--   a core that half-resolves is the same cheap failure as a 1-texel star.
--   MEASURED on blaze at 28%, whose marking is a flat 44.9 px throughout:
--       fraction 0.40   core 16.4 px
--       fraction 0.25   core 10.4 px
--       fraction 0.15   core  6.0 px   <-- under the floor
--       fraction 0.08   core  3.5 px
--   so the floor binds at about fraction 0.20 for THIS shape, and a narrower
--   marking reaches it sooner. Do not pick a fraction without reading the
--   core figure the build prints for it.
--
--   MATCHED WHITE FRACTION STOPS MEANING MATCHED APPEARANCE. One bisection
--   used to pin the whole comparison. Now `fraction` is a second free
--   parameter the calibration does not constrain, so two variants at 28% can
--   look materially different. Hold `fraction` fixed across any A/B or the
--   comparison is worth nothing -- the same argument as the white fraction
--   itself, one level down.
--
--   CONTRAST BECOMES PAIRWISE. Three colours is three pairs, and the new one
--   -- accent against core -- is the dangerous one: two accents close to each
--   other read as one blurred marking, which is the tonal-accent failure
--   already killed once. Check it against BOTH numbers, not just luminance.
--
-- The per-texel cost is one extra smoothstep, which is nothing. The cost is
-- entirely in the four paragraphs above.
-- ===========================================================================
--
-- WHAT CARRIES OVER UNCHANGED, all of it already argued in BUILD_SKINS.luau:
-- white is the only accent; both colours belong to the same shape; nothing under
-- 8 px at 40 studs; antialiased boundaries; 3D evaluation on the mesh's own UV
-- island; containment-class texel ownership; 512; Plastic; no crown cap and no
-- twist ramp, because the re-unwrapped mesh handles its own poles.
--
-- FEATURE SIZE IS MEASURED, NOT DERIVED. These shapes have no closed form for
-- "narrowest part" the way a stripe count does, so the rig measures it: white
-- area over boundary length gives a characteristic width, 2A/P, which is the
-- stripe width for a stripe and something sensible for everything else.
--
-- REVERSAL: workspace.PatternLab:Destroy().
-- ===========================================================================

local AssetService = game:GetService("AssetService")

local P = {
	TEX = 512,
	ROOT_NAME = "PatternLab",
	SOURCE_MODELS = { "Slime", "AuxScene", "slime_uv" },
	BODY_WIDTH_STUDS = 14.0,
	BODY_MATERIAL = Enum.Material.Plastic,

	-- one hue for all ten, so shape is the only variable
	HUE = Color3.fromRGB(60, 120, 240),
	HUE_NAME = "blue",
	COLOUR_WHITE = Color3.fromRGB(252, 251, 247),

	-- hue dominates: white is the marking, not half the animal
	WHITE_TARGET = 0.28,
	WHITE_TOLERANCE = 0.004,

	-- THE TERMINATOR RULE, measured -- see the section of that name above.
	-- A warning, never an assert: a high score is a reason to look, not proof
	-- of a bad marking.
	-- A RAMP HAS NO EDGE, so "how wide is the smallest feature" has to be asked
	-- of what is VISIBLE rather than of the mask. A texel counts as visible when
	-- its painted colour differs from the body by more than this, in Color3
	-- units. See THE RAMP AND THE MEASUREMENTS in the header.
	VIS_THRESHOLD = 0.12,

	SHADOW_BINS = 256,
	SHADOW_WARN = 0.80,
	-- A marking wants to STRADDLE the light, so the flag is two-sided: well
	-- under 1 means it hides in the shade and renders grey (countershade), well
	-- over 1 means it sits in the highlight and reads as a lit top (cap-tilt).
	LIT_LO = 0.50,
	LIT_HI = 2.00,

	-- THE SIX AUTHORED HUES, mirrored from SLIME_COLOR_BY_TIER in
	-- src/ReplicatedStorage/Config/SlimeConfig.luau. Every 6-slime tier uses
	-- these same six in this same order, so one row of the grid below is one
	-- tier's entire art. COPIED rather than required, because this file is
	-- standalone by design -- if SlimeConfig's six ever move, move these too.
	HUES = {
		{ "green", Color3.fromRGB(70, 200, 80) },
		{ "red", Color3.fromRGB(225, 60, 60) },
		{ "blue", Color3.fromRGB(60, 120, 240) },
		{ "yellow", Color3.fromRGB(245, 215, 55) },
		{ "purple", Color3.fromRGB(165, 80, 220) },
		{ "orange", Color3.fromRGB(250, 140, 40) },
	},

	-- Tier -> variant. NON-EMPTY SWITCHES THIS FILE TO GRID MODE: every hue
	-- against every rung, laid out hue across and tier back. A shape chosen on
	-- one hue is a shape chosen on one sixth of the evidence, and the hue that
	-- breaks a marking will not be the one it was designed against.
	-- THE LADDER AS IT STANDS. Paste this in as LADDER to build the grid:
	--     { "Common", "bare" },
	--     { "Uncommon", "blaze" },
	--     { "Rare", "stripes4" },       -- twist 140
	--     { "Epic", "dots24" },
	--     { "Legendary", <fire> },      -- NOT YET: see FIRE above
	-- Mane is out -- it read as a soft halo bleeding into the body rather than
	-- as a marking. Legendary stops being a shape and becomes an image, which
	-- is the medium change the tiers above the patterns need, arriving one rung
	-- earlier than first planned.
	-- Collar held Rare until dots24 displaced it: collar and mane are both a
	-- white band across the upper face, and one row apart they were hard to
	-- rank. A dot field is a different visual family altogether, which is what
	-- separates Uncommon from Epic in a way another band could not. Note this
	-- was NOT what the IoU numbers said -- they called Uncommon -> Rare the
	-- tight pair, because they measure where the white sits and not what a
	-- player perceives. The grid was believed over the metric, correctly.
	LADDER = {},
	ROW_SPACING = 34,

	-- Build only these variants, by name, in this order. Empty builds them all.
	-- This is what makes an A/B repeatable instead of a scratch edit: name the
	-- two you are comparing and everything else about the build is untouched.
	ONLY = {},
	SEARCH_ITERS = 30,
	SEARCH_LO = -3.0,
	SEARCH_HI = 3.0,

	EDGE_SOFT = 0.012,
	ORIGIN = Vector3.new(-95, 0, -260),
	SPACING = 21,
	BODY_YAW_DEG = 179.4,

	VIEW_DISTANCE = 40,
	VIEW_FOV_DEG = 70,
	VIEW_FRAME_PX = 563,
	MIN_FEATURE_PX = 8,

	SAMPLE_STRIDE = 3,
	TICK_EVERY = 512,
	PAINT_TICK_ROWS = 6,
	YIELD_MS = 12,
}

-- face parts, measured off a lineup slime; offsets are in body-local space
local FACE_PARTS = {
	{ name = "eye_dark", mesh = "rbxassetid://81454373295475",
	  rel = CFrame.new(-3.537100, 0.256561, -4.447517),
	  size = Vector3.new(5.315629, 3.702577, 4.563491),
	  color = Color3.fromRGB(18, 18, 28) },
	{ name = "eye_white", mesh = "rbxassetid://109111264562266",
	  rel = CFrame.new(-3.943192, 0.935150, -4.960449),
	  size = Vector3.new(4.603409, 1.716936, 3.742096),
	  color = Color3.fromRGB(255, 255, 255) },
	{ name = "blush", mesh = "rbxassetid://83359732401472",
	  rel = CFrame.new(-3.323163, -1.230103, -4.188950),
	  size = Vector3.new(7.190265, 0.950127, 5.825126),
	  color = Color3.fromRGB(222, 66, 114) },
}

-- ===================================================================
-- THE FACE-ALIGNED FRAME.
-- Taken from where the eyes actually sit rather than declared, so it stays
-- correct if the face parts move. Flattened to the horizontal: the bilateral
-- axis of an animal is horizontal even when its face tips up or down.
-- ===================================================================
local FACE_REL = FACE_PARTS[1].rel.Position
local FWD = Vector3.new(FACE_REL.X, 0, FACE_REL.Z).Unit
local SIDE = Vector3.new(-FWD.Z, 0, FWD.X)

local function luminance(c: Color3): number
	return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
end

-- TWO NUMBERS, because one is not enough -- lifted from BUILD_SKINS' accentFor
-- and kept identical on purpose. Luminance gap alone rejects cream-on-yellow,
-- which in fact reads perfectly well: the separation there is chroma, not
-- brightness. RGB distance catches what luminance misses.
local function contrast(base: Color3, acc: Color3): (number, number)
	local dr, dg, db = acc.R - base.R, acc.G - base.G, acc.B - base.B
	return math.abs(luminance(acc) - luminance(base)), math.sqrt(dr*dr + dg*dg + db*db)
end

-- Colour at a point on a stop list, stops sorted by position.
local function rampAt(stops, h: number): (number, number, number)
	if h <= stops[1][1] then
		local c = stops[1][2]
		return c.R, c.G, c.B
	end
	for i = 1, #stops - 1 do
		local a, b = stops[i], stops[i + 1]
		if h <= b[1] then
			local u = (h - a[1]) / math.max(b[1] - a[1], 1e-9)
			local ca, cb = a[2], b[2]
			return ca.R + (cb.R - ca.R) * u,
				ca.G + (cb.G - ca.G) * u,
				ca.B + (cb.B - ca.B) * u
		end
	end
	local c = stops[#stops][2]
	return c.R, c.G, c.B
end

local function smoothstep(e0: number, e1: number, x: number): number
	local u = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return u * u * (3 - 2 * u)
end

-- Chebyshev meridian stripes, seamless and twistable -- the one shape family
-- already proven on this mesh. Returns a signed distance, white where positive.
local function stripeField(qx: number, qy: number, qz: number,
	k: number, phase: number, twist: number, yHalf: number): number
	local r = math.sqrt(qx * qx + qz * qz)
	if r < 1e-9 then return 0 end
	local c, sth = qx / r, qz / r
	local t0, t1 = 1.0, c
	local u0, u1 = 1.0, 2 * c
	for _ = 2, k do
		t0, t1 = t1, 2 * c * t1 - t0
		u0, u1 = u1, 2 * c * u1 - u0
	end
	local h = math.clamp(qy / yHalf, -1, 1)
	local a = k * (phase + twist * h / 2)
	local f = t1 * math.cos(a) + sth * u0 * math.sin(a)
	local slope = twist / (2 * yHalf)
	return f / (k * math.sqrt(1 / (r * r) + slope * slope))
end

-- ===================================================================
-- THE TEN VARIANTS.
--
-- Every one is g(q): white wherever g < k, so a LARGER k always means MORE
-- white and one monotone bisection calibrates all ten. g is distance-like in
-- every case, which is what lets a single EDGE_SOFT antialias all of them.
--
-- f = forward (toward the face), s = sideways, y = up. Anything using s*s or
-- |s| is bilaterally symmetric -- the way a marking on an animal is.
--
-- TWO OPTIONAL FIELDS, both there so a shape can be A/B'd against ITSELF with
-- everything else held fixed -- which is the only way the comparison means
-- anything, exactly as the shared white fraction is:
--     heat  = function returning 0..1, and `stops`, a colour ramp over it.
--             Together these replace `white`/`core` entirely: see THE RAMP AND
--             THE MEASUREMENTS in the header before using them.
--     target = number  coverage for THIS variant. 28% is a rule about white
--             diluting a hue; a variant whose accent IS the hue is not bound
--             by it.
--     white = Color3   the accent for this variant only (default COLOUR_WHITE)
--     soft  = number   boundary half-width for this variant (default EDGE_SOFT)
-- Both were added after an A/B that found neither of them is what makes
-- countershade read as shadow. Keep them: proving a knob does NOT matter is
-- worth as much as proving one does, and it should not cost a scratch edit.
--
-- AND ONE THAT IS NOT A KNOB:
--     core = { color = Color3, fraction = number }
-- See THE SECOND ACCENT below. It changes what a skin IS, not how it is tuned.
-- ===================================================================
local YHALF = 0.6773     -- body half-height in body-radii; refined at build time


-- ===================================================================
-- THE DOT FIELD.
--
-- EQUAL AREA ON THE SPHEROID, NOT EQUAL STEPS IN UV. A UV grid bunches at the
-- crown, because that is exactly where the unwrap crowds every u column into
-- one point -- the "dumpling pleats" failure BUILD_GALAXY documents. Latitude
-- rings do the same thing more politely. So the dots are placed by SURFACE
-- AREA of the actual body: the body is a surface of revolution with equatorial
-- semi-axis 1 and polar semi-axis YHALF, its area element is
--     dA = 2*pi * sin(t) * sqrt(cos(t)^2 + YHALF^2 * sin(t)^2) dt
-- which is integrated once into a table and inverted, so dot i sits at the
-- latitude holding (i + 0.5)/n of the total area. Longitude is the golden
-- angle, which never repeats and so never lines dots up into a seam.
--
-- THERE IS NO POLE TO RUN OUT OF. Nothing here is parameterised by longitude,
-- so no count converges anywhere: the crown is just another patch of area and
-- gets its share of dots. That is the whole reason for choosing area over UV.
--
-- PERFECT REGULARITY IS NOT AVAILABLE AND THIS IS NOT A SHORTCUT. Only 4, 6, 8,
-- 12 and 20 points can be placed on a sphere all-equidistant -- the Platonic
-- solids -- and the body is not even a sphere. For every other count the best
-- that exists is EVENLY SPACED, not identically spaced, and the spread is
-- measured and reported below rather than asserted away.
--
-- THE PROFILE IS THE MESH'S OWN, AND THIS IS THE FIX FOR A MEASURED DEFECT.
-- The first version of this integrated a perfect spheroid. The body is a DOME,
-- rounder on top than underneath, so every band got the dot count that a shape
-- the body only approximates would deserve. White share per height band,
-- base -> crown, 24 dots:
--     ideal spheroid    18.6 18.0 29.3 34.9 35.1 33.9 34.0 34.7   spread 17.1
--     measured profile  22.0 30.9 28.5 30.6 30.8 30.9 30.9 29.8   spread  8.9
-- A monotone tilt toward the crown, replaced by a flat profile with one low
-- band at the base. The lit ratio agrees from different evidence: 1.23 -> 1.08
-- against an ideal of 1.00, and J stops climbing with dot count -- 0.12/0.17/
-- 0.25 across 12/24/40 dots became 0.09/0.09/0.10, because that climb WAS the
-- bias rather than anything about density.
--
-- THE EMPTY-BUCKET TRAP IS REAL HERE TOO, and it is BUILD_TIERMARKS' trap
-- exactly: this mesh fills 54 of 96 bands, so 42 are empty. Interpolating into
-- those zeros collapses the radius to roughly a quarter of true. Over there it
-- buried marks inside the body across two invisible builds; here it would put a
-- whole latitude of dots inside the slime. Only non-empty bands are samples.
--
-- DO NOT VALIDATE THIS BY COUNTING PIXELS DOWN THE POLE. That check was tried
-- and it cannot resolve the question: an axis-on view sees the pole face-on and
-- the flanks edge-on, so it over-reads white at whichever pole faces the camera
-- no matter how the dots are placed. It moved 46.1% -> 42.8% at the crown while
-- the actual distribution error halved. Per-band share on the texel set is the
-- instrument that works.
--
-- STILL UNCORRECTED, and much smaller: dot SIZE is not constant. The threshold
-- is a fixed distance in 3D and the body is flatter at the poles, so the same
-- radius cuts a wider patch there. That is most of the residual base band above.
-- Correcting it means scaling the threshold by local curvature.
-- ===================================================================
local DOT_CACHE = {}
local DOT_ORDER = {}
local DOT_NOTES = {}

-- The measured silhouette, installed by run() before any variant is evaluated.
local PROFILE: { { number } }? = nil
local PROFILE_Y0, PROFILE_Y1 = -0.6773, 0.6773

local function radiusAt(t: number): number
	local sm = PROFILE :: { { number } }
	t = math.clamp(t, 0, 1)
	if t <= sm[1][1] then return sm[1][2] end
	if t >= sm[#sm][1] then return sm[#sm][2] end
	for i = 1, #sm - 1 do
		local a, b = sm[i], sm[i + 1]
		if t >= a[1] and t <= b[1] then
			return a[2] + (b[2] - a[2]) * ((t - a[1]) / (b[1] - a[1]))
		end
	end
	return sm[#sm][2]
end

local function dotCentres(n: number)
	if DOT_CACHE[n] then return DOT_CACHE[n] end
	assert(PROFILE, "[Lab] dot field evaluated before the silhouette was measured")

	-- Cumulative area of the MEASURED surface of revolution. The 2*pi factors
	-- out of both the cumulative sum and the target, so it is left off.
	local STEPS = 4096
	local y0, y1 = PROFILE_Y0, PROFILE_Y1
	local dy = (y1 - y0) / STEPS
	local cum = table.create(STEPS + 1)
	cum[1] = 0
	for i = 1, STEPS do
		local r0, r1 = radiusAt((i - 1) / STEPS), radiusAt(i / STEPS)
		cum[i + 1] = cum[i] + ((r0 + r1) / 2) * math.sqrt((r1 - r0)^2 + dy * dy)
	end
	local total = cum[STEPS + 1]

	local cx, cy, cz = table.create(n), table.create(n), table.create(n)
	local GA = math.pi * (3 - math.sqrt(5))
	local j = 1
	for i = 0, n - 1 do
		local target = (i + 0.5) / n * total
		while j < STEPS and cum[j + 1] < target do j += 1 end
		local t = (j - 0.5) / STEPS
		local lon = i * GA
		local r = radiusAt(t)
		cx[i + 1] = r * math.cos(lon)
		cy[i + 1] = y0 + (y1 - y0) * t
		cz[i + 1] = r * math.sin(lon)
	end

	-- how even did that actually come out? nearest-neighbour spacing in 3D on
	-- the body itself, plus where the dots sit in height, reported not assumed
	local lo, hi, sum = math.huge, 0, 0
	local topN = 0
	for i = 1, n do
		local best = math.huge
		for k = 1, n do
			if k ~= i then
				local ax, ay, az = cx[i]-cx[k], cy[i]-cy[k], cz[i]-cz[k]
				local d = ax*ax + ay*ay + az*az
				if d < best then best = d end
			end
		end
		best = math.sqrt(best)
		lo = math.min(lo, best); hi = math.max(hi, best); sum += best
		if cy[i] > y0 + 0.8 * (y1 - y0) then topN += 1 end
	end
	DOT_NOTES[n] = string.format(
		"spacing min %.3f mean %.3f max %.3f (max/min %.2f) | %d of %d dots in the top 20%% of height",
		lo, sum / n, hi, hi / lo, topN, n)
	table.insert(DOT_ORDER, n)
	local t = { cx = cx, cy = cy, cz = cz, n = n }
	DOT_CACHE[n] = t
	return t
end

local function dotField(qx: number, qy: number, qz: number, n: number): number
	local d = dotCentres(n)
	local cx, cy, cz = d.cx, d.cy, d.cz
	local best = math.huge
	for i = 1, n do
		local dx, dy, dz = qx - cx[i], qy - cy[i], qz - cz[i]
		local s = dx*dx + dy*dy + dz*dz
		if s < best then best = s end
	end
	return math.sqrt(best)
end



-- =================== THE RAMP, AND WHAT IT DOES TO THE NUMBERS ===========
--
-- A variant may supply `heat(q..., k) -> 0..1` and `stops`, a list of
-- {position, Color3}. Inside the mask the colour is the ramp evaluated at heat
-- rather than a single accent, which is what lets a shape carry a DIRECTION:
-- a flame tongue can be white-hot at its root and fade to the body colour at
-- its tip, and the eye reads that as upward. No threshold can express it.
--
-- THE HONEST PART. Every measurement in this file is defined on a MASK -- a
-- region with a boundary -- and a ramp is not a mask. Rather than keep printing
-- numbers that have quietly stopped meaning what they say:
--
--   COVERAGE still computes, and still positions the flame, BUT IT NO LONGER
--   MEANS "how much of the body looks different". Where heat is near zero the
--   ramp equals the body colour, so part of the mask is invisible by design.
--   Read it as "how much of the body the field covers", never as how much shows.
--
--   FEATURE SIZE ON THE MASK BECOMES MEANINGLESS, and this is the dangerous
--   one, because it keeps producing a healthy-looking number. It measures a
--   contour that is mostly INVISIBLE -- the tips fade out, so the mask edge is
--   not an edge. For ramp variants the floor is enforced on VISIBLE size
--   instead: 2A/P over the texels whose painted colour differs from the body by
--   more than VIS_THRESHOLD. That is the number that has to clear 8 px, and it
--   is the one the build reports and asserts on.
--
--   J AND lit ARE NOT REPORTED FOR RAMPS. Both are defined on white-versus-not,
--   and both answer "could lighting have produced this?" -- a question fire
--   answers YES to by construction, because fire is a height field. The number
--   would be high and would mean nothing. Worse, it would mean the OPPOSITE of
--   what it means elsewhere: fire is brightest at the BASE, where the light is
--   dimmest, so it contradicts the shading rather than mimicking it. A metric
--   that inverts its meaning on a class of inputs must be switched off for that
--   class, not explained away in a comment next to a number.
--
--   CONTRAST becomes per-stop. One base-against-accent pair is now several, and
--   the pair that matters is the body against the HOTTEST stop.
--
-- This is the third time a number here has kept reporting after its meaning
-- lapsed -- after the pole pixel count that could not see the fix it was
-- measuring, and the IoU that ranked an adjacency it was not measuring. The
-- pattern is the same every time: the number stays computable after the thing
-- it described stops existing.
-- ===========================================================================

-- ========================= FIRE: TWO ATTEMPTS, NEITHER LANDS =============
--
-- Legendary is meant to stop being a shape and become an IMAGE, and fire is the
-- image. Both attempts below are kept because re-deriving them costs what it
-- cost the first time, and because the second one is wrong in a way that says
-- what the third needs.
--
-- ATTEMPT 1 -- plain fbm as a height field, amp 0.5, scale 2.0.
-- Read as a PALE WASH with a wavy top edge. No tongues at all. The measured
-- tell was there before the render: feature sizes of 98 to 207 px, when a
-- flame should be producing far finer boundary than a plain marking. Smooth
-- fbm has no peaks, and flames are peaks.
--
-- ATTEMPT 2 -- ridged noise, squared, advected downward with height, amp 1.15.
-- Feature dropped to 28-41 px, and tongues appeared. They read as DRIPS
-- RUNNING DOWN rather than flames licking up.
--
-- WHY, AND IT IS NOT A SHAPE PROBLEM. A tapering pale streak on a darker body
-- is exactly what a drip looks like. What makes a flame read upward is the
-- COLOUR RAMP ALONG ITS LENGTH -- white-hot at the root, cooling to the hue at
-- the tip -- and this file cannot express that. `core` colours a SMALLER
-- COVERAGE, which on a height field is a horizontal band across the bottom of
-- everything, not a gradient that follows each tongue to its own tip. So every
-- tongue comes out flat-coloured and the direction cue is missing.
--
-- WHAT THE THIRD ATTEMPT NEEDS, and it is structural, not a parameter:
-- a variant must be able to return a RAMP rather than a threshold -- colour as
-- a continuous function of how far up its own tongue a texel sits, normalised
-- per tongue, something like (amp*ridge - t) / (amp*ridge). That is a third
-- colour mode beside `white` and `core`, and it breaks the assumption every
-- measurement here rests on: that a skin is regions with boundaries. Feature
-- size, white fraction and both light numbers are all defined on a MASK. A ramp
-- has no mask, so either fire keeps a thresholded mask for measurement and
-- ramps only the colour inside it, or the measurements need rethinking.
--
-- AND A TENSION WORTH SETTLING BEFORE ANY OF THAT. Fire wants fine detail and
-- 40 studs forbids it: attempt 2's core is already 9.8 px against the 8 px
-- floor. Breaking the tips into separate embers -- which is what would most
-- sell the direction -- goes straight under it. Fire at this distance may have
-- to be a FEW BOLD TONGUES rather than many fine ones, which is a different
-- picture from the one the word "fire" suggests.
--
-- WHAT DID WORK, MEASURED: the hue survives fire better than it survives the
-- rung below it. Share of body pixels where blue clearly dominates red:
--     bare          88.3%
--     fire-ember2   84.6%
--     fire-lick2    82.5%
--     fire-engulf2  76.9%
--     dots24        66.6%   <- the current Rare rung
-- Because the flames are themselves in the hue family -- a luminance ramp
-- within the hue rather than a separate fire colour -- while white dots are
-- neutral. SO THE ANSWER TO "how does the hue survive" IS: THE FLAMES ARE THE
-- HUE. A blue slime burns blue. Orange flames would read as an orange slime,
-- and the tier colour is already carried elsewhere (SLIME_TIER_COLORS).
-- ===========================================================================
-- ===================================================================
-- VALUE NOISE, lifted verbatim from BUILD_GALAXY so the two files cannot
-- drift: same integer hash, same trilinear smoothstep interpolation, same
-- fbm. Reproducible bit-for-bit from the seed, which is what lets a skin be
-- regenerated rather than stored.
-- ===================================================================
local function ihash(x: number, y: number, z: number, s: number): number
	local h = bit32.bxor(
		(x * 374761393) % 4294967296,
		(y * 668265263) % 4294967296,
		(z * 1103515245) % 4294967296,
		(s * 2654435761) % 4294967296
	)
	h = bit32.bxor(h, bit32.rshift(h, 15))
	h = (h * 40503) % 4294967296
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = (h * 40503) % 4294967296
	return bit32.bxor(h, bit32.rshift(h, 16))
end

local function hnorm(x: number, y: number, z: number, s: number): number
	return ihash(x, y, z, s) / 4294967296
end

local function vnoise3(x: number, y: number, z: number, s: number): number
	local ix, iy, iz = math.floor(x), math.floor(y), math.floor(z)
	local fx, fy, fz = x - ix, y - iy, z - iz
	local ux = fx * fx * (3 - 2 * fx)
	local uy = fy * fy * (3 - 2 * fy)
	local uz = fz * fz * (3 - 2 * fz)
	local c000 = hnorm(ix, iy, iz, s)
	local c100 = hnorm(ix + 1, iy, iz, s)
	local c010 = hnorm(ix, iy + 1, iz, s)
	local c110 = hnorm(ix + 1, iy + 1, iz, s)
	local c001 = hnorm(ix, iy, iz + 1, s)
	local c101 = hnorm(ix + 1, iy, iz + 1, s)
	local c011 = hnorm(ix, iy + 1, iz + 1, s)
	local c111 = hnorm(ix + 1, iy + 1, iz + 1, s)
	local x00 = c000 + (c100 - c000) * ux
	local x10 = c010 + (c110 - c010) * ux
	local x01 = c001 + (c101 - c001) * ux
	local x11 = c011 + (c111 - c011) * ux
	local y0 = x00 + (x10 - x00) * uy
	local y1 = x01 + (x11 - x01) * uy
	return y0 + (y1 - y0) * uz
end

local function fbm3(x: number, y: number, z: number, oct: number, s: number): number
	local sum, amp, norm, f = 0, 1, 0, 1
	for _ = 1, oct do
		sum += amp * vnoise3(x * f, y * f, z * f, s)
		norm += amp
		amp *= 0.5
		f *= 2
	end
	return sum / norm
end

-- ===================================================================
-- THE FLAME FIELD. FIRE HAS A DIRECTION, WHICH IS THE WHOLE DIFFERENCE
-- FROM GALAXY. Galaxy's nebula is isotropic -- it looks the same whichever way
-- the body is turned, which is right for a sky and wrong for a flame. Here:
--
--   THE NOISE IS SAMPLED COMPRESSED IN Y, so its features come out TALL.
--   Isotropic noise gives blobs, and blobs read as mould, not fire. VSTRETCH
--   below is how many times taller than wide a tongue is.
--
--   IT IS A HEIGHT FIELD, NOT A DENSITY. The flame reaches a height that
--   varies with where you are around the body, and burns everything below it.
--   That is what makes tongues lick UPWARD from a common base instead of
--   floating as detached patches.
--
--   THE HOTTEST PART IS THE BASE, and this comes out for free. The core is
--   calibrated to a SMALLER coverage than the flame, and a smaller coverage of
--   a height field is the lower part of it. Fire is hottest at its root; this
--   is the one place where the existing two-accent machinery happens to model
--   the physics rather than merely allow it.
-- ===================================================================
-- FEW BOLD TONGUES, NOT MANY FINE ONES. 40 studs decides this: embers and
-- fine tips land under the 8 px floor, and a feature that half-resolves is the
-- failure this project keeps rediscovering. So the noise runs at ONE octave and
-- a low scale -- big, confident shapes -- and the detail budget is spent on the
-- colour ramp instead, which costs no resolution at all.
local function flameHeight(qx: number, qy: number, qz: number,
	scale: number, vstretch: number, amp: number, seed: number): number
	local t = (qy - PROFILE_Y0) / math.max(PROFILE_Y1 - PROFILE_Y0, 1e-9)
	-- ADVECTION: the sample drifts as t rises, so a tongue leans and narrows
	-- on the way up instead of standing as a vertical stripe.
	local n = fbm3(qx * scale, qy * scale / vstretch - t * 1.1, qz * scale, 1, seed)
	-- SPIKE WHERE THE NOISE IS EXTREME, NOT WHERE IT IS AVERAGE. The usual
	-- ridged form 1 - |2n-1| peaks at n = 0.5, which for value noise is the
	-- COMMONEST value -- so it produces broad plateaus separated by thin
	-- valleys, i.e. a flat band, which is exactly what the first two ramp
	-- builds rendered. |2n-1| is near zero for most of the body and reaches 1
	-- only rarely, so squaring it leaves a few tall tongues over a quiet base.
	local d = math.abs(2 * n - 1)
	return amp * d * d
end

local function flameT(qy: number): number
	return (qy - PROFILE_Y0) / math.max(PROFILE_Y1 - PROFILE_Y0, 1e-9)
end


-- ===================== THE OUTLINE, AND WHAT IT CANNOT BE ================
--
-- A REAL RIM IS VIEW-DEPENDENT AND A BAKED TEXTURE CANNOT BE. Fresnel lights
-- the edge because it asks where the CAMERA is, every frame. A texture is
-- painted once and knows nothing about the viewer, and Roblox exposes no shader
-- hook on a MeshPart's texture to ask. So what follows is not a rim: it is a
-- rim BAKED FOR ONE DIRECTION, and that direction is the face.
--
-- WHICH IS CORRECT HEAD-ON AND WRONG FROM ANYWHERE ELSE. The set of points
-- whose normal is perpendicular to a fixed direction is a great circle; from
-- that direction it is exactly the silhouette, and as the body turns the bright
-- band slides across the surface and stops coinciding with the edge. Every shot
-- in this file is head-on at 40 studs, so the lab cannot see this failure --
-- which is precisely why it is written down here rather than discovered later.
-- BEFORE SHIPPING IT, settle whether a slime ever presents another face.
--
-- WHAT IS YAW-INDEPENDENT, if it turns out slimes do turn: a band near the TOP
-- (and bottom) of the body sits on the silhouette from EVERY horizontal
-- direction, because those normals point up and are grazing to any horizontal
-- view. A top-and-bottom rim survives rotation; a full outline does not. It is
-- a different picture -- a lit crown rather than an outline -- so it is a
-- design decision, not a fallback.
--
-- Galaxy, incidentally, had no rim term at all. Its EDGE_COLOR is the
-- low-density end of the nebula ramp; the lighter edges being remembered are
-- cloud, not silhouette.
-- ===========================================================================

-- ===================================================================
-- TONGUES ARE PLACED, NOT THRESHOLDED. This is attempt five, and the change is
-- the same one that rescued the dot field after two failures at scattered
-- spots: STOP HOPING A NOISE FIELD PRODUCES THE FEATURE AND PUT THE FEATURE
-- WHERE YOU WANT IT.
--
-- Attempts one to four all thresholded smooth noise and all failed for the
-- same underlying reason, however different they looked. Smooth noise has no
-- lateral contrast: neighbouring columns differ only slightly, so the result is
-- always a band, a drip or a gradient -- never a countable tongue with a gap
-- beside it. A tongue needs its neighbour to be BODY, sharply.
--
-- So N azimuths are chosen outright, each gets a width and a height, and noise
-- is demoted to perturbing what is already there. The count is a parameter
-- instead of an emergent accident, which is what "four or five bold tongues"
-- requires -- you cannot ask a noise threshold for exactly five of anything.
--
-- NO atan2, for the same reason stripeField has none: the branch cut is a seam
-- waiting to happen. Proximity to a tongue is a DOT PRODUCT against a horizontal
-- unit vector, which is continuous everywhere including across the wrap.
-- ===================================================================
local TONGUE_CACHE = {}

local function tongueDirs(n: number, seed: number)
	local key = n * 1000 + seed
	if TONGUE_CACHE[key] then return TONGUE_CACHE[key] end
	local dx, dz, hj = table.create(n), table.create(n), table.create(n)
	for i = 1, n do
		local a = 2 * math.pi * (i - 1) / n
		dx[i], dz[i] = math.cos(a), math.sin(a)
		-- per-tongue height, so they are not a row of identical spikes
		hj[i] = 0.70 + 0.60 * hnorm(i, 7, 13, seed)
	end
	local t = { dx = dx, dz = dz, hj = hj, n = n }
	TONGUE_CACHE[key] = t
	return t
end

local function tongueHeight(qx: number, qy: number, qz: number,
	n: number, halfCos: number, amp: number, seed: number): number
	local r = math.sqrt(qx * qx + qz * qz)
	if r < 1e-6 then return 0 end
	local ux, uz = qx / r, qz / r
	local T = tongueDirs(n, seed)
	local best, bestI = -2, 1
	for i = 1, n do
		local c = ux * T.dx[i] + uz * T.dz[i]
		if c > best then best, bestI = c, i end
	end
	-- outside the tongue's own width there is NO flame at all: this is the
	-- lateral contrast that every noise-threshold attempt failed to produce
	if best <= halfCos then return 0 end
	local w = (best - halfCos) / (1 - halfCos)
	w = w * w * (3 - 2 * w)
	-- SHARPENING THE PROFILE WAS TRIED (w^2.2) AND MADE IT WORSE, which is
	-- worth keeping because the reason is not obvious. Narrowing the tongue
	-- lowers coverage, so the bisection raises k to compensate, and a larger k
	-- scales every tongue BOTH taller and wider at the root. The tips came out
	-- blunter than before and the tongues read as broad panels. Under a
	-- calibrated field you cannot change one dimension of a shape in isolation;
	-- the calibration gives back whatever area you take away.
	local t = flameT(qy)
	local nz = fbm3(qx * 2.2, qy * 0.55 - t * 1.1, qz * 2.2, 1, seed + 3)
	return amp * T.hj[bestI] * w * (0.80 + 0.40 * nz)
end

local VARIANTS = {
	-- ---- outline: a rim baked for the head-on view ----------------------
	-- See THE OUTLINE above for the one thing that matters about these.
	-- |f/l| is how far the surface normal points along the face axis, so it is
	-- 0 exactly on the head-on silhouette and 1 at the nose and the tail.
	{
		name = "rim-thin",
		note = "narrow bright outline, nothing else",
		target = 0.16,
		g = function(qx, qy, qz, f, s, y)
			local l = math.sqrt(qx * qx + qy * qy + qz * qz)
			return l < 1e-9 and 9 or math.abs(f / l)
		end,
		heat = function(qx, qy, qz, f, s, y, k)
			local l = math.sqrt(qx * qx + qy * qy + qz * qz)
			if l < 1e-9 or k <= 1e-6 then return 0 end
			return math.clamp(1 - math.abs(f / l) / k, 0, 1)
		end,
		stops = function(base)
			return { { 0.00, base }, { 1.00, Color3.new(
				base.R + (1 - base.R) * 0.80,
				base.G + (1 - base.G) * 0.80,
				base.B + (1 - base.B) * 0.80) } }
		end,
	},
	{
		name = "rim-thick",
		note = "the same outline, twice the depth",
		target = 0.34,
		g = function(qx, qy, qz, f, s, y)
			local l = math.sqrt(qx * qx + qy * qy + qz * qz)
			return l < 1e-9 and 9 or math.abs(f / l)
		end,
		heat = function(qx, qy, qz, f, s, y, k)
			local l = math.sqrt(qx * qx + qy * qy + qz * qz)
			if l < 1e-9 or k <= 1e-6 then return 0 end
			return math.clamp(1 - math.abs(f / l) / k, 0, 1)
		end,
		stops = function(base)
			return { { 0.00, base }, { 1.00, Color3.new(
				base.R + (1 - base.R) * 0.80,
				base.G + (1 - base.G) * 0.80,
				base.B + (1 - base.B) * 0.80) } }
		end,
	},
	{
		-- The mask is the WHOLE body here and the ramp does all the work, which
		-- is the other thing ramp mode buys: a treatment with no boundary at all.
		name = "rim-body",
		note = "outline plus a faint mottling across the body",
		target = 0.98,
		g = function(qx, qy, qz, f, s, y)
			local l = math.sqrt(qx * qx + qy * qy + qz * qz)
			return l < 1e-9 and 9 or math.abs(f / l)
		end,
		heat = function(qx, qy, qz, f, s, y, k)
			local l = math.sqrt(qx * qx + qy * qy + qz * qz)
			if l < 1e-9 then return 0 end
			local rim = math.clamp(1 - math.abs(f / l) / 0.30, 0, 1)
			local mottle = fbm3(qx * 1.6, qy * 1.6, qz * 1.6, 2, 91) - 0.5
			return math.clamp(rim * 0.92 + mottle * 0.42, 0, 1)
		end,
		stops = function(base)
			return { { 0.00, base }, { 1.00, Color3.new(
				base.R + (1 - base.R) * 0.80,
				base.G + (1 - base.G) * 0.80,
				base.B + (1 - base.B) * 0.80) } }
		end,
	},
	-- ---- Legendary: fire, tongues placed explicitly ---------------------
	-- The tip stop IS the body colour, so a tongue fades out rather than
	-- ending at an edge -- which is also why the mask's feature size stopped
	-- meaning anything and the floor moved to VISIBLE size.
	--
	-- The stops are a FUNCTION of the base, so the flames carry whatever hue
	-- the slime is: measured, fire in the hue family preserved hue better than
	-- the white dot field one rung below it, 82.5% against 66.6%.
	{
		name = "fire-t5",
		note = "five placed tongues, white-hot roots fading to the hue",
		target = 0.45,
		g = function(qx, qy, qz, f, s, y)
			return flameT(qy) / math.max(tongueHeight(qx, qy, qz, 5, 0.90, 1.30, 17), 1e-3)
		end,
		heat = function(qx, qy, qz, f, s, y, k)
			local h = k * tongueHeight(qx, qy, qz, 5, 0.90, 1.30, 17)
			return h > 1e-6 and math.clamp(1 - flameT(qy) / h, 0, 1) or 0
		end,
		stops = function(base)
			local function toward(u)
				return Color3.new(base.R + (1 - base.R) * u,
					base.G + (1 - base.G) * u, base.B + (1 - base.B) * u)
			end
			return { { 0.00, base }, { 0.35, toward(0.50) }, { 1.00, Color3.new(1, 1, 1) } }
		end,
	},
	{
		name = "fire-t4",
		note = "four placed tongues, wider each",
		target = 0.45,
		g = function(qx, qy, qz, f, s, y)
			return flameT(qy) / math.max(tongueHeight(qx, qy, qz, 4, 0.86, 1.40, 17), 1e-3)
		end,
		heat = function(qx, qy, qz, f, s, y, k)
			local h = k * tongueHeight(qx, qy, qz, 4, 0.86, 1.40, 17)
			return h > 1e-6 and math.clamp(1 - flameT(qy) / h, 0, 1) or 0
		end,
		stops = function(base)
			local function toward(u)
				return Color3.new(base.R + (1 - base.R) * u,
					base.G + (1 - base.G) * u, base.B + (1 - base.B) * u)
			end
			return { { 0.00, base }, { 0.35, toward(0.50) }, { 1.00, Color3.new(1, 1, 1) } }
		end,
	},
	{
		name = "fire-t5-hot",
		note = "five tongues, white carried further up each one",
		target = 0.45,
		g = function(qx, qy, qz, f, s, y)
			return flameT(qy) / math.max(tongueHeight(qx, qy, qz, 5, 0.90, 1.30, 17), 1e-3)
		end,
		heat = function(qx, qy, qz, f, s, y, k)
			local h = k * tongueHeight(qx, qy, qz, 5, 0.90, 1.30, 17)
			return h > 1e-6 and math.clamp(1 - flameT(qy) / h, 0, 1) or 0
		end,
		stops = function(base)
			local function toward(u)
				return Color3.new(base.R + (1 - base.R) * u,
					base.G + (1 - base.G) * u, base.B + (1 - base.B) * u)
			end
			return { { 0.00, base }, { 0.25, toward(0.55) }, { 0.60, Color3.new(1, 1, 1) }, { 1.00, Color3.new(1, 1, 1) } }
		end,
	},
	{
		-- Common. Calibration is skipped for it -- there is no boundary to
		-- place, and bisecting toward 28% white on a shape that has no white
		-- would run the search to its bracket and report nonsense.
		name = "bare",
		note = "no marking at all -- Common",
		solid = true,
		g = function(qx, qy, qz, f, s, y) return 9 end,
	},
	{
		name = "countershade",
		note = "white belly, boundary rising toward the face and dipping at the flanks",
		g = function(qx, qy, qz, f, s, y) return y - 0.55 * f + 0.35 * s * s end,
	},
	{
		name = "bib",
		note = "oval breast patch on the lower front, like a bird's",
		g = function(qx, qy, qz, f, s, y)
			local l = math.sqrt(qx * qx + qy * qy + qz * qz)
			if l < 1e-9 then return 9 end
			-- taller than wide: squash the sideways axis before measuring the cap
			local d = (f * 0.72 - y * 0.69) / l - 0.45 * (s / l) * (s / l)
			return -d
		end,
	},
	{
		name = "blaze",
		note = "one band over the crown, front to back, like a badger",
		g = function(qx, qy, qz, f, s, y) return math.abs(s) end,
	},
	{
		name = "socks",
		note = "white only at the base, a flat foot",
		g = function(qx, qy, qz, f, s, y) return y end,
	},
	{
		name = "cap-tilt",
		note = "white crown, tilted back off the face",
		g = function(qx, qy, qz, f, s, y) return -(y + 0.40 * f) end,
	},
	{
		name = "collar",
		note = "band around the shoulders, dipping at the front",
		g = function(qx, qy, qz, f, s, y) return math.abs(y - (0.10 + 0.38 * f)) end,
	},
	{
		name = "muzzle",
		note = "white around the face itself, hue everywhere else",
		g = function(qx, qy, qz, f, s, y)
			local l = math.sqrt(qx * qx + qy * qy + qz * qz)
			return l < 1e-9 and 9 or -(f / l)
		end,
	},
	{
		name = "backdrop",
		note = "one big patch on the back, invisible head-on",
		g = function(qx, qy, qz, f, s, y)
			local l = math.sqrt(qx * qx + qy * qy + qz * qz)
			return l < 1e-9 and 9 or (f / l)
		end,
	},
	{
		-- TAKEN FOR UNCOMMON at 140 deg. At 70 the white read as a specular
		-- smear on a glossy curved body; doubling the twist makes the band
		-- visibly WRAP, and nothing about a highlight wraps. Measured against
		-- the 70 deg version side by side, both at 28% white.
		name = "stripes4",
		note = "four spiral stripes, twist 140 deg -- Uncommon",
		g = function(qx, qy, qz, f, s, y)
			return -stripeField(qx, qy, qz, 2, 0, math.rad(140), YHALF)
		end,
	},
	{
		name = "stripes2",
		note = "two wide spiral stripes, white narrower than hue",
		g = function(qx, qy, qz, f, s, y)
			return -stripeField(qx, qy, qz, 1, 0, math.rad(70), YHALF)
		end,
	},

	-- ---- candidates for Rare -------------------------------------------
	-- Between stripes4 and blaze in boldness: ONE marking rather than four,
	-- but not the whole crown. All three are shaped so their edge cuts ACROSS
	-- the light rather than lying along it, and none is a diagonal sweep.
	{
		name = "flanks",
		note = "one patch down each side, hue over spine, belly and face",
		g = function(qx, qy, qz, f, s, y)
			local l = math.sqrt(qx * qx + qy * qy + qz * qz)
			return l < 1e-9 and 9 or -(math.abs(s) / l)
		end,
	},
	{
		name = "crest",
		note = "band over the crown, stopping short of the face",
		g = function(qx, qy, qz, f, s, y)
			return math.abs(s) + 0.9 * math.max(0, f - 0.15)
		end,
	},
	-- ---- candidates for Epic -------------------------------------------
	-- Bolder than collar, quieter than blaze. The metrics push hard toward
	-- shapes defined by f and s and NOT by y: a marking that never mentions
	-- height cannot be mistaken for a height gradient, which is why these three
	-- sit at the bottom of the J column. None of them covers the face, so none
	-- changes what the creature IS the way plastron and muzzle do.
	{
		name = "dots12",
		note = "12 dots, equal-area on the measured silhouette",
		g = function(qx, qy, qz, f, s, y) return dotField(qx, qy, qz, 12) end,
	},
	{
		name = "dots24",
		note = "24 dots, equal-area on the measured silhouette -- Rare",
		g = function(qx, qy, qz, f, s, y) return dotField(qx, qy, qz, 24) end,
	},
	{
		name = "dots40",
		note = "40 dots, equal-area on the measured silhouette",
		g = function(qx, qy, qz, f, s, y) return dotField(qx, qy, qz, 40) end,
	},
	{
		name = "mane",
		note = "ring around the face, hue inside it and behind it",
		g = function(qx, qy, qz, f, s, y)
			local l = math.sqrt(qx * qx + qy * qy + qz * qz)
			return l < 1e-9 and 9 or math.abs(f / l - 0.45)
		end,
	},
	{
		name = "brackets",
		note = "one stripe down each side of the face, hue between them",
		g = function(qx, qy, qz, f, s, y)
			local l = math.sqrt(qx * qx + qy * qy + qz * qz)
			return l < 1e-9 and 9 or math.abs(math.abs(s) / l - 0.55)
		end,
	},
	{
		name = "plastron",
		note = "tall shield down the front, from the brow to the belly",
		g = function(qx, qy, qz, f, s, y)
			local l = math.sqrt(qx * qx + qy * qy + qz * qz)
			if l < 1e-9 then return 9 end
			-- muzzle, squashed sideways: taller and narrower, so it spans the
			-- light boundary instead of sitting on one side of it
			return -(f / l) + 0.8 * (s / l) * (s / l)
		end,
	},
}

local function newYielder(budgetMs: number)
	local budget, last = budgetMs / 1000, os.clock()
	local worst = 0
	return {
		tick = function()
			local held = os.clock() - last
			if held >= budget then
				if held > worst then worst = held end
				task.wait()
				last = os.clock()
			end
		end,
		mark = function() last = os.clock() end,
		worstMs = function(): number return worst * 1000 end,
	}
end

-- ===================================================================
-- THE UV -> 3D MAP. BUILD_SKINS' pipeline, including its ownership rule:
-- containment class first, outwardness breaking ties, never interiority
-- magnitude. Strays excluded by distance from the centroid, never by a Y test.
-- ===================================================================
local function buildUVMap(meshId: string, W: number, Y)
	local em = AssetService:CreateEditableMeshAsync(Content.fromUri(meshId))
	local verts, faces = em:GetVertices(), em:GetFaces()
	Y.mark()

	local sx, sy, sz = 0, 0, 0
	for _, id in ipairs(verts) do
		Y.tick()
		local p = em:GetPosition(id)
		sx += p.X; sy += p.Y; sz += p.Z
	end
	local gx, gy, gz = sx / #verts, sy / #verts, sz / #verts
	local dsum = 0
	for _, id in ipairs(verts) do
		Y.tick()
		local p = em:GetPosition(id)
		dsum += math.sqrt((p.X-gx)^2 + (p.Y-gy)^2 + (p.Z-gz)^2)
	end
	local dmean = dsum / #verts
	local isStray: { [number]: boolean } = {}
	for _, id in ipairs(verts) do
		Y.tick()
		local p = em:GetPosition(id)
		if math.sqrt((p.X-gx)^2 + (p.Y-gy)^2 + (p.Z-gz)^2) > 8 * dmean then isStray[id] = true end
	end

	local mnx, mxx = math.huge, -math.huge
	local mny, mxy = math.huge, -math.huge
	local mnz, mxz = math.huge, -math.huge
	local amnx, amxx = math.huge, -math.huge
	for _, id in ipairs(verts) do
		Y.tick()
		local p = em:GetPosition(id)
		amnx = math.min(amnx, p.X); amxx = math.max(amxx, p.X)
		if not isStray[id] then
			mnx = math.min(mnx, p.X); mxx = math.max(mxx, p.X)
			mny = math.min(mny, p.Y); mxy = math.max(mxy, p.Y)
			mnz = math.min(mnz, p.Z); mxz = math.max(mxz, p.Z)
		end
	end
	local CX, CY, CZ = (mnx+mxx)/2, (mny+mxy)/2, (mnz+mxz)/2
	local RAD = (mxx - mnx) / 2

	-- ===================================================================
	-- THE MEASURED SILHOUETTE. Lifted from BUILD_TIERMARKS' buildProfile:
	-- 96 height bands, the MAX radius in each, and -- the part that matters --
	-- ONLY NON-EMPTY BUCKETS become interpolation samples. The vertices sit in
	-- discrete latitude rings, so a large minority of the bands contain none at
	-- all; interpolating into a zero collapses the radius to about a quarter of
	-- true, which over there buried every mark inside the body across two
	-- entirely invisible builds. Here it would put a whole latitude of dots
	-- inside the slime instead. Same trap, different symptom.
	-- Built in this pass rather than a second one: the vertices are already open.
	-- ===================================================================
	local PB = 96
	local bucket = table.create(PB, 0)
	for _, id in ipairs(verts) do
		Y.tick()
		if not isStray[id] then
			local p = em:GetPosition(id)
			local tb = (p.Y - mny) / math.max(mxy - mny, 1e-9)
			local bi = math.clamp(math.floor(tb * PB) + 1, 1, PB)
			local rr = math.sqrt((p.X-CX)^2 + (p.Z-CZ)^2) / RAD
			if rr > bucket[bi] then bucket[bi] = rr end
		end
	end
	local profile, filled = {}, 0
	for bi = 1, PB do
		if bucket[bi] > 0 then
			filled += 1
			table.insert(profile, { (bi - 0.5) / PB, bucket[bi] })
		end
	end
	assert(#profile >= 8, string.format(
		"[Lab] silhouette profile has only %d non-empty bands of %d -- too few to interpolate",
		#profile, PB))

	local POS = buffer.create(W*W*12)
	local PRIO = buffer.create(W*W*8)
	local MASK = buffer.create(W*W)
	local covered = 0

	for _, f in ipairs(faces) do
		Y.tick()
		local fv = em:GetFaceVertices(f)
		if isStray[fv[1]] or isStray[fv[2]] or isStray[fv[3]] then continue end
		local p1,p2,p3 = em:GetPosition(fv[1]), em:GetPosition(fv[2]), em:GetPosition(fv[3])
		local fu = em:GetFaceUVs(f)
		local a,b,c = em:GetUV(fu[1]), em:GetUV(fu[2]), em:GetUV(fu[3])
		local e1x,e1y,e1z = p2.X-p1.X, p2.Y-p1.Y, p2.Z-p1.Z
		local e2x,e2y,e2z = p3.X-p1.X, p3.Y-p1.Y, p3.Z-p1.Z
		local nx,ny,nz = e1y*e2z-e1z*e2y, e1z*e2x-e1x*e2z, e1x*e2y-e1y*e2x
		local nl = math.sqrt(nx*nx+ny*ny+nz*nz)
		local rx,ry,rz = (p1.X+p2.X+p3.X)/3-CX, (p1.Y+p2.Y+p3.Y)/3-CY, (p1.Z+p2.Z+p3.Z)/3-CZ
		local rl = math.sqrt(rx*rx+ry*ry+rz*rz)
		local outward = (nl > 1e-12 and rl > 1e-12) and (nx*rx+ny*ry+nz*rz)/(nl*rl) or 0

		local u1,u2,u3 = a.X,b.X,c.X
		local v1,v2,v3 = a.Y,b.Y,c.Y
		local umin = math.min(u1,u2,u3)
		if math.max(u1,u2,u3) - umin > 0.5 then
			if u1-umin <= 0.5 then u1 += 1 end
			if u2-umin <= 0.5 then u2 += 1 end
			if u3-umin <= 0.5 then u3 += 1 end
		end
		local x1,y1,x2,y2,x3,y3 = u1*W, v1*W, u2*W, v2*W, u3*W, v3*W
		local d = (y2-y3)*(x1-x3) + (x3-x2)*(y1-y3)
		if math.abs(d) < 1e-12 then continue end
		local inv = 1/d
		for py = math.max(0,math.floor(math.min(y1,y2,y3))), math.min(W-1,math.ceil(math.max(y1,y2,y3))) do
			local fy = py + 0.5
			for px = math.floor(math.min(x1,x2,x3)), math.ceil(math.max(x1,x2,x3)) do
				local fx = px + 0.5
				local l1 = ((y2-y3)*(fx-x3)+(x3-x2)*(fy-y3))*inv
				local l2 = ((y3-y1)*(fx-x3)+(x1-x3)*(fy-y3))*inv
				local l3 = 1-l1-l2
				if l1 >= -0.002 and l2 >= -0.002 and l3 >= -0.002 then
					local idx = py*W + (px % W)
					local o, po = idx*12, idx*8
					local qx = (l1*p1.X+l2*p2.X+l3*p3.X-CX)/RAD
					local qy = (l1*p1.Y+l2*p2.Y+l3*p3.Y-CY)/RAD
					local qz = (l1*p1.Z+l2*p2.Z+l3*p3.Z-CZ)/RAD
					local interior = math.min(l1,l2,l3)
					local wins
					if buffer.readu8(MASK, idx) == 0 then
						buffer.writeu8(MASK, idx, 1); covered += 1; wins = true
					else
						local hi_ = buffer.readf32(PRIO, po)
						local ho = buffer.readf32(PRIO, po+4)
						local ic, hc = interior >= 0, hi_ >= 0
						if ic ~= hc then wins = ic else wins = outward > ho end
					end
					if wins then
						buffer.writef32(POS,o,qx); buffer.writef32(POS,o+4,qy); buffer.writef32(POS,o+8,qz)
						buffer.writef32(PRIO,po,interior); buffer.writef32(PRIO,po+4,outward)
					end
				end
			end
		end
	end
	return {
		POS = POS, MASK = MASK, covered = covered,
		CX = CX, CY = CY, CZ = CZ, RAD = RAD,
		HEIGHT = mxy - mny, FULL_W = amxx - amnx,
		PROFILE = profile, PROFILE_BANDS = PB, PROFILE_FILLED = filled,
		QY0 = (mny - CY) / RAD, QY1 = (mxy - CY) / RAD,
	}
end

local function dilate(POS, MASK, W: number, passes: number, Y): number
	local grown = 0
	for _ = 1, passes do
		local add = {}
		for y = 0, W-1 do
			Y.tick()
			for x = 0, W-1 do
				local idx = y*W + x
				if buffer.readu8(MASK, idx) == 0 then
					local nb = -1
					if x > 0 and buffer.readu8(MASK, idx-1) == 1 then nb = idx-1
					elseif x < W-1 and buffer.readu8(MASK, idx+1) == 1 then nb = idx+1
					elseif y > 0 and buffer.readu8(MASK, idx-W) == 1 then nb = idx-W
					elseif y < W-1 and buffer.readu8(MASK, idx+W) == 1 then nb = idx+W
					end
					if nb >= 0 then table.insert(add, { idx, nb }) end
				end
			end
		end
		for _, pr in ipairs(add) do
			local o, no = pr[1]*12, pr[2]*12
			buffer.writef32(POS,o,buffer.readf32(POS,no))
			buffer.writef32(POS,o+4,buffer.readf32(POS,no+4))
			buffer.writef32(POS,o+8,buffer.readf32(POS,no+8))
			buffer.writeu8(MASK, pr[1], 2); grown += 1
		end
		for _, pr in ipairs(add) do buffer.writeu8(MASK, pr[1], 1) end
	end
	return grown
end

-- ===================================================================
-- BUILD.
-- ===================================================================
local function run()
	local lines = {}
	local function log(...) table.insert(lines, string.format(...)) end
	local t0 = os.clock()

	local src: BasePart? = nil
	for _, name in ipairs(P.SOURCE_MODELS) do
		local assets = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
		local m = (assets and assets:FindFirstChild(name)) or workspace:FindFirstChild(name)
		if m then
			local best, bestVol = nil, -1
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("MeshPart") then
					local v = d.Size.X * d.Size.Y * d.Size.Z
					if v > bestVol then best, bestVol = d :: BasePart, v end
				end
			end
			if best then src = best break end
		end
	end
	assert(src, "[Lab] no MeshPart found under any of {" .. table.concat(P.SOURCE_MODELS, ", ") .. "}")
	local source = src :: BasePart
	log("[Lab] source: %s", source:GetFullName())

	local W = P.TEX
	local Y = newYielder(P.YIELD_MS)
	local M = buildUVMap((source :: any).MeshId, W, Y)
	local coverage = M.covered / (W * W)
	assert(coverage > 0.10, string.format(
		"[Lab] source mesh covers only %.2f%% of the sheet -- no usable UV unwrap", coverage * 100))
	log("[Lab] UV map: %d texels (%.1f%% of sheet)", M.covered, coverage * 100)
	log("[Lab] silhouette: %d non-empty of %d height bands, radius %.3f at the base to %.3f at the crown",
		M.PROFILE_FILLED, M.PROFILE_BANDS, M.PROFILE[1][2], M.PROFILE[#M.PROFILE][2])

	local POS, MASK = M.POS, M.MASK
	dilate(POS, MASK, W, 3, Y)

	local bodySizeX = P.BODY_WIDTH_STUDS * M.FULL_W / (2 * M.RAD)
	local partScale = bodySizeX / source.Size.X
	local studsPerMeshUnit = bodySizeX / M.FULL_W
	local bodyRadiusStuds = M.RAD * studsPerMeshUnit
	local bodyHeightStuds = M.HEIGHT * studsPerMeshUnit
	YHALF = (M.HEIGHT / M.RAD) / 2
	PROFILE = M.PROFILE
	PROFILE_Y0, PROFILE_Y1 = M.QY0, M.QY1
	local pxPerStud = P.VIEW_FRAME_PX / (2 * P.VIEW_DISTANCE * math.tan(math.rad(P.VIEW_FOV_DEG) / 2))
	log("[Lab] body %.2f studs across, %.2f px/stud at %d studs, white target %.0f%%",
		2 * bodyRadiusStuds, pxPerStud, P.VIEW_DISTANCE, P.WHITE_TARGET * 100)

	-- sample subset, with the face-frame components precomputed once
	local sample = {}
	do
		local n = 0
		for idx = 0, W*W - 1 do
			if buffer.readu8(MASK, idx) == 1 then
				n += 1
				if n % P.SAMPLE_STRIDE == 0 then
					local o = idx*12
					local qx = buffer.readf32(POS,o)
					local qy = buffer.readf32(POS,o+4)
					local qz = buffer.readf32(POS,o+8)
					table.insert(sample, { qx, qy, qz,
						qx*FWD.X + qz*FWD.Z, qx*SIDE.X + qz*SIDE.Z })
				end
			end
		end
	end

	local function whiteAt(v, qx, qy, qz, f, s, k)
		local soft = v.soft or P.EDGE_SOFT
		return smoothstep(-soft, soft, k - v.g(qx, qy, qz, f, s, qy))
	end

	-- one monotone bisection calibrates every shape, because g is written so a
	-- larger k always admits more white
	local function calibrate(v, target: number): (number, number)
		local lo, hi, got = P.SEARCH_LO, P.SEARCH_HI, 0
		for _ = 1, P.SEARCH_ITERS do
			local mid = (lo + hi) / 2
			local hit = 0
			for si, q in ipairs(sample) do
				if si % P.TICK_EVERY == 0 then Y.tick() end
				hit += whiteAt(v, q[1], q[2], q[3], q[4], q[5], mid)
			end
			got = hit / #sample
			if math.abs(got - target) <= P.WHITE_TOLERANCE then return mid, got end
			if got < target then lo = mid else hi = mid end
		end
		return (lo + hi) / 2, got
	end

	-- ===================================================================
	-- THE TERMINATOR RULE, MEASURED.
	-- All a light does is fall off monotonically from top to bottom, so "could
	-- lighting have drawn this marking?" is exactly "how well does a single
	-- height threshold predict where the white is?". This returns Youden's J of
	-- the best such threshold: 1 means a light draws it exactly, 0 means height
	-- tells you nothing at all about where the white went.
	-- ===================================================================
	local function lightFit(v, k: number): (number, number)
		local B = P.SHADOW_BINS
		local wHist, nHist = table.create(B, 0), table.create(B, 0)
		local lo, hi = math.huge, -math.huge
		for _, q in ipairs(sample) do
			if q[2] < lo then lo = q[2] end
			if q[2] > hi then hi = q[2] end
		end
		local span = math.max(hi - lo, 1e-9)
		local white, total = 0, 0
		local litWhite, litAll = 0, 0
		for si, q in ipairs(sample) do
			if si % P.TICK_EVERY == 0 then Y.tick() end
			local b = math.clamp(math.floor((q[2] - lo) / span * B), 0, B - 1) + 1
			-- the body is close enough to a sphere that the outward direction IS
			-- the normal, so lambert against a straight-down key light is q.y/|q|
			local l = math.sqrt(q[1]*q[1] + q[2]*q[2] + q[3]*q[3])
			local lit = l > 1e-9 and math.max(0, q[2] / l) or 0
			litAll += lit
			if whiteAt(v, q[1], q[2], q[3], q[4], q[5], k) > 0.5 then
				wHist[b] += 1
				white += 1
				litWhite += lit
			else
				nHist[b] += 1
			end
			total += 1
		end
		-- how lit is the marking, against how lit the body is on average? Below 1
		-- the marking sits in the shade and renders grey no matter how white the
		-- paint is -- which is countershade's whole failure, and no tone or edge
		-- setting escapes it.
		local litRatio = (white > 0 and litAll > 0)
			and (litWhite / white) / (litAll / total) or 0

		-- an all-white or all-hue body is trivially predicted by any threshold
		if white == 0 or white == total then return 1, litRatio end
		local cw, cn, best = 0, 0, 0
		for b = 1, B do
			cw += wHist[b]
			cn += nHist[b]
			local j = math.abs(cw / white - cn / (total - white))
			if j > best then best = j end
		end
		return best, litRatio
	end

	for _, c in ipairs(workspace:GetChildren()) do
		if c.Name == P.ROOT_NAME then c:Destroy() end
	end
	local root = Instance.new("Model")
	root.Name = P.ROOT_NAME
	root.Parent = workspace

	local localOff = Vector3.new(M.CX, M.CY, M.CZ)
	local buf = buffer.create(W*W*4)
	local base, acc = P.HUE, P.COLOUR_WHITE
	local br, bg, bb = base.R, base.G, base.B
	local ar, ag, ab = acc.R, acc.G, acc.B  -- reassigned per variant below

	-- median texel step, for turning the area/perimeter ratio into studs
	local stepSum, stepN = 0, 0
	do
		local mid = W // 2
		for x = 0, W-2 do
			local i1, i2 = mid*W + x, mid*W + x + 1
			if buffer.readu8(MASK,i1) == 1 and buffer.readu8(MASK,i2) == 1 then
				local o1, o2 = i1*12, i2*12
				stepSum += math.sqrt(
					(buffer.readf32(POS,o1)-buffer.readf32(POS,o2))^2 +
					(buffer.readf32(POS,o1+4)-buffer.readf32(POS,o2+4))^2 +
					(buffer.readf32(POS,o1+8)-buffer.readf32(POS,o2+8))^2)
				stepN += 1
			end
		end
	end
	local texelStep = stepSum / math.max(1, stepN)

	local byName = {}
	for _, v in ipairs(VARIANTS) do byName[v.name] = v end

	-- One flat job list, so grid mode and row mode share the whole builder
	-- below instead of forking it.
	local jobs = {}
	if #P.LADDER > 0 then
		for row, rung in ipairs(P.LADDER) do
			local tier, vname = rung[1], rung[2]
			local v = byName[vname]
			assert(v, string.format("[Lab] ladder rung %q names variant %q, which is not here",
				tier, vname))
			for col, hue in ipairs(P.HUES) do
				table.insert(jobs, {
					v = v, tier = tier, hueName = hue[1], hue = hue[2],
					x = (col - 1) * P.SPACING, z = (row - 1) * P.ROW_SPACING,
				})
			end
		end
	end

	local build = VARIANTS
	if #P.ONLY > 0 then
		local want = {}
		for _, n in ipairs(P.ONLY) do want[n] = true end
		build = {}
		for _, n in ipairs(P.ONLY) do
			for _, v in ipairs(VARIANTS) do
				if v.name == n then table.insert(build, v) want[n] = nil break end
			end
		end
		for n in pairs(want) do
			error(string.format("[Lab] P.ONLY names %q, which is not a variant here", n))
		end
	end

	if #jobs == 0 then
		for i, v in ipairs(build) do
			table.insert(jobs, { v = v, tier = "", hueName = P.HUE_NAME, hue = P.HUE,
				x = (i - 1) * P.SPACING, z = 0 })
		end
	end

	-- k, the white fraction and both light numbers are all GEOMETRY. None of
	-- them knows what colour the body is, so in grid mode each rung is
	-- calibrated once and the other five hues reuse it -- 5 bisections rather
	-- than 30, and it also guarantees a rung is the identical SHAPE across the
	-- row rather than six independent searches landing 0.3% apart.
	local shapeCache = {}

	local worstPx, worstWhat = math.huge, "?"
	for vi, job in ipairs(jobs) do
		Y.tick()
		local v = job.v
		local k, measured, shadow, lit, coreK
		if v.solid then
			k, measured, shadow, lit = 0, 0, 0, 1
		elseif shapeCache[v.name] then
			local c = shapeCache[v.name]
			k, measured, shadow, lit, coreK = c[1], c[2], c[3], c[4], c[5]
		else
			k, measured = calibrate(v, v.target or P.WHITE_TARGET)
			if v.stops then
				shadow, lit = 0, 0        -- see THE RAMP: not applicable, so not computed
			else
				shadow, lit = lightFit(v, k)
			end
			-- THE CORE IS CALIBRATED, NOT SCALED. k is a threshold in g-space and
			-- it is NEGATIVE for some fields (anything written as -(f/l) and the
			-- like), so k * fraction moves the boundary the WRONG WAY for half
			-- the variants here. Bisecting to a coverage target is sign-agnostic.
			if v.core then
				coreK = calibrate(v, (v.target or P.WHITE_TARGET) * v.core.fraction)
			end
			shapeCache[v.name] = { k, measured, shadow, lit, coreK }
		end
		local accV = v.white or P.COLOUR_WHITE
		ar, ag, ab = accV.R, accV.G, accV.B
		br, bg, bb = job.hue.R, job.hue.G, job.hue.B
		-- stops may be a FUNCTION of the base, which is what lets the flames
		-- carry whatever hue this slime is rather than a fixed fire colour
		local stopsV = nil
		if v.stops then
			stopsV = (typeof(v.stops) == "function")
				and v.stops(Color3.new(br, bg, bb)) or v.stops
		end
		if v.deep then br, bg, bb = br * v.deep, bg * v.deep, bb * v.deep end

		-- paint, and measure the shape while painting: white texel count and the
		-- count of white texels with a non-white neighbour give area and perimeter
		local whiteN, edgeN = 0, 0
		local coreN, coreEdgeN = 0, 0
		local visN, visEdgeN = 0, 0
		local rowVis = table.create(W)
		local VT2 = P.VIS_THRESHOLD * P.VIS_THRESHOLD
		local rowWhite = table.create(W)
		local rowCore = table.create(W)
		local cr, cg, cb = 0, 0, 0
		if v.core then cr, cg, cb = v.core.color.R, v.core.color.G, v.core.color.B end
		for y = 0, W-1 do
			if y % P.PAINT_TICK_ROWS == 0 then Y.tick() end
			for x = 0, W-1 do
				local idx = y*W + x
				local off = idx*4
				if buffer.readu8(MASK, idx) ~= 0 then
					local o = idx*12
					local qx = buffer.readf32(POS,o)
					local qy = buffer.readf32(POS,o+4)
					local qz = buffer.readf32(POS,o+8)
					local fq = qx*FWD.X + qz*FWD.Z
					local sq = qx*SIDE.X + qz*SIDE.Z
					local a = whiteAt(v, qx, qy, qz, fq, sq, k)
					if a > 0.5 then whiteN += 1 end
					rowWhite[x + 1] = a > 0.5
					if x > 0 and rowWhite[x] ~= rowWhite[x + 1] then edgeN += 1 end
					local pr, pg, pb
					if v.stops then
						-- inside the mask the colour is the ramp; `a` still
						-- antialiases the mask edge against the body
						local h = v.heat(qx, qy, qz, fq, sq, qy, k)
						local hr, hg, hb = rampAt(stopsV, h)
						pr = br + (hr - br) * a
						pg = bg + (hg - bg) * a
						pb = bb + (hb - bb) * a
					else
						pr = br + (ar-br)*a
						pg = bg + (ag-bg)*a
						pb = bb + (ab-bb)*a
					end
					if coreK and not v.stops then
						local c = whiteAt(v, qx, qy, qz, fq, sq, coreK)
						pr = pr + (cr-pr)*c
						pg = pg + (cg-pg)*c
						pb = pb + (cb-pb)*c
						if c > 0.5 then coreN += 1 end
						rowCore[x + 1] = c > 0.5
						if x > 0 and rowCore[x] ~= rowCore[x + 1] then coreEdgeN += 1 end
					end
					local dr, dg, db = pr - br, pg - bg, pb - bb
					local seen = (dr*dr + dg*dg + db*db) > VT2
					if seen then visN += 1 end
					rowVis[x + 1] = seen
					if x > 0 and rowVis[x] ~= rowVis[x + 1] then visEdgeN += 1 end
					buffer.writeu8(buf, off, math.floor(math.clamp(pr, 0, 1)*255 + 0.5))
					buffer.writeu8(buf, off+1, math.floor(math.clamp(pg, 0, 1)*255 + 0.5))
					buffer.writeu8(buf, off+2, math.floor(math.clamp(pb, 0, 1)*255 + 0.5))
					buffer.writeu8(buf, off+3, 255)
				else
					rowWhite[x + 1] = false
					rowCore[x + 1] = false
					rowVis[x + 1] = false
					buffer.writeu8(buf, off, 0); buffer.writeu8(buf, off+1, 0)
					buffer.writeu8(buf, off+2, 0); buffer.writeu8(buf, off+3, 255)
				end
			end
		end

		-- characteristic width 2A/P, which is exactly the stripe width for a stripe
		local widthStuds = (edgeN > 0)
			and (2 * whiteN / edgeN) * texelStep * bodyRadiusStuds or 0
		local widthPx = widthStuds * pxPerStud
		-- THE VISIBLE SIZE. For a mask this agrees with widthPx by construction,
		-- because everything inside a mask is the accent. For a RAMP it does not,
		-- and it is the only one of the two that means anything -- see the header.
		local visPx = (visEdgeN > 0)
			and (2 * visN / visEdgeN) * texelStep * bodyRadiusStuds * pxPerStud or 0

		-- a rung with no marking has no narrowest feature; it would read as 0 px
		local floorPx = v.stops and visPx or widthPx
		if not v.solid and floorPx < worstPx then
			worstPx, worstWhat = floorPx, v.name .. (v.stops and " visible" or "")
		end

		-- THE CORE IS THE THING AT RISK, not the marking around it: it is
		-- narrower by construction, so it is measured on its own and tracked
		-- against the same 8 px floor rather than assumed safe.
		local corePx = 0
		if coreK and coreEdgeN > 0 then
			corePx = (2 * coreN / coreEdgeN) * texelStep * bodyRadiusStuds * pxPerStud
			if corePx < worstPx then worstPx, worstWhat = corePx, v.name .. " core" end
		end

		local img = AssetService:CreateEditableImage({ Size = Vector2.new(W, W) })
		img:WritePixelsBuffer(Vector2.zero, Vector2.new(W, W), buf)
		Y.mark()

		local at = P.ORIGIN + Vector3.new(job.x, 0, job.z)
		local bodyCF = CFrame.new(at.X, at.Y + bodyHeightStuds/2, at.Z)
			* CFrame.Angles(0, math.rad(P.BODY_YAW_DEG), 0)
		local slime = Instance.new("Model")
		slime.Name = (job.tier ~= "")
			and string.format("T%02d_%s_%s", vi, job.tier, job.hueName)
			or string.format("V%02d_%s", vi, v.name)
		slime.Parent = root

		local body = source:Clone()
		body.Size = source.Size * partScale
		body.Name = "body"
		body.Color = Color3.new(1,1,1)
		body.Material = P.BODY_MATERIAL
		body.Anchored = true
		body.CanCollide = false; body.CanQuery = false; body.CanTouch = false
		pcall(function() body.TextureID = "" end)
		body.TextureContent = Content.fromObject(img)
		body.CFrame = bodyCF * CFrame.new(-localOff)
		body.Parent = slime
		slime.PrimaryPart = body

		for _, spec in ipairs(FACE_PARTS) do
			local part = AssetService:CreateMeshPartAsync(Content.fromUri(spec.mesh))
			part.Name = spec.name
			part.Size = spec.size
			part.Color = spec.color
			part.Material = Enum.Material.SmoothPlastic
			part.Anchored = true
			part.CanCollide = false; part.CanQuery = false; part.CanTouch = false
			part.CFrame = bodyCF * spec.rel
			part.Parent = slime
		end
		Y.mark()

		slime:SetAttribute("BodyCentre", Vector3.new(at.X, at.Y + bodyHeightStuds/2, at.Z))
		slime:SetAttribute("Variant", v.name)
		slime:SetAttribute("Index", vi)
		slime:SetAttribute("Hue", job.hueName)
		slime:SetAttribute("Tier", job.tier)
		slime:SetAttribute("WhiteFraction", measured)

		slime:SetAttribute("ShadowAlignment", shadow)
		slime:SetAttribute("LitRatio", lit)
		local coreNote = corePx > 0 and string.format(" | core %5.1f px", corePx) or ""
		if v.stops then
			-- J and lit are switched off here, not hidden: both are defined on
			-- white-versus-not and both would invert their meaning on a ramp.
			log("[Lab] %2d %-17s covers %.1f%% of the body | VISIBLE feature %5.1f px"
				.. " (mask says %.1f, which is not the number to read) | J -- | lit -- | %s",
				vi, v.name, measured * 100, visPx, widthPx, v.note)
		elseif job.tier ~= "" then
			local lumGap, rgbDist = contrast(job.hue, accV)
			log("[Lab] %2d %-10s %-7s %-9s white %4.1f%% | feature %5.1f px | lum gap %.2f | rgb %.2f",
				vi, job.tier, job.hueName, v.name, measured * 100, widthPx, lumGap, rgbDist)
		else
			log("[Lab] %2d %-17s white %.1f%% | feature %5.1f px%s | J %.2f | lit %.2f%s | %s",
				vi, v.name, measured * 100, widthPx, coreNote, shadow, lit,
				(shadow >= P.SHADOW_WARN or lit <= P.LIT_LO or lit >= P.LIT_HI)
					and " <--" or "    ", v.note)
		end
	end

	for _, n in ipairs(DOT_ORDER) do
		log("[Lab] dots %d: %s", n, DOT_NOTES[n])
	end
	log("[Lab] narrowest feature: %.1f px (%s), floor is %d px",
		worstPx, worstWhat, P.MIN_FEATURE_PX)
	log("[Lab] watchdog worst hold %.1f ms | built %d variants in %.2f s",
		Y.worstMs(), #jobs, os.clock() - t0)
	log("[Lab] undo with workspace.%s:Destroy()", P.ROOT_NAME)

	local outStr = table.concat(lines, "\n")
	print(outStr)
	return outStr
end

return run()
