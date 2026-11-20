//+------------------------------------------------------------------+
//|                                              CRT_Functions.mqh   |
//|                              Concept Refined Trading Functions   |
//+------------------------------------------------------------------+
#property copyright "ICT CRT Gold Trading System"
#property strict

//+------------------------------------------------------------------+
//| Supply/Demand Zone Structure                                     |
//+------------------------------------------------------------------+
struct SupplyDemandZone
{
    datetime timeStart;
    datetime timeEnd;
    double   zoneHigh;
    double   zoneLow;
    bool     isSupply;
    int      touchCount;
    bool     isFresh;
    int      strength;
};

//+------------------------------------------------------------------+
//| Trendline Structure                                              |
//+------------------------------------------------------------------+
struct Trendline
{
    datetime point1Time;
    datetime point2Time;
    double   point1Price;
    double   point2Price;
    bool     isBullish;
    int      touchCount;
    bool     isBroken;
};

//+------------------------------------------------------------------+
//| Volume Profile Structure                                         |
//+------------------------------------------------------------------+
struct VolumeProfile
{
    double   priceLevel;
    long     volume;
    bool     isPOC; // Point of Control
    bool     isHVN; // High Volume Node
    bool     isLVN; // Low Volume Node
};

//+------------------------------------------------------------------+
//| CRT Functions Class                                              |
//+------------------------------------------------------------------+
class CCRTFunctions
{
private:
    ENUM_TIMEFRAMES     m_timeframe;
    int                 m_lookback;
    bool                m_useSupplyDemand;
    bool                m_useTrendline;
    bool                m_useVolumeProfile;

    SupplyDemandZone    m_sdZones[];
    Trendline           m_trendlines[];
    VolumeProfile       m_volumeProfile[];

    int                 m_trend; // 1 = Uptrend, -1 = Downtrend, 0 = Sideways

public:
    //--- Constructor
    CCRTFunctions()
    {
        m_timeframe = PERIOD_CURRENT;
        m_lookback = 200;
        m_useSupplyDemand = true;
        m_useTrendline = true;
        m_useVolumeProfile = true;
        m_trend = 0;
    }

    //--- Destructor
    ~CCRTFunctions() {}

    //+------------------------------------------------------------------+
    //| Initialize CRT Functions                                         |
    //+------------------------------------------------------------------+
    bool Initialize(ENUM_TIMEFRAMES timeframe, int lookback, bool useSD,
                    bool useTrendline, bool useVolume)
    {
        m_timeframe = timeframe;
        m_lookback = lookback;
        m_useSupplyDemand = useSD;
        m_useTrendline = useTrendline;
        m_useVolumeProfile = useVolume;

        Print("CRT Functions initialized: TF=", EnumToString(m_timeframe),
              " Lookback=", m_lookback);

        return true;
    }

    //+------------------------------------------------------------------+
    //| Get CRT Signal                                                   |
    //+------------------------------------------------------------------+
    int GetSignal(string symbol)
    {
        //--- Update market analysis
        DetermineTrend(symbol);

        if(m_useSupplyDemand)
            IdentifySupplyDemandZones(symbol);

        if(m_useTrendline)
            IdentifyTrendlines(symbol);

        if(m_useVolumeProfile)
            AnalyzeVolumeProfile(symbol);

        //--- Analyze confluence
        int signal = AnalyzeConfluence(symbol);

        return signal;
    }

    //+------------------------------------------------------------------+
    //| Determine Trend                                                  |
    //+------------------------------------------------------------------+
    void DetermineTrend(string symbol)
    {
        //--- Use moving averages for trend determination
        int ma20Period = 20;
        int ma50Period = 50;
        int ma200Period = 200;

        double ma20 = CalculateMA(symbol, m_timeframe, ma20Period, 0);
        double ma50 = CalculateMA(symbol, m_timeframe, ma50Period, 0);
        double ma200 = CalculateMA(symbol, m_timeframe, ma200Period, 0);
        double currentPrice = iClose(symbol, m_timeframe, 0);

        //--- Determine trend based on MA alignment
        if(ma20 > ma50 && ma50 > ma200 && currentPrice > ma20)
        {
            m_trend = 1; // Strong uptrend
        }
        else if(ma20 < ma50 && ma50 < ma200 && currentPrice < ma20)
        {
            m_trend = -1; // Strong downtrend
        }
        else
        {
            m_trend = 0; // Sideways or weak trend
        }

        //--- Additional trend confirmation with Higher Highs/Lower Lows
        bool hasHigherHighs = CheckHigherHighs(symbol);
        bool hasLowerLows = CheckLowerLows(symbol);

        if(hasHigherHighs && m_trend >= 0)
            m_trend = 1;
        else if(hasLowerLows && m_trend <= 0)
            m_trend = -1;
    }

    //+------------------------------------------------------------------+
    //| Calculate Moving Average                                         |
    //+------------------------------------------------------------------+
    double CalculateMA(string symbol, ENUM_TIMEFRAMES tf, int period, int shift)
    {
        double sum = 0;
        for(int i = shift; i < shift + period; i++)
        {
            sum += iClose(symbol, tf, i);
        }
        return sum / period;
    }

    //+------------------------------------------------------------------+
    //| Check for Higher Highs                                          |
    //+------------------------------------------------------------------+
    bool CheckHigherHighs(string symbol)
    {
        int swingCount = 0;
        double lastHigh = 0;

        for(int i = 5; i < m_lookback && swingCount < 3; i++)
        {
            if(IsSwingHigh(symbol, i))
            {
                double currentHigh = iHigh(symbol, m_timeframe, i);
                if(lastHigh > 0)
                {
                    if(currentHigh <= lastHigh)
                        return false;
                }
                lastHigh = currentHigh;
                swingCount++;
            }
        }

        return (swingCount >= 2);
    }

    //+------------------------------------------------------------------+
    //| Check for Lower Lows                                            |
    //+------------------------------------------------------------------+
    bool CheckLowerLows(string symbol)
    {
        int swingCount = 0;
        double lastLow = DBL_MAX;

        for(int i = 5; i < m_lookback && swingCount < 3; i++)
        {
            if(IsSwingLow(symbol, i))
            {
                double currentLow = iLow(symbol, m_timeframe, i);
                if(lastLow < DBL_MAX)
                {
                    if(currentLow >= lastLow)
                        return false;
                }
                lastLow = currentLow;
                swingCount++;
            }
        }

        return (swingCount >= 2);
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
    //| Identify Supply/Demand Zones                                    |
    //+------------------------------------------------------------------+
    void IdentifySupplyDemandZones(string symbol)
    {
        ArrayResize(m_sdZones, 0);

        for(int i = 3; i < m_lookback - 3; i++)
        {
            //--- Look for demand zones (strong bullish moves from consolidation)
            bool isConsolidation = CheckConsolidation(symbol, i, 5);

            if(isConsolidation)
            {
                double moveAfter = iClose(symbol, m_timeframe, i - 3) - iClose(symbol, m_timeframe, i);

                //--- Demand zone (bullish move after consolidation)
                if(moveAfter > 0)
                {
                    double avgRange = 0;
                    for(int j = i; j < i + 5; j++)
                    {
                        avgRange += iHigh(symbol, m_timeframe, j) - iLow(symbol, m_timeframe, j);
                    }
                    avgRange /= 5;

                    if(moveAfter > avgRange * 3)
                    {
                        SupplyDemandZone zone;
                        zone.timeStart = iTime(symbol, m_timeframe, i + 4);
                        zone.timeEnd = iTime(symbol, m_timeframe, i);
                        zone.zoneHigh = iHigh(symbol, m_timeframe, iHighest(symbol, m_timeframe, MODE_HIGH, 5, i));
                        zone.zoneLow = iLow(symbol, m_timeframe, iLowest(symbol, m_timeframe, MODE_LOW, 5, i));
                        zone.isSupply = false;
                        zone.touchCount = 0;
                        zone.isFresh = true;
                        zone.strength = (int)((moveAfter / _Point) / 100);

                        ArrayResize(m_sdZones, ArraySize(m_sdZones) + 1);
                        m_sdZones[ArraySize(m_sdZones) - 1] = zone;
                    }
                }

                //--- Supply zone (bearish move after consolidation)
                if(moveAfter < 0)
                {
                    double avgRange = 0;
                    for(int j = i; j < i + 5; j++)
                    {
                        avgRange += iHigh(symbol, m_timeframe, j) - iLow(symbol, m_timeframe, j);
                    }
                    avgRange /= 5;

                    if(MathAbs(moveAfter) > avgRange * 3)
                    {
                        SupplyDemandZone zone;
                        zone.timeStart = iTime(symbol, m_timeframe, i + 4);
                        zone.timeEnd = iTime(symbol, m_timeframe, i);
                        zone.zoneHigh = iHigh(symbol, m_timeframe, iHighest(symbol, m_timeframe, MODE_HIGH, 5, i));
                        zone.zoneLow = iLow(symbol, m_timeframe, iLowest(symbol, m_timeframe, MODE_LOW, 5, i));
                        zone.isSupply = true;
                        zone.touchCount = 0;
                        zone.isFresh = true;
                        zone.strength = (int)((MathAbs(moveAfter) / _Point) / 100);

                        ArrayResize(m_sdZones, ArraySize(m_sdZones) + 1);
                        m_sdZones[ArraySize(m_sdZones) - 1] = zone;
                    }
                }
            }
        }

        //--- Update zone status
        double currentPrice = iClose(symbol, m_timeframe, 0);
        for(int i = 0; i < ArraySize(m_sdZones); i++)
        {
            if(currentPrice >= m_sdZones[i].zoneLow && currentPrice <= m_sdZones[i].zoneHigh)
            {
                m_sdZones[i].touchCount++;
                if(m_sdZones[i].touchCount > 1)
                    m_sdZones[i].isFresh = false;
            }
        }

        Print("Identified ", ArraySize(m_sdZones), " Supply/Demand zones");
    }

    //+------------------------------------------------------------------+
    //| Check for Consolidation                                         |
    //+------------------------------------------------------------------+
    bool CheckConsolidation(string symbol, int startBar, int period)
    {
        double highest = iHigh(symbol, m_timeframe, iHighest(symbol, m_timeframe, MODE_HIGH, period, startBar));
        double lowest = iLow(symbol, m_timeframe, iLowest(symbol, m_timeframe, MODE_LOW, period, startBar));
        double range = highest - lowest;

        double avgRange = 0;
        for(int i = 0; i < period; i++)
        {
            avgRange += iHigh(symbol, m_timeframe, startBar + i) - iLow(symbol, m_timeframe, startBar + i);
        }
        avgRange /= period;

        return (range < avgRange * 2);
    }

    //+------------------------------------------------------------------+
    //| Identify Trendlines                                             |
    //+------------------------------------------------------------------+
    void IdentifyTrendlines(string symbol)
    {
        ArrayResize(m_trendlines, 0);

        //--- Find swing points for trendlines
        double swingHighs[];
        datetime swingHighTimes[];
        double swingLows[];
        datetime swingLowTimes[];

        ArrayResize(swingHighs, 0);
        ArrayResize(swingHighTimes, 0);
        ArrayResize(swingLows, 0);
        ArrayResize(swingLowTimes, 0);

        for(int i = 5; i < m_lookback; i++)
        {
            if(IsSwingHigh(symbol, i))
            {
                ArrayResize(swingHighs, ArraySize(swingHighs) + 1);
                ArrayResize(swingHighTimes, ArraySize(swingHighTimes) + 1);
                swingHighs[ArraySize(swingHighs) - 1] = iHigh(symbol, m_timeframe, i);
                swingHighTimes[ArraySize(swingHighTimes) - 1] = iTime(symbol, m_timeframe, i);
            }

            if(IsSwingLow(symbol, i))
            {
                ArrayResize(swingLows, ArraySize(swingLows) + 1);
                ArrayResize(swingLowTimes, ArraySize(swingLowTimes) + 1);
                swingLows[ArraySize(swingLows) - 1] = iLow(symbol, m_timeframe, i);
                swingLowTimes[ArraySize(swingLowTimes) - 1] = iTime(symbol, m_timeframe, i);
            }
        }

        //--- Create support trendlines (from swing lows)
        for(int i = 0; i < ArraySize(swingLows) - 1; i++)
        {
            Trendline tl;
            tl.point1Price = swingLows[i + 1];
            tl.point1Time = swingLowTimes[i + 1];
            tl.point2Price = swingLows[i];
            tl.point2Time = swingLowTimes[i];
            tl.isBullish = true;
            tl.touchCount = 2;
            tl.isBroken = false;

            ArrayResize(m_trendlines, ArraySize(m_trendlines) + 1);
            m_trendlines[ArraySize(m_trendlines) - 1] = tl;
        }

        //--- Create resistance trendlines (from swing highs)
        for(int i = 0; i < ArraySize(swingHighs) - 1; i++)
        {
            Trendline tl;
            tl.point1Price = swingHighs[i + 1];
            tl.point1Time = swingHighTimes[i + 1];
            tl.point2Price = swingHighs[i];
            tl.point2Time = swingHighTimes[i];
            tl.isBullish = false;
            tl.touchCount = 2;
            tl.isBroken = false;

            ArrayResize(m_trendlines, ArraySize(m_trendlines) + 1);
            m_trendlines[ArraySize(m_trendlines) - 1] = tl;
        }

        Print("Identified ", ArraySize(m_trendlines), " trendlines");
    }

    //+------------------------------------------------------------------+
    //| Analyze Volume Profile                                          |
    //+------------------------------------------------------------------+
    void AnalyzeVolumeProfile(string symbol)
    {
        ArrayResize(m_volumeProfile, 0);

        //--- Calculate price levels and volumes
        double highest = iHigh(symbol, m_timeframe, iHighest(symbol, m_timeframe, MODE_HIGH, m_lookback, 0));
        double lowest = iLow(symbol, m_timeframe, iLowest(symbol, m_timeframe, MODE_LOW, m_lookback, 0));

        int levels = 50;
        double priceStep = (highest - lowest) / levels;

        for(int i = 0; i < levels; i++)
        {
            VolumeProfile vp;
            vp.priceLevel = lowest + (i * priceStep);
            vp.volume = 0;
            vp.isPOC = false;
            vp.isHVN = false;
            vp.isLVN = false;

            //--- Calculate volume at this price level
            for(int j = 0; j < m_lookback; j++)
            {
                double barHigh = iHigh(symbol, m_timeframe, j);
                double barLow = iLow(symbol, m_timeframe, j);

                if(vp.priceLevel >= barLow && vp.priceLevel <= barHigh)
                {
                    vp.volume += iVolume(symbol, m_timeframe, j);
                }
            }

            ArrayResize(m_volumeProfile, ArraySize(m_volumeProfile) + 1);
            m_volumeProfile[ArraySize(m_volumeProfile) - 1] = vp;
        }

        //--- Find POC (Point of Control - highest volume)
        long maxVolume = 0;
        int pocIndex = 0;
        for(int i = 0; i < ArraySize(m_volumeProfile); i++)
        {
            if(m_volumeProfile[i].volume > maxVolume)
            {
                maxVolume = m_volumeProfile[i].volume;
                pocIndex = i;
            }
        }
        m_volumeProfile[pocIndex].isPOC = true;

        //--- Mark HVN and LVN
        long avgVolume = 0;
        for(int i = 0; i < ArraySize(m_volumeProfile); i++)
        {
            avgVolume += m_volumeProfile[i].volume;
        }
        avgVolume /= ArraySize(m_volumeProfile);

        for(int i = 0; i < ArraySize(m_volumeProfile); i++)
        {
            if(m_volumeProfile[i].volume > avgVolume * 1.5)
                m_volumeProfile[i].isHVN = true;
            else if(m_volumeProfile[i].volume < avgVolume * 0.5)
                m_volumeProfile[i].isLVN = true;
        }
    }

    //+------------------------------------------------------------------+
    //| Analyze Confluence                                               |
    //+------------------------------------------------------------------+
    int AnalyzeConfluence(string symbol)
    {
        int bullishScore = 0;
        int bearishScore = 0;

        double currentPrice = iClose(symbol, m_timeframe, 0);

        //--- Trend bias
        if(m_trend == 1)
            bullishScore += 3;
        else if(m_trend == -1)
            bearishScore += 3;

        //--- Supply/Demand confluence
        for(int i = 0; i < ArraySize(m_sdZones); i++)
        {
            if(!m_sdZones[i].isFresh) continue;

            if(currentPrice >= m_sdZones[i].zoneLow && currentPrice <= m_sdZones[i].zoneHigh)
            {
                if(!m_sdZones[i].isSupply)
                    bullishScore += 2;
                else
                    bearishScore += 2;
            }
        }

        //--- Trendline confluence
        for(int i = 0; i < ArraySize(m_trendlines); i++)
        {
            if(m_trendlines[i].isBroken) continue;

            double trendlinePrice = CalculateTrendlinePrice(m_trendlines[i], iTime(symbol, m_timeframe, 0));
            double diff = MathAbs(currentPrice - trendlinePrice);
            double threshold = 50 * _Point;

            if(diff < threshold)
            {
                if(m_trendlines[i].isBullish)
                    bullishScore += 1;
                else
                    bearishScore += 1;
            }
        }

        //--- Volume profile confluence
        for(int i = 0; i < ArraySize(m_volumeProfile); i++)
        {
            double diff = MathAbs(currentPrice - m_volumeProfile[i].priceLevel);
            double threshold = 20 * _Point;

            if(diff < threshold)
            {
                if(m_volumeProfile[i].isPOC || m_volumeProfile[i].isHVN)
                    bullishScore += 1; // HVN acts as support/resistance
            }
        }

        //--- Determine final signal
        int threshold = 4;

        if(bullishScore >= threshold && bullishScore > bearishScore)
        {
            Print("CRT Bullish Signal: Score=", bullishScore);
            return 1;
        }
        else if(bearishScore >= threshold && bearishScore > bullishScore)
        {
            Print("CRT Bearish Signal: Score=", bearishScore);
            return -1;
        }

        return 0;
    }

    //+------------------------------------------------------------------+
    //| Calculate Trendline Price                                       |
    //+------------------------------------------------------------------+
    double CalculateTrendlinePrice(Trendline &tl, datetime currentTime)
    {
        double timeDiff = (double)(tl.point2Time - tl.point1Time);
        double priceDiff = tl.point2Price - tl.point1Price;
        double slope = priceDiff / timeDiff;

        double timeFromPoint2 = (double)(currentTime - tl.point2Time);
        double priceAtTime = tl.point2Price + (slope * timeFromPoint2);

        return priceAtTime;
    }

    //+------------------------------------------------------------------+
    //| Get Trend                                                        |
    //+------------------------------------------------------------------+
    int GetTrend() { return m_trend; }
};
