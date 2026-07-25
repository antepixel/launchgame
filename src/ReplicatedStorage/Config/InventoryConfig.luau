--!strict
-- Every inventory constant lives here, and ONLY here -- same rule as every
-- other Config module in this project.

export type InventoryConfig = {
	SELL_VALUE_INCOME_MULTIPLIER: number,
}

local InventoryConfig: InventoryConfig = {
	-- Selling a slime pays this many SECONDS' worth of its own income -- 60
	-- = "a minute of what it would have earned," per the written report.
	-- Read by PlayerProfile.sellFromInventory: sell value = incomePerSecond
	-- * this * quantity. Tune the whole sell-vs-keep tradeoff for the
	-- entire economy by changing this ONE number.
	SELL_VALUE_INCOME_MULTIPLIER = 60,
}

return InventoryConfig
