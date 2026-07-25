--!strict
-- Every DataStore/persistence-timing constant lives here, and ONLY here --
-- same rule as every other Config module in this project. See PlayerStore.
-- luau (the only module that reads these) and the written report for how
-- each one is actually used.

export type PersistenceConfig = {
	DATASTORE_NAME: string,
	AUTO_SAVE_INTERVAL_SECONDS: number,
	LOAD_RETRY_ATTEMPTS: number,
	LOAD_RETRY_BACKOFF_SECONDS: number,
	SAVE_RETRY_ATTEMPTS: number,
	SAVE_RETRY_BACKOFF_SECONDS: number,
	SESSION_STALE_SECONDS: number,
	SESSION_WAIT_ATTEMPTS: number,
	SESSION_WAIT_SECONDS: number,
}

local PersistenceConfig: PersistenceConfig = {
	-- DataStore name -- bump this (e.g. "PlayerProfile_v2") if the saved
	-- SHAPE ever changes incompatibly; old keys under the old name are then
	-- simply never read again, rather than being misread as the new shape.
	DATASTORE_NAME = "PlayerProfile_v1",

	-- Seconds between automatic saves of every currently-connected,
	-- successfully-loaded player -- see PlayerProfile's autosave loop.
	AUTO_SAVE_INTERVAL_SECONDS = 120,

	-- Load: how many times to retry a failed GetAsync (network/throttling),
	-- and how long to wait between attempts, before giving up and treating
	-- it as a LOAD FAILURE -- see the written report for exactly what
	-- happens then (never an empty profile that can overwrite a real save).
	LOAD_RETRY_ATTEMPTS = 3,
	LOAD_RETRY_BACKOFF_SECONDS = 2,

	-- Save: same idea, for a failed UpdateAsync. A save that still fails
	-- after these retries is simply skipped for that cycle -- the next
	-- periodic save (or the next leave, if this was a leave-save) tries
	-- again; nothing here ever falls back to writing partial/blank data.
	SAVE_RETRY_ATTEMPTS = 3,
	SAVE_RETRY_BACKOFF_SECONDS = 2,

	-- Session lock (see PlayerStore.luau): a save stamps its own
	-- game.JobId + the current time. A LOAD that finds a DIFFERENT JobId
	-- stamped more recently than this many seconds ago treats that session
	-- as still active elsewhere and waits (see SESSION_WAIT_ATTEMPTS/
	-- SECONDS below) rather than reading and playing on top of it
	-- immediately. Comfortably above AUTO_SAVE_INTERVAL_SECONDS so a
	-- normally-running session never looks stale to a concurrent load.
	SESSION_STALE_SECONDS = 180,
	-- How many times (and how long between) a load waits out a
	-- still-looks-active session before giving up and proceeding anyway --
	-- see the written report; this is a best-effort reduction of the race
	-- window, not a hard distributed lock.
	SESSION_WAIT_ATTEMPTS = 3,
	SESSION_WAIT_SECONDS = 2,
}

return PersistenceConfig
