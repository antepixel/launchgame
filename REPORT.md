# Per-slot collection, and the offline retune

Started from `59e38c215a3a48fb23e3268b3828754431f937fa` ("Report the sound system
pass"), on `ladder-renumber`.

One pending pot per player became ten — one per slot, banked at that slime's own
pad. The return pad on the approach link is gone. Offline earnings dropped from
uncapped-rate/8-hour to 22% of rate, capped at 12 hours.

Every measurement below is reproducible with:

```
lune run dev/analysis/verify_offline.luau
```

which prints only and writes nothing to `dev/out/`.

---

## STEP 0 — SURVEY

### 0a. The auto-mount trap — checked first, and there is no trap

`checkProximityMounts` (`src/ServerScriptService/LaunchServer.server.luau:2242`)
is called every frame from the Heartbeat connection at
`LaunchServer.server.luau:2274`. It is **not** gated by a flag, a cooldown, or a
timer. Its only gates, per player, are:

- `states[player] ~= "grounded"` → skip (`:2244`)
- no character / dead humanoid / no root part → skip (`:2247-2258`)
- no pivot or no lane index → skip (`:2259-2263`)
- then: horizontal (X/Z, Y dropped) distance from that player's own pivot
  `<= LaunchConfig.SWING_MOUNT_RADIUS_STUDS` (18) → `mountPlayer` (`:2266-2270`)

So yes — it fires continuously, every frame, for any grounded player inside the
circle. **But a dismounted player can walk away freely, and the reason is
geometry, not gating.**

`onDismount` (`:1557`) and `onReturnToSwing` (`:1501`) both end at
`moveToLaneReturn` (`:1299`), which places the character at
`LaneConfig.SWING_PIVOT_Z + LaunchConfig.SWING_RETURN_CLEARANCE_STUDS`
= 30 + 22 = **Z 52** (`:1304`), on the lane's own X. The mount circle reaches
Z 48. The player is dropped 4 studs **outside** it.

The base is at **higher Z** — `BaseConfig.BASE_SLOT_Z_START = 117`, plot centre
150, back edge 192 (`BaseConfig.luau:247`, `:407`, `:440`). The swing pivot is at
Z 30. So the walk from the return position to the base runs in **+Z, directly
away from the pivot**: the measured distance increases monotonically from 22
studs at the first step and never comes back inside 18. There is no fight to
lose.

Walking the other way (−Z) re-seats the player at Z 48, which is the intended
auto-mount and unchanged by this pass.

Verified as an assertion rather than prose — `verify_offline.luau` §6h checks
both `returnZ > mountZ` and `BASE_SLOT_Z_START > returnZ`.

**No STOP condition. Nothing in this prompt's assumptions was contradicted.**

### 0b. The route from the swing to the base

| leg | Z span | surface | built by |
|---|---|---|---|
| return position → approach link end | 52 → 67 | static concrete, `APPROACH_LINK_WIDTH` 9 | `PathConfig:115-117` |
| the conveyor | 67 → 85 | two 9-deep belt halves | `PathConfig:165-167` |
| spur | 85 → 108 | static, 10 wide | `PathConfig:138-140` |
| plot mat + central path | 108 → 192 | static, path 10 wide | `BaseConfig:407,418` |
| the ten collect pads | 117 → 173 | two columns at baseX ∓8 | `BaseGeometry.collectPadPlacement` |

**The conveyor helps neither direction.** `MapBuilder.server.luau:304` sets
`belt.AssemblyLinearVelocity = Vector3.new(half.direction * BELT_SPEED_STUDS_PER_SECOND, 0, 0)`
— **X only**. It is a cross-map shuttle between the two shops
(`PathConfig:142-167`: the two halves run in opposing X directions so a player
can reach any lane or either shop without walking). The swing→base trip is a
pure **Z** journey, perpendicular to it.

What the belt actually does to this trip is push the player sideways for the 18
studs of crossing: 1.12 s at walk speed, ~18 studs of drift per half, opposed
between the halves so the net displacement across the full width is ≈0 — a
shallow S, not a detour. Neither an assist nor an obstacle; the number below
ignores it, correctly.

### 0c. Round trip on foot

Nothing in `src/` ever assigns `Humanoid.WalkSpeed` (checked by grep), so the
real speed is Roblox's default **16 studs/s**.

Measured in `verify_offline.luau` §6h against the real
`BaseGeometry.collectPadPlacement` output, walking all ten pads in a
boustrophedon (both columns of a row, then the next row):

```
out 65.4 studs + row 126.0 + back 121.2 = 312.6 studs -> 19.54 s at 16 studs/s
```

Cycle times (perfect play, same four-term model `dev/analysis/cycle_time.luau`
uses: bar wait 1.20 + flight + reward + the 4-stud remount walk 0.25):

| | tier 1 | tier 10 |
|---|---|---|
| cycle | 5.45 s | 15.80 s |
| trip as % of ONE cycle | **358%** | **124%** |

That is the number the prompt's "+155% if you collect every cycle" figure was
measuring, and it is worse than that figure because the trip now walks the whole
row rather than touching one pad. Amortised, it is a different animal — see 6h.

### 0d. The ten collect pads

Created in `PlayerProfile.spawnSlimeVisual` at `:485-509` (line numbers as
found at survey time):

- position/size from `BaseGeometry.collectPadPlacement(baseIndex, slotNumber)`
  (`BaseGeometry.luau:168`), nothing literal
- X: centred in the channel between the slot pad's inner edge and the central
  path's near edge — `baseX ∓ 8`, **4 studs wide** (`BASE_COLLECT_PAD_WIDTH_STUDS`)
- Z: the slot pad's own Z, **8 deep** (`BASE_COLLECT_PAD_DEPTH_STUDS`), so pad
  and slime line up end to end
- Y: mat top + half height (`BASE_COLLECT_PAD_HEIGHT_STUDS` 0.4)
- named `"CollectPad"`, `Anchored`, `CanCollide = false`, `CanTouch` left at its
  default true
- **parented into the slime `Model`** (`:509`), which is the whole teardown
  story: the pad cannot outlive its slime, so `removeToInventory`'s
  `model:Destroy()` and `onPlayerRemoving`'s `baseFolder:Destroy()` both take it
  with them without knowing it exists.

Confirmed: created in `spawnSlimeVisual`, destroyed with their slime.

The slime `Model` carries a `SlotNumber` attribute, set **before** it is parented
(`:452-454`), for `SlimeUpgradeTagClient`. That attribute is what this pass reuses
to bind a pad to a slot — no new registry, no change to the pad's construction.

### 0e. Every path that can empty a slot

**Exactly one**, and this is verified rather than assumed: `profile.slots[n] = nil`
appears once in the entire tree, in `PlayerProfile.removeToInventory`. The scan
in §6b asserts the count.

| named in the prompt | what actually exists |
|---|---|
| manual removal | `PlayerProfile.removeToInventory` — the one site |
| wipe | `devWipeProfile` → `devClearBase` → `removeToInventory` per slot |
| sell | **cannot empty a slot.** `sellFromInventory` only ever reads/decrements `profile.inventory`; that is what makes "remove before you sell" true by construction |
| replacement | **does not exist.** `placeFromInventory` refuses when the base is full ("no free slot -- remove one first") rather than swapping anything out |

Removed slimes land in `profile.inventory` (stacked by globalIndex), and
`sellFromInventory` is the sell route from there
(`incomePerSecond * SELL_VALUE_INCOME_MULTIPLIER * quantity`).

So banking-on-removal needed **one line in one function**, and the other three
paths inherit it.

### 0f. `totalIncomePerSecond`

At survey time (`PlayerProfile.luau:669`) it looped slots 1..`SLOT_COUNT`, looked
up `SlimeData.SLIMES[globalIndex]`, and summed
`SlimeUpgrade.incomeForLevel(slime.incomePerSecond, profile.levels[i] or 1)`.

**No per-slot rate was available** — the per-slot value existed only as a loop
temporary. It had to be extracted, and was: `slotIncomePerSecond(profile, slot)`
is now the primitive and `totalIncomePerSecond` is a sum of it, so there is still
exactly one expression for "what does a slot earn".

### 0g. The single-pot implementation, in full

Everything the rework had to touch:

| piece | where |
|---|---|
| `pendingIncome: number` | `Profile` type, `PlayerProfile:60` |
| `offlineCredit: number` | `Profile` type, `:68` (session-only, never persisted) |
| `lastCollectAt: number` | `Profile` type, `:73` — one debounce timestamp per player |
| `setPending(profile, pending, offline)` | `:692` — the pot's one writer, sets both attributes |
| `collectPending(player, profile, pad, hit)` | `:955` — owner check, debounce, whole-pot read, distance check, atomic payout, `UI_COLLECT` |
| `wireCollectPad` / `wireCollectPads` | `:1039` / `:1061` — `DescendantAdded` + initial pass, matching two names |
| `PendingIncome` attribute | written in `buildBaseFolder:320` and `setPending` |
| `OfflineCredit` attribute | same |
| the return pad part | `buildBaseFolder:302-313`, name `ReturnCollectPad` |
| return pad geometry | `BaseGeometry.returnPadPlacement:232` + two load-time asserts `:253-273` |
| return pad constants | `BaseConfig.BASE_RETURN_PAD_EDGE_MARGIN_STUDS`, `_Z_MARGIN_STUDS` |
| return pad label | `BaseClient.client.luau:215-287` (BillboardGui, collect line + "while away" line) |
| HUD pending line | `BaseClient:134-153` |
| the tick | `PlayerProfile:1621-1635` — `os.clock()` delta, into `pendingIncome` |
| offline accrual | `creditOfflineIncome:881` → `OfflineIncome.creditFor` |
| persistence | `toSaveShape` writes `pendingIncome`; `applyLoadedData` reads it |
| the debounce window | `BaseConfig.BASE_INCOME_TICK_SECONDS` (1 s) |
| the sound | `SoundConfig.UI_COLLECT`, fired from `collectPending` |

---

## STEP 1 — PER-SLOT POTS

**1a.** `pendingIncome: number` → `pendingBySlot: { [number]: number }` (slot →
dollars, missing = nothing pending). An empty slot holds no entry, not a zero.

**1b.** The tick credits each slot `slotIncomePerSecond(profile, i) * elapsed` —
its own slime at its own level, never a share of a total. The `os.clock()` delta
from the previous pass is kept exactly (`elapsed = now - lastTick`, not the
nominal `BASE_INCOME_TICK_SECONDS`), and is still deliberately unclamped.

One `publishPending` per profile per tick, after the slot loop rather than inside
it: the ten slots of one profile are one state change to any client, and
publishing is an attribute write plus a JSON encode.

**1c.** No cap, no clamp, nothing bounding a pot while the player is connected.
Measured: 24 h AFK on the test profile accrues **9.1×** the entire offline
ceiling. That is the intended relationship, not a leak — see 2c.

**1d.** Persisted as a dense `pendingBySlot` array with a 0 sentinel, the same
shape `slots` and `levels` already use (DataStore arrays cannot hold holes
reliably). A player who logs off holding money on eight slimes keeps all eight.

*Migration from the single pot:* a save written by the previous pass has one
scalar `pendingIncome` with no slot attached. It is spread across the slots **in
proportion to each slot's own rate** — the same rule offline accrual uses — so it
turns up where it would have been earned. The one case proportion cannot answer
is a base with no slimes at all (nothing to be proportional to); such a pot is
parked on slot 1 and picked up by the orphan pass below, which banks it, since an
empty base has no pad to ever collect it at.

*Orphan pots:* a pot on a slot that did not end up occupied cannot come from a
save this code wrote (removal banks first), but can arrive hand-edited, or from a
save whose slot held a `globalIndex` that no longer exists in `SlimeData` and was
skipped on load. Those are banked through `bankSlot` rather than stranded or
silently dropped — routing it that way is what keeps `bankSlot` the *only* place
in the file that moves a pot into cash (§6f counts the sites).

**1e. Removal banks first.** One line, at the top of `removeToInventory`, before
`profile.slots[slotNumber] = nil` and before `model:Destroy()` takes the pad with
it. Paths covered, from 0e:

| path | how it is covered | demonstrated in |
|---|---|---|
| manual removal (the Remove button → `InventoryServer`) | `bankSlot` called directly | §6b, and a source scan asserting bank-before-clear in source order |
| dev clear base | routes every slot through `removeToInventory` | §6b (all ten pots banked) |
| dev wipe | routes through `devClearBase` → `removeToInventory`, then zeroes money as a wipe should | §6b + source scan |
| sell | unreachable from a slot — needs no banking, and the scan asserts `sellFromInventory` never mentions `profile.slots` | §6b |
| replacement | does not exist — the scan asserts `placeFromInventory` never clears an occupied slot | §6b |

**1f.** Replicated as **`PendingBySlot`, a JSON array of `{slot, pending}` on the
base folder** — the exact shape and encoding `syncClientState` already uses for
`Slots` and `Inventory`, decoded on the client the same way `InventoryClient`
decodes those. No remote was added.

*Chosen over an attribute on each `CollectPad` part.* That would have been
marginally cheaper (no encode, no parse) and the pad already knows its slot — but
it means ten attribute writes per player per tick instead of one, and it puts the
value on an instance that only exists while a slime does, so nothing could render
a pot for a pad that had not been built yet.

`PendingIncome` survives as the **total** across slots, for the HUD (5d).

---

## STEP 2 — OFFLINE: 12-HOUR CAP AT 22%

**2a.** `OFFLINE_RATE_MULTIPLIER = 0.22`, commented with the intent: offline
should be meaningfully worse than playing — not worthless (coming back to nothing
is the fastest way to not come back at all) but far enough below the online rate
that idling is never a strategy and returning is always the rewarded choice. The
comment records that it is expected to be retuned once real player data exists,
and what data should decide it (the observed split between slot income and launch
income in a real session).

**2b.** `OFFLINE_CAP_SECONDS = 43200`, commented as a **design limit, not a
sanity bound** — and pointing at where the sanity bounds actually live
(`OfflineIncome.elapsedSeconds` handles a non-number, a NaN and a negative
elapsed, none of which go near this number). It covers both dominant absence
patterns, a night's sleep and a school or work day, so an ordinary player never
discovers a cap exists.

The reason recorded for capping at all is protecting the returning player, not
punishing absence: uncapped at 22%, a three-month absence returns **475 hours**
of income (measured, printed by §6c), which is several swing tiers already
affordable and the next week of content deleted as a welcome-back gift.

Combined ceiling: 12 h × 0.22 = **2.64 hours of income**, however long the
absence. Asserted, not just stated (§6c).

**2c.** The AFK asymmetry is recorded in the same comment block, explicitly as a
design position and not an oversight: online is uncapped and paid at full rate,
offline is capped and discounted; a player who leaves the game running keeps
earning 100% forever while a player who logs out earns 22% for at most twelve
hours. The comment says why making them consistent in either direction would
delete the reason to stay.

**2d.** Distribution is per slot **by construction rather than by a division**:
`creditOfflineIncome` calls `OfflineIncome.creditFor(lastSeen, now, rate_i)` once
per slot, at that slot's own rate, through the same arithmetic the total used to
go through. Since `elapsed` depends only on the timestamps,
`Σ elapsed·M·rate_i = elapsed·M·Σrate_i` — the per-slot credits sum to exactly
what one call at the summed rate returns, and no special case is needed for a
total rate of zero. `os.time()` is read **once**, before the loop, so every slot
is credited for the identical absence.

**2e.** Every guard from the previous pass kept and re-verified (§6d):

| guard | result |
|---|---|
| nil `lastSeen` | credits 0, and is checked *not* to equal the full cap (the `lastSeen or 0` epoch bug) |
| non-number / NaN `lastSeen` | credits 0 |
| negative elapsed (cross-server clock skew) | clamps to 0 at 1 s, 60 s, 1 h and 10× the cap of skew |
| failed load | guarded upstream by the `not ok` bail; source scan asserts the bail sits above both `applyLoadedData` and `creditOfflineIncome`, and the second line of defence (rate 0) is measured |
| accrual runs after `applyLoadedData` | source scan asserts the order |

**2f.** `offlineCredit` stays session-only and unpersisted, and stays **one
figure, not ten**. It feeds one summary sentence shown once on return; a per-slot
breakdown would need a surface to render on, and the only candidate is the pads —
which already show that slot's whole pot, of which the offline share is an
invisible fraction the player has no decision to make about.

---

## STEP 3 — THE TEN PADS

**3a.** Each pad banks its own slot only. The slot is read from the pad's parent
`Model`'s `SlotNumber` attribute at **wiring time**, once, not per touch: a pad's
slot cannot change (the pad dies with its slime; a new slime builds a new pad),
so re-reading it per Touched would re-derive a constant several times a step. A
pad whose parent carries no `SlotNumber` warns and is left unwired rather than
silently bound to nothing.

**3b.** `lastCollectAt: number` → `lastCollectAtBySlot: { [number]: number }`.
This is load-bearing, not cosmetic, and §6e measures why: **the closest two pads
on the walking route are 0.88 s apart at 16 studs/s, against a 1.00 s debounce
window.** A single shared timestamp would have banked the first pad of a walk and
silently skipped the rest — the exact failure the per-slot design exists to
avoid. The whole ten-pad walk takes 7.88 s, well under ten windows.

The atomic read-zero-credit is kept and moved into `bankSlot`, which is now the
single door from a pot into cash. §6e demonstrates independently that with the
debounce removed entirely, the atomic zero alone still yields exactly one payout
per pot — the two guards do not depend on each other.

**3c.** Banking zero is a silent no-op: `bankSlot` returns 0 and `collectPending`
returns before the sound. With ten pots and one walk, most pads are empty most of
the time — that is the normal case, not an error.

**3d.** Server-authoritative and owner-only, unchanged in shape: the handler
bails unless the touching part is a descendant of **the owner's** character, so a
player crossing a neighbour's pad banks nothing. (Six bases stand in a row with
nothing stopping a player wandering into one, so this is a live case.) Both the
slot and the amount are decided server-side; there is no remote in the path at
all.

**3e.** Confirmed: the `DescendantAdded` approach still handles a slime placed
hours after join, and it is now the *only* thing that matters — the return pad
was the only pad the initial `GetDescendants` pass ever actually found, because
it was the only one built synchronously at join. The watch is armed before the
load starts, which is what it has to be for the first `spawnSlimeVisual` of the
session to be caught.

---

## STEP 4 — THE RETURN PAD IS GONE

Removed:

| thing | file |
|---|---|
| the `ReturnCollectPad` part and its 12 build lines | `PlayerProfile.buildBaseFolder` |
| `RETURN_PAD_NAME` and its comment block | `PlayerProfile` |
| its branch in `wireCollectPads`' name match | `PlayerProfile` |
| `BaseGeometry.returnPadPlacement` (whole function) | `BaseGeometry` |
| its two load-time asserts (on the link's Z span, and clearing the conveyor) | `BaseGeometry` |
| the now-unused `LaunchConfig` require | `BaseGeometry` |
| `BASE_RETURN_PAD_EDGE_MARGIN_STUDS`, `BASE_RETURN_PAD_Z_MARGIN_STUDS` and their block | `BaseConfig` (value table **and** the `BaseConfig` export type) |
| the pad's `BillboardGui` label, its two lines, the `WaitForChild` and the fallback warning | `BaseClient.client.luau` |
| §7g of the old verification (which asserted the pad covered the whole walk) | `dev/analysis/verify_offline.luau` |

**Nothing else referenced it.** Checked by grep for `ReturnCollectPad`,
`returnPadPlacement` and `BASE_RETURN_PAD` across `src/` and `dev/analysis/`; the
only survivors are the comments that record the removal, and §6g asserts each
file no longer contains its own piece.

`PathConfig` stays required in `BaseGeometry` — `entranceSignPosition` still
measures its setback from the walkway. `GroundConfig` stays required in
`PlayerProfile` — the ten pads still use its shared top-surface finish.

---

## STEP 5 — UI

**5a. The amount is painted ON the pad**, a `SurfaceGui` on the top face
(`Face = Top`, `LightInfluence = 0`, `PixelsPerStud = 24` — the same three
properties `MapBuilder`'s slot-number labels use), not a `BillboardGui` above it.

`BaseConfig:231-234`'s original "no text on it, deliberately" argument was that a
green pad already reads as "stand here" and that ten more labels per base would
compete with the nametags and upgrade strips already hanging over these pads.
**Half of that still holds and is exactly why this is not a BillboardGui** — a
third floating label would stack three things in the air over every slime across
six bases. What changed is that the pad now has something to say that the player
cannot get anywhere else: under one pot a pad was only a place to stand and the
HUD carried the number; under ten pots the amount waiting on *this* slime is
per-pad information, and the walk down the row is a series of small decisions.

The `BaseConfig` comment is updated to record that the decision was revisited,
what changed, and which half of the original reasoning survived.

*Rejected:* a `BillboardGui` with a `MaxDistance` clamp matching the nametags. It
reads from further away, which is the one thing a SurfaceGui gives up — but
"readable from across the plot" is not this label's job. The HUD total answers
"is a trip worth it" from anywhere; the pad answers "is *this* pad worth stepping
on" from the path beside it.

**5b.** Hidden at zero — `label.Visible = amount > 0`. A row of ten "$0"s would
turn the thing that says "there is money here" into wallpaper. The pad itself
stays visible.

**5c. The "while you were away" line moved to the HUD**, one 30 px step above the
pending readout. There is no single pad to hang it on any more, and the credit is
spread across ten of them — hanging it over one would be arbitrary, over all ten
would say the same sentence ten times. Shown once on return, hidden while zero,
and cleared by the first collect at *any* pad (the server zeroes `OfflineCredit`
inside `bankSlot`), so nothing client-side has to time or remember it.

**5d.** The HUD's pending readout is now the **total across slots** —
`PendingIncome` is written by `publishPending` as `pendingTotal(profile)`. That
is what makes collection a decision: the number is readable from the swing, which
is where the player chooses between another launch and a trip.

**5e.** Both `GuiObject` traps set explicitly on every new element (the HUD away
line, the pad `TextLabel`): `BorderSizePixel = 0`, since a transparent background
does not clear the 1 px default border, and `TextStrokeTransparency` set
explicitly — here to **0** with a dark `TextStrokeColor3`, which is what
`BaseConfig`'s own `BASE_COLLECT_PAD_COLOR` comment prescribed for white text
over a bright Neon pad ("solve it on the text"). That comment is updated to note
the readout now exists and took the advice.

**5f.** Client-side only. The server writes `PendingIncome` / `PendingBySlot` /
`OfflineCredit` when they change (once per income tick, once per collect) and
never per frame; the client renders from attribute-changed signals. There are no
per-frame server writes and no remote in this path.

**5g. `UI_COLLECT`.** The entry's *tuning* is untouched (id still `nil`, volume
0.45, pitch 1.0, group UI, 2 s lifetime) — its **brief was rewritten**, because
the old one stated a firing pattern that is now false ("the return pad sits on
the post-flight walk, so this fires on EVERY cycle — roughly every 5 to 16
seconds"). Leaving that in the file would have been a lie in the one place
someone shops for the asset from.

**The guidance itself holds, and holds harder.** "Short decay, no tail, no
melody, nothing that resolves; if in doubt pick the quieter, duller option" was
written for a sound heard hundreds of times an hour; it is now a sound heard up
to ten times in ~8 seconds and then not at all for several launches. The length
ceiling (0.15–0.25 s) went from a preference to a requirement: at 0.88 s between
the closest two pads, anything with a tail overlaps *itself*.

**A rapid ten-in-a-row needs nothing.** No pitch step per pad, deliberately, for
two reasons: a rising run turns ten confirmations into a melody, which is the one
thing the entry says this sound must never become; and it would require a pitch
argument on `SoundBroadcast.playFor`, which today carries a key and nothing else
(the pitch lives in the registry, client-side). A run of ten is the *desired*
read — it is the sound of a good haul and the reward for having made the trip.
Recorded in the entry as "revisit only if a real asset in a real playtest turns
out to machine-gun." No asset ID was added.

---

## STEP 6 — VERIFICATION

`lune run dev/analysis/verify_offline.luau` — 84 checks, all passing, prints
only. Everything it can require, it requires for real (`OfflineIncome`,
`BaseConfig`, `BaseGeometry`, `PathConfig`, `LaneConfig`, `LaunchConfig`,
`SlimeData`, `SlimeUpgrade`). What it cannot (`PlayerProfile` requires `Players`,
`HttpService` and a DataStore-backed `PlayerStore` at module scope) is modelled
inline **and pinned to the real file with a structural scan**, so a model that
drifts from the code it stands in for fails the scan rather than passing quietly.
All source scanning goes through `common.readSource` (CRLF-normalising).

### 6a. Per-slot accrual

**Method:** a test profile of ten different slimes at mixed levels, asserted
first to have ten *distinct* per-slot rates (so "each grew at its own rate" is a
real claim, not one ten equal numbers satisfy by accident). Seven deliberately
ragged ticks (0.972–1.317 s) are run through the transcribed tick loop; each
slot's pot is compared against `slotIncomePerSecond(i) × span` individually, and
the ten are then summed against `RATE × span`.

```
ten pots sum to $27869.244851; one shared pot over the same 7.491 s would hold $27869.244851
```

Ten individual PASSes plus the sum. Uneven ticks are the point — the payout is
for time that actually passed, not for the nominal interval.

**No online cap:** 24 h AFK accrues $3.21e8 against an offline ceiling of
$3.54e7 — **9.1×**, asserted as a strict inequality.

### 6b. Removal banks first

**Method:** the ordering is modelled (bank, then clear, then destroy), exercised
on three cases, and then the model is pinned to the source:

- manual removal of slot 4 banks $4,000 and leaves slot 5's $5,000 alone
- devClearBase banks all ten ($55,000)
- removing a slot with an empty pot banks nothing, silently

Source scan (comments stripped first, so documentation cannot satisfy a check and
a commented-out line cannot count as present):

- exactly **one** site in the file empties a slot (both a literal and a pattern
  count agree)
- `bankSlot(profile, slotNumber)` appears **before** `profile.slots[slotNumber] = nil`
  in source order
- `devClearBase` empties through `removeToInventory`, not by hand
- `devWipeProfile` empties through `devClearBase`
- `sellFromInventory`'s body never mentions `profile.slots`
- `placeFromInventory` never clears an occupied slot

### 6c. Offline at 22%

**Method:** per-slot `creditFor` at a fixed synthetic `now`, against the real
module and the real constants.

| away | paid for | credit (test profile) |
|---|---|---|
| 1 h | 1.0 h | $2.95M |
| 12 h (the cap) | 12.0 h | **$35.4M** |
| 24 h | 12.0 h | **$35.4M** |
| 1 week | 12.0 h | **$35.4M** |
| 3 months | 12.0 h | **$35.4M** |

Everything past 12 h returns the **identical** figure — asserted as equality
against the first capped result, not as "approximately". 

The 12 h value is checked to equal **2.64 hours of this profile's own online
income** (`RATE × 2.64 × 3600`), measured rather than asserted, and separately
`12 × 0.22 = 2.64` exactly.

Proportional distribution is checked at **every** one of the five absences: for
each slot, `credit_i / total` is compared against `rate_i / RATE` to 1e-9.

For scale, printed alongside: uncapped at 22%, a week would return 37.0 h of
income and three months **475 h**. That is what the cap is for.

### 6d. Zero cases

nil, non-number, NaN, four magnitudes of future-dated `lastSeen`, a zero-rate
slot, and a failed load's empty profile at the full cap — all credit exactly 0.
The nil case is additionally checked *not* to equal the full cap, which is the
`lastSeen or 0` epoch bug stated as a test. The failed-load and ordering
guarantees are asserted structurally in 6b.

### 6e. Walking the row

**Method:** the walk is simulated against the **real** pad positions from
`BaseGeometry.collectPadPlacement`, in the order a player meets them
(boustrophedon), with arrival times derived from the real distances at 16
studs/s, and a realistic 7-event per-limb Touched burst at each pad. The guard
sequence is `collectPending`'s, transcribed.

```
the walk takes 7.88 s, 70 Touched events fired across 10 pads
```

- all ten pots banked ($5,500 of $5,500)
- every pad paid **exactly once** — none skipped, none twice
- the whole walk is shorter than ten debounce windows, so a shared debounce would
  have banked one pad and skipped nine
- closest two pads: **0.88 s apart against a 1.00 s window** — per-slot keying is
  load-bearing
- with the debounce removed entirely, the atomic zero alone still yields one
  payout

### 6f. Nothing sums pending into spendable cash

The previous pass's source-level check, re-run against the new shape:

- `upgradeSlime` gates on `profile.money < cost` and never reads `pendingBySlot`
  or `pendingTotal`
- `buyNextTier` gates on `profile.money < price`, same
- no `spendableMoney` helper exists
- **exactly one** site moves a pot into cash (`bankSlot`) — the needle changed
  with the shape, the property did not
- `bankSlot` zeroes the pot inside the same yield-free stretch that credits the
  cash

### 6g. Cycle time unchanged

The launch loop gained **no term at all**, and could not have: collection left
the loop entirely rather than being added to it.

- the post-flight walk is still 0.25 s (4 studs at 16 studs/s) — asserted;
  removing the return pad did not move where the player lands or where auto-mount
  takes them, since the pad was scenery on a walk defined by
  `SWING_RETURN_CLEARANCE_STUDS` and `SWING_MOUNT_RADIUS_STUDS`
- `LaunchServer.server.luau` never mentions `pendingBySlot`, `collectPending`,
  `bankSlot`, `PendingIncome` or `CollectPad` — five asserted absences; the
  launch loop and collection do not touch
- each file that built, placed or labelled the return pad is asserted to no
  longer contain its own piece of it

Cycle times are therefore exactly as the previous pass left them: **5.45 s at
tier 1, 15.80 s at tier 10** (perfect play).

### 6h. What the trip costs

The trip is 19.54 s (312.6 studs at 16 studs/s). Amortised — the player launches
N times, then makes one trip:

| launches per trip | cost at tier 1 | cost at tier 10 |
|---|---|---|
| 5 | 71.7% | 24.7% |
| 10 | **35.8%** | **12.4%** |
| 20 | 17.9% | 6.2% |

**Reading it.** The prompt's amortisation estimate (~15% at eight-to-ten
launches) lands between the two columns and is closest to the tier-10 figure. The
tier-1 column is the pessimistic end and is also the least real: a tier-1 player
has one or two slimes, a tiny pot, and no reason to walk at all — the trip is
priced against a cycle so short (5.45 s) that *anything* costs a lot of it. By
tier 10 the same trip is 12% at ten launches, and a tier-10 player is the one
with ten slimes and a pot worth walking for.

The direction that matters is the shape: cost falls linearly with launches
between trips, and the player sets that number. Ten pots visibly filling at
different rates, with a total on the HUD, is what turns "when do I walk?" into a
decision they can actually make. At 36% (worst case, tier 1) it is a real cost;
at 12% it is close to free. Nobody is forced to either end.

---

## WHERE I CHOSE

| choice | rejected alternative |
|---|---|
| per-slot pending replicated as one JSON attribute (`PendingBySlot`), matching `Slots`/`Inventory` | an attribute on each `CollectPad` part — cheaper to read, but ten writes per tick instead of one, and no value can exist before its pad does |
| offline credited by calling `creditFor` once per slot at that slot's rate | one call at the total rate, then divided by rate share — same result, but a second formula to keep in step and a zero-rate special case |
| `bankSlot` as the single door from any pot into cash | banking inline at each call site — three atomic sequences to keep identical, and §6f's "exactly one site" check would have nothing to count |
| pad slot bound once at wiring time from the parent Model's `SlotNumber` | re-reading the attribute per Touched — re-deriving a constant several times per step |
| legacy single pot distributed by rate; the no-slimes case parked on slot 1 for the orphan pass to bank | adding to `money` directly — would have created a second route into cash |
| the "while you were away" line on the HUD | on one arbitrary pad (which one?), or on all ten (the same sentence ten times) |
| `SurfaceGui` on the pad's top face | `BillboardGui` above it — reads further away, but stacks a third label in the air over every slime |
| `UI_COLLECT` left exactly as tuned, brief rewritten | a pitch step per pad — turns ten confirmations into a melody, and needs a pitch argument on `playFor` that does not exist |

## WHAT I DID NOT TOUCH

`SlimeRoll.luau`, the income tables, weight ratios, luck constants and spreads;
the chest table, the ladder, every price, the upgrade curve, `SLOT_COUNT`; the
flight formulas including the tier-keyed duration, the arch, ping compensation
and the sweet-spot constants; `PlayerStore.luau`'s session logic;
`LaunchRewardScene.luau` (not opened); every `nil` asset ID in the sound
registry; every file in `dev/out/`. The ten pads' positions, sizes, colours and
their construction inside `spawnSlimeVisual` are byte-for-byte unchanged — the
wiring reads a `SlotNumber` that was already there, and the `SurfaceGui` is built
client-side, in `BaseClient`, onto a pad it did not create.
