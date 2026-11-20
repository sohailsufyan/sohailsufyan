//+------------------------------------------------------------------+
//|                                          GoldDCA_Assistant.mq5   |
//|  Manual trade DCA Assistant (XAUUSD)                             |
//|  - Aap manually BUY/SELL kholo, EA khud trade NAHI kholta        |
//|  - Price har $5 against jaye to usi side ka naya DCA layer       |
//|  - BUY aur SELL side alag-alag basket (hedge bhi chalega)        |
//|  - Exit: average se +$3 par SL breakeven, +$5 par close,         |
//|          backup: +$2 tak aakar +$0.5 par wapas = close           |
//|  - Net close: dono side mila kar profit me = sab close           |
//+------------------------------------------------------------------+
#property copyright "GoldDCA_Assistant"
#property version   "1.10"

#include <Trade/Trade.mqh>

enum ENUM_DCA_LOT { LOT_SAME_AS_FIRST = 0, LOT_FIXED_EACH = 1, LOT_ADD_EACH = 2, LOT_MULTIPLY = 3 };

input group "=== Kaunse trades manage karne hain ==="
input bool            InpManageManual     = true;         // Manual trades (magic 0) manage karo
input bool            InpManageAnyMagic   = false;        // Doosre EA ke trades bhi (dhyan se)
input long            InpMagic            = 999001;       // Assistant ke DCA layers ka magic

input group "=== DCA ==="
input double          InpStepUSD          = 5.0;          // Har $5 against par naya layer
input double          InpStepGrowth       = 1.0;          // Gap growth (1.0 = har baar $5)
input int             InpMaxLayers        = 0;            // Max layers per side (0 = unlimited)
input double          InpMaxSideLots      = 0.0;          // Ek side ka max kul lot (0 = off)
input ENUM_DCA_LOT    InpLotMode          = LOT_SAME_AS_FIRST; // DCA lot kaise
input double          InpFixedLot         = 0.10;         // LOT_FIXED_EACH: har layer ka lot
input double          InpLotAdd           = 0.10;         // LOT_ADD_EACH: pehla lot + ye x layer (6.0, 6.1, 6.2..)
input double          InpLotMult          = 1.2;          // LOT_MULTIPLY: pehla lot x ye^layer
input int             InpMinSecBetween    = 30;           // Do layers ke beech min seconds
input int             InpMaxSpread        = 60;           // Spread isse zyada (points) to DCA nahi

input group "=== Exit (average price se $ doori) ==="
input double          InpTrigger          = 3.0;          // Average se +$3 jaate hi SL breakeven par
input double          InpLock             = 0.0;          // Breakeven ke upar kitna lock (0 = theek average price)
input bool            InpUseTrailing      = false;        // Breakeven ke baad SL price ke peeche chale (trailing)
input double          InpTrailDist        = 2.0;          // Trailing doori (agar ON)
input double          InpTP               = 5.0;          // +$5 par poori side close (0 = TP off). Panel se badal sakte
input bool            InpBackup           = true;         // Backup exit ON
input double          InpBackupArm        = 2.0;          // +$2 tak aaye...
input double          InpBackupExit       = 0.5;          // ...phir +$0.5 par wapas aaye to close
input bool            InpBrokerSLTP       = true;         // Broker par bhi TP / trailing SL lagao

input group "=== Protection ==="
input bool            InpNetClose         = true;         // BUY + SELL dono khule, ek loss me: net profit par sab close
input double          InpNetCloseUSD      = 5.0;          // Net close kam se kam $
input double          InpNetPerLot        = 50.0;         // Ya har 1 lot par $ (jo bada)
input double          InpHardStopUSD      = 0.0;          // Ek side ka loss itne $ ho to close (0 = off)

input group "=== Panel ==="
input int             InpPanelX           = 10;           // Panel X
input int             InpPanelY           = 25;           // Panel Y

//==================== GLOBALS ====================
CTrade   trade;
#define  APFX "GDA_"

struct Side
  {
   int      dir;          // 1 BUY, -1 SELL
   int      count;
   double   lots, avg, lastPrice, firstLot, profit;
   bool     trail;
   double   trailSL, maxMove;
   datetime lastLayer;
   string   why;
   double   next;
  };
Side     S[2];
bool     dcaPaused = false;
double   rtTP = 0, rtTrig = 0, rtStep = 0;     // panel buttons se badalne wale values
string   gvA = "";

//+------------------------------------------------------------------+
int OnInit()
  {
   rtTP = InpTP; rtTrig = InpTrigger; rtStep = InpStepUSD;
   gvA = "GDA_" + _Symbol + "_" + IntegerToString(InpMagic) + "_";
   if(!MQLInfoInteger(MQL_TESTER) && GlobalVariableCheck(gvA + "tp"))
     {
      rtTP = GlobalVariableGet(gvA + "tp"); rtTrig = GlobalVariableGet(gvA + "be");
      rtStep = GlobalVariableGet(gvA + "dca"); dcaPaused = GlobalVariableGet(gvA + "pause") > 0.5;
     }
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFillingBySymbol(_Symbol);
   for(int i = 0; i < 2; i++)
     {
      S[i].dir = (i == 0) ? 1 : -1;
      ResetSide(S[i]);
      S[i].lastLayer = 0;
     }
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("WARNING: Hedging account chahiye - netting par BUY/SELL aapas me cut ho jayenge.");
   PrintFormat("DCA Assistant ready: har $%.1f against par layer. Manually trade kholo.", rtStep);
   EventSetTimer(1);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   ObjectsDeleteAll(0, APFX);
  }

void OnTimer() { DrawPanel(); }

void ResetSide(Side &s)
  {
   s.count = 0; s.lots = 0; s.avg = 0; s.lastPrice = 0; s.firstLot = 0; s.profit = 0;
   s.trail = false; s.trailSL = 0; s.maxMove = 0; s.why = ""; s.next = 0;
  }

//==================== POSITIONS ====================
bool Managed()
  {
   if(PositionGetString(POSITION_SYMBOL) != _Symbol) return false;
   long mg = PositionGetInteger(POSITION_MAGIC);
   if(mg == InpMagic) return true;
   if(mg == 0) return InpManageManual;
   return InpManageAnyMagic;
  }

int PosDir() { return (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1; }

void ReadSide(Side &s)
  {
   bool tr = s.trail; double tsl = s.trailSL, mm = s.maxMove; datetime ll = s.lastLayer;
   int c0 = s.count;
   s.count = 0; s.lots = 0; s.avg = 0; s.lastPrice = 0; s.firstLot = 0; s.profit = 0;
   double pv = 0; datetime oldest = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0 || !Managed() || PosDir() != s.dir) continue;
      double v = PositionGetDouble(POSITION_VOLUME), p = PositionGetDouble(POSITION_PRICE_OPEN);
      datetime t = (datetime)PositionGetInteger(POSITION_TIME);
      s.count++; s.lots += v; pv += v * p;
      s.profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      if(s.lastPrice == 0 || (s.dir == 1 && p < s.lastPrice) || (s.dir == -1 && p > s.lastPrice)) s.lastPrice = p;
      if(oldest == 0 || t < oldest) { oldest = t; s.firstLot = v; }
     }
   if(s.lots > 0) s.avg = pv / s.lots;
   if(s.count == 0) { ResetSide(s); s.lastLayer = ll; return; }
   s.trail = tr; s.trailSL = tsl; s.maxMove = mm; s.lastLayer = ll;
   if(s.count != c0) s.maxMove = 0;        // naya layer / position = naya average
  }

void CloseSide(Side &s, string why)
  {
   PrintFormat("%s side close (%s): %d positions, %.2f lot, P/L %.2f", s.dir == 1 ? "BUY" : "SELL", why, s.count, s.lots, s.profit);
   for(int pass = 0; pass < 3; pass++)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(t == 0 || !Managed() || PosDir() != s.dir) continue;
         if(!PositionSelectByTicket(t)) continue;
         trade.PositionClose(t);
        }
      ReadSide(s);
      if(s.count == 0) break;
     }
   ResetSide(s);
  }

//==================== LOTS ====================
double NormLot(double lot)
  {
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(st <= 0) st = 0.01;
   lot = MathFloor(lot / st + 1e-9) * st;
   lot = MathMax(mn, MathMin(lot, mx));
   return NormalizeDouble(lot, 2);
  }

double NextLot(Side &s)
  {
   int n = s.count;                       // naya layer ka index (pehla = 0)
   switch(InpLotMode)
     {
      case LOT_FIXED_EACH: return NormLot(InpFixedLot);
      case LOT_ADD_EACH:   return NormLot(s.firstLot + InpLotAdd * n);
      case LOT_MULTIPLY:   return NormLot(s.firstLot * MathPow(InpLotMult, n));
      default:             return NormLot(s.firstLot);
     }
  }

//==================== MAIN ====================
void OnTick()
  {
   for(int i = 0; i < 2; i++) ReadSide(S[i]);
   CheckNetClose();
   for(int i = 0; i < 2; i++)
      if(S[i].count > 0) ManageSide(S[i]);
   DrawPanel();
  }

void ManageSide(Side &s)
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double cur  = (s.dir == 1) ? bid : ask;
   double move = (s.dir == 1) ? bid - s.avg : s.avg - ask;
   if(move > s.maxMove) s.maxMove = move;

   //--- exits
   if(InpHardStopUSD > 0 && s.profit <= -InpHardStopUSD) { CloseSide(s, "hard stop"); return; }
   if(InpBackup && !s.trail && s.maxMove >= InpBackupArm && move <= InpBackupExit && s.profit > 0)
     { CloseSide(s, "backup"); return; }
   if(rtTP > 0 && move >= rtTP && s.profit > 0) { CloseSide(s, "TP"); return; }
   if(!s.trail && move >= rtTrig)
     {
      s.trail = true;
      s.trailSL = s.avg + s.dir * InpLock;
      PrintFormat("%s: +$%.1f aaya, SL breakeven%s par (%.2f)", s.dir == 1 ? "BUY" : "SELL", rtTrig,
                  InpLock > 0 ? StringFormat(" +$%.1f", InpLock) : "", s.trailSL);
     }
   if(s.trail)
     {
      double cand = InpUseTrailing ? cur - s.dir * InpTrailDist : s.trailSL;
      if(s.dir == 1 && cand > s.trailSL + 0.1) s.trailSL = cand;
      if(s.dir == -1 && cand < s.trailSL - 0.1) s.trailSL = cand;
      bool hit = (s.dir == 1) ? (bid <= s.trailSL) : (ask >= s.trailSL);
      if(hit) { CloseSide(s, "trailing SL"); return; }
     }
   if(InpBrokerSLTP) SyncSLTP(s);

   //--- DCA
   double step = rtStep * MathPow(InpStepGrowth, MathMax(0, s.count - 1));
   s.next = s.lastPrice - s.dir * step;
   if(dcaPaused) { s.why = "PAUSED"; return; }
   if(s.trail)   { s.why = "breakeven"; return; }
   if(InpMaxLayers > 0 && s.count >= InpMaxLayers) { s.why = "max layers"; return; }
   double lot = NextLot(s);
   if(InpMaxSideLots > 0 && s.lots + lot > InpMaxSideLots + 1e-9) { s.why = "max lots"; return; }
   if(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpread) { s.why = "spread"; return; }
   bool add = (s.dir == 1) ? (ask <= s.next) : (bid >= s.next);
   if(!add) { s.why = StringFormat("waiting $%.0f", step); return; }
   if(TimeCurrent() - s.lastLayer < InpMinSecBetween) { s.why = "gap sec"; return; }

   double m = 0;
   if(OrderCalcMargin(s.dir == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, lot, cur, m) &&
      AccountInfoDouble(ACCOUNT_MARGIN_FREE) < m * 1.2) { s.why = "margin kam"; return; }

   string cm = StringFormat("DCA-A %s L%d", s.dir == 1 ? "B" : "S", s.count + 1);
   bool ok = (s.dir == 1) ? trade.Buy(lot, _Symbol, 0, 0, 0, cm) : trade.Sell(lot, _Symbol, 0, 0, 0, cm);
   if(ok && (trade.ResultRetcode() == TRADE_RETCODE_DONE || trade.ResultRetcode() == TRADE_RETCODE_PLACED))
     {
      s.lastLayer = TimeCurrent();
      s.why = "";
      PrintFormat("%s DCA layer %d: %.2f lot @ %.2f", s.dir == 1 ? "BUY" : "SELL", s.count + 1, lot, trade.ResultPrice());
     }
   else
      s.why = StringFormat("order fail %d", trade.ResultRetcode());
  }

// Sab positions par common TP (average + $5); trailing chale to common SL. Price ke paas ho to purana rehne do.
void SyncSLTP(Side &s)
  {
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   long   lv = MathMax(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL), SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL));
   double minStop = (double)lv * _Point + 5 * _Point;
   double freeze  = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point + 2 * _Point;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double px = (s.dir == 1) ? bid : ask;

   double tp = rtTP > 0 ? NormalizeDouble(s.avg + s.dir * rtTP, digits) : 0;
   double sl = s.trail ? NormalizeDouble(s.trailSL, digits) : 0;
   bool tpOK = tp > 0 && ((s.dir == 1) ? (tp - ask >= minStop) : (bid - tp >= minStop));
   bool slOK = sl > 0 && ((s.dir == 1) ? (bid - sl >= minStop) : (sl - ask >= minStop));

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !Managed() || PosDir() != s.dir) continue;
      double cSL = PositionGetDouble(POSITION_SL), cTP = PositionGetDouble(POSITION_TP);
      if((cSL > 0 && MathAbs(px - cSL) <= freeze) || (cTP > 0 && MathAbs(px - cTP) <= freeze)) continue;
      double nSL = slOK ? sl : cSL, nTP = tpOK ? tp : (rtTP <= 0 ? 0 : cTP);   // TP off = TP hata do
      if(MathAbs(cSL - nSL) < 20 * _Point && MathAbs(cTP - nTP) < 20 * _Point) continue;
      trade.PositionModify(t, nSL, nTP);
     }
  }

void CheckNetClose()
  {
   if(!InpNetClose || S[0].count == 0 || S[1].count == 0) return;
   if(S[0].profit >= 0 && S[1].profit >= 0) return;
   double net = S[0].profit + S[1].profit, lots = S[0].lots + S[1].lots;
   double need = MathMax(InpNetCloseUSD, InpNetPerLot * lots);
   if(net >= need)
     {
      PrintFormat("NET CLOSE: BUY %.2f + SELL %.2f = %.2f >= %.2f", S[0].profit, S[1].profit, net, need);
      CloseSide(S[0], "net close");
      CloseSide(S[1], "net close");
     }
  }

//==================== PANEL ====================
color pBg = C'18,20,32', pCard = C'28,31,48', pLine = C'48,52,78', pTxt = C'225,228,240', pDim = C'140,146,175';
color pBuy = C'38,196,133', pSell = C'239,83,80', pWarn = C'255,183,77';
datetime lastDraw = 0;

void R(string id, int x, int y, int w, int h, color bg)
  {
   string n = APFX + id;
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
     }
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, InpPanelX + x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, InpPanelY + y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, n, OBJPROP_COLOR, pLine);
  }

void T(string id, int x, int y, string txt, color c, int size = 9, bool bold = false)
  {
   string n = APFX + id;
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
     }
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, InpPanelX + x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, InpPanelY + y);
   ObjectSetString(0, n, OBJPROP_TEXT, txt);
   ObjectSetString(0, n, OBJPROP_FONT, bold ? "Segoe UI Semibold" : "Segoe UI");
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
  }

void B(string id, int x, int y, int w, int h, string txt, color bg, color fg)
  {
   string n = APFX + id;
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
      ObjectSetString(0, n, OBJPROP_FONT, "Segoe UI Semibold");
      ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 8);
     }
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, InpPanelX + x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, InpPanelY + y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
   ObjectSetString(0, n, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, n, OBJPROP_COLOR, fg);
   ObjectSetInteger(0, n, OBJPROP_STATE, false);
  }

void DrawPanel()
  {
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return;
   if(TimeLocal() == lastDraw) return;
   lastDraw = TimeLocal();
   int W = 330, y = 0;
   R("bg", 0, 0, W, 200, pBg);
   T("title", 10, 6, "DCA ASSISTANT  (manual trades)", pTxt, 10, true);
   T("sub", 10, 24, StringFormat("DCA har $%.1f  |  +$%.1f par SL breakeven  |  %s", rtStep, rtTrig,
                                 rtTP > 0 ? StringFormat("TP +$%.1f", rtTP) : "TP OFF"), pDim, 8);
   y = 44;
   for(int i = 0; i < 2; i++)
     {
      Side s = S[i];
      string k = IntegerToString(i);
      color sc = s.dir == 1 ? pBuy : pSell;
      R("c" + k, 6, y, W - 12, 46, pCard);
      T("n" + k, 14, y + 4, s.dir == 1 ? "BUY SIDE" : "SELL SIDE", sc, 9, true);
      if(s.count == 0)
        {
         T("i" + k, 14, y + 24, "Koi trade nahi - manually kholo", pDim, 8);
         T("s" + k, 200, y + 4, "", pDim, 8);
        }
      else
        {
         T("s" + k, 200, y + 4, StringFormat("P/L %+.2f", s.profit), s.profit >= 0 ? pBuy : pSell, 9, true);
         string st = s.trail ? StringFormat("SL BREAKEVEN %.2f", s.trailSL) : StringFormat("next DCA %.2f (%s)", s.next, s.why == "" ? "ready" : s.why);
         T("i" + k, 14, y + 24, StringFormat("%d pos | %.2f lot | avg %.2f | %s", s.count, s.lots, s.avg, st), pTxt, 8);
        }
      y += 50;
     }
   double net = S[0].profit + S[1].profit;
   T("net", 10, y + 2, StringFormat("NET: %+.2f   |   DCA: %s", net, dcaPaused ? "PAUSED" : "ON"), net >= 0 ? pBuy : pSell, 9, true);
   y += 22;
   int bw = (W - 12 - 8) / 3;
   B("btn_cb", 6, y, bw, 22, "Close BUY", pBuy, pBg);
   B("btn_cs", 6 + bw + 4, y, bw, 22, "Close SELL", pSell, clrWhite);
   B("btn_ca", 6 + 2 * (bw + 4), y, bw, 22, "Close ALL", pWarn, pBg);
   y += 26;
   B("btn_p", 6, y, W - 12, 22, dcaPaused ? "RESUME DCA" : "PAUSE DCA", dcaPaused ? pWarn : pLine, dcaPaused ? pBg : pTxt);
   y += 28;
   // TP / Breakeven / DCA setting buttons
   string lab[3]; string ids[3] = {"tp", "be", "dca"};
   lab[0] = rtTP > 0 ? StringFormat("TP  +$%.1f", rtTP) : "TP  OFF";
   lab[1] = StringFormat("Breakeven  +$%.1f", rtTrig);
   lab[2] = StringFormat("DCA  $%.1f", rtStep);
   for(int r = 0; r < 3; r++)
     {
      R("row" + IntegerToString(r), 6, y, W - 12, 24, pCard);
      B("btn_" + ids[r] + "m", 10, y + 2, 34, 20, "-", pLine, pTxt);
      T("lab" + IntegerToString(r), 54, y + 5, lab[r], (r == 0 && rtTP <= 0) ? pWarn : pTxt, 9, true);
      B("btn_" + ids[r] + "p", W - 48, y + 2, 34, 20, "+", pLine, pTxt);
      y += 28;
     }
   ObjectSetInteger(0, APFX + "bg", OBJPROP_YSIZE, y);
   ChartRedraw();
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_OBJECT_CLICK || StringFind(sparam, APFX + "btn_") != 0) return;
   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   string b = StringSubstr(sparam, StringLen(APFX + "btn_"));
   if(b == "p") { dcaPaused = !dcaPaused; Print(dcaPaused ? "DCA PAUSED" : "DCA RESUMED"); }
   else if(b == "tpm" || b == "tpp")
     {
      rtTP = MathMax(0.0, MathMin(100.0, rtTP + (b == "tpp" ? 0.5 : -0.5)));
      PrintFormat("TP ab %s", rtTP > 0 ? StringFormat("+$%.1f", rtTP) : "OFF");
     }
   else if(b == "bem" || b == "bep")
     {
      rtTrig = MathMax(0.5, MathMin(100.0, rtTrig + (b == "bep" ? 0.5 : -0.5)));
      PrintFormat("Breakeven trigger ab +$%.1f", rtTrig);
     }
   else if(b == "dcam" || b == "dcap")
     {
      rtStep = MathMax(1.0, MathMin(100.0, rtStep + (b == "dcap" ? 1.0 : -1.0)));
      PrintFormat("DCA gap ab $%.1f", rtStep);
     }
   else
     {
      string what = b == "cb" ? "BUY side" : (b == "cs" ? "SELL side" : "BUY + SELL dono");
      if(MessageBox(what + " ke saare trades close karein?", "DCA Assistant", MB_YESNO | MB_ICONWARNING) == IDYES)
        {
         for(int i = 0; i < 2; i++) ReadSide(S[i]);
         if(b == "cb" || b == "ca") CloseSide(S[0], "button");
         if(b == "cs" || b == "ca") CloseSide(S[1], "button");
        }
     }
   if(!MQLInfoInteger(MQL_TESTER))
     {
      GlobalVariableSet(gvA + "tp", rtTP); GlobalVariableSet(gvA + "be", rtTrig);
      GlobalVariableSet(gvA + "dca", rtStep); GlobalVariableSet(gvA + "pause", dcaPaused ? 1 : 0);
     }
   lastDraw = 0;
   DrawPanel();
  }
//+------------------------------------------------------------------+
