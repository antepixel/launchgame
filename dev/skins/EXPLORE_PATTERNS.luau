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
-- KNOWN AND MEASURED: THE PROFILE IS IDEALISED, AND THE BODY IS NOT.
-- Everything above integrates the area element of a perfect spheroid. The mesh
-- is a DOME -- rounder on top than underneath -- so the dot count per band is
-- right for a shape the body only approximates. Measured on dots24 by counting
-- white against body in three renders:
--     head-on     28.3%   (calibrated 28.0%, so the calibration itself is right)
--     crown       46.1%
--     underside   20.4%
-- Some of that spread is foreshortening -- an axis-on view sees the pole
-- face-on and the flanks edge-on -- but the two poles differ from EACH OTHER by
-- more than foreshortening explains, and that difference is the dome.
--
-- The lit ratio caught it independently and before any of these renders existed:
-- a uniform field should measure lit = 1.00 and these measure 1.16, 1.23, 1.35,
-- rising with dot count. Two measurements from different evidence agreeing that
-- the field is top-heavy is worth more than either alone.
--
-- THE FIX, NOT APPLIED HERE: integrate the MESH's own radius-versus-height
-- profile instead of a spheroid's. BUILD_TIERMARKS already does exactly this --
-- 45,694 vertices bucketed into 96 height bands with radiusAt interpolating
-- between them -- and it also records the trap, which is that 42 of its 96
-- buckets come out EMPTY and interpolating into a zero collapses the radius to
-- ~25% of true. Reuse that, do not rewrite it.
--
-- A SECOND, SMALLER RESIDUAL: dot SIZE is not constant either. The threshold is
-- a fixed distance in 3D, and the body is flatter at the poles -- meridional
-- radius of curvature a^2/b = 1.48 there against b^2/a = 0.46 at the equator, a
-- 3.2x difference -- so the same radius cuts a wider patch on the flatter part.
-- Correcting it means scaling the threshold by local curvature. Left alone: it
-- is far smaller than the profile error above, and fixing the profile first may
-- make it not worth fixing at all.
-- ===================================================================
local DOT_CACHE = {}
local DOT_ORDER = {}
local DOT_NOTES = {}

local function dotCentres(n: number)
	if DOT_CACHE[n] then return DOT_CACHE[n] end
	local b = YHALF
	local STEPS = 4096
	local cum = table.create(STEPS + 1)
	cum[1] = 0
	for i = 1, STEPS do
		local th = (i - 0.5) * math.pi / STEPS
		local st = math.sin(th)
		cum[i + 1] = cum[i] + st * math.sqrt(math.cos(th)^2 + b*b*st*st) * (math.pi / STEPS)
	end
	local total = cum[STEPS + 1]

	local cx, cy, cz = table.create(n), table.create(n), table.create(n)
	local GA = math.pi * (3 - math.sqrt(5))
	local j = 1
	for i = 0, n - 1 do
		local target = (i + 0.5) / n * total
		while j < STEPS and cum[j + 1] < target do j += 1 end
		local th = (j - 0.5) * math.pi / STEPS
		local lon = i * GA
		local st = math.sin(th)
		cx[i + 1] = st * math.cos(lon)
		cy[i + 1] = b * math.cos(th)
		cz[i + 1] = st * math.sin(lon)
	end

	-- how even did that actually come out? nearest-neighbour spacing in 3D on
	-- the body itself, plus where the dots sit in height, reported not assumed
	local lo, hi, sum = math.huge, 0, 0
	local topN = 0
	for i = 1, n do
		local best = math.huge
		for k = 1, n do
			if k ~= i then
				local dx, dy, dz = cx[i]-cx[k], cy[i]-cy[k], cz[i]-cz[k]
				local d = dx*dx + dy*dy + dz*dz
				if d < best then best = d end
			end
		end
		best = math.sqrt(best)
		lo = math.min(lo, best); hi = math.max(hi, best); sum += best
		if cy[i] > 0.8 * b then topN += 1 end
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

local VARIANTS = {
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
		note = "12 dots, equal-area on the spheroid",
		g = function(qx, qy, qz, f, s, y) return dotField(qx, qy, qz, 12) end,
	},
	{
		name = "dots24",
		note = "24 dots, equal-area on the spheroid",
		g = function(qx, qy, qz, f, s, y) return dotField(qx, qy, qz, 24) end,
	},
	{
		name = "dots40",
		note = "40 dots, equal-area on the spheroid",
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

	local POS, MASK = M.POS, M.MASK
	dilate(POS, MASK, W, 3, Y)

	local bodySizeX = P.BODY_WIDTH_STUDS * M.FULL_W / (2 * M.RAD)
	local partScale = bodySizeX / source.Size.X
	local studsPerMeshUnit = bodySizeX / M.FULL_W
	local bodyRadiusStuds = M.RAD * studsPerMeshUnit
	local bodyHeightStuds = M.HEIGHT * studsPerMeshUnit
	YHALF = (M.HEIGHT / M.RAD) / 2
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
			k, measured = calibrate(v, P.WHITE_TARGET)
			shadow, lit = lightFit(v, k)
			-- THE CORE IS CALIBRATED, NOT SCALED. k is a threshold in g-space and
			-- it is NEGATIVE for some fields (anything written as -(f/l) and the
			-- like), so k * fraction moves the boundary the WRONG WAY for half
			-- the variants here. Bisecting to a coverage target is sign-agnostic.
			if v.core then
				coreK = calibrate(v, P.WHITE_TARGET * v.core.fraction)
			end
			shapeCache[v.name] = { k, measured, shadow, lit, coreK }
		end
		local accV = v.white or P.COLOUR_WHITE
		ar, ag, ab = accV.R, accV.G, accV.B
		br, bg, bb = job.hue.R, job.hue.G, job.hue.B

		-- paint, and measure the shape while painting: white texel count and the
		-- count of white texels with a non-white neighbour give area and perimeter
		local whiteN, edgeN = 0, 0
		local coreN, coreEdgeN = 0, 0
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
					local pr = br + (ar-br)*a
					local pg = bg + (ag-bg)*a
					local pb = bb + (ab-bb)*a
					if coreK then
						local c = whiteAt(v, qx, qy, qz, fq, sq, coreK)
						pr = pr + (cr-pr)*c
						pg = pg + (cg-pg)*c
						pb = pb + (cb-pb)*c
						if c > 0.5 then coreN += 1 end
						rowCore[x + 1] = c > 0.5
						if x > 0 and rowCore[x] ~= rowCore[x + 1] then coreEdgeN += 1 end
					end
					buffer.writeu8(buf, off, math.floor(math.clamp(pr, 0, 1)*255 + 0.5))
					buffer.writeu8(buf, off+1, math.floor(math.clamp(pg, 0, 1)*255 + 0.5))
					buffer.writeu8(buf, off+2, math.floor(math.clamp(pb, 0, 1)*255 + 0.5))
					buffer.writeu8(buf, off+3, 255)
				else
					rowWhite[x + 1] = false
					rowCore[x + 1] = false
					buffer.writeu8(buf, off, 0); buffer.writeu8(buf, off+1, 0)
					buffer.writeu8(buf, off+2, 0); buffer.writeu8(buf, off+3, 255)
				end
			end
		end

		-- characteristic width 2A/P, which is exactly the stripe width for a stripe
		local widthStuds = (edgeN > 0)
			and (2 * whiteN / edgeN) * texelStep * bodyRadiusStuds or 0
		local widthPx = widthStuds * pxPerStud
		-- a rung with no marking has no narrowest feature; it would read as 0 px
		if not v.solid and widthPx < worstPx then worstPx, worstWhat = widthPx, v.name end

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
		if job.tier ~= "" then
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
