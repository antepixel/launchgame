--!strict
-- THE ONLY MODULE IN THIS PROJECT THAT EVER CREATES A Sound. Every sound in the
-- game goes through play2D / playAt / startLoop below; nothing else anywhere in
-- src/ calls Instance.new("Sound"), and dev/analysis/verify_sound.luau greps the
-- tree to keep it that way (see REPORT.md §6b).
--
-- ===== CLIENT-ONLY, DELIBERATELY, AND THIS IS THE CENTRAL ROUTING DECISION.
-- Not one Sound instance is created on the server. World sounds that other
-- players must hear are BROADCAST by the server as a key plus a position (see
-- ServerScriptService/SoundBroadcast.luau) and built here, locally, by each
-- receiving client.
--
-- The obvious alternative -- parent a Sound to a part on the server and let
-- Roblox replicate it -- is fewer moving parts and was rejected for one
-- specific reason: the MUTE TOGGLE. Every SoundGroup in this game is created
-- locally by this module, so muting is a plain local property write on an
-- instance the server has never heard of, and there is no way for one player's
-- mute to reach another's. With server-created groups, muting would depend on
-- the rule that a client's property writes to replicated instances stay local
-- -- true, but a rule the whole feature would be silently resting on. Owning
-- every Sound on the client makes locality structural instead.
--
-- It also matches what this codebase already does everywhere else: the server
-- owns state and the client renders it (see LaunchRemoteLanes, which recomputes
-- other players' whole flights client-side from replicated attributes rather
-- than being driven per-frame by the server).
--
-- ===== NIL-SAFE BY CONSTRUCTION. An entry whose id is nil, and a key that does
-- not exist at all, both return silently. No error, no gap in the caller's
-- logic, and -- crucially -- no log flood: the missing-key warning fires ONCE
-- per unique key per session (see `warned` below), because several of these
-- callers sit in per-frame or per-tick code paths where a warn-per-call would
-- bury every other message in the output.
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local SoundConfig = require(ReplicatedStorage.Config.SoundConfig)

local SoundPlayer = {}

export type LoopHandle = {
	sound: Sound,
	entry: SoundConfig.SoundEntry,
	holder: BasePart?,
	stopped: boolean,
}

-- ===== Missing-id / missing-key bookkeeping. Keyed by the STRING the caller
-- asked for, so "MISSING_ENTRY" and a real key with a nil id are tracked
-- separately and each warns at most once. Never cleared -- a session is the
-- right scope, and re-warning would defeat the point.
local warned: { [string]: boolean } = {}

local function warnOnce(key: string, message: string)
	if warned[key] then
		return
	end
	warned[key] = true
	warn(string.format("[SoundPlayer] %s", message))
end

-- Exposed for the verification harness only (see dev/analysis/verify_sound.luau),
-- which needs to prove the once-per-key property rather than assert it.
function SoundPlayer._warnedCount(): number
	local count = 0
	for _ in warned do
		count += 1
	end
	return count
end

-- ===== SoundGroups: one per category, all nested inside a single master group
-- so the mute toggle and any future master slider move one number. Created
-- lazily on first use rather than at require time, because this module is
-- required by client scripts whose load order relative to SoundService is not
-- guaranteed, and because a server-side require (SoundBroadcast requires
-- SoundConfig, not this) must never build them.
local masterGroup: SoundGroup? = nil
local groups: { [string]: SoundGroup } = {}

local function ensureGroups(): { [string]: SoundGroup }
	if masterGroup then
		return groups
	end

	local master = Instance.new("SoundGroup")
	master.Name = "Master"
	master.Volume = SoundConfig.MASTER_VOLUME
	master.Parent = SoundService
	masterGroup = master

	for _, groupName in SoundConfig.GROUP_ORDER do
		local group = Instance.new("SoundGroup")
		group.Name = groupName
		group.Volume = SoundConfig.GROUP_VOLUMES[groupName]
		-- Nested INSIDE the master group, which is what makes the master's
		-- volume multiplicative over all four rather than a fifth sibling that
		-- controls nothing.
		group.Parent = master
		groups[groupName] = group
	end

	return groups
end

-- The master group, built if needed. The mute toggle's only handle on the mix;
-- see SoundClient.client.luau.
function SoundPlayer.masterGroup(): SoundGroup
	ensureGroups()
	return masterGroup :: SoundGroup
end

-- ===== Entry lookup, and the ONLY place a missing key or a nil id is decided.
-- Returns nil for "do nothing", having warned at most once.
local function resolve(key: string): SoundConfig.SoundEntry?
	local entry = SoundConfig.SOUNDS[key]
	if not entry then
		warnOnce(
			key,
			string.format(
				"no sound entry named %q -- this is a typo in a call site, not a missing asset. Nothing will play. (Warned once; further calls are silent.)",
				key
			)
		)
		return nil
	end
	if not entry.id then
		-- EXPECTED, not an error: every id ships nil by design (see
		-- SoundConfig's header). Warned once at info level so the log says
		-- exactly which sounds are still unfilled without repeating itself.
		warnOnce(
			key,
			string.format(
				"entry %q has no asset id yet -- silent by design. Drop an id into SoundConfig.SOUNDS.%s to enable it. (Warned once.)",
				key,
				key
			)
		)
		return nil
	end
	return entry
end

-- Applies everything an entry says about a Sound, in one place, so a 2D and a
-- 3D sound can never disagree about how the registry is read.
local function configure(sound: Sound, entry: SoundConfig.SoundEntry, groupTable: { [string]: SoundGroup })
	sound.SoundId = entry.id :: string
	sound.Volume = entry.volume
	sound.PlaybackSpeed = entry.pitch
	sound.Looped = entry.looped
	sound.SoundGroup = groupTable[entry.group]

	if entry.spatial then
		-- ===== RollOffMode.Linear IS LOAD-BEARING, not a style choice.
		--
		-- Roblox's DEFAULT is Inverse, under which volume falls as roughly 1/d
		-- and RollOffMaxDistance is the distance at which attenuation STOPS
		-- GETTING WORSE -- the sound then holds that level forever. On a map
		-- that is 3,000 studs long (the road runs Z -4 to Z -2,964), an Inverse
		-- sound is faintly audible from anywhere, which is precisely the bug
		-- REPORT.md §2c exists to rule out: a landing at Z -2,744 must not be
		-- heard at a base at Z 150.
		--
		-- Linear falls to TRUE SILENCE at RollOffMaxDistance, which makes every
		-- distance in SoundConfig a real, checkable cutoff rather than a
		-- suggestion. Rejected: LinearSquare, which also reaches zero but front-
		-- loads the falloff so hard that these already-tight radii would go
		-- inaudible almost immediately.
		sound.RollOffMode = Enum.RollOffMode.Linear
		sound.RollOffMinDistance = entry.rollOffMinDistance :: number
		sound.RollOffMaxDistance = entry.rollOffMaxDistance :: number
	end
end

-- ===== 2D: a one-shot with no position, identical wherever the listener
-- stands. Parented to SoundService itself, which is what makes it 2D -- a Sound
-- not descended from a BasePart or Attachment has no position to attenuate
-- from. Used for every UI, FLIGHT and REWARD entry.
--
-- `pitchScale` and `volumeScale` are optional per-firing multipliers on top of
-- the entry's own values, for the callers that vary a sound rather than just
-- triggering it (the doubling chain climbs in pitch, the reveal scales by slime
-- tier). They multiply rather than replace so the registry stays the single
-- place the base level is set.
function SoundPlayer.play2D(key: string, pitchScale: number?, volumeScale: number?): Sound?
	if not RunService:IsClient() then
		-- Structural, not defensive: this module never runs server-side (see the
		-- header). Warned once so a mis-wired server call is visible rather than
		-- silently doing nothing.
		warnOnce("__server__" .. key, string.format("play2D(%q) was called on the server; sounds are client-only. Route it through SoundBroadcast instead.", key))
		return nil
	end
	local entry = resolve(key)
	if not entry then
		return nil
	end

	local groupTable = ensureGroups()
	local sound = Instance.new("Sound")
	sound.Name = key
	configure(sound, entry, groupTable)
	if pitchScale then
		sound.PlaybackSpeed = entry.pitch * pitchScale
	end
	if volumeScale then
		sound.Volume = entry.volume * volumeScale
	end
	sound.Parent = SoundService

	-- CLEANED UP TWO WAYS, because one is not enough. Ended covers the normal
	-- case; Debris covers the case where the asset fails to load or is moderated
	-- and Ended therefore never fires at all, which would otherwise leak one
	-- Sound instance per firing forever. maxLifetimeSeconds is documented in
	-- SoundConfig as a backstop set comfortably above the real length, never as
	-- a fade.
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	Debris:AddItem(sound, entry.maxLifetimeSeconds)
	sound:Play()
	return sound
end

-- ===== 3D: a one-shot AT A WORLD POSITION. Builds a throwaway anchored holder
-- part, because a Sound needs a BasePart or Attachment ancestor to be
-- positional at all and these fire at places (a landing spot, a swing) rather
-- than at instances that reliably exist and persist.
--
-- The holder is invisible, non-colliding, non-touchable and non-queryable, so
-- it cannot be walked into, cannot trip the collect pads' Touched handlers, and
-- cannot be hit by any raycast. That matters: this project has exactly one
-- .Touched in it (the collect pads) and a stray physical part appearing at a
-- landing spot would be a gameplay change, which this pass is not allowed to
-- make.
function SoundPlayer.playAt(key: string, position: Vector3, pitchScale: number?, volumeScale: number?): Sound?
	if not RunService:IsClient() then
		warnOnce("__server__" .. key, string.format("playAt(%q) was called on the server; sounds are client-only. Route it through SoundBroadcast instead.", key))
		return nil
	end
	local entry = resolve(key)
	if not entry then
		return nil
	end
	if not entry.spatial then
		warnOnce(
			"__2d__" .. key,
			string.format("playAt(%q) was called but that entry is not spatial -- playing it 2D instead. Set spatial = true (and rolloff distances) if it should be positional.", key)
		)
		return SoundPlayer.play2D(key, pitchScale, volumeScale)
	end

	local groupTable = ensureGroups()
	local holder = Instance.new("Part")
	holder.Name = "SoundHolder_" .. key
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanTouch = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.new(1, 1, 1)
	holder.Position = position
	-- Parented to the CAMERA, not Workspace: a client-created part under
	-- Workspace is still local-only, but Camera is the conventional home for
	-- client-only scenery and keeps these out of anything that iterates
	-- Workspace's children looking for real geometry.
	holder.Parent = workspace.CurrentCamera

	local sound = Instance.new("Sound")
	sound.Name = key
	configure(sound, entry, groupTable)
	if pitchScale then
		sound.PlaybackSpeed = entry.pitch * pitchScale
	end
	if volumeScale then
		sound.Volume = entry.volume * volumeScale
	end
	sound.Parent = holder

	-- Destroying the HOLDER takes the sound with it, so there is one cleanup
	-- path rather than two that could disagree.
	sound.Ended:Once(function()
		holder:Destroy()
	end)
	Debris:AddItem(holder, entry.maxLifetimeSeconds)
	sound:Play()
	return sound
end

-- ===== LOOPS. Returns a handle to stop later, or nil if the entry is missing
-- or unfilled -- and a nil handle is safe to pass straight back to stopLoop, so
-- callers never need to branch on it. That is what keeps the flight's teardown
-- paths free of nil checks.
--
-- `parent` is optional: pass a BasePart to make the loop positional (the
-- conveyor), omit it for a 2D loop (the flight rush). A spatial entry with no
-- parent would be silently non-positional, so that combination warns.
function SoundPlayer.startLoop(key: string, parent: BasePart?): LoopHandle?
	if not RunService:IsClient() then
		warnOnce("__server__" .. key, string.format("startLoop(%q) was called on the server; sounds are client-only.", key))
		return nil
	end
	local entry = resolve(key)
	if not entry then
		return nil
	end
	if entry.spatial and not parent then
		warnOnce("__noparent__" .. key, string.format("startLoop(%q) is spatial but was given no parent part -- it would play 2D. Not started.", key))
		return nil
	end

	local groupTable = ensureGroups()
	local sound = Instance.new("Sound")
	sound.Name = key
	configure(sound, entry, groupTable)
	-- Forced true rather than trusted: a looped call on a non-looped entry
	-- would play once and then sit there forever, which reads as "the loop
	-- broke" rather than as a config mistake.
	sound.Looped = true
	sound.Parent = if parent then parent else SoundService
	-- NO Debris and NO Ended cleanup: a loop's lifetime is its owner's business
	-- entirely. Every caller in this project pairs startLoop with a stopLoop on
	-- every exit path -- see REPORT.md §6c, which walks all four for the flight.
	sound:Play()

	return {
		sound = sound,
		entry = entry,
		holder = parent,
		stopped = false,
	}
end

-- IDEMPOTENT AND nil-TOLERANT, and both matter. The flight's rush is stopped
-- from three different places (the landing frame, the flight-state reset, and
-- the return to grounded) precisely so that no exit path can miss it -- which
-- means two or three of them routinely fire for the same flight. Double-stopping
-- must be a no-op, and stopping a loop that never started (because its id is
-- still nil) must be too.
function SoundPlayer.stopLoop(handle: LoopHandle?)
	if not handle or handle.stopped then
		return
	end
	handle.stopped = true
	handle.sound:Stop()
	handle.sound:Destroy()
end

-- Live control of a running loop, for the flight rush's speed tracking. Silent
-- no-op on a nil or already-stopped handle, so the per-frame caller needs no
-- guard of its own.
function SoundPlayer.setLoopPitch(handle: LoopHandle?, pitchScale: number)
	if not handle or handle.stopped then
		return
	end
	handle.sound.PlaybackSpeed = handle.entry.pitch * pitchScale
end

function SoundPlayer.setLoopVolume(handle: LoopHandle?, volumeScale: number)
	if not handle or handle.stopped then
		return
	end
	handle.sound.Volume = handle.entry.volume * volumeScale
end

return SoundPlayer
