# Advanced Grid Trading EA

MetaTrader 5 Expert Advisor for grid trading with three independent order types (AA, BB, CC), trailing profit, session-based balance logic, capital scaling, lock profit, and notifications.

---

## Overview

- **Grid:** Base price at attach, evenly spaced levels (pips), max levels per side. Buy Stop above base, Sell Stop below base.
- **AA, BB & CC:** Separate lot, Fixed/Geometric, multiplier, max lot, TP, and magic. Same grid; each level has at most one AA, one BB, and one CC (pending or position). AA = Magic Number, BB = Magic Number + 1, CC = Magic Number + 2. All orders use a single comment (e.g. "EA Grid").
- **Session:** Current session starts when the EA is attached or when the EA performs an automatic reset. All balance and trailing logic uses only positions and closed P/L from the current session. P/L includes profit, swap, and commission where applicable.

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

**AA Auto balance (pair)**

- Close one **loss** (opposite side of base) + one **profit** (same side as price) when their **combined P/L ≥ threshold** (USD). Lots can differ. Price must be at least **5 grid levels** from base. Cooldown (seconds) after closing a pair. **Only runs when session closed P/L (after lock) ≥ 0.**

**AA Balance by BB**

- Close one **losing AA** (opposite side) when **(BB closed P/L in session) + (that AA position P/L) ≥ threshold** (USD). Session only; price must be **5 levels** from base; cooldown after closing. **Only runs when BB session closed P/L (after lock) ≥ 0.**

### 2.2 Common (Magic & Comment)

- **Magic Number** – AA uses this magic; BB = Magic + 1; CC = Magic + 2.
- **Order comment** – Same comment for all orders (e.g. "EA Grid").

### 2.3 BB (settings)

- Same structure as AA: Enable, lot, Fixed/Geometric, multiplier, max lot, Take profit.

**BB Auto balance**

- Close **one losing BB** (opposite side) when **(BB closed P/L in session) + (that position P/L) ≥ threshold** (USD). Least negative first. Session only; price **5 levels** from base; cooldown. **Only runs when BB session closed P/L (after lock) ≥ 0.**

### 2.4 CC (settings)

- Same logic as BB, separate parameters: Enable, lot, Fixed/Geometric, multiplier, max lot, Take profit.

**CC Auto balance**

- Close **one losing CC** (opposite side) when **(CC closed P/L in session) + (that position P/L) ≥ threshold** (USD). Least negative first. Session only; price **5 levels** from base; cooldown. **Only runs when CC session closed P/L (after lock) ≥ 0.**

---

## 3. SESSION: Trailing profit

- **Enable trailing** – When open profit (current session) ≥ threshold (USD), cancel all pending and start trailing SL (Buy/Sell) on open positions.
- **Start trailing when open profit ≥ (USD)** – Threshold to enter trailing mode.
- **Lock: close all when profit drops this % from peak** – If profit falls by this % from the session peak, close all and reset (new session).
- **Pips: SL distance / trailing step** – SL distance from price and step for trailing updates.

Only positions opened in the **current session** are used for trailing. Notifications are sent on reset, not on entering trailing.

---

## 3B. SESSION: Balance orders (reset EA by grid levels)

- **Enable** – When enabled, the EA can **reset** (close all, new base, replace orders) when:
  - Number of grid levels with an open position (current session) ≥ **Min grid levels**, and  
  - Session total (closed + open P/L) ≥ **Session total threshold** (USD).

---

## 4. CAPITAL % SCALING

- **Scale by capital growth** – When enabled, **lot** (AA/BB/CC) and **trailing threshold (USD)** are scaled by account growth % vs base capital.
- **Base capital (USD)** – 0 = balance when EA attached; > 0 = use this value. Base is set once and not updated on EA reset.
- **x% (max 100)** – Scaling factor. Formula: `multiplier = 1 + growth × (x/100)`, where `growth = (current balance − base) / base`. Multiplier is clamped between 0.1 and 10. Example: base 50,000, current 75,000 → growth 50%; x = 50 → multiplier 1.25 → lots and trailing threshold × 1.25.

**What is scaled:** AA/BB/CC base lot and Trailing threshold (USD). TP/SL (pips) use input values and are not multiplied by this factor.

---

## 5. NOTIFICATIONS

- **Send notification when EA resets or stops** – Push notification on full reset or EA stop. Content includes reason, chart, balance, %, max drawdown, max lot / total open. Reset message includes **Locked profit (saved, cumulative): X.XX USD** when lock profit is used.

---

## 6. LOCK PROFIT (Save %)

**Meaning:** Lock profit = reserve a portion of each profitable close so that **this amount is not counted in AA/BB/CC balance logic** (and not in trailing/session totals for thresholds).

When enabled:

- On each **profitable** close (deal P/L > 0), a **percentage** of that profit (e.g. 25%) is **locked** into a reserve.
- **Deal P/L** = Profit + Swap + Commission. Locked = deal P/L × (Lock % / 100). Only the **remainder** is added to session closed P/L (and to BB/CC session totals when the deal is BB/CC).
- The **locked amount** is **not** included in:
  - Session closed totals used for **AA pair balance**, **AA by BB**, **BB auto balance**, **CC auto balance**
  - Trailing threshold or session total for reset.
- The locked reserve is **cumulative** and **never reset** by the EA. The reset notification shows: **Locked profit (saved, cumulative): X.XX USD**.

**Parameters:**

- **Enable Lock Profit** – Turn the feature on/off.
- **Lock this %** – Percentage of each profitable close to reserve (0–100). Example: 25 = reserve 25 USD from 100 USD profit; only 75 USD counts toward balance/trailing.

**Example (10% lock):**

- Start: **1000 USD**. Session starts at 1000 USD, session closed P/L = 0.
- **Order 1** closes at TP **+100 USD** → 10% locked = 10 USD → **90 USD** added to “available for balance”.
- **Order 2** closes at TP **+200 USD** → 10% locked = 20 USD → **180 USD** added to “available for balance”.
- Total available for balance = 90 + 180 = **270 USD**. **Order 3** is open and **−100 USD**.
- Balance condition met: 270 + (−100) = 170 ≥ threshold, session closed ≥ 0, and **remaining after close ≥ 0** (170 ≥ 0) → EA **closes order 3** (realizes −100).
- After close: session closed P/L = **170 USD**. Locked reserve cumulative = **30 USD**. Account balance = 1000 + 100 + 200 − 100 = **1200 USD**.
- **If order 3 had been −300 USD:** 270 + (−300) = −30 &lt; 0 → balance would **not** close it (do not spend more than the 270 available).
- **EA reset** → new session; session closed P/L **resets to 0**; only deals in the new session count from then on.

---

## Session and P/L calculation

- **Current session** starts when:
  - The EA is **attached** to the chart, or  
  - The EA performs an **automatic reset** (trailing lock, balance-orders reset, or trailing all closed).
- On session start, session closed P/L and balance cooldowns are **reset to zero**; `sessionStartTime` is set. Each EA reset = **new session** (count from the beginning). **Capital scaling multiplier** is updated on init and after each full reset (using current balance vs base).
- **Closed P/L** (for session totals and balance) = **Profit + Swap + Commission** (deal-based). When Lock Profit is on: on each **profitable** close, a **percentage is locked** (reserve); only the **remainder** is added to session closed P/L. That remainder is the amount **available for balance** (AA, BB, CC).
- **Balance rule:** Balance (AA pair, AA by BB, BB, CC) **only runs when** the relevant session closed P/L (after lock) is **≥ 0**. If session closed is negative, balance is not allowed (no spend on closing losers).
- **Do not spend more than available:** A losing order is closed only when **after closing, the remaining session P/L (for that type) stays ≥ 0**. If the loss is greater than the available amount (e.g. 270 available, loss 300 → 270 − 300 = −30), balance does **not** close that order.
- **Open position P/L** (for balance and trailing) = **Profit + Swap** (commission applies when the position is closed).
- Only **deals with time ≥ sessionStartTime** are counted in session closed P/L. Only **positions opened at or after sessionStartTime** are considered “current session” for trailing and balance logic.

---

## File

- **AdvancedGridTrading.mq5** – Single EA file; attach to chart in MetaTrader 5.

---

## Version

2.01 – Advanced Grid Trading EA (Pro edition). AA, BB, CC; Lock profit; Capital % scaling; session-based balance and trailing.
