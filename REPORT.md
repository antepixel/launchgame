# Five small items

**Branch `ladder-renumber`. Started from `2ef9fc1967659d1e4a1775a95c060398fc51244e`** (the tip of the
Divine-ladder pass) with a clean tree — nothing needed committing first.

Five commits, one per item, in the order the brief set:

| # | commit | item |
|---|---|---|
| 1 | `f7ccc38` | the wrong Divine weighted-mean figure in `REPORT.md` |
| 2 | `06bafed` | assert on `SLIME_TIER_WEIGHT_RATIO` |
| 3 | `ce8df5f` | assert on `SLOT_COUNT` |
| 4 | `22595c3` | `FLIGHT_DURATION_EXPONENT` 0.5 -> 0.35 |
| 5 | `eeacd4a` | the `GetNetworkPing` probe (dev-only, not run in this pass) |

Any one reverts alone with `git revert <hash>`. Nothing here touched the roll distribution, the
ladder, or any price; no JSON in `dev/out/` was regenerated.

**One item deviates from its brief and the deviation is argued, not slipped in: item 5 is NOT behind
the `IsStudio()` gate**, because that gate is a hard early return and would make the probe
unrunnable in the only environment where it can be measured. §5b has the reasoning and the one-line
change to reverse it.

## Reproduce every number

```
lune run dev/analysis/flight_pacing.luau     # item 4: the before/after tables
lune run dev/analysis/verify_divine.luau     # unchanged, re-run to confirm items 2-3 broke nothing
lune run dev/run_gallery.luau                # loads BaseGeometry through the real builder (item 3)
```

All from the repo root, deterministic. Measured at **`eeacd4a`**.

---

# Item 1 — the wrong figure in the report

**Confirmed wrong, and the correct figure is $158,157.57.** Computed three independent ways before
touching the prose:

| check | result |
|---|---|
| `sum(income_i * share_i)` over the eight shipped incomes at the 1.40 ratio | **$158,157.5669** |
| the sum of §3g's own "conditional contribution" column | **$158,157.5669** — identical |
| consistency with band 68: pre-box P(Divine) x the mean shift, added to the old figure | 0.0434044 x $12,532.57 = **$543.97**; $8,872 + $544 = **$9,415.97** against the reported $9,416 |

The old prose said $195,485 and a 1.34x rise. The rise over the old uniform mean ($145,625) is
**1.086x**. Had $195,485 been right, band 68 would have come out at $11,036, not the $9,416 that was
measured and reported — which is the check that settles it.

**One extra number in the same sentence was also wrong and is corrected:** it said Divine is "only
4.6% of that band's mass". 4.6% is the WITH-box P(Divine) at tier 9 (4.5562%); the pre-box figure
the sentence needs is **4.340%**. Left alone it would have been an inconsistency inside the very
sentence being fixed, so it moved too — the brief's own "measured: 4.340%" is what it now reads.

Prose only. No code, no data, no JSON: everything downstream of the figure was already right.

---

# Item 2 — an assert on `SLIME_TIER_WEIGHT_RATIO`

Two asserts in `SlimeData.luau`, beside the income and colour ones and in the same message format:

- **Length**, outside the per-tier loop, because a per-tier check cannot see a table that is too
  *long* — an entry at index 9 of an 8-tier ladder would never be read and never be noticed.
- **Every entry a number >= 1.0**, inside the loop with the others. `>= 1.0` because the semantics
  only run one way: the ratio makes each step *up* a tier's income ladder rarer
  (`weight_i = ratio ^ -(i - 1)`), so a value below 1 silently inverts it and makes the best slime in
  a tier the most common.

**Confirmed to fire, by loading `SlimeData` against deliberately broken copies of the config rather
than by reading the code:**

| broken config | result |
|---|---|
| 7-entry array | `SlimeConfig.SLIME_TIER_WEIGHT_RATIO has 7 entries, expected 8 to match SLIME_TIER_NAMES` |
| Divine set to 0.8 | `SlimeConfig.SLIME_TIER_WEIGHT_RATIO[8] (Divine) is 0.8, expected a number >= 1.0` |
| Divine set to `"x"` | `SlimeConfig.SLIME_TIER_WEIGHT_RATIO[8] (Divine) is x, expected a number >= 1.0` |

`SlimeConfig.luau` was restored byte-identical afterwards (`git diff --exit-code` clean).

The runtime fallback in `pickSlimeInTier` is untouched, as instructed — the assert catches the
config error at load, the fallback stays as defence in depth.

**One thing beyond the letter of the item, because it sat two lines above the change:** the comment
over `slimesByTier` still said *"every slime within a tier is equally likely"*, which stopped being
true one pass ago. It now records that the list's ascending-income order is load-bearing for the
weighting.

---

# Item 3 — an assert on `SLOT_COUNT`

## 3a. The derivation, from the constants as they stand

```
row r's pads are centred at  BASE_SLOT_Z_START + r * BASE_SLOT_ROW_SPACING_STUDS
their far edge is that       + BASE_SLOT_PAD_SIZE.Z / 2
the plot's back boundary is  min(BASE_PLOT_CENTER_Z + BASE_MAT_SIZE.Z/2,
                                 BASE_BACK_EDGE_Z  - BASE_BACK_EDGE_SIZE.Z/2)
```

| quantity | value |
|---|---|
| first row centre | 117.00 |
| row pitch | 14.00 |
| pad half-depth | 4.00 |
| mat far edge | 192.00 |
| back edge part, near face | **191.50** |
| binding limit | **191.50 — the back edge part**, 0.5 studs tighter than the mat |

`r <= (191.5 - 117 - 4) / 14 = 5.0357`, so `r_max = 5`, so **6 rows x 2 columns = 12 slots**.

**The figure is 12, as the earlier pass found** — but the binding constraint is the back edge part
rather than the mat itself, which the earlier pass recorded as "the mat's far edge at 192". Half a
stud, no consequence for the answer, and the assert now names whichever of the two actually binds
rather than asserting which one it will be.

Row by row, to show where it breaks: rows 0-5 (slots 1-12) reach Z 121, 135, 149, 163, 177, 191 —
all inside 191.5. Row 6 (slots 13-14) reaches **205, thirteen and a half studs past the boundary**,
out over the grass with the edge part through it.

## 3b. The assert

In `BaseGeometry`, which is where the layout lives, re-deriving all of the above from the constants
rather than hardcoding 12. Its message names the count, the maximum, the row layout, the offending
row's actual reach, the limit, and which boundary binds:

```
BaseConfig.SLOT_COUNT is 13, but the plot holds at most 12 (6 rows of 2): row 6's pads
would reach Z 205.0 against a back limit of 191.5 (the back edge part). Move
BASE_SLOT_Z_START, BASE_SLOT_ROW_SPACING_STUDS, BASE_GRID_COLUMNS or the mat before
raising it.
```

Confirmed by loading `BaseGeometry` against edited configs: **10 and 12 load; 13, 14 and 20 refuse.**

## 3c. The derivation at the point of change

Written onto `SLOT_COUNT` itself in `BaseConfig`, so someone raising it reads the ceiling there
rather than discovering it at load. It also records what does *not* block a raise — the save is a
positional array sized from the constant and tolerates a shorter one on load, and the pad name
format (`Slot%02d`) is good to 99 — so the geometry is identified as the only real obstacle.

`SLOT_COUNT`'s value is unchanged at 10.

---

# Item 4 — `FLIGHT_DURATION_EXPONENT` 0.5 -> 0.35

**Shipped.** 4c and 4d both came back clean; the reasoning is below, and it was checked before the
constant moved rather than after.

The "old" columns recompute the same formula at the previous exponent, so both columns come out of
the same code and can differ only by the exponent. Note these are the *current* ladder's distances,
so tiers 2-9 differ from `cycle_economics.json`'s figures (which predate the renumber); tier 1 and
the top tier match it exactly, their distances being unchanged.

## 4a. Flight duration and speed

| tier | distance | flight old | flight new | change | studs/s old | studs/s new |
|---|---|---|---|---|---|---|
| 1 | 200.00 | 1.8000 | **1.8000** | +0.00% | 111.1 | 111.1 |
| 2 | 527.66 | 2.9237 | 2.5278 | -13.54% | 180.5 | 208.7 |
| 3 | 846.64 | 3.7035 | 2.9827 | -19.46% | 228.6 | 283.9 |
| 4 | 1165.48 | 4.3452 | 3.3357 | -23.23% | 268.2 | 349.4 |
| 5 | 1484.10 | 4.9033 | 3.6301 | -25.97% | 302.7 | 408.8 |
| 6 | 1802.56 | 5.4038 | 3.8857 | -28.09% | 333.6 | 463.9 |
| 7 | 2120.78 | 5.8615 | 4.1133 | -29.83% | 361.8 | 515.6 |
| 8 | 2438.72 | 6.2855 | 4.3194 | -31.28% | 388.0 | 564.6 |
| 9 | 2756.36 | 6.6823 | 4.5085 | -32.53% | 412.5 | 611.4 |
| 10 | 3071.04 | 7.0534 | **4.6823** | -33.62% | 435.4 | 655.9 |

The top tier lands at **4.68 s**, matching the prediction. Tier 1 is unchanged to the last digit —
its distance *is* `baseDistance`, so the ratio is 1 and no exponent can move it.

## 4b. Cycle time and launches per minute, perfect play

Phases held fixed from `cycle_economics.json` (bar 1.20 s, reward 2.00 s box / 3.35 s chest, return
0.25 s); only the flight term moves. Those phases carry that pass's assumptions — perfect play hits
the sweet spot on the first pass, and the walk speed is Roblox's default 16, which this repo never
configures.

| tier | cycle old | cycle new | change | launches/min old | new | gain |
|---|---|---|---|---|---|---|
| 1 | 5.25 | 5.25 | +0.00% | 11.43 | 11.43 | +0.00% |
| 2 | 6.37 | 5.98 | -6.21% | 9.41 | 10.04 | +6.62% |
| 3 | 7.15 | 6.43 | -10.08% | 8.39 | 9.33 | +11.20% |
| 4 | 7.80 | 6.79 | -12.95% | 7.70 | 8.84 | +14.88% |
| 5 | 8.35 | 7.08 | -15.24% | 7.18 | 8.47 | +17.98% |
| 6 | 8.85 | 7.34 | -17.15% | 6.78 | 8.18 | +20.69% |
| 7 | 9.31 | 7.56 | -18.77% | 6.44 | 7.93 | +23.11% |
| 8 | 9.74 | 7.77 | -20.20% | 6.16 | 7.72 | +25.31% |
| 9 | 10.13 | 7.96 | -21.45% | 5.92 | 7.54 | +27.31% |
| 10 | 11.85 | **9.48** | -20.00% | 5.06 | **6.33** | +25.01% |

The flight's share of the cycle at the top tier falls from **59.5% to 49.4%**; at tier 9, from 66.0%
to 56.6%. Buying a tier still slows each roll — tier 10's cycle is 9.48 s against tier 1's 5.25 s —
but by 1.81x rather than 2.26x.

## 4c. Frame-rate dependence in landing — none, and it is structural

**A faster flight cannot land a player on a different band than a slower one from the same release.**

The landing is not integrated over frames. `onRelease` computes
`trajectoryPosition(startPosition, distance, archHeight, 1)` **once, at release** — a closed form in
which `u = 1` is a literal, with no time, no elapsed, and no frame term — and immediately resolves
`bandLuckForLandingZ(landingPosition.Z)`, storing the luck and the zone on the flight record. So the
band and the `short`/`road`/`past` branch are decided before the first frame of flight exists.

The Heartbeat handler's only use of duration is `u = (now - flight.startTime) / flight.duration`
compared against 1 — a decision about *when* to place the character, not *where*. When it fires, it
places at that same precomputed `u = 1` point. Measured at both exponents, all ten tiers: landing Z
identical to four decimals, band identical.

The one thing that does change is the wall clock: a shorter flight ends sooner, and the placement
still happens up to one Heartbeat (~16 ms at 60 fps) after `u` crosses 1, exactly as before. That
timing slack is unchanged by the exponent and does not touch position. At the shortest flight in the
game (tier 1, 1.8 s, unchanged) that is still ~108 frames, so there is no degenerate zero-frame case.

## 4d. Everything that reads flight duration

| reader | what it does | scales? |
|---|---|---|
| `LaunchServer` Heartbeat landing check | `u = (now - startTime) / flight.duration` against 1 | yes — reads the per-flight stored value, not the constant |
| `pivot:SetAttribute("FlightDuration", duration)` -> `LaunchRemoteLanes:160-194` | renders OTHER players' flights from the attribute | yes — same `u` formula, and it already rejects `duration <= 0` |
| `flightStartedRemote` -> `LaunchClient:978, :1318` | this client's own render loop | yes — `u = clamp((now - startTime) / flightDuration, 0, 1)` |
| flight trail | `Trail.Lifetime` is `visual.trailLifetime`, a per-tier constant; destroyed at landing and on cancellation | no duration term — a shorter flight simply draws a shorter ribbon |
| release/chase camera | `releaseCameraPullback` is a function of **distance**; framing is set once at release | no duration term |
| death / disconnect cancellation | `clearActiveRider` drops the flight and destroys the trail | no duration term, no timeout keyed to it |

**Nothing assumes a duration range.** The closest thing to an assumption is a comment on
`OUTCOME_RAINBOW_CYCLES_PER_SECOND`, which reasons that the outcome word is on screen for "the
flight plus RESET_DELAY -- a few seconds -- so 0.6 gives it two or three visible sweeps". At the top
tier that goes from ~4.2 sweeps to ~2.8, and tier 1 is unchanged — still inside the "two or three"
the comment is aiming at. Cosmetic, no change made.

---

# Item 5 — the `GetNetworkPing` probe

Added, **not run** — it needs a published place and a human.

## 5a. What it measures, and how many samples

It times the **`RidingAssigned` -> `RiderReady` handshake** that every mount already performs, and
logs the interval beside `Player:GetNetworkPing()` on the same connection, with the running mean of
both and their ratio:

```
[PingProbe] Ante sample 7/20: round trip 121.4ms, GetNetworkPing 62.1ms | means: trip 118.9ms, ping 60.4ms, RATIO 1.969
```

**Twenty samples.** Ping jitters by tens of milliseconds against a 60-150 ms signal, and the mean's
standard error falls as `1/sqrt(n)`, so 20 cuts it by ~4.5x — ample for a question whose two
candidate answers are a *factor of two* apart. It costs nothing to collect: one sample per mount, so
20 arrive within a few minutes of ordinary play with no special procedure.

**Deviation from the brief's stated mechanism, and why.** §5a asks for a `RemoteFunction:InvokeClient`
round trip; §5b asks for "no new remote if an existing one can carry it". Those pull opposite ways
and I followed 5b, because the existing handshake carries it and `InvokeClient` costs two things
worth avoiding: a new remote living in a published place, and a server thread parked on a client's
willingness to answer (an unanswered `InvokeClient` yields indefinitely). The price of reusing the
handshake is that the measured interval includes the client's own handling of `RidingAssigned`
(`setMounted`/`setGrounded`, a few UI property writes) before it acks — so the figure is an **upper
bound** on round-trip time. A few milliseconds of UI work cannot move a ratio that is either ~1 or
~2, so it does not affect the answer; if a precise RTT is ever wanted for its own sake, that is when
the dedicated remote earns its cost.

## 5b. The gate — and the one place this pass departs from its brief

**The probe is behind the allowlist (`DevConfig.ALLOWLISTED_USER_IDS`, the same list and the same
`table.find` check `DevPanelServer` uses) and deliberately NOT behind `RunService:IsStudio()`.**

The brief says "the same allowlist/IsStudio path DevPanelServer already uses". Reading that path
first is what turned up the conflict: `DevPanelServer`'s Gate 1 is a **hard early return** —

```lua
if not RunService:IsStudio() then
	return
end
```

— placed above everything else in the file, deliberately, so that in a published server the dev
remotes are never created at all. `DevPanelClient` and `LaunchServer`'s dev bindable do the same.
There is no allowlist-only path anywhere in the tree to reuse.

So the two halves of item 5 cannot both hold: behind `IsStudio()` the probe can only run in Studio,
where the brief's own reasoning says the measurement is undefined (a local test client has ~0 ping,
so the ratio is 0/0). Shipping it fully gated would mean shipping something that can never produce
the number it exists to produce.

What tips the decision is what the probe actually is. It creates **no remote**, changes **no
behaviour** for anyone, and the allowlist gates only whether a `print` happens. The worst a
non-allowlisted player can do is nothing; the worst an allowlisted one can do is delay their own ack
and corrupt their own log line. That is a very different object from the dev panel's money-granting
remote, and the `IsStudio()` gate exists for the latter.

**To reverse this** — if you would rather have a probe that cannot run than a log line in
production — wrap the `devPingProbeEnabled` body in the same check:

```lua
local function devPingProbeEnabled(player: Player): boolean
	return RunService:IsStudio() and table.find(DevConfig.ALLOWLISTED_USER_IDS, player.UserId) ~= nil
end
```

One line, and `git revert eeacd4a` removes the probe entirely.

## 5c. The removal marker

`TODO: REMOVE BEFORE LAUNCH` appears on all four pieces — the `DevConfig` require, the per-player
state beside the other per-player tables, the cleanup line in `clearActiveRider`, and the probe
block itself — each pointing at the dev panel so the whole thing leaves in one sweep. Searching
`PingProbe` finds every piece.

## 5d. The run procedure

1. **Add your UserId** to `DevConfig.ALLOWLISTED_USER_IDS` if it is not already there (it currently
   holds one entry) and publish the place.
2. **Join the published place** — not Studio, and not a local server. The measurement needs real
   latency; a Studio client reads ~0 ms and the ratio is meaningless.
3. **Mount the swing twenty times.** Any ordinary play does this: walk into the swing, launch, come
   back, walk in again. Each mount emits one line to the **server** output (View -> Output with the
   server context selected, or the Developer Console's Server tab, F9).
4. **Read the RATIO on the line marked `<-- STABLE`** (sample 20). Earlier lines show the running
   mean converging; the marked one is where it is worth trusting.

What the answer means:

| ratio | reading | consequence |
|---|---|---|
| **~2.0** | `GetNetworkPing` reports **one-way** time | The current code and its comment are correct. `releasePingCompensationSeconds` rewinds by the right amount and nothing needs changing. |
| **~1.0** | `GetNetworkPing` reports **round-trip** time | The rewind is **twice** what it should be. A 60 ms player is over-compensated by ~30 ms — biased the wrong way by 42% of the top tier's 0.072 s snap half-window. The fix would be halving the value before the clamp, and the 0.12 s clamp itself would want re-deriving against one-way rather than round-trip latency. |
| anything else | the handshake's client-side work is not negligible after all | Re-measure with a dedicated `RemoteFunction`, accepting the costs in 5a. |

**Nothing was changed in the grading path**: `releasePingCompensationSeconds`,
`RELEASE_PING_COMPENSATION_MAX_SECONDS` and the release phase math are untouched. The fix, if the
ratio says one is needed, is a later decision informed by the number.

---

# What this leaves

1. **Item 4 shifted the cycle times the economy passes measured.** `cycle_economics.json` and
   everything joined to it (`slot_sweep.json`'s minutes, the dead-time totals) are now optimistic by
   6-27% on cycle length at tiers 2-10. Those JSONs describe `e12ca51` and were deliberately not
   regenerated; a re-measurement of cycle time against this branch is outstanding, and item 4 is one
   more reason for it.
2. **The `GetNetworkPing` question is open until someone runs the probe** (§5d). Until then the
   compensation is correct-or-doubled and nobody knows which.
3. **The item-5 gating decision is yours to confirm.** It is the one place this pass did not do what
   its brief literally said, the reasoning is in §5b, and the reversal is one line.
4. **Untouched, as required:** `SlimeRoll.luau` entirely, `SLIME_INCOME_BY_TIER`, the ratio values,
   `SLIME_TIER_COUNTS`, all four luck/extrapolation constants, the spreads, the shape, the chest
   constants and landing path, the whole ladder and its prices, the 74-band curve,
   `FLIGHT_DURATION_SECONDS`, `ARC_HEIGHT_SQRT_COEFFICIENT`, `MAX_FLIGHT_PITCH`,
   `DISTANCE_PER_MULTIPLIER`, every `SWEET_SPOT_*`, `SWING_PERIOD_SECONDS`,
   `releasePingCompensationSeconds` and its clamp, `SLOT_COUNT`'s value, the upgrade curve, the base
   layout geometry, the box mechanics, `LaunchRewardScene.luau` (not opened), and every file in
   `dev/out/`.

# Files

| item | files |
|---|---|
| 1 | `REPORT.md` (prose only, superseded by this report) |
| 2 | `src/ReplicatedStorage/Config/SlimeData.luau` |
| 3 | `src/ReplicatedStorage/Config/BaseGeometry.luau`, `src/ReplicatedStorage/Config/BaseConfig.luau` |
| 4 | `src/ReplicatedStorage/Config/LaunchConfig.luau`; new `dev/analysis/flight_pacing.luau` and its log |
| 5 | `src/ServerScriptService/LaunchServer.server.luau` |
