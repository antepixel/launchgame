--!strict
-- Server-only roll logic -- lives in ServerScriptService specifically (not
-- ReplicatedStorage) so a client CANNOT require this module at all, not just
-- "isn't supposed to": ServerScriptService's contents never replicate to any
-- client, structurally, regardless of what a modified client tries. See
-- LaunchServer.server.luau's onBoxPress for the only caller.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SlimeConfig = require(ReplicatedStorage.Config.SlimeConfig)
local SlimeData = require(ReplicatedStorage.Config.SlimeData)

local SlimeRoll = {}

local function lerp(a: number, b: number, t: number): number
	return a + t * (b - a)
end

-- ===== THE SLIDING WINDOW =====
-- Luck does not reweight a fixed 8-tier table -- it moves a WINDOW of
-- SLIME_WINDOW_WIDTH (4) consecutive tiers up the ladder, and reshapes the
-- weighting WITHIN that window as it slides. Tiers outside the window get
-- EXACTLY zero -- "rolled off entirely," not a thin tail -- by construction:
-- the loop below only ever assigns a weight to tiers inside [windowStart,
-- windowStart + WIDTH - 1].
--
-- t is luck's position between the two observed anchors, on a LOG scale
-- (luck spans 220 to 120,000 -- ~545x -- a linear scale would put almost
-- every real luck value within a hair of 0). t=0 at SLIME_LUCK_ANCHOR_LOW,
-- t=1 at SLIME_LUCK_ANCHOR_HIGH; every other shape parameter below is a
-- plain LERP on this same t, clamped to [EXTRAPOLATION_T_MIN,
-- EXTRAPOLATION_T_MAX] so luck far outside the observed range still produces
-- a sane (if increasingly extrapolated) distribution instead of nonsense.
--
-- WINDOW POSITION: windowStart lerps from SLIME_WINDOW_START_LOW (1, i.e.
-- Common-Epic) to SLIME_WINDOW_START_HIGH (5, i.e. Legendary-Divine), then
-- ROUNDS to the nearest whole tier -- the window jumps between whole 4-tier
-- ranges as luck crosses each rounding threshold, which is what makes
-- "rolled off entirely" a clean cutoff rather than a fuzzy fade.
--
-- SHAPE WITHIN THE WINDOW: weight_i = exp( -(|i - peak| / spread) ^ shape ),
-- a generalised (super-)Gaussian. peak = windowStart + peakOffset, where
-- peakOffset is a CONSTANT 1 (peak always sits one tier in from the window's
-- bottom -- Uncommon at low luck, Mythic at high luck) -- see SlimeConfig for
-- why this is fixed rather than lerped: it's what gives every stage the same
-- three-part shape (a fading tier below the peak, the peak, a tail above).
-- spread is SPLIT into spreadDown (i <= peak) and spreadUp (i > peak) so the
-- tier below the peak and the tail above it can decay at different rates --
-- this is what produces the OBSERVED asymmetry at luck 120,000 (Legendary's
-- 15% below Mythic vs. Secret+Divine's 7% above it), which a single symmetric
-- spread cannot reproduce (a symmetric shape would force Legendary and
-- Secret, both exactly 1 tier from the peak, to identical weight), AND (at
-- the low end) what keeps the tail two tiers above the peak sitting at a
-- reachable 1-5% all the way up the curve, not just at the anchors. shape
-- itself also lerps: HIGH at low luck (a moderately peaked middle) down to
-- LOW at high luck (<1, a sharp single spike with a longer tail --
-- reproduces "concentrated in one tier with a thin rare tail"). SHAPE_LOW
-- and SPREAD_*_LOW sit deliberately CLOSE to their _HIGH twins rather than
-- far from them -- see SlimeConfig's SLIME_SPREAD_DOWN_LOW comment for why:
-- the gap between LOW and HIGH is exactly what makes expected roll VALUE
-- dip as luck rises within a still-static window (concentration increasing
-- while the window itself hasn't advanced yet drains the upper tail faster
-- than the fading tier below it can compensate) -- so the two numbers were
-- solved together to keep that dip negligible, not just to hit a target
-- shape at the anchors in isolation. Every one of these curves (windowStart,
-- peakOffset, spreadDown, spreadUp, shape, plus the two luck anchors
-- themselves) is a LOW/HIGH pair in SlimeConfig -- retuning the whole curve
-- is moving those numbers, never rewriting this function.
function SlimeRoll.distributionForLuck(luck: number): { number }
	local lnLow = math.log(SlimeConfig.SLIME_LUCK_ANCHOR_LOW)
	local lnHigh = math.log(SlimeConfig.SLIME_LUCK_ANCHOR_HIGH)
	local lnLuck = math.log(math.max(luck, 1e-6))
	local t = (lnLuck - lnLow) / (lnHigh - lnLow)
	t = math.clamp(t, SlimeConfig.SLIME_EXTRAPOLATION_T_MIN, SlimeConfig.SLIME_EXTRAPOLATION_T_MAX)

	local tierCount = #SlimeConfig.SLIME_TIER_NAMES
	local windowWidth = SlimeConfig.SLIME_WINDOW_WIDTH
	local windowStartRaw = lerp(SlimeConfig.SLIME_WINDOW_START_LOW, SlimeConfig.SLIME_WINDOW_START_HIGH, t)
	local windowStart = math.clamp(math.round(windowStartRaw), 1, tierCount - windowWidth + 1)

	local peakOffset = lerp(SlimeConfig.SLIME_PEAK_OFFSET_LOW, SlimeConfig.SLIME_PEAK_OFFSET_HIGH, t)
	local spreadDown = lerp(SlimeConfig.SLIME_SPREAD_DOWN_LOW, SlimeConfig.SLIME_SPREAD_DOWN_HIGH, t)
	local spreadUp = lerp(SlimeConfig.SLIME_SPREAD_UP_LOW, SlimeConfig.SLIME_SPREAD_UP_HIGH, t)
	local shape = lerp(SlimeConfig.SLIME_SHAPE_LOW, SlimeConfig.SLIME_SHAPE_HIGH, t)
	local peak = windowStart + peakOffset

	local weights = table.create(tierCount, 0)
	local total = 0
	for i = windowStart, windowStart + windowWidth - 1 do
		local dist = i - peak
		local spread = if dist <= 0 then spreadDown else spreadUp
		local w = math.exp(-(math.abs(dist) / spread) ^ shape)
		weights[i] = w
		total += w
	end
	for i = 1, tierCount do
		weights[i] = weights[i] / total
	end
	return weights
end

-- Weighted pick over the distribution above -- a standard cumulative-sum
-- roll, math.random() called ONCE, server-side, here.
local function rollTier(luck: number): number
	local weights = SlimeRoll.distributionForLuck(luck)
	local roll = math.random()
	local cumulative = 0
	for i = 1, #weights do
		cumulative += weights[i]
		if roll <= cumulative then
			return i
		end
	end
	return #weights -- floating-point safety net only; cumulative reaches 1 by construction
end

-- ===== THE FULL ROLL: tier (weighted, luck-shaped) then slime (flat within
-- the tier) -- see the module doc above for the tier step; "within a tier
-- every slime is equally likely" is just a uniform pick over that tier's
-- list. =====
function SlimeRoll.rollSlime(luck: number): SlimeData.Slime
	local tier = rollTier(luck)
	local pool = SlimeData.SLIMES_BY_TIER[tier]
	local index = math.random(1, #pool)
	return pool[index]
end

return SlimeRoll
