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
-- ===================== THE TERMINATOR RULE (learned here) =================
--
-- A MARKING HAS TO CROSS THE LIGHT BOUNDARY TO READ AS A MARKING. If it lies
-- along one side of that boundary instead, the renderer is already drawing the
-- same shape for free, and the eye takes the cheaper explanation: not a marked
-- creature, just a lit one. This is what killed countershade, and in hindsight
-- it is what killed the tonal accents before it. Both put their edge exactly
-- where the light already puts one.
--
-- IT IS NOT THE TONE AND IT IS NOT THE EDGE. Both were A/B'd against
-- countershade at 40 studs, on the body, at matched white fraction, and neither
-- moves it:
--     cream  (252,251,247) on the belly renders  144.9
--     pure   (255,255,255) on the belly renders  146.8   -- 2 of 255, invisible
--     the SAME cream on an up-facing crown renders 234.1 -- 90 of 255
-- The grey is the shading, not the paint; the accent was already 1.2% off pure
-- white, so there was never any grey in it to remove. Likewise the boundary
-- already resolves in about 2 px at 40 studs, and a 6x harder texture edge
-- moved exactly one pixel. THIS IS WHY BOTH KNOBS EXIST AS PER-VARIANT
-- OVERRIDES rather than having been deleted: proving a knob does not matter is
-- worth keeping, and it should not cost a scratch edit to prove it again.
--
-- SO IT IS MEASURED, NOT EYEBALLED -- lightFit() reports two numbers per
-- variant, and they answer different halves of the question.
--
--   J   Youden's J of the best single height threshold. All a light does is
--       fall off monotonically from top to bottom, so this asks how much of the
--       marking a plain gradient could account for. 1.00 = a light draws it
--       exactly. Measured: socks 1.00, cap-tilt 0.73, countershade 0.51,
--       blaze 0.13, stripes4 0.05, plastron 0.01.
--
--   lit Mean lambert over the white, against mean lambert over the whole body.
--       Where the marking SITS rather than what shape it is, and the one that
--       matches what the pixels did. Countershade measures 0.01 -- its white is
--       entirely under the equator, which is exactly the 144.9-against-234.1
--       above. Wanted: near 1, meaning the marking straddles the boundary.
--       Measured: socks 0.00, countershade 0.01, bib 0.16, stripes2 0.70,
--       plastron 1.00, blaze 1.47, crest 1.74, cap-tilt 3.02.
--
-- BOTH ARE FLAGGED, NEVER ASSERTED. A high J or a lopsided lit is a reason to
-- look, not proof of a bad marking -- and the flag is two-sided, because
-- hiding in the shade (countershade) and sitting in the highlight (cap-tilt)
-- are the same mistake wearing different clothes.
--
-- THE COROLLARY, AND IT IS THE USEFUL HALF: A MARKING THAT NEVER MENTIONS
-- HEIGHT CANNOT BE MISTAKEN FOR A HEIGHT GRADIENT. Every shape here that
-- scores well is a function of f and s alone -- mane 0.10, brackets 0.11,
-- blaze 0.13, stripes4 0.05 -- and every shape that scores badly has y in it.
-- That is not a coincidence, it is the definition of J restated.
--
-- IT IS A TRADE, NOT A TUNING PROBLEM, once y is in the formula. A chevron
-- band |y + 0.45|s| - c| was swept across four offsets looking for one that
-- both straddles the light and stays unpredictable:
--     c = 0.18   J 0.40   lit 0.21     buried in the shade
--     c = 0.30   J 0.50   lit 0.57
--     c = 0.45   J 0.70   lit 1.66
--     c = 0.60   J 0.88   lit 3.31     sitting in the highlight
-- lit passes through 1 somewhere around c = 0.35, where J is already ~0.6.
-- Raising a y-dependent marking ACROSS the light boundary is the same act as
-- making it more predictable FROM height. There is no setting where it is both,
-- so the family was dropped rather than tuned. Reach for f and s instead.
--
-- WHAT THESE NUMBERS DO NOT MEASURE IS BOLDNESS. They say whether a shape can
-- be mistaken for lighting; they say nothing about how loud it is, which is
-- what a rarity ladder is actually ordering. Keep judging that by eye.
-- ===========================================================================
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

	-- THE TERMINATOR RULE, measured -- see the section of that name above.
	-- A warning, never an assert: a high score is a reason to look, not proof
	-- of a bad marking.
	SHADOW_BINS = 256,
	SHADOW_WARN = 0.80,
	-- A marking wants to STRADDLE the light, so the flag is two-sided: well
	-- under 1 means it hides in the shade and renders grey (countershade), well
	-- over 1 means it sits in the highlight and reads as a lit top (cap-tilt).
	LIT_LO = 0.50,
	LIT_HI = 2.00,

	-- Build only these variants, by name, in this order. Empty builds them all.
	-- This is what makes an A/B repeatable instead of a scratch edit: name the
	-- two you are comparing and everything else about the build is untouched.
	ONLY = {},
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
--
-- TWO OPTIONAL FIELDS, both there so a shape can be A/B'd against ITSELF with
-- everything else held fixed -- which is the only way the comparison means
-- anything, exactly as the shared white fraction is:
--     white = Color3   the accent for this variant only (default COLOUR_WHITE)
--     soft  = number   boundary half-width for this variant (default EDGE_SOFT)
-- Both were added after an A/B that found neither of them is what makes
-- countershade read as shadow. Keep them: proving a knob does NOT matter is
-- worth as much as proving one does, and it should not cost a scratch edit.
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
		-- TAKEN FOR UNCOMMON at 140 deg. At 70 the white read as a specular
		-- smear on a glossy curved body; doubling the twist makes the band
		-- visibly WRAP, and nothing about a highlight wraps. Measured against
		-- the 70 deg version side by side, both at 28% white.
		name = "stripes4",
		note = "four spiral stripes, twist 140 deg -- Uncommon",
		g = function(qx, qy, qz, f, s, y)
			return -stripeField(qx, qy, qz, 2, 0, math.rad(140), YHALF)
		end,
	},
	{
		name = "stripes2",
		note = "two wide spiral stripes, white narrower than hue",
		g = function(qx, qy, qz, f, s, y)
			return -stripeField(qx, qy, qz, 1, 0, math.rad(70), YHALF)
		end,
	},

	-- ---- candidates for Rare -------------------------------------------
	-- Between stripes4 and blaze in boldness: ONE marking rather than four,
	-- but not the whole crown. All three are shaped so their edge cuts ACROSS
	-- the light rather than lying along it, and none is a diagonal sweep.
	{
		name = "flanks",
		note = "one patch down each side, hue over spine, belly and face",
		g = function(qx, qy, qz, f, s, y)
			local l = math.sqrt(qx * qx + qy * qy + qz * qz)
			return l < 1e-9 and 9 or -(math.abs(s) / l)
		end,
	},
	{
		name = "crest",
		note = "band over the crown, stopping short of the face",
		g = function(qx, qy, qz, f, s, y)
			return math.abs(s) + 0.9 * math.max(0, f - 0.15)
		end,
	},
	-- ---- candidates for Epic -------------------------------------------
	-- Bolder than collar, quieter than blaze. The metrics push hard toward
	-- shapes defined by f and s and NOT by y: a marking that never mentions
	-- height cannot be mistaken for a height gradient, which is why these three
	-- sit at the bottom of the J column. None of them covers the face, so none
	-- changes what the creature IS the way plastron and muzzle do.
	{
		name = "mane",
		note = "ring around the face, hue inside it and behind it",
		g = function(qx, qy, qz, f, s, y)
			local l = math.sqrt(qx * qx + qy * qy + qz * qz)
			return l < 1e-9 and 9 or math.abs(f / l - 0.45)
		end,
	},
	{
		name = "brackets",
		note = "one stripe down each side of the face, hue between them",
		g = function(qx, qy, qz, f, s, y)
			local l = math.sqrt(qx * qx + qy * qy + qz * qz)
			return l < 1e-9 and 9 or math.abs(math.abs(s) / l - 0.55)
		end,
	},
	{
		name = "plastron",
		note = "tall shield down the front, from the brow to the belly",
		g = function(qx, qy, qz, f, s, y)
			local l = math.sqrt(qx * qx + qy * qy + qz * qz)
			if l < 1e-9 then return 9 end
			-- muzzle, squashed sideways: taller and narrower, so it spans the
			-- light boundary instead of sitting on one side of it
			return -(f / l) + 0.8 * (s / l) * (s / l)
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
		local soft = v.soft or P.EDGE_SOFT
		return smoothstep(-soft, soft, k - v.g(qx, qy, qz, f, s, qy))
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

	-- ===================================================================
	-- THE TERMINATOR RULE, MEASURED.
	-- All a light does is fall off monotonically from top to bottom, so "could
	-- lighting have drawn this marking?" is exactly "how well does a single
	-- height threshold predict where the white is?". This returns Youden's J of
	-- the best such threshold: 1 means a light draws it exactly, 0 means height
	-- tells you nothing at all about where the white went.
	-- ===================================================================
	local function lightFit(v, k: number): (number, number)
		local B = P.SHADOW_BINS
		local wHist, nHist = table.create(B, 0), table.create(B, 0)
		local lo, hi = math.huge, -math.huge
		for _, q in ipairs(sample) do
			if q[2] < lo then lo = q[2] end
			if q[2] > hi then hi = q[2] end
		end
		local span = math.max(hi - lo, 1e-9)
		local white, total = 0, 0
		local litWhite, litAll = 0, 0
		for si, q in ipairs(sample) do
			if si % P.TICK_EVERY == 0 then Y.tick() end
			local b = math.clamp(math.floor((q[2] - lo) / span * B), 0, B - 1) + 1
			-- the body is close enough to a sphere that the outward direction IS
			-- the normal, so lambert against a straight-down key light is q.y/|q|
			local l = math.sqrt(q[1]*q[1] + q[2]*q[2] + q[3]*q[3])
			local lit = l > 1e-9 and math.max(0, q[2] / l) or 0
			litAll += lit
			if whiteAt(v, q[1], q[2], q[3], q[4], q[5], k) > 0.5 then
				wHist[b] += 1
				white += 1
				litWhite += lit
			else
				nHist[b] += 1
			end
			total += 1
		end
		-- how lit is the marking, against how lit the body is on average? Below 1
		-- the marking sits in the shade and renders grey no matter how white the
		-- paint is -- which is countershade's whole failure, and no tone or edge
		-- setting escapes it.
		local litRatio = (white > 0 and litAll > 0)
			and (litWhite / white) / (litAll / total) or 0

		-- an all-white or all-hue body is trivially predicted by any threshold
		if white == 0 or white == total then return 1, litRatio end
		local cw, cn, best = 0, 0, 0
		for b = 1, B do
			cw += wHist[b]
			cn += nHist[b]
			local j = math.abs(cw / white - cn / (total - white))
			if j > best then best = j end
		end
		return best, litRatio
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
	local ar, ag, ab = acc.R, acc.G, acc.B  -- reassigned per variant below

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

	local build = VARIANTS
	if #P.ONLY > 0 then
		local want = {}
		for _, n in ipairs(P.ONLY) do want[n] = true end
		build = {}
		for _, n in ipairs(P.ONLY) do
			for _, v in ipairs(VARIANTS) do
				if v.name == n then table.insert(build, v) want[n] = nil break end
			end
		end
		for n in pairs(want) do
			error(string.format("[Lab] P.ONLY names %q, which is not a variant here", n))
		end
	end

	local worstPx, worstWhat = math.huge, "?"
	for vi, v in ipairs(build) do
		Y.tick()
		local k, measured = calibrate(v)
		local shadow, lit = lightFit(v, k)
		local accV = v.white or P.COLOUR_WHITE
		ar, ag, ab = accV.R, accV.G, accV.B

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

		slime:SetAttribute("ShadowAlignment", shadow)
		slime:SetAttribute("LitRatio", lit)
		log("[Lab] %2d %-17s white %.1f%% | feature %5.1f px | J %.2f | lit %.2f%s | %s",
			vi, v.name, measured * 100, widthPx, shadow, lit,
			(shadow >= P.SHADOW_WARN or lit <= P.LIT_LO or lit >= P.LIT_HI)
				and " <--" or "    ", v.note)
	end

	log("[Lab] narrowest feature: %.1f px (%s), floor is %d px",
		worstPx, worstWhat, P.MIN_FEATURE_PX)
	log("[Lab] watchdog worst hold %.1f ms | built %d variants in %.2f s",
		Y.worstMs(), #build, os.clock() - t0)
	log("[Lab] undo with workspace.%s:Destroy()", P.ROOT_NAME)

	local outStr = table.concat(lines, "\n")
	print(outStr)
	return outStr
end

return run()
