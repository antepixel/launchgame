-- STEP 3 verification for the leaderboard. See REPORT.md.
--
--   lune run dev/analysis/verify_leaderstats.luau
--
-- Run from the REPO ROOT. Deterministic; no sampling, no seed. Prints to stdout
-- only; writes nothing to dev/out. Exits non-zero if any check fails.
--
-- REQUIRED FOR REAL through dev/rbxshim.luau: MoneyFormat (the actual formatter
-- the columns render through), SlimeData/SlimeUpgrade/BaseConfig (the actual
-- income and ceiling figures), ShopConfig (the actual top price).
--
-- WHAT IS SCANNED RATHER THAN RUN, and why: PlayerProfile.luau requires Players,
-- HttpService and a DataStore-backed PlayerStore at module scope, so it cannot
-- be loaded outside the game and the wiring cannot be exercised here. What CAN
-- be checked -- and is the thing most likely to rot -- is that every function
-- which changes a leaderboard quantity also refreshes it. That is a property of
-- the source, and the scan below reads it out of the real file.
--
-- EVERY READ GOES THROUGH common.readSource, which normalises CRLF -> LF.
local C = require("./common")
local shim = C.shim

shim.registerModule(shim.ReplicatedStorage:FindFirstChild("Config"), "MoneyFormat", "src/ReplicatedStorage/Config/MoneyFormat.luau")
local MoneyFormat = shim.loadLuauModule("src/ReplicatedStorage/Config/MoneyFormat.luau")

local failures = {}
local function check(condition: boolean, message: string)
	if not condition then
		table.insert(failures, message)
	end
	print(string.format("  [%s] %s", if condition then "PASS" else "FAIL", message))
end

--============================ The source, parsed ============================--
-- Comments stripped QUOTE-AWARE. The naive gsub("%-%-.*$", "") cuts into string
-- literals, and this codebase's own strings contain "--" as an em-dash -- it
-- silently hid a whole string from a previous pass's survey. A comment mentioning
-- refreshLeaderstats must not count as a call site, and a commented-out call must
-- not count as present, so this has to be right.
local function stripComments(source: string): string
	local out = {}
	for line in string.gmatch(source, "([^\n]*)\n?") do
		local quote, cut, i = nil, #line + 1, 1
		while i <= #line do
			local ch = string.sub(line, i, i)
			if quote then
				if ch == "\\" then
					i += 1
				elseif ch == quote then
					quote = nil
				end
			elseif ch == '"' or ch == "'" then
				quote = ch
			elseif ch == "-" and string.sub(line, i + 1, i + 1) == "-" then
				cut = i
				break
			end
			i += 1
		end
		table.insert(out, string.sub(line, 1, cut - 1))
	end
	return table.concat(out, "\n")
end

local PROFILE_PATH = "src/ServerScriptService/PlayerProfile.luau"
local source = stripComments(C.readSource(PROFILE_PATH))

-- Every top-level function in the file, with the line range it owns. Every
-- function in PlayerProfile.luau is top-level (there are no nested named
-- functions), so a line's owner is simply the last function header at or above
-- it.
local lines = {}
for line in string.gmatch(source, "([^\n]*)\n?") do
	table.insert(lines, line)
end

local function ownerOf(lineNumber: number): string
	local owner = "(file scope)"
	for i = 1, lineNumber do
		local name = string.match(lines[i], "^local function ([%w_]+)")
			or string.match(lines[i], "^function PlayerProfile%.([%w_]+)")
		if name then
			owner = name
		end
	end
	return owner
end

local function functionsContaining(needle: string): { [string]: number }
	local found = {}
	for i, line in lines do
		if string.find(line, needle, 1, true) then
			local owner = ownerOf(i)
			found[owner] = (found[owner] or 0) + 1
		end
	end
	return found
end

local function sortedKeys(map): { string }
	local keys = {}
	for key in map do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

--=================== 0a: nothing else writes to leaderstats ===================--
print("0a. leaderstats exists in exactly one place")
local FILES = {
	"src/ServerScriptService/PlayerProfile.luau",
	"src/ServerScriptService/LaunchServer.server.luau",
	"src/ServerScriptService/InventoryServer.server.luau",
	"src/ServerScriptService/UpgradeServer.server.luau",
	"src/ServerScriptService/ShopServer.server.luau",
	"src/ServerScriptService/DevPanelServer.server.luau",
	"src/ServerScriptService/MapBuilder.server.luau",
	"src/ServerScriptService/RunwayBuilder.server.luau",
	"src/StarterPlayer/StarterPlayerScripts/BaseClient.client.luau",
	"src/StarterPlayer/StarterPlayerScripts/InventoryClient.client.luau",
	"src/StarterPlayer/StarterPlayerScripts/ShopClient.client.luau",
	"src/StarterPlayer/StarterPlayerScripts/LaunchClient.client.luau",
	"src/StarterPlayer/StarterPlayerScripts/SlimeUpgradeTagClient.client.luau",
	"src/StarterPlayer/StarterPlayerScripts/DevPanelClient.client.luau",
}
local writers = {}
for _, path in FILES do
	if string.find(stripComments(C.readSource(path)), "leaderstats", 1, true) then
		table.insert(writers, path)
	end
end
check(#writers == 1 and writers[1] == PROFILE_PATH,
	string.format("exactly one file mentions leaderstats in code: %s", table.concat(writers, ", ")))

--=============== 3b/3c/3d: every write site refreshes the board ===============--
-- THE CORE STRUCTURAL CHECK. Build the set of functions that change a
-- leaderboard quantity, and the set that refresh it, and require the first to be
-- a subset of the second. This is what makes "we did not miss one" a checkable
-- property rather than a claim -- and it keeps working when a NEW write site is
-- added later, which is exactly when a hand-written list would go stale.
--
-- The three anchors, one per column:
--   Money    every money mutation in this file is immediately followed by
--            SetAttribute("Money", ...) -- that pairing is a pre-existing
--            invariant of the file, not something this pass introduced.
--   Swing    same, with SetAttribute("SwingTier", ...).
--   $/s      the rate is a function of slots and levels, and syncClientState is
--            documented as being "called at the end of every function in this
--            file that touches slots or inventory".
print("\n3b/3c/3d. every function that changes a column also refreshes the board")
local moneyWriters = functionsContaining('SetAttribute("Money"')
local tierWriters = functionsContaining('SetAttribute("SwingTier"')
local rateWriters = functionsContaining("syncClientState(profile)")
local refreshers = functionsContaining("refreshLeaderstats(profile)")

-- buildBaseFolder writes the two attributes at their initial values before any
-- profile exists to refresh from -- it is the folder builder, not a mutation
-- site. buildLeaderstats covers the same instant, with the same values.
local NOT_A_MUTATION_SITE = { buildBaseFolder = true }

local function requireRefresh(label: string, writerSet)
	for _, name in sortedKeys(writerSet) do
		if not NOT_A_MUTATION_SITE[name] then
			check(refreshers[name] ~= nil,
				string.format("%s: %s() refreshes the leaderboard", label, name))
		end
	end
end
requireRefresh("money", moneyWriters)
requireRefresh("tier", tierWriters)
requireRefresh("rate", rateWriters)

-- Named individually, because these are the cases the brief calls out and a
-- reader should see them asserted by name rather than inferred from a loop.
check(refreshers.upgradeSlime ~= nil, "3c: upgradeSlime refreshes -- an upgrade moves BOTH money and $/s")
check(rateWriters.upgradeSlime ~= nil, "3c: upgradeSlime really is a rate-change site (it calls syncClientState)")
check(refreshers.buyNextTier ~= nil, "3d: buyNextTier refreshes -- the Swing column")
check(refreshers.bankSlot ~= nil, "3b: bankSlot refreshes -- every collect, and every removal's banking")
check(refreshers.removeToInventory ~= nil, "3b/3c: removeToInventory refreshes AFTER the slot is cleared")
check(refreshers.onPlayerAdded ~= nil, "3a: onPlayerAdded refreshes at the bottom of the load")

print(string.format("    money-write functions: %s", table.concat(sortedKeys(moneyWriters), ", ")))
print(string.format("    tier-write  functions: %s", table.concat(sortedKeys(tierWriters), ", ")))
print(string.format("    rate-write  functions: %s", table.concat(sortedKeys(rateWriters), ", ")))
print(string.format("    refreshing  functions: %s", table.concat(sortedKeys(refreshers), ", ")))

-- The rule the file's own comments claim: EVERY syncClientState call site is
-- followed by a refresh. Checked as a line-adjacency property, not just a
-- same-function one, so a refresh sitting in a different branch of the same
-- function cannot satisfy it.
print("\n    every syncClientState(profile) line is followed by a refreshLeaderstats(profile) line")
local syncLines, satisfied = 0, 0
for i, line in lines do
	if string.find(line, "syncClientState(profile)", 1, true) then
		syncLines += 1
		-- Skip blank lines: stripComments leaves an EMPTY line where a comment
		-- was, and most of these call sites carry a line or two explaining which
		-- columns move. "Immediately followed" means "the next line of code".
		local j = i + 1
		while lines[j] and string.match(lines[j], "^%s*$") do
			j += 1
		end
		if lines[j] and string.find(lines[j], "refreshLeaderstats(profile)", 1, true) then
			satisfied += 1
		end
	end
end
check(syncLines > 0 and syncLines == satisfied,
	string.format("%d of %d syncClientState call sites are immediately followed by a refresh", satisfied, syncLines))

--=============== 1g: $/s is not re-derived anywhere ===============--
print("\n1g. the rate shown is the same expression the accrual pays")
local refreshBody = ""
do
	local startIndex = string.find(source, "local function refreshLeaderstats", 1, true)
	if startIndex then
		refreshBody = string.sub(source, startIndex, (string.find(source, "\nend\n", startIndex, true) or #source))
	end
end
check(refreshBody ~= "", "refreshLeaderstats was found in the source")
check(string.find(refreshBody, "totalIncomePerSecond(profile)", 1, true) ~= nil,
	"refreshLeaderstats calls totalIncomePerSecond -- the same function the tick and the offline accrual use")
check(string.find(refreshBody, "incomeForLevel", 1, true) == nil
	and string.find(refreshBody, "SLIMES[", 1, true) == nil,
	"refreshLeaderstats does NOT re-derive the rate from the income tables itself")
-- ONE EXPRESSION FOR WHAT A SLOT EARNS, still -- checked by OWNER rather than by
-- a raw count, which says what the property actually is. Exactly one function
-- turns a slot into a rate (slotIncomePerSecond); the only other readers of the
-- level formula are the two that paint the on-slime income LABEL, which is a
-- rendering of one slime and not a rate anything is paid from.
local incomeForLevelOwners = functionsContaining("SlimeUpgrade.incomeForLevel")
local EXPECTED_INCOME_READERS = { slotIncomePerSecond = true, spawnSlimeVisual = true, refreshSlimeVisualLabel = true }
local unexpected = {}
for _, name in sortedKeys(incomeForLevelOwners) do
	if not EXPECTED_INCOME_READERS[name] then
		table.insert(unexpected, name)
	end
end
check(#unexpected == 0 and incomeForLevelOwners.slotIncomePerSecond ~= nil,
	string.format("the level formula is read only by slotIncomePerSecond and the two label painters (found: %s)",
		table.concat(sortedKeys(incomeForLevelOwners), ", ")))

--=============== 2a-2d: what the pass was told NOT to do ===============--
print("\n2a-2d. the four prohibitions, read off the source")
local buildBody = ""
do
	local startIndex = string.find(source, "local function buildLeaderstats", 1, true)
	if startIndex then
		buildBody = string.sub(source, startIndex, (string.find(source, "\nend\n", startIndex, true) or #source))
	end
end
check(buildBody ~= "", "buildLeaderstats was found in the source")
local _, valueCount = string.gsub(buildBody, "%.Parent = folder", "")
check(valueCount == 3, string.format("2a: exactly %d columns, not four -- no pending-income column", valueCount))
check(string.find(buildBody, "pending", 1, true) == nil and string.find(refreshBody, "pending", 1, true) == nil,
	"2a: neither the builder nor the refresher mentions the pending pot")
check(string.find(refreshBody, "task.wait", 1, true) == nil
	and string.find(refreshBody, "Heartbeat", 1, true) == nil
	and string.find(refreshBody, "RunService", 1, true) == nil,
	"2b: no timer and no per-frame loop -- refresh is call-driven only")
-- 2c: the save shape is unchanged. Ten fields, exactly as before this pass.
local saveBody = ""
do
	local startIndex = string.find(source, "local function toSaveShape", 1, true)
	saveBody = string.sub(source, startIndex, (string.find(source, "\nend\n", startIndex, true) or #source))
end
local saveFields = {}
for name in string.gmatch(saveBody, "\n\t\t([%a][%w]*) = ") do
	table.insert(saveFields, name)
end
table.sort(saveFields)
local EXPECTED_SAVE = { "chestPending", "chestsOpened", "inventory", "lastSeen", "levels", "money", "pendingBySlot", "seen", "slots", "swingTier" }
check(table.concat(saveFields, ",") == table.concat(EXPECTED_SAVE, ","),
	string.format("2c: the save shape is unchanged (%s)", table.concat(saveFields, ", ")))
check(string.find(saveBody, "leaderstats", 1, true) == nil, "2c: toSaveShape does not persist anything about the leaderboard")
-- 2d: the HUD stack is untouched.
local baseClient = stripComments(C.readSource("src/StarterPlayer/StarterPlayerScripts/BaseClient.client.luau"))
check(string.find(baseClient, "leaderstats", 1, true) == nil, "2d: BaseClient (the HUD) knows nothing about the leaderboard")

--=============== 1c/1d: the three columns, and their types ===============--
print("\n1b/1c/1d. three columns, in order, with the right types")
check(string.find(buildBody, 'Instance.new("IntValue")', 1, true) ~= nil, "1c: Swing is an IntValue (sorts numerically)")
local _, stringValueCount = string.gsub(buildBody, 'Instance%.new%("StringValue"%)', "")
check(stringValueCount == 2, "1d: Money and $/s are StringValues")
check(string.find(buildBody, 'folder.Name = "leaderstats"', 1, true) ~= nil, "the folder is named exactly \"leaderstats\"")
check(string.find(buildBody, "folder.Parent = player", 1, true) ~= nil, "the folder is parented to the Player")
-- Order is parent order; assert the three .Parent = folder lines appear in the
-- documented sequence.
local swingAt = string.find(buildBody, 'swing.Name = "Swing"', 1, true)
local moneyAt = string.find(buildBody, 'money.Name = "Money"', 1, true)
local rateAt = string.find(buildBody, 'rate.Name = "$/s"', 1, true)
check(swingAt ~= nil and moneyAt ~= nil and rateAt ~= nil and swingAt < moneyAt and moneyAt < rateAt,
	"1b: the column order in source is Swing, Money, $/s")
-- The tradeoff is recorded where a future editor will see it.
local rawProfile = C.readSource(PROFILE_PATH)
check(string.find(string.lower(rawProfile), "alphabetically", 1, true) ~= nil
	and string.find(rawProfile, "2,147,483,647", 1, true) ~= nil,
	"1d: the alphabetical-sort tradeoff and the IntValue cap are both recorded in a comment")

--=============== 3e: MoneyFormat at the extremes ===============--
print("\n3e. MoneyFormat across the whole range the columns must carry")
local INT_VALUE_MAX = 2147483647
local topSlime = 0
for _, slime in C.SlimeData.SLIMES do
	topSlime = math.max(topSlime, slime.incomePerSecond)
end
local ceilingBase = topSlime * C.SLOT_COUNT
local ceilingMaxed = ceilingBase * C.maxLevelMultiplier()
local topPrice = C.ShopConfig.SWING_TIER_PRICES[#C.ShopConfig.SWING_TIER_PRICES]

local cases = {
	{ value = 0, expect = "$0", note = "a brand-new profile" },
	{ value = 999, expect = "$999", note = "just under the first suffix" },
	{ value = 1500, expect = "$1.5K", note = "" },
	{ value = 9100000, expect = "$9.1M", note = "" },
	{ value = topPrice, expect = "$800B", note = "the top swing tier's price" },
	{ value = ceilingMaxed, expect = "$244.5M", note = "a fully levelled ceiling base's income/s" },
	{ value = INT_VALUE_MAX, expect = "$2.1B", note = "the IntValue cap -- what an integer column could not exceed" },
}
for _, case in cases do
	local rendered = MoneyFormat.format(case.value)
	print(string.format("    %22.4f -> %-10s %s", case.value, rendered, case.note))
	check(rendered == case.expect, string.format("MoneyFormat.format(%s) == %q", C.fmt(case.value), case.expect))
end
check(topPrice > INT_VALUE_MAX,
	string.format("the top price ($%s) exceeds the IntValue cap ($%s) -- an integer Money column WOULD overflow in ordinary play",
		C.fmt(topPrice), C.fmt(INT_VALUE_MAX)))
check(ceilingMaxed < INT_VALUE_MAX,
	string.format("the ceiling INCOME ($%s/s) fits an IntValue, but money accumulated from it does not -- both columns use one type for one reason",
		C.fmt(ceilingMaxed)))
-- The sort cost, demonstrated rather than asserted in prose.
check(MoneyFormat.format(9100000) > MoneyFormat.format(800e9),
	'the accepted cost, demonstrated: "$9.1M" sorts ABOVE "$800B" alphabetically')

-- Fractional money reaches the formatter (income accrues as a float and bankSlot
-- adds it whole), so the sub-$1000 integer path must tolerate a non-integer.
for _, value in { 0.5, 12.75, 999.99 } do
	local ok, rendered = pcall(MoneyFormat.format, value)
	check(ok, string.format("MoneyFormat tolerates fractional money (%.2f -> %s)", value, tostring(rendered)))
end

--=============== 3a/3f: the load window ===============--
print("\n3a/3f. nothing wrong is displayed during the DataStore read")
local addedBody = ""
do
	local startIndex = string.find(source, "local function onPlayerAdded", 1, true)
	addedBody = string.sub(source, startIndex, (string.find(source, "\nend)\nend\n", startIndex, true) or #source))
end
check(string.find(addedBody, "buildLeaderstats(player)", 1, true) ~= nil, "the folder is built in onPlayerAdded")
local buildAt = string.find(addedBody, "buildLeaderstats(player)", 1, true)
local loadAt = string.find(addedBody, "PlayerStore.load(player.UserId)", 1, true)
check(buildAt ~= nil and loadAt ~= nil and buildAt < loadAt,
	"3f: it is built BEFORE the load starts, so the player is never without a leaderboard row")
-- The starting values must equal the fresh-profile values, or the pre-load
-- display would be wrong rather than merely early.
check(string.find(buildBody, "swing.Value = 1", 1, true) ~= nil, "3f: Swing starts at 1, which IS a fresh profile's tier")
local _, zeroFormats = string.gsub(buildBody, "MoneyFormat%.format%(0%)", "")
check(zeroFormats == 2, "3f: Money and $/s both start at MoneyFormat.format(0), which IS a fresh profile's balance and rate")
check(string.find(addedBody, "money = 0,", 1, true) ~= nil and string.find(addedBody, "swingTier = 1,", 1, true) ~= nil,
	"3f: the profile literal really does start at money 0 / tier 1, so the starting columns are true, not placeholders")
-- And a failed load leaves them true rather than stale.
local bailAt = string.find(addedBody, "if not ok then", 1, true)
local refreshAt = string.find(addedBody, "refreshLeaderstats(profile)", 1, true)
check(bailAt ~= nil and refreshAt ~= nil and bailAt < refreshAt,
	"3a: a FAILED load returns before the refresh -- and its session is a blank profile, for which 1/$0/$0 is correct")
local syncAt = string.find(addedBody, "syncClientState(profile)", 1, true)
check(syncAt ~= nil and syncAt < refreshAt,
	"3a: the refresh is the LAST line of the load, after slots and levels are populated, so $/s is right on the first paint")

--=============== 3g: nothing was added to the save ===============--
-- Asserted above under 2c; restated here so STEP 3's own list is complete.
print("\n3g. nothing was added to the save shape -- see the 2c check above")
check(#saveFields == 10, string.format("3g: toSaveShape still writes exactly 10 fields (%d)", #saveFields))

--================================= result =================================--
print("")
if #failures > 0 then
	for _, message in failures do
		print("FAILED: " .. message)
	end
	error(string.format("%d check(s) failed", #failures))
end
print("VERIFY PASSED: every check agrees with the edited tree.")
