# Advanced Grid Trading EA (MetaTrader 5)

**Version 2.00** — Pro edition with per-order lot, scale by capital, trailing profit, and session management.

An Expert Advisor that places grid orders around a base price line. When attached to a chart, the current BID price becomes the **base line**. The EA creates grid levels above and below, placing pending orders (Buy Limit, Buy Stop, Sell Limit, Sell Stop) at each level. It auto-refills orders when closed, supports session reset by profit/loss, trailing profit lock, and scales lot/TP/SL by account growth %.

---

## Grid Structure

- **Base line**: BID price when EA is attached (or after each reset).
- **Level 1**: Half grid step from base (X/2 pips).
- **Level 2, 3, …**: Each level spaced by **X pips** (GridDistancePips).
- **Levels per side**: `MaxGridLevels` above and below base; no orders at the base line itself.
- **Example** (MaxGridLevels = 1): 1 level above + 1 below; each level can have 1 Buy + 1 Sell (pending or open).

---

## Main Features

- **Even grid spacing**: All levels and refills use the same grid step.
- **Four order types**: Buy Limit, Buy Stop, Sell Limit, Sell Stop — enable/disable each independently.
- **Per-order lot**: Individual initial lot (level 1) for each order type.
- **Per-order TP**: Individual Take Profit (pips, 0=off) for each order type.
- **Stop placement rules**: Buy Stop only above base line; Sell Stop only below base line (configurable).
- **Lot scaling**: Fixed or Geometric per order type; level 2+ uses multiplier.
- **Auto refill**: Replaces closed orders at correct grid levels.
- **Snap to grid**: Adjusts pending orders that drift from grid levels.
- **Session reset by profit**: When session profit ≥ target (USD) → Reset or Stop EA.
- **Session SL (total loss)**: When session total ≤ -threshold (USD) → Reset or Stop EA.
- **Order balance reset**: When total open lot ≥ threshold and session profit ≥ min (USD) → Reset EA.
- **Trailing profit**: When profit ≥ threshold → cancel pendings, trail SL on open positions; lock profit when it drops by % from peak.
- **Trailing threshold modes**: Session (open + closed) or Open only (only open positions).
- **Scale by account %**: Lot, TP, SL, trailing threshold scale by capital growth; base capital can be manual or balance at attach.
- **Stop EA mode**: Close all, cancel pendings, no new orders.

---

## Input Parameters

### 1. GRID
| Parameter | Description |
|-----------|-------------|
| Grid distance (pips) | Spacing between grid levels. |
| Number of grid levels per side | Levels above and below base line. |
| Auto refill orders when closed | Enable automatic refill when orders are closed. |

### 2. ORDERS

#### 2.1 BUY LIMIT / 2.2 BUY STOP / 2.3 SELL LIMIT / 2.4 SELL STOP
| Parameter | Description |
|-----------|-------------|
| Enable | Enable/disable this order type. |
| Initial lot (level 1) | Lot size for level 1; level 2+ uses multiplier if Geometric. |
| Only place above/below base line | (Buy Stop / Sell Stop only) Restrict placement to one side of base. |
| Take Profit (pips, 0=off) | Per-order TP; 0 = no TP. |
| Lot mode: Fixed / Geometric | Fixed = same lot all levels; Geometric = level 2+ = base × multiplier^(level-1). |
| Lot multiplier per level | Geometric multiplier. |

#### 2.5 COMMON
| Parameter | Description |
|-----------|-------------|
| Magic Number | EA identifier for orders. |
| Order comment | Comment on orders. |

### 3. SESSION: Reset by Profit
| Parameter | Description |
|-----------|-------------|
| Enable reset when session profit reaches target | Enable session reset by profit. |
| Session profit to trigger reset (USD) | Target profit (USD) to trigger. |
| On target: Reset EA / Stop EA | Reset (new session) or Stop (no new orders). |

### 4. SESSION: SL (Total Loss)
| Parameter | Description |
|-----------|-------------|
| Enable session SL when total session loss hits level | Enable session SL. |
| Session loss to trigger SL (USD) | Trigger when total ≤ -this value. |
| On SL: Reset EA / Stop EA | Reset or Stop. |

### 5. SESSION: Order Balance
| Parameter | Description |
|-----------|-------------|
| Enable | Reset when total lot ≥ threshold and session profit ≥ min. |
| Total open lot to trigger balance reset | Lot threshold. |
| Session profit must be >= this (USD) to allow reset | Min profit (USD). |

### 6. SESSION: Trailing Profit
| Parameter | Description |
|-----------|-------------|
| Enable trailing | Cancel pendings, trail SL when profit ≥ threshold. |
| Threshold mode: Session / Open only | Session = open + closed; Open only = only open positions. |
| Start trailing when profit >= (USD) | Profit threshold (USD). |
| Lock: close all when profit drops this % from peak | Lock % from peak. |
| Pips: SL distance from price | SL distance for Buy A / Sell A. |
| Pips: step to move SL | Step to update SL. |

### 7. SCALE BY ACCOUNT %
| Parameter | Description |
|-----------|-------------|
| Enable | Scale lot, TP, SL, trailing by x% account growth. |
| Base capital (USD) | 0 = use balance at EA attach; >0 = use this value as base. |
| x% (max 100) | Capital +100% vs base → params scale by x%. E.g. 50% = half of growth. |

### 8. NOTIFICATIONS
| Parameter | Description |
|-----------|-------------|
| Send notification when EA resets or stops | Enable push/email notifications. |

---

## Scale Formula

- **Capital growth**: `growth = (currentBalance - baseCapital) / baseCapital`
- **Multiplier**: `sessionMultiplier = 1.0 + growth × (AccountGrowthScalePct / 100)`
- **Example**: Base 1000, current 1500, setting 50% → growth 50%, multiplier 1.25 (params +25%)
- **Updated on**: Each EA reset (trailing lock, session SL, session TP, order balance)

---

## Installation & Usage (MT5)

1. Copy `AdvancedGridTrading.mq5` to `MQL5/Experts/` (MT5 Data Folder).
2. Open **MetaEditor** → open file → **Compile** (F7).
3. In MT5: **Navigator** → Expert Advisors → drag EA onto chart.
4. Enable **Algo Trading** for live trading.
5. Adjust **Input** in the EA properties dialog.

---

## Strategy Tester

1. Open **Strategy Tester**, select Expert `AdvancedGridTrading`.
2. Choose symbol, timeframe, test period.
3. Run and check **Journal/Experts** for logs.

---

## Notes

- **Base line** is fixed until reset; after reset, current price becomes new base.
- **Session** = from EA attach or last reset; total = closed profit + open floating.
- **Base capital** for scaling: manual input or balance at attach; never changes.
- **Pips**: EA uses `pnt × 10` for 1 pip (5/3 digit pairs); verify for other symbols.

---

## Files

- `AdvancedGridTrading.mq5` — EA source code.
- `README.md` — This documentation.
