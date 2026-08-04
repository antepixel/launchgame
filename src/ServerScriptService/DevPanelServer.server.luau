--!strict
-- ============================================================
-- TODO: REMOVE BEFORE LAUNCH -- this is the server half of the dev-testing
-- panel (money/slime/base/save cheats for testing progression). See the
-- written report for the exact list of files/blocks to delete to strip this
-- out entirely; DO NOT ship this in a published place.
-- ============================================================
--
-- GATE 1 -- HARD STUDIO GATE (the primary protection): this check runs
-- BEFORE anything else in this script, including creating the remote
-- itself. In a published server RunService:IsStudio() is false, this file
-- returns on the very next line, and NOTHING below it ever executes -- no
-- folder, no RemoteEvent, nothing a client could even try to call. This is
-- what "forgetting to remove it before launch must be harmless" actually
-- means: there is no code path in a live server that creates this remote,
-- not a check that rejects requests to one that exists.
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DevConfig = require(ReplicatedStorage.Config.DevConfig)
local SlimeData = require(ReplicatedStorage.Config.SlimeData)
-- Every dev action goes through PlayerProfile (never touches a profile's
-- money/slots/seen directly from here) so saves stay exactly as consistent
-- as a normal reveal -- see PlayerProfile.luau's "DEV PANEL SUPPORT" block.
local PlayerProfile = require(ServerScriptService.PlayerProfile)

-- Rebuilding the current rider's swing structure needs LaunchServer's own
-- local state (swingPivot, swingStructureFolder, activePlayer) -- state that
-- has no business living in PlayerProfile, which is data/persistence, not
-- presentation. LaunchServer.server.luau exposes exactly this one action as
-- a BindableEvent (server-internal, never reachable by a client directly)
-- instead -- see its own "DEV PANEL SUPPORT" comment. Only created in
-- Studio (same Gate 1 as this whole file), so this WaitForChild is safe/
-- expected to resolve quickly, same reasoning as DevPanelClient's own
-- WaitForChild("DevRemotes").
local devRebuildSwingEvent = ServerScriptService:WaitForChild("DevRebuildCurrentSwing") :: BindableEvent

-- GATE 2 -- USERID ALLOWLIST (belt and braces): independent of Gate 1 --
-- checked again on EVERY action below, not cached, not checked only once at
-- connection time. If Gate 1 above is ever loosened or removed by mistake
-- (a bad edit, a copy-paste into a place that isn't actually Studio-gated
-- the same way), this is what still stops anyone not explicitly listed in
-- DevConfig.ALLOWLISTED_USER_IDS from doing anything through this remote --
-- UNLESS RunService:IsStudio() is ALSO true (see the written report -- Bug
-- 2): Studio's own multi-client test mode hands every simulated client a
-- placeholder UserId that can never match a real one hand-entered into
-- ALLOWLISTED_USER_IDS, which otherwise made this panel unusable in exactly
-- the mode it's needed for. Skipping the allowlist while IsStudio() is true
-- does not weaken this gate's own defense-in-depth purpose: this whole file
-- already returns before ever creating the remote when IsStudio() is false
-- (see Gate 1), so the ONLY way this function's IsStudio() branch is ever
-- reached at all is when Gate 1 already confirmed it -- a published server
-- (IsStudio() always false there, and this file never even runs) still
-- requires an allowlisted UserId if Gate 1 is ever bypassed, exactly as
-- before.
local function isAllowlisted(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	return table.find(DevConfig.ALLOWLISTED_USER_IDS, player.UserId) ~= nil
end

local remotesFolder = Instance.new("Folder")
remotesFolder.Name = "DevRemotes"
remotesFolder.Parent = ReplicatedStorage

-- ONE remote for every dev action (actionName + a payload), not one remote
-- per button -- keeps the dev panel's entire network surface to a single
-- Instance, which matters here specifically because Gate 1 means this is
-- also the entire list of things that do not exist in a published server.
local devActionRemote = Instance.new("RemoteEvent")
devActionRemote.Name = "DevAction"
devActionRemote.Parent = remotesFolder

-- Every dev action is logged to the server console -- warn(), not print(),
-- so accidental use stands out in the output rather than blending into
-- ordinary log noise.
local function logAction(player: Player, description: string)
	warn(string.format("[DEV PANEL] %s (%d): %s", player.Name, player.UserId, description))
end

local function onDevAction(player: Player, actionName: string, payload: any)
	if not isAllowlisted(player) then
		warn(string.format("[DEV PANEL] REJECTED (not allowlisted): %s (%d) tried action=%s", player.Name, player.UserId, tostring(actionName)))
		return
	end

	if actionName == "AddMoney" and typeof(payload) == "number" then
		PlayerProfile.devAddMoney(player, payload)
		logAction(player, string.format("added money: %+d", payload))
	elseif actionName == "SetMoney" and typeof(payload) == "number" then
		PlayerProfile.devSetMoney(player, payload)
		logAction(player, string.format("set money to: %d", payload))
	elseif actionName == "GiveSlime" and typeof(payload) == "number" then
		local slime = SlimeData.SLIMES[payload]
		if slime then
			local placed = PlayerProfile.receiveSlime(player, slime)
			logAction(player, string.format("gave slime '%s' (%s) -- %s", slime.name, slime.tierName, if placed then "placed" else "added to inventory (base full)"))
		end
	elseif actionName == "GiveRandomSlimeInTier" and typeof(payload) == "number" then
		local pool = SlimeData.SLIMES_BY_TIER[payload]
		if pool and #pool > 0 then
			local slime = pool[math.random(1, #pool)]
			local placed = PlayerProfile.receiveSlime(player, slime)
			logAction(player, string.format("gave random slime '%s' (%s) -- %s", slime.name, slime.tierName, if placed then "placed" else "added to inventory (base full)"))
		end
	elseif actionName == "SetSwingTier" and typeof(payload) == "number" then
		PlayerProfile.devSetSwingTier(player, payload)
		logAction(player, string.format("set swing tier to: %d", payload))
	elseif actionName == "RebuildSwing" then
		-- Rebuilds whatever the CURRENT rider's tier already is, or -- if no
		-- one is riding -- the REQUESTING player's own tier (see
		-- LaunchServer.server.luau's handler; `player` is passed through so
		-- it never has to guess/default to tier 1 for whoever pressed the
		-- button). Does not read `payload`, does not touch tier or any other
		-- profile state, purely a fresh SwingBuilder.build() call.
		devRebuildSwingEvent:Fire(player)
		logAction(player, "rebuilt current rider's swing at their current tier")
	elseif actionName == "SetSlimeLevel" and typeof(payload) == "table" and typeof(payload.slot) == "number" and typeof(payload.level) == "number" then
		PlayerProfile.devSetSlimeLevel(player, payload.slot, payload.level)
		logAction(player, string.format("set slot %d's slime level to: %d", payload.slot, payload.level))
	elseif actionName == "ClearBase" then
		PlayerProfile.devClearBase(player)
		logAction(player, "cleared base (all 10 slots emptied)")
	elseif actionName == "WipeSave" then
		PlayerProfile.devWipeProfile(player)
		logAction(player, "WIPED SAVE (money, slots, and collection reset to fresh-player state)")
	else
		warn(string.format("[DEV PANEL] Unrecognized action '%s' from %s (%d)", tostring(actionName), player.Name, player.UserId))
	end
end

devActionRemote.OnServerEvent:Connect(onDevAction)

do
	local idStrings = {}
	for _, id in DevConfig.ALLOWLISTED_USER_IDS do
		table.insert(idStrings, tostring(id))
	end
	print(string.format("[DEV PANEL] Enabled (Studio only). Allowlisted UserIds: %s", table.concat(idStrings, ", ")))
end
