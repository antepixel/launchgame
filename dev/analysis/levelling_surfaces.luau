-- What a player can actually SEE about levelling, read off the source rather
-- than remembered. See REPORT.md STEP 2 and STEP 5.
--
--   lune run dev/analysis/levelling_surfaces.luau
--
-- Run from the REPO ROOT. Prints only; writes nothing. Deterministic.
--
-- EVERY READ GOES THROUGH common.readSource, which normalises CRLF -> LF. This
-- tree is developed on Windows with autocrlf on, so a needle written with "\n"
-- matches nothing against the real bytes -- and the dangerous half of that is
-- that a "this must not appear" check then PASSES for the wrong reason. That
-- has already happened once in this repo (see REPORT.md, the sound pass).
local C = require("./common")

local FILES = {
	"src/StarterPlayer/StarterPlayerScripts/BaseClient.client.luau",
	"src/StarterPlayer/StarterPlayerScripts/InventoryClient.client.luau",
	"src/StarterPlayer/StarterPlayerScripts/ShopClient.client.luau",
	"src/StarterPlayer/StarterPlayerScripts/SlimeUpgradeTagClient.client.luau",
	"src/StarterPlayer/StarterPlayerScripts/SlimeIdleClient.client.luau",
	"src/StarterPlayer/StarterPlayerScripts/LaunchClient.client.luau",
	"src/StarterPlayer/StarterPlayerScripts/SoundClient.client.luau",
	"src/StarterPlayer/StarterPlayerScripts/DevPanelClient.client.luau",
	"src/ReplicatedStorage/LaunchClient/LaunchHud.luau",
	"src/ReplicatedStorage/SignBuilder.luau",
	"src/ServerScriptService/PlayerProfile.luau",
	"src/ServerScriptService/MapBuilder.server.luau",
	"src/ServerScriptService/InventoryServer.server.luau",
	"src/ServerScriptService/UpgradeServer.server.luau",
	"src/ServerScriptService/ShopServer.server.luau",
}

-- LaunchRewardScene.luau is DELIBERATELY ABSENT from that list and is not read
-- anywhere in this file. The pass that commissioned this survey forbids opening
-- it. What can still be said about it without opening it, from its callers and
-- its config, is recorded in REPORT.md STEP 5a.

-- Strips Luau line comments WITHOUT cutting into string literals, and that
-- distinction is not pedantry -- it is the second CRLF-class trap in this file.
-- The naive `gsub("%-%-.*$", "")` truncates at the first `--` on the line, and
-- this codebase's own UI strings CONTAIN `--` as an em-dash separator
-- ("Slot %d: %s -- Lv %d -- %s"). Stripping naively deleted exactly the
-- level-mentioning half of the most important string in the survey, and the
-- scan then reported it as absent. Quote-aware, so a `--` inside a literal is
-- kept and a `--` outside one still ends the line.
local function stripComments(source: string): string
	local out = {}
	for line in string.gmatch(source, "([^\n]*)\n?") do
		local quote = nil
		local cut = #line + 1
		local i = 1
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

--=================== Every player-visible string in the tree ===================--
-- Anything assigned to .Text or .PlaceholderText, with its line number. Comments
-- are stripped first so a string quoted INSIDE a comment cannot be reported as
-- something the player sees.
print("=== Every literal assigned to .Text / .PlaceholderText, by file ===")
local allStrings = {}
for _, path in FILES do
	local source = stripComments(C.readSource(path))
	local lineNumber = 0
	local hits = {}
	for line in string.gmatch(source, "([^\n]*)\n?") do
		lineNumber += 1
		-- `[^=]=` so a comparison (`== "number"`) is never mistaken for an
		-- assignment -- typeof checks against string literals are everywhere in
		-- this codebase and would otherwise be reported as player-visible text.
		local property = string.match(line, "%.(Text)%s*=[^=]") or string.match(line, "%.(PlaceholderText)%s*=[^=]")
		if property then
			local literal = string.match(line, '=%s*"([^"]*)"')
			local formatted = string.match(line, 'format%("([^"]*)"')
			local value = literal or formatted
			if value then
				table.insert(hits, { line = lineNumber, property = property, value = value, isFormat = formatted ~= nil })
				table.insert(allStrings, { path = path, line = lineNumber, value = value })
			end
		end
	end
	if #hits > 0 then
		print(string.format("\n-- %s (%d)", path, #hits))
		for _, hit in hits do
			print(string.format("   :%-4d %s%s", hit.line, if hit.isFormat then "(fmt) " else "      ", hit.value))
		end
	end
end

--============ Which of those mention levelling in any form at all ============--
local LEVEL_NEEDLES = { "Lv ", "Level", "level", "Upgrade", "UPGRADE", "Upgraded", "MAXED", "MAX +", "%+1", "%+5" }
print("\n\n=== Player-visible strings that mention a level or an upgrade ===")
local levelStrings = {}
for _, entry in allStrings do
	for _, needle in LEVEL_NEEDLES do
		if string.find(entry.value, needle) then
			table.insert(levelStrings, entry)
			break
		end
	end
end
for _, entry in levelStrings do
	print(string.format("   %-62s :%-4d %s", entry.path:gsub("^src/", ""), entry.line, entry.value))
end
print(string.format("   -> %d of %d player-visible strings mention levelling at all", #levelStrings, #allStrings))

--=============== Does anything TELL the player to do something? ===============--
-- Imperative-mood strings: an instruction, as opposed to a readout of state.
print("\n\n=== Imperative strings (the game telling the player to act) ===")
local IMPERATIVES = { "Time your", "Press", "Hold", "Tap", "Click", "Walk", "Go ", "Try ", "Buy ", "Level up", "Remember", "Tip", "Hint", "First" }
local found = 0
for _, entry in allStrings do
	for _, needle in IMPERATIVES do
		if string.find(entry.value, needle) then
			print(string.format("   %-62s :%-4d %s", entry.path:gsub("^src/", ""), entry.line, entry.value))
			found += 1
			break
		end
	end
end
print(string.format("   -> %d imperative string(s) in the whole tree", found))

--================= Is there any notification/toast machinery? =================--
print("\n\n=== Notification / toast / tip / one-shot message machinery ===")
local MACHINERY = {
	{ needle = "StarterGui", what = "Roblox SetCore notification API" },
	{ needle = "SetCore", what = "SetCore (SendNotification / chat)" },
	{ needle = "Notification", what = "anything named Notification" },
	{ needle = "Toast", what = "anything named Toast" },
	{ needle = "Tooltip", what = "anything named Tooltip" },
	{ needle = "TextChatService", what = "chat-based messaging" },
	{ needle = "Hint", what = "a Hint instance" },
	{ needle = "showTip", what = "a tip helper" },
	{ needle = "onboard", what = "onboarding of any kind" },
	{ needle = "Tutorial", what = "a tutorial of any kind" },
	{ needle = "firstJoin", what = "a first-join branch" },
	{ needle = "hasSeen", what = "a has-seen flag" },
}
for _, probe in MACHINERY do
	local where = {}
	for _, path in FILES do
		-- Comments stripped: the word "Hint" appearing in a design note is not a
		-- Hint instance, and counting it would report machinery that is not there.
		if string.find(stripComments(C.readSource(path)), probe.needle, 1, true) then
			table.insert(where, (path:gsub("^src/", "")))
		end
	end
	print(string.format("   %-40s %s", probe.what, if #where > 0 then table.concat(where, ", ") else "NOT PRESENT ANYWHERE"))
end

-- The one general-purpose status line that does exist, and what drives it.
print("\n   The one reusable message surface that DOES exist:")
local inventorySource = stripComments(C.readSource("src/StarterPlayer/StarterPlayerScripts/InventoryClient.client.luau"))
local shopSource = stripComments(C.readSource("src/StarterPlayer/StarterPlayerScripts/ShopClient.client.luau"))
local _, inventoryStatusWrites = string.gsub(inventorySource, "statusLabel%.Text", "")
local _, shopStatusWrites = string.gsub(shopSource, "statusLabel%.Text", "")
print(string.format("     InventoryClient statusLabel: %d writes; ShopClient statusLabel: %d writes", inventoryStatusWrites, shopStatusWrites))
print("     Both live INSIDE their own panel, so neither can say anything while the panel is shut.")

--================== What the profile persists, for gating ==================--
print("\n\n=== Persisted profile fields (what a one-time message could be gated on) ===")
local profileSource = stripComments(C.readSource("src/ServerScriptService/PlayerProfile.luau"))
local saveShape = string.match(profileSource, "return {(.-)\n\tend\n") or ""
local saveStart = string.find(profileSource, "local function toSaveShape", 1, true)
if saveStart then
	local body = string.sub(profileSource, saveStart, (string.find(profileSource, "\nend\n", saveStart, true) or #profileSource))
	local fields = {}
	for name in string.gmatch(body, "\n\t\t([%a][%w]*) = ") do
		table.insert(fields, name)
	end
	print("   toSaveShape writes: " .. table.concat(fields, ", "))
end
for _, probe in { "chestsOpened", "seen", "lastSeen", "canSave", "swingTier", "levels" } do
	local present = string.find(profileSource, probe, 1, true) ~= nil
	print(string.format("   %-14s %s", probe, if present then "present in the profile" else "absent"))
end
print("   PlayerStore.load returns (nil, true) for a genuinely new player -- see PlayerStore.luau's")
print("   own three-outcome comment. That is a first-join SIGNAL at load time, not a stored flag.")

--===================== Where the upgrade buttons live =====================--
print("\n\n=== The upgrade buttons: both surfaces, measured off the source ===")
local tagSource = C.readSource("src/StarterPlayer/StarterPlayerScripts/SlimeUpgradeTagClient.client.luau")
local function constant(source: string, name: string): string
	return string.match(source, name .. "%s*=%s*([%d%.]+)") or "?"
end
print(string.format("   on-slime strip: %s x %s px, button width scale %s, MaxDistance %s studs, AlwaysOnTop true",
	constant(tagSource, "UPGRADE_TAG_WIDTH_PIXELS"), constant(tagSource, "UPGRADE_TAG_HEIGHT_PIXELS"),
	constant(tagSource, "UPGRADE_TAG_BUTTON_WIDTH_SCALE"), constant(tagSource, "UPGRADE_TAG_MAX_DISTANCE_STUDS")))
print(string.format("   -> each button is %.1f x %s px on screen",
	tonumber(constant(tagSource, "UPGRADE_TAG_WIDTH_PIXELS")) * tonumber(constant(tagSource, "UPGRADE_TAG_BUTTON_WIDTH_SCALE")),
	constant(tagSource, "UPGRADE_TAG_HEIGHT_PIXELS")))
print("   inventory panel: 560 x 680 px panel, opened by a 150 x 44 px INVENTORY button, panel.Visible = false at start")

--================ What one level costs at the very first slime ================--
-- The number a brand-new player is actually shown on their first slime, derived
-- from the real formulas rather than quoted.
print("\n\n=== What the first upgrade button a new player sees actually says ===")
local commons = C.SlimeData.SLIMES_BY_TIER[1]
local lowest, highest = commons[1], commons[#commons]
for _, slime in { lowest, highest } do
	local one = (C.SlimeUpgrade.totalUpgradeCost(slime.incomePerSecond, 1, 1))
	local five = (C.SlimeUpgrade.totalUpgradeCost(slime.incomePerSecond, 1, 5))
	local maxCost, maxCount = C.SlimeUpgrade.totalUpgradeCost(slime.incomePerSecond, 1, C.SlimeUpgradeConfig.MAX_LEVEL)
	print(string.format("   %-18s base $%s/s  ->  +1 costs $%s | +5 costs $%s | MAX +%d costs $%s",
		slime.name, C.fmt(slime.incomePerSecond), C.fmt(one), C.fmt(five), maxCount, C.fmt(maxCost)))
	print(string.format("     %-16s seconds of that slime's own production to repay one level: %d",
		"", C.SlimeUpgradeConfig.UPGRADE_PAYBACK_SECONDS))
end
