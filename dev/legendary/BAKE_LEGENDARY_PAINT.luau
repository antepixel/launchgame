--!strict
-- BAKE_LEGENDARY_PAINT.luau -- run the Studio paint rig OFFLINE, under Lune,
-- and hold it against the run that is already in dev/out/legendary_paint.log.
--
--     lune run dev/legendary/BAKE_LEGENDARY_PAINT.luau
--
-- Run from the REPO ROOT. Deterministic; no sampling, no seed. Exits non-zero
-- if the offline table and the Studio table differ anywhere.
--
-- NOT SHIPPING CODE and deliberately not under src/. Same standing as the
-- BUILD_* files beside it.
--
-- ===================== WHY THIS IS A GATE AND NOT A PORT ===================
--
-- The point of an offline evaluator is to stop paying a Studio round-trip per
-- texture. That is worth nothing unless the offline evaluator IS the Studio
-- one -- and "I reimplemented it carefully" is exactly the claim that cannot
-- be settled by reading it. So this file REIMPLEMENTS NOTHING ABOUT THE PAINT.
-- It loads dev/legendary/BUILD_LEGENDARY_PAINT.luau off disk, UNMODIFIED, and
-- runs its own bytes.
--
-- What it supplies is the ENVIRONMENT: an EditableMesh backed by
-- DUMP_MESH.luau's dump, an EditableImage that keeps its pixels instead of
-- handing them to a renderer, and the handful of Instance/AssetService members
-- the build touches. Everything that decides a NUMBER -- the rasteriser, the
-- dilation, the sample stride, the bisection, the six fields, the four rules --
-- is the file's own code, not a copy of it.
--
-- THE ONE THING THE ENVIRONMENT COULD STILL GET WRONG IS THE MESH, which is
-- why the dump is byte-exact (f32 out, f32 in) and carries the engine's own
-- vertex and face ORDER: the rasteriser breaks a tie between two faces
-- claiming one texel in favour of whichever arrived first, so the order is an
-- input to the answer rather than an implementation detail.
--
-- AND THAT IS WHAT THE COMPARISON AT THE BOTTOM IS FOR. Agreement to the last
-- printed digit, across all six designs and all four rules, is the evidence
-- that the environment is faithful. One mismatched digit means it is not --
-- and means every texture baked here would have been baked by a different
-- evaluator than the one the designs were judged in.
--
-- WHAT IS EXCLUDED FROM THE COMPARISON, and it is one line: the watchdog line,
-- which reports wall-clock hold and total build time. Those are properties of
-- the machine, not of the paint. Named here rather than quietly skipped.
--
-- ========================== WHAT IT WRITES =================================
--
--   dev/out/bake/<design>.png          the 512x512 sheet -- exactly the pixels
--                                      WritePixelsBuffer was handed in Studio
--   dev/out/bake_legendary_paint.log   the offline log, beside the Studio one
--
-- The PNGs are the upload candidates. They are not a preview of the texture;
-- they ARE the texture, byte for byte what the Studio build put on the body.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local shim = require("../rbxshim")

local MESH_DUMP = "dev/out/slime_mesh.bin"
local PAINT_SRC = "dev/legendary/BUILD_LEGENDARY_PAINT.luau"
local REFERENCE = "dev/out/legendary_paint.log"
local OUT_DIR = "dev/out/bake"
local OUT_LOG = "dev/out/bake_legendary_paint.log"

-- The gate, spelled out. These are the numbers dev/out/legendary_paint.log
-- prints, and they are asserted by value as well as by whole-line comparison
-- so that a pass says them out loud instead of only implying them.
local WANT_TEXELS, WANT_PCT = "256966", "98.0"
local WANT_TIGER_K, WANT_TIGER_COV = "0.179", "44.9"

-- The source MeshPart the Studio run picked, and its two properties the build
-- reads: MeshId is what it asks AssetService for, and Size is the divisor in
-- `partScale`. Both measured off ReplicatedStorage.Assets.Slime.slime in the
-- live place, not assumed.
local SOURCE_MESH_ID = "rbxassetid://81396785350180"
local SOURCE_SIZE = shim.Vector3.new(31.672481536865234, 21.452163696289062, 31.685401916503906)

--===================== the mesh, as the engine handed it ====================--
-- Mirrors DUMP_MESH.luau's format exactly. Vertex and UV "ids" here are plain
-- ordinals: the build only ever passes an id straight back in, so what an id
-- IS does not matter -- only that the ORDER of GetVertices/GetFaces is the
-- engine's own.
local function editableMeshFromDump(path: string)
	local raw = fs.readFile(path)
	local buf = buffer.fromstring(raw)
	assert(buffer.readstring(buf, 0, 8) == "SLMESH01",
		string.format("%s is not a SLMESH01 dump", path))
	local nv = buffer.readu32(buf, 8)
	local nf = buffer.readu32(buf, 12)
	assert(buffer.len(buf) == 16 + nv * 12 + nf * 36, string.format(
		"%s is %d bytes, but %d vertices and %d faces need %d",
		path, buffer.len(buf), nv, nf, 16 + nv * 12 + nf * 36))

	local vertIds, faceIds = table.create(nv), table.create(nf)
	for i = 1, nv do
		vertIds[i] = i
	end
	for i = 1, nf do
		faceIds[i] = i
	end

	local VBASE = 16
	local FBASE = 16 + nv * 12
	local Vector3, Vector2 = shim.Vector3, shim.Vector2

	local em = {}
	function em:GetVertices()
		return vertIds
	end
	function em:GetFaces()
		return faceIds
	end
	function em:GetPosition(id: number)
		local o = VBASE + (id - 1) * 12
		return Vector3.new(
			buffer.readf32(buf, o),
			buffer.readf32(buf, o + 4),
			buffer.readf32(buf, o + 8))
	end
	function em:GetFaceVertices(fid: number)
		local o = FBASE + (fid - 1) * 36
		return {
			buffer.readu32(buf, o) + 1,
			buffer.readu32(buf, o + 4) + 1,
			buffer.readu32(buf, o + 8) + 1,
		}
	end
	-- A UV "id" is (face, corner) packed, because the dump stores UVs per face
	-- corner rather than as a shared pool. The build never inspects one.
	function em:GetFaceUVs(fid: number)
		return { fid * 4 + 1, fid * 4 + 2, fid * 4 + 3 }
	end
	function em:GetUV(uid: number)
		local fid = uid // 4
		local corner = uid - fid * 4
		local o = FBASE + (fid - 1) * 36 + 12 + (corner - 1) * 8
		return Vector2.new(buffer.readf32(buf, o), buffer.readf32(buf, o + 4))
	end
	return em, nv, nf
end

local MESH, MESH_NV, MESH_NF = editableMeshFromDump(MESH_DUMP)

--=========================== PNG, written by hand ==========================--
-- serde supplies the zlib stream; the container is three chunks and a CRC.
local CRC_TABLE: { [number]: number } = {}
for i = 0, 255 do
	local c = i
	for _ = 1, 8 do
		if bit32.band(c, 1) == 1 then
			c = bit32.bxor(0xEDB88320, bit32.rshift(c, 1))
		else
			c = bit32.rshift(c, 1)
		end
	end
	CRC_TABLE[i] = c
end

local function crc32(s: string): number
	local c = 0xFFFFFFFF
	for i = 1, #s do
		c = bit32.bxor(CRC_TABLE[bit32.band(bit32.bxor(c, string.byte(s, i)), 0xFF)], bit32.rshift(c, 8))
	end
	return bit32.bxor(c, 0xFFFFFFFF)
end

local function chunk(kind: string, data: string): string
	return string.pack(">I4", #data) .. kind .. data .. string.pack(">I4", crc32(kind .. data))
end

local function writePNG(path: string, w: number, h: number, rgba: buffer)
	-- filter byte 0 (None) in front of every scanline
	local rows = table.create(h)
	for y = 0, h - 1 do
		rows[y + 1] = "\0" .. buffer.readstring(rgba, y * w * 4, w * 4)
	end
	fs.writeFile(path, table.concat({
		"\137PNG\r\n\26\n",
		chunk("IHDR", string.pack(">I4I4BBBBB", w, h, 8, 6, 0, 0, 0)),
		chunk("IDAT", (serde.compress :: any)("zlib", table.concat(rows))),
		chunk("IEND", ""),
	}))
end

--====================== the environment the build runs in ===================--
local Instance, Vector3, Vector2 = shim.Instance, shim.Vector3, shim.Vector2
local ReplicatedStorage = shim.ReplicatedStorage
local Workspace = shim.Workspace

-- ReplicatedStorage.Assets.Slime.slime, which is what the build's own source
-- search finds first in the live place.
do
	local assets = Instance.new("Folder")
	assets.Name = "Assets"
	assets.Parent = ReplicatedStorage
	local model = Instance.new("Model")
	model.Name = "Slime"
	model.Parent = assets
	local body = Instance.new("MeshPart")
	body.Name = "slime"
	body.MeshId = SOURCE_MESH_ID
	body.Size = SOURCE_SIZE
	body.Parent = model
end

-- Every sheet the build paints, in order, so they can be written out
-- afterwards. WritePixelsBuffer COPIES: the build reuses ONE scratch buffer
-- for all six designs, so aliasing it would leave six copies of the last.
local images: { { w: number, h: number, img: any } } = {}

local AssetService = {
	CreateEditableMeshAsync = function(_self, content)
		assert(content.uri == SOURCE_MESH_ID, string.format(
			"the dump in %s is %s, but the build asked for %s",
			MESH_DUMP, SOURCE_MESH_ID, tostring(content.uri)))
		return MESH
	end,
	CreateEditableImage = function(_self, opts)
		local img = { Size = opts.Size, pixels = nil :: buffer? }
		function img:WritePixelsBuffer(_pos, _size, src)
			local copy = buffer.create(buffer.len(src))
			buffer.copy(copy, 0, src)
			self.pixels = copy
		end
		table.insert(images, { w = opts.Size.X, h = opts.Size.Y, img = img })
		return img
	end,
	-- The face parts. Their geometry is a stub -- nothing measured reads them
	-- back, they are in the Studio build so the frames have a face on -- but
	-- the part still has to accept the properties the build sets.
	CreateMeshPartAsync = function(_self, content)
		local p = Instance.new("MeshPart")
		p.MeshId = tostring(content.uri)
		p.Size = Vector3.new(1, 1, 1)
		return p
	end,
}

local Content = {
	fromUri = function(uri: string)
		return { uri = uri }
	end,
	fromObject = function(obj: any)
		return { object = obj }
	end,
}

-- SPAWNED WORK RUNS INLINE. The build spawns because execute_luau over the
-- Studio bridge is capped at ~30 s and an overrun does not stop; here there is
-- no bridge and no watchdog, so the spawned thread is the calling one and
-- `wait` is a no-op. That is why the watchdog line is the one line excluded
-- from the comparison -- it measures a yield that never happens here.
local task = {
	spawn = function(f, ...)
		f(...)
	end,
	wait = function() end,
	defer = function(f, ...)
		f(...)
	end,
}

local services: { [string]: any } = {
	ReplicatedStorage = ReplicatedStorage,
	Workspace = Workspace,
	AssetService = AssetService,
}
local fakeGame = {
	GetService = function(_self, name: string)
		local s = services[name]
		assert(s, string.format(
			"BAKE: the build asked for %s, which this environment does not stand in for", name))
		return s
	end,
}

local env = setmetatable({
	game = fakeGame,
	workspace = Workspace,
	Instance = Instance,
	Vector3 = Vector3,
	Vector2 = Vector2,
	CFrame = shim.CFrame,
	Color3 = shim.Color3,
	Enum = shim.Enum,
	Content = Content,
	task = task,
	require = function()
		error("BAKE: the paint build requires nothing, by design -- see its header")
	end,
	-- Roblox-only globals the build does not use today but that cost nothing
	-- to stand behind, so a future edit to the build fails on its own terms
	-- rather than on "attempt to index nil".
	typeof = function(v)
		return type(v)
	end,
	-- LUNE'S GLOBALS ARE NOT IN _G. Falling through to _G looks right and
	-- gives an empty table, so the build dies on `math.pi` being nil three
	-- hundred lines into a file that has nothing wrong with it. getfenv() is
	-- this driver's own environment, which does have them.
}, { __index = getfenv() })

--============================== run the build ==============================--
local source = fs.readFile(PAINT_SRC)
local chunkFn, err = loadstring(source, "@" .. PAINT_SRC)
assert(chunkFn, string.format("failed to parse %s: %s", PAINT_SRC, tostring(err)))
setfenv(chunkFn, env)

print(string.format("[Bake] mesh %s: %d vertices, %d faces, from %s",
	SOURCE_MESH_ID, MESH_NV, MESH_NF, MESH_DUMP))
print(string.format("[Bake] running %s unmodified, in a stand-in environment", PAINT_SRC))

local t0 = os.clock()
chunkFn()
local elapsed = os.clock() - t0

assert(Workspace:GetAttribute("PaintDone") == true, "BAKE: the build never finished")
local produced = tostring(Workspace:GetAttribute("PaintLog"))
print(string.format("[Bake] finished in %.1f s, %d sheets painted", elapsed, #images))

--=========================== write the sheets out ==========================--
if not fs.isDir(OUT_DIR) then
	fs.writeDir(OUT_DIR)
end
-- The build names its cells L<n>_<design> and stamps Index on each; the images
-- come out in the same order, so the two zip.
local cells = {}
for _, m in ipairs((Workspace:FindFirstChild("LegendaryPaint") :: any):GetChildren()) do
	if m.ClassName == "Model" then
		table.insert(cells, { i = m:GetAttribute("Index"), name = m:GetAttribute("Design") })
	end
end
table.sort(cells, function(a, b)
	return a.i < b.i
end)
for i, rec in ipairs(images) do
	local name = cells[i] and cells[i].name or tostring(i)
	assert(rec.img.pixels, string.format("BAKE: sheet %s was created but never written", name))
	local path = string.format("%s/%s.png", OUT_DIR, name)
	writePNG(path, rec.w, rec.h, rec.img.pixels)
	print(string.format("[Bake] %-10s -> %s (%d x %d)", name, path, rec.w, rec.h))
end
fs.writeFile(OUT_LOG, produced .. "\n")

--===================== the gate: against the Studio run ====================--
-- The reference log carries two framings of the same six designs. The build
-- here is P.FRAMING = "base", so it is the base block that has to match.
local reference = fs.readFile(REFERENCE)
local block = reference:match("==== FRAMING: base ====\n(.-)\n==== FRAMING")
	or reference:match("==== FRAMING: base ====\n(.*)$")
assert(block, string.format("no base framing block in %s", REFERENCE))

local function paintLines(text: string): { string }
	local out = {}
	for line in text:gmatch("[^\n]+") do
		-- WALL CLOCK IS NOT PAINT. The watchdog line reports hold time and
		-- total build time, both properties of the machine.
		if line:sub(1, 8) == "[Paint] " and not line:match("^%[Paint%] watchdog") then
			table.insert(out, (line:gsub("%s+$", "")))
		end
	end
	return out
end

local want, got = paintLines(block), paintLines(produced)
local failures = {}
for i = 1, math.max(#want, #got) do
	if want[i] ~= got[i] then
		table.insert(failures, string.format("  line %d\n     studio: %s\n    offline: %s",
			i, tostring(want[i]), tostring(got[i])))
	end
end

local texels, pct = "?", "?"
local tigerCov, tigerK = "?", "?"
for _, line in ipairs(got) do
	local t, p = line:match("UV map: (%d+) texels %(([%d%.]+)%% of sheet%)")
	if t then
		texels, pct = t, p
	end
	local cov, k = line:match("^%[Paint%] tiger%s+%S.-%s+([%d%.]+)%%%s+(%-?[%d%.]+)%s")
	if cov then
		tigerCov, tigerK = cov, k
	end
end

print("")
print(string.format("=== GATE 1: offline against %s, base framing ===", REFERENCE))
print(string.format("  %d comparable lines (watchdog excluded: wall clock is not paint)", #want))
print(string.format("  UV map   %s texels (%s%%)      expected %s (%s)",
	texels, pct, WANT_TEXELS, WANT_PCT))
print(string.format("  tiger    k = %s at cov %s%%   expected %s at %s",
	tigerK, tigerCov, WANT_TIGER_K, WANT_TIGER_COV))
print("")

local numbersOk = texels == WANT_TEXELS and pct == WANT_PCT
	and tigerK == WANT_TIGER_K and tigerCov == WANT_TIGER_COV
if #failures == 0 and numbersOk then
	print("  [PASS] every line identical -- the offline evaluator IS the Studio one")
	return true
end

if #failures > 0 then
	print(string.format("  [FAIL] %d of %d lines differ", #failures, math.max(#want, #got)))
	for _, f in ipairs(failures) do
		print(f)
	end
else
	print("  [FAIL] the lines match the reference log but not the gate's own numbers,")
	print("         which means the reference log is not the run this gate was written for")
end
print("")
print("  A MISS MEANS THE OFFLINE EVALUATOR IS NOT THE STUDIO ONE. Nothing")
print("  downstream of it -- no bake, no upload, no wiring -- is worth building.")
process.exit(1)
return false
