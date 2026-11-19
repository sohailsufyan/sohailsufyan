# GoldSwingEA – MT5 XAUUSD Swing Expert Advisor

## Strategy
- **Trend filter:** D1 close > D1 EMA50 (buy) / < (sell)
- **Signal TF (H4):** EMA21 > EMA50 > EMA200 (buy) / ulta (sell)
- **Entry:** Price pichle 5 candles me EMA21 tak pullback kare, phir trend direction me
  strong candle close ho + RSI 50–70 (buy) / 30–50 (sell)
- **SL:** 1.5 × ATR  |  **TP:** 3.5 × ATR  (~1:2.3 Risk:Reward)
- **Management:** 1R par 50% partial close, breakeven, ATR trailing stop

## Risk protection
| Feature | Default |
|---|---|
| Risk per trade | 2% equity (lot auto-calculate) |
| Max daily loss | 5% – us din aur trade nahi |
| Max drawdown (peak se) | 25% – sab close, EA halt |
| Monthly target lock | 50% – hit hote hi us mahine naye trade band |
| Margin cap | Free margin ka max 30% ek trade me |
| Spread / session / Friday filter | Haan |

## Install
1. `Experts/GoldSwingEA.mq5` ko `MQL5/Experts/` me copy karein
2. MetaEditor me open karke **F7** (compile)
3. XAUUSD **H4** chart par lagayein, *Algo Trading* ON
4. Preset: EA inputs → *Load* → `Presets/*.set`

## Leverage aur 50% monthly – sach
- 500x leverage **sirf margin** kam karti hai. Profit/loss lot size aur SL distance se aata hai.
- H4 swing par ~4–10 trades/mahina aate hain. 50% monthly ke liye har trade par ~5%+
  risk lagana padega – 5–6 consecutive losses (normal baat hai) = ~25–30% drawdown.
- **Realistic:** Safe 3–8%, Moderate 5–15%, Aggressive kabhi +30–50%, kabhi -30–40%.
- Isliye EA me monthly target lock + drawdown kill-switch diya hai.

## Testing (zaroori)
1. Strategy Tester → XAUUSD, H4, *Every tick based on real ticks*, kam se kam 2–3 saal
2. Apne broker ke hisaab se `InpMaxSpreadPoints` aur session hours (server time) adjust karein
3. Kam se kam 1 mahina demo, phir chhote real account se start

> Disclaimer: Ye educational tool hai, financial advice nahi. Past performance future ki guarantee nahi.

---

# GoldDCA_EA – Trend DCA EA (XAUUSD)

- **Entry:** H1 trend (EMA50/200) ki direction me, M15 par EMA9 > EMA21 + RSI confirm
- **DCA:** Price $7 against jaye to naya layer (lot x1.3, gap x1.2), max 6 layers
- **Confirm:** MACD (line > signal, histogram badh raha, zero line ke sahi side) + ATR filter (bahut volatile ya dead market me entry nahi)
- **Exit:** Average price se 0.5 x ATR (min $1.5) profit par poora basket close
- **Auto TP/SL:** Har layer par broker-side common TP (basket target) aur SL (hard stop price) lagta hai, har naye layer par update
- **Daily:** 5% target hit → naye basket band; 15% daily loss → sab close
- **Hard stop:** Basket loss equity ka 15% → sab close (isko OFF mat karein)
- **News:** High-impact USD news se 30 min pehle/baad naya trade/DCA nahi, pehle profit me ho to close
  (sirf live/demo me kaam karta hai, Strategy Tester me MT5 calendar nahi hota)
- **Account:** Hedging account zaroori
- **S/R Levels (v1.20):** Previous Year, Half-year, Quarter, Month, Week, 3-Day, Day aur last 5 H4 candles ke
  Open/High/Low/Close chart par draw hote hain (sab par zone box: bade levels ±$1, 3D/D/H4 ±$0.5). BUY ke thoda upar (ya SELL ke
  thoda neeche) Week ya usse bada level ho to naya basket skip hota hai.

## GoldDCA_EA v2.00 – Scalp + Intraday (dono saath)
| | Scalp | Intraday |
|---|---|---|
| Signal / Trend TF | M5 / M15 | M15 / H1 |
| DCA step | $4 | $7 |
| Max layers | 4 (lot x1.2) | 6 (lot x1.3) |
| TP | 0.6 x ATR (min $0.8) | 0.5 x ATR (min $1.5) |
| Basket hard stop | 6% equity | 12% equity |
| Magic | base + 1 | base + 2 |

- Dono engine **H1 master trend** ki direction me hi entry lete hain (UP = sirf BUY, DOWN = sirf SELL, sideways = no entry)
- Ek engine BUY basket me ho to doosra SELL nahi kholta (`InpNoOpposite`)
- Daily target 5% / daily loss 15% poore account par (dono engine milake)
- Sirf ek chahiye to `InpScOn` ya `InpInOn` = false

## v2.10 – naye features
- **Basket trailing:** TP level aate hi basket close nahi hota, TP ka 50% lock hokar trailing SL chalta hai (broker SL bhi update)
- **Fixed Add lot:** layer lot = pehla lot + pehla lot x 0.5 x N (multiplier ki jagah seedha badhna)
- **New candle gate:** ek signal-TF candle me max 1 DCA layer
- **Cutloss $:** dono engine ka floating loss X $ ho to sab close, 30 min cooldown ke baad resume (ya din band)
- **Manual trades:** magic 0 wale manual trade Intraday engine ke basket me aa jaate hain, unpar DCA/TP/SL lagta hai

## v2.20 – TICK M1 Scalp engine (3rd engine, magic base + 3)
- Har tick par check hota hai (bar close ka wait nahi)
- Entry: H1 master + M5 trend same, M1 EMA9/21 + RSI aligned, aur **pichle 5 sec me trend direction me $0.30+ ka tick burst** (min 5 ticks)
- $2+ ka jhatka (spike/news) = entry nahi; spread 30 points se zyada = entry nahi
- DCA step $2 (gap x1.3), max 3 layers, TP 0.8 x M1 ATR (min $0.40), hard stop 4%, cooldown 30 sec
- Ek M1 candle me max 1 naya basket aur max 1 DCA layer
- Strategy Tester me **"Every tick based on real ticks"** mode zaroori hai

## v2.30 – Market Scanner (sirf high probability entry)
Har naye basket se pehle 0-100 score banta hai; default **75+ (HIGH)** par hi entry:
| Part | Max | Kya check |
|---|---|---|
| MTF alignment | 25 | M5, M15, H1, H4, D1 par EMA50/200 trend same direction |
| Momentum | 15 | H1 RSI zone, M15 MACD histogram, H1 ADX >= 20 + DI |
| Volatility | 10 | M15 ATR apne 50-bar average ka 0.8x-2x |
| Session | 10 | London+NY overlap 10, London/NY 7, Asia 3 (`InpServerGMTOffset` set karein) |
| Liquidity | 15 | PDH/PDL ya swing high/low ka stop-hunt sweep = 15, warna aage S/R tak jagah |
| Order flow | 15 | Last 60s uptick/downtick pressure + M5 tick volume surge |
| Cross-asset | 10 | EURUSD (Dollar ulta) + XAGUSD (Silver saath); symbol na mile to neutral |
- ELITE (85+) par lot x `InpEliteLotMult` (default 1.0)
- Panel par live score + breakdown; Experts log me har entry/skip ka score

## v2.40 – Signal Panel + $7 DCA sab engines + 50% booking
- **Signal Panel (chart par):** status badge, account tiles (Balance/Equity/Floating/Margin), drawdown bar,
  BUY/SELL/WAIT signal card + score /100 + tier, trade plan (Entry, TP1 = 50% book, TP2 = trailing, DCA levels, hard stop),
  7-part score breakdown bars, session + agla session (IST), news status, teeno engine cards, aaj ka P/L
- **Alerts:** naya HIGH signal par MT5 popup + phone push (MT5 app me MetaQuotes ID set karein)
- **DCA:** Scalp, Intraday, Tick-M1 – teeno me har $11 against par naya layer (step growth 1.0), layers unlimited (0); rok sirf hard stop / cutloss / trend-flip / margin / `InpMaxTotalLots`
- **50% booking:** basket TP level aate hi 50% volume close, baaki trailing SL par (`InpBookPct`)

## v2.60 – Customised settings (preset: `Presets/GoldDCA_Recommended.set`)
- Lot: 0.01 per $2,000 balance (fixed-add 0.5) | DCA $11, unlimited layers
- Hard stop: Scalp 10%, Intraday 15%, Tick 8% equity
- **Breakeven exit:** 3+ layers ke baad price average + $0.50 par aaye to poora basket close

## v2.70 – Chart control buttons (panel ke neeche)
- **SCALP / INTRADAY / TICK-M1 ON-OFF:** engine band karne par naye trade nahi, chalu basket ka TP/SL/trailing chalta rahega
- **Direction:** BUY + SELL → BUY ONLY → SELL ONLY (click se badlta hai)
- **PAUSE / RESUME:** naye basket aur DCA band, exits chalte rahenge
- **DCA − / +:** sab engines ka DCA gap $1 kam/zyada
- **Lot − / +:** lot 0.5x se 10x (0.5 ke step me)
- **CLOSE ALL EA TRADES:** confirm ke baad saare EA baskets close
- Button settings restart ke baad bhi yaad rehti hain

## v2.80 – Hard stop 80% (customisable)
- Default hard stop: Scalp / Intraday / Tick = **80% equity**, daily loss limit = **80%**
- Panel buttons: **Hard SL − / +** (5% step, sab engines) aur **Day loss − / +** (5% step); restart ke baad bhi yaad
- WARNING: 80% par ek bura basket account ka 80% le sakta hai

## v2.90 – Hedge mode (BUY + SELL dono)
- `InpHedgeMode = true` (default): har engine ka **BUY basket aur SELL basket alag-alag** chal sakte hain (SCALP-BUY / SCALP-SELL, INTRADAY-BUY / -SELL, TICK-M1-BUY / -SELL)
- Dono side apna DCA ($11), TP, 50% book, trailing, breakeven aur hard stop alag rakhte hain
- Naya basket ab bhi trend ki direction me hi khulta hai; trend palatne par purana basket chalta rehta hai (uska DCA ruk jata hai) aur nayi direction ka basket khul jata hai
- Panel par 6 engine rows (BUY hara, SELL laal); ON/OFF button dono side ek saath
- v2.91: `InpAddOnlyInTrend = false` (default) – BUY aur SELL dono side ka DCA hamesha chalu, chahe basket EA ne khola ho ya manual trade ho
- v2.92: retracement exit – DCA wala basket (2+ layers) BUY ho ya SELL, average + $0.50 profit aate hi poora close (`InpBEMinLayers = 2`)

## v3.00 – Fixed $ exit (default, BUY aur SELL dono basket par)
- Average se **+$3** → SL **+$1** par lock, trailing shuru
- Trailing SL price ke **$2 peeche** chalta hai
- Average se **+$5** → poora basket close (broker TP bhi +$5 par)
- Inputs: `InpFxTrigger`, `InpFxLock`, `InpFxTrailDist`, `InpFxTP`, `InpFxBookPct` (trigger par % book, default 0)
- `InpFxExit = false` karne par purana ATR TP + 50% book + $0.50 breakeven tareeka
- v3.10: **Backup exit** – price average se +$2 tak aaye (lekin +$3 na chhue) aur wapas +$0.50 par aaye to poora basket profit me close (`InpFxBackup`, `InpFxBackupArm`, `InpFxBackupExit`)

## v3.20 – Institutional: Structure (BOS/CHoCH) + Liquidity Sweep + VWAP
- **Market structure (M15):** fractal swing high/low; close swing ke paar = **BOS** (trend jaari) ya **CHoCH** (trend badla). Naya basket sirf structure ki direction me (`InpUseStructure`)
- **Liquidity sweep:** swing ya pichle din ke high/low ke paar wick, phir wapas andar close = stop-hunt. `InpRequireSweep = true` karne par entry sirf sweep ke baad
- **VWAP (aaj ka):** BUY sirf VWAP ke upar, SELL sirf neeche (`InpUseVWAP`). `InpVWAPDCA = true`: DCA layer sirf VWAP band ke bahar (discount/premium zone)
- Chart: VWAP + bands (neela), swing levels (orange), BOS/CHoCH level, sweep arrow. Panel me Structure / Sweep / VWAP row

## v3.30 – Smart DCA pause + Net profit close
- **DCA pause:** basket ke khilaf high probability reversal (ulta master trend + ulti direction ka scanner score 75+, ya structure ka ulta CHoCH) aaye to us basket ka DCA ruk jata hai; reversal hatne par phir chalu. Panel: "DCA PAUSED (reversal)"
- **Net profit close:** 2 ya zyada basket khule hon aur koi loss me ho, to jab saare baskets ka total P/L ≥ max($5, $50 × kul lot) ho jaye, sab positions ek saath profit me close
- Panel me NET row: kitne baskets, kul lot, net P/L, kis $ par sab close hoga

## v3.40 – Early Escape (fasne se pehle profit me bahar)
Basket me inme se koi bhi khatra dikhe to **ESCAPE mode**: average se sirf **+$0.20** profit aate hi poora basket close (+$3/+$5 ka intezaar nahi):
- Ulti direction ka score 60+ (MEDIUM) aur trend ya structure ulta (reversal risk) – DCA bhi ruk jata hai
- High-impact news aane wali – DCA bhi ruk jata hai
- 4 ya zyada layers ho gaye
- Basket 6 ghante se purana
- Basket ka loss equity ka 5%+
Panel: "ESCAPE: <kaaran>". Inputs: `InpEscape*`
