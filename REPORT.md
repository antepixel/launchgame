# The sound system

**Branch `ladder-renumber`. Started from `2d28d1d9a186f91e20d3fbb1357dc15595975735`** (the tip of the
collect-system pass), clean tree.

Six commits, one per step, each independently revertable:

| step | commit | what |
|---|---|---|
| 1 | `1b4e6a8` | the registry and the one module allowed to create a `Sound` |
| 2 | `7a54545` | world-sound routing, the UI click hook, the conveyor, the mute toggle |
| 3 | `f7106e0` | the flight rush and the sweet-spot tick |
| 4 | `6a4e178` | the reward chain: box, doubling climb, tier-scaled reveal, chest |
| 5 | `24ede1f` | purchase and inventory confirmations |
| 6 | `7791d17` | verification, and two real gaps the tests found |

## Reproduce

```
lune run dev/analysis/verify_sound.luau      # 6a-6f, exits non-zero on failure
lune run dev/analysis/verify_offline.luau    # last pass, re-run: still passes
lune run dev/analysis/verify_ladder.luau     # unchanged, still passes
rojo build default.project.json -o <path>    # whole-tree syntax check
```

**30 checks pass.** Nothing in `dev/out/` was regenerated or touched.

---

# The headline: 23 entries, every id nil

**No asset ID was invented, guessed, or recalled.** All 23 entries ship with `id = nil` and are
silent. `SoundConfig` asserts at load that any id which *is* filled in is a well-formed
`rbxassetid://<digits>` string, so a typo'd or bare number fails loudly the moment it is added rather
than resolving to nothing.

**§6f is the shopping table** and is the most important output of this pass. It is at the bottom.

---

# 0. Survey

## 0a — there is genuinely no audio

`grep -rniE "sound|playbackloudness|rbxassetid" --include=*.luau src/` returned **5 hits, none of
them audio**:

| hit | verdict |
|---|---|
| `LaneConfig.luau:80` "That reasoning was **sound** in isolation" | English prose |
| `SlimeConfig.luau:255` "The reasoning for raising it was **sound**" | English prose |
| `ConveyorScroll.luau:22` "The reasoning was **sound** and the cost" | English prose |
| `PlayerProfile.luau:933` "not an error worth a **sound** or a message" | English prose (and now out of date — that path does have a sound; see §0b) |
| `PathConfig.luau:226` `BELT_RIDGE_TEXTURE_ASSET_ID = "rbxassetid://87264921429321"` | a **Texture**, not audio |

Also checked and clean: `default.project.json` contains no `Sound`, and none of the three `.rbxmx`
assets (`Chest`, `Sign`, `Slime`) contains a `Sound` instance. **Confirmed: this pass adds the first
audio in the project, and `SoundPlayer` contains the first `Instance.new("Sound")`.**

## 0b/0c/0d — every moment, where it fires, and who hears it

| moment | fires at | side | who hears | entry |
|---|---|---|---|---|
| swing mount | `LaunchServer:1840` `mountPlayer` | server | **nearby** | `WORLD_SWING_MOUNT` |
| bar sweep enters sweet spot | `LaunchClient:1633` render loop | client | self | `FLIGHT_SWEET_SPOT_ENTER` |
| release (apparatus) | `LaunchServer:2136` after `flightStartedRemote` | server | **nearby** | `WORLD_LAUNCH_RELEASE` |
| release (the flyer's own) | `LaunchClient:1094` `FlightStarted` | client | self | `FLIGHT_RELEASE` |
| flight | `LaunchClient:1099`→`1610` | client | self | `FLIGHT_WIND_LOOP` |
| landing, road | `LaunchServer:2360` landing handler | server | **nearby** | `WORLD_LANDING_ROAD` |
| landing, short | same, `flight.zone == "short"` | server | **nearby** | `WORLD_LANDING_SHORT` |
| landing, past (chest) | same, `flight.zone == "past"` | server | **nearby** | `WORLD_LANDING_PAST` |
| box appears | `LaunchClient:1209` `BoxStarted` | client | self | `REWARD_BOX_APPEAR` |
| box press | `LaunchServer:2494` `onBoxPress` | **server** | self | `REWARD_BOX_PRESS` |
| each doubling | `LaunchClient:1247` `BoxResult(false)` | client | self | `REWARD_BOX_DOUBLE` |
| box opens | `LaunchClient:1224` `BoxResult(true)` | client | self | `REWARD_BOX_OPEN` |
| slime reveal | `LaunchClient:1355` `SlimeRevealed` | client | self | `REWARD_SLIME_REVEAL` (+`_RARE`) |
| first-ever slime | same, `isNew` | client | self | `REWARD_SLIME_NEW` |
| chest lid opens | `LaunchServer:2690` `prompt.Triggered` | server | **nearby** | `WORLD_CHEST_OPEN` |
| chest reveal | `LaunchClient:1334` `ChestRevealStarted` | client | self | `REWARD_CHEST_REVEAL` |
| collect | `PlayerProfile:1010` `collectPending` | **server** | self | `UI_COLLECT` |
| upgrade bought | `InventoryClient` `upgradeResult(true)` | client | self | `UI_PURCHASE_SUCCESS` |
| swing tier bought | `ShopClient` `buyTierResult(true)` | client | self | `UI_PURCHASE_SUCCESS` |
| any purchase refused | both result remotes, `false` | client | self | `UI_ACTION_DENIED` |
| slime placed / removed / sold | `InventoryClient` `inventoryActionResult(true)` | client | self | `UI_INVENTORY_ACTION` |
| any UI button | `SoundClient`, `PlayerGui.DescendantAdded` | client | self | `UI_BUTTON_CLICK` |
| the conveyor | `SoundClient`, on `BeltNear`/`BeltFar` | client | **nearby** | `WORLD_CONVEYOR_LOOP` |

**0d, which should be public and which would be noise.** Six players share one map, so in principle
every launch, landing and chest is witnessable. The rule I applied: **a sound is public only if the
thing that caused it is visible from where it can be heard.**

- **Public (7 entries):** mount, release, the three landings, the chest lid, the conveyor. All have a
  visible cause — a person on a swing, a person hitting the ground, a lid moving, a belt running.
- **Private (16 entries):** everything in UI, FLIGHT and REWARD. Two reasons. The reward scene is
  framed by a camera move around one player's own frozen character and the box hangs at *their* arm's
  length — it is not visible to anyone else, so a sound from it would come from nowhere. And UI is
  worse: six players' button clicks and collect chimes, at 5–16-second cycles each, would be a
  continuous stream of unattributable noise. **`UI_COLLECT` is the sharpest case** — it fires on
  every cycle for every player, so broadcasting it would put five other people's cash registers in
  everyone's ears permanently.

## 0e — existing button affordances

**14 `TextButton` construction sites, no `ImageButton`s, and none of them has any click affordance
today** beyond `BackgroundColor3` changes:

`LaunchHud.luau:372` (release), `:411` (dismount); `DevPanelClient:182, 204, 304`;
`InventoryClient:45` (error), `:138` (open), `:194` (close), `:288` (rows);
`ShopClient:47` (error), `:97` (open), `:153` (close), `:231` (buy);
`SlimeUpgradeTagClient:340` (the world-space upgrade strips).

**None of those files was edited.** `SoundClient` connects `PlayerGui.DescendantAdded` and puts
`UI_BUTTON_CLICK` on every `GuiButton`'s **`Activated`** — chosen over `MouseButton1Click` because
`Activated` also fires for touch and gamepad, and this game is played on phones.

## 0f — `RespectFilteringEnabled`, and where sounds live

**It matters, and it is now set explicitly** (`SoundClient.client.luau`), rather than left at its
default. Every `Sound` in this game is created by a LocalScript. With this property false, Roblox's
legacy behaviour replicates a client's `Sound:Play()` outward — which would mean every player
hearing every other player's button clicks and collect chimes, i.e. exactly the failure the 2D/3D
split exists to prevent. Setting it `true` keeps client-initiated playback local, which is what makes
"2D means only I hear it" true rather than merely intended.

**What the existing split implies.** This codebase's rule is *server owns state, client renders* —
`LaunchRemoteLanes` recomputes other players' entire flights client-side from replicated attributes
rather than being driven per-frame by the server. Audio follows the same rule: **the server creates
no `Sound` at all.** It broadcasts a key and a position; each client builds the sound locally. See
§2 for the routing decision this drives.

---

# 1. The registry

**1a/1b — `SoundConfig.luau`**, 23 entries in four groups. Every entry carries `id`, `volume`,
`pitch`, `group`, `spatial`, `looped`, `maxLifetimeSeconds`, and (for 3D) `rollOffMinDistance` /
`rollOffMaxDistance`. Each has a **WHAT / LENGTH / CHARACTER** comment written to be shopped from —
what it is for, how long it may run, and what it should feel like.

Two things are asserted at load, because both are otherwise *silent* failures that nobody without
ears could diagnose:

- a `spatial` entry with no positive `rollOffMaxDistance` (it would fall back to default attenuation
  and be audible across a 3,000-stud map);
- a `group` name that is not one of the four (the sound would be created outside the mixer entirely).

**1c — one construction path, and how it is enforced.** `SoundPlayer.luau` is the only module that
calls `Instance.new("Sound")` or `Instance.new("SoundGroup")`. There is no language-level way to
prevent another script doing it, so the rule is kept by a **test**: `verify_sound.luau` walks all 54
`.luau` files under `src/`, greps for both constructors, and fails if any hit is outside
`SoundPlayer`. It also asserts `SoundPlayer` *does* contain them (6 sites), so the rule cannot pass
vacuously if the module is ever gutted.

```
scanned 54 .luau files under src/
[PASS] no Sound/SoundGroup constructed outside src/ReplicatedStorage/SoundPlayer.luau
[PASS] src/ReplicatedStorage/SoundPlayer.luau does construct them (6 sites) -- the rule is not vacuous
```

**1d — nil-safe by construction.** `resolve()` is the single gate. A key that does not exist and a
key whose `id` is nil both return `nil`, and every public function returns early on that — so
`play2D`, `playAt` and `startLoop` all no-op. `stopLoop(nil)` is a no-op too, which is what lets the
flight's three teardown paths call it unconditionally.

**Warned once per key, never per call.** `warned[key]` is set *before* the warn fires and never
cleared. The two message texts differ on purpose: an unknown key says "this is a typo at a call
site, not a missing asset", while a nil id says "silent by design — drop an id into
`SoundConfig.SOUNDS.<KEY>`". Demonstrated in §6e.

---

# 2. 2D versus 3D

## The routing decision

**Not one `Sound` is created on the server.** World sounds are broadcast by `SoundBroadcast.luau` as
a key plus a `Vector3` and built locally by each receiving client.

The obvious alternative — parent a `Sound` to a part on the server and let Roblox replicate it — is
fewer moving parts, and **I rejected it for one specific reason: the mute toggle.** Because every
`SoundGroup` is created locally, muting is a plain property write on an instance the server has never
heard of, and there is no mechanism by which one player's mute could reach another. With
server-created groups, muting would depend on the rule that a client's property writes to replicated
instances stay local — true, but a rule the whole feature would be silently resting on. Owning every
`Sound` on the client makes locality **structural** rather than incidental.

The cost: one `FireAllClients` per public event, carrying a short string and a `Vector3`. At six
players and a few events per second that is negligible. `SoundBroadcast`'s header names the point at
which it would stop being negligible (a much higher player cap) and what to do then.

**2a — UI is 2D**: parented to `SoundService` itself, which is what makes it non-positional — a
`Sound` with no `BasePart`/`Attachment` ancestor has nothing to attenuate from. All 16 UI, FLIGHT and
REWARD entries.

**2b — world is 3D**: `SoundPlayer.playAt` builds a throwaway holder part at the position, because
these fire at *places* rather than at instances that reliably persist. The holder is invisible,
`CanCollide = false`, **`CanTouch = false`** and `CanQuery = false` — the `CanTouch` part is
load-bearing, not tidiness: this project has exactly one `.Touched` in it (the collect pads), and a
stray touchable part appearing at a landing spot would be a gameplay change, which this pass is not
allowed to make.

## 2c — the map is ~3,000 studs, and `RollOffMode` is the whole answer

The road runs **Z −4.3 to −2,964.3** (74 bands × 40 studs); the plots sit at **Z 150**. Map length
end to end: **3,114 studs**. The deepest landing that can actually happen — tier 10's perfect launch
at **Z −3,061.7** — is **3,212 studs** from a base.

**Roblox's default `RollOffMode` is `Inverse`, under which `RollOffMaxDistance` is NOT a cutoff.**
Volume falls as roughly 1/d and `MaxDistance` is merely where attenuation stops getting worse — the
sound then holds that level indefinitely. On this map an `Inverse` sound is faintly audible from
anywhere, which is precisely the bug 2c asks about.

**`SoundPlayer` forces `Enum.RollOffMode.Linear`**, which falls to true silence at
`RollOffMaxDistance`. That is what makes every distance below a real, checkable boundary. *Rejected:*
`LinearSquare`, which also reaches zero but front-loads the falloff so hard these already-tight radii
would go inaudible almost immediately.

| entry | max audible | as % of the 3,212-stud landing-to-base distance |
|---|---|---|
| `WORLD_LANDING_ROAD` / `_SHORT` / `_PAST` | 250 | 7.8% |
| `WORLD_CHEST_OPEN` | 150 | 4.7% |
| `WORLD_LAUNCH_RELEASE` / `WORLD_SWING_MOUNT` | 120 | 3.7% |
| `WORLD_CONVEYOR_LOOP` | 40 | 1.2% |

**Confirmed: a landing at Z −2,744 is inaudible at the base.** The loudest-reaching world sound
covers 250 studs of a 3,114-stud map — 8%. Checked per entry by `verify_sound.luau` against the
figures re-derived from the real config, so it fails if either a distance or the map changes.

**Why 250 for landings specifically:** tiers land **320 studs apart** in Z. At 250 a player hears
landings only from others on **their own tier** — which is exactly the "someone landed near me"
signal worth having — and never from an adjacent tier. *Rejected:* 1,000, which would have made
mid-road landings audible back at the swings.

## 2d — six players, and what stacks

| entry | max simultaneous | assessment |
|---|---|---|
| `WORLD_LAUNCH_RELEASE`, `WORLD_SWING_MOUNT` | **3** | bounded by the 120-stud rolloff |
| `WORLD_LANDING_*` | up to 6 | only if all six are on the same tier and synchronised |
| `WORLD_CHEST_OPEN` | up to 6 | requires six simultaneous chest opens; vanishingly rare |
| `WORLD_CONVEYOR_LOOP` | 2 | fixed — one per belt half, always on |

**The swing area was the real risk and it is the one I acted on.** The six swings sit 60 studs apart
across a 360-stud row, so a sound reaching 300 studs would be audible from all six lanes — six
launch whooshes at once, every cycle, forever. **120 studs bounds it to three**: this lane and one
either side. Under Linear rolloff a listener at exactly 120 studs hears silence, so the lane two away
(120 studs) does not count — verified rather than assumed:

```
lane pitch 60 studs; WORLD_LAUNCH_RELEASE reaches 120 -> at most 3 of 6 lanes audible at once
```

*(This corrected a claim I had made: my first version of the check counted 5, using
`floor(reach/pitch)` and so including the boundary lane. The strict inequality is the right one and
3 is the true figure.)*

**Landings can stack six-deep in principle** and I deliberately did nothing about it. It requires all
six players on the same swing tier landing within ~0.5 s of each other, which the 5–16-second cycles
and independent bar timing make rare; and when it does happen, six people landing together *is* the
event. Suppressing it would need a per-position rate limiter — real complexity for a case that is
arguably a feature. Flagged rather than fixed.

---

# 3. The flight

## 3a — the rush, and its teardown

One looping 2D sound on the flying player's own client, alive for exactly the flight: **2 s at tier
1, 11 s at tier 10** — the longest continuous moment in the game.

**Hooked at four sites, three of them teardown**, all idempotent and nil-tolerant so none has to
coordinate with the others:

| # | site | catches |
|---|---|---|
| — | `FlightStarted` handler | *starts* it, after a defensive stop so a second flight cannot orphan the first's loop |
| 1 | the landing frame (`u >= 1`) | an **ordinary landing** |
| 2 | `resetFlightState()` | **death, disconnect, mid-flight dismount, cancellation** |
| 3 | `setGrounded(true)` | belt-and-braces: every route back to neutral |

**Site 2 is the one that answers "is it the same path that already cancels the flight state?" — yes,
exactly.** `resetFlightState` has precisely one caller: the `resetReadyRemote` handler. And
`LaunchServer.clearActiveRider` **reuses `resetReadyRemote` as its death/disconnect cancellation
signal** (its own comment says so: *"This is a DEATH/DISCONNECT CANCELLATION signal, not a landing
signal — reusing resetReadyRemote … because its own OnClientEvent handler already does exactly
'return to neutral'"*). So the single line in `resetFlightState` inherits every cancellation route
the flight state itself already has.

**Site 1 cannot be folded into site 2.** `resetReadyRemote` arrives `RESET_DELAY` (0.75 s) *after*
the landing, so relying on it alone would leave the rush droning for three-quarters of a second after
the player had visibly hit the ground — on every single flight.

## 3b — pitch and volume track speed, not time

Speed is derived from the **derivative of the same trajectory the render loop already positions the
character with**:

```
z(u) = startZ − distance·u          → dz/du = −distance
y(u) = startY + (topY−startY)·u
       + arch·4·u·(1−u)             → dy/du = (topY−startY) + arch·4·(1−2u)
speed = |(dy/du, dz/du)| / duration
```

Read-only — it derives a number *from* the flight formulas and changes nothing about them. **The
vertical term is why this is worth doing:** the rush dips at the apex and swells again on the
descent, so the sound follows the arc rather than merely counting down.

**Measured instantaneous 3D speed across all ten tiers: 100.0 to 296.1 studs/s.** Rounded outward to
100/300 so the mapping never clamps in play.

| | pitch | volume |
|---|---|---|
| at 100 studs/s | 0.85 | 0.40 |
| at 300 studs/s | 1.30 | 1.00 |

**Range at both ends of the ladder:**

| | speed over the flight | pitch | volume |
|---|---|---|---|
| tier 1 | 100.0 → 171.7 | 0.85 → 1.01 | 0.40 → 0.68 |
| tier 10 | 279.2 → 296.1 (dips to 279 at apex) | 1.25 → 1.29 | 0.94 → 0.98 |

So a tier-1 flight is a low, quiet whoosh that swells noticeably; a tier-10 flight is a loud, high,
near-constant rush. *Rejected:* mapping to a wider 0.5–2.0 pitch span, which would make the top tier
a shriek and the bottom a rumble — two different sounds rather than one sound moving.

## 3c — the bar sweep: wired, as an edge

**I wired it, and I think it helps rather than clutters** — but only in the form I chose.

It fires on the frame the bar crosses **into** the sweet-spot window and not again until it has left
— **one tick per 2.4-second sweep**, not a tone for as long as you are inside. It uses
`LaunchFormulas.inSweetSpot`, the same predicate the grading uses, so the tick can never mark a
window the multiplier disagrees with.

**Why it earns its place:** the full window is 0.288 s, but only **0.072 s** of that reaches tier
10's snap threshold of 1.95. A 72-millisecond target is genuinely hard to hit by eye, and an audible
edge is something a player can act on by reflex rather than by watching.

**What I did NOT do, and this is the version that would clutter:** a rising tone tracking the bar
continuously. It would run for the entire time any player sits on a swing — which is most of the
game — and it would be a pitch-varying tone competing with the flight rush for the same perceptual
space. No entry exists for it; the one that exists is documented as an edge tick and nothing else.

The starting state is `wasInSweetSpot = true`, so a rider who mounts with the bar *already* inside
the window does not get a tick for a crossing that never happened.

## 3d — the three landing zones do not sound alike

Three separate entries, selected from **`flight.zone`** — the enum the server itself branched on when
it decided whether this landing earns a box, nothing, or a chest. Read, not re-derived, so the sound
can never disagree with the outcome.

- `WORLD_LANDING_ROAD` — solid, weighty, "arriving".
- `WORLD_LANDING_SHORT` — duller and flatter, no ring. Recognisably worse without being a punishment;
  the player already knows and the HUD already says so.
- `WORLD_LANDING_PAST` — triumphant, with a bright ascending tail, and allowed to be longer (0.6–1.2 s)
  because nothing follows it immediately.

---

# 4. The reward chain

## 4a — box, press, and the doubling climb

**The press is played from the SERVER, and that was a forced choice worth explaining.** Every route
into a press — Space, tap-anywhere, and **the `ClickDetector` on the box itself, which lives inside
`LaunchRewardScene.luau`** — converges on `boxPressRemote`, so `onBoxPress` is the only place that
sees all of them.

The client-side alternative was hooking `RewardScene.press()` at its two `LaunchClient` call sites.
That would have been latency-free, but it would have **missed the `ClickDetector` route entirely** —
clicking the box would be silent while clicking beside it was not. Inconsistent is worse than late,
so the press costs one round trip. It buys something real: placed after the rate-limit guard, it
fires only for presses the server **accepted**, so it never promises a roll that was swallowed.

**The pitch climb.** `+0.06` per link, **ceiling 2.0** (one octave). The chain is geometric at
`BOX_DOUBLE_CHANCE = 0.55`:

| | doublings |
|---|---|
| mean | 1.22 |
| 99% of boxes stop by | 7 |
| 99.9% by | 11 |
| **99.99% by** | **15** |

**The longest realistic chain is ~15.** At +0.06 the ceiling is reached on the **18th** doubling
(1 + 0.06×17 = 2.02 → clamped), which occurs about **once in 47,000 boxes** (0.55¹⁸ = 2.1×10⁻⁵).
**Past that it holds at 2.0** rather than continuing into inaudibility. So in normal play the climb
never runs out of range, and the monster chain that does simply stops rising. *Rejected:* a
multiplicative climb (×1.06/link), which sounds identical for the first few links and then runs away
fastest on exactly the chains most worth hearing.

The counter resets on `BoxStarted`, not on `BoxResult`, so it tracks one box from first press to open
and cannot inherit a previous box's height. The first doubling plays at the entry's own pitch, so the
climb is audible *as* a climb from the second link.

## 4b — the reveal, scaled by tier

**By tier, not by luck**, as instructed — and the reason is that they genuinely diverge: a huge luck
roll can still land a Common. The player is looking at the slime, so the sound must describe the
slime.

Rarer reads as **lower, louder**, across the 8 tiers (`Common … Divine`):

| | tier 1 (Common) | tier 8 (Divine) |
|---|---|---|
| pitch | 1.15 | 0.90 |
| volume scale | 0.85 | 1.15 |

Both ramps are derived from `#SlimeConfig.SLIME_TIER_NAMES` rather than hardcoded, so adding a tier
rescales the ramp instead of leaving the top two indistinguishable.

**Pitch alone across eight tiers is a gradient nobody can name**, so `REWARD_SLIME_REVEAL_RARE` is
layered on top for **tiers ≥ 6** (Mythic, Secret, Divine). That makes the best pulls *categorically*
different, not merely lower. Threshold 6 rather than 8 deliberately: a fanfare that fires only on the
single rarest tier would almost never be heard.

`REWARD_SLIME_NEW` layers on a slime this player has never seen — `isNew` is already on the wire, so
it costs nothing to know. It fires on the chest path too: a *first* Divine out of a chest deserves it
most.

## 4c — the chest

`REWARD_CHEST_REVEAL` **replaces** the ordinary reveal on a chest pull rather than stacking with it.
The chest table is 20% Divine, so layering box-reveal + rarity fanfare + chest swell would put three
celebratory sounds together on most opens. A flag set by `ChestRevealStarted` and consumed by the
`SlimeRevealed` that follows one line later does the swap; it is also cleared in `setGrounded`, so a
leak could never silence a *later* reveal — the failure mode there would be a silent reveal, exactly
the class of bug nobody can hear their way to.

It plays over the 3D `WORLD_CHEST_OPEN` broadcast from the lid, deliberately in a different register:
that one is wood and metal, this one is light and air.

## 4d — collect

**0.15–0.25 s specified, and the ceiling is the important part of the entry.** The return pad sits on
the post-flight walk, so this fires **every cycle** — roughly every 5 to 16 seconds, indefinitely,
hundreds of times an hour. The entry's comment says so explicitly and directs: single soft coin or
register ding, short decay, no tail, no melody, nothing that resolves — *a sound that goes somewhere
is a sound you notice, and this one must become texture.* Volume 0.45, the second-quietest thing in
the UI group.

---

# 5. Mixing and control

## 5a — groups and levels

Four `SoundGroup`s **nested inside one master**, so the master multiplies over all four rather than
being a fifth sibling controlling nothing.

| group | volume | reasoning |
|---|---|---|
| REWARD | **0.85** | the payoff, short, at most once per cycle — should sit on top |
| UI | **0.60** | crisp confirmations, but clicks fire constantly while a menu is open |
| WORLD | **0.50** | mostly other people's events; scenery, not competition |
| FLIGHT | **0.30** | the only category that runs **continuously for up to 11 s** |

**FLIGHT at 0.30 is the number most likely to need retuning and the one with the clearest argument.**
A rush loop mixed at one-shot level would dominate the single longest moment in the game and mask the
landing that ends it. The collect chime and the flight loop are the two sounds that repeat most, and
both sit well below the one-shot purchase chime — which is exactly what 5a asks for.

## 5b — the mute toggle

**There is no settings system in this project, and this does not invent one.** `PlayerProfile`
persists gameplay state; there is no client-preferences store, no settings panel, and nothing that
survives a rejoin except the profile.

So the mute is **session-only**, stated rather than hidden: a player who mutes is unmuted on their
next join. *Rejected:* adding a `muted` field to the save shape plus a remote to set it — that puts a
client preference into the gameplay save schema and adds a write path to a profile system built last
pass, for one boolean. If audio settings ever grow past that (per-group sliders), they want their own
store and this becomes its first field.

**Both a keybind and a button**, matching how this codebase already works: `MUTE_TOGGLE_KEYCODE` in
config read at one `InputBegan` site (`DevConfig.TOGGLE_KEYCODE`'s pattern), plus an on-screen 🔊/🔇
button, because a keybind alone excludes every touch player. It continues the existing top-right
stack (shop at y-offset 0, inventory at 54, this at 108) and carries both `GuiObject` traps —
`BorderSizePixel = 0` and `TextStrokeTransparency = 1`.

It drives the **master group only**, never the four category volumes, so unmuting restores exactly
the authored mix rather than flattening everything to one level.

## 5c — no collision with the reward scene, and `LaunchRewardScene` was not opened

**Not opened.** Every reward hook is in `LaunchClient.client.luau`, which already handles all five
reward remotes (`BoxStarted`, `BoxResult`, `ChestRevealStarted`, `SlimeRevealed`, `ResetReady`) — the
scene module is only *called* from there. The one thing that genuinely could not be reached from
outside was the box's own `ClickDetector`, which is why the press is played server-side (§4a).

**The timeline, checked against the real constants:**

| t | scene event | sound | length |
|---|---|---|---|
| 0 | box appears, camera moves in | `REWARD_BOX_APPEAR` | 0.4–0.8 s |
| … | each press (≥ `BOX_PRESS_COOLDOWN_SECONDS` = 0.25 apart) | `REWARD_BOX_PRESS` | **0.08–0.15 s** |
| … | each doubling | `REWARD_BOX_DOUBLE` | 0.15–0.3 s |
| 0 | open → thrash (`BOX_THRASH_SECONDS` = 0.25) → burst (`BOX_OPEN_BURST_SECONDS` = 0.3) | `REWARD_BOX_OPEN` | **0.3–0.6 s** |
| +0.6 | slime reveal (`REVEAL_BOX_TO_SLIME_DELAY_SECONDS` = 0.6) | `REWARD_SLIME_REVEAL` | 0.5–0.9 s |

**Two length ceilings are set by these constants and are recorded in the entries themselves**: the
press must be under 0.25 s or presses overlap each other, and the open must be under 0.6 s or it is
still ringing when the slime arrives. Nothing plays during the camera move itself except the box
appearing, which is what the camera is moving toward.

---

# 6. Verification

`lune run dev/analysis/verify_sound.luau` — **VERIFY PASSED, 30 checks.**

Its header states the boundary first: this checks **structure**, not sound. It cannot verify that any
asset is appropriate, audible or correctly mixed — those need ears and a filled-in registry.

**6a — every id nil, and the game runs with zero audio errors.** Method: load the real `SoundConfig`
through the shim (which runs its load-time asserts), then check all 23 `id` fields. *How this was
tested without playtesting:* three independent layers — `rojo build` parses the whole tree after
every step (syntax); the shim loads the real `SoundConfig` and `SoundPlayer` and calls into them
(runtime, for the nil path); and every call site is a bare added statement beside a decision already
made, verified by the additive-only diff check below.

```
SoundConfig loaded: 23 entries across 4 groups
[PASS] all 23 entries have id = nil
```

**6b — no `Instance.new("Sound")` outside `SoundPlayer`.** Quoted in §1c. 54 files scanned, 0
offenders, 6 sites inside the allowed module.

**6c — the flight loop's teardown.** Method: read the real client source for the call count and the
three contexts.

```
[PASS] stopFlightWind appears 5 times (1 definition + 4 call sites); found 5
[PASS] teardown context present: resetFlightState -- every cancellation via clearActiveRider's resetReadyRemote
[PASS] teardown context present: setGrounded -- the catch-all every route back to neutral funnels through
[PASS] teardown context present: the landing frame -- an ordinary landing, which cannot wait for ResetReady
[PASS] teardown context present: FlightStarted -- the defensive stop before starting a new loop
[PASS] stopLoop(nil) is a safe no-op, and is safe to call repeatedly
```

The four exit paths walked: **normal landing** → the `u >= 1` branch, line 1610. **Death** →
`clearActiveRider` → `resetReadyRemote` → `resetFlightState`, line 535. **Disconnect** → same, guarded
on `player.Parent` server-side. **Mid-flight dismount/cancellation** → same. Plus `setGrounded` under
all of them.

**6d — reach per world sound.** Table in §2c. Every entry checked against the 3,212-stud
deepest-landing-to-base distance and the 3,114-stud map length, both re-derived from the real config
rather than quoted. Plus a check that `SoundPlayer` forces `RollOffMode.Linear`, without which none
of the distances would be a real cutoff.

**6e — warned once per key.** Method: call the real `SoundPlayer` 100 times across two keys — one
that does not exist, one that exists with a nil id — and count.

```
100 calls across 2 keys (50 each): warned keys went 0 -> 2
[PASS] 100 calls with a bad key and an unfilled key raised no error
[PASS] exactly 2 new warnings for 2 distinct keys over 100 calls; got 2
[PASS] 25 further calls with an already-warned key add no warnings at all
[PASS] play2D returns nil for an unknown key
[PASS] play2D returns nil for an entry whose id is still unset
[PASS] startLoop returns nil for an unfilled entry, which stopLoop then accepts
```

**Additive-only.** A `git diff --numstat` against `2d28d1d` confirms every pre-existing file this
pass touched **gained lines and lost none** — a sound call is additive; a changed condition or a
moved call would not be. This is the mechanised form of "no gameplay behaviour changes at all".

## Two real bugs the tests found

Both were found by writing the checks, not by reasoning, and both are fixed in `7791d17`.

1. **`dev/rbxshim.luau` never provided `warn`.** It is a Roblox global, and several real modules call
   it — `PlayerProfile`'s load-failure path, `BaseClient`'s missing-base warning, `SoundPlayer`'s
   warn-once. Any analysis script that reached one of those lines died on *"attempt to call a nil
   value"*. Now routed to `print` with a `[warn]` prefix, which is also what lets a test observe
   warnings at all.

2. **The working tree is CRLF, so every source-scanning needle written with `\n` silently matched
   nothing.** This already affected the *previous* pass: `verify_offline.luau`'s `bodyOf()`
   terminator `"\nend\n"` never matched, so it scanned to end-of-file instead of to the end of the
   function. It passed either way — overshooting only made it stricter — but it was passing for the
   wrong reason. Source reads now go through a new `common.readSource`, which normalises line
   endings, so any future structural check gets it right by default. `verify_offline` re-runs and
   still passes with the terminator now actually working.

I also corrected two of my own claims: `stopFlightWind` has four call sites, not three; and a
120-stud launch reaches **three** lanes, not five — under Linear rolloff a listener exactly at
`RollOffMaxDistance` hears silence, so the boundary lane does not count.

---

# 6f. THE REGISTRY — the shopping table

**All 23 ids are nil.** Fill any `id` in `SoundConfig.SOUNDS` and it starts playing everywhere it is
already wired, with no code change. Each entry's own comment in `SoundConfig.luau` carries this same
guidance in full.

### UI — 2D, own client only

| entry | vol | length | character |
|---|---|---|---|
| `UI_BUTTON_CLICK` | 0.35 | **0.05–0.12 s** | Soft, neutral, non-musical click. Fires more than anything else in the game — must have **no pitch identity**; anything melodic becomes maddening. |
| `UI_PURCHASE_SUCCESS` | 0.70 | 0.4–0.8 s | Ascending 2–3 note confirmation. Warm, not triumphant — must not compete with the reveal. |
| `UI_ACTION_DENIED` | 0.50 | 0.15–0.3 s | Short, low, soft "no". Dull thud or descending two-note. **Not** harsh or buzzer-like — players hit this constantly while saving up. |
| `UI_INVENTORY_ACTION` | 0.55 | 0.2–0.4 s | Soft organic "plop" — something physical set down. Slimes are the subject, so wet/squishy beats a UI beep. Covers place, remove and sell. |
| `UI_COLLECT` | 0.45 | **0.15–0.25 s** | Single soft coin/register ding. **Fires every cycle, hundreds of times an hour.** Short decay, no tail, no melody. If in doubt pick the quieter, duller option. |

### FLIGHT — 2D, flying player only

| entry | vol | length | character |
|---|---|---|---|
| `FLIGHT_WIND_LOOP` | 1.00 | **2–4 s, seamless loop** | Broadband wind/air rush. Steady, no melody, no pitch centre. Pitched live 0.85–1.30× — pick **noise, not a tone**. No gust or flutter: any recognisable event gives away the loop point, which repeats 3–5× at tier 10. |
| `FLIGHT_RELEASE` | 0.80 | 0.3–0.6 s | Sharp upward whoosh. The most physical moment in the game; should feel like effort released. Must decay before the loop establishes. |
| `FLIGHT_SWEET_SPOT_ENTER` | 0.40 | **0.04–0.08 s** | Single dry tick or rimshot. Marks an **edge** — not a tone, emphatically not a rising sweep. Repeats every 2.4 s while anyone rides, so it must be tiny. |

### WORLD — 3D, heard by nearby players

| entry | vol | rolloff | length | character |
|---|---|---|---|---|
| `WORLD_LANDING_ROAD` | 0.90 | 15–250 | 0.3–0.5 s | Solid, weighty impact. Dust and body, not a crash. Reads as *arriving*. |
| `WORLD_LANDING_SHORT` | 0.80 | 15–250 | 0.3–0.5 s | Duller, flatter, no ring. A soft flop into dirt. Recognisably worse without being a punishment. |
| `WORLD_LANDING_PAST` | 1.00 | 20–250 | 0.6–1.2 s | Triumphant arrival — impact with a bright ascending tail or shimmer. Unmistakably the good one within a tenth of a second. |
| `WORLD_LAUNCH_RELEASE` | 0.70 | 10–120 | 0.3–0.5 s | Rope and timber under load, then release. Mechanical and woody — the air is the flyer's sound, this is the apparatus. |
| `WORLD_SWING_MOUNT` | 0.40 | 10–120 | 0.15–0.3 s | Light creak and settle; weight arriving on a seat. Very quiet — fires every cycle for every player, so it is texture. |
| `WORLD_CHEST_OPEN` | 1.00 | 20–150 | 0.8–1.5 s | Heavy wooden lid with metal fittings, hinges under strain, then a bright magical bloom. **Two-part: mechanism, then payoff.** The sound the whole ladder exists to reach. |
| `WORLD_CONVEYOR_LOOP` | 0.35 | 8–40 | **2–5 s, seamless loop** | Low mechanical rumble with faint roller texture. **No squeak, no rhythmic clank** — this is the only always-on sound in the game and anything periodic will drive players mad. |

### REWARD — 2D, rewarded player only

| entry | vol | length | character |
|---|---|---|---|
| `REWARD_BOX_APPEAR` | 0.80 | 0.4–0.8 s | Magical appear — shimmer with a soft impact under it. Anticipatory; asks the question the press answers. |
| `REWARD_BOX_PRESS` | 0.60 | **0.08–0.15 s** | Dull thump, knuckles on a crate. Deliberately unrewarding — the reward is the doubling that may follow. Must be under the 0.25 s press cooldown. |
| `REWARD_BOX_DOUBLE` | 0.75 | 0.15–0.3 s | Bright rising "ching" or arpeggio step. **Transposed up to an octave by the chain**, so it needs a clear pitch centre — a bell or pluck, not noise. The game's escalation sound. |
| `REWARD_BOX_OPEN` | 0.90 | **0.3–0.6 s** | Crack and burst — something breaking open and scattering. Decisive. Must be clear of the 0.6 s reveal delay. |
| `REWARD_SLIME_REVEAL` | 0.80 | 0.5–0.9 s | Soft organic rise with a bright bloom. **Pitched 0.90–1.15 by tier**, so avoid strong formants or a recognisable instrument that will sound obviously slowed. |
| `REWARD_SLIME_REVEAL_RARE` | 0.95 | 1.0–2.0 s | Fanfare or choral swell, unashamedly celebratory. Layered on tiers 6–8. The sound a player should recognise before reading the name. |
| `REWARD_SLIME_NEW` | 0.70 | 0.4–0.8 s | Short discovery sting, distinct from the rarity fanfare — both can fire together on a first Divine. Keep it thin and high so it sits **on top**. |
| `REWARD_CHEST_REVEAL` | 1.00 | 1.5–2.5 s | Grand ascending swell — the biggest sound in the file. Plays over `WORLD_CHEST_OPEN`, so occupy a different register: that one is wood and metal, this is light and air. |

---

# 7. Deliberately left silent

Per the brief's "if a moment would be better silent, say so":

- **The income tick.** Fires every second, per player, forever. It would be the single most grating
  sound possible, and the pot already has a visible readout.
- **Dismount.** The inverse of mounting, but rare and deliberate, and `WORLD_SWING_MOUNT` already
  covers seat transitions. A second creak would double the swing-area noise for no new information.
- **Reveal dismiss / click-to-return.** The reveal has already resolved audibly; a chime for
  *closing* it would be a sound for ending a sound.
- **Death and respawn.** There is no combat and death is not a designed state here; it is an
  interruption, and interruptions should not be celebrated or stung.
- **A continuous bar-sweep tone** — see §3c. The edge tick replaces it deliberately.
- **A `LaunchRewardScene`-internal press hook** — not silent, but moved server-side rather than
  reached by opening that file. See §4a.

---

# 8. What I did not touch

Per MUST NOT CHANGE, verified: `SlimeRoll.luau`, the income tables, weight ratios, luck constants and
spreads — not opened. The chest table, the ladder, every price, the upgrade curve, `SLOT_COUNT` —
untouched; `verify_ladder.luau` re-run and **PASSED**. The flight formulas including the tier-keyed
duration, the arch, the ping compensation and the sweet-spot constants — untouched; the flight sound
*reads* the trajectory's derivative and writes nothing back. The collect system from last pass — the
pot, the accrual, the pads, the debounce — untouched; `verify_offline.luau` re-run and **PASSED**.
**`LaunchRewardScene.luau` — not opened.** Every file in `dev/out/` — nothing regenerated, nothing
edited.

**No gameplay behaviour changed.** Every call added is a bare notification placed beside a decision
already made, and the additive-only diff check in §6 is the mechanised proof: every pre-existing file
touched gained lines and lost none. No sound required moving or re-timing anything — nothing to
report under that heading.

No gamepass, no doubling reward, no group-join button, no monetisation. The levelling-discovery
problem is untouched. `start_playtest`/`stop_playtest` were never called.
