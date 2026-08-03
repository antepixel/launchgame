-- Minimal-but-faithful Roblox API shim so the project's real .luau source
-- files can run UNMODIFIED under Lune (see rokit.toml) and produce REAL
-- Instance/Model geometry -- actual per-part CFrame/Size, actual world-axis
-- AABB math -- instead of a hand-derived formula that could silently drift
-- from what Studio actually builds.
--
-- WHY THIS EXISTS: iterating on swing geometry (tier scaling, footprint
-- clamps, camera framing) by editing a .luau file, opening Studio, pressing
-- Play, and reading the output console is slow. This shim implements just
-- enough of the Roblox API -- Vector3, CFrame, Color3, UDim2, Enum,
-- Instance (Parent/CFrame/Size/GetDescendants/IsA/etc.), and a tiny fake
-- `game:GetService()` -- to load and run the REAL gameplay/config modules
-- (see registerModule calls near the bottom) plus dev-only scripts like
-- gallery/SwingGallery.server.luau, entirely on the command line.
--
-- HOW TO RUN: from the repo root,
--   lune run dev/run_gallery.luau
-- prints the same measurement/diagnostic/camera output the gallery script
-- prints in Studio. Any edit to gallery/SwingGallery.server.luau or the
-- modules it requires is picked up immediately (this shim reads them fresh
-- off disk every run, relative to the current working directory -- run it
-- from the repo root, not from inside dev/).
--
-- KEEP THIS FAITHFUL, NOT CONVENIENT: every primitive here (rotateLocal,
-- the CFrame*Vector3 point transform, GetDescendants/IsA) is implemented
-- to match documented Roblox behaviour exactly, specifically so this shim
-- and real Studio can never legitimately disagree about geometry -- see
-- the written report on the swing-lane measurement bug this shim was built
-- to chase down (Studio's Model:GetBoundingBox()/GetExtentsSize() silently
-- permute W/H/D per tier when no PrimaryPart is set; this shim is why that
-- was diagnosable without a Studio round-trip for every guess).

local fs = require("@lune/fs")

--============================= Vector3 =============================--
local Vector3 = {}
local Vector3Mt = {}

local function v3(x, y, z)
	return setmetatable({ X = x, Y = y, Z = z }, Vector3Mt)
end

Vector3.new = v3

Vector3Mt.__index = function(t, k)
	if k == "Magnitude" then
		return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
	elseif k == "Unit" then
		local m = math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
		if m < 1e-12 then
			return v3(0, 0, 0)
		end
		return v3(t.X / m, t.Y / m, t.Z / m)
	elseif k == "Cross" then
		return function(self, other)
			return v3(
				self.Y * other.Z - self.Z * other.Y,
				self.Z * other.X - self.X * other.Z,
				self.X * other.Y - self.Y * other.X
			)
		end
	elseif k == "Dot" then
		return function(self, other)
			return self.X * other.X + self.Y * other.Y + self.Z * other.Z
		end
	elseif k == "Lerp" then
		return function(self, other, alpha)
			return v3(
				self.X + (other.X - self.X) * alpha,
				self.Y + (other.Y - self.Y) * alpha,
				self.Z + (other.Z - self.Z) * alpha
			)
		end
	end
	return nil
end

Vector3Mt.__add = function(a, b)
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
Vector3Mt.__sub = function(a, b)
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
Vector3Mt.__mul = function(a, b)
	if type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	elseif type(a) == "number" then
		return v3(a * b.X, a * b.Y, a * b.Z)
	end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
Vector3Mt.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
Vector3Mt.__div = function(a, b)
	return v3(a.X / b, a.Y / b, a.Z / b)
end

Vector3.new = v3

--============================= Color3 / UDim2 =============================--
local UDim2 = {}
UDim2.new = function(xs, xo, ys, yo)
	return { xs = xs, xo = xo, ys = ys, yo = yo }
end
UDim2.fromScale = function(xs, ys)
	return { xs = xs, xo = 0, ys = ys, yo = 0 }
end

local Color3 = {}
local Color3Mt = {}
Color3Mt.__index = function(t, k)
	if k == "Lerp" then
		return function(self, other, alpha)
			return setmetatable({
				r = self.r + (other.r - self.r) * alpha,
				g = self.g + (other.g - self.g) * alpha,
				b = self.b + (other.b - self.b) * alpha,
			}, Color3Mt)
		end
	end
	return nil
end
Color3.new = function(r, g, b)
	return setmetatable({ r = r, g = g, b = b }, Color3Mt)
end
Color3.fromRGB = function(r, g, b)
	return setmetatable({ r = r / 255, g = g / 255, b = b / 255 }, Color3Mt)
end

--============================= CFrame =============================--
-- Represented as { p = Vector3, rx = Vector3, ry = Vector3, rz = Vector3 }
-- where rx/ry/rz are the world-space images of the local +X/+Y/+Z axes
-- (i.e. columns of the 3x3 rotation matrix). Identity: rx=(1,0,0),
-- ry=(0,1,0), rz=(0,0,1).
local CFrame = {}
local CFrameMt = {}

local function rotateLocal(rot, lx, ly, lz)
	return v3(
		rot.rx.X * lx + rot.ry.X * ly + rot.rz.X * lz,
		rot.rx.Y * lx + rot.ry.Y * ly + rot.rz.Y * lz,
		rot.rx.Z * lx + rot.ry.Z * ly + rot.rz.Z * lz
	)
end

local function mkcf(p, rx, ry, rz)
	return setmetatable({ p = p, rx = rx, ry = ry, rz = rz }, CFrameMt)
end

CFrame.new = function(a, b, c)
	if b == nil then
		-- CFrame.new(vector3)
		return mkcf(a, v3(1, 0, 0), v3(0, 1, 0), v3(0, 0, 1))
	end
	return mkcf(v3(a, b, c), v3(1, 0, 0), v3(0, 1, 0), v3(0, 0, 1))
end

-- Roblox: if the Z column is omitted, it's the cross product of X and Y.
CFrame.fromMatrix = function(pos, vx, vy, vz)
	if vz == nil then
		vz = vx:Cross(vy)
	end
	return mkcf(pos, vx, vy, vz)
end

CFrame.Angles = function(rx, ry, rz)
	-- Only ever called with a single nonzero axis in this codebase
	-- (Y-axis chain-link twist). Implemented as the standard combined
	-- intrinsic X*Y*Z rotation matrix so any single-axis call is exact.
	local cx, sx = math.cos(rx), math.sin(rx)
	local cy, sy = math.cos(ry), math.sin(ry)
	local cz, sz = math.cos(rz), math.sin(rz)
	-- Columns = R * localAxis, R = Rz * Ry * Rx
	local function mul(mx, my, mz)
		-- apply Rx then Ry then Rz to a local vector (mx,my,mz)
		local x1, y1, z1 = mx, my * cx - mz * sx, my * sx + mz * cx
		local x2, y2, z2 = x1 * cy + z1 * sy, y1, -x1 * sy + z1 * cy
		local x3, y3, z3 = x2 * cz - y2 * sz, x2 * sz + y2 * cz, z2
		return v3(x3, y3, z3)
	end
	return mkcf(v3(0, 0, 0), mul(1, 0, 0), mul(0, 1, 0), mul(0, 0, 1))
end

CFrameMt.__index = function(t, k)
	if k == "Position" then
		return t.p
	elseif k == "XVector" then
		return t.rx
	elseif k == "YVector" then
		return t.ry
	elseif k == "ZVector" then
		return t.rz
	end
	return nil
end

CFrameMt.__mul = function(a, b)
	if getmetatable(b) == Vector3Mt then
		return a.p + rotateLocal(a, b.X, b.Y, b.Z)
	end
	local newP = a.p + rotateLocal(a, b.p.X, b.p.Y, b.p.Z)
	local newRx = rotateLocal(a, b.rx.X, b.rx.Y, b.rx.Z)
	local newRy = rotateLocal(a, b.ry.X, b.ry.Y, b.ry.Z)
	local newRz = rotateLocal(a, b.rz.X, b.rz.Y, b.rz.Z)
	return mkcf(newP, newRx, newRy, newRz)
end

CFrame.lookAt = function(pos, target)
	-- Not geometrically load-bearing for bounding-box purposes (only used
	-- for the gallery's cosmetic camera markers); identity rotation is fine.
	return mkcf(pos, v3(1, 0, 0), v3(0, 1, 0), v3(0, 0, 1))
end

--============================= Enum (auto-vivifying) =============================--
local function makeEnumLeaf(path)
	return setmetatable({ __enumPath = path }, {
		__tostring = function(self)
			return self.__enumPath
		end,
	})
end

local function makeEnumCategory(catName)
	return setmetatable({}, {
		__index = function(t, k)
			local leaf = makeEnumLeaf(catName .. "." .. k)
			rawset(t, k, leaf)
			return leaf
		end,
	})
end

local Enum = setmetatable({}, {
	__index = function(t, k)
		local cat = makeEnumCategory(k)
		rawset(t, k, cat)
		return cat
	end,
})

--============================= Instance =============================--
local InstanceMt = {}

local function isPartClass(className)
	return className == "Part"
end

local function collectDescendantParts(inst, out)
	for _, child in ipairs(inst._children) do
		if isPartClass(child.ClassName) then
			table.insert(out, child)
		end
		collectDescendantParts(child, out)
	end
end

local function extentsSizeAndBounds(inst)
	local parts = {}
	collectDescendantParts(inst, parts)
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	for _, part in ipairs(parts) do
		local size = part.Size
		local cf = part.CFrame
		local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
		for _, sx in ipairs({ -hx, hx }) do
			for _, sy in ipairs({ -hy, hy }) do
				for _, sz in ipairs({ -hz, hz }) do
					local w = cf.p + rotateLocal(cf, sx, sy, sz)
					if w.X < minX then minX = w.X end
					if w.X > maxX then maxX = w.X end
					if w.Y < minY then minY = w.Y end
					if w.Y > maxY then maxY = w.Y end
					if w.Z < minZ then minZ = w.Z end
					if w.Z > maxZ then maxZ = w.Z end
				end
			end
		end
	end
	if #parts == 0 then
		return v3(0, 0, 0), 0, 0, 0, 0, 0, 0
	end
	return v3(maxX - minX, maxY - minY, maxZ - minZ), minX, maxX, minY, maxY, minZ, maxZ
end

local function newInstance(className)
	local inst
	inst = setmetatable({
		ClassName = className,
		Name = className,
		_children = {},
		_parent = nil,
		_attrs = {},
		Anchored = false,
		CanCollide = false,
		Transparency = 0,
		Shape = nil,
		Material = nil,
		Color = nil,
		Size = v3(0, 0, 0),
		_cframe = CFrame.new(0, 0, 0),
		PrimaryPart = nil,
	}, InstanceMt)
	return inst
end

InstanceMt.__index = function(t, k)
	if k == "Position" then
		return rawget(t, "_cframe").p
	elseif k == "CFrame" then
		return rawget(t, "_cframe")
	elseif k == "Parent" then
		return rawget(t, "_parent")
	elseif k == "ClearAllChildren" then
		return function(self)
			for _, child in ipairs(self._children) do
				child._parent = nil
			end
			self._children = {}
		end
	elseif k == "GetExtentsSize" then
		return function(self)
			local size = extentsSizeAndBounds(self)
			return size
		end
	elseif k == "GetBoundingBox" then
		return function(self)
			local size, minX, maxX, minY, maxY, minZ, maxZ = extentsSizeAndBounds(self)
			local center = v3((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2)
			return CFrame.new(center), size
		end
	elseif k == "SetAttribute" then
		return function(self, name, value)
			self._attrs[name] = value
		end
	elseif k == "GetAttribute" then
		return function(self, name)
			return self._attrs[name]
		end
	elseif k == "WaitForChild" or k == "FindFirstChild" then
		return function(self, name)
			for _, child in ipairs(self._children) do
				if child.Name == name then
					return child
				end
			end
			return nil
		end
	elseif k == "GetChildren" then
		return function(self)
			local out = {}
			for _, child in ipairs(self._children) do
				table.insert(out, child)
			end
			return out
		end
	elseif k == "GetDescendants" then
		return function(self)
			local out = {}
			local function collect(node)
				for _, child in ipairs(node._children) do
					table.insert(out, child)
					collect(child)
				end
			end
			collect(self)
			return out
		end
	elseif k == "IsA" then
		return function(self, className)
			if className == self.ClassName then
				return true
			elseif className == "BasePart" then
				return self.ClassName == "Part"
			elseif className == "PVInstance" then
				return self.ClassName == "Part" or self.ClassName == "Model"
			end
			return false
		end
	end
	-- Roblox dot-indexing shorthand for FindFirstChild by name.
	for _, child in ipairs(rawget(t, "_children")) do
		if child.Name == k then
			return child
		end
	end
	return nil
end

InstanceMt.__newindex = function(t, k, v)
	if k == "Position" then
		local old = rawget(t, "_cframe")
		rawset(t, "_cframe", CFrame.new(v))
		return
	elseif k == "CFrame" then
		rawset(t, "_cframe", v)
		return
	elseif k == "Parent" then
		local old = rawget(t, "_parent")
		if old ~= nil then
			for i, c in ipairs(old._children) do
				if c == t then
					table.remove(old._children, i)
					break
				end
			end
		end
		rawset(t, "_parent", v)
		if v ~= nil then
			table.insert(v._children, t)
		end
		return
	end
	rawset(t, k, v)
end

local Instance = {
	new = function(className)
		return newInstance(className)
	end,
}

--============================= game / services =============================--
local baseplate = newInstance("Part")
baseplate.Anchored = true
baseplate.Position = v3(200, -2, 0)
baseplate.Size = v3(500, 4, 120)

local Workspace = newInstance("Folder")
Workspace.Name = "Workspace"
baseplate.Parent = Workspace
baseplate.Name = "Baseplate"

local ServerScriptService = newInstance("Folder")
ServerScriptService.Name = "ServerScriptService"

local ConfigFolder = newInstance("Folder")
ConfigFolder.Name = "Config"
local ReplicatedStorage = newInstance("Folder")
ReplicatedStorage.Name = "ReplicatedStorage"
ConfigFolder.Parent = ReplicatedStorage

local services = {
	Workspace = Workspace,
	ServerScriptService = ServerScriptService,
	ReplicatedStorage = ReplicatedStorage,
}

local game = {
	GetService = function(self, name)
		return services[name]
	end,
}

--============================= module loader =============================--
-- Paths are relative to the CURRENT WORKING DIRECTORY, not to this file --
-- run `lune run dev/run_gallery.luau` from the repo root (see the header
-- comment above). No hardcoded machine-specific path.
local moduleCache = {}

local function loadLuauModule(relPath)
	if moduleCache[relPath] then
		return moduleCache[relPath].value
	end
	local source = fs.readFile(relPath)
	local env = setmetatable({
		game = game,
		Instance = Instance,
		Vector3 = Vector3,
		CFrame = CFrame,
		Color3 = Color3,
		Enum = Enum,
		UDim2 = UDim2,
		ColorSequence = { new = function(c) return { c } end },
		math = math,
		string = string,
		table = table,
		ipairs = ipairs,
		pairs = pairs,
		tostring = tostring,
		tonumber = tonumber,
		type = type,
		typeof = function(v)
			if getmetatable(v) == Vector3Mt then
				return "Vector3"
			elseif getmetatable(v) == CFrameMt then
				return "CFrame"
			elseif getmetatable(v) == InstanceMt then
				return "Instance"
			end
			return type(v)
		end,
		select = select,
		print = print,
		error = error,
		assert = assert,
		require = function(handle)
			return requireHandle(handle)
		end,
		unpack = unpack or table.unpack,
	}, { __index = _G })
	local chunk, err = loadstring(source, "@" .. relPath)
	if chunk then
		setfenv(chunk, env)
	end
	if not chunk then
		error("failed to parse " .. relPath .. ": " .. tostring(err))
	end
	local ok, result = pcall(chunk)
	if not ok then
		error("failed to run " .. relPath .. ": " .. tostring(result))
	end
	moduleCache[relPath] = { value = result }
	return result
end

-- Map "handle" instances (folder children created below) to source paths.
local handleToPath = {}

function requireHandle(handle)
	local path = handleToPath[handle]
	if not path then
		error("no module registered for this require() target")
	end
	return loadLuauModule(path)
end

local function registerModule(parentFolder, name, relPath)
	local handle = newInstance("ModuleScript")
	handle.Name = name
	handle.Parent = parentFolder
	handleToPath[handle] = relPath
	return handle
end

registerModule(ConfigFolder, "LaunchConfig", "src/ReplicatedStorage/Config/LaunchConfig.luau")
registerModule(ConfigFolder, "SwingTierVisuals", "src/ReplicatedStorage/Config/SwingTierVisuals.luau")
registerModule(ConfigFolder, "SwingGeometry", "src/ReplicatedStorage/Config/SwingGeometry.luau")
registerModule(ConfigFolder, "BaseConfig", "src/ReplicatedStorage/Config/BaseConfig.luau")
registerModule(ConfigFolder, "BaseGeometry", "src/ReplicatedStorage/Config/BaseGeometry.luau")
registerModule(ServerScriptService, "SwingBuilder", "src/ServerScriptService/SwingBuilder.luau")

return {
	loadLuauModule = loadLuauModule,
	Instance = Instance,
	Vector3 = Vector3,
	CFrame = CFrame,
	Color3 = Color3,
	Enum = Enum,
	game = game,
	Workspace = Workspace,
	ServerScriptService = ServerScriptService,
	ReplicatedStorage = ReplicatedStorage,
	-- Exposed so an ad-hoc driver script can register additional modules
	-- (e.g. for a one-off diagnostic) without editing this file.
	registerModule = registerModule,
}
