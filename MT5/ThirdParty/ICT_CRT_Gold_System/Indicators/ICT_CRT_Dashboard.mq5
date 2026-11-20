//+------------------------------------------------------------------+
//|                                         ICT_CRT_Dashboard.mq5    |
//|                                          Visual Dashboard         |
//+------------------------------------------------------------------+
#property copyright "ICT CRT Gold Trading System"
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots 0

#include <ChartObjects/ChartObjectsTxtControls.mqh>

//--- Input Parameters
input group "=== DASHBOARD SETTINGS ==="
input int      DashboardX = 20;                     // Dashboard X Position
input int      DashboardY = 30;                     // Dashboard Y Position
input color    PanelColor = clrDarkSlateGray;       // Panel Background Color
input color    TextColor = clrWhite;                // Text Color
input color    BullishColor = clrLime;              // Bullish Color
input color    BearishColor = clrRed;               // Bearish Color
input int      FontSize = 9;                        // Font Size
input string   FontName = "Arial";                  // Font Name
input bool     ShowOrderBlocks = true;              // Show Order Blocks
input bool     ShowFVG = true;                      // Show Fair Value Gaps
input bool     ShowSupplyDemand = true;             // Show Supply/Demand Zones
input bool     ShowLiquidity = true;                // Show Liquidity Levels

//--- Global Variables
string dashboardLabels[];
int totalLabels = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("Initializing ICT CRT Dashboard...");

    //--- Create dashboard
    CreateDashboard();

    Print("ICT CRT Dashboard initialized successfully!");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("Removing dashboard objects...");

    //--- Remove all dashboard objects
    for(int i = 0; i < ArraySize(dashboardLabels); i++)
    {
        ObjectDelete(0, dashboardLabels[i]);
    }

    ObjectDelete(0, "Dashboard_Panel");

    ChartRedraw();
    Print("Dashboard cleanup completed");
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    //--- Update dashboard
    UpdateDashboard();

    //--- Draw market structure
    if(ShowOrderBlocks)
        DrawOrderBlocks();

    if(ShowFVG)
        DrawFairValueGaps();

    if(ShowSupplyDemand)
        DrawSupplyDemandZones();

    if(ShowLiquidity)
        DrawLiquidityLevels();

    return(rates_total);
}

//+------------------------------------------------------------------+
//| Create Dashboard                                                 |
//+------------------------------------------------------------------+
void CreateDashboard()
{
    ArrayResize(dashboardLabels, 0);

    //--- Create background panel
    CreatePanel("Dashboard_Panel", DashboardX, DashboardY, 350, 400, PanelColor);

    int yOffset = DashboardY + 10;
    int lineHeight = 20;

    //--- Title
    CreateLabel("Dashboard_Title", DashboardX + 10, yOffset, "ICT CRT GOLD TRADING SYSTEM",
                TextColor, FontSize + 2, FontName);
    yOffset += lineHeight + 10;

    //--- Separator
    CreateLabel("Dashboard_Sep1", DashboardX + 10, yOffset, "═══════════════════════════════════",
                TextColor, FontSize, FontName);
    yOffset += lineHeight;

    //--- Market Structure Section
    CreateLabel("Dashboard_MSTitle", DashboardX + 10, yOffset, "MARKET STRUCTURE",
                TextColor, FontSize + 1, FontName);
    yOffset += lineHeight;

    CreateLabel("Dashboard_Trend", DashboardX + 20, yOffset, "Trend: Loading...",
                TextColor, FontSize, FontName);
    yOffset += lineHeight;

    CreateLabel("Dashboard_Structure", DashboardX + 20, yOffset, "Structure: Loading...",
                TextColor, FontSize, FontName);
    yOffset += lineHeight;

    CreateLabel("Dashboard_LastSwingHigh", DashboardX + 20, yOffset, "Last Swing High: -",
                TextColor, FontSize, FontName);
    yOffset += lineHeight;

    CreateLabel("Dashboard_LastSwingLow", DashboardX + 20, yOffset, "Last Swing Low: -",
                TextColor, FontSize, FontName);
    yOffset += lineHeight + 5;

    //--- ICT Section
    CreateLabel("Dashboard_ICTTitle", DashboardX + 10, yOffset, "ICT SIGNALS",
                TextColor, FontSize + 1, FontName);
    yOffset += lineHeight;

    CreateLabel("Dashboard_OrderBlocks", DashboardX + 20, yOffset, "Order Blocks: -",
                TextColor, FontSize, FontName);
    yOffset += lineHeight;

    CreateLabel("Dashboard_FVG", DashboardX + 20, yOffset, "Fair Value Gaps: -",
                TextColor, FontSize, FontName);
    yOffset += lineHeight;

    CreateLabel("Dashboard_Liquidity", DashboardX + 20, yOffset, "Liquidity Levels: -",
                TextColor, FontSize, FontName);
    yOffset += lineHeight;

    CreateLabel("Dashboard_ICTSignal", DashboardX + 20, yOffset, "ICT Signal: NEUTRAL",
                TextColor, FontSize, FontName);
    yOffset += lineHeight + 5;

    //--- CRT Section
    CreateLabel("Dashboard_CRTTitle", DashboardX + 10, yOffset, "CRT SIGNALS",
                TextColor, FontSize + 1, FontName);
    yOffset += lineHeight;

    CreateLabel("Dashboard_SupplyDemand", DashboardX + 20, yOffset, "S/D Zones: -",
                TextColor, FontSize, FontName);
    yOffset += lineHeight;

    CreateLabel("Dashboard_Trendlines", DashboardX + 20, yOffset, "Trendlines: -",
                TextColor, FontSize, FontName);
    yOffset += lineHeight;

    CreateLabel("Dashboard_Volume", DashboardX + 20, yOffset, "Volume Profile: -",
                TextColor, FontSize, FontName);
    yOffset += lineHeight;

    CreateLabel("Dashboard_CRTSignal", DashboardX + 20, yOffset, "CRT Signal: NEUTRAL",
                TextColor, FontSize, FontName);
    yOffset += lineHeight + 5;

    //--- Combined Signal Section
    CreateLabel("Dashboard_Sep2", DashboardX + 10, yOffset, "═══════════════════════════════════",
                TextColor, FontSize, FontName);
    yOffset += lineHeight;

    CreateLabel("Dashboard_FinalSignal", DashboardX + 10, yOffset, "COMBINED SIGNAL: NEUTRAL",
                TextColor, FontSize + 1, FontName);
    yOffset += lineHeight;

    CreateLabel("Dashboard_Confidence", DashboardX + 20, yOffset, "Confidence: -",
                TextColor, FontSize, FontName);
    yOffset += lineHeight + 5;

    //--- Account Info Section
    CreateLabel("Dashboard_Sep3", DashboardX + 10, yOffset, "═══════════════════════════════════",
                TextColor, FontSize, FontName);
    yOffset += lineHeight;

    CreateLabel("Dashboard_Balance", DashboardX + 10, yOffset, "Balance: -",
                TextColor, FontSize, FontName);
    yOffset += lineHeight;

    CreateLabel("Dashboard_Equity", DashboardX + 10, yOffset, "Equity: -",
                TextColor, FontSize, FontName);
    yOffset += lineHeight;

    CreateLabel("Dashboard_Profit", DashboardX + 10, yOffset, "Floating P/L: -",
                TextColor, FontSize, FontName);
    yOffset += lineHeight;

    CreateLabel("Dashboard_Drawdown", DashboardX + 10, yOffset, "Drawdown: -",
                TextColor, FontSize, FontName);

    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Update Dashboard                                                 |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
    //--- Market structure updates (placeholder - would connect to EA)
    UpdateLabel("Dashboard_Trend", "Trend: Analyzing...");
    UpdateLabel("Dashboard_Structure", "Structure: Bullish BOS");

    //--- Account info
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double profit = AccountInfoDouble(ACCOUNT_PROFIT);

    UpdateLabel("Dashboard_Balance", "Balance: " + DoubleToString(balance, 2));
    UpdateLabel("Dashboard_Equity", "Equity: " + DoubleToString(equity, 2));
    UpdateLabel("Dashboard_Profit", "Floating P/L: " + DoubleToString(profit, 2));

    //--- Current price
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    UpdateLabel("Dashboard_LastSwingHigh", "Last Swing High: " + DoubleToString(currentPrice + 1000 * _Point, _Digits));
    UpdateLabel("Dashboard_LastSwingLow", "Last Swing Low: " + DoubleToString(currentPrice - 1000 * _Point, _Digits));
}

//+------------------------------------------------------------------+
//| Create Panel                                                     |
//+------------------------------------------------------------------+
void CreatePanel(string name, int x, int y, int width, int height, color bgColor)
{
    ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
    ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
    ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
    ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, name, OBJPROP_BACK, true);
}

//+------------------------------------------------------------------+
//| Create Label                                                     |
//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, string text, color col, int size, string font)
{
    ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_COLOR, col);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
    ObjectSetString(0, name, OBJPROP_FONT, font);
    ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);

    int size_current = ArraySize(dashboardLabels);
    ArrayResize(dashboardLabels, size_current + 1);
    dashboardLabels[size_current] = name;
}

//+------------------------------------------------------------------+
//| Update Label                                                     |
//+------------------------------------------------------------------+
void UpdateLabel(string name, string text)
{
    if(ObjectFind(0, name) >= 0)
    {
        ObjectSetString(0, name, OBJPROP_TEXT, text);
    }
}

//+------------------------------------------------------------------+
//| Draw Order Blocks                                                |
//+------------------------------------------------------------------+
void DrawOrderBlocks()
{
    // Placeholder - would draw order blocks on chart
    // Implementation would scan for order blocks and draw rectangles
}

//+------------------------------------------------------------------+
//| Draw Fair Value Gaps                                            |
//+------------------------------------------------------------------+
void DrawFairValueGaps()
{
    // Placeholder - would draw FVG zones on chart
    // Implementation would identify and highlight FVG areas
}

//+------------------------------------------------------------------+
//| Draw Supply/Demand Zones                                        |
//+------------------------------------------------------------------+
void DrawSupplyDemandZones()
{
    // Placeholder - would draw supply/demand zones
    // Implementation would identify and draw SD zones
}

//+------------------------------------------------------------------+
//| Draw Liquidity Levels                                           |
//+------------------------------------------------------------------+
void DrawLiquidityLevels()
{
    // Placeholder - would draw liquidity levels
    // Implementation would mark equal highs/lows
}

//+------------------------------------------------------------------+
//| Chart Event Handler                                             |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
    // Handle chart events if needed
}
