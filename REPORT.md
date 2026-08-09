# Belt stutter — instrumentation, no fix

**No fix in this pass, by instruction.** One file changed:
`ReplicatedStorage/LaunchClient/ConveyorScroll.luau`. `rojo build` passes.

You are right that I have been proposing causes instead of measuring them. Two hypotheses, two misses.
This pass adds measurement only.

**The single number that decides it is `inc/delta`.** The increment is `speed × delta × sign`, and both
`speed` and `sign` are now constants — so that ratio *must* come out dead flat at exactly the belt
speed. Whether it does, and whether `delta` is flat alongside it, separates all three of your
candidates in one reading. §How to read it.

**The quantisation question is measured directly, in-session** — the loop now writes `OffsetStudsU`
and reads it straight back, so `writeback err` tells you whether the property stores what we computed.
I could not probe it myself; the Studio plugin timed out on both attempts. §Quantisation.

---

## What was added

A single delimited block in `ConveyorScroll.luau`, plus three marked lines inside the loop. Both are
labelled `TEMPORARY INSTRUMENTATION` and the block's header names the three lines, so removal is
mechanical.

| captured, per belt per frame | why |
|---|---|
| `deltaTime` | your candidate 1 — is the client's frame pacing irregular? |
| `increment` (`speed × delta × sign`) | your candidate 2 — is the arithmetic irregular? |
| `inc / delta` | **the discriminator** — must be constant; see below |
| offset **before** and **after** the wrap | confirms the wrap fires where expected and never goes backwards except at a boundary |
| cached `speed` | confirms the cache holds one value and is not being re-sampled |
| **`writeback err`** | write the offset, read it straight back — direct test of property-level quantisation |

**300 frames (~5 s at 60 fps), then one summary — not per-frame printing.** Per-frame output would
cost frames and change the thing being measured, which on a stutter investigation would be
self-defeating.

### Running it

It is client-side (required by `LaunchClient`). Play, stand anywhere, wait ~5 seconds, then **filter
Output for `[BeltScroll]`**. It prints once and stops; `DEBUG_ENABLED` at the top of the block turns it
off without deleting anything.

## How to read it — the decision table

Expected healthy values at 60 fps with the current settings: `delta` mean **0.01667**, `increment` mean
**0.5333**, `inc/delta` **32.00000** with a standard deviation around **1e-15** (pure float noise).

| `inc/delta` | `frame delta` | verdict |
|---|---|---|
| **flat** (sd < 1e-9) | **varies** (max/min > ~1.5, outliers > 0) | **Candidate 1 — frame pacing.** The client is hitching and the belt is only revealing it. The arithmetic is doing its job perfectly; a scrolling texture is just an unusually sensitive readout of frame-time variance. |
| **varies** (sd meaningfully > 0) | either | **Candidate 2 — the arithmetic.** Something that should be constant is not: the speed cache is being re-sampled, or the sign is changing. This would genuinely surprise me and would point straight at a bug in the loop. |
| **flat** | **flat** (max/min ≈ 1.0–1.2, few or no outliers) | **Candidate 3 — downstream of us.** The value we compute is smooth and evenly spaced, so the stepping is in how the property is stored or rendered. Then read `writeback err`. |

### The `writeback err` line

| value | meaning |
|---|---|
| **≤ ~1e-7** | The property stores what we asked. float32 rounding only. If motion still steps, it is the **renderer**, not the value. |
| **> 1e-4** | **The property itself is snapping** to a grid. Our arithmetic never reaches the renderer intact, and no amount of precision upstream will help. |

### One interpretive caution about the outlier list

`increment` is exactly proportional to `delta`, so **an increment outlier is a delta outlier** — the
outlier list is a frame-pacing readout, not an arithmetic one. Do not read "7 outlier frames" as "the
maths wobbled 7 times"; it means the frame time did. The arithmetic's health is `inc/delta`'s standard
deviation and nothing else.

That is also why I print both: if outliers are frequent *and* `inc/delta` is flat, candidate 1 is
confirmed on two independent measures.

## Quantisation — what I can and cannot establish

**I could not measure it myself.** I attempted a direct probe — build a part and texture, write a
sequence of offsets, read each back, report the worst error — and the Studio MCP bridge timed out with
`Studio plugin connection timeout`, as it did on the surface-type probe last pass. No playtest was run,
per instruction. So the probe now lives inside the instrumentation instead, and your run will answer it.

**What I can establish by reasoning, kept separate from what is measured:**

- **`OffsetStudsU` is a float property**, and at the magnitudes involved (0–8 studs) float32 storage
  gives ~1e-7 of error against a 0.53-stud increment. Storage precision alone cannot produce visible
  steps. This is the same arithmetic that already ruled out the unbounded-growth theory.
- **Texel snapping is unlikely to be the mechanism.** GPU sampling of a texture is continuous and
  bilinear-filtered; a sub-texel UV offset renders as a sub-texel shift, not a snapped one. If the
  renderer worked on whole texels, the step would be 8/256 = 0.03 studs against a 0.53-stud
  increment — 6% granularity, far too fine to see.
- **The mechanism that *would* fit is temporal, not spatial.** Property writes reach the render thread
  through the instance property system, which is not obliged to sample them once per `RenderStepped`.
  If the render thread picks the offset up on its own cadence, some frames show no change and the next
  shows a double step — visually identical to microstutter, and **completely invisible to our
  arithmetic**, which would read perfectly smooth. This is my leading candidate *if* the data comes
  back "both flat", and it is exactly the case the third row of the table above points at.

**The tell that separates temporal from spatial, if it comes to that:** a temporal cadence problem
produces stepping with a **regular period that does not change when the frame rate changes**, and
raising `BELT_RIDGE_TILE_STUDS` would *not* help. Spatial quantisation would scale with the tile.
That is a test to run after the data, not before — and it needs a constant you have put out of scope,
so I have not touched it.

**What the instrumentation cannot see.** `writeback err` proves whether the *property* stores our
value. It cannot prove what the *renderer* does with it afterwards — no Lua-visible measurement can.
If the data lands on row 3 with a clean writeback, the remaining discrimination is visual, and I will
describe that test rather than guess again.

## A cheap cross-check worth doing at the same time

While the belt is stuttering, **watch the swing seat**. It is repositioned every frame by a different
module (`LaunchFormulas`/`LaunchClient`) from a clock rather than from a property, so:

- **swing smooth, belt stuttering** → the problem is specific to the belt path (rows 2 or 3).
- **both stuttering together** → row 1, and the belt is a symptom rather than a cause.

This costs nothing, needs no code, and independently corroborates whatever the numbers say.

## Removal

Delete the block between `TEMPORARY INSTRUMENTATION` and `END TEMPORARY INSTRUMENTATION`, then the two
`if DEBUG_ENABLED and not debugDone then` guards in `update()` (one inside the belt loop, one at the
end of the frame). The three lines that compute `increment` and `before` stay — they are now used by
the real code path and reading them as locals is clearer than the one-line version anyway.

## Files

| file | change |
|---|---|
| `LaunchClient/ConveyorScroll.luau` | temporary instrumentation block; `increment`/`before` lifted to locals; two guarded recording calls |

**Nothing else touched.** `BELT_SPEED_STUDS_PER_SECOND`, the velocities, `BELT_RIDGE_TILE_STUDS` (8),
`BELT_RIDGE_SCROLL_SIGN` (1), the texture asset ID and the belt geometry are all unchanged, and
`git status` shows one modified file.

## What I need back

Paste the `[BeltScroll]` block from Output. The three lines that decide it are `inc/delta`'s standard
deviation, `frame delta`'s max/min, and `writeback err`'s max — everything else is corroboration.

## Still outstanding, unchanged

The chest's facing inference (`orientLockToFront`); the tier-11 overshoot slice; `game.rbxlx` still a
stale 6 Aug artifact; the two duplicate-function pairs; the 27-local remotes bootstrap; the
`GetNetworkPing()` one-way-vs-RTT question; the release camera's 35° tilt against an 88–210 stud
pullback putting the subject at the top edge of frame; the kerb's comment claiming MapBuilder leaves it
`CanCollide` off when it does not; and the road labels having grown 50% from the widening.
