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
