//+------------------------------------------------------------------+
//|                                               GoldBreakoutEA.mq5 |
//|                 XAUUSD Asian-range breakout (London / New York)  |
//+------------------------------------------------------------------+
#property copyright "sohailsufyan"
#property version   "1.00"
#property description "XAUUSD Asian-range breakout EA. Risk % lot, SL/TP on every order, daily protection."

/*
 WHAT IT DOES
 ------------
 1. Every server day it measures the "Asian range": highest high and lowest low of
    M5 bars between InpRangeStartHour and InpRangeEndHour (SERVER time).
 2. If the range size is between InpMinRange and InpMaxRange ($ price move), the day
    is tradable. The range is drawn on the chart as a rectangle.
 3. Between InpTradeStartHour and InpTradeEndHour, on each CLOSED bar of the chart
    timeframe (M15 recommended):
      BUY  when close > range high + InpBreakBuffer
      SELL when close < range low  - InpBreakBuffer
    Optional trend filter: buy only above EMA(InpTrendEMA) on InpTrendTF, sell only below.
    Max one buy and one sell per day, and at most InpMaxTradesPerDay entries.
 4. SL distance = range size x InpSLRangeFrac, clamped to [InpMinSL, InpMaxSL] $.
    TP = SL distance x InpRR. Both are sent with the order (broker-side).
 5. Management (every tick): breakeven at InpBE_R x R (locks InpBE_Lock $),
    optional trailing. All EA trades are closed at InpCloseHour (no overnight).

 LOT SIZE
 --------
 InpFixedLot > 0 -> that lot is used (clamped to broker min/max/step).
 InpFixedLot = 0 -> lot = balance x InpRiskPercent% / loss-per-lot at the SL distance.
   If that lot is below the broker minimum the trade is SKIPPED (no over-risking).
   Orders larger than SYMBOL_VOLUME_MAX are split into several orders.

 PROTECTION (all ON by default)
 ------------------------------
 - Max daily loss %  : equity down this much vs day-start equity -> no new trades today.
 - Equity stop %     : equity down this much vs day-start equity -> close all EA trades, halt today.
 - Max total lots, max spread, Friday stop hour, close-all switch.

 ASSUMPTIONS
 -----------
 - All hours are SERVER time (TimeCurrent). Defaults fit a GMT+2/+3 broker:
   00-07 = Asian session, 08-16 = London + NY open.
 - "$" distances are price moves (3.00 = gold moving $3). Works for 2- and 3-digit quotes.
 - Only positions with InpMagic on this symbol are touched. Manual trades are ignored.
 - Day-start equity is taken at the first tick of the server day (or when the EA starts).
 - R for breakeven/trailing = today's SL distance (positions are closed the same day).

 WHAT IT NEVER DOES
 ------------------
 No martingale, no grid, no DCA, no hedging, no trade without SL.
 No profit is guaranteed. Test on demo first.
*/

#include <Trade/Trade.mqh>
CTrade trade;

//--- inputs
input group "Risk"
input double InpRiskPercent    = 1.0;      // Risk per trade, % of balance (used when Fixed lot = 0)
input double InpFixedLot       = 0.0;      // Fixed lot (>0 overrides risk %)
input double InpMaxTotalLots   = 5.0;      // Max total open lots by this EA
input ulong  InpMagic          = 26112301; // Magic number
input int    InpDeviationPts   = 30;       // Max slippage (points)

input group "Range"
input int    InpRangeStartHour = 0;        // Range start hour (server time)
input int    InpRangeEndHour   = 7;        // Range end hour (server time, exclusive)
input double InpMinRange       = 3.0;      // Min range size ($)
input double InpMaxRange       = 25.0;     // Max range size ($)
input double InpBreakBuffer    = 0.50;     // Close must be this far beyond the range ($)

input group "Entries"
input int    InpTradeStartHour = 8;        // First hour for entries (server time)
input int    InpTradeEndHour   = 16;       // No new entries from this hour (server time)
input int    InpMaxTradesPerDay= 2;        // Max entries per day (1 buy + 1 sell max)
input bool   InpUseTrendFilter = true;     // Trade only with the EMA trend
input ENUM_TIMEFRAMES InpTrendTF = PERIOD_H1; // Trend filter timeframe
input int    InpTrendEMA       = 200;      // Trend filter EMA period
input double InpMaxSpread      = 0.50;     // Max spread for entries ($)

input group "Exits"
input double InpSLRangeFrac    = 0.5;      // SL distance = range size x this
input double InpMinSL          = 3.0;      // Min SL distance ($)
input double InpMaxSL          = 15.0;     // Max SL distance ($)
input double InpRR             = 2.0;      // TP = SL x this (0 = no TP)
input bool   InpUseBreakEven   = true;     // Move SL to breakeven
input double InpBE_R           = 1.0;      // Breakeven trigger (x R)
input double InpBE_Lock        = 0.30;     // Breakeven lock ($ beyond entry)
input bool   InpUseTrailing    = false;    // Trailing stop
input double InpTrailStart_R   = 1.5;      // Trailing start (x R)
input double InpTrailDist      = 4.0;      // Trailing distance ($)
input int    InpCloseHour      = 22;       // Close all EA trades at this server hour (-1 = off)

input group "Protection"
input double InpMaxDailyLossPct= 3.0;      // Max daily loss % -> no new trades today (0 = off)
input double InpEquityStopPct  = 6.0;      // Equity stop % -> close all + halt today (0 = off)
input int    InpFridayStopHour = 14;       // No new entries on Friday from this hour (-1 = off)
input bool   InpCloseAllNow    = false;    // Close all EA trades now and stop entries

//--- globals
#define OBJ_PREFIX "GBE_"
int      g_hEma          = INVALID_HANDLE;
datetime g_dayStart      = 0;
double   g_dayStartEq    = 0.0;
bool     g_dayHalted     = false;
bool     g_rangeReady    = false;
bool     g_rangeValid    = false;
double   g_rangeHigh     = 0.0;
double   g_rangeLow      = 0.0;
double   g_slDist        = 0.0;
string   g_status        = "";

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpRiskPercent <= 0.0 && InpFixedLot <= 0.0)
     { Print("Set InpRiskPercent > 0 or InpFixedLot > 0"); return INIT_PARAMETERS_INCORRECT; }
   if(InpRiskPercent > 10.0)
     { Print("InpRiskPercent above 10% is refused"); return INIT_PARAMETERS_INCORRECT; }
   if(InpRangeStartHour < 0 || InpRangeEndHour > 23 || InpRangeStartHour >= InpRangeEndHour)
     { Print("Range hours must satisfy 0 <= start < end <= 23"); return INIT_PARAMETERS_INCORRECT; }
   if(InpTradeStartHour < InpRangeEndHour || InpTradeEndHour > 24 || InpTradeStartHour >= InpTradeEndHour)
     { Print("Trade hours must start at/after range end and start < end"); return INIT_PARAMETERS_INCORRECT; }
   if(InpMinRange <= 0.0 || InpMaxRange <= InpMinRange)
     { Print("Need 0 < InpMinRange < InpMaxRange"); return INIT_PARAMETERS_INCORRECT; }
   if(InpSLRangeFrac <= 0.0 || InpMinSL <= 0.0 || InpMaxSL < InpMinSL)
     { Print("Invalid SL settings"); return INIT_PARAMETERS_INCORRECT; }
   if(InpRR < 0.0 || InpBE_R <= 0.0 || InpTrailStart_R <= 0.0 || InpTrailDist <= 0.0)
     { Print("Invalid exit settings"); return INIT_PARAMETERS_INCORRECT; }
   if(InpMaxTradesPerDay < 1 || InpMaxTotalLots <= 0.0 || InpMaxSpread <= 0.0)
     { Print("Invalid protection settings"); return INIT_PARAMETERS_INCORRECT; }
   if(InpCloseHour > 23 || InpFridayStopHour > 23)
     { Print("Hours must be <= 23"); return INIT_PARAMETERS_INCORRECT; }

   if(StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0)
      Print("Warning: EA is designed for XAUUSD/GOLD, attached to ", _Symbol);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPts);
   trade.SetTypeFillingBySymbol(_Symbol);

   if(InpUseTrendFilter)
     {
      g_hEma = iMA(_Symbol, InpTrendTF, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);
      if(g_hEma == INVALID_HANDLE)
        { Print("Failed to create EMA handle, error ", GetLastError()); return INIT_FAILED; }
     }

   ResetDay();
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_hEma != INVALID_HANDLE) { IndicatorRelease(g_hEma); g_hEma = INVALID_HANDLE; }
   ObjectsDeleteAll(0, OBJ_PREFIX);
   Comment("");
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   datetime now = TimeCurrent();
   if(now - now % 86400 != g_dayStart)
      ResetDay();

   MqlDateTime dt;
   TimeToStruct(now, dt);

   //--- close-all switch
   if(InpCloseAllNow)
     {
      CloseAll("close-all switch");
      ShowStatus("CLOSE-ALL switch ON - no trading");
      return;
     }

   //--- equity protection
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double ddPct = (g_dayStartEq > 0.0) ? (g_dayStartEq - eq) / g_dayStartEq * 100.0 : 0.0;
   if(InpEquityStopPct > 0.0 && ddPct >= InpEquityStopPct)
     {
      if(CountPositions() > 0) CloseAll(StringFormat("equity stop %.2f%%", ddPct));
      if(!g_dayHalted) Print("Equity stop hit (", DoubleToString(ddPct, 2), "%) - halted for today");
      g_dayHalted = true;
     }
   else if(InpMaxDailyLossPct > 0.0 && ddPct >= InpMaxDailyLossPct && !g_dayHalted)
     {
      Print("Max daily loss hit (", DoubleToString(ddPct, 2), "%) - no new trades today");
      g_dayHalted = true;
     }

   //--- end-of-day close
   if(InpCloseHour >= 0 && dt.hour >= InpCloseHour && CountPositions() > 0)
      CloseAll("end-of-day close");

   //--- range
   if(!g_rangeReady && dt.hour >= InpRangeEndHour)
      BuildRange();

   //--- manage open trades every tick
   ManagePositions();

   //--- entries only on a new bar
   if(IsNewBar())
      CheckEntry(dt);

   ShowStatus(g_status);
  }

//+------------------------------------------------------------------+
//| Day handling                                                      |
//+------------------------------------------------------------------+
void ResetDay()
  {
   datetime now = TimeCurrent();
   g_dayStart   = now - now % 86400;
   g_dayStartEq = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dayHalted  = false;
   g_rangeReady = false;
   g_rangeValid = false;
   g_rangeHigh  = 0.0;
   g_rangeLow   = 0.0;
   g_slDist     = 0.0;
   g_status     = "Waiting for Asian range";
  }

//+------------------------------------------------------------------+
void BuildRange()
  {
   datetime rs = g_dayStart + InpRangeStartHour * 3600;
   datetime re = g_dayStart + InpRangeEndHour * 3600 - 1;

   double highs[], lows[];
   int nh = CopyHigh(_Symbol, PERIOD_M5, rs, re, highs);
   int nl = CopyLow(_Symbol, PERIOD_M5, rs, re, lows);
   if(nh <= 0 || nl <= 0)
      return;                       // data not loaded yet, retry next tick

   g_rangeReady = true;
   int minBars = (InpRangeEndHour - InpRangeStartHour) * 12 / 2;   // at least half the M5 bars
   if(nh < minBars)
     {
      g_status = StringFormat("Range skipped: only %d M5 bars (holiday / late open)", nh);
      Print(g_status);
      return;
     }

   g_rangeHigh = highs[ArrayMaximum(highs)];
   g_rangeLow  = lows[ArrayMinimum(lows)];
   double size = g_rangeHigh - g_rangeLow;

   if(size < InpMinRange || size > InpMaxRange)
     {
      g_status = StringFormat("Range %.2f outside [%.2f, %.2f] - no trades today", size, InpMinRange, InpMaxRange);
      Print(g_status);
      return;
     }

   g_slDist     = MathMax(InpMinSL, MathMin(InpMaxSL, size * InpSLRangeFrac));
   g_rangeValid = true;
   g_status     = StringFormat("Range %.2f - %.2f (size %.2f, SL %.2f)", g_rangeLow, g_rangeHigh, size, g_slDist);
   Print(g_status);
   DrawRange(rs, re);
  }

//+------------------------------------------------------------------+
void DrawRange(datetime t1, datetime t2)
  {
   string name = OBJ_PREFIX + TimeToString(g_dayStart, TIME_DATE);
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   if(ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, g_rangeHigh, t2, g_rangeLow))
     {
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrGoldenrod);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
     }
  }

//+------------------------------------------------------------------+
//| Entry logic                                                       |
//+------------------------------------------------------------------+
bool IsNewBar()
  {
   static datetime last = 0;
   datetime t = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(t == 0 || t == last) return false;
   last = t;
   return true;
  }

//+------------------------------------------------------------------+
void CheckEntry(const MqlDateTime &dt)
  {
   if(!g_rangeValid || g_dayHalted) return;
   if(dt.hour < InpTradeStartHour || dt.hour >= InpTradeEndHour) return;
   if(InpCloseHour >= 0 && dt.hour >= InpCloseHour) return;
   if(InpFridayStopHour >= 0 && dt.day_of_week == 5 && dt.hour >= InpFridayStopHour) return;

   int buys = 0, sells = 0;
   TodayEntries(buys, sells);
   if(buys + sells >= InpMaxTradesPerDay) return;

   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   datetime t1   = iTime(_Symbol, PERIOD_CURRENT, 1);
   if(close1 <= 0.0 || t1 < g_dayStart + InpRangeEndHour * 3600) return;

   bool buySig  = (buys == 0)  && close1 > g_rangeHigh + InpBreakBuffer;
   bool sellSig = (sells == 0) && close1 < g_rangeLow  - InpBreakBuffer;
   if(!buySig && !sellSig) return;

   if(InpUseTrendFilter)
     {
      double ema[];
      ArraySetAsSeries(ema, true);
      if(CopyBuffer(g_hEma, 0, 1, 1, ema) != 1) { Print("EMA data not ready"); return; }
      double trendClose = iClose(_Symbol, InpTrendTF, 1);
      if(trendClose <= 0.0) return;
      if(buySig  && trendClose <= ema[0]) { buySig  = false; Print("Buy breakout skipped: below trend EMA"); }
      if(sellSig && trendClose >= ema[0]) { sellSig = false; Print("Sell breakout skipped: above trend EMA"); }
     }

   if(buySig)       OpenTrade(ORDER_TYPE_BUY);
   else if(sellSig) OpenTrade(ORDER_TYPE_SELL);
  }

//+------------------------------------------------------------------+
void OpenTrade(const ENUM_ORDER_TYPE type)
  {
   MqlTick tk;
   if(!SymbolInfoTick(_Symbol, tk)) return;

   double spread = tk.ask - tk.bid;
   if(spread > InpMaxSpread)
     { Print("Entry skipped: spread ", DoubleToString(spread, _Digits), " > ", DoubleToString(InpMaxSpread, 2)); return; }

   bool   isBuy   = (type == ORDER_TYPE_BUY);
   double price   = isBuy ? tk.ask : tk.bid;
   double minDist = StopsLevelDist() + spread + _Point;
   double slDist  = MathMax(g_slDist, minDist);
   double tpDist  = (InpRR > 0.0) ? MathMax(slDist * InpRR, minDist) : 0.0;

   double sl = NormPrice(isBuy ? price - slDist : price + slDist);
   double tp = (tpDist > 0.0) ? NormPrice(isBuy ? price + tpDist : price - tpDist) : 0.0;

   double lots = CalcLots(slDist);
   if(lots <= 0.0) return;

   double room = InpMaxTotalLots - OpenLots();
   if(room < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
     { Print("Entry skipped: max total lots reached"); return; }
   lots = NormalizeVolDown(MathMin(lots, room));
   if(lots <= 0.0) return;

   double margin = 0.0;
   if(!OrderCalcMargin(type, _Symbol, lots, price, margin))
     { Print("OrderCalcMargin failed, error ", GetLastError()); return; }
   if(margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
     { Print("Entry skipped: not enough free margin (need ", DoubleToString(margin, 2), ")"); return; }

   double volMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double volMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double remaining = lots;
   string cmt = isBuy ? "GBE breakout buy" : "GBE breakout sell";

   for(int guard = 0; guard < 50 && remaining >= volMin - 1e-9; guard++)
     {
      double v = NormalizeVolDown(MathMin(remaining, volMax));
      if(v < volMin) break;
      bool ok = isBuy ? trade.Buy(v, _Symbol, 0.0, sl, tp, cmt)
                      : trade.Sell(v, _Symbol, 0.0, sl, tp, cmt);
      uint rc = trade.ResultRetcode();
      if(!ok || (rc != TRADE_RETCODE_DONE && rc != TRADE_RETCODE_PLACED && rc != TRADE_RETCODE_DONE_PARTIAL))
        {
         Print(isBuy ? "Buy" : "Sell", " failed: ", rc, " ", trade.ResultRetcodeDescription());
         break;
        }
      remaining -= v;
     }

   g_status = StringFormat("%s %.2f lots, SL %.2f, TP %.2f", isBuy ? "BUY" : "SELL", lots, sl, tp);
   Print(g_status);
  }

//+------------------------------------------------------------------+
//| Trade management                                                  |
//+------------------------------------------------------------------+
void ManagePositions()
  {
   if(!InpUseBreakEven && !InpUseTrailing) return;
   if(g_slDist <= 0.0) return;          // R unknown until today's range is built

   MqlTick tk;
   if(!SymbolInfoTick(_Symbol, tk)) return;

   double R       = g_slDist;
   double tick    = TickSize();
   double stopMin = StopsLevelDist();
   double freeze  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      double open  = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);
      long   ptype = PositionGetInteger(POSITION_TYPE);
      double newSL = curSL;

      if(ptype == POSITION_TYPE_BUY)
        {
         double profit = tk.bid - open;
         if(InpUseBreakEven && profit >= InpBE_R * R)
           {
            double be = open + InpBE_Lock;
            if(newSL < be) newSL = be;
           }
         if(InpUseTrailing && profit >= InpTrailStart_R * R)
           {
            double tr = tk.bid - InpTrailDist;
            if(tr > newSL) newSL = tr;
           }
         newSL = NormPrice(newSL);
         if(newSL <= 0.0 || newSL <= curSL + tick / 2.0) continue;
         if(tk.bid - newSL < stopMin) continue;
         if(curSL > 0.0 && tk.bid - curSL <= freeze) continue;
        }
      else
        {
         double profit = open - tk.ask;
         if(InpUseBreakEven && profit >= InpBE_R * R)
           {
            double be = open - InpBE_Lock;
            if(newSL == 0.0 || newSL > be) newSL = be;
           }
         if(InpUseTrailing && profit >= InpTrailStart_R * R)
           {
            double tr = tk.ask + InpTrailDist;
            if(newSL == 0.0 || tr < newSL) newSL = tr;
           }
         newSL = NormPrice(newSL);
         if(newSL <= 0.0) continue;
         if(curSL > 0.0 && newSL >= curSL - tick / 2.0) continue;
         if(newSL - tk.ask < stopMin) continue;
         if(curSL > 0.0 && curSL - tk.ask <= freeze) continue;
        }

      if(!trade.PositionModify(ticket, newSL, curTP))
         Print("SL modify failed #", ticket, ": ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
     }
  }

//+------------------------------------------------------------------+
void CloseAll(const string why)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(trade.PositionClose(ticket))
         Print("Closed #", ticket, " (", why, ")");
      else
         Print("Close failed #", ticket, ": ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
     }
  }

//+------------------------------------------------------------------+
//| Helpers                                                           |
//+------------------------------------------------------------------+
int CountPositions()
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      n++;
     }
   return n;
  }

//+------------------------------------------------------------------+
double OpenLots()
  {
   double lots = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      lots += PositionGetDouble(POSITION_VOLUME);
     }
   return lots;
  }

//+------------------------------------------------------------------+
//| Entries made today, from deal history (survives EA restarts).    |
//| Split orders of one signal share a timestamp and count once.     |
//+------------------------------------------------------------------+
void TodayEntries(int &buys, int &sells)
  {
   buys = 0; sells = 0;
   if(!HistorySelect(g_dayStart, TimeCurrent() + 60)) return;
   datetime lastBuy = 0, lastSell = 0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0) continue;
      if(HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol) continue;
      if((ulong)HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagic) continue;
      if(HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
      datetime t = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
      long dtype = HistoryDealGetInteger(d, DEAL_TYPE);
      if(dtype == DEAL_TYPE_BUY && t != lastBuy)        { buys++;  lastBuy  = t; }
      else if(dtype == DEAL_TYPE_SELL && t != lastSell) { sells++; lastSell = t; }
     }
  }

//+------------------------------------------------------------------+
double CalcLots(const double slDist)
  {
   double volMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   if(InpFixedLot > 0.0)
     {
      double v = NormalizeVolDown(InpFixedLot);
      return (v < volMin) ? volMin : v;
     }

   double tickSize  = TickSize();
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickValue <= 0.0) tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickValue <= 0.0 || slDist <= 0.0)
     { Print("Cannot size lot: tick size/value unavailable"); return 0.0; }

   double riskMoney  = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double lossPerLot = slDist / tickSize * tickValue;
   double lots       = NormalizeVolDown(riskMoney / lossPerLot);

   if(lots < volMin)
     {
      Print("Entry skipped: risk lot ", DoubleToString(riskMoney / lossPerLot, 4),
            " < broker min ", DoubleToString(volMin, 2), " (raise risk % or balance)");
      return 0.0;
     }
   return lots;
  }

//+------------------------------------------------------------------+
double NormalizeVolDown(const double v)
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = 0.01;
   double r = MathFloor(v / step + 1e-9) * step;
   int digits = (int)MathMax(0.0, MathCeil(-MathLog10(step)));
   return NormalizeDouble(r, digits);
  }

//+------------------------------------------------------------------+
double TickSize()
  {
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   return (ts > 0.0) ? ts : _Point;
  }

//+------------------------------------------------------------------+
double NormPrice(const double p)
  {
   if(p <= 0.0) return 0.0;
   double ts = TickSize();
   return NormalizeDouble(MathRound(p / ts) * ts, _Digits);
  }

//+------------------------------------------------------------------+
double StopsLevelDist()
  {
   long stops  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   return MathMax((double)stops, (double)freeze) * _Point;
  }

//+------------------------------------------------------------------+
void ShowStatus(const string msg)
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION)) return;
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd = (g_dayStartEq > 0.0) ? (g_dayStartEq - eq) / g_dayStartEq * 100.0 : 0.0;
   Comment(StringFormat("GoldBreakoutEA v1.00\n%s\nPositions: %d  Lots: %.2f\nDay P/L: %.2f%%%s",
                        msg, CountPositions(), OpenLots(), -dd,
                        g_dayHalted ? "\nHALTED for today" : ""));
  }
//+------------------------------------------------------------------+
