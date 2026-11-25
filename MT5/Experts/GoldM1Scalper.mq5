//+------------------------------------------------------------------+
//|                                              GoldM1Scalper.mq5   |
//|  XAUUSD M1 scalper  v1.00  (GoldHedgeScalper v1.22, bina hedge)   |
//|  - Har naye M1 candle par EMA trend ki direction me trade         |
//|    (ya BOTH mode: BUY + SELL dono)                                |
//|  - Har position ka apna chhota TP (+$1), $3 against par DCA       |
//|  - Side +$1.5 chale to SL breakeven +$0.50                        |
//|  - Pair Close: phansa trade + profit wale trades saath band       |
//|  - Koi hedge nahi, koi LOCK nahi                                  |
//|  - Badi news ke aas-paas naya trade / DCA nahi                    |
//|  - Har group close sirf total profit me                           |
//|  - Manual trade ka apna SL/TP waisa hi rahe                       |
//+------------------------------------------------------------------+
#property copyright "GoldM1Scalper"
#property version   "1.00"

#include <Trade/Trade.mqh>

enum ENUM_ENTRY_MODE { MODE_TREND = 0, MODE_BOTH = 1 };

input group "=== Entry (har M1 candle) ==="
input bool            InpAutoOn           = true;         // Auto entry ON
input ENUM_ENTRY_MODE InpMode             = MODE_TREND;   // TREND = EMA direction, BOTH = BUY + SELL dono
input ENUM_TIMEFRAMES InpSigTF            = PERIOD_M1;    // Entry candle timeframe
input int             InpFastEMA          = 21;           // Fast EMA
input int             InpSlowEMA          = 50;           // Slow EMA
input bool            InpUseHTF           = true;         // Bada trend bhi same ho (H1 EMA50)
input ENUM_TIMEFRAMES InpHTF              = PERIOD_H1;    // Bada trend TF (H1 rakho, M1 nahi)
input bool            InpAutoLot          = true;         // Lot capital ke hisaab se khud (AUTO)
input double          InpBalancePer001    = 1000.0;       // AUTO: har itne $ balance par 0.01 lot
input double          InpLot              = 0.01;         // FIXED: har trade ka lot
input int             InpMaxPerSide       = 5;            // Ek side me max positions (DCA milake)
input bool            InpSessionOnly      = true;         // Sirf London + New York
input int             InpGMTOffset        = 2;            // Server time = GMT + ?
input int             InpMaxSpread        = 40;           // Max spread (cents, 40 = $0.40)

input group "=== Exit (turant profit) ==="
input double          InpTP               = 1.0;          // Har position ka TP: entry se +$1
input double          InpBETrigger        = 1.5;          // Side average se +$1.5 par sab positions ka SL breakeven
input double          InpBELock           = 0.5;          // Breakeven = average + $0.50 (loss na ho)
input bool            InpNetClose         = true;         // BUY + SELL dono khule, sabka total profit me = sab close
input double          InpNetCloseUSD      = 5.0;          // Net kam se kam $

input group "=== DCA ==="
input bool            InpDCA              = true;         // DCA ON
input double          InpDCAStep          = 3.0;          // Side ki sabse kharab position se $3 against par naya trade

input group "=== Pair Close ==="
input bool            InpPairClose        = true;         // Phansa trade + profit wale trades saath band
input double          InpPairMinUSD       = 0.20;         // Sabka total kam se kam +$ (loss me kabhi nahi)
input int             InpPairMinPos       = 3;            // Kam se kam itni positions khuli hon
input int             InpPairMaxWin       = 3;            // 1 loss wale ko max itne profit wale trades se cover

input group "=== News filter ==="
input bool            InpNewsFilter       = true;         // Badi (high impact) news ke aas-paas naya trade / DCA nahi
input int             InpNewsBeforeMin    = 15;           // News se itne min pehle
input int             InpNewsAfterMin     = 15;           // News ke itne min baad tak
input string          InpNewsCurrency     = "USD";        // News currency

input group "=== Protection ==="
input double          InpMinMarginLevel   = 300.0;        // Margin level isse kam = naye trade/DCA band
input double          InpMinFreeMarginPct = 30.0;         // Free margin equity ka isse kam = naye trade band
input bool            InpManageManual     = true;         // Manual trades (magic 0) bhi manage (TP/BE/net/pair)
input bool            InpKeepManualSLTP   = true;         // Manual trade ka apna SL/TP mat badlo (BE sirf profit ki taraf)
input long            InpMagic            = 777555;       // Magic (GoldHedgeScalper wala hi, taaki khule trade chalte rahein)

input group "=== Panel ==="
input int             InpPanelX           = 10;
input int             InpPanelY           = 25;

//==================== GLOBALS ====================
CTrade   trade;
int      hF = INVALID_HANDLE, hS = INVALID_HANDLE, hH = INVALID_HANDLE;
datetime lastBar = 0;
bool     autoOn, rtAuto, rtPair;
int      mode, rtMax, curTrend = 0, oldN = 0;
double   rtTP, rtDCA, rtLot, rtPer;
#define  PFX "GMS_"

struct SideInfo { int n; double lots, avg, worst, profit; bool be; double beSL; };
SideInfo SB, SS;                 // BUY side, SELL side (AUTO / DCA / manual)
double   allProfit, buyLotsAll, sellLotsAll;
bool     anyLoss;
bool     newsNow = false;
datetime lastNewsCheck = 0;

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
   rtAuto = InpAutoLot; rtPer = InpBalancePer001; rtPair = InpPairClose;
   SB.be = false; SS.be = false; SB.beSL = 0; SS.beSL = 0; SB.n = 0; SS.n = 0;
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("WARNING: Hedging account chahiye (har DCA alag position).");
   if(InpUseHTF && PeriodSeconds(InpHTF) <= PeriodSeconds(InpSigTF))
      Print("WARNING: Bada trend TF entry TF se bada rakho (H1), warna trend filter kaam nahi karega.");
   ReadAll();
   if(oldN > 0)
      PrintFormat("NOTE: purane version ke %d HEDGE/LOCK trade khule hain. Ye EA unhe nahi chhedta, khud band karein.", oldN);
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
// Purane GoldHedgeScalper ke HEDGE / LOCK trade: ye EA unhe nahi chhedta
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
int    Dir()      { return PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1; }
double PL()       { return PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP); }
double Spread()   { return (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / 0.01; }
double VolMin()   { return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN); }
double B1(int h, int shift) { double a[]; ArraySetAsSeries(a, true); return CopyBuffer(h, 0, shift, 1, a) == 1 ? a[0] : 0; }

double NormLot(double lot)
  {
   double mn = VolMin(), mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
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
      s.profit += PL();
      if(s.worst == 0 || (dir == 1 && p < s.worst) || (dir == -1 && p > s.worst)) s.worst = p;
     }
   if(s.lots > 0) s.avg = pv / s.lots;
   s.be = be; s.beSL = bsl;
   if(s.n == 0 || s.n > n0) { s.be = false; s.beSL = 0; }   // nayi position = naya average
  }

void ReadAll()
  {
   ReadSide(1, SB); ReadSide(-1, SS);
   allProfit = 0; buyLotsAll = 0; sellLotsAll = 0; anyLoss = false; oldN = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(OldHedge()) { oldN++; continue; }
      if(!Mine()) continue;
      double v = PositionGetDouble(POSITION_VOLUME), p = PL();
      allProfit += p; if(p < 0) anyLoss = true;
      if(Dir() == 1) buyLotsAll += v; else sellLotsAll += v;
     }
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
   if(!rtAuto) return NormLot(rtLot);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   return NormLot(0.01 * MathFloor(bal / MathMax(1.0, rtPer)));
  }

bool Open(int dir, double lot, string tag)
  {
   double px = dir == 1 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double tp = rtTP > 0 ? NormalizeDouble(px + dir * rtTP, dg) : 0;
   bool ok = dir == 1 ? trade.Buy(lot, _Symbol, 0, 0, tp, "GHS " + tag) : trade.Sell(lot, _Symbol, 0, 0, tp, "GHS " + tag);
   if(!ok || (trade.ResultRetcode() != TRADE_RETCODE_DONE && trade.ResultRetcode() != TRADE_RETCODE_PLACED))
     {
      PrintFormat("Order fail %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
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

//==================== PAIR CLOSE ====================
// Sabse zyada loss wala phansa trade + sabse zyada profit wale trades: total >= min tabhi band
bool PairClose()
  {
   if(!rtPair) return false;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int cnt = 0; ulong wT = 0; double wP = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !Mine()) continue;
      int d = Dir();
      cnt++;
      double p = PL(), op = PositionGetDouble(POSITION_PRICE_OPEN);
      bool stuck = d == 1 ? op - bid >= rtDCA : ask - op >= rtDCA;   // kam se kam 1 DCA step against
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

//==================== MAIN ====================
void OnTick()
  {
   ReadAll();
   UpdateNews();
   curTrend = Trend();
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   //--- 1) Net close: BUY + SELL dono khule, sabka total profit me (koi loss me ho)
   if(InpNetClose && buyLotsAll > 0 && sellLotsAll > 0 && anyLoss && allProfit >= InpNetCloseUSD)
     {
      PrintFormat("NET CLOSE: total %+.2f", allProfit);
      CloseWhere(0);
      return;
     }

   //--- 2) Pair close: phansa trade profit wale trades ke saath nikle
   if(PairClose()) { Panel(); return; }

   //--- 3) TP + breakeven
   if(ManageStops(1, SB, bid, ask) || ManageStops(-1, SS, bid, ask)) { Panel(); return; }

   bool roomOK = MarginOK() && Spread() <= InpMaxSpread && !newsNow;

   //--- 4) DCA: side ki sabse kharab position se $X against
   if(InpDCA && roomOK)
     {
      if(SB.n > 0 && SB.n < rtMax && !SB.be && ask <= SB.worst - rtDCA) Open(1, CurLot(), "DCA");
      if(SS.n > 0 && SS.n < rtMax && !SS.be && bid >= SS.worst + rtDCA) Open(-1, CurLot(), "DCA");
     }

   //--- 5) Har naye candle par entry
   datetime bar = iTime(_Symbol, InpSigTF, 0);
   if(bar != lastBar)
     {
      lastBar = bar;
      if(autoOn && roomOK && SessionOK())
        {
         bool wantB = (mode == MODE_BOTH) || curTrend == 1;
         bool wantS = (mode == MODE_BOTH) || curTrend == -1;
         if(wantB && SB.n < rtMax && !SB.be) Open(1, CurLot(), "AUTO");
         if(wantS && SS.n < rtMax && !SS.be) Open(-1, CurLot(), "AUTO");
        }
     }
   Panel();
  }

// TP har position par; side +$X chale to sab ka SL = average + lock
bool ManageStops(int dir, SideInfo &s, double bid, double ask)
  {
   if(s.n == 0) return false;
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
      double eaTP = rtTP > 0 ? NormalizeDouble(op + dir * rtTP, dg) : 0;
      bool userTP = manual && InpKeepManualSLTP && cTP > 0 && MathAbs(cTP - eaTP) >= 10 * _Point;
      if(!userTP && eaTP > 0 && ((dir == 1 && bid >= eaTP) || (dir == -1 && ask <= eaTP)))
        { trade.PositionClose(t); continue; }       // price TP se aage nikal gaya (TP laga nahi tha) = profit book
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
void OnOff(string id, int x, int y, int w, string name, bool on)
  {
   Bt(id, x, y, w, 22, name + (on ? ": ON" : ": OFF"), on ? cB : cLn, on ? cBg : cTx);
  }

void Panel()
  {
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return;
   if(TimeLocal() == lastDraw) return;
   lastDraw = TimeLocal();
   int W = 330, y;
   Rc("bg", 0, 0, W, 100, cBg);
   Tx("ti", 10, 6, "GOLD M1 SCALPER  (bina hedge)", cTx, 10, true);
   double ml = AccountInfoDouble(ACCOUNT_MARGIN) > 0 ? AccountInfoDouble(ACCOUNT_MARGIN_LEVEL) : 0;
   Tx("st", 10, 24, StringFormat("Trend: %s | Margin %s | Spread %.0f%s", curTrend == 1 ? "UP" : (curTrend == -1 ? "DOWN" : "SIDE"),
      ml > 0 ? StringFormat("%.0f%%", ml) : "-", Spread(), newsNow ? "  |  NEWS" : ""), MarginOK() && !newsNow ? cDm : cS, 8);
   y = 44;
   Rc("cb", 6, y, W - 12, 22, cCard);
   Tx("lb", 12, y + 4, StringFormat("BUY  %d pos | %.2f lot | P/L %+.2f%s", SB.n, SB.lots, SB.profit, SB.be ? " | BE" : ""), cB, 8, true);
   y += 24;
   Rc("cs", 6, y, W - 12, 22, cCard);
   Tx("ls", 12, y + 4, StringFormat("SELL %d pos | %.2f lot | P/L %+.2f%s", SS.n, SS.lots, SS.profit, SS.be ? " | BE" : ""), cS, 8, true);
   y += 26;
   Tx("net", 10, y, StringFormat("NET %+.2f", allProfit), allProfit >= 0 ? cB : cS, 9, true);
   y += 18;
   if(oldN > 0)
     {
      Tx("old", 10, y, StringFormat("Purane HEDGE/LOCK: %d trade (EA nahi chhedta, khud band karein)", oldN), cW, 8, true);
      y += 16;
     }
   else ObjectDelete(0, PFX + "old");
   y += 4;
   int bw = (W - 12 - 8) / 3;
   Bt("auto", 6, y, bw, 22, autoOn ? "AUTO ON" : "AUTO OFF", autoOn ? cB : cLn, autoOn ? cBg : cTx);
   Bt("mode", 6 + bw + 4, y, bw, 22, mode == MODE_TREND ? "MODE: TREND" : "MODE: BOTH", cLn, cTx);
   OnOff("pair", 6 + 2 * (bw + 4), y, bw, "PAIR", rtPair);
   y += 26;
   Bt("cb", 6, y, bw, 22, "Close BUY", cB, cBg);
   Bt("cs", 6 + bw + 4, y, bw, 22, "Close SELL", cS, clrWhite);
   Bt("ca", 6 + 2 * (bw + 4), y, bw, 22, "CLOSE ALL", cS, clrWhite);
   y += 26;
   Bt("lotmode", 6, y, W - 12, 22, rtAuto ? "LOT: AUTO (capital)" : "LOT: FIXED", rtAuto ? cB : cLn, rtAuto ? cBg : cTx);
   y += 28;
   string lab[4];
   string ids[4] = {"tp", "dca", "lot", "max"};
   lab[0] = rtTP > 0 ? StringFormat("TP  +$%.1f (har trade)", rtTP) : "TP  OFF";
   lab[1] = StringFormat("DCA  $%.1f", rtDCA);
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
   ReadAll();
   curTrend = Trend();
   if(b == "auto") autoOn = !autoOn;
   else if(b == "mode") mode = (mode == MODE_TREND) ? MODE_BOTH : MODE_TREND;
   else if(b == "pair") rtPair = !rtPair;
   else if(b == "tpm" || b == "tpp") rtTP = MathMax(0.0, rtTP + (b == "tpp" ? 0.1 : -0.1));
   else if(b == "dcam" || b == "dcap") rtDCA = MathMax(0.5, rtDCA + (b == "dcap" ? 0.5 : -0.5));
   else if(b == "lotmode") rtAuto = !rtAuto;
   else if(b == "lotm" || b == "lotp")
     {
      if(rtAuto) rtPer = MathMax(100.0, rtPer + (b == "lotp" ? -100.0 : 100.0));   // + = zyada lot (kam $ per 0.01)
      else rtLot = MathMax(VolMin(), rtLot + (b == "lotp" ? 0.01 : -0.01));
     }
   else if(b == "maxm" || b == "maxp") rtMax = MathMax(1, rtMax + (b == "maxp" ? 1 : -1));
   else if(b == "cb" || b == "cs" || b == "ca")
     {
      string w = b == "cb" ? "BUY" : (b == "cs" ? "SELL" : "SAB");
      if(MessageBox(w + " positions close karein?", "Gold M1 Scalper", MB_YESNO | MB_ICONWARNING) == IDYES)
         CloseWhere(b == "ca" ? 0 : (b == "cb" ? 1 : -1));
     }
   lastDraw = 0;
   Panel();
  }
//+------------------------------------------------------------------+
