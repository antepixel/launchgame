--!strict
-- Per-player "which slimes have I ever revealed" tracking -- IN-MEMORY ONLY.
-- No DataStore, no persistence: this table starts empty every server start,
-- and a player's collection is gone the moment the server restarts or they
-- leave (see cleanup below). That's a deliberate limitation for this pass,
-- not an oversight -- see the written report.
local SlimeCollection = {}

-- Player -> set of globalIndex already seen. Keyed by the live Player
-- instance (same convention LaunchServer already uses for activePlayer),
-- not UserId -- nothing here needs to survive a disconnect, so there's no
-- reason to key on something that would.
local seenByPlayer: { [Player]: { [number]: boolean } } = {}

-- Records a reveal and reports whether it was NEW. Call exactly once per
-- reveal (see LaunchServer's onBoxPress) -- calling twice for the same
-- reveal would incorrectly report the second call as a duplicate.
function SlimeCollection.recordSeen(player: Player, globalIndex: number): boolean
	local seen = seenByPlayer[player]
	if not seen then
		seen = {}
		seenByPlayer[player] = seen
	end
	local isNew = not seen[globalIndex]
	seen[globalIndex] = true
	return isNew
end

-- Frees a player's record on disconnect -- called from LaunchServer's
-- existing PlayerRemoving handler. Without this, seenByPlayer would keep
-- growing for the lifetime of the server across every player who ever
-- joined, not just the ones currently connected.
function SlimeCollection.cleanup(player: Player)
	seenByPlayer[player] = nil
end

return SlimeCollection
