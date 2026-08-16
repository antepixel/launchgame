--!strict
-- BUILD_GALAXY.luau -- STANDALONE REBUILD SCRIPT FOR THE GALAXY SKIN.
--
-- Paste the whole file into the Studio command bar and it builds
-- workspace.GalaxySkin from nothing: the textured body, the face parts, and a
-- procedurally generated EditableImage. No other file needs to be present.
--
-- NOT SHIPPING CODE and deliberately NOT under src/ (Rojo syncs that). Same
-- standing as dev/tiermarks/BUILD_TIERMARKS.luau and dev/divine/BUILD_DIVINE.luau.
--
-- ============================ WHAT WAS LEARNED =============================
--
-- THE PATTERN IS EVALUATED IN 3D, NOT DRAWN IN 2D. This is the whole design.
-- Every earlier skin generated a 2D image and let the UV mapping carry it onto
-- the mesh, which produced two unavoidable artifacts:
--   * at the top of the dome every u column converges to one point, so any 2D
--     pattern bunches into radiating streaks -- the "dumpling pleats" look;
--   * at the u wrap the left and right edges of the sheet do not agree, so a
--     vertical seam runs down the body.
-- Both are properties of the MAPPING, so no amount of 2D authoring removes them.
--
-- Instead: for each texel, recover the 3D point on the mesh that the texel
-- actually paints, and evaluate the galaxy as a function of that point. 3D space
-- has no seam and no pole, so adjacent surface points get adjacent values by
-- construction, however badly the UV layout is distorted.
--
-- THE UV -> 3D MAP IS DERIVED FROM THE MESH, NOT ASSUMED. The usual
-- theta = u*2pi / phi = v*pi sphere formula is WRONG for this asset: the island
-- occupies only v = 0.3345 .. 0.6899, u carries an overshoot to 1.2517, and the
-- body is a squashed dome, not a sphere. So buildUVMap() rasterises the mesh's
-- own UV triangles and barycentrically interpolates vertex positions -- the
-- exact inverse of whatever Blender produced.
--
-- MEASURED, NOT ASSUMED -- the two numbers that prove the fix works:
--   * SEAM: texel column 0 and column 1023 are 1.15 texels apart in 3D. They are
--     genuine neighbours, so the function is continuous across the wrap.
--   * POLE: the topmost covered row's 1024 texels collapse to a sphere of radius
--     0.058 body-radii. They are all essentially ONE 3D point, so they all get
--     the same colour and cannot streak.
-- Re-verified by the script on every run; a mesh change that broke either would
-- have to be caught here rather than discovered by eye.
--
-- TWO SEAM-STRADDLING TRIANGLES EXIST and must be handled. Almost all of the
-- mesh has duplicated vertices along the seam, but 2 faces of 15192 span the
-- wrap directly. Rasterised naively they smear across the entire sheet. Fixed by
-- lifting the low corners by +1 and letting the texel index wrap modulo width.
--
-- THE STRAY CUBE IS EXCLUDED. The imported mesh carries 24 vertices of a stray
-- unit cube ~500 units above the body (12 faces). Its UVs would otherwise stamp
-- garbage into the sheet.
--
-- STARS ARE 3D, WHICH IS WHY THEY ARE ROUND. A star drawn as a round dot in
-- texture space renders as a STREAK on the mesh, stretched by the UV distortion
-- -- that was the second-biggest tell in earlier attempts. Here a star is a
-- sphere in 3D; the surface cuts it in a circle, so it is round on the body no
-- matter what the mapping does. It also means brightness varies for free: stars
-- whose centre lies slightly off the surface are cut nearer their rim and read
-- dimmer, which is exactly the uneven field a real sky has.
--
-- THE GENERATION LOOP MUST YIELD OR STUDIO KILLS THE PLUGIN. A million texels
-- of galaxy() is tens of seconds of straight-line work, and holding the main
-- thread that long makes Studio raise "user_MCPPlugin.rbxmx is not responding"
-- and offer to end the plugin. If the user takes that offer -- or Studio decides
-- on its own -- the MCP bridge dies WITH the plugin and the whole generation is
-- lost with no partial result. So every heavy loop yields.
--
-- THE YIELD IS TIME-BUDGETED, NOT EVERY-N-ROWS. A fixed row stride does not
-- work here because cost per row is wildly uneven: rows outside the UV island
-- are pure buffer writes, rows through a dense cloud run the full 27-cell star
-- lattice on all 1024 texels. One stride is either useless on the cheap rows or
-- still over budget on the expensive ones. Instead the loops check the clock at
-- a sub-row boundary and yield once they have held the thread for YIELD_MS,
-- which bounds the block by construction whatever the content does. The worst
-- hold actually observed is reported on every run, so a regression shows up as
-- a number rather than as another watchdog dialog.
--
-- RESOLUTION IS 1024 x 1024, AND 67% OF IT IS WASTED. Not a choice -- the UV
-- island covers only 32.8% of the sheet, so two thirds of the memory paints
-- nothing. Rescaling the UVs in Blender to fill 0..1 would give roughly 1.7x the
-- linear resolution for the same 4 MB. See the report for the sizing arithmetic.
--
-- VERIFICATION STATUS -- READ THIS BEFORE TRUSTING THE NUMBERS ABOVE.
-- The maths is verified OFFLINE, without Studio, by two suites that load this
-- very file and exercise its real functions:
--     lune run dev/analysis/verify_galaxy_core.luau     -- noise, galaxy(), yielder
--     lune run dev/analysis/verify_galaxy_uvmap.luau    -- buildUVMap vs ground truth
-- The second builds a synthetic UV sphere whose correct answer for every texel
-- is known analytically, and confirms the map lands within 0.34 texels of it --
-- with a negative control that strips the straddle lift and shows the error blow
-- out to 325 texels, so the fix is demonstrably load-bearing rather than merely
-- untriggered.
--
-- VERIFIED IN STUDIO by destroy-and-rebuild against the real slime_uv asset.
-- Build completed in 16.6 s, of which paint is 15.5 s. Measured on that run:
--   coverage    343973 texels, 32.8% of sheet, 2 seam triangles, 12 cube faces
--   seam gap    1.07 texels        pole spread  0.0762 body-radii
--   dark 63.1%  lit 36.9%          star-bright  0.87%
--   grazed      7 texels (0.002%)  worst hold   18.7 ms in 'paint' (budget 12)
-- A straight-down screenshot at the pole shows smooth cloud and round discrete
-- stars with NO radiating streaks, so the 3D approach holds on the real asset,
-- not just on the synthetic sphere in the offline suite.
--
-- THE OVERLAP IS REAL AND IT IS RASTERISER BLEED, not two surfaces colliding.
-- 16801 texels (4.88% of the island) are claimed by two faces that disagree,
-- worst 0.818 body-radii, 93% of them in rows 640..703 -- the island's bottom
-- band, which is the body's underside. The tempting reading is that the underside
-- and the lower outer wall fight over shared texels. MEASURED, they do not: the
-- contested pairs sit 0.05-0.07 body-radii apart, i.e. adjacent bits of the SAME
-- surface, and the u overshoot supplies only 18.9% of them (129 faces, 1.00% of
-- UV area). What was actually happening is that the -0.002 barycentric tolerance
-- lets a face paint a texel past its own edge, and under last-writer-wins a face
-- that merely GRAZED a texel could take it from the face that contained it.
--
-- FIXED by deciding ownership on containment class, outwardness breaking ties
-- (see buildUVMap). Grazed ownership went from 2075 texels to 7. The underside
-- reads as continuous cloud with visible stars instead of a smeared vortex, and
-- the outer surface is unchanged -- coverage and seam gap identical to the digit,
-- and the pole shot is indistinguishable from the pre-fix one.
--
-- WHY THE UNDERSIDE WAS WORTH FIXING AT ALL: a slime at rest hides it on the
-- ground, so a base-builder could ignore this entirely. This is a launch game --
-- slimes are airborne for most of the reward loop and a player below is looking
-- straight at rows 640..703.
--
-- WHAT REMAINS: 167 neighbour-jump texels along the extreme bottom rim, visible
-- as fine striation right at the silhouette edge. That is UV density, not
-- ownership -- the bottom band carries a stretch factor of 43 against ~29
-- elsewhere -- and it needs a better unwrap, not a better tie-break.
--
-- IF THE STUDIO BRIDGE WILL NOT ANSWER, read dev/README.md BEFORE touching the
-- plugin. "Studio plugin connection timeout" usually does NOT mean the plugin is
-- dead -- with several sessions open there are several MCP servers, and yours may
-- simply not be the one Studio attached to.
--
-- REVERSAL: workspace.GalaxySkin:Destroy().
-- ===========================================================================

local AssetService = game:GetService("AssetService")

-- ===================================================================
-- PARAMETERS -- everything tunable lives here.
-- ===================================================================
local P = {
	-- ---- output ----
	TEX_W = 1024,
	TEX_H = 1024,
	ROOT_NAME = "GalaxySkin",
	SOURCE_MODEL = "slime_uv",     -- the UNWRAPPED body; the lineup mesh has no usable UVs
	SOURCE_PART = "default",
	BUILD_POS = Vector3.new(0, 40, 0),
	-- The face sits at body azimuth -141.5 deg. This yaw turns it toward a camera
	-- standing at world azimuth +37.9, which is the framing the report shots use.
	BODY_YAW_DEG = 179.4,
	-- Plastic, NOT SmoothPlastic. On a near-black texture SmoothPlastic's specular
	-- lobe becomes a large blown-out white blob that reads as a bug -- it swamps
	-- the stars and destroys the illusion. Plastic's highlight is soft enough to
	-- leave the dark ground dark. Neon also removes the blob but self-lights the
	-- whole body, flattening the form. The lineup slimes are Plastic too.
	BODY_MATERIAL = Enum.Material.Plastic,

	-- ---- watchdog guard ----
	-- Longest the generation loops may hold the main thread before yielding.
	-- One 60 Hz frame is 16.7 ms, so 12 ms leaves headroom for the partial chunk
	-- in flight when the budget expires and still keeps each block inside a
	-- frame or two. See the header for why this is time-based, not row-based.
	YIELD_MS = 12,

	-- ---- the dark ground ----
	-- Near-black with a blue-violet tint. Everything else is ADDED to this, so
	-- the bright parts read as light rather than as paint.
	BASE_COLOR = Color3.fromRGB(5, 4, 13),

	-- ---- nebula structure ----
	NEBULA_SCALE = 2.05,           -- 3D frequency of the cloud detail
	NEBULA_OCTAVES = 4,
	NEBULA_WARP = 0.90,            -- domain-warp strength; this is what makes edges ragged
	NEBULA_WARP_SCALE = 1.25,
	NEBULA_LO = 0.40,              -- below this density the surface stays dark
	NEBULA_HI = 0.78,              -- at this density the cloud is at full strength
	NEBULA_GAIN = 1.15,

	-- ---- which parts of the body get clouds at all ----
	-- A very low frequency field, so only two or three big regions light up
	-- instead of an even scatter.
	-- Tuned by measurement, not by eye. This gate decides how much of the body
	-- gets any cloud at all, and it is the single most sensitive parameter:
	--   LO 0.38 -> 83.2% dark, a whole hemisphere bare (too dark)
	--   LO 0.27 -> 51.4% dark, clouds nearly everywhere (too busy)
	--   LO 0.32 -> 62.0% dark  <- kept, inside the intended 60-70% band
	REGION_SCALE = 0.80,
	REGION_OCTAVES = 2,
	REGION_LO = 0.32,
	REGION_HI = 0.69,

	-- ---- cloud colour ramp: edge -> mid -> core ----
	EDGE_COLOR = Color3.fromRGB(26, 38, 124),    -- deep blue, thin outskirts
	MID_COLOR = Color3.fromRGB(134, 54, 210),    -- violet
	CORE_COLOR = Color3.fromRGB(255, 82, 176),   -- hot pink, densest cores
	TINT_SCALE = 2.7,              -- breaks the ramp off pure density
	TINT_AMOUNT = 0.42,

	-- ---- stars ----
	STAR_CELL = 0.050,             -- 3D lattice pitch, in body radii
	STAR_PROB = 0.68,              -- fraction of cells holding a star
	STAR_RADIUS = 0.0092,          -- core radius; ~1 texel at this resolution
	STAR_BRIGHT_GAMMA = 2.7,       -- >1 => mostly dim, a handful bright
	STAR_MIN_B = 0.12,
	STAR_MAX_B = 1.0,
	STAR_DENSITY_SCALE = 1.45,     -- low-freq field that clumps the stars
	STAR_DENSITY_MIN = 0.35,       -- how sparse the emptiest regions get
	BLOOM_THRESHOLD = 0.70,        -- only the brightest stars bloom
	BLOOM_RADIUS = 0.030,
	BLOOM_GAIN = 0.42,
	STAR_WARM = Color3.fromRGB(255, 240, 214),   -- slight colour spread across stars
	STAR_COOL = Color3.fromRGB(206, 226, 255),

	-- ---- seeds ----
	SEED_WARP = 11,
	SEED_NEBULA = 29,
	SEED_REGION = 47,
	SEED_TINT = 71,
	SEED_STARDENS = 97,
	SEED_STAR = 131,
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
-- WATCHDOG GUARD. tick() is called at loop boundaries; it yields only once the
-- thread has been held for YIELD_MS, so the cost on a cheap iteration is one
-- os.clock() and nothing else. Yielding is what keeps Studio from killing the
-- plugin (and the MCP bridge with it) partway through generation.
-- ===================================================================
local function newYielder(budgetMs: number)
	local budget = budgetMs / 1000
	local last = os.clock()
	local yields, worst, worstLabel = 0, 0, "none"
	local label = "startup"
	local phaseStart = os.clock()
	local order, spent = {}, {}

	local function note()
		local held = os.clock() - last
		if held > worst then
			worst = held
			worstLabel = label
		end
	end
	local function endPhase(now: number)
		if not spent[label] then table.insert(order, label) end
		spent[label] = (spent[label] or 0) + (now - phaseStart)
	end

	return {
		tick = function()
			if os.clock() - last >= budget then
				note()
				task.wait()
				last = os.clock()
				yields += 1
			end
		end,
		-- call at the end of a loop so the final unyielded chunk is measured too
		close = function()
			note()
			last = os.clock()
		end,
		-- Start a new phase, AND reset the clock without recording a hold.
		--
		-- That second part is load-bearing. os.clock() measures wall time, which
		-- cannot distinguish "this loop blocked the main thread" from "the thread
		-- was parked inside an engine call that yields internally". Async calls
		-- like CreateEditableMeshAsync / CreateEditableImage take real seconds but
		-- hold nothing, so charging them to the next tick reports a fake stall --
		-- which is exactly what the first real run did, aborting a finished build
		-- on a hold that never happened. Call mark() straight after any such call.
		mark = function(name: string)
			local now = os.clock()
			endPhase(now)
			label = name
			phaseStart = now
			last = now
		end,
		yields = function(): number return yields end,
		worstMs = function(): number return worst * 1000 end,
		worstLabel = function(): string return worstLabel end,
		breakdown = function(): string
			endPhase(os.clock())
			phaseStart = os.clock()
			local parts = {}
			for _, k in ipairs(order) do
				table.insert(parts, string.format("%s %.1fs", k, spent[k]))
			end
			return table.concat(parts, ", ")
		end,
	}
end

-- ===================================================================
-- NOISE. Integer hash, no trig: every multiply is kept under 2^53 so the
-- result is exact and the image is reproducible bit-for-bit.
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

-- ===================================================================
-- THE GALAXY. q is a point on the body, in body-radius units, centred on the
-- body. Returns linear r, g, b in 0..1.
-- ===================================================================
local BASE_R, BASE_G, BASE_B = P.BASE_COLOR.R, P.BASE_COLOR.G, P.BASE_COLOR.B
local EDGE_R, EDGE_G, EDGE_B = P.EDGE_COLOR.R, P.EDGE_COLOR.G, P.EDGE_COLOR.B
local MID_R, MID_G, MID_B = P.MID_COLOR.R, P.MID_COLOR.G, P.MID_COLOR.B
local CORE_R, CORE_G, CORE_B = P.CORE_COLOR.R, P.CORE_COLOR.G, P.CORE_COLOR.B
local WARM_R, WARM_G, WARM_B = P.STAR_WARM.R, P.STAR_WARM.G, P.STAR_WARM.B
local COOL_R, COOL_G, COOL_B = P.STAR_COOL.R, P.STAR_COOL.G, P.STAR_COOL.B

local function galaxy(qx: number, qy: number, qz: number): (number, number, number, number)
	-- ---- nebula ----
	local ws = P.NEBULA_WARP_SCALE
	local wx = (vnoise3(qx * ws, qy * ws, qz * ws, P.SEED_WARP) - 0.5) * P.NEBULA_WARP
	local wy = (vnoise3(qx * ws, qy * ws, qz * ws, P.SEED_WARP + 1) - 0.5) * P.NEBULA_WARP
	local wz = (vnoise3(qx * ws, qy * ws, qz * ws, P.SEED_WARP + 2) - 0.5) * P.NEBULA_WARP

	local ns = P.NEBULA_SCALE
	local n = fbm3(qx * ns + wx, qy * ns + wy, qz * ns + wz, P.NEBULA_OCTAVES, P.SEED_NEBULA)

	local rs = P.REGION_SCALE
	local region = smoothstep(P.REGION_LO, P.REGION_HI,
		fbm3(qx * rs, qy * rs, qz * rs, P.REGION_OCTAVES, P.SEED_REGION))

	local density = smoothstep(P.NEBULA_LO, P.NEBULA_HI, n) * region

	local r, g, b = BASE_R, BASE_G, BASE_B
	if density > 0.001 then
		local ts = P.TINT_SCALE
		local tint = vnoise3(qx * ts, qy * ts, qz * ts, P.SEED_TINT) - 0.5
		local ramp = math.clamp(density + tint * P.TINT_AMOUNT, 0, 1)
		local cr, cg, cb
		if ramp < 0.5 then
			local k = ramp * 2
			cr = EDGE_R + (MID_R - EDGE_R) * k
			cg = EDGE_G + (MID_G - EDGE_G) * k
			cb = EDGE_B + (MID_B - EDGE_B) * k
		else
			local k = (ramp - 0.5) * 2
			cr = MID_R + (CORE_R - MID_R) * k
			cg = MID_G + (CORE_G - MID_G) * k
			cb = MID_B + (CORE_B - MID_B) * k
		end
		local amt = density * P.NEBULA_GAIN
		r += cr * amt
		g += cg * amt
		b += cb * amt
	end

	-- ---- stars: 3D cellular, so they are round ON THE BODY ----
	local ds = P.STAR_DENSITY_SCALE
	local dens = vnoise3(qx * ds, qy * ds, qz * ds, P.SEED_STARDENS)
	local prob = P.STAR_PROB * (P.STAR_DENSITY_MIN + (1 - P.STAR_DENSITY_MIN) * dens)

	local cell = P.STAR_CELL
	local cx0 = math.floor(qx / cell)
	local cy0 = math.floor(qy / cell)
	local cz0 = math.floor(qz / cell)
	local sr, sg, sb = 0, 0, 0
	for dz = -1, 1 do
		for dy = -1, 1 do
			for dx = -1, 1 do
				local cx, cy, cz = cx0 + dx, cy0 + dy, cz0 + dz
				local h1 = ihash(cx, cy, cz, P.SEED_STAR)
				if (h1 % 4096) / 4096 < prob then
					local h2 = ihash(cx, cy, cz, P.SEED_STAR + 1)
					local jx = (bit32.band(h1, 1023) / 1024)
					local jy = (bit32.band(bit32.rshift(h1, 10), 1023) / 1024)
					local jz = (bit32.band(bit32.rshift(h1, 20), 1023) / 1024)
					local px = (cx + jx) * cell
					local py = (cy + jy) * cell
					local pz = (cz + jz) * cell
					local ddx, ddy, ddz = qx - px, qy - py, qz - pz
					local d = math.sqrt(ddx * ddx + ddy * ddy + ddz * ddz)

					local bt = (bit32.band(h2, 65535) / 65536) ^ P.STAR_BRIGHT_GAMMA
					local bright = P.STAR_MIN_B + (P.STAR_MAX_B - P.STAR_MIN_B) * bt
					local rad = P.STAR_RADIUS * (0.55 + 0.75 * bt)

					local core = smoothstep(rad, 0, d) * bright
					local glow = 0
					if bt > P.BLOOM_THRESHOLD then
						local over = (bt - P.BLOOM_THRESHOLD) / (1 - P.BLOOM_THRESHOLD)
						glow = smoothstep(P.BLOOM_RADIUS, 0, d) * over * P.BLOOM_GAIN
					end
					local amt = core + glow
					if amt > 0 then
						local ct = bit32.band(bit32.rshift(h2, 16), 255) / 256
						sr += (COOL_R + (WARM_R - COOL_R) * ct) * amt
						sg += (COOL_G + (WARM_G - COOL_G) * ct) * amt
						sb += (COOL_B + (WARM_B - COOL_B) * ct) * amt
					end
				end
			end
		end
	end

	return r + sr, g + sg, b + sb, density
end

-- ===================================================================
-- THE UV -> 3D MAP, derived by rasterising the mesh's own UV triangles.
-- ===================================================================
local function buildUVMap(meshId: string, W: number, H: number, Y)
	local em = AssetService:CreateEditableMeshAsync(Content.fromUri(meshId))
	local verts, faces = em:GetVertices(), em:GetFaces()
	Y.mark("uvmap:verts")   -- the Async above yields; do not charge it as a stall

	-- body bbox, excluding the stray cube (which sits above Y = 0)
	local mnx, mxx = math.huge, -math.huge
	local mny, mxy = math.huge, -math.huge
	local mnz, mxz = math.huge, -math.huge
	for _, id in ipairs(verts) do
		Y.tick()   -- ~45k GetPosition calls is itself past the watchdog on a cold cache
		local p = em:GetPosition(id)
		if p.Y < 0 then
			mnx = math.min(mnx, p.X); mxx = math.max(mxx, p.X)
			mny = math.min(mny, p.Y); mxy = math.max(mxy, p.Y)
			mnz = math.min(mnz, p.Z); mxz = math.max(mxz, p.Z)
		end
	end
	local CX, CY, CZ = (mnx + mxx) / 2, (mny + mxy) / 2, (mnz + mxz) / 2
	local RAD = (mxx - mnx) / 2

	local POS = buffer.create(W * H * 3 * 4)
	local MASK = buffer.create(W * H)
	local covered, seamTris, skipped = 0, 0, 0

	-- OWNERSHIP. When two faces claim one texel, the winner is chosen by geometry
	-- rather than by which happened to rasterise last.
	--
	-- PRIMARY RULE: CONTAINMENT CLASS. The barycentric test below admits a texel
	-- at -0.002, so every triangle paints roughly a texel past its true edge. That
	-- bleed is wanted at the island rim (it stops the boundary cracking under
	-- bilinear filtering) but it means a face that merely GRAZES a texel could
	-- overwrite the face the texel genuinely belongs to. A grazing face has a
	-- negative minimum barycentric coordinate and a containing face does not, so
	-- the sign of min(l1,l2,l3) separates them exactly. Containing beats grazing.
	--
	-- This is what the underside conflicts turned out to be: measured pairs sat
	-- 0.05-0.07 body-radii apart, i.e. adjacent bits of the SAME surface bleeding
	-- into each other -- not the underside colliding with the outer wall, and not
	-- the u overshoot, which supplies only 18.9% of contested texels.
	--
	-- ONLY THE SIGN, NEVER THE MAGNITUDE. Ranking by how interior a texel is
	-- looks like a strictly better version of the same idea and is a disaster:
	-- among faces that ALL legitimately contain a texel it reorders the winner
	-- texel by texel, destroying the spatial coherence that makes the result read
	-- as a smooth surface. Measured over the four candidate policies, ranking by
	-- magnitude cut grazed ownership to 57 but took neighbour jumps from 111 to
	-- 4044 -- a visible fan of radial streaks on the upper dome. Class-only gets
	-- grazed down to 7 for 171 jumps. Do not "improve" this into a comparison.
	--
	-- TIE-BREAK: OUTWARDNESS -- within one class, prefer the face whose normal
	-- points away from the body centre, so a surface a player can see wins over
	-- one tucked underneath. It is a genuine if small improvement: dropping it and
	-- keeping the incumbent instead scores 194 jumps against this rule's 171.
	--
	-- It cannot do more than that here, and it is worth knowing why. This mesh is
	-- closed and consistently wound -- all 15180 body faces have POSITIVE
	-- outwardness, mean +0.948, range ~0.85..0.93 -- so outwardness never
	-- separates "underside" from "outer wall"; on its own it decides only 120
	-- texels. Containment is what does the work. If a future asset has genuinely
	-- overlapping charts, this is the clause that will matter.
	local CONFLICT_EPS = 0.05
	local conflicts, worstConflict = 0, 0
	-- per texel: [0] = interiority of current owner, [4] = its outwardness
	local PRIO = buffer.create(W * H * 8)

	Y.mark("uvmap:faces")
	for _, f in ipairs(faces) do
		Y.tick()   -- ~15k faces; average face is tiny, so per-face is fine granularity
		local fv = em:GetFaceVertices(f)
		local fu = em:GetFaceUVs(f)
		local p1, p2, p3 = em:GetPosition(fv[1]), em:GetPosition(fv[2]), em:GetPosition(fv[3])
		if p1.Y > 0 or p2.Y > 0 or p3.Y > 0 then
			skipped += 1
			continue
		end
		local a, b, c = em:GetUV(fu[1]), em:GetUV(fu[2]), em:GetUV(fu[3])
		local u1, u2, u3 = a.X, b.X, c.X
		local v1, v2, v3 = a.Y, b.Y, c.Y

		-- outwardness: how far this face's normal agrees with the direction from
		-- the body centre out to it. Computed once per face, used only to break
		-- interiority ties (see the OWNERSHIP note above).
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
					local first = buffer.readu8(MASK, idx) == 0
					local o, po = idx * 12, idx * 8
					local nx = (l1 * p1.X + l2 * p2.X + l3 * p3.X - CX) / RAD
					local ny = (l1 * p1.Y + l2 * p2.Y + l3 * p3.Y - CY) / RAD
					local nz = (l1 * p1.Z + l2 * p2.Z + l3 * p3.Z - CZ) / RAD
					local interior = math.min(l1, l2, l3)

					local wins
					if first then
						buffer.writeu8(MASK, idx, 1)
						covered += 1
						wins = true
					else
						-- count the contest regardless of who wins, so the figure
						-- stays comparable across ownership policies
						local dx = nx - buffer.readf32(POS, o)
						local dy = ny - buffer.readf32(POS, o + 4)
						local dz = nz - buffer.readf32(POS, o + 8)
						local d = math.sqrt(dx * dx + dy * dy + dz * dz)
						if d > CONFLICT_EPS then
							conflicts += 1
							if d > worstConflict then worstConflict = d end
						end
						local heldInt = buffer.readf32(PRIO, po)
						local heldOut = buffer.readf32(PRIO, po + 4)
						-- CLASS FIRST, and only class. A face either contains the
						-- texel or merely grazes it; containing always beats
						-- grazing. Within one class, outwardness decides.
						local iContains = interior >= 0
						local hContains = heldInt >= 0
						if iContains ~= hContains then
							wins = iContains
						else
							wins = outward > heldOut
						end
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

	-- THE NUMBER THAT SHOWS THE OWNERSHIP RULE WORKING. 'conflicts' counts texels
	-- two faces fought over, which is a property of the UV layout and so does not
	-- move when the tie-break changes. What DOES move is how many texels end up
	-- held by a face that only grazes them (negative interiority) -- under
	-- last-writer-wins that was whatever face order happened to leave behind.
	Y.mark("uvmap:audit")
	local grazed = 0
	for y = 0, H - 1 do
		Y.tick()
		local row = y * W
		for x = 0, W - 1 do
			local idx = row + x
			if buffer.readu8(MASK, idx) == 1 and buffer.readf32(PRIO, idx * 8) < 0 then
				grazed += 1
			end
		end
	end

	Y.close()
	return {
		POS = POS, MASK = MASK, covered = covered, seamTris = seamTris, skipped = skipped,
		conflicts = conflicts, worstConflict = worstConflict, grazed = grazed,
		CX = CX, CY = CY, CZ = CZ, RAD = RAD,
	}
end

-- Grow the painted region a few texels past the island edge, so bilinear
-- filtering at the boundary samples real colour instead of unwritten black.
local function dilate(POS, MASK, W: number, H: number, passes: number, y0: number, y1: number, Y): number
	local grown = 0
	for _ = 1, passes do
		local add = {}
		for y = math.max(0, y0), math.min(H - 1, y1) do
			Y.tick()   -- a row here is 1024 buffer reads; row granularity is well inside budget
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
-- BUILD.
-- ===================================================================
local function run()
	local lines = {}
	local function log(...) table.insert(lines, string.format(...)) end
	local t0 = os.clock()

	local srcModel = workspace:FindFirstChild(P.SOURCE_MODEL)
	assert(srcModel, string.format(
		"[Galaxy] workspace.%s not found. This skin needs the UNWRAPPED body mesh; "
			.. "the lineup slimes have no usable UV unwrap.", P.SOURCE_MODEL))
	local src = srcModel:FindFirstChild(P.SOURCE_PART) :: BasePart
	assert(src, "[Galaxy] " .. P.SOURCE_MODEL .. "." .. P.SOURCE_PART .. " not found")

	local W, H = P.TEX_W, P.TEX_H
	local Y = newYielder(P.YIELD_MS)
	local M = buildUVMap((src :: any).MeshId, W, H, Y)
	log("[Galaxy] UV map: %d texels covered (%.1f%% of sheet), %d seam triangles fixed, %d cube faces skipped",
		M.covered, 100 * M.covered / (W * H), M.seamTris, M.skipped)
	log("[Galaxy] OVERLAP: %d texels claimed by two faces that disagree (%.2f%% of the island), worst %.3f body-radii",
		M.conflicts, 100 * M.conflicts / math.max(1, M.covered), M.worstConflict)
	log("[Galaxy] OWNERSHIP: %d texels (%.3f%%) held by a face that only grazes them",
		M.grazed, 100 * M.grazed / math.max(1, M.covered))

	-- prove the two properties the whole approach rests on
	Y.mark("verify")
	local POS, MASK = M.POS, M.MASK
	local function getp(ix, iy)
		local idx = iy * W + ix
		if buffer.readu8(MASK, idx) == 0 then return nil end
		local o = idx * 12
		return buffer.readf32(POS, o), buffer.readf32(POS, o + 4), buffer.readf32(POS, o + 8)
	end
	local rmin, rmax = H, -1
	for y = 0, H - 1 do
		Y.tick()   -- an uncovered row scans all 1024 columns before giving up
		for x = 0, W - 1 do
			if buffer.readu8(MASK, y * W + x) == 1 then
				if y < rmin then rmin = y end
				if y > rmax then rmax = y end
				break
			end
		end
	end
	local seamWorst = 0
	for y = rmin, rmax do
		local ax, ay, az = getp(0, y)
		local bx, by, bz = getp(W - 1, y)
		if ax and bx then
			seamWorst = math.max(seamWorst, math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2 + (az - bz) ^ 2))
		end
	end
	-- Reference scale: the 3D distance between two horizontally adjacent texels,
	-- averaged over every adjacent covered pair in the island's middle row. This
	-- used to sample the single hardcoded pair (400, 401), which throws on a nil
	-- if either texel happens to land outside the island -- and it would throw
	-- only after buildUVMap, i.e. after the expensive half of the run.
	local midRow = (rmin + rmax) // 2
	local stepSum, stepN = 0, 0
	for x = 0, W - 2 do
		local ax, ay, az = getp(x, midRow)
		local bx, by, bz = getp(x + 1, midRow)
		if ax and bx then
			stepSum += math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2 + (az - bz) ^ 2)
			stepN += 1
		end
	end
	assert(stepN > 0, "[Galaxy] island middle row has no adjacent covered texels -- UV map is broken")
	local step = stepSum / stepN
	assert(step > 0, "[Galaxy] adjacent texels map to the same 3D point -- UV map is degenerate")
	local sx, sy, sz, cnt = 0, 0, 0, 0
	local pts = {}
	for x = 0, W - 1 do
		local a, b, c = getp(x, rmin)
		if a then sx += a; sy += b; sz += c; cnt += 1; table.insert(pts, { a, b, c }) end
	end
	local poleSpread = 0
	if cnt > 0 then
		sx, sy, sz = sx / cnt, sy / cnt, sz / cnt
		for _, p in ipairs(pts) do
			poleSpread = math.max(poleSpread, math.sqrt((p[1] - sx) ^ 2 + (p[2] - sy) ^ 2 + (p[3] - sz) ^ 2))
		end
	end
	log("[Galaxy] CONTINUITY: seam gap %.4f (= %.2f texels); pole row spread %.4f body-radii",
		seamWorst, seamWorst / step, poleSpread)
	assert(seamWorst / step < 3, "[Galaxy] seam columns are not neighbours -- 3D continuity would not hold")
	assert(poleSpread < 0.15, "[Galaxy] pole row does not converge -- streaking would return")

	-- only the band around the island can ever need growing
	Y.mark("dilate")
	local grown = dilate(POS, MASK, W, H, 4, rmin - 8, rmax + 8, Y)
	log("[Galaxy] dilated %d texels past the island edge (bilinear guard)", grown)

	-- ---- paint ----
	local img = AssetService:CreateEditableImage({ Size = Vector2.new(W, H) })
	local buf = buffer.create(W * H * 4)
	Y.mark("paint")   -- CreateEditableImage can yield; start the paint clock after it
	local darkCount, litCount, starCount = 0, 0, 0
	local painted = 0
	-- Sub-row, NOT per-row. A single row through a dense cloud runs galaxy() on
	-- all 1024 texels and on its own overruns a frame several times over, so a
	-- per-row check would never bring the block inside budget. 128 makes the
	-- check granularity ~8x finer than a row while costing one cheap test per texel.
	local TICK_STRIDE = 128
	for y = 0, H - 1 do
		for x = 0, W - 1 do
			if x % TICK_STRIDE == 0 then Y.tick() end
			local idx = y * W + x
			if buffer.readu8(MASK, idx) ~= 0 then
				local o = idx * 12
				local qx = buffer.readf32(POS, o)
				local qy = buffer.readf32(POS, o + 4)
				local qz = buffer.readf32(POS, o + 8)
				local r, g, b, dens = galaxy(qx, qy, qz)
				local lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
				if lum < 0.06 then darkCount += 1 else litCount += 1 end
				if lum > 0.45 then starCount += 1 end
				local off = idx * 4
				buffer.writeu8(buf, off, math.floor(math.clamp(r, 0, 1) * 255 + 0.5))
				buffer.writeu8(buf, off + 1, math.floor(math.clamp(g, 0, 1) * 255 + 0.5))
				buffer.writeu8(buf, off + 2, math.floor(math.clamp(b, 0, 1) * 255 + 0.5))
				buffer.writeu8(buf, off + 3, 255)
				painted += 1
			else
				local off = idx * 4
				buffer.writeu8(buf, off, 0)
				buffer.writeu8(buf, off + 1, 0)
				buffer.writeu8(buf, off + 2, 0)
				buffer.writeu8(buf, off + 3, 255)
			end
		end
	end
	Y.close()
	img:WritePixelsBuffer(Vector2.zero, Vector2.new(W, H), buf)
	log("[Galaxy] painted %d texels | dark %.1f%% | lit %.1f%% | star-bright %.2f%%",
		painted, 100 * darkCount / painted, 100 * litCount / painted, 100 * starCount / painted)
	-- Reported, NOT asserted. The first real run aborted here after 8.7 minutes of
	-- completed work over a hold that turned out to be an Async call yielding
	-- rather than a loop blocking. Even a genuine overrun is a performance fault,
	-- not a correctness one: throwing away a finished texture over it is strictly
	-- worse than handing it over with the number attached. The continuity asserts
	-- above still abort, because those mean the IMAGE is wrong.
	log("[Galaxy] WATCHDOG: yielded %d times | longest hold %.1f ms in '%s' (budget %d ms)",
		Y.yields(), Y.worstMs(), Y.worstLabel(), P.YIELD_MS)
	log("[Galaxy] TIME: %s", Y.breakdown())
	if Y.worstMs() > 100 then
		warn(string.format(
			"[Galaxy] '%s' held the main thread %.0f ms -- over the 100 ms watchdog margin. "
				.. "The build is fine; the guard needs a tick inside that phase.",
			Y.worstLabel(), Y.worstMs()))
	end

	-- ---- assemble ----
	for _, c in ipairs(workspace:GetChildren()) do
		if c.Name == P.ROOT_NAME then c:Destroy() end
	end
	local root = Instance.new("Model")
	root.Name = P.ROOT_NAME
	root.Parent = workspace

	-- body centre sits at an offset inside the source part's bounding box,
	-- because the stray cube inflates that box ~500 units upward
	local localOff = Vector3.new(M.CX, M.CY, M.CZ)
	local bodyCF = CFrame.new(P.BUILD_POS) * CFrame.Angles(0, math.rad(P.BODY_YAW_DEG), 0)

	local body = src:Clone()
	body.Name = "body"
	body.Color = Color3.new(1, 1, 1)
	body.Material = P.BODY_MATERIAL
	body.Anchored = true
	body.CanCollide = false; body.CanQuery = false; body.CanTouch = false
	pcall(function() body.TextureID = "" end)
	body.TextureContent = Content.fromObject(img)
	body.CFrame = bodyCF * CFrame.new(-localOff)
	body.Parent = root
	root.PrimaryPart = body

	for _, spec in ipairs(FACE_PARTS) do
		local part = AssetService:CreateMeshPartAsync(Content.fromUri(spec.mesh))
		part.Name = spec.name
		part.Size = spec.size
		part.Color = spec.color
		part.Material = Enum.Material.Plastic   -- matches the lineup slimes
		part.Anchored = true
		part.CanCollide = false; part.CanQuery = false; part.CanTouch = false
		part.CFrame = bodyCF * spec.rel
		part.Parent = root
	end

	root:SetAttribute("BodyCentre", P.BUILD_POS)
	root:SetAttribute("BodyYawDeg", P.BODY_YAW_DEG)

	log("[Galaxy] built workspace.%s (%dx%d texture, body + %d face parts) in %.2f s",
		P.ROOT_NAME, W, H, #FACE_PARTS, os.clock() - t0)
	log("[Galaxy] undo with workspace.%s:Destroy()", P.ROOT_NAME)

	local outStr = table.concat(lines, "\n")
	print(outStr)
	return outStr
end

return run()
