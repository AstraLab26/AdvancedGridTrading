//+------------------------------------------------------------------+
//|                                         AdvancedGridTrading.mq5   |
//|              Advanced Grid Trading EA - Pro edition              |
//+------------------------------------------------------------------+
#property copyright "Advanced Grid EA"
#property version   "2.00"
#property description "Advanced Grid Trading EA: per-order lot, scale by capital, trailing profit, session reset"

#include <Trade\Trade.mqh>

//--- Lot scale: 0=Fixed, 2=Geometric. Level 1 = LotSize; level 2+ = multiplier.
enum ENUM_LOT_SCALE { LOT_FIXED = 0, LOT_GEOMETRIC = 2 };
enum ENUM_ON_TARGET { ON_TARGET_RESET = 0, ON_TARGET_STOP = 1 };

//+------------------------------------------------------------------+
//| 1. GRID                                                           |
//+------------------------------------------------------------------+
input group "=== 1. GRID ==="
input double GridDistancePips = 1500.0;         // Grid distance (pips)
input int MaxGridLevels = 20;                   // Number of grid levels per side (above/below base line)
input bool AutoRefillOrders = true;             // Auto refill orders when closed

//+------------------------------------------------------------------+
//| 2. ORDERS                                                         |
//+------------------------------------------------------------------+
input group "=== 2. ORDERS ==="

input group "--- 2.1 BUY LIMIT ---"
input bool EnableBuyLimit = true;               // Enable
input double LotSizeBuyLimit = 0.02;            // Initial lot (level 1, fixed)
input ENUM_LOT_SCALE BuyLimitLotScale = LOT_FIXED;  // Fixed / Geometric
input double LotMultBuyLimit = 1.0;             // Lot mult for level 2+ (Geometric)
input double TakeProfitPipsBuyLimit = 1500.0;  // Take Profit (pips, 0=off)

input group "--- 2.2 BUY STOP ---"
input bool EnableBuyStop = true;                // Enable
input double LotSizeBuyStop = 0.04;             // Initial lot (level 1, fixed)
input ENUM_LOT_SCALE BuyStopLotScale = LOT_GEOMETRIC;   // Fixed / Geometric
input double LotMultBuyStop = 2.0;              // Lot mult for level 2+ (Geometric)
input bool BuyStopOnlyAboveBase = true;         // Only place above base line (disable = place all levels)
input double TakeProfitPipsBuyStop = 0.0;      // Take Profit (pips, 0=off)

input group "--- 2.3 SELL LIMIT ---"
input bool EnableSellLimit = true;             // Enable
input double LotSizeSellLimit = 0.02;           // Initial lot (level 1, fixed)
input ENUM_LOT_SCALE SellLimitLotScale = LOT_FIXED; // Fixed / Geometric
input double LotMultSellLimit = 1.0;            // Lot mult for level 2+ (Geometric)
input double TakeProfitPipsSellLimit = 1500.0; // Take Profit (pips, 0=off)

input group "--- 2.4 SELL STOP ---"
input bool EnableSellStop = true;               // Enable
input double LotSizeSellStop = 0.04;             // Initial lot (level 1, fixed)
input ENUM_LOT_SCALE SellStopLotScale = LOT_GEOMETRIC;  // Fixed / Geometric
input double LotMultSellStop = 2.0;             // Lot mult for level 2+ (Geometric)
input bool SellStopOnlyBelowBase = true;        // Only place below base line (disable = place all levels)
input double TakeProfitPipsSellStop = 0.0;     // Take Profit (pips, 0=off)

input group "--- 2.5 COMMON ---"
input int MagicNumber = 123456;                // Magic Number (EA identifier)
input string CommentOrder = "EA Grid AA";      // Order comment (AA)

input group "=== 2B. ORDERS BB (Stop only, above/below base) ==="
input bool EnableBB = true;                     // Enable BB pending orders
input double LotSizeBuyStopBB = 4.0;            // BB Buy Stop: initial lot (level 1)
input double LotSizeSellStopBB = 4.0;           // BB Sell Stop: initial lot (level 1)
input ENUM_LOT_SCALE BBLotScale = LOT_GEOMETRIC;  // BB: Fixed / Geometric
input double LotMultBB = 0.5;                   // BB: lot mult for level 2+
input double TakeProfitPipsBuyStopBB = 1500.0; // BB Buy Stop TP (pips, 0=off)
input double TakeProfitPipsSellStopBB = 1500.0;// BB Sell Stop TP (pips, 0=off)
input string CommentOrderBB = "EA Grid BB";    // Order comment (BB)

//+------------------------------------------------------------------+
//| 3. SESSION: Reset / SL / Balance / Trailing                       |
//+------------------------------------------------------------------+
input group "=== 3. SESSION: Reset by Profit ==="
input bool EnableResetByProfit = false;         // Enable reset when session profit reaches target
input double TargetProfitUSD = 15.0;           // Session profit to trigger reset (USD)
input ENUM_ON_TARGET OnTargetReached = ON_TARGET_RESET;  // On target: Reset EA / Stop EA

input group "=== 4. SESSION: SL (Total Loss) ==="
input bool EnableSLTotal = false;               // Enable session SL when total session loss hits level
input double SLTotalUSD = 2000.0;              // Session loss to trigger SL (USD): total <= -this value
input ENUM_ON_TARGET OnSLReached = ON_TARGET_RESET;     // On SL: Reset EA / Stop EA

input group "=== 5. SESSION: Order Balance ==="
input bool EnableBalanceReset = true;           // Enable: reset when total lot >= threshold and session profit >= min
input double BalanceResetTotalLot = 8.0;       // Total open lot to trigger balance reset
input double BalanceResetMinProfitUSD = 50.0;  // Session profit must be >= this (USD) to allow reset

//--- Trailing threshold: Session = open+closed in session; OpenOnly = only open positions
enum ENUM_TRAILING_THRESHOLD_MODE { TRAILING_THRESHOLD_SESSION = 0,   // Session: open + closed in session
                                    TRAILING_THRESHOLD_OPEN_ONLY = 1 }; // Open only: only open positions

input group "=== 6. SESSION: Trailing Profit ==="
input bool EnableTrailingTotalProfit = true;    // Enable trailing: cancel pendings, trail SL when profit >= threshold
input ENUM_TRAILING_THRESHOLD_MODE TrailingThresholdMode = TRAILING_THRESHOLD_OPEN_ONLY;  // Threshold mode: Session / Open only
input double TrailingThresholdUSD = 200.0;     // Start trailing when profit >= (USD)
input double TrailingLockStepPct = 20.0;       // Lock: close all when profit drops this % from peak
input double GongLaiPips = 1500.0;             // Pips: SL distance from price (Buy A / Sell A)
input double GongLaiStepPips = 1000.0;         // Pips: step to move SL (update every step pips)

//+------------------------------------------------------------------+
//| 7. SCALE BY ACCOUNT %                                             |
//+------------------------------------------------------------------+
input group "=== 7. SCALE BY ACCOUNT % ==="
input bool EnableScaleByAccountGrowth = true;   // Enable: lot, TP, SL, trailing scale by x% account growth
input double BaseCapitalUSD = 100000.0;        // Base capital (USD): 0 = use balance at EA attach; >0 = use this as base
input double AccountGrowthScalePct = 50.0;     // x% (max 100): account +100% vs base -> scale by x%

//+------------------------------------------------------------------+
//| 8. NOTIFICATIONS                                                  |
//+------------------------------------------------------------------+
input group "=== 8. NOTIFICATIONS ==="
input bool EnableResetNotification = true;     // Send notification when EA resets or stops

//--- Global variables
CTrade trade;
double pnt;
int dgt;
double basePrice;                               // Base price (base line)
double gridLevels[];                            // Array of level prices (evenly spaced by GridDistancePips)
double gridStep;                                // One grid step (price) = GridDistancePips, used for tolerance/snap
double sessionClosedProfit = 0.0;               // Total closed profit/loss in current session
datetime lastResetTime = 0;                     // Last reset time (avoid double-count from orders just closed on reset)
bool eaStoppedByTarget = false;                 // true = EA stopped placing new orders (Stop mode)
double balanceGoc = 0.0;                       // Account balance when EA was attached (base, unchanged)
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

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   dgt = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   pnt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   basePrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   sessionClosedProfit = 0.0;
   lastResetTime = 0;
   eaStoppedByTarget = false;
   balanceGoc = (BaseCapitalUSD > 0) ? BaseCapitalUSD : AccountInfoDouble(ACCOUNT_BALANCE);
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
   
   Print("========================================");
   Print("Advanced Grid Trading EA started. Session profit: 0 USD (open + closed from now)");
   Print("Symbol: ", _Symbol, " | Base: ", basePrice, " | Grid: ", GridDistancePips, " pips | Levels: ", ArraySize(gridLevels));
   if(EnableResetByProfit)
      Print("When session profit >= ", TargetProfitUSD, " USD: ", OnTargetReached == ON_TARGET_RESET ? "Reset EA" : "Stop EA");
   if(EnableSLTotal)
      Print("When session total (open+closed) <= -", SLTotalUSD, " USD", EnableScaleByAccountGrowth ? " (scaled by account %)" : "", ": ", OnSLReached == ON_TARGET_RESET ? "Reset EA" : "Stop EA");
   if(EnableTrailingTotalProfit)
      Print("Trailing profit: ", TrailingThresholdMode == TRAILING_THRESHOLD_SESSION ? "session (open+closed)" : "open only", ", start when >= ", TrailingThresholdUSD, " USD, lock when drops ", TrailingLockStepPct, "% from peak");
   if(EnableBalanceReset)
      Print("Order balance: reset when total open lot >= ", BalanceResetTotalLot, " and session profit >= ", BalanceResetMinProfitUSD, " USD");
   if(EnableScaleByAccountGrowth)
      Print("Base capital = ", balanceGoc, " USD", BaseCapitalUSD > 0 ? " (manual)" : " (balance at attach)", ". Lot/TP/SL/Trailing x ", AccountGrowthScalePct, "% growth. mult=", sessionMultiplier);
   Print("Lot per type (L1,L2,L3): BuyStop=", GetLotForLevel(ORDER_TYPE_BUY_STOP,1), ",", GetLotForLevel(ORDER_TYPE_BUY_STOP,2), ",", GetLotForLevel(ORDER_TYPE_BUY_STOP,3),
         " | SellStop=", GetLotForLevel(ORDER_TYPE_SELL_STOP,1), ",", GetLotForLevel(ORDER_TYPE_SELL_STOP,2), ",", GetLotForLevel(ORDER_TYPE_SELL_STOP,3));
   if(EnableBB)
      Print("BB enabled: BuyStop above, SellStop below. Lot L1,L2,L3: ", GetLotForLevelBB(true,1), ",", GetLotForLevelBB(true,2), ",", GetLotForLevelBB(true,3),
            " | ", GetLotForLevelBB(false,1), ",", GetLotForLevelBB(false,2), ",", GetLotForLevelBB(false,3));
   Print("========================================");
   
   // On start place 4 order types (Buy/Sell, Limit/Stop) at grid levels, evenly spaced by gridStep
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
   
   double floating = 0.0;
   if(EnableResetByProfit && TargetProfitUSD > 0 || EnableSLTotal && SLTotalUSD > 0 || EnableTrailingTotalProfit)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0 && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            floating += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      }
   }
   
   double totalSession = sessionClosedProfit + floating;
   double totalForTrailing = (TrailingThresholdMode == TRAILING_THRESHOLD_SESSION) ? totalSession : floating;
   double effectiveTP = (EnableScaleByAccountGrowth && TargetProfitUSD > 0) ? (TargetProfitUSD * sessionMultiplier) : TargetProfitUSD;
   double effectiveTrailingThreshold = (EnableScaleByAccountGrowth && TrailingThresholdUSD > 0) ? (TrailingThresholdUSD * sessionMultiplier) : TrailingThresholdUSD;
   double effectiveSLTotalUSD = (EnableScaleByAccountGrowth && SLTotalUSD > 0) ? (SLTotalUSD * sessionMultiplier) : SLTotalUSD;
   
   if(EnableTrailingTotalProfit && TrailingThresholdUSD > 0 && TrailingLockStepPct > 0)
   {
      double effectiveLockStepUSD = effectiveTrailingThreshold * (MathMax(0.0, MathMin(100.0, TrailingLockStepPct)) / 100.0);
      if(totalForTrailing >= effectiveTrailingThreshold)
      {
         if(!gongLaiMode)
         {
            gongLaiMode = true;
            CancelAllPendingOrders();
            Print("Trailing profit: ", (TrailingThresholdMode == TRAILING_THRESHOLD_SESSION ? "session" : "open only"), " reached ", totalForTrailing, " USD (>= ", effectiveTrailingThreshold, "). Cancelled pendings, no refill. Starting trail SL by Buy A/Sell A.");
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
   
   if(EnableSLTotal && SLTotalUSD > 0)
   {
      if(totalSession <= -effectiveSLTotalUSD)
      {
         CloseAllPositionsAndOrders();
         if(OnSLReached == ON_TARGET_STOP)
         {
            eaStoppedByTarget = true;
            Print("Session SL: ", totalSession, " USD (limit -", effectiveSLTotalUSD, "). EA STOPPED: closed all, cancelled pendings, no new orders.");
            if(EnableResetNotification) { SendResetNotification("Session SL"); double b = AccountInfoDouble(ACCOUNT_BALANCE); sessionPeakBalance = b; sessionMinBalance = b; sessionMaxSingleLot = 0; sessionTotalLotAtMaxLot = 0; }
            return;
         }
         UpdateSessionMultiplierFromAccountGrowth();
         lastResetTime = TimeCurrent();
         sessionClosedProfit = 0.0;
         sessionPeakProfit = 0.0;
         gongLaiMode = false;
         lastBuyTrailPrice = 0.0;
         lastSellTrailPrice = 0.0;
         basePrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         InitializeGridLevels();
         Print("Session SL: ", totalSession, " USD (limit -", effectiveSLTotalUSD, "). EA reset: new base line = ", basePrice, ". New session started.");
         if(EnableResetNotification) { SendResetNotification("Session SL"); double b = AccountInfoDouble(ACCOUNT_BALANCE); sessionPeakBalance = b; sessionMinBalance = b; sessionMaxSingleLot = 0; sessionTotalLotAtMaxLot = 0; }
         return;
      }
   }
   
   if(EnableResetByProfit && TargetProfitUSD > 0)
   {
      if(totalSession >= effectiveTP)
      {
         CloseAllPositionsAndOrders();
         if(OnTargetReached == ON_TARGET_STOP)
         {
            eaStoppedByTarget = true;
            Print("Session reached ", totalSession, " USD (target ", effectiveTP, "). EA STOPPED: closed all, cancelled pendings, no new orders.");
            if(EnableResetNotification) { SendResetNotification("Session profit"); double b = AccountInfoDouble(ACCOUNT_BALANCE); sessionPeakBalance = b; sessionMinBalance = b; sessionMaxSingleLot = 0; sessionTotalLotAtMaxLot = 0; }
            return;
         }
         UpdateSessionMultiplierFromAccountGrowth();
         lastResetTime = TimeCurrent();
         sessionClosedProfit = 0.0;
         sessionPeakProfit = 0.0;
         gongLaiMode = false;
         lastBuyTrailPrice = 0.0;
         lastSellTrailPrice = 0.0;
         basePrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         InitializeGridLevels();
         Print("Session reached ", totalSession, " USD (target ", effectiveTP, "). EA reset: new base line = ", basePrice, ", profit counter = 0 USD. New session started.");
         if(EnableResetNotification) { SendResetNotification("Session profit"); double b = AccountInfoDouble(ACCOUNT_BALANCE); sessionPeakBalance = b; sessionMinBalance = b; sessionMaxSingleLot = 0; sessionTotalLotAtMaxLot = 0; }
         return;
      }
   }
   
   if(EnableBalanceReset && BalanceResetTotalLot > 0 && BalanceResetMinProfitUSD > 0)
   {
      double totalOpenLot = 0.0;
      for(int i = 0; i < PositionsTotal(); i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
            totalOpenLot += PositionGetDouble(POSITION_VOLUME);
      }
      if(totalOpenLot >= BalanceResetTotalLot && totalSession >= BalanceResetMinProfitUSD)
      {
         CloseAllPositionsAndOrders();
         UpdateSessionMultiplierFromAccountGrowth();
         lastResetTime = TimeCurrent();
         sessionClosedProfit = 0.0;
         sessionPeakProfit = 0.0;
         gongLaiMode = false;
         lastBuyTrailPrice = 0.0;
         lastSellTrailPrice = 0.0;
         basePrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         InitializeGridLevels();
         Print("Order balance: total open lot ", totalOpenLot, " >= ", BalanceResetTotalLot, ", session profit ", totalSession, " USD >= ", BalanceResetMinProfitUSD, " USD. EA reset, new base = ", basePrice);
         if(EnableResetNotification) { SendResetNotification("Order balance"); double b = AccountInfoDouble(ACCOUNT_BALANCE); sessionPeakBalance = b; sessionMinBalance = b; sessionMaxSingleLot = 0; sessionTotalLotAtMaxLot = 0; }
         return;
      }
   }
   
   if(gongLaiMode)
   {
      int posCount = 0;
      for(int i = 0; i < PositionsTotal(); i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
            posCount++;
      }
      if(posCount == 0)
      {
         gongLaiMode = false;
         lastBuyTrailPrice = 0.0;
         lastSellTrailPrice = 0.0;
         sessionClosedProfit = 0.0;
         sessionPeakProfit = 0.0;
         basePrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         InitializeGridLevels();
         Print("Trailing: all positions closed (price hit SL). Reset session, new base = ", basePrice, ". Placing orders again.");
         if(EnableResetNotification) { SendResetNotification("Trailing profit"); double b = AccountInfoDouble(ACCOUNT_BALANCE); sessionPeakBalance = b; sessionMinBalance = b; sessionMaxSingleLot = 0; sessionTotalLotAtMaxLot = 0; }
      }
      else
         DoGongLaiTrailing();
   }
   
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
      Print("Reset: capital ", balanceGoc, " -> ", newBalance, " (+", (growth*100), "%). Setting ", pct, "% -> Lot/TP/SL/Trailing x ", sessionMultiplier);
   }
   UpdateCapitalGrowthLabel();
}

//+------------------------------------------------------------------+
//| Cập nhật nhãn trên biểu đồ: vốn base, vốn hiện tại, % tăng, mult  |
//| Khi BaseCapitalUSD > 0: so sánh vốn hiện tại vs vốn nhập input     |
//+------------------------------------------------------------------+
void UpdateCapitalGrowthLabel()
{
   if(balanceGoc <= 0)
      return;
   long chartId = ChartID();
   double currentBal = AccountInfoDouble(ACCOUNT_BALANCE);
   double growthPct = (balanceGoc > 0) ? ((currentBal - balanceGoc) / balanceGoc * 100.0) : 0;
   string baseStr = (BaseCapitalUSD > 0) ? "Vốn base (input): " : "Vốn base (attach): ";
   string txt = baseStr + DoubleToString(balanceGoc, 2) + " USD\n";
   txt += "Vốn hiện tại: " + DoubleToString(currentBal, 2) + " USD\n";
   txt += "Vốn tăng: " + (growthPct >= 0 ? "+" : "") + DoubleToString(growthPct, 2) + "%\n";
   txt += "Hàm số x " + DoubleToString(sessionMultiplier, 2);
   if(ObjectFind(chartId, "GridCapitalGrowth") < 0)
      ObjectCreate(chartId, "GridCapitalGrowth", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(chartId, "GridCapitalGrowth", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(chartId, "GridCapitalGrowth", OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(chartId, "GridCapitalGrowth", OBJPROP_YDISTANCE, 25);
   ObjectSetString(chartId, "GridCapitalGrowth", OBJPROP_TEXT, txt);
   ObjectSetInteger(chartId, "GridCapitalGrowth", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(chartId, "GridCapitalGrowth", OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(chartId, "GridCapitalGrowth", OBJPROP_SELECTABLE, false);
   ObjectSetInteger(chartId, "GridCapitalGrowth", OBJPROP_BACK, false);
   ChartRedraw(chartId);
}

void DeleteCapitalGrowthLabel()
{
   ObjectDelete(ChartID(), "GridCapitalGrowth");
   ChartRedraw(ChartID());
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
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
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
//| Send notification when EA resets or stops                          |
//+------------------------------------------------------------------+
void SendResetNotification(const string chucNang)
{
   if(!EnableResetNotification) return;
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double pct = (balanceGoc > 0) ? ((bal - balanceGoc) / balanceGoc * 100.0) : 0;
   double maxLossUSD = globalPeakBalance - globalMinBalance;
   string msg = "EA RESET\n";
   msg += "Chart: " + _Symbol + "\n";
   msg += "Function: " + chucNang + "\n";
   msg += "Initial balance: " + DoubleToString(balanceGoc, 2) + " USD\n";
   msg += "Current balance: " + DoubleToString(bal, 2) + " USD (" + (pct >= 0 ? "+" : "") + DoubleToString(pct, 2) + "%)\n";
   msg += "Max loss/balance (since EA attach): " + DoubleToString(maxLossUSD, 2) + "/" + DoubleToString(globalMinBalance, 2) + " (USD)\n";
   msg += "Max lot/total open (since EA attach): " + DoubleToString(globalMaxSingleLot, 2) + "/" + DoubleToString(globalTotalLotAtMaxLot, 2);
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
      if(ticket > 0 && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         trade.PositionClose(ticket);
   }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0 && OrderGetInteger(ORDER_MAGIC) == MagicNumber)
         trade.OrderDelete(ticket);
   }
}

//+------------------------------------------------------------------+
//| Cancel Buy Stop below base / Sell Stop above base when restriction is on |
//+------------------------------------------------------------------+
void CancelStopOrdersOutsideBaseZone()
{
   if(!BuyStopOnlyAboveBase && !SellStopOnlyBelowBase)
      return;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket <= 0 || OrderGetInteger(ORDER_MAGIC) != MagicNumber || OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      double price = OrderGetDouble(ORDER_PRICE_OPEN);
      if(BuyStopOnlyAboveBase && ot == ORDER_TYPE_BUY_STOP && price < basePrice)
         trade.OrderDelete(ticket);
      else if(SellStopOnlyBelowBase && ot == ORDER_TYPE_SELL_STOP && price > basePrice)
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
      if(ticket > 0 && OrderGetInteger(ORDER_MAGIC) == MagicNumber && OrderGetString(ORDER_SYMBOL) == _Symbol)
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
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      double pr = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      if(pr < 0)
         trade.PositionClose(ticket);
   }
}

//+------------------------------------------------------------------+
//| After setting SL: price above base -> close all Sells; below base -> close all Buys |
//+------------------------------------------------------------------+
void CloseOppositeSidePositions(bool closeSells)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
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
         if(PositionGetInteger(POSITION_MAGIC) != MagicNumber || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if(PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_BUY) continue;
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
         if(PositionGetInteger(POSITION_MAGIC) != MagicNumber || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if(PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_BUY) continue;
         double curSL = PositionGetDouble(POSITION_SL);
         double curTP = PositionGetDouble(POSITION_TP);
         if(slBuyA > curSL && slBuyA < bid)
            trade.PositionModify(ticket, slBuyA, curTP);
      }
      lastSellTrailPrice = 0.0;
      CloseOppositeSidePositions(true);
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
         if(PositionGetInteger(POSITION_MAGIC) != MagicNumber || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if(PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_SELL) continue;
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
         if(PositionGetInteger(POSITION_MAGIC) != MagicNumber || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if(PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_SELL) continue;
         double curSL = PositionGetDouble(POSITION_SL);
         double curTP = PositionGetDouble(POSITION_TP);
         if((curSL <= 0 || slSellA < curSL) && slSellA > ask)
            trade.PositionModify(ticket, slSellA, curTP);
      }
      lastBuyTrailPrice = 0.0;
      CloseOppositeSidePositions(false);
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
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != MagicNumber)
      return;
   long dealTime = (long)HistoryDealGetInteger(trans.deal, DEAL_TIME);
   if(lastResetTime > 0 && dealTime >= lastResetTime && dealTime <= lastResetTime + 15)
      return;
   
   sessionClosedProfit += HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                        + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                        + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
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
//| Bậc lưới: trên đường gốc = +1,+2,...+n; dưới = -1,-2,...-n.      |
//+------------------------------------------------------------------+
int GetLevelNumberFromIndex(int levelIndex)
{
   if(levelIndex < MaxGridLevels)
      return levelIndex + 1;   // +1, +2, ... +n
   return -(levelIndex - MaxGridLevels + 1);   // -1, -2, ... -n
}

//+------------------------------------------------------------------+
//| Lot đầu tiên (bậc 1): MỖI LOẠI LỆNH TÍNH RIÊNG. Tăng theo % vốn    |
//| khi EnableScaleByAccountGrowth: lot = input × sessionMultiplier.   |
//| Sell Stop = LotSizeSellStop | Buy Stop = LotSizeBuyStop | ...      |
//+------------------------------------------------------------------+
double GetBaseLotForOrderType(ENUM_ORDER_TYPE orderType)
{
   double lot = LotSizeBuyLimit;
   if(orderType == ORDER_TYPE_BUY_LIMIT)  lot = LotSizeBuyLimit;
   else if(orderType == ORDER_TYPE_BUY_STOP)  lot = LotSizeBuyStop;
   else if(orderType == ORDER_TYPE_SELL_LIMIT) lot = LotSizeSellLimit;
   else if(orderType == ORDER_TYPE_SELL_STOP)  lot = LotSizeSellStop;
   return (EnableScaleByAccountGrowth) ? (lot * sessionMultiplier) : lot;
}

//+------------------------------------------------------------------+
//| Lot: Level 1 = fixed (input). Level 2+ = input * mult^(level-1)   |
//| Scale and mult per order type.                                    |
//+------------------------------------------------------------------+
double GetLotMultForOrderType(ENUM_ORDER_TYPE orderType)
{
   if(orderType == ORDER_TYPE_BUY_LIMIT)  return LotMultBuyLimit;
   if(orderType == ORDER_TYPE_BUY_STOP)   return LotMultBuyStop;
   if(orderType == ORDER_TYPE_SELL_LIMIT) return LotMultSellLimit;
   if(orderType == ORDER_TYPE_SELL_STOP)  return LotMultSellStop;
   return 1.0;
}

ENUM_LOT_SCALE GetLotScaleForOrderType(ENUM_ORDER_TYPE orderType)
{
   if(orderType == ORDER_TYPE_BUY_LIMIT)  return BuyLimitLotScale;
   if(orderType == ORDER_TYPE_BUY_STOP)   return BuyStopLotScale;
   if(orderType == ORDER_TYPE_SELL_LIMIT) return SellLimitLotScale;
   if(orderType == ORDER_TYPE_SELL_STOP)  return SellStopLotScale;
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
   if(orderType == ORDER_TYPE_BUY_LIMIT)  return TakeProfitPipsBuyLimit;
   if(orderType == ORDER_TYPE_BUY_STOP)   return TakeProfitPipsBuyStop;
   if(orderType == ORDER_TYPE_SELL_LIMIT) return TakeProfitPipsSellLimit;
   if(orderType == ORDER_TYPE_SELL_STOP)  return TakeProfitPipsSellStop;
   return 0;
}

//+------------------------------------------------------------------+
//| BB: Base lot (level 1). Separate params, same % capital scaling.  |
//+------------------------------------------------------------------+
double GetBaseLotForOrderTypeBB(bool isBuyStop)
{
   double lot = isBuyStop ? LotSizeBuyStopBB : LotSizeSellStopBB;
   return (EnableScaleByAccountGrowth) ? (lot * sessionMultiplier) : lot;
}

//+------------------------------------------------------------------+
//| BB: Lot for level. Same logic as AA, separate params.             |
//+------------------------------------------------------------------+
double GetLotForLevelBB(bool isBuyStop, int levelNum)
{
   int absLevel = MathAbs(levelNum);
   double baseLot = GetBaseLotForOrderTypeBB(isBuyStop);
   double lot = baseLot;
   if(absLevel <= 1 || BBLotScale == LOT_FIXED)
      lot = baseLot;
   else if(BBLotScale == LOT_GEOMETRIC)
      lot = baseLot * MathPow(LotMultBB, absLevel - 1);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathMax(minLot, MathMin(maxLot, lot));
   lot = MathFloor(lot / lotStep) * lotStep;
   if(lot < minLot) lot = minLot;
   return NormalizeDouble(lot, 2);
}

double GetTakeProfitPipsForOrderTypeBB(bool isBuyStop)
{
   return isBuyStop ? TakeProfitPipsBuyStopBB : TakeProfitPipsSellStopBB;
}

//+------------------------------------------------------------------+
//| Initialize level prices - evenly spaced using gridStep            |
//+------------------------------------------------------------------+
void InitializeGridLevels()
{
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
void ManageGridOrders()
{
   if(gongLaiMode)
      return;
   
   CancelStopOrdersOutsideBaseZone();
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double minDistance = gridStep * 0.5;
   
   // Iterate by level: 1 (closest to base), 2, 3, ... n (furthest)
   for(int levelNum = 1; levelNum <= MaxGridLevels; levelNum++)
   {
      // Above base: index = levelNum - 1
      int idxAbove = levelNum - 1;
      double levelAbove = gridLevels[idxAbove];
      if(MathAbs(levelAbove - currentPrice) >= minDistance)
      {
         if(levelAbove > currentPrice)
         {
            if(EnableBuyStop && (!BuyStopOnlyAboveBase || levelAbove >= basePrice))
               EnsureOrderAtLevel(ORDER_TYPE_BUY_STOP, levelAbove, +levelNum);
            if(EnableBB)
               EnsureOrderAtLevelBB(true, levelAbove, +levelNum);
            if(EnableSellLimit)
               EnsureOrderAtLevel(ORDER_TYPE_SELL_LIMIT, levelAbove, +levelNum);
         }
      }
      
      // Below base: index = MaxGridLevels + levelNum - 1
      int idxBelow = MaxGridLevels + levelNum - 1;
      double levelBelow = gridLevels[idxBelow];
      if(MathAbs(levelBelow - currentPrice) >= minDistance)
      {
         if(levelBelow < currentPrice)
         {
            if(EnableBuyLimit)
               EnsureOrderAtLevel(ORDER_TYPE_BUY_LIMIT, levelBelow, -levelNum);
            if(EnableSellStop && (!SellStopOnlyBelowBase || levelBelow <= basePrice))
               EnsureOrderAtLevel(ORDER_TYPE_SELL_STOP, levelBelow, -levelNum);
            if(EnableBB)
               EnsureOrderAtLevelBB(false, levelBelow, -levelNum);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Ensure order at level - create if missing                          |
//+------------------------------------------------------------------+
void EnsureOrderAtLevel(ENUM_ORDER_TYPE orderType, double priceLevel, int levelNum)
{
   ulong  ticket       = 0;
   double existingPrice = 0.0;
   if(GetPendingOrderAtLevel(orderType, priceLevel, ticket, existingPrice))
   {
      double desiredPrice = NormalizeDouble(priceLevel, dgt);
      if(MathAbs(existingPrice - desiredPrice) > (pnt / 2.0))
         AdjustPendingOrderToLevel(ticket, orderType, priceLevel);
      return;
   }
   
   if(!CanPlaceOrderAtLevel(orderType, priceLevel))
      return;
   
   PlacePendingOrder(orderType, priceLevel, levelNum);
}

//+------------------------------------------------------------------+
//| BB: Ensure order at level - Buy Stop above, Sell Stop below       |
//+------------------------------------------------------------------+
void EnsureOrderAtLevelBB(bool isBuyStop, double priceLevel, int levelNum)
{
   ulong ticket = 0;
   double existingPrice = 0.0;
   if(GetPendingOrderAtLevel(isBuyStop ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP, priceLevel, ticket, existingPrice, CommentOrderBB))
   {
      double desiredPrice = NormalizeDouble(priceLevel, dgt);
      if(MathAbs(existingPrice - desiredPrice) > (pnt / 2.0))
         AdjustPendingOrderToLevel(ticket, isBuyStop ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP, priceLevel, GetTakeProfitPipsForOrderTypeBB(isBuyStop));
      return;
   }
   if(!CanPlaceOrderAtLevel(isBuyStop ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP, priceLevel, true))
      return;
   PlacePendingOrderBB(isBuyStop, priceLevel, levelNum);
}

//+------------------------------------------------------------------+
//| Find pending order on same side near level. filterComment: ""=AA,  |
//| CommentOrderBB=BB.                                                |
//+------------------------------------------------------------------+
bool GetPendingOrderAtLevel(ENUM_ORDER_TYPE orderType,
                            double priceLevel,
                            ulong &ticket,
                            double &orderPrice,
                            string filterComment = "")
{
   double tolerance = gridStep * 0.5;
   bool   isBuySide = (orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_BUY_STOP);
   string matchComment = (filterComment == "") ? CommentOrder : filterComment;

   for(int i = 0; i < OrdersTotal(); i++)
   {
      ulong t = OrderGetTicket(i);
      if(t <= 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber || OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if(StringFind(OrderGetString(ORDER_COMMENT), matchComment) != 0)
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
//| Adjust pending order to grid level. tpPipsOverride: -1=use AA/BB default |
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
//| Check if order or position exists at level                        |
//+------------------------------------------------------------------+
bool OrderOrPositionExistsAtLevel(ENUM_ORDER_TYPE orderType, double priceLevel)
{
   double tolerance = gridStep * 0.5;  // half grid step
   bool isBuyOrder = (orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_BUY_STOP);
   
   // Check pending orders
   for(int i = 0; i < OrdersTotal(); i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
      {
         if(OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
            OrderGetString(ORDER_SYMBOL) == _Symbol)
         {
            double orderPrice = OrderGetDouble(ORDER_PRICE_OPEN);
            if(MathAbs(orderPrice - priceLevel) < tolerance)
            {
               ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
               bool isOrderBuy = (ot == ORDER_TYPE_BUY_LIMIT || ot == ORDER_TYPE_BUY_STOP);
               
               if(isBuyOrder == isOrderBuy)
                  return true;
            }
         }
      }
   }
   
   // Check open positions
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            double posPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            if(MathAbs(posPrice - priceLevel) < tolerance)
            {
               ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
               bool isPosBuy = (pt == POSITION_TYPE_BUY);
               
               if(isBuyOrder == isPosBuy)
                  return true;
            }
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check if order can be placed at level (grid balance).             |
//| allowSecondOnSide: true for BB (max 2 Buy above / 2 Sell below).   |
//+------------------------------------------------------------------+
bool CanPlaceOrderAtLevel(ENUM_ORDER_TYPE orderType, double priceLevel, bool allowSecondOnSide = false)
{
   double tolerance = gridStep * 0.5;
   bool isBuyOrder = (orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_BUY_STOP);
   bool levelAbove = (priceLevel > basePrice);
   int maxBuy = (levelAbove && (EnableBB || allowSecondOnSide)) ? 2 : 1;
   int maxSell = (!levelAbove && (EnableBB || allowSecondOnSide)) ? 2 : 1;
   int buyCount = 0, sellCount = 0;

   for(int i = 0; i < OrdersTotal(); i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket <= 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber || OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      double orderPrice = OrderGetDouble(ORDER_PRICE_OPEN);
      if(MathAbs(orderPrice - priceLevel) >= tolerance) continue;
      ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(ot == ORDER_TYPE_BUY_LIMIT || ot == ORDER_TYPE_BUY_STOP) buyCount++;
      else if(ot == ORDER_TYPE_SELL_LIMIT || ot == ORDER_TYPE_SELL_STOP) sellCount++;
   }
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      double posPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      if(MathAbs(posPrice - priceLevel) >= tolerance) continue;
      ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(pt == POSITION_TYPE_BUY) buyCount++;
      else if(pt == POSITION_TYPE_SELL) sellCount++;
   }
   if(isBuyOrder && buyCount >= maxBuy) return false;
   if(!isBuyOrder && sellCount >= maxSell) return false;
   return true;
}

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
      if(orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_BUY_STOP)
         tp = NormalizeDouble(price + tpPips * pnt * 10.0, dgt);
      else
         tp = NormalizeDouble(price - tpPips * pnt * 10.0, dgt);
   }
   
   string cmt = CommentOrder + " " + (levelNum > 0 ? "+" : "") + IntegerToString(levelNum);
   bool result = false;
   if(orderType == ORDER_TYPE_BUY_LIMIT)
      result = trade.BuyLimit(lot, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);
   else if(orderType == ORDER_TYPE_SELL_LIMIT)
      result = trade.SellLimit(lot, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);
   else if(orderType == ORDER_TYPE_BUY_STOP)
      result = trade.BuyStop(lot, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);
   else if(orderType == ORDER_TYPE_SELL_STOP)
      result = trade.SellStop(lot, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);
   
   if(result)
      Print("Order placed: ", EnumToString(orderType), " at ", price, " lot ", lot, " (bậc ", levelNum > 0 ? "+" : "", levelNum, ")");
   else
      Print("Order error: ", EnumToString(orderType), " | Error: ", GetLastError());
}

//+------------------------------------------------------------------+
//| BB: Place pending order (Buy Stop or Sell Stop only)              |
//+------------------------------------------------------------------+
void PlacePendingOrderBB(bool isBuyStop, double priceLevel, int levelNum)
{
   double price = NormalizeDouble(priceLevel, dgt);
   double lot   = GetLotForLevelBB(isBuyStop, levelNum);
   double sl = 0, tp = 0;
   double tpPips = GetTakeProfitPipsForOrderTypeBB(isBuyStop);
   if(tpPips > 0)
   {
      if(isBuyStop)
         tp = NormalizeDouble(price + tpPips * pnt * 10.0, dgt);
      else
         tp = NormalizeDouble(price - tpPips * pnt * 10.0, dgt);
   }
   string cmt = CommentOrderBB + " " + (levelNum > 0 ? "+" : "") + IntegerToString(levelNum);
   bool result = false;
   if(isBuyStop)
      result = trade.BuyStop(lot, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);
   else
      result = trade.SellStop(lot, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);
   if(result)
      Print("Order placed BB: ", isBuyStop ? "BuyStop" : "SellStop", " at ", price, " lot ", lot, " (bậc ", levelNum > 0 ? "+" : "", levelNum, ")");
   else
      Print("Order error BB: ", isBuyStop ? "BuyStop" : "SellStop", " | Error: ", GetLastError());
}
//+------------------------------------------------------------------+
