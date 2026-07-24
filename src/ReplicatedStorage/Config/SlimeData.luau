--!strict
-- Generates the full 65-slime catalog from SlimeConfig's tier definitions --
-- GENERATED, not hand-authored (same philosophy as LuckCurve.luau/
-- RunwayBuilder.server.luau: a repeated, formulaic list is a loop's job, not
-- 65 hand-typed table entries). Placeholder names/colours only -- swapped
-- for real assets later. Every slime's colour is simply its tier's colour
-- (see SlimeConfig.SLIME_TIER_COLORS), and its income is its tier's flat
-- base income (see SlimeConfig.SLIME_TIER_BASE_INCOME) -- no per-slime
-- variance within a tier in this pass.
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
	local income = SlimeConfig.SLIME_TIER_BASE_INCOME[tier]

	slimesByTier[tier] = {}
	for i = 1, count do
		local slime: Slime = {
			globalIndex = #slimes + 1,
			name = string.format("%s Slime %d", tierName, i),
			tier = tier,
			tierName = tierName,
			color = color,
			incomePerSecond = income,
		}
		table.insert(slimes, slime)
		table.insert(slimesByTier[tier], slime)
	end
end

SlimeData.SLIMES = slimes
SlimeData.SLIMES_BY_TIER = slimesByTier

return SlimeData
