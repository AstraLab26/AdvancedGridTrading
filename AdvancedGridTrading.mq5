//+------------------------------------------------------------------+
//|                                         AdvancedGridTrading.mq5   |
//|              Advanced Grid Trading EA - Pro edition              |
//+------------------------------------------------------------------+
#property copyright "Advanced Grid EA"
#property version   "2.01"
#property description "Advanced Grid Trading EA: per-order lot, scale by capital, trailing profit, session reset"

#include <Trade\Trade.mqh>

//--- Lot scale: 0=Fixed, 2=Geometric. Level 1 = LotSize; level 2+ = multiplier.
enum ENUM_LOT_SCALE { LOT_FIXED = 0, LOT_GEOMETRIC = 2 };

//+------------------------------------------------------------------+
//| 1. GRID                                                           |
//+------------------------------------------------------------------+
input group "=== 1. GRID ==="
input double GridDistancePips = 2000.0;         // Grid distance (pips)
input int MaxGridLevels = 30;                   // Max grid levels per side (above/below base line)

//+------------------------------------------------------------------+
//| 2. ORDERS                                                          |
//+------------------------------------------------------------------+
input group "=== 2. ORDERS ==="

input group "--- 2.1 Common (Magic & Comment) ---"
input int MagicNumber = 123456;                // Magic Number (AA=this, BB=this+1, CC=this+2)
input string CommentOrder = "EA Grid";          // Order comment (same for all)

input group "--- 2.2 AA (settings) ---"
input bool EnableAA = true;                     // Enable AA (Buy Stop + Sell Stop)
input double LotSizeAA = 0.01;                  // AA: Lot size level 1
input ENUM_LOT_SCALE AALotScale = LOT_GEOMETRIC; // AA: Fixed / Geometric
input double LotMultAA = 1.3;                   // AA: Lot multiplier for level 2+ (Geometric)
input double MaxLotAA = 2.0;                    // AA: Max lot per order (0=no limit)
input double TakeProfitPipsAA = 0.0;           // AA: Take profit (pips; 0=off)
input bool EnableBalanceAAByBB = true;         // AA: Balance when session TP $ minus lock % is enough to cover the losing AA (pool + loss >= 0 and >= threshold)
input double BalanceAAByBBThresholdUSD = 20.0;  // AA: Threshold USD. Close that AA when (pool + 1 AA loss) >= this value and >= 0
input int BalanceAAByBBCooldownSec = 300;     // AA: Cooldown (seconds) after closing; 0=none. Price must be 5 levels from base

input group "--- 2.3 BB (settings) ---"
input bool EnableBB = true;                     // Enable BB (Buy Stop + Sell Stop)
input double LotSizeBB = 0.05;                  // BB: Lot size level 1
input ENUM_LOT_SCALE BBLotScale = LOT_GEOMETRIC; // BB: Fixed / Geometric
input double LotMultBB = 1.1;                   // BB: Lot multiplier for level 2+ (Geometric)
input double MaxLotBB = 2.0;                    // BB: Max lot per order (0=no limit)
input double TakeProfitPipsBB = 2000.0;         // BB: Take profit (pips; 0=off)
input bool EnableBalanceBB = true;              // BB: Balance when session TP $ minus lock % is enough to cover the losing BB (pool + loss >= 0 and >= threshold)
input double BalanceBBThresholdUSD = 20.0;      // BB: Threshold USD. Close BB when (pool + 1 BB loss) >= this and >= 0
input int BalanceBBCooldownSec = 300;           // BB: Cooldown (seconds) after closing BB loser; 0=none

input group "--- 2.4 CC (settings) ---"
input bool EnableCC = true;                      // Enable CC (Buy Stop + Sell Stop)
input double LotSizeCC = 0.1;                    // CC: Lot size level 1
input ENUM_LOT_SCALE CCLotScale = LOT_FIXED;     // CC: Fixed / Geometric
input double LotMultCC = 1.5;                    // CC: Lot multiplier for level 2+ (Geometric)
input double MaxLotCC = 2.0;                     // CC: Max lot per order (0=no limit)
input double TakeProfitPipsCC = 2000.0;          // CC: Take profit (pips; 0=off)
input bool EnableBalanceCC = true;               // CC: Balance when session TP $ minus lock % is enough to cover the losing CC (pool + loss >= 0 and >= threshold)
input double BalanceCCThresholdUSD = 20.0;       // CC: Threshold USD. Close CC when (pool + 1 CC loss) >= this value and >= 0
input int BalanceCCCooldownSec = 300;            // CC: Cooldown (seconds) after closing CC loser; 0=none

//+------------------------------------------------------------------+
//| 3. SESSION: Trailing profit (open orders only)                    |
//+------------------------------------------------------------------+
input group "=== 3. SESSION: Trailing profit ==="
input bool EnableTrailingTotalProfit = true;    // Enable trailing: cancel pending, move SL when open profit >= threshold
input double TrailingThresholdUSD = 200.0;     // Start trailing when open profit >= (USD)
input double TrailingLockStepPct = 15.0;       // Lock: close all when profit drops this % from peak
input double GongLaiPips = 1500.0;             // Pips: SL distance from price (Buy A / Sell A)
input double GongLaiStepPips = 500.0;           // Pips: trailing step (update every step)

//+------------------------------------------------------------------+
//| 4. CAPITAL % SCALING                                               |
//+------------------------------------------------------------------+
input group "=== 4. CAPITAL % SCALING ==="
input bool EnableScaleByAccountGrowth = true;   // Scale lot, TP, SL, trailing by % capital growth
input double BaseCapitalUSD = 50000.0;         // Base capital (USD): 0=balance when EA attached; >0=use this value
input double AccountGrowthScalePct = 50.0;     // x% (max 100): capital +100% vs base -> multiply by x%

//+------------------------------------------------------------------+
//| 5. NOTIFICATIONS                                                    |
//+------------------------------------------------------------------+
input group "=== 5. NOTIFICATIONS ==="
input bool EnableResetNotification = true;     // Send notification when EA resets or stops

input group "=== 6. LOCK PROFIT (Save %) ==="
input bool EnableLockProfit = true;            // Lock profit: reserve X% of each profitable TP close; reserved amount is not used for AA/BB/CC balance pool
input double LockProfitPct = 25.0;             // Lock this % of each profitable close (e.g. 25 = reserve 25 USD from 100 USD profit); 0-100

//--- Global variables
CTrade trade;
double pnt;
int dgt;
double basePrice;                               // Base price (base line)
double gridLevels[];                            // Array of level prices (evenly spaced by GridDistancePips)
double gridStep;                                // One grid step (price) = GridDistancePips, used for tolerance/snap
double sessionClosedProfit = 0.0;               // Session closed P/L total (AA+BB+CC đóng TP, sau lock). Reset on EA reset. Pool chung cho cân bằng AA/BB/CC.
double sessionClosedProfitBB = 0.0;             // BB closed P/L in session (after lock). Dùng nội bộ khi cần.
double sessionClosedProfitCC = 0.0;             // CC closed P/L in session (after lock). Dùng nội bộ khi cần.
double sessionClosedProfitRemaining = 0.0;      // Pool còn lại trong tick (sau khi đóng lệnh lỗ AA/BB/CC). Mỗi tick = sessionClosedProfit.
datetime lastResetTime = 0;                     // Last reset time (avoid double-count from orders just closed on reset)
bool eaStoppedByTarget = false;                 // true = EA stopped placing new orders (Stop mode)
double balanceGoc = 0.0;                       // Base capital for scaling (BaseCapitalUSD or balance at attach)
double attachBalance = 0.0;                    // Vốn lúc EA khởi động: cập nhật mỗi lần EA khởi động hoặc reset (panel "Vốn ban đầu")
double sessionMultiplier = 1.0;                // Lot and TP multiplier by % growth vs balanceGoc (1.0 = no change)
double sessionPeakProfit = 0.0;                // Session profit peak (for trailing profit lock)
bool gongLaiMode = false;                      // true = trailing threshold reached, pendings cancelled, only trail SL on open positions
double lastBuyTrailPrice = 0.0;                // Last price when SL Buy was updated (trailing step)
double lastSellTrailPrice = 0.0;               // Last price when SL Sell was updated (trailing step)
double sessionPeakBalance = 0.0;               // Highest balance in session (for notification)
double sessionMinBalance = 0.0;                // Lowest balance in session (max drawdown)
double globalPeakBalance = 0.0;                // Highest balance since EA attach (not reset)
double globalMinBalance = 0.0;                 // Lowest balance since EA attach = equity at max drawdown (not reset)
double sessionMaxSingleLot = 0.0;              // Largest single position lot in session
double sessionTotalLotAtMaxLot = 0.0;         // Total open lot when that max single lot occurred
double globalMaxSingleLot = 0.0;              // Largest single lot since EA attach (not reset)
double globalTotalLotAtMaxLot = 0.0;          // Total open lot at that time since EA attach (not reset)
datetime sessionStartTime = 0;                // Phiên hiện tại: bắt đầu khi gắn EA hoặc EA reset. Chỉ tính P/L và lệnh từ thời điểm này.
double sessionStartBalance = 0.0;             // Balance at session start (for info panel and session %)
int MagicAA = 0;                              // AA orders magic (set in OnInit)
int MagicBB = 0;                              // BB orders magic (MagicNumber+1)
int MagicCC = 0;                              // CC orders magic (MagicNumber+2)
datetime lastBalanceBBCloseTime = 0;          // Last time we closed losing BB (for cooldown)
datetime lastBalanceCCCloseTime = 0;          // Last time we closed losing CC (for cooldown)
datetime lastBalanceAAByBBCloseTime = 0;     // Last time we closed AA by BB balance (for cooldown)
double lockedProfitReserve = 0.0;            // Locked profit (X% of each profitable close); excluded from AA/BB/CC balance and trailing

//+------------------------------------------------------------------+
//| True if magic belongs to this EA (AA, BB or CC)                    |
//+------------------------------------------------------------------+
bool IsOurMagic(long magic)
{
   return (magic == MagicAA || magic == MagicBB || magic == MagicCC);
}

//+------------------------------------------------------------------+
//| Swap helpers for sort by distance                                |
//+------------------------------------------------------------------+
void SwapDouble(double &a, double &b) { double t = a; a = b; b = t; }
void SwapULong(ulong &a, ulong &b) { ulong t = a; a = b; b = t; }

//+------------------------------------------------------------------+
//| Position P/L = profit + swap (phí qua đêm). Commission (hoa hồng) chỉ có khi lệnh đóng (trong DEAL). |
//+------------------------------------------------------------------+
double GetPositionPnL(ulong ticket)
{
   if(ticket == 0 || !PositionSelectByTicket(ticket)) return 0.0;
   return PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   MagicAA = MagicNumber;
   MagicBB = MagicNumber + 1;
   MagicCC = MagicNumber + 2;
   trade.SetExpertMagicNumber(MagicAA);
   dgt = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   pnt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   basePrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   sessionClosedProfit = 0.0;
   sessionClosedProfitBB = 0.0;
   sessionClosedProfitCC = 0.0;
   lastBalanceBBCloseTime = 0;
   lastBalanceCCCloseTime = 0;
   lastBalanceAAByBBCloseTime = 0;
   lastResetTime = 0;
   eaStoppedByTarget = false;
   balanceGoc = (BaseCapitalUSD > 0) ? BaseCapitalUSD : AccountInfoDouble(ACCOUNT_BALANCE);
   attachBalance = AccountInfoDouble(ACCOUNT_BALANCE);   // Vốn ban đầu: balance when EA is first added (for panel only)
   sessionMultiplier = 1.0;
   UpdateSessionMultiplierFromAccountGrowth();
   sessionPeakProfit = 0.0;
   gongLaiMode = false;
   lastBuyTrailPrice = 0.0;
   lastSellTrailPrice = 0.0;
   double currentBal = AccountInfoDouble(ACCOUNT_BALANCE);
   sessionPeakBalance = currentBal;
   sessionMinBalance = currentBal;
   globalPeakBalance = currentBal;
   globalMinBalance = currentBal;
   sessionMaxSingleLot = 0.0;
   sessionTotalLotAtMaxLot = 0.0;
   
   InitializeGridLevels();
   if(EnableResetNotification)
      SendResetNotification("EA started");
   Print("========================================");
   Print("Advanced Grid Trading EA started. Session profit: 0 USD (open + closed from now)");
   Print("Symbol: ", _Symbol, " | Base: ", basePrice, " | Grid: ", GridDistancePips, " pips | Levels: ", ArraySize(gridLevels));
   if(EnableTrailingTotalProfit)
      Print("Trailing: open orders only. Start when profit >= ", TrailingThresholdUSD, " USD, lock when down ", TrailingLockStepPct, "% from peak.");
   if(EnableAA && EnableBalanceAAByBB)
      Print("Balance AA by BB: close 1 losing AA when (BB closed + that AA loss) >= ", BalanceAAByBBThresholdUSD, " USD. Session only. Price 5 levels. Cooldown ", BalanceAAByBBCooldownSec, "s.");
   if(EnableBB && EnableBalanceBB)
      Print("Balance BB: when (BB closed + BB open opposite side) >= ", BalanceBBThresholdUSD, " USD, close losing BB on that side.");
   if(EnableCC && EnableBalanceCC)
      Print("Balance CC: when (CC closed + CC open opposite side) >= ", BalanceCCThresholdUSD, " USD, close losing CC on that side.");
   if(EnableLockProfit && LockProfitPct > 0)
      Print("Lock profit: ", LockProfitPct, "% of each profitable close is reserved; this amount is not counted in AA/BB/CC balance logic.");
   if(EnableScaleByAccountGrowth)
      Print("Base capital = ", balanceGoc, " USD", BaseCapitalUSD > 0 ? " (manual)" : " (balance at attach)", ". Lot/TP/SL/Trailing x ", AccountGrowthScalePct, "% growth. mult=", sessionMultiplier);
   if(EnableAA)
      Print("AA (BuyStop+SellStop) L1,L2,L3: ", GetLotForLevel(ORDER_TYPE_BUY_STOP,1), ",", GetLotForLevel(ORDER_TYPE_BUY_STOP,2), ",", GetLotForLevel(ORDER_TYPE_BUY_STOP,3));
   if(EnableBB)
      Print("BB (BuyStop+SellStop) L1,L2,L3: ", GetLotForLevelBB(true,1), ",", GetLotForLevelBB(true,2), ",", GetLotForLevelBB(true,3));
   if(EnableCC)
      Print("CC (BuyStop+SellStop) L1,L2,L3: ", GetLotForLevelCC(true,1), ",", GetLotForLevelCC(true,2), ",", GetLotForLevelCC(true,3));
   Print("========================================");
   
   // On start place orders at grid levels
   ManageGridOrders();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   DeleteCapitalGrowthLabel();
   Print("Advanced Grid Trading EA stopped. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(eaStoppedByTarget)
      return;
   
   if(EnableResetNotification)
      UpdateSessionStatsForNotification();
   
   // Gồng lãi: chỉ tính lệnh đang mở của phiên hiện tại (mở sau sessionStartTime)
   double floating = 0.0;
   if(EnableTrailingTotalProfit)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0 || !IsOurMagic(PositionGetInteger(POSITION_MAGIC)) || PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;
         if(sessionStartTime > 0 && (datetime)PositionGetInteger(POSITION_TIME) < sessionStartTime)
            continue;   // Bỏ qua lệnh mở trước phiên hiện tại
         floating += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      }
   }
   double totalForTrailing = floating;
   double effectiveTrailingThreshold = (EnableScaleByAccountGrowth && TrailingThresholdUSD > 0) ? (TrailingThresholdUSD * sessionMultiplier) : TrailingThresholdUSD;
   
   if(EnableTrailingTotalProfit && TrailingThresholdUSD > 0 && TrailingLockStepPct > 0)
   {
      double effectiveLockStepUSD = effectiveTrailingThreshold * (MathMax(0.0, MathMin(100.0, TrailingLockStepPct)) / 100.0);
      if(totalForTrailing >= effectiveTrailingThreshold)
      {
         if(!gongLaiMode)
         {
            gongLaiMode = true;
            CancelAllPendingOrders();
            Print("Trailing: open profit ", totalForTrailing, " USD (>= ", effectiveTrailingThreshold, "). Pending orders cancelled, trailing SL started.");
         }
         if(totalForTrailing > sessionPeakProfit)
            sessionPeakProfit = totalForTrailing;
         if(totalForTrailing <= sessionPeakProfit - effectiveLockStepUSD)
         {
            double peak = sessionPeakProfit;
            CloseAllPositionsAndOrders();
            UpdateSessionMultiplierFromAccountGrowth();
            lastResetTime = TimeCurrent();
            sessionClosedProfit = 0.0;
            sessionClosedProfitBB = 0.0;
            sessionClosedProfitCC = 0.0;
            lastBalanceBBCloseTime = 0;
            lastBalanceCCCloseTime = 0;
            lastBalanceAAByBBCloseTime = 0;
         sessionPeakProfit = 0.0;
            gongLaiMode = false;
            lastBuyTrailPrice = 0.0;
            lastSellTrailPrice = 0.0;
            basePrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            InitializeGridLevels();
            Print("Trailing profit: lock (peak ", peak, " USD, current ", totalForTrailing, " USD). Reset EA, new session.");
            if(EnableResetNotification) { SendResetNotification("Trailing profit"); double b = AccountInfoDouble(ACCOUNT_BALANCE); sessionPeakBalance = b; sessionMinBalance = b; sessionMaxSingleLot = 0; sessionTotalLotAtMaxLot = 0; }
            return;
         }
      }
   }
   
   if(gongLaiMode)
   {
      int posCount = 0;   // Chỉ đếm lệnh phiên hiện tại
      for(int i = 0; i < PositionsTotal(); i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         if(!IsOurMagic(PositionGetInteger(POSITION_MAGIC)) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if(sessionStartTime > 0 && (datetime)PositionGetInteger(POSITION_TIME) < sessionStartTime) continue;
         posCount++;
      }
      if(posCount == 0)
      {
         CloseAllPositionsAndOrders();
         UpdateSessionMultiplierFromAccountGrowth();
         lastResetTime = TimeCurrent();
         gongLaiMode = false;
         lastBuyTrailPrice = 0.0;
         lastSellTrailPrice = 0.0;
         sessionClosedProfit = 0.0;
         sessionClosedProfitBB = 0.0;
         sessionClosedProfitCC = 0.0;
         lastBalanceBBCloseTime = 0;
         lastBalanceCCCloseTime = 0;
         lastBalanceAAByBBCloseTime = 0;
      sessionPeakProfit = 0.0;
         basePrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         InitializeGridLevels();
         Print("Trailing: all positions closed (SL hit). Reset session, new base = ", basePrice, ". Placing orders again.");
         if(EnableResetNotification) { SendResetNotification("Trailing profit"); double b = AccountInfoDouble(ACCOUNT_BALANCE); sessionPeakBalance = b; sessionMinBalance = b; sessionMaxSingleLot = 0; sessionTotalLotAtMaxLot = 0; }
      }
      else
         DoGongLaiTrailing();
   }
   
   // Pool chung AA+BB+CC đóng TP. Mỗi tick khởi tạo remaining = pool; mỗi lần đóng lệnh lỗ thì trừ remaining.
   sessionClosedProfitRemaining = sessionClosedProfit;
   if(EnableAA && EnableBalanceAAByBB)
      DoBalanceAAByBB();
   if(EnableBB && EnableBalanceBB)
      DoBalanceBB();
   if(EnableCC && EnableBalanceCC)
      DoBalanceCC();
   
   ManageGridOrders();
}

//+------------------------------------------------------------------+
//| On EA reset: update sessionMultiplier by account growth %         |
//| Vốn tăng 100%, cài hàm số tăng 50% -> EA reset, các hàm số tăng 50%    |
//| Formula: mult = 1 + growth × (AccountGrowthScalePct/100)         |
//| Vốn base = BaseCapitalUSD (nếu >0) hoặc balance khi gắn EA. So sánh với vốn hiện tại. |
//+------------------------------------------------------------------+
void UpdateSessionMultiplierFromAccountGrowth()
{
   if(balanceGoc <= 0)
      return;
   double newBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double growth = (newBalance - balanceGoc) / balanceGoc;
   if(EnableScaleByAccountGrowth && AccountGrowthScalePct > 0)
   {
      double pct = MathMin(100.0, MathMax(0.0, AccountGrowthScalePct));
      sessionMultiplier = 1.0 + growth * (pct / 100.0);
      if(sessionMultiplier < 0.1) sessionMultiplier = 0.1;
      if(sessionMultiplier > 10.0) sessionMultiplier = 10.0;
      Print("Reset: capital ", balanceGoc, " -> ", newBalance, " (+", (growth*100), "%). Scale ", pct, "% -> Lot/TP/SL/Trailing x ", sessionMultiplier);
   }
}

void DeleteCapitalGrowthLabel()
{
   DeleteBaseLine();
   DeleteSessionStartLine();
   ChartRedraw(ChartID());
}

//+------------------------------------------------------------------+
//| Draw thin base line (đường gốc) on chart at basePrice            |
//+------------------------------------------------------------------+
void DrawBaseLine()
{
   long chartId = ChartID();
   if(ObjectFind(chartId, "GridBaseLine") < 0)
      ObjectCreate(chartId, "GridBaseLine", OBJ_HLINE, 0, 0, basePrice);
   ObjectSetDouble(chartId, "GridBaseLine", OBJPROP_PRICE, basePrice);
   ObjectSetInteger(chartId, "GridBaseLine", OBJPROP_WIDTH, 1);
   ObjectSetInteger(chartId, "GridBaseLine", OBJPROP_COLOR, clrDodgerBlue);
   ObjectSetInteger(chartId, "GridBaseLine", OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(chartId, "GridBaseLine", OBJPROP_SELECTABLE, false);
   ObjectSetInteger(chartId, "GridBaseLine", OBJPROP_BACK, false);
   ChartRedraw(chartId);
}

void DeleteBaseLine()
{
   ObjectDelete(ChartID(), "GridBaseLine");
}

//+------------------------------------------------------------------+
//| Draw vertical line at session start (lúc EA bắt đầu vào lệnh chờ)  |
//+------------------------------------------------------------------+
void DrawSessionStartLine()
{
   if(sessionStartTime <= 0) return;
   long chartId = ChartID();
   if(ObjectFind(chartId, "GridSessionStart") < 0)
      ObjectCreate(chartId, "GridSessionStart", OBJ_VLINE, 0, sessionStartTime, 0);
   ObjectSetInteger(chartId, "GridSessionStart", OBJPROP_TIME, (long)sessionStartTime);
   ObjectSetInteger(chartId, "GridSessionStart", OBJPROP_WIDTH, 1);
   ObjectSetInteger(chartId, "GridSessionStart", OBJPROP_COLOR, clrSilver);
   ObjectSetInteger(chartId, "GridSessionStart", OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(chartId, "GridSessionStart", OBJPROP_SELECTABLE, false);
   ObjectSetInteger(chartId, "GridSessionStart", OBJPROP_BACK, false);
   ChartRedraw(chartId);
}

void DeleteSessionStartLine()
{
   ObjectDelete(ChartID(), "GridSessionStart");
}

//+------------------------------------------------------------------+
//| Update peak/min balance (session + global since EA attach) and max lot in session |
//+------------------------------------------------------------------+
void UpdateSessionStatsForNotification()
{
   double b = AccountInfoDouble(ACCOUNT_BALANCE);
   if(b > sessionPeakBalance) sessionPeakBalance = b;
   if(b < sessionMinBalance) sessionMinBalance = b;
   if(b > globalPeakBalance) globalPeakBalance = b;
   if(b < globalMinBalance) globalMinBalance = b;
   double totalLot = 0, maxLot = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(!IsOurMagic(PositionGetInteger(POSITION_MAGIC)) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      double vol = PositionGetDouble(POSITION_VOLUME);
      totalLot += vol;
      if(vol > maxLot) maxLot = vol;
   }
   if(maxLot > sessionMaxSingleLot)
   {
      sessionMaxSingleLot = maxLot;
      sessionTotalLotAtMaxLot = totalLot;
   }
   if(maxLot > globalMaxSingleLot)
   {
      globalMaxSingleLot = maxLot;
      globalTotalLotAtMaxLot = totalLot;
   }
}

//+------------------------------------------------------------------+
//| Send notification when EA resets or stops. Example:                |
//| EA RESET                                                           |
//| Chart: EURUSD                                                     |
//| Reason: Trailing profit                                           |
//| Initial balance: 10000.00 USD                                      |
//| Current balance: 10250.00 USD (+2.50%)                             |
//| Max drawdown/balance (since attach): 150.00 / 9850.00 USD          |
//| Locked profit (saved, cumulative): 45.20 USD                       |
//| Max single lot / total open (since attach): 0.05 / 0.25             |
//+------------------------------------------------------------------+
void SendResetNotification(const string reason)
{
   if(!EnableResetNotification) return;
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double pct = (balanceGoc > 0) ? ((bal - balanceGoc) / balanceGoc * 100.0) : 0;
   double maxLossUSD = globalPeakBalance - globalMinBalance;
   string msg = "EA RESET\n";
   msg += "Chart: " + _Symbol + "\n";
   msg += "Reason: " + reason + "\n";
   msg += "Initial balance: " + DoubleToString(balanceGoc, 2) + " USD\n";
   msg += "Current balance: " + DoubleToString(bal, 2) + " USD (" + (pct >= 0 ? "+" : "") + DoubleToString(pct, 2) + "%)\n";
   msg += "Max drawdown/balance (since attach): " + DoubleToString(maxLossUSD, 2) + " / " + DoubleToString(globalMinBalance, 2) + " USD\n";
   msg += "Locked profit (saved, cumulative): " + DoubleToString(lockedProfitReserve, 2) + " USD\n";
   msg += "Max single lot / total open (since attach): " + DoubleToString(globalMaxSingleLot, 2) + " / " + DoubleToString(globalTotalLotAtMaxLot, 2);
   SendNotification(msg);
}

//+------------------------------------------------------------------+
//| Close all positions and cancel pending orders (same Magic)        |
//+------------------------------------------------------------------+
void CloseAllPositionsAndOrders()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && IsOurMagic(PositionGetInteger(POSITION_MAGIC)))
         trade.PositionClose(ticket);
   }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0 && IsOurMagic(OrderGetInteger(ORDER_MAGIC)))
         trade.OrderDelete(ticket);
   }
}

//+------------------------------------------------------------------+
//| Cancel Buy Stop below base / Sell Stop above base when restriction is on |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Hủy Buy Stop dưới đường gốc, Sell Stop trên đường gốc (lệnh chỉ đặt BS trên base, SS dưới base). |
void CancelStopOrdersOutsideBaseZone()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket <= 0 || !IsOurMagic(OrderGetInteger(ORDER_MAGIC)) || OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      double price = OrderGetDouble(ORDER_PRICE_OPEN);
      if(ot == ORDER_TYPE_BUY_STOP && price < basePrice)
         trade.OrderDelete(ticket);
      else if(ot == ORDER_TYPE_SELL_STOP && price > basePrice)
         trade.OrderDelete(ticket);
   }
}

//+------------------------------------------------------------------+
//| Cancel all pending orders (do not close positions) - used when entering trailing mode |
//+------------------------------------------------------------------+
void CancelAllPendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0 && IsOurMagic(OrderGetInteger(ORDER_MAGIC)) && OrderGetString(ORDER_SYMBOL) == _Symbol)
         trade.OrderDelete(ticket);
   }
}

//+------------------------------------------------------------------+
//| Close all positions in loss (profit+swap < 0) - used after setting SL in trailing |
//+------------------------------------------------------------------+
void CloseNegativePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(!IsOurMagic(PositionGetInteger(POSITION_MAGIC)) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      double pr = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      if(pr < 0)
         trade.PositionClose(ticket);
   }
}

//+------------------------------------------------------------------+
//| After setting SL: price above base -> close all Sells; below base -> close all Buys. |
//| onlyCurrentSession: true = chỉ đóng lệnh mở trong phiên hiện tại (gồng lãi). |
//+------------------------------------------------------------------+
void CloseOppositeSidePositions(bool closeSells, bool onlyCurrentSession = false)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(!IsOurMagic(PositionGetInteger(POSITION_MAGIC)) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(onlyCurrentSession && sessionStartTime > 0 && (datetime)PositionGetInteger(POSITION_TIME) < sessionStartTime) continue;
      if(closeSells && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         trade.PositionClose(ticket);
      else if(!closeSells && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         trade.PositionClose(ticket);
   }
}

//+------------------------------------------------------------------+
//| Trailing: SL Buy A = when price moves Step pip from Buy A set SL for all Buy at SL Buy A; Sell opposite |
//+------------------------------------------------------------------+
void DoGongLaiTrailing()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double pipSize = pnt * 10.0;
   double stepSize = GongLaiStepPips * pipSize;

   if(bid > basePrice)
   {
      // Find Buy A: open Buy with smallest positive profit, get entry price
      double buyAEntry = 0.0;
      double minPosProfit = 1e9;
      int buyCount = 0;
      for(int i = 0; i < PositionsTotal(); i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         if(!IsOurMagic(PositionGetInteger(POSITION_MAGIC)) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if(PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_BUY) continue;
         if(sessionStartTime > 0 && (datetime)PositionGetInteger(POSITION_TIME) < sessionStartTime) continue;   // Chỉ phiên hiện tại
         buyCount++;
         double pr = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         if(pr > 0 && pr < minPosProfit)
         {
            minPosProfit = pr;
            buyAEntry = PositionGetDouble(POSITION_PRICE_OPEN);
         }
      }
      if(buyCount == 0 || minPosProfit >= 1e9 || buyAEntry <= 0) { lastSellTrailPrice = 0.0; return; }
      // Number of steps price moved up from Buy A (1 step = Step pip). E.g. Buy A=1000, Step=50, price=1200 -> nSteps=4, SL Buy A=1150
      double stepsUp = (bid - buyAEntry) / stepSize;
      if(stepsUp < 1.0)
         return;
      int nSteps = (int)MathFloor(stepsUp);
      // SL Buy A = Buy A entry + (nSteps-1)*step. At price 1200 set all Buy SL at 1150
      double slBuyA = NormalizeDouble(buyAEntry + (nSteps - 1) * stepSize, dgt);
      if(slBuyA >= bid)
         return;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         if(!IsOurMagic(PositionGetInteger(POSITION_MAGIC)) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if(PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_BUY) continue;
         if(sessionStartTime > 0 && (datetime)PositionGetInteger(POSITION_TIME) < sessionStartTime) continue;   // Chỉ phiên hiện tại
         double curSL = PositionGetDouble(POSITION_SL);
         double curTP = PositionGetDouble(POSITION_TP);
         if(slBuyA > curSL && slBuyA < bid)
            trade.PositionModify(ticket, slBuyA, curTP);
      }
      lastSellTrailPrice = 0.0;
      CloseOppositeSidePositions(true, true);   // Chỉ phiên hiện tại
   }
   else if(ask < basePrice)
   {
      // Find Sell A: open Sell with smallest positive profit, get entry price
      double sellAEntry = 0.0;
      double minPosProfit = 1e9;
      int sellCount = 0;
      for(int i = 0; i < PositionsTotal(); i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         if(!IsOurMagic(PositionGetInteger(POSITION_MAGIC)) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if(PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_SELL) continue;
         if(sessionStartTime > 0 && (datetime)PositionGetInteger(POSITION_TIME) < sessionStartTime) continue;   // Chỉ phiên hiện tại
         sellCount++;
         double pr = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         if(pr > 0 && pr < minPosProfit)
         {
            minPosProfit = pr;
            sellAEntry = PositionGetDouble(POSITION_PRICE_OPEN);
         }
      }
      if(sellCount == 0 || minPosProfit >= 1e9 || sellAEntry <= 0) { lastBuyTrailPrice = 0.0; return; }
      // Number of steps price moved down from Sell A (1 step = Step pip)
      double stepsDown = (sellAEntry - ask) / stepSize;
      if(stepsDown < 1.0)
         return;
      int nSteps = (int)MathFloor(stepsDown);
      // SL Sell A = Sell A entry - (nSteps - 1) * step (opposite to Buy)
      double slSellA = NormalizeDouble(sellAEntry - (nSteps - 1) * stepSize, dgt);
      if(slSellA <= ask)
         return;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         if(!IsOurMagic(PositionGetInteger(POSITION_MAGIC)) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if(PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_SELL) continue;
         if(sessionStartTime > 0 && (datetime)PositionGetInteger(POSITION_TIME) < sessionStartTime) continue;   // Chỉ phiên hiện tại
         double curSL = PositionGetDouble(POSITION_SL);
         double curTP = PositionGetDouble(POSITION_TP);
         if((curSL <= 0 || slSellA < curSL) && slSellA > ask)
            trade.PositionModify(ticket, slSellA, curTP);
      }
      lastBuyTrailPrice = 0.0;
      CloseOppositeSidePositions(false, true);   // Chỉ phiên hiện tại
   }
   else
   {
      lastBuyTrailPrice = 0.0;
      lastSellTrailPrice = 0.0;
   }
}

//+------------------------------------------------------------------+
//| Add closed profit/loss to session (by Magic)                       |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT)
      return;
   if(!IsOurMagic(HistoryDealGetInteger(trans.deal, DEAL_MAGIC)))
      return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
      return;
   long dealTime = (long)HistoryDealGetInteger(trans.deal, DEAL_TIME);
   // Chỉ tính lệnh đóng trong phiên hiện tại (từ sessionStartTime). Gắn EA hoặc EA reset = phiên mới, sessionStartTime cập nhật.
   if(sessionStartTime > 0 && dealTime < (long)sessionStartTime)
      return;
   if(lastResetTime > 0 && dealTime >= lastResetTime && dealTime <= lastResetTime + 15)
      return;   // Tránh cộng trùng deal từ lệnh vừa đóng khi reset
   // Chỉ tính lệnh đóng bởi TP (Take Profit). Lệnh đóng bởi SL / cắt tay / stop out không cộng vào pool cân bằng.
   if(HistoryDealGetInteger(trans.deal, DEAL_REASON) != DEAL_REASON_TP)
      return;
   
   // Closed deal P/L = profit + swap + commission
   double dealPnL = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                  + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                  + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   // Pool phiên = số $ lệnh đạt TP - % tiền tiết kiệm. Cân bằng AA/BB/CC chỉ khi pool > lệnh âm cần cân bằng (pool + loss >= 0).
   if(EnableLockProfit && LockProfitPct > 0 && dealPnL > 0)
   {
      double pct = MathMin(100.0, MathMax(0.0, LockProfitPct));
      double locked = dealPnL * (pct / 100.0);
      lockedProfitReserve += locked;
      dealPnL -= locked;
   }
   sessionClosedProfit += dealPnL;
   long dealMagic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   if(dealMagic == MagicBB)
      sessionClosedProfitBB += dealPnL;
   if(dealMagic == MagicCC)
      sessionClosedProfitCC += dealPnL;
}

//+------------------------------------------------------------------+
//| Grid structure: Base line = 0 (reference). Level 1 = closest to   |
//| base. Level 2, 3, ... n = further from base. No orders at base.   |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Return exact price of level (index 0..totalLevels-1).             |
//| Spacing between consecutive levels = gridStep (even).             |
//+------------------------------------------------------------------+
double GetGridLevelPrice(int levelIndex)
{
   if(levelIndex < MaxGridLevels)
      return NormalizeDouble(basePrice + (levelIndex + 0.5) * gridStep, dgt);
   else
      return NormalizeDouble(basePrice - (levelIndex - MaxGridLevels + 0.5) * gridStep, dgt);
}

//+------------------------------------------------------------------+
//| Lot đầu tiên (bậc 1): MỖI LOẠI LỆNH TÍNH RIÊNG. Tăng theo % vốn    |
//| khi EnableScaleByAccountGrowth: lot = input × sessionMultiplier.   |
//| AA: Buy Stop & Sell Stop dùng chung LotSizeAA.                      |
//+------------------------------------------------------------------+
double GetBaseLotForOrderType(ENUM_ORDER_TYPE orderType)
{
   if(orderType != ORDER_TYPE_BUY_STOP && orderType != ORDER_TYPE_SELL_STOP) return 0;
   return (EnableScaleByAccountGrowth) ? (LotSizeAA * sessionMultiplier) : LotSizeAA;
}

//+------------------------------------------------------------------+
//| Lot: Level 1 = fixed (input). Level 2+ = input * mult^(level-1)   |
//| Scale and mult per order type.                                    |
//+------------------------------------------------------------------+
double GetLotMultForOrderType(ENUM_ORDER_TYPE orderType)
{
   if(orderType == ORDER_TYPE_BUY_STOP || orderType == ORDER_TYPE_SELL_STOP) return LotMultAA;
   return 1.0;
}

ENUM_LOT_SCALE GetLotScaleForOrderType(ENUM_ORDER_TYPE orderType)
{
   if(orderType == ORDER_TYPE_BUY_STOP || orderType == ORDER_TYPE_SELL_STOP) return AALotScale;
   return LOT_FIXED;
}

//+------------------------------------------------------------------+
//| CÁCH TÍNH LOT: Bậc +1/-1 = lot đầu tiên. Bậc +2/-2, +3/-3... =     |
//| gấp thếp theo hệ số. levelNum: +1..+n (trên), -1..-n (dưới).       |
//+------------------------------------------------------------------+
double GetLotForLevel(ENUM_ORDER_TYPE orderType, int levelNum)
{
   int absLevel = MathAbs(levelNum);
   double baseLot = GetBaseLotForOrderType(orderType);
   ENUM_LOT_SCALE scale = GetLotScaleForOrderType(orderType);
   double lot = baseLot;
   if(absLevel <= 1 || scale == LOT_FIXED)
      lot = baseLot;   // Bậc +1/-1 = lot đầu tiên
   else if(scale == LOT_GEOMETRIC)
      lot = baseLot * MathPow(GetLotMultForOrderType(orderType), absLevel - 1);   // Bậc +2/-2... = gấp thếp
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(MaxLotAA > 0)
      maxLot = MathMin(maxLot, MaxLotAA);   // Giới hạn lot lớn nhất AA (0 = không giới hạn)
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathMax(minLot, MathMin(maxLot, lot));
   lot = MathFloor(lot / lotStep) * lotStep;
   if(lot < minLot) lot = minLot;
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| Get Take Profit (pips) for order type; 0 = off                    |
//+------------------------------------------------------------------+
double GetTakeProfitPipsForOrderType(ENUM_ORDER_TYPE orderType)
{
   if(orderType == ORDER_TYPE_BUY_STOP || orderType == ORDER_TYPE_SELL_STOP) return TakeProfitPipsAA;
   return 0;
}

//+------------------------------------------------------------------+
//| BB: Lot bậc 1 (có scale theo vốn nếu bật)                        |
//+------------------------------------------------------------------+
double GetBaseLotBB()
{
   return (EnableScaleByAccountGrowth) ? (LotSizeBB * sessionMultiplier) : LotSizeBB;
}

//+------------------------------------------------------------------+
//| BB: Lot theo bậc (Fixed hoặc Geometric), riêng AA                 |
//+------------------------------------------------------------------+
double GetLotForLevelBB(bool isBuyStop, int levelNum)
{
   int absLevel = MathAbs(levelNum);
   double baseLot = GetBaseLotBB();
   double lot = baseLot;
   if(absLevel <= 1 || BBLotScale == LOT_FIXED)
      lot = baseLot;
   else if(BBLotScale == LOT_GEOMETRIC)
      lot = baseLot * MathPow(LotMultBB, absLevel - 1);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(MaxLotBB > 0)
      maxLot = MathMin(maxLot, MaxLotBB);   // Giới hạn lot lớn nhất BB
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathMax(minLot, MathMin(maxLot, lot));
   lot = MathFloor(lot / lotStep) * lotStep;
   if(lot < minLot) lot = minLot;
   return NormalizeDouble(lot, 2);
}

double GetTakeProfitPipsBB()
{
   return TakeProfitPipsBB;
}

//+------------------------------------------------------------------+
//| CC: Lot bậc 1 (có scale theo vốn nếu bật)                        |
//+------------------------------------------------------------------+
double GetBaseLotCC()
{
   return (EnableScaleByAccountGrowth) ? (LotSizeCC * sessionMultiplier) : LotSizeCC;
}

//+------------------------------------------------------------------+
//| CC: Lot theo bậc (Fixed hoặc Geometric)                          |
//+------------------------------------------------------------------+
double GetLotForLevelCC(bool isBuyStop, int levelNum)
{
   int absLevel = MathAbs(levelNum);
   double baseLot = GetBaseLotCC();
   double lot = baseLot;
   if(absLevel <= 1 || CCLotScale == LOT_FIXED)
      lot = baseLot;
   else if(CCLotScale == LOT_GEOMETRIC)
      lot = baseLot * MathPow(LotMultCC, absLevel - 1);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(MaxLotCC > 0)
      maxLot = MathMin(maxLot, MaxLotCC);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathMax(minLot, MathMin(maxLot, lot));
   lot = MathFloor(lot / lotStep) * lotStep;
   if(lot < minLot) lot = minLot;
   return NormalizeDouble(lot, 2);
}

double GetTakeProfitPipsCC()
{
   return TakeProfitPipsCC;
}

//+------------------------------------------------------------------+
//| Initialize level prices - evenly spaced using gridStep            |
//+------------------------------------------------------------------+
void InitializeGridLevels()
{
   // Phiên hiện tại = 0 và bắt đầu tính từ đây (gọi khi gắn EA hoặc EA reset tự động)
   sessionStartTime = TimeCurrent();
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   sessionStartBalance = bal;
   attachBalance = bal;   // Vốn lúc EA khởi động: cập nhật mỗi lần EA khởi động lại / reset
   gridStep = GridDistancePips * pnt * 10.0;   // One grid step (even)
   int totalLevels = MaxGridLevels * 2;
   
   ArrayResize(gridLevels, totalLevels);
   
   for(int i = 0; i < totalLevels; i++)
      gridLevels[i] = GetGridLevelPrice(i);
   
   Print("Initialized ", totalLevels, " grid levels (", MaxGridLevels, " above + ", MaxGridLevels, " below base), spacing ", GridDistancePips, " pips");
}

//+------------------------------------------------------------------+
//| Manage grid: place orders from level 1 (closest to base) outward  |
//| GHI NHỚ BẬC LƯỚI: Đường gốc = bậc 0. Trên đường gốc = +1,+2,...+n. |
//| Dưới đường gốc = -1,-2,...-n. EA đặt lệnh chờ theo thứ tự này.     |
//| Each level evenly spaced by gridStep.                             |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| True if there is a position at priceLevel with given magic (Symbol). |
//+------------------------------------------------------------------+
bool PositionExistsAtLevelWithMagic(double priceLevel, long whichMagic)
{
   double tolerance = gridStep * 0.5;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != whichMagic || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      double posPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      if(MathAbs(posPrice - priceLevel) < tolerance)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Mỗi bậc: tối đa 1 lệnh mỗi loại (AA, BB, CC) theo input. Xóa lệnh chờ trùng; nếu đã có position tại bậc thì giữ 0 pending. |
//+------------------------------------------------------------------+
void RemoveDuplicateOrdersAtLevel()
{
   double tolerance = gridStep * 0.5;
   int nLevels = ArraySize(gridLevels);
   long magics[] = {MagicAA, MagicBB, MagicCC};
   bool enabled[] = {EnableAA, EnableBB, EnableCC};
   bool buySides[] = {true, false};  // Buy Stop, Sell Stop
   for(int L = 0; L < nLevels; L++)
   {
      double priceLevel = gridLevels[L];
      for(int m = 0; m < 3; m++)
      {
         if(!enabled[m]) continue;   // Chỉ áp dụng cho loại đang bật
         long whichMagic = magics[m];
         for(int side = 0; side < 2; side++)
         {
            bool isBuy = buySides[side];
            int positionCount = 0;
            for(int i = 0; i < PositionsTotal(); i++)
            {
               ulong ticket = PositionGetTicket(i);
               if(ticket <= 0) continue;
               if(PositionGetInteger(POSITION_MAGIC) != whichMagic || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
               if((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) != isBuy) continue;
               double posPrice = PositionGetDouble(POSITION_PRICE_OPEN);
               if(MathAbs(posPrice - priceLevel) < tolerance)
                  positionCount++;
            }
            ulong pendingTickets[];
            for(int i = 0; i < OrdersTotal(); i++)
            {
               ulong t = OrderGetTicket(i);
               if(t <= 0) continue;
               if(OrderGetInteger(ORDER_MAGIC) != whichMagic || OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
               if(StringFind(OrderGetString(ORDER_COMMENT), CommentOrder) != 0) continue;
               ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
               bool orderBuy = (ot == ORDER_TYPE_BUY_STOP || ot == ORDER_TYPE_BUY_LIMIT);
               if(orderBuy != isBuy) continue;
               double orderPrice = OrderGetDouble(ORDER_PRICE_OPEN);
               if(MathAbs(orderPrice - priceLevel) >= tolerance) continue;
               int n = ArraySize(pendingTickets);
               ArrayResize(pendingTickets, n + 1);
               pendingTickets[n] = t;
            }
            int keepPendings = (positionCount >= 1) ? 0 : 1;
            if(ArraySize(pendingTickets) > keepPendings)
            {
               for(int k = keepPendings; k < ArraySize(pendingTickets); k++)
                  trade.OrderDelete(pendingTickets[k]);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Balance AA: đóng lệnh âm XA đường gốc trước. Nếu pool không đủ thì đóng 1 phần (partial close). |
//| Pool = session TP $ - lock %. Floor = sessionStartBalance + lockedProfitReserve. |
//+------------------------------------------------------------------+
void DoBalanceAAByBB()
{
   if(!EnableAA || !EnableBalanceAAByBB || BalanceAAByBBThresholdUSD <= 0.0)
      return;
   if(sessionClosedProfitRemaining < 0)
      return;
   if(BalanceAAByBBCooldownSec > 0 && lastBalanceAAByBBCloseTime > 0 && (TimeCurrent() - lastBalanceAAByBBCloseTime) < BalanceAAByBBCooldownSec)
      return;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool priceAboveBase = (bid > basePrice);
   int nLevels = ArraySize(gridLevels);
   if(priceAboveBase)
   {
      if(nLevels < 5 || bid < gridLevels[4])
         return;
   }
   else
   {
      if(nLevels <= MaxGridLevels + 4)
         return;
      if(bid > gridLevels[MaxGridLevels + 4])
         return;
   }
   ulong tickets[];
   double pls[], vols[], openPrices[];
   ArrayResize(tickets, 0);
   ArrayResize(pls, 0);
   ArrayResize(vols, 0);
   ArrayResize(openPrices, 0);
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicAA || PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(sessionStartTime > 0 && (datetime)PositionGetInteger(POSITION_TIME) < sessionStartTime)
         continue;
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double pr = GetPositionPnL(ticket);
      double vol = PositionGetDouble(POSITION_VOLUME);
      bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      bool oppositeSide = priceAboveBase ? (!isBuy && openPrice < basePrice) : (isBuy && openPrice > basePrice);
      if(!oppositeSide || pr >= 0.0) continue;
      int n = ArraySize(tickets);
      ArrayResize(tickets, n + 1);
      ArrayResize(pls, n + 1);
      ArrayResize(vols, n + 1);
      ArrayResize(openPrices, n + 1);
      tickets[n] = ticket;
      pls[n] = pr;
      vols[n] = vol;
      openPrices[n] = openPrice;
   }
   int cnt = ArraySize(tickets);
   if(cnt == 0) return;
   // Sắp xếp: xa đường gốc trước (distance = |openPrice - basePrice| giảm dần)
   for(int i = 0; i < cnt - 1; i++)
      for(int j = i + 1; j < cnt; j++)
      {
         double di = MathAbs(openPrices[i] - basePrice);
         double dj = MathAbs(openPrices[j] - basePrice);
         if(dj > di)
         {
            SwapDouble(openPrices[i], openPrices[j]);
            SwapDouble(pls[i], pls[j]);
            SwapDouble(vols[i], vols[j]);
            SwapULong(tickets[i], tickets[j]);
         }
      }
   double balanceFloor = sessionStartBalance + lockedProfitReserve;
   double balanceNow = AccountInfoDouble(ACCOUNT_BALANCE);
   double pool = sessionClosedProfitRemaining;
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   // Chỉ xử lý lệnh xa nhất (k=0)
   int k = 0;
   double afterClose = pool + pls[k];
   double balanceAfterClose = balanceNow + pls[k];
   if(afterClose >= BalanceAAByBBThresholdUSD && afterClose >= 0 && balanceAfterClose >= balanceFloor)
   {
      trade.PositionClose(tickets[k]);
      sessionClosedProfitRemaining += pls[k];
      lastBalanceAAByBBCloseTime = TimeCurrent();
      Print("Balance AA: full close 1 losing AA (farthest from base). Pool remaining ", sessionClosedProfitRemaining, ". Cooldown ", BalanceAAByBBCooldownSec, "s.");
      return;
   }
   // Pool không đủ đóng hết: đóng 1 phần (partial) tương ứng số $ cân bằng
   double spendable = MathMin(pool, MathMin(balanceNow - balanceFloor, MathAbs(pls[k])));
   if(spendable <= 0) return;
   double volClose = vols[k] * (spendable / MathAbs(pls[k]));
   volClose = MathFloor(volClose / lotStep) * lotStep;
   if(volClose < minLot) return;  // Không đủ đóng phần nhỏ nhất -> đợi pool tăng
   if(volClose >= vols[k]) { volClose = vols[k]; spendable = MathAbs(pls[k]); }
   if(trade.PositionClosePartial(_Symbol, volClose, tickets[k]))
   {
      double realizedPnL = (volClose / vols[k]) * pls[k];
      sessionClosedProfitRemaining += realizedPnL;
      lastBalanceAAByBBCloseTime = TimeCurrent();
      Print("Balance AA: partial close ", volClose, " of ", vols[k], " (farthest from base). Realized ", realizedPnL, " USD. Pool remaining ", sessionClosedProfitRemaining, ". Cooldown ", BalanceAAByBBCooldownSec, "s.");
   }
}

//+------------------------------------------------------------------+
//| Balance BB: đóng lệnh âm XA đường gốc trước; không đủ thì đóng 1 phần (partial). |
//+------------------------------------------------------------------+
void DoBalanceBB()
{
   if(!EnableBB || !EnableBalanceBB || BalanceBBThresholdUSD <= 0.0)
      return;
   if(sessionClosedProfitRemaining < 0)
      return;
   if(BalanceBBCooldownSec > 0 && lastBalanceBBCloseTime > 0 && (TimeCurrent() - lastBalanceBBCloseTime) < BalanceBBCooldownSec)
      return;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool priceAboveBase = (bid > basePrice);
   int nLevels = ArraySize(gridLevels);
   if(priceAboveBase)
   {
      if(nLevels < 5 || bid < gridLevels[4])
         return;
   }
   else
   {
      if(nLevels <= MaxGridLevels + 4)
         return;
      if(bid > gridLevels[MaxGridLevels + 4])
         return;
   }
   ulong tickets[];
   double pls[], vols[], openPrices[];
   ArrayResize(tickets, 0);
   ArrayResize(pls, 0);
   ArrayResize(vols, 0);
   ArrayResize(openPrices, 0);
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicBB || PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(sessionStartTime > 0 && (datetime)PositionGetInteger(POSITION_TIME) < sessionStartTime)
         continue;
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double pr = GetPositionPnL(ticket);
      double vol = PositionGetDouble(POSITION_VOLUME);
      bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      bool oppositeSide = priceAboveBase ? (!isBuy && openPrice < basePrice) : (isBuy && openPrice > basePrice);
      if(!oppositeSide || pr >= 0.0) continue;
      int n = ArraySize(tickets);
      ArrayResize(tickets, n + 1);
      ArrayResize(pls, n + 1);
      ArrayResize(vols, n + 1);
      ArrayResize(openPrices, n + 1);
      tickets[n] = ticket;
      pls[n] = pr;
      vols[n] = vol;
      openPrices[n] = openPrice;
   }
   int cnt = ArraySize(tickets);
   if(cnt == 0) return;
   // Xa đường gốc trước
   for(int i = 0; i < cnt - 1; i++)
      for(int j = i + 1; j < cnt; j++)
      {
         double di = MathAbs(openPrices[i] - basePrice);
         double dj = MathAbs(openPrices[j] - basePrice);
         if(dj > di)
         {
            SwapDouble(openPrices[i], openPrices[j]);
            SwapDouble(pls[i], pls[j]);
            SwapDouble(vols[i], vols[j]);
            SwapULong(tickets[i], tickets[j]);
         }
      }
   double balanceFloor = sessionStartBalance + lockedProfitReserve;
   double balanceNow = AccountInfoDouble(ACCOUNT_BALANCE);
   double runningClosed = sessionClosedProfitRemaining;
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   int closedCount = 0;
   for(int k = 0; k < cnt; k++)
   {
      double afterClose = runningClosed + pls[k];
      double balanceAfterClose = balanceNow + pls[k];
      if(afterClose >= BalanceBBThresholdUSD && afterClose >= 0 && balanceAfterClose >= balanceFloor)
      {
         trade.PositionClose(tickets[k]);
         runningClosed += pls[k];
         balanceNow = balanceAfterClose;
         closedCount++;
         continue;
      }
      double spendable = MathMin(runningClosed, MathMin(balanceNow - balanceFloor, MathAbs(pls[k])));
      if(spendable <= 0) continue;
      double volClose = vols[k] * (spendable / MathAbs(pls[k]));
      volClose = MathFloor(volClose / lotStep) * lotStep;
      if(volClose < minLot) continue;
      if(volClose >= vols[k]) { volClose = vols[k]; spendable = MathAbs(pls[k]); }
      if(trade.PositionClosePartial(_Symbol, volClose, tickets[k]))
      {
         double realizedPnL = (volClose / vols[k]) * pls[k];
         runningClosed += realizedPnL;
         balanceNow += realizedPnL;
         closedCount++;
      }
   }
   if(closedCount > 0)
   {
      sessionClosedProfitRemaining = runningClosed;
      lastBalanceBBCloseTime = TimeCurrent();
      Print("Balance BB: closed ", closedCount, " (full/partial, farthest first). Pool remaining ", runningClosed, ". Cooldown ", BalanceBBCooldownSec, "s.");
   }
}

//+------------------------------------------------------------------+
//| Balance CC: đóng lệnh âm XA đường gốc trước; không đủ thì đóng 1 phần (partial). |
//+------------------------------------------------------------------+
void DoBalanceCC()
{
   if(!EnableCC || !EnableBalanceCC || BalanceCCThresholdUSD <= 0.0)
      return;
   if(sessionClosedProfitRemaining < 0)
      return;
   if(BalanceCCCooldownSec > 0 && lastBalanceCCCloseTime > 0 && (TimeCurrent() - lastBalanceCCCloseTime) < BalanceCCCooldownSec)
      return;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool priceAboveBase = (bid > basePrice);
   int nLevels = ArraySize(gridLevels);
   if(priceAboveBase)
   {
      if(nLevels < 5 || bid < gridLevels[4])
         return;
   }
   else
   {
      if(nLevels <= MaxGridLevels + 4)
         return;
      if(bid > gridLevels[MaxGridLevels + 4])
         return;
   }
   ulong tickets[];
   double pls[], vols[], openPrices[];
   ArrayResize(tickets, 0);
   ArrayResize(pls, 0);
   ArrayResize(vols, 0);
   ArrayResize(openPrices, 0);
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicCC || PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(sessionStartTime > 0 && (datetime)PositionGetInteger(POSITION_TIME) < sessionStartTime)
         continue;
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double pr = GetPositionPnL(ticket);
      double vol = PositionGetDouble(POSITION_VOLUME);
      bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      bool oppositeSide = priceAboveBase ? (!isBuy && openPrice < basePrice) : (isBuy && openPrice > basePrice);
      if(!oppositeSide || pr >= 0.0) continue;
      int n = ArraySize(tickets);
      ArrayResize(tickets, n + 1);
      ArrayResize(pls, n + 1);
      ArrayResize(vols, n + 1);
      ArrayResize(openPrices, n + 1);
      tickets[n] = ticket;
      pls[n] = pr;
      vols[n] = vol;
      openPrices[n] = openPrice;
   }
   int cnt = ArraySize(tickets);
   if(cnt == 0) return;
   for(int i = 0; i < cnt - 1; i++)
      for(int j = i + 1; j < cnt; j++)
      {
         double di = MathAbs(openPrices[i] - basePrice);
         double dj = MathAbs(openPrices[j] - basePrice);
         if(dj > di)
         {
            SwapDouble(openPrices[i], openPrices[j]);
            SwapDouble(pls[i], pls[j]);
            SwapDouble(vols[i], vols[j]);
            SwapULong(tickets[i], tickets[j]);
         }
      }
   double balanceFloor = sessionStartBalance + lockedProfitReserve;
   double balanceNow = AccountInfoDouble(ACCOUNT_BALANCE);
   double runningClosed = sessionClosedProfitRemaining;
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   int closedCount = 0;
   for(int k = 0; k < cnt; k++)
   {
      double afterClose = runningClosed + pls[k];
      double balanceAfterClose = balanceNow + pls[k];
      if(afterClose >= BalanceCCThresholdUSD && afterClose >= 0 && balanceAfterClose >= balanceFloor)
      {
         trade.PositionClose(tickets[k]);
         runningClosed += pls[k];
         balanceNow = balanceAfterClose;
         closedCount++;
         continue;
      }
      double spendable = MathMin(runningClosed, MathMin(balanceNow - balanceFloor, MathAbs(pls[k])));
      if(spendable <= 0) continue;
      double volClose = vols[k] * (spendable / MathAbs(pls[k]));
      volClose = MathFloor(volClose / lotStep) * lotStep;
      if(volClose < minLot) continue;
      if(volClose >= vols[k]) { volClose = vols[k]; spendable = MathAbs(pls[k]); }
      if(trade.PositionClosePartial(_Symbol, volClose, tickets[k]))
      {
         double realizedPnL = (volClose / vols[k]) * pls[k];
         runningClosed += realizedPnL;
         balanceNow += realizedPnL;
         closedCount++;
      }
   }
   if(closedCount > 0)
   {
      sessionClosedProfitRemaining = runningClosed;
      lastBalanceCCCloseTime = TimeCurrent();
      Print("Balance CC: closed ", closedCount, " (full/partial, farthest first). Pool remaining ", runningClosed, ". Cooldown ", BalanceCCCooldownSec, "s.");
   }
}

//+------------------------------------------------------------------+
void ManageGridOrders()
{
   if(gongLaiMode)
      return;
   
   CancelStopOrdersOutsideBaseZone();
   RemoveDuplicateOrdersAtLevel();   // Mỗi bậc tối đa 1 lệnh mỗi loại
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   // Buy Stop: trên đường gốc VÀ trên giá hiện tại. Sell Stop: dưới đường gốc VÀ dưới giá hiện tại. Thiếu thì bổ sung.
   for(int levelNum = 1; levelNum <= MaxGridLevels; levelNum++)
   {
      int idxAbove = levelNum - 1;
      double levelAbove = gridLevels[idxAbove];
      if(levelAbove >= basePrice && levelAbove > currentPrice)   // Buy Stop: bậc trên base và trên giá
      {
         if(EnableAA)
            EnsureOrderAtLevel(ORDER_TYPE_BUY_STOP, levelAbove, +levelNum);
         if(EnableBB)
            EnsureOrderAtLevelBB(true, levelAbove, +levelNum);
         if(EnableCC)
            EnsureOrderAtLevelCC(true, levelAbove, +levelNum);
      }
      int idxBelow = MaxGridLevels + levelNum - 1;
      double levelBelow = gridLevels[idxBelow];
      if(levelBelow <= basePrice && levelBelow < currentPrice)   // Sell Stop: bậc dưới base và dưới giá
      {
         if(EnableAA)
            EnsureOrderAtLevel(ORDER_TYPE_SELL_STOP, levelBelow, -levelNum);
         if(EnableBB)
            EnsureOrderAtLevelBB(false, levelBelow, -levelNum);
         if(EnableCC)
            EnsureOrderAtLevelCC(false, levelBelow, -levelNum);
      }
   }
}

//+------------------------------------------------------------------+
//| Ensure order at level - chỉ bổ sung khi thiếu (chưa có lệnh chờ và chưa có position cùng loại tại bậc). |
//+------------------------------------------------------------------+
void EnsureOrderAtLevel(ENUM_ORDER_TYPE orderType, double priceLevel, int levelNum)
{
   ulong  ticket       = 0;
   double existingPrice = 0.0;
   if(GetPendingOrderAtLevel(orderType, priceLevel, ticket, existingPrice, MagicAA))
   {
      double desiredPrice = NormalizeDouble(priceLevel, dgt);
      if(MathAbs(existingPrice - desiredPrice) > (pnt / 2.0))
         AdjustPendingOrderToLevel(ticket, orderType, priceLevel);
      return;
   }
   if(PositionExistsAtLevelWithMagic(priceLevel, MagicAA))
      return;
   if(!CanPlaceOrderAtLevel(orderType, priceLevel, MagicAA))
      return;
   PlacePendingOrder(orderType, priceLevel, levelNum);
}

//+------------------------------------------------------------------+
//| BB: Ensure order at level - chỉ bổ sung khi thiếu (chưa có lệnh chờ BB và chưa có position BB tại bậc). |
//+------------------------------------------------------------------+
void EnsureOrderAtLevelBB(bool isBuyStop, double priceLevel, int levelNum)
{
   ulong ticket = 0;
   double existingPrice = 0.0;
   if(GetPendingOrderAtLevel(isBuyStop ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP, priceLevel, ticket, existingPrice, MagicBB))
   {
      double desiredPrice = NormalizeDouble(priceLevel, dgt);
      if(MathAbs(existingPrice - desiredPrice) > (pnt / 2.0))
         AdjustPendingOrderToLevel(ticket, isBuyStop ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP, priceLevel, GetTakeProfitPipsBB());
      return;
   }
   if(PositionExistsAtLevelWithMagic(priceLevel, MagicBB))
      return;
   if(!CanPlaceOrderAtLevel(isBuyStop ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP, priceLevel, MagicBB))
      return;
   PlacePendingOrderBB(isBuyStop, priceLevel, levelNum);
}

//+------------------------------------------------------------------+
//| CC: Ensure order at level - chỉ bổ sung khi thiếu (chưa có lệnh chờ CC và chưa có position CC tại bậc). |
//+------------------------------------------------------------------+
void EnsureOrderAtLevelCC(bool isBuyStop, double priceLevel, int levelNum)
{
   ulong ticket = 0;
   double existingPrice = 0.0;
   if(GetPendingOrderAtLevel(isBuyStop ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP, priceLevel, ticket, existingPrice, MagicCC))
   {
      double desiredPrice = NormalizeDouble(priceLevel, dgt);
      if(MathAbs(existingPrice - desiredPrice) > (pnt / 2.0))
         AdjustPendingOrderToLevel(ticket, isBuyStop ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP, priceLevel, GetTakeProfitPipsCC());
      return;
   }
   if(PositionExistsAtLevelWithMagic(priceLevel, MagicCC))
      return;
   if(!CanPlaceOrderAtLevel(isBuyStop ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP, priceLevel, MagicCC))
      return;
   PlacePendingOrderCC(isBuyStop, priceLevel, levelNum);
}

//+------------------------------------------------------------------+
//| Find pending order at level: same order type, same magic, comment = CommentOrder. |
//+------------------------------------------------------------------+
bool GetPendingOrderAtLevel(ENUM_ORDER_TYPE orderType,
                            double priceLevel,
                            ulong &ticket,
                            double &orderPrice,
                            long whichMagic)
{
   double tolerance = gridStep * 0.5;
   bool   isBuySide = (orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_BUY_STOP);

   for(int i = 0; i < OrdersTotal(); i++)
   {
      ulong t = OrderGetTicket(i);
      if(t <= 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) != whichMagic || OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if(StringFind(OrderGetString(ORDER_COMMENT), CommentOrder) != 0)
         continue;

      ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      bool isOrderBuy = (ot == ORDER_TYPE_BUY_LIMIT || ot == ORDER_TYPE_BUY_STOP);
      if(isOrderBuy != isBuySide) continue;

      double price = OrderGetDouble(ORDER_PRICE_OPEN);
      if(MathAbs(price - priceLevel) < tolerance)
      {
         ticket = t;
         orderPrice = price;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Adjust pending order to grid level. tpPipsOverride: -1=use AA default |
//+------------------------------------------------------------------+
void AdjustPendingOrderToLevel(ulong ticket,
                               ENUM_ORDER_TYPE orderType,
                               double priceLevel,
                               double tpPipsOverride = -1)
{
   double price = NormalizeDouble(priceLevel, dgt);
   double sl = 0, tp = 0;
   double tpPips = (tpPipsOverride >= 0) ? tpPipsOverride : GetTakeProfitPipsForOrderType(orderType);

   if(tpPips > 0)
   {
      if(orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_BUY_STOP)
         tp = NormalizeDouble(price + tpPips * pnt * 10.0, dgt);
      else
         tp = NormalizeDouble(price - tpPips * pnt * 10.0, dgt);
   }

   // CTrade::OrderModify(ticket, price, sl, tp, type_time, expiration, stoplimit)
   bool result = trade.OrderModify(ticket, price, sl, tp, ORDER_TIME_GTC, 0, 0);
   if(result)
      Print("Adjusted order to level: ", EnumToString(orderType), " at ", price, " | TP: ", tp);
   else
      Print("Order adjust error: ", EnumToString(orderType), " | Error: ", GetLastError());
}

//+------------------------------------------------------------------+
//| Kiểm tra có thể đặt lệnh tại bậc: mỗi bậc tối đa 1 lệnh mỗi loại (AA, BB, CC) theo input. whichMagic = magic của loại đang đặt. |
//+------------------------------------------------------------------+
bool CanPlaceOrderAtLevel(ENUM_ORDER_TYPE orderType, double priceLevel, long whichMagic)
{
   double tolerance = gridStep * 0.5;
   bool isBuyOrder = (orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_BUY_STOP);
   int countSameLevel = 0;

   for(int i = 0; i < OrdersTotal(); i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket <= 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) != whichMagic || OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      double orderPrice = OrderGetDouble(ORDER_PRICE_OPEN);
      if(MathAbs(orderPrice - priceLevel) >= tolerance) continue;
      ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      bool orderBuy = (ot == ORDER_TYPE_BUY_LIMIT || ot == ORDER_TYPE_BUY_STOP);
      if(orderBuy == isBuyOrder)
         countSameLevel++;
   }
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != whichMagic || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      double posPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      if(MathAbs(posPrice - priceLevel) >= tolerance) continue;
      ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if((pt == POSITION_TYPE_BUY) == isBuyOrder)
         countSameLevel++;
   }
   return (countSameLevel < 1);   // Tối đa 1 lệnh (pending hoặc position) mỗi loại mỗi bậc
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Place pending order with TP; lot by grid level. SL set by trailing only |
//+------------------------------------------------------------------+
void PlacePendingOrder(ENUM_ORDER_TYPE orderType, double priceLevel, int levelNum)
{
   double price = NormalizeDouble(priceLevel, dgt);
   double lot   = GetLotForLevel(orderType, levelNum);
   double sl = 0, tp = 0;
   double tpPips = GetTakeProfitPipsForOrderType(orderType);
   
   if(tpPips > 0)
   {
      if(orderType == ORDER_TYPE_BUY_STOP)
         tp = NormalizeDouble(price + tpPips * pnt * 10.0, dgt);
      else
         tp = NormalizeDouble(price - tpPips * pnt * 10.0, dgt);
   }
   
   trade.SetExpertMagicNumber(MagicAA);
   string cmt = CommentOrder;
   bool result = false;
   if(orderType == ORDER_TYPE_BUY_STOP)
      result = trade.BuyStop(lot, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);
   else if(orderType == ORDER_TYPE_SELL_STOP)
      result = trade.SellStop(lot, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);
   
   if(result)
      Print("Order placed: ", EnumToString(orderType), " at ", price, " lot ", lot, " (level ", levelNum > 0 ? "+" : "", levelNum, ")");
   else
      Print("Order error: ", EnumToString(orderType), " | Error: ", GetLastError());
}

//+------------------------------------------------------------------+
//| BB: Đặt lệnh chờ (Buy Stop hoặc Sell Stop), lot/TP riêng BB       |
//+------------------------------------------------------------------+
void PlacePendingOrderBB(bool isBuyStop, double priceLevel, int levelNum)
{
   double price = NormalizeDouble(priceLevel, dgt);
   double lot   = GetLotForLevelBB(isBuyStop, levelNum);
   double sl = 0, tp = 0;
   double tpPips = GetTakeProfitPipsBB();
   if(tpPips > 0)
   {
      if(isBuyStop)
         tp = NormalizeDouble(price + tpPips * pnt * 10.0, dgt);
      else
         tp = NormalizeDouble(price - tpPips * pnt * 10.0, dgt);
   }
   trade.SetExpertMagicNumber(MagicBB);
   string cmt = CommentOrder;
   bool result = false;
   if(isBuyStop)
      result = trade.BuyStop(lot, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);
   else
      result = trade.SellStop(lot, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);
   if(result)
      Print("Order placed BB: ", isBuyStop ? "BuyStop" : "SellStop", " at ", price, " lot ", lot, " (level ", levelNum > 0 ? "+" : "", levelNum, ")");
   else
      Print("Order error BB | Error: ", GetLastError());
}

//+------------------------------------------------------------------+
//| CC: Đặt lệnh chờ (Buy Stop hoặc Sell Stop), lot/TP riêng CC       |
//+------------------------------------------------------------------+
void PlacePendingOrderCC(bool isBuyStop, double priceLevel, int levelNum)
{
   double price = NormalizeDouble(priceLevel, dgt);
   double lot   = GetLotForLevelCC(isBuyStop, levelNum);
   double sl = 0, tp = 0;
   double tpPips = GetTakeProfitPipsCC();
   if(tpPips > 0)
   {
      if(isBuyStop)
         tp = NormalizeDouble(price + tpPips * pnt * 10.0, dgt);
      else
         tp = NormalizeDouble(price - tpPips * pnt * 10.0, dgt);
   }
   trade.SetExpertMagicNumber(MagicCC);
   string cmt = CommentOrder;
   bool result = false;
   if(isBuyStop)
      result = trade.BuyStop(lot, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);
   else
      result = trade.SellStop(lot, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);
   if(result)
      Print("Order placed CC: ", isBuyStop ? "BuyStop" : "SellStop", " at ", price, " lot ", lot, " (level ", levelNum > 0 ? "+" : "", levelNum, ")");
   else
      Print("Order error CC | Error: ", GetLastError());
}

//+------------------------------------------------------------------+
