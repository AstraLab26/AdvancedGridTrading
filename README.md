# Advanced Grid Trading EA

MetaTrader 5 Expert Advisor for grid trading with two independent order types (AA and BB), trailing profit, session-based balance logic, and notifications.

---

## Overview

- **Grid:** Base price at attach, evenly spaced levels (pips), max levels per side. Buy Stop above base, Sell Stop below base.
- **AA & BB:** Separate lot, Fixed/Geometric, multiplier, max lot, TP, and comment. Same grid; each level has at most one AA and one BB (pending or position). AA uses Magic Number, BB uses Magic Number + 1. All orders use a single comment (e.g. "EA Grid").
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

- Close one **loss** (opposite side of base) + one **profit** (same side as price) when their **combined P/L ≥ threshold** (USD). Lots can differ. Price must be at least **5 grid levels** from base. Cooldown (seconds) after closing a pair.

**AA Balance by BB**

- Close one **losing AA** (opposite side) when **(BB closed P/L in session) + (that AA position P/L) ≥ threshold** (USD). Session only; price must be **5 levels** from base; cooldown after closing.

### 2.2 Common (Magic & Comment)

- **Magic Number** – AA uses this magic; BB uses Magic Number + 1.
- **Order comment** – Same comment for all orders (e.g. "EA Grid").

### 2.3 BB (settings)

- Same structure as AA: Enable, lot, Fixed/Geometric, multiplier, max lot, Take profit.

**BB Auto balance**

- Close **one losing BB** (opposite side) when **(BB closed P/L in session) + (that position P/L) ≥ threshold** (USD). Least negative first. Session only; price **5 levels** from base; cooldown.

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

- **Scale by capital growth** – When enabled, lot, TP, SL, and trailing scale by account growth % vs base capital.
- **Base capital (USD)** – 0 = balance when EA attached; > 0 = use this value.
- **x% (max 100)** – Scaling factor (e.g. 50% = capital +100% vs base → multiply by 50%).

---

## 5. NOTIFICATIONS

- **Send notification when EA resets or stops** – Push notification on full reset or EA stop. Content includes reason, chart, balance, %, max drawdown, max lot / total open.

---

## Session and P/L calculation

- **Current session** starts when:
  - The EA is **attached** to the chart, or  
  - The EA performs an **automatic reset** (trailing lock, balance-orders reset, or trailing all closed).
- On session start, session closed P/L and balance cooldowns are **reset to zero**; `sessionStartTime` is set.
- **Closed P/L** (for session totals and BB closed) = **Profit + Swap + Commission** (deal-based).
- **Open position P/L** (for balance and trailing) = **Profit + Swap** (commission applies when the position is closed).
- Only **deals with time ≥ sessionStartTime** are counted in session closed P/L. Only **positions opened at or after sessionStartTime** are considered “current session” for trailing and balance logic.

---

## File

- **AdvancedGridTrading.mq5** – Single EA file; attach to chart in MetaTrader 5.

---

## Version

2.01 – Advanced Grid Trading EA (Pro edition).
