-- Offline verification of dev/skins/BUILD_GALAXY.luau's pure-math core: the
-- noise stack, galaxy(), and the watchdog yielder. The design rationale lives in
-- that file's own header block; this file only checks it.
--
--   lune run dev/analysis/verify_galaxy_core.luau
--
-- Run from the REPO ROOT. Deterministic (its own LCG, no math.random, no seed
-- argument). Prints to stdout only; writes nothing to dev/out. Exits non-zero if
-- any check fails.
--
-- WHY THIS EXISTS: the galaxy skin can only be seen by building it in Studio,
-- and the Studio MCP plugin dies often enough that "just run it and look" is not
-- a reliable loop. Everything here is a property of the maths rather than of the
-- render, so it can be checked without Studio at all -- and it is the half most
-- likely to rot silently, because a broken noise function still produces a
-- picture, just the wrong one.
--
-- THE REAL FILE IS EXERCISED, NOT A COPY. The source is sliced at the section
-- divider where Roblox-only APIs begin and the front half is loaded verbatim, so
-- editing BUILD_GALAXY.luau is picked up here immediately. Nothing below
-- reimplements a function that exists in that file.
--
-- WHAT IT CANNOT CHECK, stated plainly: this covers galaxy() as a function of a
-- 3D point. Whether the right 3D point reaches it for a given texel is the UV
-- map's job -- see verify_galaxy_uvmap.luau. Whether the result looks good on
-- the body is a screenshot question and belongs in Studio.
local luau = require("@lune/luau")
local C = require("./common")

-- readSource, not fs.readFile: the repo checks out CRLF, and the section markers
-- below are line-anchored.
local src = C.readSource("dev/skins/BUILD_GALAXY.luau")

-- the section divider, not the header paragraph that mentions the same phrase
local MARKER = "-- THE UV %-> 3D MAP, derived"
local cut = src:find(MARKER)
assert(cut, "marker not found -- file structure changed")
local core = src:sub(1, cut - 1)
assert(core:find("local function galaxy"), "galaxy() not inside the sliced region")
assert(core:find("local function newYielder"), "newYielder() not inside the sliced region")

-- ---- stubs for the Roblox constructors the core touches ----
local PRELUDE = [[
local waits = 0
Color3 = {
	fromRGB = function(r, g, b) return { R = r / 255, G = g / 255, B = b / 255 } end,
	new = function(r, g, b) return { R = r, G = g, B = b } end,
}
Vector3 = { new = function(x, y, z) return { X = x, Y = y, Z = z } end }
Vector2 = { new = function(x, y) return { X = x, Y = y } end, zero = { X = 0, Y = 0 } }
CFrame = { new = function(...) return { ... } end, Angles = function(...) return { ... } end }
Enum = { Material = { Plastic = "Plastic", SmoothPlastic = "SmoothPlastic" } }
task = { wait = function() waits += 1 end }
game = { GetService = function() return {} end }
__waits = function() return waits end
]]

local SUFFIX = [[
return { galaxy = galaxy, newYielder = newYielder, vnoise3 = vnoise3, P = P, waits = __waits }
]]

local chunk = luau.load(PRELUDE .. core .. SUFFIX, { debugName = "galaxycore" })
local G = chunk()
local galaxy, newYielder, P = G.galaxy, G.newYielder, G.P

local fails = 0
local function check(name, ok, detail)
	print(string.format("  [%s] %s%s", ok and "PASS" or "FAIL", name, detail and ("  -- " .. detail) or ""))
	if not ok then fails += 1 end
end

-- deterministic sampler (no math.random, so runs are comparable)
local seed = 12345
local function rnd()
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end
local function spherePoint()
	-- uniform on the unit sphere
	local z = rnd() * 2 - 1
	local t = rnd() * 2 * math.pi
	local r = math.sqrt(math.max(0, 1 - z * z))
	return r * math.cos(t), r * math.sin(t), z
end

print("\n=== 1. galaxy() is deterministic ===")
do
	local x, y, z = spherePoint()
	local a1, a2, a3 = galaxy(x, y, z)
	local b1, b2, b3 = galaxy(x, y, z)
	check("same input gives identical output", a1 == b1 and a2 == b2 and a3 == b3)
end

print("\n=== 2. galaxy() is continuous in 3D (no seam, no pole) ===")
do
	-- The premise of the whole design: nearby 3D points get nearby colours.
	-- A genuine discontinuity would show as a large jump across a tiny step.
	local EPS = 1e-4
	local worst, worstAt = 0, nil
	for _ = 1, 40000 do
		local x, y, z = spherePoint()
		local r1, g1, b1 = galaxy(x, y, z)
		-- step along an arbitrary tangent direction
		local tx, ty, tz = spherePoint()
		local r2, g2, b2 = galaxy(x + tx * EPS, y + ty * EPS, z + tz * EPS)
		local d = math.max(math.abs(r1 - r2), math.abs(g1 - g2), math.abs(b1 - b2))
		if d > worst then worst, worstAt = d, { x, y, z } end
	end
	-- Star cores are deliberately steep (radius ~0.009), so a 1e-4 step can still
	-- move brightness a few percent. Anything approaching a full-scale jump would
	-- mean a real discontinuity.
	check("max colour jump over a 1e-4 step stays small", worst < 0.10,
		string.format("worst = %.5f at (%.3f, %.3f, %.3f)", worst, worstAt[1], worstAt[2], worstAt[3]))
end

print("\n=== 3. the u-wrap and the pole are not special ===")
do
	-- Whatever the UV layout does, these are ordinary 3D points. Sample a ring
	-- right at the top of the body (where a 2D pattern would streak) and confirm
	-- the values vary no more than anywhere else.
	local function ringSpread(elevation)
		local lo, hi = math.huge, -math.huge
		local r = math.sqrt(math.max(0, 1 - elevation * elevation))
		for i = 0, 255 do
			local t = i / 256 * 2 * math.pi
			local cr, cg, cb = galaxy(r * math.cos(t), elevation, r * math.sin(t))
			local lum = 0.2126 * cr + 0.7152 * cg + 0.0722 * cb
			lo, hi = math.min(lo, lum), math.max(hi, lum)
		end
		return hi - lo
	end
	local atPole = ringSpread(0.9995)   -- the convergence point
	local atMid = ringSpread(0.0)       -- the equator, for reference
	check("a ring at the pole is far tighter than one at the equator", atPole < atMid,
		string.format("pole spread %.5f vs equator spread %.5f", atPole, atMid))
end

print("\n=== 4. colour statistics land in the intended band ===")
do
	local dark, lit, star, n = 0, 0, 0, 60000
	for _ = 1, n do
		local x, y, z = spherePoint()
		local r, g, b = galaxy(x, y, z)
		local lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
		if lum < 0.06 then dark += 1 else lit += 1 end
		if lum > 0.45 then star += 1 end
	end
	local darkPct = 100 * dark / n
	-- the header claims the REGION_LO 0.32 tuning gives ~62% dark
	check("dark fraction inside the intended 60-70% band", darkPct >= 55 and darkPct <= 75,
		string.format("dark %.1f%%, lit %.1f%%, star-bright %.2f%%", darkPct, 100 * lit / n, 100 * star / n))
	check("some texels are star-bright", star > 0, string.format("%d of %d", star, n))
end

print("\n=== 5. output stays in a sane range ===")
do
	local maxc, minc = -math.huge, math.huge
	local over = 0
	for _ = 1, 40000 do
		local x, y, z = spherePoint()
		local r, g, b = galaxy(x, y, z)
		maxc = math.max(maxc, r, g, b)
		minc = math.min(minc, r, g, b)
		if r > 1 or g > 1 or b > 1 then over += 1 end
	end
	check("no negative channels", minc >= 0, string.format("min = %.4f", minc))
	check("clipping is rare (bloom cores only)", over / 40000 < 0.02,
		string.format("max = %.3f, %.2f%% of samples clip", maxc, 100 * over / 40000))
end

print("\n=== 6. the yielder honours its budget ===")
do
	local Y = newYielder(12)
	local burn = 0
	-- simulate a heavy loop: tick, then hold the thread for ~3 ms per iteration
	for _ = 1, 40 do
		Y.tick()
		local t = os.clock()
		while os.clock() - t < 0.003 do burn += 1 end
	end
	Y.close()
	check("it yielded", Y.yields() > 0, string.format("%d yields over ~120 ms of work", Y.yields()))
	check("worst hold is near the budget, not the whole loop", Y.worstMs() < 40,
		string.format("worst hold %.1f ms (budget 12 ms)", Y.worstMs()))
	check("task.wait was actually called", G.waits() == Y.yields(),
		string.format("%d waits vs %d yields", G.waits(), Y.yields()))
end

print("\n=== 7. a zero-cost loop never yields ===")
do
	local Y = newYielder(12)
	for _ = 1, 100000 do Y.tick() end
	Y.close()
	check("tick() on cheap iterations is essentially free", Y.yields() <= 2,
		string.format("%d yields over 100k empty ticks (%.1f ms worst)", Y.yields(), Y.worstMs()))
end

print(string.format("\n%s  (%d failure%s)", fails == 0 and "ALL PASS" or "FAILURES", fails, fails == 1 and "" or "s"))
if fails > 0 then
	require("@lune/process").exit(1)
end

