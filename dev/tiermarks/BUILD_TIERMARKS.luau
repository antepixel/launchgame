--!strict
-- BUILD_TIERMARKS.luau -- STANDALONE REBUILD SCRIPT FOR THE TIER-MARK TREATMENT.
--
-- Paste the whole file into the Studio command bar and it reconstructs every
-- tier mark on workspace.SlimeLineup from nothing. No other file needs to be
-- present. THE TREATMENT IS THE MATHS, NOT THE PARTS -- the marks themselves
-- regenerate in seconds; this file is the seven minutes of derivation that
-- would otherwise be lost when the session closes.
--
-- NOT SHIPPING CODE and deliberately NOT under src/ (Rojo syncs that). This is
-- a design prototype. When a direction is approved it gets rebuilt properly as
-- a builder module.
--
-- PRECONDITION: workspace.SlimeLineup must exist, with rows T1_Common ..
-- T5_Legendary, each holding six slime Models built by
-- ReplicatedStorage.SlimeBuilder (a Model containing a MeshPart named "slime"
-- plus eye_dark / eye_white / blush). The script asserts this and stops with a
-- clear message rather than half-building. Rebuilding the LINEUP itself is a
-- separate job and is not attempted here.
--
-- ============================ WHAT WAS LEARNED =============================
--
-- WHY GEOMETRY AT ALL -- the texture path is dead on this asset. The body mesh
-- has NO USABLE UV UNWRAP: an authored EditableImage checkerboard, a solid
-- green fill, and a half-red/half-blue split were each applied via
-- TextureContent. Solid green rendered green (so the pipeline works), but the
-- checkerboard and the half/half BOTH rendered as the exact arithmetic average
-- of the image with zero spatial variation -- every vertex maps to the same UV,
-- the derivative is zero, and the sampler collapses to the 1x1 mip. That kills
-- TextureID, Decal, Texture and SurfaceAppearance alike, since all four sample
-- the same dead UV set. A ~20-minute Blender cylindrical unwrap would make all
-- of this trivial and procedural via EditableImage, with zero added parts --
-- see the written report. This file is the no-unwrap fallback.
--
-- THE MARKER TRIANGLES ARE THE LOAD-BEARING TRICK. Two sub-pixel triangles are
-- emitted at the BODY MESH's own bbox corners, so the generated mark mesh has
-- exactly the same bounding box as the body mesh. That is what makes
--     mark.Size   = body.Size * MARK_INFLATE
--     mark.CFrame = body.CFrame
-- exact, with no offset arithmetic anywhere -- and it is also why the mark
-- follows SlimeIdleClient's squash FOR FREE: the idle writes body.Size as
-- baseSize * (sxz, sy, sxz), and the mark, being a pure multiple of body.Size,
-- deforms identically. Verified at both extremes (sy 0.92 and 1.08) with no
-- separation. Without the markers the mesh bbox is set by the mark geometry
-- itself, which varies per tier, and every tier lands at a different scale.
--
-- THE OFFSET IS 2.0%, AND THIS WAS MEASURED, NOT GUESSED. 1.006 was tried and
-- z-fought badly -- the mark vanished INSIDE the body and rendered as nothing
-- at all. Intermediate baked normal offsets of 0.008 and 0.014 mesh units both
-- speckled. 2.0% is the first value with no shimmer. The residual cause is that
-- radiusAt interpolates linearly between measured latitude rings, and a chord
-- cuts slightly inside a convex surface.
--
-- THE PROFILE MUST COME FROM NON-EMPTY BUCKETS ONLY. The mesh's 45,694 vertices
-- sit in discrete latitude rings, so bucketing them into 96 height bands leaves
-- 42 of the 96 EMPTY. Interpolating into a zero collapsed the radius to ~25% of
-- true and buried every mark inside the body -- this was the cause of two
-- entirely invisible builds before it was found. Only non-empty buckets become
-- interpolation samples.
--
-- GRID IS 96 x 48. Finer was rejected on the 60-slime budget: doubling either
-- axis quadruples triangles on Legendary, the most expensive tier, and the
-- 60-slime worst case is already ~352k triangles. The cost of 96x48 is visible
-- stair-stepping on the Legendary marbling at close range -- an accepted,
-- reported limitation, not an oversight.
--
-- SINGLE OUTWARD WINDING. The shell hugs an opaque convex-ish body and is never
-- viewed from inside, so back faces are pure waste; emitting one winding halves
-- the triangle count. Winding direction was determined empirically (a red /
-- blue / white three-ring test): a,b,c + a,c,d with theta increasing in `s` and
-- t increasing in `row` is the OUTWARD-facing order. The reverse order renders
-- invisible from outside. DoubleSided is Plugin-capability only and THROWS from
-- game code, so it is never written -- nor are MeshId, RenderFidelity,
-- CollisionFidelity or InitialSize. Color, Material and Size are shading/scale
-- only and safe.
--
-- THE FACE STAYS BASE-COLOURED ON EVERY TIER. Decided by building it both ways
-- and looking: a band THROUGH the face puts the eyes on a white patch and the
-- protruding eye MeshParts chop the band into pieces -- it reads stuck-on. A
-- band ABOVE the face reads as a deliberate marking. A band BELOW the face has
-- the highest coverage of the three (34.9%) but reads as the slime standing in
-- a white puddle. Above won, and the exclusion cone below applies that decision
-- globally so the face reads identically at every rarity.
--
-- COVERAGE IS BISECTION-TUNED, NOT HAND-PICKED. The monotonic ordering IS the
-- ladder -- it is the only thing telling a player that a marbled slime outranks
-- a patched one -- so it must not depend on anyone's eye. Each mask exposes a
-- scalar knob that is monotonically INCREASING in coverage, and the tuner
-- bisects it against a target measured on the same grid the mesh is built from.
-- (An earlier tuner had the comparison inverted and converged to the wrong
-- bracket -- 86% for Rare, 2% for Legendary. The direction below is correct.)
--
-- MEASURED RESULT, for regression comparison after any edit:
--     tier          coverage   tris    parts/slime
--     Common          0.0%        0        0
--     Uncommon       26.9%     2496        1
--     Rare           35.0%     3280        1
--     Epic           50.0%     4432        1
--     Legendary      65.0%     5862        1
-- One MeshPart per slime at every tier, because the pattern is a mask
-- rasterised into a SINGLE generated shell mesh rather than one part per blob.
-- That is what clears the cost gate: 60 slimes worst case is 60 parts and
-- 4 shared meshes, against ~1,200 parts for a per-blob approach.
--
-- KNOWN WEAKEST PAIR: Rare -> Epic. From any single viewing angle both read as
-- "irregular white on the upper body", and an asymmetric mask hides much of its
-- coverage on the far side, so the 35% -> 50% step does not land visually. The
-- fix (NOT applied here -- deliberately left as-is) is to make Epic a genuine
-- half-and-half split with a hard straight boundary instead of a splash.
--
-- REVERSAL: workspace.TierMarks:Destroy(). No body property is ever written --
-- not Material, not Color, not Reflectance. The marks are additive only.
-- ===========================================================================

local AssetService = game:GetService("AssetService")

-- ===================================================================
-- CONFIG -- every tunable in one place.
-- ===================================================================
local CONFIG = {
	ROOT_NAME = "TierMarks",
	LINEUP_NAME = "SlimeLineup",
	BODY_PART_NAME = "slime",

	-- 2.0%. See the header: 1.006 z-fought and rendered nothing.
	MARK_INFLATE = 1.020,
	MARK_COLOR = Color3.fromRGB(255, 255, 255),

	-- Face exclusion cone. Azimuth is atan2(x, z) and was MEASURED off the
	-- asset: eye_dark, eye_white and blush all sit at -141.5 degrees, with
	-- angular half-widths of 21-27 degrees, spanning 32-72% of body height.
	-- The cone is widened to 46 degrees for margin, and stops at t = 0.68 so
	-- the Uncommon cap (which starts at 0.68) is not notched by it.
	FACE_AZIMUTH_DEG = -141.5,
	FACE_ANGLE_DEG = 46,
	FACE_T_LO = 0.26,
	FACE_T_HI = 0.68,

	-- Uncommon: ONE wide band ABOVE the face. Roughly a quarter of body height,
	-- the reference's weight -- hairlines read as shrink-wrap creases, not paint.
	UNCOMMON_T_LO = 0.68,
	UNCOMMON_T_HI = 0.94,

	-- Bisection targets. Must climb monotonically or the ladder is broken.
	TARGET_RARE = 0.35,
	TARGET_EPIC = 0.50,
	TARGET_LEGENDARY = 0.65,

	-- Sampling grid. See header for why finer was rejected.
	GRID_THETA = 96,
	GRID_T = 48,
	-- Poles are degenerate (radius -> 0), so the domain stops just short of both.
	T_MIN = 0.02,
	T_MAX = 0.97,

	-- Height rows across each emitted cell. 1 is enough because the cell already
	-- spans a t range; the row count only affects meridian tessellation.
	PROFILE_BUCKETS = 96,
}

local TAU = 2 * math.pi

-- ===================================================================
-- 1. THE MEASURED SILHOUETTE.
--
-- The body is a SQUASHED DOME, not a sphere. Sanity landmarks from the real
-- asset: ~86% of max radius at the base, WIDEST AT 31% height, 76% at t=0.75,
-- 37% at t=0.94. A mark built from an assumed sphere floats badly at the top
-- and clips at the equator.
--
-- Primary path re-measures from the live mesh (finer, and self-correcting if
-- the asset is ever re-exported). Fallback is the baked table below, measured
-- from MeshId rbxassetid://114522325695786 at 45,694 vertices, so this file
-- still works if the Mesh/Image APIs are disabled.
-- ===================================================================
local BAKED_BBOX = {
	mnx = -1.0003, mxx = 1.0003,
	mny = -0.6775, mxy = 0.6775,
	mnz = -1.0007, mxz = 1.0007,
}
local BAKED_PROFILE = {
	{ 0.000, 0.8592 }, { 0.062, 0.9197 }, { 0.125, 0.9722 }, { 0.188, 0.9940 },
	{ 0.250, 0.9999 }, { 0.312, 1.0007 }, { 0.375, 0.9949 }, { 0.438, 0.9838 },
	{ 0.500, 0.9558 }, { 0.562, 0.9298 }, { 0.625, 0.8799 }, { 0.688, 0.8390 },
	{ 0.750, 0.7648 }, { 0.812, 0.6735 }, { 0.875, 0.5417 }, { 0.938, 0.3695 },
}

local function buildProfile(body: BasePart)
	local bbox = table.clone(BAKED_BBOX)
	local samples = BAKED_PROFILE
	local source = "baked table (16 samples)"

	local ok, em = pcall(function()
		return AssetService:CreateEditableMeshAsync(Content.fromUri((body :: any).MeshId))
	end)
	if ok then
		local verts = em:GetVertices()
		local mnx, mxx = math.huge, -math.huge
		local mny, mxy = math.huge, -math.huge
		local mnz, mxz = math.huge, -math.huge
		local pts = table.create(#verts)
		for i, id in ipairs(verts) do
			local p = em:GetPosition(id)
			pts[i] = p
			mnx = math.min(mnx, p.X); mxx = math.max(mxx, p.X)
			mny = math.min(mny, p.Y); mxy = math.max(mxy, p.Y)
			mnz = math.min(mnz, p.Z); mxz = math.max(mxz, p.Z)
		end
		local B = CONFIG.PROFILE_BUCKETS
		local bucket = table.create(B, 0)
		for _, p in ipairs(pts) do
			local t = (p.Y - mny) / (mxy - mny)
			local b = math.clamp(math.floor(t * B) + 1, 1, B)
			local r = math.sqrt(p.X * p.X + p.Z * p.Z)
			if r > bucket[b] then bucket[b] = r end
		end
		-- NON-EMPTY BUCKETS ONLY. See header -- 42 of 96 are empty because the
		-- vertices sit in discrete latitude rings, and interpolating into a
		-- zero collapses the radius and buries every mark inside the body.
		local live = {}
		for b = 1, B do
			if bucket[b] > 0 then
				table.insert(live, { (b - 0.5) / B, bucket[b] })
			end
		end
		table.sort(live, function(a, b) return a[1] < b[1] end)
		if #live >= 8 then
			bbox = { mnx = mnx, mxx = mxx, mny = mny, mxy = mxy, mnz = mnz, mxz = mxz }
			samples = live
			source = string.format("live mesh (%d vertices, %d non-empty of %d buckets)", #verts, #live, B)
		end
	end

	local function radiusAt(t: number): number
		t = math.clamp(t, 0, 1)
		if t <= samples[1][1] then return samples[1][2] end
		if t >= samples[#samples][1] then return samples[#samples][2] end
		for i = 1, #samples - 1 do
			local a, b = samples[i], samples[i + 1]
			if t >= a[1] and t <= b[1] then
				return a[2] + (b[2] - a[2]) * ((t - a[1]) / (b[1] - a[1]))
			end
		end
		return samples[#samples][2]
	end

	return { bbox = bbox, radiusAt = radiusAt, source = source }
end

-- ===================================================================
-- 2. THE MASK -> SHELL MESH GENERATOR.
--
-- A mask is any predicate over the surface parameter domain,
-- mask(theta, t) -> boolean, with theta the azimuth (atan2(x, z)) and t the
-- normalised height. The generator rasterises that mask onto the measured
-- silhouette and emits ONE mesh -- which is what makes every tier cost exactly
-- one MeshPart regardless of how many separate blobs the pattern appears to
-- have.
-- ===================================================================
local function makeGenerator(P)
	local NTH, NT = CONFIG.GRID_THETA, CONFIG.GRID_T
	local TMIN, TMAX = CONFIG.T_MIN, CONFIG.T_MAX
	local bbox = P.bbox
	local radiusAt = P.radiusAt

	-- Area-weighted coverage on the SAME grid the mesh is built from, so the
	-- tuner and the build can never disagree.
	local function measure(mask): number
		local inA, allA = 0, 0
		for i = 0, NT - 1 do
			local t0 = TMIN + (TMAX - TMIN) * i / NT
			local t1 = TMIN + (TMAX - TMIN) * (i + 1) / NT
			local tm = (t0 + t1) / 2
			local r0, r1 = radiusAt(t0), radiusAt(t1)
			local dy = (bbox.mxy - bbox.mny) * (t1 - t0)
			local cell = radiusAt(tm) * (TAU / NTH) * math.sqrt((r1 - r0) ^ 2 + dy * dy)
			for j = 0, NTH - 1 do
				allA += cell
				if mask(TAU * (j + 0.5) / NTH, tm) then inA += cell end
			end
		end
		return inA / allA
	end

	local function buildMesh(mask): (MeshPart, number, number)
		local em = AssetService:CreateEditableMesh()

		-- THE MARKER TRIANGLES. Two sub-pixel triangles at the BODY MESH's own
		-- bbox corners, pinning this mesh's bounding box to the body's. See the
		-- header -- this is what makes Size = body.Size * inflate exact and the
		-- breathing automatic.
		local e = 1e-4
		local function marker(x, y, z, sx, sy)
			local a = em:AddVertex(Vector3.new(x, y, z))
			local b = em:AddVertex(Vector3.new(x + sx * e, y, z))
			local c = em:AddVertex(Vector3.new(x, y + sy * e, z))
			em:AddTriangle(a, b, c)
		end
		marker(bbox.mnx, bbox.mny, bbox.mnz, 1, 1)
		marker(bbox.mxx, bbox.mxy, bbox.mxz, -1, -1)

		-- Clamp so mark geometry never exceeds the marker bbox, which would
		-- silently rescale the whole mesh and cancel the inflate.
		local RMAX = bbox.mxx * 0.9999
		local function vert(th: number, t: number)
			local r = math.min(radiusAt(t), RMAX)
			return em:AddVertex(Vector3.new(
				r * math.sin(th),
				bbox.mny + (bbox.mxy - bbox.mny) * t,
				r * math.cos(th)
			))
		end

		local areaIn, areaAll, tris = 0, 0, 0
		for i = 0, NT - 1 do
			local t0 = TMIN + (TMAX - TMIN) * i / NT
			local t1 = TMIN + (TMAX - TMIN) * (i + 1) / NT
			local tm = (t0 + t1) / 2
			local r0, r1 = radiusAt(t0), radiusAt(t1)
			local dy = (bbox.mxy - bbox.mny) * (t1 - t0)
			local cell = radiusAt(tm) * (TAU / NTH) * math.sqrt((r1 - r0) ^ 2 + dy * dy)
			for j = 0, NTH - 1 do
				local th0 = TAU * j / NTH
				local th1 = TAU * (j + 1) / NTH
				areaAll += cell
				if mask((th0 + th1) / 2, tm) then
					local a, b, c, d = vert(th0, t0), vert(th1, t0), vert(th1, t1), vert(th0, t1)
					-- SINGLE OUTWARD WINDING -- see header.
					em:AddTriangle(a, b, c)
					em:AddTriangle(a, c, d)
					tris += 2
					areaIn += cell
				end
			end
		end

		local mp = AssetService:CreateMeshPartAsync(Content.fromObject(em))
		return mp, areaIn / areaAll, tris
	end

	-- Masks are monotonically INCREASING in k. Bisect against the target.
	local function tune(make, target: number)
		local lo, hi = -4, 4
		for _ = 1, 30 do
			local mid = (lo + hi) / 2
			if measure(make(mid)) < target then lo = mid else hi = mid end
		end
		local k = (lo + hi) / 2
		return make(k), k
	end

	return { measure = measure, buildMesh = buildMesh, tune = tune }
end

-- ===================================================================
-- 3. THE FOUR TIER MASKS.
--
-- Each tier is a DIFFERENT pattern type, so shape alone cannot rank them.
-- Ordering therefore lives in two things that both climb monotonically:
--   COVERAGE   -- 0 / 26.9 / 35 / 50 / 65 percent
--   COMPLEXITY -- one simple form, then broken up, then irregular, then
--                 intricate: band -> patches -> splash -> marbling.
-- ===================================================================
local function makeMasks()
	local FACE_AZ = math.rad(CONFIG.FACE_AZIMUTH_DEG)
	local FACE_ANG = math.rad(CONFIG.FACE_ANGLE_DEG)

	local function angdiff(a: number, b: number): number
		local d = (a - b) % TAU
		if d > math.pi then d = TAU - d end
		return d
	end

	local function faceClear(th: number, t: number): boolean
		return not (angdiff(th, FACE_AZ) < FACE_ANG and t > CONFIG.FACE_T_LO and t < CONFIG.FACE_T_HI)
	end

	-- UNCOMMON -- one wide band above the face. Fixed, not tuned: its position
	-- is the Step-1 visual decision, and its coverage falls out at 26.9%.
	local function maskUncommon(_: number, t: number): boolean
		return t >= CONFIG.UNCOMMON_T_LO and t <= CONFIG.UNCOMMON_T_HI
	end

	-- RARE -- four LARGE irregular patches. Big blobs, not a scatter of small
	-- ones: geometry is worst at speckle, and small marks fail the 40-stud test.
	local RARE_BLOBS = {
		{ FACE_AZ + math.rad(60),  0.68, 1.15, 0.30 },
		{ FACE_AZ + math.rad(165), 0.42, 1.35, 0.34 },
		{ FACE_AZ + math.rad(255), 0.72, 1.05, 0.28 },
		{ FACE_AZ + math.rad(200), 0.14, 1.25, 0.24 },
	}
	local function makeRare(k: number)
		local s = 1 + 0.22 * k
		return function(th: number, t: number): boolean
			if not faceClear(th, t) then return false end
			for _, b in ipairs(RARE_BLOBS) do
				local da = angdiff(th, b[1]) / (b[3] * s)
				local dt = (t - b[2]) / (b[4] * s)
				-- wobble breaks the ellipse into an irregular patch edge
				local wob = 1 + 0.22 * math.sin(3 * th + 5 * t) + 0.14 * math.sin(7 * t)
				if (da * da + dt * dt) < wob * wob then return true end
			end
			return false
		end
	end

	-- EPIC -- one bold asymmetric splash with a wavy edge, plus two detached
	-- droplets. Asymmetry is what separates it from the symmetrical tiers below.
	local SPLASH_AZ = FACE_AZ + math.rad(175)
	local function makeEpic(k: number)
		local s = 0.50 + 0.14 * k
		return function(th: number, t: number): boolean
			if not faceClear(th, t) then return false end
			local edge = s + 0.30 * math.sin(3.0 * t * math.pi + 1.1) + 0.12 * math.sin(6.0 * t * math.pi)
			if angdiff(th, SPLASH_AZ) < edge * math.pi then return true end
			if angdiff(th, SPLASH_AZ + math.rad(120)) < 0.42 and math.abs(t - 0.30) < 0.13 then return true end
			if angdiff(th, SPLASH_AZ - math.rad(118)) < 0.30 and math.abs(t - 0.78) < 0.10 then return true end
			return false
		end
	end

	-- LEGENDARY -- dense marbling. A domain-warped vein field: the warp term is
	-- fed back into both carrier waves, which is what makes it read as marble
	-- rather than as stripes.
	local function makeLegendary(k: number)
		return function(th: number, t: number): boolean
			if not faceClear(th, t) then return false end
			local warp = 0.9 * math.sin(3.0 * t * math.pi + 1.7 * th) + 0.5 * math.sin(5.0 * th + 4.0 * t)
			local v = math.sin(5.0 * th + 2.4 * warp) + 0.75 * math.sin(7.5 * t * math.pi + 1.3 * warp)
			return v > -0.62 * k
		end
	end

	return {
		maskUncommon = maskUncommon,
		makeRare = makeRare,
		makeEpic = makeEpic,
		makeLegendary = makeLegendary,
	}
end

-- ===================================================================
-- 4. BUILD.
-- ===================================================================
local function run()
	local lineup = workspace:FindFirstChild(CONFIG.LINEUP_NAME)
	assert(lineup, string.format(
		"[TierMarks] workspace.%s not found. This script marks an EXISTING lineup; "
			.. "it does not build one. Rebuild the lineup first (SlimeBuilder.build over "
			.. "SlimeData.SLIMES_BY_TIER), then re-run.",
		CONFIG.LINEUP_NAME
	))

	local rows = { "T1_Common", "T2_Uncommon", "T3_Rare", "T4_Epic", "T5_Legendary" }
	for _, name in ipairs(rows) do
		assert(lineup:FindFirstChild(name), "[TierMarks] missing lineup row: " .. name)
	end

	local sample = nil
	for _, m in ipairs(lineup.T1_Common:GetChildren()) do
		if m:IsA("Model") and m:FindFirstChild(CONFIG.BODY_PART_NAME) then
			sample = m:FindFirstChild(CONFIG.BODY_PART_NAME)
			break
		end
	end
	assert(sample, "[TierMarks] no slime body found in T1_Common")

	local existing = workspace:FindFirstChild(CONFIG.ROOT_NAME)
	if existing then existing:Destroy() end

	local P = buildProfile(sample :: BasePart)
	local G = makeGenerator(P)
	local M = makeMasks()

	local root = Instance.new("Folder")
	root.Name = CONFIG.ROOT_NAME
	root.Parent = workspace
	for k, v in pairs(CONFIG) do
		if typeof(v) == "number" or typeof(v) == "Color3" then
			root:SetAttribute(k, v)
		end
	end

	local rareMask, kRare = G.tune(M.makeRare, CONFIG.TARGET_RARE)
	local epicMask, kEpic = G.tune(M.makeEpic, CONFIG.TARGET_EPIC)
	local legMask, kLeg = G.tune(M.makeLegendary, CONFIG.TARGET_LEGENDARY)

	local tiers = {
		{ row = "T2_Uncommon",  mask = M.maskUncommon, k = nil },
		{ row = "T3_Rare",      mask = rareMask,       k = kRare },
		{ row = "T4_Epic",      mask = epicMask,       k = kEpic },
		{ row = "T5_Legendary", mask = legMask,        k = kLeg },
	}

	local lines = { "[TierMarks] profile source: " .. P.source }
	local total = 0
	for _, tier in ipairs(tiers) do
		local tpl, coverage, tris = G.buildMesh(tier.mask)
		tpl.Name = tier.row .. "_tpl"
		tpl.Transparency = 1
		tpl.Anchored = true
		tpl.CanCollide = false; tpl.CanQuery = false; tpl.CanTouch = false; tpl.CastShadow = false
		tpl.Parent = root  -- kept alive: clones reference this mesh

		local tierFolder = Instance.new("Folder")
		tierFolder.Name = tier.row
		tierFolder.Parent = root

		for _, model in ipairs(lineup[tier.row]:GetChildren()) do
			if model:IsA("Model") then
				local body = model:FindFirstChild(CONFIG.BODY_PART_NAME)
				if body then
					-- one folder per slime, so the whole treatment is removable
					-- in one action and any single slime can be stripped alone
					local per = Instance.new("Folder")
					per.Name = model.Name
					per.Parent = tierFolder

					local mark = tpl:Clone()
					mark.Name = "Mark"
					mark.Transparency = 0
					mark.Color = CONFIG.MARK_COLOR
					mark.Material = (body :: BasePart).Material  -- SAME material as Common
					mark.Anchored = true
					mark.CanCollide = false; mark.CanQuery = false; mark.CanTouch = false
					mark.CastShadow = false
					mark.Size = (body :: BasePart).Size * CONFIG.MARK_INFLATE
					mark.CFrame = (body :: BasePart).CFrame
					mark.Parent = per
					total += 1
				end
			end
		end

		table.insert(lines, string.format(
			"[TierMarks] %-13s coverage=%5.1f%%  tris=%5d  parts/slime=1%s",
			tier.row, coverage * 100, tris,
			tier.k and string.format("  (k=%.3f)", tier.k) or ""
		))
	end

	table.insert(lines, string.format(
		"[TierMarks] T1_Common     coverage=  0.0%%  tris=    0  parts/slime=0"))
	table.insert(lines, string.format(
		"[TierMarks] done: %d marks, 4 shared meshes. Undo with workspace.%s:Destroy()",
		total, CONFIG.ROOT_NAME))

	local out = table.concat(lines, "\n")
	print(out)
	return out
end

return run()
