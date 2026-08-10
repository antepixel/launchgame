# A steeper Divine ladder, with a rarer top

**Branch `ladder-renumber`. Started from `fcb914c502e6a63a50aee737959a92dc741bda95`** with a clean
tree — nothing needed committing first.

| commit | what |
|---|---|
| `fcb914c` | starting point (the anchor revert and its report) |
| `54f2e88` | steps 1-2: the within-tier weighting mechanism, Divine's 1.40 ratio, the 1.50x income ladder |
| `b0baa4e` | step 4: two stale assumptions fixed in `common.luau`, v2 baselines regenerated |

**Every prediction in the brief is confirmed.** Tier 9's expected income per roll moves
$9,192 -> **$9,763** (1.062x, predicted ~$9,757); the ceiling moves $100M/s -> **$244.5M/s**
(predicted ~$245M); P(Divine) is **unchanged to 0.0**; P(Divine 8) at tier 9 falls
0.570% -> **0.132%** (predicted ~0.133%). Nothing contradicted.

## Reproduce every number

```
lune run dev/analysis/verify_divine.luau     # steps 0, 1 and 3, plus the step-4 clamp measurement
lune run dev/analysis/roll_ev_v2.luau        # 2,000,000 rolls/tier, seed 20260810 (~2 min)
lune run dev/analysis/slot_sim_v2.luau       # seed 20260811 (~80 s)
```

All from the repo root. `verify_divine.luau` is deterministic and was run three times: before any
edit (`dev/out/verify_divine_step0.log`, which is where the step-0 answers and the
backward-compatibility test come from), after the mechanism was added at uniform ratios, and after
both edits (`dev/out/verify_divine.log`). Measured at **`54f2e88`** for gameplay figures;
`roll_economics_v2.json` records that hash itself.

---

# Step 0 — read first

## 0a. How mass is distributed within a tier today

**Uniform, and it was uniform in both roll paths.**

```lua
-- SlimeRoll.luau:130-135 (pre-change)
function SlimeRoll.rollSlime(luck: number): SlimeData.Slime
	local tier = rollTier(luck)
	local pool = SlimeData.SLIMES_BY_TIER[tier]
	local index = math.random(1, #pool)     -- flat pick over that tier's list
	return pool[index]
end
```

`rollTier` returns a tier from the luck-shaped window; the second step was an unweighted
`math.random(1, #pool)`. The chest did the same thing independently at
`LaunchServer.server.luau:1444` (`pool[math.random(1, #pool)]`). Tier sizes are
6/6/6/6/6/6/21/8, so a Divine roll was 12.5% likely to be each of the eight.

## 0b. Every consumer of `SLIME_INCOME_BY_TIER`

The constant itself is read in exactly one place — `SlimeData.luau:47`, the generator that turns it
into the 65 slime records' `incomePerSecond`. Everything else reads that field:

| consumer | what it does with it | affected by a Divine income change? |
|---|---|---|
| `SlimeData.luau:47-76` | builds the catalog; asserts the row length against `SLIME_TIER_COUNTS` | yes, and the assert still passes (8 entries) |
| `PlayerProfile.luau:1182` | `totalIncomePerSecond` — sums placed slimes | yes, this is the point |
| `PlayerProfile.luau:997` | sell value = income x 60 | yes: a top Divine now sells for $51.2M |
| `PlayerProfile.luau:1057-1079` | upgrade cost, via `SlimeUpgrade.totalUpgradeCost` | yes, see 0e |
| `PlayerProfile.luau:488, 523` | the world billboard over a placed slime, via `formatIncomePerSecond` | yes, see 0c |
| `InventoryClient.luau:346, 358, 412, 420-424, 482` | income preview, upgrade cost, row label, sell buttons, sort order | yes, all via `MoneyFormat` |
| `SlimeUpgradeTagClient.luau:271, 284` | the on-slime upgrade strip | yes, via `MoneyFormat` |

**Nothing assumes a maximum slime income.** No cap, no clamp, no reverse lookup from income back to
tier — the last of those existed once and was deleted in the upgrade rebuild (`SlimeUpgrade.luau`'s
own header records it, and notes it was fragile precisely because it assumed distinct incomes).

## 0c. `MoneyFormat` at the new magnitudes

| value | renders as |
|---|---|
| $854,297/s | `$854.3K` |
| $245,000,000/s | `$245M` |
| $14,160,000,000 | `$14.2B` |
| 2^53 = 9,007,199,254,740,992 | `$9Qa` |
| 1e18 | `$1Qi` |
| 1e21 | `$1000Qi` |

Suffixes run to Qi (1e18) and the loop degrades gracefully past it (`$1000Qi`) rather than
breaking. Precision is float64's exact-integer range, 2^53 ~= 9.007e15 — every figure this change
produces is at most $141.6B, six orders of magnitude inside it. **`MoneyFormat` renders the new
magnitudes cleanly, so the step-4 stop-before condition does not fire.**

One thing to flag, not fix: `PlayerProfile.formatIncomePerSecond` (`:242`) is a separate local
formatter for the world billboard. It handles K/M/B correctly, so $854.3K/s and a maxed $24.4M/s
both render — but its comment claims per-slime income "tops out at 1200" and names a constant
(`SLIME_TIER_BASE_INCOME`) that no longer exists. The code is fine; the comment was already stale
and this change makes it more so.

## 0d. What a save stores

**Only `globalIndex`.** `toSaveShape` (`PlayerProfile.luau:578-608`) writes `slots` as an array of
`globalIndex` (0 for empty), `levels` as an array of integers, and `inventory` as
`{globalIndex, count}` records. No income is persisted anywhere; `applyLoadedData:621-634` looks the
slime up in `SlimeData.SLIMES[globalIndex]`. **Income changes therefore apply retroactively to every
existing save with no migration** — a player holding Divine 8 wakes up owning an $854K/s slime.
Confirmed.

## 0e. `SlimeUpgrade.totalUpgradeCost(854297, 1, 25)`

**$14,160,063,086.73** — 24 levels, exactly 16,575.105715 seconds of base income, the same
multiplier every slime in the game pays. For the value actually shipped (854,000):
**$14,155,140,280.33**.

Nothing overflows, clamps or loses precision: the cost is a closed form
(`PAYBACK * income * (GROWTH^n - 1)`), $14.16B is 636,000x below 2^53, and the seconds-of-base
figure is identical to five decimal places for both bases — which is the invariant that says the
arithmetic did not drift.

## 0f. The stale clamp in `common.luau`

**Confirmed still present at the start of this pass**: `clampLuck = M.SlimeConfig.SLIME_LUCK_ANCHOR_HIGH`
(then line 135). With `T_MAX = 1.35` the true clamp is `220 * (120000/220)^1.35` = **1,089,047**, so
the box tail was being collapsed 9x early. Fixed in step 4 — along with a second stale assumption in
the same function that this pass created.

---

# Step 1 — the within-tier weighting mechanism

New config, one entry per tier:

```lua
SLIME_TIER_WEIGHT_RATIO = { 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.40 },
```

Semantics: slime i of a tier of n (1-indexed, ascending income) gets weight `ratio ^ -(i - 1)`,
normalised across that tier. Ratio 1.0 is exactly uniform.

Implemented once, in `SlimeRoll.pickSlimeInTier`, and called from both roll paths. **The `ratio == 1`
branch keeps the original `math.random(1, #pool)` call** — that is a compatibility guarantee, not an
optimisation: a uniform tier consumes the same single draw from the same RNG stream and returns the
same slime it would have before the function existed. Only Divine takes the weighted branch.

## The backward-compatibility stop condition — PASSED, before Divine's ratio was set

Run twice, as a distinct result:

| when | comparison | result |
|---|---|---|
| before any config existed (mechanism defaulting to 1.0) | full 65-slime PMF at all ten tier lucks + the chest table | **worst difference 0.000e+00 (bitwise identical)** |
| with `SLIME_TIER_WEIGHT_RATIO` present and **every entry 1.0** | same comparison | **worst difference 0.000e+00 (bitwise identical)** |

Only after the second run passed was Divine's entry changed to 1.40. Bitwise identity — not
"identical to 1e-15" — is achievable because the uniform path evaluates the same `mass / #pool`
expression it always did, rather than `mass * (1/n)`, which would differ by an ulp at n = 6.

## The chest

**The chest rolls its own distribution and it IS affected, deliberately.** Its *tier* comes from its
own table — `CHEST_DIVINE_CHANCE = 0.20` off the top, the rest geometric at
`CHEST_TIER_WEIGHT_RATIO = 2.0` — and neither of those was touched. What changed is the line after:
it used to do its own flat `pool[math.random(1, #pool)]` and now calls
`SlimeRoll.pickSlimeInTier(tier)`, the same function the box uses. So a Divine from a chest and a
Divine from a box are the same lottery, and P(Divine) from a chest is still exactly 0.20 (verified,
§3a). Left uniform, the chest would have paid the top Divine 12.5% of the time while the box paid it
2.9%, which is the kind of split nobody discovers until it is being exploited.

---

# Step 2 — the Divine income ladder

```lua
{ 50000, 75000, 113000, 169000, 253000, 380000, 570000, 854000 }, -- Divine
```

Rounded to three significant figures, matching the table's existing style. The first entry is
exactly 50,000, so the Secret-to-Divine boundary does not move. **Achieved ratios after rounding:**

| step | 1->2 | 2->3 | 3->4 | 4->5 | 5->6 | 6->7 | 7->8 |
|---|---|---|---|---|---|---|---|
| ratio | 1.5000 | 1.5067 | 1.4956 | 1.4970 | 1.5020 | 1.5000 | 1.4982 |

Geometric mean **1.4999x**, total spread **17.08x** (was 7.0x). Worst deviation from the exact
1.50x series is +0.44% (113,000 against 112,500). No other tier's incomes were touched.

---

# Step 3 — verification

`dev/analysis/verify_divine.luau`, fresh code: its own per-slime PMF, its own box integrator with
the clamp derived from `T_MAX`, sharing nothing with `verify_anchor.luau`, `clamp_effect.luau` or
`common.luau`.

## The four stop conditions — all pass

| # | check | expected | actual | |
|---|---|---|---|---|
| 3a | P(Divine) per tier, split vs tier weight | identical to 1e-12 | **0.000e+00** road, **0.000e+00** chest | PASS |
| 3b | worst decreasing step, 74 bands / extrapolated to 1e6 | exactly 0 and 0 | **0.0000e+00 / 0.0000e+00** | PASS |
| 3c | worst \|sum - 1\| over 79 probes + chest | <= 1e-9, no NaN, no negative | **1.110e-15**, none, none | PASS |
| 3d | band 68 pre-box E[base]/roll | ~$8.87K x the Divine change | **$9.416K** (1.061x) | PASS |

**3a** is the one that matters most and it came out exact, not merely within tolerance: the
within-tier split is applied to a tier mass the roll already fixed, so it cannot move it. P(Divine)
at tier 9 is 4.5562% before and after; P(Divine) from a chest is 0.20 before and after.

**3d**: $8.872K -> $9.416K is 1.061x, and the Divine tier's own mean income rose 1.34x
(uniform mean $145,625 -> weighted mean $195,485). The band-68 figure moves less because Divine is
only 4.6% of that band's mass.

## 3e. Per tier

Pre-change comparison figures are the ones the brief supplied, which came from `verify_anchor.luau`
on the same true-clamp integrator, so this is like for like.

| tier | luck | P(Divine) | P(Divine 8) | P(Secret+) | E no box | E with box | vs pre-change |
|---|---|---|---|---|---|---|---|
| 1 | 25 | 0.0036% | 0.0001% | 0.0314% | $25.47 | $39.68 | 1.0113x |
| 2 | 65 | 0.0115% | 0.0003% | 0.0762% | $25.71 | $64.24 | 1.0229x |
| 3 | 150 | 0.0210% | 0.0006% | 0.1392% | $25.93 | $101.1 | 1.0267x |
| 4 | 550 | 0.0691% | 0.0020% | 0.4590% | $66.39 | $257.2 | 1.0348x |
| 5 | 950 | 0.1246% | 0.0036% | 0.8309% | $66.86 | $411.1 | 1.0395x |
| 6 | 4,500 | 0.4160% | 0.0121% | 2.7609% | $190.7 | $1.212K | 1.0450x |
| 7 | 8,500 | 0.7539% | 0.0219% | 5.0112% | $192.6 | $2.043K | 1.0485x |
| 8 | 35,000 | 2.4963% | 0.0726% | 13.3359% | $896.5 | $5.758K | 1.0575x |
| 9 | 75,000 | 4.5562% | 0.1325% | 20.8819% | $9.416K | $9.763K | **1.0621x** |
| 10 | chest | 20.0000% | 0.5815% | 60.3150% | — | $36.07K | chest table |

Expected income rises 1.1% to 6.2%, increasing with tier — the two changes very nearly cancel, which
is what they were designed to do. P(Divine) and P(Secret+) are unchanged everywhere (the small
apparent differences against `roll_ev_v2.json`'s earlier run are the stale-clamp fix in step 4, not
this change).

## 3f. The top Divine at tier 9

**P(Divine 8) = 0.1325%, one in 755 rolls, 2.1 hours of perfect play** at the 10.1 s cycle measured
for tier 9. Before: 0.570%, one in 175 rolls, 29 minutes. The best slime in the game went from
something a player meets in half an hour to something they meet in an afternoon.

## 3g. The Divine PMF at tier 9

| slime | income/s | probability | share of Divine mass | conditional contribution | unconditional |
|---|---|---|---|---|---|
| Divine 1 | $50K | 1.396388% | 30.65% | $15.32K | $698.2 |
| Divine 2 | $75K | 0.997420% | 21.89% | $16.42K | $748.1 |
| Divine 3 | $113K | 0.712443% | 15.64% | $17.67K | $805.1 |
| Divine 4 | $169K | 0.508888% | 11.17% | $18.88K | $860.0 |
| Divine 5 | $253K | 0.363491% | 7.98% | $20.18K | $919.6 |
| Divine 6 | $380K | 0.259637% | 5.70% | $21.65K | $986.6 |
| Divine 7 | $570K | 0.185455% | 4.07% | $23.20K | $1.057K |
| Divine 8 | $854K | 0.132468% | 2.91% | $24.83K | $1.131K |

**Yes, they are roughly equal in contribution, and the brief's $15K-$25K band is exactly right** —
conditional contributions run **$15.32K to $24.83K**, a 1.62x spread against a 17.1x income spread.
(The "conditional" column is contribution to the mean of a Divine roll, which is what that band
refers to; the unconditional column is the same figures times P(Divine), $698 to $1,131, the same
1.62x.) A ratio of 1.50 rather than 1.40 would have made them exactly equal; 1.40 deliberately
leaves the top slightly ahead so chasing it is still worth something.

## 3h/3i. The ceiling and what it costs

| | before | after |
|---|---|---|
| top Divine base income | $350K/s | **$854K/s** |
| ceiling: 10 slots x top x 28.6252 | $100.2M/s | **$244.5M/s** |
| saturated slot price (ceiling slot x $600) | $6,011,287,000 | **$14,666,300,000** |
| cost to max one top Divine | $5.80B | **$14.16B** |
| cost to max a full ceiling base | $58.0B | **$141.6B** |

The saturated-slot price is now **2.44x** what it was. Maxing a full ceiling base costs $141.6B
against the top swing tier's $800B, so the swing ladder is still the larger sink at the very top —
by 5.65x, down from 13.8x before this change.

---

# Step 4 — the stale assumptions, and the rebaseline

## Two fixes in `common.luau`, not one

The brief directed the clamp fix. Applying only that would have left the regenerated baseline
describing a game that no longer exists, so a second assumption in the same function was fixed too,
and that is flagged here rather than buried:

1. **The clamp** — `clampLuck = SLIME_LUCK_ANCHOR_HIGH` became
   `LOW * (HIGH/LOW)^T_MAX` = 1,089,047. Measured on this tree, per tier:

| tier | luck | E with box, stale clamp | true clamp | understated by |
|---|---|---|---|---|
| 1 | 25 | $39.56 | $39.68 | 0.32% |
| 2 | 65 | $63.77 | $64.24 | 0.72% |
| 3 | 150 | $100.3 | $101.1 | 0.82% |
| 4 | 550 | $254.4 | $257.2 | 1.08% |
| 5 | 950 | $406.0 | $411.1 | 1.25% |
| 6 | 4,500 | $1.196K | $1.212K | 1.38% |
| 7 | 8,500 | $2.013K | $2.043K | 1.51% |
| 8 | 35,000 | $5.658K | $5.758K | 1.76% |
| 9 | 75,000 | $9.584K | $9.763K | **1.86%** |

   Which reproduces the previous pass's 0.3%-1.8% estimate closely.

2. **The within-tier split** — the same function divided a tier's mass by `#pool`
   unconditionally. That was correct until this pass gave Divine a 1.40 ratio; left alone, every
   regenerated figure would have modelled a uniform Divine while the game rolled a weighted one.
   It now calls a shared `withinTierShares` helper that mirrors `SlimeRoll.pickSlimeInTier`, with
   uniform tiers keeping the identical `mass / #pool` expression so their numbers stay bit-identical.
   `chestPmf` got the same treatment, for the same reason.

Cross-checked afterwards: `common.luau`'s box-integrated expected income now agrees with the
independent `verify_divine.luau` figures at every tier and at the chest, to the precision of the
comparison (four significant figures).

## The regenerated baselines

`dev/out/roll_ev_v2.json` and `dev/out/roll_economics_v2.json`, at commit `54f2e88`, same seeds
(20260810 / 20260811), same sample counts (2,000,000 rolls per tier; 10,000 sims x 10,000 rolls).
The four `e12ca51` baselines — `roll_economics.json`, `cycle_economics.json`, `slot_sweep.json`,
`roll_ev.json` — are untouched.

| tier | band | luck | E[base]/roll (exact) | (2M sampled) | P(Divine) | P(Secret+) | ratio vs previous tier |
|---|---|---|---|---|---|---|---|
| 1 | 4 | 25 | $39.68 | $38.12 | 0.0036% | 0.0314% | — |
| 2 | 12 | 65 | $64.24 | $62.82 | 0.0115% | 0.0762% | 1.62x |
| 3 | 20 | 150 | $101.1 | $100.8 | 0.0210% | 0.1392% | 1.57x |
| 4 | 28 | 550 | $257.2 | $257.0 | 0.0691% | 0.4590% | 2.54x |
| 5 | 36 | 950 | $411.1 | $417.0 | 0.1246% | 0.8309% | 1.60x |
| 6 | 44 | 4,500 | $1.212K | $1.201K | 0.4160% | 2.7609% | 2.95x |
| 7 | 52 | 8,500 | $2.043K | $2.038K | 0.7539% | 5.0112% | 1.69x |
| 8 | 60 | 35,000 | $5.758K | $5.741K | 2.4963% | 13.3359% | 2.82x |
| 9 | 68 | 75,000 | $9.763K | $9.733K | 4.5562% | 20.8819% | 1.70x |
| 10 | chest | — | $36.07K | $35.98K | 20.0000% | 60.3150% | 3.69x |

Ratios run **1.57x to 3.69x**, against 1.57x-3.72x before this pass and 1.16x-2.47x under the broken
anchor. Per the brief, the ratios are reported and no conclusion is drawn about whether the even
8-band spacing is right.

Ten-slot equilibrium income from `roll_economics_v2.json`, for the next pass to join against:
$47.1K, $161.8K, $319.5K, $1.045M, $1.703M, $3.851M, $5.224M, $7.688M, $8.540M, $8.540M per second
of base income by tier.

---

# What this leaves

1. **Sell value scales with the change and nobody has looked at it.** A top Divine now sells for
   $51.2M (60 seconds of income x $854K). `InventoryConfig.SELL_VALUE_INCOME_MULTIPLIER` was not
   touched, and selling is still 60 seconds of income for every slime — but the *absolute* number a
   Divine sells for is now 2.44x larger, against unchanged swing prices.

2. **The ceiling grew 2.44x while prices did not move.** Equilibrium base income at the top tiers is
   up correspondingly (tier 9's ten-slot equilibrium is now $8.54M/s against $3.5M/s), so measured
   progression times will be shorter than the last full measurement pass reported. No repricing was
   in scope.

3. **`cycle_economics.json` and `slot_sweep.json` still describe `e12ca51`.** Only the two roll-side
   baselines were regenerated. A full re-measurement of cycle time and the slot sweep against this
   tree is still outstanding, and the slot sweep in particular now has a different answer available
   to it: the ceiling it measured as $3.5M/s of base income is $8.54M/s here.

4. **`PlayerProfile.formatIncomePerSecond`'s comment is stale** (0c) — it claims per-slime income
   tops out at 1200 and names a deleted constant. The code handles the new magnitudes correctly;
   only the comment lies. Not fixed, since this pass was scoped to two gameplay constants.

5. **Untouched, as required:** incomes for tiers 1-7, `SLIME_TIER_COUNTS`, all four luck/extrapolation
   constants, `SLIME_PEAK_OFFSET_*`, both spreads, the shape and both NaN floors, the sliding window
   and the generalised Gaussian, `CHEST_DIVINE_CHANCE` and `CHEST_TIER_WEIGHT_RATIO`, the whole
   renumbered ladder and its prices, the 74-band curve, the upgrade curve, `SLOT_COUNT`, the flight
   formulas, the ping compensation, the box mechanics, and `LaunchRewardScene.luau` — not opened.

# Files

**Edited (gameplay), three files:**

- `src/ReplicatedStorage/Config/SlimeConfig.luau` — added `SLIME_TIER_WEIGHT_RATIO` (and its type
  entry), replaced Divine's income row.
- `src/ServerScriptService/SlimeRoll.luau` — new `pickSlimeInTier`, with the uniform fast path;
  `rollSlime` now delegates to it.
- `src/ServerScriptService/LaunchServer.server.luau` — `rollChestSlime`'s final pick goes through
  the same function (one line plus its comment).

**Edited (analysis):** `dev/analysis/common.luau` — the clamp and the within-tier split.

**Created:** `dev/analysis/verify_divine.luau`; `dev/out/verify_divine.log`,
`verify_divine_step0.log`. Regenerated: `dev/out/roll_ev_v2.json`, `roll_economics_v2.json` and
their logs.
