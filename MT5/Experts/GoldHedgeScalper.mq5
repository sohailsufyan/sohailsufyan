//+------------------------------------------------------------------+
//|                                           GoldHedgeScalper.mq5   |
//|  XAUUSD M1 hedge scalper  v1.24                                   |
//|  - Har naye M1 candle par EMA trend ki direction me trade         |
//|    + filters: pullback (EMA21 ke paas), RSI, ADX, entry gap      |
//|    + High-probability score 0-5: zyada lot + profit me legs       |
//|    (ya BOTH mode: BUY + SELL dono)                                |
//|  - Har position ka apna chhota TP (+$1), $3 against par DCA       |
//|  - Side +$1.5 chale to SL breakeven +$0.50                        |
//|  - Pair Close: phansa trade + profit wale trades saath band       |
//|  - Recovery Hedge: side phanse + M1 trend ulta (ya loss 5%+)      |
//|    = 50% hedge (max 100%), do step me (25% + 25%), profit lock,    |
//|    price wapas aaye to hedge dheere-dheere chhota (total plus me)   |
//|  - Auto LOCK: margin kam ya badi news = net lot 0                 |
//|  - Har group close sirf total profit me                           |
//|  - Manual trade ka apna SL/TP waisa hi rahe                       |
//+------------------------------------------------------------------+
#property copyright "GoldHedgeScalper"
#property version   "1.24"

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
input bool            InpNetClose         = true;         // Sab trades ka total profit me = sab close
input double          InpNetCloseUSD      = 5.0;          // Net kam se kam $

input group "=== DCA ==="
input bool            InpDCA              = true;         // DCA ON
input double          InpDCAStep          = 3.0;          // Side ki sabse kharab position se $3 against par naya trade

input group "=== Pair Close ==="
input bool            InpPairClose        = true;         // Phansa trade + profit wale trades saath band
input double          InpPairMinUSD       = 0.20;         // Sabka total kam se kam +$ (loss me kabhi nahi)
input int             InpPairMinPos       = 3;            // Kam se kam itni positions khuli hon
input int             InpPairMaxWin       = 3;            // 1 loss wale ko max itne profit wale trades se cover

input group "=== Recovery Hedge ==="
input bool            InpRecHedge         = true;         // Side phanse + trend ulta = hedge
input double          InpHedgePct         = 50.0;         // Hedge lot = phansi side ke lot ka % (max 100)
input int             InpRecLayers        = 3;            // Side me itni positions ho jayein
input double          InpRecLossPct       = 3.0;          // ya side ka loss balance ka itna % (0 = off)
input double          InpHedgeCloseUSD    = 1.0;          // Side + hedge total itna +$ = dono band
input int             InpHedgeCoolMin     = 15;           // Hedge band hone ke baad itne min naya hedge nahi
input bool            InpHedgeFastTrend   = true;         // Hedge ke liye sirf M1 trend dekho (H1 ka intezaar nahi)
input double          InpRecHardPct       = 5.0;          // Side ka loss balance ka itna % = hedge (M1 side ke favour me na ho) (0 = off)
input bool            InpHedgeSteps       = true;         // Step hedge: pehle aadha, price 1 DCA step aur gire to baaki
input bool            InpHedgeReduce      = true;         // Smart hedge kam: profit wala trade + hedge ka hissa saath band (total plus)

input group "=== Entry filters (TREND mode) ==="
input bool            InpUseFilters       = true;         // Filters ON (panel button se bhi)
input bool            InpUsePullback      = true;         // Pullback: price EMA21 ke paas ho tabhi entry (bhaagte price par nahi)
input double          InpPullbackATR      = 1.0;          // EMA21 se max doori = itne ATR(14)
input bool            InpUseRSI           = true;         // RSI filter
input int             InpRSIPeriod        = 14;           // RSI period
input double          InpRSIBuyMax        = 70.0;         // RSI isse upar = BUY nahi (overbought)
input double          InpRSISellMin       = 30.0;         // RSI isse neeche = SELL nahi (oversold)
input bool            InpUseADX           = true;         // ADX filter: side-ways market me entry nahi
input ENUM_TIMEFRAMES InpADXTF            = PERIOD_M15;   // ADX timeframe
input double          InpADXMin           = 20.0;         // ADX isse kam = entry nahi
input int             InpMinGapMin        = 3;            // Ek side me 2 AUTO entry ke beech kam se kam itne minute (BOTH mode me bhi)

input group "=== High probability: zyada lot + legs (TREND mode) ==="
input bool            InpBoostOn          = true;         // HP score acha ho to lot badhao
input int             InpBoostScore       = 4;            // Score (0-5) itna ya zyada = High probability
input double          InpBoostMult        = 1.5;          // Score 4: lot x
input double          InpBoostMult5       = 2.0;          // Score 5: lot x
input bool            InpLegsOn           = true;         // Profit me chal rahi side me naye legs (pyramiding)
input int             InpMaxLegs          = 2;            // Ek side me max profit legs
input double          InpLegStepTP        = 0.5;          // Sabse achhi entry se itne x TP aage jaye tab naya leg
input double          InpBoostMaxDD       = 3.0;          // Account DD isse zyada (%) = boost/legs band

input group "=== Auto LOCK ==="
input bool            InpAutoLock         = true;         // Auto LOCK ON
input double          InpLockMarginLevel  = 200.0;        // Margin level isse kam = auto LOCK
input bool            InpNewsLock         = true;         // Badi (high impact) news se pehle LOCK
input int             InpNewsBeforeMin    = 15;           // News se itne min pehle
input int             InpNewsAfterMin     = 15;           // News ke itne min baad tak
input string          InpNewsCurrency     = "USD";        // News currency
input int             InpLockMinMinutes   = 15;           // Auto UNLOCK se pehle kam se kam itne min lock
input double          InpUnlockMinUSD     = 0.20;         // UNLOCK tabhi jab band hone wale trades ka total +$ ho

input group "=== Protection ==="
input double          InpMinMarginLevel   = 300.0;        // Margin level isse kam = naye trade/DCA band
input double          InpMinFreeMarginPct = 30.0;         // Free margin equity ka isse kam = naye trade band
input bool            InpManageManual     = true;         // Manual trades (magic 0) bhi manage (TP/BE/net/hedge)
input bool            InpKeepManualSLTP   = true;         // Manual trade ka apna SL/TP mat badlo (BE sirf profit ki taraf)
input long            InpMagic            = 777555;       // Magic

input group "=== Panel ==="
input int             InpPanelX           = 10;
input int             InpPanelY           = 25;

//==================== GLOBALS ====================
CTrade   trade;
int      hF = INVALID_HANDLE, hS = INVALID_HANDLE, hH = INVALID_HANDLE;
int      hRSI = INVALID_HANDLE, hATR = INVALID_HANDLE, hADX = INVALID_HANDLE, hH4 = INVALID_HANDLE;
datetime lastBar = 0;
bool     autoOn, rtAuto, rtHedge, rtPair, rtAutoLock, rtFilter, rtBoost, rtLegs;
int      mode, rtMax, curTrend = 0, curFast = 0;
double   rtTP, rtDCA, rtLot, rtPer, rtHedgePct;
#define  PFX "GHS_"

struct SideInfo { int n, legs; double lots, avg, worst, best, profit; bool be; double beSL; };
struct Grp      { int n; double lots, profit, pv; };
SideInfo SB, SS;                 // normal trades (AUTO / DCA / manual)
Grp      HB, HS, LK;             // HB = BUY side ka hedge (SELL), HS = SELL side ka hedge (BUY), LK = LOCK trades
double   allProfit, buyLotsAll, sellLotsAll;
bool     anyLoss;
datetime hedgeClosed[2];         // 0 = BUY side, 1 = SELL side
datetime lastAuto[2];            // aakhri AUTO entry ka time (0 = BUY, 1 = SELL)
string   entryWhy = "-";         // panel: entry kyun hui / kyun ruki
bool     hedgeBE[2];             // hedge ka profit lock ON
int      lockReason = 0;         // 0 none, 1 margin, 2 news, 3 manual
datetime lockTime = 0;
bool     newsNow = false;
datetime lastNewsCheck = 0;
string   gvLock;

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFillingBySymbol(_Symbol);
   hF = iMA(_Symbol, InpSigTF, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hS = iMA(_Symbol, InpSigTF, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hH = iMA(_Symbol, InpHTF, 50, 0, MODE_EMA, PRICE_CLOSE);
   hRSI = iRSI(_Symbol, InpSigTF, InpRSIPeriod, PRICE_CLOSE);
   hATR = iATR(_Symbol, InpSigTF, 14);
   hADX = iADX(_Symbol, InpADXTF, 14);
   hH4  = iMA(_Symbol, PERIOD_H4, 50, 0, MODE_EMA, PRICE_CLOSE);
   if(hF == INVALID_HANDLE || hS == INVALID_HANDLE || hH == INVALID_HANDLE ||
      hRSI == INVALID_HANDLE || hATR == INVALID_HANDLE || hADX == INVALID_HANDLE || hH4 == INVALID_HANDLE) return(INIT_FAILED);
   autoOn = InpAutoOn; mode = InpMode; rtTP = InpTP; rtDCA = InpDCAStep; rtLot = InpLot; rtMax = InpMaxPerSide;
   rtAuto = InpAutoLot; rtPer = InpBalancePer001;
   rtHedge = InpRecHedge; rtPair = InpPairClose; rtAutoLock = InpAutoLock; rtFilter = InpUseFilters;
   rtBoost = InpBoostOn; rtLegs = InpLegsOn;
   lastAuto[0] = 0; lastAuto[1] = 0;
   rtHedgePct = MathMax(10.0, MathMin(100.0, InpHedgePct));
   SB.be = false; SS.be = false; SB.beSL = 0; SS.beSL = 0; SB.n = 0; SS.n = 0; SB.legs = 0; SS.legs = 0;
   hedgeClosed[0] = 0; hedgeClosed[1] = 0; hedgeBE[0] = false; hedgeBE[1] = false;
   gvLock = PFX + _Symbol + "_" + IntegerToString(InpMagic) + "_lock";
   if(GlobalVariableCheck(gvLock + "R"))
     {
      lockReason = (int)GlobalVariableGet(gvLock + "R");
      lockTime   = (datetime)(long)GlobalVariableGet(gvLock + "T");
     }
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("WARNING: Hedging account chahiye.");
   if(InpUseHTF && PeriodSeconds(InpHTF) <= PeriodSeconds(InpSigTF))
      Print("WARNING: Bada trend TF entry TF se bada rakho (H1), warna trend filter kaam nahi karega.");
   EventSetTimer(1);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int r)
  {
   EventKillTimer();
   IndicatorRelease(hF); IndicatorRelease(hS); IndicatorRelease(hH);
   IndicatorRelease(hRSI); IndicatorRelease(hATR); IndicatorRelease(hADX); IndicatorRelease(hH4);
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
double PL()       { return PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP); }
double Spread()   { return (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / 0.01; }
double VolMin()   { return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN); }
double B1(int h, int shift) { double a[]; ArraySetAsSeries(a, true); return CopyBuffer(h, 0, shift, 1, a) == 1 ? a[0] : 0; }

// 0 = normal (AUTO / DCA / manual), 1 = HEDGE, 2 = LOCK  (sirf EA ke apne trades)
int Kind()
  {
   if(PositionGetInteger(POSITION_MAGIC) != InpMagic) return 0;
   string c = PositionGetString(POSITION_COMMENT);
   if(StringFind(c, "LOCK") >= 0)  return 2;
   if(StringFind(c, "HEDGE") >= 0) return 1;
   return 0;
  }

double NormLot(double lot)
  {
   double mn = VolMin(), mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP); if(st <= 0) st = 0.01;
   lot = MathFloor(lot / st + 1e-9) * st;
   return NormalizeDouble(MathMax(mn, MathMin(lot, mx)), 2);
  }

void ZeroG(Grp &g) { g.n = 0; g.lots = 0; g.profit = 0; g.pv = 0; }
void AddG(Grp &g, double v, double p, double op) { g.n++; g.lots += v; g.profit += p; g.pv += v * op; }
double GAvg(Grp &g) { return g.lots > 0 ? g.pv / g.lots : 0; }

void ReadSide(int dir, SideInfo &s)
  {
   bool be = s.be; double bsl = s.beSL; int n0 = s.n;
   s.n = 0; s.legs = 0; s.lots = 0; s.avg = 0; s.worst = 0; s.best = 0; s.profit = 0;
   double pv = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0 || !Mine() || Dir() != dir || Kind() != 0) continue;
      double v = PositionGetDouble(POSITION_VOLUME), p = PositionGetDouble(POSITION_PRICE_OPEN);
      s.n++; s.lots += v; pv += v * p;
      s.profit += PL();
      if(s.worst == 0 || (dir == 1 && p < s.worst) || (dir == -1 && p > s.worst)) s.worst = p;
      if(s.best == 0 || (dir == 1 && p > s.best) || (dir == -1 && p < s.best)) s.best = p;
      if(StringFind(PositionGetString(POSITION_COMMENT), "LEG") >= 0) s.legs++;
     }
   if(s.lots > 0) s.avg = pv / s.lots;
   s.be = be; s.beSL = bsl;
   if(s.n == 0 || s.n > n0) { s.be = false; s.beSL = 0; }   // nayi position = naya average
  }

void ReadAll()
  {
   ReadSide(1, SB); ReadSide(-1, SS);
   ZeroG(HB); ZeroG(HS); ZeroG(LK);
   allProfit = 0; buyLotsAll = 0; sellLotsAll = 0; anyLoss = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0 || !Mine()) continue;
      double v = PositionGetDouble(POSITION_VOLUME), p = PL();
      int d = Dir(), k = Kind();
      allProfit += p; if(p < 0) anyLoss = true;
      if(d == 1) buyLotsAll += v; else sellLotsAll += v;
      double op = PositionGetDouble(POSITION_PRICE_OPEN);
      if(k == 2) AddG(LK, v, p, op);
      else if(k == 1) { if(d == -1) AddG(HB, v, p, op); else AddG(HS, v, p, op); }
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

// Sirf entry TF (M1) ka EMA trend, bade TF ke bina - hedge ke liye
int FastTrend()
  {
   double f = B1(hF, 1), sl = B1(hS, 1), c = iClose(_Symbol, InpSigTF, 1);
   if(f == 0 || sl == 0) return 0;
   return (f > sl && c > f) ? 1 : ((f < sl && c < f) ? -1 : 0);
  }

// Entry filter: "" = entry theek, warna rukne ki wajah
string EntryBlock(int dir)
  {
   int k = dir == 1 ? 0 : 1;
   if(InpMinGapMin > 0 && TimeCurrent() - lastAuto[k] < InpMinGapMin * 60) return "gap " + IntegerToString(InpMinGapMin) + " min";
   if(!rtFilter || mode == MODE_BOTH) return "";
   if(InpUseADX)
     {
      double a = B1(hADX, 1);
      if(a > 0 && a < InpADXMin) return StringFormat("ADX %.0f < %.0f (side-ways)", a, InpADXMin);
     }
   if(InpUseRSI)
     {
      double r = B1(hRSI, 1);
      if(r > 0 && dir == 1 && r >= InpRSIBuyMax)   return StringFormat("RSI %.0f (overbought)", r);
      if(r > 0 && dir == -1 && r <= InpRSISellMin) return StringFormat("RSI %.0f (oversold)", r);
     }
   if(InpUsePullback)
     {
      double e = B1(hF, 1), at = B1(hATR, 1), c = iClose(_Symbol, InpSigTF, 1);
      double d = dir == 1 ? c - e : e - c;
      if(at > 0 && d > InpPullbackATR * at) return StringFormat("price EMA21 se %.1f ATR door", d / at);
     }
   return "";
  }

// Account ka DD % (balance se equity kitni kam)
double AcctDDPct()
  {
   double b = AccountInfoDouble(ACCOUNT_BALANCE), e = AccountInfoDouble(ACCOUNT_EQUITY);
   return b > 0 ? MathMax(0.0, (b - e) / b * 100.0) : 0;
  }

// High-probability score 0-5: H4 trend, ADX >= 25, gehra pullback, RSI momentum zone, London-NY overlap
int HPScore(int dir)
  {
   int sc = 0;
   double h4 = B1(hH4, 1), h4c = iClose(_Symbol, PERIOD_H4, 1);
   if(h4 > 0 && ((dir == 1 && h4c > h4) || (dir == -1 && h4c < h4))) sc++;
   if(B1(hADX, 1) >= 25) sc++;
   double e = B1(hF, 1), at = B1(hATR, 1), c = iClose(_Symbol, InpSigTF, 1);
   if(at > 0 && MathAbs(c - e) <= 0.5 * at) sc++;
   double r = B1(hRSI, 1);
   if((dir == 1 && r >= 45 && r <= 65) || (dir == -1 && r >= 35 && r <= 55)) sc++;
   MqlDateTime g; TimeToStruct(TimeCurrent() - InpGMTOffset * 3600, g);
   if(g.hour >= 12 && g.hour < 16) sc++;
   return sc;
  }

double BoostMult(int sc)
  {
   if(!rtBoost || mode == MODE_BOTH || AcctDDPct() >= InpBoostMaxDD) return 1.0;
   if(sc >= 5) return MathMax(1.0, InpBoostMult5);
   if(sc >= InpBoostScore) return MathMax(1.0, InpBoostMult);
   return 1.0;
  }

// Profit me chal rahi side me naya leg (base lot): trend same, HP score acha, DD kam
bool TryLeg(int dir, SideInfo &s, Grp &h)
  {
   if(!rtLegs || mode == MODE_BOTH || s.n == 0 || s.n >= rtMax || h.n > 0 || s.legs >= InpMaxLegs) return false;
   if(curTrend != dir || s.profit <= 0 || rtTP <= 0 || AcctDDPct() >= InpBoostMaxDD) return false;
   double px = dir == 1 ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double need = InpLegStepTP * rtTP;
   if((dir == 1 && px < s.best + need) || (dir == -1 && px > s.best - need)) return false;
   int sc = HPScore(dir);
   if(sc < InpBoostScore) return false;
   if(!Open(dir, CurLot(), "LEG")) return false;
   PrintFormat("%s side profit me (%+.2f), HP %d/5: LEG %d khula", dir == 1 ? "BUY" : "SELL", s.profit, sc, s.legs + 1);
   return true;
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
   double tp = (rtTP > 0 && tag != "LOCK" && tag != "HEDGE") ? NormalizeDouble(px + dir * rtTP, dg) : 0;
   bool ok = dir == 1 ? trade.Buy(lot, _Symbol, 0, 0, tp, "GHS " + tag) : trade.Sell(lot, _Symbol, 0, 0, tp, "GHS " + tag);
   if(!ok || (trade.ResultRetcode() != TRADE_RETCODE_DONE && trade.ResultRetcode() != TRADE_RETCODE_PLACED))
     {
      PrintFormat("Order fail %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
      return false;
     }
   return true;
  }

// dir: 0 = dono, kind: -1 = sab, 0 normal, 1 hedge, 2 lock
void CloseWhere(int dir, int kind)
  {
   for(int pass = 0; pass < 3; pass++)
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(t == 0 || !Mine()) continue;
         if(dir != 0 && Dir() != dir) continue;
         if(kind >= 0 && Kind() != kind) continue;
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
   if(!rtAutoLock || !InpNewsLock || MQLInfoInteger(MQL_TESTER)) { newsNow = false; return; }
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

//==================== LOCK ====================
void SaveLock(int reason)
  {
   lockReason = reason; lockTime = TimeCurrent();
   GlobalVariableSet(gvLock + "R", reason); GlobalVariableSet(gvLock + "T", (double)(long)lockTime);
  }
void ResetLock()
  {
   lockReason = 0; lockTime = 0;
   GlobalVariableDel(gvLock + "R"); GlobalVariableDel(gvLock + "T");
  }
string LockName() { return lockReason == 1 ? "margin" : (lockReason == 2 ? "news" : (lockReason == 3 ? "manual" : "-")); }

// LOCK: net lot zero (loss wahin ruk jaye)
bool DoLock(int reason)
  {
   double net = buyLotsAll - sellLotsAll;
   if(MathAbs(net) < VolMin()) { Print("Pehle se lock hai (net 0)"); return false; }
   int dir = net > 0 ? -1 : 1;
   double lot = NormLot(MathAbs(net));
   if(!Open(dir, lot, "LOCK")) return false;
   SaveLock(reason);
   SB.be = false; SS.be = false;
   PrintFormat("LOCK (%s): %s %.2f lot - net exposure 0", LockName(), dir == 1 ? "BUY" : "SELL", lot);
   return true;
  }

bool CheckAutoLock()
  {
   if(!rtAutoLock || MathAbs(buyLotsAll - sellLotsAll) < VolMin()) return false;
   bool marginLow = AccountInfoDouble(ACCOUNT_MARGIN) > 0 && AccountInfoDouble(ACCOUNT_MARGIN_LEVEL) < InpLockMarginLevel;
   if(marginLow) return DoLock(1);
   if(InpNewsLock && newsNow)
     {
      if(allProfit >= InpUnlockMinUSD)      // sab profit me = news se pehle profit book
        {
         PrintFormat("News aa rahi hai: total %+.2f profit me, sab band", allProfit);
         CloseWhere(0, -1);
         return true;
        }
      return DoLock(2);
     }
   return false;
  }

// UNLOCK: LOCK trades (+ zarurat ho to original side ke profit wale trades) - total profit me ho tabhi
bool SmartUnlock(bool byButton)
  {
   if(LK.n == 0) return false;
   double lockNet = 0;    // LOCK trades ka net (BUY +, SELL -)
   ulong tk[]; ArrayResize(tk, PositionsTotal() + 1); int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !Mine() || Kind() != 2) continue;
      lockNet += Dir() * PositionGetDouble(POSITION_VOLUME);
      tk[n++] = t;
     }
   int orig = lockNet > 0 ? -1 : 1;   // LOCK SELL = original side BUY
   if(!byButton)
     {
      if(lockReason == 3) return false;                                       // manual LOCK = manual UNLOCK
      if(TimeCurrent() - lockTime < InpLockMinMinutes * 60) return false;
      if(lockReason == 2 && newsNow) return false;                            // news abhi chal rahi
      if(lockReason != 2 && curTrend != orig) return false;                   // trend wapas original side me ho
     }
   double sum = LK.profit, bLots = 0, sLots = 0;
   // original side ke profit wale trades (sabse zyada pehle) jab tak total >= min
   while(sum < InpUnlockMinUSD)
     {
      ulong best = 0; double bp = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(t == 0 || !Mine() || Kind() != 0 || Dir() != orig) continue;
         bool used = false;
         for(int j = 0; j < n; j++) if(tk[j] == t) { used = true; break; }
         if(used) continue;
         double p = PL();
         if(p > bp) { bp = p; best = t; }
        }
      if(best == 0) break;
      tk[n++] = best; sum += bp;
     }
   if(sum < InpUnlockMinUSD)
     {
      if(byButton) PrintFormat("UNLOCK nahi hua: total %+.2f (profit me nahi)", sum);
      return false;
     }
   // auto unlock: unlock ke baad margin level theek rahe
   if(!byButton)
     {
      for(int j = 0; j < n; j++)
         if(PositionSelectByTicket(tk[j])) { if(Dir() == 1) bLots += PositionGetDouble(POSITION_VOLUME); else sLots += PositionGetDouble(POSITION_VOLUME); }
      double big = MathMax(buyLotsAll - bLots, sellLotsAll - sLots), mAfter = 0;
      if(big > 0 && OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, big, SymbolInfoDouble(_Symbol, SYMBOL_ASK), mAfter) && mAfter > 0)
         if(AccountInfoDouble(ACCOUNT_EQUITY) / mAfter * 100.0 < InpLockMarginLevel + 50.0) return false;
     }
   PrintFormat("UNLOCK (%s): %d trades band, total %+.2f", LockName(), n, sum);
   ulong srt[]; ArrayResize(srt, n);
   int m = 0;
   for(int j = n - 1; j >= 0; j--) srt[m++] = tk[j];   // profit wale pehle, LOCK baad me
   CloseTickets(srt, m);
   ResetLock();
   return true;
  }

//==================== RECOVERY HEDGE ====================
void OrphanHedgeTP(int hd)
  {
   if(rtTP <= 0) return;
   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !Mine() || Kind() != 1 || Dir() != hd || PositionGetDouble(POSITION_TP) > 0) continue;
      double tp = NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN) + hd * rtTP, dg);
      if((hd == 1 && bid >= tp) || (hd == -1 && ask <= tp)) trade.PositionClose(t);
      else trade.PositionModify(t, PositionGetDouble(POSITION_SL), tp);
     }
  }

// Price wapas side ke favour me: side ka sabse profit wala trade + hedge ka utna hissa jitna wo cover kare (total >= min)
bool HedgeReduce(int dir, Grp &h)
  {
   if(!InpHedgeReduce || h.n == 0 || h.profit >= 0) return false;
   ulong bt = 0, wt = 0; double bp = 0, wp = 0, wv = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !Mine()) continue;
      int k = Kind(), d = Dir(); double p = PL();
      if(k == 0 && d == dir && p > bp)  { bp = p; bt = t; }
      if(k == 1 && d == -dir && p < wp) { wp = p; wt = t; wv = PositionGetDouble(POSITION_VOLUME); }
     }
   if(bt == 0 || wt == 0 || bp <= InpPairMinUSD || wv <= 0) return false;
   double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP); if(st <= 0) st = 0.01;
   double perLot = -wp / wv;                                   // hedge ka loss per lot
   double v = MathFloor((bp - InpPairMinUSD) / perLot / st + 1e-9) * st;
   bool full = v >= wv - 1e-9;
   if(!full && wv - v < VolMin() - 1e-9)                      // bacha hissa min lot se kam na ho
     {
      if(bp + wp >= InpPairMinUSD) full = true;
      else v = MathFloor((wv - VolMin()) / st + 1e-9) * st;
     }
   if(!full && v < VolMin() - 1e-9) return false;
   double lossPart = full ? wp : -perLot * v;
   PrintFormat("SMART HEDGE KAM: profit trade %+.2f + hedge %.2f lot %+.2f = %+.2f",
               bp, full ? wv : v, lossPart, bp + lossPart);
   if(!trade.PositionClose(bt)) return false;                  // profit wala pehle
   if(full) trade.PositionClose(wt);
   else     trade.PositionClosePartial(wt, NormalizeDouble(v, 2));
   return true;
  }

bool ManageHedge(int dir, SideInfo &s, Grp &h)
  {
   int k = dir == 1 ? 0 : 1;
   string side = dir == 1 ? "BUY" : "SELL";
   int ht = InpHedgeFastTrend ? curFast : curTrend;     // hedge ke liye trend
   if(h.n == 0) hedgeBE[k] = false;
   if(h.n > 0)
     {
      // side + hedge ka total profit me = dono band
      if(s.n > 0 && s.profit + h.profit >= InpHedgeCloseUSD)
        {
         PrintFormat("%s side + hedge band: %+.2f %+.2f = %+.2f", side, s.profit, h.profit, s.profit + h.profit);
         CloseWhere(-dir, 1);
         CloseWhere(dir, 0);
         hedgeClosed[k] = TimeCurrent();
         return true;
        }
      // trend wapas side ke favour me (ya side khali) + hedge profit me = sirf hedge band
      if(h.profit >= InpHedgeCloseUSD && (s.n == 0 || ht == dir))
        {
         PrintFormat("%s side ka hedge profit me band: %+.2f", side, h.profit);
         CloseWhere(-dir, 1);
         hedgeClosed[k] = TimeCurrent();
         return true;
        }
      // hedge ka profit lock: hedge +BE trigger chala, phir wapas +lock par aaya = hedge profit me band
      double hm = dir == 1 ? GAvg(h) - SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID) - GAvg(h);
      if(!hedgeBE[k] && hm >= InpBETrigger) { hedgeBE[k] = true; PrintFormat("%s side ka hedge +$%.1f chala: profit lock ON", side, hm); }
      if(hedgeBE[k] && hm <= InpBELock && h.profit > 0)
        {
         PrintFormat("%s side ka hedge profit lock par band: %+.2f", side, h.profit);
         CloseWhere(-dir, 1);
         hedgeClosed[k] = TimeCurrent();
         return true;
        }
      // price wapas side ke favour me = hedge dheere-dheere chhota (har close total plus me)
      if(s.n > 0 && ht != -dir && HedgeReduce(dir, h)) return true;
      // step hedge: price hedge se 1 DCA step aur ulta gaya = baaki hedge
      if(InpHedgeSteps && h.n == 1 && s.n > 0)
        {
         double tgt = MathMin(NormLot(s.lots * rtHedgePct / 100.0), s.lots);
         double add = tgt - h.lots;
         double far = dir == 1 ? GAvg(h) - SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK) - GAvg(h);
         if(add >= VolMin() && far >= rtDCA && Spread() <= InpMaxSpread && s.profit < 0)
           {
            add = NormLot(add);
            if(Open(-dir, add, "HEDGE"))
              {
               PrintFormat("%s side: price $%.1f aur ulta, HEDGE step 2: %s %.2f lot (kul %.2f)",
                           side, far, dir == 1 ? "SELL" : "BUY", add, h.lots + add);
               return true;
              }
           }
        }
      if(s.n == 0) OrphanHedgeTP(-dir);   // side band ho gayi: hedge ko normal TP
      return false;
     }
   if(!rtHedge || s.n == 0 || s.profit >= 0) return false;
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double lossPct = bal > 0 ? -s.profit / bal * 100.0 : 0;
   bool stuck = s.n >= InpRecLayers || (InpRecLossPct > 0 && lossPct >= InpRecLossPct);
   bool normal = stuck && ht == -dir;                                       // phansi + trend ulta
   bool hard = InpRecHardPct > 0 && lossPct >= InpRecHardPct && ht != dir;  // loss bada + price side ke favour me nahi
   if(!normal && !hard) return false;
   if(TimeCurrent() - hedgeClosed[k] < InpHedgeCoolMin * 60) return false;
   if(Spread() > InpMaxSpread) return false;
   double lot = MathMin(NormLot(s.lots * rtHedgePct / 100.0), s.lots);   // kabhi side se zyada nahi
   if(InpHedgeSteps) lot = NormLot(lot / 2.0);                           // step 1 = aadha
   if(lot < VolMin()) return false;
   if(!Open(-dir, lot, "HEDGE")) return false;
   PrintFormat("%s side phansi (%d pos, %+.2f = %.1f%%), %s: HEDGE%s %s %.2f lot (target %.0f%%)",
               side, s.n, s.profit, lossPct, normal ? "trend ulta" : "loss bada", InpHedgeSteps ? " step 1" : "",
               dir == 1 ? "SELL" : "BUY", lot, rtHedgePct);
   return true;
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
      if(t == 0 || !Mine() || Kind() != 0) continue;
      int d = Dir();
      if((d == 1 && HB.n > 0) || (d == -1 && HS.n > 0)) continue;   // hedge wali side ko hedge sambhalega
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
         if(t == 0 || t == wT || !Mine() || Kind() != 0) continue;
         int d = Dir();
         if((d == 1 && HB.n > 0) || (d == -1 && HS.n > 0)) continue;
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
   curFast = FastTrend();
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(LK.n == 0 && lockReason != 0) ResetLock();

   //--- 1) Net close: sab trades ka total profit me (koi loss me ho)
   if(InpNetClose && buyLotsAll > 0 && sellLotsAll > 0 && anyLoss && allProfit >= InpNetCloseUSD)
     {
      PrintFormat("NET CLOSE: total %+.2f", allProfit);
      CloseWhere(0, -1);
      ResetLock();
      return;
     }

   //--- 2) LOCK laga hai = sab freeze (TP hate, DCA/entry/pair band) - sirf UNLOCK ya net close
   if(LK.n > 0)
     {
      ManageStops(1, SB, true, bid, ask);
      ManageStops(-1, SS, true, bid, ask);
      SmartUnlock(false);
      Panel();
      return;
     }
   if(CheckAutoLock()) { Panel(); return; }

   //--- 3) Pair close (pehle - phansa trade profit ke saath nikle to hedge ki zarurat nahi)
   if(PairClose()) { Panel(); return; }

   //--- 4) Recovery hedge
   if(ManageHedge(1, SB, HB) || ManageHedge(-1, SS, HS)) { Panel(); return; }

   //--- 5) TP + breakeven (hedge wali side: TP hata, group close se nikalegi)
   if(ManageStops(1, SB, HB.n > 0, bid, ask) || ManageStops(-1, SS, HS.n > 0, bid, ask)) { Panel(); return; }

   bool roomOK = MarginOK() && Spread() <= InpMaxSpread && !newsNow;

   //--- 6) DCA: side ki sabse kharab position se $X against (hedge wali side ka DCA ruka)
   if(InpDCA && roomOK)
     {
      if(SB.n > 0 && SB.n < rtMax && !SB.be && HB.n == 0 && ask <= SB.worst - rtDCA) Open(1, CurLot(), "DCA");
      if(SS.n > 0 && SS.n < rtMax && !SS.be && HS.n == 0 && bid >= SS.worst + rtDCA) Open(-1, CurLot(), "DCA");
     }

   //--- 7) Har naye candle par entry
   datetime bar = iTime(_Symbol, InpSigTF, 0);
   if(bar != lastBar)
     {
      lastBar = bar;
      if(!autoOn) entryWhy = "AUTO OFF";
      else if(!SessionOK()) entryWhy = "session ke bahar";
      else if(!roomOK) entryWhy = !MarginOK() ? "margin kam" : (Spread() > InpMaxSpread ? "spread zyada" : "news time");
      else if(mode == MODE_TREND && curTrend == 0) entryWhy = "trend SIDE (M1/H1 match nahi)";
      else
        {
         bool wantB = (mode == MODE_BOTH) || curTrend == 1;
         bool wantS = (mode == MODE_BOTH) || curTrend == -1;
         string wb = "", ws = "";
         if(wantB)
           {
            if(SB.n >= rtMax) wb = "max per side";
            else if(SB.be) wb = "breakeven lagi";
            else if(HB.n > 0) wb = "hedge laga";
            else wb = EntryBlock(1);
            if(wb == "")
              {
               int sc = HPScore(1); double mlt = BoostMult(sc);
               if(Open(1, NormLot(CurLot() * mlt), "AUTO"))
                 {
                  lastAuto[0] = TimeCurrent();
                  wb = mlt > 1.0 ? StringFormat("khula HP %d/5 lot x%.1f", sc, mlt) : StringFormat("khula (HP %d/5)", sc);
                 }
               else wb = "order fail (Experts tab)";
              }
           }
         if(wantS)
           {
            if(SS.n >= rtMax) ws = "max per side";
            else if(SS.be) ws = "breakeven lagi";
            else if(HS.n > 0) ws = "hedge laga";
            else ws = EntryBlock(-1);
            if(ws == "")
              {
               int sc = HPScore(-1); double mlt = BoostMult(sc);
               if(Open(-1, NormLot(CurLot() * mlt), "AUTO"))
                 {
                  lastAuto[1] = TimeCurrent();
                  ws = mlt > 1.0 ? StringFormat("khula HP %d/5 lot x%.1f", sc, mlt) : StringFormat("khula (HP %d/5)", sc);
                 }
               else ws = "order fail (Experts tab)";
              }
           }
         entryWhy = (wantB ? "BUY " + wb : "") + (wantB && wantS ? " | " : "") + (wantS ? "SELL " + ws : "");
        }
      // profit me chal rahi side me legs (har naye candle par max 1)
      if(autoOn && roomOK && SessionOK() && (TryLeg(1, SB, HB) || TryLeg(-1, SS, HS))) entryWhy += " | LEG khula";
     }
   Panel();
  }

// TP har position par; side +$X chale to sab ka SL = average + lock
// frozen = hedge/LOCK laga hai: EA ka TP hata do, breakeven nahi
bool ManageStops(int dir, SideInfo &s, bool frozen, double bid, double ask)
  {
   if(s.n == 0) return false;
   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   long lv = MathMax(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL), SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL));
   double minStop = (double)lv * _Point + 5 * _Point;
   if(frozen) { s.be = false; s.beSL = 0; }
   else
     {
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
         CloseWhere(dir, 0);
         s.be = false;
         return true;
        }
     }
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !Mine() || Dir() != dir || Kind() != 0) continue;
      double op = PositionGetDouble(POSITION_PRICE_OPEN), cSL = PositionGetDouble(POSITION_SL), cTP = PositionGetDouble(POSITION_TP);
      bool manual = PositionGetInteger(POSITION_MAGIC) == 0;
      double eaTP = rtTP > 0 ? NormalizeDouble(op + dir * rtTP, dg) : 0;
      bool userTP = manual && InpKeepManualSLTP && cTP > 0 && MathAbs(cTP - eaTP) >= 10 * _Point;
      if(!frozen && !userTP && eaTP > 0 && ((dir == 1 && bid >= eaTP) || (dir == -1 && ask <= eaTP)))
        { trade.PositionClose(t); continue; }       // price TP se aage nikal gaya (freeze ke baad) = profit book
      double tp = userTP ? cTP : (frozen ? 0 : eaTP);
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
   Tx("ti", 10, 6, "GOLD HEDGE SCALPER", cTx, 10, true);
   double ml = AccountInfoDouble(ACCOUNT_MARGIN) > 0 ? AccountInfoDouble(ACCOUNT_MARGIN_LEVEL) : 0;
   Tx("st", 10, 24, StringFormat("Trend: %s (M1 %s) | Margin %s | Spread %.0f%s", curTrend == 1 ? "UP" : (curTrend == -1 ? "DOWN" : "SIDE"),
      curFast == 1 ? "UP" : (curFast == -1 ? "DOWN" : "SIDE"),
      ml > 0 ? StringFormat("%.0f%%", ml) : "-", Spread(), newsNow ? "  |  NEWS" : ""), MarginOK() && !newsNow ? cDm : cS, 8);
   y = 44;
   Rc("cb", 6, y, W - 12, 22, cCard);
   Tx("lb", 12, y + 4, StringFormat("BUY  %d pos | %.2f lot | P/L %+.2f%s%s", SB.n, SB.lots, SB.profit, SB.be ? " | BE" : "",
      HB.n > 0 ? " | HEDGED" : ""), cB, 8, true);
   y += 24;
   Rc("cs", 6, y, W - 12, 22, cCard);
   Tx("ls", 12, y + 4, StringFormat("SELL %d pos | %.2f lot | P/L %+.2f%s%s", SS.n, SS.lots, SS.profit, SS.be ? " | BE" : "",
      HS.n > 0 ? " | HEDGED" : ""), cS, 8, true);
   y += 26;
   Tx("net", 10, y, StringFormat("NET %+.2f  (net lot %+.2f)", allProfit, buyLotsAll - sellLotsAll), allProfit >= 0 ? cB : cS, 9, true);
   y += 18;
   string pr = StringFormat("Hedge: BUY-side %s | SELL-side %s",
                            HB.n > 0 ? StringFormat("%.2f/%d (%+.2f)%s", HB.lots, HB.n, HB.profit, hedgeBE[0] ? " LOCK" : "") : "-",
                            HS.n > 0 ? StringFormat("%.2f/%d (%+.2f)%s", HS.lots, HS.n, HS.profit, hedgeBE[1] ? " LOCK" : "") : "-");
   Tx("hg", 10, y, pr, HB.n + HS.n > 0 ? cW : cDm, 8);
   y += 16;
   Tx("lk", 10, y, LK.n > 0 ? StringFormat("LOCK ON (%s) %.2f lot  P/L %+.2f", LockName(), LK.lots, LK.profit) : "LOCK: OFF",
      LK.n > 0 ? cW : cDm, 8, LK.n > 0);
   y += 16;
   Tx("ew", 10, y, "Entry: " + entryWhy, StringFind(entryWhy, "khula") >= 0 ? cB : cDm, 8);
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
   OnOff("hedge", 6, y, bw, "HEDGE", rtHedge);
   OnOff("pair", 6 + bw + 4, y, bw, "PAIR", rtPair);
   OnOff("alock", 6 + 2 * (bw + 4), y, bw, "A-LOCK", rtAutoLock);
   y += 26;
   Bt("ca", 6, y, bw, 22, "CLOSE ALL", cS, clrWhite);
   Bt("lotmode", 6 + bw + 4, y, bw, 22, rtAuto ? "LOT: AUTO" : "LOT: FIXED", rtAuto ? cB : cLn, rtAuto ? cBg : cTx);
   OnOff("filt", 6 + 2 * (bw + 4), y, bw, "FILTER", rtFilter);
   y += 26;
   OnOff("boost", 6, y, (W - 16) / 2, "HP LOT BOOST", rtBoost);
   OnOff("legs", 6 + (W - 16) / 2 + 4, y, (W - 16) / 2, "PROFIT LEGS", rtLegs);
   y += 28;
   string lab[5];
   string ids[5] = {"tp", "dca", "lot", "max", "hp"};
   lab[0] = rtTP > 0 ? StringFormat("TP  +$%.1f (har trade)", rtTP) : "TP  OFF";
   lab[1] = StringFormat("DCA  $%.1f", rtDCA);
   lab[2] = rtAuto ? StringFormat("Lot AUTO %.2f  (0.01 / $%.0f)", CurLot(), rtPer) : StringFormat("Lot FIXED  %.2f", rtLot);
   lab[3] = StringFormat("Max per side  %d", rtMax);
   lab[4] = StringFormat("Hedge  %.0f%%  (max 100%%)", rtHedgePct);
   for(int r = 0; r < 5; r++)
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
   curFast = FastTrend();
   if(b == "auto") autoOn = !autoOn;
   else if(b == "mode") mode = (mode == MODE_TREND) ? MODE_BOTH : MODE_TREND;
   else if(b == "lock") DoLock(3);
   else if(b == "unlock")
     {
      if(LK.n == 0) Print("LOCK laga hi nahi hai");
      else if(!SmartUnlock(true) &&
              MessageBox(StringFormat("LOCK abhi profit me nahi hai (LOCK P/L %+.2f).\nFir bhi UNLOCK karein?", LK.profit),
                         "Gold Hedge Scalper", MB_YESNO | MB_ICONWARNING) == IDYES)
        { CloseWhere(0, 2); ResetLock(); Print("UNLOCK (force): LOCK positions band"); }
     }
   else if(b == "hedge") rtHedge = !rtHedge;
   else if(b == "pair") rtPair = !rtPair;
   else if(b == "alock") rtAutoLock = !rtAutoLock;
   else if(b == "filt") rtFilter = !rtFilter;
   else if(b == "boost") rtBoost = !rtBoost;
   else if(b == "legs") rtLegs = !rtLegs;
   else if(b == "tpm" || b == "tpp") rtTP = MathMax(0.0, rtTP + (b == "tpp" ? 0.1 : -0.1));
   else if(b == "dcam" || b == "dcap") rtDCA = MathMax(0.5, rtDCA + (b == "dcap" ? 0.5 : -0.5));
   else if(b == "hpm" || b == "hpp") rtHedgePct = MathMax(10.0, MathMin(100.0, rtHedgePct + (b == "hpp" ? 10.0 : -10.0)));
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
      if(MessageBox(w + " positions close karein?", "Gold Hedge Scalper", MB_YESNO | MB_ICONWARNING) == IDYES)
        {
         if(b == "ca") { CloseWhere(0, -1); ResetLock(); }
         else
           {
            int cd = b == "cb" ? 1 : -1;
            CloseWhere(cd, 0);       // us side ke trades
            CloseWhere(-cd, 1);      // + us side ka hedge (LOCK nahi chhedta)
           }
        }
     }
   lastDraw = 0;
   Panel();
  }
//+------------------------------------------------------------------+
