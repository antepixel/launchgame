# Accumulate-and-collect, offline earnings, and one-second-per-tier flights

**Branch `ladder-renumber`. Started from `e419ac77dd87ec1fbf7708cf767b36cfce2241ac`.**

A note on that hash, since the brief said to start from `735e246`: `e419ac7` *is* `735e246` plus
the previous pass's STEP 0 report, and it changed `REPORT.md` and nothing else
(`git diff --stat 735e246 e419ac7` → `REPORT.md | 666 +++---`). So the code this pass started from
is byte-identical to `735e246`. The tree was clean; nothing needed committing first.

Eight commits, one per step, each independently revertable:

| step | commit | what |
|---|---|---|
| 1 | `7f36dbf` | flight duration keys off tier index — tier N flies N + 1 s |
| 2 | `880b956` | the return collect pad on the approach link |
| 3b | `9443827` | income accrues into a pending pot instead of cash |
| 3c | `d1986bb` | the tick pays for elapsed time, not the nominal interval |
| 4 | `b76582b` | offline accrual on load |
| 5 | `0a55ed8` | all eleven pads wired to bank the pot on touch |
| 6 | `a5e542f` | pad label, "while you were away" line, HUD readout |
| 7 | `1c8c337` | verification, and the refactor that made it real |

## Reproduce every number

```
lune run dev/analysis/flight_tier_pacing.luau   # step 1: 1a, 1c, 1e, 1f
lune run dev/analysis/verify_offline.luau       # step 7: 7a-7h, exits non-zero on failure
lune run dev/analysis/verify_ladder.luau        # unchanged, re-run to confirm step 1 broke nothing
rojo build default.project.json -o <path>       # whole-tree syntax check, run after every step
```

All from the repo root, deterministic. Nothing in `dev/out/` was regenerated or touched.

## Two things to read before anything else

**1. The brief contradicted itself about where the pad goes, and the geometry settled it — but not
at the Z either clause named.** §2 has the measurement. Short version: the post-flight walk is
**four studs, not 22**, because auto-mount fires at Z 48. The pad is at Z 46–54.

**2. One thing I could not verify and you should check in Studio.** §7i. Everything else in step 7
is measured or read off the source.

---

# 1. Flight duration becomes one second per tier

## 1a — the exponent form really cannot do this

Verified before implementing, as asked, and **my numbers agree with the brief exactly**, so no stop.

Fitting the exponent through *both* endpoints (2 s at tier 1, 11 s at tier 10) is a solve, not a
search: `2 · s₁₀^e = 11` → `e = ln(5.5) / ln(15.3552)` = **0.624117**.

| tier | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| want | 2.00 | 3.00 | 4.00 | 5.00 | 6.00 | 7.00 | 8.00 | 9.00 | 10.00 | 11.00 |
| power law | 2.00 | 3.66 | 4.92 | **6.01** | 6.99 | 7.89 | 8.73 | 9.53 | 10.28 | 11.00 |
| error | 0.00 | +0.66 | +0.92 | **+1.01** | +0.99 | +0.89 | +0.73 | +0.53 | +0.28 | 0.00 |

Worst deviation **+1.0086 s at tier 4** — a fifth of that tier's intended flight, in the middle of
the ladder where most buying happens.

**The cause is structural, and worth recording because it rules out retuning rather than just this
fit.** `SWING_TIER_DISTANCE_SCALE` is solved so each tier lands on an evenly spaced *band*, which
makes distance very nearly linear in tier. Any power of a near-linear sequence is a curve, and the
target is a straight line. No exponent fixes that; only a linear function does. And once the
function is linear in tier, routing it through distance buys nothing — hence
`BASE + tier * PER_TIER`, both `1.0`.

## 1b — what happened to the two old constants

**Both `FLIGHT_DURATION_SECONDS` and `FLIGHT_DURATION_EXPONENT` are DELETED** — from the
`LaunchConfig` type export and from the table. Not left in place unread. `grep` for either name
across `--include=*.luau` now returns only prose in comments explaining what was removed.

That is the answer the brief asked for, but the interesting half is what else read them. **Five
files did**, all in `dev/analysis/`, and leaving them broken was not an option:

| file | was | now |
|---|---|---|
| `cycle_time.luau:125,453` | inlined the formula, wrote both constants into the JSON | `C.flightDurationForTier(tier)`; JSON keys renamed to the new pair |
| `slot_sim.luau:364` | inlined the formula | `C.flightDurationForTier(tier)` |
| `slot_sim_v2.luau:370` | inlined the formula | `C.flightDurationForTier(tier)` |
| `verify_ladder.luau:105` | inlined the formula | `C.flightDurationForTier(tier)` |
| `flight_pacing.luau:31,35,44` | *is* the 0.5→0.35 comparison | carries both as locals marked historical |

Four of them now go through one new mirror, `common.flightDurationForTier`, so there is a single
copy of the live formula in that directory instead of five. `flight_pacing.luau` is the exception on
purpose: it exists to document the *previous* pass's change, so it keeps the retired values as its
own locals and still reproduces `dev/out/flight_pacing.log` byte for byte. Its header now says
loudly that neither constant is live and points at the new script.

Three now-dead locals were removed with them (`BASE_DISTANCE` in `verify_ladder`, `baseDistance` and
a `facts` that lost its only use in both `slot_sim` files).

**One stale comment fixed, not left:** `ARC_HEIGHT_SQRT_COEFFICIENT` reasoned that the square root
"matches `FLIGHT_DURATION_EXPONENT` (0.5)". That pairing is gone — height is still √distance while
time is now linear in tier — so the comment now states the real consequence: time grows 11× up the
ladder against the arch's 3.9×, so high-tier flights trace a **flatter, longer** arc, which reads as
a cruise. The coefficient itself is untouched.

## 1c — the landing is unaffected, confirmed per tier

`trajectoryPosition` is `z = startPosition.Z - distance * u`. **There is no time term in it at
all**, and `onRelease` calls it once with `u = 1` as a literal and resolves `bandLuckForLandingZ`
immediately — so the band and zone are decided before the first frame of flight exists. Duration
only decides *when* the Heartbeat loop places the character.

Evaluated at both durations for all ten tiers. Identical, not merely close:

| tier | flight old | flight new | landing Z (both) | band (both) | zone |
|---|---|---|---|---|---|
| 1 | 1.8000 | 2.0000 | −175.7358 | 4 | road |
| 2 | 2.5278 | 3.0000 | −504.2561 | 12 | road |
| 3 | 2.9827 | 4.0000 | −824.2686 | 20 | road |
| 4 | 3.3357 | 5.0000 | −1144.2557 | 28 | road |
| 5 | 3.6301 | 6.0000 | −1464.2523 | 36 | road |
| 6 | 3.8857 | 7.0000 | −1784.2610 | 44 | road |
| 7 | 4.1133 | 8.0000 | −2104.2590 | 52 | road |
| 8 | 4.3194 | 9.0000 | −2424.2639 | 60 | road |
| 9 | 4.5085 | 10.0000 | −2744.2556 | 68 | road |
| 10 | 4.6823 | 11.0000 | −3061.6888 | 76 | past |

`verify_ladder.luau` independently re-derives every landing from the real config and still reports
**VERIFY PASSED** — every tier on its solved target band, every band step exactly 8.

What *did* change is the rate the curve is traversed at. At a fixed 1.0 s after release a tier-10
flight is now at Z −269.83 where it used to be at −646.53. Same curve, different clock.

## 1d — every duration reader re-checked

All six, plus one the brief did not list. **Nothing assumes an upper bound**; every consumer divides
by the duration rather than comparing against a constant.

| # | reader | how it uses duration | scales? |
|---|---|---|---|
| 1 | `LaunchServer` Heartbeat landing check `:2267` | `u = (now - startTime) / flight.duration` | yes |
| 2 | `FlightDuration` attribute → `LaunchRemoteLanes:194` | same ratio, plus a `duration <= 0` type guard and a deliberate reject of `u < 0 or u >= 1` | yes |
| 3 | `flightStartedRemote` → `LaunchClient:978`, `:1318` | `math.clamp(elapsed / flightDuration, 0, 1)` | yes |
| 4 | flight trail | **does not read duration at all** — `Trail.Lifetime` is a per-tier `SwingTierVisuals` constant; attached at release, destroyed at landing | n/a |
| 5 | release/chase camera | **does not read duration** — one-shot framing at `LaunchClient:1029-1031` from `releaseCameraPullback(startZ, distance)`, then handed back to the Custom camera. No tween | n/a |
| 6 | death/disconnect cancellation `clearActiveRider:1151` | event-driven; removes the flight from `activeFlights` so the Heartbeat never fires for it. No timer | yes |
| 7 | `RIDER_READY_TIMEOUT_SECONDS = 15` (not in the brief's list) | armed at **mount**, not at release, and self-invalidates once `riderReadyFlags[player]` is set | unaffected |

**Two consequences of the 2.35× longer top flight that are worth naming rather than burying:**

- **The trail ribbon gets shorter at high tiers.** Its length is `Lifetime × speed`, `Lifetime` is
  fixed per tier, and top-tier speed drops from 656 to 279 studs/s. The tier-10 ribbon is now about
  43% of its former length. Not a bug — the flight reads as a cruise rather than a streak — but if
  the top tiers' trails look thin, `SwingTierVisuals.trailLifetime` is the dial, not the duration.
- **The mid-flight cancellation window is 2.35× wider.** Death and disconnect during flight are
  handled identically, just exercised more often.

## 1e — the rainbow sweeps, reported not changed

`OUTCOME_RAINBOW_CYCLES_PER_SECOND` stays at 0.6. Its comment reasons about "the flight plus
`RESET_DELAY` — a few seconds — so 0.6 gives it two or three visible sweeps." On screen time is
`flight + 0.75`:

| tier | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| sweeps old | 1.53 | 1.97 | 2.24 | 2.45 | 2.63 | 2.78 | 2.92 | 3.04 | 3.16 | 3.26 |
| **sweeps new** | 1.65 | 2.25 | 2.85 | 3.45 | 4.05 | 4.65 | 5.25 | 5.85 | 6.45 | **7.05** |

**Flagged:** the comment's stated design range ("two or three") now holds only up to tier 3. At tier
10 the word cycles the full spectrum seven times. Whether that reads as celebratory or as a
distraction is a taste call that wants eyes on it, not arithmetic. If it needs fixing, 0.25 would
restore ~2.9 sweeps at the top — but it would drop tier 1 to 0.7, i.e. not even one full sweep, so
the honest fix is probably to key the rate off the tier the same way the duration now is. Out of
scope this pass.

## 1f — the full before/after table, perfect play

Phases held fixed from `cycle_economics.json`: bar 1.20, reward 2.00 box / 3.35 chest, return 0.25.
Tier 10 is the chest landing (`zone == "past"`); every other tier is a box.

| tier | distance | flight old | flight new | Δ | st/s old | st/s new | cycle old | cycle new | l/min old | l/min new | flight share |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 200.0 | 1.8000 | 2.0000 | +11.1% | 111.1 | 100.0 | 5.25 | **5.45** | 11.43 | 11.01 | 34.3% → 36.7% |
| 2 | 527.7 | 2.5278 | 3.0000 | +18.7% | 208.7 | 175.9 | 5.98 | 6.45 | 10.04 | 9.30 | 42.3% → 46.5% |
| 3 | 846.6 | 2.9827 | 4.0000 | +34.1% | 283.9 | 211.7 | 6.43 | 7.45 | 9.33 | 8.05 | 46.4% → 53.7% |
| 4 | 1165.5 | 3.3357 | 5.0000 | +49.9% | 349.4 | 233.1 | 6.79 | 8.45 | 8.84 | 7.10 | 49.2% → 59.2% |
| 5 | 1484.1 | 3.6301 | 6.0000 | +65.3% | 408.8 | 247.3 | 7.08 | 9.45 | 8.47 | 6.35 | 51.3% → 63.5% |
| 6 | 1802.6 | 3.8857 | 7.0000 | +80.1% | 463.9 | 257.5 | 7.34 | 10.45 | 8.18 | 5.74 | 53.0% → 67.0% |
| 7 | 2120.8 | 4.1133 | 8.0000 | +94.5% | 515.6 | 265.1 | 7.56 | 11.45 | 7.93 | 5.24 | 54.4% → 69.9% |
| 8 | 2438.7 | 4.3194 | 9.0000 | +108.4% | 564.6 | 271.0 | 7.77 | 12.45 | 7.72 | 4.82 | 55.6% → 72.3% |
| 9 | 2756.4 | 4.5085 | 10.0000 | +121.8% | 611.4 | 275.6 | 7.96 | 13.45 | 7.54 | 4.46 | 56.6% → 74.3% |
| 10 | 3071.0 | 4.6823 | 11.0000 | +134.9% | 655.9 | 279.2 | 9.48 | **15.80** | 6.33 | **3.80** | 49.4% → 69.6% |

**Both of the brief's expected figures land exactly: 5.25 → 5.45 at tier 1, 9.48 → 15.80 at tier 10,
launches/min 6.33 → 3.80.**

**One consequence the brief did not ask about but which follows directly, and which I think is the
real thing to watch:** speed still rises with tier, but it now *flattens out* — 100 st/s at tier 1
climbing to 279 at tier 10, with the increments collapsing along the way (tier 1→2 gains 76 st/s;
tier 9→10 gains 3.6). The old form climbed to 656 and was still gaining 44 st/s at the top. Under
that curve a bigger tier read as more powerful largely *through speed*; that read now comes almost
entirely from **duration and distance** instead. Consistent with the stated intent — the flight is
the thing worth watching, and a cruise shows more of it — but it is a different feel, not just a
longer one.

**And one genuine loss, stated plainly.** Duration no longer varies with the release. A worst
release (`WORST_MULTIPLIER` 0.75 vs `SWEET_SPOT_MULTIPLIER` 2.0) covers 0.375× the ground in the
*same* seconds, so its speed ratio drops from 0.529× to 0.375× — the "whiffed release is a slow
drift" effect roughly doubles. At tier 10 a badly timed launch is now an 11-second drift covering
1,152 studs. I think that is defensible (a whiff *should* read as underpowered) and it is the direct
price of even spacing, so I have not deviated. If it needs softening, the fix is a mild distance term
multiplying the tier-keyed result — not a return to the exponent.

## 1g — what is now stale

**`dev/out/cycle_economics.json` and everything joined to it are stale. Not regenerated, as
instructed.**

It is stale on **three** counts, not one: it was measured at `e12ca51` against an **eleven-tier**
ladder, at exponent **0.5** (not even the 0.35 that shipped after it), and now against a
tier-keyed duration. Its `gitCommit` field still reads `e12ca51`, and `cycle_time.luau` refuses to
run against a mismatched join, so it cannot be regenerated by accident.

Measured against the **current** ladder, the cycle grows by:

| tier | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| cycle Δ | +3.8% | +7.9% | +15.8% | +24.5% | +33.5% | +42.5% | +51.4% | +60.2% | **+69.0%** | +66.6% |

**Any figure expressed per unit of real time is therefore overstated by up to 69%** — launches per
minute, income per real minute, the re-max drain rates in `slot_sim`/`slot_sim_v2`, and every
`deadTimeMinutes` figure. The *distribution* figures (`roll_economics_v2.json`, expected value per
roll, the slime tables) are untouched: nothing in this pass changed what a roll pays, only how often
one happens.

---

# 2. The return pad, and the brief's two conflicting placements

## The contradiction, and how I resolved it

2a says two incompatible things:

> Place it on the approach link **between Z 52 (the return position) and Z 67** […] The player is
> pivoted to Z 52 facing −Z and walks 22 studs to the swing at Z 30, **so the pad must sit ON that
> 22-stud walk, not beyond it.**

Z 52→67 is *behind* a player who faces −Z and walks toward Z 30. Those are opposite directions.
Putting the pad at 52–67 would have made collecting a **backwards detour**, which is precisely what
option 1 exists to avoid — and it would have failed 2b, 7g and the "zero seconds" requirement, all
of which state the walk. **The walk wins**; the `[52, 67]` clause is the error.

## But the walk is four studs, not 22

`checkProximityMounts` (`LaunchServer.server.luau:2248`) seats a grounded player the instant their
**horizontal** distance from the pivot reaches `SWING_MOUNT_RADIUS_STUDS`:

```lua
local horizontalOffset = Vector2.new(rootPart.Position.X - pivotPosition.X, rootPart.Position.Z - pivotPosition.Z)
if horizontalOffset.Magnitude <= LaunchConfig.SWING_MOUNT_RADIUS_STUDS then
```

The return position shares the pivot's X exactly (both `laneCenterX`), so that distance is pure Z.
Pivot at Z 30, radius 18 → **auto-mount fires at Z 48**. The player is placed at Z 52 and is seated
four studs later. They never walk to the swing at all.

This is not incidental — `SWING_RETURN_CLEARANCE_STUDS`' own comment says it exists to clear that
radius ("22 > 18"). The 22 studs in the brief is the *clearance*, not a walk.

**Consequence:** the pad had to be centred on a 4-stud window, and a pad placed anywhere in
`[52, 67]` would have been touched by a player exactly never.

## 2a/2b — the placement, and the overlap

`BaseGeometry.returnPadPlacement(laneIndex)`. Nothing is a literal; all three axes derive from
constants that already decide where the player goes:

- **Z**: centred on `(returnZ + mountZ) / 2` = **50**, depth `(returnZ - mountZ) + 2 × margin` = **8**
  → spans **Z 46–54**.
- **X**: `laneCenterX` (deliberately *not* `baseLaneCenterX` — this pad is on the swing side; the two
  agree today but mean different things). Width `APPROACH_LINK_WIDTH - 2 × 0.5` = **8** of the link's 9.
- **Y**: the approach link's own top face, computed — `groundY + 0.15 + 0.15 + 0.2` = **groundY + 0.5**.

Measured across all six lanes:

```
player is placed at Z 52.0, auto-mounts at Z 48.0 -> the walk is 4.0 studs
pad Z 46.0-54.0 vs walk 48.0-52.0; pad is 8.0 wide against a 9.0-wide approach link
lane 0..5: the pad is centred on the walk line's own X          PASS
lane 0..5: the pad covers the ENTIRE 4.0-stud walk (overlap 4.0) PASS
```

**Overlap is 4.0 studs of a 4.0-stud walk — 100%, with 2 studs of margin past each end.** The
forward margin covers the landing spot itself (a player who never takes a step is still standing on
it); the rear margin continues past the mount boundary so a fast walker cannot tunnel across it
between two touch samples.

**Walkable there, and clear of the conveyor**, both asserted at module load rather than checked once
by hand: the approach link spans Z 34–67 (`PathConfig.APPROACH_LINK_START_Z`/`_END_Z`) so 46–54 sits
comfortably inside it, and the conveyor's near edge is at Z 67 (`BACK_WALKWAY_Z 76 − SIZE.Z/2 9`),
13 studs clear. `BaseGeometry` fails the load with a specific message if either ever stops holding.

## 2c/2d/2e — construction, name, keying

**Parented to the base folder** (`Base_<UserId>`), built in `buildBaseFolder`, which runs
synchronously at join before the DataStore read even starts. So it exists for a player with zero
slimes placed — the stranded-pot fix from the last pass's §3. It still cannot outlive its owner:
`onPlayerRemoving` destroys the whole folder exactly as before.

*Rejected:* a static per-lane part in `MapBlockout` beside the slot pads. It would have matched how
the rest of the map's dressing is built, but this pad has an **owner** in a way a slot pad does not,
so it would have needed re-keying on every lane reuse and clearing on every leave. The per-player
folder gives both for free.

**Named `ReturnCollectPad`**, distinct from the ten `CollectPad`s (which are told apart only by
parent). The collect handler wires both by name; the world label goes above this one only.

**Keyed per-player** by parent (the owner's folder) and **per-lane** by position
(`returnPadPlacement(profile.baseIndex)` — the same index that places their base and their swing).

**On "one construction path, not two":** I built it in the same module, in the same idiom, from the
same shared constants (`BASE_COLLECT_PAD_HEIGHT_STUDS`/`_COLOR`/`_MATERIAL`,
`GROUND_TOP_SURFACE`) — but I did **not** factor out a shared builder with `spawnSlimeVisual`.
MUST NOT CHANGE lists the ten pads' "position, size, colour, parent, **construction**. Additive
only." A shared helper would have rewritten their construction to produce a byte-identical result,
and with playtesting out of scope I could not prove the equivalence I would have been asserting.
Flagging the tension rather than silently picking: if you want the refactor, it is about fifteen
lines and I would do it as its own commit.

**Sizing differs from the ten deliberately**: they are 4 wide because they sit *beside* a walk and
are stepped onto on purpose; this one sits *across* a walk and must not be missed by a player who
drifts a stud off centre, so it is 8 of the corridor's 9.

---

# 3. The pending pot

**3a** — `OFFLINE_CAP_SECONDS = 28800` and `OFFLINE_RATE_MULTIPLIER = 1.0`, in `BaseConfig` beside
`BASE_INCOME_TICK_SECONDS`. Both carry the "expected to be retuned after real player data" note and
the self-scaling argument: offline income is a multiple of *the player's own current rate*, the same
`totalIncomePerSecond` the online tick uses, so eight hours away pays exactly what eight hours
present would. It can refund time; it cannot outrun progression. An empty base earns nothing from a
week away.

**3b** — the tick's destination moved from `profile.money` to `profile.pendingIncome`. The rate
calculation is untouched.

**3d — not spendable, and this is now enforced by a test rather than asserted.** The two balance
checks found in the last pass's §0f are the only ones in the project, and `verify_offline.luau`
reads them out of the source (comments stripped, so commented-out code cannot pass):

```
[PASS] upgradeSlime gates on banked cash only (`profile.money < cost`)
[PASS] upgradeSlime never reads pendingIncome
[PASS] buyNextTier gates on banked cash only (`profile.money < price`)
[PASS] buyNextTier never reads pendingIncome
[PASS] no spendableMoney() helper exists to sum the two buckets
[PASS] exactly one site moves the pot into cash (collectPending)
```

All eleven money sites re-checked by inspection: the tick (now writes the pot), `sellFromInventory`
(+cash, no check), `upgradeSlime` (−cash, **checks cash**), `buyNextTier` (−cash, **checks cash**),
`applyLoadedData`, `buildBaseFolder`, the post-load replication, the three dev-panel writers, and
`toSaveShape`. Nothing sums the two. `devWipeProfile` now also zeroes the pot — a wipe that left it
would have the player collect the pre-wipe base's earnings moments later.

**3e** — persisted in `toSaveShape`. Clamped `> 0` on load, so a corrupt or hand-edited negative
cannot silently eat the next collect (NaN also fails `> 0` and lands on 0).

**3f** — replicated as a `PendingIncome` attribute on the base folder, exactly as `Money` is. No new
remote. One writer, `setPending`, so the field and the attribute cannot drift.

## 3c — the interval bug, measured

Its own commit (`d1986bb`), separate from `9443827`.

The loop credited `rate × BASE_INCOME_TICK_SECONDS` — the *nominal* interval — while `task.wait(n)`
resumes on the first Heartbeat **at or after** the deadline. Every tick dropped the overshoot, and
dropped more of it the busier the server was.

Measured over 30 ticks on a 60fps-equivalent scheduler, both accounting schemes run over the **same
ticks**:

```
wall clock       30.2631 s   -> owed $3026.31
BEFORE (nominal) credited $3000.00   short by $26.31  (0.8695%)
AFTER  (elapsed) credited $3026.31   short by $0.00  (0.0000%)

mean actual tick 1.007085 s  (overshoot +0.007085 s)
worst actual tick 1.016865 s (overshoot +0.016865 s)
over an hour at this drift, BEFORE loses 31.3 seconds of income
```

**0.87% of all idle income, ~31 seconds per hour online**, and worse under load. Fixed with an
`os.clock()` delta — monotonic, so it cannot jump backwards or be resynced mid-interval the way a
wall clock can. **Deliberately unclamped**: a 10-second hitch credits 10 seconds, which is correct;
the player *was* online and their slimes *were* earning. Clamping would reintroduce the same
under-payment at a higher threshold.

One accepted imprecision, unchanged from before: a player joining midway through an interval is paid
for the whole of it. Bounded by one tick, always in the player's favour, not worth a per-profile
timestamp.

---

# 4. Offline accrual

**4a — `lastSeen`, written unconditionally in `toSaveShape` from `os.time()`.** Every save is a
moment the player was demonstrably present, so the periodic autosave, the leave-save and the
shutdown save all stamp it.

**`sessionHeartbeat` is not reused, and `PlayerStore.luau` is untouched.** It is a session *lock*,
and `PlayerStore.save` nils it whenever `releasingSession` is true — i.e. on the single most common
exit path, a clean leave. Reusing it would credit **zero to every player who logged off normally and
pay only the ones who crashed**. Exactly backwards.

**4b — the 120 s bound is already met; no new save loop added.** `AUTO_SAVE_INTERVAL_SECONDS = 120`
(`PersistenceConfig.luau:27`), driving the existing loop at `PlayerProfile.luau`. A hard crash skips
both `PlayerRemoving` and `BindToClose`, so the last periodic save is all that survives and
`lastSeen` is at most 120 seconds stale. **That staleness is always in the player's favour** — an
older `lastSeen` means a *longer* computed absence, so a crash can only ever over-credit by up to two
minutes of the player's own rate, never under-credit.

**4c** — credits `elapsed × totalIncomePerSecond(profile) × OFFLINE_RATE_MULTIPLIER`, calling the
existing `totalIncomePerSecond` directly. Added to any saved pot, never replacing it.

**4d — the ordering, exactly as placed.** In `onPlayerAdded`'s load task:

```lua
local data, ok = PlayerStore.load(player.UserId)
if profiles[player] ~= profile then return end          -- player already left
if not ok then baseFolder:SetAttribute("SaveDisabled", true) return end   -- 4g: never reaches accrual
applyLoadedData(profile, data)      -- populates slots and levels
creditOfflineIncome(profile, data)  -- reads them, via totalIncomePerSecond
profile.canSave = true
```

`creditOfflineIncome` is **after** `applyLoadedData`. Reversed, `profile.slots` and `profile.levels`
are still empty tables, the rate is zero, and the player is silently credited nothing — no error, no
warning. Both lines carry a comment saying so.

**This required moving `totalIncomePerSecond` up the file**, from beside the income tick (line 1296)
to above `setPending` (line 665). A `local function` is only in scope *below* its own definition, so
a reference from `onPlayerAdded` at line 1061 would have resolved to a **nil global** rather than to
it — a runtime error on the first join, not a subtle bug, but worth naming since it is the kind of
thing that looks like a no-op move.

**4e** — nil `lastSeen` credits **zero**, handled explicitly. `data.lastSeen or 0` would have treated
the epoch as the last seen time and handed **every existing player the full cap** on their first join
after this update. Tested.

**4f** — negative elapsed clamps to zero via `math.clamp(now - lastSeen, 0, CAP)`. This is not
paranoia: `os.time()` is each machine's wall clock, and a save on one server loaded on another
running seconds behind produces a genuine negative. Unclamped it would *subtract* from a pot the
player legitimately earned before logging off. Tested at 1 s, 60 s, 1 h and 10× the cap of future
skew.

**4g** — a failed load credits zero, by structure: the `not ok` branch returns before either line
above. Belt and braces, such a session also has an empty base, so its rate is zero — tested.

**4h** — `offlineCredit` tracks this session's credit apart from the pot, and is **never persisted**
(it describes this arrival; a save carrying it would re-announce a credit already shown). Cleared by
the first collect, together with the pot, in one call.

---

# 5. Collecting

**5a** — all eleven pads, one handler, **`Touched`**. A `ProximityPrompt` is the established pattern
here (the treasure chest uses one) and is the wrong one: it costs a keypress and a hold, and the
entire point of option 1 is that collection costs *nothing* on a walk already being made. This is
the first `.Touched` in `src/`.

The ten per-slot pads are wired **without modifying `spawnSlimeVisual`**: `wireCollectPads` connects
`DescendantAdded` on the base folder and matches by name, so pads created lazily — one per slime,
possibly hours after the join — opt in for free. A one-shot pass over the folder would have caught
only the return pad.

**5b/5c — the guard, and there are two of them, independent.**

1. **The payout is atomic.** It reads the pot, zeroes it, and credits cash with **no yield in
   between** (nothing between the capture and the write yields — verified line by line). So a second
   fire finds an empty pot and pays nothing. **Double-payment is impossible by construction, not by
   timing.**
2. **A debounce window of `BASE_INCOME_TICK_SECONDS`** — derived, not picked: exactly long enough
   that at most one tick's income can accumulate between two collects, so a lingering player banks
   whole ticks rather than slivers. Stored as `lastCollectAt` **on the profile**, so it dies with the
   profile and needs no cleanup.

*Rejected:* a boolean flag reset by `task.delay` — needs the scheduler and leaks a pending timer if
the player leaves inside the window.

Simulated over a realistic per-limb burst (see 7b): **7 handler fires, 1 payout, exactly the pot
banked.** With the debounce removed the atomic zero alone still yields exactly 1 payout, which is the
independence claim tested directly.

**5d** — collecting zero returns silently. A player crosses this pad on every return trip and an
empty pot is the *normal* case, not an error worth feedback.

**5e — server-authoritative, and I want to be precise about what the distance check does and does
not do.** The server reads the amount from `profile.pendingIncome`; there is no remote, so a client
cannot name a figure, request an amount, or reach another player's pot. Only the owner's own
character can trigger a pad (`hit:IsDescendantOf(player.Character)`) — without that, any player
crossing someone else's return pad would bank it for them and fire their "while you were away" line
while they were elsewhere.

**Tolerance: the touched pad's own half-diagonal + 6 studs, horizontal only.** That is 11.66 studs
for the 8×8 return pad and 10.47 for a 4×8 slot pad — it adapts rather than assuming one pad shape.
Horizontal because the root sits above the tile by a hip height that varies with the avatar's rig, so
a 3D check would be measuring body type. *Rejected:* a tight ~2-stud tolerance, which would reject
legitimate collects from a player crossing at walking speed for no gain.

**What it is not:** the position it validates is the character's own, which is client-owned, and it
is the same position that produced the `Touched`. So it does **not** stop a modified client
teleporting onto a pad — nothing server-side short of rejecting client physics could. It is a guard
against a stale or desynced touch firing when the player is demonstrably nowhere near. That is
enough here because **collecting has no exploit value**: it moves the player's own already-earned
money from one of their own buckets to another, at a rate they already earned it. There is nothing to
gain by collecting from the wrong place, only by earning more, which this path cannot do.

**5f — confirmed, not assumed.** `grep -rn "CanTouch" src/` returns exactly one assignment in the
whole tree, `LaunchRewardScene.luau:817`, on the mystery box's cube. Neither pad kind ever writes it,
so both keep `Instance.new`'s default of **true**. Both are `Anchored` with `CanCollide = false`,
which does not affect `Touched` — it is an overlap event, not a collision response.

---

# 6. UI

Pure attribute rendering in `BaseClient.client.luau`, matching its existing no-remote pattern: two
new `GetAttributeChangedSignal` connections and nothing written per frame (**6d**). The server writes
`PendingIncome`/`OfflineCredit` only when they change — once per income tick, once per collect.

**6a** — a `BillboardGui` on the return pad reading `Collect $X` through `MoneyFormat`, hidden at
zero (the label is an invitation; there is nothing to invite when the pot is empty — the pad itself
stays visible). `BillboardGui` is this codebase's convention for labels floating *in the air*
(slot nametags, upgrade strips, the box's luck readout); `SurfaceGui` is for text painted *on*
geometry (the sign board, band numbers, slot pad numbers).

Carries all three settings the nametags learned the hard way: **`MaxDistance = 40`** (same as the
nametags), **`AlwaysOnTop = false`**, **no stroke**. A `BillboardGui`'s `Size` is in screen pixels
and so holds constant size at every distance — that is exactly what put "a grey band on the horizon"
when the base sign was one of these, and `MaxDistance` is the clamp that stops six lanes' worth of
labels doing it again. `StudsOffset` is 6 studs so a player standing *on* the pad does not have the
label inside their own character.

**The ten per-slot pads are left bare, as instructed** — `BaseConfig.luau`'s argument against
labelling them still holds (they already carry a slime nametag and an upgrade button strip
overhead). The return pad is alone on an empty stretch of approach link, so one label there reverses
nothing.

**6b** — a second line above it, `$X while you were away`, `Visible` only while `OfflineCredit > 0`.
It disappears on its own with nothing client-side to time or remember, because `collectPending`
clears the pot and the credit together in one call.

**6c** — a fourth 30 px line at −170, continuing the stack (money at 0, tier at −110, save warning at
−140). Dimmer green than the money readout: close enough to read as money, far enough not to be
mistaken for the balance. Always visible including at $0 — hiding it would make the stack jump on
every collect.

**Both traps handled explicitly on every new label**: `BorderSizePixel = 0` (a transparent
*background* does not clear the *border* — separate render pass) and `TextStrokeTransparency` set
rather than left at its visible default. The three pre-existing labels in that file carry deliberate
non-zero strokes for contrast against the 3D world and are untouched.

If the pad ever fails to appear the client warns and degrades to no label; collection still works,
since it is entirely server-side.

---

# 7. Verification

`lune run dev/analysis/verify_offline.luau` — **VERIFY PASSED**, exits non-zero on any failure.

**The refactor that made this real, and why it is in the step-7 commit.** The accrual arithmetic
started inside `PlayerProfile.creditOfflineIncome`, which cannot be loaded outside the game —
`PlayerProfile` requires `Players`, `HttpService`, a DataStore-backed `PlayerStore` and a built
`Workspace.MapBlockout` at module scope. Anything left there could only ever be checked against a
*mirror*, which is exactly the failure mode `common.luau`'s own header warns about ("If LaunchServer's
flight math changes, this file goes stale and nothing will warn you"). So the three decisions that
actually matter — what a missing timestamp credits, what a backwards clock credits, what happens at
the cap — moved to `src/ReplicatedStorage/Config/OfflineIncome.luau`, beside the two constants they
read. That is the same arrangement `SlimeUpgrade.luau` has with `SlimeUpgradeConfig.luau`. **The
tests now exercise the real module.**

**7a — the pot is not spendable.** Method: source-level extraction of both balance-check bodies with
comments stripped, asserting each gates on banked cash and never mentions the pot, plus assertions
that no `spendableMoney` helper exists and that exactly one site moves the pot into cash. Output
quoted in §3 above. This is a regression guard, not a one-time claim: the single change that would
break the property now fails a test.

I could not attempt a literal in-game purchase (playtesting is out of scope), so this is inspection —
but it is *mechanised* inspection over the real file, which is stronger than a reading.

**7b — no double-collect.** Method: **modelled, and flagged as the one mirrored thing in the file**,
because `Touched` is an engine event. The model transcribes `collectPending`'s guard sequence.

```
one step across the pad: handler fired 7 times, 1 payout(s), banked $100.0000
  [PASS] the handler really did fire 7 times (a burst, as Touched does)
  [PASS] exactly ONE payout resulted
  [PASS] exactly the pot was banked, not a multiple of it
  [PASS] with the debounce removed, the atomic zero alone still yields one payout
loitering 5 s at 4 touches/s: fired 21 times, 6 payout(s)
  [PASS] a loitering player banks at most about one payout per income tick
```

**7 fires, 1 payout.** A loitering player gets ~1 payout per income tick, not per touch.

**7c — offline credit.** Method: the real `OfflineIncome.creditFor` against a representative
10-slime mixed-level profile (3720.36 $/s).

| absence | paid for | expected | actual |
|---|---|---|---|
| 1 hour | 3600 s | $13,393,309.50 | $13,393,309.50 |
| exactly the cap (28800 s) | 28800 s | $107,146,476.00 | $107,146,476.00 |
| 3× the cap (86400 s) | 28800 s | $107,146,476.00 | $107,146,476.00 |
| 1 s under the cap | 28799 s | $107,142,755.64 | $107,142,755.64 |
| 1 s over the cap | 28800 s | $107,146,476.00 | $107,146,476.00 |

Both cap boundaries tested, not just the cap.

**7d — new profile and failed load credit zero.** nil `lastSeen` → 0; explicitly *not* the full cap,
which is what the epoch reading would have paid; a string `lastSeen` → 0; a NaN `lastSeen` → 0
(NaN survives `math.clamp` unchanged, so it is caught by name); a failed load's empty profile → 0
even at the full cap.

**7e — rejoining immediately.** 0 s → $0.00 exactly; 1 s → one second's income; 2 s → two seconds'.
No duplicate of the previous session.

**7f — offline rate equals the online rate.** The strong form is structural: there is exactly **one**
`totalIncomePerSecond` and both the tick and the accrual call it — neither re-derives the sum, so
they cannot diverge. What is measurable is that nothing between that rate and the pot rescales it:

```
online tick of 1.00 s credits $3720.363750
offline span of 1.00 s credits $3720.363750
  [PASS] offline and online pay the identical amount for the identical span
  [PASS] OFFLINE_RATE_MULTIPLIER is 1.0, so nothing discounts offline time
```

Plus self-scaling: a rate of 0 credits 0 at the full cap, and credit scales linearly with the
player's own rate.

**7g — the return pad is on the walk line.** Method: the real `BaseGeometry.returnPadPlacement`
across all six lanes, against the walk line derived from the real `LaneConfig`/`LaunchConfig`.
**Overlap 4.0 studs of a 4.0-stud walk on every lane**, pad centred on the walk's own X, 8 wide in a
9-wide corridor, clear of the conveyor. **Detour: 0 studs, 0 seconds** — the player walks the same
line whether or not they collect.

**7h — cycle time changed only by the step 1 flight term.** Method: for each tier, assert
`newCycle − oldCycle == newFlight − oldFlight` exactly. **All ten tiers pass to within 1e-9.**

| tier | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| cycle new | 5.45 | 6.45 | 7.45 | 8.45 | 9.45 | 10.45 | 11.45 | 12.45 | 13.45 | 15.80 |
| Δ = flight Δ | 0.2000 | 0.4722 | 1.0173 | 1.6643 | 2.3699 | 3.1143 | 3.8867 | 4.6806 | 5.4915 | 6.3177 |

**Steps 2–6 added no term to the loop.** The return pad costs zero seconds, which is the entire point
of option 1.

## 7i — the one thing I could not verify

**Does `Touched` fire for a player who is teleported onto the pad and then stands perfectly still?**

The player is `PivotTo`'d to Z 52, which is *inside* the pad's 46–54 footprint, and then unanchored.
Roblox fires `Touched` when parts begin overlapping, and any movement at all — the walk to Z 48, or
just the idle animation's limb motion — generates touch events, so in practice this is how every
step-on-a-pad mechanic in Roblox behaves and I expect it to work. But a teleport *into* an existing
overlap on an anchored, non-colliding part is the one case I would want to see with my own eyes, and
playtesting was out of scope.

**Why the risk is small even if it does not fire on the teleport:** the pad extends two studs past
the mount boundary, so the player crosses a *moving* contact on the way to Z 48 regardless. The only
way to miss it entirely is to be returned and then never move at all before mounting — and not
moving means not mounting, so they stay on the pad with the pot visible above them.

**If it turns out to need help**, the in-scope fix is a `Region3`/`GetPartBoundsInBox` sweep in the
existing income tick as a backstop; I did not add one because step 5a specified `Touched` and an
unrequested second mechanism is worse than a flagged unknown.

---

# 8. Decisions where I chose, one line each

| decision | chose | rejected |
|---|---|---|
| pad Z | centred on the real 4-stud walk window, Z 46–54 | the brief's Z 52–67, which sits behind a player walking −Z and would never be touched |
| pad parent | the per-player base folder | a static `MapBlockout` lane part, which would outlive its owner and need re-keying |
| pad width | 8 of the corridor's 9, sized to be unmissable | matching the slot pads' 4, which a player drifting off centre could walk past |
| debounce | `lastCollectAt` timestamp on the profile, window = `BASE_INCOME_TICK_SECONDS` | a boolean reset by `task.delay`, which leaks a timer if the player leaves inside the window |
| distance tolerance | touched pad's half-diagonal + 6 studs, horizontal | a tight ~2 studs, which would reject legitimate walking collects for no gain |
| retired constants | deleted from `LaunchConfig`, five `dev/analysis` readers updated | leaving them in place unread, which the brief forbade |
| shared pad builder | none — additive only | refactoring `spawnSlimeVisual`, whose construction is in MUST NOT CHANGE |
| accrual arithmetic | own Config module, testable | leaving it in `PlayerProfile`, where it could only be mirror-tested |
| hitch handling | credit the full elapsed time | clamping, which reintroduces the under-payment 3c fixes |

---

# 9. What I did not touch

Per MUST NOT CHANGE, verified: the ten collect pads (position, size, colour, parent and construction
all untouched — the diff for `spawnSlimeVisual` is empty); `PlayerStore.luau` entirely, including
`sessionJobId`, `sessionHeartbeat` and the lock; `SlimeRoll.luau` — not opened; the chest table and
landing path; the whole ladder and every price — `verify_ladder.luau` re-run and **PASSED**, with its
one pre-existing warning (tier 9's 0.613× box multiple) unchanged; the upgrade curve, `MAX_LEVEL`,
`SLOT_COUNT`, `BASE_SLOT_*` and the plot geometry; `DISTANCE_PER_MULTIPLIER`, every `SWEET_SPOT_*`,
`SWING_PERIOD_SECONDS`, `ARC_HEIGHT_SQRT_COEFFICIENT` (value untouched; one stale comment corrected),
`MAX_FLIGHT_PITCH`, the trajectory and arch formulas, the ping compensation, `moveToLaneReturn`,
`SWING_RETURN_CLEARANCE_STUDS`, the box mechanics; `LaunchRewardScene.luau` — not opened (the two
`grep` hits cited above come from repo-wide pattern searches, not a read); **every file in
`dev/out/`** — nothing regenerated, nothing edited.

No gamepass, no doubling reward, no group-join button, no monetisation. The levelling-discovery
problem is untouched. `start_playtest`/`stop_playtest` were never called.
