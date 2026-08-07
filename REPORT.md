# Tiers 3, 4 and 5 retuned to the geometric ramp

Three prices changed. Tiers 2, 6, 7, 8, 9, 10 and 11 untouched, as required.

| tier | was | exact target-hitting value | **now** | cost |
|---|---|---|---|---|
| 3 | $600K | $432,844 | **$450K** | +3.96% |
| 4 | $8.00M | $5,118,433 | **$5.00M** | −2.31% |
| 5 | $25.0M | $20,017,095 | **$20.0M** | −0.09% |

**Verification:** computed from the live config through `dev/rbxshim.luau` under Lune, after
the edit. No playtest was run.

---

## The rounding choices

The budget was 5% of target accuracy. All three land inside it.

- **Tier 3 → $450K, +3.96%.** This one spends most of the budget. $425K would have cost only
  −1.81% and $430K only −0.66%, but neither is a number a player reads as round. $450K is the
  roundest value available inside the budget, and it makes the visible ladder read
  100K → 450K → 5M → 20M → 250M. I took readability here because the budget explicitly allows
  it; if you would rather keep the accuracy, **$430K costs 0.66%** and is the better trade if
  4% of a twelve-minute target ever matters.
- **Tier 4 → $5.00M, −2.31%.** $5,120,000 would have been near-exact (+0.03%) but "$5.12M" on a
  button is noise. $5M is free of it for 2.3%.
- **Tier 5 → $20.0M, −0.09%.** The exact value rounds to $20M essentially for nothing.

Rounding all three **cost 4.05 minutes in total** across tiers 3–5 (28.9 min of target time vs
32.9 min achieved under the ramp) — under a minute and a half per tier.

---

## Time per step

Same assumptions as `ECONOMY_DUMP.md` section 5: ten filled slots, slimes rolled at that tier's
own post-box luck, perfect sweet-spot landings (so these are a **lower bound**), box at its
geometric-mean 2.333x multiplier, income banked and spent on nothing else.

`geo ramp` is now the config's stated model: level multiplier
`28.6252 ^ ((tier − 1) / 4)`, giving **1.00x / 2.31x / 5.35x / 12.38x / 28.63x** at tiers 1–5,
saturated thereafter.

| step | price | target | A (all L1) | B (all maxed) | geo ramp | error vs target |
|---|---|---|---|---|---|---|
| 1→2 | $100K | 6.0m | 6.5m | 14s | 6.5m | +7.95% |
| 2→3 | **$450K** | 12.0m | 28.9m | 60s | **12.5m** | **+3.96%** |
| 3→4 | **$5.00M** | 24.0m | 2.1h | 4.4m | **23.4m** | **−2.31%** |
| 4→5 | **$20.0M** | 40.0m | 8.2h | 17.3m | **40.0m** | **−0.09%** |
| 5→6 | $250M | 70.0m | 36.3h | 76.0m | 76.0m | +8.61% |
| 6→7 | $3.00B | 3.0h | 4.0d | 3.4h | 3.4h | +11.90% |
| 7→8 | $6.00B | 6.0h | 7.9d | 6.6h | 6.6h | +9.77% |
| 8→9 | $110B | 12.0h | 14.5d | 12.2h | 12.2h | +1.40% |
| 9→10 | $260B | 28.0h | 33.2d | 27.9h | 27.9h | −0.44% |
| 10→11 | $800B | 3.3d | 102.2d | 3.6d | 3.6d | +7.08% |

**The three retuned steps are now the most accurate in the ladder** — 3.96%, 2.31% and 0.09%
against a worst-case of 11.90% at tier 6→7, which was out of scope and unchanged.

Worst deviation across the whole ladder under the geometric ramp: **11.90%**, down from the
**56%** the old tiers 3–5 produced under this same reading.

Tier 1→2's +7.95% is unchanged — tier 2's price was on the exclusion list. It is the one
remaining early step that is meaningfully off, and $92.6K would put it on target if you want it.

Scenario A remains a constant **28.6x** slower than B at every step, since maxing scales all
ten slots by the same factor and prices do not move.

---

## Cumulative

| | to tier 6 | to tier 11 |
|---|---|---|
| target | 2.5h | 5.5d |
| **geo ramp (the model)** | **2.6h** | **5.8d** |
| scenario B (all maxed) | 1.6h | 5.7d |
| scenario A (all level 1) | 47.2h | 163.8d |

**Tier 6 in 2.6h against a 2.5h target — 4% over**, and comfortably inside the 5–7 hour session
alongside levelling and play. Under a fully maxed base it is 1.6h.

**Tier 11 in 5.8d against 5.5d — 5% over.**

Both totals improved slightly against the previous prices (2.6h vs 3.1h to tier 6; 5.8d
unchanged to tier 11), because the three retuned prices came down.

Scenario A's 163.8 days is worth repeating: a player who never levels cannot climb this ladder.
The prices assume levelling happens. That is the intended coupling, but it means the early game
is a wall for anyone who does not engage with upgrades at all.

---

## Ordering

**Nothing is out of order.** Strictly increasing at every step:

| tier | price | x prev |
|---|---|---|
| 2 | $100K | — |
| 3 | $450K | 4.50x |
| 4 | $5.00M | 11.11x |
| 5 | $20.0M | 4.00x |
| 6 | $250M | 12.50x |
| 7 | $3.00B | 12.00x |
| 8 | $6.00B | 2.00x |
| 9 | $110B | 18.33x |
| 10 | $260B | 2.36x |
| 11 | $800B | 3.08x |

Largest value 8.000e11, safely inside float64's exact-integer range (2^53 ≈ 9.007e15).

---

## Smoothness improved

The retune made the time ladder markedly more even, because the three prices moved toward what
the income model actually supports.

| step | price x prev | time x prev (geo ramp) |
|---|---|---|
| 2→3 | 4.50x | 1.93x |
| 3→4 | 11.11x | 1.88x |
| 4→5 | 4.00x | 1.70x |
| 5→6 | 12.50x | 1.90x |
| 6→7 | 12.00x | 2.65x |
| 7→8 | 2.00x | 1.96x |
| 8→9 | 18.33x | 1.85x |
| 9→10 | 2.36x | 2.29x |
| 10→11 | 3.08x | 3.07x |

Price steps span **2.00x – 18.33x** (a 9.2x spread). Time steps now span **1.70x – 3.07x** (a
1.8x spread) — against 2.4x before this retune. **Lumpy prices, smooth times**, which was the
design intent, and the early game is now the smoothest part of the ladder rather than the most
erratic.

The mechanism is still visible at tier 8→9: an 18.33x price jump produces the *smallest* time
step in the whole ladder (1.85x), because income leaps 9.9x across that same step when the roll
window crosses into Epic–Secret. Pricing smoothly there would have produced exactly the uneven
times the lumpy prices avoid.

---

## What the config now records

`ShopConfig.SWING_TIER_PRICES`' comment gained two things:

1. **The ramp is geometric, stated as load-bearing.** The formula
   `28.6252 ^ ((tier − 1) / 4)` is written out, with its five values, and the reasoning — a
   level multiplier compounds, because a player maxes their best slime first and works down,
   so it grows by ratio rather than by equal increments. A linear ramp would credit the player
   with 7.9x their base income by tier 2, which no plausible play pattern produces that early.

   Crucially it also records the **scope** of that choice: the two readings disagree by up to
   3.8x on tiers 3–5 and by **nothing** from tier 6 up, where the ramp has saturated. So the
   ramp shape prices exactly three entries in the table, and if it is ever revisited those are
   the only three that move.

2. **The rounding, with its cost.** The exact values, the shipped values, and the +3.96% /
   −2.31% / −0.09% each one costs — including that tier 3 spends most of the budget on its own
   and that $425K was the accurate alternative.

The existing "this is a model, not a measurement" caveat is kept and narrowed: it now says the
ramp is the single assumption **tiers 3–5** rest on, rather than the whole table, which is the
more accurate claim.

---

## Files changed

| file | change |
|---|---|
| `Config/ShopConfig.luau` | 3 prices (tiers 3, 4, 5) + the geometric-ramp and rounding comments |

No logic changed. `PlayerProfile.buyNextTier` and `ShopClient` read the table unchanged.
Parses clean. Temporary analysis scripts deleted.

`ECONOMY_DUMP.md` sections 4, 5, 6 and 7.5 remain stale — they quote the pre-repricing values.
Regenerating it is still a separate ask.

**Still outstanding:** `.gitignore`'s entries for `ECONOMY_DUMP.md` and `REPORT.md` were
written in UTF-16 and match nothing; both files are tracked anyway from commit `7968604`.
Untracking needs `git rm --cached` plus a UTF-8 rewrite. Not done — no instruction to.
