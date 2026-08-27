--!strict
-- DUMP_MESH.luau -- paste into the Studio command bar. Writes the slime body
-- mesh to a local HTTP sink so it can be evaluated OFFLINE, byte-for-byte the
-- way BUILD_LEGENDARY_PAINT's buildUVMap sees it.
--
-- NOT SHIPPING CODE. Same standing as the BUILD_* files beside it.
--
-- WHY A DUMP AND NOT A REIMPLEMENTATION. The offline evaluator has to be THE
-- SAME evaluator, or its agreement with Studio proves nothing. Everything
-- except the mesh source is already plain Luau arithmetic that Lune can run
-- unmodified; the mesh is the one thing that only exists behind
-- AssetService:CreateEditableMeshAsync. So the mesh crosses, and nothing else
-- has to.
--
-- WHAT "THE WAY buildUVMap SEES IT" MEANS, and why the ORDER is part of the
-- payload rather than an implementation detail: the rasteriser resolves two
-- faces claiming one texel by a priority test, and where that test ties, the
-- face that got there FIRST keeps the texel. So GetVertices() order and
-- GetFaces() order are inputs to the answer. They are preserved exactly:
-- vertices are written in GetVertices() order and faces reference them by
-- ORDINAL in that order, faces are written in GetFaces() order.
--
-- Both orders are stable across calls -- checked by dumping twice and
-- comparing SHA-1, which matched.
--
-- FORMAT (little-endian, all floats f32 because that is what the engine
-- stores, so the dump is lossless rather than merely precise):
--     "SLMESH01"                      8 bytes
--     u32 vertexCount, u32 faceCount
--     vertexCount x 3 f32             positions, GetVertices() order
--     faceCount   x (3 u32 + 6 f32)   vertex ordinals then the three UVs
--
-- HOW TO RUN. Start a sink that appends POST bodies to a file, e.g.
-- dev/legendary/meshsink.py, then paste this in. The mesh is ~650 KB and
-- HttpService carries it as raw bytes unaltered (verified with a 0..255
-- round-trip before trusting it).
local AssetService = game:GetService("AssetService")
local HttpService = game:GetService("HttpService")

local MESH_ID = "rbxassetid://81396785350180" -- ReplicatedStorage.Assets.Slime.slime
local SINK = "http://127.0.0.1:8731/mesh"

local em = AssetService:CreateEditableMeshAsync(Content.fromUri(MESH_ID))
local verts, faces = em:GetVertices(), em:GetFaces()

-- id -> ordinal, so the dump never carries an engine-assigned id (they are
-- large and arbitrary -- 4294967297 for the first vertex here) and the offline
-- side can index a flat array
local ord: { [number]: number } = {}
for i, id in ipairs(verts) do
	ord[id] = i - 1
end

local nv, nf = #verts, #faces
local buf = buffer.create(16 + nv * 12 + nf * 36)
buffer.writestring(buf, 0, "SLMESH01")
buffer.writeu32(buf, 8, nv)
buffer.writeu32(buf, 12, nf)

local o = 16
for _, id in ipairs(verts) do
	local p = em:GetPosition(id)
	buffer.writef32(buf, o, p.X)
	buffer.writef32(buf, o + 4, p.Y)
	buffer.writef32(buf, o + 8, p.Z)
	o += 12
end
for _, fc in ipairs(faces) do
	local fv = em:GetFaceVertices(fc)
	local fu = em:GetFaceUVs(fc)
	buffer.writeu32(buf, o, ord[fv[1]])
	buffer.writeu32(buf, o + 4, ord[fv[2]])
	buffer.writeu32(buf, o + 8, ord[fv[3]])
	o += 12
	for i = 1, 3 do
		local uv = em:GetUV(fu[i])
		buffer.writef32(buf, o, uv.X)
		buffer.writef32(buf, o + 4, uv.Y)
		o += 8
	end
end

local body = buffer.tostring(buf)
local res = HttpService:RequestAsync({
	Url = SINK,
	Method = "POST",
	Headers = { ["Content-Type"] = "application/octet-stream" },
	Body = body,
})
return string.format("mesh %s: %d verts, %d faces, %d bytes, sink said %d",
	MESH_ID, nv, nf, #body, res.StatusCode)
