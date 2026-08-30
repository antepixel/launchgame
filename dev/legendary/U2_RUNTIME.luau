--!strict
-- U2_RUNTIME.luau -- INSTALLS a server probe (and, at runtime, a client probe)
-- so the texture questions get answered in the CONTEXT THE SHIPPING CODE RUNS
-- IN rather than in edit mode.
--
-- ============================= HOW TO RUN IT ==============================
--
--   1.  python dev/legendary/meshsink.py          from the repo root, and
--       LEAVE IT RUNNING. Without it the round trip has no bake to compare
--       against and says so; 2a, 2b and 2c are unaffected.
--   2.  Paste this file into the Studio command bar with MODE = "install".
--   3.  PRESS PLAY BY HAND, with a client. Not start_playtest: two runs of it
--       came back server-only, no player ever joined, and 2b is exactly the
--       question a server-only run cannot answer. See dev/README.md.
--   4.  Read the output from
--       %LOCALAPPDATA%\Roblox\logs\*_Studio_*_last.log -- every line starts
--       [U2RT]. get_playtest_output returned 0 lines for a run that had
--       printed all of them, so it is not the channel to trust.
--   5.  Paste again with MODE = "remove".
--
-- BEFORE STEP 2, and it costs four seconds:
--
--     lune run dev/legendary/check_probe.luau
--
-- This file does not run the code it installs -- it BUILDS it out of four
-- long-bracket blocks and a string.format. check_probe.luau compiles the real
-- generated source and checks every say() call's specifiers against its
-- arguments, so a typo costs four seconds here instead of a whole Play.
-- Handed an RGBA dump of the bake it also checks that sheetStats below
-- reproduces encode_probe.py's constants, which is the assert this probe makes
-- at runtime in the least convenient possible place.
--
-- NOT SHIPPING CODE. It writes one Script into the DataModel and takes it out
-- again; nothing it installs is under src/.
--
-- ===================== WHY NOT execute_luau target="server" ================
--
-- Because it does not answer on this bridge. During a playtest the plugin
-- registers ONE instance and it is a client: target="server", "client-1" and
-- "client-2" all come back "Studio plugin connection timeout" while
-- target="edit" happily runs in the play CLIENT (RunService:IsServer() false,
-- IsClient() true, Players.LocalPlayer set). dev/analysis/runtime_mesh_probe.
-- luau's whole how-to-run section assumes those targets work, so it cannot be
-- driven from here as written. See dev/README.md.
--
-- An installed Script does not care how the bridge routes anything: it runs
-- because the engine runs it, in the real context, and it reports through
-- LogService. Read it back from %LOCALAPPDATA%\Roblox\logs\*_Studio_*_last.log
-- rather than through get_playtest_output, which returned outputCount 0 for a
-- run that had in fact printed every line -- also dev/README.md.
--
-- ================ AND WHY IT INSTALLS WHERE IT INSTALLS ====================
--
-- THE FIRST VERSION PUT THE PROBES IN ServerScriptService AND
-- StarterPlayerScripts AND ROJO ATE BOTH OF THEM. default.project.json gives
-- both of those a `$path`, so they are Rojo-managed folders and a sync prunes
-- any child that is not on disk. The scripts were installed, the place was
-- played, and by the time the log was read they had simply stopped existing --
-- with no error anywhere, because nothing failed. workspace.U3Test survived
-- the same interval untouched, which is the tell: Workspace is NOT
-- `$path`-managed (the project names only Baseplate under it).
--
-- So:
--   THE SERVER PROBE GOES IN Workspace. A Script parented into Workspace runs
--   on the server exactly as one in ServerScriptService does, and Rojo has no
--   opinion about it.
--   THE CLIENT PROBE IS A TEMPLATE UNDER THE SERVER SCRIPT, cloned into each
--   player's PlayerGui as they join. It sits in Workspace too, Disabled, so
--   Rojo has no opinion about it either -- and a LocalScript cannot run from
--   Workspace in any case (only PlayerGui, PlayerScripts, a character, or
--   ReplicatedFirst), so parking it there costs nothing.
--
-- Anything else installed into a `$path` folder will be eaten the same way.
-- That is not a Rojo bug, it is what a managed folder means. The managed set
-- is every container a client script would naturally live in: ServerScriptService,
-- ReplicatedStorage, StarterGui and StarterPlayerScripts all carry a `$path`.
-- Workspace does not -- default.project.json names only Baseplate under it.
--
-- ============ AND WHY THE CLIENT HALF IS CLONED, NOT AUTHORED ==============
--
-- THE FIRST VERSION HAD THE SERVER BUILD THE LocalScript AT RUNTIME, carrying
-- its source as a string and doing `ls.Source = CLIENT_SRC`. THAT IS NOT
-- ALLOWED AND IT COST A PLAYTEST TO FIND OUT:
--
--     Error: The current thread cannot write 'Source'
--            (lacking capability PluginOrOpenCloud)
--     Script 'Workspace.U2ProbeServer', Line 428 - function attach
--
-- This is the SAME capability family the 2a section below was written to be
-- afraid of -- SlimeBuilder's RenderFidelity and CollisionFidelity throwing
-- "the current thread cannot write '<name>'" from a server script. TextureID
-- turned out not to be in it. `Source` is, and the check was pointed at the
-- wrong property: the risky write in this file was never the texture, it was
-- the probe's own installer.
--
-- WHAT IT LOOKED LIKE, WHICH IS THE PART WORTH REMEMBERING: the server ran
-- perfectly. It answered 2a, it ran the whole round trip, it printed twenty
-- correct lines. The ONE thing missing was any line from a client -- and the
-- obvious reading of that is "no player joined", which is exactly what the
-- previous two runs had actually suffered from. The server log said
-- `Player -1 added, there are now 1 players total`. A player HAD joined. The
-- error was four lines further down the same log, under a different FLog tag
-- (CreatorError, not CreatorOutput), so a grep for the probe's own prefix
-- could not see it. GREP THE LOG FOR ERRORS, NOT ONLY FOR YOUR OWN TAG.
--
-- THE FIX IS Clone(), which copies Source without writing it. The template is
-- authored ONCE, at install time, from the command bar -- which does hold
-- PluginOrOpenCloud -- and the server only ever clones and reparents it.
--
-- ========================== WHAT IT ASKS =================================
--
-- 2a. MAY A SERVER SCRIPT WRITE A MeshPart's TEXTURE AT ALL? ANSWERED, yes --
--     both TextureID and TextureContent, no throw, value reads back. See
--     dev/out/u2u3.log. Kept in the probe because it now runs against a
--     DIFFERENT asset, and "the property is writable" and "this particular
--     asset binds" are two questions.
--
-- 2b. DOES THE TEXTURE CROSS TO A SECOND CLIENT? STILL OPEN. The server stamps
--     what it wrote onto the part as an attribute; each client reports what IT
--     sees against that stamp. Equal means it replicated. That is
--     runtime_mesh_probe's own detector shape pointed at a different property.
--     Both previous runs were server-only -- no player ever joined, so the
--     PlayerAdded attach never fired. numPlayers on start_playtest did not
--     produce clients. This needs a Play pressed by hand.
--
-- 2c. AND DOES Color TINT AT RUNTIME? Edit mode says no -- measured, on both
--     the EditableImage path and the asset path (dev/out/u2u3.log). Runtime is
--     a different renderer path and gets asked again rather than assumed. This
--     one is answered by LOOKING, not by a string.
--
-- U2's UPLOAD HALF. NOW ASKED, because there is an asset id.
--     THE SHEET IS NO LONGER THE SIGN BOARD. The bodies are bound to
--     rbxassetid://104689541793385 -- dev/out/bake/tiger.png, uploaded. The
--     sign board stays in the frame as a CONTROL and nothing else, so that a
--     tiger that fails to bind (moderation still pending is the ordinary
--     reason) can be told apart from a mechanism that stopped working.
--
-- ==================== HOW THE ROUND TRIP IS MEASURED ======================
--
-- NOT BY LOOKING AT IT. The server pulls the bake's own RGBA from
-- dev/legendary/meshsink.py, reads the UPLOADED asset back through
-- AssetService:CreateEditableImageAsync + ReadPixelsBuffer, and holds the two
-- against each other texel by texel. dev/legendary/encode_probe.py derives the
-- reference constants below from dev/out/bake/tiger.png and the probe asserts
-- the bake it received reproduces them, so a stale or truncated sink file
-- fails loudly instead of quietly becoming the baseline.
--
-- THE FEATURE NUMBER IS REPORTED AND IS NOT THE EVIDENCE. The question that
-- prompted this is whether the encode preserves tiger's narrowest bar at
-- 19.6 px against the 8 px floor, and 2A/P is the paint rig's own definition
-- of that number, so it is computed and printed. But encode_probe.py put the
-- bake through six degradations and measured what 2A/P does:
--
--     case              featBase  2A/P drift  classflip  meanErr  maxErr
--     bake (identity)     19.60px      +0.00%      0.00%     0.00       0
--     jpeg q95            19.79px      +0.99%      0.10%     5.18     123
--     jpeg q85            19.86px      +1.33%      0.14%     6.65     124
--     jpeg q70            19.89px      +1.50%      0.19%     8.59     167
--     jpeg q50            19.95px      +1.80%      0.26%    10.65     178
--     resize 256->512     20.03px      +2.20%      0.27%     3.56     165
--     resize 128->512     20.62px      +5.18%      0.67%     8.99     183
--
-- IT NEVER MOVES. featBase holds within 5% of 19.6 px through a 4x downsample
-- that destroys the sheet, and never approaches the 8 px floor. 2A/P is a mean
-- characteristic width over the whole mark set, dominated by the wide bars;
-- "is the narrowest bar still above the floor" is not the question it answers.
-- So it is printed AS A FLOOR CHECK THAT CANNOT FAIL, labelled, and the two
-- columns that do move -- class flips across a = 0.5, and per-texel error --
-- are the ones the verdict is read from. dev/README.md, the standing rule: a
-- metric that cannot notice its own irrelevance needs a guard, not a comment.
--
-- WHY THE ROUND TRIP IS ON THE SERVER AND 2b IS ON THE CLIENTS. HttpService is
-- server-only, so the bake can only be fetched there. The clients read the
-- asset back too and check its shape against the same constants -- that costs
-- one Play instead of two if the server's image read turns out to be refused,
-- and if both succeed it also answers whether the server and the client are
-- handed the same bytes.
local P = {
	MODE = "install", -- "install" | "remove"
	SERVER_NAME = "U2ProbeServer",
	MODEL_NAME = "U2ServerBuilt",

	-- dev/out/bake/tiger.png, uploaded. THE REAL SHEET.
	TEXTURE = "rbxassetid://104689541793385",
	-- ReplicatedStorage.Assets.Sign.board -- the control, see the header.
	CONTROL_TEXTURE = "rbxassetid://98429592839825",

	-- meshsink.py, running from the repo root. Same endpoint U2U3.luau uses.
	SINK_URL = "http://127.0.0.1:8731/rgba/tiger",
}

-- The instrument, shared VERBATIM by the server and client halves so there is
-- one implementation of the classification and not two that might drift.
-- Every constant here is printed by dev/legendary/encode_probe.py, which
-- derives them from dev/out/bake/tiger.png's own pixels.
local STATS_SRC = [==[
local RW = 512
local RBYTES = RW * RW * 4
local RBYTESUM = 150405167
local RINMAP, RMARKN, REDGEN = 262104, 117747, 4230
local RRATIO = 55.6723 -- 2 * markN / edgeN, in texels
local RFEAT_BASE, RFEAT_REVEAL, RFLOOR = 19.6, 21.1, 8.0

-- BUILD_LEGENDARY_PAINT.luau's tiger entry, verbatim.
local PRI_R, PRI_G, PRI_B = 250, 150, 45 -- tangerine
local MRK_R, MRK_G, MRK_B = 46, 26, 92 -- deep indigo
local DR, DG, DB = MRK_R - PRI_R, MRK_G - PRI_G, MRK_B - PRI_B
local HALF = 0.5 * (DR * DR + DG * DG + DB * DB)

-- A texel is off the UV map iff the bake wrote it black. 16 is a threshold in
-- a gap that is not close on either side -- the darkest painted colour is the
-- mark at max-channel 92, off-map is exactly 0 -- and it is a threshold rather
-- than ~= 0 because a lossy encode bleeds the silhouette, and the SAME rule
-- has to apply to both sheets or the comparison is between two questions.
local INMAP_LEVEL = 16

-- The paint loop's own counting, reproduced and not improved: a transition is
-- scored only when the CURRENT texel is on the map, and an off-map texel reads
-- as not-mark, so entering the silhouette already in the mark colour scores an
-- edge. The number has to be the same number.
local function sheetStats(buf)
	local inMapBuf = buffer.create(RW * RW)
	local markBuf = buffer.create(RW * RW)
	local inMap, markN, edgeN = 0, 0, 0
	local row = table.create(RW, false)
	for py = 0, RW - 1 do
		if py % 64 == 0 then task.wait() end
		for px = 0, RW - 1 do
			local i = py * RW + px
			local o = i * 4
			local r = buffer.readu8(buf, o)
			local g = buffer.readu8(buf, o + 1)
			local b = buffer.readu8(buf, o + 2)
			local isMark = false
			if math.max(r, g, b) > INMAP_LEVEL then
				inMap += 1
				buffer.writeu8(inMapBuf, i, 1)
				isMark = ((r - PRI_R) * DR + (g - PRI_G) * DG + (b - PRI_B) * DB) > HALF
				if isMark then
					markN += 1
					buffer.writeu8(markBuf, i, 1)
				end
				if px > 0 and row[px] ~= isMark then
					edgeN += 1
				end
			end
			row[px + 1] = isMark
		end
	end
	return {
		inMap = inMap,
		markN = markN,
		edgeN = edgeN,
		ratio = (edgeN > 0) and (2 * markN / edgeN) or 0,
		inMapBuf = inMapBuf,
		markBuf = markBuf,
	}
end

-- The design's feature width at both framings. It carries through by RATIO
-- alone because texelStep, the body width and the px/stud are constants shared
-- by the two sheets -- so this needs none of them, only the published anchors.
local function featPx(ratio)
	return RFEAT_BASE * ratio / RRATIO, RFEAT_REVEAL * ratio / RRATIO
end

-- The uploaded asset's decoded pixels: buffer, size, error. Every step is
-- pcall'd separately because "the asset would not load" and "this context may
-- not read images" are different answers and both are worth having.
local function readAsset(uri)
	local ok, img = pcall(function()
		return game:GetService("AssetService"):CreateEditableImageAsync(Content.fromUri(uri))
	end)
	if not ok then
		return nil, nil, "CreateEditableImageAsync: " .. tostring(img)
	end
	local size = img.Size
	local ok2, buf = pcall(function()
		return img:ReadPixelsBuffer(Vector2.zero, size)
	end)
	if not ok2 then
		return nil, size, "ReadPixelsBuffer: " .. tostring(buf)
	end
	return buf, size, nil
end
]==]

-- The upload round trip. Server only: HttpService is server-only, so the bake
-- can only be fetched here. Reads sheetStats/featPx/readAsset and the TEXTURE
-- and SINK_URL locals out of the scope it is inlined into.
local MEASURE_SRC = [==[
local function roundTrip(say)
	say("---- the upload round trip: %s against dev/out/bake/tiger.png ----", TEXTURE)

	-- the bake, from the sink
	local bake, bakeErr = nil, nil
	local okHttp, body = pcall(function()
		return game:GetService("HttpService"):GetAsync(SINK_URL)
	end)
	if not okHttp then
		bakeErr = "GetAsync: " .. tostring(body)
	elseif #body ~= RBYTES then
		bakeErr = string.format("the sink returned %d bytes, wanted %d", #body, RBYTES)
	else
		bake = buffer.fromstring(body)
		-- CHECKED, NOT TRUSTED. A sheet that arrives short or stale still
		-- classifies fine and would silently become the baseline.
		local sum = 0
		for i = 0, RBYTES - 1 do
			if i % 262144 == 0 then task.wait() end
			sum += buffer.readu8(bake, i)
		end
		if sum ~= RBYTESUM then
			bake, bakeErr = nil, string.format(
				"the sink's byte sum is %d, wanted %d -- these are NOT the bake's pixels", sum, RBYTESUM)
		else
			say("sink: %d bytes, byte sum %d -- the bake's own pixels, verified", #body, sum)
		end
	end
	if not bake then
		say("NO BAKE TO COMPARE AGAINST -- %s", bakeErr)
		say("  is meshsink.py running from the repo root? Without it the round trip")
		say("  cannot be measured; 2a, 2b and 2c above are unaffected.")
		return
	end

	-- the asset, read back
	local rt, rtSize, rtErr = readAsset(TEXTURE)
	if not rt then
		say("COULD NOT READ THE ASSET BACK -- %s", rtErr)
		say("  size reported: %s", tostring(rtSize))
		say("  the clients try the same read; if one of them managed it, the shape")
		say("  half of the answer is in their lines instead.")
		return
	end
	say("asset read back at %s", tostring(rtSize))
	if rtSize.X ~= RW or rtSize.Y ~= RW then
		say("THE ENCODE RESIZED THE SHEET: %dx%d, uploaded 512x512. That alone decides it --",
			rtSize.X, rtSize.Y)
		say("  every feature is scaled by %.3f before anything else is measured.", rtSize.X / RW)
		return
	end

	local sBake = sheetStats(bake)
	local sRt = sheetStats(rt)

	local refOk = (sBake.inMap == RINMAP and sBake.markN == RMARKN and sBake.edgeN == REDGEN)
	say("bake      inMap %6d  markN %6d  edgeN %5d  2A/P %8.4f tx  %s",
		sBake.inMap, sBake.markN, sBake.edgeN, sBake.ratio,
		refOk and "== encode_probe.py's reference" or "DOES NOT MATCH encode_probe.py")
	if not refOk then
		say("  wanted inMap %d markN %d edgeN %d. The instrument and the reference have",
			RINMAP, RMARKN, REDGEN)
		say("  drifted apart -- re-run dev/legendary/encode_probe.py. Everything below")
		say("  is still a real comparison of the two sheets, but the ANCHOR is suspect.")
	end
	say("roundtrip inMap %6d  markN %6d  edgeN %5d  2A/P %8.4f tx  (%+.2f%%)",
		sRt.inMap, sRt.markN, sRt.edgeN, sRt.ratio, (sRt.ratio / sBake.ratio - 1) * 100)

	local fb, fr = featPx(sRt.ratio)
	say("FEATURE WIDTH  base %.2f px (bake %.1f)  reveal %.2f px (bake %.1f)  floor %.0f px -- %s",
		fb, RFEAT_BASE, fr, RFEAT_REVEAL, RFLOOR,
		(math.min(fb, fr) >= RFLOOR) and "CLEARS THE FLOOR" or "BELOW THE FLOOR")
	say("  AND THAT LINE CANNOT FAIL, so do not read it as evidence. Offline, featBase")
	say("  held within 5%% of 19.6 px through jpeg q50 AND a 4x downsample -- 2A/P is a")
	say("  mean width over the whole mark set and the wide bars carry it. See this")
	say("  file's header table and dev/legendary/encode_probe.py.")

	-- the two numbers that do move
	local n, tot, mx, o8, o32, flips, mapFlips = 0, 0, 0, 0, 0, 0, 0
	for i = 0, RW * RW - 1 do
		if i % 65536 == 0 then task.wait() end
		local inBake = buffer.readu8(sBake.inMapBuf, i)
		if inBake ~= buffer.readu8(sRt.inMapBuf, i) then
			mapFlips += 1
		end
		if inBake == 1 then
			n += 1
			if buffer.readu8(sBake.markBuf, i) ~= buffer.readu8(sRt.markBuf, i) then
				flips += 1
			end
			local o = i * 4
			local e = math.max(
				math.abs(buffer.readu8(bake, o) - buffer.readu8(rt, o)),
				math.abs(buffer.readu8(bake, o + 1) - buffer.readu8(rt, o + 1)),
				math.abs(buffer.readu8(bake, o + 2) - buffer.readu8(rt, o + 2)))
			tot += e
			if e > mx then mx = e end
			if e > 8 then o8 += 1 end
			if e > 32 then o32 += 1 end
		end
	end
	local meanErr = tot / math.max(n, 1)
	local flipPct = 100 * flips / math.max(n, 1)
	say("CLASS FLIPS   %6d of %d in-map texels (%.3f%%)   off-map flips %d",
		flips, n, flipPct, mapFlips)
	say("TEXEL ERROR   mean %.2f  max %d  over 8: %.1f%%  over 32: %.2f%%  (max channel)",
		meanErr, mx, 100 * o8 / math.max(n, 1), 100 * o32 / math.max(n, 1))
	say("  the scale, from encode_probe.py -- classflip%% / meanErr:")
	say("  identity 0.000/0.00 | q95 0.103/5.18 | q85 0.135/6.65 | q70 0.193/8.59")
	say("  q50 0.257/10.65 | 2x down 0.272/3.56 | 4x down 0.670/8.99")

	if flips == 0 and mx == 0 then
		say("VERDICT: the asset is BYTE-FOR-BYTE the bake. Roblox's encode was lossless")
		say("  for this sheet and the upload path costs the design nothing.")
	elseif flipPct <= 0.103 and meanErr <= 5.18 then
		say("VERDICT: the sheet came back CHANGED but at or under jpeg q95 on both axes.")
		say("  The boundaries moved by %d texels in %d. Whether that is acceptable is a", flips, n)
		say("  design call, not a floor breach -- the floor is not what is at risk here.")
	else
		say("VERDICT: the sheet came back CHANGED BY MORE THAN jpeg q95 on at least one")
		say("  axis. Place it on the scale above; note that a downsample shows as LOW")
		say("  meanErr with HIGH flips, and a lossy block encode as the reverse.")
	end
end
]==]

-- The client half, carried as text and cloned into PlayerGui at runtime. See
-- the header: this is what keeps it out of Rojo's way.
local CLIENT_SRC = [==[
local MODEL_NAME = "%s"
local TEXTURE = "%s"
%s
local Players = game:GetService("Players")
local me = Players.LocalPlayer.Name
local function say(...) print("[U2RT client " .. me .. "] " .. string.format(...)) end

local model = workspace:WaitForChild(MODEL_NAME, 30)
if not model then
	say("workspace.%%s NEVER ARRIVED -- 2b FAILS: the server-built model did not replicate", MODEL_NAME)
	return
end
-- Parts arrive as children after the model does, so wait for the count rather
-- than for a fixed time.
local t0 = os.clock()
while #model:GetChildren() < 5 and os.clock() - t0 < 15 do
	task.wait(0.1)
end
say("sees workspace.%%s, %%d children, after %%.1f s", MODEL_NAME, #model:GetChildren(), os.clock() - t0)
for _, b in ipairs(model:GetChildren()) do
	local wrote = b:GetAttribute("SrvWrote")
	local srvTex = b:GetAttribute("SrvTextureID")
	local srvCol = b:GetAttribute("SrvColor")
	local mine = b.TextureID
	local col = string.format("%%d,%%d,%%d", b.Color.R * 255, b.Color.G * 255, b.Color.B * 255)
	say("%%-15s wrote %%-14s | server saw %%q | I see %%q | %%s | Color srv %%s mine %%s %%s",
		b.Name, tostring(wrote), tostring(srvTex), mine,
		(mine == srvTex) and "TEXTURE CROSSED" or "TEXTURE DID NOT CROSS",
		tostring(srvCol), col, (col == srvCol) and "(colour crossed)" or "(COLOUR DID NOT CROSS)")
end
say("2b answered above. 2c is a RENDER question -- look at the frame, not at these strings.")

-- The client cannot fetch the bake (HttpService is server-only), so it cannot
-- do the per-texel comparison. It CAN read the asset back and check its shape
-- against the same constants, which answers the round trip's shape half if the
-- server's image read was refused, and otherwise says whether the server and
-- the client were handed the same bytes.
task.spawn(function()
	local rt, size, err = readAsset(TEXTURE)
	if not rt then
		say("asset read back FAILED -- %%s (size %%s)", err, tostring(size))
		return
	end
	if size.X ~= RW or size.Y ~= RW then
		say("asset came back %%dx%%d, uploaded 512x512 -- THE ENCODE RESIZED IT", size.X, size.Y)
		return
	end
	local s = sheetStats(rt)
	local fb, fr = featPx(s.ratio)
	say("asset %%s: inMap %%d markN %%d edgeN %%d 2A/P %%.4f tx", tostring(size), s.inMap, s.markN, s.edgeN, s.ratio)
	say("  against the bake's %%d / %%d / %%d and 2A/P %%.4f", RINMAP, RMARKN, REDGEN, RRATIO)
	say("  feature width base %%.2f px, reveal %%.2f px, floor %%.0f px -- %%s (a floor check",
		fb, fr, RFLOOR, (math.min(fb, fr) >= RFLOOR) and "clears" or "BELOW")
	say("  that cannot fail; the server's class-flip and texel-error lines are the evidence)")
end)
]==]

local SERVER_SRC = [==[
-- installed by dev/legendary/U2_RUNTIME.luau -- remove with MODE = "remove"
local TEXTURE = "%s"
local CONTROL_TEXTURE = "%s"
local MODEL_NAME = "%s"
local SINK_URL = "%s"
%s
%s
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local function say(...) print("[U2RT server] " .. string.format(...)) end
say("context: IsServer=%%s IsClient=%%s", tostring(RunService:IsServer()), tostring(RunService:IsClient()))
say("sheet: %%s (dev/out/bake/tiger.png, uploaded)", TEXTURE)

local old = workspace:FindFirstChild(MODEL_NAME)
if old then old:Destroy() end

local src = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Slime"):WaitForChild("slime")
local model = Instance.new("Model")
model.Name = MODEL_NAME

local function mk(name, color, how, tex, x)
	local b = src:Clone()
	b.Name = name
	b.Size = src.Size * (10 / src.Size.X)
	b.Color = color
	b.Anchored = true
	b.CanCollide = false
	local ok, err = true, nil
	if how == "TextureID" then
		ok, err = pcall(function() b.TextureID = tex end)
	elseif how == "TextureContent" then
		ok, err = pcall(function() b.TextureContent = Content.fromUri(tex) end)
	end
	b.CFrame = CFrame.new(x, 30, 0)
	b:SetAttribute("SrvWrote", how or "NONE")
	b:SetAttribute("SrvOk", ok)
	b:SetAttribute("SrvTextureID", b.TextureID)
	b:SetAttribute("SrvColor", string.format("%%d,%%d,%%d", b.Color.R * 255, b.Color.G * 255, b.Color.B * 255))
	b.Parent = model
	say("%%-15s via %%-14s write=%%s%%s TextureID now %%q", name, tostring(how), tostring(ok),
		ok and " " or (" -- " .. tostring(err) .. " "), b.TextureID)
end

mk("srv_white_TID", Color3.new(1, 1, 1), "TextureID", TEXTURE, -32)
mk("srv_red_TID", Color3.new(1, 0, 0), "TextureID", TEXTURE, -16)
mk("srv_white_TC", Color3.new(1, 1, 1), "TextureContent", TEXTURE, 0)
-- THE TWO CONTROLS. srv_sign_TID carries an asset already proven to bind and
-- render here, so a tiger that comes up blank (moderation pending is the
-- ordinary reason) is told apart from a mechanism that stopped working.
-- srv_none_red carries no texture at all, so "both look the same" cannot be
-- confused with "nothing ever bound" -- dev/README.md's standing trap.
mk("srv_sign_TID", Color3.new(1, 1, 1), "TextureID", CONTROL_TEXTURE, 16)
mk("srv_none_red", Color3.new(1, 0, 0), nil, nil, 32)

model.Parent = workspace
say("parented workspace.%%s with %%d bodies -- 2a is answered above", MODEL_NAME, #model:GetChildren())

-- The client half, created at RUNTIME so no sync can prune it.
local function attach(player)
	local gui = player:WaitForChild("PlayerGui", 20)
	if not gui then
		say("no PlayerGui for %%s -- cannot attach the client probe", player.Name)
		return
	end
	-- CLONED, NOT AUTHORED. A runtime server thread MAY NOT WRITE Source --
	-- "the current thread cannot write 'Source' (lacking capability
	-- PluginOrOpenCloud)" -- which is what the first version of this did and
	-- why no client ever reported. Clone() copies the source without writing
	-- it, so the template is authored once at install time, from the command
	-- bar, which does hold that capability. See this file's header.
	local template = script:FindFirstChild("U2ProbeClient")
	if not template then
		say("NO CLIENT TEMPLATE under %%s -- reinstall with MODE = \"install\"", script:GetFullName())
		return
	end
	local ls = template:Clone()
	ls.Disabled = false
	ls.Parent = gui
	say("attached client probe to %%s", player.Name)
end
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(attach, p)
end
Players.PlayerAdded:Connect(function(p)
	task.spawn(attach, p)
end)

-- Off the main path on purpose: the round trip yields on HTTP and on an image
-- decode, and neither 2a nor 2b should wait behind it or die with it.
task.spawn(function()
	local ok, err = pcall(roundTrip, say)
	if not ok then
		say("the round trip threw: %%s", tostring(err))
	end
end)
]==]

local out = {}
local function log(...)
	table.insert(out, string.format(...))
end

local function removeInstalled(): boolean
	local s = workspace:FindFirstChild(P.SERVER_NAME)
	if s then
		s:Destroy()
		return true
	end
	return false
end

if P.MODE == "remove" then
	log("[U2RT] removed workspace.%s: %s", P.SERVER_NAME, tostring(removeInstalled()))
	local m = workspace:FindFirstChild(P.MODEL_NAME)
	if m then
		m:Destroy()
	end
	log("[U2RT] removed workspace.%s: %s", P.MODEL_NAME, tostring(m ~= nil))
else
	removeInstalled()
	local s = Instance.new("Script")
	s.Name = P.SERVER_NAME
	s.Source = string.format(SERVER_SRC, P.TEXTURE, P.CONTROL_TEXTURE, P.MODEL_NAME, P.SINK_URL,
		STATS_SRC, MEASURE_SRC)
	s.Parent = workspace

	-- THE CLIENT TEMPLATE, AUTHORED HERE AND NOWHERE ELSE. This paste runs in
	-- the command bar, which holds PluginOrOpenCloud and may therefore write
	-- Source; the installed server Script does not, and throws if it tries.
	-- It lives under the server Script so that removing one removes both, and
	-- it is Disabled and in Workspace so it cannot run where it sits -- a
	-- LocalScript only runs from PlayerGui, PlayerScripts, a character or
	-- ReplicatedFirst, and the server clones it into the first of those.
	local c = Instance.new("LocalScript")
	c.Name = "U2ProbeClient"
	c.Disabled = true
	c.Source = string.format(CLIENT_SRC, P.MODEL_NAME, P.TEXTURE, STATS_SRC)
	c.Parent = s

	log("[U2RT] installed %s (%d chars) + %s template (%d chars), in Workspace",
		s:GetFullName(), #s.Source, c.Name, #c.Source)
	log("[U2RT]   because Rojo manages ServerScriptService, ReplicatedStorage,")
	log("[U2RT]   StarterGui and StarterPlayerScripts and prunes what it does")
	log("[U2RT]   not have on disk -- see this file's header")
	log("[U2RT] sheet %s -- the uploaded bake, NOT the sign board", P.TEXTURE)
	log("[U2RT] START meshsink.py FROM THE REPO ROOT FIRST, or the round trip has")
	log("[U2RT]   nothing to compare against:  python dev/legendary/meshsink.py")
	log("[U2RT] then play with two clients; every line of the answer starts [U2RT]")
	log("[U2RT] read it from %%LOCALAPPDATA%%\\Roblox\\logs\\*_Studio_*_last.log --")
	log("[U2RT]   get_playtest_output has returned 0 lines for a run that printed")
end

local text = table.concat(out, "\n")
print(text)
return text
