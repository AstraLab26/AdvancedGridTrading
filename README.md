# Advanced Grid Trading EA

MetaTrader 5 Expert Advisor for grid trading with four independent order types (AA, BB, CC, **DD**), trailing profit, session-based balance logic (AA/BB/CC only), capital scaling, lock profit (save %), and notifications.

---

## Overview

- **Grid:** Base price at attach, evenly spaced levels (pips), max levels per side. **AA/BB/CC:** **Buy Stop** at levels **above the base line and above current price**; **Sell Stop** at levels **below the base line and below current price**. **DD:** **Sell Limit** at levels **above base** (price drops to hit); **Buy Limit** at levels **below base** (price rises to hit). Missing orders (per enabled type) at a level are added by the EA.
- **AA, BB, CC & DD:** Separate lot, Fixed/Geometric, multiplier, max lot, TP, and magic for each. **DD has no balance mode** (never closed for balance). **Pool:** TP from **AA + BB + CC + DD** (after lock) feeds the balance pool used **only to close losing AA/BB/CC**; DD TP adds to pool but DD positions are never balanced. Magic: AA = Magic Number, BB = +1, CC = +2, **DD = +3**. All orders use one comment (e.g. "EA Grid").
- **Session:** Starts when the EA is attached or auto-reset. **Only TP closes** contribute to the balance pool; SL/manual do not. **Pool** = TP in session − lock in session. **Locked $** is cumulative and never reset; not used for balance.

---

## 1. GRID

| Parameter | Description |
|-----------|-------------|
| **Grid distance (pips)** | Distance between adjacent grid levels. Default: **2000**. |
| **Max grid levels per side** | Maximum levels above and below the base line. Default: **40**. |

---

## 2. ORDERS

### 2.1 Common (Magic & Comment)

- **Magic Number** – AA = this; BB = +1; CC = +2; **DD = +3**.
- **Order comment** – Same for all orders.

### 2.2 AA / 2.3 BB / 2.4 CC

- **AA, BB, CC** use **Buy Stop** (above base, above price) and **Sell Stop** (below base, below price). Enable, lot, Fixed/Geometric, multiplier, max lot, TP, **Enable Balance** (20 USD threshold, 300 s cooldown; prepare at 3 levels, execute at 5 levels). Unified balance: farthest first; same level **AA → BB → CC**. See balance rules below.

### 2.5 DD (settings)

- **Enable DD** – Sell Limit above base + Buy Limit below base. **No balance** (DD is never closed by balance logic).
- **Lot / TP / scale** – Same scaling idea as AA/BB/CC when **Scale by account growth** is on (lot uses session multiplier).
- **Lock profit** – Same % lock applies to DD TP closes; remainder goes to pool **for balancing AA/BB/CC only**.

---

## 3. SESSION: Trailing profit

- **Enable trailing** – When open profit ≥ threshold (USD), cancel pending and trail SL on open positions.
- **Start trailing when open profit ≥ (USD)** – Default: **200**.
- **When profit drops** – Lock profit (close all + reset) or Return to initial.
- **Point A / Trailing step** – Defaults **1500** / **1000** pips.
- **Breakeven reset** – Optional; default off.

---

## 4. CAPITAL % SCALING

- **Scale by capital growth** – Lot (AA/BB/CC/**DD**) and trailing threshold scale by growth vs base capital.
- **Base capital (USD)** – 0 = balance at attach; >0 = fixed value. Default in code: **100000** (change in inputs as needed).
- **x% / Max increase %** – Scaling caps (e.g. 50%, max 100%).

---

## 5. NOTIFICATIONS

- **Reset / stop** – Push (+ optional Telegram). Includes chart, reason, **Price at reset** (Bid), settings, balance, change %, drawdown, locked profit, etc.
- **Telegram** – Enable + Bot token + Chat ID; allow `https://api.telegram.org` in WebRequest.

Example snippet:

```
EA RESET
Chart: GBPUSD
Reason: ...
Price at reset: 1.26543
--- SETTINGS ---
...
```

---

## 6. LOCK PROFIT (Save %)

- **Lock** – % of each **profitable TP close** reserved (cumulative, never reset). Applies to **AA, BB, CC, DD** TP closes. Remainder goes to session pool.
- **Pool** – TP in session − lock in session; **DD TP increases pool** but only **AA/BB/CC** are closed by balance.

---

## Balance method (AA + BB + CC only)

- Pool shared; prepare at 3 levels; execute at 5 levels; 20 USD / 300 s; opposite-side losers only; lock Buy above base, lock Sell below base; partial close when pool insufficient; deal comment **"Balance order"**.

---

## File

- **AdvancedGridTrading.mq5** – Single EA file for MetaTrader 5.

---

## Version

**2.07** – Advanced Grid Trading EA (Pro). AA, BB, CC (Buy/Sell Stop); **DD** (Sell Limit above base, Buy Limit below base, no balance); pool = TP (AA+BB+CC+DD) after lock; balance closes **only AA/BB/CC**; trailing; notifications including **Price at reset**.
