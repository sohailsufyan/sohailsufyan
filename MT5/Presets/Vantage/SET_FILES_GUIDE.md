# Hedge Scalper Set Files (Vantage)

Load: EA chart par lagao → Inputs → **Load** → set file → OK. Pehle demo.

| Set | Lot | Max/side | TP | DCA | Margin stop | Kiske liye |
|---|---|---|---|---|---|---|
| Gold_1_Safe | 0.01 / $2000 | 3 | +$1 | $4 | 500% | Naye users |
| Gold_2_Normal | 0.01 / $1000 | 5 | +$1 | $3 | 300% | Default |
| Gold_3_Aggressive | 0.01 / $500 | 8 | +$0.8 | $2.5 | 200% | Zyada risk, 24h |
| Gold_4_BothSides | 0.01 / $1000 | 5 | +$0.6 | $3 | 300% | Video jaisa BUY+SELL |
| Gold_5_SmallAccount | 0.01 fixed | 2 | +$1 | $4 | 500% | $100–500 account |
| BTC_1_Safe | 0.01 / $2000 | 3 | +$30 | $200 | 500% | Naye users |
| BTC_2_Normal | 0.01 / $1000 | 5 | +$30 | $150 | 300% | Default |
| BTC_3_Aggressive | 0.01 / $500 | 8 | +$25 | $120 | 200% | Zyada risk |
| BTC_4_BothSides | 0.01 / $1000 | 5 | +$25 | $150 | 300% | BUY+SELL dono |
| BTC_5_SmallAccount | 0.01 fixed | 2 | +$30 | $200 | 500% | $100–500 account |

Sab sets: M1, EMA 21/50 + H1 trend, breakeven (2+ positions), net close $5, Gold spread max $0.60, BTC $50, GMT+2.
Gold sets → GoldHedgeScalper (XAUUSD chart). BTC sets → BTCHedgeScalper (BTCUSD chart).

**v1.20 (sab sets me):** Pair Close ON ($0.20+), Recovery Hedge 50% (max 100%, ek side ka ek hedge), Auto LOCK (margin 200% / Safe+Small 300% / Aggressive 150%, USD high-impact news ±15 min), manual trade ka apna SL/TP waisa hi rahe. Breakeven: Gold +$1.5 chale to SL average + $0.50, BTC +$40 chale to average + $20.

**v1.21:** Hedge sirf M1 trend se (H1 ka intezaar nahi), loss ≥ 5% balance par hedge turant, hedge ka profit lock.
