//+------------------------------------------------------------------+
//|                                                GoldSMCFibEA.mq5  |
//|  XAUUSD H1 swing EA: SMC + Fibonacci golden zone + confluence    |
//+------------------------------------------------------------------+
//  KYA KARTA HAI
//   1. Trend (H1) = structure (HH+HL / LH+LL) + EMA (21>34>50, price vs EMA200), dono same.
//      UP = sirf BUY, DOWN = sirf SELL, side-ways = koi trade nahi.
//   2. H1 BOS (pichhle swing ke paar close) -> impulse leg L..H.
//   3. Pullback 0.5-0.7 golden zone. Entry SIRF H1 candle close par:
//      candle zone chhuye, 0.786 ke paar close na kare, 0.618 ke upar (BUY) close kare,
//      aur bullish candle ya pin bar ho. Sirf pehla pullback.
//   4. Confluence score 0-11 -> grade A / A+ / A++. Min grade se kam = skip.
//      1 H4 Fib/level + H1 swing level   2 D / 3D Fib/level   3 W / 1M / 3M / 6M / Y
//      4 EMA 21/34/50/200 zone me ya H4 stack   5 RSI(7) divergence   6 RSI(7) pullback zone
//      7 StochRSI cross   8 Volume spike   9 Liquidity sweep (equal lows/highs bhi)   10 MACD   11 FVG zone me
//   5. SL = Fib 1.0 (L) se $1 aage. TP = Fib 1.272 (strong trend 1.618), kam se kam $15.
//      Smart TP: raaste me mazboot liquidity (equal highs/lows, POC, bada level) ho to usse $0.50 pehle.
//   6. Average se +$5 -> saari positions ka SL = average + $0.20.
//   7. DCA: har $5 ulta, max 3, wahi fixed lot, turant (candle close nahi), 0.786 ke paar nahi.
//   8. Fakeout: H1 candle 0.786 ke paar close -> hedge (fixed lot). Hedge SL = 0.5 ke paar + $1,
//      TP = ulti taraf 1.272 (min $15). Hedge me breakeven hai, DCA default OFF (sirf 1 position).
//   9. Group close (option): main + hedge ka total >= +$1 -> sab band. Default OFF: dono apne SL/TP se.
//  10. Breakeven par band hua aur setup valid -> M15 candle close confirmation par re-entry (max 2).
//  11. Limits: din me max 7 trade, daily SL $, daily target, lagatar loss, weekly loss, equity stop.
//  12. Liquidity heatmap (12H / 1D / 3D / 1W / 1M / ALL), journal CSV + stats panel.
//  13. Manual trades (magic 0) bhi isi strategy se: Fib SL/TP (agar nahi lagaya), breakeven,
//      3 DCA x $5, 0.786 fakeout par hedge, group close.
//  KABHI NAHI: doosre EA ke trade nahi chhedta, lot double nahi karta (DCA fixed lot).
//  RISK: DCA + hedge se ek setup me 8 position tak ho sakti hain. Daily SL limit zaroor rakho.
//+------------------------------------------------------------------+
#property copyright "GoldSMCFibEA"
#property version   "1.01"
#property description "XAUUSD H1: SMC + Fibonacci golden zone + confluence grade"

#include <Trade/Trade.mqh>

enum ENUM_LOTMODE  { LOT_FIXED = 0, LOT_RISK = 1 };
enum ENUM_MINGRADE { MIN_A = 0, MIN_APLUS = 1, MIN_APLUSPLUS = 2 };
enum ENUM_HMRANGE  { HM_12H = 0, HM_1D = 1, HM_3D = 2, HM_1W = 3, HM_1M = 4, HM_ALL = 5 };

input group "=== Risk / Lot ==="
input ENUM_LOTMODE    InpLotMode        = LOT_FIXED;   // Lot mode: FIXED ya RISK %
input double          InpLot            = 0.01;        // FIXED lot (entry, DCA, hedge, re-entry)
input double          InpRiskPct        = 1.0;         // RISK mode: balance ka itna % ek trade (SL tak)
input double          InpMaxLot         = 1.00;        // Ek order ka max lot
input double          InpMaxTotalLots   = 1.00;        // EA ki saari positions ka max kul lot
input double          InpAPPMult        = 1.0;         // A++ grade par lot x (1 = same)

input group "=== Daily / weekly limits ==="
input int             InpMaxTradesDay   = 7;           // Din me max trades (entry + re-entry + hedge; DCA nahi gina)
input double          InpDailySLUSD     = 100.0;       // Daily SL limit $ (0 = off)
input double          InpDailySLPct     = 0.0;         // Daily SL limit % of din-shuru balance (0 = off)
input bool            InpDailyCloseAll  = false;       // Daily SL lage to khule trade bhi band
input double          InpDailyTargetUSD = 0.0;         // Daily target $ (0 = off): poora = us din naye trade band
input int             InpMaxConsecLoss  = 3;           // Din me lagatar itne loss = us din band (0 = off)
input double          InpWeeklyLossPct  = 5.0;         // Hafte ka loss % = hafte bhar band (0 = off)
input double          InpEquityStopPct  = 10.0;        // Equity din-shuru se itna % gire = sab band (0 = off)

input group "=== Filters ==="
input double          InpMaxSpreadUSD   = 0.50;        // Max spread ($)
input bool            InpNewsFilter     = true;        // High-impact news ke aas-paas nayi entry nahi
input int             InpNewsBeforeMin  = 15;          // News se itne min pehle
input int             InpNewsAfterMin   = 15;          // News ke itne min baad tak
input string          InpNewsCurrency   = "USD";       // News currency
input bool            InpUseSession     = false;       // Session filter (server time)
input int             InpSessStartHour  = 0;           // Session shuru (server hour)
input int             InpSessEndHour    = 24;          // Session khatam (server hour)

input group "=== Trend (H1) ==="
input int             InpEMA1           = 21;          // EMA 1
input int             InpEMA2           = 34;          // EMA 2
input int             InpEMA3           = 50;          // EMA 3
input int             InpEMA4           = 200;         // EMA 4
input int             InpSwingBars      = 3;           // Swing = dono taraf itni candles
input int             InpSwingLookback  = 200;         // Swing dhoondhne ke liye H1 candles

input group "=== SMC + Fibonacci ==="
input double          InpZoneTop        = 0.5;         // Golden zone shuru
input double          InpZoneBottom     = 0.7;         // Golden zone khatam
input double          InpConfirmFib     = 0.618;       // Confirmation candle isse aage close kare
input double          InpInvalidFib     = 0.786;       // Fakeout line: iske paar H1 close = hedge, DCA band
input double          InpMinLegATR      = 1.0;         // Impulse leg kam se kam itne ATR(H1)
input double          InpMaxLegATR      = 10.0;        // Impulse leg zyada se zyada itne ATR(H1)
input int             InpSetupMaxBars   = 48;          // BOS ke baad itni H1 candles me entry nahi = setup khatam

input group "=== Exit (Fibonacci) ==="
input double          InpSLBufferUSD    = 1.0;         // SL = Fib 1.0 (L) se itna $ aage
input double          InpTPExt          = 1.272;       // TP extension (normal)
input double          InpTPExtStrong    = 1.618;       // TP extension (strong trend: H1 + H4 EMA stack)
input double          InpTPMinUSD       = 15.0;        // TP kam se kam entry se itna $
input bool            InpSmartTP        = true;        // Smart TP: raaste ki mazboot liquidity se pehle (min $15 ke baad)
input double          InpTPLiqBufUSD    = 0.50;        // Smart TP: liquidity se itna $ pehle
input double          InpBETriggerUSD   = 5.0;         // Average se itna $ profit = breakeven
input double          InpBELockUSD      = 0.20;        // Breakeven SL = average + itna $

input group "=== DCA (turant, candle close nahi) ==="
input bool            InpDCA            = true;        // DCA ON
input int             InpDCAMax         = 3;           // Max DCA per basket
input double          InpDCAStepUSD     = 5.0;         // Aakhri position se itna $ ulta = DCA

input group "=== Fakeout hedge ==="
input bool            InpHedge          = true;        // 0.786 ke paar H1 close = hedge (fixed lot)
input double          InpHedgeSLBufUSD  = 1.0;         // Hedge SL = Fib 0.5 ke paar + itna $
input double          InpHedgeExt       = 1.272;       // Hedge TP = ulti taraf ka extension
input bool            InpHedgeDCA       = false;       // Hedge me bhi DCA (OFF = hedge sirf 1 position, DD kam)
input bool            InpGroupClose     = false;       // Main + hedge ka total +$ hote hi sab band (OFF = dono apne SL/TP se)
input double          InpGroupCloseUSD  = 1.0;         // Group close ON ho to: total itna +$ = sab band

input group "=== Re-entry (breakeven ke baad) ==="
input bool            InpReEntry        = true;        // Re-entry ON
input int             InpReEntryMax     = 2;           // Ek setup me max re-entry
input ENUM_TIMEFRAMES InpReEntryTF      = PERIOD_M15;  // Re-entry confirmation candle TF

input group "=== Confluence grade (11 points) ==="
input ENUM_MINGRADE   InpMinGrade       = MIN_APLUS;   // Min grade
input int             InpGradeAPlus     = 4;           // A+ ke liye min points
input int             InpGradeAPlusPlus = 8;           // A++ ke liye min points
input double          InpConfTolUSD     = 2.0;         // Level zone ke itne $ paas = confluence
input bool            InpUseH4          = true;        // 1: H4 Fib/level + H1 swing level
input bool            InpUseD3D         = true;        // 2: D / 3D Fib/level
input bool            InpUseWBig        = true;        // 3: W / 1M / 3M / 6M / Y Fib/level
input bool            InpUseEMAConf     = true;        // 4: EMA zone me ya H4 stack aligned
input bool            InpUseRSIDiv      = true;        // 5: RSI divergence (hidden/regular)
input bool            InpUseRSIZone     = true;        // 6: RSI pullback zone
input bool            InpUseStochRSI    = true;        // 7: StochRSI cross
input bool            InpUseVolume      = true;        // 8: Volume spike
input bool            InpUseSweep       = true;        // 9: Liquidity sweep (swing / PDL / equal lows-highs)
input bool            InpUseMACD        = true;        // 10: MACD histogram turn / divergence
input bool            InpUseFVG         = true;        // 11: FVG (H1 / M15) golden zone me
input int             InpRSIPeriod      = 7;           // RSI period (divergence + zone)
input double          InpRSIBuyLo       = 30.0;        // BUY: RSI zone min
input double          InpRSIBuyHi       = 50.0;        // BUY: RSI zone max
input double          InpRSISellLo      = 50.0;        // SELL: RSI zone min
input double          InpRSISellHi      = 70.0;        // SELL: RSI zone max
input int             InpStochRSIPeriod = 14;          // StochRSI: RSI period
input int             InpStochKPeriod   = 14;          // StochRSI: stochastic period
input int             InpStochSmooth    = 3;           // StochRSI: %K smoothing
input int             InpStochD         = 3;           // StochRSI: %D
input double          InpStochOS        = 20.0;        // StochRSI oversold
input double          InpStochOB        = 80.0;        // StochRSI overbought
input double          InpVolMult        = 1.5;         // Volume: average ka itna guna
input int             InpVolAvgBars     = 20;          // Volume average candles
input int             InpMACDFast       = 12;          // MACD fast
input int             InpMACDSlow       = 26;          // MACD slow
input int             InpMACDSignal     = 9;           // MACD signal

input group "=== Liquidity heatmap ==="
input bool            InpHeatmap        = true;        // Heatmap ON
input ENUM_HMRANGE    InpHMRange        = HM_1M;       // Range: 12H / 1D / 3D / 1W / 1M / ALL
input double          InpEqualTolUSD    = 0.50;        // Equal highs/lows ki doori ($)
input bool            InpShowFVG        = true;        // FVG box
input bool            InpShowLevels     = true;        // H4 / D / 3D / W / 1M / 3M / 6M / Y levels
input bool            InpShowVP         = true;        // Volume profile
input int             InpVPBins         = 40;          // Volume profile bins

input group "=== Manual trades ==="
input bool            InpManageManual   = true;        // Manual trades (magic 0) bhi isi strategy se manage
input bool            InpKeepManualSLTP = true;        // Manual ka apna SL/TP ho to waisa hi rahe (nahi ho to EA Fib SL/TP lagaye)
input bool            InpManualDCA      = true;        // Manual trade par DCA (3 x $5, manual lot)
input bool            InpManualHedge    = true;        // Manual trade par 0.786 fakeout hedge

input group "=== Journal / panel ==="
input bool            InpJournal        = true;        // Har closed trade CSV me (MQL5/Files)
input string          InpJournalFile    = "GoldSMCFib_Journal.csv";
input bool            InpPanel          = true;        // Panel ON
input int             InpPanelX         = 10;
input int             InpPanelY         = 25;
input long            InpMagic          = 20261124;    // Magic

//==================== GLOBALS ====================
CTrade   trade;
int      hE1 = INVALID_HANDLE, hE2 = INVALID_HANDLE, hE3 = INVALID_HANDLE, hE4 = INVALID_HANDLE;
int      h4E1 = INVALID_HANDLE, h4E2 = INVALID_HANDLE, h4E3 = INVALID_HANDLE, h4E4 = INVALID_HANDLE;
int      hRSI = INVALID_HANDLE, hRSI14 = INVALID_HANDLE, hMACD = INVALID_HANDLE, hATR = INVALID_HANDLE;
#define  PFX  "SFE_P_"
#define  HMP  "SFE_HM_"

struct SetupT
  {
   bool     act;
   int      dir;
   double   L, H;
   bool     touched, entered, hedgeDone, reArmed;
   int      reent, score;
   datetime bosTime;
   double   extreme, tp, sl;
   string   grade, why;
  };
SetupT   S;

struct Basket { int n, dir; double lots, pv, profit, worst, sl, tp, firstLot; };
Basket   MB, HB;   // MB = main (setup direction), HB = hedge
Basket   MMB[2], MHB[2];   // manual basket (0 = BUY, 1 = SELL) aur uska hedge
struct ManCtx { bool act; double L, H; bool hedgeDone; };
ManCtx   MC[2];
#define  K_MAIN  0
#define  K_HEDGE 1
#define  K_MANB  2
#define  K_MANS  3
#define  K_MHB   4
#define  K_MHS   5
#define  MAXPTS  11

bool     rtOn = true, rtHMOn = true;
int      rtMinGrade = 1, rtHM = 4;
double   rtLot = 0.01;
int      curTrend = 0;
string   entryWhy = "-";
string   gv;
datetime lastH1 = 0, lastM15 = 0;
int      prevMainN = 0;

datetime dayStart = 0;
double   dayStartEq = 0, dayStartBal = 0;
int      consecLoss = 0, tradesToday = 0;
bool     dayStopped = false;
string   stopWhy = "";
double   plToday = 0, plWeek = 0, weekStartBal = 0;

int      stTotal = 0, stWins = 0, stAP = 0, stAPW = 0, stAPP = 0, stAPPW = 0, stNW = 0, stNL = 0;
double   stSumW = 0, stSumL = 0;

bool     newsNow = false;
datetime lastNewsCheck = 0;
int      timerTick = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpLot <= 0 || InpMaxLot <= 0 || InpDCAStepUSD <= 0 || InpTPExt <= 1.0 || InpTPExtStrong <= 1.0 ||
      !(InpZoneTop < InpConfirmFib && InpConfirmFib < InpZoneBottom && InpZoneBottom < InpInvalidFib && InpInvalidFib < 1.0) ||
      InpSwingBars < 1 || InpGradeAPlus > InpGradeAPlusPlus)
     {
      Print("Inputs galat: lot > 0, TP ext > 1, aur 0.5 < 0.618 < 0.7 < 0.786 < 1 ka kram zaroori");
      return(INIT_PARAMETERS_INCORRECT);
     }
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFillingBySymbol(_Symbol);

   hE1  = iMA(_Symbol, PERIOD_H1, InpEMA1, 0, MODE_EMA, PRICE_CLOSE);
   hE2  = iMA(_Symbol, PERIOD_H1, InpEMA2, 0, MODE_EMA, PRICE_CLOSE);
   hE3  = iMA(_Symbol, PERIOD_H1, InpEMA3, 0, MODE_EMA, PRICE_CLOSE);
   hE4  = iMA(_Symbol, PERIOD_H1, InpEMA4, 0, MODE_EMA, PRICE_CLOSE);
   h4E1 = iMA(_Symbol, PERIOD_H4, InpEMA1, 0, MODE_EMA, PRICE_CLOSE);
   h4E2 = iMA(_Symbol, PERIOD_H4, InpEMA2, 0, MODE_EMA, PRICE_CLOSE);
   h4E3 = iMA(_Symbol, PERIOD_H4, InpEMA3, 0, MODE_EMA, PRICE_CLOSE);
   h4E4 = iMA(_Symbol, PERIOD_H4, InpEMA4, 0, MODE_EMA, PRICE_CLOSE);
   hRSI   = iRSI(_Symbol, PERIOD_H1, InpRSIPeriod, PRICE_CLOSE);
   hRSI14 = iRSI(_Symbol, PERIOD_H1, InpStochRSIPeriod, PRICE_CLOSE);
   hMACD  = iMACD(_Symbol, PERIOD_H1, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE);
   hATR   = iATR(_Symbol, PERIOD_H1, 14);
   if(hE1 == INVALID_HANDLE || hE2 == INVALID_HANDLE || hE3 == INVALID_HANDLE || hE4 == INVALID_HANDLE ||
      h4E1 == INVALID_HANDLE || h4E2 == INVALID_HANDLE || h4E3 == INVALID_HANDLE || h4E4 == INVALID_HANDLE ||
      hRSI == INVALID_HANDLE || hRSI14 == INVALID_HANDLE || hMACD == INVALID_HANDLE || hATR == INVALID_HANDLE)
     {
      Print("Indicator handle nahi bana");
      return(INIT_FAILED);
     }

   rtOn = true; rtLot = InpLot; rtMinGrade = (int)InpMinGrade; rtHM = (int)InpHMRange; rtHMOn = InpHeatmap;
   gv = "SFE_" + _Symbol + "_" + IntegerToString(InpMagic) + "_";
   ResetSetup();
   for(int k = 0; k < 2; k++) { MC[k].act = false; MC[k].L = 0; MC[k].H = 0; MC[k].hedgeDone = false; }
   LoadState();
   ReadBaskets();
   prevMainN = MB.n;
   curTrend = Trend();
   lastH1 = iTime(_Symbol, PERIOD_H1, 0);       // attach karte hi purani candle par entry nahi
   lastM15 = iTime(_Symbol, InpReEntryTF, 0);
   entryWhy = "agle H1 candle close ka intezaar";
   CheckNewDay();
   UpdateDayStats();
   UpdateStats();
   EventSetTimer(1);
   if(rtHMOn) DrawHeatmap();
   Panel();
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int r)
  {
   EventKillTimer();
   IndicatorRelease(hE1); IndicatorRelease(hE2); IndicatorRelease(hE3); IndicatorRelease(hE4);
   IndicatorRelease(h4E1); IndicatorRelease(h4E2); IndicatorRelease(h4E3); IndicatorRelease(h4E4);
   IndicatorRelease(hRSI); IndicatorRelease(hRSI14); IndicatorRelease(hMACD); IndicatorRelease(hATR);
   ObjectsDeleteAll(0, PFX);
   ObjectsDeleteAll(0, HMP);
   SaveState();
  }

void OnTimer()
  {
   timerTick++;
   CheckNewDay();
   if(timerTick % 2 == 0) UpdateDayStats();
   if(timerTick % 30 == 0) UpdateStats();
   UpdateNews();
   Panel();
  }

//==================== HELPERS ====================
double Bid()      { return SymbolInfoDouble(_Symbol, SYMBOL_BID); }
double Ask()      { return SymbolInfoDouble(_Symbol, SYMBOL_ASK); }
double Spread()   { return Ask() - Bid(); }
double VolMin()   { return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN); }
double StopsMin()
  {
   long a = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL), b = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   long lv = a > b ? a : b;
   return (double)(lv + 2) * _Point;
  }
double NP(double p) { return NormalizeDouble(p, _Digits); }
double Buf(int h, int buf, int shift)
  {
   double a[1];
   if(CopyBuffer(h, buf, shift, 1, a) != 1) return EMPTY_VALUE;
   return a[0];
  }
bool Mine()
  {
   return PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic;
  }
bool IsHedgeCmt(string c) { return StringFind(c, "SFE H") == 0; }
bool IsEntryCmt(string c) { return StringFind(c, "SFE E") == 0 || StringFind(c, "SFE R") == 0 || StringFind(c, "SFE HG") == 0; }

double NormLot(double lot)
  {
   double mn = VolMin(), mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP); if(st <= 0) st = 0.01;
   lot = MathFloor(lot / st + 1e-9) * st;
   lot = MathMin(lot, MathMin(mx, InpMaxLot));
   return NormalizeDouble(MathMax(mn, lot), 2);
  }

// FIXED = rtLot. RISK = balance ka % / SL doori (tick value se)
double CalcLot(double slDist)
  {
   if(InpLotMode == LOT_FIXED || slDist <= 0) return NormLot(rtLot);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tv <= 0) tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(ts <= 0 || tv <= 0) return NormLot(rtLot);
   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPct / 100.0;
   return NormLot(risk / (slDist / ts * tv));
  }

double TotalLots()
  {
   double t = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetTicket(i) > 0 && Mine()) t += PositionGetDouble(POSITION_VOLUME);
   return t;
  }

bool SendOrder(int dir, double lot, double sl, double tp, string cmt)
  {
   if(TotalLots() + lot > InpMaxTotalLots + 1e-9) { PrintFormat("Skip %s: max total lots %.2f", cmt, InpMaxTotalLots); return false; }
   double px = dir == 1 ? Ask() : Bid();
   double mreq = 0;
   if(OrderCalcMargin(dir == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, lot, px, mreq) &&
      mreq > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
     {
      PrintFormat("Skip %s: margin kam (chahiye %.2f)", cmt, mreq);
      return false;
     }
   double sm = StopsMin();
   if(sl > 0 && ((dir == 1 && Bid() - sl < sm) || (dir == -1 && sl - Ask() < sm))) { PrintFormat("Skip %s: SL price ke bahut paas", cmt); return false; }
   if(tp > 0 && ((dir == 1 && tp - Ask() < sm) || (dir == -1 && Bid() - tp < sm))) tp = 0;
   bool ok = dir == 1 ? trade.Buy(lot, _Symbol, 0, NP(sl), NP(tp), cmt) : trade.Sell(lot, _Symbol, 0, NP(sl), NP(tp), cmt);
   if(!ok || (trade.ResultRetcode() != TRADE_RETCODE_DONE && trade.ResultRetcode() != TRADE_RETCODE_PLACED))
     {
      PrintFormat("Order fail %s: %d %s", cmt, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      return false;
     }
   PrintFormat("OPEN %s %s %.2f lot @ %.2f  SL %.2f  TP %.2f", dir == 1 ? "BUY" : "SELL", cmt, lot, px, sl, tp);
   return true;
  }

void CloseAll(string why)
  {
   PrintFormat("CLOSE ALL: %s", why);
   for(int pass = 0; pass < 3; pass++)
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(t > 0 && Mine()) trade.PositionClose(t);
        }
  }

//==================== BASKETS ====================
void ZeroB(Basket &b) { b.n = 0; b.dir = 0; b.lots = 0; b.pv = 0; b.profit = 0; b.worst = 0; b.sl = 0; b.tp = 0; b.firstLot = 0; }
double Avg(Basket &b) { return b.lots > 0 ? b.pv / b.lots : 0; }

void AddB(Basket &b, int d, double v, double op, double pr, double sl, double tp)
  {
   b.n++; b.dir = d; b.lots += v; b.pv += v * op; b.profit += pr;
   if(b.worst == 0 || (d == 1 && op < b.worst) || (d == -1 && op > b.worst)) b.worst = op;
   if(b.sl == 0) b.sl = sl;
   if(b.tp == 0) b.tp = tp;
   if(b.firstLot == 0) b.firstLot = v;
  }

// Selected position kis basket ki hai (-1 = hamari nahi)
int KindOf()
  {
   if(PositionGetString(POSITION_SYMBOL) != _Symbol) return -1;
   long mg = PositionGetInteger(POSITION_MAGIC);
   int d = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
   if(mg == 0) return InpManageManual ? (d == 1 ? K_MANB : K_MANS) : -1;
   if(mg != InpMagic) return -1;
   string c = PositionGetString(POSITION_COMMENT);
   if(StringFind(c, "SFE MHB") == 0) return K_MHB;
   if(StringFind(c, "SFE MHS") == 0) return K_MHS;
   if(StringFind(c, "SFE MD") == 0)  return d == 1 ? K_MANB : K_MANS;
   if(StringFind(c, "SFE H") == 0)   return K_HEDGE;
   return K_MAIN;
  }

void ReadBaskets()
  {
   ZeroB(MB); ZeroB(HB);
   for(int k = 0; k < 2; k++) { ZeroB(MMB[k]); ZeroB(MHB[k]); }
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0) continue;
      int kind = KindOf();
      if(kind < 0) continue;
      int d = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
      double v = PositionGetDouble(POSITION_VOLUME), op = PositionGetDouble(POSITION_PRICE_OPEN);
      double pr = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      double sl = PositionGetDouble(POSITION_SL), tp = PositionGetDouble(POSITION_TP);
      if(kind == K_MAIN)       AddB(MB, d, v, op, pr, sl, tp);
      else if(kind == K_HEDGE) AddB(HB, d, v, op, pr, sl, tp);
      else if(kind == K_MANB)  AddB(MMB[0], d, v, op, pr, sl, tp);
      else if(kind == K_MANS)  AddB(MMB[1], d, v, op, pr, sl, tp);
      else if(kind == K_MHB)   AddB(MHB[0], d, v, op, pr, sl, tp);
      else if(kind == K_MHS)   AddB(MHB[1], d, v, op, pr, sl, tp);
     }
  }

void CloseKind(int kind)
  {
   for(int pass = 0; pass < 3; pass++)
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(t > 0 && KindOf() == kind) trade.PositionClose(t);
        }
  }

//==================== STATE (restart ke baad yaad rahe) ====================
void ResetSetup()
  {
   S.act = false; S.dir = 0; S.L = 0; S.H = 0; S.touched = false; S.entered = false; S.hedgeDone = false;
   S.reArmed = false; S.reent = 0; S.score = 0; S.bosTime = 0; S.extreme = 0; S.tp = 0; S.sl = 0;
   S.grade = "-"; S.why = "";
  }

void SaveState()
  {
   if(MQLInfoInteger(MQL_TESTER)) return;
   GlobalVariableSet(gv + "act", S.act ? 1 : 0);   GlobalVariableSet(gv + "dir", S.dir);
   GlobalVariableSet(gv + "L", S.L);                GlobalVariableSet(gv + "H", S.H);
   GlobalVariableSet(gv + "tch", S.touched ? 1 : 0); GlobalVariableSet(gv + "ent", S.entered ? 1 : 0);
   GlobalVariableSet(gv + "hdg", S.hedgeDone ? 1 : 0); GlobalVariableSet(gv + "rea", S.reArmed ? 1 : 0);
   GlobalVariableSet(gv + "ren", S.reent);          GlobalVariableSet(gv + "sco", S.score);
   GlobalVariableSet(gv + "bos", (double)(long)S.bosTime); GlobalVariableSet(gv + "ext", S.extreme);
   GlobalVariableSet(gv + "tp", S.tp);              GlobalVariableSet(gv + "sl", S.sl);
   GlobalVariableSet(gv + "dS", (double)(long)dayStart); GlobalVariableSet(gv + "dEq", dayStartEq);
   GlobalVariableSet(gv + "dBal", dayStartBal);     GlobalVariableSet(gv + "cL", consecLoss);
   GlobalVariableSet(gv + "dSt", dayStopped ? 1 : 0);
   for(int k = 0; k < 2; k++)
     {
      string m = gv + "m" + IntegerToString(k);
      GlobalVariableSet(m + "a", MC[k].act ? 1 : 0); GlobalVariableSet(m + "L", MC[k].L);
      GlobalVariableSet(m + "H", MC[k].H);           GlobalVariableSet(m + "h", MC[k].hedgeDone ? 1 : 0);
     }
  }

void LoadState()
  {
   if(MQLInfoInteger(MQL_TESTER) || !GlobalVariableCheck(gv + "act")) return;
   S.act = GlobalVariableGet(gv + "act") > 0.5;  S.dir = (int)GlobalVariableGet(gv + "dir");
   S.L = GlobalVariableGet(gv + "L");             S.H = GlobalVariableGet(gv + "H");
   S.touched = GlobalVariableGet(gv + "tch") > 0.5; S.entered = GlobalVariableGet(gv + "ent") > 0.5;
   S.hedgeDone = GlobalVariableGet(gv + "hdg") > 0.5; S.reArmed = GlobalVariableGet(gv + "rea") > 0.5;
   S.reent = (int)GlobalVariableGet(gv + "ren"); S.score = (int)GlobalVariableGet(gv + "sco");
   S.bosTime = (datetime)(long)GlobalVariableGet(gv + "bos"); S.extreme = GlobalVariableGet(gv + "ext");
   S.tp = GlobalVariableGet(gv + "tp");           S.sl = GlobalVariableGet(gv + "sl");
   S.grade = GradeName(S.score);
   if(GlobalVariableCheck(gv + "dS"))
     {
      dayStart = (datetime)(long)GlobalVariableGet(gv + "dS");
      dayStartEq = GlobalVariableGet(gv + "dEq"); dayStartBal = GlobalVariableGet(gv + "dBal");
      consecLoss = (int)GlobalVariableGet(gv + "cL"); dayStopped = GlobalVariableGet(gv + "dSt") > 0.5;
      if(dayStopped) stopWhy = "aaj ka stop (restart se pehle)";
     }
   for(int k = 0; k < 2; k++)
     {
      string m = gv + "m" + IntegerToString(k);
      if(!GlobalVariableCheck(m + "a")) continue;
      MC[k].act = GlobalVariableGet(m + "a") > 0.5; MC[k].L = GlobalVariableGet(m + "L");
      MC[k].H = GlobalVariableGet(m + "H");          MC[k].hedgeDone = GlobalVariableGet(m + "h") > 0.5;
      if(MC[k].act && MC[k].H <= MC[k].L) MC[k].act = false;
     }
   if(S.act && (S.dir == 0 || S.H <= S.L)) ResetSetup();
  }

void Deactivate(string why)
  {
   if(S.act) PrintFormat("Setup khatam: %s", why);
   ResetSetup();
   SaveState();
  }

//==================== DAY / WEEK ====================
datetime DayStartOf(datetime t) { return t - (t % 86400); }
datetime WeekStartOf(datetime t)
  {
   MqlDateTime d; TimeToStruct(t, d);
   return DayStartOf(t) - ((d.day_of_week + 6) % 7) * 86400;
  }

void CheckNewDay()
  {
   datetime d0 = DayStartOf(TimeCurrent());
   if(d0 == dayStart) return;
   dayStart = d0;
   dayStartEq = AccountInfoDouble(ACCOUNT_EQUITY);
   dayStartBal = AccountInfoDouble(ACCOUNT_BALANCE);
   consecLoss = 0; dayStopped = false; stopWhy = "";
   SaveState();
  }

double Floating()
  {
   double f = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetTicket(i) > 0 && Mine()) f += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   return f;
  }

void UpdateDayStats()
  {
   datetime now = TimeCurrent(), ws = WeekStartOf(now);
   double closedDay = 0, closedWeek = 0; int cnt = 0;
   if(HistorySelect(ws, now + 3600))
      for(int i = 0; i < HistoryDealsTotal(); i++)
        {
         ulong dl = HistoryDealGetTicket(i);
         if(dl == 0 || HistoryDealGetString(dl, DEAL_SYMBOL) != _Symbol || HistoryDealGetInteger(dl, DEAL_MAGIC) != InpMagic) continue;
         double v = HistoryDealGetDouble(dl, DEAL_PROFIT) + HistoryDealGetDouble(dl, DEAL_SWAP) + HistoryDealGetDouble(dl, DEAL_COMMISSION);
         datetime tm = (datetime)HistoryDealGetInteger(dl, DEAL_TIME);
         closedWeek += v;
         if(tm >= dayStart)
           {
            closedDay += v;
            if(HistoryDealGetInteger(dl, DEAL_ENTRY) == DEAL_ENTRY_IN && IsEntryCmt(HistoryDealGetString(dl, DEAL_COMMENT))) cnt++;
           }
        }
   double fl = Floating();
   plToday = closedDay + fl;
   plWeek = closedWeek + fl;
   weekStartBal = AccountInfoDouble(ACCOUNT_BALANCE) - closedWeek;
   tradesToday = cnt;
  }

// Saare closed trades: win %, grade ke hisaab se (sirf entry / re-entry positions gini)
void UpdateStats()
  {
   stTotal = 0; stWins = 0; stAP = 0; stAPW = 0; stAPP = 0; stAPPW = 0; stNW = 0; stNL = 0; stSumW = 0; stSumL = 0;
   if(!HistorySelect(0, TimeCurrent() + 3600)) return;
   int nd = HistoryDealsTotal();
   long ids[]; string cm[]; double pl[]; bool isOut[];
   int n = 0;
   for(int i = 0; i < nd; i++)
     {
      ulong dl = HistoryDealGetTicket(i);
      if(dl == 0 || HistoryDealGetString(dl, DEAL_SYMBOL) != _Symbol || HistoryDealGetInteger(dl, DEAL_MAGIC) != InpMagic) continue;
      long pid = HistoryDealGetInteger(dl, DEAL_POSITION_ID);
      int k = -1;
      for(int j = 0; j < n; j++) if(ids[j] == pid) { k = j; break; }
      if(k < 0)
        {
         ArrayResize(ids, n + 1); ArrayResize(cm, n + 1); ArrayResize(pl, n + 1); ArrayResize(isOut, n + 1);
         ids[n] = pid; cm[n] = ""; pl[n] = 0; isOut[n] = false; k = n; n++;
        }
      long en = HistoryDealGetInteger(dl, DEAL_ENTRY);
      if(en == DEAL_ENTRY_IN) cm[k] = HistoryDealGetString(dl, DEAL_COMMENT);
      else isOut[k] = true;
      pl[k] += HistoryDealGetDouble(dl, DEAL_PROFIT) + HistoryDealGetDouble(dl, DEAL_SWAP) + HistoryDealGetDouble(dl, DEAL_COMMISSION);
     }
   for(int k = 0; k < n; k++)
     {
      if(!isOut[k] || !(StringFind(cm[k], "SFE E") == 0 || StringFind(cm[k], "SFE R") == 0)) continue;
      bool w = pl[k] > 0;
      stTotal++; if(w) { stWins++; stNW++; stSumW += pl[k]; } else { stNL++; stSumL += pl[k]; }
      if(StringFind(cm[k], "A++") >= 0) { stAPP++; if(w) stAPPW++; }
      else if(StringFind(cm[k], "A+") >= 0) { stAP++; if(w) stAPW++; }
     }
  }

//==================== NEWS ====================
void UpdateNews()
  {
   if(!InpNewsFilter || MQLInfoInteger(MQL_TESTER)) { newsNow = false; return; }
   if(TimeCurrent() - lastNewsCheck < 60) return;
   lastNewsCheck = TimeCurrent();
   newsNow = false;
   datetime now = TimeTradeServer();
   MqlCalendarValue vals[];
   if(CalendarValueHistory(vals, now - InpNewsAfterMin * 60, now + InpNewsBeforeMin * 60, NULL, InpNewsCurrency) <= 0) return;
   for(int i = 0; i < ArraySize(vals); i++)
     {
      MqlCalendarEvent ev;
      if(CalendarEventById(vals[i].event_id, ev) && ev.importance == CALENDAR_IMPORTANCE_HIGH) { newsNow = true; break; }
     }
  }

// Nayi entry ki ijazat (hedge par ye limits nahi lagti, wo bachav hai)
bool AllowNew(string &why)
  {
   why = "";
   if(!rtOn) { why = "EA OFF"; return false; }
   if(dayStopped) { why = stopWhy; return false; }
   if(InpMaxTradesDay > 0 && tradesToday >= InpMaxTradesDay) { why = StringFormat("aaj ke max %d trade ho gaye", InpMaxTradesDay); return false; }
   double lim = DailyLimit();
   if(lim > 0 && plToday <= -lim) { why = StringFormat("daily SL limit -$%.2f", lim); return false; }
   if(InpDailyTargetUSD > 0 && plToday >= InpDailyTargetUSD) { why = "daily target poora"; return false; }
   if(InpMaxConsecLoss > 0 && consecLoss >= InpMaxConsecLoss) { why = StringFormat("lagatar %d loss", consecLoss); return false; }
   if(InpWeeklyLossPct > 0 && weekStartBal > 0 && plWeek <= -weekStartBal * InpWeeklyLossPct / 100.0) { why = "weekly loss limit"; return false; }
   if(Spread() > InpMaxSpreadUSD) { why = StringFormat("spread $%.2f zyada", Spread()); return false; }
   if(newsNow) { why = "news time"; return false; }
   if(InpUseSession)
     {
      MqlDateTime d; TimeToStruct(TimeCurrent(), d);
      bool in = InpSessStartHour <= InpSessEndHour ? (d.hour >= InpSessStartHour && d.hour < InpSessEndHour)
                                                    : (d.hour >= InpSessStartHour || d.hour < InpSessEndHour);
      if(!in) { why = "session ke bahar"; return false; }
     }
   return true;
  }

double DailyLimit()
  {
   double a = InpDailySLUSD > 0 ? InpDailySLUSD : 0;
   double b = InpDailySLPct > 0 ? dayStartBal * InpDailySLPct / 100.0 : 0;
   if(a > 0 && b > 0) return MathMin(a, b);
   return MathMax(a, b);
  }

//==================== STRUCTURE / TREND ====================
bool IsSwingHigh(ENUM_TIMEFRAMES tf, int s, int n)
  {
   double h = iHigh(_Symbol, tf, s);
   if(h <= 0) return false;
   for(int k = 1; k <= n; k++)
      if(iHigh(_Symbol, tf, s + k) >= h || iHigh(_Symbol, tf, s - k) > h) return false;
   return true;
  }
bool IsSwingLow(ENUM_TIMEFRAMES tf, int s, int n)
  {
   double l = iLow(_Symbol, tf, s);
   if(l <= 0) return false;
   for(int k = 1; k <= n; k++)
      if(iLow(_Symbol, tf, s + k) <= l || iLow(_Symbol, tf, s - k) < l) return false;
   return true;
  }

// Sabse naye 2 swing high aur 2 swing low (sirf confirmed candles)
bool Swings(double &sh1, double &sh2, int &bsh, double &sl1, double &sl2, int &bsl)
  {
   int nH = 0, nL = 0;
   sh1 = 0; sh2 = 0; sl1 = 0; sl2 = 0; bsh = 0; bsl = 0;
   int maxS = (int)MathMin(InpSwingLookback, iBars(_Symbol, PERIOD_H1) - InpSwingBars - 2);
   for(int s = InpSwingBars + 1; s < maxS && (nH < 2 || nL < 2); s++)
     {
      if(nH < 2 && IsSwingHigh(PERIOD_H1, s, InpSwingBars)) { if(nH == 0) { sh1 = iHigh(_Symbol, PERIOD_H1, s); bsh = s; } else sh2 = iHigh(_Symbol, PERIOD_H1, s); nH++; }
      if(nL < 2 && IsSwingLow(PERIOD_H1, s, InpSwingBars))  { if(nL == 0) { sl1 = iLow(_Symbol, PERIOD_H1, s); bsl = s; } else sl2 = iLow(_Symbol, PERIOD_H1, s); nL++; }
     }
   return nH == 2 && nL == 2;
  }

int StructTrend()
  {
   double sh1, sh2, sl1, sl2; int bsh, bsl;
   if(!Swings(sh1, sh2, bsh, sl1, sl2, bsl)) return 0;
   if(sh1 > sh2 && sl1 > sl2) return 1;
   if(sh1 < sh2 && sl1 < sl2) return -1;
   return 0;
  }

// EMA stack: 1 = price EMA200 ke upar aur 21 > 34 > 50, -1 = ulta, full = 50 vs 200 bhi
int EmaStack(int a, int b, int c, int d, ENUM_TIMEFRAMES tf, bool full)
  {
   double e1 = Buf(a, 0, 1), e2 = Buf(b, 0, 1), e3 = Buf(c, 0, 1), e4 = Buf(d, 0, 1), cl = iClose(_Symbol, tf, 1);
   if(e1 == EMPTY_VALUE || e2 == EMPTY_VALUE || e3 == EMPTY_VALUE || e4 == EMPTY_VALUE || cl <= 0) return 0;
   if(cl > e4 && e1 > e2 && e2 > e3 && (!full || e3 > e4)) return 1;
   if(cl < e4 && e1 < e2 && e2 < e3 && (!full || e3 < e4)) return -1;
   return 0;
  }

int Trend()
  {
   int st = StructTrend(), em = EmaStack(hE1, hE2, hE3, hE4, PERIOD_H1, false);
   return (st != 0 && st == em) ? st : 0;
  }

// Setup chalu rakhne ke liye: structure ulta nahi hua aur price EMA200 ki sahi taraf
bool TrendHolds(int d)
  {
   double e4 = Buf(hE4, 0, 1), c1 = iClose(_Symbol, PERIOD_H1, 1);
   if(e4 == EMPTY_VALUE) return false;
   return StructTrend() != -d && (d == 1 ? c1 > e4 : c1 < e4);
  }

bool StrongTrend(int dir)
  {
   return EmaStack(hE1, hE2, hE3, hE4, PERIOD_H1, true) == dir && EmaStack(h4E1, h4E2, h4E3, h4E4, PERIOD_H4, false) == dir;
  }

//==================== FIBONACCI ====================
double FibOf(int d, double L, double H, double f) { double R = H - L; return d == 1 ? H - f * R : L + f * R; }
double Fib(double f) { return FibOf(S.dir, S.L, S.H, f); }

double CalcTP(int d, double entry)
  {
   double R = S.H - S.L;
   double ext = StrongTrend(d) ? InpTPExtStrong : InpTPExt;
   double fibTP = d == 1 ? S.H + (ext - 1.0) * R : S.L - (ext - 1.0) * R;
   double minTP = entry + d * InpTPMinUSD;
   return SmartTP(d, entry, d == 1 ? MathMax(fibTP, minTP) : MathMin(fibTP, minTP));
  }

void AddLv(double &lv[], int &n, double p) { if(p <= 0) return; ArrayResize(lv, n + 1); lv[n] = p; n++; }

// Volume profile ka POC (sabse zyada trading wala price), heatmap range ke M15 candles se
double POCPrice(int hours)
  {
   int vb = (int)MathMin(iBarShift(_Symbol, PERIOD_M15, TimeCurrent() - hours * 3600), 3000);
   if(vb <= 5) return 0;
   int ih = iHighest(_Symbol, PERIOD_M15, MODE_HIGH, vb, 1), il = iLowest(_Symbol, PERIOD_M15, MODE_LOW, vb, 1);
   if(ih < 0 || il < 0) return 0;
   double hi = iHigh(_Symbol, PERIOD_M15, ih), lo = iLow(_Symbol, PERIOD_M15, il);
   int bins = InpVPBins > 2 ? InpVPBins : 40;
   if(hi <= lo) return 0;
   double step = (hi - lo) / bins, vol[];
   ArrayResize(vol, bins); ArrayInitialize(vol, 0);
   for(int s = 1; s <= vb; s++)
     {
      double tp = (iHigh(_Symbol, PERIOD_M15, s) + iLow(_Symbol, PERIOD_M15, s) + iClose(_Symbol, PERIOD_M15, s)) / 3.0;
      int k = (int)MathFloor((tp - lo) / step);
      k = k < 0 ? 0 : (k > bins - 1 ? bins - 1 : k);
      vol[k] += (double)iVolume(_Symbol, PERIOD_M15, s);
     }
   int mk = ArrayMaximum(vol);
   return lo + (mk + 0.5) * step;
  }

// Trade ki direction me aage padi mazboot liquidity: equal highs/lows (sweep nahi hui), bade levels, POC
int LiquidityTargets(int dir, double entry, double &lv[])
  {
   int n = 0;
   double sp[]; int ns = 0;
   for(int s = 3; s < 200; s++)
     {
      if(dir == 1 && IsSwingHigh(PERIOD_H1, s, 2))
        {
         double p = iHigh(_Symbol, PERIOD_H1, s);
         int ih = iHighest(_Symbol, PERIOD_H1, MODE_HIGH, s - 1, 1);
         if(p > entry && ih >= 0 && iHigh(_Symbol, PERIOD_H1, ih) <= p) { ArrayResize(sp, ns + 1); sp[ns] = p; ns++; }
        }
      if(dir == -1 && IsSwingLow(PERIOD_H1, s, 2))
        {
         double p = iLow(_Symbol, PERIOD_H1, s);
         int il = iLowest(_Symbol, PERIOD_H1, MODE_LOW, s - 1, 1);
         if(p < entry && il >= 0 && iLow(_Symbol, PERIOD_H1, il) >= p) { ArrayResize(sp, ns + 1); sp[ns] = p; ns++; }
        }
     }
   for(int i = 0; i < ns; i++)
      for(int j = i + 1; j < ns; j++)
         if(MathAbs(sp[i] - sp[j]) <= InpEqualTolUSD) AddLv(lv, n, dir == 1 ? MathMin(sp[i], sp[j]) : MathMax(sp[i], sp[j]));
   ENUM_TIMEFRAMES tfs[6] = {PERIOD_D1, PERIOD_W1, PERIOD_MN1, PERIOD_MN1, PERIOD_MN1, PERIOD_MN1};
   int cnt[6] = {1, 1, 1, 3, 6, 12};
   for(int t = 0; t < 6; t++)
     {
      if(iBars(_Symbol, tfs[t]) < cnt[t] + 2) continue;
      double h = iHigh(_Symbol, tfs[t], 1), l = iLow(_Symbol, tfs[t], 1);
      for(int s = 2; s <= cnt[t]; s++) { h = MathMax(h, iHigh(_Symbol, tfs[t], s)); l = MathMin(l, iLow(_Symbol, tfs[t], s)); }
      if(dir == 1 && h > entry) AddLv(lv, n, h);
      if(dir == -1 && l < entry) AddLv(lv, n, l);
     }
   double poc = POCPrice(RangeHours());
   if((dir == 1 && poc > entry) || (dir == -1 && poc < entry && poc > 0)) AddLv(lv, n, poc);
   return n;
  }

// Fib TP se pehle koi mazboot liquidity ho to TP usse $0.50 pehle (lekin entry se $15 se kam nahi)
double SmartTP(int dir, double entry, double tp0)
  {
   if(!InpSmartTP) return tp0;
   double minTP = entry + dir * InpTPMinUSD, best = tp0;
   double lv[];
   int n = LiquidityTargets(dir, entry, lv);
   for(int i = 0; i < n; i++)
     {
      double t = lv[i] - dir * InpTPLiqBufUSD;
      if(dir == 1 && t >= minTP && t < best) best = t;
      if(dir == -1 && t <= minTP && t > best) best = t;
     }
   if(MathAbs(best - tp0) > _Point) PrintFormat("Smart TP: raaste me liquidity, TP %.2f (Fib wala %.2f)", best, tp0);
   return best;
  }

void NewSetup(int d, double L, double H, double atr)
  {
   double R = H - L;
   if(R < InpMinLegATR * atr || R > InpMaxLegATR * atr)
     {
      PrintFormat("BOS %s mila par leg $%.2f (ATR $%.2f) range ke bahar, skip", d == 1 ? "UP" : "DOWN", R, atr);
      return;
     }
   ResetSetup();
   S.act = true; S.dir = d; S.L = L; S.H = H; S.bosTime = iTime(_Symbol, PERIOD_H1, 1);
   PrintFormat("SETUP %s: BOS, leg L %.2f  H %.2f  (R $%.2f) | zone %.2f - %.2f | 0.786 %.2f",
               d == 1 ? "BUY" : "SELL", L, H, R, Fib(InpZoneTop), Fib(InpZoneBottom), Fib(InpInvalidFib));
   SaveState();
  }

// H1 BOS: trend ki direction me pichhle swing ke paar pehla close
void DetectBOS(int t)
  {
   if(t == 0) return;
   double sh1, sh2, sl1, sl2; int bsh, bsl;
   if(!Swings(sh1, sh2, bsh, sl1, sl2, bsl)) return;
   double atr = Buf(hATR, 0, 1);
   if(atr == EMPTY_VALUE || atr <= 0) return;
   double c1 = iClose(_Symbol, PERIOD_H1, 1), c2 = iClose(_Symbol, PERIOD_H1, 2);
   if(t == 1 && c1 > sh1 && c2 <= sh1)
     {
      double L = iLow(_Symbol, PERIOD_H1, 1);
      for(int s = 1; s < bsh; s++) L = MathMin(L, iLow(_Symbol, PERIOD_H1, s));
      NewSetup(1, L, iHigh(_Symbol, PERIOD_H1, 1), atr);
     }
   else if(t == -1 && c1 < sl1 && c2 >= sl1)
     {
      double H = iHigh(_Symbol, PERIOD_H1, 1);
      for(int s = 1; s < bsl; s++) H = MathMax(H, iHigh(_Symbol, PERIOD_H1, s));
      NewSetup(-1, iLow(_Symbol, PERIOD_H1, 1), H, atr);
     }
  }

// Har naye H1 candle par leg update / setup khatam (entry se pehle tak)
void UpdateSetup()
  {
   if(!S.act || S.entered) return;
   int d = S.dir;
   double h1 = iHigh(_Symbol, PERIOD_H1, 1), l1 = iLow(_Symbol, PERIOD_H1, 1), c1 = iClose(_Symbol, PERIOD_H1, 1);
   if(!TrendHolds(d)) { Deactivate("trend ulta / EMA200 ke paar close"); return; }
   if((d == 1 && c1 < S.L) || (d == -1 && c1 > S.H)) { Deactivate("structure toota (1.0 ke paar close)"); return; }
   int bars = iBarShift(_Symbol, PERIOD_H1, S.bosTime);
   if(bars > InpSetupMaxBars) { Deactivate("entry ka time khatam"); return; }
   if(S.touched)
     {
      S.extreme = d == 1 ? MathMin(S.extreme, l1) : MathMax(S.extreme, h1);
      if((d == 1 && h1 > S.H) || (d == -1 && l1 < S.L))   // bina entry naya high/low = naya leg
        {
         if(d == 1) { S.L = S.extreme; S.H = h1; } else { S.H = S.extreme; S.L = l1; }
         S.touched = false; S.bosTime = iTime(_Symbol, PERIOD_H1, 1);
         PrintFormat("Naya leg: L %.2f  H %.2f", S.L, S.H);
        }
     }
   else
     {
      if(d == 1 && h1 > S.H) S.H = h1;
      if(d == -1 && l1 < S.L) S.L = l1;
     }
   SaveState();
  }

//==================== CONFLUENCE (11 points) ====================
bool InZ(double p, double zLo, double zHi) { return p > 0 && p >= zLo - InpConfTolUSD && p <= zHi + InpConfTolUSD; }

// TF ke pichhle 'cnt' candles ka High / Low / Open / Close
bool HLOCInZone(ENUM_TIMEFRAMES tf, int cnt, double zLo, double zHi)
  {
   if(iBars(_Symbol, tf) < cnt + 2) return false;
   double h = iHigh(_Symbol, tf, 1), l = iLow(_Symbol, tf, 1);
   for(int s = 2; s <= cnt; s++) { h = MathMax(h, iHigh(_Symbol, tf, s)); l = MathMin(l, iLow(_Symbol, tf, s)); }
   double o = iOpen(_Symbol, tf, cnt), c = iClose(_Symbol, tf, 1);
   return InZ(h, zLo, zHi) || InZ(l, zLo, zHi) || InZ(o, zLo, zHi) || InZ(c, zLo, zHi);
  }

// TF ke bade leg (lookback ka high-low) ke 0.5 / 0.618 / 0.786 level
bool FibTFInZone(ENUM_TIMEFRAMES tf, int lookback, double zLo, double zHi)
  {
   int bars = iBars(_Symbol, tf);
   if(bars < 10) return false;
   lookback = (int)MathMin(lookback, bars - 2);
   int ih = iHighest(_Symbol, tf, MODE_HIGH, lookback, 1), il = iLowest(_Symbol, tf, MODE_LOW, lookback, 1);
   if(ih < 0 || il < 0) return false;
   double hi = iHigh(_Symbol, tf, ih), lo = iLow(_Symbol, tf, il), R = hi - lo;
   if(R <= 0) return false;
   double f[3] = {0.5, 0.618, 0.786};
   for(int i = 0; i < 3; i++)
     {
      double lv = ih < il ? hi - f[i] * R : lo + f[i] * R;   // naya high = up leg, warna down leg
      if(InZ(lv, zLo, zHi)) return true;
     }
   return false;
  }

bool SwingLevelInZone(double zLo, double zHi)
  {
   for(int s = 5; s < 150; s++)
     {
      if(IsSwingHigh(PERIOD_H1, s, 2) && InZ(iHigh(_Symbol, PERIOD_H1, s), zLo, zHi)) return true;
      if(IsSwingLow(PERIOD_H1, s, 2) && InZ(iLow(_Symbol, PERIOD_H1, s), zLo, zHi)) return true;
     }
   return false;
  }

// Price aur oscillator ka divergence: abhi ka pullback (candle 1-3) vs pichhla swing (5-60)
bool Divergence(int d, int h, int buf)
  {
   if(d == 1)
     {
      int cs = iLowest(_Symbol, PERIOD_H1, MODE_LOW, 3, 1);
      if(cs < 0) return false;
      double cl = iLow(_Symbol, PERIOD_H1, cs), cr = Buf(h, buf, cs);
      for(int s = 5; s <= 60; s++)
         if(IsSwingLow(PERIOD_H1, s, 2))
           {
            double pl = iLow(_Symbol, PERIOD_H1, s), pr = Buf(h, buf, s);
            if(cr == EMPTY_VALUE || pr == EMPTY_VALUE) return false;
            return (cl < pl && cr > pr) || (cl > pl && cr < pr);   // regular ya hidden bullish
           }
     }
   else
     {
      int cs = iHighest(_Symbol, PERIOD_H1, MODE_HIGH, 3, 1);
      if(cs < 0) return false;
      double ch = iHigh(_Symbol, PERIOD_H1, cs), cr = Buf(h, buf, cs);
      for(int s = 5; s <= 60; s++)
         if(IsSwingHigh(PERIOD_H1, s, 2))
           {
            double ph = iHigh(_Symbol, PERIOD_H1, s), pr = Buf(h, buf, s);
            if(cr == EMPTY_VALUE || pr == EMPTY_VALUE) return false;
            return (ch > ph && cr < pr) || (ch < ph && cr > pr);   // regular ya hidden bearish
           }
     }
   return false;
  }

bool RSIZone(int d)
  {
   double r1 = Buf(hRSI, 0, 1), r2 = Buf(hRSI, 0, 2), r3 = Buf(hRSI, 0, 3);
   if(r1 == EMPTY_VALUE || r2 == EMPTY_VALUE || r3 == EMPTY_VALUE) return false;
   if(d == 1) { double m = MathMin(r1, MathMin(r2, r3)); return m >= InpRSIBuyLo && m <= InpRSIBuyHi; }
   double x = MathMax(r1, MathMax(r2, r3));
   return x >= InpRSISellLo && x <= InpRSISellHi;
  }

// StochRSI (RSI 14, stoch 14, smooth 3, D 3): oversold se upar cross (BUY), overbought se neeche (SELL)
bool StochRSICross(int d)
  {
   int K = InpStochKPeriod, sm = InpStochSmooth, D = InpStochD;
   int need = K + sm + D + 6;
   double r[];
   ArraySetAsSeries(r, true);
   if(CopyBuffer(hRSI14, 0, 1, need, r) != need) return false;   // r[0] = candle 1
   int nraw = need - K + 1;
   double raw[]; ArrayResize(raw, nraw);
   for(int i = 0; i < nraw; i++)
     {
      double hi = r[i], lo = r[i];
      for(int j = 1; j < K; j++) { hi = MathMax(hi, r[i + j]); lo = MathMin(lo, r[i + j]); }
      raw[i] = hi > lo ? (r[i] - lo) / (hi - lo) * 100.0 : 50.0;
     }
   int nk = nraw - sm + 1;
   double kv[]; ArrayResize(kv, nk);
   for(int i = 0; i < nk; i++) { double s = 0; for(int j = 0; j < sm; j++) s += raw[i + j]; kv[i] = s / sm; }
   int ndv = nk - D + 1;
   if(ndv < 4) return false;
   double dv[]; ArrayResize(dv, ndv);
   for(int i = 0; i < ndv; i++) { double s = 0; for(int j = 0; j < D; j++) s += kv[i + j]; dv[i] = s / D; }
   if(d == 1)
     {
      bool cross = (kv[0] > dv[0] && kv[1] <= dv[1]) || (kv[1] > dv[1] && kv[2] <= dv[2]);
      return cross && MathMin(MathMin(kv[0], kv[1]), MathMin(kv[2], kv[3])) < InpStochOS;
     }
   bool crs = (kv[0] < dv[0] && kv[1] >= dv[1]) || (kv[1] < dv[1] && kv[2] >= dv[2]);
   return crs && MathMax(MathMax(kv[0], kv[1]), MathMax(kv[2], kv[3])) > InpStochOB;
  }

bool VolumeSpike()
  {
   double v1 = (double)iVolume(_Symbol, PERIOD_H1, 1), s = 0;
   if(v1 <= 0) return false;
   for(int i = 2; i < 2 + InpVolAvgBars; i++) s += (double)iVolume(_Symbol, PERIOD_H1, i);
   double avg = s / InpVolAvgBars;
   return avg > 0 && v1 >= InpVolMult * avg;
  }

// Confirmation candle ne liquidity (pichhla H1 swing / pichhle din ka low-high) li aur wapas close hui
// 0 = sweep nahi, 1 = swing / PDL-PDH sweep, 2 = equal lows/highs (M15) ka sweep
int LiquiditySweep(int d)
  {
   double l1 = iLow(_Symbol, PERIOD_H1, 1), h1 = iHigh(_Symbol, PERIOD_H1, 1), c1 = iClose(_Symbol, PERIOD_H1, 1);
   //--- equal lows / highs (M15, pichhle ~24 ghante): sabse zyada stop-loss yahin
   double ep[]; int ne = 0;
   for(int s = 5; s < 100; s++)
     {
      if(d == 1 && IsSwingLow(PERIOD_M15, s, 2))   { ArrayResize(ep, ne + 1); ep[ne] = iLow(_Symbol, PERIOD_M15, s);  ne++; }
      if(d == -1 && IsSwingHigh(PERIOD_M15, s, 2)) { ArrayResize(ep, ne + 1); ep[ne] = iHigh(_Symbol, PERIOD_M15, s); ne++; }
     }
   for(int i = 0; i < ne; i++)
      for(int j = i + 1; j < ne; j++)
         if(MathAbs(ep[i] - ep[j]) <= InpEqualTolUSD)
           {
            double lv = d == 1 ? MathMin(ep[i], ep[j]) : MathMax(ep[i], ep[j]);
            if(d == 1 && l1 < lv && c1 > lv) return 2;
            if(d == -1 && h1 > lv && c1 < lv) return 2;
           }
   if(d == 1)
     {
      double pdl = iLow(_Symbol, PERIOD_D1, 1);
      if(pdl > 0 && l1 < pdl && c1 > pdl) return 1;
      for(int s = 3; s < 100; s++)
         if(IsSwingLow(PERIOD_H1, s, 2)) { double p = iLow(_Symbol, PERIOD_H1, s); if(l1 < p && c1 > p) return 1; }
     }
   else
     {
      double pdh = iHigh(_Symbol, PERIOD_D1, 1);
      if(pdh > 0 && h1 > pdh && c1 < pdh) return 1;
      for(int s = 3; s < 100; s++)
         if(IsSwingHigh(PERIOD_H1, s, 2)) { double p = iHigh(_Symbol, PERIOD_H1, s); if(h1 > p && c1 < p) return 1; }
     }
   return 0;
  }

// FVG (H1 ya M15) jo golden zone ke saath overlap kare
bool FVGInZone(int d, double zLo, double zHi)
  {
   ENUM_TIMEFRAMES tfs[2] = {PERIOD_H1, PERIOD_M15};
   int lk[2] = {60, 96};
   for(int t = 0; t < 2; t++)
      for(int i = 1; i < lk[t] - 2; i++)
        {
         double lo0 = iLow(_Symbol, tfs[t], i), hi0 = iHigh(_Symbol, tfs[t], i);
         double hi2 = iHigh(_Symbol, tfs[t], i + 2), lo2 = iLow(_Symbol, tfs[t], i + 2);
         if(d == 1 && lo0 > hi2 && lo0 >= zLo - InpConfTolUSD && hi2 <= zHi + InpConfTolUSD) return true;
         if(d == -1 && hi0 < lo2 && lo2 >= zLo - InpConfTolUSD && hi0 <= zHi + InpConfTolUSD) return true;
        }
   return false;
  }

bool MACDTurn(int d)
  {
   double h[5];
   for(int i = 1; i <= 4; i++)
     {
      double m = Buf(hMACD, 0, i), s = Buf(hMACD, 1, i);
      if(m == EMPTY_VALUE || s == EMPTY_VALUE) return false;
      h[i] = m - s;
     }
   if(d == 1) return (h[1] > h[2] && h[2] <= h[3]) || (h[1] > h[2] && h[2] > h[3] && h[3] <= h[4]) || Divergence(1, hMACD, 0);
   return (h[1] < h[2] && h[2] >= h[3]) || (h[1] < h[2] && h[2] < h[3] && h[3] >= h[4]) || Divergence(-1, hMACD, 0);
  }

int Score(int d, double z1, double z2, string &why)
  {
   double zLo = MathMin(z1, z2), zHi = MathMax(z1, z2);
   int sc = 0; why = "";
   if(InpUseH4 && (FibTFInZone(PERIOD_H4, 60, zLo, zHi) || HLOCInZone(PERIOD_H4, 1, zLo, zHi) || SwingLevelInZone(zLo, zHi)))
     { sc++; why += "H4 "; }
   if(InpUseD3D && (FibTFInZone(PERIOD_D1, 30, zLo, zHi) || FibTFInZone(PERIOD_D1, 60, zLo, zHi) ||
                    HLOCInZone(PERIOD_D1, 1, zLo, zHi) || HLOCInZone(PERIOD_D1, 3, zLo, zHi)))
     { sc++; why += "D/3D "; }
   if(InpUseWBig && (FibTFInZone(PERIOD_W1, 26, zLo, zHi) || HLOCInZone(PERIOD_W1, 1, zLo, zHi) || HLOCInZone(PERIOD_MN1, 1, zLo, zHi) ||
                     HLOCInZone(PERIOD_MN1, 3, zLo, zHi) || HLOCInZone(PERIOD_MN1, 6, zLo, zHi) || HLOCInZone(PERIOD_MN1, 12, zLo, zHi)))
     { sc++; why += "W/big "; }
   if(InpUseEMAConf)
     {
      bool e = InZ(Buf(hE1, 0, 1), zLo, zHi) || InZ(Buf(hE2, 0, 1), zLo, zHi) || InZ(Buf(hE3, 0, 1), zLo, zHi) ||
               InZ(Buf(hE4, 0, 1), zLo, zHi) || EmaStack(h4E1, h4E2, h4E3, h4E4, PERIOD_H4, false) == d;
      if(e) { sc++; why += "EMA "; }
     }
   if(InpUseRSIDiv && Divergence(d, hRSI, 0)) { sc++; why += "RSIdiv "; }
   if(InpUseRSIZone && RSIZone(d))            { sc++; why += "RSIz "; }
   if(InpUseStochRSI && StochRSICross(d))     { sc++; why += "StRSI "; }
   if(InpUseVolume && VolumeSpike())          { sc++; why += "Vol "; }
   if(InpUseSweep)
     {
      int sw = LiquiditySweep(d);
      if(sw > 0) { sc++; why += sw == 2 ? "Sweep(EQ) " : "Sweep "; }
     }
   if(InpUseMACD && MACDTurn(d))              { sc++; why += "MACD "; }
   if(InpUseFVG && FVGInZone(d, zLo, zHi))    { sc++; why += "FVG "; }
   return sc;
  }

int GradeIdx(int sc) { return sc >= InpGradeAPlusPlus ? 2 : (sc >= InpGradeAPlus ? 1 : 0); }
string GradeName(int sc) { int g = GradeIdx(sc); return g == 2 ? "A++" : (g == 1 ? "A+" : "A"); }
string MinGradeName() { return rtMinGrade == 2 ? "A++" : (rtMinGrade == 1 ? "A+" : "A"); }

//==================== ENTRY ====================
bool OpenMain(int d, string cmt)
  {
   double px = d == 1 ? Ask() : Bid();
   double sl = d == 1 ? S.L - InpSLBufferUSD : S.H + InpSLBufferUSD;
   double tp = CalcTP(d, px);
   double lot = CalcLot(MathAbs(px - sl));
   if(GradeIdx(S.score) == 2 && InpAPPMult > 1.0) lot = NormLot(lot * InpAPPMult);
   if(!SendOrder(d, lot, sl, tp, cmt)) return false;
   S.entered = true; S.sl = sl; S.tp = tp; S.reArmed = false;
   SaveState();
   return true;
  }

// H1 candle close par: zone chhui, 0.786 ke paar close nahi, 0.618 ke aage close, bullish/pin bar
void CheckEntry()
  {
   if(!S.act || S.entered || MB.n > 0) return;
   int d = S.dir;
   double o1 = iOpen(_Symbol, PERIOD_H1, 1), h1 = iHigh(_Symbol, PERIOD_H1, 1), l1 = iLow(_Symbol, PERIOD_H1, 1), c1 = iClose(_Symbol, PERIOD_H1, 1);
   double z05 = Fib(InpZoneTop), z07 = Fib(InpZoneBottom), zc = Fib(InpConfirmFib), zi = Fib(InpInvalidFib);
   bool touch = d == 1 ? l1 <= z05 : h1 >= z05;
   if(!touch) { entryWhy = StringFormat("%s setup: pullback ka intezaar (zone %.2f - %.2f)", d == 1 ? "BUY" : "SELL", z05, z07); return; }
   if(!S.touched) { S.touched = true; S.extreme = d == 1 ? l1 : h1; }
   bool notBroken = d == 1 ? c1 > zi : c1 < zi;
   if(!notBroken) { Deactivate("entry se pehle H1 close 0.786 ke paar (setup fail)"); entryWhy = "setup fail: 0.786 ke paar close"; return; }
   if(!TrendHolds(d)) { entryWhy = "zone me, lekin trend kamzor (EMA200 / structure)"; return; }
   bool closeOK = d == 1 ? c1 >= zc : c1 <= zc;
   double body = MathAbs(c1 - o1);
   double lw = MathMin(o1, c1) - l1, uw = h1 - MathMax(o1, c1);
   bool candleOK = d == 1 ? (c1 > o1 || lw >= 2.0 * body) : (c1 < o1 || uw >= 2.0 * body);
   if(!closeOK || !candleOK)
     {
      entryWhy = StringFormat("zone me, H1 confirmation nahi (close %.2f, chahiye %s %.2f)", c1, d == 1 ? ">=" : "<=", zc);
      return;
     }
   string why;
   int sc = Score(d, z05, z07, why);
   S.score = sc; S.grade = GradeName(sc); S.why = why;
   PrintFormat("SIGNAL %s %s %d/%d: %s", d == 1 ? "BUY" : "SELL", S.grade, sc, MAXPTS, why);
   if(GradeIdx(sc) < rtMinGrade) { entryWhy = StringFormat("%s %d/%d min grade %s se kam, skip", S.grade, sc, MAXPTS, MinGradeName()); return; }
   string block;
   if(!AllowNew(block)) { entryWhy = StringFormat("%s %d/%d mila, ruka: %s", S.grade, sc, MAXPTS, block); return; }
   if(OpenMain(d, StringFormat("SFE E %s%d", S.grade, sc))) entryWhy = StringFormat("%s ENTRY %s %d/%d", d == 1 ? "BUY" : "SELL", S.grade, sc, MAXPTS);
   else entryWhy = "order fail (Experts tab dekho)";
  }

// Breakeven ke baad M15 close confirmation par re-entry (setup valid ho)
void CheckReEntry()
  {
   if(!InpReEntry || !S.act || !S.reArmed || MB.n > 0) return;
   int d = S.dir;
   if(S.reent >= InpReEntryMax) { S.reArmed = false; return; }
   double zi = Fib(InpInvalidFib), bid = Bid(), ask = Ask();
   if(d == 1 ? bid <= zi : ask >= zi) { entryWhy = "re-entry: price 0.786 ke paar, setup band"; if(HB.n == 0) Deactivate("0.786 ke paar"); else S.reArmed = false; return; }
   if(S.tp > 0 && ((d == 1 && bid >= S.tp) || (d == -1 && ask <= S.tp))) { Deactivate("price TP tak pahunch gaya"); return; }
   if(!TrendHolds(d)) { entryWhy = "re-entry: trend match nahi"; return; }
   double o1 = iOpen(_Symbol, InpReEntryTF, 1), c1 = iClose(_Symbol, InpReEntryTF, 1);
   double h2 = iHigh(_Symbol, InpReEntryTF, 2), l2 = iLow(_Symbol, InpReEntryTF, 2);
   bool conf = d == 1 ? (c1 > o1 && c1 > h2) : (c1 < o1 && c1 < l2);
   if(!conf) { entryWhy = "re-entry: M15 confirmation ka intezaar"; return; }
   string block;
   if(!AllowNew(block)) { entryWhy = "re-entry ruka: " + block; return; }
   if(OpenMain(d, StringFormat("SFE R %s%d", S.grade, S.score)))
     {
      S.reent++;
      entryWhy = StringFormat("RE-ENTRY %d/%d", S.reent, InpReEntryMax);
      SaveState();
     }
  }

// Fakeout: H1 close 0.786 ke paar -> hedge (fixed lot). Hedge bachav hai, din ki limits nahi lagti
void CheckHedge()
  {
   if(!InpHedge || !S.act || !S.entered || S.hedgeDone || MB.n == 0 || HB.n > 0 || !rtOn) return;
   int d = S.dir;
   double c1 = iClose(_Symbol, PERIOD_H1, 1), zi = Fib(InpInvalidFib);
   if(!(d == 1 ? c1 < zi : c1 > zi)) return;
   if(Spread() > InpMaxSpreadUSD) return;
   int hd = -d;
   double px = hd == 1 ? Ask() : Bid();
   double sl = Fib(InpZoneTop) + d * InpHedgeSLBufUSD;
   double R = S.H - S.L;
   double fibTP = d == 1 ? S.L - (InpHedgeExt - 1.0) * R : S.H + (InpHedgeExt - 1.0) * R;
   double minTP = px + hd * InpTPMinUSD;
   double tp = SmartTP(hd, px, hd == -1 ? MathMin(fibTP, minTP) : MathMax(fibTP, minTP));
   double lot = CalcLot(MathAbs(px - sl));
   PrintFormat("FAKEOUT: H1 close %.2f, 0.786 (%.2f) ke paar -> HEDGE", c1, zi);
   if(SendOrder(hd, lot, sl, tp, "SFE HG")) { S.hedgeDone = true; SaveState(); }
  }

//==================== MANAGEMENT (har tick) ====================
void ManageBE(Basket &b, int kind)
  {
   if(b.n == 0) return;
   int d = b.dir;
   double avg = Avg(b), bid = Bid(), ask = Ask(), sm = StopsMin();
   if(!(d == 1 ? bid >= avg + InpBETriggerUSD : ask <= avg - InpBETriggerUSD)) return;
   double nsl = NP(avg + d * InpBELockUSD);
   if(d == 1 ? bid - nsl < sm : nsl - ask < sm) return;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || KindOf() != kind) continue;
      double cur = PositionGetDouble(POSITION_SL), tp = PositionGetDouble(POSITION_TP);
      bool better = d == 1 ? (cur < nsl - _Point) : (cur == 0 || cur > nsl + _Point);
      if(better && trade.PositionModify(t, nsl, tp))
         PrintFormat("%s BREAKEVEN: SL %.2f (average %.2f + $%.2f)", KindName(kind), nsl, avg, InpBELockUSD);
     }
  }

// DCA: aakhri (sabse kharab) position se $5 ulta, max 3, turant. Main me 0.786 ke paar nahi
string KindName(int kind)
  {
   string n[6] = {"MAIN", "HEDGE", "MANUAL BUY", "MANUAL SELL", "MANUAL-BUY HEDGE", "MANUAL-SELL HEDGE"};
   return kind >= 0 && kind < 6 ? n[kind] : "?";
  }

void ManageDCA(Basket &b, int kind)
  {
   if(!InpDCA || !rtOn || b.n == 0 || b.n - 1 >= InpDCAMax) return;
   bool manual = kind == K_MANB || kind == K_MANS || kind == K_MHB || kind == K_MHS;
   if(manual && !InpManualDCA) return;
   if(!InpHedgeDCA && (kind == K_HEDGE || kind == K_MHB || kind == K_MHS)) return;   // hedge me DCA nahi
   int d = b.dir;
   double bid = Bid(), ask = Ask();
   if(!(d == 1 ? ask <= b.worst - InpDCAStepUSD : bid >= b.worst + InpDCAStepUSD)) return;
   double zi = 0;
   if(kind == K_MAIN && S.act && S.dir == d) zi = Fib(InpInvalidFib);
   if(kind == K_MANB && MC[0].act) zi = FibOf(1, MC[0].L, MC[0].H, InpInvalidFib);
   if(kind == K_MANS && MC[1].act) zi = FibOf(-1, MC[1].L, MC[1].H, InpInvalidFib);
   if(zi > 0 && (d == 1 ? bid <= zi : ask >= zi)) return;      // 0.786 ke paar DCA nahi
   if(Spread() > InpMaxSpreadUSD) return;
   double lot = b.firstLot > 0 ? NormLot(b.firstLot) : NormLot(rtLot);
   string pre = kind == K_HEDGE ? "SFE HD" : (kind == K_MAIN ? "SFE D" : (kind == K_MHB ? "SFE MHB" : (kind == K_MHS ? "SFE MHS" : "SFE MD")));
   SendOrder(d, lot, b.sl, b.tp, pre + IntegerToString(b.n));
  }

//==================== MANUAL TRADES (isi strategy se) ====================
// Manual trade ka Fib leg: EA ka setup same direction me ho to wahi, warna pichhla H1 swing
bool ManualLeg(int d, double entry, double &L, double &H)
  {
   if(S.act && S.dir == d) { L = S.L; H = S.H; return true; }
   int maxS = (int)MathMin(InpSwingLookback, iBars(_Symbol, PERIOD_H1) - InpSwingBars - 2);
   for(int s = InpSwingBars + 1; s < maxS; s++)
     {
      if(d == 1 && IsSwingLow(PERIOD_H1, s, InpSwingBars) && iLow(_Symbol, PERIOD_H1, s) < entry)
        {
         L = iLow(_Symbol, PERIOD_H1, s);
         int ih = iHighest(_Symbol, PERIOD_H1, MODE_HIGH, s, 0);
         H = MathMax(ih >= 0 ? iHigh(_Symbol, PERIOD_H1, ih) : entry, entry);
         return H > L;
        }
      if(d == -1 && IsSwingHigh(PERIOD_H1, s, InpSwingBars) && iHigh(_Symbol, PERIOD_H1, s) > entry)
        {
         H = iHigh(_Symbol, PERIOD_H1, s);
         int il = iLowest(_Symbol, PERIOD_H1, MODE_LOW, s, 0);
         L = MathMin(il >= 0 ? iLow(_Symbol, PERIOD_H1, il) : entry, entry);
         return H > L;
        }
     }
   return false;
  }

// Manual basket: leg, Fib SL/TP (agar nahi), breakeven, DCA, hedge, group close
void ManageManual(int k, bool newH1)
  {
   if(!InpManageManual) return;
   int d = k == 0 ? 1 : -1, kind = k == 0 ? K_MANB : K_MANS, hkind = k == 0 ? K_MHB : K_MHS;
   if(MMB[k].n == 0)
     {
      if(MC[k].act && MHB[k].n == 0) { MC[k].act = false; MC[k].hedgeDone = false; SaveState(); }
      ManageBE(MHB[k], hkind);
      ManageDCA(MHB[k], hkind);
      return;
     }
   if(!MC[k].act)
     {
      double L = 0, H = 0;
      if(!ManualLeg(d, Avg(MMB[k]), L, H)) return;
      MC[k].act = true; MC[k].L = L; MC[k].H = H; MC[k].hedgeDone = false;
      PrintFormat("MANUAL %s mila: Fib leg L %.2f  H %.2f | 0.786 %.2f", d == 1 ? "BUY" : "SELL", L, H, FibOf(d, L, H, InpInvalidFib));
      SaveState();
     }
   //--- group close: manual + uska hedge total profit me
   if(InpGroupClose && MHB[k].n > 0 && MMB[k].profit + MHB[k].profit >= InpGroupCloseUSD)
     {
      PrintFormat("MANUAL GROUP CLOSE: %+.2f + hedge %+.2f", MMB[k].profit, MHB[k].profit);
      CloseKind(hkind); CloseKind(kind);
      MC[k].act = false; MC[k].hedgeDone = false; SaveState();
      return;
     }
   //--- Fib SL / TP (manual ka apna ho to waisa hi)
   double sl = NP(d == 1 ? MC[k].L - InpSLBufferUSD : MC[k].H + InpSLBufferUSD);
   double bid = Bid(), ask = Ask(), sm = StopsMin();
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || KindOf() != kind) continue;
      double cs = PositionGetDouble(POSITION_SL), ct = PositionGetDouble(POSITION_TP), op = PositionGetDouble(POSITION_PRICE_OPEN);
      double nsl = cs, ntp = ct;
      bool needTP = ct == 0 || (!InpKeepManualSLTP && newH1);   // TP sirf zarurat par (har tick nahi)
      if(needTP)
        {
         double R = MC[k].H - MC[k].L, ext = StrongTrend(d) ? InpTPExtStrong : InpTPExt;
         double fibTP = d == 1 ? MC[k].H + (ext - 1.0) * R : MC[k].L - (ext - 1.0) * R, minTP = op + d * InpTPMinUSD;
         ntp = NP(SmartTP(d, op, d == 1 ? MathMax(fibTP, minTP) : MathMin(fibTP, minTP)));
        }
      bool slWorse = cs > 0 && (d == 1 ? cs < sl : cs > sl);
      if(cs == 0 || (!InpKeepManualSLTP && slWorse)) nsl = sl;
      if(nsl > 0 && (d == 1 ? bid - nsl < sm : nsl - ask < sm)) nsl = cs;
      if(ntp > 0 && (d == 1 ? ntp - ask < sm : bid - ntp < sm)) ntp = ct;
      if(MathAbs(nsl - cs) > _Point || MathAbs(ntp - ct) > _Point)
         if(trade.PositionModify(t, nsl, ntp)) PrintFormat("MANUAL %s #%I64u: SL %.2f  TP %.2f (Fib)", d == 1 ? "BUY" : "SELL", t, nsl, ntp);
     }
   ManageBE(MMB[k], kind);
   ManageBE(MHB[k], hkind);
   ManageDCA(MMB[k], kind);
   ManageDCA(MHB[k], hkind);
   //--- fakeout hedge (H1 close 0.786 ke paar), manual lot
   if(newH1 && InpManualHedge && rtOn && !MC[k].hedgeDone && MHB[k].n == 0)
     {
      double c1 = iClose(_Symbol, PERIOD_H1, 1), zi = FibOf(d, MC[k].L, MC[k].H, InpInvalidFib);
      if((d == 1 ? c1 < zi : c1 > zi) && Spread() <= InpMaxSpreadUSD)
        {
         int hd = -d;
         double px = hd == 1 ? Ask() : Bid();
         double hsl = FibOf(d, MC[k].L, MC[k].H, InpZoneTop) + d * InpHedgeSLBufUSD;
         double R = MC[k].H - MC[k].L;
         double fibTP = d == 1 ? MC[k].L - (InpHedgeExt - 1.0) * R : MC[k].H + (InpHedgeExt - 1.0) * R, minTP = px + hd * InpTPMinUSD;
         double htp = SmartTP(hd, px, hd == -1 ? MathMin(fibTP, minTP) : MathMax(fibTP, minTP));
         PrintFormat("MANUAL FAKEOUT: H1 close %.2f, 0.786 (%.2f) ke paar -> HEDGE", c1, zi);
         if(SendOrder(hd, NormLot(MMB[k].firstLot), hsl, htp, k == 0 ? "SFE MHB" : "SFE MHS")) { MC[k].hedgeDone = true; SaveState(); }
        }
     }
  }

// Main basket ki aakhri closing deal: 1 = TP / profit, 2 = breakeven (SL profit me), 3 = loss
int MainExitType(int d)
  {
   if(!HistorySelect(TimeCurrent() - 7 * 86400, TimeCurrent() + 3600)) return 0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
     {
      ulong dl = HistoryDealGetTicket(i);
      if(dl == 0 || HistoryDealGetString(dl, DEAL_SYMBOL) != _Symbol || HistoryDealGetInteger(dl, DEAL_MAGIC) != InpMagic) continue;
      long en = HistoryDealGetInteger(dl, DEAL_ENTRY);
      if(en != DEAL_ENTRY_OUT && en != DEAL_ENTRY_OUT_BY) continue;
      int posDir = HistoryDealGetInteger(dl, DEAL_TYPE) == DEAL_TYPE_SELL ? 1 : -1;   // SELL deal = BUY position band
      if(posDir != d) continue;                                                       // hedge ulti direction ka hai
      double pl = HistoryDealGetDouble(dl, DEAL_PROFIT) + HistoryDealGetDouble(dl, DEAL_SWAP) + HistoryDealGetDouble(dl, DEAL_COMMISSION);
      long rs = HistoryDealGetInteger(dl, DEAL_REASON);
      if(rs == DEAL_REASON_TP) return 1;
      if(rs == DEAL_REASON_SL) return pl >= 0 ? 2 : 3;
      return pl >= 0 ? 1 : 3;
     }
   return 0;
  }

// Main basket band hua: TP / loss = setup khatam, breakeven = re-entry ka mauka
void HandleBasketClose()
  {
   if(S.act && S.entered && prevMainN > 0 && MB.n == 0)
     {
      int ex = MainExitType(S.dir);
      if(ex == 2 && InpReEntry && S.reent < InpReEntryMax)
        {
         S.reArmed = true;
         entryWhy = "breakeven par band, re-entry ka intezaar (M15)";
         PrintFormat("Main basket breakeven par band. Re-entry ON (%d/%d)", S.reent, InpReEntryMax);
         SaveState();
        }
      else if(HB.n == 0) Deactivate(ex == 1 ? "TP / profit me band" : (ex == 3 ? "SL laga" : "basket band"));
     }
   if(S.act && S.entered && !S.reArmed && MB.n == 0 && HB.n == 0 && prevMainN == 0) Deactivate("saari positions band");
   prevMainN = MB.n;
  }

//==================== MAIN ====================
void OnTick()
  {
   CheckNewDay();
   ReadBaskets();

   //--- equity stop
   if(InpEquityStopPct > 0 && dayStartEq > 0 && !dayStopped &&
      AccountInfoDouble(ACCOUNT_EQUITY) <= dayStartEq * (1.0 - InpEquityStopPct / 100.0))
     {
      CloseAll(StringFormat("equity stop %.1f%%", InpEquityStopPct));
      dayStopped = true; stopWhy = "equity stop (aaj band)";
      SaveState();
      return;
     }
   //--- daily SL par sab band (option)
   double lim = DailyLimit();
   if(InpDailyCloseAll && lim > 0 && !dayStopped && plToday <= -lim && (MB.n > 0 || HB.n > 0))
     {
      CloseAll("daily SL limit");
      dayStopped = true; stopWhy = "daily SL limit (aaj band)";
      SaveState();
      return;
     }
   //--- main + hedge total profit me = sab band
   if(InpGroupClose && MB.n > 0 && HB.n > 0 && MB.profit + HB.profit >= InpGroupCloseUSD)
     {
      PrintFormat("GROUP CLOSE: main %+.2f + hedge %+.2f", MB.profit, HB.profit);
      CloseAll("main + hedge profit me");
      if(S.act) Deactivate("main + hedge group close");
      return;
     }

   ManageBE(MB, K_MAIN);
   ManageBE(HB, K_HEDGE);
   ManageDCA(MB, K_MAIN);
   ManageDCA(HB, K_HEDGE);
   HandleBasketClose();

   //--- har naye H1 candle par: hedge check, entry, leg update, naya BOS
   datetime h1t = iTime(_Symbol, PERIOD_H1, 0);
   bool newH1 = h1t != lastH1 && h1t > 0;
   ManageManual(0, newH1);
   ManageManual(1, newH1);
   if(newH1)
     {
      lastH1 = h1t;
      curTrend = Trend();
      CheckHedge();
      if(S.act)
        {
         CheckEntry();
         UpdateSetup();
        }
      if(!S.act && MB.n == 0 && HB.n == 0)
        {
         entryWhy = curTrend == 0 ? "trend side-ways: koi trade nahi" : StringFormat("trend %s: BOS ka intezaar", curTrend == 1 ? "UP (sirf BUY)" : "DOWN (sirf SELL)");
         DetectBOS(curTrend);
        }
     }

   //--- har naye M15 candle par: re-entry, heatmap
   datetime m15t = iTime(_Symbol, InpReEntryTF, 0);
   if(m15t != lastM15 && m15t > 0)
     {
      lastM15 = m15t;
      CheckReEntry();
      if(rtHMOn) DrawHeatmap();
     }
  }

//==================== TRADE EVENTS: journal, lagatar loss, exit ka kaaran ====================
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0) return;
   ulong dl = trans.deal;
   if(!HistoryDealSelect(dl)) return;
   if(HistoryDealGetString(dl, DEAL_SYMBOL) != _Symbol || HistoryDealGetInteger(dl, DEAL_MAGIC) != InpMagic) return;
   long entry = HistoryDealGetInteger(dl, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) return;
   double pl = HistoryDealGetDouble(dl, DEAL_PROFIT) + HistoryDealGetDouble(dl, DEAL_SWAP) + HistoryDealGetDouble(dl, DEAL_COMMISSION);
   long reason = HistoryDealGetInteger(dl, DEAL_REASON);
   long dtype = HistoryDealGetInteger(dl, DEAL_TYPE);
   double cpx = HistoryDealGetDouble(dl, DEAL_PRICE), vol = HistoryDealGetDouble(dl, DEAL_VOLUME);
   datetime ctm = (datetime)HistoryDealGetInteger(dl, DEAL_TIME);
   long pid = HistoryDealGetInteger(dl, DEAL_POSITION_ID);
   int posDir = dtype == DEAL_TYPE_SELL ? 1 : -1;   // SELL deal = BUY position band hui

   // open wali deal: comment, price, time
   string ocmt = ""; double opx = 0; datetime otm = 0;
   if(HistorySelectByPosition(pid))
      for(int i = 0; i < HistoryDealsTotal(); i++)
        {
         ulong d2 = HistoryDealGetTicket(i);
         if(d2 > 0 && HistoryDealGetInteger(d2, DEAL_ENTRY) == DEAL_ENTRY_IN)
           { ocmt = HistoryDealGetString(d2, DEAL_COMMENT); opx = HistoryDealGetDouble(d2, DEAL_PRICE); otm = (datetime)HistoryDealGetInteger(d2, DEAL_TIME); break; }
        }
   string rs = reason == DEAL_REASON_TP ? "TP" : (reason == DEAL_REASON_SL ? (pl >= 0 ? "BE/SL+" : "SL") : (pl >= 0 ? "close+" : "close-"));

   if(IsEntryCmt(ocmt))
     {
      consecLoss = pl < 0 ? consecLoss + 1 : 0;
      if(InpMaxConsecLoss > 0 && consecLoss >= InpMaxConsecLoss) PrintFormat("Lagatar %d loss: aaj nayi entry band", consecLoss);
      SaveState();
     }

   if(InpJournal)
     {
      int fh = FileOpen(InpJournalFile, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE, ',');
      if(fh != INVALID_HANDLE)
        {
         if(FileSize(fh) == 0)
            FileWrite(fh, "close_time", "open_time", "position", "dir", "kind", "comment", "lot", "open", "close", "profit", "reason", "balance");
         FileSeek(fh, 0, SEEK_END);
         string kind = StringFind(ocmt, "SFE E") == 0 ? "ENTRY" : (StringFind(ocmt, "SFE R") == 0 ? "REENTRY" :
                       (StringFind(ocmt, "SFE HG") == 0 ? "HEDGE" : (StringFind(ocmt, "SFE HD") == 0 ? "HEDGE_DCA" : "DCA")));
         FileWrite(fh, TimeToString(ctm, TIME_DATE | TIME_SECONDS), TimeToString(otm, TIME_DATE | TIME_SECONDS), (string)pid,
                   posDir == 1 ? "BUY" : "SELL", kind, ocmt, DoubleToString(vol, 2), DoubleToString(opx, _Digits),
                   DoubleToString(cpx, _Digits), DoubleToString(pl, 2), rs, DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
         FileClose(fh);
        }
     }
   PrintFormat("CLOSE %s %s %.2f lot  %+.2f  (%s)", posDir == 1 ? "BUY" : "SELL", ocmt, vol, pl, rs);
  }

//==================== LIQUIDITY HEATMAP ====================
int HMIdx() { return rtHM < 0 ? 0 : (rtHM > 5 ? 5 : rtHM); }
int RangeHours() { int h[6] = {12, 24, 72, 168, 720, 720}; return h[HMIdx()]; }
string RangeName() { string n[6] = {"12H", "1D", "3D", "1W", "1M", "ALL"}; return n[HMIdx()]; }

void HmRect(string id, datetime t1, double p1, datetime t2, double p2, color c)
  {
   string n = HMP + id;
   if(!ObjectCreate(0, n, OBJ_RECTANGLE, 0, t1, p1, t2, p2)) return;
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetInteger(0, n, OBJPROP_FILL, true);
   ObjectSetInteger(0, n, OBJPROP_BACK, true);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
  }
void HmLine(string id, datetime t1, datetime t2, double p, color c, int style, string label)
  {
   string n = HMP + id;
   if(!ObjectCreate(0, n, OBJ_TREND, 0, t1, p, t2, p)) return;
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetInteger(0, n, OBJPROP_STYLE, style);
   ObjectSetInteger(0, n, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, n, OBJPROP_BACK, true);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
   string tn = n + "_t";
   if(ObjectCreate(0, tn, OBJ_TEXT, 0, t2, p))
     {
      ObjectSetString(0, tn, OBJPROP_TEXT, label);
      ObjectSetInteger(0, tn, OBJPROP_COLOR, c);
      ObjectSetInteger(0, tn, OBJPROP_FONTSIZE, 7);
      ObjectSetInteger(0, tn, OBJPROP_ANCHOR, ANCHOR_LEFT);
      ObjectSetInteger(0, tn, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, tn, OBJPROP_HIDDEN, true);
     }
  }

void DrawLevel(string id, ENUM_TIMEFRAMES tf, int cnt, datetime from, datetime to, color c, string nm)
  {
   if(iBars(_Symbol, tf) < cnt + 2) return;
   double h = iHigh(_Symbol, tf, 1), l = iLow(_Symbol, tf, 1);
   for(int s = 2; s <= cnt; s++) { h = MathMax(h, iHigh(_Symbol, tf, s)); l = MathMin(l, iLow(_Symbol, tf, s)); }
   double o = iOpen(_Symbol, tf, cnt), cl = iClose(_Symbol, tf, 1);
   HmLine(id + "H", from, to, h, c, STYLE_SOLID, nm + " H");
   HmLine(id + "L", from, to, l, c, STYLE_SOLID, nm + " L");
   HmLine(id + "O", from, to, o, c, STYLE_DOT, nm + " O");
   HmLine(id + "C", from, to, cl, c, STYLE_DOT, nm + " C");
  }

void DrawHeatmap()
  {
   ObjectsDeleteAll(0, HMP);
   if(!rtHMOn) { ChartRedraw(); return; }
   int hours = RangeHours();
   datetime now = TimeCurrent(), from = now - hours * 3600;
   datetime right = now + PeriodSeconds(PERIOD_CURRENT) * 15;
   ENUM_TIMEFRAMES tf = hours <= 12 ? PERIOD_M15 : PERIOD_H1;
   int bars = iBarShift(_Symbol, tf, from);
   if(bars < 0) bars = iBars(_Symbol, tf) - 5;
   bars = (int)MathMin(bars, 2000);
   int n = InpSwingBars;
   double band = MathMax(InpEqualTolUSD * 0.4, 10 * _Point);

   //--- swing highs / lows: equal = gehra rang, sweep ho chuka = dhundhla
   double hp[], lp[]; datetime ht[], lt[]; int nh = 0, nl = 0;
   for(int s = n + 1; s < bars; s++)
     {
      if(IsSwingHigh(tf, s, n)) { ArrayResize(hp, nh + 1); ArrayResize(ht, nh + 1); hp[nh] = iHigh(_Symbol, tf, s); ht[nh] = iTime(_Symbol, tf, s); nh++; }
      if(IsSwingLow(tf, s, n))  { ArrayResize(lp, nl + 1); ArrayResize(lt, nl + 1); lp[nl] = iLow(_Symbol, tf, s);  lt[nl] = iTime(_Symbol, tf, s); nl++; }
     }
   for(int i = 0; i < nh; i++)
     {
      int eq = 0;
      for(int j = 0; j < nh; j++) if(j != i && MathAbs(hp[j] - hp[i]) <= InpEqualTolUSD) eq++;
      int sh = iBarShift(_Symbol, tf, ht[i]);
      bool swept = sh > 1 && iHighest(_Symbol, tf, MODE_HIGH, sh - 1, 1) >= 0 && iHigh(_Symbol, tf, iHighest(_Symbol, tf, MODE_HIGH, sh - 1, 1)) > hp[i];
      color c = swept ? C'70,70,80' : (eq >= 2 ? C'255,40,40' : (eq == 1 ? C'200,50,50' : C'130,45,45'));
      HmRect("sh" + IntegerToString(i), ht[i], hp[i] + band, right, hp[i] - band, c);
     }
   for(int i = 0; i < nl; i++)
     {
      int eq = 0;
      for(int j = 0; j < nl; j++) if(j != i && MathAbs(lp[j] - lp[i]) <= InpEqualTolUSD) eq++;
      int sh = iBarShift(_Symbol, tf, lt[i]);
      bool swept = sh > 1 && iLowest(_Symbol, tf, MODE_LOW, sh - 1, 1) >= 0 && iLow(_Symbol, tf, iLowest(_Symbol, tf, MODE_LOW, sh - 1, 1)) < lp[i];
      color c = swept ? C'70,70,80' : (eq >= 2 ? C'40,230,90' : (eq == 1 ? C'45,180,80' : C'40,120,60'));
      HmRect("sl" + IntegerToString(i), lt[i], lp[i] + band, right, lp[i] - band, c);
     }

   //--- FVG (bhara nahi gaya)
   if(InpShowFVG)
      for(int i = 1; i < bars - 2; i++)
        {
         double hi2 = iHigh(_Symbol, tf, i + 2), lo2 = iLow(_Symbol, tf, i + 2), lo0 = iLow(_Symbol, tf, i), hi0 = iHigh(_Symbol, tf, i);
         datetime t = iTime(_Symbol, tf, i + 1);
         if(lo0 > hi2)   // bullish FVG
           {
            bool filled = i > 1 && iLow(_Symbol, tf, iLowest(_Symbol, tf, MODE_LOW, i - 1, 1)) <= hi2;
            if(!filled) HmRect("fb" + IntegerToString(i), t, lo0, right, hi2, C'40,70,150');
           }
         if(hi0 < lo2)   // bearish FVG
           {
            bool filled = i > 1 && iHigh(_Symbol, tf, iHighest(_Symbol, tf, MODE_HIGH, i - 1, 1)) >= lo2;
            if(!filled) HmRect("fs" + IntegerToString(i), t, lo2, right, hi0, C'110,50,140');
           }
        }

   //--- bade levels (pichhla H / L / O / C)
   if(InpShowLevels)
     {
      DrawLevel("H4", PERIOD_H4, 1, from, right, C'120,120,120', "H4");
      DrawLevel("D1", PERIOD_D1, 1, from, right, C'200,200,90', "D");
      DrawLevel("D3", PERIOD_D1, 3, from, right, C'210,180,60', "3D");
      DrawLevel("W1", PERIOD_W1, 1, from, right, C'240,150,40', "W");
      DrawLevel("M1", PERIOD_MN1, 1, from, right, C'250,120,30', "1M");
      if(rtHM == HM_ALL || rtHM == HM_1M)
        {
         DrawLevel("M3", PERIOD_MN1, 3, from, right, C'255,90,20', "3M");
         DrawLevel("M6", PERIOD_MN1, 6, from, right, C'255,60,60', "6M");
         DrawLevel("Y1", PERIOD_MN1, 12, from, right, C'255,40,140', "Y");
        }
     }

   //--- volume profile (M15 tick volume) chart ke right side
   if(InpShowVP && InpVPBins > 2)
     {
      int vb = (int)MathMin(iBarShift(_Symbol, PERIOD_M15, from), 3000);
      if(vb > 5)
        {
         int ih = iHighest(_Symbol, PERIOD_M15, MODE_HIGH, vb, 1), il = iLowest(_Symbol, PERIOD_M15, MODE_LOW, vb, 1);
         double hi = iHigh(_Symbol, PERIOD_M15, ih), lo = iLow(_Symbol, PERIOD_M15, il);
         if(hi > lo)
           {
            double step = (hi - lo) / InpVPBins, vol[];
            ArrayResize(vol, InpVPBins); ArrayInitialize(vol, 0);
            for(int s = 1; s <= vb; s++)
              {
               double tp = (iHigh(_Symbol, PERIOD_M15, s) + iLow(_Symbol, PERIOD_M15, s) + iClose(_Symbol, PERIOD_M15, s)) / 3.0;
               int k = (int)MathFloor((tp - lo) / step);
               k = k < 0 ? 0 : (k > InpVPBins - 1 ? InpVPBins - 1 : k);
               vol[k] += (double)iVolume(_Symbol, PERIOD_M15, s);
              }
            double mx = vol[ArrayMaximum(vol)];
            int psec = PeriodSeconds(PERIOD_CURRENT);
            for(int k = 0; k < InpVPBins && mx > 0; k++)
              {
               int w = (int)MathRound(vol[k] / mx * 25.0);
               if(w < 1) continue;
               datetime t1 = right + psec * 2, t2 = t1 + psec * w;
               color c = vol[k] >= mx ? C'240,200,40' : C'80,90,110';
               HmRect("vp" + IntegerToString(k), t1, lo + k * step, t2, lo + (k + 1) * step - step * 0.1, c);
              }
           }
        }
     }
   ChartRedraw();
  }

//==================== PANEL ====================
color cBg = C'18,20,32', cCard = C'28,31,48', cLn = C'48,52,78', cTx = C'225,228,240', cDm = C'140,146,175';
color cB = C'38,196,133', cS = C'239,83,80', cW = C'255,183,77';
datetime lastDraw = 0;

void Rc(string id, int x, int y, int w, int h, color bg)
  {
   string n = PFX + id;
   if(ObjectFind(0, n) < 0) { ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0); ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
                              ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false); ObjectSetInteger(0, n, OBJPROP_HIDDEN, true); }
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, InpPanelX + x); ObjectSetInteger(0, n, OBJPROP_YDISTANCE, InpPanelY + y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, w); ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, bg); ObjectSetInteger(0, n, OBJPROP_COLOR, cLn);
  }
void Tx(string id, int x, int y, string t, color c, int sz = 8, bool b = false)
  {
   string n = PFX + id;
   if(ObjectFind(0, n) < 0) { ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0); ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false); ObjectSetInteger(0, n, OBJPROP_HIDDEN, true); }
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, InpPanelX + x); ObjectSetInteger(0, n, OBJPROP_YDISTANCE, InpPanelY + y);
   ObjectSetString(0, n, OBJPROP_TEXT, t); ObjectSetString(0, n, OBJPROP_FONT, b ? "Segoe UI Semibold" : "Segoe UI");
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, sz); ObjectSetInteger(0, n, OBJPROP_COLOR, c);
  }
void Bt(string id, int x, int y, int w, int h, string t, color bg, color fg)
  {
   string n = PFX + "btn_" + id;
   if(ObjectFind(0, n) < 0) { ObjectCreate(0, n, OBJ_BUTTON, 0, 0, 0); ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false); ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
                              ObjectSetString(0, n, OBJPROP_FONT, "Segoe UI Semibold"); ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 8); }
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, InpPanelX + x); ObjectSetInteger(0, n, OBJPROP_YDISTANCE, InpPanelY + y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, w); ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
   ObjectSetString(0, n, OBJPROP_TEXT, t); ObjectSetInteger(0, n, OBJPROP_BGCOLOR, bg); ObjectSetInteger(0, n, OBJPROP_COLOR, fg);
   ObjectSetInteger(0, n, OBJPROP_STATE, false);
  }

void Panel()
  {
   if(!InpPanel || (MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE))) return;
   if(TimeLocal() == lastDraw) return;
   lastDraw = TimeLocal();
   int W = 380, y = 6;
   Rc("bg", 0, 0, W, 100, cBg);
   Tx("ti", 10, y, "GOLD SMC FIB EA  v1.01", cTx, 10, true);
   Tx("on", W - 70, y + 2, rtOn ? "RUNNING" : "OFF", rtOn ? cB : cS, 8, true);
   y += 20;
   int h4 = EmaStack(h4E1, h4E2, h4E3, h4E4, PERIOD_H4, false);
   Tx("st", 10, y, StringFormat("Trend H1: %s | H4: %s | Spread $%.2f%s", curTrend == 1 ? "UP" : (curTrend == -1 ? "DOWN" : "SIDE"),
      h4 == 1 ? "UP" : (h4 == -1 ? "DOWN" : "SIDE"), Spread(), newsNow ? " | NEWS" : ""), cDm);
   y += 16;
   string su = !S.act ? "Setup: koi nahi" :
               StringFormat("Setup %s: L %.2f  H %.2f | zone %.2f-%.2f | 0.786 %.2f", S.dir == 1 ? "BUY" : "SELL", S.L, S.H,
                            Fib(InpZoneTop), Fib(InpZoneBottom), Fib(InpInvalidFib));
   Tx("su", 10, y, su, S.act ? cW : cDm);
   y += 16;
   Tx("gr", 10, y, S.score > 0 || S.act ? StringFormat("Grade: %s %d/%d  %s", S.grade, S.score, MAXPTS, S.why) : "Grade: -", cTx);
   y += 16;
   Tx("ew", 10, y, "Entry: " + entryWhy, StringFind(entryWhy, "ENTRY") >= 0 ? cB : cDm);
   y += 20;
   Rc("cm", 6, y, W - 12, 20, cCard);
   Tx("mb", 12, y + 3, MB.n > 0 ? StringFormat("MAIN %s %d pos | %.2f lot | avg %.2f | P/L %+.2f", MB.dir == 1 ? "BUY" : "SELL", MB.n, MB.lots, Avg(MB), MB.profit)
                              : "MAIN: koi position nahi", MB.n > 0 ? (MB.profit >= 0 ? cB : cS) : cDm, 8, true);
   y += 22;
   Rc("ch", 6, y, W - 12, 20, cCard);
   Tx("hb", 12, y + 3, HB.n > 0 ? StringFormat("HEDGE %s %d pos | %.2f lot | P/L %+.2f", HB.dir == 1 ? "BUY" : "SELL", HB.n, HB.lots, HB.profit)
                              : "HEDGE: nahi", HB.n > 0 ? cW : cDm, 8, true);
   y += 22;
   string mt = "MANUAL: koi trade nahi";
   if(MMB[0].n + MMB[1].n + MHB[0].n + MHB[1].n > 0)
      mt = StringFormat("MANUAL  BUY %d pos %+.2f%s | SELL %d pos %+.2f%s", MMB[0].n, MMB[0].profit, MHB[0].n > 0 ? " +hedge" : "",
                        MMB[1].n, MMB[1].profit, MHB[1].n > 0 ? " +hedge" : "");
   Rc("cmn", 6, y, W - 12, 20, cCard);
   Tx("mn", 12, y + 3, InpManageManual ? mt : "MANUAL: manage OFF", MMB[0].n + MMB[1].n > 0 ? cTx : cDm, 8, true);
   y += 24;
   double lim = DailyLimit();
   string stt;
   bool allow = AllowNew(stt);
   Tx("dy", 10, y, StringFormat("Aaj: %d/%d trade | P/L %+.2f | Daily SL %s | %s", tradesToday, InpMaxTradesDay, plToday,
      lim > 0 ? StringFormat("-$%.0f", lim) : "off", allow ? "ACTIVE" : "STOP: " + stt), allow ? cTx : cS);
   y += 16;
   double wr = stTotal > 0 ? 100.0 * stWins / stTotal : 0;
   Tx("s1", 10, y, StringFormat("Stats: %d trade | Win %.0f%% | A+ %d (%.0f%%) | A++ %d (%.0f%%)", stTotal, wr,
      stAP, stAP > 0 ? 100.0 * stAPW / stAP : 0, stAPP, stAPP > 0 ? 100.0 * stAPPW / stAPP : 0), cDm);
   y += 16;
   Tx("s2", 10, y, StringFormat("Avg jeet %+.2f | Avg haar %+.2f | Re-entry %d/%d | Lagatar loss %d",
      stNW > 0 ? stSumW / stNW : 0, stNL > 0 ? stSumL / stNL : 0, S.reent, InpReEntryMax, consecLoss), cDm);
   y += 20;
   int bw = (W - 12 - 8) / 3;
   Bt("on", 6, y, bw, 22, rtOn ? "EA: ON" : "EA: OFF", rtOn ? cB : cLn, rtOn ? cBg : cTx);
   Bt("ca", 6 + bw + 4, y, bw, 22, "CLOSE ALL", cS, clrWhite);
   Bt("hmon", 6 + 2 * (bw + 4), y, bw, 22, rtHMOn ? "HEATMAP: ON" : "HEATMAP: OFF", rtHMOn ? cB : cLn, rtHMOn ? cBg : cTx);
   y += 26;
   Rc("r1", 6, y, W - 12, 24, cCard);
   Bt("gm", 10, y + 2, 28, 20, "-", cLn, cTx);
   Tx("gl", 44, y + 5, "Min grade " + MinGradeName(), cTx, 9, true);
   Bt("gp", 150, y + 2, 28, 20, "+", cLn, cTx);
   Bt("lm", 196, y + 2, 28, 20, "-", cLn, cTx);
   Tx("ll", 230, y + 5, InpLotMode == LOT_FIXED ? StringFormat("Lot %.2f", rtLot) : StringFormat("Risk %.1f%%", InpRiskPct), cTx, 9, true);
   Bt("lp", W - 42, y + 2, 28, 20, "+", cLn, cTx);
   y += 28;
   int hw = (W - 12 - 5 * 3) / 6;
   string hn[6] = {"12H", "1D", "3D", "1W", "1M", "ALL"};
   for(int i = 0; i < 6; i++)
      Bt("hm" + IntegerToString(i), 6 + i * (hw + 3), y, hw, 20, hn[i], rtHM == i ? cW : cLn, rtHM == i ? cBg : cTx);
   y += 24;
   ObjectSetInteger(0, PFX + "bg", OBJPROP_YSIZE, y + 4);
   ChartRedraw();
  }

void OnChartEvent(const int id, const long &l, const double &d, const string &sp)
  {
   if(id != CHARTEVENT_OBJECT_CLICK || StringFind(sp, PFX + "btn_") != 0) return;
   ObjectSetInteger(0, sp, OBJPROP_STATE, false);
   string b = StringSubstr(sp, StringLen(PFX + "btn_"));
   if(b == "on") rtOn = !rtOn;
   else if(b == "ca")
     {
      if(MQLInfoInteger(MQL_TESTER) || MessageBox("EA ki saari positions band karein?", "Gold SMC Fib EA", MB_YESNO | MB_ICONWARNING) == IDYES)
        { CloseAll("CLOSE ALL button"); if(S.act) Deactivate("CLOSE ALL button"); }
     }
   else if(b == "hmon") { rtHMOn = !rtHMOn; DrawHeatmap(); }
   else if(b == "gm") rtMinGrade = rtMinGrade > 0 ? rtMinGrade - 1 : 0;
   else if(b == "gp") rtMinGrade = rtMinGrade < 2 ? rtMinGrade + 1 : 2;
   else if(b == "lm") rtLot = MathMax(VolMin(), NormalizeDouble(rtLot - 0.01, 2));
   else if(b == "lp") rtLot = MathMin(InpMaxLot, NormalizeDouble(rtLot + 0.01, 2));
   else if(StringFind(b, "hm") == 0 && StringLen(b) == 3)
     {
      rtHM = (int)StringToInteger(StringSubstr(b, 2, 1));
      rtHMOn = true;
      DrawHeatmap();
     }
   lastDraw = 0;
   Panel();
  }
//+------------------------------------------------------------------+
