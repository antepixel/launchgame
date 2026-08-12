# A leaderstats board: Swing, Money, $/s

Started from `aea068c8ed010997608e80801f6fa631ea6a5f6c` (`aea068c`, "Verify the
per-slot rework, and report it") on `ladder-renumber`.

Two commits, in this order:

| commit | what |
|---|---|
| `bf31d6b` | Pin `verify_sound`'s additive-only check to the sound pass's own tip (the separate fix) |
| `5c5bfcb` | Add the leaderboard |

**Reproduce every claim below:**

```
lune run dev/analysis/verify_leaderstats.luau
```

Prints only; writes nothing to `dev/out/`. Deterministic.

---

## STEP 0 — SURVEY

### 0a. No leaderstats exists anywhere

`grep -rn "leaderstats\|leaderboard\|IntValue\|StringValue" src/` returns
**nothing** — not a folder, not a write, not a Value instance of any kind. The
game has never had one. Nothing writes to `Player.leaderstats`, and no client
script reads one.

Re-asserted structurally in `verify_leaderstats.luau` §0a, which scans fourteen
server and client files through `common.readSource` (comments stripped) and
requires **exactly one** to mention `leaderstats` — `PlayerProfile.luau`.

### 0b. `totalIncomePerSecond`

```lua
local function slotIncomePerSecond(profile: Profile, slotNumber: number): number   -- :657
local function totalIncomePerSecond(profile: Profile): number                      -- :673
```

`PlayerProfile.luau:673-679`. The total **is still a plain sum of the
primitive** — it loops `1..SLOT_COUNT` calling `slotIncomePerSecond(profile, i)`
and adds. Confirmed.

There is **exactly one expression for what a slot earns**:
`SlimeUpgrade.incomeForLevel(slime.incomePerSecond, profile.levels[slot] or 1)`
at `:666`. `SlimeUpgrade.incomeForLevel` appears three more times in the file,
and all three are in functions that paint a *label*, never that compute a rate:
`spawnSlimeVisual` and `refreshSlimeVisualLabel` (the on-slime income line).
The verification asserts this **by owner** rather than by count, so the property
is stated as what it is: the level formula is read by one rate function and two
renderers.

Callers of the total: `creditOfflineIncome` (`:951`, the legacy-pot migration)
and — after this pass — `refreshLeaderstats`. The income tick and the offline
accrual both walk `slotIncomePerSecond` per slot directly.

### 0c. Every place `profile.money` is written

Eight sites, and **every one is immediately followed by
`baseFolder:SetAttribute("Money", ...)`**. That pairing is a pre-existing
invariant of the file — the HUD, the shop and the upgrade strips all render off
that attribute — and this pass leans on it as the anchor for the money column.

| # | function | line | when |
|---|---|---|---|
| 1 | `bankSlot` | `:746` | every collect, every removal's banking, load reconciliation |
| 2 | `applyLoadedData` | `:841` | on load (published at `:1357`) |
| 3 | `sellFromInventory` | `:1610` | selling unplaced slimes |
| 4 | `upgradeSlime` | `:1698` | buying levels |
| 5 | `buyNextTier` | `:1770` | buying a swing tier |
| 6 | `devSetMoney` | `:1923` | dev panel |
| 7 | `devAddMoney` | `:1934` | dev panel |
| 8 | `devWipeProfile` | `:1979` | dev panel |

Plus `buildBaseFolder:313`, which writes the attribute at its initial 0 before a
profile exists — the folder builder, not a mutation site.

### 0d. Every place `profile.swingTier` is written

| # | function | line |
|---|---|---|
| 1 | `applyLoadedData` | `:880` (published at `:1358`) |
| 2 | `buyNextTier` | `:1771` |
| 3 | `devWipeProfile` | `:1991` |
| 4 | `devSetSwingTier` | `:2010` |

Plus `buildBaseFolder:317` at its initial 1.

### 0e. Every place the income RATE can change

The rate is a function of `profile.slots` and `profile.levels`. Both are written
at exactly six places:

| function | line | what changes |
|---|---|---|
| `applyLoadedData` | `:849` | slots + levels, on load |
| `receiveSlime` | `:1471-1472` | a revealed slime auto-placed |
| `placeFromInventory` | `:1513-1514` | a slime placed by hand |
| `removeToInventory` | `:1564,1567` | a slot emptied |
| `upgradeSlime` | `:1699` | **a level bought — money AND rate** |
| `devSetSlimeLevel` | `:2030` | dev panel |

`devClearBase` and `devWipeProfile` reach the rate through `removeToInventory`.

**Every one of those six is followed by `syncClientState(profile)`** — the
function whose own header states it is "called at the end of every function in
this file that touches slots or inventory". That makes `syncClientState` the
natural anchor for the rate column, and the verification asserts the adjacency
line by line rather than trusting the comment.

The brief's warning is exactly right: `upgradeSlime` is the trap. It changes
money *and* the rate, so a board wired only to money changes would show a fresh
balance beside a stale $/s — the very number the column exists to make visible.

### 0f. `MoneyFormat` across the range

`MoneyFormat.luau` carries suffixes to `Qi` (10¹⁸) and falls back to `"$%d"`
below $1,000. Measured, not assumed:

| value | renders |
|---|---|
| $0 | `$0` |
| $999 | `$999` |
| $1,500 | `$1.5K` |
| $9,100,000 | `$9.1M` |
| $800,000,000,000 (top tier price) | `$800B` |
| $244,459,004.67 (ceiling base income/s) | `$244.5M` |
| 2,147,483,647 (the IntValue cap) | `$2.1B` |
| 10¹⁸ | `$1Qi` |

It also tolerates **fractional** input — income accrues as a float and `bankSlot`
adds it whole, so money is routinely non-integer. `"$%d"` truncates rather than
erroring (`0.5 → $0`, `999.99 → $999`). The HUD already relies on this; the
leaderboard now does too.

### 0g. The load window

`onPlayerAdded` runs **synchronously** through `buildBaseFolder` (`:1278`) and
the profile literal (`:1280`), then spawns a thread for `PlayerStore.load`
(`:1309`). During that read — one DataStore round trip plus up to
`LOAD_RETRY_ATTEMPTS` retries, and possibly a session-lock wait — the profile
holds `money = 0` and `swingTier = 1`, and the base folder's attributes say the
same.

Those are **not wrong values**; they are the values of a brand-new profile,
which is what the player has until the load says otherwise. Three outcomes:

- **new player** (`nil, true`) — 0 / tier 1 is correct and stays correct.
- **existing profile** (`data, true`) — corrected at `:1357-1368`.
- **failed load** (`nil, false`) — returns early at `:1330`; the session plays on
  a blank profile with `canSave = false`, for which 0 / tier 1 is correct.

**Nothing in this survey contradicted the brief.**

---

## STEP 1 — THE LEADERBOARD

### 1a. Where it is built

`buildLeaderstats(player)` sits directly beside `buildBaseFolder` in
`PlayerProfile.luau`, and is called from `onPlayerAdded` immediately after it.

**Why there:** this module is already documented as "the single owner of ALL
per-player state". A second script building a leaderstats folder would need its
own copy of the profile lookup and its own hooks into every write site — the
exact split this module exists to prevent. Building it here means the refresh has
a profile in hand at every call site, for free.

The folder is `Name = "leaderstats"` and `Parent = player` — both Roblox
requirements, not choices. It is parented **last**, once all three children
exist, so the engine can never see a half-populated folder (the same ordering
guarantee `SoundBroadcast`'s remotes folder and `buildBaseFolder`'s attributes
already use).

The folder and its three Values are carried on the `Profile` type as a
`leaderstats` record, exactly the way `baseFolder` already is:

```lua
leaderstats: {
    folder: Folder,
    swing: IntValue,
    money: StringValue,
    rate: StringValue,
},
```

*Chosen over holding just the folder and calling `FindFirstChild` per refresh:*
these three never move and never change identity, so looking them up repeatedly
would be re-deriving a constant.

### 1b/1c. Three columns, in order

`Swing`, `Money`, `$/s`. Roblox's player list renders the Values in **parent
order**, so the order they are parented in `buildLeaderstats` is the order they
appear left to right.

**Swing is an `IntValue`.** The tier is 1–10, reads naturally as a bare number,
and — crucially — integer columns sort **numerically**, so the one column where
a ranking is both meaningful and achievable gets one.

### 1d. Money and $/s are `StringValue`s, and what that costs

An `IntValue` is a signed 32-bit integer capping at **2,147,483,647**, which
`MoneyFormat` renders as **`$2.1B`**. The top swing tier costs **$800B — 373×
that cap** — and a fully levelled ceiling base earns $244.5M/s, which would blow
through it in under ten seconds of holding. An integer column would overflow
**inside ordinary play**, not at some theoretical extreme.

A `NumberValue` (double) holds the magnitude but renders in the player list as
raw `8.0000000000e+11`, which is worse than useless.

So both go through `MoneyFormat`, the same shared formatter the HUD's money
readout and the shop's prices use — chosen deliberately over the file's own local
`formatIncomePerSecond`, because the Money column and the HUD money readout are
two views of the same number and `MoneyFormat` exists precisely so those cannot
diverge.

Representative renderings: `$0` · `$999` · `$1.5K` · `$9.1M` · `$800B` ·
`$244.5M`.

**THE COST, STATED PLAINLY: Roblox sorts `StringValue` columns alphabetically,
not numerically. `"$9.1M"` sorts above `"$800B"`.** The Money and $/s columns are
readouts that happen to sit next to each other, not a ranking. This is accepted.
The alternative is a custom scoreboard GUI — a ScreenGui, a sorted list,
per-player rows, a refresh path and six rows of layout to maintain — a great deal
of UI for the gain of one column sorting properly.

The tradeoff is recorded in a comment above `buildLeaderstats`, including the
instruction not to "fix" it into an `IntValue`, which would trade a cosmetic sort
problem for silently wrong numbers. `verify_leaderstats.luau` asserts that both
the word *alphabetically* and the literal `2,147,483,647` are present in the
source, so the reasoning cannot be deleted without a test failing.

The $/s **value** is a bare money figure with no `/s` suffix — the column
*header* carries the unit, so `$5.4K` under `$/s` reads as "$5.4K per second".
(`formatIncomePerSecond` appends `/s` because the on-slime nametag it feeds has
no header to carry it.)

### 1e. One writer, fifteen call sites

```lua
local function refreshLeaderstats(profile: Profile)
```

*Takes the profile alone, not `(player, profile)` as the brief suggested.*
Everything it needs is on the profile — including the Value instances — and two
of its callers, `bankSlot` and the load path, have **no `Player` in scope at
all**. Requiring one would have meant either threading a player argument through
the collect path or a reverse lookup from the `profiles` table, for no gain.

All three columns are written together from one read of the profile, so they
cannot drift out of step with each other even for a frame. It **writes only on a
real change** — three comparisons — which makes a redundant call provably free
and is what lets call sites be added liberally rather than carefully.

The fifteen sites, by rule:

| rule | sites |
|---|---|
| every `syncClientState(profile)` call site (covers all rate changes) | `onPlayerAdded`, `recordChestOpened`, `receiveSlime` ×2, `placeFromInventory`, `removeToInventory`, `sellFromInventory`, `upgradeSlime`, `devWipeProfile`, `devSetSlimeLevel` |
| money/tier sites that do **not** call `syncClientState` | `bankSlot`, `buyNextTier`, `devSetMoney`, `devAddMoney`, `devSetSwingTier` |

`recordChestOpened` changes no column. It is called anyway so the rule is
**exceptionless** — a rule with one documented exception is a rule nobody can
verify — and the same-value guard makes it a no-op.

Two placements were deliberate rather than mechanical:

- **`bankSlot`**: after `publishPending`, below the atomic read-zero-credit
  stretch. It is a pure read of state that is already final and cannot yield, so
  the payout's own no-yield guarantee is untouched by it.
- **`removeToInventory`**: after the slot is cleared, *not* merged with the one
  `bankSlot` already made a few lines above. That earlier call published the
  banked money while the slot was still occupied and still earning; this one
  publishes the rate after it is gone.

### 1f. The load window

**The folder is built before the load starts, at values that are true for a
brand-new player**, and refreshed as the last line of the load.

Starting values are `Swing = 1`, `Money = MoneyFormat.format(0)`,
`$/s = MoneyFormat.format(0)` — and the profile literal on the very next lines
starts at `money = 0, swingTier = 1` with empty slots. So the board is not
showing a placeholder that must be corrected; it is showing a fresh profile,
accurately, until the load says otherwise.

*Rejected: building it after the load resolves.* That would leave the player with
no leaderboard row at all for the length of a DataStore read and its retries —
and, worse, the failed-load path returns early, so a player whose load failed
would have had no leaderboard for the entire session. Those sessions play on a
blank profile, for which 1 / $0 / $0 is exactly right.

The refresh is the **last** line of the load block, after `syncClientState`.
Placing it beside the `Money`/`SwingTier` attribute writes further up would have
published a correct tier and balance against a still-empty slot table — a $/s of
zero — and left it there until the player's next purchase.

### 1g. $/s is not re-derived

`refreshLeaderstats` calls `totalIncomePerSecond(profile)`, the same function
reached by the income tick and the offline accrual (both through
`slotIncomePerSecond`). Asserted three ways in the verification: that the call is
present, that the function body contains **no** `incomeForLevel` and no
`SLIMES[` lookup of its own, and that the level formula is read only by
`slotIncomePerSecond` and the two label painters.

---

## STEP 2 — WHAT WAS NOT DONE

All four checked against the source, not asserted in prose:

| # | prohibition | how it is verified |
|---|---|---|
| 2a | no pending-income column | `buildLeaderstats` has exactly **3** `.Parent = folder` lines, and neither it nor `refreshLeaderstats` mentions `pending` |
| 2b | no timer, no per-frame update | `refreshLeaderstats` contains no `task.wait`, no `Heartbeat`, no `RunService` — it is call-driven only |
| 2c | nothing persisted | `toSaveShape` still writes exactly its ten fields, and never mentions `leaderstats` |
| 2d | HUD untouched | `BaseClient.client.luau` contains no reference to `leaderstats`; not one line of it changed |

---

## STEP 3 — VERIFICATION

`lune run dev/analysis/verify_leaderstats.luau` — **all checks pass**.

`PlayerProfile.luau` requires `Players`, `HttpService` and a DataStore-backed
`PlayerStore` at module scope, so it cannot be loaded outside the game and the
wiring cannot be *executed* here. What can be checked — and is the thing most
likely to rot — is the source property that every function changing a column also
refreshes it. All scanning goes through `common.readSource` (CRLF-normalising)
with a **quote-aware** comment strip, because the naive `gsub("%-%-.*$", "")`
cuts into string literals in this tree.

### 3a. Correct immediately after a load, both cases

**Method:** source-order assertions on `onPlayerAdded`.

- `buildLeaderstats(player)` appears **before** `PlayerStore.load` — the row
  exists from the first frame.
- `swing.Value = 1` and two `MoneyFormat.format(0)` calls in the builder, checked
  against the profile literal's own `money = 0,` / `swingTier = 1,` — the
  starting columns are the fresh-profile values, so a **new player** is correct
  with no refresh at all.
- The `if not ok then` bail appears **before** the refresh — a **failed load**
  never reaches it, and its blank-profile session keeps the correct 1 / $0 / $0.
- `syncClientState(profile)` appears **before** the refresh — for an **existing
  profile**, slots and levels are populated by the time $/s is computed, so it is
  right on the first paint rather than zero.

### 3b. Money updates on every 0c site

The check does not use a hand-written list. It derives the set of functions
containing `SetAttribute("Money"` from the file itself and requires each to
contain a `refreshLeaderstats(profile)` call — so a *new* money site added later
is caught too, which is exactly when a hand-written list would go stale.

Result: `bankSlot`, `buyNextTier`, `devAddMoney`, `devSetMoney`,
`devWipeProfile`, `onPlayerAdded`, `sellFromInventory`, `upgradeSlime` — **all
eight refresh.** (`buildBaseFolder` is excluded by name: it writes the initial
attribute before a profile exists, and `buildLeaderstats` covers the same instant
with the same values.)

### 3c. $/s updates on every 0e site, upgrade included

Same derivation from `syncClientState(profile)`: `devSetSlimeLevel`,
`devWipeProfile`, `onPlayerAdded`, `placeFromInventory`, `receiveSlime`,
`recordChestOpened`, `removeToInventory`, `sellFromInventory`, `upgradeSlime` —
**all nine refresh.**

Plus a stronger, line-level check: **10 of 10** `syncClientState(profile)` call
sites are immediately followed by a `refreshLeaderstats(profile)` line (skipping
blank lines left by stripped comments), so a refresh sitting in a different
branch of the same function cannot satisfy the rule.

And `upgradeSlime` is asserted **by name**, twice: that it refreshes, and that it
really is a rate-change site.

### 3d. Swing updates on tier purchase

`buyNextTier` asserted by name. Derived tier-write set:
`buyNextTier`, `devSetSwingTier`, `devWipeProfile`, `onPlayerAdded` — all
refresh.

### 3e. `MoneyFormat` at the extremes

Every value run through the real module and compared against an expected string:

| value | expected | result |
|---|---|---|
| 0 | `$0` | PASS |
| 999 | `$999` | PASS |
| 1,500 | `$1.5K` | PASS |
| 9,100,000 | `$9.1M` | PASS |
| 800,000,000,000 | `$800B` | PASS |
| 244,459,004.67 | `$244.5M` | PASS |
| 2,147,483,647 | `$2.1B` | PASS |

The ceiling income is **derived, not quoted**: the top slime in `SlimeData` is
$854K/s, times `SLOT_COUNT` (10) is $8.54M/s of base, times
`SlimeUpgrade.incomeMultiplier(MAX_LEVEL)` (28.6252) is **$244,459,004.67/s** —
matching the brief's $244.5M exactly.

Two further assertions rather than claims:

- `topPrice > INT_VALUE_MAX` — the overflow argument, measured.
- `MoneyFormat.format(9100000) > MoneyFormat.format(800e9)` — **the accepted
  sort cost, demonstrated**: `"$9.1M"` really does sort above `"$800B"`.

And three fractional inputs (0.5, 12.75, 999.99) confirm the sub-$1,000 integer
path tolerates the non-integer money the accrual actually produces.

### 3f. No value flashes wrong during the load window

Covered by 3a's source-order assertions. The board never displays a value that
is not true of the profile at that instant: before the load it shows a fresh
profile because the profile *is* fresh, and the single correcting write happens
after every piece of loaded state has landed.

### 3g. Nothing added to the save shape

`toSaveShape` writes exactly ten fields, unchanged:

```
chestPending, chestsOpened, inventory, lastSeen, levels,
money, pendingBySlot, seen, slots, swingTier
```

Asserted as an exact sorted-list equality, plus that the function never mentions
`leaderstats`.

---

## THE SEPARATE FIX — `verify_sound.luau`

Commit `bf31d6b`, before the leaderboard work.

**The bug.** Its final check ran
`git diff --numstat 2d28d1d HEAD -- src` and required no pre-existing file to
have lost a line. `2d28d1d` is the sound pass's base — but the far end was
**HEAD**, which quietly turned a claim about *one pass* into a claim about *every
commit ever made after it*.

The per-slot collection pass legitimately deleted lines in five files, so from
`76071f0` onward the check failed permanently, for a reason it was never written
to detect:

```
BaseConfig.luau +99 -106   BaseGeometry.luau +14 -85   OfflineIncome.luau +23 -12
PlayerProfile.luau +462 -214   BaseClient.client.luau +213 -104
```

**The fix.** Both ends are now the sound pass's own commits —
`BASE_COMMIT = "2d28d1d"`, `END_COMMIT = "59e38c2"` — so the diff describes
exactly the change the file was written to police, and stays true whatever lands
afterwards. The comment says what to do if the sound system is ever edited again:
re-point `END_COMMIT` at that work's own tip, not unpin it.

**All six verify scripts after the fix:**

| script | result |
|---|---|
| `verify_ladder` | PASS |
| `verify_sound` | **PASS** (was failing) |
| `verify_anchor` | PASS |
| `verify_divine` | PASS |
| `verify_offline` | PASS |
| `verify_leaderstats` | PASS (new) |

---

## WHERE I CHOSE

| choice | rejected alternative |
|---|---|
| `refreshLeaderstats(profile)` — profile only | `(player, profile)` as briefed — `bankSlot` and the load path have no Player in scope, so it would need threading or a reverse lookup for no gain |
| leaderstats built in `PlayerProfile`, beside `buildBaseFolder` | a separate script — would need its own profile lookup and its own hooks into all fifteen sites |
| the record of four instances carried on the Profile | holding only the folder and calling `FindFirstChild` per refresh — re-deriving a constant |
| `StringValue` + `MoneyFormat` for Money and $/s | `IntValue` (overflows at $2.1B against an $800B top tier) or `NumberValue` (renders as `8.0000000000e+11`) |
| built before the load at fresh-profile values | built after the load — no row during the read, and none at all for a failed load |
| bare `$5.4K` in the $/s column | `$5.4K/s`, which reads as "$5.4K/s per second" under a `$/s` header |
| refresh called at all 15 sites, guarded by a same-value check | hooking `GetAttributeChangedSignal` on the base folder — structurally airtight, but deferred-signal timing and an invisible update path in a codebase where every other cross-cutting update is a direct call |
| verification derives the write-site set from the file | a hand-written list of functions — stale the moment a site is added |

## WHAT I DID NOT TOUCH

`SlimeRoll.luau`, the income tables, weight ratios, luck constants and spreads;
the chest table, the ladder, every price, the upgrade curve, `SLOT_COUNT`; the
flight formulas, the ping compensation, the sweet-spot constants; the collect
system (per-slot pots, the accrual, the pads, the debounce — `bankSlot` gained
one line *below* its atomic stretch and nothing else); the sound registry and
every nil asset ID; `PlayerStore.luau`; `LaunchRewardScene.luau` (not opened);
every file in `dev/out/`; the HUD stack (`BaseClient.client.luau` is byte-for-byte
unchanged).

**Note on the working tree:** three files from the previous pass's survey
(`dev/analysis/levelling_gap.luau`, `dev/analysis/levelling_surfaces.luau`,
`dev/out/levelling_gap.json`) were left uncommitted by that pass and are
deliberately still untracked — they are not part of this work and were not swept
into either commit.
