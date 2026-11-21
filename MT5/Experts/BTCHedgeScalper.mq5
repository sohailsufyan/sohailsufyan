//+------------------------------------------------------------------+
//|                                            BTCHedgeScalper.mq5   |
//|  BTCUSD M1 hedge scalper (crypto 24/7)                            |
//|  - Har naye M1 candle par EMA trend ki direction me trade         |
//|    (ya BOTH mode: BUY + SELL dono)                                |
//|  - Har position ka apna chhota TP (+$1) - turant profit           |
//|  - $3 against par DCA, side +$1 chale to SL breakeven +$0.20      |
//|  - Loss me auto-close nahi; net profit (BUY+SELL) par sab close    |
//|  - LOCK / UNLOCK hedge buttons, margin guard                       |
//+------------------------------------------------------------------+
#property copyright "BTCHedgeScalper"
#property version   "1.10"

#include <Trade/Trade.mqh>

enum ENUM_ENTRY_MODE { MODE_TREND = 0, MODE_BOTH = 1 };

input group "=== Entry (har M1 candle) ==="
input bool            InpAutoOn           = true;         // Auto entry ON
input ENUM_ENTRY_MODE InpMode             = MODE_TREND;   // TREND = EMA direction, BOTH = BUY + SELL dono
input ENUM_TIMEFRAMES InpSigTF            = PERIOD_M1;    // Entry candle timeframe
input int             InpFastEMA          = 21;           // Fast EMA
input int             InpSlowEMA          = 50;           // Slow EMA
input bool            InpUseHTF           = true;         // Bada trend bhi same ho (H1 EMA50)
input ENUM_TIMEFRAMES InpHTF              = PERIOD_H1;    // Bada trend TF
input bool            InpAutoLot          = true;         // Lot capital ke hisaab se khud (AUTO)
input double          InpBalancePer001    = 1000.0;       // AUTO: har itne $ balance par 0.01 lot
input double          InpLot              = 0.01;         // FIXED: har trade ka lot
input int             InpMaxPerSide       = 5;            // Ek side me max positions (DCA milake)
input bool            InpSessionOnly      = false;        // Sirf London + New York (BTC 24/7 chalta hai)
input int             InpGMTOffset        = 2;            // Server time = GMT + ?
input int             InpMaxSpread        = 3000;         // Max spread (cents, 3000 = $30)

input group "=== Exit (turant profit) ==="
input double          InpTP               = 30.0;         // Har position ka TP: entry se +$30
input double          InpBETrigger        = 30.0;         // Side average se +$30 par sab positions ka SL breakeven
input double          InpBELock           = 5.0;          // Breakeven = average + $5 (loss na ho)
input bool            InpNetClose         = true;         // BUY + SELL net profit me = sab close
input double          InpNetCloseUSD      = 5.0;          // Net kam se kam $

input group "=== DCA ==="
input bool            InpDCA              = true;         // DCA ON
input double          InpDCAStep          = 150.0;        // Side ki sabse kharab position se $150 against par naya trade

input group "=== Protection ==="
input double          InpMinMarginLevel   = 300.0;        // Margin level isse kam = naye trade/DCA band
input double          InpMinFreeMarginPct = 30.0;         // Free margin equity ka isse kam = naye trade band
input bool            InpManageManual     = true;         // Manual trades (magic 0) bhi manage (TP/BE/net/lock)
input long            InpMagic            = 777666;       // Magic

input group "=== Panel ==="
input int             InpPanelX           = 10;
input int             InpPanelY           = 25;

//==================== GLOBALS ====================
CTrade   trade;
int      hF = INVALID_HANDLE, hS = INVALID_HANDLE, hH = INVALID_HANDLE;
datetime lastBar = 0;
bool     autoOn;
int      mode;
double   rtTP, rtDCA, rtLot, rtPer;
bool     rtAuto;
int      rtMax;
#define  PFX "BHS_"

struct SideInfo { int n; double lots, avg, worst, profit; bool be; double beSL; };
SideInfo SB, SS;

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFillingBySymbol(_Symbol);
   hF = iMA(_Symbol, InpSigTF, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hS = iMA(_Symbol, InpSigTF, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hH = iMA(_Symbol, InpHTF, 50, 0, MODE_EMA, PRICE_CLOSE);
   if(hF == INVALID_HANDLE || hS == INVALID_HANDLE || hH == INVALID_HANDLE) return(INIT_FAILED);
   autoOn = InpAutoOn; mode = InpMode; rtTP = InpTP; rtDCA = InpDCAStep; rtLot = InpLot; rtMax = InpMaxPerSide;
   rtAuto = InpAutoLot; rtPer = InpBalancePer001;
   SB.be = false; SS.be = false; SB.beSL = 0; SS.beSL = 0;
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("WARNING: Hedging account chahiye.");
   EventSetTimer(1);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int r)
  {
   EventKillTimer();
   IndicatorRelease(hF); IndicatorRelease(hS); IndicatorRelease(hH);
   ObjectsDeleteAll(0, PFX);
  }

void OnTimer() { Panel(); }

//==================== HELPERS ====================
bool Mine()
  {
   if(PositionGetString(POSITION_SYMBOL) != _Symbol) return false;
   long mg = PositionGetInteger(POSITION_MAGIC);
   return mg == InpMagic || (InpManageManual && mg == 0);
  }
int    Dir()      { return PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1; }
double Spread()   { return (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / 0.01; }
double B1(int h, int shift) { double a[]; ArraySetAsSeries(a, true); return CopyBuffer(h, 0, shift, 1, a) == 1 ? a[0] : 0; }
bool   IsLock()   { return StringFind(PositionGetString(POSITION_COMMENT), "LOCK") >= 0; }

double NormLot(double lot)
  {
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP); if(st <= 0) st = 0.01;
   lot = MathFloor(lot / st + 1e-9) * st;
   return NormalizeDouble(MathMax(mn, MathMin(lot, mx)), 2);
  }

void ReadSide(int dir, SideInfo &s)
  {
   bool be = s.be; double bsl = s.beSL; int n0 = s.n;
   s.n = 0; s.lots = 0; s.avg = 0; s.worst = 0; s.profit = 0;
   double pv = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0 || !Mine() || Dir() != dir) continue;
      double v = PositionGetDouble(POSITION_VOLUME), p = PositionGetDouble(POSITION_PRICE_OPEN);
      s.n++; s.lots += v; pv += v * p;
      s.profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      if(s.worst == 0 || (dir == 1 && p < s.worst) || (dir == -1 && p > s.worst)) s.worst = p;
     }
   if(s.lots > 0) s.avg = pv / s.lots;
   s.be = be; s.beSL = bsl;
   if(s.n == 0 || s.n > n0) { s.be = false; s.beSL = 0; }   // nayi position = naya average
  }

bool MarginOK()
  {
   double m = AccountInfoDouble(ACCOUNT_MARGIN), eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(m > 0 && AccountInfoDouble(ACCOUNT_MARGIN_LEVEL) < InpMinMarginLevel) return false;
   if(eq > 0 && AccountInfoDouble(ACCOUNT_MARGIN_FREE) / eq * 100.0 < InpMinFreeMarginPct) return false;
   return true;
  }

bool SessionOK()
  {
   if(!InpSessionOnly) return true;
   MqlDateTime g; TimeToStruct(TimeCurrent() - InpGMTOffset * 3600, g);
   return g.hour >= 7 && g.hour < 21;
  }

int Trend()
  {
   double f = B1(hF, 1), s = B1(hS, 1), c = iClose(_Symbol, InpSigTF, 1);
   if(f == 0 || s == 0) return 0;
   int t = (f > s && c > f) ? 1 : ((f < s && c < f) ? -1 : 0);
   if(t != 0 && InpUseHTF)
     {
      double h = B1(hH, 1), hc = iClose(_Symbol, InpHTF, 1);
      if(h == 0 || (t == 1 && hc < h) || (t == -1 && hc > h)) return 0;
     }
   return t;
  }

// Capital ke hisaab se lot (AUTO) ya fixed
double CurLot()
  {
   if(!rtAuto) return CurLot();
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   return NormLot(0.01 * MathFloor(bal / MathMax(1.0, rtPer)));
  }

bool Open(int dir, double lot, string tag)
  {
   double px = dir == 1 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double tp = (rtTP > 0 && tag != "LOCK") ? NormalizeDouble(px + dir * rtTP, dg) : 0;
   bool ok = dir == 1 ? trade.Buy(lot, _Symbol, 0, 0, tp, "BHS " + tag) : trade.Sell(lot, _Symbol, 0, 0, tp, "BHS " + tag);
   if(!ok || (trade.ResultRetcode() != TRADE_RETCODE_DONE && trade.ResultRetcode() != TRADE_RETCODE_PLACED))
     {
      PrintFormat("Order fail %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
      return false;
     }
   return true;
  }

void CloseWhere(int dir, bool onlyLock)
  {
   for(int pass = 0; pass < 3; pass++)
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(t == 0 || !Mine()) continue;
         if(dir != 0 && Dir() != dir) continue;
         if(onlyLock && !IsLock()) continue;
         if(PositionSelectByTicket(t)) trade.PositionClose(t);
        }
  }

//==================== MAIN ====================
void OnTick()
  {
   ReadSide(1, SB); ReadSide(-1, SS);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   //--- Net profit close (dono side khuli, koi loss me)
   if(InpNetClose && SB.n > 0 && SS.n > 0 && (SB.profit < 0 || SS.profit < 0) && SB.profit + SS.profit >= InpNetCloseUSD)
     {
      PrintFormat("NET CLOSE: %.2f + %.2f = %.2f", SB.profit, SS.profit, SB.profit + SS.profit);
      CloseWhere(0, false);
      return;
     }

   //--- Har position ka TP (manual trades ko bhi) + breakeven
   ManageStops(1, SB, bid, ask);
   ManageStops(-1, SS, bid, ask);

   bool roomOK = MarginOK() && Spread() <= InpMaxSpread;

   //--- DCA: side ki sabse kharab position se $X against
   if(InpDCA && roomOK)
     {
      if(SB.n > 0 && SB.n < rtMax && !SB.be && ask <= SB.worst - rtDCA) Open(1, CurLot(), "DCA");
      if(SS.n > 0 && SS.n < rtMax && !SS.be && bid >= SS.worst + rtDCA) Open(-1, CurLot(), "DCA");
     }

   //--- Har naye candle par entry
   datetime bar = iTime(_Symbol, InpSigTF, 0);
   if(bar != lastBar)
     {
      lastBar = bar;
      if(autoOn && roomOK && SessionOK())
        {
         int t = Trend();
         bool wantB = (mode == MODE_BOTH) || t == 1;
         bool wantS = (mode == MODE_BOTH) || t == -1;
         if(wantB && SB.n < rtMax && !SB.be) Open(1, CurLot(), "AUTO");
         if(wantS && SS.n < rtMax && !SS.be) Open(-1, CurLot(), "AUTO");
        }
     }
   Panel();
  }

// TP har position par; side +$X chale to sab ka SL = average + lock
void ManageStops(int dir, SideInfo &s, double bid, double ask)
  {
   if(s.n == 0) return;
   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   long lv = MathMax(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL), SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL));
   double minStop = (double)lv * _Point + 5 * _Point;
   double move = dir == 1 ? bid - s.avg : s.avg - ask;
   if(!s.be && s.n >= 2 && move >= InpBETrigger)
     {
      s.be = true;
      s.beSL = NormalizeDouble(s.avg + dir * InpBELock, dg);
      PrintFormat("%s side: +$%.1f, sab positions ka SL breakeven %.2f", dir == 1 ? "BUY" : "SELL", InpBETrigger, s.beSL);
     }
   if(s.be && s.profit > 0 && ((dir == 1 && bid <= s.beSL) || (dir == -1 && ask >= s.beSL)))   // side ka total profit me ho tabhi
     {
      PrintFormat("%s side breakeven close", dir == 1 ? "BUY" : "SELL");
      CloseWhere(dir, false);
      s.be = false;
      return;
     }
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !Mine() || Dir() != dir || IsLock()) continue;
      double op = PositionGetDouble(POSITION_PRICE_OPEN), cSL = PositionGetDouble(POSITION_SL), cTP = PositionGetDouble(POSITION_TP);
      double tp = rtTP > 0 ? NormalizeDouble(op + dir * rtTP, dg) : 0;
      if(tp > 0 && ((dir == 1 && tp - ask < minStop) || (dir == -1 && bid - tp < minStop))) tp = cTP;
      double sl = cSL;
      if(s.be && ((dir == 1 && bid - s.beSL >= minStop) || (dir == -1 && s.beSL - ask >= minStop))) sl = s.beSL;
      if(MathAbs(sl - cSL) < 10 * _Point && MathAbs(tp - cTP) < 10 * _Point) continue;
      trade.PositionModify(t, sl, tp);
     }
  }

// LOCK: net lot zero (loss wahin ruk jaye)
void DoLock()
  {
   double net = SB.lots - SS.lots;
   if(MathAbs(net) < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) { Print("Pehle se lock hai (net 0)"); return; }
   int dir = net > 0 ? -1 : 1;
   if(Open(dir, NormLot(MathAbs(net)), "LOCK")) PrintFormat("LOCK: %s %.2f lot - net exposure 0", dir == 1 ? "BUY" : "SELL", MathAbs(net));
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
void Tx(string id, int x, int y, string t, color c, int sz = 9, bool b = false)
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
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return;
   if(TimeLocal() == lastDraw) return;
   lastDraw = TimeLocal();
   int W = 330, y;
   Rc("bg", 0, 0, W, 100, cBg);
   int t = Trend();
   Tx("ti", 10, 6, "BTC HEDGE SCALPER", cTx, 10, true);
   double ml = AccountInfoDouble(ACCOUNT_MARGIN) > 0 ? AccountInfoDouble(ACCOUNT_MARGIN_LEVEL) : 0;
   Tx("st", 10, 24, StringFormat("Trend: %s  |  Margin %s  |  Spread %.0f", t == 1 ? "UP" : (t == -1 ? "DOWN" : "SIDE"),
      ml > 0 ? StringFormat("%.0f%%", ml) : "-", Spread()), MarginOK() ? cDm : cS, 8);
   y = 44;
   Rc("cb", 6, y, W - 12, 22, cCard);
   Tx("lb", 12, y + 4, StringFormat("BUY  %d pos | %.2f lot | P/L %+.2f%s", SB.n, SB.lots, SB.profit, SB.be ? " | BE" : ""), cB, 8, true);
   y += 24;
   Rc("cs", 6, y, W - 12, 22, cCard);
   Tx("ls", 12, y + 4, StringFormat("SELL %d pos | %.2f lot | P/L %+.2f%s", SS.n, SS.lots, SS.profit, SS.be ? " | BE" : ""), cS, 8, true);
   y += 26;
   double net = SB.profit + SS.profit;
   Tx("net", 10, y, StringFormat("NET %+.2f  (net lot %+.2f)", net, SB.lots - SS.lots), net >= 0 ? cB : cS, 9, true);
   y += 20;
   int bw = (W - 12 - 8) / 3;
   Bt("auto", 6, y, bw, 22, autoOn ? "AUTO ON" : "AUTO OFF", autoOn ? cB : cLn, autoOn ? cBg : cTx);
   Bt("mode", 6 + bw + 4, y, bw, 22, mode == MODE_TREND ? "MODE: TREND" : "MODE: BOTH", cLn, cTx);
   Bt("lock", 6 + 2 * (bw + 4), y, bw, 22, "LOCK", cW, cBg);
   y += 26;
   Bt("unlock", 6, y, bw, 22, "UNLOCK", cLn, cTx);
   Bt("cb", 6 + bw + 4, y, bw, 22, "Close BUY", cB, cBg);
   Bt("cs", 6 + 2 * (bw + 4), y, bw, 22, "Close SELL", cS, clrWhite);
   y += 26;
   Bt("ca", 6, y, (W - 16) / 2, 22, "CLOSE ALL", cS, clrWhite);
   Bt("lotmode", 6 + (W - 16) / 2 + 4, y, (W - 16) / 2, 22, rtAuto ? "LOT: AUTO (capital)" : "LOT: FIXED", rtAuto ? cB : cLn, rtAuto ? cBg : cTx);
   y += 28;
   string lab[4];
   string ids[4] = {"tp", "dca", "lot", "max"};
   lab[0] = rtTP > 0 ? StringFormat("TP  +$%.0f (har trade)", rtTP) : "TP  OFF";
   lab[1] = StringFormat("DCA  $%.0f", rtDCA);
   lab[2] = rtAuto ? StringFormat("Lot AUTO %.2f  (0.01 / $%.0f)", CurLot(), rtPer) : StringFormat("Lot FIXED  %.2f", rtLot);
   lab[3] = StringFormat("Max per side  %d", rtMax);
   for(int r = 0; r < 4; r++)
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
   ReadSide(1, SB); ReadSide(-1, SS);
   if(b == "auto") autoOn = !autoOn;
   else if(b == "mode") mode = (mode == MODE_TREND) ? MODE_BOTH : MODE_TREND;
   else if(b == "lock") DoLock();
   else if(b == "unlock") { CloseWhere(0, true); Print("UNLOCK: LOCK positions band"); }
   else if(b == "tpm" || b == "tpp") rtTP = MathMax(0.0, rtTP + (b == "tpp" ? 5.0 : -5.0));
   else if(b == "dcam" || b == "dcap") rtDCA = MathMax(10.0, rtDCA + (b == "dcap" ? 25.0 : -25.0));
   else if(b == "lotmode") rtAuto = !rtAuto;
   else if(b == "lotm" || b == "lotp")
     {
      if(rtAuto) rtPer = MathMax(100.0, rtPer + (b == "lotp" ? -100.0 : 100.0));   // + = zyada lot (kam $ per 0.01)
      else rtLot = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), rtLot + (b == "lotp" ? 0.01 : -0.01));
     }
   else if(b == "maxm" || b == "maxp") rtMax = MathMax(1, rtMax + (b == "maxp" ? 1 : -1));
   else
     {
      string w = b == "cb" ? "BUY" : (b == "cs" ? "SELL" : "SAB");
      if(MessageBox(w + " positions close karein?", "BTC Hedge Scalper", MB_YESNO | MB_ICONWARNING) == IDYES)
         CloseWhere(b == "cb" ? 1 : (b == "cs" ? -1 : 0), false);
     }
   lastDraw = 0;
   Panel();
  }
//+------------------------------------------------------------------+
