# Accumulate-and-collect — STEP 0 report, and a STOP

**Branch `ladder-renumber`. Started from `735e246f1c79fcdd56c39ac805c9de7971674c0b`** ("Report the
five small items").

**On the dirty tree:** the tree was reported dirty, but it was dirty *against `master`*, not against
real work. `git diff --stat ladder-renumber` over the whole working tree came back empty — the
checkout was byte-identical to `ladder-renumber`'s tip, with `master` simply 12 commits behind it.
Switching branches was therefore a no-op on file contents and left a clean tree. **No commit was
needed and none was made**; there was nothing uncommitted to preserve. `735e246` is both the hash I
started from and the hash the tree is still at.

**No code was written.** §0d's answer is the STOP condition the brief specified, and §4 below is the
argument. Everything in STEP 0 is answered first, because most of it stands regardless of how the
0d decision goes and the next pass should not have to re-derive it.

---

# 1. The STOP, stated first

> **0d.** Confirm from the map geometry that a player returning from the landing spot to the swing
> passes within touching distance of at least one collect pad. **If they do not pass a pad, STOP and
> report** — decision A above depends on this and the pads would need moving first.

**They do not pass a pad. They do not pass within 61 studs of one, and there is no walk back from
the landing spot at all — the return is a teleport.**

Decision A ("income accrues to the pot ALWAYS... the pads sit on the walk back from the landing
spot, so collecting is passive within the existing loop") rests on a premise the map does not
support. Per the brief's MUST NOT CHANGE list I have not moved the pads, and per the STOP I have not
built the system on top of the wrong premise.

The rest of STEP 0 is answered in full below; §4 is the geometry, §5 is what it costs, §6 is what I
would need from you to proceed.

---

# 2. STEP 0 answers

## 0a — the income tick

`BASE_INCOME_TICK_SECONDS` is consumed in exactly one place: `PlayerProfile.luau:1189-1200`.

```lua
task.spawn(function()
	while true do
		task.wait(BaseConfig.BASE_INCOME_TICK_SECONDS)
		for _, profile in profiles do
			local income = totalIncomePerSecond(profile)
			if income > 0 then
				profile.money += income * BaseConfig.BASE_INCOME_TICK_SECONDS
				profile.baseFolder:SetAttribute("Money", profile.money)
			end
		end
	end
end)
```

| question | answer |
|---|---|
| loop kind | `while true` + `task.wait(interval)` inside one `task.spawn`. **Not** Heartbeat. |
| per-player or global | **One global loop**, iterating the module-level `profiles` map each tick. |
| what it computes | `totalIncomePerSecond(profile) * BASE_INCOME_TICK_SECONDS` — a rate times the *nominal* interval. |
| what it writes | `profile.money` (in-memory, authoritative) and the `Money` attribute on `Base_<UserId>` (replicated, display). |

The constant is defined at `BaseConfig.luau:183` and is `1`.

**One thing worth flagging for whoever does write step 1b.** The lump uses the *config* interval, not
the *elapsed* interval. `task.wait(1)` returns after *at least* 1 second, typically 1 frame more, and
much more on a loaded server — so this loop already under-pays slightly and unboundedly under load.
It is a pre-existing bug, not one this pass introduces, and 1b ("the tick's rate calculation is
unchanged; only its destination moves") correctly does not ask me to fix it. But note that moving the
destination to a pot makes it *more* visible, not less: an under-paying pot is a number the player
watches accumulate, where an under-paying cash balance was invisible against income arriving from
launches. Recommend fixing it in the same pass with an `os.clock()` delta, as a separate commit.

## 0b — income per second from a profile

`PlayerProfile.totalIncomePerSecond`, `PlayerProfile.luau:1175-1187`. Local to the module, not
exported.

```lua
local function totalIncomePerSecond(profile: Profile): number
	local total = 0
	for i = 1, BaseConfig.SLOT_COUNT do
		local globalIndex = profile.slots[i]
		if globalIndex then
			local slime = SlimeData.SLIMES[globalIndex]
			if slime then
				total += SlimeUpgrade.incomeForLevel(slime.incomePerSecond, profile.levels[i] or 1)
			end
		end
	end
	return total
end
```

**Yes, it already accounts for slot levels via `SlimeUpgrade.incomeForLevel`** (`:1182`), which is
`baseIncomePerSecond * SlimeUpgrade.incomeMultiplier(level)` (`SlimeUpgrade.luau:59-61`). It reads
`profile.slots` and `profile.levels` only — placed slimes. Inventory contributes nothing.

This is the function §5f would have compared against, and it is the right one to reuse for offline
accrual: **there is only one, so online and offline cannot diverge as long as offline calls this
exact function rather than re-deriving the sum.** It is currently `local`; offline accrual can call
it directly from inside the same module (which is where profile load already lives), so it need not
be exported at all.

## 0c — the collect pads

| | |
|---|---|
| **where built** | `PlayerProfile.spawnSlimeVisual`, `PlayerProfile.luau:391-415`. **Not** `MapBuilder`, and **not** `BaseGeometry` (which only computes the placement). |
| **how many** | Up to `SLOT_COUNT` = 10 per player — but **one per *occupied* slot, not one per slot.** They are created inside `spawnSlimeVisual`, so an empty slot has no pad and a fresh player has none at all. |
| **class** | `Part` (`:392`). Anchored, `CanCollide = false`, `CanTouch` left at its default `true`. |
| **name** | `"CollectPad"` (`:393`) — all of them, in every base. Not unique; disambiguated only by parent. |
| **parent** | The **slime `Model`** (`:415`), not the base folder — deliberately, so destroying a slot visual destroys its pad (`:363-377` explains the teardown reasoning). |
| **size** | `(4, 0.4, 8)` — width and depth from `BaseGeometry.collectPadPlacement`, `BaseGeometry.luau:175-179`. |
| **position** | Derived, `BaseGeometry.collectPadPlacement:164-188`. Centred in the channel between the slot pad's inner edge and the central path's edge, on the slot's own Z. |

**Behaviour: none. They are purely visual.** I grepped the whole repo for `CollectPad` and
`COLLECT_PAD` (`*.luau`); every hit is either the construction block above, the `BaseConfig` tuning
constants, or the `BaseGeometry` derivation. Specifically:

- no `Touched` connection anywhere in the repo (`.Touched` has **zero** hits in `src/`)
- no `ProximityPrompt` on them (prompts exist, but only on the treasure chest — `MapBuilder.server.luau:616`, `ChestBuilder.luau:264` — and the mystery box uses a `ClickDetector`, `LaunchRewardScene.luau:900`)
- no `ClickDetector`
- no attributes set on them
- no `SetAttribute`, no tag, no registry — nothing anywhere reads a `CollectPad` back

`BaseConfig.luau:226-229` states this outright: *"THIS PASS IS THE PAD ONLY: geometry, colour and
placement. There is no collection logic and no accumulated-money system behind it yet."*

**Exact world positions**, for lane *i* with `baseX = LaneConfig.baseLaneCenterX(i)` (which is
`laneCenterX(i)` — the plots ride the swing pitch now, `LaneConfig.luau:105-107`), so
`baseX ∈ {-150, -90, -30, 30, 90, 150}`:

- **X** = `baseX ± 8`. Derivation: slot pads sit at `baseX ± 15` (`BaseConfig.luau:193`, half of `BASE_SLOT_COLUMN_SPACING_STUDS` = 30); the inner edge is `baseX ∓ 11`; the path edge is `baseX ∓ 5` (`BASE_PATH_SIZE.X` = 10); midpoint `baseX ∓ 8`. Odd slots take `-8`, even slots `+8`.
- **Z** = the slot's own row: **117, 131, 145, 159, 173** (`BASE_SLOT_Z_START` = 117, `BASE_SLOT_ROW_SPACING_STUDS` = 14, `BaseConfig.luau:195-200`).
- **Y** = mat top + half pad height = `groundY + 0.2 + 0.2 + 0.2` = `groundY + 0.6`.

So slot 1's pad occupies X `[baseX-10, baseX-6]`, Z `[113, 121]`.

## 0d — the walking loop

**There is no walk from the landing spot. See §1 and §4.**

## 0e — the profile schema

The `Profile` type is `PlayerProfile.luau:37-92`. What `toSaveShape` (`:578-609`) actually persists is
narrower than the type — the DataStore record is exactly these eight keys:

| key | shape | notes |
|---|---|---|
| `money` | number | |
| `slots` | dense array of `SLOT_COUNT`, `0` = empty | |
| `levels` | dense array of `SLOT_COUNT`, default `1` | |
| `seen` | array of globalIndex | |
| `swingTier` | number | re-clamped on load, `:653-656` |
| `inventory` | array of `{globalIndex, count}` | |
| `chestsOpened` | number | |
| `chestPending` | boolean | |

The in-memory-only fields (`baseIndex`, `baseFolder`, `visualParts`, `canSave`) are deliberately not
saved.

**Is there a timestamp / `lastSeen` / `lastSave` / session marker already?** **Yes — and it is a trap,
not a gift.** `PlayerStore.save` stamps two extra fields onto the record
(`PlayerStore.luau:127-134`):

```lua
if releasingSession then
	profileData.sessionJobId = nil
	profileData.sessionHeartbeat = nil
else
	profileData.sessionJobId = game.JobId
	profileData.sessionHeartbeat = os.time()
end
```

`sessionHeartbeat` **is** an `os.time()` written server-side. It looks exactly like the `lastSeen`
step 2a asks for. **It cannot be used as one.** It is a session *lock*, and on the single most common
exit path — a clean leave, `releasingSession = true`, `PlayerProfile.luau:794` — it is explicitly set
to `nil`. A player who logs off normally leaves *no* heartbeat behind, so reusing this field would
credit every clean-leave player **zero** offline income and only pay out after a crash. That is
precisely backwards. Step 2a needs its own field written unconditionally in `toSaveShape`, and the
next pass must not "reuse the timestamp that's already there."

Read at load: `PlayerStore.luau:92-97`, purely to decide whether another server looks live. Nothing
else reads it.

**Save cadence — both, plus a third:**

1. **Periodic**, every `AUTO_SAVE_INTERVAL_SECONDS` = **120 s** (`PersistenceConfig.luau:27`), loop at `PlayerProfile.luau:1205-1214`, gated on `profile.canSave`.
2. **On leave**, `onPlayerRemoving` → `PlayerStore.save(..., true)`, `PlayerProfile.luau:793-795`.
3. **On shutdown**, `game:BindToClose`, `PlayerProfile.luau:1228-1242` — concurrent, not serial, waiting on a pending counter.

**What happens to an unsaved profile if the server crashes:** it loses **at most 120 seconds** of
progress. A hard crash skips both `PlayerRemoving` and `BindToClose`, so the last periodic save is
all that survives. **Step 2a's requirement is therefore already met with no new save loop needed** —
the bound exists and is 120 s. That is the one item in the brief that turns out to be free. (The
bound applies to the pot too, once it is persisted: a crash can lose up to 120 s of pot, same as it
can lose 120 s of cash today.)

Load failure is handled separately and correctly: `canSave` stays `false` for the whole session
(`PlayerProfile.luau:744-758`) so a blank profile can never overwrite a real save that merely failed
to read. **Offline accrual must respect this flag** — a profile that failed to load has no `lastSeen`
and no slots, and must credit zero rather than treating the failure as a fresh player.

## 0f — every site that reads or writes cash

Grepped `profile\.money|\.money\s*[-+]?=|SetAttribute\("Money"` across `src/`. **Every hit is in
`PlayerProfile.luau`.** No other server module touches money directly; `ShopServer`, `UpgradeServer`,
`InventoryServer` and `DevPanelServer` all route through the functions below. This is the list step
1c would have to keep reading banked cash only:

| # | site | line | direction | balance check? |
|---|---|---|---|---|
| 1 | income tick | `:1195-1196` | **+** | no |
| 2 | `sellFromInventory` | `:998-999` | **+** | no |
| 3 | `upgradeSlime` | `:1060`, `:1072`, `:1086-1088` | **−** | **yes** — `profile.money < cost`, plus the binary search at `:1068-1079` |
| 4 | `buyNextTier` | `:1154`, `:1158-1160` | **−** | **yes** — `profile.money < price` |
| 5 | `applyLoadedData` | `:615-617` | set | no |
| 6 | `buildBaseFolder` | `:227` | init 0 | no |
| 7 | join, post-load | `:769` | replicate | no |
| 8 | `devSetMoney` | `:1268-1269` | set | no (dev, Studio-gated) |
| 9 | `devAddMoney` | `:1279-1280` | ± | no (dev, Studio-gated) |
| 10 | `devWipeProfile` | `:1316-1317` | zero | no (dev, Studio-gated) |
| 11 | `toSaveShape` | `:600` | read → save | no |

**Only sites 3 and 4 are balance checks**, and both compare against `profile.money` directly. A
`pendingIncome` field added alongside would be non-spendable *by construction* — neither site sums
anything — provided nobody later writes a `spendableMoney()` helper. Client-side affordability
displays (`SlimeUpgradeTagClient`, `ShopClient`, `InventoryClient` read the `Money` attribute) are
display only and are re-validated server-side at sites 3 and 4.

## 0g — the HUD's money display

`BaseClient.client.luau`. It is a pure renderer of replicated attributes on this player's own
`Base_<UserId>` folder — **no remotes at all** (`:1-9`, `:141-146`).

- `MoneyReadout`, `:70-82`. Bottom-left, `AnchorPoint (0,1)`, `Position (0.02, 0, 0.98, 0)`, `Size (0, 480, 0, 110)`, `GothamBlack`, `TextScaled`, green `(0.25, 1, 0.35)`.
- Updates via `baseFolder:GetAttributeChangedSignal("Money"):Connect(refreshMoney)` (`:141`), formatted through `MoneyFormat.format` (`:127-130`).
- Two siblings stack **upward** from it: `TierReadout` at Y offset `-110` (`:88-100`) and `SaveWarning` at `-140` (`:107-120`), each 30 px tall.

**Is there room for a pending indicator? Yes.** The stack currently ends at `-170`; a fourth 30 px
line at `-170` continues the established pattern exactly, and a new `PendingIncome` attribute on the
same base folder would need no remote and no new plumbing — one more
`GetAttributeChangedSignal` connection. That is the cheapest possible 4c, and it is the right shape.

## 0h — `BillboardGui` vs `SurfaceGui`

**Both are used, and the codebase draws a clean, consistent line between them.** It is not a matter
of taste here — it is a rule with a written rationale:

- **`SurfaceGui` = text painted on real geometry.** The entrance sign board (`SignBuilder.luau:248`), the runway band numbers (`RunwayBuilder.server.luau:179`), the slot-pad numbers (`MapBuilder.server.luau:184`), the mystery box's six "?" faces (`LaunchRewardScene.luau:836`).
- **`BillboardGui` = a label floating in the air above a thing.** The slot nametags (`PlayerProfile.luau:451`), the upgrade button strips (`SlimeUpgradeTagClient.client.luau:311`), the box's luck readout (`LaunchRewardScene.luau:862`).

The rationale is recorded twice and is a scar, not a preference: `SignBuilder.luau:4-7` and
`PlayerProfile.luau:173-182` both explain that the base sign *used* to be a `BillboardGui`, that a
`BillboardGui`'s `Offset` is **screen pixels** so it held a constant size at every distance, and that
this read as "a grey band on the horizon" from anywhere on the map. It was replaced with real
geometry carrying a `SurfaceGui`.

**For step 4a — "a world-space label above each collect pad" — the matching class is `BillboardGui`**,
since it floats above a part rather than being painted on one. But it must carry the three settings
the existing nametag learned the hard way (`PlayerProfile.luau:451-457`): a finite `MaxDistance`
(the nametags use 40 studs, `:292`), `AlwaysOnTop = false`, and no stroke — otherwise it reproduces
the horizon-haze bug on ten more labels per base, six bases at once.

**Note a direct conflict with 4a, which the brief should know about.** `BaseConfig.luau:231-234`
records a deliberate decision *against* labelling these pads:

> NO TEXT ON IT, deliberately. A green pad on the floor already reads as "stand here" — a SurfaceGui
> saying COLLECT would be ten more labels per base competing with the nametags and the button strips
> already hanging over these same pads.

Step 4a reverses that. I think 4a is right — a pad that pays a *variable amount* needs to say the
amount, which the old decision was not weighing — but it is a reversal, and the comment says
`SurfaceGui` where 4a wants a floating label, which would put a third GUI layer above pads that
already carry a nametag and an upgrade strip. Flagging rather than deciding.

---

# 3. Decision B — the code makes it awkward, but not wrong

The brief asked me to report if the code makes either decision wrong. Decision A is §4. Decision B
("ONE pending pot per player... The pads are plural because they are on the path, not because they
hold separate money") is **sound and I would keep it**, but two facts about the pads cut against it
and both need a deliberate answer:

1. **The pads are per-*occupied-slot*, and they live *inside* the slime model** (`PlayerProfile.luau:415`). Visually a pad is glued to one specific slime, directly in front of it, on that slime's row. A player will read "this pad is *that slime's* money" — which is exactly what decision B says it is not. Showing the same `Collect $X` on all ten simultaneously makes the shared-pot reading obvious the moment there are two, so 4a happens to fix this. With one slime placed, it is unresolvable and also harmless.

2. **A player can hold a pot with zero pads to collect it from.** Pads exist only where a slime is placed, and `removeToInventory` destroys the model and its pad with it (`:956-960`). Remove all ten slimes while holding an uncollected pot and the money is stranded — unreachable until something is placed again. It is a corner, but it is reachable through ordinary UI, it strands *real* money, and it gets worse with offline accrual, since the pot can be large. The fix is not more pads; it is one pad that does not depend on a slime — which is the same conversation as §6.

---

# 4. The geometry behind the STOP

## The loop as the code actually runs it

The player never walks back from a landing. `LaunchServer.server.luau:2266-2275` is explicit:

> **FROZEN AT LANDING** [...] the root **STAYS anchored** and AutoRotate **STAYS off** here [...]
> The landing spot is up to ~2,900 studs down an empty road with nothing to walk to; freeing the
> player here just let them wander off with no reason to.

They stay frozen through the box and the reveal, and are then **teleported** by `moveToLaneReturn`
(`:1293-1312`):

```lua
local returnPosition = Vector3.new(
	LaneConfig.laneCenterX(laneIndex),
	groundY + standingHeight,
	LaneConfig.SWING_PIVOT_Z + LaunchConfig.SWING_RETURN_CLEARANCE_STUDS
)
character:PivotTo(CFrame.lookAt(returnPosition, returnPosition + Vector3.new(0, 0, -1)))
```

`SWING_PIVOT_Z` = 30 (`LaneConfig.luau:38`), `SWING_RETURN_CLEARANCE_STUDS` = 22
(`LaunchConfig.luau:438`) → **Z = 52**, at the lane's own X. Both landing outcomes go through this
one function — the luckless auto-return (`:1337-1366`) and the click-driven reward return — and so
does the chest-landing safety net (`:1403`), so there is no branch that walks.

The full cycle in Z: mount the swing at **Z 30** → fly to **Z −176 … −2,900** → teleport to **Z 52**
→ walk 22 studs back to **Z 30**. **The cycle never exceeds Z 52.**

## Where the pads are relative to that

The plot sits *behind* the return position, past two intervening structures:

| Z | what | source |
|---|---|---|
| 30 | swing pivot | `LaneConfig.luau:38` |
| **52** | **return position — the furthest +Z the loop ever reaches** | `LaunchServer.server.luau:1298` |
| 67 | approach link ends | `PathConfig.luau:116` |
| 67–85 | **conveyor belt walkway** | `PathConfig.luau:165-167` |
| 85–108 | spur | `PathConfig.luau:138-140` |
| 108 | plot front edge (mat) | `BaseConfig.luau:309`, `:82` |
| **113–121** | **nearest collect pads (slots 1 & 2)** | `BaseGeometry.luau:164-188` |
| 173 | furthest collect pads (slots 9 & 10) | `BaseConfig.luau:195-200` |

**Distances from the return position `(baseX, 52)`** — and `baseX == swingX`, since
`baseLaneCenterX` delegates to `laneCenterX` (`LaneConfig.luau:105-107`), so there is no X offset to
help:

| measurement | value |
|---|---|
| to the nearest pad's **centre** `(baseX−8, 117)` | `√(8² + 65²)` = **65.5 studs** |
| to the nearest pad's **nearest corner** `(baseX−6, 113)` | `√(6² + 61²)` = **61.3 studs** |
| to the **furthest** pad (slot 9/10, Z 173) | **121.3 studs** |
| character touch radius, generously | ~3 studs |

**61.3 studs versus ~3. The pads are off the loop by a factor of twenty.**

They are not merely far, they are *behind a barrier of purpose*: reaching them means crossing the
two-way conveyor at Z 67–85, which is the map's explicit boundary between "the swing area" and "the
base area." The plots were moved +46 studs precisely so the shop walkway would sit between the two
(`BaseConfig.luau:300-308`).

## This is corroborated by your own analysis, not just by me

`dev/out/cycle_economics.json` already models the cycle, and its constants include
`"returnZ": 52` and `"beltWalkwayZ": 76`. Its per-cycle breakdown is:

```
barWaitSeconds + flightSeconds (1.8) + returnSeconds (0.25) + rewardSceneSeconds (2)
```

**`returnSeconds` is 0.25** — that is `RESET_DELAY`, the teleport. The model contains **no walking
term at all**, because there is no walking in the loop. The baseline the brief asks me to compare
against in 5g is itself built on the fact that decision A's premise is false.

Total cycle at tier 1: **5.25 s** (perfect play), **7.65 s** (hit50), **14.85 s** (hit20).

---

# 5. What decision A would actually cost, in numbers

Since the pads are not passive, collecting becomes a **detour**. Costing it at the default walk speed
of 16 studs/s (`cycle_economics.json` records `assumedWalkSpeedStudsPerSecond: 16` and
`walkSpeedIsConfigured: false`):

| leg | studs | seconds |
|---|---|---|
| Z 52 → 67, approach link | 15 | 0.94 |
| Z 67 → 85, across the belt (it pushes on **X**, not Z, so no help) | 18 | 1.13 |
| Z 85 → 108, spur | 23 | 1.44 |
| Z 108 → 117, mat to slot-1 pad | 9 | 0.56 |
| **one way** | **65** | **4.06** |
| **round trip** | **130** | **8.13** |

Against the measured cycle:

| player model | cycle now | cycle + collect detour | penalty |
|---|---|---|---|
| perfect | 5.25 s | 13.4 s | **+155%** |
| hit50 | 7.65 s | 15.8 s | **+106%** |
| hit20 | 14.85 s | 23.0 s | **+55%** |

**Collecting every cycle would more than double the loop for a competent player**, and launches/minute
would fall from 11.4 to 4.5 at perfect play. The realistic player response is not "collect every
cycle" — it is "collect every N cycles," which is fine for the pot but means **the equilibrium income
figures in `roll_economics_v2.json` are computed against a loop that no longer exists**, since those
launches are what generate slimes in the first place. Decision A's stated goal — "realised income
should stay close to the measured equilibrium" — is not achievable by building the system as
specified on this map. That is the substance of the STOP, not a technicality about stud counts.

Note the asymmetry that makes this worth getting right: **offline accrual (STEP 2) is unaffected by
any of this** and is the actual D1 hook. Only the *collection* half depends on pad placement.

---

# 6. What I need to proceed

The brief forbids moving the pads in this pass, so this is your call, not mine. Four options, with
what each costs:

| # | option | cost | my read |
|---|---|---|---|
| **1** | **Add one collect pad on the return path** — near Z 52–67, at `baseX`, on the approach link the player already crosses. Leave the ten existing pads exactly where they are as base dressing (wired to the same single pot, which is decision B unchanged). | New geometry in `BaseGeometry`/`MapBuilder`, ~30 lines. Does **not** move any existing pad, so the MUST NOT CHANGE list holds literally. | **Recommended.** It is the smallest change that makes decision A true as written, it needs no repricing, and decision B ("the pads are plural because they are on the path") becomes *actually* true instead of aspirational. It also fixes §3's stranded-pot corner for free, since it does not depend on a placed slime. |
| **2** | **Keep decision A, accept the detour.** Build exactly as specified. | Free to build; costs the loop, per §5. | Viable only if you intend the base to become a place players deliberately visit. That is a real design, but it is a *different* one, and it makes the cycle figures stale. |
| **3** | **Auto-collect on proximity to the plot**, no pad touch required. | Cheap. | Removes the collect *action*, which is the satisfying part of the genre beat. I would not. |
| **4** | **STEP 2 only** — ship offline accrual into the pot, defer collection. | Smallest. | Tempting, but a pot with no way to bank it is worse than no pot. Only sensible bundled with option 1 as a follow-up. |

If you pick **option 1**, tell me and I will build steps 1–5 in full against it, including the new
pad, in per-step commits. Everything in §2 above is the survey that pass needs, so it starts
immediately rather than re-reading.

If you pick **option 2**, say so and I will build it exactly as the brief specifies — the objection
is registered here and does not need re-litigating; I will note the realised-vs-theoretical gap in
5g with the §5 numbers and leave the decision to you.

---

# 7. Everything I did not touch

No files were modified. `git status` is clean at `735e246`. In particular, and per MUST NOT CHANGE:
`SlimeRoll.luau` was not opened; no income, chest, ladder, upgrade-curve, layout, band-curve or
flight constant was read for anything but the citations above; `LaunchRewardScene.luau` was not
opened (the two `grep` hits quoted in §0h come from a repo-wide pattern search, not a read); nothing
in `dev/out/` was regenerated — the two JSON files in §4 and §5 were read only.
