# Studded ground surfaces

**Three files changed, `rojo build` passes.** One named value —
`GroundConfig.GROUND_TOP_SURFACE = Enum.SurfaceType.Studs` — read by both builders that make ground.

**Answering (c) honestly up front: only ONE surface in the map had a surface type set at all.** The
collect pads were explicitly `Smooth`. Everything else was left at the part default, and **I could not
query what that default is** — the Studio plugin is offline, my probe timed out. That materially
affects how much visible change to expect. §c.

**The road bands' labels are not on the bands.** They live on a separate invisible part floating above
each band, so studs there would *not* fight them — your stated reason for excluding them doesn't hold.
I left them smooth as instructed, but the technical objection is gone and my actual opinion is in §Road
bands.

**The belt is the one place studs work against you** — static studs under a scrolling texture is the
same problem that got DiamondPlate dropped from that part last pass. Applied as asked, flagged clearly.
§a.

**Studs on the Neon collect pads will probably be invisible** — Neon shades flat and relief is read
from shading. §b.

**Nothing derives a height or landing from these surfaces** — verified against each one, not assumed.
§d.

---

## What was included

| surface | builder | included | note |
|---|---|:--:|---|
| Belt halves (`BeltNear`/`BeltFar`) | MapBuilder | ✅ | see §a — has a Top-face `Texture` |
| Approach links | MapBuilder | ✅ | |
| Spurs | MapBuilder | ✅ | |
| Plot mats | MapBuilder | ✅ | |
| Central paths | MapBuilder | ✅ | also PathConfig-coloured, also ground |
| Side edge trim (×2/lane) | MapBuilder | ✅ | 1.1 studs proud — walked over between plots |
| Back edge trim | MapBuilder | ✅ | |
| Slot pads (10/lane) | MapBuilder | ✅ | see §a — has a Top-face `SurfaceGui` |
| Collect pads | PlayerProfile | ✅ | see §b — Neon |
| **Kerb** | MapBuilder | ✅ | **my judgement call — you didn't list it** |
| Shop stall floor | — | n/a | **there isn't one** |

## Things you missed, and what I did about each

**The kerb — included.** `GroundConfig.KERB_SIZE`, 480 × 1.2 × 2 along the road edge. It is paved
ground dressing in the same concrete as the paths, and at 1.2 studs tall a player walks over it rather
than round it. Leaving it smooth would have put an unstudded strip across the full width right where
the paths meet the runway. Say the word and it comes out — it is one `asGround` wrapper.

**The shop stalls have no floor.** I checked the whole build: posts, front panel, rail, counter top,
roof deck, roof band, shopkeeper torso/head, sign leg, sign board. **No floor part exists** — the
stalls stand directly on the belt/baseplate. So "stall floors, if they have one" resolves to nothing
to do. The counter top is furniture, not ground, and is excluded.

**The swing ground pads — deliberately NOT included, and I want you to confirm.** `SwingBuilder`
builds four `GroundPad*` parts per swing, under the frame's feet. They are genuinely walkable ground by
any reasonable reading. I left them alone because "the swings" are on your standing exclusion list and
these are built by `SwingBuilder` as part of the swing. **If you meant the pads to count as ground,
that is a fifth call site and I should add it** — but I would rather ask than widen an explicit
exclusion on my own.

**The mount radius markers — excluded.** Flat translucent Neon discs, `CanCollide = false`. They are an
overlay indicating a radius, not a surface; studs on a see-through marker would read as a bug.

## a) Studs + a Texture on the same face

**They coexist. Neither overrides the other, and there is no conflict to resolve.**

They are independent systems: `SurfaceType` is a rendered decoration on the face, a `Texture` is a
tiled image drawn on it. Setting one does not clear or suppress the other. The belt's ridge texture has
a **transparent background** (the spec I gave you, and what you uploaded), so the studs show *through*
the gaps between ridges and the dark bars draw over them.

**The real problem is not technical, it is that they fight for the same job.**

The scrolling ridges exist to make the surface look like it is moving. **Studs are static.** A static
pattern sitting under a moving one gives the eye a fixed reference that says "this surface is not
actually going anywhere" — which is precisely the reasoning that got `DiamondPlate` dropped from the
belt last pass, in this same file's history:

> two competing patterns on one surface read as noise, and the moving one loses — which is exactly the
> thing that has to stay legible

Studs are a *stronger* fixed reference than DiamondPlate's tread was, because the relief is coarser and
catches light.

**I applied it, because you scoped it explicitly and you may well like the classic look enough to
accept a weaker sense of motion.** But it is the one surface in the list where the change works against
something we deliberately built, so:

**Revert for the belt alone:** delete the `asGround(...)` wrapper on `MapBuilder:288` (the
`local belt = asGround(newBlock(` line and its closing paren). Nothing else is affected — the texture,
the scroller, the velocities and the geometry are all independent.

### The slot pads have the same question, with a different answer

Each slot pad carries a Top-face `SurfaceGui` (`SlotLabel`, the slot number, `PixelsPerStud = 24`). A
SurfaceGui is drawn as a flat overlay *on* the face — it does not displace the surface decoration under
it, so again both render. Here I think it is fine rather than counterproductive: the label is opaque
text over the studs, nothing is animated, and a numbered studded pad is exactly the classic look. If
the number gets harder to read against the relief, the same one-wrapper revert applies at
`MapBuilder:175`.

## b) Studs on the Neon collect pads

**Likely to be invisible, and the material is the reason — not the property.**

`BASE_COLLECT_PAD_MATERIAL = Enum.Material.Neon`. Neon is self-illuminated: it renders at near-uniform
full brightness and ignores most scene lighting. **Surface relief is read entirely from shading** — the
light and dark sides of each stud are what make it look raised. Flood the surface with uniform emission
and there is little shading left for the relief to live in.

So the property will be set correctly and the pads may look exactly as they do now. **That is expected,
not a failure.** Your options if you want them studded for real:

- Accept flat — the pads are 4 × 8 stud markers, and their job is to be an obvious green "collect
  here", which Neon does well.
- Change `BASE_COLLECT_PAD_MATERIAL` to `SmoothPlastic` with a bright green — studs would read, at the
  cost of the glow. **Out of scope this pass** (material is on your must-not-change list) and I have
  not touched it.

Worth noting the pads are also `CanCollide = false` — they are markers you walk *through*, not on. That
weakens the case for studding them at all, but they were in your list and the change is harmless.

## c) What each part type was set to before

**Only one surface in the entire map had ever been assigned.** `grep` across `src` for any
`*Surface` property found exactly two lines, both on the collect pad:

| part type | before | after |
|---|---|---|
| **Collect pads** | **`Enum.SurfaceType.Smooth`** (explicit, `PlayerProfile:399`) | **`Studs`** |
| Belt halves, approach links, spurs, mats, central paths, side/back trim, slot pads, kerb | **never assigned — engine default** | **`Studs`** |

### The honest caveat on that second row

**I could not determine what `Instance.new("Part")` actually defaults `TopSurface` to in your Studio
version.** I tried to query it — create a part, read the property back, test the Texture interaction
and confirm the size is unchanged — and the call failed with `Studio plugin connection timeout`. No
playtest was run, per your instruction.

This matters, so I will not paper over it. Roblox's long-standing `Instance.new` default is
`TopSurface = Studs` (Studio's *insert* button applies Smooth, which is a different path). **If that is
still the default, most of these parts were already studded and this pass changes nothing visible for
them** — the only guaranteed visible change would be the collect pads, which were explicitly Smooth.

Either way the change is worth having: it makes the finish an explicit, named, single decision instead
of an inherited default that a future engine change could silently flip. But if you look at it and the
paths appear unchanged, **that is the likely reason, and it means they were already right** — not that
the code failed.

If the ground looks smooth *after* this, the cause is elsewhere: most likely material. `Concrete`,
`Slate` and similar carry their own strong surface texture that can visually swamp stud relief.

## d) Does anything derive a height or landing from these surfaces?

**Confirmed, by checking each derivation rather than assuming.**

Surface types are a rendered decoration. They do not change `Size`, the bounding box, or collision
geometry — a studded part occupies exactly the volume its `Size` describes, and a character stands at
the same height on it.

Every height derivation in the project reads `Position` and `Size`, never a surface:

| derivation | reads | affected |
|---|---|:--:|
| `RunwayGeometry.RUNWAY_TOP_Y` | `baseplate.Position.Y + baseplate.Size.Y / 2` | ❌ (and the baseplate is excluded anyway) |
| `groundY` (BaseGeometry, MapBuilder, SwingGeometry) | same baseplate expression | ❌ |
| `matTopY` | `groundY + BASE_MAT_Y_OFFSET + BASE_MAT_SIZE.Y / 2` | ❌ |
| Slot pad Y | `groundY + BASE_SLOT_PAD_Y_OFFSET` | ❌ |
| Collect pad Y | `matTopY + size.Y / 2` | ❌ |
| Flight landing Y | `RunwayGeometry.RUNWAY_TOP_Y` (u = 1) | ❌ |
| `bandLuckForLandingZ` | landing **Z** only | ❌ |
| Return position Y | `groundY +` a standing offset | ❌ |
| `SwingGeometry.pivotYForScale` | `groundY + PIVOT_HEIGHT * scale` | ❌ |

**Nothing reads a rendered surface, and no `Size` changed.** The one thing that would have been a real
risk — a surface decoration inflating collision and lifting characters — is not how Roblox implements
these.

## Road bands — you asked me to push back, so here it is

**The technical objection you raised does not exist.** I checked, expecting to confirm it, and found
the opposite: the number labels are **not on the bands**. `RunwayBuilder:150-166` builds a *separate*
part per band —

```lua
local sign = Instance.new("Part")
sign.Transparency = 1                                    -- invisible
sign.CanCollide = false
sign.Position = Vector3.new(RUNWAY_X, RUNWAY_TOP_Y + SIGN_CLEARANCE, centerZ)   -- floating ABOVE
```

— with the `SurfaceGui` on *that*. The labels hover above the road on their own invisible plate. **A
studded band could not fight them; they do not share a face, or even a part.**

**My actual opinion: I think the bands would look better studded, and I would put them in.** The road
is the single biggest surface in the map and the one thing every flight is framed against; leaving it
the only smooth walkable surface in a studded map is the inconsistency, not the other way round. The
classic Roblox rainbow road *is* studded — that is the reference this road is already reaching for with
its full-saturation `Color3.fromHSV(hue, 1, 1)` bands.

**Two honest counterpoints:** at flight altitude (68–267 studs of arch) stud relief will be invisible
anyway, so the benefit is confined to standing near the start; and it is 74 bands at 360 × 40 studs
each, which is a lot of surface decoration, though the cost is modest.

**I left them smooth, as instructed.** If you want them, it is one `asGround`-equivalent line in
`RunwayBuilder` after `band.Material` — say so and I will add it.

## Files

| file | change |
|---|---|
| `Config/GroundConfig.luau` | new `GROUND_TOP_SURFACE = Enum.SurfaceType.Studs` + type field; header broadened from "just the kerb" |
| `MapBuilder.server.luau` | new `asGround(part)` helper; applied at **10 call sites** (kerb, mat, central path, 2 side edges, back edge, slot pads, approach link, spur, belt) |
| `PlayerProfile.luau` | collect pad `TopSurface`: hardcoded `Smooth` → `GroundConfig.GROUND_TOP_SURFACE`; requires `GroundConfig` |

**`asGround` is opt-in at each call site, deliberately not applied in the part factory** — that factory
also builds stall roofs, posts, sign boards and the giant slime's ground patch, none of which are
ground. Wrapping explicitly keeps "what counts as ground" readable as a list instead of as a side
effect of which constructor something used.

**Nothing else changed.** No geometry, position, size, colour or material; the belt velocities and
ridge texture, the road's Z geometry, the baseplate, the road bands, the slime patch, the swings, signs,
chest, slimes and landmark are all untouched. `BottomSurface` on the collect pad stays `Smooth` — it
sits face-down on the mat and is never seen.

## What needs eyes in Studio

1. **Did anything actually change?** §c — if the paths look identical, the default was already `Studs`
   and that is fine.
2. **Does the belt still read as moving?** §a. This is the one I would revert first.
3. **Are the collect pads visibly studded, or did Neon flatten them?** §b. Flat is expected.
4. **Are the slot numbers still readable** over the relief? §a.
5. **Do you want the road bands too?** §Road bands — the objection turned out not to apply.
6. **Do you want the swing ground pads?** I excluded them under "the swings"; they are arguably ground.

## Still outstanding, unchanged

The chest's facing inference (`orientLockToFront`); the tier-11 overshoot slice; `game.rbxlx` still a
stale 6 Aug artifact; the two duplicate-function pairs; the 27-local remotes bootstrap; the
`GetNetworkPing()` one-way-vs-RTT question; the release camera's 35° tilt against an 88–210 stud
pullback putting the subject at the top edge of frame; the kerb's comment claiming MapBuilder leaves it
`CanCollide` off when it does not; and the road labels having grown 50% from the widening.
