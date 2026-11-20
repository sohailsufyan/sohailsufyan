//+------------------------------------------------------------------+
//|                                              ICT_Functions.mqh   |
//|                                   Inner Circle Trader Functions  |
//+------------------------------------------------------------------+
#property copyright "ICT CRT Gold Trading System"
#property strict

//+------------------------------------------------------------------+
//| ICT Order Block Structure                                        |
//+------------------------------------------------------------------+
struct OrderBlock
{
    datetime time;
    double   high;
    double   low;
    double   open;
    double   close;
    bool     isBullish;
    bool     isValid;
    int      strength;
};

//+------------------------------------------------------------------+
//| Fair Value Gap Structure                                         |
//+------------------------------------------------------------------+
struct FairValueGap
{
    datetime time;
    double   gapHigh;
    double   gapLow;
    bool     isBullish;
    bool     isFilled;
    double   fillPercent;
};

//+------------------------------------------------------------------+
//| Liquidity Level Structure                                        |
//+------------------------------------------------------------------+
struct LiquidityLevel
{
    double   price;
    datetime time;
    int      touchCount;
    bool     isHigh;
    bool     isSwept;
};

//+------------------------------------------------------------------+
//| ICT Functions Class                                              |
//+------------------------------------------------------------------+
class CICTFunctions
{
private:
    ENUM_TIMEFRAMES m_timeframe;
    int             m_lookback;
    bool            m_useOrderBlocks;
    bool            m_useFVG;
    bool            m_useBOS;
    bool            m_useLiquidityGrab;

    OrderBlock      m_orderBlocks[];
    FairValueGap    m_fvgArray[];
    LiquidityLevel  m_liquidityLevels[];

    double          m_lastSwingHigh;
    double          m_lastSwingLow;
    datetime        m_lastSwingHighTime;
    datetime        m_lastSwingLowTime;

    int             m_marketStructure; // 1 = Bullish, -1 = Bearish, 0 = Neutral

public:
    //--- Constructor
    CICTFunctions()
    {
        m_timeframe = PERIOD_CURRENT;
        m_lookback = 100;
        m_useOrderBlocks = true;
        m_useFVG = true;
        m_useBOS = true;
        m_useLiquidityGrab = true;
        m_marketStructure = 0;
        m_lastSwingHigh = 0;
        m_lastSwingLow = 0;
    }

    //--- Destructor
    ~CICTFunctions() {}

    //+------------------------------------------------------------------+
    //| Initialize ICT Functions                                         |
    //+------------------------------------------------------------------+
    bool Initialize(ENUM_TIMEFRAMES timeframe, int lookback, bool useOB,
                    bool useFVG, bool useBOS, bool useLiq)
    {
        m_timeframe = timeframe;
        m_lookback = lookback;
        m_useOrderBlocks = useOB;
        m_useFVG = useFVG;
        m_useBOS = useBOS;
        m_useLiquidityGrab = useLiq;

        Print("ICT Functions initialized: TF=", EnumToString(m_timeframe),
              " Lookback=", m_lookback);

        return true;
    }

    //+------------------------------------------------------------------+
    //| Get ICT Signal                                                   |
    //+------------------------------------------------------------------+
    int GetSignal(string symbol)
    {
        //--- Update market analysis
        UpdateMarketStructure(symbol);

        if(m_useOrderBlocks)
            IdentifyOrderBlocks(symbol);

        if(m_useFVG)
            IdentifyFairValueGaps(symbol);

        if(m_useLiquidityGrab)
            IdentifyLiquidityLevels(symbol);

        //--- Analyze confluence
        int signal = AnalyzeConfluence(symbol);

        return signal;
    }

    //+------------------------------------------------------------------+
    //| Update Market Structure                                          |
    //+------------------------------------------------------------------+
    void UpdateMarketStructure(string symbol)
    {
        double currentHigh = 0, currentLow = DBL_MAX;
        int highBar = 0, lowBar = 0;

        //--- Find recent swing high and low
        for(int i = 5; i < m_lookback; i++)
        {
            double high = iHigh(symbol, m_timeframe, i);
            double low = iLow(symbol, m_timeframe, i);

            //--- Check for swing high
            if(IsSwingHigh(symbol, i) && high > currentHigh)
            {
                currentHigh = high;
                highBar = i;
            }

            //--- Check for swing low
            if(IsSwingLow(symbol, i) && low < currentLow)
            {
                currentLow = low;
                lowBar = i;
            }
        }

        //--- Update swing levels
        if(currentHigh > 0 && currentHigh != m_lastSwingHigh)
        {
            m_lastSwingHigh = currentHigh;
            m_lastSwingHighTime = iTime(symbol, m_timeframe, highBar);
        }

        if(currentLow < DBL_MAX && currentLow != m_lastSwingLow)
        {
            m_lastSwingLow = currentLow;
            m_lastSwingLowTime = iTime(symbol, m_timeframe, lowBar);
        }

        //--- Determine market structure
        double currentPrice = iClose(symbol, m_timeframe, 0);

        if(m_useBOS)
        {
            //--- Check for Break of Structure
            if(currentPrice > m_lastSwingHigh)
            {
                m_marketStructure = 1; // Bullish BOS
                Print("Bullish Break of Structure detected at ", currentPrice);
            }
            else if(currentPrice < m_lastSwingLow)
            {
                m_marketStructure = -1; // Bearish BOS
                Print("Bearish Break of Structure detected at ", currentPrice);
            }
        }
    }

    //+------------------------------------------------------------------+
    //| Check if bar is swing high                                      |
    //+------------------------------------------------------------------+
    bool IsSwingHigh(string symbol, int bar)
    {
        if(bar < 2) return false;

        double centerHigh = iHigh(symbol, m_timeframe, bar);

        for(int i = 1; i <= 2; i++)
        {
            if(iHigh(symbol, m_timeframe, bar - i) >= centerHigh ||
               iHigh(symbol, m_timeframe, bar + i) >= centerHigh)
                return false;
        }

        return true;
    }

    //+------------------------------------------------------------------+
    //| Check if bar is swing low                                       |
    //+------------------------------------------------------------------+
    bool IsSwingLow(string symbol, int bar)
    {
        if(bar < 2) return false;

        double centerLow = iLow(symbol, m_timeframe, bar);

        for(int i = 1; i <= 2; i++)
        {
            if(iLow(symbol, m_timeframe, bar - i) <= centerLow ||
               iLow(symbol, m_timeframe, bar + i) <= centerLow)
                return false;
        }

        return true;
    }

    //+------------------------------------------------------------------+
    //| Identify Order Blocks                                           |
    //+------------------------------------------------------------------+
    void IdentifyOrderBlocks(string symbol)
    {
        ArrayResize(m_orderBlocks, 0);

        for(int i = 1; i < m_lookback - 1; i++)
        {
            double open = iOpen(symbol, m_timeframe, i);
            double close = iClose(symbol, m_timeframe, i);
            double high = iHigh(symbol, m_timeframe, i);
            double low = iLow(symbol, m_timeframe, i);

            double nextOpen = iOpen(symbol, m_timeframe, i - 1);
            double nextClose = iClose(symbol, m_timeframe, i - 1);

            //--- Bullish Order Block
            if(close < open && nextClose > nextOpen)
            {
                double moveSize = nextClose - nextOpen;
                if(moveSize > (open - close) * 2)
                {
                    OrderBlock ob;
                    ob.time = iTime(symbol, m_timeframe, i);
                    ob.high = high;
                    ob.low = low;
                    ob.open = open;
                    ob.close = close;
                    ob.isBullish = true;
                    ob.isValid = true;
                    ob.strength = (int)((moveSize / _Point) / 10);

                    ArrayResize(m_orderBlocks, ArraySize(m_orderBlocks) + 1);
                    m_orderBlocks[ArraySize(m_orderBlocks) - 1] = ob;
                }
            }

            //--- Bearish Order Block
            if(close > open && nextClose < nextOpen)
            {
                double moveSize = nextOpen - nextClose;
                if(moveSize > (close - open) * 2)
                {
                    OrderBlock ob;
                    ob.time = iTime(symbol, m_timeframe, i);
                    ob.high = high;
                    ob.low = low;
                    ob.open = open;
                    ob.close = close;
                    ob.isBullish = false;
                    ob.isValid = true;
                    ob.strength = (int)((moveSize / _Point) / 10);

                    ArrayResize(m_orderBlocks, ArraySize(m_orderBlocks) + 1);
                    m_orderBlocks[ArraySize(m_orderBlocks) - 1] = ob;
                }
            }
        }

        Print("Identified ", ArraySize(m_orderBlocks), " order blocks");
    }

    //+------------------------------------------------------------------+
    //| Identify Fair Value Gaps                                        |
    //+------------------------------------------------------------------+
    void IdentifyFairValueGaps(string symbol)
    {
        ArrayResize(m_fvgArray, 0);

        for(int i = 1; i < m_lookback - 1; i++)
        {
            double prevHigh = iHigh(symbol, m_timeframe, i + 1);
            double prevLow = iLow(symbol, m_timeframe, i + 1);
            double currentHigh = iHigh(symbol, m_timeframe, i);
            double currentLow = iLow(symbol, m_timeframe, i);
            double nextHigh = iHigh(symbol, m_timeframe, i - 1);
            double nextLow = iLow(symbol, m_timeframe, i - 1);

            //--- Bullish FVG (gap between previous high and next low)
            if(nextLow > prevHigh)
            {
                FairValueGap fvg;
                fvg.time = iTime(symbol, m_timeframe, i);
                fvg.gapLow = prevHigh;
                fvg.gapHigh = nextLow;
                fvg.isBullish = true;
                fvg.isFilled = false;
                fvg.fillPercent = 0;

                ArrayResize(m_fvgArray, ArraySize(m_fvgArray) + 1);
                m_fvgArray[ArraySize(m_fvgArray) - 1] = fvg;
            }

            //--- Bearish FVG (gap between previous low and next high)
            if(nextHigh < prevLow)
            {
                FairValueGap fvg;
                fvg.time = iTime(symbol, m_timeframe, i);
                fvg.gapHigh = prevLow;
                fvg.gapLow = nextHigh;
                fvg.isBullish = false;
                fvg.isFilled = false;
                fvg.fillPercent = 0;

                ArrayResize(m_fvgArray, ArraySize(m_fvgArray) + 1);
                m_fvgArray[ArraySize(m_fvgArray) - 1] = fvg;
            }
        }

        //--- Check if FVGs are filled
        double currentPrice = iClose(symbol, m_timeframe, 0);
        for(int i = 0; i < ArraySize(m_fvgArray); i++)
        {
            if(currentPrice >= m_fvgArray[i].gapLow && currentPrice <= m_fvgArray[i].gapHigh)
            {
                double gapSize = m_fvgArray[i].gapHigh - m_fvgArray[i].gapLow;
                double filled = currentPrice - m_fvgArray[i].gapLow;
                m_fvgArray[i].fillPercent = (filled / gapSize) * 100;

                if(m_fvgArray[i].fillPercent > 50)
                    m_fvgArray[i].isFilled = true;
            }
        }

        Print("Identified ", ArraySize(m_fvgArray), " Fair Value Gaps");
    }

    //+------------------------------------------------------------------+
    //| Identify Liquidity Levels                                       |
    //+------------------------------------------------------------------+
    void IdentifyLiquidityLevels(string symbol)
    {
        ArrayResize(m_liquidityLevels, 0);

        //--- Find equal highs and lows
        for(int i = 5; i < m_lookback - 5; i++)
        {
            if(IsSwingHigh(symbol, i))
            {
                double high = iHigh(symbol, m_timeframe, i);

                //--- Check for equal highs within tolerance
                for(int j = i + 5; j < m_lookback; j++)
                {
                    if(IsSwingHigh(symbol, j))
                    {
                        double high2 = iHigh(symbol, m_timeframe, j);
                        double diff = MathAbs(high - high2);
                        double tolerance = 50 * _Point;

                        if(diff < tolerance)
                        {
                            LiquidityLevel liq;
                            liq.price = high;
                            liq.time = iTime(symbol, m_timeframe, i);
                            liq.touchCount = 2;
                            liq.isHigh = true;
                            liq.isSwept = false;

                            ArrayResize(m_liquidityLevels, ArraySize(m_liquidityLevels) + 1);
                            m_liquidityLevels[ArraySize(m_liquidityLevels) - 1] = liq;
                            break;
                        }
                    }
                }
            }

            if(IsSwingLow(symbol, i))
            {
                double low = iLow(symbol, m_timeframe, i);

                //--- Check for equal lows within tolerance
                for(int j = i + 5; j < m_lookback; j++)
                {
                    if(IsSwingLow(symbol, j))
                    {
                        double low2 = iLow(symbol, m_timeframe, j);
                        double diff = MathAbs(low - low2);
                        double tolerance = 50 * _Point;

                        if(diff < tolerance)
                        {
                            LiquidityLevel liq;
                            liq.price = low;
                            liq.time = iTime(symbol, m_timeframe, i);
                            liq.touchCount = 2;
                            liq.isHigh = false;
                            liq.isSwept = false;

                            ArrayResize(m_liquidityLevels, ArraySize(m_liquidityLevels) + 1);
                            m_liquidityLevels[ArraySize(m_liquidityLevels) - 1] = liq;
                            break;
                        }
                    }
                }
            }
        }

        Print("Identified ", ArraySize(m_liquidityLevels), " liquidity levels");
    }

    //+------------------------------------------------------------------+
    //| Analyze Confluence                                               |
    //+------------------------------------------------------------------+
    int AnalyzeConfluence(string symbol)
    {
        int bullishScore = 0;
        int bearishScore = 0;

        double currentPrice = iClose(symbol, m_timeframe, 0);

        //--- Market structure bias
        if(m_marketStructure == 1)
            bullishScore += 3;
        else if(m_marketStructure == -1)
            bearishScore += 3;

        //--- Order block confluence
        for(int i = 0; i < ArraySize(m_orderBlocks); i++)
        {
            if(!m_orderBlocks[i].isValid) continue;

            if(m_orderBlocks[i].isBullish)
            {
                if(currentPrice >= m_orderBlocks[i].low && currentPrice <= m_orderBlocks[i].high)
                    bullishScore += 2;
            }
            else
            {
                if(currentPrice >= m_orderBlocks[i].low && currentPrice <= m_orderBlocks[i].high)
                    bearishScore += 2;
            }
        }

        //--- FVG confluence
        for(int i = 0; i < ArraySize(m_fvgArray); i++)
        {
            if(m_fvgArray[i].isFilled) continue;

            if(m_fvgArray[i].isBullish)
            {
                if(currentPrice >= m_fvgArray[i].gapLow && currentPrice <= m_fvgArray[i].gapHigh)
                    bullishScore += 2;
            }
            else
            {
                if(currentPrice >= m_fvgArray[i].gapLow && currentPrice <= m_fvgArray[i].gapHigh)
                    bearishScore += 2;
            }
        }

        //--- Liquidity grab confluence
        for(int i = 0; i < ArraySize(m_liquidityLevels); i++)
        {
            if(m_liquidityLevels[i].isSwept) continue;

            double diff = MathAbs(currentPrice - m_liquidityLevels[i].price);
            double threshold = 100 * _Point;

            if(diff < threshold)
            {
                if(m_liquidityLevels[i].isHigh)
                    bearishScore += 1; // Expect reversal after sweep
                else
                    bullishScore += 1;
            }
        }

        //--- Determine final signal
        int threshold = 4;

        if(bullishScore >= threshold && bullishScore > bearishScore)
        {
            Print("ICT Bullish Signal: Score=", bullishScore);
            return 1;
        }
        else if(bearishScore >= threshold && bearishScore > bullishScore)
        {
            Print("ICT Bearish Signal: Score=", bearishScore);
            return -1;
        }

        return 0;
    }

    //+------------------------------------------------------------------+
    //| Get Market Structure                                             |
    //+------------------------------------------------------------------+
    int GetMarketStructure() { return m_marketStructure; }

    //+------------------------------------------------------------------+
    //| Get Last Swing High                                             |
    //+------------------------------------------------------------------+
    double GetLastSwingHigh() { return m_lastSwingHigh; }

    //+------------------------------------------------------------------+
    //| Get Last Swing Low                                              |
    //+------------------------------------------------------------------+
    double GetLastSwingLow() { return m_lastSwingLow; }
};
