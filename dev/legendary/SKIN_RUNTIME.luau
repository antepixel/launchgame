--!strict
-- SKIN_RUNTIME.luau -- PUTS THE TIGER LEGENDARY ON A REAL SLOT PAD and reports
-- what the SERVER built and what a CLIENT sees, through the shipping pipeline
-- rather than beside it.
--
--   1.  Paste into the Studio command bar with MODE = "install".
--   2.  PRESS PLAY WITH A CLIENT.
--   3.  Read the log; lines start [SKIN server] / [SKIN client <name>].
--   4.  Paste again with MODE = "remove".
--
-- NOT SHIPPING CODE. Install pattern copied from dev/legendary/U2_RUNTIME.luau
-- -- Workspace, because Rojo prunes `$path` folders, and a CLONED client
-- template, because a runtime thread may not write Script.Source. Both traps
-- are documented in that file's header and in dev/README.md.
--
-- ============================== WHAT IT PROVES =============================
--
-- It does NOT build a slime itself. It calls PlayerProfile.receiveSlime -- the
-- same entry point the dev panel's GiveSlime action uses -- and then MEASURES
-- what the shipping code produced. If it built its own slime it would only be
-- testing SlimeBuilder, which edit mode already covers; the open question is
-- whether the wiring carries a skin all the way from SlimeConfig through
-- SlimeData and PlayerProfile onto a pad, on a server, replicated to a client.
--
-- IT FINDS THE TIGER BY ITS SKIN, NOT BY INDEX. globalIndex 25 is written down
-- as a cross-check and asserted against the catalog, so a reordered tier fails
-- loudly here instead of silently granting the wrong slime and reporting that
-- the skin did not bind.
--
-- THE CONTROL IS THE OTHER SLIMES ALREADY ON THE BASE. Every unskinned slime
-- on the same base must come back with TextureID "" in the same sweep. Without
-- that, "the tiger has a texture" cannot be told apart from "everything has a
-- texture", which is exactly the failure dev/README.md keeps warning about --
-- and it is free here, because the base already has slimes on it.
local P = {
	MODE = "install", -- "install" | "remove"
	SERVER_NAME = "SkinProbeServer",
	-- Legendary Slime 1. Cross-checked against the catalog, never trusted.
	EXPECT_INDEX = 25,
	EXPECT_SKIN = "rbxassetid://104689541793385",
}

local SWEEP_SRC = [==[
-- Every slime body on any base, and what texture it carries. Shared verbatim
-- by both halves so the server and the client are answering the same question.
local function sweepSlimes(say, tag)
	local skinned, bare, rows = 0, 0, {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("MeshPart") and d.Name == "slime" then
			local model = d.Parent
			local full = model and model:GetFullName() or d:GetFullName()
			-- only the bases; the lineup and any lab scene are not the pipeline
			if string.find(full, "Base_", 1, true) then
				if d.TextureID ~= "" then skinned += 1 else bare += 1 end
				table.insert(rows, string.format(
					"%-34s %6.2f studs  Color %3d,%3d,%3d  TextureID %q",
					string.gsub(full, "Workspace%.", ""), d.Size.X,
					d.Color.R * 255, d.Color.G * 255, d.Color.B * 255, d.TextureID))
			end
		end
	end
	table.sort(rows)
	say("%s %d slot slimes on bases -- %d skinned, %d bare", tag, #rows, skinned, bare)
	for _, r in ipairs(rows) do
		say("%s   %s", tag, r)
	end
	return skinned, bare
end
]==]

local CLIENT_SRC = [==[
local EXPECT_SKIN = "%s"
%s
local Players = game:GetService("Players")
local me = Players.LocalPlayer.Name
local function say(...) print("[SKIN client " .. me .. "] " .. string.format(...)) end

-- Wait for a skinned body to actually replicate rather than sweeping once and
-- reporting an absence that only means "not yet".
local body, t0 = nil, os.clock()
while os.clock() - t0 < 45 do
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("MeshPart") and d.Name == "slime" and d.TextureID == EXPECT_SKIN then
			body = d
			break
		end
	end
	if body then break end
	task.wait(0.5)
end

if not body then
	say("NO skinned body reached this client in 45 s -- sweeping anyway:")
	sweepSlimes(say, "final")
	return
end
say("skinned body arrived after %%.1f s: %%s", os.clock() - t0, body:GetFullName())
sweepSlimes(say, "final")

-- AIM THE CAMERA AT IT so a capture shows the thing being claimed. In a running
-- client the camera is the client's own -- the edit-mode trap where Studio
-- re-asserts its rotation every frame (see dev/skins/AIM.luau) does not apply.
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
local at = body.Position
cam.CFrame = CFrame.lookAt(at + Vector3.new(0, 2.5, 11), at)
local v = cam:WorldToViewportPoint(at)
say("camera aimed: subject depth %%.1f (positive = in front) at %%s", v.Z, tostring(at))
say("HOLDING THE CAMERA for 120 s so a screenshot can be taken.")
task.wait(120)
cam.CameraType = Enum.CameraType.Custom
say("camera released")
]==]

local SERVER_SRC = [==[
-- installed by dev/legendary/SKIN_RUNTIME.luau -- remove with MODE = "remove"
local EXPECT_INDEX = %d
local EXPECT_SKIN = "%s"
%s
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local SlimeData = require(RS.Config.SlimeData)
local PlayerProfile = require(game:GetService("ServerScriptService").PlayerProfile)

local function say(...) print("[SKIN server] " .. string.format(...)) end

-- FOUND BY SKIN, CHECKED AGAINST THE INDEX. A reordered tier fails here.
local tiger
for _, s in ipairs(SlimeData.SLIMES) do
	if s.skinTextureId then tiger = s break end
end
if not tiger then
	say("NO SLIME IN THE CATALOG CARRIES A SKIN -- the wiring is not in this build")
	return
end
say("catalog: #%%d %%s (tier %%d %%s) skin %%s", tiger.globalIndex, tiger.name, tiger.tier, tiger.tierName, tiger.skinTextureId)
if tiger.globalIndex ~= EXPECT_INDEX then
	say("  WARNING: expected globalIndex %%d -- the tier order has moved", EXPECT_INDEX)
end
if tiger.skinTextureId ~= EXPECT_SKIN then
	say("  WARNING: expected skin %%s", EXPECT_SKIN)
end

local function attach(player)
	local gui = player:WaitForChild("PlayerGui", 20)
	if not gui then return end
	local template = script:FindFirstChild("SkinProbeClient")
	if not template then
		say("NO CLIENT TEMPLATE under %%s -- reinstall", script:GetFullName())
		return
	end
	local ls = template:Clone()
	ls.Disabled = false
	ls.Parent = gui
	say("attached client probe to %%s", player.Name)
end

local function onPlayer(player)
	task.spawn(attach, player)
	-- The profile is built by LaunchServer's own PlayerAdded; retry rather than
	-- guess how long that takes.
	local placed, err = nil, nil
	for i = 1, 40 do
		task.wait(0.5)
		local ok, res = pcall(PlayerProfile.receiveSlime, player, tiger)
		if ok then
			placed = res
			break
		end
		err = res
	end
	if placed == nil then
		say("receiveSlime never succeeded for %%s -- last error: %%s", player.Name, tostring(err))
		return
	end
	say("receiveSlime(%%s, %%s) -> placed on a pad = %%s", player.Name, tiger.name, tostring(placed))
	if not placed then
		say("  it went to INVENTORY, not a pad -- every slot is full. Clearing one is a")
		say("  dev-panel action (ClearBase) and is NOT done here without being asked.")
	end
	task.wait(2)
	local skinned, bare = sweepSlimes(say, "server")
	say("server verdict: %%d skinned, %%d bare on the bases", skinned, bare)
	if skinned == 0 then
		say("  THE SKIN DID NOT REACH THE PAD. SlimeBuilder got a nil skinTextureId,")
		say("  or PlayerProfile is not passing it.")
	end
end

for _, p in ipairs(Players:GetPlayers()) do task.spawn(onPlayer, p) end
Players.PlayerAdded:Connect(function(p) task.spawn(onPlayer, p) end)
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
	log("[SKIN] removed workspace.%s: %s", P.SERVER_NAME, tostring(removeInstalled()))
else
	removeInstalled()
	local s = Instance.new("Script")
	s.Name = P.SERVER_NAME
	s.Source = string.format(SERVER_SRC, P.EXPECT_INDEX, P.EXPECT_SKIN, SWEEP_SRC)
	s.Parent = workspace

	local c = Instance.new("LocalScript")
	c.Name = "SkinProbeClient"
	c.Disabled = true
	c.Source = string.format(CLIENT_SRC, P.EXPECT_SKIN, SWEEP_SRC)
	c.Parent = s

	log("[SKIN] installed %s (%d chars) + %s template (%d chars)",
		s:GetFullName(), #s.Source, c.Name, #c.Source)
	log("[SKIN] press Play WITH A CLIENT. The client holds the camera on the tiger")
	log("[SKIN]   for 120 s so a screenshot can be taken while it is on screen.")
end

local text = table.concat(out, "\n")
print(text)
return text
