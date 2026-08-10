-- How much of a roll's value comes from the mystery box, as opposed to the
-- band the player landed on: expected base income per roll at each tier's
-- pre-box band luck (no doublings at all) against the box-integrated figure.
--
--   lune run dev/analysis/nobox_ev.luau
--
-- Run from the REPO ROOT. Pure analytic -- no sampling, no seed.
local C = require("./common")

print("tier  bandLuck  E[base]/roll no box  E[base]/roll with box  box multiple")
for tier = 1, C.SWING_TIER_COUNT do
	local f = C.perfectLaunchForTier(tier)
	if f.zone ~= "road" then
		print(string.format("%4d  %8s  (chest landing -- no box on this path)", tier, tostring(f.luck)))
		continue
	end
	local weights = C.SlimeRoll.distributionForLuck(f.luck)
	local noBox = 0
	for t, mass in weights do
		if mass > 0 then
			local pool = C.SlimeData.SLIMES_BY_TIER[t]
			local mean = 0
			for _, s in pool do
				mean += s.incomePerSecond
			end
			noBox += mass * mean / #pool
		end
	end
	local withBox = C.expectedIncomeOfPmf(C.rollPmfForBandLuck(f.luck))
	print(string.format("%4d  %8s  $%-18s  $%-20s  %.2fx", tier, tostring(f.luck), C.fmt(noBox), C.fmt(withBox), withBox / noBox))
end
