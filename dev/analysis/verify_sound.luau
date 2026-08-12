-- STEP 6 verification for the sound system. See REPORT.md.
--
--   lune run dev/analysis/verify_sound.luau
--
-- Run from the REPO ROOT. Deterministic; no sampling, no seed. Prints to stdout
-- only; writes nothing to dev/out. Exits non-zero if any check fails.
--
-- ===== WHAT THIS CAN AND CANNOT PROVE, stated first because the distinction is
-- the whole shape of this pass. Nobody involved can hear anything, so this
-- checks STRUCTURE: that every id is unset, that nothing plays by accident,
-- that the one module allowed to make a Sound is the only one that does, that
-- no world sound can carry across the map, and that a missing id warns once
-- rather than per call. It cannot and does not check that any sound is
-- appropriate, audible, or correctly mixed -- those need ears and a filled-in
-- registry.
--
-- REQUIRED FOR REAL through dev/rbxshim.luau: SoundConfig (the actual registry,
-- including its load-time asserts) and SoundPlayer (the actual nil-safe
-- resolve). The shim's audio service stubs are deliberately thin -- see their
-- own comment in rbxshim.luau for why a passing run here is not a claim that
-- audio works.
local fs = require("@lune/fs")
local process = require("@lune/process")

local C = require("./common")
local shim = C.shim

local Config = shim.ReplicatedStorage:FindFirstChild("Config")
shim.registerModule(Config, "SoundConfig", "src/ReplicatedStorage/Config/SoundConfig.luau")
local SoundConfig = shim.loadLuauModule("src/ReplicatedStorage/Config/SoundConfig.luau")
local SoundPlayer = shim.loadLuauModule("src/ReplicatedStorage/SoundPlayer.luau")

local failures = {}
local function check(condition: boolean, message: string)
	if not condition then
		table.insert(failures, message)
	end
	print(string.format("  [%s] %s", if condition then "PASS" else "FAIL", message))
end

-- Stable ordering everywhere below, so the output diffs cleanly run to run.
local sortedKeys = {}
for key in SoundConfig.SOUNDS do
	table.insert(sortedKeys, key)
end
table.sort(sortedKeys)

--=================== 6a: every id nil, config loads clean ===================--
-- The load itself is half the check: SoundConfig asserts at require time that
-- every spatial entry carries rolloff distances, that every group name is real,
-- and that any non-nil id is a well-formed rbxassetid:// string. Reaching this
-- line at all means all three passed for all entries.
print(string.format("SoundConfig loaded: %d entries across %d groups\n", #sortedKeys, #SoundConfig.GROUP_ORDER))

print("6a. every registry entry ships with a nil asset id")
local filled = {}
for _, key in sortedKeys do
	if SoundConfig.SOUNDS[key].id ~= nil then
		table.insert(filled, key)
	end
end
check(#filled == 0, string.format(
	"all %d entries have id = nil%s",
	#sortedKeys,
	if #filled == 0 then "" else " -- FILLED: " .. table.concat(filled, ", ")
))

--============== 6b: no Instance.new("Sound") outside SoundPlayer ==============--
-- Greps the real tree rather than asserting the convention in prose. This is the
-- ENFORCEMENT for "one construction path" -- there is no language-level way to
-- prevent another script calling Instance.new("Sound"), so the rule is kept by a
-- test that fails when it is broken.
print("\n6b. only SoundPlayer creates a Sound")
local ALLOWED_SOUND_CREATOR = "src/ReplicatedStorage/SoundPlayer.luau"

local function listLuauFiles(dir: string, out: { string })
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			listLuauFiles(path, out)
		elseif string.match(name, "%.luau$") then
			table.insert(out, path)
		end
	end
	return out
end

local srcFiles = listLuauFiles("src", {})
table.sort(srcFiles)
local offenders = {}
local creatorHits = 0
for _, path in srcFiles do
	local source = C.readSource(path)
	-- Both the Sound and the SoundGroup constructors; either one outside the
	-- player would be a second construction path.
	for _, pattern in { 'Instance%.new%("Sound"%)', 'Instance%.new%("SoundGroup"%)' } do
		local _, count = string.gsub(source, pattern, "")
		if count > 0 then
			if path == ALLOWED_SOUND_CREATOR then
				creatorHits += count
			else
				table.insert(offenders, string.format("%s (%d)", path, count))
			end
		end
	end
end
print(string.format("    scanned %d .luau files under src/", #srcFiles))
check(#offenders == 0, string.format(
	"no Sound/SoundGroup constructed outside %s%s",
	ALLOWED_SOUND_CREATOR,
	if #offenders == 0 then "" else " -- OFFENDERS: " .. table.concat(offenders, ", ")
))
check(creatorHits > 0, string.format("%s does construct them (%d sites) -- the rule is not vacuous", ALLOWED_SOUND_CREATOR, creatorHits))

--=============== 6c: the flight loop's teardown paths ===============--
-- The flight rush is the one looping, player-owned sound, so a missed teardown
-- is a permanent drone. Checked by reading the real client source for the three
-- call sites and the contexts they sit in.
print("\n6c. the flight rush is stopped on every exit path")
local launchClient = C.readSource("src/StarterPlayer/StarterPlayerScripts/LaunchClient.client.luau")
local _, stopCallCount = string.gsub(launchClient, "stopFlightWind%(%)", "")
-- One definition plus FOUR call sites: the three teardown paths below, plus a
-- defensive stop inside the FlightStarted handler so a second flight starting
-- without an intervening reset cannot orphan the previous loop.
check(stopCallCount == 5, string.format("stopFlightWind appears 5 times (1 definition + 4 call sites); found %d", stopCallCount))
for _, context in {
	{ needle = "local function resetFlightState", label = "resetFlightState -- every cancellation (death, disconnect, dismount) via clearActiveRider's resetReadyRemote" },
	{ needle = "local function setGrounded", label = "setGrounded -- the catch-all every route back to neutral funnels through" },
	{ needle = "flightActive = false\n\t\t\treturn", label = "the landing frame -- an ordinary landing, which cannot wait for ResetReady 0.75s later" },
} do
	check(string.find(launchClient, context.needle, 1, true) ~= nil, "teardown context present: " .. context.label)
end
-- stopLoop must tolerate being called twice and being called with nothing, or
-- the three-site design is unsafe rather than belt-and-braces.
local okDoubleStop = pcall(function()
	SoundPlayer.stopLoop(nil)
	SoundPlayer.stopLoop(nil)
end)
check(okDoubleStop, "stopLoop(nil) is a safe no-op, and is safe to call repeatedly")

--=========== 6d: no world sound carries across the map ===========--
-- The road runs from RUNWAY_START_Z back through 74 bands of
-- RUNWAY_BAND_LENGTH_STUDS; the plots sit at BASE_PLOT_CENTER_Z. The worst case
-- for "audible where it should not be" is the furthest landing against the
-- nearest base.
print("\n6d. every world sound's reach, against the map's real dimensions")
local runwayStartZ = C.RunwayGeometry.RUNWAY_START_Z
local roadFarZ = runwayStartZ - #C.LuckCurve.VALUES * C.LaunchConfig.RUNWAY_BAND_LENGTH_STUDS
local mapLengthStuds = math.abs(roadFarZ - C.BaseConfig.BASE_PLOT_CENTER_Z)
-- The deepest landing that can actually happen: tier 10's perfect launch.
local deepestLandingZ = C.perfectLaunchForTier(C.SWING_TIER_COUNT).landingZ
local deepestLandingToBase = math.abs(C.BaseConfig.BASE_PLOT_CENTER_Z - deepestLandingZ)
print(string.format("    road spans Z %.1f to %.1f; plots sit at Z %.1f", runwayStartZ, roadFarZ, C.BaseConfig.BASE_PLOT_CENTER_Z))
print(string.format("    map length end to end: %.0f studs", mapLengthStuds))
print(string.format("    deepest real landing (tier %d) at Z %.1f, i.e. %.0f studs from a base", C.SWING_TIER_COUNT, deepestLandingZ, deepestLandingToBase))
print("")
print("    entry                    2D/3D  max audible  vs deepest-landing-to-base")
local worstReach = 0
for _, key in sortedKeys do
	local entry = SoundConfig.SOUNDS[key]
	if entry.spatial then
		local reach = entry.rollOffMaxDistance :: number
		worstReach = math.max(worstReach, reach)
		print(string.format("    %-24s  3D     %6.0f       %.1f%% of it", key, reach, reach / deepestLandingToBase * 100))
		check(reach < deepestLandingToBase, string.format(
			"%s reaches %.0f studs, well short of the %.0f studs from the deepest landing to a base",
			key, reach, deepestLandingToBase
		))
	end
end
check(worstReach < mapLengthStuds, string.format(
	"the loudest-reaching world sound (%.0f studs) cannot cross the %.0f-stud map", worstReach, mapLengthStuds
))
-- Linear rolloff is what makes RollOffMaxDistance a true silence boundary; the
-- default Inverse mode would leave every one of these faintly audible from
-- anywhere, which is the exact bug the distances above are chosen to prevent.
local soundPlayerSource = C.readSource("src/ReplicatedStorage/SoundPlayer.luau")
check(string.find(soundPlayerSource, "Enum.RollOffMode.Linear", 1, true) ~= nil,
	"SoundPlayer forces RollOffMode.Linear, so RollOffMaxDistance is a real cutoff and not merely where attenuation stops")

-- Lane geometry, for the stacking question: how many of the six lanes fall
-- inside the swing-area sounds' reach.
local lanePitch = C.LaunchConfig.RUNWAY_WIDTH_STUDS / C.LaneConfig.LANE_COUNT
local launchReach = SoundConfig.SOUNDS.WORLD_LAUNCH_RELEASE.rollOffMaxDistance :: number
-- STRICTLY inside: under Linear rolloff a listener exactly at
-- RollOffMaxDistance hears nothing, so a lane sitting precisely on the boundary
-- is not a lane that hears it. At a 60-stud pitch and a 120-stud reach that is
-- the difference between counting 5 lanes and the true 3.
local lanesEitherSide = math.ceil(launchReach / lanePitch) - 1
local lanesHeard = math.min(C.LaneConfig.LANE_COUNT, 1 + 2 * lanesEitherSide)
print(string.format("\n    lane pitch %.0f studs; WORLD_LAUNCH_RELEASE reaches %.0f -> at most %d of %d lanes audible at once",
	lanePitch, launchReach, lanesHeard, C.LaneConfig.LANE_COUNT))
check(lanesHeard < C.LaneConfig.LANE_COUNT, string.format(
	"a launch cannot stack across all %d lanes (at most %d: this lane and %d either side)",
	C.LaneConfig.LANE_COUNT, lanesHeard, lanesEitherSide
))

--=============== 6e: the missing-id warning fires once per key ===============--
-- Exercises the REAL SoundPlayer. Both branches of resolve() are covered: a key
-- that does not exist at all, and a key that exists with a nil id (which is every
-- entry as this ships). Neither may error, and neither may warn twice.
print("\n6e. the missing-id warning fires once per key, not once per call")
local before = SoundPlayer._warnedCount()
local okCalls = pcall(function()
	for _ = 1, 50 do
		SoundPlayer.play2D("MISSING_ENTRY")
		SoundPlayer.play2D("UI_COLLECT")
	end
end)
local after = SoundPlayer._warnedCount()
print(string.format("    100 calls across 2 keys (50 each): warned keys went %d -> %d", before, after))
check(okCalls, "100 calls with a bad key and an unfilled key raised no error")
check(after - before == 2, string.format(
	"exactly 2 new warnings for 2 distinct keys over 100 calls; got %d", after - before
))
local repeatBefore = SoundPlayer._warnedCount()
for _ = 1, 25 do
	SoundPlayer.play2D("MISSING_ENTRY")
end
check(SoundPlayer._warnedCount() == repeatBefore, "25 further calls with an already-warned key add no warnings at all")
-- A no-op must still be a clean no-op for the caller: nil back, not an error and
-- not a half-built Sound.
check(SoundPlayer.play2D("MISSING_ENTRY") == nil, "play2D returns nil for an unknown key")
check(SoundPlayer.play2D("UI_COLLECT") == nil, "play2D returns nil for an entry whose id is still unset")
check(SoundPlayer.startLoop("FLIGHT_WIND_LOOP") == nil, "startLoop returns nil for an unfilled entry, which stopLoop then accepts")

--============ 6f source data: the registry, as a shopping table ============--
print("\n6f. the registry (full table is in REPORT.md)")
print("    entry                     group    2D/3D  vol   pitch  loop  rolloff")
for _, key in sortedKeys do
	local e = SoundConfig.SOUNDS[key]
	print(string.format("    %-24s  %-7s  %-5s  %.2f  %.2f   %-4s  %s",
		key, e.group, if e.spatial then "3D" else "2D", e.volume, e.pitch,
		if e.looped then "yes" else "no",
		if e.spatial then string.format("%.0f-%.0f", e.rollOffMinDistance :: number, e.rollOffMaxDistance :: number) else "--"))
end

-- Group coverage: every declared group should actually be used, or it is a
-- mixer channel controlling nothing.
print("")
local usedGroups: { [string]: number } = {}
for _, key in sortedKeys do
	local group = SoundConfig.SOUNDS[key].group
	usedGroups[group] = (usedGroups[group] or 0) + 1
end
for _, groupName in SoundConfig.GROUP_ORDER do
	local count = usedGroups[groupName] or 0
	print(string.format("    group %-7s volume %.2f  %d entries", groupName, SoundConfig.GROUP_VOLUMES[groupName], count))
	check(count > 0, string.format("group %q has at least one entry", groupName))
end

--=================== no gameplay behaviour changed ===================--
-- The pass's hardest constraint, checked the only way it can be from here: the
-- files this pass touched must differ from their pre-pass versions ONLY by
-- added lines, never by removed or rewritten ones. A sound call is additive; a
-- changed condition or a moved call is not.
print("\nadditive-only check against the sound pass's own base and tip")
--
-- ===== PINNED AT BOTH ENDS, AND THAT IS THE FIX (see REPORT.md). This used to
-- compare BASE_COMMIT against **HEAD**, which quietly turned a claim about ONE
-- pass into a claim about every commit ever made after it. The per-slot
-- collection pass legitimately deleted lines in five files, so from that commit
-- onward this check failed permanently, and for a reason it was never written to
-- detect. A test that is always red gets ignored, and then a real failure hides
-- inside it.
--
-- Both ends are the sound pass's OWN commits now -- its base and its tip -- so
-- the diff describes exactly the change this file was written to police, and
-- stays true no matter what lands afterwards. If later work ever edits the sound
-- system in a way this ought to catch, the right move is to re-point END_COMMIT
-- at that work's own tip, not to unpin it again.
local BASE_COMMIT = "2d28d1d"
local END_COMMIT = "59e38c2"
local diffOk, diffResult = pcall(function()
	return process.exec("git", { "diff", "--numstat", BASE_COMMIT, END_COMMIT, "--", "src" }).stdout
end)
if diffOk then
	local clean = true
	for line in string.gmatch(diffResult :: string, "[^\n]+") do
		local added, removed, path = string.match(line, "^(%d+)%s+(%d+)%s+(.+)$")
		if added and tonumber(removed) > 0 then
			-- Files created by this pass have 0 removals; files merely wired
			-- into should too.
			print(string.format("    %s: +%s -%s", path, added, removed))
			clean = false
		end
	end
	check(clean, "every pre-existing file this pass touched gained lines and lost none")
else
	print("    (git unavailable -- skipped)")
end

--================================= result =================================--
print("")
if #failures > 0 then
	for _, message in failures do
		print("FAILED: " .. message)
	end
	error(string.format("%d check(s) failed", #failures))
end
print("VERIFY PASSED: every check agrees with the edited tree.")
