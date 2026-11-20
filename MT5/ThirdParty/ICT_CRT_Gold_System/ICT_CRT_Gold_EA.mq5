//+------------------------------------------------------------------+
//|                                             ICT_CRT_Gold_EA.mq5 |
//|                                  ICT & CRT Combined Trading System |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "ICT CRT Gold Trading System"
#property link      ""
#property version   "1.02"
#property strict

/*
   v1.02
   - Only this EA's own positions (magic) block a new trade.
   - Max-drawdown peak balance survives EA restarts (was reset on every restart).

   v1.01 - Bug fixes
   - Auto lot was 100x (2-digit gold) / 1000x (3-digit gold) too big (RiskManagement.mqh).
   - Lot is never rounded up to the broker minimum (trade skipped instead).
   - OnDeinit used notificationManager after deleting it (invalid pointer access).
   - NotificationManager called its own method instead of MT5's SendNotification().
   - Trailing stop and drawdown check run on every tick and outside trading hours
     (they ran once per bar and only inside trading hours / below max drawdown).
   - Orders use a filling mode the symbol supports (was the default FOK).
*/

#include "Include/ICT_Functions.mqh"
#include "Include/CRT_Functions.mqh"
#include "Include/RiskManagement.mqh"
#include "Include/SignalManager.mqh"
#include "Include/NotificationManager.mqh"

//--- Input Parameters
input group "=== TRADING PARAMETERS ==="
input bool     EnableICT = true;                    // Enable ICT Strategy
input bool     EnableCRT = true;                    // Enable CRT Strategy
input double   LotSize = 0.01;                      // Lot Size
input bool     UseAutoLot = true;                   // Use Automatic Lot Sizing
input double   RiskPercent = 2.0;                   // Risk Percentage per Trade
input int      MaxDailyTrades = 5;                  // Maximum Daily Trades
input int      MagicNumber = 123456;                // Magic Number

input group "=== ICT SETTINGS ==="
input ENUM_TIMEFRAMES ICT_Timeframe = PERIOD_H1;    // ICT Analysis Timeframe
input bool     UseOrderBlocks = true;               // Use Order Blocks
input bool     UseFVG = true;                       // Use Fair Value Gaps
input bool     UseBreakOfStructure = true;          // Use Break of Structure
input bool     UseLiquidityGrab = true;             // Use Liquidity Grab
input int      ICT_LookbackBars = 100;              // ICT Lookback Period

input group "=== CRT SETTINGS ==="
input ENUM_TIMEFRAMES CRT_Timeframe = PERIOD_M15;   // CRT Analysis Timeframe
input bool     UseSupplyDemand = true;              // Use Supply/Demand Zones
input bool     UseTrendline = true;                 // Use Trendline Breaks
input bool     UseVolumeProfile = true;             // Use Volume Profile
input int      CRT_LookbackBars = 200;              // CRT Lookback Period

input group "=== RISK MANAGEMENT ==="
input double   StopLossPoints = 500;                // Stop Loss (Points)
input double   TakeProfitPoints = 1000;             // Take Profit (Points)
input bool     UseTrailingStop = true;              // Use Trailing Stop
input double   TrailingStopPoints = 300;            // Trailing Stop (Points)
input double   MaxDrawdownPercent = 10.0;           // Max Drawdown %

input group "=== TIME FILTERS ==="
input bool     UseTradingHours = true;              // Use Trading Hours Filter
input int      StartHour = 8;                       // Start Hour (Broker Time)
input int      EndHour = 20;                        // End Hour (Broker Time)
input bool     TradeMonday = true;                  // Trade on Monday
input bool     TradeTuesday = true;                 // Trade on Tuesday
input bool     TradeWednesday = true;               // Trade on Wednesday
input bool     TradeThursday = true;                // Trade on Thursday
input bool     TradeFriday = true;                  // Trade on Friday

input group "=== NOTIFICATIONS ==="
input bool     EnableEmailAlerts = false;           // Enable Email Alerts
input bool     EnablePushNotifications = true;      // Enable Push Notifications
input bool     EnableSoundAlerts = true;            // Enable Sound Alerts

//--- Global Variables
CICTFunctions      *ictFunctions;
CCRTFunctions      *crtFunctions;
CRiskManagement    *riskManager;
CSignalManager     *signalManager;
CNotificationManager *notificationManager;

int dailyTradeCount = 0;
datetime lastTradeDate = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("Initializing ICT CRT Gold Trading System...");

    //--- Initialize classes
    ictFunctions = new CICTFunctions();
    crtFunctions = new CCRTFunctions();
    riskManager = new CRiskManagement();
    signalManager = new CSignalManager();
    notificationManager = new CNotificationManager();

    //--- Configure ICT
    if(!ictFunctions.Initialize(ICT_Timeframe, ICT_LookbackBars, UseOrderBlocks,
                                 UseFVG, UseBreakOfStructure, UseLiquidityGrab))
    {
        Print("Failed to initialize ICT Functions");
        return(INIT_FAILED);
    }

    //--- Configure CRT
    if(!crtFunctions.Initialize(CRT_Timeframe, CRT_LookbackBars, UseSupplyDemand,
                                UseTrendline, UseVolumeProfile))
    {
        Print("Failed to initialize CRT Functions");
        return(INIT_FAILED);
    }

    //--- Configure Risk Management
    riskManager.SetRiskParameters(RiskPercent, MaxDrawdownPercent, UseAutoLot, LotSize);
    riskManager.SetStopLoss(StopLossPoints);
    riskManager.SetTakeProfit(TakeProfitPoints);
    riskManager.SetTrailingStop(UseTrailingStop, TrailingStopPoints);

    //--- Configure Signal Manager
    signalManager.Initialize(EnableICT, EnableCRT, MagicNumber);

    //--- Configure Notifications
    notificationManager.SetNotificationSettings(EnableEmailAlerts,
                                                EnablePushNotifications,
                                                EnableSoundAlerts);

    Print("ICT CRT Gold Trading System initialized successfully!");
    notificationManager.SendNotification("EA Started", "ICT CRT Gold EA is now active");

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("Shutting down ICT CRT Gold Trading System...");

    // FIX: Notify BEFORE deleting the object. It was called after "delete", which is an
    // invalid pointer access (runtime error every time the EA is removed or reloaded).
    if(notificationManager != NULL)
        notificationManager.SendNotification("EA Stopped", "ICT CRT Gold EA has been stopped");

    //--- Cleanup
    if(ictFunctions != NULL)        { delete ictFunctions;        ictFunctions = NULL; }
    if(crtFunctions != NULL)        { delete crtFunctions;        crtFunctions = NULL; }
    if(riskManager != NULL)         { delete riskManager;         riskManager = NULL; }
    if(signalManager != NULL)       { delete signalManager;       signalManager = NULL; }
    if(notificationManager != NULL) { delete notificationManager; notificationManager = NULL; }

    Print("Cleanup completed");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // FIX: Manage open trades and drawdown on EVERY tick and at all hours. Before, the
    // trailing stop and drawdown check ran once per bar (once an hour on H1), only inside
    // trading hours, and the drawdown value froze as soon as max drawdown was hit.
    if(UseTrailingStop)
        riskManager.UpdateTrailingStops(MagicNumber);
    riskManager.MonitorDrawdown();

    //--- New signals only once per new bar
    static datetime lastBar = 0;
    datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);

    if(currentBar == lastBar)
        return;

    lastBar = currentBar;

    //--- Reset daily trade count
    ResetDailyTradeCount();

    //--- Check trading conditions
    if(!IsTradingAllowed())
        return;

    //--- Check for new trade signals
    CheckForTradeSignals();
}

//+------------------------------------------------------------------+
//| FIX: Filling mode supported by the symbol (default FOK is        |
//| rejected by brokers that only allow IOC / Return)                |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING GetFillingMode()
{
    long modes = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
    if((modes & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) return ORDER_FILLING_FOK;
    if((modes & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) return ORDER_FILLING_IOC;
    return ORDER_FILLING_RETURN;
}

//+------------------------------------------------------------------+
//| Check for trade signals                                          |
//+------------------------------------------------------------------+
void CheckForTradeSignals()
{
    //--- Check if we can take more trades today
    if(dailyTradeCount >= MaxDailyTrades)
    {
        Print("Daily trade limit reached: ", dailyTradeCount);
        return;
    }

    //--- Check if we already have open positions
    // FIX v1.02: only THIS EA's positions (magic) count. PositionSelect(_Symbol) also
    // matched manual trades and other EAs (e.g. a DCA EA on XAUUSD), so this EA never
    // traded while any of them had a position open.
    if(HasOurPosition())
    {
        Print("Position already open for ", _Symbol, " (magic ", MagicNumber, ")");
        return;
    }

    //--- Get ICT signals
    int ictSignal = 0;
    if(EnableICT)
    {
        ictSignal = ictFunctions.GetSignal(_Symbol);
    }

    //--- Get CRT signals
    int crtSignal = 0;
    if(EnableCRT)
    {
        crtSignal = crtFunctions.GetSignal(_Symbol);
    }

    //--- Combine signals
    int finalSignal = signalManager.CombineSignals(ictSignal, crtSignal);

    //--- Execute trade based on signal
    if(finalSignal == 1) // Buy signal
    {
        ExecuteBuyTrade();
    }
    else if(finalSignal == -1) // Sell signal
    {
        ExecuteSellTrade();
    }
}

//+------------------------------------------------------------------+
//| Execute Buy Trade                                                |
//+------------------------------------------------------------------+
void ExecuteBuyTrade()
{
    double lotSize = UseAutoLot ? riskManager.CalculateLotSize(_Symbol, StopLossPoints) : LotSize;
    if(lotSize <= 0)
        return;   // FIX: risk-sized lot below broker minimum -> skip

    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double sl = riskManager.CalculateBuyStopLoss(ask, StopLossPoints);
    double tp = riskManager.CalculateBuyTakeProfit(ask, TakeProfitPoints);

    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lotSize;
    request.type = ORDER_TYPE_BUY;
    request.price = ask;
    request.sl = sl;
    request.tp = tp;
    request.deviation = 10;
    request.type_filling = GetFillingMode();   // FIX: filling mode the symbol supports
    request.magic = MagicNumber;
    request.comment = "ICT CRT Buy";

    if(OrderSend(request, result))
    {
        if(result.retcode == TRADE_RETCODE_DONE)
        {
            Print("Buy order executed successfully. Ticket: ", result.order);
            dailyTradeCount++;
            notificationManager.SendTradeNotification("BUY", _Symbol, lotSize, ask, sl, tp);
        }
        else
        {
            Print("Buy order failed. Return code: ", result.retcode);
        }
    }
}

//+------------------------------------------------------------------+
//| Execute Sell Trade                                               |
//+------------------------------------------------------------------+
void ExecuteSellTrade()
{
    double lotSize = UseAutoLot ? riskManager.CalculateLotSize(_Symbol, StopLossPoints) : LotSize;
    if(lotSize <= 0)
        return;   // FIX: risk-sized lot below broker minimum -> skip

    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double sl = riskManager.CalculateSellStopLoss(bid, StopLossPoints);
    double tp = riskManager.CalculateSellTakeProfit(bid, TakeProfitPoints);

    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lotSize;
    request.type = ORDER_TYPE_SELL;
    request.price = bid;
    request.sl = sl;
    request.tp = tp;
    request.deviation = 10;
    request.type_filling = GetFillingMode();   // FIX: filling mode the symbol supports
    request.magic = MagicNumber;
    request.comment = "ICT CRT Sell";

    if(OrderSend(request, result))
    {
        if(result.retcode == TRADE_RETCODE_DONE)
        {
            Print("Sell order executed successfully. Ticket: ", result.order);
            dailyTradeCount++;
            notificationManager.SendTradeNotification("SELL", _Symbol, lotSize, bid, sl, tp);
        }
        else
        {
            Print("Sell order failed. Return code: ", result.retcode);
        }
    }
}

//+------------------------------------------------------------------+
//| FIX v1.02: Does this EA (magic + symbol) have an open position?  |
//+------------------------------------------------------------------+
bool HasOurPosition()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Check if trading is allowed                                      |
//+------------------------------------------------------------------+
bool IsTradingAllowed()
{
    //--- Check trading hours
    if(UseTradingHours)
    {
        MqlDateTime time;
        TimeCurrent(time);

        if(time.hour < StartHour || time.hour >= EndHour)
            return false;
    }

    //--- Check trading days
    MqlDateTime time;
    TimeCurrent(time);

    switch(time.day_of_week)
    {
        case 1: if(!TradeMonday) return false; break;
        case 2: if(!TradeTuesday) return false; break;
        case 3: if(!TradeWednesday) return false; break;
        case 4: if(!TradeThursday) return false; break;
        case 5: if(!TradeFriday) return false; break;
        default: return false;
    }

    //--- Check drawdown limit
    if(!riskManager.IsDrawdownAcceptable())
        return false;

    return true;
}

//+------------------------------------------------------------------+
//| Reset daily trade count                                          |
//+------------------------------------------------------------------+
void ResetDailyTradeCount()
{
    datetime currentDate = iTime(_Symbol, PERIOD_D1, 0);

    if(currentDate != lastTradeDate)
    {
        dailyTradeCount = 0;
        lastTradeDate = currentDate;
        Print("Daily trade count reset for new day");
    }
}
