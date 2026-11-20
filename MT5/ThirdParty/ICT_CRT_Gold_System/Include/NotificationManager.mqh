//+------------------------------------------------------------------+
//|                                      NotificationManager.mqh     |
//|                              Alerts & Notifications Functions    |
//+------------------------------------------------------------------+
#property copyright "ICT CRT Gold Trading System"
#property strict

//+------------------------------------------------------------------+
//| Notification Manager Class                                       |
//+------------------------------------------------------------------+
class CNotificationManager
{
private:
    bool    m_enableEmail;
    bool    m_enablePush;
    bool    m_enableSound;

    string  m_lastNotification;
    datetime m_lastNotificationTime;

    int     m_notificationCooldown; // seconds between similar notifications

public:
    //--- Constructor
    CNotificationManager()
    {
        m_enableEmail = false;
        m_enablePush = true;
        m_enableSound = true;
        m_lastNotification = "";
        m_lastNotificationTime = 0;
        m_notificationCooldown = 60; // 1 minute cooldown
    }

    //--- Destructor
    ~CNotificationManager() {}

    //+------------------------------------------------------------------+
    //| Set Notification Settings                                        |
    //+------------------------------------------------------------------+
    void SetNotificationSettings(bool enableEmail, bool enablePush, bool enableSound)
    {
        m_enableEmail = enableEmail;
        m_enablePush = enablePush;
        m_enableSound = enableSound;

        Print("Notifications configured: Email=", m_enableEmail,
              " Push=", m_enablePush, " Sound=", m_enableSound);
    }

    //+------------------------------------------------------------------+
    //| Send General Notification                                        |
    //+------------------------------------------------------------------+
    void SendNotification(string title, string message)
    {
        // Check cooldown
        if(!CheckCooldown(message))
            return;

        string fullMessage = title + ": " + message;

        Print(fullMessage);

        // Send push notification
        if(m_enablePush)
        {
            // FIX: "::" calls MT5's built-in SendNotification(). Without it the call
            // resolves to this class's own 2-parameter method -> compile error.
            if(::SendNotification(fullMessage))
            {
                Print("Push notification sent successfully");
            }
            else
            {
                Print("Failed to send push notification");
            }
        }

        // Send email
        if(m_enableEmail)
        {
            string subject = "ICT CRT EA - " + title;
            if(SendMail(subject, message))
            {
                Print("Email notification sent successfully");
            }
            else
            {
                Print("Failed to send email notification");
            }
        }

        // Play sound
        if(m_enableSound)
        {
            PlaySound("alert.wav");
        }

        // Update last notification
        m_lastNotification = message;
        m_lastNotificationTime = TimeCurrent();
    }

    //+------------------------------------------------------------------+
    //| Send Trade Notification                                         |
    //+------------------------------------------------------------------+
    void SendTradeNotification(string tradeType, string symbol, double lots,
                              double price, double sl, double tp)
    {
        string message = StringFormat(
            "%s trade executed on %s\nLot Size: %.2f\nEntry: %.5f\nSL: %.5f\nTP: %.5f",
            tradeType, symbol, lots, price, sl, tp
        );

        SendNotification("Trade Executed", message);

        // Play specific sound for trades
        if(m_enableSound)
        {
            if(tradeType == "BUY")
                PlaySound("trade_open.wav");
            else
                PlaySound("trade_open.wav");
        }
    }

    //+------------------------------------------------------------------+
    //| Send Signal Alert                                               |
    //+------------------------------------------------------------------+
    void SendSignalAlert(string signalType, string source, double confidence)
    {
        string message = StringFormat(
            "%s signal detected\nSource: %s\nConfidence: %.1f%%\nSymbol: %s",
            signalType, source, confidence, _Symbol
        );

        SendNotification("Trading Signal", message);

        // Play signal sound
        if(m_enableSound)
        {
            PlaySound("signal.wav");
        }
    }

    //+------------------------------------------------------------------+
    //| Send Order Execution Alert                                      |
    //+------------------------------------------------------------------+
    void SendOrderExecutionAlert(bool success, string orderType, ulong ticket)
    {
        string status = success ? "SUCCESS" : "FAILED";
        string message = StringFormat(
            "Order %s\nType: %s\nTicket: %I64u\nSymbol: %s",
            status, orderType, ticket, _Symbol
        );

        SendNotification("Order Status", message);

        if(m_enableSound)
        {
            if(success)
                PlaySound("ok.wav");
            else
                PlaySound("timeout.wav");
        }
    }

    //+------------------------------------------------------------------+
    //| Send Position Closed Alert                                      |
    //+------------------------------------------------------------------+
    void SendPositionClosedAlert(string closeReason, double profit, ulong ticket)
    {
        string profitStr = profit >= 0 ? "Profit" : "Loss";
        string message = StringFormat(
            "Position closed\nReason: %s\n%s: %.2f\nTicket: %I64u",
            closeReason, profitStr, MathAbs(profit), ticket
        );

        SendNotification("Position Closed", message);

        if(m_enableSound)
        {
            if(profit >= 0)
                PlaySound("ok.wav");
            else
                PlaySound("timeout.wav");
        }
    }

    //+------------------------------------------------------------------+
    //| Send Risk Alert                                                 |
    //+------------------------------------------------------------------+
    void SendRiskAlert(string riskType, string details)
    {
        string message = StringFormat(
            "RISK ALERT: %s\nDetails: %s\nSymbol: %s\nTime: %s",
            riskType, details, _Symbol, TimeToString(TimeCurrent())
        );

        SendNotification("Risk Warning", message);

        // Force send even with cooldown for risk alerts
        m_lastNotificationTime = 0;

        if(m_enableSound)
        {
            PlaySound("alert2.wav");
        }
    }

    //+------------------------------------------------------------------+
    //| Send Drawdown Alert                                             |
    //+------------------------------------------------------------------+
    void SendDrawdownAlert(double currentDD, double maxDD)
    {
        string message = StringFormat(
            "Drawdown Alert\nCurrent Drawdown: %.2f%%\nMax Allowed: %.2f%%\nAction: Trading paused",
            currentDD, maxDD
        );

        SendNotification("Drawdown Warning", message);

        if(m_enableSound)
        {
            PlaySound("alert2.wav");
        }
    }

    //+------------------------------------------------------------------+
    //| Send Daily Summary                                              |
    //+------------------------------------------------------------------+
    void SendDailySummary(int totalTrades, int winTrades, int lossTrades,
                         double totalProfit, double winRate)
    {
        string message = StringFormat(
            "Daily Trading Summary\nTotal Trades: %d\nWins: %d | Losses: %d\nWin Rate: %.1f%%\nTotal P/L: %.2f",
            totalTrades, winTrades, lossTrades, winRate, totalProfit
        );

        SendNotification("Daily Summary", message);
    }

    //+------------------------------------------------------------------+
    //| Send Error Alert                                                |
    //+------------------------------------------------------------------+
    void SendErrorAlert(int errorCode, string errorDescription)
    {
        string message = StringFormat(
            "Error Occurred\nCode: %d\nDescription: %s\nSymbol: %s",
            errorCode, errorDescription, _Symbol
        );

        SendNotification("Error Alert", message);

        if(m_enableSound)
        {
            PlaySound("stops.wav");
        }
    }

    //+------------------------------------------------------------------+
    //| Check Notification Cooldown                                     |
    //+------------------------------------------------------------------+
    bool CheckCooldown(string message)
    {
        // Always allow different messages
        if(message != m_lastNotification)
            return true;

        // Check time since last identical notification
        datetime currentTime = TimeCurrent();
        if((currentTime - m_lastNotificationTime) < m_notificationCooldown)
        {
            return false;
        }

        return true;
    }

    //+------------------------------------------------------------------+
    //| Set Cooldown Period                                             |
    //+------------------------------------------------------------------+
    void SetCooldownPeriod(int seconds)
    {
        m_notificationCooldown = seconds;
        Print("Notification cooldown set to ", seconds, " seconds");
    }

    //+------------------------------------------------------------------+
    //| Play Custom Sound                                               |
    //+------------------------------------------------------------------+
    void PlayCustomSound(string soundFile)
    {
        if(m_enableSound)
        {
            PlaySound(soundFile);
        }
    }

    //+------------------------------------------------------------------+
    //| Send Market Condition Alert                                     |
    //+------------------------------------------------------------------+
    void SendMarketConditionAlert(string condition, string description)
    {
        string message = StringFormat(
            "Market Condition Update\nCondition: %s\nDetails: %s\nSymbol: %s",
            condition, description, _Symbol
        );

        SendNotification("Market Update", message);
    }

    //+------------------------------------------------------------------+
    //| Send Startup Notification                                       |
    //+------------------------------------------------------------------+
    void SendStartupNotification()
    {
        string message = StringFormat(
            "EA Started Successfully\nSymbol: %s\nTimeframe: %s\nAccount: %I64u",
            _Symbol, EnumToString(_Period), AccountInfoInteger(ACCOUNT_LOGIN)
        );

        SendNotification("EA Started", message);
    }

    //+------------------------------------------------------------------+
    //| Send Shutdown Notification                                      |
    //+------------------------------------------------------------------+
    void SendShutdownNotification(string reason)
    {
        string message = StringFormat(
            "EA Stopped\nReason: %s\nSymbol: %s\nTime: %s",
            reason, _Symbol, TimeToString(TimeCurrent())
        );

        SendNotification("EA Stopped", message);
    }

    //+------------------------------------------------------------------+
    //| Test Notifications                                              |
    //+------------------------------------------------------------------+
    void TestNotifications()
    {
        Print("Testing notification systems...");

        if(m_enablePush)
        {
            SendNotification("ICT CRT EA - Test Notification");
            Print("Push notification test sent");
        }

        if(m_enableEmail)
        {
            SendMail("ICT CRT EA - Test Email", "This is a test email from your trading EA.");
            Print("Email test sent");
        }

        if(m_enableSound)
        {
            PlaySound("alert.wav");
            Print("Sound alert played");
        }
    }
};
