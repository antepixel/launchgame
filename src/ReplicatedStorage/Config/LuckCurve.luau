--!strict
-- Generates the full band-luck sequence -- GENERATED, not hand-authored (see
-- the written report). NUM_DECADES repeating "decades," each one order of
-- magnitude above the last. Each decade is internally 20 equal steps up to
-- that decade's ceiling (step = ceiling / 20); values already produced by the
-- PREVIOUS decade's finer-grained grid are dropped from this one, so the
-- merged sequence never repeats a number and gets progressively coarser as it
-- climbs:
--   decade 1, ceiling 100:     5, 10, 15 ... 100        (20 values, nothing to trim -- first decade)
--   decade 2, ceiling 1000:    150, 200 ... 1000         (of 20 steps, the first two -- 50, 100 -- already exist in decade 1)
--   decade 3, ceiling 10000:   1500, 2000 ... 10000      (first two -- 500, 1000 -- already exist in decade 2)
--   decade 4, ceiling 100000:  15000, 20000 ... 100000   (first two -- 5000, 10000 -- already exist in decade 3)
-- Raising NUM_DECADES is the only change needed to extend the curve further
-- (5 decades reaches a million) -- everything below is a loop over decade
-- bases, not a literal list.
local LuckCurve = {}

local NUM_DECADES = 4
local STEPS_PER_DECADE = 20

local values: { number } = {}
local previousCeiling = 0
for decade = 1, NUM_DECADES do
	local ceiling = 100 * 10 ^ (decade - 1)
	local step = ceiling / STEPS_PER_DECADE
	for i = 1, STEPS_PER_DECADE do
		local value = step * i
		if value > previousCeiling then
			table.insert(values, value)
		end
	end
	previousCeiling = ceiling
end

-- THE single source of truth for the road: band i's luck is VALUES[i + 1]
-- (Lua/Luau arrays are 1-indexed), and the band count is #VALUES -- not a
-- separately authored constant anywhere. RunwayBuilder (placing the physical
-- bands) and LaunchServer (scoring a landing against them) both read this
-- exact table, so neither can drift out of sync with the other or with this
-- generator.
LuckCurve.VALUES = values

-- Shared display formatting so the SurfaceGui labels on the bands and the
-- HUD's landing readout always agree on how a given luck value reads. Values
-- under 1000 (all of decade 1, and most of decade 2) print as plain whole
-- numbers -- 5, 100, 950. From 1000 up, printed in thousands with a "K" suffix,
-- trimming a redundant ".0" (1000 -> "1K", 1500 -> "1.5K", 15000 -> "15K",
-- 100000 -> "100K") -- past four digits, a bare number stops reading as a
-- quantity at a glance, which is exactly the range this curve spends most of
-- its length in (56 of 74 bands, decades 3-4, are all >= 1500).
function LuckCurve.formatLuck(value: number): string
	if value >= 1000 then
		local thousands = string.format("%.1f", value / 1000)
		thousands = thousands:gsub("%.0$", "")
		return thousands .. "K"
	end
	return string.format("%d", value)
end

return LuckCurve
