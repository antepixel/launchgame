--!strict
-- Server-side half of the sound system: tells clients WHAT happened and WHERE,
-- and never creates a Sound itself. Every Sound instance in this game is built
-- on the client by SoundPlayer.luau -- see that module's header for why the
-- server owning none of them is what makes the mute toggle structurally local.
--
-- TWO DIRECTIONS, deliberately kept as two remotes rather than one with an
-- optional position, because they mean different things and mixing them up is
-- the exact mistake that would make one player hear another's UI:
--
--   broadcast(key, position)  -- everyone hears it, positioned in the world.
--                                For events that are genuinely public: a
--                                landing, a launch, a chest opening.
--   playFor(player, key)      -- ONE player hears it, with no position at all.
--                                For a private confirmation the server happens
--                                to be the one that knows about, i.e. a collect.
--
-- WHY BROADCAST TO EVERY CLIENT rather than cull by distance server-side. Each
-- world sound carries a RollOffMaxDistance of 40-250 studs (see SoundConfig)
-- on a map ~3,000 studs long, so most recipients of any given broadcast will
-- hear nothing at all -- server-side culling would genuinely save work. It is
-- not done because the payload is one short string and one Vector3, these fire
-- at most a few times per second across all six players, and culling would
-- require the server to hold a per-player position snapshot that nothing else
-- here needs. If the player cap ever rises far above LaneConfig.LANE_COUNT,
-- this is the first thing to revisit.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundConfig = require(ReplicatedStorage.Config.SoundConfig)

local SoundBroadcast = {}

-- Same "one folder per system, named after it" convention ShopServer,
-- InventoryServer and UpgradeServer already use (ShopRemotes, etc.).
local remotesFolder = Instance.new("Folder")
remotesFolder.Name = "SoundRemotes"

local worldSoundRemote = Instance.new("RemoteEvent")
worldSoundRemote.Name = "WorldSound"
worldSoundRemote.Parent = remotesFolder

local playerSoundRemote = Instance.new("RemoteEvent")
playerSoundRemote.Name = "PlayerSound"
playerSoundRemote.Parent = remotesFolder

-- Parented last, once both children exist, so a client that finds the folder
-- can never find it half-populated -- the same ordering guarantee LaunchServer's
-- own Remotes folder is built with.
remotesFolder.Parent = ReplicatedStorage

-- ===== SERVER-SIDE KEY VALIDATION, and it is not about trust. Nothing a client
-- sends reaches here -- both remotes are server-to-client only and neither has
-- an OnServerEvent connection anywhere -- so there is no attacker to defend
-- against. This catches a TYPO at a call site: without it a misspelled key would
-- travel to six clients and be diagnosed six times, once per client, in six
-- separate logs. Warned once per bad key, matching SoundPlayer's own policy, so
-- a typo in a per-landing call path cannot flood the server log either.
local warnedKeys: { [string]: boolean } = {}

local function keyIsKnown(key: string): boolean
	if SoundConfig.SOUNDS[key] then
		return true
	end
	if not warnedKeys[key] then
		warnedKeys[key] = true
		warn(string.format(
			"[SoundBroadcast] no sound entry named %q -- this is a typo at a call site, not a missing asset. Nothing will be sent. (Warned once.)",
			key
		))
	end
	return false
end

-- A public, positioned event. Every client receives it; each one's own
-- SoundPlayer decides whether it is close enough to hear anything, using the
-- rolloff distances in SoundConfig.
--
-- Deliberately fires even for entries whose id is still nil: the client-side
-- resolve is where "unfilled" is decided, so there is exactly one place that
-- knows, and filling an id in SoundConfig starts the sound with no change here.
function SoundBroadcast.broadcast(key: string, position: Vector3)
	if not keyIsKnown(key) then
		return
	end
	worldSoundRemote:FireAllClients(key, position)
end

-- A private, unpositioned confirmation for one player. Guarded on player.Parent
-- for the same reason LaunchServer's own delayed fires are: this can be reached
-- from a Touched handler that outlives the player's departure by a frame, and
-- FireClient to a player who has already left errors.
function SoundBroadcast.playFor(player: Player, key: string)
	if not keyIsKnown(key) then
		return
	end
	if not player.Parent then
		return
	end
	playerSoundRemote:FireClient(player, key)
end

return SoundBroadcast
