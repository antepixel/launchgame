--!strict
-- BUILD_DIVINE.luau -- STANDALONE REBUILD SCRIPT FOR THE DIVINE-TIER TREATMENT.
--
-- Paste the whole file into the Studio command bar and it reconstructs
-- workspace.DivinePrototype from nothing: all five layers, both scripts, all
-- 34 tuning attributes, and -- if it is missing -- the body model itself.
--
-- NOT SHIPPING CODE and deliberately NOT under src/ (Rojo syncs that). This is
-- a design prototype, the same standing as dev/tiermarks/BUILD_TIERMARKS.luau.
--
-- WHY THIS FILE EXISTS. The entire treatment -- 60+ parts and ~240 lines of
-- script -- lived ONLY in an open Studio session and in game.rbxlx, which
-- .gitignore excludes via `*.rbxlx`. Nothing about it was recoverable from git.
-- That is the same exposure that produced BUILD_TIERMARKS, one session after a
-- previous session lost work that existed only in memory.
--
-- ============================ WHAT WAS LEARNED =============================
--
-- THE TREATMENT IS ONE TIME FUNCTION. DivinePose.pose(t, config, baseline)
-- derives every layer's state -- body colour and squash, halo, motes, glow
-- shell, ground light -- from a single scalar t. The editor preview loop and
-- the runtime animator both call it, so they cannot drift apart. Everything
-- else in this file is scaffolding around that one function.
--
-- THE BASELINE MUST BE BAKED, NOT RE-MEASURED. This is the load-bearing trap.
-- L1_Body carries the body's UNDEFORMED rest pose as attributes. At the moment
-- this file was extracted the live body was at sy = 1.080000, i.e. u = +1.0 --
-- maximum stretch, the top of the breath. Re-measuring the body at build time
-- would bake that frame's squash in as the new rest pose, and every subsequent
-- rebuild would compound it. DivinePose.baseline's own comment names this as
-- the drift bug SlimeIdleClient documents. So BASELINE below is a constant
-- table, and the script asserts against the live body rather than reading it.
--
-- PHASE IS DERIVED, NOT INVENTED. Phase = phaseFor(rest centre), where
-- phaseFor is lifted verbatim from SlimeIdleClient -- quarter-stud
-- quantisation, +32768 offset, 65536 stride, seeded Random, first draw.
-- Verified: phaseFor(BaseX, RestY + BaseSizeY/2, BaseZ) reproduces the stored
-- 0.20121376577200081 exactly, while the body's CURRENT (mid-breath) position
-- gives 0.33839674876295744 and the rest BASE gives 0.91477394321274119. The
-- rest CENTRE is the correct argument; the other two are wrong answers that
-- would silently desynchronise the glow from the breathing.
--
-- THE STATIC POSE IS PINNED SO REBUILDS ARE COMPARABLE. The treatment is an
-- animation, so "identical" needs a fixed clock. BUILD_POSE_T is the t that
-- puts the breath at u = +1, matching the state this file was extracted from:
--     t = IdlePeriod * (0.25 - Phase) = 2 * (0.25 - 0.201213...) = 0.097572...
-- Rebuilding at that t reproduces the extracted frame property-for-property,
-- which is what makes the verification below meaningful.
--
-- MESHPARTS CANNOT BE BUILT BY WRITING MeshId. `Instance.new("MeshPart").MeshId
-- = ...` throws "cannot write 'MeshId' (lacking capability NotAccessible)".
-- The route that works from a script is
--     AssetService:CreateMeshPartAsync(Content.fromUri("rbxassetid://..."))
-- which was verified to return the body mesh at MeshSize 2.0006 x 1.3550 x
-- 2.0014. That is how both the GlowShell and the rebuilt body are made.
--
-- THE BODY IS A STRAY MODEL, NOT A LINEUP SLIME. See BODY below -- this is the
-- one real standalone risk and it is handled rather than asserted away.
--
-- KNOWN LIMITATION, DELIBERATELY NOT FIXED: with DriveIdleBreathing = true the
-- pose writes the body's Size and CFrame every frame, but eye_dark, eye_white
-- and blush are separate anchored parts that nothing moves. The face therefore
-- does not follow the breathing. Preserved as-is; fixing it is a design change,
-- not a save.
--
-- COSMETIC, PRESERVED VERBATIM: DivinePose.config repeats AccentWhiteMix and
-- ShellAccentMix three times each, and HaloWidthRatio twice, inside one table
-- constructor. Harmless -- every duplicate reads the same attribute, so the
-- last write wins with an identical value -- but it is an editing artifact. It
-- is reproduced exactly because this file is a save, not a cleanup.
--
-- IF THE STUDIO BRIDGE WILL NOT ANSWER, read dev/README.md BEFORE touching the
-- plugin. "Studio plugin connection timeout" usually does NOT mean the plugin is
-- dead -- with several sessions open there are several MCP servers, and yours may
-- simply not be the one Studio attached to.
--
-- REVERSAL: workspace.DivinePrototype:Destroy(). The body's pre-treatment
-- colour and material are recorded on L1_Body as OriginalColor / OriginalMaterial
-- (Color3 70,200,80 and Plastic -- w was a green slime before the treatment).
-- ===========================================================================

local AssetService = game:GetService("AssetService")

-- ===================================================================
-- 1. THE 34 TUNING ATTRIBUTES, exactly as extracted.
-- ===================================================================
local CONFIG = {
	-- body colour: a slow hue drift around violet
	HueBaseDeg = 268,
	HueSpanDeg = 22,
	HueDriftRate = 0.05,
	BodySaturation = 0.95,
	BodyValue = 0.42,

	-- the gold accent shared by halo and motes
	AccentColor = Color3.fromRGB(255, 198, 92),
	AccentWhiteMix = 0.1,
	ShellAccentMix = 0.4,

	-- halo: 48 tapered Neon blades on a tilted, rolling ring
	HaloSegments = 48,
	HaloRadius = 158,
	HaloHeightStuds = 40,
	HaloSpeed = 0.06,
	HaloTiltDeg = 12,
	HaloThickMin = 4,
	HaloThickMax = 9,
	HaloGapFraction = 0.12,
	HaloRollDeg = 18,
	HaloWidthRatio = 1.35,

	-- motes: 7 spheres on golden-angle, non-coplanar inclined orbits
	MoteCount = 7,
	MoteRadiusMin = 300,
	MoteRadiusMax = 400,
	MoteSpeed = 0.045,
	MoteSize = 20,
	MoteInclineMinDeg = 18,
	MoteInclineMaxDeg = 80,

	-- glow shell + ground light, both on the breath's clock
	PulseDepth = 0.6,
	ShellInflate = 0.045,
	ShellTransparency = 0.8,
	LightRange = 60,
	LightBrightness = 14,
	LightHeightStuds = 18,   -- was hardcoded inside the pose source; it is a LENGTH

	-- the breath itself, shared with SlimeIdleClient
	IdleAmplitude = 0.08,
	IdlePeriod = 2,

	-- wiring
	BodyModelName = "w",
	DriveIdleBreathing = true,
}

-- ===================================================================
-- 1b. BODY PROFILES -- the same treatment on bodies of different size.
--
-- Every length in CONFIG above is authored against the GIANT (workspace.w,
-- 334.42 studs across). A lineup slime is 14.00 across, a uniform 1/23.89, so
-- those numbers have to come down or the halo swallows the slime. They are
-- SCALED HERE rather than copied into a second file, because two copies of the
-- pose maths is exactly how two versions drift apart.
--
-- WHAT SCALES AND WHAT DOES NOT is the entire content of this block:
--   * LENGTHS scale with the body -- HaloRadius, HaloHeightStuds, MoteRadiusMin,
--     MoteRadiusMax, LightRange, LightHeightStuds, the blade thicknesses, MoteSize.
--   * NOTHING ELSE DOES. Every colour, every angle (HaloTiltDeg, HaloRollDeg,
--     MoteInclineMin/MaxDeg), every ratio (HaloGapFraction, HaloWidthRatio,
--     PulseDepth, ShellInflate, ShellTransparency, IdleAmplitude), every rate
--     (HaloSpeed, MoteSpeed, HueDriftRate, IdlePeriod), and MoteCount are already
--     dimensionless.
--
-- TWO ARE EASY TO GET WRONG, so they are named. ShellInflate is a FRACTION of
-- body size -- the pose multiplies it into b.size -- so scaling it would shrink
-- the shell twice. LightBrightness is an INTENSITY, not a distance; with the
-- geometry scaled uniformly the same value lands the same illumination, and
-- dividing it would dim the base glow for no reason.
--
-- THIN FEATURES NEED MORE THAN THE SCALE FACTOR. A straight divide is
-- geometrically right and visually wrong once a feature stops resolving. At 40
-- studs and FOV 70 the frame is ~10 px per stud, so a blade at 4 / 23.89 = 0.17
-- studs is a 1.7 px sliver that aliases instead of reading as a shape. ThinBoost
-- and MoteBoost lift those back over the threshold. Both are 1 on the giant,
-- where nothing is anywhere near it.
-- ===================================================================
local REFERENCE_WIDTH = 334.4164733886719   -- the giant's BaseSizeX; CONFIG is authored for this

local PROFILES = {
	giant = {
		RootName = "DivinePrototype",
		BodyModelName = "w",
		HaloSegments = 48,
		ThinBoost = 1,
		MoteBoost = 1,
		PhaseExpect = 0.20121376577200081,
		Baseline = {
			BaseSizeX = 334.4164733886719,
			BaseSizeY = 226.50440979003906,
			BaseSizeZ = 334.5528869628906,
			BaseX = 78.52466583251953,
			BaseZ = 240.9720916748047,
			RestY = -5.515754699707031,
			OriginalColor = Color3.fromRGB(70, 200, 80),
			OriginalMaterial = "Plastic",
		},
	},
	lineup = {
		RootName = "DivineSmall",
		BodyModelName = "w_small",
		-- 48 BLADES DO NOT SURVIVE THE SHRINK, and faceting is not why. The
		-- sagitta at 24 segments on a 6.61 radius is R*(1-cos(pi/24)) = 0.057
		-- studs, well under a pixel -- even 16 would still look round. The GAPS
		-- are the constraint: at 48 the chord is 0.865 studs and the 12% gap is
		-- 0.104 studs, about 1 px, so the blades merge and the ring renders as a
		-- thin washed-out outline instead of a struck crown. At 24 the gap is 2.1
		-- px and the taper reads. Verified by building both and comparing.
		HaloSegments = 24,
		ThinBoost = 2,
		MoteBoost = 1.5,
		PhaseExpect = 0.49993847500041505,
		Baseline = {
			BaseSizeX = 14.000000,
			BaseSizeY = 9.482373,
			BaseSizeZ = 14.005711,
			BaseX = -140.000000,
			BaseZ = 0.000000,
			RestY = 0.000000,
			OriginalColor = Color3.fromRGB(225, 60, 60),
			OriginalMaterial = "Plastic",
		},
	},
}

-- CHANGE THIS LINE to retarget the treatment. Nothing else needs editing.
local ACTIVE_PROFILE = "giant"

local PROFILE = PROFILES[ACTIVE_PROFILE]
assert(PROFILE, string.format("[Divine] unknown profile %q", tostring(ACTIVE_PROFILE)))

-- Exactly 1.0 on the giant, so that path stays bit-identical to before profiles.
local BODY_SCALE = PROFILE.Baseline.BaseSizeX / REFERENCE_WIDTH

CONFIG.BodyModelName = PROFILE.BodyModelName
CONFIG.HaloSegments = PROFILE.HaloSegments
for _, k in ipairs({
	"HaloRadius", "HaloHeightStuds", "MoteRadiusMin", "MoteRadiusMax",
	"LightRange", "LightHeightStuds",
}) do
	CONFIG[k] = CONFIG[k] * BODY_SCALE
end
CONFIG.HaloThickMin = CONFIG.HaloThickMin * BODY_SCALE * PROFILE.ThinBoost
CONFIG.HaloThickMax = CONFIG.HaloThickMax * BODY_SCALE * PROFILE.ThinBoost
CONFIG.MoteSize = CONFIG.MoteSize * BODY_SCALE * PROFILE.MoteBoost

-- ===================================================================
-- 2. THE BAKED BASELINE. See the header -- never re-measure this.
-- Phase is omitted deliberately: it is DERIVED from the rest centre below and
-- checked against PHASE_EXPECT, so a wrong baseline cannot pass silently.
-- ===================================================================
local BASELINE = PROFILE.Baseline
local PHASE_EXPECT = PROFILE.PhaseExpect

-- ===================================================================
-- 3. THE BODY. workspace.w is NOT a lineup slime: it sits directly under
-- Workspace, carries an RBX_ReimportId attribute (so it came from Studio's 3D
-- importer, not from ReplicatedStorage.SlimeBuilder), and is ~23x the lineup
-- scale -- its slime part is 321.79 studs across against the lineup's 14.00.
-- That scale is why every tuning number here is large: HaloRadius 158,
-- MoteRadiusMax 400, a 345-stud glow shell.
--
-- It does share all four part names and all four MeshIds with a lineup slime,
-- so it is the same asset, just imported separately and huge.
--
-- Rather than assert it exists, the four parts are baked below and rebuilt if
-- missing -- otherwise this file would not be standalone, it would be standalone
-- *given an untracked model that also only exists in the open session*.
-- ===================================================================
local BODY_PARTS = {
	{
		name = "slime",
		mesh = "rbxassetid://114522325695786",
		size = Vector3.new(321.7923889160156, 244.624755859375, 321.9236755371094),
		cf = CFrame.new(78.524666, 116.796623, 240.972092),
		color = Color3.fromRGB(53, 5, 107),
		material = Enum.Material.SmoothPlastic,
	},
	{
		name = "eye_dark",
		mesh = "rbxassetid://81454373295475",
		size = Vector3.new(126.9738540649414, 88.44304656982422, 109.00762176513672),
		cf = CFrame.new(-5.965660, 113.865112, 134.734650),
		color = Color3.fromRGB(18, 18, 28),
		material = Enum.Material.Plastic,
	},
	{
		name = "eye_white",
		mesh = "rbxassetid://109111264562266",
		size = Vector3.new(109.96114349365234, 41.012264251708984, 89.38703918457031),
		cf = CFrame.new(-15.665916, 130.074097, 122.482391),
		color = Color3.fromRGB(255, 255, 255),
		material = Enum.Material.Plastic,
	},
	{
		name = "blush",
		mesh = "rbxassetid://83359732401472",
		size = Vector3.new(171.75306701660156, 22.695573806762695, 139.14414978027344),
		cf = CFrame.new(-0.855370, 78.353149, 140.911179),
		color = Color3.fromRGB(222, 66, 114),
		material = Enum.Material.Plastic,
	},
}

-- ===================================================================
-- 4. DivinePose -- VERBATIM. Do not tidy: see the header on the duplicated
-- config keys. This is the whole treatment; everything else is scaffolding.
-- ===================================================================
local DIVINE_POSE_SOURCE = [==[
--!strict
-- DIVINE-TIER TREATMENT -- THE SINGLE TIME FUNCTION (2a).
-- Every layer's state -- body colour and squash, halo, motes, glow shell,
-- ground light -- is derived here from one scalar t. Same structure as the
-- palm tree: geometry and motion in one module, so the editor preview loop
-- and the runtime client animator read the identical function and cannot
-- drift apart.
local DivinePose = {}
local TAU = 2 * math.pi

-- PHASE, LIFTED VERBATIM FROM SlimeIdleClient.phaseFor (1d).
-- Not guessed and not re-derived: quarter-stud quantisation, +32768 offset,
-- 65536 stride per axis, seeded Random, first draw. If this drifts from that
-- file the glow desynchronises from the breathing, so it is copied exactly.
function DivinePose.phaseFor(p: Vector3): number
	local qx = math.round(p.X * 4) + 32768
	local qy = math.round(p.Y * 4) + 32768
	local qz = math.round(p.Z * 4) + 32768
	return Random.new(qx + qy * 65536 + qz * 65536 * 65536):NextNumber()
end

function DivinePose.config(root: Instance)
	local function g(n: string) return root:GetAttribute(n) end
	return {
		HueBaseDeg = g("HueBaseDeg"), HueSpanDeg = g("HueSpanDeg"),
		HueDriftRate = g("HueDriftRate"),
		BodySaturation = g("BodySaturation"), BodyValue = g("BodyValue"),
		AccentColor = g("AccentColor"), AccentWhiteMix = g("AccentWhiteMix"), ShellAccentMix = g("ShellAccentMix"), AccentWhiteMix = g("AccentWhiteMix"), ShellAccentMix = g("ShellAccentMix"), AccentWhiteMix = g("AccentWhiteMix"), ShellAccentMix = g("ShellAccentMix"),
		HaloSegments = g("HaloSegments"), HaloRadius = g("HaloRadius"),
		HaloHeightStuds = g("HaloHeightStuds"), HaloSpeed = g("HaloSpeed"),
		HaloTiltDeg = g("HaloTiltDeg"), HaloThickMin = g("HaloThickMin"),
		HaloThickMax = g("HaloThickMax"), HaloGapFraction = g("HaloGapFraction"),
		HaloRollDeg = g("HaloRollDeg"), HaloWidthRatio = g("HaloWidthRatio"), HaloWidthRatio = g("HaloWidthRatio"),
		MoteCount = g("MoteCount"), MoteRadiusMin = g("MoteRadiusMin"),
		MoteRadiusMax = g("MoteRadiusMax"), MoteSpeed = g("MoteSpeed"),
		MoteSize = g("MoteSize"), MoteInclineMinDeg = g("MoteInclineMinDeg"),
		MoteInclineMaxDeg = g("MoteInclineMaxDeg"),
		PulseDepth = g("PulseDepth"), ShellInflate = g("ShellInflate"),
		ShellTransparency = g("ShellTransparency"),
		LightRange = g("LightRange"), LightBrightness = g("LightBrightness"),
		LightHeightStuds = g("LightHeightStuds"),
		IdleAmplitude = g("IdleAmplitude"), IdlePeriod = g("IdlePeriod"),
	}
end

-- The undeformed baseline, captured once at build time onto L1_Body and never
-- re-measured -- re-measuring a mid-breath slime bakes that frame's squash in
-- as the new rest pose, which is the exact drift bug SlimeIdleClient documents.
function DivinePose.baseline(l1: Instance)
	local function g(n: string) return l1:GetAttribute(n) end
	return {
		size = Vector3.new(g("BaseSizeX"), g("BaseSizeY"), g("BaseSizeZ")),
		x = g("BaseX"), z = g("BaseZ"), restY = g("RestY"), phase = g("Phase"),
	}
end

local function fract(x: number): number return x - math.floor(x) end

-- THE ONE FUNCTION. t is os.clock().
function DivinePose.pose(t: number, c, b)
	-- ===== THE BREATH (1d) =====
	-- u is the raw -1..1 breath signal; sy is EXACTLY SlimeIdleClient's
	-- sy = 1 + amplitude * sin(TAU * (cycles + phase)), and every glow term
	-- below is a function of that same u -- so the light swells on the body's
	-- own clock, in phase, by construction rather than by tuning.
	local u = math.sin(TAU * (t / c.IdlePeriod + b.phase))
	local sy = 1 + c.IdleAmplitude * u
	local sxz = 1 / math.sqrt(sy)          -- volume conservation, not 2 - sy
	local topY = b.restY + b.size.Y * sy   -- live top of the body
	local midY = b.restY + b.size.Y * sy / 2

	-- base stays planted: writing Size holds the CENTRE, so re-derive it
	local bodyCFrame = CFrame.new(b.x, midY, b.z)

	-- ===== 1a: hue drift =====
	local hue = fract((c.HueBaseDeg + c.HueSpanDeg * math.sin(TAU * t * c.HueDriftRate)) / 360)
	local bodyColor = Color3.fromHSV(hue, c.BodySaturation, c.BodyValue)

	-- accent brightens toward white on the stretch half of the breath
	local lift = math.clamp(0.5 + 0.5 * u, 0, 1) * c.PulseDepth
	local accent = c.AccentColor:Lerp(Color3.new(1, 1, 1), c.AccentWhiteMix * lift)

	-- ===== 1b: halo =====
	local halo = table.create(c.HaloSegments)
	local haloCentre = Vector3.new(b.x, topY + c.HaloHeightStuds, b.z)
	local tilt = CFrame.Angles(math.rad(c.HaloTiltDeg), 0, 0)
	local spin = TAU * t * c.HaloSpeed
	local chord = 2 * c.HaloRadius * math.sin(math.pi / c.HaloSegments)
	local segLen = chord * (1 - c.HaloGapFraction)
	for i = 1, c.HaloSegments do
		local a = spin + TAU * (i - 1) / c.HaloSegments
		-- taper: one full cycle of thickness around the ring, so it reads as a
		-- struck blade crown rather than a uniform tube
		local thick = c.HaloThickMin + (c.HaloThickMax - c.HaloThickMin) * (0.5 + 0.5 * math.cos(a))
		local roll = math.rad(c.HaloRollDeg) * math.sin(a)
		local cf = CFrame.new(haloCentre)
			* tilt
			* CFrame.new(math.cos(a) * c.HaloRadius, 0, math.sin(a) * c.HaloRadius)
			* CFrame.Angles(0, -a, 0)
			* CFrame.Angles(0, 0, roll)
		halo[i] = { cf = cf, size = Vector3.new(thick * c.HaloWidthRatio, thick, segLen) }
	end

	-- ===== 1c: motes on genuinely inclined, non-coplanar orbits =====
	-- Each orbit is a plane spanned by U (in XZ) and V (tilted out of it by
	-- the inclination), so no two motes share a plane and none of them are on
	-- the flat ring the halo already occupies.
	local motes = table.create(c.MoteCount)
	local orbitCentre = Vector3.new(b.x, midY, b.z)
	local n = c.MoteCount
	for i = 1, n do
		local k = i - 1
		local omega = math.rad(k * 137.507)                       -- golden angle
		local incl = math.rad(c.MoteInclineMinDeg
			+ (c.MoteInclineMaxDeg - c.MoteInclineMinDeg) * (k / math.max(1, n - 1)))
		local radius = c.MoteRadiusMin
			+ (c.MoteRadiusMax - c.MoteRadiusMin) * fract(k * 0.618034)
		local phase = fract(k * 0.618034 + 0.37)
		local speed = c.MoteSpeed * (0.8 + 0.4 * fract(k * 0.381966))
		local a = TAU * (t * speed + phase)
		local U = Vector3.new(math.cos(omega), 0, math.sin(omega))
		local V = Vector3.new(
			-math.sin(omega) * math.cos(incl),
			math.sin(incl),
			math.cos(omega) * math.cos(incl)
		)
		local p = orbitCentre + (U * math.cos(a) + V * math.sin(a)) * radius
		local sz = c.MoteSize * (1 + 0.25 * c.PulseDepth * u)
		motes[i] = { cf = CFrame.new(p), size = Vector3.new(sz, sz, sz) }
	end

	-- ===== 1d: glow shell swells with the same u =====
	local inflate = 1 + c.ShellInflate * (1 + c.PulseDepth * u)
	local shell = {
		cf = bodyCFrame,
		size = Vector3.new(
			b.size.X * sxz * inflate,
			b.size.Y * sy * inflate,
			b.size.Z * sxz * inflate
		),
		transparency = math.clamp(c.ShellTransparency - 0.12 * c.PulseDepth * u, 0, 1),
		color = bodyColor:Lerp(c.AccentColor, c.ShellAccentMix),
	}

	-- ===== 1e: ground light, same clock again =====
	local light = {
		cf = CFrame.new(b.x, b.restY + c.LightHeightStuds, b.z),
		brightness = c.LightBrightness * (1 + 0.5 * c.PulseDepth * u),
		range = c.LightRange,
		color = bodyColor:Lerp(Color3.new(1, 1, 1), 0.35),
	}

	return {
		sy = sy, sxz = sxz, u = u,
		bodyCFrame = bodyCFrame,
		bodySize = Vector3.new(b.size.X * sxz, b.size.Y * sy, b.size.Z * sxz),
		bodyColor = bodyColor,
		accent = accent,
		halo = halo, motes = motes, shell = shell, light = light,
	}
end

-- Applies a pose to the actual instances. Shared by the editor preview loop
-- and the runtime client animator so there is one apply path, not two.
-- driveBody is false at runtime: SlimeIdleClient already owns the body's
-- Size/CFrame there, and two writers would fight.
function DivinePose.apply(root: Instance, p, driveBody: boolean)
	local model = workspace:FindFirstChild(root:GetAttribute("BodyModelName"))
	local body = model and model:FindFirstChild("slime")
	if body then
		body.Color = p.bodyColor
		if driveBody then
			body.Size = p.bodySize
			body.CFrame = p.bodyCFrame
		end
	end

	local halo = root:FindFirstChild("L2_Halo")
	if halo then
		local kids = halo:GetChildren()
		for i, seg in ipairs(kids) do
			local s = p.halo[i]
			if s then seg.CFrame = s.cf; seg.Size = s.size; seg.Color = p.accent end
		end
	end

	local motes = root:FindFirstChild("L3_Motes")
	if motes then
		for i, mo in ipairs(motes:GetChildren()) do
			local s = p.motes[i]
			if s then mo.CFrame = s.cf; mo.Size = s.size; mo.Color = p.accent end
		end
	end

	local pulse = root:FindFirstChild("L4_Pulse")
	local shell = pulse and pulse:FindFirstChild("GlowShell")
	if shell then
		shell.Size = p.shell.size
		shell.CFrame = p.shell.cf
		shell.Transparency = p.shell.transparency
		shell.Color = p.shell.color
	end

	local gl = root:FindFirstChild("L5_GroundLight")
	local anchor = gl and gl:FindFirstChild("LightAnchor")
	if anchor then
		anchor.CFrame = p.light.cf
		local pl = anchor:FindFirstChild("GroundLight")
		if pl then
			pl.Brightness = p.light.brightness
			pl.Range = p.light.range
			pl.Color = p.light.color
		end
	end
end

return DivinePose
]==]

-- ===================================================================
-- 5. DivineAnimator -- VERBATIM. RunContext = Client; see its own header.
-- ===================================================================
local DIVINE_ANIMATOR_SOURCE = [==[
--!strict
-- CLIENT ONLY (2b). Anchored parts do not replicate smoothly, so a server-side
-- per-frame CFrame write on any of this would stutter for every client but the
-- host -- the same reason the six-lane remote rendering fix exists, and the
-- same reason SlimeIdleClient is a LocalScript. RunContext = Client.
--
-- Reads its motion from DivinePose, the identical module the editor preview
-- loop uses, so the two can never disagree.
local RunService = game:GetService("RunService")
local root = script.Parent
local DivinePose = require(root:WaitForChild("DivinePose"))

local l1 = root:WaitForChild("L1_Body")
local baseline = DivinePose.baseline(l1)

RunService.RenderStepped:Connect(function()
	local cfg = DivinePose.config(root)
	local pose = DivinePose.pose(os.clock(), cfg, baseline)
	-- driveBody follows the attribute: false wherever SlimeIdleClient is
	-- already animating this body, so there is exactly one writer.
	DivinePose.apply(root, pose, root:GetAttribute("DriveIdleBreathing") == true)
end)
]==]

-- ===================================================================
-- 6. BUILD.
-- ===================================================================
local ROOT_NAME = PROFILE.RootName

-- phaseFor, needed here to DERIVE Phase at build time. Same function as the
-- module's; duplicated because the module does not exist yet when this runs.
local function phaseFor(p: Vector3): number
	local qx = math.round(p.X * 4) + 32768
	local qy = math.round(p.Y * 4) + 32768
	local qz = math.round(p.Z * 4) + 32768
	return Random.new(qx + qy * 65536 + qz * 65536 * 65536):NextNumber()
end

local function dressPart(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
end

local function ensureBody(lines: { string })
	local model = workspace:FindFirstChild(CONFIG.BodyModelName)
	if model then
		table.insert(lines, string.format(
			"[Divine] body model workspace.%s found -- reused, not rebuilt", CONFIG.BodyModelName))
		return model
	end

	table.insert(lines, string.format(
		"[Divine] workspace.%s MISSING -- rebuilding it from baked mesh data", CONFIG.BodyModelName))
	-- BODY_PARTS are baked in the GIANT's coordinates, so any other profile has to
	-- bring them down and move them. Scale about the giant's REST CENTRE rather
	-- than repositioning each part independently -- the four parts' relative
	-- layout is what puts the face on the body, and moving them separately would
	-- leave the eyes floating off it.
	local gb = PROFILES.giant.Baseline
	local srcCentre = Vector3.new(gb.BaseX, gb.RestY + gb.BaseSizeY / 2, gb.BaseZ)
	local dstCentre = Vector3.new(
		BASELINE.BaseX, BASELINE.RestY + BASELINE.BaseSizeY / 2, BASELINE.BaseZ)
	local identity = BODY_SCALE == 1 and dstCentre == srcCentre

	model = Instance.new("Model")
	model.Name = CONFIG.BodyModelName
	for _, spec in ipairs(BODY_PARTS) do
		-- MeshId is not writable from a script; this is the route that works
		local part = AssetService:CreateMeshPartAsync(Content.fromUri(spec.mesh))
		part.Name = spec.name
		if identity then
			-- take the baked values untouched, so the giant cannot drift by a
			-- rounding step just because the scaling path exists
			part.Size = spec.size
			part.CFrame = spec.cf
		else
			part.Size = spec.size * BODY_SCALE
			part.CFrame = (spec.cf - spec.cf.Position)
				+ (dstCentre + (spec.cf.Position - srcCentre) * BODY_SCALE)
		end
		part.Color = spec.color
		part.Material = spec.material
		part.Anchored = true
		part.CanCollide = false
		part.Parent = model
	end
	model.PrimaryPart = model:FindFirstChild("slime") :: BasePart
	model.Parent = workspace
	return model
end

local function run()
	local lines = {}

	-- REMOVE ALL, not just the first. FindFirstChild returns one match, so a
	-- self-clean built on it leaves duplicates behind on the second run -- the
	-- exact bug that produced two workspace.TierMarks folders.
	local removed = 0
	for _, c in ipairs(workspace:GetChildren()) do
		if c.Name == ROOT_NAME then c:Destroy(); removed += 1 end
	end
	if removed > 0 then
		table.insert(lines, string.format("[Divine] removed %d existing %s folder(s)", removed, ROOT_NAME))
	end

	local model = ensureBody(lines)
	local body = model:FindFirstChild("slime") :: BasePart
	assert(body, "[Divine] body model has no part named 'slime'")

	local root = Instance.new("Folder")
	root.Name = ROOT_NAME
	root.Parent = workspace
	for k, v in pairs(CONFIG) do
		root:SetAttribute(k, v)
	end

	-- ---- L1_Body: the baked baseline, plus the DERIVED phase ----
	local l1 = Instance.new("Folder")
	l1.Name = "L1_Body"
	l1.Parent = root
	for k, v in pairs(BASELINE) do
		l1:SetAttribute(k, v)
	end
	local restCentre = Vector3.new(
		BASELINE.BaseX,
		BASELINE.RestY + BASELINE.BaseSizeY / 2,
		BASELINE.BaseZ
	)
	local phase = phaseFor(restCentre)
	l1:SetAttribute("Phase", phase)
	assert(math.abs(phase - PHASE_EXPECT) < 1e-12, string.format(
		"[Divine] Phase derived %.17f but expected %.17f -- the baseline rest centre "
			.. "has moved, and the glow would desynchronise from the breathing.",
		phase, PHASE_EXPECT))
	table.insert(lines, string.format(
		"[Divine] L1_Body baseline baked; Phase derived = %.17f (matches)", phase))

	-- ---- L2_Halo: HaloSegments tapered Neon blades ----
	local l2 = Instance.new("Folder")
	l2.Name = "L2_Halo"
	l2.Parent = root
	for i = 1, CONFIG.HaloSegments do
		local seg = Instance.new("Part")
		seg.Name = string.format("Seg%02d", i)
		seg.Shape = Enum.PartType.Block
		seg.Material = Enum.Material.Neon
		seg.Color = CONFIG.AccentColor
		dressPart(seg)
		seg.Parent = l2
	end

	-- ---- L3_Motes: MoteCount Neon spheres ----
	local l3 = Instance.new("Folder")
	l3.Name = "L3_Motes"
	l3.Parent = root
	for i = 1, CONFIG.MoteCount do
		local mo = Instance.new("Part")
		mo.Name = "Mote" .. i
		mo.Shape = Enum.PartType.Ball
		mo.Material = Enum.Material.Neon
		mo.Color = CONFIG.AccentColor
		mo.Size = Vector3.new(CONFIG.MoteSize, CONFIG.MoteSize, CONFIG.MoteSize)
		dressPart(mo)
		mo.Parent = l3
	end

	-- ---- L4_Pulse: the glow shell, the body's own mesh blown up ----
	local l4 = Instance.new("Folder")
	l4.Name = "L4_Pulse"
	l4.Parent = root
	local shell = AssetService:CreateMeshPartAsync(Content.fromUri(BODY_PARTS[1].mesh))
	shell.Name = "GlowShell"
	shell.Material = Enum.Material.Neon
	shell.Transparency = CONFIG.ShellTransparency
	dressPart(shell)
	shell.Parent = l4

	-- ---- L5_GroundLight ----
	local l5 = Instance.new("Folder")
	l5.Name = "L5_GroundLight"
	l5.Parent = root
	local anchor = Instance.new("Part")
	anchor.Name = "LightAnchor"
	anchor.Shape = Enum.PartType.Block
	anchor.Size = Vector3.new(2, 2, 2)
	anchor.Transparency = 1
	anchor.Material = Enum.Material.Plastic
	anchor.Color = Color3.fromRGB(163, 162, 165)
	dressPart(anchor)
	anchor.Parent = l5
	local light = Instance.new("PointLight")
	light.Name = "GroundLight"
	light.Range = CONFIG.LightRange
	light.Brightness = CONFIG.LightBrightness
	light.Shadows = false
	light.Parent = anchor

	-- ---- the two scripts ----
	local pose = Instance.new("ModuleScript")
	pose.Name = "DivinePose"
	pose.Source = DIVINE_POSE_SOURCE
	pose.Parent = root

	local animator = Instance.new("Script")
	animator.Name = "DivineAnimator"
	animator.RunContext = Enum.RunContext.Client
	animator.Source = DIVINE_ANIMATOR_SOURCE
	animator.Parent = root

	-- ---- record the body's pre-treatment look, then apply the treatment ----
	body.Material = Enum.Material.SmoothPlastic

	-- ---- pin the static pose so rebuilds are comparable (see header) ----
	local BUILD_POSE_T = CONFIG.IdlePeriod * (0.25 - phase)
	local DivinePose = require(pose) :: any
	local cfg = DivinePose.config(root)
	local base = DivinePose.baseline(l1)
	local p = DivinePose.pose(BUILD_POSE_T, cfg, base)
	DivinePose.apply(root, p, CONFIG.DriveIdleBreathing == true)

	table.insert(lines, string.format(
		"[Divine] L2_Halo %d segs | L3_Motes %d | L4_Pulse GlowShell | L5_GroundLight",
		CONFIG.HaloSegments, CONFIG.MoteCount))
	table.insert(lines, string.format(
		"[Divine] posed at t = %.17f (breath u = %+.6f)", BUILD_POSE_T, p.u))
	local attrN = 0
	for _ in pairs(CONFIG) do attrN += 1 end
	table.insert(lines, string.format(
		"[Divine] done: %d attributes, 5 layers, 2 scripts. Undo with workspace.%s:Destroy()",
		attrN, ROOT_NAME))

	local outStr = table.concat(lines, "\n")
	print(outStr)
	return outStr
end

return run()
