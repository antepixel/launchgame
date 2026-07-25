--!strict
-- Inventory: place/remove/sell. Server-authoritative -- see PlayerProfile.
-- placeFromInventory/removeToInventory/sellFromInventory for the actual
-- validation (ownership, slot availability, quantities). This file is just
-- remote plumbing, same shape as ShopServer.server.luau: one remote per
-- action plus a shared result event, nothing else ever crosses the wire.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Every action goes through PlayerProfile, and ONLY PlayerProfile -- so
-- place/remove/sell touch slots/inventory/money exactly the same way every
-- other profile change does, and stay picked up by the same periodic/leave
-- save this file never has to know about.
local PlayerProfile = require(ServerScriptService.PlayerProfile)

local remotesFolder = Instance.new("Folder")
remotesFolder.Name = "InventoryRemotes"
remotesFolder.Parent = ReplicatedStorage

local function makeRemote(name: string): RemoteEvent
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remotesFolder
	return remote
end

-- Client -> server: (globalIndex: number) -- move one copy of this slime
-- from inventory into the first free slot.
local placeSlimeRemote = makeRemote("PlaceSlime")
-- Client -> server: (slotNumber: number) -- move the slime in this slot
-- back to inventory, freeing the slot.
local removeSlimeRemote = makeRemote("RemoveSlime")
-- Client -> server: (globalIndex: number, quantity: number) -- sell this
-- many UNPLACED copies for money. Selling a PLACED slime isn't a supported
-- call shape at all -- see PlayerProfile.sellFromInventory, which only
-- ever reads/decrements inventory, never slots.
local sellSlimeRemote = makeRemote("SellSlime")
-- Server -> client: fires once per action attempt (success or failure),
-- shared by all three above -- same (success, reason) shape ShopServer's
-- BuyTierResult already uses. The client's own slot/inventory contents come
-- from the base folder's Slots/Inventory attributes (already replicated,
-- see PlayerProfile.syncClientState) -- this event exists purely to report
-- WHY an attempt failed, for a one-line status message.
local inventoryActionResultRemote = makeRemote("InventoryActionResult")

local function fireResult(player: Player, ok: boolean, reason: string?)
	inventoryActionResultRemote:FireClient(player, ok, reason)
end

placeSlimeRemote.OnServerEvent:Connect(function(player: Player, globalIndex: any)
	if typeof(globalIndex) ~= "number" then
		return
	end
	local ok, reason = PlayerProfile.placeFromInventory(player, globalIndex)
	fireResult(player, ok, reason)
end)

removeSlimeRemote.OnServerEvent:Connect(function(player: Player, slotNumber: any)
	if typeof(slotNumber) ~= "number" then
		return
	end
	local ok, reason = PlayerProfile.removeToInventory(player, slotNumber)
	fireResult(player, ok, reason)
end)

sellSlimeRemote.OnServerEvent:Connect(function(player: Player, globalIndex: any, quantity: any)
	if typeof(globalIndex) ~= "number" or typeof(quantity) ~= "number" then
		return
	end
	local ok, reason = PlayerProfile.sellFromInventory(player, globalIndex, quantity)
	fireResult(player, ok, reason)
end)
