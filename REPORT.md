# The swing ladder, renumbered from eleven tiers to ten

**Branch: `ladder-renumber`. Pre-change commit: `8ea8f408adcb918523301a5dc44aef2f99be17e3`.**

That commit is a snapshot of the tree exactly as the three measurement passes describe it, taken
before anything here was edited. To undo the whole change:

```
git reset --hard 8ea8f408adcb918523301a5dc44aef2f99be17e3
```

Three commits on the branch, in the order the brief asked for:

| commit | what |
|---|---|
| `8ea8f40` | baseline (pre-change), nothing of this task in it |
| `4d972fc` | step 3 — the renumber itself |
| `526bda0` | step 5 — the migration statement, after step 4's verification |

Studio was never opened, no playtest was run, and nothing in `dev/out/roll_economics.json`,
`dev/out/cycle_economics.json`, `dev/out/slot_sweep.json` or the five earlier analysis scripts was
regenerated or edited.

## Reproduce every number

```
lune run dev/analysis/solve_ladder.luau     # step 2: the solve (also prints the current-ladder offsets)
lune run dev/analysis/verify_ladder.luau    # step 4 + step 5: read-back through the real formulas
lune run dev/analysis/clamp_effect.luau     # step 3f: what the luck-anchor change did
lune run dev/run_gallery.luau               # smoke test: builds every tier through the real SwingBuilder
```

All from the repo root. Deterministic — no sampling and no seeds anywhere in this pass.

## The one thing that needs a second pass

**Raising `SLIME_LUCK_ANCHOR_HIGH` to 1,000,000 did what it was asked to do at the top of the road
and cost about 10x of base roll value on the way.** The dead box is gone — the band the new tier 9
lands on went from a 1.01x box to a 2.55x box — but stretching the anchor also slowed how fast the
window advances with luck, so the same band that used to roll `$8.87K` of expected base income now
rolls `$877`. Net, at the same band and including the box, a roll is **4.0x worse than it was**
(`$8.98K` -> `$2.23K`). Prices were not rebalanced, by instruction. §3f has the measurement; §"What
this leaves" has the consequence.

---

# Step 1 — what the source actually says

Nothing found here contradicts the brief in a way that blocks the change, so I proceeded. Three
answers came back *smaller* than the brief assumed, and one came back structurally different; all
four are called out below rather than quietly absorbed.

## 1a. Everything indexed by swing tier

| what | file:line | length before | length after |
|---|---|---|---|
| `SWING_TIER_DISTANCE_SCALE` | `LaunchConfig.luau:1044` (now `:1073`) | 11 | 10 |
| `SWING_TIER_SNAP_THRESHOLD` | `LaunchConfig.luau:1068` (now `:1097`) | 11 | 10 |
| `SwingTierVisuals.TIERS` | `SwingTierVisuals.luau:143` | 11 records | 10 records |
| `SWING_TIER_PRICES` | `ShopConfig.luau:108` | 11 | 10 |
| design-target list | `ShopConfig.luau:39-43` | 10 targets (tiers 2-11) | 9 targets (tiers 2-10) |

**Structural difference from the brief's assumption:** there is no "visual scale array". Visual
scale is one field (`scale`) inside `SwingTierVisuals.TIERS`, an array of 11 full art records —
frame material, colours, chain style, trail and burst settings. Deleting a tier means deleting a
whole record, not an entry in a number list. Old tier 10's record (obsidian, energy tether) is the
one that went; the surviving records keep their own art and only their `scale` moved.

**The design-target list is a comment block, not code** (`ShopConfig.luau:39-43`) — it documents how
the prices were derived. It was updated with the same care as the array it describes.

**Rope length is not an array at all** — see 1c.

**There is no explicit ladder bound anywhere.** Every consumer derives the count from
`#LaunchConfig.SWING_TIER_DISTANCE_SCALE`: `PlayerProfile.buyNextTier:1134`,
`applyLoadedData:641`, `devSetSwingTier:1325`, `ShopClient.client.luau:86`,
`DevPanelClient.client.luau:362`. That is why this change is as small as it is.

## 1b. Literal `10`s and `11`s that mean a swing tier

**In `src/`: none that are functional.** I checked every site the brief named:

| site | what it does | literal? |
|---|---|---|
| `LaunchServer.server.luau:2253` chest branch | branches on `flight.zone == "past"` | no — zone, never a tier number |
| `PlayerProfile.buyNextTier:1134-1137` | `nextTier > #SWING_TIER_DISTANCE_SCALE` | no |
| `PlayerProfile.applyLoadedData:641` | clamps to `#SWING_TIER_DISTANCE_SCALE` | no |
| `ShopClient.client.luau:86` | `TIER_COUNT = #SWING_TIER_DISTANCE_SCALE`, rows built `1..TIER_COUNT` | no |
| `DevPanelClient.client.luau:362` | `swingTierCount = #SWING_TIER_DISTANCE_SCALE`, buttons in rows of 4 | no |
| `SwingTierVisuals.forTier:535` | `math.clamp(tier, 1, #tiers)` | no |

So 3d turned out to be a comment job, not a code job. **34 comment references to "tier 11" or
"tier 10" did name an index whose meaning changed**, across 14 files, and those were updated — a
comment that says "tier 11 is the only tier this can fire on" is false the moment the ladder has
ten. They are listed in §3d.

**Outside `src/`, one real literal:** `gallery/SwingGallery.server.luau:25` held
`local TIER_COUNT = 11`. The gallery is dev-only tooling and outside the brief's `src/` scope, but
after the renumber it rendered a phantom eleventh swing that `forTier` silently clamped to the top
tier — the gallery drew the same swing twice and labelled the copy a tier. It now reads
`#LaunchConfig.SWING_TIER_DISTANCE_SCALE` like every other consumer. Reported here because it is a
change outside the named scope.

## 1c. Visual scale and rope length are not independent

Rope is **derived**, one line, no table:

```lua
-- SwingGeometry.luau:71-73
function SwingGeometry.ropeLengthForScale(scale: number): number
	return LaunchConfig.SWING_ROPE_LENGTH * scale     -- SWING_ROPE_LENGTH = 10
end
```

`SwingBuilder` calls it with the tier's own `visual.scale`; `swingSeatPosition` recovers the same
number at runtime from the pivot's live Y via `ropeLengthForPivotY` (the inverse of
`pivotYForScale`). So choosing a visual scale sets the rope, and the rope sets the seat — which is
exactly why the solve has to run in that order.

## 1d. The seat offset, and what it is on the current ladder

The launch does not start at band 0 and does not start at the pivot. At sweet-spot phase
(`SWEET_SPOT_PHASE = 0.25`, where `sin(2*pi*phase) = 1` so theta is the full 35-degree arc):

```
-- LaunchServer.server.luau:591-594 (swingTheta), :602-610 (swingSeatPosition)
seatZ  = SWING_PIVOT_Z - ropeLength * sin(SWING_ARC_HALF_ANGLE_DEGREES)
-- :683-688 trajectoryPosition at u = 1, then :736-746 bandLuckForLandingZ
offset = seatZ - RUNWAY_START_Z        -- studs of the flight spent before band 0
```

`SWING_PIVOT_Z = 30`, `RUNWAY_START_Z = -4.26`. Measured on the **pre-change** ladder:

| tier | visual scale | rope | seat Z | offset from band 0 |
|---|---|---|---|---|
| 1 | 1.00 | 10.00 | 24.264 | **28.524** |
| 2 | 1.12 | 11.20 | 23.576 | 27.836 |
| 3 | 1.28 | 12.80 | 22.658 | 26.918 |
| 4 | 1.55 | 15.50 | 21.110 | 25.370 |
| 5 | 1.75 | 17.50 | 19.962 | 24.222 |
| 6 | 2.00 | 20.00 | 18.528 | 22.788 |
| 7 | 2.30 | 23.00 | 16.808 | 21.068 |
| 8 | 2.55 | 25.50 | 15.374 | 19.634 |
| 9 | 2.80 | 28.00 | 13.940 | 18.200 |
| 10 | 3.15 | 31.50 | 11.932 | 16.192 |
| 11 | 3.60 | 36.00 | 9.351 | **13.611** |

The offset shrinks by 14.9 studs across the ladder — more than a third of a band — which is the
coupling the brief warns about and `ECONOMY_DUMP.md` got wrong.

## 1e. A saved `swingTier` of 10 or 11 against a 10-entry ladder

**It already clamps, and always did.** `PlayerProfile.applyLoadedData:640-643`:

```lua
if typeof(data.swingTier) == "number" then
	local tierCount = #LaunchConfig.SWING_TIER_DISTANCE_SCALE
	profile.swingTier = math.clamp(math.floor(data.swingTier), 1, tierCount)
end
```

It does not error, and it cannot persist out of range: `toSaveShape:604` writes
`profile.swingTier`, which is the already-clamped value. Nothing else assigns the field except
`buyNextTier` (bounded) and `devSetSwingTier` (clamped the same way). See §5 for what that means for
real saves and for the one consequence it carries.

## 1f. The luck clamp and everything that reads it

| constant | value before | read at |
|---|---|---|
| `SLIME_LUCK_ANCHOR_LOW` | 220 | `SlimeRoll.luau:68` |
| `SLIME_LUCK_ANCHOR_HIGH` | **120,000** | `SlimeRoll.luau:69` |
| `SLIME_EXTRAPOLATION_T_MIN` | -0.5 | `SlimeRoll.luau:72` |
| `SLIME_EXTRAPOLATION_T_MAX` | 1.0 | `SlimeRoll.luau:72` |

Those four are read in exactly one function, `SlimeRoll.distributionForLuck` (`:67-109`), and
nowhere else in `src/`. The consuming logic:

```
t = (ln(luck) - ln(LOW)) / (ln(HIGH) - ln(LOW))          -- :68-71, log scale
t = clamp(t, T_MIN, T_MAX)                                -- :72
windowStart = clamp(round(lerp(1, 5, t)), 1, 5)           -- :76-77, whole-tier jumps
peak/spreadDown/spreadUp/shape = lerp(..., t)             -- :79-93, each with a floor
```

Because `windowStart` **rounds**, the window advances in whole-tier jumps at fixed values of `t`,
and `t` is a pure function of `ln(luck)` between the two anchors. Moving the high anchor therefore
moves every one of those jumps, not just the clamp point — which is the whole of §3f.

---

# Step 2 — the solve

`dev/analysis/solve_ladder.luau`. Visual scale first, geometric between the two fixed ends
(`3.60^((tier-1)/9)`, rounded to the 2 dp every existing entry is written at — the old 11-entry
series was itself geometric, ratios 1.10-1.21 with a geometric mean of 1.1372, so this keeps the
ladder's existing character). Then rope, then seat offset, then the distance scale that puts the
perfect-launch landing on the **centre** of the target band, rounded to 4 dp (0.02 studs).

| tier | visual | rope | seat offset | distance scale | distance | landing Z | from band 0 | band | target | margin low | margin high |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 1.00 | 10.00 | 28.524 | **1.0000** | 200.00 | -175.74 | 171.48 | 4 | 4 | 11.48 | 28.52 |
| 2 | 1.15 | 11.50 | 27.664 | 2.6383 | 527.66 | -504.26 | 500.00 | 12 | 12 | 20.00 | 20.00 |
| 3 | 1.33 | 13.30 | 26.631 | 4.2332 | 846.64 | -824.27 | 820.01 | 20 | 20 | 20.01 | 19.99 |
| 4 | 1.53 | 15.30 | 25.484 | 5.8274 | 1165.48 | -1144.26 | 1140.00 | 28 | 28 | 20.00 | 20.00 |
| 5 | 1.77 | 17.70 | 24.108 | 7.4205 | 1484.10 | -1464.25 | 1459.99 | 36 | 36 | 19.99 | 20.01 |
| 6 | 2.04 | 20.40 | 22.559 | 9.0128 | 1802.56 | -1784.26 | 1780.00 | 44 | 44 | 20.00 | 20.00 |
| 7 | 2.35 | 23.50 | 20.781 | 10.6039 | 2120.78 | -2104.26 | 2100.00 | 52 | 52 | 20.00 | 20.00 |
| 8 | 2.71 | 27.10 | 18.716 | 12.1936 | 2438.72 | -2424.26 | 2420.00 | 60 | 60 | 20.00 | 20.00 |
| 9 | 3.12 | 31.20 | 16.364 | 13.7818 | 2756.36 | -2744.26 | 2740.00 | 68 | 68 | 20.00 | 20.00 |
| 10 | 3.60 | 36.00 | 13.611 | **15.3552** | 3071.04 | -3061.69 | 3057.43 | past | past | 17.43 | 22.57 |

**No tier is flagged.** Every solved tier sits dead centre with 20 studs to either boundary. Tier 1
is off-centre (11.48 / 28.52) because its scale is fixed at 1.0000 and cannot be moved — still four
times the 5-stud flag threshold. Tier 10's margins are measured against the platform edge rather
than a band and are shown for completeness.

---

# Step 3 — what was edited

## 3a. The tier-indexed arrays

```lua
-- LaunchConfig.luau
SWING_TIER_DISTANCE_SCALE = { 1.0, 2.6383, 4.2332, 5.8274, 7.4205, 9.0128, 10.6039, 12.1936, 13.7818, 15.3552 },
-- SwingTierVisuals.TIERS[n].scale
                            { 1.00, 1.15,   1.33,   1.53,   1.77,   2.04,   2.35,    2.71,    3.12,    3.60 }
```

Tier 1's entries are byte-identical (`1.0`, `scale = 1.0,`). Tier 10's are old tier 11's,
byte-identical (`15.3552`, `scale = 3.6,`) — including its whole art record, which was moved by
deleting the record above it rather than by rewriting it.

## 3b. The snap-threshold override

`{ 1.90 x9, 1.95 }` — the 1.95 moved from index 11 to index 10. **Read back from the loaded module
by `verify_ladder.luau`, not assumed:** `tier 10 = 1.95, every other tier = 1.90`, and the verifier
fails hard if any entry disagrees. This is the one that fails silently if missed —
`snapThresholdForTier` falls back to the global 1.90 for a missing entry, which would double the
chest window from 0.072 s to 0.144 s with nothing on screen to say so.

## 3c. Prices and targets, indices moved and nothing else

| tier | price | was |
|---|---|---|
| 1-9 | 0 / 100K / 450K / 5M / 20M / 250M / 3B / 6B / 110B | the same, at the same indices |
| 10 | **800B** | old tier 11's price |
| — | — | old tier 10's **260B is deleted** |

Design targets likewise: tiers 2-9 unchanged (6 min / 12 / 24 / 40 / 70 / 3 h / 6 h / 12 h), the
80-hour target moved to tier 10, the 28-hour target deleted with the tier it priced. No number
changed value.

## 3d. Literals and comments

No functional literals existed in `src/` (§1b). 34 comment references naming a tier index whose
meaning changed were updated across `LaunchConfig`, `ShopConfig`, `SwingTierVisuals`, `LaneConfig`,
`PathConfig`, `MoneyFormat`, `TreasureConfig`, `LaunchFormulas`, `LaunchServer`, `MapBuilder`,
`PlayerProfile`, `SwingBuilder`, `BaseClient` and `DevPanelClient`, plus the gallery's hardcoded
count. Where a comment quoted a *measurement* of the top tier (footprint 35.01 studs, the
20.649-stud seat offset, the 0.52 : 1 ring ratio) the measurement was left alone and only the
tier's name changed — those numbers describe the top tier, which is unchanged. One pre-existing
inaccuracy was deliberately **not** corrected: `LaunchConfig`'s flight-duration comment calls the
top tier "14.8x farther" when the array says 15.3552x. It predates this pass and correcting it is
not this pass's business.

## 3e. The luck clamp

`SLIME_LUCK_ANCHOR_HIGH = 120000` -> `1000000`, with the reasoning written into the constant's own
comment block.

## 3f. What raising the clamp did — reported, not fixed

**The distribution is defined out to 1,000,000 and beyond, and it is well-formed there.** Probed
through the real module: at luck 100K / 200K / 500K / 1M / 2M / 10M / 1B the weights sum to
`1.000000000000` with no NaN anywhere, and everything at or above 1,000,000 is bit-identical
(t clamps at `T_MAX = 1.0`). Expected base income per roll at the clamp is `$9.06K`, which is what
the *old* clamped distribution paid at 120,000 — the top of the curve did not change shape, it moved
to require 8.3x more luck to reach.

**The NaN safety floors still hold, and are still not load-bearing.** Each lerp's zero crossing
against `T_MAX = 1.0`:

| lerp | low | high | crosses zero at t | reachable? |
|---|---|---|---|---|
| `spreadDown` | 0.5400 | 0.3780 | 3.3333 | no |
| `spreadUp` | 0.6900 | 0.6400 | 13.8000 | no |
| `shape` | 1.0800 | 0.9000 | 6.0000 | no |

`T_MAX` is unchanged at 1.0 and every crossing is far above it, so `SLIME_SPREAD_FLOOR` and
`SLIME_SHAPE_FLOOR` remain unreachable — exactly the property `SlimeConfig` claims for them. Raising
the anchor did not put them in play; it moved `t` **down** at every real luck value, away from the
crossings, not toward them.

**But the window transitions all moved down the road, and that is the cost.** `t` at a given luck is
now `ln(luck/220) / ln(1000000/220)` instead of `/ ln(120000/220)` — the same log scale stretched
over 8.3x more range, so every luck value maps to a smaller `t` and the window advances more slowly:

| | before (anchor 120,000) | after (anchor 1,000,000) |
|---|---|---|
| window transitions, at band | 0, 27, 40, 56, **64** | 0, **30, 46, 62** |
| windows reachable on the road | Common-Epic ... **Legendary-Divine** | Common-Epic ... **Epic-Secret** |
| `t` at the top of the road (luck 100,000) | 1.0000 (clamped) | **0.7266** (not clamped) |
| E[base income] per roll at band 68 (luck 75,000), no box | $8.87K | **$877** |
| box multiple at band 68 | **1.01x** | **2.55x** |
| E[base income] per roll at band 68, with the box | $8.98K | **$2.23K** |

So: **the dead box is genuinely fixed** — from the top band the chain now needs four doublings to
reach the clamp (P(D >= 4) = 9.15%) where it used to need one, and every band on the road has a live
box. **And the road itself got poorer**: the Legendary-Divine window is no longer reachable by
landing at all, only by doubling into it, and a top-of-road roll is worth about a tenth of what it
was before the box is applied, four times less after. Prices were not rebalanced, by instruction, so
the ladder is now materially more expensive in time than the three prior passes measured. This is
the part the brief expected to need a second pass, and it does.

---

# Step 4 — verification, by reading the edited tree back

`dev/analysis/verify_ladder.luau` loads the arrays the way the game loads them and re-derives every
landing through the real formulas — the distance, the seat, `trajectoryPosition` at `u = 1` and
`bandLuckForLandingZ`. It shares no code with the solver. `LaunchServer.server.luau` is a `.server`
script and cannot be required, so those four formulas are mirrored with their source lines cited at
each use site; everything else (`LaunchConfig`, `SwingTierVisuals`, `SwingGeometry`, `LuckCurve`,
`ShopConfig`, `SlimeConfig`, `SlimeData`, `SlimeRoll`) is required for real through
`dev/rbxshim.luau`.

**Every tier's read-back agrees with the step-2 solve exactly.** No disagreement to explain.

| tier | dist scale | distance | landing Z | from band 0 | band | target | match | pre-box luck | flight (s) | arch | angle |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 1.0000 | 200.00 | -175.74 | 171.48 | 4 | 4 | yes | 25 | 1.8000 | 68.06 | 25.00 |
| 2 | 2.6383 | 527.66 | -504.26 | 500.00 | 12 | 12 | yes | 65 | 2.9237 | 110.55 | 25.00 |
| 3 | 4.2332 | 846.64 | -824.27 | 820.01 | 20 | 20 | yes | 150 | 3.7035 | 140.03 | 25.00 |
| 4 | 5.8274 | 1165.48 | -1144.26 | 1140.00 | 28 | 28 | yes | 550 | 4.3452 | 164.29 | 25.00 |
| 5 | 7.4205 | 1484.10 | -1464.25 | 1459.99 | 36 | 36 | yes | 950 | 4.9033 | 185.40 | 25.00 |
| 6 | 9.0128 | 1802.56 | -1784.26 | 1780.00 | 44 | 44 | yes | 4,500 | 5.4038 | 204.32 | 24.08 |
| 7 | 10.6039 | 2120.78 | -2104.26 | 2100.00 | 52 | 52 | yes | 8,500 | 5.8615 | 221.62 | 22.38 |
| 8 | 12.1936 | 2438.72 | -2424.26 | 2420.00 | 60 | 60 | yes | 35,000 | 6.2855 | 237.66 | 20.99 |
| 9 | 13.7818 | 2756.36 | -2744.26 | 2740.00 | 68 | 68 | yes | 75,000 | 6.6823 | 252.66 | 19.82 |
| 10 | 15.3552 | 3071.04 | -3061.69 | 3057.43 | past | past | yes | — (chest) | 7.0534 | 266.69 | 18.83 |

Flight duration, arch height and launch angle are all computed under the **unchanged** formulas
(`FLIGHT_DURATION_SECONDS = 1.8`, exponent 0.5, `ARC_HEIGHT_SQRT_COEFFICIENT = 4.8125`, pitch clamp
25 degrees). Tier 1's 1.8000 s confirms the normaliser is intact.

**Band steps: 8, every one of them.** 4 -> 12 -> 20 -> 28 -> 36 -> 44 -> 52 -> 60 -> 68, then tier 10
leaves the road. Checked by the verifier, not by eye.

## Roll value at the new clamp

| tier | pre-box luck | E[base]/roll, no box | E[base]/roll, with box | box multiple |
|---|---|---|---|---|
| 1 | 25 | $25.6 | $31.7 | **1.24x** |
| 2 | 65 | $25.8 | $36.7 | **1.42x** |
| 3 | 150 | $26.0 | $45.7 | 1.76x |
| 4 | 550 | $26.2 | $91.0 | 3.47x |
| 5 | 950 | $66.5 | $144 | 2.16x |
| 6 | 4,500 | $67.6 | $322 | 4.77x |
| 7 | 8,500 | $190 | $530 | 2.79x |
| 8 | 35,000 | $193 | $1.31K | 6.81x |
| 9 | 75,000 | $877 | $2.23K | 2.55x |
| 10 | — | chest table, no box on this path | | |

**Two tiers are under the 1.5x floor: tier 1 at 1.24x and tier 2 at 1.42x. Saying it plainly, as
asked — but the reading is not "the clamp fix has not worked".** The fix was aimed at the top of the
road and it worked there: the band that carried a 1.01x box now carries 2.55x, and no band on the
road is dead any more. Tiers 1 and 2 are under the floor for the opposite reason — the anchor
stretch *diluted* low-luck doublings. At luck 25 the first few doublings (25 -> 50 -> 100) no longer
move `t` far enough to cross a window boundary, so the box has almost nothing to buy; before the
change the same doublings covered a larger share of a shorter scale and tier 1 measured 1.53x. This
is the same mechanism as §3f, seen from the bottom of the road instead of the top, and it is a
consequence of the anchor value, not of a mistake in applying it.

**Monotonicity holds.** Expected income per roll is non-decreasing across all 74 band lucks under
the new clamp — worst decreasing step `0.0000e+00`. The verifier treats a failure here as a stop
condition; it did not fire.

## Before and after, per tier

Old figures are from the pre-change baseline artifacts (`dev/out/roll_ev.json`,
`dev/out/nobox_ev.log`), which describe the tree at `e12ca51` and were not regenerated.

| new tier | new band / luck | new E/roll (with box) | old tier | old band / luck | old E/roll |
|---|---|---|---|---|---|
| 1 | 4 / 25 | $31.7 | 1 | 4 / 25 | $39.0 |
| 2 | 12 / 65 | $36.7 | 2 | 14 / 75 | $65.2 |
| 3 | 20 / 150 | $45.7 | 3 | 21 / 200 | $106 |
| 4 | 28 / 550 | $91.0 | 4 | 31 / 700 | $263 |
| 5 | 36 / 950 | $144 | 5 | 40 / 2,500 | $714 |
| 6 | 44 / 4,500 | $322 | 6 | 45 / 5,000 | $1.14K |
| 7 | 52 / 8,500 | $530 | 7 | 53 / 9,000 | $1.92K |
| 8 | 60 / 35,000 | $1.31K | 8 | 57 / 20,000 | $3.34K |
| 9 | 68 / 75,000 | $2.23K | 10 (deleted) | 68 / 75,000 | $8.98K |
| 10 | chest | $33.6K (chest table, unchanged) | 11 | chest | $33.6K |

Roll income is down at every road tier. Most of that is the anchor (§3f), not the respacing: at the
identical band 68 with the identical luck 75,000, the drop is 4.0x and the only thing that changed
is the clamp.

---

# Step 5 — migration

**What 1e found: the clamp already exists and is already correct.** A saved `swingTier` of 11 loads
as 10, does not error, and cannot persist out of range. The minimum safe handling was therefore
*already implemented*; adding a second clamp would have been redundant code pretending to be a fix.
What was missing was the statement that this clamp is now load-bearing for the renumber, so that is
what was added — a comment at `PlayerProfile.applyLoadedData:636-652`, no logic change. No migration
table, no save version, exactly as instructed.

Read back through the live array by the verifier:

| saved value | loads as | note |
|---|---|---|
| 1 | 1 | unchanged |
| 9 | 9 | unchanged |
| 10 | 10 | unchanged |
| **11** | **10** | clamped down to the top tier |
| 12 / 99 | 10 | clamped down to the top tier |
| 0 / -3 | 1 | clamped up to tier 1 |
| 10.7 | 10 | floored, then clamped |

**One accepted consequence, stated because it is a real player-visible effect and nobody should
find it by surprise:** a profile saved at **old tier 10** keeps the number 10 and is therefore
promoted to the new top tier — the chest tier — for free. Nothing in the save distinguishes it from
an old tier 11, and the brief rules out the save version that would be needed to tell them apart.
The alternative would be demoting real purchases, which is worse. Old tier 11 owners keep exactly
the swing they bought.

---

# What this leaves

1. **The three baseline measurement JSONs now describe a tree that no longer exists.**
   `roll_economics.json`, `cycle_economics.json` and `slot_sweep.json` all record commit `e12ca51`
   and were deliberately not regenerated. Every income, dead-time and pricing figure in them is
   pre-change. They remain valid as the *baseline*; they are not valid as a description of this
   branch.

2. **The economy is not balanced for the new clamp, by instruction.** Roll income is down roughly
   2-4x at every road tier while every price is unchanged, so measured progression times will be
   materially longer than the three passes reported. The prices were explicitly out of scope. A
   re-measurement pass against this branch is the obvious next step, and it should re-run
   `roll_ev.luau`, `slot_sim.luau` and `cycle_time.luau` on the new tree before anything is retuned.

3. **Two tiers now have a box worth under 1.5x** (tier 1, 1.24x; tier 2, 1.42x) — the mirror image
   of the problem this pass removed from the top of the road. Whether that matters is a design call:
   a tier-1 player pressing a box that nearly always resolves to the same window is exactly the
   "dead interaction" the mystery box's own comment says it exists to avoid.

4. **The footprint clamp now bites one tier earlier.** `FOOTPRINT_SCALE_MAX = 2.21` caps horizontal
   size; with the respaced scales, tiers 7-10 all measure 35.01 studs wide instead of tiers 8-11
   (measured through the real builder by `dev/run_gallery.luau`). Nothing exceeds the 40-stud lane,
   which is what the clamp exists to guarantee, but the top four swings now differ only in height.

5. **Untouched, as required:** tier 1's scales, the top tier's 15.3552 / 3.60 / 1.95, every price and
   design-target value, `DISTANCE_PER_MULTIPLIER`, `SWEET_SPOT_*`, `SWING_PERIOD_SECONDS`, the flight
   and arch formulas, `RUNWAY_BAND_LENGTH_STUDS`, `RUNWAY_START_Z`, the 74-band curve, the chest
   table and the whole chest landing path, the upgrade curve, `SLOT_COUNT` and the base layout, the
   ping compensation, the box mechanics (`BOX_DOUBLE_CHANCE`, `BOX_PRESS_COOLDOWN_SECONDS`, the
   doubling chain), and `LaunchRewardScene`'s acquire/release structure — that file was not opened
   for editing at all.

# Files

**Edited (gameplay):** `LaunchConfig.luau` (both tier arrays + comments), `SwingTierVisuals.luau`
(8 respaced scales, one record deleted, comments), `ShopConfig.luau` (price array, target list,
comments), `SlimeConfig.luau` (`SLIME_LUCK_ANCHOR_HIGH`), `PlayerProfile.luau` (comment only),
and comment-only changes in `LaneConfig`, `PathConfig`, `MoneyFormat`, `TreasureConfig`,
`LaunchFormulas`, `LaunchServer`, `MapBuilder`, `SwingBuilder`, `BaseClient`, `DevPanelClient`.

**Edited (dev tooling):** `gallery/SwingGallery.server.luau` — hardcoded `TIER_COUNT = 11` now
derived from the array.

**Created:** `dev/analysis/solve_ladder.luau`, `dev/analysis/verify_ladder.luau`,
`dev/analysis/clamp_effect.luau`, and their logs in `dev/out/`.
