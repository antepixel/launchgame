--!strict
-- BUILD_SKINS.luau -- STANDALONE REBUILD SCRIPT FOR THE TWO-TONE SLIME SKINS.
--
-- Paste the whole file into the Studio command bar and it builds
-- workspace.SkinLineup from nothing: six slimes, one per hue, each white and
-- its hue in equal measure across one boundary curve, on a procedurally
-- generated EditableImage. No other file needs to be present.
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
-- SO THE DESIGN IS THE BOUNDARY. With the split fixed at 50/50 there is nothing
-- left to vary except the curve where the two colours meet: where it sits and
-- what it does as it travels round the body. That is the entire creative
-- surface here, and every one of the six entries below is one curve.
--
-- WHICH IS WHY COVERAGE CANNOT BE THE RARITY AXIS. An earlier pass escalated
-- rarity as accent coverage -- 10/25/42/60% -- and that was wrong from the
-- start, not merely mistuned: any ladder built on coverage forces every rung
-- except the middle to be lopsided, and lopsided is exactly what makes the
-- lesser colour read as paint. Rarity needs a different axis entirely. It is
-- DELIBERATELY NOT SOLVED HERE, and nothing below encodes a tier.
--
-- THE RESOLVE RULE STILL BINDS, it just has less to bite on. A feature is either
-- clearly visible at 40 studs or it is not present -- three cheap-looking
-- results in this project were all the same mistake, a feature that HALF
-- resolves: 1-texel stars that mipped to mush, 1 px halo gaps that merged, and
-- sub-stud motes that read as stray balls. At 50/50 both regions are half a body
-- and cannot be too small; the only thing that can is a wave's excursion, so
-- that is what gets measured and asserted against MIN_FEATURE_PX.
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
-- The balance search INTEGRATES that soft value rather than counting texels,
-- because a texel on the boundary is genuinely part white. Worth knowing if you
-- port this: 0 is truthy in Lua, so a boolean call site keeps compiling and
-- silently counts every texel the moment fields start returning numbers.
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
-- NO SPOTS, NO PATCHES, NO WEDGES -- and the reasons differ, which matters.
-- Wedges converge to a point at the pole, so their width goes to zero by
-- construction; any shape sized as a function of latitude half-resolves
-- somewhere. Spots and patches had no such flaw and passed the pixel rule at
-- 30.6 px, and were still cut, because on a rounded body a scatter of blobs
-- reads as STAINING however cleanly its edges land. Resolving is necessary and
-- not sufficient.
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
	-- NOT a rarity axis. Both colours are the body; neither is applied to the
	-- other. The search below solves each boundary's offset so the two sides come
	-- out at this ratio, which is what stops either colour reading as paint.
	BALANCE = 0.50,
	COVERAGE_TOLERANCE = 0.004,      -- binary search stops inside this
	COVERAGE_ITERS = 24,
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

	-- ---- the boundary, which IS the design ----
	-- With the split fixed at 50/50 the only thing left to vary is the curve
	-- itself: where it sits and what it does as it goes round. Amplitude is in
	-- body-radii, so 0.16 is a peak-to-trough of 0.32 = 2.24 studs = 22.5 px at
	-- 40 studs. A wave shallower than that is a wobble rather than a shape.
	TILT_GENTLE_DEG = 22,
	TILT_STEEP_DEG = 58,
	WAVE_AMP = 0.16,

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
local function planeNormal(tiltDeg: number): Vector3
	local t = math.rad(tiltDeg)
	return Vector3.new(math.sin(t), math.cos(t), 0).Unit
end
local N_GENTLE = planeNormal(P.TILT_GENTLE_DEG)
local N_STEEP = planeNormal(P.TILT_STEEP_DEG)

-- AZIMUTHAL HARMONICS WITHOUT atan2. cos(k*theta) has no seam as a function of
-- (x, z) -- it is a polynomial in x/r and z/r -- but atan2 does have a branch
-- cut, and computing the angle first would import a discontinuity the 3D
-- evaluation exists to avoid. Chebyshev on cos(theta) keeps it continuous.
--
-- The result is damped by r so it vanishes at the poles, where theta is
-- undefined. Without that the wave would fight itself to a point at the top.
local function harmonic(qx: number, qz: number, k: number): number
	local r = math.sqrt(qx * qx + qz * qz)
	if r < 1e-6 then return 0 end
	local c = qx / r
	local v
	if k == 2 then
		v = 2 * c * c - 1
	elseif k == 3 then
		v = 4 * c * c * c - 3 * c
	else
		v = c
	end
	return r * v
end

-- Soft threshold: 1 well inside the shape, 0 well outside, smooth across a band
-- EDGE_SOFT wide. Everything below goes through this, so no boundary anywhere is
-- a hard texel step.
local E = P.EDGE_SOFT
local function inside(value: number, edge: number): number
	-- accent where value < edge
	return 1 - smoothstep(edge - E, edge + E, value)
end
local function above(value: number, edge: number): number
	-- accent where value > edge
	return smoothstep(edge - E, edge + E, value)
end

-- ===================================================================
-- THE SIX BOUNDARIES.
--
-- Each is field(q, c) -> a signed number: white where it is positive, hue where
-- it is negative, and the sign change IS the design. c slides the curve up and
-- down the body and is the one knob the 50/50 search turns, so every entry only
-- has to describe the curve's SHAPE, not its position.
--
-- waveStuds reports the peak-to-trough excursion, which is the only thing here
-- that can be too small to read; a plane cut has none and reports the body.
-- ===================================================================
local BOUNDARIES = {
	{
		name = "level",
		-- a flat cut: the plainest possible two-tone, and the control for the rest
		field = function(qx: number, qy: number, qz: number, c: number): number
			return qy - c
		end,
		waveStuds = function(radius: number): number return radius end,
	},
	{
		name = "tilt-gentle",
		field = function(qx: number, qy: number, qz: number, c: number): number
			return qx * N_GENTLE.X + qy * N_GENTLE.Y + qz * N_GENTLE.Z - c
		end,
		waveStuds = function(radius: number): number return radius end,
	},
	{
		name = "tilt-steep",
		-- close to a left/right division rather than a top/bottom one
		field = function(qx: number, qy: number, qz: number, c: number): number
			return qx * N_STEEP.X + qy * N_STEEP.Y + qz * N_STEEP.Z - c
		end,
		waveStuds = function(radius: number): number return radius end,
	},
	{
		name = "wave2",
		-- two humps: reads as a soft S sweeping round the body
		field = function(qx: number, qy: number, qz: number, c: number): number
			return qy - c - P.WAVE_AMP * harmonic(qx, qz, 2)
		end,
		waveStuds = function(radius: number): number return 2 * P.WAVE_AMP * radius end,
	},
	{
		name = "wave3",
		-- three humps: a scalloped crown
		field = function(qx: number, qy: number, qz: number, c: number): number
			return qy - c - P.WAVE_AMP * harmonic(qx, qz, 3)
		end,
		waveStuds = function(radius: number): number return 2 * P.WAVE_AMP * radius end,
	},
	{
		name = "tilt-wave2",
		-- a tilted cut that also undulates, so neither end of the curve is level
		field = function(qx: number, qy: number, qz: number, c: number): number
			return qx * N_GENTLE.X + qy * N_GENTLE.Y + qz * N_GENTLE.Z
				- c - P.WAVE_AMP * harmonic(qx, qz, 2)
		end,
		waveStuds = function(radius: number): number return 2 * P.WAVE_AMP * radius end,
	},
}

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

	-- White where the field is positive, softened across EDGE_SOFT so the boundary
	-- is never a texel step.
	local function whiteAt(b, qx: number, qy: number, qz: number, c: number): number
		return smoothstep(-P.EDGE_SOFT, P.EDGE_SOFT, b.field(qx, qy, qz, c))
	end

	-- ---- slide the boundary until the two sides balance ----
	-- The offset runs over the body's own extent, not 0..2: these fields are
	-- signed distances along an axis through a body whose qy only reaches ~0.68,
	-- and a search range wider than the body wastes its first iterations outside
	-- it. Monotone in c by construction -- raising the cut can only grow the side
	-- below it -- which is what makes a bisection valid here.
	--
	-- Ticks INSIDE the sample loop, not just per iteration: 24 iterations over
	-- ~39k samples is a million field evaluations, and ticking only at the
	-- iteration boundary previously measured a 522 ms main-thread hold.
	local function balance(b, target: number): (number, number)
		local lo, hi = -1.2, 1.2
		local got = 0
		for _ = 1, P.COVERAGE_ITERS do
			local mid = (lo + hi) / 2
			local hit = 0
			for si, q in ipairs(sample) do
				if si % P.CALIBRATE_TICK_EVERY == 0 then Y.tick() end
				hit += whiteAt(b, q[1], q[2], q[3], mid)
			end
			got = hit / #sample
			if math.abs(got - target) <= P.COVERAGE_TOLERANCE then
				return mid, got
			end
			-- raising the cut shrinks the white side, so the sense is inverted
			if got > target then lo = mid else hi = mid end
		end
		return (lo + hi) / 2, got
	end

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
		local target = P.BALANCE
		local balLo, balHi = math.huge, -math.huge

		for hi_, hue in ipairs(HUES) do
			Y.tick()
			local shape = BOUNDARIES[((hi_ - 1) % #BOUNDARIES) + 1]
			local k, measured = balance(shape, target)
			balLo = math.min(balLo, measured)
			balHi = math.max(balHi, measured)

			local featureStuds = shape.waveStuds(bodyRadiusStuds)
			local featurePx = featureStuds * pxPerStud
			if featurePx < worstFeaturePx then
				worstFeaturePx = featurePx
				worstFeatureWhat = shape.name
			end

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
						local a = whiteAt(shape, qx, qy, qz, k)
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
			slime.Name = string.format("%s_%s", hue.name, shape.name)
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
			slime:SetAttribute("Shape", shape.name)
			slime:SetAttribute("WhiteFraction", measured)
			slime:SetAttribute("BoundaryOffset", k)

			table.insert(rows, string.format(
				"[Skins]   %-7s %-11s offset %+.4f  white %.1f%%  wave %.1f px",
				hue.name, shape.name, k, measured * 100, featurePx))
		end

		table.insert(rows, string.format(
			"[Skins] balance target %.0f%% | measured %.1f-%.1f%% across the six",
			target * 100, balLo * 100, balHi * 100))
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
