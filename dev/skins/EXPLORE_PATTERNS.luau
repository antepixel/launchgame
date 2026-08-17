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
-- ===================================================================
local YHALF = 0.6773     -- body half-height in body-radii; refined at build time

local VARIANTS = {
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
		name = "stripes4",
		note = "four spiral stripes, white narrower than hue",
		g = function(qx, qy, qz, f, s, y)
			return -stripeField(qx, qy, qz, 2, 0, math.rad(70), YHALF)
		end,
	},
	{
		name = "stripes2",
		note = "two wide spiral stripes, white narrower than hue",
		g = function(qx, qy, qz, f, s, y)
			return -stripeField(qx, qy, qz, 1, 0, math.rad(70), YHALF)
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
		return smoothstep(-P.EDGE_SOFT, P.EDGE_SOFT, k - v.g(qx, qy, qz, f, s, qy))
	end

	-- one monotone bisection calibrates every shape, because g is written so a
	-- larger k always admits more white
	local function calibrate(v): (number, number)
		local lo, hi, got = P.SEARCH_LO, P.SEARCH_HI, 0
		for _ = 1, P.SEARCH_ITERS do
			local mid = (lo + hi) / 2
			local hit = 0
			for si, q in ipairs(sample) do
				if si % P.TICK_EVERY == 0 then Y.tick() end
				hit += whiteAt(v, q[1], q[2], q[3], q[4], q[5], mid)
			end
			got = hit / #sample
			if math.abs(got - P.WHITE_TARGET) <= P.WHITE_TOLERANCE then return mid, got end
			if got < P.WHITE_TARGET then lo = mid else hi = mid end
		end
		return (lo + hi) / 2, got
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
	local ar, ag, ab = acc.R, acc.G, acc.B

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

	local worstPx, worstWhat = math.huge, "?"
	for vi, v in ipairs(VARIANTS) do
		Y.tick()
		local k, measured = calibrate(v)

		-- paint, and measure the shape while painting: white texel count and the
		-- count of white texels with a non-white neighbour give area and perimeter
		local whiteN, edgeN = 0, 0
		local rowWhite = table.create(W)
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
					buffer.writeu8(buf, off, math.floor(math.clamp(br + (ar-br)*a, 0, 1)*255 + 0.5))
					buffer.writeu8(buf, off+1, math.floor(math.clamp(bg + (ag-bg)*a, 0, 1)*255 + 0.5))
					buffer.writeu8(buf, off+2, math.floor(math.clamp(bb + (ab-bb)*a, 0, 1)*255 + 0.5))
					buffer.writeu8(buf, off+3, 255)
				else
					rowWhite[x + 1] = false
					buffer.writeu8(buf, off, 0); buffer.writeu8(buf, off+1, 0)
					buffer.writeu8(buf, off+2, 0); buffer.writeu8(buf, off+3, 255)
				end
			end
		end

		-- characteristic width 2A/P, which is exactly the stripe width for a stripe
		local widthStuds = (edgeN > 0)
			and (2 * whiteN / edgeN) * texelStep * bodyRadiusStuds or 0
		local widthPx = widthStuds * pxPerStud
		if widthPx < worstPx then worstPx, worstWhat = widthPx, v.name end

		local img = AssetService:CreateEditableImage({ Size = Vector2.new(W, W) })
		img:WritePixelsBuffer(Vector2.zero, Vector2.new(W, W), buf)
		Y.mark()

		local at = P.ORIGIN + Vector3.new((vi - 1) * P.SPACING, 0, 0)
		local bodyCF = CFrame.new(at.X, at.Y + bodyHeightStuds/2, at.Z)
			* CFrame.Angles(0, math.rad(P.BODY_YAW_DEG), 0)
		local slime = Instance.new("Model")
		slime.Name = string.format("V%02d_%s", vi, v.name)
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
		slime:SetAttribute("Hue", P.HUE_NAME)
		slime:SetAttribute("WhiteFraction", measured)

		log("[Lab] %2d %-13s white %.1f%% | feature %.1f px | %s",
			vi, v.name, measured * 100, widthPx, v.note)
	end

	log("[Lab] narrowest feature: %.1f px (%s), floor is %d px",
		worstPx, worstWhat, P.MIN_FEATURE_PX)
	log("[Lab] watchdog worst hold %.1f ms | built %d variants in %.2f s",
		Y.worstMs(), #VARIANTS, os.clock() - t0)
	log("[Lab] undo with workspace.%s:Destroy()", P.ROOT_NAME)

	local outStr = table.concat(lines, "\n")
	print(outStr)
	return outStr
end

return run()
