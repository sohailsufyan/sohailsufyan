# Third-party Gold EAs (bug-fixed copies)

Yeh 4 EAs doosre GitHub repos se liye gaye hain aur unke bugs fix kiye gaye hain.
Har folder mein us EA ka original license hai. Inmein se koi bhi EA backtest
mein proven nahi hai – live account se pehle Strategy Tester mein test karein.

> Note: Yeh files MetaEditor mein compile karke check nahi ki gayi (fix ek Linux
> container mein hue). Pehle F7 se compile karein, error aaye to bata dein.

| Folder | Source | License | Version |
|---|---|---|---|
| `EA_SCALPER_XAUUSD/` | github.com/francomascareloai/EA_SCALPER_XAUUSD | PolyForm Noncommercial + `TRADING_RESTRICTIONS.md` (sirf offline backtest, live/demo-broker par mana) | EA_SCALPER_XAUUSD 4.32, EA_AGGRESSIVE_SCALPER 3.12 |
| `ICT_CRT_Gold_System/` | github.com/Design-Arena-Gens/agentic-620c05c3 (AI-generated) | Koi license file nahi | 1.02 |
| `Fib_GoldenZone_EA/` | github.com/vrd07/Quant_Trading (`mt5_bridge/`) | MIT | 1.02 |

## Install

- **EA_SCALPER_XAUUSD / EA_AGGRESSIVE_SCALPER**: `EA_SCALPER_XAUUSD/MQL5/Experts/*.mq5` ko
  `MQL5/Experts/` mein, aur `EA_SCALPER_XAUUSD/MQL5/Include/EA_SCALPER/` folder ko
  `MQL5/Include/EA_SCALPER/` mein copy karein. (Original repo ka baaki `Include/`
  copy na karein – woh MT5 ki standard library overwrite karta hai.)
- **ICT_CRT_Gold_System**: poora folder `MQL5/Experts/ICT_CRT_Gold_System/` mein.
- **Fib_GoldenZone_EA**: `.mq5` ko `MQL5/Experts/` mein.

## Kya fix hua

### EA_SCALPER_XAUUSD (4.3 → 4.32)
- Broker TP ab final target par; pehle TP1 par poori position band ho jati thi aur 40%/30%/trail kabhi nahi chalta tha (`Include/EA_SCALPER/Execution/CTradeManager.mqh`).
- Purana executor har trade par fixed 150/200-point breakeven/trailing laga raha tha – band.
- Ek waqt mein ek trade; pehle har tick poora signal pipeline chalta tha aur order fail hota tha.
- Lot kabhi min lot tak upar round nahi hota (risk se zyada); drawdown/news size-cut hamesha lagta hai.
- Tester mein spread cap chupke se 200 point nahi hota; `InpTesterMaxSpread` input.
- TrendFollow signal ab apna SL/TP use karta hai (pehle compute hokar ignore hota tha).

### EA_AGGRESSIVE_SCALPER (3.10 → 3.12)
- Signal ab last closed candle par (pehle 1-tick wali candle – candle/sweep/delta checks kabhi true nahi hote the).
- Breakeven ke baad partial/trailing ab chalta hai (pehle risk 0 maan kar skip).
- Restart par purane saare deals learning mein dobara nahi jaate; partial close alag trade nahi gina jata.
- Edge sizing asli TP R:R se (pehle 3.0 maan kar losing system bhi 3% risk leta tha).
- Lot min lot tak round-up nahi; MTF block ab final; filling mode symbol se; GMT offset sahi.
- Daily equity / trade count / loss streak restart ke baad bhi yaad rehte hain.
- `InpUseModeSettings` (default true): mode ke BE/partial/risk values ab use hote hain.
- `InpMaxSpread` aur `InpUseNewsBlock` har mode mein kaam karte hain.
- Breakeven exit loss streak mein nahi gina jata.

### ICT_CRT_Gold_System (1.00 → 1.02)
- **Auto lot 100x (2-digit gold) / 1000x (3-digit) bada tha** – fix.
- Min lot round-up band; EA remove par crash (`OnDeinit`) fix; `::SendNotification` compile fix.
- Trailing aur drawdown check har tick; filling mode symbol se.
- Sirf is EA ki (magic) position naya trade rokti hai; max-drawdown peak restart ke baad yaad rehta hai.
- Dhyan dein: is EA ka "CRT" Candle Range Theory **nahi** hai (supply/demand + trendline + volume profile hai).

### Fib_GoldenZone_EA (1.00 → 1.02)
- Traded/expired/invalid leg dobara arm nahi hoti (pehle `InpExpireBars` kaam nahi karta tha aur TP/trail ke baad wahi leg dobara trade hoti thi).
- Bar-close mode mein fill ke baad ki pehli candle confirmation mein gini jati hai.
- "PLACED phir reject" wala fill EA ko hamesha ke liye block nahi karta.
- `InpRiskPercent` (default 0 = purane fixed lots): har leg equity ke % risk se size.
