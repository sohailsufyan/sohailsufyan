//+------------------------------------------------------------------+
//|                                                 GoldSwingEA.mq5  |
//|   XAUUSD Swing Trading EA - Trend + Pullback (H4 / D1 filter)    |
//|                                                                  |
//|  NOTE: Koi bhi EA fixed monthly return ki guarantee nahi deta.   |
//|  Leverage sirf margin kam karti hai - RISK lot size se aata hai. |
//|  Hamesha pehle Strategy Tester + Demo par test karein.           |
//+------------------------------------------------------------------+
#property copyright "GoldSwingEA"
#property version   "1.00"

#include <Trade/Trade.mqh>

//--- Enums
enum ENUM_RISK_MODE
  {
   RISK_PERCENT = 0,   // Risk % of equity per trade
   RISK_FIXED_LOT = 1  // Fixed lot size
  };

//==================== INPUTS ====================
input group "=== General ==="
input long            InpMagic            = 777001;        // Magic number
input string          InpComment          = "GoldSwing";   // Order comment
input ENUM_TIMEFRAMES InpSignalTF         = PERIOD_H4;     // Signal timeframe
input ENUM_TIMEFRAMES InpTrendTF          = PERIOD_D1;     // Higher timeframe trend filter

input group "=== Risk Management ==="
input ENUM_RISK_MODE  InpRiskMode         = RISK_PERCENT;  // Risk mode
input double          InpRiskPercent      = 2.0;           // Risk per trade (% of equity)
input double          InpFixedLot         = 0.01;          // Fixed lot (if fixed mode)
input double          InpMaxLot           = 5.0;           // Maximum lot cap
input int             InpMaxPositions     = 1;             // Max open positions (this EA)
input double          InpMaxDailyLossPct  = 5.0;           // Max daily loss % (stop trading for the day)
input double          InpMaxDrawdownPct   = 25.0;          // Max drawdown from peak % (EA stops completely)
input double          InpMonthlyTargetPct = 50.0;          // Monthly target % (0 = off) - lock profits when hit
input double          InpMaxMarginUsePct  = 30.0;          // Max margin usage % of free margin per trade

input group "=== Strategy: Trend ==="
input int             InpTrendEMA         = 50;            // HTF trend EMA (D1)
input int             InpFastEMA          = 21;            // Signal TF fast EMA
input int             InpSlowEMA          = 50;            // Signal TF slow EMA
input int             InpBaseEMA          = 200;           // Signal TF base EMA

input group "=== Strategy: Entry ==="
input int             InpRSIPeriod        = 14;            // RSI period
input double          InpRSIBuyMin        = 50.0;          // RSI min for BUY
input double          InpRSIBuyMax        = 70.0;          // RSI max for BUY (avoid overbought)
input double          InpRSISellMax       = 50.0;          // RSI max for SELL
input double          InpRSISellMin       = 30.0;          // RSI min for SELL (avoid oversold)
input int             InpPullbackBars     = 5;             // Bars to look back for pullback to EMA

input group "=== SL / TP (ATR based) ==="
input int             InpATRPeriod        = 14;            // ATR period
input double          InpSL_ATR           = 1.5;           // Stop Loss = ATR x
input double          InpTP_ATR           = 3.5;           // Take Profit = ATR x
input double          InpBE_ATR           = 1.0;           // Move to breakeven after ATR x profit (0=off)
input double          InpBE_LockPoints    = 50;            // Breakeven lock (points above entry)
input double          InpTrail_ATR        = 1.5;           // Trailing distance ATR x (0=off)
input double          InpTrailStart_ATR   = 1.5;           // Start trailing after ATR x profit
input double          InpPartialClosePct  = 50.0;          // Partial close % at 1R (0=off)

input group "=== Filters ==="
input int             InpMaxSpreadPoints  = 60;            // Max spread (points)
input bool            InpUseSession       = true;          // Trade only in session hours
input int             InpSessionStartHour = 7;             // Session start (server hour)
input int             InpSessionEndHour   = 20;            // Session end (server hour)
input bool            InpNoFridayLate     = true;          // No new trades Friday after 18:00
input bool            InpAllowBuy         = true;          // Allow BUY
input bool            InpAllowSell        = true;          // Allow SELL

//==================== GLOBALS ====================
CTrade   trade;
int      hFastEMA = INVALID_HANDLE, hSlowEMA = INVALID_HANDLE, hBaseEMA = INVALID_HANDLE;
int      hTrendEMA = INVALID_HANDLE, hRSI = INVALID_HANDLE, hATR = INVALID_HANDLE;
datetime lastBarTime = 0;
bool     eaHalted = false;

string   gvPeak, gvDayEq, gvDay, gvMonEq, gvMon, gvPartial;

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFillingBySymbol(_Symbol);

   hFastEMA  = iMA(_Symbol, InpSignalTF, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hSlowEMA  = iMA(_Symbol, InpSignalTF, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hBaseEMA  = iMA(_Symbol, InpSignalTF, InpBaseEMA, 0, MODE_EMA, PRICE_CLOSE);
   hTrendEMA = iMA(_Symbol, InpTrendTF,  InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   hRSI      = iRSI(_Symbol, InpSignalTF, InpRSIPeriod, PRICE_CLOSE);
   hATR      = iATR(_Symbol, InpSignalTF, InpATRPeriod);

   if(hFastEMA == INVALID_HANDLE || hSlowEMA == INVALID_HANDLE || hBaseEMA == INVALID_HANDLE ||
      hTrendEMA == INVALID_HANDLE || hRSI == INVALID_HANDLE || hATR == INVALID_HANDLE)
     {
      Print("Indicator handle create nahi hua. Error: ", GetLastError());
      return(INIT_FAILED);
     }

   string pre = "GSEA_" + _Symbol + "_" + IntegerToString(InpMagic) + "_";
   gvPeak    = pre + "Peak";
   gvDayEq   = pre + "DayEq";
   gvDay     = pre + "Day";
   gvMonEq   = pre + "MonEq";
   gvMon     = pre + "Mon";
   gvPartial = pre + "PC_";

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(!GlobalVariableCheck(gvPeak) || MQLInfoInteger(MQL_TESTER))
      GlobalVariableSet(gvPeak, eq);
   UpdateEquityTrackers();

   long lev = AccountInfoInteger(ACCOUNT_LEVERAGE);
   PrintFormat("GoldSwingEA started on %s | Leverage 1:%d | Risk/trade %.2f%%",
               _Symbol, lev, InpRiskPercent);
   if(InpRiskPercent > 5.0)
      Print("WARNING: Risk per trade 5% se zyada hai - account blow hone ka risk bahut high hai!");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(hFastEMA);
   IndicatorRelease(hSlowEMA);
   IndicatorRelease(hBaseEMA);
   IndicatorRelease(hTrendEMA);
   IndicatorRelease(hRSI);
   IndicatorRelease(hATR);
   Comment("");
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   UpdateEquityTrackers();
   ManagePositions();
   ShowPanel();

   if(eaHalted)
      return;

   // Only evaluate signals once per new signal-TF bar
   datetime barTime = iTime(_Symbol, InpSignalTF, 0);
   if(barTime == 0 || barTime == lastBarTime)
      return;
   lastBarTime = barTime;

   if(!RiskGuardsOK())
      return;
   if(!FiltersOK())
      return;
   if(CountMyPositions() >= InpMaxPositions)
      return;

   int signal = GetSignal();
   if(signal == 1 && InpAllowBuy)
      OpenTrade(ORDER_TYPE_BUY);
   else
      if(signal == -1 && InpAllowSell)
         OpenTrade(ORDER_TYPE_SELL);
  }

//==================== SIGNAL ====================
bool GetBuf(int handle, int buffer, int start, int count, double &arr[])
  {
   ArraySetAsSeries(arr, true);
   return(CopyBuffer(handle, buffer, start, count, arr) == count);
  }

// returns 1 = BUY, -1 = SELL, 0 = none
int GetSignal()
  {
   int need = InpPullbackBars + 3;
   double fast[], slow[], base[], trend[], rsi[], atr[];
   if(!GetBuf(hFastEMA, 0, 0, need, fast))  return 0;
   if(!GetBuf(hSlowEMA, 0, 0, need, slow))  return 0;
   if(!GetBuf(hBaseEMA, 0, 0, need, base))  return 0;
   if(!GetBuf(hTrendEMA, 0, 0, 3, trend))   return 0;
   if(!GetBuf(hRSI, 0, 0, 3, rsi))          return 0;
   if(!GetBuf(hATR, 0, 0, 3, atr))          return 0;

   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(_Symbol, InpSignalTF, 0, need, r) != need) return 0;

   double htfClose = iClose(_Symbol, InpTrendTF, 1);
   if(htfClose == 0) return 0;

   // Bar 1 = last closed bar
   double c1 = r[1].close, o1 = r[1].open;
   double c2 = r[2].close;

   //--- BUY: uptrend on both TFs, pullback to fast EMA, bullish re-entry candle
   bool upTrend = (htfClose > trend[1]) && (fast[1] > slow[1]) && (slow[1] > base[1]);
   if(upTrend)
     {
      bool touched = false;
      for(int i = 1; i <= InpPullbackBars; i++)
         if(r[i].low <= fast[i] + 0.2 * atr[1]) { touched = true; break; }

      bool reclaim = (c1 > fast[1]) && (c1 > o1) && (c1 > c2);
      bool notTooFar = (c1 - fast[1]) < 1.0 * atr[1];
      bool rsiOK = (rsi[1] >= InpRSIBuyMin && rsi[1] <= InpRSIBuyMax);
      if(touched && reclaim && notTooFar && rsiOK)
         return 1;
     }

   //--- SELL: downtrend on both TFs, pullback to fast EMA, bearish re-entry candle
   bool downTrend = (htfClose < trend[1]) && (fast[1] < slow[1]) && (slow[1] < base[1]);
   if(downTrend)
     {
      bool touched = false;
      for(int i = 1; i <= InpPullbackBars; i++)
         if(r[i].high >= fast[i] - 0.2 * atr[1]) { touched = true; break; }

      bool reclaim = (c1 < fast[1]) && (c1 < o1) && (c1 < c2);
      bool notTooFar = (fast[1] - c1) < 1.0 * atr[1];
      bool rsiOK = (rsi[1] <= InpRSISellMax && rsi[1] >= InpRSISellMin);
      if(touched && reclaim && notTooFar && rsiOK)
         return -1;
     }
   return 0;
  }

//==================== TRADE EXECUTION ====================
void OpenTrade(ENUM_ORDER_TYPE type)
  {
   double atr[];
   if(!GetBuf(hATR, 0, 1, 1, atr)) return;
   double a = atr[0];

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double minStop = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

   double slDist = MathMax(InpSL_ATR * a, minStop + 10 * _Point);
   double tpDist = MathMax(InpTP_ATR * a, minStop + 10 * _Point);

   double price, sl, tp;
   if(type == ORDER_TYPE_BUY)
     {
      price = ask;
      sl = NormalizeDouble(price - slDist, digits);
      tp = NormalizeDouble(price + tpDist, digits);
     }
   else
     {
      price = bid;
      sl = NormalizeDouble(price + slDist, digits);
      tp = NormalizeDouble(price - tpDist, digits);
     }

   double lots = CalcLots(type, price, sl);
   if(lots <= 0)
     {
      Print("Lot size 0 aaya - trade skip.");
      return;
     }

   bool ok = (type == ORDER_TYPE_BUY) ? trade.Buy(lots, _Symbol, price, sl, tp, InpComment)
                                      : trade.Sell(lots, _Symbol, price, sl, tp, InpComment);
   if(ok)
      PrintFormat("%s opened: lots=%.2f price=%.2f SL=%.2f TP=%.2f",
                  (type == ORDER_TYPE_BUY ? "BUY" : "SELL"), lots, price, sl, tp);
   else
      PrintFormat("Order fail: %d - %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
  }

double NormalizeLots(double lots)
  {
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;
   lots = MathFloor(lots / step) * step;
   lots = MathMin(lots, MathMin(maxLot, InpMaxLot));
   if(lots < minLot) return 0.0;
   return NormalizeDouble(lots, 2);
  }

double CalcLots(ENUM_ORDER_TYPE type, double price, double sl)
  {
   double lots;
   if(InpRiskMode == RISK_FIXED_LOT)
      lots = InpFixedLot;
   else
     {
      double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
      double riskMoney = equity * InpRiskPercent / 100.0;
      double lossPerLot = 0;
      if(!OrderCalcProfit(type, _Symbol, 1.0, price, sl, lossPerLot) || lossPerLot == 0)
         return 0;
      lots = riskMoney / MathAbs(lossPerLot);
     }

   lots = NormalizeLots(lots);
   if(lots <= 0) return 0;

   // Margin safety - 500x leverage par bhi over-exposure se bachao
   double marginPerLot = 0;
   if(OrderCalcMargin(type, _Symbol, 1.0, price, marginPerLot) && marginPerLot > 0)
     {
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      double maxByMargin = (freeMargin * InpMaxMarginUsePct / 100.0) / marginPerLot;
      if(lots > maxByMargin)
         lots = NormalizeLots(maxByMargin);
     }
   return lots;
  }

//==================== POSITION MANAGEMENT ====================
int CountMyPositions()
  {
   int cnt = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic)
         cnt++;
     }
   return cnt;
  }

void ManagePositions()
  {
   double atr[];
   if(!GetBuf(hATR, 0, 1, 1, atr)) return;
   double a = atr[0];
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double minStop = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;

      long   type  = PositionGetInteger(POSITION_TYPE);
      double open  = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);
      double vol   = PositionGetDouble(POSITION_VOLUME);
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      bool   isBuy  = (type == POSITION_TYPE_BUY);
      double cur    = isBuy ? bid : ask;
      double profitDist = isBuy ? (cur - open) : (open - cur);
      double oneR   = InpSL_ATR * a;

      //--- Partial close at 1R (once per ticket)
      string pcKey = gvPartial + IntegerToString((long)ticket);
      if(InpPartialClosePct > 0 && profitDist >= oneR && !GlobalVariableCheck(pcKey))
        {
         double closeVol = NormalizeLots(vol * InpPartialClosePct / 100.0);
         double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         if(closeVol > 0 && (vol - closeVol) >= minLot)
           {
            if(trade.PositionClosePartial(ticket, closeVol))
               GlobalVariableSet(pcKey, 1);
           }
         else
            GlobalVariableSet(pcKey, 1); // too small to split
        }

      double newSL = sl;

      //--- Breakeven
      if(InpBE_ATR > 0 && profitDist >= InpBE_ATR * a)
        {
         double be = isBuy ? open + InpBE_LockPoints * _Point : open - InpBE_LockPoints * _Point;
         if(isBuy && (newSL < be || newSL == 0)) newSL = be;
         if(!isBuy && (newSL > be || newSL == 0)) newSL = be;
        }

      //--- ATR trailing
      if(InpTrail_ATR > 0 && profitDist >= InpTrailStart_ATR * a)
        {
         double tr = isBuy ? cur - InpTrail_ATR * a : cur + InpTrail_ATR * a;
         if(isBuy && tr > newSL) newSL = tr;
         if(!isBuy && (tr < newSL || newSL == 0)) newSL = tr;
        }

      newSL = NormalizeDouble(newSL, digits);
      if(newSL != sl)
        {
         // respect broker stop level
         bool valid = isBuy ? (bid - newSL > minStop) : (newSL - ask > minStop);
         bool improves = isBuy ? (newSL > sl + _Point) : (sl == 0 || newSL < sl - _Point);
         if(valid && improves)
            trade.PositionModify(ticket, newSL, tp);
        }
     }
  }

//==================== RISK GUARDS ====================
void UpdateEquityTrackers()
  {
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int dayKey = dt.year * 1000 + dt.day_of_year;
   int monKey = dt.year * 100 + dt.mon;

   if(!GlobalVariableCheck(gvDay) || (int)GlobalVariableGet(gvDay) != dayKey)
     {
      GlobalVariableSet(gvDay, dayKey);
      GlobalVariableSet(gvDayEq, eq);
     }
   if(!GlobalVariableCheck(gvMon) || (int)GlobalVariableGet(gvMon) != monKey)
     {
      GlobalVariableSet(gvMon, monKey);
      GlobalVariableSet(gvMonEq, eq);
     }
   if(eq > GlobalVariableGet(gvPeak))
      GlobalVariableSet(gvPeak, eq);

   // Hard stop on max drawdown
   double peak = GlobalVariableGet(gvPeak);
   if(peak > 0 && InpMaxDrawdownPct > 0 && (peak - eq) / peak * 100.0 >= InpMaxDrawdownPct)
     {
      if(!eaHalted)
        {
         PrintFormat("MAX DRAWDOWN %.1f%% hit. Sab positions close aur EA halt.", InpMaxDrawdownPct);
         CloseAll();
        }
      eaHalted = true;
     }
  }

bool RiskGuardsOK()
  {
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double dayEq = GlobalVariableGet(gvDayEq);
   double monEq = GlobalVariableGet(gvMonEq);

   if(dayEq > 0 && InpMaxDailyLossPct > 0 && (dayEq - eq) / dayEq * 100.0 >= InpMaxDailyLossPct)
      return false;

   if(monEq > 0 && InpMonthlyTargetPct > 0 && (eq - monEq) / monEq * 100.0 >= InpMonthlyTargetPct)
      return false; // Target hit - is mahine aur naye trade nahi

   return true;
  }

bool FiltersOK()
  {
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpreadPoints)
      return false;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(InpUseSession && (dt.hour < InpSessionStartHour || dt.hour >= InpSessionEndHour))
      return false;
   if(InpNoFridayLate && dt.day_of_week == 5 && dt.hour >= 18)
      return false;
   return true;
  }

void CloseAll()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic)
         trade.PositionClose(t);
     }
  }

//==================== PANEL ====================
void ShowPanel()
  {
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE))
      return;
   double eq    = AccountInfoDouble(ACCOUNT_EQUITY);
   double dayEq = GlobalVariableGet(gvDayEq);
   double monEq = GlobalVariableGet(gvMonEq);
   double peak  = GlobalVariableGet(gvPeak);
   double dayPL = dayEq > 0 ? (eq - dayEq) / dayEq * 100.0 : 0;
   double monPL = monEq > 0 ? (eq - monEq) / monEq * 100.0 : 0;
   double dd    = peak > 0 ? (peak - eq) / peak * 100.0 : 0;

   Comment(StringFormat(
              "GoldSwingEA v1.00  |  %s\n"
              "Status     : %s\n"
              "Equity     : %.2f\n"
              "Today P/L  : %.2f%%  (limit -%.1f%%)\n"
              "Month P/L  : %.2f%%  (target %.1f%%)\n"
              "Drawdown   : %.2f%%  (max %.1f%%)\n"
              "Positions  : %d / %d\n"
              "Spread     : %d pts",
              _Symbol, (eaHalted ? "HALTED (max DD)" : "Running"), eq,
              dayPL, InpMaxDailyLossPct, monPL, InpMonthlyTargetPct,
              dd, InpMaxDrawdownPct, CountMyPositions(), InpMaxPositions,
              (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)));
  }
//+------------------------------------------------------------------+
