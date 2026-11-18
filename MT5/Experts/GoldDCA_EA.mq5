//+------------------------------------------------------------------+
//|                                                GoldDCA_EA.mq5    |
//|  XAUUSD Trend-following DCA EA - SCALP + INTRADAY (dono saath)   |
//|  - Master trend (H1) ki direction me hi dono engine trade lete   |
//|  - Scalp   : M5 signal, M15 trend, chhota step/TP, kam layers    |
//|  - Intraday: M15 signal, H1 trend, $7 step, bada TP              |
//|  - Har engine ka alag basket (alag magic), alag TP/SL            |
//|  - MACD + RSI + ATR confirm, S/R levels, news filter, daily limit|
//|  WARNING: DCA me ek bada trend against ho to bada loss ho sakta  |
//|  hai. Basket hard stop OFF mat karein.                           |
//+------------------------------------------------------------------+
#property copyright "GoldDCA_EA"
#property version   "2.00"

#include <Trade/Trade.mqh>

enum ENUM_LOT_MODE  { LOT_FIXED = 0, LOT_AUTO = 1 };
enum ENUM_STEP_MODE { STEP_FIXED_PRICE = 0, STEP_ATR = 1 };
enum ENUM_TP_MODE   { TP_FIXED_PRICE = 0, TP_ATR = 1 };

input group "=== General ==="
input long            InpMagic            = 888001;       // Base magic (Scalp = +1, Intraday = +2)
input string          InpComment          = "GoldDCA";    // Order comment
input ENUM_TIMEFRAMES InpMasterTF         = PERIOD_H1;    // Master trend timeframe (dono engine follow karenge)
input int             InpMasterFastEMA    = 50;           // Master fast EMA
input int             InpMasterSlowEMA    = 200;          // Master slow EMA
input bool            InpNoOpposite       = true;         // Ek engine BUY me ho to doosra SELL na khole

input group "=== Lot Size (shared) ==="
input ENUM_LOT_MODE   InpLotMode          = LOT_AUTO;     // Lot mode
input double          InpFixedLot         = 0.01;         // Fixed first lot
input double          InpBalancePerLot    = 1000.0;       // AUTO: har itne $ balance par 0.01 lot
input double          InpMaxLot           = 2.0;          // Max lot per layer

input group "=== SCALP Engine ==="
input bool            InpScOn             = true;             // Scalp ON
input ENUM_TIMEFRAMES InpScSigTF          = PERIOD_M5;        // Scalp signal TF
input ENUM_TIMEFRAMES InpScTrendTF        = PERIOD_M15;       // Scalp trend TF
input double          InpScLotFactor      = 1.0;              // Scalp first lot x base lot
input double          InpScLotMult        = 1.2;              // Scalp DCA lot multiplier
input ENUM_STEP_MODE  InpScStepMode       = STEP_FIXED_PRICE; // Scalp step mode
input double          InpScStep           = 4.0;              // Scalp DCA step ($)
input double          InpScStepATR        = 1.0;              // Scalp step ATR x (ATR mode)
input double          InpScStepGrowth     = 1.2;              // Scalp step growth
input int             InpScMaxLayers      = 4;                // Scalp max layers
input ENUM_TP_MODE    InpScTPMode         = TP_ATR;           // Scalp TP mode
input double          InpScTP             = 1.0;              // Scalp fixed TP ($ from average)
input double          InpScTP_ATR         = 0.6;              // Scalp TP ATR x
input double          InpScTPMin          = 0.8;              // Scalp min TP ($)
input double          InpScStopPct        = 6.0;              // Scalp basket hard stop (% equity)
input int             InpScCooldownMin    = 2;                // Scalp cooldown (min)
input int             InpScMaxBaskets     = 30;               // Scalp max baskets/day
input double          InpScMaxATR         = 8.0;              // Scalp: signal ATR max ($)
input double          InpScMinATR         = 0.5;              // Scalp: signal ATR min ($)

input group "=== INTRADAY Engine ==="
input bool            InpInOn             = true;             // Intraday ON
input ENUM_TIMEFRAMES InpInSigTF          = PERIOD_M15;       // Intraday signal TF
input ENUM_TIMEFRAMES InpInTrendTF        = PERIOD_H1;        // Intraday trend TF
input double          InpInLotFactor      = 1.0;              // Intraday first lot x base lot
input double          InpInLotMult        = 1.3;              // Intraday DCA lot multiplier
input ENUM_STEP_MODE  InpInStepMode       = STEP_FIXED_PRICE; // Intraday step mode
input double          InpInStep           = 7.0;              // Intraday DCA step ($)
input double          InpInStepATR        = 1.0;              // Intraday step ATR x (ATR mode)
input double          InpInStepGrowth     = 1.2;              // Intraday step growth
input int             InpInMaxLayers      = 6;                // Intraday max layers
input ENUM_TP_MODE    InpInTPMode         = TP_ATR;           // Intraday TP mode
input double          InpInTP             = 2.0;              // Intraday fixed TP ($ from average)
input double          InpInTP_ATR         = 0.5;              // Intraday TP ATR x
input double          InpInTPMin          = 1.5;              // Intraday min TP ($)
input double          InpInStopPct        = 12.0;             // Intraday basket hard stop (% equity)
input int             InpInCooldownMin    = 5;                // Intraday cooldown (min)
input int             InpInMaxBaskets     = 20;               // Intraday max baskets/day
input double          InpInMaxATR         = 15.0;             // Intraday: signal ATR max ($)
input double          InpInMinATR         = 1.0;              // Intraday: signal ATR min ($)

input group "=== DCA / Exit (shared) ==="
input int             InpMinSecBetween    = 60;           // Layers ke beech min seconds
input bool            InpAddOnlyInTrend   = true;         // Trend palat jaye to naya layer mat jodo
input bool            InpBrokerSLTP       = true;         // Auto SL/TP broker par bhi lagao

input group "=== Daily Limits (account) ==="
input double          InpDailyTargetPct   = 5.0;          // Daily target % - hit hone par naye basket band
input double          InpDailyLossPct     = 15.0;         // Daily max loss % - sab close, din band

input group "=== Entry Indicators (shared) ==="
input int             InpTrendFastEMA     = 50;           // Engine trend TF fast EMA
input int             InpTrendSlowEMA     = 200;          // Engine trend TF slow EMA
input int             InpSigFastEMA       = 9;            // Signal TF fast EMA
input int             InpSigSlowEMA       = 21;           // Signal TF slow EMA
input int             InpRSIPeriod        = 14;           // RSI period
input double          InpRSIBuyMin        = 50;           // BUY: RSI min
input double          InpRSIBuyMax        = 72;           // BUY: RSI max
input double          InpRSISellMin       = 28;           // SELL: RSI min
input double          InpRSISellMax       = 50;           // SELL: RSI max
input int             InpATRPeriod        = 14;           // ATR period
input bool            InpUseMACD          = true;         // MACD confirm ON
input int             InpMACDFast         = 12;           // MACD fast
input int             InpMACDSlow         = 26;           // MACD slow
input int             InpMACDSignal       = 9;            // MACD signal
input bool            InpMACDZeroLine     = true;         // BUY: MACD > 0, SELL: MACD < 0

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
input double          InpZoneHalf         = 1.0;          // Zone half-width ($) - Y/6M/3M/1M/W
input bool            InpDrawSmallZones   = true;         // 3D / D / H4 levels par bhi zone (box)
input double          InpZoneHalfSmall    = 0.5;          // Zone half-width ($) - 3D/D/H4
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

//==================== ENGINE ====================
struct Engine
  {
   string            name;
   bool              on;
   long              magic;
   ENUM_TIMEFRAMES   sigTF, trendTF;
   int               hTF, hTS, hSF, hSS, hRSI, hATR, hMACD;
   double            lotFactor, lotMult;
   int               stepMode; double step, stepATR, stepGrowth;
   int               maxLayers;
   int               tpMode; double tp, tpATR, tpMin;
   double            stopPct, maxATR, minATR;
   int               cooldownMin, maxBaskets;
   // state
   datetime          lastSigBar, lastCloseTime, lastLayerTime;
   double            basketStartEq, syncedTP, syncedSL;
   int               syncedLayers, basketsToday, tradesToday;
  };

CTrade   trade;
Engine   E[2];
int      hMF = INVALID_HANDLE, hMS = INVALID_HANDLE;
datetime lastNewsCheck = 0;
bool     newsActive = false, newsSoon = false, dayStopped = false;
double   dayStartEq = 0;
int      dayKey = -1;

struct SRLevel { double price; int rank; string tag; };
SRLevel  levels[];
datetime lastLevelsBar = 0, lastLevelsTry = 0;
#define  SRPFX "GDCA_SR_"

bool SetupEngine(Engine &e, string name, bool on, long magic, ENUM_TIMEFRAMES sig, ENUM_TIMEFRAMES tr,
                 double lotF, double lotM, int stepMode, double step, double stepATR, double growth, int layers,
                 int tpMode, double tp, double tpATR, double tpMin, double stopPct, int cool, int maxB,
                 double maxATR, double minATR)
  {
   e.name = name; e.on = on; e.magic = magic; e.sigTF = sig; e.trendTF = tr;
   e.lotFactor = lotF; e.lotMult = lotM; e.stepMode = stepMode; e.step = step; e.stepATR = stepATR;
   e.stepGrowth = growth; e.maxLayers = layers; e.tpMode = tpMode; e.tp = tp; e.tpATR = tpATR; e.tpMin = tpMin;
   e.stopPct = stopPct; e.cooldownMin = cool; e.maxBaskets = maxB; e.maxATR = maxATR; e.minATR = minATR;
   e.lastSigBar = 0; e.lastCloseTime = 0; e.lastLayerTime = 0;
   e.basketStartEq = AccountInfoDouble(ACCOUNT_EQUITY); e.syncedTP = 0; e.syncedSL = 0;
   e.syncedLayers = 0; e.basketsToday = 0; e.tradesToday = 0;
   e.hTF = e.hTS = e.hSF = e.hSS = e.hRSI = e.hATR = e.hMACD = INVALID_HANDLE;
   if(!on) return true;
   e.hTF   = iMA(_Symbol, tr,  InpTrendFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   e.hTS   = iMA(_Symbol, tr,  InpTrendSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   e.hSF   = iMA(_Symbol, sig, InpSigFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   e.hSS   = iMA(_Symbol, sig, InpSigSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   e.hRSI  = iRSI(_Symbol, sig, InpRSIPeriod, PRICE_CLOSE);
   e.hATR  = iATR(_Symbol, sig, InpATRPeriod);
   e.hMACD = iMACD(_Symbol, sig, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE);
   return !(e.hTF == INVALID_HANDLE || e.hTS == INVALID_HANDLE || e.hSF == INVALID_HANDLE ||
            e.hSS == INVALID_HANDLE || e.hRSI == INVALID_HANDLE || e.hATR == INVALID_HANDLE || e.hMACD == INVALID_HANDLE);
  }

void ReleaseEngine(Engine &e)
  {
   if(!e.on) return;
   IndicatorRelease(e.hTF); IndicatorRelease(e.hTS); IndicatorRelease(e.hSF); IndicatorRelease(e.hSS);
   IndicatorRelease(e.hRSI); IndicatorRelease(e.hATR); IndicatorRelease(e.hMACD);
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetDeviationInPoints(50);
   trade.SetTypeFillingBySymbol(_Symbol);

   hMF = iMA(_Symbol, InpMasterTF, InpMasterFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hMS = iMA(_Symbol, InpMasterTF, InpMasterSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   if(hMF == INVALID_HANDLE || hMS == INVALID_HANDLE) return(INIT_FAILED);

   if(!SetupEngine(E[0], "SCALP", InpScOn, InpMagic + 1, InpScSigTF, InpScTrendTF, InpScLotFactor, InpScLotMult,
                   InpScStepMode, InpScStep, InpScStepATR, InpScStepGrowth, InpScMaxLayers,
                   InpScTPMode, InpScTP, InpScTP_ATR, InpScTPMin, InpScStopPct, InpScCooldownMin, InpScMaxBaskets,
                   InpScMaxATR, InpScMinATR))
     { Print("Scalp indicator error: ", GetLastError()); return(INIT_FAILED); }
   if(!SetupEngine(E[1], "INTRADAY", InpInOn, InpMagic + 2, InpInSigTF, InpInTrendTF, InpInLotFactor, InpInLotMult,
                   InpInStepMode, InpInStep, InpInStepATR, InpInStepGrowth, InpInMaxLayers,
                   InpInTPMode, InpInTP, InpInTP_ATR, InpInTPMin, InpInStopPct, InpInCooldownMin, InpInMaxBaskets,
                   InpInMaxATR, InpInMinATR))
     { Print("Intraday indicator error: ", GetLastError()); return(INIT_FAILED); }

   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("WARNING: Ye EA HEDGING account ke liye hai. Netting account par layers merge ho jayenge.");
   if(InpScStopPct <= 0 || InpInStopPct <= 0)
      Print("WARNING: Basket hard stop OFF hai - ek galat trend poora account khatam kar sakta hai!");

   ResetDay();
   UpdateLevels(true);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   IndicatorRelease(hMF); IndicatorRelease(hMS);
   ReleaseEngine(E[0]); ReleaseEngine(E[1]);
   ObjectsDeleteAll(0, SRPFX);
   Comment("");
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   UpdateLevels(false);
   CheckNewDay();
   UpdateNews();

   for(int k = 0; k < 2; k++)
     {
      if(!E[k].on && CountLayers(E[k]) == 0) continue;
      int dir, layers; double avg, lots, lastPrice, profit;
      GetBasket(E[k], dir, layers, avg, lots, lastPrice, profit);
      if(layers > 0)
         ManageBasket(E[k], dir, layers, avg, lastPrice, profit);
      else
         if(E[k].on)
            TryNewBasket(E[k], k);
     }
   ShowPanel();
  }

//==================== DAY TRACKING ====================
void ResetDay()
  {
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   dayKey = dt.year * 1000 + dt.day_of_year;
   dayStartEq = AccountInfoDouble(ACCOUNT_EQUITY);
   dayStopped = false;
   for(int k = 0; k < 2; k++) { E[k].basketsToday = 0; E[k].tradesToday = 0; }
  }

void CheckNewDay()
  {
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.year * 1000 + dt.day_of_year != dayKey && CountLayers(E[0]) + CountLayers(E[1]) == 0)
      ResetDay();

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(!dayStopped && dayStartEq > 0 && InpDailyLossPct > 0 &&
      (dayStartEq - eq) / dayStartEq * 100.0 >= InpDailyLossPct)
     {
      PrintFormat("Daily loss %.1f%% hit - sab close, aaj trading band.", InpDailyLossPct);
      CloseBasket(E[0]); CloseBasket(E[1]);
      dayStopped = true;
     }
  }

double DayPLPct()
  {
   if(dayStartEq <= 0) return 0;
   return (AccountInfoDouble(ACCOUNT_EQUITY) - dayStartEq) / dayStartEq * 100.0;
  }

//==================== BASKET ====================
bool IsMine(Engine &e)
  {
   return PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == e.magic;
  }

int CountLayers(Engine &e)
  {
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0) continue;
      if(IsMine(e)) c++;
     }
   return c;
  }

void GetBasket(Engine &e, int &dir, int &layers, double &avg, double &lots, double &lastPrice, double &profit)
  {
   dir = 0; layers = 0; avg = 0; lots = 0; lastPrice = 0; profit = 0;
   double sumPV = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0) continue;
      if(!IsMine(e)) continue;
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

void ManageBasket(Engine &e, int dir, int layers, double avg, double lastPrice, double profit)
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(InpBrokerSLTP) SyncSLTP(e, dir, layers, avg);

   //--- 1) Basket TP
   double tpDist = TPDist(e);
   bool tpHit = (dir == 1) ? (bid >= avg + tpDist) : (ask <= avg - tpDist);
   if(tpHit && profit > 0)
     {
      PrintFormat("[%s] Basket TP: %d layers, profit %.2f", e.name, layers, profit);
      CloseBasket(e);
      return;
     }

   //--- 2) Hard stop
   if(e.stopPct > 0 && e.basketStartEq > 0 && profit < 0 &&
      (-profit) / e.basketStartEq * 100.0 >= e.stopPct)
     {
      PrintFormat("[%s] BASKET HARD STOP: loss %.2f (%.1f%%). Sab close.", e.name, profit, e.stopPct);
      CloseBasket(e);
      return;
     }

   //--- 3) News se pehle profit lock
   if(InpUseNews && InpNewsCloseProfit && newsSoon && profit > 0)
     {
      PrintFormat("[%s] High-impact news aa rahi hai - basket profit me close.", e.name);
      CloseBasket(e);
      return;
     }

   //--- 4) DCA layer
   if(!e.on || dayStopped) return;
   if(layers >= e.maxLayers) return;
   if(InpUseNews && InpNewsNoDCA && newsActive) return;
   if(TimeCurrent() - e.lastLayerTime < InpMinSecBetween) return;
   if(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpreadPoints) return;
   if(InpAddOnlyInTrend && TrendDir(e.hTF, e.hTS, e.trendTF) != dir) return;

   double step = BaseStep(e) * MathPow(e.stepGrowth, layers - 1);
   bool add = (dir == 1) ? (ask <= lastPrice - step) : (bid >= lastPrice + step);
   if(!add) return;

   double lot = LayerLot(e, layers);
   if(!MarginOK(dir, lot)) { PrintFormat("[%s] Margin kam - DCA layer skip.", e.name); return; }
   if(Open(e, dir, lot, "L" + IntegerToString(layers + 1)))
      PrintFormat("[%s] DCA layer %d @ %.2f, lot %.2f", e.name, layers + 1, dir == 1 ? ask : bid, lot);
  }

void CloseBasket(Engine &e)
  {
   trade.SetExpertMagicNumber(e.magic);
   for(int pass = 0; pass < 3; pass++)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(t == 0) continue;
         if(IsMine(e)) trade.PositionClose(t);
        }
      if(CountLayers(e) == 0) break;
     }
   e.lastCloseTime = TimeCurrent();
   e.syncedTP = 0; e.syncedSL = 0; e.syncedLayers = 0;
   e.basketStartEq = AccountInfoDouble(ACCOUNT_EQUITY);
  }

//==================== ENTRY ====================
void TryNewBasket(Engine &e, int k)
  {
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dayStopped) return;
   if(InpDailyTargetPct > 0 && DayPLPct() >= InpDailyTargetPct) return;
   if(e.basketsToday >= e.maxBaskets) return;
   if(TimeCurrent() - e.lastCloseTime < e.cooldownMin * 60) return;
   if(InpUseNews && (newsActive || newsSoon)) return;
   if(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpreadPoints) return;
   if(InpUseSession && (dt.hour < InpSessionStart || dt.hour >= InpSessionEnd)) return;
   if(InpFridayStop && dt.day_of_week == 5 && dt.hour >= 20) return;

   datetime bar = iTime(_Symbol, e.sigTF, 0);
   if(bar == 0 || bar == e.lastSigBar) return;
   e.lastSigBar = bar;

   int sig = Signal(e);
   if(sig == 0) return;
   if(sig == 1 && !InpAllowBuy) return;
   if(sig == -1 && !InpAllowSell) return;

   // Doosre engine ka basket ulti direction me ho to skip
   if(InpNoOpposite)
     {
      int od, ol; double oa, olots, olp, opr;
      GetBasket(E[1 - k], od, ol, oa, olots, olp, opr);
      if(ol > 0 && od != sig) return;
     }

   if(InpUseSRFilter && SRBlocked(sig)) return;

   double lot = LayerLot(e, 0);
   if(!MarginOK(sig, lot)) return;
   e.basketStartEq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(Open(e, sig, lot, "L1"))
     {
      e.basketsToday++;
      PrintFormat("[%s] New %s basket, lot %.2f", e.name, sig == 1 ? "BUY" : "SELL", lot);
     }
  }

bool Buf(int h, int start, int count, double &a[])
  {
   ArraySetAsSeries(a, true);
   return CopyBuffer(h, 0, start, count, a) == count;
  }

int TrendDir(int hf, int hs, ENUM_TIMEFRAMES tf)
  {
   double f[], s[];
   if(!Buf(hf, 1, 1, f) || !Buf(hs, 1, 1, s)) return 0;
   double c = iClose(_Symbol, tf, 1);
   if(f[0] > s[0] && c > f[0]) return 1;
   if(f[0] < s[0] && c < f[0]) return -1;
   return 0;
  }

int MasterTrend() { return TrendDir(hMF, hMS, InpMasterTF); }

int Signal(Engine &e)
  {
   int trend = TrendDir(e.hTF, e.hTS, e.trendTF);
   if(trend == 0 || trend != MasterTrend()) return 0;   // engine trend + master trend dono same

   double f[], s[], r[], a[];
   if(!Buf(e.hSF, 1, 2, f) || !Buf(e.hSS, 1, 2, s) || !Buf(e.hRSI, 1, 1, r) || !Buf(e.hATR, 1, 1, a)) return 0;
   if(e.maxATR > 0 && a[0] > e.maxATR) return 0;   // bahut volatile
   if(e.minATR > 0 && a[0] < e.minATR) return 0;   // market dead

   if(InpUseMACD)
     {
      double mm[], ms[];
      ArraySetAsSeries(mm, true); ArraySetAsSeries(ms, true);
      if(CopyBuffer(e.hMACD, 0, 1, 2, mm) != 2 || CopyBuffer(e.hMACD, 1, 1, 2, ms) != 2) return 0;
      double h0 = mm[0] - ms[0], h1 = mm[1] - ms[1];
      bool macdBuy  = (mm[0] > ms[0]) && (h0 >= h1) && (!InpMACDZeroLine || mm[0] > 0);
      bool macdSell = (mm[0] < ms[0]) && (h0 <= h1) && (!InpMACDZeroLine || mm[0] < 0);
      if(trend == 1 && !macdBuy) return 0;
      if(trend == -1 && !macdSell) return 0;
     }

   double c = iClose(_Symbol, e.sigTF, 1);
   double o = iOpen(_Symbol, e.sigTF, 1);
   if(trend == 1 && f[0] > s[0] && c > f[0] && c > o && r[0] >= InpRSIBuyMin && r[0] <= InpRSIBuyMax)
      return 1;
   if(trend == -1 && f[0] < s[0] && c < f[0] && c < o && r[0] >= InpRSISellMin && r[0] <= InpRSISellMax)
      return -1;
   return 0;
  }

//==================== AUTO TP / SL ====================
double SigATR(Engine &e)
  {
   double a[];
   if(Buf(e.hATR, 1, 1, a)) return a[0];
   return 0;
  }

double TPDist(Engine &e)
  {
   if(e.tpMode == TP_ATR)
     {
      double a = SigATR(e);
      if(a > 0) return MathMax(a * e.tpATR, e.tpMin);
     }
   return e.tp;
  }

void SyncSLTP(Engine &e, int dir, int layers, double avg)
  {
   int    digits  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double minStop = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point + 5 * _Point;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double totalLots = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0) continue;
      if(IsMine(e)) totalLots += PositionGetDouble(POSITION_VOLUME);
     }
   if(totalLots <= 0) return;

   double tp = NormalizeDouble(dir == 1 ? avg + TPDist(e) : avg - TPDist(e), digits);
   double sl = 0;
   if(e.stopPct > 0 && e.basketStartEq > 0)
     {
      double perDollar = 0;
      ENUM_ORDER_TYPE ot = dir == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(OrderCalcProfit(ot, _Symbol, 1.0, avg, dir == 1 ? avg + 1.0 : avg - 1.0, perDollar) && perDollar > 0)
        {
         double dist = (e.basketStartEq * e.stopPct / 100.0) / (totalLots * perDollar);
         sl = NormalizeDouble(dir == 1 ? avg - dist : avg + dist, digits);
        }
     }

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

   bool changed = (layers != e.syncedLayers) || MathAbs(tp - e.syncedTP) > 50 * _Point || MathAbs(sl - e.syncedSL) > 50 * _Point;
   if(!changed) return;

   trade.SetExpertMagicNumber(e.magic);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!IsMine(e)) continue;
      double curSL = PositionGetDouble(POSITION_SL), curTP = PositionGetDouble(POSITION_TP);
      if(MathAbs(curSL - sl) < _Point && MathAbs(curTP - tp) < _Point) continue;
      trade.PositionModify(t, sl, tp);
     }
   e.syncedTP = tp; e.syncedSL = sl; e.syncedLayers = layers;
  }

//==================== HELPERS ====================
double BaseStep(Engine &e)
  {
   if(e.stepMode == STEP_ATR)
     {
      double a = SigATR(e);
      if(a > 0) return a * e.stepATR;
     }
   return e.step;
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

double LayerLot(Engine &e, int layerIndex)
  {
   double base = InpFixedLot;
   if(InpLotMode == LOT_AUTO && InpBalancePerLot > 0)
      base = 0.01 * MathFloor(AccountInfoDouble(ACCOUNT_BALANCE) / InpBalancePerLot);
   if(base <= 0) base = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   return NormLot(base * e.lotFactor * MathPow(e.lotMult, layerIndex));
  }

bool MarginOK(int dir, double lot)
  {
   double price = dir == 1 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double m = 0;
   if(!OrderCalcMargin(dir == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, lot, price, m)) return false;
   return (AccountInfoDouble(ACCOUNT_MARGIN_FREE) - m) > AccountInfoDouble(ACCOUNT_EQUITY) * 0.3;
  }

bool Open(Engine &e, int dir, double lot, string tag)
  {
   trade.SetExpertMagicNumber(e.magic);
   string cm = InpComment + "_" + (e.magic == InpMagic + 1 ? "SC" : "IN") + "_" + tag;
   bool ok = (dir == 1) ? trade.Buy(lot, _Symbol, 0, 0, 0, cm) : trade.Sell(lot, _Symbol, 0, 0, 0, cm);
   if(ok && (trade.ResultRetcode() == TRADE_RETCODE_DONE || trade.ResultRetcode() == TRADE_RETCODE_PLACED))
     {
      e.lastLayerTime = TimeCurrent();
      e.tradesToday++;
      return true;
     }
   PrintFormat("[%s] Order fail: %d %s", e.name, trade.ResultRetcode(), trade.ResultRetcodeDescription());
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

void DrawLine(string id, datetime t1, double price, color clr, int width, ENUM_LINE_STYLE style, string label, double zone, datetime t2)
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

   if(zone > 0)
     {
      string z = n + "_Z";
      if(ObjectFind(0, z) < 0) ObjectCreate(0, z, OBJ_RECTANGLE, 0, t1, price + zone, t2, price - zone);
      else { ObjectMove(0, z, 0, t1, price + zone); ObjectMove(0, z, 1, t2, price - zone); }
      ObjectSetInteger(0, z, OBJPROP_COLOR, InpZoneColor);
      ObjectSetInteger(0, z, OBJPROP_FILL, true);
      ObjectSetInteger(0, z, OBJPROP_BACK, true);
      ObjectSetInteger(0, z, OBJPROP_SELECTABLE, false);
     }
  }

void AddOHLC(string name, int rank, bool show, double o, double h, double l, double c, datetime t0,
             color clr, int width, ENUM_LINE_STYLE style, bool big, datetime t2)
  {
   AddLevel(o, rank, name + "-O"); AddLevel(h, rank, name + "-H");
   AddLevel(l, rank, name + "-L"); AddLevel(c, rank, name + "-C");
   if(!InpShowLevels || !show) return;
   double zone = big ? (InpDrawZones ? InpZoneHalf : 0) : (InpDrawSmallZones ? InpZoneHalfSmall : 0);
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
string EngineLine(Engine &e)
  {
   if(!e.on && CountLayers(e) == 0) return e.name + "   : OFF";
   int d, layers; double avg, lots, lp, pr;
   GetBasket(e, d, layers, avg, lots, lp, pr);
   int tr = TrendDir(e.hTF, e.hTS, e.trendTF);
   return StringFormat("%-8s: trend %s | %s %d/%d lots %.2f avg %.2f P/L %.2f | TP %.2f SL %.2f | today %d baskets",
                       e.name, tr == 1 ? "UP" : (tr == -1 ? "DOWN" : "SIDE"),
                       d == 1 ? "BUY" : (d == -1 ? "SELL" : "-"), layers, e.maxLayers, lots, avg, pr,
                       e.syncedTP, e.syncedSL, e.basketsToday);
  }

void ShowPanel()
  {
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return;
   int mt = MasterTrend();
   string status = dayStopped ? "STOPPED (daily loss)" :
                   (InpDailyTargetPct > 0 && DayPLPct() >= InpDailyTargetPct ? "Daily target hit" : "Running");
   Comment(StringFormat(
      "GoldDCA_EA v2.00 (Scalp + Intraday) | %s\n"
      "Status    : %s\n"
      "Master %s : %s\n"
      "News      : %s\n"
      "%s\n%s\n"
      "Today P/L : %.2f%%  (target %.1f%%, max loss %.1f%%)  trades %d",
      _Symbol, status, EnumToString(InpMasterTF),
      mt == 1 ? "UP - sirf BUY" : (mt == -1 ? "DOWN - sirf SELL" : "SIDEWAYS - no entry"),
      newsActive ? "HIGH IMPACT - paused" : "Clear",
      EngineLine(E[0]), EngineLine(E[1]),
      DayPLPct(), InpDailyTargetPct, InpDailyLossPct, E[0].tradesToday + E[1].tradesToday));
  }
//+------------------------------------------------------------------+
