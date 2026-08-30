--!strict
-- SCALE_PROBE.luau -- HOW WIDE ARE THE SLOT SLIMES ACTUALLY RENDERING?
--
-- Paste into the Studio command bar with MODE = "install", press Play with a
-- client, read the log, then paste again with MODE = "remove".
--
-- NOT SHIPPING CODE. Same standing as dev/legendary/U2_RUNTIME.luau, whose
-- install pattern this copies wholesale -- including the two traps that pattern
-- exists to avoid (Rojo pruning a `$path` folder, and a runtime thread being
-- unable to write Script.Source). See that file's header for both.
--
-- ============================== THE QUESTION ===============================
--
-- The base slot slimes are reported rendering at giant scale. SlimeBuilder
-- derives its unit from the LIVE template:
--
--     UNIT_WIDTH_STUDS = templateBody.Size.X / template:GetScale()
--     model:ScaleTo(widthStuds / UNIT_WIDTH_STUDS)
--
-- and Model:ScaleTo is ABSOLUTE in this engine, so that derivation is the
-- single point where a mesh swap could silently change every slime's size.
--
-- IN EDIT MODE THE DERIVATION IS EXACT -- measured before writing this file:
--
--     template body.Size.X 31.6725, GetScale 15.831855 -> UNIT 2.000554
--     build(colour, 7) -> ScaleTo(3.499031) -> body.Size.X = 7.0000, ratio 1.0000
--
-- SO THIS PROBE EXISTS TO FIND WHERE RUNTIME DIFFERS FROM THAT, and the whole
-- point is that it asks the SERVER and the CLIENT separately. Those two can
-- disagree, and which one is wrong changes the answer completely:
--
--   server 7, client 7        -- the slot slimes are correct; whatever looks
--                                giant in the frame is something else.
--   server 7, client ~31.67   -- the SERVER built correctly and the CLIENT is
--                                rendering the template's unscaled width. That
--                                is SlimeIdleClient's baseline capture: it
--                                reads bodyPart.Size ONCE into bodyBaseSize and
--                                writes Size back every frame from it, so a
--                                capture taken before the scale replicated is
--                                pinned in for the life of the slime.
--   server ~31.67             -- the derivation itself broke at runtime, and
--                                every slime in the game is wrong-sized.
--
-- IT DOES NOT ASSUME WHERE SLOT SLIMES LIVE. It sweeps Workspace for every
-- MeshPart named `slime` and buckets by width, so the giant landmark, the slot
-- slimes and anything unexpected all show up side by side and get told apart by
-- their measurements rather than by their parent's name.
--
-- IT SAMPLES REPEATEDLY, because a slot slime does not exist at t=0 -- it is
-- built when a profile loads. A single early sweep would find nothing and read
-- as "no slimes", which is not the same answer as "slimes, correctly sized".
local P = {
	MODE = "install", -- "install" | "remove"
	SERVER_NAME = "ScaleProbeServer",
}

-- Shared VERBATIM by both halves so the server and the client are running one
-- implementation of the sweep, not two that might drift.
local SWEEP_SRC = [==[
local BODY_PART_NAME = "slime"
-- PlayerProfile.luau's SLOT_SLIME_WIDTH_STUDS and GiantSlimeConfig's
-- BODY_WIDTH_STUDS. Copied rather than required so this probe still reports
-- when a require fails -- which is itself one of the things it might catch.
local WANT_SLOT = 7
local WANT_GIANT = 1050

local function templateLine()
	local RS = game:GetService("ReplicatedStorage")
	local assets = RS:FindFirstChild("Assets")
	local tmpl = assets and assets:FindFirstChild("Slime")
	local body = tmpl and tmpl:FindFirstChild(BODY_PART_NAME)
	if not (tmpl and body) then
		return "template NOT FOUND under ReplicatedStorage.Assets.Slime"
	end
	local gs = tmpl:GetScale()
	return string.format("template body.Size.X %.4f  GetScale %.6f  UNIT_WIDTH_STUDS %.6f",
		body.Size.X, gs, (gs ~= 0) and (body.Size.X / gs) or -1)
end

local function sweep(say, tag)
	say("%s %s", tag, templateLine())
	local buckets, order, n = {}, {}, 0
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("MeshPart") and d.Name == BODY_PART_NAME then
			n += 1
			local key = string.format("%.2f", d.Size.X)
			local bk = buckets[key]
			if not bk then
				local parent = d.Parent
				bk = {
					n = 0,
					path = parent and parent:GetFullName() or d:GetFullName(),
					scale = (parent and parent:IsA("Model")) and parent:GetScale() or -1,
				}
				buckets[key] = bk
				table.insert(order, key)
			end
			bk.n += 1
		end
	end
	table.sort(order, function(a, b) return tonumber(a) < tonumber(b) end)
	say("%s %d body MeshParts in Workspace, %d distinct widths", tag, n, #order)
	if n == 0 then
		say("%s   nothing to measure yet -- no slime has been built at this instant", tag)
		return
	end
	for _, key in ipairs(order) do
		local bk = buckets[key]
		local w = tonumber(key)
		local note
		if math.abs(w - WANT_SLOT) < 0.05 then
			note = "slot slime, CORRECT"
		elseif math.abs(w - WANT_GIANT) < 5 then
			note = "the giant landmark, expected"
		else
			note = string.format("UNEXPECTED -- %.3fx the slot's %d", w / WANT_SLOT, WANT_SLOT)
		end
		say("%s   %9.2f studs  x%-3d  model GetScale %9.4f  %s", tag, w, bk.n, bk.scale, note)
		say("%s              e.g. %s", tag, bk.path)
	end
end
]==]

local CLIENT_SRC = [==[
%s
local Players = game:GetService("Players")
local me = Players.LocalPlayer.Name
local function say(...) print("[SCALE client " .. me .. "] " .. string.format(...)) end

-- THE CLIENT NUMBER IS THE RENDERED ONE. SlimeIdleClient writes Size every
-- frame from a baseline it captured once, so what the client holds is what the
-- player sees -- and it is allowed to disagree with the server.
for _, t in ipairs({ 3, 8, 15, 30 }) do
	task.wait(t == 3 and 3 or 5)
	sweep(say, string.format("t=%%02ds", t))
end
say("done. The idle animation swings width by about %%.0f%%%% either side of rest,", 8)
say("so a bucket within a few percent of a clean number is that number.")
]==]

local SERVER_SRC = [==[
-- installed by dev/analysis/SCALE_PROBE.luau -- remove with MODE = "remove"
%s
local Players = game:GetService("Players")
local function say(...) print("[SCALE server] " .. string.format(...)) end

say("context: IsServer=%%s IsClient=%%s",
	tostring(game:GetService("RunService"):IsServer()),
	tostring(game:GetService("RunService"):IsClient()))

-- The client half, cloned rather than authored: a runtime thread may not write
-- Script.Source. See dev/legendary/U2_RUNTIME.luau's header.
local function attach(player)
	local gui = player:WaitForChild("PlayerGui", 20)
	if not gui then
		say("no PlayerGui for %%s", player.Name)
		return
	end
	local template = script:FindFirstChild("ScaleProbeClient")
	if not template then
		say("NO CLIENT TEMPLATE under %%s -- reinstall", script:GetFullName())
		return
	end
	local ls = template:Clone()
	ls.Disabled = false
	ls.Parent = gui
	say("attached client probe to %%s", player.Name)
end
for _, p in ipairs(Players:GetPlayers()) do task.spawn(attach, p) end
Players.PlayerAdded:Connect(function(p) task.spawn(attach, p) end)

task.spawn(function()
	for _, t in ipairs({ 3, 8, 15, 30 }) do
		task.wait(t == 3 and 3 or 5)
		sweep(say, string.format("t=%%02ds", t))
	end
	say("done. Compare these widths against the client's for the SAME instant:")
	say("  both 7      -- slot slimes are correct, the giant thing is something else")
	say("  server 7, client ~31.67 -- SlimeIdleClient captured its baseline before")
	say("                             the scale replicated; server is fine")
	say("  server ~31.67 -- SlimeBuilder's derivation broke at runtime")
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
	log("[SCALE] removed workspace.%s: %s", P.SERVER_NAME, tostring(removeInstalled()))
else
	removeInstalled()
	local s = Instance.new("Script")
	s.Name = P.SERVER_NAME
	s.Source = string.format(SERVER_SRC, SWEEP_SRC)
	s.Parent = workspace

	local c = Instance.new("LocalScript")
	c.Name = "ScaleProbeClient"
	c.Disabled = true
	c.Source = string.format(CLIENT_SRC, SWEEP_SRC)
	c.Parent = s

	log("[SCALE] installed %s (%d chars) + %s template (%d chars)",
		s:GetFullName(), #s.Source, c.Name, #c.Source)
	log("[SCALE] press Play WITH A CLIENT; server lines start [SCALE server],")
	log("[SCALE]   client lines [SCALE client <name>]. The playtest writes its own")
	log("[SCALE]   Studio log file, NOT the edit one -- see dev/README.md.")
end

local text = table.concat(out, "\n")
print(text)
return text
