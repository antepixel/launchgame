-- Offline verification of dev/skins/BUILD_GALAXY.luau's buildUVMap(): the
-- UV -> 3D inverse map, the seam-straddle fix, the stray-cube filter, the
-- overlap counter, and the two continuity metrics the build script asserts on.
-- The design rationale lives in that file's own header block; this file only
-- checks it.
--
--   lune run dev/analysis/verify_galaxy_uvmap.luau
--
-- Run from the REPO ROOT. Fully deterministic -- the mesh is constructed, not
-- sampled. Prints to stdout only; writes nothing to dev/out. Exits non-zero if
-- any check fails.
--
-- THE MESH IS SYNTHETIC AND THAT IS THE POINT. Against the real asset the only
-- available checks are self-consistency ones -- the build script's own seam and
-- pole asserts -- which cannot distinguish "the map is right" from "the map is
-- wrong in a self-consistent way". Here the mesh is a UV sphere built to order,
-- so the correct 3D point for every texel is known ANALYTICALLY (see truth()),
-- and the map is checked against ground truth texel by texel. The sphere is
-- given the same awkward properties as the real import on purpose: the island
-- occupies only a band of v, the body sits entirely below Y = 0, a stray cube
-- floats above it, and two quad rows straddle the u wrap without duplicated
-- seam vertices.
--
-- THE REAL FUNCTION IS EXERCISED, via a stub of just the six EditableMesh
-- methods buildUVMap calls. Nothing below reimplements the rasteriser.
--
-- TEST 9 IS A NEGATIVE CONTROL AND IS LOAD-BEARING. It reloads the core with the
-- three straddle-lift lines stripped out and requires the map to get WORSE. An
-- earlier version of test 7 measured neighbour-to-neighbour jump and passed
-- identically with and without the fix -- because an unlifted straddle triangle
-- joins lon 63 to lon 0, which are ADJACENT in 3D, so it interpolates smoothly
-- and stays near the surface. It is not off-surface; it lands on the WRONG
-- TEXELS, overwriting a ~1000-texel band with positions from a 5.6-degree
-- sliver. Only a ground-truth comparison sees that. Without test 9 the suite
-- would have looked green while proving nothing.
local luau = require("@lune/luau")
local C = require("./common")

-- readSource, not fs.readFile: the repo checks out CRLF, and the section markers
-- and the test-9 patch below are line-anchored.
local src = C.readSource("dev/skins/BUILD_GALAXY.luau")
local cut = src:find("-- BUILD%.\n")
assert(cut, "BUILD section divider not found")
local core = src:sub(1, cut - 1)
assert(core:find("local function buildUVMap"), "buildUVMap not in sliced region")
assert(core:find("local function dilate"), "dilate not in sliced region")

-- ================= synthetic mesh =================
-- A UV sphere with the standard spherical unwrap: a seam at u = 0/1 and a
-- convergence point at v = VMIN. Deliberately built with the same awkward
-- properties as the real asset -- the island occupies only a band of v, the
-- body sits entirely below Y = 0, a stray cube floats above it, and a couple of
-- faces straddle the wrap without duplicated seam vertices.
local NLAT, NLON = 40, 64
local VMIN, VMAX = 0.3345, 0.6899
local R, CY = 50, -100
local SEAM_QUADS = { 7, 21 }   -- quad rows whose wrap face is left un-duplicated

local pos, uv, faces = {}, {}, {}
local function vid(lat, lon) return lat * (NLON + 1) + lon + 1 end

for lat = 0, NLAT do
	local phi = (lat / NLAT) * math.pi
	local sp, cp = math.sin(phi), math.cos(phi)
	for lon = 0, NLON do
		local theta = (lon / NLON) * 2 * math.pi
		pos[vid(lat, lon)] = { X = R * sp * math.cos(theta), Y = CY + R * cp, Z = R * sp * math.sin(theta) }
		uv[vid(lat, lon)] = { X = lon / NLON, Y = VMIN + (lat / NLAT) * (VMAX - VMIN) }
	end
end

local injectedSeam = 0
for lat = 0, NLAT - 1 do
	for lon = 0, NLON - 1 do
		local a, b = vid(lat, lon), vid(lat, lon + 1)
		local c, d = vid(lat + 1, lon), vid(lat + 1, lon + 1)
		local ua, ub, uc, ud = a, b, c, d
		-- on the chosen rows, the last quad references the lon = 0 UVs instead of
		-- the duplicated lon = NLON ones, so the triangle spans the whole sheet
		if lon == NLON - 1 and table.find(SEAM_QUADS, lat) then
			ub, ud = vid(lat, 0), vid(lat + 1, 0)
			injectedSeam += 2
		end
		table.insert(faces, { v = { a, b, c }, t = { ua, ub, uc } })
		table.insert(faces, { v = { b, d, c }, t = { ub, ud, uc } })
	end
end
local bodyFaces = #faces

-- stray unit cube ~500 above the body, as on the real import
local cubeBase = #pos
for i = 0, 7 do
	local n = cubeBase + i + 1
	pos[n] = { X = (i % 2), Y = 400 + ((i // 2) % 2), Z = (i // 4) }
	uv[n] = { X = (i % 2) * 0.9, Y = (i // 4) * 0.9 }
end
local cubeFaces = 0
for i = 1, 12 do
	local a = cubeBase + 1 + (i % 8)
	local b = cubeBase + 1 + ((i + 1) % 8)
	local c = cubeBase + 1 + ((i + 3) % 8)
	table.insert(faces, { v = { a, b, c }, t = { a, b, c } })
	cubeFaces += 1
end

-- ================= stubs =================
local PRELUDE = [[
Color3 = { fromRGB = function(r,g,b) return {R=r/255,G=g/255,B=b/255} end, new = function(r,g,b) return {R=r,G=g,B=b} end }
Vector3 = { new = function(x,y,z) return {X=x,Y=y,Z=z} end }
Vector2 = { new = function(x,y) return {X=x,Y=y} end, zero = {X=0,Y=0} }
CFrame = { new = function(...) return {...} end, Angles = function(...) return {...} end }
Enum = { Material = { Plastic = "Plastic" } }
task = { wait = function() end }
Content = { fromUri = function(u) return u end, fromObject = function(o) return o end }
game = { GetService = function() return { CreateEditableMeshAsync = function(_, _) return __MESH end } end }
]]
local SUFFIX = "return { buildUVMap = buildUVMap, dilate = dilate, newYielder = newYielder }\n"

local MESH = {
	GetVertices = function() local t = {} for i = 1, #pos do t[i] = i end return t end,
	GetFaces = function() local t = {} for i = 1, #faces do t[i] = i end return t end,
	GetPosition = function(_, id) return pos[id] end,
	GetUV = function(_, id) return uv[id] end,
	GetFaceVertices = function(_, f) return faces[f].v end,
	GetFaceUVs = function(_, f) return faces[f].t end,
}
-- the mesh stub arrives as the chunk's vararg, which the prelude closes over
local chunk = luau.load("local __MESH = ...\n" .. PRELUDE .. core .. SUFFIX, { debugName = "uvmapcore" })
local U = chunk(MESH)

local fails = 0
local function check(name, ok, detail)
	print(string.format("  [%s] %s%s", ok and "PASS" or "FAIL", name, detail and ("  -- " .. detail) or ""))
	if not ok then fails += 1 end
end

local W, H = 1024, 1024
local Y = U.newYielder(12)
local t0 = os.clock()
local M = U.buildUVMap("stub://mesh", W, H, Y)
local buildSecs = os.clock() - t0

print("\n=== 1. the rasteriser covered the island ===")
local pct = 100 * M.covered / (W * H)
check("coverage is a plausible island fraction", pct > 25 and pct < 45,
	string.format("%d texels = %.1f%% of sheet, built in %.2f s", M.covered, pct, buildSecs))

print("\n=== 2. seam-straddling triangles were detected ===")
check("found exactly the injected straddle faces", M.seamTris == injectedSeam,
	string.format("detected %d, injected %d", M.seamTris, injectedSeam))

print("\n=== 3. the stray cube was excluded ===")
check("skipped exactly the cube faces", M.skipped == cubeFaces,
	string.format("skipped %d, cube has %d (body has %d)", M.skipped, cubeFaces, bodyFaces))

print("\n=== 3b. the overlap counter reads clean on a non-overlapping unwrap ===")
check("no disagreeing double-claims", M.conflicts == 0,
	string.format("%d conflicts, worst %.4f body-radii", M.conflicts, M.worstConflict))

-- ---- replicate the script's own continuity metrics ----
local POS, MASK = M.POS, M.MASK
local function getp(ix, iy)
	local idx = iy * W + ix
	if buffer.readu8(MASK, idx) == 0 then return nil end
	local o = idx * 12
	return buffer.readf32(POS, o), buffer.readf32(POS, o + 4), buffer.readf32(POS, o + 8)
end
local rmin, rmax = H, -1
for y = 0, H - 1 do
	for x = 0, W - 1 do
		if buffer.readu8(MASK, y * W + x) == 1 then
			if y < rmin then rmin = y end
			if y > rmax then rmax = y end
			break
		end
	end
end

local midRow = (rmin + rmax) // 2
local stepSum, stepN = 0, 0
for x = 0, W - 2 do
	local ax, ay, az = getp(x, midRow)
	local bx, by, bz = getp(x + 1, midRow)
	if ax and bx then
		stepSum += math.sqrt((ax-bx)^2 + (ay-by)^2 + (az-bz)^2)
		stepN += 1
	end
end
local step = stepSum / stepN

local seamWorst = 0
for y = rmin, rmax do
	local ax, ay, az = getp(0, y)
	local bx, by, bz = getp(W - 1, y)
	if ax and bx then
		seamWorst = math.max(seamWorst, math.sqrt((ax-bx)^2 + (ay-by)^2 + (az-bz)^2))
	end
end

local sx, sy, sz, cnt, pts = 0, 0, 0, 0, {}
for x = 0, W - 1 do
	local a, b, c = getp(x, rmin)
	if a then sx += a; sy += b; sz += c; cnt += 1; table.insert(pts, {a,b,c}) end
end
local poleSpread = 0
if cnt > 0 then
	sx, sy, sz = sx/cnt, sy/cnt, sz/cnt
	for _, p in ipairs(pts) do
		poleSpread = math.max(poleSpread, math.sqrt((p[1]-sx)^2 + (p[2]-sy)^2 + (p[3]-sz)^2))
	end
end

print("\n=== 4. island rows land where the UV band says they should ===")
check("rmin matches VMIN", math.abs(rmin - VMIN * H) < 3, string.format("rmin %d, expected ~%d", rmin, math.floor(VMIN * H)))
check("rmax matches VMAX", math.abs(rmax - VMAX * H) < 3, string.format("rmax %d, expected ~%d", rmax, math.floor(VMAX * H)))

print("\n=== 5. SEAM: the wrap columns are genuine 3D neighbours ===")
check("seam gap under the script's 3-texel assert", seamWorst / step < 3,
	string.format("gap %.4f body-radii = %.2f texels (texel step %.5f)", seamWorst, seamWorst / step, step))

print("\n=== 6. POLE: the top row collapses to one point ===")
check("pole spread under the script's 0.15 assert", poleSpread < 0.15,
	string.format("spread %.4f body-radii over %d texels", poleSpread, cnt))

print("\n=== 7. the map matches analytic ground truth, texel by texel ===")
-- The strongest available check, and the only one that catches an unlifted
-- straddle. Staying ON the surface does not distinguish the two cases: the
-- straddling triangle joins lon 63 to lon 0, which are ADJACENT in 3D, so
-- interpolating it across the sheet still yields near-surface points -- they
-- simply land on the WRONG TEXELS, overwriting a 1000-texel band with positions
-- from a 5.6-degree sliver. So compare each texel against the point the
-- synthetic unwrap says it should hold.
local function truth(x, y)
	local u = (x + 0.5) / W
	local v = (y + 0.5) / H
	local phi = ((v - VMIN) / (VMAX - VMIN)) * math.pi
	local theta = u * 2 * math.pi
	local sp = math.sin(phi)
	return sp * math.cos(theta), math.cos(phi), sp * math.sin(theta)
end
local function vsTruth(getter)
	local worst, worstAt = 0, nil
	for y = rmin + 2, rmax - 2 do          -- skip the partially covered edge rows
		for x = 0, W - 1 do
			local a, b, c = getter(x, y)
			if a then
				local tx, ty, tz = truth(x, y)
				local d = math.sqrt((a-tx)^2 + (b-ty)^2 + (c-tz)^2)
				if d > worst then worst, worstAt = d, { x, y } end
			end
		end
	end
	return worst, worstAt
end
do
	local worst, at = vsTruth(getp)
	-- tolerance is the chord sag of one quad plus half-texel quantisation
	check("every texel is within a texel-step of ground truth", worst < 0.02,
		string.format("worst error %.5f body-radii (= %.2f texels) at (%d, %d)",
			worst, worst / step, at[1], at[2]))
end

print("\n=== 8. dilate grows the island without corrupting it ===")
do
	local before = M.covered
	local grown = U.dilate(POS, MASK, W, H, 4, rmin - 8, rmax + 8, Y)
	local after = 0
	for i = 0, W * H - 1 do if buffer.readu8(MASK, i) ~= 0 then after += 1 end end
	check("grew the covered set", grown > 0 and after == before + grown,
		string.format("%d -> %d texels (+%d)", before, after, grown))
	check("growth is a thin rim, not a flood", grown < before * 0.15,
		string.format("grew %.1f%% of the island over 4 passes", 100 * grown / before))
end

print("\n=== 9. NEGATIVE CONTROL: disable the straddle lift, the smear must return ===")
do
	-- If test 7 passes with the fix removed, test 7 proves nothing. Reload the
	-- core with the three lift lines stripped and confirm it degrades.
	local broken, n = core, 0
	broken, n = broken:gsub("if u([123]) %- umin <= 0%.5 then u[123] %+= 1 end", "")
	assert(n == 3, "expected to strip 3 lift lines, stripped " .. n)
	local B = luau.load("local __MESH = ...\n" .. PRELUDE .. broken .. SUFFIX, { debugName = "broken" })(MESH)
	local M2 = B.buildUVMap("stub://mesh", W, H, B.newYielder(12))
	local P2, K2 = M2.POS, M2.MASK
	local function g2(ix, iy)
		local idx = iy * W + ix
		if buffer.readu8(K2, idx) == 0 then return nil end
		local o = idx * 12
		return buffer.readf32(P2, o), buffer.readf32(P2, o + 4), buffer.readf32(P2, o + 8)
	end
	local worst, at = vsTruth(g2)
	check("without the lift, a band of texels holds the wrong 3D point", worst > 0.5,
		string.format("worst error %.5f body-radii (= %.0f texels) at (%d, %d)",
			worst, worst / step, at[1], at[2]))
end

print(string.format("\nyielder: %d yields, worst hold %.1f ms", Y.yields(), Y.worstMs()))
print(string.format("\n%s  (%d failure%s)", fails == 0 and "ALL PASS" or "FAILURES", fails, fails == 1 and "" or "s"))
if fails > 0 then require("@lune/process").exit(1) end
