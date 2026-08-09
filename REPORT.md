# Arc raised 25%: k 3.85 → 4.8125

One constant, one file. **`ARC_HEIGHT_SQRT_COEFFICIENT = 4.8125`**, exactly.

**Your expected shape is exact** — 68.1 / 206.4 / 266.7 against your 68 / 206 / 267. §2.

**Distance is untouched and the release framing is byte-identical** — the pullback formula contains
no arch term, and the sky table's u = 0 column comes out the same to the digit. §5, §7.

**What it costs: scenery goes from worth 32 points of frame to 29.** Bare-map mid-flight gives back
2 points (84% → 86%). Cheap for a 25% bigger arc. §4.

**The pose clamp comes back at tiers 4 and 5.** It bound at tiers 1–3 before; the binding band widens
from ≤1,040 studs of distance to ≤1,654. §6.

**The launch angle you asked to watch** now runs 53.0° at tier 1 down to 18.8° at tier 11 — the same
3.9× spread, lifted. Tier 1 is back to almost exactly its original steepness. §3.

---

## 1. The value, derived

```
current shipped k                     3.85
target: arch 25% above current        3.85 * 1.25 = 4.8125   <- exact, no rounding
```

**Arch is linear in k**, so multiplying k by 1.25 multiplies the arch by exactly 1.25 at every tier —
verified at 1.2500 to four places at tiers 1, 6 and 11. This is a uniform lift of the whole curve,
not a reshaping: the 3.9× spread between the ends is unchanged.

**I used 4.8125, not 4.8082.** Re-deriving from a scaled mid-ladder target (165 × 1.25 = 206.25, over
√1840) gives 4.808228. The two differ because the shipped 3.85 was itself rounded *up* from 3.846582.
The brief said "25% above current", and current means the value actually in the file — so the
multiply is the honest reading, and it is the one that makes the ratio exactly 1.25 rather than
1.2494. The difference is 0.6 studs of arch at tier 11.

Your 4.81 would have given 1.2494× — a 0.06% shortfall, invisible, but there was no reason to accept
it when the exact value is a terminating decimal.

## 2. Arch, apex and launch angle, every tier

| tier | dist | OLD arch | OLD apex | OLD angle | **NEW arch** | **NEW apex** | **NEW angle** | apex Δ |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 200 | 54.4 | 57.9 | 46.5° | **68.1** | **71.5** | **53.0°** | +23.5% |
| 2 | 600 | 94.3 | 98.0 | 31.6° | **117.9** | **121.6** | **37.7°** | +24.0% |
| 3 | 880 | 114.2 | 118.3 | 27.0° | **142.8** | **146.9** | **32.6°** | +24.1% |
| 4 | 1280 | 137.7 | 142.5 | 22.9° | **172.2** | **176.9** | **28.0°** | +24.2% |
| 5 | 1640 | 155.9 | 161.2 | 20.5° | **194.9** | **200.1** | **25.1°** | +24.2% |
| 6 | 1840 | 165.1 | 171.0 | 19.4° | **206.4** | **212.3** | **23.9°** | +24.1% |
| 7 | 2160 | 178.9 | 185.5 | 18.0° | **223.7** | **230.2** | **22.2°** | +24.1% |
| 8 | 2320 | 185.4 | 192.6 | 17.4° | **231.8** | **239.0** | **21.5°** | +24.1% |
| 9 | 2520 | 193.3 | 201.1 | 16.7° | **241.6** | **249.4** | **20.7°** | +24.0% |
| 10 | 2760 | 202.3 | 210.9 | 16.0° | **252.8** | **261.5** | **19.8°** | +24.0% |
| 11 | 3071 | 213.4 | 223.1 | 15.2° | **266.7** | **276.4** | **18.8°** | +23.9% |

**Arch is up exactly 25.00% everywhere; apex is up 23.5–24.2%.** Not a discrepancy — apex is the
arch term *plus* the start-height descent term, and only the arch part scales with k. The gap is
largest at tier 1, where the 6.8-stud start height is the biggest share of the total.

### Where the launch angle lands

This is the character measure worth watching, since √ scaling made it vary by tier. Against all
three arcs the game has had:

| tier | 1 | 3 | 6 | 8 | 11 | spread |
|---|---:|---:|---:|---:|---:|---|
| original (0.35 linear) | 53.8° | 54.3° | 54.3° | 54.3° | 54.3° | flat |
| k = 3.85 | 46.5° | 27.0° | 19.4° | 17.4° | 15.2° | 3.1× |
| **k = 4.8125** | **53.0°** | **32.6°** | **23.9°** | **21.5°** | **18.8°** | **2.8×** |

**Tier 1 is back to essentially its original steepness** — 53.0° against the old 53.8°, a 0.8°
difference. So the lift lands almost entirely where you'd want it: the bottom of the ladder is
restored to the lob it always was, and the top comes up from 15.2° to 18.8° without returning to the
flat 54° that put every flight 650 studs in the sky.

The tiers that still read flattest are 9–11 at 18.8–20.7°. That is a line drive rather than a lob,
and it is inherent to √ scaling — only a different exponent narrows the spread.

## 3. How far ahead the ground enters frame

`apex / tan(35°)`, against all three arcs:

| tier | dist | original | k = 3.85 | **k = 4.8125** |
|---:|---:|---:|---:|---:|
| 1 | 200 | 105 | 83 | **102** |
| 2 | 600 | 305 | 140 | **174** |
| 3 | 880 | 446 | 169 | **210** |
| 4 | 1280 | 647 | 204 | **253** |
| 5 | 1640 | 827 | 230 | **286** |
| 6 | 1840 | **928** | **244** | **303** |
| 7 | 2160 | 1089 | 265 | **329** |
| 8 | 2320 | 1170 | 275 | **341** |
| 9 | 2520 | 1271 | 287 | **356** |
| 10 | 2760 | 1392 | 301 | **373** |
| 11 | 3071 | 1549 | 319 | **395** |

At tier 6: 928 → 244 → **303**. Still 16% of the flight's length rather than the 50% the original arc
cost, so the ground is in frame from early in the flight — just not quite as early as at k = 3.85.

## 4. Sky fraction — what the lift costs

Camera unchanged (pullback 200.3 at tier 6 — it does not read arch, §7). Same method, same points,
lane 0 / lane 3.

### Bare map

| level camera | u=0 | u=.25 | u=.5 | u=.75 | u=1 |
|---|---|---|---|---|---|
| k = 3.85 (arch 165.1) | 41/41 | 84/84 | 86/86 | 80/80 | 48/41 |
| **k = 4.8125 (arch 206.4)** | 41/41 | **86/86** | **88/88** | **83/83** | 48/41 |

| 35° down camera | u=0 | u=.25 | u=.5 | u=.75 | u=1 |
|---|---|---|---|---|---|
| k = 3.85 | 40/37 | 76/76 | 78/78 | 74/74 | 57/49 |
| **k = 4.8125** | 40/37 | **78/78** | **80/80** | **76/76** | 57/49 |

### With the hypothetical flanking scenery

(Same sensitivity test as before — 100 studs tall, X ±130 to ±320, road's full length. Not a
proposal.)

| level camera | u=0 | u=.25 | u=.5 | u=.75 | u=1 |
|---|---|---|---|---|---|
| k = 3.85 | 28/25 | 52/52 | 57/56 | 49/49 | 14/11 |
| **k = 4.8125** | 28/25 | **57/56** | **63/61** | **54/53** | 14/11 |

| 35° down camera | u=0 | u=.25 | u=.5 | u=.75 | u=1 |
|---|---|---|---|---|---|
| k = 3.85 | 11/6 | 29/26 | 35/32 | 27/24 | 5/6 |
| **k = 4.8125** | 11/6 | **34/31** | **42/38** | **32/29** | 5/6 |

### What scenery is worth, at each arc

At u = 0.25, level camera:

| arc | bare | with scenery | **scenery is worth** |
|---|---:|---:|---:|
| original (0.35 linear) | 94% | 86% | 8 points |
| k = 3.85 | 84% | 52% | **32 points** |
| **k = 4.8125** | **86%** | **57%** | **29 points** |

On the 35°-down camera: 19 → 47 → **44** points.

**The cost of the 25% lift is 3 points of scenery value and 2 points of bare-map sky.** The change
gives back a small fraction of what flattening bought, and keeps the great majority of it — 29 of the
32 points. Nothing about the enabling result changes.

## 5. Horizontal distance at u = 1 — confirmed

Both trajectory copies are untouched by this pass:

```lua
local z = startPosition.Z - distance * u              -- no arch term
local heightOffset = archHeight * 4 * u * (1 - u)     -- exactly 0 at u = 0 and u = 1
```

Landing Z per tier, identical to the last four surveys:

| tier | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| landing Z | −175.74 | −576.42 | −857.34 | −1258.89 | −1620.04 | −1821.47 | −2143.19 | −2304.63 | −2506.06 | −2748.07 | −3061.69 |

And observed rather than argued: **the u = 0 and u = 1 columns of every sky table above are
bit-identical between the two arcs.** They can only be, if the arch term really is zero at both
endpoints.

Duration is also unchanged (distance only): 1.80 s at tier 1 through 7.05 s at tier 11.

## 6. The pose clamp binds again at tiers 4 and 5

`trajectoryPitch` clamps to ±25°.

| tier | 1 | 2 | 3 | **4** | **5** | 6 | 7 | 8 | 9 | 10 | 11 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| raw release angle | 53.0° | 37.7° | 32.6° | **28.0°** | **25.1°** | 23.9° | 22.2° | 21.5° | 20.7° | 19.8° | 18.8° |
| k = 3.85 — binds? | YES | YES | YES | no | no | no | no | no | no | no | no |
| **k = 4.8125 — binds?** | **YES** | **YES** | **YES** | **YES** | **YES** | no | no | no | no | no | no |

**The binding band widens from distance ≤ 1,040 studs to ≤ 1,654 studs** (solving
`4k√d − startY = d·tan 25°`). Tiers 4 and 5 cross back over; **tier 5 is marginal at 25.1°**, one
tenth of a degree inside the clamp, so it will visually read as clamped but is effectively right on
the line.

The shape is the same as before and still the inverse of the linear case: arch grows as √d while the
clamp threshold grows as d, so short flights slam into the clamp and long ones do not reach it. Tiers
6–11 still release at their true angle (18.8–23.9°) rather than a clipped 25°.

## 7. The release framing is identical — confirmed

```lua
local function releaseCameraPullback(startPositionZ: number, distance: number): number
	local requested = LaunchConfig.CAMERA_BEHIND_DISTANCE + distance * LaunchConfig.CAMERA_PULLBACK_FACTOR
	local standZ = (BaseConfig.BASE_BACK_EDGE_Z + RunwayGeometry.MAP_BACK_EDGE_Z) / 2
	return math.min(requested, standZ - startPositionZ)
end
```

**No arch term appears anywhere in it.** Pullback per tier is unchanged: 88.0 at tier 1, then 195.3
→ 209.5 for tiers 2–11, all pinned to the map's back edge at Z 218.87.

Empirically: the u = 0 sky column is **41/41 and 40/37 in both rows of every table** — identical,
because both the camera and the arch term are the same at that instant. This is exactly the property
the camera fix was made for, and it is now observed twice over.

## 8. Files changed

| file | change |
|---|---|
| `Config/LaunchConfig.luau` | `ARC_HEIGHT_SQRT_COEFFICIENT` 3.85 → **4.8125**, and the derivation comment updated to record the multiply and why it is not 4.8082 |

**Nothing else.** No code path changed — `LaunchServer:1888` still reads
`ARC_HEIGHT_SQRT_COEFFICIENT * math.sqrt(distance)`. Distance, the camera pullback, snap thresholds,
ping compensation, the luck distribution, the chest and reveal, road geometry, the platform, the
landmark, the builders, the module boundaries, the six-lane block, the spawn flow, the dev panel
gates and the `resetReadyRemote` path are all untouched.

Both files parse; `rojo build` succeeds.

## 9. What needs eyes in Studio

- **Tiers 4 and 5 are back on the pose clamp**, and tier 5 by 0.1°. If the tilt reads
  inconsistently between tier 5 (clamped) and tier 6 (23.9°, not clamped), the clamp itself —
  `MAX_FLIGHT_PITCH`, 25° — is the constant, not k.
- **Tier 1 at 53.0° is within a degree of the original 53.8°.** If tier 1 was already the tier that
  felt right, it now feels the same again, which is either the confirmation or the sign that the lift
  went too far at the bottom.
- **Bare-map mid-flight is 86%.** As before, judging this arc against the current empty map measures
  the wrong thing — the 29-point scenery figure is the one that matters.
- **No playtest**, per instruction.

## 10. Still outstanding, unchanged

The chest's facing inference (`orientLockToFront`); the tier-11 overshoot slice; `game.rbxlx` still a
stale 6 Aug artifact; the two duplicate-function pairs; the 27-local remotes bootstrap; and the
`GetNetworkPing()` one-way-vs-RTT question.
