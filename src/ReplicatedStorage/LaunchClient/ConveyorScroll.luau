--!strict
-- Scrolls the conveyor belts' ridge textures so the surface LOOKS like it is
-- moving, matching the speed and direction it actually carries a player at.
-- Purely cosmetic: this touches nothing but Texture.OffsetStudsU, never a
-- part, a position, or a velocity.
--
-- ONE LOOP FOR BOTH HALVES, not one per part -- LaunchClient connects
-- ConveyorScroll.update to a single RenderStepped and this walks its own
-- (two-entry) list. Adding a third belt later costs nothing here.
--
-- THE SPEED IS NOT A SECOND COPY OF THE CONSTANT. It is read off the belt
-- part's OWN AssemblyLinearVelocity -- the exact vector the physics solver
-- uses to carry the player, set once by MapBuilder from
-- PathConfig.BELT_SPEED_STUDS_PER_SECOND. So the visual cannot drift from the
-- physics: there is no second number to keep in step, and retuning the belt's
-- speed (or reversing a half) moves the texture with it automatically, with
-- no edit in this file. That is also why the two halves come out opposed for
-- free -- their velocities already are.
--
-- READ ONCE AND CACHED, NOT EVERY FRAME (bug fix -- microstutter, see
-- REPORT.md). It used to be sampled every RenderStepped, on the reasoning
-- that a live read can never go stale. The reasoning was sound and the cost
-- was not: AssemblyLinearVelocity on an ANCHORED, server-replicated part is
-- a physics-state query, not a plain stored field, and there is no contract
-- that it returns a bit-identical value every frame on the client. A single
-- sample that came back low -- or momentarily zero -- turned into a short
-- frame for the texture and read as a jump. Sampling once removes the whole
-- class of problem, and is safe here because MapBuilder.server.luau:265 is
-- the ONLY writer of a belt's velocity and it writes once, at build. A map
-- rebuild re-discovers the belts and re-samples, so the cache cannot outlive
-- the thing it describes.
--
-- ZERO IS TREATED AS "NOT READY YET", not as a stopped belt: the part can
-- replicate to this client before its velocity property does, and caching a
-- premature 0 would freeze that half forever. So a zero sample is simply
-- retried next frame -- and a genuinely stopped belt has nothing to scroll
-- anyway, which is the same behaviour.
--
-- WHY CLIENT-SIDE. Offsetting a texture is a render-time detail with no
-- gameplay meaning; replicating it would be pure waste, and each client
-- scrolling its own copy at its own frame rate is exactly right. Nothing here
-- is authoritative and nothing reads it back.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PathConfig = require(ReplicatedStorage.Config.PathConfig)

local ConveyorScroll = {}

-- The folder MapBuilder parents the whole blockout to, and the Texture name
-- it gives each belt. Both are matched by NAME rather than by position -- the
-- belt's X/Z are derived from the lane pitch and have already moved twice,
-- and a scroller has no business caring where the thing it animates sits.
local MAP_FOLDER_NAME = "MapBlockout"
local RIDGE_TEXTURE_NAME = "BeltRidges"

type Belt = {
	part: BasePart,
	texture: Texture,
	-- Cached surface speed along X, 0 until successfully sampled -- see the
	-- header for why it is sampled once rather than per frame, and why 0
	-- means "retry" rather than "stopped".
	speed: number,
	-- OUR OWN accumulator, in Lua's float64, wrapped to one tile. The offset
	-- used to be accumulated by reading Texture.OffsetStudsU back and adding
	-- to it, which put a float32 round-trip in the loop every frame; keeping
	-- it here makes the property write-only and the accumulation exact. See
	-- REPORT.md -- this was defence rather than the diagnosed cause, but it
	-- costs one number and removes the question permanently.
	offset: number,
}

local belts: { Belt } = {}

-- Rescans on demand rather than caching once at require time: this module is
-- required by LaunchClient, which can finish loading before MapBuilder (a
-- server script) has finished building the map, and can also outlive a
-- rebuild. An empty list is a cheap no-op every frame, so retrying costs
-- nothing until the belts actually exist.
local function findBelts(): { Belt }
	local found: { Belt } = {}
	local mapFolder = Workspace:FindFirstChild(MAP_FOLDER_NAME)
	if not mapFolder then
		return found
	end
	for _, child in mapFolder:GetChildren() do
		if child:IsA("BasePart") then
			local texture = child:FindFirstChild(RIDGE_TEXTURE_NAME)
			if texture and texture:IsA("Texture") then
				table.insert(found, { part = child, texture = texture, speed = 0, offset = 0 })
			end
		end
	end
	return found
end

--- Advances every belt's ridge texture by one frame's worth of its own
--- surface velocity. Safe to call before the map exists, and safe to call
--- after a belt has been destroyed (the parent check drops stale entries).
function ConveyorScroll.update(deltaTime: number)
	if #belts == 0 then
		belts = findBelts()
		if #belts == 0 then
			return
		end
	end

	local tile = PathConfig.BELT_RIDGE_TILE_STUDS
	for _, belt in belts do
		if not belt.part.Parent then
			-- The map was rebuilt underneath us -- drop the whole list and
			-- let the next frame rediscover it, rather than half-updating a
			-- set of parts that no longer exists.
			belts = {}
			return
		end
		-- The SAME vector the solver carries a player with -- sign and
		-- magnitude both come from here, so a reversed or retuned belt needs
		-- no change in this file. Sampled ONCE per belt, not per frame; see
		-- the header for why, and why 0 means "not replicated yet, retry"
		-- rather than "stopped".
		if belt.speed == 0 then
			belt.speed = belt.part.AssemblyLinearVelocity.X
			if belt.speed == 0 then
				continue
			end
		end
		-- Accumulated HERE, in float64, and wrapped to one tile -- the
		-- texture repeats every `tile` studs, so the wrap is invisible and
		-- the running value stays small and exact forever. The property is
		-- written, never read back.
		local increment = belt.speed * deltaTime * PathConfig.BELT_RIDGE_SCROLL_SIGN
		belt.offset = (belt.offset + increment) % tile
		belt.texture.OffsetStudsU = belt.offset
	end
end

return ConveyorScroll
