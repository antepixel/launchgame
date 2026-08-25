--!strict
-- BUILD_LEGENDARY.luau -- CANDIDATES FOR THE TOP RUNG, BUILT AS GEOMETRY.
--
-- Paste the whole file into the Studio command bar and it builds
-- workspace.LegendaryLab from nothing: one cell per candidate, each on its own
-- ground, at the framing the game actually uses. No other file needs to be
-- present.
--
-- NOT SHIPPING CODE and deliberately NOT under src/ (Rojo syncs that). Same
-- standing as BUILD_SKINS, BUILD_TIERMARKS and BUILD_DIVINE beside it.
--
-- ======================= WHY THIS IS NOT A TEXTURE =========================
--
-- THE LADDER BELOW IT IS SETTLED AND IT IS ALL PAINT: bare, blaze, stripes4 at
-- twist 140, dots24. Four rungs of white-on-hue marking, each a shape on the
-- body's own surface. Legendary has to be a MEDIUM CHANGE or it is a fifth
-- pattern, and a fifth pattern reads as "another one of those" no matter how
-- loud it is. That was already written down when mane was dropped: "Legendary
-- stops being a shape and becomes an image."
--
-- AND THE TWO ATTEMPTS SINCE THEN BOTH DIED OF THE SAME THING, from opposite
-- directions. Fire died five times because a thresholded noise field has no
-- lateral contrast and never produces a countable tongue -- and when tongues
-- were finally PLACED rather than thresholded, they still had to be painted,
-- and paint on the body cannot change what the body IS. The glow shell died on
-- the rainbow road: a translucent Neon ring is a COLOUR AGAINST A BACKGROUND,
-- it measured 0.487 against grass and 0.000 against a road band of its own
-- colour, and RunwayBuilder paints that road Color3.fromHSV(i % 5 / 5, 1, 1) --
-- every hue, fully saturated, cycling every 200 studs. There is no shell colour
-- that dodges it.
--
-- SO THE THING THAT IS NEITHER, AND THIS IS THE WHOLE ARGUMENT OF THE FILE:
--
--     a texture is a colour against the BODY
--     a glow is a colour against the BACKGROUND
--     a change to the SILHOUETTE, in the body's own colour, is neither
--
-- The body already reads against every backdrop in this game -- it is opaque,
-- it is lit, and it has to, or there would be no game. Geometry that is the
-- same colour and the same material as the body INHERITS that. It cannot lose
-- to a backdrop it matches, because the body doesn't. It cannot be mistaken for
-- lighting, because a light does not add mass. And it cannot be confused with
-- another marking, because it is not on the surface at all.
--
-- That is a derivation from the measurements rather than a taste call, and it
-- is why every candidate here is geometry and every one is body-coloured.
--
-- ========================= WHAT IT HAS TO CLEAR ============================
--
-- THE TWO REAL FRAMINGS, neither of which is the pattern lab's:
--     base    7 studs wide on an 8 x 0.6 x 8 pad, player camera, ~16 studs.
--             25.1 px per stud, so the body is 88 px across the flank.
--     reveal  16 studs wide, box camera at 34 studs, pitch 0.
--             11.8 px per stud, body 95 px, and the horizon cuts it in HALF.
-- Anything that only works at the lab's 14-studs-at-40 is not an answer.
--
-- ALL SIX HUES. Every failure that got far in this project was blue-only.
-- Body-coloured geometry is hue-independent by construction, which is most of
-- the reason to reach for it, but the TONE that separates the addition from the
-- body is not: a light tip vanishes on yellow. That is the thing to check.
--
-- DECISIVELY BOLDER THAN dots24, which is a 24-dot field at 28% coverage.
--
-- AND IT STILL HAS TO READ AS ITS COLOUR, which is the constraint that kills
-- the easy answers -- gold, prismatic, a white crown. The addition is the
-- body's hue, shaded, and nothing here changes what colour the slime is.
--
-- ============================ HOW IT IS BUILT ==============================
--
-- ONE MESH PER CANDIDATE, SHARED BY EVERY SLIME. Each direction emits a single
-- EditableMesh containing all of its geometry, which becomes one MeshPart,
-- which is Cloned per slime -- 60 parts and ONE mesh, the cost profile
-- BUILD_TIERMARKS established and the glow shell repeated. Nothing here is one
-- part per spike; that would be ~500 parts at 60 slimes and it would not ship.
--
-- THE CONSTELLATION IS RIGID SO IT CAN BE ONE MESH. Six droplets orbiting
-- independently need six parts. Six droplets holding station relative to each
-- other while the whole ring turns need one, and look the same. Where a
-- direction wants motion it gets it by moving the PART -- see MOTION below.
--
-- MARKERS PIN THE BOX TO A KNOWN MULTIPLE OF THE BODY'S. BUILD_TIERMARKS' trick,
-- with the one change this file needs: its marks hug the body so its markers
-- sit on the body's own bbox, but a spike sticks OUT, and geometry that exceeds
-- the marker box silently rescales the whole mesh. So the markers go at
-- EXTENT x the body's half-extents and the part is sized to match. Anything
-- that would reach past EXTENT is clamped and counted, and the count is printed.
--
-- WINDING IS COMPUTED, NOT REMEMBERED. BUILD_TIERMARKS determined its outward
-- winding empirically with a three-ring colour test, which is fine for one
-- fixed grid and useless here -- these shapes point in every direction. Every
-- triangle is emitted through triOut(), which takes a reference point known to
-- be INSIDE the solid, computes (b-a) x (c-a), and swaps two corners if the
-- normal points the wrong way. A back-facing triangle is invisible from
-- outside, so getting this wrong looks like missing geometry rather than an
-- error, which is exactly the kind of failure worth removing by construction.
--
-- FLAT SHADING IS THE DEFAULT AND IS DELIBERATE. Every triangle gets its own
-- three vertices, so Roblox computes per-face normals and the geometry reads
-- faceted. On a crystal that is the look; on a droplet at 15 px it is invisible.
--
-- VERTEX COLOUR CARRIES THE TONE, so a shape can shade along its length with no
-- texture and no second part. It MULTIPLIES the part's Color, which is exactly
-- why the first pass came out grey: lifting the hue 34% toward white and then
-- multiplying it back down by 0.72 does not return the hue, it returns a
-- DESATURATED version of it, because the white that was added gets scaled too.
-- Blue (60,120,240) went to (91,120,176) at the root -- a slate, not a blue --
-- and every candidate read as a different material bolted to the slime.
--     So the range is narrow now and it stays near 1. LIFT is 0.12 and shades
-- run 0.86..1.00, which is a tone difference the lighting can work with while
-- the addition is unmistakably the same colour as the body. The renderer
-- already shades these by normal; vertex colour is for gradients ALONG a shape,
-- not for making it visible.

-- SMOOTH OR FACETED IS A PER-CANDIDATE CHOICE, and the first pass got it wrong
-- by not having one. Every triangle owning its own three vertices gives
-- per-face normals, which is right for a crystal and wrong for a droplet: the
-- orbiting balls came out visibly checkered, because a UV sphere split into
-- triangles flat-shades into alternating facets. `smooth` deduplicates vertices
-- by position so Roblox averages the normals across them.
--
-- ============================== MOTION =====================================
--
-- NOTHING BELOW DIVINE MOVES, so motion is the one axis that cannot be mistaken
-- for a louder shape -- and it is the only axis that is genuinely independent of
-- the backdrop, because the eye detects change over time without needing
-- contrast to do it. Candidates that want it declare `spin` (radians per second
-- about the body's own axis) and `bob` (studs, on the idle breath's period).
-- The lab poses them statically at PHASE so rebuilds are comparable, exactly as
-- BUILD_DIVINE pins its pose; SHOOT_PHASES builds the same candidate at several
-- phases side by side so a still can show what a still cannot.
--
--
-- ====================== WHAT WHITE IS DOING HERE =========================
--
-- BODY-COLOURED GEOMETRY ALONE IS NOT BOLDER THAN dots24, and that is a
-- measurement rather than an opinion. LADDER_REF exists because it could not
-- be settled any other way: it builds a real dots24 slime -- the same
-- EditableImage, lifted off EXPLORE_PATTERNS' own output rather than
-- reimplemented -- at 7 studs, on the same pad, on the same grass, under the
-- same camera. Put beside it, a blue slime with a blue plume changes the
-- OUTLINE decisively and loses on sheer loudness anyway, because white on hue
-- is a bigger local contrast than any amount of hue on hue. The tier below
-- would have out-shouted the tier above.
--
-- AND THE ANSWER IS BOTH, WHICH IS WHY regalia EXISTS. plume's claim on the top
-- rung is a change of KIND -- it is the only slime in the ladder that is not a
-- ball -- and that is a real claim, but on the ladder's own axis, white AREA,
-- it does not beat dots24. A rung that loses to the rung below on the measure
-- the ladder is ordered by is a rung worth testing twice. regalia is the plume
-- with the crown's ring around its foot: five white-capped drops plus three
-- beads, so the top rung wins on kind AND on area, and it stops being a
-- question anyone has to argue about.
--
-- SO THE GEOMETRY CARRIES THE LADDER'S OWN ACCENT. Not a new colour, not gold,
-- not a material change: the same (252, 251, 247) every rung below is built
-- from, on the geometry instead of on the surface. The slime still reads as
-- its hue -- the body is untouched and the addition is mostly hue -- and the
-- rung reads as the last step of the same ladder rather than a different game.
--
-- AND VERTEX COLOUR IS WHAT MAKES THAT FREE. It multiplies Color, so a
-- hue-coloured part can only ever be darkened, which is why three rounds of
-- this could not put white anywhere. Set the part to WHITE and the multiply is
-- an identity: one part carries the hue AND the accent, with no texture, no
-- UVs and no second instance. The price is a mesh per hue rather than one --
-- six instead of one, which is the shape TierMarks already ships and costs
-- nothing that matters.
--
-- WHITE HAS TO ARRIVE AT AN EDGE, NOT ALONG A GRADIENT, and this is the
-- terminator rule arriving in geometry with no warning that it would. A drop
-- graded from hue at the root to white at the tip renders as SHEEN: the
-- boundary runs along the same axis the light's own falloff runs, so the eye
-- takes the cheaper explanation and sees a lit drop rather than a white-tipped
-- one. Measured on the plume, the crest went 93,148,255 -> 220,237,255 and
-- still read as a highlight. The three BEADS read as white from the first
-- frame, because a bead is a discrete object with an edge no light can draw.
-- Every accent here is therefore a separate element or a hard step, never a
-- ramp. Same rule that killed countershade, three years of representation away.
--
-- ===================== WHAT THE SHAPE HAS TO BE ==========================
--
-- A CONE IS THE WRONG SHAPE EVEN WHEN THE COLOUR IS RIGHT. The crown was built
-- first from straight tapered cones with a hard white cap, and it read -- to
-- the frame, unmistakably -- as a ring of SHARPENED PENCILS. Moving the cap
-- from 0.62 to 0.80 of the length did nothing, because the cap was never the
-- tell: a straight taper on a circular base is a manufactured object and the
-- slime is not one. Rebuilt from the same drop profile the plume uses, the
-- identical arrangement reads as soft horns. THE ADDITION HAS TO BE MADE OF
-- THE SAME STUFF AS THE THING, and "stuff" here is the profile, not the
-- colour, which the colour work above had already established and this
-- re-established one level down.
--
-- A DROP READS AS A DROP BY ITS ASPECT. At 1.10R long and 0.325R fat the plume
-- was a SPIRE and the slime stopped being liquid; at 0.84R and 0.355R it was a
-- drop. `peak` then tested going further -- 0.545R fat, sunk 0.30R rather than
-- 0.12R -- and won on both counts, so the two were merged rather than shipped
-- as a pair. A base wider than the dome's local radius is what removes the
-- ledge where an addition meets a body: below that it sits ON the crown, above
-- it the crown IS drawn up.
--
-- ========================= WHAT THE RENDER SAYS ===========================
--
-- ALL SIX HUES, at the base framing, and this is the constraint every earlier
-- failure in this project was hiding from. Body-coloured geometry is
-- hue-independent by construction; the accent is not, and yellow is the case
-- to watch because a white bead on a 245,215,55 body has the least to work
-- with. It holds -- the beads separate on all six, because they are discrete
-- objects with their own shading and not a tonal difference.
--
-- THE ACCENT'S HUE-DEPENDENCE IS THE LADDER'S OWN, NOT A NEW ONE. Measured on
-- regalia by classifying the render rather than sampling guessed coordinates --
-- the caps are the only low-saturation high-value pixels on the subject:
--     hue      white cap against body     rgb     lum
--     red                                0.926   0.541
--     green                              0.856   0.290
--     orange                             0.791   0.335
--     blue                               0.789   0.462
--     purple                             0.689   0.498
--     yellow                             0.679   0.176
-- Yellow is last, which is exactly where flat white-on-yellow lands in the
-- texture ladder too: (252,251,247) on (245,215,55) computes to rgb 0.766 and
-- lum 0.161, against the geometry's measured 0.679 and 0.176. The top rung is
-- no more hue-sensitive than the four below it, and for the same reason -- it
-- is the same accent.
--
-- AND IT SURVIVES THE REVEAL, WHICH IS WHAT THE GLOW SHELL COULD NOT DO.
-- Same 16-stud slime, same box camera at 34 studs and pitch 0, same fully
-- saturated road underneath. Contrast of the addition against what is actually
-- behind it:
--     plume, the drop against sky          rgb 0.687   lum 0.436
--     crown, a horn against sky            rgb 0.487   lum 0.329
--     the glow shell's ring against sky    rgb 0.206   lum 0.008
--     the glow shell over a matching band  rgb 0.000   lum 0.000
--     a white marking on a blue body       rgb 0.912   lum 0.530
-- Three times the shell's rgb separation and fifty times its luminance, and it
-- sits nearer a painted marking than a glow.
--
-- THE ROAD NEVER GETS A SHOT AT IT, and that falls out of the silhouette rule
-- rather than being designed for. The usable space is UP; the reveal camera is
-- level through the slime's middle, so the horizon cuts the body in half and
-- everything above it is sky. The addition is always against sky and the body
-- is always against the road -- and the body is opaque and lit, so it reads
-- there anyway. The failure that killed the shell cannot reach a treatment
-- that lives above the horizon.
--
-- ============================== COST ======================================
--
--     candidate   tris   x60 slimes   meshes
--     regalia     2617       157k        6 (one per hue)
--     crown       2436       146k        6
--     plume       1242        75k        6
--     antennae     824        49k        6
-- against TierMarks' accepted 352k and the glow shell's 924k for a cloned
-- body. One MeshPart per slime in every case, which is the budget that was
-- accepted; six meshes rather than one is the price of vertex colour carrying
-- the hue, and mesh count was never what the gate was on.
--
-- WHAT SHIPPING IT NEEDS, which this file deliberately does not do:
-- SlimeBuilder.build(color, widthStuds) clones the template and ScaleTo's it,
-- so a Legendary slime needs the part added and sized against the body it
-- ends up with, not against the template. The animator is one CFrame write per
-- part per frame and must read the body's CFrame live rather than caching a
-- rest pose -- SlimeIdleClient owns that body and moves it every frame, and
-- two writers to one transform is the hazard BUILD_DIVINE's driveBody flag
-- exists to avoid.
-- ===========================================================================
--
-- REVERSAL: workspace.LegendaryLab:Destroy().
-- ===========================================================================

local AssetService = game:GetService("AssetService")

local P = {
	ROOT_NAME = "LegendaryLab",
	SOURCE_MODELS = { "Slime", "AuxScene", "slime_uv" },

	-- Which candidates, by name, in this order. Empty builds every LIVE one.
	ONLY = {},
	-- Include the cut directions too. They are kept as code rather than only as
	-- prose because a reason you cannot rebuild is a reason nobody can check --
	-- and because every one of them was judged before the tone and sphere bugs
	-- were found, so the shots that killed them are not shots of what they
	-- would look like now. Rebuilt, coronet and halo look materially better;
	-- both are still cut, and the reason is written on each one.
	SHOW_DEAD = false,
	-- BUILD THE RUNG BELOW AS A REFERENCE CELL, at the same size, on the same
	-- ground, under the same camera. "Decisively bolder than dots24" is not a
	-- judgement anyone can make from two screenshots taken at different scales
	-- on different days, and this is the only honest way to ask it. Requires
	-- EXPLORE_PATTERNS to have been run with ONLY = { "dots24" } first; the
	-- texture is lifted off that slime rather than re-derived here, so it is
	-- the SAME image and not a second implementation of it. Name as many rungs
	-- as you want in front of the candidates; the whole ladder in one frame is
	-- the only way to see whether the top of it is actually the top.
	LADDER_REF = {},
	-- Which hues. Empty builds just the first.
	HUES_ONLY = { "blue" },
	-- "base" (7 studs on a pad, on grass) or "reveal" (16 studs, over the road)
	FRAMING = "base",
	-- Build one candidate at these phases of its own motion instead of the
	-- whole set -- a strip that shows what a still cannot. Empty = off.
	SHOOT_PHASES = {},
	PHASE_OF = "",

	-- one cell per subject, far enough apart that nothing else is ever in frame
	CELL_SPACING = 400,
	CELL_Z = -1600,

	-- THE TWO REAL FRAMINGS. Both are read by the aim helper at the bottom.
	BASE_WIDTH_STUDS = 7,
	BASE_EYE_Y = 5.0,
	BASE_DISTANCE = 16,
	REVEAL_WIDTH_STUDS = 16,
	REVEAL_Y = 40,
	REVEAL_DISTANCE = 34,
	FOV_DEG = 70,

	BODY_YAW_DEG = 179.4,
	BODY_MATERIAL = Enum.Material.Plastic,

	-- How far past the body's own box the generated mesh may reach, PER AXIS.
	-- Uniform was tried and is wrong: the body is 1.48x wider than tall, so a
	-- single multiplier that gives a crown enough headroom gives an orbiting
	-- ring far more width than it needs, and one that fits the ring clipped the
	-- antennae -- 936 vertices silently flattened onto the box. The clamp
	-- counts and prints, which is how that was caught rather than shipped.
	EXTENT_XZ = 1.8,
	EXTENT_Y = 2.7,
	-- the addition's colour: the hue lifted this far toward white. Small on
	-- purpose -- see VERTEX COLOUR above for what a big one did.
	LIFT = 0.12,
	-- THE LADDER'S OWN ACCENT, copied from BUILD_SKINS rather than re-picked.
	-- Every rung below Legendary is white-on-hue; a top rung that drops white
	-- entirely does not read as the same ladder's last step, and measured
	-- against a real dots24 slime at the same size it did not read as bolder
	-- either -- see WHAT WHITE IS DOING HERE.
	ACCENT = Color3.fromRGB(252, 251, 247),
	PHASE = 0.25,
	-- emit the animator so the lab actually moves; the static pose above is
	-- still what a screenshot sees
	ANIMATE = true,

	HUES = {
		{ "blue", Color3.fromRGB(60, 120, 240) },
		{ "green", Color3.fromRGB(70, 200, 80) },
		{ "red", Color3.fromRGB(225, 60, 60) },
		{ "yellow", Color3.fromRGB(245, 215, 55) },
		{ "purple", Color3.fromRGB(165, 80, 220) },
		{ "orange", Color3.fromRGB(250, 140, 40) },
	},

	-- ground, from the game's own config
	GRASS = Color3.fromRGB(104, 198, 78),
	PAD = Color3.fromRGB(182, 182, 188),
	BAND_COUNT = 24,
	BAND_LENGTH = 40,

	YIELD_MS = 12,
}

-- face parts, measured off a lineup slime; offsets are in body-local space,
-- in the mesh's own units (the same frame the generated geometry uses)
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
local FACE_REL = FACE_PARTS[1].rel.Position
local FWD = Vector3.new(FACE_REL.X, 0, FACE_REL.Z).Unit

local TAU = 2 * math.pi

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
-- THE MEASURED SILHOUETTE, and the ray march that puts geometry ON it.
--
-- Same 96-band profile BUILD_TIERMARKS and the dot field use, including the
-- empty-bucket rule: this mesh fills 54 of 96 bands, and interpolating into
-- the 42 empty ones collapses the radius to about a quarter of true. Over
-- there that buried every mark inside the body across two invisible builds.
-- Here it would plant a crown of spikes inside the slime.
--
-- ATTACHMENT IS A RAY MARCH, NOT A FORMULA. A spike needs the point where a ray
-- from the body's centre leaves the surface, and the surface is a measured
-- profile rather than anything with a closed form. Marching outward in small
-- steps and taking the crossing is exact enough at these sizes and cannot go
-- wrong the way an inverted formula can.
-- ===================================================================
local PROFILE: { { number } } = {}
local PY0, PY1, PRAD = -0.6775, 0.6775, 1.0

local function radiusAt(t: number): number
	local sm = PROFILE
	t = math.clamp(t, 0, 1)
	if t <= sm[1][1] then return sm[1][2] end
	if t >= sm[#sm][1] then return sm[#sm][2] end
	for i = 1, #sm - 1 do
		local a, b = sm[i], sm[i + 1]
		if t >= a[1] and t <= b[1] then
			return a[2] + (b[2] - a[2]) * ((t - a[1]) / (b[1] - a[1]))
		end
	end
	return sm[#sm][2]
end

-- is a point (mesh units, centred) inside the surface of revolution?
local function inside(p: Vector3): boolean
	local t = (p.Y - PY0) / math.max(PY1 - PY0, 1e-9)
	if t < 0 or t > 1 then return false end
	local r = math.sqrt(p.X * p.X + p.Z * p.Z)
	return r <= radiusAt(t) * PRAD
end

-- where a ray from the centre leaves the body
local function surfacePoint(dir: Vector3): Vector3
	local d = dir.Unit
	local lo, hi = 0.0, 0.05
	while inside(d * hi) and hi < 4 do hi += 0.05 end
	for _ = 1, 24 do
		local mid = (lo + hi) / 2
		if inside(d * mid) then lo = mid else hi = mid end
	end
	return d * ((lo + hi) / 2)
end

-- ===================================================================
-- THE EMITTER.
--
-- Positions in, triangles out, winding fixed by construction -- see WINDING IS
-- COMPUTED in the header. `ref` is any point known to be inside the solid the
-- triangle belongs to; the normal is flipped to face away from it.
--
-- Shades are a scalar 0..1 multiplied into the part's Color, cached by
-- quantised value so a 600-triangle mesh does not allocate 1800 colours.
-- ===================================================================
local function newEmitter(box, exz: number, ey: number, smooth: boolean)
	local em = AssetService:CreateEditableMesh()
	local e = 1e-4
	local function marker(x, y, z, sx, sy)
		local a = em:AddVertex(Vector3.new(x, y, z))
		local b = em:AddVertex(Vector3.new(x + sx * e, y, z))
		local c = em:AddVertex(Vector3.new(x, y + sy * e, z))
		em:AddTriangle(a, b, c)
	end
	local hx, hy, hz = box.hx * exz, box.hy * ey, box.hz * exz
	marker(-hx, -hy, -hz, 1, 1)
	marker(hx, hy, hz, -1, -1)

	local tris, clamped = 0, 0
	local colourCache = {}
	local function shadeId(c: Color3): number
		local q = string.format("%d/%d/%d",
			math.floor(c.R * 96 + 0.5), math.floor(c.G * 96 + 0.5), math.floor(c.B * 96 + 0.5))
		local id = colourCache[q]
		if not id then id = em:AddColor(c, 1) colourCache[q] = id end
		return id
	end

	-- SHARED VERTICES MEAN SMOOTH NORMALS. Roblox averages across whatever
	-- vertices a face references, so deduplicating by position is the whole of
	-- smooth shading; leaving them separate is the whole of flat shading.
	local vcache = {}
	local function vid(p: Vector3): number
		if not smooth then return em:AddVertex(p) end
		local k = string.format("%.4f/%.4f/%.4f", p.X, p.Y, p.Z)
		local id = vcache[k]
		if not id then id = em:AddVertex(p) vcache[k] = id end
		return id
	end

	local function clampIn(p: Vector3): Vector3
		local cx = math.clamp(p.X, -hx, hx)
		local cy = math.clamp(p.Y, -hy, hy)
		local cz = math.clamp(p.Z, -hz, hz)
		if cx ~= p.X or cy ~= p.Y or cz ~= p.Z then clamped += 1 end
		return Vector3.new(cx, cy, cz)
	end

	local function triOut(pa: Vector3, pb: Vector3, pc: Vector3, ref: Vector3,
		sa: Color3?, sb: Color3?, sc: Color3?)
		pa, pb, pc = clampIn(pa), clampIn(pb), clampIn(pc)
		local n = (pb - pa):Cross(pc - pa)
		local outward = ((pa + pb + pc) / 3) - ref
		if n:Dot(outward) < 0 then
			pb, pc = pc, pb
			sb, sc = sc, sb
		end
		local f = em:AddTriangle(vid(pa), vid(pb), vid(pc))
		if sa then
			em:SetFaceColors(f, { shadeId(sa), shadeId(sb :: Color3), shadeId(sc :: Color3) })
		end
		tris += 1
	end

	return {
		em = em, triOut = triOut,
		count = function() return tris end,
		clamped = function() return clamped end,
	}
end

-- an orthonormal frame with `axis` as its third vector
local function frameFor(axis: Vector3): (Vector3, Vector3, Vector3)
	local a = axis.Unit
	local up = math.abs(a.Y) > 0.95 and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
	local u = up:Cross(a).Unit
	return u, a:Cross(u).Unit, a
end

-- ---- a tapered spike: ring at the base, ring (or point) at the tip ----
local function emitSpike(E, base: Vector3, axis: Vector3, r0: number, r1: number,
	len: number, segs: number, s0: Color3, s1: Color3, hard: number?)
	local u, v, a = frameFor(axis)
	local tip = base + a * len
	local ref = base - a * (len * 0.5)
	local function ring(centre, r)
		local pts = table.create(segs)
		for i = 0, segs - 1 do
			local th = TAU * i / segs
			pts[i + 1] = centre + u * (math.cos(th) * r) + v * (math.sin(th) * r)
		end
		return pts
	end
	local lo, hi = ring(base, r0), ring(tip, r1)
	-- A HARD BREAK, NOT A RAMP, and this is the terminator rule arriving in
	-- geometry. White graded up a smooth form reads as SHEEN: the boundary runs
	-- along the same axis the light's own falloff does, so the eye takes the
	-- cheaper explanation and sees a lit drop rather than a white-tipped one.
	-- The beads read as white from the first frame because they are discrete
	-- objects with an edge a light cannot draw. So the cap gets an edge too:
	-- `hard` is the fraction up the spike where the colour changes, and the two
	-- bands are each a flat colour with a real boundary between them.
	local c0, c1 = s0, s1
	if hard then
		local mid = ring(base + (tip - base) * hard, r0 + (r1 - r0) * hard)
		for i = 1, segs do
			local j = i % segs + 1
			E.triOut(lo[i], lo[j], mid[j], ref, c0, c0, c0)
			E.triOut(lo[i], mid[j], mid[i], ref, c0, c0, c0)
			E.triOut(mid[i], mid[j], hi[j], ref, c1, c1, c1)
			E.triOut(mid[i], hi[j], hi[i], ref, c1, c1, c1)
		end
	else
		for i = 1, segs do
			local j = i % segs + 1
			E.triOut(lo[i], lo[j], hi[j], ref, c0, c0, c1)
			E.triOut(lo[i], hi[j], hi[i], ref, c0, c1, c1)
		end
	end
	-- cap the tip so a wide-tipped spike is not hollow
	if r1 > 1e-4 then
		for i = 2, segs - 1 do
			E.triOut(hi[1], hi[i], hi[i + 1], ref, c1, c1, c1)
		end
	end
end

-- ---- a swept tube along a polyline, radius per station ----
local function emitTube(E, pts: { Vector3 }, radii: { number }, segs: number,
	shades: { Color3 })
	local rings = {}
	for k, c in ipairs(pts) do
		local dir
		if k == 1 then dir = (pts[2] - pts[1])
		elseif k == #pts then dir = (pts[#pts] - pts[#pts - 1])
		else dir = (pts[k + 1] - pts[k - 1]) end
		local u, v = frameFor(dir)
		local ring = table.create(segs)
		for i = 0, segs - 1 do
			local th = TAU * i / segs
			ring[i + 1] = c + u * (math.cos(th) * radii[k]) + v * (math.sin(th) * radii[k])
		end
		rings[k] = ring
	end
	for k = 1, #rings - 1 do
		local ref = (pts[k] + pts[k + 1]) / 2
		for i = 1, segs do
			local j = i % segs + 1
			E.triOut(rings[k][i], rings[k][j], rings[k + 1][j], ref,
				shades[k], shades[k], shades[k + 1])
			E.triOut(rings[k][i], rings[k + 1][j], rings[k + 1][i], ref,
				shades[k], shades[k + 1], shades[k + 1])
		end
	end
end

-- ---- a flat angular plate: a quad given thickness ----
local function emitPlate(E, centre: Vector3, normal: Vector3, along: Vector3,
	halfLen: number, halfWid: number, thick: number, tipPinch: number,
	sBase: Color3, sTip: Color3)
	local n = normal.Unit
	local a = (along - n * along:Dot(n)).Unit
	local w = n:Cross(a).Unit
	local corners = {
		{ centre - a * halfLen - w * halfWid, sBase },
		{ centre - a * halfLen + w * halfWid, sBase },
		{ centre + a * halfLen + w * (halfWid * tipPinch), sTip },
		{ centre + a * halfLen - w * (halfWid * tipPinch), sTip },
	}
	local front, back = {}, {}
	for i, c in ipairs(corners) do
		front[i] = c[1] + n * thick
		back[i] = c[1] - n * thick
	end
	local ref = centre
	local s = { corners[1][2], corners[2][2], corners[3][2], corners[4][2] }
	E.triOut(front[1], front[2], front[3], ref, s[1], s[2], s[3])
	E.triOut(front[1], front[3], front[4], ref, s[1], s[3], s[4])
	E.triOut(back[1], back[2], back[3], ref, s[1], s[2], s[3])
	E.triOut(back[1], back[3], back[4], ref, s[1], s[3], s[4])
	for i = 1, 4 do
		local j = i % 4 + 1
		E.triOut(front[i], front[j], back[j], ref, s[i], s[j], s[j])
		E.triOut(front[i], back[j], back[i], ref, s[i], s[j], s[i])
	end
end

-- ---- a lathe: a solid of revolution from {distance along axis, radius} ----
-- Drops, bulbs, necks and stalks are all this shape with a different profile,
-- which is most of why the second pass has fewer primitives than the first.
local function emitLathe(E, origin: Vector3, axis: Vector3,
	stations: { { number } }, segs: number, s0: any, s1: any)
	local u, v, a = frameFor(axis)
	local n = #stations
	local rings = {}
	for k, st in ipairs(stations) do
		local c = origin + a * st[1]
		local ring = table.create(segs)
		for i = 0, segs - 1 do
			local th = TAU * i / segs
			ring[i + 1] = c + u * (math.cos(th) * st[2]) + v * (math.sin(th) * st[2])
		end
		rings[k] = { pts = ring, centre = c, r = st[2] }
	end
	-- s0/s1 may be Color3 endpoints or a single function of u -- a two-stop
	-- ramp is not enough once white has to arrive partway up a shape rather
	-- than at its tip.
	local fn = typeof(s0) == "function" and s0 or nil
	local function shade(k)
		local u = (k - 1) / math.max(n - 1, 1)
		if fn then return fn(u) end
		return (s0 :: Color3):Lerp(s1 :: Color3, u)
	end
	for k = 1, n - 1 do
		local ref = (rings[k].centre + rings[k + 1].centre) / 2
		local sa, sb = shade(k), shade(k + 1)
		for i = 1, segs do
			local j = i % segs + 1
			E.triOut(rings[k].pts[i], rings[k].pts[j], rings[k + 1].pts[j], ref, sa, sa, sb)
			E.triOut(rings[k].pts[i], rings[k + 1].pts[j], rings[k + 1].pts[i], ref, sa, sb, sb)
		end
	end
	-- close the ends only where they are open
	for _, e in ipairs({ { 1, 1, shade(1) }, { n, -1, shade(n) } }) do
		local k, sgn, sh = e[1], e[2], e[3]
		if rings[k].r > 1e-4 then
			local tip = rings[k].centre + a * (sgn * rings[k].r * 0.35)
			local ref = rings[k].centre - a * (sgn * rings[k].r)
			for i = 1, segs do
				local j = i % segs + 1
				E.triOut(rings[k].pts[i], rings[k].pts[j], tip, ref, sh, sh, sh)
			end
		end
	end
end

-- A BALL, AS STATIONS. Two bugs were paid for here and both are worth keeping.
--
-- Round two wrote these inline with five stations, which is four bands, which
-- is an octahedron -- every droplet in the lab rendered as a visible diamond.
--
-- Round three replaced that with nine stations and the droplets STILL came out
-- pointed at the poles, which took building one at 6 studs on its own to see:
-- at 30 px on a contact sheet a lemon and a ball are the same object. The
-- profile spaced HEIGHT linearly (2r * u) while spacing RADIUS by sine, and
-- those are two different parameterisations. A sphere needs both taken from the
-- same angle, so the poles come in tangent to the axis instead of as cusps:
--     d = r * (1 - cos t)      radius = r * sin t      t = pi * k / steps
-- The lesson is the file's own: the picture beat the reasoning, and it only
-- beat it once the picture was big enough to show what it was of.
local function ballStations(r: number, steps: number)
	local out = {}
	for k = 0, steps do
		local t = math.pi * k / steps
		out[k + 1] = { r * (1 - math.cos(t)), r * math.sin(t) }
	end
	return out
end

-- a rounded drop: fat and round at the root, tapering to a soft point
local function dropProfile(len: number, fat: number, stations: number)
	local out = {}
	for k = 0, stations do
		local u = k / stations
		-- sin gives a round shoulder; the (1-u) term brings it to a point
		local r = fat * math.sin(math.pi * (0.18 + 0.82 * u) ) * (1 - u) ^ 0.55
		out[k + 1] = { len * u, math.max(r, 0.0) }
	end
	out[1][2] = fat * 0.72
	return out
end

-- ===================================================================
-- THE CANDIDATES.
--
-- Every one is a function of the emitter and the body's measured radius R, in
-- the mesh's own units, centred on the body's centre. Every one is body-
-- coloured; `spin` and `bob` declare motion for the animator; `smooth` picks
-- averaged normals over per-face ones.
--
-- Azimuths are taken from the FACE, not from world X, for the same reason the
-- pattern lab resolves everything into f/s/y: the body has a front, and a
-- decoration that ignores it is a shape imposed on a sphere.
--
-- THREE FROM THE FIRST PASS ARE GONE and the reasons are worth more than the
-- shapes were:
--
--   drips  INVISIBLE AT THE FRAMING THAT MATTERS. Teardrops hanging off the
--          lower rim are occluded by the body's own bulge from any camera at
--          or above eye height, and what clears the bulge is then against the
--          pad. It measured as a treatment and rendered as nothing. The lower
--          hemisphere of a slime that sits on the ground is not display space.
--
--   shards ANGULAR PLATES ARE THE WRONG MATERIAL. Flat panes read as sheet
--          metal or paper bolted to a blob -- the silhouette changed and the
--          creature stopped being a slime. This is the same failure as the
--          tonal accents, one level up: the addition has to belong to the
--          thing, and hard flat facets do not belong to something soft.
--
--   frill  SAME, plus it fanned out sideways into a collar, and a white band
--          across the upper body is the marking family this project has
--          already rejected twice (mane, collar). Rebuilding it in geometry
--          did not make it a new idea.
--
-- What survived the first pass is the observation that spikes and stalks BOTH
-- read instantly at 7 studs. Silhouette was never in doubt. The question the
-- second pass is asking is whether it can read as a slime while it does.
--
-- AND THREE MORE DIED OF ONE RULE, which is the most useful thing this file
-- found and is worth stating on its own:
--
--     GEOMETRY ONLY COUNTS WHERE IT BREAKS THE SILHOUETTE FROM THE CAMERA THE
--     GAME ACTUALLY USES, AND BOTH OF THOSE CAMERAS ARE LEVEL.
--
--   ring   Eight beads circling the waist at 1.06R. A level camera sees a
--          waist ring EDGE-ON: the near beads sit inside the body's own
--          outline and change nothing, and only the two at the extreme sides
--          break it, where they read as lumps rather than as a ring. A ring
--          reads as a ring from above, and nothing in this game looks down.
--   orbit  Same failure at 1.20R, with the added problem that beads floating
--          clear of a body they match read as debris rather than as its doing.
--   drips  Same failure below the equator, plus occlusion by the body's own
--          bulge and then by the pad.
--
-- So the usable space is UP and OUT-AND-UP, and every candidate that survived
-- is in it. That is not a taste convergence, it is where the two framings put
-- their horizon: the base camera sits at eye height with the slime's crown
-- 21% above it, and the reveal camera is level through the slime's middle.
-- ===================================================================
local FACE_AZ = math.atan2(FWD.X, FWD.Z)

-- a direction from azimuth (about the face) and elevation
local function dirAt(az: number, elevDeg: number): Vector3
	local e = math.rad(elevDeg)
	return Vector3.new(math.sin(az) * math.cos(e), math.sin(e), math.cos(az) * math.cos(e))
end

local CANDIDATES = {
	{
		-- THE ONE THAT LANDED FIRST TIME. A slime is a drop of liquid; the thing
		-- a drop of liquid does that nothing else here does is LIFT.
		name = "plume",
		note = "the crown drawn up into a standing drop, beads breaking off above",
		spin = 0.0, bob = 0.045, sway = 5.5, smooth = true,
		build = function(E, R, T)
			local base = surfacePoint(Vector3.new(0, 1, 0))
			local axis = (Vector3.new(0, 1, 0) + FWD * 0.10).Unit
			-- A DROP READS AS A DROP BY ITS ASPECT, NOT ITS SIZE. At 1.10R long
			-- and 0.325R fat this was a SPIRE -- the eye called it a spike on a
			-- ball and the slime stopped being liquid. Shorter and fatter is the
			-- fix, and it is the same trade the fire tongues found: under a
			-- shape you cannot change one dimension in isolation and keep the
			-- reading.
			-- WHITE ARRIVES PARTWAY UP, NOT AT THE TIP. The ladder below is
			-- ordered by white COVERAGE -- 0, blaze, stripes4, dots24 at 28% --
			-- so a top rung whose white is three small beads is not obviously
			-- its last step. Measured against a real dots24 slime at the same
			-- size it was not obviously bolder either. The crest carries it.
			-- SUNK AND WIDE, so it flows out of the crown instead of sitting on
			-- it. `peak` was built as a separate candidate to test exactly this
			-- -- 0.545R fat and sunk 0.30R against the plume's 0.355R and 0.12R
			-- -- and it won on both counts: bigger reads bolder, and a base
			-- wider than the dome's local radius removes the ledge where an
			-- addition meets a body. The two were merged rather than shipped
			-- as a pair, because they were one idea at two settings.
			emitLathe(E, base - Vector3.new(0, R * 0.28, 0), axis,
				dropProfile(R * 1.00, R * 0.520, 16), 18, T.body, T.light)
			local tip = base + axis * (R * 0.72)
			-- three beads, each smaller and further, so the eye reads a sequence
			-- rather than a cluster: this is the same argument as placing tongues
			-- instead of thresholding them, one dimension down.
			for k, rr in ipairs({ 0.100, 0.065, 0.038 }) do
				local c = tip + axis * (R * (0.20 + 0.195 * (k - 1))) + FWD * (R * 0.035 * (k - 1))
				emitLathe(E, c - Vector3.new(0, R * rr, 0), Vector3.new(0, 1, 0),
					ballStations(R * rr, 9), 12, T.accent, T.accent)
			end
		end,
	},
	{
		-- BOTH AT ONCE. The plume's claim on the top rung is a change of KIND --
		-- it is the only slime in the ladder that is not a ball -- but on white
		-- AREA it does not beat dots24, and a rung that loses to the rung below
		-- on the ladder's own axis is worth testing against a version that does
		-- not. This is the plume with the crown's ring around its foot.
		name = "regalia",
		note = "the plume, ringed at its foot by five white-capped drops",
		spin = 0.0, bob = 0.045, sway = 5.0, smooth = true,
		build = function(E, R, T)
			local base = surfacePoint(Vector3.new(0, 1, 0))
			local axis = (Vector3.new(0, 1, 0) + FWD * 0.10).Unit
			emitLathe(E, base - Vector3.new(0, R * 0.28, 0), axis,
				dropProfile(R * 1.00, R * 0.520, 16), 18, T.body, T.light)
			local tip = base + axis * (R * 0.72)
			for k, rr in ipairs({ 0.100, 0.065, 0.038 }) do
				local c = tip + axis * (R * (0.20 + 0.195 * (k - 1))) + FWD * (R * 0.035 * (k - 1))
				emitLathe(E, c - Vector3.new(0, R * rr, 0), Vector3.new(0, 1, 0),
					ballStations(R * rr, 9), 12, T.accent, T.accent)
			end
			local n = 5
			for i = 0, n - 1 do
				local az = FACE_AZ + math.pi + TAU * i / n
				local dir = dirAt(az, 30)
				local b = surfacePoint(dir)
				local a2 = (dir + Vector3.new(0, 0.85, 0)).Unit
				emitLathe(E, b - dir * (R * 0.10), a2,
					dropProfile(R * 0.46, R * 0.155, 12), 11, function(u)
						if u < 0.72 then return T.body:Lerp(T.light, u / 0.72) end
						return T.accent
					end, nil)
			end
		end,
	},
	{
		-- A CONE IS THE WRONG SHAPE EVEN WHEN THE COLOUR IS RIGHT. Built as
		-- straight cones with a hard white cap this read, unmistakably, as a
		-- ring of SHARPENED PENCILS -- and moving the cap from 0.62 to 0.80 did
		-- not touch it, because the tell was never the cap. A straight taper
		-- with a circular base is a manufactured object; the slime is not. So
		-- the crown is built from the same drop profile as the plume, which is
		-- the shape the body itself is made of.
		name = "crown",
		note = "seven drops standing off the shoulder, capped in the ladder's white",
		spin = 0.0, bob = 0.02, sway = 2.0, smooth = true,
		build = function(E, R, T)
			local n = 7
			for i = 0, n - 1 do
				local az = FACE_AZ + math.pi + TAU * i / n
				local dir = dirAt(az, 40)
				local base = surfacePoint(dir)
				local axis = (dir + Vector3.new(0, 0.72, 0)).Unit
				local len = R * (0.66 + 0.10 * math.sin(i * 2.4))
				emitLathe(E, base - dir * (R * 0.10), axis,
					dropProfile(len, R * 0.20, 14), 12, function(u)
						-- a STEP, not a ramp: white that fades up a form reads
						-- as sheen, which is the terminator rule in geometry
						if u < 0.74 then return T.body:Lerp(T.light, u / 0.74) end
						return T.accent
					end, nil)
			end
		end,
	},
	{
		name = "antennae",
		note = "two thick stalks with heavy white bulbs, leaning forward",
		spin = 0.0, bob = 0.05, sway = 7.0, smooth = true,
		build = function(E, R, T)
			for side = -1, 1, 2 do
				local az = FACE_AZ + side * math.rad(24)
				local dir = dirAt(az, 64)
				local base = surfacePoint(dir)
				local pts, radii, shades = {}, {}, {}
				local len = R * 0.90
				for k = 0, 8 do
					local u = k / 8
					pts[k + 1] = base + Vector3.new(0, len * u, 0)
						+ FWD * (len * 0.30 * u * u)
						+ Vector3.new(math.sin(az), 0, math.cos(az)) * (len * 0.16 * u)
					radii[k + 1] = R * (0.082 - 0.030 * u)
					shades[k + 1] = T.body:Lerp(T.light, u)
				end
				emitTube(E, pts, radii, 10, shades)
				local b = R * 0.155
				emitLathe(E, pts[9] - Vector3.new(0, b, 0), Vector3.new(0, 1, 0),
					ballStations(b, 9), 14, T.accent, T.accent)
			end
		end,
	},

	-- ===================================================================
	-- THE ONES THAT DID NOT MAKE IT, KEPT AS CODE.
	--
	-- The prose above says what each of these died of, which is worth having
	-- and is not the same as having them. A reason you cannot rebuild is a
	-- reason nobody can check, and every one of these was judged in a round
	-- BEFORE the tone bug and the sphere-profile bug were found -- so the
	-- shots that killed them are not shots of what they would look like now.
	-- Set SHOW_DEAD to build them alongside the survivors, under the same
	-- emitter, the same accent and the same camera. Same argument as the
	-- matched white fraction one lab over: a comparison across different
	-- builds is not a comparison.
	--
	-- CORONET AND HALO LOOK MATERIALLY BETTER REBUILT than they did when they
	-- were cut, and both are still cut. coronet is a clean set of soft horns
	-- once the tone is right -- it is crown without the white cap, and crown is
	-- the version of it that wins. halo is a real ring of droplets once they
	-- are spheres rather than lemons; it is still scattered rather than held,
	-- but it is the first thing to reopen if regalia is rejected. Saying that
	-- is the useful half of keeping them: a cut made on a broken build is a cut
	-- that deserves re-reading, and eleven of the thirteen still read the same.
	-- ===================================================================
	{
		name = "crown-cones",
		note = "the first crown: straight cones, hard white cap",
		dead = "read as sharpened pencils -- a straight taper on a circular base"
			.. " is a manufactured object and a slime is not one",
		spin = 0.0, bob = 0.0, sway = 0.0, smooth = false,
		build = function(E, R, T)
			for i = 0, 6 do
				local az = FACE_AZ + math.pi + TAU * i / 7
				local dir = dirAt(az, 38)
				local base = surfacePoint(dir)
				local axis = (dir + Vector3.new(0, 0.55, 0)).Unit
				local len = R * (0.70 + 0.11 * math.sin(i * 2.4))
				emitSpike(E, base - dir * (R * 0.06), axis,
					R * 0.145, R * 0.035, len, 8, T.body, T.accent, 0.80)
			end
		end,
	},
	{
		name = "coronet",
		note = "seven soft drops on the shoulder, no cap",
		dead = "right family, too timid to be a rung above a 24-dot field."
			.. " Absorbed into crown, which is this at size with a white cap",
		spin = 0.0, bob = 0.0, sway = 0.0, smooth = true,
		build = function(E, R, T)
			for i = 0, 6 do
				local az = FACE_AZ + math.pi + TAU * i / 7
				local dir = dirAt(az, 40)
				local base = surfacePoint(dir)
				local axis = (dir + Vector3.new(0, 0.75, 0)).Unit
				local len = R * (0.52 + 0.09 * math.sin(i * 2.4))
				emitLathe(E, base - dir * (R * 0.08), axis,
					dropProfile(len, R * 0.155, 9), 10, T.body, T.light)
			end
		end,
	},
	{
		name = "halo",
		note = "six droplets in a ring above the crown, turning",
		dead = "scattered rather than a ring: at 0.66R apart and clear of the"
			.. " body they read as bubbles drifting off, not as the slime's doing",
		spin = 0.40, bob = 0.0, sway = 0.0, smooth = true,
		build = function(E, R, T)
			local top = surfacePoint(Vector3.new(0, 1, 0)).Y
			for i = 0, 5 do
				local az = TAU * i / 6
				local rad = R * 0.66
				local c = Vector3.new(math.sin(az) * rad, top + R * 0.22, math.cos(az) * rad)
				local rr = R * 0.175
				emitLathe(E, c - Vector3.new(0, rr, 0), Vector3.new(0, 1, 0),
					ballStations(rr, 9), 14, T.accent, T.light)
			end
		end,
	},
	{
		name = "orbit",
		note = "six droplets held off the flanks in a ring, turning",
		dead = "THE SILHOUETTE RULE. A level camera sees a waist ring edge-on:"
			.. " the near beads sit inside the body's own outline and change"
			.. " nothing, and the side ones read as lumps stuck on",
		spin = 0.45, bob = 0.0, sway = 0.0, smooth = true,
		build = function(E, R, T)
			for i = 0, 5 do
				local az = TAU * i / 6
				local lift = 0.26 * math.sin(i * 1.7 + 0.4)
				local rad = R * 1.20
				local c = Vector3.new(math.sin(az) * rad, R * lift, math.cos(az) * rad)
				local rr = R * (0.175 + 0.035 * math.sin(i * 1.3))
				emitLathe(E, c - Vector3.new(0, rr, 0), Vector3.new(0, 1, 0),
					ballStations(rr, 9), 14, T.light, T.body)
			end
		end,
	},
	{
		name = "ring",
		note = "eight beads circling the waist, tight and even, turning",
		dead = "the same rule, and this one was built specifically to test"
			.. " whether TIGHT and EVEN rescued it. It does not: the geometry is"
			.. " correct and the camera still cannot see it",
		spin = 0.55, bob = 0.0, sway = 0.0, smooth = true,
		build = function(E, R, T)
			for i = 0, 7 do
				local az = TAU * i / 8
				local rad = R * 1.06
				local c = Vector3.new(math.sin(az) * rad, R * 0.06, math.cos(az) * rad)
				local rr = R * 0.125
				emitLathe(E, c - Vector3.new(0, rr, 0), Vector3.new(0, 1, 0),
					ballStations(rr, 9), 12, T.accent, T.light)
			end
		end,
	},
	{
		name = "drips",
		note = "seven teardrops hanging off the lower rim",
		dead = "the same rule below the equator, plus occlusion: what clears the"
			.. " body's own bulge is then against the pad. The lower hemisphere"
			.. " of a slime that sits on the ground is not display space",
		spin = 0.0, bob = 0.0, sway = 0.0, smooth = true,
		build = function(E, R, T)
			for i = 0, 6 do
				local az = FACE_AZ + math.pi + TAU * i / 7 + 0.16
				local dir = dirAt(az, -26)
				local base = surfacePoint(dir)
				local len = R * (0.34 + 0.20 * math.abs(math.sin(i * 2.9)))
				local pts, radii, shades = {}, {}, {}
				for k = 0, 5 do
					local u = k / 5
					pts[k + 1] = base + Vector3.new(0, -len * u, 0)
					radii[k + 1] = R * (0.10 * (1 - u * 0.85) + 0.055 * math.sin(u * math.pi))
					shades[k + 1] = T.body:Lerp(T.light, u)
				end
				emitTube(E, pts, radii, 7, shades)
				local b = R * 0.075
				emitLathe(E, pts[6] + Vector3.new(0, -R * 0.055 - b, 0), Vector3.new(0, 1, 0),
					ballStations(b, 9), 10, T.accent, T.accent)
			end
		end,
	},
	{
		name = "shards",
		note = "five angular plates erupting from the back and shoulders",
		dead = "WRONG MATERIAL. Flat panes read as sheet metal bolted to a blob:"
			.. " the silhouette changed and the creature stopped being a slime."
			.. " The tonal-accent failure one level up -- the addition has to"
			.. " belong to the thing",
		spin = 0.0, bob = 0.0, sway = 0.0, smooth = false,
		build = function(E, R, T)
			local specs = {
				{ 150, 46, 0.78, 0.34 }, { 205, 30, 0.95, 0.40 },
				{ 255, 52, 0.70, 0.30 }, { 180, 66, 0.62, 0.26 },
				{ 232, 12, 0.86, 0.36 },
			}
			for _, sp in ipairs(specs) do
				local az = FACE_AZ + math.pi + math.rad(sp[1])
				local dir = dirAt(az, sp[2])
				local base = surfacePoint(dir)
				local axis = (dir + Vector3.new(0, 0.35, 0)).Unit
				local normal = Vector3.new(math.cos(az), 0, -math.sin(az))
				emitPlate(E, base + axis * (R * sp[3] * 0.5), normal, axis,
					R * sp[3] * 0.5, R * sp[4], R * 0.035, 0.18, T.body, T.accent)
			end
		end,
	},
	{
		name = "frill",
		note = "a ruff of fourteen overlapping petals around the upper body",
		dead = "the same wrong material, fanned sideways -- and a band across the"
			.. " upper body is the marking family this project has already"
			.. " rejected twice. Rebuilding it in geometry did not make it new",
		spin = 0.0, bob = 0.0, sway = 0.0, smooth = false,
		build = function(E, R, T)
			for i = 0, 13 do
				local az = TAU * i / 14
				local dir = dirAt(az, 16)
				local base = surfacePoint(dir)
				local axis = (dir + Vector3.new(0, -0.30, 0)).Unit
				local normal = Vector3.new(math.cos(az), 0, -math.sin(az))
				emitPlate(E, base + axis * (R * 0.20), normal, axis,
					R * 0.24, R * 0.16, R * 0.022, 0.55, T.body, T.accent)
			end
		end,
	},
	{
		name = "spire",
		note = "the plume at 1.10R long and 0.325R fat",
		dead = "a DROP READS BY ITS ASPECT. Tall and narrow is a spire, and the"
			.. " slime stopped being liquid. Kept because the failure is a"
			.. " setting rather than an idea, and the setting is easy to redo",
		spin = 0.0, bob = 0.045, sway = 5.5, smooth = true,
		build = function(E, R, T)
			local base = surfacePoint(Vector3.new(0, 1, 0))
			local axis = (Vector3.new(0, 1, 0) + FWD * 0.10).Unit
			emitLathe(E, base - Vector3.new(0, R * 0.12, 0), axis,
				dropProfile(R * 1.10, R * 0.325, 14), 16, T.body, T.light)
			local tip = base + axis * (R * 1.10)
			for k, rr in ipairs({ 0.115, 0.072, 0.042 }) do
				local c = tip + axis * (R * (0.17 + 0.26 * (k - 1))) + FWD * (R * 0.03 * (k - 1))
				emitLathe(E, c - Vector3.new(0, R * rr, 0), Vector3.new(0, 1, 0),
					ballStations(R * rr, 9), 12, T.accent, T.accent)
			end
		end,
	},
}


-- ===================================================================
-- THE ANIMATOR, emitted into the lab as a client Script.
--
-- One CFrame write per Legendary part per frame. Sixty of those is nothing --
-- SlimeIdleClient already writes Size and CFrame for every slime body in the
-- base every frame, and this is strictly less work than that.
--
-- IT READS THE BODY'S CFrame EVERY FRAME rather than caching a rest pose,
-- because in the real game SlimeIdleClient owns the body and moves it; caching
-- would make the addition drift off the top of a breathing slime. Two writers
-- to one part is the failure BUILD_DIVINE's `driveBody` flag exists to avoid,
-- and this is the same hazard one level out.
-- ===================================================================
local ANIMATOR_SOURCE = [==[
local RunService = game:GetService("RunService")
local root = script.Parent
local PERIOD = 2.6      -- deliberately NOT SlimeIdleClient's IdlePeriod of 2:
                        -- a lean that shares the breath's period reads as part
                        -- of the breath, and the point of the lean is to be a
                        -- second thing happening.

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for _, m in ipairs(root:GetChildren()) do
		if m:IsA("Model") then
			local g = m:FindFirstChild("Legendary")
			local body = m:FindFirstChild("body")
			if g and body then
				local ph = (t / PERIOD) * math.pi * 2
				local sway = math.rad(m:GetAttribute("SwayDeg") or 0) * math.sin(ph)
				local bob = (m:GetAttribute("BobFrac") or 0) * math.sin(ph) * body.Size.Y
				local spin = (m:GetAttribute("SpinRate") or 0) * t
				g.CFrame = body.CFrame
					* CFrame.Angles(0, spin, 0)
					* CFrame.Angles(0, 0, sway)
					* CFrame.new(0, bob, 0)
			end
		end
	end
end)
]==]

-- ===================================================================
-- BUILD.
-- ===================================================================
local function run()
	local lines = {}
	local function log(...) table.insert(lines, string.format(...)) end
	local t0 = os.clock()
	local Y = newYielder(P.YIELD_MS)

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
	assert(src, "[Legendary] no MeshPart found under any of {"
		.. table.concat(P.SOURCE_MODELS, ", ") .. "}")
	local source = src :: BasePart
	log("[Legendary] source: %s", source:GetFullName())

	-- ---- measure the silhouette ----
	local em = AssetService:CreateEditableMeshAsync(Content.fromUri((source :: any).MeshId))
	local verts = em:GetVertices()
	Y.mark()
	local mnx, mxx = math.huge, -math.huge
	local mny, mxy = math.huge, -math.huge
	local mnz, mxz = math.huge, -math.huge
	for _, id in ipairs(verts) do
		Y.tick()
		local p = em:GetPosition(id)
		mnx = math.min(mnx, p.X); mxx = math.max(mxx, p.X)
		mny = math.min(mny, p.Y); mxy = math.max(mxy, p.Y)
		mnz = math.min(mnz, p.Z); mxz = math.max(mxz, p.Z)
	end
	local CX, CY, CZ = (mnx + mxx) / 2, (mny + mxy) / 2, (mnz + mxz) / 2
	local RAD = (mxx - mnx) / 2
	local PB = 96
	local bucket = table.create(PB, 0)
	for _, id in ipairs(verts) do
		Y.tick()
		local p = em:GetPosition(id)
		local tb = (p.Y - mny) / math.max(mxy - mny, 1e-9)
		local bi = math.clamp(math.floor(tb * PB) + 1, 1, PB)
		local rr = math.sqrt((p.X - CX) ^ 2 + (p.Z - CZ) ^ 2) / RAD
		if rr > bucket[bi] then bucket[bi] = rr end
	end
	local filled = 0
	PROFILE = {}
	for bi = 1, PB do
		if bucket[bi] > 0 then
			filled += 1
			table.insert(PROFILE, { (bi - 0.5) / PB, bucket[bi] })
		end
	end
	assert(#PROFILE >= 8, "[Legendary] silhouette profile too sparse to interpolate")
	PY0, PY1, PRAD = mny - CY, mxy - CY, RAD
	log("[Legendary] silhouette: %d non-empty of %d bands, radius %.3f base to %.3f crown",
		filled, PB, PROFILE[1][2], PROFILE[#PROFILE][2])

	local BOX = { hx = (mxx - mnx) / 2, hy = (mxy - mny) / 2, hz = (mxz - mnz) / 2 }

	-- ---- framing ----
	local isBase = P.FRAMING == "base"
	local widthStuds = isBase and P.BASE_WIDTH_STUDS or P.REVEAL_WIDTH_STUDS
	local distance = isBase and P.BASE_DISTANCE or P.REVEAL_DISTANCE
	local bodySize = source.Size * (widthStuds / (2 * BOX.hx)) / (source.Size.X / (2 * BOX.hx))
	bodySize = Vector3.new(
		widthStuds,
		widthStuds * (BOX.hy / BOX.hx),
		widthStuds * (BOX.hz / BOX.hx))
	local studsPerUnit = widthStuds / (2 * BOX.hx)
	local pxPerStud = 563 / (2 * distance * math.tan(math.rad(P.FOV_DEG) / 2))
	log("[Legendary] framing %s: body %.2f studs across, %.1f px/stud at %d studs, %.0f px wide",
		P.FRAMING, widthStuds, pxPerStud, distance, widthStuds * pxPerStud)

	-- ---- which candidates, which hues ----
	local live = {}
	for _, c in ipairs(CANDIDATES) do
		if P.SHOW_DEAD or not c.dead then table.insert(live, c) end
	end

	local build = {}
	if #P.ONLY > 0 then
		for _, n in ipairs(P.ONLY) do
			local found = nil
			for _, c in ipairs(CANDIDATES) do if c.name == n then found = c break end end
			assert(found, string.format("[Legendary] ONLY names %q, which is not a candidate", n))
			table.insert(build, found)
		end
	else
		build = live
	end
	local hues = {}
	local wanted = {}
	for _, n in ipairs(P.HUES_ONLY) do wanted[n] = true end
	for _, h in ipairs(P.HUES) do
		if #P.HUES_ONLY == 0 or wanted[h[1]] then table.insert(hues, h) end
	end
	if #hues == 0 then hues = { P.HUES[1] } end

	for _, c in ipairs(workspace:GetChildren()) do
		if c.Name == P.ROOT_NAME then c:Destroy() end
	end
	local root = Instance.new("Model")
	root.Name = P.ROOT_NAME
	root.Parent = workspace

	-- ---- one shared mesh per (candidate, hue) ----
	-- THE PART IS WHITE AND THE VERTEX COLOUR IS THE ALBEDO. Vertex colour
	-- MULTIPLIES Color, so a coloured part can only ever be darkened -- which
	-- is why the first three rounds could not put the ladder's white anywhere.
	-- Set Color to white and the multiply becomes an identity: the mesh can
	-- carry the hue AND the accent, in one part, with no texture and no UVs.
	-- The price is that the mesh now depends on the hue, so there are six
	-- rather than one. That is the shape TierMarks already ships (four masks,
	-- four meshes) and it changes nothing that costs: still one PART per slime,
	-- still the same triangles on screen.
	local proto = {}
	local function protoFor(c, hueName: string, hue: Color3)
		local key = c.name .. "|" .. hueName
		if proto[key] then return proto[key] end
		local E = newEmitter(BOX, P.EXTENT_XZ, P.EXTENT_Y, c.smooth == true)
		c.build(E, RAD, {
			body = hue,
			light = hue:Lerp(Color3.new(1, 1, 1), P.LIFT),
			accent = P.ACCENT,
		})
		Y.mark()
		local mp = AssetService:CreateMeshPartAsync(Content.fromObject(E.em))
		Y.mark()
		mp.Name = "Legendary_" .. c.name .. "_" .. hueName
		proto[key] = { part = mp, tris = E.count(), clamped = E.clamped() }
		return proto[key]
	end

	local function ground(cx: number, cz: number)
		if isBase then
			local g = Instance.new("Part")
			g.Size = Vector3.new(300, 1, 900) g.CFrame = CFrame.new(cx, -0.5, cz - 430)
			g.Color = P.GRASS g.Material = Enum.Material.Grass
			g.Anchored = true g.CanCollide = false g.CanQuery = false g.CanTouch = false
			g.Name = "grass" g.Parent = root
			local pad = Instance.new("Part")
			pad.Size = Vector3.new(8, 0.6, 8) pad.CFrame = CFrame.new(cx, 1.0, cz)
			pad.Color = P.PAD pad.Material = Enum.Material.Concrete
			pad.Anchored = true pad.CanCollide = false pad.CanQuery = false pad.CanTouch = false
			pad.Name = "pad" pad.Parent = root
		else
			for i = 0, P.BAND_COUNT - 1 do
				local b = Instance.new("Part")
				b.Size = Vector3.new(300, 1, P.BAND_LENGTH)
				b.CFrame = CFrame.new(cx, -0.5, cz - i * P.BAND_LENGTH)
				b.Color = Color3.fromHSV((i % 5) / 5, 1, 1)
				b.Material = Enum.Material.Plastic
				b.Anchored = true b.CanCollide = false b.CanQuery = false b.CanTouch = false
				b.Name = "band" .. i b.Parent = root
			end
		end
	end

	-- ---- one cell per (candidate, hue) ----
	local jobs = {}
	if #P.SHOOT_PHASES > 0 then
		local c = nil
		for _, cc in ipairs(CANDIDATES) do if cc.name == P.PHASE_OF then c = cc break end end
		assert(c, string.format("[Legendary] PHASE_OF names %q, which is not a candidate", P.PHASE_OF))
		for _, ph in ipairs(P.SHOOT_PHASES) do
			table.insert(jobs, { c = c, hue = hues[1], phase = ph,
				name = string.format("%s_p%02d", c.name, math.floor(ph * 100)) })
		end
	else
		for _, c in ipairs(build) do
			for _, h in ipairs(hues) do
				table.insert(jobs, { c = c, hue = h, phase = P.PHASE,
					name = string.format("%s_%s", c.name, h[1]) })
			end
		end
	end

	for ri = #P.LADDER_REF, 1, -1 do
		local want = P.LADDER_REF[ri]
		local lab = workspace:FindFirstChild("PatternLab")
		local ref = nil
		if lab then
			for _, c in ipairs(lab:GetChildren()) do
				if c:GetAttribute("Variant") == want then ref = c end
			end
		end
		assert(ref, string.format("[Legendary] LADDER_REF names %q -- run"
			.. " EXPLORE_PATTERNS with that variant in ONLY first", want))
		table.insert(jobs, 1, { c = { name = want .. "-ref", spin = 0, bob = 0, sway = 0,
			note = "a rung below, same size, same ground, same camera" },
			hue = hues[1], phase = 0, name = want .. "_ref",
			texture = (ref:FindFirstChild("body") :: any).TextureContent })
	end

	local centreY = isBase and (1.3 + bodySize.Y / 2) or P.REVEAL_Y
	for i, job in ipairs(jobs) do
		Y.tick()
		local cx = (i - 1) * P.CELL_SPACING
		local cz = P.CELL_Z
		ground(cx, cz)

		local m = Instance.new("Model")
		m.Name = job.name
		m.Parent = root
		local bodyCF = CFrame.new(cx, centreY, cz) * CFrame.Angles(0, math.rad(P.BODY_YAW_DEG), 0)

		local body = source:Clone()
		body.Size = bodySize
		body.Name = "body"
		body.Color = job.hue[2]
		body.Material = P.BODY_MATERIAL
		body.Anchored = true
		body.CanCollide = false body.CanQuery = false body.CanTouch = false
		pcall(function() body.TextureID = "" end)
		if job.texture then
			body.Color = Color3.new(1, 1, 1)
			body.TextureContent = job.texture
		end
		body.CFrame = bodyCF
		body.Parent = m
		m.PrimaryPart = body

		for _, spec in ipairs(FACE_PARTS) do
			local part = AssetService:CreateMeshPartAsync(Content.fromUri(spec.mesh))
			part.Name = spec.name
			part.Size = spec.size * studsPerUnit / (spec.size.X / spec.size.X)
			part.Size = spec.size * (studsPerUnit / (source.Size.X / (2 * BOX.hx)))
			part.Color = spec.color
			part.Material = Enum.Material.SmoothPlastic
			part.Anchored = true
			part.CanCollide = false part.CanQuery = false part.CanTouch = false
			part.CFrame = bodyCF * CFrame.new(spec.rel.Position * (studsPerUnit / (source.Size.X / (2 * BOX.hx))))
			part.Parent = m
		end
		Y.mark()

		-- NOT `job.texture and nil or protoFor(...)`. `x and nil or y` is y for
		-- every x in Lua, because `x and nil` is nil and `nil or y` is y -- the
		-- reference cell called protoFor anyway and died on a candidate with no
		-- build function. The ternary idiom cannot carry nil as its true arm.
		local pr = nil
		if not job.texture then pr = protoFor(job.c, job.hue[1], job.hue[2]) end
		if pr then
		local g = pr.part:Clone()
		g.Name = "Legendary"
		g.Size = Vector3.new(bodySize.X * P.EXTENT_XZ, bodySize.Y * P.EXTENT_Y, bodySize.Z * P.EXTENT_XZ)
		-- the hue lifted toward white; vertex colour brings it back down
		g.Color = Color3.new(1, 1, 1)   -- see protoFor: the mesh carries its own colour
		g.Material = P.BODY_MATERIAL
		g.Anchored = true
		g.CanCollide = false g.CanQuery = false g.CanTouch = false
		-- SWAY IS A LEAN ABOUT THE BODY'S OWN CENTRE, not a translation. A drop
		-- standing on a slime has inertia; leaning is what says so, and a bob
		-- alone reads as the body's breath already does (SlimeIdleClient runs
		-- one at IdlePeriod 2). The lean is around the SIDEWAYS axis so it
		-- rocks across the face rather than nodding at the camera.
		local ph = job.phase * TAU
		local sway = math.rad(job.c.sway or 0) * math.sin(ph)
		g.CFrame = bodyCF
			* CFrame.Angles(0, (job.c.spin or 0) * job.phase * TAU, 0)
			* CFrame.Angles(0, 0, sway)
			* CFrame.new(0, (job.c.bob or 0) * math.sin(ph) * bodySize.Y, 0)
		g.Parent = m
		end

		m:SetAttribute("BodyCentre", Vector3.new(cx, centreY, cz))
		m:SetAttribute("Index", i)
		m:SetAttribute("Candidate", job.c.name)
		m:SetAttribute("Hue", job.hue[1])
		m:SetAttribute("Framing", P.FRAMING)
		m:SetAttribute("Distance", distance)
		m:SetAttribute("EyeY", isBase and P.BASE_EYE_Y or P.REVEAL_Y)
		m:SetAttribute("Tris", pr and pr.tris or 0)
		m:SetAttribute("SwayDeg", job.c.sway or 0)
		m:SetAttribute("BobFrac", job.c.bob or 0)
		m:SetAttribute("SpinRate", job.c.spin or 0)
	end

	local meshes, worst = 0, 0
	for _, pr in pairs(proto) do
		meshes += 1
		worst = math.max(worst, pr.tris)
		if pr.clamped > 0 then
			log("[Legendary] %d verts CLAMPED at extent %.1f/%.1f -- geometry is being"
				.. " flattened onto the marker box", pr.clamped, P.EXTENT_XZ, P.EXTENT_Y)
		end
	end
	for _, c in ipairs(build) do
		local any = nil
		for k, pr in pairs(proto) do if k:sub(1, #c.name + 1) == c.name .. "|" then any = pr end end
		if any then
			log("[Legendary] %-12s %5d tris | %s%s", c.name, any.tris,
				c.dead and "CUT -- " or "", c.dead or c.note)
		end
	end
	-- ---- the animator, so the motion is real rather than posed ----
	-- Emitted into the lab the way BUILD_DIVINE emits DivineAnimator: the
	-- treatment has to be a thing that exists and runs, not a pose the build
	-- happened to freeze. It reads the same attributes the static pose above
	-- writes, so a screenshot and a running slime cannot disagree about what
	-- the motion is.
	if P.ANIMATE then
		local anim = Instance.new("Script")
		anim.Name = "LegendaryAnimator"
		anim.RunContext = Enum.RunContext.Client
		anim.Source = ANIMATOR_SOURCE
		anim.Parent = root
	end

	log("[Legendary] built %d cells at %d studs apart | %d shared meshes, 1 part per slime",
		#jobs, P.CELL_SPACING, meshes)
	log("[Legendary] worst candidate %d tris -> 60 slimes = %dk, against TierMarks' accepted 352k",
		worst, worst * 60 // 1000)
	log("[Legendary] watchdog worst hold %.1f ms | %.2f s", Y.worstMs(), os.clock() - t0)
	log("[Legendary] undo with workspace.%s:Destroy()", P.ROOT_NAME)

	local out = table.concat(lines, "\n")
	print(out)
	return out
end

return run()
