//+------------------------------------------------------------------+
//|                              Zerith_Gold_MultiZone_Breakout_EA.mq5 |
//|               Zerith Series / Multi-Zone Swing Breakout Engine    |
//|                 https://github.com/BlamzKunG/My-Expert-Advisor   |
//+------------------------------------------------------------------+
#property copyright "Zerith Series / BlamzKunG Architecture"
#property link      "https://github.com/BlamzKunG/My-Expert-Advisor"
#property version   "1.10"
#property description "Zerith Gold Multi-Zone Swing Breakout MT5 EA"
#property description "High-Precision H1 Market Structure Breakout System for XAUUSD (Gold)"
#property description "Features 6 Autonomous Breakout Zones, Dynamic Daily Price Scaling, Multi-Tier BE/Trailing & Prop DD Guard"
//
// v1.10 fixes (vs v1.00):
//  - Buy-stop and sell-stop of the same zone are tracked separately (a zone's
//    sell stop no longer prevents its buy stop from ever being placed/updated).
//  - Lot change on a pending order deletes and re-places it (OrderModify cannot
//    change volume; v1.00 re-sent the same modify on every tick).
//  - All strategy distances are in $0.01 units, so 2-digit and 3-digit gold
//    quotes behave the same (v1.00 was 10x too tight on 3-digit brokers).
//  - NFP calendar is UTC; it is now converted to server time (v1.00 compared
//    UTC times to server time, so the block ran 2-3 hours early).
//    NFP dates corrected: July-4 holiday shifts, Nov 2027/2028 DST, 2025 shutdown.
//  - Session filters (labelled UTC) now really use UTC.
//  - "Close All Trades before Weekend" now actually closes trades.
//  - Trailing / BE never sends an SL inside the broker stop level, and a missed
//    TP (price already beyond it) closes the trade instead of spamming errors.
//  - Pivots are computed once per new H1 bar instead of on every tick.

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| ENUMERATIONS                                                     |
//+------------------------------------------------------------------+
enum ENUM_LOT_MODE
{
   LOT_MODE_RISK_PERCENT = 0, // Risk % Per Trade (StopLoss Based)
   LOT_MODE_FIXED        = 1, // Fixed Lot Size
   LOT_MODE_PER_BALANCE  = 2  // Lot Step Per Balance ($ per 0.01 Lot)
};

enum ENUM_TRAIL_MODE
{
   TRAIL_MODE_DYNAMIC = 0, // Auto Dynamic (Scaled by Gold Daily Price)
   TRAIL_MODE_FIXED   = 1  // Fixed Points (Custom BE Trigger & Trail Dist)
};

//+------------------------------------------------------------------+
//| ZONE CONFIGURATION STRUCTURE                                     |
//+------------------------------------------------------------------+
struct SZoneConfig
{
   string            name;             // Zone Name
   int               magic_suffix;     // Magic Number Offset (+9, +14, etc.)
   ENUM_TIMEFRAMES   tf;               // Calculation Timeframe
   int               pivot_right;      // Right Bars for Pivot Confirmation
   int               pivot_left;       // Left Bars for Pivot Confirmation
   double            buffer_pts;       // Breakout Buffer Distance (Points)
   double            base_tp_pts;      // Base Take Profit Distance (Points)
   double            scale_base_price; // Base Gold Price for Dynamic TP Scaling
   bool              no_wednesday;     // Block Wednesday Trading
};

// Confirmed pivots of one zone, ordered from the most recent (lowest shift)
struct SPivotCache
{
   datetime          barTime;
   double            highs[];
   double            lows[];
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//| "Points" below always mean $0.01 of gold price (1 cent), on both |
//| 2-digit and 3-digit quotes. 3000 points = $30.                   |
//+------------------------------------------------------------------+
input group ">>>> 1. Multi-Zone Breakout Strategy Engine"
input bool            InpZoneA1               = true;              // Zone A1: H1 Base Breakout (London/NY)
input bool            InpZoneA2               = true;              // Zone A2: H1 Base Breakout (London Focus)
input bool            InpZoneA3               = true;              // Zone A3: H1 Base Breakout (Multi-Session)
input bool            InpZoneB1               = true;              // Zone B1: H1 Mid Breakout (Fast Pivots, No Wed)
input bool            InpZoneB2               = true;              // Zone B2: H1 Mid Breakout (Broad Window)
input bool            InpZoneB3               = true;              // Zone B3: H1 Macro Swing Breakout (Large Target)
input bool            InpAllowBuy             = true;              // Allow Buy Trades
input bool            InpAllowSell            = true;              // Allow Sell Trades
input int             InpMaxSpreadPoints      = 600;               // Max Spread Allowed (cents, 600 = $6.00)

input group ">>>> 2. Stop Loss, Take Profit & Trailing System"
input int             InpStopLossPoints       = 3000;              // Stop Loss (cents, 3000 = $30 on Gold)
input ENUM_TRAIL_MODE InpTrailMode            = TRAIL_MODE_DYNAMIC;// Trailing & Break-Even Mode
input int             InpFixedBETriggerPts    = 0;                 // Fixed BE Trigger (cents, 0 = Use Dynamic Scaled)
input int             InpFixedTrailDistPts    = 0;                 // Fixed Trail Distance (cents, 0 = Use Dynamic Scaled)
input int             InpFirstLockPts         = 10;                // Stage 1 BE Profit Lock (cents)

input group ">>>> 3. Money Management & Lot Sizing"
input ENUM_LOT_MODE   InpLotMode              = LOT_MODE_RISK_PERCENT; // Lot Sizing Model
input double          InpRiskPercent          = 1.0;               // Risk % Per Trade (if Risk % Mode)
input double          InpFixedLot             = 0.01;              // Fixed Lot Size (if Fixed Mode)
input double          InpDollarPer001         = 2500.0;            // Account $ per 0.01 Lot (if Per Balance Mode)
input bool            InpUseEquity            = false;             // Base Sizing on Equity (false = Balance)

input group ">>>> 4. Capital Protection (Prop Firm / Daily DD)"
input bool            InpEnableDailyDDLimit   = true;              // Enable Daily Drawdown Protection
input double          InpMaxDailyDDPercent    = 4.0;               // Max Daily DD Limit % from day's peak equity (Closes all on breach)

input group ">>>> 5. Market Windows & Session Filters"
input bool            InpSess_Asia            = true;              // Enable Asia Session (00:00-08:00 UTC)
input bool            InpSess_London          = true;              // Enable London Session (08:00-13:00 UTC)
input bool            InpSess_Overlap         = true;              // Enable London/NY Overlap (13:00-17:00 UTC)
input bool            InpSess_NY              = true;              // Enable New York Session (17:00-24:00 UTC)
input int             InpCloseWindowMins      = 90;                // Minutes before Day End to Stop New Orders (server time)
input int             InpOpenDelayMins        = 15;                // Minutes after Market Open to Resume Trading
input bool            InpCloseWeekend         = false;             // Close All Trades before Weekend
input int             InpFridayStopHour       = 21;                // Friday Trading Cutoff Hour (Server Time)

input group ">>>> 6. Broker Server Time (for NFP & UTC sessions)"
input bool            InpAutoGMTOffset        = true;              // Live: auto-detect server GMT offset
input int             InpServerGMTOffset      = 2;                 // Tester/manual: server GMT offset in winter (hours)
input bool            InpServerUsesUSDST      = true;              // Tester/manual: server adds +1h during US summer time

input group ">>>> 7. News Protection (NFP Filter)"
input bool            InpEnableNFPFilter      = true;              // Enable US Non-Farm Payrolls News Filter
input int             InpNFPMinutesBefore     = 30;                // Mins Before NFP Release to Block Orders
input int             InpNFPMinutesAfter      = 30;                // Mins After NFP Release to Resume Orders
input bool            InpNFPClosePending      = true;              // Cancel Pending Stop Orders during NFP
input bool            InpNFPCloseOpen         = false;             // Close Active Positions during NFP

input group ">>>> 8. System & Interface Settings"
input ulong           InpBaseMagic            = 133700;            // Base Magic Number
input string          InpTradeCommentTag      = "Zerith_XAU";      // Trade Comment Prefix
input bool            InpShowDashboard        = true;              // Show On-Chart HUD Dashboard
input color           InpThemeAccent          = C'0,230,118';      // Theme Accent Color (Emerald Cyan)

//+------------------------------------------------------------------+
//| GLOBAL SYSTEM OBJECTS & STATE                                    |
//+------------------------------------------------------------------+
CTrade            m_trade;
CPositionInfo     m_position;
COrderInfo        m_order;
CAccountInfo      m_account;
CSymbolInfo       m_symbol;

#define ZONE_COUNT       6
#define PIVOT_MAX_SHIFT  100

SZoneConfig       g_zones[ZONE_COUNT];
SPivotCache       g_pivots[ZONE_COUNT];
double            g_unit = 0.01;          // price value of one strategy "point" ($0.01)
bool              g_dailyDDBreached = false;
datetime          g_lastDayTracked = 0;
double            g_dailyPeakEquity = 0.0;
double            g_dailyStartEquity = 0.0;
datetime          g_lastVisualUpdate = 0;

// NFP release times in UTC (13:30 during US winter time, 12:30 during US summer time)
datetime g_nfp_calendar[] = {
   D'2024.01.05 13:30', D'2024.02.02 13:30', D'2024.03.08 13:30', D'2024.04.05 12:30',
   D'2024.05.03 12:30', D'2024.06.07 12:30', D'2024.07.05 12:30', D'2024.08.02 12:30',
   D'2024.09.06 12:30', D'2024.10.04 12:30', D'2024.11.01 12:30', D'2024.12.06 13:30',
   D'2025.01.10 13:30', D'2025.02.07 13:30', D'2025.03.07 13:30', D'2025.04.04 12:30',
   D'2025.05.02 12:30', D'2025.06.06 12:30', D'2025.07.03 12:30', D'2025.08.01 12:30',
   D'2025.09.05 12:30', D'2025.10.03 12:30', D'2025.11.07 13:30', D'2025.12.05 13:30',
   // 2025 US government shutdown: delayed releases (scheduled dates above kept as a precaution)
   D'2025.11.20 13:30', D'2025.12.16 13:30',
   D'2026.01.09 13:30', D'2026.02.06 13:30', D'2026.02.11 13:30', D'2026.03.06 13:30', D'2026.04.03 12:30',
   D'2026.05.08 12:30', D'2026.06.05 12:30', D'2026.07.02 12:30', D'2026.08.07 12:30',
   D'2026.09.04 12:30', D'2026.10.02 12:30', D'2026.11.06 13:30', D'2026.12.04 13:30',
   D'2027.01.08 13:30', D'2027.02.05 13:30', D'2027.03.05 13:30', D'2027.04.02 12:30',
   D'2027.05.07 12:30', D'2027.06.04 12:30', D'2027.07.02 12:30', D'2027.08.06 12:30',
   D'2027.09.03 12:30', D'2027.10.08 12:30', D'2027.11.05 12:30', D'2027.12.03 13:30',
   D'2028.01.07 13:30', D'2028.02.04 13:30', D'2028.03.03 13:30', D'2028.04.07 12:30',
   D'2028.05.05 12:30', D'2028.06.02 12:30', D'2028.07.07 12:30', D'2028.08.04 12:30',
   D'2028.09.01 12:30', D'2028.10.06 12:30', D'2028.11.03 12:30', D'2028.12.08 13:30'
};

//+------------------------------------------------------------------+
//| INITIALIZATION FUNCTIONS                                         |
//+------------------------------------------------------------------+
void InitZones()
{
   // Zone A1: Base H1 Breakout (Magic +9)
   g_zones[0].name             = "A1";
   g_zones[0].magic_suffix     = 9;
   g_zones[0].tf               = PERIOD_H1;
   g_zones[0].pivot_right      = 26;
   g_zones[0].pivot_left       = 24;
   g_zones[0].buffer_pts       = 120.0;
   g_zones[0].base_tp_pts      = 824.0;
   g_zones[0].scale_base_price = 2400.0;
   g_zones[0].no_wednesday     = false;

   // Zone A2: Base H1 Breakout (Magic +14)
   g_zones[1].name             = "A2";
   g_zones[1].magic_suffix     = 14;
   g_zones[1].tf               = PERIOD_H1;
   g_zones[1].pivot_right      = 25;
   g_zones[1].pivot_left       = 23;
   g_zones[1].buffer_pts       = 10.0;
   g_zones[1].base_tp_pts      = 1522.5;
   g_zones[1].scale_base_price = 2600.0;
   g_zones[1].no_wednesday     = false;

   // Zone A3: Base H1 Breakout (Magic +15)
   g_zones[2].name             = "A3";
   g_zones[2].magic_suffix     = 15;
   g_zones[2].tf               = PERIOD_H1;
   g_zones[2].pivot_right      = 26;
   g_zones[2].pivot_left       = 20;
   g_zones[2].buffer_pts       = 80.0;
   g_zones[2].base_tp_pts      = 1284.0;
   g_zones[2].scale_base_price = 2800.0;
   g_zones[2].no_wednesday     = false;

   // Zone B1: Mid H1 Breakout (Magic +13) - Excludes Wednesdays
   g_zones[3].name             = "B1";
   g_zones[3].magic_suffix     = 13;
   g_zones[3].tf               = PERIOD_H1;
   g_zones[3].pivot_right      = 7;
   g_zones[3].pivot_left       = 5;
   g_zones[3].buffer_pts       = 40.0;
   g_zones[3].base_tp_pts      = 1485.0;
   g_zones[3].scale_base_price = 1900.0;
   g_zones[3].no_wednesday     = true;

   // Zone B2: Mid H1 Breakout (Magic +12)
   g_zones[4].name             = "B2";
   g_zones[4].magic_suffix     = 12;
   g_zones[4].tf               = PERIOD_H1;
   g_zones[4].pivot_right      = 30;
   g_zones[4].pivot_left       = 19;
   g_zones[4].buffer_pts       = 160.0;
   g_zones[4].base_tp_pts      = 927.0;
   g_zones[4].scale_base_price = 2600.0;
   g_zones[4].no_wednesday     = false;

   // Zone B3: Macro Swing Breakout (Magic +8)
   g_zones[5].name             = "B3";
   g_zones[5].magic_suffix     = 8;
   g_zones[5].tf               = PERIOD_H1;
   g_zones[5].pivot_right      = 7;
   g_zones[5].pivot_left       = 2;
   g_zones[5].buffer_pts       = 250.0;
   g_zones[5].base_tp_pts      = 3630.0;
   g_zones[5].scale_base_price = 2000.0;
   g_zones[5].no_wednesday     = false;

   for(int z = 0; z < ZONE_COUNT; z++)
   {
      g_pivots[z].barTime = 0;
      ArrayResize(g_pivots[z].highs, 0);
      ArrayResize(g_pivots[z].lows, 0);
   }
}

bool IsZoneEnabled(int idx)
{
   if(idx == 0) return InpZoneA1;
   if(idx == 1) return InpZoneA2;
   if(idx == 2) return InpZoneA3;
   if(idx == 3) return InpZoneB1;
   if(idx == 4) return InpZoneB2;
   if(idx == 5) return InpZoneB3;
   return false;
}

ulong GetZoneMagic(int idx)
{
   if(idx >= 0 && idx < ZONE_COUNT) return InpBaseMagic + g_zones[idx].magic_suffix;
   return InpBaseMagic;
}

int GetZoneIndexByMagic(ulong magic)
{
   for(int i = 0; i < ZONE_COUNT; i++)
   {
      if(GetZoneMagic(i) == magic) return i;
   }
   return -1;
}

ENUM_ORDER_TYPE_FILLING GetOptimalFillingMode()
{
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   if((filling & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

//+------------------------------------------------------------------+
//| EXPERT INITIALIZATION                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   if(!m_symbol.Name(_Symbol))
   {
      Print("[Zerith Error] Failed to initialize symbol: ", _Symbol);
      return INIT_FAILED;
   }
   m_symbol.RefreshRates();

   // One strategy point = $0.01 regardless of 2- or 3-digit quotes
   g_unit = MathMax(_Point, 0.01);

   InitZones();

   m_trade.SetExpertMagicNumber(InpBaseMagic);
   m_trade.SetTypeFilling(GetOptimalFillingMode());
   m_trade.SetDeviationInPoints(15);

   g_dailyStartEquity = m_account.Equity();
   g_dailyPeakEquity  = m_account.Equity();
   g_lastDayTracked   = iTime(_Symbol, PERIOD_D1, 0);

   PrintFormat("[Zerith Init] Zerith Gold Multi-Zone Breakout EA v1.10 loaded on %s (TF: %s, digits %d, server GMT%+d)",
               _Symbol, EnumToString(Period()), _Digits, ServerGMTOffsetHours(TimeCurrent()));

   if(InpShowDashboard) CreateDashboard();

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| EXPERT DEINITIALIZATION                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   RemoveDashboard();
   Comment("");
}

//+------------------------------------------------------------------+
//| SERVER TIME <-> UTC                                              |
//+------------------------------------------------------------------+
datetime NthSundayOfMonth(int year, int month, int n)
{
   MqlDateTime d;
   ZeroMemory(d);
   d.year = year; d.mon = month; d.day = 1;
   datetime first = StructToTime(d);
   MqlDateTime f;
   TimeToStruct(first, f);
   int toSunday = (7 - f.day_of_week) % 7;
   return first + (datetime)((toSunday + 7 * (n - 1)) * 86400);
}

// US daylight saving: 2nd Sunday of March 07:00 UTC -> 1st Sunday of November 06:00 UTC
bool IsUSSummerTime(datetime utc)
{
   MqlDateTime t;
   TimeToStruct(utc, t);
   datetime start = NthSundayOfMonth(t.year, 3, 2) + 7 * 3600;
   datetime end   = NthSundayOfMonth(t.year, 11, 1) + 6 * 3600;
   return (utc >= start && utc < end);
}

// Server GMT offset (hours) valid around the given UTC time
int ServerGMTOffsetHours(datetime utcApprox)
{
   if(InpAutoGMTOffset && !MQLInfoInteger(MQL_TESTER))
   {
      datetime gmt = TimeGMT();
      if(gmt > 0)
         return (int)MathRound((double)(TimeTradeServer() - gmt) / 3600.0);
   }
   return InpServerGMTOffset + ((InpServerUsesUSDST && IsUSSummerTime(utcApprox)) ? 1 : 0);
}

datetime ServerToUTC(datetime server)
{
   datetime approx = server - InpServerGMTOffset * 3600;
   return server - ServerGMTOffsetHours(approx) * 3600;
}

//+------------------------------------------------------------------+
//| DYNAMIC SCALE & PRICING CALCULATIONS                             |
//+------------------------------------------------------------------+
double GetPrevDayOpen()
{
   double prev_d1_open = iOpen(_Symbol, PERIOD_D1, 1);
   if(prev_d1_open <= 0.0) prev_d1_open = m_symbol.Bid();
   return prev_d1_open;
}

double GetDailyScale()
{
   double prev_d1_open = GetPrevDayOpen();
   return (prev_d1_open > 0.0) ? prev_d1_open / 2000.0 : 1.0;
}

double CalculateDynamicTP(int zoneIdx, ENUM_POSITION_TYPE posType, double openPrice)
{
   if(zoneIdx < 0 || zoneIdx >= ZONE_COUNT) return 0.0;

   double dist_pts = g_zones[zoneIdx].base_tp_pts * (GetPrevDayOpen() / g_zones[zoneIdx].scale_base_price);
   double dist = dist_pts * g_unit;

   double tp = (posType == POSITION_TYPE_BUY) ? openPrice + dist : openPrice - dist;
   return NormalizeDouble(tp, _Digits);
}

//+------------------------------------------------------------------+
//| TIME & SESSION ENGINE                                            |
//+------------------------------------------------------------------+
bool IsMinuteBetween(int minuteOfDay, int startMinute, int endMinute)
{
   return (minuteOfDay >= startMinute && minuteOfDay < endMinute);
}

bool IsWeekendCutoff()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return (dt.day_of_week == 0 || dt.day_of_week == 6 ||
           (dt.day_of_week == 5 && dt.hour >= InpFridayStopHour));
}

bool IsEntryWindowOpen()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int minuteOfDay = dt.hour * 60 + dt.min;

   if(InpCloseWeekend && IsWeekendCutoff())
      return false;

   int startMinute = MathMax(0, 50 + InpOpenDelayMins);
   int endMinute   = MathMin(1440, 1440 - InpCloseWindowMins);

   return (minuteOfDay >= startMinute && minuteOfDay < endMinute);
}

bool IsPublicSessionOpen()
{
   MqlDateTime u;
   TimeToStruct(ServerToUTC(TimeCurrent()), u);
   int utcMinute = u.hour * 60 + u.min;

   if(utcMinute < 480)  return InpSess_Asia;
   if(utcMinute < 780)  return InpSess_London;
   if(utcMinute < 1020) return InpSess_Overlap;
   return InpSess_NY;
}

// Zone precision windows are in server time (as originally tuned)
bool IsZoneSessionOpen(int zoneIdx)
{
   if(zoneIdx < 0 || zoneIdx >= ZONE_COUNT) return false;
   if(!IsPublicSessionOpen()) return false;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int minuteOfDay = dt.hour * 60 + dt.min;

   if(g_zones[zoneIdx].no_wednesday && dt.day_of_week == 3) return false;

   if(zoneIdx == 0) // Zone A1
      return IsMinuteBetween(minuteOfDay, 65, 660) ||
             IsMinuteBetween(minuteOfDay, 720, 960) ||
             IsMinuteBetween(minuteOfDay, 1020, 1140) ||
             IsMinuteBetween(minuteOfDay, 1200, 1350);

   if(zoneIdx == 1) // Zone A2
      return IsMinuteBetween(minuteOfDay, 75, 660) ||
             IsMinuteBetween(minuteOfDay, 720, 1140) ||
             IsMinuteBetween(minuteOfDay, 1200, 1260);

   if(zoneIdx == 2) // Zone A3
      return IsMinuteBetween(minuteOfDay, 75, 480) ||
             IsMinuteBetween(minuteOfDay, 540, 660) ||
             IsMinuteBetween(minuteOfDay, 720, 780) ||
             IsMinuteBetween(minuteOfDay, 840, 1020) ||
             IsMinuteBetween(minuteOfDay, 1080, 1350);

   if(zoneIdx == 3) // Zone B1
      return IsMinuteBetween(minuteOfDay, 75, 240) ||
             IsMinuteBetween(minuteOfDay, 300, 480) ||
             IsMinuteBetween(minuteOfDay, 540, 660) ||
             IsMinuteBetween(minuteOfDay, 720, 780) ||
             IsMinuteBetween(minuteOfDay, 1080, 1320);

   if(zoneIdx == 4) // Zone B2
      return IsMinuteBetween(minuteOfDay, 75, 1350);

   if(zoneIdx == 5) // Zone B3
      return IsMinuteBetween(minuteOfDay, 120, 1350);

   return false;
}

bool IsNFPWindowActive()
{
   if(!InpEnableNFPFilter) return false;
   datetime now = TimeCurrent();

   int totalEvents = ArraySize(g_nfp_calendar);
   for(int i = 0; i < totalEvents; i++)
   {
      datetime nfpUtc     = g_nfp_calendar[i];
      datetime nfpServer  = nfpUtc + ServerGMTOffsetHours(nfpUtc) * 3600;
      datetime startBlock = nfpServer - InpNFPMinutesBefore * 60;
      datetime endBlock   = nfpServer + InpNFPMinutesAfter * 60;

      if(now >= startBlock && now <= endBlock)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| SWING PIVOT DETECTION ENGINE (cached per new bar)                |
//+------------------------------------------------------------------+
void RefreshPivots(int z)
{
   ENUM_TIMEFRAMES tf = g_zones[z].tf;
   datetime barTime = iTime(_Symbol, tf, 0);
   if(barTime == 0 || barTime == g_pivots[z].barTime) return;

   int left  = g_zones[z].pivot_left;
   int right = g_zones[z].pivot_right;
   int need  = PIVOT_MAX_SHIFT + left + 1;

   double hi[], lo[];
   ArraySetAsSeries(hi, true);
   ArraySetAsSeries(lo, true);
   int gotH = CopyHigh(_Symbol, tf, 0, need, hi);
   int gotL = CopyLow(_Symbol, tf, 0, need, lo);
   int got  = MathMin(gotH, gotL);
   if(got < left + right + 5) return; // history not ready, retry next tick

   ArrayResize(g_pivots[z].highs, 0);
   ArrayResize(g_pivots[z].lows, 0);

   int maxShift = MathMin(got - left - 1, PIVOT_MAX_SHIFT);
   for(int shift = right + 1; shift <= maxShift; shift++)
   {
      double ch = hi[shift];
      bool isHigh = true;
      for(int l = 1; l <= left && isHigh; l++)   if(hi[shift + l] >= ch) isHigh = false;
      for(int r = 1; r <= right && isHigh; r++)  if(hi[shift - r] >= ch) isHigh = false;
      if(isHigh)
      {
         int n = ArraySize(g_pivots[z].highs);
         ArrayResize(g_pivots[z].highs, n + 1);
         g_pivots[z].highs[n] = ch;
      }

      double cl = lo[shift];
      bool isLow = true;
      for(int l = 1; l <= left && isLow; l++)    if(lo[shift + l] <= cl) isLow = false;
      for(int r = 1; r <= right && isLow; r++)   if(lo[shift - r] <= cl) isLow = false;
      if(isLow)
      {
         int n = ArraySize(g_pivots[z].lows);
         ArrayResize(g_pivots[z].lows, n + 1);
         g_pivots[z].lows[n] = cl;
      }
   }
   g_pivots[z].barTime = barTime;
}

// Most recent confirmed swing high that is still above Ask + buffer
bool FindSwingHigh(int z, double &swingHigh)
{
   double limit = m_symbol.Ask() + g_zones[z].buffer_pts * g_unit;
   int n = ArraySize(g_pivots[z].highs);
   for(int i = 0; i < n; i++)
   {
      if(g_pivots[z].highs[i] > limit)
      {
         swingHigh = g_pivots[z].highs[i];
         return true;
      }
   }
   return false;
}

// Most recent confirmed swing low that is still below Bid - buffer
bool FindSwingLow(int z, double &swingLow)
{
   double limit = m_symbol.Bid() - g_zones[z].buffer_pts * g_unit;
   int n = ArraySize(g_pivots[z].lows);
   for(int i = 0; i < n; i++)
   {
      if(g_pivots[z].lows[i] < limit)
      {
         swingLow = g_pivots[z].lows[i];
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| MONEY MANAGEMENT & LOT CALCULATION                               |
//+------------------------------------------------------------------+
double CalculateLots(double slPoints)
{
   double capital = InpUseEquity ? m_account.Equity() : m_account.Balance();
   double step    = m_symbol.LotsStep();
   double minLot  = m_symbol.LotsMin();
   double maxLot  = m_symbol.LotsMax();
   double lots    = InpFixedLot;

   if(InpLotMode == LOT_MODE_FIXED)
   {
      lots = InpFixedLot;
   }
   else if(InpLotMode == LOT_MODE_PER_BALANCE)
   {
      double stepCapital = MathMax(1.0, InpDollarPer001);
      lots = MathFloor(capital / stepCapital) * 0.01;
   }
   else // LOT_MODE_RISK_PERCENT
   {
      double riskCash = capital * MathMax(0.01, InpRiskPercent) / 100.0;
      double ask = m_symbol.Ask();
      double oneLotLoss = 0.0;

      if(ask > 0.0 && OrderCalcProfit(ORDER_TYPE_BUY, _Symbol, 1.0, ask, ask - slPoints * g_unit, oneLotLoss) && oneLotLoss != 0.0)
         lots = riskCash / MathAbs(oneLotLoss);
      else
         lots = minLot;
   }

   if(step > 0.0) lots = MathFloor((lots + 1e-9) / step) * step;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| POSITION & ORDER QUERIES                                         |
//+------------------------------------------------------------------+
bool HasPositionOfType(ulong magic, ENUM_POSITION_TYPE type)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(m_position.SelectByIndex(i) &&
         m_position.Symbol() == _Symbol &&
         m_position.Magic() == magic &&
         m_position.PositionType() == type)
         return true;
   }
   return false;
}

bool FindPendingOrder(ulong magic, ENUM_ORDER_TYPE type, ulong &ticket, double &price, double &lots)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(m_order.SelectByIndex(i) &&
         m_order.Symbol() == _Symbol &&
         m_order.Magic() == magic &&
         m_order.OrderType() == type)
      {
         ticket = m_order.Ticket();
         price  = m_order.PriceOpen();
         lots   = m_order.VolumeCurrent();
         return true;
      }
   }
   return false;
}

void CancelPendingOrdersByMagic(ulong magic)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(m_order.SelectByIndex(i))
      {
         if(m_order.Symbol() == _Symbol && m_order.Magic() == magic)
         {
            m_trade.OrderDelete(m_order.Ticket());
         }
      }
   }
}

void CancelAllPendingOrders()
{
   for(int z = 0; z < ZONE_COUNT; z++) CancelPendingOrdersByMagic(GetZoneMagic(z));
}

void CloseAllManagedPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(m_position.SelectByIndex(i))
      {
         if(m_position.Symbol() == _Symbol && GetZoneIndexByMagic(m_position.Magic()) >= 0)
         {
            m_trade.PositionClose(m_position.Ticket());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| CAPITAL PROTECTION (PROP FIRM DAILY DRAWDOWN)                    |
//+------------------------------------------------------------------+
void ManageDailyDrawdown()
{
   datetime currentDay = iTime(_Symbol, PERIOD_D1, 0);
   if(currentDay != g_lastDayTracked)
   {
      g_lastDayTracked   = currentDay;
      g_dailyStartEquity = m_account.Equity();
      g_dailyPeakEquity  = m_account.Equity();
      g_dailyDDBreached  = false;
   }

   if(m_account.Equity() > g_dailyPeakEquity)
      g_dailyPeakEquity = m_account.Equity();

   if(!InpEnableDailyDDLimit || g_dailyDDBreached) return;

   double currentDD = (g_dailyPeakEquity > 0.0)
                      ? (g_dailyPeakEquity - m_account.Equity()) / g_dailyPeakEquity * 100.0
                      : 0.0;

   if(currentDD >= InpMaxDailyDDPercent)
   {
      g_dailyDDBreached = true;
      PrintFormat("[Zerith Guard Alert] Daily Drawdown Limit breached (%.2f%% >= %.2f%%)! Closing positions & pausing.",
                  currentDD, InpMaxDailyDDPercent);
      CloseAllManagedPositions();
      CancelAllPendingOrders();
   }
}

//+------------------------------------------------------------------+
//| MULTI-TIER TRAILING STOP & BREAK-EVEN ENGINE                     |
//+------------------------------------------------------------------+
void ManageTrailingAndBE()
{
   double scale = GetDailyScale();
   double trigger_pts = (InpTrailMode == TRAIL_MODE_DYNAMIC || InpFixedBETriggerPts <= 0)
                        ? 110.0 * scale
                        : (double)InpFixedBETriggerPts;
   double trail_pts   = (InpTrailMode == TRAIL_MODE_DYNAMIC || InpFixedTrailDistPts <= 0)
                        ? 121.0 * scale
                        : (double)InpFixedTrailDistPts;

   double trigger_dist = trigger_pts * g_unit;
   double lock_dist    = 30.0 * scale * g_unit;
   double trail_dist   = trail_pts * g_unit;
   double first_lock   = InpFirstLockPts * g_unit;
   double epsilon      = 0.5 * _Point;
   double stopLevel    = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point + _Point;

   double bid = m_symbol.Bid();
   double ask = m_symbol.Ask();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!m_position.SelectByIndex(i)) continue;
      if(m_position.Symbol() != _Symbol) continue;

      int zoneIdx = GetZoneIndexByMagic(m_position.Magic());
      if(zoneIdx < 0) continue;

      ulong  ticket      = m_position.Ticket();
      ENUM_POSITION_TYPE pType = m_position.PositionType();
      bool   isBuy       = (pType == POSITION_TYPE_BUY);
      double openPrice   = m_position.PriceOpen();
      double currentSL   = m_position.StopLoss();
      double currentTP   = m_position.TakeProfit();
      double marketPrice = isBuy ? bid : ask;

      // Ensure Dynamic Take Profit is configured
      if(currentTP <= 0.0)
      {
         double desiredTP = CalculateDynamicTP(zoneIdx, pType, openPrice);
         if(desiredTP > 0.0)
         {
            bool tpReached = isBuy ? (bid >= desiredTP) : (ask <= desiredTP);
            if(tpReached)
            {
               // Price already beyond the target (gap/slippage): take the profit now
               m_trade.PositionClose(ticket);
               continue;
            }
            bool tpValid = isBuy ? (desiredTP > bid + stopLevel) : (desiredTP < ask - stopLevel);
            if(tpValid && m_trade.PositionModify(ticket, currentSL, desiredTP))
               currentTP = desiredTP;
         }
      }

      // Check if price reached BE trigger threshold
      bool triggerHit = isBuy ? (marketPrice >= openPrice + trigger_dist)
                              : (marketPrice <= openPrice - trigger_dist);
      if(!triggerHit) continue;

      // Highest SL (buy) / lowest SL (sell) the broker will accept right now
      double maxSL = isBuy ? bid - stopLevel : ask + stopLevel;

      // Tier 1: Initial Lock-In (small BE buffer)
      double firstSL = NormalizeDouble(isBuy ? openPrice + first_lock : openPrice - first_lock, _Digits);
      bool needFirstLock = isBuy ? (currentSL < firstSL - epsilon)
                                 : (currentSL > firstSL + epsilon || currentSL == 0.0);

      if(needFirstLock)
      {
         bool firstOk = isBuy ? (firstSL <= maxSL) : (firstSL >= maxSL);
         if(firstOk) m_trade.PositionModify(ticket, firstSL, currentTP);
         continue;
      }

      // Tier 2 & 3: Secured lock distance + Trailing behind market
      double lockedSL  = isBuy ? openPrice + lock_dist : openPrice - lock_dist;
      double trailedSL = isBuy ? marketPrice - trail_dist : marketPrice + trail_dist;
      double desiredSL = isBuy ? MathMax(lockedSL, trailedSL) : MathMin(lockedSL, trailedSL);
      desiredSL = isBuy ? MathMin(desiredSL, maxSL) : MathMax(desiredSL, maxSL);
      desiredSL = NormalizeDouble(desiredSL, _Digits);

      bool tighter = isBuy ? (desiredSL > currentSL + epsilon)
                           : (desiredSL < currentSL - epsilon);

      if(tighter)
         m_trade.PositionModify(ticket, desiredSL, currentTP);
   }
}

//+------------------------------------------------------------------+
//| BREAKOUT ORDER EXECUTION ENGINE                                  |
//+------------------------------------------------------------------+
void SyncStopOrder(int z, bool isBuy, double minClearance)
{
   ulong magic = GetZoneMagic(z);
   ENUM_ORDER_TYPE orderType = isBuy ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP;

   double level = 0.0;
   bool found = isBuy ? FindSwingHigh(z, level) : FindSwingLow(z, level);
   if(!found) return;

   double entryPrice = NormalizeDouble(level, _Digits);
   bool clear = isBuy ? (m_symbol.Ask() < entryPrice - minClearance)
                      : (m_symbol.Bid() > entryPrice + minClearance);
   if(!clear) return;

   double desiredLots = CalculateLots(InpStopLossPoints);
   double slDist      = InpStopLossPoints * g_unit;
   double initialSL   = NormalizeDouble(isBuy ? entryPrice - slDist : entryPrice + slDist, _Digits);
   string comment     = StringFormat("%s_%s", InpTradeCommentTag, g_zones[z].name);

   ulong  ticket = 0;
   double pendingPrice = 0.0, pendingLots = 0.0;
   bool hasPending = FindPendingOrder(magic, orderType, ticket, pendingPrice, pendingLots);

   m_trade.SetExpertMagicNumber(magic);

   if(hasPending && MathAbs(pendingLots - desiredLots) >= m_symbol.LotsStep() - 1e-9)
   {
      // Volume cannot be modified on a pending order: replace it
      if(!m_trade.OrderDelete(ticket)) return;
      hasPending = false;
   }

   if(!hasPending)
   {
      if(isBuy) m_trade.BuyStop(desiredLots, entryPrice, _Symbol, initialSL, 0.0, ORDER_TIME_GTC, 0, comment);
      else      m_trade.SellStop(desiredLots, entryPrice, _Symbol, initialSL, 0.0, ORDER_TIME_GTC, 0, comment);
   }
   else if(MathAbs(pendingPrice - entryPrice) > 10.0 * g_unit)
   {
      m_trade.OrderModify(ticket, entryPrice, initialSL, 0.0, ORDER_TIME_GTC, 0);
   }
}

void ProcessBreakoutZones()
{
   if(g_dailyDDBreached) return;
   if(!IsEntryWindowOpen())
   {
      CancelAllPendingOrders();
      return;
   }

   // NFP News Filter check
   if(IsNFPWindowActive())
   {
      if(InpNFPClosePending) CancelAllPendingOrders();
      if(InpNFPCloseOpen)    CloseAllManagedPositions();
      return;
   }

   // Spread check (in $0.01 units)
   double spreadUnits = (m_symbol.Ask() - m_symbol.Bid()) / g_unit;
   if(spreadUnits > InpMaxSpreadPoints)
      return;

   double stopLevel   = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double freezeLevel = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
   double minClearance = MathMax(stopLevel, freezeLevel) + 2.0 * _Point;

   for(int z = 0; z < ZONE_COUNT; z++)
   {
      if(!IsZoneEnabled(z)) continue;
      ulong magic = GetZoneMagic(z);

      // Session Window Check
      if(!IsZoneSessionOpen(z))
      {
         CancelPendingOrdersByMagic(magic);
         continue;
      }

      RefreshPivots(z);

      if(InpAllowBuy && !HasPositionOfType(magic, POSITION_TYPE_BUY))
         SyncStopOrder(z, true, minClearance);

      if(InpAllowSell && !HasPositionOfType(magic, POSITION_TYPE_SELL))
         SyncStopOrder(z, false, minClearance);
   }
}

//+------------------------------------------------------------------+
//| MAIN ONTICK HANDLER                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!m_symbol.RefreshRates()) return;

   ManageDailyDrawdown();

   if(InpCloseWeekend && IsWeekendCutoff())
   {
      CloseAllManagedPositions();
      CancelAllPendingOrders();
   }

   ManageTrailingAndBE();
   ProcessBreakoutZones();

   if(InpShowDashboard)
   {
      datetime now = TimeCurrent();
      if(now - g_lastVisualUpdate >= 1)
      {
         g_lastVisualUpdate = now;
         UpdateDashboard();
      }
   }
}

//+------------------------------------------------------------------+
//| ON-CHART HUD DASHBOARD                                           |
//+------------------------------------------------------------------+
#define UI_PREFIX "ZERITH_DASH_"

void CreateRect(string name, int x, int y, int w, int h, color bg, color border)
{
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void CreateLabel(string name, string text, int x, int y, int fontSize, color textColor, string font="Segoe UI", int anchor=ANCHOR_LEFT_UPPER)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void SetLabelText(string name, string text, color clr=clrNONE)
{
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   if(clr != clrNONE) ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

void CreateDashboard()
{
   int x = 20, y = 30, w = 310, h = 260;
   color bg = C'13,17,23';       // Dark Obsidian
   color border = C'33,38,45';   // Slate Border
   color hdr = C'22,27,34';      // Header fill

   CreateRect(UI_PREFIX+"BG", x, y, w, h, bg, border);
   CreateRect(UI_PREFIX+"HDR", x, y, w, 32, hdr, border);
   CreateRect(UI_PREFIX+"ACCENT", x, y, 4, 32, InpThemeAccent, InpThemeAccent);

   CreateLabel(UI_PREFIX+"TITLE", "ZERITH MULTI-ZONE BREAKOUT", x + 14, y + 8, 9, clrWhite, "Segoe UI Bold");
   CreateLabel(UI_PREFIX+"SUB", "H1 Breakout  |  " + Symbol(), x + 14, y + 22, 7, C'139,148,158');

   // Tiles
   int tileY = y + 42;
   CreateRect(UI_PREFIX+"T1", x + 8, tileY, 142, 36, C'22,27,34', border);
   CreateRect(UI_PREFIX+"T2", x + 158, tileY, 144, 36, C'22,27,34', border);
   CreateLabel(UI_PREFIX+"T1_L", "ACCOUNT EQUITY", x + 16, tileY + 4, 7, C'139,148,158');
   CreateLabel(UI_PREFIX+"T1_V", "$0.00", x + 16, tileY + 18, 9, clrWhite, "Segoe UI Bold");
   CreateLabel(UI_PREFIX+"T2_L", "TODAY P&L", x + 166, tileY + 4, 7, C'139,148,158');
   CreateLabel(UI_PREFIX+"T2_V", "$0.00", x + 166, tileY + 18, 9, clrWhite, "Segoe UI Bold");

   int rowY = tileY + 44;
   CreateLabel(UI_PREFIX+"L_SPREAD", "Spread:", x + 12, rowY, 8, C'139,148,158');
   CreateLabel(UI_PREFIX+"V_SPREAD", "---", x + 120, rowY, 8, clrWhite);

   CreateLabel(UI_PREFIX+"L_SCALE", "Price Scale:", x + 12, rowY + 18, 8, C'139,148,158');
   CreateLabel(UI_PREFIX+"V_SCALE", "---", x + 120, rowY + 18, 8, clrWhite);

   CreateLabel(UI_PREFIX+"L_GUARD", "Daily DD Guard:", x + 12, rowY + 36, 8, C'139,148,158');
   CreateLabel(UI_PREFIX+"V_GUARD", "NORMAL", x + 120, rowY + 36, 8, InpThemeAccent);

   CreateLabel(UI_PREFIX+"L_NFP", "NFP Filter:", x + 12, rowY + 54, 8, C'139,148,158');
   CreateLabel(UI_PREFIX+"V_NFP", "INACTIVE", x + 120, rowY + 54, 8, InpThemeAccent);

   // Zone badges
   int zoneY = rowY + 76;
   CreateLabel(UI_PREFIX+"L_ZONES", "Active Zones:", x + 12, zoneY, 8, C'139,148,158');
   CreateLabel(UI_PREFIX+"V_ZONES", "A1 A2 A3 B1 B2 B3", x + 100, zoneY, 8, InpThemeAccent, "Segoe UI Bold");

   CreateLabel(UI_PREFIX+"L_POS", "Managed Positions:", x + 12, zoneY + 18, 8, C'139,148,158');
   CreateLabel(UI_PREFIX+"V_POS", "0 Orders", x + 130, zoneY + 18, 8, clrWhite);

   ChartRedraw(0);
}

void UpdateDashboard()
{
   double equity = m_account.Equity();
   SetLabelText(UI_PREFIX+"T1_V", StringFormat("$%.2f", equity));

   // Today's realized P&L of this EA's zones
   datetime startToday = iTime(_Symbol, PERIOD_D1, 0);
   double todayProfit = 0.0;
   if(HistorySelect(startToday, TimeCurrent() + 86400))
   {
      for(int h = HistoryDealsTotal() - 1; h >= 0; h--)
      {
         ulong ticket = HistoryDealGetTicket(h);
         if(ticket == 0) continue;
         if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
         if(GetZoneIndexByMagic((ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC)) < 0) continue;
         todayProfit += HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                        HistoryDealGetDouble(ticket, DEAL_SWAP) +
                        HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      }
   }
   color pnlColor = (todayProfit >= 0) ? InpThemeAccent : C'248,81,73';
   SetLabelText(UI_PREFIX+"T2_V", StringFormat("%s$%.2f", (todayProfit >= 0 ? "+" : ""), todayProfit), pnlColor);

   SetLabelText(UI_PREFIX+"V_SPREAD", StringFormat("$%.2f", m_symbol.Ask() - m_symbol.Bid()));
   SetLabelText(UI_PREFIX+"V_SCALE", StringFormat("%.2fx", GetDailyScale()));

   if(g_dailyDDBreached)
      SetLabelText(UI_PREFIX+"V_GUARD", "PAUSED (LIMIT HIT)", C'248,81,73');
   else
      SetLabelText(UI_PREFIX+"V_GUARD", "ACTIVE (OK)", InpThemeAccent);

   if(IsNFPWindowActive())
      SetLabelText(UI_PREFIX+"V_NFP", "BLOCKED (NEWS)", C'255,160,0');
   else
      SetLabelText(UI_PREFIX+"V_NFP", "CLEAR", InpThemeAccent);

   string zoneStr = "";
   for(int z = 0; z < ZONE_COUNT; z++)
      if(IsZoneEnabled(z)) zoneStr += g_zones[z].name + " ";
   SetLabelText(UI_PREFIX+"V_ZONES", zoneStr == "" ? "NONE" : zoneStr);

   int managedPos = 0;
   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      if(m_position.SelectByIndex(p) && m_position.Symbol() == _Symbol && GetZoneIndexByMagic(m_position.Magic()) >= 0)
         managedPos++;
   }
   int managedOrders = 0;
   for(int o = OrdersTotal() - 1; o >= 0; o--)
   {
      if(m_order.SelectByIndex(o) && m_order.Symbol() == _Symbol && GetZoneIndexByMagic(m_order.Magic()) >= 0)
         managedOrders++;
   }
   SetLabelText(UI_PREFIX+"V_POS", StringFormat("%d Pos / %d Pend", managedPos, managedOrders));

   ChartRedraw(0);
}

void RemoveDashboard()
{
   ObjectsDeleteAll(0, UI_PREFIX);
   ChartRedraw(0);
}
//+------------------------------------------------------------------+
