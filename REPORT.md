# The luck anchor, reverted; `T_MAX` raised instead

**Branch `ladder-renumber`. Started from `a5235f41a82a706d631a0ba90e3d7f7c720afca6`** (the report
commit sitting directly on top of `526bda0`), with a clean tree — nothing needed committing first.

| commit | what |
|---|---|
| `a5235f4` | starting point — the ladder renumber and its report |
| `5a0423f` | steps 1-2: `SLIME_LUCK_ANCHOR_HIGH` back to 120,000, `SLIME_EXTRAPOLATION_T_MAX` to 1.35 |
| `be2b31a` | step 4: the fresh v2 baseline |

**Two gameplay constants changed in this pass, both in `SlimeConfig.luau`, and nothing else.**
`git diff a5235f4 5a0423f --stat` is one file, and the only non-comment lines in it are those two
values.

## Reproduce every number

```
lune run dev/analysis/verify_anchor.luau      # step 0 + step 3, all four stop conditions
lune run dev/analysis/roll_ev_v2.luau         # step 4a: 2,000,000 rolls/tier, seed 20260810 (~2 min)
lune run dev/analysis/slot_sim_v2.luau        # step 4b: seed 20260811 (~75 s)
```

All from the repo root. `verify_anchor.luau` is deterministic and safe to run before or after the
edit — it was run both ways, and the pre-edit run is kept at `dev/out/verify_anchor_before.log` as
evidence the verifier detects the broken state rather than merely agreeing with whatever it finds.

Measured at **`5a0423f`** (steps 0-3) and **`5a0423f`** (step 4 — `roll_economics_v2.json` records
that hash itself).

## The finding that matters

**The revert works exactly as the brief predicted, and the thing it was meant to fix stays broken.**
Band 68's pre-box income is back to `$8.872K`, all four window transitions are back on the road, and
the box now gets four live doublings there instead of one. But band 68's box multiple only moves
**1.01x -> 1.04x**, because past `t = 0.875` the window is saturated — there is no fifth window
above Legendary-Divine for extra `t` to unlock, so all the extrapolation can do is sharpen the shape
inside the top window, worth about 10% of expected income. **New tier 9 still has a near-dead box.**
The 2.55x the anchor change bought was not headroom; it was the mapping being broken in a way that
left band 68 far enough down the window progression to have somewhere to climb.

---

# Step 0 — the peak lerp, before anything was edited

Run against the unedited tree (`dev/out/verify_anchor_before.log`).

## 0a. What `peak` is

```lua
-- SlimeRoll.luau:79
local peakOffset = lerp(SlimeConfig.SLIME_PEAK_OFFSET_LOW, SlimeConfig.SLIME_PEAK_OFFSET_HIGH, t)
-- SlimeRoll.luau:94
local peak = windowStart + peakOffset
-- SlimeRoll.luau:98-104 -- the only place it is used
for i = windowStart, windowStart + windowWidth - 1 do
	local dist = i - peak
	local spread = if dist <= 0 then spreadDown else spreadUp
	local w = math.exp(-(math.abs(dist) / spread) ^ shape)
```

**Endpoints: `SLIME_PEAK_OFFSET_LOW = 1.0`, `SLIME_PEAK_OFFSET_HIGH = 1.0` — identical, so
`peakOffset` is a constant 1.0 and does not vary with `t` at all.** `SlimeConfig`'s own comment says
this is deliberate: a fixed offset is what gives every stage the same three-part shape.

**It is not an index, of either kind.** It is the real-valued centre of the generalised Gaussian, in
slime-tier units, and it is only ever read as `dist = i - peak` inside the window loop. No table is
subscripted with it, so it cannot index `nil` and cannot wrap. What it *could* do — if the endpoints
ever differed — is drift outside `[windowStart, windowStart + 3]`, which would put the modal weight
on a tier that never gets a weight assigned. That is the failure mode worth watching, and it is
structurally impossible while the two endpoints are equal.

## 0b/0c. Every `t`-dependent quantity at the probe values

| t | windowStart | peakOffset | peak | peak inside the window? | spreadDown | spreadUp | shape | floors engaged |
|---|---|---|---|---|---|---|---|---|
| 1.00 | 5 | 1.0000 | 6.00 | yes | 0.3780 | 0.6400 | 0.9000 | none |
| 1.10 | 5 | 1.0000 | 6.00 | yes | 0.3618 | 0.6350 | 0.8820 | none |
| 1.20 | 5 | 1.0000 | 6.00 | yes | 0.3456 | 0.6300 | 0.8640 | none |
| 1.30 | 5 | 1.0000 | 6.00 | yes | 0.3294 | 0.6250 | 0.8460 | none |
| **1.35** | 5 | 1.0000 | **6.00** | **yes** | 0.3213 | 0.6225 | 0.8370 | **none** |
| 1.40 | 5 | 1.0000 | 6.00 | yes | 0.3132 | 0.6200 | 0.8280 | none |
| 1.50 | 5 | 1.0000 | 6.00 | yes | 0.2970 | 0.6150 | 0.8100 | none |

`peak` is 6.00 at every one of them — Mythic, one tier inside the Legendary-Divine window. **Nothing
falls outside any valid range at any probed `t`, and no floor engages.**

## 0d. `windowStart` range check

| t | raw lerp | rounded | after clamp | saturated at 5? |
|---|---|---|---|---|
| 0.875 | 4.5000 | 5 | 5 | yes |
| 1.000 | 5.0000 | 5 | 5 | yes |
| 1.100 | 5.4000 | 5 | 5 | yes |
| 1.200 | 5.8000 | 6 | **5** | yes |
| 1.300 | 6.2000 | 6 | **5** | yes |
| 1.350 | 6.4000 | 6 | **5** | yes |
| 1.400 | 6.6000 | 7 | **5** | yes |
| 1.500 | 7.0000 | 7 | **5** | yes |
| 3.000 | 13.0000 | 13 | **5** | yes |

Confirmed: it saturates at 5 for every `t >= 0.875` and can never index out of range — the clamp in
`SlimeRoll.luau:77` is doing real work from `t = 1.2` upward, and the ceiling it clamps to
(`tierCount - windowWidth + 1` = 5) is derived, not hardcoded.

## 0e. `T_MAX_SAFE` and `T_MAX_TARGET`

| quantity | lerp | reaches its floor at |
|---|---|---|
| `spreadDown` | 0.54 -> 0.378, floor `SLIME_SPREAD_FLOOR` = 0.05 | **t = 3.0247** |
| `shape` | 1.08 -> 0.90, floor `SLIME_SHAPE_FLOOR` = 0.10 | t = 5.4444 |
| `spreadUp` | 0.69 -> 0.640, floor 0.05 | t = 12.8000 |
| `peak` | constant 1.0 offset | never leaves range |
| `windowStart` | saturates at 5 | never out of range |

```
T_MAX_SAFE   = 3.0247      (bound: spreadDown, the first floor to engage)
T_MAX_TARGET = min(1.35, 3.0247) = 1.35
```

Well above the 1.10 stop threshold, so I proceeded. **Note this is a tighter bound than the previous
pass reported**: that pass gave `spreadDown`'s *zero crossing* at t = 3.3333, but the floor engages
earlier, at 3.0247, and "no floor engaged" is the stricter condition the brief asked for.

**One correction found while doing this.** The comment that justified `T_MAX = 1.0` claimed the shape
exponent "crosses ZERO at t=1.21 and goes NEGATIVE beyond that". Against the current constants that
is false — shape lerps 1.08 -> 0.90 and crosses zero at t = 6.0, not 1.21. The 1.21 predates the
retune that set these values. It was the stated reason `T_MAX` could not be raised, so anyone
trusting it would have concluded this change was unsafe. The comment has been rewritten with the
measured figure and the correction recorded in place.

---

# Steps 1 and 2 — the two constants

```lua
SLIME_LUCK_ANCHOR_HIGH     = 120000   -- was 1000000
SLIME_EXTRAPOLATION_T_MAX  = 1.35     -- was 1.0
```

`SLIME_LUCK_ANCHOR_LOW` (220) and `SLIME_EXTRAPOLATION_T_MIN` (-0.5) are untouched, as is every
other line of `SlimeRoll.luau` — the sliding window, the generalised Gaussian, both NaN floors.

Both comment blocks were rewritten. The anchor's now records that it does **two** jobs — it sets
where `t` clamps *and* the rate at which `t` advances, because `t = ln(luck/220) / ln(HIGH/220)` —
and that this is exactly why it is not the knob for box headroom. `T_MAX`'s names the binding
quantity (`spreadDown` reaching its floor at t = 3.0247), states that `peak` cannot leave range at
any `t`, corrects the stale 1.21 claim, and says plainly that window saturation at t = 0.875 is what
caps the gain.

## Verifying the arithmetic the brief supplied

| the brief's figure | measured | agrees |
|---|---|---|
| `ln(120000/220) = 6.3016` | 6.30157 | yes |
| top band luck 100,000 -> t = 0.9711 | 0.97110 | yes |
| band 68, luck 75,000 -> t = 0.9254 | 0.92541 | yes |
| 150,000 -> t = 1.0354 | 1.03539 | yes |
| 300,000 -> t = 1.1454 | 1.14537 | yes |
| 600,000 -> t = 1.2554 | 1.25534 | yes |
| 1,200,000 -> t = 1.3654 | 1.36532, **clamped to 1.35** | yes |

The clamp now bites at luck `220 * (120000/220)^1.35` = **1.0887M**, which is why the fourth doubling
from band 68 (1.2M) is the last one that moves anything.

---

# Step 3 — verification

`dev/analysis/verify_anchor.luau`, written fresh. It shares no code with `clamp_effect.luau` and
does not use `common.luau`'s box integrator — that one hardcodes the clamp at
`SLIME_LUCK_ANCHOR_HIGH`, which is only correct while `T_MAX = 1.0`; this file derives the clamp
from `T_MAX` instead. See §"A defect in the v2 numbers" for what that assumption costs elsewhere.

## The four stop conditions — all four pass

| # | check | expected | actual | |
|---|---|---|---|---|
| 3a | band 68 (luck 75,000) pre-box E[base]/roll | $8.0K..$9.8K (~$8.87K) | **$8.872K** | PASS |
| 3b | window transitions, by band | 0, 27, 40, 56, 64 | **0, 27, 40, 56, 64** | PASS |
| 3c | worst decreasing step across 74 band lucks | 0 | **0.000000e+00** | PASS |
| 3d | worst \|sum - 1\| past the old clamp | <= 1e-9, no NaN/negative/out-of-range | **2.220e-16** | PASS |

**3a** is the number that proves the mapping is back: `$8.872K` against the `$8.87K` recorded in the
pre-change `dev/out/roll_ev.json`, and against the `$877` the broken anchor produced — a 10.1x
recovery, to four significant figures the original value.

**3b**, in full:

| band | luck | t | window becomes |
|---|---|---|---|
| 0 | 5 | -0.5000 (clamped at T_MIN) | Common-Epic |
| 27 | 500 | 0.1303 | Uncommon-Legendary |
| 40 | 2,500 | 0.3857 | Rare-Mythic |
| 56 | 15,000 | 0.6700 | Epic-Secret |
| **64** | **55,000** | **0.8762** | **Legendary-Divine** |

The t = 0.875 transition is back on the road at band 64, where three measurement passes validated
it. Under the broken anchor it needed luck 349,000 against a top band of 100,000 and did not exist
on the road at all.

**3d**, per probe — every one sums to 1.000000000000000 with no NaN, no negative mass and no weight
outside the 8 real tiers (65 slimes): luck 120K, 250K, 500K, 1M, 5M. Worst deviation 2.220e-16, which
is one float ulp.

## 3e. Does the extrapolation reach?

**Yes — the distributions differ, so `T_MAX` bought something. It is just small.**

| luck | t | P(Divine) | E[base]/roll | TV distance from the previous probe |
|---|---|---|---|---|
| 120K | 1.0000 | 4.4686% | $9.062K | — |
| 250K | 1.1165 | 4.6760% | $9.370K | 0.003732 |
| 500K | 1.2265 | 4.8801% | $9.673K | 0.003456 |
| 1M | 1.3365 | 5.0924% | $9.988K | 0.003393 |

No two are identical, so the fix is reaching. Across the whole extrapolated range the gain is
**+10.2% of expected income and +0.62 points of P(Divine)** — the window cannot advance past
Legendary-Divine, so all `t` can do above 0.875 is sharpen the shape inside it.

## 3f. Box multiple per tier, three trees side by side

Integrating the doubling chain exactly (geometric at `BOX_DOUBLE_CHANCE = 0.55`, tail collapsed at
the true clamp). **The three columns are not on the same bands** — the original tree is the
11-tier ladder, the other two the renumbered 10-tier one — so only tier 1 (band 4, luck 25) is a
like-for-like comparison across all three.

| tier | original tree (anchor 120K, T_MAX 1.0) | anchor-1,000,000 tree | **this tree** |
|---|---|---|---|
| 1 | 1.53x | 1.24x | **1.54x** |
| 2 | 2.53x | 1.42x | **2.44x** |
| 3 | 4.09x | 1.76x | **3.80x** |
| 4 | 3.95x | 3.47x | **3.74x** |
| 5 | 3.78x | 2.16x | **5.92x** |
| 6 | 5.99x | 4.77x | **6.08x** |
| 7 | 9.95x | 2.79x | **10.12x** |
| 8 | 3.79x | 6.81x | **6.07x** |
| 9 | 5.94x | 2.55x | **1.04x** |
| 10 | 1.01x | (chest) | (chest) |

**Plainly: one tier is under 1.5x — tier 9, at 1.04x.** Tiers 1 and 2 are fixed (1.54x and 2.44x,
back above where the original tree had them), and every other tier is at or above 3.7x. But the dead
box that the ladder renumber deleted old tier 10 to remove is now sitting on new tier 9, at 1.04x
instead of 1.01x. Raising `T_MAX` moved it by three percentage points.

The reason is structural and worth stating exactly: **band 68 sits at t = 0.9254, already inside the
final window.** Its four remaining doublings all land in the range where the window cannot advance,
so they buy the ~10% of shape sharpening from 3e and nothing else. No value of `T_MAX` fixes this —
`T_MAX = 3.0` would add perhaps another few percent. What band 68's box would need is a *fifth*
window, which needs more slime tiers, or a top band placed lower in the window progression.

## 3g. Doublings that still change the distribution, per tier

| tier | band luck | live doublings |
|---|---|---|
| 1 | 25 | 16 |
| 2 | 65 | 15 |
| 3 | 150 | 13 |
| 4 | 550 | 11 |
| 5 | 950 | 11 |
| 6 | 4,500 | 8 |
| 7 | 8,500 | 8 |
| 8 | 35,000 | 5 |
| 9 | 75,000 | **4** |
| 10 | chest — no box on that path | — |

Band 68 gets the four the brief predicted. Under the old `T_MAX = 1.0` it had one.

## 3h. Expected base income per roll, per tier

| tier | band luck | no box | with box | box multiple |
|---|---|---|---|---|
| 1 | 25 | $25.47 | $39.24 | 1.54x |
| 2 | 65 | $25.71 | $62.80 | 2.44x |
| 3 | 150 | $25.93 | $98.50 | 3.80x |
| 4 | 550 | $66.39 | $248.5 | 3.74x |
| 5 | 950 | $66.86 | $395.5 | 5.92x |
| 6 | 4,500 | $190.7 | $1.160K | 6.08x |
| 7 | 8,500 | $192.6 | $1.949K | 10.12x |
| 8 | 35,000 | $896.5 | $5.445K | 6.07x |
| 9 | 75,000 | $8.872K | $9.192K | 1.04x |
| 10 | chest | — | $33.6K (chest table) | — |

---

# Step 4 — the fresh baseline, beside the old one

`dev/out/roll_economics.json`, `cycle_economics.json`, `slot_sweep.json` and `roll_ev.json` are
untouched and still describe commit `e12ca51`.

**Deviation from the brief, stated because it changes the file list.** The brief asked for
`roll_ev.luau` to write both `roll_ev_v2.json` and `roll_economics_v2.json`. It cannot: those two
files come from two different scripts (`roll_ev.luau` writes the first, `slot_sim.luau` the second),
and both hardcode their paths with no argument to override. So both were copied:

- `dev/analysis/roll_ev_v2.luau` — one change, the output path. Verified by diffing against the
  original with `_v2` stripped: the only remaining difference is the added header paragraph.
- `dev/analysis/slot_sim_v2.luau` — two changes, its input path (it reads the v2 roll data) and its
  output path.

Neither needed a tier-count edit; both already read `#SWING_TIER_DISTANCE_SCALE`. Seeds (20260810 /
20260811) and sample counts (2,000,000 rolls per tier; 10,000 sims x 10,000 rolls) are unchanged.
`roll_economics_v2.json` records `gitCommit 5a0423f`.

## The renumbered ladder, measured on this tree

Sampled and analytic figures agree to a max per-slime PMF deviation of 3.5e-04.

| tier | band | pre-box luck | E[base]/roll (exact) | (2M sampled) | P(Divine) | P(Secret+) | ratio vs previous tier |
|---|---|---|---|---|---|---|---|
| 1 | 4 | 25 | $39.12 | $38.57 | 0.0035% | 0.0313% | — |
| 2 | 12 | 65 | $62.37 | $61.23 | 0.0112% | 0.0759% | **1.59x** |
| 3 | 20 | 150 | $97.74 | $98.72 | 0.0205% | 0.1386% | **1.57x** |
| 4 | 28 | 550 | $246.0 | $252.5 | 0.0674% | 0.4568% | **2.52x** |
| 5 | 36 | 950 | $390.8 | $391.1 | 0.1215% | 0.8269% | **1.59x** |
| 6 | 44 | 4,500 | $1.145K | $1.167K | 0.4057% | 2.7478% | **2.93x** |
| 7 | 52 | 8,500 | $1.921K | $1.962K | 0.7351% | 4.9872% | **1.68x** |
| 8 | 60 | 35,000 | $5.353K | $5.463K | 2.4344% | 13.2568% | **2.79x** |
| 9 | 68 | 75,000 | $9.027K | $9.201K | 4.4451% | 20.7400% | **1.69x** |
| 10 | chest | — | $33.57K | $33.56K | 20.0000% | 60.3150% | **3.72x** |

**Income ratios are now 1.57x to 3.72x**, against the 1.16x-2.47x the previous pass measured under
the broken anchor. They alternate — roughly 1.6x, then 2.5-2.9x, then 1.6x again — because a tier
whose 8-band step crosses a window transition gains far more than one whose step stays inside a
window. Per the brief I am reporting the ratios and stopping; whether the even 8-band spacing is the
right choice is a separate decision.

## A defect in the v2 numbers, found while checking them

The with-box figures in `roll_ev_v2.json` are **understated by 0.3% to 1.8%**, and the cause is worth
recording. `roll_ev.luau` gets its box mixture from `dev/analysis/common.luau`, whose
`rollPmfForBandLuck` sets `clampLuck = SlimeConfig.SLIME_LUCK_ANCHOR_HIGH`. That was correct while
`t` clamped exactly at the anchor. With `T_MAX = 1.35` the clamp moved to 1.0887M, so the integrator
now collapses the doubling tail 3.2x too early:

| tier | v2 JSON (stale clamp) | verify_anchor (clamp derived from T_MAX) | understated by |
|---|---|---|---|
| 1 | $39.12 | $39.24 | 0.3% |
| 5 | $390.8 | $395.5 | 1.2% |
| 8 | $5.353K | $5.445K | 1.7% |
| 9 | $9.027K | $9.192K | 1.8% |

`common.luau` is on this pass's read-only list, so it was **not** edited — the bias is reported
instead. It is small enough not to change any conclusion here, and the correct figures are the
`verify_anchor.luau` ones in §3f/3h. Any future pass that touches `T_MAX` again should fix
`common.luau` first, or its baselines will drift further.

---

# What this leaves

1. **New tier 9's box is still dead (1.04x).** The renumber deleted old tier 10 for having a 1.01x
   box; the same band, now under new tier 9, has 1.04x. `T_MAX` cannot fix it — the window is
   saturated from t = 0.875 and there is no sixth tier-window to unlock. The options are a fifth
   window (more slime tiers), a top band placed lower in the progression (a shorter road or a
   different band target for tier 9), or accepting that the top road tier's box is decorative.

2. **The road is exactly as three measurement passes measured it.** Transitions at bands
   0/27/40/56/64, band 68 at $8.87K, monotonicity intact. Anything those passes concluded about
   per-band income holds again.

3. **The v2 baseline is ready for the next pass** at `dev/out/roll_ev_v2.json` and
   `dev/out/roll_economics_v2.json`, both recording `5a0423f`, with the 0.3-1.8% box understatement
   noted above. `cycle_economics.json` and `slot_sweep.json` have **not** been regenerated — they
   still describe `e12ca51`, so a full re-measurement of cycle time and the slot sweep against this
   tree is still outstanding.

4. **Untouched, as required:** `SLIME_LUCK_ANCHOR_LOW`, `SLIME_EXTRAPOLATION_T_MIN`, every other line
   of `SlimeRoll.luau`, the whole renumbered ladder (`SWING_TIER_DISTANCE_SCALE`, the visual scales,
   `SWING_TIER_SNAP_THRESHOLD` with 1.95 at index 10, `SWING_TIER_PRICES`, the design targets), the
   74-band curve, `RUNWAY_BAND_LENGTH_STUDS`, `RUNWAY_START_Z`, the box mechanics, the chest table
   and landing path, the flight and arch formulas, the upgrade curve, `SLOT_COUNT`, the base layout,
   the ping compensation, and `LaunchRewardScene.luau` — which was not opened.

# Files

**Edited (gameplay):** `src/ReplicatedStorage/Config/SlimeConfig.luau` — two constants and their
comment blocks. Nothing else.

**Created:** `dev/analysis/verify_anchor.luau`, `dev/analysis/roll_ev_v2.luau`,
`dev/analysis/slot_sim_v2.luau`, and in `dev/out/`: `verify_anchor.log`,
`verify_anchor_before.log`, `roll_ev_v2.json`, `roll_ev_v2.log`, `roll_economics_v2.json`,
`slot_sim_v2.log`.
