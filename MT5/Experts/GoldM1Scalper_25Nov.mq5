//+------------------------------------------------------------------+
//|                                        GoldM1Scalper_25Nov.mq5   |
//|  XAUUSD M1 scalper  v2.00  (25 Nov 2026)                         |
//+------------------------------------------------------------------+
//  KYA KARTA HAI
//  1. Trend sirf H1 candle close par (price action): HH + HL = UP, LH + LL = DOWN,
//     warna SIDE. H1 close pichhle swing high ke upar = UP (BOS), swing low ke neeche = DOWN.
//  2. Fibonacci (main): H1 leg (BUY: swing low -> high, SELL: swing high -> low).
//     Levels 0 / 0.382 / 0.5 / 0.618 / 0.65 / 0.786 / 1 / 1.27 chart par. Entry zone 0.5 - 0.65.
//  3. Support / resistance: H4, D, 3D, W, 1M, 3M, 6M, Y ki pichhli candle ka Open / High / Low / Close.
//  4. Liquidity sweep: M1 wick in levels / H1 swing / equal highs-lows ke paar, close wapas andar.
//  5. Entry M1 candle close par. H1 UP = BUY, DOWN = SELL, SIDE = dono (sirf sweep).
//     - Fib: M1 close 0.5 - 0.65 zone me, candle trend ki taraf
//     - Sweep: trend ki taraf (SIDE me dono)
//     - TP ke raaste me (InpRoomUSD ke andar) ulta level = entry nahi
//     - High sweep ke baad 15 min BUY nahi, low sweep ke baad SELL nahi
//     - M1 close Fib 1.0 ke paar = leg khatam (naye BOS / trend tak Fib entry nahi)
//  6. Har trade TP +$1. Side +$1.5 chale to SL average + $0.50.
//  7. DCA: side ki sabse kharab position se $10 ulta, pehle trade ke lot se, unlimited.
//  8. Koi hedge / lock / SL nahi. Margin guard option (default 0 = off).
//  9. Pair close + net close: sirf total profit me.
// 10. Liquidity heatmap: swing highs/lows (equal = gehra rang), FVG, levels, volume profile.
//+------------------------------------------------------------------+
#property copyright "GoldM1Scalper"
#property version   "2.00"

#include <Trade/Trade.mqh>

#define  TITLE    "GOLD M1 SCALPER  25 NOV"
#define  CMT      "GMS"
#define  PFX      "GMS_"
#define  HMP      "GMS_HM_"
#define  FBP      "GMS_FB_"
#define  TP_STEP  0.1
#define  DCA_STEP 1.0

enum ENUM_HMRANGE { HM_12H = 0, HM_1D = 1, HM_3D = 2, HM_1W = 3, HM_1M = 4, HM_ALL = 5 };

input group "=== Lot ==="
input bool            InpAutoLot        = false;       // Lot capital ke hisaab se (AUTO)
input double          InpBalancePer001  = 1000.0;      // AUTO: har itne $ balance par 0.01 lot
input double          InpLot            = 0.01;        // FIXED lot (entry; DCA pehle trade ke lot se)

input group "=== Trend (H1, sirf candle close par) ==="
input int             InpSwingBars      = 3;           // H1 swing = dono taraf itni candles
input int             InpSwingLookback  = 200;         // Swing dhoondhne ke liye H1 candles
input bool            InpSideBoth       = true;        // H1 SIDE = BUY + SELL dono (sirf sweep entry)

input group "=== Fibonacci (H1 leg) ==="
input double          InpZoneTop        = 0.5;         // Entry zone shuru
input double          InpZoneBottom     = 0.65;        // Entry zone khatam
input double          InpDeepFib        = 0.786;       // Wick yahan tak aur close zone me = deep entry
input double          InpMinLegATR      = 1.0;         // Leg kam se kam itne ATR(H1)
input double          InpMaxLegATR      = 10.0;        // Leg zyada se zyada itne ATR(H1)
input bool            InpShowFib        = true;        // Fib chart par

input group "=== Liquidity sweep / levels ==="
input bool            InpUseSweep       = true;        // Sweep entry ON
input double          InpSweepMinUSD    = 0.30;        // Wick level ke paar kam se kam itna $
input int             InpSweepBlockMin  = 15;          // Ulte sweep ke baad itne min us side entry nahi
input double          InpRoomUSD        = 1.5;         // TP ke raaste me itne $ ke andar ulta level = entry nahi (0 = off)
input double          InpEqualTolUSD    = 0.50;        // Equal highs/lows ki doori ($)

input group "=== Entry (M1 candle close) ==="
input bool            InpAutoOn         = true;        // Auto entry ON
input int             InpMaxEntries     = 5;           // Ek side me max entry trade (DCA alag, unlimited)
input bool            InpSessionOnly    = true;        // Sirf London + New York (GMT 7-21)
input int             InpGMTOffset      = 2;           // Server time = GMT + ?
input double          InpMaxSpreadUSD   = 0.40;        // Max spread ($)

input group "=== Exit ==="
input double          InpTP             = 1.0;         // Har trade ka TP: entry se +$
input double          InpBETrigger      = 1.5;         // Side average se +$ = sab positions ka SL breakeven
input double          InpBELock         = 0.5;         // Breakeven SL = average + $
input bool            InpNetClose       = true;        // BUY + SELL dono khule, sabka total profit me = sab band
input double          InpNetCloseUSD    = 5.0;         // Net kam se kam $

input group "=== DCA (koi brake nahi) ==="
input bool            InpDCA            = true;        // DCA ON
input double          InpDCAStep        = 10.0;        // Sabse kharab position se itna $ ulta = naya trade
input int             InpDCAMax         = 0;           // Ek side me max DCA (0 = unlimited)

input group "=== Pair Close ==="
input bool            InpPairClose      = true;        // Phansa trade + profit wale trades saath band
input double          InpPairMinUSD     = 0.20;        // Sabka total kam se kam +$ (loss me kabhi nahi)
input int             InpPairMinPos     = 3;           // Kam se kam itni positions khuli hon
input int             InpPairMaxWin     = 3;           // 1 loss wale ko max itne profit wale trades se cover

input group "=== News filter ==="
input bool            InpNewsFilter     = true;        // Badi (high impact) news ke aas-paas naya trade / DCA nahi
input int             InpNewsBeforeMin  = 15;          // News se itne min pehle
input int             InpNewsAfterMin   = 15;          // News ke itne min baad tak
input string          InpNewsCurrency   = "USD";       // News currency

input group "=== Protection ==="
input double          InpMinMarginLevel = 0.0;         // Margin level isse kam = naye trade/DCA band (0 = off)
input bool            InpManageManual   = false;       // Manual trades (magic 0) bhi (GoldSMCFibEA chal raha ho to OFF)
input bool            InpKeepManualSLTP = true;        // Manual trade ka apna TP waisa hi rahe
input long            InpMagic          = 2511250;     // Magic

input group "=== Liquidity heatmap ==="
input bool            InpHeatmap        = true;        // Heatmap ON
input ENUM_HMRANGE    InpHMRange        = HM_1D;       // Range: 12H / 1D / 3D / 1W / 1M / ALL
input bool            InpShowFVG        = true;        // FVG box
input bool            InpShowLevels     = true;        // H4 / D / 3D / W / 1M / 3M / 6M / Y levels
input bool            InpShowVP         = true;        // Volume profile
input int             InpVPBins         = 40;          // Volume profile bins

input group "=== Panel ==="
input int             InpPanelX         = 10;
input int             InpPanelY         = 25;

//==================== GLOBALS ====================
CTrade   trade;
int      hATR = INVALID_HANDLE;
datetime lastM1 = 0, lastM15 = 0, lastH1 = 0;
bool     autoOn, rtAuto, rtPair, rtHMOn;
int      rtHM, curTrend = 0;
double   rtTP, rtDCA, rtLot, rtPer;
string   trendWhy = "-", legWhy = "abhi nahi", sigTxt = "-";

struct Leg { bool act; int dir; double L, H, extreme; bool touched; datetime tL, tH, tExt; };
Leg      LG;
struct SideInfo { int n, ent, dca; double lots, avg, worst, profit, firstLot; datetime firstT; bool be; double beSL; };
SideInfo SB, SS;
double   allProfit, buyLotsAll, sellLotsAll;
bool     anyLoss;
bool     newsNow = false;
datetime lastNewsCheck = 0;
datetime lastLowSweep = 0, lastHighSweep = 0;
bool     legPending = true;   // shuruaat ka leg: ATR ready hone par

double   lvP[];  string lvN[];  color lvC[];  int lvS[];  int lvCnt = 0;   // H4 ... Y levels
double   supP[]; int supN = 0;                                          // H1 swing lows + equal lows
double   resP[]; int resN = 0;                                          // H1 swing highs + equal highs

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFillingBySymbol(_Symbol);
   hATR = iATR(_Symbol, PERIOD_H1, 14);
   if(hATR == INVALID_HANDLE) return(INIT_FAILED);
   if(InpTP <= 0 || InpDCAStep <= 0 || InpLot <= 0 || InpZoneBottom <= InpZoneTop || InpDeepFib <= InpZoneBottom)
     {
      Print("Inputs galat: TP / DCA / lot > 0, aur zone 0.5 < 0.65 < 0.786 rakho");
      return(INIT_PARAMETERS_INCORRECT);
     }
   autoOn = InpAutoOn; rtTP = InpTP; rtDCA = InpDCAStep; rtLot = InpLot;
   rtAuto = InpAutoLot; rtPer = InpBalancePer001; rtPair = InpPairClose;
   rtHMOn = InpHeatmap; rtHM = (int)InpHMRange;
   LG.act = false; LG.dir = 0; LG.L = 0; LG.H = 0; LG.extreme = 0; LG.touched = false; LG.tL = 0; LG.tH = 0; LG.tExt = 0;
   SB.be = false; SS.be = false; SB.beSL = 0; SS.beSL = 0; SB.n = 0; SS.n = 0;
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("WARNING: Hedging account chahiye (har trade / DCA alag position).");
   //--- shuruaat: trend, leg, levels
   string why = "";
   curTrend = CalcTrend(why); trendWhy = why;
   lastH1 = iTime(_Symbol, PERIOD_H1, 0);
   lastM15 = iTime(_Symbol, PERIOD_M15, 0);
   lastM1 = iTime(_Symbol, PERIOD_M1, 0);
   BuildLevels();
   BuildLiq();
   ReadAll();
   DrawFib();
   if(rtHMOn) DrawHeatmap();
   PrintFormat("%s: H1 %s (%s)", TITLE, TrendName(curTrend), trendWhy);
   EventSetTimer(1);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int r)
  {
   EventKillTimer();
   IndicatorRelease(hATR);
   ObjectsDeleteAll(0, PFX);
  }

void OnTimer() { UpdateNews(); Panel(); }

//==================== HELPERS ====================
double Bid()     { return SymbolInfoDouble(_Symbol, SYMBOL_BID); }
double Ask()     { return SymbolInfoDouble(_Symbol, SYMBOL_ASK); }
double Spread()  { return Ask() - Bid(); }
double VolMin()  { return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN); }
double NP(double p) { return NormalizeDouble(p, _Digits); }
string DS(double p) { return DoubleToString(p, _Digits); }
string TrendName(int t) { return t == 1 ? "UP" : (t == -1 ? "DOWN" : "SIDE"); }
double Buf(int h, int buf, int shift)
  {
   double a[];
   if(CopyBuffer(h, buf, shift, 1, a) != 1) return EMPTY_VALUE;
   return a[0];
  }
int    Dir() { return PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1; }
double PL()  { return PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP); }

// Purane hedge EA ke HEDGE / LOCK trade (same magic diya ho to bhi) ye EA nahi chhedta
bool OldHedge()
  {
   if(PositionGetInteger(POSITION_MAGIC) != InpMagic) return false;
   string c = PositionGetString(POSITION_COMMENT);
   return StringFind(c, "HEDGE") >= 0 || StringFind(c, "LOCK") >= 0;
  }
bool Mine()
  {
   if(PositionGetString(POSITION_SYMBOL) != _Symbol) return false;
   long mg = PositionGetInteger(POSITION_MAGIC);
   if(mg == InpMagic) return !OldHedge();
   return InpManageManual && mg == 0;
  }
bool IsDCA()
  {
   return PositionGetInteger(POSITION_MAGIC) == InpMagic && StringFind(PositionGetString(POSITION_COMMENT), CMT + " D") == 0;
  }

double NormLot(double lot)
  {
   double mn = VolMin(), mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP); if(st <= 0) st = 0.01;
   lot = MathFloor(lot / st + 1e-9) * st;
   return NormalizeDouble(MathMax(mn, MathMin(lot, mx)), 2);
  }

double CurLot()
  {
   if(!rtAuto) return NormLot(rtLot);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   return NormLot(0.01 * MathFloor(bal / MathMax(1.0, rtPer)));
  }

void ReadSide(int dir, SideInfo &s)
  {
   bool be = s.be; double bsl = s.beSL; int n0 = s.n;
   s.n = 0; s.ent = 0; s.dca = 0; s.lots = 0; s.avg = 0; s.worst = 0; s.profit = 0; s.firstLot = 0; s.firstT = 0;
   double pv = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0 || !Mine() || Dir() != dir) continue;
      double v = PositionGetDouble(POSITION_VOLUME), p = PositionGetDouble(POSITION_PRICE_OPEN);
      datetime ot = (datetime)PositionGetInteger(POSITION_TIME);
      s.n++; s.lots += v; pv += v * p; s.profit += PL();
      if(IsDCA()) s.dca++; else s.ent++;
      if(s.worst == 0 || (dir == 1 && p < s.worst) || (dir == -1 && p > s.worst)) s.worst = p;
      if(s.firstT == 0 || ot < s.firstT) { s.firstT = ot; s.firstLot = v; }
     }
   if(s.lots > 0) s.avg = pv / s.lots;
   s.be = be; s.beSL = bsl;
   if(s.n == 0 || s.n > n0) { s.be = false; s.beSL = 0; }   // nayi position = naya average
  }

void ReadAll()
  {
   ReadSide(1, SB); ReadSide(-1, SS);
   allProfit = 0; buyLotsAll = 0; sellLotsAll = 0; anyLoss = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0 || !Mine()) continue;
      double v = PositionGetDouble(POSITION_VOLUME), p = PL();
      allProfit += p; if(p < 0) anyLoss = true;
      if(Dir() == 1) buyLotsAll += v; else sellLotsAll += v;
     }
  }

bool MarginOK()
  {
   if(InpMinMarginLevel <= 0) return true;
   return AccountInfoDouble(ACCOUNT_MARGIN) <= 0 || AccountInfoDouble(ACCOUNT_MARGIN_LEVEL) >= InpMinMarginLevel;
  }

bool SessionOK()
  {
   if(!InpSessionOnly) return true;
   MqlDateTime g; TimeToStruct(TimeCurrent() - InpGMTOffset * 3600, g);
   return g.hour >= 7 && g.hour < 21;
  }

bool Open(int dir, double lot, string tag)
  {
   double px = dir == 1 ? Ask() : Bid();
   double tp = rtTP > 0 ? NP(px + dir * rtTP) : 0;
   string c = CMT + " " + tag;
   bool ok = dir == 1 ? trade.Buy(lot, _Symbol, 0, 0, tp, c) : trade.Sell(lot, _Symbol, 0, 0, tp, c);
   if(!ok || (trade.ResultRetcode() != TRADE_RETCODE_DONE && trade.ResultRetcode() != TRADE_RETCODE_PLACED))
     {
      PrintFormat("Order fail %s: %d %s", c, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      return false;
     }
   return true;
  }

// dir: 0 = dono, 1 = BUY, -1 = SELL
void CloseWhere(int dir)
  {
   for(int pass = 0; pass < 3; pass++)
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(t == 0 || !Mine()) continue;
         if(dir != 0 && Dir() != dir) continue;
         trade.PositionClose(t);
        }
  }

void CloseTickets(ulong &tk[], int n)
  {
   for(int i = 0; i < n; i++)
      if(PositionSelectByTicket(tk[i])) trade.PositionClose(tk[i]);
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
      if(!CalendarEventById(vals[i].event_id, ev)) continue;
      if(ev.importance == CALENDAR_IMPORTANCE_HIGH) { newsNow = true; break; }
     }
  }

//==================== H1 STRUCTURE / TREND ====================
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

int MaxSwingShift()
  {
   return (int)MathMin(InpSwingLookback, iBars(_Symbol, PERIOD_H1) - InpSwingBars - 2);
  }

// Sabse naye 2 swing high aur 2 swing low (H1)
bool Swings(double &sh1, double &sh2, double &sl1, double &sl2)
  {
   int nH = 0, nL = 0, maxS = MaxSwingShift();
   sh1 = 0; sh2 = 0; sl1 = 0; sl2 = 0;
   for(int s = InpSwingBars + 1; s < maxS && (nH < 2 || nL < 2); s++)
     {
      if(nH < 2 && IsSwingHigh(PERIOD_H1, s, InpSwingBars)) { if(nH == 0) sh1 = iHigh(_Symbol, PERIOD_H1, s); else sh2 = iHigh(_Symbol, PERIOD_H1, s); nH++; }
      if(nL < 2 && IsSwingLow(PERIOD_H1, s, InpSwingBars))  { if(nL == 0) sl1 = iLow(_Symbol, PERIOD_H1, s);  else sl2 = iLow(_Symbol, PERIOD_H1, s);  nL++; }
     }
   return nH == 2 && nL == 2;
  }

// H1 trend, sirf band candle se: BOS pehle, phir HH/HL ya LH/LL
int CalcTrend(string &why)
  {
   double sh1, sh2, sl1, sl2;
   if(!Swings(sh1, sh2, sl1, sl2)) { why = "swing kam"; return 0; }
   double c1 = iClose(_Symbol, PERIOD_H1, 1);
   if(c1 > sh1) { why = "BOS upar"; return 1; }
   if(c1 < sl1) { why = "BOS neeche"; return -1; }
   if(sh1 > sh2 && sl1 > sl2) { why = "HH + HL"; return 1; }
   if(sh1 < sh2 && sl1 < sl2) { why = "LH + LL"; return -1; }
   why = "mila-jula";
   return 0;
  }

//==================== FIBONACCI LEG ====================
double FibOf(int d, double L, double H, double f) { double R = H - L; return d == 1 ? H - f * R : L + f * R; }
double Fib(double f) { return FibOf(LG.dir, LG.L, LG.H, f); }

bool SetLeg(int d, double L, double H, datetime tL, datetime tH, string why)
  {
   double atr = Buf(hATR, 0, 1), R = H - L;
   if(R <= 0 || atr == EMPTY_VALUE || atr <= 0) return false;
   if(R < InpMinLegATR * atr || R > InpMaxLegATR * atr)
     {
      PrintFormat("Fib leg %s $%.2f (ATR $%.2f) range ke bahar, skip", d == 1 ? "BUY" : "SELL", R, atr);
      return false;
     }
   LG.act = true; LG.dir = d; LG.L = L; LG.H = H; LG.tL = tL; LG.tH = tH;
   LG.touched = false; LG.extreme = 0; LG.tExt = 0;
   legWhy = why;
   PrintFormat("FIB LEG %s (%s): L %s  H %s | zone %s - %s | 0.786 %s",
               d == 1 ? "BUY" : "SELL", why, DS(L), DS(H), DS(Fib(InpZoneTop)), DS(Fib(InpZoneBottom)), DS(Fib(InpDeepFib)));
   return true;
  }

// Structure se leg: sabse naya swing (BUY me high) ya uske baad ka extreme = leg ka end,
// usse pehle ka ulta swing (BUY me low) = leg ki shuruaat
void LegFromStructure(int d, string why)
  {
   int n = InpSwingBars, maxS = MaxSwingShift();
   int bs = -1;
   for(int s = n + 1; s < maxS; s++)
      if(d == 1 ? IsSwingHigh(PERIOD_H1, s, n) : IsSwingLow(PERIOD_H1, s, n)) { bs = s; break; }
   if(bs < 0) return;
   int ie = d == 1 ? iHighest(_Symbol, PERIOD_H1, MODE_HIGH, bs, 1) : iLowest(_Symbol, PERIOD_H1, MODE_LOW, bs, 1);
   if(ie < 1) return;
   int bo = -1;
   for(int s = ie + 1; s < maxS; s++)
      if(d == 1 ? IsSwingLow(PERIOD_H1, s, n) : IsSwingHigh(PERIOD_H1, s, n)) { bo = s; break; }
   if(bo < 0) return;
   int io = d == 1 ? iLowest(_Symbol, PERIOD_H1, MODE_LOW, bo - ie + 1, ie) : iHighest(_Symbol, PERIOD_H1, MODE_HIGH, bo - ie + 1, ie);
   if(io < 0) return;
   if(d == 1) SetLeg(1, iLow(_Symbol, PERIOD_H1, io), iHigh(_Symbol, PERIOD_H1, ie), iTime(_Symbol, PERIOD_H1, io), iTime(_Symbol, PERIOD_H1, ie), why);
   else       SetLeg(-1, iLow(_Symbol, PERIOD_H1, ie), iHigh(_Symbol, PERIOD_H1, io), iTime(_Symbol, PERIOD_H1, ie), iTime(_Symbol, PERIOD_H1, io), why);
  }

// Har H1 close par leg aage badhao: zone touch se pehle naya high = leg lamba,
// touch ke baad naya high = naya leg (pullback ka low se)
void UpdateLeg()
  {
   if(!LG.act || LG.dir != curTrend) return;
   int d = LG.dir;
   double h1 = iHigh(_Symbol, PERIOD_H1, 1), l1 = iLow(_Symbol, PERIOD_H1, 1);
   datetime t1 = iTime(_Symbol, PERIOD_H1, 1);
   if(LG.touched)
     {
      if(LG.extreme == 0 || (d == 1 ? l1 < LG.extreme : h1 > LG.extreme)) { LG.extreme = d == 1 ? l1 : h1; LG.tExt = t1; }
      if(d == 1 && h1 > LG.H)  { SetLeg(1, LG.extreme, h1, LG.tExt, t1, "naya high"); return; }
      if(d == -1 && l1 < LG.L) { SetLeg(-1, l1, LG.extreme, t1, LG.tExt, "naya low"); return; }
     }
   else
     {
      if(d == 1 && h1 > LG.H)  { LG.H = h1; LG.tH = t1; }
      if(d == -1 && l1 < LG.L) { LG.L = l1; LG.tL = t1; }
     }
  }

// Naya H1 candle band: trend + leg (sirf yahin trend badalta hai)
void OnNewH1()
  {
   string why = "";
   int t = CalcTrend(why);
   double sh1, sh2, sl1, sl2;
   bool bos = false;
   if(t != 0 && Swings(sh1, sh2, sl1, sl2))
     {
      double c1 = iClose(_Symbol, PERIOD_H1, 1), c2 = iClose(_Symbol, PERIOD_H1, 2);
      bos = (t == 1 && c1 > sh1 && c2 <= sh1) || (t == -1 && c1 < sl1 && c2 >= sl1);
     }
   bool changed = t != curTrend;
   if(changed) PrintFormat("H1 TREND: %s -> %s (%s)", TrendName(curTrend), TrendName(t), why);
   curTrend = t; trendWhy = why;
   if(t == 0)
     {
      if(LG.act) { LG.act = false; legWhy = "H1 SIDE"; }
     }
   else if(changed || bos) LegFromStructure(t, bos ? "BOS" : "naya trend");
   else UpdateLeg();
   BuildLevels();
   DrawFib();
  }

// M1 close Fib 1.0 ke paar = leg khatam
void CheckInvalid()
  {
   if(!LG.act) return;
   double c1 = iClose(_Symbol, PERIOD_M1, 1);
   if((LG.dir == 1 && c1 < LG.L) || (LG.dir == -1 && c1 > LG.H))
     {
      LG.act = false; legWhy = "M1 close 1.0 ke paar";
      PrintFormat("FIB LEG khatam: M1 close %s, 1.0 (%s) ke paar", DS(c1), DS(LG.dir == 1 ? LG.L : LG.H));
      DrawFib();
     }
  }

// 0 = nahi, 1 = zone, 2 = zone + wick 0.786 tak (M1 candle band)
int FibSignal(int d)
  {
   if(!LG.act || LG.dir != d) return 0;
   double o1 = iOpen(_Symbol, PERIOD_M1, 1), c1 = iClose(_Symbol, PERIOD_M1, 1);
   double l1 = iLow(_Symbol, PERIOD_M1, 1), h1 = iHigh(_Symbol, PERIOD_M1, 1);
   if(!(d == 1 ? c1 > o1 : c1 < o1)) return 0;                  // candle trend ki taraf
   double a = Fib(InpZoneTop), b = Fib(InpZoneBottom);
   if(c1 < MathMin(a, b) || c1 > MathMax(a, b)) return 0;      // close zone me
   double dp = Fib(InpDeepFib);
   return (d == 1 ? l1 <= dp : h1 >= dp) ? 2 : 1;
  }

//==================== LEVELS (H4 ... Y) ====================
void AddLvl(double p, string nm, color c, int st)
  {
   if(p <= 0) return;
   ArrayResize(lvP, lvCnt + 1); ArrayResize(lvN, lvCnt + 1); ArrayResize(lvC, lvCnt + 1); ArrayResize(lvS, lvCnt + 1);
   lvP[lvCnt] = p; lvN[lvCnt] = nm; lvC[lvCnt] = c; lvS[lvCnt] = st; lvCnt++;
  }
void AddOHLC(double o, double h, double l, double c, string nm, color col)
  {
   AddLvl(h, nm + " H", col, STYLE_SOLID);
   AddLvl(l, nm + " L", col, STYLE_SOLID);
   AddLvl(o, nm + " O", col, STYLE_DOT);
   AddLvl(c, nm + " C", col, STYLE_DOT);
  }
// Pichhli 'cnt' candles (H4 / D / 3D / W / 1M)
void AddTF(ENUM_TIMEFRAMES tf, int cnt, string nm, color col)
  {
   if(iBars(_Symbol, tf) < cnt + 2) return;
   double h = iHigh(_Symbol, tf, 1), l = iLow(_Symbol, tf, 1);
   for(int s = 2; s <= cnt; s++) { h = MathMax(h, iHigh(_Symbol, tf, s)); l = MathMin(l, iLow(_Symbol, tf, s)); }
   AddOHLC(iOpen(_Symbol, tf, cnt), h, l, iClose(_Symbol, tf, 1), nm, col);
  }
datetime MonthStart(int y, int m)
  {
   MqlDateTime t; ZeroMemory(t);
   t.year = y; t.mon = m; t.day = 1;
   return StructToTime(t);
  }
// Calendar ki pichhli 3M (quarter) / 6M (half) / Y (saal) candle, monthly bars se
void AddPeriod(int P, string nm, color col)
  {
   MqlDateTime now; TimeToStruct(TimeCurrent(), now);
   int cs = now.year * 12 + ((now.mon - 1) / P) * P;   // abhi wale period ka pehla mahina
   int ps = cs - P;                                     // pichhla period
   double o = 0, h = 0, l = 0, c = 0; bool any = false;
   for(int k = 0; k < P; k++)
     {
      int mi = ps + k;
      int sh = iBarShift(_Symbol, PERIOD_MN1, MonthStart(mi / 12, mi % 12 + 1), true);
      if(sh < 1) continue;
      double bh = iHigh(_Symbol, PERIOD_MN1, sh), bl = iLow(_Symbol, PERIOD_MN1, sh);
      if(!any) { o = iOpen(_Symbol, PERIOD_MN1, sh); h = bh; l = bl; any = true; }
      else     { h = MathMax(h, bh); l = MathMin(l, bl); }
      c = iClose(_Symbol, PERIOD_MN1, sh);
     }
   if(any) AddOHLC(o, h, l, c, nm, col);
  }
void BuildLevels()
  {
   lvCnt = 0;
   ArrayResize(lvP, 0); ArrayResize(lvN, 0); ArrayResize(lvC, 0); ArrayResize(lvS, 0);
   AddTF(PERIOD_H4, 1, "H4", C'130,130,140');
   AddTF(PERIOD_D1, 1, "D", C'200,200,90');
   AddTF(PERIOD_D1, 3, "3D", C'210,180,60');
   AddTF(PERIOD_W1, 1, "W", C'240,150,40');
   AddTF(PERIOD_MN1, 1, "1M", C'250,120,30');
   AddPeriod(3, "3M", C'255,90,20');
   AddPeriod(6, "6M", C'255,60,60');
   AddPeriod(12, "Y", C'255,40,140');
  }

//==================== LIQUIDITY (sweep + raaste ke levels) ====================
void AddSup(double p) { ArrayResize(supP, supN + 1); supP[supN] = p; supN++; }
void AddRes(double p) { ArrayResize(resP, resN + 1); resP[resN] = p; resN++; }

// H1 swing jo abhi tak sweep nahi hue + M15 equal highs/lows
void BuildLiq()
  {
   supN = 0; resN = 0; ArrayResize(supP, 0); ArrayResize(resP, 0);
   for(int s = 3; s < 100; s++)
     {
      if(IsSwingLow(PERIOD_H1, s, 2))
        {
         double p = iLow(_Symbol, PERIOD_H1, s);
         int il = iLowest(_Symbol, PERIOD_H1, MODE_LOW, s - 1, 1);
         if(il >= 0 && iLow(_Symbol, PERIOD_H1, il) > p) AddSup(p);
        }
      if(IsSwingHigh(PERIOD_H1, s, 2))
        {
         double p = iHigh(_Symbol, PERIOD_H1, s);
         int ih = iHighest(_Symbol, PERIOD_H1, MODE_HIGH, s - 1, 1);
         if(ih >= 0 && iHigh(_Symbol, PERIOD_H1, ih) < p) AddRes(p);
        }
     }
   double el[], eh[]; int nl = 0, nh = 0;
   for(int s = 3; s < 100; s++)
     {
      if(IsSwingLow(PERIOD_M15, s, 2))  { ArrayResize(el, nl + 1); el[nl] = iLow(_Symbol, PERIOD_M15, s);  nl++; }
      if(IsSwingHigh(PERIOD_M15, s, 2)) { ArrayResize(eh, nh + 1); eh[nh] = iHigh(_Symbol, PERIOD_M15, s); nh++; }
     }
   for(int i = 0; i < nl; i++)
      for(int j = i + 1; j < nl; j++)
         if(MathAbs(el[i] - el[j]) <= InpEqualTolUSD) AddSup(MathMin(el[i], el[j]));
   for(int i = 0; i < nh; i++)
      for(int j = i + 1; j < nh; j++)
         if(MathAbs(eh[i] - eh[j]) <= InpEqualTolUSD) AddRes(MathMax(eh[i], eh[j]));
  }

// Band M1 candle: 1 = low sweep (BUY), -1 = high sweep (SELL), 0 = nahi / dono
int SweepOnM1(string &nm)
  {
   double l1 = iLow(_Symbol, PERIOD_M1, 1), h1 = iHigh(_Symbol, PERIOD_M1, 1), c1 = iClose(_Symbol, PERIOD_M1, 1);
   bool lo = false, hi = false; string nl = "", nh = "";
   for(int i = 0; i < lvCnt; i++)
     {
      if(!lo && l1 <= lvP[i] - InpSweepMinUSD && c1 > lvP[i]) { lo = true; nl = lvN[i]; }
      if(!hi && h1 >= lvP[i] + InpSweepMinUSD && c1 < lvP[i]) { hi = true; nh = lvN[i]; }
     }
   for(int i = 0; i < supN && !lo; i++)
      if(l1 <= supP[i] - InpSweepMinUSD && c1 > supP[i]) { lo = true; nl = "swing/equal low " + DS(supP[i]); }
   for(int i = 0; i < resN && !hi; i++)
      if(h1 >= resP[i] + InpSweepMinUSD && c1 < resP[i]) { hi = true; nh = "swing/equal high " + DS(resP[i]); }
   if(lo && !hi) { nm = nl; return 1; }
   if(hi && !lo) { nm = nh; return -1; }
   return 0;
  }

// TP ke raaste me (InpRoomUSD ke andar) ulta level to entry nahi
bool RoomOK(int d, double px, string &blk)
  {
   if(InpRoomUSD <= 0) return true;
   for(int i = 0; i < lvCnt; i++)
      if(d == 1 ? (lvP[i] > px && lvP[i] - px <= InpRoomUSD) : (lvP[i] < px && px - lvP[i] <= InpRoomUSD)) { blk = lvN[i]; return false; }
   if(d == 1)
     {
      for(int i = 0; i < resN; i++) if(resP[i] > px && resP[i] - px <= InpRoomUSD) { blk = "swing high " + DS(resP[i]); return false; }
     }
   else
     {
      for(int i = 0; i < supN; i++) if(supP[i] < px && px - supP[i] <= InpRoomUSD) { blk = "swing low " + DS(supP[i]); return false; }
     }
   return true;
  }

//==================== ENTRY / DCA ====================
void EntryFor(int d, SideInfo &s, int sw, string snm)
  {
   bool allowed = curTrend == d || (curTrend == 0 && InpSideBoth);
   if(!allowed || s.ent >= InpMaxEntries || s.be) return;
   string side = d == 1 ? "BUY" : "SELL";
   string tag = "", why = "";
   int fs = curTrend == d ? FibSignal(d) : 0;
   if(fs > 0) { tag = "F"; why = fs == 2 ? "Fib zone + 0.786 wick" : "Fib zone 0.5-0.65"; }
   else if(sw == d) { tag = "S"; why = "sweep " + snm; }
   if(tag == "") return;
   datetime opp = d == 1 ? lastHighSweep : lastLowSweep;
   if(opp > 0 && TimeCurrent() - opp < InpSweepBlockMin * 60)
     {
      sigTxt = side + " ruka: " + (d == 1 ? "high" : "low") + " sweep abhi hua";
      return;
     }
   double px = d == 1 ? Ask() : Bid();
   string blk = "";
   if(!RoomOK(d, px, blk))
     {
      sigTxt = side + " ruka: raaste me " + blk;
      PrintFormat("%s signal (%s) par entry nahi: TP ke raaste me %s", side, why, blk);
      return;
     }
   double lot = CurLot();
   if(Open(d, lot, tag))
     {
      sigTxt = side + ": " + why;
      PrintFormat("ENTRY %s %.2f lot @ %s (%s) | H1 %s", side, lot, DS(px), why, TrendName(curTrend));
     }
  }

void CheckEntries()
  {
   string snm = "";
   int sw = InpUseSweep ? SweepOnM1(snm) : 0;
   if(sw == 1)  { lastLowSweep = TimeCurrent();  PrintFormat("LOW SWEEP: %s", snm); }
   if(sw == -1) { lastHighSweep = TimeCurrent(); PrintFormat("HIGH SWEEP: %s", snm); }
   if(!autoOn || !SessionOK() || newsNow || !MarginOK() || Spread() > InpMaxSpreadUSD) return;
   EntryFor(1, SB, sw, snm);
   EntryFor(-1, SS, sw, snm);
  }

// DCA: side ki sabse kharab position se rtDCA ulta, pehle trade ke lot se (har tick)
void DoDCA(int d, SideInfo &s)
  {
   if(!InpDCA || s.n == 0 || s.be) return;
   if(InpDCAMax > 0 && s.dca >= InpDCAMax) return;
   double px = d == 1 ? Ask() : Bid();
   if(!(d == 1 ? px <= s.worst - rtDCA : px >= s.worst + rtDCA)) return;
   double lot = s.firstLot > 0 ? NormLot(s.firstLot) : CurLot();
   if(Open(d, lot, "D" + IntegerToString(s.dca + 1)))
      PrintFormat("DCA %s #%d: %.2f lot @ %s (sabse kharab %s se $%.2f ulta)", d == 1 ? "BUY" : "SELL", s.dca + 1, lot, DS(px), DS(s.worst), rtDCA);
  }

//==================== PAIR CLOSE ====================
// Sabse zyada loss wala phansa trade + sabse zyada profit wale trades: total >= min tabhi band
bool PairClose()
  {
   if(!rtPair) return false;
   double bid = Bid(), ask = Ask();
   int cnt = 0; ulong wT = 0; double wP = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !Mine()) continue;
      int d = Dir();
      cnt++;
      double p = PL(), op = PositionGetDouble(POSITION_PRICE_OPEN);
      bool stuck = d == 1 ? op - bid >= rtDCA : ask - op >= rtDCA;   // kam se kam 1 DCA step ulta
      if(stuck && p < wP) { wP = p; wT = t; }
     }
   if(cnt < InpPairMinPos || wT == 0) return false;
   ulong tk[]; ArrayResize(tk, InpPairMaxWin + 1);
   int n = 0; double sum = wP;
   while(n < InpPairMaxWin && sum < InpPairMinUSD)
     {
      ulong best = 0; double bp = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(t == 0 || t == wT || !Mine()) continue;
         bool used = false;
         for(int j = 0; j < n; j++) if(tk[j] == t) { used = true; break; }
         if(used) continue;
         double p = PL();
         if(p > bp) { bp = p; best = t; }
        }
      if(best == 0) break;
      tk[n++] = best; sum += bp;
     }
   if(sum < InpPairMinUSD) return false;
   PrintFormat("PAIR CLOSE: loss %.2f + %d profit trades = %+.2f", wP, n, sum);
   tk[n++] = wT;            // profit wale pehle, loss wala last
   CloseTickets(tk, n);
   return true;
  }

//==================== TP + BREAKEVEN ====================
bool ManageStops(int dir, SideInfo &s, double bid, double ask)
  {
   if(s.n == 0) return false;
   long lv = MathMax(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL), SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL));
   double minStop = (double)lv * _Point + 5 * _Point;
   double move = dir == 1 ? bid - s.avg : s.avg - ask;
   if(!s.be && s.n >= 2 && move >= InpBETrigger)
     {
      s.be = true;
      s.beSL = NP(s.avg + dir * InpBELock);
      PrintFormat("%s side: +$%.2f, sab positions ka SL breakeven %s", dir == 1 ? "BUY" : "SELL", InpBETrigger, DS(s.beSL));
     }
   if(s.be && s.profit > 0 && ((dir == 1 && bid <= s.beSL) || (dir == -1 && ask >= s.beSL)))   // side ka total profit me ho tabhi
     {
      PrintFormat("%s side breakeven close %+.2f", dir == 1 ? "BUY" : "SELL", s.profit);
      CloseWhere(dir);
      s.be = false;
      return true;
     }
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !Mine() || Dir() != dir) continue;
      double op = PositionGetDouble(POSITION_PRICE_OPEN), cSL = PositionGetDouble(POSITION_SL), cTP = PositionGetDouble(POSITION_TP);
      bool manual = PositionGetInteger(POSITION_MAGIC) == 0;
      double eaTP = rtTP > 0 ? NP(op + dir * rtTP) : 0;
      bool userTP = manual && InpKeepManualSLTP && cTP > 0 && MathAbs(cTP - eaTP) >= 10 * _Point;
      if(!userTP && eaTP > 0 && ((dir == 1 && bid >= eaTP) || (dir == -1 && ask <= eaTP)))
        { trade.PositionClose(t); continue; }       // price TP se aage (TP laga nahi tha) = profit book
      double tp = userTP ? cTP : eaTP;
      if(tp > 0 && MathAbs(tp - cTP) >= 10 * _Point && ((dir == 1 && tp - ask < minStop) || (dir == -1 && bid - tp < minStop))) tp = cTP;
      double sl = cSL;
      if(s.be && ((dir == 1 && bid - s.beSL >= minStop) || (dir == -1 && s.beSL - ask >= minStop)))
         sl = cSL <= 0 ? s.beSL : (dir == 1 ? MathMax(cSL, s.beSL) : MathMin(cSL, s.beSL));   // SL sirf profit ki taraf
      if(MathAbs(sl - cSL) < 10 * _Point && MathAbs(tp - cTP) < 10 * _Point) continue;
      trade.PositionModify(t, sl, tp);
     }
   return false;
  }

//==================== MAIN ====================
void OnTick()
  {
   ReadAll();
   UpdateNews();

   //--- naya H1 candle = trend + leg (trend sirf yahin badalta hai)
   datetime h1 = iTime(_Symbol, PERIOD_H1, 0);
   if(h1 > 0 && h1 != lastH1) { lastH1 = h1; OnNewH1(); if(rtHMOn) DrawHeatmap(); }
   //--- naya M15 candle = liquidity levels + heatmap
   datetime m15 = iTime(_Symbol, PERIOD_M15, 0);
   if(m15 > 0 && m15 != lastM15) { lastM15 = m15; BuildLiq(); if(rtHMOn) DrawHeatmap(); }

   //--- shuruaat ka Fib leg (ATR ready hone ke baad, ek baar)
   if(legPending && Buf(hATR, 0, 1) != EMPTY_VALUE)
     {
      legPending = false;
      if(curTrend != 0 && !LG.act) { LegFromStructure(curTrend, "shuruaat"); DrawFib(); }
     }

   double bid = Bid(), ask = Ask();
   if(LG.act && !LG.touched && (LG.dir == 1 ? bid <= Fib(InpZoneTop) : ask >= Fib(InpZoneTop))) LG.touched = true;

   //--- 1) Net close: BUY + SELL dono khule, total profit me
   if(InpNetClose && buyLotsAll > 0 && sellLotsAll > 0 && anyLoss && allProfit >= InpNetCloseUSD)
     {
      PrintFormat("NET CLOSE: total %+.2f", allProfit);
      CloseWhere(0);
      return;
     }
   //--- 2) Pair close
   if(PairClose()) { Panel(); return; }
   //--- 3) TP + breakeven
   if(ManageStops(1, SB, bid, ask) || ManageStops(-1, SS, bid, ask)) { Panel(); return; }
   //--- 4) DCA (har tick, candle close nahi)
   if(Spread() <= InpMaxSpreadUSD && !newsNow && MarginOK()) { DoDCA(1, SB); DoDCA(-1, SS); }
   //--- 5) M1 candle band: leg invalid check + entry
   datetime m1 = iTime(_Symbol, PERIOD_M1, 0);
   if(m1 > 0 && m1 != lastM1)
     {
      lastM1 = m1;
      CheckInvalid();
      CheckEntries();
     }
   Panel();
  }

//==================== FIB DRAW ====================
void FbLine(string id, datetime t1, datetime t2, double p, color c, string label)
  {
   string n = FBP + id;
   if(!ObjectCreate(0, n, OBJ_TREND, 0, t1, p, t2, p)) return;
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetInteger(0, n, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, n, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
   string tn = n + "_t";
   if(ObjectCreate(0, tn, OBJ_TEXT, 0, t2, p))
     {
      ObjectSetString(0, tn, OBJPROP_TEXT, label);
      ObjectSetInteger(0, tn, OBJPROP_COLOR, c);
      ObjectSetInteger(0, tn, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, tn, OBJPROP_ANCHOR, ANCHOR_LEFT);
      ObjectSetInteger(0, tn, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, tn, OBJPROP_HIDDEN, true);
     }
  }

void DrawFib()
  {
   ObjectsDeleteAll(0, FBP);
   if(!InpShowFib || !LG.act) { ChartRedraw(); return; }
   double fl[8] = {0.0, 0.382, 0.5, 0.618, 0.65, 0.786, 1.0, 1.27};
   string fn[8] = {"0", "0.382", "0.5", "0.618", "0.65", "0.786", "1", "1.27"};
   color  fc[8] = {C'150,150,150', C'60,120,230', C'190,60,60', C'235,60,60', C'240,150,40', C'40,180,90', C'150,150,150', C'170,90,210'};
   datetime t1 = LG.tL < LG.tH ? LG.tL : LG.tH, t2 = TimeCurrent() + PeriodSeconds(PERIOD_H1) * 6;
   for(int i = 0; i < 8; i++)
     {
      double p = Fib(fl[i]);
      FbLine("f" + IntegerToString(i), t1, t2, p, fc[i], StringFormat("%s (%s)", fn[i], DS(p)));
     }
   string z = FBP + "zone";
   if(ObjectCreate(0, z, OBJ_RECTANGLE, 0, t1, Fib(InpZoneTop), t2, Fib(InpZoneBottom)))
     {
      ObjectSetInteger(0, z, OBJPROP_COLOR, LG.dir == 1 ? C'25,70,45' : C'80,30,30');
      ObjectSetInteger(0, z, OBJPROP_FILL, true);
      ObjectSetInteger(0, z, OBJPROP_BACK, true);
      ObjectSetInteger(0, z, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, z, OBJPROP_HIDDEN, true);
     }
   string tr = FBP + "leg";
   if(ObjectCreate(0, tr, OBJ_TREND, 0, LG.dir == 1 ? LG.tL : LG.tH, LG.dir == 1 ? LG.L : LG.H, LG.dir == 1 ? LG.tH : LG.tL, LG.dir == 1 ? LG.H : LG.L))
     {
      ObjectSetInteger(0, tr, OBJPROP_COLOR, C'150,150,150');
      ObjectSetInteger(0, tr, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, tr, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, tr, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, tr, OBJPROP_HIDDEN, true);
     }
   ChartRedraw();
  }

//==================== LIQUIDITY HEATMAP ====================
int HMIdx() { return rtHM < 0 ? 0 : (rtHM > 5 ? 5 : rtHM); }
int RangeHours() { int h[6] = {12, 24, 72, 168, 720, 2160}; return h[HMIdx()]; }

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

void DrawHeatmap()
  {
   ObjectsDeleteAll(0, HMP);
   if(!rtHMOn) { ChartRedraw(); return; }
   int hours = RangeHours();
   datetime now = TimeCurrent(), from = now - hours * 3600;
   datetime right = now + PeriodSeconds(PERIOD_CURRENT) * 15;
   ENUM_TIMEFRAMES tf = hours <= 24 ? PERIOD_M15 : PERIOD_H1;
   int bars = iBarShift(_Symbol, tf, from);
   if(bars < 0) bars = iBars(_Symbol, tf) - 5;
   bars = (int)MathMin(bars, 2000);
   int n = 2;
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
      int ih = sh > 1 ? iHighest(_Symbol, tf, MODE_HIGH, sh - 1, 1) : -1;
      bool swept = ih >= 0 && iHigh(_Symbol, tf, ih) > hp[i];
      color c = swept ? C'70,70,80' : (eq >= 2 ? C'255,40,40' : (eq == 1 ? C'200,50,50' : C'130,45,45'));
      HmRect("sh" + IntegerToString(i), ht[i], hp[i] + band, right, hp[i] - band, c);
     }
   for(int i = 0; i < nl; i++)
     {
      int eq = 0;
      for(int j = 0; j < nl; j++) if(j != i && MathAbs(lp[j] - lp[i]) <= InpEqualTolUSD) eq++;
      int sh = iBarShift(_Symbol, tf, lt[i]);
      int il = sh > 1 ? iLowest(_Symbol, tf, MODE_LOW, sh - 1, 1) : -1;
      bool swept = il >= 0 && iLow(_Symbol, tf, il) < lp[i];
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
            int il = i > 1 ? iLowest(_Symbol, tf, MODE_LOW, i - 1, 1) : -1;
            bool filled = il >= 0 && iLow(_Symbol, tf, il) <= hi2;
            if(!filled) HmRect("fb" + IntegerToString(i), t, lo0, right, hi2, C'40,70,150');
           }
         if(hi0 < lo2)   // bearish FVG
           {
            int ih = i > 1 ? iHighest(_Symbol, tf, MODE_HIGH, i - 1, 1) : -1;
            bool filled = ih >= 0 && iHigh(_Symbol, tf, ih) >= lo2;
            if(!filled) HmRect("fs" + IntegerToString(i), t, lo2, right, hi0, C'110,50,140');
           }
        }

   //--- bade levels: H4 / D / 3D / W / 1M / 3M / 6M / Y ka O / H / L / C
   if(InpShowLevels)
      for(int i = 0; i < lvCnt; i++)
         HmLine("lv" + IntegerToString(i), from, right, lvP[i], lvC[i], lvS[i], lvN[i]);

   //--- volume profile (M15 tick volume) chart ke right side, POC = peela
   if(InpShowVP && InpVPBins > 2)
     {
      int vb = (int)MathMin(iBarShift(_Symbol, PERIOD_M15, from), 3000);
      if(vb > 5)
        {
         int ih = iHighest(_Symbol, PERIOD_M15, MODE_HIGH, vb, 1), il = iLowest(_Symbol, PERIOD_M15, MODE_LOW, vb, 1);
         double hi = ih >= 0 ? iHigh(_Symbol, PERIOD_M15, ih) : 0, lo = il >= 0 ? iLow(_Symbol, PERIOD_M15, il) : 0;
         if(hi > lo && lo > 0)
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
void OnOff(string id, int x, int y, int w, string name, bool on)
  {
   Bt(id, x, y, w, 22, name + (on ? ": ON" : ": OFF"), on ? cB : cLn, on ? cBg : cTx);
  }

void Panel()
  {
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return;
   if(TimeLocal() == lastDraw) return;
   lastDraw = TimeLocal();
   int W = 340, y;
   Rc("bg", 0, 0, W, 100, cBg);
   Tx("ti", 10, 6, TITLE, cTx, 10, true);
   bool wb = curTrend == 1 || (curTrend == 0 && InpSideBoth), ws = curTrend == -1 || (curTrend == 0 && InpSideBoth);
   string tr = wb && ws ? "BUY+SELL (sweep)" : (wb ? "BUY" : (ws ? "SELL" : "-"));
   Tx("st", 10, 24, StringFormat("H1: %s (%s) | trade %s | spread %s%s", TrendName(curTrend), trendWhy, tr, DS(Spread()), newsNow ? " | NEWS" : ""),
      newsNow ? cS : (curTrend == 1 ? cB : (curTrend == -1 ? cS : cDm)), 8, true);
   y = 42;
   string lg = LG.act ? StringFormat("Fib %s: L %s  H %s | zone %s - %s%s", LG.dir == 1 ? "BUY" : "SELL", DS(LG.L), DS(LG.H),
                                     DS(Fib(InpZoneTop)), DS(Fib(InpZoneBottom)), LG.touched ? " | zone touch" : "")
                      : "Fib leg: " + legWhy;
   Tx("lg", 10, y, lg, LG.act ? cW : cDm, 8);
   y += 16;
   Tx("sg", 10, y, "Signal: " + sigTxt, cDm, 8);
   y += 20;
   Rc("cb", 6, y, W - 12, 22, cCard);
   Tx("lb", 12, y + 4, StringFormat("BUY  %d (%d entry + %d DCA) | %.2f lot | %+.2f%s", SB.n, SB.ent, SB.dca, SB.lots, SB.profit, SB.be ? " | BE" : ""), cB, 8, true);
   y += 24;
   Rc("cs", 6, y, W - 12, 22, cCard);
   Tx("ls", 12, y + 4, StringFormat("SELL %d (%d entry + %d DCA) | %.2f lot | %+.2f%s", SS.n, SS.ent, SS.dca, SS.lots, SS.profit, SS.be ? " | BE" : ""), cS, 8, true);
   y += 26;
   double ml = AccountInfoDouble(ACCOUNT_MARGIN) > 0 ? AccountInfoDouble(ACCOUNT_MARGIN_LEVEL) : 0;
   Tx("net", 10, y, StringFormat("NET %+.2f | margin %s", allProfit, ml > 0 ? StringFormat("%.0f%%", ml) : "-"), allProfit >= 0 ? cB : cS, 9, true);
   y += 22;
   int bw = (W - 12 - 8) / 3;
   Bt("auto", 6, y, bw, 22, autoOn ? "AUTO ON" : "AUTO OFF", autoOn ? cB : cLn, autoOn ? cBg : cTx);
   OnOff("pair", 6 + bw + 4, y, bw, "PAIR", rtPair);
   OnOff("hmon", 6 + 2 * (bw + 4), y, bw, "HEATMAP", rtHMOn);
   y += 26;
   string hn[6] = {"12H", "1D", "3D", "1W", "1M", "ALL"};
   int hw = (W - 12 - 15) / 6;
   for(int i = 0; i < 6; i++)
      Bt("hm" + IntegerToString(i), 6 + i * (hw + 3), y, hw, 20, hn[i], rtHM == i ? cW : cLn, rtHM == i ? cBg : cTx);
   y += 24;
   Bt("cb", 6, y, bw, 22, "Close BUY", cB, cBg);
   Bt("cs", 6 + bw + 4, y, bw, 22, "Close SELL", cS, clrWhite);
   Bt("ca", 6 + 2 * (bw + 4), y, bw, 22, "CLOSE ALL", cS, clrWhite);
   y += 26;
   Bt("lotmode", 6, y, W - 12, 22, rtAuto ? "LOT: AUTO (capital)" : "LOT: FIXED", rtAuto ? cB : cLn, rtAuto ? cBg : cTx);
   y += 28;
   string lab[3];
   string ids[3] = {"tp", "dca", "lot"};
   lab[0] = StringFormat("TP  +$%s (har trade)", DoubleToString(rtTP, TP_STEP < 1 ? 1 : 0));
   lab[1] = StringFormat("DCA  $%s  (%s)", DoubleToString(rtDCA, DCA_STEP < 1 ? 1 : 0), InpDCAMax > 0 ? StringFormat("max %d", InpDCAMax) : "unlimited");
   lab[2] = rtAuto ? StringFormat("Lot AUTO %.2f  (0.01 / $%.0f)", CurLot(), rtPer) : StringFormat("Lot FIXED  %.2f", rtLot);
   for(int r = 0; r < 3; r++)
     {
      Rc("row" + IntegerToString(r), 6, y, W - 12, 24, cCard);
      Bt(ids[r] + "m", 10, y + 2, 32, 20, "-", cLn, cTx);
      Tx("l" + IntegerToString(r), 50, y + 5, lab[r], cTx, 9, true);
      Bt(ids[r] + "p", W - 46, y + 2, 32, 20, "+", cLn, cTx);
      y += 27;
     }
   ObjectSetInteger(0, PFX + "bg", OBJPROP_YSIZE, y + 4);
   ChartRedraw();
  }

void OnChartEvent(const int id, const long &l, const double &d, const string &sp)
  {
   if(id != CHARTEVENT_OBJECT_CLICK || StringFind(sp, PFX + "btn_") != 0) return;
   ObjectSetInteger(0, sp, OBJPROP_STATE, false);
   string b = StringSubstr(sp, StringLen(PFX + "btn_"));
   ReadAll();
   if(b == "auto") autoOn = !autoOn;
   else if(b == "pair") rtPair = !rtPair;
   else if(b == "hmon") { rtHMOn = !rtHMOn; DrawHeatmap(); }
   else if(StringFind(b, "hm") == 0 && StringLen(b) == 3)
     {
      rtHM = (int)StringToInteger(StringSubstr(b, 2));
      if(!rtHMOn) rtHMOn = true;
      DrawHeatmap();
     }
   else if(b == "tpm" || b == "tpp") rtTP = MathMax(TP_STEP, rtTP + (b == "tpp" ? TP_STEP : -TP_STEP));
   else if(b == "dcam" || b == "dcap") rtDCA = MathMax(DCA_STEP, rtDCA + (b == "dcap" ? DCA_STEP : -DCA_STEP));
   else if(b == "lotmode") rtAuto = !rtAuto;
   else if(b == "lotm" || b == "lotp")
     {
      if(rtAuto) rtPer = MathMax(100.0, rtPer + (b == "lotp" ? -100.0 : 100.0));   // + = zyada lot (kam $ per 0.01)
      else rtLot = MathMax(VolMin(), rtLot + (b == "lotp" ? 0.01 : -0.01));
     }
   else if(b == "cb" || b == "cs" || b == "ca")
     {
      string w = b == "cb" ? "BUY" : (b == "cs" ? "SELL" : "SAB");
      if(MessageBox(w + " positions close karein?", TITLE, MB_YESNO | MB_ICONWARNING) == IDYES)
         CloseWhere(b == "ca" ? 0 : (b == "cb" ? 1 : -1));
     }
   lastDraw = 0;
   Panel();
  }
//+------------------------------------------------------------------+
