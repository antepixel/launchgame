--!strict
-- U2_RUNTIME.luau -- INSTALLS a server probe (and, at runtime, a client probe)
-- so the texture questions get answered in the CONTEXT THE SHIPPING CODE RUNS
-- IN rather than in edit mode.
--
-- Paste into the Studio command bar with MODE = "install", play with two
-- clients, read the output, then paste again with MODE = "remove".
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
-- LogService where get_output_log and get_playtest_output can read it.
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
--   THE CLIENT PROBE IS NOT INSTALLED AT ALL. The server probe carries its
--   source as a string and clones a LocalScript into each player's PlayerGui
--   as they join. A runtime instance is invisible to Rojo by construction --
--   there is no sync that can prune something created after the sync.
--
-- Anything else installed into a `$path` folder will be eaten the same way.
-- That is not a Rojo bug, it is what a managed folder means.
--
-- ========================== WHAT IT ASKS =================================
--
-- 2a. MAY A SERVER SCRIPT WRITE A MeshPart's TEXTURE AT ALL? A real capability
--     question, not a formality. SlimeBuilder's own header records
--     RenderFidelity and CollisionFidelity THROWING when written from a server
--     or client script -- "the current thread cannot write '<name>'" -- and
--     they do not fail quietly, they take every slime build down with them.
--     TextureID could be in that family. Checked with pcall, error printed.
--
-- 2b. DOES THE TEXTURE CROSS TO A SECOND CLIENT? The server stamps what it
--     wrote onto the part as an attribute; each client reports what IT sees
--     against that stamp. Equal means it replicated. That is
--     runtime_mesh_probe's own detector shape pointed at a different property.
--
-- 2c. AND DOES Color TINT AT RUNTIME? Edit mode says no -- measured, on both
--     the EditableImage path and the asset path (dev/out/u2u3.log). Runtime is
--     a different renderer path and gets asked again rather than assumed. This
--     one is answered by LOOKING, not by a string.
--
-- THE STAND-IN TEXTURE IS AN IMAGE ALREADY IN THE PLACE (the sign board), so
-- none of this needs an upload. What it therefore CANNOT answer is whether OUR
-- baked sheet survives Roblox's own image encode -- the one genuinely
-- upload-shaped question, still open for want of an asset id.
local P = {
	MODE = "install", -- "install" | "remove"
	SERVER_NAME = "U2ProbeServer",
	MODEL_NAME = "U2ServerBuilt",
	TEXTURE = "rbxassetid://98429592839825", -- ReplicatedStorage.Assets.Sign.board
}

-- The client half, carried as text and cloned into PlayerGui at runtime. See
-- the header: this is what keeps it out of Rojo's way.
local CLIENT_SRC = [==[
local MODEL_NAME = "%s"
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
while #model:GetChildren() < 4 and os.clock() - t0 < 15 do
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
]==]

local SERVER_SRC = [==[
-- installed by dev/legendary/U2_RUNTIME.luau -- remove with MODE = "remove"
local TEXTURE = "%s"
local MODEL_NAME = "%s"
local CLIENT_SRC = %s

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local function say(...) print("[U2RT server] " .. string.format(...)) end
say("context: IsServer=%%s IsClient=%%s", tostring(RunService:IsServer()), tostring(RunService:IsClient()))

local old = workspace:FindFirstChild(MODEL_NAME)
if old then old:Destroy() end

local src = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Slime"):WaitForChild("slime")
local model = Instance.new("Model")
model.Name = MODEL_NAME

local function mk(name, color, how, x)
	local b = src:Clone()
	b.Name = name
	b.Size = src.Size * (10 / src.Size.X)
	b.Color = color
	b.Anchored = true
	b.CanCollide = false
	local ok, err = true, nil
	if how == "TextureID" then
		ok, err = pcall(function() b.TextureID = TEXTURE end)
	elseif how == "TextureContent" then
		ok, err = pcall(function() b.TextureContent = Content.fromUri(TEXTURE) end)
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

mk("srv_white_TID", Color3.new(1, 1, 1), "TextureID", -24)
mk("srv_red_TID", Color3.new(1, 0, 0), "TextureID", -8)
mk("srv_white_TC", Color3.new(1, 1, 1), "TextureContent", 8)
mk("srv_none_red", Color3.new(1, 0, 0), nil, 24)

model.Parent = workspace
say("parented workspace.%%s with %%d bodies -- 2a is answered above", MODEL_NAME, #model:GetChildren())

-- The client half, created at RUNTIME so no sync can prune it.
local function attach(player)
	local gui = player:WaitForChild("PlayerGui", 20)
	if not gui then
		say("no PlayerGui for %%s -- cannot attach the client probe", player.Name)
		return
	end
	local ls = Instance.new("LocalScript")
	ls.Name = "U2ProbeClient"
	ls.Source = CLIENT_SRC
	ls.Parent = gui
	say("attached client probe to %%s", player.Name)
end
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(attach, p)
end
Players.PlayerAdded:Connect(function(p)
	task.spawn(attach, p)
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
	s.Source = string.format(SERVER_SRC, P.TEXTURE, P.MODEL_NAME,
		string.format("%q", string.format(CLIENT_SRC, P.MODEL_NAME)))
	s.Parent = workspace
	log("[U2RT] installed %s (%d chars), in Workspace because Rojo manages",
		s:GetFullName(), #s.Source)
	log("[U2RT]   ServerScriptService and StarterPlayerScripts and prunes what it")
	log("[U2RT]   does not have on disk -- see this file's header")
	log("[U2RT] now play with two clients; every line of the answer starts [U2RT]")
end

local text = table.concat(out, "\n")
print(text)
return text
