--!strict
-- Swing shop: buy the next swing tier with money. Server-authoritative --
-- see PlayerProfile.buyNextTier for the actual validation (order, price,
-- funds). This file is just the remote plumbing, exactly like LaunchServer's
-- own remotes for Release/BoxPress: a bare, content-free client signal in, a
-- result event back out, nothing else ever crosses the wire.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Buying goes through PlayerProfile, and ONLY PlayerProfile -- see
-- PlayerProfile.buyNextTier -- so a purchase touches money/tier state
-- exactly the same way every other profile change does, and stays picked up
-- by the same periodic/leave save this file never has to know about.
local PlayerProfile = require(ServerScriptService.PlayerProfile)

local remotesFolder = Instance.new("Folder")
remotesFolder.Name = "ShopRemotes"
remotesFolder.Parent = ReplicatedStorage

-- Client -> server: content-free, exactly like Release/BoxPress. There is
-- no "which tier" argument -- see PlayerProfile.buyNextTier, which always
-- prices `profile.swingTier + 1` from THIS player's own server-held record,
-- never a client-supplied number.
local buyTierRemote = Instance.new("RemoteEvent")
buyTierRemote.Name = "BuyTier"
buyTierRemote.Parent = remotesFolder

-- Server -> client: fires once per purchase ATTEMPT (success or failure).
-- The client's own tier/money numbers come from its Base folder's
-- attributes (already replicated, see PlayerProfile.luau), same as every
-- other HUD number in this project -- this event exists purely to report
-- WHY an attempt failed, for a one-line status message.
local buyTierResultRemote = Instance.new("RemoteEvent")
buyTierResultRemote.Name = "BuyTierResult"
buyTierResultRemote.Parent = remotesFolder

local function onBuyTier(player: Player)
	local ok, reason = PlayerProfile.buyNextTier(player)
	buyTierResultRemote:FireClient(player, ok, reason)
end

buyTierRemote.OnServerEvent:Connect(onBuyTier)
