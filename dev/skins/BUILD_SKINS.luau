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
-- orthogonal on purpose. Six shapes -- belt, cap, foot, split, spots, patches --
-- appear once per tier, so within-tier variety is a genuinely different pattern
-- rather than only a different hue, while the rarity read stays clean because
-- every shape in a tier carries the same coverage. The shape assignment rotates
-- by tier, so a given hue wears a different pattern at each rarity.
--
-- NO WEDGES, AND THE REASON GENERALISES. Longitude wedges were the obvious
-- seventh shape and they are a trap: they converge to a point at the pole, so
-- the feature width goes to zero there by construction. Any shape whose size is
-- a function of latitude will half-resolve somewhere. Every shape kept here has
-- a width that is bounded away from zero over the whole surface.
--
-- ACCENT DIRECTION IS ADAPTIVE, AND THAT IS WHAT MAKES IT WORK ON ALL SIX HUES.
-- The palette is bright: base luminance runs 0.37 (red) to 0.82 (yellow). A
-- fixed light accent dies on yellow; a fixed dark accent is weakest on red. So
-- the accent goes DARK on bright bases and LIGHT on dark ones, whichever
-- direction has headroom. Measured worst-case base/accent luminance gap goes
-- from 0.239 with a fixed dark accent to 0.362 adaptive -- a 52% improvement on
-- the worst hue, which is the only hue that matters.
--
-- 256 x 256, WHICH IS THE POINT RATHER THAN A COMPROMISE. At 40 studs the front
-- of the body covers about 10,300 px. The UV island is 32.8% of the sheet and
-- roughly half of it faces the camera, so 0.164 * R^2 = 10,300 gives R = 250.
-- 256 is 1:1 at the only distance that counts. The galaxy skin's 1024 bought
-- four times the linear detail in a design whose rule forbids fine detail, at
-- sixteen times the memory.
--
-- MEMORY, AND WHY THE TEXTURES ARE NOT SHARED. 256 x 256 RGBA is 256 KB. 24
-- skins is 6.0 MB; all 65 eventually is 16.3 MB. Sharing one texture per tier
-- and tinting per hue would cut that to 1.0 MB now and 2.8 MB at 65 -- but it
-- forces all six slimes in a tier to wear the SAME shape, which throws away the
-- within-tier variety that is the whole point of having six of them. The
-- resolution drop already solved the memory problem the sharing was meant to
-- solve -- 16 MB at full roster is not worth trading the variety for.
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
	TEX = 256,
	ROOT_NAME = "SkinLineup",
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
	-- THE ACCENT MUST NOT LOOK LIKE SHADING. A merely darker version of the base
	-- hue fails at 40 studs even at a luminance gap of 0.36, because a curved lit
	-- body ALREADY spans that much from its highlight to its shaded flank -- the
	-- pattern reads as form, not as marking. The fix is to make the accent
	-- extreme: near-black or near-white, which lighting never produces on a
	-- saturated mid-tone. Measured worst-hue gap goes 0.362 -> 0.475.
	ACCENT_SPLIT_LUM = 0.58,         -- above this the base is "bright" -> dark accent
	ACCENT_DARK_V = 0.18,
	ACCENT_DARK_S = 0.85,
	ACCENT_LIGHT_V = 1.00,
	ACCENT_LIGHT_S = 0.10,

	-- ---- face keep-clear ----
	-- Sized to the face PARTS and no larger. The eyes span about 25 degrees of arc
	-- from the body centre and the blush sits just under them, so 38 + 12 clears
	-- them. It was 52 + 16 first, and that masked so much of the camera-facing
	-- hemisphere that a Common slime showed almost no pattern from the front --
	-- the coverage was all pushed around the sides where nobody looks.
	FACE_DIR = Vector3.new(-3.537, 0.257, -4.448),
	FACE_CLEAR_DEG = 38,
	FACE_EDGE_DEG = 12,              -- soft falloff so the mask is not a visible disc

	-- ---- shape-specific constants ----
	-- The belt rides HIGH, as a crown band, because the face sits on the equator
	-- (qy ~ 0.05) and a belt there lands squarely under the face mask -- at 10%
	-- coverage that left the Common slime with two dark slivers at its edges and
	-- nothing in front. qy 0.34 clears the eyes and reads from the front.
	BELT_CENTRE_Y = 0.34,
	SPLIT_TILT_DEG = 24,
	SPOT_CELL = 0.62,                -- 3D lattice pitch in body-radii; big cells, big spots
	SPOT_PROB = 0.55,
	PATCH_SCALE = 1.15,              -- low frequency: blobs, not speckle
	PATCH_OCTAVES = 2,

	-- ---- watchdog ----
	YIELD_MS = 12,

	-- ---- seeds ----
	SEED_SPOT = 4021,
	SEED_PATCH = 8117,
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

-- ===================================================================
-- NOISE. Integer hash, no trig, every multiply under 2^53 so the result is
-- exact and the skins are reproducible bit-for-bit.
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
local SPLIT_N = (function()
	local t = math.rad(P.SPLIT_TILT_DEG)
	return Vector3.new(math.sin(t), math.cos(t), 0).Unit
end)()

local SHAPES = {
	{
		name = "belt",
		-- a band around the middle; the classic and the most legible
		accent = function(qx: number, qy: number, qz: number, k: number): boolean
			return math.abs(qy - P.BELT_CENTRE_Y) < k
		end,
		minStuds = function(k: number, radius: number): number
			return 2 * k * radius              -- the band's height
		end,
	},
	{
		name = "cap",
		accent = function(qx: number, qy: number, qz: number, k: number): boolean
			return qy > 1 - k
		end,
		minStuds = function(k: number, radius: number): number
			return k * radius                  -- how far down the cap reaches
		end,
	},
	{
		name = "foot",
		accent = function(qx: number, qy: number, qz: number, k: number): boolean
			return qy < k - 1
		end,
		minStuds = function(k: number, radius: number): number
			return k * radius
		end,
	},
	{
		name = "split",
		-- one tilted plane, two halves; nothing here can be small
		accent = function(qx: number, qy: number, qz: number, k: number): boolean
			return qx * SPLIT_N.X + qy * SPLIT_N.Y + qz * SPLIT_N.Z > 1 - 2 * k
		end,
		minStuds = function(k: number, radius: number): number
			return math.min(k, 1 - k) * 2 * radius
		end,
	},
	{
		name = "spots",
		-- a few big round spots on a coarse 3D lattice. Round ON THE BODY,
		-- because the spot is a sphere in 3D and the surface cuts it in a circle
		-- whatever the UV mapping does.
		accent = function(qx: number, qy: number, qz: number, k: number): boolean
			local cell = P.SPOT_CELL
			local cx0, cy0, cz0 = math.floor(qx / cell), math.floor(qy / cell), math.floor(qz / cell)
			for dz = -1, 1 do
				for dy = -1, 1 do
					for dx = -1, 1 do
						local cx, cy, cz = cx0 + dx, cy0 + dy, cz0 + dz
						local h = ihash(cx, cy, cz, P.SEED_SPOT)
						if (h % 4096) / 4096 < P.SPOT_PROB then
							local jx = bit32.band(h, 1023) / 1024
							local jy = bit32.band(bit32.rshift(h, 10), 1023) / 1024
							local jz = bit32.band(bit32.rshift(h, 20), 1023) / 1024
							local px = (cx + jx) * cell
							local py = (cy + jy) * cell
							local pz = (cz + jz) * cell
							local ddx, ddy, ddz = qx - px, qy - py, qz - pz
							if ddx * ddx + ddy * ddy + ddz * ddz < k * k then
								return true
							end
						end
					end
				end
			end
			return false
		end,
		minStuds = function(k: number, radius: number): number
			return 2 * k * radius              -- spot diameter
		end,
	},
	{
		name = "patches",
		-- organic blobs from low-frequency 3D noise. PATCH_SCALE is deliberately
		-- near 1 -- one or two features across the whole body, not a field.
		accent = function(qx: number, qy: number, qz: number, k: number): boolean
			local s = P.PATCH_SCALE
			return fbm3(qx * s, qy * s, qz * s, P.PATCH_OCTAVES, P.SEED_PATCH) > 1 - k
		end,
		minStuds = function(k: number, radius: number): number
			-- characteristic blob size is set by the noise wavelength, not by k;
			-- one period of the base octave across the body
			return (0.5 / P.PATCH_SCALE) * radius
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
local function accentFor(base: Color3): (Color3, number)
	local h, s, v = Color3.toHSV(base)
	local lum = luminance(base)
	local acc
	if lum > P.ACCENT_SPLIT_LUM then
		acc = Color3.fromHSV(h, math.min(1, s * P.ACCENT_DARK_S), v * P.ACCENT_DARK_V)
	else
		acc = Color3.fromHSV(h, math.clamp(s * P.ACCENT_LIGHT_S, 0, 1),
			math.min(1, v * P.ACCENT_LIGHT_V + 0.10))
	end
	return acc, math.abs(luminance(acc) - lum)
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
			local hit = 0
			for si, q in ipairs(sample) do
				if si % P.CALIBRATE_TICK_EVERY == 0 then Y.tick() end
				if shape.accent(q[1], q[2], q[3], mid) and faceOpen(q[1], q[2], q[3]) > 0.5 then
					hit += 1
				end
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
			local accent, gap = accentFor(base)
			if gap < tierWorstGap then
				tierWorstGap = gap
				tierWorstHue = hue.name
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
						local a = 0
						if shape.accent(qx, qy, qz, k) then
							a = faceOpen(qx, qy, qz)
						end
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
			"[Skins] %-9s target %2.0f%% | measured %.1f-%.1f%% | smallest feature %.1f px (%s) | worst hue %s (lum gap %.3f)",
			tierName, target * 100, covLo * 100, covHi * 100, tierMinPx, tierMinWhat,
			tierWorstHue, tierWorstGap))
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
