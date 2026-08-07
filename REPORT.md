# Roll distribution: NaN safety floors

**What was done:** two named floor constants added to `SlimeConfig`, applied with `math.max`
to the three interpolated shape values in `SlimeRoll.distributionForLuck`. Two files.

**Effect on the game today: none.** Maximum deviation from the previous behaviour across
2,000,000 log-spaced luck values is **0.000e+00**, and the floors bind at **0** of those
points.

**Verification:** computed from the live modules loaded through `dev/rbxshim.luau` under Lune.
No playtest was run (none was permitted).

---

## Correction to the premise, before anything else

The task states the NaN failure is *"reachable from the top band through a 22-doubling box
chain at roughly 1 in 515,253… across a real player base it will happen."*

**That is not the case today, and I should have been clearer about it in the previous report.**
The 1-in-515,253 figure appeared there under the heading *"Raising it is currently unsafe"* —
it was the reachability of that luck value **conditional on `T_MAX` being raised or removed**.
It is not the probability of the failure occurring as the code stands.

`SLIME_EXTRAPOLATION_T_MAX = 1.0` clamps `t` before any lerp crosses zero. The earliest
crossing is `spreadDown` at **t = 3.333**. No luck value — no matter how long the box chain —
can produce a `t` above 1.0, because the clamp is applied to `t` directly, after the log
mapping and before the lerps. Confirmed by scanning the live module over 2,000,000 luck values
from 1e-4 to 1e12: **no NaN observed anywhere.**

So the hazard is **latent, not live**. No player can hit it. Nobody has hit it.

That does not make the fix pointless, and I have done it — you said it stands on its own
merits and it does, but the merit is different from the one stated. What it actually buys:

- **`T_MAX` stops being load-bearing for safety.** Right now one constant is silently doing
  two unrelated jobs: bounding the *shape* of the curve (a design decision) and preventing a
  NaN (a correctness guard). Anyone who later raises `T_MAX` for a design reason — which is
  exactly what the previous report flagged as a live question — reintroduces a
  guaranteed-Divine failure with no warning. After this change, `T_MAX` is a curve decision
  only.
- **The failure mode is the worst possible kind.** Silent, and maximally generous. Not a
  crash, not an error in the log: every roll returns Divine and the economy is destroyed
  quietly. Guarding a failure with that shape is worth doing even at low probability.

If you were budgeting this work against a believed 1-in-515,253 live incident rate, the real
rate is zero and you may want to re-rank it. It is done either way; it was cheap.

---

## The change

### `src/ReplicatedStorage/Config/SlimeConfig.luau`

| constant | value |
|---|---|
| `SLIME_SPREAD_FLOOR` | **0.05** |
| `SLIME_SHAPE_FLOOR` | **0.10** |

Both added to the exported `SlimeConfig` type as well as the table.

### `src/ServerScriptService/SlimeRoll.luau`

```lua
local spreadDown = math.max(lerp(...SPREAD_DOWN_LOW, ...SPREAD_DOWN_HIGH, t), SlimeConfig.SLIME_SPREAD_FLOOR)
local spreadUp   = math.max(lerp(...SPREAD_UP_LOW,   ...SPREAD_UP_HIGH,   t), SlimeConfig.SLIME_SPREAD_FLOOR)
local shape      = math.max(lerp(...SHAPE_LOW,       ...SHAPE_HIGH,       t), SlimeConfig.SLIME_SHAPE_FLOOR)
```

Three lines changed. `peakOffset` is not floored: it is a position, not a divisor or an
exponent, and both its LOW and HIGH are 1.0, so it is constant and cannot degenerate.

Nothing else changed. The six spread/shape constants retuned in the previous pass, `T_MAX`,
`T_MIN`, the window width, the window start pair, the peak offset, both luck anchors, the
weight formula, the normalisation and `rollTier` are all untouched.

---

## Margin: what the curve actually reaches

Minimum values reached across the **entire allowed `t` range** `[-0.5, 1.0]`:

| value | minimum reached | at t | floor | **margin** |
|---|---|---|---|---|
| `spreadDown` | 0.3780 | 1.000 | 0.05 | **7.6x** |
| `spreadUp` | 0.6400 | 1.000 | 0.05 | **12.8x** |
| `shape` | 0.9000 | 1.000 | 0.10 | **9.0x** |

All three minima occur at `t = 1.0`, i.e. at `T_MAX`, which is where the curve is most
concentrated. The floors sit an order of magnitude below.

The floors are also chosen to be above the point where the *shape* degenerates, not merely
above zero:

- A spread of 0.05 puts the nearest off-peak tier at `exp(-(1/0.05)^0.1) ≈ 0.22` of the peak,
  so a floored window is still a four-tier window rather than a single spike.
- A shape of 0.10 keeps the exponent positive, so weights still decay with distance instead of
  inverting.

A floored distribution would be an odd-looking distribution. It would not be a broken one.

---

## Verification

### 1. The distribution is unchanged everywhere it is reachable

Compared the pre-fix maths against the live post-fix module over **2,000,000 log-spaced luck
values from 1e-4 to 1e12** — which spans the whole of `t ≤ 1.0`, i.e. everything reachable:

| metric | result |
|---|---|
| **maximum deviation** | **0.000e+00** |
| grid points where any floor bound | **0** |
| NaN anywhere in the new module | **false** |

Not "within tolerance" — bit-identical, because `math.max` returns its argument unchanged when
the floor does not bind, and the floor never binds.

The "before" reference is a reimplementation of the pre-fix maths that was proven
bit-identical to the pre-fix live module over the same 2,000,000 values (max abs deviation
0.000e+00) **before** the edit was applied, so it is a valid baseline now that the real module
has changed.

### 2. Monotonicity still holds

Same scan, same 2,000,000 points:

- **decreasing steps: 0**
- worst step: 0.00000000%
- **+2 tail range: 2.49% – 4.47%** (inside the stated 1–5% rule)

Swing-tier expected income, identical to the previous pass to every digit reported:

| tier | post-box luck | E[income] | delta |
|---|---|---|---|
| 1 | 70 | 25.73 | — |
| 2 | 187 | 25.99 | +1.00% |
| 3 | 583 | 66.44 | +155.62% |
| 4 | 1,750 | 67.40 | +1.44% |
| 5 | 5,833 | 191.46 | +184.09% |
| 6 | 11,665 | 867.17 | +352.92% |
| 7 | 22,164 | 884.06 | +1.95% |
| 8 | 58,326 | 8,772.23 | +892.27% |
| 9 | 116,653 | 9,050.53 | +3.17% |
| 10 | 186,645 | 9,062.13 | +0.13% |
| 11 | 233,306 | 9,062.13 | 0.00% |

All deltas through tier 10 strictly positive. The 10→11 zero is the `T_MAX` clamp, unchanged
and out of scope as before.

### 3. NaN immunity in the region the floors exist for

`t` forced past `T_MAX` to exercise the crossings directly:

| t | spreadDown | spreadUp | shape | unfloored | floored |
|---|---|---|---|---|---|
| 3.30 | 0.0054 | 0.5250 | 0.4860 | ok | ok, sums to 1.000000 |
| **3.34** | **−0.0011** | 0.5230 | 0.4788 | **NaN — all rolls Divine** | ok, sums to 1.000000 |
| 4.00 | −0.1080 | 0.4900 | 0.3600 | **NaN — all rolls Divine** | ok, sums to 1.000000 |
| 6.00 | −0.4320 | 0.3900 | −0.0000 | **NaN — all rolls Divine** | ok, sums to 1.000000 |
| 10.0 | −1.0800 | 0.1900 | −0.7200 | **NaN — all rolls Divine** | ok, sums to 1.000000 |
| 20.0 | −2.7000 | −0.3100 | −2.5200 | **NaN — all rolls Divine** | ok, sums to 1.000000 |
| 100 | −15.66 | −4.3100 | −16.92 | **NaN — all rolls Divine** | ok, sums to 1.000000 |
| 1e6 | −161,999 | −49,999 | −179,999 | **NaN — all rolls Divine** | ok, sums to 1.000000 |

The floored column stays a valid normalised distribution at every value of `t`, including ones
no configuration could plausibly produce. `T_MAX` can now be set to anything without
reintroducing this class of failure.

---

## Analysis only, not changed: `rollTier`'s `return #weights` fallback

```lua
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
```

### What it currently does

Two distinct situations reach that last line, and the comment only describes one of them.

1. **The intended case.** Weights are valid and sum to 1, but floating-point rounding leaves
   `cumulative` a few ULPs below `roll` on the final iteration. Returning the last tier is
   exactly right: it is the tier that owns that sliver of probability. This is a real
   possibility and the guard is correct for it.
2. **The unintended case.** A weight is NaN. Every `roll <= cumulative` comparison against NaN
   is false, so the loop completes without returning, and the function reports the **last
   tier — Divine — with certainty.** The guard silently converts "the distribution is broken"
   into "the player won the best item in the game."

The comment asserts the second case away (*"cumulative reaches 1 by construction"*), which was
true of the construction as written and is exactly the kind of assumption that stops being
true when a constant moves.

### Should it detect a non-finite weight and fail loudly?

**My recommendation: yes, but not as an error — as a `warn` plus a safe fallback, and only
after this floor fix is in.** Reasoning below; I have not changed it.

**Option A — leave it as is.**

- *Risk:* a NaN is indistinguishable from a legitimate rounding fall-through. If one ever
  occurs it is silent, permanent for as long as the bad config is live, and maximally
  generous. Nobody notices until the economy is visibly wrong, and the cause is several layers
  from the symptom.
- *Mitigation now in place:* with the floors, `distributionForLuck` cannot produce a NaN from
  any value of `t`. Option A's residual risk is now confined to a NaN arriving from somewhere
  else — a NaN `luck` argument, or a future edit to the weight formula itself.

**Option B — `error()` on a non-finite weight.**

- *Benefit:* impossible to miss, and it stops a corrupt roll from ever being awarded.
- *Risk, and this is why I would not do it:* `rollTier` is called from `SlimeRoll.rollSlime`,
  which `LaunchServer.onBoxPress` calls in the middle of the reveal sequence. An uncaught error
  there aborts the handler mid-sequence — the player has already landed, already pressed the
  box, and would be left with the box open, no slime, and quite possibly a stuck client state
  depending on what the remaining sequence would have sent. Turning a rare data fault into a
  reliable player-facing softlock trades a silent failure for a loud one that is *worse for the
  player who hits it*. In a server context serving several players, an error in a per-player
  handler is also easy to leave unhandled and hard to attribute.

**Option C — detect, `warn` with the offending inputs, and fall back to the bottom tier.**

- Distinguishes the two cases: a genuine rounding fall-through returns the last tier as today;
  a non-finite weight logs and returns tier 1.
- *Benefit:* the failure becomes visible in the server log with the luck value that caused it,
  the sequence completes, and the player gets a Common instead of a guaranteed Divine — the
  failure stops being generous, which removes any incentive to trigger it and stops it silently
  inflating the economy.
- *Risk:* a player in that (never-observed) situation gets an undeservedly bad roll. That is a
  real cost, but it is bounded, attributable, and recoverable by a compensating grant; a
  silently inflated economy is none of those.
- *Secondary risk:* log spam if the condition is persistent rather than transient. Worth
  rate-limiting or firing once per server lifetime.

**Why not now.** With the floors in place the condition is unreachable from the config, so
Option C is defence against a *future* edit rather than a present fault, and it changes
observable behaviour in a case that cannot currently occur. It is worth doing as a small
separate change with its own verification — the two fixes have different risk profiles and
should not share a diff. The comment on that line should be corrected regardless, since it
currently documents only one of the two ways the line is reached.

---

## Files

- **Changed:** `src/ReplicatedStorage/Config/SlimeConfig.luau` (2 new constants + type entries
  + the comment recording why they exist and that they are unreachable),
  `src/ServerScriptService/SlimeRoll.luau` (3 lines floored + comment).
- **Not changed:** `rollTier`, `T_MAX`, `T_MIN`, the six retuned shape constants, and
  everything else on the exclusion list.
- **Untracked, not staged:** `REPORT.md`, `ECONOMY_DUMP.md`. `.gitignore` not modified.
- All temporary analysis scripts deleted. Both edited files parse clean.

### Still outstanding from the previous pass

`ECONOMY_DUMP.md` §1 and §7.1 remain stale — they describe the pre-monotonicity-fix
distribution. Unaffected by this change; regenerating it is still a separate ask.
