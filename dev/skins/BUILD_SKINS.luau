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
-- MERIDIAN, NOT LATITUDE. Every earlier pass divided the body HORIZONTALLY, by
-- latitude, and every one produced a band -- a hat, a belt, a sash, a diagonal
-- sash. Stripes running pole to pole divide it by LONGITUDE, and that single
-- change is the difference between a marking and a beach ball. Six or eight
-- stripes around the full circumference, alternating white and hue.
--
-- WHICH IS WHY COVERAGE CANNOT BE THE RARITY AXIS. An earlier pass escalated
-- rarity as accent coverage -- 10/25/42/60% -- and that was wrong from the
-- start, not merely mistuned: any ladder built on coverage forces every rung
-- except the middle to be lopsided, and lopsided is exactly what makes the
-- lesser colour read as paint. Rarity needs a different axis entirely. It is
-- DELIBERATELY NOT SOLVED HERE, and nothing below encodes a tier.
--
-- THE RESOLVE RULE STILL BINDS, AND IT NOW HAS A DELIBERATE EXCEPTION. A feature
-- is either clearly visible at 40 studs or it is not present -- three
-- cheap-looking results in this project were the same mistake, a feature that
-- HALF resolves: 1-texel stars that mipped to mush, 1 px halo gaps that merged,
-- sub-stud motes that read as stray balls. Stripe width at the equator is what
-- gets measured against MIN_FEATURE_PX, and it clears it by a wide margin: 73.7
-- px at 6 stripes, 55.3 px at 8.
--
-- THE EXCEPTION IS THE CROWN, AND IT IS THE POINT RATHER THAN A FAILURE. Stripe
-- width is proportional to the horizontal radius, so it falls to zero at the
-- pole by construction. Measured, it drops under the 8 px floor only above
-- r = 0.109 (6 stripes) or r = 0.145 (8), which is the top 1.1% / 2.0% of the
-- surface -- a cap under 0.05 studs tall. A beach ball converges at its crown
-- and reads as CORRECT there; that is what the object is. An earlier pass
-- rejected longitude wedges for precisely this property and was wrong to. The
-- rule was always about features that half-resolve where they are supposed to be
-- legible, not about a convergence the design is built around.
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
-- half of any full turn, at every latitude, so meridian stripes are 50/50 for
-- free. Measured across the six on the real texel set: 49.5% to 51.6%, the
-- spread being UV sampling density rather than the maths.
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
	SOURCE_MODEL = "slime_uv",       -- the UNWRAPPED body; lineup meshes have no UVs
	SOURCE_PART = "default",
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
	STRIPE_SPECS = {
		{ count = 6, phaseDeg = 0 },
		{ count = 8, phaseDeg = 0 },
		{ count = 6, phaseDeg = 30 },
		{ count = 8, phaseDeg = 22.5 },
		{ count = 6, phaseDeg = 15 },
		{ count = 8, phaseDeg = 11.25 },
	},

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
-- THE SIX SHAPES.
--
-- Each is accent(q, k) -> boolean, where q is a point on the body in
-- body-radius units and k is the ONE knob the coverage search turns. Every
-- shape is written so that a LARGER k means MORE accent, which is what lets a
-- single monotone binary search calibrate all six.
--
-- minStuds(k, radius) returns the shape's smallest dimension, which the build
-- converts to pixels at 40 studs and asserts against MIN_FEATURE_PX.
-- ===================================================================
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
-- THE CONVERGENCE AT THE POLE IS WANTED. An earlier pass rejected longitude
-- wedges for exactly the property being asked for here -- stripe width goes to
-- zero at the pole -- and damped the harmonic by r to kill it. A beach ball
-- converges at the crown and reads as correct, so there is NO damping of the
-- pattern here.
--
-- THE ONE r THAT REMAINS IS NOT DAMPING, AND THE DISTINCTION IS THE SUBTLE PART.
-- T_k is dimensionless, so a fixed smoothstep band around it would be a fixed
-- band in ANGLE -- and an angular band is a spatial band that shrinks with r,
-- which near the crown would leave the edges hard exactly where the stripes are
-- finest. Scaling by r/k converts the field into a signed DISTANCE: near a zero
-- crossing |dT/dtheta| = k and arc length is r*dtheta, so d(T*r/k)/ds = 1
-- exactly. That makes the antialiasing the same physical width everywhere.
-- Because r/k is strictly positive it cannot move a single boundary -- the sign
-- is untouched, so the stripes still run to a point at the pole.
-- ===================================================================
local function stripeField(qx: number, qy: number, qz: number,
	k: number, cs: number, sn: number): number
	local r = math.sqrt(qx * qx + qz * qz)
	if r < 1e-9 then return 0 end        -- the pole itself: one texel, either way
	local c = (qx * cs + qz * sn) / r    -- cos(theta - phase)
	-- T_k by the standard recurrence; T_k(cos t) == cos(k t)
	local t0, t1 = 1.0, c
	for _ = 2, k do
		t0, t1 = t1, 2 * c * t1 - t0
	end
	local t = (k == 0) and 1.0 or t1
	return t * r / k
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

	local mnx, mxx = math.huge, -math.huge
	local mny, mxy = math.huge, -math.huge
	local mnz, mxz = math.huge, -math.huge
	-- the FULL bbox too, stray cube included: that is what the part's Size covers,
	-- so it is the only way to convert mesh units to studs
	local amnx, amxx = math.huge, -math.huge
	for _, id in ipairs(verts) do
		Y.tick()
		local p = em:GetPosition(id)
		amnx = math.min(amnx, p.X); amxx = math.max(amxx, p.X)
		if p.Y < 0 then                      -- excludes the stray cube ~500 above
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
		local p1, p2, p3 = em:GetPosition(fv[1]), em:GetPosition(fv[2]), em:GetPosition(fv[3])
		if p1.Y > 0 or p2.Y > 0 or p3.Y > 0 then
			skipped += 1
			continue
		end
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
		FULL_W = amxx - amnx,
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

	local srcModel = workspace:FindFirstChild(P.SOURCE_MODEL)
	assert(srcModel, string.format(
		"[Skins] workspace.%s not found. These skins need the UNWRAPPED body mesh; "
			.. "the lineup slimes have exactly ONE distinct UV coordinate and cannot "
			.. "display any texture at all.", P.SOURCE_MODEL))
	local src = srcModel:FindFirstChild(P.SOURCE_PART) :: BasePart
	assert(src, "[Skins] " .. P.SOURCE_MODEL .. "." .. P.SOURCE_PART .. " not found")

	local W = P.TEX
	local Y = newYielder(P.YIELD_MS)
	local M = buildUVMap((src :: any).MeshId, W, W, Y)
	log("[Skins] UV map: %d texels covered (%.1f%% of sheet), %d seam tris, %d cube faces skipped",
		M.covered, 100 * M.covered / (W * W), M.seamTris, M.skipped)

	local POS, MASK = M.POS, M.MASK

	local grown = dilate(POS, MASK, W, W, 3, Y)
	log("[Skins] dilated %d texels past the island edge (bilinear guard)", grown)

	-- Mesh units -> studs. The part's Size covers the FULL mesh bbox, which the
	-- stray cube inflates, so the conversion has to come from that and not from
	-- the body. Every pixel figure below depends on this being right; it was
	-- getting this wrong that framed an earlier shot at a fifth of body size.
	local studsPerMeshUnit = src.Size.X / M.FULL_W
	local bodyRadiusStuds = M.RAD * studsPerMeshUnit
	local bodyHeightStuds = M.HEIGHT * studsPerMeshUnit
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
		k: number, cs: number, sn: number): number
		return smoothstep(-P.EDGE_SOFT, P.EDGE_SOFT, stripeField(qx, qy, qz, k, cs, sn))
	end

	-- WHERE DO THE STRIPES STOP RESOLVING? Stripe width at horizontal radius r is
	-- the circumference over the count, so it falls to the 8 px floor at a
	-- specific r and is finer than that above it. Census the real texel set rather
	-- than assume the body is a sphere.
	local function convergence(count: number): (number, number, number)
		local floorStuds = P.MIN_FEATURE_PX / pxPerStud
		local rCrit = floorStuds * count / (2 * math.pi * bodyRadiusStuds)
		local below, topY = 0, -math.huge
		for _, q in ipairs(sample) do
			local r = math.sqrt(q[1] * q[1] + q[3] * q[3])
			if r < rCrit then
				below += 1
				if math.abs(q[2]) > topY then topY = math.abs(q[2]) end
			end
		end
		return rCrit, below / #sample, topY
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
			local ph = math.rad(spec.phaseDeg)
			local cs, sn = math.cos(ph), math.sin(ph)

			-- measure the split rather than assume it
			local hit = 0
			for si, q in ipairs(sample) do
				if si % P.CALIBRATE_TICK_EVERY == 0 then Y.tick() end
				hit += whiteAt(q[1], q[2], q[3], k, cs, sn)
			end
			local measured = hit / #sample
			balLo = math.min(balLo, measured)
			balHi = math.max(balHi, measured)

			-- Stripe width at the equator: the body's circumference over the
			-- count. This is the number the design lives or dies by.
			local featureStuds = 2 * math.pi * bodyRadiusStuds / count
			local featurePx = featureStuds * pxPerStud
			if featurePx < worstFeaturePx then
				worstFeaturePx = featurePx
				worstFeatureWhat = string.format("%d stripes", count)
			end
			local rCrit, fineFrac, fineTopY = convergence(count)

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
						local a = whiteAt(qx, qy, qz, k, cs, sn)
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

			local body = src:Clone()
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
			slime:SetAttribute("Shape", string.format("%d-stripe", count))
			slime:SetAttribute("StripeCount", count)
			slime:SetAttribute("PhaseDeg", spec.phaseDeg)
			slime:SetAttribute("WhiteFraction", measured)

			table.insert(rows, string.format(
				"[Skins]   %-7s %d stripes phase %5.1f deg | white %.1f%% | equator %.2f studs = %.1f px"
					.. " | under floor above r=%.3f: %.2f%% of surface, top %.3f",
				hue.name, count, spec.phaseDeg, measured * 100, featureStuds, featurePx,
				rCrit, fineFrac * 100, fineTopY))
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
