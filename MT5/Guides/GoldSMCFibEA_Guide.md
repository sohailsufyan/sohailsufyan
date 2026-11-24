# Gold SMC Fib EA v1.01: Guide

XAUUSD ka H1 swing EA. Isme SMC (BOS, liquidity sweep), Fibonacci golden zone aur 11 point ka confluence grade hai. Trade sirf high probability setup par hota hai. Aapke manual trade bhi isi strategy se manage hote hain.

> ⚠️ Pehle **demo** par kam se kam 1–2 hafte chalao. Koi bhi EA profit ki guarantee nahi deta.

---

## 1. Install (5 step)

1. `GoldSMCFibEA.mq5` ko **MT5 → File → Open Data Folder → MQL5 → Experts** me copy karo.
2. MetaEditor me file kholo aur **F7** dabao. "0 errors" aana chahiye.
3. Set files (`GoldSMCFib_*.set`) ko **MQL5 → Presets** me copy karo.
4. **XAUUSD H1** chart kholo aur EA ko chart par drag karo.
5. Inputs → **Load** → apni set file chuno → **OK**. Toolbar me **Algo Trading** green hona chahiye.

Saari doori $ me hai (jaise $5, $15), isliye **ek hi set file Vantage (2 digit) aur Exness (3 digit) dono par chalti hai**.

---

## 2. Strategy kaise kaam karti hai

### Step 1: Trend (H1)
Dono shart ek saath poori honi chahiye:

| Trend | Structure | EMA |
|---|---|---|
| **UP → sirf BUY** | Higher High + Higher Low | Price EMA200 ke upar, EMA 21 > 34 > 50 |
| **DOWN → sirf SELL** | Lower High + Lower Low | Price EMA200 ke neeche, EMA 21 < 34 < 50 |
| Side-ways | Match nahi | **Koi trade nahi** |

### Step 2: BOS (Break of Structure)
H1 candle pichhle swing high ke **upar close** kare (BUY). Isse impulse leg banta hai: low **L** se high **H** tak.

### Step 3: Fibonacci golden zone
```
Level(f) = H − f × (H − L)        (BUY)
```
| Level | Kaam |
|---|---|
| 0.5 – 0.7 | **Golden zone**: yahan pullback ka intezaar |
| 0.618 | Confirmation candle isse upar close kare |
| 0.786 | **Fakeout line** |
| 1.0 (L) | SL isse $1 neeche |
| 1.272 / 1.618 | TP |

### Step 4: Entry (sirf H1 candle close par)
- Candle golden zone ko chhuye
- **0.786 ke neeche close na kare.** Kar de to setup fail.
- **0.618 ke upar close** kare
- Hari candle ho, ya pin bar (neeche ka wick body ka 2 guna)
- Sirf **pehla pullback**

### Step 5: Grade (11 point)
| # | Point | Kab milta hai |
|---|---|---|
| 1 | H4 | H4 ka Fib level, pichhli H4 candle ka H/L/O/C, ya H1 swing level zone me |
| 2 | D / 3D | Daily ya 3-day ka Fib ya H/L/O/C zone me |
| 3 | W / big | Weekly, 1M, 3M, 6M ya Y level zone me |
| 4 | EMA | EMA 21/34/50/200 zone me, ya H4 par EMA stack bhi same |
| 5 | RSI div | RSI(7) divergence (hidden ya regular) |
| 6 | RSI zone | RSI(7) pullback zone me (BUY 30–50, SELL 50–70) |
| 7 | StochRSI | Oversold (20) se upar cross (BUY) |
| 8 | Volume | Confirmation candle ka tick volume average ka 1.5 guna |
| 9 | Sweep | Candle ne pichhla swing low, PDL ya **equal lows** (M15) toda aur wapas upar close hui. Panel par `Sweep(EQ)` = equal lows ka sweep. |
| 10 | MACD | Histogram mud gaya, ya MACD divergence |
| 11 | FVG | H1 ya M15 ka FVG golden zone ke saath overlap kare |

| Grade | Point | Default |
|---|---|---|
| A | 0–3 | Skip |
| **A+** | 4–7 | Trade |
| **A++** | 8–11 | Trade (chaho to bada lot) |

"Level zone me" ka matlab: zone ke **±$2** ke andar (`InpConfTolUSD`).

---

## 3. Exit, DCA, hedge, re-entry

| Kya | Rule |
|---|---|
| **SL** | Fib 1.0 (L) se $1 aage |
| **TP** | Fib 1.272. Strong trend (H1 + H4 EMA stack) me 1.618. Kam se kam **$15**. |
| **Smart TP** | TP se pehle raaste me mazboot liquidity ho (equal highs/lows, POC, PDH/PWH/1M/3M/6M/Y) to TP usse **$0.50 pehle**, lekin $15 se kam nahi |
| **Breakeven** | Average se **+$5** → saari positions ka SL **average + $0.20** |
| **DCA** | Har **$5 ulta**, max **3**, wahi lot, **turant** (candle close nahi). 0.786 ke paar DCA nahi. |
| **Fakeout hedge** | H1 candle 0.786 ke paar close → ulti taraf **hedge** (fixed lot, sirf **1 position**). SL 0.5 ke paar + $1, TP ulti taraf 1.272 (min $15). Breakeven hai, **DCA nahi** (`InpHedgeDCA = false`). |
| **Group close** | Default **OFF**: main aur hedge apne SL/TP se band hote hain. ON karoge (`InpGroupClose`) to total +$1 par sab band. |
| **Re-entry** | Trade breakeven par band hua aur setup abhi valid hai → **M15** candle trend ki taraf close ho → dobara entry. Ek setup me max **2**. |

### Hedge ka maths (kyun group close OFF hai)
$40 leg, 0.01 lot, fakeout ke baad:

| Setting | Price neeche hi gaya | Price wapas TP tak |
|---|---|---|
| Hedge ON + group close | −$15 | +$1 (jeet kat gayi) |
| Hedge OFF | −$27.6 | +$76 |
| **Hedge ON, group close OFF (default)** | **−$15** | **+$62** |

---

## 3b. Manual trades

Aap khud koi XAUUSD trade kholte ho (magic 0), to EA use bhi isi strategy se manage karta hai:

| Kya | Rule |
|---|---|
| Fib leg | EA ka setup usi direction me ho to wahi leg, warna pichhla H1 swing low/high |
| SL / TP | Aapne nahi lagaya to EA **Fib SL** (L − $1) aur **Fib TP** (min $15, smart TP) lagayega. Aapka apna SL/TP ho to waisa hi rahega (`InpKeepManualSLTP`). |
| Breakeven | +$5 → SL average + $0.20 |
| DCA | 3 × $5, **aapke trade ke lot se**, 0.786 tak |
| Hedge | 0.786 ke paar H1 close → hedge (aapke lot se, 1 position) |

Band karna ho to `InpManageManual = false`.

---

## 4. Example (BUY)

L = 3500, H = 3540 (leg $40)

| | Price |
|---|---|
| Golden zone | 3520.00 – 3512.00 |
| Entry (0.618 ke upar H1 close) | ~3515.30 |
| DCA 1 (−$5) | 3510.30 |
| DCA 2 (−$10) | 3505.30 → 0.786 (3508.56) ke neeche, **nahi lagega** |
| Fakeout line 0.786 | 3508.56 |
| SL | 3499.00 |
| TP 1.272 / 1.618 | 3550.88 / 3564.72 |
| Breakeven | 3520.30 par SL 3515.50 |

**0.01 lot par:** TP aaya to +$35.6 (strong trend me +$49.4). Entry + 1 DCA ke saath SL laga to lagbhag −$27.6.

---

## 5. Risk table

Gold me **0.01 lot = $1 move par $1**.

| Account | Lot | Daily SL | Set file |
|---|---|---|---|
| $1,000 | 0.01 | $50 | `GoldSMCFib_1_1000_Safe.set` |
| $1,000 | 0.02 | $100 | `GoldSMCFib_2_1000_Normal.set` |
| $1,000 | 0.02, sirf A++ | $100 | `GoldSMCFib_3_APlusPlus_Only.set` |
| $5,000 | 0.05 | $250 | `GoldSMCFib_4_5000.set` |
| $10,000 | 0.10 | $500 | `GoldSMCFib_5_10000.set` |

Ek setup me sabse zyada **5 position** ho sakti hain: entry + 3 DCA + 1 hedge. Isliye lot chhota rakho aur **Daily SL limit** hamesha ON rakho.

---

## 6. Limits (sab Inputs me badal sakte ho)

| Input | Default | Kaam |
|---|---|---|
| `InpLot` | 0.01 | Fixed lot |
| `InpMaxTradesDay` | 7 | Entry + re-entry + hedge gine jate hain, DCA nahi |
| `InpDailySLUSD` | 100 | Aaj ka loss itna hua → us din nayi entry band |
| `InpDailyCloseAll` | false | true = daily SL lagte hi khule trade bhi band |
| `InpDailyTargetUSD` | 0 (off) | Target poora → us din nayi entry band |
| `InpMaxConsecLoss` | 3 | Lagatar itne loss → us din band |
| `InpWeeklyLossPct` | 5% | Hafte ka loss limit |
| `InpEquityStopPct` | 10% | Equity din-shuru se itna gire → sab band |
| `InpMaxSpreadUSD` | $0.50 | Isse zyada spread par entry nahi |
| `InpNewsFilter` | ON | USD ki high-impact news ke ±15 min entry nahi |
| `InpMinGrade` | A+ | Isse kam grade = skip |

---

## 7. Panel

| Line | Matlab |
|---|---|
| Trend H1 / H4 | UP / DOWN / SIDE |
| Setup | Leg ka L, H, golden zone aur 0.786 line |
| Grade | Jaise `A+ 6/10 H4 D/3D EMA RSIdiv Vol Sweep` |
| Entry | Trade kyun khula ya kyun ruka |
| MAIN / HEDGE / MANUAL | Position, lot, average, P/L |
| Aaj | Trade x/7, aaj ka P/L, daily SL, ACTIVE ya STOP ka kaaran |
| Stats | Win %, A+ aur A++ ka win %, average jeet/haar |

**Buttons:** EA ON/OFF, CLOSE ALL, HEATMAP ON/OFF, Min grade −/+, Lot −/+, Heatmap range (12H / 1D / 3D / 1W / 1M / ALL)

---

## 8. Liquidity heatmap

| Rang | Kya hai |
|---|---|
| 🔴 Laal pattiyan | Swing highs. Jitna gehra, utne equal highs (zyada stop-loss jama). |
| 🟢 Hari pattiyan | Swing lows / equal lows |
| ⚫ Dhundhli | Sweep ho chuki liquidity (le li gayi) |
| 🔵 Neela box | Bullish FVG (bhara nahi) |
| 🟣 Baingani box | Bearish FVG |
| Rangeen lines | H4, D, 3D, W, 1M, 3M, 6M, Y ke H / L (solid) aur O / C (dotted) |
| Right side bars | Volume profile. Peela bar = sabse zyada trading wala price (POC). |

Heatmap har naye M15 candle par update hota hai. 12H range me M15 swings dikhte hain, baaki me H1.

---

## 9. Journal

Har band trade `MQL5/Files/GoldSMCFib_Journal.csv` me save hota hai: time, BUY/SELL, kind (ENTRY / DCA / REENTRY / HEDGE), grade, lot, open, close, profit, kaaran (TP / SL / BE).

Excel me kholkar dekh sakte ho ki kaunsa grade sabse zyada jeet raha hai.

---

## 10. FAQ

**Trade kyun nahi le raha?** Panel ki **Entry** line padho. Usme likha hoga: trend side-ways, BOS ka intezaar, pullback ka intezaar, confirmation nahi, grade kam, ya limit lagi hai. Ye EA hafte me kuch hi trade leta hai. Ye normal hai.

**Restart kiya to?** Setup, din ki limits aur lagatar loss yaad rehte hain (MT5 Global Variables).

**Strategy Tester me?** "Every tick based on real ticks", XAUUSD, H1, kam se kam 6–12 mahine ka data. News filter tester me band rehta hai.

**Kabhi nahi karta:** doosre EA ke trade nahi chhedta, lot double nahi karta.
