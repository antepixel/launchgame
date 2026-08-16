--!strict
-- VERIFY_UNWRAP.luau -- CHECKS A RE-UNWRAPPED BODY MESH AGAINST dev/UNWRAP_SPEC.md
--
-- Paste the whole file into the Studio command bar with the mesh you want to
-- check in workspace.slime_uv. It prints one line per requirement, PASS or FAIL,
-- and a short reason. No other file needs to be present.
--
-- NOT SHIPPING CODE and deliberately NOT under src/ (Rojo syncs that). Same
-- standing as the BUILD_ scripts beside it.
--
-- IF THE STUDIO BRIDGE WILL NOT ANSWER, read dev/README.md BEFORE touching the
-- plugin. "Studio plugin connection timeout" usually does NOT mean the plugin is
-- dead -- with several sessions open there are several MCP servers, and yours may
-- simply not be the one Studio attached to.
--
-- ============================ WHAT THIS IS FOR =============================
--
-- The current unwrap is NOT INJECTIVE on the underside: two different patches of
-- the body land on the same texels, so one of them renders with colour painted
-- for somewhere else, up to 0.81 body-radii away. That is the smudge under the
-- slime, and no generator can fix it -- the information is not there, because
-- two surface points genuinely share one texel.
--
-- IT IS MEASURED HERE RATHER THAN EYEBALLED because the failure is easy to
-- mistake for something else. It was first read as a texel-DENSITY problem and
-- it is not: the underside band carries 11478 texels against ~5720 for every
-- other band, roughly double. That doubling is itself the fingerprint of two
-- patches landing in one place, and the giveaway is the distribution -- 3956 of
-- 4139 contested texels in the bottom band and literally zero across the whole
-- middle of the body. A pattern bug would be spread out.
--
-- THE BASELINE TO BEAT -- what THIS script reports on the mesh as it is today:
--     stray verts 24 / faces 12      (must become 0)
--     u range 0.0000 .. 1.2517       (must become 0 .. 1)
--     v range 0.3340 .. 0.6907       (must become 0 .. 1)
--     straddling triangles 2         (must become 0)
--     contested 3290 texels, 3.84%   (must become 0)
--     island coverage 32.7%          (must become >= 85%)
--     tears 26                       (must become 0)
--     density p95/p05 3.40           (must become < 3)
--
-- These run slightly under the figures the BUILD scripts report (4139 contested,
-- 43 tears) for a deliberate reason: the build scripts wrap out-of-range u with
-- px % W, because they have to cope with the overshoot. This script does NOT
-- wrap -- it reports the overshoot as its own failure and measures the rest on
-- what actually lies inside the square. On a mesh that meets the spec the two
-- agree exactly, because there is nothing outside 0..1 to disagree about.
--
-- READ THE COVERAGE NUMBER LAST. Coverage fixed while contested is still
-- non-zero is the worse outcome to accept, because the extra resolution makes
-- the wrong-texel patches sharper rather than softer.
-- ===========================================================================

local AssetService = game:GetService("AssetService")

local P = {
	SOURCE_MODEL = "slime_uv",
	SOURCE_PART = "default",
	TEX = 512,                   -- the resolution the skins actually ship at
	CONFLICT_EPS = 0.05,         -- body-radii; ~8 texels, far outside edge rounding
	TEAR_FACTOR = 6,             -- a neighbour this many times the median step is a tear
	MIN_COVERAGE = 0.85,
	YIELD_MS = 12,
}

local function newYielder(budgetMs: number)
	local budget, last = budgetMs / 1000, os.clock()
	return {
		tick = function()
			if os.clock() - last >= budget then
				task.wait()
				last = os.clock()
			end
		end,
		mark = function() last = os.clock() end,
	}
end

local function run()
	local lines = {}
	local function log(...) table.insert(lines, string.format(...)) end
	local pass, fail = 0, 0
	local function check(ok: boolean, name: string, detail: string)
		if ok then pass += 1 else fail += 1 end
		log("  [%s] %-28s %s", ok and "PASS" or "FAIL", name, detail)
	end

	local model = workspace:FindFirstChild(P.SOURCE_MODEL)
	assert(model, "[Verify] workspace." .. P.SOURCE_MODEL .. " not found")
	local src = model:FindFirstChild(P.SOURCE_PART) :: BasePart
	assert(src, "[Verify] " .. P.SOURCE_MODEL .. "." .. P.SOURCE_PART .. " not found")

	local Y = newYielder(P.YIELD_MS)
	local W = P.TEX
	local em = AssetService:CreateEditableMeshAsync(Content.fromUri((src :: any).MeshId))
	Y.mark()
	local verts, faces = em:GetVertices(), em:GetFaces()

	log("[Verify] %s -> %d verts, %d faces, checked at %d x %d",
		tostring((src :: any).MeshId), #verts, #faces, W, W)

	-- ---- stray geometry ----
	-- The old mesh carried a unit cube ~500 units above the body. It is detected
	-- by its DISTANCE from the main body rather than by a hardcoded Y test, so
	-- this still works if the re-export re-centres everything.
	local sx, sy, sz = 0, 0, 0
	for _, id in ipairs(verts) do
		Y.tick()
		local p = em:GetPosition(id)
		sx += p.X; sy += p.Y; sz += p.Z
	end
	local cx, cy, cz = sx / #verts, sy / #verts, sz / #verts
	local dsum = 0
	for _, id in ipairs(verts) do
		Y.tick()
		local p = em:GetPosition(id)
		dsum += math.sqrt((p.X-cx)^2 + (p.Y-cy)^2 + (p.Z-cz)^2)
	end
	local dmean = dsum / #verts
	-- EVERY CHECK BELOW EXCLUDES STRAY GEOMETRY, and that is not a nicety. Left in,
	-- the cube's 12 faces stamp their own UVs across the sheet and their vertices
	-- sit ~500 units out, so they alone read as 34.6% of the island contested at a
	-- worst disagreement of 72 body-radii -- swamping the real defect, which is
	-- 4.8% at 0.81. The numbers below therefore describe the BODY whether or not
	-- the cube has been deleted yet, so they stay comparable across the re-unwrap.
	local isStray: { [number]: boolean } = {}
	local stray = 0
	for _, id in ipairs(verts) do
		Y.tick()
		local p = em:GetPosition(id)
		if math.sqrt((p.X-cx)^2 + (p.Y-cy)^2 + (p.Z-cz)^2) > 8 * dmean then
			isStray[id] = true
			stray += 1
		end
	end
	check(stray == 0, "no stray geometry",
		string.format("%d verts sit >8x the mean radius from the centroid", stray))

	local function faceIsStray(f): boolean
		local fv = em:GetFaceVertices(f)
		return isStray[fv[1]] or isStray[fv[2]] or isStray[fv[3]] or false
	end
	local bodyFaces = 0
	for _, f in ipairs(faces) do
		Y.tick()
		if not faceIsStray(f) then bodyFaces += 1 end
	end

	-- ---- bbox of what remains ----
	local mnx, mxx = math.huge, -math.huge
	local mny, mxy = math.huge, -math.huge
	local mnz, mxz = math.huge, -math.huge
	for _, id in ipairs(verts) do
		Y.tick()
		local p = em:GetPosition(id)
		if not isStray[id] then
			mnx = math.min(mnx, p.X); mxx = math.max(mxx, p.X)
			mny = math.min(mny, p.Y); mxy = math.max(mxy, p.Y)
			mnz = math.min(mnz, p.Z); mxz = math.max(mxz, p.Z)
		end
	end
	local CX, CY, CZ = (mnx+mxx)/2, (mny+mxy)/2, (mnz+mxz)/2
	local RAD = (mxx - mnx) / 2
	log("[Verify] body bbox %.2f x %.2f x %.2f mesh units", mxx-mnx, mxy-mny, mxz-mnz)

	-- ---- UV range and straddling triangles ----
	local umin, umax, vmin, vmax = math.huge, -math.huge, math.huge, -math.huge
	local straddle = 0
	for _, f in ipairs(faces) do
		Y.tick()
		if faceIsStray(f) then continue end
		local fu = em:GetFaceUVs(f)
		local a, b, c = em:GetUV(fu[1]), em:GetUV(fu[2]), em:GetUV(fu[3])
		local lo, hi = math.min(a.X,b.X,c.X), math.max(a.X,b.X,c.X)
		umin = math.min(umin, lo); umax = math.max(umax, hi)
		vmin = math.min(vmin, math.min(a.Y,b.Y,c.Y))
		vmax = math.max(vmax, math.max(a.Y,b.Y,c.Y))
		if hi - lo > 0.5 then straddle += 1 end
	end
	log("[Verify] %d body faces (%d stray excluded from every check below)",
		bodyFaces, #faces - bodyFaces)
	check(umin >= -1e-6 and umax <= 1 + 1e-6, "u inside 0..1",
		string.format("u %.4f .. %.4f", umin, umax))
	check(vmin >= -1e-6 and vmax <= 1 + 1e-6, "v inside 0..1",
		string.format("v %.4f .. %.4f", vmin, vmax))
	check(straddle == 0, "no straddling triangles",
		string.format("%d of %d span the wrap", straddle, bodyFaces))

	-- ---- rasterise, exactly as the build scripts do ----
	local POS = buffer.create(W*W*12)
	local PRIO = buffer.create(W*W*8)
	local MASK = buffer.create(W*W)
	local covered, contested, worstContest = 0, 0, 0
	for _, f in ipairs(faces) do
		Y.tick()
		if faceIsStray(f) then continue end
		local fv = em:GetFaceVertices(f)
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

		local x1,y1 = a.X*W, a.Y*W
		local x2,y2 = b.X*W, b.Y*W
		local x3,y3 = c.X*W, c.Y*W
		local d = (y2-y3)*(x1-x3) + (x3-x2)*(y1-y3)
		if math.abs(d) >= 1e-12 then
			local inv = 1/d
			for py = math.max(0,math.floor(math.min(y1,y2,y3))), math.min(W-1,math.ceil(math.max(y1,y2,y3))) do
				local fy = py + 0.5
				for px = math.max(0,math.floor(math.min(x1,x2,x3))), math.min(W-1,math.ceil(math.max(x1,x2,x3))) do
					local fx = px + 0.5
					local l1 = ((y2-y3)*(fx-x3)+(x3-x2)*(fy-y3))*inv
					local l2 = ((y3-y1)*(fx-x3)+(x1-x3)*(fy-y3))*inv
					local l3 = 1-l1-l2
					if l1 >= -0.002 and l2 >= -0.002 and l3 >= -0.002 then
						local idx = py*W + px
						local o, po = idx*12, idx*8
						local qx = (l1*p1.X+l2*p2.X+l3*p3.X-CX)/RAD
						local qy = (l1*p1.Y+l2*p2.Y+l3*p3.Y-CY)/RAD
						local qz = (l1*p1.Z+l2*p2.Z+l3*p3.Z-CZ)/RAD
						local interior = math.min(l1,l2,l3)
						local wins
						if buffer.readu8(MASK, idx) == 0 then
							buffer.writeu8(MASK, idx, 1)
							covered += 1
							wins = true
						else
							local hi_ = buffer.readf32(PRIO, po)
							local ho = buffer.readf32(PRIO, po+4)
							local dx = qx - buffer.readf32(POS,o)
							local dy = qy - buffer.readf32(POS,o+4)
							local dz = qz - buffer.readf32(POS,o+8)
							local dist = math.sqrt(dx*dx+dy*dy+dz*dz)
							if dist > P.CONFLICT_EPS then
								contested += 1
								if dist > worstContest then worstContest = dist end
							end
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
	end

	check(contested == 0, "injective (no shared texels)",
		string.format("%d texels claimed by two disagreeing faces (%.2f%% of island), worst %.3f body-radii",
			contested, 100 * contested / math.max(1, covered), worstContest))

	local coverage = covered / (W*W)
	check(coverage >= P.MIN_COVERAGE, "island fills the sheet",
		string.format("%.1f%% of the sheet (target >= %.0f%%); linear resolution vs 32.8%% baseline is %.2fx",
			coverage * 100, P.MIN_COVERAGE * 100, math.sqrt(coverage / 0.328)))

	-- ---- tears and density uniformity ----
	local function get(ix: number, iy: number)
		local idx = iy*W + ix
		if buffer.readu8(MASK, idx) == 0 then return nil end
		local o = idx*12
		return buffer.readf32(POS,o), buffer.readf32(POS,o+4), buffer.readf32(POS,o+8)
	end
	local steps = {}
	for y = 0, W-2 do
		Y.tick()
		for x = 0, W-2 do
			local ax,ay,az = get(x,y)
			local bx,by,bz = get(x+1,y)
			if ax and bx then
				table.insert(steps, math.sqrt((ax-bx)^2+(ay-by)^2+(az-bz)^2))
			end
		end
	end
	table.sort(steps)
	local median = steps[#steps // 2]
	local tears = 0
	for _, d in ipairs(steps) do
		if d > P.TEAR_FACTOR * median then tears += 1 end
	end
	check(tears == 0, "no tears",
		string.format("%d sheet-neighbours are >%dx the median step (%.5f) apart in 3D",
			tears, P.TEAR_FACTOR, median))

	-- density spread: p95 over p5, a proxy for how uneven the stretch is
	local p05 = steps[math.max(1, math.floor(#steps * 0.05))]
	local p95 = steps[math.max(1, math.floor(#steps * 0.95))]
	check(p95 / p05 < 3, "texel density is even",
		string.format("p95/p05 step ratio %.2f (median %.5f body-radii)", p95 / p05, median))

	log("")
	log("[Verify] %d passed, %d failed", pass, fail)
	if fail == 0 then
		log("[Verify] the unwrap meets dev/UNWRAP_SPEC.md -- rebuild the skins and look at the underside")
	else
		log("[Verify] see the failure table in dev/UNWRAP_SPEC.md for what each one means")
	end

	local outStr = table.concat(lines, "\n")
	print(outStr)
	return outStr
end

return run()
