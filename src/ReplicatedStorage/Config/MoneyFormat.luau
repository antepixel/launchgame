--!strict
-- Shared large-number formatting for money -- used by BaseClient.client.luau
-- (the money HUD) and ShopClient.client.luau (tier prices), which must
-- agree EXACTLY on how a given amount reads: the HUD showing whether you can
-- afford something and the shop showing what it costs are two views of the
-- SAME number, so this is the one place that formatting logic lives, rather
-- than two copies that could quietly drift out of sync. That risk is real
-- here specifically because shop prices run all the way up past a
-- QUINTILLION (see ShopConfig.SWING_TIER_PRICES's tier 10/11) -- far beyond
-- what a short K/M/B-only formatter (like LuckCurve.formatLuck, which never
-- needs to exceed 120,000, or PlayerProfile's own per-slime income
-- formatter, which never exceeds a few thousand) has any reason to handle,
-- so it isn't duplicated as a fourth local copy the way those smaller ones
-- are -- see each of THEIR own comments for why staying local is fine at
-- their scale.
local MoneyFormat = {}

-- Short-scale suffixes, checked high to low -- matches LuckCurve.formatLuck's
-- own style (one decimal, trimmed ".0") for everything under 1000, extended
-- to comfortably cover tier 11's price (2.5e20, i.e. "$250Qi").
local TIERS = {
	{ scale = 1e18, suffix = "Qi" }, -- Quintillion
	{ scale = 1e15, suffix = "Qa" }, -- Quadrillion
	{ scale = 1e12, suffix = "T" }, -- Trillion
	{ scale = 1e9, suffix = "B" }, -- Billion
	{ scale = 1e6, suffix = "M" }, -- Million
	{ scale = 1e3, suffix = "K" }, -- Thousand
}

function MoneyFormat.format(value: number): string
	local magnitude = math.abs(value)
	for _, tier in TIERS do
		if magnitude >= tier.scale then
			local formatted = string.format("%.1f", value / tier.scale)
			formatted = formatted:gsub("%.0$", "")
			return "$" .. formatted .. tier.suffix
		end
	end
	return string.format("$%d", value)
end

return MoneyFormat
