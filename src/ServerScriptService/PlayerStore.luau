--!strict
-- Low-level DataStore I/O for player profiles -- the ONLY module that talks
-- to DataStoreService. PlayerProfile.luau owns the in-memory gameplay shape
-- (money, slots, seen); this module only ever moves a plain, DataStore-safe
-- table in and out of the store, plus the session-lock check and
-- same-server save mutex described below -- nothing here knows what a
-- "slime" or a "slot" is. Server-only by construction (ServerScriptService),
-- same reasoning as SlimeRoll.luau.
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PersistenceConfig = require(ReplicatedStorage.Config.PersistenceConfig)

local PlayerStore = {}

local store = DataStoreService:GetDataStore(PersistenceConfig.DATASTORE_NAME)

local function keyFor(userId: number): string
	return "Player_" .. tostring(userId)
end

-- Retries `fn` up to `times`, waiting `backoffSeconds` between attempts.
-- Returns (true, result) the moment fn succeeds, or (false, nil) once every
-- attempt has failed.
local function attempt(times: number, backoffSeconds: number, fn: () -> any): (boolean, any)
	for attemptNumber = 1, times do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		if attemptNumber < times then
			task.wait(backoffSeconds)
		end
	end
	return false, nil
end

-- SAME-SERVER SAVE MUTEX: guarantees this server never has two DataStore
-- writes for the same key in flight at once -- e.g. the periodic autosave
-- and a leave-save landing back to back for the same player, which yield
-- (DataStore calls always do) and could otherwise genuinely interleave. A
-- second save for a key that's already mid-write simply waits for the first
-- to finish before starting, rather than racing it. This is the
-- WITHIN-this-server half of "join while a previous session is still
-- saving" (see the written report for the ACROSS-servers half, the session
-- lock below) -- it's exact, not best-effort, because it's plain Luau state
-- on one process, not something two different server processes have to
-- agree on.
local savesInFlight: { [number]: boolean } = {}

-- Loads one player's saved data. Three distinct outcomes, NOT two -- see the
-- written report for why this distinction is the whole point:
--   (data, true)  -- a real save was found and read successfully.
--   (nil, true)   -- read succeeded, no save exists yet (a genuinely new
--                    player) -- safe to start empty AND safe to save later.
--   (nil, false)  -- the read itself FAILED (every retry exhausted) -- the
--                    caller must start this session empty for PLAY purposes
--                    but must NEVER save, or an unreadable-right-now real
--                    save would be overwritten by blank data.
function PlayerStore.load(userId: number): ({ [string]: any }?, boolean)
	local key = keyFor(userId)

	-- Don't start a read while a write for this exact key is still landing
	-- -- a fast rejoin could otherwise read the split-second-stale value
	-- from just before that write finishes, for no reason (we know exactly
	-- when it's done, since it's happening on THIS server).
	while savesInFlight[userId] do
		task.wait()
	end

	local waitsRemaining = PersistenceConfig.SESSION_WAIT_ATTEMPTS
	while true do
		local ok, data = attempt(PersistenceConfig.LOAD_RETRY_ATTEMPTS, PersistenceConfig.LOAD_RETRY_BACKOFF_SECONDS, function()
			return store:GetAsync(key)
		end)
		if not ok then
			return nil, false
		end
		if data == nil then
			return nil, true
		end

		-- SESSION LOCK (best-effort ACROSS servers -- see the written
		-- report): if this save was last stamped by a DIFFERENT server
		-- within the last SESSION_STALE_SECONDS, some other live session
		-- may still be playing (and about to save) this exact profile --
		-- most commonly a fast rejoin into a NEW server before the OLD
		-- server's leave-save has landed. Wait it out a few times rather
		-- than reading and playing on top of it immediately; if it's still
		-- "active" after every wait, proceed anyway (assume the other
		-- session crashed/hung rather than lock this player out forever).
		local sessionJobId = data.sessionJobId
		local sessionHeartbeat = data.sessionHeartbeat
		local looksActiveElsewhere = typeof(sessionJobId) == "string"
			and sessionJobId ~= game.JobId
			and typeof(sessionHeartbeat) == "number"
			and (os.time() - sessionHeartbeat) < PersistenceConfig.SESSION_STALE_SECONDS

		if not looksActiveElsewhere or waitsRemaining <= 0 then
			return data, true
		end

		waitsRemaining -= 1
		task.wait(PersistenceConfig.SESSION_WAIT_SECONDS)
	end
end

-- Saves one player's data. `releasingSession` is true for the FINAL save of
-- a session (the player is leaving, or the server is shutting down) -- it
-- stamps a CLEARED session marker instead of an active one, so a fast
-- rejoin sees "cleanly released" immediately rather than waiting out
-- SESSION_STALE_SECONDS for nothing. Every other save (the periodic
-- autosave, while the player is still here) stamps itself as the currently
-- active session.
--
-- UpdateAsync, not SetAsync: an atomic per-key write is the standard,
-- documented mitigation against two writers racing the same key. The
-- transform below doesn't need to inspect the OLD value (this server is the
-- sole authority for its own connected player during normal play, and
-- savesInFlight above already prevents THIS server from double-writing it),
-- but going through UpdateAsync still gets Roblox's own consistency
-- handling for the write itself, which a blind SetAsync would not.
--
-- profileData is expected to be a FRESH table built for this one call (see
-- PlayerProfile.toSaveShape) -- this function stamps session fields
-- directly onto it rather than cloning.
function PlayerStore.save(userId: number, profileData: { [string]: any }, releasingSession: boolean): boolean
	if releasingSession then
		profileData.sessionJobId = nil
		profileData.sessionHeartbeat = nil
	else
		profileData.sessionJobId = game.JobId
		profileData.sessionHeartbeat = os.time()
	end

	while savesInFlight[userId] do
		task.wait()
	end
	savesInFlight[userId] = true

	local key = keyFor(userId)
	local ok = attempt(PersistenceConfig.SAVE_RETRY_ATTEMPTS, PersistenceConfig.SAVE_RETRY_BACKOFF_SECONDS, function()
		store:UpdateAsync(key, function()
			return profileData
		end)
	end)

	savesInFlight[userId] = nil
	return ok
end

return PlayerStore
