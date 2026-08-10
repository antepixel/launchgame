--!strict
-- Generates the full 65-slime catalog from SlimeConfig's tier definitions --
-- GENERATED, not hand-authored (same philosophy as LuckCurve.luau/
-- RunwayBuilder.server.luau: a repeated, formulaic list is a loop's job, not
-- 65 hand-typed table entries). Placeholder names/colours only -- swapped
-- for real assets later. Every slime has TWO colours now (see the written
-- report): `color` is its OWN per-slime colour, the MEASURED per-slime
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

for tier = 1, #SlimeConfig.SLIME_TIER_NAMES do
	local tierName = SlimeConfig.SLIME_TIER_NAMES[tier]
	local count = SlimeConfig.SLIME_TIER_COUNTS[tier]
	local tierColor = SlimeConfig.SLIME_TIER_COLORS[tier]
	local colors = SlimeConfig.SLIME_COLOR_BY_TIER[tier]
	local incomes = SlimeConfig.SLIME_INCOME_BY_TIER[tier]

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

	slimesByTier[tier] = {}
	for i = 1, count do
		local slime: Slime = {
			globalIndex = #slimes + 1,
			name = string.format("%s Slime %d", tierName, i),
			tier = tier,
			tierName = tierName,
			color = colors[i],
			tierColor = tierColor,
			incomePerSecond = incomes[i],
		}
		table.insert(slimes, slime)
		table.insert(slimesByTier[tier], slime)
	end
end

SlimeData.SLIMES = slimes
SlimeData.SLIMES_BY_TIER = slimesByTier

return SlimeData
