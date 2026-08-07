# Economy dump

Every number below is **computed from the live config modules**, loaded through `dev/rbxshim.luau`
under Lune -- not from memory, and not from a running game (no playtest was run). Sources:
`LuckCurve`, `SlimeConfig`, `SlimeData`, `SlimeRoll`, `SlimeUpgrade`, `SlimeUpgradeConfig`,
`ShopConfig`, `LaunchConfig`.

Constants in play: `MAX_LEVEL` = 1000, `BOX_DOUBLE_CHANCE` = 0.55, `DISTANCE_PER_MULTIPLIER` = 100,
`RUNWAY_BAND_LENGTH_STUDS` = 40, `SWEET_SPOT_MULTIPLIER` = 2.0, 74 bands, 65 slimes across 8 tiers, 11 swing tiers.

## 1. The full luck distribution

The roll is a **sliding window**, not fixed weights: `SlimeRoll.distributionForLuck` moves a
4-tier window up the ladder on log-luck and reshapes a generalised Gaussian inside it.
Tiers outside the window are **exactly zero** by construction. The probabilities below are the
actual computed weights per band, not the formula.

`typ` = the peak (modal) tier. `+2` = the tier two steps above it, the one the config says should
sit at a reachable 1-5%. **FLAG** marks bands where it falls outside that.

| band | luck | window | typ | Common | Uncommon | Rare | Epic | Legendary | Mythic | Secret | Divine | +2 tier | +2 P | |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 5 | Common-Epic | Uncommon | 8.18% | 66.55% | 20.93% | 4.35% | - | - | - | - | Epic | 4.35% |  |
| 1 | 10 | Common-Epic | Uncommon | 8.21% | 66.63% | 20.84% | 4.32% | - | - | - | - | Epic | 4.32% |  |
| 2 | 15 | Common-Epic | Uncommon | 8.45% | 67.21% | 20.21% | 4.13% | - | - | - | - | Epic | 4.13% |  |
| 3 | 20 | Common-Epic | Uncommon | 8.62% | 67.62% | 19.76% | 4.00% | - | - | - | - | Epic | 4.00% |  |
| 4 | 25 | Common-Epic | Uncommon | 8.75% | 67.93% | 19.41% | 3.90% | - | - | - | - | Epic | 3.90% |  |
| 5 | 30 | Common-Epic | Uncommon | 8.86% | 68.19% | 19.12% | 3.83% | - | - | - | - | Epic | 3.83% |  |
| 6 | 35 | Common-Epic | Uncommon | 8.95% | 68.41% | 18.88% | 3.76% | - | - | - | - | Epic | 3.76% |  |
| 7 | 40 | Common-Epic | Uncommon | 9.04% | 68.59% | 18.67% | 3.70% | - | - | - | - | Epic | 3.70% |  |
| 8 | 45 | Common-Epic | Uncommon | 9.11% | 68.76% | 18.48% | 3.65% | - | - | - | - | Epic | 3.65% |  |
| 9 | 50 | Common-Epic | Uncommon | 9.17% | 68.90% | 18.31% | 3.61% | - | - | - | - | Epic | 3.61% |  |
| 10 | 55 | Common-Epic | Uncommon | 9.23% | 69.04% | 18.16% | 3.57% | - | - | - | - | Epic | 3.57% |  |
| 11 | 60 | Common-Epic | Uncommon | 9.29% | 69.16% | 18.02% | 3.53% | - | - | - | - | Epic | 3.53% |  |
| 12 | 65 | Common-Epic | Uncommon | 9.34% | 69.27% | 17.89% | 3.50% | - | - | - | - | Epic | 3.50% |  |
| 13 | 70 | Common-Epic | Uncommon | 9.39% | 69.37% | 17.78% | 3.47% | - | - | - | - | Epic | 3.47% |  |
| 14 | 75 | Common-Epic | Uncommon | 9.43% | 69.46% | 17.66% | 3.44% | - | - | - | - | Epic | 3.44% |  |
| 15 | 80 | Common-Epic | Uncommon | 9.47% | 69.55% | 17.56% | 3.42% | - | - | - | - | Epic | 3.42% |  |
| 16 | 85 | Common-Epic | Uncommon | 9.51% | 69.63% | 17.46% | 3.39% | - | - | - | - | Epic | 3.39% |  |
| 17 | 90 | Common-Epic | Uncommon | 9.55% | 69.71% | 17.37% | 3.37% | - | - | - | - | Epic | 3.37% |  |
| 18 | 95 | Common-Epic | Uncommon | 9.58% | 69.79% | 17.29% | 3.35% | - | - | - | - | Epic | 3.35% |  |
| 19 | 100 | Common-Epic | Uncommon | 9.61% | 69.86% | 17.20% | 3.33% | - | - | - | - | Epic | 3.33% |  |
| 20 | 150 | Common-Epic | Uncommon | 9.88% | 70.40% | 16.55% | 3.17% | - | - | - | - | Epic | 3.17% |  |
| 21 | 200 | Common-Epic | Uncommon | 10.07% | 70.78% | 16.09% | 3.06% | - | - | - | - | Epic | 3.06% |  |
| 22 | 250 | Common-Epic | Uncommon | 10.22% | 71.08% | 15.73% | 2.97% | - | - | - | - | Epic | 2.97% |  |
| 23 | 300 | Common-Epic | Uncommon | 10.35% | 71.32% | 15.43% | 2.90% | - | - | - | - | Epic | 2.90% |  |
| 24 | 350 | Common-Epic | Uncommon | 10.45% | 71.52% | 15.19% | 2.85% | - | - | - | - | Epic | 2.85% |  |
| 25 | 400 | Common-Epic | Uncommon | 10.54% | 71.69% | 14.97% | 2.80% | - | - | - | - | Epic | 2.80% |  |
| 26 | 450 | Common-Epic | Uncommon | 10.62% | 71.84% | 14.78% | 2.76% | - | - | - | - | Epic | 2.76% |  |
| 27 | 500 | Uncommon-Legendary | Rare | - | 10.70% | 71.97% | 14.61% | 2.72% | - | - | - | Legendary | 2.72% |  |
| 28 | 550 | Uncommon-Legendary | Rare | - | 10.76% | 72.09% | 14.46% | 2.68% | - | - | - | Legendary | 2.68% |  |
| 29 | 600 | Uncommon-Legendary | Rare | - | 10.83% | 72.20% | 14.32% | 2.65% | - | - | - | Legendary | 2.65% |  |
| 30 | 650 | Uncommon-Legendary | Rare | - | 10.88% | 72.31% | 14.19% | 2.63% | - | - | - | Legendary | 2.63% |  |
| 31 | 700 | Uncommon-Legendary | Rare | - | 10.93% | 72.40% | 14.07% | 2.60% | - | - | - | Legendary | 2.60% |  |
| 32 | 750 | Uncommon-Legendary | Rare | - | 10.98% | 72.48% | 13.96% | 2.58% | - | - | - | Legendary | 2.58% |  |
| 33 | 800 | Uncommon-Legendary | Rare | - | 11.03% | 72.56% | 13.85% | 2.55% | - | - | - | Legendary | 2.55% |  |
| 34 | 850 | Uncommon-Legendary | Rare | - | 11.07% | 72.64% | 13.76% | 2.53% | - | - | - | Legendary | 2.53% |  |
| 35 | 900 | Uncommon-Legendary | Rare | - | 11.11% | 72.71% | 13.66% | 2.51% | - | - | - | Legendary | 2.51% |  |
| 36 | 950 | Uncommon-Legendary | Rare | - | 11.15% | 72.78% | 13.58% | 2.49% | - | - | - | Legendary | 2.49% |  |
| 37 | 1,000 | Uncommon-Legendary | Rare | - | 11.19% | 72.84% | 13.49% | 2.48% | - | - | - | Legendary | 2.48% |  |
| 38 | 1,500 | Uncommon-Legendary | Rare | - | 11.48% | 73.33% | 12.84% | 2.34% | - | - | - | Legendary | 2.34% |  |
| 39 | 2,000 | Uncommon-Legendary | Rare | - | 11.70% | 73.68% | 12.38% | 2.24% | - | - | - | Legendary | 2.24% |  |
| 40 | 2,500 | Rare-Mythic | Epic | - | - | 11.86% | 73.94% | 12.03% | 2.17% | - | - | Mythic | 2.17% |  |
| 41 | 3,000 | Rare-Mythic | Epic | - | - | 12.00% | 74.15% | 11.74% | 2.11% | - | - | Mythic | 2.11% |  |
| 42 | 3,500 | Rare-Mythic | Epic | - | - | 12.12% | 74.33% | 11.49% | 2.06% | - | - | Mythic | 2.06% |  |
| 43 | 4,000 | Rare-Mythic | Epic | - | - | 12.22% | 74.48% | 11.28% | 2.02% | - | - | Mythic | 2.02% |  |
| 44 | 4,500 | Rare-Mythic | Epic | - | - | 12.31% | 74.61% | 11.10% | 1.98% | - | - | Mythic | 1.98% |  |
| 45 | 5,000 | Rare-Mythic | Epic | - | - | 12.39% | 74.73% | 10.93% | 1.95% | - | - | Mythic | 1.95% |  |
| 46 | 5,500 | Rare-Mythic | Epic | - | - | 12.46% | 74.84% | 10.78% | 1.92% | - | - | Mythic | 1.92% |  |
| 47 | 6,000 | Rare-Mythic | Epic | - | - | 12.53% | 74.93% | 10.64% | 1.89% | - | - | Mythic | 1.89% |  |
| 48 | 6,500 | Rare-Mythic | Epic | - | - | 12.59% | 75.02% | 10.52% | 1.87% | - | - | Mythic | 1.87% |  |
| 49 | 7,000 | Rare-Mythic | Epic | - | - | 12.65% | 75.10% | 10.40% | 1.85% | - | - | Mythic | 1.85% |  |
| 50 | 7,500 | Rare-Mythic | Epic | - | - | 12.71% | 75.18% | 10.29% | 1.82% | - | - | Mythic | 1.82% |  |
| 51 | 8,000 | Rare-Mythic | Epic | - | - | 12.76% | 75.25% | 10.19% | 1.80% | - | - | Mythic | 1.80% |  |
| 52 | 8,500 | Rare-Mythic | Epic | - | - | 12.80% | 75.31% | 10.10% | 1.79% | - | - | Mythic | 1.79% |  |
| 53 | 9,000 | Rare-Mythic | Epic | - | - | 12.85% | 75.38% | 10.01% | 1.77% | - | - | Mythic | 1.77% |  |
| 54 | 9,500 | Rare-Mythic | Epic | - | - | 12.89% | 75.43% | 9.92% | 1.75% | - | - | Mythic | 1.75% |  |
| 55 | 10,000 | Rare-Mythic | Epic | - | - | 12.93% | 75.49% | 9.84% | 1.74% | - | - | Mythic | 1.74% |  |
| 56 | 15,000 | Epic-Secret | Legendary | - | - | - | 13.26% | 75.92% | 9.21% | 1.61% | - | Secret | 1.61% |  |
| 57 | 20,000 | Epic-Secret | Legendary | - | - | - | 13.49% | 76.22% | 8.76% | 1.53% | - | Secret | 1.53% |  |
| 58 | 25,000 | Epic-Secret | Legendary | - | - | - | 13.67% | 76.44% | 8.42% | 1.46% | - | Secret | 1.46% |  |
| 59 | 30,000 | Epic-Secret | Legendary | - | - | - | 13.82% | 76.63% | 8.14% | 1.41% | - | Secret | 1.41% |  |
| 60 | 35,000 | Epic-Secret | Legendary | - | - | - | 13.95% | 76.78% | 7.90% | 1.36% | - | Secret | 1.36% |  |
| 61 | 40,000 | Epic-Secret | Legendary | - | - | - | 14.06% | 76.91% | 7.70% | 1.33% | - | Secret | 1.33% |  |
| 62 | 45,000 | Epic-Secret | Legendary | - | - | - | 14.16% | 77.03% | 7.52% | 1.29% | - | Secret | 1.29% |  |
| 63 | 50,000 | Epic-Secret | Legendary | - | - | - | 14.25% | 77.13% | 7.36% | 1.26% | - | Secret | 1.26% |  |
| 64 | 55,000 | Legendary-Divine | Mythic | - | - | - | - | 14.33% | 77.23% | 7.21% | 1.23% | Divine | 1.23% |  |
| 65 | 60,000 | Legendary-Divine | Mythic | - | - | - | - | 14.40% | 77.31% | 7.08% | 1.21% | Divine | 1.21% |  |
| 66 | 65,000 | Legendary-Divine | Mythic | - | - | - | - | 14.47% | 77.39% | 6.95% | 1.18% | Divine | 1.18% |  |
| 67 | 70,000 | Legendary-Divine | Mythic | - | - | - | - | 14.54% | 77.46% | 6.84% | 1.16% | Divine | 1.16% |  |
| 68 | 75,000 | Legendary-Divine | Mythic | - | - | - | - | 14.60% | 77.53% | 6.74% | 1.14% | Divine | 1.14% |  |
| 69 | 80,000 | Legendary-Divine | Mythic | - | - | - | - | 14.65% | 77.59% | 6.64% | 1.12% | Divine | 1.12% |  |
| 70 | 85,000 | Legendary-Divine | Mythic | - | - | - | - | 14.70% | 77.64% | 6.55% | 1.11% | Divine | 1.11% |  |
| 71 | 90,000 | Legendary-Divine | Mythic | - | - | - | - | 14.75% | 77.70% | 6.46% | 1.09% | Divine | 1.09% |  |
| 72 | 95,000 | Legendary-Divine | Mythic | - | - | - | - | 14.80% | 77.75% | 6.38% | 1.07% | Divine | 1.07% |  |
| 73 | 100,000 | Legendary-Divine | Mythic | - | - | - | - | 14.84% | 77.80% | 6.30% | 1.06% | Divine | 1.06% |  |

**0 of 74 bands flagged.**

The +2 tail holds across the whole road: its range over all 74 bands is **1.06% to 4.35%**,
comfortably inside the stated 1-5% rule at both ends, and it never leaves the window (the peak
is always one tier in from the window's bottom, so +2 is always the window's top tier).

### Window transitions

The window start is rounded to a whole tier, so it steps rather than slides. Where it steps:

| at band | luck | window becomes | peak becomes |
|---|---|---|---|
| 0 | 5 | Common-Epic | Uncommon |
| 27 | 500 | Uncommon-Legendary | Rare |
| 40 | 2,500 | Rare-Mythic | Epic |
| 56 | 15,000 | Epic-Secret | Legendary |
| 64 | 55,000 | Legendary-Divine | Mythic |

## 2. The upgrade cost curve

Representative slime per tier = the **median-income** entry of that tier's `SLIME_INCOME_BY_TIER` list.

Cost of `+1` at level L = base x (693 + 309 x (L-1)) seconds of the slime's own BASE income.
Income multiplier = 1 + scale x (39.0 x (L-1) + 0.486 x (L-1)^2), rescaled per tier to reach 1700 x 2.63^(tier-1) at max level.

### T1 Common -- base $7/s (max multiplier 1700x at level 1000)

| level | income/s | multiplier | cost of +1 | cumulative cost from L1 |
|---|---|---|---|---|
| 1 | $7 | 1.0x | $4.85K | $0 |
| 5 | $11 | 1.5x | $13.5K | $32.4K |
| 10 | $16 | 2.3x | $24.3K | $122K |
| 25 | $35 | 4.9x | $56.8K | $713K |
| 50 | $77 | 11.0x | $111K | $2.78M |
| 100 | $203 | 29.0x | $219K | $11.0M |
| 250 | $911 | 130.2x | $543K | $68.0M |
| 500 | $3.20K | 456.5x | $1.08M | $271M |
| 1000 | $11.9K | 1700.0x | n/a (at max) | $1.08B |

### T2 Uncommon -- base $19/s (max multiplier 4471x at level 1000)

| level | income/s | multiplier | cost of +1 | cumulative cost from L1 |
|---|---|---|---|---|
| 1 | $19 | 1.0x | $13.2K | $0 |
| 5 | $46 | 2.4x | $36.7K | $87.9K |
| 10 | $82 | 4.3x | $66.0K | $330K |
| 25 | $216 | 11.4x | $154K | $1.94M |
| 50 | $518 | 27.3x | $301K | $7.55M |
| 100 | $1.42K | 74.6x | $594K | $29.8M |
| 250 | $6.48K | 340.9x | $1.48M | $185M |
| 500 | $22.8K | 1199.4x | $2.94M | $736M |
| 1000 | $84.9K | 4471.0x | n/a (at max) | $2.94B |

### T3 Rare -- base $45/s (max multiplier 11759x at level 1000)

| level | income/s | multiplier | cost of +1 | cumulative cost from L1 |
|---|---|---|---|---|
| 1 | $45 | 1.0x | $31.2K | $0 |
| 5 | $210 | 4.7x | $86.8K | $208K |
| 10 | $439 | 9.8x | $156K | $781K |
| 25 | $1.27K | 28.3x | $365K | $4.59M |
| 50 | $3.15K | 70.1x | $713K | $17.9M |
| 100 | $8.75K | 194.5x | $1.41M | $70.5M |
| 250 | $40.3K | 895.0x | $3.49M | $437M |
| 500 | $142K | 3153.1x | $6.97M | $1.74B |
| 1000 | $529K | 11758.7x | n/a (at max) | $6.96B |

### T4 Epic -- base $110/s (max multiplier 30925x at level 1000)

| level | income/s | multiplier | cost of +1 | cumulative cost from L1 |
|---|---|---|---|---|
| 1 | $110 | 1.0x | $76.2K | $0 |
| 5 | $1.17K | 10.7x | $212K | $509K |
| 10 | $2.64K | 24.0x | $382K | $1.91M |
| 25 | $8.00K | 72.8x | $892K | $11.2M |
| 50 | $20.1K | 182.6x | $1.74M | $43.7M |
| 100 | $56.1K | 510.0x | $3.44M | $172M |
| 250 | $259K | 2352.5x | $8.54M | $1.07B |
| 500 | $912K | 8291.5x | $17.0M | $4.26B |
| 1000 | $3.40M | 30925.5x | n/a (at max) | $17.0B |

### T5 Legendary -- base $350/s (max multiplier 81334x at level 1000)

| level | income/s | multiplier | cost of +1 | cumulative cost from L1 |
|---|---|---|---|---|
| 1 | $350 | 1.0x | $243K | $0 |
| 5 | $9.25K | 26.4x | $675K | $1.62M |
| 10 | $21.6K | 61.6x | $1.22M | $6.08M |
| 25 | $66.4K | 189.7x | $2.84M | $35.7M |
| 50 | $168K | 478.7x | $5.54M | $139M |
| 100 | $469K | 1339.7x | $10.9M | $549M |
| 250 | $2.16M | 6185.5x | $27.2M | $3.40B |
| 500 | $7.63M | 21805.4x | $54.2M | $13.6B |
| 1000 | $28.5M | 81334.0x | n/a (at max) | $54.2B |

### T6 Mythic -- base $1.10K/s (max multiplier 213908x at level 1000)

| level | income/s | multiplier | cost of +1 | cumulative cost from L1 |
|---|---|---|---|---|
| 1 | $1.10K | 1.0x | $762K | $0 |
| 5 | $74.6K | 67.9x | $2.12M | $5.09M |
| 10 | $176K | 160.4x | $3.82M | $19.1M |
| 25 | $547K | 497.4x | $8.92M | $112M |
| 50 | $1.38M | 1257.5x | $17.4M | $437M |
| 100 | $3.87M | 3521.7x | $34.4M | $1.72B |
| 250 | $17.9M | 16266.2x | $85.4M | $10.7B |
| 500 | $63.1M | 57347.1x | $170M | $42.6B |
| 1000 | $235M | 213908.3x | n/a (at max) | $170B |

### T7 Secret -- base $9.00K/s (max multiplier 562579x at level 1000)

| level | income/s | multiplier | cost of +1 | cumulative cost from L1 |
|---|---|---|---|---|
| 1 | $9.00K | 1.0x | $6.24M | $0 |
| 5 | $1.59M | 176.8x | $17.4M | $41.6M |
| 10 | $3.78M | 420.1x | $31.3M | $156M |
| 25 | $11.8M | 1306.5x | $73.0M | $917M |
| 50 | $29.7M | 3305.6x | $143M | $3.58B |
| 100 | $83.3M | 9260.4x | $282M | $14.1B |
| 250 | $385M | 42778.7x | $699M | $87.4B |
| 500 | $1.36B | 150821.6x | $1.39B | $349B |
| 1000 | $5.06B | 562578.9x | n/a (at max) | $1.39T |

### T8 Divine -- base $100K/s (max multiplier 1479582x at level 1000)

| level | income/s | multiplier | cost of +1 | cumulative cost from L1 |
|---|---|---|---|---|
| 1 | $100K | 1.0x | $69.3M | $0 |
| 5 | $46.3M | 463.5x | $193M | $463M |
| 10 | $110M | 1103.3x | $347M | $1.74B |
| 25 | $343M | 3434.4x | $811M | $10.2B |
| 50 | $869M | 8692.0x | $1.58B | $39.7B |
| 100 | $2.44B | 24353.3x | $3.13B | $157B |
| 250 | $11.3B | 112506.5x | $7.76B | $971B |
| 500 | $39.7B | 396659.6x | $15.5B | $3.87T |
| 1000 | $148B | 1479582.4x | n/a (at max) | $15.5T |

## 3. Upgrade ROI

`marginal/s` = income(L+1) - income(L), the income one extra level actually buys.
`ROI` = marginal income per dollar spent on that level. `payback` = how long that single level takes
to pay for itself out of its own income gain.

### T1 Common -- base $7/s

| level | cost of +1 | marginal/s | ROI ($/s per $) | payback |
|---|---|---|---|---|
| 1 | $4.85K | $0.896 | 1.847e-04 | 1.5h |
| 5 | $13.5K | $0.984 | 7.291e-05 | 3.8h |
| 10 | $24.3K | $1 | 4.502e-05 | 6.2h |
| 25 | $56.8K | $1 | 2.512e-05 | 11.1h |
| 50 | $111K | $2 | 1.784e-05 | 15.6h |
| 100 | $219K | $3 | 1.407e-05 | 19.7h |
| 250 | $543K | $6 | 1.176e-05 | 23.6h |
| 500 | $1.08M | $12 | 1.098e-05 | 25.3h |
| 1000 | n/a (at max) | n/a | n/a | n/a |

### T2 Uncommon -- base $19/s

| level | cost of +1 | marginal/s | ROI ($/s per $) | payback |
|---|---|---|---|---|
| 1 | $13.2K | $6 | 4.861e-04 | 34.3m |
| 5 | $36.7K | $7 | 1.918e-04 | 86.9m |
| 10 | $66.0K | $8 | 1.184e-04 | 2.3h |
| 25 | $154K | $10 | 6.608e-05 | 4.2h |
| 50 | $301K | $14 | 4.693e-05 | 5.9h |
| 100 | $594K | $22 | 3.701e-05 | 7.5h |
| 250 | $1.48M | $46 | 3.093e-05 | 9.0h |
| 500 | $2.94M | $85 | 2.889e-05 | 9.6h |
| 1000 | n/a (at max) | n/a | n/a | n/a |

### T3 Rare -- base $45/s

| level | cost of +1 | marginal/s | ROI ($/s per $) | payback |
|---|---|---|---|---|
| 1 | $31.2K | $40 | 1.279e-03 | 13.0m |
| 5 | $86.8K | $44 | 5.045e-04 | 33.0m |
| 10 | $156K | $49 | 3.115e-04 | 53.5m |
| 25 | $365K | $63 | 1.738e-04 | 1.6h |
| 50 | $713K | $88 | 1.235e-04 | 2.3h |
| 100 | $1.41M | $137 | 9.734e-05 | 2.9h |
| 250 | $3.49M | $284 | 8.137e-05 | 3.4h |
| 500 | $6.97M | $530 | 7.599e-05 | 3.7h |
| 1000 | n/a (at max) | n/a | n/a | n/a |

### T4 Epic -- base $110/s

| level | cost of +1 | marginal/s | ROI ($/s per $) | payback |
|---|---|---|---|---|
| 1 | $76.2K | $256 | 3.363e-03 | 5.0m |
| 5 | $212K | $282 | 1.327e-03 | 12.6m |
| 10 | $382K | $313 | 8.194e-04 | 20.3m |
| 25 | $892K | $408 | 4.572e-04 | 36.5m |
| 50 | $1.74M | $566 | 3.247e-04 | 51.3m |
| 100 | $3.44M | $881 | 2.560e-04 | 65.1m |
| 250 | $8.54M | $1.83K | 2.140e-04 | 77.9m |
| 500 | $17.0M | $3.41K | 1.999e-04 | 83.4m |
| 1000 | n/a (at max) | n/a | n/a | n/a |

### T5 Legendary -- base $350/s

| level | cost of +1 | marginal/s | ROI ($/s per $) | payback |
|---|---|---|---|---|
| 1 | $243K | $2.15K | 8.844e-03 | 1.9m |
| 5 | $675K | $2.36K | 3.490e-03 | 4.8m |
| 10 | $1.22M | $2.62K | 2.155e-03 | 7.7m |
| 25 | $2.84M | $3.41K | 1.202e-03 | 13.9m |
| 50 | $5.54M | $4.73K | 8.540e-04 | 19.5m |
| 100 | $10.9M | $7.37K | 6.734e-04 | 24.8m |
| 250 | $27.2M | $15.3K | 5.628e-04 | 29.6m |
| 500 | $54.2M | $28.5K | 5.256e-04 | 31.7m |
| 1000 | n/a (at max) | n/a | n/a | n/a |

### T6 Mythic -- base $1.10K/s

| level | cost of +1 | marginal/s | ROI ($/s per $) | payback |
|---|---|---|---|---|
| 1 | $762K | $17.7K | 2.326e-02 | 43s |
| 5 | $2.12M | $19.5K | 9.179e-03 | 1.8m |
| 10 | $3.82M | $21.7K | 5.668e-03 | 2.9m |
| 25 | $8.92M | $28.2K | 3.162e-03 | 5.3m |
| 50 | $17.4M | $39.1K | 2.246e-03 | 7.4m |
| 100 | $34.4M | $60.9K | 1.771e-03 | 9.4m |
| 250 | $85.4M | $126K | 1.480e-03 | 11.3m |
| 500 | $170M | $236K | 1.382e-03 | 12.1m |
| 1000 | n/a (at max) | n/a | n/a | n/a |

### T7 Secret -- base $9.00K/s

| level | cost of +1 | marginal/s | ROI ($/s per $) | payback |
|---|---|---|---|---|
| 1 | $6.24M | $382K | 6.117e-02 | 16s |
| 5 | $17.4M | $419K | 2.414e-02 | 41s |
| 10 | $31.3M | $466K | 1.491e-02 | 67s |
| 25 | $73.0M | $607K | 8.317e-03 | 2.0m |
| 50 | $143M | $842K | 5.907e-03 | 2.8m |
| 100 | $282M | $1.31M | 4.658e-03 | 3.6m |
| 250 | $699M | $2.72M | 3.893e-03 | 4.3m |
| 500 | $1.39B | $5.07M | 3.636e-03 | 4.6m |
| 1000 | n/a (at max) | n/a | n/a | n/a |

### T8 Divine -- base $100K/s

| level | cost of +1 | marginal/s | ROI ($/s per $) | payback |
|---|---|---|---|---|
| 1 | $69.3M | $11.1M | 1.609e-01 | 6s |
| 5 | $193M | $12.2M | 6.349e-02 | 16s |
| 10 | $347M | $13.6M | 3.920e-02 | 26s |
| 25 | $811M | $17.7M | 2.187e-02 | 46s |
| 50 | $1.58B | $24.6M | 1.554e-02 | 64s |
| 100 | $3.13B | $38.3M | 1.225e-02 | 82s |
| 250 | $7.76B | $79.5M | 1.024e-02 | 1.6m |
| 500 | $15.5B | $148M | 9.562e-03 | 1.7m |
| 1000 | n/a (at max) | n/a | n/a | n/a |

## 4. The swing ladder

`reach` = best-case landing distance = `DISTANCE_PER_MULTIPLIER` x `SWEET_SPOT_MULTIPLIER` x tier scale,
i.e. a **perfect** sweet-spot launch. A typical landing falls short of this. Band = `floor(reach / 40)`,
luck = `LuckCurve.VALUES[band+1]` -- exactly what `LaunchServer.bandLuckForLandingZ` computes.

`post-box` is that luck after the mystery box's doubling chain, at the box's **geometric-mean**
multiplier of 2.33x. See the appendix -- the arithmetic mean does not exist.

| tier | price | x prev | dist scale | reach (studs) | band | band luck | post-box luck | modal tier at post-box |
|---|---|---|---|---|---|---|---|---|
| 1 | - | - | 1.0 | 200 | 5 | 30 | 69 | Uncommon |
| 2 | $50.0K | - | 3.0 | 600 | 15 | 80 | 186 | Uncommon |
| 3 | $250K | 5.0x | 4.4 | 880 | 22 | 250 | 583 | Rare |
| 4 | $1.00M | 4.0x | 6.4 | 1280 | 32 | 750 | 1,749 | Rare |
| 5 | $10.0M | 10.0x | 8.2 | 1640 | 40 | 2,500 | 5,832 | Epic |
| 6 | $100M | 10.0x | 9.2 | 1840 | 45 | 5,000 | 11,665 | Legendary |
| 7 | $1.00B | 10.0x | 10.8 | 2160 | 54 | 9,500 | 22,164 | Legendary |
| 8 | $500B | 500.0x | 11.6 | 2320 | 58 | 25,000 | 58,326 | Mythic |
| 9 | $500T | 1000.0x | 12.6 | 2520 | 63 | 50,000 | 116,652 | Mythic |
| 10 | $5.00Qi | 10000.0x | 13.8 | 2760 | 69 | 80,000 | 186,644 | Mythic |
| 11 | $250Qi | 50.0x | 14.8 | 2960 | 73 | 100,000 | 233,305 | Mythic |

## 5. Time to afford each swing tier

### Assumptions, stated explicitly

1. A player at swing tier N has **all 10 slots filled**, with slimes rolled at that tier's own post-box
   luck. Income per slot = the probability-weighted mean base income of the tier distribution at that luck.
2. **All slimes at level 1** -- no upgrade spend at all. This is the reading most generous to swing
   tiers and least generous to upgrades; section 6 is where that tension shows up.
3. Every launch lands a **perfect sweet spot**. Real landings fall short, so real luck -- and so real
   income -- is lower. These times are a **lower bound**.
4. The box resolves at its geometric-mean multiplier every time.
5. Income is banked continuously and spent on nothing else.

| from tier | to tier | income/slot | income/s (x10 slots) | price | time to afford |
|---|---|---|---|---|---|
| 1 | 2 | $27/s | $271/s | $50.0K | 3.1m |
| 2 | 3 | $26/s | $262/s | $250K | 15.9m |
| 3 | 4 | $63/s | $632/s | $1.00M | 26.4m |
| 4 | 5 | $61/s | $605/s | $10.0M | 4.6h |
| 5 | 6 | $156/s | $1.56K/s | $100M | 17.9h |
| 6 | 7 | $585/s | $5.85K/s | $1.00B | 47.5h |
| 7 | 8 | $557/s | $5.57K/s | $500B | 2.8y |
| 8 | 9 | $3.46K/s | $34.6K/s | $500T | 457.8y |
| 9 | 10 | $3.07K/s | $30.7K/s | $5.00Qi | 5161744.8y |
| 10 | 11 | $3.05K/s | $30.5K/s | $250Qi | 259435687.3y |

## 6. Where the time goes -- swing tier vs. +100 upgrade

Same income model as section 5. `best slime` = the highest-income slime of the **modal tier** at that
swing tier's post-box luck -- the best a player at that stage can routinely expect to own. The +100 is
priced from level 50, a plausible level for a slime someone has been feeding.

| at tier | income/s | next tier price | t(next tier) | best slime | +100 from L50 | t(+100) | **ratio** |
|---|---|---|---|---|---|---|---|
| 1 | $271/s | $50.0K | 3.1m | Uncommon $25/s | $77.8M | 3.3d | **1556.5x** |
| 2 | $262/s | $250K | 15.9m | Uncommon $25/s | $77.8M | 3.4d | **311.3x** |
| 3 | $632/s | $1.00M | 26.4m | Rare $60/s | $187M | 3.4d | **186.8x** |
| 4 | $605/s | $10.0M | 4.6h | Rare $60/s | $187M | 3.6d | **18.7x** |
| 5 | $1.56K/s | $100M | 17.9h | Epic $150/s | $467M | 3.5d | **4.7x** |
| 6 | $5.85K/s | $1.00B | 47.5h | Legendary $500/s | $1.56B | 3.1d | **1.6x** |
| 7 | $5.57K/s | $500B | 2.8y | Legendary $500/s | $1.56B | 3.2d | **0.0x** |
| 8 | $34.6K/s | $500T | 457.8y | Mythic $1.50K/s | $4.67B | 37.5h | **0.0x** |
| 9 | $30.7K/s | $5.00Qi | 5161744.8y | Mythic $1.50K/s | $4.67B | 42.3h | **0.0x** |
| 10 | $30.5K/s | $250Qi | 259435687.3y | Mythic $1.50K/s | $4.67B | 42.5h | **0.0x** |

### The mid-game player in detail

Swing tier 5. Income $1.56K/s across 10 slots. Best slime a Epic at $150/s base.
Tier 6 costs $100M = **17.9h**.

| +100 from level | cost | time | ratio vs next swing tier |
|---|---|---|---|
| 1 | $240M | 42.8h | 2.4x |
| 5 | $258M | 46.1h | 2.6x |
| 10 | $282M | 2.1d | 2.8x |
| 25 | $351M | 2.6d | 3.5x |
| 50 | $467M | 3.5d | 4.7x |
| 100 | $699M | 5.2d | 7.0x |
| 250 | $1.39B | 10.4d | 13.9x |
| 500 | $2.55B | 19.0d | 25.5x |

The cheapest upgrade actions available to that same player, for scale:

| action | cost | time | ratio vs next swing tier |
|---|---|---|---|
| +1 at L1 | $104K | 67s | 0.00x |
| +10 at L1 | $3.13M | 33.5m | 0.03x |
| +100 at L1 | $240M | 42.8h | 2.40x |

## 7. Observations and anomalies

All computed, all from the same config load as everything above.

### 7.1 Buying a swing tier can LOWER your expected income

Expected income per slot at each swing tier's own post-box luck. Negative deltas mean the tier
you just paid for rolls *worse* slimes on average than the one below it.

| tier | band luck | post-box luck | E[income]/slot | delta vs prev |
|---|---|---|---|---|
| 1 | 30 | 69 | $27/s | - |
| 2 | 80 | 186 | $26/s | -3.3% |
| 3 | 250 | 583 | $63/s | +141.3% |
| 4 | 750 | 1,749 | $61/s | -4.2% |
| 5 | 2,500 | 5,832 | $156/s | +157.1% |
| 6 | 5,000 | 11,665 | $585/s | +276.2% |
| 7 | 9,500 | 22,164 | $557/s | -4.8% |
| 8 | 25,000 | 58,326 | $3.46K/s | +521.2% |
| 9 | 50,000 | 116,652 | $3.07K/s | -11.3% |
| 10 | 80,000 | 186,644 | $3.05K/s | -0.5% |
| 11 | 100,000 | 233,305 | $3.05K/s | +0.0% |

Tiers that are a net downgrade for rolling: **2** (-3.3%), **4** (-4.2%), **7** (-4.8%), **9** (-11.3%), **10** (-0.5%).

The cause is in `SlimeRoll` and is documented there as a known dip: within a *static* window,
rising luck concentrates probability on the peak tier and drains the tail above it. The comment
says the LOW/HIGH shape constants were solved together to keep that dip negligible -- and in
*probability* terms it is small. In *income* terms it is not, because tier mean incomes grow
roughly 2.5-3x per tier, so losing a point of tail probability costs far more than gaining a
point of peak probability pays. The dip was tuned against the wrong quantity.

### 7.2 The luck curve saturates before the price ladder does

`SLIME_EXTRAPOLATION_T_MAX` = 1.0 clamps t at the high anchor, so **every post-box luck at or
above 120,000 produces an identical distribution**. At the box's 2.33x that means any band luck at or
above 51,434.

| tier | band luck | post-box | saturated? | price |
|---|---|---|---|---|
| 8 | 25,000 | 58,326 | no | $500B |
| 9 | 50,000 | 116,652 | no | $500T |
| 10 | 80,000 | 186,644 | **YES** | $5.00Qi |
| 11 | 100,000 | 233,305 | **YES** | $250Qi |

Tier 10 and tier 11 distributions identical to 1e-12: **true**. Tier 11 costs $250Qi and buys
no change whatsoever in what it rolls -- only reach, which nothing else reads once the band tops out.
Tier 9 is only 2.8% short of the clamp itself (post-box 116,652 against a 120,000 anchor), so the
effective top of the roll curve is tier 9 for any box chain of two doublings or more.

### 7.3 The swing price ladder has two discontinuities

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

Tiers 3-7 run a clean 4-10x ladder. Tier 8 jumps 500x, tier 9 1000x, tier 10 10000x -- then tier 11
drops back to 50x. The 10000x step and the 50x step are inconsistent with each other and with
everything below.

### 7.4 Upgrade payback gets WORSE with level, and the tier spread is ~870x

Payback for a single `+1`, at each tier and level. It rises monotonically with level for every tier --
upgrading never gets better, it converges to a per-tier floor from below.

| tier | L1 | L10 | L100 | L500 | L900 |
|---|---|---|---|---|---|
| T1 Common | 1.5h | 6.2h | 19.7h | 25.3h | 26.1h |
| T2 Uncommon | 34.3m | 2.3h | 7.5h | 9.6h | 9.9h |
| T3 Rare | 13.0m | 53.5m | 2.9h | 3.7h | 3.8h |
| T4 Epic | 5.0m | 20.3m | 65.1m | 83.4m | 86.1m |
| T5 Legendary | 1.9m | 7.7m | 24.8m | 31.7m | 32.7m |
| T6 Mythic | 43s | 2.9m | 9.4m | 12.1m | 12.4m |
| T7 Secret | 16s | 67s | 3.6m | 4.6m | 4.7m |
| T8 Divine | 6s | 26s | 82s | 1.7m | 1.8m |

At level 500 a Common's level pays back in 25.3h; a Divine's in 1.7m -- a **871x** spread, which is
exactly `INCOME_MAX_MULTIPLIER_RATIO^7` = 870. Payback is inversely proportional to a tier's max
multiplier, so levelling a low-tier slime is never worth doing at any level.

### 7.5 The cost curve was fitted to Secret and only works there

`SlimeUpgradeConfig` says level 901's upgrade should cost `~0.65 seconds of ITS OWN (level-901,
already leveled) income`. That is true for Secret and badly false elsewhere -- the cost is a flat
multiple of BASE income for every tier, while the income multiplier that pays it back is scaled per
tier. Cost of `+1` at level 901, in seconds of that slime's own current income:

| tier | seconds of own income |
|---|---|
| T1 Common | 200.39s |
| T2 Uncommon | 76.20s |
| T3 Rare | 28.97s |
| T4 Epic | 11.02s |
| T5 Legendary | 4.19s |
| T6 Mythic | 1.59s |
| T7 Secret | 0.61s |
| T8 Divine | 0.23s |

The documented 0.65s lands on Secret, as the comment claims. Common pays ~330x more.

### 7.6 The mystery box has no expected value

`BOX_DOUBLE_CHANCE` = 0.55, so 2p = 1.10 > 1 and E[2^D] is a **divergent series** -- the box's mean
luck multiplier does not exist as a finite number. Every figure in this document uses the geometric
mean (2.33x) instead, which is finite and is the right average for a multiplicative process, but
it is worth knowing that the design has no mean payout: the tail is heavy enough that a long enough
session is dominated by single lucky chains. See the appendix for the tail probabilities.

## Appendix: the mystery box multiplier

Each press doubles luck with probability p = 0.55, otherwise opens the box. The number of
doublings D is geometric, so the luck multiplier is 2^D.

| statistic | value |
|---|---|
| E[D], expected doublings | 1.2222 |
| median D | 1 |
| geometric-mean multiplier, 2^E[D] | 2.333x |
| median multiplier | 2x |
| E[2^D], the arithmetic mean | **divergent** -- 2p = 1.10 > 1 |
| P(D >= 5), a 32x box | 5.03% |
| P(D >= 10), a 1024x box | 0.25% |
| P(D >= 20), a ~1,000,000x box | 0.0006% (1 in 155864) |

