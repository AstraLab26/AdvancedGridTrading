//+------------------------------------------------------------------+
//|                                         AdvancedGridTrading.mq5   |
//|              Advanced Grid Trading EA - Pro edition              |
//+------------------------------------------------------------------+
#property copyright "Advanced Grid EA"
#property version   "2.07"
#property description "Advanced Grid Trading EA: per-order lot, scale by capital, trailing profit, session reset"
// Telegram: Add https://api.telegram.org to Tools -> Options -> Expert Advisors -> Allow WebRequest for listed URL

#include <Trade\Trade.mqh>

//--- Lot scale: 0=Fixed, 2=Geometric. Level 1 = LotSize; level 2+ = multiplier.
enum ENUM_LOT_SCALE { LOT_FIXED = 0, LOT_GEOMETRIC = 2 };

//--- Trailing: when profit drops (Lock = close all + reset; Return = exit trailing, replace pending, no close no reset)
enum ENUM_TRAILING_DROP_MODE { TRAILING_MODE_LOCK = 0,      // Lock: profit drops X% from peak -> close all and reset
                               TRAILING_MODE_RETURN = 1 };  // Return: profit drops to threshold -> exit trailing, replace pending

#define BALANCE_THRESHOLD_USD_DEFAULT 20.0   // Balance AA/BB/CC: threshold USD (pool + loss >= this)
#define BALANCE_COOLDOWN_SEC_DEFAULT 300     // Balance: cooldown (seconds) after close; 0=none
#define BALANCE_PREPARE_LEVELS  3            // Min grid levels from base to select farthest opposite order (prepare only)
#define BALANCE_EXECUTE_LEVELS  5            // Min grid levels from base to actually close (pool must be enough)
#define COMMENT_BALANCE_PREPARE_TAG " | BP"  // Appended to CommentOrder on order selected for balance prepare (pending)
#define OBJ_PREFIX_BALANCE_PREPARE "EA_BP_" // Chart object prefix for position prepare mark (position comment not modifiable)

//+------------------------------------------------------------------+
//| 1. GRID                                                           |
//+------------------------------------------------------------------+
input group "=== 1. GRID ==="
input double GridDistancePips = 2000.0;         // Grid distance (pips)
input int MaxGridLevels = 40;                   // Max grid levels per side (above/below base line)

//+------------------------------------------------------------------+
//| 2. ORDERS                                                          |
//+------------------------------------------------------------------+
input group "=== 2. ORDERS ==="

input group "--- 2.1 Common (Magic & Comment) ---"
input int MagicNumber = 123456;                // Magic Number (AA=this, BB=this+1, CC=this+2, DD=this+3)
input string CommentOrder = "EA Grid";          // Order comment (same for all)

input group "--- 2.2 AA (settings) ---"
input bool EnableAA = true;                     // Enable AA (Buy Stop + Sell Stop)
input double LotSizeAA = 0.05;                  // AA: Lot size level 1
input ENUM_LOT_SCALE AALotScale = LOT_GEOMETRIC; // AA: Fixed / Geometric
input double LotMultAA = 1.3;                   // AA: Lot multiplier for level 2+ (Geometric)
input double MaxLotAA = 1.5;                    // AA: Max lot per order (0=no limit)
input double TakeProfitPipsAA = 0.0;           // AA: Take profit (pips; 0=off)
input bool EnableBalanceAAByBB = true;         // AA: Balance when (pool + loss) >= 20 USD; cooldown 300s. Prepare at 3 levels, execute at 5

input group "--- 2.3 BB (settings) ---"
input bool EnableBB = true;                     // Enable BB (Buy Stop + Sell Stop)
input double LotSizeBB = 0.05;                  // BB: Lot size level 1
input ENUM_LOT_SCALE BBLotScale = LOT_GEOMETRIC; // BB: Fixed / Geometric
input double LotMultBB = 1.3;                   // BB: Lot multiplier for level 2+ (Geometric)
input double MaxLotBB = 1.5;                    // BB: Max lot per order (0=no limit)
input double TakeProfitPipsBB = 2000.0;         // BB: Take profit (pips; 0=off)
input bool EnableBalanceBB = true;              // BB: Balance when (pool + loss) >= 20 USD; cooldown 300s. Prepare at 3 levels, execute at 5

input group "--- 2.4 CC (settings) ---"
input bool EnableCC = true;                      // Enable CC (Buy Stop + Sell Stop)
input double LotSizeCC = 0.05;                    // CC: Lot size level 1
input ENUM_LOT_SCALE CCLotScale = LOT_FIXED;     // CC: Fixed / Geometric
input double LotMultCC = 1.3;                    // CC: Lot multiplier for level 2+ (Geometric)
input double MaxLotCC = 2.0;                     // CC: Max lot per order (0=no limit)
input double TakeProfitPipsCC = 2000.0;          // CC: Take profit (pips; 0=off)
input bool EnableBalanceCC = true;               // CC: Balance when (pool + loss) >= 20 USD; cooldown 300s. Prepare at 3 levels, execute at 5

input group "--- 2.5 DD (settings) ---"
input bool EnableDD = true;                       // Enable DD (Sell Limit above base + Buy Limit below base; no balance)
input double LotSizeDD = 0.01;                   // DD: Lot size level 1
input ENUM_LOT_SCALE DDLotScale = LOT_FIXED;      // DD: Fixed / Geometric
input double LotMultDD = 1.3;                    // DD: Lot multiplier for level 2+ (Geometric)
input double MaxLotDD = 0.01;                    // DD: Max lot per order (0=no limit)
input double TakeProfitPipsDD = 2000.0;          // DD: Take profit (pips; 0=off)

//+------------------------------------------------------------------+
//| 3. SESSION: Trailing profit (open orders only)                    |
//+------------------------------------------------------------------+
input group "=== 3. SESSION: Trailing profit ==="
input bool EnableTrailingTotalProfit = true;    // Enable trailing: cancel pending, move SL when open profit >= threshold
input double TrailingThresholdUSD = 200.0;       // Start trailing when open profit >= (USD)
input ENUM_TRAILING_DROP_MODE TrailingDropMode = TRAILING_MODE_RETURN;  // When profit drops: Lock profit | Return to initial
input double TrailingDropPct = 20.0;           // % (both modes): trigger when profit drops X%. E.g. threshold 100 USD, 20% = trigger when drops to 80 USD
input double TrailingPointAPips = 1500.0;       // Point A (pips): base = grid level closest to price at threshold. Buy: A = base + X pip; Sell: A = base - X pip. SL at A then trail by step
input double GongLaiStepPips = 1000.0;          // Pips: trailing step (price moves 1 step -> SL trails 1 step)
input bool EnableResetAtBreakevenWhenNearBase = false;  // Breakeven cut: max open level >= X levels and (open USD + closed TP minus lock) >= 0 -> Reset. Current session only
input int ResetBreakevenMaxLevelsFromBase = 10;        // Min grid levels from base for open positions to apply breakeven reset (>= X levels)

//+------------------------------------------------------------------+
//| 4. CAPITAL % SCALING                                               |
//+------------------------------------------------------------------+
input group "=== 4. CAPITAL % SCALING ==="
input bool EnableScaleByAccountGrowth = true;   // Scale lot, TP, SL, trailing by % capital growth
input double BaseCapitalUSD = 50000.0;         // Base capital (USD): 0=balance when EA attached; >0=use this value
input double AccountGrowthScalePct = 50.0;     // x% (max 100): capital +100% vs base -> multiply by x%
input double MaxScaleIncreasePct = 100.0;      // Max increase % for lot/functions (0=no limit). E.g. 100 = lot/functions increase max 100%, mult capped at 2.0

//+------------------------------------------------------------------+
//| 5. NOTIFICATIONS                                                    |
//+------------------------------------------------------------------+
input group "=== 5. NOTIFICATIONS ==="
input bool EnableResetNotification = true;     // Send notification when EA resets or stops
input group "--- 5.1 Telegram ---"
input bool EnableTelegram = false;              // Send notifications to Telegram group
input string TelegramBotToken = "";             // Bot Token (from @BotFather)
input string TelegramChatID = "";               // Group Chat ID (negative number, e.g. -1001234567890)

input group "=== 6. LOCK PROFIT (Save %) ==="
input bool EnableLockProfit = true;            // Lock profit: reserve X% of each profitable TP close (AA, BB, CC, DD); reserved amount is not used for balance pool
input double LockProfitPct = 25.0;             // Lock this % of each profitable close (e.g. 25 = reserve 25 USD from 100 USD profit); 0-100

//--- Global variables
CTrade trade;
double pnt;
int dgt;
double basePrice;                               // Base price (base line)
double gridLevels[];                            // Array of level prices (evenly spaced by GridDistancePips)
double gridStep;                                // One grid step (price) = GridDistancePips, used for tolerance/snap
// Pool = TP profit in current session minus lock (AA+BB+CC+DD). Used for balance AA/BB/CC only (DD is not balanced).
double sessionClosedProfit = 0.0;               // Session: (TP profit - lock) in session. Reset on EA reset. Shared balance pool.
double sessionLockedProfit = 0.0;               // Locked profit in current session. Reset on EA reset.
double sessionClosedProfitBB = 0.0;            // BB closed P/L in session (after lock). Internal use.
double sessionClosedProfitCC = 0.0;             // CC closed P/L in session (after lock). Internal use.
double sessionClosedProfitDD = 0.0;            // DD closed P/L in session (after lock). Internal use; DD TP is in pool but DD is not balanced.
double sessionClosedProfitRemaining = 0.0;      // Pool remaining in tick (after closing losing AA/BB/CC). Each tick = sessionClosedProfit.
datetime lastResetTime = 0;                     // Last reset time (avoid double-count from orders just closed on reset)
bool eaStoppedByTarget = false;                 // true = EA stopped placing new orders (Stop mode)
double balanceGoc = 0.0;                       // Base capital for scaling (BaseCapitalUSD or balance at attach)
double attachBalance = 0.0;                    // Balance when EA first attached: never reset. For "Initial balance at EA startup" and "Change vs initial"
double sessionMultiplier = 1.0;                // Lot and TP multiplier by % growth vs balanceGoc (1.0 = no change)
double sessionPeakProfit = 0.0;                // Session profit peak (for trailing profit lock)
bool gongLaiMode = false;                      // true = trailing threshold reached, pendings cancelled, only trail SL on open positions
bool trailingSLPlaced = false;                // SL already placed (at point A or trailed). Return mode only allowed when SL not yet placed.
double lastBuyTrailPrice = 0.0;                // Last price when SL Buy was updated (trailing step)
double lastSellTrailPrice = 0.0;               // Last price when SL Sell was updated (trailing step)
double pointABaseLevel = 0.0;                 // Grid level chosen for point A (was used for yellow line draw)
double trailingGocBuy = 0.0;                 // Buy base fixed at trailing threshold (grid level below price, closest)
double trailingGocSell = 0.0;                // Sell base fixed at threshold (grid level above price, closest)
double sessionPeakBalance = 0.0;               // Highest balance in session (for notification)
double sessionMinBalance = 0.0;                // Lowest balance in session (max drawdown)
double globalPeakBalance = 0.0;                // Highest balance since EA attach (not reset)
double globalMinBalance = 0.0;                 // Lowest balance since EA attach = equity at max drawdown (not reset)
double sessionMaxSingleLot = 0.0;              // Largest single position lot in session
double sessionTotalLotAtMaxLot = 0.0;         // Total open lot when that max single lot occurred
double globalMaxSingleLot = 0.0;              // Largest single lot since EA attach (not reset)
double globalTotalLotAtMaxLot = 0.0;          // Total open lot at that time since EA attach (not reset)
datetime sessionStartTime = 0;                // Current session: starts when EA attached or EA reset. Only P/L and orders from this time.
double sessionStartBalance = 0.0;             // Balance at session start (for info panel and session %)
int MagicAA = 0;                              // AA orders magic (set in OnInit)
int MagicBB = 0;                              // BB orders magic (MagicNumber+1)
int MagicCC = 0;                              // CC orders magic (MagicNumber+2)
int MagicDD = 0;                              // DD orders magic (MagicNumber+3)
datetime lastBalanceBBCloseTime = 0;          // Last time we closed losing BB (for cooldown)
datetime lastBalanceCCCloseTime = 0;          // Last time we closed losing CC (for cooldown)
datetime lastBalanceAAByBBCloseTime = 0;     // Last time we closed AA by BB balance (for cooldown)
ulong balancePreparedTicket = 0;             // Ticket selected for balance (farthest opposite); cleared if price returns to base
int balancePrepareDirection = 0;             // 0=none, +1=price above base (prepare Sells below), -1=price below base (prepare Buys above)
double balanceSelectedLevelPrice = 0.0;      // Ghi nhớ: mức giá bậc lưới được chọn cho cân bằng (chỉ đóng lệnh tại bậc này)
ulong balanceSelectedTickets[];              // Đánh dấu: danh sách ticket lệnh được chọn để chuẩn bị cân bằng (1 bậc xa nhất)
ulong balanceMarkedTickets[];                // Legacy: dùng khi clear chart objects
// Locked profit cumulative across sessions, never reset. This $ lock not used for balance (pool = TP in session - lock in session).
double lockedProfitReserve = 0.0;            // Locked profit (X% of each profitable TP close); cumulative; not used for balance pool

//+------------------------------------------------------------------+
//| True if magic belongs to this EA (AA, BB or CC)                    |
//+------------------------------------------------------------------+
bool IsOurMagic(long magic)
{
   return (magic == MagicAA || magic == MagicBB || magic == MagicCC || magic == MagicDD);
}

//+------------------------------------------------------------------+
//| Swap helpers for sort by distance                                |
//+------------------------------------------------------------------+
void SwapDouble(double &a, double &b) { double t = a; a = b; b = t; }
void SwapULong(ulong &a, ulong &b) { ulong t = a; a = b; b = t; }

//+------------------------------------------------------------------+
//| Position P/L = profit + swap (overnight fee). Commission only when position closed (in DEAL). |
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
   MagicDD = MagicNumber + 3;
   trade.SetExpertMagicNumber(MagicAA);
   dgt = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   pnt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   basePrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);   // Khi khởi động: đường gốc = giá hiện tại
   sessionClosedProfit = 0.0;
   sessionLockedProfit = 0.0;
   sessionClosedProfitBB = 0.0;
   sessionClosedProfitCC = 0.0;
   sessionClosedProfitDD = 0.0;
   lastBalanceBBCloseTime = 0;
   lastBalanceCCCloseTime = 0;
   lastBalanceAAByBBCloseTime = 0;
   balanceSelectedLevelPrice = 0.0;
   ArrayResize(balanceSelectedTickets, 0);
   ArrayResize(balanceMarkedTickets, 0);
   lastResetTime = 0;
   eaStoppedByTarget = false;
   balanceGoc = (BaseCapitalUSD > 0) ? BaseCapitalUSD : AccountInfoDouble(ACCOUNT_BALANCE);
   attachBalance = AccountInfoDouble(ACCOUNT_BALANCE);   // Initial capital: balance when EA is first added (for panel only)
   sessionMultiplier = 1.0;
   UpdateSessionMultiplierFromAccountGrowth();
   sessionPeakProfit = 0.0;
   gongLaiMode = false;
   trailingGocBuy = 0.0;
   trailingGocSell = 0.0;
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
      Print("Trailing: open orders only. Start when profit >= ", TrailingThresholdUSD, " USD. Drop mode: ", EnumToString(TrailingDropMode), ", drop pct: ", TrailingDropPct, "%.");
   if(EnableAA && EnableBalanceAAByBB)
      Print("Balance AA by BB: close 1 losing AA when (BB closed + that AA loss) >= ", BALANCE_THRESHOLD_USD_DEFAULT, " USD. Session only. Price 5 levels. Cooldown ", BALANCE_COOLDOWN_SEC_DEFAULT, "s.");
   if(EnableBB && EnableBalanceBB)
      Print("Balance BB: when (BB closed + BB open opposite side) >= ", BALANCE_THRESHOLD_USD_DEFAULT, " USD, close losing BB on that side.");
   if(EnableCC && EnableBalanceCC)
      Print("Balance CC: when (CC closed + CC open opposite side) >= ", BALANCE_THRESHOLD_USD_DEFAULT, " USD, close losing CC on that side.");
   if(EnableLockProfit && LockProfitPct > 0)
      Print("Lock profit: ", LockProfitPct, "% of each profitable close (AA, BB, CC, DD) is reserved; this amount is not counted in balance pool.");
   if(EnableScaleByAccountGrowth)
      Print("Base capital = ", balanceGoc, " USD", BaseCapitalUSD > 0 ? " (manual)" : " (balance at attach)", ". Lot/TP/SL/Trailing x ", AccountGrowthScalePct, "% growth. mult=", sessionMultiplier);
   if(EnableAA)
      Print("AA (BuyStop+SellStop) L1,L2,L3: ", GetLotForLevel(ORDER_TYPE_BUY_STOP,1), ",", GetLotForLevel(ORDER_TYPE_BUY_STOP,2), ",", GetLotForLevel(ORDER_TYPE_BUY_STOP,3));
   if(EnableBB)
      Print("BB (BuyStop+SellStop) L1,L2,L3: ", GetLotForLevelBB(true,1), ",", GetLotForLevelBB(true,2), ",", GetLotForLevelBB(true,3));
   if(EnableCC)
      Print("CC (BuyStop+SellStop) L1,L2,L3: ", GetLotForLevelCC(true,1), ",", GetLotForLevelCC(true,2), ",", GetLotForLevelCC(true,3));
   if(EnableDD)
      Print("DD (SellLimit above + BuyLimit below) L1,L2,L3: ", GetLotForLevelDD(true,1), ",", GetLotForLevelDD(true,2), ",", GetLotForLevelDD(true,3));
   Print("========================================");
   // Thêm lệnh chờ các loại (AA, BB, CC, DD theo input) từ bậc 1, bậc 2, ... bậc N
   ManageGridOrders();
   DrawBaseLine();
   DrawSessionStartLine();   // Session start vertical line (no draw, delete only)
   DrawRealtimeLine();       // Realtime vertical line (no draw, delete only)
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(EnableResetNotification || EnableTelegram)
   {
      UpdateSessionStatsForNotification();
      SendResetNotification("EA stopped (reason: " + IntegerToString(reason) + ")");
   }
   DeleteCapitalGrowthLabel();
   ObjectsDeleteAll(0, OBJ_PREFIX_BALANCE_PREPARE);
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
   
   // Trailing: only count open positions of current session (opened after sessionStartTime)
   double floating = 0.0;
   if(EnableTrailingTotalProfit)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0 || !IsOurMagic(PositionGetInteger(POSITION_MAGIC)) || PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;
         if(sessionStartTime > 0 && (datetime)PositionGetInteger(POSITION_TIME) < sessionStartTime)
            continue;   // Skip positions opened before current session
         floating += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      }
   }
   double totalForTrailing = floating;
   double effectiveTrailingThreshold = (EnableScaleByAccountGrowth && TrailingThresholdUSD > 0) ? (TrailingThresholdUSD * sessionMultiplier) : TrailingThresholdUSD;
   
   if(EnableTrailingTotalProfit && TrailingThresholdUSD > 0)
   {
      if(totalForTrailing >= effectiveTrailingThreshold)
      {
         if(!gongLaiMode)
         {
            gongLaiMode = true;
            trailingSLPlaced = false;   // SL not placed yet; Return mode can exit trailing when profit drops
            CancelAllPendingOrders();
            RemoveTPFromAllSessionPositions();   // Remove TP from all open positions (current session)
            Print("Trailing: open profit ", totalForTrailing, " USD (>= ", effectiveTrailingThreshold, "). Pending cancelled, TP removed, trailing SL (point A) started.");
         }
         if(totalForTrailing > sessionPeakProfit)
            sessionPeakProfit = totalForTrailing;
      }
      // Both modes: trigger when profit drops X%. dropLevel = trailing threshold * (1 - X%). E.g. 100 USD, 10% -> trigger at 90 USD
      if(gongLaiMode && TrailingDropPct > 0)
      {
         double pct = MathMax(0.0, MathMin(100.0, TrailingDropPct));
         double dropLevel = effectiveTrailingThreshold * (1.0 - pct / 100.0);   // e.g. 100 USD, 10% -> 90 USD
         if(totalForTrailing <= dropLevel)
         {
            if(TrailingDropMode == TRAILING_MODE_RETURN)
            {
               // Return only when SL not yet placed. Once SL placed, do not exit trailing (wait for SL hit).
               // After exit: when profit reaches threshold again, trailing logic restarts (cancel pending, remove TP, trail from point A...).
               if(!trailingSLPlaced)
               {
                  gongLaiMode = false;
   trailingGocBuy = 0.0;
   trailingGocSell = 0.0;
                  trailingSLPlaced = false;
                  sessionPeakProfit = 0.0;
                  lastBuyTrailPrice = 0.0;
                  lastSellTrailPrice = 0.0;
                  Print("Trailing return: profit ", totalForTrailing, " USD <= drop level ", dropLevel, " (SL not placed). Exit trailing, re-place pending. When profit reaches threshold again, trailing will restart.");
               }
            }
            else if(TrailingDropMode == TRAILING_MODE_LOCK)
            {
               // SL not placed: on drop threshold reset EA (close all, new session). SL placed: do not reset on drop, only trail (reset when SL hit).
               if(!trailingSLPlaced)
               {
                  CloseAllPositionsAndOrders();
                  UpdateSessionMultiplierFromAccountGrowth();
                  lastResetTime = TimeCurrent();
                  sessionClosedProfit = 0.0;
                  sessionLockedProfit = 0.0;
                  sessionClosedProfitBB = 0.0;
                  sessionClosedProfitCC = 0.0;
                  sessionClosedProfitDD = 0.0;
                  lastBalanceBBCloseTime = 0;
                  lastBalanceCCCloseTime = 0;
                  lastBalanceAAByBBCloseTime = 0;
                  sessionPeakProfit = 0.0;
                  gongLaiMode = false;
                  trailingGocBuy = 0.0;
                  trailingGocSell = 0.0;
                  trailingSLPlaced = false;
                  lastBuyTrailPrice = 0.0;
                  lastSellTrailPrice = 0.0;
                  ClearBalanceSelection();
                  balancePrepareDirection = 0;
                  basePrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                  InitializeGridLevels();
                  DrawBaseLine();
                  DrawSessionStartLine();
                  Print("Trailing profit: lock (SL not placed, profit ", totalForTrailing, " USD <= drop ", dropLevel, "). Reset EA, new session.");
                  if(EnableResetNotification) { SendResetNotification("Trailing profit"); double b = AccountInfoDouble(ACCOUNT_BALANCE); sessionPeakBalance = b; sessionMinBalance = b; sessionMaxSingleLot = 0; sessionTotalLotAtMaxLot = 0; }
                  return;
               }
               // SL placed: no reset, only trail (DoGongLaiTrailing); reset when price hits SL (posCount=0)
            }
         }
      }
   }
   
   // Breakeven cut: max open level >= X levels AND (open USD + closed TP minus lock) >= 0 -> EA Reset. Current session only.
   if(!gongLaiMode && EnableResetAtBreakevenWhenNearBase && ResetBreakevenMaxLevelsFromBase > 0 && ArraySize(gridLevels) > 0)
   {
      double openFloating = 0.0;   // P/L of open positions, current session only
      int maxLevelsFromBase = 0;
      int sessionPosCount = 0;
      for(int i = 0; i < PositionsTotal(); i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0 || !IsOurMagic(PositionGetInteger(POSITION_MAGIC)) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if(sessionStartTime > 0 && (datetime)PositionGetInteger(POSITION_TIME) < sessionStartTime) continue;
         sessionPosCount++;
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         openFloating += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         double dist = MathAbs(openPrice - basePrice);
         int lev = (int)MathRound(dist / gridStep);
         if(lev > maxLevelsFromBase) maxLevelsFromBase = lev;
      }
      int xLevels = MathMax(1, MathMin(MaxGridLevels, ResetBreakevenMaxLevelsFromBase));
      // sessionClosedProfit = TP closes in session minus lock (current session only)
      if(sessionPosCount > 0 && maxLevelsFromBase >= xLevels && (openFloating + sessionClosedProfit) >= 0.0)
      {
         CloseAllPositionsAndOrders();
         UpdateSessionMultiplierFromAccountGrowth();
         lastResetTime = TimeCurrent();
         sessionClosedProfit = 0.0;
         sessionLockedProfit = 0.0;
         sessionClosedProfitBB = 0.0;
         sessionClosedProfitCC = 0.0;
         sessionClosedProfitDD = 0.0;
         lastBalanceBBCloseTime = 0;
         lastBalanceCCCloseTime = 0;
         lastBalanceAAByBBCloseTime = 0;
         sessionPeakProfit = 0.0;
         gongLaiMode = false;
         trailingGocBuy = 0.0;
         trailingGocSell = 0.0;
         lastBuyTrailPrice = 0.0;
         lastSellTrailPrice = 0.0;
         ClearBalanceSelection();
         balancePrepareDirection = 0;
         basePrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         InitializeGridLevels();
         DrawBaseLine();
         DrawSessionStartLine();
         Print("Reset at breakeven: max level from base = ", maxLevelsFromBase, ", open+TP-lock >= 0. New base = ", basePrice);
         if(EnableResetNotification) { SendResetNotification("Breakeven"); double b = AccountInfoDouble(ACCOUNT_BALANCE); sessionPeakBalance = b; sessionMinBalance = b; sessionMaxSingleLot = 0; sessionTotalLotAtMaxLot = 0; }
         return;
      }
   }

   if(gongLaiMode)
   {
      int posCount = 0;   // Count only current session positions
      for(int i = 0; i < PositionsTotal(); i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         if(!IsOurMagic(PositionGetInteger(POSITION_MAGIC)) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if(sessionStartTime > 0 && (datetime)PositionGetInteger(POSITION_TIME) < sessionStartTime) continue;
         posCount++;
      }
      // When price reverses and hits SL -> all positions closed -> posCount=0 -> EA reset (new base, place orders)
      if(posCount == 0)
      {
         CloseAllPositionsAndOrders();
         UpdateSessionMultiplierFromAccountGrowth();
         lastResetTime = TimeCurrent();
         gongLaiMode = false;
         trailingGocBuy = 0.0;
         trailingGocSell = 0.0;
         trailingSLPlaced = false;
         pointABaseLevel = 0.0;
         lastBuyTrailPrice = 0.0;
         lastSellTrailPrice = 0.0;
         sessionClosedProfit = 0.0;
         sessionLockedProfit = 0.0;
         sessionClosedProfitBB = 0.0;
         sessionClosedProfitCC = 0.0;
         sessionClosedProfitDD = 0.0;
         lastBalanceBBCloseTime = 0;
         lastBalanceCCCloseTime = 0;
         lastBalanceAAByBBCloseTime = 0;
         sessionPeakProfit = 0.0;
         ClearBalanceSelection();
         balancePrepareDirection = 0;
         DrawPointABaseLine();
         basePrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         InitializeGridLevels();
         DrawBaseLine();
         DrawSessionStartLine();
         Print("Trailing: SL hit, all positions closed. EA reset, new base = ", basePrice, ". Placing orders again.");
         if(EnableResetNotification) { SendResetNotification("Trailing profit (SL hit)"); double b = AccountInfoDouble(ACCOUNT_BALANCE); sessionPeakBalance = b; sessionMinBalance = b; sessionMaxSingleLot = 0; sessionTotalLotAtMaxLot = 0; }
         ManageGridOrders();
      }
      else
         DoGongLaiTrailing();
   }

   // Point A line at chosen grid level (trailing only); delete when not trailing
   DrawPointABaseLine();
   // Realtime vertical dashed line
   DrawRealtimeLine();

   // Shared pool AA+BB+CC TP closes. Unified balance: close farthest (AA/BB/CC) first, then closer levels.
   sessionClosedProfitRemaining = sessionClosedProfit;
   DoBalanceAll();
   
   ManageGridOrders();
}

//+------------------------------------------------------------------+
//| On EA reset: update sessionMultiplier by account growth %         |
//| Capital +100%, scale 50% -> on reset, lot/TP/trailing scale +50%  |
//| Formula: mult = 1 + growth × (AccountGrowthScalePct/100)         |
//| Base capital = BaseCapitalUSD (if >0) or balance when EA attached. Compare to current balance. |
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
      double maxMult = (MaxScaleIncreasePct > 0) ? (1.0 + MaxScaleIncreasePct / 100.0) : 10.0;  // 0 = no limit (cap 10x)
      if(sessionMultiplier > maxMult) sessionMultiplier = maxMult;
      Print("Reset: capital ", balanceGoc, " -> ", newBalance, " (+", (growth*100), "%). Scale ", pct, "% -> Lot/TP/SL/Trailing x ", sessionMultiplier);
   }
}

void DeleteCapitalGrowthLabel()
{
   DeleteBaseLine();
   DeleteSessionStartLine();
   DeleteRealtimeLine();
   ChartRedraw(ChartID());
}

//+------------------------------------------------------------------+
//| Draw thin base line on chart at basePrice (no draw: only delete if exists) |
//+------------------------------------------------------------------+
void DrawBaseLine()
{
   long chartId = ChartID();
   if(ObjectFind(chartId, "GridBaseLine") >= 0)
      ObjectDelete(chartId, "GridBaseLine");
   ChartRedraw(chartId);
}

void DeleteBaseLine()
{
   ObjectDelete(ChartID(), "GridBaseLine");
}

//+------------------------------------------------------------------+
//| Draw vertical line at session start (EA start / reset). No draw: only delete if exists. |
//+------------------------------------------------------------------+
void DrawSessionStartLine()
{
   long chartId = ChartID();
   if(ObjectFind(chartId, "GridSessionStart") >= 0)
      ObjectDelete(chartId, "GridSessionStart");
   ChartRedraw(chartId);
}

void DeleteSessionStartLine()
{
   ObjectDelete(ChartID(), "GridSessionStart");
}

//+------------------------------------------------------------------+
//| Vertical dashed line at real time (updated each tick). No draw: only delete if exists. |
//+------------------------------------------------------------------+
void DrawRealtimeLine()
{
   long chartId = ChartID();
   if(ObjectFind(chartId, "GridRealtimeLine") >= 0)
      ObjectDelete(chartId, "GridRealtimeLine");
   ChartRedraw(chartId);
}

void DeleteRealtimeLine()
{
   ObjectDelete(ChartID(), "GridRealtimeLine");
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
//| URL encode for Telegram text                                       |
//+------------------------------------------------------------------+
string UrlEncodeForTelegram(const string s)
{
   string result = "";
   for(int i = 0; i < StringLen(s); i++)
   {
      ushort c = StringGetCharacter(s, i);
      if(c == ' ') result += "+";
      else if(c == '\n') result += "%0A";
      else if(c == '\r') result += "%0D";
      else if(c == '&') result += "%26";
      else if(c == '=') result += "%3D";
      else if(c == '+') result += "%2B";
      else if(c == '%') result += "%25";
      else if(c >= 32 && c < 127) result += CharToString((uchar)c);
      else result += "%" + StringFormat("%02X", c);
   }
   return result;
}

//+------------------------------------------------------------------+
//| Send message to Telegram via Bot. Add https://api.telegram.org to Allow WebRequest. |
//+------------------------------------------------------------------+
void SendTelegramMessage(const string msg)
{
   if(!EnableTelegram || StringLen(TelegramBotToken) < 10 || StringLen(TelegramChatID) < 5)
      return;
   string url = "https://api.telegram.org/bot" + TelegramBotToken + "/sendMessage";
   string body = "chat_id=" + TelegramChatID + "&text=" + UrlEncodeForTelegram(msg);
   char post[], result[];
   string resultHeaders;
   StringToCharArray(body, post, 0, StringLen(body));
   string headers = "Content-Type: application/x-www-form-urlencoded\r\n";
   ResetLastError();
   int res = WebRequest("POST", url, headers, 5000, post, result, resultHeaders);
   if(res != 200)
      Print("Telegram: WebRequest failed, res=", res, " err=", GetLastError(), ". Add https://api.telegram.org to Tools->Options->Expert Advisors->Allow WebRequest.");
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
   if(!EnableResetNotification && !EnableTelegram) return;
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int symDigits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   // Change % = vs balance when EA attached/started (attachBalance), NOT vs base capital (BaseCapitalUSD)
   double pct = (attachBalance > 0) ? ((bal - attachBalance) / attachBalance * 100.0) : 0;
   double maxLossUSD = globalPeakBalance - globalMinBalance;
   string msg = "EA RESET\n";
   msg += "Chart: " + _Symbol + "\n";
   msg += "Reason: " + reason + "\n";
   msg += "Price at reset: " + DoubleToString(bid, symDigits) + "\n\n";
   msg += "--- SETTINGS ---\n";
   msg += "Initial balance at EA startup: " + DoubleToString(attachBalance, 2) + " USD\n";
   if(BaseCapitalUSD == 0)
      msg += "Base capital (USD): 0 (use balance at attach)\n";
   else
      msg += "Base capital (USD): " + DoubleToString(BaseCapitalUSD, 2) + "\n";
   msg += "Capital scale %: " + DoubleToString(AccountGrowthScalePct, 1) + "%\n\n";
   msg += "--- CURRENT STATUS ---\n";
   msg += "Current balance: " + DoubleToString(bal, 2) + " USD\n";
   msg += "Change vs initial capital at EA startup: " + (pct >= 0 ? "+" : "") + DoubleToString(pct, 2) + "%\n";
   msg += "Max drawdown: " + DoubleToString(maxLossUSD, 2) + " USD\n";
   msg += "Lowest balance (since attach): " + DoubleToString(globalMinBalance, 2) + " USD\n";
   msg += "Locked profit (saved, cumulative): " + DoubleToString(lockedProfitReserve, 2) + " USD\n\n";
   msg += "--- FREE EA ---\n";
   msg += "Free MT5 automated trading EA.\n";
   msg += "Just register an account using this link: https://one.exnessonelink.com/a/iu0hffnbzb\n";
   msg += "After registering, send me your account ID to receive the EA.";
   if(EnableResetNotification)
      SendNotification(msg);
   SendTelegramMessage(msg);
}

//+------------------------------------------------------------------+
//| Check: losing position on opposite side of current price vs base (eligible for balance close) |
//+------------------------------------------------------------------+
bool IsLosingOppositeSidePosition(ulong ticket, bool priceAboveBase)
{
   if(ticket == 0 || !PositionSelectByTicket(ticket)) return false;
   if(!IsOurMagic(PositionGetInteger(POSITION_MAGIC)) || PositionGetString(POSITION_SYMBOL) != _Symbol) return false;
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double pr = GetPositionPnL(ticket);
   if(pr >= 0.0) return false;   // Only losing positions
   bool posBelowBase = (openPrice < basePrice);
   bool posAboveBase = (openPrice > basePrice);
   bool opposite = (priceAboveBase && posBelowBase) || (!priceAboveBase && posAboveBase);
   return opposite;
}

//+------------------------------------------------------------------+
//| Lock for balance: price above base -> lock Buy (do not close Buy); price below base -> lock Sell (do not close Sell). Avoid wrong close. |
//+------------------------------------------------------------------+
bool IsPositionLockedForBalance(ulong ticket, bool priceAboveBase)
{
   if(ticket == 0 || !PositionSelectByTicket(ticket)) return false;
   ulong posType = PositionGetInteger(POSITION_TYPE);
   // Price above base -> lock Buy; price below base -> lock Sell
   if(priceAboveBase && posType == POSITION_TYPE_BUY) return true;   // Do not close Buy
   if(!priceAboveBase && posType == POSITION_TYPE_SELL) return true;  // Do not close Sell
   return false;
}

//+------------------------------------------------------------------+
//| Close position with deal comment (used for balance: comment = "Balance order") |
//+------------------------------------------------------------------+
bool PositionCloseWithComment(ulong ticket, const string comment)
{
   if(ticket == 0 || !PositionSelectByTicket(ticket)) return false;
   ulong posType = PositionGetInteger(POSITION_TYPE);
   double vol = PositionGetDouble(POSITION_VOLUME);
   double price = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   ENUM_ORDER_TYPE closeType = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   MqlTradeRequest req = {};
   MqlTradeResult res = {};
   req.action = TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.volume = vol;
   req.type = closeType;
   req.position = ticket;
   req.price = price;
   req.deviation = 10;
   req.comment = comment;
   if(!OrderSend(req, res))
      return false;
   return (res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED);
}

bool PositionClosePartialWithComment(ulong ticket, double volumeClose, const string comment)
{
   if(ticket == 0 || volumeClose <= 0 || !PositionSelectByTicket(ticket)) return false;
   ulong posType = PositionGetInteger(POSITION_TYPE);
   double price = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   ENUM_ORDER_TYPE closeType = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   MqlTradeRequest req = {};
   MqlTradeResult res = {};
   req.action = TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.volume = volumeClose;
   req.type = closeType;
   req.position = ticket;
   req.price = price;
   req.deviation = 10;
   req.comment = comment;
   if(!OrderSend(req, res))
      return false;
   return (res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_PLACED);
}

//+------------------------------------------------------------------+
//| Strip balance prepare tag from comment if present                 |
//+------------------------------------------------------------------+
string CommentWithoutBalancePrepare(const string cmt)
{
   int p = StringFind(cmt, COMMENT_BALANCE_PREPARE_TAG);
   if(p >= 0)
      return StringSubstr(cmt, 0, p);
   return cmt;
}

//+------------------------------------------------------------------+
//| Clear prepare mark: delete chart label (only positions were marked) |
//+------------------------------------------------------------------+
void ClearBalancePrepareMark(ulong ticket)
{
   if(ticket == 0) return;
   string objName = OBJ_PREFIX_BALANCE_PREPARE + IntegerToString(ticket);
   if(ObjectFind(0, objName) >= 0)
      ObjectDelete(0, objName);
}

//+------------------------------------------------------------------+
//| Chart label: "Lệnh được chọn" + Comment hiển thị "Lệnh được chọn"  |
//| (Position comment không sửa được trong MT5 nên hiển thị trên nhãn)  |
//+------------------------------------------------------------------+
void SetBalancePrepareChartLabel(ulong ticket, double priceLevel, datetime timeVal)
{
   string objName = OBJ_PREFIX_BALANCE_PREPARE + IntegerToString(ticket);
   if(ObjectFind(0, objName) < 0)
   {
      ObjectCreate(0, objName, OBJ_TEXT, 0, timeVal, priceLevel);
      ObjectSetInteger(0, objName, OBJPROP_COLOR, clrDodgerBlue);
      ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, objName, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
      ObjectSetInteger(0, objName, OBJPROP_BACK, false);
      ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
   }
   else
   {
      ObjectSetDouble(0, objName, OBJPROP_PRICE, priceLevel);
      ObjectSetInteger(0, objName, OBJPROP_TIME, (long)timeVal);
   }
   ObjectSetString(0, objName, OBJPROP_TEXT, "Lệnh được chọn");
   ObjectSetString(0, objName, OBJPROP_FONT, "Arial");
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Set prepare mark on position only (lệnh đang mở). Chart label.   |
//| Pending orders are not selected for balance prepare.              |
//+------------------------------------------------------------------+
void SetBalancePrepareMark(ulong ticket)
{
   if(ticket == 0) return;
   if(!PositionSelectByTicket(ticket)) return;
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   datetime t = (datetime)PositionGetInteger(POSITION_TIME);
   SetBalancePrepareChartLabel(ticket, openPrice, t);
}

//+------------------------------------------------------------------+
//| Clear all BP marks (before remarking next level)                   |
//+------------------------------------------------------------------+
void ClearAllBalancePrepareMarks()
{
   for(int i = 0; i < ArraySize(balanceMarkedTickets); i++)
      if(balanceMarkedTickets[i] > 0)
         ClearBalancePrepareMark(balanceMarkedTickets[i]);
   ArrayResize(balanceMarkedTickets, 0);
}

//+------------------------------------------------------------------+
//| Append ticket to balanceMarkedTickets if not already present       |
//+------------------------------------------------------------------+
void AppendMarkedTicket(ulong ticket)
{
   if(ticket == 0) return;
   for(int i = 0; i < ArraySize(balanceMarkedTickets); i++)
      if(balanceMarkedTickets[i] == ticket) return;
   int n = ArraySize(balanceMarkedTickets);
   ArrayResize(balanceMarkedTickets, n + 1);
   balanceMarkedTickets[n] = ticket;
}

//+------------------------------------------------------------------+
//| Chỉ 1 bậc lưới: chọn và nhãn (comment) chỉ lệnh mở tại levelPrice.|
//| Lệnh ở bậc khác (price khác) không chọn, không hiển thị.           |
//+------------------------------------------------------------------+
void MarkAllTypesAtLevelWithBalancePrepare(double levelPrice)
{
   double tol = gridStep * 0.5;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      long mg = PositionGetInteger(POSITION_MAGIC);
      if(mg != MagicAA && mg != MagicBB && mg != MagicCC) continue;
      double posPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      if(MathAbs(posPrice - levelPrice) > tol) continue;
      SetBalancePrepareMark(ticket);
      AppendMarkedTicket(ticket);
   }
}

//+------------------------------------------------------------------+
//| Xóa ghi nhớ / đánh dấu lệnh chọn (khi giá qua đường gốc hoặc tắt cân bằng) |
//+------------------------------------------------------------------+
void ClearBalanceSelection()
{
   balanceSelectedLevelPrice = 0.0;
   ArrayResize(balanceSelectedTickets, 0);
   balancePreparedTicket = 0;
}

//+------------------------------------------------------------------+
//| Ghi nhớ, đánh dấu lệnh được chọn để chuẩn bị cho chế độ cân bằng.  |
//| Chỉ 1 bậc lưới (xa nhất): lưu mức giá bậc + danh sách ticket tại bậc đó. |
//| Khi bậc đó hết lệnh mới chuyển sang bậc gần hơn (gọi lại với tickets mới). |
//+------------------------------------------------------------------+
void MarkSelectedOrdersForBalance(ulong &tickets[], double &openPrices[], int cnt)
{
   balanceSelectedLevelPrice = 0.0;
   ArrayResize(balanceSelectedTickets, 0);
   balancePreparedTicket = 0;
   if(cnt <= 0)
      return;
   double levelPrice0 = openPrices[0];
   double tol = gridStep * 0.5;
   balanceSelectedLevelPrice = levelPrice0;   // ghi nhớ bậc được chọn
   for(int i = 0; i < cnt; i++)
   {
      if(MathAbs(openPrices[i] - levelPrice0) > tol)
         break;   // chỉ lấy lệnh tại đúng 1 bậc (xa nhất)
      int n = ArraySize(balanceSelectedTickets);
      ArrayResize(balanceSelectedTickets, n + 1);
      balanceSelectedTickets[n] = tickets[i];
   }
   if(ArraySize(balanceSelectedTickets) > 0)
      balancePreparedTicket = balanceSelectedTickets[0];
}

//+------------------------------------------------------------------+
//| Cập nhật đánh dấu (gọi MarkSelectedOrdersForBalance), xóa nhãn chart cũ. |
//+------------------------------------------------------------------+
void UpdateBalancePrepareMarks(ulong &tickets[], double &openPrices[], int cnt)
{
   ObjectsDeleteAll(0, OBJ_PREFIX_BALANCE_PREPARE);
   MarkSelectedOrdersForBalance(tickets, openPrices, cnt);
}

//+------------------------------------------------------------------+
//| Close all positions and cancel all pending orders (EA magic).     |
//| After this: no open positions, no pending orders. Used on every reset. |
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
//| Cancel Buy Stop below base, Sell Stop above base (orders placed BS above base, SS below base only). |
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
//| Remove TP from all open positions in session (when entering trailing) |
//+------------------------------------------------------------------+
void RemoveTPFromAllSessionPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(!IsOurMagic(PositionGetInteger(POSITION_MAGIC)) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(sessionStartTime > 0 && (datetime)PositionGetInteger(POSITION_TIME) < sessionStartTime) continue;
      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);
      if(curTP > 0)
         trade.PositionModify(ticket, curSL, 0);
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
//| onlyCurrentSession: true = close only positions opened in current session (trailing). |
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
//| Trailing: Point A = SL level = base ± X pip (base = grid level closest to price at threshold, fixed). |
//| Place SL at point A when price reaches (base + point A pip + step); each further step trails SL 1 step. SL hit -> EA reset. |
//+------------------------------------------------------------------+
void DoGongLaiTrailing()
{
   pointABaseLevel = 0.0;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double pipSize = (dgt == 5 || dgt == 3) ? (pnt * 10.0) : pnt;
   double stepSize = GongLaiStepPips * pipSize;

   if(bid > basePrice)
   {
      // Buy base fixed at threshold: grid level (above base) below price and closest. Set once when entering trailing.
      if(trailingGocBuy <= 0.0)
      {
         int nLevels = ArraySize(gridLevels);
         for(int i = 0; i < MaxGridLevels && i < nLevels; i++)
         {
            double L = gridLevels[i];
            if(L < bid && L > trailingGocBuy)
               trailingGocBuy = L;
         }
      }
      if(trailingGocBuy <= 0.0) { lastSellTrailPrice = 0.0; return; }
      pointABaseLevel = trailingGocBuy;
      // Point A = SL level = base + X pip (fixed).
      double pointA_Buy = trailingGocBuy + TrailingPointAPips * pipSize;
      // Place SL at point A when price reaches (base + point A pip + step); each further step trails SL up.
      double distPointAPips = TrailingPointAPips * pipSize;
      double firstTriggerDist = distPointAPips + stepSize;   // base + point A + 1 step
      if((bid - trailingGocBuy) < firstTriggerDist)
         return;
      int stepsBeyondFirst = (int)MathFloor(((bid - trailingGocBuy) - firstTriggerDist) / stepSize);
      double slBuyA = NormalizeDouble(pointA_Buy + stepsBeyondFirst * stepSize, dgt);
      if(slBuyA >= bid)
         return;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         if(!IsOurMagic(PositionGetInteger(POSITION_MAGIC)) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if(PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_BUY) continue;
         if(sessionStartTime > 0 && (datetime)PositionGetInteger(POSITION_TIME) < sessionStartTime) continue;   // Current session only
         double curSL = PositionGetDouble(POSITION_SL);
         double curTP = PositionGetDouble(POSITION_TP);
         if(slBuyA > curSL && slBuyA < bid)
         {
            trade.PositionModify(ticket, slBuyA, curTP);
            trailingSLPlaced = true;   // SL placed -> Return mode cannot exit trailing anymore
         }
      }
      lastSellTrailPrice = 0.0;
      CloseOppositeSidePositions(true, true);   // Current session only
   }
   else if(ask < basePrice)
   {
      // Sell base fixed at threshold: grid level (below base) above price and closest. Set once when entering trailing.
      if(trailingGocSell <= 0.0)
      {
         int nLevels = ArraySize(gridLevels);
         for(int i = MaxGridLevels; i < nLevels; i++)
         {
            double L = gridLevels[i];
            if(L > ask && (trailingGocSell <= 0.0 || L < trailingGocSell))
               trailingGocSell = L;
         }
      }
      if(trailingGocSell <= 0.0) { lastBuyTrailPrice = 0.0; return; }
      pointABaseLevel = trailingGocSell;
      // Point A = SL level = base - X pip (fixed).
      double pointA_Sell = trailingGocSell - TrailingPointAPips * pipSize;
      // Place SL at point A when price reaches (base - point A pip - step); each further step trails SL down.
      double distPointAPips = TrailingPointAPips * pipSize;
      double firstTriggerDist = distPointAPips + stepSize;   // base - point A - 1 step (distance from base down)
      if((trailingGocSell - ask) < firstTriggerDist)
         return;
      int stepsBeyondFirst = (int)MathFloor(((trailingGocSell - ask) - firstTriggerDist) / stepSize);
      double slSellA = NormalizeDouble(pointA_Sell - stepsBeyondFirst * stepSize, dgt);
      if(slSellA <= ask)
         return;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         if(!IsOurMagic(PositionGetInteger(POSITION_MAGIC)) || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if(PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_SELL) continue;
         if(sessionStartTime > 0 && (datetime)PositionGetInteger(POSITION_TIME) < sessionStartTime) continue;   // Current session only
         double curSL = PositionGetDouble(POSITION_SL);
         double curTP = PositionGetDouble(POSITION_TP);
         if((curSL <= 0 || slSellA < curSL) && slSellA > ask)
         {
            trade.PositionModify(ticket, slSellA, curTP);
            trailingSLPlaced = true;   // SL placed -> Return mode cannot exit trailing anymore
         }
      }
      lastBuyTrailPrice = 0.0;
      CloseOppositeSidePositions(false, true);   // Current session only
   }
   else
   {
      lastBuyTrailPrice = 0.0;
      lastSellTrailPrice = 0.0;
   }
}

//+------------------------------------------------------------------+
//| Draw thin yellow line at grid level chosen for point A (trailing). No draw: only delete if exists. |
//+------------------------------------------------------------------+
void DrawPointABaseLine()
{
   long chartId = ChartID();
   if(ObjectFind(chartId, "GridPointABase") >= 0)
      ObjectDelete(chartId, "GridPointABase");
   ChartRedraw(chartId);
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
   // Only count deals closed in current session (from sessionStartTime). EA attach or EA reset = new session, sessionStartTime updated.
   if(sessionStartTime > 0 && dealTime < (long)sessionStartTime)
      return;
   if(lastResetTime > 0 && dealTime >= lastResetTime && dealTime <= lastResetTime + 15)
      return;   // Avoid double-counting deals from positions just closed on reset
   // Only count closes by TP (Take Profit). Closes by SL / manual / stop out do not add to balance pool.
   if(HistoryDealGetInteger(trans.deal, DEAL_REASON) != DEAL_REASON_TP)
      return;
   
   // Closed deal P/L = profit + swap + commission (TP closes in session only)
   double dealPnL = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                  + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                  + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   // Lock profit (tiền tiết kiệm): apply same % to AA, BB, CC and DD TP closes. lockedProfitReserve cumulative; pool = TP - session lock.
   if(EnableLockProfit && LockProfitPct > 0 && dealPnL > 0)
   {
      double pct = MathMin(100.0, MathMax(0.0, LockProfitPct));
      double locked = dealPnL * (pct / 100.0);
      lockedProfitReserve += locked;   // Cumulative, never reset
      sessionLockedProfit += locked;   // Lock in session (so pool = TP - session lock)
      dealPnL -= locked;
   }
   sessionClosedProfit += dealPnL;   // Balance pool = session TP (AA+BB+CC+DD) - session lock; used to balance AA/BB/CC only (DD not balanced)
   long dealMagic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   if(dealMagic == MagicBB)
      sessionClosedProfitBB += dealPnL;
   if(dealMagic == MagicCC)
      sessionClosedProfitCC += dealPnL;
   if(dealMagic == MagicDD)
      sessionClosedProfitDD += dealPnL;
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
//| First lot (level 1): EACH ORDER TYPE SEPARATE. Scale by % capital  |
//| when EnableScaleByAccountGrowth: lot = input × sessionMultiplier.  |
//| AA: Buy Stop & Sell Stop share LotSizeAA.                          |
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
//| LOT CALC: Level +1/-1 = first lot. Level +2/-2, +3/-3... =         |
//| Scale by multiplier. levelNum: +1..+n (above), -1..-n (below).    |
//+------------------------------------------------------------------+
double GetLotForLevel(ENUM_ORDER_TYPE orderType, int levelNum)
{
   int absLevel = MathAbs(levelNum);
   double baseLot = GetBaseLotForOrderType(orderType);
   ENUM_LOT_SCALE scale = GetLotScaleForOrderType(orderType);
   double lot = baseLot;
   if(absLevel <= 1 || scale == LOT_FIXED)
      lot = baseLot;   // Level +1/-1 = first lot
   else if(scale == LOT_GEOMETRIC)
      lot = baseLot * MathPow(GetLotMultForOrderType(orderType), absLevel - 1);   // Level +2/-2... = scaled
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(MaxLotAA > 0)
      maxLot = MathMin(maxLot, MaxLotAA);   // AA max lot cap (0 = no limit)
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
//| BB: Lot level 1 (scaled by capital if enabled)                    |
//+------------------------------------------------------------------+
double GetBaseLotBB()
{
   return (EnableScaleByAccountGrowth) ? (LotSizeBB * sessionMultiplier) : LotSizeBB;
}

//+------------------------------------------------------------------+
//| BB: Lot by level (Fixed or Geometric), separate from AA           |
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
      maxLot = MathMin(maxLot, MaxLotBB);   // BB max lot cap
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
//| CC: Lot level 1 (scaled by capital if enabled)                    |
//+------------------------------------------------------------------+
double GetBaseLotCC()
{
   return (EnableScaleByAccountGrowth) ? (LotSizeCC * sessionMultiplier) : LotSizeCC;
}

//+------------------------------------------------------------------+
//| CC: Lot by level (Fixed or Geometric)                            |
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
//| DD: Lot level 1 (scaled by capital % growth, same as AA/BB/CC)    |
//+------------------------------------------------------------------+
double GetBaseLotDD()
{
   return (EnableScaleByAccountGrowth) ? (LotSizeDD * sessionMultiplier) : LotSizeDD;
}

//+------------------------------------------------------------------+
//| DD: Lot by level (Fixed or Geometric). isSellLimit=true = above base (Sell Limit), false = below base (Buy Limit) |
//+------------------------------------------------------------------+
double GetLotForLevelDD(bool isSellLimit, int levelNum)
{
   int absLevel = MathAbs(levelNum);
   double baseLot = GetBaseLotDD();
   double lot = baseLot;
   if(absLevel <= 1 || DDLotScale == LOT_FIXED)
      lot = baseLot;
   else if(DDLotScale == LOT_GEOMETRIC)
      lot = baseLot * MathPow(LotMultDD, absLevel - 1);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(MaxLotDD > 0)
      maxLot = MathMin(maxLot, MaxLotDD);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathMax(minLot, MathMin(maxLot, lot));
   lot = MathFloor(lot / lotStep) * lotStep;
   if(lot < minLot) lot = minLot;
   return NormalizeDouble(lot, 2);
}

double GetTakeProfitPipsDD()
{
   return TakeProfitPipsDD;
}

//+------------------------------------------------------------------+
//| Initialize level prices - evenly spaced using gridStep            |
//+------------------------------------------------------------------+
void InitializeGridLevels()
{
   // Current session = 0 and start counting from here (called when EA attached or EA auto reset)
   sessionStartTime = TimeCurrent();
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   sessionStartBalance = bal;
   // attachBalance NOT updated here - set once in OnInit (capital when EA first attached)
   gridStep = GridDistancePips * pnt * 10.0;   // One grid step (even)
   int totalLevels = MaxGridLevels * 2;
   
   ArrayResize(gridLevels, totalLevels);
   
   for(int i = 0; i < totalLevels; i++)
      gridLevels[i] = GetGridLevelPrice(i);
   
   Print("Initialized ", totalLevels, " grid levels (", MaxGridLevels, " above + ", MaxGridLevels, " below base), spacing ", GridDistancePips, " pips");
}

//+------------------------------------------------------------------+
//| Manage grid: place orders from level 1 (closest to base) outward  |
//| GRID LEVELS: Base line = level 0. Above base = +1,+2,...+n.        |
//| Below base = -1,-2,...-n. EA places pending orders in this order. |
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
//| Per level: max 1 order per type (AA, BB, CC, DD) per input. Remove duplicate pending; if position at level keep 0 pending. |
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
         if(!enabled[m]) continue;   // Only for enabled type
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
   // DD: Sell Limit above base (L < MaxGridLevels), Buy Limit below base (L >= MaxGridLevels); max 1 per level
   if(EnableDD)
   {
      for(int L = 0; L < nLevels; L++)
      {
         double priceLevel = gridLevels[L];
         bool isSellLevel = (L < MaxGridLevels);
         bool isBuy = !isSellLevel;
         int positionCount = 0;
         for(int i = 0; i < PositionsTotal(); i++)
         {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            if(PositionGetInteger(POSITION_MAGIC) != MagicDD || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
            if((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) != isBuy) continue;
            double posPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            if(MathAbs(posPrice - priceLevel) < tolerance)
               positionCount++;
         }
         ulong pendingTickets[];
         ENUM_ORDER_TYPE wantType = isSellLevel ? ORDER_TYPE_SELL_LIMIT : ORDER_TYPE_BUY_LIMIT;
         for(int i = 0; i < OrdersTotal(); i++)
         {
            ulong t = OrderGetTicket(i);
            if(t <= 0) continue;
            if(OrderGetInteger(ORDER_MAGIC) != MagicDD || OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
            if(StringFind(OrderGetString(ORDER_COMMENT), CommentOrder) != 0) continue;
            ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
            if(ot != wantType) continue;
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

//+------------------------------------------------------------------+
//| Balance rules for AA, BB, CC:                                    |
//| Pool = TP in current session minus lock in session.               |
//| 1. Only close losing positions on OPPOSITE side of current price vs base. |
//| 2. Farthest from base first; same level: AA->BB->CC               |
//| 3. Prepare: price >= PREPARE levels from base -> select farthest   |
//|    opposite loser (no close). Clear prepare only when price CROSSES |
//|    base (not when only moving back within 3 levels on same side).   |
//| 4. Execute: price >= EXECUTE levels from base + pool enough ->   |
//|    close/partial; then next closer; wait if pool insufficient.     |
//+------------------------------------------------------------------+
void DoBalanceAll()
{
   bool anyBalance = (EnableAA && EnableBalanceAAByBB && BALANCE_THRESHOLD_USD_DEFAULT > 0) ||
                     (EnableBB && EnableBalanceBB && BALANCE_THRESHOLD_USD_DEFAULT > 0) ||
                     (EnableCC && EnableBalanceCC && BALANCE_THRESHOLD_USD_DEFAULT > 0);
   if(!anyBalance)
      return;
   if(sessionClosedProfitRemaining < 0)
      return;
   int minCooldown = 0;
   if(EnableAA && EnableBalanceAAByBB && BALANCE_THRESHOLD_USD_DEFAULT > 0 && BALANCE_COOLDOWN_SEC_DEFAULT > 0)
      minCooldown = (minCooldown == 0) ? BALANCE_COOLDOWN_SEC_DEFAULT : MathMin(minCooldown, BALANCE_COOLDOWN_SEC_DEFAULT);
   if(EnableBB && EnableBalanceBB && BALANCE_THRESHOLD_USD_DEFAULT > 0 && BALANCE_COOLDOWN_SEC_DEFAULT > 0)
      minCooldown = (minCooldown == 0) ? BALANCE_COOLDOWN_SEC_DEFAULT : MathMin(minCooldown, BALANCE_COOLDOWN_SEC_DEFAULT);
   if(EnableCC && EnableBalanceCC && BALANCE_THRESHOLD_USD_DEFAULT > 0 && BALANCE_COOLDOWN_SEC_DEFAULT > 0)
      minCooldown = (minCooldown == 0) ? BALANCE_COOLDOWN_SEC_DEFAULT : MathMin(minCooldown, BALANCE_COOLDOWN_SEC_DEFAULT);
   datetime lastClose = MathMax(lastBalanceAAByBBCloseTime, MathMax(lastBalanceBBCloseTime, lastBalanceCCCloseTime));
   if(minCooldown > 0 && lastClose > 0 && (TimeCurrent() - lastClose) < minCooldown)
      return;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool priceAboveBase = (bid > basePrice);
   bool priceBelowBase = (bid < basePrice);
   int nLevels = ArraySize(gridLevels);
   int prepLevels = MathMax(1, MathMin(MaxGridLevels, BALANCE_PREPARE_LEVELS));
   int execLevels = MathMax(prepLevels, MathMin(MaxGridLevels, BALANCE_EXECUTE_LEVELS));
   int idxPrep = prepLevels - 1;   // e.g. 3 levels -> index 2 above base
   int idxExec = execLevels - 1;   // e.g. 5 levels -> index 4 above base

   // Clear preparation only when price CROSSES base (not when only <3 levels on same side)
   // Prepared while above base -> clear when bid at or below base; prepared while below -> clear when bid at or above base
   if(balancePrepareDirection == 1 && !priceAboveBase)
   {
      ObjectsDeleteAll(0, OBJ_PREFIX_BALANCE_PREPARE);
      ClearBalanceSelection();
      ClearAllBalancePrepareMarks();
      balancePrepareDirection = 0;
   }
   else if(balancePrepareDirection == -1 && !priceBelowBase)
   {
      ObjectsDeleteAll(0, OBJ_PREFIX_BALANCE_PREPARE);
      ClearBalanceSelection();
      ClearAllBalancePrepareMarks();
      balancePrepareDirection = 0;
   }
   if(!priceAboveBase && !priceBelowBase)
      return;   // at base: no prepare/execute this tick (already cleared if had prepare)
   // Need >= 3 levels from base on current side to (re)select preparation; <3 on same side: keep existing prepare, do nothing
   if(priceAboveBase)
   {
      if(nLevels <= idxPrep || bid < gridLevels[idxPrep])
         return;   // not enough levels to refresh prepare; do not clear unless cross base (handled above)
      if(nLevels <= idxExec || bid < gridLevels[idxExec])
         balancePrepareDirection = 1;   // prepare-only until execute zone
   }
   else if(priceBelowBase)
   {
      int idxPrepBelow = MaxGridLevels + idxPrep;
      if(nLevels <= idxPrepBelow || bid > gridLevels[idxPrepBelow])
         return;   // not deep enough below base to refresh; keep prepare until cross base
      int idxExecBelow = MaxGridLevels + idxExec;
      if(nLevels <= idxExecBelow || bid > gridLevels[idxExecBelow])
         balancePrepareDirection = -1;
   }

   bool executeZone = false;
   if(priceAboveBase && nLevels > idxExec && bid >= gridLevels[idxExec])
      executeZone = true;
   else if(priceBelowBase)
   {
      int idxExecBelow = MaxGridLevels + idxExec;
      if(nLevels > idxExecBelow && bid <= gridLevels[idxExecBelow])
         executeZone = true;
   }
   ulong tickets[];
   double pls[], vols[], openPrices[];
   int types[];   // 0=AA, 1=BB, 2=CC
   ArrayResize(tickets, 0);
   ArrayResize(pls, 0);
   ArrayResize(vols, 0);
   ArrayResize(openPrices, 0);
   ArrayResize(types, 0);
   long magics[] = {MagicAA, MagicBB, MagicCC};
   bool enabled[] = {EnableAA && EnableBalanceAAByBB, EnableBB && EnableBalanceBB, EnableCC && EnableBalanceCC};
   double thresholds[] = {BALANCE_THRESHOLD_USD_DEFAULT, BALANCE_THRESHOLD_USD_DEFAULT, BALANCE_THRESHOLD_USD_DEFAULT};
   for(int t = 0; t < 3; t++)
   {
      if(!enabled[t] || thresholds[t] <= 0) continue;
      for(int i = 0; i < PositionsTotal(); i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) != magics[t] || PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;
         if(sessionStartTime > 0 && (datetime)PositionGetInteger(POSITION_TIME) < sessionStartTime)
            continue;
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double pr = GetPositionPnL(ticket);
         double vol = PositionGetDouble(POSITION_VOLUME);
         // Only close losing position on opposite side of price vs base (check function)
         if(!IsLosingOppositeSidePosition(ticket, priceAboveBase)) continue;
         // Lock: price above base do not close Buy, price below base do not close Sell (avoid wrong close)
         if(IsPositionLockedForBalance(ticket, priceAboveBase)) continue;
         int n = ArraySize(tickets);
         ArrayResize(tickets, n + 1);
         ArrayResize(pls, n + 1);
         ArrayResize(vols, n + 1);
         ArrayResize(openPrices, n + 1);
         ArrayResize(types, n + 1);
         tickets[n] = ticket;
         pls[n] = pr;
         vols[n] = vol;
         openPrices[n] = openPrice;
         types[n] = t;
      }
   }
   int cnt = ArraySize(tickets);
   if(cnt == 0) return;
   // Sort: farthest from base first; same level then AA -> BB -> CC
   for(int i = 0; i < cnt - 1; i++)
      for(int j = i + 1; j < cnt; j++)
      {
         double di = MathAbs(openPrices[i] - basePrice);
         double dj = MathAbs(openPrices[j] - basePrice);
         bool swap = (dj > di);
         if(!swap && MathAbs(dj - di) < gridStep * 0.5 && types[j] < types[i])
            swap = true;   // Same level: AA(0) then BB(1) then CC(2)
         if(swap)
         {
            SwapDouble(openPrices[i], openPrices[j]);
            SwapDouble(pls[i], pls[j]);
            SwapDouble(vols[i], vols[j]);
            SwapULong(tickets[i], tickets[j]);
            int tt = types[i]; types[i] = types[j]; types[j] = tt;
         }
      }
   // Chỉ chọn lệnh mở ở bậc xa nhất; dán nhãn bậc đó. Khi bậc đó hết lệnh thì tick sau chuyển sang bậc gần hơn, bậc cũ hết nhãn.
   if(!executeZone)
   {
      if(balancePrepareDirection == 0)
         balancePrepareDirection = priceAboveBase ? 1 : -1;
      UpdateBalancePrepareMarks(tickets, openPrices, cnt);
      return;
   }
   // Execute: ghi nhớ/đánh dấu lệnh chọn rồi chỉ đóng đúng lệnh tại bậc được chọn.
   UpdateBalancePrepareMarks(tickets, openPrices, cnt);
   double levelPrice0 = balanceSelectedLevelPrice;   // dùng bậc đã ghi nhớ để xóa cân bằng đúng lệnh
   double tolLevel = gridStep * 0.5;
   double balanceFloor = sessionStartBalance + lockedProfitReserve;
   double balanceNow = AccountInfoDouble(ACCOUNT_BALANCE);
   double runningClosed = sessionClosedProfitRemaining;
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   int closedCount = 0;
   for(int k = 0; k < cnt; k++)
   {
      if(MathAbs(openPrices[k] - levelPrice0) > tolLevel)
         break;   // chỉ xóa cân bằng lệnh tại bậc được chọn; bậc gần hơn đợi tick sau
      int typ = types[k];
      double thresh = thresholds[typ];
      double afterClose = runningClosed + pls[k];
      double balanceAfterClose = balanceNow + pls[k];
      if(afterClose >= thresh && afterClose >= 0 && balanceAfterClose >= balanceFloor)
      {
         PositionCloseWithComment(tickets[k], "Balance order");
         runningClosed += pls[k];
         balanceNow = balanceAfterClose;
         closedCount++;
         if(typ == 0) lastBalanceAAByBBCloseTime = TimeCurrent();
         else if(typ == 1) lastBalanceBBCloseTime = TimeCurrent();
         else lastBalanceCCCloseTime = TimeCurrent();
         continue;
      }
      double spendable = MathMin(runningClosed, MathMin(balanceNow - balanceFloor, MathAbs(pls[k])));
      if(spendable <= 0) continue;
      double volClose = vols[k] * (spendable / MathAbs(pls[k]));
      volClose = MathFloor(volClose / lotStep) * lotStep;
      if(volClose < minLot) continue;
      if(volClose >= vols[k]) volClose = vols[k];
      if(PositionClosePartialWithComment(tickets[k], volClose, "Balance order"))
      {
         double realizedPnL = (volClose / vols[k]) * pls[k];
         runningClosed += realizedPnL;
         balanceNow += realizedPnL;
         closedCount++;
         if(typ == 0) lastBalanceAAByBBCloseTime = TimeCurrent();
         else if(typ == 1) lastBalanceBBCloseTime = TimeCurrent();
         else lastBalanceCCCloseTime = TimeCurrent();
      }
   }
   if(closedCount > 0)
   {
      sessionClosedProfitRemaining = runningClosed;
      Print("Balance: closed ", closedCount, " (AA+BB+CC, farthest first). Pool remaining ", runningClosed, ".");
   }
   // Next tick DoBalanceAll rebuilds queue; prepare path or execute path will SetBalancePrepareMark on new head
}

//+------------------------------------------------------------------+
//| Thêm lệnh chờ từ bậc 1 (gần đường gốc) -> bậc 2 -> ... -> bậc N. |
//| Tại mỗi bậc: kiểm tra đầy đủ thiếu lệnh chờ loại nào (AA, BB, CC, DD theo input) thì thêm. |
//| Trên gốc: Buy Stop (AA/BB/CC) + Sell Limit (DD). Dưới gốc: Sell Stop (AA/BB/CC) + Buy Limit (DD). |
//+------------------------------------------------------------------+
void ManageGridOrders()
{
   if(gongLaiMode)
      return;
   
   CancelStopOrdersOutsideBaseZone();
   RemoveDuplicateOrdersAtLevel();
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   // Phía trên gốc: bậc 1 (gần gốc) -> 2 -> ... -> N. Mỗi bậc kiểm tra đủ AA, BB, CC, DD (bật thì đặt nếu thiếu).
   for(int levelNum = 1; levelNum <= MaxGridLevels; levelNum++)
   {
      int idxAbove = levelNum - 1;
      double levelAbove = gridLevels[idxAbove];
      if(levelAbove >= basePrice && levelAbove > currentPrice)
      {
         if(EnableAA) EnsureOrderAtLevel(ORDER_TYPE_BUY_STOP, levelAbove, +levelNum);
         if(EnableBB) EnsureOrderAtLevelBB(true, levelAbove, +levelNum);
         if(EnableCC) EnsureOrderAtLevelCC(true, levelAbove, +levelNum);
         if(EnableDD) EnsureOrderAtLevelDD(true, levelAbove, +levelNum);
      }
   }
   // Phía dưới gốc: bậc 1 (gần gốc) -> 2 -> ... -> N. Mỗi bậc kiểm tra đủ AA, BB, CC, DD (bật thì đặt nếu thiếu).
   for(int levelNum = 1; levelNum <= MaxGridLevels; levelNum++)
   {
      int idxBelow = MaxGridLevels + levelNum - 1;
      double levelBelow = gridLevels[idxBelow];
      if(levelBelow <= basePrice && levelBelow < currentPrice)
      {
         if(EnableAA) EnsureOrderAtLevel(ORDER_TYPE_SELL_STOP, levelBelow, -levelNum);
         if(EnableBB) EnsureOrderAtLevelBB(false, levelBelow, -levelNum);
         if(EnableCC) EnsureOrderAtLevelCC(false, levelBelow, -levelNum);
         if(EnableDD) EnsureOrderAtLevelDD(false, levelBelow, -levelNum);
      }
   }
}

//+------------------------------------------------------------------+
//| Ensure order at level - add only when missing (no pending and no position of same type at level). |
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
//| BB: Ensure order at level - add only when missing (no BB pending and no BB position at level). |
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
//| CC: Ensure order at level - add only when missing (no CC pending and no CC position at level). |
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
//| DD: Ensure order at level - Sell Limit above base, Buy Limit below base. No balance. |
//+------------------------------------------------------------------+
void EnsureOrderAtLevelDD(bool isSellLimit, double priceLevel, int levelNum)
{
   ulong ticket = 0;
   double existingPrice = 0.0;
   ENUM_ORDER_TYPE ot = isSellLimit ? ORDER_TYPE_SELL_LIMIT : ORDER_TYPE_BUY_LIMIT;
   if(GetPendingOrderAtLevel(ot, priceLevel, ticket, existingPrice, MagicDD))
   {
      double desiredPrice = NormalizeDouble(priceLevel, dgt);
      if(MathAbs(existingPrice - desiredPrice) > (pnt / 2.0))
         AdjustPendingOrderToLevel(ticket, ot, priceLevel, GetTakeProfitPipsDD());
      return;
   }
   if(PositionExistsAtLevelWithMagic(priceLevel, MagicDD))
      return;
   if(!CanPlaceOrderAtLevel(ot, priceLevel, MagicDD))
      return;
   PlacePendingOrderDD(isSellLimit, priceLevel, levelNum);
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
//| Check if order can be placed at level: max 1 order per type (AA, BB, CC) per level per input. whichMagic = magic of type being placed. |
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
   return (countSameLevel < 1);   // Max 1 order (pending or position) per type per level
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
//| BB: Place pending order (Buy Stop or Sell Stop), lot/TP separate for BB |
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
//| CC: Place pending order (Buy Stop or Sell Stop), lot/TP separate for CC |
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
//| DD: Place pending order (Sell Limit above base, Buy Limit below base). No balance. |
//+------------------------------------------------------------------+
void PlacePendingOrderDD(bool isSellLimit, double priceLevel, int levelNum)
{
   double price = NormalizeDouble(priceLevel, dgt);
   double lot   = GetLotForLevelDD(isSellLimit, levelNum);
   double sl = 0, tp = 0;
   double tpPips = GetTakeProfitPipsDD();
   if(tpPips > 0)
   {
      if(isSellLimit)
         tp = NormalizeDouble(price - tpPips * pnt * 10.0, dgt);
      else
         tp = NormalizeDouble(price + tpPips * pnt * 10.0, dgt);
   }
   trade.SetExpertMagicNumber(MagicDD);
   string cmt = CommentOrder;
   bool result = false;
   if(isSellLimit)
      result = trade.SellLimit(lot, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);
   else
      result = trade.BuyLimit(lot, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, cmt);
   if(result)
      Print("Order placed DD: ", isSellLimit ? "SellLimit" : "BuyLimit", " at ", price, " lot ", lot, " (level ", levelNum > 0 ? "+" : "", levelNum, ")");
   else
      Print("Order error DD | Error: ", GetLastError());
}

//+------------------------------------------------------------------+
