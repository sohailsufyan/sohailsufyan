//+------------------------------------------------------------------+
//|                                         RiskManagement.mqh       |
//|                              Risk & Money Management Functions   |
//+------------------------------------------------------------------+
#property copyright "ICT CRT Gold Trading System"
#property strict

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Risk Management Class                                            |
//+------------------------------------------------------------------+
class CRiskManagement
{
private:
    double      m_riskPercent;
    double      m_maxDrawdownPercent;
    bool        m_useAutoLot;
    double      m_fixedLotSize;
    double      m_stopLossPoints;
    double      m_takeProfitPoints;
    bool        m_useTrailingStop;
    double      m_trailingStopPoints;

    double      m_initialBalance;
    double      m_peakBalance;
    double      m_currentDrawdown;

    CTrade      m_trade;

public:
    //--- Constructor
    CRiskManagement()
    {
        m_riskPercent = 2.0;
        m_maxDrawdownPercent = 10.0;
        m_useAutoLot = true;
        m_fixedLotSize = 0.01;
        m_stopLossPoints = 500;
        m_takeProfitPoints = 1000;
        m_useTrailingStop = true;
        m_trailingStopPoints = 300;

        m_initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        m_peakBalance = m_initialBalance;
        m_currentDrawdown = 0;

        // FIX v1.02: Restore the peak balance saved by an earlier run on this account,
        // so restarting the EA does not reset the max-drawdown protection.
        // (Delete the terminal global variable "ICTCRT_PEAK_<login>_<symbol>" to reset.)
        string key = PeakKey();
        if(GlobalVariableCheck(key))
        {
            double saved = GlobalVariableGet(key);
            if(saved > m_peakBalance) m_peakBalance = saved;
        }
        GlobalVariableSet(key, m_peakBalance);
        if(m_peakBalance > 0)
            m_currentDrawdown = ((m_peakBalance - m_initialBalance) / m_peakBalance) * 100.0;
    }

    string PeakKey()
    {
        return "ICTCRT_PEAK_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_" + _Symbol;
    }

    //--- Destructor
    ~CRiskManagement() {}

    //+------------------------------------------------------------------+
    //| Set Risk Parameters                                              |
    //+------------------------------------------------------------------+
    void SetRiskParameters(double riskPercent, double maxDrawdown,
                          bool useAutoLot, double fixedLot)
    {
        m_riskPercent = riskPercent;
        m_maxDrawdownPercent = maxDrawdown;
        m_useAutoLot = useAutoLot;
        m_fixedLotSize = fixedLot;

        Print("Risk Parameters Set: Risk=", m_riskPercent, "% MaxDD=",
              m_maxDrawdownPercent, "%");
    }

    //+------------------------------------------------------------------+
    //| Set Stop Loss                                                    |
    //+------------------------------------------------------------------+
    void SetStopLoss(double points)
    {
        m_stopLossPoints = points;
    }

    //+------------------------------------------------------------------+
    //| Set Take Profit                                                  |
    //+------------------------------------------------------------------+
    void SetTakeProfit(double points)
    {
        m_takeProfitPoints = points;
    }

    //+------------------------------------------------------------------+
    //| Set Trailing Stop                                               |
    //+------------------------------------------------------------------+
    void SetTrailingStop(bool useTrailing, double points)
    {
        m_useTrailingStop = useTrailing;
        m_trailingStopPoints = points;
    }

    //+------------------------------------------------------------------+
    //| Calculate Lot Size Based on Risk                                |
    //+------------------------------------------------------------------+
    double CalculateLotSize(string symbol, double stopLossPoints)
    {
        if(!m_useAutoLot)
            return m_fixedLotSize;

        double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        double riskAmount = accountBalance * (m_riskPercent / 100.0);

        double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
        double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);

        if(tickSize <= 0 || point <= 0 || stopLossPoints <= 0)
            return 0.0;

        // Money per 1 point move for 1 lot
        double valuePerPoint = (tickValue / tickSize) * point;
        if(valuePerPoint <= 0)
            return 0.0;

        // FIX: Loss for 1 lot at the SL = stopLossPoints * valuePerPoint.
        // The old formula also multiplied by "point" (0.01 / 0.001 on gold), which made
        // the lot 100x (2-digit gold) or 1000x (3-digit gold) too BIG.
        // Example: $1000, 2%, SL 500 pts on 2-digit gold -> correct 0.04 lot, old code 4.00 lots.
        double lotSize = riskAmount / (stopLossPoints * valuePerPoint);

        // Normalize lot size
        double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
        double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
        if(lotStep <= 0) lotStep = 0.01;

        lotSize = MathFloor(lotSize / lotStep + 1e-7) * lotStep;
        lotSize = MathMin(maxLot, lotSize);

        // FIX: Never round UP to the broker minimum - that risks more than RiskPercent.
        if(lotSize < minLot)
        {
            Print("Lot ", DoubleToString(lotSize, 3), " < min lot ", minLot,
                  " - trade skipped (min lot would risk more than ", m_riskPercent, "%)");
            return 0.0;
        }

        Print("Calculated Lot Size: ", lotSize, " (Risk: ", m_riskPercent,
              "% of ", accountBalance, ")");

        return lotSize;
    }

    //+------------------------------------------------------------------+
    //| Calculate Buy Stop Loss                                         |
    //+------------------------------------------------------------------+
    double CalculateBuyStopLoss(double entryPrice, double stopPoints)
    {
        double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
        double sl = entryPrice - (stopPoints * point);

        // Normalize price
        int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
        sl = NormalizeDouble(sl, digits);

        return sl;
    }

    //+------------------------------------------------------------------+
    //| Calculate Sell Stop Loss                                        |
    //+------------------------------------------------------------------+
    double CalculateSellStopLoss(double entryPrice, double stopPoints)
    {
        double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
        double sl = entryPrice + (stopPoints * point);

        // Normalize price
        int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
        sl = NormalizeDouble(sl, digits);

        return sl;
    }

    //+------------------------------------------------------------------+
    //| Calculate Buy Take Profit                                       |
    //+------------------------------------------------------------------+
    double CalculateBuyTakeProfit(double entryPrice, double tpPoints)
    {
        double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
        double tp = entryPrice + (tpPoints * point);

        // Normalize price
        int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
        tp = NormalizeDouble(tp, digits);

        return tp;
    }

    //+------------------------------------------------------------------+
    //| Calculate Sell Take Profit                                      |
    //+------------------------------------------------------------------+
    double CalculateSellTakeProfit(double entryPrice, double tpPoints)
    {
        double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
        double tp = entryPrice - (tpPoints * point);

        // Normalize price
        int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
        tp = NormalizeDouble(tp, digits);

        return tp;
    }

    //+------------------------------------------------------------------+
    //| Update Trailing Stops                                           |
    //+------------------------------------------------------------------+
    void UpdateTrailingStops(int magicNumber)
    {
        if(!m_useTrailingStop)
            return;

        double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
        int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;

            if(PositionGetInteger(POSITION_MAGIC) != magicNumber)
                continue;

            if(PositionGetString(POSITION_SYMBOL) != _Symbol)
                continue;

            double positionOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double positionSL = PositionGetDouble(POSITION_SL);
            double positionTP = PositionGetDouble(POSITION_TP);
            ENUM_POSITION_TYPE positionType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

            double currentPrice = 0;
            double newSL = 0;

            if(positionType == POSITION_TYPE_BUY)
            {
                currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                double profitPoints = (currentPrice - positionOpenPrice) / point;

                if(profitPoints > m_trailingStopPoints)
                {
                    newSL = currentPrice - (m_trailingStopPoints * point);
                    newSL = NormalizeDouble(newSL, digits);

                    if(newSL > positionSL)
                    {
                        if(m_trade.PositionModify(ticket, newSL, positionTP))
                        {
                            Print("Trailing stop updated for Buy position #", ticket,
                                  " New SL: ", newSL);
                        }
                    }
                }
            }
            else if(positionType == POSITION_TYPE_SELL)
            {
                currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                double profitPoints = (positionOpenPrice - currentPrice) / point;

                if(profitPoints > m_trailingStopPoints)
                {
                    newSL = currentPrice + (m_trailingStopPoints * point);
                    newSL = NormalizeDouble(newSL, digits);

                    if(newSL < positionSL || positionSL == 0)
                    {
                        if(m_trade.PositionModify(ticket, newSL, positionTP))
                        {
                            Print("Trailing stop updated for Sell position #", ticket,
                                  " New SL: ", newSL);
                        }
                    }
                }
            }
        }
    }

    //+------------------------------------------------------------------+
    //| Monitor Drawdown                                                 |
    //+------------------------------------------------------------------+
    void MonitorDrawdown()
    {
        double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);

        // Update peak balance
        if(currentBalance > m_peakBalance)
        {
            m_peakBalance = currentBalance;
            GlobalVariableSet(PeakKey(), m_peakBalance);   // FIX v1.02: persist
        }

        // Calculate drawdown
        if(m_peakBalance > 0)
        {
            m_currentDrawdown = ((m_peakBalance - currentBalance) / m_peakBalance) * 100.0;
        }

        // FIX: Now called every tick, so only log when the state changes (no log spam)
        static bool wasExceeded = false;
        bool exceeded = (m_currentDrawdown > m_maxDrawdownPercent);
        if(exceeded && !wasExceeded)
        {
            Print("WARNING: Maximum drawdown exceeded! Current: ",
                  DoubleToString(m_currentDrawdown, 2), "% Max: ", m_maxDrawdownPercent, "%");
        }
        wasExceeded = exceeded;
    }

    //+------------------------------------------------------------------+
    //| Check if Drawdown is Acceptable                                 |
    //+------------------------------------------------------------------+
    bool IsDrawdownAcceptable()
    {
        return (m_currentDrawdown < m_maxDrawdownPercent);
    }

    //+------------------------------------------------------------------+
    //| Get Current Drawdown                                            |
    //+------------------------------------------------------------------+
    double GetCurrentDrawdown()
    {
        return m_currentDrawdown;
    }

    //+------------------------------------------------------------------+
    //| Calculate Position Risk                                         |
    //+------------------------------------------------------------------+
    double CalculatePositionRisk(string symbol, double lotSize, double stopLossPoints)
    {
        double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
        double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);

        if(tickSize <= 0) return 0.0;
        double valuePerPoint = (tickValue / tickSize) * point;
        // FIX: same extra "* point" as CalculateLotSize (risk was shown 100x too small)
        double riskAmount = lotSize * stopLossPoints * valuePerPoint;

        return riskAmount;
    }

    //+------------------------------------------------------------------+
    //| Get Risk/Reward Ratio                                           |
    //+------------------------------------------------------------------+
    double GetRiskRewardRatio()
    {
        if(m_stopLossPoints == 0)
            return 0;

        return m_takeProfitPoints / m_stopLossPoints;
    }

    //+------------------------------------------------------------------+
    //| Check if Risk is Acceptable                                     |
    //+------------------------------------------------------------------+
    bool IsRiskAcceptable(double lotSize)
    {
        double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        double riskAmount = CalculatePositionRisk(_Symbol, lotSize, m_stopLossPoints);
        double riskPercent = (riskAmount / accountBalance) * 100.0;

        if(riskPercent > m_riskPercent * 1.5) // Allow 50% tolerance
        {
            Print("Risk too high: ", DoubleToString(riskPercent, 2), "% (Max: ", m_riskPercent, "%)");
            return false;
        }

        return true;
    }

    //+------------------------------------------------------------------+
    //| Get Account Statistics                                          |
    //+------------------------------------------------------------------+
    string GetAccountStats()
    {
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
        double profit = AccountInfoDouble(ACCOUNT_PROFIT);

        string stats = StringFormat(
            "Balance: %.2f | Equity: %.2f | Profit: %.2f | DD: %.2f%% | Free Margin: %.2f",
            balance, equity, profit, m_currentDrawdown, freeMargin
        );

        return stats;
    }
};
