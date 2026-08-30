--!strict
-- CHECK_PROBE.luau -- does U2_RUNTIME.luau's INSTALLED source parse?
--
--     lune run dev/legendary/check_probe.luau        # from the repo root
--
-- U2_RUNTIME.luau does not run the code it installs; it BUILDS it out of four
-- long-bracket blocks and one string.format, and hands it to the engine. So a
-- syntax error, or a say() whose specifiers and arguments disagree, is not
-- found by reading the file -- it is found by pressing Play, watching nothing
-- print, and going looking. That is an expensive way to learn it, and this is
-- a cheap one.
--
-- It pulls the blocks straight out of the file text and does the SAME format
-- calls the file does, so it is checking the real installed source rather than
-- a copy of it. NOT SHIPPING CODE.
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local PATH = "dev/legendary/U2_RUNTIME.luau"
-- Normalised to LF first: git here has core.autocrlf on, so a fresh checkout
-- has CRLF in the working tree while the long-bracket pattern below anchors on
-- a bare newline. Without this the extraction silently finds NOTHING on someone
-- else's clone, and "no blocks found" reads as "the file changed" rather than
-- "the line endings did". Written with string.char so the fix itself carries no
-- escape that a shell or an editor can quietly rewrite.
local CR, LF = string.char(13), string.char(10)
local text = string.gsub(fs.readFile(PATH), CR .. LF, LF)

-- the file itself
local okSelf, errSelf = pcall(luau.compile, text)
print(string.format("%-28s %s", PATH, okSelf and "parses" or ("FAILS: " .. tostring(errSelf))))
assert(okSelf, "the file does not parse")

-- its four [==[ ]==] blocks, in order
local blocks = {}
local order = {}
for name, body in string.gmatch(text, "local ([%w_]+) = %[==%[\n(.-)%]==%]") do
	blocks[name] = body
	table.insert(order, name)
end
print("blocks found: " .. table.concat(order, ", "))
for _, want in ipairs({ "STATS_SRC", "MEASURE_SRC", "CLIENT_SRC", "SERVER_SRC" }) do
	assert(blocks[want], want .. " not found -- the extraction pattern has drifted")
end

-- the same values the file installs with
local TEXTURE = "rbxassetid://104689541793385"
local CONTROL = "rbxassetid://98429592839825"
local MODEL = "U2ServerBuilt"
local SINK = "http://127.0.0.1:8731/rgba/tiger"

local clientSource = string.format(blocks.CLIENT_SRC, MODEL, TEXTURE, blocks.STATS_SRC)
local serverSource = string.format(blocks.SERVER_SRC, TEXTURE, CONTROL, MODEL, SINK,
	blocks.STATS_SRC, blocks.MEASURE_SRC)

local function check(name, src)
	local ok, err = pcall(luau.compile, src)
	print(string.format("%-28s %6d chars  %s", name, #src, ok and "parses" or ("FAILS: " .. tostring(err))))
	return ok
end

local a = check("generated client source", clientSource)
local b = check("generated server source", serverSource)

-- The two are installed as SEPARATE instances -- the server Script and the
-- LocalScript template under it -- because a runtime server thread may not
-- write Source. Neither one's parsing says anything about the other's, so
-- both are checked.
assert(a and b, "generated source does not parse")

-- Every runtime string.format in the generated sources: does the spec count
-- match the argument count? A mismatch is a runtime error inside the playtest,
-- which is exactly as expensive to find as a syntax error.
local function specs(fmt)
	local n = 0
	local i = 1
	while i <= #fmt do
		local c = string.sub(fmt, i, i)
		if c == "%" then
			local nxt = string.sub(fmt, i + 1, i + 1)
			if nxt == "%" then
				i += 1
			else
				local j = i + 1
				while j <= #fmt and string.find(string.sub(fmt, j, j), "[-+ #0-9.]") do
					j += 1
				end
				n += 1
				i = j
			end
		end
		i += 1
	end
	return n
end

local bad = 0
-- Walk each source and take each say( call to its BALANCED closing paren, so a
-- call whose arguments run onto the next line is counted whole. The first pass
-- of this check flagged ten of those as mismatches and every one was the
-- checker truncating at the newline -- which is its own small lesson about
-- believing a number before asking what it can and cannot see.
for _, src in ipairs({ { "client", clientSource }, { "server", serverSource } }) do
	local text = src[2]
	local at = 1
	while true do
		local s0 = string.find(text, 'say("', at, true)
		if not s0 then break end
		-- find the balanced end of the call
		local depth, k, inStr, esc = 0, s0 + 3, false, false
		while k <= #text do
			local c = string.sub(text, k, k)
			if inStr then
				if esc then esc = false
				elseif c == "\\" then esc = true
				elseif c == '"' then inStr = false end
			elseif c == '"' then inStr = true
			elseif c == "(" then depth += 1
			elseif c == ")" then
				depth -= 1
				if depth == 0 then break end
			end
			k += 1
		end
		local call = string.sub(text, s0, k)
		at = k + 1
		local fmt = string.match(call, 'say%("(.-)"[,%)]')
		if fmt then
			local rest = string.sub(call, #fmt + 7)
			local args, depth2, inStr2, esc2 = 0, 0, false, false
			for q = 1, #rest do
				local c = string.sub(rest, q, q)
				if inStr2 then
					if esc2 then esc2 = false
					elseif c == "\\" then esc2 = true
					elseif c == '"' then inStr2 = false end
				elseif c == '"' then inStr2 = true
				elseif c == "(" or c == "{" then depth2 += 1
				elseif c == ")" or c == "}" then depth2 -= 1
				elseif c == "," and depth2 <= 0 then args += 1 end
			end
			local want = specs(fmt)
			if want ~= args then
				bad += 1
				print(string.format("  %s: %d specs, %d args -- %s", src[1], want, args, fmt))
			end
		end
	end
end
print(string.format("say() format/arg mismatches: %d", bad))
assert(bad == 0, "a say() call in the installed source would error at runtime")
print("OK -- the installed source parses and every say() lines up")

-- ---------------------------------------------------------------------------
-- AND DOES THE INSTRUMENT AGREE WITH THE REFERENCE IT ASSERTS AGAINST?
--
-- sheetStats is Luau and dev/legendary/encode_probe.py is Python, and the
-- probe asserts one against the other's constants at runtime inside a
-- playtest. If they disagree, that assert fires in the one place it is most
-- expensive to debug. So it is settled here instead, on the bake's real bytes:
--
--     python -c "import sys;sys.path.insert(0,'dev/legendary');
--                from meshsink import png_to_rgba;
--                open('tiger.rgba','wb').write(png_to_rgba('dev/out/bake/tiger.png'))"
--     lune run dev/legendary/check_probe.luau tiger.rgba
--
-- Skipped with a line saying so when no dump is given -- a check that silently
-- does nothing is worse than one that is absent.
local process = require("@lune/process")
local dump = process.args[1]
if not dump then
	print("no RGBA dump given -- sheetStats vs encode_probe.py NOT checked (see above)")
	return
end

local raw = fs.readFile(dump)
assert(#raw == 512 * 512 * 4, string.format("%s is %d bytes, wanted %d", dump, #raw, 512 * 512 * 4))

-- STATS_SRC's own bytes, not a copy of them. task.wait is the only thing in it
-- that Lune does not have as a global.
local stats = luau.load(blocks.STATS_SRC .. "\nreturn sheetStats", {
	environment = { task = { wait = function() end } },
})()

local s = stats(buffer.fromstring(raw))
local want = { inMap = 262104, markN = 117747, edgeN = 4230, ratio = 55.6723 }
print(string.format("sheetStats on %s:", dump))
print(string.format("  inMap %6d  want %6d  %s", s.inMap, want.inMap, s.inMap == want.inMap and "ok" or "MISMATCH"))
print(string.format("  markN %6d  want %6d  %s", s.markN, want.markN, s.markN == want.markN and "ok" or "MISMATCH"))
print(string.format("  edgeN %6d  want %6d  %s", s.edgeN, want.edgeN, s.edgeN == want.edgeN and "ok" or "MISMATCH"))
print(string.format("  2A/P  %.4f  want %.4f  %s", s.ratio, want.ratio,
	math.abs(s.ratio - want.ratio) < 5e-4 and "ok" or "MISMATCH"))
assert(s.inMap == want.inMap and s.markN == want.markN and s.edgeN == want.edgeN,
	"the Luau instrument and encode_probe.py disagree on the bake -- the probe's runtime "
		.. "assert would fire inside the playtest")
print("OK -- the instrument reproduces encode_probe.py's reference on the bake's own bytes")
