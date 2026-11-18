//+------------------------------------------------------------------+
//|                                                GoldDCA_EA.mq5    |
//|  XAUUSD Trend-following DCA EA                                   |
//|  - Trend direction me entry (H1 trend + M15 signal)              |
//|  - Price $X against jaye to naya layer (DCA)                     |
//|  - Basket average price + target par sab close                   |
//|  - Daily target / daily loss / basket hard stop / news filter    |
//|  WARNING: DCA me win-rate high hota hai, lekin ek bada trend     |
//|  against ho to bada loss ho sakta hai. Basket stop OFF mat karein|
//+------------------------------------------------------------------+
#property copyright "GoldDCA_EA"
#property version   "1.20"

#include <Trade/Trade.mqh>

enum ENUM_LOT_MODE { LOT_FIXED = 0, LOT_AUTO = 1 };
enum ENUM_STEP_MODE { STEP_FIXED_PRICE = 0, STEP_ATR = 1 };
enum ENUM_TP_MODE { TP_FIXED_PRICE = 0, TP_ATR = 1 };

input group "=== General ==="
input long            InpMagic            = 888001;       // Magic number
input string          InpComment          = "GoldDCA";    // Order comment
input ENUM_TIMEFRAMES InpSignalTF         = PERIOD_M15;   // Entry signal timeframe
input ENUM_TIMEFRAMES InpTrendTF          = PERIOD_H1;    // Trend timeframe

input group "=== Lot Size ==="
input ENUM_LOT_MODE   InpLotMode          = LOT_AUTO;     // Lot mode
input double          InpFixedLot         = 0.01;         // Fixed first lot
input double          InpBalancePerLot    = 1000.0;       // AUTO: har itne $ balance par 0.01 lot
input double          InpLotMultiplier    = 1.3;          // Har DCA layer par lot x (1.0 = same lot)
input double          InpMaxLot           = 2.0;          // Max lot per layer

input group "=== DCA ==="
input ENUM_STEP_MODE  InpStepMode         = STEP_FIXED_PRICE; // DCA step mode
input double          InpStepPrice        = 7.0;          // Step: price $X against (Gold $7)
input double          InpStepATRMult      = 1.0;          // Step: ATR x (agar ATR mode)
input double          InpStepGrowth       = 1.2;          // Har layer par step x (gap badhta jaye)
input int             InpMaxLayers        = 6;            // Max layers (first trade included)
input int             InpMinSecBetween    = 60;           // Layers ke beech min seconds
input bool            InpAddOnlyInTrend   = true;         // Trend palat jaye to naya layer mat jodo

input group "=== Basket Exit ==="
input ENUM_TP_MODE    InpTPMode           = TP_ATR;       // Basket TP mode
input double          InpTPPrice          = 2.0;          // Fixed: average price se $X profit par close
input double          InpTP_ATRMult       = 0.5;          // ATR: average se ATR x profit par close
input double          InpTPMinPrice       = 1.5;          // ATR mode me TP kam se kam $X
input bool            InpBrokerSLTP       = true;         // Auto SL/TP broker par bhi lagao (EA/VPS off ho tab bhi safe)
input double          InpTPMoney          = 0.0;          // Ya basket profit $ (0 = off)
input double          InpBasketStopPct    = 15.0;         // Basket loss equity ka % ho to sab close (HARD STOP)
input int             InpCooldownMin      = 5;            // Basket close ke baad wait (minutes)

input group "=== Daily Limits ==="
input double          InpDailyTargetPct   = 5.0;          // Daily target % - hit hone par naye basket band
input double          InpDailyLossPct     = 15.0;         // Daily max loss % - sab close, din band
input int             InpMaxBasketsPerDay = 30;           // Max baskets per day

input group "=== Entry Strategy ==="
input int             InpTrendFastEMA     = 50;           // Trend TF fast EMA
input int             InpTrendSlowEMA     = 200;          // Trend TF slow EMA
input int             InpSigFastEMA       = 9;            // Signal TF fast EMA
input int             InpSigSlowEMA       = 21;           // Signal TF slow EMA
input int             InpRSIPeriod        = 14;           // RSI period
input double          InpRSIBuyMin        = 50;           // BUY: RSI min
input double          InpRSIBuyMax        = 72;           // BUY: RSI max
input double          InpRSISellMin       = 28;           // SELL: RSI min
input double          InpRSISellMax       = 50;           // SELL: RSI max
input int             InpATRPeriod        = 14;           // ATR period (signal TF)
input double          InpMaxATRPrice      = 15.0;         // Signal TF ATR isse zyada ho to entry nahi (volatility)
input double          InpMinATRPrice      = 1.0;          // ATR isse kam ho to entry nahi (dead market)

input group "=== MACD Confirmation ==="
input bool            InpUseMACD          = true;         // MACD confirm ON
input int             InpMACDFast         = 12;           // MACD fast
input int             InpMACDSlow         = 26;           // MACD slow
input int             InpMACDSignal       = 9;            // MACD signal
input bool            InpMACDZeroLine     = true;         // BUY ke liye MACD > 0, SELL ke liye < 0

input group "=== News Filter (live only, MT5 calendar) ==="
input bool            InpUseNews          = true;         // News filter ON
input int             InpNewsBeforeMin    = 30;           // High-impact USD news se pehle (min)
input int             InpNewsAfterMin     = 30;           // News ke baad (min)
input bool            InpNewsNoDCA        = true;         // News window me DCA layer bhi nahi
input bool            InpNewsCloseProfit  = true;         // News se pehle basket profit me ho to close

input group "=== S/R Levels (Y / 6M / 3M / 1M / W / 3D / D / H4) ==="
input bool            InpShowLevels       = true;         // Chart par levels draw karo
input bool            InpShowY            = true;         // Previous Year O/H/L/C
input bool            InpShow6M           = true;         // Previous Half-year O/H/L/C
input bool            InpShow3M           = true;         // Previous Quarter O/H/L/C
input bool            InpShow1M           = true;         // Previous Month O/H/L/C
input bool            InpShowW            = true;         // Previous Week O/H/L/C
input bool            InpShow3D           = true;         // Last 3 Days O/H/L/C
input bool            InpShowD            = true;         // Previous Day O/H/L/C
input bool            InpShowH4           = true;         // Last H4 candles O/H/L/C
input int             InpH4Count          = 5;            // Kitne H4 candles
input bool            InpDrawZones        = true;         // Y/6M/3M/1M/W levels par zone (box)
input double          InpZoneHalf         = 1.0;          // Zone half-width ($)
input color           InpZoneColor        = C'45,45,70';  // Zone color
input bool            InpUseSRFilter      = true;         // S/R ke paas against-direction entry block
input double          InpSRBlockDist      = 3.0;          // BUY: resistance itne $ upar ho to skip (SELL ulta)
input int             InpSRMinRank        = 3;            // Filter kin levels par: 7=Y 6=6M 5=3M 4=1M 3=W 2=3D 1=D 0=H4

input group "=== Filters ==="
input int             InpMaxSpreadPoints  = 50;           // Max spread (points)
input bool            InpUseSession       = true;         // Session filter
input int             InpSessionStart     = 2;            // Start hour (server)
input int             InpSessionEnd       = 22;           // End hour (server)
input bool            InpFridayStop       = true;         // Friday 20:00 ke baad naya basket nahi
input bool            InpAllowBuy         = true;         // Allow BUY
input bool            InpAllowSell        = true;         // Allow SELL

//==================== GLOBALS ====================
CTrade   trade;
int      hTF = INVALID_HANDLE, hTS = INVALID_HANDLE, hSF = INVALID_HANDLE, hSS = INVALID_HANDLE;
int      hRSI = INVALID_HANDLE, hATR = INVALID_HANDLE, hMACD = INVALID_HANDLE;
double   syncedTP = 0, syncedSL = 0; int syncedLayers = 0;

struct SRLevel { double price; int rank; string tag; };
SRLevel  levels[];
datetime lastLevelsBar = 0, lastLevelsTry = 0;
#define  SRPFX "GDCA_SR_"
datetime lastSigBar = 0, lastCloseTime = 0, lastLayerTime = 0, lastNewsCheck = 0;
bool     newsActive = false, newsSoon = false;
bool     dayStopped = false;
double   dayStartEq = 0, basketStartEq = 0;
int      dayKey = -1, basketsToday = 0, tradesToday = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFillingBySymbol(_Symbol);

   hTF  = iMA(_Symbol, InpTrendTF, InpTrendFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hTS  = iMA(_Symbol, InpTrendTF, InpTrendSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hSF  = iMA(_Symbol, InpSignalTF, InpSigFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hSS  = iMA(_Symbol, InpSignalTF, InpSigSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hRSI = iRSI(_Symbol, InpSignalTF, InpRSIPeriod, PRICE_CLOSE);
   hATR = iATR(_Symbol, InpSignalTF, InpATRPeriod);
   hMACD = iMACD(_Symbol, InpSignalTF, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE);
   if(hMACD == INVALID_HANDLE ||hTF == INVALID_HANDLE || hTS == INVALID_HANDLE || hSF == INVALID_HANDLE ||
      hSS == INVALID_HANDLE || hRSI == INVALID_HANDLE || hATR == INVALID_HANDLE)
     {
      Print("Indicator handle error: ", GetLastError());
      return(INIT_FAILED);
     }

   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("WARNING: Ye EA HEDGING account ke liye hai. Netting account par layers merge ho jayenge.");
   if(InpBasketStopPct <= 0)
      Print("WARNING: Basket hard stop OFF hai - ek galat trend poora account khatam kar sakta hai!");

   ResetDay();
   UpdateLevels(true);
   basketStartEq = AccountInfoDouble(ACCOUNT_EQUITY);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   IndicatorRelease(hTF); IndicatorRelease(hTS); IndicatorRelease(hSF);
   IndicatorRelease(hSS); IndicatorRelease(hRSI); IndicatorRelease(hATR); IndicatorRelease(hMACD);
   ObjectsDeleteAll(0, SRPFX);
   Comment("");
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   UpdateLevels(false);
   CheckNewDay();
   UpdateNews();

   int    dir; double avg, lots, lastPrice, profit; int layers;
   GetBasket(dir, layers, avg, lots, lastPrice, profit);

   if(layers > 0)
      ManageBasket(dir, layers, avg, lastPrice, profit);
   else
      TryNewBasket();

   ShowPanel();
  }

//==================== DAY TRACKING ====================
void ResetDay()
  {
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   dayKey = dt.year * 1000 + dt.day_of_year;
   dayStartEq = AccountInfoDouble(ACCOUNT_EQUITY);
   basketsToday = 0; tradesToday = 0;
   dayStopped = false;
  }

void CheckNewDay()
  {
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   int k = dt.year * 1000 + dt.day_of_year;
   if(k != dayKey)
     {
      // Basket khula ho to day reset mat karo jab tak close na ho (daily % sahi rahe)
      if(CountLayers() == 0) ResetDay();
     }

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(!dayStopped && dayStartEq > 0 && InpDailyLossPct > 0 &&
      (dayStartEq - eq) / dayStartEq * 100.0 >= InpDailyLossPct)
     {
      PrintFormat("Daily loss %.1f%% hit - sab close, aaj trading band.", InpDailyLossPct);
      CloseBasket();
      dayStopped = true;
     }
  }

double DayPLPct()
  {
   if(dayStartEq <= 0) return 0;
   return (AccountInfoDouble(ACCOUNT_EQUITY) - dayStartEq) / dayStartEq * 100.0;
  }

//==================== BASKET ====================
int CountLayers()
  {
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic) c++;
     }
   return c;
  }

// dir: 1 buy, -1 sell. lastPrice = sabse kharab (latest DCA) entry
void GetBasket(int &dir, int &layers, double &avg, double &lots, double &lastPrice, double &profit)
  {
   dir = 0; layers = 0; avg = 0; lots = 0; lastPrice = 0; profit = 0;
   double sumPV = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      double v = PositionGetDouble(POSITION_VOLUME);
      double p = PositionGetDouble(POSITION_PRICE_OPEN);
      bool buy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      dir = buy ? 1 : -1;
      layers++;
      lots += v; sumPV += v * p;
      profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      if(lastPrice == 0 || (buy && p < lastPrice) || (!buy && p > lastPrice)) lastPrice = p;
     }
   if(lots > 0) avg = sumPV / lots;
  }

void ManageBasket(int dir, int layers, double avg, double lastPrice, double profit)
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);

   //--- 1) Basket TP
   if(InpBrokerSLTP) SyncSLTP(dir, layers, avg);
   double tpDist = TPDist();
   bool tpHit = (dir == 1) ? (bid >= avg + tpDist) : (ask <= avg - tpDist);
   if(InpTPMoney > 0 && profit >= InpTPMoney) tpHit = true;
   if(tpHit && profit > 0)
     {
      PrintFormat("Basket TP: %d layers, profit %.2f", layers, profit);
      CloseBasket();
      return;
     }

   //--- 2) Hard stop
   if(InpBasketStopPct > 0 && basketStartEq > 0 && profit < 0 &&
      (-profit) / basketStartEq * 100.0 >= InpBasketStopPct)
     {
      PrintFormat("BASKET HARD STOP: loss %.2f (%.1f%%). Sab close.", profit, InpBasketStopPct);
      CloseBasket();
      return;
     }

   //--- 3) News se pehle profit lock
   if(InpUseNews && InpNewsCloseProfit && newsSoon && profit > 0)
     {
      Print("High-impact news aa rahi hai - basket profit me close.");
      CloseBasket();
      return;
     }

   //--- 4) DCA layer add
   if(layers >= InpMaxLayers) return;
   if(InpUseNews && InpNewsNoDCA && newsActive) return;
   if(TimeCurrent() - lastLayerTime < InpMinSecBetween) return;
   if(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpreadPoints) return;
   if(InpAddOnlyInTrend && TrendDir() != dir) return;

   double step = BaseStep() * MathPow(InpStepGrowth, layers - 1);
   bool add = (dir == 1) ? (ask <= lastPrice - step) : (bid >= lastPrice + step);
   if(!add) return;

   double lot = LayerLot(layers);
   if(!MarginOK(dir, lot)) { Print("Margin kam - DCA layer skip."); return; }
   if(Open(dir, lot, "L" + IntegerToString(layers + 1)))
      PrintFormat("DCA layer %d added @ %.2f, lot %.2f", layers + 1, dir == 1 ? ask : bid, lot);
  }

void CloseBasket()
  {
   for(int pass = 0; pass < 3; pass++)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(t == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic)
            trade.PositionClose(t);
        }
      if(CountLayers() == 0) break;
     }
   lastCloseTime = TimeCurrent();
   syncedTP = 0; syncedSL = 0; syncedLayers = 0;
   basketStartEq = AccountInfoDouble(ACCOUNT_EQUITY);
  }

//==================== ENTRY ====================
void TryNewBasket()
  {
   // Pending day reset (pichle din ka basket ab close ho gaya)
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.year * 1000 + dt.day_of_year != dayKey) ResetDay();

   if(dayStopped) return;
   if(InpDailyTargetPct > 0 && DayPLPct() >= InpDailyTargetPct) return;
   if(basketsToday >= InpMaxBasketsPerDay) return;
   if(TimeCurrent() - lastCloseTime < InpCooldownMin * 60) return;
   if(InpUseNews && (newsActive || newsSoon)) return;
   if(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpreadPoints) return;
   if(InpUseSession && (dt.hour < InpSessionStart || dt.hour >= InpSessionEnd)) return;
   if(InpFridayStop && dt.day_of_week == 5 && dt.hour >= 20) return;

   datetime bar = iTime(_Symbol, InpSignalTF, 0);
   if(bar == 0 || bar == lastSigBar) return;

   int sig = Signal();
   lastSigBar = bar;
   if(sig == 0) return;
   if(sig == 1 && !InpAllowBuy) return;
   if(sig == -1 && !InpAllowSell) return;

   if(InpUseSRFilter && SRBlocked(sig)) return;

   double lot = LayerLot(0);
   if(!MarginOK(sig, lot)) return;
   basketStartEq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(Open(sig, lot, "L1"))
     {
      basketsToday++;
      PrintFormat("New %s basket, lot %.2f", sig == 1 ? "BUY" : "SELL", lot);
     }
  }

bool Buf(int h, int start, int count, double &a[])
  {
   ArraySetAsSeries(a, true);
   return CopyBuffer(h, 0, start, count, a) == count;
  }

int TrendDir()
  {
   double f[], s[];
   if(!Buf(hTF, 1, 1, f) || !Buf(hTS, 1, 1, s)) return 0;
   double c = iClose(_Symbol, InpTrendTF, 1);
   if(f[0] > s[0] && c > f[0]) return 1;
   if(f[0] < s[0] && c < f[0]) return -1;
   return 0;
  }

int Signal()
  {
   int trend = TrendDir();
   if(trend == 0) return 0;

   double f[], s[], r[], a[];
   if(!Buf(hSF, 1, 2, f) || !Buf(hSS, 1, 2, s) || !Buf(hRSI, 1, 1, r) || !Buf(hATR, 1, 1, a)) return 0;
   if(InpMaxATRPrice > 0 && a[0] > InpMaxATRPrice) return 0; // bahut volatile
   if(InpMinATRPrice > 0 && a[0] < InpMinATRPrice) return 0; // market dead

   if(InpUseMACD)
     {
      double mm[], ms[];
      ArraySetAsSeries(mm, true); ArraySetAsSeries(ms, true);
      if(CopyBuffer(hMACD, 0, 1, 2, mm) != 2 || CopyBuffer(hMACD, 1, 1, 2, ms) != 2) return 0;
      double h0 = mm[0] - ms[0], h1 = mm[1] - ms[1];      // histogram bar1, bar2
      bool macdBuy  = (mm[0] > ms[0]) && (h0 >= h1) && (!InpMACDZeroLine || mm[0] > 0);
      bool macdSell = (mm[0] < ms[0]) && (h0 <= h1) && (!InpMACDZeroLine || mm[0] < 0);
      if(trend == 1 && !macdBuy) return 0;
      if(trend == -1 && !macdSell) return 0;
     }

   double c = iClose(_Symbol, InpSignalTF, 1);
   double o = iOpen(_Symbol, InpSignalTF, 1);

   if(trend == 1 && f[0] > s[0] && c > f[0] && c > o && r[0] >= InpRSIBuyMin && r[0] <= InpRSIBuyMax)
      return 1;
   if(trend == -1 && f[0] < s[0] && c < f[0] && c < o && r[0] >= InpRSISellMin && r[0] <= InpRSISellMax)
      return -1;
   return 0;
  }

//==================== AUTO TP / SL ====================
double TPDist()
  {
   if(InpTPMode == TP_ATR)
     {
      double a[];
      if(Buf(hATR, 1, 1, a) && a[0] > 0) return MathMax(a[0] * InpTP_ATRMult, InpTPMinPrice);
     }
   return InpTPPrice;
  }

// Sab layers par ek hi TP (average +/- TP) aur ek hi SL (hard stop price)
void SyncSLTP(int dir, int layers, double avg)
  {
   int    digits  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double minStop = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point + 5 * _Point;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double totalLots = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic)
         totalLots += PositionGetDouble(POSITION_VOLUME);
     }
   if(totalLots <= 0) return;

   double tp = NormalizeDouble(dir == 1 ? avg + TPDist() : avg - TPDist(), digits);

   // SL = wo price jahan basket loss = InpBasketStopPct (current lots ke hisaab se)
   double sl = 0;
   if(InpBasketStopPct > 0 && basketStartEq > 0)
     {
      double perDollar = 0; // 1 lot, $1 move ka money
      ENUM_ORDER_TYPE ot = dir == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(OrderCalcProfit(ot, _Symbol, 1.0, avg, dir == 1 ? avg + 1.0 : avg - 1.0, perDollar) && perDollar > 0)
        {
         double allowLoss = basketStartEq * InpBasketStopPct / 100.0;
         double dist = allowLoss / (totalLots * perDollar);
         sl = NormalizeDouble(dir == 1 ? avg - dist : avg + dist, digits);
        }
     }

   // stop-level validation
   if(dir == 1)
     {
      if(tp - ask < minStop) tp = 0;
      if(sl > 0 && bid - sl < minStop) sl = 0;
     }
   else
     {
      if(bid - tp < minStop) tp = 0;
      if(sl > 0 && sl - ask < minStop) sl = 0;
     }

   bool changed = (layers != syncedLayers) || MathAbs(tp - syncedTP) > 50 * _Point || MathAbs(sl - syncedSL) > 50 * _Point;
   if(!changed) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      double curSL = PositionGetDouble(POSITION_SL), curTP = PositionGetDouble(POSITION_TP);
      if(MathAbs(curSL - sl) < _Point && MathAbs(curTP - tp) < _Point) continue;
      trade.PositionModify(t, sl, tp);
     }
   syncedTP = tp; syncedSL = sl; syncedLayers = layers;
  }

//==================== HELPERS ====================
double BaseStep()
  {
   if(InpStepMode == STEP_ATR)
     {
      double a[];
      if(Buf(hATR, 1, 1, a) && a[0] > 0) return a[0] * InpStepATRMult;
     }
   return InpStepPrice;
  }

double NormLot(double lot)
  {
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(st <= 0) st = 0.01;
   lot = MathFloor(lot / st + 1e-9) * st;
   lot = MathMax(mn, MathMin(lot, MathMin(mx, InpMaxLot)));
   return NormalizeDouble(lot, 2);
  }

double LayerLot(int layerIndex)
  {
   double base = InpFixedLot;
   if(InpLotMode == LOT_AUTO && InpBalancePerLot > 0)
      base = 0.01 * MathFloor(AccountInfoDouble(ACCOUNT_BALANCE) / InpBalancePerLot);
   if(base <= 0) base = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   return NormLot(base * MathPow(InpLotMultiplier, layerIndex));
  }

bool MarginOK(int dir, double lot)
  {
   double price = dir == 1 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double m = 0;
   if(!OrderCalcMargin(dir == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, lot, price, m)) return false;
   return (AccountInfoDouble(ACCOUNT_MARGIN_FREE) - m) > AccountInfoDouble(ACCOUNT_EQUITY) * 0.3;
  }

bool Open(int dir, double lot, string tag)
  {
   bool ok = (dir == 1) ? trade.Buy(lot, _Symbol, 0, 0, 0, InpComment + "_" + tag)
                        : trade.Sell(lot, _Symbol, 0, 0, 0, InpComment + "_" + tag);
   if(ok && (trade.ResultRetcode() == TRADE_RETCODE_DONE || trade.ResultRetcode() == TRADE_RETCODE_PLACED))
     {
      lastLayerTime = TimeCurrent();
      tradesToday++;
      return true;
     }
   PrintFormat("Order fail: %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
   return false;
  }

//==================== S/R LEVELS ====================
bool AggMonths(datetime from, datetime to, double &o, double &h, double &l, double &c, datetime &t0)
  {
   MqlRates r[];
   int n = CopyRates(_Symbol, PERIOD_MN1, from, to, r);   // oldest first
   if(n <= 0) return false;
   o = r[0].open; c = r[n - 1].close; h = r[0].high; l = r[0].low; t0 = r[0].time;
   for(int i = 1; i < n; i++) { h = MathMax(h, r[i].high); l = MathMin(l, r[i].low); }
   return true;
  }

bool AggBars(ENUM_TIMEFRAMES tf, int start, int count, double &o, double &h, double &l, double &c, datetime &t0)
  {
   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(_Symbol, tf, start, count, r) != count) return false;
   o = r[count - 1].open; c = r[0].close; h = r[0].high; l = r[0].low; t0 = r[count - 1].time;
   for(int i = 1; i < count; i++) { h = MathMax(h, r[i].high); l = MathMin(l, r[i].low); }
   return true;
  }

datetime MonthStart(int year, int mon)
  {
   while(mon <= 0) { mon += 12; year--; }
   MqlDateTime d; ZeroMemory(d);
   d.year = year; d.mon = mon; d.day = 1;
   return StructToTime(d);
  }

void AddLevel(double price, int rank, string tag)
  {
   int n = ArraySize(levels);
   ArrayResize(levels, n + 1);
   levels[n].price = price; levels[n].rank = rank; levels[n].tag = tag;
  }

void DrawLine(string id, datetime t1, double price, color clr, int width, ENUM_LINE_STYLE style, string label, bool zone, datetime t2)
  {
   string n = SRPFX + id;
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_TREND, 0, t1, price, t2, price);
   else { ObjectMove(0, n, 0, t1, price); ObjectMove(0, n, 1, t2, price); }
   ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, n, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, n, OBJPROP_STYLE, style);
   ObjectSetInteger(0, n, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_BACK, true);
   ObjectSetString(0, n, OBJPROP_TOOLTIP, label + " " + DoubleToString(price, _Digits));

   string t = n + "_T";
   if(ObjectFind(0, t) < 0) ObjectCreate(0, t, OBJ_TEXT, 0, t2, price);
   else ObjectMove(0, t, 0, t2, price);
   ObjectSetString(0, t, OBJPROP_TEXT, label + " " + DoubleToString(price, _Digits));
   ObjectSetInteger(0, t, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, t, OBJPROP_FONTSIZE, 7);
   ObjectSetInteger(0, t, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, t, OBJPROP_SELECTABLE, false);

   if(zone && InpDrawZones && InpZoneHalf > 0)
     {
      string z = n + "_Z";
      if(ObjectFind(0, z) < 0) ObjectCreate(0, z, OBJ_RECTANGLE, 0, t1, price + InpZoneHalf, t2, price - InpZoneHalf);
      else { ObjectMove(0, z, 0, t1, price + InpZoneHalf); ObjectMove(0, z, 1, t2, price - InpZoneHalf); }
      ObjectSetInteger(0, z, OBJPROP_COLOR, InpZoneColor);
      ObjectSetInteger(0, z, OBJPROP_FILL, true);
      ObjectSetInteger(0, z, OBJPROP_BACK, true);
      ObjectSetInteger(0, z, OBJPROP_SELECTABLE, false);
     }
  }

void AddOHLC(string name, int rank, bool show, double o, double h, double l, double c, datetime t0,
             color clr, int width, ENUM_LINE_STYLE style, bool zone, datetime t2)
  {
   AddLevel(o, rank, name + "-O"); AddLevel(h, rank, name + "-H");
   AddLevel(l, rank, name + "-L"); AddLevel(c, rank, name + "-C");
   if(!InpShowLevels || !show) return;
   DrawLine(name + "_O", t0, o, clr, width, style, name + " Open",  zone, t2);
   DrawLine(name + "_H", t0, h, clr, width, style, name + " High",  zone, t2);
   DrawLine(name + "_L", t0, l, clr, width, style, name + " Low",   zone, t2);
   DrawLine(name + "_C", t0, c, clr, width, style, name + " Close", zone, t2);
  }

void UpdateLevels(bool force)
  {
   datetime h4 = iTime(_Symbol, PERIOD_H4, 0);
   if(!force && h4 == lastLevelsBar) return;
   if(!force && TimeCurrent() - lastLevelsTry < 10) return;   // history load retry throttle
   lastLevelsTry = TimeCurrent();

   ArrayResize(levels, 0);
   ObjectsDeleteAll(0, SRPFX);
   datetime t2 = TimeCurrent() + PeriodSeconds(PERIOD_H4) * 6;
   MqlDateTime now; TimeToStruct(TimeCurrent(), now);
   double o, h, l, c; datetime t0;
   bool ok = true;

   // Previous Year
   if(AggMonths(MonthStart(now.year - 1, 1), MonthStart(now.year - 1, 12), o, h, l, c, t0))
      AddOHLC("Y", 7, InpShowY, o, h, l, c, t0, clrRed, 3, STYLE_SOLID, true, t2);
   else ok = false;

   // Previous Half-year (Jan-Jun / Jul-Dec)
   int hs = (now.mon <= 6) ? 7 : 1;  int hy = (now.mon <= 6) ? now.year - 1 : now.year;
   if(AggMonths(MonthStart(hy, hs), MonthStart(hy, hs + 5), o, h, l, c, t0))
      AddOHLC("6M", 6, InpShow6M, o, h, l, c, t0, clrOrangeRed, 3, STYLE_SOLID, true, t2);
   else ok = false;

   // Previous Quarter
   int qStart = ((now.mon - 1) / 3) * 3 + 1 - 3;   // pichle quarter ka pehla month
   datetime qs = MonthStart(now.year, qStart);
   MqlDateTime qd; TimeToStruct(qs, qd);
   if(AggMonths(qs, MonthStart(qd.year, qd.mon + 2), o, h, l, c, t0))
      AddOHLC("3M", 5, InpShow3M, o, h, l, c, t0, clrOrange, 2, STYLE_SOLID, true, t2);
   else ok = false;

   if(AggBars(PERIOD_MN1, 1, 1, o, h, l, c, t0))
      AddOHLC("1M", 4, InpShow1M, o, h, l, c, t0, clrGold, 2, STYLE_SOLID, true, t2);
   else ok = false;

   if(AggBars(PERIOD_W1, 1, 1, o, h, l, c, t0))
      AddOHLC("W", 3, InpShowW, o, h, l, c, t0, clrDodgerBlue, 2, STYLE_SOLID, true, t2);
   else ok = false;

   if(AggBars(PERIOD_D1, 1, 3, o, h, l, c, t0))
      AddOHLC("3D", 2, InpShow3D, o, h, l, c, t0, clrMediumPurple, 1, STYLE_DASH, false, t2);
   else ok = false;

   if(AggBars(PERIOD_D1, 1, 1, o, h, l, c, t0))
      AddOHLC("D", 1, InpShowD, o, h, l, c, t0, clrSilver, 1, STYLE_DASH, false, t2);
   else ok = false;

   for(int i = 1; i <= InpH4Count; i++)
     {
      if(AggBars(PERIOD_H4, i, 1, o, h, l, c, t0))
         AddOHLC("H4#" + IntegerToString(i), 0, InpShowH4, o, h, l, c, t0, clrGray, 1, STYLE_DOT, false, t2);
      else ok = false;
     }

   if(ok) lastLevelsBar = h4;   // history poori nahi aayi to agle tick par phir try
   ChartRedraw();
  }

// BUY ke upar paas me resistance / SELL ke neeche paas me support ho to block
bool SRBlocked(int dir)
  {
   double price = dir == 1 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   for(int i = 0; i < ArraySize(levels); i++)
     {
      if(levels[i].rank < InpSRMinRank) continue;
      double d = levels[i].price - price;
      if(dir == 1 && d > 0 && d <= InpSRBlockDist)
        { PrintFormat("BUY skip: resistance %s %.2f paas me", levels[i].tag, levels[i].price); return true; }
      if(dir == -1 && d < 0 && -d <= InpSRBlockDist)
        { PrintFormat("SELL skip: support %s %.2f paas me", levels[i].tag, levels[i].price); return true; }
     }
   return false;
  }

//==================== NEWS ====================
void UpdateNews()
  {
   if(!InpUseNews || MQLInfoInteger(MQL_TESTER)) { newsActive = false; newsSoon = false; return; }
   if(TimeCurrent() - lastNewsCheck < 60) return;
   lastNewsCheck = TimeCurrent();
   newsActive = false; newsSoon = false;

   datetime now = TimeTradeServer();
   MqlCalendarValue vals[];
   if(CalendarValueHistory(vals, now - InpNewsAfterMin * 60, now + InpNewsBeforeMin * 60, NULL, "USD") <= 0)
      return;
   for(int i = 0; i < ArraySize(vals); i++)
     {
      MqlCalendarEvent ev;
      if(!CalendarEventById(vals[i].event_id, ev)) continue;
      if(ev.importance != CALENDAR_IMPORTANCE_HIGH) continue;
      newsActive = true;
      if(vals[i].time >= now) newsSoon = true;
     }
  }

//==================== PANEL ====================
void ShowPanel()
  {
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return;
   int d; double avg, lots, lp, pr; int layers;
   GetBasket(d, layers, avg, lots, lp, pr);
   Comment(StringFormat(
      "GoldDCA_EA v1.20 | %s\n"
      "Status      : %s\n"
      "Trend (%s)  : %s\n"
      "News        : %s\n"
      "Basket      : %s  layers %d/%d  lots %.2f\n"
      "Avg price   : %.2f   Basket P/L: %.2f\n"
      "Auto TP/SL  : %.2f / %.2f\n"
      "Today P/L   : %.2f%%  (target %.1f%%, max loss %.1f%%)\n"
      "Today       : %d baskets, %d trades",
      _Symbol,
      dayStopped ? "STOPPED (daily loss)" : (DayPLPct() >= InpDailyTargetPct && InpDailyTargetPct > 0 ? "Daily target hit" : "Running"),
      EnumToString(InpTrendTF), TrendDir() == 1 ? "UP" : (TrendDir() == -1 ? "DOWN" : "SIDEWAYS - no entry"),
      newsActive ? "HIGH IMPACT - paused" : "Clear",
      d == 1 ? "BUY" : (d == -1 ? "SELL" : "-"), layers, InpMaxLayers, lots,
      avg, pr, syncedTP, syncedSL, DayPLPct(), InpDailyTargetPct, InpDailyLossPct, basketsToday, tradesToday));
  }
//+------------------------------------------------------------------+
