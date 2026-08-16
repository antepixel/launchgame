--!strict
-- BUILD_SKINS.luau -- STANDALONE REBUILD SCRIPT FOR THE TWO-TONE SLIME SKINS.
--
-- Paste the whole file into the Studio command bar and it builds
-- workspace.SkinLineup from nothing: six slimes, one per hue, each striped white
-- and its hue pole to pole like a beach ball, on a procedurally generated
-- EditableImage. No other file needs to be present.
--
-- NOT SHIPPING CODE and deliberately NOT under src/ (Rojo syncs that). Same
-- standing as dev/tiermarks/BUILD_TIERMARKS.luau and dev/divine/BUILD_DIVINE.luau.
--
-- IF THE STUDIO BRIDGE WILL NOT ANSWER, read dev/README.md BEFORE touching the
-- plugin. "Studio plugin connection timeout" usually does NOT mean the plugin is
-- dead -- with several sessions open there are several MCP servers, and yours may
-- simply not be the one Studio attached to.
--
-- ============================ WHAT WAS LEARNED =============================
--
-- NEITHER COLOUR IS THE BASE. BOTH ARE. This is the whole design and it took
-- three rejected passes to arrive at. A slime is white AND a hue, in roughly
-- equal weight, forming one shape together -- not a hue with something applied
-- to it. The moment one colour dominates, the smaller one stops being part of
-- the object and starts being PAINT ON it, and paint on a toy reads as cheap
-- however cleanly it resolves.
--
-- MERIDIAN, NOT LATITUDE, AND SHEARED. Every earlier pass divided the body
-- HORIZONTALLY, by latitude, and every one produced a band -- a hat, a belt, a
-- sash, a diagonal sash. Stripes running pole to pole divide it by LONGITUDE,
-- and that single change is the difference between a marking and a beach ball.
-- Six or eight around the circumference, alternating white and hue, and then
-- twisted: the pattern rotates by twistDeg between the base and the crown, so a
-- stripe leaving one longitude at the bottom arrives at another at the top.
--
-- WHICH IS WHY COVERAGE CANNOT BE THE RARITY AXIS. An earlier pass escalated
-- rarity as accent coverage -- 10/25/42/60% -- and that was wrong from the
-- start, not merely mistuned: any ladder built on coverage forces every rung
-- except the middle to be lopsided, and lopsided is exactly what makes the
-- lesser colour read as paint. Rarity needs a different axis entirely. It is
-- DELIBERATELY NOT SOLVED HERE, and nothing below encodes a tier.
--
-- THE RESOLVE RULE STILL BINDS, AND THE CROWN IS WHERE IT BIT. A feature is
-- either clearly visible at 40 studs or it is not present -- three cheap-looking
-- results in this project were the same mistake, a feature that HALF resolves:
-- 1-texel stars that mipped to mush, 1 px halo gaps that merged, sub-stud motes
-- that read as stray balls.
--
-- Stripe width is proportional to horizontal radius, so it falls to ZERO at the
-- pole by construction. An earlier version let it, on the reasoning that a beach
-- ball converges at its crown and reads as correct. The GEOMETRY does. The
-- ANTIALIASING does not: once every boundary crowds inside a texel a smoothstep
-- has nothing left to resolve, and the top rendered as a ragged fan -- a
-- rendering fault, not a feature, and precisely the cheap look being avoided.
--
-- So the stripes are stopped by a solid white cap while still well clear of the
-- floor: CAP_AT_STRIPE_PX = 12, against a floor of 8. A FADE was the alternative
-- and would also have removed the artifact, but it resolves to a half-and-half
-- blend -- a washed pastel smear that looks like the texture giving up, where a
-- hard cap is what a real beach ball has and a crisp edge is what this design is
-- made of. The cap is a SECOND boundary, which every earlier pass avoided, but
-- here it is a deliberate feature rather than a mask leaking through.
--
-- THE CAP ALONE WAS NOT ENOUGH, AND THE SPIRAL IS WHY. Capping fixed the plain
-- narrowing and left a second, different artifact: the crown SPLAYED into
-- feathered spikes. A straight meridian converges cleanly to a point, but a
-- constant-rate helix keeps cutting across longitude right into the place where
-- all longitudes meet -- near the crown a single texel spans many longitudes of
-- boundary, and the smoothstep again has nothing coherent to resolve. Capping
-- lower would only have hidden more of the body under white.
--
-- The fix is that the TWIST RATE reaches zero before the pole does. It is shaped
-- as (1 - h^2), peaking at the equator and vanishing at both poles, so the
-- boundary is running straight along a meridian by the time it converges, and
-- only then does the cap take over. Measured, the boundary's lean off the
-- meridian falls from 30-60 degrees at the equator to 0.14-1.02 degrees at the
-- cap, and it sweeps 0.04-0.25% of a stripe width per texel there -- against
-- roughly 4-5% for the unramped helix, which is what the spikes were.
--
-- The cap is keyed to stripe WIDTH rather than to a latitude, so it self-adjusts
-- to the count and the twist instead of being guessed per design. It catches
-- both poles, since it tests horizontal radius -- the underside converged and
-- fanned just as badly as the top.
--
-- MEASURED, at 40 studs: equator width runs 63.7 px (6 stripes, 30 deg twist)
-- down to 27.5 px (8 stripes, 90 deg) -- twist NARROWS stripes, since a sheared
-- stripe is thinner across than around, and the ramp concentrates the shear at
-- the equator so a given total leans harder there than a flat rate would. Every
-- one is above the floor, and the narrowest stripe that renders anywhere is
-- 12.0 px at the cap edge.
--
-- 40 studs, FOV 70, a 563 px tall frame => 10.05 px per stud. The body is 14
-- studs across, so it lands 141 px wide, and 8 px is 0.80 studs.
--
-- EVERY BOUNDARY IS ANTIALIASED, and on a design that IS its boundary this
-- stopped being a polish item and became the point. A hard threshold stair-steps
-- at ANY resolution -- 256 merely made it obvious. Fields return a signed value
-- and the colour mix runs through a smoothstep band EDGE_SOFT wide. A soft
-- boundary is NOT a sub-resolution feature and does not violate the 8 px rule:
-- that rule is about how big a region is, not how sharp its border is.
--
-- The white fraction INTEGRATES that soft value rather than counting texels,
-- because a texel on a boundary is genuinely part white. Worth knowing if you
-- port this: 0 is truthy in Lua, so a boolean call site keeps compiling and
-- silently counts every texel the moment fields start returning numbers.
--
-- NOTHING IS SEARCHED FOR ANY MORE. The latitude cuts had to have their offset
-- solved until the two sides levelled out. cos(k*theta) is positive over exactly
-- half of any full turn, at EVERY latitude, and the twist does not disturb that
-- -- it rotates the pattern rather than reweighting it. Confirmed offline at six
-- latitudes against all six specs: deviation from 50% is 0.0000.
--
-- The built figures read 50.9% to 52.7% white, and the excess is the crown caps,
-- which are solid white and take 2.6-5.0% of the surface. Half of that was white
-- already, so the caps shift the balance by about one to two and a half points.
--
-- 512, WHICH IS A MEMORY DECISION AND NOT A QUALITY ONE. An early pass derived
-- 256 from area -- island 32.8% of the sheet, half facing camera, 0.164*R^2 =
-- 10,300 px -- which is right about area and irrelevant to edges, since one
-- texel per pixel puts the stair steps at exactly the size the eye resolves.
-- 1024 fixes that and costs 4 MB a skin, which is 260 MB at the full 65 roster.
-- With antialiasing carrying the edges, 512 holds up at a quarter of that: 1 MB
-- a skin, 65 MB at 65. TEX is the only line to change if that judgement shifts.
--
-- WHITE IS A COLOUR HERE, NOT AN ABSENCE OF ONE. Two earlier accent schemes
-- failed on that distinction. A darker shade of the base hue reads as SHADING,
-- because a lit curved body already spans that luminance range from highlight to
-- flank. Near-black and near-white fix the shading problem and read as DIRT.
-- What works is a near-white that is unmistakably a material -- and at 50/50 it
-- is not an accent at all, it is half the animal.
--
-- ONE CONTRAST NUMBER IS NOT ENOUGH. Luminance gap alone rejects white on
-- yellow at 0.13, and white on yellow reads perfectly well because the
-- separation there is chroma rather than brightness. Both luminance gap and RGB
-- distance are measured; the worst hue is chosen on RGB distance.
--
-- NO FACE MASK, AND REMOVING IT WAS A DESIGN FIX RATHER THAN A SIMPLIFICATION.
-- Earlier passes forced a cone around the eyes back to base colour so the face
-- would read. On a design whose whole content is ONE boundary, that cone drew a
-- SECOND one -- a faint disc round the face competing with the real curve. At
-- 50/50 it is also unnecessary: the dark eye mesh reads on white, and the hue
-- side is a saturated mid-tone.
--
-- NO SPOTS AND NO PATCHES. Both passed the pixel rule comfortably at 30.6 px and
-- were still cut, because on a rounded body a scatter of blobs reads as STAINING
-- however cleanly its edges land. Resolving is necessary and not sufficient --
-- which is the same lesson as the crown above, pointing the other way: passing
-- the measurement does not make a thing good, and failing it does not
-- automatically make a thing bad.
--
-- THE TEXTURE PIPELINE IS BUILD_GALAXY's, INCLUDING ITS OWNERSHIP RULE. Per
-- texel, recover the 3D point on the mesh and evaluate the field there -- 3D has
-- no seam and no pole, so continuity is free, which is what lets a boundary run
-- round the whole body without breaking at the wrap. Texel ownership is decided
-- by containment class, never by rasterisation order, and never by ranking
-- interiority magnitude. See BUILD_GALAXY's header for why that last one is a
-- trap. That code is duplicated here rather than shared because these files are
-- standalone by design.
--
-- REVERSAL: workspace.SkinLineup:Destroy().
-- ===========================================================================

local AssetService = game:GetService("AssetService")

-- ===================================================================
-- PARAMETERS -- everything tunable lives here.
-- ===================================================================
local P = {
	-- ---- output ----
	-- 512: enough headroom over the sampling rate for the boundary, at a quarter
	-- of 1024's memory. See the header -- the old 256 matched texel size to pixel
	-- size, which puts the stair steps at exactly the size the eye resolves.
	TEX = 512,
	ROOT_NAME = "SkinLineup",
	-- The UNWRAPPED body; the lineup meshes have exactly ONE distinct UV coordinate
	-- and cannot display a texture at all. First name that resolves wins, and the
	-- first MeshPart ANYWHERE beneath it is the body -- importers nest it
	-- differently every time.
	SOURCE_MODELS = { "AuxScene", "slime_uv" },

	-- Everything is calibrated to the lineup's body width: 40 studs, 10.05 px per
	-- stud, a 141 px body. The source part arrives at whatever scale the exporter
	-- chose -- the re-unwrapped mesh is 2.0 units across, not 14 -- so the clone is
	-- scaled to hit this rather than trusting the import.
	BODY_WIDTH_STUDS = 14.0,
	-- Plastic, NOT SmoothPlastic. SmoothPlastic's specular lobe puts a hard white
	-- highlight on the dome that competes with the pattern for the eye, and the
	-- lineup slimes are Plastic anyway.
	BODY_MATERIAL = Enum.Material.Plastic,

	-- ---- layout: one row, hues along X ----
	ORIGIN = Vector3.new(-55, 0, -260),
	HUE_SPACING = 22,
	BODY_YAW_DEG = 179.4,            -- turns the face toward the camera

	-- ---- the viewing condition the whole design is calibrated to ----
	VIEW_DISTANCE = 40,
	VIEW_FOV_DEG = 70,
	VIEW_FRAME_PX = 563,
	MIN_FEATURE_PX = 8,              -- below this a feature half-resolves; hard assert

	-- ---- the split ----
	-- NOT a rarity axis, and not searched for either: cos(k*theta) is positive
	-- over exactly half of any full turn, so meridian stripes come out 50/50 by
	-- construction at every latitude. Measured on the real texel set anyway.
	COVERAGE_SAMPLE_STRIDE = 3,      -- every Nth covered texel during the search
	CALIBRATE_TICK_EVERY = 512,      -- yield check inside the search loop
	PAINT_TICK_ROWS = 6,             -- yield check every N rows of the paint loop

	-- ---- the two colours ----
	-- White and the hue, in roughly equal weight. There is no "accent": at 50/50
	-- with one clean boundary the eye reads ONE object made of two colours, and it
	-- is dominance that makes the smaller colour look like paint applied to the
	-- larger. A hair of warmth keeps the white from reading as clinical.
	COLOUR_WHITE = Color3.fromRGB(252, 251, 247),

	-- ---- edge antialiasing ----
	-- Half-width of the accent boundary, in body-radii. A hard threshold gives a
	-- stair-stepped edge at ANY resolution; this is the actual fix, and 1024 is
	-- what gives it room to work. ~0.012 is about two texels at 1024, where the
	-- island's texel step measures 0.006 body-radii.
	--
	-- A soft boundary is NOT a sub-resolution feature and does not violate the
	-- 8 px rule: the rule is about how big a SHAPE is, not how sharp its border.
	EDGE_SOFT = 0.012,

	-- ---- face keep-clear ----
	-- THE FACE MASK IS GONE. It forced a cone around the eyes back to base colour,
	-- which drew a SECOND boundary on the body -- a faint disc floating around the
	-- face, competing with the one boundary that is supposed to be the design. It
	-- earned its place when the pattern was a marking on a base and a pale accent
	-- could swallow the eye whites. At 50/50 the eyes read on either colour: the
	-- dark eye mesh contrasts with white, and the hue side is a saturated mid-tone.

	-- ---- the stripes ----
	-- Count is the number of stripes around the FULL circumference, so half are
	-- white. It must be EVEN: the field is cos(k*theta), which has 2k sign
	-- regions, so count = 2k and an odd count is not expressible this way at all
	-- while staying exactly half and half. 6 and 8 are the two the reference
	-- suggests; both are shown so they can be compared side by side.
	--
	-- Phase rotates the pattern about the vertical axis. It matters more than it
	-- sounds: with the face fixed, phase decides whether the face sits centred on
	-- a stripe or straddles a boundary.
	-- twistDeg is how far the stripe pattern ROTATES between the bottom of the
	-- body and the top. 0 gives straight meridians; positive shears them into a
	-- helix, so a stripe leaving one longitude at the base arrives at a different
	-- one at the crown. Three values are shown against both counts.
	-- twistDeg is the TOTAL rotation from the bottom of the body to the top. The
	-- rate is not constant over that span -- see TWIST_RAMP_POWER -- so the same
	-- total buys a steeper equator than it used to; these values are lower than
	-- the unramped set for that reason.
	STRIPE_SPECS = {
		{ count = 6, phaseDeg = 0, twistDeg = 30 },
		{ count = 6, phaseDeg = 30, twistDeg = 60 },
		{ count = 8, phaseDeg = 0, twistDeg = 30 },
		{ count = 8, phaseDeg = 22.5, twistDeg = 60 },
		{ count = 6, phaseDeg = 15, twistDeg = 90 },
		{ count = 8, phaseDeg = 11.25, twistDeg = 90 },
	},

	-- ---- the twist ramp ----
	-- THE TWIST RATE MUST REACH ZERO BEFORE THE POLE DOES. A constant rate makes
	-- the boundary a true helix, and a helix does not converge cleanly: it keeps
	-- cutting across longitude right into the point where all longitudes meet, so
	-- near the crown one texel spans many longitudes of boundary and the
	-- smoothstep has nothing coherent to resolve. That renders as feathered spikes
	-- -- a different failure from plain narrowing, and specific to the spiral.
	--
	-- So the rate is shaped as (1 - h^2)^power, h being height normalised to +-1.
	-- It peaks at the equator and vanishes at both poles, which means the boundary
	-- is running STRAIGHT along a meridian by the time it converges. Only then
	-- does the cap take over.
	--
	-- Power 1 integrates to h - h^3/3, so alpha(h) = 0.75 * total * (h - h^3/3)
	-- delivers exactly twistDeg end to end while peaking at 1.5x the flat rate.
	-- SET 0 to switch the ramp off and get the flat rate back, for comparison.
	TWIST_RAMP_POWER = 1,

	-- ---- the crown cap ----
	-- Stripes must NOT be allowed to reach the pole. Their width falls to zero
	-- there by construction, and once every boundary crowds inside a texel the
	-- smoothstep has nothing left to resolve -- the result is a ragged fan that
	-- reads as a rendering fault, which is the exact "cheap" failure this whole
	-- design exists to avoid. So the stripes stop while they are still wide
	-- enough to read, and a solid cap takes over.
	--
	-- A CAP RATHER THAN A FADE. Fading the stripe contrast out over the crown
	-- also removes the artifact, but it resolves to a half-and-half blend -- a
	-- washed pastel smear that looks like the texture giving up. A hard cap with
	-- its own clean boundary is what a real beach ball has, and a crisp edge is
	-- the thing this design is made of. It is a second boundary, which every
	-- earlier pass avoided, but here it is a deliberate feature rather than a
	-- mask leaking through.
	--
	-- Expressed as the stripe width at which the cap starts, so it self-adjusts
	-- to the stripe count rather than being a latitude guessed per design.
	CAP_AT_STRIPE_PX = 12,           -- 1.5x the 8 px floor

	-- ---- watchdog ----
	YIELD_MS = 12,
}

-- The six-hue cycle, read off the existing lineup so these match the game.
local HUES = {
	{ name = "green", color = Color3.fromRGB(70, 200, 80) },
	{ name = "red", color = Color3.fromRGB(225, 60, 60) },
	{ name = "blue", color = Color3.fromRGB(60, 120, 240) },
	{ name = "yellow", color = Color3.fromRGB(245, 215, 55) },
	{ name = "purple", color = Color3.fromRGB(165, 80, 220) },
	{ name = "orange", color = Color3.fromRGB(250, 140, 40) },
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
-- WATCHDOG GUARD. Identical in intent to BUILD_GALAXY's: tick() yields only
-- once the thread has been held for YIELD_MS, and mark() resets the clock
-- WITHOUT recording, for spans that park inside an Async engine call. os.clock
-- measures wall time and cannot tell a blocked thread from a parked one.
-- ===================================================================
local function newYielder(budgetMs: number)
	local budget = budgetMs / 1000
	local last = os.clock()
	local yields, worst = 0, 0
	return {
		tick = function()
			if os.clock() - last >= budget then
				local held = os.clock() - last
				if held > worst then worst = held end
				task.wait()
				last = os.clock()
				yields += 1
			end
		end,
		close = function()
			local held = os.clock() - last
			if held > worst then worst = held end
			last = os.clock()
		end,
		mark = function() last = os.clock() end,
		yields = function(): number return yields end,
		worstMs = function(): number return worst * 1000 end,
	}
end

local function smoothstep(e0: number, e1: number, x: number): number
	local u = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return u * u * (3 - 2 * u)
end

local function luminance(c: Color3): number
	return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
end

-- ===================================================================
-- THE STRIPE FIELD.
--
-- MERIDIAN, NOT LATITUDE. Every earlier pass cut the body horizontally, by
-- latitude, and the result was always a band -- a hat, a belt, a sash. Stripes
-- running pole to pole divide it by LONGITUDE instead, and that is the whole
-- difference. White where the field is positive.
--
-- SEAMLESS WITHOUT atan2. Stripes are inherently a function of theta and the
-- obvious implementation reaches for atan2, which has a branch cut down the -x
-- axis -- importing exactly the discontinuity that evaluating in 3D exists to
-- avoid, and putting a visible join down one meridian. But cos(k*theta) needs no
-- angle: it is the Chebyshev polynomial T_k evaluated at cos(theta) = x/r, which
-- is an exact identity and a polynomial in x/r, so it is continuous everywhere
-- theta is defined. cos(k*theta) has 2k sign regions, hence 2k stripes.
--
-- IT IS ALSO EXACTLY HALF AND HALF, for free and at every latitude: cos is
-- positive over exactly half of any full turn. No balance search is needed here,
-- unlike the latitude cuts, which had to be slid until they levelled out.
--
-- THE TWIST NEEDS sin(k*theta) TOO, AND THAT IS THE SECOND CHEBYSHEV KIND.
-- Shearing the stripes into a helix means rotating the pattern by an angle that
-- grows with height: cos(k*(theta - alpha(y))), which expands to
--     cos(k theta) cos(k alpha) + sin(k theta) sin(k alpha).
-- So sin(k*theta) is needed as well, and it has its own seamless form:
--     sin(k theta) = sin(theta) * U_{k-1}(cos theta),
-- with U the Chebyshev polynomial of the SECOND kind. Both halves stay
-- polynomials in x/r and z/r, so the helix is as seam-free as the straight
-- stripes were. Reaching for atan2 here would have been even more tempting than
-- before, and would have put a visible join down one meridian.
--
-- THE CONVERGENCE IS STILL WANTED, BUT THE STRIPES NO LONGER REACH IT. A beach
-- ball converges at the crown and reads as correct, so the pattern is not damped
-- toward the pole. What broke was the ANTIALIASING: once every boundary crowds
-- inside a texel there is nothing left for a smoothstep to resolve, and the top
-- rendered as a ragged fan that looked like a fault rather than a feature. The
-- stripes are therefore stopped by a solid cap while still well above the
-- resolve floor -- see CAP_AT_STRIPE_PX -- rather than being faded out.
--
-- THE SCALE FACTOR IS NOT DAMPING, AND THE DISTINCTION IS THE SUBTLE PART. The
-- field is dimensionless, so a fixed smoothstep band around it is a fixed band
-- in ANGLE -- and an angular band is a spatial band that shrinks with r, leaving
-- edges hard exactly where stripes are finest. Dividing by the field's own
-- gradient magnitude converts it to a signed DISTANCE, so the antialiasing is
-- the same physical width everywhere. With twist the boundary is a helix and the
-- gradient picks up a vertical term, hence the full k*sqrt(1/r^2 + alpha'^2)
-- rather than just k/r. Because that factor is strictly positive it cannot move
-- a single boundary -- only the softness changes, never the geometry.
-- ===================================================================
-- THE RAMP. alpha(h) is the pattern's rotation at normalised height h in [-1,1];
-- alphaRate is its derivative with respect to h. The rate is shaped so it peaks
-- at the equator and reaches ZERO at both poles, which is what stops the
-- boundary cutting across longitude where longitudes converge.
-- POWER 0 IS A REAL SETTING, not a degenerate one: it is the flat rate the ramp
-- replaced, kept so the ramp can be switched off and compared. Both forms are
-- normalised so alpha(1) - alpha(-1) is exactly `total` either way, which is what
-- makes the comparison fair -- the twist delivered end to end is identical and
-- only its distribution over the height changes.
local function alphaOf(h: number, total: number): number
	if P.TWIST_RAMP_POWER == 0 then return total * h / 2 end
	return total * 0.75 * (h - h * h * h / 3)     -- integral of (1 - h^2)
end
local function alphaRate(h: number, total: number): number
	if P.TWIST_RAMP_POWER == 0 then return total / 2 end
	return total * 0.75 * (1 - h * h)
end

-- Returns a SIGNED DISTANCE to the nearest stripe boundary: white where
-- positive. phase is a fixed rotation; twist is the TOTAL rotation bottom to
-- top, applied through the ramp above.
local function stripeField(qx: number, qy: number, qz: number,
	k: number, phase: number, twist: number, yHalf: number): number
	local r = math.sqrt(qx * qx + qz * qz)
	if r < 1e-9 then return 0 end        -- the pole itself; the cap covers it anyway
	local c, sth = qx / r, qz / r        -- cos(theta), sin(theta)
	-- T_k(c) == cos(k*theta); U_{k-1}(c) * sin(theta) == sin(k*theta)
	local t0, t1 = 1.0, c                -- T_0, T_1
	local u0, u1 = 1.0, 2 * c            -- U_0, U_1
	for _ = 2, k do
		t0, t1 = t1, 2 * c * t1 - t0
		u0, u1 = u1, 2 * c * u1 - u0
	end
	local h = math.clamp(qy / yHalf, -1, 1)
	local a = k * (phase + alphaOf(h, twist))
	-- after the loop u0 holds U_{k-1} for every k >= 1, which is the one wanted
	local f = t1 * math.cos(a) + sth * u0 * math.sin(a)
	-- |grad f| at a crossing, in body-radii: the horizontal term k/r plus the
	-- vertical one the twist adds. Dividing by it makes f a distance. The slope
	-- is now a function of height, so it is evaluated here rather than passed in.
	local slope = alphaRate(h, twist) / yHalf
	local grad = k * math.sqrt(1 / (r * r) + slope * slope)
	return f / grad
end


-- ===================================================================
-- THE UV -> 3D MAP, rasterised from the mesh's own UV triangles.
-- Ownership: containment class first, outwardness breaking ties. NEVER rank by
-- interiority magnitude -- see BUILD_GALAXY's header.
-- ===================================================================
local function buildUVMap(meshId: string, W: number, H: number, Y)
	local em = AssetService:CreateEditableMeshAsync(Content.fromUri(meshId))
	local verts, faces = em:GetVertices(), em:GetFaces()
	Y.mark()

	-- STRAY GEOMETRY IS EXCLUDED BY DISTANCE FROM THE CENTROID, not by a Y test.
	-- This used to read `if p.Y < 0`, which worked only because every vertex of the
	-- OLD body happened to sit below zero. The re-unwrapped mesh spans Y 0..1.355 --
	-- entirely above it -- so that test would have excluded the WHOLE BODY and
	-- produced an empty texture with no error at all. Distance from the centroid
	-- says what "stray" actually means and survives any re-export or re-centring.
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
	local strayVerts = 0
	for _, id in ipairs(verts) do
		Y.tick()
		local p = em:GetPosition(id)
		if math.sqrt((p.X-gx)^2 + (p.Y-gy)^2 + (p.Z-gz)^2) > 8 * dmean then
			isStray[id] = true
			strayVerts += 1
		end
	end

	local mnx, mxx = math.huge, -math.huge
	local mny, mxy = math.huge, -math.huge
	local mnz, mxz = math.huge, -math.huge
	-- the FULL bbox too, strays included: that is what the part's Size covers, so
	-- it is the only way to convert mesh units to studs
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
	local CX, CY, CZ = (mnx + mxx) / 2, (mny + mxy) / 2, (mnz + mxz) / 2
	local RAD = (mxx - mnx) / 2

	local POS = buffer.create(W * H * 3 * 4)
	local MASK = buffer.create(W * H)
	local PRIO = buffer.create(W * H * 8)
	local covered, seamTris, skipped = 0, 0, 0

	for _, f in ipairs(faces) do
		Y.tick()
		local fv = em:GetFaceVertices(f)
		if isStray[fv[1]] or isStray[fv[2]] or isStray[fv[3]] then
			skipped += 1
			continue
		end
		local p1, p2, p3 = em:GetPosition(fv[1]), em:GetPosition(fv[2]), em:GetPosition(fv[3])
		local fu = em:GetFaceUVs(f)
		local a, b, c = em:GetUV(fu[1]), em:GetUV(fu[2]), em:GetUV(fu[3])
		local u1, u2, u3 = a.X, b.X, c.X
		local v1, v2, v3 = a.Y, b.Y, c.Y

		local e1x, e1y, e1z = p2.X - p1.X, p2.Y - p1.Y, p2.Z - p1.Z
		local e2x, e2y, e2z = p3.X - p1.X, p3.Y - p1.Y, p3.Z - p1.Z
		local fnx = e1y * e2z - e1z * e2y
		local fny = e1z * e2x - e1x * e2z
		local fnz = e1x * e2y - e1y * e2x
		local fnl = math.sqrt(fnx * fnx + fny * fny + fnz * fnz)
		local rx = (p1.X + p2.X + p3.X) / 3 - CX
		local ry = (p1.Y + p2.Y + p3.Y) / 3 - CY
		local rz = (p1.Z + p2.Z + p3.Z) / 3 - CZ
		local rl = math.sqrt(rx * rx + ry * ry + rz * rz)
		local outward = 0
		if fnl > 1e-12 and rl > 1e-12 then
			outward = (fnx * rx + fny * ry + fnz * rz) / (fnl * rl)
		end

		-- seam-straddling triangle: lift the low corners, wrap the index later
		local umin = math.min(u1, u2, u3)
		if math.max(u1, u2, u3) - umin > 0.5 then
			seamTris += 1
			if u1 - umin <= 0.5 then u1 += 1 end
			if u2 - umin <= 0.5 then u2 += 1 end
			if u3 - umin <= 0.5 then u3 += 1 end
		end

		local x1, y1 = u1 * W, v1 * H
		local x2, y2 = u2 * W, v2 * H
		local x3, y3 = u3 * W, v3 * H
		local d = (y2 - y3) * (x1 - x3) + (x3 - x2) * (y1 - y3)
		if math.abs(d) < 1e-12 then continue end
		local inv = 1 / d

		local minx = math.floor(math.min(x1, x2, x3))
		local maxx = math.ceil(math.max(x1, x2, x3))
		local miny = math.max(0, math.floor(math.min(y1, y2, y3)))
		local maxy = math.min(H - 1, math.ceil(math.max(y1, y2, y3)))

		for py = miny, maxy do
			local fy = py + 0.5
			for px = minx, maxx do
				local fx = px + 0.5
				local l1 = ((y2 - y3) * (fx - x3) + (x3 - x2) * (fy - y3)) * inv
				local l2 = ((y3 - y1) * (fx - x3) + (x1 - x3) * (fy - y3)) * inv
				local l3 = 1 - l1 - l2
				if l1 >= -0.002 and l2 >= -0.002 and l3 >= -0.002 then
					local idx = py * W + (px % W)
					local o, po = idx * 12, idx * 8
					local nx = (l1 * p1.X + l2 * p2.X + l3 * p3.X - CX) / RAD
					local ny = (l1 * p1.Y + l2 * p2.Y + l3 * p3.Y - CY) / RAD
					local nz = (l1 * p1.Z + l2 * p2.Z + l3 * p3.Z - CZ) / RAD
					local interior = math.min(l1, l2, l3)

					local wins
					if buffer.readu8(MASK, idx) == 0 then
						buffer.writeu8(MASK, idx, 1)
						covered += 1
						wins = true
					else
						local heldInt = buffer.readf32(PRIO, po)
						local heldOut = buffer.readf32(PRIO, po + 4)
						local iC, hC = interior >= 0, heldInt >= 0
						if iC ~= hC then wins = iC else wins = outward > heldOut end
					end
					if wins then
						buffer.writef32(POS, o, nx)
						buffer.writef32(POS, o + 4, ny)
						buffer.writef32(POS, o + 8, nz)
						buffer.writef32(PRIO, po, interior)
						buffer.writef32(PRIO, po + 4, outward)
					end
				end
			end
		end
	end

	Y.close()
	return {
		POS = POS, MASK = MASK, covered = covered, seamTris = seamTris, skipped = skipped,
		CX = CX, CY = CY, CZ = CZ, RAD = RAD, HEIGHT = mxy - mny,
		FULL_W = amxx - amnx, strayVerts = strayVerts,
	}
end

-- Grow the painted region past the island edge so bilinear filtering at the
-- boundary samples real colour instead of unwritten black.
local function dilate(POS, MASK, W: number, H: number, passes: number, Y): number
	local grown = 0
	for _ = 1, passes do
		local add = {}
		for y = 0, H - 1 do
			Y.tick()
			for x = 0, W - 1 do
				local idx = y * W + x
				if buffer.readu8(MASK, idx) == 0 then
					local nb = -1
					if x > 0 and buffer.readu8(MASK, idx - 1) == 1 then nb = idx - 1
					elseif x < W - 1 and buffer.readu8(MASK, idx + 1) == 1 then nb = idx + 1
					elseif y > 0 and buffer.readu8(MASK, idx - W) == 1 then nb = idx - W
					elseif y < H - 1 and buffer.readu8(MASK, idx + W) == 1 then nb = idx + W
					end
					if nb >= 0 then table.insert(add, { idx, nb }) end
				end
			end
		end
		for _, pair in ipairs(add) do
			local idx, nb = pair[1], pair[2]
			local o, no = idx * 12, nb * 12
			buffer.writef32(POS, o, buffer.readf32(POS, no))
			buffer.writef32(POS, o + 4, buffer.readf32(POS, no + 4))
			buffer.writef32(POS, o + 8, buffer.readf32(POS, no + 8))
			buffer.writeu8(MASK, idx, 2)
			grown += 1
		end
		for _, pair in ipairs(add) do buffer.writeu8(MASK, pair[1], 1) end
	end
	Y.close()
	return grown
end

-- ===================================================================
-- COLOUR: base and the adaptive accent.
-- ===================================================================
-- Returns the accent, plus TWO contrast numbers because one is not enough.
-- Luminance gap alone rejects cream-on-yellow, which in fact reads perfectly
-- well -- the separation there is chroma, not brightness. RGB distance catches
-- what luminance misses, so both are measured and both are reported.
local function accentFor(base: Color3): (Color3, number, number)
	local acc = P.COLOUR_WHITE
	local lumGap = math.abs(luminance(acc) - luminance(base))
	local dr, dg, db = acc.R - base.R, acc.G - base.G, acc.B - base.B
	return acc, lumGap, math.sqrt(dr * dr + dg * dg + db * db)
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
		local m = workspace:FindFirstChild(name)
		if m then
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("MeshPart") then src = d :: BasePart break end
			end
			if src then break end
		end
	end
	assert(src, string.format(
		"[Skins] no MeshPart found under any of {%s}. These skins need the UNWRAPPED "
			.. "body; the lineup slimes have exactly ONE distinct UV coordinate and "
			.. "cannot display a texture at all.", table.concat(P.SOURCE_MODELS, ", ")))
	local source = src :: BasePart
	log("[Skins] source: %s", source:GetFullName())

	local W = P.TEX
	local Y = newYielder(P.YIELD_MS)
	local M = buildUVMap((source :: any).MeshId, W, W, Y)
	log("[Skins] UV map: %d texels covered (%.1f%% of sheet), %d seam tris, %d cube faces skipped",
		M.covered, 100 * M.covered / (W * W), M.seamTris, M.skipped)

	local POS, MASK = M.POS, M.MASK

	local grown = dilate(POS, MASK, W, W, 3, Y)
	log("[Skins] dilated %d texels past the island edge (bilinear guard)", grown)

	-- SCALE THE BODY TO THE CALIBRATED WIDTH rather than trusting the import. The
	-- old mesh arrived 14 studs across and the re-unwrapped one arrives 2.0, so a
	-- clone at source scale would be a seventh of the size with the face parts --
	-- which are fixed studs -- swamping it. Sizing here means the source part can
	-- be any scale.
	--
	-- The part's Size covers the FULL mesh bbox including any strays, so the
	-- conversion runs through that and not through the body.
	local bodySizeX = P.BODY_WIDTH_STUDS * M.FULL_W / (2 * M.RAD)
	local partScale = bodySizeX / source.Size.X
	local studsPerMeshUnit = bodySizeX / M.FULL_W
	local bodyRadiusStuds = M.RAD * studsPerMeshUnit
	local bodyHeightStuds = M.HEIGHT * studsPerMeshUnit
	log("[Skins] mesh: %d stray verts, bbox %.4f wide -> part scaled %.4fx so the body is %.2f studs",
		M.strayVerts, M.FULL_W, partScale, 2 * bodyRadiusStuds)
	-- height in the SAME units the field works in, i.e. body-radii, so a twist
	-- given as degrees bottom-to-top converts to a slope per unit qy
	local bodyHeightRadii = M.HEIGHT / M.RAD
	local yHalfRadii = bodyHeightRadii / 2
	local pxPerStud = P.VIEW_FRAME_PX
		/ (2 * P.VIEW_DISTANCE * math.tan(math.rad(P.VIEW_FOV_DEG) / 2))
	log("[Skins] view: %d studs, FOV %d, %d px frame -> %.2f px/stud; body radius %.2f studs (%.0f px wide)",
		P.VIEW_DISTANCE, P.VIEW_FOV_DEG, P.VIEW_FRAME_PX, pxPerStud, bodyRadiusStuds,
		2 * bodyRadiusStuds * pxPerStud)

	-- ---- the sample subset used by the coverage search ----
	local sample = {}
	do
		local n = 0
		for idx = 0, W * W - 1 do
			if buffer.readu8(MASK, idx) == 1 then
				n += 1
				if n % P.COVERAGE_SAMPLE_STRIDE == 0 then
					local o = idx * 12
					table.insert(sample, {
						buffer.readf32(POS, o), buffer.readf32(POS, o + 4), buffer.readf32(POS, o + 8),
					})
				end
			end
		end
	end
	log("[Skins] coverage search samples %d of %d covered texels", #sample, M.covered)

	-- White where the field is positive, softened across EDGE_SOFT. Because the
	-- field was scaled into a signed distance, this band is the same physical
	-- width at every latitude -- including where the stripes are finest.
	local function whiteAt(qx: number, qy: number, qz: number,
		k: number, phase: number, twist: number, rCap: number): number
		local stripe = smoothstep(-P.EDGE_SOFT, P.EDGE_SOFT,
			stripeField(qx, qy, qz, k, phase, twist, yHalfRadii))
		-- Inside rCap the crown cap takes over, in solid white. r is the
		-- horizontal radius, so this catches BOTH poles -- the underside
		-- converges just as hard as the top and fanned just as badly.
		local r = math.sqrt(qx * qx + qz * qz)
		local capMix = smoothstep(rCap - P.EDGE_SOFT, rCap + P.EDGE_SOFT, r)
		return capMix * stripe + (1 - capMix)
	end

	-- The twist rate at the latitude whose horizontal radius is r. On the body
	-- h^2 + r^2 ~ 1, so (1 - h^2) is r^2: the rate falls off as the SQUARE of the
	-- radius, which is why it is already negligible by the time the stripes are
	-- narrow enough to cap.
	local function slopeAtRadius(r: number, twist: number): number
		return alphaRate(math.sqrt(math.max(0, 1 - r * r)), twist) / yHalfRadii
	end

	-- How far the boundary leans off the meridian at radius r. This is the number
	-- that says whether it can resolve: 0 degrees is a straight meridian
	-- converging cleanly to a point, and large angles are the helix cutting
	-- across longitude as the longitudes themselves converge.
	local function boundaryTiltDeg(r: number, twist: number): number
		return math.deg(math.atan(r * slopeAtRadius(r, twist)))
	end

	-- Stripe width at horizontal radius r, in studs, including the narrowing the
	-- shear causes: a leaning stripe is thinner across than it is around.
	local function stripeWidthStuds(r: number, count: number, twist: number): number
		local around = 2 * math.pi * r * bodyRadiusStuds / count
		local sl = slopeAtRadius(r, twist)
		return around / math.sqrt(1 + (r * sl) ^ 2)
	end

	-- Where to stop the stripes: the radius at which their width falls to
	-- CAP_AT_STRIPE_PX. Solved by bisection because the twist term makes it
	-- awkward to invert, and width is monotone in r.
	local function capRadius(count: number, twist: number): (number, number)
		local want = P.CAP_AT_STRIPE_PX / pxPerStud
		local lo, hi = 0.0, 1.0
		for _ = 1, 40 do
			local mid = (lo + hi) / 2
			if stripeWidthStuds(mid, count, twist) < want then lo = mid else hi = mid end
		end
		local r = (lo + hi) / 2
		return r, stripeWidthStuds(r, count, twist) * pxPerStud
	end

	-- How much of the surface the crown caps take, measured on the real texel set
	-- rather than assumed from a sphere.
	local function capFraction(rCap: number): number
		local n = 0
		for _, q in ipairs(sample) do
			if math.sqrt(q[1] * q[1] + q[3] * q[3]) < rCap then n += 1 end
		end
		return n / #sample
	end

	-- ---- (no balance search: see below) ----
	--[[ The latitude cuts needed their offset solved so the two sides came out
	     equal. Meridian stripes do not: cos(k*theta) is positive over exactly
	     half of any full turn, at EVERY latitude, so the split is 50/50 by
	     construction. It is measured below anyway, because the texel-weighted
	     fraction is not quite the surface fraction -- the UV island does not
	     sample the body uniformly -- and a drift there would mean the map is
	     wrong, not the maths.
	--]]
	-- ---- generate one slime per hue ----
	for _, c in ipairs(workspace:GetChildren()) do
		if c.Name == P.ROOT_NAME then c:Destroy() end
	end
	local root = Instance.new("Model")
	root.Name = P.ROOT_NAME
	root.Parent = workspace

	local localOff = Vector3.new(M.CX, M.CY, M.CZ)
	local buf = buffer.create(W * W * 4)
	local worstFeaturePx, worstFeatureWhat = math.huge, "?"
	local rows = {}
	local texCount = 0
	local worstGap, worstGapHue = math.huge, "?"

	do
		local balLo, balHi = math.huge, -math.huge

		for hi_, hue in ipairs(HUES) do
			Y.tick()
			local spec = P.STRIPE_SPECS[((hi_ - 1) % #P.STRIPE_SPECS) + 1]
			local count = spec.count
			assert(count % 2 == 0, "[Skins] stripe count must be even to split 50/50")
			local k = count // 2
			local phase = math.rad(spec.phaseDeg)
			local twist = math.rad(spec.twistDeg)
			local rCap, capPx = capRadius(count, twist)

			-- measure the split rather than assume it
			local hit = 0
			for si, q in ipairs(sample) do
				if si % P.CALIBRATE_TICK_EVERY == 0 then Y.tick() end
				hit += whiteAt(q[1], q[2], q[3], k, phase, twist, rCap)
			end
			local measured = hit / #sample
			balLo = math.min(balLo, measured)
			balHi = math.max(balHi, measured)

			-- The stripe width at the equator is what the design lives or dies by;
			-- the width AT THE CAP is the smallest one that ever renders.
			local featureStuds = stripeWidthStuds(1.0, count, twist)
			local featurePx = featureStuds * pxPerStud
			if capPx < worstFeaturePx then
				worstFeaturePx = capPx
				worstFeatureWhat = string.format("%d stripes at the cap", count)
			end
			local capFrac = capFraction(rCap)

			local base = hue.color
			local accent, lumGap, rgbDist = accentFor(base)
			if rgbDist < worstGap then
				worstGap = rgbDist
				worstGapHue = string.format("%s (rgb %.3f, lum %.3f)", hue.name, rgbDist, lumGap)
			end

			-- paint
			local br, bg, bb = base.R, base.G, base.B
			local ar, ag, ab = accent.R, accent.G, accent.B
			for y = 0, W - 1 do
				if y % P.PAINT_TICK_ROWS == 0 then Y.tick() end
				for x = 0, W - 1 do
					local idx = y * W + x
					local off = idx * 4
					if buffer.readu8(MASK, idx) ~= 0 then
						local o = idx * 12
						local qx = buffer.readf32(POS, o)
						local qy = buffer.readf32(POS, o + 4)
						local qz = buffer.readf32(POS, o + 8)
						local a = whiteAt(qx, qy, qz, k, phase, twist, rCap)
						buffer.writeu8(buf, off, math.floor(math.clamp(br + (ar - br) * a, 0, 1) * 255 + 0.5))
						buffer.writeu8(buf, off + 1, math.floor(math.clamp(bg + (ag - bg) * a, 0, 1) * 255 + 0.5))
						buffer.writeu8(buf, off + 2, math.floor(math.clamp(bb + (ab - bb) * a, 0, 1) * 255 + 0.5))
						buffer.writeu8(buf, off + 3, 255)
					else
						buffer.writeu8(buf, off, 0)
						buffer.writeu8(buf, off + 1, 0)
						buffer.writeu8(buf, off + 2, 0)
						buffer.writeu8(buf, off + 3, 255)
					end
				end
			end
			local img = AssetService:CreateEditableImage({ Size = Vector2.new(W, W) })
			img:WritePixelsBuffer(Vector2.zero, Vector2.new(W, W), buf)
			Y.mark()
			texCount += 1

			-- assemble this slime
			local at = P.ORIGIN + Vector3.new((hi_ - 1) * P.HUE_SPACING, 0, 0)
			-- ORIGIN.Y is the ground; lift by half the body so it rests on it
			local bodyCF = CFrame.new(at.X, at.Y + bodyHeightStuds / 2, at.Z)
				* CFrame.Angles(0, math.rad(P.BODY_YAW_DEG), 0)

			local slime = Instance.new("Model")
			slime.Name = string.format("%s_%dstripe", hue.name, count)
			slime.Parent = root

			local body = source:Clone()
			body.Size = source.Size * partScale
			body.Name = "body"
			body.Color = Color3.new(1, 1, 1)
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

			-- The part ORIGIN is the full mesh bbox centre, which the stray cube
			-- shoves hundreds of studs off the visible body, so Model:GetPivot and
			-- Model:GetBoundingBox both point at empty air. Record where the body
			-- actually is; anything repositioning these needs it.
			slime:SetAttribute("BodyCentre", Vector3.new(at.X, at.Y + bodyHeightStuds / 2, at.Z))
			slime:SetAttribute("Tier", "Balanced")
			slime:SetAttribute("Hue", hue.name)
			slime:SetAttribute("Shape", string.format("%d-stripe-twist%d", count, spec.twistDeg))
			slime:SetAttribute("StripeCount", count)
			slime:SetAttribute("TwistDeg", spec.twistDeg)
			slime:SetAttribute("PhaseDeg", spec.phaseDeg)
			slime:SetAttribute("WhiteFraction", measured)

			table.insert(rows, string.format(
				"[Skins]   %-7s %d stripes twist %3d deg | white %.1f%% | equator %.1f px"
					.. " | cap r=%.3f at %.1f px | boundary tilt %.1f deg at equator -> %.2f deg at cap"
					.. " | cap covers %.1f%%",
				hue.name, count, spec.twistDeg, measured * 100, featurePx,
				rCap, capPx, boundaryTiltDeg(1.0, twist), boundaryTiltDeg(rCap, twist),
				capFrac * 100))
		end

		table.insert(rows, string.format(
			"[Skins] split is 50/50 by construction | measured %.1f-%.1f%% across the six",
			balLo * 100, balHi * 100))
	end

	for _, r in ipairs(rows) do table.insert(lines, r) end

	assert(worstFeaturePx >= P.MIN_FEATURE_PX, string.format(
		"[Skins] smallest feature is %.1f px (%s) at %d studs, under the %d px floor -- "
			.. "it would half-resolve, which is the exact failure this design exists to avoid",
		worstFeaturePx, worstFeatureWhat, P.VIEW_DISTANCE, P.MIN_FEATURE_PX))
	log("[Skins] smallest boundary excursion: %.1f px (%s), floor is %d px",
		worstFeaturePx, worstFeatureWhat, P.MIN_FEATURE_PX)
	log("[Skins] worst hue against white: %s", worstGapHue)

	local perTexKB = W * W * 4 / 1024
	log("[Skins] MEMORY: %d x %d RGBA = %.0f KB per skin | %d skins = %.1f MB | all 65 = %.1f MB",
		W, W, perTexKB, texCount, texCount * perTexKB / 1024, 65 * perTexKB / 1024)
	-- Sharing is not available here at all: each slime carries a DIFFERENT
	-- boundary, so there is no shared image to tint. It would only become an
	-- option if a whole set wore one curve, which is the opposite of the design.

	-- Reported, not asserted: an overrun is a performance fault, not a wrong
	-- image, and throwing away 24 finished textures over it is worse than saying
	-- so. The continuity of the pattern is what the asserts above guard.
	log("[Skins] WATCHDOG: yielded %d times | longest hold %.1f ms (budget %d ms)",
		Y.yields(), Y.worstMs(), P.YIELD_MS)
	if Y.worstMs() > 100 then
		warn(string.format("[Skins] a loop held the main thread %.0f ms -- over the 100 ms "
			.. "margin; the guard is not covering it", Y.worstMs()))
	end
	log("[Skins] built workspace.%s: %d slimes in %.2f s", P.ROOT_NAME, texCount, os.clock() - t0)
	log("[Skins] undo with workspace.%s:Destroy()", P.ROOT_NAME)

	local outStr = table.concat(lines, "\n")
	print(outStr)
	return outStr
end

return run()
