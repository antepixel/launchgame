# Chain links flipping thick/thin: the alternation was a function of the swing's angle

**Your diagnosis was close but not right.** The alternation *is* already a pure function of link index,
the link count *is* a fixed per-tier integer, and `repositionChainSide` *does* only move links. All
three of the things you suspected check out clean.

**The actual bug is one line**, `LaunchFormulas.repositionChainSide`, in the orientation basis rather
than in the alternation. The links are not two thicknesses — they are one 2:1 block, and every other
one is rotated 90°. Which *face* that presents to the camera depends on a reference vector that was
picked by a threshold on the chain's current tilt:

```lua
local reference = if math.abs(yAxis.Y) > 0.9 then Vector3.new(1, 0, 0) else Vector3.new(0, 1, 0)
```

`|cos θ| = 0.9` is **θ = 25.84°**, and the swing travels **±35°**. So the branch flips four times a
cycle, and takes every link's apparent thickness with it — inverting the whole pattern, top included.
The swing spends **45% of each cycle** on the far side of that threshold, which is why two screenshots
disagree about half the time.

**Fixed by pinning the reference to `(1, 0, 0)`**, the swing-plane normal. One line. §5.

**Worth pinning? Yes, easily** — the fix is a constant replacing a conditional, strictly *less* code
than what was there. Flattening every link to one thickness would have been the bigger change. §7.

---

## a) Where the links are built, and how thickness is decided

`SwingBuilder.luau:538-565`, inside `buildChainSide`, run once per side:

```lua
local topPoint = anchor.Position
local count = math.max(1, visual.chainLinkCount)
local chainThickness = if visual.chainStyle == "Rod" then postThickness * 0.35 else postThickness * 0.22
for i = 1, count do
	local segStart = topPoint:Lerp(seatTopPoint, (i - 1) / count)
	local segEnd = topPoint:Lerp(seatTopPoint, i / count)
	local link: Part
	local twisted = visual.chainStyle == "Chain" and i % 2 == 0
	if visual.chainStyle == "Chain" then
		local cf, length = cframeAlongY(segStart, segEnd)
		if twisted then
			cf = cf * CFrame.Angles(0, math.rad(90), 0)
		end
		link = newPart(Enum.PartType.Block, Vector3.new(chainThickness, length, chainThickness * 0.5), cf, ...)
	else
		link = newRod(segStart, segEnd, chainThickness, Enum.PartType.Cylinder, ...)
	end
	link:SetAttribute("ChainIndex", i)
	link:SetAttribute("Side", sideName)
	link:SetAttribute("Twist90", twisted)
end
```

**There is no thickness alternation at all.** Every link on a tier is built at the *same* size,
`Vector3.new(chainThickness, length, chainThickness * 0.5)` — a block with a **2:1 cross-section**,
wide on local X, narrow on local Z. What alternates is a **90° rotation about the link's own long
axis** (`CFrame.Angles(0, math.rad(90), 0)`), applied when `twisted` is true.

So "thick" and "thin" are the *same part* seen edge-on or face-on. That distinction is the whole bug:
a rotation's appearance depends on the frame it is measured in, and a size's does not.

**`twisted` is decided by `i % 2 == 0` — a pure parity check on the loop index.** Not position, not
height, not a rounded value. That part is exactly what you asked for and it was already correct.

## b) What the alternation is actually a function of

Two separate things, and only the first is index-driven:

| | driven by | stable? |
|---|---|---|
| **which links are twisted** (the parity) | `i % 2` — pure index | ✅ yes, always was |
| **what "twisted" looks like** (the basis it rotates in) | the chain's **current tilt** | ❌ **this is the bug** |

The parity is applied relative to a basis recomputed every frame in
`LaunchFormulas.repositionChainSide`:

```lua
local yAxis = delta.Unit
local reference = if math.abs(yAxis.Y) > 0.9 then Vector3.new(1, 0, 0) else Vector3.new(0, 1, 0)
local xAxis = reference:Cross(yAxis).Unit
```

`delta` is anchor → seat, so `yAxis.Y = -cos θ` where θ is the swing's angle. Working the cross
products through, the block's **wide** local-X axis lands on:

| swing angle | `\|yAxis.Y\|` | reference chosen | wide axis points along | untwisted link reads |
|---|---|---|---|---|
| θ = 0° (rest) | 1.00 | `(1,0,0)` | world −Z (into the view) | **narrow** |
| θ = 25° | 0.906 | `(1,0,0)` | world −Z | **narrow** |
| **θ = 25.84°** | **0.900** | — **threshold** — | — | — |
| θ = 26° | 0.899 | `(0,1,0)` | world +X (across the view) | **WIDE** |
| θ = 35° (sweet spot) | 0.819 | `(0,1,0)` | world +X | **WIDE** |

Verified numerically — the top link's wide-axis projection onto world X goes 0.00 → 1.00 between 25°
and 26°, and stays there out to 35°.

**So the topmost link is narrow below 25.84° and wide above it**, and every link behind it inverts in
lockstep. The pattern never breaks or shifts by one — it flips wholesale. `θ = 35 sin(2πp)` puts the
swing past 25.84° for **45% of every cycle**, so a screenshot taken at an arbitrary moment is close to
a coin flip. That matches "two screenshots of the same swing show opposite arrangements" precisely.

Worth noting *why* this hid for so long: the identical threshold lives in `SwingBuilder`'s
`cframeFacingAlongY:79-84`, where it is genuinely harmless — the builder only ever evaluates it at the
**θ = 0 reference pose**, where it always takes the `(1,0,0)` branch. The built swing is correct. It is
only the per-frame client repositioning that ever sees a tilted chain.

## c) The link count does not vary, and does not divide anything

```lua
local count = math.max(1, visual.chainLinkCount)
```

`chainLinkCount` is a **literal integer in `SwingTierVisuals`**, one per tier. It is not derived from
the swing's height, the rope length, `scale`, or any geometry — so there is no division, no remainder,
and no possibility of the loop starting or ending mid-pattern. The links are spaced by `Lerp` at
`(i-1)/count` and `i/count`, which fits exactly `count` segments between the endpoints at any height by
construction.

**And the top link is always `i = 1`, so `1 % 2 == 0` is always false — the topmost link is never the
twisted one, at every tier, in every build.** Your hypothesis (c) would have produced a pattern that
shifted by one; what you actually have is a pattern that inverts. Different signature, different cause.

## d) `repositionChainSide` only moves links — confirmed

It writes `CFrame` and `Size`, but never the cross-section:

```lua
-- Cylinder branch: X is the length axis
link.Size = Vector3.new(length, link.Size.Y, link.Size.Z)
-- Block branch: Y is the length axis
link.Size = Vector3.new(link.Size.X, length, link.Size.Z)
```

Each writes **only the length axis** and reads the other two back off the part itself. The 2:1
cross-section set at build time is preserved verbatim, every frame, forever. No size is ever
reassigned.

The ordering is sound too: links are filtered by their `Side` attribute, then
`table.sort`ed on `ChainIndex`. Every link carries a distinct `ChainIndex` within its side, so the
comparator is a strict ordering with no ties and the result is deterministic regardless of
`GetChildren` order or `table.sort`'s instability. `Twist90` is read per-link from the attribute rather
than recomputed from the loop position, so the parity follows the individual link.

Both callers — `LaunchClient.repositionChainLinks:359` and
`LaunchRemoteLanes.repositionChainLinksFor:75` — delegate to this one function, so they shared the bug
and share the fix.

## e) Per tier: which tiers are affected

Only `chainStyle == "Chain"` builds blocks. `Rope` and `Rod` build **cylinders**, which are radially
symmetric about their length axis — the reference vector rotates them, but you cannot see a cylinder
spin about its own axis, so the flip is invisible. `Energy` builds no links at all, just a `Beam`.

| tier | style | links | count even? | alternates? | topmost link | affected by the bug? |
|---:|---|---:|---|---|---|---|
| 1 | Rope | 5 | odd | no | cylinder | no — radially symmetric |
| 2 | Rope | 5 | odd | no | cylinder | no — radially symmetric |
| 3 | Rope | 6 | even | no | cylinder | no — radially symmetric |
| **4** | **Chain** | **7** | **odd** | **YES** | **`i=1`, untwisted** | **YES** |
| **5** | **Chain** | **7** | **odd** | **YES** | **`i=1`, untwisted** | **YES** |
| **6** | **Chain** | **8** | **even** | **YES** | **`i=1`, untwisted** | **YES** |
| 7 | Rod | 3 | odd | no | cylinder | no — radially symmetric |
| 8 | Rod | 3 | odd | no | cylinder | no — radially symmetric |
| 9 | Rod | 2 | even | no | cylinder | no — radially symmetric |
| 10 | Energy | 0 | — | no | Beam | no — no links exist |
| 11 | Energy | 0 | — | no | Beam | no — no links exist |

**Tiers 4, 5 and 6 only.** You reported tier 5, which is one of exactly three tiers that can show it —
consistent. Note the count's parity is irrelevant to the symptom: tier 6 has an even count and tiers 4
and 5 odd, and all three flip identically, because the flip is global to the side rather than an
off-by-one at either end.

## 5. The fix

`LaunchFormulas.repositionChainSide`, block branch only:

```lua
-- was: local reference = if math.abs(yAxis.Y) > 0.9 then Vector3.new(1, 0, 0) else Vector3.new(0, 1, 0)
local reference = Vector3.new(1, 0, 0)
```

**`(1, 0, 0)` is correct unconditionally here, not a workaround for the threshold.** Each side's chain
runs from an anchor at `X = ±seatHalfWidth` to a seat attachment at the **same** `X`
(`SwingBuilder:446-452, 506-507`), so `delta.X` is exactly zero and the chain direction always lies in
the YZ plane. World X is the swing-plane normal: perpendicular to `yAxis` at every θ by construction,
so the cross product can never go degenerate, and it is continuous where the old branch was not.

Working it through, `xAxis = (1,0,0) × (0, −cos θ, sin θ) = (0, −sin θ, −cos θ)`, which is a unit vector
perpendicular to `yAxis` at every θ, and the block's narrow local-Z axis lands on world −X for all θ.
Stable by construction, not by tuning.

It is also **the same branch the builder takes**, since `cframeFacingAlongY` evaluates at the θ = 0
reference pose where `|yAxis.Y| = 1`. So the first repositioned frame now agrees with the built pose
instead of potentially popping.

**What it was a function of:** the swing's current tilt angle, via a `|yAxis.Y| > 0.9` threshold on the
chain direction.
**What it is a function of now:** nothing but the link's own index — the basis is a fixed world axis,
and `i % 2` alone decides which links are turned in it.

### Deliberately not changed

The **cylinder branch keeps its conditional.** It is genuinely unobservable there (a cylinder cannot
show rotation about its length axis), the Rope/Rod chains are the only callers that hit it, and
changing it would be churn with no visual effect. The asymmetry between the two branches is now
explained in a comment at the fix site so it does not read as an oversight.

## 6. Verification

- **Geometry re-derived from the source constants**: threshold at θ = 25.84°, swing travel ±35°, 45% of
  each cycle past it, top link's wide-axis projection 0.00 → 1.00 across the threshold under the old
  code and flat 0.00 at every θ under the fix.
- **`rojo build default.project.json` succeeds.**
- **Diff is one file**: `LaunchFormulas.luau`, one logic line plus its comment.
- **No playtest**, per instruction.

Not verified on screen — this is a visual bug and the arithmetic says it is fixed, but tiers 4–6 at the
swing extremes are what would confirm it.

## 7. Is it worth pinning, or should the links just be one thickness?

**Pinning is worth it, and it is not a close call** — the fix replaced a conditional with a constant.
It is fewer tokens than what was there, adds no state, no new attribute, no per-tier data, and no
branch. There is no complexity to weigh against the detail.

Flattening the links to a single thickness would have been the *larger* change: it means editing the
block's size in `SwingBuilder`, deleting the `twisted` computation, the build-time
`CFrame.Angles` branch, the `Twist90` `SetAttribute`, and the re-apply in `repositionChainSide` — five
edits across two files, to remove a deliberate visual that distinguishes the three mid-tier swings from
the Rope tiers below and the Rod tiers above.

If the alternation had needed new machinery to stabilise — a stored orientation, a per-tier table, a
seeded value — the answer would have been the opposite, and I would have said so. It did not. The
alternation was already index-driven; only the frame it was drawn in was not.

## 8. Untouched

Swing heights, `SWING_PERIOD_SECONDS`, the sweet-spot phase window, arc angle,
`ARC_HEIGHT_SQRT_COEFFICIENT`, the camera pullback, distance at any tier, the per-tier snap thresholds,
ping compensation, the luck distribution, swing prices, the upgrade curve, the chest and its reveal,
road geometry, the platform, the landmark, SlimeBuilder, SignBuilder, ChestBuilder, the collect pads,
the idle breathing animation, the six-lane remote rendering block, the spawn flow, the dev panel gates
and the `resetReadyRemote` death-cancellation path. `SwingBuilder` itself is unmodified — the build was
always correct.

## 9. One adjacent observation, not fixed

`Twist90` is read with `link:GetAttribute("Twist90")`, which returns `nil` if the client repositions a
link before its attributes have replicated. That would make *every* link untwisted for those frames —
all links looking identical, briefly — rather than inverting the pattern, so it is not what you saw.
It is transient and self-correcting, and fixing it properly means gating the reposition on attribute
presence. Left alone; flagged in case a first-frame flicker ever gets reported.

## 10. Still outstanding, unchanged

The chest's facing inference (`orientLockToFront`); the tier-11 overshoot slice; `game.rbxlx` still a
stale 6 Aug artifact; the two duplicate-function pairs; the 27-local remotes bootstrap; the
`GetNetworkPing()` one-way-vs-RTT question; and the release camera's 35° tilt against a 88–210 stud
pullback putting the subject at the top edge of frame (see the previous report).
