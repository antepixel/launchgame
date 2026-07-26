--!strict
-- Slime upgrades: level up a placed slime with money. Server-authoritative --
-- see PlayerProfile.upgradeSlime for the actual validation (slot occupancy,
-- affordable/available count, price). This file is just the remote plumbing,
-- same shape as ShopServer.server.luau and InventoryServer.server.luau: one
-- remote in, one shared result event out, nothing else ever crosses the wire.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Upgrading goes through PlayerProfile, and ONLY PlayerProfile -- see
-- PlayerProfile.upgradeSlime -- so a purchase touches money/levels state
-- exactly the same way every other profile change does, and stays picked up
-- by the same periodic/leave save this file never has to know about.
local PlayerProfile = require(ServerScriptService.PlayerProfile)

local remotesFolder = Instance.new("Folder")
remotesFolder.Name = "UpgradeRemotes"
remotesFolder.Parent = ReplicatedStorage

-- Client -> server: (slotNumber: number, count: number) -- upgrade the
-- slime in this slot by up to `count` levels (1, 10, or 100 -- see
-- InventoryClient.client.luau's three buy buttons). There is no "price"
-- argument -- PlayerProfile.upgradeSlime always computes the charge itself
-- from this player's own server-held level/money, never from anything the
-- client claims.
local upgradeSlimeRemote = Instance.new("RemoteEvent")
upgradeSlimeRemote.Name = "UpgradeSlime"
upgradeSlimeRemote.Parent = remotesFolder

-- Server -> client: fires once per upgrade ATTEMPT (success or failure), plus
-- how many levels were actually bought (may be fewer than requested -- see
-- PlayerProfile.upgradeSlime's partial-buy behaviour). The client's own
-- level/income numbers come from the base folder's Slots attribute (already
-- replicated, see PlayerProfile.syncClientState) -- this event exists purely
-- to report the outcome for a one-line status message.
local upgradeResultRemote = Instance.new("RemoteEvent")
upgradeResultRemote.Name = "UpgradeResult"
upgradeResultRemote.Parent = remotesFolder

upgradeSlimeRemote.OnServerEvent:Connect(function(player: Player, slotNumber: any, count: any)
	if typeof(slotNumber) ~= "number" or typeof(count) ~= "number" then
		return
	end
	local ok, reason, boughtCount = PlayerProfile.upgradeSlime(player, slotNumber, count)
	upgradeResultRemote:FireClient(player, ok, reason, boughtCount)
end)
