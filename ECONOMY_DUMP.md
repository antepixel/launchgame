# Economy dump

Regenerated from the live config modules through `dev/rbxshim.luau` under Lune. Supersedes
the previous dump entirely: this one postdates **both** the roll-distribution fix (six
retuned spread/shape constants, expected income now monotonic in luck) and the **upgrade
curve rebuild** (25 levels, flat 1.15x compounding, 600-second payback). No playtest was run.

Sources: `LuckCurve`, `SlimeConfig`, `SlimeData`, `SlimeRoll`, `SlimeUpgrade`,
`SlimeUpgradeConfig`, `ShopConfig`, `LaunchConfig`.

Constants in play: `MAX_LEVEL` = 25, `UPGRADE_GROWTH_RATE` = 0.15, `UPGRADE_PAYBACK_SECONDS` = 600,
`BOX_DOUBLE_CHANCE` = 0.55, 74 bands, 65 slimes across 8 tiers, 11 swing tiers.

A fully maxed slime earns **28.6252x** its base income, the same for every tier.

## 1. The full luck distribution

The roll is a sliding window: `SlimeRoll.distributionForLuck` moves a 4-tier window up the
ladder on log-luck and shapes a generalised Gaussian inside it. Tiers outside the window are
exactly zero by construction. Probabilities below are the actual computed weights per band.

`typ` = peak (modal) tier. `+2` = the tier two above it, which the config's own rule says must
sit at 1-5%.

| band | luck | window | typ | Common | Uncommon | Rare | Epic | Legendary | Mythic | Secret | Divine | +2 tier | +2 P |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 5 | Common-Epic | Uncommon | 12.13% | 69.56% | 15.82% | 2.49% | - | - | - | - | Epic | 2.49% |
| 1 | 10 | Common-Epic | Uncommon | 12.09% | 69.59% | 15.82% | 2.49% | - | - | - | - | Epic | 2.49% |
| 2 | 15 | Common-Epic | Uncommon | 11.83% | 69.78% | 15.84% | 2.56% | - | - | - | - | Epic | 2.56% |
| 3 | 20 | Common-Epic | Uncommon | 11.64% | 69.91% | 15.85% | 2.60% | - | - | - | - | Epic | 2.60% |
| 4 | 25 | Common-Epic | Uncommon | 11.50% | 70.01% | 15.85% | 2.64% | - | - | - | - | Epic | 2.64% |
| 5 | 30 | Common-Epic | Uncommon | 11.38% | 70.09% | 15.86% | 2.67% | - | - | - | - | Epic | 2.67% |
| 6 | 35 | Common-Epic | Uncommon | 11.28% | 70.16% | 15.86% | 2.69% | - | - | - | - | Epic | 2.69% |
| 7 | 40 | Common-Epic | Uncommon | 11.20% | 70.21% | 15.87% | 2.72% | - | - | - | - | Epic | 2.72% |
| 8 | 45 | Common-Epic | Uncommon | 11.12% | 70.27% | 15.87% | 2.74% | - | - | - | - | Epic | 2.74% |
| 9 | 50 | Common-Epic | Uncommon | 11.06% | 70.31% | 15.88% | 2.75% | - | - | - | - | Epic | 2.75% |
| 10 | 55 | Common-Epic | Uncommon | 11.00% | 70.35% | 15.88% | 2.77% | - | - | - | - | Epic | 2.77% |
| 11 | 60 | Common-Epic | Uncommon | 10.94% | 70.39% | 15.88% | 2.79% | - | - | - | - | Epic | 2.79% |
| 12 | 65 | Common-Epic | Uncommon | 10.89% | 70.42% | 15.89% | 2.80% | - | - | - | - | Epic | 2.80% |
| 13 | 70 | Common-Epic | Uncommon | 10.85% | 70.45% | 15.89% | 2.81% | - | - | - | - | Epic | 2.81% |
| 14 | 75 | Common-Epic | Uncommon | 10.80% | 70.48% | 15.89% | 2.83% | - | - | - | - | Epic | 2.83% |
| 15 | 80 | Common-Epic | Uncommon | 10.76% | 70.51% | 15.89% | 2.84% | - | - | - | - | Epic | 2.84% |
| 16 | 85 | Common-Epic | Uncommon | 10.72% | 70.53% | 15.90% | 2.85% | - | - | - | - | Epic | 2.85% |
| 17 | 90 | Common-Epic | Uncommon | 10.69% | 70.56% | 15.90% | 2.86% | - | - | - | - | Epic | 2.86% |
| 18 | 95 | Common-Epic | Uncommon | 10.65% | 70.58% | 15.90% | 2.87% | - | - | - | - | Epic | 2.87% |
| 19 | 100 | Common-Epic | Uncommon | 10.62% | 70.60% | 15.90% | 2.88% | - | - | - | - | Epic | 2.88% |
| 20 | 150 | Common-Epic | Uncommon | 10.37% | 70.76% | 15.92% | 2.95% | - | - | - | - | Epic | 2.95% |
| 21 | 200 | Common-Epic | Uncommon | 10.19% | 70.87% | 15.93% | 3.00% | - | - | - | - | Epic | 3.00% |
| 22 | 250 | Common-Epic | Uncommon | 10.06% | 70.96% | 15.94% | 3.04% | - | - | - | - | Epic | 3.04% |
| 23 | 300 | Common-Epic | Uncommon | 9.95% | 71.03% | 15.95% | 3.08% | - | - | - | - | Epic | 3.08% |
| 24 | 350 | Common-Epic | Uncommon | 9.85% | 71.08% | 15.95% | 3.11% | - | - | - | - | Epic | 3.11% |
| 25 | 400 | Common-Epic | Uncommon | 9.77% | 71.13% | 15.96% | 3.13% | - | - | - | - | Epic | 3.13% |
| 26 | 450 | Common-Epic | Uncommon | 9.70% | 71.18% | 15.97% | 3.16% | - | - | - | - | Epic | 3.16% |
| 27 | 500 | Uncommon-Legendary | Rare | - | 9.64% | 71.21% | 15.97% | 3.18% | - | - | - | Legendary | 3.18% |
| 28 | 550 | Uncommon-Legendary | Rare | - | 9.58% | 71.25% | 15.98% | 3.20% | - | - | - | Legendary | 3.20% |
| 29 | 600 | Uncommon-Legendary | Rare | - | 9.53% | 71.28% | 15.98% | 3.21% | - | - | - | Legendary | 3.21% |
| 30 | 650 | Uncommon-Legendary | Rare | - | 9.48% | 71.31% | 15.98% | 3.23% | - | - | - | Legendary | 3.23% |
| 31 | 700 | Uncommon-Legendary | Rare | - | 9.44% | 71.33% | 15.99% | 3.25% | - | - | - | Legendary | 3.25% |
| 32 | 750 | Uncommon-Legendary | Rare | - | 9.40% | 71.35% | 15.99% | 3.26% | - | - | - | Legendary | 3.26% |
| 33 | 800 | Uncommon-Legendary | Rare | - | 9.36% | 71.38% | 15.99% | 3.27% | - | - | - | Legendary | 3.27% |
| 34 | 850 | Uncommon-Legendary | Rare | - | 9.32% | 71.40% | 16.00% | 3.28% | - | - | - | Legendary | 3.28% |
| 35 | 900 | Uncommon-Legendary | Rare | - | 9.29% | 71.42% | 16.00% | 3.30% | - | - | - | Legendary | 3.30% |
| 36 | 950 | Uncommon-Legendary | Rare | - | 9.26% | 71.43% | 16.00% | 3.31% | - | - | - | Legendary | 3.31% |
| 37 | 1,000 | Uncommon-Legendary | Rare | - | 9.23% | 71.45% | 16.00% | 3.32% | - | - | - | Legendary | 3.32% |
| 38 | 1,500 | Uncommon-Legendary | Rare | - | 8.99% | 71.58% | 16.02% | 3.40% | - | - | - | Legendary | 3.40% |
| 39 | 2,000 | Uncommon-Legendary | Rare | - | 8.82% | 71.67% | 16.04% | 3.46% | - | - | - | Legendary | 3.46% |
| 40 | 2,500 | Rare-Mythic | Epic | - | - | 8.69% | 71.74% | 16.05% | 3.51% | - | - | Mythic | 3.51% |
| 41 | 3,000 | Rare-Mythic | Epic | - | - | 8.59% | 71.80% | 16.06% | 3.55% | - | - | Mythic | 3.55% |
| 42 | 3,500 | Rare-Mythic | Epic | - | - | 8.50% | 71.84% | 16.07% | 3.59% | - | - | Mythic | 3.59% |
| 43 | 4,000 | Rare-Mythic | Epic | - | - | 8.42% | 71.88% | 16.08% | 3.62% | - | - | Mythic | 3.62% |
| 44 | 4,500 | Rare-Mythic | Epic | - | - | 8.36% | 71.91% | 16.08% | 3.64% | - | - | Mythic | 3.64% |
| 45 | 5,000 | Rare-Mythic | Epic | - | - | 8.30% | 71.94% | 16.09% | 3.67% | - | - | Mythic | 3.67% |
| 46 | 5,500 | Rare-Mythic | Epic | - | - | 8.24% | 71.97% | 16.10% | 3.69% | - | - | Mythic | 3.69% |
| 47 | 6,000 | Rare-Mythic | Epic | - | - | 8.20% | 71.99% | 16.10% | 3.71% | - | - | Mythic | 3.71% |
| 48 | 6,500 | Rare-Mythic | Epic | - | - | 8.15% | 72.01% | 16.11% | 3.73% | - | - | Mythic | 3.73% |
| 49 | 7,000 | Rare-Mythic | Epic | - | - | 8.11% | 72.03% | 16.11% | 3.75% | - | - | Mythic | 3.75% |
| 50 | 7,500 | Rare-Mythic | Epic | - | - | 8.07% | 72.05% | 16.11% | 3.76% | - | - | Mythic | 3.76% |
| 51 | 8,000 | Rare-Mythic | Epic | - | - | 8.04% | 72.07% | 16.12% | 3.78% | - | - | Mythic | 3.78% |
| 52 | 8,500 | Rare-Mythic | Epic | - | - | 8.00% | 72.08% | 16.12% | 3.79% | - | - | Mythic | 3.79% |
| 53 | 9,000 | Rare-Mythic | Epic | - | - | 7.97% | 72.10% | 16.13% | 3.80% | - | - | Mythic | 3.80% |
| 54 | 9,500 | Rare-Mythic | Epic | - | - | 7.94% | 72.11% | 16.13% | 3.82% | - | - | Mythic | 3.82% |
| 55 | 10,000 | Rare-Mythic | Epic | - | - | 7.91% | 72.13% | 16.13% | 3.83% | - | - | Mythic | 3.83% |
| 56 | 15,000 | Epic-Secret | Legendary | - | - | - | 7.69% | 72.23% | 16.16% | 3.93% | - | Secret | 3.93% |
| 57 | 20,000 | Epic-Secret | Legendary | - | - | - | 7.53% | 72.29% | 16.18% | 4.00% | - | Secret | 4.00% |
| 58 | 25,000 | Epic-Secret | Legendary | - | - | - | 7.41% | 72.34% | 16.19% | 4.05% | - | Secret | 4.05% |
| 59 | 30,000 | Epic-Secret | Legendary | - | - | - | 7.31% | 72.38% | 16.20% | 4.10% | - | Secret | 4.10% |
| 60 | 35,000 | Epic-Secret | Legendary | - | - | - | 7.23% | 72.41% | 16.21% | 4.14% | - | Secret | 4.14% |
| 61 | 40,000 | Epic-Secret | Legendary | - | - | - | 7.16% | 72.44% | 16.22% | 4.17% | - | Secret | 4.17% |
| 62 | 45,000 | Epic-Secret | Legendary | - | - | - | 7.10% | 72.47% | 16.23% | 4.21% | - | Secret | 4.21% |
| 63 | 50,000 | Epic-Secret | Legendary | - | - | - | 7.04% | 72.49% | 16.24% | 4.23% | - | Secret | 4.23% |
| 64 | 55,000 | Legendary-Divine | Mythic | - | - | - | - | 6.99% | 72.50% | 16.24% | 4.26% | Divine | 4.26% |
| 65 | 60,000 | Legendary-Divine | Mythic | - | - | - | - | 6.95% | 72.52% | 16.25% | 4.28% | Divine | 4.28% |
| 66 | 65,000 | Legendary-Divine | Mythic | - | - | - | - | 6.91% | 72.54% | 16.26% | 4.30% | Divine | 4.30% |
| 67 | 70,000 | Legendary-Divine | Mythic | - | - | - | - | 6.87% | 72.55% | 16.26% | 4.32% | Divine | 4.32% |
| 68 | 75,000 | Legendary-Divine | Mythic | - | - | - | - | 6.83% | 72.56% | 16.27% | 4.34% | Divine | 4.34% |
| 69 | 80,000 | Legendary-Divine | Mythic | - | - | - | - | 6.80% | 72.57% | 16.27% | 4.36% | Divine | 4.36% |
| 70 | 85,000 | Legendary-Divine | Mythic | - | - | - | - | 6.77% | 72.58% | 16.28% | 4.37% | Divine | 4.37% |
| 71 | 90,000 | Legendary-Divine | Mythic | - | - | - | - | 6.74% | 72.59% | 16.28% | 4.39% | Divine | 4.39% |
| 72 | 95,000 | Legendary-Divine | Mythic | - | - | - | - | 6.71% | 72.60% | 16.28% | 4.40% | Divine | 4.40% |
| 73 | 100,000 | Legendary-Divine | Mythic | - | - | - | - | 6.68% | 72.61% | 16.29% | 4.42% | Divine | 4.42% |

**+2 tail range across all 74 bands: 2.49% to 4.42%.** Bands outside the 1-5% rule: **0**.
**Expected income decreases from one band to the next: 0.** (Was 69 of 73 before the fix.)

### Window transitions

| at band | luck | window becomes | peak becomes |
|---|---|---|---|
| 0 | 5 | Common-Epic | Uncommon |
| 27 | 500 | Uncommon-Legendary | Rare |
| 40 | 2,500 | Rare-Mythic | Epic |
| 56 | 15,000 | Epic-Secret | Legendary |
| 64 | 55,000 | Legendary-Divine | Mythic |

## 2. The upgrade cost curve

Representative slime per tier = the median-income entry of that tier's `SLIME_INCOME_BY_TIER`.

Cost of the next level = `UPGRADE_PAYBACK_SECONDS x UPGRADE_GROWTH_RATE x current income/s` = 90x
current income. Income = `base x 1.15^(level-1)`.

**The two "seconds of base" columns are identical for every tier** -- that is the point of the
rebuild. Every slime in the game pays the same relative price for the same level, and full max
costs **16575 seconds of base income** (4.6h of unlevelled production) for all of them.

| level | multiplier | cost (s of base) | cumulative (s of base) |
|---|---|---|---|
| 1 | 1.0000x | 90.0 | 0.0 |
| 2 | 1.1500x | 103.5 | 90.0 |
| 3 | 1.3225x | 119.0 | 193.5 |
| 4 | 1.5209x | 136.9 | 312.5 |
| 5 | 1.7490x | 157.4 | 449.4 |
| 6 | 2.0114x | 181.0 | 606.8 |
| 7 | 2.3131x | 208.2 | 787.8 |
| 8 | 2.6600x | 239.4 | 996.0 |
| 9 | 3.0590x | 275.3 | 1235.4 |
| 10 | 3.5179x | 316.6 | 1510.7 |
| 11 | 4.0456x | 364.1 | 1827.3 |
| 12 | 4.6524x | 418.7 | 2191.4 |
| 13 | 5.3503x | 481.5 | 2610.2 |
| 14 | 6.1528x | 553.8 | 3091.7 |
| 15 | 7.0757x | 636.8 | 3645.4 |
| 16 | 8.1371x | 732.3 | 4282.2 |
| 17 | 9.3576x | 842.2 | 5014.6 |
| 18 | 10.7613x | 968.5 | 5856.8 |
| 19 | 12.3755x | 1113.8 | 6825.3 |
| 20 | 14.2318x | 1280.9 | 7939.1 |
| 21 | 16.3665x | 1473.0 | 9219.9 |
| 22 | 18.8215x | 1693.9 | 10692.9 |
| 23 | 21.6447x | 1948.0 | 12386.8 |
| 24 | 24.8915x | 2240.2 | 14334.9 |
| 25 | 28.6252x | -- (max) | 16575.1 |

In dollars, per tier:

### T1 Common -- base $7.00/s, maxed $200/s

| level | income/s | cost of +1 | cumulative from L1 |
|---|---|---|---|
| 1 | $7.00 | $630 | $0 |
| 2 | $8.05 | $724 | $630 |
| 3 | $9.26 | $833 | $1.35K |
| 4 | $11 | $958 | $2.19K |
| 5 | $12 | $1.10K | $3.15K |
| 6 | $14 | $1.27K | $4.25K |
| 7 | $16 | $1.46K | $5.51K |
| 8 | $19 | $1.68K | $6.97K |
| 9 | $21 | $1.93K | $8.65K |
| 10 | $25 | $2.22K | $10.6K |
| 11 | $28 | $2.55K | $12.8K |
| 12 | $33 | $2.93K | $15.3K |
| 13 | $37 | $3.37K | $18.3K |
| 14 | $43 | $3.88K | $21.6K |
| 15 | $50 | $4.46K | $25.5K |
| 16 | $57 | $5.13K | $30.0K |
| 17 | $66 | $5.90K | $35.1K |
| 18 | $75 | $6.78K | $41.0K |
| 19 | $87 | $7.80K | $47.8K |
| 20 | $100 | $8.97K | $55.6K |
| 21 | $115 | $10.3K | $64.5K |
| 22 | $132 | $11.9K | $74.9K |
| 23 | $152 | $13.6K | $86.7K |
| 24 | $174 | $15.7K | $100K |
| 25 | $200 | -- (max) | $116K |

Total to max: **$116K** = 16575 seconds of base income.

### T2 Uncommon -- base $19/s, maxed $544/s

| level | income/s | cost of +1 | cumulative from L1 |
|---|---|---|---|
| 1 | $19 | $1.71K | $0 |
| 2 | $22 | $1.97K | $1.71K |
| 3 | $25 | $2.26K | $3.68K |
| 4 | $29 | $2.60K | $5.94K |
| 5 | $33 | $2.99K | $8.54K |
| 6 | $38 | $3.44K | $11.5K |
| 7 | $44 | $3.96K | $15.0K |
| 8 | $51 | $4.55K | $18.9K |
| 9 | $58 | $5.23K | $23.5K |
| 10 | $67 | $6.02K | $28.7K |
| 11 | $77 | $6.92K | $34.7K |
| 12 | $88 | $7.96K | $41.6K |
| 13 | $102 | $9.15K | $49.6K |
| 14 | $117 | $10.5K | $58.7K |
| 15 | $134 | $12.1K | $69.3K |
| 16 | $155 | $13.9K | $81.4K |
| 17 | $178 | $16.0K | $95.3K |
| 18 | $204 | $18.4K | $111K |
| 19 | $235 | $21.2K | $130K |
| 20 | $270 | $24.3K | $151K |
| 21 | $311 | $28.0K | $175K |
| 22 | $358 | $32.2K | $203K |
| 23 | $411 | $37.0K | $235K |
| 24 | $473 | $42.6K | $272K |
| 25 | $544 | -- (max) | $315K |

Total to max: **$315K** = 16575 seconds of base income.

### T3 Rare -- base $45/s, maxed $1.29K/s

| level | income/s | cost of +1 | cumulative from L1 |
|---|---|---|---|
| 1 | $45 | $4.05K | $0 |
| 2 | $52 | $4.66K | $4.05K |
| 3 | $60 | $5.36K | $8.71K |
| 4 | $68 | $6.16K | $14.1K |
| 5 | $79 | $7.08K | $20.2K |
| 6 | $91 | $8.15K | $27.3K |
| 7 | $104 | $9.37K | $35.5K |
| 8 | $120 | $10.8K | $44.8K |
| 9 | $138 | $12.4K | $55.6K |
| 10 | $158 | $14.2K | $68.0K |
| 11 | $182 | $16.4K | $82.2K |
| 12 | $209 | $18.8K | $98.6K |
| 13 | $241 | $21.7K | $117K |
| 14 | $277 | $24.9K | $139K |
| 15 | $318 | $28.7K | $164K |
| 16 | $366 | $33.0K | $193K |
| 17 | $421 | $37.9K | $226K |
| 18 | $484 | $43.6K | $264K |
| 19 | $557 | $50.1K | $307K |
| 20 | $640 | $57.6K | $357K |
| 21 | $736 | $66.3K | $415K |
| 22 | $847 | $76.2K | $481K |
| 23 | $974 | $87.7K | $557K |
| 24 | $1.12K | $101K | $645K |
| 25 | $1.29K | -- (max) | $746K |

Total to max: **$746K** = 16575 seconds of base income.

### T4 Epic -- base $110/s, maxed $3.15K/s

| level | income/s | cost of +1 | cumulative from L1 |
|---|---|---|---|
| 1 | $110 | $9.90K | $0 |
| 2 | $126 | $11.4K | $9.90K |
| 3 | $145 | $13.1K | $21.3K |
| 4 | $167 | $15.1K | $34.4K |
| 5 | $192 | $17.3K | $49.4K |
| 6 | $221 | $19.9K | $66.7K |
| 7 | $254 | $22.9K | $86.7K |
| 8 | $293 | $26.3K | $110K |
| 9 | $336 | $30.3K | $136K |
| 10 | $387 | $34.8K | $166K |
| 11 | $445 | $40.1K | $201K |
| 12 | $512 | $46.1K | $241K |
| 13 | $589 | $53.0K | $287K |
| 14 | $677 | $60.9K | $340K |
| 15 | $778 | $70.0K | $401K |
| 16 | $895 | $80.6K | $471K |
| 17 | $1.03K | $92.6K | $552K |
| 18 | $1.18K | $107K | $644K |
| 19 | $1.36K | $123K | $751K |
| 20 | $1.57K | $141K | $873K |
| 21 | $1.80K | $162K | $1.01M |
| 22 | $2.07K | $186K | $1.18M |
| 23 | $2.38K | $214K | $1.36M |
| 24 | $2.74K | $246K | $1.58M |
| 25 | $3.15K | -- (max) | $1.82M |

Total to max: **$1.82M** = 16575 seconds of base income.

### T5 Legendary -- base $350/s, maxed $10.0K/s

| level | income/s | cost of +1 | cumulative from L1 |
|---|---|---|---|
| 1 | $350 | $31.5K | $0 |
| 2 | $402 | $36.2K | $31.5K |
| 3 | $463 | $41.7K | $67.7K |
| 4 | $532 | $47.9K | $109K |
| 5 | $612 | $55.1K | $157K |
| 6 | $704 | $63.4K | $212K |
| 7 | $810 | $72.9K | $276K |
| 8 | $931 | $83.8K | $349K |
| 9 | $1.07K | $96.4K | $432K |
| 10 | $1.23K | $111K | $529K |
| 11 | $1.42K | $127K | $640K |
| 12 | $1.63K | $147K | $767K |
| 13 | $1.87K | $169K | $914K |
| 14 | $2.15K | $194K | $1.08M |
| 15 | $2.48K | $223K | $1.28M |
| 16 | $2.85K | $256K | $1.50M |
| 17 | $3.28K | $295K | $1.76M |
| 18 | $3.77K | $339K | $2.05M |
| 19 | $4.33K | $390K | $2.39M |
| 20 | $4.98K | $448K | $2.78M |
| 21 | $5.73K | $516K | $3.23M |
| 22 | $6.59K | $593K | $3.74M |
| 23 | $7.58K | $682K | $4.34M |
| 24 | $8.71K | $784K | $5.02M |
| 25 | $10.0K | -- (max) | $5.80M |

Total to max: **$5.80M** = 16575 seconds of base income.

### T6 Mythic -- base $1.10K/s, maxed $31.5K/s

| level | income/s | cost of +1 | cumulative from L1 |
|---|---|---|---|
| 1 | $1.10K | $99.0K | $0 |
| 2 | $1.26K | $114K | $99.0K |
| 3 | $1.45K | $131K | $213K |
| 4 | $1.67K | $151K | $344K |
| 5 | $1.92K | $173K | $494K |
| 6 | $2.21K | $199K | $667K |
| 7 | $2.54K | $229K | $867K |
| 8 | $2.93K | $263K | $1.10M |
| 9 | $3.36K | $303K | $1.36M |
| 10 | $3.87K | $348K | $1.66M |
| 11 | $4.45K | $401K | $2.01M |
| 12 | $5.12K | $461K | $2.41M |
| 13 | $5.89K | $530K | $2.87M |
| 14 | $6.77K | $609K | $3.40M |
| 15 | $7.78K | $700K | $4.01M |
| 16 | $8.95K | $806K | $4.71M |
| 17 | $10.3K | $926K | $5.52M |
| 18 | $11.8K | $1.07M | $6.44M |
| 19 | $13.6K | $1.23M | $7.51M |
| 20 | $15.7K | $1.41M | $8.73M |
| 21 | $18.0K | $1.62M | $10.1M |
| 22 | $20.7K | $1.86M | $11.8M |
| 23 | $23.8K | $2.14M | $13.6M |
| 24 | $27.4K | $2.46M | $15.8M |
| 25 | $31.5K | -- (max) | $18.2M |

Total to max: **$18.2M** = 16575 seconds of base income.

### T7 Secret -- base $9.00K/s, maxed $258K/s

| level | income/s | cost of +1 | cumulative from L1 |
|---|---|---|---|
| 1 | $9.00K | $810K | $0 |
| 2 | $10.3K | $931K | $810K |
| 3 | $11.9K | $1.07M | $1.74M |
| 4 | $13.7K | $1.23M | $2.81M |
| 5 | $15.7K | $1.42M | $4.04M |
| 6 | $18.1K | $1.63M | $5.46M |
| 7 | $20.8K | $1.87M | $7.09M |
| 8 | $23.9K | $2.15M | $8.96M |
| 9 | $27.5K | $2.48M | $11.1M |
| 10 | $31.7K | $2.85M | $13.6M |
| 11 | $36.4K | $3.28M | $16.4M |
| 12 | $41.9K | $3.77M | $19.7M |
| 13 | $48.2K | $4.33M | $23.5M |
| 14 | $55.4K | $4.98M | $27.8M |
| 15 | $63.7K | $5.73M | $32.8M |
| 16 | $73.2K | $6.59M | $38.5M |
| 17 | $84.2K | $7.58M | $45.1M |
| 18 | $96.9K | $8.72M | $52.7M |
| 19 | $111K | $10.0M | $61.4M |
| 20 | $128K | $11.5M | $71.5M |
| 21 | $147K | $13.3M | $83.0M |
| 22 | $169K | $15.2M | $96.2M |
| 23 | $195K | $17.5M | $111M |
| 24 | $224K | $20.2M | $129M |
| 25 | $258K | -- (max) | $149M |

Total to max: **$149M** = 16575 seconds of base income.

### T8 Divine -- base $100K/s, maxed $2.86M/s

| level | income/s | cost of +1 | cumulative from L1 |
|---|---|---|---|
| 1 | $100K | $9.00M | $0 |
| 2 | $115K | $10.3M | $9.00M |
| 3 | $132K | $11.9M | $19.3M |
| 4 | $152K | $13.7M | $31.3M |
| 5 | $175K | $15.7M | $44.9M |
| 6 | $201K | $18.1M | $60.7M |
| 7 | $231K | $20.8M | $78.8M |
| 8 | $266K | $23.9M | $99.6M |
| 9 | $306K | $27.5M | $124M |
| 10 | $352K | $31.7M | $151M |
| 11 | $405K | $36.4M | $183M |
| 12 | $465K | $41.9M | $219M |
| 13 | $535K | $48.2M | $261M |
| 14 | $615K | $55.4M | $309M |
| 15 | $708K | $63.7M | $365M |
| 16 | $814K | $73.2M | $428M |
| 17 | $936K | $84.2M | $501M |
| 18 | $1.08M | $96.9M | $586M |
| 19 | $1.24M | $111M | $683M |
| 20 | $1.42M | $128M | $794M |
| 21 | $1.64M | $147M | $922M |
| 22 | $1.88M | $169M | $1.07B |
| 23 | $2.16M | $195M | $1.24B |
| 24 | $2.49M | $224M | $1.43B |
| 25 | $2.86M | -- (max) | $1.66B |

Total to max: **$1.66B** = 16575 seconds of base income.

## 3. Upgrade ROI

**Flat 600 seconds, everywhere.** Not approximately -- identically, by construction.

One level costs `PAYBACK x RATE x I` and buys an income gain of `RATE x I`, so
`cost / gain = PAYBACK` with both `I` and `RATE` cancelling. Payback therefore does not depend
on level, on tier, or on base income. There is no curve to plot and no table worth repeating
25 times; what follows is the verification instead.

| check | scope | worst deviation from 600s |
|---|---|---|
| single `+1` | all 65 slimes x all 24 levels | **1.478e-12** |
| multi-level | every (slime, level, count) | **1.478e-12** |

Both are floating-point noise (~1 part in 10^15). The multi-level result is the one worth
noting: buying MAX is priced identically to buying the same levels one at a time -- no bulk
discount, no bulk penalty.

Spot values, to make the shape concrete:

| | Common ($7 base) | Divine ($100K base) |
|---|---|---|
| payback at level 1 | 600.000000000s | 600.000000000s |
| payback at level 5 | 600.000000000s | 600.000000000s |
| payback at level 12 | 600.000000000s | 600.000000000s |
| payback at level 20 | 600.000000000s | 600.000000000s |
| payback at level 24 | 600.000000000s | 600.000000000s |

For contrast, the curve this replaced: a Common's single level paid back in 1.5h at level 1
and 26h at level 900, rising the whole way, while a Divine's paid back 871x faster at every
level. Both of those spreads are now exactly zero.

## 4. The swing ladder

`reach` = best-case landing distance = `DISTANCE_PER_MULTIPLIER x SWEET_SPOT_MULTIPLIER x tier
scale`, i.e. a **perfect** sweet-spot launch; a typical landing falls short. Band =
`floor(reach / 40)`, luck = `LuckCurve.VALUES[band+1]`, exactly as `bandLuckForLandingZ`
computes it. `post-box` applies the mystery box's geometric-mean multiplier of
2.333x (the arithmetic mean does not exist -- see section 7).

| tier | price | x prev | reach | band | band luck | post-box luck | E[income]/slot | delta |
|---|---|---|---|---|---|---|---|---|
| 1 | - | - | 200 | 5 | 30 | 69 | $26/s | - |
| 2 | $50.0K | - | 600 | 15 | 80 | 186 | $26/s | +1.00% |
| 3 | $250K | 5x | 880 | 22 | 250 | 583 | $66/s | +155.62% |
| 4 | $1.00M | 4x | 1280 | 32 | 750 | 1,749 | $67/s | +1.44% |
| 5 | $10.0M | 10x | 1640 | 40 | 2,500 | 5,832 | $191/s | +184.09% |
| 6 | $100M | 10x | 1840 | 45 | 5,000 | 11,665 | $867/s | +352.92% |
| 7 | $1.00B | 10x | 2160 | 54 | 9,500 | 22,164 | $884/s | +1.95% |
| 8 | $500B | 500x | 2320 | 58 | 25,000 | 58,326 | $8.77K/s | +892.27% |
| 9 | $500T | 1000x | 2520 | 63 | 50,000 | 116,652 | $9.05K/s | +3.17% |
| 10 | $5.00Qi | 10000x | 2760 | 69 | 80,000 | 186,644 | $9.06K/s | +0.13% |
| 11 | $250Qi | 50x | 2960 | 73 | 100,000 | 233,305 | $9.06K/s | +0.00% |

Every delta is positive except tier 10 -> 11, which is exactly zero: both post-box lucks sit
past `SLIME_EXTRAPOLATION_T_MAX`, so they produce an identical distribution. See section 7.

## 5. Time to afford each swing tier

### Assumptions, stated explicitly

1. A player at swing tier N has **all 10 slots filled**, with slimes rolled at that tier's own
   post-box luck. Income per slot = the probability-weighted mean base income of the tier
   distribution at that luck, times the level multiplier for the scenario.
2. Every launch lands a **perfect sweet spot**. Real landings fall short, so real luck -- and
   so real income -- is lower. These times are a **lower bound**.
3. The box resolves at its geometric-mean multiplier every time.
4. Income is banked continuously and spent on nothing else. In particular scenario B assumes
   the slimes are **already** maxed and does not charge for maxing them; section 6 prices that.

**Scenario A** -- all 10 slimes at level 1 (multiplier 1.0x).  
**Scenario B** -- all 10 slimes maxed at level 25 (multiplier 28.6252x).

| from | to | price | A: income/s | A: time | B: income/s | B: time | speed-up |
|---|---|---|---|---|---|---|---|
| 1 | 2 | $50.0K | $257/s | 3.2m | $7.37K/s | 7s | 28.6x |
| 2 | 3 | $250K | $260/s | 16.0m | $7.44K/s | 34s | 28.6x |
| 3 | 4 | $1.00M | $664/s | 25.1m | $19.0K/s | 53s | 28.6x |
| 4 | 5 | $10.0M | $674/s | 4.1h | $19.3K/s | 8.6m | 28.6x |
| 5 | 6 | $100M | $1.91K/s | 14.5h | $54.8K/s | 30.4m | 28.6x |
| 6 | 7 | $1.00B | $8.67K/s | 32.0h | $248K/s | 67.1m | 28.6x |
| 7 | 8 | $500B | $8.84K/s | 654.6d | $253K/s | 22.9d | 28.6x |
| 8 | 9 | $500T | $87.7K/s | 180.6y | $2.51M/s | 6.3y | 28.6x |
| 9 | 10 | $5.00Qi | $90.5K/s | 1750619.8y | $2.59M/s | 61156.6y | 28.6x |
| 10 | 11 | $250Qi | $90.6K/s | 87418952.1y | $2.59M/s | 3053918.4y | 28.6x |

The speed-up is a constant 28.63x at every tier, because maxing scales all ten slots by
the same factor and the swing price does not move. That is the whole gap: **maxing your base
cuts every swing-tier wait by a factor of 28.6**, and nothing else about the ladder changes.

## 6. Where the time goes -- next swing tier vs. maxing one good slime

`best slime` = the highest-income slime of the **modal tier** at that swing tier's post-box
luck -- the best a player at that stage can routinely expect to own. Maxing it means buying
all 24 levels from 1, which costs 16,575 seconds of that slime's base income.

Both columns use the **scenario A** income (all slimes level 1), since that is the state a
player is in when the decision is actually in front of them.

| at tier | income/s | next tier | t(next tier) | best slime | max it | t(max) | **ratio** |
|---|---|---|---|---|---|---|---|
| 1 | $257/s | $50.0K | 3.2m | Uncommon $25/s | $414K | 26.8m | **8.29x** |
| 2 | $260/s | $250K | 16.0m | Uncommon $25/s | $414K | 26.6m | **1.66x** |
| 3 | $664/s | $1.00M | 25.1m | Rare $60/s | $995K | 24.9m | **0.99x** |
| 4 | $674/s | $10.0M | 4.1h | Rare $60/s | $995K | 24.6m | **0.10x** |
| 5 | $1.91K/s | $100M | 14.5h | Epic $150/s | $2.49M | 21.6m | **0.02x** |
| 6 | $8.67K/s | $1.00B | 32.0h | Legendary $500/s | $8.29M | 15.9m | **0.01x** |
| 7 | $8.84K/s | $500B | 654.6d | Legendary $500/s | $8.29M | 15.6m | **0.00x** |
| 8 | $87.7K/s | $500T | 180.6y | Mythic $1.50K/s | $24.9M | 4.7m | **0.00x** |
| 9 | $90.5K/s | $5.00Qi | 1750619.8y | Mythic $1.50K/s | $24.9M | 4.6m | **0.00x** |
| 10 | $90.6K/s | $250Qi | 87418952.1y | Mythic $1.50K/s | $24.9M | 4.6m | **0.00x** |

A ratio below 1 means maxing a slime is the cheaper next purchase; above 1 means the swing
tier is. For contrast, the same comparison on the old curve ran from **1556x** at tier 1 down
to 4.7x at tier 5 -- upgrading was never remotely competitive until very late.

The same table under scenario B income (base already maxed), for the tier-by-tier shape once
a player is established:

| at tier | income/s | t(next tier) | t(max one more good slime) | ratio |
|---|---|---|---|---|
| 1 | $7.37K/s | 7s | 56s | 8.29x |
| 2 | $7.44K/s | 34s | 56s | 1.66x |
| 3 | $19.0K/s | 53s | 52s | 0.99x |
| 4 | $19.3K/s | 8.6m | 52s | 0.10x |
| 5 | $54.8K/s | 30.4m | 45s | 0.02x |
| 6 | $248K/s | 67.1m | 33s | 0.01x |
| 7 | $253K/s | 22.9d | 33s | 0.00x |
| 8 | $2.51M/s | 6.3y | 10s | 0.00x |
| 9 | $2.59M/s | 61156.6y | 10s | 0.00x |
| 10 | $2.59M/s | 3053918.4y | 10s | 0.00x |

## 7. Observations and anomalies

### 7.1 Fixed since the last dump: expected income is now monotonic in luck

The previous dump's headline finding -- five of ten swing tiers rolling *worse* slimes than
the tier below -- is gone. Across the 74 band values there are now **0** decreasing steps, and
across 2,000,000 log-spaced luck values (verified in the roll-distribution pass) also 0.
Every swing tier delta in section 4 is positive except the 10 -> 11 clamp case below.

### 7.2 The luck curve still saturates before the price ladder does

`SLIME_EXTRAPOLATION_T_MAX` = 1.0 clamps t at the high anchor, so every post-box luck at or
above 120,000 produces an identical distribution. Unchanged by either fix.

Tier 10 and tier 11 distributions identical to 1e-12: **true**. Tier 11 costs $250Qi and
buys no change at all in what it rolls. The window is already at its maximum (Legendary-Divine)
at t = 0.875, before the clamp -- with 8 tiers and a 4-wide window there is nowhere further to
go, so raising `T_MAX` cannot help. That needs more tiers, or a narrower window at the top.

### 7.3 The swing price ladder still has two discontinuities

| step | ratio |
|---|---|
| 2 -> 3 | 5x |
| 3 -> 4 | 4x |
| 4 -> 5 | 10x |
| 5 -> 6 | 10x |
| 6 -> 7 | 10x |
| 7 -> 8 | 500x  <-- jumps an order of magnitude |
| 8 -> 9 | 1000x |
| 9 -> 10 | 10000x  <-- jumps an order of magnitude |
| 10 -> 11 | 50x  <-- drops an order of magnitude |

Tiers 3-7 run a clean 4-10x ladder; tier 8 jumps 500x, tier 9 1000x, tier 10 10000x, then tier
11 drops back to 50x. Untouched by either fix, and now the single largest remaining problem in
the economy -- see 7.5.

### 7.4 Levelling may now be TOO good -- it dominates from tier 3 onward

The old curve made upgrading never worth it (ratio 1556x at tier 1). The new one may have
overshot in the other direction. From section 6, the crossover where maxing a slime becomes
cheaper than the next swing tier lands at **tier 3**, and past that it is not close:

| at tier | t(next swing tier) | t(max best slime) | maxing is |
|---|---|---|---|
| 1 | 3.2m | 26.8m | 8.3x more expensive |
| 3 | 25.1m | 24.9m | 1x cheaper |
| 5 | 14.5h | 21.6m | 40x cheaper |
| 7 | 654.6d | 15.6m | 60331x cheaper |

The strategic consequence is stronger than those numbers alone suggest, because maxing is not
just cheaper -- it is also **multiplicative on the thing you would have spent the money on**.
Maxing all ten slots costs roughly ten times one slime and returns 28.63x income, which then
makes the swing tier 28.63x faster to afford. So the dominant strategy at every tier from 3
onward is: max the entire base first, buy the swing tier second, always. The swing shop stops
being a decision.

Whether that is wrong depends on what the swing tiers are for. If they are meant to be the
spine of progression, `UPGRADE_PAYBACK_SECONDS` is too low and wants raising -- it is the only
lever on how expensive levelling feels, and nothing else in the curve needs to move. If they
are meant to be a gate you pass once the base is built, this is working as intended. I cannot
tell which from the config, so I am flagging it rather than proposing a number.

One thing the rebuild did get unambiguously right: because payback is flat and every tier maxes
to the same 28.63x, "should I level or should I roll" now has the same answer for a Common as
for a Divine. The decision no longer depends on which tier you happen to hold.

### 7.5 The late-game ladder is still unreachable, and the rebuild did not touch it

Even with a fully maxed base (scenario B), the top of the price ladder is not a progression:

| step | price | time at scenario B income |
|---|---|---|
| 7 -> 8 | $500B | 22.9d |
| 8 -> 9 | $500T | 6.3y |
| 9 -> 10 | $5.00Qi | 61156.6y |
| 10 -> 11 | $250Qi | 3053918.4y |

Maxing the whole base buys a 28.63x speed-up, which moves a 5-million-year wait to a
180,000-year one. The upgrade rebuild was never going to fix this and did not: **the swing
prices above tier 7 are the problem**, not the income curve. This is the thing I would look at
next.

### 7.6 The mystery box still has no expected value

`BOX_DOUBLE_CHANCE` = 0.55, so 2p = 1.10 > 1 and E[2^D] is a divergent series -- the box's
mean luck multiplier does not exist as a finite number. Every figure in this document uses the
geometric mean (2.333x) instead, which is finite and is the right average for a multiplicative
process. Unchanged by either fix.

| statistic | value |
|---|---|
| E[D], expected doublings | 1.2222 |
| median D | 1 |
| geometric-mean multiplier | 2.333x |
| E[2^D] | **divergent** -- 2p = 1.10 > 1 |
| P(D >= 10), a 1024x box | 0.25% |
| P(D >= 20), a ~1,000,000x box | 0.0006% (1 in 155864) |

### 7.7 Not an economy finding: `.gitignore` does not actually ignore these files

`ECONOMY_DUMP.md` and `REPORT.md` were appended to `.gitignore` in **UTF-16**, so git reads the
entries as null-separated bytes and matches nothing -- `git check-ignore` confirms neither file
is matched by any rule. Both are also already **tracked** (committed in `7968604`), and
`.gitignore` never applies to tracked files regardless of encoding. To actually untrack them:
`git rm --cached ECONOMY_DUMP.md REPORT.md` and rewrite `.gitignore` as UTF-8. Not done here --
this pass is analysis only.

