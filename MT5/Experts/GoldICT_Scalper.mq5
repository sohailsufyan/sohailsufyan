//+------------------------------------------------------------------+
//|                                              GoldICT_Scalper.mq5 |
//|   XAUUSD ICT Silver Bullet Scalper - Liquidity Sweep + FVG       |
//|                                                                  |
//|  Setup (har closed bar par, sirf Kill Zone ke andar):            |
//|   1. Bias   : price H4 EMA200 ke upar = sirf BUY, neeche = SELL  |
//|   2. Sweep  : pichhle range ka low (BUY) / high (SELL) toda gaya |
//|               aur price wapas range ke andar close hua           |
//|   3. Displacement candle + 3-candle Fair Value Gap bana          |
//|   4. Price wapas FVG mein aaye -> market entry                   |
//|   SL : sweep ke extreme (ya Order Block) ke peeche               |
//|   TP : InpTP_RR x risk  |  Lot: equity ka InpRiskPercent risk    |
//|                                                                  |
//|  Idea BAKOME "Ultimate ICT Gold Scalper" (MIT) se liya - code     |
//|  poora naya hai. Original mein ICT levels trade decision mein    |
//|  use hi nahi hote the aur lot size 100x se zyada galat tha.      |
//|                                                                  |
//|  NOTE: Koi bhi EA profit ki guarantee nahi deta. Pehle Strategy  |
//|  Tester (Every tick based on real ticks) + Demo par test karein. |
//+------------------------------------------------------------------+
#property copyright "GoldICT_Scalper"
#property version   "1.00"
#property description "ICT Silver Bullet scalper for XAUUSD: liquidity sweep + displacement FVG entry, risk-based lots."

#include <Trade/Trade.mqh>

//==================== ENUMS ====================
enum ENUM_GICT_SL_MODE
  {
   GICT_SL_SWEEP      = 0,  // SL beyond the sweep extreme (wider, safer)
   GICT_SL_ORDERBLOCK = 1   // SL beyond the order block candle (tighter)
  };

enum ENUM_GICT_LOG
  {
   GICT_LOG_NONE  = 0,      // No logs
   GICT_LOG_ERROR = 1,      // Errors only
   GICT_LOG_INFO  = 2,      // Setups, trades, skips
   GICT_LOG_DEBUG = 3       // Everything (why a bar had no setup)
  };

//==================== INPUTS ====================
input group "=== General ==="
input long            InpMagic              = 777301;     // Magic number
input string          InpComment            = "GoldICT";  // Order comment
input ENUM_TIMEFRAMES InpExecTF             = PERIOD_M5;  // Setup timeframe (M5 = Silver Bullet)

input group "=== Risk Management ==="
input double InpRiskPercent         = 1.0;    // Risk per trade (% of equity)
input double InpMaxDailyLossPct     = 5.0;    // No new trades after this daily loss % (0 = off)
input double InpMaxDailyProfitPct   = 8.0;    // No new trades after this daily profit % (0 = off)
input int    InpMaxPositions        = 2;      // Max open positions of this EA
input int    InpMaxDailyTrades      = 6;      // Max trades per day
input int    InpMaxTradesPerWindow  = 1;      // Max trades per kill zone window
input double InpMaxLot              = 5.0;    // Hard lot cap

input group "=== Gold filters (in $, works on 2 and 3 digit quotes) ==="
input double InpMaxSpreadUSD        = 0.50;   // Max spread in $ (0.50 = 50 cents)
input double InpMinATR_USD          = 1.00;   // Min ATR(14) of setup TF in $ (dead market filter)

input group "=== ICT setup ==="
input bool   InpUseLiquiditySweep   = true;   // Require a liquidity sweep before the FVG
input int    InpSweepBars           = 10;     // Bars (before the FVG) that may hold the sweep
input int    InpLiquidityLookback   = 40;     // Older bars whose high/low is the liquidity
input double InpFVG_MinSizeATR      = 0.30;   // Min FVG size (x ATR)
input double InpDisplacementATR     = 0.80;   // Min displacement candle body (x ATR), 0 = off
input int    InpSetupExpiryBars     = 6;      // Cancel an untouched setup after N bars
input ENUM_GICT_SL_MODE InpSLMode   = GICT_SL_SWEEP; // Stop loss anchor
input double InpSL_BufferATR        = 0.10;   // Extra SL buffer (x ATR)
input double InpMinSL_ATR           = 0.30;   // Skip if the stop is closer than this (x ATR)
input double InpMaxSL_ATR           = 4.00;   // Skip if the stop is wider than this (x ATR)
input double InpTP_RR               = 2.0;    // Take profit = this x risk

input group "=== Bias (trend filter) ==="
input bool   InpUseH4Bias           = true;   // Price vs H4 EMA decides the direction
input int    InpH4EmaPeriod         = 200;    // H4 EMA period
input bool   InpUseH1Filter         = false;  // Also require price on the same side of the H1 EMA
input int    InpH1EmaPeriod         = 34;     // H1 EMA period

input group "=== Kill zones (BROKER server hours; NY time + 7 on most GMT+2/+3 brokers) ==="
input bool   InpUseKillZones        = true;   // Trade only inside the windows below
input bool   InpKZ1_On              = true;   // Window 1: London Silver Bullet (03-04 New York)
input int    InpKZ1_Start           = 10;     // Window 1 start hour (broker)
input int    InpKZ1_End             = 11;     // Window 1 end hour (broker)
input bool   InpKZ2_On              = true;   // Window 2: NY AM Silver Bullet (10-11 New York)
input int    InpKZ2_Start           = 17;     // Window 2 start hour (broker)
input int    InpKZ2_End             = 18;     // Window 2 end hour (broker)
input bool   InpKZ3_On              = false;  // Window 3: NY PM Silver Bullet (14-15 New York)
input int    InpKZ3_Start           = 21;     // Window 3 start hour (broker)
input int    InpKZ3_End             = 22;     // Window 3 end hour (broker)
input bool   InpAllowEntryAfterKZ   = false;  // Allow filling an armed setup after its window ends
input bool   InpNoFridayLate        = true;   // No new setups on Friday from 20:00 broker

input group "=== Position management (R = initial risk) ==="
input bool   InpUseBreakEven        = true;   // Move SL to entry
input double InpBE_TriggerR         = 1.0;    // ...when profit reaches this many R
input double InpBE_LockR            = 0.05;   // ...plus this many R locked (covers costs)
input bool   InpUsePartialClose     = true;   // Close part of the position
input double InpPartialR            = 1.0;    // ...at this many R
input double InpPartialPercent      = 50.0;   // ...this % of the volume
input bool   InpUseTrailing         = true;   // ATR trailing stop
input double InpTrailStartR         = 1.5;    // ...starts at this many R
input double InpTrailATR            = 1.0;    // ...distance behind price (x ATR)

input group "=== Execution / display ==="
input int           InpSlippagePoints = 30;             // Max slippage (points)
input ENUM_GICT_LOG InpLogLevel       = GICT_LOG_INFO;  // Log level
input bool          InpShowPanel      = true;           // Status panel on the chart

//==================== STATE ====================
struct SGictSetup
  {
   bool     active;
   bool     isLong;
   double   entry;     // proximal FVG edge (fill when price comes back here)
   double   fvgFar;    // distal FVG edge
   double   sl;        // stop for the trade
   datetime barTime;   // bar that completed the FVG
   int      window;    // kill zone 1..3 (0 = kill zones off)
  };

CTrade     g_trade;
SGictSetup g_setup;

int      g_hATR   = INVALID_HANDLE;
int      g_hEmaH4 = INVALID_HANDLE;
int      g_hEmaH1 = INVALID_HANDLE;
datetime g_lastBar = 0;

// Daily state (kept across EA restarts with terminal global variables)
int      g_dayKey         = 0;
double   g_dayStartEquity = 0.0;
int      g_tradesToday    = 0;
int      g_windowKey      = 0;
int      g_windowTrades   = 0;

//==================== HELPERS ====================
void Msg(const ENUM_GICT_LOG level, const string text)
  {
   if(InpLogLevel >= level)
      Print("[GoldICT] ", text);
  }

string GvPrefix()
  {
   return("GICT_" + IntegerToString(InpMagic) + "_" + _Symbol + "_");
  }

string Px(const double price)
  {
   return(DoubleToString(price, _Digits));
  }

double NormPrice(const double price)
  {
   double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double p = price;
   if(tick > 0.0)
      p = MathRound(price / tick) * tick;
   return(NormalizeDouble(p, _Digits));
  }

double BufferValue(const int handle, const int shift)
  {
   if(handle == INVALID_HANDLE)
      return(0.0);
   double b[1];
   if(CopyBuffer(handle, 0, shift, 1, b) != 1)
      return(0.0);
   return(b[0]);
  }

bool InHourRange(const int hour, const int startHour, const int endHour)
  {
   if(startHour == endHour)
      return(false);
   if(startHour < endHour)
      return(hour >= startHour && hour < endHour);
   return(hour >= startHour || hour < endHour);     // window across midnight
  }

// 1..3 = inside that kill zone, 0 = outside (or kill zones off)
int CurrentWindow()
  {
   if(!InpUseKillZones)
      return(0);
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(InpKZ1_On && InHourRange(dt.hour, InpKZ1_Start, InpKZ1_End)) return(1);
   if(InpKZ2_On && InHourRange(dt.hour, InpKZ2_Start, InpKZ2_End)) return(2);
   if(InpKZ3_On && InHourRange(dt.hour, InpKZ3_Start, InpKZ3_End)) return(3);
   return(0);
  }

bool IsFridayLate()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return(dt.day_of_week == 5 && dt.hour >= 20);
  }

int CountPositions()
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      n++;
     }
   return(n);
  }

void ClearSetup()
  {
   ZeroMemory(g_setup);
  }

//==================== DAILY STATE ====================
void CheckNewDay()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int key = dt.year * 10000 + dt.mon * 100 + dt.day;
   if(key == g_dayKey)
      return;
   g_dayKey = key;

   string p = GvPrefix();
   bool sameDay = GlobalVariableCheck(p + "DAY") && (int)GlobalVariableGet(p + "DAY") == key &&
                  GlobalVariableCheck(p + "DAYEQ") && GlobalVariableGet(p + "DAYEQ") > 0.0;
   if(sameDay)
     {
      // EA restarted during the day: keep the day's limits
      g_dayStartEquity = GlobalVariableGet(p + "DAYEQ");
      g_tradesToday    = GlobalVariableCheck(p + "DAYTRADES") ? (int)GlobalVariableGet(p + "DAYTRADES") : 0;
      g_windowKey      = GlobalVariableCheck(p + "WKEY")      ? (int)GlobalVariableGet(p + "WKEY")      : 0;
      g_windowTrades   = GlobalVariableCheck(p + "WTRADES")   ? (int)GlobalVariableGet(p + "WTRADES")   : 0;
      Msg(GICT_LOG_INFO, StringFormat("Day state restored: start equity %.2f, trades today %d",
                                      g_dayStartEquity, g_tradesToday));
     }
   else
     {
      g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      g_tradesToday    = 0;
      GlobalVariableSet(p + "DAY", key);
      GlobalVariableSet(p + "DAYEQ", g_dayStartEquity);
      GlobalVariableSet(p + "DAYTRADES", 0);
      Msg(GICT_LOG_INFO, StringFormat("New day: start equity %.2f", g_dayStartEquity));
     }
  }

double DayPLPercent()
  {
   if(g_dayStartEquity <= 0.0)
      return(0.0);
   return((AccountInfoDouble(ACCOUNT_EQUITY) - g_dayStartEquity) / g_dayStartEquity * 100.0);
  }

bool DailyLimitHit(string &why)
  {
   if(g_tradesToday >= InpMaxDailyTrades)
     { why = "max trades today reached"; return(true); }
   double pl = DayPLPercent();
   if(InpMaxDailyLossPct > 0.0 && pl <= -InpMaxDailyLossPct)
     { why = StringFormat("daily loss limit (%.2f%%)", pl); return(true); }
   if(InpMaxDailyProfitPct > 0.0 && pl >= InpMaxDailyProfitPct)
     { why = StringFormat("daily profit target (%.2f%%)", pl); return(true); }
   return(false);
  }

int WindowTradesUsed(const int window)
  {
   int key = g_dayKey * 10 + window;
   return(key == g_windowKey ? g_windowTrades : 0);
  }

void CountWindowTrade(const int window)
  {
   int key = g_dayKey * 10 + window;
   if(key != g_windowKey)
     {
      g_windowKey = key;
      g_windowTrades = 0;
     }
   g_windowTrades++;
   GlobalVariableSet(GvPrefix() + "WKEY", g_windowKey);
   GlobalVariableSet(GvPrefix() + "WTRADES", g_windowTrades);
  }

//==================== INIT / DEINIT ====================
int OnInit()
  {
   if(InpRiskPercent <= 0.0 || InpTP_RR <= 0.0)
     { Print("[GoldICT] Risk % and TP R:R must be > 0"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpSweepBars < 1 || InpLiquidityLookback < InpSweepBars + 5)
     { Print("[GoldICT] Liquidity lookback must be at least sweep bars + 5"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpMinSL_ATR >= InpMaxSL_ATR)
     { Print("[GoldICT] Min SL must be smaller than max SL"); return(INIT_PARAMETERS_INCORRECT); }
   if(InpPartialPercent <= 0.0 || InpPartialPercent >= 100.0)
     { Print("[GoldICT] Partial close % must be between 0 and 100"); return(INIT_PARAMETERS_INCORRECT); }

   g_hATR   = iATR(_Symbol, InpExecTF, 14);
   g_hEmaH4 = iMA(_Symbol, PERIOD_H4, InpH4EmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_hEmaH1 = iMA(_Symbol, PERIOD_H1, InpH1EmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(g_hATR == INVALID_HANDLE || g_hEmaH4 == INVALID_HANDLE || g_hEmaH1 == INVALID_HANDLE)
     { Print("[GoldICT] Indicator handles failed"); return(INIT_FAILED); }

   g_trade.SetExpertMagicNumber((ulong)InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   if(!g_trade.SetTypeFillingBySymbol(_Symbol))
      g_trade.SetTypeFilling(ORDER_FILLING_IOC);

   ClearSetup();
   g_dayKey = 0;
   CheckNewDay();

   Msg(GICT_LOG_INFO, StringFormat("Started on %s %s | risk %.2f%% | TP %.1fR | kill zones %s",
                                   _Symbol, EnumToString(InpExecTF), InpRiskPercent, InpTP_RR,
                                   InpUseKillZones ? "ON" : "OFF"));
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(g_hATR   != INVALID_HANDLE) IndicatorRelease(g_hATR);
   if(g_hEmaH4 != INVALID_HANDLE) IndicatorRelease(g_hEmaH4);
   if(g_hEmaH1 != INVALID_HANDLE) IndicatorRelease(g_hEmaH1);
   Comment("");
  }

//==================== MAIN LOOP ====================
void OnTick()
  {
   CheckNewDay();
   ManagePositions();

   datetime bar = iTime(_Symbol, InpExecTF, 0);
   if(bar != 0 && bar != g_lastBar)
     {
      g_lastBar = bar;
      OnNewBar();
     }

   CheckEntry();

   if(InpShowPanel)
      DrawPanel();
  }

void OnNewBar()
  {
   CleanupPositionVars();

   //--- Expire an untouched setup
   if(g_setup.active)
     {
      int age = iBarShift(_Symbol, InpExecTF, g_setup.barTime, false);
      bool windowOver = (InpUseKillZones && !InpAllowEntryAfterKZ && CurrentWindow() == 0);
      if(age > InpSetupExpiryBars || windowOver)
        {
         Msg(GICT_LOG_INFO, windowOver ? "Setup cancelled: kill zone over" : "Setup cancelled: expired untouched");
         ClearSetup();
        }
     }
   if(g_setup.active)
      return;                                   // one setup at a time

   //--- Look for a new setup
   int window = CurrentWindow();
   if(InpUseKillZones && window == 0)
      return;
   if(InpNoFridayLate && IsFridayLate())
      return;
   if(InpUseKillZones && WindowTradesUsed(window) >= InpMaxTradesPerWindow)
      return;
   string why = "";
   if(DailyLimitHit(why))
      return;

   DetectSetup(window);
  }

//==================== SETUP DETECTION ====================
void DetectSetup(const int window)
  {
   int need = InpLiquidityLookback + 5;
   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(_Symbol, InpExecTF, 0, need, r) < need)
      return;

   double atr = BufferValue(g_hATR, 1);
   if(atr <= 0.0)
      return;
   if(atr < InpMinATR_USD)
     {
      Msg(GICT_LOG_DEBUG, StringFormat("No setup: ATR %.2f below %.2f", atr, InpMinATR_USD));
      return;
     }

   //--- Direction from the H4 EMA (and optionally the H1 EMA)
   bool allowLong = true, allowShort = true;
   if(InpUseH4Bias)
     {
      double ema = BufferValue(g_hEmaH4, 0);
      if(ema <= 0.0) return;
      if(r[1].close <= ema) allowLong  = false;
      if(r[1].close >= ema) allowShort = false;
     }
   if(InpUseH1Filter)
     {
      double ema1 = BufferValue(g_hEmaH1, 0);
      if(ema1 <= 0.0) return;
      if(r[1].close <= ema1) allowLong  = false;
      if(r[1].close >= ema1) allowShort = false;
     }

   if(allowLong && TryBuildSetup(r, atr, true, window))
      return;
   if(allowShort)
      TryBuildSetup(r, atr, false, window);
  }

// FVG completed by the last closed bar: r[3] = candle A, r[2] = displacement B, r[1] = candle C
bool TryBuildSetup(const MqlRates &r[], const double atr, const bool isLong, const int window)
  {
   string side = isLong ? "BUY" : "SELL";

   //--- 1. Fair value gap between A and C
   double gap = isLong ? (r[1].low - r[3].high) : (r[3].low - r[1].high);
   if(gap <= 0.0 || gap < InpFVG_MinSizeATR * atr)
      return(false);

   //--- 2. Displacement: B must be a strong candle in the trade direction
   double body = r[2].close - r[2].open;
   if(isLong ? (body <= 0.0) : (body >= 0.0))
      return(false);
   if(InpDisplacementATR > 0.0 && MathAbs(body) < InpDisplacementATR * atr)
     {
      Msg(GICT_LOG_DEBUG, side + " FVG skipped: displacement candle too small");
      return(false);
     }

   //--- 3. Sweep extreme = lowest low (BUY) / highest high (SELL) of the bars before C
   int sweepEnd = 1 + InpSweepBars;                       // inclusive
   double sweepExt = isLong ? r[2].low : r[2].high;
   for(int k = 2; k <= sweepEnd; k++)
      sweepExt = isLong ? MathMin(sweepExt, r[k].low) : MathMax(sweepExt, r[k].high);

   //--- 4. Liquidity sweep: the move took the older range's low/high, then closed back inside
   if(InpUseLiquiditySweep)
     {
      double liq = isLong ? r[sweepEnd + 1].low : r[sweepEnd + 1].high;
      for(int k = sweepEnd + 1; k <= InpLiquidityLookback; k++)
         liq = isLong ? MathMin(liq, r[k].low) : MathMax(liq, r[k].high);

      bool swept = isLong ? (sweepExt < liq && r[1].close > liq)
                          : (sweepExt > liq && r[1].close < liq);
      if(!swept)
        {
         Msg(GICT_LOG_DEBUG, side + " FVG skipped: no liquidity sweep before it");
         return(false);
        }
     }

   //--- 5. Stop anchor: sweep extreme, or the order block (last opposite candle before B)
   double fvgFar = isLong ? r[3].high : r[3].low;
   double anchor = sweepExt;
   if(InpSLMode == GICT_SL_ORDERBLOCK)
     {
      for(int k = 3; k <= sweepEnd; k++)
        {
         bool opposite = isLong ? (r[k].close < r[k].open) : (r[k].close > r[k].open);
         if(opposite)
           {
            anchor = isLong ? r[k].low : r[k].high;
            break;
           }
        }
      // The order block must sit beyond the FVG, otherwise fall back to the sweep extreme
      if(isLong ? (anchor >= fvgFar) : (anchor <= fvgFar))
         anchor = sweepExt;
     }

   double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double buf    = InpSL_BufferATR * atr;
   double entry  = isLong ? r[1].low : r[1].high;         // proximal FVG edge
   // A SELL stop triggers on the ask, so it also needs the spread
   double sl     = isLong ? (anchor - buf) : (anchor + buf + spread);

   double risk = isLong ? (entry - sl) : (sl - entry);
   if(risk <= 0.0)
      return(false);
   if(risk < InpMinSL_ATR * atr || risk > InpMaxSL_ATR * atr)
     {
      Msg(GICT_LOG_DEBUG, StringFormat("%s FVG skipped: stop %.2f outside %.2f-%.2f x ATR",
                                       side, risk / atr, InpMinSL_ATR, InpMaxSL_ATR));
      return(false);
     }

   //--- Price must still be on the right side of the stop
   double px = isLong ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(isLong ? (px <= sl) : (px >= sl))
      return(false);

   g_setup.active  = true;
   g_setup.isLong  = isLong;
   g_setup.entry   = NormPrice(entry);
   g_setup.fvgFar  = NormPrice(fvgFar);
   g_setup.sl      = NormPrice(sl);
   g_setup.barTime = r[1].time;
   g_setup.window  = window;

   Msg(GICT_LOG_INFO, StringFormat("SETUP %s armed | entry %s | SL %s | FVG %s-%s | risk %.2f (%.2f ATR)%s",
                                   side, Px(g_setup.entry), Px(g_setup.sl),
                                   Px(MathMin(entry, fvgFar)), Px(MathMax(entry, fvgFar)),
                                   risk, risk / atr,
                                   window > 0 ? " | KZ" + IntegerToString(window) : ""));
   return(true);
  }

//==================== ENTRY ====================
void CheckEntry()
  {
   if(!g_setup.active)
      return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0)
      return;

   //--- Invalidated: price reached the stop before we got in
   if(g_setup.isLong ? (bid <= g_setup.sl) : (ask >= g_setup.sl))
     {
      Msg(GICT_LOG_INFO, "Setup invalidated: price hit the stop level before entry");
      ClearSetup();
      return;
     }

   //--- Wait for the retrace into the FVG
   bool tapped = g_setup.isLong ? (ask <= g_setup.entry) : (bid >= g_setup.entry);
   if(!tapped)
      return;

   if(InpUseKillZones && !InpAllowEntryAfterKZ && CurrentWindow() == 0)
      return;                                   // cancelled on the next bar

   string why = "";
   if(DailyLimitHit(why))
     {
      Msg(GICT_LOG_INFO, "Entry skipped: " + why);
      ClearSetup();
      return;
     }
   if(CountPositions() >= InpMaxPositions)
      return;                                   // keep the setup until it expires
   if(ask - bid > InpMaxSpreadUSD)
      return;                                   // wait for the spread to come back

   OpenTrade(ask, bid);
  }

// Lot so that hitting the stop loses InpRiskPercent of equity.
// Rounded DOWN to the volume step; 0 if even the minimum lot would risk more.
double RiskLot(const bool isLong, const double price, const double sl)
  {
   double loss = 0.0;
   if(!OrderCalcProfit(isLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, 1.0, price, sl, loss))
      return(0.0);
   loss = MathAbs(loss);
   if(loss <= 0.0)
      return(0.0);

   double money = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPercent / 100.0;
   double lot   = money / loss;

   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0.0) step = 0.01;

   lot = MathFloor(lot / step + 1e-7) * step;
   lot = MathMin(lot, MathMin(maxLot, InpMaxLot));
   if(lot < minLot)
     {
      Msg(GICT_LOG_INFO, StringFormat("Entry skipped: risk lot %.3f < min lot %.2f (stop too wide for %.2f%% risk)",
                                      lot, minLot, InpRiskPercent));
      return(0.0);
     }

   double margin = 0.0;
   if(OrderCalcMargin(isLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, lot, price, margin) &&
      margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.9)
     {
      Msg(GICT_LOG_INFO, StringFormat("Entry skipped: not enough free margin for %.2f lot", lot));
      return(0.0);
     }

   int digits = (int)MathMax(0, MathRound(-MathLog10(step)));
   return(NormalizeDouble(lot, digits));
  }

void OpenTrade(const double ask, const double bid)
  {
   bool   isLong = g_setup.isLong;
   double price  = isLong ? ask : bid;
   double sl     = g_setup.sl;
   double risk   = isLong ? (price - sl) : (sl - price);
   if(risk <= 0.0)
     { ClearSetup(); return; }

   double tp = NormPrice(isLong ? price + InpTP_RR * risk : price - InpTP_RR * risk);

   double stopLevel = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(risk <= stopLevel || InpTP_RR * risk <= stopLevel)
     {
      Msg(GICT_LOG_INFO, "Entry skipped: stop or target inside the broker stop level");
      ClearSetup();
      return;
     }

   double lot = RiskLot(isLong, price, sl);
   if(lot <= 0.0)
     { ClearSetup(); return; }

   bool ok = isLong ? g_trade.Buy(lot, _Symbol, 0.0, sl, tp, InpComment)
                    : g_trade.Sell(lot, _Symbol, 0.0, sl, tp, InpComment);
   uint rc = g_trade.ResultRetcode();

   if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED))
     {
      g_tradesToday++;
      GlobalVariableSet(GvPrefix() + "DAYTRADES", g_tradesToday);
      if(InpUseKillZones && g_setup.window > 0)
         CountWindowTrade(g_setup.window);
      Msg(GICT_LOG_INFO, StringFormat("TRADE %s %.2f lot @ %s | SL %s | TP %s | risk %.2f%%",
                                      isLong ? "BUY" : "SELL", lot, Px(price), Px(sl), Px(tp), InpRiskPercent));
      ClearSetup();                             // one trade per setup
      return;
     }

   Msg(GICT_LOG_ERROR, StringFormat("Order failed: %u %s", rc, g_trade.ResultRetcodeDescription()));
   bool retry = (rc == TRADE_RETCODE_REQUOTE || rc == TRADE_RETCODE_PRICE_CHANGED ||
                 rc == TRADE_RETCODE_PRICE_OFF || rc == TRADE_RETCODE_TIMEOUT ||
                 rc == TRADE_RETCODE_CONNECTION);
   if(!retry)
      ClearSetup();
  }

//==================== POSITION MANAGEMENT ====================
bool StopDistanceOK(const bool isLong, const double newSL, const double bid, const double ask)
  {
   long stopsLvl  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double minDist = (double)(stopsLvl > freezeLvl ? stopsLvl : freezeLvl) * _Point;
   return(isLong ? (newSL < bid - minDist) : (newSL > ask + minDist));
  }

void ManagePositions()
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0)
      return;

   double atr = -1.0;                           // loaded only if trailing needs it
   string p = GvPrefix();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      bool   isLong = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double open   = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl     = PositionGetDouble(POSITION_SL);
      double vol    = PositionGetDouble(POSITION_VOLUME);
      double px     = isLong ? bid : ask;

      //--- Initial risk (price distance), remembered per position so BE/trailing
      //    never turn it into 0
      string kR = p + "R_" + IntegerToString((long)ticket);
      double risk = GlobalVariableCheck(kR) ? GlobalVariableGet(kR) : 0.0;
      if(risk <= 0.0)
        {
         double d = isLong ? (open - sl) : (sl - open);
         if(sl > 0.0 && d > 0.0)
           {
            risk = d;
            GlobalVariableSet(kR, risk);
           }
         else
            continue;                           // unknown initial risk
        }
      double rNow = (isLong ? (px - open) : (open - px)) / risk;

      //--- Partial close (once per position)
      if(InpUsePartialClose && rNow >= InpPartialR)
        {
         string kP = p + "P_" + IntegerToString((long)ticket);
         if(!GlobalVariableCheck(kP))
           {
            double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
            double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            if(step <= 0.0) step = 0.01;
            double cv = MathFloor(vol * InpPartialPercent / 100.0 / step + 1e-7) * step;
            if(cv >= minLot && (vol - cv) >= minLot - 1e-9)
              {
               if(g_trade.PositionClosePartial(ticket, cv))
                 {
                  GlobalVariableSet(kP, 1.0);
                  Msg(GICT_LOG_INFO, StringFormat("Partial close %.2f lot at %.2fR (#%I64u)", cv, rNow, ticket));
                 }
              }
            else
               GlobalVariableSet(kP, 0.0);      // too small to split - do not retry every tick
           }
        }

      if(!PositionSelectByTicket(ticket))
         continue;                              // fully closed
      sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);

      //--- Breakeven + trailing: pick the best stop, never loosen it
      double newSL = sl;
      if(InpUseBreakEven && rNow >= InpBE_TriggerR)
        {
         double be = isLong ? open + InpBE_LockR * risk : open - InpBE_LockR * risk;
         if(isLong ? (be > newSL) : (newSL == 0.0 || be < newSL))
            newSL = be;
        }
      if(InpUseTrailing && rNow >= InpTrailStartR)
        {
         if(atr < 0.0)
            atr = BufferValue(g_hATR, 1);
         if(atr > 0.0)
           {
            double tr = isLong ? (px - InpTrailATR * atr) : (px + InpTrailATR * atr);
            if(isLong ? (tr > newSL) : (newSL == 0.0 || tr < newSL))
               newSL = tr;
           }
        }
      newSL = NormPrice(newSL);

      // Only modify for a meaningful improvement (no modify spam on every tick)
      double minStep = MathMax(risk * 0.05, 5.0 * _Point);
      bool better = isLong ? (newSL > sl + minStep) : (sl == 0.0 || newSL < sl - minStep);
      if(better && StopDistanceOK(isLong, newSL, bid, ask))
        {
         if(!g_trade.PositionModify(ticket, newSL, tp))
            Msg(GICT_LOG_DEBUG, StringFormat("Stop move failed on #%I64u: %s", ticket, g_trade.ResultRetcodeDescription()));
        }
     }
  }

// Delete the per-position variables of positions that are closed
void CleanupPositionVars()
  {
   string p = GvPrefix();
   for(int i = GlobalVariablesTotal() - 1; i >= 0; i--)
     {
      string name = GlobalVariableName(i);
      if(StringFind(name, p) != 0)
         continue;
      string rest = StringSubstr(name, StringLen(p));
      if(StringFind(rest, "R_") != 0 && StringFind(rest, "P_") != 0)
         continue;
      ulong t = (ulong)StringToInteger(StringSubstr(rest, 2));
      if(t > 0 && !PositionSelectByTicket(t))
         GlobalVariableDel(name);
     }
  }

//==================== PANEL ====================
void DrawPanel()
  {
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE))
      return;
   static datetime lastDraw = 0;
   datetime now = TimeCurrent();
   if(now == lastDraw)
      return;
   lastDraw = now;

   int w = CurrentWindow();
   string win = !InpUseKillZones ? "off (all hours)" : (w > 0 ? "KZ" + IntegerToString(w) + " OPEN" : "closed");
   string setup = "none";
   if(g_setup.active)
      setup = StringFormat("%s  entry %s  SL %s", g_setup.isLong ? "BUY" : "SELL", Px(g_setup.entry), Px(g_setup.sl));

   string s = "GoldICT_Scalper v1.00\n";
   s += "Kill zone: " + win + "\n";
   s += "Setup: " + setup + "\n";
   s += StringFormat("Positions: %d/%d   Trades today: %d/%d\n", CountPositions(), InpMaxPositions,
                     g_tradesToday, InpMaxDailyTrades);
   s += StringFormat("Day P/L: %.2f%%   Spread: $%.2f", DayPLPercent(),
                     SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID));
   Comment(s);
  }
//+------------------------------------------------------------------+
