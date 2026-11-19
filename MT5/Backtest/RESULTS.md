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

## Run 2 – $20,000 account, fixed 0.1 lot per layer, $11 DCA (unlimited), 50% book + trailing, breakeven exit
Script: `GoldDCA_Fixed01_BT.pine` (OANDA:XAUUSD 15m, 2025-11-19 → 2026-11-19)

| Metric | Value |
|---|---|
| Net profit | **+$10,724 (+53.6%)** ≈ $894/month, ~3.6%/month compounded |
| Max drawdown | **$4,398 (15.5%)** |
| Profit factor | 2.53 |
| Win rate (per fill) | 74.7% |
| Avg win / avg loss | $53.09 / $62.03 |
| Largest single loss / win | $403 / $482 |
| Max position | 0.90 lot (9 layers ≈ $90-99 against) |
| Longs / Shorts net | +$3,162 (PF 1.84) / +$7,562 (PF 3.31) |
| Commission | $860 |
| Buy & hold | -11.7% |

Hard stop 15% vs 65%: identical result – the hard stop never triggered in these 12 months.
