//+------------------------------------------------------------------+
//|                                                GoldDCA_EA.mq5    |
//|  XAUUSD Trend-following DCA EA - SCALP + INTRADAY (dono saath)   |
//|  - Master trend (H1) ki direction me hi dono engine trade lete   |
//|  - Scalp   : M5 signal, M15 trend, chhota step/TP, kam layers    |
//|  - Intraday: M15 signal, H1 trend, $7 step, bada TP              |
//|  - Har engine ka alag basket (alag magic), alag TP/SL            |
//|  - MACD + RSI + ATR confirm, S/R levels, news filter, daily limit|
//|  WARNING: DCA me ek bada trend against ho to bada loss ho sakta  |
//|  hai. Basket hard stop OFF mat karein.                           |
//+------------------------------------------------------------------+
#property copyright "GoldDCA_EA"
#property version   "3.82"

#include <Trade/Trade.mqh>

enum ENUM_LOT_MODE  { LOT_FIXED = 0, LOT_AUTO = 1 };
enum ENUM_STEP_MODE { STEP_FIXED_PRICE = 0, STEP_ATR = 1 };
enum ENUM_TP_MODE   { TP_FIXED_PRICE = 0, TP_ATR = 1 };
enum ENUM_LOT_PROG  { PROG_MULTIPLIER = 0, PROG_FIXED_ADD = 1 };
enum ENUM_MAN_ENG   { MAN_SCALP = 0, MAN_INTRADAY = 1, MAN_TICK = 2 };
#define NT 3   // engine types: 0 = SCALP, 1 = INTRADAY, 2 = TICK M1
#define NE 6   // engine slots: 0-2 = BUY side (ya dono side jab hedge off), 3-5 = SELL side (hedge mode)

input group "=== General ==="
input long            InpMagic            = 888001;       // Base magic (Scalp +1, Intraday +2, Tick M1 +3)
input string          InpComment          = "GoldDCA";    // Order comment
input ENUM_TIMEFRAMES InpMasterTF         = PERIOD_H1;    // Master trend timeframe (dono engine follow karenge)
input int             InpMasterFastEMA    = 50;           // Master fast EMA
input int             InpMasterSlowEMA    = 200;          // Master slow EMA
input bool            InpHedgeMode        = true;         // HEDGE: BUY aur SELL basket ek saath alag-alag chal sakte hain
input bool            InpNoOpposite       = true;         // (Hedge OFF par) ek engine BUY me ho to doosra SELL na khole

input group "=== Lot Size (shared) ==="
input ENUM_LOT_MODE   InpLotMode          = LOT_AUTO;     // Lot mode
input double          InpFixedLot         = 0.01;         // Fixed first lot
input double          InpBalancePerLot    = 2000.0;       // AUTO: har itne $ balance par 0.01 lot
input double          InpMaxLot           = 2.0;          // Max lot per layer
input ENUM_LOT_PROG   InpLotProgression   = PROG_FIXED_ADD; // DCA lot: Multiplier (x) ya Fixed Add (+)
input double          InpLotAddFactor     = 0.5;          // Fixed Add: har layer par +pehla lot x ye (1.0 = 0.01,0.02,0.03..)

input group "=== SCALP Engine ==="
input bool            InpScOn             = true;             // Scalp ON
input ENUM_TIMEFRAMES InpScSigTF          = PERIOD_M5;        // Scalp signal TF
input ENUM_TIMEFRAMES InpScTrendTF        = PERIOD_M15;       // Scalp trend TF
input double          InpScLotFactor      = 1.0;              // Scalp first lot x base lot
input double          InpScLotMult        = 1.2;              // Scalp DCA lot multiplier
input ENUM_STEP_MODE  InpScStepMode       = STEP_FIXED_PRICE; // Scalp step mode
input double          InpScStep           = 3.0;              // Scalp DCA step ($)
input double          InpScStepATR        = 1.0;              // Scalp step ATR x (ATR mode)
input double          InpScStepGrowth     = 1.0;              // Scalp step growth (1.0 = har layer $3)
input int             InpScMaxLayers      = 0;                // Scalp max layers (0 = unlimited)
input ENUM_TP_MODE    InpScTPMode         = TP_ATR;           // Scalp TP mode
input double          InpScTP             = 1.0;              // Scalp fixed TP ($ from average)
input double          InpScTP_ATR         = 0.6;              // Scalp TP ATR x
input double          InpScTPMin          = 0.8;              // Scalp min TP ($)
input double          InpScStopPct        = 80.0;              // Scalp basket hard stop (% equity)
input int             InpScCooldownMin    = 2;                // Scalp cooldown (min)
input int             InpScMaxBaskets     = 30;               // Scalp max baskets/day
input double          InpScMaxATR         = 8.0;              // Scalp: signal ATR max ($)
input double          InpScMinATR         = 0.5;              // Scalp: signal ATR min ($)

input group "=== INTRADAY Engine ==="
input bool            InpInOn             = true;             // Intraday ON
input ENUM_TIMEFRAMES InpInSigTF          = PERIOD_M15;       // Intraday signal TF
input ENUM_TIMEFRAMES InpInTrendTF        = PERIOD_H1;        // Intraday trend TF
input double          InpInLotFactor      = 1.0;              // Intraday first lot x base lot
input double          InpInLotMult        = 1.3;              // Intraday DCA lot multiplier
input ENUM_STEP_MODE  InpInStepMode       = STEP_FIXED_PRICE; // Intraday step mode
input double          InpInStep           = 3.0;              // Intraday DCA step ($)
input double          InpInStepATR        = 1.0;              // Intraday step ATR x (ATR mode)
input double          InpInStepGrowth     = 1.0;              // Intraday step growth (1.0 = har layer $3)
input int             InpInMaxLayers      = 0;                // Intraday max layers (0 = unlimited)
input ENUM_TP_MODE    InpInTPMode         = TP_ATR;           // Intraday TP mode
input double          InpInTP             = 2.0;              // Intraday fixed TP ($ from average)
input double          InpInTP_ATR         = 0.5;              // Intraday TP ATR x
input double          InpInTPMin          = 1.5;              // Intraday min TP ($)
input double          InpInStopPct        = 80.0;             // Intraday basket hard stop (% equity)
input int             InpInCooldownMin    = 5;                // Intraday cooldown (min)
input int             InpInMaxBaskets     = 20;               // Intraday max baskets/day
input double          InpInMaxATR         = 15.0;             // Intraday: signal ATR max ($)
input double          InpInMinATR         = 1.0;              // Intraday: signal ATR min ($)

input group "=== TICK M1 SCALP Engine (har tick par check) ==="
input bool            InpTkOn             = true;             // Tick M1 scalp ON
input ENUM_TIMEFRAMES InpTkSigTF          = PERIOD_M1;        // Tick engine signal TF (EMA/RSI/ATR)
input ENUM_TIMEFRAMES InpTkTrendTF        = PERIOD_M5;        // Tick engine trend TF
input int             InpTkWindowSec      = 5;                // Momentum window (seconds)
input double          InpTkMinMove        = 0.30;             // Window me kam se kam itna $ move trend direction me
input double          InpTkMaxMove        = 2.00;             // Isse zyada move = spike, entry nahi
input int             InpTkMinTicks       = 5;                // Window me kam se kam itne ticks (liquidity)
input int             InpTkMaxSpread      = 30;               // Tick engine max spread (points)
input bool            InpTkUseMACD        = false;            // Tick engine par MACD confirm (slow hota hai)
input double          InpTkLotFactor      = 1.0;              // Tick first lot x base lot
input double          InpTkLotMult        = 1.2;              // Tick DCA lot multiplier
input ENUM_STEP_MODE  InpTkStepMode       = STEP_FIXED_PRICE; // Tick step mode
input double          InpTkStep           = 3.0;              // Tick DCA step ($)
input double          InpTkStepATR        = 1.5;              // Tick step ATR x (ATR mode)
input double          InpTkStepGrowth     = 1.0;              // Tick step growth (1.0 = har layer $3)
input int             InpTkMaxLayers      = 0;                // Tick max layers (0 = unlimited)
input ENUM_TP_MODE    InpTkTPMode         = TP_ATR;           // Tick TP mode
input double          InpTkTP             = 0.5;              // Tick fixed TP ($ from average)
input double          InpTkTP_ATR         = 0.8;              // Tick TP M1 ATR x
input double          InpTkTPMin          = 0.4;              // Tick min TP ($)
input double          InpTkStopPct        = 80.0;              // Tick basket hard stop (% equity)
input int             InpTkCooldownSec    = 30;               // Tick cooldown (seconds)
input int             InpTkMaxBaskets     = 60;               // Tick max baskets/day
input double          InpTkMaxATR         = 4.0;              // Tick: M1 ATR max ($)
input double          InpTkMinATR         = 0.3;              // Tick: M1 ATR min ($)

input group "=== DCA / Exit (shared) ==="
input int             InpMinSecBetween    = 60;           // Layers ke beech min seconds
input bool            InpAddOnlyInTrend   = false;        // true = trend palatne par DCA ruk jaye; false = BUY aur SELL dono side DCA hamesha chalu
input bool            InpBrokerSLTP       = true;         // Auto SL/TP broker par bhi lagao
input bool            InpBEExit           = true;         // Breakeven exit: kaafi layers ke baad average par wapas aaye to nikal jao
input int             InpBEMinLayers      = 2;            // Itne ya zyada layers (DCA hua) to profit hote hi poora basket close
input double          InpBEBuffer         = 0.5;          // Average se itna $ upar (cost cover) par close
input double          InpMaxTotalLots     = 0.0;          // Ek basket ka max total lot (0 = no limit)
input bool            InpNewCandleLayer   = true;         // Ek candle me max 1 layer (naya candle aane par hi agla layer)

input group "=== Exit: Fixed $ Lock + Trailing (default) ==="
input bool            InpFxExit           = true;         // ON: niche wale $ niyam (ATR TP / 50% book / $0.50 exit ki jagah)
input double          InpFxTrigger        = 3.0;          // Average se $3 profit par trailing shuru
input double          InpFxLock           = 1.0;          // Trigger par SL average + $1 par lock
input double          InpFxTrailDist      = 2.0;          // Phir SL price ke $2 peeche chalega
input double          InpFxTP             = 5.0;          // Average se $5 par poora basket close
input double          InpFxBookPct        = 0.0;          // Trigger ($3) par itna % book (0 = off)
input bool            InpFxBackup         = true;         // Backup: +$2 tak aakar palte to chhote profit me nikal jao
input double          InpFxBackupArm      = 2.0;          // Backup tab active jab price average se +$2 tak pahunche
input double          InpFxBackupExit     = 0.5;          // Phir wapas +$0.50 par aaye to poora basket close

input group "=== Basket Trailing (ATR mode, jab Fixed $ exit OFF) ==="
input bool            InpBasketTrail      = true;         // TP par close ki jagah trailing shuru karo
input double          InpTrailLockPct     = 50.0;         // Trailing start par TP ka itna % lock
input double          InpTrailDistMult    = 1.0;          // Trailing distance = TP distance x ye
input double          InpTrailStep        = 0.3;          // SL kam se kam itna $ move ho tab update
input double          InpBookPct          = 50.0;         // TP aate hi basket ka itna % volume book (0 = off), baaki trailing

input group "=== Signal Panel ==="
input bool            InpGraphicPanel     = true;         // Graphic signal panel (false = simple text)
input int             InpPanelX           = 10;           // Panel X (px)
input int             InpPanelY           = 25;           // Panel Y (px)
input bool            InpAlertPopup       = true;         // Naya HIGH signal: MT5 popup alert
input bool            InpAlertPush        = true;         // Naya HIGH signal: phone push (MT5 app)
input int             InpAlertGapMin      = 15;           // Do alerts ke beech min gap (minutes)

input group "=== Smart Pause + Net Profit Close ==="
input bool            InpPauseOnReversal  = true;         // High probability ulta signal aaye to us basket ka DCA pause
input int             InpReversalScore    = 75;           // Ulti direction ka scanner score itna ya zyada = reversal
input bool            InpPauseOnCHoCH     = true;         // Structure ulta CHoCH de to bhi DCA pause
input bool            InpNetClose         = true;         // Saare baskets ka total P/L profit me aaye to sab close
input double          InpNetCloseUSD      = 5.0;          // Kam se kam itna $ net profit
input double          InpNetClosePerLot   = 50.0;         // Ya har 1.00 lot par itna $ (jo bada ho)

input group "=== Recovery Hedge (trend against ho to turant chhota hedge) ==="
input bool            InpRecHedge         = true;         // Recovery hedge ON (Hedge mode zaroori)
input int             InpRecLayers        = 3;            // Phanse basket me itne layers ho gaye to (0 = off)
input double          InpRecDDPct         = 3.0;          // Ya basket loss equity ka itna % (0 = off)
input double          InpRecRatio         = 50.0;         // Hedge lot = phanse basket ke lot ka itna % (100 = poora barabar)
input int             InpRecCooldownMin   = 15;           // Ek hedge band hone ke baad dobara kitni der baad

input group "=== Weekend Protection (Friday) ==="
input bool            InpFriClose         = true;         // Friday shaam basket profit me / average ke paas ho to close
input int             InpFriHour          = 20;           // Friday kis server hour se
input double          InpFriMaxLossUSD    = 0.0;          // Basket ka loss itne $ tak ho to bhi close (0 = sirf profit me)
input bool            InpFriNoDCA         = true;         // Friday is hour ke baad naye DCA layers bhi nahi
input bool            InpFriForceClose    = false;        // Friday force close: sab baskets band, chahe loss ho
input int             InpFriForceHour     = 22;           // Force close ka server hour

input group "=== Margin / Lot Limit (sab baskets mila kar) ==="
input double          InpMaxAllLots       = 0.0;          // Saare EA baskets ka kul lot isse zyada nahi (0 = off)
input double          InpMinMarginLevel   = 150.0;        // Margin level % isse kam ho to naya basket / layer nahi (0 = off)

input group "=== Telegram Alerts ==="
input bool            InpTgOn             = false;        // Telegram alerts ON
input string          InpTgToken          = "";           // Bot token (BotFather se)
input string          InpTgChatId         = "";           // Chat ID
input bool            InpTgLayers         = true;         // Har DCA layer ka message bhi
input bool            InpTgDaily          = true;         // Din khatam hone par daily report

input group "=== Cutloss ($) ==="
input double          InpCutlossUSD       = 0.0;          // Dono engine ka floating loss itna $ ho to sab close (0 = off)
input bool            InpResumeAfterCut   = true;         // true = cooldown ke baad phir shuru, false = din band
input int             InpCutCooldownMin   = 30;           // Cutloss ke baad wait (minutes)

input group "=== Manual Trades ==="
input bool            InpManageManual     = true;         // Manual trades ko DCA basket me manage karo
input ENUM_MAN_ENG    InpManualEngine     = MAN_INTRADAY; // Manual trade kaunsa engine sambhale
input bool            InpManualAnyMagic   = false;        // true = doosre EA ke trades bhi (warna sirf magic 0)

input group "=== Daily Limits (account) ==="
input double          InpDailyTargetPct   = 5.0;          // Daily target % - hit hone par naye basket band
input double          InpDailyLossPct     = 80.0;         // Daily max loss % - sab close, din band (hard stop se kam rakhoge to pehle yahi lagega)

input group "=== Entry Indicators (shared) ==="
input int             InpTrendFastEMA     = 50;           // Engine trend TF fast EMA
input int             InpTrendSlowEMA     = 200;          // Engine trend TF slow EMA
input int             InpSigFastEMA       = 9;            // Signal TF fast EMA
input int             InpSigSlowEMA       = 21;           // Signal TF slow EMA
input int             InpRSIPeriod        = 14;           // RSI period
input double          InpRSIBuyMin        = 50;           // BUY: RSI min
input double          InpRSIBuyMax        = 72;           // BUY: RSI max
input double          InpRSISellMin       = 28;           // SELL: RSI min
input double          InpRSISellMax       = 50;           // SELL: RSI max
input int             InpATRPeriod        = 14;           // ATR period
input bool            InpUseMACD          = true;         // MACD confirm ON
input int             InpMACDFast         = 12;           // MACD fast
input int             InpMACDSlow         = 26;           // MACD slow
input int             InpMACDSignal       = 9;            // MACD signal
input bool            InpMACDZeroLine     = true;         // BUY: MACD > 0, SELL: MACD < 0

input group "=== News Filter (live only, MT5 calendar) ==="
input bool            InpUseNews          = true;         // News filter ON
input int             InpNewsBeforeMin    = 30;           // High-impact USD news se pehle (min)
input int             InpNewsAfterMin     = 30;           // News ke baad (min)
input bool            InpNewsNoDCA        = true;         // News window me DCA layer bhi nahi
input bool            InpNewsCloseProfit  = true;         // News se pehle basket profit me ho to close

input group "=== S/R Levels (Y / 6M / 3M / 1M / W / 3D / D / H4) ==="
input bool            InpShowLevels       = true;         // Chart par levels draw karo
input bool            InpShowY            = true;         // Previous Year O/H/L/C
input bool            InpShow6M           = true;         // Previous Half-year O/H/L/C
input bool            InpShow3M           = true;         // Previous Quarter O/H/L/C
input bool            InpShow1M           = true;         // Previous Month O/H/L/C
input bool            InpShowW            = true;         // Previous Week O/H/L/C
input bool            InpShow3D           = true;         // Last 3 Days O/H/L/C
input bool            InpShowD            = true;         // Previous Day O/H/L/C
input bool            InpShowH4           = true;         // Last H4 candles O/H/L/C
input int             InpH4Count          = 5;            // Kitne H4 candles
input bool            InpDrawZones        = true;         // Y/6M/3M/1M/W levels par zone (box)
input double          InpZoneHalf         = 1.0;          // Zone half-width ($) - Y/6M/3M/1M/W
input bool            InpDrawSmallZones   = true;         // 3D / D / H4 levels par bhi zone (box)
input double          InpZoneHalfSmall    = 0.5;          // Zone half-width ($) - 3D/D/H4
input color           InpZoneColor        = C'45,45,70';  // Zone color
input bool            InpUseSRFilter      = true;         // S/R ke paas against-direction entry block
input double          InpSRBlockDist      = 3.0;          // BUY: resistance itne $ upar ho to skip (SELL ulta)
input int             InpSRMinRank        = 3;            // Filter kin levels par: 7=Y 6=6M 5=3M 4=1M 3=W 2=3D 1=D 0=H4

input group "=== Market Scanner (High Probability only) ==="
input bool            InpUseScanner       = true;         // Scanner ON - sirf high score par entry
input int             InpMinScore         = 75;           // Entry ke liye min score (0-100). 75 = HIGH
input int             InpMedScore         = 60;           // MEDIUM tier (sirf display)
input int             InpEliteScore       = 85;           // ELITE tier
input double          InpEliteLotMult     = 1.0;          // ELITE score par lot x (1.0 = same)
input int             InpServerGMTOffset  = 2;            // Broker server time = GMT + ? (sessions ke liye)
input string          InpSymDollar        = "EURUSD";     // Dollar proxy symbol (blank = off)
input string          InpSymSilver        = "XAGUSD";     // Silver symbol (blank = off)

input group "=== Institutional: Structure (BOS/CHoCH) + Liquidity Sweep + VWAP ==="
input bool            InpUseStructure     = true;         // Entry sirf market structure (BOS/CHoCH) ki direction me
input ENUM_TIMEFRAMES InpStructTF         = PERIOD_M15;   // Structure / sweep timeframe
input int             InpSwingLen         = 3;            // Swing point: dono taraf kitne candles (fractal)
input int             InpStructLookback   = 300;          // Kitne candles peeche tak structure padhe
input bool            InpRequireSweep     = false;        // Entry ke liye recent liquidity sweep zaroori
input int             InpSweepBars        = 8;            // Sweep kitne candles purana tak maanya
input bool            InpUseVWAP          = true;         // BUY sirf VWAP ke upar, SELL sirf neeche
input bool            InpVWAPDCA          = false;        // DCA layer sirf VWAP band ke bahar (BUY: VWAP - band se neeche)
input double          InpVWAPBandSD       = 1.0;          // VWAP band = itne standard deviation
input bool            InpDrawInst         = true;         // Chart par VWAP, bands, swing levels, sweep draw karo

input group "=== Filters ==="
input int             InpMaxSpreadPoints  = 50;           // Max spread (points)
input bool            InpUseSession       = true;         // Session filter
input int             InpSessionStart     = 2;            // Start hour (server)
input int             InpSessionEnd       = 22;           // End hour (server)
input bool            InpFridayStop       = true;         // Friday 20:00 ke baad naya basket nahi
input bool            InpAllowBuy         = true;         // Allow BUY
input bool            InpAllowSell        = true;         // Allow SELL

//==================== ENGINE ====================
struct Engine
  {
   string            name;
   bool              on;
   long              magic;
   ENUM_TIMEFRAMES   sigTF, trendTF;
   int               hTF, hTS, hSF, hSS, hRSI, hATR, hMACD;
   double            lotFactor, lotMult;
   int               stepMode; double step, stepATR, stepGrowth;
   int               maxLayers;
   int               tpMode; double tp, tpATR, tpMin;
   double            stopPct, maxATR, minATR;
   int               cooldownSec, maxBaskets;
   bool              tickMode, useMACD;
   int               maxSpread;
   string            tag;
   double            lotScale;
   // state
   datetime          lastSigBar, lastCloseTime, lastLayerTime;
   double            basketStartEq, syncedTP, syncedSL;
   int               syncedLayers, basketsToday, tradesToday;
   datetime          lastLayerBar;
   bool              trailActive, manual, booked;
   double            trailSL;
   int               adoptDir;
   int               side;      // 1 = sirf BUY basket, -1 = sirf SELL basket, 0 = dono
   double            maxMove;   // average se sabse zyada favourable move (backup exit ke liye)
   bool              dcaPaused; // reversal ki wajah se DCA ruka hai
   datetime          recLast;   // aakhri recovery hedge kab khula
   string            dcaWhy;    // DCA abhi kyun nahi juda
   double            dcaNext;   // agla DCA price
  };

CTrade   trade;
Engine   E[NE];

// Tick buffer (tick-by-tick momentum)
#define TKBUF 1024
double   tkBid[TKBUF];
long     tkMsc[TKBUF];
int      tkHead = 0, tkCount = 0;

//--- Scanner
struct ScoreResult { int total, mtf, mom, vol, ses, liq, flow, cross; };
ENUM_TIMEFRAMES scTF[5] = {PERIOD_M5, PERIOD_M15, PERIOD_H1, PERIOD_H4, PERIOD_D1};
int      hScF[5], hScS[5];
int      hScRSI = INVALID_HANDLE, hScMACD = INVALID_HANDLE, hScADX = INVALID_HANDLE, hScATR = INVALID_HANDLE;
int      hDolEMA = INVALID_HANDLE, hSilF = INVALID_HANDLE, hSilS = INVALID_HANDLE;
string   symDollar = "", symSilver = "";
ScoreResult lastScan; int lastScanDir = 0; datetime lastScanTime = 0;
int      hMF = INVALID_HANDLE, hMS = INVALID_HANDLE;
datetime lastNewsCheck = 0;
bool     newsActive = false, newsSoon = false, dayStopped = false;
double   dayStartEq = 0;
int      dayKey = -1;
datetime cutlossUntil = 0;

struct SRLevel { double price; int rank; string tag; };
SRLevel  levels[];
datetime lastLevelsBar = 0, lastLevelsTry = 0;
#define  SRPFX "GDCA_SR_"
#define  PFX   "GDCA_P_"
#define  IPFX  "GDCA_I_"

//--- Institutional state
int      stBias = 0;           // 1 = bullish structure, -1 = bearish
string   stType = "";          // "BOS" ya "CHoCH"
double   stSwingH = 0, stSwingL = 0, stBreakLvl = 0;
datetime stBreakTime = 0, stLastBar = 0;
int      swDir = 0;            // latest liquidity sweep: 1 = sell-side sweep (BUY), -1 = buy-side sweep (SELL)
double   swLevel = 0;
datetime swTime = 0;
double   vwap = 0, vwapSD = 0;
datetime vwapBar = 0;

//--- Chart button controls (runtime, inputs ke upar override)
bool     rtPaused = false;
int      rtSide = 0;          // 0 = BUY+SELL, 1 = BUY only, -1 = SELL only
double   rtLotMult = 1.0;     // lot multiplier
double   rtDayLoss = -1;      // runtime daily loss % (-1 = input)
string   gvCtl = "";

bool SetupEngine(Engine &e, string name, bool on, long magic, ENUM_TIMEFRAMES sig, ENUM_TIMEFRAMES tr,
                 double lotF, double lotM, int stepMode, double step, double stepATR, double growth, int layers,
                 int tpMode, double tp, double tpATR, double tpMin, double stopPct, int cool, int maxB,
                 double maxATR, double minATR)
  {
   e.name = name; e.on = on; e.magic = magic; e.sigTF = sig; e.trendTF = tr;
   e.lotFactor = lotF; e.lotMult = lotM; e.stepMode = stepMode; e.step = step; e.stepATR = stepATR;
   e.stepGrowth = growth; e.maxLayers = layers; e.tpMode = tpMode; e.tp = tp; e.tpATR = tpATR; e.tpMin = tpMin;
   e.stopPct = stopPct; e.cooldownSec = cool * 60;
   e.lotScale = 1.0;
   e.tickMode = false; e.useMACD = InpUseMACD; e.maxSpread = InpMaxSpreadPoints; e.tag = StringSubstr(name, 0, 2); e.maxBaskets = maxB; e.maxATR = maxATR; e.minATR = minATR;
   e.lastSigBar = 0; e.lastCloseTime = 0; e.lastLayerTime = 0;
   e.basketStartEq = AccountInfoDouble(ACCOUNT_EQUITY); e.syncedTP = 0; e.syncedSL = 0;
   e.syncedLayers = 0; e.basketsToday = 0; e.tradesToday = 0;
   e.lastLayerBar = 0; e.trailActive = false; e.trailSL = 0; e.manual = false; e.adoptDir = 0; e.booked = false; e.side = 0; e.maxMove = 0; e.dcaPaused = false; e.recLast = 0; e.dcaWhy = ""; e.dcaNext = 0;
   e.hTF = e.hTS = e.hSF = e.hSS = e.hRSI = e.hATR = e.hMACD = INVALID_HANDLE;
   e.hTF   = iMA(_Symbol, tr,  InpTrendFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   e.hTS   = iMA(_Symbol, tr,  InpTrendSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   e.hSF   = iMA(_Symbol, sig, InpSigFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   e.hSS   = iMA(_Symbol, sig, InpSigSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   e.hRSI  = iRSI(_Symbol, sig, InpRSIPeriod, PRICE_CLOSE);
   e.hATR  = iATR(_Symbol, sig, InpATRPeriod);
   e.hMACD = iMACD(_Symbol, sig, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE);
   return !(e.hTF == INVALID_HANDLE || e.hTS == INVALID_HANDLE || e.hSF == INVALID_HANDLE ||
            e.hSS == INVALID_HANDLE || e.hRSI == INVALID_HANDLE || e.hATR == INVALID_HANDLE || e.hMACD == INVALID_HANDLE);
  }

void ReleaseEngine(Engine &e)
  {
   if(e.hTF == INVALID_HANDLE) return;
   IndicatorRelease(e.hTF); IndicatorRelease(e.hTS); IndicatorRelease(e.hSF); IndicatorRelease(e.hSS);
   IndicatorRelease(e.hRSI); IndicatorRelease(e.hATR); IndicatorRelease(e.hMACD);
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetDeviationInPoints(50);
   trade.SetTypeFillingBySymbol(_Symbol);

   hMF = iMA(_Symbol, InpMasterTF, InpMasterFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hMS = iMA(_Symbol, InpMasterTF, InpMasterSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   if(hMF == INVALID_HANDLE || hMS == INVALID_HANDLE) return(INIT_FAILED);

   if(!SetupEngine(E[0], "SCALP", InpScOn, InpMagic + 1, InpScSigTF, InpScTrendTF, InpScLotFactor, InpScLotMult,
                   InpScStepMode, InpScStep, InpScStepATR, InpScStepGrowth, InpScMaxLayers,
                   InpScTPMode, InpScTP, InpScTP_ATR, InpScTPMin, InpScStopPct, InpScCooldownMin, InpScMaxBaskets,
                   InpScMaxATR, InpScMinATR))
     { Print("Scalp indicator error: ", GetLastError()); return(INIT_FAILED); }
   if(!SetupEngine(E[1], "INTRADAY", InpInOn, InpMagic + 2, InpInSigTF, InpInTrendTF, InpInLotFactor, InpInLotMult,
                   InpInStepMode, InpInStep, InpInStepATR, InpInStepGrowth, InpInMaxLayers,
                   InpInTPMode, InpInTP, InpInTP_ATR, InpInTPMin, InpInStopPct, InpInCooldownMin, InpInMaxBaskets,
                   InpInMaxATR, InpInMinATR))
     { Print("Intraday indicator error: ", GetLastError()); return(INIT_FAILED); }
   if(!SetupEngine(E[2], "TICK-M1", InpTkOn, InpMagic + 3, InpTkSigTF, InpTkTrendTF, InpTkLotFactor, InpTkLotMult,
                   InpTkStepMode, InpTkStep, InpTkStepATR, InpTkStepGrowth, InpTkMaxLayers,
                   InpTkTPMode, InpTkTP, InpTkTP_ATR, InpTkTPMin, InpTkStopPct, 0, InpTkMaxBaskets,
                   InpTkMaxATR, InpTkMinATR))
     { Print("Tick indicator error: ", GetLastError()); return(INIT_FAILED); }
   E[2].tickMode = true; E[2].cooldownSec = InpTkCooldownSec; E[2].useMACD = InpTkUseMACD;
   E[2].maxSpread = InpTkMaxSpread; E[2].tag = "TK";

   E[0].manual = InpManageManual && InpManualEngine == MAN_SCALP && InpScOn;
   E[1].manual = InpManageManual && InpManualEngine == MAN_INTRADAY && InpInOn;
   E[2].manual = InpManageManual && InpManualEngine == MAN_TICK && InpTkOn;

   //--- Hedge mode: har engine ka BUY aur SELL basket alag (slot 3-5 = SELL)
   for(int t = 0; t < NT; t++)
     {
      if(!SetupEngine(E[t + NT], E[t].name, E[t].on, E[t].magic, E[t].sigTF, E[t].trendTF, E[t].lotFactor, E[t].lotMult,
                      E[t].stepMode, E[t].step, E[t].stepATR, E[t].stepGrowth, E[t].maxLayers,
                      E[t].tpMode, E[t].tp, E[t].tpATR, E[t].tpMin, E[t].stopPct, 0, E[t].maxBaskets, E[t].maxATR, E[t].minATR))
        { Print("Hedge engine indicator error: ", GetLastError()); return(INIT_FAILED); }
      E[t + NT].cooldownSec = E[t].cooldownSec; E[t + NT].tickMode = E[t].tickMode; E[t + NT].useMACD = E[t].useMACD;
      E[t + NT].maxSpread = E[t].maxSpread; E[t + NT].tag = E[t].tag; E[t + NT].manual = E[t].manual;
      if(InpHedgeMode)
        {
         E[t].side = 1;       E[t].name = E[t].name + "-BUY";
         E[t + NT].side = -1; E[t + NT].name = E[t + NT].name + "-SELL";
        }
      else
        {
         E[t + NT].on = false;
         E[t + NT].magic = -100 - t;      // hedge off: ye slot kisi position ko match nahi karega
         E[t + NT].manual = false;
        }
     }

   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("WARNING: Ye EA HEDGING account ke liye hai. Netting account par layers merge ho jayenge.");
   if(InpScStopPct <= 0 || InpInStopPct <= 0)
      Print("WARNING: Basket hard stop OFF hai - ek galat trend poora account khatam kar sakta hai!");

   if(!InitScanner()) { Print("Scanner indicator error: ", GetLastError()); return(INIT_FAILED); }

   LoadControls();
   ResetDay();
   UpdateLevels(true);
   EventSetTimer(1);
   return(INIT_SUCCEEDED);
  }

void OnTimer()
  {
   ShowPanel();
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   ObjectsDeleteAll(0, PFX);
   ObjectsDeleteAll(0, IPFX);
   IndicatorRelease(hMF); IndicatorRelease(hMS);
   for(int k = 0; k < NE; k++) ReleaseEngine(E[k]);
   for(int i = 0; i < 5; i++) { IndicatorRelease(hScF[i]); IndicatorRelease(hScS[i]); }
   IndicatorRelease(hScRSI); IndicatorRelease(hScMACD); IndicatorRelease(hScADX); IndicatorRelease(hScATR);
   if(hDolEMA != INVALID_HANDLE) IndicatorRelease(hDolEMA);
   if(hSilF != INVALID_HANDLE) { IndicatorRelease(hSilF); IndicatorRelease(hSilS); }
   ObjectsDeleteAll(0, SRPFX);
   Comment("");
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   UpdateLevels(false);
   UpdateStructure();
   UpdateVWAP();
   CheckNewDay();
   UpdateNews();
   CheckCutloss();
   CheckNetClose();
   CheckRecoveryHedge();
   if(InpFriForceClose && FridayLate(InpFriForceHour) && TotalLayers() > 0)
     {
      Print("Friday FORCE close - sab baskets band");
      Tg("Friday FORCE close - sab baskets band");
      CloseAllEngines();
     }
   RecordTick();

   for(int k = 0; k < NE; k++)
     {
      if(!InpHedgeMode && k >= NT) continue;
      UpdateAdopt(E[k]);
      if(!E[k].on && CountLayers(E[k]) == 0) continue;
      int dir, layers; double avg, lots, lastPrice, profit;
      GetBasket(E[k], dir, layers, avg, lots, lastPrice, profit);
      if(layers > 0)
         ManageBasket(E[k], dir, layers, avg, lastPrice, profit);
      else
         if(E[k].on)
            TryNewBasket(E[k], k);
     }
   ShowPanel();
  }

//==================== DAY TRACKING ====================
void ResetDay()
  {
   if(InpTgDaily && dayStartEq > 0)
     {
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      Tg(StringFormat("DAILY REPORT %s | P/L %+.2f (%+.2f%%) | trades %d | Balance %.2f | Equity %.2f",
                      _Symbol, eq - dayStartEq, (eq - dayStartEq) / dayStartEq * 100.0, TradesToday(),
                      AccountInfoDouble(ACCOUNT_BALANCE), eq));
     }
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   dayKey = dt.year * 1000 + dt.day_of_year;
   dayStartEq = AccountInfoDouble(ACCOUNT_EQUITY);
   dayStopped = false;
   for(int k = 0; k < NE; k++) { E[k].basketsToday = 0; E[k].tradesToday = 0; }
  }

void CheckNewDay()
  {
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.year * 1000 + dt.day_of_year != dayKey && TotalLayers() == 0)
      ResetDay();

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(!dayStopped && dayStartEq > 0 && DayLossPct() > 0 &&
      (dayStartEq - eq) / dayStartEq * 100.0 >= DayLossPct())
     {
      PrintFormat("Daily loss %.1f%% hit - sab close, aaj trading band.", DayLossPct());
      Tg(StringFormat("DAILY LOSS LIMIT %.0f%% hit - sab close, aaj trading band", DayLossPct()));
      CloseAllEngines();
      dayStopped = true;
     }
  }

double DayPLPct()
  {
   if(dayStartEq <= 0) return 0;
   return (AccountInfoDouble(ACCOUNT_EQUITY) - dayStartEq) / dayStartEq * 100.0;
  }

//==================== BASKET ====================
bool IsForeign(long mg)
  {
   for(int k = 0; k < NE; k++) if(mg == E[k].magic) return false;
   return InpManualAnyMagic || mg == 0;
  }

// Selected position is engine ka? (apne magic + adopt kiye manual trades)
bool IsMine(Engine &e)
  {
   if(PositionGetString(POSITION_SYMBOL) != _Symbol) return false;
   if(e.side != 0)
     {
      int pd = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      if(pd != e.side) return false;
     }
   long mg = PositionGetInteger(POSITION_MAGIC);
   if(mg == e.magic) return true;
   if(!e.manual || e.adoptDir == 0 || !IsForeign(mg)) return false;
   int d = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
   return d == e.adoptDir;
  }

// Manual engine ke liye basket direction tay karo
void UpdateAdopt(Engine &e)
  {
   e.adoptDir = 0;
   if(!e.manual) return;
   datetime oldest = 0; int foreignDir = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      long mg = PositionGetInteger(POSITION_MAGIC);
      int d = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      if(e.side != 0 && d != e.side) continue;
      if(mg == e.magic) { e.adoptDir = d; return; }       // apna basket chal raha hai
      if(IsForeign(mg))
        {
         datetime t = (datetime)PositionGetInteger(POSITION_TIME);
         if(oldest == 0 || t < oldest) { oldest = t; foreignDir = d; }
        }
     }
   e.adoptDir = foreignDir;
  }

int CountLayers(Engine &e)
  {
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0) continue;
      if(IsMine(e)) c++;
     }
   return c;
  }

void GetBasket(Engine &e, int &dir, int &layers, double &avg, double &lots, double &lastPrice, double &profit)
  {
   dir = 0; layers = 0; avg = 0; lots = 0; lastPrice = 0; profit = 0;
   double sumPV = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0) continue;
      if(!IsMine(e)) continue;
      double v = PositionGetDouble(POSITION_VOLUME);
      double p = PositionGetDouble(POSITION_PRICE_OPEN);
      bool buy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      dir = buy ? 1 : -1;
      layers++;
      lots += v; sumPV += v * p;
      profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      if(lastPrice == 0 || (buy && p < lastPrice) || (!buy && p > lastPrice)) lastPrice = p;
     }
   if(lots > 0) avg = sumPV / lots;
  }

void ManageBasket(Engine &e, int dir, int layers, double avg, double lastPrice, double profit)
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(InpBrokerSLTP) SyncSLTP(e, dir, layers, avg);

   //--- 1a) Fixed $ exit: +$3 par +$1 lock, phir $2 trailing, +$5 par close
   if(InpFxExit)
     {
      double cur  = (dir == 1) ? bid : ask;
      double move = (dir == 1) ? bid - avg : avg - ask;
      if(move > e.maxMove) e.maxMove = move;
      // Backup: +$2 tak aaya, +$3 nahi chhua, wapas +$0.50 par aaya -> chhote profit me close
      if(InpFxBackup && !e.trailActive && e.maxMove >= InpFxBackupArm && move <= InpFxBackupExit && profit > 0)
        {
         PrintFormat("[%s] Backup exit: max +$%.2f ke baad +$%.2f par close, profit %.2f", e.name, e.maxMove, move, profit);
         CloseBasket(e);
         return;
        }
      if(move >= InpFxTP && profit > 0)
        {
         PrintFormat("[%s] TP +$%.1f hit: %d layers, profit %.2f", e.name, InpFxTP, layers, profit);
         CloseBasket(e);
         return;
        }
      if(!e.trailActive && move >= InpFxTrigger)
        {
         e.trailActive = true;
         e.trailSL = (dir == 1) ? avg + InpFxLock : avg - InpFxLock;
         PrintFormat("[%s] +$%.1f aaya: SL +$%.1f par lock (%.2f), trailing shuru", e.name, InpFxTrigger, InpFxLock, e.trailSL);
         if(InpFxBookPct > 0) BookPartial(e, InpFxBookPct);
        }
      if(e.trailActive)
        {
         double cand = (dir == 1) ? cur - InpFxTrailDist : cur + InpFxTrailDist;
         if(dir == 1 && cand > e.trailSL + 0.1) e.trailSL = cand;
         if(dir == -1 && cand < e.trailSL - 0.1) e.trailSL = cand;
         bool hit = (dir == 1) ? (bid <= e.trailSL) : (ask >= e.trailSL);
         if(hit)
           {
            PrintFormat("[%s] Trailing SL hit: %d layers, profit %.2f", e.name, layers, profit);
            CloseBasket(e);
            return;
           }
        }
     }

   //--- 1) Basket TP / Trailing (ATR mode)
   double tpDist = TPDist(e);
   if(InpFxExit) tpDist = DBL_MAX;   // ATR exit band
   bool tpHit = !InpFxExit && ((dir == 1) ? (bid >= avg + tpDist) : (ask <= avg - tpDist));
   if(InpFxExit) { }
   else if(!InpBasketTrail)
     {
      if(tpHit && profit > 0)
        {
         PrintFormat("[%s] Basket TP: %d layers, profit %.2f", e.name, layers, profit);
         CloseBasket(e);
         return;
        }
     }
   else
     {
      double cur = (dir == 1) ? bid : ask;
      if(!e.trailActive && tpHit)
        {
         e.trailActive = true;
         double lock = tpDist * InpTrailLockPct / 100.0;
         e.trailSL = (dir == 1) ? avg + lock : avg - lock;
         PrintFormat("[%s] Trailing shuru, SL lock %.2f", e.name, e.trailSL);
         if(InpBookPct > 0) BookPartial(e, InpBookPct);
        }
      if(e.trailActive)
        {
         double cand = (dir == 1) ? cur - tpDist * InpTrailDistMult : cur + tpDist * InpTrailDistMult;
         if(dir == 1 && cand > e.trailSL + InpTrailStep) e.trailSL = cand;
         if(dir == -1 && cand < e.trailSL - InpTrailStep) e.trailSL = cand;
         bool hit = (dir == 1) ? (bid <= e.trailSL) : (ask >= e.trailSL);
         if(hit)
           {
            PrintFormat("[%s] Trailing SL hit: %d layers, profit %.2f", e.name, layers, profit);
            CloseBasket(e);
            return;
           }
        }
     }

   //--- 2) Hard stop
   if(e.stopPct > 0 && e.basketStartEq > 0 && profit < 0 &&
      (-profit) / e.basketStartEq * 100.0 >= e.stopPct)
     {
      PrintFormat("[%s] BASKET HARD STOP: loss %.2f (%.1f%%). Sab close.", e.name, profit, e.stopPct);
      CloseBasket(e);
      return;
     }

   //--- 2b) Breakeven exit (lambi DCA ke baad average par lautne par) - Fixed $ exit me band
   if(InpBEExit && !InpFxExit && !e.trailActive && layers >= InpBEMinLayers && profit > 0)
     {
      bool be = (dir == 1) ? (bid >= avg + InpBEBuffer) : (ask <= avg - InpBEBuffer);
      if(be)
        {
         PrintFormat("[%s] Breakeven exit: %d layers, profit %.2f", e.name, layers, profit);
         CloseBasket(e);
         return;
        }
     }

   //--- 3) News se pehle profit lock
   if(InpUseNews && InpNewsCloseProfit && newsSoon && profit > 0)
     {
      PrintFormat("[%s] High-impact news aa rahi hai - basket profit me close.", e.name);
      CloseBasket(e);
      return;
     }

   //--- 3b) Weekend protection
   if(InpFriClose && FridayLate(InpFriHour) && (profit >= 0 || (InpFriMaxLossUSD > 0 && profit >= -InpFriMaxLossUSD)))
     {
      PrintFormat("[%s] Friday close: %d layers, P/L %.2f (weekend gap se bachao)", e.name, layers, profit);
      Tg(StringFormat("Friday close [%s] %d layers, P/L %+.2f", e.name, layers, profit));
      CloseBasket(e);
      return;
     }

   //--- 4) DCA layer (har rukawat ka kaaran e.dcaWhy me, panel par dikhta hai)
   double stepNow = BaseStep(e) * MathPow(e.stepGrowth, layers - 1);
   e.dcaNext = (dir == 1) ? lastPrice - stepNow : lastPrice + stepNow;
   if(!e.on)            { e.dcaWhy = "engine OFF"; return; }
   if(dayStopped)       { e.dcaWhy = "day stopped"; return; }
   if(e.trailActive)    { e.dcaWhy = "trailing (profit lock)"; return; }
   if(rtPaused)         { e.dcaWhy = "PAUSE button"; return; }
   if(TimeCurrent() < cutlossUntil) { e.dcaWhy = "cutloss cooldown"; return; }
   if(InpFriNoDCA && FridayLate(InpFriHour)) { e.dcaWhy = "Friday late"; return; }
   bool hedgeLayer = ReducesNet(dir, LayerLot(e, layers));
   if(!hedgeLayer && !AccountRoomOK(LayerLot(e, layers))) { e.dcaWhy = "margin/lot limit"; return; }
   if(e.maxLayers > 0 && layers >= e.maxLayers) { e.dcaWhy = "max layers"; return; }
   if(InpMaxTotalLots > 0)
     {
      double cur = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
         if(PositionGetTicket(i) != 0 && IsMine(e)) cur += PositionGetDouble(POSITION_VOLUME);
      if(cur + LayerLot(e, layers) > InpMaxTotalLots + 1e-9) { e.dcaWhy = "basket max lots"; return; }
     }
   if(InpVWAPDCA && vwap > 0)
     {
      double band = vwapSD * InpVWAPBandSD;
      if(dir == 1 && ask > vwap - band)  { e.dcaWhy = "VWAP band"; return; }
      if(dir == -1 && bid < vwap + band) { e.dcaWhy = "VWAP band"; return; }
     }
   if(InpUseNews && InpNewsNoDCA && newsActive) { e.dcaWhy = "news"; return; }
   if(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > e.maxSpread)
     { e.dcaWhy = StringFormat("spread %d > %d", (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD), e.maxSpread); return; }
   if(InpAddOnlyInTrend && TrendDir(e.hTF, e.hTS, e.trendTF) != dir) { e.dcaWhy = "trend against"; return; }
   bool rev = InpPauseOnReversal && ReversalAgainst(dir);
   if(rev != e.dcaPaused)
      PrintFormat("[%s] DCA %s", e.name, rev ? "PAUSED - high probability reversal" : "RESUMED");
   e.dcaPaused = rev;
   if(rev) { e.dcaWhy = "reversal pause"; return; }

   bool add = (dir == 1) ? (ask <= e.dcaNext) : (bid >= e.dcaNext);
   if(!add) { e.dcaWhy = StringFormat("waiting $%.0f", stepNow); return; }
   if(InpNewCandleLayer && iTime(_Symbol, e.sigTF, 0) == e.lastLayerBar) { e.dcaWhy = "next candle"; return; }
   if(TimeCurrent() - e.lastLayerTime < InpMinSecBetween) { e.dcaWhy = "min gap sec"; return; }

   double lot = LayerLot(e, layers);
   if(!hedgeLayer && !MarginOK(dir, lot)) { e.dcaWhy = "free margin kam"; return; }
   e.dcaWhy = "";
   if(Open(e, dir, lot, "L" + IntegerToString(layers + 1)))
      PrintFormat("[%s] DCA layer %d @ %.2f, lot %.2f", e.name, layers + 1, dir == 1 ? ask : bid, lot);
   else
      e.dcaWhy = StringFormat("order fail %d", trade.ResultRetcode());
  }

void CloseBasket(Engine &e)
  {
   int cd, cl; double ca, clt, clp, cpr;
   GetBasket(e, cd, cl, ca, clt, clp, cpr);
   if(cl > 0)
      Tg(StringFormat("%s CLOSED [%s] %s | %d layers, %.2f lot | P/L %+.2f | Equity %.2f",
                      cpr >= 0 ? "PROFIT" : "LOSS", e.name, cd == 1 ? "BUY" : "SELL", cl, clt, cpr,
                      AccountInfoDouble(ACCOUNT_EQUITY)));
   trade.SetExpertMagicNumber(e.magic);
   for(int pass = 0; pass < 3; pass++)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(t == 0) continue;
         if(!IsMine(e)) continue;
         if(!PositionSelectByTicket(t)) continue;     // broker ne SL/TP se pehle hi band kar diya
         trade.PositionClose(t);
        }
      if(CountLayers(e) == 0) break;
     }
   e.lastCloseTime = TimeCurrent();
   e.syncedTP = 0; e.syncedSL = 0; e.syncedLayers = 0;
   e.trailActive = false; e.trailSL = 0; e.lotScale = 1.0; e.booked = false; e.maxMove = 0;
   e.basketStartEq = AccountInfoDouble(ACCOUNT_EQUITY);
  }

int TotalLayers()
  {
   int n = 0;
   for(int k = 0; k < NE; k++) n += CountLayers(E[k]);
   return n;
  }

void CloseAllEngines()
  {
   for(int k = 0; k < NE; k++) CloseBasket(E[k]);
  }

//==================== TICK BUFFER ====================
void RecordTick()
  {
   MqlTick t;
   if(!SymbolInfoTick(_Symbol, t)) return;
   int last = (tkHead - 1 + TKBUF) % TKBUF;
   if(tkCount > 0 && tkMsc[last] == t.time_msc && tkBid[last] == t.bid) return;
   tkBid[tkHead] = t.bid; tkMsc[tkHead] = t.time_msc;
   tkHead = (tkHead + 1) % TKBUF;
   if(tkCount < TKBUF) tkCount++;
  }

// Pichle InpTkWindowSec seconds me move: 1 = trend direction me valid burst, 0 = nahi
int TickMomentum(int trend)
  {
   if(tkCount < 2) return 0;
   int newest = (tkHead - 1 + TKBUF) % TKBUF;
   long nowMs = tkMsc[newest];
   long fromMs = nowMs - (long)InpTkWindowSec * 1000;
   int n = 0; double oldest = tkBid[newest], hi = tkBid[newest], lo = tkBid[newest];
   for(int i = 0; i < tkCount; i++)
     {
      int idx = (newest - i + TKBUF) % TKBUF;
      if(tkMsc[idx] < fromMs) break;
      oldest = tkBid[idx]; n++;
      hi = MathMax(hi, tkBid[idx]); lo = MathMin(lo, tkBid[idx]);
     }
   if(n < InpTkMinTicks) return 0;
   double move = tkBid[newest] - oldest;
   if(MathAbs(move) > InpTkMaxMove || (hi - lo) > InpTkMaxMove) return 0;   // spike / news jhatka
   if(trend == 1 && move >= InpTkMinMove) return 1;
   if(trend == -1 && move <= -InpTkMinMove) return 1;
   return 0;
  }

//==================== MARKET SCANNER ====================
// Broker suffix ke saath symbol dhoondo (XAUUSDm -> EURUSDm)
string FindSymbol(string base)
  {
   if(base == "") return "";
   if(SymbolSelect(base, true)) return base;
   string suffix = "";
   int p = StringFind(_Symbol, "XAUUSD");
   if(p >= 0) suffix = StringSubstr(_Symbol, p + 6);
   string pre = (p > 0) ? StringSubstr(_Symbol, 0, p) : "";
   string cand = pre + base + suffix;
   if(cand != base && SymbolSelect(cand, true)) return cand;
   return "";
  }

bool InitScanner()
  {
   for(int i = 0; i < 5; i++)
     {
      hScF[i] = iMA(_Symbol, scTF[i], 50, 0, MODE_EMA, PRICE_CLOSE);
      hScS[i] = iMA(_Symbol, scTF[i], 200, 0, MODE_EMA, PRICE_CLOSE);
      if(hScF[i] == INVALID_HANDLE || hScS[i] == INVALID_HANDLE) return false;
     }
   hScRSI  = iRSI(_Symbol, PERIOD_H1, 14, PRICE_CLOSE);
   hScMACD = iMACD(_Symbol, PERIOD_M15, 12, 26, 9, PRICE_CLOSE);
   hScADX  = iADX(_Symbol, PERIOD_H1, 14);
   hScATR  = iATR(_Symbol, PERIOD_M15, 14);
   if(hScRSI == INVALID_HANDLE || hScMACD == INVALID_HANDLE || hScADX == INVALID_HANDLE || hScATR == INVALID_HANDLE)
      return false;

   symDollar = FindSymbol(InpSymDollar);
   symSilver = FindSymbol(InpSymSilver);
   if(symDollar != "") hDolEMA = iMA(symDollar, PERIOD_M15, 21, 0, MODE_EMA, PRICE_CLOSE);
   if(symSilver != "")
     {
      hSilF = iMA(symSilver, PERIOD_H1, 50, 0, MODE_EMA, PRICE_CLOSE);
      hSilS = iMA(symSilver, PERIOD_H1, 200, 0, MODE_EMA, PRICE_CLOSE);
     }
   PrintFormat("Scanner ready. Dollar proxy: %s | Silver: %s",
               symDollar == "" ? "NOT FOUND (neutral)" : symDollar, symSilver == "" ? "NOT FOUND (neutral)" : symSilver);
   return true;
  }

double B1(int h, int buf, int shift)
  {
   double a[];
   ArraySetAsSeries(a, true);
   if(CopyBuffer(h, buf, shift, 1, a) != 1) return EMPTY_VALUE;
   return a[0];
  }

// 1) Multi-timeframe alignment (25): M5, M15, H1, H4, D1 - har ek 5
int ScoreMTF(int dir)
  {
   int pts = 0;
   for(int i = 0; i < 5; i++)
     {
      double f = B1(hScF[i], 0, 1), sl = B1(hScS[i], 0, 1);
      double c = iClose(_Symbol, scTF[i], 1);
      if(f == EMPTY_VALUE || sl == EMPTY_VALUE || c == 0) continue;
      if(dir == 1 && f > sl && c > f) pts += 5;
      if(dir == -1 && f < sl && c < f) pts += 5;
     }
   return pts;
  }

// 2) Momentum (15): H1 RSI, M15 MACD histogram, H1 ADX + DI
int ScoreMomentum(int dir)
  {
   int pts = 0;
   double r = B1(hScRSI, 0, 1);
   if(r != EMPTY_VALUE)
     {
      if(dir == 1 && r >= 52 && r <= 72) pts += 5;
      if(dir == -1 && r <= 48 && r >= 28) pts += 5;
     }
   double m0 = B1(hScMACD, 0, 1), s0 = B1(hScMACD, 1, 1), m1 = B1(hScMACD, 0, 2), s1 = B1(hScMACD, 1, 2);
   if(m0 != EMPTY_VALUE && m1 != EMPTY_VALUE)
     {
      double h0 = m0 - s0, h1 = m1 - s1;
      if(dir == 1 && h0 > 0 && h0 >= h1) pts += 5;
      if(dir == -1 && h0 < 0 && h0 <= h1) pts += 5;
     }
   double adx = B1(hScADX, 0, 1), pdi = B1(hScADX, 1, 1), mdi = B1(hScADX, 2, 1);
   if(adx != EMPTY_VALUE && adx >= 20)
     {
      if(dir == 1 && pdi > mdi) pts += 5;
      if(dir == -1 && mdi > pdi) pts += 5;
     }
   return pts;
  }

// 3) Volatility (10): M15 ATR apne 50-bar average ke mukable normal ho
int ScoreVolatility()
  {
   double a[];
   ArraySetAsSeries(a, true);
   if(CopyBuffer(hScATR, 0, 1, 50, a) != 50) return 0;
   double avg = 0;
   for(int i = 0; i < 50; i++) avg += a[i];
   avg /= 50.0;
   if(avg <= 0) return 0;
   double ratio = a[0] / avg;
   if(ratio >= 0.8 && ratio <= 2.0) return 10;
   if(ratio >= 0.6 && ratio <= 2.5) return 5;
   return 0;   // dead market ya pagal volatility
  }

// 4) Session (10): London/NY overlap best
int ScoreSession()
  {
   MqlDateTime g;
   TimeToStruct(TimeCurrent() - InpServerGMTOffset * 3600, g);
   int h = g.hour;
   bool london = (h >= 7 && h < 16), ny = (h >= 12 && h < 21);
   if(london && ny) return 10;
   if(london || ny) return 7;
   return 3;   // Asia
  }

// 5) Liquidity (15): stop-hunt sweep ya aage jagah
int ScoreLiquidity(int dir)
  {
   double atr = B1(hScATR, 0, 1);
   if(atr == EMPTY_VALUE || atr <= 0) return 0;
   double price = (dir == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // Reference liquidity: previous day H/L + M15 swing (bars 13..60)
   double pdh = iHigh(_Symbol, PERIOD_D1, 1), pdl = iLow(_Symbol, PERIOD_D1, 1);
   int hiIdx = iHighest(_Symbol, PERIOD_M15, MODE_HIGH, 48, 13);
   int loIdx = iLowest(_Symbol, PERIOD_M15, MODE_LOW, 48, 13);
   double swH = hiIdx >= 0 ? iHigh(_Symbol, PERIOD_M15, hiIdx) : 0;
   double swL = loIdx >= 0 ? iLow(_Symbol, PERIOD_M15, loIdx) : 0;

   double refs[2];
   refs[0] = (dir == 1) ? pdl : pdh;
   refs[1] = (dir == 1) ? swL : swH;
   for(int r = 0; r < 2; r++)
     {
      double lv = refs[r];
      if(lv <= 0) continue;
      for(int i = 1; i <= 12; i++)
        {
         double lo = iLow(_Symbol, PERIOD_M15, i), hi = iHigh(_Symbol, PERIOD_M15, i), cl = iClose(_Symbol, PERIOD_M15, i);
         if(dir == 1 && lo < lv && cl > lv && price > lv) return 15;    // sell-side liquidity sweep -> BUY
         if(dir == -1 && hi > lv && cl < lv && price < lv) return 15;   // buy-side liquidity sweep -> SELL
        }
     }

   // Sweep nahi: aage kitni jagah hai (nearest opposing S/R)
   double nearest = DBL_MAX;
   for(int i = 0; i < ArraySize(levels); i++)
     {
      if(levels[i].rank < 1) continue;
      double d = levels[i].price - price;
      if(dir == 1 && d > 0) nearest = MathMin(nearest, d);
      if(dir == -1 && d < 0) nearest = MathMin(nearest, -d);
     }
   if(nearest >= 3.0 * atr) return 10;
   if(nearest >= 1.5 * atr) return 5;
   return 0;
  }

// 6) Order flow (15): tick pressure (last 60s) + tick volume surge
int ScoreFlow(int dir)
  {
   int pts = 0;
   if(tkCount > 2)
     {
      int newest = (tkHead - 1 + TKBUF) % TKBUF;
      long fromMs = tkMsc[newest] - 60000;
      int up = 0, dn = 0;
      for(int i = 0; i < tkCount - 1; i++)
        {
         int a = (newest - i + TKBUF) % TKBUF, b = (newest - i - 1 + TKBUF) % TKBUF;
         if(tkMsc[b] < fromMs) break;
         if(tkBid[a] > tkBid[b]) up++;
         else if(tkBid[a] < tkBid[b]) dn++;
        }
      int tot = up + dn;
      if(tot >= 10)
        {
         double share = (dir == 1) ? (double)up / tot : (double)dn / tot;
         if(share >= 0.60) pts += 8;
         else if(share >= 0.55) pts += 4;
        }
     }
   long v[];
   ArraySetAsSeries(v, true);
   if(CopyTickVolume(_Symbol, PERIOD_M5, 1, 21, v) == 21)
     {
      double avg = 0;
      for(int i = 1; i < 21; i++) avg += (double)v[i];
      avg /= 20.0;
      double o = iOpen(_Symbol, PERIOD_M5, 1), c = iClose(_Symbol, PERIOD_M5, 1);
      bool candleOK = (dir == 1) ? c > o : c < o;
      if(avg > 0 && v[0] > 1.5 * avg && candleOK) pts += 7;
      else if(avg > 0 && v[0] > 1.2 * avg && candleOK) pts += 3;
     }
   return pts;
  }

// 7) Cross-asset (10): Dollar ulta, Silver saath. Symbol na mile to neutral (half)
int ScoreCross(int dir)
  {
   int pts = 0;
   if(hDolEMA == INVALID_HANDLE) pts += 2;
   else
     {
      double e = B1(hDolEMA, 0, 1), c = iClose(symDollar, PERIOD_M15, 1);
      // EURUSD upar = Dollar kamzor = Gold BUY ke liye achha
      if(e != EMPTY_VALUE && c > 0)
        {
         if(dir == 1 && c > e) pts += 5;
         if(dir == -1 && c < e) pts += 5;
        }
     }
   if(hSilF == INVALID_HANDLE) pts += 2;
   else
     {
      double f = B1(hSilF, 0, 1), sl = B1(hSilS, 0, 1), c = iClose(symSilver, PERIOD_H1, 1);
      if(f != EMPTY_VALUE && sl != EMPTY_VALUE && c > 0)
        {
         if(dir == 1 && f > sl && c > f) pts += 5;
         if(dir == -1 && f < sl && c < f) pts += 5;
        }
     }
   return pts;
  }

void ScanMarket(int dir, ScoreResult &r)
  {
   r.mtf = ScoreMTF(dir);
   r.mom = ScoreMomentum(dir);
   r.vol = ScoreVolatility();
   r.ses = ScoreSession();
   r.liq = ScoreLiquidity(dir);
   r.flow = ScoreFlow(dir);
   r.cross = ScoreCross(dir);
   r.total = r.mtf + r.mom + r.vol + r.ses + r.liq + r.flow + r.cross;
  }

string Tier(int score)
  {
   if(score >= InpEliteScore) return "ELITE";
   if(score >= InpMinScore) return "HIGH";
   if(score >= InpMedScore) return "MEDIUM";
   return "LOW";
  }

string ScoreText(ScoreResult &r)
  {
   return StringFormat("[MTF %d/25 MOM %d/15 VOL %d/10 SES %d/10 LIQ %d/15 FLOW %d/15 X %d/10]",
                       r.mtf, r.mom, r.vol, r.ses, r.liq, r.flow, r.cross);
  }

//==================== 50% BOOKING ====================
// TP par basket ka pct% volume close karo (pehle poori chhoti positions, phir partial)
void BookPartial(Engine &e, double pct)
  {
   ulong  tk[]; double vl[];
   double total = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !IsMine(e)) continue;
      int n = ArraySize(tk);
      ArrayResize(tk, n + 1); ArrayResize(vl, n + 1);
      tk[n] = t; vl[n] = PositionGetDouble(POSITION_VOLUME);
      total += vl[n];
     }
   double target = total * pct / 100.0;
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double stepL  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(stepL <= 0) stepL = 0.01;
   double closed = 0;
   trade.SetExpertMagicNumber(e.magic);
   for(int i = 0; i < ArraySize(tk) && closed < target - 1e-9; i++)
     {
      double remain = target - closed;
      if(vl[i] <= remain + 1e-9)
        {
         if(trade.PositionClose(tk[i])) closed += vl[i];
        }
      else
        {
         double part = MathFloor(remain / stepL + 1e-9) * stepL;
         if(part >= minLot && vl[i] - part >= minLot - 1e-9)
           {
            if(trade.PositionClosePartial(tk[i], NormalizeDouble(part, 2))) closed += part;
           }
        }
     }
   e.booked = closed > 0;
   if(closed > 0)
      PrintFormat("[%s] Profit booked: %.2f / %.2f lots (%.0f%%), baaki trailing SL par", e.name, closed, total, pct);
   else
      PrintFormat("[%s] Lot itna chhota hai ki %.0f%% book nahi ho sakta - poora basket trailing par", e.name, pct);
  }

//==================== CUTLOSS ($) ====================
void CheckCutloss()
  {
   if(InpCutlossUSD <= 0) return;
   double total = 0;
   for(int k = 0; k < NE; k++)
     {
      int d, l; double a, lots, lp, pr;
      GetBasket(E[k], d, l, a, lots, lp, pr);
      total += pr;
     }
   if(total > -InpCutlossUSD) return;
   PrintFormat("CUTLOSS: floating %.2f <= -%.2f. Sab close.", total, InpCutlossUSD);
   Tg(StringFormat("CUTLOSS: floating %.2f - sab close", total));
   CloseAllEngines();
   if(InpResumeAfterCut) cutlossUntil = TimeCurrent() + InpCutCooldownMin * 60;
   else dayStopped = true;
  }

//==================== ENTRY ====================
void TryNewBasket(Engine &e, int k)
  {
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dayStopped || rtPaused) return;
   if(TimeCurrent() < cutlossUntil) return;
   if(InpDailyTargetPct > 0 && DayPLPct() >= InpDailyTargetPct) return;
   if(e.basketsToday >= e.maxBaskets) return;
   if(TimeCurrent() - e.lastCloseTime < e.cooldownSec) return;
   if(InpUseNews && (newsActive || newsSoon)) return;
   if(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > e.maxSpread) return;
   if(InpUseSession && (dt.hour < InpSessionStart || dt.hour >= InpSessionEnd)) return;
   if(InpFridayStop && dt.day_of_week == 5 && dt.hour >= 20) return;

   int sig = 0;
   if(e.tickMode)
     {
      // Har tick par check, lekin ek M1 candle me sirf ek naya basket
      if(iTime(_Symbol, e.sigTF, 0) == e.lastSigBar) return;
      sig = Signal(e);
      if(sig != 0) e.lastSigBar = iTime(_Symbol, e.sigTF, 0);
     }
   else
     {
      datetime bar = iTime(_Symbol, e.sigTF, 0);
      if(bar == 0 || bar == e.lastSigBar) return;
      e.lastSigBar = bar;
      sig = Signal(e);
     }
   if(sig == 0) return;
   if(e.side != 0 && sig != e.side) return;
   if(!InstOK(sig)) return;
   if(sig == 1 && (!InpAllowBuy || rtSide == -1)) return;
   if(sig == -1 && (!InpAllowSell || rtSide == 1)) return;

   // Doosre engine ka basket ulti direction me ho to skip
   if(InpNoOpposite && !InpHedgeMode)
     {
      for(int j = 0; j < NE; j++)
        {
         if(j == k) continue;
         int od, ol; double oa, olots, olp, opr;
         GetBasket(E[j], od, ol, oa, olots, olp, opr);
         if(ol > 0 && od != sig) return;
        }
     }

   if(InpUseSRFilter && SRBlocked(sig)) return;

   //--- Market Scanner: sirf high probability
   ScoreResult sc;
   e.lotScale = 1.0;
   if(InpUseScanner)
     {
      ScanMarket(sig, sc);
      if(sc.total < InpMinScore)
        {
         PrintFormat("[%s] %s skip: score %d < %d  %s", e.name, sig == 1 ? "BUY" : "SELL", sc.total, InpMinScore, ScoreText(sc));
         return;
        }
      if(sc.total >= InpEliteScore) e.lotScale = InpEliteLotMult;
      PrintFormat("[%s] %s score %d (%s)  %s", e.name, sig == 1 ? "BUY" : "SELL", sc.total, Tier(sc.total), ScoreText(sc));
     }

   double lot = LayerLot(e, 0);
   bool hedgeOpen = ReducesNet(sig, lot);       // hedge (net lot ghatata hai) = limit se chhoot
   if(!hedgeOpen && !MarginOK(sig, lot)) return;
   if(!hedgeOpen && !AccountRoomOK(lot)) return;
   if(hedgeOpen && !AccountRoomOK(lot)) PrintFormat("[%s] Limit lagi hai, lekin ye HEDGE hai (net lot ghatega) - khol rahe hain", e.name);
   e.basketStartEq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(Open(e, sig, lot, "L1"))
     {
      e.basketsToday++;
      PrintFormat("[%s] New %s basket, lot %.2f", e.name, sig == 1 ? "BUY" : "SELL", lot);
     }
  }

bool Buf(int h, int start, int count, double &a[])
  {
   ArraySetAsSeries(a, true);
   return CopyBuffer(h, 0, start, count, a) == count;
  }

int TrendDir(int hf, int hs, ENUM_TIMEFRAMES tf)
  {
   double f[], s[];
   if(!Buf(hf, 1, 1, f) || !Buf(hs, 1, 1, s)) return 0;
   double c = iClose(_Symbol, tf, 1);
   if(f[0] > s[0] && c > f[0]) return 1;
   if(f[0] < s[0] && c < f[0]) return -1;
   return 0;
  }

int MasterTrend() { return TrendDir(hMF, hMS, InpMasterTF); }

int Signal(Engine &e)
  {
   int trend = TrendDir(e.hTF, e.hTS, e.trendTF);
   if(trend == 0 || trend != MasterTrend()) return 0;   // engine trend + master trend dono same

   double f[], s[], r[], a[];
   if(!Buf(e.hSF, 1, 2, f) || !Buf(e.hSS, 1, 2, s) || !Buf(e.hRSI, 1, 1, r) || !Buf(e.hATR, 1, 1, a)) return 0;
   if(e.maxATR > 0 && a[0] > e.maxATR) return 0;   // bahut volatile
   if(e.minATR > 0 && a[0] < e.minATR) return 0;   // market dead

   if(e.tickMode && TickMomentum(trend) == 0) return 0;   // tick burst trend direction me chahiye

   if(e.useMACD)
     {
      double mm[], ms[];
      ArraySetAsSeries(mm, true); ArraySetAsSeries(ms, true);
      if(CopyBuffer(e.hMACD, 0, 1, 2, mm) != 2 || CopyBuffer(e.hMACD, 1, 1, 2, ms) != 2) return 0;
      double h0 = mm[0] - ms[0], h1 = mm[1] - ms[1];
      bool macdBuy  = (mm[0] > ms[0]) && (h0 >= h1) && (!InpMACDZeroLine || mm[0] > 0);
      bool macdSell = (mm[0] < ms[0]) && (h0 <= h1) && (!InpMACDZeroLine || mm[0] < 0);
      if(trend == 1 && !macdBuy) return 0;
      if(trend == -1 && !macdSell) return 0;
     }

   double c = iClose(_Symbol, e.sigTF, 1);
   double o = iOpen(_Symbol, e.sigTF, 1);
   if(trend == 1 && f[0] > s[0] && c > f[0] && c > o && r[0] >= InpRSIBuyMin && r[0] <= InpRSIBuyMax)
      return 1;
   if(trend == -1 && f[0] < s[0] && c < f[0] && c < o && r[0] >= InpRSISellMin && r[0] <= InpRSISellMax)
      return -1;
   return 0;
  }

//==================== AUTO TP / SL ====================
double SigATR(Engine &e)
  {
   double a[];
   if(Buf(e.hATR, 1, 1, a)) return a[0];
   return 0;
  }

double TPDist(Engine &e)
  {
   if(InpFxExit) return InpFxTP;
   if(e.tpMode == TP_ATR)
     {
      double a = SigATR(e);
      if(a > 0) return MathMax(a * e.tpATR, e.tpMin);
     }
   return e.tp;
  }

void SyncSLTP(Engine &e, int dir, int layers, double avg)
  {
   int    digits  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   long   stopsLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long   freezeLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double minStop = (double)MathMax(stopsLvl, freezeLvl) * _Point + 5 * _Point;
   double freeze  = (double)freezeLvl * _Point + 2 * _Point;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double totalLots = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0) continue;
      if(IsMine(e)) totalLots += PositionGetDouble(POSITION_VOLUME);
     }
   if(totalLots <= 0) return;

   double tp = NormalizeDouble(dir == 1 ? avg + TPDist(e) : avg - TPDist(e), digits);
   double sl = 0;
   if(e.stopPct > 0 && e.basketStartEq > 0)
     {
      double perDollar = 0;
      ENUM_ORDER_TYPE ot = dir == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(OrderCalcProfit(ot, _Symbol, 1.0, avg, dir == 1 ? avg + 1.0 : avg - 1.0, perDollar) && perDollar > 0)
        {
         double allow = e.basketStartEq * e.stopPct / 100.0;
         if(InpCutlossUSD > 0) allow = MathMin(allow, InpCutlossUSD);
         double dist = allow / (totalLots * perDollar);
         sl = NormalizeDouble(dir == 1 ? avg - dist : avg + dist, digits);
        }
     }

   if(e.trailActive)
     {
      if(!InpFxExit) tp = 0;   // ATR mode: trailing chal raha hai - TP hata do; Fixed mode: +$5 TP rehta hai
      sl = NormalizeDouble(e.trailSL, digits);
     }
   // Price ke bahut paas wala SL/TP broker reject karta hai: tab naya value mat bhejo, purana rehne do (0 kabhi nahi)
   bool tpOK = tp > 0 && ((dir == 1) ? (tp - ask >= minStop) : (bid - tp >= minStop));
   bool slOK = sl > 0 && ((dir == 1) ? (bid - sl >= minStop) : (sl - ask >= minStop));

   bool changed = (layers != e.syncedLayers) || MathAbs(tp - e.syncedTP) > 50 * _Point || MathAbs(sl - e.syncedSL) > 20 * _Point;
   if(!changed) return;

   trade.SetExpertMagicNumber(e.magic);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(!IsMine(e)) continue;
      double curSL = PositionGetDouble(POSITION_SL), curTP = PositionGetDouble(POSITION_TP);
      double px = (dir == 1) ? bid : ask;
      // freeze zone: purana SL/TP price ke itna paas hai ki broker modify nahi karne dega
      if((curSL > 0 && MathAbs(px - curSL) <= freeze) || (curTP > 0 && MathAbs(px - curTP) <= freeze)) continue;
      double nSL = slOK ? sl : curSL;
      double nTP = tpOK ? tp : curTP;
      if(MathAbs(curSL - nSL) < _Point && MathAbs(curTP - nTP) < _Point) continue;
      trade.PositionModify(t, nSL, nTP);
     }
   e.syncedTP = tp; e.syncedSL = sl; e.syncedLayers = layers;
  }

//==================== HELPERS ====================
double BaseStep(Engine &e)
  {
   if(e.stepMode == STEP_ATR)
     {
      double a = SigATR(e);
      if(a > 0) return a * e.stepATR;
     }
   return e.step;
  }

double NormLot(double lot)
  {
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(st <= 0) st = 0.01;
   lot = MathFloor(lot / st + 1e-9) * st;
   lot = MathMax(mn, MathMin(lot, MathMin(mx, InpMaxLot)));
   return NormalizeDouble(lot, 2);
  }

double LayerLot(Engine &e, int layerIndex)
  {
   double base = InpFixedLot;
   if(InpLotMode == LOT_AUTO && InpBalancePerLot > 0)
      base = 0.01 * MathFloor(AccountInfoDouble(ACCOUNT_BALANCE) / InpBalancePerLot);
   if(base <= 0) base = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double first = base * e.lotFactor * e.lotScale * rtLotMult;
   if(InpLotProgression == PROG_FIXED_ADD)
      return NormLot(first + first * InpLotAddFactor * layerIndex);
   return NormLot(first * MathPow(e.lotMult, layerIndex));
  }

bool MarginOK(int dir, double lot)
  {
   double price = dir == 1 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double m = 0;
   if(!OrderCalcMargin(dir == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, lot, price, m)) return false;
   return (AccountInfoDouble(ACCOUNT_MARGIN_FREE) - m) > AccountInfoDouble(ACCOUNT_EQUITY) * 0.3;
  }

bool Open(Engine &e, int dir, double lot, string tag)
  {
   trade.SetExpertMagicNumber(e.magic);
   string cm = InpComment + "_" + e.tag + "_" + tag;
   bool ok = (dir == 1) ? trade.Buy(lot, _Symbol, 0, 0, 0, cm) : trade.Sell(lot, _Symbol, 0, 0, 0, cm);
   if(ok && (trade.ResultRetcode() == TRADE_RETCODE_DONE || trade.ResultRetcode() == TRADE_RETCODE_PLACED))
     {
      e.lastLayerTime = TimeCurrent();
      e.lastLayerBar = iTime(_Symbol, e.sigTF, 0);
      e.maxMove = 0;      // naya layer = naya average, backup dobara se
      e.tradesToday++;
      if(tag == "L1" || InpTgLayers)
         Tg(StringFormat("%s [%s] %s %s | lot %.2f @ %.2f", tag == "L1" ? "NEW BASKET" : "DCA " + tag, e.name,
                         dir == 1 ? "BUY" : "SELL", _Symbol, lot, trade.ResultPrice()));
      return true;
     }
   PrintFormat("[%s] Order fail: %d %s", e.name, trade.ResultRetcode(), trade.ResultRetcodeDescription());
   return false;
  }

//==================== S/R LEVELS ====================
bool AggMonths(datetime from, datetime to, double &o, double &h, double &l, double &c, datetime &t0)
  {
   MqlRates r[];
   int n = CopyRates(_Symbol, PERIOD_MN1, from, to, r);   // oldest first
   if(n <= 0) return false;
   o = r[0].open; c = r[n - 1].close; h = r[0].high; l = r[0].low; t0 = r[0].time;
   for(int i = 1; i < n; i++) { h = MathMax(h, r[i].high); l = MathMin(l, r[i].low); }
   return true;
  }

bool AggBars(ENUM_TIMEFRAMES tf, int start, int count, double &o, double &h, double &l, double &c, datetime &t0)
  {
   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(_Symbol, tf, start, count, r) != count) return false;
   o = r[count - 1].open; c = r[0].close; h = r[0].high; l = r[0].low; t0 = r[count - 1].time;
   for(int i = 1; i < count; i++) { h = MathMax(h, r[i].high); l = MathMin(l, r[i].low); }
   return true;
  }

datetime MonthStart(int year, int mon)
  {
   while(mon <= 0) { mon += 12; year--; }
   MqlDateTime d; ZeroMemory(d);
   d.year = year; d.mon = mon; d.day = 1;
   return StructToTime(d);
  }

void AddLevel(double price, int rank, string tag)
  {
   int n = ArraySize(levels);
   ArrayResize(levels, n + 1);
   levels[n].price = price; levels[n].rank = rank; levels[n].tag = tag;
  }

void DrawLine(string id, datetime t1, double price, color clr, int width, ENUM_LINE_STYLE style, string label, double zone, datetime t2)
  {
   string n = SRPFX + id;
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_TREND, 0, t1, price, t2, price);
   else { ObjectMove(0, n, 0, t1, price); ObjectMove(0, n, 1, t2, price); }
   ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, n, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, n, OBJPROP_STYLE, style);
   ObjectSetInteger(0, n, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_BACK, true);
   ObjectSetString(0, n, OBJPROP_TOOLTIP, label + " " + DoubleToString(price, _Digits));

   string t = n + "_T";
   if(ObjectFind(0, t) < 0) ObjectCreate(0, t, OBJ_TEXT, 0, t2, price);
   else ObjectMove(0, t, 0, t2, price);
   ObjectSetString(0, t, OBJPROP_TEXT, label + " " + DoubleToString(price, _Digits));
   ObjectSetInteger(0, t, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, t, OBJPROP_FONTSIZE, 7);
   ObjectSetInteger(0, t, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, t, OBJPROP_SELECTABLE, false);

   if(zone > 0)
     {
      string z = n + "_Z";
      if(ObjectFind(0, z) < 0) ObjectCreate(0, z, OBJ_RECTANGLE, 0, t1, price + zone, t2, price - zone);
      else { ObjectMove(0, z, 0, t1, price + zone); ObjectMove(0, z, 1, t2, price - zone); }
      ObjectSetInteger(0, z, OBJPROP_COLOR, InpZoneColor);
      ObjectSetInteger(0, z, OBJPROP_FILL, true);
      ObjectSetInteger(0, z, OBJPROP_BACK, true);
      ObjectSetInteger(0, z, OBJPROP_SELECTABLE, false);
     }
  }

void AddOHLC(string name, int rank, bool show, double o, double h, double l, double c, datetime t0,
             color clr, int width, ENUM_LINE_STYLE style, bool big, datetime t2)
  {
   AddLevel(o, rank, name + "-O"); AddLevel(h, rank, name + "-H");
   AddLevel(l, rank, name + "-L"); AddLevel(c, rank, name + "-C");
   if(!InpShowLevels || !show) return;
   double zone = big ? (InpDrawZones ? InpZoneHalf : 0) : (InpDrawSmallZones ? InpZoneHalfSmall : 0);
   DrawLine(name + "_O", t0, o, clr, width, style, name + " Open",  zone, t2);
   DrawLine(name + "_H", t0, h, clr, width, style, name + " High",  zone, t2);
   DrawLine(name + "_L", t0, l, clr, width, style, name + " Low",   zone, t2);
   DrawLine(name + "_C", t0, c, clr, width, style, name + " Close", zone, t2);
  }

void UpdateLevels(bool force)
  {
   datetime h4 = iTime(_Symbol, PERIOD_H4, 0);
   if(!force && h4 == lastLevelsBar) return;
   if(!force && TimeCurrent() - lastLevelsTry < 10) return;   // history load retry throttle
   lastLevelsTry = TimeCurrent();

   ArrayResize(levels, 0);
   ObjectsDeleteAll(0, SRPFX);
   datetime t2 = TimeCurrent() + PeriodSeconds(PERIOD_H4) * 6;
   MqlDateTime now; TimeToStruct(TimeCurrent(), now);
   double o, h, l, c; datetime t0;
   bool ok = true;

   // Previous Year
   if(AggMonths(MonthStart(now.year - 1, 1), MonthStart(now.year - 1, 12), o, h, l, c, t0))
      AddOHLC("Y", 7, InpShowY, o, h, l, c, t0, clrRed, 3, STYLE_SOLID, true, t2);
   else ok = false;

   // Previous Half-year (Jan-Jun / Jul-Dec)
   int hs = (now.mon <= 6) ? 7 : 1;  int hy = (now.mon <= 6) ? now.year - 1 : now.year;
   if(AggMonths(MonthStart(hy, hs), MonthStart(hy, hs + 5), o, h, l, c, t0))
      AddOHLC("6M", 6, InpShow6M, o, h, l, c, t0, clrOrangeRed, 3, STYLE_SOLID, true, t2);
   else ok = false;

   // Previous Quarter
   int qStart = ((now.mon - 1) / 3) * 3 + 1 - 3;   // pichle quarter ka pehla month
   datetime qs = MonthStart(now.year, qStart);
   MqlDateTime qd; TimeToStruct(qs, qd);
   if(AggMonths(qs, MonthStart(qd.year, qd.mon + 2), o, h, l, c, t0))
      AddOHLC("3M", 5, InpShow3M, o, h, l, c, t0, clrOrange, 2, STYLE_SOLID, true, t2);
   else ok = false;

   if(AggBars(PERIOD_MN1, 1, 1, o, h, l, c, t0))
      AddOHLC("1M", 4, InpShow1M, o, h, l, c, t0, clrGold, 2, STYLE_SOLID, true, t2);
   else ok = false;

   if(AggBars(PERIOD_W1, 1, 1, o, h, l, c, t0))
      AddOHLC("W", 3, InpShowW, o, h, l, c, t0, clrDodgerBlue, 2, STYLE_SOLID, true, t2);
   else ok = false;

   if(AggBars(PERIOD_D1, 1, 3, o, h, l, c, t0))
      AddOHLC("3D", 2, InpShow3D, o, h, l, c, t0, clrMediumPurple, 1, STYLE_DASH, false, t2);
   else ok = false;

   if(AggBars(PERIOD_D1, 1, 1, o, h, l, c, t0))
      AddOHLC("D", 1, InpShowD, o, h, l, c, t0, clrSilver, 1, STYLE_DASH, false, t2);
   else ok = false;

   for(int i = 1; i <= InpH4Count; i++)
     {
      if(AggBars(PERIOD_H4, i, 1, o, h, l, c, t0))
         AddOHLC("H4#" + IntegerToString(i), 0, InpShowH4, o, h, l, c, t0, clrGray, 1, STYLE_DOT, false, t2);
      else ok = false;
     }

   if(ok) lastLevelsBar = h4;   // history poori nahi aayi to agle tick par phir try
   ChartRedraw();
  }

// BUY ke upar paas me resistance / SELL ke neeche paas me support ho to block
bool SRBlocked(int dir)
  {
   double price = dir == 1 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   for(int i = 0; i < ArraySize(levels); i++)
     {
      if(levels[i].rank < InpSRMinRank) continue;
      double d = levels[i].price - price;
      if(dir == 1 && d > 0 && d <= InpSRBlockDist)
        { PrintFormat("BUY skip: resistance %s %.2f paas me", levels[i].tag, levels[i].price); return true; }
      if(dir == -1 && d < 0 && -d <= InpSRBlockDist)
        { PrintFormat("SELL skip: support %s %.2f paas me", levels[i].tag, levels[i].price); return true; }
     }
   return false;
  }

//==================== NEWS ====================
void UpdateNews()
  {
   if(!InpUseNews || MQLInfoInteger(MQL_TESTER)) { newsActive = false; newsSoon = false; return; }
   if(TimeCurrent() - lastNewsCheck < 60) return;
   lastNewsCheck = TimeCurrent();
   newsActive = false; newsSoon = false;

   datetime now = TimeTradeServer();
   MqlCalendarValue vals[];
   if(CalendarValueHistory(vals, now - InpNewsAfterMin * 60, now + InpNewsBeforeMin * 60, NULL, "USD") <= 0)
      return;
   for(int i = 0; i < ArraySize(vals); i++)
     {
      MqlCalendarEvent ev;
      if(!CalendarEventById(vals[i].event_id, ev)) continue;
      if(ev.importance != CALENDAR_IMPORTANCE_HIGH) continue;
      newsActive = true;
      if(vals[i].time >= now) newsSoon = true;
     }
  }

//==================== PANEL ====================
string EngineLine(Engine &e)
  {
   if(!e.on && CountLayers(e) == 0) return e.name + "   : OFF";
   int d, layers; double avg, lots, lp, pr;
   GetBasket(e, d, layers, avg, lots, lp, pr);
   int tr = TrendDir(e.hTF, e.hTS, e.trendTF);
   return StringFormat("%-8s: trend %s | %s %d/%s lots %.2f avg %.2f P/L %.2f | TP %.2f SL %.2f%s | today %d baskets%s",
                       e.name, tr == 1 ? "UP" : (tr == -1 ? "DOWN" : "SIDE"),
                       d == 1 ? "BUY" : (d == -1 ? "SELL" : "-"), layers, MaxStr(e.maxLayers), lots, avg, pr,
                       e.syncedTP, e.syncedSL, e.trailActive ? " TRAILING" : "", e.basketsToday,
                       e.manual ? " | manual ON" : "");
  }

void ShowTextPanel()
  {
   int mt = MasterTrend();
   string status = dayStopped ? "STOPPED (daily loss / cutloss)" :
                   (TimeCurrent() < cutlossUntil ? "CUTLOSS cooldown till " + TimeToString(cutlossUntil, TIME_MINUTES) :
                   (InpDailyTargetPct > 0 && DayPLPct() >= InpDailyTargetPct ? "Daily target hit" : "Running"));
   string scanLine = "Scanner   : OFF";
   if(InpUseScanner)
     {
      int sd = (mt != 0) ? mt : 1;
      if(sd != lastScanDir || TimeCurrent() - lastScanTime >= 5)
        { ScanMarket(sd, lastScan); lastScanDir = sd; lastScanTime = TimeCurrent(); }
      scanLine = StringFormat("Scanner   : %s score %d/100 = %s (entry %d+)  %s",
                              sd == 1 ? "BUY" : "SELL", lastScan.total, Tier(lastScan.total), InpMinScore, ScoreText(lastScan));
     }
   Comment(StringFormat(
      "GoldDCA_EA v3.82 | %s\n"
      "Status    : %s\n"
      "Master %s : %s\n"
      "News      : %s\n"
      "%s\n"
      "%s\n%s\n%s\n"
      "Today P/L : %.2f%%  (target %.1f%%, max loss %.1f%%)  trades %d",
      _Symbol, status, EnumToString(InpMasterTF),
      mt == 1 ? "UP - sirf BUY" : (mt == -1 ? "DOWN - sirf SELL" : "SIDEWAYS - no entry"),
      newsActive ? "HIGH IMPACT - paused" : "Clear",
      scanLine,
      EngineLine(E[0]) + "\n" + EngineLine(E[3]), EngineLine(E[1]) + "\n" + EngineLine(E[4]), EngineLine(E[2]) + "\n" + EngineLine(E[5]),
      DayPLPct(), InpDailyTargetPct, DayLossPct(), TradesToday()));
  }
//+------------------------------------------------------------------+

//==================== GRAPHIC SIGNAL PANEL ====================
color    cBg = C'18,20,32', cCard = C'28,31,48', cLine = C'48,52,78', cTxt = C'225,228,240', cDim = C'140,146,175';
color    cBuy = C'38,196,133', cSell = C'239,83,80', cWarn = C'255,183,77', cAcc = C'124,108,255';
datetime lastPanel = 0, lastAlertTime = 0;
int      lastAlertDir = 0;
bool     prevHigh = false;

void PRect(string id, int x, int y, int w, int h, color bg, color border)
  {
   string n = PFX + id;
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, n, OBJPROP_BACK, false);
     }
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, InpPanelX + x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, InpPanelY + y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, MathMax(w, 1));
   ObjectSetInteger(0, n, OBJPROP_YSIZE, MathMax(h, 1));
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, n, OBJPROP_COLOR, border);
  }

void PText(string id, int x, int y, string txt, color c, int size = 9, bool bold = false, ENUM_ANCHOR_POINT anc = ANCHOR_LEFT_UPPER)
  {
   string n = PFX + id;
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
     }
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, InpPanelX + x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, InpPanelY + y);
   ObjectSetInteger(0, n, OBJPROP_ANCHOR, anc);
   ObjectSetString(0, n, OBJPROP_TEXT, txt);
   ObjectSetString(0, n, OBJPROP_FONT, bold ? "Segoe UI Semibold" : "Segoe UI");
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
  }

void PBar(string id, int x, int y, int w, int h, double frac, color fg)
  {
   frac = MathMax(0.0, MathMin(1.0, frac));
   PRect(id + "_bg", x, y, w, h, cLine, cLine);
   PRect(id + "_fg", x, y, (int)MathRound(w * frac), h, fg, fg);
  }

string SessionNow(int &nextHourGMT)
  {
   MqlDateTime g;
   TimeToStruct(TimeCurrent() - InpServerGMTOffset * 3600, g);
   int h = g.hour;
   bool asia = (h >= 0 && h < 9), lon = (h >= 7 && h < 16), ny = (h >= 12 && h < 21);
   int opens[3] = {0, 7, 12};
   nextHourGMT = 0;
   for(int i = 0; i < 3; i++) if(opens[i] > h) { nextHourGMT = opens[i]; break; }
   if(lon && ny) return "LONDON + NEW YORK";
   if(lon && asia) return "ASIA + LONDON";
   if(lon) return "LONDON";
   if(ny) return "NEW YORK";
   if(asia) return "ASIA";
   return "OFF-HOURS";
  }

string ISTTime(int gmtHour)
  {
   int mins = gmtHour * 60 + 330;          // IST = GMT + 5:30
   mins %= 1440;
   return StringFormat("%02d:%02d IST", mins / 60, mins % 60);
  }

int TradesToday()
  {
   int n = 0;
   for(int k = 0; k < NE; k++) n += E[k].tradesToday;
   return n;
  }

double DayLossPct() { return rtDayLoss >= 0 ? rtDayLoss : InpDailyLossPct; }

string MaxStr(int m) { return m > 0 ? IntegerToString(m) : "unlimited"; }
int DcaShow() { return InpInMaxLayers > 0 ? (int)MathMin(4, InpInMaxLayers - 1) : 4; }

string EngineState(Engine &e, int layers)
  {
   if(!e.on && layers == 0) return "OFF";
   if(layers == 0)
     {
      if(dayStopped) return "STOPPED";
      if(TimeCurrent() < cutlossUntil) return "COOLDOWN";
      if(InpUseNews && (newsActive || newsSoon)) return "NEWS PAUSE";
      return "SCANNING";
     }
   if(e.trailActive) return e.booked ? "BOOKED + TRAIL" : "TRAILING";
   if(e.dcaPaused) return "DCA PAUSED (reversal)";
   if(e.maxLayers > 0 && layers >= e.maxLayers) return "MAX LAYERS";
   return "DCA ACTIVE";
  }

void ShowPanel()
  {
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return;
   if(!InpGraphicPanel) { ShowTextPanel(); return; }
   if(TimeLocal() == lastPanel) return;      // max 1 update / second
   lastPanel = TimeLocal();

   int W = 360, x0 = 0, y = 0;
   double bal = AccountInfoDouble(ACCOUNT_BALANCE), eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double margin = AccountInfoDouble(ACCOUNT_MARGIN);
   double mlvl = margin > 0 ? eq / margin * 100.0 : 0;
   static double peakEq = 0;
   if(eq > peakEq) peakEq = eq;
   double dd = peakEq > 0 ? (peakEq - eq) / peakEq * 100.0 : 0;

   int mt = MasterTrend();
   int sd = (mt != 0) ? mt : 1;
   if(InpUseScanner && (sd != lastScanDir || TimeCurrent() - lastScanTime >= 5))
     { ScanMarket(sd, lastScan); lastScanDir = sd; lastScanTime = TimeCurrent(); }
   int score = InpUseScanner ? lastScan.total : 0;
   bool isHigh = (mt != 0 && score >= InpMinScore);

   // ---- background
   PRect("bg", x0, 0, W, 520, cBg, cLine);

   // ---- header
   string status = dayStopped ? "STOPPED" : (TimeCurrent() < cutlossUntil ? "COOLDOWN" :
                   (InpDailyTargetPct > 0 && DayPLPct() >= InpDailyTargetPct ? "TARGET HIT" : "RUNNING"));
   color stC = status == "RUNNING" ? cBuy : (status == "TARGET HIT" ? cAcc : cWarn);
   PText("title", 12, 8, "GOLD DCA  SIGNAL PANEL", cTxt, 11, true);
   PText("ver", 12, 27, _Symbol + "  |  v3.82  |  " + TimeToString(TimeCurrent(), TIME_MINUTES) + " server", cDim, 8);
   PRect("badge", W - 96, 10, 84, 20, stC, stC);
   PText("badgeT", W - 54, 13, status, cBg, 8, true, ANCHOR_UPPER);
   y = 48;

   // ---- account tiles
   string tl[4] = {"BALANCE", "EQUITY", "FLOATING", "MARGIN LVL"};
   double fl = eq - bal;
   string tv[4];
   tv[0] = DoubleToString(bal, 2); tv[1] = DoubleToString(eq, 2);
   tv[2] = (fl >= 0 ? "+" : "") + DoubleToString(fl, 2);
   tv[3] = margin > 0 ? DoubleToString(mlvl, 0) + "%" : "-";
   for(int i = 0; i < 4; i++)
     {
      int tx = 8 + i * 87;
      PRect("tile" + IntegerToString(i), tx, y, 82, 40, cCard, cLine);
      PText("tileL" + IntegerToString(i), tx + 6, y + 4, tl[i], cDim, 7);
      color vc = (i == 2) ? (fl >= 0 ? cBuy : cSell) : (i == 3 && margin > 0 && mlvl < 200 ? cWarn : cTxt);
      PText("tileV" + IntegerToString(i), tx + 6, y + 18, tv[i], vc, 10, true);
     }
   y += 46;
   PText("ddL", 10, y, StringFormat("Drawdown %.1f%%", dd), dd > 18 ? cSell : cDim, 8);
   PBar("dd", 110, y + 4, W - 120, 6, dd / 25.0, dd > 18 ? cSell : (dd > 10 ? cWarn : cBuy));
   y += 20;

   // ---- signal card
   PRect("sig", 8, y, W - 16, 150, cCard, isHigh ? (sd == 1 ? cBuy : cSell) : cLine);
   string dirTxt = (mt == 0) ? "WAIT" : (sd == 1 ? "BUY" : "SELL");
   color dirC = (mt == 0) ? cDim : (sd == 1 ? cBuy : cSell);
   PText("sigDir", 18, y + 8, dirTxt, dirC, 22, true);
   string tier = (mt == 0) ? "SIDEWAYS - no entry" : Tier(score) + (isHigh ? "  |  HIGH PROBABILITY" : "  |  wait for " + IntegerToString(InpMinScore) + "+");
   PText("sigTier", 18, y + 46, tier, isHigh ? dirC : cWarn, 8, true);
   PText("sigScore", W - 24, y + 6, IntegerToString(score), isHigh ? dirC : cTxt, 24, true, ANCHOR_RIGHT_UPPER);
   PText("sigScoreL", W - 24, y + 44, "/100 SCORE", cDim, 7, false, ANCHOR_RIGHT_UPPER);
   PBar("sigBar", 18, y + 62, W - 52, 6, score / 100.0, score >= InpMinScore ? dirC : (score >= InpMedScore ? cWarn : cSell));

   // trade plan (intraday basket logic)
   double px = sd == 1 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double atr = B1(hScATR, 0, 1);
   if(atr == EMPTY_VALUE) atr = 0;
   double tp1d = MathMax(atr * InpInTP_ATR, InpInTPMin);
   double tp1 = px + sd * tp1d, tp2 = px + sd * 2.0 * MathMax(atr, tp1d);
   if(InpFxExit) { tp1 = px + sd * InpFxTrigger; tp2 = px + sd * InpFxTP; }
   int ty = y + 76;
   PText("pE", 18, ty, "ENTRY", cDim, 7);       PText("pEv", 18, ty + 12, DoubleToString(px, _Digits), cTxt, 9, true);
   PText("pT1", 105, ty, InpFxExit ? StringFormat("+$%.0f: lock +$%.0f, trail", InpFxTrigger, InpFxLock) : "TP1 (" + DoubleToString(InpBookPct, 0) + "% book)", cDim, 7);
   PText("pT1v", 105, ty + 12, DoubleToString(tp1, _Digits), cBuy, 9, true);
   PText("pT2", 225, ty, InpFxExit ? StringFormat("TP +$%.0f (close)", InpFxTP) : "TP2 (trailing)", cDim, 7); PText("pT2v", 225, ty + 12, DoubleToString(tp2, _Digits), cBuy, 9, true);
   string dca = "DCA every $" + DoubleToString(E[1].step, 0) + ": ";
   for(int i = 1; i <= DcaShow(); i++)
      dca += DoubleToString(px - sd * E[1].step * i, 1) + (i < DcaShow() ? " | " : "");
   PText("pDca", 18, ty + 32, dca, cWarn, 8);
   PText("pSL", 18, ty + 48, StringFormat("Hard stop: basket loss %.0f%% equity%s", InpInStopPct,
                                           InpCutlossUSD > 0 ? StringFormat(" / $%.0f cutloss", InpCutlossUSD) : ""), cSell, 8);
   y += 158;

   // ---- score breakdown
   string nm[7] = {"Trend MTF", "Momentum", "Volatility", "Session", "Liquidity", "Order flow", "Dollar/Silver"};
   int    vv[7], mx[7] = {25, 15, 10, 10, 15, 15, 10};
   vv[0] = lastScan.mtf; vv[1] = lastScan.mom; vv[2] = lastScan.vol; vv[3] = lastScan.ses;
   vv[4] = lastScan.liq; vv[5] = lastScan.flow; vv[6] = lastScan.cross;
   PText("brkT", 10, y, "SCORE BREAKDOWN", cDim, 7, true);
   y += 14;
   for(int i = 0; i < 7; i++)
     {
      double f = InpUseScanner ? (double)vv[i] / mx[i] : 0;
      PText("bn" + IntegerToString(i), 12, y, nm[i], cTxt, 8);
      PBar("bb" + IntegerToString(i), 105, y + 4, 190, 6, f, f >= 0.66 ? cBuy : (f >= 0.33 ? cWarn : cSell));
      PText("bv" + IntegerToString(i), W - 14, y, InpUseScanner ? StringFormat("%d/%d", vv[i], mx[i]) : "-", cDim, 8, false, ANCHOR_RIGHT_UPPER);
      y += 15;
     }
   y += 4;

   // ---- session / news
   int nextH;
   string ses = SessionNow(nextH);
   PRect("ses", 8, y, W - 16, 22, cCard, cLine);
   PText("sesT", 16, y + 4, "Session: " + ses + "   |   next open " + ISTTime(nextH), cTxt, 8);
   PText("news", W - 16, y + 4, newsActive ? "NEWS!" : "News clear", newsActive ? cSell : cBuy, 8, true, ANCHOR_RIGHT_UPPER);
   y += 28;
   {
      int nb; double net, lots; NetPL(nb, net, lots);
      double need = MathMax(InpNetCloseUSD, InpNetClosePerLot * lots);
      PText("netT", 10, y, nb > 0 ? StringFormat("NET (%d baskets, %.2f lot): %+.2f  |  sab close at +%.2f%s", nb, lots, net, need,
            (InpNetClose && nb >= 2) ? "" : " (2+ baskets par)") : "NET: no open baskets", net >= 0 ? cBuy : cSell, 8, true);
      y += 18;
   }
   PRect("inst", 8, y, W - 16, 38, cCard, cLine);
   string stTxt = stBias == 1 ? "BULLISH" : (stBias == -1 ? "BEARISH" : "-");
   PText("instS", 16, y + 3, "Structure: " + stTxt + (stType != "" ? " (" + stType + ")" : ""), stBias == 1 ? cBuy : (stBias == -1 ? cSell : cDim), 8, true);
   string swTxt = swDir == 0 ? "Sweep: none" : StringFormat("Sweep: %s @ %.2f", swDir == 1 ? "sell-side (BUY)" : "buy-side (SELL)", swLevel);
   PText("instW", W - 16, y + 3, swTxt, swDir == 1 ? cBuy : (swDir == -1 ? cSell : cDim), 8, false, ANCHOR_RIGHT_UPPER);
   double bidNow = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   string vTxt = vwap > 0 ? StringFormat("VWAP %.2f  (%s)  | band +/-%.2f", vwap, bidNow >= vwap ? "price ABOVE -> BUY side" : "price BELOW -> SELL side", vwapSD * InpVWAPBandSD) : "VWAP: -";
   PText("instV", 16, y + 20, vTxt, vwap > 0 ? (bidNow >= vwap ? cBuy : cSell) : cDim, 8);
   y += 44;

   // ---- engines
   PText("engT", 10, y, InpHedgeMode ? "ENGINES  (HEDGE: BUY + SELL alag basket)" : "ENGINES", cDim, 7, true);
   y += 14;
   int nShow = InpHedgeMode ? NE : NT;
   for(int r = 0; r < nShow; r++)
     {
      int k = InpHedgeMode ? ((r % 2 == 0) ? r / 2 : r / 2 + NT) : r;     // SCALP-B, SCALP-S, INTRA-B, ...
      int d, layers; double avg, lots, lp, pr;
      GetBasket(E[k], d, layers, avg, lots, lp, pr);
      string st = EngineState(E[k], layers);
      string ks = IntegerToString(r);
      PRect("eng" + ks, 8, y, W - 16, 32, cCard, cLine);
      color nc = E[k].side == 1 ? cBuy : (E[k].side == -1 ? cSell : cTxt);
      PText("engN" + ks, 16, y + 2, E[k].name, nc, 8, true);
      color stc = (st == "SCANNING" || st == "DCA ACTIVE") ? cAcc : (StringFind(st, "TRAIL") >= 0 ? cBuy : (st == "OFF" ? cDim : cWarn));
      PText("engS" + ks, W - 16, y + 2, st, stc, 8, true, ANCHOR_RIGHT_UPPER);
      string info = layers > 0 ?
                    StringFormat("%dL %.2flot avg %.2f %+.2f | DCA@%.2f %s", layers, lots, avg, pr,
                                 E[k].dcaNext, E[k].dcaWhy == "" ? "ready" : E[k].dcaWhy) :
                    StringFormat("DCA $%.0f | max %s layers | %d baskets today", E[k].step, MaxStr(E[k].maxLayers), E[k].basketsToday);
      PText("engI" + ks, 16, y + 16, info, layers > 0 ? (pr >= 0 ? cBuy : cSell) : cDim, 8);
      y += 35;
     }

   // ---- today
   int trades = TradesToday();
   double dpl = DayPLPct();
   PText("today", 10, y + 2, StringFormat("Today: %+.2f%%  (target %.0f%% | max loss %.0f%%)  |  %d trades", dpl, InpDailyTargetPct, DayLossPct(), trades),
         dpl >= 0 ? cBuy : cSell, 8, true);
   y += 22;

   // ---- control buttons
   PText("ctlT", 10, y, "CONTROLS", cDim, 7, true);
   y += 14;
   int bw = (W - 16 - 8) / 3;
   string tn[NT] = {"SCALP", "INTRADAY", "TICK-M1"};
   for(int k = 0; k < NT; k++)
      PButton("btn_eng" + IntegerToString(k), 8 + k * (bw + 4), y, bw, 22,
              tn[k] + (E[k].on ? "  ON" : "  OFF"), E[k].on ? cBuy : cLine, E[k].on ? cBg : cTxt);
   y += 26;
   string sideTxt = rtSide == 0 ? "BUY + SELL" : (rtSide == 1 ? "BUY ONLY" : "SELL ONLY");
   PButton("btn_side", 8, y, bw * 2 + 4, 22, "Direction: " + sideTxt, rtSide == 0 ? cAcc : (rtSide == 1 ? cBuy : cSell), cBg);
   PButton("btn_pause", 8 + 2 * (bw + 4), y, bw, 22, rtPaused ? "RESUME" : "PAUSE", rtPaused ? cWarn : cLine, rtPaused ? cBg : cTxt);
   y += 26;
   int sw = 26;
   PButton("btn_dcam", 8, y, sw, 22, "-", cLine, cTxt);
   PText("dcaV", 8 + sw + 4, y + 4, "DCA $" + DoubleToString(E[1].step, 0), cTxt, 8, true);
   PButton("btn_dcap", 8 + sw + 70, y, sw, 22, "+", cLine, cTxt);
   int lx = W / 2 + 4;
   PButton("btn_lotm", lx, y, sw, 22, "-", cLine, cTxt);
   PText("lotV", lx + sw + 4, y + 4, StringFormat("Lot %.1fx (%.2f)", rtLotMult, LayerLot(E[1], 0)), cTxt, 8, true);
   PButton("btn_lotp", W - 8 - sw, y, sw, 22, "+", cLine, cTxt);
   y += 26;
   PButton("btn_slm", 8, y, sw, 22, "-", cLine, cTxt);
   PText("slV", 8 + sw + 4, y + 4, StringFormat("Hard SL %.0f%%", E[1].stopPct), E[1].stopPct > 30 ? cWarn : cTxt, 8, true);
   PButton("btn_slp", 8 + sw + 92, y, sw, 22, "+", cLine, cTxt);
   PButton("btn_dlm", lx, y, sw, 22, "-", cLine, cTxt);
   PText("dlV", lx + sw + 4, y + 4, StringFormat("Day loss %.0f%%", DayLossPct()), DayLossPct() > 30 ? cWarn : cTxt, 8, true);
   PButton("btn_dlp", W - 8 - sw, y, sw, 22, "+", cLine, cTxt);
   y += 26;
   PButton("btn_close", 8, y, W - 16, 24, "CLOSE ALL EA TRADES", cSell, clrWhite);
   y += 30;
   ObjectSetInteger(0, PFX + "bg", OBJPROP_YSIZE, y);

   // ---- alerts on fresh HIGH signal
   if(isHigh && (!prevHigh || sd != lastAlertDir) && TimeCurrent() - lastAlertTime >= InpAlertGapMin * 60)
     {
      string msg = StringFormat("%s %s %s %d/100 | Entry %s TP1 %s TP2 %s | DCA $%.0f", _Symbol, sd == 1 ? "BUY" : "SELL", Tier(score), score,
                                DoubleToString(px, _Digits), DoubleToString(tp1, _Digits), DoubleToString(tp2, _Digits), E[1].step);
      if(InpAlertPopup) Alert(msg);
      if(InpAlertPush) SendNotification(msg);
      lastAlertTime = TimeCurrent(); lastAlertDir = sd;
     }
   prevHigh = isHigh;
   ChartRedraw();
  }
//+------------------------------------------------------------------+

//==================== CHART BUTTONS ====================
void PButton(string id, int x, int y, int w, int h, string txt, color bg, color fg)
  {
   string n = PFX + id;
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
   ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, cLine);
   ObjectSetInteger(0, n, OBJPROP_STATE, false);
  }

// Settings restart ke baad bhi yaad rahein (terminal global variables)
void SaveControls()
  {
   GlobalVariableSet(gvCtl + "paused", rtPaused ? 1 : 0);
   GlobalVariableSet(gvCtl + "side", rtSide);
   GlobalVariableSet(gvCtl + "lot", rtLotMult);
   GlobalVariableSet(gvCtl + "step", E[1].step);
   GlobalVariableSet(gvCtl + "sl", E[1].stopPct);
   GlobalVariableSet(gvCtl + "dayloss", DayLossPct());
   for(int k = 0; k < NE; k++) GlobalVariableSet(gvCtl + "on" + IntegerToString(k), E[k].on ? 1 : 0);
  }

void LoadControls()
  {
   gvCtl = "GDCA_" + _Symbol + "_" + IntegerToString(InpMagic) + "_";
   if(MQLInfoInteger(MQL_TESTER) || !GlobalVariableCheck(gvCtl + "side")) return;
   rtPaused  = GlobalVariableGet(gvCtl + "paused") > 0.5;
   rtSide    = (int)GlobalVariableGet(gvCtl + "side");
   rtLotMult = MathMax(0.5, GlobalVariableGet(gvCtl + "lot"));
   double st = GlobalVariableGet(gvCtl + "step");
   if(st >= 1) for(int k = 0; k < NE; k++) E[k].step = st;
   if(GlobalVariableCheck(gvCtl + "sl"))
     {
      double sl = GlobalVariableGet(gvCtl + "sl");
      if(sl >= 5) for(int k = 0; k < NE; k++) E[k].stopPct = sl;
     }
   if(GlobalVariableCheck(gvCtl + "dayloss")) rtDayLoss = GlobalVariableGet(gvCtl + "dayloss");
   for(int k = 0; k < NE; k++)
      if(GlobalVariableCheck(gvCtl + "on" + IntegerToString(k)))
         E[k].on = GlobalVariableGet(gvCtl + "on" + IntegerToString(k)) > 0.5;
   if(!InpHedgeMode) for(int k = NT; k < NE; k++) E[k].on = false;
   PrintFormat("Saved controls loaded: paused=%s side=%d lot=%.1fx step=$%.0f", rtPaused ? "yes" : "no", rtSide, rtLotMult, E[1].step);
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_OBJECT_CLICK || StringFind(sparam, PFX + "btn_") != 0) return;
   string b = StringSubstr(sparam, StringLen(PFX + "btn_"));
   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);

   if(StringFind(b, "eng") == 0)
     {
      int k = (int)StringToInteger(StringSubstr(b, 3));
      if(k >= 0 && k < NT)
        {
         E[k].on = !E[k].on;
         if(InpHedgeMode) E[k + NT].on = E[k].on;
         PrintFormat("[%s] %s (button)", E[k].name, E[k].on ? "ON" : "OFF");
        }
     }
   else if(b == "side")  { rtSide = (rtSide == 0) ? 1 : (rtSide == 1 ? -1 : 0); }
   else if(b == "pause") { rtPaused = !rtPaused; Print(rtPaused ? "EA PAUSED - naye trade/DCA band, exits chalte rahenge" : "EA RESUMED"); }
   else if(b == "dcam" || b == "dcap")
     {
      double st = MathMax(1.0, E[1].step + (b == "dcap" ? 1.0 : -1.0));
      for(int k = 0; k < NE; k++) E[k].step = st;
      PrintFormat("DCA step ab $%.0f (sab engines)", st);
     }
   else if(b == "lotm" || b == "lotp")
     {
      rtLotMult = MathMax(0.5, MathMin(10.0, rtLotMult + (b == "lotp" ? 0.5 : -0.5)));
      PrintFormat("Lot multiplier ab %.1fx", rtLotMult);
     }
   else if(b == "slm" || b == "slp")
     {
      double v = MathMax(5.0, MathMin(95.0, E[1].stopPct + (b == "slp" ? 5.0 : -5.0)));
      for(int k = 0; k < NE; k++) E[k].stopPct = v;
      PrintFormat("Hard stop ab %.0f%% equity (sab engines)", v);
     }
   else if(b == "dlm" || b == "dlp")
     {
      rtDayLoss = MathMax(5.0, MathMin(95.0, DayLossPct() + (b == "dlp" ? 5.0 : -5.0)));
      PrintFormat("Daily loss limit ab %.0f%%", rtDayLoss);
     }
   else if(b == "close")
     {
      int r = MessageBox("Saare EA trades abhi close karein?", "GoldDCA - Close All", MB_YESNO | MB_ICONWARNING);
      if(r == IDYES) { CloseAllEngines(); Print("CLOSE ALL (button)"); }
     }
   SaveControls();
   lastPanel = 0;
   ShowPanel();
  }

//==================== INSTITUTIONAL: STRUCTURE / SWEEP / VWAP ====================
// Market structure (fractal swings) + BOS/CHoCH + liquidity sweep, har naye StructTF candle par
void UpdateStructure()
  {
   datetime bar = iTime(_Symbol, InpStructTF, 0);
   if(bar == 0 || bar == stLastBar) return;
   MqlRates r[];
   ArraySetAsSeries(r, false);                       // oldest first
   int n = CopyRates(_Symbol, InpStructTF, 1, InpStructLookback, r);
   int L = MathMax(1, InpSwingLen);
   if(n < 2 * L + 5) return;
   stLastBar = bar;

   double lastH = 0, lastL = 0, refH = 0, refL = 0;
   int bias = 0; string typ = "";
   double brk = 0; datetime brkT = 0;
   int sd = 0; double slv = 0; datetime st = 0;
   double pdh = iHigh(_Symbol, PERIOD_D1, 1), pdl = iLow(_Symbol, PERIOD_D1, 1);

   for(int i = L; i < n; i++)
     {
      // swing confirm at j (needs L bars on both sides)
      int j = i - L;
      if(j >= L)
        {
         bool isH = true, isL = true;
         for(int k = 1; k <= L; k++)
           {
            if(r[j].high <= r[j - k].high || r[j].high < r[j + k].high) isH = false;
            if(r[j].low >= r[j - k].low || r[j].low > r[j + k].low) isL = false;
           }
         if(isH) { lastH = r[j].high; refH = r[j].high; }
         if(isL) { lastL = r[j].low;  refL = r[j].low; }
        }
      // BOS / CHoCH on candle close
      if(lastH > 0 && r[i].close > lastH)
        { typ = (bias == -1) ? "CHoCH" : "BOS"; bias = 1; brk = lastH; brkT = r[i].time; lastH = 0; }
      else if(lastL > 0 && r[i].close < lastL)
        { typ = (bias == 1) ? "CHoCH" : "BOS"; bias = -1; brk = lastL; brkT = r[i].time; lastL = 0; }

      // Liquidity sweep in recent candles: wick beyond swing / PDH-PDL, close back inside
      if(i >= n - InpSweepBars)
        {
         double lvls[2]; lvls[0] = refL; lvls[1] = pdl;
         for(int q = 0; q < 2; q++)
            if(lvls[q] > 0 && r[i].low < lvls[q] && r[i].close > lvls[q]) { sd = 1; slv = lvls[q]; st = r[i].time; }
         double lvlh[2]; lvlh[0] = refH; lvlh[1] = pdh;
         for(int q = 0; q < 2; q++)
            if(lvlh[q] > 0 && r[i].high > lvlh[q] && r[i].close < lvlh[q]) { sd = -1; slv = lvlh[q]; st = r[i].time; }
        }
     }
   if(bias != stBias || typ != stType)
      PrintFormat("Structure: %s %s @ %.2f", bias == 1 ? "BULLISH" : (bias == -1 ? "BEARISH" : "-"), typ, brk);
   stBias = bias; stType = typ; stBreakLvl = brk; stBreakTime = brkT;
   stSwingH = refH; stSwingL = refL;
   swDir = sd; swLevel = slv; swTime = st;
   DrawInst();
  }

// Session VWAP (aaj ke din ka, M1 tick volume se) + standard deviation band
void UpdateVWAP()
  {
   datetime bar = iTime(_Symbol, PERIOD_M1, 0);
   if(bar == 0 || bar == vwapBar) return;
   vwapBar = bar;
   datetime dayStart = iTime(_Symbol, PERIOD_D1, 0);
   MqlRates r[];
   int n = CopyRates(_Symbol, PERIOD_M1, dayStart, TimeCurrent(), r);
   if(n <= 0) return;
   double sv = 0, spv = 0, sp2v = 0;
   for(int i = 0; i < n; i++)
     {
      double tp = (r[i].high + r[i].low + r[i].close) / 3.0;
      double v = (double)MathMax((long)1, r[i].tick_volume);
      sv += v; spv += tp * v; sp2v += tp * tp * v;
     }
   if(sv <= 0) return;
   vwap = spv / sv;
   double vr = sp2v / sv - vwap * vwap;
   vwapSD = vr > 0 ? MathSqrt(vr) : 0;
   DrawInst();
  }

// Entry filter: structure + sweep + VWAP
bool InstOK(int sig)
  {
   if(InpUseStructure && stBias != sig) return false;
   if(InpRequireSweep && swDir != sig) return false;
   if(InpUseVWAP && vwap > 0)
     {
      double px = sig == 1 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(sig == 1 && px < vwap) return false;
      if(sig == -1 && px > vwap) return false;
     }
   return true;
  }

void IHLine(string id, double price, color c, ENUM_LINE_STYLE st, int w, string label)
  {
   string n = IPFX + id;
   if(price <= 0) { ObjectDelete(0, n); ObjectDelete(0, n + "_T"); return; }
   datetime t1 = iTime(_Symbol, PERIOD_D1, 0), t2 = TimeCurrent() + PeriodSeconds(PERIOD_H1) * 3;
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_TREND, 0, t1, price, t2, price);
   else { ObjectMove(0, n, 0, t1, price); ObjectMove(0, n, 1, t2, price); }
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetInteger(0, n, OBJPROP_STYLE, st);
   ObjectSetInteger(0, n, OBJPROP_WIDTH, w);
   ObjectSetInteger(0, n, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_BACK, true);
   string t = n + "_T";
   if(ObjectFind(0, t) < 0) ObjectCreate(0, t, OBJ_TEXT, 0, t2, price);
   else ObjectMove(0, t, 0, t2, price);
   ObjectSetString(0, t, OBJPROP_TEXT, label + " " + DoubleToString(price, _Digits));
   ObjectSetInteger(0, t, OBJPROP_COLOR, c);
   ObjectSetInteger(0, t, OBJPROP_FONTSIZE, 7);
   ObjectSetInteger(0, t, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, t, OBJPROP_SELECTABLE, false);
  }

void DrawInst()
  {
   if(!InpDrawInst || (MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE))) return;
   double b = vwapSD * InpVWAPBandSD;
   IHLine("vwap", vwap, clrDeepSkyBlue, STYLE_SOLID, 2, "VWAP");
   IHLine("vwapU", vwap > 0 && b > 0 ? vwap + b : 0, clrDeepSkyBlue, STYLE_DOT, 1, "VWAP +band");
   IHLine("vwapD", vwap > 0 && b > 0 ? vwap - b : 0, clrDeepSkyBlue, STYLE_DOT, 1, "VWAP -band");
   IHLine("swH", stSwingH, clrOrange, STYLE_DASH, 1, "Swing High (liquidity)");
   IHLine("swL", stSwingL, clrOrange, STYLE_DASH, 1, "Swing Low (liquidity)");
   IHLine("brk", stBreakLvl, stBias == 1 ? clrLimeGreen : clrTomato, STYLE_DASHDOT, 1, stType != "" ? stType + " level" : "Break");
   string a = IPFX + "sweep";
   if(swDir != 0 && swTime > 0)
     {
      if(ObjectFind(0, a) < 0) ObjectCreate(0, a, OBJ_ARROW, 0, swTime, swLevel);
      else ObjectMove(0, a, 0, swTime, swLevel);
      ObjectSetInteger(0, a, OBJPROP_ARROWCODE, swDir == 1 ? 233 : 234);
      ObjectSetInteger(0, a, OBJPROP_COLOR, swDir == 1 ? clrLimeGreen : clrTomato);
      ObjectSetInteger(0, a, OBJPROP_WIDTH, 3);
      ObjectSetInteger(0, a, OBJPROP_ANCHOR, swDir == 1 ? ANCHOR_TOP : ANCHOR_BOTTOM);
      ObjectSetString(0, a, OBJPROP_TOOLTIP, swDir == 1 ? "Sell-side liquidity sweep" : "Buy-side liquidity sweep");
     }
   else ObjectDelete(0, a);
  }

//==================== SMART PAUSE + NET PROFIT CLOSE ====================
double   revScore[2] = {0, 0};
datetime revTime[2] = {0, 0};

// Basket ki direction (dir) ke khilaf high probability reversal?
bool ReversalAgainst(int dir)
  {
   int opp = -dir;
   if(InpPauseOnCHoCH && stBias == opp && stType == "CHoCH") return true;
   if(!InpUseScanner) return false;
   if(MasterTrend() != opp) return false;          // ulta trend confirm nahi
   int ix = opp == 1 ? 0 : 1;
   if(TimeCurrent() - revTime[ix] >= 10)
     {
      ScoreResult r;
      ScanMarket(opp, r);
      revScore[ix] = r.total; revTime[ix] = TimeCurrent();
     }
   return revScore[ix] >= InpReversalScore;
  }

void NetPL(int &baskets, double &net, double &lots)
  {
   baskets = 0; net = 0; lots = 0;
   for(int k = 0; k < NE; k++)
     {
      if(!InpHedgeMode && k >= NT) continue;
      int d, l; double a, lt, lp, pr;
      GetBasket(E[k], d, l, a, lt, lp, pr);
      if(l > 0) { baskets++; net += pr; lots += lt; }
     }
  }

// 2 ya zyada baskets (jaise hedge BUY + SELL, ya paused basket) ka total P/L profit me aaye to sab close
void CheckNetClose()
  {
   if(!InpNetClose) return;
   int nb; double net, lots;
   NetPL(nb, net, lots);
   if(nb < 2) return;
   bool anyLoss = false;
   for(int k = 0; k < NE; k++)
     {
      if(!InpHedgeMode && k >= NT) continue;
      int d, l; double a, lt, lp, pr;
      GetBasket(E[k], d, l, a, lt, lp, pr);
      if(l > 0 && pr < 0) anyLoss = true;
     }
   if(!anyLoss) return;                              // sab profit me hain to apne niyam se nikalenge
   double need = MathMax(InpNetCloseUSD, InpNetClosePerLot * lots);
   if(net >= need)
     {
      PrintFormat("NET PROFIT CLOSE: %d baskets, net %+.2f >= %.2f - sab positions profit me close", nb, net, need);
      Tg(StringFormat("NET PROFIT CLOSE: %d baskets, net %+.2f", nb, net));
      CloseAllEngines();
     }
  }

//==================== WEEKEND / MARGIN / TELEGRAM ====================
bool FridayLate(int hour)
  {
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   return dt.day_of_week == 5 && dt.hour >= hour;
  }

double AllEALots()
  {
   double l = 0;
   for(int k = 0; k < NE; k++)
     {
      if(!InpHedgeMode && k >= NT) continue;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
         if(PositionGetTicket(i) != 0 && IsMine(E[k])) l += PositionGetDouble(POSITION_VOLUME);
     }
   return l;
  }

// Saare EA baskets ka net lot: BUY (+) aur SELL (-)
double AllEANet()
  {
   double net = 0;
   for(int k = 0; k < NE; k++)
     {
      if(!InpHedgeMode && k >= NT) continue;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(PositionGetTicket(i) == 0 || !IsMine(E[k])) continue;
         double v = PositionGetDouble(POSITION_VOLUME);
         net += (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? v : -v;
        }
     }
   return net;
  }

// Ye order net exposure kam karega? (= hedge, limits se chhoot)
bool ReducesNet(int dir, double lot)
  {
   if(!InpHedgeMode) return false;
   double net = AllEANet();
   return MathAbs(net + dir * lot) < MathAbs(net) - 1e-9;
  }

// Kul lot limit + margin level check (naya basket / layer se pehle)
bool AccountRoomOK(double addLot)
  {
   if(InpMaxAllLots > 0 && AllEALots() + addLot > InpMaxAllLots + 1e-9) return false;
   if(InpMinMarginLevel > 0)
     {
      double m = AccountInfoDouble(ACCOUNT_MARGIN);
      if(m > 0 && AccountInfoDouble(ACCOUNT_MARGIN_LEVEL) < InpMinMarginLevel) return false;
     }
   return true;
  }

string UrlEncode(string s)
  {
   uchar b[];
   int n = StringToCharArray(s, b, 0, WHOLE_ARRAY, CP_UTF8);
   string out = "";
   for(int i = 0; i < n; i++)
     {
      uchar c = b[i];
      if(c == 0) break;
      if((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' || c == '~')
         out += CharToString(c);
      else
         out += StringFormat("%%%02X", c);
     }
   return out;
  }

datetime tgWarned = 0;
void Tg(string msg)
  {
   if(!InpTgOn || InpTgToken == "" || InpTgChatId == "" || MQLInfoInteger(MQL_TESTER)) return;
   string url = "https://api.telegram.org/bot" + InpTgToken + "/sendMessage";
   string body = "chat_id=" + UrlEncode(InpTgChatId) + "&text=" + UrlEncode("GoldDCA: " + msg);
   char data[], res[];
   StringToCharArray(body, data, 0, StringLen(body));
   string rh;
   int code = WebRequest("POST", url, "Content-Type: application/x-www-form-urlencoded\r\n", 3000, data, res, rh);
   if(code != 200 && TimeCurrent() - tgWarned > 3600)
     {
      tgWarned = TimeCurrent();
      PrintFormat("Telegram fail (code %d, err %d). MT5: Tools > Options > Expert Advisors > 'Allow WebRequest' me https://api.telegram.org add karein.",
                  code, GetLastError());
     }
  }

//==================== RECOVERY HEDGE ====================
// Basket phansa (layers / loss) + trend ulta (ya DCA pause) => ulti side me chhota hedge basket.
// Lot double nahi hota (martingale nahi). Net close dono ko saath profit me nikalta hai.
void CheckRecoveryHedge()
  {
   if(!InpRecHedge || !InpHedgeMode || dayStopped || rtPaused) return;
   if(TimeCurrent() < cutlossUntil) return;
   for(int k = 0; k < NE; k++)
     {
      int d, layers; double avg, lots, lp, pr;
      GetBasket(E[k], d, layers, avg, lots, lp, pr);
      if(layers == 0 || pr >= 0) continue;

      bool deep = (InpRecLayers > 0 && layers >= InpRecLayers) ||
                  (InpRecDDPct > 0 && E[k].basketStartEq > 0 && -pr / E[k].basketStartEq * 100.0 >= InpRecDDPct);
      if(!deep) continue;
      bool against = (MasterTrend() == -d) || E[k].dcaPaused;
      if(!against) continue;

      int h = (k < NT) ? k + NT : k - NT;                 // usi engine ka ulti side wala slot
      if(!E[h].on || E[h].side != -d) continue;
      int hd, hl; double ha, hlots, hlp, hpr;
      GetBasket(E[h], hd, hl, ha, hlots, hlp, hpr);
      if(hl > 0) continue;                                // hedge pehle se khula hai
      if(TimeCurrent() - E[h].recLast < InpRecCooldownMin * 60) continue;
      if(InpFridayStop && FridayLate(20)) continue;

      double lot = NormLot(lots * InpRecRatio / 100.0);
      if(lot <= 0) continue;
      E[h].basketStartEq = AccountInfoDouble(ACCOUNT_EQUITY);
      if(Open(E[h], -d, lot, "H1"))
        {
         E[h].recLast = TimeCurrent();
         E[h].basketsToday++;
         PrintFormat("[%s] RECOVERY HEDGE: %s %d layers / P/L %.2f phansa, trend ulta -> %s %.2f lot",
                     E[h].name, E[k].name, layers, pr, d == 1 ? "SELL" : "BUY", lot);
         Tg(StringFormat("RECOVERY HEDGE [%s] %s %.2f lot (phansa: %s %d layers, P/L %+.2f)",
                         E[h].name, d == 1 ? "SELL" : "BUY", lot, E[k].name, layers, pr));
        }
     }
  }
