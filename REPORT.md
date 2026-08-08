# Distance readout: back on the HUD, whole studs, "???" past the road

Three changes, all in the client's display layer. **No server file touched, and nothing about what
the distance IS changed** — only how it is written.

**One formatter now serves all three display sites.** They were two `string.format("%.1f studs", …)`
calls and a hand-written `"0.0 studs"` literal — three places to keep in step, and the reason a
"no decimals" change could otherwise have left one behind. §2.

**Rounded, not truncated**, and the reason is agreement between two labels the player sees one after
the other, not just accuracy. §2.

**"???" is gated on the zone**, the same `"past"` the headline above it already branches on — not on
a distance threshold, which would be a second hand-maintained copy of the road's length. §3.

**The Studio diagnostic survives exactly where it was useful:** on screen, appended in brackets, on
the one landing that hides it from players. §3.

**Verified:** all five client files parse; `math.round` confirmed present and the formatter's output
checked against the boundary values.

---

## 1. Back on the normal HUD

The `RunService:IsStudio()` gate at `distanceSubLabel`'s construction is gone. The label keeps its
default `Visible` and shows for everyone, on every landing, as it did before that pass.

```lua
-- was
distanceSubLabel.Visible = RunService:IsStudio()
distanceSubLabel.Parent = flightHudFrame
-- now
distanceSubLabel.Parent = flightHudFrame
```

The comment block that justified the gate is replaced with a short note recording that the gate
existed and where the diagnostic value went instead. `RunService` stays required — §3 still uses it.

Nothing else about the label moved: same position, size, font, colour, stroke, and the same parent,
so it is still hidden and shown with the rest of `flightHudFrame`.

## 2. No decimals — rounded

**Every distance on screen now goes through one function:**

```lua
local function distanceText(distance: number): string
	return string.format("%d studs", math.round(distance))
end
```

### The three places changed

| # | site | before | after |
|---|---|---|---|
| 1 | `LaunchHud.setLiveDistance` — the live in-flight countup, every frame, on the headline | `string.format("%.1f studs", distance)` | `distanceText(distance)` |
| 2 | `LaunchHud.showLandingResult` — the final sub-line | `string.format("%.1f studs", distance)` | `distanceText(distance)` (or `???`, §3) |
| 3 | `LaunchClient.doRelease` — the zero written at the instant of release | `Hud.setDistanceText("0.0 studs")` | `Hud.setLiveDistance(0)` |

The third was the one that made this worth centralising: it was a **string literal**, so it would
have kept saying `0.0 studs` after both format calls were fixed, and nothing would have caught it.
Routing it through `setLiveDistance(0)` makes it impossible for that to happen again.
`Hud.setDistanceText` had no other caller and is deleted, along with its export-table entry.

`resetFlightHudText` blanks the sub-line to `""` and is unaffected.

### Rounded, and why

`math.round`, verified present and checked at the boundaries:

```
0.0000     -> 0 studs        2963.6000  -> 2964 studs
0.4000     -> 0 studs        2964.4000  -> 2964 studs
0.5000     -> 1 studs        3071.0400  -> 3071 studs
3070.9998  -> 3071 studs     1535.5200  -> 1536 studs
```

Two reasons, and the second is the real one:

1. **The sub-line is a measurement of a finished flight**, so rounding is simply the smaller error —
   at most half a stud out, against a whole stud for truncation.
2. **The countup and the final readout are different labels the player sees in sequence**, so they
   have to agree at the boundary. One rule in one function guarantees that. The old arrangement — a
   formatted countup and a separate literal reset — is exactly the shape that lets two readouts
   disagree.

The usual argument for truncating a *counter* — never claim distance the player has not yet
travelled — is real but costs at most half a stud in 3,071, for a fraction of the final frame. Not
visible, and not worth a second rounding rule that would reintroduce (2).

## 3. "???" past the road

```lua
if zone == "past" then
	distanceSubLabel.Text = if RunService:IsStudio()
		then string.format("??? (%s)", distanceText(distance))
		else "???"
else
	distanceSubLabel.Text = distanceText(distance)
end
```

**Hooked in `LaunchHud.showLandingResult`, on the `zone` parameter** — the same value the headline
three lines above already branches on, which arrives from `LaunchClient`'s `landingBandZone` and is
the client's mirror of `bandLuckForLandingZ`'s own `"short" | "road" | "past"` enum.

Gating on the zone rather than on a distance threshold matters for a specific reason: a threshold
would be a **second copy of the road's total length** (`#LuckCurve.VALUES × RUNWAY_BAND_LENGTH_STUDS`,
plus the launch origin's offset), maintained by hand, free to drift from the one the server actually
scores against. The zone is that decision, already made, by the function that owns it. It also means
the headline and the sub-line can never describe different landings — one branch, one condition.

It reads as **off the map rather than as a bigger number**, which is what the landing is: past the
last band, where the road's measurement stops and there is nothing left to count against.

### The Studio number: on screen, in brackets

In Studio the same line reads `??? (3071 studs)`; in a published server it reads `???`.

**On screen rather than printed or behind the dev panel, deliberately.** The value's whole worth is
that it is the SERVER's own authoritative distance, arriving on `FlightStarted` — and it is what
made the ping bug findable: the client/server phase gap was caught by *reading the number off the
screen mid-session and noticing it was not 3071*. A log line is only found by someone already
looking for it, and a dev-panel field is only read by someone who opened the panel. Neither would
have caught that bug.

And the `"past"` landing is precisely the case worth watching — it is the tier-11 chest landing, the
one whose distance is most likely to be wrong and hardest to eyeball from the world. Hiding the
number there and nowhere else would have removed it from the one place it earns its keep.

## 4. Files changed

| file | change |
|---|---|
| `LaunchClient/LaunchHud.luau` | Studio gate removed; `distanceText` added; `setLiveDistance` and `showLandingResult` route through it; `"???"` + Studio suffix on `"past"`; `setDistanceText` deleted (function and export) |
| `LaunchClient.client.luau` | `Hud.setDistanceText("0.0 studs")` → `Hud.setLiveDistance(0)` |

A repo-wide grep for `%.1f studs`, `0.0 studs` and `setDistanceText` returns only comments recording
what those used to be.

**Untouched:** the outcome word and its rainbow, the HUD's visibility gating and fade timing, the
chest reveal and model, the roll table, tier 11's reach and snap thresholds, ping compensation, the
multiplier-to-distance mapping, and everything else on the exclusion list. `flightDistance` itself is
unchanged — this pass only formats it.

## 5. Worth knowing

- **A luckless landing shows a distance now.** It always did before the Studio gate, and it still
  reads `"No luck (short of the road)"` over e.g. `"2410 studs"` — correct, and the same as before
  that pass.
- **The `"past"` headline stays blank** (from the previous pass), so a chest landing now shows an
  empty headline over `???`. That is the intended reading — the player is standing on the platform
  looking at a chest — but it is the composition to glance at first.
- **No playtest**, per instruction.

## 6. Still outstanding, unchanged

The chest's facing inference (`orientLockToFront`); the tier-11 overshoot slice; `game.rbxlx` still a
stale 6 Aug artifact; the two duplicate-function pairs; the 27-local remotes bootstrap; and the
`GetNetworkPing()` one-way-vs-RTT question.
