--!strict
-- Generates the full 65-slime catalog from SlimeConfig's tier definitions --
-- GENERATED, not hand-authored (same philosophy as LuckCurve.luau/
-- RunwayBuilder.server.luau: a repeated, formulaic list is a loop's job, not
-- 65 hand-typed table entries). Placeholder names/colours only -- swapped
-- for real assets later. Every slime's colour is simply its tier's colour
-- (see SlimeConfig.SLIME_TIER_COLORS); its income is the MEASURED per-slime
-- value at the same position in SlimeConfig.SLIME_INCOME_BY_TIER -- real,
-- distinct numbers now, not one flat value shared by a whole tier.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SlimeConfig = require(ReplicatedStorage.Config.SlimeConfig)

export type Slime = {
	globalIndex: number,
	name: string,
	tier: number,
	tierName: string,
	color: Color3,
	incomePerSecond: number,
}

local SlimeData = {}

-- Flat, ordered list -- ALL 65 slimes, Common's 6 first through Divine's 8
-- last -- indexed by globalIndex (1-based). This index is the ONLY slime
-- identifier ever sent over the wire (see LaunchServer's onBoxPress): the
-- client looks up name/tier/colour/income from THIS SAME shared table, not
-- from anything the server sends alongside it.
local slimes: { Slime } = {}
-- One list per tier -- what SlimeRoll indexes into once it's already chosen
-- a tier (see SlimeRoll.luau): "every slime within a tier is equally likely"
-- is just "pick a uniformly random index into this list."
local slimesByTier: { { Slime } } = {}

for tier = 1, #SlimeConfig.SLIME_TIER_NAMES do
	local tierName = SlimeConfig.SLIME_TIER_NAMES[tier]
	local count = SlimeConfig.SLIME_TIER_COUNTS[tier]
	local color = SlimeConfig.SLIME_TIER_COLORS[tier]
	local incomes = SlimeConfig.SLIME_INCOME_BY_TIER[tier]

	-- Fail loudly, at load time, rather than silently indexing past the end
	-- (nil income) or dropping measured values a tier doesn't have room
	-- for -- a tier's slime count and its income list are two separately-
	-- authored places in SlimeConfig that must agree, and this is the one
	-- spot both are read together.
	assert(
		#incomes == count,
		string.format("SlimeConfig.SLIME_INCOME_BY_TIER[%d] (%s) has %d entries, expected %d to match SLIME_TIER_COUNTS[%d]", tier, tierName, #incomes, count, tier)
	)

	slimesByTier[tier] = {}
	for i = 1, count do
		local slime: Slime = {
			globalIndex = #slimes + 1,
			name = string.format("%s Slime %d", tierName, i),
			tier = tier,
			tierName = tierName,
			color = color,
			incomePerSecond = incomes[i],
		}
		table.insert(slimes, slime)
		table.insert(slimesByTier[tier], slime)
	end
end

SlimeData.SLIMES = slimes
SlimeData.SLIMES_BY_TIER = slimesByTier

return SlimeData
