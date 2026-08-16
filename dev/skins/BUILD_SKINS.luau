--!strict
-- BUILD_SKINS.luau -- STANDALONE REBUILD SCRIPT FOR THE TIER 1-4 SLIME SKINS.
--
-- Paste the whole file into the Studio command bar and it builds
-- workspace.SkinLineup from nothing: 24 slimes, four tiers by six hues, each
-- with its own procedurally generated EditableImage. No other file needs to be
-- present.
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
-- ONE RULE DECIDES EVERYTHING: a feature is either clearly visible at 40 studs
-- or it is not present. Nothing in between. This project has produced three
-- cheap-looking results in a row and all three were the same mistake -- a
-- feature that HALF resolves. 1-texel stars that mipped to mush; a 48-blade halo
-- whose 1 px gaps merged into a washed-out ring; sub-stud motes that read as
-- stray balls. The giant slime looks good for the opposite reason: it is one
-- saturated colour that resolves perfectly at every distance.
--
-- So the resolve threshold is enforced MECHANICALLY here, not by eye. Every
-- shape reports its smallest dimension, that is converted to pixels at 40 studs,
-- and the build ASSERTS it clears MIN_FEATURE_PX. A pattern that would turn to
-- mush stops the build instead of shipping.
--
-- 40 studs, FOV 70, a 563 px tall frame => 10.05 px per stud. The body is 14
-- studs across, so it lands 141 px wide. 8 px is therefore 0.80 studs, or 0.114
-- body-radii. That single number is why there are no speckles, no thin stripes
-- and no texture inside a shape anywhere below.
--
-- RARITY IS COVERAGE, AND IT IS MEASURED, NOT ESTIMATED. The one axis that
-- escalates across tiers is how much of the body the accent colour takes:
-- Common 10%, Uncommon 25%, Rare 42%, Epic 60%. Complexity is explicitly NOT the
-- axis -- complexity is what reads as cheap. Coverage is not approximated from a
-- formula either: each shape has one scalar knob, and the build binary-searches
-- it against the REAL texel set until measured coverage hits the tier target, so
-- the ladder is exact on the actual mesh rather than on an idealised sphere.
--
-- SHAPE VARIES WITHIN A TIER, COVERAGE VARIES ACROSS TIERS. These two axes are
-- orthogonal on purpose. Six placements -- belt-high, belt-low, cap, foot,
-- split-shallow, split-steep -- appear once per tier, so within-tier variety is
-- a genuinely different pattern rather than only a different hue, while the
-- rarity read stays clean because every shape in a tier carries the same
-- coverage. The assignment rotates by tier, so a hue wears a different pattern
-- at each rarity.
--
-- RESOLVING IS NECESSARY AND NOT SUFFICIENT -- spots and patches are gone. Both
-- passed the pixel rule comfortably (30.6 px features) and both still looked
-- cheap, because on a rounded body a scatter of blobs reads as STAINING however
-- cleanly its edges land. What survives is the family that follows the body's
-- own form: bands and divisions. Variety then comes from where the band sits and
-- how the plane is angled, not from adding more kinds of thing.
--
-- NO WEDGES, AND THE REASON GENERALISES. Longitude wedges were the obvious
-- seventh shape and they are a trap: they converge to a point at the pole, so
-- the feature width goes to zero there by construction. Any shape whose size is
-- a function of latitude will half-resolve somewhere. Every shape kept here has
-- a width that is bounded away from zero over the whole surface.
--
-- THE ACCENT IS ONE CREAM, AND IT IS A COLOUR RATHER THAN AN ABSENCE OF ONE.
-- Two failed versions got here. A darker shade of the base hue reads as SHADING,
-- because a curved lit body already spans that luminance range from highlight to
-- flank. Near-black and near-white fix that and read as DIRT -- both are
-- absences of colour, so on a saturated toy body they look like a stain or a
-- blown highlight rather than a second material. A warm cream is neither: it
-- sits in the same palette as the bodies, and lighting still cannot produce
-- cream on green, so the constraint that killed version one is still satisfied.
--
-- ONE CONTRAST NUMBER IS NOT ENOUGH. Luminance gap alone rejects cream on
-- yellow -- only 0.13 -- and cream on yellow reads perfectly well, because the
-- separation there is chroma, not brightness. Both luminance gap and RGB
-- distance are measured and reported; the worst hue is chosen on RGB distance.
--
-- EVERY BOUNDARY IS ANTIALIASED, AND THAT IS THE REAL FIX FOR THE BLOCKY LOOK.
-- A hard threshold stair-steps at ANY resolution -- 256 simply made it obvious.
-- Shapes return a 0..1 coverage value through a smoothstep band EDGE_SOFT wide,
-- not a boolean. A soft boundary is NOT a sub-resolution feature and does not
-- violate the 8 px rule: that rule is about how big a shape is, not how sharp
-- its border is. Coverage therefore INTEGRATES the soft value rather than
-- counting texels, which is what keeps the tier percentages honest.
--
-- 1024 x 1024, BECAUSE THE 256 DERIVATION ANSWERED THE WRONG QUESTION. That
-- arithmetic -- island 32.8% of the sheet, half of it facing camera, 0.164*R^2 =
-- 10,300 px, so R = 250 -- is correct for AREA and irrelevant for EDGES. Putting
-- one texel per pixel places the stair steps at exactly the size the eye
-- resolves. Edges want headroom over the sampling rate, not parity with it.
--
-- MEMORY IS THE COST OF THAT, AND IT IS NOT SMALL. 1024 RGBA is 4 MB per skin:
-- 24 MB for one tier, 96 MB for 24 skins, 260 MB at the full 65. That last
-- number is past what a Roblox place should spend on slime skins. 512 halves the
-- linear resolution for a quarter of the memory -- 1 MB per skin, 65 MB at 65 --
-- and with antialiasing doing the real work on edges, 512 is the likely shipping
-- value. TEX is the only line that needs changing.
--
-- THE FACE IS MASKED OUT OF THE PATTERN. The eyes and blush are separate
-- MeshParts sitting proud of the body, and they read best against a saturated
-- mid-tone rather than against a pale accent -- white eye_white on a pale accent
-- washes out. A cone around the face direction is forced to base colour, with a
-- soft edge so it is not a visible disc. The mask is applied BEFORE coverage is
-- measured, so the tier percentages are true of the finished skin.
--
-- THE TEXTURE PIPELINE IS BUILD_GALAXY's, INCLUDING ITS OWNERSHIP RULE. Per
-- texel, recover the 3D point on the mesh and evaluate the pattern there -- 3D
-- has no seam and no pole, so continuity is free. Texel ownership is decided by
-- containment class, never by rasterisation order, and never by ranking
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
	-- 1024, not 256. The 256 derivation was right about AREA -- one texel per
	-- pixel at 40 studs -- and wrong about EDGES. A boundary stair-steps wherever
	-- it is visible at all, and matching texel size to pixel size puts the steps
	-- exactly at the size the eye picks up. Edges need headroom over the sampling
	-- rate, not parity with it.
	TEX = 1024,
	ROOT_NAME = "SkinLineup",
	-- nil builds all four tiers; a tier name builds only that one
	ONLY_TIER = "Rare",
	SOURCE_MODEL = "slime_uv",       -- the UNWRAPPED body; lineup meshes have no UVs
	SOURCE_PART = "default",
	-- Plastic, NOT SmoothPlastic. SmoothPlastic's specular lobe puts a hard white
	-- highlight on the dome that competes with the pattern for the eye, and the
	-- lineup slimes are Plastic anyway.
	BODY_MATERIAL = Enum.Material.Plastic,

	-- ---- layout: hues along X, tiers along Z ----
	ORIGIN = Vector3.new(-55, 0, -260),
	HUE_SPACING = 22,
	TIER_SPACING = 30,
	BODY_YAW_DEG = 179.4,            -- turns the face toward the camera

	-- ---- the viewing condition the whole design is calibrated to ----
	VIEW_DISTANCE = 40,
	VIEW_FOV_DEG = 70,
	VIEW_FRAME_PX = 563,
	MIN_FEATURE_PX = 8,              -- below this a feature half-resolves; hard assert

	-- ---- rarity ladder: fraction of the body wearing the accent ----
	TIER_COVERAGE = { 0.10, 0.25, 0.42, 0.60 },
	COVERAGE_TOLERANCE = 0.004,      -- binary search stops inside this
	COVERAGE_ITERS = 24,
	COVERAGE_SAMPLE_STRIDE = 3,      -- every Nth covered texel during the search
	CALIBRATE_TICK_EVERY = 512,      -- yield check inside the search loop
	PAINT_TICK_ROWS = 6,             -- yield check every N rows of the paint loop

	-- ---- accent derivation ----
	-- ONE CREAM, FOR EVERY HUE.
	--
	-- The accent must not look like SHADING: a merely darker version of the base
	-- fails at 40 studs even at a 0.36 luminance gap, because a curved lit body
	-- already spans that much from highlight to shaded flank, so the pattern reads
	-- as form. Cream satisfies that -- lighting cannot produce cream on green.
	--
	-- But it must not look like DIRT either, which is where near-black and
	-- near-white landed. Both are absences of colour; on a saturated toy body they
	-- read as a stain or a blown-out highlight rather than as a second material.
	-- A warm cream is a colour, and it sits in the same palette as the bodies.
	--
	-- Pulled 10% toward the base hue so each slime's marking belongs to that
	-- slime rather than looking pasted on from outside the palette.
	ACCENT_CREAM = Color3.fromRGB(255, 246, 226),
	ACCENT_HUE_MIX = 0.10,

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
	-- Sized to the face PARTS and no larger. The eyes span about 25 degrees of arc
	-- from the body centre and the blush sits just under them, so 38 + 12 clears
	-- them. It was 52 + 16 first, and that masked so much of the camera-facing
	-- hemisphere that a Common slime showed almost no pattern from the front --
	-- the coverage was all pushed around the sides where nobody looks.
	FACE_DIR = Vector3.new(-3.537, 0.257, -4.448),
	FACE_CLEAR_DEG = 38,
	FACE_EDGE_DEG = 12,              -- soft falloff so the mask is not a visible disc

	-- ---- shape placement ----
	-- The high belt rides as a crown band because the face sits on the equator
	-- (qy ~ 0.05) and a belt there lands squarely under the face mask -- at 10%
	-- coverage that left the Common slime with two slivers at its edges and
	-- nothing in front. The low belt sits under the face for the same reason.
	BELT_HIGH_Y = 0.34,
	BELT_LOW_Y = -0.30,
	SPLIT_SHALLOW_DEG = 20,          -- gentle diagonal
	SPLIT_STEEP_DEG = 55,            -- steep diagonal, nearly a side division

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

local TIERS = { "Common", "Uncommon", "Rare", "Epic" }

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
local N_SHALLOW = planeNormal(P.SPLIT_SHALLOW_DEG)
local N_STEEP = planeNormal(P.SPLIT_STEEP_DEG)

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

-- SPOTS AND PATCHES ARE GONE. Both resolved perfectly well by the pixel rule and
-- both still looked cheap: on a rounded body a scatter of blobs reads as
-- staining rather than as a marking, however cleanly its edges land. Resolving
-- is necessary and not sufficient. What survives is the family that follows the
-- body's own form -- bands and divisions -- and within-tier variety now comes
-- from WHERE the band sits and HOW the plane is angled, not from adding kinds.
local SHAPES = {
	{
		name = "belt-high",
		accent = function(qx: number, qy: number, qz: number, k: number): number
			return inside(math.abs(qy - P.BELT_HIGH_Y), k)
		end,
		minStuds = function(k: number, radius: number): number
			return 2 * k * radius              -- the band's height
		end,
	},
	{
		name = "belt-low",
		accent = function(qx: number, qy: number, qz: number, k: number): number
			return inside(math.abs(qy - P.BELT_LOW_Y), k)
		end,
		minStuds = function(k: number, radius: number): number
			return 2 * k * radius
		end,
	},
	{
		name = "cap",
		accent = function(qx: number, qy: number, qz: number, k: number): number
			return above(qy, 1 - k)
		end,
		minStuds = function(k: number, radius: number): number
			return k * radius                  -- how far down the cap reaches
		end,
	},
	{
		name = "foot",
		accent = function(qx: number, qy: number, qz: number, k: number): number
			return inside(qy, k - 1)
		end,
		minStuds = function(k: number, radius: number): number
			return k * radius
		end,
	},
	{
		name = "split-shallow",
		accent = function(qx: number, qy: number, qz: number, k: number): number
			return above(qx * N_SHALLOW.X + qy * N_SHALLOW.Y + qz * N_SHALLOW.Z, 1 - 2 * k)
		end,
		minStuds = function(k: number, radius: number): number
			return math.min(k, 1 - k) * 2 * radius
		end,
	},
	{
		name = "split-steep",
		accent = function(qx: number, qy: number, qz: number, k: number): number
			return above(qx * N_STEEP.X + qy * N_STEEP.Y + qz * N_STEEP.Z, 1 - 2 * k)
		end,
		minStuds = function(k: number, radius: number): number
			return math.min(k, 1 - k) * 2 * radius
		end,
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
	local acc = P.ACCENT_CREAM:Lerp(base, P.ACCENT_HUE_MIX)
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

	-- ---- face keep-clear mask ----
	local FD = P.FACE_DIR.Unit
	local cosClear = math.cos(math.rad(P.FACE_CLEAR_DEG))
	local cosEdge = math.cos(math.rad(P.FACE_CLEAR_DEG + P.FACE_EDGE_DEG))
	local function faceOpen(qx: number, qy: number, qz: number): number
		local l = math.sqrt(qx * qx + qy * qy + qz * qz)
		if l < 1e-9 then return 1 end
		local d = (qx * FD.X + qy * FD.Y + qz * FD.Z) / l
		-- 0 inside the cone (pure base), 1 well outside it
		return smoothstep(cosClear, cosEdge, d)
	end

	-- ---- calibrate one shape to a target coverage ----
	-- Ticks INSIDE the sample loop, not just per iteration. 24 iterations over
	-- 7680 samples is 184k shape evaluations, and 'spots' costs 27 lattice cells
	-- each -- that is 5M hash operations per skin. Ticking only at the iteration
	-- boundary measured a 522 ms main-thread hold, which is the watchdog dialog
	-- waiting to happen.
	local function calibrate(shape, target: number): (number, number)
		local lo, hi = 0.0, 2.0
		local got = 0
		for _ = 1, P.COVERAGE_ITERS do
			local mid = (lo + hi) / 2
			-- Coverage INTEGRATES the soft accent value rather than counting a
			-- boolean. With antialiased edges a texel can be half accent, and
			-- summing the fractions is what keeps the tier percentages honest.
			local hit = 0
			for si, q in ipairs(sample) do
				if si % P.CALIBRATE_TICK_EVERY == 0 then Y.tick() end
				hit += shape.accent(q[1], q[2], q[3], mid) * faceOpen(q[1], q[2], q[3])
			end
			got = hit / #sample
			if math.abs(got - target) <= P.COVERAGE_TOLERANCE then
				return mid, got
			end
			if got < target then lo = mid else hi = mid end
		end
		return (lo + hi) / 2, got
	end

	-- ---- generate the 24 skins ----
	for _, c in ipairs(workspace:GetChildren()) do
		if c.Name == P.ROOT_NAME then c:Destroy() end
	end
	local root = Instance.new("Model")
	root.Name = P.ROOT_NAME
	root.Parent = workspace

	local localOff = Vector3.new(M.CX, M.CY, M.CZ)
	local buf = buffer.create(W * W * 4)
	local worstFeaturePx, worstFeatureWhat = math.huge, "?"
	local worstGapByTier = {}
	local rows = {}
	local texCount = 0

	for ti, tierName in ipairs(TIERS) do
		if P.ONLY_TIER and tierName ~= P.ONLY_TIER then continue end
		local target = P.TIER_COVERAGE[ti]
		local tierWorstGap, tierWorstHue = math.huge, "?"
		local tierMinPx, tierMinWhat = math.huge, "?"
		local covLo, covHi = math.huge, -math.huge

		for hi_, hue in ipairs(HUES) do
			Y.tick()
			-- shape rotates by tier, so a hue wears a different pattern at each rarity
			local shape = SHAPES[((hi_ - 1 + ti - 1) % #SHAPES) + 1]
			local k, measured = calibrate(shape, target)
			covLo = math.min(covLo, measured)
			covHi = math.max(covHi, measured)

			local featureStuds = shape.minStuds(k, bodyRadiusStuds)
			local featurePx = featureStuds * pxPerStud
			if featurePx < tierMinPx then
				tierMinPx = featurePx
				tierMinWhat = shape.name
			end
			if featurePx < worstFeaturePx then
				worstFeaturePx = featurePx
				worstFeatureWhat = string.format("%s/%s", tierName, shape.name)
			end

			local base = hue.color
			local accent, lumGap, rgbDist = accentFor(base)
			if rgbDist < tierWorstGap then
				tierWorstGap = rgbDist
				tierWorstHue = string.format("%s (rgb %.3f, lum %.3f)", hue.name, rgbDist, lumGap)
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
						local a = shape.accent(qx, qy, qz, k) * faceOpen(qx, qy, qz)
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
			local at = P.ORIGIN
				+ Vector3.new((hi_ - 1) * P.HUE_SPACING, 0, (ti - 1) * P.TIER_SPACING)
			-- ORIGIN.Y is the ground; lift by half the body so it rests on it
			local bodyCF = CFrame.new(at.X, at.Y + bodyHeightStuds / 2, at.Z)
				* CFrame.Angles(0, math.rad(P.BODY_YAW_DEG), 0)

			local slime = Instance.new("Model")
			slime.Name = string.format("%s_%s", tierName, hue.name)
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
			slime:SetAttribute("Tier", tierName)
			slime:SetAttribute("Hue", hue.name)
			slime:SetAttribute("Shape", shape.name)
			slime:SetAttribute("Coverage", measured)
			slime:SetAttribute("FeaturePx", featurePx)
		end

		worstGapByTier[ti] = { hue = tierWorstHue, gap = tierWorstGap }
		table.insert(rows, string.format(
			"[Skins] %-9s target %2.0f%% | measured %.1f-%.1f%% | smallest feature %.1f px (%s) | worst hue %s",
			tierName, target * 100, covLo * 100, covHi * 100, tierMinPx, tierMinWhat,
			tierWorstHue))
	end

	for _, r in ipairs(rows) do table.insert(lines, r) end

	assert(worstFeaturePx >= P.MIN_FEATURE_PX, string.format(
		"[Skins] smallest feature is %.1f px (%s) at %d studs, under the %d px floor -- "
			.. "it would half-resolve, which is the exact failure this design exists to avoid",
		worstFeaturePx, worstFeatureWhat, P.VIEW_DISTANCE, P.MIN_FEATURE_PX))
	log("[Skins] SMALLEST FEATURE across all 24: %.1f px (%s), floor is %d px",
		worstFeaturePx, worstFeatureWhat, P.MIN_FEATURE_PX)

	local perTexKB = W * W * 4 / 1024
	log("[Skins] MEMORY: %d x %d RGBA = %.0f KB per skin | %d skins = %.1f MB | all 65 = %.1f MB",
		W, W, perTexKB, texCount, texCount * perTexKB / 1024, 65 * perTexKB / 1024)
	log("[Skins] one-texture-per-tier + hue tint would be %.1f MB now / %.1f MB at 65, "
		.. "but forces all six slimes in a tier to share one shape",
		4 * perTexKB / 1024, 11 * perTexKB / 1024)

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
