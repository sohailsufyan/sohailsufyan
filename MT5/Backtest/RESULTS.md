# GoldDCA_EA – 12 month backtest (TradingView Deep Backtesting)

- Symbol / TF: OANDA:XAUUSD, 15m (Intraday engine port: `GoldDCA_Intraday_BT.pine`)
- Period: 2025-11-19 → 2026-11-19, start capital $1,000, 0.01 lot per $1,000 (auto), cost $0.30/oz round trip
- Not included: Tick-M1 & Scalp-M5 engines, news filter, tick order-flow (neutral 4/15), swap, real broker spread/slippage

| Metric | Scanner ON (min score 75) | Scanner OFF |
|---|---|---|
| Net profit | **+$473 (+47.3%)** | +$822 (+82.2%) |
| Max drawdown | **$415 (26.6%)** | $1,080 (45.0%) |
| Profit factor | **1.31** | 1.13 |
| Win rate (per layer) | 64.5% | 62.8% |
| Avg win / avg loss | $10.91 / $15.13 | $10.49 / $15.72 |
| Trades (layer fills) | 282 | 1,095 |
| Longs net / PF | +$364 / 2.08 | +$611 / 1.23 |
| Shorts net / PF | +$109 / 1.09 | +$210 / 1.06 |
| Commission paid | $99 | $458 |
| Buy & hold same period | -11.4% | -10.9% |

Average ≈ 3.3% per month (compounded) with scanner ON.
