//+------------------------------------------------------------------+
//|                                           SignalManager.mqh      |
//|                          Signal Detection & Management Functions |
//+------------------------------------------------------------------+
#property copyright "ICT CRT Gold Trading System"
#property strict

//+------------------------------------------------------------------+
//| Signal Structure                                                 |
//+------------------------------------------------------------------+
struct Signal
{
    datetime time;
    int      type;        // 1 = Buy, -1 = Sell, 0 = Neutral
    string   source;      // "ICT", "CRT", "Combined"
    int      strength;    // Signal strength 1-10
    double   confidence;  // Confidence level 0-100%
    string   description;
};

//+------------------------------------------------------------------+
//| Signal Manager Class                                             |
//+------------------------------------------------------------------+
class CSignalManager
{
private:
    bool        m_enableICT;
    bool        m_enableCRT;
    int         m_magicNumber;

    Signal      m_signalHistory[];
    int         m_maxHistorySize;

    // Signal weights for combination
    double      m_ictWeight;
    double      m_crtWeight;

    // Confluence requirements
    int         m_minConfluenceScore;
    bool        m_requireBothSignals;

public:
    //--- Constructor
    CSignalManager()
    {
        m_enableICT = true;
        m_enableCRT = true;
        m_magicNumber = 123456;
        m_maxHistorySize = 100;

        m_ictWeight = 0.6;
        m_crtWeight = 0.4;

        m_minConfluenceScore = 5;
        m_requireBothSignals = false;

        ArrayResize(m_signalHistory, 0);
    }

    //--- Destructor
    ~CSignalManager() {}

    //+------------------------------------------------------------------+
    //| Initialize Signal Manager                                        |
    //+------------------------------------------------------------------+
    bool Initialize(bool enableICT, bool enableCRT, int magicNumber)
    {
        m_enableICT = enableICT;
        m_enableCRT = enableCRT;
        m_magicNumber = magicNumber;

        Print("Signal Manager initialized: ICT=", m_enableICT, " CRT=", m_enableCRT);

        return true;
    }

    //+------------------------------------------------------------------+
    //| Combine ICT and CRT Signals                                     |
    //+------------------------------------------------------------------+
    int CombineSignals(int ictSignal, int crtSignal)
    {
        // If both strategies are disabled, return no signal
        if(!m_enableICT && !m_enableCRT)
            return 0;

        // If only one strategy is enabled, use that signal
        if(m_enableICT && !m_enableCRT)
            return ictSignal;

        if(m_enableCRT && !m_enableICT)
            return crtSignal;

        // Both strategies enabled - combine signals
        int finalSignal = 0;

        // Method 1: Require both signals to agree
        if(m_requireBothSignals)
        {
            if(ictSignal == 1 && crtSignal == 1)
            {
                finalSignal = 1;
                LogSignal(1, "Combined", 10, 95.0, "Both ICT and CRT bullish");
            }
            else if(ictSignal == -1 && crtSignal == -1)
            {
                finalSignal = -1;
                LogSignal(-1, "Combined", 10, 95.0, "Both ICT and CRT bearish");
            }
            else
            {
                finalSignal = 0;
                Print("Signals do not agree: ICT=", ictSignal, " CRT=", crtSignal);
            }
        }
        // Method 2: Weighted combination
        else
        {
            double weightedScore = (ictSignal * m_ictWeight) + (crtSignal * m_crtWeight);

            if(weightedScore > 0.5)
            {
                finalSignal = 1;
                double confidence = CalculateConfidence(ictSignal, crtSignal);
                LogSignal(1, "Combined", (int)(MathAbs(weightedScore) * 10),
                         confidence, "Weighted bullish signal");
            }
            else if(weightedScore < -0.5)
            {
                finalSignal = -1;
                double confidence = CalculateConfidence(ictSignal, crtSignal);
                LogSignal(-1, "Combined", (int)(MathAbs(weightedScore) * 10),
                         confidence, "Weighted bearish signal");
            }
            else
            {
                finalSignal = 0;
                Print("Weak combined signal: ", weightedScore);
            }
        }

        return finalSignal;
    }

    //+------------------------------------------------------------------+
    //| Calculate Signal Confidence                                     |
    //+------------------------------------------------------------------+
    double CalculateConfidence(int ictSignal, int crtSignal)
    {
        double confidence = 0;

        // Both signals agree strongly
        if((ictSignal == 1 && crtSignal == 1) || (ictSignal == -1 && crtSignal == -1))
        {
            confidence = 90.0;
        }
        // One strong signal, one neutral
        else if((ictSignal != 0 && crtSignal == 0) || (ictSignal == 0 && crtSignal != 0))
        {
            confidence = 60.0;
        }
        // Signals conflict
        else if((ictSignal == 1 && crtSignal == -1) || (ictSignal == -1 && crtSignal == 1))
        {
            confidence = 30.0;
        }
        // Both neutral
        else
        {
            confidence = 50.0;
        }

        return confidence;
    }

    //+------------------------------------------------------------------+
    //| Log Signal to History                                           |
    //+------------------------------------------------------------------+
    void LogSignal(int type, string source, int strength, double confidence, string description)
    {
        Signal sig;
        sig.time = TimeCurrent();
        sig.type = type;
        sig.source = source;
        sig.strength = strength;
        sig.confidence = confidence;
        sig.description = description;

        // Add to history
        int size = ArraySize(m_signalHistory);
        if(size >= m_maxHistorySize)
        {
            // Remove oldest signal
            ArrayRemove(m_signalHistory, 0, 1);
        }

        ArrayResize(m_signalHistory, ArraySize(m_signalHistory) + 1);
        m_signalHistory[ArraySize(m_signalHistory) - 1] = sig;

        Print("Signal Logged: ", source, " Type=", type, " Strength=", strength,
              " Confidence=", DoubleToString(confidence, 1), "%");
    }

    //+------------------------------------------------------------------+
    //| Get Last Signal                                                  |
    //+------------------------------------------------------------------+
    bool GetLastSignal(Signal &signal)
    {
        int size = ArraySize(m_signalHistory);
        if(size == 0)
            return false;

        signal = m_signalHistory[size - 1];
        return true;
    }

    //+------------------------------------------------------------------+
    //| Get Signal Statistics                                           |
    //+------------------------------------------------------------------+
    string GetSignalStats()
    {
        int totalSignals = ArraySize(m_signalHistory);
        int buySignals = 0;
        int sellSignals = 0;
        double avgConfidence = 0;

        for(int i = 0; i < totalSignals; i++)
        {
            if(m_signalHistory[i].type == 1)
                buySignals++;
            else if(m_signalHistory[i].type == -1)
                sellSignals++;

            avgConfidence += m_signalHistory[i].confidence;
        }

        if(totalSignals > 0)
            avgConfidence /= totalSignals;

        string stats = StringFormat(
            "Signals: %d | Buy: %d | Sell: %d | Avg Confidence: %.1f%%",
            totalSignals, buySignals, sellSignals, avgConfidence
        );

        return stats;
    }

    //+------------------------------------------------------------------+
    //| Check Signal Divergence                                         |
    //+------------------------------------------------------------------+
    bool HasSignalDivergence(int ictSignal, int crtSignal)
    {
        // Check if ICT and CRT signals are opposite
        if((ictSignal == 1 && crtSignal == -1) || (ictSignal == -1 && crtSignal == 1))
        {
            Print("WARNING: Signal divergence detected! ICT=", ictSignal, " CRT=", crtSignal);
            return true;
        }

        return false;
    }

    //+------------------------------------------------------------------+
    //| Validate Signal Timing                                          |
    //+------------------------------------------------------------------+
    bool ValidateSignalTiming()
    {
        int size = ArraySize(m_signalHistory);
        if(size < 2)
            return true;

        // Check if last signal was too recent
        Signal lastSignal = m_signalHistory[size - 1];
        datetime currentTime = TimeCurrent();

        int minTimeBetweenSignals = 300; // 5 minutes

        if((currentTime - lastSignal.time) < minTimeBetweenSignals)
        {
            Print("Signal too recent, waiting for cooldown");
            return false;
        }

        return true;
    }

    //+------------------------------------------------------------------+
    //| Filter Weak Signals                                             |
    //+------------------------------------------------------------------+
    bool FilterWeakSignals(int signal, double confidence)
    {
        double minConfidence = 60.0;

        if(signal == 0)
            return false;

        if(confidence < minConfidence)
        {
            Print("Signal filtered due to low confidence: ", confidence, "%");
            return false;
        }

        return true;
    }

    //+------------------------------------------------------------------+
    //| Set Signal Weights                                              |
    //+------------------------------------------------------------------+
    void SetSignalWeights(double ictWeight, double crtWeight)
    {
        // Normalize weights to sum to 1.0
        double total = ictWeight + crtWeight;
        if(total > 0)
        {
            m_ictWeight = ictWeight / total;
            m_crtWeight = crtWeight / total;
        }

        Print("Signal weights updated: ICT=", m_ictWeight, " CRT=", m_crtWeight);
    }

    //+------------------------------------------------------------------+
    //| Set Confluence Requirements                                     |
    //+------------------------------------------------------------------+
    void SetConfluenceRequirements(int minScore, bool requireBoth)
    {
        m_minConfluenceScore = minScore;
        m_requireBothSignals = requireBoth;

        Print("Confluence requirements: MinScore=", m_minConfluenceScore,
              " RequireBoth=", m_requireBothSignals);
    }

    //+------------------------------------------------------------------+
    //| Clear Signal History                                            |
    //+------------------------------------------------------------------+
    void ClearSignalHistory()
    {
        ArrayResize(m_signalHistory, 0);
        Print("Signal history cleared");
    }

    //+------------------------------------------------------------------+
    //| Get Recent Signals                                              |
    //+------------------------------------------------------------------+
    int GetRecentSignalCount(int type, int minutes)
    {
        int count = 0;
        datetime cutoffTime = TimeCurrent() - (minutes * 60);

        for(int i = ArraySize(m_signalHistory) - 1; i >= 0; i--)
        {
            if(m_signalHistory[i].time < cutoffTime)
                break;

            if(m_signalHistory[i].type == type)
                count++;
        }

        return count;
    }
};
