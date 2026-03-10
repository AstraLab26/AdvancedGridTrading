# Advanced Grid Trading EA

MetaTrader 5 Expert Advisor for grid trading with three independent order types (AA, BB, CC), trailing profit, session-based balance logic, capital scaling, lock profit (save %), and notifications.

---

## Overview

- **Grid:** Base price at attach, evenly spaced levels (pips), max levels per side. **Buy Stop** is placed only at levels **above the base line and above current price**; **Sell Stop** only at levels **below the base line and below current price**. Missing orders (per enabled type AA/BB/CC) at a level are added by the EA.
- **AA, BB & CC:** Separate lot, Fixed/Geometric, multiplier, max lot, TP, and magic. Same grid; **at most one order per type per level** (per input: if AA enabled then max 1 AA, etc.). AA = Magic Number, BB = Magic Number + 1, CC = Magic Number + 2. All orders use a single comment (e.g. "EA Grid").
- **Session:** Current session starts when the EA is attached or when the EA performs an automatic reset. All balance and trailing logic uses only positions and closed P/L from the current session. **Only orders closed at Take Profit (TP)** contribute to the balance pool; SL or manual closes do not.
- **Balance pool:** Pool = **TP closes in current session only** minus **lock (savings) in current session**. Only this remainder is used for balancing. **Locked $ (savings)** is **cumulative across sessions and never reset**; that locked amount is **not used for balance** (floor = session start balance + locked reserve so balance never spends the reserve).

---

## 1. GRID

| Parameter | Description |
|-----------|-------------|
| **Grid distance (pips)** | Distance between adjacent grid levels. |
| **Max grid levels per side** | Maximum levels above and below the base line. |

Levels are evenly spaced. No orders at the base; level 1 is closest to base, then level 2, 3, …  
**Order placement:** When EA starts, orders are placed **from level closest to base outward** (level 1 first, then 2, 3, …). Buy Stop at levels **above the base line and above current price**; Sell Stop at levels **below the base line and below current price**. At most one AA, one BB, one CC per level (per enabled type); the EA supplements missing orders.

---

## 2. ORDERS

Input order: **Common** (Magic & Comment) first, then **AA**, **BB**, **CC** (each with Enable, lot, TP, balance settings).

### 2.1 Common (Magic & Comment)

- **Magic Number** – AA = this; BB = Magic + 1; CC = Magic + 2.
- **Order comment** – Same comment for all orders (e.g. "EA Grid").
- **Cancel same-side when no opposite** – When price is at least N levels from base and there are **no positions on the opposite side**, delete all **same-side** pending orders and do not place new same-side pendings.
- **Cancel same-side min levels from base** – Minimum grid levels (price distance from base) to apply the above (e.g. 5 = only when price ≥ 5 levels from base).

### 2.2 AA (settings)

- **Enable AA** – Turn AA (Buy Stop + Sell Stop) on/off.
- **Lot level 1** – Lot size for the first level.
- **Fixed / Geometric** – Lot scaling: Fixed or Geometric (multiplier per level).
- **Lot multiplier** – For Geometric: multiplier for level 2+.
- **Max lot** – Maximum lot per order (0 = no limit).
- **Take profit (pips)** – TP in pips (0 = off).
- **Enable Balance** – Use pool to close losing AA.
- **Threshold (USD)** – Close when (pool + loss) ≥ this and ≥ 0.
- **Cooldown (sec)** – Wait time after closing (0 = none).

**Balance rules (AA + BB + CC)**

- **Rule 1 – Opposite side:** Only close **losing** positions on the **opposite side of the base line** from current price: price above base → close Sells (below base); price below base → close Buys (above base).
- **Lock Buy / Lock Sell (avoid wrong close):** When **price is above base**, **Buy positions are locked** – balance must **not** close any Buy. When **price is below base**, **Sell positions are locked** – balance must **not** close any Sell. This prevents the balance logic from closing the wrong side.
- **Rule 2 – Farthest first:** Close losing orders **farthest from base first**, then closer. When same level: **AA → BB → CC**.
- Each type (AA, BB, CC) uses its **own threshold** when checking (Pool + loss) ≥ threshold. Shared pool; **current price** must be **at least 5 grid levels** from base; cooldown after closing.
- **If pool is insufficient** for full close: EA **partially closes** (lot proportional to spendable $). Balance closes (full or partial) are sent with deal comment **"Balance order"**.

### 2.3 BB (settings)

- Same structure as AA: Enable, lot, Fixed/Geometric, multiplier, max lot, Take profit, Enable Balance, Threshold (USD), Cooldown (sec). Balance uses unified logic (farthest first, same level: AA → BB → CC).

### 2.4 CC (settings)

- Same logic as BB, separate parameters: Enable, lot, Fixed/Geometric, multiplier, max lot, Take profit, Enable Balance, Threshold (USD), Cooldown (sec). Balance uses unified logic (farthest first, same level: AA → BB → CC).

---

## 3. SESSION: Trailing profit

- **Enable trailing** – When open profit (current session) ≥ threshold (USD), cancel all pending and start trailing SL (Buy/Sell) on open positions.
- **Start trailing when open profit ≥ (USD)** – Threshold to enter trailing mode.
- **Lock: close all when profit drops this % from peak** – If profit falls by this % from the session peak, close all and reset (new session).
- **Pips: SL distance / trailing step** – SL distance from price and step for trailing updates.

Only positions opened in the **current session** are used for trailing. Notifications are sent on reset.

**Chart drawing:**
- **Thin base line** – Horizontal line at base price (updates on EA reset).
- **Vertical line** – Session start time (when EA started or last reset). Updates each time EA resets.

---

## 4. CAPITAL % SCALING

- **Scale by capital growth** – When enabled, **lot** (AA/BB/CC) and **trailing threshold (USD)** are scaled by account growth % vs **base capital**.
- **Base capital (USD)** – 0 = balance when EA attached; > 0 = use this value. Base is used for lot/TP/SL/Trailing scaling only. Updated on EA reset (session start).
- **x% (max 100)** – Scaling factor. Formula: `multiplier = 1 + growth × (x/100)`. TP/SL (pips) use input values and are not scaled.
- **Max increase % for lot/functions** – Cap on multiplier increase (0 = no limit). E.g. 100 = lot/functions can increase max 100%, multiplier capped at 2.0.

**Note:** Base capital is used only for scaling (lot, TP, SL, trailing). The notification "Initial balance at EA startup" and "Change vs initial capital at EA startup" use **balance when EA was first attached** (never reset), not base capital.

---

## 5. NOTIFICATIONS

- **Send notification when EA resets or stops** – Push notification on full reset or EA stop. Content includes reason, chart, balance, **Change vs initial capital at EA startup** (%), max drawdown, max lot / total open. Reset message includes **Locked profit (saved, cumulative): X.XX USD** when lock profit is used.
- **Initial balance at EA startup** – Balance when EA was first attached. **Never reset** (stays the same even after EA resets).
- **Change vs initial capital at EA startup** – % = (current balance − initial at attach) / initial at attach × 100. Uses balance when EA was first attached, not base capital.

**Telegram:**
- **Enable Telegram** – Send notifications to a Telegram group via Bot.
- **Bot Token** – Token from @BotFather.
- **Chat ID** – Group ID (negative number, e.g. -1001234567890).
- **Note:** Add `https://api.telegram.org` to Tools → Options → Expert Advisors → Allow WebRequest for listed URL.

**Example (MT5 push notification & Telegram – same content):**

```
EA RESET
Chart: GBPUSD
Reason: EA stopped (reason: 1)

--- SETTINGS ---
Initial balance at EA startup: 50000.00 USD
Base capital (USD): 50000.00
Capital scale %: 50.0%

--- CURRENT STATUS ---
Current balance: 24800.00 USD
Change vs initial capital at EA startup: -50.40%
Max drawdown: 320.00 USD
Lowest balance (since attach): 24680.00 USD
Locked profit (saved, cumulative): 125.50 USD

--- FREE EA ---
Free MT5 automated trading EA.
Just register an account using this link: https://one.exnessonelink.com/a/iu0hffnbzb
After registering, send me your account ID to receive the EA.
```

---

## 6. LOCK PROFIT (Save %)

**Meaning:** Lock profit = reserve a **percentage** of each **profitable TP close**. That locked amount is **cumulative across sessions and never reset**. The locked $ is **not used for balance** (floor protects it).

When enabled:

- On each **profitable** close that is a **Take Profit** (TP), a **percentage** of that profit (e.g. 10%) is **locked** into a reserve. **Locked profit is cumulative over all sessions and is never reset** (e.g. on EA reset or new session).
- **Deal P/L** = Profit + Swap + Commission. Locked = deal P/L × (Lock % / 100). Only the **remainder** is added to the **current session** balance pool.
- **Pool** = **TP closes in current session only** minus **lock taken in current session**. This pool is **shared** for balancing AA, BB, and CC. The **locked $ (savings)** is **not** used for balance.
- **Floor:** When balancing, a losing order is closed only if **account balance after close ≥ session start balance + locked profit reserve**. So the cumulative locked amount is never spent.

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
- **Pool** = **TP in current session** minus **lock in current session**. Locked $ is cumulative and never reset; it is not used for balance. One shared pool for AA, BB, and CC balance.
- **Balance rule:** Balance runs only when **current price** is at least **5 grid levels** from the base line. Only close **losing** positions on the **opposite side of the base** (price above base → close Sells below base; price below base → close Buys above base). **Lock:** When price above base, **Buy is locked** (do not close Buy); when price below base, **Sell is locked** (do not close Sell). Close a loser only when:
  1. **(Pool + that loss) ≥ threshold** and **≥ 0** (pool covers the loss).
  2. **Account balance after close ≥ session start balance + locked profit reserve** (floor).
- **Order of closing:** Collect AA, BB, CC (only opposite-side losers, respecting Buy/Sell lock); **farthest from base line first**. When same level: **AA → BB → CC**. Close all at farthest level, then next. If pool is not enough to close that position fully, **partial close** (lot proportional to spendable $); if below min lot, wait until pool increases. Balance closes use deal comment **"Balance order"**.
- **Remaining pool** is decreased when a losing order is closed (unified order: farthest first, same level then AA → BB → CC).
- **Open position P/L** = Profit + Swap. Only positions opened at or after session start are considered for balance and trailing.

---

## Balance method – Example

**Setup:** Base = 1000. Grid distance = 100 pips. Levels above base: 1010, 1020, 1030, …; below base: 990, 980, 970, …

**Case 1 – Price above base, close Sells below base (AA, BB, CC unified)**

- Current price = **1200** (≥ 5 levels from base) → balance is allowed.
- Open positions: Buy 1010 (+profit), **Sell CC 940 (−120 USD)**, **Sell BB 970 (−80 USD)**, **Sell AA 990 (−50 USD)**.
- **Opposite side + lock:** Price above base → close only **Sells below base**; **Buy is locked** (balance must not close any Buy).
- **Order of closing (farthest first):** Close **Sell CC 940** first, then Sell BB 970, then Sell AA 990. Deals get comment **"Balance order"**.

**Case 2 – Price below base, close Buys above base**

- Current price = **850** (≥ 5 levels from base) → balance is allowed.
- Open positions: Sell 980 (+profit), **Buy 1050 (−80 USD)**, **Buy 1100 (−150 USD)**.
- **Opposite side + lock:** Price below base → close only **Buys above base** (1050, 1100); **Sell is locked** (balance must not close any Sell).
- **Order of closing:** Farthest from base first → close **Buy 1100** (−150 USD) first. Deals get comment **"Balance order"**.

**Case 3 – Pool insufficient, partial close**

- Pool = 60 USD. Farthest losing position to close: Sell 940, loss 120 USD.
- Pool cannot cover full close → EA **partially closes** Sell 940: lot closed proportional to 60/120 = 50% of lot.
- Realized loss = 60 USD; remaining pool = 0. Remaining position waits for pool to grow before further close.

**Case 4 – Same farthest level: priority AA → BB → CC**

- Orders at same level 940: **Sell AA 940**, **Sell BB 940**, **Sell CC 940**.
- **Order of closing:** AA first → BB → CC last. When same level, priority by type.

**Case 5 – Price near base, no balance**

- Current price = **1005** (fewer than 5 levels from base) → **balance does not run**, even if there are losing positions.

---

## File

- **AdvancedGridTrading.mq5** – Single EA file; attach to chart in MetaTrader 5.

---

## Version

2.06 – Advanced Grid Trading EA (Pro). AA, BB, CC; order placement from closest to base outward; balance rules (opposite side, farthest first; **lock Buy when price above base, lock Sell when price below base** to avoid closing wrong side); balance closes with deal comment **"Balance order"**; pool = **TP in current session minus lock in current session**; **locked $ cumulative across sessions, never reset, not used for balance**; Cancel same-side pending when no opposite (optional, configurable levels); at most one order per type per level; shared pool; unified balance (farthest first, same level: AA → BB → CC, partial close when pool insufficient); Max scale increase %; chart: thin base line + vertical session start line; trailing; Telegram notifications; Initial balance at EA startup never reset.
