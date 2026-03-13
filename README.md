# Advanced Grid Trading EA — Full guide

MetaTrader 5 Expert Advisor for **grid trading** with four stackable order types **AA, BB, CC, DD**, **trailing profit**, **balance** logic (closes losing **AA/BB/CC** only), **capital scaling**, **lock profit** (% savings on every profitable TP including **DD**), and **notifications** (including **Price at reset**).

---

## Table of contents

1. [Concepts](#1-concepts)  
2. [Input reference (all groups)](#2-input-reference-all-groups)  
3. [Grid & how orders are placed](#3-grid--how-orders-are-placed)  
4. [AA / BB / CC (Stops) vs DD (Limits)](#4-aa--bb--cc-stops-vs-dd-limits)  
5. [Session, pool, and lock profit](#5-session-pool-and-lock-profit)  
6. [Balance rules (step by step)](#6-balance-rules-step-by-step)  
7. [Balance examples](#7-balance-examples)  
8. [Trailing profit](#8-trailing-profit)  
9. [Capital scaling](#9-capital-scaling)  
10. [Notifications](#10-notifications)  
11. [File & version](#11-file--version)

---

## 1. Concepts

| Term | Meaning |
|------|--------|
| **Base line** | Reference price when the **session** starts (EA attach or reset). Grid levels are built around it. |
| **Session** | Period from attach/reset until next reset. Balance pool and trailing use only deals **in the current session**. |
| **Balance pool** | Money available to **close losing AA/BB/CC** positions. Filled only by **TP closes** (profit after lock). **DD TP also fills the pool**, but DD positions are **never** closed by balance. |
| **Lock profit** | % of each **profitable TP** (AA/BB/CC/**DD**) set aside as savings. **Cumulative, never reset.** Not spent when balancing. |
| **Magic** | AA = input Magic; BB = +1; CC = +2; **DD = +3**. One comment for all (e.g. `EA Grid`). |

---

## 2. Input reference (all groups)

### 1. GRID

| Input | Default | Description |
|-------|---------|-------------|
| Grid distance (pips) | 2000 | Spacing between adjacent levels. |
| Max grid levels per side | **40** | Max levels above **and** below base (total levels = 2 × this). |

### 2. ORDERS — Common

| Input | Default | Description |
|-------|---------|-------------|
| Magic Number | 123456 | AA = this; BB/CC/DD = +1, +2, +3. |
| Order comment | EA Grid | Same on every order. |

### 2.2–2.4 AA / BB / CC

Each block: **Enable**, **Lot level 1**, **Fixed / Geometric**, **Lot mult (level 2+)**, **Max lot (0 = no limit)**, **TP (pips, 0 = off)**, **Enable balance** (pool + loss ≥ 20 USD, cooldown 300 s; prepare at 3 levels, execute at 5).

Typical defaults: AA lot 0.05, Geometric; BB similar; CC often **Fixed** lot; TP BB/CC often 2000 pips (if set).

### 2.5 DD

| Input | Default | Description |
|-------|---------|-------------|
| Enable DD | true | Sell Limit above base + Buy Limit below base. |
| Lot level 1 | **0.01** | Base lot (scaled like others if scaling on). |
| Fixed / Geometric | **Fixed** | How lot grows by level. |
| Max lot | 1.5 | Cap per order (0 = no limit). |
| TP (pips) | 2000 | TP distance; 0 = off. |
| Balance | — | **DD has no balance** — EA never closes DD to balance. |

### 3. SESSION — Trailing

| Input | Default | Description |
|-------|---------|-------------|
| Enable trailing | true | Cancel pendings and trail SL when profit ≥ threshold. |
| Start when profit ≥ (USD) | **200** | Enter trailing mode. |
| When profit drops | Return | **Lock** = close all + reset; **Return** = exit trailing, replace pendings. |
| Drop % | 20 | Trigger when profit falls this % from peak. |
| Point A (pips) | 1500 | SL anchor from grid level at threshold. |
| Trailing step (pips) | 1000 | SL moves by this step. |
| Breakeven reset | false | Optional reset when far from base and P/L + pool ≥ 0. |
| Breakeven min levels | 10 | Min levels from base for breakeven reset. |

### 4. CAPITAL % SCALING

| Input | Default | Description |
|-------|---------|-------------|
| Scale by growth | true | Scale lot (AA/BB/CC/**DD**) and trailing threshold. |
| Base capital (USD) | **100000** | 0 = balance at attach; >0 = fixed base for multiplier. |
| x% (scale) | 50 | `multiplier = 1 + growth × (x/100)` capped by max increase. |
| Max increase % | 100 | Caps multiplier (e.g. 100 → max mult 2.0). |

### 5. NOTIFICATIONS

| Input | Default | Description |
|-------|---------|-------------|
| Notify on reset/stop | true | Push (+ Telegram if enabled). Includes **Price at reset** (Bid). |
| Telegram | off | Needs Bot token + Chat ID + WebRequest allow list. |

### 6. LOCK PROFIT

| Input | Default | Description |
|-------|---------|-------------|
| Enable | true | Reserve % of each **profitable TP** (AA/BB/CC/**DD**). |
| Lock % | 25 | e.g. 25 → 25 USD locked from 100 USD profit; 75 USD to pool. |

---

## 3. Grid & how orders are placed

- Levels are **evenly spaced** by Grid distance. **No order at base**; level 1 is closest to base, then 2, 3, …  
- EA adds missing orders **from nearest level to base outward**.  
- **At most one pending per type per level**; duplicates are deleted.

**AA / BB / CC (Stop orders)**  
- **Buy Stop:** only at levels **above base** and **above current price**.  
- **Sell Stop:** only at levels **below base** and **below current price**.

**DD (Limit orders)**  
- **Sell Limit:** on levels **above base** — triggers when price **falls** to that level.  
- **Buy Limit:** on levels **below base** — triggers when price **rises** to that level.

---

## 4. AA / BB / CC (Stops) vs DD (Limits)

| | AA, BB, CC | DD |
|--|------------|-----|
| Pending types | Buy Stop / Sell Stop | Sell Limit (above base) / Buy Limit (below base) |
| Balance | Optional per type | **Never** — DD not closed by balance |
| Pool | TP increases pool | **TP increases pool** (helps AA/BB/CC) |
| Lock on TP | Yes | **Yes** — same % |
| Lot scaling | Yes | **Yes** |

---

## 5. Session, pool, and lock profit

- **Session** starts at attach or reset. `sessionStartTime` is set; pool counters can reset.  
- **Only DEAL_REASON_TP** adds to pool. SL/manual/stop-out do **not**.  
- On each profitable TP close:  
  - Deal P/L = Profit + Swap + Commission.  
  - If lock enabled: `locked = P/L × (Lock%/100)` → add to **lockedProfitReserve** (never reset).  
  - **Remainder** adds to **session pool**.  
- **Pool** is **shared** for balancing **AA/BB/CC** only.  
- **Floor:** balance after a balance-close must be **≥ session start balance + cumulative locked** so savings are not consumed.

---

## 6. Balance rules (step by step)

Fixed in code: **20 USD** threshold, **300 s** cooldown, **3 levels** prepare, **5 levels** execute.

1. **Opposite side only:**  
   - Price **above base** → only close **losing Sells** (below base). **Buys locked** — never closed by balance.  
   - Price **below base** → only close **losing Buys** (above base). **Sells locked**.

2. **Distance from base:**  
   - **Prepare** (select farthest opposite loser): price **≥ 3 levels** from base.  
   - **Execute** (close): price **≥ 5 levels** from base **and** pool enough.

3. **Order of closes:**  
   - **Farthest from base first.**  
   - Same level: **AA → BB → CC**.

4. **Partial close:** if pool < full loss, close **part of lot** proportionally; deal comment **"Balance order"**.

5. **DD:** never selected for balance; DD TP still **increases pool**.

---

## 7. Balance examples

**Setup:** Base = 1000. Step = 100 pips → above: 1010, 1020, … below: 990, 980, …

**Ex.1 — Above base**  
Price 1200 (≥5 levels). Losing Sells below base −120, −80, −50. Close farthest first; Buys not touched.

**Ex.2 — Below base**  
Price 850. Losing Buys above base only; Sells not touched.

**Ex.3 — Partial**  
Pool 60, need 120 → close 50% lot; wait for more TP.

**Ex.4 — Same level**  
Sell AA, Sell BB, Sell CC at same price → close AA then BB then CC.

**Ex.5 — Near base**  
Price within 5 levels of base → **no** balance execute.

---

## 8. Trailing profit

- Open profit ≥ **TrailingThresholdUSD** → cancel pendings, manage SL (Point A, then step).  
- **Lock** mode: drop X% from peak → close all + reset.  
- **Return** mode: drop X% → leave trailing, restore grid (no forced close if SL not placed yet per logic).  
- Optional breakeven reset when enabled and conditions met.

---

## 9. Capital scaling

- `growth = (currentBalance − baseCapital) / baseCapital` (or 0 if base ≤ 0).  
- `sessionMultiplier = 1 + growth × (AccountGrowthScalePct/100)`, capped.  
- Applied to lot base (AA/BB/CC/**DD**) and trailing USD threshold when scaling is on.

---

## 10. Notifications

Reset/stop message includes:

- Chart, **Reason**  
- **Price at reset:** Bid at moment of notification  
- Initial balance at EA startup (never reset)  
- Base capital, scale %  
- Current balance, change % vs initial, drawdown, lowest balance  
- **Locked profit (saved, cumulative)**  
- Optional Telegram block (same text)

Example:

```
EA RESET
Chart: GBPUSD
Reason: Trailing profit (SL hit)
Price at reset: 1.26543
--- SETTINGS ---
Initial balance at EA startup: 100000.00 USD
Base capital (USD): 100000.00
...
```

Add `https://api.telegram.org` to MT5 **WebRequest** allow list.

---

## 11. File & version

- **File:** `AdvancedGridTrading.mq5` — single EA, attach to MT5 chart.  
- **Version 2.07** — Four types (AA/BB/CC Stop + DD Limit); pool from all; balance only AA/BB/CC; lock on all TP; **Price at reset** in notifications.
