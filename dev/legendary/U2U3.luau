--!strict
-- U2U3.luau -- THE HAND-ASSIGNMENT. Puts the baked tiger sheet onto a real
-- body in Studio and answers the two questions that decide the wiring.
--
-- Paste the whole file into the Studio command bar. It rebuilds
-- workspace.U3Test from nothing and aims the edit camera at it. No other file
-- needs to be present -- but dev/legendary/meshsink.py has to be running from
-- the repo root for the SINK path (see below).
--
-- NOT SHIPPING CODE and deliberately NOT under src/ (Rojo syncs that). Same
-- standing as the BUILD_ and AIM scripts beside it.
--
-- ============================== THE TWO QUESTIONS ==========================
--
-- U2 -- DOES THE BAKE SURVIVE THE ROUND TRIP? The offline rig
-- (BAKE_LEGENDARY_PAINT.luau) proved it computes the same NUMBERS as Studio,
-- line for line. That is not the same as proving the PIXELS it writes end up
-- on the body looking like the sheet: the bake writes a PNG, the PNG becomes
-- an asset, the asset becomes a texture, and each of those steps could be
-- lying. So the sheet goes on a body and gets looked at.
--
-- U3 -- DOES MeshPart.Color STILL TINT A TEXTURED BODY? This is the whole
-- question, and it is worth one line of code either way:
--
--     SlimeBuilder.build does `body.Color = color`.
--
-- If Color multiplies the texture, then a Legendary's per-slime hue would
-- multiply INTO the painted sheet and every one of the six would come out
-- muddied by a colour that has nothing to do with its design -- so the line
-- has to become white-when-skinned. If Color is ignored once a texture is
-- bound, the line stays exactly as it is and the per-slime colour simply
-- stops being visible for painted tiers, which is correct by itself.
--
-- THE TEST IS TWO BODIES SIDE BY SIDE WITH THE SAME TEXTURE, one Color white
-- and one Color red. Nothing else differs. If the right-hand slime's tangerine
-- comes out dark red, Color multiplies. If the two are indistinguishable,
-- it does not.
--
-- A CONTROL IS IN THE FRAME ON PURPOSE: a third body, red, with NO texture.
-- Without it a "the two look the same" reading cannot tell "Color is ignored"
-- apart from "the texture never bound at all", which look identical when the
-- texture fails to load and the body falls back to... its Color. That is the
-- failure this control exists to separate, and it is exactly the shape
-- dev/README.md warns about: a reading that stays computable after the thing
-- it described stopped being there.
--
-- ========================= TWO WAYS TO GET THE SHEET =======================
--
-- SOURCE = "sink" -- no upload, no asset id. Studio GETs the raw RGBA from
-- dev/legendary/meshsink.py (which decodes dev/out/bake/tiger.png) and writes
-- it straight into an EditableImage. This settles U3 completely and settles
-- the PIXELS half of U2, because the bytes on the body are the bytes the bake
-- wrote -- the script checks that with a byte sum rather than trusting it.
--
-- SOURCE = "asset" -- the real shipping path. Set UPLOADED_TEXTURE_ID to the
-- uploaded image's asset id and it binds that instead. This is the half of U2
-- the sink cannot answer: whether an UPLOADED asset renders the same as the
-- bytes did.
--
-- "both" builds both rows, which is the whole answer in one frame.
--
-- REVERSAL: workspace.U3Test:Destroy(), and paste AIM.luau with INDEX = 0 to
-- hand the camera back (or set RELEASE_CAMERA = true here and re-paste).
local AssetService = game:GetService("AssetService")
local HttpService = game:GetService("HttpService")

local P = {
	ROOT_NAME = "U3Test",

	-- "sink" | "asset" | "both"
	SOURCE = "sink",
	SINK_URL = "http://127.0.0.1:8731/rgba/tiger",
	-- The uploaded image asset. "" means the asset row is skipped.
	UPLOADED_TEXTURE_ID = "",

	TEX = 512,
	-- 512 x 512 RGBA, and the byte sum the bake wrote. Both are checked rather
	-- than assumed: a texture that arrives short or scrambled would still bind
	-- and still render something.
	EXPECT_BYTES = 512 * 512 * 4,
	EXPECT_BYTESUM = 150405167,

	BODY_WIDTH_STUDS = 10,
	SPACING = 16,
	-- Same yaw the paint rig builds its cells at, so this frame is comparable
	-- to the LegendaryPaint cells rather than being its own arbitrary angle.
	BODY_YAW_DEG = 179.4,
	CENTRE_Y = 6,
	CELL_Z = -1600,

	GRASS = Color3.fromRGB(104, 198, 78),
	WHITE = Color3.new(1, 1, 1),
	RED = Color3.new(1, 0, 0),

	FOV = 70,
	DISTANCE = 46,
	RELEASE_CAMERA = false,

	SOURCE_MODELS = { "Slime", "AuxScene", "slime_uv" },
}

local out = {}
local function log(...)
	table.insert(out, string.format(...))
end

local function run(): string
	local cam = workspace.CurrentCamera
	if P.RELEASE_CAMERA then
		cam.CameraType = Enum.CameraType.Fixed
		local msg = "[U2U3] camera handed back to Studio"
		print(msg)
		return msg
	end

	-- the body MeshPart, found the same way the paint rig finds it
	local src: BasePart? = nil
	for _, name in ipairs(P.SOURCE_MODELS) do
		local assets = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
		local m = (assets and assets:FindFirstChild(name)) or workspace:FindFirstChild(name)
		if m then
			local best, bestVol = nil, -1
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("MeshPart") then
					local v = d.Size.X * d.Size.Y * d.Size.Z
					if v > bestVol then
						best, bestVol = d :: BasePart, v
					end
				end
			end
			if best then
				src = best
				break
			end
		end
	end
	assert(src, "[U2U3] no MeshPart under any of {" .. table.concat(P.SOURCE_MODELS, ", ") .. "}")
	local source = src :: BasePart
	log("[U2U3] source: %s", source:GetFullName())

	--------------------------------------------------------------------------
	-- the sheet, from the sink
	--------------------------------------------------------------------------
	local sinkImage: any = nil
	if P.SOURCE == "sink" or P.SOURCE == "both" then
		local body = HttpService:GetAsync(P.SINK_URL)
		assert(#body == P.EXPECT_BYTES, string.format(
			"[U2U3] the sink returned %d bytes, expected %d -- is meshsink.py running from the repo root?",
			#body, P.EXPECT_BYTES))
		local buf = buffer.fromstring(body)
		-- CHECKED, NOT TRUSTED. A texture that arrives scrambled still binds and
		-- still renders something, and "it looks wrong" is then a question about
		-- the design rather than about the transport.
		local sum = 0
		for i = 0, P.EXPECT_BYTES - 1 do
			sum += buffer.readu8(buf, i)
		end
		assert(sum == P.EXPECT_BYTESUM, string.format(
			"[U2U3] the sheet's byte sum is %d, expected %d -- these are NOT the pixels the bake wrote",
			sum, P.EXPECT_BYTESUM))
		log("[U2U3] sink: %d bytes, byte sum %d -- the bake's own pixels, verified", #body, sum)

		sinkImage = AssetService:CreateEditableImage({ Size = Vector2.new(P.TEX, P.TEX) })
		sinkImage:WritePixelsBuffer(Vector2.zero, Vector2.new(P.TEX, P.TEX), buf)
	end

	local hasAsset = (P.SOURCE == "asset" or P.SOURCE == "both") and P.UPLOADED_TEXTURE_ID ~= ""
	if (P.SOURCE == "asset" or P.SOURCE == "both") and not hasAsset then
		log("[U2U3] UPLOADED_TEXTURE_ID is empty -- the asset row is skipped, so the")
		log("[U2U3]   UPLOAD half of U2 is NOT answered by this run")
	end

	--------------------------------------------------------------------------
	-- the row
	--------------------------------------------------------------------------
	for _, c in ipairs(workspace:GetChildren()) do
		if c.Name == P.ROOT_NAME then
			c:Destroy()
		end
	end
	local root = Instance.new("Model")
	root.Name = P.ROOT_NAME
	root.Parent = workspace

	local scale = P.BODY_WIDTH_STUDS / source.Size.X

	-- name, colour, how the texture is bound (nil = none)
	local cells: { { name: string, color: Color3, bind: string? } } = {}
	if sinkImage then
		table.insert(cells, { name = "sink_white", color = P.WHITE, bind = "sink" })
		table.insert(cells, { name = "sink_red", color = P.RED, bind = "sink" })
	end
	if hasAsset then
		table.insert(cells, { name = "asset_white", color = P.WHITE, bind = "asset" })
		table.insert(cells, { name = "asset_red", color = P.RED, bind = "asset" })
	end
	-- THE CONTROL. See the header: without it, "both look the same" cannot be
	-- told apart from "no texture ever bound".
	table.insert(cells, { name = "control_red_untextured", color = P.RED, bind = nil })

	local span = (#cells - 1) * P.SPACING
	local x0 = -span / 2

	local ground = Instance.new("Part")
	ground.Size = Vector3.new(span + 120, 1, 120)
	ground.CFrame = CFrame.new(0, -0.5, P.CELL_Z)
	ground.Color = P.GRASS
	ground.Material = Enum.Material.Grass
	ground.Anchored = true
	ground.CanCollide = false
	ground.CanQuery = false
	ground.CanTouch = false
	ground.Name = "grass"
	ground.Parent = root

	for i, cell in ipairs(cells) do
		local body = source:Clone()
		body.Name = cell.name
		body.Size = source.Size * scale
		body.Color = cell.color
		body.Material = Enum.Material.Plastic
		body.Anchored = true
		body.CanCollide = false
		body.CanQuery = false
		body.CanTouch = false
		pcall(function()
			body.TextureID = ""
		end)
		if cell.bind == "sink" then
			body.TextureContent = Content.fromObject(sinkImage)
		elseif cell.bind == "asset" then
			body.TextureContent = Content.fromUri(P.UPLOADED_TEXTURE_ID)
		end
		body.CFrame = CFrame.new(x0 + (i - 1) * P.SPACING, P.CENTRE_Y, P.CELL_Z)
			* CFrame.Angles(0, math.rad(P.BODY_YAW_DEG), 0)
		body.Parent = root
		log("[U2U3] %-24s Color %.0f,%.0f,%.0f  texture %s",
			cell.name, cell.color.R * 255, cell.color.G * 255, cell.color.B * 255,
			cell.bind or "NONE (control)")
	end

	--------------------------------------------------------------------------
	-- the camera. Scriptable BEFORE the write or the rotation is discarded --
	-- see AIM.luau's header, this is the same trap.
	--------------------------------------------------------------------------
	local at = Vector3.new(0, P.CENTRE_Y, P.CELL_Z)
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = P.FOV
	cam.CFrame = CFrame.lookAt(at + Vector3.new(0, 0, P.DISTANCE), at)
	local v = cam:WorldToViewportPoint(at)
	assert(v.Z > 0, string.format(
		"[U2U3] the row is BEHIND the camera (depth %.1f) -- the viewport kept its own rotation", v.Z))
	log("[U2U3] %d bodies, %.0f studs apart, camera %.0f studs out at fov %d",
		#cells, P.SPACING, v.Z, P.FOV)
	log("[U2U3] READ THE FRAME: if the red-Color body's tangerine is dark red, Color MULTIPLIES")
	log("[U2U3]   the texture and SlimeBuilder must set white when a skin is present. If it is")
	log("[U2U3]   indistinguishable from the white-Color body, Color is IGNORED and the line stays.")
	log("[U2U3]   The untextured control must be plain red, or no texture bound at all.")

	local text = table.concat(out, "\n")
	print(text)
	return text
end

return run()
