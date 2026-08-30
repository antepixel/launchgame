--!strict
-- Generates the full 65-slime catalog from SlimeConfig's tier definitions --
-- GENERATED, not hand-authored (same philosophy as LuckCurve.luau/
-- RunwayBuilder.server.luau: a repeated, formulaic list is a loop's job, not
-- 65 hand-typed table entries). THE NAMES ARE NO LONGER GENERATED -- they
-- are authored, one per slime, in SlimeConfig.SLIME_NAME_BY_TIER, because a
-- formula cannot write the names for a collection game and "Secret Slime 9"
-- is not a name. Colours are still placeholders.
--
-- Every slime has TWO colours (see the written report): `color` is its OWN
-- per-slime colour, the MEASURED per-slime
-- value at the same position in SlimeConfig.SLIME_COLOR_BY_TIER -- distinct
-- within a tier, same shape/indexing as income below; `tierColor` is the
-- colour shared by every slime in that tier (SlimeConfig.SLIME_TIER_COLORS),
-- kept as its own field for the sites that need tier identity, not
-- individual identity (the reveal panel, inventory rows). Income is the
-- MEASURED per-slime value at the same position in SlimeConfig.
-- SLIME_INCOME_BY_TIER -- real, distinct numbers now, not one flat value
-- shared by a whole tier.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SlimeConfig = require(ReplicatedStorage.Config.SlimeConfig)

export type Slime = {
	globalIndex: number,
	name: string,
	tier: number,
	tierName: string,
	color: Color3,
	tierColor: Color3,
	incomePerSecond: number,
	-- The painted sheet bound to this slime's body, or nil for the plain
	-- coloured body every slime had before skins existed. nil rather than ""
	-- so that "has a skin" is a presence test at every call site instead of an
	-- emptiness test that reads as a bug the first time someone sees it.
	skinTextureId: string?,
}

local SlimeData = {}

-- Flat, ordered list -- ALL 65 slimes, Common's 6 first through Divine's 8
-- last -- indexed by globalIndex (1-based). This index is the ONLY slime
-- identifier ever sent over the wire (see LaunchServer's onBoxPress): the
-- client looks up name/tier/colour/income from THIS SAME shared table, not
-- from anything the server sends alongside it.
local slimes: { Slime } = {}
-- One list per tier -- what SlimeRoll.pickSlimeInTier picks from once a tier
-- is already chosen (see SlimeRoll.luau). ASCENDING INCOME ORDER, which is
-- load-bearing now that the pick is not always flat: entry i of this list is
-- entry i of SLIME_INCOME_BY_TIER and gets weight ratio^-(i-1) from
-- SLIME_TIER_WEIGHT_RATIO, so a tier whose incomes were written out of order
-- would silently weight the wrong slimes. Uniform tiers (every tier but
-- Divine today) still take a flat pick over this same list.
local slimesByTier: { { Slime } } = {}

-- Checked once, outside the per-tier loop below, because a per-tier check
-- cannot see a table that is too LONG: an entry at index 9 of an 8-tier ladder
-- would never be read and never be noticed. Same failure class as the
-- per-tier asserts, different shape.
assert(
	#SlimeConfig.SLIME_TIER_WEIGHT_RATIO == #SlimeConfig.SLIME_TIER_NAMES,
	string.format("SlimeConfig.SLIME_TIER_WEIGHT_RATIO has %d entries, expected %d to match SLIME_TIER_NAMES", #SlimeConfig.SLIME_TIER_WEIGHT_RATIO, #SlimeConfig.SLIME_TIER_NAMES)
)

-- SLIME_SKIN_BY_TIER is SPARSE, so the length assert every other table gets
-- cannot be applied to it -- and a sparse table's failure mode is exactly the
-- one a length check would have caught elsewhere: an entry nothing ever reads.
-- A skin written at [5][7] of a six-slime tier, or at tier [9] of an eight-tier
-- ladder, is silently dropped -- the slime it was meant for just renders plain,
-- which looks like "the upload did not work" and sends someone off checking the
-- asset. So every key is validated against SLIME_TIER_COUNTS here, at load,
-- BEFORE the catalog is built. Same reasoning as the WEIGHT_RATIO assert above:
-- the table this loop does not otherwise read is the one that fails quietly.
for tierKey, row in pairs(SlimeConfig.SLIME_SKIN_BY_TIER) do
	assert(
		typeof(tierKey) == "number" and SlimeConfig.SLIME_TIER_NAMES[tierKey] ~= nil,
		string.format("SlimeConfig.SLIME_SKIN_BY_TIER has key %s, which is not a tier index 1..%d", tostring(tierKey), #SlimeConfig.SLIME_TIER_NAMES)
	)
	local count = SlimeConfig.SLIME_TIER_COUNTS[tierKey]
	for slot, id in pairs(row) do
		assert(
			typeof(slot) == "number" and slot >= 1 and slot <= count,
			string.format("SlimeConfig.SLIME_SKIN_BY_TIER[%d] (%s) has index %s, outside 1..%d for that tier", tierKey, SlimeConfig.SLIME_TIER_NAMES[tierKey], tostring(slot), count)
		)
		-- A malformed id does NOT throw when written to TextureID -- it binds,
		-- resolves to nothing, and the slime renders untextured. That is
		-- indistinguishable from "no skin configured" at a glance, which is why
		-- the shape is checked here rather than discovered in a frame.
		assert(
			typeof(id) == "string" and string.match(id, "^rbxassetid://%d+$") ~= nil,
			string.format("SlimeConfig.SLIME_SKIN_BY_TIER[%d][%d] is %q, expected a well-formed \"rbxassetid://<number>\"", tierKey, slot, tostring(id))
		)
	end
end

for tier = 1, #SlimeConfig.SLIME_TIER_NAMES do
	local tierName = SlimeConfig.SLIME_TIER_NAMES[tier]
	local count = SlimeConfig.SLIME_TIER_COUNTS[tier]
	local tierColor = SlimeConfig.SLIME_TIER_COLORS[tier]
	local colors = SlimeConfig.SLIME_COLOR_BY_TIER[tier]
	local incomes = SlimeConfig.SLIME_INCOME_BY_TIER[tier]
	local names = SlimeConfig.SLIME_NAME_BY_TIER[tier]

	-- Fail loudly, at load time, rather than silently indexing past the end
	-- (nil income/colour) or dropping measured values a tier doesn't have
	-- room for -- a tier's slime count and its income/colour lists are
	-- separately-authored places in SlimeConfig that must agree, and this is
	-- the one spot all of them are read together.
	assert(
		#incomes == count,
		string.format("SlimeConfig.SLIME_INCOME_BY_TIER[%d] (%s) has %d entries, expected %d to match SLIME_TIER_COUNTS[%d]", tier, tierName, #incomes, count, tier)
	)
	assert(
		#colors == count,
		string.format("SlimeConfig.SLIME_COLOR_BY_TIER[%d] (%s) has %d entries, expected %d to match SLIME_TIER_COUNTS[%d]", tier, tierName, #colors, count, tier)
	)
	assert(
		#names == count,
		string.format("SlimeConfig.SLIME_NAME_BY_TIER[%d] (%s) has %d entries, expected %d to match SLIME_TIER_COUNTS[%d]", tier, tierName, #names, count, tier)
	)
	-- SLIME_TIER_WEIGHT_RATIO is checked here too, for the same reason and in
	-- the same place, even though this generator does not read it: it is the
	-- one loop that already walks every tier with SlimeConfig open, and a
	-- missing or malformed entry there fails SILENTLY rather than loudly.
	-- SlimeRoll.pickSlimeInTier's `typeof(ratio) ~= "number"` fallback treats a
	-- nil entry as uniform, which is a perfectly reasonable runtime default and
	-- a terrible way to find out the table is short -- a silently-uniform
	-- Divine is exactly the bug the analysis layer shipped one pass ago and
	-- only caught by cross-checking two integrators. The fallback stays; this
	-- is what makes sure it never has to fire.
	--
	-- >= 1.0 because the semantics only run one way: the ratio makes each step
	-- UP a tier's income ladder rarer than the step below it (weight_i =
	-- ratio ^ -(i - 1)). A value below 1 would silently invert that and make
	-- the best slime in a tier the most common one.
	local ratio = SlimeConfig.SLIME_TIER_WEIGHT_RATIO[tier]
	assert(
		typeof(ratio) == "number" and ratio >= 1.0,
		string.format("SlimeConfig.SLIME_TIER_WEIGHT_RATIO[%d] (%s) is %s, expected a number >= 1.0", tier, tierName, tostring(ratio))
	)

	local skins = SlimeConfig.SLIME_SKIN_BY_TIER[tier]

	slimesByTier[tier] = {}
	for i = 1, count do
		local slime: Slime = {
			globalIndex = #slimes + 1,
			name = names[i],
			tier = tier,
			tierName = tierName,
			color = colors[i],
			tierColor = tierColor,
			incomePerSecond = incomes[i],
			skinTextureId = skins and skins[i] or nil,
		}
		table.insert(slimes, slime)
		table.insert(slimesByTier[tier], slime)
	end
end

SlimeData.SLIMES = slimes
SlimeData.SLIMES_BY_TIER = slimesByTier

return SlimeData
