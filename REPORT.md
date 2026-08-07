# Slime upgrade curve, rebuilt

25 levels, flat 1.15x compounding identical for every tier, cost pinned to a constant
600-second payback. The per-tier multiplier ladder, the quadratic income shape and the
base-income cost fit are gone.

**Verification:** computed from the live modules loaded through `dev/rbxshim.luau` under Lune.
No playtest was run (none was permitted).

---

## Constants

`src/ReplicatedStorage/Config/SlimeUpgradeConfig.luau` now holds exactly three values:

| constant | value | meaning |
|---|---|---|
| `MAX_LEVEL` | **25** | was 1000 |
| `UPGRADE_GROWTH_RATE` | **0.15** | income multiplies by 1.15 per level |
| `UPGRADE_PAYBACK_SECONDS` | **600** | how long one level takes to pay for itself |

Cost of the next level = `UPGRADE_PAYBACK_SECONDS × UPGRADE_GROWTH_RATE × current income/s`
= 90x current income at these values. **90 is not written anywhere** — it is the product of the
two named constants, computed in `SlimeUpgrade.totalUpgradeCost`.

---

## 1. The multiplier table

Identical for every tier. `multiplier(level) = 1.15^(level-1)`.

| level | multiplier |
|---|---|
| 1 | 1.0000x |
| 5 | 1.7490x |
| 10 | 3.5179x |
| 15 | 7.0757x |
| 20 | 14.2318x |
| 25 | **28.6252x** |

`1.15^24 = 28.625176`; `incomeMultiplier(25) = 28.625176`; difference **0.000e+00**.

Confirmed identical across all eight tiers:

| tier | base | maxed | multiplier |
|---|---|---|---|
| Common | $7.00/s | $200/s | 28.6252x |
| Uncommon | $19/s | $544/s | 28.6252x |
| Rare | $45/s | $1.29K/s | 28.6252x |
| Epic | $110/s | $3.15K/s | 28.6252x |
| Legendary | $350/s | $10.0K/s | 28.6252x |
| Mythic | $1.10K/s | $31.5K/s | 28.6252x |
| Secret | $9.00K/s | $258K/s | 28.6252x |
| Divine | $100K/s | $2.86M/s | 28.6252x |

(Representative slime per tier = the median-income entry of that tier's list, same convention
as `ECONOMY_DUMP.md`.)

---

## 2. Cost of each level, and cumulative to max

Note the **"seconds of base income" columns are identical for both tiers** — that is the point
of the rebuild. Every tier now pays the same relative price for the same level.

### Common, base $7.00/s

| level | income/s | cost of +1 | cost (s of base) | cumulative | cumul (s of base) |
|---|---|---|---|---|---|
| 1 | $7.00 | $630 | 90.0 | $0 | 0.0 |
| 2 | $8.05 | $724 | 103.5 | $630 | 90.0 |
| 3 | $9.26 | $833 | 119.0 | $1.35K | 193.5 |
| 4 | $11 | $958 | 136.9 | $2.19K | 312.5 |
| 5 | $12 | $1.10K | 157.4 | $3.15K | 449.4 |
| 6 | $14 | $1.27K | 181.0 | $4.25K | 606.8 |
| 7 | $16 | $1.46K | 208.2 | $5.51K | 787.8 |
| 8 | $19 | $1.68K | 239.4 | $6.97K | 996.0 |
| 9 | $21 | $1.93K | 275.3 | $8.65K | 1235.4 |
| 10 | $25 | $2.22K | 316.6 | $10.6K | 1510.7 |
| 11 | $28 | $2.55K | 364.1 | $12.8K | 1827.3 |
| 12 | $33 | $2.93K | 418.7 | $15.3K | 2191.4 |
| 13 | $37 | $3.37K | 481.5 | $18.3K | 2610.2 |
| 14 | $43 | $3.88K | 553.8 | $21.6K | 3091.7 |
| 15 | $50 | $4.46K | 636.8 | $25.5K | 3645.4 |
| 16 | $57 | $5.13K | 732.3 | $30.0K | 4282.2 |
| 17 | $66 | $5.90K | 842.2 | $35.1K | 5014.6 |
| 18 | $75 | $6.78K | 968.5 | $41.0K | 5856.8 |
| 19 | $87 | $7.80K | 1113.8 | $47.8K | 6825.3 |
| 20 | $100 | $8.97K | 1280.9 | $55.6K | 7939.1 |
| 21 | $115 | $10.3K | 1473.0 | $64.5K | 9219.9 |
| 22 | $132 | $11.9K | 1693.9 | $74.9K | 10692.9 |
| 23 | $152 | $13.6K | 1948.0 | $86.7K | 12386.8 |
| 24 | $174 | $15.7K | 2240.2 | $100K | 14334.9 |
| 25 | $200 | — (max) | — | **$116K** | **16575.1** |

### Divine, base $100K/s

| level | income/s | cost of +1 | cost (s of base) | cumulative | cumul (s of base) |
|---|---|---|---|---|---|
| 1 | $100K | $9.00M | 90.0 | $0 | 0.0 |
| 2 | $115K | $10.3M | 103.5 | $9.00M | 90.0 |
| 3 | $132K | $11.9M | 119.0 | $19.3M | 193.5 |
| 4 | $152K | $13.7M | 136.9 | $31.3M | 312.5 |
| 5 | $175K | $15.7M | 157.4 | $44.9M | 449.4 |
| 6 | $201K | $18.1M | 181.0 | $60.7M | 606.8 |
| 7 | $231K | $20.8M | 208.2 | $78.8M | 787.8 |
| 8 | $266K | $23.9M | 239.4 | $99.6M | 996.0 |
| 9 | $306K | $27.5M | 275.3 | $124M | 1235.4 |
| 10 | $352K | $31.7M | 316.6 | $151M | 1510.7 |
| 11 | $405K | $36.4M | 364.1 | $183M | 1827.3 |
| 12 | $465K | $41.9M | 418.7 | $219M | 2191.4 |
| 13 | $535K | $48.2M | 481.5 | $261M | 2610.2 |
| 14 | $615K | $55.4M | 553.8 | $309M | 3091.7 |
| 15 | $708K | $63.7M | 636.8 | $365M | 3645.4 |
| 16 | $814K | $73.2M | 732.3 | $428M | 4282.2 |
| 17 | $936K | $84.2M | 842.2 | $501M | 5014.6 |
| 18 | $1.08M | $96.9M | 968.5 | $586M | 5856.8 |
| 19 | $1.24M | $111M | 1113.8 | $683M | 6825.3 |
| 20 | $1.42M | $128M | 1280.9 | $794M | 7939.1 |
| 21 | $1.64M | $147M | 1473.0 | $922M | 9219.9 |
| 22 | $1.88M | $169M | 1693.9 | $1.07B | 10692.9 |
| 23 | $2.16M | $195M | 1948.0 | $1.24B | 12386.8 |
| 24 | $2.49M | $224M | 2240.2 | $1.43B | 14334.9 |
| 25 | $2.86M | — (max) | — | **$1.66B** | **16575.1** |

**Full max costs 16,575 seconds of base income — 4.6 hours of that slime's unlevelled
production — for every slime in the game.** Common and Divine differ only in the dollar
figures, never in the relative price.

---

## 3. The payback identity

`payback = cost of +1 ÷ (income(L+1) − income(L))`. Algebraically:

```
cost = PAYBACK × RATE × I
gain = (1 + RATE) × I − I = RATE × I
cost / gain = PAYBACK          -- I and RATE both cancel
```

Both `I` and `RATE` cancel, so payback is independent of level, of tier, and of base income.
Computed from the live module:

| level | Common payback (s) | Divine payback (s) | abs diff |
|---|---|---|---|
| 1 | 600.000000000000 | 600.000000000000 | 1.137e-13 |
| 5 | 600.000000000000 | 600.000000000000 | 4.547e-13 |
| 10 | 600.000000000001 | 600.000000000000 | 1.137e-13 |
| 20 | 599.999999999999 | 600.000000000000 | 4.547e-13 |
| 24 | 600.000000000000 | 600.000000000000 | 0.000e+00 |

**They match to floating-point noise** — worst difference 5.684e-13, which is ~1 part in 10^15.

Two stronger checks, both exhaustive rather than sampled:

- **All 65 slimes × all 24 levels:** worst `|payback − 600|` = **1.478e-12**.
- **Every (slime, level, count) multi-level purchase:** worst `|payback − 600|` = **1.478e-12**.

The multi-level case holds for the same reason and is worth stating explicitly, because the
closed form makes it non-obvious: `n` levels cost `PAYBACK × I × (G^n − 1)` and buy a gain of
exactly `I × (G^n − 1)`, so the ratio is `PAYBACK` for every `n`. Buying MAX is priced
identically to buying the levels one at a time — there is no bulk discount and no bulk penalty.

---

## 4. A maxed Common against every tier's base income

Maxing multiplies by 28.63x, which sits between three and four tier steps (tier bases step
2.4x–3.2x through the mid ladder).

**Common at the tier's median base, $7.00/s → $200/s maxed:**

| vs tier | base range | mean | verdict |
|---|---|---|---|
| Common | $5.00 – $10 | $7.50 | beats the whole tier |
| Uncommon | $15 – $25 | $20 | beats the whole tier |
| Rare | $35 – $60 | $48 | **beats the whole tier** |
| Epic | $80 – $150 | $117 | beats the whole tier |
| Legendary | $250 – $500 | $375 | **loses to the whole tier** |
| Mythic | $800 – $1.50K | $1.17K | loses to the whole tier |
| Secret | $3.00K – $20.0K | $10.3K | loses to the whole tier |
| Divine | $50.0K – $350K | $146K | loses to the whole tier |

**Beats Rare, loses to Legendary — as intended.** It also clears Epic outright, which is the
one thing beyond the stated target; at 28.63x that is unavoidable, since Rare-max ($60) to
Legendary-min ($250) is only a 4.2x window and the multiplier has to land somewhere inside a
much wider span.

Sensitivity across the Common tier's own spread:

| Common base | maxed | first tier it fails to beat outright |
|---|---|---|
| $5.00 (worst) | $143/s | Epic (beats the average, loses to the best) |
| $7.00 (median) | $200/s | Legendary |
| $10 (best) | $286/s | Legendary (beats the worst Legendary only) |

So a maxed Common is worth roughly "a fresh Epic, or a bad Legendary" across the whole tier.
Both levelling and rolling stay worth doing, which was the goal.

---

## 5. Buttons: +1 / +5 / MAX

Changed in **both** surfaces, identically:

- `src/StarterPlayer/StarterPlayerScripts/InventoryClient.client.luau` (the panel)
- `src/StarterPlayer/StarterPlayerScripts/SlimeUpgradeTagClient.client.luau` (the on-slime strip)

Both now share the same declarative spec:

```lua
local UPGRADE_BUTTONS = {
    { count = 1, label = "+1" },
    { count = 5, label = "+5" },
    { count = SlimeUpgradeConfig.MAX_LEVEL, label = "MAX" },
}
```

**MAX sends `MAX_LEVEL` and lets the server cap it.** No separate remote, no separate code
path, no client-side "how many are left" arithmetic that could disagree with the server.
`totalUpgradeCost` already caps any count at the levels remaining and returns the real number,
which is what the label displays:

| from level | count returned | expected | cost (Common $7) |
|---|---|---|---|
| 1 | 24 | 24 | $116K |
| 5 | 20 | 20 | $113K |
| 13 | 12 | 12 | $97.8K |
| 24 | 1 | 1 | $15.7K |
| 25 | 0 | 0 | $0 |

Labels: `+1` / `+5` show `+n (cost)` using the **actual** count, so near the cap `+5` honestly
reads `+2`. MAX shows `MAX +n (cost)`. A maxed slime shows `MAXED` on all three, greyed.

### Server validation — confirmed, and unchanged

The client sends **only `(slotNumber, count)`**. No price, no level, no slime identity. There
is nothing in the message for a modified client to inflate.

`PlayerProfile.upgradeSlime` (PlayerProfile.luau:908) independently:

1. resolves the slot from **its own** `profile.slots`, rejecting empty/invalid slots;
2. reads the current level from **its own** `profile.levels`;
3. rejects outright if already at `MAX_LEVEL`;
4. calls `SlimeUpgrade.totalUpgradeCost(slime.incomePerSecond, currentLevel, count)` — the
   price is derived from server-held state and the *server's* copy of the shared formula;
5. binary-searches the largest affordable count against **its own** `profile.money` if the
   full amount is unaffordable;
6. charges that recomputed cost and writes the new level.

A client sending `count = 999999` gets capped to the levels remaining and then to what it can
afford. A client sending a garbage type is rejected by `UpgradeServer`'s `typeof` guard before
it ever reaches this. The MAX button deliberately relies on exactly that capping rather than
working around it.

---

## 6. Migration: saved levels above 25

**Decision: clamp to 25, which the existing code already does.**
`PlayerProfile.applyLoadedData` (PlayerProfile.luau:584) runs every loaded level through
`SlimeUpgrade.clampLevel`, which clamps to `[1, MAX_LEVEL]`. Lowering `MAX_LEVEL` from 1000 to
25 makes that the migration with no new code. Verified: `clampLevel(1000) = 25`,
`clampLevel(26) = 25`, `clampLevel(0) = 1`, `clampLevel(12.7) = 12`.

### What it costs the player

A slime saved at level 1000 was earning `base × 1700` (Common) up to `base × 1,479,582`
(Divine) under the old curve. After clamping it earns `base × 28.63`. In the worst case — a
maxed Divine — that is a **~51,700x income reduction on that slot**; a maxed Common loses
~59x. The money spent on those levels is not refunded, and there is no record of it to refund
from: the profile stores the level, not the spend.

That sounds severe and mostly is not, for two reasons worth separating:

- **The whole economy is rescaled together.** Every slime, every player, and (through the roll
  fix in the previous pass) every income figure moved. A player who was earning astronomically
  is now earning proportionally to everyone else. The loss is in absolute dollars, not in
  standing.
- **The old numbers were the bug.** A level-1000 Divine at 1.48 million times base was the
  double-counting this rebuild exists to remove.

It is still a real loss for anyone who had levelled deeply, and I want to be plain that
clamping is a *choice with a cost*, not a free operation. Three alternatives I considered:

1. **Refund the difference in money.** Not possible from the stored data — the profile records
   only the resulting level, and reconstructing the spend needs the old cost curve, which is
   being deleted. It could be done by keeping the old formula around purely for migration, but
   that means shipping the thing being removed and running it against saves whose provenance
   is unknown.
2. **Grandfather old slimes above the cap.** Rejected — it makes `MAX_LEVEL` not a cap,
   reintroduces the per-tier income explosion for exactly the players who least need it, and
   every consumer of `level` would need a second code path.
3. **One-off compensating grant** (e.g. money proportional to slots held above 25). Viable,
   and separable from this change. If you want it, it needs deciding before the first server
   runs this build — after that the old levels are gone from every profile that has loaded.

**If the game has not shipped**, none of this matters and the clamp is simply correct.

### Everything else that reads `level`

Audited; all of it is display or income derived from the same clamped value, so nothing needs
a migration of its own:

| site | use |
|---|---|
| `PlayerProfile.spawnSlimeVisual` | `incomeForLevel` for the nametag income line |
| `PlayerProfile.refreshSlimeVisualLabel` | `"%s (Lv %d)"` + income after an upgrade |
| `PlayerProfile.syncClientState` | packs `level` into the replicated `Slots` JSON |
| income tick loop (PlayerProfile.luau:1059) | `incomeForLevel` summed across slots |
| `InventoryClient.buildBaseRow` | row label + button prices |
| `SlimeUpgradeTagClient.refreshTag` | on-slime button prices |
| `PlayerProfile.devSetSlimeLevel` | dev panel, already `clampLevel`ed |
| `DevPanelClient` | placeholder text reads `MAX_LEVEL`, so it now says "1-25" automatically |

No persistence format changed. A profile written by this build is readable by the old one
(levels are just small numbers) and vice versa.

---

## 7. What was deleted

### From `SlimeUpgradeConfig.luau`

| removed | why |
|---|---|
| `INCOME_MAX_MULTIPLIER_BASE` (1700.0) | per-tier multiplier ladder is gone |
| `INCOME_MAX_MULTIPLIER_RATIO` (2.63) | as above — **confirmed no other reader** |
| `INCOME_LEVEL_LINEAR_COEFF` (39.0) | quadratic income shape is gone |
| `INCOME_LEVEL_QUADRATIC_COEFF` (0.486) | as above |
| `UPGRADE_COST_SECONDS_AT_LEVEL_1` (693.0) | old base-income cost fit |
| `UPGRADE_COST_SECONDS_SLOPE_PER_LEVEL` (309.0) | as above |

All six removed from the exported `SlimeUpgradeConfig` type as well as the table.

### From `SlimeUpgrade.luau`

| removed | why |
|---|---|
| `maxMultiplierByTier` generated table | growth is tier-independent |
| `tierByBaseIncome` reverse lookup | nothing needs a slime's tier any more |
| `SHAPE_VALUE_AT_MAX_LEVEL` normalisation constant | no shape to normalise |
| `upgradeCostSeconds(level)` local | replaced by the closed form |
| `require(SlimeConfig)`, `require(SlimeData)` | no longer read at all |

The `tierByBaseIncome` removal also retires a documented fragility: it required all 65 slimes
to have **distinct** base incomes and would have silently picked whichever was inserted first
if two ever collided. That failure mode cannot occur now because nothing looks up a tier.

`SlimeUpgrade.incomeMultiplier` changed signature from `(baseIncomePerSecond, level)` to
`(level)` — the base was only ever used for the tier lookup. Checked: no external caller;
`incomeForLevel` was the only user.

### Comments removed or rewritten

- The whole "fitted against the reference Secret slime table, max relative error ~5.6%" block.
- The log-linear regression narrative for the 1,700x / 562,600x / 1,479,700x per-tier fit.
- The claim that level 901 costs "~0.65 seconds of its own income" — true only for Secret, and
  the reason the old curve looked correct in review.
- `+1/+10/+100` references in both client headers, `UpgradeServer`'s remote contract comment,
  `InventoryClient.buildBaseRow`'s header, and the "TextScaled still fits +100" note.
- `PlayerProfile.upgradeSlime`'s "a client showing +100" example and the binary search's
  "never a loop over up to 1000 levels" justification.

---

## Files changed

| file | change |
|---|---|
| `Config/SlimeUpgradeConfig.luau` | rewritten — 6 constants out, 2 in, `MAX_LEVEL` 1000 → 25 |
| `Config/SlimeUpgrade.luau` | rewritten — compounding multiplier, closed-form geometric cost |
| `ServerScriptService/PlayerProfile.luau` | two stale comments only; **no logic change** |
| `ServerScriptService/UpgradeServer.server.luau` | remote contract comment only |
| `StarterPlayerScripts/InventoryClient.client.luau` | button spec + labels |
| `StarterPlayerScripts/SlimeUpgradeTagClient.client.luau` | button spec + labels |

All parse clean. Temporary analysis scripts deleted.

`ECONOMY_DUMP.md` is now stale in two more places (§2 the cost curve, §3 ROI) on top of the §1
and §7.1 staleness from the roll-distribution pass. Regenerating it is still a separate ask —
worth doing now that both the roll and the upgrade curves have moved, since §6's
swing-vs-upgrade ratio was the finding that started all of this and it will look very
different.

**Untracked, not staged:** `REPORT.md`, `ECONOMY_DUMP.md`. `.gitignore` not modified.
