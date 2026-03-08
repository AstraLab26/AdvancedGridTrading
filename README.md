# Advanced Grid Trading EA

MetaTrader 5 Expert Advisor for grid trading with three independent order types (AA, BB, CC), trailing profit, session-based balance logic, capital scaling, lock profit (save %), and notifications.

---

## Overview

- **Grid:** Base price at attach, evenly spaced levels (pips), max levels per side. Buy Stop above base, Sell Stop below base.
- **AA, BB & CC:** Separate lot, Fixed/Geometric, multiplier, max lot, TP, and magic. Same grid; each level has at most one AA, one BB, and one CC (pending or position). AA = Magic Number, BB = Magic Number + 1, CC = Magic Number + 2. All orders use a single comment (e.g. "EA Grid").
- **Session:** Current session starts when the EA is attached or when the EA performs an automatic reset. All balance and trailing logic uses only positions and closed P/L from the current session. **Only orders closed at Take Profit (TP)** contribute to the balance pool; SL or manual closes do not.
- **Balance pool:** Pool = (AA + BB + CC) **TP closes in session** minus **lock % (savings)**. This single pool is used for balancing losing AA, BB, and CC. Balance is allowed only when **pool covers the loss** and **account balance after close does not fall below the floor** (session start balance + locked reserve).

---

## 1. GRID

| Parameter | Description |
|-----------|-------------|
| **Grid distance (pips)** | Distance between adjacent grid levels. |
| **Max grid levels per side** | Maximum levels above and below the base line. |

Levels are evenly spaced. No orders at the base; level 1 is closest to base, then level 2, 3, …

---

## 2. ORDERS

### 2.1 AA (settings)

- **Enable AA** – Turn AA (Buy Stop + Sell Stop) on/off.
- **Lot level 1** – Lot size for the first level.
- **Fixed / Geometric** – Lot scaling: Fixed or Geometric (multiplier per level).
- **Lot multiplier** – For Geometric: multiplier for level 2+.
- **Max lot** – Maximum lot per order (0 = no limit).
- **Take profit (pips)** – TP in pips (0 = off).

**AA Balance (by TP pool)**

- **Priority: close the losing AA farthest from the base line first** (one position per run). Close **one losing AA** (opposite side) when:
  1. **(Pool + that AA loss) ≥ threshold** (USD) and **≥ 0** (pool covers the loss).
  2. **Account balance after close ≥ floor** (session start balance + locked profit reserve).
- **If pool is not enough to close the full position:** EA closes a **partial** amount (lot proportional to spendable $). If even partial is below min lot, wait until pool increases.
- Pool = session **TP closes** (AA+BB+CC) minus lock %. Session only; price must be **5 levels** from base; cooldown after closing.

### 2.2 Common (Magic & Comment)

- **Magic Number** – AA uses this magic; BB = Magic + 1; CC = Magic + 2.
- **Order comment** – Same comment for all orders (e.g. "EA Grid").

### 2.3 BB (settings)

- Same structure as AA: Enable, lot, Fixed/Geometric, multiplier, max lot, Take profit.

**BB Balance (by TP pool)**

- Close **losing BB** (opposite side) when (pool + that loss) ≥ threshold and ≥ 0, and **balance after close ≥ floor**. **Priority: close the losing position farthest from the base line first.** If pool is not enough to close it fully, **partial close** (lot proportional to $); if below min lot, wait for pool to grow. Pool = session TP closes minus lock %. Session only; price **5 levels** from base; cooldown.

### 2.4 CC (settings)

- Same logic as BB, separate parameters: Enable, lot, Fixed/Geometric, multiplier, max lot, Take profit.

**CC Balance (by TP pool)**

- Close **losing CC** (opposite side) when (pool + that loss) ≥ threshold and ≥ 0, and **balance after close ≥ floor**. **Priority: close the losing position farthest from the base line first.** If pool is not enough to close it fully, **partial close** (lot proportional to $); if below min lot, wait for pool to grow. Same shared pool (TP closes − lock %). Session only; cooldown.

---

## 3. SESSION: Trailing profit

- **Enable trailing** – When open profit (current session) ≥ threshold (USD), cancel all pending and start trailing SL (Buy/Sell) on open positions.
- **Start trailing when open profit ≥ (USD)** – Threshold to enter trailing mode.
- **Lock: close all when profit drops this % from peak** – If profit falls by this % from the session peak, close all and reset (new session).
- **Pips: SL distance / trailing step** – SL distance from price and step for trailing updates.

Only positions opened in the **current session** are used for trailing. Notifications are sent on reset.

---

## 4. CAPITAL % SCALING

- **Scale by capital growth** – When enabled, **lot** (AA/BB/CC) and **trailing threshold (USD)** are scaled by account growth % vs base capital.
- **Base capital (USD)** – 0 = balance when EA attached; > 0 = use this value. Base is updated on EA reset (session start).
- **x% (max 100)** – Scaling factor. Formula: `multiplier = 1 + growth × (x/100)`. Multiplier is clamped. TP/SL (pips) use input values and are not scaled.

---

## 5. NOTIFICATIONS

- **Send notification when EA resets or stops** – Push notification on full reset or EA stop. Content includes reason, chart, balance, %, max drawdown, max lot / total open. Reset message includes **Locked profit (saved, cumulative): X.XX USD** when lock profit is used.

---

## 6. LOCK PROFIT (Save %)

**Meaning:** Lock profit = reserve a **percentage** of each **profitable TP close**. This amount is **not** used for the balance pool. Only the **remainder** (TP $ − lock %) is added to the pool that pays for closing losing orders.

When enabled:

- On each **profitable** close that is a **Take Profit** (TP), a **percentage** of that profit (e.g. 10%) is **locked** into a reserve.
- **Deal P/L** = Profit + Swap + Commission. Locked = deal P/L × (Lock % / 100). Only the **remainder** is added to the session balance pool.
- The **balance pool** = sum over current session of (TP close $ − lock %) for AA, BB, and CC. This pool is **shared** for balancing AA, BB, and CC.
- **Floor:** When balancing, a losing order is closed only if **account balance after close ≥ session start balance + locked profit reserve**. So capital never drops below (session start + savings).

**Parameters:**

- **Enable Lock Profit** – Turn the feature on/off.
- **Lock this %** – Percentage of each profitable TP close to reserve (0–100). Example: 10 = reserve 10 USD from 100 USD profit; 90 USD goes to the balance pool.

**Example (10% lock, floor):**

- EA resets; **session start balance = 1700 USD**. Lock % = 10%.
- **Orders 1, 2, 3** close at TP: total profit **+300 USD** → 10% locked = **30 USD** → **270 USD** added to balance pool.
- Account balance = 2000 USD. **Floor = 1700 + 30 = 1730 USD** (capital must not go below this).
- **Orders 4, 5, 6** are losing. EA may close them only if:
  - (Pool + that loss) ≥ threshold and ≥ 0 (pool covers the loss),
  - **Balance after close ≥ 1730 USD** (so total loss taken from balance ≤ 270 USD).
- So balance can drop to **minimum 1730 USD**, not lower. When more orders hit TP, pool increases and balancing can continue.

---

## Session and P/L calculation

- **Current session** starts when the EA is **attached** or when the EA **resets** (trailing lock or all closed).
- **Only TP closes** (DEAL_REASON_TP) are counted in the balance pool. SL, manual, or stop-out closes do **not** add to the pool.
- **Pool** = (AA + BB + CC) session TP closes, minus lock % on each profitable TP close. One shared pool for AA, BB, and CC balance.
- **Balance rule:** Close a loser only when:
  1. **(Pool + that loss) ≥ threshold** and **≥ 0** (pool covers the loss).
  2. **Account balance after close ≥ session start balance + locked profit reserve** (floor).
- **Order of closing:** **Farthest from base line first.** If pool is not enough to close that position fully, **partial close** (lot proportional to spendable $); if below min lot, wait until pool increases.
- **Remaining pool** is decreased when a losing order is closed (same tick: AA then BB then CC use the same remaining pool).
- **Open position P/L** = Profit + Swap. Only positions opened at or after session start are considered for balance and trailing.

---

## File

- **AdvancedGridTrading.mq5** – Single EA file; attach to chart in MetaTrader 5.

---

## Version

2.01 – Advanced Grid Trading EA (Pro). AA, BB, CC; only TP for pool; shared pool; floor = session start + locked; lock profit; capital scaling; session balance (farthest-from-base first, partial close when pool insufficient) and trailing.
