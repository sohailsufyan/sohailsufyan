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
#property version   "1.00"

#include <Trade/Trade.mqh>

enum ENUM_LOT_MODE { LOT_FIXED = 0, LOT_AUTO = 1 };
enum ENUM_STEP_MODE { STEP_FIXED_PRICE = 0, STEP_ATR = 1 };

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
input double          InpTPPrice          = 2.0;          // Average price se $X profit par sab close
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

input group "=== News Filter (live only, MT5 calendar) ==="
input bool            InpUseNews          = true;         // News filter ON
input int             InpNewsBeforeMin    = 30;           // High-impact USD news se pehle (min)
input int             InpNewsAfterMin     = 30;           // News ke baad (min)
input bool            InpNewsNoDCA        = true;         // News window me DCA layer bhi nahi
input bool            InpNewsCloseProfit  = true;         // News se pehle basket profit me ho to close

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
int      hRSI = INVALID_HANDLE, hATR = INVALID_HANDLE;
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
   if(hTF == INVALID_HANDLE || hTS == INVALID_HANDLE || hSF == INVALID_HANDLE ||
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
   basketStartEq = AccountInfoDouble(ACCOUNT_EQUITY);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   IndicatorRelease(hTF); IndicatorRelease(hTS); IndicatorRelease(hSF);
   IndicatorRelease(hSS); IndicatorRelease(hRSI); IndicatorRelease(hATR);
   Comment("");
  }

//+------------------------------------------------------------------+
void OnTick()
  {
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
   bool tpHit = (dir == 1) ? (bid >= avg + InpTPPrice) : (ask <= avg - InpTPPrice);
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

   double c = iClose(_Symbol, InpSignalTF, 1);
   double o = iOpen(_Symbol, InpSignalTF, 1);

   if(trend == 1 && f[0] > s[0] && c > f[0] && c > o && r[0] >= InpRSIBuyMin && r[0] <= InpRSIBuyMax)
      return 1;
   if(trend == -1 && f[0] < s[0] && c < f[0] && c < o && r[0] >= InpRSISellMin && r[0] <= InpRSISellMax)
      return -1;
   return 0;
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
      "GoldDCA_EA v1.00 | %s\n"
      "Status      : %s\n"
      "Trend (%s)  : %s\n"
      "News        : %s\n"
      "Basket      : %s  layers %d/%d  lots %.2f\n"
      "Avg price   : %.2f   Basket P/L: %.2f\n"
      "Today P/L   : %.2f%%  (target %.1f%%, max loss %.1f%%)\n"
      "Today       : %d baskets, %d trades",
      _Symbol,
      dayStopped ? "STOPPED (daily loss)" : (DayPLPct() >= InpDailyTargetPct && InpDailyTargetPct > 0 ? "Daily target hit" : "Running"),
      EnumToString(InpTrendTF), TrendDir() == 1 ? "UP" : (TrendDir() == -1 ? "DOWN" : "SIDEWAYS - no entry"),
      newsActive ? "HIGH IMPACT - paused" : "Clear",
      d == 1 ? "BUY" : (d == -1 ? "SELL" : "-"), layers, InpMaxLayers, lots,
      avg, pr, DayPLPct(), InpDailyTargetPct, InpDailyLossPct, basketsToday, tradesToday));
  }
//+------------------------------------------------------------------+
